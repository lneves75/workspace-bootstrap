# git configuration

| File | Used as | How |
|---|---|---|
| `gitconfig` | shared defaults: aliases, pull/push/rebase behaviour, editor | included at the **top** of `~/.gitconfig` |
| `ignore` | global gitignore (OS and editor clutter) | symlinked to `~/.config/git/ignore` |

`~/.gitconfig` stays a normal personal file. It is not a symlink, because `git config --global`
writes to it. Your `user.name` and `user.email` live there, along with anything else you set.
Because the include comes first, your own values override the shared ones.

To see where a setting comes from: `git config --show-origin --get pull.ff`.
