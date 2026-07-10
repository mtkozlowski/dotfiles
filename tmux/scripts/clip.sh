#!/usr/bin/env bash
# Copy stdin to the tmux paste buffer AND to the system clipboard of *every*
# attached client via OSC 52 (set-clipboard on forwards it to the terminal).
#
# Why broadcast instead of a plain `tmux load-buffer -w -`?
# `-w` sends the clipboard escape to a single target-client, defaulting to the
# current one. Inside a floax popup the current client is the popup's own
# `tmux attach -t scratch`, whose terminal is the popup surface (tmux-256color,
# no clipboard capability) — the escape dies there and never reaches Ghostty.
# The real client (Ghostty over SSH) is also attached, so addressing every
# client with `-t` makes the server emit OSC 52 straight to the real client's
# tty, bypassing the popup entirely. In a normal pane there is only one client,
# so this behaves exactly like the old `load-buffer -w -`.
set -euo pipefail

data="$(cat)"

# Keep the yank in a fixed buffer so it's pasteable and buffers don't pile up.
printf '%s' "$data" | tmux load-buffer -b clip -

# Push it to the clipboard of each attached client's terminal.
tmux list-clients -F '#{client_name}' | while IFS= read -r client; do
  printf '%s' "$data" | tmux load-buffer -w -b clip -t "$client" - 2>/dev/null || true
done
