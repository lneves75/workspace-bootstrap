# shellcheck shell=bash
#
# Package layer: Homebrew on macOS, apt on Debian/Ubuntu.
# Every function is idempotent and respects --dry-run (WSB_DRY_RUN=1).
#
# Package list files (packages/*.brew, packages/*.apt): one name per line,
# '#' comments allowed. Prefix a Homebrew cask with "cask:".

export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1

pkg_backend() {
  if is_macos; then printf brew; else printf apt; fi
}

# --- installed-package cache ------------------------------------------------
# Querying brew once per package is slow, so we list everything once and
# reset the cache after installing.

_PKG_CACHE=""
_PKG_CACHE_LOADED=0

pkg_cache_reset() { _PKG_CACHE=""; _PKG_CACHE_LOADED=0; }

_pkg_cache_load() {
  [[ $_PKG_CACHE_LOADED == 1 ]] && return 0
  if is_macos; then
    if command_exists brew; then
      _PKG_CACHE=$(
        brew list --formula -1 2>/dev/null || true
        brew list --cask -1 2>/dev/null | sed 's/^/cask:/' || true
      )
    fi
  else
    _PKG_CACHE=$(dpkg-query -W -f='${Package} ${Status}\n' 2>/dev/null \
      | awk '$NF == "installed" { sub(/:.*/, "", $1); print $1 }' || true)
  fi
  _PKG_CACHE_LOADED=1
}

# pkg_installed NAME   (NAME may be "cask:foo", or a tap formula such as
# "hashicorp/tap/terraform", which brew lists by its short name)
pkg_installed() {
  local name=$1
  case "$name" in
    cask:*) ;;
    */*)    name=${name##*/} ;;
  esac
  _pkg_cache_load
  grep -qxF -- "$name" <<< "$_PKG_CACHE"
}

# --- apt index --------------------------------------------------------------

# Refresh the apt index only when it is missing or older than WSB_APT_MAX_AGE
# minutes (default 360). We keep our own stamp because apt sets the mtime of
# downloaded lists to the server's Last-Modified time.
# pkg_apt_refresh [--force]
pkg_apt_refresh() {
  local stamp max_age=${WSB_APT_MAX_AGE:-360}
  stamp="$(wsb_state_dir)/apt-update.stamp"

  if [[ "${1:-}" != --force ]] && ls /var/lib/apt/lists/*_Packages* >/dev/null 2>&1 \
     && [[ -f "$stamp" ]] && [[ -z "$(find "$stamp" -mmin +"$max_age" 2>/dev/null)" ]]; then
    log_ok "apt index is fresh"
    return 0
  fi
  log_info "refreshing apt index"
  run as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  [[ "${WSB_DRY_RUN:-0}" == 1 ]] || touch "$stamp"
}

# --- install ----------------------------------------------------------------

# pkg_install NAME...   install unconditionally (use pkg_ensure instead)
pkg_install() {
  if is_macos; then
    local formulae=() casks=() p
    for p in "$@"; do
      case "$p" in
        cask:*) casks+=("${p#cask:}") ;;
        *)      formulae+=("$p") ;;
      esac
    done
    if [[ ${#formulae[@]} -gt 0 ]]; then
      run brew install --formula "${formulae[@]}"
    fi
    if [[ ${#casks[@]} -gt 0 ]]; then
      run brew install --cask "${casks[@]}"
    fi
  else
    pkg_apt_refresh
    run as_root env DEBIAN_FRONTEND=noninteractive \
      apt-get install -y -qq --no-install-recommends "$@"
  fi
}

# pkg_ensure NAME...   install only the packages that are missing
pkg_ensure() {
  local present=() missing=() p
  for p in "$@"; do
    if pkg_installed "$p"; then present+=("$p"); else missing+=("$p"); fi
  done

  if [[ ${#present[@]} -gt 0 ]]; then
    log_ok "already installed: ${present[*]}"
  fi
  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ "${WSB_DRY_RUN:-0}" == 1 ]]; then
    log_info "would install: ${missing[*]}"
    mark_changed "would install: ${missing[*]}"
    return 0
  fi

  log_info "installing: ${missing[*]}"
  pkg_install "${missing[@]}"
  pkg_cache_reset

  local failed=()
  for p in "${missing[@]}"; do
    pkg_installed "$p" || failed+=("$p")
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    log_err "not installed after install: ${failed[*]}"
    return 1
  fi
  log_ok "installed: ${missing[*]}"
  mark_changed "installed: ${missing[*]}"
}

# pkg_list FILE   print package names from a list file
pkg_list() {
  [[ -f "$1" ]] || { log_err "package list not found: $1"; return 1; }
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

# pkg_ensure_list NAME   ensure packages/NAME.brew or packages/NAME.apt
pkg_ensure_list() {
  local file pkgs=() p
  file="$WSB_ROOT/packages/$1.$(pkg_backend)"
  while IFS= read -r p; do
    pkgs+=("$p")
  done < <(pkg_list "$file")
  if [[ ${#pkgs[@]} -eq 0 ]]; then
    log_info "no packages listed in ${file#"$WSB_ROOT"/}"
    return 0
  fi
  pkg_ensure "${pkgs[@]}"
}

# pkg_apt_add_repo NAME "KEY_URL [KEY_URL...]" REPO_LINE
# Add a third-party apt repository signed by the key(s) at KEY_URL (several
# keys are combined into one keyring). In REPO_LINE, @KEYRING@ is replaced by
# the keyring path, e.g.
#   "deb [arch=amd64 signed-by=@KEYRING@] https://example.com/deb stable main"
# Idempotent: nothing happens if the keyring and the same list file exist.
pkg_apt_add_repo() {
  local name=$1 key_url=$2 line=$3
  local keyring="/etc/apt/keyrings/$name.gpg" list="/etc/apt/sources.list.d/$name.list"
  line=${line//@KEYRING@/$keyring}

  if [[ -s "$keyring" && -f "$list" && "$(cat "$list")" == "$line" ]]; then
    log_ok "apt repository '$name' already configured"
    return 0
  fi
  if [[ "${WSB_DRY_RUN:-0}" == 1 ]]; then
    log_info "would add apt repository '$name'"
    mark_changed "would add apt repository $name"
    return 0
  fi

  log_info "adding apt repository '$name'"
  local tmp url
  tmp=$(mktemp)
  : > "$tmp"
  for url in $key_url; do
    if ! curl -fsSL "$url" -o "$tmp.key"; then
      rm -f "$tmp" "$tmp.key"
      log_err "could not download signing key $url"
      return 1
    fi
    # Keys come either ASCII-armored or binary; apt wants binary in a .gpg
    # file. Binary keyrings can simply be concatenated.
    if grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "$tmp.key"; then
      gpg --batch --yes --dearmor -o "$tmp.bin" "$tmp.key"
      cat "$tmp.bin" >> "$tmp"
      rm -f "$tmp.bin"
    else
      cat "$tmp.key" >> "$tmp"
    fi
  done
  as_root install -d -m 755 /etc/apt/keyrings
  as_root install -m 644 "$tmp" "$keyring"
  printf '%s\n' "$line" > "$tmp.list"
  as_root install -m 644 "$tmp.list" "$list"
  rm -f "$tmp" "$tmp.key" "$tmp.list"
  mark_changed "added apt repository $name"
  pkg_apt_refresh --force
}
