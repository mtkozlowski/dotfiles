#!/usr/bin/env bash
# Telegram notifications for one Claude Code session.
#
# Two roles in one file:
#   toggle | on | off | status   flips the switch for the current session.
#                                The /afk slash command calls this.
#   hook                         runs from the Notification, Stop and SessionEnd
#                                hooks, reads the hook payload on stdin and sends
#                                one message when that session's switch is on.
#
# The switch is per session, so turning it on in the session you walk away from
# leaves every other session quiet. State lives in
# $XDG_STATE_HOME/claude-telegram/<session-id> and is dropped when the session ends.
#
# Setup on a machine:
#   1. Create a bot with @BotFather, then send it any message and read your chat id
#      from https://api.telegram.org/bot<TOKEN>/getUpdates
#   2. cp ~/dotfiles/home/.claude/telegram.env.local.example ~/.claude/telegram.env.local
#      chmod 600 ~/.claude/telegram.env.local, then fill in the two values.
#   3. Register the hooks in ~/.claude/settings.json (machine local, not tracked):
#        "Notification": [{ "matcher": "*", "hooks": [
#          { "type": "command", "command": "bash '$HOME/.claude/hooks/telegram-notify.sh' hook", "timeout": 15 }]}],
#        "Stop":        [ same one entry ],
#        "SessionEnd":  [ same one entry ]
#
# Nothing is sent unless the switch is on, so the hooks cost one file test per turn.

set -uo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-telegram"
config_file="${CLAUDE_TELEGRAM_ENV:-$HOME/.claude/telegram.env.local}"
max_chars=600

die() { printf '%s\n' "$*" >&2; exit 1; }

# A value may be a literal or a 1Password reference, so real secrets never have to
# sit in a file. See the Secrets section of zsh/.zshrc.local.example.
resolve() {
  case "$1" in
    op://*) command -v op >/dev/null 2>&1 && op read --no-newline "$1" 2>/dev/null ;;
    *) printf '%s' "$1" ;;
  esac
}

load_creds() {
  if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    # shellcheck disable=SC1090
    [ -r "$config_file" ] && . "$config_file"
  fi
  token=$(resolve "${TELEGRAM_BOT_TOKEN:-}")
  chat=$(resolve "${TELEGRAM_CHAT_ID:-}")
  [ -n "$token" ] && [ -n "$chat" ]
}

# The text goes through a file so no quoting of message content is needed, and the
# bot token goes through a curl config file so it stays out of the process list.
send() {
  local body tmp rc
  body=$1
  tmp=$(mktemp "${TMPDIR:-/tmp}/claude-telegram.XXXXXX") || return 1
  printf '%s' "$body" >"$tmp"
  curl -sS --max-time 10 -o /dev/null -K - <<EOF
url = "https://api.telegram.org/bot${token}/sendMessage"
data-urlencode = "chat_id=${chat}"
data-urlencode = "text@${tmp}"
EOF
  rc=$?
  rm -f "$tmp"
  return $rc
}

# Last block of assistant prose in the transcript, so the message says what the
# agent actually replied. Only the tail of the file is read.
last_reply() {
  local path=$1
  [ -r "$path" ] || return 0
  tail -n 400 "$path" 2>/dev/null | jq -rs '
    [ .[]
      | select(.type == "assistant")
      | [ (.message.content? // [])[]? | select(.type == "text") | .text ]
      | join("\n\n")
    ] | map(select(. != "")) | last // ""' 2>/dev/null
}

case "${1:-toggle}" in
  hook)
    payload=$(cat)
    command -v jq >/dev/null 2>&1 || exit 0
    command -v curl >/dev/null 2>&1 || exit 0

    field() { printf '%s' "$payload" | jq -r "$1 // \"\"" 2>/dev/null; }
    [ -z "$(field .agent_id)" ] || exit 0   # subagent turns are not worth a phone buzz

    session=$(field .session_id)
    [ -n "$session" ] || exit 0
    state_file="$state_dir/$session"
    [ -f "$state_file" ] || exit 0

    event=$(field .hook_event_name)
    cwd=$(field .cwd)
    where=$(basename "${cwd:-$PWD}")

    case "$event" in
      Notification) text="Claude needs you in $where"$'\n\n'"$(field .message)" ;;
      Stop)         text="Claude finished a turn in $where"$'\n\n'"$(last_reply "$(field .transcript_path)")" ;;
      SessionEnd)   text="Claude session in $where ended ($(field .reason))" ;;
      *)            exit 0 ;;
    esac

    [ ${#text} -le $max_chars ] || text="${text:0:$max_chars}…"
    load_creds || exit 0
    send "$text" >/dev/null 2>&1
    [ "$event" = "SessionEnd" ] && rm -f "$state_file"
    exit 0
    ;;

  on|off|toggle|status)
    action=$1
    session="${CLAUDE_CODE_SESSION_ID:-}"
    [ -n "$session" ] || die "no CLAUDE_CODE_SESSION_ID in the environment, so there is no session to switch"
    state_file="$state_dir/$session"

    if [ "$action" = toggle ]; then
      [ -f "$state_file" ] && action=off || action=on
    fi

    case "$action" in
      status)
        [ -f "$state_file" ] && printf 'Telegram notifications are on for this session.\n' \
                             || printf 'Telegram notifications are off for this session.\n'
        ;;
      on)
        load_creds || die "no Telegram credentials: set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID, or fill in $config_file"
        send "Telegram notifications are on for the Claude session in $(basename "$PWD")." \
          || die "Telegram rejected the test message, so notifications stay off. Check the token and chat id in $config_file"
        mkdir -p "$state_dir" && touch "$state_file"
        # Drop switches left behind by sessions that were killed.
        find "$state_dir" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null
        printf 'Telegram notifications are on for this session. A test message was sent.\n'
        ;;
      off)
        rm -f "$state_file"
        printf 'Telegram notifications are off for this session.\n'
        ;;
    esac
    ;;

  *)
    die "usage: telegram-notify.sh [toggle|on|off|status|hook]"
    ;;
esac
