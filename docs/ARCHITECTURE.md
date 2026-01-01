# Cleona Chat -- Architecture & Technical Specification

**Decentralized -- Post-Quantum Secure -- Peer-to-Peer**

Public Edition

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Network Architecture](#2-network-architecture)
3. [Erasure Coding & Message Delivery](#3-erasure-coding--message-delivery)
4. [Encryption & Cryptography](#4-encryption--cryptography)
5. [Identity & Authentication](#5-identity--authentication)
6. [Identity Recovery & Restore Broadcast](#6-identity-recovery--restore-broadcast)
7. [Synchronization Strategy](#7-synchronization-strategy)
8. [DoS Protection & Network Resilience](#8-dos-protection--network-resilience)
9. [Protocol Escalation & Transport](#9-protocol-escalation--transport)
10. [Channels & Moderation](#10-channels--moderation)
11. [Voice & Video Calls](#11-voice--video-calls)
12. [Platform Architecture](#12-platform-architecture)
13. [Technology Stack](#13-technology-stack)
14. [Security Considerations](#14-security-considerations)
15. [Message Flow Summary](#15-message-flow-summary)

---

## 1. Executive Summary

Cleona Chat is a decentralized, peer-to-peer messaging application that operates
entirely without central servers. It combines post-quantum cryptography with an
innovative network architecture to deliver secure, reliable communication.

The application is built with Flutter (Dart) for cross-platform development,
targeting Android and iOS as primary release platforms, with Linux and Windows
Desktop as additional supported platforms.

### 1.1 Core Principles

**No central servers.** All communication is fully peer-to-peer via a
Kademlia-based Distributed Hash Table (DHT). There is no single point of failure
or control. Every node in the network is a full participant -- capable of routing
messages, storing fragments for offline peers, and sharing peer knowledge.

**Post-quantum end-to-end encryption.** A hybrid approach combining classical
algorithms (X25519, Ed25519, AES-256-GCM) with post-quantum algorithms
(ML-KEM-768, ML-DSA-65). If either scheme is broken, the other still protects
all communication. Database files on disk are encrypted at rest with
XSalsa20-Poly1305.

**Anonymity by design.** No phone number, email address, or personal information
is required. Identity is purely cryptographic -- a key pair generated on the
device.

**Erasure coding for offline delivery.** Messages are split into N=10 redundant
fragments using Reed-Solomon coding, of which only K=7 are needed for
reconstruction. Fragments are distributed across peers near the recipient's
virtual mailbox in DHT space.

**Push-first message delivery.** Message delivery is event-driven, not
polling-based. Relay nodes forward fragments immediately to the mailbox owner
upon storage. Polling occurs only once at startup.

**Restore Broadcast.** An innovative recovery mechanism where contacts serve as a
distributed backup. Upon device loss, a signed broadcast triggers automatic
identity and chat history restoration from contacts -- no cloud server needed.

**HD-Wallet Multi-Identity.** A single master seed derives all identities using
HD-wallet-style key derivation. Recovery of the master seed via a 24-word phrase
restores all identities.

**Single port communication.** Each node uses a single random ephemeral UDP port.
All traffic (chat, DHT, relay, signaling, media) goes through this single port.
A TLS fallback provides censorship resistance when UDP is blocked.

**Data compression.** All protocol payloads are compressed with zstd before
encryption, reducing bandwidth usage significantly for text and metadata.

### 1.2 Unique Innovations

**Erasure Coding for Messaging.** Borrowed from distributed storage systems
(Ceph, IPFS), but applied to messenger offline delivery. It solves the offline
problem without central servers at only 1.43x storage overhead.

**Restore Broadcast.** Your contacts ARE your backup -- without them needing to
do anything actively. This eliminates the need for cloud storage entirely.

**Per-Message Key Encapsulation.** Instead of session-based protocols (like
Double Ratchet), every message is self-contained. There is no shared mutable
state between sender and recipient that could desynchronize.

**Mesh Discovery.** Infrastructure-free peer discovery through physical
encounters. Every meeting between two Cleona users merges their entire network
graphs, creating organic, viral network growth.

---

## 2. Network Architecture

### 2.1 Communication Port

Each Cleona node communicates over a single UDP port, randomly selected from the
ephemeral range on first launch and persisted. This avoids requiring root
privileges and eliminates conflicts with other services. A TLS listener on
port+2 serves as an anti-censorship fallback.

Network separation between beta and production networks is achieved through
cryptographic means (network secrets in node IDs), not through port separation.

### 2.2 Distributed Hash Table (DHT)

Cleona uses a Kademlia-based DHT as the backbone of its peer-to-peer network.
Kademlia provides O(log n) routing, natural redundancy through k-bucket
replication, and has been proven at scale (BitTorrent, IPFS, Ethereum).

#### 2.2.1 Node Identity

Every device running Cleona is a node in the DHT. The node ID is computed as:

```
node_id = SHA-256(network_secret + public_key_bytes)
```

This produces a 256-bit identifier. The `network_secret` is derived from the
Maintainer Ed25519 key and the network channel. Because the secret differs
between channels and is unknown to forks, nodes with a different secret occupy a
completely separate DHT address space -- they can never discover or communicate
with each other.

#### 2.2.2 Virtual Mailbox

Each user has a virtual mailbox in the DHT address space, derived differently
from the node ID to prevent correlation:

```
mailbox_id = SHA-256("mailbox" + public_key_bytes)
```

Nodes whose IDs are closest in XOR distance to the mailbox ID are responsible
for temporarily storing message fragments for the user when they are offline.

#### 2.2.3 Routing Table (Distance-Vector)

Each node maintains a routing table with **routes** (not just peers). Inspired
by RIP (Routing Information Protocol), adapted for P2P mesh.

**Route entry:** Each route contains: destination (NodeId), nextHop (NodeId,
null for direct), hopCount, cost (sum of link costs), connectionType (LAN,
public UDP, hole punch, relay, mobile), and lastConfirmed timestamp. Multiple
routes per destination are allowed, sorted by cost (cheapest first).

**Cost model:** Each link type has a fixed cost reflecting its reliability and
expense. LAN connections are cheapest; mobile relay connections are most
expensive. Total route cost equals the sum of all link costs on the path. Cost
determines route selection only -- it is independent of TTL.

**Distance-Vector protocol:** Route updates are propagated event-driven (not
periodic) using Bellman-Ford. **Split Horizon** prevents routes from being
advertised back to the neighbor they were learned from. **Poison Reverse**
advertises failed routes with infinite cost to prevent counting-to-infinity.
A safety-net full route exchange occurs periodically.

**Route-Down detection:** A route is marked DOWN after consecutive RUDP Light
timeouts (no DELIVERY_RECEIPT). Route-DOWN is surgical: only the specific route
via a specific nextHop is marked, not all routes to the peer. If alternative
routes exist, the peer is not considered unreachable. Dead routes remain briefly
in the table for recovery via neighbor updates.

**Three-tier capacity:**

| Tier | Purpose | Eviction Policy |
|------|---------|-----------------|
| Contact routes | Direct contacts | Never evicted |
| Transit routes | Kademlia k-buckets (O(log n)) | Standard Kademlia rules |
| Channel routes | Channel subscribers | LRU + highest cost first |

### 2.3 Mesh Discovery

Cleona uses organic, infrastructure-free peer discovery. Nodes find each other
through physical proximity and share their knowledge transitively.

#### 2.3.1 The Principle

Every Cleona node maintains a peer list: a signed, timestamped directory of all
known nodes. When two nodes encounter each other -- on the same WiFi, via NFC
tap, or through a QR code scan -- they exchange their complete peer lists. This
is mathematically equivalent to the "six degrees of separation" principle.

#### 2.3.2 Peer List Entry

Each entry in the peer list contains:

- Node ID (32 bytes)
- Multi-address list (scored by reliability)
- Network channel identifier
- Last-seen timestamp
- NAT type classification
- Capabilities bitfield
- Ed25519 + ML-DSA public keys
- Dual signatures (classical + post-quantum)

Each `PeerAddress` tracks success/fail counts and a reliability score. The
`allConnectionTargets()` method returns a deduplicated, scored list sorted by
reliability. Stale entries (no successful contact within a configurable window)
are automatically removed.

#### 2.3.3 Passive Discovery (Automatic)

**IPv6 Multicast:** Cleona sends a compact HMAC-authenticated discovery packet
to a link-local multicast group. All Cleona nodes on the same local network
respond with their node ID and reachability info. Zero configuration needed.

**IPv4 Local Broadcast:** Discovery packets on a fixed UDP port via IPv4
broadcast. Limited to the local subnet -- never crosses subnet boundaries.

**IPv4 Multicast:** The same HMAC-authenticated packet sent to an
organization-local scope multicast group. Can be routed across subnets by
routers with IGMP support.

**Event-driven discovery:** Discovery packets are sent as a short burst on all
channels in parallel at startup and on network change, then the sender stops.
No perpetual broadcasting.

**Cross-Subnet Unicast Scan:** When broadcast and multicast find no peers, a
one-time unicast scan probes the local address range. The scan stops immediately
when a peer responds.

#### 2.3.4 Active Discovery (Deliberate User Action)

**NFC Contact Exchange.** Two phones held together (~4cm range) exchange identity
data and peer lists instantly. This serves a dual purpose: peer discovery (merge
network graphs) and contact pairing (exchange public keys). Contacts established
via NFC are assigned a high verification level due to physical co-presence.

**Why not Bluetooth Low Energy?** BLE was evaluated and rejected: (1) presence
leakage -- BLE advertising broadcasts "this device runs Cleona" to everyone
within ~30m; (2) peer list poisoning -- BLE operates outside the Closed Network
Model; (3) eclipse attacks on fresh nodes; (4) no meaningful benefit over
existing LAN discovery mechanisms.

**QR Code / ContactSeed.** One user displays a QR code containing a ContactSeed
URI. The URI encodes the sender's node ID, display name, reachable addresses,
and several seed peers. The scanner connects to any seed peer, bootstraps into
the full network via Kademlia, and sends a contact request.

**Copy & Paste ContactSeed URI.** The same URI can be shared via any text
channel: email, SMS, another messenger. The "Add Contact" dialog accepts both
plain hex Node-IDs and full `cleona://` URIs.

#### 2.3.5 Peer List Exchange Protocol

When two nodes discover each other, they execute a delta-based peer list
exchange: both send a compact summary (IDs + timestamps), each side identifies
entries the other is missing, and only the requested full PeerInfos are
transmitted. This is bandwidth-efficient even for large peer lists.

### 2.4 NAT Traversal & Reachability

Cleona uses a multi-strategy approach for connecting nodes behind NAT:

#### 2.4.1 Public Address Discovery

A decentralized STUN mechanism: when Node A receives a packet from Node B, it
reports B's public IP back. Multiple confirmations are required before a node
accepts a reported public IP. No dedicated STUN server needed -- every peer
provides this service.

Address scoring tracks success/fail counts for each known address. Addresses
with very low scores are deprioritized. Exponential backoff prevents repeated
attempts to unreachable addresses.

#### 2.4.2 Connection Strategies (Priority Order)

1. **Direct LAN** (both on same subnet or routable via gateway)
2. **Direct public UDP** (one or both have public IP)
3. **UDP hole punching** (both behind NAT, coordinated via mutual peer)
4. **Relay via known route** (Distance-Vector routing table provides relay path)
5. **Default-Gateway** (forward to best-connected peer for unknown destinations)

#### 2.4.3 Active UDP Hole Punch & NAT Keepalive

When a node learns about a peer with a public IP, it attempts a coordinated UDP
hole punch via a third-party coordinator:

1. Node A asks coordinator to notify Node B.
2. Both A and B send UDP packets to each other's public IP, opening NAT pinholes.
3. Direct communication established -- relay becomes unnecessary.

**NAT timeout probing.** The keepalive interval is dynamically determined per
connection by probing with increasing intervals until the NAT mapping expires.
Keepalive is set to a fraction of the detected NAT timeout.

**The NAT keepalive is the only periodic network traffic in the entire system.**
Everything else is event-driven.

#### 2.4.4 Route-Based Delivery

The routing table determines the cheapest route. On failure, the next cheapest
route is tried. After consecutive timeouts on a route, it is marked DOWN with
Poison Reverse. Addresses within a route are prioritized:
LAN > Public > Mobile/CGNAT.

**Default-Gateway.** When no route to the destination exists, the message is
forwarded to the best-connected known peer. TTL prevents loops.

### 2.5 Bootstrap Node

An optional accelerator for the early network phase. It is a normal Cleona node
running headless -- not a special server. It uses the exact same code and
protocol as every other node. Its only distinction is guaranteed uptime.

**Not hardcoded.** New nodes learn the bootstrap address exclusively through
social contact (QR code / ContactSeed URI).

**Not a dependency.** Nodes with existing peers operate independently. The
bootstrap can be decommissioned when the network is self-sustaining (a
configurable threshold of simultaneously online nodes over a sustained period).

### 2.6 Network Change Detection

When a device switches networks (WiFi to cellular, new WLAN, VPN toggle):

1. Reset NAT traversal (clear cached public IP)
2. Reset relay routes
3. Trigger discovery burst
4. Ping all known peers
5. Re-bootstrap Kademlia DHT
6. Broadcast route update
7. Poll mailbox for missed messages

Detection mechanisms are platform-specific: connectivity event streams on
Flutter, IP polling on headless daemons, public IP polling for long-running
servers.

### 2.7 Multi-Hop Relay

**Distance-Vector routing makes relay proactive.** The routing table knows which
peer serves as relay -- no reactive searching needed.

**Wrapper architecture.** The original envelope remains unchanged (signatures +
PoW valid). Relay nodes see only encrypted blobs.

**Loop prevention.** Three layers: relay-ID dedup cache, visited-nodes list, and
TTL (start=64, decremented per hop, dropped at 0).

**Rate limiting.** Configurable per-source and total relay budgets prevent abuse.

---

## 3. Erasure Coding & Message Delivery

### 3.1 Concept

Inspired by RAID-5 but more resilient, Cleona uses Reed-Solomon erasure coding
for two purposes:

1. **Offline message delivery.** When the recipient is offline, fragments are
   distributed to DHT peers near the recipient's mailbox. When the recipient
   comes online, any 7 of 10 fragments suffice to reconstruct the message.

2. **Recovery backup.** Fragments serve as distributed backup. If the chat
   partner is offline during recovery, DHT fragments can still reconstruct
   messages.

This is fundamentally different from simple replication (N copies): erasure
coding achieves the same reliability at only 1.43x storage overhead versus Nx
for replication.

### 3.2 Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| N (total fragments) | 10 | Distributed across 10 nearest DHT peers |
| K (required for reconstruction) | 7 | Tolerates 3 peer failures |
| Redundancy factor | 1.43x | Efficient use of relay storage |
| Fragment retention | 7 days | Balance between backup reliability and storage |

Fragments are not deleted immediately after successful delivery. They remain as
recovery backup for a configurable period. Deletion occurs when the fragment
exceeds its TTL or both chat partners have deleted the message.

### 3.3 Three-Layer Delivery

Every non-ephemeral message uses three complementary delivery mechanisms:

**Layer 1 -- Route-based delivery.** The message is sent as a whole (not
fragmented) to the recipient via the cheapest route in the Distance-Vector
routing table. This may be direct or via relay. The sender waits for a
DELIVERY_RECEIPT (RUDP Light) to confirm delivery.

**Layer 2 -- Store-and-Forward on mutual peers.** If direct/relay delivery fails,
the complete message is stored on **mutual peers** -- nodes known to both sender
and recipient that are currently online. Messages are stored whole, not
fragmented.

**Layer 3 -- Reed-Solomon erasure-coded backup.** The message is split into N=10
fragments and distributed across DHT peers using ACK-driven delivery. This
protects against long-term node failures.

**Why three layers?** Each addresses a different failure mode:

- Layer 1: Recipient is online but on a different network path
- Layer 2: Recipient is temporarily offline (hours)
- Layer 3: Storage nodes themselves fail permanently (days/weeks)

**Ephemeral messages** (typing indicators, read receipts, delivery receipts)
skip erasure-coded backup.

### 3.4 RUDP Light (Reliable UDP)

UDP is fire-and-forget. Cleona adds a lightweight reliability layer that
provides delivery feedback without TCP's overhead.

**Design.** The RUDP layer does NOT retransmit until acknowledged (like TCP).
Instead, it provides a **delivery receipt** per message: the receiver sends a
short ACK. If no ACK arrives within a timeout, the sender knows the peer is
unreachable and can act -- try an alternative route, mark the route as down, or
trigger relay.

**ACK timeout.** Based on the observed round-trip time (RTT) to the specific
peer, using exponential moving average. For peers with no RTT history, a
conservative default is used.

**No retransmit to same peer.** If the ACK times out, an alternative peer is
selected rather than retransmitting to the same (likely unreachable) peer.

**Route-Down detection.** After consecutive RUDP Light timeouts, the specific
route is marked DOWN and Poison Reverse is propagated. This is surgical: only
the specific route via a specific nextHop is invalidated, not all routes.

### 3.5 App-Level UDP Fragmentation

Payloads exceeding the UDP MTU (~1200 bytes, common with PQ keys) are fragmented
at the application level:

1. Payload split into chunks with a compact header (magic, fragmentId, index,
   total)
2. Each fragment sent individually via UDP
3. Each fragment tracked by RUDP Light
4. Missing fragments requested via Fragment-NACK (active retransmission)
5. Receiver reassembles after all fragments arrive

**Fragment-NACK.** When the receiver detects missing fragments, it sends a NACK
listing the missing indices. The sender resends only those fragments. This
avoids waiting for full RUDP timeout on partial loss.

**Distinction from Reed-Solomon.** App-level fragmentation handles large payloads
to ONLINE peers. Reed-Solomon handles storage for OFFLINE peers with redundancy.

### 3.6 Intelligent Fragment Distribution

Fragments are distributed with ACK feedback:

1. **Initial distribution:** Select N target peers (sorted by RTT/reliability),
   send one fragment to each.
2. **ACK collection:** Wait for ACK within RTT-based timeout per fragment.
3. **Redistribution on failure:** For unacknowledged fragments, select
   alternative peers and resend.
4. **Completion check:** Once N ACKs are collected (from original or alternative
   peers), the message is STORED_IN_NETWORK -- fully reconstructable.

**Fragment replication limit.** A maximum number of copies per fragment prevents
flooding in small networks.

**Physical host awareness.** When multiple identities run on the same device,
the fragment distributor selects at most one peer per physical host, preserving
the redundancy purpose of erasure coding.

### 3.7 Message Status Lifecycle

```
QUEUED -> SENT -> STORED_IN_NETWORK -> DELIVERED -> READ
```

| Status | Meaning |
|--------|---------|
| QUEUED | In persistent SendQueue, no peer reachable |
| SENT | Fragments dispatched, ACKs pending |
| STORED_IN_NETWORK | Sufficient ACKs received, message reconstructable |
| DELIVERED | Recipient has reassembled (DELIVERY_RECEIPT) |
| READ | Recipient has viewed (READ_RECEIPT, optional) |

### 3.8 Store-and-Forward on Mutual Peers

When direct and relay delivery both fail, the complete message is stored on
mutual peers -- nodes known to both sender and recipient. Mutual peers are
computed from shared contacts and shared group members. Up to 3 mutual peers
are selected; if fewer are available, any confirmed peer serves as fallback.

**Proactive push.** When a storing peer detects the recipient is back online
(via PONG or DELIVERY_RECEIPT), it immediately pushes stored messages. The
startup poll serves as fallback.

### 3.9 Two-Stage Media Delivery

Large media files use a two-stage process:

1. **Metadata announcement:** Filename, size, MIME type, compressed thumbnail,
   and content hash are sent via the normal delivery path.
2. **Confirmed transfer:** The actual file transfer begins only after the
   recipient explicitly requests download.

Auto-download thresholds are user-configurable per media type.

### 3.10 Mailbox: Push-First with Startup Poll

Delivery is push-first: relay nodes that store a fragment immediately forward it
to the mailbox owner if they know the owner's address. Sub-second delivery
latency for most messages.

**Startup poll.** When a node comes online, it polls once to collect fragments
that accumulated while offline. During normal operation, no periodic polling
occurs.

---

## 4. Encryption & Cryptography

### 4.1 Design Philosophy

Cleona employs a hybrid encryption scheme combining classical algorithms with
post-quantum algorithms. An attacker must break BOTH simultaneously. If either
remains secure, all data is protected.

**Stateless by design.** Cleona uses Per-Message Key Encapsulation instead of
session-based protocols (like Signal's Double Ratchet). Every message is
self-contained. There is no shared mutable state that could desynchronize. This
eliminates an entire class of bugs while maintaining equivalent security
properties.

### 4.2 Cryptographic Primitives

| Category | Algorithm | Key Size | Purpose |
|----------|-----------|----------|---------|
| Identity Signatures | Ed25519 + ML-DSA-65 | 32B + 4,595B | Dual signatures |
| Per-Message KEM | X25519 + ML-KEM-768 | 32B + 1,184B | Per-message key encapsulation |
| Symmetric (Messages) | AES-256-GCM | 256-bit | Message encryption |
| Symmetric (DB at rest) | XSalsa20-Poly1305 | 256-bit | Database encryption |
| Symmetric (Calls) | AES-256-GCM | 256-bit | Real-time media (SRTP) |
| Hash | SHA-256 | 256-bit | Node ID, Mailbox ID, KDF |
| KDF | HKDF-SHA256 | Variable | Key derivation |
| Password Hash | Argon2id | Variable | Key file encryption |

### 4.3 Per-Message Key Encapsulation (Stateless E2E)

Every message is encrypted with a fresh, one-time key derived independently.

#### 4.3.1 How It Works

**Sending (Alice to Bob):**

1. Alice generates a fresh ephemeral X25519 key pair.
2. Alice performs X25519 Diffie-Hellman with Bob's public key.
3. Alice performs ML-KEM-768 encapsulation to Bob's ML-KEM public key.
4. Alice derives the message key:
   `msg_key = HKDF-SHA256(dh_secret || kem_secret, "cleona-msg-v1")`
5. Alice encrypts the payload with AES-256-GCM.
6. Alice sends: `[eph_pk | kem_ciphertext | aes_nonce | encrypted_payload]`
7. Alice **deletes** the ephemeral private key immediately.

**Receiving (Bob):**

1. Bob extracts the ephemeral public key and KEM ciphertext.
2. Bob performs X25519 DH and ML-KEM-768 decapsulation.
3. Bob derives the same message key via HKDF.
4. Bob decrypts the payload.

No state required. Bob needs only his own private keys and the ephemeral data
embedded in the message.

#### 4.3.2 Security Properties

| Property | How It Is Achieved |
|----------|-------------------|
| **Forward Secrecy** | Ephemeral private key deleted immediately after encryption |
| **Post-Quantum Security** | Hybrid: X25519 + ML-KEM-768. Must break BOTH |
| **Per-Message Keys** | Fresh ephemeral key per message. One compromise reveals nothing about others |
| **Post-Compromise Recovery** | Key rotation creates new keys; attacker with old key loses access |
| **Offline Delivery** | Only needs recipient's public key. No handshake required |
| **No Session Breakage** | No session to break, corrupt, or desynchronize |

#### 4.3.3 Key Rotation

Each identity periodically rotates its X25519 and ML-KEM public keys:

1. New key pair generated.
2. Distributed to all contacts via KEY_ROTATION message.
3. Senders use the latest known public key.
4. Old private key retained for a transition period to decrypt in-transit
   messages.
5. Old private key deleted after transition.

**Timing invariant.** The key transition period is strictly longer than the DHT
fragment retention period. This guarantees that every erasure-coded fragment can
be decrypted within the transition window.

#### 4.3.4 Per-Message Overhead

| Component | Size |
|-----------|------|
| X25519 ephemeral public key | 32 bytes |
| ML-KEM-768 ciphertext | 1,088 bytes |
| AES-256-GCM nonce | 12 bytes |
| **Total** | **~1.1 KB per message** |

The overhead is constant regardless of message size. For large media files, it
is negligible. The trade-off: eliminating the entire PQXDH handshake
infrastructure (Pre-Key Bundles, OTKs, SPK rotation, session state persistence)
is a massive simplification.

#### 4.3.5 Encryption Exceptions

The following are NOT encrypted with Per-Message KEM:

- **RESTORE_BROADCAST / RESTORE_RESPONSE** -- A recovering peer may not have the
  sender's current public key. Signed only.
- **CONTACT_REQUEST / CONTACT_REQUEST_RESPONSE** -- First contact; the sender
  may not have the recipient's encryption key yet. Signed only.

All other message types are always encrypted.

### 4.4 Call Encryption

Real-time voice and video calls use an ephemeral symmetric key negotiated once
at call start (per-message KEM overhead would be unacceptable at 50+
packets/second):

1. Both parties generate fresh ephemeral X25519 + ML-KEM-768 key pairs.
2. Both exchange ephemeral public keys and KEM ciphertexts via CALL_INVITE /
   CALL_ANSWER.
3. Both derive: `call_key = HKDF(DH_a||DH_b||KEM_a||KEM_b, "cleona-call-v1")`
4. All media frames encrypted with AES-256-GCM using the call key.
5. Call key exists only in memory; deleted on hangup.

**Group calls:** The initiator generates a random call key, encrypted
individually to each participant via Per-Message KEM. Key rotation occurs
when a participant is kicked or a new participant joins.

### 4.5 Group Encryption (Pairwise Per-Message KEM)

Group messages use pairwise Per-Message KEM: each message is individually
encrypted to each group member using their public key with a fresh ephemeral
key per member. No shared group key exists.

**Trade-offs.** O(n) send cost per message versus O(1) for shared-key approaches
like MLS. For Cleona's target group sizes (up to ~50 members), this is
acceptable and provides stronger security: compromising one member's private key
does not affect any other member's encryption.

### 4.6 Encryption Order

Outgoing messages are processed as:

```
Serialize (Protobuf) -> Compress (zstd) -> Encrypt (Per-Message KEM, AES-256-GCM)
  -> Sign (Ed25519 + ML-DSA-65) -> Erasure Code (if non-ephemeral)
  -> Proof of Work -> Send
```

Incoming messages are processed in reverse order.

### 4.7 Database Encryption at Rest

All SQLite databases are encrypted at rest using XSalsa20-Poly1305 (libsodium
AEAD).

**Key derivation.**

```
db_key = SHA-256(ed25519_secret_key[0:32] + "cleona-db-key-v1")
```

**File format.** `[24-byte random nonce][ciphertext + Poly1305 MAC]`

**Runtime flow:**

1. On startup, decrypt to a temp file. SQLite operates on this.
2. Periodic encrypted flushes for crash safety.
3. On shutdown, final encrypted flush; temp file securely deleted.
4. Automatic migration from unencrypted to encrypted databases.

### 4.8 Key Storage

| Platform | Storage | Protection |
|----------|---------|------------|
| Android | Android Keystore | Hardware-backed |
| iOS | Secure Enclave / Keychain | Hardware-backed |
| Linux | File-based (keys.json) | Argon2id + XSalsa20-Poly1305 |

The master seed is never stored in plaintext.

---

## 5. Identity & Authentication

### 5.1 Identity Model

Cleona uses a purely cryptographic identity model. No email, phone number, or
personal information is required or collected. At first launch, the app generates
two hybrid key pairs: encryption (X25519 + ML-KEM-768) and signing (Ed25519 +
ML-DSA-65).

Users set a human-readable display name during setup. Names can be changed at
any time; changes are broadcast to all contacts. Recipients can locally rename
any contact without affecting the actual name.

### 5.2 Multi-Identity Architecture

A single Cleona installation can host multiple cryptographic identities. Each
identity has its own keys, contact list, message history, and database.

#### 5.2.1 HD-Wallet Key Derivation

All identities are derived from a single master seed (256 bits) using
index-based SHA-256 context strings:

```
ed25519_seed = SHA-256(master_seed + "cleona-identity-N-ed25519")
```

Where N is a monotonically increasing identity index (never reused). X25519 keys
are derived via birational mapping from Ed25519. Post-quantum keys (ML-DSA-65,
ML-KEM-768) are generated fresh per identity because the PQ libraries do not
support seeded key generation.

The master seed is encoded as a 24-word recovery phrase for human-friendly
backup.

#### 5.2.2 Identity Switching

All identity nodes run simultaneously. Switching identities in the UI is
instantaneous -- no reconnection needed.

### 5.3 Contact Verification

Contacts are added via QR code, ContactSeed URI, NFC tap, or Mesh Discovery.
There is no address book upload or phone number matching. Four verification
levels:

| Level | How Established |
|-------|-----------------|
| **Unverified** | Contact added via Node-ID or URI |
| **Seen** | Key exchange completed successfully |
| **Verified** | QR code or NFC verification in person |
| **Trusted** | Explicitly marked by user |

Key changes trigger prominent notifications.

### 5.4 Contact Request Protocol

Adding a contact requires explicit mutual consent. The request includes display
name, all public keys, optional profile data, and a Proof of Work.

**Anti-spam protections:** PoW on each request, configurable rate limiting,
deduplication, and blocking (no response to blocked senders).

**KEX Gate.** Encrypted messages are only processed if the sender is an accepted
contact or group member. Unknown senders are silently dropped.

### 5.5 Identity Deletion

When an identity is deleted, an IDENTITY_DELETED notification is sent to all
contacts. Contacts clean up associated data and display a notification.

---

## 6. Identity Recovery & Restore Broadcast

### 6.1 Recovery Phrase (24 Words)

At initial setup, the app generates a 24-word recovery phrase encoding 264 bits
(256 bits entropy + 8-bit checksum). The word list uses deterministic phonetic
generation for pronounceability.

From the seed, key pairs are derived deterministically via SHA-256 with context
strings. Post-quantum keys cannot be derived from the seed and are regenerated
after recovery.

### 6.2 Social Recovery (Shamir's Secret Sharing)

As an alternative to remembering the phrase, users can designate 5 trusted
contacts as recovery guardians. The seed is split into 5 shares using Shamir's
Secret Sharing (threshold: 3 of 5, GF(256) arithmetic).

An attacker would need to compromise 3 of 5 guardians simultaneously. Guardians
do not know who the other guardians are.

### 6.3 Restore Broadcast

After key recovery, the app sends a signed broadcast to all former contacts:

1. User recovers private key (phrase or Social Recovery).
2. App wipes old profile, re-derives keys from seed.
3. App joins DHT with the recovered identity (original Node-ID).
4. Signed Restore Broadcast sent to all contacts.
5. Contacts verify signature and respond with: contact list, encrypted chat
   history, group/channel memberships.

**Progressive restoration:**

- **Phase 1 (seconds):** Contact list rebuilds as contacts respond.
- **Phase 2 (minutes):** Latest messages per conversation delivered first.
- **Phase 3 (hours/days):** Full chat history loads progressively.

**Anti-abuse:** Rate-limited broadcasts, guardian confirmation required before
contacts release data, visible notification to all contacts.

**Post-quantum key handling.** Fresh PQ keys are generated and distributed via
the Restore Broadcast. During the brief transition, messages use classical-only
encryption (still secure against non-quantum attackers).

### 6.4 DHT Identity Registry (Erasure-Coded)

To recover multiple identities from a single master seed:

**DHT Key:** `SHA-256(master_seed + "cleona-registry-id")`

**Encryption Key:** `SHA-256(master_seed + "cleona-registry-key")` (XSalsa20-Poly1305)

The encrypted registry is split using Reed-Solomon (N=10, K=7) and distributed
across the 10 DHT nodes closest to the registry's key. Only the master seed
holder can decrypt it.

---

## 7. Synchronization Strategy

### 7.1 Push-First Architecture

Message delivery is event-driven and push-based. When a message is sent, it is
pushed immediately to the recipient or to relay/storage nodes. There are no
periodic sync intervals during normal operation.

Relay nodes push fragments immediately when the mailbox owner becomes reachable.
The only polling is a single startup poll to collect messages that arrived while
completely offline.

### 7.2 Platform-Specific Background Behavior

**Android.** Background service keeps the UDP socket alive. WorkManager schedules
periodic wake-ups during Doze mode. Optional foreground service for near-instant
delivery.

**iOS.** Background App Refresh provides periodic wake-up windows. APNs delivers
zero-content wake-up signals.

**Desktop (Linux/Windows).** Background daemon runs continuously with permanently
open UDP socket. Instant push delivery.

### 7.3 Optional Push Wake-Up (FCM / APNs)

Push notifications are an optional comfort layer for faster mobile wake-up. They
are not architecturally required.

A lightweight relay peer monitors incoming fragments for registered nodes and
sends zero-content push notifications. The push payload contains no message
content, no sender info, no preview -- zero metadata leakage.

---

## 8. DoS Protection & Network Resilience

Without central infrastructure, the P2P network must defend against flooding,
spam, and storage abuse. Cleona implements five layers of defense.

### 8.1 Layer 1: Proof of Work per Message

Every application-level message includes a SHA-256 based hashcash Proof of Work.
The sender must find a nonce producing a hash with a configurable number of
leading zero bits.

**Exemptions:**

- **LAN peers:** Messages between peers on the same local network skip PoW (they
  are already authenticated via signatures and encryption).
- **Infrastructure messages:** Group/channel management, key rotation, profile
  updates, recovery, and ephemeral messages are exempt (authenticated by
  signature).
- **Relay-bound messages:** Messages routed through relay skip sender-side PoW
  (the receiver exempts relay-delivered messages).

PoW is computed asynchronously to prevent UI freezes.

### 8.2 Layer 2: Rate Limiting per Node Identity

Each node tracks traffic volume per source Node-ID and enforces configurable
rate limits (packets and bytes per time window). Excessive traffic from a single
source is silently dropped. Relay-unwrapped inner envelopes and
Store-and-Forward-retrieved messages are exempt from rate limiting (the outer
envelope was already counted).

Every packet that passes the rate limiter generates a positive reputation event,
ensuring that normal infrastructure traffic (DHT, routing, peer exchange) builds
reputation.

### 8.3 Layer 3: Reputation System

Nodes build reputation over time based on observed behavior. Reputation is
strictly local -- each node independently evaluates its peers. New nodes start
with a neutral reputation.

Ban decisions consider the peer's overall reputation score, not just absolute
bad action counts. A peer with good history is not banned for transient
rate-limit violations. Permanent bans require consistently poor scores. When
temporary bans expire, bad action counters decay to prevent de-facto permanent
bans from single bursts.

### 8.4 Layer 4: Fragment Budgets

Each node allocates limited relay storage per source Node-ID. Excess fragments
are rejected. This prevents a single attacker from filling all relay storage.

### 8.5 Layer 5: Network-Level Banning

Nodes can temporarily or permanently ban misbehaving peers. Bans are strictly
local decisions -- no central ban list. When many independent nodes ban the same
attacker, the attacker becomes effectively isolated from the network.

---

## 9. Protocol Escalation & Transport

### 9.1 UDP as Primary Transport

All normal traffic uses UDP exclusively. App-level fragmentation handles
payloads exceeding the UDP MTU. RUDP Light provides delivery confirmation and
integrity verification.

### 9.2 TLS Anti-Censorship Fallback

A TLS listener on port+2 activates when UDP is completely blocked (corporate
firewalls, censored countries) after consecutive UDP failures. When active, TLS
replaces UDP as the transport layer for the affected peer. All message types
flow over TLS.

RUDP Light remains active even over TLS for application-level reachability
detection (a missing DELIVERY_RECEIPT indicates the peer is unresponsive even
if the TLS connection is open).

**Recovery probes.** Even with active TLS fallback, periodic UDP probes check
whether UDP has become available again. On success, the node switches back to
UDP.

### 9.3 Three-Stage Escalation

```
Stage 1: UDP single packet (<=MTU)
Stage 2: UDP fragmented with Fragment-NACK retry (>MTU)
Stage 3: TLS on port+2 (when UDP is blocked)
```

---

## 10. Channels & Moderation

### 10.1 Private Channels

Invitation-only broadcast channels with role-based access control:

| Role | Groups | Channels |
|------|--------|----------|
| Owner | Full control | Full control |
| Admin | Invite/remove, moderate, post, config | Invite/remove, moderate, post |
| Member | Read + post | -- |
| Subscriber | -- | Read only |

Encryption is pairwise E2E, identical to regular group chats (Per-Message KEM
to each member).

### 10.2 Public Channels

Openly discoverable broadcast channels listed in a compressed DHT index.

**Channel discovery.** Users find channels via a searchable directory. Each entry
includes name, language, content rating, description snippet, subscriber count,
and moderation status.

**Uniqueness.** Channel names are globally unique via DHT key derivation.
First-come-first-served with squatting protection (identity must have a minimum
network age).

**Content rating.** Channels carry a content rating (general or mature). Mature
channels are invisible to identities that have not self-declared as adult.

### 10.3 Decentralized Content Moderation

Six report categories: mislabeled maturity, wrong content, and four types of
illegal content (drugs, weapons, CSAM, other).

**Single post reports** are sent to channel admins. If unresolved after a
configurable period, they escalate to channel-level reports.

**Channel-level reports** require the reporter to select specific posts as
evidence. When the report counter reaches a configurable threshold, a jury of
randomly selected users reviews the evidence.

#### 10.3.1 Jury System

- Random jurors selected from users with the same language as the reported
  channel.
- Jurors must not be connected to the channel or reporters (independence check
  based on shared group/channel membership size relative to total network size).
- Configurable jury size and voting timeout.
- 2/3 majority required for action.
- Consequences: content reclassification, Bad Badge escalation, or channel
  deletion (DHT tombstone).

#### 10.3.2 Bad Badge System

A trust signal for misleading channel descriptions. Three-stage escalation:

| Stage | Consequence |
|-------|-------------|
| 1 | "Content questionable" label, probation after admin correction |
| 2 | "Repeatedly misleading" label, longer probation |
| 3 | Permanent label |

Badges are never hidden -- only deprioritized in search with visual warning.

#### 10.3.3 CSAM Special Procedure

CSAM cannot use the standard jury procedure because viewing CSAM is itself
illegal. Instead: a graduated response based on independent reporter count with
no jury involvement:

1. First report: registered, no visible action.
2. Configurable threshold of independent reports: channel temporarily hidden;
   admin can file objection triggering a limited jury review (jury reviews
   metadata, not content).
3. Higher threshold: channel permanently deleted (tombstone).

**Anti-abuse:** Elevated reporter requirements (network age, conversation count,
contact count, adult flag, reporting cooldown). Strike system for demonstrably
malicious reports.

#### 10.3.4 Anti-Sybil: Social Graph Reachability Check

Defense against coordinated bot reports: when a report is filed, random validator
nodes check whether the reporter's identity is reachable within a limited number
of hops through the social graph. Bot clusters form isolated islands with no
paths to the real network, causing validation to fail.

Each node maintains a Bloom filter of contacts at limited depth. Reachability is
a local lookup (yes/no) -- no social graph data is exposed.

All checks are performed by receiving nodes at the network level, not by the
reporter's app. Modified clients cannot bypass this.

---

## 11. Voice & Video Calls

### 11.1 Design Principles

- **Direct P2P.** No server, no SFU, no TURN.
- **Post-quantum encryption.** Hybrid X25519 + ML-KEM-768 key exchange.
- **Overlay Multicast Tree** for group calls (not full mesh).
- **LAN IPv6 Multicast** for local participants.
- **Forward Secrecy.** Ephemeral keys only in RAM, never persisted.

### 11.2 Audio Engine

- Codec: Opus (configurable bitrate)
- Adaptive jitter buffer for out-of-order delivery and packet loss
- Capture isolation (separate processing thread)
- Frame encryption: AES-256-GCM per frame with sequence number

### 11.3 Video Engine

- Codec: VP8 (libvpx)
- Adaptive bitrate based on measured bandwidth
- PiP (Picture-in-Picture) layout

### 11.4 1:1 Call Flow

```
Alice                                    Bob
  |                                        |
  |-- CALL_INVITE (eph keys, KEM ct) ---->|
  |                                        |
  |<-- CALL_ANSWER (eph keys, KEM ct) ----|
  |                                        |
  Both derive: call_key = HKDF(DH + KEM, "cleona-call-v1")
  |                                        |
  |<=== AES-256-GCM encrypted media =====>|
  |                                        |
  |-- CALL_HANGUP ----------------------->|
  |   call_key deleted                     |
```

### 11.5 Group Calls

**Key distribution:** Initiator generates random call key, encrypted
individually to each participant via Per-Message KEM. Key rotation on kick or
new participant (not on crash+rejoin).

**Overlay Multicast Tree:** For participants across different networks, an
application-layer multicast tree distributes streams. Each participant uploads at
most 2-3 streams regardless of group size. The tree is constructed dynamically
based on measured RTT and available bandwidth, using the Distance-Vector routing
table as a weighted graph.

**LAN optimization:** Participants on the same local network use IPv6 multicast.
One stream reaches all local participants simultaneously -- zero additional
upload cost.

**Scaling limits:**

| Mode | Max Participants | Bottleneck |
|------|-----------------|------------|
| Video call | ~50 | Overlay tree depth, cumulative latency |
| Audio call | 100+ | Audio bitrate is negligible |

---

## 12. Platform Architecture

### 12.1 Daemon + GUI Separation

Cleona is split into two layers:

1. **Background Service (Daemon).** Contains all networking, DHT, cryptography,
   message storage, and relay logic. Runs without a GUI.

2. **GUI (Flutter Frontend).** Visual interface for chatting, contacts, settings.
   Connects to the local daemon. Can be opened and closed without affecting
   message delivery.

```
+------------------------------------------+
|  System Tray / App Icon                  |  <- Badge with unread count
+------------------------------------------+
|  GUI (Flutter Window)                    |  <- Opens/closes independently
|  - Chat screens, contacts, settings      |
+------------------------------------------+
|  Background Service (CleonaNode)         |  <- Runs continuously
|  - DHT routing, peer discovery           |
|  - Message encryption/decryption         |
|  - Fragment storage/relay                |
|  - Offline message queuing               |
+------------------------------------------+
```

### 12.2 Six-Layer Architecture

The full message path passes through six distinct layers:

| Layer | Function | Common Failure Modes |
|-------|----------|---------------------|
| 1+2 Network | UDP transport, DHT, peer discovery, RUDP | NAT blocks, firewall, ACK timeout |
| 3 Storage | Fragment store/retrieve, mailbox ID | Mailbox ID mismatch, fragment loss |
| 4 Encryption | Per-Message KEM, signatures | Missing public key, corrupted ciphertext |
| 5 Service | Contact management, groups, routing | Missing callback wiring, dedup issues |
| 6 GUI | Flutter widgets, state management | Provider not notified, stale state |

A failure in any layer blocks all layers above. Diagnostics work bottom-up.

### 12.3 IPC Communication

**Linux.** Unix Domain Socket. JSON-Lines protocol with identity routing.

**Windows.** TCP loopback with shared-secret authentication token. The daemon
writes a port+token file; clients authenticate on connect. Unauthenticated
connections are immediately closed.

**Android/iOS.** In-process communication (daemon and GUI share a single
process).

### 12.4 Multi-Identity Single Port

One daemon, one UDP port, all identities simultaneously active. The daemon
routes incoming messages to the correct identity based on recipient ID.

### 12.5 Single-Instance Guard

The daemon enforces single-instance via multiple checks: lock file with living
PID, IPC endpoint reachability, and UDP port probing. On startup failure, the
daemon cleans up and exits -- preventing zombie daemons.

---

## 13. Technology Stack

| Component | Technology |
|-----------|-----------|
| Framework | Flutter (Dart) |
| Platforms | Linux Desktop, Windows Desktop, Android, iOS |
| Database | SQLite via drift ORM, encrypted at rest |
| Serialization | Protocol Buffers |
| Classical Crypto | libsodium (Ed25519, X25519, XSalsa20-Poly1305, SHA-256, Argon2id) |
| Post-Quantum Crypto | liboqs (ML-KEM-768, ML-DSA-65) |
| Erasure Coding | Reed-Solomon (liberasurecode / pure Dart fallback) |
| Compression | zstd (libzstd) |
| Audio Codec | Opus (libopus via FFI) |
| Video Codec | VP8 (libvpx via FFI) |
| Voice Transcription | whisper.cpp (on-device, no cloud) |
| Network Detection | connectivity_plus (Flutter), NetworkInterface polling (headless) |
| FFI | Dart FFI for all native library bindings |

### 13.1 Localization

33 languages including right-to-left support (Arabic, Hebrew, Farsi). System
language auto-detection with English fallback. RTL layout automatically applied
via Flutter's built-in RTL support.

---

## 14. Security Considerations

### 14.1 Closed Network Model

Cleona follows the Signal model: source code is publicly available for auditing,
but only official maintainer-signed builds participate in the network. This
protects against malicious forks.

#### Network Secret

The packet format depends on a build-time secret derived from the Maintainer
Ed25519 key:

```
network_secret = HMAC-SHA256(maintainer_private_key, "cleona-network-" + channel)
```

Nodes without the correct secret compute different Node-IDs (parallel DHT
address space) and cannot parse or generate valid packets. They are
cryptographically isolated.

#### Packet-Level Authentication

Every outgoing UDP packet is authenticated:

```
[8B truncated HMAC-SHA256(network_secret, payload)][payload]
```

On receipt, invalid HMAC causes immediate silent drop before any further
processing. This provides:

- **Invisibility.** Fork nodes' packets are dropped at the earliest stage.
- **DoS resistance.** Invalid packets rejected with a single fast HMAC check.
- **No protocol leakage.** Without the secret, packet contents are opaque.

#### Secret Rotation

The network secret is rotated with each major release. During a transition
period, nodes accept packets with either the current or previous secret.
Outgoing packets always use the current secret. After the transition, the
previous secret is dropped. Extracted secrets from old builds become worthless.

#### Binary Protection

The network secret is split, XOR-masked, and distributed across different code
locations. Dart AOT compilation produces native machine code with no readable
source or string table. This raises the extraction effort above the threshold
where building a separate messenger is easier.

#### Defense-in-Depth Summary

| Layer | Mechanism | Protects Against |
|-------|-----------|-----------------|
| 1 | Network Secret + HMAC | Fork nodes cannot participate |
| 2 | Secret Node-IDs | Fork nodes in separate DHT space |
| 3 | Binary Obfuscation | Casual reverse engineering |
| 4 | Secret Rotation | Extracted secrets expire |
| 5 | Donation Signatures | Address swapping without re-signing |
| 6 | Distribution Signing | Tampered binaries detectable |
| 7 | Trademark + License | Legal protection for name/brand |

### 14.2 Network Security

- **Dual signature verification.** All messages are signed with both Ed25519 and
  ML-DSA-65. Both verified on receipt.
- **NAT amplification prevention.** DHT responses do not trigger further
  responses.
- **Lenient stale key handling.** Stale cached keys are cleared on mismatch
  rather than rejecting messages, allowing recovery from key rotation.
- **HMAC-authenticated discovery.** Discovery packets are authenticated before
  any protocol parsing.
- **IPv6 zone ID filtering.** Link-local zone IDs (interface-specific) are
  excluded from shared peer data.
- **IP sanitization.** Malformed IP strings are cleaned before use.

### 14.3 Database Security

All databases encrypted at rest (XSalsa20-Poly1305). Key derived from identity's
Ed25519 secret key via SHA-256. Quantum-resistant: SHA-256 provides 128-bit
security against Grover's algorithm. Unencrypted temp files securely deleted on
shutdown.

### 14.4 Key Storage Security

Private keys encrypted with Argon2id + XSalsa20-Poly1305 on desktop, and
hardware-backed storage (Android Keystore, iOS Secure Enclave) on mobile.

### 14.5 App Permissions

Minimum-permissions philosophy. Permissions requested only when the feature is
first used:

| Permission | When Requested |
|-----------|---------------|
| Network/Internet | Always (core functionality) |
| Camera | First photo/video/QR scan |
| Microphone | First voice message/call |
| Storage | First media send/receive |
| NFC | First NFC contact exchange |
| Notifications | First message received |

**Never requested:** Contacts/Address Book, Location/GPS, Phone State/Call Logs.

---

## 15. Message Flow Summary

### 15.1 Outgoing Message

```
1. User types message
2. Serialize to Protobuf
3. Compress with zstd
4. Encrypt with Per-Message KEM (fresh ephemeral X25519 + ML-KEM-768)
   -> AES-256-GCM with derived message key
5. Dual sign: Ed25519 + ML-DSA-65
6. Compute Proof of Work (if required)
7. Three-Layer Send:
   Layer 1: Direct/Relay via cheapest route (RUDP Light)
   Layer 2: Store-and-Forward on mutual peers (if Layer 1 fails)
   Layer 3: Reed-Solomon erasure-coded backup on DHT peers
8. Wait for DELIVERY_RECEIPT
```

### 15.2 Incoming Message

```
1. Receive UDP packet
2. Verify HMAC (network authentication) -- drop if invalid
3. Verify Proof of Work -- drop if invalid
4. Verify dual signatures (Ed25519 + ML-DSA-65) -- drop if invalid
5. Check KEX Gate: is sender an accepted contact or group member?
6. Per-Message KEM decryption (X25519 DH + ML-KEM-768 decapsulate -> HKDF -> AES-256-GCM)
7. Decompress (zstd)
8. Deserialize Protobuf
9. Deduplicate (check against processed message IDs)
10. Route to correct conversation
11. Send DELIVERY_RECEIPT to sender
```

### 15.3 Offline Message Retrieval

```
1. Node comes online
2. Startup poll: FRAGMENT_RETRIEVE to all recently-confirmed peers
3. Simultaneously: PEER_RETRIEVE for Store-and-Forward whole messages
4. Collect Reed-Solomon fragments
5. When K=7 or more fragments available: reconstruct via Reed-Solomon
6. Decrypt and process as normal incoming message
7. Send FRAGMENT_DELETE to relay peers to free storage
```

---

## Appendix A: Cryptographic Algorithm Rationale

### Why Per-Message KEM Instead of Double Ratchet?

The Double Ratchet (used by Signal, WhatsApp) provides excellent forward secrecy
through continuous key derivation. However, it requires synchronized session
state between sender and recipient. In a decentralized, offline-capable system:

1. **Session establishment requires online handshake.** In Cleona, the recipient
   may be offline for days. Per-Message KEM requires only the recipient's public
   key (known from contact exchange).

2. **Session state can desynchronize.** Device loss, restore, multi-device use,
   and network partitions all risk desynchronizing ratchet state. Per-Message KEM
   has no state to lose.

3. **Complexity cost.** Double Ratchet requires Pre-Key Bundles, one-time keys,
   signed pre-keys, session establishment messages, and ratchet state
   persistence. Per-Message KEM eliminates all of this.

4. **Security equivalent.** Per-Message KEM provides forward secrecy (ephemeral
   key deleted immediately), post-quantum security (hybrid KEM), and
   post-compromise recovery (key rotation). The trade-off is ~1.1 KB overhead
   per message.

### Why Hybrid (Classical + Post-Quantum)?

Post-quantum algorithms (ML-KEM-768, ML-DSA-65) are relatively new. While
standardized by NIST, they lack the decades of cryptanalysis that classical
algorithms have undergone. The hybrid approach ensures:

- If ML-KEM-768 is broken, X25519 still protects communication.
- If X25519 is broken (quantum computer), ML-KEM-768 still protects.
- An attacker must break BOTH simultaneously.

### Why Reed-Solomon Instead of Simple Replication?

Simple replication of N=10 copies requires 10x the storage. Reed-Solomon with
N=10, K=7 requires only 1.43x storage while tolerating the same number of node
failures (3 of 10). In a P2P network where every node contributes limited
storage, this efficiency difference is significant.

---

## Appendix B: Threat Model

### Assumptions

- The attacker controls some fraction of network nodes.
- The attacker can observe all network traffic (passive).
- The attacker can inject, modify, or drop packets (active).
- The attacker may have access to quantum computers (future).
- The attacker does NOT have physical access to the target device.

### Mitigated Threats

| Threat | Mitigation |
|--------|-----------|
| Message interception | Per-Message KEM (hybrid PQ) E2E encryption |
| Message tampering | Dual signatures (Ed25519 + ML-DSA-65) |
| Replay attacks | Message ID deduplication, PoW freshness |
| Spam/flooding | 5-layer DoS protection (PoW, rate limiting, reputation, fragment budgets, banning) |
| Sybil attacks | Anti-Sybil social graph reachability, configurable reporter requirements |
| Metadata leakage | No central server sees message patterns; relay nodes see only encrypted blobs |
| Key compromise (past) | Forward secrecy via ephemeral keys deleted after use |
| Key compromise (future) | Post-compromise recovery via key rotation |
| Quantum computers | ML-KEM-768 + ML-DSA-65 hybrid encryption |
| Device theft | Database encryption at rest, hardware-backed key storage on mobile |
| Eclipse attacks | Closed Network Model (HMAC authentication), no BLE (peer list poisoning vector removed) |
| Coordinated false reports | Jury system with independence criteria, anti-Sybil validation |

### Acknowledged Limitations

- **No hardware attestation.** A sufficiently determined attacker who extracts
  the network secret from an official build can participate in the network with
  modified code. This is inherent to any system without TPM/Play Integrity.

- **Group scalability.** Pairwise encryption has O(n) cost. Groups beyond ~50
  members may experience noticeable send latency. Future migration to MLS
  (RFC 9420) is architecturally possible.

- **Recovery requires contacts.** If ALL contacts are permanently offline,
  recovery is impossible. This is by design -- contacts are the distributed
  backup.

- **P2P reachability.** If no path exists between two participants (both behind
  Symmetric NAT with no common relay peer), direct communication is impossible.
  This is a fundamental limitation of serverless P2P.

---

## Appendix C: Data Flow Diagrams

### C.1 Contact Exchange via QR Code

```
Alice (has peers)                    Bob (new, no peers)
  |                                    |
  |  [Displays QR: cleona://nodeId     |
  |   ?n=Alice&a=addrs&s=seedPeers]    |
  |                                    |
  |                            [Scans QR]
  |                                    |
  |                            [Connects to seed peer]
  |                            [Kademlia bootstrap]
  |                            [ROUTE_UPDATE to all]
  |                                    |
  |<--- CONTACT_REQUEST (signed) ------|
  |                                    |
  |  [Alice confirms]                  |
  |                                    |
  |--- CONTACT_REQUEST_RESPONSE ------>|
  |                                    |
  |<==== Encrypted communication =====>|
```

### C.2 Offline Message Delivery

```
Alice (online)          DHT Peers           Bob (offline)
  |                        |                    |
  | Encrypt message        |                    |
  | Reed-Solomon encode    |                    |
  |                        |                    |
  |-- Fragment 0 --------->| Peer A             |
  |-- Fragment 1 --------->| Peer B             |
  |   ...                  |  ...               |
  |-- Fragment 9 --------->| Peer J             |
  |                        |                    |
  |<-- ACK (stored) -------|                    |
  |                        |                    |
  |   [Status: STORED_IN_NETWORK]               |
  |                        |                    |
  |                        |       [Bob comes online]
  |                        |                    |
  |                        |<-- Startup poll ---|
  |                        |                    |
  |                        |--- Fragments ----->|
  |                        |                    |
  |                        |  [Reed-Solomon decode]
  |                        |  [Decrypt message]
  |                        |                    |
  |<-- DELIVERY_RECEIPT ---|----<from Bob>-------|
```

### C.3 Restore Broadcast

```
User enters 24-word phrase
  |
  v
Derive master seed
  |
  v
Derive Ed25519/X25519 keys (deterministic)
Generate fresh ML-KEM/ML-DSA keys
  |
  v
Join DHT with recovered Node-ID
  |
  v
Send signed RESTORE_BROADCAST to DHT
  |
  +---> Contact A: verifies signature, responds
  |       Phase 1: contact list + group info
  |       Phase 2: recent messages
  |       Phase 3: full history
  |
  +---> Contact B: responds similarly
  |
  +---> Contact C: offline (responds later)
  |
  v
Progressive state rebuild
```

---

*This document describes the architecture as of the current release. For
security disclosures, please see SECURITY.md.*
