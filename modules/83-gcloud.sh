# shellcheck shell=bash disable=SC2034  # MODULE_* and TOOL_* are read by bootstrap.sh / lib/tools.sh
#
# Module: gcloud (optional): Google Cloud CLI
# Logic in lib/tools.sh. Asked with default No; remembered once chosen.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install the Google Cloud CLI (gcloud)?"

TOOL_NAME="Google Cloud CLI"
TOOL_CMD=gcloud
TOOL_VERSION="gcloud --version"
TOOL_BREW=cask:gcloud-cli
TOOL_APT=google-cloud-cli
TOOL_APT_REPO="google-cloud-cli|https://packages.cloud.google.com/apt/doc/apt-key.gpg|deb [signed-by=@KEYRING@] https://packages.cloud.google.com/apt cloud-sdk main"

module_check()   { tool_module_check; }
module_install() { tool_module_install; }
