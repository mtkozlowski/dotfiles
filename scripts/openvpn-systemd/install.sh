#!/usr/bin/env bash
# Install the OpenVPN units, route pinner, and sudoers policy by
# rendering the *.in templates against ~/.config/vpn/site.conf.
#
# Run as your normal user; sudo is invoked per step. Every internal hostname,
# address, unit name and username comes from site.conf, which lives outside this
# repository — see site.conf.example.
#
# Idempotent: re-running re-renders and re-installs the same files.
#
# PREREQUISITE, not handled here: ./vpn-creds-provision.sh must have written the
# encrypted credential, and the openvpn config's auth-user-pass must point at
# it. Both are checked below, and the exact fix is printed if they are missing.
set -euo pipefail
cd "$(dirname "$0")"

[[ $EUID -ne 0 ]] || {
  echo "run as your user, not root — sudo is invoked per step" >&2
  exit 1
}

: "${VPN_SITE_CONF:=${XDG_CONFIG_HOME:-$HOME/.config}/vpn/site.conf}"
[[ -r "$VPN_SITE_CONF" ]] || {
  echo "missing $VPN_SITE_CONF — copy site.conf.example and fill it in" >&2
  exit 1
}
# shellcheck source=/dev/null
set -a; . "$VPN_SITE_CONF"; set +a

for v in VPN_UNIT VPN_ROUTE_UNIT VPN_DEV VPN_PROBE_HOST VPN_DNS \
         VPN_CRED_NAME VPN_CRED_DEST VPN_OVPN_CONF VPN_SUDO_USER; do
  [[ -n "${!v:-}" ]] || { echo "$VPN_SITE_CONF: $v is unset" >&2; exit 1; }
done
VPN_ROUTE_TIMER="${VPN_ROUTE_UNIT%.service}.timer"
CRED_PATH="/run/credentials/${VPN_UNIT}/${VPN_CRED_NAME}"

sudo grep -qE "^auth-user-pass[[:space:]]+${CRED_PATH}\$" "$VPN_OVPN_CONF" || {
  echo "$VPN_OVPN_CONF does not point at the systemd credential yet. Run:" >&2
  echo "  sudo sed -i 's#^auth-user-pass\$#auth-user-pass ${CRED_PATH}#' $VPN_OVPN_CONF" >&2
  exit 1
}

sudo test -f "$VPN_CRED_DEST" || {
  echo "missing $VPN_CRED_DEST — run ./vpn-creds-provision.sh first" >&2
  exit 1
}

render() {
  sed -e "s#@HOST@#${VPN_PROBE_HOST}#g" \
      -e "s#@DNS@#${VPN_DNS}#g" \
      -e "s#@DEV@#${VPN_DEV}#g" \
      -e "s#@VPN_UNIT@#${VPN_UNIT}#g" \
      -e "s#@VPN_ROUTE_UNIT@#${VPN_ROUTE_UNIT}#g" \
      -e "s#@VPN_ROUTE_TIMER@#${VPN_ROUTE_TIMER}#g" \
      -e "s#@VPN_CRED_NAME@#${VPN_CRED_NAME}#g" \
      -e "s#@VPN_CRED_DEST@#${VPN_CRED_DEST}#g" \
      -e "s#@VPN_SUDO_USER@#${VPN_SUDO_USER}#g" \
      "$1"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for f in route-pin.sh.in routes.service.in routes.timer.in \
         client-override.conf.in nopasswd.sudoers.in; do
  render "$f" >"$tmp/${f%.in}"
done

# A surviving placeholder means a template grew a token this script does not
# substitute; installing it would produce a broken unit or sudoers file.
if grep -rnE '@[A-Z_]+@' "$tmp"; then
  echo "unrendered placeholders remain (see above)" >&2
  exit 1
fi

sudo install -m 0755 -o root -g root "$tmp/route-pin.sh" /etc/openvpn/route-pin.sh
sudo install -m 0644 -o root -g root "$tmp/routes.service" "/etc/systemd/system/${VPN_ROUTE_UNIT}"
sudo install -m 0644 -o root -g root "$tmp/routes.timer"   "/etc/systemd/system/${VPN_ROUTE_TIMER}"

sudo install -d -m 0755 "/etc/systemd/system/${VPN_UNIT}.d"
sudo install -m 0644 -o root -g root "$tmp/client-override.conf" \
  "/etc/systemd/system/${VPN_UNIT}.d/override.conf"

# visudo -c validates the policy before it can lock anyone out of sudo.
sudo install -m 0440 -o root -g root "$tmp/nopasswd.sudoers" /etc/sudoers.d/vpn-openvpn
sudo visudo -c -f /etc/sudoers.d/vpn-openvpn

sudo systemctl daemon-reload

# An openvpn started by hand (e.g. in a tmux pane) owns the tunnel device; two
# instances would fight over it. This drops the tunnel for every user on the
# host for a few seconds.
sudo pkill -TERM -f "openvpn --config ${VPN_OVPN_CONF}" || true
sleep 2

sudo systemctl enable --now "$VPN_UNIT" "$VPN_ROUTE_TIMER"
sudo systemctl start "$VPN_ROUTE_UNIT"

systemctl --no-pager --lines=0 status "$VPN_UNIT" "$VPN_ROUTE_TIMER" || true
