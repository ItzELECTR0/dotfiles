# Shells and dotfiles

## Which shell is which

The login shell is PowerShell, and the terminal starts `pwsh -NoLogo`. Agent tool calls still run
`/usr/bin/bash`, so write bash for tooling and PowerShell only when the target is the user's own
interactive shell.

`~/.bashrc` is a handful of aliases and an early `return` for non-interactive shells, so a tool shell
inherits none of it. Never assume a user alias or function exists in a command you run.

The real interactive configuration is `~/.config/powershell/profile.ps1`, a large file with well over
a hundred functions and aliases, plus `oh-my-posh` for the prompt. Any request to change "my shell"
or "my prompt" means that file, not `.bashrc`.

`EDITOR` is set to a terminal editor, and `GIT_EDITOR=true`, so git never opens an editor. Always
pass `-m`, and never assume an interactive rebase or amend prompt will work.

## Dotfiles

`~/.dotfiles` is a git repo deployed with GNU stow, where the repo is itself the stow package:

```bash
cd ~/.dotfiles && stow .
```

Most of `~/.config/<name>` is a symlink into `~/.dotfiles/.config/<name>`, and so are several
top-level dotfiles and `~/.agents`.

Edit through the symlink or edit the file under `~/.dotfiles`. Never delete and recreate a symlink,
and never write a plain file over one, because that silently detaches the config from the repo. A new
file only reaches `~` after another `stow .`, and `.stow-local-ignore` lists what is deliberately not
deployed.

`~/.dotfiles/scripts` holds desktop, media, mount and VM helper scripts. Hyprland refers to them
through the `dirs` table defined at the top of `hyprland.lua`.

## Agent instruction files

The canonical global rules are `~/.agents/AGENTS.md`, with the topic files beside it in the same
directory. Every agent reaches them through an adapter, so edit the canonical file and never an
adapter:

| Agent | Adapter |
| --- | --- |
| Claude Code | `~/.claude/CLAUDE.md`, a one-line `@` import |
| Gemini CLI | `~/.gemini/GEMINI.md`, a one-line `@` import |
| Codex | `~/.codex/AGENTS.md`, a symlink |

All four live in `~/.dotfiles` and are stowed into place.

## Git

Identity, rebase-on-pull, default branch and the credential helper are all set in `~/.gitconfig`,
which is itself in the dotfiles repo. Read it rather than repeating its values here.

`~/.gitignore_global` carries the global excludes. Note that per-project `.agents/` directories are
meant to be committed and are deliberately not excluded.

Commit only when asked, never push. See the commit message and git authority rules in `AGENTS.md`.
