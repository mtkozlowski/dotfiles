# OpenVPN client control (Linux/systemd only; no-op elsewhere).
#
# The tunnel is a systemd unit, not a shell job: it must outlive the session
# that started it, come back after reboot, and log to journald so `vpn logs`
# has history to read. Everything here is a thin wrapper over systemctl plus
# one end-to-end reachability probe, because a running unit does NOT imply the
# gated host is reachable — the pinned routes can drift out from
# under an otherwise healthy tunnel, and only an HTTP probe sees that.
#
# Unit names, the gated host and its resolver all name internal infrastructure,
# so they come from ~/.config/vpn/site.conf, outside this repository. Without
# that file `vpn` still loads and says what is missing.
# See scripts/openvpn-systemd/site.conf.example.
if command -v systemctl >/dev/null 2>&1 && [[ "$(uname -s)" == Linux ]]; then

  typeset -g VPN_SITE_CONF="${VPN_SITE_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/vpn/site.conf}"
  [[ -r "$VPN_SITE_CONF" ]] && source "$VPN_SITE_CONF"

  # Only the device has a portable default; the rest are site facts.
  typeset -g VPN_DEV="${VPN_DEV:-tun0}"

  # Fully-qualified unit names: the sudoers rule that makes these calls
  # password-free matches argv literally, so the suffix is not optional.
  _vpn_configured() {
    local missing=()
    local v
    for v in VPN_UNIT VPN_ROUTE_UNIT VPN_PROBE_HOST VPN_DNS; do
      [[ -n "${(P)v}" ]] || missing+=("$v")
    done
    [[ ${#missing} -eq 0 ]] && return 0
    print -u2 "vpn: unconfigured — ${missing[*]} unset in $VPN_SITE_CONF"
    print -u2 "     see scripts/openvpn-systemd/site.conf.example"
    return 1
  }

  vpn() {
    local cmd="${1:-status}"; shift 2>/dev/null

    # --help must work on an unconfigured machine; everything else needs the
    # site facts.
    [[ "$cmd" == (-h|--help|help) ]] || _vpn_configured || return 1

    case "$cmd" in
      on|up|start)
        sudo systemctl start "$VPN_UNIT" "$VPN_ROUTE_UNIT" || return
        vpn status
        ;;

      off|down|stop)
        # This box is shared and the tunnel is system-wide: another user's
        # tooling rides the same routes, so stopping it is not a private act.
        if [[ "$1" != -y ]]; then
          local reply
          read "reply?Stop $VPN_UNIT? Other users on this host lose the tunnel too. [y/N] "
          [[ "$reply" == [yY]* ]] || { print -u2 "aborted"; return 1; }
        fi
        sudo systemctl stop "$VPN_UNIT"
        ;;

      restart|reconnect)
        sudo systemctl restart "$VPN_UNIT" || return
        sudo systemctl start "$VPN_ROUTE_UNIT"
        vpn status
        ;;

      refresh|routes)
        # Re-pin the allowlisted host's current addresses onto the tunnel.
        sudo systemctl start "$VPN_ROUTE_UNIT" || return
        vpn status
        ;;

      enable)  sudo systemctl enable --now "$VPN_UNIT" "${VPN_ROUTE_UNIT%.service}.timer" ;;
      disable) sudo systemctl disable --now "$VPN_UNIT" "${VPN_ROUTE_UNIT%.service}.timer" ;;

      logs|log)
        local since="30 min ago" follow=()
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -f|--follow)  follow=(-f); shift ;;
            --since)      since="$2"; shift 2 ;;
            --since=*)    since="${1#--since=}"; shift ;;
            -h|--help)    print "usage: vpn logs [--since SPEC] [-f]"; return 0 ;;
            # Bare argument is a --since spec, so `vpn logs today` works.
            *)            since="$1"; shift ;;
          esac
        done
        journalctl -u "$VPN_UNIT" -u "$VPN_ROUTE_UNIT" --since "$since" --no-pager "${follow[@]}"
        ;;

      status|st)
        local active; active="$(systemctl is-active "$VPN_UNIT" 2>/dev/null)"
        print "unit    $VPN_UNIT: $active ($(systemctl is-enabled "$VPN_UNIT" 2>/dev/null))"

        local addr; addr="$(ip -br addr show "$VPN_DEV" 2>/dev/null | awk '{print $3}')"
        print "device  $VPN_DEV: ${addr:-absent}"

        # Pinned /32s vs what the tunnel's resolver answers right now. A
        # mismatch means traffic to the gated host is leaving off-tunnel.
        local want have
        want="$(dig +short "$VPN_PROBE_HOST" A "@$VPN_DNS" 2>/dev/null \
                | grep -E '^[0-9.]+$' | sort -u | paste -sd, -)"
        have="$(ip route show dev "$VPN_DEV" 2>/dev/null \
                | awk '$1 ~ /^[0-9]+\./ && $2 == "scope" {print $1}' | sort -u | paste -sd, -)"
        print "routes  pinned=${have:-none} resolved=${want:-unresolved}"
        [[ -n "$want" && "$have" != "$want" ]] && print "        ! pin drift — run: vpn refresh"

        # The only check that proves the path end to end. 403 is the
        # allowlist rejecting an off-tunnel source address.
        local code
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "https://$VPN_PROBE_HOST/" 2>/dev/null)"
        case "$code" in
          200) print "probe   $VPN_PROBE_HOST: 200 reachable via tunnel" ;;
          403) print "probe   $VPN_PROBE_HOST: 403 blocked — request left off-tunnel" ;;
          000|"") print "probe   $VPN_PROBE_HOST: unreachable (no response)" ;;
          *)   print "probe   $VPN_PROBE_HOST: HTTP $code" ;;
        esac
        ;;

      -h|--help|help)
        print "usage: vpn <on|off|restart|refresh|status|logs|enable|disable>"
        print "  off [-y]                 stop tunnel (shared host — confirms first)"
        print "  refresh                  re-pin allowlisted host routes onto $VPN_DEV"
        print "  status                   unit + device + route drift + HTTP probe"
        print "  logs [--since SPEC] [-f] default: 30 min ago; SPEC is any journalctl form"
        print "  enable | disable         start at boot (unit + route refresh timer)"
        ;;

      *) print -u2 "vpn: unknown command '$cmd' (try: vpn --help)"; return 2 ;;
    esac
  }
fi
