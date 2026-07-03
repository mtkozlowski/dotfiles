# zsh

Cross-machine zsh config. The same `.zshrc` is expected to load cleanly on
macOS workstations, Linux VPSes, and virtual desktops. Per-machine differences
live in an untracked `.zshrc.local`.

## File layout

```
~/.zshenv                 (in $HOME — hard-coded by zsh, must live there)
  └─ sets ZDOTDIR=~/.config/zsh/
~/.zprofile               (in $HOME — login shells; minimal, just brew shellenv)
~/.config/zsh/            (stow symlink → dotfiles/zsh/)
  ├─ .zshrc               (tracked — universal config)
  ├─ .zshrc.local.example (tracked — template)
  └─ .zshrc.local         (untracked, gitignored — this machine's overrides)
```

`.zshenv` MUST live in `$HOME` because zsh hard-codes that lookup before
anything else. Once it sets `ZDOTDIR`, every other zsh startup file is read
from `~/.config/zsh/`.

## The three-layer split

| Layer | Where | Contents |
|-------|-------|----------|
| Universal | tracked `.zshrc` | shell behavior, completions, prompt, git/docker/dir aliases, vi mode, tool init (with guards) |
| OS-true | tracked `.zshrc`, guarded by `$OSTYPE` | things that depend on the OS itself (`osascript`, `qlmanage` for macOS Finder helpers) |
| Per-machine | untracked `.zshrc.local` | tools that happen to be installed *on this host*: nvm, bun, conda, GUI app PATHs, IDE aliases, work shortcuts, secrets |

**Test for "does this go in tracked .zshrc?"** — Would it be useful on *every*
zsh I open across all my machines? If no, it belongs in `.zshrc.local`.

## Patterns used

### Guard tool initialization with `command -v`

Anything that calls an external tool needs to no-op cleanly when the tool isn't
installed (e.g. fresh VPS):

```zsh
command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
```

For brew specifically, the whole sourcing block is wrapped so plugin paths
don't blow up on machines without brew:

```zsh
if command -v brew >/dev/null 2>&1; then
    source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
```

### Guard PATH additions with directory existence

Don't pollute `$PATH` with paths that don't exist on this machine:

```zsh
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"
```

### Guard OS-specific code with `$OSTYPE`

Reserved for things that depend on the OS itself, not on a specific tool:

```zsh
if [[ "$OSTYPE" == darwin* ]]; then
    function pfd() { osascript ... }
fi
```

Tool-specific code does NOT belong here even if you only have the tool on
macOS — use directory/command guards in `.zshrc.local` instead. JetBrains
runs on Linux too; Obsidian runs on Linux too. The OS guard is for `osascript`
and `qlmanage`, which are macOS-only by definition.

### Use `$HOME`, not `/Users/$USER`

Hard-coded `/Users/<you>/...` paths break on Linux. Always `$HOME`.

### `.zshrc.local` source line

Last line of `.zshrc`:

```zsh
[[ -f "$ZDOTDIR/.zshrc.local" ]] && source "$ZDOTDIR/.zshrc.local"
```

Loaded last so it can override anything tracked.

### Secrets via 1Password (`op.zsh`)

`op.zsh` (sourced from `.zshrc`) authenticates `op` the same way on every
machine — a 1Password service-account token, with no desktop-app/biometric
integration. The token lives in one `0600` file
(`$XDG_CONFIG_HOME/op/service-account-token`), is injected into `op`'s own
process per-call, and is never exported to the shell or passed as an argv — so
it stays private from other users on a shared box. Fetch secrets with
`op run --env-file=<refs>` (references committable, values never on disk) or the
`openv VAR op://ref` helper. See `.zshrc.local.example` for one-time setup.

## Stow + the folded-directory gotcha

`.stowrc` targets `~/.config`, and `~/.config/zsh` is a *folded* symlink
straight to `dotfiles/zsh/` — i.e. the directory itself is the symlink, not
each file inside it. Consequence: any file written to `~/.config/zsh/`
physically lands in this repo directory.

That means `--ignore` patterns in `.stowrc` don't help for `.zshrc.local` —
once the dir is folded, every file inside is "stowed" implicitly. So
`.zshrc.local` is kept out of git via `.gitignore` (`*.local` with
`!*.local.example`), not via stow.

If you ever want a file to NOT be visible from `~/.config/zsh/`, you'd need
to un-fold the directory first (delete the symlink, recreate it as a real
dir, then re-stow individual files). Not worth doing — gitignore is fine.

## New-machine setup

```sh
git clone <dotfiles> ~/dotfiles
cd ~/dotfiles
stow zsh                                             # plus other packages
cp ~/.config/zsh/.zshrc.local.example \
   ~/.config/zsh/.zshrc.local
$EDITOR ~/.config/zsh/.zshrc.local                   # uncomment what applies
```

On a barebones VPS: leave `.zshrc.local` mostly empty. On a Mac: uncomment
GUI app blocks. On a JS-heavy box: uncomment nvm/bun. On work hardware:
add the work shortcuts and IDE aliases.

## brew upgrade summaries

`bup` runs `brew upgrade` and then uses the `claude` CLI to summarize what the
upgrades introduce (critical fixes, new features, breaking changes).

- Summaries and raw logs are saved under `${XDG_STATE_HOME:-~/.local/state}/brew-changes/`.
- `bup --no-notes` (or `BREW_NOTES=0 bup`) upgrades without the summary.
- `BREW_NOTES_MODEL=opus bup` overrides the model (default: `sonnet`).
- `brew-changes-last` re-generates the summary for the most recent upgrade.

Requires `brew` and the `claude` CLI; on machines without them, `bup` degrades
gracefully (plain upgrade, or a no-op note).

## Adding new stuff later

Before adding a line to tracked `.zshrc`, ask: *is this useful on every
machine I open zsh on?*

- Yes → tracked `.zshrc`, guarded with `command -v` / `[[ -d ... ]]` / `$OSTYPE` as appropriate.
- No → `.zshrc.local` on the machines that need it, plus a commented entry in `.zshrc.local.example` so future-you remembers it exists.
