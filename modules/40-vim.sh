# shellcheck shell=bash
#
# Module: vim
#   1. vim (macOS ships one; apt on Debian/Ubuntu)
#   2. ~/.vimrc → config/vim/vimrc (any existing file is backed up)

module_install() {
  if is_debian; then
    pkg_ensure vim
  elif command_exists vim; then
    log_ok "vim already installed ($(vim --version 2>/dev/null | sed -n 1p))"
  else
    pkg_ensure vim
  fi
  link_file "$WSB_ROOT/config/vim/vimrc" "$HOME/.vimrc"
}
