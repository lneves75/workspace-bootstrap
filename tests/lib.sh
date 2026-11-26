# shellcheck shell=bash
#
# Test helpers shared by tests/run.sh (Linux containers) and tests/macos.sh.

# make_fake_remote ROOT WORK
# Build a throwaway git remote from the working tree at ROOT, with two
# releases (v0.0.1, v0.0.2) cut by scripts/release.sh. Creates:
#   WORK/remote.git          bare repository to install from
#   WORK/install-main.sh     install.sh as served from main
#   WORK/install-v0.0.1.sh   install.sh as served from tag v0.0.1
make_fake_remote() {
  local root=$1 work=$2 src="$2/src"
  mkdir -p "$src"
  ( cd "$root" && tar --exclude=.git --exclude=.version -cf - . ) | ( cd "$src" && tar -xf - )
  (
    cd "$src" || exit 1
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
    export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
    git init --quiet -b main
    git add -A
    git commit --quiet -m initial
    scripts/release.sh v0.0.1 >/dev/null
    scripts/release.sh v0.0.2 >/dev/null
    git show v0.0.1:install.sh > "$work/install-v0.0.1.sh"
    git show main:install.sh   > "$work/install-main.sh"
  )
  git clone --quiet --bare "$src" "$work/remote.git"

  grep -qx 'WSB_PINNED_REF="v0.0.1"' "$work/install-v0.0.1.sh" || { echo "✖ tag install.sh not pinned"; return 1; }
  grep -qx 'WSB_PINNED_REF=""'       "$work/install-main.sh"   || { echo "✖ main install.sh still pinned"; return 1; }
  echo "✔ release.sh pins tags and reopens main"
}
