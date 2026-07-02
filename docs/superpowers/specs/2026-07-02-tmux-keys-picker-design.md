# tmux-keys: searchable, executable keybinding picker

**Date:** 2026-07-02
**Status:** Approved design, pending implementation

## Problem

`prefix + ?` in tmux shows all key bindings, but the built-in view is a static,
non-interactive dump. We want it to be:

1. **Searchable** — fuzzy-find a binding by what it *does* or by its command.
2. **Executable** — hitting `Enter` on a row runs that binding.

Use the modern CLI tooling already installed in this environment (fzf, bat).

## Environment (verified)

- tmux **3.7**
- Available: `fzf`, `tv`, `bat`, `glow`, `rg`, `yazi`
- Existing pattern: `display-popup -E` is already used for lazygit and sp-status.
- Of 45 custom bindings, only 3 carry `-N` notes. `tmux list-keys -N` yields 72
  annotated rows (tmux ships default notes for built-ins); plain `tmux list-keys`
  yields 310 rows, each with the full command.

## Key technical finding (verified empirically)

**`send-keys` cannot trigger a tmux binding.** A test bound `prefix+g` to
`new-window` and ran `tmux send-keys C-a g`; the window count did not change,
because `send-keys` injects bytes into the pane's program, *downstream* of
tmux's prefix/key-table dispatcher. tmux exposes no command to replay a key
through the key table. Therefore the only robust way to invoke a binding
programmatically is **to run its bound command directly**.

## Design

### Surface

Bind `prefix + ?` to a single self-contained script via `run-shell` (one clean
line in `tmux.reset.conf`, no `\;` chains):

```
bind -N "searchable keybindings (fzf popup)" ? run-shell "~/.config/tmux/scripts/tmux-keys"
```

### Script: `tmux/scripts/tmux-keys`

Re-entrant with two modes:

1. **Outer (run-shell) mode — no args:**
   - Create a temp file.
   - `tmux display-popup -w 80% -h 80% -E "<script> --pick <tmpfile>"` (blocks
     until the popup closes).
   - If the temp file is non-empty, run `tmux source-file <tmpfile>` — executes
     the chosen command on the real (underlying) pane, in the correct
     client/session context. Clean up the temp file.

2. **Inner (`--pick <tmpfile>`) mode — runs inside the popup:**
   - Build the row list (below), pipe into fzf.
   - On `Enter`: resolve the exact command for the selected `table`+`key` via
     `tmux list-keys -T <table> <key>`, strip the `bind-key -T <table> <key> `
     prefix, write the remaining command verbatim to `<tmpfile>`, exit (popup
     closes). Executing via `source-file` uses tmux's own parser, so complex
     bindings with nested quoting (e.g. the `sesh` picker) round-trip exactly.
   - On `Ctrl-Y`: copy the `prefix key` combo into the tmux buffer instead of
     executing (cheatsheet use); do not write a command.

### Data pipeline

- **Backbone:** `tmux list-keys -T prefix` and `-T root` — parsed as
  `bind-key -T <table> <key> <command...>` (fields: table=`$3`, key=`$4`,
  command = remainder). Every binding is present and executable.
- **Descriptions:** `tmux list-keys -N` provides `key → note` where a note
  exists; joined by key. Rows without a note fall back to showing the raw
  command as the description.
- **Default scope:** prefix + root tables. copy-mode / copy-mode-vi are hidden
  by default (executing them out of context is meaningless) but reachable via a
  flag (e.g. `--all`).

### fzf configuration

- Fuzzy search across key + description + command.
- A hidden leading `table\tkey` token (via `--delimiter` tab + `--with-nth`) so
  the visible columns stay clean while the accept handler can recover the exact
  binding.
- `--ansi` with table names colorized; aligned columns.
- `--preview` shows the full command (and note) rendered with `bat -l sh`.
- Key bindings: `enter` = run, `ctrl-y` = copy combo to buffer.

## Components & responsibilities

| Unit | Responsibility | Interface |
|------|----------------|-----------|
| `tmux-keys` (outer) | Own the popup lifecycle + post-selection execution | invoked by `run-shell`, no args |
| `tmux-keys --pick` (inner) | Build rows, drive fzf, resolve+emit chosen command | writes command to tmpfile |
| tmux binding | Entry point on `prefix + ?` | one `run-shell` line |

## Out of scope (YAGNI)

- Adding `-N` notes to un-annotated bindings (declined — bindings stay as is).
- Persistent `tv` channel; a one-shot fzf popup fits the use case.
- Editing / rebinding keys from the picker.

## Testing

- Verify the popup opens on `prefix + ?` and closes cleanly.
- Enter on a simple binding (e.g. split) performs the action on the correct pane.
- Enter on the complex `sesh` binding runs without quoting corruption.
- `Ctrl-Y` copies the combo to the buffer and executes nothing.
- Fuzzy search finds a binding by description and by command text.
- copy-mode rows are hidden by default, shown with `--all`.
