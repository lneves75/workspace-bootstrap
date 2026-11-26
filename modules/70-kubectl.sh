# shellcheck shell=bash disable=SC2034  # MODULE_* and TOOL_* are read by bootstrap.sh / lib/tools.sh
#
# Module: kubectl (optional): kubectl
# Logic in lib/tools.sh. Asked with default No; remembered once chosen.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install kubectl (Kubernetes CLI)?"

TOOL_NAME="kubectl"
TOOL_CMD=kubectl
TOOL_VERSION="kubectl version --client"
TOOL_BREW=kubernetes-cli
TOOL_APT=kubectl
# shellcheck source=versions.env
source "$WSB_ROOT/versions.env"
TOOL_APT_REPO="kubernetes|https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_MINOR/deb/Release.key|deb [signed-by=@KEYRING@] https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_MINOR/deb/ /"

module_check()   { tool_module_check; }
module_install() { tool_module_install; }
