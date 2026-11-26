# shellcheck shell=bash disable=SC2034  # MODULE_* are read by bootstrap.sh
#
# Module: docker (optional)
# colima + docker CLI on macOS, docker-ce on Debian/Ubuntu.
#
# Optional: asked interactively (default No); skipped in --unattended mode
# unless selected with --with docker (or --only docker).
#
# TODO(milestone 6)

MODULE_OPTIONAL=1
MODULE_PROMPT="Install Docker (colima on macOS, docker-ce on Debian/Ubuntu)?"

module_check()   { return 1; }
module_install() { return "$WSB_RC_TODO"; }
