#!/usr/bin/env bash
# Pick a zoxide directory and open it in a NEW tmux window.
# Bound to prefix + C-y (replaces sessionx's C-y "zo-new-window").
# Lives in a script (not inline in the bind) because tmux expands $vars in
# run-shell strings at parse time, which would eat the "$dir" guard.

dir="$(
  zoxide query -l | fzf-tmux -p 60%,50% \
    --no-sort --ansi --border-label ' new window in… ' --prompt '📁  ' \
    --preview 'ls -la {}' \
    --preview-window 'right:55%'
)"

[ -n "$dir" ] && tmux new-window -c "$dir"
