# WireGuard — a re-orientation note

For the times you come back to WireGuard after months and think *"what the hell was that?"*.
Read the mental model, then jump to whatever line in a config is confusing you.

---

## 1. The mental model (read this first)

WireGuard builds **encrypted tunnels between machines**. That's it. It shows up on your
system as a **network interface** (like `wg0` on Linux, `utun4` on macOS) that you send
packets into; they come out the other end, decrypted, on another machine.

Three ideas explain almost everything:

1. **Every machine has a key pair.** A machine is identified by its **public key**, not by
   its IP or hostname. If you know a machine's public key, you can talk to it; the IP can
   even change and the tunnel survives.
2. **A tunnel is just a list of peers.** Your config has one `[Interface]` (this machine)
   and one or more `[Peer]` blocks (the machines you talk to). There is no "client" or
   "server" in the protocol — those are just roles *you* assign by how you configure them.
3. **"Cryptokey routing" ties an IP range to a public key.** For each peer you declare which
   IP addresses "live behind" it (`AllowedIPs`). WireGuard uses that list twice:
   - **Sending:** *which peer do I encrypt this packet to?* → the peer whose `AllowedIPs`
     contains the **destination** IP.
   - **Receiving:** *should I accept this decrypted packet?* → only if its **source** IP is
     inside that same peer's `AllowedIPs`. Otherwise it's **silently dropped**.

That dual role of `AllowedIPs` is the single most misunderstood thing in WireGuard. Keep it
in mind and 90% of "handshake works but traffic doesn't" mysteries explain themselves.

Other properties worth knowing: it runs over **UDP** (single port), it's **connectionless**
(no dial/hangup — a peer is reachable whenever packets can flow), and it's **quiet** — if you
send nothing, nothing goes on the wire (relevant to keepalives, below).

---

## 2. Anatomy of a config file

A WireGuard config (e.g. `/etc/wireguard/wg0.conf`) has exactly one `[Interface]` and any
number of `[Peer]` sections:

```ini
[Interface]
# "Me" — this machine's identity and how it behaves locally.
PrivateKey = <this machine's private key>
Address    = 10.0.0.2/24
ListenPort = 51820
DNS        = 1.1.1.1

[Peer]
# "The other end" — one block per machine I talk to.
PublicKey    = <the other machine's public key>
PresharedKey = <optional shared secret>
Endpoint     = 203.0.113.5:51820
AllowedIPs   = 10.0.0.0/24
PersistentKeepalive = 25
```

### `[Interface]` = **me**
Everything about *this* machine: its private key, the address(es) it owns on the tunnel, the
UDP port it listens on, DNS to use while connected. There is only ever **one** `[Interface]`.

### `[Peer]` = **the other end**
One block per remote machine. It holds *that* peer's public key, where to reach it
(`Endpoint`), and which IPs route to it (`AllowedIPs`). A "server" config has many `[Peer]`
blocks (one per client); a "client" config typically has one `[Peer]` per server it uses.

The asymmetry to remember: **your `[Interface] PrivateKey` corresponds to the `[Peer] PublicKey`
that the *other* machine lists for you.** Keys always cross over.

---

## 3. Keys — private, public, preshared

- **Private key** — secret, lives only in `[Interface] PrivateKey` on its own machine. Never
  leaves it. Generated with `wg genkey`.
- **Public key** — derived from the private key (`wg pubkey`). Safe to share. This is what the
  *other* side puts in its `[Peer] PublicKey` to identify you. It's the machine's real "name".
- **Preshared key (`PresharedKey`)** — *optional* extra symmetric secret, mixed into the
  encryption on top of the key pair. Both peers must have the **same** value in their matching
  blocks. It's an added layer that hardens the tunnel against a future attacker who records
  traffic today and hopes to break it with a quantum computer later (**post-quantum
  hardening**). It is **not** a replacement for the key pair and not required — omit it and
  WireGuard is still secure today. Generate with `wg genpsk`.

```bash
wg genkey | tee private.key | wg pubkey > public.key   # make a key pair
wg genpsk > preshared.key                              # make a preshared key
```

Rule of thumb: a **key pair per machine**, a **preshared key per peer-relationship** (a unique
one for each Interface↔Peer link).

---

## 4. Addresses — why some look "complete" and some have zeros

This is where the confusion usually lives. There are two different things that both look like
IP addresses but mean different things.

### 4a. A host address vs. a network (range)

An IPv4 address is 4 numbers (octets), 0–255 each: `10.20.0.1`. Conceptually it splits into a
**network part** (which subnet) and a **host part** (which machine in it). The `/N` suffix says
how many bits (from the left) are the network part.

- `10.20.0.1` — a **specific machine** (a host). Often `.1` is the server/gateway of its subnet,
  by convention (nothing enforces it; it's just a habit).
- `10.20.0.0/24` — a **whole subnet**, "all of `10.20.0.*`". The **zeros are the host part
  blanked out** — you're naming the *network*, not a machine. `10.20.0.0` with `/24` means
  "the first 24 bits (`10.20.0`) are the network; the last 8 bits (the final octet) are free
  for hosts `.0`–`.255`".
- `0.0.0.0/0` — **every possible address** ("the whole internet / default route"). All bits are
  host bits, none are network bits, so every address matches.

So an address "with zeros at the end" is almost always a **network/range**, and the zeros are
just the host bits set to nothing. `10.20.0.0/24` is the *name of the street*; `10.20.0.7` is
*a house on it*.

### 4b. Why some are bare (`10.20.0.1`) and some have a `/N`

The `/N` is **CIDR notation** — it turns a single address into a range by declaring the network
size. `N` is the number of leading bits that are fixed.

| Notation | Means | How many addresses |
|---|---|---|
| `10.20.0.1` (bare) | a single host — implicitly `/32` in most WireGuard contexts | 1 |
| `10.20.0.1/32` | exactly this one host | 1 |
| `10.20.0.0/24` | the `10.20.0.*` subnet | 256 |
| `10.20.0.0/16` | the `10.20.*.*` range | 65,536 |
| `10.0.0.0/8` | all of `10.*.*.*` | ~16.7M |
| `0.0.0.0/0` | everything (default route) | all IPv4 |

**Yes, there are other options:** any `/N` from `/0` to `/32` for IPv4 (and `/0`–`/128` for
IPv6, e.g. `fd00::/8`, `::/0`). `/24` and `/32` are just the two you see most: `/24` = "a small
subnet", `/32` = "one exact machine".

Quick reading trick: **bigger `/N` = smaller, more specific range.** `/32` is one machine; `/0`
is the entire internet.

### 4c. Where each form shows up in WireGuard

- **`[Interface] Address`** — usually a host with the subnet mask of the tunnel network, e.g.
  `Address = 10.20.0.2/24`. The `/24` tells your OS "I'm one machine on the `10.20.0.0/24`
  network," which affects local routing and source-address choice.
- **`[Peer] AllowedIPs`** — a **list of ranges** that live behind that peer:
  - `AllowedIPs = 10.20.0.5/32` — just that one machine routes to this peer (typical for a
    single client on a server).
  - `AllowedIPs = 10.20.0.0/24` — the peer's whole subnet routes to it (typical client→server:
    "send anything for `10.20.0.*` down this tunnel").
  - `AllowedIPs = 0.0.0.0/0, ::/0` — **full tunnel**: route *all* traffic through this peer
    (VPN-your-whole-connection mode).

Private ranges you'll see used for tunnels (RFC 1918 — never routed on the public internet):
`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. Pick something here for your tunnel subnet.

---

## 5. The common `[Interface]` / `[Peer]` options

### `[Interface]`
| Option | What it does |
|---|---|
| `PrivateKey` | This machine's secret key. Required. |
| `Address` | The tunnel IP(s) this machine owns, with mask, e.g. `10.0.0.2/24`. Can list several, comma-separated. |
| `ListenPort` | UDP port to listen on (default 51820). Servers set it; roaming clients can omit it (random port). |
| `DNS` | DNS server(s) to use while the tunnel is up. Mostly for full-tunnel setups; prevents leaks. |
| `MTU` | Packet size. Leave unset unless you hit weirdness on odd links; then try lowering (e.g. 1420 → 1280). |
| `PostUp` / `PostDown` | Shell commands run after the interface comes up / goes down (firewall rules, routes). `wg-quick` only. |

### `[Peer]`
| Option | What it does |
|---|---|
| `PublicKey` | The remote machine's public key. Its identity. Required. |
| `AllowedIPs` | The IP ranges behind this peer. Route table **and** inbound source filter (see §1). Required. |
| `Endpoint` | Where to reach this peer: `host:port` or `IP:port`. The side that *initiates* needs it; a server behind no NAT can omit it for roaming clients and learn it from incoming packets. |
| `PresharedKey` | Optional shared secret for this link (§3). |
| `PersistentKeepalive` | Send a tiny packet every N seconds (25 is typical) to keep NAT/firewall holes open. Needed when this peer sits **behind NAT** and must stay reachable; otherwise omit. |

---

## 6. `wg` vs `wg-quick`, and the commands you actually use

- **`wg`** — the low-level tool. Loads keys/peers into the kernel, shows status. Does **not**
  touch your IP addresses or routing table.
- **`wg-quick`** — a convenience wrapper (a shell script) around `wg` + `ip`/`route`. It reads a
  `.conf`, brings the interface up, assigns `Address`, and **installs routes derived from every
  peer's `AllowedIPs`**. This is what you normally use to start/stop a tunnel.
  - Consequence worth remembering: **routes come from `wg-quick`, not `wg`.** If you edit a
    config and only hot-reload the peers (`wg syncconf`), the crypto updates but the **routing
    table does not** — you may need a full `wg-quick down && wg-quick up` (or a manual
    `ip route add`) for new `AllowedIPs` to actually route.

```bash
wg-quick up wg0            # bring tunnel up (from /etc/wireguard/wg0.conf)
wg-quick down wg0          # tear it down
sudo wg show               # status: peers, last handshake, transfer, endpoints
sudo wg show wg0 allowed-ips   # who owns which IPs
wg genkey | wg pubkey      # inspect/derive keys
```

On macOS/iOS the **WireGuard app** does the `wg-quick` job for you (import a `.conf` or scan a
QR code, toggle on). Note: macOS/iOS run **one tunnel at a time** — to reach several servers at
once, use one config with multiple `[Peer]` blocks rather than several tunnels.

---

## 7. Sanity checklist when a tunnel "doesn't work"

Work outward, and use `sudo wg show` first — it's the single most useful diagnostic.

1. **Is there a recent handshake?** `wg show` → "latest handshake". No handshake ⇒ you're not
   even reaching the peer: wrong `Endpoint`, or the UDP `ListenPort` is blocked by a firewall /
   cloud security group. Fix connectivity before anything else.
2. **Handshake OK but no data / one-way?** Almost always **`AllowedIPs`**. Remember it's a source
   filter on receive: a peer drops any decrypted packet whose *source* isn't in the `AllowedIPs`
   you gave it. Both sides must agree on which IPs belong to whom.
3. **Ping the peer's own tunnel IP** (e.g. the server's `Address`). That involves no routing or
   firewalls beyond the tunnel — if *that* fails, it's a tunnel/`AllowedIPs`/source-address
   problem, not a downstream service/firewall problem.
4. **Reaching things *behind* a peer (subnets, containers)?** Then also check: the far side has
   IP forwarding on, its host firewall allows the tunnel interface, and the range is in
   `AllowedIPs` on both ends.
5. **Peer behind NAT keeps going silent?** Add `PersistentKeepalive = 25` on the side that needs
   to stay reachable.

---

## 8. One-screen glossary

- **Interface (`[Interface]`)** — this machine's side of the tunnel (its key, its tunnel IP).
- **Peer (`[Peer]`)** — a remote machine you tunnel to; identified by its public key.
- **Public / private key** — a machine's identity; private stays home, public is shared and
  used by the other side to name you.
- **Preshared key** — optional extra shared secret per link; post-quantum hardening, not
  required.
- **AllowedIPs** — the IP ranges behind a peer. Doubles as the routing rule (send) and the
  source-address ACL (receive). The concept to really understand.
- **Endpoint** — `host:port` where a peer is reached over the internet (UDP).
- **CIDR / `/N`** — how big a range an address names; `/32` = one host, `/24` = a 256-address
  subnet, `/0` = everything. Higher `/N` = more specific.
- **`0.0.0.0/0`** — "all IPv4 addresses"; put in `AllowedIPs` to route your whole connection
  through a peer (full tunnel).
- **Network address** (e.g. `10.20.0.0/24`) — names a subnet, not a machine; the trailing zeros
  are the blanked-out host part.
- **PersistentKeepalive** — periodic tiny packet to hold NAT/firewall holes open.
- **`wg` vs `wg-quick`** — low-level tool vs. the wrapper that also sets addresses and routes.
