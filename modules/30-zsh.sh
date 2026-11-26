# shellcheck shell=bash
#
# Module: zsh
#   1. zsh itself (ships with macOS; apt on Debian/Ubuntu)
#   2. Oh My Zsh at the commit pinned in versions.env
#   3. external plugins from config/zsh/external-plugins.txt, each pinned
#   4. ~/.zshrc → config/zsh/zshrc (any existing file is backed up)
#   5. zsh as the login shell (set WSB_NO_CHSH=1 to skip)
#   6. Debian/Ubuntu: the en_US.UTF-8 locale, which the agnoster theme needs
#
# Each step checks first and is skipped when already in place. An Oh My Zsh or
# plugin checkout that was installed some other way (on a branch) is reported
# and left alone.

ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$ZSH_DIR/custom}"

zsh_path() {
  # Prefer the system zsh on macOS: it is already listed in /etc/shells.
  if is_macos && [[ -x /bin/zsh ]]; then
    printf /bin/zsh
  else
    command -v zsh
  fi
}

login_shell() {
  local user
  user=$(id -un)
  if is_macos; then
    dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{ print $2 }'
  else
    getent passwd "$user" | cut -d: -f7
  fi
}

ensure_zsh_installed() {
  if is_debian; then
    pkg_ensure zsh
  elif command_exists zsh; then
    log_ok "zsh already installed ($(zsh --version))"
  else
    log_err "zsh not found (it ships with macOS; is /bin/zsh missing?)"
    return 1
  fi
}

ensure_external_plugins() {
  local list="$WSB_ROOT/config/zsh/external-plugins.txt" name url commit
  while read -r name url commit _; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    git_pinned_checkout "$name" "$ZSH_CUSTOM_DIR/plugins/$name" "$url" "$commit"
  done < "$list"
}

ensure_login_shell() {
  local zsh current user
  zsh=$(zsh_path)
  current=$(login_shell)
  user=$(id -un)

  if [[ "$(basename "${current:-none}")" == zsh ]]; then
    log_ok "login shell already zsh ($current)"
    return 0
  fi
  if [[ "${WSB_NO_CHSH:-0}" == 1 ]]; then
    log_info "login shell is ${current:-unknown}; not changing it (WSB_NO_CHSH=1)"
    return 0
  fi
  if [[ -z "$zsh" ]]; then
    log_err "zsh not on PATH"
    return 1
  fi

  if ! grep -qx "$zsh" /etc/shells 2>/dev/null; then
    log_info "adding $zsh to /etc/shells"
    run as_root sh -c "printf '%s\n' '$zsh' >> /etc/shells"
    mark_changed "added $zsh to /etc/shells"
  fi

  log_info "changing login shell of $user: ${current:-unknown} → $zsh"
  run as_root chsh -s "$zsh" "$user"
  mark_changed "login shell → $zsh (applies to new logins)"
}

has_utf8_locale() {
  grep -qiE '^en_US\.utf-?8$' <<< "$(locale -a 2>/dev/null)"
}

ensure_utf8_locale() {
  is_debian || return 0
  if has_utf8_locale; then
    log_ok "en_US.UTF-8 locale available"
    return 0
  fi
  if [[ "$WSB_DRY_RUN" == 1 ]]; then
    log_info "would generate the en_US.UTF-8 locale (for the agnoster theme)"
    mark_changed "would generate en_US.UTF-8"
    return 0
  fi
  pkg_ensure locales
  log_info "generating the en_US.UTF-8 locale (for the agnoster theme)"
  if [[ "$WSB_OS" == ubuntu ]]; then
    as_root locale-gen en_US.UTF-8 >/dev/null
  else
    if grep -qE '^# *en_US\.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null; then
      as_root sed -i 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
    elif ! grep -qE '^en_US\.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null; then
      as_root sh -c "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
    fi
    as_root locale-gen >/dev/null
  fi
  has_utf8_locale || { log_err "en_US.UTF-8 still missing after locale-gen"; return 1; }
  log_ok "generated en_US.UTF-8"
  mark_changed "generated the en_US.UTF-8 locale"
}

module_install() {
  # shellcheck source=versions.env
  source "$WSB_ROOT/versions.env"

  ensure_zsh_installed
  ensure_utf8_locale
  git_pinned_checkout "Oh My Zsh" "$ZSH_DIR" "$OMZ_REPO" "$OMZ_COMMIT"
  ensure_external_plugins
  link_file "$WSB_ROOT/config/zsh/zshrc" "$HOME/.zshrc"
  ensure_login_shell
}
