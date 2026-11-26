# Git aliases on top of the Oh My Zsh git plugin
# (https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/git).

alias gundo='git reset --soft HEAD~1'   # undo last commit, keep the changes staged
alias gwip='git add -A && git commit --no-verify -m "wip"'
alias glast='git log -1 --stat'
