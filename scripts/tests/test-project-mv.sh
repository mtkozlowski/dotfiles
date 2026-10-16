#!/usr/bin/env bash
# Test harness for project-mv. Builds a fake $HOME with every store the tool touches.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/../project-mv"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n   %s\n' "$1" "$2"; }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else nope "$1" "expected [$2] got [$3]"; fi; }
assert_file_has() { if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else nope "$1" "$2 lacks [$3]"; fi; }
assert_file_lacks() { if grep -qF -- "$3" "$2" 2>/dev/null; then nope "$1" "$2 still has [$3]"; else ok "$1"; fi; }

# Resolved form, because agents record the resolved working directory (/private/var on macOS).
TMP="$(mktemp -d "${TMPDIR:-/tmp}/project-mv-test.XXXXXX")" || exit 1
T="$(cd "$TMP" && pwd -P)" || exit 1
trap '[ -n "${BLOCKER:-}" ] && kill "$BLOCKER" 2>/dev/null; rm -rf "$TMP"' EXIT
export HOME="$T/home" XDG_DATA_HOME="$T/home/.local/share" XDG_STATE_HOME="$T/home/.local/state" _ZO_DATA_DIR="$T/zoxide"
mkdir -p "$HOME" "$_ZO_DATA_DIR"
H="$HOME"
P="$H/Projects"
OLD="$P/app"
NEW="$P/work/app"
enc() { printf %s "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
penc() { printf %s "${1#/}" | tr / -; }

# Runs the tool as a module so the checks for running Claude and Paseo processes can be stubbed.
mv_tool() {
  python3 - "$TOOL" "$@" <<'EOF'
import sys, importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader("project_mv", sys.argv[1])
spec = importlib.util.spec_from_loader("project_mv", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
m.running_commands = lambda: set()
m.paseo_running = lambda: False
sys.argv = ["project-mv", *sys.argv[2:]]
m.main()
EOF
}

# --- fixture: git repo with a worktrunk sibling worktree, a subdirectory and a look-alike project ---
mkdir -p "$OLD/sub" "$P/app-v2" "$P/app.claude-version" "$P/work"
git -C "$OLD" init -q -b main
git -C "$OLD" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$OLD" worktree add -q "$P/app-worktrees/feat" -b feat
mkdir -p "$OLD/.claude"
printf '{"permissions":{"allow":["Read(%s/**)"]}}\n' "$OLD" > "$OLD/.claude/settings.local.json"

C="$H/.claude/projects"
mkdir -p "$C/$(enc "$OLD")/memory" "$C/$(enc "$P/app-worktrees/feat")" "$C/$(enc "$OLD/sub")/memory" "$C/$(enc "$P/app-v2")"
printf '{"cwd":"%s","text":"see %s/src, %s/x, %s and %s/.claude/projects/%s/memory"}\n' \
  "$OLD" "$OLD" "$P/app-v2" "$P/app.claude-version" "$H" "$(enc "$OLD")" > "$C/$(enc "$OLD")/s1.jsonl"
printf -- '- project lives in %s.\n' "$OLD" > "$C/$(enc "$OLD")/memory/MEMORY.md"
printf '{"cwd":"%s"}\n' "$P/app-worktrees/feat" > "$C/$(enc "$P/app-worktrees/feat")/s2.jsonl"
printf 'sub memory\n' > "$C/$(enc "$OLD/sub")/memory/MEMORY.md"
printf '{"cwd":"%s"}\n' "$P/app-v2" > "$C/$(enc "$P/app-v2")/s3.jsonl"
printf '{"display":"a","project":"%s"}\n{"display":"b","project":"%s"}\n' "$OLD" "$P/app-v2" > "$H/.claude/history.jsonl"
cat > "$H/.claude.json" <<EOF
{
  "projects": {
    "$OLD": {"allowedTools": ["a"]},
    "$P/app-v2": {"allowedTools": ["b"]},
    "$P/app-worktrees/feat": {}
  },
  "githubRepoPaths": {"o/app": ["$OLD", "$P/app-worktrees/feat"]}
}
EOF

mkdir -p "$H/.codex/sessions"
printf '[projects."%s"]\ntrust_level = "trusted"\n' "$OLD" > "$H/.codex/config.toml"
printf '{"payload":{"cwd":"%s"}}\n' "$OLD" > "$H/.codex/sessions/r1.jsonl"
sqlite3 "$H/.codex/state_5.sqlite" "create table threads(id text primary key, rollout_path text, cwd text);
  create table project_roots(project_id text, position int, path text);
  insert into threads values('t1','$H/.codex/sessions/r1.jsonl','$OLD');
  insert into project_roots values('p1',0,'$P/app-v2');"

mkdir -p "$XDG_DATA_HOME/opencode"
sqlite3 "$XDG_DATA_HOME/opencode/opencode.db" "create table project(id text primary key, worktree text, sandboxes text);
  create table session(id text primary key, directory text);
  create table project_directory(project_id text, directory text, primary key(project_id, directory));
  insert into project values('o1','$OLD','[\"$P/app.claude-version\",\"$OLD/sub\"]');
  insert into session values('s1','$OLD/sub');
  insert into project_directory values('o1','$OLD');"

A="$H/.paseo/agents/$(penc "$OLD")"
mkdir -p "$A" "$H/.paseo/projects"
printf '{\n  "cwd": "%s",\n  "persistence": {"metadata": {"cwd": "%s"}}\n}\n' "$OLD" "$OLD" > "$A/a1.json"
printf '[\n  {"rootPath": "%s"}, {"rootPath": "%s"}\n]\n' "$OLD" "$P/app-v2" > "$H/.paseo/projects/projects.json"

zoxide add "$OLD" "$OLD/sub"

snapshot() { (cd "$H" && find . -type f -not -path './.local/state/*' | sort | xargs shasum 2>/dev/null) ; }

# --- a running agent inside the project blocks the move ---
# A copied system binary is killed on macOS and a symlink keeps its target's name, so build one.
mkdir -p "$T/bin"
printf '#include <unistd.h>\nint main(void) { sleep(30); return 0; }\n' > "$T/bin/claude.c"
cc -o "$T/bin/claude" "$T/bin/claude.c" || { echo "cc is needed for the blocker test"; exit 1; }
(cd "$OLD/sub" && exec "$T/bin/claude" 30) & BLOCKER=$!
sleep 1
out="$(mv_tool -y -p "$OLD" "$NEW" 2>&1)"; status=$?
assert_eq "blocker: exits 1" "1" "$status"
case "$out" in *"agent processes"*) ok "blocker: names the agent";; *) nope "blocker: names the agent" "$out";; esac
kill "$BLOCKER" 2>/dev/null; wait "$BLOCKER" 2>/dev/null; BLOCKER=
[ -d "$OLD" ] && ok "blocker: nothing moved" || nope "blocker: nothing moved" "$OLD is gone"

# --- dry run changes nothing ---
before="$(snapshot)"
mv_tool -n "$OLD" "$NEW" > "$T/dry.out" 2>&1
assert_eq "dry run: exits 0" "0" "$?"
assert_eq "dry run: no file changed" "$before" "$(snapshot)"
assert_file_has "dry run: plans the move" "$T/dry.out" "plan: move $OLD -> $NEW"

# --- real run ---
mv_tool -y "$OLD" "$NEW" > "$T/run.out" 2>&1
assert_eq "run: exits 0" "0" "$?" || cat "$T/run.out"
[ ! -e "$OLD" ] && [ -d "$NEW/sub" ] && ok "dir: moved" || nope "dir: moved" "$(ls "$P")"
[ -d "$P/work/app-worktrees/feat" ] && ok "dir: worktrunk sibling moved" || nope "dir: worktrunk sibling moved" "$(ls "$P/work")"
assert_eq "git: worktree works" "feat" "$(git -C "$P/work/app-worktrees/feat" branch --show-current 2>&1)"
assert_eq "git: main lists new worktree path" "$P/work/app-worktrees/feat" \
  "$(git -C "$NEW" worktree list --porcelain | sed -n 's/^worktree //p' | sed -n 2p)"
assert_file_has "settings: rewritten" "$NEW/.claude/settings.local.json" "Read($NEW/**)"

[ -f "$C/$(enc "$NEW")/s1.jsonl" ] && ok "claude: main folder renamed" || nope "claude: main folder renamed" "$(ls "$C")"
[ -f "$C/$(enc "$P/work/app-worktrees/feat")/s2.jsonl" ] && ok "claude: worktree folder renamed" || nope "claude: worktree folder renamed" "$(ls "$C")"
[ -f "$C/$(enc "$NEW/sub")/memory/MEMORY.md" ] && ok "claude: memory-only subfolder renamed" || nope "claude: memory-only subfolder renamed" "$(ls "$C")"
[ -f "$C/$(enc "$P/app-v2")/s3.jsonl" ] && ok "claude: look-alike folder untouched" || nope "claude: look-alike folder untouched" "$(ls "$C")"
S1="$C/$(enc "$NEW")/s1.jsonl"
assert_file_has "claude: cwd rewritten" "$S1" "\"cwd\":\"$NEW\""
assert_file_has "claude: encoded memory path rewritten" "$S1" "projects/$(enc "$NEW")/memory"
assert_file_has "claude: look-alike path kept" "$S1" "$P/app-v2/x"
assert_file_has "claude: dotted look-alike kept" "$S1" "$P/app.claude-version"
assert_file_has "claude: memory rewritten" "$C/$(enc "$NEW")/memory/MEMORY.md" "lives in $NEW."
assert_file_has "history: moved project rewritten" "$H/.claude/history.jsonl" "\"project\":\"$NEW\""
assert_file_has "history: look-alike kept" "$H/.claude/history.jsonl" "\"project\":\"$P/app-v2\""
assert_eq "claude.json: project keys" "$P/app-v2,$NEW,$P/work/app-worktrees/feat" \
  "$(jq -r '.projects | keys | sort | join(",")' "$H/.claude.json")"
assert_eq "claude.json: settings kept" "a" "$(jq -r --arg k "$NEW" '.projects[$k].allowedTools[0]' "$H/.claude.json")"
assert_eq "claude.json: githubRepoPaths" "$NEW,$P/work/app-worktrees/feat" "$(jq -r '.githubRepoPaths["o/app"] | join(",")' "$H/.claude.json")"

assert_file_has "codex: config key" "$H/.codex/config.toml" "[projects.\"$NEW\"]"
assert_eq "codex: thread cwd" "$NEW" "$(sqlite3 "$H/.codex/state_5.sqlite" "select cwd from threads")"
assert_eq "codex: unrelated root kept" "$P/app-v2" "$(sqlite3 "$H/.codex/state_5.sqlite" "select path from project_roots")"
assert_file_has "codex: rollout rewritten" "$H/.codex/sessions/r1.jsonl" "\"cwd\":\"$NEW\""

DB="$XDG_DATA_HOME/opencode/opencode.db"
assert_eq "opencode: worktree" "$NEW" "$(sqlite3 "$DB" "select worktree from project")"
assert_eq "opencode: sandboxes" "[\"$P/app.claude-version\",\"$NEW/sub\"]" "$(sqlite3 "$DB" "select sandboxes from project")"
assert_eq "opencode: session" "$NEW/sub" "$(sqlite3 "$DB" "select directory from session")"
assert_eq "opencode: project_directory" "$NEW" "$(sqlite3 "$DB" "select directory from project_directory")"

A2="$H/.paseo/agents/$(penc "$NEW")"
[ -f "$A2/a1.json" ] && ok "paseo: agent folder renamed" || nope "paseo: agent folder renamed" "$(ls "$H/.paseo/agents")"
assert_eq "paseo: agent cwd" "$NEW $NEW" "$(jq -r '"\(.cwd) \(.persistence.metadata.cwd)"' "$A2/a1.json")"
assert_eq "paseo: projects" "$NEW $P/app-v2" "$(jq -r 'map(.rootPath) | join(" ")' "$H/.paseo/projects/projects.json")"

assert_eq "zoxide: entries moved" "$NEW $NEW/sub" "$(zoxide query --list --all | sort | tr '\n' ' ' | sed 's/ $//')"
ls "$XDG_STATE_HOME/project-mv/"*/moves.txt >/dev/null 2>&1 && ok "backup: moves recorded" || nope "backup: moves recorded" "no moves.txt"

# --- running again after the move changes nothing ---
before="$(snapshot)"
mv_tool -y "$OLD" "$NEW" > "$T/again.out" 2>&1
assert_eq "rerun: exits 0" "0" "$?"
assert_eq "rerun: no file changed" "$before" "$(snapshot)"

# --- with Claude running, ~/.claude.json is left for later ---
mv_tool -y "$NEW" "$P/app" >/dev/null 2>&1
mv_running() {
  python3 - "$TOOL" "$@" <<'EOF'
import sys, importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader("project_mv", sys.argv[1])
spec = importlib.util.spec_from_loader("project_mv", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
m.running_commands = lambda: {"claude"}
m.paseo_running = lambda: False
sys.argv = ["project-mv", *sys.argv[2:]]
m.main()
EOF
}
out="$(mv_running -y "$P/app" "$NEW" 2>&1)"; status=$?
assert_eq "claude running: exits 3" "3" "$status"
assert_file_has "claude running: claude.json untouched" "$H/.claude.json" "\"$P/app\""
case "$out" in *"run the same command again"*) ok "claude running: says how to finish";; *) nope "claude running: says how to finish" "$out";; esac
mv_tool -y "$P/app" "$NEW" >/dev/null 2>&1
assert_file_has "claude running: rerun finishes claude.json" "$H/.claude.json" "\"$NEW\""

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
