# zsh configuration

`~/.zshrc` is a symlink to [`zshrc`](zshrc), which loads the rest of this folder in this order:

| Order | File | What goes there |
|---|---|---|
| 1 | `env.zsh` | PATH, Homebrew shellenv, EDITOR, PAGER |
| 2 | `~/.zshrc.pre.local` | *personal*: anything needed before Oh My Zsh, e.g. `WSB_EXTRA_PLUGINS=(kubectl terraform)` or `ZSH_THEME=agnoster` |
| 3 | `plugins/<plugin>.zsh` | settings for a plugin, read when it loads. Name the file after the plugin |
| 4 | `omz.zsh` | theme (agnoster unless `ZSH_THEME` is set), plugin list, then Oh My Zsh itself |
| 4b | `completions/*.zsh` | completions Oh My Zsh doesn't provide (e.g. yq), generated once and cached |
| 5 | `options.zsh` | `setopt` and history settings, after Oh My Zsh so they win |
| 6 | `functions/*.zsh` | shell functions, grouped by topic |
| 7 | `aliases/*.zsh` | aliases, grouped by topic, after Oh My Zsh so they override its aliases |
| 8 | `~/.zshrc.d/*.zsh` | *personal*: your own snippets |
| 9 | `~/.zshrc.local` | *personal*: sourced last, overrides everything |

Files in this folder are shared through the repo. The *personal* files live only on your
machine, and workspace-bootstrap never touches them.

## Plugins

- **Bundled** Oh My Zsh plugins: add the name to `plugins=(…)` in `omz.zsh`.
- **External** plugins: add a line to `external-plugins.txt` (name, repository, pinned commit)
  and add the name to `plugins=(…)`. `bootstrap.sh --only zsh` clones it into
  `$ZSH_CUSTOM/plugins/`.
- A plugin that isn't installed is skipped, so startup never fails because of one.
- Tool plugins (kubectl, terraform, opentofu, terragrunt, fluxcd, gh, aws, azure, gcloud) are
  added only when the tool's command exists. To add another, extend the `command → plugin` list
  in `omz.zsh`.

Oh My Zsh itself is pinned in `versions.env`, and its auto-updater is off. `wsb --upgrade` updates
it together with the rest of workspace-bootstrap.

## Adding things

- New alias group: `aliases/<topic>.zsh`
- New function group: `functions/<topic>.zsh`
- New plugin settings: `plugins/<plugin-name>.zsh`
- New completion: `completions/<tool>.zsh` with `_wsb_cached_completion <tool> <command that prints a zsh completion>`

Any `*.zsh` file in those folders is picked up automatically.
