# tmux-keys Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `prefix + ?` open a fuzzy-searchable fzf popup of all tmux key bindings where `Enter` runs the selected binding.

**Architecture:** A single self-contained script `tmux/scripts/tmux-keys` with three modes. `--pick` runs inside a `display-popup`: it builds rows from `tmux list-keys` (backbone, always executable) enriched with `tmux list-keys -N` notes, drives fzf, and writes the chosen command to a per-uid temp file. `--exec` runs after the popup closes and sources that file onto the real pane. A tmux `{ }` block bound to `?` sequences the two so the popup is dismissed before the command runs (required — some bindings open their own popups, which cannot nest). The row-building/parsing logic is exposed as `--build-rows` for unit testing without a live tmux.

**Tech Stack:** POSIX-ish bash (must run on macOS bash 3.2 — no associative arrays; joins done in awk), `awk`, `fzf`, `bat`, tmux 3.7.

## Global Constraints

- Target tmux **3.7**; macOS default **bash 3.2** — no bash associative arrays, no `mapfile`.
- Script lives at `tmux/scripts/tmux-keys` in the repo; reachable at `~/.config/tmux/scripts/tmux-keys` (the dir is symlinked: `~/.config/tmux -> ../dotfiles/tmux`).
- Multi-command tmux bindings use `{ }` blocks, never `\;` chains.
- Do NOT add `-N` notes to existing bindings (declined in spec).
- Executable commands must be preserved **verbatim** from `list-keys` (nested quoting in the `sesh` binding must round-trip); execute via `tmux source-file`, never by re-quoting through a shell.
- Only `-r` may appear before `-T` in `list-keys` output; locate `-T` dynamically rather than assuming a fixed column.

---

### Task 1: Row-building core + `--build-rows` (unit-tested)

Builds the fzf row for each binding and is fully testable from fixtures with no running tmux. Each output row is TAB-delimited: `visible \t combo \t command`, where `command` is the verbatim tmux command (field 3) used later for execution and preview.

**Files:**
- Create: `tmux/scripts/tmux-keys`
- Test: `tmux/scripts/tests/tmux-keys.test.sh`

**Interfaces:**
- Produces: `tmux-keys --build-rows <NOTES_FILE>` reads raw `list-keys` lines on **stdin** and a notes file (`table<TAB>key<TAB>note`) as `$1`; prints one TAB-delimited row per binding to stdout. Field 1 = colorized display string, field 2 = combo (`prefix X` / `root X`), field 3 = verbatim command.

- [ ] **Step 1: Write the failing test**

Create `tmux/scripts/tests/tmux-keys.test.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for tmux-keys --build-rows (no live tmux required).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../tmux-keys"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { # desc, condition-rc
  if [ "$2" -eq 0 ]; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi
}

# Fixture: raw `list-keys` output (note the -r line and a root Mouse line)
cat > "$TMP/raw" <<'EOF'
bind-key    -T prefix !       break-pane
bind-key -r -T prefix ,       resize-pane -L 20
bind-key    -T prefix g       display-popup -d "#{pane_current_path}" -w 90% -h 90% -E "lazygit"
bind-key    -T root MouseDown1Pane select-pane -t = \; send-keys -M
EOF

# Fixture: notes (only ! has a note)
printf 'prefix\t!\tBreak pane to a new window\n' > "$TMP/notes"

out="$("$SCRIPT" --build-rows "$TMP/notes" < "$TMP/raw")"

grep -q "Break pane to a new window" <<<"$out"; check "note is joined for prefix !" $?
grep -q "resize-pane -L 20" <<<"$out";          check "-r binding is parsed (,)" $?
grep -qF 'display-popup -d "#{pane_current_path}" -w 90% -h 90% -E "lazygit"' <<<"$out"; check "verbatim command preserved" $?
if grep -q "MouseDown1Pane" <<<"$out"; then check "root Mouse* filtered out" 1; else check "root Mouse* filtered out" 0; fi

# Field 3 of the g row must be the exact command (no shell re-quoting)
gcmd="$(grep lazygit <<<"$out" | cut -f3)"
[ "$gcmd" = 'display-popup -d "#{pane_current_path}" -w 90% -h 90% -E "lazygit"' ]; check "field 3 == exact command" $?

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tmux/scripts/tests/tmux-keys.test.sh`
Expected: FAIL — the script does not exist yet (`No such file or directory` / all checks fail).

- [ ] **Step 3: Write minimal implementation**

Create `tmux/scripts/tmux-keys`:

```bash
#!/usr/bin/env bash
# tmux-keys — searchable, executable tmux keybinding picker.
#   --build-rows NOTES   build fzf rows from raw `list-keys` (stdin) + notes file (internal + tests)
#   --pick [--all]       run inside display-popup: fuzzy-pick a binding, stash chosen command
#   --exec               run after popup closes: source the chosen command, then clear it
set -euo pipefail

cmdfile() { printf '%s/tmux-keys.%s.cmd' "${TMPDIR:-/tmp}" "$(id -u)"; }

build_rows() {
  # $1 = notes file (table<TAB>key<TAB>note); raw `list-keys` lines on stdin
  awk -v notes="$1" '
    BEGIN {
      while ((getline line < notes) > 0) {
        ti = index(line, "\t"); if (ti == 0) continue
        tb = substr(line, 1, ti-1); rest = substr(line, ti+1)
        ki = index(rest, "\t"); if (ki == 0) continue
        note[tb SUBSEP substr(rest, 1, ki-1)] = substr(rest, ki+1)
      }
    }
    {
      tpos = 0
      for (i = 1; i <= NF; i++) if ($i == "-T") { tpos = i; break }
      if (tpos == 0) next
      table = $(tpos+1); key = $(tpos+2)
      # verbatim command = strip the first (tpos+2) whitespace-delimited tokens
      line = $0; k = tpos + 2
      for (j = 0; j < k; j++) sub(/^[ \t]*[^ \t]+/, "", line)
      sub(/^[ \t]+/, "", line)
      cmd = line
      if (table == "root" && key ~ /^(Mouse|Wheel)/) next
      nkey = key; gsub(/\\/, "", nkey)
      desc = ((table SUBSEP nkey) in note) ? note[table SUBSEP nkey] : cmd
      combo = (table == "prefix") ? ("prefix " nkey) : (table " " nkey)
      color = (table == "prefix") ? "\033[36m" : "\033[33m"
      visible = sprintf("%s%-16s\033[0m %-46s \033[2m%s\033[0m", color, combo, desc, cmd)
      printf "%s\t%s\t%s\n", visible, combo, cmd
    }
  '
}

case "${1:-}" in
  --build-rows) shift; build_rows "$1" ;;
  *) echo "usage: tmux-keys --build-rows NOTES | --pick [--all] | --exec" >&2; exit 2 ;;
esac
```

Then make it executable:

```bash
chmod +x tmux/scripts/tmux-keys
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tmux/scripts/tests/tmux-keys.test.sh`
Expected: all 5 lines print `ok   - ...`; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add tmux/scripts/tmux-keys tmux/scripts/tests/tmux-keys.test.sh
git commit -m "feat(tmux): tmux-keys row builder with notes join and verbatim commands"
```

---

### Task 2: Interactive picker + execution glue (`--pick`, `--exec`, `collect_rows`)

Adds the tmux-facing pieces around the tested core: gather rows from the live server, run fzf in the popup, stash the choice, and execute it after the popup closes. These are integration-tested manually inside a real tmux session (fzf needs a TTY).

**Files:**
- Modify: `tmux/scripts/tmux-keys`

**Interfaces:**
- Consumes: `build_rows` and `cmdfile` from Task 1.
- Produces:
  - `collect_rows [all]` — runs `tmux list-keys`/`-N` for `prefix`+`root` (plus `copy-mode`+`copy-mode-vi` when arg is `all`), feeds `build_rows`, prints rows.
  - `tmux-keys --pick [--all]` — truncates the cmdfile, runs fzf, writes the selected verbatim command (fzf field 3) to the cmdfile; `Ctrl-Y` copies the combo (field 2) to the tmux buffer and aborts.
  - `tmux-keys --exec` — `source-file`s the cmdfile if non-empty, then removes it.

- [ ] **Step 1: Add `collect_rows`, `run_pick`, `run_exec` and extend the dispatch**

In `tmux/scripts/tmux-keys`, insert these three functions immediately after the `build_rows` function definition:

```bash
collect_rows() {
  # $1 = "all" to include copy-mode tables
  local tmpd notes raw tables t
  tmpd="$(mktemp -d)"; notes="$tmpd/notes"; raw="$tmpd/raw"
  : > "$notes"; : > "$raw"
  tables="prefix root"
  [ "${1:-}" = all ] && tables="prefix root copy-mode copy-mode-vi"
  for t in $tables; do
    tmux list-keys -N -T "$t" 2>/dev/null \
      | awk -v t="$t" 'NF { key=$1; $1=""; sub(/^[ \t]+/,""); print t"\t"key"\t"$0 }' >> "$notes"
    tmux list-keys -T "$t" 2>/dev/null >> "$raw"
  done
  build_rows "$notes" < "$raw"
  rm -rf "$tmpd"
}

run_pick() {
  local all="" cf sel cmd
  [ "${1:-}" = --all ] && all=all
  cf="$(cmdfile)"; : > "$cf"
  sel="$(collect_rows "$all" | fzf \
      --ansi --delimiter=$'\t' --with-nth=1 --nth=1 \
      --height=100% --layout=reverse --border=none \
      --prompt='keys ▸ ' \
      --header='enter: run   ctrl-y: copy combo   esc: cancel' \
      --preview='printf "%s" {3} | bat --language=bash --color=always --style=plain --paging=never' \
      --preview-window='down,3,wrap' \
      --bind='ctrl-y:execute-silent(tmux set-buffer -- {2})+abort' \
    )" || true
  [ -n "$sel" ] || return 0
  cmd="$(printf '%s' "$sel" | cut -f3)"
  printf '%s\n' "$cmd" > "$cf"
}

run_exec() {
  local cf; cf="$(cmdfile)"
  [ -s "$cf" ] && tmux source-file "$cf"
  rm -f "$cf"
}
```

Then replace the `case` dispatch at the bottom of the file with:

```bash
case "${1:-}" in
  --build-rows) shift; build_rows "$1" ;;
  --pick)       shift; run_pick "$@" ;;
  --exec)       run_exec ;;
  *) echo "usage: tmux-keys --build-rows NOTES | --pick [--all] | --exec" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Re-run the unit test to confirm no regression**

Run: `bash tmux/scripts/tests/tmux-keys.test.sh`
Expected: all 5 checks still `ok`; exit 0. (Task 1's core is unchanged.)

- [ ] **Step 3: Manual integration test — picker + execution**

Run inside a real, attached tmux session (fzf needs a TTY):

```bash
# 1. Picker renders and returns a command without executing anything:
~/.config/tmux/scripts/tmux-keys --pick
#    -> fzf popup of bindings appears. Type "split" to filter, highlight the
#       vertical-split binding, press Enter. Popup closes.
cat "${TMPDIR:-/tmp}/tmux-keys.$(id -u).cmd"
#    Expected: the exact split-window command is printed.

# 2. Execution applies it to the current pane:
~/.config/tmux/scripts/tmux-keys --exec
#    Expected: the pane splits; the cmd file is now gone:
test -e "${TMPDIR:-/tmp}/tmux-keys.$(id -u).cmd" && echo "STILL EXISTS (bad)" || echo "cleaned up (good)"

# 3. Ctrl-Y copies instead of running:
~/.config/tmux/scripts/tmux-keys --pick   # highlight any row, press Ctrl-Y
tmux show-buffer                          # Expected: prints e.g. "prefix v"
test -s "${TMPDIR:-/tmp}/tmux-keys.$(id -u).cmd" && echo "cmd stashed (bad)" || echo "empty (good)"
```

All three expectations must hold before continuing.

- [ ] **Step 4: Commit**

```bash
git add tmux/scripts/tmux-keys
git commit -m "feat(tmux): tmux-keys interactive fzf picker with popup-safe execution"
```

---

### Task 3: Bind `prefix + ?` and document

Wires the entry point and records the tool in the tmux README.

**Files:**
- Modify: `tmux/tmux.reset.conf` (near the existing `display-popup` bindings, ~line 77-82)
- Modify: `tmux/README.md`

**Interfaces:**
- Consumes: `tmux-keys --pick` and `tmux-keys --exec` from Task 2.

- [ ] **Step 1: Add the binding**

In `tmux/tmux.reset.conf`, directly below the existing `bind -N "superpowers SDD ledger (popup)" G ...` line, add:

```tmux
bind -N "searchable keybindings (fzf popup)" ? {
  display-popup -w 80% -h 80% -E "~/.config/tmux/scripts/tmux-keys --pick"
  run-shell -b "~/.config/tmux/scripts/tmux-keys --exec"
}
```

(The `{ }` block runs `display-popup` — which blocks until dismissed — then `--exec`, so the chosen command runs only after the popup closes. This lets bindings that open their own popups, like `g`/`G`, work without nesting.)

- [ ] **Step 2: Reload config and verify the binding is registered**

Run (inside tmux):

```bash
tmux source-file ~/.config/tmux/tmux.conf
tmux list-keys -T prefix '?'
```

Expected: prints a `bind-key -T prefix ? { ... display-popup ... }` line referencing `tmux-keys`.

- [ ] **Step 3: Manual end-to-end test**

Press `prefix + ?`:
- Expected: the fzf popup opens; typing filters by key/description/command; the preview pane shows the full command via `bat`.
- Highlight a harmless binding (e.g. a split) and press `Enter`: the popup closes and the action runs on the underlying pane.
- Press `prefix + ?` again, highlight `g`, press `Enter`: lazygit opens in its own popup (confirms no popup-nesting problem).

- [ ] **Step 4: Document in the tmux README**

Add to `tmux/README.md` under an appropriate section (create a short "Scripts" or "Key bindings" note if none exists):

```markdown
### `prefix + ?` — searchable keybindings

Opens an fzf popup listing all key bindings (via `scripts/tmux-keys`). Fuzzy-search
by key, description, or command. `Enter` runs the selected binding; `Ctrl-Y` copies
the key combo to the tmux buffer. Descriptions come from binding `-N` notes where
present, otherwise the raw command.
```

- [ ] **Step 5: Commit**

```bash
git add tmux/tmux.reset.conf tmux/README.md
git commit -m "feat(tmux): bind prefix+? to searchable keybinding picker"
```

---

## Notes / Known Limitations

- `--exec` sources the chosen command against the most-recent client/pane. In the normal single-attached-session case this is the pane that pressed `prefix + ?`. With multiple simultaneously attached clients it could target the wrong pane — acceptable for a personal dotfiles tool.
- `copy-mode` / `copy-mode-vi` bindings are hidden by default (they're meaningless to run outside that mode). They can be surfaced by invoking `tmux-keys --pick --all` directly; not wired to a key by default (YAGNI).
- Command matching for the notes join normalizes keys by stripping backslashes (`\#` → `#`); a binding on a literal backslash key would not get its note. Harmless — it falls back to showing the command.
