# dotfiles

Personal, cross-platform (macOS + Linux) terminal environment, managed with
[GNU stow](https://www.gnu.org/software/stow/). One repo, symlinked into
`~/.config`, kept identical across a macOS laptop and several Linux VPSs — with a
clean separation between what's safe to publish and what stays private.

## What's inside

| Package      | Tool | Notes |
|--------------|------|-------|
| `zsh`        | [zsh](https://www.zsh.org/) | prompt, completions, vi-mode, atuin-backed autosuggestions |
| `nushell`    | [nushell](https://www.nushell.sh/) | structured-data shell, used alongside zsh |
| `nvim`       | [Neovim](https://neovim.io/) | LazyVim-based config |
| `tmux`       | [tmux](https://github.com/tmux/tmux) | session persistence; OSC 52 yank for headless VPSs |
| `yazi`       | [yazi](https://github.com/sxyazi/yazi) | terminal file manager + plugins |
| `gh-dash`    | [gh-dash](https://www.gh-dash.dev/) | GitHub PR/issue dashboard with a custom PR-review pipeline |
| `atuin`      | [atuin](https://atuin.sh/) | SQLite shell history with sync |
| `starship`   | [starship](https://starship.rs/) | prompt |
| `television` | [television](https://github.com/alexpasmantier/television) | fuzzy "channels" for git, docker, k8s, aws, … |
| `sesh`       | [sesh](https://github.com/joshmedeski/sesh) | tmux session manager |
| `aerospace`  | [AeroSpace](https://github.com/nikitabobko/AeroSpace) | tiling WM (macOS) |
| `vim`        | vim | minimal fallback `.vimrc` |
| `scripts`    | — | helpers, incl. `bup` (summarizes what `brew upgrade` changes) |

## Layout & install

Each top-level directory is a stow *package*. `.stowrc` targets `~/.config`, so
stowing a package symlinks it there (e.g. `~/.config/nvim -> dotfiles/nvim`):

```sh
git clone https://github.com/<you>/dotfiles ~/dotfiles
cd ~/dotfiles
stow */                       # or stow individual packages: stow nvim tmux zsh
git config core.hooksPath .githooks   # enable the secret-scanning pre-commit hook
```

zsh is loaded via `ZDOTDIR="$XDG_CONFIG_HOME/zsh"` (set in `~/.zshenv`), so
`~/.config/zsh/.zshrc` is the entrypoint.

## Private overlay

The repo is public, so it contains **only generic, shareable config**. Anything
private or machine-specific lives in an overlay that's never published, layered on
top at shell startup:

```
 public repo (this)            tracked, generic
   └─ zsh/.zshrc               sources, last:
        └─ ~/.config/zsh/.zshrc.local      untracked per-machine bootstrap (*.local, gitignored)
             ├─ source ~/.dotfiles-private/init.zsh   ① companion repo (private, synced)
             └─ export KEY=$(op read …)               ② secret manager (1Password / pass / age)
```

1. **Companion repo** — a separate *private* git repo (e.g. `~/.dotfiles-private`)
   for work aliases, private functions, and gh-dash work repo paths. It syncs
   across machines via its own remote and is sourced from `.zshrc.local`.
2. **Secret manager** — real credentials are fetched at shell init (never stored
   in any repo). See the `--- Secrets ---` section of
   [`zsh/.zshrc.local.example`](zsh/.zshrc.local.example).

Copy the template to start a machine's overlay:

```sh
cp ~/dotfiles/zsh/.zshrc.local.example ~/.config/zsh/.zshrc.local
$EDITOR ~/.config/zsh/.zshrc.local
```

gh-dash uses the same idea: a generic, tracked `repoPaths.<host>.yml` plus an
optional gitignored `repoPaths.local.yml` (kept in the companion repo) that the
shell-startup assembly appends automatically.

## Keeping it clean

A zero-dependency pre-commit hook (`.githooks/pre-commit`) blocks commits that
contain generic secret shapes (private keys, AWS keys, tokens, JWTs). It also
honors a personal, gitignored marker list — copy
[`.githooks/markers.local.example`](.githooks/markers.local.example) to
`markers.local` and add strings that should never be republished (employer names,
usernames, internal hosts). If [gitleaks](https://github.com/gitleaks/gitleaks)
is installed, it runs too.
