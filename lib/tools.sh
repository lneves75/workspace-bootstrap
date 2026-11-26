# shellcheck shell=bash
#
# Shared logic for the optional CLI tool modules (modules/7x-*, 8x-*) and the
# pinned binary downloads used on Debian/Ubuntu.
#
# A tool module sets these variables and calls tool_module_check /
# tool_module_install:
#
#   TOOL_NAME        display name                      (required)
#   TOOL_CMD         command it provides               (required)
#   TOOL_VERSION     command that prints its version   (required)
#   TOOL_BREW        Homebrew formula, "cask:x" or "tap/x/formula" (macOS)
#   TOOL_APT         apt package (Debian/Ubuntu), from ...
#   TOOL_APT_REPO    ... this repository: "name|key-url [key-url]|deb line"
#                    (@KEYRING@, @ARCH@ and @CODENAME@ are substituted)
#   TOOL_PINNED      Debian/Ubuntu: version installed by tool_install_pinned
#                    (a function the module defines) instead of apt
#
# An existing installation from anywhere else (another package manager, an
# installer, Docker Desktop's kubectl, ...) counts as set up and is left
# alone. Only a pinned binary that we installed is upgraded to a new pin.

WSB_BIN_DIR=/usr/local/bin

sha256_of() {
  if command_exists sha256sum; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# version_matches "OUTPUT" VERSION: VERSION appears as a whole version number
version_matches() {
  local re
  re="(^|[^0-9.])v?${2//./\\.}([^0-9.]|$)"
  grep -qE -- "$re" <<< "$1"
}

# download_verified URL SHA256 DEST: download, refuse anything whose sha256
# differs from the pinned one.
download_verified() {
  local url=$1 want=$2 dest=$3 got
  if ! curl -fsSL --retry 3 -o "$dest" "$url"; then
    log_err "download failed: $url"
    return 1
  fi
  got=$(sha256_of "$dest")
  if [[ "$got" != "$want" ]]; then
    log_err "checksum mismatch for $url"
    log_err "  expected $want"
    log_err "  got      $got"
    rm -f "$dest"
    return 1
  fi
}

# Pinned binary installed by us: in $WSB_BIN_DIR and at the pinned version.
pinned_binary_current() { # pinned_binary_current CMD VERSION VERSION-COMMAND
  local cmd=$1 version=$2 out
  [[ -x "$WSB_BIN_DIR/$cmd" ]] || return 1
  out=$(eval "$3" 2>&1 | sed -n 1,3p) || true
  version_matches "$out" "$version"
}

# install_release_binary CMD VERSION URL SHA256 [MEMBER]
# Install a single binary (or MEMBER of a .tar.gz) into $WSB_BIN_DIR.
install_release_binary() {
  local cmd=$1 version=$2 url=$3 sha=$4 member=${5:-} tmp src
  tmp=$(mktemp -d)
  download_verified "$url" "$sha" "$tmp/download" || { rm -rf "$tmp"; return 1; }
  if [[ -n "$member" ]]; then
    tar -xzf "$tmp/download" -C "$tmp" "$member"
    src="$tmp/$member"
  else
    src="$tmp/download"
  fi
  as_root install -m 755 "$src" "$WSB_BIN_DIR/$cmd"
  rm -rf "$tmp"
}

_tool_version_line() {
  local out
  out=$(eval "$TOOL_VERSION" 2>/dev/null | sed -n 1p) || true
  printf '%s' "${out:-unknown version}"
}

# Debian/Ubuntu with a pinned version and a binary that is ours but outdated
_tool_pinned_outdated() {
  [[ -n "${TOOL_PINNED:-}" ]] && is_debian && [[ -x "$WSB_BIN_DIR/$TOOL_CMD" ]] \
    && ! pinned_binary_current "$TOOL_CMD" "$TOOL_PINNED" "$TOOL_VERSION"
}

tool_module_check() {
  command_exists "$TOOL_CMD" || return 1
  ! _tool_pinned_outdated
}

_tool_apt_repo() {
  local spec=$1 name keys line codename
  name=${spec%%|*}; spec=${spec#*|}
  keys=${spec%%|*}; line=${spec#*|}
  codename=$(wsb_os_codename)
  line=${line//@ARCH@/$WSB_ARCH}
  line=${line//@CODENAME@/$codename}
  pkg_apt_add_repo "$name" "$keys" "$line"
}

tool_module_install() {
  local where
  if command_exists "$TOOL_CMD" && ! _tool_pinned_outdated; then
    where=$(command -v "$TOOL_CMD")
    log_ok "$TOOL_NAME already installed ($where): $(_tool_version_line)"
    return 0
  fi

  if is_macos; then
    [[ -n "${TOOL_BREW:-}" ]] || { log_err "no Homebrew package defined for $TOOL_NAME"; return 1; }
    pkg_ensure "$TOOL_BREW"
  elif [[ -n "${TOOL_PINNED:-}" ]]; then
    if [[ "$WSB_DRY_RUN" == 1 ]]; then
      log_info "would install $TOOL_NAME $TOOL_PINNED (verified download)"
      mark_changed "would install $TOOL_NAME $TOOL_PINNED"
      return 0
    fi
    log_info "installing $TOOL_NAME $TOOL_PINNED (verified download)"
    tool_install_pinned
    pinned_binary_current "$TOOL_CMD" "$TOOL_PINNED" "$TOOL_VERSION" \
      || { log_err "$TOOL_NAME is not at $TOOL_PINNED after installation"; return 1; }
    mark_changed "installed $TOOL_NAME $TOOL_PINNED"
  else
    if [[ -n "${TOOL_APT_REPO:-}" ]]; then _tool_apt_repo "$TOOL_APT_REPO"; fi
    pkg_ensure "$TOOL_APT"
  fi

  if [[ "$WSB_DRY_RUN" != 1 ]]; then
    hash -r
    command_exists "$TOOL_CMD" || { log_err "$TOOL_CMD not on PATH after installation"; return 1; }
    log_ok "$(_tool_version_line)"
  fi
}

# For doctor.sh: report this tool's state. Prints one of:
#   ok MESSAGE | bad MESSAGE | info MESSAGE
tool_doctor() {
  if ! command_exists "$TOOL_CMD"; then
    printf 'info %s: not installed\n' "$TOOL_NAME"
  elif _tool_pinned_outdated; then
    printf 'bad %s: %s, pinned %s (re-run bootstrap)\n' "$TOOL_NAME" "$(_tool_version_line)" "$TOOL_PINNED"
  else
    printf 'ok %s: %s\n' "$TOOL_NAME" "$(_tool_version_line)"
  fi
}
