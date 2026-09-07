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
| `herdr`      | [herdr](https://herdr.dev/) | workspaces, tabs and panes for coding agents; lazygit popup on `prefix+g`, gh dash on `prefix+u` |
| `yazi`       | [yazi](https://github.com/sxyazi/yazi) | terminal file manager + plugins |
| `gh-dash`    | [gh-dash](https://www.gh-dash.dev/) | GitHub PR/issue dashboard with a custom PR-review pipeline |
| `atuin`      | [atuin](https://atuin.sh/) | SQLite shell history with sync |
| `starship`   | [starship](https://starship.rs/) | prompt |
| `television` | [television](https://github.com/alexpasmantier/television) | fuzzy "channels" for git, docker, k8s, aws, … |
| `sesh`       | [sesh](https://github.com/joshmedeski/sesh) | tmux session manager |
| `aerospace`  | [AeroSpace](https://github.com/nikitabobko/AeroSpace) | tiling WM (macOS) |
| `vim`        | vim | minimal fallback `.vimrc` |
| `scripts`    | — | helpers, incl. `bup` (summarizes what `brew upgrade` changes), `mux-open`/`mux-copy` (same command under tmux and herdr) and `openvpn-systemd` (OpenVPN client as a managed systemd unit) |
| `agents`     | — | `AGENTS.md`: universal working agreements shared by every coding agent |
| `home`       | — | files that belong in `$HOME` rather than `~/.config` (see below) |

## Layout & install

Each top-level directory is a stow *package*. `.stowrc` targets `~/.config`, so
stowing the repo symlinks each package there (e.g. `~/.config/nvim -> dotfiles/nvim`).
`home` is ignored in `.stowrc` and stowed separately, because it targets `$HOME`:

```sh
git clone https://github.com/<you>/dotfiles ~/dotfiles
cd ~/dotfiles
stow .                                     # links every package into ~/.config
stow --no-folding --target="$HOME" home    # the one package that targets $HOME, not ~/.config
stow --no-folding --target="$HOME/.config/herdr" herdr   # see below
git config core.hooksPath .githooks   # enable the secret-scanning pre-commit hook
```

`--no-folding` is required for the `home` package. `~/.codex` and `~/.claude` are
directories the tools write runtime state into (caches, sqlite databases, credentials).
Folding would replace such a directory with a single symlink into the repo, so every
byte the tool wrote would land in the git tree. With `--no-folding`, `~/.codex` stays a
real directory holding one symlink per tracked file.

`herdr` is ignored in `.stowrc` for the same reason, and stowed with its own target.
Herdr writes `herdr.sock`, `herdr-server.log` and `session.json` into `~/.config/herdr`,
so that directory has to stay real. The target names the directory itself, because the
package holds the config file rather than a directory to link.

zsh is loaded via `ZDOTDIR="$XDG_CONFIG_HOME/zsh"` (set in `~/.zshenv`), so
`~/.config/zsh/.zshrc` is the entrypoint.

## Agent rules

`agents/AGENTS.md` is the single source of truth for how every coding agent should work —
one tool-neutral file, so a rule is written once and every agent obeys it. Each agent's
expected filename is a symlink back to it, committed in the repo:

```
agents/AGENTS.md                        canonical
home/.claude/CLAUDE.md   ──┐
home/.codex/AGENTS.md    ──┴─────────►  ../../agents/AGENTS.md
```

opencode reads it via `instructions` in `~/.config/opencode/opencode.json` (machine-local,
untracked), which leaves its own `~/.config/opencode/AGENTS.md` free for the caveman plugin:

```json
{ "instructions": ["~/.config/agents/AGENTS.md"] }
```

Adding another agent is one symlink under `home/` pointing at `../../agents/AGENTS.md`.

Scope: only rules that hold in **every** repo on **both** platforms belong here, since the
file is loaded in full on every agent session. Machine-specific facts (which Postgres
cluster, whether Docker exists) stay in that agent's own per-project memory.

## tmux alerts from an agent pane

A pane raises a tmux window alert when its agent stops and waits for me. tmux does
the alerting side for any agent (`monitor-bell on`, `bell-action any`), so each agent
only has to write the BEL byte:

| Agent | How it rings |
|-------|--------------|
| Claude Code | `preferredNotifChannel: terminal_bell` in `~/.claude/settings.json` |
| pi | `home/.pi/agent/extensions/terminal-bell.ts`, since pi has no such setting |

The pi extension rings on `agent_settled` and on `ui_prompt_start`, the two moments pi
hands control back. It stays quiet outside the TUI, so `-p`, JSON and RPC runs and
subagents do not ring.

## Telegram notifications (`/afk`)

Claude Code sessions can ping a Telegram bot when the agent finishes a turn, asks for
input or permission, or ends. Useful when a long task runs and you leave the terminal.

```
home/.claude/hooks/telegram-notify.sh   the switch and the sender, one file
home/.claude/commands/afk.md            the /afk slash command
home/.claude/telegram.env.local.example credentials template (copy, never commit)
```

`/afk` flips the switch for the current session only, so every other session stays quiet.
`/afk on`, `/afk off` and `/afk status` are explicit. Turning it on sends a test message and
refuses to stay on if Telegram rejects it. State lives in
`$XDG_STATE_HOME/claude-telegram/<session-id>` and is dropped when the session ends.

Per-machine setup is two steps, both described in the script header: copy the credentials
template to `~/.claude/telegram.env.local` (a value may be an `op://` reference instead of
a literal), then register the `Notification`, `Stop` and `SessionEnd` hooks in
`~/.claude/settings.json`, which stays untracked because it also holds machine state.

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
