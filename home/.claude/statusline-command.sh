#!/usr/bin/env bash
# Claude Code status line script
# [Model (effort)] repo  branch* ⇡wt | XX% ctx | 5h: YY% · Xh Ym | wk: ZZ%
#
# The line is fitted to the width of the pane. What gives way first is the
# worktree, then the branch, then the effort note, then the repo name. The usage
# numbers go last. The directory shown is the repo, not the checkout folder, so
# a worktree named after its branch does not print the branch twice.

input=$(cat)

# One jq pass instead of one per field.
eval "$(printf '%s' "$input" | jq -r '
  @sh "model=\(.model.display_name)",
  @sh "effort=\(.effort.level // "")",
  @sh "fast=\(.fast_mode // false)",
  @sh "agent=\(.agent.name // "")",
  @sh "dir=\(.workspace.current_dir // .cwd // "")",
  @sh "wt=\(.workspace.git_worktree // "")",
  @sh "ctx_used=\(.context_window.used_percentage // "")",
  @sh "five_pct=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "five_at=\(.rate_limits.five_hour.resets_at // "")",
  @sh "week_pct=\(.rate_limits.seven_day.used_percentage // "")"
')"

# Shorten $1 to at most $2 characters, keeping the start and the end of it, and
# put the result in SHORT. A ticket branch keeps both its id and its last word:
# feature-esp-218-migrate-the…-azure
# The answer goes into a variable because this script runs on every render and a
# command substitution here would cost a fork each time.
shorten() {
  local s=$1 max=$2 tail=0
  SHORT=""
  [ "${#s}" -le "$max" ] && { SHORT=$s; return; }
  # A stub of a few characters says less than the space it costs.
  [ "$max" -lt 6 ] && return
  [ "$max" -ge 16 ] && tail=6
  SHORT="${s:0:$((max - 1 - tail))}…${s:$((${#s} - tail))}"
}

# Model label: name, effort, fast mode, active agent.
# The name drops any parenthetical suffix, so "Opus 5 (1M context)" reads
# "Opus 5". note holds the parts that go first when space runs out.
model=${model%% (*}
model_note=""
[ -n "$effort" ] && model_note="${model_note} (${effort})"
[ "$fast" = "true" ] && model_note="${model_note} ⚡"
[ -n "$agent" ] && model_note="${model_note} · ${agent}"

# Repo name, branch, dirty marker, worktree.
# The repo name comes from the common git dir, so every worktree of a project
# shows the project name rather than the name of its own folder.
branch=""
dirty=""
dir_name=""
if [ -n "$dir" ]; then
  dir_name=$(basename "$dir")
  # One call for both: line 1 is the branch, line 2 the common git dir.
  IFS=$'\n' read -r -d '' branch common_dir < <(
    git -C "$dir" rev-parse --abbrev-ref HEAD --path-format=absolute --git-common-dir 2>/dev/null
    printf '\0'
  )
  if [ -n "$common_dir" ]; then
    common_dir=${common_dir%/}
    leaf=$(basename "$common_dir")
    case $leaf in
      # .git, .bare and the like name the store, the parent names the project.
      .*) dir_name=$(basename "$(dirname "$common_dir")") ;;
      *.git) dir_name=$(basename "$leaf" .git) ;;
      *) dir_name=$leaf ;;
    esac
  fi
  # git status is slow in big repos and this script runs on every render, so the
  # dirty check is cached per directory for 5 seconds.
  if [ -n "$branch" ]; then
    cache="${TMPDIR:-/tmp}/cc-statusline-$(printf '%s' "$dir" | cksum | cut -d' ' -f1)"
    now=$(date +%s)
    stamp=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0)
    if [ $((now - stamp)) -ge 5 ]; then
      if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
        printf '*' >"$cache"
      else
        : >"$cache"
      fi
    fi
    dirty=$(cat "$cache" 2>/dev/null)
  fi
fi

# A worktree named after its branch says nothing the branch has not said.
# Folder names carry dashes where a branch carries slashes, so compare loosely.
# nocasematch keeps this to shell builtins, which bash 3.2 on macOS also has.
shopt -s nocasematch
wt_name=""
[ -n "$wt" ] && wt_name=$(basename "$wt")
if [ -n "$wt_name" ] && [[ ${wt_name//[\/_]/-} == "${branch//[\/_]/-}" ]]; then
  wt_name=""
fi
shopt -u nocasematch

# Context window.
if [ -n "$ctx_used" ]; then
  ctx_part="$(printf '%.0f' "$ctx_used")% ctx"
else
  ctx_part="ctx: -"
fi

# Time until a rate limit window resets.
reset_in() {
  local secs=$(($1 - $(date +%s)))
  if [ "$secs" -le 0 ]; then
    printf 'resetting'
  elif [ "$secs" -ge 3600 ]; then
    printf '%dh %dm' $((secs / 3600)) $(((secs % 3600) / 60))
  else
    printf '%dm' $((secs / 60))
  fi
}

# Usage side, from the fullest form down to the barest one.
usage_parts() {
  local sep=$1 p=("$2")
  [ -n "$3" ] && p+=("$3")
  [ -n "$4" ] && p+=("$4")
  local out
  out=$(printf "%s${sep}" "${p[@]}")
  printf '%s' "${out%$sep}"
}

five_full=""
five_short=""
if [ -n "$five_pct" ] && [ -n "$five_at" ]; then
  five_full="5h: $(printf '%.0f' "$five_pct")% · $(reset_in "$five_at")"
  five_short="5h $(printf '%.0f' "$five_pct")%"
fi
week_full=""
week_short=""
if [ -n "$week_pct" ]; then
  week_full="wk: $(printf '%.0f' "$week_pct")%"
  week_short="wk $(printf '%.0f' "$week_pct")%"
fi
ctx_short=${ctx_part% ctx}

usage_full=$(usage_parts " | " "$ctx_part" "$five_full" "$week_full")
usage_mid=$(usage_parts " | " "$ctx_short" "$five_short" "$week_short")
usage_min=$(usage_parts " | " "$ctx_short" "$five_short" "")

# Build the left side from the budget each field is given, into HEAD.
# $1 keep the effort note, $2 repo chars, $3 branch chars, $4 worktree chars.
build_head() {
  local h
  if [ "$1" = "1" ]; then h="[${model}${model_note}]"; else h="[${model}]"; fi
  shorten "$dir_name" "$2"
  [ -n "$SHORT" ] && h="${h} ${SHORT}"
  shorten "$branch" "$3"
  [ -n "$SHORT" ] && h="${h}  ${SHORT}${dirty}"
  shorten "$wt_name" "$4"
  [ -n "$SHORT" ] && h="${h} ⇡${SHORT}"
  HEAD=$h
}

# Claude Code exports COLUMNS as the width of the pane it renders in.
width=${COLUMNS:-200}

# Widest first, then give up space until the whole line fits.
# Fields are: usage form, effort note, repo, branch, worktree.
# The usage numbers are the last thing to give ground.
for step in \
  "full 1 40 60 40" \
  "full 1 24 32 20" \
  "full 1 16 24 12" \
  "full 1 12 16 0" \
  "full 0 10 14 0" \
  "full 0 8 10 0" \
  "mid  0 8 10 0" \
  "mid  0 0 8 0" \
  "min  0 0 8 0" \
  "min  0 0 0 0"; do
  read -r form keep_note dir_max branch_max wt_max <<<"$step"
  case $form in
    full) usage=$usage_full ;;
    mid) usage=$usage_mid ;;
    *) usage=$usage_min ;;
  esac
  build_head "$keep_note" "$dir_max" "$branch_max" "$wt_max"
  # Two spare columns: some glyphs here take two cells but count as one char.
  [ $((${#HEAD} + ${#usage} + 3)) -le $((width - 2)) ] && break
done

# Any slack left over goes back to the branch name. Adding a branch that the
# step dropped also costs its separator, so keep the wider head only if it fits.
head=$HEAD
slack=$((width - 2 - ${#head} - ${#usage} - 3))
if [ "$slack" -gt 0 ] && [ "${#branch}" -gt "$branch_max" ]; then
  for extra in "$slack" $((slack - 3)); do
    [ "$extra" -lt 1 ] && continue
    build_head "$keep_note" "$dir_max" $((branch_max + extra)) "$wt_max"
    if [ $((${#HEAD} + ${#usage} + 3)) -le $((width - 2)) ]; then
      head=$HEAD
      break
    fi
  done
fi

line="${head} | ${usage}"
# Last resort: the terminal is narrower than the usage numbers themselves.
if [ "${#line}" -gt "$width" ]; then
  line="${line:0:$((width - 1))}…"
fi
printf '%s' "$line"
