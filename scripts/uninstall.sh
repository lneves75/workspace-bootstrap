#!/usr/bin/env bash
#
# Undo workspace-bootstrap's configuration changes.
#
#   ~/.workspace-bootstrap/scripts/uninstall.sh [--yes] [--dry-run] [--all]
#
# Default: removes only the configuration hooks, restoring backups:
#   - ~/.zshrc, ~/.vimrc, ~/.config/git/ignore: symlinks into the repo are
#     removed and the newest backup of each file is put back
#   - ~/.gitconfig: the shared-defaults [include] is removed (the rest of the
#     file, including your name and email, is kept)
#   - ~/.config/mise/conf.d/workspace-bootstrap.toml: removed unless you
#     changed it
# --all also removes the Oh My Zsh and plugin checkouts that
# workspace-bootstrap made, its state directory and the checkout itself.
#
# Never touched: installed packages, languages and Docker (remove them with
# brew / apt / mise), the login shell, group membership, your personal files
# (~/.zshrc.local, ~/.gitconfig values, ...) and the backups.
set -euo pipefail

WSB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WSB_ROOT
# shellcheck source=lib/common.sh
source "$WSB_ROOT/lib/common.sh"
# shellcheck source=lib/files.sh
source "$WSB_ROOT/lib/files.sh"

YES=0 ALL=0 WSB_DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y)  YES=1 ;;
    --all)     ALL=1 ;;
    --dry-run) WSB_DRY_RUN=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $arg (see --help)" ;;
  esac
done
export WSB_DRY_RUN

BACKUP_ROOT="$HOME/.workspace-bootstrap-backup"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
GIT_SHARED="$WSB_ROOT/config/git/gitconfig"
GIT_COMMENT="# Shared defaults from workspace-bootstrap; settings below override them."
MISE_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/mise/conf.d/workspace-bootstrap.toml"

printf 'This removes the workspace-bootstrap configuration from %s%s.\n' "$HOME" \
  "$([[ $ALL == 1 ]] && printf ', plus Oh My Zsh and %s' "$(_tilde "$WSB_ROOT")")"
if [[ $YES != 1 && $WSB_DRY_RUN != 1 ]]; then
  ask_yes_no "Continue?" n || { echo "Nothing changed."; exit 0; }
fi

# Newest backup of $HOME-relative path REL, if any.
newest_backup() {
  local rel=$1 dir
  [[ -d "$BACKUP_ROOT" ]] || return 1
  while IFS= read -r dir; do
    if [[ -e "$dir/$rel" || -L "$dir/$rel" ]]; then printf '%s' "$dir/$rel"; return 0; fi
  done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r)
  return 1
}

unlink_and_restore() { # unlink_and_restore DEST
  local dest=$1 rel backup
  rel=${dest#"$HOME"/}
  if [[ ! -L "$dest" ]] || [[ "$(readlink "$dest")" != "$WSB_ROOT"/* ]]; then
    log_info "$(_tilde "$dest"): not a workspace-bootstrap link, left as is"
    return 0
  fi
  run rm "$dest"
  if backup=$(newest_backup "$rel"); then
    run mv "$backup" "$dest"
    log_ok "removed link $(_tilde "$dest"), restored $(_tilde "$backup")"
  else
    log_ok "removed link $(_tilde "$dest") (no backup to restore)"
  fi
}

remove_git_include() {
  local cfg="$HOME/.gitconfig" includes tmp
  includes=$(git config --global --get-all include.path 2>/dev/null || true)
  if ! grep -qxF "$GIT_SHARED" <<< "$includes"; then
    log_info "no workspace-bootstrap include in ~/.gitconfig"
    return 0
  fi
  if [[ $WSB_DRY_RUN == 1 ]]; then
    log_info "would remove the shared-defaults include from ~/.gitconfig"
    return 0
  fi
  git config --global --fixed-value --unset-all include.path "$GIT_SHARED"
  tmp=$(mktemp)
  grep -vxF "$GIT_COMMENT" "$cfg" > "$tmp" || true
  cat "$tmp" > "$cfg"
  rm -f "$tmp"
  if [[ -z "$(git config --global --get-regexp '^include\.' 2>/dev/null || true)" ]]; then
    git config --global --remove-section include 2>/dev/null || true
  fi
  log_ok "removed the shared-defaults include from ~/.gitconfig (your settings kept)"
}

remove_mise_copy() {
  local record
  record=$(managed_copy_record "$MISE_DEST")
  if [[ ! -e "$MISE_DEST" ]]; then
    log_info "$(_tilde "$MISE_DEST"): not present"
  elif { [[ -f "$record" ]] && cmp -s "$MISE_DEST" "$record"; } || cmp -s "$MISE_DEST" "$WSB_ROOT/config/mise/workspace-bootstrap.toml"; then
    run rm -f "$MISE_DEST" "$record"
    log_ok "removed $(_tilde "$MISE_DEST")"
  else
    log_warn "$(_tilde "$MISE_DEST") was changed by you; left as is"
  fi
}

remove_checkout() { # remove_checkout NAME DIR — only checkouts we made (detached HEAD)
  local name=$1 dir=$2
  [[ -d "$dir/.git" ]] || return 0
  if git -C "$dir" symbolic-ref -q HEAD >/dev/null; then
    log_info "$name: own checkout on a branch, left as is"
    return 0
  fi
  run rm -rf "$dir"
  log_ok "removed $name ($(_tilde "$dir"))"
}

log_step "configuration"
unlink_and_restore "$HOME/.zshrc"
unlink_and_restore "$HOME/.vimrc"
unlink_and_restore "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
remove_git_include
remove_mise_copy

if [[ $ALL == 1 ]]; then
  log_step "checkouts"
  while read -r name _; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    remove_checkout "$name" "${ZSH_CUSTOM:-$ZSH_DIR/custom}/plugins/$name"
  done < "$WSB_ROOT/config/zsh/external-plugins.txt"
  remove_checkout "Oh My Zsh" "$ZSH_DIR"
  run rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/workspace-bootstrap"
  log_ok "removed state directory"
  if [[ -f "$WSB_ROOT/.version" ]]; then
    run rm -rf "$WSB_ROOT"
    log_ok "removed $(_tilde "$WSB_ROOT")"
  else
    log_info "$(_tilde "$WSB_ROOT") is a development checkout; not removed"
  fi
fi

log_step "Not changed"
log_info "packages, languages and Docker: remove with brew / apt / mise if you no longer want them"
log_info "login shell: chsh -s /bin/bash   (if you want to switch back)"
log_info "backups: $(_tilde "$BACKUP_ROOT")"
printf '\nDone.%s\n' "$([[ $WSB_DRY_RUN == 1 ]] && printf ' (dry run, nothing changed)')"
