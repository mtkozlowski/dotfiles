# Recipe: Upgrade `gh-dash` into a full PR-review pipeline

Reproduces the workflow from *"I'm never going back to GitHub UI ever again"* (16 min). Each step is independently useful — stop at whatever level of automation you want.

The author's own dotfiles are referenced in the video as the source of truth for the configs; if you want the exact files, hunt those down. Below is the assembly recipe with the moving parts named.

---

## Stack at a glance

| Layer | Tool | What it does |
|---|---|---|
| Base | `gh` (GitHub CLI) | auth + API |
| TUI | `gh-dash` | list/filter PRs, issues, notifications |
| Diff pager | `delta` | colorized syntax + side-by-side |
| Diff browser (optional) | `diffnav` | TUI file-tree on top of delta |
| Inline review (optional) | `octo.nvim` | review/comment from Neovim |
| Multiplexer | `tmux` | new windows per PR-review session |
| Git UX | `lazygit` | bound to a gh-dash key |
| Worktrees | `worktrunk` | one worktree per PR, no stash/reset dance |
| AI reviewer | `opencode` | prompt-driven PR review |

---

## Step 1 — Install `gh-dash`

```bash
# Prereq: GitHub CLI
brew install gh                  # or your package manager
gh auth login                    # SSH, paste the code, approve

# Extension
gh extension install dlvhdr/gh-dash
gh extension list                # confirm
gh dash                          # launch
```

Vim motions work (`j/k/l`, `G`, `gg`). `?` toggles the help menu. Run `gh dash` inside a repo path to scope it to that repo.

## Step 2 — Replace the diff pager with `delta`

The default `d` diff is usable but ugly.

```bash
brew install git-delta
```

Edit `~/.config/gh-dash/config.yml`:

```yaml
pager:
  diff: delta
```

Restart. For side-by-side comparison, add delta's flag:

```yaml
pager:
  diff: "delta --side-by-side"
```

## Step 3 — (Optional) Swap `delta` for `diffnav`

Same author as delta. Adds a file-tree TUI on top.

```bash
# Install per diffnav README (Go binary)
```

```yaml
pager:
  diff: diffnav
```

Inside diffnav: tree toggle, side-by-side toggle, icon toggle — all from its `?` menu.

## Step 4 — Tune the gh-dash config

Config lives at `~/.config/gh-dash/config.yml`. Highlights worth changing first:

```yaml
defaults:
  preview:
    open: false          # start with preview pane closed
    width: 60            # bigger when toggled

prSections:
  - title: All
    filters: "is:open"   # nuke the "author:@me" default
  - title: Involved
    filters: "is:open involves:@me"

issuesSections:
  - title: All
    filters: "is:open"
```

The three top-level views are **PRs / Issues / Notifications** — `s` cycles between them (also clickable in the bottom bar).

## Step 5 — Universal keybinding: `G` → LazyGit in a new tmux window

In `config.yml`:

```yaml
keybindings:
  universal:
    - key: G
      command: >
        tmux new-window -n lazygit -c {{.RepoPath}} \;
        send-keys 'lazygit' Enter
```

`{{.RepoPath}}` is a gh-dash template variable. The video notes the author uses `;` as the command separator because tmux semicolons are fussy — adapt to your shell.

## Step 6 — PR-context keybinding: `C` → tmux window + Neovim + Octo

```yaml
keybindings:
  prs:
    - key: C
      command: >
        tmux new-window -n {{.RepoName}} -c {{.RepoPath}} \;
        send-keys 'nvim +"Octo pr edit {{.PrNumber}}"' Enter
```

Now in gh-dash, selecting a PR and hitting `C` spawns a tmux window already opened to that PR in Octo (review, comment, side-by-side diff with `]q` / `[q`-style navigation that Octo provides).

Install `octo.nvim` via lazy.nvim:

```lua
{
  "pwntester/octo.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  config = function() require("octo").setup() end,
}
```

## Step 7 — Endgame: worktree + AI review on one keypress

This is the payoff. `C` opens a fresh **git worktree** for the PR and launches **opencode** with a "review this PR" prompt.

```yaml
keybindings:
  prs:
    - key: C
      command: >
        tmux new-window -n pr-{{.PrNumber}} -c {{.RepoPath}} \;
        send-keys 'worktrunk pr:{{.PrNumber}} -- opencode "review this PR"' Enter
```

What happens when you press `C`:

1. gh-dash hands the PR number to a new tmux window.
2. `worktrunk` creates an isolated worktree for that PR (no stash, no branch switching in your main checkout).
3. `opencode` starts a session inside that worktree, pre-prompted to review the diff.

You walk over to the new tmux window and the AI has already started.

---

## Template variables available in commands

From the video, these are the ones used:

- `{{.RepoPath}}` — absolute path of the repo gh-dash is currently in
- `{{.RepoName}}` — repo name (good for tmux window titles)
- `{{.PrNumber}}` — selected PR number (only valid under `keybindings.prs`)

Check `gh-dash`'s docs for the full list; these three carry 90% of what you need.

---

## Suggested adoption order

1. Steps 1–2 (install + delta). 10 minutes, immediate quality-of-life.
2. Step 4 (config customization). The default `author:@me` filter is the first thing that frustrates everyone.
3. Step 5 (LazyGit bind). Easy win, reusable across all gh-dash sessions.
4. Step 6 OR Step 7. Pick one — Octo if you want a human review flow, worktrunk+opencode if you want AI-assisted.

Skip Step 3 (diffnav) unless you actually miss a file tree in delta — it's marginal.

---

## Gotchas the author flagged

- gh-dash on a repo path filters to that repo by default. Remove the implicit `repo:` filter to see all your PRs across GitHub — but expect *a lot* (he hit 83M results without it).
- The default config assumes you're the PR author. Most people are involved in more PRs than they author; rewrite the filters first.
- Octo and gh-dash overlap. Author's take: **gh-dash for listing/triage, Octo only when you need to actually engage with code** — otherwise it's redundant.
