#!/usr/bin/env bash
#
# End-to-end tests for install.sh / bootstrap.sh / release.sh in containers.
#
#   tests/run.sh                 # all images, in parallel
#   tests/run.sh ubuntu:24.04    # just one
#
# Builds a throwaway git remote from the working tree with two releases
# (v0.0.1, v0.0.2) and runs tests/container.sh inside each image against it.
# Needs docker; nothing outside the temp dir is modified.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
SUPPORTED_IMAGES=(ubuntu:24.04 ubuntu:22.04 debian:12)
UNSUPPORTED_IMAGES=(fedora:41)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/wsb-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

make_fake_remote "$ROOT" "$WORK"
cp "$ROOT/tests/container.sh" "$WORK/"

images=("$@")
[[ ${#images[@]} -gt 0 ]] || images=("${SUPPORTED_IMAGES[@]}" "${UNSUPPORTED_IMAGES[@]}")

run_image() { # run_image IMAGE LOG
  local image=$1 log=$2 mode=supported u
  for u in "${UNSUPPORTED_IMAGES[@]}"; do [[ "$u" == "$image" ]] && mode=unsupported; done
  {
    printf '\n\033[1m=== %s (%s) ===\033[0m\n' "$image" "$mode"
    docker run --rm -v "$WORK:/t:ro" "$image" sh /t/container.sh "$mode"
  } > "$log" 2>&1
}

# Images run in parallel; each one's output is printed when it finishes.
pids=() logs=()
for image in "${images[@]}"; do
  log="$WORK/${image//[:\/]/-}.log"
  run_image "$image" "$log" &
  pids+=($!); logs+=("$log")
done

fail=0
for i in "${!images[@]}"; do
  if wait "${pids[$i]}"; then status='\033[1;32mPASS\033[0m'; else status='\033[1;31mFAIL\033[0m'; fail=1; fi
  grep -v -E 'Pulling|Pull complete|Digest:|Status:|Verifying|Download|Unable to find' "${logs[$i]}" || true
  printf "${status} %s (%s checks passed)\n" "${images[$i]}" "$(grep -c '✔' "${logs[$i]}" || true)"
done
exit $fail
