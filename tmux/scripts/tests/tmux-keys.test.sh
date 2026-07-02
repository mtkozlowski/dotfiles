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

# --- parse_notes: prefixed "C-a !" form yields the real key ---
cat > "$TMP/n_prefixed" <<'EOF'
C-a !       Break pane to a new window
C-a g       lazygit (popup)
EOF
outp="$("$SCRIPT" --parse-notes prefix < "$TMP/n_prefixed")"
[ "$(printf '%s\n' "$outp" | grep -c .)" -eq 2 ]; check "parse_notes: one row per note" $?
printf '%s\n' "$outp" | grep -q "^prefix"$'\t'"!"$'\t'"Break pane to a new window$"; check "parse_notes: C-a ! -> key !" $?
printf '%s\n' "$outp" | grep -q "^prefix"$'\t'"g"$'\t'"lazygit (popup)$"; check "parse_notes: C-a g -> key g" $?

# --- parse_notes: bare "!" form still works ---
printf '!       Break pane to a new window\n' > "$TMP/n_bare"
outb="$("$SCRIPT" --parse-notes prefix < "$TMP/n_bare")"
printf '%s\n' "$outb" | grep -q "^prefix"$'\t'"!"$'\t'"Break pane to a new window$"; check "parse_notes: bare key ! works" $?

# --- end-to-end: parse_notes output joins as description in build_rows ---
"$SCRIPT" --parse-notes prefix < "$TMP/n_prefixed" > "$TMP/notes2"
printf 'bind-key    -T prefix g       display-popup -E "lazygit"\n' > "$TMP/raw2"
out2="$("$SCRIPT" --build-rows "$TMP/notes2" < "$TMP/raw2")"
grep -q "lazygit (popup)" <<<"$out2"; check "note joins onto binding g (end-to-end)" $?

exit $fail
