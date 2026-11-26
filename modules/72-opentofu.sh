# shellcheck shell=bash disable=SC2034  # MODULE_* and TOOL_* are read by bootstrap.sh / lib/tools.sh
#
# Module: opentofu (optional): OpenTofu
# Logic in lib/tools.sh. Asked with default No; remembered once chosen.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install OpenTofu (tofu)?"

TOOL_NAME="OpenTofu"
TOOL_CMD=tofu
TOOL_VERSION="tofu version"
TOOL_BREW=opentofu
TOOL_APT=tofu
TOOL_APT_REPO="opentofu|https://get.opentofu.org/opentofu.gpg https://packages.opentofu.org/opentofu/tofu/gpgkey|deb [signed-by=@KEYRING@] https://packages.opentofu.org/opentofu/tofu/any/ any main"

module_check()   { tool_module_check; }
module_install() { tool_module_install; }
