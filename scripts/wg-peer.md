# wg-peer

Generate WireGuard peers and assemble one combined multi-server client config.

macOS/iOS run only one tunnel at a time, so to reach several servers at once you need
**one** client config with multiple `[Peer]` blocks — i.e. one client keypair registered
on every server under **one shared tunnel IP**. `wg-peer` splits that into three steps:
`keygen` once, `add` on each server (same client IP every time), then `assemble` on the client.

> **Why one shared IP (not one per server)?** macOS/iOS always source packets from the
> interface's *primary* address. If the client had a different IP per server, every server
> but one would see a "wrong" source address and silently drop the traffic at its `AllowedIPs`
> check — handshake succeeds, no data flows. See [`wg-peer-networking.md`](./wg-peer-networking.md)
> for the mechanism, confirmed against WireGuard's primary docs.

## Commands

| Command | Where | What it does |
|---------|-------|--------------|
| `wg-peer keygen <name>` | anywhere, once | Writes `<name>.key` (0600) + `<name>.pub`; prints the pubkey to register on each server. |
| `wg-peer add <name> <client-ip> <client-pubkey> [opts]` | each **server**, as root | Registers the client under the **same** `<client-ip>` (`AllowedIPs = <client-ip>/32`), hot-reloads wg, adds a host route if that IP is outside this server's subnet, and emits a `<label>.fragment`. |
| `wg-peer assemble <out-name> --key <name>.key [opts] <fragment>...` | the **client** | Stitches one `[Interface]` (single shared `Address`) + every fragment's `[Peer]` into `<out-name>.conf`. |

### `add` options
- `--conf PATH` — server config (default `/etc/wireguard/wg0.conf`)
- `--label NAME` — fragment label / `[Peer]` comment (default: hostname)
- `--endpoint H[:P]` — client-facing endpoint. **Recommended to set explicitly.** Default:
  source IP from the local routing table + `ListenPort`; only falls back to a third-party
  lookup (revealing the server IP) if that looks NATed. IPv6 literal: `[2001:db8::1]:51820`.
- `--route CIDR[,..]` — `AllowedIPs` the client routes here (default: the server's own
  subnet, IPv4 only). Use `0.0.0.0/0` for a full tunnel.

> Use the **same** `<client-ip>` in every `add`. On servers whose own subnet does not contain
> that IP, `add` adds a host route (`ip route replace <client-ip> dev wg0`) so replies use the
> tunnel; it becomes permanent on the next `wg-quick up` (routes derive from `AllowedIPs`).

### `assemble` options
- `--dns IP[,IP]` — add a `DNS` line
- `--qr` — also print a QR code (needs `qrencode`)

## Setup — 3 servers, one client

Pick **one** client IP and reuse it on every server. Each server keeps its **own distinct
subnet** (that's what it advertises back to the client as a route).

```bash
wg-peer keygen laptop                    # once; keep laptop.key + laptop.pub
PUB=$(cat laptop.pub)
IP=10.0.0.2                             # ONE client IP, used on every server

# on each server, as root (same IP everywhere; distinct server subnets):
sudo wg-peer add laptop "$IP" "$PUB" --label srv1 --endpoint A.A.A.A:51820   # srv1 on 10.0.0.0/24
sudo wg-peer add laptop "$IP" "$PUB" --label srv2 --endpoint B.B.B.B:51820   # srv2 on 10.1.0.0/24
sudo wg-peer add laptop "$IP" "$PUB" --label srv3 --endpoint C.C.C.C:51820   # srv3 on 10.2.0.0/24
#   srv1 contains 10.0.0.2 in its subnet → no extra route
#   srv2/srv3 do NOT → add auto-installs a host route to 10.0.0.2

# securely copy srv{1,2,3}.fragment to the laptop, then:
wg-peer assemble vpn --key laptop.key srv1.fragment srv2.fragment srv3.fragment
rm srv*.fragment                          # they hold preshared keys
```

The assembled `vpn.conf` has a single `Address = 10.0.0.2/32` and one `[Peer]` per server.
Import it (WireGuard app, or `wg-quick up`), and all three servers are reachable at once.

## Extending later — add a 4th server (existing servers untouched)

```bash
sudo wg-peer add laptop 10.0.0.2 "$(cat laptop.pub)" --label srv4 --endpoint D.D.D.D:51820  # same IP, new box
wg-peer assemble vpn-v2 --key laptop.key srv1.fragment srv2.fragment srv3.fragment srv4.fragment
```

When extending:
- Keep `laptop.key` / `laptop.pub` — needed for every future `add` and `assemble`.
- Reuse the **same client IP**; give each new server a **distinct subnet/route** (enforced).
- `assemble` won't overwrite — use a new out-name (or delete the old `.conf`).

## Security notes
- **One client IP, distinct server routes.** No two servers may advertise the same `AllowedIPs`
  route prefix (WireGuard maps each prefix to one peer); `assemble` rejects duplicate routes and
  warns on overlaps and on a full tunnel with no `--dns` (DNS-leak risk).
- **Server firewall/ACL rules keyed to the WG subnet will miss.** Replies now come from the
  shared client IP, which may sit outside a server's own subnet. Scope rules by the WG
  **interface** (`ufw allow in on wg0`), not by subnet.
- **Fragments carry a preshared key in cleartext.** Move them server→client over a secure
  channel (scp/age) and delete them once `assemble` has run. `<name>.key` is likewise secret.
- Only **one** peer can carry `0.0.0.0/0` (a second full tunnel is a duplicate → rejected).

## Limitations
- Automatic subnet routing, host-route insertion and endpoint autodetection are **IPv4-only**;
  pass `--route` and `--endpoint` explicitly for IPv6.
- Overlap detection catches exact duplicates (fatal) and warns on partial overlaps; it does
  not resolve them for you.
- `add` requires the target interface to already be up (`wg-quick up <iface>`). The auto host
  route uses `ip(8)` (Linux); on a non-`ip` host `add` prints the route to add manually.
- If you feed `assemble` an older config with a **different IP per server**, it keeps them but
  warns — that layout is the macOS/iOS trap above.
