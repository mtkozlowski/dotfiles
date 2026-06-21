# Brew Upgrade Change Summarizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `bup` run `brew upgrade` and then auto-generate a concise, changelog-based summary of what the upgrades introduce (critical bug fixes, new features, breaking changes), printed to the terminal and saved to a timestamped file.

**Architecture:** A sourceable shell library (`scripts/brew-changes-lib.sh`) holds all reusable logic (state dir, package extraction, agent invocation, delivery). Two thin executable scripts use it: `scripts/brew-upgrade-changes` (runs the upgrade then summarizes) and `scripts/brew-changes-last` (re-summarizes the most recent log). A `bup()` function in `zsh/.zshrc` delegates to the first script.

**Tech Stack:** Bash (POSIX-friendly), Homebrew (`brew`), Claude Code headless CLI (`claude -p`). Tests are plain-bash harness scripts using PATH stubs for `brew`/`claude` (no test framework — `bats` is not installed).

## Global Constraints

- Scripts live in `scripts/` (already on `PATH` via `zsh/.zshrc`: `export PATH="$HOME/dotfiles/scripts:$PATH"`). Executables get `chmod +x`, matching `scripts/claude-mv`.
- Dotfiles are shared between macOS and Linux. Anything that runs unconditionally (including `bup` being defined) must be harmless on machines without `brew` or `claude` — guard those shell-outs; never hard-error.
- State files go under `${XDG_STATE_HOME:-$HOME/.local/state}/brew-changes/`.
- Timestamp format for filenames: `YYYY-MM-DD-HHMMSS` (`date +%Y-%m-%d-%H%M%S`).
- Raw log: `<TS>.upgrade.log`. Summary: `<TS>.summary.md` (same `<TS>` per run).
- Agent invocation: `claude -p "<prompt>" --model "${BREW_NOTES_MODEL:-sonnet}" --allowed-tools "WebSearch WebFetch"`. (Verified to run clean and exit 0.)
- Package-line extraction pattern (ERE): `^[^[:space:]]+ [^[:space:]]+ -> [^[:space:]]+$`.
- Skip-agent switches: env `BREW_NOTES=0`, or `--no-notes` flag (consumed by the wrapper, NOT forwarded to `brew`).
- Always preserve `brew`'s own exit status as the script's exit status on the upgrade path.
- Bash safety header for every script/lib: `set -euo pipefail` is too aggressive for an interactive-sourced wrapper path; scripts use `set -uo pipefail` (no `-e`) so a failed agent step never kills the user's shell or masks brew's status. Handle errors explicitly.

---

## File Structure

- **Create** `scripts/brew-changes-lib.sh` — sourceable; defines `bc_state_dir`, `bc_extract_upgrades`, `bc_summarize`. No top-level side effects (safe to source).
- **Create** `scripts/brew-upgrade-changes` — executable; runs `brew upgrade`, tees to raw log, extracts, summarizes.
- **Create** `scripts/brew-changes-last` — executable; finds newest `*.upgrade.log`, re-summarizes.
- **Create** `scripts/tests/test-brew-changes.sh` — executable; plain-bash test harness with PATH stubs.
- **Create** `scripts/tests/fixtures/sample-upgrade.log` — captured sample `brew upgrade` output for tests.
- **Modify** `zsh/.zshrc` — replace `alias bup='brew upgrade'` with a `bup()` function.

---

## Task 1: Sourceable library — state dir + package extraction

**Files:**
- Create: `scripts/brew-changes-lib.sh`
- Create: `scripts/tests/fixtures/sample-upgrade.log`
- Create: `scripts/tests/test-brew-changes.sh`

**Interfaces:**
- Produces:
  - `bc_state_dir()` → prints the state dir path (`${XDG_STATE_HOME:-$HOME/.local/state}/brew-changes`), creating it with `mkdir -p`. Returns 0.
  - `bc_extract_upgrades <logfile>` → prints, one per line, the upgraded-package lines (`name old -> new`) found in `<logfile>`. Prints nothing and returns 0 when there are none.

- [ ] **Step 1: Create the test fixture**

Create `scripts/tests/fixtures/sample-upgrade.log` with realistic plain-text `brew upgrade` output:

```
==> Upgrading 14 outdated packages:
util-linux 2.42.1 -> 2.42.2
television 0.15.8 -> 0.15.9
luajit 2.1.1780076327 -> 2.1.1781602682
certifi 2026.5.20 -> 2026.6.17
fmt 12.1.0 -> 12.2.0
gh 2.94.0 -> 2.95.0
worktrunk 0.57.0 -> 0.60.0
tig 2.6.0 -> 2.6.1
libffi 3.5.2 -> 3.6.0
llhttp 9.4.1 -> 9.4.2
cloudflared 2026.6.0 -> 2026.6.1
carapace 1.7.0 -> 1.7.1
node 26.3.0 -> 26.3.1
jq 1.8.1 -> 1.8.2
==> Running `brew cleanup`...
Removing: /Users/x/Library/Caches/Homebrew/node--26.3.0... (12MB)
==> Caveats
==> node
Bash completion has been installed to: -> see docs
```

(The trailing `cleanup`/`Caveats` lines — including one with ` -> ` inside a caveat — are intentional: they verify extraction does not over-match.)

- [ ] **Step 2: Write the failing test harness with the first two tests**

Create `scripts/tests/test-brew-changes.sh`:

```bash
#!/usr/bin/env bash
# Test harness for brew-changes scripts. No framework; PATH stubs for brew/claude.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$HERE/.." && pwd)"
FIXTURES="$HERE/fixtures"

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n   %s\n' "$1" "$2"; }

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else nope "$1" "expected [$2] got [$3]"; fi
}
# assert_contains <name> <haystack> <needle>
assert_contains() {
  case "$3" in *"$2"*) ok "$1";; *) nope "$1" "[$3] does not contain [$2]";; esac
}

# shellcheck disable=SC1090
. "$SCRIPTS_DIR/brew-changes-lib.sh"

# --- bc_extract_upgrades ---
extracted="$(bc_extract_upgrades "$FIXTURES/sample-upgrade.log")"
count="$(printf '%s\n' "$extracted" | grep -c ' -> ' || true)"
assert_eq "extract: finds 14 package lines" "14" "$count"
assert_contains "extract: includes worktrunk line" "worktrunk 0.57.0 -> 0.60.0" "$extracted"
case "$extracted" in
  *Caveats*|*Bash\ completion*) nope "extract: excludes non-package lines" "leaked caveat/cleanup line";;
  *) ok "extract: excludes non-package lines";;
esac

# --- bc_extract_upgrades on empty input ---
empty_log="$(mktemp)"; printf 'Already up-to-date.\n' > "$empty_log"
empty_out="$(bc_extract_upgrades "$empty_log")"
assert_eq "extract: empty when nothing upgraded" "" "$empty_out"
rm -f "$empty_log"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

`chmod +x scripts/tests/test-brew-changes.sh`.

- [ ] **Step 3: Run the test to verify it fails**

Run: `scripts/tests/test-brew-changes.sh`
Expected: FAIL — `brew-changes-lib.sh` does not exist yet, so sourcing errors / `bc_extract_upgrades: command not found`.

- [ ] **Step 4: Write the minimal library**

Create `scripts/brew-changes-lib.sh`:

```bash
#!/usr/bin/env bash
# Sourceable helpers for the brew-changes scripts. No side effects on source.

bc_state_dir() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/brew-changes"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# bc_extract_upgrades <logfile>: print "name old -> new" lines only.
bc_extract_upgrades() {
  local log="$1"
  [ -f "$log" ] || return 0
  grep -E '^[^[:space:]]+ [^[:space:]]+ -> [^[:space:]]+$' "$log" || true
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `scripts/tests/test-brew-changes.sh`
Expected: PASS — `4 passed, 0 failed` (extract count=14, includes worktrunk, excludes caveats, empty case).

- [ ] **Step 6: Commit**

```bash
git add scripts/brew-changes-lib.sh scripts/tests/test-brew-changes.sh scripts/tests/fixtures/sample-upgrade.log
git commit -m "feat(brew-changes): library + tests for upgrade-line extraction"
```

---

## Task 2: Agent invocation + delivery (`bc_summarize`)

**Files:**
- Modify: `scripts/brew-changes-lib.sh`
- Modify: `scripts/tests/test-brew-changes.sh`

**Interfaces:**
- Consumes: `bc_state_dir`.
- Produces:
  - `bc_summarize <pkg_list_text> <summary_outfile>` → builds the prompt from `<pkg_list_text>`, runs `claude -p` with web tools, writes its stdout to `<summary_outfile>`, prints the summary to stdout, then prints `Saved: <summary_outfile>`. Returns the claude exit status. If `claude` is not on PATH, prints a note to stderr and returns 0 without writing a summary.

- [ ] **Step 1: Add the failing tests for `bc_summarize`**

Append to `scripts/tests/test-brew-changes.sh` before the final summary `printf`:

```bash
# --- bc_summarize: uses a claude stub, writes + prints summary + path ---
stubdir="$(mktemp -d)"
cat > "$stubdir/claude" <<'STUB'
#!/usr/bin/env bash
# record argv, ignore the prompt, emit a canned summary
printf '%s\n' "$@" > "$STUB_ARGS_FILE"
echo "## gh 2.94.0 -> 2.95.0"
echo "- New: example feature"
STUB
chmod +x "$stubdir/claude"
export STUB_ARGS_FILE="$stubdir/args"

out_file="$(mktemp)"
PATH="$stubdir:$PATH" \
  summary_out="$(bc_summarize "gh 2.94.0 -> 2.95.0" "$out_file")"

assert_contains "summarize: prints summary heading" "## gh 2.94.0 -> 2.95.0" "$summary_out"
assert_contains "summarize: prints saved path" "Saved: $out_file" "$summary_out"
assert_contains "summarize: writes summary file" "example feature" "$(cat "$out_file")"
assert_contains "summarize: passes --model" "sonnet" "$(cat "$STUB_ARGS_FILE")"
assert_contains "summarize: allows web tools" "WebSearch" "$(cat "$STUB_ARGS_FILE")"

# --- bc_summarize: missing claude is non-fatal ---
emptybin="$(mktemp -d)"
out_file2="$(mktemp)"
set +e
PATH="$emptybin" bc_summarize "gh 1 -> 2" "$out_file2" >/dev/null 2>&1
rc=$?
set -e 2>/dev/null || true
assert_eq "summarize: missing claude returns 0" "0" "$rc"

rm -rf "$stubdir" "$emptybin"; rm -f "$out_file" "$out_file2"
```

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run: `scripts/tests/test-brew-changes.sh`
Expected: FAIL — `bc_summarize: command not found` (function not defined yet).

- [ ] **Step 3: Implement `bc_summarize`**

Append to `scripts/brew-changes-lib.sh`:

```bash
# bc_summarize <pkg_list_text> <summary_outfile>
bc_summarize() {
  local pkgs="$1" out="$2"
  if ! command -v claude >/dev/null 2>&1; then
    printf 'brew-changes: claude CLI not found; skipping summary.\n' >&2
    return 0
  fi

  local prompt
  prompt="$(cat <<EOF
You are summarizing Homebrew package upgrades for a developer.

Here is the list of upgraded packages as "name old_version -> new_version":

$pkgs

For each package, look up the actual release notes / changelog between the old
and new version using web search and fetch. Then write a CONCISE markdown
digest grouped by package, focused ONLY on:
- critical bug fixes
- new functionality the user can use
- breaking changes

Collapse trivial library patch-bumps with no user-visible change into a single
short line at the end (e.g. "Minor lib bumps: libffi, llhttp, fmt"). No filler,
no preamble, no restating version numbers I already gave you beyond a short
heading per notable package. This is a quick post-upgrade digest.
EOF
)"

  local model="${BREW_NOTES_MODEL:-sonnet}"
  local rc
  claude -p "$prompt" --model "$model" --allowed-tools "WebSearch WebFetch" \
    | tee "$out"
  rc="${PIPESTATUS[0]}"
  printf '\nSaved: %s\n' "$out"
  return "$rc"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `scripts/tests/test-brew-changes.sh`
Expected: PASS — all prior tests plus the 6 new `summarize:` assertions pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/brew-changes-lib.sh scripts/tests/test-brew-changes.sh
git commit -m "feat(brew-changes): bc_summarize agent invocation + delivery"
```

---

## Task 3: `brew-upgrade-changes` driver script

**Files:**
- Create: `scripts/brew-upgrade-changes`
- Modify: `scripts/tests/test-brew-changes.sh`

**Interfaces:**
- Consumes: `bc_state_dir`, `bc_extract_upgrades`, `bc_summarize`.
- Produces: executable `brew-upgrade-changes [--no-notes] [brew-upgrade-args...]`.
  Behavior: guards missing `brew`; runs `brew upgrade <args>` teeing to raw log;
  extracts upgrades; if none → prints "nothing upgraded" and exits with brew's
  status; else (unless skipped) → calls `bc_summarize`. `--no-notes`/`BREW_NOTES=0`
  skip the agent. Exit status = brew's upgrade status.

- [ ] **Step 1: Add failing integration tests (brew + claude stubbed)**

Append to `scripts/tests/test-brew-changes.sh` (before the final summary `printf`):

```bash
# Helper: build a stub dir with a brew that prints the fixture, and a claude stub.
make_stubs() { # <dir> <brew_output_file>
  local d="$1" out="$2"
  cat > "$d/brew" <<STUB
#!/usr/bin/env bash
cat "$out"
exit 0
STUB
  cat > "$d/claude" <<'STUB'
#!/usr/bin/env bash
touch "$CLAUDE_CALLED_MARKER"
echo "## summary from stub"
STUB
  chmod +x "$d/brew" "$d/claude"
}

DRIVER="$SCRIPTS_DIR/brew-upgrade-changes"

# --- happy path: upgrades present -> summary produced, raw log saved ---
sd="$(mktemp -d)"; make_stubs "$sd" "$FIXTURES/sample-upgrade.log"
state="$(mktemp -d)"
export CLAUDE_CALLED_MARKER="$sd/called"
hp_out="$(PATH="$sd:$PATH" XDG_STATE_HOME="$state" "$DRIVER")"
assert_contains "driver: prints agent summary" "## summary from stub" "$hp_out"
assert_contains "driver: prints saved path" "Saved:" "$hp_out"
[ -f "$sd/called" ] && ok "driver: agent was called" || nope "driver: agent was called" "marker missing"
ls "$state/brew-changes/"*.upgrade.log >/dev/null 2>&1 \
  && ok "driver: raw log written" || nope "driver: raw log written" "no .upgrade.log"
ls "$state/brew-changes/"*.summary.md >/dev/null 2>&1 \
  && ok "driver: summary file written" || nope "driver: summary file written" "no .summary.md"

# --- --no-notes: agent NOT called ---
rm -f "$sd/called"
PATH="$sd:$PATH" XDG_STATE_HOME="$state" "$DRIVER" --no-notes >/dev/null 2>&1
[ -f "$sd/called" ] && nope "driver: --no-notes skips agent" "marker present" \
  || ok "driver: --no-notes skips agent"

# --- BREW_NOTES=0: agent NOT called ---
rm -f "$sd/called"
PATH="$sd:$PATH" XDG_STATE_HOME="$state" BREW_NOTES=0 "$DRIVER" >/dev/null 2>&1
[ -f "$sd/called" ] && nope "driver: BREW_NOTES=0 skips agent" "marker present" \
  || ok "driver: BREW_NOTES=0 skips agent"

# --- nothing upgraded: no agent, friendly message ---
sd2="$(mktemp -d)"
nolog="$(mktemp)"; printf 'Already up-to-date.\n' > "$nolog"
make_stubs "$sd2" "$nolog"
export CLAUDE_CALLED_MARKER="$sd2/called"
noup_out="$(PATH="$sd2:$PATH" XDG_STATE_HOME="$state" "$DRIVER")"
assert_contains "driver: nothing-upgraded message" "othing upgraded" "$noup_out"
[ -f "$sd2/called" ] && nope "driver: no agent when nothing upgraded" "marker present" \
  || ok "driver: no agent when nothing upgraded"

# --- missing brew: graceful, no crash ---
eb="$(mktemp -d)"  # empty bin: no brew
set +e
PATH="$eb" XDG_STATE_HOME="$state" "$DRIVER" >/dev/null 2>&1
rc_nobrew=$?
set -e 2>/dev/null || true
assert_eq "driver: missing brew exits 0" "0" "$rc_nobrew"

rm -rf "$sd" "$sd2" "$eb" "$state"; rm -f "$nolog"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `scripts/tests/test-brew-changes.sh`
Expected: FAIL — `brew-upgrade-changes` does not exist (`No such file or directory`).

- [ ] **Step 3: Write the driver script**

Create `scripts/brew-upgrade-changes`:

```bash
#!/usr/bin/env bash
# Run `brew upgrade`, then summarize what the upgrades introduce via an agent.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$DIR/brew-changes-lib.sh"

if ! command -v brew >/dev/null 2>&1; then
  printf 'brew-changes: brew not found on PATH; nothing to do.\n' >&2
  exit 0
fi

# Parse our own flag; forward everything else to brew.
notes=1
[ "${BREW_NOTES:-1}" = "0" ] && notes=0
brew_args=()
for a in "$@"; do
  case "$a" in
    --no-notes) notes=0 ;;
    *) brew_args+=("$a") ;;
  esac
done

state="$(bc_state_dir)"
ts="$(date +%Y-%m-%d-%H%M%S)"
raw="$state/$ts.upgrade.log"

# Run the upgrade, stream to terminal AND capture to the raw log.
brew upgrade "${brew_args[@]}" 2>&1 | tee "$raw"
brew_rc="${PIPESTATUS[0]}"

pkgs="$(bc_extract_upgrades "$raw")"
if [ -z "$pkgs" ]; then
  printf '\nbrew-changes: nothing upgraded.\n'
  exit "$brew_rc"
fi

if [ "$notes" -eq 0 ]; then
  printf '\nbrew-changes: %d package(s) upgraded (summary skipped). Raw log: %s\n' \
    "$(printf '%s\n' "$pkgs" | grep -c ' -> ')" "$raw"
  exit "$brew_rc"
fi

printf '\nbrew-changes: summarizing %d upgrade(s)...\n' \
  "$(printf '%s\n' "$pkgs" | grep -c ' -> ')"
bc_summarize "$pkgs" "$state/$ts.summary.md" || \
  printf 'brew-changes: summary step failed; raw log saved: %s (retry: brew-changes-last)\n' "$raw" >&2

exit "$brew_rc"
```

`chmod +x scripts/brew-upgrade-changes`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `scripts/tests/test-brew-changes.sh`
Expected: PASS — happy path, `--no-notes`, `BREW_NOTES=0`, nothing-upgraded, missing-brew all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/brew-upgrade-changes scripts/tests/test-brew-changes.sh
git commit -m "feat(brew-changes): brew-upgrade-changes driver script"
```

---

## Task 4: `brew-changes-last` re-summarize script

**Files:**
- Create: `scripts/brew-changes-last`
- Modify: `scripts/tests/test-brew-changes.sh`

**Interfaces:**
- Consumes: `bc_state_dir`, `bc_extract_upgrades`, `bc_summarize`.
- Produces: executable `brew-changes-last` — finds the newest `*.upgrade.log` in
  the state dir, extracts its upgrades, and re-runs `bc_summarize` into a
  `<that-TS>.summary.md`. If no logs exist, prints a note and exits 0.

- [ ] **Step 1: Add failing tests for `brew-changes-last`**

Append to `scripts/tests/test-brew-changes.sh` (before the final summary `printf`):

```bash
LAST="$SCRIPTS_DIR/brew-changes-last"

# --- re-summarize newest log ---
st="$(mktemp -d)"; mkdir -p "$st/brew-changes"
cp "$FIXTURES/sample-upgrade.log" "$st/brew-changes/2026-06-20-100000.upgrade.log"
cp "$FIXTURES/sample-upgrade.log" "$st/brew-changes/2026-06-21-100000.upgrade.log"
sb="$(mktemp -d)"
cat > "$sb/claude" <<'STUB'
#!/usr/bin/env bash
echo "## re-summary stub"
STUB
chmod +x "$sb/claude"
last_out="$(PATH="$sb:$PATH" XDG_STATE_HOME="$st" "$LAST")"
assert_contains "last: prints re-summary" "## re-summary stub" "$last_out"
[ -f "$st/brew-changes/2026-06-21-100000.summary.md" ] \
  && ok "last: writes summary for newest log" \
  || nope "last: writes summary for newest log" "expected newest .summary.md"

# --- no logs present: graceful ---
st2="$(mktemp -d)"
set +e
PATH="$sb:$PATH" XDG_STATE_HOME="$st2" "$LAST" >/dev/null 2>&1
rc_nolog=$?
set -e 2>/dev/null || true
assert_eq "last: no logs exits 0" "0" "$rc_nolog"

rm -rf "$st" "$st2" "$sb"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `scripts/tests/test-brew-changes.sh`
Expected: FAIL — `brew-changes-last` does not exist.

- [ ] **Step 3: Write `brew-changes-last`**

Create `scripts/brew-changes-last`:

```bash
#!/usr/bin/env bash
# Re-summarize the most recent `brew upgrade` log without re-running brew.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$DIR/brew-changes-lib.sh"

state="$(bc_state_dir)"
# Newest by filename (timestamps sort lexicographically).
raw="$(ls -1 "$state"/*.upgrade.log 2>/dev/null | sort | tail -n1)"
if [ -z "$raw" ]; then
  printf 'brew-changes: no upgrade logs found in %s\n' "$state" >&2
  exit 0
fi

pkgs="$(bc_extract_upgrades "$raw")"
if [ -z "$pkgs" ]; then
  printf 'brew-changes: no upgraded packages found in %s\n' "$raw" >&2
  exit 0
fi

ts="$(basename "$raw" .upgrade.log)"
printf 'brew-changes: re-summarizing %s\n' "$raw"
bc_summarize "$pkgs" "$state/$ts.summary.md"
```

`chmod +x scripts/brew-changes-last`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `scripts/tests/test-brew-changes.sh`
Expected: PASS — `last:` assertions green; full suite passes.

- [ ] **Step 5: Commit**

```bash
git add scripts/brew-changes-last scripts/tests/test-brew-changes.sh
git commit -m "feat(brew-changes): brew-changes-last re-summarize script"
```

---

## Task 5: Wire up `bup` in `zsh/.zshrc`

**Files:**
- Modify: `zsh/.zshrc` (the `# brew` block, currently lines ~94-96)

**Interfaces:**
- Consumes: `brew-upgrade-changes` (on PATH via `scripts/`).
- Produces: `bup` shell function replacing the old alias.

- [ ] **Step 1: Replace the alias with a function**

In `zsh/.zshrc`, find:

```zsh
# brew
alias bu='brew update'
alias bup='brew upgrade'
```

Replace with:

```zsh
# brew
alias bu='brew update'
# bup: upgrade, then summarize what the upgrades introduce (see scripts/brew-upgrade-changes).
# Use `bup --no-notes` or `BREW_NOTES=0 bup` to skip the agent.
bup() { brew-upgrade-changes "$@" }
```

- [ ] **Step 2: Verify zsh parses the file without error**

Run: `zsh -n zsh/.zshrc`
Expected: no output, exit 0 (syntax OK).

- [ ] **Step 3: Verify the function resolves to the script in a real shell**

Run: `zsh -ic 'source zsh/.zshrc 2>/dev/null; type bup; command -v brew-upgrade-changes'`
Expected: `bup` is shown as a shell function, and the `brew-upgrade-changes` path is printed (confirming it's on PATH). If the path is missing, confirm `scripts/` is on PATH in this shell.

- [ ] **Step 4: Commit**

```bash
git add zsh/.zshrc
git commit -m "feat(brew): bup wraps brew upgrade with change summarizer"
```

---

## Task 6: End-to-end smoke test + README note

**Files:**
- Modify: `zsh/README.md` (document the new `bup` behavior and knobs)
- Run: full test suite + one real dry invocation

- [ ] **Step 1: Run the full test suite**

Run: `scripts/tests/test-brew-changes.sh`
Expected: `N passed, 0 failed` (all tasks' assertions).

- [ ] **Step 2: Real no-op smoke test (safe; no packages changed)**

Run: `BREW_NOTES=0 brew-changes-last; echo "rc=$?"` (re-summarize path is read-only-ish; with `BREW_NOTES=0` unset it would call the agent — here we only confirm it locates logs or reports none).
Expected: either "no upgrade logs found" (clean machine) or it prints a real summary. Either way `rc=0`. This confirms wiring without forcing a real `brew upgrade`.

- [ ] **Step 3: Document in `zsh/README.md`**

Add a short section near the brew/alias docs:

```markdown
## brew upgrade summaries

`bup` runs `brew upgrade` and then uses the `claude` CLI to summarize what the
upgrades introduce (critical fixes, new features, breaking changes).

- Summaries and raw logs are saved under `${XDG_STATE_HOME:-~/.local/state}/brew-changes/`.
- `bup --no-notes` (or `BREW_NOTES=0 bup`) upgrades without the summary.
- `BREW_NOTES_MODEL=opus bup` overrides the model (default: `sonnet`).
- `brew-changes-last` re-generates the summary for the most recent upgrade.

Requires `brew` and the `claude` CLI; on machines without them, `bup` degrades
gracefully (plain upgrade, or a no-op note).
```

- [ ] **Step 4: Commit**

```bash
git add zsh/README.md
git commit -m "docs(zsh): document bup change summaries"
```

---

## Self-Review

**Spec coverage:**
- Wrapped upgrade, auto-trigger → Task 3 + Task 5. ✓
- Raw log capture (`<TS>.upgrade.log`) → Task 3. ✓
- Package extraction from `name old -> new` lines → Task 1. ✓
- No-op short-circuit when nothing upgraded → Task 3. ✓
- `--no-notes` / `BREW_NOTES=0` skip → Task 3 (tested). ✓
- `claude -p` + WebSearch/WebFetch + `BREW_NOTES_MODEL` default `sonnet` → Task 2. ✓
- Inline print + saved `<TS>.summary.md` + print path on success → Task 2 (`bc_summarize` prints summary and `Saved:` path). ✓
- `brew-changes-last` as a separate script reusing shared lib → Task 4. ✓
- Brew guard / claude guard / shared-dotfiles safety → Task 2 (claude), Task 3 (brew). ✓
- Interruptible / failure preserves raw log → Task 3 (summary failure prints raw-log path + retry hint). ✓
- Storage layout under `${XDG_STATE_HOME:-$HOME/.local/state}/brew-changes/` → Task 1 (`bc_state_dir`). ✓
- Out-of-scope items (background, notifications, caching, pruning) → not implemented. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases" — every code/test step has full content. ✓

**Type/name consistency:** `bc_state_dir`, `bc_extract_upgrades`, `bc_summarize` used identically across Tasks 1-4. Filename scheme `<TS>.upgrade.log` / `<TS>.summary.md` consistent across Tasks 3-4. Flag `--no-notes` and env `BREW_NOTES`/`BREW_NOTES_MODEL` consistent across Tasks 2-3 and README. ✓
