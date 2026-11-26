#!/bin/sh
#
# workspace-bootstrap — stage 0 installer
#
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/lneves75/workspace-bootstrap/main/install.sh)"
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/lneves75/workspace-bootstrap/v0.1.0/install.sh)"
#
# Responsibilities (kept deliberately small, POSIX sh only):
#   1. refuse unsupported platforms
#   2. make sure git + curl are present
#   3. resolve which version of workspace-bootstrap to install
#   4. clone that version into $BOOTSTRAP_DIR and hand over to bootstrap.sh
#
# Environment:
#   WSB_REF          version to install: a tag (v1.2.3), a branch (main) or "latest".
#                    Overrides the version baked into this script.
#   WSB_REPO         git URL to clone from (default: the GitHub repo)
#   BOOTSTRAP_DIR    where to clone (default: ~/.workspace-bootstrap)
#   WSB_UNATTENDED   1 = never prompt (same as --unattended)
#
# All arguments are passed through to bootstrap.sh.

set -eu

# Set by scripts/release.sh on release commits. Do not edit by hand.
WSB_PINNED_REF=""

WSB_REPO="${WSB_REPO:-https://github.com/lneves75/workspace-bootstrap.git}"
BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-$HOME/.workspace-bootstrap}"
WSB_REF="${WSB_REF:-}"
WSB_UNATTENDED="${WSB_UNATTENDED:-0}"

for arg in "$@"; do
  case "$arg" in
    --unattended) WSB_UNATTENDED=1 ;;
  esac
done

# --- output -----------------------------------------------------------------

if [ -t 1 ]; then
  C_BLUE=$(printf '\033[1;34m'); C_YEL=$(printf '\033[1;33m')
  C_RED=$(printf '\033[1;31m');  C_GRN=$(printf '\033[1;32m'); C_OFF=$(printf '\033[0m')
else
  C_BLUE=""; C_YEL=""; C_RED=""; C_GRN=""; C_OFF=""
fi

info() { printf '%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
ok()   { printf '%s✔%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%s✖%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# --- platform ---------------------------------------------------------------

detect_platform() {
  kernel=$(uname -s)
  case "$kernel" in
    Darwin)
      WSB_OS=macos
      ;;
    Linux)
      [ -r /etc/os-release ] || die "Unsupported OS: cannot read /etc/os-release. Supported: macOS, Debian, Ubuntu."
      # shellcheck disable=SC1091
      os_id=$(. /etc/os-release && printf '%s' "${ID:-}")
      case "$os_id" in
        debian|ubuntu) WSB_OS=$os_id ;;
        *)
          # shellcheck disable=SC1091
          os_name=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-$os_id}")
          die "Unsupported OS: ${os_name:-unknown Linux}. workspace-bootstrap supports macOS, Debian and Ubuntu only."
          ;;
      esac
      ;;
    *)
      die "Unsupported OS: $kernel. workspace-bootstrap supports macOS, Debian and Ubuntu only."
      ;;
  esac

  machine=$(uname -m)
  case "$machine" in
    x86_64|amd64)  WSB_ARCH=amd64 ;;
    arm64|aarch64) WSB_ARCH=arm64 ;;
    *) die "Unsupported architecture: $machine. Supported: x86_64, arm64." ;;
  esac
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "Root privileges required for: $* (sudo is not installed)."
  fi
}

# --- prerequisites: git + curl ---------------------------------------------

ensure_prereqs_macos() {
  # /usr/bin/git exists on a fresh Mac but is only a shim until the
  # Command Line Tools are installed, so check for the tools themselves.
  if xcode-select -p >/dev/null 2>&1; then
    ok "Xcode Command Line Tools present"
    return
  fi
  if [ "$WSB_UNATTENDED" = 1 ]; then
    die "Xcode Command Line Tools are missing. Install them with 'xcode-select --install' and re-run."
  fi
  info "Installing Xcode Command Line Tools (accept the dialog that opens)…"
  xcode-select --install >/dev/null 2>&1 || true
  waited=0
  until xcode-select -p >/dev/null 2>&1; do
    sleep 5
    waited=$((waited + 5))
    [ "$waited" -ge 1800 ] && die "Timed out waiting for Xcode Command Line Tools."
  done
  ok "Xcode Command Line Tools installed"
}

ensure_prereqs_debian() {
  missing=""
  command -v git  >/dev/null 2>&1 || missing="$missing git"
  command -v curl >/dev/null 2>&1 || missing="$missing curl"
  [ -e /etc/ssl/certs/ca-certificates.crt ] || missing="$missing ca-certificates"
  if [ -z "$missing" ]; then
    ok "git and curl present"
    return
  fi
  info "Installing:$missing"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  # shellcheck disable=SC2086
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $missing >/dev/null
  ok "Installed:$missing"
}

# --- version resolution -----------------------------------------------------

latest_release() {
  # Highest vMAJOR.MINOR.PATCH tag on the remote; empty if there are none.
  git ls-remote --tags --refs "$WSB_REPO" 'v*' 2>/dev/null \
    | sed 's#.*refs/tags/##' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed 's/^v//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n 1 \
    | sed 's/^/v/' || true
}

resolve_ref() {
  if [ -n "$WSB_REF" ] && [ "$WSB_REF" != latest ]; then
    WSB_SOURCE="env"
  elif [ -n "$WSB_PINNED_REF" ] && [ "$WSB_REF" != latest ]; then
    WSB_REF=$WSB_PINNED_REF
    WSB_SOURCE=pinned
  else
    WSB_REF=$(latest_release)
    WSB_SOURCE=latest
    if [ -z "$WSB_REF" ]; then
      git ls-remote --exit-code "$WSB_REPO" HEAD >/dev/null 2>&1 \
        || die "Cannot reach repository $WSB_REPO"
      warn "No releases found in $WSB_REPO, falling back to 'main'."
      WSB_REF=main
      WSB_SOURCE=fallback
    fi
  fi
  info "Using workspace-bootstrap $WSB_REF ($WSB_SOURCE)"
}

# --- fetch ------------------------------------------------------------------

fetch_repo() {
  if [ -e "$BOOTSTRAP_DIR" ] && [ ! -d "$BOOTSTRAP_DIR/.git" ]; then
    die "$BOOTSTRAP_DIR exists but is not a git checkout. Move it away or set BOOTSTRAP_DIR."
  fi

  # Same path for fresh installs and updates: shallow-fetch exactly one ref
  # (tag or branch) and check it out detached. (`git clone --depth 1 --branch
  # <annotated tag>` works too but prints a spurious "not a commit" warning.)
  fresh=0
  if [ -d "$BOOTSTRAP_DIR/.git" ]; then
    if [ -n "$(git -C "$BOOTSTRAP_DIR" status --porcelain --untracked-files=no)" ]; then
      die "$BOOTSTRAP_DIR has local modifications. Commit, stash or discard them first."
    fi
    info "Updating $BOOTSTRAP_DIR to $WSB_REF"
    git -C "$BOOTSTRAP_DIR" remote set-url origin "$WSB_REPO"
  else
    fresh=1
    info "Cloning $WSB_REPO ($WSB_REF) into $BOOTSTRAP_DIR"
    git init --quiet "$BOOTSTRAP_DIR"
    git -C "$BOOTSTRAP_DIR" remote add origin "$WSB_REPO"
  fi

  if ! git -C "$BOOTSTRAP_DIR" fetch --quiet --depth 1 --force origin "$WSB_REF"; then
    [ "$fresh" = 1 ] && rm -rf "$BOOTSTRAP_DIR"
    die "Version '$WSB_REF' not found in $WSB_REPO"
  fi
  git -C "$BOOTSTRAP_DIR" checkout --quiet --force --detach FETCH_HEAD

  commit=$(git -C "$BOOTSTRAP_DIR" rev-parse HEAD)
  {
    printf 'WSB_REF=%s\n' "$WSB_REF"
    printf 'WSB_COMMIT=%s\n' "$commit"
    printf 'WSB_SOURCE=%s\n' "$WSB_SOURCE"
  } > "$BOOTSTRAP_DIR/.version"
  ok "Checked out $WSB_REF ($(printf '%s' "$commit" | cut -c1-12))"
}

# --- main -------------------------------------------------------------------

main() {
  detect_platform
  info "Platform: $WSB_OS/$WSB_ARCH"

  case "$WSB_OS" in
    macos) ensure_prereqs_macos ;;
    *)     ensure_prereqs_debian ;;
  esac

  resolve_ref
  fetch_repo

  command -v bash >/dev/null 2>&1 || die "bash is required to continue."
  export WSB_UNATTENDED BOOTSTRAP_DIR
  exec bash "$BOOTSTRAP_DIR/bootstrap.sh" "$@"
}

main "$@"
