#!/usr/bin/env bash
#
# End-to-end test on a real macOS machine: installs everything (including
# the optional mise and docker modules) into the CURRENT USER'S HOME.
# Meant for throwaway CI runners only, so it refuses to run unless CI=true.
#
#   CI=true tests/macos.sh
# pass/fail always succeed, so `A && pass || fail` is safe here.
# shellcheck disable=SC2015
set -uo pipefail

[[ "${CI:-}" == true ]] || { echo "Refusing to run outside CI (it changes \$HOME). Set CI=true on a throwaway machine."; exit 2; }
[[ "$(uname -s)" == Darwin ]] || { echo "macOS only"; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/wsb-mac.XXXXXX")
make_fake_remote "$ROOT" "$WORK" || exit 1

export WSB_REPO="file://$WORK/remote.git"
export BOOTSTRAP_DIR="$HOME/.workspace-bootstrap"
FAILS=0
pass() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✖\033[0m %s\n' "$*"; FAILS=$((FAILS + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

TOOLS=kubectl,terraform,opentofu,terragrunt,flux,gh,aws,azure,gcloud

section "first run: everything, unattended"
printf '# pre-existing zshrc\n' >> "$HOME/.zshrc"
if WSB_GIT_NAME="CI" WSB_GIT_EMAIL=ci@example.com \
   sh -c "$(cat "$WORK/install-main.sh")" "" --unattended --with "mise,docker,$TOOLS" > "$WORK/first.log" 2>&1; then
  pass "install succeeded"
else
  fail "install failed"; tail -n 60 "$WORK/first.log"
fi
sed -n '/==> Summary/,$p' "$WORK/first.log"
[[ "$(sed -n 's/^WSB_REF=//p' "$BOOTSTRAP_DIR/.version")" == v0.0.2 ]] && pass "latest release installed" || fail "wrong version"

section "pinned languages in an interactive zsh"
src="$BOOTSTRAP_DIR/config/mise/workspace-bootstrap.toml"
pin() { sed -n "s/^$1 = \"\(.*\)\"/\1/p" "$src"; }
out=$(zsh -i -c 'go version; python --version; node --version' 2>&1)
grep -q "go$(pin go) " <<< "$out" && pass "go $(pin go)" || { fail "go"; echo "$out"; }
grep -q "Python $(pin python)" <<< "$out" && pass "python $(pin python)" || { fail "python"; echo "$out"; }
grep -q "v$(pin node)" <<< "$out" && pass "node $(pin node)" || { fail "node"; echo "$out"; }

section "docker (colima is installed but not started in --unattended mode)"
command -v docker >/dev/null && pass "docker CLI" || fail "docker CLI missing"
docker compose version >/dev/null 2>&1 && pass "compose plugin registered" || fail "compose plugin"
docker buildx version >/dev/null 2>&1 && pass "buildx plugin registered" || fail "buildx plugin"
if brew list --versions colima >/dev/null 2>&1; then
  jq -e '.cliPluginsExtraDirs | index("'"$(brew --prefix)"'/lib/docker/cli-plugins")' "$HOME/.docker/config.json" >/dev/null \
    && pass "cliPluginsExtraDirs set in ~/.docker/config.json" || fail "cliPluginsExtraDirs"
else
  pass "pre-existing Docker detected; colima not installed"
fi

section "optional CLI tools (Homebrew, or already on the runner)"
for c in kubectl terraform tofu terragrunt flux gh aws az gcloud yq jq; do
  command -v "$c" >/dev/null && pass "$c: $(command -v "$c")" || fail "$c missing"
done
out=$(zsh -i -c 'print -r -- "THEME=$ZSH_THEME"; alias k tf; for c in kubectl terraform gh yq; do (( $+_comps[$c] )) && print "COMP $c"; done' 2>&1)
grep -qx 'THEME=agnoster' <<< "$out" && pass "theme agnoster" || { fail "theme"; echo "$out"; }
grep -qx 'k=kubectl' <<< "$out" && grep -qx 'tf=terraform' <<< "$out" && pass "aliases k, tf" || { fail "aliases"; echo "$out"; }
[ "$(grep -c '^COMP ' <<< "$out")" = 4 ] && pass "completions (kubectl, terraform, gh, yq)" || { fail "completions"; echo "$out"; }
vimout=$(vim -N -u "$HOME/.vimrc" -i NONE -es -c 'call writefile([get(g:, "colors_name", "none") . exists("g:loaded_fugitive")], "/dev/stdout")' -c 'qa!' </dev/null)
[ "$vimout" = PaperColor1 ] && pass "vim: PaperColor + plugins" || fail "vim plugins ($vimout)"

section "second run changes nothing"
bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended > "$WORK/second.log" 2>&1 || fail "second run failed"
if grep -q ": changed (" "$WORK/second.log"; then fail "second run changed:"; grep ": changed (" "$WORK/second.log"; else pass "nothing changed"; fi

section "doctor"
if bash "$BOOTSTRAP_DIR/bootstrap.sh" --doctor > "$WORK/doctor.log" 2>&1; then pass "doctor: no problems"; else fail "doctor:"; grep '✖' "$WORK/doctor.log"; fi
cat "$WORK/doctor.log"

section "uninstall restores the original ~/.zshrc"
bash "$BOOTSTRAP_DIR/scripts/uninstall.sh" --yes > "$WORK/uninstall.log" 2>&1 || fail "uninstall failed"
[[ ! -L "$HOME/.zshrc" ]] && grep -q '# pre-existing zshrc' "$HOME/.zshrc" && pass "restored" || { fail "not restored"; cat "$WORK/uninstall.log"; }

echo
[[ $FAILS -eq 0 ]] && echo "PASS macOS" || echo "FAIL macOS ($FAILS)"
exit "$FAILS"
