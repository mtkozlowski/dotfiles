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
set +e
PATH="/usr/bin:/bin" XDG_STATE_HOME="$state" "$DRIVER" >/dev/null 2>&1
rc_nobrew=$?
set -e 2>/dev/null || true
assert_eq "driver: missing brew exits 0" "0" "$rc_nobrew"

rm -rf "$sd" "$sd2" "$state"; rm -f "$nolog"

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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
