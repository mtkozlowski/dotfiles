# wg-peer

Generate WireGuard peers and assemble one combined multi-server client config.

macOS/iOS run only one tunnel at a time, so to reach several servers at once you need
**one** client config with multiple `[Peer]` blocks — i.e. one client keypair registered
on every server. `wg-peer` splits that into three steps: `keygen` once, `add` on each
server, then `assemble` on the client.

## Commands

| Command | Where | What it does |
|---------|-------|--------------|
| `wg-peer keygen <name>` | anywhere, once | Writes `<name>.key` (0600) + `<name>.pub`; prints the pubkey to register on each server. |
| `wg-peer add <name> <peer-ip/cidr> <client-pubkey> [opts]` | each **server**, as root | Appends a labeled `[Peer]`, hot-reloads wg, and emits a `<label>.fragment` for the client. |
| `wg-peer assemble <out-name> --key <name>.key [opts] <fragment>...` | the **client** | Stitches one `[Interface]` + every fragment's `[Peer]` into `<out-name>.conf`. |

### `add` options
- `--conf PATH` — server config (default `/etc/wireguard/wg0.conf`)
- `--label NAME` — fragment label / `[Peer]` comment (default: hostname)
- `--endpoint H[:P]` — client-facing endpoint. **Recommended to set explicitly.** Default:
  source IP from the local routing table + `ListenPort`; only falls back to a third-party
  lookup (revealing the server IP) if that looks NATed. IPv6 literal: `[2001:db8::1]:51820`.
- `--route CIDR[,..]` — `AllowedIPs` the client routes here (default: the server's own
  subnet, IPv4 only). Use `0.0.0.0/0` for a full tunnel.

### `assemble` options
- `--dns IP[,IP]` — add a `DNS` line
- `--qr` — also print a QR code (needs `qrencode`)

## Setup — 3 servers (each on its own subnet)

```bash
wg-peer keygen laptop                    # once; keep laptop.key + laptop.pub
PUB=$(cat laptop.pub)

# on each server, as root:
sudo wg-peer add laptop 10.0.0.2 "$PUB" --label srv1     # server on 10.0.0.0/24
sudo wg-peer add laptop 10.1.0.2 "$PUB" --label srv2     # server on 10.1.0.0/24
sudo wg-peer add laptop 10.2.0.2 "$PUB" --label srv3     # server on 10.2.0.0/24

# securely copy srv{1,2,3}.fragment to the laptop, then:
wg-peer assemble vpn --key laptop.key srv1.fragment srv2.fragment srv3.fragment
rm srv*.fragment                          # they hold preshared keys
```

## Extending later — add a 4th server (existing servers untouched)

```bash
sudo wg-peer add laptop 10.3.0.2 "$(cat laptop.pub)" --label srv4   # new box only
wg-peer assemble vpn-v2 --key laptop.key srv1.fragment srv2.fragment srv3.fragment srv4.fragment
```

Three things to remember when extending:
- Keep `laptop.key` / `laptop.pub` — needed for every future `add` and `assemble`.
- Give each new server a **distinct subnet** — the script enforces this.
- `assemble` won't overwrite — use a new out-name (or delete the old `.conf`).

## Security notes
- **Distinct subnets required.** No two servers may advertise the same `AllowedIPs` prefix;
  WireGuard maps each prefix to exactly one peer. `assemble` rejects duplicates and warns on
  overlaps and on a full tunnel with no `--dns` (DNS-leak risk).
- **Fragments carry a preshared key in cleartext.** Move them server→client over a secure
  channel (scp/age) and delete them once `assemble` has run. `<name>.key` is likewise secret.
- Only **one** peer can carry `0.0.0.0/0` (a second full tunnel is a duplicate → rejected).

## Limitations
- Automatic subnet routing and endpoint autodetection are **IPv4-only**; pass `--route` and
  `--endpoint` explicitly for IPv6.
- Overlap detection catches exact duplicates (fatal) and warns on partial overlaps; it does
  not resolve them for you.
- `add` requires the target interface to already be up (`wg-quick up <iface>`).
