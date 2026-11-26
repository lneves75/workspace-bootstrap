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
    wsb_sudo_ensure || return 1
    sudo "$@"
  fi
}

# Make sure sudo works, asking for the password only the first time it is
# really needed (an idempotent re-run with nothing to do never asks). Then
# keep the sudo timestamp fresh until bootstrap.sh ($WSB_MAIN_PID) exits.
wsb_sudo_ensure() {
  is_root && return 0
  command_exists sudo || { log_err "sudo is required (or run as root)."; return 1; }

  if ! sudo -n true 2>/dev/null; then
    if [[ "${WSB_UNATTENDED:-0}" == 1 ]]; then
      log_err "Unattended mode needs passwordless sudo (or run as root)."
      return 1
    fi
    log_info "administrator rights needed; you may be asked for your password"
    sudo -v || { log_err "could not obtain sudo rights"; return 1; }
  fi

  local pidfile="${WSB_RUN_DIR:-}/sudo-keepalive.pid"
  if [[ -n "${WSB_RUN_DIR:-}" && ! -f "$pidfile" ]]; then
    local main=${WSB_MAIN_PID:-$$}
    ( while kill -0 "$main" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) >/dev/null 2>&1 &
    printf '%s' "$!" > "$pidfile"
  fi
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

# --- change tracking --------------------------------------------------------

# Modules must be idempotent: check every item first and only act on what is
# missing. Whenever a module actually changes the system it calls
# mark_changed, so the runner can tell "installed/updated" from
# "already set up". A second run on the same machine should change nothing.
mark_changed() {
  if [[ -n "${WSB_CHANGES_FILE:-}" ]]; then
    printf '%s\n' "$*" >> "$WSB_CHANGES_FILE"
  fi
  return 0
}

# --- prompts ----------------------------------------------------------------

# ask_yes_no QUESTION [DEFAULT]   DEFAULT is n (default) or y. Returns 0 for yes.
# Reads from the terminal even when stdin is redirected. With --unattended or
# without any terminal it returns the default without asking.
ask_yes_no() {
  local question=$1 default=${2:-n} hint ans=""
  if [[ "$default" == y ]]; then hint="[Y/n]"; else hint="[y/N]"; fi

  if [[ "${WSB_UNATTENDED:-0}" == 1 ]]; then
    ans=""
  elif [[ -t 0 ]]; then
    read -r -p "    $question $hint " ans || ans=""
  elif (exec </dev/tty) 2>/dev/null; then
    read -r -p "    $question $hint " ans </dev/tty || ans=""
  fi

  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    [Nn]|[Nn][Oo])     return 1 ;;
  esac
  [[ "$default" == y ]]
}

# ask_value QUESTION   Print the answer (may be empty). Prompts on the
# terminal like ask_yes_no; empty without asking in --unattended mode or when
# there is no terminal. Use as: value=$(ask_value "Your name:")
ask_value() {
  local question=$1 ans=""
  if [[ "${WSB_UNATTENDED:-0}" == 1 ]]; then
    ans=""
  elif [[ -t 0 ]]; then
    read -r -p "    $question " ans || ans=""
  elif (exec </dev/tty) 2>/dev/null; then
    read -r -p "    $question " ans </dev/tty || ans=""
  fi
  printf '%s' "$ans"
}

# --- environment ------------------------------------------------------------

# Put Homebrew on PATH for this process (it may have been installed by an
# earlier module, in another subshell).
wsb_load_brew_env() {
  is_macos || return 0
  local brew_bin
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_bin" ]]; then
      eval "$("$brew_bin" shellenv)"
      return 0
    fi
  done
  return 0
}

wsb_state_dir() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/workspace-bootstrap"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# --- module return codes ----------------------------------------------------

# module_install may return this to report "not implemented yet".
# shellcheck disable=SC2034
WSB_RC_TODO=3
