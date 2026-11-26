#!/bin/sh
# Runs inside a test container (see tests/run.sh). /t holds the fake remote
# (remote.git) and install.sh as served from main and from tag v0.0.1.
# pass/fail always succeed, so `A && pass || fail` is safe here.
# shellcheck disable=SC2015
set -u

MODE=${1:-supported}
export WSB_REPO=file:///t/remote.git
export BOOTSTRAP_DIR=/root/.workspace-bootstrap
FAILS=0

pass() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✖\033[0m %s\n' "$*"; FAILS=$((FAILS + 1)); }

# Same invocation shape as the README one-liner.
install_from() { # install_from FILE [args...]
  f=$1; shift
  sh -c "$(cat "$f")" "" "$@" > /tmp/out.log 2>&1
}

installed_ref() { sed -n 's/^WSB_REF=//p' "$BOOTSTRAP_DIR/.version" 2>/dev/null; }

expect_ref() { # expect_ref WANT DESCRIPTION
  got=$(installed_ref)
  if [ "$got" = "$1" ]; then pass "$2 → $got"; else fail "$2: wanted $1, got '${got}'"; tail -n 20 /tmp/out.log; fi
}

if [ "$MODE" = unsupported ]; then
  if install_from /t/install-main.sh --unattended; then
    fail "install succeeded on unsupported OS"
  elif grep -q "Unsupported OS" /tmp/out.log; then
    pass "refused: $(grep 'Unsupported OS' /tmp/out.log | sed 's/^.*Unsupported/Unsupported/')"
  else
    fail "failed without the unsupported-OS message"; cat /tmp/out.log
  fi
  [ ! -e "$BOOTSTRAP_DIR" ] && pass "nothing was cloned" || fail "clone dir exists"
  exit "$FAILS"
fi

# The mounted remote is owned by the host user; written by hand because git
# isn't installed yet.
printf '[safe]\n\tdirectory = *\n' > "$HOME/.gitconfig"

# 1. fresh machine (no git/curl), main URL → latest release
command -v git >/dev/null && fail "image already has git (test assumes a bare image)"
install_from /t/install-main.sh --unattended
expect_ref v0.0.2 "main URL installs latest release"
command -v git >/dev/null && command -v curl >/dev/null && pass "git and curl provisioned" || fail "git/curl missing"
grep -q "All done" /tmp/out.log && pass "bootstrap.sh ran to completion" || { fail "bootstrap.sh did not finish"; tail -n 20 /tmp/out.log; }

# 2. re-run is idempotent
install_from /t/install-main.sh --unattended && pass "re-run succeeds" || fail "re-run failed"

# 3. tag URL pins its own version (existing checkout)
install_from /t/install-v0.0.1.sh --unattended
expect_ref v0.0.1 "tag URL pins version (update path)"
[ "$(sed -n 's/^WSB_PINNED_REF=//p' "$BOOTSTRAP_DIR/install.sh")" = '"v0.0.1"' ] \
  && pass "checked-out code is the v0.0.1 tree" || fail "checked-out tree is not v0.0.1"

# 4. tag URL on a fresh machine
rm -rf "$BOOTSTRAP_DIR"
install_from /t/install-v0.0.1.sh --unattended
expect_ref v0.0.1 "tag URL pins version (fresh clone)"

# 5. WSB_REF override
WSB_REF=main install_from /t/install-v0.0.1.sh --unattended
expect_ref main "WSB_REF=main overrides the pin"

# 6. --upgrade goes to the latest release
bash "$BOOTSTRAP_DIR/bootstrap.sh" --upgrade --unattended > /tmp/out.log 2>&1
expect_ref v0.0.2 "bootstrap.sh --upgrade"

# 7. --upgrade=REF
bash "$BOOTSTRAP_DIR/bootstrap.sh" --upgrade=v0.0.1 --unattended > /tmp/out.log 2>&1
expect_ref v0.0.1 "bootstrap.sh --upgrade=v0.0.1"

# 8. version lock: code that doesn't match .version is refused
sed -i 's/^WSB_COMMIT=.*/WSB_COMMIT=0000000000000000000000000000000000000000/' "$BOOTSTRAP_DIR/.version"
if bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended > /tmp/out.log 2>&1; then
  fail "bootstrap ran with mismatched version"
else
  grep -q "does not match the installed version" /tmp/out.log && pass "version mismatch refused" || { fail "wrong error"; cat /tmp/out.log; }
fi

# 9. unknown version fails cleanly
rm -rf "$BOOTSTRAP_DIR"
if WSB_REF=v9.9.9 install_from /t/install-main.sh --unattended; then
  fail "unknown version accepted"
else
  grep -q "not found" /tmp/out.log && pass "unknown version rejected" || { fail "wrong error"; cat /tmp/out.log; }
fi
[ ! -e "$BOOTSTRAP_DIR" ] && pass "failed fresh install leaves no directory" || fail "half-initialised $BOOTSTRAP_DIR left behind"

# 10. option handling
install_from /t/install-main.sh --unattended >/dev/null
bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended --only zsh,vim > /tmp/out.log 2>&1
if grep -q '==> zsh' /tmp/out.log && ! grep -q '==> docker' /tmp/out.log; then pass "--only"; else fail "--only"; cat /tmp/out.log; fi
bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended --skip nope > /tmp/out.log 2>&1 \
  && fail "unknown module accepted" || pass "unknown module rejected"

exit "$FAILS"
