# Plan: workspace-bootstrap

Goal (from `goals`): one command that sets up a macOS or Debian/Ubuntu workstation with zsh +
Oh My Zsh, vim, Go, Python, Node, git, curl and Docker. Everything lives in
https://github.com/lneves75/workspace-bootstrap.

## Decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Docker on macOS | **colima** + docker CLI (no Docker Desktop) |
| 2 | Language versions | **mise** manages Go, Python and Node |
| 3 | Supported OS | macOS, Debian and Ubuntu only. Anything else **stops with an "unsupported OS" message** |
| 4 | Vim | **minimal** vimrc, no plugins |
| 5 | Versioning | The default URL installs the **latest release**. A **tag in the URL** pins that release, and every later step uses that same version |
| 6 | Idempotency | Every module checks each item (zsh, plugins, packages, config) and acts only on what is missing. A second run changes nothing, and the tests check this |
| 7 | Optional modules | `mise` (languages) and `docker` prompt with **default No**. `--unattended` skips them unless `--with` names them. Already set up means no prompt |
| 8 | Remote | `github.com/lneves75/workspace-bootstrap` is created **private**. It must become public before the curl one-liner can work |
| 9 | Language versions | The latest stable releases, pinned exactly: Go 1.27.4, Python 3.15.2, Node 26.13.1 (2026-11-26) |

## 1. User experience

```sh
# Latest release
sh -c "$(curl -fsSL https://raw.githubusercontent.com/lneves75/workspace-bootstrap/main/install.sh)"

# Pinned release: the tag in the URL selects the version for every step
sh -c "$(curl -fsSL https://raw.githubusercontent.com/lneves75/workspace-bootstrap/v0.1.0/install.sh)"

# wget works too (minimal Debian images may not have curl)
sh -c "$(wget -qO- https://raw.githubusercontent.com/lneves75/workspace-bootstrap/main/install.sh)"

# Options
sh -c "$(curl -fsSL …/install.sh)" "" --unattended --skip docker
```

To re-run later: `~/.workspace-bootstrap/bootstrap.sh`. To upgrade to a newer release: `bootstrap.sh --upgrade`.

## 2. How versions are resolved (decision 5)

A script started with `sh -c "$(curl …)"` cannot see the URL it came from. So the version is
**written into `install.sh` when a release is made**:

- On `main`, `install.sh` contains `WSB_PINNED_REF=""`.
- `scripts/release.sh v0.1.0` creates a release commit that sets `WSB_PINNED_REF="v0.1.0"`, tags it
  `v0.1.0`, pushes the tag, and then sets the line back to `""` on `main`. The tag therefore points
  at an `install.sh` that already knows its own version.

How `install.sh` picks the version, in priority order:
1. `WSB_REF` environment variable, if set. This is an escape hatch, e.g. `WSB_REF=main` for unreleased work.
2. `WSB_PINNED_REF`, which is non-empty only when the script was fetched from a tag URL.
3. Otherwise, the latest release tag, from `git ls-remote --tags --sort=-v:refname`, keeping only semver tags.
4. If there are no releases yet, `main`, with a warning.

**Every later step uses that version:**
- The repo is checked out at that tag (shallow fetch of exactly that ref). `bootstrap.sh`, its modules, `config/` and the package lists all come from that tag.
- The selected version is saved to `~/.workspace-bootstrap/.version`, and `bootstrap.sh` refuses to run if what is checked out differs from it.
- Third-party versions are pinned inside the repo, so a given tag installs the same tools every time:
  - The mise config sets exact Go, Python and Node versions.
  - The Oh My Zsh install script is fetched at a pinned commit.
  - Oh My Zsh plugins are cloned at pinned commits.
  - Homebrew and apt packages cannot be pinned this way. They install the current versions from the package manager, which is acceptable for git, curl, zsh and vim.

## 3. Two-stage design

**Stage 0: `install.sh`** (POSIX `sh`, kept small)
1. Detect the OS. Only macOS, Debian and Ubuntu continue; anything else prints an "unsupported OS" message and exits with code 1.
2. Make sure git and curl are installed:
   - macOS: `xcode-select --install`, then wait until the tools are ready.
   - Debian/Ubuntu: `sudo apt-get install -y git curl ca-certificates`.
3. Work out the version (§2), clone into `$BOOTSTRAP_DIR` (default `~/.workspace-bootstrap`), and write `.version`.
4. `exec "$BOOTSTRAP_DIR/bootstrap.sh" "$@"`

**Stage 1: `bootstrap.sh`** (bash) runs the modules in order. Every module checks first and then installs, so re-running is safe.

## 4. Repository layout

```
workspace-bootstrap/
├── install.sh                # stage 0, holds WSB_PINNED_REF
├── bootstrap.sh              # stage 1 (--with, --only, --skip, --unattended, --dry-run, --upgrade)
├── lib/
│   ├── common.sh             # logging, OS/arch detection, prompts, lazy sudo, mark_changed
│   ├── pkg.sh                # pkg_ensure (idempotent) → brew (macOS) | apt (Debian/Ubuntu)
│   └── files.sh              # link_file (with backup), git_pinned_checkout
├── modules/
│   ├── 00-package-manager.sh # Homebrew on macOS, apt update on Debian/Ubuntu
│   ├── 10-base-tools.sh      # git, curl, wget, unzip, jq, build tools
│   ├── 20-git.sh             # gitconfig, global gitignore, name/email prompt
│   ├── 30-zsh.sh             # zsh, Oh My Zsh (pinned), plugins, chsh
│   ├── 40-vim.sh             # vim + minimal vimrc
│   ├── 50-mise.sh            # optional: mise + `mise install` (Go, Python, Node)
│   └── 60-docker.sh          # optional: colima (macOS) | docker-ce (Debian/Ubuntu)
├── packages/
│   ├── base.brew             # one formula per line ("cask:" prefix for casks)
│   └── base.apt
├── config/                   # all shared configuration, one folder per tool
│   ├── zsh/
│   │   ├── zshrc             # → ~/.zshrc; loader only
│   │   ├── env.zsh           # PATH, Homebrew, EDITOR
│   │   ├── omz.zsh           # theme + plugin list, loads Oh My Zsh
│   │   ├── options.zsh       # setopt, history
│   │   ├── external-plugins.txt  # name, repo, pinned commit
│   │   ├── plugins/<plugin>.zsh  # per-plugin settings
│   │   ├── aliases/*.zsh     # aliases by topic
│   │   ├── functions/*.zsh   # shell functions by topic
│   │   └── README.md         # load order, how to add things
│   ├── vim/vimrc             # → ~/.vimrc
│   ├── git/                  # gitconfig (included by ~/.gitconfig), ignore (→ ~/.config/git/ignore)
│   └── mise/workspace-bootstrap.toml  # [tools] go, python, node, copied to ~/.config/mise/conf.d/
├── versions.env              # pinned Oh My Zsh commit (later: mise version)
├── scripts/
│   ├── release.sh            # creates the release commit with the version written in, tags, resets main
│   ├── doctor.sh             # checks installed versions against the pins
│   └── uninstall.sh
├── tests/
│   ├── run.sh                # builds a throwaway remote with 2 releases, runs container.sh per image
│   └── container.sh          # scenarios run inside each container
├── .github/workflows/ci.yml  # shellcheck + ubuntu, debian container, macos runners; tag-pin test
├── docs/
└── README.md
```

## 5. Per-OS components

| Component | macOS | Debian/Ubuntu |
|---|---|---|
| git, curl, zsh, vim, jq | brew | apt |
| mise | `brew install mise` | mise's official apt repo (`mise.jdx.dev/deb`) |
| Go, Python, Node | `mise install` of the pins in `config/mise/workspace-bootstrap.toml`, a **managed copy** in `~/.config/mise/conf.d/`. It is not a symlink, because `mise use -g` rewrites the file that defines a tool. `~/.config/mise/config.toml` stays personal and overrides it | same |
| Docker | `brew install colima docker docker-compose docker-buildx`, link the Compose/Buildx plugins into Docker's CLI plugin folder, run `colima start` (skipped with `--unattended`) | Docker's official apt repo: `docker-ce`, `docker-ce-cli`, `containerd.io`, compose/buildx plugins. Adds the user to the `docker` group |

Python comes from mise's precompiled builds, so nothing needs compiling. `pipx` and `uv` can
also be listed as tools in `mise.toml`.

## 6. Configuration

- All shared configuration lives in `config/<tool>/`. The entry files are symlinked into `$HOME`.
  Anything already there is moved to `~/.workspace-bootstrap-backup/<timestamp>/` first.
- Personal files live only on the machine and are never touched:
  - zsh: `~/.zshrc.pre.local`, `~/.zshrc.d/*.zsh`, `~/.zshrc.local`
  - vim: `~/.vimrc.local`
  - git: `~/.gitconfig` itself. It is **not** symlinked, because `git config --global` writes to
    it. One `[include]` of `config/git/gitconfig` is added at its top, so personal values
    override the shared ones.
- **zsh** (see `config/zsh/README.md`):
  - Load order: `env.zsh` → `~/.zshrc.pre.local` → `plugins/*.zsh` → `omz.zsh` → `options.zsh`
    → `functions/*.zsh` → `aliases/*.zsh` → `~/.zshrc.d/*.zsh` → `~/.zshrc.local`.
  - Oh My Zsh and the external plugins are cloned by us at pinned commits; its installer script is
    not used, and its auto-updater is disabled.
  - A checkout found on a branch was installed some other way. It is reported and left alone.
  - Plugins: git, colored-man-pages, docker, docker-compose, golang, python, node, npm, mise,
    `$WSB_EXTRA_PLUGINS`, zsh-autosuggestions, zsh-syntax-highlighting (last). Plugins that
    aren't installed are dropped, so startup never fails because of one.
  - The login shell is changed with `chsh` through sudo. `WSB_NO_CHSH=1` skips it.
- **vim**: the system vim on macOS, apt on Debian/Ubuntu. `~/.vimrc` → `config/vim/vimrc`: built-in
  features only, with line numbers, search settings, 2-space indent plus Go/Python/Make
  conventions, swap/backup/undo files in `~/.vim/`, and `~/.vimrc.local` sourced last.
- **git**: shared defaults (aliases; `pull.ff=only`, `push.autoSetupRemote`, `fetch.prune`,
  `rebase.autoStash`, `diff3`, `rerere`). `~/.config/git/ignore` → `config/git/ignore`, unless
  `core.excludesFile` is already set. `user.name` and `user.email` are asked for when missing.
  With `--unattended` they come from `WSB_GIT_NAME` / `WSB_GIT_EMAIL`, or are left unset with a
  warning.

## 7. Cross-cutting rules

- Idempotent at item level. Modules call `mark_changed` for every real change, so the summary
  says *changed* or *already set up*.
- `--unattended` never prompts, for CI and containers. Optional modules are then skipped unless
  `--with` names them.
- sudo is requested **lazily**, the first time a step needs root, and kept alive for the rest of the run. A re-run with nothing to do never asks for a password.
- `set -euo pipefail`, clear `==>` / `✔` / `✖` log lines, and a summary at the end.
- Detect arm64/x86_64, which sets the Homebrew prefix and Docker's apt arch.
- All scripts must pass shellcheck.

## 8. Milestones

1. ✅ **Skeleton + versioning**: `install.sh` (OS check that stops on unsupported systems, git/curl, version resolution, clone, `.version`), `bootstrap.sh` with empty modules, `lib/common.sh`, `scripts/release.sh`. Test in Ubuntu and Debian containers, and on a Fedora container to confirm it stops with the unsupported message.
2. ✅ **Package layer**: `pkg.sh`, Homebrew, `packages/base.{brew,apt}`, base tools, idempotency and optional-module framework.
3. ✅ **Shell**: zsh, pinned Oh My Zsh and plugins, `config/zsh/` tree (plugins, aliases, functions, options), personal override files, chsh, lazy sudo.
4. ✅ **Vim and git**: minimal vimrc, shared gitconfig through an include, global gitignore, identity prompt (`WSB_GIT_NAME`/`WSB_GIT_EMAIL` for unattended runs).
5. ✅ **mise and languages**: mise (brew / mise apt repo), managed-copy config, `mise install` of the latest stable Go/Python/Node, activation through the Oh My Zsh `mise` plugin.
6. **Docker**: colima on macOS, docker-ce on Debian/Ubuntu.
7. **Quality**: `doctor.sh`, `uninstall.sh`, CI matrix, plus a CI job that tags a test release and confirms the tag URL installs exactly that version.
8. **Release**: `scripts/release.sh v0.1.0`, and the README with both one-liners.
