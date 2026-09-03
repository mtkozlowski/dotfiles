#!/usr/bin/env bash
# Prints "#<PR number>" for the current branch, plus "(#<issue number>)"
# when the PR closes an issue. Exits 1 with no output when there is no PR.
#
# Caches the answer (including the "no PR" case) per repo and branch for
# CACHE_TTL_SECONDS, so repeated prompt renders don't hit the GitHub API
# each time. Used by the custom.gh_pr module in starship.toml, which calls
# this script twice per render (once to decide whether to show the module,
# once to build its text) — the cache turns the second call into a cheap
# file read.
#
# The `gh` call is capped at GH_TIMEOUT_SECONDS: a cold shell (fresh SSH
# agent, unwarmed DNS/TLS, credential helper unlock) can take longer than
# starship's own command_timeout, which the custom.gh_pr module works
# around with ignore_timeout — this cap is the backstop so a stuck or
# unreachable `gh` still returns instead of hanging the prompt.

set -uo pipefail

CACHE_TTL_SECONDS=30
GH_TIMEOUT_SECONDS=5
CACHE_DIR="${TMPDIR:-/tmp}/starship-gh-pr"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1
branch=$(git symbolic-ref --short -q HEAD 2>/dev/null) || exit 1

mkdir -p "$CACHE_DIR"
key=$(printf '%s' "$repo_root:$branch" | cksum | cut -d' ' -f1)
cache_file="$CACHE_DIR/$key"

if [[ -f "$cache_file" ]]; then
  age=$(( $(date +%s) - $(date -r "$cache_file" +%s) ))
  if (( age < CACHE_TTL_SECONDS )); then
    content=$(<"$cache_file")
    [[ "$content" == "NONE" ]] && exit 1
    printf '%s' "$content"
    exit 0
  fi
fi

result=$(timeout "$GH_TIMEOUT_SECONDS" gh pr view --json number,closingIssuesReferences -q \
  '"#\(.number)" + (if (.closingIssuesReferences | length) > 0 then " (#" + (.closingIssuesReferences[0].number | tostring) + ")" else "" end)' \
  2>/dev/null)

if [[ -z "$result" ]]; then
  printf 'NONE' >"$cache_file"
  exit 1
fi

printf '%s' "$result" >"$cache_file"
printf '%s' "$result"
