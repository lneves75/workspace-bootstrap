# shellcheck shell=bash disable=SC2034  # MODULE_* and TOOL_* are read by bootstrap.sh / lib/tools.sh
#
# Module: terraform (optional): Terraform
# Logic in lib/tools.sh. Asked with default No; remembered once chosen.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install Terraform?"

TOOL_NAME="Terraform"
TOOL_CMD=terraform
TOOL_VERSION="CHECKPOINT_DISABLE=1 terraform version"
TOOL_BREW=hashicorp/tap/terraform
TOOL_APT=terraform
TOOL_APT_REPO="hashicorp|https://apt.releases.hashicorp.com/gpg|deb [arch=@ARCH@ signed-by=@KEYRING@] https://apt.releases.hashicorp.com @CODENAME@ main"

module_check()   { tool_module_check; }
module_install() { tool_module_install; }
