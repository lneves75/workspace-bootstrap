# workspace-bootstrap

One command to set up a development workstation on **macOS**, **Debian** or **Ubuntu**:
zsh + Oh My Zsh, vim, git, curl, Docker, and Go / Python / Node managed by
[mise](https://mise.jdx.dev).

> **Status:** milestone 4 of 8. Everything except the optional mise (languages) and Docker
> modules works; those two are still stubs.
> See [PLAN.md](PLAN.md).

## Install

Latest release:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/lneves75/workspace-bootstrap/main/install.sh)"
```

A specific release: put the tag in the URL. Every later step uses that version.

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/lneves75/workspace-bootstrap/v0.1.0/install.sh)"
```

No curl yet (minimal Debian/Ubuntu)? Use wget:

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/lneves75/workspace-bootstrap/main/install.sh)"
```

Pass options after an empty `""`:

```sh
sh -c "$(curl -fsSL …/install.sh)" "" --unattended --skip docker
```

Any other OS stops with an "Unsupported OS" message before changing anything.

## What happens

1. **`install.sh`** (POSIX sh) checks the platform. It installs git and curl: the Xcode Command
   Line Tools on macOS, or apt on Debian/Ubuntu. It then picks the version and checks it out into
   `~/.workspace-bootstrap`.
2. **`bootstrap.sh`** runs the modules in `modules/` in order and stops at the first failure.
   The summary shows each module as *changed*, *already set up*, *optional, not installed* or
   *failed*.

**Idempotent:** every module checks each item (package, plugin, config) before acting and only
installs what is missing. A second run on the same machine changes nothing and reports every
module as "already set up". The tests check this.

**Optional modules** (`mise` for Go/Python/Node, and `docker`) are asked about
interactively with **default No**. If a module is already set up, you aren't asked.
With `--unattended` they are skipped unless you name them with `--with`:

```sh
~/.workspace-bootstrap/bootstrap.sh --unattended --with mise,docker
```

| Module | macOS | Debian / Ubuntu |
|---|---|---|
| package-manager | Homebrew | apt |
| base-tools | `packages/base.brew` | `packages/base.apt` |
| git | `~/.gitconfig` includes `config/git/gitconfig`, global gitignore, name/email | same |
| zsh | zsh, Oh My Zsh + plugins (pinned), `~/.zshrc` → `config/zsh/zshrc`, login shell | same |
| vim | system vim + `~/.vimrc` → `config/vim/vimrc` | vim (apt) + same |
| mise *(optional)* | mise → Go, Python, Node (pinned in `config/mise/config.toml`) | same |
| docker *(optional)* | colima + docker CLI | docker-ce (official apt repo) |

## Configuration

Everything shared lives in [`config/`](config), one folder per tool. Entry files are symlinked
into your home directory, so `wsb --upgrade` updates them. Anything already there is moved to
`~/.workspace-bootstrap-backup/<timestamp>/` first.

```
config/zsh/
├── zshrc                  → ~/.zshrc (loader only)
├── env.zsh                PATH, Homebrew, EDITOR
├── omz.zsh                Oh My Zsh theme and plugin list
├── options.zsh            setopt, history
├── external-plugins.txt   non-bundled plugins, pinned to a commit
├── plugins/<plugin>.zsh   settings for each plugin
├── aliases/*.zsh          aliases, one file per topic
└── functions/*.zsh        shell functions, one file per topic
```

```
config/vim/vimrc           → ~/.vimrc (minimal, no plugins)
config/git/gitconfig       included at the top of ~/.gitconfig (aliases, pull/push defaults)
config/git/ignore          → ~/.config/git/ignore (global gitignore)
```

Personal, per-machine settings never go in the repo, and workspace-bootstrap never edits them:

| Tool | Personal files |
|---|---|
| zsh | `~/.zshrc.pre.local` (before Oh My Zsh, e.g. `WSB_EXTRA_PLUGINS=(kubectl)`), `~/.zshrc.d/*.zsh`, `~/.zshrc.local` (last) |
| vim | `~/.vimrc.local` |
| git | `~/.gitconfig` itself. It is not a symlink: it holds your name and email, and its settings override the shared ones |

The folder READMEs ([zsh](config/zsh/README.md), [vim](config/vim/README.md),
[git](config/git/README.md)) explain the load order and how to add things. The only change made
to an existing `~/.gitconfig` is a single `[include]` added at the top. A copy of the original
goes to the backup folder first.

## Versions

How the version is chosen, highest priority first:

1. the `WSB_REF` environment variable: a tag, a branch, or `latest`
2. the version written into `install.sh` when it was fetched from a tag URL
3. the latest `vX.Y.Z` release tag
4. `main`, with a warning, if there are no releases yet

The chosen ref and commit are saved to `~/.workspace-bootstrap/.version`. `bootstrap.sh` refuses
to run if the checked-out code no longer matches it.

```sh
~/.workspace-bootstrap/bootstrap.sh                   # re-run the installed version
~/.workspace-bootstrap/bootstrap.sh --upgrade         # move to the latest release
~/.workspace-bootstrap/bootstrap.sh --upgrade=v0.2.0  # move to a specific release
```

## Options

```
--with LIST       install these optional modules without asking
--only LIST       run only these modules (comma separated; implies --with)
--skip LIST       skip these modules
--unattended      never prompt; optional modules skipped unless --with
                  (anything needing root then requires passwordless sudo)
--dry-run         show what would be done, change nothing
--upgrade[=REF]   switch version, then re-run
--list            list modules
```

Environment: `WSB_REF`, `WSB_REPO` (clone URL), `BOOTSTRAP_DIR` (default `~/.workspace-bootstrap`),
`WSB_UNATTENDED=1`, `WSB_WITH=mise,docker`, `WSB_NO_CHSH=1` (don't change the login shell),
`WSB_GIT_NAME` / `WSB_GIT_EMAIL` (git identity without prompting).

sudo is only requested when a step needs root, so a re-run with nothing to do never asks for a
password.

## Development

```sh
tests/run.sh                 # end-to-end tests in ubuntu:24.04, ubuntu:22.04, debian:12, fedora:41
tests/run.sh debian:12       # a single image
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable -x \
  install.sh bootstrap.sh lib/*.sh modules/*.sh scripts/*.sh tests/*.sh
```

Scripts must stay compatible with **bash 3.2**, the macOS system bash. That means no associative
arrays and no `mapfile`, and empty arrays must be expanded as `${a[@]+"${a[@]}"}`.

### Writing a module

`modules/NN-name.sh` is sourced in a subshell with `lib/common.sh` and `lib/pkg.sh` already
loaded, and Homebrew is already on PATH. It defines:

- `module_install` (required): it must be idempotent. Check every item, act only on what is
  missing, and call `mark_changed "what changed"` for each real change. Use `run` for anything
  that changes the system so `--dry-run` works. Return 0 on success, or `$WSB_RC_TODO` if not
  implemented yet.
- `module_check` (optional): return 0 if everything is already in place. For an optional module,
  this skips the prompt.
- `MODULE_OPTIONAL=1` and `MODULE_PROMPT="Install …?"`: mark the module as optional.

Helpers:
- packages: `pkg_ensure NAME…`, `pkg_ensure_list base` (reads `packages/base.<brew|apt>`),
  `pkg_installed`, `pkg_apt_refresh`
- files: `link_file SRC DEST` (symlink, backing up what was there),
  `git_pinned_checkout NAME DIR URL COMMIT` (leaves checkouts it didn't make alone)
- platform and privileges: `is_macos`, `is_debian`, `as_root`
- prompts: `ask_yes_no "Question?" n`, `value=$(ask_value "Question:")`
- logging: `log_info`, `log_ok`, `log_warn`, `log_err`

Package list files hold one name per line and allow `#` comments. Prefix Homebrew casks with
`cask:`.

### Releasing

```sh
scripts/release.sh v0.1.0 --push
```

This creates a `release v0.1.0` commit in which `install.sh` contains `WSB_PINNED_REF="v0.1.0"`,
and tags that commit. It then adds a second commit that resets the pin on `main`. That is how a
tag URL knows its own version.
