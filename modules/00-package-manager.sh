# shellcheck shell=bash
#
# Module: package-manager
# macOS: Homebrew (installed only if missing). Debian/Ubuntu: fresh apt index.

WSB_HOMEBREW_INSTALL_URL="${WSB_HOMEBREW_INSTALL_URL:-https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}"

module_install() {
  if is_debian; then
    pkg_apt_refresh
    return 0
  fi

  if is_root; then
    log_err "Homebrew refuses to run as root; re-run bootstrap as your normal user."
    return 1
  fi
  if command_exists brew; then
    log_ok "Homebrew already installed ($(brew --version 2>/dev/null | sed -n 1p))"
    return 0
  fi
  if [[ "$WSB_DRY_RUN" == 1 ]]; then
    log_info "would install Homebrew"
    mark_changed "would install Homebrew"
    return 0
  fi

  log_info "installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$WSB_HOMEBREW_INSTALL_URL")"
  wsb_load_brew_env
  command_exists brew || { log_err "brew not found after installation"; return 1; }
  log_ok "installed $(brew --version 2>/dev/null | sed -n 1p)"
  mark_changed "installed Homebrew"
}
