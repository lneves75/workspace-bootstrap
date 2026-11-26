# shellcheck shell=bash disable=SC2034  # MODULE_* and TOOL_* are read by bootstrap.sh / lib/tools.sh
#
# Module: flux (optional): Flux CLI
# Logic in lib/tools.sh. Asked with default No; remembered once chosen.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install the Flux CLI (fluxcd)?"

TOOL_NAME="Flux CLI"
TOOL_CMD=flux
TOOL_VERSION="flux --version"
TOOL_BREW=fluxcd/tap/flux
# No apt repository: pinned, checksum-verified release archive (versions.env)
# shellcheck source=versions.env
source "$WSB_ROOT/versions.env"
TOOL_PINNED=$FLUX_VERSION

tool_install_pinned() {
  local sha_var="FLUX_SHA256_$WSB_ARCH"
  install_release_binary flux "$FLUX_VERSION" \
    "https://github.com/fluxcd/flux2/releases/download/v$FLUX_VERSION/flux_${FLUX_VERSION}_linux_$WSB_ARCH.tar.gz" \
    "${!sha_var}" flux
}

module_check()   { tool_module_check; }
module_install() { tool_module_install; }
