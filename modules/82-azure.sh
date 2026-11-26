# shellcheck shell=bash disable=SC2034  # MODULE_* and TOOL_* are read by bootstrap.sh / lib/tools.sh
#
# Module: azure (optional): Azure CLI
# Logic in lib/tools.sh. Asked with default No; remembered once chosen.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install the Azure CLI (az)?"

TOOL_NAME="Azure CLI"
TOOL_CMD=az
TOOL_VERSION="az version --output tsv --query '\"azure-cli\"'"
TOOL_BREW=cask:azure-cli
TOOL_APT=azure-cli
TOOL_APT_REPO="microsoft-azure-cli|https://packages.microsoft.com/keys/microsoft.asc|deb [arch=@ARCH@ signed-by=@KEYRING@] https://packages.microsoft.com/repos/azure-cli/ @CODENAME@ main"

module_check()   { tool_module_check; }
module_install() { tool_module_install; }
