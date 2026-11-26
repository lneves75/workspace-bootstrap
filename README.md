# workspace-bootstrap

One command to set up a development workstation on **macOS**, **Debian** or **Ubuntu**:
zsh + Oh My Zsh, vim, git, curl, Docker, and Go / Python / Node managed by
[mise](https://mise.jdx.dev).

> **Status:** milestone 1 of 8. The installer, versioning and module runner work;
> the modules themselves are still stubs. See [PLAN.md](PLAN.md).

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
2. **`bootstrap.sh`** runs the modules in `modules/` in order. Each one checks before it installs,
   so re-running is safe. It stops at the first failure and prints a summary.

| Module | macOS | Debian / Ubuntu |
|---|---|---|
| package-manager | Homebrew | apt |
| base-tools | brew | apt |
| git | gitconfig, global gitignore | same |
| zsh | zsh + Oh My Zsh (pinned) + plugins | same |
| vim | vim + minimal vimrc | same |
| mise | mise → Go, Python, Node (pinned in `config/mise.toml`) | same |
| docker | colima + docker CLI | docker-ce (official apt repo) |

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
--only LIST       run only these modules (comma separated)
--skip LIST       skip these modules
--unattended      never prompt (needs root or passwordless sudo)
--dry-run         show what would be done, change nothing
--upgrade[=REF]   switch version, then re-run
--list            list modules
```

Environment: `WSB_REF`, `WSB_REPO` (clone URL), `BOOTSTRAP_DIR` (default `~/.workspace-bootstrap`),
`WSB_UNATTENDED=1`.

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

`modules/NN-name.sh` is sourced in a subshell with `lib/common.sh` already loaded. It defines:

- `module_check`: return 0 if everything is already set up.
- `module_install`: do the work and return 0. Return `$WSB_RC_TODO` if it is not implemented yet.

Helpers: `is_macos`, `is_debian`, `as_root`, `run` (honours `--dry-run`), and `log_info`, `log_ok`,
`log_warn`, `log_err`.

### Releasing

```sh
scripts/release.sh v0.1.0 --push
```

This creates a `release v0.1.0` commit in which `install.sh` contains `WSB_PINNED_REF="v0.1.0"`,
and tags that commit. It then adds a second commit that resets the pin on `main`. That is how a
tag URL knows its own version.
