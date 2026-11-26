# Environment: PATH, editor, pager. Sourced first, before Oh My Zsh.

# Homebrew (macOS)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Personal bin directories first; (N/) keeps only those that exist.
typeset -U path PATH
path=(~/.local/bin(N/) ~/bin(N/) ~/go/bin(N/) $path)

export EDITOR=vim
export VISUAL=vim
export PAGER=less
export LESS='-R -F -X'
