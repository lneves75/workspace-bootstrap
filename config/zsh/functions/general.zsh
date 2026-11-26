# General-purpose shell functions.

# mkcd DIR: create DIR (and parents) and cd into it.
mkcd() {
  [[ -n $1 ]] || { print -u2 "usage: mkcd DIR"; return 1; }
  mkdir -p -- "$1" && cd -- "$1"
}

# up [N]: go up N directories (default 1).
up() {
  local n=${1:-1}
  [[ $n == <-> ]] || { print -u2 "usage: up [N]"; return 1; }
  cd "${(pl:$((n * 3))::../:)}"
}

# serve [PORT]: serve the current directory over HTTP (default port 8000).
serve() {
  python3 -m http.server "${1:-8000}"
}

# port PORT: show which process is listening on PORT.
port() {
  [[ -n $1 ]] || { print -u2 "usage: port PORT"; return 1; }
  if (( $+commands[lsof] )); then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN
  else
    ss -ltnp "sport = :$1"
  fi
}
