# Oh My Zsh: theme, plugins, then load it.

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"
ZSH_THEME="${ZSH_THEME:-robbyrussell}"

# Oh My Zsh is pinned by workspace-bootstrap (versions.env), so its own
# updater is off. Run `wsb --upgrade` to update it with everything else.
zstyle ':omz:update' mode disabled

# Avoid the interactive "insecure directories" prompt (e.g. group-writable
# Homebrew directories).
ZSH_DISABLE_COMPFIX=true

# Bundled plugins: https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins
# External ones (zsh-*) come from external-plugins.txt.
# Add your own with WSB_EXTRA_PLUGINS=(...) in ~/.zshrc.pre.local.
# zsh-syntax-highlighting must stay last.
plugins=(
  git
  colored-man-pages
  docker
  docker-compose
  golang
  python
  node
  npm
  mise
  $WSB_EXTRA_PLUGINS
  zsh-autosuggestions
  zsh-syntax-highlighting
)

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
