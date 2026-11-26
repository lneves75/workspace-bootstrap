#!/usr/bin/env bash
#
# End-to-end tests for install.sh / bootstrap.sh / release.sh in containers.
#
#   tests/run.sh                 # all images
#   tests/run.sh ubuntu:24.04    # just one
#
# Builds a throwaway git remote from the working tree with two releases
# (v0.0.1, v0.0.2) and runs tests/container.sh inside each image against it.
# Needs docker; nothing outside the temp dir is modified.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPPORTED_IMAGES=(ubuntu:24.04 ubuntu:22.04 debian:12)
UNSUPPORTED_IMAGES=(fedora:41)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/wsb-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# --- build the fake remote --------------------------------------------------
src="$WORK/src"
mkdir -p "$src"
( cd "$ROOT" && tar --exclude=.git --exclude=.version -cf - . ) | ( cd "$src" && tar -xf - )
(
  cd "$src"
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
  git init --quiet -b main
  git add -A
  git commit --quiet -m initial
  scripts/release.sh v0.0.1 >/dev/null
  scripts/release.sh v0.0.2 >/dev/null
  git show v0.0.1:install.sh > "$WORK/install-v0.0.1.sh"
  git show main:install.sh   > "$WORK/install-main.sh"
)
git clone --quiet --bare "$src" "$WORK/remote.git"
cp "$ROOT/tests/container.sh" "$WORK/"

# Sanity checks on release.sh output before going into containers.
grep -qx 'WSB_PINNED_REF="v0.0.1"' "$WORK/install-v0.0.1.sh" || { echo "✖ tag install.sh not pinned"; exit 1; }
grep -qx 'WSB_PINNED_REF=""'       "$WORK/install-main.sh"   || { echo "✖ main install.sh still pinned"; exit 1; }
echo "✔ release.sh pins tags and reopens main"

# --- run --------------------------------------------------------------------
images=("$@")
[[ ${#images[@]} -gt 0 ]] || images=("${SUPPORTED_IMAGES[@]}" "${UNSUPPORTED_IMAGES[@]}")

fail=0
for image in "${images[@]}"; do
  mode=supported
  for u in "${UNSUPPORTED_IMAGES[@]}"; do [[ "$u" == "$image" ]] && mode=unsupported; done
  printf '\n\033[1m=== %s (%s) ===\033[0m\n' "$image" "$mode"
  if docker run --rm -v "$WORK:/t:ro" "$image" sh /t/container.sh "$mode"; then
    printf '\033[1;32mPASS\033[0m %s\n' "$image"
  else
    printf '\033[1;31mFAIL\033[0m %s\n' "$image"
    fail=1
  fi
done
exit $fail
