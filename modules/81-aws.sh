# shellcheck shell=bash disable=SC2034  # MODULE_* and TOOL_* are read by bootstrap.sh / lib/tools.sh
#
# Module: aws (optional): AWS CLI
# Logic in lib/tools.sh. Asked with default No; remembered once chosen.

MODULE_OPTIONAL=1
MODULE_PROMPT="Install the AWS CLI (v2)?"

TOOL_NAME="AWS CLI"
TOOL_CMD=aws
TOOL_VERSION="aws --version"
TOOL_BREW=awscli
# No apt package for v2: AWS's installer zip, pinned and checksum-verified
# (versions.env records how the sums were checked against AWS's signature).
# shellcheck source=versions.env
source "$WSB_ROOT/versions.env"
TOOL_PINNED=$AWSCLI_VERSION

tool_install_pinned() {
  local sha_var="AWSCLI_SHA256_$WSB_ARCH" machine tmp
  case "$WSB_ARCH" in amd64) machine=x86_64 ;; arm64) machine=aarch64 ;; esac
  tmp=$(mktemp -d)
  download_verified "https://awscli.amazonaws.com/awscli-exe-linux-$machine-$AWSCLI_VERSION.zip" \
    "${!sha_var}" "$tmp/awscli.zip" || { rm -rf "$tmp"; return 1; }
  unzip -q "$tmp/awscli.zip" -d "$tmp"
  as_root "$tmp/aws/install" --bin-dir "$WSB_BIN_DIR" --install-dir /usr/local/aws-cli --update >/dev/null
  rm -rf "$tmp"
}

module_check()   { tool_module_check; }
module_install() { tool_module_install; }
