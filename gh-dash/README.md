# gh-dash

Configuration for [gh-dash](https://www.gh-dash.dev/) — a CLI dashboard for GitHub PRs, issues, and notifications. Shared across macOS and Linux machines via a build-from-base setup, because gh-dash itself reads a single flat `config.yml` with no includes and no env-var expansion in values.

## Files

| File | Tracked | Purpose |
|---|---|---|
| `config.base.yml` | yes | Shared sections, defaults, keybindings, theme, pager — everything except `repoPaths:` |
| `repoPaths.darwin.yml` | yes | macOS `repoPaths:` block (`~/Desktop/Projects/` + per-repo overrides) |
| `repoPaths.linux.yml` | yes | Linux `repoPaths:` block (flat `~/projects/`) |
| `RECIPE.md` | yes | Upstream "PR-review pipeline" walkthrough (origin: the *I'm never going back to GitHub UI* video) |
| `config.example.yml` | yes | Reference copy of the upstream example |
| `config.yml` | gitignored | Default written by `gh dash` on every launch — see [Why](#why-configyml-is-gitignored) |

## How the active config is assembled

The active config is built at shell startup by concatenating the shared base with the host-specific repoPaths fragment:

```
config.base.yml + repoPaths.<host>.yml  →  $XDG_CACHE_HOME/gh-dash/config.yml
```

Then `$GH_DASH_CONFIG` is exported pointing at that file. gh-dash reads it on launch and merges it on top of its built-in defaults.

The assembly function lives in each machine's `~/dotfiles/zsh/.zshrc.local` (untracked, one per host). The template — with macOS and Linux variants — is in `zsh/.zshrc.local.example`. The function `cat`s the two source files together, `mkdir -p`s the cache dir, writes the output, and exports the env var. If either source file is missing the function prints to stderr what's missing and returns without exporting (so `gh dash` will fall back to its built-in defaults instead of silently using a stale assembly).

## Applying a change

1. Edit `config.base.yml` (anything shared) or `repoPaths.<host>.yml` (per-machine paths).
2. Start a new shell, or `source ~/dotfiles/zsh/.zshrc.local` in the current one.
3. Restart `gh dash`. It re-reads `$GH_DASH_CONFIG` at launch — there's no hot reload.

## Adding a new repo override

The default template `:owner/:repo: ~/Desktop/Projects/:repo` (in `repoPaths.darwin.yml`) catches every flat clone regardless of owner. Repos nested in subfolders need an exact entry that overrides the template:

```yaml
repoPaths:
  ":owner/:repo": ~/Desktop/Projects/:repo
  some-owner/some-repo: ~/Desktop/Projects/work/some-repo
```

Resolution order from gh-dash's source (`internal/tui/common/repopath.go`):

1. Exact `owner/repo` key
2. `owner/*` wildcard
3. `:owner/:repo` template
4. Else: directory `gh dash` was launched from; if none, the command **errors** (`missingkey=error`)

## Custom keybindings

Defined once in `config.base.yml`, shared across machines:

| Key | View | Action |
|---|---|---|
| `G` | any | New tmux window with `lazygit` for the row's repo |
| `C` | PR | New tmux window → `wt` creates a worktree for the PR → `claude` launches pre-prompted to review the diff |
| `O` | PR | New tmux window with the PR open in [Octo](https://github.com/pwntester/octo.nvim) (nvim) for hands-on review |

`C` and `G` need `{{.RepoPath}}` to resolve, so they require a `repoPaths` entry. `O` uses `{{.RepoName}}` (owner/repo) and loads the PR via the gh API, so it works without a local clone.

## Required binaries

`gh`, `gh-dash` (`gh extension install dlvhdr/gh-dash`), `delta`, `wt` (worktrunk), `tmux`, `lazygit`, `nvim` (with `octo.nvim` — see `~/dotfiles/nvim/lua/plugins/octo.lua`), and `claude` (or `opencode` if you swap the `C` keybinding).

## Why `config.yml` is gitignored

gh-dash unconditionally creates `$XDG_CONFIG_HOME/gh-dash/config.yml` on every launch and writes its built-in defaults if the file is missing (`internal/config/parser.go`, `createConfigFileIfMissing`). Because `~/.config/gh-dash` is symlinked to this dotfiles directory, that default file lands here.

When `$GH_DASH_CONFIG` is set, gh-dash *merges* the assembled config on top of the global default, with explicit precedence: `prSections`, `issuesSections`, and `notificationsSections` are wholesale replaced; keybindings are merged; everything else uses standard map-merge with the user file winning. The stray default file is harmless noise — the gitignore rule just keeps it out of git.

## Suggested adoption / further reading

`RECIPE.md` walks through the full stack one tool at a time (delta → custom keybindings → worktree + AI review) and is the right starting point for new machines or for anyone replicating this setup.
