#!/usr/bin/env bash
#
# workspace-bootstrap — stage 1 orchestrator.
# Normally started by install.sh; can be re-run at any time:
#
#   ~/.workspace-bootstrap/bootstrap.sh [options]
#
set -euo pipefail

WSB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WSB_ROOT
# shellcheck source=lib/common.sh
source "$WSB_ROOT/lib/common.sh"

usage() {
  cat <<EOF
Usage: bootstrap.sh [options]

Options:
  --with LIST        install these optional modules without asking
  --forget LIST      stop keeping these optional modules up to date (no uninstall)
  --only LIST        run only these modules (comma separated; implies --with)
  --skip LIST        skip these modules
  --unattended       never prompt; optional modules are skipped unless --with
  --dry-run          show what would be done, change nothing
  --upgrade[=REF]    switch to the latest release (or REF) and re-run
  --doctor           check this machine against the installed version (read-only)
  --list             list modules and exit
  -h, --help         show this help

Undo the configuration changes: $WSB_ROOT/scripts/uninstall.sh

Modules (* = optional, asked with default No):
$(list_modules_annotated | sed 's/^/  /')
EOF
}

# --- modules ----------------------------------------------------------------

module_files() {
  local f
  for f in "$WSB_ROOT"/modules/[0-9][0-9]-*.sh; do
    [[ -e "$f" ]] && printf '%s\n' "$f"
  done
}

# modules/30-zsh.sh -> zsh
module_name() {
  local base
  base=$(basename "$1" .sh)
  printf '%s' "${base#[0-9][0-9]-}"
}

module_is_optional() {
  grep -q '^MODULE_OPTIONAL=1' "$1"
}

list_modules() {
  local f
  while IFS= read -r f; do
    module_name "$f"; printf '\n'
  done < <(module_files)
}

list_modules_annotated() {
  local f
  while IFS= read -r f; do
    module_name "$f"
    if module_is_optional "$f"; then printf ' *'; fi
    printf '\n'
  done < <(module_files)
}

in_list() { # in_list NAME "a,b,c"
  case ",$2," in *",$1,"*) return 0 ;; esac
  return 1
}

# --- options ----------------------------------------------------------------

WSB_ONLY=""
WSB_SKIP=""
WSB_WITH="${WSB_WITH:-}"
WSB_FORGET=""
WSB_UNATTENDED="${WSB_UNATTENDED:-0}"
WSB_DRY_RUN=0
WSB_UPGRADE=""
PASSTHRU=()

need_value() { [[ $1 -ge 2 ]] || die "$2 needs a value"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)        need_value $# "$1"; WSB_ONLY=$2; PASSTHRU+=("$1" "$2"); shift ;;
    --only=*)      WSB_ONLY=${1#*=}; PASSTHRU+=("$1") ;;
    --skip)        need_value $# "$1"; WSB_SKIP=$2; PASSTHRU+=("$1" "$2"); shift ;;
    --skip=*)      WSB_SKIP=${1#*=}; PASSTHRU+=("$1") ;;
    --with)        need_value $# "$1"; WSB_WITH=$2; PASSTHRU+=("$1" "$2"); shift ;;
    --with=*)      WSB_WITH=${1#*=}; PASSTHRU+=("$1") ;;
    --forget)      need_value $# "$1"; WSB_FORGET=$2; shift ;;
    --forget=*)    WSB_FORGET=${1#*=} ;;
    --unattended)  WSB_UNATTENDED=1; PASSTHRU+=("$1") ;;
    --dry-run)     WSB_DRY_RUN=1; PASSTHRU+=("$1") ;;
    --upgrade)     WSB_UPGRADE=latest ;;
    --upgrade=*)   WSB_UPGRADE=${1#*=} ;;
    --list)        list_modules_annotated; exit 0 ;;
    --doctor)      exec bash "$WSB_ROOT/scripts/doctor.sh" ;;
    -h|--help)     usage; exit 0 ;;
    *)             usage >&2; die "Unknown option: $1" ;;
  esac
  shift
done
export WSB_UNATTENDED WSB_DRY_RUN

# Validate module names given to --only / --skip / --with.
ALL_MODULES=$(list_modules | tr '\n' ',')
for name in ${WSB_ONLY//,/ } ${WSB_SKIP//,/ } ${WSB_WITH//,/ } ${WSB_FORGET//,/ }; do
  in_list "$name" "$ALL_MODULES" || die "Unknown module: $name (see --list)"
done

# --- upgrade ----------------------------------------------------------------

if [[ -n "$WSB_UPGRADE" ]]; then
  log_step "Upgrading workspace-bootstrap to $WSB_UPGRADE"
  repo_url=$(git -C "$WSB_ROOT" remote get-url origin 2>/dev/null) \
    || die "$WSB_ROOT is not a git checkout; re-run install.sh instead."
  # install.sh resolves the ref, checks out the new version and execs its bootstrap.sh.
  exec env WSB_REF="$WSB_UPGRADE" WSB_REPO="$repo_url" BOOTSTRAP_DIR="$WSB_ROOT" \
    sh "$WSB_ROOT/install.sh" ${PASSTHRU[@]+"${PASSTHRU[@]}"}
fi

# --- version lock -----------------------------------------------------------

WSB_REF="dev"
if [[ -f "$WSB_ROOT/.version" ]]; then
  WSB_COMMIT=""
  # shellcheck disable=SC1091
  source "$WSB_ROOT/.version"
  head_commit=$(git -C "$WSB_ROOT" rev-parse HEAD 2>/dev/null || true)
  if [[ "$head_commit" != "$WSB_COMMIT" ]]; then
    die "Checked-out code ($head_commit) does not match the installed version $WSB_REF ($WSB_COMMIT).
  Run '$WSB_ROOT/bootstrap.sh --upgrade=$WSB_REF' to restore it, or --upgrade for the latest release."
  fi
else
  log_warn "No .version file: running from a development checkout, versions are not locked."
fi
export WSB_REF

# --- run --------------------------------------------------------------------

wsb_detect_platform

printf '%sworkspace-bootstrap %s%s on %s/%s%s\n' \
  "$C_BLUE" "$WSB_REF" "$C_OFF" "$WSB_OS" "$WSB_ARCH" \
  "$([[ "$WSB_DRY_RUN" == 1 ]] && printf ' (dry run)')"

# Per-run scratch space (change log, sudo keep-alive pid). sudo itself is
# requested lazily by as_root, only when a step really needs it.
WSB_RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/wsb-run.XXXXXX")
WSB_MAIN_PID=$$
export WSB_RUN_DIR WSB_MAIN_PID
cleanup() {
  if [[ -f "$WSB_RUN_DIR/sudo-keepalive.pid" ]]; then
    kill "$(cat "$WSB_RUN_DIR/sudo-keepalive.pid")" 2>/dev/null || true
  fi
  rm -rf "$WSB_RUN_DIR"
}
trap cleanup EXIT

# Optional modules you have chosen once (prompt or --with) are remembered, so
# later runs (including `--upgrade --unattended`) keep them up to date
# without asking again. --forget removes them from this list.
SELECTED_FILE="$(wsb_state_dir)/selected-modules"
REMEMBERED=""
if [[ -f "$SELECTED_FILE" ]]; then REMEMBERED=$(tr '\n' ',' < "$SELECTED_FILE"); fi
remember_module() {
  in_list "$1" "$REMEMBERED" && return 0
  [[ "$WSB_DRY_RUN" == 1 ]] && return 0
  printf '%s\n' "$1" >> "$SELECTED_FILE"
  REMEMBERED="$REMEMBERED,$1"
}
if [[ -n "$WSB_FORGET" ]]; then
  for name in ${WSB_FORGET//,/ }; do
    if in_list "$name" "$REMEMBERED"; then
      log_info "forgetting optional module '$name' (it stays installed; future runs will ask again)"
    fi
  done
  if [[ -f "$SELECTED_FILE" && "$WSB_DRY_RUN" != 1 ]]; then
    tmp_sel=$(mktemp)
    grep -vxF -f <(tr ',' '\n' <<< "$WSB_FORGET") "$SELECTED_FILE" > "$tmp_sel" || true
    cat "$tmp_sel" > "$SELECTED_FILE"; rm -f "$tmp_sel"
    REMEMBERED=$(tr '\n' ',' < "$SELECTED_FILE")
  fi
fi

SUMMARY=()
FAILED=0
# Files replaced during this run are moved here. The folder is only created
# when something is actually backed up, and is unique per run.
if [[ -z "${WSB_BACKUP_DIR:-}" ]]; then
  WSB_BACKUP_DIR="$HOME/.workspace-bootstrap-backup/$(date +%Y%m%d-%H%M%S)"
  n=1; base=$WSB_BACKUP_DIR
  while [[ -e "$WSB_BACKUP_DIR" ]]; do n=$((n + 1)); WSB_BACKUP_DIR="$base-$n"; done
fi
export WSB_BACKUP_DIR
CHANGES_FILE="$WSB_RUN_DIR/changes"

# Module subshell exit codes (besides 0 = success and WSB_RC_TODO):
RC_ALREADY=10        # module_check says everything is in place
RC_NOT_SELECTED=12   # optional module declined / not selected
RC_WOULD_ASK=13      # optional module, dry run: would prompt

# shellcheck disable=SC2031  # $name is a local argument, not the subshell's
run_module() {
  local file=$1 name=$2 selected=$3 rc changes optional=0
  log_step "$name"
  : > "$CHANGES_FILE"
  set +e
  (
    set -euo pipefail
    export WSB_CHANGES_FILE="$CHANGES_FILE"
    MODULE_OPTIONAL=0
    MODULE_PROMPT="Install $name?"
    module_check()   { return 1; }
    module_install() { return "$WSB_RC_TODO"; }
    # shellcheck source=lib/pkg.sh
    source "$WSB_ROOT/lib/pkg.sh"
    # shellcheck source=lib/files.sh
    source "$WSB_ROOT/lib/files.sh"
    wsb_load_brew_env
    # shellcheck disable=SC1090
    source "$file"

    if module_check; then
      log_ok "already set up"
      exit $RC_ALREADY
    fi

    if [[ "$MODULE_OPTIONAL" == 1 && "$selected" != 1 ]]; then
      if [[ "$WSB_DRY_RUN" == 1 ]]; then
        log_info "optional: would ask \"$MODULE_PROMPT\" (default No)"
        exit $RC_WOULD_ASK
      fi
      if [[ "$WSB_UNATTENDED" == 1 ]]; then
        log_info "optional, not selected (use --with $name)"
        exit $RC_NOT_SELECTED
      fi
      if ! ask_yes_no "$MODULE_PROMPT" n; then
        log_info "skipped"
        exit $RC_NOT_SELECTED
      fi
      : > "$WSB_RUN_DIR/accepted-$name"   # tell the parent: chosen at the prompt
    fi

    module_install
  )
  rc=$?
  set -e
  if module_is_optional "$file"; then optional=1; fi
  # Remember an optional module once it is chosen: accepted at the prompt, or
  # selected with --with/--only (even if it turned out to be set up already).
  # A Docker that merely exists (e.g. Docker Desktop) is not remembered.
  if [[ $optional == 1 ]]; then
    if { [[ $rc == 0 ]] && [[ -f "$WSB_RUN_DIR/accepted-$name" ]]; } \
       || { [[ $selected == 1 ]] && [[ $rc == 0 || $rc == "$RC_ALREADY" ]]; }; then
      remember_module "$name"
    fi
  fi

  changes=$(wc -l < "$CHANGES_FILE" | tr -d ' ')
  case $rc in
    0)
      if [[ "$changes" -gt 0 && "$WSB_DRY_RUN" == 1 ]]; then
        SUMMARY+=("· $name: would change ($(paste -sd';' "$CHANGES_FILE" | sed 's/;/; /g'))")
      elif [[ "$changes" -gt 0 ]]; then
        log_ok "done"
        SUMMARY+=("✔ $name: changed ($(paste -sd';' "$CHANGES_FILE" | sed 's/;/; /g'))")
      else
        SUMMARY+=("✔ $name: already set up")
      fi
      ;;
    "$RC_ALREADY")      SUMMARY+=("✔ $name: already set up") ;;
    "$RC_NOT_SELECTED") SUMMARY+=("· $name: optional, not installed") ;;
    "$RC_WOULD_ASK")    SUMMARY+=("· $name: optional, would ask (default No)") ;;
    "$WSB_RC_TODO")     log_warn "not implemented yet"; SUMMARY+=("· $name: not implemented yet") ;;
    *)                  log_err "failed (exit $rc)"; SUMMARY+=("✖ $name: failed (exit $rc)"); FAILED=1 ;;
  esac
}

# Module list on fd 3 so modules keep the terminal on stdin for prompts.
while IFS= read -r file <&3; do
  name=$(module_name "$file")
  if [[ -n "$WSB_ONLY" ]] && ! in_list "$name" "$WSB_ONLY"; then continue; fi
  if [[ -n "$WSB_SKIP" ]] && in_list "$name" "$WSB_SKIP"; then
    SUMMARY+=("· $name: skipped")
    continue
  fi
  selected=0
  if in_list "$name" "$WSB_WITH" || in_list "$name" "$WSB_ONLY" || in_list "$name" "$REMEMBERED"; then selected=1; fi
  run_module "$file" "$name" "$selected"
  # Later modules depend on earlier ones: stop at the first failure.
  [[ $FAILED == 0 ]] || break
done 3< <(module_files)

log_step "Summary"
for line in ${SUMMARY[@]+"${SUMMARY[@]}"}; do
  log_info "$line"
done

if [[ -d "$WSB_BACKUP_DIR" ]]; then
  log_warn "Replaced files were backed up to $WSB_BACKUP_DIR"
fi

if [[ $FAILED != 0 ]]; then
  die "Bootstrap stopped because a module failed. Fix the problem and re-run: $WSB_ROOT/bootstrap.sh"
fi
printf '\n%sAll done.%s\n' "$C_GRN" "$C_OFF"
