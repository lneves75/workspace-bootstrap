# shellcheck shell=bash disable=SC2034  # MODULE_* are read by bootstrap.sh
#
# Module: mise (optional)
#   1. mise (Homebrew on macOS, mise's apt repository on Debian/Ubuntu)
#   2. config/mise/workspace-bootstrap.toml copied to
#      ~/.config/mise/conf.d/ (a managed copy, see lib/files.sh)
#   3. the pinned Go, Python and Node versions (`mise install`)
#
# Optional: asked interactively (default No); skipped in --unattended mode
# unless selected with --with mise (or --only mise). Not asked when it is
# already fully set up.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install Go, Python and Node (via mise)?"

MISE_SRC="$WSB_ROOT/config/mise/workspace-bootstrap.toml"
MISE_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/mise/conf.d/workspace-bootstrap.toml"
MISE_APT_KEY="https://mise.jdx.dev/gpg-key.pub"
MISE_APT_REPO="https://mise.jdx.dev/deb"

export MISE_YES=1   # never prompt inside mise

# Tools requested by the global config that are not installed, as tool@version.
# Runs from $HOME so a project config in the current directory doesn't count.
mise_missing() {
  local out
  out=$(cd "$HOME" && mise ls --global --missing --no-header) || return 1
  awk 'NF >= 2 { print $1 "@" $2 }' <<< "$out"
}

module_check() {
  command_exists mise || return 1
  managed_copy_settled "$MISE_SRC" "$MISE_DEST" || return 1
  local missing
  missing=$(mise_missing) || return 1
  [[ -z "$missing" ]]
}

ensure_mise_installed() {
  if is_debian; then
    pkg_apt_add_repo mise "$MISE_APT_KEY" \
      "deb [arch=$WSB_ARCH signed-by=@KEYRING@] $MISE_APT_REPO stable main"
  fi
  pkg_ensure mise
  if [[ "$WSB_DRY_RUN" != 1 ]]; then
    command_exists mise || { log_err "mise not on PATH after installation"; return 1; }
    log_ok "$(mise --version 2>/dev/null | sed -n 1p)"
  fi
}

ensure_tools() {
  local missing=() tool
  if [[ "$WSB_DRY_RUN" == 1 ]] && ! command_exists mise; then
    log_info "would install the versions in $(_tilde "$MISE_SRC")"
    return 0
  fi
  while IFS= read -r tool; do
    [[ -n "$tool" ]] && missing+=("$tool")
  done < <(mise_missing)

  if [[ ${#missing[@]} -eq 0 ]]; then
    local current
    current=$(cd "$HOME" && mise ls --global --current --no-header 2>/dev/null \
      | awk '{ printf "%s%s@%s", sep, $1, $2; sep=" " }') || current=""
    log_ok "all requested versions installed${current:+: $current}"
    return 0
  fi
  if [[ "$WSB_DRY_RUN" == 1 ]]; then
    log_info "would install: ${missing[*]}"
    mark_changed "would install ${missing[*]}"
    return 0
  fi

  log_info "installing: ${missing[*]} (this can take a few minutes)"
  (cd "$HOME" && mise install "${missing[@]}")
  local still
  still=$(mise_missing)
  if [[ -n "$still" ]]; then
    log_err "still missing after mise install: $still"
    return 1
  fi
  log_ok "installed: ${missing[*]}"
  mark_changed "installed ${missing[*]}"
}

module_install() {
  ensure_mise_installed
  install_managed_copy "$MISE_SRC" "$MISE_DEST"
  ensure_tools
}
