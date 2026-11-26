# shellcheck shell=bash disable=SC2034  # MODULE_* are read by bootstrap.sh
#
# Module: docker (optional)
#
# macOS:          colima (a lightweight Linux VM) + docker CLI + compose and
#                 buildx plugins from Homebrew; plugins registered in
#                 ~/.docker/config.json; colima started as a login service
#                 (asked, default Yes; never in --unattended mode)
# Debian/Ubuntu:  docker-ce + CLI + containerd + buildx/compose plugins from
#                 Docker's official apt repository; service enabled when
#                 systemd is running; user added to the `docker` group
#
# An existing Docker (Docker Desktop, OrbStack, the distribution's docker.io,
# ...) is detected and left alone.
#
# Optional: asked interactively (default No); skipped in --unattended mode
# unless selected with --with docker (or --only docker). Not asked when it is
# already set up.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install Docker (colima on macOS, docker-ce on Debian/Ubuntu)?"

DOCKER_APT_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
DOCKER_BREW_PACKAGES=(colima docker docker-compose docker-buildx)
DOCKER_CONFIG_JSON="${DOCKER_CONFIG:-$HOME/.docker}/config.json"

# docker CLI with working compose and buildx plugins (no daemon needed)
docker_cli_complete() {
  command_exists docker \
    && docker compose version >/dev/null 2>&1 \
    && docker buildx version >/dev/null 2>&1
}

in_docker_group() {
  is_root && return 0
  id -nG "$(id -un)" 2>/dev/null | tr ' ' '\n' | grep -qx docker
}

module_check() {
  docker_cli_complete || return 1
  if is_debian; then in_docker_group || return 1; fi
  return 0
}

docker_origin() {
  local path
  path=$(command -v docker) || return 0
  path=$(readlink "$path" 2>/dev/null || printf '%s' "$path")
  printf '%s' "$path"
}

# --- macOS ------------------------------------------------------------------

ensure_cli_plugins_dir() {
  local dir tmp current
  dir="$(brew --prefix)/lib/docker/cli-plugins"
  current=$(jq -r '.cliPluginsExtraDirs[]? // empty' "$DOCKER_CONFIG_JSON" 2>/dev/null || true)
  if grep -qxF "$dir" <<< "$current"; then
    log_ok "docker CLI plugins directory already registered"
    return 0
  fi
  if [[ "$WSB_DRY_RUN" == 1 ]]; then
    log_info "would add $dir to cliPluginsExtraDirs in $(_tilde "$DOCKER_CONFIG_JSON")"
    mark_changed "would register docker CLI plugins"
    return 0
  fi
  mkdir -p "$(dirname "$DOCKER_CONFIG_JSON")"
  tmp=$(mktemp)
  if [[ -s "$DOCKER_CONFIG_JSON" ]]; then
    mkdir -p "$WSB_BACKUP_DIR/.docker"
    cp -p "$DOCKER_CONFIG_JSON" "$WSB_BACKUP_DIR/.docker/config.json"
    jq --arg d "$dir" '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) + [$d] | unique)' \
      "$DOCKER_CONFIG_JSON" > "$tmp"
  else
    jq -n --arg d "$dir" '{cliPluginsExtraDirs: [$d]}' > "$tmp"
  fi
  cat "$tmp" > "$DOCKER_CONFIG_JSON"
  rm -f "$tmp"
  log_ok "registered $dir in $(_tilde "$DOCKER_CONFIG_JSON")"
  mark_changed "registered docker CLI plugins"
}

ensure_colima_running() {
  if colima status >/dev/null 2>&1; then
    log_ok "colima is running"
    return 0
  fi
  if [[ "$WSB_DRY_RUN" == 1 ]]; then
    log_info "colima is not running; would ask to start it"
    return 0
  fi
  if [[ "$WSB_UNATTENDED" == 1 ]] || ! ask_yes_no "Start the colima VM now and at every login?" y; then
    log_info "colima not started. Start it with: brew services start colima (or: colima start)"
    return 0
  fi
  log_info "starting colima (the first start downloads a VM image and takes a few minutes)"
  brew services start colima >/dev/null
  # brew services returns at once; wait for the VM and the docker socket.
  local waited=0
  until colima status >/dev/null 2>&1 && docker info >/dev/null 2>&1; do
    sleep 5; waited=$((waited + 5))
    if [[ $waited -ge 600 ]]; then
      log_err "colima did not come up within 10 minutes; see: colima status"
      return 1
    fi
  done
  log_ok "colima running; docker context: $(docker context show 2>/dev/null)"
  mark_changed "started colima"
}

install_docker_macos() {
  if command_exists docker && ! pkg_installed docker; then
    log_ok "existing Docker found ($(docker_origin)), not managed by workspace-bootstrap; leaving it as is"
    docker_cli_complete || log_warn "its compose/buildx plugins are not working; check that installation"
    return 0
  fi
  pkg_ensure "${DOCKER_BREW_PACKAGES[@]}"
  ensure_cli_plugins_dir
  ensure_colima_running
}

# --- Debian / Ubuntu ----------------------------------------------------------

os_codename() {
  # shellcheck disable=SC1091
  (. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
}

ensure_docker_service() {
  if [[ ! -d /run/systemd/system ]]; then
    log_info "systemd is not running (container or WSL?); start the daemon yourself: sudo dockerd"
    return 0
  fi
  if systemctl is-enabled --quiet docker 2>/dev/null && systemctl is-active --quiet docker 2>/dev/null; then
    log_ok "docker service enabled and running"
    return 0
  fi
  run as_root systemctl enable --now docker containerd
  mark_changed "enabled docker service"
}

ensure_docker_group() {
  local user
  is_root && return 0
  user=$(id -un)
  if in_docker_group; then
    log_ok "$user is in the docker group"
    return 0
  fi
  log_info "adding $user to the docker group (equivalent to root access to this machine)"
  run as_root usermod -aG docker "$user"
  mark_changed "added $user to the docker group (log out and back in to use docker without sudo)"
}

install_docker_debian() {
  local codename
  if pkg_installed docker.io || pkg_installed podman-docker; then
    log_warn "the distribution's Docker (docker.io / podman-docker) is installed; leaving it as is."
    log_warn "To switch to docker-ce, remove it first: sudo apt-get remove docker.io docker-compose docker-doc podman-docker"
    return 0
  fi
  if command_exists docker && ! pkg_installed docker-ce-cli; then
    log_ok "existing Docker found ($(docker_origin)), not installed via apt; leaving it as is"
    return 0
  fi

  codename=$(os_codename)
  [[ -n "$codename" ]] || { log_err "cannot determine the $WSB_OS release codename"; return 1; }
  pkg_apt_add_repo docker "https://download.docker.com/linux/$WSB_OS/gpg" \
    "deb [arch=$WSB_ARCH signed-by=@KEYRING@] https://download.docker.com/linux/$WSB_OS $codename stable"
  pkg_ensure "${DOCKER_APT_PACKAGES[@]}"
  ensure_docker_service
  ensure_docker_group
}

module_install() {
  if is_macos; then
    install_docker_macos
  else
    install_docker_debian
  fi
  if [[ "$WSB_DRY_RUN" != 1 ]] && command_exists docker; then
    log_ok "$(docker --version 2>/dev/null)"
  fi
}
