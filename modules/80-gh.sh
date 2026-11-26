# shellcheck shell=bash disable=SC2034  # MODULE_* and TOOL_* are read by bootstrap.sh / lib/tools.sh
#
# Module: gh (optional): GitHub CLI
# Logic in lib/tools.sh. Asked with default No; remembered once chosen.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install the GitHub CLI (gh)?"

TOOL_NAME="GitHub CLI"
TOOL_CMD=gh
TOOL_VERSION="gh --version"
TOOL_BREW=gh
TOOL_APT=gh
TOOL_APT_REPO="github-cli|https://cli.github.com/packages/githubcli-archive-keyring.gpg|deb [arch=@ARCH@ signed-by=@KEYRING@] https://cli.github.com/packages stable main"

module_check()   { tool_module_check; }
module_install() { tool_module_install; }
