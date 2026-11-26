#!/usr/bin/env bash
#
# Check that this machine matches what workspace-bootstrap installs.
# Read-only: it never changes anything.
#
#   ~/.workspace-bootstrap/scripts/doctor.sh      (or: wsb --doctor)
#
# ✔ fine   ! worth a look (e.g. git identity unset, daemon stopped)
# ✖ broken (exit status 1); re-running bootstrap.sh should fix it
#
set -euo pipefail

WSB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WSB_ROOT
export WSB_DRY_RUN=1   # read-only: helpers must not create anything
# shellcheck source=lib/common.sh
source "$WSB_ROOT/lib/common.sh"
# shellcheck source=lib/pkg.sh
source "$WSB_ROOT/lib/pkg.sh"
# shellcheck source=lib/files.sh
source "$WSB_ROOT/lib/files.sh"
# shellcheck source=lib/tools.sh
source "$WSB_ROOT/lib/tools.sh"
# shellcheck source=versions.env
source "$WSB_ROOT/versions.env"

wsb_detect_platform
wsb_load_brew_env

ERRORS=0
WARNINGS=0
ok()   { log_ok "$*"; }
bad()  { log_err "$*"; ERRORS=$((ERRORS + 1)); }
warn() { log_warn "$*"; WARNINGS=$((WARNINGS + 1)); }
info() { log_info "$*"; }

check_link() { # check_link SRC DEST
  local src=$1 dest=$2
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    ok "$(_tilde "$dest") → $(_tilde "$src")"
  elif [[ -e "$dest" ]]; then
    bad "$(_tilde "$dest") exists but is not linked to $(_tilde "$src")"
  else
    bad "$(_tilde "$dest") missing"
  fi
}

check_checkout() { # check_checkout NAME DIR COMMIT
  local name=$1 dir=$2 commit=$3 head branch
  if [[ ! -d "$dir/.git" ]]; then
    bad "$name not installed ($(_tilde "$dir"))"
    return
  fi
  head=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
  if [[ "$head" == "$commit" ]]; then
    ok "$name at pinned ${commit:0:12}"
  elif branch=$(git -C "$dir" symbolic-ref -q --short HEAD); then
    warn "$name: own checkout on branch '$branch' at ${head:0:12} (pinned ${commit:0:12}), not managed"
  else
    bad "$name at ${head:0:12}, pinned ${commit:0:12}"
  fi
}

# --- workspace-bootstrap -----------------------------------------------------
log_step "workspace-bootstrap"
if [[ -f "$WSB_ROOT/.version" ]]; then
  WSB_REF="" WSB_COMMIT=""
  # shellcheck disable=SC1091
  source "$WSB_ROOT/.version"
  head=$(git -C "$WSB_ROOT" rev-parse HEAD 2>/dev/null || true)
  if [[ "$head" == "$WSB_COMMIT" ]]; then
    ok "version $WSB_REF (${WSB_COMMIT:0:12}) in $(_tilde "$WSB_ROOT")"
  else
    bad "checked-out code (${head:0:12}) differs from installed version $WSB_REF (${WSB_COMMIT:0:12})"
  fi
else
  warn "development checkout $(_tilde "$WSB_ROOT") (no .version)"
fi
info "platform: $WSB_OS/$WSB_ARCH"

# --- packages ----------------------------------------------------------------
log_step "packages"
if is_macos; then
  if command_exists brew; then ok "Homebrew $(brew --version 2>/dev/null | sed -n 1p)"; else bad "Homebrew not installed"; fi
fi
missing=()
while IFS= read -r p; do
  pkg_installed "$p" || missing+=("$p")
done < <(pkg_list "$WSB_ROOT/packages/base.$(pkg_backend)")
if [[ ${#missing[@]} -eq 0 ]]; then ok "base tools installed"; else bad "base tools missing: ${missing[*]}"; fi
if is_debian; then
  if pinned_binary_current yq "$YQ_VERSION" "$WSB_BIN_DIR/yq --version"; then
    ok "yq $YQ_VERSION"
  else
    bad "yq $YQ_VERSION missing from $WSB_BIN_DIR"
  fi
elif command_exists yq; then
  ok "$(yq --version 2>/dev/null)"
fi

# --- zsh -----------------------------------------------------------------------
log_step "zsh"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
if command_exists zsh; then ok "$(zsh --version)"; else bad "zsh not installed"; fi
if is_macos; then
  shell=$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{ print $2 }')
else
  shell=$(getent passwd "$(id -un)" | cut -d: -f7)
fi
if [[ "$(basename "${shell:-none}")" == zsh ]]; then ok "login shell $shell"; else warn "login shell is ${shell:-unknown}, not zsh"; fi
check_checkout "Oh My Zsh" "$ZSH_DIR" "$OMZ_COMMIT"
while read -r name _ commit _; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  check_checkout "$name" "${ZSH_CUSTOM:-$ZSH_DIR/custom}/plugins/$name" "$commit"
done < "$WSB_ROOT/config/zsh/external-plugins.txt"
check_link "$WSB_ROOT/config/zsh/zshrc" "$HOME/.zshrc"
if command_exists zsh; then
  if err=$(zsh -i -c exit 2>&1 </dev/null) && [[ -z "$err" ]]; then
    ok "interactive zsh starts cleanly"
  else
    bad "interactive zsh startup reports: $(sed -n 1p <<< "$err")"
  fi
fi

# --- vim -----------------------------------------------------------------------
log_step "vim"
if command_exists vim; then ok "$(vim --version 2>/dev/null | sed -n 1p)"; else bad "vim not installed"; fi
check_link "$WSB_ROOT/config/vim/vimrc" "$HOME/.vimrc"
while read -r name _ commit _; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  check_checkout "vim plugin $name" "$HOME/.vim/pack/workspace-bootstrap/start/$name" "$commit"
done < "$WSB_ROOT/config/vim/plugins.txt"
if command_exists vim; then
  colors=$(vim -N -u "$HOME/.vimrc" -i NONE -es -c 'redir => g:o | silent echo get(g:, "colors_name", "none") | redir END' \
    -c 'call writefile([trim(g:o)], "/dev/stdout")' -c 'qa!' </dev/null 2>/dev/null || true)
  if [[ "$colors" == PaperColor ]]; then ok "vim loads PaperColor + plugins"; else bad "vim colorscheme is '${colors:-?}', expected PaperColor"; fi
fi

# --- git -----------------------------------------------------------------------
log_step "git"
if command_exists git; then ok "$(git --version)"; else bad "git not installed"; fi
includes=$(git config --global --get-all include.path 2>/dev/null || true)
if grep -qxF "$WSB_ROOT/config/git/gitconfig" <<< "$includes"; then
  ok "shared defaults included by ~/.gitconfig"
else
  bad "shared defaults not included by ~/.gitconfig ($(_tilde "$WSB_ROOT/config/git/gitconfig"))"
fi
excludes=$(git config --global --get core.excludesFile 2>/dev/null || true)
if [[ -n "$excludes" ]]; then
  info "global gitignore: core.excludesFile = $excludes (your own)"
else
  check_link "$WSB_ROOT/config/git/ignore" "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
fi
for key in user.name user.email; do
  value=$(git config --global --get "$key" 2>/dev/null || true)
  if [[ -n "$value" ]]; then ok "$key = $value"; else warn "$key not set (git config --global $key \"...\")"; fi
done

# --- mise (optional) ---------------------------------------------------------
log_step "mise (optional)"
MISE_SRC="$WSB_ROOT/config/mise/workspace-bootstrap.toml"
MISE_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/mise/conf.d/workspace-bootstrap.toml"
if ! command_exists mise; then
  info "not installed"
else
  ok "$(mise --version 2>/dev/null | sed -n 1p)"
  record=$(managed_copy_record "$MISE_DEST")
  if [[ ! -f "$MISE_DEST" ]]; then
    bad "$(_tilde "$MISE_DEST") missing"
  elif cmp -s "$MISE_SRC" "$MISE_DEST"; then
    ok "$(_tilde "$MISE_DEST") matches the repo pins"
  elif [[ -f "$record" ]] && cmp -s "$MISE_DEST" "$record"; then
    bad "$(_tilde "$MISE_DEST") is outdated (re-run bootstrap to update it)"
  else
    warn "$(_tilde "$MISE_DEST") changed locally (kept; repo pins not applied)"
  fi
  if out=$(cd "$HOME" && mise ls --global --missing --no-header 2>/dev/null); then
    if [[ -z "$out" ]]; then
      current=$(cd "$HOME" && mise ls --global --current --no-header 2>/dev/null \
        | awk '{ printf "%s%s@%s", sep, $1, $2; sep=" " }') || current=""
      ok "installed: ${current:-(none)}"
    else
      bad "requested but not installed: $(awk '{ printf "%s%s@%s", sep, $1, $2; sep=" " }' <<< "$out")"
    fi
  else
    bad "mise ls failed"
  fi
fi

# --- docker (optional) ---------------------------------------------------------
log_step "docker (optional)"
if ! command_exists docker; then
  info "not installed"
else
  ok "$(docker --version 2>/dev/null)"
  if docker compose version >/dev/null 2>&1; then ok "compose plugin"; else bad "docker compose plugin not working"; fi
  if docker buildx version >/dev/null 2>&1; then ok "buildx plugin"; else bad "docker buildx plugin not working"; fi
  if docker info >/dev/null 2>&1; then
    ok "daemon reachable (context: $(docker context show 2>/dev/null || echo default))"
  elif is_macos && command_exists colima; then
    warn "daemon not reachable; start it with: brew services start colima"
  else
    warn "daemon not reachable (not started, or no permission on the socket)"
  fi
  if is_debian && ! is_root; then
    if id -nG "$(id -un)" | tr ' ' '\n' | grep -qx docker; then ok "$(id -un) in docker group"; else warn "$(id -un) not in docker group"; fi
  fi
fi

# --- optional CLI tools ---------------------------------------------------------
log_step "CLI tools (optional)"
for f in "$WSB_ROOT"/modules/[0-9][0-9]-*.sh; do
  grep -q '^TOOL_CMD=' "$f" || continue
  # shellcheck disable=SC1090
  line=$( source "$f"; tool_doctor )
  case "$line" in
    ok\ *)  ok "${line#ok }" ;;
    bad\ *) bad "${line#bad }" ;;
    *)      info "${line#info }" ;;
  esac
done

# --- summary -----------------------------------------------------------------
log_step "Result"
if [[ $ERRORS -gt 0 ]]; then
  log_err "$ERRORS problem(s), $WARNINGS warning(s). Re-run $(_tilde "$WSB_ROOT")/bootstrap.sh to fix the problems."
  exit 1
fi
log_ok "no problems, $WARNINGS warning(s)"
