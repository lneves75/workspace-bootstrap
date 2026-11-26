# Shell options. Sourced after Oh My Zsh so these take precedence.

# History
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt extended_history       # save timestamps
setopt share_history          # share history between sessions
setopt hist_ignore_all_dups   # drop older duplicates
setopt hist_ignore_space      # commands starting with a space are not saved
setopt hist_reduce_blanks
setopt hist_verify            # show !! expansions before running them

# Navigation and input
setopt auto_cd                # `dir` alone means `cd dir`
setopt interactive_comments   # allow # comments on the command line
setopt no_beep
