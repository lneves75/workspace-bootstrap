# Oh My Zsh: theme, plugins, then load it.

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"
# agnoster unless ZSH_THEME is already defined (e.g. in ~/.zshrc.pre.local).
# An empty ZSH_THEME="" keeps meaning "no theme". agnoster needs a Powerline-
# or Nerd-Font-patched terminal font for its separators; set DEFAULT_USER to
# your user name to hide user@host on your own machine.
ZSH_THEME="${ZSH_THEME-agnoster}"
# agnoster builds its glyphs in the en_US.UTF-8 locale; where that locale is
# missing (minimal Linux installs) it would print "character not in range" at
# every prompt, so fall back to the default theme there. bootstrap generates
# the locale on Debian/Ubuntu.
if [[ $ZSH_THEME == agnoster && $OSTYPE != darwin* ]] \
   && ! locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
  ZSH_THEME=robbyrussell
fi

# Oh My Zsh is pinned by workspace-bootstrap (versions.env), so its own
# updater is off. Run `wsb --upgrade` to update it with everything else.
zstyle ':omz:update' mode disabled

# Avoid the interactive "insecure directories" prompt (e.g. group-writable
# Homebrew directories).
ZSH_DISABLE_COMPFIX=true

# Bundled plugins: https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins
# External ones (zsh-*) come from external-plugins.txt.
# Add your own with WSB_EXTRA_PLUGINS=(...) in ~/.zshrc.pre.local.
plugins=(
  git
  colored-man-pages
  compleat
  copyfile
  encode64
  docker
  docker-compose
  golang
  python
  node
  npm
  mise
)

# Plugins for the optional CLI tools (completions, aliases), enabled only when
# the tool is installed:  command → plugin
() {
  local cmd plugin
  for cmd plugin in \
    kubectl    kubectl \
    terraform  terraform \
    tofu       opentofu \
    terragrunt terragrunt \
    flux       fluxcd \
    gh         gh \
    aws        aws \
    az         azure \
    gcloud     gcloud
  do
    (( $+commands[$cmd] )) && plugins+=($plugin)
  done
}

# zsh-syntax-highlighting must stay last.
plugins+=($WSB_EXTRA_PLUGINS zsh-autosuggestions zsh-syntax-highlighting)

# Keep only plugins that are installed, so a missing one doesn't break startup.
() {
  local p kept=()
  for p in $plugins; do
    [[ -d $ZSH_CUSTOM/plugins/$p || -d $ZSH/plugins/$p ]] && kept+=($p)
  done
  plugins=($kept)
}

if [[ -r $ZSH/oh-my-zsh.sh ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  print -u2 "workspace-bootstrap: Oh My Zsh not found at $ZSH. Run: $WSB_ROOT/bootstrap.sh --only zsh"
fi
