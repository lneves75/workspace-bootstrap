# Helper for completions/*.zsh (loaded first: "_" sorts before letters).
#
# _wsb_cached_completion CMD GENERATOR...
# Register zsh completion for CMD from the output of GENERATOR (e.g.
# `yq shell-completion zsh`), cached in Oh My Zsh's completion cache and
# regenerated when CMD's binary is newer than the cache. Does nothing when
# CMD is not installed, or when a completion for it already exists.
_wsb_cached_completion() {
  local cmd=$1; shift
  (( $+commands[$cmd] )) || return 0
  (( $+_comps[$cmd] )) && return 0
  local cache="${ZSH_CACHE_DIR:-$HOME/.cache}/completions/_$cmd"
  if [[ ! -s $cache || ${commands[$cmd]:A} -nt $cache ]]; then
    mkdir -p "${cache:h}"
    "$@" > "$cache" 2>/dev/null || { rm -f "$cache"; return 0; }
  fi
  source "$cache"
}
