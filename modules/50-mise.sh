# shellcheck shell=bash disable=SC2034  # MODULE_* are read by bootstrap.sh
#
# Module: mise (optional)
# mise, then Go, Python and Node from config/mise.toml.
#
# Optional: asked interactively (default No); skipped in --unattended mode
# unless selected with --with mise (or --only mise).
#
# TODO(milestone 5)

MODULE_OPTIONAL=1
MODULE_PROMPT="Install Go, Python and Node (via mise)?"

module_check()   { return 1; }
module_install() { return "$WSB_RC_TODO"; }
