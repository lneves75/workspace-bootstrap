# shellcheck shell=bash
#
# Module: base-tools
# Everyday CLI tools from packages/base.brew or packages/base.apt.

module_install() {
  pkg_ensure_list base
}
