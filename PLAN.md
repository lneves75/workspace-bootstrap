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
- The repo is cloned at that tag (`git clone --branch <tag> --depth 1`). `bootstrap.sh`, its modules, the dotfiles and the package lists all come from that tag.
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
├── bootstrap.sh              # stage 1 (--only, --skip, --unattended, --dry-run, --upgrade)
├── lib/
│   ├── common.sh             # logging, OS/arch detection, unsupported-OS exit, sudo keep-alive
│   └── pkg.sh                # pkg_install → brew (macOS) | apt (Debian/Ubuntu)
├── modules/
│   ├── 00-package-manager.sh # Homebrew on macOS, apt update on Debian/Ubuntu
│   ├── 10-base-tools.sh      # git, curl, wget, unzip, jq, build tools
│   ├── 20-git.sh             # gitconfig, global gitignore, name/email prompt
│   ├── 30-zsh.sh             # zsh, Oh My Zsh (pinned), plugins, chsh
│   ├── 40-vim.sh             # vim + minimal vimrc
│   ├── 50-mise.sh            # mise + `mise install` (Go, Python, Node)
│   └── 60-docker.sh          # colima (macOS) | docker-ce (Debian/Ubuntu)
├── packages/
│   ├── Brewfile
│   └── apt.txt
├── config/
│   └── mise.toml             # [tools] go = "x.y.z", python = "x.y.z", node = "x.y.z"
├── dotfiles/
│   ├── zshrc  vimrc  gitconfig  gitignore_global
├── versions.env              # pinned Oh My Zsh / plugin commits, mise version
├── scripts/
│   ├── release.sh            # creates the release commit with the version written in, tags, resets main
│   ├── doctor.sh             # checks installed versions against the pins
│   └── uninstall.sh
├── tests/
│   ├── Dockerfile.ubuntu
│   └── Dockerfile.debian
├── .github/workflows/ci.yml  # shellcheck + ubuntu, debian container, macos runners; tag-pin test
├── docs/
└── README.md
```

## 5. Per-OS components

| Component | macOS | Debian/Ubuntu |
|---|---|---|
| git, curl, zsh, vim, jq | brew | apt |
| mise | `brew install mise` | mise's official apt repo (`mise.jdx.dev/deb`) |
| Go, Python, Node | `mise install` from `~/.config/mise/config.toml`, which is linked to `config/mise.toml` | same |
| Docker | `brew install colima docker docker-compose docker-buildx`, link the Compose/Buildx plugins into Docker's CLI plugin folder, run `colima start` (skipped with `--unattended`) | Docker's official apt repo: `docker-ce`, `docker-ce-cli`, `containerd.io`, compose/buildx plugins. Adds the user to the `docker` group |

Python comes from mise's precompiled builds, so nothing needs compiling. `pipx` and `uv` can
also be listed as tools in `mise.toml`.

## 6. Configuration and dotfiles

- Dotfiles are symlinked from the clone into `$HOME`. Existing files are backed up to `~/.workspace-bootstrap-backup/<timestamp>/`.
- Per-machine overrides go in `~/.zshrc.local`, `~/.vimrc.local` and `~/.gitconfig.local`. They are sourced or included, never overwritten.
- Oh My Zsh is installed with `RUNZSH=no CHSH=no KEEP_ZSHRC=yes --unattended`. We run `chsh` ourselves afterwards.
- Oh My Zsh plugins: `git`, `docker`, `golang`, `python`, `node`, `mise`, plus `zsh-autosuggestions` and `zsh-syntax-highlighting` (both pinned).
- zshrc contents, in order:
  1. Homebrew shellenv (macOS only)
  2. `eval "$(mise activate zsh)"`
  3. `~/.local/bin` added to PATH
  4. `~/.zshrc.local` sourced
- vimrc (minimal): syntax on, line numbers, sensible indentation, search settings, no swap files in the working directory, and `~/.vimrc.local` sourced if present.

## 7. Cross-cutting rules

- Idempotent. `--unattended` never prompts, for CI and containers.
- Ask for sudo once at the start and keep it alive during the run.
- `set -euo pipefail`, clear `==>` / `✔` / `✖` log lines, and a summary at the end.
- Detect arm64/x86_64, which sets the Homebrew prefix and Docker's apt arch.
- All scripts must pass shellcheck.

## 8. Milestones

1. **Skeleton + versioning**: `install.sh` (OS check that stops on unsupported systems, git/curl, version resolution, clone, `.version`), `bootstrap.sh` with empty modules, `lib/common.sh`, `scripts/release.sh`. Test in Ubuntu and Debian containers, and on a Fedora container to confirm it stops with the unsupported message.
2. **Package layer**: `pkg.sh`, Homebrew, Brewfile, apt.txt, base tools.
3. **Shell**: zsh, pinned Oh My Zsh and plugins, zshrc, chsh.
4. **Vim and git**: minimal vimrc, gitconfig, global gitignore.
5. **mise and languages**: install mise, `config/mise.toml`, `mise install`, version checks.
6. **Docker**: colima on macOS, docker-ce on Debian/Ubuntu.
7. **Quality**: `doctor.sh`, `uninstall.sh`, CI matrix, plus a CI job that tags a test release and confirms the tag URL installs exactly that version.
8. **Release**: `scripts/release.sh v0.1.0`, and the README with both one-liners.
