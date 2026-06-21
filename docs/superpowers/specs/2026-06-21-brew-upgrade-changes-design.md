# Design: `bup` brew-upgrade change summarizer

**Date:** 2026-06-21
**Status:** Approved (pending implementation)

## Goal

When upgrading Homebrew packages, automatically produce a short, focused
summary of what the upgrades actually introduce — concentrating on **critical
bug fixes, new functionality, and breaking changes** — instead of just seeing a
list of version bumps.

## User-facing behavior

Running `bup` (which today is `alias bup='brew upgrade'`) will:

1. Run `brew upgrade` as usual, streaming its normal output to the terminal.
2. Capture the full output to a raw log file.
3. Hand the list of upgraded packages (the `name old -> new` lines) to an agent
   (`claude -p`, headless) that looks up real release notes and writes a concise
   markdown summary.
4. Print that summary to the terminal and also save it to a timestamped file.

`bup` continues to accept and forward any arguments to `brew upgrade`
(e.g. `bup gh`, `bup --greedy`).

## Components

Two files change:

### 1. `scripts/brew-upgrade-changes` (new)

The workhorse script. `scripts/` is already on `PATH` (see `zsh/.zshrc`:
`export PATH="$HOME/dotfiles/scripts:$PATH"`), so it is directly invocable. It is
made executable (`chmod +x`), matching the existing `scripts/claude-mv`.

Written in bash, kept portable. It must be safe to source/run on machines without
Homebrew (the user's dotfiles are shared between macOS and Linux).

Responsibilities:

- **Brew guard:** if `brew` is not found on `PATH`, print a short note and exit
  non-fatally (do not error out). This keeps the command harmless on Linux boxes
  that lack Homebrew.
- **Run upgrade:** execute `brew upgrade "$@"`, teeing combined stdout+stderr to a
  raw log at `${XDG_STATE_HOME:-$HOME/.local/state}/brew-changes/<TS>.upgrade.log`
  where `<TS>` is `YYYY-MM-DD-HHMMSS`. The state directory is created if missing.
  Preserve `brew`'s exit status.
- **Extract upgraded packages:** parse the raw log for the upgraded-package lines.
  These are the lines of the form `name old_version -> new_version` that follow the
  `==> Upgraded N outdated packages` marker. Practical match: lines containing
  ` -> ` in that block.
- **No-op short-circuit:** if no packages were upgraded, print a brief
  "nothing upgraded" message and exit without invoking the agent.
- **Skip switches:** if `BREW_NOTES=0` is set in the environment, or `--no-notes`
  is passed, run only the upgrade (steps above) and skip the agent entirely.
  `--no-notes` is consumed by the wrapper and NOT forwarded to `brew`.
- **Invoke the agent:** call `claude -p` in headless mode with web tools allowed
  (WebSearch / WebFetch), passing a prompt that contains the package list and the
  summarization instructions (see "Agent prompt" below). Model is taken from
  `BREW_NOTES_MODEL` (default `sonnet`).
- **Deliver:** capture the agent's stdout. Save it to
  `${XDG_STATE_HOME:-$HOME/.local/state}/brew-changes/<TS>.summary.md` (same `<TS>`
  as the raw log), print it to the terminal, and also print the saved summary
  file path (on success too, not only on error).
- **Interruptible:** the agent step can be Ctrl-C'd without losing the raw log
  (which is already written). On interrupt, exit cleanly with a note that the raw
  log is saved and `brew-changes-last` can re-run the summary.

### 2. `zsh/.zshrc` (modified)

Replace:

```zsh
alias bup='brew upgrade'
```

with a thin function that delegates to the script:

```zsh
bup() { brew-upgrade-changes "$@" }
```

(The exact final form is decided during implementation; the intent is a thin
delegator so logic lives in the versioned script, not inline in `.zshrc`.)

### Bonus: `brew-changes-last`

A **separate** script (`scripts/brew-changes-last`) that re-summarizes the most
recent `<TS>.upgrade.log` without re-running `brew upgrade`. It reuses the same
agent-invocation and delivery logic as the main script; that shared logic is
factored into a sourceable helper (e.g. `scripts/brew-changes-lib.sh`) so both
scripts call it rather than duplicating it. Lets the user regenerate a summary
after a Ctrl-C or to retry on network failure.

## Agent prompt (intent, not final wording)

The prompt passed to `claude -p` instructs it to:

- Treat the provided list of `package old -> new` upgrades as the input.
- Look up the actual release notes / changelog for each package between the old
  and new versions (using web tools).
- Produce **concise** markdown grouped by package.
- Focus on: **critical bug fixes, new functionality, breaking changes**.
- Collapse trivial library patch-bumps (no user-visible change) into a single
  short line rather than a section each.
- Avoid filler; this is a quick post-upgrade digest, not a full report.

## Storage layout

```
${XDG_STATE_HOME:-$HOME/.local/state}/brew-changes/
  2026-06-21-091500.upgrade.log    # raw brew upgrade output
  2026-06-21-091500.summary.md     # agent summary
  ...
```

No automatic pruning in v1 (YAGNI). The user can clean the directory manually.

## Configuration knobs

| Knob | Default | Effect |
|------|---------|--------|
| `BREW_NOTES=0` | unset (enabled) | Skip the agent; upgrade only |
| `--no-notes` flag | — | Same as `BREW_NOTES=0`, per-invocation; not forwarded to brew |
| `BREW_NOTES_MODEL` | `sonnet` | Model passed to `claude -p` |

## Error handling

- **No `brew`:** non-fatal note, exit 0-ish (don't break shells that source this).
- **No upgrades:** skip agent, brief message.
- **Agent/network failure or Ctrl-C:** raw log is preserved; print the path and
  mention `brew-changes-last`. Do not mask `brew`'s own exit status with the
  agent's.
- **`claude` not installed:** detect and skip the agent with a note (don't error).

## Explicitly out of scope (v1)

- Background / non-blocking agent execution.
- Desktop notifications.
- Cross-run caching of fetched changelogs.
- Automatic log pruning / rotation.

## Verification deferred to implementation

- Exact `claude -p` headless flags for (a) allowing WebSearch/WebFetch and
  (b) selecting the model — to be confirmed against the installed CLI, not guessed.
- Exact awk/grep extraction of the upgraded-package block, validated against real
  `brew upgrade` output (and the sample in the original request).
