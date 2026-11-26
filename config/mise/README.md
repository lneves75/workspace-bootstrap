# mise configuration (Go, Python, Node)

[`workspace-bootstrap.toml`](workspace-bootstrap.toml) pins the language versions. It is
installed as **a copy** at `~/.config/mise/conf.d/workspace-bootstrap.toml`, not a symlink,
because `mise use -g` rewrites the file that defines a tool and would otherwise edit this repo.

| You want to… | Do this |
|---|---|
| use another version everywhere | add it to `~/.config/mise/config.toml`, which overrides this file |
| use another version in one project | `mise use node@24` in that project (writes `mise.toml` there) |
| take a new pin from the repo | `wsb --upgrade`. The copy is updated if you haven't changed it. If you have, bootstrap keeps your copy and warns |

The shell picks up mise through the Oh My Zsh `mise` plugin (`mise activate zsh`).
