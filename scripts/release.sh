#!/usr/bin/env bash
#
# Cut a release so that the tag's install.sh knows its own version.
#
#   scripts/release.sh v1.2.3          # create commits + tag locally
#   scripts/release.sh v1.2.3 --push   # ...and push main and the tag
#
# Result on main:
#   ... ── release v1.2.3 (tag v1.2.3, WSB_PINNED_REF="v1.2.3")
#       ── chore: reopen main after v1.2.3 (WSB_PINNED_REF="")
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT/install.sh"
BRANCH="${RELEASE_BRANCH:-main}"

die() { printf '✖ %s\n' "$*" >&2; exit 1; }

version=${1:-}
push=0
[[ "${2:-}" == --push ]] && push=1
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Usage: $0 vMAJOR.MINOR.PATCH [--push]"

cd "$ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository."
[[ "$(git symbolic-ref --short HEAD 2>/dev/null)" == "$BRANCH" ]] || die "Releases are cut from '$BRANCH'."
[[ -z "$(git status --porcelain)" ]] || die "Working tree is not clean."
git rev-parse -q --verify "refs/tags/$version" >/dev/null && die "Tag $version already exists."
grep -qx 'WSB_PINNED_REF=""' "$INSTALL" || die "install.sh does not contain the line WSB_PINNED_REF=\"\"."

set_pin() { # set_pin VALUE
  local tmp
  tmp=$(mktemp)
  sed "s/^WSB_PINNED_REF=\".*\"\$/WSB_PINNED_REF=\"$1\"/" "$INSTALL" > "$tmp"
  cat "$tmp" > "$INSTALL"   # keep file mode
  rm -f "$tmp"
  grep -qx "WSB_PINNED_REF=\"$1\"" "$INSTALL" || die "Failed to update WSB_PINNED_REF."
}

set_pin "$version"
git add "$INSTALL"
git commit --quiet -m "release $version"
git tag -a "$version" -m "workspace-bootstrap $version"

set_pin ""
git add "$INSTALL"
git commit --quiet -m "chore: reopen $BRANCH after $version"

printf '✔ Tagged %s (%s)\n' "$version" "$(git rev-parse --short "$version^{commit}")"

if [[ $push == 1 ]]; then
  git push origin "$BRANCH" "$version"
  printf '✔ Pushed %s and %s\n' "$BRANCH" "$version"
else
  printf 'Next: git push origin %s %s\n' "$BRANCH" "$version"
fi
