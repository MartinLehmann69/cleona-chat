# CLEONA CHAT

## Architecture & Technical Specification

**Decentralized - Post-Quantum Secure - Peer-to-Peer**

Version 2.2 (Stand V3.1.71)
April 2026
Public Edition

---

<!-- AUTO-GENERATED from Cleona_Chat_Architecture_v2_2.md (sha256:b3d2c8b884a0, 2026-04-26). -->
<!-- Edits to this file will be overwritten. Edit the master in Cleona/. -->


## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Network Architecture](#2-network-architecture)
3. [Erasure Coding & Message Delivery](#3-erasure-coding--message-delivery)
4. [Encryption & Cryptography](#4-encryption--cryptography)
5. [Identity & Authentication](#5-identity--authentication)
6. [Identity Recovery & Restore Broadcast](#6-identity-recovery--restore-broadcast)
7. [Synchronization Strategy](#7-synchronization-strategy)
8. [App Permissions & Privacy](#8-app-permissions--privacy)
9. [DoS Protection & Network Resilience](#9-dos-protection--network-resilience)
10. [Private Channels](#10-private-channels)
11. [Network Statistics Dashboard](#11-network-statistics-dashboard)
12. [Technology Stack](#12-technology-stack)
13. [Localization & Internationalization](#13-localization--internationalization)
14. [Feature Roadmap](#14-feature-roadmap)
15. [Data Management & Storage](#15-data-management--storage)
16. [Licensing, Funding & Donation Model](#16-licensing-funding--donation-model)
17. [Security Considerations](#17-security-considerations)
18. [Application Architecture](#18-application-architecture)
19. [Testing & Development Strategy](#19-testing--development-strategy)
20. [Linux Development Environment](#20-linux-development-environment)
21. [VM Test Infrastructure](#21-vm-test-infrastructure)
22. [Development Plan](#22-development-plan)
23. [Calendar](#23-calendar)
24. [Polls & Voting](#24-polls--voting)
25. [In-Call Collaboration](#25-in-call-collaboration)
26. [Multi-Device Support](#26-multi-device-support)
27. [IPv6 Dual-Stack Transport & CGNAT Bypass](#27-ipv6-dual-stack-transport--cgnat-bypass)
28. [Appendix: Protocol Message Format](#28-appendix-protocol-message-format)

---

## 1. Executive Summary

Cleona Chat is a decentralized, peer-to-peer messaging application that operates entirely without central servers. It combines post-quantum cryptography with an innovative network architecture to deliver secure, reliable communication.

The application is built with Flutter (Dart) for cross-platform development, targeting Android and iOS as primary release platforms, with Linux Desktop as the primary development platform and Windows Desktop as an additional supported desktop platform. The source code is publicly available under a Source Available license for transparency and security auditing.

### 1.1 Core Principles

**No central servers:** All communication is fully peer-to-peer via a Kademlia-based Distributed Hash Table (DHT). There is no single point of failure or control. Every node in the network is a full participant — capable of routing messages, storing fragments for offline peers, and sharing peer knowledge. There is no architectural difference between a "server" and a "client."

**Post-quantum end-to-end encryption:** A hybrid approach combining classical algorithms (X25519, Ed25519, AES-256-GCM) with post-quantum algorithms (ML-KEM-768, ML-DSA-65). If either scheme is broken, the other still protects all communication. Database files on disk are encrypted at rest with XSalsa20-Poly1305 using a key derived from the identity's secret key, providing post-quantum secure storage.

**Anonymity by design:** No phone number, email address, or personal information is required. Identity is purely cryptographic.

**Erasure coding for offline delivery:** Messages are split into N=10 redundant fragments using Reed-Solomon coding, of which only K=7 are needed for reconstruction. Fragments are distributed across peers near the recipient's virtual mailbox in DHT space.

**Push-first message delivery:** Message delivery is event-driven, not polling-based. Relay nodes forward fragments immediately to the mailbox owner upon storage (<1 second latency). Polling occurs only once at startup to collect messages that arrived while offline. There are no periodic sync intervals during normal operation.

**Restore Broadcast:** An innovative recovery mechanism where contacts serve as a distributed backup. Upon device loss, a signed broadcast triggers automatic identity and chat history restoration from contacts — no cloud server needed. Only one contact needs to be online for recovery to begin; the rest trickles in progressively.

**HD-Wallet Multi-Identity:** A single master seed derives all identities using HD-wallet-style key derivation (SHA-256 with index-based context strings). Recovery of the master seed via a 24-word phrase restores all identities, including their encrypted DHT identity registry.

**Mesh Discovery:** Nodes find each other organically through physical proximity (WiFi, NFC) and share peer knowledge transitively. No infrastructure required for peer discovery.

**Single port communication:** Each node uses a single random ephemeral port. UDP carries all normal traffic (chat, DHT, relay, signaling, media). A TLS fallback on the **same port** (not port+2 — V3.1.71) provides censorship resistance when UDP is completely blocked (activates after 15 consecutive failures). UDP (SOCK_DGRAM) and TCP (SOCK_STREAM) are separate kernel namespaces, so sharing one port number is conflict-free. Bootstrap uses fixed ports 8080 (Live) / 8081 (Beta) for both UDP and TCP.

**Data compression:** All protocol payloads are compressed with zstd before encryption, reducing bandwidth usage significantly for text and metadata.

**Profile personalization:** Users can set optional profile pictures (JPEG, max 64 KB) and descriptions (max 500 characters) for their identities, groups, and channels. Profile data is exchanged via contact requests, profile updates, and restore broadcasts.

### 1.2 Unique Innovations

**Erasure Coding for Messaging:** Borrowed from distributed storage systems (Ceph, IPFS), but applied to messenger offline delivery. No existing messenger uses this approach. It solves the offline problem without central servers at only 1.43x storage overhead.

**Restore Broadcast:** A completely novel concept. No existing messenger implements this. The idea that your contacts ARE your backup — without them needing to do anything actively — eliminates the need for cloud storage entirely.

**Erasure-Coded DHT Identity Registry:** Multi-identity recovery information is stored in the DHT using Reed-Solomon coding (N=10, K=7), ensuring the registry survives even when several DHT nodes are unavailable.

**Mesh Discovery:** Infrastructure-free peer discovery through physical encounters. Every meeting between two Cleona users merges their entire network graphs, creating organic, viral network growth.

**Two-Stage Media Delivery:** Large files require explicit recipient confirmation before transfer begins, preventing bandwidth waste and media-based DoS attacks.

**Per-Chat Message Policies:** Each conversation has individually configurable message expiry timers, editing windows, download permissions, and forwarding permissions, giving users granular control over data lifecycle and content distribution.

**Per-Chat Configuration Protocol:** In DM conversations, either party can propose configuration changes (download/forwarding permissions, expiry, edit window). The proposed change is sent to the partner who must explicitly confirm or reject it before it takes effect. In groups and channels, the owner sets configuration directly. This ensures mutual consent for privacy-relevant settings.

**Every Node is Equal:** There is no distinction between "server" and "client" in the protocol. Every Cleona node can perform all network functions: peer discovery, message relay, fragment storage, ID resolution. A dedicated bootstrap node exists only as a guaranteed-online peer during the early network phase.

---

## 2. Network Architecture

### 2.1 Communication Port

Each Cleona node communicates over a single port number. UDP is the primary transport. A TLS listener on the **same port** serves as anti-censorship fallback when UDP is blocked (V3.1.71; previously port+2). UDP (SOCK_DGRAM) and TCP (SOCK_STREAM) occupy distinct kernel socket namespaces, so a single port number binds both transports without collision. Bootstrap uses fixed ports 8080 (Live) and 8081 (Beta); other nodes pick a random ephemeral port on first launch.

**Port selection:** On first launch, each node selects a random port in the ephemeral range (10000–65000) and persists it in its profile. This avoids requiring root privileges (ports < 1024), eliminates conflicts with other services, and works on all network environments without configuration. The selected port is stored in the node's profile and reused on subsequent launches.

**Runtime port change (V3.1.44):** The port can be changed at runtime via Settings → Network → Port. The transport layer rebinds the UDP socket and TLS listener to the new port. A `PeerListPush` broadcast is sent immediately to all known peers so they update their address records. The new port is persisted in `identities.json` for use on subsequent launches. Validation: 1024–65535, probe-before-bind to detect conflicts.

**Why not a fixed port (e.g., 443)?** A fixed well-known port like 443 would only help with simple port-based firewalls. A raw P2P protocol on port 443 is immediately recognizable by any DPI-capable firewall and looks more suspicious than traffic on a random high port. Random ephemeral ports work identically to port 443 on home networks, mobile data, and any network without restrictive filtering.

**Network separation** between beta (development) and live (production) networks is achieved through cryptographic means (network tags in node IDs), not through port separation.

**Development note:** During localhost testing, multiple instances use ports starting at 44300 to allow simultaneous operation on a single machine. In VM testing, each VM uses its own random or configured port.

### 2.2 Distributed Hash Table (DHT)

Cleona uses a Kademlia-based DHT as the backbone of its peer-to-peer network. Kademlia was chosen for its proven reliability (used by BitTorrent, IPFS, and Ethereum), efficient O(log n) routing, and natural redundancy through k-bucket replication.

#### 2.2.1 Node Identity

Every device running Cleona is a node in the DHT. The node ID is computed as:

```
node_id = SHA-256(network_secret + public_key_bytes)
```

This produces a 256-bit identifier. The `network_secret` is a 16-byte value derived from the Maintainer Ed25519 key and the network channel (see Section 17.5). Because the secret differs between channels (beta vs. live) and is unknown to forks, nodes with a different secret occupy a completely separate DHT address space — they can never discover or communicate with each other.

#### 2.2.2 Virtual Mailbox

Each user has a virtual mailbox in the DHT address space. The mailbox ID is derived differently from the node ID to prevent correlation. There are two derivations — primary (PK-based, the canonical address) and fallback (Node-ID-based, used by senders who do not yet know the recipient's ed25519 public key):

```
mailbox_id_primary  = SHA-256("mailbox"     + ed25519_public_key)
mailbox_id_fallback = SHA-256("mailbox-nid" + node_id)
```

Senders use the primary if they have the recipient's ed25519 PK in their routing table or `contactManager` (`message_sender.dart:_computeMailboxId`); otherwise they fall back to the Node-ID-based form. Receivers poll both addresses on every mailbox poll (`cleona_service.dart:_pollMailbox`) so no fragment is lost regardless of which form the sender chose.

Nodes whose IDs are closest in XOR distance to the mailbox ID are responsible for temporarily storing message fragments for the user when they are offline.

#### 2.2.3 Routing Table (Distance-Vector, V3)

Each node maintains a routing table with **routes** (not just peers). Inspired by RIP (Routing Information Protocol), adapted for P2P mesh. See `docs/ROUTING_V3.md` for the complete specification.

**Route entry:** Each route contains: destination (NodeId), nextHop (NodeId, null for direct), hopCount, cost (sum of link costs), connectionType (lanSameSubnet/lanOtherSubnet/wifiDirect/publicUdp/holePunch/relay/mobile), lastConfirmed (last successful DELIVERY_RECEIPT via this route). Multiple routes per destination are allowed, sorted by cost (cheapest first).

**Cost model:** Each link type has a fixed cost: LAN same-subnet=1, LAN other-subnet=2, WiFi=3, Public UDP=5, Hole Punch=5, Relay=10, Mobile=20, Mobile via Relay=30. Total route cost = sum of all link costs on the path. Cost determines route SELECTION only — it is independent of TTL (see Section 2.9.9).

**Distance-Vector protocol:** Route updates are propagated event-driven (not periodic) using Bellman-Ford: when a neighbor advertises a route with cost C, and the link to that neighbor has cost L, the total cost is C+L. If this is cheaper than the current route, adopt it. **Split Horizon:** Routes are NOT advertised back to the neighbor they were learned from. **Poison Reverse:** When a route fails, it is advertised with cost=65535 (infinity) to all neighbors. Safety-net: full route exchange once per hour.

**Route-Down detection (V3.1 — relay-aware):** A route is marked DOWN after 3 consecutive RUDP Light timeouts (no DELIVERY_RECEIPT). Route-DOWN is **surgical**: only the specific route (via a particular nextHop) is marked, not all routes to the peer. If alternative routes exist, the peer is not marked as unreachable. **Relay ACK tracking:** Relay/DV sends are also tracked via DELIVERY_RECEIPT (timeout: min 8s for relay, max(2×RTT×hopCount, 8s)). **Per-route failure tracking:** Compound key "${peerHex}|${viaNextHopHex}" instead of a simple per-peer counter. **Route recovery:** Dead routes remain in the table for 5 minutes (cost=infinity) for recovery via neighbor updates. **Private-IP filter:** Direct sends to private IPs are skipped if the sender has no interface in the same subnet.

**Three-tier capacity (max ~2,100 entries):**
1. **Contact routes (max 1,000):** Direct contacts, NEVER evicted.
2. **Transit routes (max ~640):** Kademlia k-buckets (256 buckets, ~20 entries each, O(log n)). Eviction: standard Kademlia rules (ping oldest, replace on timeout).
3. **Channel routes (max 500):** Channel subscribers. Eviction: LRU + highest cost first.

**Loading and pruning (two-phase startup):** Loading the routing table from disk is pure deserialization — all peers are loaded regardless of age. Pruning is a separate step in the caller (`CleonaNode.start()`), currently set to 2 hours. **Safety net:** If the 2-hour prune removes ALL peers but the file had some, the routing table is reloaded without pruning. Stale peers are better than no peers.

**Maintenance pruning:** The periodic maintenance cycle (every 60 seconds) prunes peers older than 4 hours. **Peer selection preference:** `findClosestPeers()` partitions peers into recent (seen < 10 minutes) and stale, preferring recent peers by XOR distance.

**Bootstrap resilience:** Stored routing table entries (post-pruning) are used as additional seed peers at startup. Additionally, an optional `bootstrap_seeds.json` file (read-only at startup, populated externally — e.g. by the deployment tooling for headless and emulator setups) provides a fallback when the routing table has ≤3 peers after startup. ContactSeed-scanned peers are persisted via the routing table (`isProtectedSeed=true` to survive Doze pruning), not via this file.

**Secondary UserID index:** Alongside the 256 XOR-keyed k-buckets, the routing table maintains `Map<String, List<PeerInfo>> _byUserIdHex` so that `getPeerByUserId` and `getAllPeersForUserId` run in O(1). The index is maintained in lockstep with `addPeer` / `removePeer` / `removePeerByNodeId` / `prune` / `pruneStaleSeeds`; late-learned user IDs must go through `setPeerUserId(peer, userId)` rather than direct field assignment. When a user has multiple devices online (e.g. phone + laptop), `getPeerByUserId` returns the peer with the highest `lastSeen` — sends fan out to the most-recently-active device rather than whichever entry happened to come first in bucket-iteration order. Peers with `userId == null` (legacy pre-§26-Phase-2 entries) are not indexed; they still resolve via a linear fallback that matches `nodeId == userId`. §26 Phase 3 `sendToAllDevices` reads the full device list from the same index.

#### 2.2.3.1 User×Device dedup — deliberate non-goal

**The decision:** Each `(user, device)` pair is stored as an independent `PeerInfo`. Two identities that share a physical device appear as two routing-table entries with two independent copies of that device's physical state (`addresses`, per-address `consecutiveFailures`, NAT-hole-punch state, `lastSeen`, RTT-EMA). No attempt is made to collapse them into a shared device record.

**Why this is a reasonable thing to consider:** Classical P2P systems model `peer = (host:port)` or `peer = (keypair)`. Cleona carries a **two-dimensional (user × device) matrix** embedded in a one-dimensional set of physical (host:port) endpoints, because §26 Multi-Device gives one identity N devices and multi-identity setups put N identities on one device. In the current design the physical layer is duplicated whenever the same box serves multiple identities: when the shared NIC dies, N independent failure counters have to climb past the 3× threshold before the app notices; when the user hole-punches to the box, the hole is punched N times; when PEER_LIST_PUSH learns a new address for the box, it is added to N separate `addresses` lists.

**What a real dedup layer would actually require:**

1. A new `DeviceRecord` object that owns the physical state — `addresses` (with per-address scores and failure counters), NAT classification, hole-punch state, RTT-EMA, `lastSeen`. Each `PeerInfo` demoted to `(userId, DeviceRecord, per-identity flags)` where "per-identity flags" stay on `PeerInfo` because they **must not** cross the identity boundary (see the trust point below).
2. A way to *detect* that two `PeerInfo` entries actually refer to the same device. Options:
   - **Implicit:** match on address-set intersection. Ambiguous when two devices happen to share an address (CGNAT peers land on the same `100.64.x.y:port` during a brief window) and racy when addresses drift. Would need heuristics plus a disambiguation pass on every `PEER_LIST_PUSH`.
   - **Explicit:** carry a `deviceFingerprint` on the wire (new bytes in `PeerListEntry` / `PONG` / `CONTACT_REQUEST`). That is a protocol bump touching every codepath that deserializes peer entries, plus the §26 Phase 2 `deviceNodeId` already serves a similar purpose but is *per-identity-hashed* (`SHA-256(secret + pubkey + deviceId)`), so it can't dedup *across* identities without leaking which pubkeys share a device.
3. A migration story for the k-buckets. Today every `(user, device)` slots into one bucket by XOR-distance of `deviceNodeId`. If devices are shared records, the bucket key can still be `deviceNodeId`, but `findClosestPeers` needs to stop double-counting when N identities on the same device land in the same bucket.
4. Reconciling application-layer state. Rate-limit counters, reputation scores, DoS bans, `isProtectedSeed` are **per-identity** — merging them would let a misbehaving identity poison the reputation of a well-behaved identity that happens to share hardware (bundle attack, cross-identity correlation). So the dedup would have to rigorously separate physical state (safe to share) from application state (must stay split) across every file that today reads `peer.addresses` or `peer.consecutiveRouteFailures`.
5. Churn when addresses drift. Mobile IP changes, VPN on/off, CGNAT port rebalances — a "same device because same address" heuristic would either mistakenly merge unrelated devices or mistakenly split one device when its IP flips. Explicit fingerprints solve this but require (2) above.

Rough estimate: **~600–900 lines of Dart** across `peer_info.dart`, `kbucket.dart`, `dv_routing.dart`, `cleona_node.dart`, `peer_manager.dart`, `transport.dart`, `nat_traversal.dart`, plus a wire-protocol extension or a carefully-written heuristic + test suite for the dedup heuristic's edge cases.

**Why the benefit does not (yet) justify the cost:**

- **Not a correctness bug.** Every feature that would ostensibly benefit — NAT hole-punching, address scoring, relay learning, RUDP-light failure counting — already works correctly with the current 2D representation. The cost is a constant multiplier in routing-table memory and some wasted hole-punch / PING packets when the same device is learned under multiple identities. Both are unmeasured today, and at the current network size the absolute numbers are tiny (each `PeerInfo` is ~1 KB; a user with 20 contacts × 2 devices × 3 identities is at most 120 entries, roughly 120 KB).
- **Trust boundary matches identity boundary.** Application-layer state (rate limits, reputation, DoS bans, contact verification level) is deliberately per-identity. A physical-device merge that shared any of this state would widen the trust boundary in a way that attackers could exploit to smear reputation across identities. Keeping per-identity state in per-identity `PeerInfo` keeps the boundary where §5 (Identity & Authentication) and §9 (DoS Protection) assume it is.
- **The P2P invariants that do care about devices already use `deviceNodeId`.** §26 Phase 3 `sendToAllDevices` reads per-device entries out of the routing table — it *wants* N entries for an N-device user, not one merged entry. Collapsing devices would add a "fan this back out" step for every call fanout.
- **Address drift risks false merges.** CGNAT means two physically-distinct devices can share an `ip:port` for a burst; heuristic dedup would bind them to one record and then have to undo that when the NAT ports rotate. The resulting churn would be more expensive than the duplication it was trying to eliminate.
- **No telemetry pressure.** We have no measurements showing redundant hole-punches, no user reports of "my phone holds a connection but my other identity on the same phone can't". The engineering work is speculative until at least one of those signals appears.

**Concrete signals that would trigger reconsideration:**

1. **Measurable NAT-hole-punch multiplier.** If `network_stats_screen.dart` or field-testing shows that a multi-identity user's hole-punch traffic to the *same physical peer* is N× higher than a single-identity baseline (i.e. the duplication actually costs packets on the wire), implement explicit `deviceFingerprint` — not heuristic dedup.
2. **Reachability report correlated with identity count.** Users running 3+ identities reporting "I keep losing connection to Alice" while single-identity users on the same network don't. This would indicate that redundant failure counters delay the switch to relay long enough to be user-visible.
3. **Routing-table memory pressure on long-running Android devices.** If a device in Doze keeps accumulating entries and RSS grows measurably faster than `peerCount × ~1 KB` would predict, the duplicated address lists are probably the cause. The cheaper fix would be `pruneStaleAddresses` (already exists) before a full dedup refactor.
4. **A new §26 capability that genuinely needs "is this the same device?"** — for instance, per-device media storage quotas across identities, or device-local cache sharing. At that point the fingerprint is unavoidable and becomes cheap to add once the use case is concrete.

If any of those signals land, the implementation plan is: start with **explicit `deviceFingerprint` on the wire** (option 2b above) — the cleanest path, avoids the heuristic churn of 2a — and keep application-layer state per-identity. Until then, the two-dimensional (user × device) representation is the documented design and optimizations stay on the `PeerInfo` side (the secondary userId index above, `pruneStaleAddresses`, `pruneStaleSeeds`).

#### 2.2.4 Identity Resolution (2D-DHT)

Cleona löst User-IDs zu aktuellen Device-Adressen über zwei signierte Wertetypen
im selben Kademlia-Ring auf. Das ist eine zweite logische Lookup-Dimension neben
der heutigen Device-keyed Routing-DHT — keine zweite Topologie.

**Auth-Manifest** (langlebig, hybrid-signiert):
- Schlüssel: `Hash("auth" + userId)`
- Inhalt: `{userId, [authorizedDeviceNodeIds], ttl=24h, seq, publishedAtMs, ed25519Sig, mlDsaSig}`
- Signiert vom User-Master (Ed25519 + ML-DSA-65, hybrid)
- TTL 24h, refresh alle 20h
- Replikation: K=10 closest, Standard-Kademlia (kein Erasure-Coding)

**Liveness-Record** (kurzlebig, Ed25519-only):
- Schlüssel: `Hash("live" + userId + deviceNodeId)`
- Inhalt: `{userId, deviceNodeId, currentAddresses, ttl=15min/1h, seq, publishedAtMs, ed25519Sig}`
- Signiert vom User-Ed25519-Key (gemeinsam genutzt über alle Devices via §26 Phase-2)
- TTL adaptiv: 15min Foreground / 1h Background (analog CalendarSync V3.1.56)
- Refresh-Trigger: TTL-Timer + onAddressesChanged-Hook (NetworkChangeHandler)
- Replikation: K=10 closest

**Resolution-Cascade** beim Senden:
1. Lokaler `_byUserIdHex`-Cache (siehe §2.2.3 Secondary UserID index) — Hit → existing send-cascade
2. Cache miss → DHT-Lookup `Hash("auth" + userId)` → Auth-Manifest
3. Pro authorisiertes Device parallel: DHT-Lookup `Hash("live" + userId + deviceNodeId)` → Liveness
4. Authorized-List-Membership-Filter (Revocation), Sig-Verify, Cache populate
5. Empty result → MessageQueue (existing 7-Tage-TTL retry)

**Multi-Identity-Daemon:** Jede gehostete Identität publiziert eigenständig.
`_createEnvelope` accepts `IdentityContext`-Parameter — alle Identitäten
sind als Sender unabhängig auf der Wire.

**Hard-Cut-Migration:** Identity-Resolution ist Bestandteil des Sec H-5
KEM v2 Hard-Cut-Releases. Kein Legacy-Resolution-Fallback im neuen Code.

**Threat-Modell für Liveness Ed25519-only:** Auth-Manifest trägt die
Identitäts-Authentizität (PQ-sicher). Liveness ist transient-transport-only —
PQ-Forgery führt zu falscher Adresse, nicht zu Identitäts-Übernahme. Sender
erkennt Forgery beim KEM-Setup-Roundtrip mit User-Pubkey aus dem
hybrid-signierten Auth-Manifest. Forgery-Window ≤ Liveness-TTL = max 1h.

**Bewusster Verzicht:** kein eigener DHT-Ring (verworfen in Spec §3 als
Variante A wegen Memory + Bandwidth Doppelung). Kein deviceFingerprint
(unverändert ADR §2.2.3.1). Reverse-Lookup `deviceNodeId → users` wird
intentional nicht unterstützt (Privacy-Schutz für Multi-Identity-Daemons).

### 2.3 Mesh Discovery

Cleona uses organic, infrastructure-free peer discovery inspired by real-world social networks. Nodes find each other through physical proximity and share their knowledge transitively. No central server or directory is needed.

#### 2.3.1 The Principle

Every Cleona node maintains a peer list: a signed, timestamped directory of all known nodes and their reachability information. When two nodes encounter each other — in the same WiFi, via NFC tap, or through a QR code scan — they exchange their complete peer lists. After this exchange, both nodes know about all nodes the other had previously encountered.

Example scenario 1: Alice installs Cleona and is alone — her peer list is empty. Her partner Bob installs Cleona. They are on the same WiFi. Both devices discover each other automatically via IPv6 Multicast. Now Alice knows Bob, and Bob knows Alice. Alice visits a colleague, Charlie, who also runs Cleona. Alice and Charlie exchange peer lists. Now Alice knows Bob and Charlie, Charlie knows Alice and Bob (transitively, without ever meeting Bob). When Charlie later encounters Diana, Diana also learns about Alice and Bob. Within a few hops of transitive exchange, the entire network is connected.

Example scenario 2: Alice meets Bob at home. Alice is in the local WLAN. Bob is just a visitor with no access to Alice's WLAN. Bob installs Cleona and starts with an empty peer list. Alice shows her QR code (ContactSeed URI) containing her node ID, her reachable addresses (public + local), and up to 10 best seed peers from her peer list with all their known addresses. Bob scans the QR code. Bob's Cleona adds the seed peers and tries to connect to any of them (trying all addresses in parallel). Once connected to any peer, Bob's node performs a full Kademlia bootstrap, building up its routing table through PeerExchange with learned peers. All peers then add Bob's public IP to their peer lists. Now that basic network connectivity is established, Bob sends Alice a contact request. Alice confirms and encrypted communication begins.

This is mathematically equivalent to the "six degrees of separation" principle: after a few hops of transitive peer exchange, the entire network is connected.

#### 2.3.2 Peer List Entry Format

Each entry in the peer list contains all information needed to reach a node:

- node_id (32 bytes)
- public_ip, public_port (legacy, primary address)
- local_ip, local_port (legacy, LAN address)
- **addresses** (multi-address list, scored by reliability)
- network_channel (diagnostic field, security enforced by HMAC — see Section 17.5)
- last_seen timestamp
- NAT type classification
- capabilities bitfield
- ed25519_public_key (for mailbox ID computation)
- ml_dsa_public_key (for post-quantum signature verification)
- ed25519_signature + ml_dsa_signature (dual signatures)

**Multi-address support:** Each peer can be reachable via multiple addresses (IPv4 public, IPv6 global, LAN, UPnP-mapped, etc.). All successful contact methods are stored in a `PeerAddress` list and scored by reliability (success/fail ratio). The `allConnectionTargets()` method returns a deduplicated, scored list combining the legacy `publicIp`/`localIp` fields with the multi-address list, sorted by reliability score (best first). This ensures that senders always try the most reliable path first while maintaining backward compatibility with the legacy address fields.

Each `PeerAddress` entry contains:
- ip, port
- type (ipv4Public, ipv4Private, ipv6Global)
- score (0.0–1.0, based on success/fail ratio)
- lastSuccess, lastAttempt timestamps
- successCount, failCount

Entries older than 14 days without successful contact are automatically removed (stale peer cleanup). Only entries with matching network_channel are exchanged (enforced by HMAC at the packet level — see Section 17.5). The dual signature (classical + post-quantum) prevents spoofing of peer list entries.

**IP validation:** Nodes must not register with `0.0.0.0` as their local IP, which would cause other nodes to send packets to themselves. Local IP is detected via `NetworkInterface.list()` at startup.

**IP sanitization:** `PeerInfo._sanitizeIp()` strips port suffixes, spaces, and other garbage from IP strings. This handles corrupted data like `"203.0.113.10:4443 192.0.2.11"` that can occur when IP strings are concatenated instead of stored separately.

#### 2.3.3 Passive Discovery (Automatic, No User Action)

**IPv6 Multicast:** Cleona sends a 46-byte HMAC-authenticated CLEO discovery packet to the multicast group `ff02::1`. The packet format is: `[8 bytes HMAC-SHA256 truncated (see Section 17.5)][4 bytes "CLEO" magic (0x43 0x4C 0x45 0x4F)][32 bytes nodeId][2 bytes port (big-endian)]`. The 8-byte HMAC prefix authenticates the packet using the network secret — packets with an invalid HMAC are silently dropped before any further processing. All Cleona nodes on the same local network respond with their node ID and reachability info. Zero configuration needed, works on any network with IPv6 multicast support. IPv6-only addresses discovered via multicast are filtered when the node's transport uses IPv4, preventing send failures.

**Important:** Because multicast discovery packets arrive on the same UDP socket as protobuf protocol messages, incoming 46-byte packets with the HMAC prefix + "CLEO" magic bytes are filtered out before protobuf parsing in `_onDataReceived()`. Without this filter, discovery packets cause `InvalidProtocolBufferException` errors.

**IPv4 Local Broadcast:** Cleona sends broadcast discovery packets on UDP port 41338 using IPv4 broadcast (`255.255.255.255`). Broadcast is limited to the local /24 subnet — it never crosses subnet boundaries. Works on every IPv4 network without any router configuration.

**IPv4 Multicast (V3.1):** Cleona sends the same 46-byte HMAC-authenticated CLEO discovery packet to IPv4 multicast group `239.192.67.76` (Organization-Local Scope, RFC 2365; 67.76 = ASCII "CL") with **TTL=4** (multicastHops). Unlike broadcast, IPv4 multicast CAN be routed across subnets by routers with IGMP support. **Important:** Many consumer routers (Fritzbox, etc.) do NOT support IGMP routing — in those cases, multicast only works within the local /24 (identical to broadcast). Broadcast and multicast are sent in parallel on the same socket; the listener receives both via `joinMulticast()`.

**Event-driven discovery (V3/V3.1):** Discovery packets are sent as a **3-packet burst at 2-second intervals** on **all three channels in parallel** (IPv4 Broadcast + IPv4 Multicast + IPv6 Multicast), then the sender STOPS. No perpetual broadcasting. When a new node comes online, it sends its own burst — existing nodes hear it on the discovery listener (which runs permanently). Discovery bursts are triggered on: (1) Node startup, (2) Network change.

**Cross-Subnet Unicast Scan (V3.1.1):** If **0 peers** are still known after the 3-packet burst (neither broadcast nor multicast found anyone), a unicast scan starts across the /16 network. The scan sends the same 46-byte HMAC-authenticated CLEO discovery packet via unicast to port 41338 on every host in the /16 (except the own /24). **Scan order:** DHCP hotspots first (.1, .50, .100, .150, .200 per subnet), then fill in the rest. The scan **stops immediately** when a peer responds. Traffic: ~65K packets × 46 bytes = ~3MB, one-shot at startup, ~500 packets/s = ~130s maximum. In practice, the scan finds a peer within 10–15s. No manual --bootstrap-peer or bootstrap_seeds.json required — the discovery listener on port 41338 reacts to unicast the same way it does to broadcast/multicast.

#### 2.3.4 Active Discovery (Deliberate User Action)

**NFC Contact Exchange:** Two phones held together (~4cm range) exchange identity data and peer lists instantly via NFC. This is a deliberate, intentional action — a digital handshake.

NFC serves a dual purpose: (1) **Peer Discovery** — both nodes exchange their peer lists, merging their network knowledge. (2) **Contact Pairing** — both nodes exchange their public keys, display names, and profile data. After the NFC tap, both phones display a confirmation dialog: *"Add [Name] as contact?"*. Only when **both** users confirm is the contact created on both sides. This mutual-consent model requires no CONTACT_REQUEST/RESPONSE roundtrip over the network — the key exchange already happened via NFC.

**Security properties:** NFC requires physical proximity (~4cm) that cannot be relayed or spoofed remotely. No background advertising (unlike Bluetooth) — NFC is only active during a deliberate user action, eliminating presence leakage. The exchanged data (public keys, display name) is public by nature, so passive eavesdropping at extended range (~10m with specialized antennas) reveals no secrets. Contacts established via NFC tap are immediately assigned **Verification Level 3 (Verified)** — physical co-presence is the strongest proof of identity.

**Why not Bluetooth Low Energy (BLE)?** BLE was evaluated and rejected due to unacceptable security trade-offs: (1) **Presence leakage** — BLE advertising broadcasts "this device runs Cleona" to everyone within ~30m, enabling passive surveillance and physical tracking. In hostile environments this is a safety risk. (2) **Peer list poisoning** — BLE operates outside the Closed Network Model (HMAC-authenticated UDP), allowing attackers to inject fake peers before network-level authentication kicks in. (3) **Eclipse attacks** — fresh nodes with empty routing tables are vulnerable to BLE-based flooding with attacker-controlled peers. (4) **No meaningful benefit** — the existing discovery mechanisms (IPv4 Broadcast, IPv4 Multicast, IPv6 Multicast, Subnet Scan) already cover LAN discovery comprehensively. BLE's only advantage (background proximity discovery) is also its biggest liability.

**QR Code / ContactSeed:** One user displays a QR code containing a `ContactSeed` URI. The URI encodes:
- Sender's node ID (32 bytes / 64 hex chars)
- Sender's display name
- Sender's reachable addresses (**private AND public IPs**, multi-address separated by `%2B`)
- Up to 5 best seed peers with max 2 addresses each for QR codes (up to 10 for .clp file exchange)

Format: `cleona://<nodeIdHex>?n=<name>&a=<ip:port%2Bip:port>&s=<nodeId1@ip1:port1%2Bip2:port2,...>`

**Own addresses (V3):** The `ownAddresses` field MUST contain both private LAN IPs AND the public IP (from NatTraversal). Minimum: 1 private + 1 public. Maximum: 2 private + 2 public. This ensures the QR code works for both LAN and internet contacts.

**Seed peer requirements (V3):** Only **confirmed, currently reachable** peers are included as seed peers. A peer is confirmed if it responded with a PONG or DELIVERY_RECEIPT within the last 10 minutes. Unconfirmed peers MUST NOT appear in the QR code — dead peers in a QR code waste the scanner's time and may prevent successful contact. At least 1 private and 1 public seed peer should be included (2+2 ideal) for redundancy if one goes offline before the CR is accepted.

**Post-scan flow (V3):** After scanning, the new contact: (1) Connects to a seed peer (preferably LAN). (2) Gets the full peer list via Peer Exchange. (3) **Announces its own reachability (private + public) to ALL learned peers** via ROUTE_UPDATE. (4) Sends CONTACT_REQUEST to the QR creator.

**Important:** The multi-address separator `+` is encoded as `%2B` in the URI because `Uri.splitQueryString` (form-url-encoding) interprets literal `+` as space. The parser uses manual query string parsing via `_safeDecodeComponent()`.

**IPv6 zone ID filtering:** IPv6 link-local addresses with zone IDs (e.g., `fe80::1234%enp1s0`) are excluded from QR code seed peers via `toUri()` because zone IDs are interface-specific and meaningless on another device.

For QR codes, the seed peer count is limited to 5 (with max 2 addresses each) to keep the QR code scannable (~350 characters). For .clp file exchange, the full 10 peers are included.

**Two-stage bootstrap from ContactSeed:**
1. **Stage 1 (Minimal seed):** The receiver adds the seed peers from the QR code and attempts to connect. Any reachable peer responds with its full peer list via the standard PeerExchange protocol.
2. **Stage 2 (Full DHT bootstrap):** Once connected to any peer, a complete Kademlia bootstrap runs, populating the routing table with the full network. The seed peers serve as entry points only — they are not special in any way. **Peer probing (V3.1.44):** Peers learned via FIND_NODE_RESPONSE are immediately sent a PING (up to 2 addresses each). This establishes bidirectional communication, confirms the peer as reachable, and enables it as a QR seed peer. Without probing, peers learned transitively would never be confirmed.

**Copy & Paste ContactSeed URI (V3.1.41):** The QR Show screen's "Copy" button copies the full `cleona://` URI (including seed peers) to the clipboard. This URI can be shared via any text channel: email, SMS, another messenger, paper. The "Add Contact" dialog accepts both plain hex Node-IDs and full `cleona://` URIs. When a URI is pasted, the same `addPeersFromContactSeed()` flow as QR scanning is used — the recipient gets seed peers for network bootstrap, even without any prior Cleona contact.

**Share Peer List:** A "Share my network" button in the app generates a compact, signed peer list file (.clp extension) or a shareable link. This file can be sent via any channel whatsoever: email, SMS, another messenger, USB stick — even printed on paper as a QR code.

**Manual Peer Entry:** A user can directly enter the IP address or hostname of a known peer. This is a technical fallback for advanced users and debugging.

#### 2.3.5 Peer List Exchange Protocol

When two nodes discover each other through any method, they execute a delta-based peer list exchange in three steps: (1) Both send a compact **Summary** containing only node IDs and last_seen timestamps (`PEER_LIST_SUMMARY`). (2) Each side identifies entries the other is missing or has newer versions of and sends a **Want** request (`PEER_LIST_WANT`). (3) Only the requested full PeerInfos are transmitted in a **Push** (`PEER_LIST_PUSH`).

This delta-based approach is bandwidth-efficient. A peer list with 1,000 nodes compresses to approximately 50–100 KB for the full list, but the summary (IDs + timestamps) is under 10 KB, and a typical delta is even smaller.

**Ed25519 PK preservation:** When `upsertPeer()` updates an existing entry with newer timestamps, it preserves the existing `ed25519PublicKey` if the new entry lacks one. This is critical for correct mailbox ID computation during offline delivery.

**Address preservation:** `upsertPeer()` also preserves existing publicIp/localIp values when the new entry lacks them. If the new entry has a different publicIp from PeerExchange push data (which carries the peer's self-announced authoritative publicIp), the publicIp is adopted even when the new entry has an older timestamp — because PeerExchange push data is authoritative for the peer's own address.

#### 2.3.6 Ongoing Sync (Without Physical Encounters)

Physical proximity is only the initial door opener. Once two nodes know each other, all further peer list exchanges happen automatically over the internet during regular sync cycles. During each sync window, nodes exchange deltas with known peers, propagating new peer information transitively.

This means: if your friend visits someone and learns new peers, you will receive those new peers automatically at the next internet sync — no physical meeting required.

### 2.4 NAT Traversal & Reachability

Most devices sit behind NAT routers and have private IP addresses that are not directly reachable from the internet. This is the fundamental challenge of all P2P systems. Cleona uses a multi-strategy approach.

#### 2.4.1 Public Address Discovery

A node behind NAT does not know its own public IP address. Other peers help: when Node A receives a packet from Node B, Node A can see Node B's public IP (the NAT router's external address) and reports it back. Multiple confirmations are required before a node accepts a reported public IP as valid. This is essentially a decentralized STUN mechanism — no dedicated STUN server is needed because every peer can provide this service.

**Implementation:** `nat_traversal.dart` handles peer-reported public addresses. The `NatClassification` enum categorizes NAT types (Public, FullCone, Symmetric, Unknown) to select the optimal connection strategy. On network change (WiFi switch, cellular toggle, app resume), `NatTraversal.reset()` clears all observed addresses and resets the NAT classification to `unknown`, forcing a fresh public address discovery from the new network (see Section 2.7).

**Address scoring:** Each `PeerAddress` tracks success/fail counts. `recordSuccess()` and `recordFailure()` are called after every send attempt in `_sendRaw()`. Addresses with `score < 0.1` are skipped in `sendEnvelope()` when better alternatives exist. New addresses start with score 0.5.

**Exponential backoff:** After 2+ consecutive failures, addresses enter exponential backoff (2s → 4s → 8s → ... capped at 2min). Addresses in backoff are skipped by `sendEnvelope()`. **LAN Discovery resets backoff:** When a peer announces itself via LAN broadcast/multicast (`_touchPeer` with `isAuthoritative: true`), its `consecutiveFailures` counter is reset to 0, immediately re-enabling the address. This prevents temporary failures (e.g., daemon restart) from blocking LAN delivery for minutes.

**Proactive internet peer probing:** When a new peer with a public (non-RFC1918) IP is learned via PeerExchange, the node immediately sends a PING to that peer. This opens a NAT pinhole (the outgoing UDP packet creates a mapping in our NAT router), and the peer's PONG triggers decentralized STUN (reporting our public address back). The peer is also registered for UDP keepalive to maintain the pinhole. This ensures nodes behind NAT proactively establish reachability to internet peers, rather than waiting for the next scheduled discovery cycle.

**Address broadcast on IP change:** When `_updateOwnPublicAddress()` detects an actual change in our public IP, `_broadcastAddressUpdate()` sends a `PEER_LIST_PUSH` containing only our own PeerInfo to all known peers. This is rate-limited to max once per 30 seconds. Peers process this via the existing `_handlePeerListPush` handler, immediately learning our new address.

**DHT mailbox fallback for unreachable contacts:** When `_broadcastAddressUpdate()` fails to deliver the `PEER_LIST_PUSH` directly to a contact (e.g., the contact's address is stale), the address update is stored as erasure-coded fragments in the contact's DHT mailbox — the same mechanism used for offline chat messages. When the contact next polls their mailbox, they receive the address update and proactively ping the new address to establish direct connectivity. This works without any central server — any DHT peer can store the fragments. Only accepted contacts receive mailbox fallback (not random routing-table peers), preventing address-update spam.

**KBucket public IP preservation:** When a peer's routing table entry is updated, `KBucket.addPeer()` preserves the existing authoritative public IP if the new entry carries a private IP as publicIp. This prevents the correct public IP (learned via PeerExchange self-announcement) from being overwritten by the observed source IP of a LAN-routed packet.

#### 2.4.2 Connection Strategies

Cleona implements multiple strategies for establishing connections between nodes behind NAT, in priority order:

1. **Direct LAN** (both on same subnet or routable via gateway)
2. **Direct public UDP** (one or both have public IP)
3. **UDP hole punching** (both behind NAT, coordinated via mutual peer — see Section 2.4.6)
4. **Relay via known route** (Distance-Vector routing table provides relay path)
5. **Default-Gateway** (forward to best-connected peer for unknown destinations)

#### 2.4.6 Active UDP Hole Punch & NAT Keepalive (V3)

When a node learns about a peer with a public IP (via routing table, PeerExchange), it immediately attempts a **coordinated UDP hole punch**:

1. Node A → Coordinator (e.g. Bootstrap): `HolePunchRequest(target=B, myIp=85.x.x.x:39874)`
2. Coordinator → Node B: `HolePunchNotify(requester=A, ip=85.x.x.x:39874)`
3. A sends UDP to B's public IP (opens NAT pinhole at A's router)
4. B sends UDP to A's public IP (opens NAT pinhole at B's router)
5. Both can now communicate directly — relay becomes unnecessary

**NAT timeout probing:** The keepalive interval is dynamically determined per connection:
1. After successful hole punch, send PING/PONG at increasing intervals: 15s, 30s, 60s, 90s, 120s
2. When PONG stops arriving → last working interval = NAT timeout for this connection
3. Keepalive interval = 80% of NAT timeout (e.g., timeout 60s → keepalive every 48s)
4. Value is persisted per connection (NAT timeout rarely changes)

**Typical NAT timeouts:** Home routers (Fritz!Box): 60-180s. Mobile/CGNAT: 30-60s. Corporate NAT: 120-300s.

**The NAT keepalive is the ONLY periodic network traffic in the entire system.** Everything else is event-driven.

**On successful hole punch:** The node updates its routing table with a direct public route (cost=5) and propagates the new route to neighbors via ROUTE_UPDATE. The relay route (cost=10+) remains as fallback but is no longer primary.

#### 2.4.3 Route-Based Delivery (V3)

**V3 replaces "shotgun to all addresses" with route-based prioritized delivery:**

`sendEnvelope()` uses the cheapest route from the Distance-Vector routing table (see Section 2.2.3). If the cheapest route fails (RUDP Light timeout), the next cheapest route is tried. This is fundamentally different from the previous approach of sending to all addresses in parallel ("shotgun").

**Route selection:**
1. Look up destination in routing table → get list of routes sorted by cost
2. Send via cheapest route (UDP to nextHop's best address)
3. RUDP Light tracks delivery (DELIVERY_RECEIPT expected)
4. On timeout → try next route
5. After 3 consecutive timeouts on a route → mark DOWN, Poison Reverse

**Address priority within a route:** When the nextHop has multiple addresses, they are prioritized: LAN same-subnet (1) > LAN other-subnet (2) > Public (3) > CGNAT/Mobile (4). Send to the **best address first** (sequentially, not parallel). Only escalate to the next address on failure. This prevents duplicate packet delivery and double rate-limit consumption when a peer is reachable via multiple paths (e.g. private LAN + public DNAT).

**RUDP Light retry on ACK timeout (V3.1.35):** When a DELIVERY_RECEIPT is not received within the timeout, the message is re-queued in the persistent MessageQueue for immediate re-send. The re-send runs `sendEnvelope()` again, which picks the next cheapest route (the failed route has an incremented failure counter). This implements the "on timeout → try next route" behavior.

**Default-Gateway (V3):** When no route to the destination exists: (1) Ask best-connected LOCAL peer (most routes, lowest avg cost, highest uptime). (2) If local peers don't know the route → send to PUBLIC address of best-connected peer. (3) TTL prevents loops (see Section 2.9.9). This replaces dropping packets for unknown destinations.

**Alt-Relay when target IS the gateway (V3.1.52):** When the recipient's deviceNodeId resolves to the DV default-gateway itself, the normal gateway relay path is inapplicable (gwHex == peerHex). In this case, the cascade tries any other confirmed DV neighbor as relay hop. This fixes message delivery when a mobile device's default gateway is the recipient node (common in cross-subnet topologies with §26 Multi-Device userId→deviceNodeId mapping).

**DHT RPC delivery:** DHT protocol messages (PING/PONG/FIND_NODE) still use multi-address sending for protocol compatibility, as DHT RPCs need wildcard response matching.

**No plain TCP (V3.2):** All normal traffic uses UDP. TLS on the **same port as UDP** (V3.1.71; previously port+2) is the anti-censorship fallback (activates after 15 consecutive UDP failures). Plain TCP was removed because it cannot be relayed, cannot deliver offline, and RUDP Light already guarantees integrity. Payloads >1200 bytes use app-level UDP fragmentation with NACK-based retry (see Section 2.9.10).

**Protocol Escalation (V3.1.7):** Delivery escalates through three stages as needed: (1) UDP single packet (<=1200B). (2) UDP fragmented with Fragment-NACK retry (>1200B). (3) TLS on the same port as UDP (when UDP is blocked or peer is already in TLS mode). The escalation is sticky per peer until network change (TlsFallbackManager). For large payloads >1200B, if the peer is already in TLS mode, TLS is tried first; otherwise UDP fragmentation with NACK handles the transfer.

**Direct-Send skip for large unconfirmed payloads (V3.1.7):** Payloads >1200B are NOT sent via direct UDP when the route is not `ackConfirmed`. This prevents OS send buffer flooding with dead fragments to AP-isolated peers. Such payloads go directly to relay/S&F delivery.

#### 2.4.4 Connection Attempt Order

When Node A wants to communicate with Node B, it tries these strategies in order: (1) If both report the same local network, use local IP (instant, no NAT). (2) Try direct connection to Node B's public IP. (3) UDP hole punching if both are behind NAT. (4) Relay via learned route or DV routing table. (5) Default-Gateway. (6) Store-and-Forward on nearby peers.

#### 2.4.4a Address Priority by Type

When a peer has multiple addresses (multihomed), they are prioritized by network type:

| Priority | Address Type | Example | When to use |
|----------|-------------|---------|-------------|
| 1 (highest) | LAN private (same subnet) | 192.168.10.x | Always preferred |
| 2 | Routable via LAN gateway (other subnet) | 192.0.2.x | LAN routing through gateway |
| 3 | Public internet IP | 85.x.x.x | When LAN paths unavailable |
| 4 (lowest) | Mobile/CGNAT | 100.64.x.x | Last resort only |

Mobile data addresses (CGNAT 100.64.x.x, carrier-assigned 192.0.0.x, etc.) should only be used as a fallback when all LAN and internet paths are unavailable. They consume metered bandwidth and are often unreliable.

**Non-routable addresses** are filtered entirely: IANA Protocol Assignments (192.0.0.0/24), documentation blocks (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24), link-local (169.254.0.0/16), multicast (224.0.0.0/4), and reserved (240.0.0.0/4).

#### 2.4.4b Relay Route Learning (V3 — ACK-based, no timer expiry)

Relay routes are part of the Distance-Vector routing table (see Section 2.2.3). Each relay route is a regular route entry with `type: relay` and a `nextHop` pointing to the relay peer.

Relay routes are **learned, not guessed**:

1. Node sends PING to peer on all known addresses.
2. No PONG within ACK timeout → peer is directly unreachable.
3. Node queries known online peers: "Can you reach Peer X?" (Reachability Probe).
4. Peer Z responds: "Yes, Peer X sent me a PONG" → Route stored: destination=X, nextHop=Z, type=relay, cost=(link_to_Z + Z's_link_to_X).
5. Subsequent messages to Peer X use this route — no trial-and-error.
6. Additionally, relay routes are learned automatically when a RELAY_ACK(delivered=true) is received, and via Distance-Vector route propagation from neighbors.

**No timer-based expiry (V3):** Relay routes remain valid as long as DELIVERY_RECEIPTs confirm them. A route is marked DOWN only after **3 consecutive RUDP Light timeouts** (no DELIVERY_RECEIPT). This replaces the previous 10-minute timer expiry which caused unnecessary route loss and rediscovery.

**Learned relay route validation (V3.1.35):** Learned relay routes (stored in `peer.relayViaNodeId`) are only used if the relay node is a confirmed peer in the current session (live UDP contact). Stale relay entries from disk-loaded routing tables are cleared immediately, causing the cascade to fall through to DV routes or default gateway without delay. `confirmRoute()` for DV routing is only called for DIRECT-delivered DELIVERY_RECEIPTs (not relay-delivered from=0.0.0.0), preventing false "proven" route marking that would skip the relay cascade.

**Route-Down propagation:** When a relay route fails (3x timeout), the node sends a Poison Reverse (ROUTE_UPDATE with cost=65535) to all neighbors. Neighbors remove or update their routes accordingly and may advertise alternative routes.

**On network change:** All relay routes are reset (network topology may have changed fundamentally). Direct routes are re-probed via discovery burst.

**Example:** Alice cannot reach Handy directly (AP isolation). Bootstrap can reach Handy via LAN gateway. Alice's routing table: `{destination: Handy, nextHop: Bootstrap, hopCount: 2, cost: 6 (LAN:1 + Public:5), type: relay}`. All messages to Handy flow through Bootstrap — Alice KNOWS this proactively, no reactive searching needed.

#### 2.4.5 IPv6 Advantage

With IPv6, every device receives a globally unique public address. No NAT, no hole punching needed — direct connection always works. As IPv6 adoption grows, NAT traversal becomes less relevant. Cleona fully supports dual-stack (IPv4 + IPv6) operation.

### 2.5 Bootstrap Node (Early Network Phase)

#### 2.5.1 Concept

The Bootstrap Node is an optional accelerator for the early network phase when few users exist and physical encounters between users are rare. **It is not a special server — it is a normal Cleona node running headless on a VPS, using the exact same code and protocol as every other node.** The only difference is that it is guaranteed to be online 24/7.

Every Cleona node is capable of performing all the functions that the bootstrap node provides. In a mature network with enough active users, the bootstrap node becomes redundant and can be decommissioned.

#### 2.5.2 Functions

Because the bootstrap node runs the same code as every other node, it provides the same services that any online node provides:

1. **Peer Discovery:** New nodes that have no peers yet can contact the bootstrap node to receive an initial peer list. Any online node can provide the same service to a new peer.

2. **ID-to-IP Resolution:** The bootstrap node knows all nodes it has encountered and can resolve Node-IDs to current IP addresses. Every other node can do this for the peers it knows.

3. **Offline Message Relay:** When a message is sent to an offline peer, erasure-coded fragments are stored on the nearest DHT nodes. The bootstrap node participates in this like any other node. Every online node stores fragments for offline peers as part of normal DHT operation.

4. **NAT Traversal Assistance:** Reports the connecting node's public IP (decentralized STUN). Any peer can provide this.

#### 2.5.3 Protocol

The bootstrap node uses **the same Protobuf MessageEnvelope protocol** as all other nodes. There is no separate protocol, no JSON API, no special treatment. A node connecting to the bootstrap node does exactly the same thing as connecting to any other peer.

**NAT probe safety:** The bootstrap must not respond to `DHT_PONG` messages with further responses, as this would create an amplification loop (each packet triggers a response that triggers another response, infinitely).

#### 2.5.4 Deployment

The bootstrap node is deployed as a headless Dart binary (`dart compile exe`) running on an internet-reachable host (currently a Hyper-V VM in the reference deployment, behind an IPv4 DNAT chain and a native IPv6 path per §18.3.1). It runs on a channel-specific port (Live=8080, Beta=8081 — see Section 17.5.4). **No node has a hardcoded bootstrap address.** New nodes learn the bootstrap address exclusively through social contact (QR code / ContactSeed URI) — the scanned seed peers typically include the bootstrap if the inviting node knows it.

**Not a dependency:** The bootstrap accelerates early network growth but is never required. Nodes that already know peers from previous sessions or from LAN discovery operate independently. The bootstrap can be offline without affecting existing connections.

**Process management:** The bootstrap runs as a systemd service (`cleona-bootstrap.service`, enabled, `Restart=on-failure`) for automatic startup after boot. `loginctl enable-linger` ensures the service runs without an active login session. The headless binary wraps execution in `runZonedGuarded` for proper async error handling — without it, unhandled async exceptions crash the process silently.

#### 2.5.5 Decommission Criteria

The bootstrap node should be decommissioned when the network is self-sustaining. The criterion is:

**At least 10 nodes must be reliably online simultaneously over a sustained period (e.g., 30 days without any moment where the count drops below 10).**

This ensures that new users can always find peers, offline messages are always stored, and no single point of dependency remains.

Network health is monitored via the Network Statistics Dashboard (see Chapter 11) available on every node.

### 2.6 Complete Discovery Chain

When a Cleona node needs to find peers, it tries these methods in priority order:

1. **Stored peers from previous sessions.** On app restart, the node immediately tries to contact previously known peers. This is the fastest path and works even if all other discovery methods are unavailable.

2. **Passive Mesh Discovery:** IPv4 Local Broadcast (port 41338) + IPv6 Multicast (ff02::1) on local network. Runs automatically in the background with no user action needed. On network change, discovery triggers fast bursts.

3. **Internet sync with already-known peers:** Exchange updated peer lists with existing contacts over the internet. This propagates new peer information transitively without physical meetings.

4. **Active Mesh Discovery:** NFC tap, QR code scan, or imported .clp peer list file (received via email, messenger, etc.).

5. **Saved bootstrap seeds (`bootstrap_seeds.json`):** Read-only file loaded as fallback when the routing table has ≤3 peers after startup. Populated externally — e.g. by deployment tooling for headless nodes and emulator setups. Not written by the daemon. ContactSeed QR scans persist their peers via the routing table (`isProtectedSeed=true`), not via this file.

6. **Bootstrap node (if known):** Not hardcoded — learned via ContactSeed QR. Treated as a normal peer using the same protocol. Automatically decommissioned when the network is self-sustaining.

7. **Manual peer entry:** Direct IP input as technical last resort.

In practice, most users install Cleona because someone recommended it — and that person is already in their physical proximity, triggering Mesh Discovery automatically at step 2.

### 2.7 Network Change Detection

When a device switches networks (e.g., WiFi to cellular, new WLAN joined, VPN toggled), the node's local IP address changes. The previously cached public IP from NAT traversal becomes invalid, and peers in the old network are no longer reachable. Cleona detects these changes and automatically re-establishes network presence.

#### 2.7.1 Detection Mechanisms

Three complementary detection strategies ensure network changes are caught on all platforms:

**Flutter GUI (connectivity_plus + AppLifecycleListener):** The `connectivity_plus` package provides an event stream that fires on any connectivity change (WiFi↔Cellular switch, connection lost/restored, new WLAN joined). Additionally, an `AppLifecycleListener` triggers on app resume from background — the network may have changed while the app was suspended. Both events are handled in `main.dart` and forwarded to all active CleonaService instances via `onNetworkChanged()`.

**Headless daemon (IP polling fallback):** The headless entry point (`headless.dart`) cannot use Flutter packages. Instead, `NetworkChangeHandler` polls `NetworkInterface.list()` every 10 seconds and compares the current set of local IP addresses against the last known set. When the IP set changes, the callback fires. This is lightweight and works on any Dart platform.

**Public IP polling (headless):** Headless nodes (especially bootstrap servers behind NAT) may keep the same local IP while their public IP changes (ISP reassignment, VPN reconnect). `NetworkChangeHandler` polls `https://api.ipify.org` every 60 seconds to detect public IP changes. On change, `onNetworkChanged()` is triggered, which resets NAT state and broadcasts the new address to all peers. The first poll establishes a baseline; errors are silently logged (non-fatal).

**App resume handling:** Even when local IPs have not changed (e.g., the device stayed on the same WiFi but the app was suspended for minutes), a connectivity event still triggers a lightweight re-discovery burst. This catches peers that appeared on the network while the app was in the background.

#### 2.7.2 Recovery Actions on Network Change

When a network change is detected, `CleonaNode.onNetworkChanged()` executes the following sequence:

1. **Reset NAT traversal:** Clear all cached public IP observations. The old public IP is invalid after a network switch. NAT type classification resets to `unknown`. (See Section 2.4.)
2. **Reset relay routes:** All relay routes in the routing table are cleared (network topology may have changed fundamentally). Direct routes are re-probed.
3. **Trigger discovery burst:** Both `LocalDiscovery` and `MulticastDiscovery` send a 3-packet burst at 2-second intervals. This rapidly discovers peers on the new network.
4. **Ping all known peers:** Send DHT PING to all peers in the routing table. This announces our new address and lets peers update their routing tables.
5. **Re-bootstrap Kademlia DHT:** Run a full Kademlia bootstrap to re-announce our presence in DHT space.
6. **Broadcast route update:** Send ROUTE_UPDATE with our new addresses to all known peers, ensuring immediate route propagation.
7. **Poll mailbox:** CleonaService triggers an immediate mailbox poll (PEER_RETRIEVE) to retrieve any messages that arrived while the network was unavailable.

**Keepalive failure detection (mobile):** `UdpKeepalive` tracks consecutive rounds where ALL keepalive peers failed to respond. After 3 consecutive complete failures (~75 seconds), `onAllPeersFailed` triggers a full `onNetworkChanged()` cycle. This provides a 5-minute-cooldown safety net for mobile devices that lose connectivity without an explicit network change event (e.g., carrier handoff, tunnel collapse). The counter resets as soon as any keepalive succeeds.

**Implementation:** `NetworkChangeHandler` (`network_change_handler.dart`) encapsulates the detection logic. `CleonaNode.onNetworkChanged()` handles the recovery actions. `CleonaService.onNetworkChanged()` delegates to the node and triggers mailbox polling.

### 2.8 Data Compression

All Cleona protocol payloads are compressed before encryption using zstd (Zstandard). The compression order is critical: compress first, then encrypt. Encrypted data appears random and cannot be compressed effectively.

Compression applies to: all Protobuf message payloads (text messages, metadata, protocol messages), peer list data during exchange (1,000 peers compress from ~100 KB to ~15–20 KB), and DHT routing information.

A compression flag in the message header indicates whether the payload is compressed: `compression: NONE | ZSTD`. Recipients check this flag before attempting decompression. Older clients that do not support compression can still communicate (graceful degradation).

**KEM-encrypted envelopes (V3.1.7):** The `compression` field on KEM-encrypted envelopes describes the **plaintext** (pre-encryption), NOT the ciphertext. Node-level decompression in `_onEnvelopeReceived` skips envelopes with a KEM header (`hasKemHeader()`). Decompression occurs in the service layer after decryption. Attempting to decompress KEM ciphertext as if it were zstd-compressed data was the root cause of image decrypt failures (crypto_aead_aes256gcm_decrypt error).

**Text encoding:** All text content must use `utf8.encode()` / `utf8.decode()` for serialization — never `.codeUnits` / `String.fromCharCodes()`, which break non-ASCII characters (emojis, umlauts, CJK).

### 2.9 Lightweight RUDP & ACK-Driven Fragment Delivery

UDP is fire-and-forget — a sent packet may never arrive, and the sender has no way of knowing. For a reliable messenger, this is unacceptable. Cleona uses a lightweight Reliable UDP (RUDP) layer that provides delivery feedback without the overhead of TCP.

#### 2.9.1 Design Principle

The RUDP layer does NOT retransmit until acknowledged (like TCP). Instead, it provides a **delivery receipt** per fragment: the receiving peer sends a short ACK ("fragment stored"). If no ACK arrives within a timeout, the sender knows the peer is unreachable and can act on that information — send to an alternative peer, mark the peer as unreachable, or trigger relay.

This is fundamentally different from TCP reliability: TCP retransmits blindly until timeout (causing cascading delays). RUDP gives the sender **agency** — the sender decides what to do based on the feedback.

#### 2.9.2 ACK Mechanism

```
Sender                    Peer
  |                         |
  |--- FRAGMENT_STORE ----->|
  |                         |
  |<-- FRAGMENT_STORE_ACK --|
  |    (stored, index N)    |
```

**ACK format:** A minimal response containing the message ID and fragment index. No payload — just confirmation that the fragment was received and stored.

**Timeout:** Based on the observed Round-Trip Time (RTT) to the specific peer. Default: `2 × RTT + 50ms` jitter margin. For peers with no RTT history: 1 second initial timeout. RTT is updated with each successful ACK using exponential moving average.

**No retransmit to same peer:** If the ACK times out, the fragment is NOT resent to the same peer. Instead, an alternative peer is selected (see 2.9.3). This avoids the TCP anti-pattern of cascading retransmit timeouts to an unreachable peer.

#### 2.9.3 Intelligent Fragment Distribution

Instead of broadcasting all N=10 fragments to all peers (the old approach), fragments are distributed intelligently with ACK feedback:

**Step 1 — Initial distribution:**
The sender selects N target peers (sorted by RTT / reliability score) and sends one fragment to each peer.

**Step 2 — ACK collection:**
For each sent fragment, the sender waits for an ACK within the RTT-based timeout.

**Step 3 — Redistribution on failure:**
For each fragment where no ACK arrives:
1. Mark the peer as unreachable (update address score).
2. Select an alternative peer from the known peer list.
3. Send the fragment to the alternative peer.
4. Inform other "alive" peers that the failed peer is unreachable from this sender's perspective.

**Step 4 — Relay for unreachable peers:**
If Peer Z reports that it CAN reach Peer X (who is unreachable for the sender), Peer Z automatically serves as relay. Fragments stored on Z are forwarded to X when Z has connectivity to X. This happens automatically — no explicit relay request needed.

**Step 5 — Completion check:**
Once N ACKs are collected (from original or alternative peers), the message is in state **STORED_IN_NETWORK** — it is fully reconstructable from any K=7 of the 10 distributed fragments.

#### 2.9.4 Fragment Replication Limit

**Maximum 5 copies per fragment** in the network. This prevents fragment flooding in small networks where the sender might otherwise send the same fragment to every available peer. The sender tracks the ACK count per fragment and stops distributing once 5 ACKs are received for any single fragment.

In the test network (3-5 nodes), this means: each fragment exists at most on every node, but the limit prevents runaway replication as the network grows.

#### 2.9.5 SendQueue for Offline Scenarios

If NO peer is reachable (all ACKs timeout), the sender is effectively offline. In this case:
1. All pending fragments are held in a persistent **SendQueue**.
2. The node triggers network recovery (see Section 2.7 — NAT reset, fast discovery burst, DHT re-bootstrap).
3. As peers become reachable again, the SendQueue is drained automatically, resuming fragment distribution with ACK feedback.
4. The SendQueue is persisted to disk so fragments survive app restarts.

#### 2.9.6 Message Status Lifecycle

Every message has a delivery status visible to the sender:

```
QUEUED → SENT → STORED_IN_NETWORK → DELIVERED → READ
```

| Status | Meaning | Trigger |
|--------|---------|---------|
| QUEUED | In SendQueue, no peer reachable | No ACKs, node offline |
| SENT | Fragments dispatched, ACKs pending | First fragment sent |
| STORED_IN_NETWORK | ≥N ACKs received, message reconstructable from network | N-th ACK arrives |
| DELIVERED | Recipient has reassembled the complete message | Recipient sends DELIVERY_RECEIPT |
| READ | Recipient has opened/viewed the message | Recipient sends READ_RECEIPT |

**QUEUED → SENT:** Automatic when any peer becomes reachable.
**SENT → STORED_IN_NETWORK:** Automatic when enough ACKs confirm network storage.
**STORED_IN_NETWORK → DELIVERED:** When the recipient reassembles the message from K=7 fragments and sends a DELIVERY_RECEIPT back to the sender.
**DELIVERED → READ:** When the recipient views the message in the UI and sends a READ_RECEIPT (optional, privacy-configurable).

#### 2.9.7 Network Fragment Awareness

The network collectively knows where each fragment is stored. This is achieved through:

1. **Sender tracking:** The sender maintains a fragment distribution map: `{messageId → {fragmentIndex → [peersThatACKed]}}`. This map is persisted locally.

2. **Relay peer awareness:** Each relay peer that stores a fragment knows the mailbox owner (via PK → mailbox ID mapping). When the owner becomes reachable, the relay pushes the fragment proactively (see Section 3.5).

3. **Peer unreachability reports:** When a sender discovers a peer is unreachable, it informs other peers. This allows the network to route around failures — if Peer A can't reach Peer X but Peer B can, Peer B relays for Peer A.

#### 2.9.8 Small Network Considerations (Test Environment)

With only 3-5 test nodes, the N=10 fragment count exceeds the peer count. Adaptation:

- **Fragment distribution wraps around:** With 3 peers, fragments are distributed round-robin: Peer1 gets fragments 0,3,6,9; Peer2 gets 1,4,7; Peer3 gets 2,5,8. Each peer holds multiple fragments.
- **The 5-copy limit per fragment** ensures no single fragment floods all peers.
- **K=7 reconstruction** still works because any peer going offline loses at most ceil(10/3) = 4 fragments, leaving 6+ fragments on the remaining 2 peers — enough for K=7 if the sender also retains fragments locally.
- **Sender retains all fragments** until DELIVERED status, serving as ultimate fallback for reconstruction.

**Physical host awareness (multi-identity constraint):** When multiple identities run on the same physical device (see Section 5.2), they appear as independent DHT nodes with different Node-IDs but share the same physical availability. If the device goes offline, all identities on it are simultaneously unreachable. The fragment distributor groups target peers by IP address and selects at most one peer per IP for fragment storage. This prevents placing multiple fragments of the same message on the same physical host, which would defeat the redundancy purpose of erasure coding. The same constraint applies to Store-and-Forward target selection (Section 3.3.7).

#### 2.9.9 TTL / Hop Limit (V3)

Like IPv4 TTL / IPv6 Hop Limit. Prevents routing loops from consuming network resources indefinitely.

- **Start value:** 64 (set by the sender on every relayed message)
- **Per relay hop:** Decremented by exactly 1 (regardless of link type or cost)
- **At TTL = 0:** Packet is dropped silently, NOT forwarded
- **No error message:** Sender learns about the loss via RUDP Light timeout (no ICMP equivalent needed)

TTL is **independent of cost.** Cost determines route selection (which path); TTL prevents loops (how far a packet can travel). The `ttl` field in `RelayForward` replaces/supplements the existing `maxHops` field.

**Interaction with visited_nodes:** TTL and `visited_nodes` are complementary. `visited_nodes` detects loops early (exact, but memory-intensive). TTL is the hard fallback that kills packets even if `visited_nodes` is buggy or incomplete.

#### 2.9.10 App-Level UDP Fragmentation (V3)

Payloads >1200 bytes (PQ keys ~2KB, media announcements, etc.) would exceed the UDP MTU. OS-level IP fragmentation is unreliable behind NAT. Cleona fragments at the application level:

1. Payload is split into chunks of max 1200 bytes
2. Each chunk gets an 8-byte header: `[4B "CFRA" magic][2B fragmentId][1B index][1B totalFragments]`
3. Each fragment is sent individually via UDP
4. Each fragment is tracked by RUDP Light (individual DELIVERY_RECEIPT)
5. On loss: only the missing fragment is re-requested via Fragment-NACK
6. Receiver reassembles after all fragments arrive

**Fragment-NACK (V3.1.7, debounce-fix V3.1.54):** Active retransmission of missing fragments without waiting for DELIVERY_RECEIPT timeout:

1. The NACK timer is (re-)armed on EVERY received fragment — debounced, so it fires 500ms after the LAST incoming fragment, independent of index position. (V3.1.54 fix: previously the timer only armed on `last-index || near-complete`, which missed burst-loss scenarios where the last fragment AND several middle fragments were lost — the buffer then expired silently with `nacks=0`.)
2. When the timer fires, the receiver sends a NACK: `[4B "CFNK"][2B fragmentId][1B count][missing indices...]`
3. The sender caches all sent fragments (30s TTL) and resends the requested fragments on NACK
4. Maximum 3 NACKs per fragment group (prevents infinite retry loops). Timer is cancelled on complete reassembly.
5. Fragment-NACK does NOT affect peer reachability detection — only DELIVERY_RECEIPT determines route health

**Distinction from Reed-Solomon:** App-level fragmentation is for sending large payloads to ONLINE peers. Reed-Solomon is for storing messages for OFFLINE peers (with 1.43x redundancy for node failure tolerance).

---

## 3. Erasure Coding & Message Delivery

### 3.1 Concept

Inspired by RAID-5 but significantly more resilient, Cleona uses Reed-Solomon erasure coding for two purposes:

1. **Offline message delivery:** When the recipient is offline, fragments are distributed to DHT peers near the recipient's mailbox. When the recipient comes online and queries its DHT neighbors, 7 of 10 fragments suffice to reconstruct the message — even if 3 storage nodes are offline.

2. **Recovery backup:** Fragments serve as a distributed backup of chat messages. If the chat partner (who holds the full message) is offline during recovery, the fragments on DHT peers can reconstruct the message. This supports the design principle "Contacts = your backup."

**Important:** Reed-Solomon is NOT for compensating network packet loss during transmission. Online delivery uses RUDP Light (see Section 2.9) with per-message DELIVERY_RECEIPT. Reed-Solomon is exclusively for OFFLINE scenarios and long-term backup.

This is fundamentally different from simple replication (storing complete copies), which requires N times the storage. Erasure coding achieves the same reliability at only N/K times the storage — a 1.43x overhead versus 10x for replication.

### 3.2 Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| N (total fragments) | 10 | Distributed across 10 nearest DHT peers |
| K (required for reconstruction) | 7 | Tolerates 3 peer failures |
| Redundancy factor | 1.43x | Efficient use of relay storage |
| Fragment retention | 7 days | Balance between backup reliability and storage burden |

**Fragment retention (V3):** Fragments are NOT deleted immediately after successful delivery. They remain on the storage nodes for **7 days** as recovery backup. Deletion occurs when: (1) Both chat partners have deleted/archived the message, OR (2) the fragment is older than 7 days. For messages older than 7 days, recovery relies on the contact partner (who has the complete chat history) being online — consistent with "Contacts = your backup."

### 3.3 Message Flow

#### 3.3.1 Three-Layer Delivery Pattern

Every non-ephemeral message uses three complementary delivery mechanisms:

**Layer 1 — Route-based delivery (V3):** The message is sent as a whole (not fragmented) to the recipient via the cheapest route in the Distance-Vector routing table (see Section 2.2.3). This may be direct (UDP to peer's address) or via relay (UDP to nextHop who forwards to destination). The routing table knows proactively which path to use — no reactive searching needed. The sender waits for a DELIVERY_RECEIPT (RUDP Light) to confirm delivery. On timeout, the next cheapest route is tried. If no route exists, the Default-Gateway is used (see Section 2.4.3).

**Layer 2 — Store-and-Forward on mutual peers:** If direct/relay delivery fails (no ACK — recipient is offline), the complete message is stored on **mutual peers** — nodes that both sender and recipient know and that are currently online. This enables the recipient to retrieve missed messages when they come back online (see Section 3.3.7). Messages are stored whole, not fragmented. A 2nd or 3rd identity on the same physical node is NOT a valid Store-and-Forward target (if the node is offline, all its identities are offline).

**Layer 3 — Reed-Solomon erasure-coded backup:** Additionally, the message is split into N=10 fragments and distributed across DHT peers using ACK-driven delivery (see Section 2.9). This protects against **long-term node failures** — if 3 of 10 storage nodes go permanently offline, the message can still be reconstructed from the remaining 7. Reed-Solomon compensates for unavailable nodes, NOT for network packet loss.

**Why three layers?** Each layer addresses a different failure mode:
- Layer 1: Recipient is online but on a different network path (relay needed)
- Layer 2: Recipient is temporarily offline (hours), comes back and polls
- Layer 3: Storage nodes themselves fail permanently (days/weeks)

**Important distinction:** Short messages (TEXT, CONTACT_REQUEST, etc.) are always stored and relayed as complete messages (Layer 1 + 2). Reed-Solomon fragmentation (Layer 3) runs in parallel as a background backup mechanism. The recipient typically receives the message via Layer 1 or 2 long before Layer 3 would be needed.

**Why always backup?** UDP is connectionless — `sendEnvelope()` returns success even if the recipient is unreachable. The sender considers a peer "online" if it was seen within the last 120 seconds, but the peer could have gone offline 1 second after its last heartbeat. Without backup, such messages would be silently lost.

**Best-effort direct send:** Messages are sent directly to all recipients regardless of their `lastSeen` status. In groups, members may be known only through the group and have no direct contact history, making their `lastSeen` unreliable. Direct send + erasure-coded backup always run in parallel.

**Ephemeral messages** skip the erasure-coded backup. This includes:
- **Typing indicators** and **read receipts** — transient, not worth the storage overhead.
- **Delivery receipts** — confirmation that a message was received; transient.

**Note:** With Per-Message KEM encryption (see Section 4.3), there are no session-establishment messages. Every message is self-contained and can be delivered offline without prior handshake.

**Non-ephemeral protocol messages** that MUST use erasure-coded backup:
- **RESTORE_BROADCAST** and **RESTORE_RESPONSE** — recovery depends on reliable delivery.
- **CHAT_CONFIG_UPDATE** and **CHAT_CONFIG_RESPONSE** — settings changes must not be lost.
- **IDENTITY_DELETED** — contacts must learn about deletions.
- **PROFILE_UPDATE** — profile changes should persist.

**Short messages skip Reed-Solomon fragmentation:** Text messages and other short payloads (typically < 4 KB encrypted) are NOT split into N=10 erasure-coded fragments. Instead, they use Layer 1 (direct/relay delivery) and Layer 2 (Store-and-Forward as whole message on mutual peers) exclusively. Reed-Solomon fragmentation (Layer 3) is reserved for larger payloads where the overhead of N=10 fragments is justified — e.g., media transfers, large group config updates, and restore data. The threshold for erasure coding is configurable; the default is messages exceeding the typical single-UDP-packet size after encryption (~1200 bytes). Below this threshold, Store-and-Forward on mutual peers provides sufficient offline redundancy without the 10x fragment overhead.

#### 3.3.2 Recipient Online (Direct Delivery)

When the recipient is online, a direct P2P connection delivers the message in real-time via UDP. The message is encrypted with Per-Message KEM (see Section 4.3). Simultaneously, the erasure-coded backup is stored (see 3.3.3). The recipient receives the message instantly via the direct path; the backup fragments are available as fallback but typically not needed.

**Route-based delivery (V3):** `sendEnvelope()` sends via the cheapest route from the routing table (see Section 2.4.3). Within a route, the nextHop's best address is used (prioritized by type: LAN > Public > Mobile).

#### 3.3.3 Recipient Offline (Erasure Coded Delivery)

When the recipient is offline (or as backup for online delivery), the following sequence occurs:

1. Sender encrypts the message with Per-Message KEM (fresh ephemeral key, see Section 4.3).
2. The encrypted message is compressed with zstd.
3. The compressed, encrypted payload is split into N=10 fragments via Reed-Solomon erasure coding.
4. The sender selects N target peers (sorted by reliability score / RTT) and distributes fragments using the **ACK-driven delivery** mechanism (see Section 2.9). Each fragment is sent to one peer at a time; on ACK timeout, the fragment is redirected to an alternative peer. This replaces the old broadcast approach where all fragments were sent to all peers simultaneously.
5. Each relay peer stores its fragment locally (within its relay storage budget) and responds with a FRAGMENT_STORE_ACK.
6. The sender tracks which peer holds which fragment. Once all N=10 fragments are ACKed (by original or fallback peers), the message status transitions to STORED_IN_NETWORK. If no peers are reachable, fragments are held in the persistent SendQueue (see Section 2.9.5).
7. When the recipient comes online, their node polls the mailbox once at startup (see 3.3.6). During normal operation, relay nodes push fragments proactively (see 3.5).
8. With K=7 or more fragments collected, the original message is reconstructed via Reed-Solomon decoding.
9. The message is decompressed and decrypted using the recipient's private key and the embedded ephemeral key material.
10. Relay peers are notified of successful delivery and delete their fragments (FRAGMENT_DELETE).

**Envelope cloning:** When the same message envelope is used for both direct delivery and erasure-coded backup (e.g., in `sendContactRequest()`), the backup envelope must be a fresh clone. Reusing the same object causes signature corruption because the second signing operation covers data that includes the first signature.

#### 3.3.4 Message Deduplication

Because of the dual-delivery pattern, a recipient may receive the same message twice: once via direct delivery and once via erasure-coded reconstruction. Deduplication operates at two levels:

1. **Persisted messages (`_messages`):** Checked before KEM decryption. Messages already stored in the database from previous sessions are rejected immediately. This catches messages that reappear in the mailbox (e.g., fragments not yet cleaned up by `FRAGMENT_DELETE`).
2. **In-memory set (`_processedMessageIds`):** Marks messages as processed **after** successful decryption and routing, not before.

This two-layer dedup prevents duplicate message processing (e.g., same message arriving via direct delivery and via erasure-coded reconstruction).

#### 3.3.5 Mailbox ID Computation & PK Lookup Chain

The mailbox ID is computed as `SHA-256("mailbox" + ed25519_public_key)`. For the sender to compute the recipient's mailbox ID, they need the recipient's Ed25519 public key. The sender resolves this through a three-layer lookup chain:

1. **Routing Table (PeerInfo):** The recipient's `ed25519PublicKey` may be stored in their PeerInfo entry in the KBucket routing table. KBucket's `addPeer()` preserves known public keys when updating existing entries to prevent loss during LRU updates.
2. **ContactManager (persistent):** If the routing table entry lacks the PK, the sender queries the ContactManager for accepted contact requests from the recipient. Contact records persistently store the sender's Ed25519 PK from the original contact request.
3. **NodeId fallback (last resort):** If neither source has the PK, a fallback mailbox ID is computed as `SHA-256("mailbox-nid" + node_id)`. This uses a different domain separator to avoid collisions. The recipient also polls this fallback mailbox ID alongside the primary one.

**Important:** The PK lookup chain is critical for correct offline delivery. If sender and recipient compute different mailbox IDs, fragments are stored under the wrong address. To handle this edge case, the recipient's mailbox polling checks **both** the primary (PK-based) and fallback (nodeId-based) mailbox IDs.

#### 3.3.5a PK Propagation

To ensure senders can compute the correct (PK-based) mailbox ID, each node's Ed25519 public key is propagated through the network:

1. **Self-registration:** Each node registers itself in its own PeerManager at startup with its `ed25519PublicKey`.
2. **PeerInfo Protobuf:** The `PeerInfo` protobuf message includes the `ed25519_public_key` field. Both `toProto()` and `fromProto()` serialize/deserialize this field.
3. **PeerExchange:** After Kademlia bootstrap completes, the node initiates PeerExchange with all known peers, propagating its PK.
4. **FIND_NODE enrichment:** When responding to DHT FIND_NODE queries, the node enriches returned PeerInfos with PKs from the PeerManager (which has PKs from PeerExchange).
5. **PK preservation:** Both KBucket and PeerManager preserve existing `ed25519PublicKey` values when updating PeerInfo entries with newer timestamps but missing PKs.
6. **Stale key recovery:** When a node restarts with new keys, cached Ed25519 keys in `routing_table.json` and `peer_history.json` become stale, causing signature verification failures. The fix: on signature mismatch, the stale key is cleared from PeerInfo instead of rejecting the message, allowing the correct key to be learned from subsequent exchanges. The same lenient policy applies to ML-DSA keys.

#### 3.3.6 Mailbox: Push-First with Startup Poll

Message delivery is **push-first**: relay nodes that store a fragment immediately forward it to the mailbox owner if they know the owner's address (see Section 3.5, "Proactive fragment push"). This provides sub-second delivery latency for most messages. Mailbox polling is only used at startup and as a fallback.

**Startup poll:** When a node comes online, it polls its mailbox once (5 seconds after startup) to collect any fragments that accumulated while it was offline. The node sends FRAGMENT_RETRIEVE requests to **all recently-confirmed peers** (seen within the last 10 minutes), not just the K closest peers in XOR space. In small networks, XOR-closest peers may be stale or unreachable while actual fragment holders (e.g. the Bootstrap node) rank far from the mailbox ID. Querying all reachable peers ensures fragments are always found. If no recently-confirmed peers exist, the node falls back to querying the 10 XOR-closest peers. Each peer responds with any stored fragments for that mailbox (reusing the FRAGMENT_STORE message type as response). FRAGMENT_RETRIEVE uses multi-address parallel delivery (see Section 2.4.3). Simultaneously, PEER_RETRIEVE (type 116) is sent to all recently-confirmed peers to collect Store-and-Forward whole messages (see Section 3.3.7).

**Aggressive polling (after restore):** 10 polls at 3-second intervals immediately after a Restore Broadcast, ensuring rapid recovery on LAN networks.

**During normal operation:** No periodic polling. Fragments are pushed by relay nodes immediately upon storage. When a pushed fragment arrives, the node checks locally whether K=7 or more fragments for any message ID are available and triggers Reed-Solomon reconstruction.

**Fragment aging:** Incomplete fragment sets (< K fragments) are evicted after 10 minutes. Without this, partial fragments from lost messages accumulate indefinitely in memory.

**Cleanup:** After successful reconstruction, FRAGMENT_DELETE messages are sent to all relay peers for both mailbox IDs to free their storage.

#### 3.3.7 Store-and-Forward on Mutual Peers

When direct delivery and relay delivery both fail (recipient is offline), the complete message is stored on **mutual peers** — nodes known to both sender and recipient that are currently online. This is distinct from Reed-Solomon backup: the message is stored whole (not fragmented), and the storage target is chosen based on mutual knowledge (not DHT distance).

**Mutual peer selection (V3.1.36):** The sender computes the set of peers that both sender and recipient are likely to know, based on two sources: (1) **shared contacts** — accepted contacts are bidirectional, so both sender and recipient know them; (2) **shared group members** — groups where the recipient is a member provide additional mutual peers. From this set, only currently reachable (CONFIRMED) peers are selected. Up to 3 mutual peers are chosen; if fewer than 3 mutual peers are available, fallback to any confirmed peer. The `getMutualPeerIds` callback bridges the service layer (contacts, groups) to the node layer (S&F storage).

**Store protocol:**
```
Bob stores message on Bootstrap (direct):

  Bob                        Bootstrap
   |--- MESSAGE_STORE(msg) --->|
   |<-- MESSAGE_STORE_ACK -----|

Bob stores on Handy (via relay through Bootstrap):

  Bob                  Bootstrap              Handy
   |--- RELAY(STORE) --->|--- MESSAGE_STORE --->|
   |<-- RELAY(ACK) ------|<-- STORE_ACK --------|
```

**Retrieval at startup:** When the recipient comes online, the startup poll (Section 3.3.6) is extended to also query mutual peers for stored whole messages — not just DHT peers for erasure-coded fragments. The poll must work through relay chains: if a mutual peer (e.g., Handy) is only reachable via Bootstrap, the poll and response are relayed transparently.

**S&F push wraps in RELAY_FORWARD (V3.1.7):** When a storing peer pushes a stored envelope to the newly-online recipient, it wraps the envelope in a RELAY_FORWARD message. Without wrapping, the recipient would see `senderId=OriginalSender` arriving from the storing peer's IP, causing a false DV neighbor registration (recipient would think the original sender is a direct neighbor at the storing peer's IP).

**S&F proactive push:** When a storing peer receives a PONG or DELIVERY_RECEIPT from the recipient (indicating the recipient is back online), it immediately pushes all stored S&F messages to the recipient — wrapped in RELAY_FORWARD. This mirrors the proactive fragment push mechanism (Section 3.5) but for whole messages instead of erasure-coded fragments. The startup poll (PEER_RETRIEVE, see Section 3.3.6) serves as fallback when the proactive push does not trigger.

**S&F push count limit (V3.1.35):** Each stored message is pushed a maximum of 3 times (`maxPushCount=3`) with a minimum interval of 300 seconds between pushes. After 3 pushes, the message remains in the store for PEER_RETRIEVE retrieval and TTL expiry (7 days) but is no longer proactively pushed. This prevents network flooding from accumulated relay-backup copies that would otherwise be re-pushed indefinitely.

**Protocol messages:**

| Type | Name | Purpose |
|------|------|---------|
| 114 | PEER_STORE | Store whole message on peer for offline recipient |
| 115 | PEER_STORE_ACK | Confirmation of successful storage |
| 116 | PEER_RETRIEVE | Request stored messages at startup |
| 117 | PEER_RETRIEVE_RESPONSE | Response with stored messages |

**Storage budget per peer:** Max 50 messages per recipient, max 300 KB per envelope, TTL 7 days.

**Relationship to Reed-Solomon:** Store-and-Forward (Layer 2) provides fast retrieval of recent messages from known peers. Reed-Solomon (Layer 3) provides long-term redundancy against permanent node failures. Both run in parallel; the recipient typically receives the message via Store-and-Forward first.

**Identity constraint:** A 2nd or 3rd identity on the same physical node as the recipient is NOT a valid Store-and-Forward target. If the device is offline, all identities on that device are offline.

### 3.4 Two-Stage Media Delivery

Large media files (images, videos, documents) use a two-stage delivery process to protect recipient bandwidth and storage. Media is exchanged exclusively between sender and recipient (or group members) — never relayed through third-party nodes in unencrypted form.

#### 3.4.1 Stage 1: Metadata Announcement

When a user sends a large file, only a small metadata message is transmitted initially via the normal delivery path (direct or erasure coded). This metadata message contains: the filename, file size in bytes, MIME type, a compressed thumbnail (max 100 KB), duration (for audio/video), and the SHA-256 content hash for integrity verification.

#### 3.4.2 Stage 2: Confirmed Transfer

The actual file transfer begins only after the recipient taps "Download." In group chats, each member decides individually whether to download. The full file transfer uses direct P2P connection if both users are online, or erasure-coded DHT delivery if the recipient goes offline during transfer.

**Implementation (V3.1.11):** After MEDIA_ACCEPT, the sender calls `_storeErasureCodedBackup()` on the content envelope — identical to the inline media path. Large fragments (>1200B) are automatically split by the UDP fragmenter. Example: a 10 MB file produces 10 erasure fragments of ~1.43 MB each, each stored on a different DHT peer.

#### 3.4.3 Auto-Download Thresholds (User-Configurable)

All thresholds are user-configurable in privacy settings (`privacy_settings.dart`). Default per-type limits:

| Media Type | Default Max Size |
|-----------|-----------------|
| Images | 10 MB |
| Videos | 50 MB |
| Files | 25 MB |
| Voice Messages | 5 MB |

Users can set their own limits, disable auto-download entirely, or set different policies for WiFi vs. mobile data.

### 3.5 Relay Storage Management

Each node contributes storage to the network for relaying other users' fragments. The relay budget is dynamically adjusted based on available device storage.

Relay fragments are deleted after confirmed delivery to the recipient, or after the TTL expires (7 days). Own chat data is never automatically deleted and always has priority over relay data.

**Implementation detail:** `MailboxStore.retrieveFragments()` matches fragments by comparing the stored `mailboxId` bytes directly (`_bytesEqual`), not via hex-encoded key prefix matching. Direct byte comparison eliminates potential mismatches from encoding differences between Protobuf deserialization paths (store vs. retrieve). The store key (`mailboxHex:messageIdHex:index`) is used only for deduplication and deletion, not for retrieval matching.

**Persistent storage (V3.1.11):** The MailboxStore persists fragments as binary files (`.bin`) in `<profileDir>/mailbox/`. Each file has a 96-byte header (mailboxId, messageId, fragment metadata, timestamps) followed by raw fragment data — no base64 overhead. Legacy JSON files from older versions are automatically migrated on load. Disk writes are batched (every 2 seconds) to avoid iowait on slow virtual disks. This ensures fragments survive process restarts — critical for relay nodes that store offline messages for other peers.

**Storage budget (V3.1.11):** Each node enforces a total relay storage budget (default 500 MB, min 100 MB, max 2 GB) and a per-source budget (20% of total). `storeFragment()` rejects fragments when either budget is exceeded. Budget utilization is exposed via `budgetUtilization` for the Network Stats dashboard.

**Proactive fragment push:** When a node stores a fragment and knows the mailbox owner (via ed25519 PK → mailbox ID mapping from PeerExchange and accepted contacts), it immediately forwards the fragment to the owner. This changes the relay from pull-based (~10s poll interval) to push-based (< 1s latency). The forwarded envelope uses the relay node's own `senderId` (not the original sender's) to prevent falsely updating `lastSeen` on the recipient — which would make unreachable peers appear active and cause fragment distribution to waste sends on them.

---

## 4. Encryption & Cryptography

### 4.1 Design Philosophy

Cleona employs a hybrid encryption scheme combining classical algorithms (decades of proven security, extensive cryptanalysis) with post-quantum algorithms (protection against future quantum computers). The principle is: an attacker must break BOTH the classical AND the post-quantum scheme simultaneously to compromise communications. If either one remains secure, all data is protected.

**Stateless by design:** Cleona uses **Per-Message Key Encapsulation** instead of session-based protocols (like Signal's Double Ratchet). Every message is self-contained — it carries everything the recipient needs for decryption. There is no shared mutable state between sender and recipient that could desynchronize, corrupt, or "break." This eliminates an entire class of bugs (session establishment failures, ratchet corruption, race conditions) while maintaining the same security properties.

### 4.2 Cryptographic Primitives

| Category | Algorithm | Key Size | Purpose |
|----------|-----------|----------|---------|
| Asymmetric (Identity) | Ed25519 + ML-DSA-65 | 32B + 4,595B | Signatures |
| Asymmetric (Per-Message) | X25519 + ML-KEM-768 | 32B + 1,184B | Per-message key encapsulation |
| Symmetric (Messages) | AES-256-GCM | 256-bit | Message encryption |
| Symmetric (DB at rest) | XSalsa20-Poly1305 | 256-bit | Database encryption |
| Symmetric (Calls) | AES-256-GCM | 256-bit | Real-time media encryption (SRTP) |
| Hash | SHA-256 | 256-bit | Node ID, Mailbox ID, Key derivation |
| KDF | HKDF-SHA256 | Variable | Key derivation |
| Password Hash | Argon2id | Variable | Key file encryption |
| Compression | zstd | Variable | Payload reduction |

### 4.3 Per-Message Key Encapsulation (Stateless E2E)

Every message is encrypted with a **fresh, one-time key** that is derived independently — no handshake, no session state, no synchronization between sender and recipient.

#### 4.3.1 How It Works

**Sending (Alice → Bob):**

1. Alice generates a fresh ephemeral X25519 key pair (`eph_sk`, `eph_pk`).
2. Alice performs X25519 Diffie-Hellman: `dh_secret = DH(eph_sk, bob_x25519_pk)`.
3. Alice performs ML-KEM-768 encapsulation to Bob's ML-KEM public key: `(kem_ciphertext, kem_secret) = Encapsulate(bob_ml_kem_pk)`.
4. Alice derives the message key: `msg_key = HKDF-SHA256(ikm=dh_secret||kem_secret, salt=SHA-256("cleona-per-message-kem/salt/v2"), info="cleona-msg-v2", length=32)`. The salt provides domain separation against any future Cleona component using HKDF with similar IKM (Section 4.3.7).
5. Alice encrypts the message payload with AES-256-GCM using `msg_key`.
6. Alice sends: `[eph_pk | kem_ciphertext | aes_nonce | encrypted_payload]`.
7. Alice **deletes** `eph_sk` immediately. It is never stored.

**Receiving (Bob):**

1. Bob extracts `eph_pk` and `kem_ciphertext` from the message.
2. Bob performs X25519 DH: `dh_secret = DH(bob_x25519_sk, eph_pk)`.
3. Bob performs ML-KEM-768 decapsulation: `kem_secret = Decapsulate(bob_ml_kem_sk, kem_ciphertext)`.
4. Bob derives the same message key: `msg_key = HKDF-SHA256(ikm=dh_secret||kem_secret, salt=SHA-256("cleona-per-message-kem/salt/v2"), info="cleona-msg-v2", length=32)`.
5. Bob decrypts the payload with AES-256-GCM.

**No state required.** Bob needs only his own private keys (which he always has) and the ephemeral data embedded in the message. There is nothing to synchronize, nothing that can desynchronize.

#### 4.3.2 Security Properties

| Property | How It Is Achieved |
|----------|-------------------|
| **Forward Secrecy** | Sender's ephemeral private key is deleted immediately after encryption. Even if Bob's long-term key is later compromised, past messages cannot be decrypted because the ephemeral key no longer exists. |
| **Post-Quantum Security** | Hybrid approach: X25519 (classical) + ML-KEM-768 (post-quantum). Attacker must break BOTH. |
| **Per-Message Keys** | Every message uses a fresh ephemeral key pair → unique message key. Compromising one message key reveals nothing about any other message. |
| **Post-Compromise Recovery** | After Bob rotates his public key (see 4.3.3), all subsequent messages are encrypted to the new key. An attacker who obtained the old key loses access. |
| **Offline Delivery** | Trivial — the sender only needs the recipient's public key (known from contact exchange). No handshake required, no "session must be established first." |
| **No Session Breakage** | There is no session. Nothing to break, corrupt, or desynchronize. |
| **Domain Separation** | HKDF salt = SHA-256("cleona-per-message-kem/salt/v2"). Prevents key collision should any future Cleona component derive keys via HKDF from a similar IKM. (Section 4.3.7) |

#### 4.3.3 Key Rotation

Each identity periodically rotates its X25519 and ML-KEM public keys to provide post-compromise recovery:

1. Node generates a new X25519 + ML-KEM-768 key pair.
2. The new public keys are distributed to all contacts and peers via PeerExchange and PROFILE_UPDATE.
3. Senders use the latest known public key for new messages.
4. The old private key is retained for a transition period (14 days) to decrypt messages that were encrypted to the old key and are still in transit.
5. After the transition period, the old private key is deleted.

**Rotation interval:** Weekly (configurable). Rotation is also triggered immediately when the user suspects key compromise.

**Timing invariant (Key Transition vs. Fragment Retention):** The key transition period (14 days) is strictly longer than the DHT fragment retention period (7 days, see Section 3.2). This guarantees that every erasure-coded fragment stored in the DHT at the time of rotation can be decrypted within the transition window. There is no window in which a fragment exists but its corresponding key has already been deleted.

#### 4.3.4 Per-Message Overhead

Each message carries the ephemeral key material:

| Component | Size |
|-----------|------|
| X25519 ephemeral public key | 32 bytes |
| ML-KEM-768 ciphertext | 1,088 bytes |
| AES-256-GCM nonce | 12 bytes |
| KEM version field (uint32 varint) | 1-2 bytes |
| **Total overhead** | **~1.1 KB per message** (incl. version field) |

For a typical text message (50–500 bytes), this is significant relative overhead. However: (1) the payload is compressed with zstd before encryption, (2) the overhead is constant regardless of message size (large media files have negligible relative overhead), and (3) eliminating the entire PQXDH handshake infrastructure (Pre-Key Bundles, OTKs, SPK rotation, session state persistence) is a massive simplification that prevents an entire class of bugs.

#### 4.3.5 Encryption Exceptions

The following message types are NOT encrypted with Per-Message KEM:

- **RESTORE_BROADCAST / RESTORE_RESPONSE** — A recovering peer may not have the sender's current public key. These use envelope-level signing only.
- **CONTACT_REQUEST / CONTACT_REQUEST_RESPONSE** — First contact; the sender may not have the recipient's encryption public key yet. Signed only.

All other message types — including TEXT, FILE, VOICE_MESSAGE, GROUP_KEY_UPDATE, CHANNEL_POST, CHAT_CONFIG_UPDATE, IDENTITY_DELETED, PROFILE_UPDATE — are always encrypted with Per-Message KEM.

#### 4.3.6 Post-Quantum Key Recovery After Device Loss

ML-KEM-768 and ML-DSA-65 private keys are not deterministically derivable from the master seed (liboqs limitation) and are lost when a device is lost or destroyed. After recovery via the 24-word phrase, new PQ key pairs are generated. This creates a transition window with specific security properties:

**What happens to in-transit messages:** Messages encrypted with the old PQ public keys (still stored as erasure-coded fragments in the DHT) cannot be decrypted via PQ-KEM after recovery. However, the X25519 component of the hybrid encryption IS deterministically recovered from the master seed. Since the message key is derived as `HKDF(dh_secret || kem_secret)`, and the DH secret can be recomputed using the recovered X25519 private key, the message can still be decrypted — but with only classical (non-PQ) security during this transition.

**Why this is acceptable:** (1) Chat history is not reconstructed from DHT fragments during recovery. Instead, contacts send their stored plaintext history via Restore Response (Phase 2/3), freshly encrypted with the recovering node's new keys. (2) The Restore Broadcast distributes the new PQ public keys to all contacts immediately. Contacts update their key records and encrypt all subsequent messages with the new PQ keys. (3) The transition window (between device loss and contacts processing the Restore Broadcast) is typically minutes to hours. During this window, any messages sent by contacts fall back to X25519-only encryption — still secure against classical attackers, just without post-quantum protection.

**Explicit flow:** Recovery phrase → master seed → deterministic Ed25519/X25519 keys (identical to before) → new ML-KEM-768/ML-DSA-65 keys (fresh) → Restore Broadcast with new PQ public keys → contacts update keys → full hybrid security restored.

#### 4.3.7 KEM Versioning (Sec H-5, V3.1.72+)

The Per-Message KEM construct supports versioning via an explicit `version` field in the `PerMessageKem` proto header. Currently:

- **v1 (legacy, dropped V3.1.72):** `salt = Uint8List(32)` (zero bytes), `info = "cleona-msg-v1"`. Removed because of insufficient domain separation against potential future HKDF use of the same IKM.
- **v2 (current, V3.1.72+):** `salt = SHA-256("cleona-per-message-kem/salt/v2")` (32 bytes constant), `info = "cleona-msg-v2"`.

**Constants in `lib/core/crypto/per_message_kem.dart`:**
- `currentKemVersion = 2`
- `kemSendVersion = 2` — what we write into outgoing `kem_header.version`
- `acceptKemVersions = {2}` — what we accept on receive; messages with version ∉ this set are dropped (`KemVersionRejectedException`)

**Wire format:** `PerMessageKem.version` is `uint32` field 4. Pre-rollout senders (V3.1.71 and older) had no field 4 in their proto schema; their outgoing messages parse with `version=0` on receive (proto3 default). v2-only receivers drop these.

**Migration strategy:** Single-release cutover at V3.1.72. The simultaneous Hard-Block-Update-Enforcement (Section 16.4.7) prevents pre-rollout clients from continuing to operate without an update. Trade-off: one-time loss of in-flight v1 traffic (S&F messages, Reed-Solomon fragments) at release-day, accepted as Beta-channel migration cost.

**Anti-spoof properties:**
- Downgrade-spoof (header.version=1, ciphertext encrypted with v2 key): rejected — v1 not in `acceptKemVersions`.
- Upgrade-spoof (header.version=2, ciphertext from pre-rollout v1 sender): AES-GCM auth-tag fails because v2-salt-derived key ≠ v1-zero-bytes-salt-derived key. No cleartext leak.

**Why not match Secret Rotation pattern (Section 17.5.5)?** Secret rotation sits on the network-secret outer layer (HMAC packet authentication) and must support 90-day overlap windows because the secret is embedded in obfuscated binary fragments and rotates with major releases. The KEM version is at the inner crypto layer, lives in a single Dart file, and we control it tightly via release cadence — no overlap-window infrastructure needed.

### 4.4 Call Encryption (Ephemeral Call Key)

Real-time voice and video calls require a different encryption approach than chat messages. Per-Message KEM adds ~1.1 KB overhead and a KEM operation per packet — unacceptable for voice (50 packets/second) and video (hundreds of packets/second). Calls use an **ephemeral symmetric key** negotiated once at call start.

#### 4.4.1 Call Key Negotiation

```
Alice                          Bob
  |                              |
  |--- CALL_INVITE ------------->|
  |    [alice_eph_pk,            |
  |     KEM(bob_pk)]             |
  |                              |
  |<-- CALL_ANSWER --------------|
  |    [bob_eph_pk,              |
  |     KEM(alice_pk)]           |
  |                              |
  Both derive: call_key = HKDF(
    DH(a,B) || DH(b,A) ||
    KEM_a || KEM_b,
    "cleona-call-v1")
  |                              |
  |<=== AES-256-GCM media =====>|
  |     (SRTP with call_key)     |
  |                              |
  |--- CALL_HANGUP ------------->|
  |    call_key deleted          |
```

**Properties:**
- The call key exists only in memory, only during the call.
- Both parties contribute ephemeral keys → mutual forward secrecy.
- Hybrid: X25519 + ML-KEM-768, same post-quantum security as chat messages.
- If the call drops or a party crashes, the key is lost. Reconnecting negotiates a fresh key.

#### 4.4.2 Group Calls

Group calls use a **shared symmetric call key** distributed to all participants:

1. The call initiator generates a random 256-bit `call_key`.
2. The `call_key` is encrypted individually to each participant using Per-Message KEM (same as chat messages) and sent via CALL_INVITE.
3. All media packets are encrypted with `call_key` via AES-256-GCM (SRTP).

**Key rotation during group calls:**

| Event | Action |
|-------|--------|
| Participant leaves voluntarily | No key rotation (they already knew the key) |
| Participant crashes + rejoins | No key rotation (they had the key before) |
| Participant is **kicked** | Key rotation → new key distributed to all remaining participants |
| New participant joins | Key rotation → new key distributed to all including new participant |

Key rotation is triggered only when the **authorized participant set** changes. A crash + rejoin does not change authorization.

**Rejoin after crash:** The rejoining participant sends a CALL_REJOIN message. Any active participant responds with the current `call_key` encrypted via Per-Message KEM to the rejoining participant's public key.

#### 4.4.3 Group Call Delivery: Overlay Multicast Tree

P2P group calls use a combination of **LAN IPv6 Multicast** and an **Overlay Multicast Tree** for efficient media distribution without a central server.

**The problem with Full Mesh:** In a full mesh topology, each participant uploads N-1 copies of their stream. With 10 participants at 1 Mbps video, that is 9 Mbps upload per person — exceeding most home connections.

**LAN IPv6 Multicast:** Participants on the same local network use IPv6 multicast (temporary multicast group address per call). One stream from the sender reaches all LAN participants simultaneously — zero additional upload cost per local recipient.

**Overlay Multicast Tree (Internet):** For participants across different networks, an application-layer multicast tree distributes streams:

```
Alice (source, uploads 2 streams)
├── Bob (receives, relays to Charlie)
│   └── Charlie
└── Detlef (receives, relays to Emil)
    └── Emil
```

Each participant uploads at most **2–3 streams** regardless of total group size. The tree is constructed dynamically based on measured RTT and available bandwidth between participants. Nodes with the best connectivity serve as relay points.

**Tree construction uses existing routing table:** The overlay multicast tree is not constructed blindly. It uses the Distance-Vector routing table (Section 2.2.3) as a weighted graph. If Alice cannot reach Bob directly but has a relay route via Charlie, Charlie is placed as a relay point in the tree. The tree construction algorithm computes a minimum-spanning-tree over all participants using route costs as edge weights.

**Signaling via chat channel:** CALL_INVITE, CALL_ANSWER, and tree topology updates are delivered through the normal message channel (Per-Message KEM, 3-Layer Delivery). This channel already handles NAT traversal and relay transparently — no separate signaling infrastructure is needed.

**Unreachable participants:** If no path exists between two participants (both behind Symmetric NAT with no common relay peer), the participant cannot join the call. The app displays a notification explaining that no route could be established. This is a deliberate limitation of a serverless P2P system.

**Hybrid (LAN + Internet):**

```
┌─── Office LAN ──────────────┐     ┌─── Home LAN ──────┐
│ Alice ──→ ff02::cleona:call │     │ Detlef             │
│ Bob   ← (multicast, free)  │─1──►│ Emil ← (multicast) │
│ Charlie ← (multicast, free)│     └────────────────────┘
└─────────────────────────────┘
  1 upload for 3 local recipients     1 internet stream relayed locally
```

**Scaling limits:**

| Mode | Max Participants | Bottleneck |
|------|-----------------|------------|
| Video call | **50** | Overlay tree depth (~6 hops), cumulative latency |
| Audio call | **100+** | Audio bitrate (~50 kbps) is negligible |

#### 4.4.4 Cross-Platform Audio Stack (#U10b)

Audio capture and playback are platform-agnostic and routed through **`libcleona_audio.so`**, a thin C shim that wraps two vendored native libraries:

| Layer | Library | Version | Role |
|-------|---------|---------|------|
| Backend | **miniaudio** | 0.11.21 | Auto-selects the best native audio API per platform |
| DSP | **speexdsp** | 1.2.1 | Acoustic Echo Cancellation (AEC) + Noise Suppression (NS) |

**Backend matrix (miniaudio auto-detect):**

| Platform | Capture / Playback Backend | Notes |
|----------|---------------------------|-------|
| Linux | PulseAudio (preferred) → ALSA (fallback) | PipeWire is reachable through the PulseAudio shim |
| Android | AAudio (API 26+) → OpenSL ES (legacy) | Low-latency path |
| Windows | WASAPI | Shared mode |
| macOS | Core Audio | Build-infra not yet wired in repo |
| iOS | Core Audio (AVAudioSession) | Build-infra not yet wired in repo |

**Build reproducibility:** speexdsp 1.2.1 is **vendored as full source** under `native/cleona_audio/vendor/speexdsp/` (tarball SHA256 `d17ca363654556a4ff1d02cc13d9eb1fc5a8642c90b40bd54ce266c3807b91a7`) and statically linked into `libcleona_audio.so`. miniaudio is a single-header library committed at SHA256 `6b2029714f8634c4d7c70cc042f45074e0565766113fc064f20cd27c986be9c9`. Building no longer needs internet access or distro packages — `linux/cleona_audio/`, `android/.../jniLibs/`, and the Windows native build all reference the vendored sources directly.

**Audio parameters (constant across platforms):**

| Parameter | Value |
|-----------|-------|
| Sample rate | 16 kHz |
| Channels | 1 (mono) |
| Frame size | 320 samples = 20 ms = **640 bytes** raw PCM (S16LE) |
| Encoding | Raw PCM, AES-256-GCM per frame (no Opus, no codec compression) |
| Speex AEC tail | 4000 samples = 250 ms @ 16 kHz |
| Defaults | AEC: on, NS: on, AGC: off |

The 250 ms AEC tail covers typical headset and integrated-laptop-mic echo paths. AGC is intentionally off — gain swings introduced by AGC are perceptually worse than a slightly-low input level on the kinds of devices Cleona targets.

**Capture-isolate pattern preserved:** The Dart side keeps the v2.8 Capture-Isolate architecture: a dedicated isolate consumes 20 ms frames from a native ring buffer that the shim fills from a miniaudio capture callback. The isolate runs encryption (`AES-256-GCM` with the Call Session Key from §4.4.1) and forwards ciphertext frames to the main isolate via `SendPort`. No Dart code changes were needed at the layer above `AudioEngine` — the swap is transparent at the FFI seam.

**Why no codec:** With 16 kHz mono PCM at 640 bytes/frame, the on-wire bandwidth before AES-GCM overhead is ~256 kbps per direction. This is well within consumer broadband and 4G/5G mobile budgets, and the simplicity buys the project (a) a single ciphertext path, (b) no codec licensing concerns, (c) trivial AEC reference signal (the same PCM that goes to playback). A codec layer (Opus) can be added later behind the shim if metered-data deployments need it.

#### 4.4.5 Live-Media Frame Authenticity (#U10b)

`CALL_AUDIO` (envelope type 36) and `CALL_VIDEO` (envelope type 40) are classified as **ephemeral media** in the envelope pipeline and **skip two of the standard envelope steps**:

1. **No ML-DSA signature.** Post-quantum authenticity is established at call setup: the `CALL_INVITE` and `CALL_ANSWER` envelopes carry full Ed25519 + ML-DSA-65 dual signatures, and the resulting `call_key` is mixed from a hybrid X25519 + ML-KEM-768 KEM (§4.4.1). Once both sides hold the call key, every audio/video frame is authenticated by AES-256-GCM (16-byte tag, fresh random nonce) under that key — a quantum adversary cannot forge frames without first breaking the setup handshake. A pro-frame ML-DSA signature would add ~3500 bytes wire and ~600 µs CPU per frame on top of authentication that is already post-quantum-secure.
2. **No zstd compression probe.** Frame payloads are already AES-256-GCM ciphertext (high entropy) — zstd cannot compress them, and running the probe just costs CPU.

Pro-frame **Ed25519** identity proof and **AES-256-GCM** content authenticity remain strict on every frame. The optimisation only removes the redundant outer layer.

#### 4.4.6 Per-Call-Session Route Cache (#U10b)

A typical 1:1 audio call generates 50 envelopes per second per direction (20 ms frames). Re-running the full distance-vector route lookup for each one — including peer-table reads, NAT context filtering, and address-priority sorting — is wasteful when the destination is a single, known peer for the lifetime of the call.

Each `CallSession` therefore caches the resolved `PeerInfo` (and selected address) at the first outgoing frame. Subsequent frames send directly through the cached peer. The cache is invalidated by the existing `DvRouting.onRouteDown(peerId)` callback — when the route to the call peer is marked DOWN (3× ACK timeout, poison-reverse, or peer-leave), the next frame falls back to a fresh resolution and the call follows the same recovery cascade as any other ephemeral message.

### 4.5 Group Encryption (Pairwise Per-Message KEM)

For group chats and private channels, Cleona uses **pairwise Per-Message KEM**: each group message is individually encrypted to each group member using their public key with a fresh ephemeral key per member. No handshake, no session establishment, no shared state.

**How it works:** When a user sends a message to a group, the sender's node wraps the content in a `ChannelPost` protobuf (containing the group/channel ID, a unique post ID, the text, and optional binary content data). This `ChannelPost` is then encrypted individually to each group member using Per-Message KEM (see 4.3) and sent as a `GROUP_KEY_UPDATE` message type. Each member decrypts independently using their own private key.

**Why this works seamlessly:**
- **No session establishment needed.** Each member's public key is known from the Group Invite. Sending is possible immediately.
- **No "one-sided messaging" bugs.** Since there is no session state to synchronize, every member can always decrypt messages from every other member.
- **Member joins are instant.** New members receive all existing members' public keys in the invite and can immediately send and receive.
- **Member leaves are clean.** No session state to clean up. The leaving member simply no longer receives new messages.

**Trade-offs:** Pairwise encryption has O(n) send cost (one encrypted message per member) versus O(1) for shared-key approaches like MLS. For Cleona's target group sizes (up to ~50 members), this is acceptable and provides stronger security guarantees: compromising one member's private key does not affect any other member's encryption.

**Media in groups:** File attachments, voice messages, and pasted clipboard content are embedded directly in the `ChannelPost` via the `content_data` field (binary payload) alongside `ContentMetadata` (MIME type, file size, filename). This avoids routing media through separate FILE/VOICE_MESSAGE types, which would incorrectly appear in direct conversations instead of the group.

**Member notification:** When sending group invites or role updates to multiple members, each member must receive a freshly constructed payload. Reusing the same envelope object across members causes signature/serialization corruption.

### 4.6 Encryption Order

The processing order for outgoing messages is:

1. Serialize message to Protobuf binary.
2. Compress with zstd.
3. Encrypt with Per-Message KEM (AES-256-GCM with fresh ephemeral key).
4. Sign with Ed25519 + ML-DSA-65.
5. Erasure code (if non-ephemeral, with RUDP ACK-driven delivery).
6. Attach Proof of Work.
7. Send.

Incoming messages are processed in reverse order.

**Signing precaution:** `sendEnvelope()` must clear any existing signatures before signing. If an envelope is reused, the second signature would be computed over data containing the first signature, producing an invalid result.

**Ausnahme — Liveness-Records (§2.2.4):** Cleona's PQ-Stance fordert grundsätzlich
hybrid-Signaturen (Ed25519 + ML-DSA) auf jedem signierten Record. Liveness-Records
sind die einzige bewusste Ausnahme: Ed25519-only, weil sie kurzlebig sind (TTL
15min-1h), nur Adressen tragen (nicht Identitäts-Bindung), und PQ-Forgery dort
nur kurzes Adress-Mis-Routing bewirkt — die Identitäts-Authentizität trägt das
hybrid-signierte Auth-Manifest. Trade-off: ~15× Bandbreitenersparnis pro
Liveness-Refresh (3357B → 64B Sig).

### 4.7 Database Encryption at Rest

All SQLite database files are encrypted at rest using XSalsa20-Poly1305 (libsodium AEAD). This provides post-quantum secure storage — SHA-256 key derivation offers 128-bit security against Grover's algorithm.

#### 4.7.1 Key Derivation

The database encryption key is derived from the identity's Ed25519 secret key:

```
db_key = SHA-256(ed25519_secret_key[0:32] + "cleona-db-key-v1")
```

This produces a 32-byte key suitable for XSalsa20-Poly1305. The key is deterministic — the same identity always derives the same DB key, enabling decryption after recovery.

#### 4.7.2 File Format

Encrypted database files use the extension `.enc` (e.g., `cleona.db.enc`):

```
[24-byte random nonce][N-byte XSalsa20-Poly1305 ciphertext + 16-byte Poly1305 MAC]
```

A fresh 24-byte nonce is generated randomly for each encryption operation. The Poly1305 MAC provides authenticated encryption — tampered ciphertext is detected and rejected.

#### 4.7.3 Runtime Flow

1. **Startup:** If `cleona.db.enc` exists, decrypt it to a temp file (`.cleona_db_tmp`). SQLite operates on this unencrypted temp file in memory.
2. **Migration:** If only `cleona.db` (unencrypted) exists, copy it to temp, encrypt it to `.enc`, and operate on temp. The unencrypted original is deleted on close.
3. **Periodic flush:** Every 60 seconds, the current temp DB is encrypted back to the `.enc` file for crash safety.
4. **Shutdown:** Final encrypted flush, then the unencrypted temp file is securely deleted. The plain `cleona.db` is also removed if it still exists (migration cleanup).

#### 4.7.4 FileEncryption (separate von SQLite-Encryption)

Cleona hat zwei orthogonale Encryption-Systeme für on-disk-Daten:

1. **SQLite-DB-Encryption** (oben in §4.7.1-3): per-Identität, deterministisch
   aus Ed25519-sk abgeleitet. Verwendet für `cleona.db.enc`.
2. **FileEncryption** (`lib/core/crypto/file_encryption.dart`): daemon-level
   random 32-byte key in `~/.cleona/db.key` (mode 0600), atomic-write via
   tmp+rename mit Crash-Recovery-Sidecars (`.enc.tmp`, `.enc.old`). Verwendet
   für: routing_table.json, channels.json, contacts.json, identity_dht_storage.json
   (§2.2.4 Identity Resolution storage).

Trennung wegen unterschiedlicher Anforderungen: SQLite-Inhalte sind per-Identität-
spezifisch und müssen nach Recovery aus seed-phrase wiederherstellbar sein
(deterministisch). JSON-Files sind Daemon-shared und überleben Identity-Switch
(eigener Schlüssel).

#### 4.7.5 Implementation

The encryption logic is in `db_encryption.dart` (`DbEncryption` class). The database (`database.dart`, `CleonaDatabase`) accepts an optional `encryptionKey` parameter. `flushEncrypted()` performs periodic encrypted writes; `closeEncrypted()` performs the final flush and cleanup.

---

## 5. Identity & Authentication

### 5.1 Identity Model

Cleona uses a purely cryptographic identity model. No email, phone number, or personal information is required or collected. At first launch, the app generates two hybrid key pairs: an encryption key pair (X25519 + ML-KEM-768) for per-message key encapsulation, and a signing key pair (Ed25519 + ML-DSA-65) for authentication and message integrity.

**Profile Display Name:** Users set a human-readable display name during initial setup. This name is transmitted in contact requests so recipients see a meaningful name rather than a cryptographic identifier. The display name can be changed at any time — changes are broadcast to all accepted contacts via PROFILE_UPDATE (containing `display_name` field in `ProfileData` protobuf).

**Local Contact Alias:** Recipients can locally rename any contact without affecting the contact's actual name. The `localAlias` field overrides the display for that user only. When a contact changes their own name while the recipient has a local alias set, a notification banner appears offering to accept the new name or keep the local alias. Contacts without a local alias receive the name change automatically.

### 5.2 Multi-Identity Architecture

A single Cleona installation (called a "profile") can host multiple cryptographic identities. Each identity has its own keys, contact list, message history, database, and network port. This enables:

- Testing with multiple personas on the same device
- Role separation (personal vs. professional)
- Anonymity options (disposable identities)

#### 5.2.1 Master-Seed HD-Wallet Key Derivation

All identities within a profile are derived from a single **master seed** (32 bytes / 256 bits) using HD-wallet-style derivation:

```
ed25519_seed = SHA-256(master_seed + "cleona-identity-N-ed25519")
```

Where N is a monotonically increasing identity index (never reused, even after deletion). From the Ed25519 seed, the X25519 key pair is derived via libsodium's birational mapping. Post-quantum keys (ML-DSA-65, ML-KEM-768) are generated fresh per identity because liboqs does not support seeded key generation — these are backed up separately.

**Properties:**
- Same master seed + index always produces the same Ed25519/X25519 keys (deterministic recovery).
- The master seed is encoded as a 24-word recovery phrase for human-friendly backup.
- Recovery of the master seed restores all identity indices via the encrypted DHT Identity Registry (see Section 6.4).

#### 5.2.2 Identity Registry

The identity registry (`identities.json`, version 2) stores:

```json
{
  "version": 2,
  "master_seed_hex": "...",
  "next_identity_index": 3,
  "identities": [
    {
      "id": "identity-1",
      "display_name": "Alice",
      "profile_dir": "~/.cleona/identities/identity-1",
      "port": 49152,
      "identity_index": 0,
      "description": "Profile description text",
      "status": "active"
    }
  ]
}
```

**Backward compatibility:** v1 registries (per-identity `recovery_seed_hex`, no master seed) are loaded transparently. Legacy identities have `identity_index = -1`.

#### 5.2.3 Identity Switching

The UI displays the active identity's display name in the AppBar. Tapping it opens a bottom sheet listing all identities with their unread message counts and profile pictures. Switching identities is instantaneous — all identity nodes run simultaneously in the background. Each identity operates independently with its own contacts, chats, and encryption state.

#### 5.2.4 Identity Creation

New identities are created from the UI with a display name. If a master seed exists, keys are derived from it using the next available index. Otherwise, keys are generated randomly. A new subdirectory is created, and a new CleonaNode is started on an automatically assigned port.

#### 5.2.5 Identity Deletion with Network Notification

When an identity is permanently deleted, an `IDENTITY_DELETED` notification (type 102) is sent to all contacts via `deleteIdentityAndNotify()`. The notification contains the deleted identity's Ed25519 public key, deletion timestamp, and last known display name. Contacts receiving this notification clean up associated data (conversations, group memberships) and display a notification.

#### 5.2.6 Launcher-Badge Aggregation (#U3)

The Android system Launcher-Badge is a single number per app — there is no per-identity badge. Earlier code wired a per-service `onBadgeCountChanged` that pushed each service's own conversation sum to the system; the most-recently-firing identity overwrote the others (last-writer-wins). Result: the badge showed only one identity's count, not the cross-identity total.

`_updateAndroidBadge()` in `main.dart` now sums across all `_androidServices`:

```dart
void _updateAndroidBadge() {
  if (!Platform.isAndroid) return;
  var total = 0;
  for (final svc in _androidServices.values) {
    for (final conv in svc.conversations.values) {
      total += conv.unreadCount;
    }
  }
  channel.invokeMethod('updateBadge', {'count': total});
}
```

Each per-identity `onBadgeCountChanged` delegates to this single function. The In-App per-tab badge (`HomeScreen`) keeps per-identity granularity — only the system Launcher-Badge is aggregated.

**Persistence:** `Conversation.unreadCount` is now serialized in `conversations.json.enc` (previously transient). After daemon restart, `_loadConversations` reads the persisted value and `_updateBadgeCount()` runs once at startup so the system badge matches disk truth before any new traffic.

**Hard-Block-Update-Enforcement scope (V3.1.72+):** Hard-Block (see Section 16.4.7) operates at the daemon process level — all identities of one installation are gated together. There is no per-identity bypass; if the installation's app version is below `manifest.minRequiredVersion`, every identity sees the splash and (if user skips) operates in Reduced-Mode.

### 5.3 Profile Pictures & Descriptions

Each identity can optionally have a **profile picture** (JPEG, max 64 KB) and a **description** (max 500 characters). These are stored locally and exchanged with contacts.

#### 5.3.1 Storage

| Content | File Path |
|---------|-----------|
| Own profile picture | `{profileDir}/profile_pic.jpg` |
| Contact profile pictures | `{profileDir}/contact_pics/{nodeIdHex}.jpg` |
| Group/channel pictures | `{profileDir}/channel_pics/{channelIdHex}.jpg` |

#### 5.3.2 Exchange Mechanisms

Profile data is exchanged in multiple contexts:

1. **Contact requests:** `ContactRequestMsg` and `ContactRequestResponse` include `profile_picture` and `description` fields. Both parties see each other's profile during the request/accept flow.
2. **Profile updates:** When a user changes their picture or description, a `PROFILE_UPDATE` message (type 103) with a `ProfileData` protobuf is sent to all contacts. The `updated_at_ms` timestamp enables conflict resolution.
3. **Restore responses:** `RestoreContactInfo` and `RestoreGroupMember` include profile pictures and descriptions, ensuring profiles survive recovery.
4. **Group/channel invites:** `ChannelInvite` includes `channel_picture` and `channel_description` fields.
5. **Group/channel creation:** `ChannelCreate` includes a `picture` field.

#### 5.3.3 UI Display

- **Conversation list:** Small CircleAvatar with contact's profile picture (or initials fallback).
- **Contact request screen:** Full-size CircleAvatar (radius 48) with profile picture and description text.
- **Group messages:** Small CircleAvatar (radius 14) next to each message showing the sender's profile picture.
- **Identity list:** Profile pictures shown in identity switcher.
- **Settings:** Profile section with picture preview, "Change Picture" button (file picker), "Remove Picture" button, description TextField, and "Save Profile" button.

#### 5.3.4 Validation

Profile pictures are validated by `ImageProcessor.validateProfilePicture()`: checks for empty data and enforces the 64 KB size limit. Oversized images are rejected with a user-friendly error message including the actual size.

### 5.4 Key Storage

Private keys must be stored securely at rest on every platform. The storage strategy differs by platform, always using the strongest available mechanism:

| Platform | Storage | Encryption |
|----------|---------|------------|
| Android | Android Keystore | Hardware-backed |
| iOS | Secure Enclave / Keychain | Hardware-backed |
| Linux | File-based (keys.json) | Argon2id + XSalsa20-Poly1305 |

The Linux file-based storage (`keys.json`) format:
```json
{
  "version": 1,
  "salt": "base64-16-bytes",
  "nonce": "base64-24-bytes",
  "ciphertext": "base64-encrypted-key-data"
}
```

The plaintext (before encryption) contains base64-encoded Ed25519, ML-DSA-65, and ML-KEM-768 key pairs. X25519 keys are re-derived from Ed25519 on load (not stored separately).

Implementation: The key storage is abstracted behind a platform interface (`lib/core/crypto/key_store.dart`) with platform-specific implementations.

### 5.5 Contact Verification

Contacts are added exclusively via QR code scanning, ContactSeed URI sharing, NFC tap, or Mesh Discovery. There is no address book upload or phone number matching. Contact verification has four levels:

1. **Unverified:** Contact added via Node-ID or ContactSeed URI.
2. **Seen:** Key exchange completed successfully.
3. **Verified:** QR code or NFC verification in person.
4. **Trusted:** Explicitly marked as trusted by user.

The app prominently displays the verification status of each contact. Unverified contacts show a subtle warning. If a contact's key changes (e.g., they reinstalled the app), a prominent notification appears.

### 5.6 Contact Request Protocol

Adding a new contact in Cleona requires explicit mutual consent. When Alice adds Bob by entering his Node-ID or pasting a `cleona://` ContactSeed URI, Alice's node sends a CONTACT_REQUEST message containing her display name, Ed25519 public key, ML-DSA public key, X25519 public key, ML-KEM public key, optional profile picture, and optional description, plus a Proof of Work. Bob's node displays the request in a dedicated "Contact Requests" screen where Bob can accept, reject, or block the sender.

**ContactSeed URI in manual input (V3.1.41):** The "Add Contact" dialog accepts both plain 64-char hex Node-IDs and full `cleona://` URIs. When a URI is pasted, the embedded seed peers and target addresses are registered in the routing table (same flow as QR scan: `addPeersFromContactSeed()` → 3s wait for PONGs → `sendContactRequest()`). This ensures that new users who receive a ContactSeed URI via text, email, or any other channel can bootstrap into the network without prior peer knowledge. Plain hex Node-IDs still work but require existing network connectivity.

Accepting a request creates a contact record with the sender's display name, public keys, and profile data. Since Cleona uses Per-Message KEM (see Section 4.3), no key exchange handshake is needed — both parties can immediately send encrypted messages using each other's public keys from the contact request. The acceptance response (`ContactRequestResponse`) includes the responder's own profile picture and description. **Mutual auto-accept:** If Alice sends a CR to Bob while Bob already has a pending CR from Alice (or vice versa), the system detects the mutual intent and automatically accepts both requests. Rejecting sends a CONTACT_REQUEST_RESPONSE with the rejection reason. Blocking silently drops all future messages from that sender. **Conversation creation on acceptance:** Both `_handleContactResponse()` (outgoing CR accepted by remote) and `acceptContactRequest()` (incoming CR accepted locally) automatically create a conversation with a system message, ensuring the new contact is immediately visible in the "Recent" tab — not just in the "Contacts" tab.

**Important implementation detail:** After receiving a pending contact request, `contactManager.save()` must be called immediately to persist the request. Without this, pending CRs are lost on restart.

Contact requests are delivered both directly (if the recipient is online) and via DHT erasure-coded storage (for offline delivery). The system retries delivery whenever the target is seen online.

**Contact cleanup on deletion:** When a contact is deleted via `deleteContact()`, the contact record and associated public keys are removed. Since Cleona uses stateless Per-Message KEM (no session state), there is no session to clean up — deletion is clean and immediate.

**Persistent deletion flag:** Deleted contacts are tracked in a `_deletedContacts` set (persisted in `contacts.json`). This prevents deleted contacts from being re-created by restore broadcasts, startup auto-accept of old pending CRs, or any other mechanism that would silently resurrect them. The flag is cleared only when the user explicitly re-adds the contact (e.g., via a new QR scan), calling `clearDeletedFlag()`.

#### 5.6.1 Anti-Spam Protections

Contact requests are protected by multiple anti-spam layers:

1. **Proof of Work** at difficulty 20 on each request.
2. **Rate limiting** of at most 1 request per 20 seconds on the receiving side.
3. **Deduplication** — repeated requests from the same sender are silently dropped.
4. **Blocking** — blocked senders receive no response at all, preventing information leakage.

Rate-limited requests receive an automatic CONTACT_REQUEST_RESPONSE with `rejection_reason="rate_limited"` so the sender is informed.

#### 5.6.2 KEX Gate

To prevent unsolicited messages from appearing in a user's conversations, encrypted message processing is gated: messages are only decrypted and displayed if the sender is already an accepted contact OR a member of a shared group. Encrypted messages from unknown senders are silently dropped.

---

## 6. Identity Recovery & Restore Broadcast

This chapter describes the most innovative aspect of Cleona's architecture: how a user recovers their identity and complete chat history after device loss, without any server or cloud backup.

### 6.1 Recovery Phrase (24 Words)

At initial setup, the app generates a 24-word recovery phrase. This phrase encodes sufficient entropy to deterministically derive the complete key pair (both encryption and signing keys). The user is prompted to write down the phrase and store it securely.

**Implementation:** The 24 words encode 264 bits (256 bits entropy + 8-bit SHA-256 checksum). The word list uses deterministic phonetic generation (consonant-vowel patterns: CV, CVC, CVCV, CVCCV, CVCVC) to create pronounceable, memorable words. Bidirectional conversion is supported: `seedToPhrase()` and `phraseToSeed()` with checksum validation.

From the seed, key pairs are derived using SHA-256 with context strings: `SHA-256(seed + "cleona-ed25519")` for Ed25519, etc. Post-quantum keys (ML-KEM-768, ML-DSA-65) cannot be derived deterministically from a seed (liboqs limitation) and must be backed up separately.

### 6.2 Social Recovery (Shamir's Secret Sharing)

As an alternative to remembering a 24-word phrase, users can set up Social Recovery. The user designates 5 trusted contacts as recovery guardians. The app takes the recovery seed and splits it into 5 shares using Shamir's Secret Sharing (threshold: 3 of 5).

**Implementation:** Uses GF(256) Galois field arithmetic with irreducible polynomial 0x11B. Each secret byte gets a random degree-(K-1) polynomial where the constant term equals the secret byte. Shares are evaluated at points 1–N. Reconstruction uses Lagrange interpolation over GF(256). Share encoding: 1-based index + base64-encoded data.

Security: An attacker would need to compromise 3 of 5 guardians simultaneously. Guardians cannot collude accidentally because they don't know who the other guardians are (unless they guess). The threshold (3 of 5) balances security against the risk of guardian unavailability.

**Guardian UI Flow:**
- **Guardian setup:** Split seed → send shares to 5 contacts
- **Guardian trigger:** Contact menu → QR code + notification to other guardians
- **Guardian confirm:** Pop-up with warning, default=deny
- **Recovery:** Scan QR → collect 3/5 shares → reconstruct seed

### 6.3 Restore Broadcast

The Restore Broadcast is the mechanism that makes Cleona's recovery truly unique. After the user's key is recovered (via phrase or Social Recovery), the app sends a signed Restore Broadcast into the DHT network.

**Critical prerequisite:** The recovering device must perform a **complete wipe** of the old profile data before restoring from a recovery phrase. Without a wipe, the existing node has an empty contact list and a different Node-ID, causing a deadlock: no node recognizes the restoring sender, so all RESTORE_BROADCASTs are ignored. The correct flow is: wipe profile → enter recovery phrase → derive keys → rejoin network with original Node-ID → broadcast.

#### 6.3.1 Restore Broadcast Flow

1. User recovers their private key via recovery phrase or Social Recovery.
2. App performs a complete profile wipe and re-derives keys from the seed.
3. App connects to the DHT network using the recovered identity (original Node-ID).
4. App sends a signed Restore Broadcast message into the network (both direct and erasure-coded).
5. Every node that receives the broadcast checks: "Is this public key in my contact list?"
6. If yes, the contact's app automatically responds with: their contact information (so the recovering user rebuilds their contact list), the encrypted chat history of their shared conversation, group memberships with member crypto keys and profile data.
7. For anti-abuse protection: 3 of 5 recovery guardians must confirm the Restore Broadcast before contacts release their data. This prevents an attacker who stole the key from harvesting all chat histories.
8. The recovering device collects all responses and progressively rebuilds its complete state.

#### 6.3.2 Progressive Restoration

The restore progresses in phases to give the user a functional app as quickly as possible:

**Phase 1 (seconds):** The contact list rebuilds as contacts respond to the broadcast. The user sees their contacts appearing one by one.

**Phase 2 (minutes):** The latest 50 messages per conversation are delivered first. The user can immediately start chatting. Phase 2 is requested automatically after Phase 1 completes.

**Phase 3 (hours/days):** Full chat history loads progressively in the background, from newest to oldest. Older messages appear as they arrive.

If a contact has deleted their copy of a conversation, that history is lost (this is by design — data sovereignty means deletion is real). In group chats, any member who still has the history can provide it.

**Group restore:** Restore responses include full group membership with crypto keys (`RestoreGroupMember` proto) for each member. Since Cleona uses stateless Per-Message KEM, the recovering node can immediately send encrypted messages to all group members using their public keys — no session re-establishment needed. Group messages include the `group_id` field to route them to the correct group conversation (not the DM conversation with the sender).

#### 6.3.3 Aggressive Mailbox Polling

After sending a Restore Broadcast, the recovering node performs aggressive mailbox polling: 10 polls at 3-second intervals. This dramatically speeds up restore on LAN networks where waiting for event-driven push delivery (which depends on at least one peer noticing the recovering node via PONG) would be unnecessarily slow. The Kademlia bootstrap itself takes ~15-20 seconds with a freshly wiped routing table, so a 30-second delay before the first broadcast is used, with an automatic retry after 30 more seconds if no contacts were restored.

#### 6.3.4 Multi-Device Support

The Restore Broadcast mechanism serves as the bootstrap for multi-device support. When a user enters their 24-word seed phrase on a second device, it derives the same keys, joins the network with the same Node-ID, and performs a standard Restore Broadcast to receive the full state. After restore, the device registers itself with its twins via TWIN_ANNOUNCE and participates in ongoing Twin-Sync for local actions. See Section 26 for the complete multi-device architecture including device management, synchronization protocol, and revocation.

#### 6.3.5 Anti-Abuse Protections

**Rate limiting:** A maximum of one Restore Broadcast is accepted per identity per 5 minutes (per sender + per phase). This allows Phase-2 follow-up requests without being blocked by the Phase-1 rate limit.

**Guardian confirmation:** 3 of 5 guardians must actively confirm the restore before contacts release chat data. This is the same Social Recovery threshold — the guardian confirmation serves double duty.

**Notification:** When a Restore Broadcast occurs, ALL contacts receive a visible notification: "[Name] has set up a new device." If the real user did not initiate this, they can immediately alert their contacts.

**Encrypted transfer:** All chat history sent in response to a Restore Broadcast is encrypted with Per-Message KEM using the recovering device's public key (derived from the recovered seed). Exception: RESTORE_BROADCAST and RESTORE_RESPONSE themselves are signed only (not encrypted), since the recovering peer may not have the sender's current public key.

**Post-quantum key handling during restore:** The recovering device generates fresh ML-KEM-768 and ML-DSA-65 key pairs (since these cannot be derived deterministically from the seed). The Restore Broadcast includes these new PQ public keys. Contacts update their stored keys for the recovering identity upon receiving the broadcast. During the brief transition window before all contacts process the broadcast, any messages encrypted with the old PQ keys fall back to X25519-only decryption (see Section 4.3.6 for the full security analysis).

### 6.4 DHT Identity Registry (Erasure-Coded)

To recover multiple identities from a single master seed, Cleona stores an encrypted identity registry in the DHT.

#### 6.4.1 Registry Storage

**DHT Key:** `SHA-256(master_seed + "cleona-registry-id")` — determines where in the DHT the registry is stored.

**Encryption Key:** `SHA-256(master_seed + "cleona-registry-key")` — XSalsa20-Poly1305 secretbox encryption. Only someone with the master seed can decrypt the registry.

**Payload (JSON, encrypted):**
```json
{
  "active": [0, 2, 4],
  "next_index": 5,
  "names": {"0": "Alice", "2": "Work"}
}
```

#### 6.4.2 Erasure-Coded Redundancy

The encrypted registry is split using Reed-Solomon coding (N=10, K=7) and distributed across the 10 DHT nodes closest to the registry's DHT key. This ensures the registry survives even when up to 3 of those nodes are offline. Retrieval uses multiple polling rounds to collect enough fragments for reassembly.

#### 6.4.3 Recovery Flow

1. User enters recovery phrase → master seed derived.
2. Compute registry DHT key from master seed.
3. Retrieve erasure-coded fragments from DHT.
4. Reassemble and decrypt registry → list of active identity indices and display names.
5. For each identity index: derive Ed25519/X25519 keys from master seed + index.
6. Start each identity's node and trigger Restore Broadcast for each.

---

## 7. Synchronization Strategy

Cleona's synchronization is fundamentally event-driven. Unlike traditional messengers that poll servers at intervals, Cleona pushes messages through the network the instant they are created. This section describes the startup sequence, background behavior per platform, and network change recovery. (Push wake-up was considered as an additional layer and rejected; see §7.8.)

### 7.1 Design Principles

1. **Push-first:** Messages flow the moment they are created. No periodic sync intervals during normal operation. The only polling is a single startup poll after launch.
2. **Battery-aware:** Wake-up cost (radio activation, crypto operations) only occurs when there is actual work — an incoming message, an outgoing message, or a startup poll. No background timer waking the device every N minutes.
3. **Resilient recovery:** Network changes (WiFi→mobile, IP change, roaming) are detected automatically and trigger a complete recovery sequence — not just a reconnect, but a full re-establishment of routing, discovery, and pending message delivery.
4. **Platform-adaptive:** Each platform (Android, iOS, Linux, Windows) has a tailored background strategy that maximizes responsiveness within OS constraints.

### 7.2 Startup Initialization Sequence

When a node starts, it follows a deterministic initialization sequence:

```
1. Load routing table from disk (cached peer addresses)
2. Record startup timestamp (_startedAt)
3. Initialize components: DHT RPC, ACK tracker, MailboxStore, MessageQueue
4. Enumerate all local network interfaces (IP addresses)
5. Start transport (bind UDP socket)
6. Start LAN discovery (IPv4 broadcast + IPv6 multicast)
7. Start UPnP/NAT-PMP port mapping (non-blocking)
8. Register self in routing table
9. Send PING to all bootstrap seed peers
10. Wait 3 seconds for PONG responses
11. Run Kademlia bootstrap: FIND_NODE for own ID to up to 10 peers
    → Learn closer peers from responses → PING newly learned peers
12. Broadcast own PeerInfo to all known peers
13. Start background timers:
    - Maintenance timer: 60 seconds (routing table cleanup, stale peer pruning)
    - Peer exchange timer: 120 seconds (mesh discovery propagation)
    - DV safety-net timer: 1 hour (full Distance-Vector route exchange)
```

**Subnet scan fallback:** If after step 10 no recently reachable peer exists (no peer has `lastSeen > _startedAt`), a subnet scan is triggered — unicast PING probes across the local /16 network range at /24 resolution on port 41338.

### 7.3 Startup Poll

After initialization completes, the node performs a single poll to collect missed messages:

1. Send FRAGMENT_RETRIEVE to all recently-confirmed peers to collect erasure-coded fragments from DHT mailbox.
2. Simultaneously, send PEER_RETRIEVE to all recently-confirmed peers to collect Store-and-Forward whole messages (Section 3.3.7).
3. Process and deduplicate all received messages.

After this initial poll, the node switches to pure push-based operation. No further polling occurs during normal operation (except after network changes or Restore Broadcasts).

### 7.4 Sync Priority During Startup Poll

Within the startup poll window, operations are strictly prioritized:

1. Retrieve own pending message fragments from DHT mailbox (highest priority).
2. Retrieve Store-and-Forward whole messages from mutual peers.
3. Send own queued outbound messages from the persistent SendQueue.
4. Exchange peer list deltas with contacted peers (Mesh Discovery propagation).
5. Update DHT routing table with fresh peer information.
6. Forward relay fragments for other users (lowest priority, only if time remains).

### 7.5 Background Timers

Three periodic timers run during normal operation:

| Timer | Interval | Purpose |
|-------|----------|---------|
| Maintenance | 60 seconds | Routing table cleanup, stale peer pruning, mailbox housekeeping |
| Peer exchange | 120 seconds | Share peer list deltas with known peers (Mesh Discovery) |
| DV safety-net | 1 hour | Full Distance-Vector route exchange with all neighbors |

Additionally, a **welcome route update** fires 500ms after a new neighbor is detected, sending full DV routes to the newcomer. A **DV catch-up** is triggered when the last full route exchange was more than 60 seconds ago.

**Hard-Block-Update-Enforcement (V3.1.72+):** The cached manifest is consulted at every app start by `main.dart` to determine whether `UpdateRequiredScreen` should be shown as the initial route. The 6h DHT-poll keeps the cache fresh; users with stale caches see the splash on the next start after the cache refreshes. See Section 16.4.7 for full UX flow.

### 7.6 Network Change Detection & Recovery

Network changes (WiFi toggle, mobile data switch, roaming, IP change) are detected via two mechanisms:

1. **Platform events:** `connectivity_plus` on Flutter (GUI), periodic `NetworkInterface` polling on headless daemons.
2. **Mass route-down inference (V3.1.44):** When ≥3 distinct peer routes fail within 30 seconds, a network change is inferred even without OS notification. This catches silent IP changes that `connectivity_plus` misses.

**Recovery sequence** (executed when a network change is detected):

```
1. Verify IPs actually changed (skip false alarms from Android connectivity_plus)
   — Bypassed (force=true) for mass-route-down inference (ISP may change public IP without local IP change)
2. Reset NAT traversal state (public IP, port mapping)
3. Reset port mapper
4. Trigger fast discovery burst (broadcast + multicast on all interfaces)
5. Update local IP address list
6. Clear all relay routes and failure counters
7. Reset TLS fallback state (re-attempt UDP first)
8. Clear Distance-Vector routing table
9. PING all known peers with updated addresses
10. Re-run Kademlia bootstrap (FIND_NODE for own ID)
11. Broadcast address update to all contacts
12. Re-query public IP via ipify (V3.1.44: on every network change, not just startup)
13. After 5 seconds: if still no reachable peer, trigger subnet scan fallback
```

This is deliberately aggressive — a complete reset of routing state. The rationale: after a network change, all cached routes and relay paths are potentially stale. Re-establishing from scratch (which takes <5 seconds with known peers) is faster and more reliable than trying to salvage partially valid state.

### 7.7 Platform-Specific Background Behavior

**Android:** The in-process architecture runs all networking within the Flutter app. A foreground service (`CleonaForegroundService`, type `dataSync`) keeps the process alive and the UDP socket open for pushed messages. When the OS suspends the app (Doze mode), WorkManager schedules periodic wake-ups (minimum 15-minute OS interval). The foreground service with persistent notification provides near-instant delivery. Without it, messages arrive during the next WorkManager wake-up. **Lifecycle save (V3.1.44):** `CleonaAppState` implements `WidgetsBindingObserver` and calls `saveState()` (conversations, contacts, groups, channels) when `AppLifecycleState.paused` is received. This prevents data loss (e.g., media message types reverting to TEXT) when Android kills the process.

**iOS:** Background App Refresh provides periodic wake-up windows (iOS controls exact timing). During each window, the node opens its UDP socket and receives pushed messages. iOS limits background execution time; Cleona maximizes each window.

**Linux Desktop:** The daemon process (`cleona-daemon`) runs continuously as a separate process from the GUI. The UDP socket is permanently open, providing instant push delivery. The daemon survives GUI restarts. Becomes fully offline when the system enters standby. System tray icon (GTK3 + libappindicator3) provides visual status.

**Windows Desktop:** Identical architecture to Linux Desktop. The daemon runs as a user-space process (not a Windows Service) with a system tray icon (Win32 Shell_NotifyIcon). Each Windows user gets their own daemon instance with separate data in `%APPDATA%\.cleona`. The daemon starts at user login (Registry autostart) and provides the same always-on UDP connectivity as Linux. IPC via TCP loopback (127.0.0.1) with auth-token file (`cleona.port`).

### 7.8 Push Wake-Up — Rejected (Architecture Decision 2026-04-26)

A push wake-up layer (FCM, APNs, UnifiedPush, or any peer-relayed equivalent) was considered as a means to eliminate the persistent foreground-service notification on Android and the corresponding battery-optimization configuration burden. After full architectural review, all variants were rejected:

| Variant | Reason for rejection |
|---|---|
| FCM via Bootstrap relay (centralised credential holder) | Violates "no central server" — Bootstrap is itself temporary infrastructure (§18.3) |
| FCM with credentials distributed in every APK | One extracted credential enables network-wide spam through Google's quotas; Firebase project would be shut down within hours |
| Per-user Firebase project, credentials shared with wake-relay contacts | Firebase = Google = third party; user-stated constraint excludes this |
| UnifiedPush (ntfy.sh, NextPush, self-hosted) | Requires a distributor app on the recipient phone, which itself depends on a remote server; user-stated constraint excludes this |
| Per-peer WebPush+VAPID | Cannot be received natively on Android without a third-party distributor |
| Server-role rotation between Cleona peers | Solves the routing layer (which peer holds inbound responsibility) but does not bypass Android Doze; the recipient phone still requires one of the three OS wake mechanisms |

**Android wake-up reality:** The Android OS provides exactly three mechanisms for waking a Doze-suspended app: (a) FCM/APNs (Google/Apple as third party), (b) UnifiedPush distributor (third-party server behind the distributor app), (c) foreground service with persistent notification. There is no fourth path that allows a Cleona peer to wake a sleeping recipient without involving a third party.

**Decision:** Cleona accepts the persistent foreground-service notification as the canonical Android delivery mechanism. The `CleonaForegroundService` (type `dataSync`) remains the only supported background-message-delivery path on Android. The battery-optimization toggle that previously suggested otherwise was removed from settings in commit `8ec005f` (2026-04-26), as it implied user-controlled push behaviour that does not exist.

**Implications for users:**
- Persistent notification stays visible — this is the architecturally honest signal that Cleona is reachable in the background.
- Doze-whitelisting remains the user's choice via Android system settings; Cleona no longer requests or surfaces it (foreground-service-type apps are typically Doze-exempt for the duration of their foreground state regardless of whitelist).
- Real-time delivery on Android requires the app to be running. Without the foreground service (e.g., if the OS kills it), messages are picked up at the next WorkManager wake-up window (≥15 min OS-imposed minimum, see §7.7).

**Reconsideration triggers:** This decision should be revisited only if (1) Android adds a peer-to-peer wake API that does not require a third party, or (2) the user-stated "no third party" constraint is relaxed. Neither is on any visible roadmap.

---

## 8. App Permissions & Privacy

Cleona follows a strict minimum-permissions approach. No permission is requested at install time (except network access). Every other permission is requested at the exact moment the feature is first used, with a clear explanation of why it is needed. If the user denies a permission, the feature is gracefully disabled — the app never crashes or nags repeatedly.

### 8.1 Design Principles

1. **Just-in-time requests:** Permissions are requested when the user first triggers a feature, not at launch. This gives the user context for why the permission is needed.
2. **Graceful degradation:** If a permission is denied, the feature is silently disabled. No repeated prompts, no error dialogs, no loss of core functionality.
3. **No surveillance permissions:** Contacts, location, phone state, and call logs are never requested under any circumstances. Identity is purely cryptographic (Section 5.1).
4. **Platform-native channels:** Camera and audio permissions use platform-specific MethodChannels (not generic Flutter plugins) for precise control over the permission lifecycle.

### 8.2 Android Permission Model

**Declared permissions** (AndroidManifest.xml):

| Permission | Type | When Requested | Purpose |
|-----------|------|----------------|---------|
| `INTERNET` | Normal (auto-granted) | Always | UDP/TLS P2P communication |
| `ACCESS_NETWORK_STATE` | Normal (auto-granted) | Always | Network change detection |
| `FOREGROUND_SERVICE` | Normal (auto-granted) | Always | Keep daemon alive for push delivery |
| `FOREGROUND_SERVICE_DATA_SYNC` | Normal (auto-granted) | Always | Foreground service type for Android 14+ |
| `VIBRATE` | Normal (auto-granted) | Always | Message/call vibration alerts |
| `CAMERA` | Dangerous (runtime) | First photo/video capture or QR scan | Media capture, video calls, contact verification |
| `RECORD_AUDIO` | Dangerous (runtime) | First voice message or call | Voice recording, audio calls |
| `POST_NOTIFICATIONS` | Dangerous (runtime, Android 13+) | First incoming message | Message and call notifications |
| `NFC` | Normal (auto-granted) | Always (hardware feature optional) | Contact pairing, peer list merge |

**Hardware feature:** `android.hardware.nfc` is declared as `required="false"` — Cleona installs and runs on devices without NFC. The NFC contact exchange button is hidden on devices without NFC hardware.

**Foreground service:** `CleonaForegroundService` (type: `dataSync`) keeps the UDP socket alive for push message delivery. The persistent notification shows live connection status, e.g. "Connected — X peers", "Mobile — X peers", "Searching for peers…", or "Offline — no network" (actual strings come from i18n in 33 languages). Updated dynamically via MethodChannel (`updateServiceNotification`) on every state change, with dedup to avoid redundant updates. Channel importance: `IMPORTANCE_LOW` (no sound, no vibration, no badge).

### 8.3 iOS Permission Model

| Permission Key | When Requested | Usage Description |
|---------------|----------------|-------------------|
| `NSCameraUsageDescription` | First photo/video/QR | "Cleona needs camera access for photos, videos, and QR contact scanning" |
| `NSMicrophoneUsageDescription` | First voice message/call | "Cleona needs microphone access for voice messages and calls" |
| `NSPhotoLibraryUsageDescription` | First gallery pick | "Cleona needs photo library access to send images and videos" |

### 8.4 Desktop Permissions (Linux / Windows)

Desktop platforms do not use a runtime permission model. Camera and microphone access is controlled by PipeWire/PulseAudio (Linux) or Windows Audio/Video device APIs (Windows). No special permission dialogs are shown.

**External tool dependencies (Linux):**
- `wl-clipboard` / `xclip`: Required for binary clipboard paste (screenshots, images). Without them, only text paste works.
- `ffmpeg`: Required for voice transcription audio format conversion. Without it, voice messages play but show no transcription.

### 8.5 Permissions NOT Required

Cleona **never** requests:

| Permission | Why Not |
|-----------|---------|
| Contacts / Address Book | Contacts are added manually via QR, NFC, ContactSeed URI, or Mesh Discovery. No phone number or email needed. |
| Location / GPS | Never accessed. No location-based features. No geofencing. |
| Phone State / Call Logs | Cleona calls are data-only over UDP. No interaction with the cellular network. |
| Background Location | Not needed — network change detection uses `connectivity_plus`, not GPS. |
| SMS / MMS | No SMS verification. Identity is cryptographic. |
| Bluetooth | Removed from architecture (BLE presence leakage, Eclipse attack risk). Replaced by NFC. |

### 8.6 Privacy Architecture

Beyond permissions, Cleona's architecture enforces privacy at the protocol level:

- **No metadata on the wire:** Relay nodes see only encrypted fragments with mailbox IDs (Section 3.3.5). No sender identity, no timestamp, no message type.
- **No analytics:** No telemetry, no crash reporting, no usage tracking. Zero outbound connections except P2P communication.
- **No cloud dependencies:** No Google Play Services required. No Apple iCloud integration. (Push wake-up was considered and rejected; see §7.8.)
- **KEX Gate (Section 5.4):** Messages from unknown senders are silently dropped at the protocol level. No notification, no "message request" UI — invisible to the recipient.
- **Link previews:** Fetched by the sender, embedded encrypted in the message. The recipient makes zero network requests (Section 14.8, v3.1.29).

---

## 9. DoS Protection & Network Resilience

Without central infrastructure, the P2P network is vulnerable to flooding attacks where malicious nodes attempt to overwhelm peers with spam messages, fake DHT entries, or excessive relay storage demands. Cleona implements five layers of defense, each with configurable thresholds for production and test environments.

### 9.1 Design Principles

1. **Defense in depth:** Five independent layers, each sufficient to mitigate a class of attack. An attacker must defeat all five simultaneously.
2. **Asymmetric cost:** Sending costs more than receiving. PoW makes bulk spam expensive; rate limiting makes burst flooding ineffective.
3. **Local decisions:** No global ban list, no centralized authority. Each node independently evaluates its peers. Consensus emerges from independent local decisions.
4. **Graceful for legitimate peers:** Startup bursts, brief connectivity issues, and normal bootstrap traffic must not trigger false positives. Score-gated banning and relay exemptions prevent penalizing honest peers.

### 9.1 Layer 1: Proof of Work per Message

Every message entering the network must include a Proof of Work (PoW) solution. The algorithm is SHA-256 hashcash: the sender must find an 8-byte nonce that, combined with the message hash, produces a SHA-256 output with at least N leading zero bits.

```
PoW Parameters:
  Algorithm:           SHA-256(data || nonce_8byte_LE)
  Default difficulty:  20 leading zero bits (~1M hashes, 50-100ms desktop, 0.5-2s mobile)
  Minimum accepted:    16 leading zero bits (transition period)
  Verification:        Recompute hash, verify leading bits + hash match
```

**PoW Exemptions:** Three categories of messages are exempt:

1. **LAN peers** (private IP: 10.x, 172.16-31.x, 192.168.x): Messages between peers on the same local network skip PoW. Authenticated via Per-Message KEM + Ed25519. Detection uses `_isPrivateIp()` on both sides.

2. **Infrastructure messages**: GROUP_INVITE, GROUP_LEAVE, CHANNEL_INVITE, CHANNEL_LEAVE, CHAT_CONFIG_UPDATE, KEY_ROTATION, PROFILE_UPDATE, RESTORE_BROADCAST, TYPING_INDICATOR, READ_RECEIPT, DELIVERY_RECEIPT. Authenticated by signature and encryption.

3. **Relay-bound messages (V3.1.7)**: When `directBlocked` is true or no reachable active targets exist, PoW is skipped. Relay-delivered messages (from=0.0.0.0) are exempt from PoW verification on the receiver.

Only **chat content messages** (TEXT, IMAGE, FILE, VOICE, CALL_*) sent **directly** to **non-LAN peers** require PoW.

**Async PoW Computation:** PoW is computed in a separate Dart isolate via `ProofOfWork.computeAsync()`. The isolate loads libsodium independently. The UI shows the message immediately with "sending" status (hourglass) — the full send pipeline (compress → KEM encrypt → sign → PoW → send) runs asynchronously.

### 9.2 Layer 2: Rate Limiting per Node Identity

Each node tracks traffic volume per source Node-ID using a sliding time window.

```
Production Limits:
  Window:               10 seconds
  Per-source max:       200 packets / 10s
  Per-source max bytes: 2 MB (2,097,152 bytes) / 10s
  Global max:           2,000 packets / 10s
  Global max bytes:     20 MB (20,971,520 bytes) / 10s
  Max tracked sources:  500 (LRU eviction beyond this)

Test Limits:
  Window:               5 seconds
  Per-source max:       50 packets / 5s
  Per-source max bytes: 512 KB / 5s
  Global max:           500 packets / 5s
  Global max bytes:     5 MB / 5s
```

Excessive traffic from a single source is silently dropped. **Exemptions:** Relay-unwrapped inner envelopes, reassembled media chunks, and S&F-retrieved envelopes are exempt — the outer envelope was already counted against the relay/storage node's budget (V3.1.38).

**Positive reputation from accepted traffic (V3.1.38):** Every packet that passes the rate limiter generates a `recordGood` event for the sender's reputation score. This is critical because infrastructure messages (DHT, DV-Routing, PeerList, Relay) return early in the node-level switch-case and never reach the application-level handler. Without this, new peers doing normal bootstrap traffic could never build positive reputation.

### 9.3 Layer 3: Reputation System

Nodes build reputation over time based on observed behavior. Reputation is strictly local — each node independently evaluates its peers. There is no global reputation score.

```
Reputation Score Formula:
  score = goodActions / (goodActions + badActions)
  Range: 0.0 (worst) to 1.0 (best)
  New peers: 0.5 (neutral, no actions recorded)

Ban Thresholds (Production):
  Temporary ban:   badActions >= 20 AND score < 0.5 → ban for 1 hour
  Permanent ban:   badActions >= 100 AND score < 0.3 → permanent
  Max tracked:     2,000 peers (LRU eviction)

Ban Thresholds (Test):
  Temporary ban:   badActions >= 5 AND score < 0.5 → ban for 30 seconds
  Permanent ban:   badActions >= 15 AND score < 0.3 → permanent

Ban Decay:
  When a temporary ban expires, badActions *= 0.5 (rounded down).
  This prevents a single burst from creating a de-facto permanent ban.
```

**Score-gated banning (V3.1.35):** A peer with good history (score >= 0.5) is NOT temporarily banned, even with transient rate-limit violations during startup bursts. Only sustained misbehavior from low-reputation peers triggers bans.

### 9.4 Layer 4: Fragment Budgets

Each node allocates a limited relay storage budget per source Node-ID. If a single source attempts to store an excessive number of fragments, the excess is rejected with FRAGMENT_STORE_NACK. This prevents a single attacker from filling all relay storage on a victim node.

### 9.5 Layer 5: Network-Level Banning

Nodes can temporarily or permanently ban other nodes based on accumulated misbehavior. Bans are strictly local decisions — no central ban list exists. When many independent nodes ban the same attacker, the attacker becomes effectively isolated from the network through emergent consensus.

**Banned node behavior:** All packets from a banned Node-ID are dropped at the transport layer before any processing. The ban is keyed by Node-ID (not IP), so IP rotation does not bypass bans. Since Node-ID = SHA-256(network_secret + pubkey), generating a new Node-ID requires a new keypair — losing all contacts and reputation.

### 9.6 Attack Scenarios & Mitigations

| Attack | Layer(s) | Mitigation |
|--------|----------|------------|
| Spam flood (bulk messages) | 1+2 | PoW makes each message expensive; rate limiter drops excess |
| Sybil (fake identities) | 5 + Anti-Sybil | New IDs start at 0.5 reputation; Social Graph Reachability (Section 10.4.7) blocks coordinated reports |
| Fragment storage exhaustion | 4 | Per-source budget prevents monopolization |
| Relay abuse (relay others' traffic) | 2+3 | Rate limiter per source; relay traffic counts against relay node's budget |
| DHT poisoning (fake entries) | 1+3 | PoW on DHT operations; low-reputation entries deprioritized |
| Startup burst (legitimate new peer) | 2+3 | Rate limiter generates `recordGood` for accepted packets; score-gate prevents banning peers with score >= 0.5 |

---

## 10. Private Channels

### 10.1 Concept

Private Channels are invitation-only broadcast channels with a clear role hierarchy. They enable one-to-many communication (announcements, communities, interest groups) while maintaining full E2E encryption.

### 10.2 Role Model

Groups and channels share a similar but distinct role hierarchy:

**Groups** use 3 roles: Owner, Admin, Member. **Channels** use 3 roles: Owner, Admin, Subscriber.

| Role | Groups | Channels |
|------|--------|----------|
| Owner | Full control, appoints Admins, configures settings | Full control, appoints Admins, configures settings |
| Admin | Invite/remove members, moderate content, change settings | Invite/remove subscribers, moderate content, post |
| Member | Read + post | — |
| Subscriber | — | Read only |

The Owner configures whether Members can post (discussion mode) or only read (announcement mode). Channel/group settings (name, description, picture, posting policy, message expiry) can be changed by the **Owner or Admin**. This applies identically to groups and channels.

**Role updates:** `CHANNEL_ROLE_UPDATE` messages must be sent to ALL group/channel members, not just the affected member. The role update handler checks both `channelManager` and `groupManager` to find the correct entity.

### 10.2.1 Leave Semantics & Ownership Transfer (V3.1.70+)

**Conversation is removed on leave (not archived).** When a member leaves a group or channel, the local chat conversation is removed together with the membership record (`conversations.remove(id)` in `leaveGroup` / `leaveChannel`). Rationale: a former member has no way to interact with the group anymore — receiving, sending, inviting, and role changes are all gated on membership. Keeping a dead read-only archive creates "Leichen im Keller" without user-visible value, while widening the attack surface for accidental data retention.

The `staleConvs`-Cleanup on startup (`CleonaService._initState`) remains as a safety net: conversations referencing a group/channel that no longer exists in `_groups` / `_channels` are removed and re-saved. This catches edge cases where a membership record was removed through a side channel (recovery, migration) without its conversation being cleaned.

An earlier V3.1.70 fix (commit `0fddc88`, since reverted) attempted to retain the conversation as an archive. It was reverted on user feedback because the archive was unreachable via any action (no send, no re-invite), added no user value, and interacted badly with the `staleConvs`-Cleanup that would re-delete it on the next daemon restart.

**Automatic ownership transfer on Owner-leave:** If the leaving user is the Owner and other members remain, ownership is **automatically reassigned** before the GROUP_LEAVE broadcast fires. Order of promotion:

1. First member with `role == 'admin'` (insertion order of the `members` map)
2. Otherwise, the first remaining member (insertion order)

The new Owner is promoted locally (`role = 'owner'`, `group.ownerNodeIdHex = newOwner.nodeIdHex`), a `_broadcastGroupUpdate(group)` reaches the remaining members with the new role assignment, and then `GROUP_LEAVE` is sent per-member (fire-and-forget, pairwise-encrypted). Receiver-side handlers apply the same transfer logic independently to stay convergent with the new owner identity.

**Last-member-leave:** If `group.members.length == 1` at leave time (the Owner is the only remaining member), no transfer occurs, no `_broadcastGroupUpdate` is sent, and the group record is silently removed locally.

**UI safeguards against accidental leave (#U14 + follow-up 2026-04-24):** The user-facing Leave action is guarded by a two-step dialog sequence in `chat_screen.dart`:

1. **Group/Channel-info dialog** uses clearly differentiated button labels: "Abbrechen" (dialog cancel) + "Einladen" (secondary action) + "Verlassen" (destructive, FilledButton with `colorScheme.error` styling). The previous "Schließen" label was removed because users confused it with "Verlassen" — live-diagnosed via the Fehler-group incident (Handy log 2026-04-21 07:47:47 `Left group 8352ef03...`) where a user who wanted to close the dialog left the group instead.
2. **Confirmation sub-dialog** always shows before the Service is invoked. For Owners, the dialog body additionally names the automatic transfer recipient (e.g. "Owner role will be transferred to **X**.") so the consequence is visible before commit. For the last-member case, the text explains that the group will be dissolved.

Together these safeguards make accidental leave a three-click path (menu → Verlassen-button → Confirm-Verlassen) with explicit description of the destructive consequence, rather than a one-click accident.

### 10.3 Technical Implementation

**Encryption:** Pairwise E2E encryption, identical to regular group chats (see Section 4.5). Each channel post is individually encrypted and sent to each member via Per-Message KEM. Relay nodes see only encrypted fragments.

**Invitations:** The Owner or Admin generates a signed invite link or QR code. The invite contains the channel ID, channel name, optional channel picture, and optional channel description, encrypted to the invitee's public key. Only the intended recipient can join. The invite must include the complete member list so the invitee knows all participants.

**Discovery:** Private Channels are NOT listed in any public DHT index. Members can only join via direct invitation from an Owner or Admin. This makes channels legally and practically equivalent to private group chats.

**Scalability:** Pairwise encryption has O(n) cost per post. For channels with up to ~50 members this is acceptable. A future migration to MLS (RFC 9420) with O(log n) member changes is architecturally possible for larger channels.

**Media in channels:** File attachments, voice messages, and pasted clipboard content are supported via the `ChannelPost` protobuf's `content_data` field (see Section 4.5). Media is embedded directly in channel posts and sent pairwise to each member. Received media files are saved locally to the recipient's `downloads/` or `voice/` directory with image preview support in the UI.

**Profile data:** Groups and channels can have optional pictures (JPEG, max 64 KB) and descriptions. These are set during creation, included in invites, and updated via `updateGroupProfile()` / `updateChannelProfile()`. Profile data is persisted in the group/channel JSON state and included in restore responses.

### 10.4 Public Channels

Public, openly discoverable broadcast channels with decentralized content moderation.

> Full specification: `docs/CHANNELS.md`

#### 10.4.1 Channel Discovery & Index

Public channels are listed in a **compressed DHT index** (~200–300 bytes per channel). Users discover channels via a searchable "Suche" tab (default on first app start). The index stores: name, language, content rating (adult/general), description snippet, subscriber count, Bad Badge status (level + timestamps for badge set and correction submitted).

**Uniqueness:** Channel names are globally unique via `SHA-256("channel-name:" + lowercase(name))` as DHT key. First-come-first-served with squatting protection (identity must be 7+ days old).

**Channel creation fields:** Name (required, unique), Language (required: DE/EN/ES/HU/SV/multi), Public/Private toggle. Optional: image, description. For public channels, a "Not safe for minors" toggle appears (default ON — must be explicitly disabled to allow minors).

**Replication:** Each channel entry is stored on the 10 DHT nodes closest to its DHT key (standard Kademlia replication). Since entries are small (~300 bytes), simple replication is used rather than erasure coding. Channel updates (subscriber count changes, Bad Badge updates, tombstone markers) are propagated via gossip: each node storing a channel entry sends periodic updates (once per hour) to the 10 closest nodes. Tombstone entries (deleted channels) are replicated for 30 days before removal.

**Storage estimate:** 10,000 channels × 300 bytes ≈ 3 MB total index. A Bloom filter for name uniqueness checks requires significantly less.

#### 10.4.2 Content Rating & Age Verification

Public channels have a **"Not safe for minors" toggle**, which defaults to ON — the creator must explicitly disable it to make the channel available to minors. This is intentionally conservative.

Channels marked as not safe for minors are **invisible** to identities without the `isAdult` flag (self-declaration, see Identity Detail Screen). These channels do not appear in search results and cannot be subscribed to or read without the flag.

#### 10.4.3 Roles for Public Channels

Public channels add a new role **"Everyone"** (all network users):

| Role | Read | Post | Admin |
|------|------|------|-------|
| Owner | ✓ | ✓ | ✓ |
| Admin | ✓ | ✓ | partial |
| Subscriber | ✓ | ✗ | ✗ |
| **Everyone** | ✓* | ✗ | ✗ |

\* Restricted: NSFW channels require `isAdult` flag for read access.

#### 10.4.4 Decentralized Content Moderation

Six report categories: Not safe for minors (mislabeled), Wrong content (doesn't match description), Illegal: drugs, Illegal: weapons, Illegal: CSAM, Illegal: other.

**Single post reports** → Channel admins are notified; escalation to channel-level report after 7 days if unresolved.

**Channel-level reports** → Reporter selects 3-10 specific posts as evidence. When the report counter reaches a threshold, a **jury of 5-11 randomly selected users** reviews the evidence and votes with 2/3 majority required. Jury members have 2 days to respond; abstentions and timeouts are replaced.

**Jury language selection:** The language for jury selection comes from the **reported channel's language field** (set at creation, stored in the DHT index), not from any attribute on the juror's identity. A node is eligible for jury duty if it subscribes to at least one channel with the same language setting — a behavioral proxy for language competence that requires no metadata on the identity itself. For channels with `language: multi`, nodes of all languages are eligible. This preserves the anonymity principle (Section 5.1): no language attribute is stored on or published with any identity. Eligibility is determined locally from the node's own subscription list and answered as a simple yes/no to jury requests.

**Consequences:** NSFW reclassification, Bad Badge (3-stage escalation), or Tombstone deletion (DHT entry marking channel as removed).

#### 10.4.5 Bad Badge System

A trust signal for misleading channel descriptions. 3-stage escalation:

| Stage | Trigger | Label | Probation |
|-------|---------|-------|-----------|
| 1 | First confirmed report | "Content questionable" | 30 days after admin correction |
| 2 | Second confirmed report during probation | "Repeatedly misleading" | 90 days after correction |
| 3 | Third confirmed report | **Permanent** | — |

Badge stays until admin corrects name/description. After correction, probation phase starts. Channels with badges are **never hidden** — only deprioritized in search with visual warning.

#### 10.4.6 CSAM Special Procedure

CSAM (child sexual abuse material) cannot use the standard jury procedure because viewing CSAM is itself a criminal offense. Instead: **graduated response based on independent reporter count** with no jury.

| Stage | Trigger | Action |
|-------|---------|--------|
| 1 | First report | Registered, no visible action |
| 2 | `max(10, subscribers × 0.05)` independent reports | Channel **temporarily hidden** from search (14-day window), admin can file objection |
| 3 | `max(20, subscribers × 0.10)` independent reports | Channel **permanently deleted** (Tombstone) |

**Example thresholds:** 50 subscribers → 10/20 reporters; 500 subscribers → 25/50 reporters; 5,000 subscribers → 250/500 reporters. Minimum is always 10 for temporary, 20 for permanent — always double-digit.

**Admin objection (Stage 2):** When temporarily hidden, the admin can file an objection. This triggers a jury, but the jury does NOT see the content. Instead, they review: channel name/description, posting frequency, reporter text descriptions, and whether the channel's topic plausibly relates to CSAM allegations. The jury decides: "Plausible" (hiding maintained) or "Appears fabricated" (channel restored). This gives legitimate channel operators a defense against coordinated false reports.

**Elevated reporter requirements (CSAM only):** 30-day identity age, 10+ bidirectional conversations, 100+ received messages, 3+ long-term contacts (14+ days), `isAdult` flag required, 7-day reporting cooldown across all categories.

**Anti-abuse (Option C):** 7-day reporting cooldown as "stake" + strikes only for demonstrably malicious reports (channel restored AND reporter discovered channel shortly before reporting). 3 strikes = CSAM reporting permanently disabled for that identity.

#### 10.4.7 Anti-Sybil: Social Graph Reachability Check

Open-source code enables bot software that creates fake identities with simulated social activity to file coordinated false reports. Defense: **network-level validation** of the reporter's social graph connectivity.

**Independence criteria (size-based):** Two identities are considered "connected" if they share a group/channel with fewer than `max(50, total_users × 0.05)` members. Direct contacts are always connected. This is size-based, not public/private-based — a private group with 500 members indicates no more coordination than a public channel with 500 subscribers.

**Reachability algorithm:** When a CSAM report is filed, K random validator nodes check whether they can reach the reporter's identity within 5 hops through their social graph. If ≥60% of validators can reach the reporter, the report is accepted. Bot clusters form isolated islands with no paths to the real network, causing validator checks to fail.

**Privacy:** Each node maintains a Bloom filter of contacts up to depth 5. Reachability is a local lookup (yes/no), not a graph traversal. No social graph data is exposed.

**Critical: Network validation, not app validation.** All checks are performed by receiving nodes, not the reporter's app. A modified client (fork) can submit a report, but the network ignores it if criteria are not met.

#### 10.4.8 ModerationConfig: Configurable Thresholds & Test Presets

All moderation timeouts, thresholds, and qualification requirements are centralized in a single configuration class (`lib/core/moderation/moderation_config.dart`). This enables:

- **Production preset:** Real-world values (2-day jury timeout, 30/90-day probation, 7-day identity age, etc.)
- **Test preset:** Drastically shortened values for automated E2E testing (10s jury timeout, 30s probation, no identity age requirement, anti-Sybil disabled)

**Why this matters:** The moderation system involves time spans ranging from seconds (PoW) to months (badge probation). Without configurable presets, automated tests would be impossible — a jury timeout of 2 days cannot be tested in CI.

**Key differences between presets:**

| Parameter | Production | Test |
|-----------|-----------|------|
| Jury vote timeout | 2 days | 10 seconds |
| Jury minimum size | 5 | 3 |
| Report threshold for jury | 3 reports | 1 report |
| Badge probation (stage 1) | 30 days | 30 seconds |
| Badge probation (stage 2) | 90 days | 60 seconds |
| CSAM temp hide duration | 14 days | 20 seconds |
| CSAM reporter cooldown | 7 days | 5 seconds |
| Identity min age | 7 days | 0 |
| Identity min age (CSAM) | 30 days | 0 |
| CSAM min bidirectional partners | 10 | 0 |
| Anti-Sybil reachability | ON (60%, 5 hops) | OFF |
| Single post escalation | 7 days | 15 seconds |
| Squatting protection | 7 days | 0 |

The config also provides calculation methods: `independenceThreshold(totalUsers)`, `effectiveJurySize(availableJurors)`, `csamStage2Threshold(subscribers)`, `csamStage3Threshold(subscribers)`, `hasJuryMajority(votesFor, totalVotes)`, and time-based checks (`isJuryVoteExpired`, `isProbationComplete`, etc.).

**Enums:** `ReportCategory` (6 categories), `JuryVote` (approve/reject/abstain), `JuryConsequence` (reclassifyNsfw/addBadBadge/deleteChannel/noAction), `BadBadgeLevel` (none/questionable/repeatedlyMisleading/permanent).

### 10.7 Moderation Timer

All time-based moderation limits are enforced by a **periodic timer** (`_moderationTimer`) in `CleonaService`. Without this timer, time-dependent actions (badge expiry, jury timeouts) would only fire when triggered by unrelated events — which in production (30-day probation, 2-day jury timeout) might never happen.

**Timer interval:** Adaptive — 1/6 of the shortest configured timeout, clamped to [5 seconds, 5 minutes]. When the test preset is active with sub-5-second timeouts, the timer ticks every 1 second.

**Four checks per tick:**

1. **Jury vote timeout:** Active jury sessions that exceed `juryVoteTimeout` are resolved with whatever votes have been cast (partial quorum).
2. **Badge probation:** Channels with `correctionSubmitted=true` and `badBadgeSince` older than the probation period (`badgeProbationLevel1` / `badgeProbationLevel2`) have their badge level decremented.
3. **CSAM temp-hide lift:** Channels with `isCsamHidden=true` and `csamHiddenSince` older than `csamTempHideDuration` are unhidden.
4. **Single-post escalation:** Pending `PostReport` entries older than `singlePostEscalationTimeout` are escalated to `ChannelReport` entries and checked against the jury threshold.

**Cleanup:** Completed jury sessions are discarded after 1 hour.

**Config switch:** When `moderationConfig` is changed via IPC (`set_moderation_config`), the timer is automatically restarted with the new interval.

---

## 11. Network Statistics Dashboard

Cleona provides a dedicated, scrollable statistics page accessible from the sidebar or settings. This dashboard embodies Cleona's transparency philosophy by giving users real-time insight into the P2P network's health and their own contribution. The dashboard auto-refreshes every 5 seconds. All UI strings are fully localized (33 languages).

### 11.1 Design Principles

1. **Full transparency:** Users see exactly what their node is doing — how much data it stores for others, how many peers it knows, what its latency looks like. No hidden activity.
2. **Health at a glance:** A single color-coded badge (green/yellow/red) summarizes network health without requiring technical knowledge.
3. **Privacy-preserving metrics:** All statistics are computed locally from the node's own observations. No metrics are shared with other nodes or external services.

### 11.2 Section 1: Network Health & Active Nodes

| Metric | Source | Description |
|--------|--------|-------------|
| Active peer count | `activePeerCount()` | Peers seen within last 120 seconds (not total ever-seen) |
| Total known peers | `totalKnownPeers` | All peers in routing table (14-day pruning window) |
| NAT type | `natType` | Detected NAT type (Full Cone, Restricted, Symmetric, etc.) |
| Public IP:Port | `publicIp`, `publicPort` | Externally visible address (from peer-reported STUN) |
| Uptime | `uptime` | Time since daemon start, formatted as "Xh Ym" |
| Status | online/offline | Current connectivity state |

**Health badge thresholds:**

| Active Peers | Badge | Label |
|-------------|-------|-------|
| ≥ 10 | Green | "good" |
| 3–9 | Yellow | "warning" |
| < 3 | Red | "critical" |

**Network size estimation:** Since no single node has a complete view, the total network size is estimated via random DHT address space sampling: the node queries multiple random 256-bit IDs distributed across the address space and measures the density of responses. From the observed node density in sampled address regions, the total network size is estimated statistically.

### 11.3 Section 2: Personal Data Usage

| Metric | Granularity | Description |
|--------|-------------|-------------|
| Bytes sent (total) | Lifetime | Total outbound traffic |
| Bytes received (total) | Lifetime | Total inbound traffic |
| Bytes sent today | Daily reset | Today's outbound traffic |
| Bytes received today | Daily reset | Today's inbound traffic |
| Messages sent | Lifetime counter | Total chat messages sent |
| Messages received | Lifetime counter | Total chat messages received |

### 11.4 Section 3: Relay Contribution

| Metric | Description |
|--------|-------------|
| Fragments stored | Erasure-coded fragments currently held for other users |
| Messages relayed | Lifetime counter of successfully relayed messages |
| Relay data volume | Total bytes relayed for other users |
| Storage used | Current on-disk storage in bytes (messages + fragments + DB) |
| Database size | SQLite database file size |

### 11.5 Section 4: Connection Details (Technical)

| Metric | Description |
|--------|-------------|
| Direct connections | Number of currently active direct peer connections |
| Routing table size | Total peers in DHT routing table |
| Average latency | Mean RTT to all reachable peers (ms) |
| Min/Max latency | Lowest and highest observed RTT |
| K-bucket fill | Bar chart: peer count per k-bucket (capacity: 20 per bucket) |
| Peer latencies | List of top 10 peers with individual RTT values |

**K-bucket visualization:** A bar chart where each bar represents one k-bucket in the Kademlia routing table. Bar height scales from 0 to capacity (20 peers). Tooltip shows bucket index and current fill ratio. This gives advanced users immediate insight into routing table balance — uneven fill indicates proximity clustering in DHT address space.

### 11.6 Data Collection

All metrics are collected by a `NetworkStatsCollector` component in `CleonaService`. The collector:

- Tracks bytes sent/received at the transport layer (every UDP/TLS send/receive)
- Counts messages at the application layer (every processed envelope)
- Samples latency from ACK round-trip times (RTT-EMA in `AckTracker`)
- Polls routing table fill status from `RoutingTable.getBucketStats()`
- Persists counters to disk periodically (survives daemon restarts)

**Privacy:** No metrics are shared with any other node. The dashboard is purely a local view of the node's own activity. There is no telemetry, no analytics endpoint, no crash reporting.

---

## 12. Technology Stack

### 12.1 Design Principles

1. **No cloud dependencies:** Every library runs on-device. No Google Play Services required. No Firebase. No external APIs. (Push wake-up via Firebase was considered and rejected; see §7.8.)
2. **FFI for performance-critical code:** Cryptography, compression, audio/video codecs, and speech recognition use native C/C++ libraries via Dart FFI. Pure Dart fallbacks exist where feasible (Reed-Solomon).
3. **Cross-platform via Flutter:** A single Dart codebase targets Linux, Windows, Android, and iOS. Platform-specific code is isolated in `lib/core/platform/` and `lib/core/tray/`.

### 12.2 Application Framework

| Component | Technology | Version | Rationale |
|-----------|-----------|---------|-----------|
| Framework | Flutter (Dart) | SDK ≥3.11.0 | Single codebase for 4 platforms, native performance, rich widget system |
| State management | Provider | ^6.1.0 | Simple, well-tested, no boilerplate |
| Serialization | Protocol Buffers (protobuf) | ^4.0.0 | Compact binary format, schema evolution, language-neutral |
| Database | SQLite via drift ORM | — | Embedded, zero-config, encrypted at rest |
| UUID generation | uuid | ^4.0.0 | RFC 4122 v4 for message and event IDs |

### 12.3 Native Libraries (FFI)

| Library | Dart FFI Binding | Provides | Notes |
|---------|-----------------|----------|-------|
| **libsodium** | `sodium_ffi.dart` | Ed25519, X25519, AES-256-GCM, XSalsa20-Poly1305, SHA-256, HMAC-SHA256, HKDF, Argon2id, BLAKE2b | System package (`libsodium-dev`). 32-byte keys, 64-byte sigs. |
| **liboqs** | `oqs_ffi.dart` | ML-KEM-768 (post-quantum KEM), ML-DSA-65 (post-quantum signatures) | Built from source (not in distro repos). `OQS_init()` required before first use. |
| **libzstd** | `compression.dart` | Zstandard compression/decompression | System package (`libzstd-dev`). All payloads compressed before encryption. |
| **liberasurecode** | `reed_solomon.dart` | Reed-Solomon erasure coding (N=10, K=7) | System package. Pure Dart fallback on platforms without it. |
| **libwhisper** | `whisper_ffi.dart` | On-device speech-to-text (whisper.cpp) | Built from source + GGML deps. Optional — voice messages work without it. |
| **libopus** | `opus_ffi.dart` | Opus audio codec (legacy v2.8 path) | Retained as a build artefact for the prior FFI binding; the live audio path now uses raw PCM via `libcleona_audio` (§4.4.4). May be reintroduced behind the shim later for metered links. |
| **libvpx** | `vpx_ffi.dart` (via cleona_vpx shim) | VP8 video codec (I420/YUV 4:2:0, CBR, real-time) | For video calls. Adaptive bitrate. Error-resilient mode. |
| **miniaudio** | via `libcleona_audio` C shim | Cross-platform audio capture + playback (PulseAudio/ALSA on Linux, AAudio/OpenSL on Android, WASAPI on Windows, Core Audio on macOS/iOS) | Single-header library, version 0.11.21, vendored at SHA256 `6b2029714f8634c4d7c70cc042f45074e0565766113fc064f20cd27c986be9c9`. See §4.4.4. |
| **speexdsp** | via `libcleona_audio` C shim | Acoustic Echo Cancellation + Noise Suppression for the audio capture path | Version 1.2.1, **vendored as full source** under `native/cleona_audio/vendor/speexdsp/` (SHA256 `d17ca363654556a4ff1d02cc13d9eb1fc5a8642c90b40bd54ce266c3807b91a7`), statically linked. AEC tail = 250 ms @ 16 kHz. |

### 12.4 Flutter Packages

| Package | Version | Purpose |
|---------|---------|---------|
| `connectivity_plus` | ^6.0.0 | Network state detection (WiFi/mobile/none) |
| `qr_flutter` | ^4.1.0 | QR code generation for ContactSeed |
| `mobile_scanner` | ^6.0.0 | QR code scanning (camera-based) |
| `video_player` | ^2.11.1 | Inline video playback in chat |
| `just_audio` | ^0.10.5 | Audio playback (voice messages, notifications) |
| `record` | ^6.2.0 | Voice message recording (AAC encoder) |
| `image_picker` | ^1.0.0 | Camera capture and gallery access |
| `file_picker` | ^8.0.0 | File selection dialog |
| `desktop_drop` | ^0.7.0 | Drag-and-drop file support (desktop) |
| `emoji_picker_flutter` | ^4.4.0 | Emoji picker with categories, search, skin tones |
| `nfc_manager` | ^3.5.0 | NFC contact exchange (Android) |
| `url_launcher` | ^6.3.2 | Open URLs in browser (normal/incognito) |
| `printing` | ^5.14.3 | PDF generation for seed phrase backup |
| `shared_preferences` | ^2.2.0 | Persistent settings storage |
| `path_provider` | ^2.1.0 | Platform-specific directory paths |

### 12.5 External Tools (Runtime)

| Tool | Platform | Purpose | Required? |
|------|----------|---------|-----------|
| `ffmpeg` | Linux/Windows | Audio format conversion (AAC/OGG → WAV 16 kHz PCM) for whisper.cpp | Optional (voice transcription only) |
| `wl-clipboard` | Linux (Wayland) | Binary clipboard paste (screenshots, images) | Optional (text paste works without) |
| `xclip` | Linux (X11) | Binary clipboard paste (screenshots, images) | Optional (text paste works without) |
| `pw-play` | Linux (PipeWire) | Notification sounds, ringtones | Falls back to `paplay` (PulseAudio) |

### 12.6 Platform Targets

| Platform | Role | Architecture | Binary |
|----------|------|-------------|--------|
| Linux Desktop (x86_64) | Primary development | Daemon + GUI (separate processes, IPC via Unix socket) | `cleona-daemon` + `cleona` (Flutter bundle) |
| Windows Desktop (x86_64) | Test | Daemon + GUI (IPC via TCP loopback + auth-token) | `cleona-daemon.exe` + `cleona.exe` |
| Android (arm64-v8a, x86_64) | Release | In-process (single Flutter app) | APK with jniLibs |
| iOS (arm64) | Release (planned) | In-process | IPA |

---

## 13. Localization & Internationalization

Cleona supports 33 languages including 3 RTL scripts. The localization system is built entirely in Dart — no platform-specific resource files (no Android `strings.xml`, no iOS `Localizable.strings`). All translations live in a single compile-time constant map, enabling instant language switching without app restart.

### 13.1 Design Principles

1. **Single source of truth:** All translations are in `lib/core/i18n/translations.dart` as a compile-time `const Map<String, Map<String, String>>`. No external files, no asset loading, no build step.
2. **Instant switching:** Language changes take effect immediately via `ChangeNotifier`. No restart, no page reload. The user sees the entire UI update in real time.
3. **System language detection:** On first launch, Cleona reads `Platform.localeName` and auto-selects the matching language. English is the fallback if the system locale is not supported.
4. **RTL-first:** RTL is not an afterthought. The entire widget tree is wrapped in a `Directionality` widget that switches between `TextDirection.ltr` and `TextDirection.rtl` based on the active locale.
5. **Full coverage policy (V3.1.70+):** Every translation key must carry a real string in all 33 supported locales. English-fallback at key-addition time ("`ar`, `he`, `fa` will pick up `en` via the runtime fallback chain") is not permitted. The historical pattern of shipping new features with only DE/EN or DE/EN/ES/FR has been eliminated — any remaining gap is treated as a bug. The enforcement is `scripts/check_i18n_complete.dart`, run as a pre-commit / pre-push hook and a CI gate on every change that touches `translations.dart`. The runtime fallback chain in `AppLocale.get` remains as a defence-in-depth safety net against emergency misses (missing key after a refactor, new key referenced before translation), but it is not the expected path.

### 13.2 Supported Languages (33)

| Group | Languages |
|-------|-----------|
| Original 5 | German (de), English (en), Spanish (es), Hungarian (hu), Swedish (sv) |
| RTL (3) | Arabic (ar), Hebrew (he), Farsi/Persian (fa) |
| Western Europe (7) | French (fr), Italian (it), Portuguese (pt), Dutch (nl), Danish (da), Finnish (fi), Norwegian (no) |
| Eastern Europe (8) | Polish (pl), Romanian (ro), Czech (cs), Slovak (sk), Croatian (hr), Bulgarian (bg), Greek (el), Turkish (tr) |
| Slavic (2) | Ukrainian (uk), Russian (ru) |
| East Asia (3) | Chinese Simplified (zh), Japanese (ja), Korean (ko) |
| South/Southeast Asia (5) | Hindi (hi), Thai (th), Vietnamese (vi), Indonesian (id), Malay (ms) |

### 13.3 Implementation

**Translation key structure:** Snake_case English identifiers mapping to locale-specific strings. ~640 unique keys covering all UI elements: buttons, labels, dialogs, error messages, settings, notifications, moderation, channels, calls, calendar, polls, and system messages.

```
translations['message_sent'] = {
  'de': 'Nachricht gesendet',
  'en': 'Message sent',
  'ar': 'تم إرسال الرسالة',
  'ja': 'メッセージ送信済み',
  ...  // 33 locales
};
```

**AppLocale** (`lib/core/i18n/app_locale.dart`):

```
class AppLocale extends ChangeNotifier {
  get(String key)              → Translation with fallback chain
  tr(String key, Map params)   → Parameterized translation ({name} → value)
  setLocale(String code)       → Switch locale, persist, notify listeners
  isRtl                        → true for ar, he, fa
  textDirection                → TextDirection.rtl or .ltr
}
```

**Fallback chain (defence-in-depth, not the expected path):** Current locale → `en` → `de` → key itself (raw key name as last resort). Per §13.1-5, every new key is expected to have a real translation in all 33 locales — `scripts/check_i18n_complete.dart` enforces this in CI. The runtime fallback chain exists only to avoid a crash in the edge case where coverage check was bypassed or a new key was referenced before being translated.

**Persistence:** Selected locale is stored in `SharedPreferences` with key `'cleona_locale'`. On app start, the saved locale is loaded; if none saved, system language detection runs.

### 13.4 RTL Support (V3.1.36)

Arabic, Hebrew, and Farsi use Right-to-Left layout. The implementation uses Flutter's built-in RTL infrastructure:

- `AppLocale.isRtl` returns `true` for `ar`, `he`, `fa`
- `AppLocale.textDirection` returns the appropriate `TextDirection`
- A `Directionality` widget wraps the entire `MaterialApp` in the widget tree
- Flutter automatically mirrors: navigation arrows, padding/margins, text alignment, list item layouts, message bubble alignment (sent = left in RTL, received = right)
- The language selector in the AppBar uses flag emojis for universal recognition regardless of reading direction

### 13.5 Language in Protocol Context

Language codes appear in three protocol contexts:

1. **Channel language** (Section 10.4.1): Set at channel creation, stored in DHT index. Used for jury language selection in moderation.
2. **Voice transcription language** (Section 15.8): Configurable per identity. Passed to whisper.cpp for speech recognition. Default: auto-detect.
3. **ContactSeed URI**: No language tag — contact exchange is language-neutral.

---

## 14. Feature Roadmap

### 14.1 Development Sub-Phases

The original three-phase roadmap has been refined into sub-phases for incremental development and testing:

| Sub-Phase | Name | Scope | Status |
|-----------|------|-------|--------|
| 0 | Project Scaffold | pubspec, proto, FFI stubs, .gitignore | Complete |
| 1a | Bootstrap & Network Core | DHT, routing, UDP transport, RUDP ACK, bootstrap, LAN discovery | Complete |
| 1b | Messaging & Erasure Coding | Text messaging, Reed-Solomon, ACK-driven fragment delivery, offline delivery | Complete |
| 1c | Encryption | Per-Message KEM (X25519 + ML-KEM-768), key rotation, DB encryption | Complete |
| 1d | Media, Channels & Policies | Channels, media transfer, per-chat policies | Complete |
| 1e | Contact Requests & Identity | Contact request protocol, multi-identity, PoW, message gate | Complete |
| 1f | Service Architecture | CleonaService, KeyManager, 4-node integration | Complete |
| 2 | Enhanced Comm + GUI | Reactions, receipts, reply/forward, voice, file, edit/delete, link preview, i18n, privacy, media in groups/channels, image preview, clipboard paste, chat config, favorites, download/save, profile pictures & descriptions, identity deletion, NAT traversal, network change detection | Complete |
| 2.5 | Public Channels & Moderation | Public channels, DHT channel index, decentralized moderation (jury system, CSAM procedure, Bad Badge), anti-Sybil | Complete |
| 2.6 | Chat UX & Maintenance | Video/audio player, voice recording, drag & drop, URL detection, image zoom, donation screen, update manifest, release signing | Complete |
| 2.8 | Archive, Voice, Sybil, Calls 3a | Media Auto-Archive, Voice Transcription, Anti-Sybil Transport-Layer, Calls Phase 3a (HKDF, Jitter, Opus, Mute, Timeout) | Complete |
| 3 | Calls & Multi-Platform | Voice/video calls (overlay multicast tree + LAN multicast), desktop clients, disappearing messages | Planned |

### 14.2 Phase 1: Full-Featured Messenger (MVP)

**Messaging:** Text messaging in 1:1 and group chats (pairwise E2E encrypted). Full Unicode emoji set with emoji picker. Image sharing with in-chat preview (thumbnail in message bubble, tap for fullscreen with pinch-to-zoom via InteractiveViewer). File attachments with click-to-open (xdg-open). Voice messages with recording and playback. Clipboard paste support (Ctrl+V interception for binary content such as screenshots).

**Camera:** In-app photo capture (rear and front camera). In-app video recording. Gallery picker for existing media. Basic editing: crop and rotate.

**Channels:** Private Channels with invitation-only access and role-based permissions (Owner/Admin/Subscriber). Pairwise E2E encryption (see Section 4.5). Configurable posting mode (announcement or discussion). Full media support: file attachments, voice messages, and clipboard paste in channels.

**Per-Chat Policies:** Configurable message expiry timer per conversation (never/5min/1h/24h/7d/30d/1y/custom). Configurable message editing window per conversation (never/5min/10min/1h/always).

**Infrastructure:** Erasure-coded offline delivery (N=10, K=7). Hybrid post-quantum encryption (Per-Message KEM: X25519 + ML-KEM-768). Five-layer DoS protection. Mesh Discovery (IPv6 Multicast, IPv4 Local Broadcast, NFC, QR, peer list file). Identity recovery (24-word phrase + Social Recovery). Restore Broadcast. Adaptive background sync. Network change detection (connectivity_plus, AppLifecycleListener, IP polling). Biometric/PIN app lock. Network stats dashboard. Data compression (zstd). 30+ language support with RTL.

### 14.3 Phase 2: Enhanced Communication (Complete)

All Phase 2 features are implemented:

**Communication:** Voice messages with recording. Document/file sharing (any file type). Link previews with thumbnails. Emoji reactions on messages. Message forwarding and quoting (reply with quoted text). Read receipts, delivery receipts, and typing indicators (optional, privacy-respecting). Message editing and deletion. Per-chat message expiry and editing window policies. Per-chat configuration protocol with mutual consent for DMs (download/forwarding permissions via CHAT_CONFIG_UPDATE/RESPONSE). Full i18n support (33 languages including 3 RTL scripts — see §13) with flag selector and instant language switching. Image preview in chat bubbles with fullscreen viewer and error handling. Clipboard binary paste (screenshots, images) via wl-clipboard/xclip. Media support in groups and channels via ChannelPost content_data. Download/save buttons on received files with self-copy protection. Favorites tab alongside Recent for conversation organization. Platform-aware default download directory (OS ~/Downloads on desktop, app-internal on mobile).

**Profile & Identity:** Profile pictures (JPEG, max 64 KB) and descriptions (max 500 chars) for identities, contacts, groups, and channels. PROFILE_UPDATE broadcast to all contacts on changes. Profile data exchanged in contact requests, restore responses, and group invites. Identity deletion with IDENTITY_DELETED notification to all contacts.

**Security:** Post-quantum database encryption at rest (XSalsa20-Poly1305 with SHA-256 derived key). Automatic migration from unencrypted to encrypted DB. NAT traversal with peer-reported public addresses and UDP hole punching. IPv6 multicast discovery (ff02::1, 46-byte HMAC-authenticated CLEO packets). IPv4 local broadcast discovery (port 41338). Network change detection with automatic NAT reset, fast discovery burst, and DHT re-bootstrap (connectivity_plus on Flutter, IP polling on headless).

**Recovery:** Erasure-coded DHT identity registry (RS N=10, K=7). HD-wallet multi-identity key derivation from master seed. Aggressive mailbox polling after restore (10 polls at 3s intervals). Social Recovery / Shamir SSS (5 guardians, 3/5 threshold). Real printing support for seed phrase backup.

**Visual & UX:** Identity Skins (10 predefined visual themes per identity, with WebP hero/avatar/FAB assets where present and CSS-gradient fallback otherwise — V3.1.70 design system; Crimson was deprecated and split into Fire and Storm). ContactSeed QR (generation + scanning). Network Statistics Dashboard.

### 14.4 Phase 3: Calls & Multi-Platform — Complete

Voice and video calls implemented with libopus (audio) and libvpx VP8 (video) over the existing UDP transport — **not WebRTC**. See §4.4 (Call Encryption with HKDF-derived keys) and §12 (`opus_ffi.dart`, `JitterBuffer`). Group calls use Overlay Multicast Trees (§4.4). Desktop clients ship for Linux and Windows; Android via the in-process architecture (§18.2); macOS port v1 in progress (no tray, no calls, no video in v1). Multi-device sync (§26) including Twin-Sync, Device Revocation, and Emergency Key Rotation is complete since V3.1.44. Per-chat message expiry was already delivered in Phase 2 (§14.3) and is not re-listed here.

**Cross-platform audio (V3.X #U10b):** Audio capture and playback now run uniformly on Linux + Android + Windows through `libcleona_audio.so` (miniaudio + speexdsp; see §4.4.4). The previous Linux-only PulseAudio FFI path has been retired — Android audio, which `docs/CALLS.md §7.2` had listed as "geplant", is now live. macOS and iOS are architecturally ready (miniaudio Core Audio backend) and will follow once the build infrastructure is wired in.

### 14.5 Plain TCP Removed, TLS Fallback on Same Port as UDP (V3.2 / V3.1.71)

Plain TCP was removed in V3.2. All normal traffic uses UDP exclusively. Rationale: plain TCP cannot be relayed, cannot deliver offline (Store-and-Forward), and RUDP Light already guarantees delivery confirmation and integrity (Per-Message KEM + SHA-256 content hashes). App-level UDP fragmentation handles payloads >1200 bytes.

**TLS fallback (anti-censorship) is retained on the SAME port number as UDP** (V3.1.71, previously port+2). When UDP is completely blocked (corporate firewalls, censored countries), the TLS fallback activates automatically after 15 consecutive UDP failures. Periodic UDP probes attempt recovery. This ensures connectivity even in restrictive network environments.

**Why same port, not port+2:** UDP (SOCK_DGRAM) and TCP (SOCK_STREAM) are distinct socket types; the kernel's port allocation keeps them in separate namespaces, so `bind(udp, 8080)` and `bind(tcp, 8080)` are independent operations with no collision. Reusing the same port number collapses the firewall-configuration surface to a single hole per node and makes port-forward rules on upstream routers trivially correct. The bootstrap nodes run UDP+TCP 8080 (Live channel) and UDP+TCP 8081 (Beta channel). Mobile and desktop nodes bind both protocols to the same randomly-chosen ephemeral port picked at first launch and persisted per identity.

**Migration V3.1.70 → V3.1.71:** Nodes running V3.1.70 or older listen for TLS on port+2; V3.1.71+ nodes listen on the UDP port. During a mixed-version rollout the TLS fallback is temporarily incompatible across major-version boundaries. Since TLS only activates after 15 consecutive UDP failures, normal traffic is unaffected — the gap only shows up for peers that have fully lost UDP. Closed-network deployments (the only production case) resolve this by updating all nodes in lockstep.

**Self-Healing TLS Listener (V3.1.54):** `SecureServerSocket.bind()` can transiently fail with `Address already in use` when the previous process's TCP socket is still in `TIME_WAIT` — a common situation after an ungraceful restart. Previously the bind failure was logged once and the listener stayed permanently dead, silently breaking the anti-censorship fallback for hours until manual restart. `Transport` now schedules a rebind attempt with exponential backoff (5s → 10s → 30s → 60s cap, self-rescheduling until both IPv4 and IPv6 sockets are bound). A sentinel `_tlsContextUnavailable` disables rebind when the TLS context itself is permanently unavailable (e.g. `openssl` binary missing on Android) to prevent log spam.

**TLS as transparent transport replacement:** When the TLS fallback is active for a specific peer, TLS replaces UDP as the transport layer for that peer. All message types — including FRAGMENT_STORE, FRAGMENT_STORE_ACK, DELIVERY_RECEIPT, PEER_STORE, ROUTE_UPDATE — are sent over the TLS connection. The RUDP Light layer (ACK tracking, timeout-based route-down detection) remains active even over TLS. Although TLS itself provides reliable delivery, RUDP Light over TLS serves a different purpose: **application-level reachability detection**. If a DELIVERY_RECEIPT is missing, the peer is unresponsive at the application layer (crashed, offline) even though the TLS connection may still be open.

**Erasure-coded fragments over TLS:** Fragments are sent individually as FRAGMENT_STORE over the TLS connection. App-level UDP fragmentation (Section 2.9.10, >1200 bytes) is not needed over TLS since TLS has no MTU limitation — fragments can be sent at full size. The `compression` flag and KEM header behavior remain identical to UDP.

**UDP recovery probes:** Even with an active TLS fallback, the node periodically sends a UDP probe to check whether UDP has become available again. The interval uses exponential backoff starting at 1 minute, doubling per attempt up to a 30-minute cap (1, 2, 4, 8, 16, 30, 30, … minutes — `_baseProbeInterval` / `_maxProbeInterval` in `tls_fallback.dart`). On success, the node switches back to UDP (preferred transport), tears down the TLS connection, and the probe-attempt counter resets.

For future large-scale networks (millions of peers), a sliding-window congestion control on top of RUDP Light is planned.

### 14.6 Public Channels & Moderation (Complete — v2.6)

Public channels with decentralized content moderation are fully implemented (see Chapter 10.4 and `docs/CHANNELS.md`). Key components: DHT-based channel index with gossip propagation, content rating with age verification (isAdult self-declaration), jury-based moderation (5-11 random jurors, 2/3 majority), CSAM special procedure (staged thresholds, reporter cooldown, 3-strikes ban, dispute mechanism), Bad Badge 3-stage escalation with probation periods (30/90 days), anti-Sybil Social Graph Reachability Check (Bloom filter, 5 hops, 60% threshold), channel search with language/content-rating filter, tombstone tracking for deleted channels, melder qualification enforcement (identity age, bidirectional contacts). 210 smoke tests (154 moderation + 56 public channels).

### 14.7 v2.8: Archive, Voice Transcription, Anti-Sybil Transport, Calls Phase 3a (Complete)

Four major features implemented with full test coverage (980 tests total: 513 smoke + 467 E2E GUI).

**Media Auto-Archive:** `ArchiveManager` orchestrates periodic archive checks with SSID-based network detection, tiered storage (Original→Thumbnail→Mini→MetadataOnly), budget enforcement, and pin management. `ArchiveTransport` provides abstract transport layer with 4 protocol implementations (SMB via smbclient, SFTP via ssh/sftp, FTPS via curl, HTTP/WebDAV via dart:io HttpClient). `ArchivePlaceholder` generates tier-specific placeholder info for UI rendering. Settings UI with protocol selection, SSID configuration, storage budget, and tier boundary editing (V3.1.44: tier days configurable with validation: tier1 < tier2 < tier3, all ≥ 1 day). Safety rule enforced: never delete without confirmed archival. **Tests: 145 smoke + 18 GUI (all green).**

**Voice Transcription:** `WhisperFFI` provides FFI bindings for whisper.cpp (model loading, transcription, language detection, resource cleanup). `VoiceTranscriptionService` manages queue-based transcription pipeline with lifecycle state machine (recording→transcribing→complete→transcriptOnly), audio retention cleanup, WAV parsing, and ffmpeg conversion for OGG/MP3/AAC input. Settings UI with language selection, retention period, and model size (tiny/base/small). Independent of Media Archive. **Tests: 87 smoke + 14 GUI (all green).**

**Anti-Sybil Transport-Layer:** `SybilTransportValidator` validates incoming CHANNEL_REPORTs at network level: selects K random validators from DHT (excluding reporter), sends reachability requests, collects responses with timeout handling, accepts/rejects based on configurable threshold (60% default). `BloomFilterExchange` distributes own Bloom filter to 3 random peers periodically (5-min timer). Local reachability check via Bloom filter overlap for validator responses. **Tests: 63 smoke (all green).**

**Calls Phase 3a:** KDF upgraded from SHA-256 to HKDF-SHA256 in both caller and callee key derivation paths. 60-second ringing timeout with auto-hangup (outgoing) / auto-reject (incoming). Mute/speaker controls wired to AudioEngine (capture skips when muted, playback skips when speaker disabled). `JitterBuffer` (100ms depth, 5 frames) handles out-of-order delivery, packet loss detection with skip, duplicate filtering, buffer overflow protection. `OpusFFI` provides FFI bindings for libopus codec (encoder/decoder/PLC, 256→32 kbps compression). **Tests: 64 smoke (all green).**

### 14.8 Additional Features (v2.5–v2.7.1)

Features implemented since Phase 2 that are not covered by the sub-phases above:

**v2.5:** Identity Skins (9 visual themes per identity with background patterns, bubble styles, watermarks). Contrast accessibility skin (WCAG AAA). Thematic FABs with PNG icon assets. ContactSeed QR code generation + scanner. Guardian Recovery UI. Seed phrase printing (PDF). Contact rename (local alias + remote rename banner). Optimistic UI for message sending (PoW in isolate). Android SafeArea fixes. Identity rename broadcast (PROFILE_UPDATE). Media forward/save/copy. App icon. AnimatedTheme (400ms skin transitions). GUI action IPC (10 remote-controlled UI actions for E2E testing). PoW LAN exemption for infrastructure messages. Config propagation fix. IPC null-safety (30+ commands).

**v2.7:** Tombstone tracking for channels. Melder qualification enforcement. CSAM cooldown + strikes. Android APK signing. Linux release signing. DHT update manifest with Ed25519 signature verification.

**v2.7.1 (Chat UX):** Inline video player (play/pause, progress bar, auto aspect ratio). Inline audio player (seek slider, duration display). Voice message recording (microphone button, timer, AAC encoder). Clipboard paste (Ctrl+V for images). Drag & drop (multi-file support). URL detection (clickable links). Image fullscreen viewer (pinch-to-zoom 0.5x–5x). Extended file type icons. ML-KEM call fix (hybrid X25519 + ML-KEM-768 in CallManager).

**v3.1.8 (Clipboard Paste):** Full clipboard paste implementation per Section 18.7. `ClipboardHelper` module (`lib/core/media/clipboard_helper.dart`) with wl-paste/xclip auto-detection, MIME type extraction, `ClipboardContent` data class (data, mimeType, isText, isImage, isVideo, isAudio, suggestedFilename, filePath). Paste button (content_paste icon) in input area. Confirmation dialog with image preview, file type icon, size, filename, MIME type for binary content. Text paste directly into TextField at cursor. `text/uri-list` support for files copied from file managers (Nautilus/Thunar). Video (mp4/webm/mkv/mov), audio (mp3/ogg/wav/aac/flac), and generic file support. 8 i18n keys in 5 languages. 8 GUI E2E tests (gui-27-clipboard-paste).

**v3.1.29 (Sender-Side Link Previews):** URLs in outgoing text messages are detected (regex: `https?://...`), and the sender's device fetches OpenGraph metadata (og:title, og:description, og:site_name, og:image) before encryption. The preview data is embedded in a `LinkPreview` protobuf field on the `MessageEnvelope` and encrypted alongside the message. The **recipient makes zero network requests** — they display only what the sender included. SSRF protection blocks fetches to private/reserved IPs (10.x, 172.16-31.x, 192.168.x, 127.x, 169.254.x, 100.64-127.x, IANA reserved, multicast, IPv6 ULA/link-local, IPv4-mapped IPv6). Only HTTPS URLs are fetched. Timeout: 5s, max HTML: 256KB, max image download: 256KB. If the downloaded `og:image` exceeds the 64KB envelope budget it is **resized and re-encoded as JPEG** (descending widths 600/400/300px × descending qualities 75/60/45/30) until it fits — only if no combination produces ≤64KB is the thumbnail dropped (`LinkPreviewFetcher.recompressToFit`). Settings: enable/disable, browser open mode (Normal / Incognito preferred / Always ask). BLE was removed from the architecture (presence leakage, eclipse attacks) and replaced with NFC Contact Exchange (dual-purpose: contact pairing + peer list merge).

**v3.1.44 (Android Flavors + Channel Guard):** Android product flavors for parallel Beta/Live installation (`chat.cleona.cleona` vs `.beta`). Separate data directories, app icons (Beta has red BETA banner), and app labels. Network channel auto-detection from package name on Android (no `--dart-define` needed). ContactSeed URI extended with `c=b`/`c=l` channel tag (1 char). Cross-channel contact requests blocked at scan/paste time with user-visible error message. Applies to all contact exchange methods (QR, NFC, URI paste, manual input). E2E device revocation test (gui-48, 44 tests). IPC: `test_inject_device`, `get_seed_phrase`. `init_profile.dart` supports `--restore` mode for seed phrase recovery.

### 14.9 Known Issues & Planned Improvements (as of v2.8)

**UI Issues (resolved):**
- ~~Group member list shows own identity as node ID instead of display name.~~ Fixed: `createGroup()` now stores the display name directly in the member entry.
- ~~Deleted contacts reappear after app restart.~~ Fixed: Persistent `_deletedContacts` set prevents re-import from routing table or PeerExchange data.

**Performance:**
- Fragment delivery latency: Sub-second via proactive fragment push (relay nodes forward immediately to mailbox owner). No periodic polling needed during normal operation — polling only at startup and after restore. Fragment distribution restricted to confirmed peers (seen < 5 min) to avoid wasting sends on unreachable peers.
**Infrastructure:**
- MailboxStore is now persistent (binary files in `<profileDir>/mailbox/`, batched writes every 2s). Fragments survive restarts. V3.1.11: migrated from JSON/base64 to binary format (33% space savings).
- VM clocks on QEMU/KVM nodes drift ~1 hour. Requires proper NTP configuration or `timedatectl set-ntp true` with a reachable NTP server.

**Cryptography:**
- (Resolved) Previous Double Ratchet session issues eliminated by switch to stateless Per-Message KEM (see Section 4.3). Both parties can send immediately after contact acceptance.

---

## 15. Data Management & Storage

### 15.1 Storage Priorities

1. **Own chats, media, and metadata:** Priority 1 — never automatically deleted. This is the user's personal data and is sacrosanct.
2. **Relay fragments for other users:** Priority 2 — deleted after confirmed delivery or TTL expiry.
3. **DHT routing data:** Priority 3 — can be rebuilt from the network.

### 15.1.x Identity-Resolution-Storage (§2.2.4)

Replikator-Knoten halten Auth-Manifest- und Liveness-Records anderer User
in `~/.cleona/identity_dht_storage.json.enc` (FileEncryption). Storage-Caps:
~1000 Auth-Manifeste + ~5000 Liveness-Records (~5 MB Disk-Persistierung
dominiert von ML-DSA-Sig á 3.3 KB pro Auth-Manifest; ~7–9 MB RAM mit
Dart-Map-Overhead). LRU-Eviction nach XOR-Distance: am weitesten entfernte
Records evictieren zuerst, weil andere Replikatoren näher dran sind
(Redundanz reicht).

Persistenz separat von Mailbox-Store (§15.x) und Erasure-Fragment-Store —
identity-records sind klein, signed-self-verifying, ohne Erasure-Coding.

### 15.2 Database Encryption

All SQLite databases are encrypted at rest. See Section 4.7 for the full encryption specification. Key points:
- Algorithm: XSalsa20-Poly1305 (libsodium)
- Key derivation: SHA-256(ed25519_sk[0:32] + "cleona-db-key-v1")
- File format: `cleona.db.enc` = [24-byte nonce][ciphertext]
- Runtime: SQLite operates on decrypted temp file; periodic encrypted flushes every 60s
- Migration: Existing unencrypted databases are automatically encrypted on first open with a key

### 15.3 Message Deletion Model

Messages can be deleted locally (removed from own device only) or with a delete request (sends a deletion request to the conversation partner). Delete requests are best-effort — the recipient's app will delete the message, but there is no guarantee (the recipient could be running a modified client).

### 15.4 Per-Chat Message Expiry

Each conversation (1:1, group, or channel) has an individually configurable auto-deletion timer. When enabled, messages are automatically and irrevocably deleted from all participants' devices after the timer expires.

Critical implementation detail: The expiry timer starts after the message has been READ by the recipient, not after sending. This ensures messages are not deleted before being seen (important for offline users who might not receive a message for hours/days).

In 1:1 chats, either participant can propose a change to the expiry setting; the other must explicitly confirm. In groups and channels, the owner sets the expiry for all members. Changes apply only to future messages — existing messages keep their original expiry.

### 15.5 Per-Chat Message Editing

Each conversation has a configurable editing window that determines how long after sending a message can be edited by its author.

Only the original author can edit their messages. Edited messages display a "(edited)" label with the timestamp of the last edit. Edit history is NOT stored — only the current version exists (data minimization).

Enforcement is dual-sided: the sender's app removes the edit button after the window expires (client-side), AND recipients reject edit messages that arrive after the window has passed based on the original message timestamp (server-side enforcement, even though there is no server).

### 15.6 Per-Chat Configuration Protocol

Each conversation has configurable policies beyond expiry and editing: download permissions (whether received files can be saved), forwarding permissions (whether messages can be forwarded to other conversations), and the download directory.

#### 15.6.1 Configuration Change Flow

**DM conversations (mutual consent):** When a user changes a chat configuration setting, a `CHAT_CONFIG_UPDATE` message (type 100) is sent to the partner containing the proposed changes. The partner's app displays a confirmation dialog showing the proposed changes. The partner can accept or reject. Their response is sent as a `CHAT_CONFIG_RESPONSE` message (type 101) with an `accepted` flag and the original changes. If accepted, both sides apply the new configuration. If rejected, the proposer is notified.

**Groups and channels (owner authority):** The owner sends a `CHAT_CONFIG_UPDATE` directly to all members. The configuration takes effect immediately — no confirmation step. Group/channel configuration can be changed by the **Owner or Admin**. This is enforced both in `requestChatConfigChange()` (sender side) and `_onChatConfigUpdate()` (receiver side).

**Out-of-order delivery handling:** Since config updates and group invites are sent as separate fire-and-forget messages, a `CHAT_CONFIG_UPDATE` may arrive before the `GROUP_INVITE` that establishes the group on the receiver. To handle this, config updates for unknown groups are buffered in `_pendingGroupConfigs`. When the `GROUP_INVITE` subsequently arrives, buffered configs are applied if the sender has owner/admin role. This eliminates race conditions in asynchronous message delivery.

**Key resolution for fan-out:** When broadcasting to group/channel members, `_resolveMemberKeys()` resolves encryption keys by preferring the contact's keys (most up-to-date from key exchange) with fallback to the GroupMemberInfo keys (from the original GROUP_INVITE protobuf). This prevents delivery failures when member keys in the group record are stale or empty.

#### 15.6.2 Configurable Settings

| Setting | Type | Default | Scope |
|---------|------|---------|-------|
| `allow_downloads` | boolean | true | Whether received files can be saved to disk |
| `allow_forwarding` | boolean | true | Whether messages can be forwarded |
| `expiry_duration_ms` | int? | null (no expiry) | Message auto-delete after read |
| `edit_window_ms` | int? | null (no edits) | Time window for message editing |
| `read_receipts_enabled` | boolean | true | Whether read receipts are sent |
| `typing_indicators_enabled` | boolean | true | Whether typing indicators are sent |

#### 15.6.3 Download Directory

Each identity profile has a configurable download directory for saved files:

- **Desktop (Linux/Windows/macOS):** Defaults to the OS standard Downloads folder (`~/Downloads`).
- **Mobile (Android/iOS):** Defaults to an app-internal downloads directory. Users can optionally change to an external directory, which triggers the appropriate storage permission request at that time (not at installation).

The download directory is stored per-identity in `chat_policies.json` and can be changed in the chat settings screen.

**Self-copy protection:** When the source file already resides in the download directory, `File.copySync()` to the same path would truncate the file to 0 bytes. The save function uses `p.canonicalize()` to compare source and target paths and skips the copy if they are identical, showing an "already in download folder" notification instead.

### 15.7 Media Auto-Archive (Test-First — v2.8)

Automatic offloading of media (images, videos, files) to a local network share. When the device connects to a configured home WLAN and the share is reachable, media files are copied to the share. After a configurable retention period, originals are deleted from the device — **never without confirmed archival**.

**Scope:** DMs and groups only. Channels are excluded.

#### 15.7.1 Tiered On-Device Storage

Instead of showing blank placeholders for archived media, Cleona retains progressively smaller representations:

| Tier | Period | On Device | On Share |
|------|--------|-----------|----------|
| 1 | 0–30 days | Original | — (not yet archived) |
| 2 | 30–90 days | Thumbnail (~20–50 KB) | Original |
| 3 | 90–365 days | Mini-thumbnail (~2–5 KB, 64px) | Original |
| 4 | > 1 year | Metadata link only (date, size, type icon) | Original |

All tier boundaries are user-configurable. Pinned media ignores tiers entirely and remains as original on the device.

#### 15.7.2 Pin / Keep

Media can be marked as "keep" at three levels:

- **Per message:** Star/pin icon in the 3-dot menu of any media message.
- **Per chat:** "Never delete media in this chat" in chat settings.
- **Global:** "Never auto-delete" in archive settings.

Pinned media is still archived to the share (backup!), but **never deleted from the device**.

#### 15.7.3 Network Detection

Two mechanisms combined:

1. **SSID-based:** User configures one or more WLAN names → fast home-network check.
2. **Share reachability:** Periodic probe whether the share is actually accessible → robust (works via VPN too).

Archival starts only when both conditions are met (or share-reachability alone when no WLAN is configured, e.g., wired desktop).

#### 15.7.4 Supported Protocols

| Protocol | Description | Priority |
|----------|-------------|----------|
| **SMB/CIFS** | Universal NAS standard (Synology, QNAP, Fritz!NAS) | Required |
| **SFTP** | SSH-based, secure, good mobile support | Required |
| **FTPS** | FTP over TLS, for older NAS systems | Nice to have |
| **HTTP/HTTPS** | WebDAV-based, for self-hosted servers | Nice to have |

No plain FTP (insecure). No NFS (impractical on mobile).

#### 15.7.5 Directory Structure on Share

```
<Share-Root>/Cleona/<Identity>/<Chat>/YYYY-MM/<filename>_<content-hash>.ext
```

Content-hash suffix enables automatic deduplication when multiple devices/identities archive the same chat.

#### 15.7.6 Safety Rules

1. **Never delete without confirmed archival.** If the share is unreachable and the retention period expires, the original stays on the device.
2. **Reminder notification:** "You have X MB of archivable media. Connect to your home WLAN to free up storage."
3. **No encryption on share.** Media is stored decrypted so it can be viewed directly on PC/NAS. The share resides on the user's local home network.
4. **Initial sync:** When first activated, a background sync processes existing media with a progress bar. Ideally runs overnight while charging.

#### 15.7.7 Storage Budget

In addition to time-based tiers, users can set a maximum on-device media budget (e.g., "keep max 2 GB"). When the limit is reached, the oldest unpinned media is archived first — regardless of tier configuration.

#### 15.7.8 Batch Retrieval

Instead of tapping each placeholder individually:

- "Retrieve all media from [date range]"
- "Retrieve all media from this chat"
- Requires active share connection; progress bar during download.

#### 15.7.9 Configuration

```
Archive Settings:
├── Archive enabled: [ON/OFF]
├── Archive target: [SMB/SFTP/FTPS/HTTP(S)] + address + credentials
├── Home WLAN(s): ["FritzBox7590", ...] (multiple allowed)
├── Tier boundaries: [30/60/90 | 90/180/365 | 365/730/∞] days
├── Archive only on WLAN: [ON/OFF]
├── Archive only while charging: [ON/OFF]
├── Storage budget: "Max X GB media on device"
└── Pin default: [per message | per chat | global]
```

### 15.8 Voice Transcription (Test-First — v2.8)

On-device speech-to-text for voice messages using whisper.cpp (OpenAI Whisper as C library). The transcript is displayed as text below the voice message. After a configurable retention period, the audio is deleted and only the transcribed text remains permanently.

This feature works independently of the Media Archive — both can be enabled separately.

#### 15.8.1 Voice Lifecycle

```
Voice message received
  ├── Immediately: Background transcription starts (whisper.cpp)
  ├── Phase 1: Audio + text in parallel (configurable, e.g. 30 days)
  │   ├── User can play audio OR read text
  │   └── Manual download to device storage possible anytime
  └── Phase 2: Text only (after retention period)
      ├── Audio deleted (not archived, simply removed)
      └── Transcription remains permanently
```

#### 15.8.2 Transcription Engine

- **whisper.cpp** — runs fully on-device, no cloud dependency
- Model: "tiny" or "base" (~40–75 MB), sufficient quality for voice messages
- Supported languages: `auto` (default — Whisper auto-detects from ~99 languages), plus explicit selection from DE, EN, ES, HU, SV in the Settings UI (`voice_transcription_config.dart`). The explicit selection list is narrower than Cleona's 33 UI locales — a deliberate config choice, not a Whisper limitation.
- Automatic language detection or manual selection
- **Source-Side Transcription:** Sender transcribes before sending, transcript embedded in VoicePayload protobuf. Receiver uses sender's transcript directly. Fallback: receiver transcribes locally if no transcript from sender.

#### 15.8.2.1 Native Dependencies (Runtime)

Voice transcription requires the following native libraries and tools at runtime. If any dependency is missing, transcription is silently disabled — voice messages still work, but without text.

**Linux (Desktop / Daemon):**

| Dependency | Purpose | Install | Package (deb) | Package (rpm) |
|------------|---------|---------|---------------|---------------|
| `libwhisper.so` | Speech-to-text engine | Build from source (whisper.cpp) | — | — |
| `libggml.so`, `libggml-base.so`, `libggml-cpu.so` | Tensor computation (whisper.cpp transitive deps) | Built alongside whisper.cpp | — | — |
| `libwhisper_wrapper.so` | Dart FFI bridge (struct-by-value ABI) | Built from `scripts/build-whisper-wrapper.sh` | — | — |
| `ffmpeg` | Audio format conversion (AAC/OGG/MP3 → WAV 16kHz PCM) | `sudo apt install ffmpeg` | `ffmpeg` | `ffmpeg` |
| GGML model file | Trained speech model (`ggml-tiny.bin` or `ggml-base.bin`) | Download from Hugging Face (ggerganov/whisper.cpp) | — | — |

Library search paths (in order): system default, `/usr/lib/`, `/usr/local/lib/`, `$HOME/lib/`, `./build/`.
Model path: `$HOME/.cleona/models/ggml-{tiny,base,small}.bin`.

**Building whisper.cpp from source:**
```bash
git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON ..
make -j$(nproc)
# Install (system-wide):
sudo cp libwhisper.so* /usr/local/lib/
sudo cp ggml/src/libggml*.so* /usr/local/lib/
sudo ldconfig
# Or install (user-local, $HOME/lib/):
cp libwhisper.so* ~/lib/
cp ggml/src/libggml*.so* ~/lib/
```

**Downloading the model:**
```bash
mkdir -p ~/.cleona/models
# Tiny (~40 MB, faster, lower quality):
wget -O ~/.cleona/models/ggml-tiny.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin
# Base (~75 MB, recommended):
wget -O ~/.cleona/models/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

**Android:**

On Android, `libwhisper.so` and `libggml*.so` must be cross-compiled for arm64-v8a with the Android NDK and bundled in `android/app/src/main/jniLibs/arm64-v8a/` (same as libsodium/liboqs/libzstd). **Critical:** GGML must be built with `-DGGML_OPENMP=OFF` — the NDK does not include `libomp.so`, and OpenMP is unnecessary since NEON SIMD provides the real speedup on mobile (whisper uses only 1-4 threads). Audio format conversion (AAC → WAV 16kHz PCM) is handled by Android's MediaCodec via a MethodChannel (`chat.cleona/audio`), not ffmpeg. The GGML model is downloaded on first use via Settings → Transcription (Hugging Face CDN, ~75MB for ggml-base).

**Linux Packaging (deb/rpm):**

For distribution as .deb or .rpm packages, the following must be declared:

```
# Debian control (Depends):
Depends: ffmpeg, libstdc++6, libc6

# RPM spec (Requires):
Requires: ffmpeg, libstdc++, glibc

# Bundled in package (not in distro repos):
/usr/lib/cleona/libwhisper.so.1
/usr/lib/cleona/libggml.so.0
/usr/lib/cleona/libggml-base.so.0
/usr/lib/cleona/libggml-cpu.so.0
/usr/lib/cleona/libwhisper_wrapper.so
/usr/share/cleona/models/ggml-base.bin  (or downloaded post-install)
```

The whisper.cpp and GGML libraries are not available in standard distro repositories and must be bundled. The model file (~75 MB for base) can either be included in the package or downloaded on first launch via a post-install script, depending on package size constraints.

#### 15.8.3 Configuration

```
Voice Message Settings:
├── Auto-transcription: [ON/OFF]
├── Keep audio for: [7/14/30/60/90 days] (default: 30)
├── "Never delete": [per message (pin) | per chat | global]
└── Transcription language: [Auto | DE | EN | ES | HU | SV]
```

#### 15.8.4 Scope

DMs and groups only (same as Media Archive). Channels are excluded.

---

## 16. Licensing, Funding & Donation Model

### 16.1 Source Available Model

Cleona Chat's source code is publicly visible on GitHub for transparency, security auditing, and community trust. The custom license permits: reading and studying the source code, auditing the cryptographic implementation, submitting bug reports and feature requests, and building from source for personal use.

### 16.1.1 Publishing Infrastructure

Development uses a three-directory model to separate working code from secrets and public-facing content:

| Directory | Purpose | Git-tracked | Public |
|-----------|---------|-------------|--------|
| `Cleona/` | Full development environment (code, tests, VM scripts, internal docs) | Yes (local) | No |
| `CleonaPrivat/` | Private keys, credentials, internal documentation | No | Never |
| `CleonaGit/` | Sanitized prestage for GitHub (source + public docs + releases) | Yes (pushed to GitHub) | Yes |

**Sync workflow:** `Cleona/scripts/sync-to-git.sh` copies sanitized source from `Cleona/` to `CleonaGit/`, excluding all secrets, test infrastructure, and internal documentation. A built-in security check scans for leaked passwords and private keys before completion.

**Commit date neutralization:** All commits pushed to GitHub use a fixed neutral date (`2026-01-01T12:00:00+00:00`) to hide the development timeline. Push timestamps (set by GitHub server-side) are accepted as unavoidable.

**Published content:** Source code (`lib/`, `proto/`, `assets/`), public architecture document, security whitepaper, user manual (33 languages), changelog (sanitized), signed release artifacts (Linux/Windows/Android + SHA256SUMS).

**Not published:** Private keys, test infrastructure (`test/`, `scripts/vm/`), internal docs (`CLAUDE.md`, `HANDOVER.md`, `BUGFIX_*.md`), internal tooling (`headless.dart`, `init_profile.dart`), debug builds, VM credentials.

**Reproducible builds:** Users can verify that official binaries match the published source by building from source and comparing the unsigned output. The Ed25519 release signature is a separate verification step (authenticity, not integrity). The maintainer's private key is never needed by verifiers.

**Distribution channels:** GitHub Releases (signed binaries), Google Play (maintainer-signed APK), project website. F-Droid is not possible (requires OSS license). See `docs/PUBLISHING.md` for the full publishing strategy.

**Linux packaging:** Three formats built from the Flutter Linux bundle via `scripts/build-linux-packages.sh`: AppImage (universal, no installation), .deb (Debian/Ubuntu/Mint), .rpm (Fedora/openSUSE/RHEL). All install to `/opt/cleona/` with a wrapper script in `/usr/bin/cleona-chat` and a `.desktop` entry for application menu integration.

### 16.2 Name & Brand Protection

The name "Cleona Chat" and its associated logo are protected by trademark registration, separate from the source code license. This ensures that even if someone were to create a modified version (in violation of the license), they cannot use the Cleona name or logo.

### 16.3 Funding Sources

- GitHub Sponsors for direct sponsorship on the project page.
- Open Collective for transparent donation management (all finances publicly visible).
- Liberapay for recurring donations without platform commission.
- Cryptocurrency (Bitcoin, Monero) for privacy-respecting donations.

### 16.4 In-App Donation Banner (Signal-Style)

Inspired by Signal's approach, Cleona includes a non-intrusive donation banner. The design philosophy: visible enough to generate necessary funding, gentle enough to never annoy users or create a negative experience.

#### 16.4.1 Placement & Behavior

Location: Displayed at the top of the chat list (conversation overview screen) only. Never appears inside an active conversation, never during typing or reading. Appearance: Small, subtle card with a friendly message and a "Donate" button.

#### 16.4.2 Design Principles

Never a popup, modal, or full-screen overlay — always an inline card element. No guilt-tripping or dark patterns — positive, grateful tone only. Rotating message texts to keep it fresh: "Cleona has no ads and no investors. Your support keeps it running."

#### 16.4.3 Donation Options

**Bank Transfer (SEPA):** IBAN with EPC QR code (EPC069-12 standard) for one-tap SEPA transfers from banking apps. Details (IBAN, BIC, recipient, institute) displayed with individual copy buttons. Ed25519-signed for fork protection.

**Cryptocurrency:** Bitcoin with QR code. Monero planned for users who prefer maximum privacy.

One-time donations with predefined amounts (€3, €5, €10, €25) plus custom amount entry planned. Recurring monthly donations via supported platforms planned.

#### 16.4.4 Fork Protection for Donations

Fork protection for donations operates in two layers:

**Primary protection (network-level):** The Closed Network Model (Section 17.5) ensures that only official maintainer-signed builds can participate in the Cleona network. A forked build without the correct network secret is cryptographically isolated — it cannot connect to any existing Cleona users. An app with zero connectivity generates zero donations. This is the primary defense and renders most fork-based donation scams impractical.

**Secondary protection (in-app verification):** Donation targets (IBAN, BTC address) are additionally signed with the Ed25519 maintainer keypair. The public key is embedded in the app (`assets/cleona_maintainer_public.pem`), the private key is kept offline by the maintainer. On the donation screen, the app verifies the Ed25519 signature and displays a trust indicator: green checkmark ("Official Cleona donation address") when the signature matches, or a red warning when it does not. This catches the edge case where someone modifies only the donation addresses in an otherwise official build without re-signing.

**Implementation details:** The donation config (address + base64-encoded signature) is stored in `lib/ui/screens/donation_screen.dart`. To update the address, the maintainer signs the new address with the private key: `echo -n "new_address" | openssl pkeyutl -sign -inkey cleona_maintainer_private.pem -rawin -out sig.bin && base64 sig.bin`. The app uses libsodium's `crypto_sign_verify_detached` (via `SodiumFFI.verifyEd25519()`) for verification.

**Residual risk:** A determined attacker who reverse-engineers the network secret from an official build AND replaces both the donation addresses and the maintainer public key could theoretically create a functional fork with redirected donations. This requires significant reverse engineering effort and is mitigated by secret rotation (Section 17.5.5), binary obfuscation (Section 17.5.6), and legal protection (Sections 16.1, 16.2).

#### 16.4.5 App-Wide Code Signing (Complete — v2.7)

All three signing mechanisms are implemented:

1. **Android APK Signing:** RSA 2048-bit Keystore (`key.properties`), release signing config in `build.gradle.kts`. Required for Play Store distribution.
2. **Linux Release Signing:** `scripts/sign-release.sh` generates tarball + SHA-256 checksum + GPG signature. Users can verify authenticity before installation.
3. **Signed Update Manifest (DHT):** `lib/core/update/update_manifest.dart` — Ed25519-signed version manifest with `UpdateChecker` that verifies signature against maintainer public key. Manifest signing via `scripts/sign-update-manifest.sh`. As of V3.1.72, the manifest also carries optional `minRequiredVersion` and `minRequiredReason` fields for **Hard-Block-Update-Enforcement** — see Section 16.4.7.

The existing maintainer Ed25519 keypair (used for donation verification) is reused for the DHT update manifest. Android and Linux signing use platform-specific keys (Android Keystore, GPG respectively).

#### 16.4.6 Android Flavors — Beta/Live Parallel Install (Complete — v3.1.44)

The Android build supports two **product flavors** that can be installed side-by-side on the same device:

| | Live | Beta |
|---|---|---|
| **Package** | `chat.cleona.cleona` | `chat.cleona.cleona.beta` |
| **App Name** | Cleona Chat | Cleona Beta |
| **Icon** | Standard (purple CC) | With red BETA banner |
| **Data Dir** | `/data/data/chat.cleona.cleona/` | `/data/data/chat.cleona.cleona.beta/` |
| **Network** | Live (Port 8080) | Beta (Port 8081) |

**Network channel auto-detection (Android):** On Android, the network channel is derived at runtime from the package name (`AppPaths.packageName`). If the package ends with `.beta`, the beta channel is used; otherwise live. This eliminates the need for `--dart-define=NETWORK_CHANNEL=...` on Android — the flavor determines the channel automatically. Desktop builds continue to use `--dart-define` (default: beta).

**Data isolation:** Each flavor has its own data directory, profile, identity, and contacts. There is no shared state between the two installations. A user can run both simultaneously.

**ContactSeed channel tag:** The `cleona://` URI includes a `c=b` or `c=l` parameter (1 character) to identify the network channel. When scanning a QR code, pasting a URI, or receiving an NFC contact from a different channel, the app shows an immediate error before sending any contact request. Legacy URIs without the `c=` parameter are accepted as compatible (graceful migration).

#### 16.4.7 Hard-Block Update Enforcement (Complete — V3.1.72)

When a release introduces a backward-incompatible change (e.g., the Per-Message-KEM HKDF-Salt v2 cutover in Sec H-5), pre-release clients would silently lose messages because their wire format is no longer accepted by updated peers. Hard-Block-Update-Enforcement prevents this silent failure mode.

**Mechanism:**

The Signed Update Manifest (Section 16.4.5) carries two optional fields:

- `minRequiredVersion: String?` — semver, e.g., `"3.1.72"`. If set and `appVersion < minRequiredVersion`, the client is hard-blocked.
- `minRequiredReason: String?` — i18n key, e.g., `"update_required_kem_v2"`, used to render the explanation text in the user's locale.

**UX flow:**

1. At app start, `main.dart` reads the cached manifest (refreshed by the existing 6h DHT-poller).
2. `UpdateChecker.isHardBlocked(manifest, currentVersion)` compares versions.
3. If true, `UpdateRequiredScreen` is rendered as the initial route, before the normal `MaterialApp` shell. The screen shows:
   - Title: `t('update_required_title')`
   - Body: `t(manifest.minRequiredReason)` (i18n in 33 locales)
   - Primary button: opens `manifest.downloadUrl` externally (browser / Play Store)
   - Secondary link: "Open anyway (limited)" → enters Reduced-Mode

**Reduced-Mode semantics (`CleonaService._reducedMode = true`):**

- User-message Send (`sendTextMessage`, `sendMediaMessage`, `editMessage`, `deleteMessage`, `sendReaction`, `sendCalendarEvent`, `submitPollVote`, etc.) is gated — no-op.
- User-message Receive (TEXT, FILE, IMAGE, VIDEO, VOICE_MESSAGE, EMOJI_REACTION, MESSAGE_EDIT, MESSAGE_DELETE, CHANNEL_POST, CALENDAR_*, POLL_*) is gated — silently dropped at envelope dispatch.
- Existing conversations remain readable and scrollable (DB-stored plaintext, not affected).
- Settings screen is accessible (allows identity export, profile inspection, etc.).
- DHT-Participation continues (PEER_LIST_PUSH, presence, routing-table maintenance) — kept fresh in case the user later updates and re-enters normal operation without a cold network start.
- A persistent red banner at the top of the home screen reminds the user of the limited mode.

**Persistence:** Reduced-Mode is per-session, not persisted. Every app restart re-evaluates the manifest and re-shows `UpdateRequiredScreen` if still applicable. This prevents users from "forgetting" they are in limited mode.

**Multi-Identity scope:** The hard-block applies at the daemon process level — all identities of the installation are gated together. Multi-Identity does not provide a per-identity bypass.

**Rollback story:** If a release with `minRequiredVersion = X` introduces a critical bug, the rollback release re-publishes a manifest with `minRequiredVersion = null`. Cached manifests refresh within the 6h DHT-poll window, so the worst-case net-split lasts ~6h. Pre-release verification on the Beta cluster (24h soak with full E2E suite) is the primary defense; rollback is a fallback with cost.

---

## 17. Security Considerations

This chapter provides a threat model analysis covering all identified attack vectors and their mitigations.

### 17.1 Database Security

All SQLite databases are encrypted at rest using XSalsa20-Poly1305 with keys derived from the identity's Ed25519 secret key via SHA-256. This ensures that even if a device's filesystem is compromised, the chat history remains encrypted. The encryption is quantum-resistant: SHA-256 provides 128-bit security against Grover's algorithm, and XSalsa20-Poly1305 provides authenticated encryption.

Unencrypted temp files used during runtime (`.cleona_db_tmp`) are securely deleted on shutdown. Periodic encrypted flushes (every 60s) minimize data loss in case of crashes.

### 17.2 Key Storage Security

Private keys are stored encrypted with Argon2id + XSalsa20-Poly1305 on Linux, and hardware-backed storage (Android Keystore, iOS Secure Enclave) on mobile platforms. The master seed, which derives all identities, is never stored in plaintext — only in the encrypted `keys.json` or hardware keystore.

### 17.3 Network Security

- **Signature verification:** All messages are dual-signed (Ed25519 + ML-DSA-65). Both signatures are verified on receipt.
- **NAT probe amplification prevention:** DHT_PONG responses do not trigger further responses, preventing amplification loops.
- **Stale key handling:** Lenient policy — stale cached keys are cleared on mismatch rather than rejecting the message, allowing recovery from key rotation.
- **IPv6 filtering:** IPv6 multicast-discovered addresses are filtered when the transport socket is IPv4-only.
- **Multicast packet filtering:** 46-byte HMAC-authenticated discovery packets (HMAC prefix + "CLEO" magic bytes) are filtered before protobuf parsing to prevent `InvalidProtocolBufferException` errors.
- **Multi-address parallel delivery:** All message sending (both `sendEnvelope()` and DHT RPCs) uses parallel delivery to all known addresses. This mitigates hairpin NAT failures where large UDP packets are silently dropped on one path but delivered on another (see Section 2.4.3).
- **DHT RPC wildcard response matching:** When DHT RPCs are sent to multiple addresses of the same peer, wildcard response keys (address:port-based) ensure the response is matched regardless of which address replies. Extra wildcard keys are cleaned up together with the primary key on timeout or completion.

### 17.4 Security Audit Recommendations

Before public release, an independent security audit is strongly recommended, covering: cryptographic protocol review (Per-Message KEM implementation, hybrid X25519+ML-KEM key derivation, pairwise group encryption, call key negotiation, key rotation, DB encryption) by a specialized firm, network protocol review (DHT operations, peer list exchange, NAT traversal, RUDP ACK mechanism), and application security review (input validation, memory safety, FFI boundary security).

### 17.5 Network Access Control (Closed Network Model)

Cleona follows the **Signal model**: source code is publicly available for auditing and transparency, but only official maintainer-signed builds may participate in the Cleona network. This protects users against malicious forks that could modify donation targets, weaken encryption, or exfiltrate data.

#### 17.5.1 Design Principle

The fundamental insight: in a P2P network without central servers, network access cannot be enforced at a single point. Instead, Cleona makes the **packet format itself dependent on a build-time secret** that only official builds possess. Nodes without the correct secret cannot parse, generate, or respond to Cleona network traffic — they are cryptographically isolated into a separate, empty network.

This is analogous to two WiFi networks with different passwords: they share the same radio spectrum but cannot see each other.

#### 17.5.2 Network Secret Derivation

The network secret replaces the previous plaintext `network_tag` ("beta"/"live"):

```
network_secret = HMAC-SHA256(maintainer_private_key, "cleona-network-" + channel)
```

Where `channel` is "beta" or "live". The maintainer's Ed25519 private key serves as the root of trust. The resulting 32-byte secret is truncated to 16 bytes for use in packet authentication and Node-ID computation.

**Channel-specific bootstrap ports:** Each channel uses a dedicated default bootstrap port to avoid cross-channel interference:
- **Live: Port 8080** (production, established DNAT chain)
- **Beta: Port 8081** (development and testing)

Regular nodes use random ephemeral ports (10000-65000) as before — the fixed ports only apply to bootstrap/headless nodes.

**Build-time embedding:** The network secret is computed offline by the maintainer and embedded in the official build at compile time via `--dart-define=NETWORK_CHANNEL=live` (default: `beta`). The maintainer's private key is NEVER included in any build — only the derived secret. Compromising a build reveals the network secret for that release but not the maintainer key.

#### 17.5.3 Node-ID Computation (Updated)

```
# Previous (public, guessable):
node_id = SHA-256("live" + public_key_bytes)

# New (secret-dependent):
node_id = SHA-256(network_secret + public_key_bytes)
```

A fork without the correct `network_secret` computes entirely different Node-IDs. Since DHT routing, peer discovery, and message addressing all depend on Node-IDs, forked nodes exist in a **parallel DHT address space** with no overlap. They cannot discover, route to, or communicate with official nodes.

#### 17.5.4 Packet-Level Authentication

Every outgoing UDP packet is authenticated with the network secret:

```
# CLEO discovery packet (was 38 bytes, now 46 bytes):
[4B "CLEO"][8B HMAC-SHA256(network_secret, nodeId + port)[:8]][32B nodeId][2B port]

# Protobuf message envelope:
[8B HMAC-SHA256(network_secret, serialized_envelope)[:8]][serialized_envelope]
```

On receipt, the first 8 bytes are verified against the HMAC of the remaining payload. Invalid HMAC → packet silently dropped before any further processing (no protobuf parsing, no DHT lookup, no error response). This provides:

1. **Invisibility:** Forked nodes' packets are dropped at the earliest possible stage. No error messages reveal the existence of official nodes.
2. **DoS resistance:** Invalid packets are rejected with a single HMAC check (fast, constant-time) before any expensive operations.
3. **No protocol leakage:** Without the secret, the packet payload is opaque. An observer cannot determine whether a HMAC-authenticated packet contains a chat message, DHT operation, or media transfer.

The 8-byte truncated HMAC provides 64 bits of security — sufficient for packet authentication (birthday attacks require ~2^32 forged packets, rate-limited by UDP throughput).

#### 17.5.5 Secret Rotation

The network secret is rotated with each **major release**:

```
network_secret_v1 = HMAC-SHA256(maintainer_key, "cleona-network-live-v1")
network_secret_v2 = HMAC-SHA256(maintainer_key, "cleona-network-live-v2")
```

**Transition period (90 days):** During rotation, nodes accept packets authenticated with EITHER the current or previous secret. Outgoing packets always use the current secret. After 90 days, the previous secret is dropped. This ensures:

- Gradual migration without network split
- Extracted secrets from old builds become worthless
- Users who don't update within 90 days are gently forced to update

The signed update manifest (Section 16.4.5) communicates the minimum required version. Nodes running deprecated versions display a non-dismissable update prompt.

**Related — Inner-Layer Versioning:** A conceptually similar but operationally independent versioning pattern lives at the Per-Message-KEM layer — see Section 4.3.7 (KEM Versioning). Both use explicit version constants and accept-sets, but rotate on different layers and are independent of each other (network-secret rotation does not require a KEM-version bump, and vice versa).

#### 17.5.6 Obfuscation in Binary

The network secret is not stored as a contiguous byte sequence in the compiled binary:

1. **Splitting:** The 16-byte secret is split into 4 fragments of 4 bytes each, stored at separate locations in the Dart source (different classes, different libraries).
2. **XOR masking:** Each fragment is XOR'd with a compile-time constant. Reassembly happens at runtime.
3. **Dart AOT compilation:** The release binary is ahead-of-time compiled to native machine code. No readable Dart source, no string table with the secret, no reflection API to enumerate constants.

This is not cryptographic protection — a determined reverse engineer with sufficient time can extract the secret. The goal is to raise the effort above the threshold where building a separate messenger is easier. This matches Signal's security model: their API keys and certificate pins are also extractable from the APK, but the effort filters out all but the most determined actors (e.g., Molly fork required months of reverse engineering).

#### 17.5.7 Defense-in-Depth Summary

| Layer | Mechanism | Protects Against |
|-------|-----------|-----------------|
| 1. Network Secret | HMAC on every packet | Fork nodes cannot parse/generate valid packets |
| 2. Secret Node-IDs | SHA-256(secret + pubkey) | Fork nodes in separate DHT address space |
| 3. Binary Obfuscation | Split + XOR + AOT | Casual reverse engineering |
| 4. Secret Rotation | New secret per major release | Extracted secrets expire in ≤90 days |
| 5. Donation Signatures | Ed25519 on IBAN/BTC | Address swapping without re-signing (defense-in-depth) |
| 6. Distribution Signing | APK signing, GPG, DHT manifest | Tampered binaries detectable before install |
| 7. Trademark + License | Legal protection | Use of "Cleona" name/brand in forks |

**Threat model acknowledgment:** A sufficiently determined attacker who reverse-engineers the network secret from an official build CAN participate in the network with modified code. This is an inherent limitation of any system without hardware attestation (TPM, Play Integrity). The mitigation is making this path significantly harder than building a separate project — the same trade-off Signal, Telegram, and every other open-source messenger accepts.

---

## 18. Application Architecture

### 18.1 Background Service + GUI Separation

Cleona is architecturally split into two layers that can run independently:

1. **Background Service (Daemon):** Contains all networking, DHT, cryptography, message storage, and relay logic. Runs without a GUI. Handles message sending and receiving even when the user is not actively looking at the app.

2. **GUI (Flutter Frontend):** The visual interface for chatting, managing contacts, viewing settings, etc. Connects to the local background service. Can be opened and closed without affecting message delivery.

This separation mirrors how messaging apps work on mobile: the app "runs in the background" even when the user isn't looking at it.

```
┌─────────────────────────────────────────┐
│  System Tray / App Icon                 │  ← Shows badge with unread count
├─────────────────────────────────────────┤
│  GUI (Flutter Window)                   │  ← Opens/closes independently
│  - Chat screens, contacts, settings     │
│  - Profile picture & description mgmt   │
│  - Communicates with service layer      │
├─────────────────────────────────────────┤
│  Background Service (CleonaNode)        │  ← Runs continuously
│  - DHT routing, peer discovery          │
│  - Message encryption/decryption        │
│  - Fragment storage/relay               │
│  - Offline message queuing              │
│  - DB encryption (periodic flush)       │
└─────────────────────────────────────────┘
```

#### 18.1.1 Six-Layer Architecture Model

While the two-layer split (Service + GUI) describes the deployment architecture, the full message path from network to user passes through **six distinct layers**. Each layer depends on the ones below it — a failure in any layer blocks all layers above.

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 6: GUI                                               │
│  - Flutter widgets, state management (Provider/ChangeNotify)│
│  - Renders conversations, contacts, settings                │
│  - User input → service calls, service events → UI updates  │
│  - A bug here (e.g. missing notifyListeners, broken         │
│    callback) makes messages "invisible" even though Layer 5  │
│    processed them correctly                                  │
├─────────────────────────────────────────────────────────────┤
│  Layer 5: Service Logic                                     │
│  - CleonaService orchestration, ContactManager, GroupManager│
│  - Contact requests, group setup, message routing           │
│  - Deduplication, conversation state, offline queuing       │
├─────────────────────────────────────────────────────────────┤
│  Layer 4: Encryption                                        │
│  - Per-Message KEM: X25519 + ML-KEM-768 (stateless, 4.3)   │
│  - Every message self-contained, no shared state            │
│  - Key rotation for post-compromise recovery                │
│  - Call encryption: ephemeral symmetric key (4.4)           │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Storage & Retrieval                               │
│  - Erasure-coded fragment store/retrieve                    │
│  - Mailbox ID computation (PK-based + NodeID-based)         │
│  - Reed-Solomon encode/decode, fragment relay               │
├─────────────────────────────────────────────────────────────┤
│  Layer 1+2: Network & Transport                             │
│  - UDP primary transport, TLS anti-censorship fallback      │
│  - Lightweight RUDP: ACK-driven fragment delivery (2.9)     │
│  - DHT bootstrap, Kademlia routing, peer discovery          │
│  - NAT traversal, LAN multicast/broadcast                   │
└─────────────────────────────────────────────────────────────┘
```

**Diagnostic principle:** When a feature fails (e.g. group messages not arriving), isolate the problem layer-by-layer from bottom to top. A Layer 4 failure (recipient's public key unknown) looks identical to a Layer 1 failure (no network) from the user's perspective — both result in "message not delivered". The diagnostic test `test/smoke/smoke_layer_diag.dart` automates this bottom-up verification.

| Layer | Passes when... | Common failure modes |
|-------|----------------|---------------------|
| 1+2 Network | Nodes discover each other, UDP packets arrive, RUDP ACKs return | NAT blocks UDP, firewall, wrong port, ACK timeout |
| 3 Storage | Fragments stored and retrieved, mailbox IDs match | Mailbox ID mismatch (PK vs NodeID), fragment loss |
| 4 Encryption | Per-Message KEM decryption succeeds, recipient's PK known | Missing public key from contact exchange, corrupted KEM ciphertext |
| 5 Service | CR exchange works, group invites delivered, messages routed | Missing callback wiring, dedup swallowing messages |
| 6 GUI | Messages appear in UI, state updates visible to user | Provider not notified, callback in async `.then()`, stale state |

### 18.2 Platform-Specific Behavior

#### Linux Desktop

- The background service runs as a user-space daemon.
- A system tray icon (GTK3 + libappindicator via FFI) indicates status and shows unread message count.
- Clicking the tray icon opens or brings the GUI to the foreground.
- Closing the GUI window does NOT stop the service — messages continue to be received and forwarded.
- The service stops when the system enters standby or is shut down. This is normal — the PC is then offline, just like a phone with no connectivity.
- During development/testing: Two separate daemon instances can run simultaneously on the same machine (on different ports), each with its own tray icon, for testing P2P communication locally.
- **Single-Instance Guard (V3.1.38):** The daemon enforces single-instance via three checks: (1) lock file with living PID, (2) IPC endpoint connectable (Unix socket on Linux, TCP port on Windows), (3) UDP port probe (catches orphaned daemons whose lock file was deleted). On startup failure (e.g. port already in use), the daemon calls `shutdownAll()` which cleans up lock/PID/port files and exits — preventing zombie daemons that hold lock files but have no transport or socket.
- **Beta Branding (V3.1.44):** Window title, tray tooltip and tray/app icon are dynamically selected based on `NetworkSecret.channel`. Beta builds show "Cleona Chat (Beta)" in the title bar, "Cleona Beta" in the tray tooltip, and use `tray_icon_beta.png` / `app_icon_beta.png` (red "BETA" banner overlay). Live builds use the standard branding. Channel is set via `--dart-define=NETWORK_CHANNEL=live` at build time (default: beta).

#### Windows Desktop

- Identical daemon+GUI architecture as Linux Desktop: separate daemon process with tray icon, GUI connects via IPC.
- **IPC Transport:** TCP loopback (`127.0.0.1`, ephemeral port) with shared-secret auth token. Dart's `InternetAddressType.unix` does not support Windows, therefore TCP loopback replaces the Unix Domain Socket. The daemon writes `<port>:<token>` to `cleona.port` (analogous to `cleona.sock` on Linux). Clients must send `{"type":"auth","token":"<token>"}` as first message — unauthenticated connections are immediately closed. The token is a 32-char hex random secret generated per daemon start and readable only by the file owner.
- System tray icon via Win32 Shell_NotifyIcon (dart:ffi) with context menu (Anzeigen/Dienst stoppen/starten/Beenden).
- Each Windows user runs their own daemon instance — data isolated in `%APPDATA%\.cleona`.
- Daemon runs as a user-space process (NOT a Windows Service), starts at user login via Registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
- Native DLLs: libsodium.dll, liboqs.dll, libzstd.dll bundled alongside the executable.
- Process management uses `tasklist` (process check) and `taskkill` (terminate) instead of Unix `kill`.

#### Android

- A background service starts at device boot.
- Messages are received in the background via adaptive sync (see Chapter 7).
- The app icon shows a badge with the number of unread messages.
- Local notifications appear for incoming messages, surfaced by the foreground service from received P2P traffic. (No third-party push system is involved on Android — see §7.8.)
- Tapping the app icon or notification opens the GUI.
- The `dataSync`-type foreground service stays in memory while running. Android keeps foreground-service apps Doze-exempt during their foreground state (§7.7), so message delivery is continuous, not periodic. WorkManager periodic windows (≥15 min OS minimum) only apply if the OS kills the service entirely.
- **In-Process Architecture:** On Android, the service runs in-process (same Dart isolate as the UI). Unlike Desktop where the daemon is a separate process, Android has no IPC layer — `CleonaService` is accessed directly.
- **Deferred Init (V3.1.44):** The heavy service initialization (key loading, node startup, mailbox loading, contact/channel loading) is deferred via `Future()` so the loading screen renders before blocking work begins. This reduced startup frame drops from 244 to 89 frames. **Known Issue (V3.1.48):** Deferred init still runs on the main Dart isolate. PQ-Crypto FFI calls (ML-KEM-768, ML-DSA-65), DB decryption, and DHT bootstrap block the UI thread for >5 seconds, causing ANR dialogs (62 events observed in E2E run). **Planned Fix:** Move CPU-intensive operations to separate Dart isolates via `Isolate.run()` or `compute()`.
- **ACK Retry Limit (V3.1.44):** The AckTracker limits immediate retries to 3 per message to prevent cascade flooding on the main (UI) thread. After 3 retries, the message stays in the persistent MessageQueue for the 30-second periodic drain. This eliminated ongoing frame drops after startup.
- **Debug Log Suppression (V3.1.44):** On Android, DEBUG-level log messages are written only to the file buffer, not to the console (`print()`). This avoids synchronous I/O on the main thread. INFO and above still appear in logcat for real-time monitoring.
- **Build Guideline:** Beta flavor is ALWAYS built with `--debug` (enables logcat for debugging). Live flavor is NEVER built with `--debug` (performance, security, APK size).

**Native Libraries (Android):** Pre-compiled shared libraries are bundled in `android/app/src/main/jniLibs/arm64-v8a/`:

| Library | Purpose | Source |
|---------|---------|--------|
| `libsodium.so` | Classical crypto (Ed25519, X25519, XSalsa20-Poly1305) | [jedisct1/libsodium](https://github.com/jedisct1/libsodium) (stable) |
| `liboqs.so` | Post-quantum crypto (ML-KEM-768, ML-DSA-65) | [open-quantum-safe/liboqs](https://github.com/open-quantum-safe/liboqs) (main) |
| `libzstd.so` | Compression | [facebook/zstd](https://github.com/facebook/zstd) (release) |
| `libwhisper.so` | Voice transcription (whisper.cpp) | [ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp) (master) |
| `libggml.so`, `libggml-base.so`, `libggml-cpu.so` | Tensor computation (whisper.cpp deps) | Built alongside whisper.cpp |

All libraries are cross-compiled with the Android NDK (r28, API level 24) using `scripts/build-android-libs.sh`. They use **16KB page-aligned ELF segments** (`-Wl,-z,max-page-size=16384`) as required by Android 15+ (API 36). The build script supports building individual libraries or all at once.

**Note:** `libwhisper.so` and `libggml*.so` are optional — if missing, voice transcription is disabled but voice messages still work as audio-only. The GGML model file (`ggml-base.bin`, ~75 MB) is not bundled in the APK but downloaded on first use to `$APP_DATA/models/`.

#### iOS

- Background App Refresh handles periodic sync.
- APNs (Apple Push Notification service) provides zero-content wake-up signals. (iOS is not a currently shipped platform; the §7.8 push-rejection decision is Android-specific. iOS architecture for push will be designed at the time iOS ships, with the same "no third party" constraint applied — the conclusion may differ because Apple's APNs operates differently from Google FCM, but the decision is not yet locked.)
- Badge count on app icon shows unread messages.
- iOS limits background execution time; Cleona maximizes each sync window.
- Tapping the app icon or notification opens the GUI.

### 18.3 Bootstrap Node as Headless Service

The bootstrap node (see Chapter 2.5) is simply the background service layer deployed as a headless daemon on a VPS — no GUI, no tray icon, no user interaction. It runs the **exact same code** as any other Cleona node's background service.

Deployment: `dart compile exe` → headless binary on a Linux VPS (via `nohup` or `systemd-run`).

**Important:** The headless binary must be built separately with `dart compile exe lib/headless.dart -o build/cleona-headless`. `flutter build linux` does NOT rebuild the headless binary. The headless binary requires `runZonedGuarded` for proper async error handling — without it, unhandled async exceptions crash the process silently. The headless entry point creates its own `NetworkChangeHandler` with IP polling (10-second interval) since `connectivity_plus` is not available outside Flutter (see Section 2.7).

#### 18.3.1 Bootstrap IPv6 Reachability (Production Setup)

Where the hosting network provides native IPv6 via DHCPv6 Prefix Delegation (IA_PD), the Bootstrap should be assigned a globally-routable v6 alongside its IPv4 port-forward — the Cleona transport already listens dual-stack per §27.3, so no code change is required. Three design choices make such a setup survive ISP-driven prefix rotations (common on German consumer DSL, e.g. Telekom/M-Net force a new /56 on each reconnect):

1. **Stable interface-ID on the Bootstrap.** With the kernel default of RFC 7217 stable-privacy (`addr_gen_mode=2`/`3`), the interface identifier is a hash of the prefix — *when the prefix rotates, the IID rotates with it*, and every upstream firewall rule referencing the old IID becomes stale within 24 h. Switch the Bootstrap interface to **EUI-64** (`addr_gen_mode=0` via sysctl, or `ipv6.addr-gen-mode eui64` on a NetworkManager connection), or set an `ipv6.token` (e.g. `::b007`) for a human-readable IID. Both modes keep the IID constant across prefix rotations; only the /64 prefix part changes.
2. **Perimeter firewall pass on the segment, not the host address.** The OPNsense firewall rule for inbound IPv6 UDP on the daemon's port should use destination *"DMZ net"* (or the equivalent dynamic-segment alias), not a literal `/128` host address. The segment alias is bound to the current delegated /64 and auto-updates when the prefix rotates; a host-address rule becomes stale the same way the Bootstrap's own address would.
3. **Edge-CPE firewall permit bound to the PD-client, not the endpoint.** FRITZ!Box port forwardings are always device-scoped and the GUI offers only *interface-ID + heuristically computed /64* as the permit target — for a host *behind* another router (Bootstrap behind OPNsense) the heuristic combines the ID with the wrong /64 (typically the IA_NA /64 assigned to the downstream router's WAN, not the IA_PD /60 delegated to it), so the permit silently points at a non-existent address and traffic is dropped with *Administratively prohibited*. The fix is to configure the port-forward device entry on the **PD-client itself** (OPNsense/WAN-side MAC) rather than on the endpoint Bootstrap, and to tick the `Firewall für delegierte IPv6-Präfixe dieses Gerätes öffnen` checkbox. That opens the permit for any address in the delegated prefix on the specified ports, which is the IPv6-native intent and survives prefix rotations transparently. Because IPv6 forwarding has no NAT, this device swap is purely a firewall-scope concern and does not affect the IPv4 port-forward, which remains configured on the endpoint's device entry as before.

Example deployment chain observed in the reference infrastructure: ISP delegates **/56** → edge CPE (FRITZ!Box) retains its own /64 on the LAN, assigns a separate /64 to OPNsense-WAN via IA_NA, and passes a **/60** downstream to OPNsense via IA_PD → OPNsense uses *Track Interface* on DMZ with `Request prefix only` on WAN so the DMZ interface receives a **/64** slice from the /60 while the WAN itself keeps only IA_NA + link-local + ULA → the Bootstrap picks up a global SLAAC address in the DMZ /64 with its EUI-64 IID. Stale delegations on the edge CPE (from earlier /64-only negotiations or from before a prefix rotation) can linger as secondary routes; a CPE reboot clears the DHCPv6 lease state cleanly and is occasionally necessary.

**Revision 2026-04-24 — replacing option (3) with OPNsense-side port-forward via VIP + 1:1 NAT.** FRITZ!OS emits a daily `Änderungsnotiz Portfreigabe` mail for any permit with the `Firewall für delegierte IPv6-Präfixe` checkbox ticked, flagging the downstream delegation as *Exposed Host* because the FRITZ!Box firewall itself is disabled for the entire /60. The warning is technically accurate — the checkbox *is* a blanket-permit for the /60 — and the user's request was an equivalent reachability without that warning. The revised layout:

1. **OPNsense WAN Virtual IP** (type `IP Alias`) with a freely chosen IID in the IA_NA /64, e.g. `2001:db8:a::5701::b00f/128`. OPNsense claims the address via NDP, so the FRITZ!Box sees a new device directly on its LAN segment.
2. **OPNsense 1:1 NAT (binat)** mapping external `::b00f` ↔ internal `<bootstrap-DMZ-v6>/128`, direction WAN, destination `any`. `binat` is bidirectional: incoming packets to `::b00f` have their destination rewritten to the Bootstrap's real DMZ address; outgoing packets from the Bootstrap have their source rewritten to `::b00f`. (This is a NAT66-shaped construct despite being generally discouraged — it is the unavoidable cost of the address-hopping required by FRITZ!OS-UI, not an IPv6 topology choice.)
3. **OPNsense WAN filter rule** `pass in on WAN inet6 proto {tcp udp} to <bootstrap-DMZ-v6>/128 port 8080-8081` (evaluated post-binat on inbound), narrowing the permit to just the Bootstrap's service ports.
4. **FRITZ!Box port-forward device entry** for OPNsense with IPv6 Interface-ID `::b00f`, **without** the *Exposed-Host-for-delegated-prefixes* checkbox. The four TCP/UDP 8080/8081 port rules then target `2001:db8:a::5701::b00f` (computed by FRITZ!OS from its own IA_NA /64 + the manually entered IID — correct by construction since `::b00f` really is in that /64). FRITZ!Box no longer logs the entry as Exposed-Host and stops emitting the daily notification mail.

Compared to the original option (3), the revised setup **loses the prefix-rotation resilience that option (3)'s delegated-prefix permit provided automatically**. `::b00f` and the binat's `source_net` both reference specific /64-prefix literals that become stale on an ISP-driven /56 rotation; a simple OPNsense devd/rc.newwanipv6 hook that rewrites both fields is the natural fix but has not been implemented in this deployment. In-flight mitigations are (a) asking the ISP for a static prefix (available by statute in Germany since the Bundesnetzagentur clarification of 2020), and (b) a follow-up OPNsense script slot. Both are out of the present session's scope.

### 18.4 Service Layer Architecture

The background service consists of several specialized components that work together:

```
┌─────────────────────────────────────────────────────┐
│  CleonaService (Orchestrator)                       │
│  - Lifecycle management (start/stop/PID file)       │
│  - Wires all components together                    │
│  - Manages conversations and message state          │
│  - Mailbox poll (startup + post-restore only)        │
│  - Message deduplication by messageIdHex            │
│  - Group/channel media routing (sendFile, sendVoice)│
│  - File path tracking (filePath on UiMessage)       │
│  - Profile picture/description management           │
│  - DB encryption (flush timer, closeEncrypted)      │
│  - Network change handling (delegates to node)      │
├─────────────────────────────────────────────────────┤
│  CleonaNode (Network Core)                          │
│  - UDP primary, TLS anti-censorship fallback (p+2)  │
│  - Kademlia DHT: routing, lookup, store/retrieve    │
│  - Fragment store/retrieve/delete handlers          │
│  - Peer list exchange (Summary → Want → Push)       │
│  - Message signing and dispatch                     │
│  - Stale Ed25519/ML-DSA key recovery on mismatch   │
│  - IPv6 multicast discovery + IPv4 local broadcast  │
│  - NAT traversal (peer-reported addresses)          │
│  - Network change handling (NAT reset, re-discover) │
├─────────────────────────────────────────────────────┤
│  MessageSender                 MessageReceiver      │
│  - Direct delivery (UDP)       - Fragment reassembly│
│  - Erasure-coded backup        - Reed-Solomon decode│
│  - PK lookup chain             - Local fragment DB  │
│  - Dual-delivery logic         - UTF-8 safe decode  │
│  - Ephemeral type detection    - Pre-DR dedup       │
│  - Restore type detection      - Binary type guard  │
├─────────────────────────────────────────────────────┤
│  KeyManager            ContactManager    MessageHandler│
│  - Per-Message KEM     - Contact requests - Text/media│
│  - Key rotation        - Accept/reject    - Reactions  │
│  - PK distribution     - Message gate     - Receipts   │
│  - Call key negot.     - PoW verification - Edit/Delete│
│  - Ephemeral cleanup   - Mutual auto-acc. - Groups     │
│  - Recipient PK lookup - Profile pic/desc - Channels   │
├─────────────────────────────────────────────────────┤
│  GroupManager          ChannelManager    RestoreService│
│  - Group CRUD          - Channel CRUD   - Seed/phrase │
│  - Member management   - Member mgmt   - Shamir SSS  │
│  - Picture/description - Picture/desc   - DHT registry│
│  - Invite with members - Invite flow    - DHT snapshot│
│  - Role enforcement    - Role enforce   - Key derivat.│
├─────────────────────────────────────────────────────┤
│  ClipboardHelper (Linux)                            │
│  - wl-paste (Wayland) / xclip (X11) detection       │
│  - Binary content extraction (images, files)        │
│  - MIME type detection, suggested filename           │
└─────────────────────────────────────────────────────┘
```

**CleonaService** is the central orchestrator. It initializes CleonaNode, MessageSender, MessageReceiver, KeyManager, ContactManager, MessageHandler, GroupManager, ChannelManager, and RestoreService. It wires their callbacks together and manages the application-level state (conversations, unread counts, notifications). It also runs the startup mailbox poll, DB encryption flush timer, DHT restore snapshot timer, and deduplicates messages received via both direct and erasure-coded paths.

**MessageSender** implements the dual-delivery pattern: direct UDP send + erasure-coded backup (with RUDP ACK-driven delivery) for every non-ephemeral message. It resolves the recipient's mailbox ID through the PK lookup chain (RoutingTable → ContactManager → nodeId fallback). It detects ephemeral types (typing, receipts) and restore types (RESTORE_BROADCAST/RESPONSE) to skip Per-Message KEM encryption or erasure coding as appropriate.

**MessageReceiver** collects retrieved fragments from DHT mailbox polling (startup) and proactive push (runtime), stores them locally, and triggers Reed-Solomon reconstruction when K=7 fragments are available for a message ID. Reassembled messages are routed back through CleonaNode for decryption and UI delivery. **Important:** `_decodePayload()` must NOT call `utf8.decode()` on binary Protobuf types (GROUP_INVITE, GROUP_KEY_UPDATE, CHANNEL_POST, etc.) — only TEXT, TYPING_INDICATOR, MESSAGE_EDIT, MESSAGE_DELETE are UTF-8 decoded.

**_onReassembledMessage** must handle ALL non-standard message types: RESTORE_BROADCAST, RESTORE_RESPONSE, CHAT_CONFIG_UPDATE, CHAT_CONFIG_RESPONSE, IDENTITY_DELETED, PROFILE_UPDATE. Missing cases cause erasure-coded messages of these types to be silently ignored.

### 18.5 Implications for Code Architecture

The separation of service and GUI means:

- The **CleonaNode** and all its dependencies (DHT, crypto, database, transport) must be fully functional without Flutter or any GUI framework.
- The GUI communicates with CleonaService via in-process Dart method calls (same process) or, in future, via local IPC for true process separation.
- All state is persisted in the encrypted SQLite database — the GUI is a stateless view that can be attached and detached at will.
- The CleonaNode must be self-contained: it manages its own lifecycle, handles errors internally, and logs to persistent storage for diagnostics.
- The CleonaService must be self-contained: it handles message routing, deduplication, and offline delivery coordination without GUI involvement.

### 18.6 UI Message Chain & Media Display

Messages flow from CleonaService to the GUI through a data chain:

1. **UiMessage** (service layer): Contains `filePath` — the local filesystem path where received media is stored. Set by `onFileMessage`, `onVoiceMessage`, `_saveGroupMedia()`, and `_saveChannelMedia()` callbacks. Also set on the sender side when `sendFile()` saves a local copy.

2. **UiConversation** (service layer): Extended with `peerProfilePicture` and `peerDescription` fields for displaying contact profile data in the conversation list.

3. **ChatMessage** (chat_screen.dart): Maps `UiMessage.filePath` to `ChatMessage.filePath` for the UI layer. Includes `senderProfilePicture` for group message display.

4. **MessageBubble** (message_bubble.dart): Renders messages with media-aware display:
   - **Image files** (.png, .jpg, .jpeg, .gif, .webp, .bmp): Shown as inline thumbnail preview via `Image.file()` with `ClipRRect` (max height 250px). Tapping opens a fullscreen dialog with `InteractiveViewer` for pinch-to-zoom and pan. The fullscreen dialog includes an `errorBuilder` that shows a broken-image icon instead of a blank screen if the file cannot be loaded. An "open externally" button launches `xdg-open`.
   - **Non-image files**: Shown with a file icon and clickable underlined filename. Tapping opens via `xdg-open`.
   - **Voice messages**: Shown with audio player controls.
   - **Download/Save button**: Received files and images show a download icon button that saves the file to the user's configured download directory (see Section 15.6.3). The save operation includes self-copy protection to prevent 0-byte file corruption.

### 18.6.1 Navigation & Conversation Tabs

The home screen uses a `NavigationBar` with 6 tabs for organizing conversations:

| Tab | Icon | Content |
|-----|------|---------|
| Recent | clock | All conversations sorted by last message time (most recent first) |
| Favorites | star | Only conversations marked as favorite, sorted by time |
| Chats | chat_bubble | 1:1 DM conversations only |
| Groups | group | Group conversations only |
| Channels | campaign | Private channel conversations only |
| Inbox | mail | Pending contact requests |

**Favorites:** Users can mark/unmark conversations as favorites via the 3-dot menu (PopupMenuButton ⋮) on each conversation tile — first entry "Als Favorit markieren / Aus Favoriten entfernen". Favorited conversations show a small star indicator on their avatar in all tabs. The favorites list is persisted per identity.

**Conversation tiles:** Each conversation tile shows the contact's/group's/channel's profile picture in a CircleAvatar (with initials fallback). Groups show a group icon, channels show a campaign icon.

**Floating Action Button:** Visible on the Chats tab for creating new conversations (contact picker or manual Node-ID entry).

### 18.6.2 GUI Layout Sketch

#### Home Screen (Main View)

```
+---------------------------------------------------------------+
| AppBar: "Cleona - {Identity Name}" [Lang] [Conn] [Stats] [Cal] [Cfg] |
+---------------------------------------------------------------+
| Identity Tabs (horizontal, scrollable)                        |
| [*Alice*] [ Bob (3) ] [ Work ] [ + ]                          |
+---------------------------------------------------------------+
| Node ID: bb298992a4c1...  [Copy]                              |
+---------------------------------------------------------------+
|                                                               |
| +-----------+---------------------------------+-------+-----+ |
| | (o) John Doe                               | 14:32 |  :  |  |
| |     OK, see you tomorrow!                  |       |     |  |
| +-----------+---------------------------------+-------+-----+ |
| | [G] Project Group Alpha                    | 13:10 |  :  |  |
| |     Bob: I pushed the fix                  |       |     |  |
| +-----------+---------------------------------+-------+-----+ |
| | (o) Lisa Smith                             |yesterd|  :  |  |
| |     [file] screenshot.png                  |       |     |  |
| +-----------+---------------------------------+-------+-----+ |
| | [C] Dev Channel                            | Mon   |  :  |  |
| |     Release v2.1 is out                    |       |     |  |
| +-----------+---------------------------------+-------+-----+ |
|                                                               |
|                                                    [+] FAB    |
+---------------------------------------------------------------+
| BottomNavigationBar (6 Tabs)                                  |
| [Recent] [Favs] [Chats(2)] [Groups(1)] [Chan.] [Inbox(3)]     |
+---------------------------------------------------------------+
```

**AppBar actions (top right):** Language picker (flag emoji), Connection Status mascot (see below), Network Stats (bar chart icon + peer count chip), Calendar, Settings gear.

**Connection Status Icon (P2P-aware, 5-tier since V3.1.69):** A character icon between the language flag and the network-stats chip shows the device's actual P2P reach. Combines OS network detection (`connectivity_plus`) with real peer reachability (`CleonaNode.confirmedPeerIds`) and the reachability class (public/NAT/CGNAT/mailbox-only). Five tiers, rendered in `lib/ui/screens/home_screen.dart` (`enum ConnectionTier`):
- **`strong`** (`assets/conn_strong.png`): Fully reachable P2P, public address + direct connections active (no relay/fallback).
- **`good`** (`assets/conn_good.png`): P2P reachable, but behind NAT — hole punch worked, some peers only via relay.
- **`medium`** (`assets/conn_medium.png`): Only reachable via mobile or CGNAT (mobile-fallback socket active OR ipify reports `100.64.0.0/10` / `192.0.0.0/24`). Inbound direct reach unlikely.
- **`weak`** (`assets/conn_weak.png`): No direct P2P routes — delivery only via store-and-forward / mailbox / Reed-Solomon backup. Effectively async mode.
- **`offline`** (`assets/conn_skeleton.png`): No network available.

All 5 asset files have a transparent background (light- and dark-theme compatible). Tooltip per tier in 33 languages, plus 4 new i18n keys `conn_good`, `conn_mobile_explain`, `conn_searching_explain`, `conn_offline_explain` (full 33-locale coverage as of V3.1.70 per §13.1.5).

**Tap behaviour:** Tapping the icon at tiers `good`/`weak`/`offline` opens the NAT wizard directly (see §27.9), because port-forwarding can actually help there. At `medium` (mobile/CGNAT, where the CPE is not the bottleneck) an explanation dialog appears instead, with pointers to §27.4 (CGNAT bypass) and §27.8 (mobile fallback). At `strong` the icon is non-tappable (nothing to do).

**Hulk-icon stale-route fix (V3.1.69):** `CleonaNode.confirmedPeerIds` (`lib/core/node/cleona_node.dart`) is filtered on the getter side: a peer is only counted as "confirmed" if it has **either** a live direct route (`consecutiveRouteFailures < 3`) **or** a live relay route (`consecutiveRelayFailures < 3 && relayViaNodeId != null`). Previously the internal `_confirmedPeers` set was write-only and never shrank, so the green/"Hulk" status was shown even when all routes to all once-confirmed peers were dead — a visually false "fully connected" indicator on an actually isolated device. The filter happens lazily on each query; the internal set is no longer maintained explicitly.

`confirmedPeerCount` flows unchanged from `CleonaNode` via IPC (`state_changed` event) to the desktop GUI, or via direct reference (`_androidNode.confirmedPeerIds.length`) to the Android in-process GUI. The reachability class (public/NAT/CGNAT) is derived from the already-present signals `NetworkStats.upnpStatus`, `pcpStatus`, `Transport.mobileFallbackActive` and the ipify address — no new probing.

**NetworkStatsCollector ownership (#U5):** The shared collector lives on `CleonaNode` (`node.statsCollector`), not per-CleonaService. The transport is owned by the node and fans out every UDP frame to a single counter pair; wiring it per-Service via `??=` (the previous design) caused only the first identity to start to win the receive callback, so all later identities saw byte counters stuck at 0. `markStarted` is called once in `node._startBase`, so uptime survives a second/third identity boot. Per-identity `messagesSent`/`messagesReceived` is therefore a daemon-wide aggregate on Multi-Identity setups — accepted trade-off for the architectural simplification.
**Identity Tabs:** Active identity highlighted, inactive show unread badge, "+" creates new identity.
**FAB:** Context-dependent — Chats: "Add Contact", Groups: "New Group", Channels: "New Channel".
**Unread badges:** Each bottom tab shows a badge with the unread count for its category.
**Sorting:** Unread conversations appear at the top of every tab, then by timestamp (newest first).
**Tab search filter:** Magnifier icon at the top right of every tab. On tap a search bar slides in (AnimatedCrossFade). Filters conversations by display name and last message.

#### Chat Screen (Conversation View)

```
+---------------------------------------------------------------+
| <- AppBar: "Max Mustermann"                     [Call] [Cfg]  |
+---------------------------------------------------------------+
|                                                               |
|                        +----------------------------+         |
|                        | Hey, wie laeuft's?     vv  |  (own)  |
|                        |                      14:30 |         |
|                        +----------------------------+         |
| +----------------------------+                                |
| | Gut! Schau mal:            |                       (peer)   |
| | +----------------------+   |                                |
| | | [img] screenshot.png |   |                                |
| | | (image preview)      |   |                                |
| | +----------------------+   |                                |
| |                      14:31 |                                |
| +----------------------------+                                |
|                        +----------------------------+         |
|                        | Alles klar, bis morgen!    |  (own)  |
|                        |                   vv 14:32 |         |
|                        +----------------------------+         |
|                                                               |
|                                         Max tippt...          |
+---------------------------------------------------------------+
| [reply-to: "Schau mal:"                                x ]    |
+---------------------------------------------------------------+
| [Emoji] Nachricht eingeben...     [Paste] [Mic] [Clip] [>>]   |
+---------------------------------------------------------------+
```

**Message bubbles:** Own messages right-aligned (blue), peer messages left-aligned (grey). Status indicators: v sent, vv delivered, colored vv read. Color emoji rendering via fontFamilyFallback (Noto Color Emoji on Linux, Segoe UI Emoji on Windows, Apple Color Emoji on iOS/macOS).
**Media:** Images shown as inline thumbnail (max 250px), tap for fullscreen with pinch-to-zoom. Files shown as icon + filename, tap to open via `xdg-open`.
**Input area:** Emoji toggle, text field, clipboard paste, voice record, attachment picker, send button.
**3-dot menu on message (PopupMenuButton ⋮ top right):** Context menu with Reply, Forward, React (emoji grid), Edit (own messages, within edit window), Delete (own messages), Copy text, Save media (for media messages). Uniform UX pattern with all other screens (see `docs/UI.md` §Message Bubbles). Long-press is **not** the gesture — the 3-dot overlay sits visibly on the bubble.
**Message search:** Magnifier icon in the AppBar. On tap a search bar replaces the title. Up/down arrows navigate between hits, counter "X of Y". The active hit is highlighted (tertiary color + border) and auto-scrolled into view.

#### Inbox Tab (Contact Requests & Invites)

```
+---------------------------------------------------------------+
|                                                               |
| +-----------------------------------------------------------+ |
| | [?] Unknown (a7f3b2...)                Contact Request    | |
| | "Hi, this is Tom from the office"                         | |
| |                                [Accept]       [Reject]    | |
| +-----------------------------------------------------------+ |
| | [G] Project Group Beta                 Group Invite       | |
| | from: Lisa Smith                                          | |
| |                                [Accept]       [Reject]    | |
| +-----------------------------------------------------------+ |
| | [C] News Channel                       Channel Invite     | |
| | from: Admin                                               | |
| |                                [Accept]       [Reject]    | |
| +-----------------------------------------------------------+ |
|                                                               |
+---------------------------------------------------------------+
```

#### Screen Map (Navigation Overview)

```
                    ┌──────────────┐
                    │  SetupScreen │ ← First launch only
                    │  (Name+Pass) │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
              ┌─────│  HomeScreen  │─────┐
              │     │  (6 Tabs)    │     │
              │     └──┬───┬───┬───┘     │
              │        │   │   │         │
     ┌────────▼──┐  ┌──▼───▼┐ │  ┌──────▼──────┐
     │ Settings  │  │ Chat  │ │  │ AddContact  │
     │ -Profile  │  │Screen │ │  │ -QR Scan    │
     │ -Theme    │  │-Msgs  │ │  │ -Node ID    │
     │ -Language │  │-Media │ │  │ -QR Display │
     │ -Recovery │  │-Voice │ │  └─────────────┘
     │ -QR Code  │  │-React │ │
     └───────────┘  └───────┘ │  ┌─────────────┐
                               ├──│CreateGroup  │
                               │  │-Name, Pic   │
                               │  │-Members     │
                               │  └─────────────┘
                               │  ┌─────────────┐
                               ├──│CreateChannel│
                               │  └─────────────┘
                               │  ┌─────────────┐
                               ├──│NetworkStats │
                               │  │-Peers, DHT  │
                               │  │-LAN, Boot.  │
                               │  └─────────────┘
                               │  ┌─────────────┐
                               └──│IdentityList│
                                  │-Switch/Del  │
                                  └─────────────┘
```

#### 18.6.3 Settings-Hilfetexte (V3.1.69)

In `lib/ui/screens/settings_screen.dart` a small `?` icon (`_HelpButton` widget) is rendered next to settings titles that are not technically self-explanatory. Tap opens a BottomSheet with an explanation, without touching the actual setting value or navigating away — pure inline information. The pattern is uniform across all settings that need explanation, so users don't have to guess what e.g. "Network Tag" or "Encryption" actually does.

10 settings ship with help text in V3.1.69: `port`, `show_recovery_phrase`, `guardian_setup`, `device_management`, `media_settings`, `notification_settings`, `archive_settings`, `transcription_settings`, `encryption`, `network_tag`. Texts live in the i18n system as `<setting>_help` keys with full 33-locale coverage (V3.1.70 per §13.1.5). No new screen, no new state — just the help buttons + the 10 i18n keys.

### 18.7 Clipboard Integration (Linux)

Cleona integrates with the Linux clipboard for pasting binary content (screenshots, images, files):

**ClipboardHelper** (`lib/core/media/clipboard_helper.dart`): Detects the available clipboard tool (`wl-paste` for Wayland, `xclip` for X11) and extracts clipboard content with MIME type detection. Returns a `ClipboardContent` object with `data`, `mimeType`, `isText`, `isImage`, `isAudio`, and `suggestedFilename`.

**Ctrl+V Interception**: The text input field is wrapped in a `Focus` widget with an `onKeyEvent` handler. When Ctrl+V is pressed and `onPasteContent` is available, the handler calls `_handleCtrlV()` which:
1. Checks the clipboard via `ClipboardHelper.getContent()`
2. If text content: performs normal text paste into the TextField
3. If binary content: shows a confirmation dialog with file type, size, and image preview (for images), then sends via `onPasteContent` callback

**Paste button**: A dedicated clipboard paste button (content_paste icon) in the input area allows explicit paste without keyboard shortcut.

**Requirements**: `wl-clipboard` (Wayland) or `xclip` (X11) must be installed on the system. Without these tools, clipboard paste for binary content is unavailable (text paste still works via Flutter's built-in mechanism).

### 18.8 Notifications, Sounds & Vibration

Cleona provides audio and haptic feedback for incoming events, fully configurable per identity.

#### 18.8.1 Sound Events

| Event | Sound | Behavior |
|-------|-------|----------|
| Incoming message | Short notification tone | Single play, respects Do Not Disturb |
| Incoming call | Ringtone (looping) | Loops until accept/reject/timeout (60s) |
| Call connected | Short confirmation beep | Single play |
| Outgoing call ringing | Ringback tone | Loops until remote answers/rejects |

#### 18.8.2 Ringtone Selection

6 built-in ringtones available for incoming calls:

| # | Name | Character |
|---|------|-----------|
| 1 | Gentle | Soft marimba melody |
| 2 | Classic | Traditional phone ring |
| 3 | Pulse | Modern rhythmic beep pattern |
| 4 | Chime | Bell-like tones |
| 5 | Echo | Spacious ambient alert |
| 6 | Bright | Cheerful upbeat tone |

Ringtones are stored as Ogg Vorbis files in `assets/sounds/` (~30-50 KB each). Playback via `just_audio` (already in the project). Looping is handled by `just_audio`'s `LoopMode.one`.

#### 18.8.3 Vibration

Android only (via `HapticFeedback` or platform channel to Android Vibrator API):
- **Incoming message:** Short pulse (100ms)
- **Incoming call:** Repeating pattern (500ms on, 500ms off) until answer/reject

Linux: No vibration (desktop has no vibration motor).

#### 18.8.4 Notification Settings

Persisted in `notification_settings.json` per identity profile:

```json
{
  "soundEnabled": true,
  "vibrationEnabled": true,
  "messageSoundEnabled": true,
  "callRingtone": "gentle",
  "callVolume": 0.8
}
```

**Settings UI:** New section "Notifications" in the Settings screen:
- Toggle: Sounds on/off (master switch)
- Toggle: Vibration on/off (Android only, hidden on Desktop)
- Toggle: Message tones on/off
- Dropdown: Select ringtone (6 options, preview on selection)
- Slider: Ringtone volume

#### 18.8.5 Implementation

**NotificationSoundService** (`lib/core/service/notification_sound_service.dart`):
- Singleton, initialized with settings from disk
- `playMessageSound()` — plays message notification once
- `startRingtone(String name)` — starts looping ringtone
- `stopRingtone()` — stops looping ringtone
- `playRingback()` — plays outgoing ringback tone
- `stopRingback()` — stops ringback
- `vibrate(VibrationType type)` — triggers platform vibration

Integration points in `CleonaService`:
- `_handleTextMessage()` / `_handleMediaContent()` → `playMessageSound()` + `vibrate(message)`
- `_handleCallInvite()` → `startRingtone()` + `vibrate(call)`
- `_handleCallAnswer()` → `stopRingtone()` + `playConnected()`
- `_handleCallReject()` / `_handleCallHangup()` → `stopRingtone()`
- `startCall()` → `playRingback()`

#### 18.8.6 Notification Suppression Layers (#U18 L1+L2)

Three independent layers gate the in-app notification (sound + vibrate + Android banner) for incoming messages. They live in `_shouldSuppressNotification(conversationId, messageTimestampMs)` in `cleona_service.dart`. Badge updates run on a different code path and are NOT gated.

**L1 — Foreground active conversation.** When the chat screen for the receiving conversation is on screen AND the app lifecycle is `AppLifecycleState.resumed`, the message is already visible inline; a banner is redundant. State sources:
- `_activeConversationId` set by `ChatScreen.initState` (post-frame), cleared in `dispose`. Wired via `ICleonaService.setActiveConversationId(String?)`.
- `_isAppResumed` mirrors `AppLifecycleState.resumed`, propagated by `main.dart`'s lifecycle observer to every per-identity service. Defaults to `true` so the app behaves like "foreground" before the first event arrives.
- `IpcClient` stubs both methods as no-ops. The desktop daemon emits notifications in its own process, where foreground tracking would require IPC roundtrips — out of scope for the Android-targeted L1 fix.

**L2 — Stale-backlog suppression.** Messages with `now - timestamp > 30 s` (`_notificationStaleThresholdMs`) only update the badge. Catches the Startup-Re-Poll burst (#U1), daemon restarts, and S&F catch-up — beeping over old news is noise.

**L3 — Per-conversation debounce.** At most one notification per 2 s per conversation (`_notificationDebounceMs`). `_lastNotifiedAt` records wall-clock of the last fire; subsequent messages in the same conv within the window are silent. Group-chat burst protection.

---

## 23. Calendar

Cleona provides a fully decentralized calendar that works across all of a user's identities, enabling unified management of private and professional schedules without any server infrastructure. The calendar integrates with group calls (Section 4.4.2) and polls (Section 24) to provide a complete scheduling and meeting workflow.

### 23.1 Design Principles

1. **Identity-spanning:** All identities derived from the same master seed (Section 5.2) share a single calendar view. If AllyCat has a meeting at 14:00, Alice's calendar shows that time as blocked. External contacts querying Alice's availability see "busy" without learning that it is an AllyCat appointment.
2. **Privacy-first:** No calendar data is stored in the DHT or on any remote node. All events are stored locally in the encrypted database (Section 4.7). Sharing happens exclusively through explicit invitations and controlled Free/Busy responses.
3. **Offline-capable:** Calendar events are local-first. Group invitations are delivered via the existing Three-Layer Delivery (Section 3.3.1) and work even when participants are offline.
4. **Standards-compatible:** The internal data model is designed for iCal/CalDAV compatibility from day one, enabling future sync with Google Calendar, Thunderbird, Nextcloud, and other calendar systems.

### 23.2 Data Model

#### 23.2.1 CalendarEvent

```
CalendarEvent {
  eventId:          UUID (random, globally unique)
  identityId:       bytes (which identity owns this event)
  title:            string
  description:      string (optional, Markdown)
  location:         string (optional)
  startTime:        int64 (Unix milliseconds)
  endTime:          int64 (Unix milliseconds)
  allDay:           bool
  timeZone:         string (IANA timezone, e.g. "Europe/Berlin")

  // Recurrence (RRULE-compatible)
  recurrenceRule:   string (optional, RFC 5545 RRULE format, e.g. "FREQ=WEEKLY;BYDAY=MO")
  recurrenceExceptions: List<int64> (excluded dates as Unix ms)

  // Categorization
  category:         EventCategory (APPOINTMENT | TASK | BIRTHDAY | REMINDER | MEETING)
  color:            int32 (optional, ARGB for visual grouping)
  tags:             List<string> (optional, user-defined labels)

  // Task-specific fields (category == TASK)
  taskCompleted:    bool
  taskDueDate:      int64 (optional, deadline)
  taskPriority:     int32 (0=none, 1=low, 2=medium, 3=high)

  // Birthday-specific fields (category == BIRTHDAY)
  birthdayContactId: bytes (optional, linked contact's node ID)
  birthdayYear:     int32 (optional, birth year for age calculation, 0 = unknown)

  // Group/Call integration
  groupId:          bytes (optional, linked group/channel ID)
  hasCall:          bool (if true, a group call can be started from this event)
  callStarted:      bool (runtime flag, not persisted in invite)

  // Reminders
  reminders:        List<ReminderOffset> (e.g. [5min, 15min, 1h, 1d before])

  // Visibility control for Free/Busy queries
  freeBusyVisibility: FreeBusyLevel (FULL | TIME_ONLY | HIDDEN)
  visibilityOverrides: Map<nodeIdHex, FreeBusyLevel> (per-contact overrides)

  // Metadata
  createdAt:        int64
  updatedAt:        int64
  createdBy:        bytes (node ID of creator, relevant for group events)
}

enum EventCategory {
  APPOINTMENT = 0;
  TASK = 1;
  BIRTHDAY = 2;
  REMINDER = 3;
  MEETING = 4;
}

enum FreeBusyLevel {
  FULL = 0;       // Title, description, location, time visible
  TIME_ONLY = 1;  // Only "busy from X to Y" visible (no content)
  HIDDEN = 2;     // Not visible in Free/Busy queries at all
}

message ReminderOffset {
  int32 minutesBefore = 1;  // 5, 15, 60, 1440 (=1 day), etc.
}
```

#### 23.2.2 CalendarInvite (Group Events)

When a user creates an event linked to a group (`groupId` set), an invitation is distributed to all group members via Pairwise Fanout (Section 4.5):

```
CalendarInvite {
  eventId:      UUID
  title:        string
  description:  string
  location:     string
  startTime:    int64
  endTime:      int64
  allDay:       bool
  timeZone:     string
  recurrenceRule: string (optional)
  hasCall:      bool
  groupId:      bytes
  createdBy:    bytes (inviter's node ID)
  createdByName: string (inviter's display name)
  rsvpDeadline: int64 (optional, Unix ms)
}
```

The invite appears both in the recipient's calendar and as an interactive card in the group chat (see Section 23.7).

#### 23.2.3 RSVP Response

```
CalendarRsvp {
  eventId:      UUID
  response:     RsvpStatus (ACCEPTED | DECLINED | TENTATIVE | PROPOSE_NEW_TIME)
  proposedStart: int64 (optional, only when PROPOSE_NEW_TIME)
  proposedEnd:  int64 (optional, only when PROPOSE_NEW_TIME)
  comment:      string (optional, e.g. "Can we do 15:00 instead?")
}

enum RsvpStatus {
  ACCEPTED = 0;
  DECLINED = 1;
  TENTATIVE = 2;
  PROPOSE_NEW_TIME = 3;
}
```

RSVP responses are sent via Pairwise Fanout to all group members, so everyone sees who accepted/declined. The event creator aggregates responses and can update the event time if enough participants propose an alternative.

### 23.3 Free/Busy Protocol

The Free/Busy protocol enables privacy-controlled schedule visibility during event planning, similar to Exchange/CalDAV Free/Busy but fully decentralized and end-to-end encrypted.

#### 23.3.1 Visibility Model

Each user configures a **default Free/Busy level** and optional **per-contact overrides**:

| Level | What the querier sees | Use case |
|-------|----------------------|----------|
| **FULL** | Title + time + location | Close team members, family |
| **TIME_ONLY** | "Busy 14:00–15:30" (no content) | Professional contacts, boss |
| **HIDDEN** | No data returned for this event | Private appointments the querier should not know about |

The default applies globally. Per-contact overrides take precedence. Example: Default = TIME_ONLY, but for contact "Max" = FULL, for contact "Recruiter" = HIDDEN.

**Cross-identity privacy:** When a Free/Busy query arrives for identity Alice, the response includes blocked times from ALL identities (Alice + AllyCat + ...) but labels them all as Alice's. The querier cannot distinguish which identity caused the block. This is the key feature enabling unified private/professional calendar management.

#### 23.3.2 Request/Response Protocol

```
FreeBusyRequest {
  queryStart:   int64 (Unix ms, start of the query window)
  queryEnd:     int64 (Unix ms, end of the query window)
  requestId:    UUID (for response correlation)
}
```

```
FreeBusyResponse {
  requestId:    UUID
  blocks:       List<FreeBusyBlock>
}

FreeBusyBlock {
  start:        int64
  end:          int64
  level:        FreeBusyLevel (FULL or TIME_ONLY — HIDDEN events are simply omitted)
  title:        string (only present if level == FULL)
  location:     string (only present if level == FULL)
}
```

**Flow:**
1. Alice wants to schedule a group meeting. She opens the scheduling assistant.
2. Alice's node sends `FREE_BUSY_REQUEST` (encrypted, Per-Message KEM) to each invitee with the desired time window (e.g., "next 7 days").
3. Each invitee's node **automatically** responds with `FREE_BUSY_RESPONSE`, filtered according to their visibility settings for Alice. HIDDEN events are omitted entirely. TIME_ONLY events return only start/end. FULL events include title and location.
4. Alice sees a merged availability grid (like Outlook's Scheduling Assistant) showing free/busy for all participants. She picks a slot where everyone is available.

**Automatic response:** The Free/Busy response is generated and sent automatically by the recipient's node — no user interaction required. This works even when the recipient's GUI is closed (the daemon handles it). The user configures their visibility preferences once; responses are generated from the local calendar database.

**Rate limiting:** Free/Busy requests are subject to the same rate limits as regular messages (Section 9.2). A contact can query at most once per 20 seconds. Non-contacts cannot query Free/Busy at all (KEX Gate, Section 5.6.2).

### 23.4 Multi-Identity Calendar Merge

Since a Cleona user can have multiple identities (Section 5.2), the calendar must merge events from all identities into a single view while maintaining identity separation for external queries.

**Local view (owner's device):** All events from all identities are displayed in a single calendar view. Events are color-coded or labeled by identity (e.g., Alice events in blue, AllyCat events in green). The user sees their complete schedule.

**External view (Free/Busy queries):** When contact X queries identity Alice's availability, the response includes busy blocks from ALL identities but without revealing which identity caused the block. From X's perspective, Alice is simply "busy" — they cannot infer that Alice has a second identity.

**Event ownership:** Each event is owned by exactly one identity (`identityId` field). When sending a group invite, the invite comes from the owning identity. When accepting an invite, it is stored under the identity that received it.

**Identity switching in calendar:** The calendar view shows all events by default. A filter toggle allows showing only one identity's events. Creating a new event defaults to the currently active identity but can be changed via a dropdown.

#### 23.4.1 Identity scoping & roles (clarification)

To avoid confusion in multi-identity setups — all the following points are already implemented, consolidated here:

- **CalendarManager per identity.** Every identity has its own `CalendarManager` with its own encrypted persistence (`calendar_events.json.enc`, same pattern as ContactManager / PollManager).
- **CalendarSyncService per identity.** Every identity has its own `CalendarSyncService` with its own sync configuration (`calendar_sync_config.json.enc`) and its own SyncState (`calendar_sync_state.json.enc`). Providers (CalDAV/Google/LocalIcs) are opt-in per identity — Alice can sync against Nextcloud while AllyCat syncs against nothing.
- **`CalendarEvent.identityId`** binds each event uniquely to its owning identity; cross-identity moves are not supported (recreate the event + delete the old one).
- **Roles per event.** *Creator* (`createdBy == own nodeId`): full access (edit/delete/fan-out via `CALENDAR_UPDATE`/`CALENDAR_DELETE` to group members). *Invited participant*: read only + RSVP (`CALENDAR_RSVP`). No "co-edit" — changes to the event body flow exclusively from the creator.
- **Visibility.** Per-event `freeBusyVisibility` (`FULL`/`TIME_ONLY`/`HIDDEN`) plus per-contact override (`visibilityOverrides: Map<nodeIdHex, FreeBusyLevel>`). Affects only incoming `FREE_BUSY_REQUEST`s, not group invites (which see the full event body — anyone who is invited inevitably knows the time).

### 23.5 Reminders & Notifications

Reminders use the existing notification infrastructure (Section 18.8):

- **Desktop (Linux/Windows):** System notification via the tray icon daemon. Sound plays via pw-play/paplay (Section 18.8.5).
- **Android:** Android notification channel "Calendar Reminders" with configurable importance.
- **Multiple reminders per event:** The user can set multiple reminder offsets (e.g., 1 day before + 15 minutes before). Each fires independently.
- **Recurring events:** Reminders fire for each occurrence, not just the first.
- **Snooze:** Reminders can be snoozed (5 min, 15 min, 1 hour, custom).

**Daemon-driven:** Reminders are evaluated by the daemon, not the GUI. This ensures they fire even when the GUI is not running (Linux/Windows desktop tray mode).

### 23.6 Calendar Views & Printing

The calendar UI provides four views, all printable:

| View | Description |
|------|-------------|
| **Day** | Hourly timeline (00:00–23:59), events as colored blocks, all-day events at the top |
| **Week** | 7-column grid (Mon–Sun configurable), same hourly timeline per day |
| **Month** | Classic month grid, events as compact text entries per day cell |
| **Year** | 12 mini-months, days with events highlighted (dot indicator) |

**Task view:** A separate list view for tasks (category == TASK), sortable by due date, priority, or identity. Completed tasks are shown with strikethrough.

**Birthday view:** Automatically generated from contacts with `birthdayYear` set. Shows upcoming birthdays in a list and as all-day events in the calendar.

**Printing:** All views can be exported to PDF and printed via the system print dialog. The PDF renderer uses the current skin's color scheme. Options:
- Date range (custom or current view)
- Include/exclude identities
- Include/exclude task details
- Paper format (A4, Letter, A3)
- Orientation (portrait for day/list views, landscape for week/month)

### 23.7 Chat Integration

Group events create an interactive card in the group chat:

```
+----------------------------------------------+
| [Cal] Team Standup                           |
| Mon, 14 Apr 2026, 10:00-10:30                |
| Weekly (every Monday)                        |
|                                              |
| [ok] Alice   [?] Bob   [x] Charlie           |
|                                              |
| [Accept]   [Decline]  [Call >]               |
+----------------------------------------------+
```

**Features:**
- RSVP buttons directly in the chat card (no need to open the calendar)
- "Call" button appears at event start time (if `hasCall: true`)
- Clicking "Call" starts a group call (Section 4.4.2) with all accepted participants
- 15 minutes before the event, a reminder message appears in the chat
- RSVP status updates are shown as small system messages ("Bob hat zugesagt")

**Event updates:** If the creator modifies the event (time change, cancellation), a `CALENDAR_UPDATE` message is sent via Fanout. The chat card updates in-place (same `eventId`). Cancelled events show a strikethrough overlay.

### 23.8 External Calendar Sync (Phase 2)

External sync connects the Cleona calendar with existing calendar systems. This is planned as a Phase 2 feature because it requires network access to external servers — a concept otherwise foreign to Cleona's architecture.

**Transport duality (V3.1.69):** On desktop the GUI talks to the daemon-internal `CalendarSyncService` over the IPC channel (`IpcClient` methods). On Android no separate daemon process runs, so there is no IPC channel either — previously the sync configuration was simply locked out there ("Sync UI requires the IPC client"). Since V3.1.69, `lib/core/calendar/sync/in_process_bridge.dart` (`InProcessCalendarSyncBridge`) provides an API that mirrors the `IpcClient` calendar-sync interface 1:1 (same method names, same callback names) and forwards calls directly to `CleonaService.calendarSyncService`. The `CalendarSyncScreen._ipc` getter is `dynamic`-typed (duck dispatch), so the exact same screen code runs on both platforms. Details see §23.8.9.

#### 23.8.1 Sync Architecture

```
Cleona Calendar (local, encrypted)
  │
  ├── CalDAV Adapter ──► Thunderbird / Nextcloud / any CalDAV server
  │     (iCal export/import, RFC 5545)
  │
  └── Google Calendar Adapter ──► Google Calendar API (OAuth2)
        (REST API, push notifications via FCM)
```

**Privacy considerations:**
- External sync is **opt-in** per identity. Each identity can be linked to a different external calendar or none.
- Only events explicitly marked for sync are exported. Private events (FreeBusyLevel.HIDDEN) are never synced.
- The user chooses the sync direction: Cleona→External (export only), External→Cleona (import only), or bidirectional.
- Imported external events are stored locally but NOT distributed to Cleona contacts. They only affect Free/Busy responses.

#### 23.8.2 CalDAV Sync (Thunderbird, Nextcloud, etc.)

- Standard CalDAV protocol (RFC 4791) with iCal data format (RFC 5545).
- The Cleona daemon acts as a CalDAV client, periodically syncing with the configured CalDAV server.
- RRULE, VTODO, VALARM are mapped 1:1 to Cleona's internal model.
- Conflict resolution: Last-write-wins with conflict notification to the user.

#### 23.8.3 Google Calendar Sync

- OAuth2 authentication via system browser (no embedded WebView).
- Google Calendar API v3 for read/write access.
- **Adaptive polling, not FCM push.** Google Calendar's real-time push delivery (Watch API) requires a publicly-reachable HTTPS webhook, which a fully P2P client has no central authority to provide. FCM itself assumes a backend server that owns the FCM API key and forwards push payloads to devices — again infrastructure Cleona deliberately does not run. Instead, the sync service runs two cadences: a **foreground interval** (default 3 min) while the user has the calendar screen open, and a **background interval** (default 15 min) otherwise. The GUI signals lifecycle transitions via the `calendar_sync_set_foreground` IPC command. Manual "Sync now" is always available. This preserves the decentralized architecture while keeping perceived latency acceptable during active use.
- Shared calendars in Google are synced as read-only imports.

#### 23.8.4 iCal File Import/Export

Even without live sync, the calendar supports one-shot import/export:
- **Import:** `.ics` files (drag & drop or file picker) are parsed and added to the local calendar.
- **Export:** Any view or date range can be exported as `.ics` file for sharing.

#### 23.8.5 Local ICS Bridge (Thunderbird / Outlook / Apple Calendar)

For users who want their Cleona events visible in a desktop calendar app but do not run a CalDAV server, the daemon can continuously publish the calendar to (or pull from) a local `.ics` file. Desktop apps then subscribe to that file via the common "subscribe to internet/local calendar" flow:

- **Thunderbird:** File → New → Calendar → On My Computer → point to the file, or Subscribe to a remote URL via `file://`.
- **Outlook (Windows, 2016+):** Add Calendar → From Internet → `file://` URL (read-only subscription).
- **Apple Calendar:** File → New Calendar Subscription → `file://` URL.
- **GNOME (Evolution):** File → New → Calendar → On The Web, point to the file.

The bridge operates in one of three directions, chosen by the user at setup:
- `export` — daemon writes the file on every local change (atomic rename so readers never see a half-written file). External apps see a read-only mirror of the Cleona calendar.
- `import` — daemon watches mtime on the file and re-imports when it moves. Useful if a legacy calendar program writes the file (uncommon).
- `bidirectional` — combines both. Intended for shared-folder setups where the file lives in a synced directory (e.g. Nextcloud's Files sync) that two different calendar apps may both write.

Delete-detection on import uses a persisted set of previously-seen UIDs: a UID that vanishes from the file *and* whose local `updatedAt` hasn't advanced since the last read is treated as a deletion from the external side.

#### 23.8.6 Conflict Resolution

When the same event has been modified both locally and externally between sync runs, the service applies **last-write-wins** based on `updatedAt`. Every LWW decision is recorded in a bounded (200-entry) conflict log stored in the encrypted sync-state file:

- Each entry captures: provider (`caldav`/`google`/`localIcs`), winning side (`local` or `external`), losing side's JSON snapshot, timestamp, event title.
- The Calendar Sync settings screen exposes the log with a "Restore" action per entry — selecting it overwrites the current local event with the losing snapshot.
- The log is advisory: sync itself never stops, so automatic sync never feels interrupted.

Optionally, each provider can opt into **`askOnConflict` mode**. When enabled, a real conflict pauses the event instead of resolving it — the daemon emits a `calendar_sync_conflict_pending` IPC event with both sides' JSON, the GUI shows a dialog ("Keep local version" vs "Keep external version"), and sync picks up based on the user's choice. Pending conflicts persist across daemon restarts.

Semantic equality (title, description, location, time, recurrence, cancellation) is checked before declaring a conflict, so bookkeeping-only differences (e.g. server re-serialized `updatedAt`) do not flood the log.

#### 23.8.7 Local CalDAV Server

For users who want their Cleona calendar in a desktop calendar app **without running any external server** (Nextcloud / Baikal / Google Workspace), the daemon can host a minimal CalDAV endpoint on `127.0.0.1`. Desktop calendar apps connect directly; the daemon serves their PROPFIND / REPORT / GET / PUT / DELETE requests against the in-memory `CalendarManager`.

The server binds **only to the loopback interface** — the traffic never leaves the kernel. HTTP Basic auth is therefore acceptable without TLS (the credentials only ever travel between local processes on the same machine).

**Setup recipes** (daemon-configured port defaults to `19324`):

- **Thunderbird**: Create Calendar → On The Network → CalDAV → URL `http://127.0.0.1:19324/dav/principals/<short-id>/` (or just `http://127.0.0.1:19324/` and let auto-discovery find the principal) → Username = identity short-id (first 16 hex chars of node-id), Password = daemon token.
- **Apple Calendar.app**: Add Account → Other → Add CalDAV Account → Manual → server `127.0.0.1`, username + password as above.
- **Outlook (2016+)**: Requires the `CalDav Synchronizer` add-in. Same URL / credentials.
- **Evolution / GNOME Calendar**: New Calendar → On The Web → type CalDAV → URL + credentials.

The settings screen shows the base URL, each identity's calendar URL, and the daemon token. The token is regeneratable in one click (instantly swapped at runtime without dropping the server). Enable/disable is a single toggle; the server refuses all requests when disabled or when no token is configured.

**Subset implemented** (sufficient for read-write sync with all tested desktop clients):
- `OPTIONS` advertises `DAV: 1, 2, 3, calendar-access`.
- `PROPFIND` Depth:0 on `/` or `/dav/` → `current-user-principal`.
- `PROPFIND` Depth:0 on principal → `calendar-home-set`.
- `PROPFIND` Depth:1 on calendar-home → list of calendars (one per identity) with `supported-calendar-component-set` and `cs:getctag`.
- `PROPFIND` Depth:0 on a calendar → calendar properties including ctag.
- `PROPFIND` Depth:1 on a calendar → event hrefs + ETags.
- `REPORT calendar-query` → all events with ETags (time-range filter ignored — clients filter locally, same convention as Baikal).
- `REPORT calendar-multiget` → inline iCal bodies for a requested list of hrefs.
- `GET` on an event → iCal body + ETag.
- `PUT` on an event with `If-Match` / `If-None-Match` → create or update, with 412 on preconditions.
- `DELETE` on an event with optional `If-Match` → 204 on success, 404 if already gone, 412 on stale ETag.

**ETag** per event = `"<eventId>-<updatedAt>"` — stable, derived from the calendar's own state, changes on every edit. **Ctag** per calendar = `"<max(updatedAt)>.<event-count>"` — changes on every add/edit/delete. Thunderbird polls the ctag every 5–30 min and re-fetches the ETag list only when the ctag changes, keeping the feedback loop cheap.

**Deliberately not implemented**: WebDAV ACL / owner / permissions (single-user), `sync-collection`/`sync-token` reports (clients fall back to ctag polling with no observable downside), server-side free/busy REPORT (Cleona has its own P2P free/busy protocol; see §23.3).

#### 23.8.8 Android CalendarContract Bridge

On Android, the calendar app of choice (Samsung Calendar, Google Calendar, Divoom Calendar, the launcher's "Today" widget, etc.) reads from the platform's shared `CalendarContract` provider. Cleona mirrors each identity's events into that provider so they appear alongside everything else the user already sees — no duplicate-reminder plumbing, no separate widget, and no need to open Cleona at all just to glance at the day.

The mirror is **push-only** (one-way, Cleona → Android). Edits still happen in the Cleona UI. See §23.8.8.1 below for the full rationale of that decision and the concrete signals that would trigger a reconsideration.

**Implementation (`lib/core/calendar/sync/android_calendar_bridge.dart` + Kotlin `CalendarContractHandler`):**

- One row in `CalendarContract.Calendars` per Cleona identity, with `account_type = ACCOUNT_TYPE_LOCAL` and `owner_account = "Cleona <short-id>"`. `LOCAL` means the events never leave the device — no Google sync is involved.
- Events live in `CalendarContract.Events` with Cleona's `eventId` stashed in `SYNC_DATA1`. Upserts look up the row through that column, so we never have to maintain a parallel ID map.
- RRULE support: CalendarContract requires events with `RRULE` to use `DURATION` with `DTEND = null` (and vice-versa). The bridge enforces this, converting Cleona's start/end/rrule into whichever shape the provider wants.
- Diff-delete: after each full push the bridge lists the calendar's rows and deletes any whose `SYNC_DATA1` no longer matches an active Cleona event. This keeps the Android calendar tidy when the user deletes an event in Cleona.
- Permissions (`READ_CALENDAR` + `WRITE_CALENDAR`) are requested at runtime the first time the user taps "Sync now" in Settings. If the user denies, the bridge falls back to a "permission missing" hint.
- Calendar-provider writes to `SYNC_DATA1` and deletes on `ACCOUNT_TYPE_LOCAL` rows require the request URI to carry `CALLER_IS_SYNCADAPTER=true` + `ACCOUNT_NAME` + `ACCOUNT_TYPE` query parameters. This was discovered in the V3.1.61 → V3.1.62 on-device test and is now set on every event mutation, not just on calendar creation.

**Deliberately not implemented (in addition to the two-way-sync discussion in §23.8.8.1):**
- **Automatic on-event-change push.** The UI exposes a manual "Sync now" trigger. An automatic hook would couple `CalendarManager` directly to the bridge (violating the cross-platform separation, since the bridge only exists on Android) and produce inconsistent behaviour across Desktop/iOS/Android builds. Users who want continuous mirroring can tap once; the full-push diff-delete is idempotent and cheap enough to re-run.

##### 23.8.8.1 Why no two-way sync (decision record)

**The decision:** The bridge writes into `CalendarContract` but does not read back changes the user makes in the Android calendar app. Edits flow Cleona → Android only; changes on the Android side are overwritten by the next sync.

**What two-way sync would actually require:**

1. A Java/Kotlin `AbstractAccountAuthenticator` subclass + `Service` declared in the manifest with `android.accounts.AccountAuthenticator` intent filter and a matching `authenticator.xml` resource.
2. A `SyncAdapter` subclass (another service) declared with `android.content.SyncAdapter` intent filter and a matching `syncadapter.xml`. The adapter handles `onPerformSync(Account, Bundle, String authority, ContentProviderClient, SyncResult)` — a blocking method with no Flutter equivalent, so the actual sync logic would have to duplicate Dart-side logic in Kotlin or marshal it across the MethodChannel with careful lifecycle handling.
3. A real Cleona `Account` registered with the system's `AccountManager`. Each identity would need either its own account row (visible in Settings → Accounts, with the user able to delete it and silently break sync) or a shared "Cleona" account holding all identities (which breaks Android's per-account sync settings).
4. A `ContentObserver` or explicit poll loop on the Dart side to pick up Android-side edits and funnel them back into `CalendarManager`, including conflict detection against the Cleona `SyncConflict` log (§23.8.6).
5. Additional `AUTHENTICATE_ACCOUNTS` + `MANAGE_ACCOUNTS` + `WRITE_SYNC_SETTINGS` permissions in the manifest (some of these are restricted after API 23 and require user-visible grants).

Rough estimate: **~800–1200 lines of Kotlin** + ~200 lines of Dart + three new manifest entries, plus the inevitable bugfix pass after it first ships. Compare this to the ~200 lines of Kotlin + ~200 lines of Dart for the current push-only bridge.

**Why the benefit does not justify the cost:**

- **Cleona is the authoritative source of truth.** A Cleona event can belong to a group (via `CALENDAR_INVITE` in §23.9), carry RSVP state, reference an ongoing call, live under one specific identity in a multi-identity setup, or be a birthday mirror from a contact. The Android calendar app has no concept of any of these — it sees `title`, `dtstart`, `dtend`, `rrule`, `description`, `location`. A user who edits the event on the Android side can only modify that subset; their edit cannot express "change the group this invite targets" or "mark this as tentative for identity Alice only". Propagating an Android-side edit back into Cleona therefore silently drops meaningful state.
- **Trust boundary.** Once `WRITE_CALENDAR` is granted, *any* app with that permission (Samsung Calendar, Google Calendar, arbitrary third-party widgets) can mutate Cleona's events. Two-way sync would turn those apps into effective editors of the user's end-to-end-encrypted P2P calendar. Push-only keeps the trust boundary where it belongs: Cleona is the only writer, the system calendar is a read-only mirror.
- **Conflict resolution gets worse, not better.** §23.8.6 already defines a last-write-wins + opt-in-prompt conflict story for CalDAV and Google Calendar. Adding Android as a third conflict source means every CalendarManager write would have to check against Android's state via a `ContentObserver` — a permanent foreground thread — and the UX of conflict prompts becomes noisier without any clear win over "edit it in Cleona where you have the full picture".
- **Users rarely edit through a mirror.** The use cases driving the bridge request — seeing Cleona events next to work events in Samsung Calendar, Homescreen widget glance-ability, system-level reminders — are all read-only. Nobody has asked for "let me edit my Cleona event from Samsung Calendar".

**Concrete signals that would trigger reconsideration:**

1. Repeated user reports of "I edited a Cleona event in Samsung Calendar and it got overwritten" — this would mean users *are* using the Android side to edit, regardless of what we expected.
2. A concrete use case that requires reading from Android first — for example, importing a pre-existing Android calendar into a new Cleona identity. That would be an *import-once* feature, not full two-way sync, and could be built in ~150 lines without the SyncAdapter machinery.
3. Android introducing a simpler "observed external calendar" API that doesn't need SyncAdapter/AccountAuthenticator. Unlikely in practice.

If any of those land, the implementation plan is: start with (2) one-shot import as a separate IPC command, measure how many users invoke it, then decide whether the remaining ~1000 lines of SyncAdapter code are justified. Until then, the documented scope is firmly "push-only mirror".

#### 23.8.9 Android In-Process Bridge (V3.1.69)

On desktop (Linux/Windows) `CalendarSyncService` is part of the daemon process; the GUI talks to it via `IpcClient` (Unix socket or TCP+auth token). On Android everything runs in a single process (see §18.2 "Android"), so there is no IPC channel — the GUI would have neither an `IpcClient` at hand nor would socket/TCP operations be meaningful purely locally.

`lib/core/calendar/sync/in_process_bridge.dart` (`InProcessCalendarSyncBridge`) solves this by mirroring the `IpcClient` calendar-sync API exactly 1:1 — same method signatures (`calendarSyncStatus`, `calendarSyncCalDavConfigure`, `calendarSyncLocalIcsConfigure`, `calendarSyncTriggerNow`, `calendarSyncSetForeground`, `calendarSyncResolveConflict`, `calendarSyncRestoreConflict`, …), same callback names (`onCalendarSyncStatusUpdate`, `onCalendarSyncConflictPending`, …) — and delegating directly to the active identity's `CleonaService.calendarSyncService`. The `CalendarSyncScreen._ipc` getter is `dynamic`-typed; the same screen code runs unchanged on both platforms.

**What the bridge offers on Android:** CalDAV (user/password + discovery), local-ICS export/import/bidirectional, conflict resolution including the `askOnConflict` pending queue, manual `Trigger now`, adaptive polling with `setForeground()`. Works without a daemon process because `CleonaService` itself runs in-process.

**What is deliberately stubbed** (`bridge.isOnAndroid` hides the UI cards):

- **Google OAuth loopback flow.** Requires a short-lived HTTP server on `127.0.0.1:<random>` that the system browser visits after consent (RFC 8252). On Android foreground apps this is not reliably achievable (activity lifecycle, Doze, permissions). A native Custom-Tabs implementation would be the right solution — non-trivial effort, hence `TODO`.
- **Local CalDAV server (§23.8.7).** Requires a long-lived HTTP listener on `127.0.0.1:19324`. Not guaranteed to run in the background on Android, and the use case ("desktop calendar app syncs against a local server") simply does not exist on Android — the platform-native solution is the `CalendarContract` bridge from §23.8.8.

With that, Android sync no longer has real feature gaps for the main path CalDAV+ICS+conflicts; the only loss is Google Calendar (workaround: the user sets up Google Calendar via the web interface of a third-party CalDAV gateway and gives Cleona its CalDAV URL).

### 23.9 Protocol Messages (Calendar)

New MessageType entries for the calendar:

| MessageType | Direction | Description |
|-------------|-----------|-------------|
| `CALENDAR_INVITE` | Creator → all group members | Event invitation with full details |
| `CALENDAR_RSVP` | Invitee → all group members | Accept/Decline/Tentative/ProposeNewTime |
| `CALENDAR_UPDATE` | Creator → all group members | Event modification (time, title, cancel) |
| `CALENDAR_DELETE` | Creator → all group members | Event deletion |
| `FREE_BUSY_REQUEST` | Planner → individual contact | Request availability for a time window |
| `FREE_BUSY_RESPONSE` | Contact → planner | Filtered availability blocks |

All calendar messages are encrypted via Per-Message KEM (Section 4.3) and delivered via the Three-Layer Cascade (Section 3.3.1). They are persisted locally and erasure-coded for offline delivery.

### 23.10 Storage

Calendar events are stored in the encrypted SQLite database (Section 4.7) in a dedicated `calendar_events` table. Indexes on `startTime`, `identityId`, and `groupId` enable efficient range queries for calendar views.

**Recurring events** are stored as a single row with the RRULE. The UI expands occurrences on the fly. Exceptions (deleted or modified occurrences) are stored in `recurrenceExceptions` or as separate events with a `recurrenceOverrideFor` reference.

**RSVP state** for group events is stored in a separate `calendar_rsvp` table keyed by `(eventId, nodeIdHex)`.

### 23.11 Implementation Status (V3.1.64)

**Core calendar (V3.1.46 baseline):**
- `CalendarManager` with encrypted persistence (`calendar_events.json.enc`), proxy mode for IPC client.
- `RecurrenceEngine` (RFC 5545 RRULE: DAILY/WEEKLY/MONTHLY/YEARLY, BYDAY, BYMONTHDAY, INTERVAL, COUNT, UNTIL).
- Six protocol message handlers (CALENDAR_INVITE/RSVP/UPDATE/DELETE, FREE_BUSY_REQUEST/RESPONSE).
- Service-interface CRUD (`createCalendarEvent`/`updateCalendarEvent`/`deleteCalendarEvent`) — works both in-process (Android) and via IPC (Desktop).
- IpcClient calendar proxy with 4 event handlers (`calendar_invite`, `calendar_rsvp`, `calendar_event_updated`, `calendar_reminder`).
- Event editor (title, 5 categories, date/time, location, recurrence, reminders, group, RSVP, free/busy visibility, task priority).
- Chat-integration card for group events (RSVP buttons, call start, status display).
- iCal import/export (`ical_engine.dart`) — RFC 5545 VCALENDAR/VEVENT/VTODO/VALARM, RRULE, EXDATE, priority mapping, text escaping.
- PDF print for 4 date-based views (A4 portrait for day/year, landscape for week/month, system print dialog via `printing`).

**Completed in V3.1.56:**
- **Views**: 5th view `CalendarView.tasks` — sorted by open/due/priority, checkbox toggle, priority badges, overdue highlighting.
- **Reminders**: daemon fires `onPostNotificationAndroid` + `notificationSound.playMessageSound()` + `vibrate()` when due — reaches user even when GUI is closed or in background.
- **Birthdays (§23.4)**: `ContactInfo.birthdayMonth/Day/Year` fields (local-only, never broadcast), `CleonaService._syncCalendarBirthdays()` runs on identity init and after contact-accept, `contact_set_birthday` IPC + birthday dialog in `contacts_screen.dart`.
- **External sync (§23.8.1–§23.8.4)**: `CalDAVClient` (pure-Dart RFC 4791, Basic over HTTPS, no external deps), `GoogleCalendarClient` (OAuth2 Loopback + PKCE per RFC 8252/7636, incremental `syncToken` deltas with 410-resync fallback), `CalendarSyncService` orchestrator (two-phase pull→push, per-identity opt-in, encrypted config + state).
- **Local ICS bridge (§23.8.5)**: `LocalIcsPublisher` writes/reads `.ics` file for Thunderbird/Outlook/Apple Calendar subscription. Three directions (export/import/bidirectional), atomic writes (tmp+rename), mtime+content-hash dedup, UID-tracked delete detection.
- **Conflict resolution (§23.8.6)**: bounded (200) `SyncConflict` log with losing-event JSON snapshots, Restore action in UI, semantic-equals gating to suppress bookkeeping-only conflicts. Opt-in `askOnConflict` queues `PendingConflict` entries for user decision via `calendar_sync_conflict_pending` IPC event.
- **Adaptive polling** (FCM substitute per §23.8.3): `CalendarSyncService.setForeground(bool)` + `calendar_sync_set_foreground` IPC — 3 min while calendar UI is open, 15 min otherwise. Immediate sync on background→foreground transitions.
- **Settings-UI**: `calendar_sync_screen.dart` with CalDAV form (server discovery), Google OAuth loopback via `url_launcher`, local-ICS file-picker, conflict-log dialog with restore, pending-conflict side-by-side decision dialog. Entry point is the calendar screen's three-dot menu (`calendar_screen.dart` PopupMenuButton, fourth item `sync`, alongside import / export / print) — not the system settings screen; calendar-sync belongs to the calendar surface. Body wrapped in `SafeArea(top: false, ...)` so the Android gesture-bar does not occlude the bottom hint on edge-to-edge devices.
- **IPC**: 16 new commands (listed in §23.8 subsections) + 5 new events — all status JSON redacted (no passwords/tokens).
- **i18n**: 47 new calendar-sync + tasks + birthday keys (de/en/es/fr).

**Tests (V3.1.56 delta):**
- Smoke `smoke_calendar_sync.dart`: **46 tests**, PASS — config JSON round-trip for all three provider types, `SyncConflict`/`PendingConflict` persistence, CalDAV multistatus XML parsing, live `LocalIcsPublisher` export→import→conflict round-trip.
- E2E `gui-50-calendar-sync.spec.ts`: **60 tests** in 10 parts A–J — including 9 extended negative tests (empty path, `/proc` write-fail, missing file on import, malformed JSON, rapid configure/remove, cleanup-on-disk-then-reconfigure, all-provider status-shape coherence).

**Completed in V3.1.60:**
- **Local CalDAV server (§23.8.7)**: `lib/core/calendar/sync/caldav_server.dart` — HTTP server on `127.0.0.1:19324` (configurable) that exposes each identity's calendar as a CalDAV endpoint. Desktop calendar apps (Thunderbird, Outlook 2016+, Apple Calendar, Evolution, GNOME Calendar, KDE Korganizer) sync bidirectionally **without any external server**. Subset of RFC 4791 sufficient for read-write sync: OPTIONS, PROPFIND (current-user-principal / calendar-home-set / calendar-list / calendar props with ctag / event hrefs+ETags), REPORT `calendar-query` + `calendar-multiget`, GET, PUT with `If-Match`/`If-None-Match` → 412, DELETE with `If-Match`. HTTP Basic auth over loopback. Username = first 16 hex chars of node-id; password = daemon-wide token (opt-in, regeneratable). Four IPC commands (`caldav_server_state/set_enabled/regenerate_token/set_port`). UI card in `calendar_sync_screen.dart` with copy-URL + copy-token buttons.

**Completed in V3.1.61:**
- **Android CalendarContract bridge (§23.8.8)**: `android/app/src/main/kotlin/.../CalendarContractHandler.kt` (Kotlin MethodChannel handler) + `lib/core/calendar/sync/android_calendar_bridge.dart` (Dart wrapper). Mirrors Cleona events into the Android system calendar (Samsung Calendar / Google Calendar / any CalendarContract consumer) via `account_type=ACCOUNT_TYPE_LOCAL` so the events never leave the device. Push-only (edits happen in Cleona, Android side is a read-only mirror). `SYNC_DATA1` stores Cleona's eventId so upserts can find rows without a parallel lookup. RRULE-vs-DTEND handling per CalendarContract's exclusive rules. Diff-delete pass removes Android-side rows whose Cleona pendant has vanished. Runtime `READ_CALENDAR` + `WRITE_CALENDAR` permissions (requested in-UI on first sync).

**Completed in V3.1.62:**
- **Android bridge on-device fix:** live-test on `emulator-5554` (Android 15 API 35) surfaced `IllegalArgumentException: Only sync adapters may write to sync_data1` on the first upsert. CalendarContract accepts `SYNC_DATA1` writes and `ACCOUNT_TYPE_LOCAL` deletes only when the request URI carries `CALLER_IS_SYNCADAPTER=true` + `ACCOUNT_NAME` + `ACCOUNT_TYPE` query parameters. `ensureCalendar` already had them; `upsertEvent` and `deleteEvent` now build a `syncAdapterEventsUri` helper and use it for every event mutation. The full lifecycle (ensure → upsert → remove → re-sync) was verified end-to-end on the emulator including `adb shell content query` against the system provider.

**Completed in V3.1.63 (test coverage):**
- **GUI E2E Parts K/L/M for the local CalDAV server:** 23 new tests in `gui-50-calendar-sync.spec.ts` (suite total 60 → 83):
  - Part K (10 tests) drives the `caldav_server_state/set_enabled/regenerate_token/set_port` IPC surface (shape, token hot-swap, port rebind, identity listing, idempotency, rapid toggle survivability).
  - Part L (5 tests) exercises the real wire protocol via `ssh cleona@VM + curl 127.0.0.1:<port>`: OPTIONS capabilities, PROPFIND current-user-principal, PROPFIND calendar-home, 401 on wrong password, connect-refused when disabled.
  - Part M (8 tests) covers the negative paths: missing params, out-of-range ports (below 1024, above 65535), regenerate-while-disabled, re-enable-with-new-token verified end-to-end over the wire, unknown commands, and a 20-call IPC flood survivability test.

**Integration tests:**
- `test/integration/caldav_integration_test.dart` (47 tests, 10 flows, V3.1.59) — wire-level validation of `CalDAVClient` + `CalendarSyncService` against a pure-Dart RFC-4791 fixture server.
- `test/integration/caldav_server_test.dart` (29 tests, 6 flows, V3.1.60) — our own `CalDAVClient` talking to our own `CalDAVServer` end-to-end. Covers auth failure, discovery, REPORT, full CRUD, round-trip (GUI-created events appear to the external client), ctag changes.
- Android bridge verified live on `emulator-5554` (V3.1.62). The adb-based verification pattern documented in the V3.1.62 CHANGELOG entry is also available as `scripts/verify-android-calendar-bridge.sh` (`list` / `events` / `expect-events` / `expect-absent` / `sync-data1` subcommands, CI-optional — requires an attached device with the bridge opt-in active).

**Completed in V3.1.64 (security hardening):**

Post-ship security review of all §23.8 external sync code paths — the only place in the app where Cleona contacts non-P2P infrastructure. Six concrete findings fixed:

- **Constant-time token comparison on the local CalDAV server** (`caldav_server.dart`). Prior `pass != _token` leaked timing information to any local process that could measure response latency, which matters because the token grants access to every identity's calendar.
- **Cross-origin redirect refusal in the CalDAV client** (`caldav_client.dart`). A compromised or impersonated CalDAV server could have returned `302 Location: http://attacker.tld/...`, and the client would have resent the Basic-auth header there. Same-scheme/host/port redirects (e.g. `.well-known` → `/dav/`) remain allowed; any other redirect raises `CalDAVException` without the next hop being contacted.
- **5 MB request-body cap on the local CalDAV server** (`caldav_server.dart:_readBody`). Combined with the DNS-rebinding defense below this closes an OOM vector where a malicious browser page trickles gigabyte PUTs to 127.0.0.1.
- **Symlink refusal + 10 MB size cap in the local ICS bridge** (`local_ics_publisher.dart`). Export refuses to write through a symlink (would otherwise let a co-tenant swap the `.ics` path for `~/.ssh/authorized_keys`); import checks `stat.size` before `readAsString` (shared-folder OOM).
- **`http://`-in-the-clear warning in the CalDAV configure dialog** (`calendar_sync_screen.dart` + i18n for de/en/es/fr). Shown live as the user types, unless the host is `127.0.0.1` / `localhost` / `::1` where loopback http is legitimate.
- **Host-header check on the local CalDAV server** (DNS-rebinding defense-in-depth, `caldav_server.dart:_dispatch`). Only `127.0.0.1`, `localhost`, `::1` (with or without port, IPv6-brackets handled) are accepted; anything else answers `421 Misdirected Request`.

Explicitly **cleared** during the same review (no changes needed): RRULE expansion already capped at 1000 occurrences + 10 years (`recurrence_engine.dart`); Google OAuth state is 192 random bits + single-shot callback server (brute-forcing infeasible); PKCE is correct S256 with `Random.secure()`; no `badCertificateCallback` overrides anywhere; no credential strings in log statements; Android bridge correctly uses `ACCOUNT_TYPE_LOCAL`; CalDAV server path parsing already reduces to an opaque eventId lookup, not a filesystem path.

Out of scope: XML-parser hardening (code uses regex extraction, not `XmlDocument` — documented so a future refactor reinstates DTD/external-entity disabling); full WAF on loopback (a local attacker with filesystem access already has the token).

**Deliberately not implemented:**
- **FCM-style real-time push** — architecturally declined per §23.8.3 (a fully P2P client has no central HTTPS webhook for Google Calendar Watch API and no backend for FCM). Adaptive polling is the documented substitute.
- **Two-way Android sync (SyncAdapter + Account Authenticator)** — full rationale + reconsideration triggers in §23.8.8.1. Summary: ~800–1200 lines of Kotlin for a feature that would silently drop group/RSVP/identity metadata on every Android-side edit, widen the trust boundary to every app with `WRITE_CALENDAR`, and complicate the conflict story from §23.8.6. The push-only bridge covers every user-visible use case (system-calendar visibility, homescreen widget, system reminders); one-shot Android → Cleona import could be added later in ~150 lines without the SyncAdapter machinery.

**Completed in V3.1.69 (Android in-process sync + scoping clarification):**

- **Android in-process bridge (§23.8.9):** `lib/core/calendar/sync/in_process_bridge.dart` (`InProcessCalendarSyncBridge`) mirrors the `IpcClient` calendar-sync API 1:1 and delegates directly to `CleonaService.calendarSyncService`. Lifts the previous "Sync UI requires the IPC client" lockout on Android. `CalendarSyncScreen._ipc` is now `dynamic`-typed (duck dispatch), screen code unchanged across both platforms. CalDAV + local-ICS + conflict resolution + adaptive polling all work. Stubs (hidden in the UI via `bridge.isOnAndroid`): Google OAuth loopback (activity lifecycle not reliable) and the local CalDAV server (long-running listener + wrong use case on Android — the platform-native solution is the bridge from §23.8.8).
- **Identity scoping & roles consolidated (§23.4.1):** Existing behaviour (CalendarManager + CalendarSyncService per identity, Event.identityId binding, creator-vs-invited roles, per-event visibility + per-contact override) explicitly documented in a clarification section.

---

## 24. Polls & Voting

Cleona supports decentralized polls in groups and channels, enabling collaborative decision-making without any central server. Poll votes are distributed via the existing message infrastructure and aggregated locally by each participant.

> **Status:** Implemented in V3.1.66. Source: `lib/core/polls/poll_manager.dart`, handlers in `lib/core/service/cleona_service.dart`, crypto in `lib/core/crypto/linkable_ring_signature.dart` + `lib/core/crypto/sodium_ffi.dart`, UI in `lib/ui/screens/poll_editor_screen.dart` + `lib/ui/components/poll_card.dart`. Proto message types `POLL_CREATE=146`, `POLL_VOTE=147`, `POLL_UPDATE=148`, `POLL_SNAPSHOT=149`, `POLL_VOTE_ANONYMOUS=150`, `POLL_VOTE_REVOKE=151`.

### 24.1 Design Principles

1. **Fully decentralized:** No central vote counter. Each node aggregates votes from received messages and arrives at the same result through message convergence.
2. **Tamper-resistant:** Every vote is signed by the voter's Ed25519 key. Votes cannot be forged or modified in transit.
3. **Integrated:** Polls appear as interactive cards in the chat. Date polls can create calendar events (Section 23). Poll results can trigger group call scheduling.
4. **Privacy-flexible:** Polls can be open (everyone sees who voted what) or anonymous (only totals visible).

### 24.2 Data Model

#### 24.2.1 Poll Creation

```
PollCreate {
  pollId:         UUID
  question:       string (the poll question or title)
  description:    string (optional, additional context)
  pollType:       PollType
  options:        List<PollOption>
  settings:       PollSettings
  groupId:        bytes (group or channel this poll belongs to)
  createdBy:      bytes (creator's node ID)
  createdByName:  string (creator's display name)
  createdAt:      int64 (Unix ms)
}

enum PollType {
  SINGLE_CHOICE = 0;    // Exactly one option selectable
  MULTIPLE_CHOICE = 1;  // Multiple options selectable
  DATE_POLL = 2;        // Doodle-style: Yes/No/Maybe per time slot
  SCALE = 3;            // Rating scale (1–5 or 1–10)
  FREE_TEXT = 4;        // Open-ended text responses
}

message PollOption {
  int32 optionId = 1;           // Sequential ID (0, 1, 2, ...)
  string label = 2;             // Option text (e.g. "Option A" or "Monday 14:00")
  int64 dateStart = 3;          // Only for DATE_POLL: slot start time (Unix ms)
  int64 dateEnd = 4;            // Only for DATE_POLL: slot end time (Unix ms)
}

message PollSettings {
  bool anonymous = 1;           // If true, UI shows only totals, not who voted what
  int64 deadline = 2;           // Auto-close time (Unix ms), 0 = no deadline
  bool allowVoteChange = 3;     // Can voters change their vote? (default: true)
  bool showResultsBeforeClose = 4; // Show live results or only after close? (default: true)
  int32 maxChoices = 5;         // For MULTIPLE_CHOICE: max selectable options (0 = unlimited)
  int32 scaleMin = 6;           // For SCALE: minimum value (default: 1)
  int32 scaleMax = 7;           // For SCALE: maximum value (default: 5)
  bool onlyMembersCanVote = 8;  // For channels: only members, not subscribers (default: false)
}
```

#### 24.2.2 Poll Vote

```
PollVote {
  pollId:         UUID
  voterId:        bytes (voter's node ID)
  voterName:      string (voter's display name)
  selectedOptions: List<int32> (option IDs for SINGLE/MULTIPLE_CHOICE)
  dateResponses:  List<DateResponse> (for DATE_POLL: one per option)
  scaleValue:     int32 (for SCALE)
  freeText:       string (for FREE_TEXT)
  votedAt:        int64 (Unix ms)
}

message DateResponse {
  int32 optionId = 1;
  DateAvailability availability = 2;
}

enum DateAvailability {
  YES = 0;
  NO = 1;
  MAYBE = 2;
}
```

#### 24.2.3 Poll Update

```
PollUpdate {
  pollId:         UUID
  action:         PollAction
  updatedBy:      bytes (must be creator or group admin)
  addedOptions:   List<PollOption> (for ADD_OPTIONS)
  removedOptions: List<int32> (option IDs for REMOVE_OPTIONS)
  newDeadline:    int64 (for EXTEND_DEADLINE)
}

enum PollAction {
  CLOSE = 0;            // Manually close the poll
  REOPEN = 1;           // Reopen a closed poll
  ADD_OPTIONS = 2;      // Add new options
  REMOVE_OPTIONS = 3;   // Remove options
  EXTEND_DEADLINE = 4;  // Push the deadline
  DELETE = 5;           // Delete the poll entirely
}
```

### 24.3 Vote Distribution & Aggregation

#### 24.3.1 In Groups (Pairwise Fanout)

Votes are distributed identically to regular group messages:

1. Voter creates a `PollVote` message.
2. The message is encrypted individually to each group member via Per-Message KEM (Section 4.5).
3. Each group member receives the vote, verifies the Ed25519 signature, and updates their local vote tally.
4. Since all members receive all votes via Fanout, every node converges to the same result.

**Duplicate detection:** Each identity can have at most one active vote per poll. The key is `(pollId, voterId)`. If `allowVoteChange` is true, a newer vote (by `votedAt` timestamp) replaces the previous one. If false, the first valid vote is permanent.

**Late joiners:** When a new member joins a group, they receive the poll state through the group's restore mechanism. The poll creator can optionally re-broadcast the current tally as a `POLL_SNAPSHOT` for immediate catch-up.

#### 24.3.2 In Channels (Broadcast)

For public channels with potentially hundreds of subscribers:

1. The poll creator sends `POLL_CREATE` via channel broadcast.
2. Subscribers send `POLL_VOTE` back to the creator (not broadcast — avoids N^2 message fan-out).
3. The creator periodically broadcasts `POLL_SNAPSHOT` with aggregated totals.
4. On poll close, the creator broadcasts the final `POLL_SNAPSHOT` with complete results.

This reduces message volume from O(N^2) to O(N) for large channels.

```
PollSnapshot {
  pollId:         UUID
  totalVotes:     int32
  optionCounts:   List<OptionCount>  // (optionId, count) pairs
  closed:         bool
  snapshotAt:     int64
}
```

### 24.4 Anonymous Voting (Linkable Ring Signatures)

When `anonymous == true`, votes are cryptographically anonymous using **Linkable Ring Signatures**. No participant — not even the poll creator — can determine who voted what, while double-voting is still detected and prevented.

#### 24.4.1 Concept

The core problem: prove you are a legitimate group member and haven't voted before, without revealing which member you are. Linkable Ring Signatures solve this with two properties:

1. **Ring Signature:** The voter signs their vote using all N group members' public keys as the "ring". The signature proves "one of these N people signed this" without revealing which one.
2. **Key Image (Linkability Tag):** A deterministic value derived from the voter's private key and the poll ID. The same voter always produces the same key image for the same poll, but the key image cannot be traced back to any specific public key. If the same key image appears on two votes, the second is rejected as a duplicate.

#### 24.4.2 Cryptographic Protocol

```
Given:
  - Group members' public keys: P_1, P_2, ..., P_N (Ed25519)
  - Voter's keypair: (sk, P_j) where j is the voter's index
  - pollId: unique poll identifier

Step 1 — Key Image:
  I = sk * H_p(pollId || P_j)
  where H_p is a hash-to-point function on the Ed25519 curve.
  I is deterministic for (sk, pollId) but computationally
  unlinkable to P_j without knowing sk.

Step 2 — Ring Signature:
  The voter constructs a Schnorr ring over all N public keys:

  For each i ≠ j (non-signer members):
    Choose random c_i, r_i
    Compute L_i = r_i * G + c_i * P_i
    Compute R_i = r_i * H_p(pollId || P_i) + c_i * I

  For i = j (the actual signer):
    Choose random α
    Compute L_j = α * G
    Compute R_j = α * H_p(pollId || P_j)
    Compute c = H(pollId || vote || I || L_1 || R_1 || ... || L_N || R_N)
    c_j = c - Σ(c_i for i ≠ j)  (mod q)
    r_j = α - c_j * sk  (mod q)

  Signature = (I, c_1, r_1, c_2, r_2, ..., c_N, r_N)

Step 3 — Verification (by any participant):
  For each i = 1..N:
    Compute L_i = r_i * G + c_i * P_i
    Compute R_i = r_i * H_p(pollId || P_i) + c_i * I
  Check: H(pollId || vote || I || L_1 || R_1 || ... || L_N || R_N) == Σ(c_i)

Step 4 — Duplicate detection:
  If key image I was already seen for this pollId → reject vote.
```

#### 24.4.3 Vote Message Format (Anonymous)

```
PollVoteAnonymous {
  pollId:       UUID
  choice:       bytes (encrypted: selectedOptions / dateResponses / scaleValue)
  keyImage:     bytes (32 bytes, the linkability tag)
  ringSignature: bytes (N * 64 bytes: c_i || r_i pairs)
  ringMembers:  List<bytes> (the N public keys used, for verification order)
}
```

Note: The vote contains **no voter ID and no voter name**. The ring signature proves group membership. The key image prevents double-voting.

#### 24.4.4 Implementation

- **Curve operations:** Ed25519 scalar multiplication and point addition via libsodium (`crypto_scalarmult_ed25519`, `crypto_core_ed25519_add`). These primitives are already available in Cleona's `sodium_ffi.dart`.
- **Hash-to-point:** `crypto_core_ed25519_from_uniform()` (libsodium) maps a 64-byte hash to a valid Ed25519 point.
- **Signature size:** Proportional to group size N. For a 20-member group: 32 bytes key image + 20 × 64 bytes = ~1.3 KB. Acceptable for poll votes.
- **Verification cost:** N point multiplications per vote verification. For N=50, this takes <10ms on modern hardware. Negligible.
- **Anonymity set:** The anonymity is only as strong as the group size. A 5-person group provides limited anonymity; a 50-person channel provides strong anonymity. The UI shows a hint: "Anonymity set: N members".

#### 24.4.5 Vote Change with Anonymity

When `allowVoteChange == true` and the poll is anonymous, the voter cannot simply send a new vote — the key image would be flagged as a duplicate. Instead:

1. The voter sends a `PollVoteRevoke` with their key image and a proof of key image ownership (a signature over "revoke" using the same ring).
2. All participants remove the old vote for that key image.
3. The voter submits a new `PollVoteAnonymous` — same key image (deterministic), new choice.

This allows changing votes while maintaining anonymity.

#### 24.4.6 Limitations

- **Group size = anonymity set:** In a 3-person group, anonymous voting provides minimal privacy. The UI warns when the group has fewer than 7 members.
- **Timing analysis:** If votes arrive in rapid succession, the order of arrival could hint at identity (network proximity). Mitigation: votes are delayed by a random 0–30 second jitter before broadcast.
- **Collusion:** If N-1 members collude, they can deduce the last member's vote by elimination. This is inherent to any anonymous voting system with a known voter set.

### 24.5 Calendar Integration (Date Polls)

Date polls (`PollType.DATE_POLL`) bridge polls and calendar:

1. **Creation:** The poll creator selects time slots from the calendar view. Each slot becomes a `PollOption` with `dateStart` and `dateEnd`.
2. **Free/Busy overlay:** When viewing a date poll, the voter can optionally request Free/Busy data from all invitees (Section 23.3) to see which slots conflict with existing appointments.
3. **Result → Event:** When the poll closes, the winning time slot can be converted to a `CalendarEvent` with one click. A `CALENDAR_INVITE` is sent to all participants automatically.
4. **Group Call:** If the winning event has `hasCall: true`, a group call is automatically scheduled.

### 24.6 Chat Display

Polls appear as interactive cards in the group/channel chat:

**Single/Multiple Choice:**
```
+----------------------------------------------+
| [Poll] Where shall we meet?                  |
|                                              |
| =========----- Cafe Mueller           (7)    |
| ====---------- Beer garden            (3)    |
| ==------------ Online                 (2)    |
|                                              |
| 12 votes, ends in 2 days                     |
| [Vote]                           [Results]   |
+----------------------------------------------+
```

**Date Poll (Doodle-Style):**
```
+----------------------------------------------+
| [Poll] Next team meeting                     |
|                                              |
|              Mon 14   Tue 15   Wed 16        |
|              10:00    14:00    09:00         |
| Alice        [ok]     [ok]     [?]           |
| Bob          [x]      [ok]     [ok]          |
| Charlie      [ok]     [?]      [ok]          |
|                                              |
| [Vote]                        [-> Event]     |
+----------------------------------------------+
```

**Scale:**
```
+----------------------------------------------+
| [Poll] How was the meeting?                  |
|                                              |
| 1 --  2 --  3 ==  4 ====  5 ==               |
| Average: 3.8 (12 votes)                      |
|                                              |
| [Rate]                                       |
+----------------------------------------------+
```

### 24.7 Permissions

| Action | Groups | Channels |
|--------|--------|----------|
| Create poll | Owner, Admin, Member | Owner, Admin |
| Vote | All members | Members + Subscribers (configurable) |
| Close poll | Creator, Owner, Admin | Creator, Owner, Admin |
| Delete poll | Creator, Owner, Admin | Creator, Owner, Admin |
| View results | All members (if showResultsBeforeClose) | All subscribers (if showResultsBeforeClose) |

### 24.8 Protocol Messages (Polls)

| MessageType | Direction | Description |
|-------------|-----------|-------------|
| `POLL_CREATE` | Creator → all members | New poll with question, options, settings |
| `POLL_VOTE` | Voter → all members (groups) or → creator (channels) | Individual vote |
| `POLL_UPDATE` | Creator/Admin → all members | Close, reopen, add/remove options, extend deadline |
| `POLL_SNAPSHOT` | Creator → all subscribers (channels only) | Aggregated results broadcast |

All poll messages are encrypted via Per-Message KEM and delivered via Three-Layer Cascade.

### 24.9 Storage

Polls are stored in the encrypted SQLite database:
- `polls` table: poll definition (question, options, settings, creator, deadline, closed status)
- `poll_votes` table: individual votes, keyed by `(pollId, voterId)`, with timestamp for change detection

Closed polls are retained for 90 days, then auto-deleted (configurable per group in chat settings, Section 15.6.2).

---

## 25. In-Call Collaboration

Group calls (Section 4.4.2) can be enhanced with real-time collaboration features: shared whiteboard, file/clipboard exchange, and screen sharing. All collaboration data is encrypted with the active call key (Section 4.4.1) and distributed via the Overlay Multicast Tree (Section 4.4.3).

### 25.1 Design Principles

1. **Call-scoped:** All collaboration features are available only during an active call. When the call ends, shared content is discarded unless explicitly saved.
2. **Same encryption:** Collaboration data uses the same AES-256-GCM call key as audio/video streams. No separate key negotiation.
3. **Bandwidth-aware:** Collaboration data is lower priority than audio. If bandwidth is constrained, whiteboard updates and screen sharing quality are reduced before audio quality drops.
4. **No server:** All data flows P2P via the existing Overlay Multicast Tree. Screen sharing frames and whiteboard strokes are distributed the same way as video frames.

### 25.2 Shared Whiteboard

A collaborative canvas where all call participants can draw, write, and annotate simultaneously.

#### 25.2.1 Architecture

```
┌─────────────────────────────────────────┐
│                Whiteboard               │
│                                         │
│  Local Canvas (Flutter CustomPainter)   │
│         │                     ▲         │
│         ▼                     │         │
│  StrokeBuffer ──► Serialize ──► Encrypt │
│         │         (Protobuf)   (CallKey)│
│         ▼                     │         │
│  Overlay Multicast ◄──────────┘         │
│  (same tree as video)                   │
│         │                               │
│         ▼                               │
│  Remote participants receive,           │
│  decrypt, deserialize, render           │
└─────────────────────────────────────────┘
```

#### 25.2.2 Data Model

```
WhiteboardStroke {
  strokeId:     UUID
  authorId:     bytes (drawer's node ID)
  authorName:   string
  tool:         WhiteboardTool (PEN | HIGHLIGHTER | ERASER | TEXT | SHAPE | ARROW | LASER)
  color:        int32 (ARGB)
  strokeWidth:  float
  points:       List<Point2D> (x, y coordinates, normalized 0.0–1.0)
  pressure:     List<float> (optional, for pressure-sensitive input)
  text:         string (only for TEXT tool)
  shapeType:    ShapeType (only for SHAPE: RECTANGLE | CIRCLE | TRIANGLE | LINE)
  timestamp:    int64
}

message Point2D {
  float x = 1;
  float y = 2;
}

WhiteboardAction {
  actionType:   ActionType (CLEAR_ALL | UNDO | REDO | ADD_PAGE | SWITCH_PAGE)
  pageIndex:    int32 (for multi-page whiteboards)
  targetStrokeId: UUID (for UNDO of a specific stroke)
  authorId:     bytes
}
```

#### 25.2.3 Synchronization

- **Real-time streaming:** Strokes are streamed point-by-point as the user draws. A `StrokeBegin` message starts the stroke, `StrokePoints` messages add points in batches (every 50ms), and `StrokeEnd` finalizes it. This gives remote participants a smooth live drawing experience.
- **Late join:** When a participant joins an ongoing call with whiteboard content, any active participant sends a full `WhiteboardSnapshot` (all strokes, all pages) encrypted to the joiner's public key.
- **Conflict resolution:** Strokes from different users never conflict — they simply overlay. For UNDO/REDO, each user can only undo their own strokes. CLEAR_ALL requires Owner/Admin permission.
- **Multi-page:** The whiteboard supports multiple pages (like a flipchart). Any participant can add a page. Page navigation is synchronized — when the presenter switches pages, all participants follow (with an option to browse independently).

#### 25.2.4 Features

| Feature | Description |
|---------|-------------|
| Pen | Freehand drawing with configurable color and width |
| Highlighter | Semi-transparent strokes for emphasis |
| Eraser | Remove individual strokes by touching them |
| Text | Place text labels with configurable font size |
| Shapes | Rectangle, circle, line, arrow — drawn by dragging |
| Laser pointer | Temporary highlight (disappears after 2 seconds), visible to all participants |
| Color picker | Palette with preset colors + custom color selector |
| Sticky notes | Colored rectangles with text, movable and resizable |
| Image insert | Paste an image from clipboard onto the canvas |
| Export | Save the current whiteboard page(s) as PNG or PDF |

### 25.3 File & Clipboard Exchange

During a call, participants can share files and clipboard content directly with all call members.

#### 25.3.1 Architecture

File sharing during calls uses the existing media transfer infrastructure (Section 3.4) but scoped to the call session:

```
CallFileShare {
  fileId:       UUID
  fileName:     string
  fileSize:     int64
  mimeType:     string
  thumbnailData: bytes (optional, for images/videos, max 16 KB)
  sharedBy:     bytes (sharer's node ID)
  sharedByName: string
}
```

**Flow:**
1. User clicks "Share File" in the call UI or pastes from clipboard.
2. A `CallFileShare` announcement is sent to all call participants (via Overlay Multicast).
3. Each participant sees the file in a "Shared Files" panel.
4. Clicking "Download" triggers a direct P2P transfer (Two-Stage Media, Section 3.4) encrypted with the call key.

**Clipboard sharing:** The "Paste to Call" button sends the current clipboard content (text, image, or file) to all participants. Text appears inline in the call chat. Images are displayed as thumbnails.

#### 25.3.2 Call Chat

A lightweight text chat within the call, separate from the group's persistent chat:

```
CallChatMessage {
  messageId:    UUID
  senderId:     bytes
  senderName:   string
  text:         string
  timestamp:    int64
  replyToId:    UUID (optional)
}
```

Messages are delivered via the Overlay Multicast Tree and encrypted with the call key. Call chat is ephemeral — it is not persisted after the call ends (unless a participant explicitly saves the transcript).

### 25.4 Screen Sharing

A participant can share their screen (or a specific window) with all call members.

#### 25.4.1 Architecture

```
Screen Capture (platform-specific)
  │
  ▼
Frame Encoder (VP8, same as video)
  │
  ▼
Encrypt (AES-256-GCM, call key)
  │
  ▼
Overlay Multicast Tree (same as video stream)
  │
  ▼
Remote participants: Decrypt → Decode → Display
```

Screen sharing reuses the entire video pipeline (Section 4.4, VP8 encoding, Overlay Multicast Tree) but captures from the screen instead of the camera. It is treated as a second video stream alongside the camera feed.

#### 25.4.2 Capture Sources

| Platform | Capture Method | Window Selection |
|----------|---------------|-----------------|
| Linux | PipeWire / XDG Desktop Portal (`org.freedesktop.portal.ScreenCast`) | Portal picker dialog |
| Windows | Windows.Graphics.Capture API | System picker dialog |
| Android | MediaProjection API | System permission dialog |
| iOS | ReplayKit (RPSystemBroadcastPickerView) | System picker |

**Privacy:** All platforms show a system-level indicator when screen sharing is active (overlay icon, status bar indicator). The sharing participant sees a colored border around the shared region.

#### 25.4.3 Adaptive Quality

Screen sharing adapts to available bandwidth:

| Bandwidth | Resolution | FPS | Quality |
|-----------|-----------|-----|---------|
| > 2 Mbps | Native (up to 1920x1080) | 15 | High (sharp text) |
| 1–2 Mbps | 1280x720 | 10 | Medium |
| 500 Kbps–1 Mbps | 960x540 | 5 | Low |
| < 500 Kbps | 640x360 | 3 | Minimal |

**Text optimization:** Screen content is mostly static text and UI elements. The encoder uses a higher quality setting for static regions and lower quality for moving content (video playback on the shared screen). A "optimize for text" toggle prioritizes sharpness over framerate (2 FPS but very crisp).

#### 25.4.4 Remote Control (Optional, Phase 2)

A future extension allows the presenter to grant remote control of their screen to another participant:

- Presenter explicitly grants control via a button ("Allow [Name] to control")
- The controller's mouse/keyboard events are serialized and sent to the presenter's machine
- Only one controller at a time
- Presenter can revoke control instantly
- Not available on mobile platforms (Android/iOS)

### 25.5 Collaboration UI Layout

During a group call, the collaboration features are accessible via a toolbar:

```
+---------------------------------------------------------------+
| Call: Team Standup (4 participants)                  [Hang up]|
+---------------------------------------------------------------+
|                                                               |
| +--- Video Grid -----------+ +--- Side Panel ---------------+ |
| | Alice         Bob        | | [Whiteboard]                  ||
| |                          | | [Shared Files]                ||
| | Charlie       Detlef     | | [Chat]                        ||
| +--------------------------+ | [Participants]                ||
|                              |                               ||
|                              | (expandable panel)            ||
|                              +-------------------------------+|
+---------------------------------------------------------------+
| [Mute] [Camera] [Screen] [Whiteboard] [Share] [Paste] [Chat]  |
+---------------------------------------------------------------+
```

**Whiteboard mode:** When activated, the whiteboard replaces the video grid as the main content area. Video thumbnails move to a small strip at the top. The drawing toolbar appears on the left.

**Screen share mode:** The shared screen becomes the main content area. The sharer's video thumbnail shows a small "sharing" indicator. Other participants' videos stay in the strip.

### 25.6 Encryption & Security

All collaboration data (whiteboard strokes, shared files, screen frames, call chat) is encrypted with the same call key used for audio/video (Section 4.4.1):

- **Group call key rotation** applies to collaboration data too. When a participant is kicked, the new call key is distributed and all subsequent collaboration data uses the new key.
- **Screen sharing leakage risk:** The app shows a warning before screen sharing starts: "Participants will see your screen. Make sure no sensitive information is visible." On desktop, the app offers to hide its own notification area during sharing.
- **File sharing limits:** Maximum file size during a call is 50 MB (larger files should be shared via the regular chat). Maximum concurrent shared files: 20.

### 25.7 Protocol Messages (Collaboration)

| MessageType | Description |
|-------------|-------------|
| `WHITEBOARD_STROKE` | Real-time stroke data (begin, points, end) |
| `WHITEBOARD_ACTION` | Clear, undo, redo, page navigation |
| `WHITEBOARD_SNAPSHOT` | Full state for late joiners |
| `CALL_FILE_SHARE` | File announcement (metadata + optional thumbnail) |
| `CALL_FILE_REQUEST` | Request to download a shared file |
| `CALL_CHAT_MESSAGE` | Ephemeral in-call text message |
| `SCREEN_SHARE_START` | Announce screen sharing started (with resolution info) |
| `SCREEN_SHARE_STOP` | Announce screen sharing stopped |

All messages are encrypted with the call key and distributed via the Overlay Multicast Tree.

---

## 26. Multi-Device Support

A single identity can run on multiple devices simultaneously — for example, a phone and a PC. All devices share the same cryptographic keys (derived from the same seed phrase via Section 5.2) and present as the same identity to the network. The existing multi-address infrastructure (Section 3.2), Store-and-Forward (Section 3.3.2), and Erasure Coding (Section 3.3.3) carry the bulk of the synchronization load. The only new protocol element is a lightweight Twin-Sync mechanism for local actions that have no network-facing counterpart.

### 26.1 Design Principles

1. **Same keys, same identity:** All devices derive the same Ed25519 + ML-KEM-768 keypair from the master seed. No device-specific sub-keys. Each device computes the same User-ID (`SHA-256(network_secret + pubkey)`) and the same Mailbox-ID (`SHA-256("mailbox" + pubkey)`). Additionally, each device computes a unique **Device-Node-ID** (`SHA-256(network_secret + pubkey + deviceId)`) used for routing-level identification — the routing table is keyed by deviceNodeId, while message encryption and contact identity use the stable userId (V3.1.44 Phase 2-4).
2. **Minimal new protocol:** Multi-device adds exactly one new concept: TWIN_SYNC messages for local actions. Everything else — message delivery, encryption, routing, offline retrieval — uses existing mechanisms unchanged.
3. **Eventual consistency:** Devices are not guaranteed to be in lockstep. A message read on the phone may take up to 60 seconds to appear as read on the PC. This is acceptable for a messenger — users expect slight delays between devices.
4. **Recovery as bootstrap:** Setting up a second device uses the existing Restore Broadcast mechanism (Section 6.3). No separate "multi-device setup" flow is needed.

### 26.2 Device Registration & Pairing

#### 26.2.1 Initial Setup

A user sets up Cleona on a second device by entering their 24-word seed phrase (Section 6.1). The device derives the same keys, joins the network with the same Node-ID, and performs a standard Restore Broadcast. Contacts respond with chat history and contact data — the second device receives the full state, identical to a recovery scenario.

After restore completes, the new device registers itself in the local device list by sending a `TWIN_ANNOUNCE` message to all addresses already known for its own Node-ID (discovered via DHT FIND_NODE for its own ID).

#### 26.2.2 Device Identity

Each device is identified by:

```
DeviceRecord {
  deviceId:       UUID (generated once on first launch, stored locally)
  deviceName:     string (OS hostname by default, user-editable)
  platform:       DevicePlatform (ANDROID | IOS | LINUX | WINDOWS | MACOS)
  firstSeen:      int64 (Unix milliseconds)
  lastSeen:       int64 (Unix milliseconds, updated on each TWIN_SYNC)
  addresses:      List<PeerAddress> (current network addresses of this device)
  deviceNodeId:   bytes (V3.1.44: routing-level ID, for DEVICE_REVOKED + routing table)
}
```

The device list is maintained locally on each device and synchronized via TWIN_SYNC. It is never stored in the DHT — only the devices themselves know about each other.

#### 26.2.3 Twin Discovery

After joining the network, a device discovers its twins through two mechanisms:

1. **DHT self-lookup:** A FIND_NODE query for its own Node-ID returns peers that know addresses for this identity. The address list may contain entries from other devices (different IP:port, same Node-ID). The device sends a TWIN_ANNOUNCE to those addresses.
2. **Mailbox check:** TWIN_ANNOUNCE messages from other devices may be waiting in the shared mailbox (S&F or Erasure fragments), deposited while this device was offline.

### 26.3 Twin-Sync Protocol

#### 26.3.1 What Gets Synced

Only **local manual actions** that have no network-facing counterpart require explicit synchronization:

| Action | Sync Payload | Priority |
|--------|-------------|----------|
| Contact added (QR/NFC/URI) | Full contact record (pubkey, name, addresses) | **Critical** — must arrive before messages from this contact |
| Contact deleted | Contact pubkey | Normal |
| Message sent | Full message content (plaintext, pre-encryption) | Normal |
| Message edited locally | Message ID + new content | Normal |
| Message deleted locally | Message ID | Normal |
| Read receipt generated | Conversation ID + read-up-to timestamp | Low |
| Group created locally | Full group record | Normal |
| Profile changed | Updated fields (name, avatar, age verification) | Normal |
| Settings changed | Changed key-value pairs | Low |
| Device renamed | Device ID + new name | Low |

#### 26.3.2 What Does NOT Need Sync

These arrive naturally at all devices via the existing network infrastructure:

- **Incoming messages:** Sender delivers to all known addresses for the Node-ID. Missed deliveries are retrieved from S&F/Erasure via the shared Mailbox-ID.
- **Incoming contact requests:** Delivered to the Node-ID like any message.
- **Contact request acceptance:** The accepting contact sends a response to the identity's Node-ID — all devices receive it.
- **Incoming read receipts, typing indicators:** Delivered to the Node-ID.
- **Group invitations from others:** Delivered to the Node-ID.
- **DHT/routing updates:** Each device maintains its own routing table independently.

#### 26.3.3 Sync Message Format

```
TwinSyncEnvelope {
  syncId:         UUID (for deduplication)
  deviceId:       UUID (originating device)
  timestamp:      int64 (Unix milliseconds)
  syncType:       TwinSyncType (CONTACT_ADDED | CONTACT_DELETED | MESSAGE_SENT |
                                MESSAGE_EDITED | MESSAGE_DELETED | READ_RECEIPT |
                                GROUP_CREATED | PROFILE_CHANGED | SETTINGS_CHANGED |
                                DEVICE_ANNOUNCE | DEVICE_RENAMED | DEVICE_REVOKED)
  payload:        bytes (type-specific protobuf)
}
```

Twin-Sync messages are encrypted with the identity's own public key (Per-Message KEM, same as regular messages) and delivered via the standard Three-Layer Delivery (Section 3.3.1). They use the same RUDP Light acknowledgment (DELIVERY_RECEIPT) and S&F/Erasure fallback as regular messages — no special delivery mechanism needed.

#### 26.3.4 KEX Gate Integration

**Problem:** If Device A adds a new contact and Device B has not yet received the TWIN_SYNC, messages from that contact are dropped by Device B's KEX Gate (Section 8.3).

**Solution:** When processing messages from the shared mailbox, TWIN_SYNC messages are **always processed first**, regardless of timestamp ordering. This ensures that contact additions are applied before any messages from those contacts are evaluated. Processing order:

```
1. TWIN_SYNC (CONTACT_ADDED)    ← ensures KEX Gate whitelist is current
2. TWIN_SYNC (all other types)  ← ensures local state is current
3. Regular messages              ← now processed with full context
```

For direct delivery (not from mailbox), a race condition remains possible but self-healing: the dropped message will be retrieved from S&F/Erasure on the next poll, by which time the TWIN_SYNC will have arrived.

#### 26.3.5 Deduplication

Each TWIN_SYNC carries a UUID (`syncId`). Devices track received syncIds in a rolling window (7 days, matching S&F TTL). Duplicate syncs — which are expected when both direct delivery and S&F succeed — are silently discarded.

### 26.4 Delivery to Multiple Devices

The existing delivery infrastructure handles multi-device with minimal additions:

1. **Sender perspective:** A contact sending a message to this identity has multiple entries in their routing table — one per device, keyed by `deviceNodeId`. For regular messages, `sendEnvelope()` sends to the best device (first `getPeer(deviceNodeId)`, fallback `getPeerByUserId()`). Other devices retrieve via S&F/Erasure.
2. **Call fan-out (V3.1.44):** `CALL_INVITE` uses `sendToAllDevices()` which queries `getAllPeersForUserId()` and sends to every known device. This allows the user to answer on any device.
3. **DeviceNodeId learning (V3.1.44):** Contacts passively learn a sender's deviceNodeId from `envelope.senderDeviceNodeId` on every incoming message. Learned deviceNodeIds are stored in `ContactInfo.deviceNodeIds` (persisted in contacts.json).
4. **Mailbox poll:** All devices poll the same Mailbox-ID. Each device retrieves and processes all available messages. The S&F peers do not distinguish between devices — they serve stored messages to any node that proves ownership of the Mailbox-ID.
5. **Latency:** The directly-reached device sees the message instantly. Other devices see it on the next event-driven push from a relay or S&F peer (typically within seconds once any peer of the recovering device comes online and sends a PONG). On a stale/cold network the device may have to wait until its own next outbound traffic triggers reciprocal polling. This is acceptable and consistent with how other multi-device messengers behave.

### 26.5 Device Management

#### 26.5.1 Settings UI

A new "Devices" section in the Settings screen shows all registered twin devices:

```
+---------------------------------------------------+
| Devices                                           |
|                                                   |
| [Phone] Martin's Pixel 8  (this device)           |
|         Online, LAN 198.51.100.42                 |
|         Since 12 April 2026                       |
|         [Rename]                                  |
|                                                   |
| [PC]    Desktop Linux                             |
|         Last seen 3 minutes ago                   |
|         192.0.2.201                            |
|         Since 10 April 2026                       |
|         [Rename] [Sign out]                       |
|                                                   |
| [!] Device lost?                                  |
| [Re-key identity]                                 |
|                                                   |
+---------------------------------------------------+
```

- **Rename:** Changes the device name. Synced to all twins via TWIN_SYNC (DEVICE_RENAMED).
- **Sign out:** Removes a device from the twin group (Section 26.6.1). Not available for the current device — use "Delete identity" instead.
- **Re-key identity:** Emergency key rotation for lost/stolen devices (Section 26.6.2). UI button wired to `rotateIdentityKeys()` — fully functional (v3.1.44).

#### 26.5.2 Device Name

The device name defaults to the operating system's hostname. Users can change it from any device in the twin group. Names are informational only — the `deviceId` (UUID) is the authoritative identifier. Duplicate names are allowed but discouraged by the UI.

### 26.6 Device Revocation

#### 26.6.1 Normal Deregistration ("Sign out")

When a device is deregistered from the Settings UI on another device:

1. A `TWIN_SYNC (DEVICE_REVOKED)` is sent to all twins, including the revoked device.
2. All twins remove the revoked device from their device list.
3. The revoked device, upon receiving the message, wipes its local database and returns to the welcome screen.
4. Contacts are notified via a `DEVICE_REVOKED` broadcast containing the revoked device's `deviceNodeId` (V3.1.44 Phase 4). Contacts remove the specific routing table entry via `removePeerByNodeId()` and remove the deviceNodeId from `ContactInfo.deviceNodeIds`. Fallback: for pre-Phase-4 peers without deviceNodeId, address-based removal is used.

This is sufficient for normal scenarios (old phone replaced, temporary installation removed).

#### 26.6.2 Emergency Key Rotation ("Re-key identity")

If a device is lost or stolen, the attacker has the master private key. Address revocation alone is insufficient — the attacker could re-announce in the DHT. For this scenario, a full key rotation is necessary:

1. User triggers "Re-key identity" from any remaining device.
2. The device generates a **new master seed** and derives new keys.
3. A `KEY_ROTATION_BROADCAST` is sent to all contacts, signed with BOTH the old key (proving ownership) and the new key (proving the new identity). The broadcast contains the new public keys.
4. Contacts that receive this broadcast update the stored public key for this contact and confirm via `KEY_ROTATION_ACK`.
5. All remaining twin devices receive the new seed via TWIN_SYNC (encrypted with the old key, since they still have it) and re-derive their keys.
6. The old Node-ID and Mailbox-ID become invalid. Messages in S&F/Erasure under the old Mailbox-ID are lost (acceptable — security over availability).

**Limitation:** Contacts that are offline during the rotation window may miss the broadcast. The KEY_ROTATION_BROADCAST is stored in S&F with a 30-day TTL (extended from the normal 7 days) to maximize the chance of reaching all contacts.

**Retry path (Paket C, V3.1.67):** `CleonaService` owns a per-identity `KeyRotationRetryManager` persisted as `key_rotation_retry.json.enc`. When `rotateIdentityKeys()` finishes the initial broadcast, the manager stores the dual-signed inner `KeyRotationBroadcast` protobuf, the **pre-rotation user-id** (captured before `rotateIdentityFull` flips `identity.userId`), and a pending set of all contact Node-IDs the broadcast was sent to. A 24h timer (plus an immediate pass at daemon startup) re-sends the same inner broadcast to every contact whose last attempt is older than the retry interval. The retry envelope uses `senderId = old user-id` (via `createSignedEnvelope(senderIdOverride: ...)`) so the offline receiver's `_contacts[senderHex]` lookup still hits before it has had a chance to apply the rotation — without this override, every retry would be silently dropped by the receiver at the contact-lookup stage. Only the OUTER envelope is rebuilt per attempt (signed with the new identity key); the inner dual-signature is what the receiver authenticates against the stored (old) pubkey. A contact that ACKs is moved to `acked` and never re-sent; a contact that does not ACK within **3 attempts** or the **90-day hard cutoff** is moved to `expired`, which fires an `onKeyRotationPendingExpired` / IPC `key_rotation_pending_contact` event so the UI can warn the user. The expired contact is **flagged, not removed** — re-verification is a human decision. A new `rotateIdentityKeys()` call supersedes any prior state completely (no concurrent epochs). Edge case where an ACK is lost AND the receiver already rotated will retry fruitlessly (old-signature verification fails because the receiver's stored pubkey is already the new one) and eventually flip to `expired`; a future idempotent re-ACK path on the receiver side is deferred to a follow-up commit.

**KEY_ROTATION_ACK authentication:** `_handleKeyRotationAck` verifies the outer envelope Ed25519 signature against `contact.ed25519Pk` before calling `markAcked`. Without this check, an attacker who knows a target contact's Node-ID could forge a KEY_ROTATION_ACK with that Node-ID as `senderId`, silently suppressing further retries to the real contact and stranding it on the pre-rotation keys. Since an ACK-sender's own Ed25519 key does not change during another peer's rotation, the rotator's contact record already holds the valid verification key. This is the only handler that performs outer-envelope signature verification — other message types rely on per-message KEM decryption + inner-payload signatures for authentication.

### 26.7 Constraints & Limitations

1. **No sub-keys:** All devices share the same master private key. A stolen device compromises the identity until key rotation is performed. This is a deliberate trade-off: simplicity over granular revocation.
2. **Sent message overhead:** Every outgoing message is effectively sent twice — once to the recipient, once to all twins. For a user with 2 devices, this doubles outgoing traffic. For 3 devices, it triples. Practical impact is small (text messages are tiny; media uses Two-Stage Transfer where only the metadata is synced, not the full file).
3. **No real-time sync:** Devices converge as event-driven push from relay/S&F peers reaches each device. There is no push-based instant sync between twins — this would require permanent connections between devices and contradict the stateless design.
4. **Maximum devices:** Soft limit of 5 devices per identity. More devices multiply TWIN_SYNC traffic and increase the risk of key compromise. The UI warns but does not enforce.
5. **Seed phrase security:** The seed phrase unlocks the identity on any device. Users must be informed that sharing the seed phrase is equivalent to granting full access to their identity and all its devices.

### 26.8 Protocol Messages (Multi-Device)

| Message Type | Description |
|---|---|
| `TWIN_ANNOUNCE` | New device announces itself to existing twins (contains DeviceRecord) |
| `TWIN_SYNC` | Local action synchronization (contains TwinSyncEnvelope) |
| `DEVICE_REVOKED` | Broadcast to contacts: remove specific device addresses |
| `KEY_ROTATION_BROADCAST` | Emergency: new public keys, dual-signed (old + new) |
| `KEY_ROTATION_ACK` | Contact confirms key rotation |
| `PRESENCE_UPDATE` | Planned (§26.9): online/offline signal to explicitly opted-in scopes |

All TWIN_SYNC messages between devices are encrypted with the identity's own public key via Per-Message KEM and delivered through the standard Three-Layer Delivery cascade.

### 26.9 Presence / Online-Status Badge (Planned)

**Origin:** User-feature request 2026-04-21 (tracked as Bug #U9 in the bug-intake protocol, relocated here as forward-looking design per user decision 2026-04-24). Not yet implemented.

**User story:** Next to each contact, group, and channel, the user sees a three-state badge:
- **Green** — at least one of the counterpart's devices is currently online
- **Red** — no device online
- **Question mark** — counterpart has not granted presence visibility

**Multi-Device Semantics (§26 interaction):** Because one identity can have up to 5 devices, "online" is aggregated across all devices of the counterpart's identity. A single device online is sufficient for green on the observer's side.

**Per-Scope Opt-in (privacy-first):** Presence visibility is configured per-scope (per-contact, per-group, per-channel), default-off. Granting is asymmetric: Alice can show her presence to Bob without Bob showing his to Alice. Revocation is one-click and instant.

**Protocol — `PRESENCE_UPDATE` payload:**

```
PresenceUpdate {
  identityUserId:  bytes       (User-ID of the sender)
  deviceNodeId:    bytes       (which physical device sends this)
  status:          enum        { ONLINE, OFFLINE, REVOKED }
  scopeKind:       enum        { DIRECT, GROUP, CHANNEL }
  scopeId:         bytes       (counterpart userId / groupId / channelId)
  sentAt:          int64       (unix millis; used for TTL)
}
```

**Wire flow:**
- **Sender side:** on login / `AppLifecycleState.resumed`, each device broadcasts `PRESENCE_UPDATE(ONLINE, scopeKind, scopeId)` once per scope that has been explicitly opted-in. On background / 60s idle, `OFFLINE`. Keepalive `ONLINE` every 90s while foreground.
- **Receiver side:** aggregates received updates per (identityUserId, scopeId). Badge is **green** if any `deviceNodeId` has an un-expired `ONLINE` record (TTL 2 min). **Red** if all expired or all devices sent `OFFLINE`. **Question mark** if no update has ever been received for this scope (= no grant).
- **Revocation:** user toggles "share my status" off for a scope → sends `PRESENCE_UPDATE(REVOKED, scopeKind, scopeId)`. Receivers drop the stored state and revert to the question-mark view.

**TTL & expiry:** `ONLINE` records expire 2 min after `sentAt`. Short connectivity blips are hidden by the 90s keepalive. Longer outages fall back to red (not question mark — the grant still exists, the counterpart is just unreachable).

**Cost estimate:** ~60 bytes per `PRESENCE_UPDATE` before encryption. 50 opted-in scopes × keepalive every 90s = ~33 messages/min per device = roughly 550 B/s on the wire after KEM framing. Same order of magnitude as DV-routing chatter; negligible next to media transfers.

**Delivery:** `PRESENCE_UPDATE` is an **ephemeral** message. It does NOT trigger DELIVERY_RECEIPT (per §3.x ephemeral rules), does NOT go through Store-and-Forward or Erasure Coding (no point in resurrecting a 2-min-old online signal 10 min later), and is NOT logged in the chat timeline. Direct-send or single-hop relay only; if the counterpart is unreachable, the signal is simply lost and the receiver falls back to red after TTL.

**Implementation notes (for the future session that builds this):**
- UI: a small colored dot overlay on `ProfileAvatar` (§V3.1.70 components), three states. Per-scope toggle in Chat-Info / Group-Info / Channel-Info dialogs.
- Storage: `presence_grants.json.enc` per identity (list of scopeIds that may see me online), plus an in-memory `Map<userId, Map<deviceNodeId, (status, expiresAt)>>` for received presence state (volatile, not persisted — regenerated on resume via next incoming update wave).
- Settings: "Presence visibility" section with a master default-off toggle and a list of explicitly granted scopes; bulk-revoke button.

**Status:** Planned. Not scheduled.

---

## 27. IPv6 Dual-Stack Transport & CGNAT Bypass

### 27.1 Problem: DS-Lite and CGNAT

DS-Lite is the standard deployment model for German ISPs (Telekom, Vodafone, 1&1) and increasingly common worldwide. In DS-Lite, the subscriber receives a global, directly routable IPv6 address but shares IPv4 connectivity through Carrier-Grade NAT (CGNAT).

**Consequences for P2P communication:**
- IPv4 behind CGNAT: no incoming connections possible via IPv4 alone
- CGNAT uses Symmetric NAT: standard UDP hole punching fails because the external port changes per destination
- UPnP/NAT-PMP only controls the subscriber's local router (CPE), not the carrier's CGNAT device
- Two CGNAT peers behind the same or different carriers cannot reach each other over IPv4 directly

### 27.2 Solution: IPv6 as Primary Transport

DS-Lite assigns a global, directly routable IPv6 address to every subscriber. Since IPv6 does not use NAT, every device is directly reachable — the fundamental requirement for P2P communication.

**Dual-Stack approach:**
- IPv4 socket (existing `_udpSocket`) retained for backward compatibility and LAN communication
- IPv6 socket (new `_udpSocket6`) added for global reachability
- Both sockets feed the same `_processUdpDatagram()` handler — no protocol differences
- `_socketFor(address)` selects the outgoing socket based on the destination address type
- Implicit IPv4-to-IPv6 bridging: a dual-stack node receiving on IPv4 can forward via IPv6 (and vice versa) without any special bridging code

### 27.3 Implementation

**Transport layer (`transport.dart`):**
- `_udpSocket` (IPv4, `InternetAddress.anyIPv4`) + `_udpSocket6` (IPv6, `InternetAddress.anyIPv6`), same port
- `_socketFor(InternetAddress addr)`: returns `_udpSocket6` for IPv6 addresses, `_udpSocket` for IPv4
- `rebind()` re-creates both sockets on port change

**Address prioritization (`PeerAddress.priority`):**
- IPv6 Global Unicast = priority 2 (better than Public IPv4 = 3, because no NAT)
- IPv6 Link-Local = priority 1 (same as LAN)
- LAN IPv4 = priority 1 (unchanged)

**PeerCapabilities bitmask:**
- `ipv4 = 1`, `ipv6 = 2`, `dualStack = 3`
- Advertised in PEER_LIST_PUSH and PONG messages
- Relay selection prefers dual-stack nodes (can bridge IPv4 peers to IPv6 peers)

**ContactSeed / QR:**
- IPv6 addresses encoded in bracket format: `[2001:db8::1]:41338`
- Seed peers can include both IPv4 and IPv6 addresses

**TLS fallback:**
- `_tlsServer6` on IPv6, binds the same port as UDP (V3.1.71; previously port+2)
- Selected by destination address type, same as UDP

### 27.4 CGNAT Bypass Techniques (IPv4)

When IPv6 is not available, the following IPv4-specific techniques improve connectivity:

**PCP (Port Control Protocol, RFC 6887):**
- Sent to well-known CGNAT/AFTR gateway addresses: `192.0.0.1` (DS-Lite AFTR), `100.64.0.1` (CGNAT gateway)
- Requests external port mapping on the carrier NAT device
- Not all carriers support PCP, so this is best-effort

**Port-Prediction Hole Punch:**
- For Symmetric NAT where the external port increments per destination
- Probes +/-10 ports around the predicted external port
- Coordinated via a mutual peer (same HolePunchRequest/Notify flow as standard hole punch)

**CGNAT range recognition:**
- `100.64.0.0/10` and `192.0.0.0/24` recognized as non-routable CGNAT ranges
- Addresses in these ranges are not used for direct delivery (relay required)
- Priority set to 5 (worse than public IPv4 = 3)

### 27.5 Seed-Peer Persistence

Seed peers learned from QR codes, NFC exchanges, or ContactSeed URIs are critical for initial connectivity — especially on Android where background execution is limited.

**`isProtectedSeed` flag:**
- Set on peers learned from QR/NFC/ContactSeed
- Protected seeds survive DHT maintenance pruning (normally 4h timeout for unresponsive peers)
- Ensures the bootstrap path remains available even after extended sleep periods

**Android Doze resilience:**
- On resume from Doze/App Standby: `onNetworkChanged()` triggers full recovery cycle
- Public IP re-discovery via ipify (IPv4 + IPv6)
- Protected seed peers are immediately pinged for fast re-establishment

### 27.6 Public-IP Discovery

Each platform discovers its public IPv4 and IPv6 addresses:

| Platform | IPv4 | IPv6 | Trigger |
|---|---|---|---|
| Desktop (service_daemon) | api.ipify.org | api6.ipify.org | Startup + 60s polling |
| Headless (bootstrap) | api.ipify.org | api6.ipify.org | Startup + 60s polling |
| Android (main.dart) | api.ipify.org | api6.ipify.org | Startup + Resume |

Both addresses are included in PEER_LIST_PUSH so that contacts learn all reachable addresses.

### 27.7 Bridging Architecture

```
IPv4 Peer ──UDP4──> Dual-Stack Node ──UDP6──> IPv6 Peer
                         |
              Same _processUdpDatagram()
              _socketFor() selects outgoing socket
```

No special bridging code is required. The bridging emerges automatically from the dual-socket architecture:

1. IPv4-only peer sends to dual-stack node via `_udpSocket`
2. Dual-stack node processes message, determines next hop is IPv6-only
3. `_socketFor()` selects `_udpSocket6` for the IPv6 destination
4. Message arrives at IPv6-only peer

This works transparently for all message types: DHT, relay, direct delivery, TLS escalation.

### 27.8 Mobile Fallback Socket (WiFi-Dead Detection)

When WiFi is connected but broken (captive portal, corporate firewall, dead NAT), the OS kernel routes all UDP traffic through the WiFi interface into the void. Mobile data would work but the OS ignores it because WiFi is the default route. This leaves the device isolated despite having a functioning mobile connection.

**Detection:** After `onNetworkChanged()` recovery + 15 seconds with 0 confirmed P2P peers AND multiple local IP addresses (WiFi + Mobile), the node infers that the WiFi path is dead.

**Probe:** `_tryMobileFallback()` enumerates all local IPs via `NetworkInterface.list()`. For each non-primary IP (candidates for mobile interface), a temporary UDP socket is bound to that IP and sends a PING to known peers with public addresses. If the send succeeds (packet left the interface), the interface is viable.

**Activation:** `Transport.startMobileFallback(mobileIp)` creates a persistent UDP socket (`_udpSocketMobile`) bound to the mobile IP on port 0 (OS-assigned ephemeral port). Port 0 is mandatory because the main socket on `0.0.0.0:port` already claims all interfaces on the original port.

**Routing:** `_socketFor(addr)` is extended: when mobile fallback is active AND the destination is a non-private IP (internet peer, not LAN), the mobile socket is selected. LAN destinations still use the main socket (WiFi may work for local communication even when internet is broken).

**WiFi auto-recovery:** When a UDP packet arrives on the main socket (`_udpSocket`, port = original), WiFi is working again. `stopMobileFallback()` closes the mobile socket and reverts to WiFi-only routing. This is safe because the mobile socket uses a different port (ephemeral) — mobile responses arrive on the mobile socket, not the main socket.

**Network change:** Every `onNetworkChanged()` call starts by deactivating any active mobile fallback (`transport.stopMobileFallback()`). The new network gets a clean start — the 15s probe will re-activate mobile fallback if needed.

**UI:** The connection status icon reflects mobile fallback state. When active, the icon shows the yellow mobile mascot with tooltip "Mobilfunk-Fallback — WLAN blockiert", even though the OS reports WiFi as connected. The `mobileFallbackActive` flag flows from Transport → CleonaNode → CleonaService → IPC → GUI.

### 27.9 NAT-Troubleshooting-Wizard (Manual Port-Forwarding Guidance)

**Problem context:** All automated NAT traversal techniques (UPnP IGD, PCP on CGNAT gateways, port-prediction hole punch, TLS fallback) can fail when the subscriber's router is locked down: UPnP disabled by the user or admin, restrictive firewall, or double-NAT setups where only the outer device supports UPnP. In these cases the node remains reachable only via relay — a working but degraded state. The user has no visibility into *why* it is degraded, and no path to fix it beyond guessing.

The wizard closes this gap: it detects sustained unreachability, diagnoses whether manual port-forwarding would help, and guides the user through the router-specific steps — without requiring any Cleona developer to maintain a router-screenshot database.

**Why manual forwarding is a viable recommendation:** The Cleona UDP port is assigned randomly at first launch and persisted in the profile's settings. It is explicitly editable in the Settings UI (with a rebind triggering `Transport.rebind()` + PeerListPush broadcast). This means a router rule pointing at "UDP port `<N>` → host `<IP>`" remains valid across restarts and reconnects. Port-forwarding is a legitimate, stable answer — not a fragile workaround.

#### 27.9.1 Trigger Conditions

The wizard does not interrupt the user on every transient failure. It fires only when sustained degradation is confirmed. All signals below must be true simultaneously for at least **10 minutes of uptime**:

1. **0 confirmed direct peer connections** (all traffic flowing through relay or TLS fallback) — observed via `NetworkStats.directPeerCount == 0` while `confirmedPeerCount > 0`.
2. **UPnP IGD unavailable** OR `AddPortMapping` rejected — tracked as `NetworkStats.upnpStatus ∈ {unavailable, rejected}`.
3. **PCP unavailable** OR no successful mapping response — tracked as `NetworkStats.pcpStatus == failed`.
4. **Not behind CGNAT** — external IPv4 from ipify is not in `100.64.0.0/10` or `192.0.0.0/24`. (Behind CGNAT, manual port-forwarding on the CPE router accomplishes nothing; the wizard instead shows a short CGNAT-education screen and recommends IPv6 or relay-only operation.)
5. **Dialog not already dismissed** — persistent flag `nat_wizard_dismissed_until` in settings (set by "Remind me later" → +7d, by "Don't show again" → forever).

The 10-minute window prevents false positives during Doze wake-up, network change, or initial DHT bootstrap. The signals already exist in `NetworkStats` — no new probing is introduced by the wizard itself.

**Manual trigger (V3.1.69):** In addition to the automatic 10-minute heuristic, the wizard can be opened any time by tapping the Connection Status icon in the AppBar when its tier is `good`/`weak`/`offline` (see §18.6.2). At tier `medium` (mobile/CGNAT) the explanation dialog is shown instead — port-forwarding on the CPE does not help there. Manual trigger ignores the `nat_wizard_dismissed_until` flag because the user has actively asked for help.

#### 27.9.2 Wizard Flow

Three screens, linear, dismissible at any step:

**Step 1 — Diagnose:** Plain-language explanation of the current state:
- "Cleona currently only reaches you via a detour (relay). That costs battery and makes calls more fragile. We can fix that if you set a one-time rule in your internet router."
- Shows current port and local IP as copyable text + a QR code encoding both (for scanning with a phone while logging into the router UI on a second screen).
- Buttons: **Show instructions**, **Later**, **Don't show again**.

**Step 2 — Router identification:**
1. If UPnP IGD returned a descriptor during discovery, the parsed `<manufacturer>` + `<modelName>` + `<modelNumber>` are cached in `NetworkStats.upnpRouterInfo`. The wizard uses them to select a matching entry from the router database.
2. If UPnP returned nothing (UPnP disabled — likely the reason we are here), the screen shows a dropdown **"My router is…"** listing the curated model set + a free-text "Other model" option.
3. If a specific entry matches, it is preselected; the user can override.

**Step 3 — Instructions:** Text + deep-link to the router admin UI. No screenshots in v1 — screenshots of router UIs age poorly (firmware updates rearrange menus) and cannot be responsibly AI-generated. Text + deep-link is more durable. Three content variants:

- **Model-matched (in DB):** Specific menu path (e.g. "Internet → Permit Access → Port Forwarding → New Rule"), specific field labels ("Label: Cleona", "Protocol: UDP", "Port: `<N>`", "To computer: `<IP>`"). Deep-link opens admin URL if known (e.g. `http://fritz.box/#freigaben`). Localized strings come from the router DB and i18n.
- **Model-detected but not in DB:** Shows detected model name at the top as context ("We have no specific instructions for *TP-Link Archer XY*"), then falls through to the generic variant, plus an opt-in link to a community contribution form (off-app, non-blocking).
- **Generic (fallback):** Model-agnostic steps covering the 80 % case — admin URL hints (`192.168.1.1` / `192.168.178.1`), menu terminology variants ("Port Forwarding / Portfreigabe / NAT / Virtual Server"), explicit IPv4 and IPv6 sub-sections (IPv6 needs a firewall exception, not a forward — a common source of confusion), and a UPnP-enable hint as an alternative to manual forwarding.

After the user reports completion, a **"Check now"** button re-triggers UPnP discovery + hole-punch round + 30s observation of direct-connection counter. Result is shown inline (green: "Direct connections active", red: "Still no direct connections — please check the rule"). No implicit retry, no auto-close on green: the user confirms.

#### 27.9.3 Router Database

Static JSON asset bundled with the app (`assets/router_db.json`), roughly 40 KB for ~20 curated models covering the German market majority: FRITZ!Box (7590/7490/7530/7530 AX/6591), Speedport (Smart 3/Smart 4/Pro), TP-Link Archer (C6/C7/AX10/AX50), Netgear Nighthawk (R7000/RAX20), ASUS RT-AX (55/58U/88U), Linksys (MR8300/MR9600), Deutsche Glasfaser ONT default CPE.

Per-entry fields:
```json
{
  "match": {
    "manufacturer_contains": ["AVM"],
    "model_contains": ["FRITZ!Box 7590"]
  },
  "display_name": "FRITZ!Box 7590",
  "admin_url_hints": ["http://fritz.box", "http://192.168.178.1"],
  "steps_i18n_key": "nat_wizard.fritz7590.steps",
  "deeplink_path": "/#freigaben",
  "notes_i18n_key": "nat_wizard.fritz7590.notes"
}
```

Instructions live in the i18n system (keyed by `steps_i18n_key`), which means they ride on the existing translation pipeline instead of being duplicated per language in the JSON. Unsupported languages fall back to English, the same pattern Calendar uses. Database is community-contributable via pull requests; no per-release enforcement.

#### 27.9.4 Non-Goals and Limitations

- **No router fingerprinting beyond UPnP:** We do not scrape the admin login page, do not perform MAC OUI lookups, do not probe well-known vendor paths. Each of these raises its own false-positive and IDS-flagging risks that are disproportionate to the benefit.
- **No screenshots in v1:** Text + deep-link only. Screenshots may be added later if user feedback requests it, but will be sourced from users/community, not AI-generated or scraped.
- **No CGNAT "solution":** Behind CGNAT the wizard informs, not guides — the CPE is not the bottleneck. A link to the IPv6 section of the user manual is the correct ending.
- **No auto-retry of the port rule:** The Jetzt-pruefen button is explicit. Silently polling UPnP in the background while the user works in the router admin UI would generate confusing intermediate states.

#### 27.9.5 Footprint

- Wizard UI (three Flutter screens): ~300 LOC
- Trigger evaluation + state machine (in `CleonaService` + `NetworkStats`): ~80 LOC
- UPnP descriptor parse extension (in `nat_traversal.dart`): ~50 LOC
- Router DB JSON asset: ~40 KB
- i18n strings: ~40 keys × 4 languages + EN fallback: ~10 KB
- Smoke + E2E tests: ~200 LOC Dart + ~150 LOC TypeScript

Total binary impact below ~100 KB — well under 0.3 % of the APK, versus the 30–60 % of runtime sessions estimated to be relay-degraded in locked-down-router environments. The wizard converts an invisible "my messages sometimes take longer" user experience into a tractable, one-time fix.

### 27.10 Doze-Whitelisting Opt-out (#U18 Layer 4) — Retired

Originally introduced as part of #U18 (`4600880`, 2026-04-25): a Settings-screen toggle that asked the user to add Cleona to the Android battery-optimization whitelist via `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, plus an OEM-fallback path into the global "Akkunutzung von Apps" settings list.

Removed in `8ec005f` (2026-04-26) after the user-driven architecture review summarised in §7.8. The toggle was implementing a user-control surface for behaviour Cleona cannot actually control without a third-party push mechanism, and the OEM-fallback path's screen-jump produced the original UX confusion that triggered the review.

The `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission, the `chat.cleona/battery` MethodChannel, the `_BatteryOptimizationCard` widget, and the three associated i18n keys are all gone. Foreground-service-type apps remain Doze-exempt while in the foreground state (§7.7), which is the documented Android behaviour that Cleona now relies on.

---

## 28. Appendix: Protocol Message Format

All Cleona protocol messages are serialized using Protocol Buffers for efficient, extensible binary encoding. The core message envelope is defined below. All fields are present in every message; unused fields are left at their default values. **This same protocol is used by ALL nodes — there is no separate protocol for the bootstrap node.**

```protobuf
message MessageEnvelope {
  uint32 version = 1;
  bytes sender_id = 2;        // 32 bytes, SHA-256(tag + pubkey)
  bytes recipient_id = 3;     // 32 bytes, or empty for broadcasts
  uint64 timestamp = 4;       // Unix milliseconds
  MessageType message_type = 5;
  bytes encrypted_payload = 6;
  bytes signature_ed25519 = 7;
  bytes signature_ml_dsa = 8;
  ContentMetadata content_metadata = 9;
  EditMetadata edit_metadata = 10;
  ExpiryMetadata expiry_metadata = 11;
  ErasureCodingMetadata erasure_metadata = 12;
  ProofOfWork pow = 13;
  PerMessageKem kem_header = 14;   // Ephemeral PK + KEM ciphertext (see 4.3)
  reserved 15;                     // was: PqxdhInit (removed)
  CompressionType compression = 16;
  string network_tag = 17;         // Diagnostic only — security enforced by HMAC (Section 17.5)
  bytes message_id = 18;      // UUID v4 (16 bytes)
}

enum MessageType {
  // Core messaging
  TEXT = 0; IMAGE = 1; VIDEO = 2; GIF = 3;
  EMOJI_REACTION = 4;
  MEDIA_ANNOUNCEMENT = 5; MEDIA_ACCEPT = 6; MEDIA_REJECT = 7;
  MESSAGE_EDIT = 8; MESSAGE_EXPIRE_CONFIG = 9;

  // Key management
  KEY_ROTATION = 10;           // Public key rotation announcement
  reserved 11, 12;             // was: PREKEY_BUNDLE, KEY_EXCHANGE_RESPONSE (removed)

  // Recovery
  RESTORE_BROADCAST = 13; RESTORE_RESPONSE = 14;

  // Presence & receipts
  TYPING_INDICATOR = 15; READ_RECEIPT = 16;
  DELIVERY_RECEIPT = 90;

  // Groups
  GROUP_CREATE = 17; GROUP_INVITE = 18;
  GROUP_LEAVE = 19; GROUP_KEY_UPDATE = 20;
  MESSAGE_DELETE = 21;
  VOICE_MESSAGE = 22; FILE = 23;

  // Calls (Opus/VP8 signaling + overlay multicast)
  CALL_INVITE = 30; CALL_ANSWER = 31;
  CALL_REJECT = 32; CALL_HANGUP = 33;
  ICE_CANDIDATE = 34; CALL_REJOIN = 35;

  // Peer list exchange (3-step delta)
  PEER_LIST_SUMMARY = 50; PEER_LIST_WANT = 51; PEER_LIST_PUSH = 52;

  // Contact requests
  reserved 60, 61;             // was: PQXDH_INIT, OTK_BATCH (removed)
  CONTACT_REQUEST = 62; CONTACT_REQUEST_RESPONSE = 63;

  // Channels
  CHANNEL_CREATE = 70; CHANNEL_POST = 71;
  CHANNEL_INVITE = 72; CHANNEL_ROLE_UPDATE = 73;
  CHANNEL_LEAVE = 74;

  // DHT operations
  DHT_PING = 80; DHT_PONG = 81;
  DHT_FIND_NODE = 82; DHT_FIND_NODE_RESPONSE = 83;
  DHT_STORE = 84; DHT_STORE_RESPONSE = 85;
  DHT_FIND_VALUE = 86; DHT_FIND_VALUE_RESPONSE = 87;

  // Fragment storage (erasure coding) with RUDP ACK
  FRAGMENT_STORE = 90; FRAGMENT_STORE_ACK = 91;
  FRAGMENT_RETRIEVE = 92; FRAGMENT_DELETE = 93;

  // Per-chat configuration
  CHAT_CONFIG_UPDATE = 100; CHAT_CONFIG_RESPONSE = 101;

  // Identity management
  IDENTITY_DELETED = 102;

  // Profile updates
  PROFILE_UPDATE = 103;

  // Distance-Vector routing
  ROUTE_UPDATE = 110;

  // Reachability probing
  REACHABILITY_QUERY = 112; REACHABILITY_RESPONSE = 113;

  // Store-and-Forward (whole messages for offline peers)
  PEER_STORE = 114; PEER_STORE_ACK = 115;
  PEER_RETRIEVE = 116; PEER_RETRIEVE_RESPONSE = 117;
}
```

**ContactRequestMsg (with profile data):**
```protobuf
message ContactRequestMsg {
  string display_name = 1;
  bytes ed25519_public_key = 2;
  bytes ml_dsa_public_key = 3;
  bytes x25519_public_key = 4;
  bytes ml_kem_public_key = 5;
  string message = 6;
  bytes profile_picture = 7;     // JPEG, max 64KB
  string description = 8;       // Max 500 chars
}
```

**ContactRequestResponse (with profile data):**
```protobuf
message ContactRequestResponse {
  bool accepted = 1;
  string rejection_reason = 2;
  bytes ed25519_public_key = 3;
  bytes ml_dsa_public_key = 4;
  bytes x25519_public_key = 5;
  bytes ml_kem_public_key = 6;
  string display_name = 7;
  bytes profile_picture = 8;     // Responder's profile pic
  string description = 9;       // Responder's description
}
```

**ProfileData (PROFILE_UPDATE payload):**
```protobuf
message ProfileData {
  bytes profile_picture = 1;     // JPEG, max 64KB
  string description = 2;       // Max 500 chars
  uint64 updated_at_ms = 3;     // Timestamp for conflict resolution
  string display_name = 4;      // Updated display name (empty = unchanged)
}
```

**Contact Local Alias:** Recipients can set a `localAlias` on any ContactInfo. When set, `effectiveName` (= localAlias ?? displayName) is used for display. If a contact sends a PROFILE_UPDATE with a new `display_name` and the recipient has a `localAlias`, the new name is stored as `pendingNameChange` and a banner prompts the user to accept or keep their alias.

**ChannelCreate (with picture):**
```protobuf
message ChannelCreate {
  bytes channel_id = 1;
  string name = 2;
  string description = 3;
  bool announcement_only = 4;
  ExpiryMetadata default_expiry = 5;
  bytes picture = 6;             // JPEG, max 64KB
}
```

**ChannelInvite (with profile data):**
```protobuf
message ChannelInvite {
  bytes channel_id = 1;
  string channel_name = 2;
  bytes inviter_id = 3;
  string role = 4;
  bytes welcome_message = 5;
  bytes channel_picture = 6;     // JPEG, max 64KB
  string channel_description = 7;
}
```

**ChannelPost (group/channel media):**
```protobuf
message ChannelPost {
  bytes channel_id = 1;
  bytes post_id = 2;
  string text = 3;
  ContentMetadata media = 4;
  bytes content_data = 5;        // Binary content (file/voice/image data)
}
```

**ChatConfigUpdate (per-chat configuration):**
```protobuf
message ChatConfigUpdate {
  string conversation_id = 1;
  bool allow_downloads = 2;
  bool allow_forwarding = 3;
  bool is_request = 4;
  bool accepted = 5;
  sint64 expiry_duration_ms = 6;
  sint64 edit_window_ms = 7;
}
```

**IdentityDeletedNotification:**
```protobuf
message IdentityDeletedNotification {
  bytes identity_ed25519_pk = 1;
  uint64 deleted_at_ms = 2;
  string display_name = 3;
}
```

**RestoreResponse (with profile data):**
```protobuf
message RestoreResponse {
  uint32 restore_phase = 1;
  RestoreContactInfo contact_info = 2;  // Includes profile_picture, description
  repeated RestoreMessage messages = 3;
  repeated RestoreGroup groups = 4;     // Includes group_picture, group_description
  RestoreChatPolicy chat_policy = 5;
  bool has_more = 6;
  uint64 oldest_timestamp_ms = 7;
  string recoverer_display_name = 8;
}

message RestoreGroupMember {
  bytes node_id = 1;
  string role = 2;
  string display_name = 3;
  bytes ed25519_public_key = 4;
  bytes ml_dsa_public_key = 5;
  bytes x25519_public_key = 6;
  bytes ml_kem_public_key = 7;
  bytes profile_picture = 8;
  string description = 9;
}
```

Chat configuration changes (`CHAT_CONFIG_UPDATE`, type 100) carry proposed setting changes. In DM conversations, the partner must confirm via `CHAT_CONFIG_RESPONSE` (type 101) with `accepted=true`. In groups, the owner sets configuration directly — no confirmation step. Only the Owner can change settings (`canChangeSettings`), not Admins.

Group messages are wrapped in `ChannelPost` and sent as `GROUP_KEY_UPDATE` to each member individually via pairwise Per-Message KEM encryption. Channel posts use `CHANNEL_POST` type with the same pairwise delivery pattern.

**Store-and-Forward (whole message storage for offline peers):**
```protobuf
message PeerStore {
  bytes recipient_id = 1;         // Intended final recipient
  bytes wrapped_envelope = 2;     // Complete encrypted message
  uint64 stored_at_ms = 3;
}

message PeerStoreAck {
  bytes recipient_id = 1;
  bool success = 2;
}

message PeerRetrieve {
  bytes requester_id = 1;         // Node requesting its stored messages
}

message PeerRetrieveResponse {
  repeated bytes stored_envelopes = 1;  // All stored messages for requester
}
```

**Distance-Vector Route Update:**
```protobuf
message RouteUpdate {
  repeated RouteEntry routes = 1;
}

message RouteEntry {
  bytes destination = 1;          // 32 bytes NodeId
  int32 hopCount = 2;
  int32 cost = 3;
  ConnectionType connType = 4;
  int64 lastConfirmedMs = 5;
}
```

**Processing order for outgoing messages:** Serialize → Compress (zstd) → Encrypt (AES-256-GCM via Per-Message KEM) → Sign (Ed25519 + ML-DSA-65) → Erasure code (if non-ephemeral) → Attach PoW → Send.

**Incoming:** Verify PoW → Verify signatures → Reconstruct (if erasure coded) → Deduplicate (pre-decrypt) → Decrypt → Decompress → Deserialize.

Nodes reject any message where: the packet HMAC is invalid (see Section 17.5), PoW is invalid or insufficient, signatures fail verification, or erasure coding metadata is inconsistent. All communication occurs on a single UDP port — the same protocol for every node in the network.

---

*End of document. Version 2.4 — April 2026.*
