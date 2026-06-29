#!/usr/bin/env bash
# Sourceable helpers for the brew-changes scripts. No side effects on source.

bc_state_dir() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/brew-changes"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# bc_extract_upgrades <logfile>: print "name old -> new" lines only.
# brew pads columns with runs of spaces and may append a " (size)"; it also
# prints the same package list in several blocks (would-upgrade / upgrading /
# upgraded). So match loosely, drop the size, collapse whitespace, and dedupe.
bc_extract_upgrades() {
  local log="$1"
  [ -f "$log" ] || return 0
  grep -E '^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+->[[:space:]]+[^[:space:]]+([[:space:]]+\([^)]*\))?[[:space:]]*$' "$log" \
    | sed -E 's/[[:space:]]+\([^)]*\)[[:space:]]*$//' \
    | awk '{ $1=$1; print }' \
    | awk '!seen[$0]++'
}

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
and new version using web search and fetch.

IMPORTANT OUTPUT RULE: Do ALL of your research via tool calls first. Do NOT
write any of the summary while you are still searching — interim text is
discarded and only your single final message is kept. When research is done,
emit the ENTIRE digest at once as your final message, covering every notable
package in that one response.

The digest is CONCISE markdown grouped by package, focused ONLY on:
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
  # stdin from /dev/null: in print mode claude otherwise waits on stdin (3s
  # warning) and would consume the user's terminal input when run from bup.
  claude -p "$prompt" --model "$model" --allowed-tools "WebSearch WebFetch" \
    </dev/null | tee "$out"
  rc="${PIPESTATUS[0]}"
  printf '\nSaved: %s\n' "$out"
  return "$rc"
}
