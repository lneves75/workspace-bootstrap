# General aliases. Oh My Zsh already provides many (ll, la, .., ..., and the
# git plugin's g*); see `alias` for the full list.

alias reload='exec zsh'                 # restart the shell with a fresh config
alias path='print -rl -- $path'         # PATH, one entry per line
alias wsb="$WSB_ROOT/bootstrap.sh"      # re-run / upgrade workspace-bootstrap
alias h='history -i'
alias mkdir='mkdir -p'
