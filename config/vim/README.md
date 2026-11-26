# vim configuration

`~/.vimrc` is a symlink to [`vimrc`](vimrc). Your personal settings go in `~/.vimrc.local`,
which is sourced last.

## Ported from Neovim

The previous Neovim setup (`~/.config/nvim/init.vim` with vim-plug) was plain Vimscript, so all
of it carries over to vim:

| Neovim (init.vim) | Here |
|---|---|
| vim-plug, `~/.local/share/nvim/plugged` | Vim's native packages in `~/.vim/pack/workspace-bootstrap/start`, installed by bootstrap (no plugin manager) |
| `NLKNguyen/papercolor-theme` (2022 checkout) | same theme, latest commit (2024-03). The maintained `papercolor-theme-slim` is Neovim-only |
| `itchyny/lightline.vim` (2022) | latest (2026-10), with its `PaperColor` colorscheme |
| `tpope/vim-fugitive` (2022) | latest master (the last tag, v3.7, is from 2022) |
| `editorconfig/editorconfig-vim` (2022) | v1.2.1. Kept as a plugin because Debian 12's vim predates Vim's built-in EditorConfig |
| `background=dark`, `colorscheme PaperColor`, `t_Co=256` | same |
| `nonumber`, `noexpandtab`, `tabstop/shiftwidth/softtabstop=2` | same (Go, Python, Make and git commits keep their conventions) |
| `splitbelow`, `splitright`, `mouse-=n`, `laststatus=2`, `noshowmode` | same (`noshowmode` only while lightline is loaded) |

Plugins are pinned in [`plugins.txt`](plugins.txt) (name, repository, commit). To upgrade one,
change its commit and re-run `bootstrap.sh --only vim`. Packs you add under `~/.vim/pack/`
yourself are not touched.

Swap, backup and undo files are kept in `~/.vim/{swap,backup,undo}`, never in your projects.

Neovim still reads its own `~/.config/nvim/init.vim`, which bootstrap doesn't touch. To have
Neovim use this config too, make that file contain:
`set runtimepath^=~/.vim runtimepath+=~/.vim/after | let &packpath = &runtimepath | source ~/.vimrc`.
