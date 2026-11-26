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
cp /tmp/out.log /tmp/first.log
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

# 1c. vim module
command -v vim >/dev/null && pass "vim installed" || fail "vim missing"
[ "$(readlink "$HOME/.vimrc")" = "$BOOTSTRAP_DIR/config/vim/vimrc" ] && pass "~/.vimrc linked into the repo" || fail "~/.vimrc not linked"
vim -N -u "$HOME/.vimrc" -i NONE -es -c 'redir! > /tmp/vim.out' -c 'set number? shiftwidth?' -c 'echo "ERR=" . v:errmsg' -c 'redir END' -c 'qa!' </dev/null
grep -q 'shiftwidth=2' /tmp/vim.out && grep -q '^ERR=$' /tmp/vim.out && pass "vimrc loads without errors" || { fail "vimrc"; cat /tmp/vim.out; }
[ -d "$HOME/.vim/undo" ] && pass "vim undo/swap dirs created outside projects" || fail "~/.vim/undo missing"

# 1d. git module (unattended, no identity given)
head -n 3 "$HOME/.gitconfig" | grep -qF "path = $BOOTSTRAP_DIR/config/git/gitconfig" \
  && pass "~/.gitconfig includes shared defaults at the top" || { fail "include missing"; cat "$HOME/.gitconfig"; }
[ ! -L "$HOME/.gitconfig" ] && pass "~/.gitconfig stays a personal file (not a symlink)" || fail "~/.gitconfig is a symlink"
[ "$(git config --global --get safe.directory)" = '*' ] && pass "existing ~/.gitconfig content preserved" || fail "existing content lost"
[ "$(git config --get init.defaultBranch)" = main ] && pass "shared git defaults active" || fail "shared defaults not active"
[ "$(readlink "$HOME/.config/git/ignore")" = "$BOOTSTRAP_DIR/config/git/ignore" ] && pass "global gitignore linked" || fail "global gitignore not linked"
rm -rf /tmp/repo && git init -q /tmp/repo && touch /tmp/repo/.DS_Store
git -C /tmp/repo check-ignore -q .DS_Store && pass "global gitignore applies" || fail ".DS_Store not ignored"
grep -q "user.name not set" /tmp/first.log \
  && pass "unattended: missing identity reported, not prompted" || fail "identity warning missing"

# Personal settings override the shared defaults.
git config --global init.defaultBranch trunk
[ "$(git config --get init.defaultBranch)" = trunk ] && pass "personal ~/.gitconfig overrides shared defaults" || fail "override"
git config --global --unset init.defaultBranch

# Identity: interactive prompt (through a pseudo-terminal) ...
{ sleep 1; printf 'Test User\n'; sleep 1; printf 'test@example.com\n'; sleep 2; } \
  | script -qec "bash $BOOTSTRAP_DIR/bootstrap.sh --only git" /dev/null > /tmp/out.log 2>&1
[ "$(git config --global user.name)" = "Test User" ] && [ "$(git config --global user.email)" = test@example.com ] \
  && pass "git identity asked and saved" || { fail "git identity prompt"; cat /tmp/out.log; }
# ... or from WSB_GIT_NAME / WSB_GIT_EMAIL when unattended
H3=/tmp/home3; mkdir -p "$H3"; cp "$HOME/.gitconfig" "$H3/.gitconfig"
HOME=$H3 git config --global --unset user.name; HOME=$H3 git config --global --unset user.email
HOME=$H3 WSB_GIT_NAME="CI Bot" WSB_GIT_EMAIL=ci@example.com bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended --only git > /tmp/out.log 2>&1
[ "$(HOME=$H3 git config --global user.name)" = "CI Bot" ] && pass "identity from WSB_GIT_NAME/WSB_GIT_EMAIL" || { fail "identity from env"; cat /tmp/out.log; }
[ "$(grep -c 'path = ' "$H3/.gitconfig")" = 1 ] && pass "include not duplicated" || { fail "include duplicated"; cat "$H3/.gitconfig"; }

# 2. re-run is idempotent: succeeds and changes nothing
install_from /t/install-main.sh --unattended && pass "re-run succeeds" || fail "re-run failed"
if grep -q ": changed (" /tmp/out.log; then
  fail "re-run changed something:"; grep ": changed (" /tmp/out.log
else
  pass "re-run changes nothing"
fi
grep -q "apt index is fresh" /tmp/out.log && pass "re-run skips apt update" || fail "re-run refreshed apt index"
grep -q "base-tools: already set up" /tmp/out.log && pass "base-tools reported as already set up" || fail "base-tools status"

# 2b. interactive prompts (through a pseudo-terminal): Enter = No, y = yes.
# Input comes from a FIFO kept open by a background writer, so the
# pseudo-terminal stays open while docker installs.
if command -v script >/dev/null; then
  rm -f /tmp/in; mkfifo /tmp/in
  ( sleep 1; printf '\n'; sleep 1; printf 'y\n'; sleep 1800 ) > /tmp/in &
  feeder=$!
  script -qec "bash $BOOTSTRAP_DIR/bootstrap.sh" /dev/null < /tmp/in > /tmp/out.log 2>&1
  kill "$feeder" 2>/dev/null
  grep -q "Install Go, Python and Node (via mise)? \[y/N\]" /tmp/out.log && pass "prompts with default No" || { fail "no prompt"; cat /tmp/out.log; }
  grep -q "mise: optional, not installed" /tmp/out.log && pass "Enter declines (default No)" || { fail "Enter did not decline"; cat /tmp/out.log; }
  grep -q "docker: changed (" /tmp/out.log && pass "'y' accepts: docker installed" || { fail "'y' not accepted"; sed -n '/==> docker/,$p' /tmp/out.log; }
else
  fail "'script' not available for prompt test"
fi

# 2c. docker module
for p in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || fail "package $p missing"
done
[ -f /etc/apt/sources.list.d/docker.list ] && grep -q "https://download.docker.com/linux/" /etc/apt/sources.list.d/docker.list \
  && pass "docker-ce from Docker's apt repository" || fail "docker apt repository"
docker --version >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && docker buildx version >/dev/null 2>&1 \
  && pass "docker CLI with compose and buildx plugins" || fail "docker CLI/plugins"
grep -q "systemd is not running" /tmp/out.log && pass "no systemd: daemon start left to the user" || fail "systemd message"

# --with selects without asking; an installed optional module reports "already set up"
bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended --with docker > /tmp/out.log 2>&1
grep -q "docker: already set up" /tmp/out.log && grep -q "mise: optional, not installed" /tmp/out.log \
  && ! grep -q ": changed (" /tmp/out.log \
  && pass "--with docker: already set up, nothing changed, mise untouched" || { fail "--with docker re-run"; sed -n '/Summary/,$p' /tmp/out.log; }

# Non-root user with sudo: lazy sudo + docker group membership
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo >/dev/null 2>&1
useradd -m -s /bin/bash dev
printf 'dev ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/dev
printf '[safe]\n\tdirectory = *\n' > /home/dev/.gitconfig && chown dev: /home/dev/.gitconfig
chmod 755 "$HOME"
su - dev -c "WSB_NO_CHSH=1 bash $BOOTSTRAP_DIR/bootstrap.sh --unattended --only docker" > /tmp/out.log 2>&1
id -nG dev | tr ' ' '\n' | grep -qx docker && grep -q "added dev to the docker group" /tmp/out.log \
  && pass "non-root user added to the docker group (via sudo)" || { fail "docker group"; cat /tmp/out.log; }
su - dev -c "WSB_NO_CHSH=1 bash $BOOTSTRAP_DIR/bootstrap.sh --unattended --only docker" > /tmp/out.log 2>&1
grep -q "docker: already set up" /tmp/out.log && pass "non-root re-run: already set up" || { fail "non-root re-run"; cat /tmp/out.log; }

# 2d. mise module (optional): Go, Python, Node at the pinned versions
MISE_SRC="$BOOTSTRAP_DIR/config/mise/workspace-bootstrap.toml"
MISE_DEST="$HOME/.config/mise/conf.d/workspace-bootstrap.toml"
MISE_RECORD="$HOME/.local/state/workspace-bootstrap/managed$MISE_DEST"
pin() { sed -n "s/^$1 = \"\(.*\)\"/\1/p" "$MISE_SRC"; }
GO_V=$(pin go); PY_V=$(pin python); NODE_V=$(pin node)

command -v mise >/dev/null && fail "mise installed although never selected" || pass "mise not installed unless selected"
bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended --with mise > /tmp/out.log 2>&1
grep -q "mise: changed (" /tmp/out.log && pass "--with mise installs mise and languages" || { fail "mise install"; tail -n 40 /tmp/out.log; }
[ -f "$MISE_DEST" ] && [ ! -L "$MISE_DEST" ] && cmp -s "$MISE_SRC" "$MISE_DEST" \
  && pass "mise config installed as a managed copy (not a symlink)" || fail "mise config copy"

zsh -i -c 'go version; python --version; node --version' > /tmp/lang.out 2>&1
grep -q "go$GO_V " /tmp/lang.out && pass "go $GO_V active in zsh" || { fail "go $GO_V"; cat /tmp/lang.out; }
grep -q "Python $PY_V" /tmp/lang.out && pass "python $PY_V active in zsh" || { fail "python $PY_V"; cat /tmp/lang.out; }
grep -q "v$NODE_V" /tmp/lang.out && pass "node $NODE_V active in zsh" || { fail "node $NODE_V"; cat /tmp/lang.out; }

bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended --with mise > /tmp/out.log 2>&1
grep -q "mise: already set up" /tmp/out.log && ! grep -q ": changed (" /tmp/out.log \
  && pass "mise re-run changes nothing" || { fail "mise re-run"; sed -n '/Summary/,$p' /tmp/out.log; }

# Once installed, an interactive run no longer asks about it.
{ sleep 1; printf '\n'; sleep 3; } | script -qec "bash $BOOTSTRAP_DIR/bootstrap.sh" /dev/null > /tmp/out.log 2>&1
! grep -q "Install Go, Python and Node" /tmp/out.log && grep -q "mise: already set up" /tmp/out.log \
  && pass "installed optional module is not asked again" || { fail "asked again"; sed -n '/Summary/,$p' /tmp/out.log; }

# A copy changed by the user (e.g. `mise use -g`) is kept.
printf '# my change\n' >> "$MISE_DEST"
bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended --with mise > /tmp/out.log 2>&1
grep -q '^# my change$' "$MISE_DEST" && grep -q "mise: already set up" /tmp/out.log \
  && pass "locally changed mise config kept" || { fail "local change lost"; sed -n '/==> mise/,/==>/p' /tmp/out.log; }

# Our own outdated copy is updated to the new pins.
printf '[tools]\ngo = "1.0.0"\n' > "$MISE_DEST"; cp "$MISE_DEST" "$MISE_RECORD"
bash "$BOOTSTRAP_DIR/bootstrap.sh" --unattended --with mise > /tmp/out.log 2>&1
cmp -s "$MISE_SRC" "$MISE_DEST" && grep -q "updated ~/.config/mise/conf.d/workspace-bootstrap.toml" /tmp/out.log \
  && pass "outdated managed copy updated" || { fail "managed copy not updated"; sed -n '/==> mise/,/==>/p' /tmp/out.log; }

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
