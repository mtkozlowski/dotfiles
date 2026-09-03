#!/usr/bin/env bash
# Provision the OpenVPN credentials from 1Password into a systemd-encrypted
# credential. Run as your normal user (NOT under sudo) — `op` needs your
# service-account token, which lives in your home.
#
# The plaintext exists only in a pipe between op and systemd-creds: it is never
# written to disk, never in argv (so invisible in `ps` to other users), and
# never in this shell's environment. What lands on disk is host-key-encrypted
# and decryptable only by root on this machine.
#
# Rotation: change the item in 1Password, re-run this, then `vpn restart`.
#
# The op:// references and destination path name internal infrastructure, so
# they come from ~/.config/vpn/site.conf, which lives outside this repository.
# See site.conf.example.
set -euo pipefail

: "${VPN_SITE_CONF:=${XDG_CONFIG_HOME:-$HOME/.config}/vpn/site.conf}"
[[ -r "$VPN_SITE_CONF" ]] || {
  echo "missing $VPN_SITE_CONF — copy site.conf.example and fill it in" >&2
  exit 1
}
# shellcheck source=/dev/null
set -a; . "$VPN_SITE_CONF"; set +a

OP_ITEM="${OP_ITEM:-${VPN_OP_ITEM:-}}"
OP_PASS="${OP_PASS:-${VPN_OP_PASS:-}}"
DEST="${VPN_CRED_DEST:-}"
NAME="${VPN_CRED_NAME:-}"
for v in OP_ITEM OP_PASS DEST NAME; do
  [[ -n "${!v}" ]] || { echo "$VPN_SITE_CONF: missing value for $v" >&2; exit 1; }
done

[[ $EUID -ne 0 ]] || {
  echo "run as your user, not root — op needs your token" >&2
  exit 1
}
command -v op >/dev/null || {
  echo "op not found" >&2
  exit 1
}

# Interactive shells authenticate `op` through a zsh function (see zsh/op.zsh)
# that is not visible to this script, so the token is injected here the same
# way: read from a 0600 file into op's OWN process environment per call, so it
# never enters this script's exported env and never appears in argv.
: "${OP_TOKEN_FILE:=${XDG_CONFIG_HOME:-$HOME/.config}/op/service-account-token}"
[[ -r "$OP_TOKEN_FILE" ]] || {
  echo "no op service-account token at $OP_TOKEN_FILE" >&2
  exit 1
}
op() {
  local _t
  _t="$(<"$OP_TOKEN_FILE")"
  [[ -n "${_t//[[:space:]]/}" ]] || {
    echo "op token file $OP_TOKEN_FILE is empty" >&2
    return 1
  }
  OP_SERVICE_ACCOUNT_TOKEN="$_t" command op "$@"
}

# No TPM on this host, so the credential is bound to the systemd host key
# (/var/lib/systemd/credential.secret, created on first use, 0600 root). The
# blob is therefore useless if copied off this machine.
#
# Both fields are proven readable before the encrypt pipeline runs, so a wrong
# op:// path cannot leave a half-written credential behind.
for ref in "$OP_ITEM" "$OP_PASS"; do
  op read "$ref" >/dev/null || {
    echo "cannot read $ref — check the op:// path" >&2
    exit 1
  }
done

{
  op read "$OP_ITEM"
  op read "$OP_PASS"
} |
  sudo systemd-creds encrypt --name="$NAME" --with-key=host - "$DEST"

sudo chmod 0600 "$DEST"
sudo chown root:root "$DEST"

echo "wrote $DEST"
echo "verify: sudo systemd-creds decrypt --name=$NAME $DEST - | wc -l   # expect 2"
