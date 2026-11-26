# shellcheck shell=bash
#
# Idempotent helpers for files, symlinks and pinned git checkouts.
# All of them check first, act only when needed, call mark_changed for
# real changes and respect --dry-run.

# Short form of a path for log lines: /home/me/.zshrc -> ~/.zshrc
_tilde() { printf '%s' "${1/#$HOME/~}"; }

# link_file SRC DEST
# Make DEST a symlink to SRC. Anything already at DEST is moved to
# $WSB_BACKUP_DIR first (keeping its path relative to $HOME).
link_file() {
  local src=$1 dest=$2 backup rel
  [[ -e "$src" ]] || { log_err "link source missing: $src"; return 1; }

  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    log_ok "$(_tilde "$dest") already linked"
    return 0
  fi

  if [[ "${WSB_DRY_RUN:-0}" == 1 ]]; then
    if [[ -e "$dest" || -L "$dest" ]]; then
      log_info "would back up $(_tilde "$dest") and link it to $(_tilde "$src")"
    else
      log_info "would link $(_tilde "$dest") → $(_tilde "$src")"
    fi
    mark_changed "would link $(_tilde "$dest")"
    return 0
  fi

  if [[ -e "$dest" || -L "$dest" ]]; then
    rel=${dest#"$HOME"/}
    backup="$WSB_BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$backup")"
    mv "$dest" "$backup"
    log_warn "existing $(_tilde "$dest") moved to $(_tilde "$backup")"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  log_ok "linked $(_tilde "$dest") → $(_tilde "$src")"
  mark_changed "linked $(_tilde "$dest")"
}

# git_pinned_checkout NAME DIR URL COMMIT
#
#   missing                          → shallow clone at COMMIT (detached)
#   already at COMMIT                → nothing to do
#   ours (detached), other commit    → move it to COMMIT
#   on a branch (installed by hand / by another installer) or modified
#                                    → leave it alone, with a warning
#   exists but not a git checkout    → error
git_pinned_checkout() {
  local name=$1 dir=$2 url=$3 commit=$4 head branch
  local short=${commit:0:12}

  if [[ -d "$dir/.git" ]]; then
    head=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
    if [[ "$head" == "$commit" ]]; then
      log_ok "$name already at $short"
      return 0
    fi
    if branch=$(git -C "$dir" symbolic-ref -q --short HEAD); then
      log_warn "$name: existing checkout on branch '$branch' at ${head:0:12} (pinned: $short), not managed by workspace-bootstrap, left as is"
      return 0
    fi
    if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]]; then
      log_warn "$name: $(_tilde "$dir") has local modifications, left as is"
      return 0
    fi
    if [[ "${WSB_DRY_RUN:-0}" == 1 ]]; then
      log_info "would update $name ${head:0:12} → $short"
      mark_changed "would update $name"
      return 0
    fi
    log_info "updating $name ${head:0:12} → $short"
    git -C "$dir" remote set-url origin "$url"
    git -C "$dir" fetch --quiet --depth 1 origin "$commit"
    git -C "$dir" checkout --quiet --force --detach "$commit"
    mark_changed "updated $name to $short"
    log_ok "$name updated to $short"
    return 0
  fi

  if [[ -e "$dir" ]]; then
    log_err "$(_tilde "$dir") exists but is not a git checkout; move it away and re-run"
    return 1
  fi

  if [[ "${WSB_DRY_RUN:-0}" == 1 ]]; then
    log_info "would install $name at $short into $(_tilde "$dir")"
    mark_changed "would install $name"
    return 0
  fi
  log_info "installing $name at $short"
  mkdir -p "$(dirname "$dir")"
  git init --quiet "$dir"
  git -C "$dir" remote add origin "$url"
  if ! git -C "$dir" fetch --quiet --depth 1 origin "$commit"; then
    rm -rf "$dir"
    log_err "could not fetch $name $short from $url"
    return 1
  fi
  git -C "$dir" checkout --quiet --force --detach FETCH_HEAD
  mark_changed "installed $name $short"
  log_ok "$name installed at $short"
}
