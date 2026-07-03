#!/usr/bin/env zsh
# Unit tests for zsh/op.zsh — run: zsh zsh/tests/op-shim.test.zsh
emulate -L zsh
setopt err_exit no_unset

fail() { print -u2 "FAIL: $1"; exit 1; }
pass() { print "ok: $1"; }

# Sandbox: a fake `op` on PATH that reveals the token it received, + temp config.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat > "$work/bin/op" <<'EOF'
#!/bin/sh
# For Case D: exit nonzero on 'read' subcommand
if [ "$1" = "read" ]; then
  exit 1
fi
printf 'STUB_SAW_TOKEN=%s\n' "$OP_SERVICE_ACCOUNT_TOKEN"
EOF
chmod +x "$work/bin/op"
PATH="$work/bin:$PATH"
rehash

SHIM="${0:h}/../op.zsh"
[[ -r "$SHIM" ]] || fail "shim not found at $SHIM"

# --- Case A: no token file → `op` must NOT be shadowed by a function ---
(
  export OP_TOKEN_FILE="$work/does-not-exist"
  unset OP_SERVICE_ACCOUNT_TOKEN 2>/dev/null || true
  source "$SHIM"
  [[ "$(whence -w op)" == "op: command" ]] \
    || fail "A: op should stay the binary when no token file (got: $(whence -w op))"
)
pass "A: no token file → bare op (unconfigured)"

# --- Case B: token file present → function injects it, stripped, not exported ---
(
  export OP_TOKEN_FILE="$work/token"
  print 'ops_TESTTOKEN' > "$OP_TOKEN_FILE"; chmod 600 "$OP_TOKEN_FILE"
  unset OP_SERVICE_ACCOUNT_TOKEN 2>/dev/null || true
  source "$SHIM"
  [[ "$(whence -w op)" == "op: function" ]] \
    || fail "B1: op should be a function when token file exists (got: $(whence -w op))"
  out="$(op whoami)"
  [[ "$out" == "STUB_SAW_TOKEN=ops_TESTTOKEN" ]] \
    || fail "B2: token not injected / newline not stripped (got: $out)"
  [[ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]] \
    || fail "B3: token leaked into the calling shell's env"
)
pass "B: token file → injected per-call, stripped, not exported"

# --- Case C: empty token file → no injection ---
(
  export OP_TOKEN_FILE="$work/token-empty"
  : > "$OP_TOKEN_FILE"; chmod 600 "$OP_TOKEN_FILE"
  unset OP_SERVICE_ACCOUNT_TOKEN 2>/dev/null || true
  source "$SHIM"
  [[ "$(whence -w op)" == "op: function" ]] \
    || fail "C1: op should be a function when token file exists (got: $(whence -w op))"
  out="$(op whoami)"
  [[ "$out" == "STUB_SAW_TOKEN=" ]] \
    || fail "C2: empty token should not be injected (got: $out)"
)
pass "C: empty token file → bare op, no injection"

# --- Case D: openv propagates op read failure ---
(
  export OP_TOKEN_FILE="$work/token"
  print 'ops_TESTTOKEN' > "$OP_TOKEN_FILE"; chmod 600 "$OP_TOKEN_FILE"
  unset OP_SERVICE_ACCOUNT_TOKEN 2>/dev/null || true
  unset MYSEC 2>/dev/null || true
  source "$SHIM"
  if openv MYSEC op://test/secret 2>/dev/null; then
    fail "D1: openv should return nonzero when op read fails"
  fi
  [[ -z "${MYSEC:-}" ]] \
    || fail "D2: MYSEC should not be exported on failure (got: ${MYSEC:-UNSET})"
)
pass "D: openv propagates op read failure"

print "ALL TESTS PASSED"
