# Every machine authenticates `op` the same way: a 1Password service-account
# token in a 0600 file, injected into op's OWN process env per-invocation —
# never exported to the shell, never in argv (so it stays invisible to other
# users in `ps`). If no token file is present, `op` is left as the bare binary
# (unconfigured). No-ops on machines without `op`.
if command -v op >/dev/null 2>&1; then
  # Resolved token path (a non-secret string). OP_TOKEN_FILE lets tests/hosts
  # override it; otherwise default to the XDG location.
  typeset -g OP_TOKEN_FILE="${OP_TOKEN_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/op/service-account-token}"

  if [[ -r "$OP_TOKEN_FILE" ]]; then
    # $(<file) strips the trailing newline; the value lands only in `command
    # op`'s environment, never in this shell's exported env. If the token is
    # empty or whitespace-only, fall through to the bare (unconfigured) op.
    op() {
      local _t="$(<"$OP_TOKEN_FILE")"
      if [[ -n "${_t//[[:space:]]/}" ]]; then
        OP_SERVICE_ACCOUNT_TOKEN="$_t" command op "$@"
      else
        command op "$@"
      fi
    }
  fi

  # openv VAR op://vault/item/field — fetch ONE secret on demand into this shell
  # (use sparingly, for tools that read an ambient $VAR and can't go via op run).
  openv() {
    [[ $# -eq 2 ]] || { print -u2 "usage: openv VAR op://vault/item/field"; return 2; }
    local _v; _v="$(op read "$2")" || return
    export "$1"="$_v"
  }
fi
