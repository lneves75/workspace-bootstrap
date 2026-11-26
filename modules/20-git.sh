# shellcheck shell=bash
#
# Module: git
#   1. ~/.gitconfig includes config/git/gitconfig at the top (shared
#      defaults); ~/.gitconfig itself stays a personal file
#   2. ~/.config/git/ignore → config/git/ignore (global gitignore)
#   3. user.name / user.email: asked when missing. With --unattended they come
#      from WSB_GIT_NAME / WSB_GIT_EMAIL, or are left unset with a warning
#
# git itself is installed by base-tools (and the Xcode CLT on macOS).

GIT_SHARED="$WSB_ROOT/config/git/gitconfig"
GIT_GLOBAL="$HOME/.gitconfig"

ensure_git_include() {
  local includes tmp
  includes=$(git config --global --get-all include.path 2>/dev/null || true)
  if grep -qxF "$GIT_SHARED" <<< "$includes"; then
    log_ok "$(_tilde "$GIT_GLOBAL") already includes the shared defaults"
    return 0
  fi
  if [[ "$WSB_DRY_RUN" == 1 ]]; then
    log_info "would add the shared defaults include to the top of ~/.gitconfig"
    mark_changed "would add include to ~/.gitconfig"
    return 0
  fi

  # Prepend, so personal settings further down override the shared ones.
  # Write through any symlink (cat >) and keep a copy of the original.
  tmp=$(mktemp)
  {
    printf '# Shared defaults from workspace-bootstrap; settings below override them.\n'
    printf '[include]\n\tpath = %s\n\n' "$GIT_SHARED"
    if [[ -f "$GIT_GLOBAL" ]]; then cat "$GIT_GLOBAL"; fi
  } > "$tmp"
  if [[ -f "$GIT_GLOBAL" ]]; then
    mkdir -p "$WSB_BACKUP_DIR"
    cp -p "$GIT_GLOBAL" "$WSB_BACKUP_DIR/.gitconfig"
  fi
  cat "$tmp" > "$GIT_GLOBAL"
  rm -f "$tmp"
  log_ok "added the shared defaults include to the top of ~/.gitconfig"
  mark_changed "added include to ~/.gitconfig"
}

ensure_global_ignore() {
  local excludes
  excludes=$(git config --global --get core.excludesFile 2>/dev/null || true)
  if [[ -n "$excludes" ]]; then
    log_info "core.excludesFile is set to $excludes; config/git/ignore is not used"
    return 0
  fi
  link_file "$WSB_ROOT/config/git/ignore" "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
}

ensure_git_identity() {
  local key label env_value value
  for key in user.name user.email; do
    case "$key" in
      user.name)  label="Git user name (e.g. Jane Doe):"; env_value=${WSB_GIT_NAME:-} ;;
      user.email) label="Git email:"; env_value=${WSB_GIT_EMAIL:-} ;;
    esac

    value=$(git config --global --get "$key" 2>/dev/null || true)
    if [[ -n "$value" ]]; then
      log_ok "$key already set ($value)"
      continue
    fi
    if [[ "$WSB_DRY_RUN" == 1 ]]; then
      log_info "$key not set; would ask for it"
      continue
    fi

    value=$env_value
    if [[ -z "$value" ]]; then
      value=$(ask_value "$label")
    fi
    if [[ -z "$value" ]]; then
      log_warn "$key not set. Set it later with: git config --global $key \"...\""
      continue
    fi
    if [[ "$key" == user.email && "$value" != *@* ]]; then
      log_warn "'$value' does not look like an email address; $key not set"
      continue
    fi
    git config --global "$key" "$value"
    log_ok "set $key"
    mark_changed "set $key"
  done
}

module_install() {
  command_exists git || { log_err "git not found (base-tools should have installed it)"; return 1; }
  ensure_git_include
  ensure_global_ignore
  ensure_git_identity
}
