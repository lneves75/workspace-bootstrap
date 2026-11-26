# shellcheck shell=bash
#
# Module: zsh
# zsh, Oh My Zsh (pinned), plugins, zshrc, chsh.
#
# Contract (see bootstrap.sh):
#   module_check    return 0 if everything is already set up (nothing to do)
#   module_install  install/configure; return 0 on success,
#                   $WSB_RC_TODO if not implemented, anything else on failure
#
# TODO(milestone 3)

module_check()   { return 1; }
module_install() { return "$WSB_RC_TODO"; }
