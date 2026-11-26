# shellcheck shell=bash
#
# Shared helpers for bootstrap.sh and modules.
# Must stay compatible with bash 3.2 (the macOS system bash): no associative
# arrays, no mapfile, no ${var,,}, and guard empty-array expansions.

# --- output -----------------------------------------------------------------

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GRN=$'\033[1;32m'; C_YEL=$'\033[1;33m'
  C_RED=$'\033[1;31m';  C_DIM=$'\033[2m';    C_OFF=$'\033[0m'
else
  C_BLUE=""; C_GRN=""; C_YEL=""; C_RED=""; C_DIM=""; C_OFF=""
fi

log_step() { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
log_info() { printf '    %s\n' "$*"; }
log_ok()   { printf '    %s✔%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
log_warn() { printf '    %s!%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
log_err()  { printf '    %s✖%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()      { printf '%s✖%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# --- platform ---------------------------------------------------------------

# Sets and exports:
#   WSB_OS         macos | debian | ubuntu
#   WSB_OS_FAMILY  macos | debian
#   WSB_ARCH       amd64 | arm64
wsb_detect_platform() {
  local kernel machine os_id os_name
  kernel=$(uname -s)
  case "$kernel" in
    Darwin)
      WSB_OS=macos; WSB_OS_FAMILY=macos ;;
    Linux)
      [[ -r /etc/os-release ]] || die "Unsupported OS: cannot read /etc/os-release. Supported: macOS, Debian, Ubuntu."
      # shellcheck disable=SC1091
      os_id=$(. /etc/os-release && printf '%s' "${ID:-}")
      case "$os_id" in
        debian|ubuntu) WSB_OS=$os_id; WSB_OS_FAMILY=debian ;;
        *)
          # shellcheck disable=SC1091
          os_name=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-$os_id}")
          die "Unsupported OS: ${os_name:-unknown Linux}. workspace-bootstrap supports macOS, Debian and Ubuntu only."
          ;;
      esac
      ;;
    *)
      die "Unsupported OS: $kernel. workspace-bootstrap supports macOS, Debian and Ubuntu only." ;;
  esac

  machine=$(uname -m)
  case "$machine" in
    x86_64|amd64)  WSB_ARCH=amd64 ;;
    arm64|aarch64) WSB_ARCH=arm64 ;;
    *) die "Unsupported architecture: $machine. Supported: x86_64, arm64." ;;
  esac

  export WSB_OS WSB_OS_FAMILY WSB_ARCH
}

is_macos()  { [[ "$WSB_OS_FAMILY" == macos ]]; }
is_debian() { [[ "$WSB_OS_FAMILY" == debian ]]; }

# --- privileges -------------------------------------------------------------

is_root() { [[ "$(id -u)" -eq 0 ]]; }

# Run a command as root (directly when already root, otherwise via sudo).
as_root() {
  if is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

# Ask for the sudo password once and keep the timestamp fresh until the
# parent process exits. No-op when root or in dry-run mode.
wsb_sudo_keepalive() {
  is_root && return 0
  [[ "${WSB_DRY_RUN:-0}" == 1 ]] && return 0
  command_exists sudo || die "sudo is required (or run as root)."

  if [[ "${WSB_UNATTENDED:-0}" == 1 ]]; then
    sudo -n true 2>/dev/null || die "Unattended mode needs passwordless sudo (or run as root)."
  else
    log_info "Some steps need administrator rights; you may be asked for your password."
    sudo -v || die "Could not obtain sudo rights."
  fi

  local parent=$$
  ( while kill -0 "$parent" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  WSB_SUDO_PID=$!
  trap 'kill "$WSB_SUDO_PID" 2>/dev/null || true' EXIT
}

# --- dry run ----------------------------------------------------------------

# Run a command, or just print it in dry-run mode.
run() {
  if [[ "${WSB_DRY_RUN:-0}" == 1 ]]; then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_OFF" "$*"
  else
    "$@"
  fi
}

# --- module return codes ----------------------------------------------------

# module_install may return this to report "not implemented yet".
# shellcheck disable=SC2034
WSB_RC_TODO=3
