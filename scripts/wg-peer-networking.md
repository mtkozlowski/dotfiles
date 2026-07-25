# wg-peer — the networking rules behind the single-IP multi-server fix

Companion to [`wg-peer.md`](./wg-peer.md). `wg-peer` builds **one** client config with several
`[Peer]` blocks so a macOS laptop / iPhone can reach several WireGuard servers (macOS/iOS run
one tunnel at a time). This note verifies, against primary sources, *why* a specific bug
occurred and why the fix works.

## The scenario

- Client reaches **VPS-A** (`10.10.0.0/24`, server `10.10.0.1`) and **VPS-B** (`10.20.0.0/24`,
  server `10.20.0.1`) from a single config with two `[Peer]` blocks.
- Broken config: client `[Interface]` had `Address = 10.10.0.2/32, 10.20.0.2/32`. A worked; B did
  not — ping to `10.20.0.1` timed out although the B handshake succeeded and `wg show` on B listed
  the peer with `allowed ips: 10.20.0.2/32`.
- Root cause (empirical): pinging `10.20.0.1`, macOS stamped the packet with source **`10.10.0.2`**
  (the interface's *primary* address), even after switching both client addresses to `/24` and even
  though the route to `10.20.0.0/24` named `10.20.0.2` as source. `tcpdump` on the utun showed
  `10.10.0.2 > 10.20.0.1`. Server B dropped it: `10.10.0.2` was not in that peer's `AllowedIPs`.
  `ping -S 10.20.0.2 10.20.0.1` worked, proving the source address was the cause.
- Fix (working on both devices): give the client a **single** address `Address = 10.10.0.2/24`, and
  on VPS-B set the client peer to `AllowedIPs = 10.10.0.2/32`, then `wg-quick down/up` so a route to
  `10.10.0.2/32 dev wg0` is installed. Everything now sources from `10.10.0.2`; both servers accept
  it; no source-selection ambiguity.

The claims below explain each moving part.

---

## Claim 1 — AllowedIPs is both an outbound route table and an inbound source filter

**Verdict: Confirmed (first-party).** This is the mechanism that dropped B's packets.

The WireGuard whitepaper (Donenfeld, NDSS 2017) states both roles explicitly:

> "When an outgoing packet is being transmitted on a WireGuard interface, wg0, this table is
> consulted to determine which public key to use for encryption. […] Conversely, when wg0 receives
> an encrypted packet, after decrypting and authenticating it, it will only accept it if its source
> IP resolves in the table to the public key used in the secure session for decrypting it."

And the receive-flow step:

> "Otherwise, WireGuard checks to see if the source IP address of the plaintext inner-packet routes
> correspondingly in the cryptokey routing table. […] But if the source IP is 10.192.122.3, the
> packet does not route correspondingly for this peer, and is dropped."

The design note confirms it is deliberately one list doing both jobs:

> "When sending a packet, the list is consulted based on the destination IP; when receiving a
> packet, that same list is consulted for determining if the source IP is allowed. […] This enforces
> a one-to-one mapping of sending and receiving IP addresses."

The `wg(8)` man page restates the dual role for the `AllowedIPs` field:

> "a comma-separated list of IP (v4 or v6) addresses with CIDR masks from which incoming traffic for
> this peer is allowed and to which outgoing traffic for this peer is directed."

The public overview page phrases the inbound side as an access-control list:

> "when receiving packets, the list of allowed IPs behaves as a sort of access control list."

Because B's peer had `AllowedIPs = 10.20.0.2/32`, an inner packet whose source was `10.10.0.2`
"does not route correspondingly for this peer, and is dropped" — silently, exactly as observed.

Sources: [WireGuard whitepaper §2 Cryptokey Routing (PDF)](https://www.wireguard.com/papers/wireguard.pdf) ·
[wg(8) man page](https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8) ·
[wireguard.com — Cryptokey Routing](https://www.wireguard.com/#cryptokey-routing)

---

## Claim 2 — AllowedIPs need not be a subset of the interface's own address/subnet

**Verdict: Confirmed (by first-party example and by the absence of any constraint).**

Neither the `wg(8)` man page nor the whitepaper imposes any relationship between a peer's
`AllowedIPs` and the interface's own `Address`. The man page defines the field purely as "a
comma-separated list of IP (v4 or v6) addresses with CIDR masks" with no subset requirement. The
whitepaper's own worked example assigns a single peer allowed IPs drawn from unrelated ranges:

> "Allowed Source IPs
> 10.192.122.3/32, 10.192.124.0/24
> 10.192.122.4/32, 192.168.0.0/16
> 10.10.10.230/32"

These are arbitrary CIDRs across multiple disjoint prefixes, demonstrating that allowed IPs are
free-form. This is why VPS-B may legally accept `10.10.0.2/32` — an address *outside* its own
`10.20.0.0/24` subnet. (Nuance: this is shown by example and by the lack of any prose restriction,
not by a sentence that says "allowed IPs may be arbitrary" in so many words. The only cross-peer
constraint WireGuard enforces is that a given prefix maps to exactly one peer per interface.)

Sources: [wg(8) man page](https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8) ·
[WireGuard whitepaper §2 (PDF)](https://www.wireguard.com/papers/wireguard.pdf)

---

## Claim 3 — wg-quick installs system routes for each peer's AllowedIPs; plain wg does not

**Verdict: Confirmed (first-party).** Explains why `wg-quick down/up` was required on B to get the
`10.10.0.2/32 dev wg0` route, and why a `syncconf`-only reload leaves no route.

`wg-quick(8)` states plainly that route installation is *its* job, derived from allowed IPs:

> "It infers all routes from the list of peers' allowed IPs, and automatically adds them to the
> system routing table."

And it is explicitly only a wrapper around the two lower-level tools:

> "Generally speaking, this utility is just a simple script that wraps invocations to wg(8) and
> ip(8) in order to set up a WireGuard interface."

> "It is designed for users with simple needs, and users with more advanced needs are highly
> encouraged to use a more specific tool, a more complete network manager, or otherwise just use
> wg(8) and ip(8), as usual."

The routing table is therefore managed by the `ip(8)` (or `route`) half of the wrapper, not by
`wg(8)`. Plain `wg` / `wg setconf` / `wg syncconf` only load the cryptographic peer configuration
into the kernel/userspace device; they do not add or remove routes. So on VPS-B, editing the peer
and running a `syncconf`-style reload updates the source-filter but leaves the routing table
untouched — the `10.10.0.2/32 dev wg0` route only appears after a full `wg-quick up` (or a manual
`ip route add`). That is precisely why the fix required `wg-quick down/up` rather than a hot reload.

Sources: [wg-quick(8) man page](https://git.zx2c4.com/wireguard-tools/about/src/man/wg-quick.8) ·
[wg(8) man page](https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8)

---

## Claim 4 — macOS/utun source-address selection

**Verdict: Nuanced. Split into spec-prescribed vs. empirically-observed, with confidence flags.**

### (a) What the spec prescribes — and its scope limit (first-party, but IPv4 caveat)

The relevant standard is RFC 6724, *Default Address Selection for IPv6*. Its source-address
selection algorithm ends with the tie-breaker most people expect to save them here:

> "Rule 8: Use longest matching prefix. If CommonPrefixLen(SA, D) > CommonPrefixLen(SB, D), then
> prefer SA."

with

> "CommonPrefixLen(A, B) […] the length of the longest prefix (looking at the most significant, or
> leftmost, bits) that the two addresses have in common, up to the length of S's prefix."

Under Rule 8, sending to `10.20.0.1` *should* prefer source `10.20.0.2` over `10.10.0.2`. **But
RFC 6724 does not govern this scenario**, because the traffic is IPv4 and the RFC explicitly scopes
itself out of IPv4:

> "Application of this specification to source address selection in an IPv4 network layer might be
> possible, but this is not explored further here."

There is **no equivalent standardized default source-selection algorithm for IPv4**. So the "longest
matching prefix should have picked `10.20.0.2`" intuition is *not* a rule the OS is obligated to
follow for these addresses. Confidence: **High** that RFC 6724's Rule 8 is real and would prefer the
same-prefix source; **High** that it does not formally bind the IPv4 case here.

### (b) What macOS / utun empirically does (community evidence, NOT a spec)

For IPv4 on a point-to-point `utun`, the source address is effectively decided by the OS routing
layer / interface primary-address selection, not by a per-address longest-prefix match. In this
case macOS stamped the interface's *primary* address (`10.10.0.2`) onto packets destined for
`10.20.0.1`, ignoring both the `/24` mask change and the route's named source — confirmed locally by
`tcpdump` on the utun (`10.10.0.2 > 10.20.0.1`) and by `ping -S 10.20.0.2 …` succeeding.

The best *documented* corroboration is a WireGuard mailing-list thread on multi-address / multi-home
source selection, where operators saw the wrong source IP chosen for traffic egressing a WireGuard
interface and fixed it with source-based routing / an explicit `src` on the route:

> "the wireguard server always chose the ip with lowest metric as source ip … to reply to the
> client" — 曹煜

> resolved by "deleting the route that wireguard had set and re-creating the same route but defining
> the (correct) IP as src" — Christoph Loesch

**Label:** this is mailing-list/operator evidence, not a formal specification, and it concerns the
general OS source-selection behavior rather than a documented wireguard-apple guarantee. Confidence:
**Moderate** that "multiple addresses on one WG interface → OS may stamp the primary/first address,
and a single address or explicit source is the reliable fix" is the correct generalization; the
device-specific detail (macOS picks the interface's primary address on a point-to-point utun
regardless of mask/route-src) rests on the reproduction in this scenario plus analogous
mailing-list reports, not on a first-party wireguard-apple spec statement. The practical takeaway is
spec-independent: **don't rely on source-address selection across multiple addresses on one WG
interface — collapse to one address.**

Sources: [RFC 6724](https://datatracker.ietf.org/doc/html/rfc6724) ·
[WireGuard mailing list — source IP selection / multi-interface thread (2022-10)](https://lists.zx2c4.com/pipermail/wireguard/2022-October/007848.html)

---

## Claim 5 — macOS/iOS NetworkExtension allows one active tunnel at a time (secondary)

**Verdict: Nuanced — the reason a single multi-peer config is used; first-party support is
indirect.** Apple's Personal-VPN API is fronted by a singleton, `NEVPNManager.shared()`, and the
system surfaces a single active Personal VPN configuration; app-provided packet-tunnel providers
(`NEPacketTunnelProvider` via `NETunnelProviderManager`) can store multiple configurations but only
one runs at a time. This is why `wg-peer` deliberately produces one config with several `[Peer]`
blocks rather than several tunnels — as stated in [`wg-peer.md`](./wg-peer.md):
"macOS/iOS run only one tunnel at a time." Confidence: the one-active-tunnel behavior is
well-established platform behavior and matches the singleton API, but Apple's docs render as
JavaScript and could not be quoted verbatim here, so treat this as convention-backed rather than a
pinned spec quote.

Sources: [NEVPNManager | Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/nevpnmanager) ·
[NEPacketTunnelProvider | Apple Developer Documentation](https://developer.apple.com/documentation/NetworkExtension/NEPacketTunnelProvider)

---

## What this means for the single-IP fix

- **Two client addresses on one utun was the trap.** With `10.10.0.2` and `10.20.0.2` both on the
  interface, the OS (not RFC 6724 — that's IPv6-only) chose the *primary* address `10.10.0.2` as the
  source for B-bound traffic. (Claim 4)
- **B silently dropped it because AllowedIPs is also an inbound source filter.** A decrypted inner
  packet whose source is not in the sending peer's allowed IPs "is dropped." `10.10.0.2` was not in
  B's `10.20.0.2/32`. (Claim 1)
- **Collapsing to one address (`10.10.0.2/24`) removes the ambiguity** — every packet, to A or B,
  sources from `10.10.0.2`, so there is no source-selection decision left to get wrong. (Claim 4)
- **B can legally accept that foreign address** because AllowedIPs need not be a subset of B's own
  subnet — `AllowedIPs = 10.10.0.2/32` on B is valid even though B lives on `10.20.0.0/24`. (Claim 2)
- **`wg-quick down/up` on B was necessary, not optional,** because only wg-quick (via `ip`) installs
  the `10.10.0.2/32 dev wg0` route from allowed IPs; a plain `wg syncconf` updates the filter but
  leaves the routing table stale. (Claim 3)
- **One config, many peers is the right shape** given the one-active-tunnel platform constraint,
  which is exactly what `wg-peer` assembles. (Claim 5)
