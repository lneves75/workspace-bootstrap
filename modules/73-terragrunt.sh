# shellcheck shell=bash disable=SC2034  # MODULE_* and TOOL_* are read by bootstrap.sh / lib/tools.sh
#
# Module: terragrunt (optional): Terragrunt
# Logic in lib/tools.sh. Asked with default No; remembered once chosen.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install Terragrunt?"

TOOL_NAME="Terragrunt"
TOOL_CMD=terragrunt
TOOL_VERSION="terragrunt --version"
TOOL_BREW=terragrunt
# No apt repository: pinned, checksum-verified release binary (versions.env)
# shellcheck source=versions.env
source "$WSB_ROOT/versions.env"
TOOL_PINNED=$TERRAGRUNT_VERSION

tool_install_pinned() {
  local sha_var="TERRAGRUNT_SHA256_$WSB_ARCH"
  install_release_binary terragrunt "$TERRAGRUNT_VERSION" \
    "https://github.com/gruntwork-io/terragrunt/releases/download/v$TERRAGRUNT_VERSION/terragrunt_linux_$WSB_ARCH" \
    "${!sha_var}"
}

module_check()   { tool_module_check; }
module_install() { tool_module_install; }
