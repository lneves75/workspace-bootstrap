# shellcheck shell=bash
#
# Module: base-tools
# Everyday CLI tools from packages/base.brew or packages/base.apt, plus
# mikefarah/yq: Homebrew on macOS; on Debian/Ubuntu a pinned, checksum-
# verified binary in /usr/local/bin (the distribution's "yq" package is a
# different, Python-based tool).

ensure_yq_debian() {
  # shellcheck source=versions.env
  source "$WSB_ROOT/versions.env"
  local version_cmd="$WSB_BIN_DIR/yq --version" sha_var="YQ_SHA256_$WSB_ARCH"
  if pinned_binary_current yq "$YQ_VERSION" "$version_cmd"; then
    log_ok "yq $YQ_VERSION already installed"
    return 0
  fi
  if [[ "$WSB_DRY_RUN" == 1 ]]; then
    log_info "would install yq $YQ_VERSION (verified download)"
    mark_changed "would install yq $YQ_VERSION"
    return 0
  fi
  log_info "installing yq $YQ_VERSION (verified download)"
  install_release_binary yq "$YQ_VERSION" \
    "https://github.com/mikefarah/yq/releases/download/v$YQ_VERSION/yq_linux_$WSB_ARCH" \
    "${!sha_var}"
  pinned_binary_current yq "$YQ_VERSION" "$version_cmd" \
    || { log_err "yq is not at $YQ_VERSION after installation"; return 1; }
  log_ok "installed yq $YQ_VERSION"
  mark_changed "installed yq $YQ_VERSION"
}

module_install() {
  pkg_ensure_list base
  if is_debian; then ensure_yq_debian; fi
}
