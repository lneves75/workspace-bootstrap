# shellcheck shell=bash
#
# Module: vim
#   1. vim (macOS ships one; apt on Debian/Ubuntu)
#   2. ~/.vimrc → config/vim/vimrc (any existing file is backed up)
#   3. plugins from config/vim/plugins.txt as native Vim packages in
#      ~/.vim/pack/workspace-bootstrap/start/<name>, each at its pinned commit
#      (other packs under ~/.vim/pack are yours and are not touched)

VIM_PACK_DIR="$HOME/.vim/pack/workspace-bootstrap/start"

ensure_vim_plugins() {
  local list="$WSB_ROOT/config/vim/plugins.txt" name url commit before after
  before=$(wc -l < "${WSB_CHANGES_FILE:-/dev/null}" 2>/dev/null || echo 0)
  while read -r name url commit _; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    git_pinned_checkout "$name" "$VIM_PACK_DIR/$name" "$url" "$commit"
  done < "$list"
  after=$(wc -l < "${WSB_CHANGES_FILE:-/dev/null}" 2>/dev/null || echo 0)

  # Rebuild help tags only when a plugin was installed or updated.
  if [[ "$WSB_DRY_RUN" != 1 && "$after" -gt "$before" ]]; then
    vim -N -u NONE -i NONE -es -c "set rtp+=$VIM_PACK_DIR/*" -c 'silent! helptags ALL' -c 'qa!' </dev/null || true
  fi
}

module_install() {
  if is_debian; then
    pkg_ensure vim
  elif command_exists vim; then
    log_ok "vim already installed ($(vim --version 2>/dev/null | sed -n 1p))"
  else
    pkg_ensure vim
  fi
  link_file "$WSB_ROOT/config/vim/vimrc" "$HOME/.vimrc"
  ensure_vim_plugins
}
