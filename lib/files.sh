# shellcheck shell=bash
#
# Idempotent helpers for files, symlinks and pinned git checkouts.
# All of them check first, act only when needed, call mark_changed for
# real changes and respect --dry-run.

# Short form of a path for log lines: /home/me/.zshrc -> ~/.zshrc
# (The "~" comes from a variable: bash 5 would tilde-expand a literal one.)
_tilde() { local t='~'; printf '%s' "${1/#"$HOME"/$t}"; }

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

# install_managed_copy SRC DEST
# For config files that tools rewrite themselves (so a symlink into the repo
# would get modified). DEST is a copy of SRC; we keep a record of what we
# last wrote, so we can tell our old copy from one the user has changed:
#   missing                    → copy
#   identical to SRC           → nothing to do
#   unchanged since we wrote it→ update to the new SRC
#   changed by the user        → keep it, with a warning
managed_copy_record() { printf '%s/managed%s' "$(wsb_state_dir)" "$1"; }

# managed_copy_settled SRC DEST: true when install_managed_copy would change
# nothing (DEST matches SRC, or the user has changed DEST and it is kept).
managed_copy_settled() {
  local src=$1 dest=$2 record
  record=$(managed_copy_record "$dest")
  [[ -e "$dest" || -L "$dest" ]] || return 1
  if [[ -f "$dest" && ! -L "$dest" ]] && cmp -s "$src" "$dest"; then return 0; fi
  # Exists and differs: settled unless it is still our own (outdated) copy.
  ! { [[ -f "$record" && ! -L "$dest" ]] && cmp -s "$dest" "$record"; }
}

install_managed_copy() {
  local src=$1 dest=$2 record
  record=$(managed_copy_record "$dest")
  [[ -f "$src" ]] || { log_err "missing source: $src"; return 1; }

  if [[ -f "$dest" && ! -L "$dest" ]] && cmp -s "$src" "$dest"; then
    log_ok "$(_tilde "$dest") up to date"
    if [[ "${WSB_DRY_RUN:-0}" != 1 ]] && ! cmp -s "$src" "$record" 2>/dev/null; then
      mkdir -p "$(dirname "$record")"; cp "$src" "$record"
    fi
    return 0
  fi

  local action=install
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ -f "$record" && ! -L "$dest" ]] && cmp -s "$dest" "$record"; then
      action=update
    else
      log_warn "$(_tilde "$dest") was changed locally; keeping your version (repo version: $(_tilde "$src"))"
      return 0
    fi
  fi

  if [[ "${WSB_DRY_RUN:-0}" == 1 ]]; then
    log_info "would $action $(_tilde "$dest")"
    mark_changed "would $action $(_tilde "$dest")"
    return 0
  fi
  mkdir -p "$(dirname "$dest")" "$(dirname "$record")"
  cp "$src" "$dest"
  cp "$src" "$record"
  local done_msg="installed"
  [[ "$action" == update ]] && done_msg="updated"
  log_ok "$done_msg $(_tilde "$dest")"
  mark_changed "$done_msg $(_tilde "$dest")"
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
