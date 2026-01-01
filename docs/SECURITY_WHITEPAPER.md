# Cleona Chat -- Security Whitepaper

**Version 1.0 -- April 2026**
**Target audience:** Security researchers, cryptography auditors, protocol analysts

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Threat Model](#2-threat-model)
3. [Per-Message KEM: Stateless Hybrid Encryption](#3-per-message-kem-stateless-hybrid-encryption)
4. [Signature Scheme: Dual Classical + Post-Quantum](#4-signature-scheme-dual-classical--post-quantum)
5. [Key Derivation and Identity](#5-key-derivation-and-identity)
6. [Key Rotation](#6-key-rotation)
7. [Database Encryption](#7-database-encryption)
8. [Closed Network Model](#8-closed-network-model)
9. [Erasure Coding for Offline Delivery](#9-erasure-coding-for-offline-delivery)
10. [DoS Protection: Five-Layer Defense](#10-dos-protection-five-layer-defense)
11. [KEX Gate: Contact-Based Access Control](#11-kex-gate-contact-based-access-control)
12. [Call Encryption](#12-call-encryption)
13. [Routing Security](#13-routing-security)
14. [Content Moderation and Anti-Sybil](#14-content-moderation-and-anti-sybil)
15. [Recovery Security](#15-recovery-security)
16. [Known Limitations and Trade-offs](#16-known-limitations-and-trade-offs)
17. [Cryptographic Primitives Summary](#17-cryptographic-primitives-summary)

---

## 1. Introduction

Cleona is a fully decentralized peer-to-peer messenger with no central server, no
account registration, and no phone number or email requirement. Identity is purely
cryptographic. All communication is end-to-end encrypted using a hybrid
classical/post-quantum scheme designed to resist both current and future quantum
adversaries.

This document describes the cryptographic architecture and security properties of
Cleona in sufficient detail for independent audit. It covers the design rationale,
the specific algorithms used, the security guarantees provided, and the trade-offs
accepted.

### Design Philosophy

- **Zero trust in infrastructure.** There is no server to trust, no certificate
  authority, no DNS dependency. Every peer is untrusted until proven otherwise
  through cryptographic verification.
- **Post-quantum from day one.** All encryption and signature operations use hybrid
  classical + post-quantum schemes. Neither algorithm alone is relied upon.
- **Stateless encryption.** No session state is maintained between messages. Each
  message is an independent cryptographic operation. This eliminates an entire class
  of desynchronization bugs that plague ratchet-based protocols.
- **Minimal metadata.** The protocol is designed to minimize metadata leakage.
  Node identifiers are derived from public keys salted with a network secret,
  mailbox identifiers are uncorrelated to node identifiers, and there is no
  central directory to subpoena.

---

## 2. Threat Model

### Adversary Capabilities

Cleona's security model considers the following adversaries:

| Adversary | Capabilities | Mitigations |
|-----------|-------------|-------------|
| **Passive network observer** | Can observe all UDP traffic between nodes | Per-message encryption, no plaintext metadata in payloads |
| **Active network attacker** | Can inject, modify, drop packets | HMAC on every packet (Closed Network), dual signatures, PoW |
| **Quantum adversary (future)** | Can break X25519/Ed25519 with a cryptographically relevant quantum computer | ML-KEM-768 + ML-DSA-65 hybrid; both must be broken simultaneously |
| **Eclipse attacker** | Attempts to isolate a node by surrounding it with malicious peers | Closed Network Model (HMAC gate), Kademlia bucket diversity |
| **Sybil attacker** | Creates many fake identities to overwhelm voting/moderation | Social graph reachability check (Bloom filter, 5-hop walk), identity age requirements, activity thresholds |
| **DoS attacker** | Floods nodes with traffic or requests | Five-layer defense: PoW, rate limiting, reputation, fragment budgets, network banning |
| **Compromised device** | Attacker obtains a device with Cleona installed | Database encryption at rest (XSalsa20-Poly1305), platform keystore for key material |

### What Cleona Does NOT Protect Against

- **Endpoint compromise in real time.** If an attacker has live access to a
  device while Cleona is running, keys are in memory and messages are decrypted.
  This is inherent to any messaging system.
- **Traffic analysis at the network level.** While message contents are encrypted,
  an observer can see that two IP addresses are exchanging UDP packets. Cleona does
  not use onion routing or mixnets. Multi-hop relay provides some indirection but
  is not designed as an anonymity tool.
- **Binary extraction of network secret.** The Closed Network HMAC key is derivable
  from the binary. This is a known and accepted limitation (see Section 8).

### No Single Point of Compromise

Because there is no central server:

- There is no server database to breach.
- There is no TLS termination point where a government can install a wiretap.
- There is no company that can be compelled to hand over message history.
- Compromise of any single node reveals only that node's messages and keys.

---

## 3. Per-Message KEM: Stateless Hybrid Encryption

### Why Not Double Ratchet?

The Signal Protocol's Double Ratchet is the industry standard for end-to-end
encrypted messaging. Cleona deliberately does not use it. The reasons are
architectural:

1. **Statefulness.** Double Ratchet requires both parties to maintain synchronized
   session state (chain keys, message keys, header keys, skipped message indices).
   In a decentralized P2P network with unreliable connectivity, multi-hop relay,
   store-and-forward delivery, and multi-device support, state synchronization is
   fragile. A single lost or reordered message can desynchronize a session,
   requiring complex recovery mechanisms.

2. **Multi-identity complexity.** Cleona supports multiple identities per device
   via an HD wallet. Each identity communicates independently. Maintaining ratchet
   sessions for N identities times M contacts times D devices creates a
   combinatorial explosion of session state.

3. **Offline delivery via third parties.** Messages may be stored on mutual peers
   or erasure-coded across DHT nodes for days. The recipient may recover these
   messages out of order, from fragments, via multiple routes. Ratchet protocols
   assume roughly ordered delivery.

4. **Simplicity.** A stateless design eliminates entire categories of bugs:
   session desync, stuck ratchets, key mismatch after restore, session reset
   attacks. Every message is self-contained.

### The Per-Message KEM Construction

For each message, the sender performs a fresh key encapsulation:

```
SEND(Alice -> Bob):
  1. Generate ephemeral X25519 keypair: (eph_sk, eph_pk)
  2. Classical DH:  dh_secret = X25519(eph_sk, bob_x25519_pk)
  3. Post-quantum:  (kem_ct, kem_secret) = ML-KEM-768.Encapsulate(bob_ml_kem_pk)
  4. Key derivation: msg_key = HKDF-SHA256(dh_secret || kem_secret, "cleona-msg-v1")
  5. Encrypt:       ciphertext = AES-256-GCM(msg_key, nonce, plaintext)
  6. Transmit:      [eph_pk (32B) | kem_ct (1088B) | nonce (12B) | ciphertext]
  7. Destroy:       eph_sk is immediately zeroed from memory

RECEIVE(Bob):
  1. Classical DH:  dh_secret = X25519(bob_x25519_sk, eph_pk)
  2. Post-quantum:  kem_secret = ML-KEM-768.Decapsulate(bob_ml_kem_sk, kem_ct)
  3. Key derivation: msg_key = HKDF-SHA256(dh_secret || kem_secret, "cleona-msg-v1")
  4. Decrypt:       plaintext = AES-256-GCM.Decrypt(msg_key, nonce, ciphertext)
```

### Security Properties

- **Hybrid security.** The message key depends on both `dh_secret` and `kem_secret`.
  An attacker must break both X25519 AND ML-KEM-768 to recover the message key.
  If either primitive holds, the message remains confidential.
- **Per-message forward secrecy.** Each message uses a fresh ephemeral keypair.
  Compromise of the sender's long-term keys does not reveal past messages (the
  ephemeral secret keys are destroyed immediately after use). However, compromise
  of the *recipient's* long-term keys allows decryption of past messages -- this
  is the inherent trade-off of not using a ratchet.
- **No session state to corrupt.** There is no state to desynchronize, no ratchet
  to get stuck, no session to reset.

### Overhead

Each message carries approximately 1,132 bytes of KEM overhead:
- 32 bytes: ephemeral X25519 public key
- 1,088 bytes: ML-KEM-768 ciphertext
- 12 bytes: AES-256-GCM nonce

For a typical text message of 100-500 bytes, this represents 2-11x overhead.
For media messages of 10KB+, the overhead is negligible. The trade-off is
acceptable: zero state management in exchange for approximately 1.1KB per message.

### Exceptions

Two message types are NOT encrypted with Per-Message KEM:

- **RESTORE_BROADCAST / RESTORE_RESPONSE** -- Only signed (Ed25519 + ML-DSA-65).
  These are sent during identity recovery when the recipient may not yet have
  the sender's new KEM public keys.
- **CONTACT_REQUEST / CONTACT_REQUEST_RESPONSE** -- Only signed. These establish
  the initial key exchange; KEM encryption is not yet possible because the
  parties do not yet have each other's public keys.

---

## 4. Signature Scheme: Dual Classical + Post-Quantum

Every message in Cleona carries two independent signatures:

1. **Ed25519** (classical, 64-byte signature)
2. **ML-DSA-65** (post-quantum, NIST FIPS 204, ~3,309-byte signature)

Both signatures must verify for the message to be accepted. A message with a valid
Ed25519 signature but invalid ML-DSA-65 signature (or vice versa) is rejected.

### Rationale for Dual Signatures

- **Hedge against algorithm failure.** If a practical attack is found against
  ML-DSA-65 (the algorithm is relatively new), Ed25519 still provides authentication.
  If a quantum computer breaks Ed25519, ML-DSA-65 still provides authentication.
- **No migration path needed.** Because both are always present, there is no
  flag day when the protocol must switch from one to the other.

### Signature Scope

Signatures cover:

- **Message authentication:** Every application message (TEXT, IMAGE, GROUP_INVITE,
  etc.) is dual-signed by the sender.
- **Donation address verification:** The donation screen displays a cryptographic
  address whose authenticity is verifiable via Ed25519 signature.
- **Update manifests:** Software update manifests distributed via DHT are signed
  with a maintainer Ed25519 key. Nodes verify the signature before presenting an
  update notification.
- **Restore broadcasts:** Recovery messages are signed with the Ed25519 key
  (which is deterministically derived and therefore identical before and after
  recovery).

### Stale Key Handling

If signature verification fails due to a key mismatch (e.g., the sender has rotated
keys and the recipient has a stale cached copy), the cached key is evicted. The
message is not immediately rejected -- the system allows re-verification with
updated keys obtained through the key rotation protocol.

---

## 5. Key Derivation and Identity

### HD Wallet Architecture

Cleona uses a hierarchical deterministic (HD) wallet structure for key derivation:

```
24-word seed phrase (264 bits: 256 entropy + 8 checksum)
    |
    v
Master Seed = SHA-256("cleona-master-seed-v1" || entropy)
    |
    +---> Identity 0: Ed25519 keys via HKDF-SHA256("cleona-ed25519-0", master_seed)
    |         |
    |         +---> X25519 keys: ed25519PkToX25519(ed25519_pk)
    |         +---> ML-KEM-768 keys: independently generated (NOT deterministic)
    |         +---> ML-DSA-65 keys: independently generated (NOT deterministic)
    |
    +---> Identity 1: Ed25519 keys via HKDF-SHA256("cleona-ed25519-1", master_seed)
    |         ...
    +---> Identity N: ...
```

**Critical detail:** Only Ed25519 keys are deterministically derivable from the
seed phrase. Post-quantum keys (ML-KEM-768, ML-DSA-65) are NOT deterministically
derivable because the underlying algorithms use internal randomness during key
generation. After a recovery from seed phrase, post-quantum keys are regenerated
and distributed to contacts via the Restore Broadcast protocol.

### Seed Phrase

- 24 words from a custom 2,048-word list
- Words are phonetically distinct (indices 0-1215: CVCV 4-letter, 1216-2047: CVCVC 5-letter)
- 256 bits of entropy, 8-bit checksum
- Stored encrypted on device: `seed_phrase.json.enc` (XSalsa20-Poly1305)

### Node-ID Derivation

```
Node-ID = SHA-256(network_secret || ed25519_public_key)
```

The Node-ID serves as the peer's address in the Kademlia DHT (256-bit, 256
k-buckets). It is NOT the raw public key. The `network_secret` prefix ensures
that the same public key produces different Node-IDs on different network
instances, preventing cross-network identity correlation.

### Mailbox-ID Derivation

```
Mailbox-ID = SHA-256("mailbox" || ed25519_public_key)
```

The Mailbox-ID determines where store-and-forward fragments and erasure-coded
pieces are stored in the DHT. It uses a different derivation than the Node-ID
to prevent an observer from correlating a node's network address with its
offline storage location.

**Why the separation matters:** If Node-ID and Mailbox-ID were correlated, an
attacker who knows a peer's Node-ID (visible in routing) could determine the
DHT region where that peer's offline messages are stored, enabling targeted
denial of service against the storage nodes or traffic analysis of delivery
patterns.

### Key Storage

| Platform | Storage Mechanism |
|----------|-------------------|
| Android  | Android Keystore (hardware-backed when available) |
| iOS      | Secure Enclave / Keychain |
| Linux    | `keys.json` encrypted with Argon2id + XSalsa20-Poly1305 |
| Windows  | `keys.json` encrypted with Argon2id + XSalsa20-Poly1305 |

---

## 6. Key Rotation

KEM keys (X25519 and ML-KEM-768) are rotated weekly by default. Identity signing
keys (Ed25519 and ML-DSA-65) are NOT rotated -- they are the stable identity
anchors.

### Rotation Protocol

1. Node generates fresh X25519 and ML-KEM-768 keypairs.
2. A `KEY_ROTATION` message is sent to all accepted contacts, containing:
   - New X25519 public key
   - New ML-KEM-768 public key
   - Rotation timestamp
   - Signature (Ed25519 + ML-DSA-65, proving the identity owner authorized the rotation)
3. The old private keys are retained for 7 days as a decrypt fallback for
   messages that were in transit during rotation.
4. Recipients update their stored contact keys and any group/channel member keys.

### Rotation Triggers

- **Scheduled:** Weekly (configurable).
- **Immediate:** On suspicion of key compromise (manual trigger).

New X25519 keys are independently generated, not derived from Ed25519. This
ensures that compromise of the derivation path does not affect rotated keys.

---

## 7. Database Encryption

All local message storage is encrypted at rest.

### Construction

```
db_key = SHA-256(ed25519_private_key[0:32] || "cleona-db-key-v1")
```

The database key is derived from the identity's Ed25519 private key, meaning:

- Each identity has a unique database encryption key.
- The key is never stored separately -- it is re-derived at startup from the
  identity key material.
- Loss of the identity keys means loss of the database (by design).

### Encryption

- **Algorithm:** XSalsa20-Poly1305 (libsodium)
- **Format:** `cleona.db.enc` = `[24-byte nonce][ciphertext]`
- **Operation:** SQLite operates on a decrypted temporary file. The encrypted
  file is flushed every 60 seconds and on shutdown.
- **Migration:** Unencrypted databases from older versions are automatically
  migrated to encrypted format on first startup.

### Limitations

The decrypted temporary SQLite file exists in memory/temp storage while Cleona
is running. An attacker with live access to the process's memory or filesystem
can read it. This is an inherent limitation of the approach -- full disk-level
encryption (e.g., SQLCipher) would add a native dependency for marginal gain,
since an attacker with live process access can read decrypted messages from
memory regardless.

---

## 8. Closed Network Model

Cleona operates as a closed network. Unauthorized nodes cannot participate in
any protocol operations.

### HMAC Gate

Every UDP packet carries an HMAC computed over the packet payload:

```
hmac = HMAC-SHA256(network_secret, packet_payload)
```

Packets with invalid or missing HMACs are silently dropped at the transport
layer, before any Protobuf parsing occurs. This means:

- Unauthorized nodes cannot send valid DHT queries.
- Unauthorized nodes cannot inject routing updates.
- Unauthorized nodes cannot store fragments on legitimate nodes.
- Port scanners see an unresponsive UDP port.

### Network Secret Derivation

The `network_secret` is derived from a maintainer Ed25519 key that is compiled
into the binary:

```
network_secret = SHA-256(maintainer_ed25519_public_key || "cleona-network-v1")
```

### Known Limitation: Binary Extraction

The `network_secret` can be extracted by reverse-engineering the binary. This is
a deliberate and accepted trade-off:

- **What it prevents:** Casual attackers, port scanners, automated probes, and
  botnets cannot interact with the network.
- **What it does NOT prevent:** A motivated reverse engineer who decompiles the
  binary can extract the secret and craft valid packets.
- **Why this is acceptable:** The HMAC gate is Layer 0 defense (noise reduction).
  The real security comes from per-message encryption, signature verification,
  KEX Gate (Section 11), and the DoS protection stack (Section 10). Even with a
  valid HMAC, an attacker cannot read messages, forge signatures, or bypass the
  contact requirement.

### Secret Rotation

A Secret Rotation Framework exists for changing the network secret. When rotated,
nodes accept both old and new secrets during a transition period.

---

## 9. Erasure Coding for Offline Delivery

When the recipient of a message is offline, Cleona uses a two-tier offline
delivery system:

### Tier 1: Store-and-Forward

Complete copies of the encrypted message are stored on up to 3 mutual peers
(contacts or group members shared between sender and recipient). These peers
forward the message when the recipient comes online.

### Tier 2: Reed-Solomon Erasure Coding

The encrypted message is split into N=10 fragments using Reed-Solomon coding.
Any K=7 fragments are sufficient to reconstruct the original message.

```
Overhead:     1.43x (10/7)
Redundancy:   3 of 10 fragments can be lost and the message is still recoverable
Distribution: Fragments placed on DHT peers close to recipient's Mailbox-ID
              (XOR distance in Kademlia space)
Copy limit:   Max 5 copies per fragment in the network
TTL:          7 days
```

### Security Properties

- Fragments are encrypted before erasure coding. Each fragment is a piece of
  AES-256-GCM ciphertext. A node storing fragments cannot read the message
  content even with all 10 fragments.
- The Mailbox-ID (where fragments are stored) is uncorrelated to the Node-ID
  (where the recipient operates in the DHT), preventing storage-to-identity
  linkage.
- Fragment cleanup: After successful reconstruction, `FRAGMENT_DELETE` messages
  are sent to all storage peers to remove the fragments.

### Small Network Behavior

In networks with fewer than 10 peers, the system uses round-robin distribution
and the sender retains all fragments until delivery is confirmed.

---

## 10. DoS Protection: Five-Layer Defense

### Layer 1: Proof of Work

Every application-level message carries a SHA-256 Hashcash proof of work:

```
Target:     SHA-256(signed_envelope_bytes || nonce_8LE) must have 20 leading zero bits
Difficulty: 20 (approximately 2^20 hashes, ~50-100ms on desktop hardware)
Scope:      Application messages only (TEXT, GROUP_INVITE, etc.)
Exempt:     DHT protocol messages (PING, PONG, FIND_NODE), relay infrastructure
```

Messages with invalid PoW are silently discarded.

### Layer 2: Per-Node Rate Limiting

Each node enforces rate limits on incoming messages per source Node-ID. Relay
traffic (RELAY_FORWARD, RELAY_ACK) is exempt from rate limiting because relay
nodes process traffic on behalf of others.

### Layer 3: Reputation System

Nodes maintain a reputation score for peers based on observed behavior:

- **Good actions:** All accepted packets (valid HMAC, valid PoW, valid signatures)
  increment the sender's reputation.
- **Bad actions:** Invalid packets, rate limit violations, and protocol violations
  decrement reputation.
- **Effect:** Peers with low reputation have their traffic deprioritized or dropped.

### Layer 4: Fragment Storage Budgets

Each node enforces storage limits on DHT fragment storage to prevent storage
exhaustion attacks:

- Platform-specific budgets (100MB-2GB)
- Per-sender limits within the global budget
- Oldest fragments are evicted when budget is exceeded

### Layer 5: Network Banning

Nodes that consistently exhibit malicious behavior (sustained rate violations,
repeated invalid packets) are banned at the transport layer. Banned Node-IDs
have all their packets dropped before processing.

---

## 11. KEX Gate: Contact-Based Access Control

The KEX Gate is a fundamental anti-spam mechanism: encrypted messages from unknown
senders are silently dropped.

### How It Works

When an encrypted message arrives, the recipient checks:

1. Is `sender_id` in my accepted contacts list?
2. Is `sender_id` a member of any group I belong to?
3. Is `sender_id` a subscriber/admin/owner of any channel I belong to?

If none of these conditions are true, the message is discarded without any
response (no error, no reject -- complete silence).

### Why Silent Drop

Sending any response to an unknown sender would:

- Confirm that the recipient exists at this Node-ID (presence leakage).
- Enable enumeration attacks (probe Node-IDs and see which ones respond).
- Provide a side channel for traffic analysis.

Silent drop reveals nothing to the attacker.

### Establishing Contact

To communicate with a new person, you must first establish contact through an
authenticated channel:

| Method | Verification Level | Description |
|--------|-------------------|-------------|
| QR code scan | Verified (Level 3) | In-person scan, includes public keys + seed peers |
| NFC tap | Verified (Level 3) | Physical proximity required |
| ContactSeed URI | Seen (Level 2) | `cleona://` URI shared via any channel |
| Node-ID hex | Unverified (Level 1) | Manual entry of 64-character hex string |

Contact requests themselves are NOT KEM-encrypted (they cannot be, since the
parties don't have each other's KEM public keys yet). They are signed with
Ed25519 + ML-DSA-65 and rate-limited (1 per 20 seconds) with PoW.

### Contact Verification Levels

| Level | Name | How Achieved | Trust |
|-------|------|-------------|-------|
| 1 | Unverified | Node-ID or ContactSeed URI | Keys received over potentially insecure channel |
| 2 | Seen | Successful key exchange | Keys confirmed via cryptographic handshake |
| 3 | Verified | QR or NFC in person | Physical verification of key material |
| 4 | Trusted | Explicit user action | User has manually marked this contact as trusted |

---

## 12. Call Encryption

### 1:1 Calls

Call setup uses a bilateral ephemeral key exchange:

```
Alice -> Bob: CALL_INVITE(call_id, eph_x25519_pk_a, kem_ciphertext_a, is_video)
Bob -> Alice: CALL_ANSWER(eph_x25519_pk_b, kem_ciphertext_b)

Both compute:
  dh_a = X25519(own_eph_sk, peer_eph_pk)
  dh_b = X25519(own_eph_sk, peer_eph_pk)
  kem_secret_a = ML-KEM-768.Decapsulate(own_sk, peer_kem_ct)
  kem_secret_b = ML-KEM-768.Decapsulate(own_sk, peer_kem_ct)

  call_key = HKDF-SHA256(dh_a || dh_b || kem_secret_a || kem_secret_b, "cleona-call-v1")
```

- **Forward secrecy:** Ephemeral keys exist only in RAM during the call. They are
  never persisted. After hangup, the call key is irrecoverable.
- **Audio frames:** Each 20ms Opus frame is encrypted with AES-256-GCM using the
  call key. Frame format: `[4B seqNum][12B nonce][ciphertext + 16B GCM-tag]`.
- **Video frames:** VP8 frames encrypted identically.
- **Signaling:** CALL_INVITE, CALL_ANSWER, CALL_REJECT, CALL_HANGUP are sent
  as regular Per-Message KEM-encrypted messages through the standard message
  delivery path.

### Group Calls

- The call initiator generates a `call_key` and distributes it to each participant
  individually via Per-Message KEM encryption.
- **Key rotation:** Triggered when a participant is kicked or a new participant
  joins. NOT triggered on crash-and-rejoin (to avoid disruption).
- **Audio mixing:** Each node mixes received audio streams locally (no central
  mixer).
- **Media distribution:** Overlay Multicast Tree (RTT-based, degree-constrained
  minimum spanning tree) for efficient media distribution. LAN participants use
  IPv6 multicast (`ff02::cleona:call`) to avoid redundant transmissions.

---

## 13. Routing Security

### Distance-Vector Routing with Security Extensions

Cleona uses a Bellman-Ford distance-vector routing protocol inspired by RIP, with
security hardening for a P2P adversarial environment:

- **Split Horizon + Poison Reverse:** Standard loop prevention. A node never
  advertises a route back to the neighbor it learned it from.
- **TTL = 64:** Each relay hop decrements TTL. Packets reaching TTL=0 are
  discarded, preventing routing loops from causing infinite forwarding.
- **ACK-based route liveness:** Routes are declared DOWN after 3 consecutive
  DELIVERY_RECEIPT timeouts. There is no timer-based expiry -- only failure to
  deliver kills a route. This prevents healthy routes from being spuriously
  expired.
- **Route poisoning:** When a route goes DOWN, the node advertises it to
  neighbors with infinite cost (Poison Reverse), ensuring rapid network-wide
  convergence.

### Relay Security

Multi-hop relay preserves the original encrypted envelope intact:

```
RELAY_FORWARD {
  relay_id:       unique ID for loop detection
  original_envelope: [encrypted, signed, PoW-valid blob]
  visited_nodes:  list of Node-IDs this packet has traversed
  ttl:            decremented each hop
}
```

- Relay nodes cannot read message contents (they only see encrypted ciphertext).
- Relay nodes cannot modify the message (dual signatures are verified by the
  final recipient on the original envelope).
- **Loop prevention** uses three layers: relay_id deduplication cache (10,000
  LRU entries), visited_nodes list, and TTL decrement.
- **Relay budget:** 1 MB/min total, 256 KB/min per source node, 50 messages/min,
  max 64 KB per payload. Prevents relay abuse.

### NAT Traversal

- **Decentralized STUN:** Peers report observed public IP to each other. Minimum
  2 confirmations required before a public IP is accepted (prevents single-peer
  spoofing).
- **Active UDP hole punching:** Coordinated via a third-party node
  (HolePunchRequest/Notify protocol).
- **NAT timeout probing:** Dynamically discovers the NAT mapping lifetime per
  connection (15s -> 30s -> 60s -> ...) and sets keepalive to 80% of the
  discovered timeout.

---

## 14. Content Moderation and Anti-Sybil

Public channels use a decentralized jury-based moderation system. The anti-Sybil
measures are relevant to security researchers.

### Social Graph Reachability Check

To prevent Sybil attacks (bot farms creating fake identities to coordinate false
reports), Cleona validates the social graph embedding of reporters:

1. A report is distributed to K random validator nodes in the DHT.
2. Each validator checks: "Can I reach this identity within 5 hops through my
   social graph?"
3. If >= 60% of validators can reach the reporter, the report is accepted.
4. If < 60%, the report is rejected ("identity not sufficiently connected").

### Privacy Preservation

- Each node maintains a Bloom filter of contacts up to depth 5.
- Reachability is a local lookup, not a network graph traversal.
- The answer is binary (reachable/not-reachable) -- no path information is leaked.
- Bloom filters are periodically refreshed.

### Why This Resists Sybil

Real social graphs exhibit small-world properties (any two people connected
within ~6 hops). Bot clusters form isolated islands with no bridges to the
real social graph. An attacker faces a dilemma:

- Connect bots only to each other: isolated cluster, detected.
- Connect bots to real people: does not scale (real people must actively accept).
- Create a "bridge" account to the real graph: connects the entire cluster,
  triggering size-based independence thresholds.

---

## 15. Recovery Security

### Seed Phrase Recovery

The 24-word seed phrase reconstructs only the Ed25519 identity keys
(deterministic). Post-quantum keys (ML-KEM-768, ML-DSA-65) are regenerated
fresh, because these algorithms use internal randomness during key generation
that cannot be reproduced from a seed.

### Restore Broadcast Security

After recovery, the node sends a `RESTORE_BROADCAST` signed with its Ed25519
key (which is identical before and after recovery, since it is deterministically
derived):

1. Each contact verifies: "Is `old_node_id` in my contact list?"
2. Each contact verifies the Ed25519 signature against the stored public key.
3. On success, the contact updates the node's post-quantum keys and responds
   with contact lists, group memberships, and message history.

**Rate limiting:** Max 1 restore broadcast per identity per 5 minutes.

### Shamir Secret Sharing (Social Recovery)

As an alternative to seed phrases, Cleona supports Shamir's Secret Sharing:

- **Scheme:** 3-of-5 threshold over GF(256) with irreducible polynomial 0x11B
  (the AES field polynomial).
- **Shares:** Distributed to 5 trusted guardians.
- **Security:** Any 2 or fewer shares reveal zero information about the master
  seed (information-theoretic security).
- **Recovery:** Any 3 guardians can reconstruct the master seed via Lagrange
  interpolation.

### DHT Identity Registry

Multi-identity mappings are stored in the DHT for cross-device recovery:

```
Registry-ID = SHA-256("identity-registry" || master_public_key)
Encryption-Key = SHA-256(master_seed || "cleona-registry-key")
```

The registry payload is encrypted with XSalsa20-Poly1305 and erasure-coded
(N=10, K=7). Only the master seed holder can decrypt and update it.

---

## 16. Known Limitations and Trade-offs

### No Per-Session Forward Secrecy Against Recipient Key Compromise

Because Cleona uses per-message KEM rather than a ratchet, compromise of a
recipient's long-term KEM private key allows decryption of all past messages
encrypted to that key. Weekly key rotation limits the exposure window: only
messages encrypted since the last rotation (plus a 7-day overlap) are at risk.

This is the fundamental trade-off for stateless encryption. In a ratchet protocol,
forward secrecy is achieved through chain key advancement -- but at the cost of
statefulness and all its associated complexity in a P2P environment.

### Network Secret Extractable from Binary

As discussed in Section 8, the HMAC network secret can be extracted through
reverse engineering. This is accepted because the HMAC gate is a noise reduction
layer, not the primary security boundary.

### ML-KEM and ML-DSA Maturity

ML-KEM-768 and ML-DSA-65 are NIST post-quantum standards (FIPS 203 and FIPS 204).
They are relatively new compared to Ed25519 and X25519. The hybrid approach
mitigates this: if a practical attack is found against the post-quantum primitives,
the classical primitives still provide security. The reverse is also true.

### Post-Quantum Keys Not Deterministic

ML-KEM-768 and ML-DSA-65 key generation uses internal randomness and cannot be
deterministically reproduced from a seed phrase. After recovery, these keys are
regenerated and distributed via Restore Broadcast. This means a brief window
exists after recovery where contacts have stale post-quantum keys. Messages
encrypted with stale keys can still be decrypted for 7 days (overlap window).

### Metadata Leakage

While message contents are encrypted, the following metadata may be observable:

- **IP addresses** of communicating peers (visible to network observers).
- **Timing** of message exchanges (traffic analysis).
- **Message sizes** (though compression and padding partially obscure this).
- **DHT query patterns** (which nodes are being looked up).

Cleona does not use onion routing. Multi-hop relay provides incidental routing
indirection but is not designed or analyzed as an anonymity mechanism.

### Group Encryption: Pairwise Fan-out

Group messages are individually encrypted to each member via Per-Message KEM.
This means sending a message to a group of N members requires N separate
encryption operations and N separate network transmissions. This is O(N) in
computation and bandwidth, which limits practical group sizes. The benefit is
that there is no shared group key that, if compromised, would expose all group
messages.

---

## 17. Cryptographic Primitives Summary

| Purpose | Algorithm | Standard | Key/Output Size | Library |
|---------|-----------|----------|-----------------|---------|
| Identity signatures (classical) | Ed25519 | RFC 8032 | 32B pubkey, 64B signature | libsodium |
| Identity signatures (post-quantum) | ML-DSA-65 | FIPS 204 | 4,595B pubkey, ~3,309B signature | liboqs |
| Key encapsulation (classical) | X25519 | RFC 7748 | 32B pubkey, 32B shared secret | libsodium |
| Key encapsulation (post-quantum) | ML-KEM-768 | FIPS 203 | 1,184B pubkey, 1,088B ciphertext | liboqs |
| Symmetric encryption (messages) | AES-256-GCM | NIST SP 800-38D | 256-bit key, 12B nonce, 16B tag | libsodium |
| Symmetric encryption (database) | XSalsa20-Poly1305 | NaCl | 256-bit key, 24B nonce, 16B tag | libsodium |
| Key derivation | HKDF-SHA256 | RFC 5869 | Variable | libsodium |
| Password hashing | Argon2id | RFC 9106 | Variable | libsodium |
| Proof of work | SHA-256 Hashcash | -- | 20 leading zero bits | dart:crypto |
| Erasure coding | Reed-Solomon | -- | N=10, K=7 | liberasurecode |
| Compression | zstd | RFC 8878 | -- | libzstd |
| Network HMAC | HMAC-SHA256 | RFC 2104 | 256-bit key | libsodium |
| Secret sharing | Shamir SSS over GF(256) | -- | 3-of-5 threshold | custom (0x11B polynomial) |

---

## Message Processing Pipeline

For reference, the complete outbound and inbound processing pipelines:

### Outbound

```
Application Payload (Protobuf)
  |-- Serialize to bytes
  |-- Compress (zstd)
  |-- Encrypt (Per-Message KEM: X25519 + ML-KEM-768 -> HKDF -> AES-256-GCM)
  |-- Sign (Ed25519 + ML-DSA-65, both over the encrypted payload)
  |-- Proof of Work (SHA-256, difficulty 20)
  |-- Erasure Code (if offline delivery path: Reed-Solomon N=10 K=7)
  |-- HMAC (network secret, applied at transport layer)
  |-- Fragment (if >1200 bytes: app-level UDP fragmentation)
  |-- Send (UDP)
```

### Inbound

```
Receive (UDP)
  |-- Reassemble fragments (if fragmented)
  |-- Verify HMAC (network secret; drop silently on failure)
  |-- Verify Proof of Work (drop silently on failure)
  |-- Verify Ed25519 signature (drop on failure)
  |-- Verify ML-DSA-65 signature (drop on failure)
  |-- Reconstruct from erasure fragments (if applicable)
  |-- Deduplicate (message_id check, before decryption)
  |-- KEX Gate check (is sender a known contact? drop silently if not)
  |-- Decrypt (Per-Message KEM: X25519 + ML-KEM-768 -> HKDF -> AES-256-GCM)
  |-- Decompress (zstd)
  |-- Deserialize (Protobuf)
  |-- Deliver to application layer
```

---

*This document describes the cryptographic architecture of Cleona Chat as of
version 3.1.42. For implementation details, consult the source code in the
`lib/core/crypto/`, `lib/core/network/`, and `lib/core/service/` directories.*
