#!/bin/sh
# Runs inside a test container (see tests/run.sh). /t holds the fake remote
# (remote.git) and install.sh as served from main and from tag v0.0.1.
# pass/fail always succeed, so `A && pass || fail` is safe here.
# Messages contain a literal "~", on purpose.
# shellcheck disable=SC2015,SC2088
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
printf '# my old zshrc\n' > "$HOME/.zshrc"     # must end up in the backup
install_from /t/install-main.sh --unattended
expect_ref v0.0.2 "main URL installs latest release"
command -v git >/dev/null && command -v curl >/dev/null && pass "git and curl provisioned" || fail "git/curl missing"
grep -q "All done" /tmp/out.log && pass "bootstrap.sh ran to completion" || { fail "bootstrap.sh did not finish"; tail -n 20 /tmp/out.log; }
grep -q "base-tools: changed (installed: " /tmp/out.log && pass "first run installs base tools" || { fail "base tools not reported as installed"; tail -n 20 /tmp/out.log; }
missing=""
# shellcheck disable=SC2013  # one package name per word
for p in $(sed -e 's/#.*//' "$BOOTSTRAP_DIR/packages/base.apt"); do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing="$missing $p"
done
[ -z "$missing" ] && pass "all base packages installed" || fail "missing packages:$missing"
grep -q "docker: optional, not installed" /tmp/out.log && grep -q "mise: optional, not installed" /tmp/out.log \
  && pass "unattended: optional modules skipped" || fail "optional modules not skipped"

# 1b. zsh module
. "$BOOTSTRAP_DIR/versions.env"
command -v zsh >/dev/null && pass "zsh installed" || fail "zsh missing"
[ "$(git -C "$HOME/.oh-my-zsh" rev-parse HEAD 2>/dev/null)" = "$OMZ_COMMIT" ] \
  && pass "Oh My Zsh at pinned commit" || fail "Oh My Zsh not at $OMZ_COMMIT"
plugins_ok=1
while read -r pname _ pcommit _; do
  case "$pname" in ''|\#*) continue ;; esac
  [ "$(git -C "$HOME/.oh-my-zsh/custom/plugins/$pname" rev-parse HEAD 2>/dev/null)" = "$pcommit" ] || { plugins_ok=0; fail "plugin $pname not at $pcommit"; }
done < "$BOOTSTRAP_DIR/config/zsh/external-plugins.txt"
[ $plugins_ok = 1 ] && pass "external plugins at pinned commits"
[ "$(readlink "$HOME/.zshrc")" = "$BOOTSTRAP_DIR/config/zsh/zshrc" ] && pass "~/.zshrc linked into the repo" || fail "~/.zshrc not linked"
grep -qx '# my old zshrc' "$HOME"/.workspace-bootstrap-backup/*/.zshrc 2>/dev/null \
  && pass "previous ~/.zshrc backed up" || fail "previous ~/.zshrc not backed up"
[ "$(getent passwd root | cut -d: -f7 | xargs basename)" = zsh ] && pass "login shell is zsh" || fail "login shell not zsh"

# An interactive zsh loads the config cleanly, with our plugins, aliases and functions.
zsh -i -c 'print -r -- "PLUGINS=${plugins[*]}"; print -r -- "LAST=${plugins[-1]}"; alias wsb; whence -w mkcd up; print -r -- "HIST=$SAVEHIST"' \
  > /tmp/zsh.out 2> /tmp/zsh.err
if [ -s /tmp/zsh.err ]; then fail "zsh startup wrote to stderr:"; cat /tmp/zsh.err; else pass "zsh starts without errors"; fi
grep -q '^PLUGINS=git .*zsh-autosuggestions zsh-syntax-highlighting$' /tmp/zsh.out && pass "plugins loaded" || { fail "plugins"; cat /tmp/zsh.out; }
grep -q '^LAST=zsh-syntax-highlighting$' /tmp/zsh.out && pass "zsh-syntax-highlighting loads last" || fail "plugin order"
grep -q "^wsb=.*bootstrap.sh" /tmp/zsh.out && grep -q '^mkcd: function$' /tmp/zsh.out && pass "aliases and functions defined" || { fail "aliases/functions"; cat /tmp/zsh.out; }
grep -q '^HIST=100000$' /tmp/zsh.out && pass "options.zsh applied after Oh My Zsh" || fail "options.zsh"

# Personal files are picked up.
mkdir -p "$HOME/.zshrc.d"
printf 'WSB_EXTRA_PLUGINS=(extract)\n' > "$HOME/.zshrc.pre.local"
printf 'alias fromd=1\n' > "$HOME/.zshrc.d/mine.zsh"
printf 'alias fromlocal=1\n' > "$HOME/.zshrc.local"
zsh -i -c 'print -r -- "${plugins[*]}"; alias fromd fromlocal' > /tmp/zsh.out 2>&1
grep -q ' extract ' /tmp/zsh.out && grep -q '^fromd=1$' /tmp/zsh.out && grep -q '^fromlocal=1$' /tmp/zsh.out \
  && pass "~/.zshrc.pre.local, ~/.zshrc.d and ~/.zshrc.local are loaded" || { fail "personal files"; cat /tmp/zsh.out; }
rm -rf "$HOME/.zshrc.d" "$HOME/.zshrc.pre.local" "$HOME/.zshrc.local"

# An Oh My Zsh installed some other way (on a branch) is left alone.
H2=/tmp/home2; mkdir -p "$H2/.oh-my-zsh"
git -C "$H2/.oh-my-zsh" init -q -b master
git -C "$H2/.oh-my-zsh" -c user.name=t -c user.email=t@x commit -q --allow-empty -m mine
mine=$(git -C "$H2/.oh-my-zsh" rev-parse HEAD)
HOME=$H2 WSB_NO_CHSH=1 bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended --only zsh > /tmp/out.log 2>&1
[ "$(git -C "$H2/.oh-my-zsh" rev-parse HEAD)" = "$mine" ] && grep -q "not managed by workspace-bootstrap, left as is" /tmp/out.log \
  && pass "user's own Oh My Zsh checkout left untouched" || { fail "user's Oh My Zsh was modified"; cat /tmp/out.log; }

# 2. re-run is idempotent: succeeds and changes nothing
cp /tmp/out.log /tmp/first.log
install_from /t/install-main.sh --unattended && pass "re-run succeeds" || fail "re-run failed"
if grep -q ": changed (" /tmp/out.log; then
  fail "re-run changed something:"; grep ": changed (" /tmp/out.log
else
  pass "re-run changes nothing"
fi
grep -q "apt index is fresh" /tmp/out.log && pass "re-run skips apt update" || fail "re-run refreshed apt index"
grep -q "base-tools: already set up" /tmp/out.log && pass "base-tools reported as already set up" || fail "base-tools status"

# 2b. optional modules: --with selects without asking
bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended --with docker > /tmp/out.log 2>&1
grep -q "docker: not implemented yet" /tmp/out.log && grep -q "mise: optional, not installed" /tmp/out.log \
  && pass "--with docker selects only docker" || { fail "--with"; cat /tmp/out.log; }

# 2c. interactive prompts (through a pseudo-terminal): Enter = No, y = yes
if command -v script >/dev/null; then
  { sleep 1; printf '\n'; sleep 1; printf 'y\n'; sleep 3; } \
    | script -qec "bash $BOOTSTRAP_DIR/bootstrap.sh" /dev/null > /tmp/out.log 2>&1
  grep -q "Install Go, Python and Node (via mise)? \[y/N\]" /tmp/out.log && pass "prompts with default No" || { fail "no prompt"; cat /tmp/out.log; }
  grep -q "mise: optional, not installed" /tmp/out.log && pass "Enter declines (default No)" || { fail "Enter did not decline"; cat /tmp/out.log; }
  grep -q "docker: not implemented yet" /tmp/out.log && pass "'y' accepts" || { fail "'y' not accepted"; cat /tmp/out.log; }
else
  fail "'script' not available for prompt test"
fi

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
