# CLEONA CHAT

## Architecture & Technical Specification — v3.0

**Status:** v3.0 Major Architecture Refactor (2026-05-01+)
**Predecessor:** [`Cleona_Chat_Architecture_v2_2.md`](Cleona_Chat_Architecture_v2_2.md) — DEPRECATED, see §23 (Migration) for cross-walk

**v3.0 key features:**
- **2-layer wire format**: Outer Frame (routing, device-signed) wraps Inner Frame (identity, KEM-encrypted)
- **Clear API separation**: `service.sendToUser(userId)` for identity addressing, `node.sendToDevice(deviceId)` for pure routing
- **Privacy improvement**: relays no longer see UserIDs — only device-to-device topology

<!-- AUTO-GENERATED from Cleona_Chat_Architecture_v3_0.md (sha256:1cc94662a5d8, 2026-06-04). -->
<!-- Edits to this file will be overwritten. Edit the master in Cleona/. -->

- **Default-Gateway resilience**: re-enabled as a routing-layer fallback when the DV routing table does not know the target device
- **MessageQueue retired**: when "routes exhausted" the sender stops; S&F + mailbox pull take over offline delivery
- **Onion-routing hook**: Outer-Frame format prepared for later multi-layer encryption, not active in V3.0
- **Hard cut**: wire format and profile format incompatible with v2.2 — profile reset on upgrade

---

## Table of Contents

1. Executive Summary
2. Wire-Format & Layered Frames
3. Identity & Cryptography
4. Network Architecture
5. Message Delivery
6. Identity Recovery
7. Multi-Device Support
8. Identity-Authorization Protocols
9. Group Features (Channels, Moderation)
10. Calls
11. Calendar & Polls
12. Synchronization Strategy
13. Network Resilience
14. Storage & Data Management
15. Application Architecture
16. Permissions & Privacy
17. Internationalization
18. Network Statistics Dashboard
19. Licensing, Funding & Donation
20. Tech Stack
21. Testing Strategy
22. Development Environment
23. V2.2 → V3.0 Migration
24. Roadmap

Appendix A. Protocol Message Format (Wire Definitions)
Appendix B. Frame Examples (Hex Dumps)
Appendix C. V2.2 → V3.0 Section Cross-Walk

---
## 1. Executive Summary

Cleona Chat is a decentralized peer-to-peer messenger with no central servers, built on a Kademlia DHT topology with closed-network authentication. Security model: hybrid post-quantum cryptography (X25519+ML-KEM-768 for encryption, Ed25519+ML-DSA-65 for signatures). Identity model: cryptographic (no phone-number or email binding), multi-identity per device, multi-device per identity. Recovery via a 24-word phrase plus Restore Broadcast to contacts (no central server-side restore). Implementation: Flutter/Dart, target platforms Linux Desktop, Windows Desktop, Android, iOS.

V3.0 is an architectural hard cut against v2.2. The wire-format architecture has been changed from a flat `MessageEnvelope` to a 2-layer frame structure (see §2), the API layer has been split from an overloaded `sendEnvelope` into two clearly separated operations `sendToUser`/`sendToDevice` (see §15.3), and several structural weaknesses have been eliminated (MessageQueue carry-over, ID-type mismatch, missing routing-layer fallback). V3.0 nodes are not backwards-compatible with v2.2 — profile reset on upgrade.

### 1.1 Core Principles

These principles are non-negotiable and govern all architectural decisions:

1. **Full decentralization.** No central server, no central database, no central account directory. Every node is equal. Bootstrap nodes are only accelerators for initial mesh discovery; a Cleona network also works without them once enough peers know each other.

2. **Closed Network Model.** Only official Cleona builds participate in the network. Every UDP packet carries an HMAC with a `network_secret` derived from the maintainer key. Forks without the secret see no one and are seen by no one — not for anti-competition reasons but for security (anti-Sybil, anti-pollution, spam resistance). See §4.10.

3. **Post-quantum security from day one.** Hybrid encryption X25519+ML-KEM-768 for every message (stateless, no Double Ratchet). Hybrid signatures Ed25519+ML-DSA-65 for identity authentication. Even if a quantum computer breaks one of the two layers in 10 years, the other remains intact. See §3.

4. **Cryptographic identity.** An identity is a key pair plus an optional display name. No email, no phone number, no address verification. Recovery is performed via a 24-word phrase (BIP-39 style) and/or Restore Broadcast to verified contacts. See §6.

5. **Layered trust boundaries.** The routing layer and the identity layer have separate trust models (see §2.1). This separation prevents cross-layer spoofing and makes multi-identity daemons privacy-consistent toward relays.

6. **Stateless E2E encryption.** Every message carries its own KEM setup. No session state, no desync risk, no loss of forward secrecy through state corruption. See §3.3.

7. **Minimal network traffic.** Push-first for mailbox delivery, no polling except at startup. Auth-Manifest refresh every 20 h, liveness adaptive 15 min/1 h. DV-routing updates are event-driven (Bellman-Ford), not periodic. See §5 for delivery paths, §12 for synchronization strategy.

8. **Resilience at every layer.** When the primary path fails, there is a fallback. Direct → Relay → Default-Gateway → S&F + mailbox pull. Hard cuts without a fallback have been identified as an anti-pattern in v2.2 and are strictly avoided in v3.0. See §5.1.

9. **Decentralized moderation for public channels.** No central moderation authority. Reports are decided by juries of 5–11 randomly chosen nodes, with anti-Sybil protection via social-graph reachability. See §9.3, §9.4.

10. **Cross-platform consistency.** One Dart codebase, one wire format, identical crypto paths on all platforms. Platform specifics (Android Foreground Service, Linux tray, macOS bundle) are UI/lifecycle adaptations, not architectural variations. See §15.2.

11. **Complete i18n, no EN fallback in the code pipeline.** Every new i18n key exists in all 33 locales before it is referenced in UI code. The linter `dart scripts/check_i18n_complete.dart` is an exit-1 gate before commit. The runtime fallback EN→DE→key exists only as defence in depth. See §17.

### 1.2 V3.0 Architecture Highlights

V3.0 changes several fundamental structures compared to v2.2. The changes are not incremental — they are a deliberate reset to eliminate structural weaknesses that had become invisible through accumulated patches in v2.2.

**1. 2-layer frame architecture** (§2). An Outer Frame (NetworkPacket) carries only routing information (DeviceID-to-DeviceID, TTL, hopCount) and a device signature. An Inner Frame (ApplicationFrame) carries identity information (UserID-to-UserID), MessageType, payload, and user signature. The Inner Frame is KEM-encrypted and opaque to relays. As a result, relays no longer see UserIDs — a structural privacy improvement for multi-identity daemons.

**2. Clear service API separation** (§15.3). `service.sendToUser(envelope, userId)` performs identity resolution + multi-device fanout. `node.sendToDevice(packet, deviceId)` performs a pure routing operation. The v2.2 API `sendEnvelope(envelope, recipientNodeId)`, with its overloaded, type-undifferentiated identifier parameter, no longer exists. As a result, the v2.2 ID-type mismatch issue (userId vs. deviceNodeId) is structurally excluded.

**3. Default-Gateway as routing-layer fallback** (§5.1, §4.4). v2.2 explicitly removed the Default-Gateway fallback from the send path ("hard cut, bundled with Sec H-5 KEM v2") and replaced it with identity resolution alone — which resulted in five parallel fragile conditions for a successful send. V3.0 restores the Default-Gateway as a clean routing-layer last resort, without weakening the 2D-DHT resolver. The resolver remains the fast path; the Default-Gateway is the resilience tier.

**4. MessageQueue retired** (§5.5, §5.6). v2.2 held failed sends for 7 days in a local MessageQueue and retried periodically — often with the same (potentially wrong) ID that had already failed on the first attempt. V3.0 removes the MessageQueue entirely: when "all routes exhausted" the sender stops, S&F (erasure-coded on mutual peers) plus mailbox pull (the receiver pulls upon coming online) take over offline delivery. There is no longer any sender-side retry.

**5. Onion-routing hook prepared, not active** (§2.5). The Outer-Frame format has a `payloadType` discriminator: `payload` can be an ApplicationFrame (V3.0 default) or a nested NetworkPacket (onion layer). This makes multi-hop onion routing activatable in a later version **without another hard break**. V3.0 implements only 1 hop. When activation occurs later, a taboo list is firmly planned: live calls, DHT infrastructure, hole punch, routing updates must never traverse onion layers — latency and functionality forbid it.

**6. Device-Sig keypair as its own crypto-subject class** (§3.5). User identities have user-sig keys (Ed25519+ML-DSA-65 hybrid). In addition, every device has its own sig keypair (Ed25519+ML-DSA-65 hybrid for application frames, Ed25519-only for infrastructure frames to conserve bandwidth). This allows outer signatures to be device-attributed without leaking UserID information.

**7. Layered encryption pipeline** (§2.4). A precisely prescribed order on the sender and receiver side: Serialize → Sign Inner → Compress → KEM-Encrypt → Wrap Outer → Sign Outer → HMAC → PoW. The receiver mirrors the steps. Failure modes at every stage are documented (silent drop), no bounce-back, in order to avoid information leaks. This pipeline replaces the less formalized encryption-order block from v2.2 §4.6.

**8. Profile reset on upgrade.** Because of wire-format incompatibility and new sig keypairs, v2.2 profiles must be created from scratch when v3.0 is brought up. Restore Broadcast permits recovery of an identity (recovery phrase or contacts), but local conversations are lost. This is an acceptable cut: v3.0 is a beta-grade build, no productive data set needs to be migrated. See §23 for migration details.

**What remains unchanged:**

| Component | Status |
|---|---|
| Per-Message KEM (X25519+ML-KEM-768 hybrid v2 / Sec H-5) | unchanged, same salt scheme |
| User identity sigs (Ed25519+ML-DSA-65 hybrid) | unchanged |
| Closed Network HMAC (network_secret-derived) | unchanged, position remains in the Outer |
| PoW anti-spam | unchanged, position remains in the Outer |
| Erasure coding (Reed-Solomon N=10, K=7) | unchanged |
| Mailbox-IDs (public-key-hash-derived) | unchanged |
| 2D-DHT identity resolution | retained — sub-step in the send path, now clearly separated from routing |
| Multi-Identity HD-Wallet derivation | unchanged |
| Database encryption (XSalsa20-Poly1305) | unchanged |
| Calendar (§11.1, §11.2), Polls (§11.3, §11.4), Channels (§9), Calls (§10) | functionally unchanged, only API callers migrated |

---

## 2. Wire-Format & Layered Frames

V3.0 structures the wire format as a **2-layer frame stack**: an Outer Frame carries the routing information (device-to-device), an Inner Frame carries the identity information (user-to-user). Both layers have their own crypto subjects (Device-Sig vs. User-Sig), their own visibility (relays see only the Outer), and their own responsibilities (routing vs. application dispatch).

This is an application of the classical OSI layering model to P2P messaging. It replaces the v2.2 model, in which a single `MessageEnvelope` carried both routing and identity fields in a plaintext header — with the consequence that every relay hop could see the UserIDs of all participants and ID-mismatch bugs (userId vs. deviceNodeId) were structurally possible.

### 2.1 Layer Stack Overview

Cleona wraps every sent message in four conceptual layers, which are serialized into two physical wire frames:

```
┌──────────────────────────────────────────────────────────────┐
│ Application Layer  — MessageType + Payload (e.g. Text, CR)   │ ┐
│   • Message content                                          │ │ Inner Frame
│   • KEM-encrypted under recipientUserPublicKey               │ │ (ApplicationFrame)
├──────────────────────────────────────────────────────────────┤ │ KEM-encrypted
│ Identity Layer  — recipientUserId + senderUserId             │ │ + User-signed
│   • Which user-tab on the receiver                           │ │
│   • User-Sig (Ed25519+ML-DSA-65 hybrid)                      │ ┘
├──────────────────────────────────────────────────────────────┤
│ Routing Layer  — nextHopDeviceId + senderDeviceId            │ ┐
│   • Where in the mesh                                        │ │ Outer Frame
│   • Device-Sig (Ed25519+ML-DSA-65 hybrid for Application,    │ │ (NetworkPacket)
│     Ed25519-only for Infrastructure)                         │ │ Device-signed
│   • TTL, hopCount, RelayMetadata                             │ │ + HMAC + PoW
├──────────────────────────────────────────────────────────────┤ │
│ Transport Layer  — UDP packet or TLS frame                   │ │
│   • HMAC (Closed-Network tag, network_secret-derived)        │ │
│   • PoW (anti-spam)                                          │ ┘
└──────────────────────────────────────────────────────────────┘
```

**What each component sees:**

| Component | Sees | Does NOT see |
|---|---|---|
| Network observer (Wireshark) | Transport layer (UDP header, TLS wrapper) | Routing/Identity/Application — all AEAD-encrypted or hash-bound |
| Relay hop (multi-hop) | Routing layer (`nextHopDeviceId`, TTL, hopCount, sender device sig) | Identity layer and application payload — both opaque in the `payload` field |
| Recipient device | Routing layer + Identity layer + Application layer | nothing hidden |
| Recipient user-tab (UI) | Application payload after KEM-decrypt + User-Sig verify | nothing (recipient is the end consumer) |

**Layered trust boundary:**

- Routing-layer trust: Closed-Network HMAC + Device-Sig. Trusts the assertion "this device belongs to the Cleona network and sent the packet".
- Identity-layer trust: User-Sig (hybrid) + KEM-key match. Trusts the assertion "this user identity authored the content and only the recipient user can read it".

This separation prevents whole classes of cross-layer spoofing attacks that were structurally possible in v2.2 (e.g. a relay node manipulating senderId without the receiver noticing during routing-layer verify).

### 2.2 Outer Frame: NetworkPacket

The Outer Frame is what travels over the UDP socket. It contains exclusively routing-relevant fields. The actual application content (`payload`) is opaque to relays.

**Protobuf definition (Appendix A for the complete .proto file):**

```protobuf
message NetworkPacket {
  uint32  version          = 1;   // V3.0 = 1; wire-format bump on major cut
  uint32  flags            = 2;   // bit-flags (onion-layer indicator, etc.)
  bytes   nextHopDeviceId  = 3;   // 32 byte SHA-256 — where to
  bytes   senderDeviceId   = 4;   // 32 byte SHA-256 — from which device
  uint64  timestampMs      = 5;   // ms epoch — replay window
  uint32  ttl              = 6;   // hop limit (default 64)
  uint32  hopCount         = 7;   // +1 per relay
  bytes   networkTag       = 8;   // 16 byte HMAC-SHA256(network_secret, frame_bytes_minus_tag)
  bytes   pow              = 9;   // ProofOfWork solution (variable length)

  // Sig fields (subject = device keypair)
  bytes   deviceEd25519Sig = 10;  // 64 byte
  bytes   deviceMlDsaSig   = 11;  // ~3.3 KB ML-DSA-65 — empty for infrastructure frames

  // Payload discriminator (for onion hook in §2.5)
  PayloadType payloadType  = 12;  // APPLICATION_FRAME (default V3.0) or ONION_LAYER (future)
  bytes   payload          = 13;  // serialized ApplicationFrame or serialized NetworkPacket
}

enum PayloadType {
  APPLICATION_FRAME = 0;          // payload = ApplicationFrame (Identity layer)
  ONION_LAYER       = 1;          // payload = nested NetworkPacket (onion-routing layer)
}
```

**Field explanation:**

- **`version`**: V3.0 sets `1`. Prevents replay/mismatch between v2.2 nodes (which do not know NetworkPacket — wire reject) and v3.0 nodes.
- **`flags`**: Reserved for future extensions (e.g. EXPRESS for latency-critical frames, NEEDS_PADDING for anti-traffic-analysis padding). V3.0: typically `0`.
- **`nextHopDeviceId`**: SHA-256(network_secret + device_pubkey_ed25519) — the canonical device ID. The receiver of this physical UDP packet checks: is `nextHopDeviceId == myDeviceId`? If yes → unwrap. If no → I am a relay → forward toward `nextHopDeviceId`.
- **`senderDeviceId`**: For the reverse path (e.g. routing DELIVERY_RECEIPT back) and for sig-verify (relay fetches the sender device pubkey from DHT/RoutingTable).
- **`timestampMs`**: Replay window. Frames older than 60s are discarded. Closed-network nodes keep their clocks synchronized via NTP/Bootstrap.
- **`ttl` / `hopCount`**: Multi-hop lifetime. Default ttl=64, each relay decrements. hopCount is incremented (max 3 for the Cleona mesh, dropped beyond that).
- **`networkTag`**: HMAC-SHA256-128 with `network_secret` (16 byte, derived from Maintainer-Key + network_channel). Hardened closed-network filter — packets from non-Cleona software are discarded before any further processing.
- **`pow`**: Proof-of-Work solution (Cleona difficulty). Anti-spam filter, verification in O(1).
- **`deviceEd25519Sig` / `deviceMlDsaSig`**: Hybrid sig from the sending device. ML-DSA is omitted for infrastructure frames (DHT pings, hole punch, RTT probes) to save bandwidth — see §3.5.
- **`payloadType` / `payload`**: The Outer carries either an ApplicationFrame directly (V3.0 default) or another NetworkPacket (onion layer, not active in V3.0 — see §2.5).

**Size overview** (typical application frame with hybrid device sig):

| Field | Size |
|---|---|
| Header (version, flags, ids, timestamp, ttl, hopCount, networkTag, pow) | ~120 byte |
| deviceEd25519Sig | 64 byte |
| deviceMlDsaSig (hybrid) | ~3300 byte |
| payload (ApplicationFrame) | variable — typically 200 byte (short text msg) up to ~1000 byte (reaction, read receipt) |
| **Outer overhead total (hybrid)** | **~3500 byte** + payload |
| Outer overhead (Ed25519-only, infrastructure) | **~200 byte** + payload |

The ML-DSA size (~3.3 KB) is the dominant overhead for application frames. This is why the selectivity in §3.5 matters: only application traffic carries hybrid; infrastructure runs Ed25519-only.

### 2.3 Inner Frame: ApplicationFrame

The Inner Frame is KEM-encrypted under the recipient user pubkey. Only the recipient device (which holds the user privkey) can decrypt it. Relays see **nothing** of it — the Inner is opaque `payload` bytes inside the Outer.

**Protobuf definition (encrypted payload, AEAD-tagged):**

```protobuf
message ApplicationFrame {
  uint32      version          = 1;   // V3.0 = 1
  bytes       recipientUserId  = 2;   // 32 byte SHA-256 — which user-tab on the receiver
  bytes       senderUserId     = 3;   // 32 byte SHA-256 — from which user
  uint64      timestampMs      = 4;
  bytes       messageId        = 5;   // 16 byte random — end-to-end dedup
  MessageType messageType      = 6;   // TEXT, MEDIA_INLINE, CONTACT_REQUEST, REACTION, ...
  bytes       payload          = 7;   // application content (e.g. TextMessage.proto)

  // Sig fields (subject = user keypair)
  bytes       userEd25519Sig   = 10;  // 64 byte
  bytes       userMlDsaSig     = 11;  // ~3.3 KB ML-DSA-65 (always hybrid for application identity)

  // Conversation routing
  bytes       groupId          = 17;  // empty for DM; set for group/channel pairwise fan-out
}

// KEM header remains structurally as in v2.2 (KEM v2 Sec H-5):
message PerMessageKem {
  bytes  x25519Ciphertext   = 1;
  bytes  mlKemCiphertext    = 2;   // ML-KEM-768
  bytes  aeadCiphertext     = 3;   // ChaCha20-Poly1305(serialized ApplicationFrame)
  bytes  aeadNonce          = 4;
  uint32 version            = 5;   // KEM version, V3.0 = 2 (Sec H-5 v2 continues)
}
```

The NetworkPacket.payload bytes are the serialized `PerMessageKem`. Receiver:
1. Verifies Outer HMAC + Device-Sig
2. Reads payload, deserializes as `PerMessageKem`
3. Decapsulates KEM setup, derives the AEAD key
4. Decrypts `aeadCiphertext` → obtains serialized `ApplicationFrame`
5. Verifies User-Sig over the serialized ApplicationFrame
6. Reads `recipientUserId` → dispatches into the correct user-tab of the daemon

**Why recipientUserId lives in the Inner and NOT in the Outer:**

In v2.2, senderUserId was plaintext in the Outer — every relay saw "User Alice sends to User Bob". V3.0 hides UserIDs from relays. The Outer knows only DeviceIDs. Which users are hosted on a device is privacy-sensitive information that relays do not need to learn.

After Outer decap, the recipient daemon only knows: "this packet is for my device". Only the Inner decrypt reveals which user-tab it belongs to. This is the multi-identity clean separation: a daemon hosts e.g. Alice + AllyCat, both receive packets addressed to the same DeviceID, but Inner.recipientUserId decides which tab.

### 2.3.5 Infrastructure Frame (Device-targeted Inner)

**NEW in V3.0 Welle 5.** The third Inner-Frame variant — used when the recipient subject is a **device**, not a user. This applies to DHT operations, routing probes, NAT traversal, and reachability checks, where there is no user-identity claim to authenticate end-to-end.

**Protobuf definition:**

```protobuf
message InfrastructureFrame {
  uint32      version            = 1;   // V3.0 = 1
  bytes       recipientDeviceId  = 2;   // 32 bytes — destination device
  bytes       senderDeviceId     = 3;   // 32 bytes — sender device (= NetworkPacket.senderDeviceId)
  uint64      timestampMs        = 4;
  bytes       messageId          = 5;   // 16 bytes UUID v4 — end-to-end dedup
  MessageType messageType        = 6;   // restricted to §2.3.5 selector list (below)
  bytes       payload            = 7;   // type-specific protobuf
}
```

**No User-Sig fields** — the Outer Device-Sig (already on the NetworkPacket) provides the routing-layer authenticity. Adding a User-Sig would be cryptographic overhead without value: there is no UserID to bind.

**KEM subject**: recipient-**Device**-PK (X25519+ML-KEM-768, see §3.5b). Carried in `NetworkPacket.payload` as a `PerMessageKem` ciphertext, with `payloadType = INFRASTRUCTURE_FRAME` in the Outer.

**Permitted MessageTypes for InfrastructureFrame** (normative selector list, mirrored in `isInfrastructureMessageTypeV3()` predicate). Each row carries a **Path** annotation that selects the wire-encoding pipeline:

- **KEM** = KEM-encrypted via Device-KEM-PK of recipient (§2.4.1, default)
- **BOOT** = HMAC-only Bootstrap-Path (§2.4.1a) — used only where requiring Device-KEM-PK creates a chicken-and-egg loop (sender does not yet have recipient's Device-KEM-PK and cannot obtain it without first running one of these RPCs). Authenticity is provided by the inner record's signature (where applicable) plus the outer Closed-Network HMAC; **confidentiality of routing metadata is consciously waived for these RPCs** (see §4.10 threat-model addendum).

| Category | MessageTypes | Path |
|---|---|---|
| DHT operations (Kademlia bootstrap) | DHT_PING, DHT_PONG, DHT_FIND_NODE, DHT_FIND_NODE_RESPONSE | **BOOT** |
| DHT operations (data) | DHT_STORE, DHT_STORE_RESPONSE, DHT_FIND_VALUE, DHT_FIND_VALUE_RESPONSE | KEM |
| 2D-DHT identity resolution — RETRIEVE side | IDENTITY_AUTH_RETRIEVE/RESPONSE, IDENTITY_LIVE_RETRIEVE/RESPONSE, IDENTITY_KEM_RETRIEVE/RESPONSE | **BOOT** |
| 2D-DHT identity resolution — PUBLISH side | IDENTITY_AUTH_PUBLISH, IDENTITY_LIVE_PUBLISH, IDENTITY_KEM_PUBLISH | **BOOT** |
| Fragment storage | FRAGMENT_STORE, FRAGMENT_STORE_ACK, FRAGMENT_RETRIEVE, FRAGMENT_RETRIEVE_RESPONSE, FRAGMENT_DELETE | KEM |
| S&F on mutual peers | PEER_STORE, PEER_STORE_ACK, PEER_RETRIEVE, PEER_RETRIEVE_RESPONSE | KEM |
| Peer-list gossip | PEER_LIST_PUSH, PEER_LIST_SUMMARY, PEER_LIST_WANT, PEER_KEY_REQUEST, PEER_KEY_RESPONSE | **BOOT** |
| Routing — DV updates | ROUTE_UPDATE | **BOOT** |
| Reachability probes | REACHABILITY_QUERY, REACHABILITY_RESPONSE | **BOOT** |
| Relay forwarding | RELAY_FORWARD, RELAY_ACK | KEM |
| NAT/hole-punch | HOLE_PUNCH_REQUEST, HOLE_PUNCH_NOTIFY, HOLE_PUNCH_PING, HOLE_PUNCH_PONG | **BOOT** |
| Delivery ACK | DELIVERY_RECEIPT (when targeting senderDeviceId without UserID context) | KEM |
| Identity-Layer Infrastructure (Welle 6) | RESTORE_BROADCAST, KEY_ROTATION_BROADCAST (Emergency-variant only — when both `oldSignatureEd25519` and `newSignatureEd25519` are set in the body) | KEM |

**BOOT-path requirements** (mandatory for every BOOT-row above):

1. The inner record (where it has owner-bound semantics — AuthManifest, LivenessRecord, DeviceKemRecord) carries an Ed25519 (+ optional ML-DSA) signature over its content. The Closed-Network HMAC alone never authenticates user-bound claims.
2. Anti-replay window of 60 s on `timestampMs` is enforced (same as KEM-path).
3. PUBLISH-RPCs additionally require a monotonic `seq` field, identical to the existing 2D-DHT publish protocol.

All other MessageTypes (TEXT, MEDIA_*, GROUP_*, CHANNEL_*, CALL_*, CALENDAR_*, POLL_*, RESTORE_RESPONSE, IDENTITY_DELETED, PROFILE_UPDATE, KEY_ROTATION (periodic KEM-only), TWIN_*) remain ApplicationFrame. **Special case CONTACT_REQUEST**: First-CR-Bootstrap (§8.1.1) wraps a fully user-signed ApplicationFrame inside an InfrastructureFrame because the sender does not yet know the recipient's User-KEM-PK; CR-Retry and CR-Response after the first round-trip use ApplicationFrame normally.

The Emergency-variant discriminator for KEY_ROTATION_BROADCAST is structural (dual-sig in body), not declared in the wire envelope. The sender chooses the InfrastructureFrame path when constructing an Emergency rotation; the receiver enforces the selector match by verifying that the inner KeyRotationBroadcast body carries both old- and new-sigs.

### 2.4 Layered Encryption Pipeline

The order of operations is precisely prescribed — both on the sender side and on the receiver side. Deviations lead to decap failures and are non-debuggable.

**Sender pipeline (sendToUser → wire):**

```
Application content (e.g. TextMessage)
          │
          ▼
  [1] Serialize content (Protobuf)
          │
          ▼
  [2] Build ApplicationFrame { recipientUserId, senderUserId, messageType, payload, ... }
          │
          ▼
  [3] User-Sign ApplicationFrame  (Ed25519 + ML-DSA-65 hybrid)
          │   → fills userEd25519Sig + userMlDsaSig
          ▼
  [4] Serialize ApplicationFrame  (Protobuf, with sigs filled)
          │
          ▼
  [5] zstd-compress ApplicationFrame bytes
          │
          ▼
  [6] Per-Message KEM-encrypt  (X25519+ML-KEM-768 hybrid v2)
          │   → recipientUserId.x25519Pk + .mlKemPk fetched from contact-store
          │   → produces PerMessageKem { x25519Ct, mlKemCt, aeadCt, aeadNonce, version=2 }
          ▼
  [7] Serialize PerMessageKem    → that becomes the Outer.payload bytes
          │
          ▼
  [8] Build NetworkPacket { nextHopDeviceId, senderDeviceId, payloadType=APPLICATION_FRAME,
                            payload=PerMessageKem-bytes, timestampMs, ttl, hopCount=0, ... }
          │
          ▼
  [9] Device-Sign NetworkPacket   (Ed25519 always; ML-DSA-65 if Application, skip if Infrastructure)
          │   → fills deviceEd25519Sig + (optional) deviceMlDsaSig
          ▼
  [10] Compute PoW                (skip if recipient is LAN-peer or Infrastructure-Frame)
          │   → fills pow
          ▼
  [11] Compute HMAC               (HMAC-SHA256-128 over (frame_bytes - networkTag-field))
          │   → fills networkTag
          ▼
  [12] Serialize NetworkPacket → UDP-send (or TLS-fallback for >1200 byte)
```

**Receiver pipeline (UDP-receive → application):**

```
UDP-Packet bytes
          │
          ▼
  [1] Parse as NetworkPacket
          │   → if parse-fails: drop silently
          ▼
  [2] Verify HMAC (networkTag) using local network_secret
          │   → if mismatch: drop silently (Closed-Network filter)
          ▼
  [3] Verify timestamp window (now - timestampMs < 60s)
          │   → if too old: drop (replay protection)
          ▼
  [4] Verify Device-Sig (deviceEd25519Sig + optional deviceMlDsaSig)
          │   → fetch senderDevicePubkeys from RoutingTable or 2D-DHT (DeviceKemRecord/AuthManifest)
          │   → if mismatch: drop
          │   → Note: For InfrastructureFrame payloads, the Device-Sig-Key
          │     is rotation-stable (§3.5b — Device-Keys are independent of
          │     User-Identity rotation). Identity-Layer Infrastructure
          │     MessageTypes (RESTORE_BROADCAST, Emergency KEY_ROTATION_BROADCAST)
          │     therefore verify under unchanged Device-Pubkeys even when
          │     the underlying User-Identity is being rotated.
          ▼
  [5] Verify PoW                  (skip if Infrastructure-Frame, or if from LAN/relay)
          │
          ▼
  [6] Routing Decision
          │   IF nextHopDeviceId == myDeviceId:
          │     → I am the recipient device → unwrap-and-dispatch (continue at [7])
          │   ELSE:
          │     → I am a relay → forward to nextHop (re-wrap NetworkPacket, ttl-1)
          │     → (also send DELIVERY_RECEIPT-style ack back to senderDevice)
          │
          ▼
  [7] Read payloadType
          │   IF ONION_LAYER:
          │     → payload is a nested NetworkPacket → recurse at [1]    (V3.0 not active, see §2.5)
          │   ELSE IF INFRASTRUCTURE_FRAME:
          │     → KEM-Subjekt = recipient-Device-PK; switch to §2.4.1 receiver pipeline
          │   ELSE (APPLICATION_FRAME):
          │     → continue
          ▼
  [8] Parse payload as PerMessageKem
          │
          ▼
  [9] KEM-Decapsulate
          │   → for each hosted User-Identity on this daemon, attempt KEM-decap
          │     with that identity's User-KEM-SK (X25519 + ML-KEM-768) until
          │     one succeeds. Order: identities sorted by recently-active-first
          │     (heuristic: the identity that received the most recent inbound
          │     frame is tried first). On a single-identity daemon this collapses
          │     to one attempt.
          │   → derive AEAD-key from x25519 + mlKem ciphertexts (per attempt)
          │   → if KEM-Version mismatch: silent drop (no further attempts)
          │   → if all attempts fail to decap+AEAD-verify: silent drop (frame
          │     was not addressed to any UserID hosted on this daemon)
          │   → on first success: continue with the matching identity's User-KEM
          │     context for steps [10]-[14]
          ▼
  [10] AEAD-Decrypt aeadCiphertext  (ChaCha20-Poly1305)
          │   → if AEAD-mismatch: drop (forged or wrong recipient)
          ▼
  [11] zstd-Decompress
          │
          ▼
  [12] Parse as ApplicationFrame
          │
          ▼
  [13] Verify User-Sig (userEd25519Sig + userMlDsaSig)
          │   → fetch senderUserPubkeys from contact-store
          │   → if mismatch: drop (forgery attempt or unknown sender)
          ▼
  [14] Cross-validate Inner.recipientUserId against the identity that
       successfully decapped in Step [9]
          │   → these MUST match (defence-in-depth: detect a frame whose
          │     KEM-decap succeeded under identity A but whose Inner declares
          │     recipientUserId=B — should never happen for legitimate frames
          │     because both pubkeys derive from the same User-Master-Seed,
          │     but explicit check protects against future cross-identity
          │     KEM-key re-use bugs)
          │   → if mismatch: silent drop, log forgery hint
          ▼
       Dispatch to the matching identity's service handler
       (`_services[recipientUserId.hex].handleApplicationFrame(...)`)
          │
          ▼
  Application-handler processes the messageType + payload
```

**Failure handling at each step:**

| Step | Failure | Action |
|---|---|---|
| HMAC mismatch | Packet is not a valid Cleona packet (fork, spam, wrong channel) | Silent drop, no logging |
| Timestamp out of window | Replay attempt or clock skew | Drop + optionally clock-sync trigger |
| Device-Sig mismatch | Forgery attempt (no PQ protection if sig algorithm is broken) | Drop |
| PoW fail | Spam (no PoW computed) | Drop |
| Routing: ttl=0 | Loop or too many hops | Drop, no bounce |
| KEM-version mismatch | Sender is on an old KEM version | Silent drop, **no** DELIVERY_RECEIPT (see Sec H-5 §3.3.6) |
| KEM-decap failure | KEM setup corrupt or recipient privkey rotated | Drop |
| AEAD-tag failure | Wrong recipient or forgery | Drop |
| User-Sig mismatch | Forgery or unknown sender | Drop, KEX gate triggered (see §8.2) |
| All hosted-identity decap attempts fail | Frame addressed to a UserID not hosted here (misdelivery or misroute) | Silent drop |
| KEM-identity vs Inner-recipientUserId mismatch | Cross-identity KEM key reuse or forgery attempt | Silent drop |

**Important**: At each stage, "silent drop" is the default. Cleona performs **no** bounce-back ("your sig is invalid") and no reactive errors — that would be information leakage to an attacker. Only DELIVERY_RECEIPT on full successful processing.

#### 2.4.0 Sender Identity Snapshot

Every successfully parsed NetworkPacket carries a `senderIdentitySnapshot` that records the outcome of step §2.4 [4] (Outer Device-Sig-Verify). The snapshot is built in the receive pipeline immediately after step [4] and threaded through to every inner-frame handler. Type-specific handlers consult it to gate inner-auth-sensitive actions (e.g. §8.1 Re-Contact Auto-Overwrite, §6.3 Restore acceptance).

**Schema:**

| Field | Type | Source |
|---|---|---|
| `senderDeviceId` | 32 B | NetworkPacket.senderDeviceId |
| `senderUserId` | 32 B (or empty) | ApplicationFrame.senderUserId — empty for InfrastructureFrame |
| `outerSigStatus` | enum | `verified` \| `skippedBootstrap` \| `skippedWhitelist` |
| `verifiedDeviceEd25519Pk` | 32 B (nullable) | populated iff `verified` |
| `verifiedDeviceMlDsaPk` | 1952 B (nullable) | populated iff `verified` AND ML-DSA was present |
| `newKeyDetectedForSenderUser` | bool | true iff `senderUserId` was previously known with different user-pubkeys |
| `receivedAt` | timestamp | wall-clock at packet arrival, post timestamp-window |

**Outer-Sig-Status semantics:**

| Status | Meaning | Inner-Auth requirement |
|---|---|---|
| `verified` | Step [4] passed against routing-table pubkey | Standard — handlers MAY trust sender identity claims |
| `skippedBootstrap` | No pubkey on file (first contact, fresh routing table) | Handler MUST verify all inner-auth strictly. NO auto-trust actions (no Re-Contact-Auto-Overwrite, no Identity-key-replace without UI confirmation) |
| `skippedWhitelist` | Reserved — V3.0 Welle 6 chose Variant B (InfrastructureFrame migration) over Pre-Verify whitelist; this status is currently unreachable but kept for forward compatibility |

**Lifecycle:**

1. Constructed in `cleona_node._onPacketV3Received` immediately after step §2.4 [4]
2. Passed to `onApplicationFramePayload(packet, from, fromPort, snapshot)`
3. After Inner User-Sig verify in `decryptAndVerifyInner`, the receiver asserts `snapshot.senderUserId == frame.senderUserId` — mismatch → drop (defense against attacker-chosen senderUserId riding a lenient outer pass)
4. Threaded into every `_handle*V3(frame, senderDeviceId, snapshot)` bridge
5. Native V3-Handlers receive it as a first-class argument
6. NOT persisted — per-packet ephemeral

**Variant choice (Welle 6, ADR):**

V3.0 Welle 6 evaluated two variants for the Identity-Rotation Outer-Sig-Verify problem:

- **Variant A** (Pre-Verify-Skip Whitelist on ApplicationFrame path): rejected. Would require post-decap whitelist check + per-type inner-auth policy carried in pipeline, expanding the trusted code path for marginal benefit.
- **Variant B** (InfrastructureFrame migration of identity-rotation MessageTypes): adopted. Device-Sig-Keys are rotation-stable per §3.5b, so the regular Outer-Sig-Verify (step §2.4 [4]) succeeds without exception. The bootstrap lenient-pass remains the only authenticated-skip path, and `snapshot.outerSigStatus == skippedBootstrap` gates all trust-elevating actions in the inner handlers.

#### 2.4.1 Pipeline for INFRASTRUCTURE_FRAME

The pipeline above describes the APPLICATION_FRAME path (KEM under recipient-User-PK, User-Sig at the Identity-Layer). The INFRASTRUCTURE_FRAME path (NEW in V3.0 Welle 5) differs in three places: (i) the KEM subject is the recipient-Device-PK, not the recipient-User-PK; (ii) there is no User-Sig step (no UserID subject — Outer Device-Sig provides routing authenticity); (iii) the payload schema is `InfrastructureFrame` (§2.3.5) instead of `ApplicationFrame`.

**Sender pipeline — INFRASTRUCTURE_FRAME path** (sender knows recipient DeviceID; MessageType is in the §2.3.5 selector list):

```
service.sendInfrastructureFrame(deviceId, messageType ∈ §2.3.5, payload)
          │
          ▼
  [1'] Build InfrastructureFrame { recipientDeviceId, senderDeviceId,
                                   timestampMs, messageId, messageType, payload }
          │
          ▼
  [2'] Serialize InfrastructureFrame   (Protobuf — no User-Sig fields exist)
          │
          ▼
  [3'] zstd-compress InfrastructureFrame bytes
          │
          ▼
  [4'] Per-Message KEM-encrypt (X25519 + ML-KEM-768 hybrid v2)
          │   → recipient-Device-KEM-PK fetched from:
          │       a. local routing table cache (cached DeviceKemRecord), or
          │       b. 2D-DHT lookup of DeviceKemRecord (§4.3 step 4b), or
          │       c. ContactSeed URI (§8.1.1 — First-CR-Bootstrap only)
          │   → produces PerMessageKem { x25519Ct, mlKemCt, aeadCt, aeadNonce, version=2 }
          ▼
  [5'] Serialize PerMessageKem → Outer.payload bytes
          │
          ▼
  [6'] Build NetworkPacket { nextHopDeviceId, senderDeviceId,
                             payloadType=INFRASTRUCTURE_FRAME,
                             payload=PerMessageKem-bytes, ttl, hopCount=0, ... }
          │
          ▼
  [7'] Device-Sign NetworkPacket   (Ed25519-only per §3.5 selectivity rule —
                                     Infrastructure-Frames are bandwidth-frequent;
                                     deviceMlDsaSig is left empty)
          │
          ▼
  [8'] Compute PoW                 (skip — Infrastructure-Frames are PoW-exempt
                                     because they are routing-essential and self-rate-limited
                                     by DHT/Routing semantics; see §13.1)
          │
          ▼
  [9'] Compute HMAC                (HMAC-SHA256-128 over (frame_bytes - networkTag-field))
          │
          ▼
  [10'] Serialize NetworkPacket → UDP-send (or TLS-fallback for >1200 byte)
```

**Receiver pipeline — INFRASTRUCTURE_FRAME path** (continues from main receiver pipeline §2.4 step [7] when payloadType = INFRASTRUCTURE_FRAME):

```
[from §2.4 step 7, payloadType=INFRASTRUCTURE_FRAME]
          │
          ▼
  [8'] Parse payload as PerMessageKem
          │
          ▼
  [9'] KEM-Decapsulate using local **Device**-KEM-PrivKey (§3.5b)
          │   → derive AEAD-key from x25519 + mlKem ciphertexts
          │   → if KEM-version mismatch: silent drop
          │   → if decap fails: silent drop (forged sender or stale Device-KEM-PK)
          ▼
  [10'] AEAD-Decrypt aeadCiphertext  (ChaCha20-Poly1305)
          │   → if AEAD-mismatch: drop
          ▼
  [11'] zstd-Decompress
          │
          ▼
  [12'] Parse as InfrastructureFrame
          │
          ▼
  [13'] Validate messageType ∈ §2.3.5 selector list
          │   → if not in selector list: drop (cross-layer abuse attempt — an
          │     attacker may not promote an ApplicationFrame messageType to the
          │     Infrastructure path to bypass the User-Sig check)
          ▼
  [14'] Validate recipientDeviceId == self.deviceId
          │   The DeviceID is daemon-global (§3.1) — multi-identity has no
          │   implication at the routing layer. After this check, the
          │   InfrastructureFrame is processed daemon-wide; identity-layer
          │   routing happens only for InfrastructureFrame messageTypes that
          │   carry an explicit identity reference (e.g. CONTACT_REQUEST
          │   First-CR-Bootstrap §8.1.1, RESTORE_BROADCAST §6.3, Emergency
          │   KEY_ROTATION_BROADCAST §7.4) — those re-enter the Application-
          │   Frame KEM-decap path with per-identity User-KEM-SK selection
          │   (§2.4 step [9]).
          │   → if mismatch: drop (misdelivery — should already be
          │     filtered at §2.4 step 6)
          ▼
  Infrastructure-handler dispatches by messageType
  (DHT, Routing, NAT, Reachability, Fragment, S&F, etc.)
```

**Special case: First-CR-Bootstrap** (§8.1.1) — the sender wraps a fully User-signed `ApplicationFrame` into `InfrastructureFrame.payload` (with `messageType = CONTACT_REQUEST`). The receiver, after step [13'], detects the CR exception, parses the payload as ApplicationFrame, then runs steps [13]-[14] of the regular APPLICATION_FRAME receiver pipeline (User-Sig verify, KEX-Gate exception for CR — see §8.2). This is the only place where the §2.3.5 selector list is intentionally relaxed — it must remain strict for all other MessageTypes.

**Failure handling — additional rows for the INFRASTRUCTURE_FRAME path**:

| Step | Failure | Action |
|---|---|---|
| KEM-decap with Device-PrivKey | Sender used wrong Device-KEM-PK (stale 2D-DHT record) | Silent drop |
| AEAD-tag failure on Device-KEM | Wrong recipient device or forgery | Drop |
| messageType outside §2.3.5 selector | Cross-layer abuse attempt | Drop, optionally reputation hit |
| recipientDeviceId not hosted | Misdelivery (routing bug or stale DeviceKemRecord pointing at a moved identity) | Drop |

#### 2.4.1a Pipeline for BOOTSTRAP_INFRASTRUCTURE_FRAME

The default InfrastructureFrame path (§2.4.1) KEM-encrypts every Inner under the recipient's Device-KEM-PK. For the BOOT-subset of §2.3.5 this would create an unresolvable bootstrap loop: the sender cannot obtain the recipient's Device-KEM-PK without first running one of these very RPCs. The BOOT-path therefore omits the KEM-encryption step and relies on Closed-Network HMAC (§4.10) for authenticity, plus an inner record signature where the message carries owner-bound claims.

**Sender pipeline — BOOTSTRAP_INFRASTRUCTURE_FRAME path** (sender knows recipient DeviceID; messageType is in the BOOT-subset of §2.3.5):

```
service.sendBootstrapInfrastructureFrame(deviceId, messageType ∈ §2.3.5 BOOT-subset, payload)
          │
          ▼
  [1″] Build InfrastructureFrame { recipientDeviceId, senderDeviceId,
                                   timestampMs, messageId, messageType, payload }
          │   For PUBLISH-RPCs: payload is the signed record (AuthManifest /
          │   LivenessRecord / DeviceKemRecord) — its Ed25519 (+ML-DSA) signature
          │   provides owner-bound authenticity. For RETRIEVE/PING/HOLE-PUNCH/etc.:
          │   payload is a plain protobuf request — Closed-Network HMAC alone
          │   provides Closed-Network membership; no user-binding is claimed.
          ▼
  [2″] Serialize InfrastructureFrame   (Protobuf, no User-Sig fields, no zstd)
          │
          ▼
  [3″] Build NetworkPacket { nextHopDeviceId, senderDeviceId,
                             payloadType=BOOTSTRAP_INFRASTRUCTURE_FRAME,
                             payload=InfrastructureFrame-bytes,
                             ttl, hopCount=0, timestampMs, ... }
          │
          ▼
  [4″] Device-Sign NetworkPacket    (Ed25519-only; deviceMlDsaSig left empty —
                                     same selectivity rule as §2.4.1)
          │
          ▼
  [5″] PoW skip                     (BOOT-frames are routing-essential, see §13.1)
          │
          ▼
  [6″] Compute HMAC                 (HMAC-SHA256-128 over (frame_bytes − networkTag-field))
          │
          ▼
  [7″] Serialize NetworkPacket → UDP-send
```

**Receiver pipeline — BOOTSTRAP_INFRASTRUCTURE_FRAME path** (continues from §2.4 step [7] when payloadType = BOOTSTRAP_INFRASTRUCTURE_FRAME):

```
[from §2.4 step 7, payloadType=BOOTSTRAP_INFRASTRUCTURE_FRAME]
          │
          ▼
  [8″] Parse payload directly as InfrastructureFrame
          │   (no PerMessageKem wrapper, no zstd, no KEM-decap)
          ▼
  [9″] Validate messageType ∈ §2.3.5 BOOT-subset
          │   → if outside BOOT-subset: drop (cross-layer abuse — an attacker
          │     may not promote a KEM-required messageType to the BOOT-path
          │     to bypass confidentiality)
          ▼
  [10″] Validate recipientDeviceId == self.deviceId
          (per §3.1 the DeviceID is daemon-global — multi-identity is a
          User-Layer property and has no consequence here. PUBLISH-RPCs
          that announce an identity-bound record (AuthManifest,
          LivenessRecord, DeviceKemRecord) target a replicator-DeviceID
          chosen by Kademlia distance to the record's storage-key — the
          target DeviceID is the daemon's deviceID regardless of which
          identity is publishing.)
          │
          ▼
  [11″] Inner-record signature verify (PUBLISH-RPCs only — RETRIEVE/PING/etc.
                                       carry no signed inner record):
          │   AuthManifest      → ed25519+mlDsa.verify(record, claimed userMasterPk)
          │   LivenessRecord    → ed25519.verify(record, claimed userPk)
          │   DeviceKemRecord   → ed25519.verify(record, claimed userMasterEd25519Pk)
          │   if verify fails: drop
          ▼
  Bootstrap-Infrastructure-handler dispatches by messageType
  (DHT bootstrap, 2D-DHT lookup, peer-list gossip, NAT, reachability)
```

**Failure-handling additions for the BOOT-path**:

| Step | Failure | Action |
|---|---|---|
| messageType outside BOOT-subset | Cross-layer abuse attempt (KEM-required type promoted to BOOT) | Drop, reputation hit |
| recipientDeviceId mismatch | Misdelivery | Drop |
| Inner-record sig verify (PUBLISH) | Forged record under fake user identity | Drop, reputation hit |
| Outer HMAC fails | Forged Closed-Network membership | Silent drop (already at §2.4 step 1) |

**Wire-format change**: `NetworkPacket.payloadType` enum gains one value `BOOTSTRAP_INFRASTRUCTURE_FRAME = 3` (after `APPLICATION_FRAME = 1`, `INFRASTRUCTURE_FRAME = 2`, `ONION_LAYER = 4` reserved per §2.5). No existing fields move; older receivers drop the unknown enum value silently — forward-only behaviour.

**Why this is safe**: the only confidentiality property waived is **routing metadata** (who knows whom, which device hosts which user, which addresses a device announces). This information is leakable to Closed-Network insiders by design — DHT participants must answer FIND_NODE/RETRIEVE truthfully to function as a DHT. KEM-encryption of these RPCs in the original V3 design hid the metadata only from passive on-path observers, not from active DHT peers. Outsiders still see nothing (HMAC blocks). User-content confidentiality is unaffected — every MessageType that carries user-content remains on the KEM-path. See §4.10 threat-model addendum.

### 2.5 Onion-Routing Hook

V3.0 implements **no** onion routing, but is structurally prepared for later activation through two complementary mechanisms:

1. **The `payloadType` discriminator** (§2.2) allows the NetworkPacket payload to be a nested NetworkPacket (`ONION_LAYER`) rather than an ApplicationFrame.
2. **The Device-KEM-Keypair** (§3.5b, NEW in V3.0 Welle 5) — the per-hop KEM subject for onion encryption. Without a Device-KEM-Keypair the onion layer would have no cryptographic subject; with it, each hop can decrypt its own onion shell using its Device-KEM-PrivKey.

Note for spec-history: prior to Welle 5, the Device-KEM-Keypair did not exist; the wire-format example below was therefore *structurally a phantom* — the `KEM-encrypt-to-HopN.devicePubkey` step had no concrete cryptographic subject. Welle 5 (Device-KEM-Keypair, DeviceKemRecord in 2D-DHT) closes that gap and makes the §2.5 wire-format example actually constructable.

**What later activation would look like:**

The sender selects a path with, say, 3 relays: Hop1 → Hop2 → Hop3 → Receiver. Instead of a flat NetworkPacket, the sender constructs three nested layers:

```
NetworkPacket(nextHop=Hop1, payloadType=ONION_LAYER, payload=
  KEM-encrypt-to-Hop1.devicePubkey(
    NetworkPacket(nextHop=Hop2, payloadType=ONION_LAYER, payload=
      KEM-encrypt-to-Hop2.devicePubkey(
        NetworkPacket(nextHop=Hop3, payloadType=ONION_LAYER, payload=
          KEM-encrypt-to-Hop3.devicePubkey(
            NetworkPacket(nextHop=Receiver, payloadType=APPLICATION_FRAME, payload=
              KEM-encrypt-to-Receiver.userPubkey(ApplicationFrame)
            )
          )
        )
      )
    )
  )
)
```

Each hop receives an Outer NetworkPacket. It verifies HMAC + DeviceSig + ttl, sees `payloadType=ONION_LAYER`, decrypts **one** layer (KEM decap with its own device privkey), and obtains the **inner** NetworkPacket. It forwards that toward its `nextHopDeviceId` — it does not know whether further layers lie behind it or whether the next hop is already the final receiver.

Receiver step 7 in the pipeline (see §2.4) handles this automatically: recursive processing via the `payloadType` discriminator.

**Why not activate in V3.0:**

1. **Anonymity-set size**: Onion routing requires a large number of hops to resist traffic analysis. Cleona Beta currently has ~7 nodes; even with 1000 nodes the set would be too small for mathematically robust anonymity. Onion routing in a small network is security theater — an adversary who can observe most nodes deanonymizes via timing correlation.
2. **Bandwidth overhead**: Each layer carries a KEM setup (~1.6 KB) plus a Device-Sig (~3.3 KB). At 3 hops that is ~15 KB overhead per message. Unacceptable for mobile cellular.
3. **Latency**: 3 hops = 3 sequential decrypt operations + 3 RTTs. A complete no-go for live calls.
4. **Threat-model extension**: Anonymity against a network observer is a different threat model from Cleona's current one (E2E + MITM + spoofing). It deserves its own spec discussion with Sybil protection on hop selection.

**Onion taboo list** (binding, also after later activation):

These MessageTypes must **never** be sent through onion routing, regardless of sender preference or user setting:

| Category | MessageTypes | Reason |
|---|---|---|
| **Live media** (latency-critical) | CALL_AUDIO, CALL_VIDEO, CALL_GROUP_AUDIO, CALL_GROUP_VIDEO, CALL_RTT_PING, CALL_RTT_PONG | Audio frame budget ≤50ms — onion hops would add >100ms |
| **Call setup** | CALL_INVITE, CALL_RESPONSE, CALL_BYE, CALL_TREE_UPDATE, CALL_REJOIN | Setup latency would be unacceptable for accept/reject UX |
| **DHT infrastructure** | IDENTITY_AUTH_PUBLISH, IDENTITY_LIVE_PUBLISH, IDENTITY_AUTH_RETRIEVE, IDENTITY_LIVE_RETRIEVE, FRAGMENT_STORE, FRAGMENT_RETRIEVE, PEER_LIST_PUSH, PEER_STORE, PEER_RETRIEVE | Topology visibility required for DHT replication — anonymization would break the DHT |
| **NAT/routing probes** | HOLE_PUNCH_REQUEST, HOLE_PUNCH_NOTIFY, HOLE_PUNCH_PING, HOLE_PUNCH_PONG, REACHABILITY_QUERY, REACHABILITY_RESPONSE | The direct path is the entire purpose — onion would negate the function |
| **Routing updates** | ROUTE_UPDATE, RELAY_FORWARD, RELAY_ACK, DELIVERY_RECEIPT | Routing information is precisely what onion would hide — chicken-and-egg problem |

Cross-ref: §10.3 (Live-Media Frame Authenticity) refers here, because the onion-taboo status for calls is normatively fixed there.

**Which MessageTypes would be onion candidates** (on later activation as opt-in):

- TEXT, MEDIA_INLINE, MEDIA_CHUNK
- REACTION, REPLY, EDIT, DELETE, READ_RECEIPT, TYPING_INDICATOR
- CONTACT_REQUEST, CONTACT_REQUEST_RESPONSE
- GROUP_INVITE, GROUP_LEAVE, CHANNEL_INVITE, CHANNEL_LEAVE
- CALENDAR_INVITE, CALENDAR_RSVP, POLL_CREATE, POLL_VOTE, etc.

The default for these would initially be OFF (bandwidth + latency). A per-chat setting is possible, with a clear UI hint about the trade-offs.

### 2.6 Frame Lifecycle: Send & Receive

This section describes the lifecycle from the service-layer perspective — how an application action (e.g. "user clicks Send in the chat") is turned into wire frames, and how received frames conversely arrive in the UI.

**Send lifecycle:**

```
GUI: User clicks "Send" with text "Hallo"
                 │
                 ▼
service.sendToUser(recipientUserId, MessageType.TEXT, payload=encoded("Hallo"))
                 │
                 ├─ [a] Identity-Resolution: identityResolver.resolveUserToDevices(recipientUserId)
                 │      → returns List<deviceId> (1..N devices for this user)
                 │      → if empty: storeForOfflineDelivery(envelope, recipientUserId)
                 │                  via S&F + Mailbox (see §5.4-5.6)
                 │                  → done
                 │
                 ├─ [b] For each device in result: fanout
                 │      ├─ build ApplicationFrame (Inner)
                 │      ├─ User-Sign Inner
                 │      ├─ Compress + KEM-encrypt Inner → PerMessageKem-bytes
                 │      ├─ build NetworkPacket (Outer) with payload=PerMessageKem
                 │      └─ node.sendToDevice(NetworkPacket, deviceId)
                 │
                 ▼
node.sendToDevice(packet, deviceId)
                 │
                 ├─ [c] Routing-Decision: routingTable.routesFor(deviceId), sorted by cost
                 │      ├─ try cheapest route, max 3 retries (ACK timeout 8s direct, 16s relay)
                 │      ├─ if no ACK: try next-cheaper route
                 │      ├─ if all enumerated routes exhausted: try defaultGateway
                 │      └─ if defaultGateway also fails: report failure (nothing more to do)
                 │
                 ├─ [d] On-success-path:
                 │      ├─ Device-Sign NetworkPacket
                 │      ├─ Compute PoW (if not Infrastructure + not LAN)
                 │      ├─ Compute HMAC
                 │      ├─ UDP-send (or TLS for >1200 byte)
                 │      └─ ackTracker.trackSend(...) for DELIVERY_RECEIPT
                 │
                 ▼
On DELIVERY_RECEIPT received from receiverDevice:
                 │
                 ├─ Mark message as delivered (per recipient device)
                 ├─ Update route-stats (route confirmed alive)
                 └─ UI shows ✓ checkmark
```

**Receive lifecycle:**

```
Transport-Layer: UDP packet bytes arrive
                 │
                 ▼
[Pipeline §2.4 receiver-side, steps 1-13]
                 │
                 ├─ if I am NOT the final hop (relay-case):
                 │   ├─ recurse routing: node.sendToDevice(repacked-packet, nextHopDeviceId)
                 │   └─ done (no application-dispatch)
                 │
                 ├─ if I am the final hop:
                 │   ├─ KEM-decap → AEAD-decrypt → ApplicationFrame
                 │   ├─ User-Sig-verify → if fail: KEX-Gate triggered (§8.2)
                 │   └─ continue dispatch
                 │
                 ▼
service.handleApplicationFrame(frame)
                 │
                 ├─ [a] Identity-Dispatch: which User-Tab?
                 │      → frame.recipientUserId → find local IdentityContext
                 │      → if no match: drop (this Daemon doesn't host that user)
                 │
                 ├─ [b] Dedup: messageId already seen?
                 │      → if yes: send DELIVERY_RECEIPT (idempotent), then drop
                 │
                 ├─ [c] Application-Handler dispatch by MessageType:
                 │      ├─ TEXT     → addToConversation(senderUserId, text)
                 │      ├─ MEDIA_*  → mediaHandler.process(...)
                 │      ├─ CR       → contactRequestHandler(...)
                 │      ├─ ...
                 │
                 ├─ [d] Send DELIVERY_RECEIPT back to senderDeviceId
                 │      (uses NetworkPacket.senderDeviceId from the Outer — that IS the route back)
                 │
                 ▼
GUI: New message appears in correct User-Tab
```

**Service-layer API connection:**

V3.0 establishes two canonical APIs for send operations:

- **`service.sendToUser(envelope, userId)`** — higher level. Performs identity resolution, multi-device fanout, offline fallback. This is the API that application code (GUI, Calendar, Polls, Channels) calls.

- **`node.sendToDevice(packet, deviceId)`** — lower level. Pure routing operation: routing-table consult, cheapest-route cascade, defaultGateway fallback, ACK tracking. Called from the service layer, but also directly from routing components (relay forwarding, DHT gossip).

The old v2.2 API `node.sendEnvelope(envelope, recipientNodeId)` with its overloaded, type-undifferentiated identifier parameter no longer exists in V3.0. All call sites have been migrated (see §15.3 Service Layer API + §23.3 Code Migration Map).

---
## 3. Identity & Cryptography

Cleona identities are cryptographic keypairs — without email, phone number, or central verification. V3.0 explicitly separates two identity classes that were often mixed in v2.2: **UserID** (stable cross-device identity, what the app UI presents to a user as a "contact") and **DeviceID** (physical hosting of an identity on a concrete device, what the mesh routing requires). Each has its own Sig-Keypair, its own crypto responsibilities, and its own lifecycle.

This separation is the cryptographic foundation of the 2-Layer wire format from §2: Outer-Frames are Device-signed (routing authenticity), Inner-Frames are User-signed (identity authenticity).

### 3.1 Identity Model (UserID vs DeviceID)

**UserID** (or "User Identity") represents a person, i.e. a logical identity that the UI maps to a contact. A UserID can be hosted on multiple devices (Multi-Device, §7), and a single daemon can host multiple UserIDs concurrently (Multi-Identity, §3.6).

```
userId = SHA-256(network_secret || ed25519_user_pubkey)    // 32 bytes
```

UserID properties:
- **Stable**: persists across device changes, recovery, and Multi-Device additions
- **Network-scoped**: differs between Beta and Live (different `network_secret`)
- **Identity-claims**: User-Sig-Keypair (see §3.4) signs ApplicationFrames in the Inner Layer
- **Recoverable**: 24-word phrase or Restore-Broadcast (§6) regenerates the User-Keys

**DeviceID** represents a concrete daemon instance on a concrete device. A phone daemon is one DeviceID. A desktop daemon is a different DeviceID. If user Alice runs her account on three devices, there are three DeviceIDs for the single UserID Alice.

**Multi-Identity is a User-Layer property, not a Device-Layer property.** A daemon hosting N UserIDs (e.g. cleona2 hosting Bob + Charly) has exactly **one** DeviceID. The DeviceID is computed from the daemon-global Device-Sig keypair (`~/.cleona/device_keys.enc`, see §3.5/§3.5b/§3.7) and is independent of any UserID. All hosted identities share the same DeviceID for routing; the User-Layer dispatch (which identity the inbound frame belongs to) happens after Inner KEM-decap by recipient User-KEM-SK, not from the Outer routing header.

```
deviceId = SHA-256(network_secret || ed25519_device_pubkey)    // 32 bytes
```

DeviceID properties:
- **Per-Device**: freshly generated on first daemon start, never shared between devices
- **Routing identifier**: Kademlia-Buckets are keyed by deviceId, DV-Routing operates on deviceIds
- **Device-claims**: Device-Sig-Keypair (see §3.5) signs NetworkPackets in the Outer Layer
- **Non-recoverable**: when a device is lost, the DeviceID is freshly created during setup on the replacement device — that is acceptable because the UserID stays stable and Device-Revocation (§7.4) removes the old device entry from the Auth-Manifest

**Authorization relationship** (central for the 2D-DHT, §4.3):

A UserID holds an **Auth-Manifest** in the DHT (key `Hash("auth"||userId)`). The manifest is hybrid User-signed and contains the list of `authorizedDeviceIds` for that UserID. Only devices in this list are permitted to publish Liveness-Records for the UserID. This gives the sender, on resolver lookup, a trusted list of "which devices currently host this user".

```
Auth-Manifest (KEM v2 inside DHT-record):
{
  userId:               bytes (32),
  authorizedDeviceIds:  [bytes (32), ...],     // 1..N devices hosting this UserID
  ttl:                  uint64,                 // 24h
  seq:                  uint64,                 // replay protection
  publishedAtMs:        uint64,
  ed25519Sig:           bytes (64),             // User-Sig hybrid
  mlDsaSig:             bytes (3300)
}
```

**Terminology hygiene** in v3.0:
- When the spec mentions **userId**, the User-Identity is meant — this is the ID carried in the Inner Frame (`recipientUserId`, `senderUserId`) and what application code calls a "contact" in the UI.
- When the spec mentions **deviceId**, the Device routing ID is meant — this is the ID carried in the Outer Frame (`nextHopDeviceId`, `senderDeviceId`) and used by DV-Routing.
- The historical v2.2 term "nodeId" is **avoided** in v3.0 because it carried both meanings, which is exactly how the v2.2 ID-Mismatch bug arose. In code migration (§23.3) all `nodeId` sites are explicitly renamed to either `userId` or `deviceId`.

### 3.2 Cryptographic Primitives

Cleona uses exclusively audited, established primitives from two C libraries via FFI:

| Library | Primitives | Use |
|---|---|---|
| **libsodium** (1.0.20+) | Ed25519, X25519, ChaCha20-Poly1305, XSalsa20-Poly1305, BLAKE2b, SHA-256, HMAC-SHA-256, HKDF | Classical crypto + DB-Encryption |
| **liboqs** (0.10+) | ML-KEM-768 (FIPS 203), ML-DSA-65 (FIPS 204) | Post-Quantum layer |

Rationale for this selection:
- libsodium has ~12 years of audit history and is the standard for modern crypto applications
- liboqs is the NIST PQC reference implementation and receives regular updates in lockstep with the NIST standards
- ML-KEM-768 is NIST-Level-3 (192-bit Quantum-Security), ML-DSA-65 is Level-3 (192-bit Quantum-Security)
- Both PQ algorithms have been FIPS-standardized since 2024 — they are not experimental

Deliberate exclusions:
- **No TLS** as a crypto layer (TLS is used only as a transport fallback, §4.1). E2E encryption must reach end to end from sender to recipient; TLS only covers sender-to-relay.
- **No Double Ratchet** (Signal Protocol). Avoids session-state complexity (desync, loss of forward secrecy on state corruption). Replaced by stateless Per-Message KEM (§3.3).
- **No RSA, no ECDSA with secp256k1**. Ed25519 is more modern, faster, and less side-channel-prone.
- **No AES-CBC, AES-CTR**. ChaCha20-Poly1305 is AEAD, integrates the MAC, and is faster on ARM without AES-NI.

### 3.3 Per-Message KEM (X25519+ML-KEM-768 hybrid v2)

Cleona's E2E encryption mechanism. Every application message carries its own ephemeral key setup — no session state, no desync risk.

**Hybrid KEM = X25519 + ML-KEM-768 combined**:
- Sender generates an ephemeral X25519 keypair
- Sender encapsulates against the recipient's X25519 pubkey → `x25519_ct` (32 bytes) + `x25519_shared` (32 bytes)
- Sender encapsulates against the recipient's ML-KEM-768 pubkey → `mlkem_ct` (1088 bytes) + `mlkem_shared` (32 bytes)
- Combined key: `combined = HKDF-SHA-256(x25519_shared || mlkem_shared, salt, info)`
- AEAD encrypt: `aead_ct = ChaCha20-Poly1305(combined, nonce, plaintext)`

Recipient:
- Decapsulates with own X25519 private key → `x25519_shared`
- Decapsulates with own ML-KEM-768 private key → `mlkem_shared`
- Reconstructs combined → AEAD decrypt

**Security**: even if a quantum computer breaks X25519 in 10 years, ML-KEM-768 remains secure. Even if ML-KEM-768 is broken due to an implementation flaw or a new attack, X25519 remains secure. The attacker must break **both simultaneously**.

**HKDF salt v2 (Sec H-5)**:
```
salt = SHA-256("cleona-per-message-kem/salt/v2")    // 32 bytes
info = "cleona-msg-v2"                              // ASCII
```

V3.0 keeps KEM v2 unchanged. Sec H-5 v2 was deployed only at the start of May 2026; there is no reason for an immediate v3 bump.

**Wire format of the KEM header** (carried as `payload` in the Inner ApplicationFrame):

```
PerMessageKem {
  uint32  version         = 5;   // 2 (Sec H-5 v2)
  bytes   x25519Ct        = 1;   // 32 bytes
  bytes   mlKemCt         = 2;   // 1088 bytes
  bytes   aeadNonce       = 4;   // 12 bytes
  bytes   aeadCt          = 3;   // ciphertext + 16-byte AEAD tag
}
```

**Per-message overhead** (Inner-Frame level, before Outer-Wrap):

| Component | Size |
|---|---|
| KEM header (x25519_ct + mlkem_ct + nonce + tag) | 1148 bytes |
| zstd-compressed ApplicationFrame body | variable |
| **Inner overhead total (KEM)** | **1148 bytes** |

Plus User-Sig (in the Inner): 64 bytes Ed25519 + ~3300 bytes ML-DSA-65 = ~3364 bytes. Total Inner overhead per ApplicationFrame with hybrid sig: **~4500 bytes**.

**Versioning** (Sec H-5):
- Sender stamps the KEM with a `version` field
- Receiver accepts only `version ∈ acceptKemVersions = {2}`
- On mismatch: silent drop without DELIVERY_RECEIPT (no bounce, no reputation strike)
- The hard-block update mechanism (§19.5.7) enforces minRequiredVersion at security cuts

**Encryption Exceptions** (Inner-Frame KEM is skipped or replaced):
- **Live-Call frames** (CALL_AUDIO, CALL_VIDEO): the Inner carries AES-GCM under `call_key` (per-CallSession ephemeral) instead of the User-KEM. Rationale in §10.3.
- **DHT-Infrastructure frames** (PEER_LIST_PUSH, AUTH/LIVE_PUBLISH/RETRIEVE, FRAGMENT_*): the Outer carries these directly as application-untyped packets, no KEM (records are self-validating via their own sigs).
- **Routing probes** (HOLE_PUNCH_*, REACHABILITY_*, ROUTE_UPDATE, RELAY_ACK, DELIVERY_RECEIPT): no KEM, not user-attributed.

**PQ Key Recovery After Device Loss**: because User-Keys are recoverable via the Recovery-Phrase (§6.1), the recipient can replay the KEM decryption of older messages after device loss. Restore-Broadcast (§6.3) re-delivers the messages from contacts.

### 3.4 User Identity Sigs (Ed25519+ML-DSA-65 hybrid)

Every user holds a **User-Sig-Keypair** that carries the authenticity of the User-Identity at the Inner-Frame layer. Hybrid: Ed25519 for performance and long-standing audit trust, ML-DSA-65 for PQ security.

**Use**:
- Signs the ApplicationFrame in the Inner Layer (fields `userEd25519Sig` + `userMlDsaSig`)
- Signs the Auth-Manifest in the 2D-DHT (§4.3)
- Signs identity claims (profile updates, identity-deletion broadcasts, Restore-Broadcasts)

**Pubkey format**:
- Ed25519 pubkey: 32 bytes
- ML-DSA-65 pubkey: 1952 bytes
- Stored together in `Contact` records (profile picture, display name, etc.; see §8.3)

**Sig sizes** (per Inner Frame):
- Ed25519: 64 bytes (signs the ApplicationFrame bytes preceding the User-Sig fields)
- ML-DSA-65: ~3300 bytes

**Hybrid verification**: the recipient checks both sigs individually. Acceptance only when **both** are valid. The combined sig is therefore not weaker than the weaker of the two algorithms.

**Key generation**: derived from the 24-word recovery seed via HD-Wallet-Derivation (§3.6).

**Key rotation**: User-Keys explicitly do not rotate (it would break identity stability). On compromise: Identity-Deletion + create a new identity (§3.9 for retention of the verification level via trusted-contact re-verification).

### 3.5 Device Identity Sigs (Ed25519+ML-DSA-65 hybrid)

**NEW in V3.0.** Every device holds its own **Device-Sig-Keypair** that carries the authenticity of the routing device at the Outer-Frame layer. Hybrid for application traffic, Ed25519-only for infrastructure.

**Rationale for separation from User-Sigs**:
- Routing-layer operations (Outer-Sig on a NetworkPacket) must **not** leak the UserID — a relay sees only the DeviceID, not which users live on the device
- Device compromise (e.g. a stolen phone) should be remediable without User re-setup — the Device-Sig-Key is disposable, the User-Sig-Key is not
- §7.4 Device-Revocation removes the DeviceID from the Auth-Manifest without touching the User-Identity

**Use**:
- Signs the NetworkPacket in the Outer Layer (fields `deviceEd25519Sig` + optional `deviceMlDsaSig`)
- Signs the Liveness-Record in the 2D-DHT (§4.3)
- The recipient retrieves the Device-Pubkey from the Auth-Manifest (which is in the DHT and hybrid User-signed) — trust chain: the User-Sig on the Auth-Manifest authenticates the list of allowed DeviceIDs, and each DeviceID entry contains the Device-Pubkeys.

**Pubkey format**:
- Ed25519 pubkey: 32 bytes
- ML-DSA-65 pubkey: 1952 bytes
- Associated with the DeviceID inside the Auth-Manifest

**Sig sizes**:
- Ed25519: 64 bytes (always)
- ML-DSA-65: ~3300 bytes (only on application frames)

**Selectivity — hybrid vs. Ed25519-only**:

Hybrid (Ed25519 + ML-DSA-65) for:
- Application frames: all MessageTypes except those explicitly Ed25519-only
- Examples: TEXT, MEDIA_*, REACTION, CONTACT_REQUEST, GROUP_*, CHANNEL_*, CALENDAR_*, POLL_*

Ed25519-only for (bandwidth conservation — these frames are frequent):
- DHT-Infrastructure: AUTH/LIVE_PUBLISH/RETRIEVE, FRAGMENT_*, PEER_*, IDENTITY_*
- Routing probes: HOLE_PUNCH_*, REACHABILITY_*, ROUTE_UPDATE
- Live-Calls: CALL_AUDIO, CALL_VIDEO, CALL_RTT_PING/PONG, CALL_GROUP_*
- ACKs: DELIVERY_RECEIPT, RELAY_ACK
- Heartbeats: TYPING_INDICATOR, READ_RECEIPT (status updates with low value for PQ protection)

**Bandwidth rationale**: ML-DSA-65 is ~3.3 KB per sig. A live-call audio session sends ~50 frames/second. Hybrid would mean ~165 KB/s per direction for sigs alone — unacceptable. Ed25519 is 64 bytes, ~3.2 KB/s — tolerable.

**Security argument**: Ed25519-only Outer-Sig protects against classical forgeries. A PQ forgery on Ed25519-only frames would let an attacker forge routing frames — the resulting damage is bandwidth waste (the receiver drops on Inner decrypt because the User-KEM/Sig does not match), not identity takeover. An acceptable trade-off for live calls and infrastructure.

**Key generation**: locally generated on the device using cryptographic randomness (NOT derived from the User-Master-Seed). See §3.6 #5 for the security rationale: device-key independence ensures that a seed compromise does not retroactively compromise old devices, and that recovery on a replacement device produces a fresh, distinct DeviceID that can be authorized via §7.1 without leaking the old device's signing material.

**Key rotation**: once at device setup. On device loss: the old device is removed from the Auth-Manifest via §7.4, and new Device-Keys are freshly generated on the replacement device.

**PeerInfo PK cache layout (Welle 3, 2026-05-08)**: receivers cache the sender's signing PKs in `PeerInfo` for Outer-Sig-Verify. Two distinct fields are required because the User-Sig PK and Device-Sig PK serve disjoint purposes:

| Field | Source | Used for |
|---|---|---|
| `ed25519PublicKey` / `mlDsaPublicKey` | User-Sig keypair (seed-derived, identity-wide, identical across all of the user's devices) | Mailbox-ID derivation (§3.2 `mailboxId = SHA-256("mailbox" \|\| ed25519_pk)`), CR/CRR sig verify, contact resolution |
| `deviceEd25519PublicKey` / `deviceMlDsaPublicKey` | Device-Sig keypair (per-device, persisted in `device_keys.enc`) | Outer `NetworkPacketV3.device_sig` verify (§2.4 step 4) |

Both pairs are populated from the same authenticated channels (self-broadcast `PEER_LIST_PUSH`, `KEY_ROTATION_BROADCAST`) and share a single `pkSource` flag — they always come from the same provenance event and are versioned together. `verifyOuterDeviceSig` MUST consult the Device-Sig fields exclusively; mixing User-Sig PK into a Device-Sig verify is a guaranteed mismatch and was the root cause of the `0× V3 BOOT recv` deadlock observed pre-Welle-3.

### 3.5b Device KEM Keypair (X25519 + ML-KEM-768 hybrid)

**NEW in V3.0 Welle 5.** Every device additionally holds a **Device-KEM-Keypair** as the cryptographic subject for operations addressed to a *device* rather than a *user*. This is the third KEM subject in V3.0, complementing the existing User-KEM-Keypair (Inner Identity Layer, §3.3) and the Device-Sig-Keypair (Outer Routing Layer, §3.5).

**Use cases**:

1. **Infrastructure-Frame KEM** (§2.3.5) — DHT pings, routing probes, NAT/hole-punch, reachability queries, peer-list gossip, fragment storage, S&F on mutual peers, 2D-DHT identity-resolution operations. Sender encapsulates under recipient Device-KEM-PK; recipient decapsulates with Device-KEM-PrivKey.
2. **First-Contact-Request bootstrap** (§8.1.1) — when Alice scans Bob's ContactSeed she knows his DeviceID and Device-KEM-PK (from the URI), but not yet his User-KEM-PK (which she only learns from CONTACT_REQUEST_RESPONSE). The CONTACT_REQUEST itself is therefore wrapped as `InfrastructureFrame.payload` (KEM under Bob's Device-KEM-PK), with Alice's full user-signed ApplicationFrame carried as the inner payload.
3. **Onion routing** (§2.5, future) — the per-hop KEM subject that makes the onion-hook structurally tragfähig. Without a Device-KEM-Keypair the §2.5 onion construction had no concrete cryptographic subject.

**Rationale for separation from User-KEM-Keypair**:

- Operations addressed to a device must not require a UserID context — DHT operations, routing, NAT traversal happen below the identity layer.
- A user can host multiple identities on one device (Multi-Identity §3.6), but DHT operations are device-scoped; binding them to a specific UserID would leak which identity initiated which infrastructure call.
- Lifecycle: Device-KEM lives and dies with the device; analogous to the Device-Sig keypair (§3.5).
- Onion-routing security relies on each hop being able to decrypt without consulting any user context.

**Pubkey format**:

- X25519 KEM-pubkey: 32 bytes
- ML-KEM-768 KEM-pubkey: 1184 bytes
- Stored together with the Device-Sig keys in the device key container (§3.7)

**Distribution**:

- Inside the **DeviceKemRecord** in the 2D-DHT (§4.3 — separate record with 24h TTL, storage-key `SHA-256("kem" || userId || deviceId)`)
- Inside the **ContactSeed URI** (§8.1.1) for First-Contact-Request bootstrap, parameters `dxk` (X25519) + `dmk` (ML-KEM-768)
- Cached in the local routing table once a `ResolvedDevice` has been observed

**Key generation**: locally on the device using cryptographic randomness (NOT derived from the User-Master-Seed). The same rationale as §3.5 applies: device-key independence ensures that a seed compromise does not retroactively compromise the device's KEM state. See §3.6 #5 for the unified explanation that covers both Sig and KEM device keys.

**Key rotation**: once at device setup. On device loss, the old device is removed from the AuthManifest via §7.4 Device-Revocation. The DeviceKemRecord becomes implicitly invalid because the resolver-cascade filters by AuthManifest membership (§4.3 step 5) — even if a stale DeviceKemRecord lingers in the DHT, it is rejected by the receiver because the deviceId is no longer authorized.

### 3.6 Multi-Identity HD-Wallet Derivation

Every User-Identity is based on a 32-byte Master-Seed (derived from the 24-word Recovery-Phrase). **All** Cleona keys are deterministically derived from the Master-Seed — Multi-Identity, Multi-Device, all Sig-Keys, all KEM-Keys.

**HD-Wallet schema** (analogous to BIP-32, adapted to Cleona):

```
master_seed (32 bytes, from 24-word phrase via PBKDF2-SHA-512, 4096 rounds)
├── m/identity/0     → User-Identity 1 (e.g. "Alice")
│   ├── m/identity/0/ed25519_user      → User Ed25519 keypair
│   ├── m/identity/0/mldsa_user        → User ML-DSA-65 keypair
│   ├── m/identity/0/x25519_user       → User X25519 keypair (KEM receive)
│   ├── m/identity/0/mlkem_user        → User ML-KEM-768 keypair (KEM receive)
│   └── m/identity/0/db_key            → DB-Encryption-Key for this identity
├── m/identity/1     → User-Identity 2 (e.g. "AllyCat")
│   └── ... (same schema)
├── m/identity/N     → User-Identity N+1
│   └── ...
└── m/device         → Device-specific, NOT seed-derived (locally generated)
    ├── ed25519_device                  → Device Ed25519 sig keypair (NEW in v3.0)
    ├── mldsa_device                    → Device ML-DSA-65 sig keypair (NEW in v3.0)
    ├── x25519_device                   → Device X25519 KEM keypair (NEW in v3.0 Welle 5, §3.5b)
    └── mlkem_device                    → Device ML-KEM-768 KEM keypair (NEW in v3.0 Welle 5, §3.5b)
```

**Important properties**:

1. **Seed recovery regenerates User-Keys, not Device-Keys.** The 24-word phrase regenerates all User-Identities and their keys via deterministic HD-Wallet derivation. Device-Keys are freshly created on the replacement device — that is acceptable because the DeviceID is a routing identifier, not an identity subject. Restore-Broadcast (§6.3) carries the UserID identity, and Device-Authorization-Update (§7.1) registers the new DeviceID in the Auth-Manifest.

2. **Multi-Identity is deterministically derivable.** When a user starts on a replacement device with the same seed, the same N identities can be recreated.

3. **`Identity Registry` (erasure-coded in the DHT, §6.4)** stores the list of User-Identities together with display names and profile pictures. During recovery the user fetches this list and decides which identities to reconstruct on the replacement device (sometimes only 1 of 5 is desired).

4. **Identity-Deletion** (§8.4) removes an identity permanently — the next derivation at `m/identity/N` for that index is mapped differently (or the index is skipped). An Identity-Deleted-Broadcast notifies contacts.

5. **The `m/device` branch is NOT seed-derived** — Device-Keys (both Sig and KEM) are generated locally with a cryptographic randomness source. This is the explicit decision so that the Device-Identity is not derivable from the Recovery-Phrase: a seed compromise must not retroactively compromise old devices, neither for Sig (impersonation as the device) nor for KEM (decryption of past or pending Infrastructure-Frames or onion-routed payloads addressed to the device's KEM-PK).

### 3.7 Key Storage

**On-disk layout** (per Cleona daemon profile):

```
~/.cleona/                                    (Linux)
%APPDATA%/Cleona/                             (Windows)
files/.cleona/                                (Android, in app-private storage)

  master_seed.enc                             # Master-Seed, keyring-encrypted (Linux/Windows: libsecret/DPAPI; Android: KeyStore)
  device_keys.enc                             # Device Sig (Ed25519+ML-DSA-65) + Device KEM (X25519+ML-KEM-768) private keys, separately keyring-encrypted
  identities/
    0/
      identity_meta.json.enc                  # display name, profile picture, display settings, FileEncryption-encrypted
      identity_db.sqlite.enc                  # conversations, messages, contacts (DB-Encryption per §3.8)
      identity_resolution_state.json.enc      # AuthManifest-seq, Liveness-seq, RecoverAuthSeq (FileEncryption)
    1/
      ... (same schema)
  routing_table.json.enc                      # shared across identities (DeviceID-keyed)
  network_secret.enc                          # Beta vs. Live config
```

**Key cascade**:
1. The **OS keyring** protects `master_seed.enc` and `device_keys.enc` (which contains both the Device-Sig keypairs Ed25519+ML-DSA-65 and the Device-KEM keypairs X25519+ML-KEM-768; see §3.5 + §3.5b). On Linux: libsecret (GNOME Keyring / KWallet). On Windows: DPAPI (CurrentUser scope). On Android: AndroidKeyStore with a biometric/device-credential gate.
2. The **Master-Seed** is held in RAM after daemon start (in a protected memory region via libsodium `sodium_mlock`).
3. **HD-Wallet derivation** (§3.6) generates all further keys on demand — the private keys live only in protected memory.
4. The **DB-Encryption-Key** is derived from the User-Identity Ed25519 private key (§3.8).
5. The **FileEncryption-Key** for `identity_meta.json.enc` and `identity_resolution_state.json.enc` is derived separately from the Master-Seed (`m/identity/N/file_enc_key`).

**Memory hygiene**:
- libsodium `sodium_mlock` prevents swap-out of the keys
- private keys are actively overwritten with `sodium_memzero` after use (e.g. after KEM decapsulation)
- pubkeys live in normal heap (no secret)

**Secret-Rotation** (§13.2): network_secret may be rotated by the maintainer. The daemon holds a dual-secret window during the transition phase.

### 3.8 Database Encryption

All persistent data in `identity_db.sqlite.enc` is encrypted before write and decrypted on read. SQLite sees only ciphertext — no SQLCipher plugin is required.

**Algorithm**: XSalsa20-Poly1305 (libsodium `crypto_secretbox`)
- 192-bit nonce (random per write)
- 256-bit key (see key derivation below)
- AEAD: encrypts and authenticates simultaneously

**Key derivation**:
```
db_key = SHA-256(ed25519_user_sk || "cleona-db-key-v1")    // 32 bytes
```

The DB-Key is therefore:
- unique per UserIdentity
- deterministically derivable from the User private key
- not directly persisted on the filesystem (derived in-memory at every daemon start)
- regenerable via Recovery-Phrase (the User private key is seed-derived, hence so is the DB-Key)

**File format**:
```
[12-byte salt prefix]                  // once per file
[8-byte chunk count]                   // number of chunks that follow
[chunk 1: 8-byte nonce | 4-byte len | encrypted payload]
[chunk 2: ...]
...
```

Chunks of ~64 KB so that partial reads are possible without decrypting the whole file. Sidecar recovery via `.tmp` and `.old` analogous to `AtomicJsonWriter` (see §14.3 for details).

**What is NOT encrypted**:
- `routing_table.json.enc` — encrypted with FileEncryption (NOT DB-Encryption — it belongs to shared state, not to the User-Identity)
- log files (`~/.cleona/logs/cleona_*.log`) — not encrypted because they are debug output. Sensitive data (private keys, plaintext content) is redacted by the logger.

### 3.9 Contact Verification & Key Rotation

**Verification levels** (4 stages per contact):

| Level | Meaning | Visual cue in the UI |
|---|---|---|
| **unverified** | the contact exists, but key authenticity has never been checked | standard avatar, no badge |
| **seen** | we have had this contact at least once on a direct send path (implicit key use) | weak badge |
| **verified** | the user has actively compared the Sig-Pubkey fingerprint with the contact offline (Quishing or QR-Code scan) | green badge |
| **trusted** | the user has explicitly marked the contact as "trusted" (e.g. family, close friends) | double badge |

Verification is **per UserID** — when a contact changes devices (e.g. a new phone), the verification level is preserved because the UserID is stable.

**Key-Change-Detection**:
For `verified` and `trusted`, Cleona stores a `verifiedKeyFingerprint` = SHA-256(ed25519_user_pk). If the pubkey received from the contact no longer matches this fingerprint, a **Key-Change-Warning** is shown in the chat:

> ⚠ Bob's identity key has changed. This may be an identity reset or a man-in-the-middle attempt. Please verify the new key offline.

The verification level is reset to `unverified` until the user actively re-verifies.

**KEX Gate (§8.2)**: ApplicationFrames received from **unknown** senders (no entry in the `Contact` store) are silently dropped. This prevents spam from random senders. Only explicit Contact-Requests (§8.1) are the permitted first contacts.

**Profile-Picture and display name** are synchronized as a sub-step of Contact-Update (§8.3 Identity Updates & Profile Sync).

**Wire-layer note:** The transport for `KEY_ROTATION_BROADCAST` (Emergency-variant) and `RESTORE_BROADCAST` is the **InfrastructureFrame** path (§2.4.1) since V3.0 Welle 6 — see §7.4 (Emergency Key Rotation) and §6.3 (Restore Broadcast) for the rationale. Periodic KEM-only `KEY_ROTATION` continues on the regular ApplicationFrame path because no signature key changes.

---
## 4. Network Architecture

Cleona's mesh topology combines a Kademlia DHT for discovery, Distance-Vector routing for multi-hop paths, and a 2D-DHT (identity resolution) for the user-to-device mapping. All three components operate exclusively on the **DeviceID axis** — UserIDs are an identity-layer concern and do not belong in routing code (see §3.1 for the terminology hygiene).

### 4.1 Communication Port (UDP+TLS Single-Port)

Cleona nodes communicate over **a single UDP port per daemon** that additionally accepts TLS frames as a fallback. At the kernel level, UDP (SOCK_DGRAM) and TCP (SOCK_STREAM) share the port number without conflict — they are two separate sockets.

**Port assignment:**
- **Bootstrap nodes**: UDP+TCP 8080 (live channel), 8081 (beta channel)
- **Mobile/desktop daemons**: a random port in `[1024, 65535]`, fixed on first start and persisted in `~/.cleona/`. It remains stable across daemon restarts — important for NAT hole punching and for stored routing-table entries.

**Protocol Escalation** (order applied as payload size or unreliability grows):
1. **UDP single-shot** (default): payload ≤ 1200 bytes → one UDP packet
2. **UDP fragmented + NACK retry**: payload > 1200 bytes → app-level fragmentation (max 255 fragments, Fragment-NACK CFNK §5.8)
3. **TLS on the same port** (fallback): after 15 consecutive UDP failures or on anti-censorship indicators → TLS frame instead of UDP datagram

TLS serves exclusively as a **transport fallback** for reachability — the end-to-end encryption (KEM layer) is unaffected. TLS provides no additional security, only additional reachability against operator DPI filters.

### 4.2 DHT (Kademlia, Closed Network)

Cleona uses a Kademlia DHT as the backbone for peer discovery, mailbox lookup, erasure-coded fragment storage, and 2D-DHT identity resolution. Kademlia was chosen for its O(log n) routing, natural redundancy via k-bucket replication, and long-standing use in BitTorrent, IPFS, and Ethereum.

**DHT address space**: 256-bit, identical key space as DeviceIDs and Mailbox IDs.

**k-bucket configuration**: 256 buckets (one per XOR-distance bit), with ~20 entries per bucket.

**Closed Network authentication**: every DHT operation is authenticated by the HMAC in the outer frame (§4.10). Nodes without the `network_secret` can neither perform DHT operations nor interpret responses.

**Kademlia operations in v3.0**:

| Operation | Key type | Value type | Purpose |
|---|---|---|---|
| `findClosestPeers(key)` | DeviceID hash or any 256-bit key | list of DeviceIDs | routing lookup, K=10 closest |
| `store(key, value)` | Mailbox-ID, Auth-Manifest key, Liveness key, Fragment key | bytes | replicator operation for mailbox / 2D-DHT / erasure |
| `retrieve(key)` | as for `store` | bytes | lookup operation |
| `pingPong(deviceId)` | DeviceID | reachability + RTT | liveness checks |

**Replication factor**: K=10 (Kademlia convention). DHT records survive the loss of 9 replicator nodes, which remains safe for small mesh sizes (10–100 nodes).

**Eviction**: standard Kademlia rules — the oldest bucket entry is pinged and replaced by a new one on timeout.

### 4.3 Identity Resolution (2D-DHT)

Identity resolution answers the question: *"which devices currently host this UserID?"* — it is the **first** step on every user-addressed send path (see §5.1). It runs **before** the routing layer, not intermixed with it.

**Three-lookup steps** in the 2D-DHT:

1. **Auth-Manifest lookup** (long-lived, 24h TTL):
   ```
   key = SHA-256("auth" || userId)
   value = AuthManifest { userId, authorizedDeviceIds[], ttl=24h, seq, ed25519Sig, mlDsaSig }
   ```
   - hybrid-signed by the user's master keypair
   - refreshed every 20h by the IdentityPublisher (see §3.4)
   - returns the list of `authorizedDeviceIds` for this user

2. **Liveness-record lookup per device** (short-lived, adaptive 15min/1h):
   ```
   key = SHA-256("live" || userId || deviceId)
   value = LivenessRecord { userId, deviceId, currentAddresses[], ttl, seq, ed25519Sig }
   ```
   - signed Ed25519-only by the user key
   - refreshed every 15 min (foreground) or 1 h (background)
   - returns the current addresses for this device

3. **DeviceKem-record lookup per device** (long-lived, 24h TTL — NEW in V3.0 Welle 5):
   ```
   key = SHA-256("kem" || userId || deviceId)
   value = DeviceKemRecord { userId, deviceId, deviceX25519Pk, deviceMlKemPk,
                             ttl=24h, seq, publishedAtMs, ed25519Sig, userEd25519Pk }
   ```
   - signed by the user master Ed25519 key (same trust anchor as AuthManifest — the user vouches for the device's KEM-PK)
   - refreshed every 20h by the IdentityPublisher (parallel to AuthManifest)
   - returns the device's KEM pubkey set, sufficient for KEM-encap when sending an InfrastructureFrame to this device (§2.3.5)
   - **separated from LivenessRecord** because Device-KEM-PK changes only at device-key-reset (multi-year cadence) while Liveness must refresh every 15 min — different lifecycles. Co-locating them would re-publish the KEM-PK every 15 min for no semantic gain

**Resolution cascade** (in IdentityResolver, `lib/core/identity_resolution/identity_resolver.dart`):

```
resolve(userId) → List<ResolvedDevice>:

  1. Cache hit? routingTable._byUserIdHex[userId] fresh < 1h?
     → for each cached device, populate `deviceX25519Pk` /
       `deviceMlKemPk` / `deviceKemPublishedAtMs` from the local
       `IdentityDhtHandler` (this node may be a replicator for the
       target's DeviceKemRecord, or be the publisher itself via
       self-store — see "Publisher self-store" below).
     → if every cached device has KEM populated: return cached
       devices, no DHT lookup needed.
     → if any cached device is missing KEM: fall through to step 2
       (DHT lookup) so the caller is not stuck with a no-KEM result
       that fails First-CR via `firstCrPickDeviceKem` (§8.1.1).

  2. Auth-Manifest lookup:
     authKey = SHA-256("auth" + userId)
     replicators = kademlia.findClosestPeers(authKey, count=10)
     responses = parallel kademlia.retrieve(authKey) on each replicator
     authManifest = highest-seq AuthManifest from responses
     if none found: return []  ← Empty result triggers offline-delivery (§5.5/§5.6)

     **Wire-path**: each `kademlia.retrieve` call sends an
     `IDENTITY_AUTH_RETRIEVE` request via the BOOTSTRAP_INFRASTRUCTURE_FRAME
     pipeline (§2.4.1a) — replicator's Device-KEM-PK is unknown at this point,
     so KEM-encryption is impossible. The Auth-Manifest reply carries its own
     hybrid Ed25519+ML-DSA signature (verified in step 3 below).

  3. Sig-Verify Auth-Manifest:
     ed25519.verify(authManifest, userMasterEd25519Pubkey)
     mlDsa.verify(authManifest, userMasterMlDsaPubkey)
     if either fails: skip this manifest

  4. Liveness lookup per authorized device (parallel):
     for each deviceId in authManifest.authorizedDeviceIds:
       liveKey = SHA-256("live" + userId + deviceId)
       replicators = kademlia.findClosestPeers(liveKey, count=10)
       responses = parallel retrieve
       liveness = highest-seq LivenessRecord
       if no liveness: addresses=[], device returned with empty addresses
                      (sender will still attempt via DV routing)

     **Wire-path**: BOOTSTRAP_INFRASTRUCTURE_FRAME (§2.4.1a). The LivenessRecord
     reply is Ed25519-signed by the user key.

  4b. DeviceKem lookup per authorized device (parallel with step 4):
      for each deviceId in authManifest.authorizedDeviceIds:
        kemKey = SHA-256("kem" + userId + deviceId)
        replicators = kademlia.findClosestPeers(kemKey, count=10)
        responses = parallel retrieve
        deviceKem = highest-seq DeviceKemRecord
        verify ed25519Sig with userEd25519Pk (must match userMasterEd25519Pubkey from step 3)
        if no kem record / verify-fail:
          deviceX25519Pk=null, deviceMlKemPk=null in result
          (InfrastructureFrame-send to this device is impossible until DeviceKemRecord
           publishes; ApplicationFrame-send is unaffected — User-KEM-PK comes from
           AuthManifest)

      **Wire-path**: BOOTSTRAP_INFRASTRUCTURE_FRAME (§2.4.1a). This is the
      definitional bootstrap RPC — its very purpose is to obtain the Device-KEM-PK
      that subsequent KEM-path InfrastructureFrames will encrypt to. The
      DeviceKemRecord reply is Ed25519-signed by the user master key (same
      trust anchor as the Auth-Manifest, see §3.5b).

  5. Authorized filter:
     reject any LivenessRecord/DeviceKemRecord whose deviceId not in
     authManifest.authorizedDeviceIds

  6. Cache populate:
     routingTable.addPeer for each device with non-empty addresses
     routingTable.addDeviceKem for each device with non-null KEM pubkeys

  7. Return List<ResolvedDevice>
```

**Publisher cold-start semantics** (V3.0 Welle 5 — small-network correctness): the IdentityPublisher does NOT gate on a hard peer-count threshold. Instead:

1. **Burst-grace** (1s): poll the routing table at 100ms; if `peerCount >= peerThreshold (5)` mid-poll, publish immediately to the K-closest set (best case — the LAN multicast burst delivered the full neighbourhood before we publish).
2. **Single-peer fallback**: after the burst-grace expires, if at least one peer is reachable, publish anyway. `findClosestPeers(K=10)` returns `min(K, available)` — a single-peer publish is well-defined.
3. **Re-publish on join**: every `onPeerJoined()` callback while `peerCount < peerThreshold` re-broadcasts the current Liveness record so newly-arrived peers also receive a replica without waiting for the 15-min refresh tick.
4. **Cold-zero retry**: if no peer is reachable after the full `coldStartTimeout` (30s), schedule a 60s retry; the timer is superseded by `onPeerJoined()` when the first peer arrives.

`peerThreshold = 5` is no longer a hard publish gate but a "sufficient-redundancy goal". Small LANs and 2-node test setups MUST be able to publish identity records — otherwise resolution stalls indefinitely.

**Publisher self-store**: the publisher persists every Auth-Manifest / LivenessRecord / DeviceKemRecord it broadcasts into the local IdentityDhtHandler before sending to the K-closest replicators. Standard Kademlia convention publishes records to the K-closest peers including the publisher when it ranks among the K-closest; an explicit self-store makes this invariant uniform across small networks (where the publisher *always* ranks closest to its own dht-keys) and avoids the silent gap where a 2-node cluster has the records nowhere — the only candidate replicator (`findClosestPeers` returns the *other* peer, not self) is the publisher itself, but it never stored its own record.

**Liveness-publish receiver-side routability** (V3.0 Welle 5 — multi-device correctness): on receiving an `IDENTITY_LIVE_PUBLISH`, the node also seeds the routing table (`routingTable.addPeer`) and DV-routing (`dvRouting.addDirectNeighbor`) with the announced `(deviceNodeId, addresses)` tuple. Without this hop, a freshly-paired sibling device of a contact (e.g. Alice's newly-added phone joining her existing desktop) would resolve via the AuthManifest but have no routing path until the next Kademlia bucket-refresh. Seeding from the Liveness publish closes that gap immediately. (Note: in V3.0 Welle 5 this was incorrectly motivated by a multi-identity case — that motivation became obsolete with the Multi-Identity DeviceID refactor (§3.1), where all hosted identities of a daemon share one DeviceID.)

**API contract** (V3.0):
```dart
class IdentityResolver {
  Future<List<ResolvedDevice>> resolveUserToDevices(Uint8List userId);
}

class ResolvedDevice {
  final Uint8List deviceId;
  final List<PeerAddress> addresses;
  final int livenessPublishedAtMs;

  // NEW in V3.0 Welle 5 — Device-KEM pubkeys for InfrastructureFrame KEM-encap.
  // Null when no DeviceKemRecord was found (older device, or pre-Welle-5 build).
  // Sender then cannot send InfrastructureFrame to this device but can still send
  // ApplicationFrame (User-KEM-PK comes from AuthManifest, not DeviceKemRecord).
  final Uint8List? deviceX25519Pk;
  final Uint8List? deviceMlKemPk;
  final int? deviceKemPublishedAtMs;
}
```

**Important**: `resolveUserToDevices` always takes a UserID. If the caller already has a DeviceID it does not invoke the resolver at all — routing operates directly on the DeviceID. The ID-type-mismatch bug from v2.2 is therefore structurally excluded.

**Callers**: only `service.sendToUser(envelope, userId)` (see §15.3) invokes the resolver. Routing-internal operations (DV updates, relay forwarding, hole-punch) never deal with UserIDs and do not need the resolver.

**Inflight dedup**: two concurrent `resolveUserToDevices(sameUserId)` calls both wait on the result of the first — preventing RPC spam during burst sends.

**Threat model for Ed25519-only liveness**: the auth manifest carries identity authenticity (PQ-secure). Liveness is transient transport-only — a PQ forgery yields a wrong address, not an identity takeover. The sender detects forgery during the KEM-setup roundtrip with the user pubkey from the hybrid-signed auth manifest. The forgery window is bounded by the liveness TTL, at most 1 h.

**Storage**: replicator-side persistence in `~/.cleona/identity_dht_storage.json.enc` (FileEncryption, see §14.2). Crash recovery via `.tmp`/`.old` sidecars.

### 4.4 Routing (Distance-Vector V3, sendToDevice API)

Cleona's routing layer operates exclusively on **DeviceIDs**. The routing table stores routes per destination device, with multi-path support (multiple routes per device, sorted by cost).

**Distance-Vector protocol** (Bellman-Ford, adapted to P2P):

- **Route entry**: `{destination: DeviceID, nextHop: DeviceID?, hopCount: int, cost: int, connectionType: enum, lastConfirmed: Instant}`
- **Cost model** (link-cost table):

  | Link type | Cost |
  |---|---|
  | LAN same-subnet | 1 |
  | LAN other-subnet | 2 |
  | WiFi Direct | 3 |
  | Public UDP | 5 |
  | Hole Punch | 5 |
  | Relay | 10 |
  | Mobile | 20 |
  | Mobile via Relay | 30 |

  Total route cost = sum of all link costs along the path.

- **Updates are event-driven**: on every `PEER_LIST_PUSH`, `ROUTE_UPDATE`, `RELAY_ACK`, routes are updated. There is no periodic refresh apart from a safety net (1×/hour full exchange).
- **Receive-side `_touchPeer`**: every successfully verified incoming V3 packet calls `_touchPeer(senderDeviceId, from.address, fromPort)` immediately after `dvRouting.addDirectNeighbor`. This keeps `routingTable` (peer info + addresses) and `dvRouting._neighbors` in sync regardless of the discovery channel (LAN multicast, cross-subnet unicast scan, third-party `PEER_LIST_PUSH`) — without it, cross-subnet peers would land in `dvRouting` but never in `routingTable`, leaving the send cascade with `routes=0` despite a "DV: New neighbor" log line.
- **Split Horizon**: routes are NOT advertised back to the neighbor they were learned from.
- **Poison Reverse**: when a route fails, it is advertised with `cost=65535` (infinity) to all neighbors — accelerating loop detection.

**Route-down detection** (RUDP Light, §5.8):
- After 3 consecutive `DELIVERY_RECEIPT` timeouts, a specific route is marked DOWN.
- **Surgical**: only the specific route via a concrete `nextHop`, not all routes to the device. If alternative routes exist, the device remains reachable.
- **Recovery**: dead routes stay 5 minutes in the table (`cost=infinity`) — they can be revived by new neighbor updates.

**Three-Tier Capacity** (max ~2,140 routing entries):

| Tier | Max | Contents | Eviction |
|---|---|---|---|
| Contact routes | 1000 | direct contacts | NEVER evicted |
| Transit routes | ~640 | Kademlia bucket entries | standard Kademlia rules |
| Channel routes | 500 | channel subscribers | LRU + highest cost |

**`node.sendToDevice()` API** (V3.0 canonical):

```dart
class CleonaNode {
  /// Pure routing operation. Sender knows the deviceId from the previous
  /// IdentityResolver lookup (§4.3) or from a direct DeviceID-based
  /// invocation (e.g. relay forwarding, DHT-RPC, Hole-Punch coordination).
  Future<bool> sendToDevice(NetworkPacket packet, Uint8List deviceId);
}
```

**Cascade in `sendToDevice`**:

```
sendToDevice(packet, deviceId):
  routes = routingTable.routesFor(deviceId)  // sorted by cost ascending
  for route in routes:
    success = _attemptDelivery(packet, route, maxRetries=3)
    if success: return true
    // ACK timeout 8s direct, ~16s relay (RTT-based), surgical mark route DOWN
  // All learned routes exhausted — try defaultGateway as last resort
  defaultGw = dvRouting.defaultGatewayHex
  if defaultGw != null && defaultGw != deviceId:
    gwPeer = routingTable.getPeerByDeviceId(hexToBytes(defaultGw))
    if gwPeer != null:
      success = _sendViaNextHop(packet, deviceId, gwPeer, maxRetries=3)
      if success: return true
  // No path worked — return failure. Caller decides next step.
  return false
```

**Important**: when `sendToDevice` returns `false`, the sender has tried every available path including the default gateway. The caller (typically `service.sendToUser`) then decides on the failover path: erasure-coded S&F on mutual peers (§5.5) plus a mailbox entry (§5.6) for receiver pull-up.

**MessageQueue no longer exists.** v2.2's MessageQueue retried the same send for 7 days. v3.0 stops after cascade exhaustion. The receiver pulls offline messages from the mailbox itself.

**Loading & pruning** (two-phase startup):
- Phase 1: pure deserialization of `routing_table.json.enc` — all peers are loaded, regardless of age.
- Phase 2: the caller (`CleonaNode.start()`) invokes `prune(maxAge: 2h)` separately.
- Safety net: if the 2h prune would remove **all** peers, the table is re-loaded without pruning.

**Maintenance pruning**: a scheduled run every 15 minutes prunes peers older than 4h. (The previous 60s tick was overkill — the prune target itself ages 4h+, and 15 minutes is granular enough.)

**Preference**: `findClosestPeers()` partitions into "recent" (< 10 min) and "stale", preferring recent peers by XOR distance. DHT/resolution lookups select by **age and XOR distance only** — they are **not** filtered by `direct-confirmed` (the V3.1.71 `defaultPeerFilter = isPeerConfirmed` is removed in V3.1.72: it broke first-contact identity resolution, which must reach replicators chosen by distance, not by whether we recently heard from them directly).

**Periodic-Operations Inventory** (V3.0 — event-driven where possible):

| Mechanism | Frequency | Network traffic? | Replaceable by event? |
|---|---|---|---|
| Maintenance prune | 15 min | none (internal only) | no — bounded internal scan, fine as a low-rate timer |
| Peer-Exchange tick (legacy 120 s) | **removed** | — | yes, replaced by event triggers (below) |
| DV Safety-Net + liveness heartbeat | 1 h | full `ROUTE_UPDATE` to all neighbours, a piggy-backed slim `PEER_LIST_PUSH` (Self-Broadcast) per §5.10.5 cold-path, **and a gate-bypassing liveness-PING sweep to all known peers — incl. LAN/IPv6/same-WAN — via the direct `_sendInfraDirect` path (jittered), refreshing `direct-confirmed` (§4.6)** | partially — once-per-hour backstop; the PING sweep is the **sole periodic refresh** of direct-confirmed for non-NAT peers, which `UdpKeepalive` deliberately does not cover (V3.1.72) |

**Event triggers replacing the periodic Peer-Exchange tick**:

1. **New-neighbor event** — when `_touchPeer` reports `isNewNeighbor=true` for an incoming sender, the node fires one slim `PEER_LIST_PUSH` to its **confirmed** neighbours only (shuffled, 200 ms spacing per peer, §4.4 confirmed-peer gate) so the mesh learns the new peer immediately. Unconfirmed peers are skipped — they pull via Mesh-Refresh when they come back online. Logged as `§5.11: new-peer-event → broadcasting PEER_LIST_PUSH to N neighbors (200ms jitter)`.
2. **Identity-rotation event** — on local signing-key rotation (`_performKeyRotation`, `rotateIdentityKeys`, `_handleTwinSettingsChanged`), the service calls `node.broadcastAddressUpdate()` which fires one slim firstParty `PEER_LIST_PUSH` (Self-Broadcast, 200 ms jitter per peer) to all known peers. This lets every peer's stale-PK cache heal under §5.10.5 — see §5.10.2 hot path for the receive-side mechanism.

The replacement is not a 1:1 mapping — the old 120 s tick produced ~30 `PEER_LIST_SUMMARY` per hour per node regardless of whether anything had changed. The event triggers fire only when there is something to report. Measured reduction in periodic chatter: ~30× (from ~30/h to ~1/h via the safety-net piggy-back).

**Slim PEER_LIST_PUSH and on-demand PQ-key fetch** (V3.1.71):

All `PEER_LIST_PUSH` paths (new-neighbor, address-update, safety-net, `_pushSelfToPeer`) now serialize `PeerInfoProto` in **slim** mode: the five PQ key/signature fields (`ml_dsa_pk` 1952 B, `ml_kem_pk` 1184 B, `x25519_pk` 32 B, `device_ml_dsa_pk` 1952 B, `ml_dsa_sig` 3309 B) are omitted. Instead, a `key_fingerprint` field (32 B, `SHA-256(ed25519_pk ‖ ml_dsa_pk ‖ x25519_pk ‖ ml_kem_pk ‖ device_ed25519_pk ‖ device_ml_dsa_pk)`) is included so the receiver can detect key changes without the full material.

Result: a slim PeerInfoProto is ~450 B — fits in a single UDP datagram (MTU 1200 B) without app-level fragmentation. The previous full PeerInfoProto was ~8,800 B = 8 UDP fragments per push. Under congestion (e.g. 20-node simultaneous startup), fragment-loss triggered NACK-retransmit spirals.

**On-demand PQ-key fetch**: when the receiver processes a slim `PEER_LIST_PUSH` and detects that the sender's PQ keys are missing from its cache **or** the received `key_fingerprint` differs from the locally computed fingerprint, it sends a `PEER_KEY_REQUEST` (empty payload, BOOT path) to the sender. The sender responds with a `PEER_KEY_RESPONSE` carrying the full `PeerInfoProto` (including all PQ keys) for each hosted identity. Cooldown: max 1 request per peer per 60 s.

**Push jitter**: both `_pushSelfToNeighborsExcept` and `_broadcastAddressUpdate` filter to confirmed peers (§4.4), shuffle the list, and space sends at 200 ms per peer. Combined with the 0–3 s cold-start jitter (§4.5), this limits the peak burst rate even when many nodes join simultaneously.

The PEER_LIST_WANT → PEER_LIST_PUSH response path (`_handlePeerListWantInfra`) continues to deliver **full** PeerInfoProto — the WANT is an explicit key-material request and the response must carry the complete PQ keys.

### 4.5 Mesh Discovery

Cleona nodes find each other through several discovery channels running in parallel. No BLE (presence leakage, eclipse attack).

**Discovery channels**:

| Channel | Mechanism | Use case |
|---|---|---|
| **IPv4 Broadcast** | UDP broadcast 255.255.255.255 on the local subnet | LAN, same subnet |
| **IPv4 Multicast** | 239.192.67.76, TTL=4 | LAN, cross-subnet with IGMP snooping |
| **IPv6 Multicast** | ff02::1 (link-local) + ff15::cleona (site-local) | LAN, IPv6-only networks |
| **NFC** | pairing bump between two devices | first introduction, contact exchange |
| **QR code** | device pubkey + addresses encoded as QR | visual pairing path |
| **ContactSeed URI** | `cleona://...` link, copy/paste | sharing via email or messenger |

**Discovery burst**: 3× in parallel on all channels, then silence. No periodic repetition — Cleona is not a heartbeat system.

**Cold-start jitter**: when `_finishStart()` runs (after Kademlia bootstrap or quick-start), the node delays 0–3 s (uniform random) before firing its first peer-exchange and address-broadcast round. This staggers the O(N²) `PEER_LIST_PUSH` cascade that occurs when many nodes boot simultaneously (e.g. a mod-lab cluster or power-cycle event). Without jitter, 20 simultaneous nodes produce ~35,000 UDP packets in <10 s — enough to congest a consumer-grade router and trigger fragment-NACK retransmit spirals.

**Subnet-scan fallback**: if 0 peers are found after the burst, a unicast probe over the /16 subnet (port 41338) is used as a last resort.

#### 4.5.2 Native UDP Send Path (libcleona_net)

LAN-Discovery's send path on Linux and Windows desktop runs through a small C library, **`libcleona_net`**, instead of Dart's built-in `RawDatagramSocket.send()`. The shim wraps the host operating system's native UDP send call — `sendto()` from POSIX on Linux, `WSASendTo()` from WinSock2 on Windows — and exposes a tiny synchronous API to Dart through FFI. This subsection explains why the indirection was necessary, what exactly the shim does and does not do, how it behaves when something is wrong, and what the consequences are for receive, security, and other platforms.

**The reason this exists at all.** When Cleona has no known peer addresses on startup, `LocalDiscovery` enters a subnet-scan phase that probes the local /16 network at /24 resolution, sending one CLEO discovery datagram per host at roughly 500 packets per second. On Linux this completes in roughly 130 seconds and finds same-host neighbours and seed bootstraps reliably. On Windows the same code completes in the same wall-clock time but only about 11 percent of the issued sends actually leave the host — pktmon counters at the Windows TCPIP layer confirm that the dropped sends never reach the kernel network stack. Raising the kernel send buffer to 4 MB does not change the drop rate. The defect therefore lives in Dart's Windows I/O implementation, specifically in the IOCP-based UDP send routine that the VM substitutes for the simpler POSIX path. PowerShell's `.NET UdpClient` doing the equivalent work shows zero drops, which both proves the underlying network can carry the traffic and gives us a reference for what "correct" looks like. The C shim adopts the `.NET UdpClient` strategy: each `cleona_udp_send` call invokes `WSASendTo` synchronously and returns either the number of bytes sent or a negative error code, with no IOCP queueing layer between the Dart caller and the kernel.

**What the shim does.** A single C source file under `native/cleona_net/` exposes four functions: open a UDP socket bound to a given local port, configure send and receive buffer sizes, send one datagram to a destination IP and port (returning the byte count or a negative error), and close the socket. The Dart side wraps each function in a small `dart:ffi` binding under `lib/core/network/native_udp_sender.dart`. `LocalDiscovery` holds one `NativeUdpSender` instance for the lifetime of the daemon, opened against the well-known discovery port 41338. The shim is **send-only** — no recv, no select, no epoll. Receive remains in Dart's `RawDatagramSocket.listen()` callback as before, because the receive path has no observable defect on any platform we tested.

**What the shim does not do.** It does not wrap multicast group membership management, broadcast permission flags, or the routing-related socket options that LocalDiscovery already configures on the Dart-owned listening socket. Both sockets — the Dart-owned receive socket and the shim-owned send socket — are bound to the same local port 41338 using `SO_REUSEADDR` (Linux/Windows) so that they can coexist; multicast group membership remains on the Dart socket where the listener actually reads incoming traffic. The shim is purely a syscall conduit for outgoing datagrams.

**What happens when something is wrong.** The shim is a hard dependency on Linux x86_64 and Windows x86_64 desktop builds. On daemon startup, if the dynamic library cannot be opened — file missing from the bundle, wrong CPU architecture, broken build — the daemon logs a single explicit error line that names the expected library path (`libcleona_net.so` or `cleona_net.dll`) and exits with a non-zero status. There is **no fallback to the Dart send path**. We considered a fallback and rejected it: a silent fallback would mask exactly the conditions we built the shim to fix — broken builds, missed deployment steps, or platform mismatches would all manifest as "subnet-scan still drops 89 percent of sends" and operations would look indistinguishable from the un-shimmed state. The architectural fix would then risk being declared "useless" and reverted, when in reality the shim simply was not being used. By failing closed at startup we make this class of failure visible and immediate.

**Security model.** The shim sees raw UDP datagrams that the rest of Cleona has already constructed — CLEO discovery probes (38 bytes including magic) for the LAN-Discovery send path, no other payload types. The shim performs no cryptography, validates no headers, and has no awareness of the Closed-Network HMAC framing (§4.10) — that wrapping happens above the FFI seam on the Dart side. The C source has no parsing, no allocation past the per-call buffer, and no state beyond the socket handle. The trusted native code surface introduced by this shim is therefore small and self-contained.

**Build and deployment.** The C source lives under `native/cleona_net/` with a CMakeLists.txt that produces `libcleona_net.so` on Linux and `cleona_net.dll` on Windows. Linux builds are bundled into the Flutter Linux release alongside `libcleona_audio.so`; Windows builds drop into `build/windows/x64/runner/Release/` next to `libsodium.dll`. Android, iOS, and macOS desktop builds skip the shim entirely — those platforms continue to use Dart's `RawDatagramSocket` directly, with no functional regression observed. Phase 2 may extend the shim to other platforms if a measurable drop pattern is later observed there.

**Peer-list format** (carried in the PEER_LIST_PUSH application frame):

```protobuf
message PeerListEntry {
  bytes        deviceId           = 1;
  repeated PeerAddressProto addresses = 2;
  uint64       lastSeenMs         = 3;
  uint64       ageHours           = 4;     // RoutingTable age, hint for pruning
  ConnectionType connectionType   = 5;
}
```

**Peer-list exchange**: on every new peer (`onPeerJoined` hook), a PEER_LIST_PUSH containing the local node's top-N peers (sorted by `lastSeen` recency) is sent.

**Active vs. passive discovery**:
- **Passive**: runs continuously in the background (broadcast/multicast listeners), no user action.
- **Active**: user-triggered (NFC bump, QR scan, ContactSeed paste, manual peer entry).

### 4.6 NAT Traversal & Reachability

Cleona nodes behind NATs must make themselves mutually reachable. Cleona combines several techniques in parallel:

**Public-address discovery**:
- **STUN-style PingPong**: node A pings the bootstrap, the bootstrap replies "I see you from 1.2.3.4:39874". The node updates its own `publicIp/publicPort` field.
- **UPnP-IGD**: if active on the router, automatic port forwarding (for 1h, then re-claim).
- **PCP/NAT-PMP**: modern UPnP successor.
- **NAT-egress observation** (§4.6.4): cross-class private allowed — if the bootstrap sees a private source IP (e.g. from an AVM emulator NAT), it is accepted as observed IP when no local IP in the same class exists.

**Connection strategies** (order tried when sending to a peer):

1. Same-subnet LAN address (private IPv4 in the local /24)
2. Other-subnet LAN address (private IPv4 in another /24, RFC 1918)
3. Public IPv6 (when both sender and receiver have global IPv6)
4. Public IPv4 + UPnP hole
5. Hole-punched UDP (coordinated via the bootstrap as rendezvous)
6. Mobile-direct (when sender/receiver are on mobile CGNAT, often does not work)
7. Relay (multi-hop via DV routing)

**Active UDP Hole Punch** (V3):
- The coordinator (bootstrap or mutual peer) sends `HOLE_PUNCH_NOTIFY` to both endpoints simultaneously.
- Both endpoints send `HOLE_PUNCH_PING` to each other's observed IP.
- The NAT mapping opens on both sides → communication becomes possible.

**Keepalive** (`UdpKeepalive`, §4.6.4): every 20s a HOLE_PUNCH_PING is sent to each **confirmed** NAT-traversal peer to maintain carrier-NAT pinholes. Registration gate (`_needsKeepalive`): IPv6 peers are never registered (no NAT in standard IPv6), private-IPv4 peers are never registered (LAN-reachable), public-IPv4 peers sharing the node's own WAN IP are never registered (behind same NAT). Newly registered peers start **unconfirmed** and receive at most 3 pings; a PONG promotes to **confirmed** (= successful NAT traversal, pinged indefinitely). Unconfirmed peers that exhaust their attempts are **suspended** until a network-change event resets them. After 3 consecutive rounds where all active (non-suspended) peers fail to PONG, `onAllPeersFailed` triggers a full network-change cycle (5-min cooldown). Peers that fail ≥5 consecutive rounds are excluded from the quorum (structurally unreachable). (V3.1.71) **NAT-keepalive (pinhole maintenance, cross-NAT public-IPv4 only) is distinct from the confirmation heartbeat (§4.4): the IPv6/private-LAN/same-WAN exclusions here apply *only* to pinhole maintenance — `direct-confirmed` for those peer types is refreshed by the once-per-hour liveness-PING sweep instead. (V3.1.72)**

**Address priority by type**:

| Priority | Address type | Latency / reliability |
|---|---|---|
| 1 | Same-subnet LAN | < 1ms, very reliable |
| 2 | Other-subnet LAN | < 5ms, reliable |
| 3 | Public IPv6 (global) | 10–50ms, reliable |
| 4 | Public IPv4 (UPnP) | 10–50ms, mostly reliable |
| 5 | Hole-punched | 50–100ms, NAT-dependent |
| 6 | Mobile-direct | 100–500ms, frequently CGNAT-blocked |
| 7 | Relay | additive (sum of links) |

**Backoff per address**: on failure, a specific address is deprioritized with exponential backoff (5s → 30s → 5min) — not the entire PeerInfo. Multi-address devices retain routing options through other addresses.

**Relay route learning** (V3 — ACK-based):
- When peer A is unreachable through all direct addresses, the sender attempts multi-hop relay via the DV cascade.
- On successful delivery (RELAY_ACK), the relay route is stored as "learned" with cost = sum of links.
- Future sends use this route directly, without a fresh discovery.
- No timer-based expiry — only ACK failure marks a route as down.

**Reachability states** (V3.1.72): a peer has **three** orthogonal, per-node states. Conflating them was the V3.1.71 regression that broke first-contact and idle delivery.

1. **direct-confirmed** — `_confirmedPeers` map: timestamp of the last *direct* (hopCount == 0) packet received from the peer; valid for **1 hour** (TTL). Refreshed by *any* directly-received packet (incl. PONG, DELIVERY_RECEIPT) and by the once-per-hour liveness-PING sweep on the DV Safety-Net (§4.4). It is an **inbound** observation ("I recently heard directly from X") and only a *hint* — not proof — that the *outbound* direct path works (asymmetric NAT).
2. **reachable** — an alive DV route exists, **direct or via relay** (`Route.isAlive`, `dvRouting.hasAliveRouteTo`). This is the deliverability state.
3. **delivered** — `Route.ackConfirmed`: a DELIVERY_RECEIPT (RUDP-Light) returned over the route. The only *proof* of outbound reachability; supersedes the heuristics and drives address scoring and "route DOWN" detection.

**Which state gates which decision:**

| Decision | Gated by |
|---|---|
| Put a packet on the wire at all — `_sendV3ViaHop`, relay-forward intake | **reachable** (alive route, direct *or* relay) |
| "Try direct before relay" ordering | direct-confirmed |
| NAT-keepalive registration (§4.6.4) | direct-confirmed + peer type |
| Proactive *periodic* direct gossip — `_broadcastAddressUpdate`, `_pushSelfToNeighborsExcept` | direct-confirmed |

**The send and relay-forward paths gate on _reachable_, not _direct-confirmed_.** A peer reachable only via relay (CGNAT, or a never-before-heard first-contact target) must still receive user- and routing-initiated traffic. First-contact (no route yet) is **not** a drop: the cascade attempts the ContactSeed addresses directly **and** relays via the seed peers, and RUDP-Light decides delivery. The idle-traffic savings come from gating *proactive periodic* traffic (the gossip rows above) and from RUDP-Light deciding delivery — **not** from refusing to send real messages. When an offline peer reboots, it still pulls updates via the Mesh-Refresh path (PEER_LIST_SUMMARY → PEER_LIST_WANT → PEER_LIST_PUSH).

> **V3.1.71 regression (fixed in V3.1.72):** the four V3.1.71 gates used *direct-confirmed* to suppress **all** outbound, including `_sendV3ViaHop` and relay-forward. This silently dropped (a) every first-contact CR to an as-yet-unconfirmed target, and (b) the first message to any established LAN/IPv6 peer that had been idle > TTL — because the idle-traffic elimination simultaneously removed the keepalive that kept those peer types confirmed. The send/relay decision now uses *reachable*; *direct-confirmed* gates only proactive periodic direct traffic.

### 4.7 IPv6 Dual-Stack & CGNAT Bypass

V3.0 nodes operate **dual-stack** (IPv4 + IPv6 in parallel). IPv6 is increasingly important because of DS-Lite and CGNAT at mobile carriers.

**Problem: DS-Lite and CGNAT**:
- Carriers (especially mobile in DE) hand out only a shared CGNAT IPv4 plus a global IPv6.
- IPv4-direct is usually impossible inside CGNAT (source-NAT mappings are under operator control).
- IPv6-direct is trivial — every device has its own global IPv6.

**Solution: IPv6 as primary transport** when both endpoints have global IPv6:

- The sender checks: does the local node have a global IPv6? does the receiver have a global IPv6 in the liveness record?
- If yes: try IPv6 first (address priority 3, ahead of IPv4-UPnP).
- IPv6 reachability check: `PeerAddress.isReachableFromCurrentNetwork` checks for at least one global IPv6 (excluding fe80/fec0/fc/fd/::1/ff*).

**IPv4 CGNAT bypass techniques**:
- UPnP (when the router is IPv4 and the user has port-forwarding permission)
- Coordinated hole punch (rarely successful with symmetric NAT)
- Port prediction for symmetric NAT (heuristic)
- Mobile fallback socket (§4.6.4): after 15 consecutive sendUdp failures → all non-LAN traffic is shifted onto the mobile socket.

**Bridging architecture** (dual-stack nodes as IPv4↔IPv6 bridges):
- A node with both IPv4 and global IPv6 automatically becomes a bridge between IPv4-only and IPv6-only nodes.
- When sender (IPv4-only) and receiver (IPv6-only) share mutual peers via a dual-stack node, multi-hop relay implicitly acts as a bridge.

**Bootstrap IPv6 reachability**: bootstrap nodes have a statically configured global IPv6 (e.g. via OPNsense VIP). This guarantees bootstrap reachability even in DS-Lite scenarios.

### 4.8 Bootstrap Node

Bootstrap nodes are **accelerators for initial mesh discovery**, not central servers. The Cleona mesh works without them once enough peers know each other.

**Concept**: well-known long-running nodes with stable addresses that serve as the initial anchor for fresh daemon starts.

**Functions**:
- Reply to DhtPing with their own peer list (PEER_LIST_PUSH).
- Replicator for mailbox lookups, auth-manifest replication, and erasure-coded fragments.
- Hole-punch coordinator for other nodes (mediating UDP mappings).
- Relay hub for multi-hop paths (ChannelMessage forwarding).

**Protocol**: bootstrap nodes are functionally **identical** to any other Cleona daemon — there is no special bootstrap API. They distinguish themselves only by stable long-running deployment; fresh daemons reach them through the same Discovery channels every other peer uses (LAN multicast/broadcast burst, IPv4-Multicast 239.192.67.76 with TTL=4 cross-subnet via IGMP-capable routers, IPv6-Multicast, Subnet-Scan-Fallback on the local /16, or `cleona://`-ContactSeed URI handed out via QR/NFC/email). There is **no** hardcoded bootstrap anchor file in the daemon — neither a `bootstrap_seeds.json` nor a `--bootstrap-peer` CLI flag (both removed in V3.0 as architectural inconsistencies; see §4.10 Closed-Network Model and the `docs/NETWORK.md` discovery channels).

*A section is omitted from the public edition.*


**Decommission criteria**: bootstrap nodes will **no longer be used** once the network is self-sustaining:
- ≥10 stable nodes per channel
- ≥30 days of stability without bootstrap intervention
- Mesh discovery operates self-organizing through peer lists

Until then, bootstrap nodes are the initial single-point-of-failure — if they are down, fresh daemon starts cannot enter the mesh.

**Bootstrap resilience**: stored routing-table entries (after pruning at §4.4) are kept across restarts and re-touched at startup so the daemon doesn't have to re-discover its known mesh from scratch. If the persisted routing table is empty (fresh install) or pruned to zero (long offline), Discovery falls back to the architected channels — LAN burst, Subnet-Scan, ContactSeed import.

### 4.9 Network Change Detection

Mobile devices change networks frequently: WiFi → mobile, new WiFi, VPN toggle, etc. Cleona reacts to such changes with re-discovery and a liveness republish.

**Detection mechanisms**:
- **Platform-API subscriptions**: Android `ConnectivityManager` callbacks, Linux `NetworkManager` D-Bus signals, Windows `INetworkListManager`.
- **Periodic polling fallback**: every 30s, re-read the local addresses via `getAllLocalIps()` and compare against the last state.
- **Network tag**: an HMAC mismatch on incoming packets can hint at a network change (an old network cache is still alive).

**Recovery actions on a network change**:
1. Retry public-IP discovery via STUN/UPnP.
2. Liveness republish (debounced 5s, see §3.5/§4.3).
3. Soft-reset of the routing table: stale routes get a mark-stale flag, prune after 30s.
4. Topology-aware keepalive filter: ignore keepalives from old WLAN peers when in mobile-only mode.
5. Re-ping the bootstrap (no re-discovery — the bootstrap entry is kept).
6. Drain the send queue (S&F pull, mailbox pull) — new messages may arrive on the new addresses.

**Topology-aware keepalive filter**: mobile-only devices ignore keepalives from WLAN peers when the WLAN has been switched. This prevents stale WLAN addresses from staying "alive" in the cache.

**Routing-table audit on daemon start**: on every start `auditAddresses(currentLocalIps)` runs — pruning carrier-NAT addresses (100.64.0.0/10 RFC 6598, 192.0.0.0/24). All RFC 1918 private IPv4 are kept when the local node itself is on a private network (cross-subnet private peers are L3-routable via the gateway). Public IPv4 + IPv6 are kept (score-decay handles staleness).

**Tunnel-IPv6 filter**: Teredo (2001::/32), 6to4 (2002::/16), Documentation (2001:db8::/32), and IPv4-mapped (::ffff:0:0/96) are filtered out during local address iteration. This prevents a Windows Teredo tunnel flap from triggering a soft reset.

#### 4.9.1 DV-Routing Persistence

The Distance-Vector table (`DvRoutingTable._neighbors`, `_routes`, `_defaultGatewayHex`, `_relayConfirmedNeighbors`) is persisted to `dv_routing.json` in the profile directory and reloaded on daemon start. Without this, every restart loses the topology learned in the previous session: the daemon would see `peers=N` (loaded from `routing_table.json`) but `cascade exhausted (routes=0)` for every send, until a fresh authenticated V3 receive from each peer rebuilds `_neighbors` from scratch via `addDirectNeighbor` (§4.4 receive-side hook). For nodes behind NATs whose peers expect *us* to ping first, that gap is observably fatal — the peer never gets a packet because we have no route, and we never learn a route because the peer never pings.

**Snapshot points** (mirror the routing-table cadence):
- Periodic maintenance (`Maintenance.run`): right after `_saveRoutingTable()`.
- Clean shutdown (`stop()`): right after `_saveRoutingTable()`, before `transport.stop()`.

**Crash window**: a process crash between the two snapshot writes can leave a `dv_routing.json` referencing nodeIds no longer in `routing_table.json`. `loadFromJson` tolerates this — orphan routes simply expire via the 30 s prune sweep below.

**Boot-load semantics — every loaded route is marked stale:**

`DvRoutingTable.loadFromJson` is **not** a verbatim restore. The post-load state is identical to what the soft-reset path produces: every route gets `isStale = true` and a `+5` cost penalty via `markAllRoutesStale()`. This has two effects:

1. **Soft-floor on trust** — a freshly revalidated route after boot (via incoming `DELIVERY_RECEIPT`, `PONG`, or DV-update) immediately wins the cost comparison against the loaded version.
2. **Self-healing prune** — `_loadDvRouting` schedules the same 30 s `pruneStaleRoutes` sweep that `onNetworkChanged` already wires for live network-change events. Routes whose `lastConfirmed` is not refreshed within the deadline disappear, restoring exactly the prior end-state of a soft-reset.

The two flows (soft-reset on network change, boot-load from disk) thus converge on the same code path; the only difference is the trigger.

**Tier registries are NOT persisted**: `_contactIds` and `_channelMemberIds` are repopulated on service start from `contacts.json.enc` and the channel registry via `dv.registerContact` / `dv.registerChannelMember` (`cleona_service.dart`). A duplicate snapshot in `dv_routing.json` would only invite drift between the two sources of truth.

**File format**: plain JSON, unencrypted (same threat model as `routing_table.json` — the local FS is trusted, an attacker with disk access has bigger problems than the routing topology). Schema:

```json
{
  "neighbors": { "<deviceIdHex>": "<ConnectionType.name>", ... },
  "routes": {
    "<destHex>": [
      { "destination": "<hex>", "nextHop": "<hex|absent>",
        "hopCount": N, "cost": N, "type": "direct|relay",
        "lastConfirmed": <ms>, "connType": "<name>",
        "consecutiveFailures": N, "ackConfirmed": <bool> },
      ...
    ], ...
  },
  "defaultGatewayHex": "<hex>",
  "relayConfirmedNeighbors": [ "<hex>", ... ]
}
```

`Route.cost` is stored *without* the stale-penalty (`cost - _stalenessPenalty`) so repeated stale cycles across restarts don't accumulate penalty on penalty.

### 4.10 Closed Network Model & HMAC

Cleona is a **Closed Network** — only official Cleona builds participate in the network. Forks or third-party implementations without the `network_secret` see no one on the network and are seen by no one.

**Rationale**: not anti-competitive, but security-driven:
- **Anti-Sybil**: an attacker with a self-built client cannot operate fake nodes en masse.
- **Anti-pollution**: no spam, no incompatible wire-format variant in the mesh.
- **Updates remain controllable**: the maintainer can cut off old versions through secret rotation (§13.2).

**Network-secret derivation**:

```
network_secret = HKDF-SHA-256(
    salt    = "cleona-network-secret-v1",
    ikm     = ed25519_sign(maintainer_sk, network_channel),
    info    = network_channel,    // "live" or "beta"
    length  = 16 bytes
)
```

- `maintainer_sk` is the maintainer's private key (Ed25519); only the maintainer has access.
- The maintainer signs the `network_channel` string — the signature is deterministic (Ed25519 is deterministic).
- HKDF derives a 16-byte secret.

This means:
- The maintainer can reproducibly generate the secret.
- Nobody else can derive it (they don't know `maintainer_sk`).
- Beta and live have different secrets (different `info` tag in HKDF).

**Network tag in NetworkPacket** (§2.2):

```
networkTag = HMAC-SHA256-128(network_secret, frame_bytes_minus_networkTag_field)
```

- 128-bit output (= 16 bytes) — sufficient for MAC security and compact.
- The receiver computes the HMAC with its own `network_secret` and compares.
- Mismatch → silent drop, **no** logging (avoids side-channel info leak).

**Node-ID derivation** is also secret-dependent (see §3.1):

```
deviceId = SHA-256(network_secret || ed25519_device_pubkey)
userId   = SHA-256(network_secret || ed25519_user_pubkey)
```

This places nodes with different `network_secret` values in entirely separate DHT address spaces — they cannot find each other even if they had identical pubkeys.

**Packet-level authentication** (centralized in the outer NetworkPacket, §2.2):

| Protection | Mechanism | Position |
|---|---|---|
| Closed-network filter | HMAC-SHA256-128(network_secret, ...) | NetworkPacket.networkTag |
| Routing authenticity | hybrid device signature Ed25519+ML-DSA | NetworkPacket.deviceEd25519Sig + .deviceMlDsaSig |
| Anti-replay | timestamp window 60s | NetworkPacket.timestampMs |
| Anti-spam | PoW (selective) | NetworkPacket.pow |

**Defense in depth**: HMAC is the first filter stage (rejected without sig-verify, without KEM decap, cheap). Only after the HMAC passes are the device signature and the replay window checked. Only then comes the routing decision or KEM decap.

**Secret rotation**: see §13.2.

**Obfuscation**: the network secret is not embedded in the binary as a plaintext constant — it is derived at runtime from the maintainer key, which itself is reconstructed from `assets/cleona_maintainer_public.pem` (public) and an app-internal salt slot. This is not crypto-secure (anyone with reverse-engineering can extract it), but it raises the bar for trivial forks (e.g. decompile + recompile) — they have to actively modify the secret-derivation path, which is plainly recognizable as tampering.

**Threat-model addendum — confidentiality of routing metadata** (V3.0 BOOT-subset, §2.4.1a):

The §2.3.5 BOOT-subset RPCs (DHT bootstrap, 2D-DHT identity-resolution lookups, peer-list gossip, NAT/hole-punch, reachability probes, DV-route updates) intentionally waive Inner-frame confidentiality. The HMAC layer guarantees Closed-Network membership; inner record signatures (where applicable) guarantee owner-bound authenticity. **Insider visibility of routing metadata is by design** — a DHT cannot function if its participants cannot read the lookup queries they are supposed to answer. KEM-encrypting these RPCs in the original V3 design hid metadata only from passive on-path observers, while the active DHT peers — who are by definition Closed-Network insiders — saw the metadata anyway after their own KEM-decap. The cryptographic effort therefore protected against a threat that is not in scope (passive on-path observation by an entity that already passed the HMAC filter is not modeled).

**What stays confidential against insiders** (always KEM-encrypted, never on BOOT-path):

- All user-content frames (TEXT, MEDIA_*, GROUP_*, CHANNEL_*, CALL_*, CALENDAR_*, POLL_*, REACTION, EDIT, DELETE, READ_RECEIPT, TYPING_INDICATOR, etc. — the entire ApplicationFrame path, §2.4.1).
- Fragment-storage and S&F payloads (FRAGMENT_*, PEER_STORE/RETRIEVE) — they carry user-content fragments.
- Relay-forward payloads (RELAY_FORWARD, RELAY_ACK) — they tunnel ApplicationFrames through intermediate hops.
- Identity-layer security broadcasts (RESTORE_BROADCAST, KEY_ROTATION_BROADCAST) — sender-identity-bound state changes that benefit from layered confidentiality even within the closed network.

**What is insider-visible by design** (BOOT-path, see §2.3.5 path-annotations):

- Which devices are alive and reachable at which addresses (LivenessRecord lookups).
- Which devices are authorized for which user (Auth-Manifest lookups).
- The Kademlia routing topology (PING/FIND_NODE).
- The Distance-Vector route table (ROUTE_UPDATE).

This visibility is identical to V2's behaviour and was implicitly accepted there. V3.0 makes it explicit, so future readers can audit the trade-off rather than rediscover it as a regression.

---
## 5. Message Delivery

Cleona's delivery pipeline runs as a **Three-Layer Cascade**: identity resolution provides the target devices, routing attempts each device, and on failure S&F+Mailbox takes over for offline delivery. The sender stops once the cascade is exhausted — there is no longer an indefinite MessageQueue retry.

### 5.1 Three-Layer Delivery Pattern

This is the **canonical send path** in V3.0. Every user-addressed message (text, media, CR, reaction, etc.) traverses these three layers:

```
Layer 1 — Identity Resolution (§4.3)
  service.sendToUser(envelope, userId)
    → identityResolver.resolveUserToDevices(userId)
    → returns List<deviceId> for the N devices that host this user
    → if empty: SKIP Layer 2, go directly to Layer 3 (S&F + Mailbox)

Layer 2 — Per-Device Routing (§4.4)
  for each deviceId in resolved devices:
    node.sendToDevice(packet, deviceId)
      → tries cheapest route, max 3 ACK retries
      → next-cheaper route on failure
      → defaultGateway as last resort
      → returns true on DELIVERY_RECEIPT, false on cascade-exhausted

Layer 3 — Offline Delivery (§5.4 + §5.5 + §5.6)
  if Layer 2 returned false for ALL resolved devices (or Layer 1 was empty):
    → Erasure-coded backup on K=10 closest DHT nodes (§5.4)
    → S&F copy on 3 mutual peers (§5.5)
    → Mailbox entry (§5.6) for receiver pull
    → Sender is done — receiver will poll on next coming-online
```

**Comparison with v2.2's "Direct → Relay → S&F" pattern**:
- v2.2 chained Direct/Relay/S&F as three attempt stages WITHIN the send operation
- v3.0 separates them by **responsibility**: the identity layer determines the WHO (which devices), the routing layer the HOW (which path), and S&F+Mailbox the WHAT-IF-OFFLINE (asynchronous fallback)

**Important**: in V3.0, Direct and Relay are both sub-strategies inside `sendToDevice` (§4.4) — the distinction is transparent to the service layer. The caller only sees "sendToDevice success" or "sendToDevice failed".

**Sender-side retries no longer exist.** Once all Layer-2 routes are exhausted and Layer-3 (S&F + Mailbox) has been triggered, the sender has done its duty. The receiver will pull the message from its mailbox on next coming-online.

### 5.2 Direct Delivery (Single-Hop UDP)

The default path in `node.sendToDevice` for devices in the routing table with direct reachability.

**Flow**:
1. `routingTable.routesFor(deviceId)` returns routes sorted by cost
2. Cheapest route has `nextHop=null` (= Direct), cost = LAN/WiFi/PublicUDP
3. NetworkPacket build (§2.4 sender-side pipeline)
4. UDP send to the address-prioritized addresses (§4.6)
5. Wait for DELIVERY_RECEIPT (timeout 8s)
6. On timeout: per-address backoff (5s/30s/5min), try the next address
7. After 3 consecutive ACK timeouts on this route: mark route DOWN (surgical, §4.4)

**TLS escalation**: when UDP fails (single-shot or after fragmentation), TLS is attempted on the same port. The TLS frame carries the same NetworkPacket — no additional protocol layer.

**LAN optimisations**:
- Same subnet → no PoW (LAN-peer detection)
- Same subnet → KEM remains active (privacy against LAN sniffers), but signature verification is faster
- Address priority 1 (same-subnet) is always tried before others

### 5.3 Relay Delivery (Multi-Hop, max 3)

When direct delivery is not possible (all direct addresses in backoff or unreachable), `sendToDevice` routes via multi-hop relay.

**Mechanism**:
- Cleona node X knows a route to receiver device Z via relay node Y
- The sender wraps the original NetworkPacket into a `RelayForward` ApplicationFrame addressed to Y
- Y receives, checks `finalRecipientDeviceId == Z`, unwraps, forwards the inner packet to Z
- Z verifies the outer signature (from Y), the inner signature (from the original sender); the DELIVERY_RECEIPT travels back via Y to the original sender

**RelayForward ApplicationFrame** (inner frame carrying the actual NetworkPacket):

```protobuf
message RelayForward {
  bytes  relayId             = 1;   // 16 bytes random — anti-loop detection
  bytes  finalRecipientId    = 2;   // = deviceId of final destination
  bytes  wrappedPacket       = 3;   // serialized NetworkPacket (Outer Layer of original)
  uint32 hopCount            = 4;
  uint32 maxHops             = 5;   // = 3 for Cleona
  uint32 ttl                 = 6;
  bytes  originDeviceId      = 7;   // so DELIVERY_RECEIPT can route back
  uint64 createdAtMs         = 8;
  repeated bytes visited     = 9;   // list of traversed deviceIds (anti-loop)
}
```

**Important**: `finalRecipientId` is always a **DeviceID**, never a UserID. Multi-Identity-aware: the `visited` array contains ALL local DeviceIDs while forwarding (if a daemon hosts multiple identities, each counts as a separate "visited" entry for loop detection).

**Hop limit**: at most 3 hops. Beyond 3 the packet is dropped — no unbounded cascade.

**Relay budget** (§3.5 in v2.2 → in v3.0 under storage management): relays maintain a local storage budget for in-flight RelayForward packets. When exceeded, the relay drops new forwarding requests.

**Relay-Route-Learning (V3 — ACK-based)**:
- The sender learns successful relay routes via RELAY_ACK
- Future sends use the learned route directly — no fresh discovery
- On RELAY_ACK timeout: the relay route is marked DOWN (surgical, §4.4)
- No timer-based expiry — only failures cause marking

**Chunking for large payloads**: when a packet to be relayed exceeds `relayBudget.maxFrameSize` (300 KB), it is chunked and forwarded in multiple parts — with its own reassembly semantics on the receiver.

### 5.4 Erasure Coding (Offline Delivery)

If the receiver is offline, the message is stored on the K=10 closest DHT nodes as Reed-Solomon erasure-coded fragments. The receiver pulls the fragments on coming online and reassembles them.

**Parameters**:
- **N=10, K=7** (Reed-Solomon code rate): 10 fragments are produced, at least 7 must be available for reassembly
- **1.43× storage overhead** (10/7)
- **Resilience**: up to 3 fragment nodes may fail

**Fragment storage**:
- Key: `Hash("fragment" || messageId || fragmentIndex)`
- Fragments are placed on the K=10 closest DHT replicators of the `messageId` hash
- Max 5 copies per fragment in the network (storage-budget limit)

**Encoded payload (V3.0)**: each fragment carries a slice of the complete V3 `NetworkPacket` bytes (Outer-Device-Sig + KEM-payload + Inner). The sender does not build a separate "offline-delivery envelope" — the canonical packet is identical-or-equivalent to one of the per-device packets already built for direct delivery in §2.4.

- For **ApplicationFrame** payloads (User-KEM-targeted, see §3.3): one erasure-coded copy per recipient **user** suffices, because the inner KEM-ciphertext is identical across all devices of the recipient user (KEM is User-PK-keyed). All devices polling the user's mailbox find the same fragments and reassemble independently.
- For **InfrastructureFrame** payloads on the §2.3.5 Identity-Layer Infrastructure list (`RESTORE_BROADCAST`, Emergency `KEY_ROTATION_BROADCAST`): KEM is **Device**-PK-keyed (§3.5b), so the encoded blob can only reach one specific device. The sender takes the per-device packet built for the contact's first-resolved device as the canonical erasure-source; other devices of the same contact pick up via subsequent Direct-Send retries or via S&F on Mutual Peers (§5.5).

**Receiver polling**:
- At daemon startup: mailbox + fragment lookup for own UserID
- `Hash("fragment" || messageId || index)` for `index ∈ [0..9]` queried in parallel
- As soon as 7 fragments are available: Reed-Solomon decode → re-inject the reassembled `NetworkPacket` bytes into the standard receive pipeline (§2.4 Receiver pipeline). Outer-Device-Sig-Verify, KEM-Decap, Inner-User-Sig-Verify (or Inner-Device-Auth for InfrastructureFrame), dispatch run identically to a UDP-received packet — no separate verification path.

**Lifetime**: fragments are stored for 7 days, after which replicator nodes verify them. If the receiver has not picked up: the fragment is pruned (storage recovery).

**Erasure is push-based**: the sender places fragments on send-failure, not on every send. Storage efficiency stays bounded.

### 5.5 Store-and-Forward on Mutual Peers

In addition to erasure-coded fragments, on failure the sender also stores a **complete copy** of the message on 3 mutual peers (= peers that have both the sender and the receiver as a contact). This way the message is held on intentionally trustworthy nodes, not only on random DHT replicators.

**Mutual-peer selection** (Architecture Section 5.5 v2.2):
- The sender's `Contact` store contains the UserIDs of its contacts
- For each contact, the sender checks: does this contact also have the receiver in its contact list? (via shared-channel membership or an explicit hint)
- If yes, it is a "mutual peer" — Cleona trusts mutuals more than random DHT nodes

**S&F storage**:
- Same inner frame (`ApplicationFrame`) as the original send target
- Outer wrap to the mutual peer as a `STORE_AND_FORWARD` MessageType
- The mutual holds the message for at most 7 days or until the receiver retrieves it

**Receiver pull**:
- On coming online: `STORE_AND_FORWARD_RETRIEVE` to all known mutual peers
- Mutuals send the stored messages back
- Dedup via `messageId`

**Connection to the disappearance of MessageQueue**:
- v2.2 additionally maintained a local MessageQueue at the sender for 7-day retry of the same message
- v3.0 removes this queue entirely — S&F takes over the responsibility
- Benefit: receiver-pull instead of sender-push, less traffic, less ID confusion

**Storage limit**: per receiver, max 30 stored messages on a single mutual. On overflow: oldest-first eviction.

### 5.6 Mailbox (UserID-based Pull)

Every user has a **virtual mailbox** in the DHT — addressed via `mailbox_id_primary` and `mailbox_id_fallback`. The receiver polls on coming online.

**Mailbox-ID derivation**:
```
mailbox_id_primary  = SHA-256("mailbox" || ed25519_user_pubkey)        // 32 bytes
mailbox_id_fallback = SHA-256("mailbox-nid" || userId)                 // 32 bytes
```

- **Primary**: pubkey-based, used by senders that already know the receiver's pubkey (contact store)
- **Fallback**: UserID-based, used by senders that do not yet have the pubkey (e.g. first KEM encapsulation toward a new contact)

The receiver polls **both** on every mailbox poll, so no send is lost.

**Mailbox storage**:
- Key: mailbox_id_*
- Value: list of small notification records (NOT the entire message — that lives in S&F or erasure)
- Notification: `{senderUserId, messageId, timestamp, hint}` — informs the receiver that a message exists for them
- The receiver then fetches the full message via S&F pull or fragment reassembly

**Polling schedule**:
- At daemon startup: aggressive polling, 10× every 3s (~30s total)
- In steady state: one mailbox poll every 60s
- On `onNetworkChanged`: re-poll on the new address

**PK propagation**: if receiver A does not yet have the pubkey of sender B (e.g. first CR), A cannot decrypt the KEM. In that case the message is a `CONTACT_REQUEST`, which carries the sender pubkey in cleartext (in the inner frame) — handled specially in §8.1 Contact Request Protocol.

**Mailbox-storage lifetime**: 7 days, analogous to erasure/S&F.

### 5.7 Two-Stage Media

Large media files (images >256KB, audio, video) are transferred in two stages:

**Stage 1 — Metadata Announcement** (in the inner frame as `MEDIA_ANNOUNCE`):
```
{
  mediaId:           bytes (16),
  mimeType:          string,
  totalSize:         uint64,
  totalChunks:       uint32,
  thumbnailBlob:     bytes (≤4KB),
  caption:           string?,
  expirySeconds:     uint64
}
```

The receiver immediately sees the preview (thumbnail) in the UI and decides (or auto-downloads via setting) whether to request Stage 2.

**Stage 2 — Confirmed Transfer** (chunked):
- The receiver sends `MEDIA_REQUEST` with `mediaId` back
- The sender chunks the media into `MEDIA_CHUNK` frames (≤32 KB each after compression)
- Per chunk: separate KEM encryption + ACK
- After the last chunk: `MEDIA_COMPLETE` confirms reassembly

**Auto-Download Thresholds** (user-configurable):
- Per-chat setting: Auto-Download YES/ASK/NO
- Per media type: images Auto, video Ask, audio Auto, files Ask (defaults)
- Per network: Auto on WiFi, Ask on mobile

**Inline media** (≤256 KB) skip Stage 1+2 — they are sent directly inside the application frame as `MEDIA_INLINE`.

### 5.8 RUDP Light & Fragment-NACK

Cleona's "Reliable UDP Light" — minimal overhead for ACK tracking, without TCP complexity.

**ACK mechanism**:
- Every application message (except ephemeral types such as TYPING_INDICATOR, READ_RECEIPT) expects a `DELIVERY_RECEIPT`
- DELIVERY_RECEIPT is a dedicated inner-frame type, sent from the receiver back to the sender
- The sender's `AckTracker` keeps a timer per `messageId`
- Timeout = max(2 × RTT × hopCount, 8s) — Direct: 8s, Relay: ~16s
- On timeout: per-route failure counter +1
- After 3 consecutive timeouts on the same route: route DOWN (surgical)

**Important**: NO timer-based expiry. Routes live until they accrue 3 ACK timeouts. This prevents short burst failures (e.g. WiFi glitch) from prematurely deleting routes.

**Fragment-NACK** (CFNK, "Cleona Fragment Negative ACK"):
- Used with app-level fragmentation (>1200 bytes → fragmented into 1200-byte pieces)
- The receiver collects fragments; the reassembly buffer is keyed by `(senderDeviceId, messageId)`
- If after 500ms a fragment is missing: NACK with `missingFragmentIndices`
- The sender resends the missing fragments
- Max 3 NACK retries per fragment group (self-rescheduling)

**App-level UDP fragmentation** (V3):
- Payload >1200 bytes → fragments of ≤1200 bytes
- Max 255 fragments per application frame (= ~300 KB max)
- Each fragment is an own UDP packet with fragment header (`groupId`, `index`, `total`)
- Reassembly on the receiver after all fragments arrive or after NACK retry

**Message-status lifecycle** in the UI:
- `pending` — created by the sender, not yet sent
- `sent` — UDP send completed
- `delivered` — DELIVERY_RECEIPT received (at least one)
- `failed` — sender cascade exhausted, Layer-3 fallback triggered
- `seen` (optional, opt-in) — READ_RECEIPT received

### 5.9 Compression

zstd compression precedes KEM encryption.

**Pipeline position** (see §2.4):
```
ApplicationFrame bytes (after user signing)
  → zstd-compress
  → KEM-encrypt
  → wrapped in Outer
```

**Why zstd, not gzip or brotli**:
- zstd is markedly faster (especially on ARM/mobile)
- Comparable compression ratio
- Modern, well maintained (Facebook), portable C library

**Compression level**: 3 (default) — a good trade-off between CPU and ratio. Adjustable per message type:
- Text frames: level 5 (higher ratio, small payloads)
- Media frames: level 1 (fast, little gain because media is mostly already compressed)
- Live-call frames: SKIP zstd (latency-critical, frames are small anyway)

**Verified gain**: text messages ~50-70% smaller. Media (JPEG/AAC/H.264) ~5% smaller.

### 5.10 Send-Cascade Recovery & Self-Healing

The §5.1 Three-Layer Cascade describes the *happy path*. When sends to a peer fail, V3.0 escalates through five stages — driven by **packets-without-acknowledgement**, not by timers — to recover the route, the peer's keys, or, as last resort, the entire Discovery state.

**Hard rule**: stage progression is exclusively triggered by `(sentPackets, ackedPackets, signalsReceived)` counters. No wall-clock thresholds (no "M minutes idle"). In a healthy mesh, any number of stages may proceed within milliseconds.

#### 5.10.1 Stage 1 — Direct (Recap)

`sendToDevice(deviceId)` issues up to 3 packets along the cheapest route. RUDP Light tracks them via `AckTracker` (§5.8). If a `device_sig_invalid` reply arrives **at any point** (even after the 1st packet), Stage 1 is interrupted and Stage 2 fires immediately — no point in continuing to 3 timeouts when we already have a hard signal that the peer's signing key changed.

#### 5.10.2 Stage 2 — Stale-PK Recovery

**Trigger**: an incoming packet from `senderDeviceId == X` fails Outer-Device-Sig verification against the cached `firstParty` Device-Sig PK for X (`PeerInfo.deviceEd25519PublicKey` / `deviceMlDsaPublicKey` per §3.5 Welle-3 layout), so the cache is likely stale because X rotated keys, not malice.

**Action** (single-shot per peer, 30 s cooldown):

1. Mark X's `PeerInfo.pkStale = true` — orthogonal to `pkSource`. Doesn't delete the PK; carve-out at receive time (§5.10.5) lets the next firstParty Self-Broadcast overwrite it.
2. Send X **one** Stale-PK probe — a `MTV3_DHT_PING` on the BOOT path (§2.4.1a) with `pk_recovery_hint = true` set in the inner body. Fire-and-forget; sender does not block.
3. Reputation-suppression: while `pkStale == true`, the standard `recordBad('device_sig_invalid')` reputation hit is *not* applied. We have no proof yet whether the new key is legitimate; we trust the cascade.

**Wire-format addition** (DhtPing Inner):

```protobuf
message DhtPing {
  bytes  senderId          = 1;
  uint64 timestampMs       = 2;
  bool   pk_recovery_hint  = 3;   // NEW Welle 5.12 — Stage-2 hot-path signal
                                  // Receiver answers PONG *plus* an unsolicited
                                  // firstParty PEER_LIST_PUSH (Self-Broadcast).
}
```

**Hot-path receiver behaviour** (§5.10.2 + §5.12 hot path): when `_handleDhtPingInfra` sees `pkRecoveryHint == true`, it sends the regular `DHT_PONG` and **additionally** a `PEER_LIST_PUSH` (Self-Broadcast carrying its own PeerInfo with current PKs) to the sender. The sender's `_handlePeerListPushInfra` accepts the new PK under the §5.10.5 carve-out, which clears `pkStale` and lifts reputation suppression. **Healing in 1 RTT.**

**Cold-path backstop** (§5.12 cold path): the DV Safety-Net (§4.4, 1 h) piggy-backs a firstParty Self-Broadcast to all neighbours, so even peers who never trigger Stage 2 see a fresh `firstParty` PK at most 1 h after rotation.

#### 5.10.3 Stage 3 — Alternative Route (Recap)

After 3× ACK timeout on the cheapest route, the AckTracker marks that route DOWN (surgical, §4.4) and `sendToDevice` falls through to the next-cheaper route — up to 3 packets there. Stage 3 reuses the existing DV cascade unchanged.

#### 5.10.4 Stage 4 — Mesh-State Refresh

**Trigger**: 6 packets total (Stage 1 + Stage 3) sent to X without any reply (no DELIVERY_RECEIPT, no PONG, no sig-invalid signal). The cascade routes are all stale or X is unreachable on every learned path.

**Action** (60 s cooldown per failed peer):

1. Iterate the routing table's *other* peers in cost order (excluding the failed X).
2. For each: send `MTV3_PEER_LIST_WANT` on the BOOT path with `wantedNodeIds = [X]`, **50 ms spacing** between sends (serial, not parallel storm).
3. After the last WANT is dispatched, wait **150 ms tail** for any reply.
4. Success criterion: did *any* peer reply with `MTV3_PEER_LIST_PUSH`? (`_stage4ReplySeen` flag flipped by the receive handler within the tail window.) If yes, reset `_unackedPacketsToPeer[X] = 0`; the next send-attempt naturally retries Stage 1 with potentially refreshed cache. If no, escalate to Stage 5.

**Counter mechanics**:

- `_unackedPacketsToPeer[deviceIdHex]` is the source of truth for the Stage 4 trigger.
- Incremented in `sendToDevice` (and relay-forward via `_sendV3ViaHop`) per packet sent.
- Reset to 0 on any positive signal from this device: `DELIVERY_RECEIPT` (via `ackTracker.onAckReceived`), incoming `PONG`, incoming `PEER_LIST_PUSH`. Decrement is centralised in `_dispatchInfrastructureFrameLocal` so all infra reply types reset uniformly.
- Persisted only in memory — survives no daemon restart (cold start runs §2.7.1 anyway).

**Solicited-Reply-Adoption** (closes the "asks for All, gets All back, doesn't write it down" gap):

A `MTV3_PEER_LIST_PUSH` reply that arrives within 30 s of a `MTV3_PEER_LIST_WANT` we sent to the same `senderDeviceId` is treated as a *solicited reply* — the sender is adopted as a direct neighbor (`dvRouting.addDirectNeighbor`) **before** the inbound `processRouteUpdate` call runs. Without this, a freshly-restarted node (no `dv_routing.json` yet — see §4.9.1) or a never-before-seen peer that we just queried would have no `_neighbors` entry for the answering peer, and the silent guard in `dvRouting.processRouteUpdate` (`return false` on unknown sender) would discard the carried routes despite us being the ones who *asked*.

**Tracker mechanics**:

- `_outstandingPeerListWants[deviceIdHex]` is populated at every `MTV3_PEER_LIST_WANT` send-site (the `PeerListSummary`-driven anti-entropy WANT and the §5.10.4 burst above).
- Cleared on first matching `PEER_LIST_PUSH` — adoption happens once.
- Pruned by `_maintenance` for entries older than the 30 s window (no PUSH ever came back).
- In-memory only; intentionally not persisted (an outstanding WANT from a previous daemon lifetime carries no semantics).

**Trust boundary**: solicited-reply-adoption only short-circuits the DV neighbor-membership precondition. Outer-Device-Sig verify, closed-network HMAC, rate-limit, reputation-ban and the timestamp window all run **upstream** in `_onPacketV3Received` and would have rejected a forged reply long before this handler. A network attacker who does not see our WANT cannot meaningfully forge a PUSH, because an unsolicited PUSH falls back to the existing `_neighbors` precondition (and is dropped silently if the sender isn't already an authenticated direct neighbor).

#### 5.10.5 Stage 5 — Re-Discovery

**Trigger**: Stage 4 completed with zero replies — the entire learned mesh appears unreachable.

**Action** (single-shot per cascade-fail; no recursive Stage 5 → Stage 5):

1. Re-execute the Startup-Discovery procedure (§4.5):
   - Three-burst on IPv4-Broadcast + IPv4-Multicast (239.192.67.76) + IPv6-Multicast, intervals 0/2/2 s
   - Subnet-Scan on the local /16 (DHCP-priority hosts first, then sweep)
2. Blanket-mark **all** known peers' `pkStale = true` so a fresh firstParty Self-Broadcast can replace any stale PK on receive.
3. If even Stage 5 yields no peer, the message proceeds normally to §5.4 (Erasure Coding) and §5.6 (Mailbox) — the message is not lost, it shifts to the offline-delivery layers.

**§5.10.5 PK-Provenance carve-out** (the `pkStale` flag in `PeerInfo`):

The standard rule is that a `firstParty` PK can never be overwritten by an incoming `firstParty` PK (pollution prevention — see `PeerInfo.pkSource` semantics). The carve-out: if `pkStale == true` AND the incoming source is `firstParty`, the overwrite is allowed and `pkStale = false` is cleared. This is the only path through which a rotated PK enters the cache without operator intervention — and Stage 2 + Stage 5 are the two places where `pkStale` gets set.

#### 5.10.6 State Machine Summary

```
            Stage 1: Direct (≤3 pkts)
                  │
        ┌─────────┼─────────┐
        │         │         │
   sig_invalid  3× ACK    success
        │       timeout      │
        ▼         ▼          ▼
    Stage 2:   Stage 3:   ─done─
   Stale-PK    Alt route
   probe       (≤3 pkts)
   (1 RTT
    via §5.12)
        │         │
        │   ┌─────┼─────┐
        │   │     │     │
        │  3× ACK  │  success
        │  timeout │     │
        │   │     ▼     ▼
        │   │  ─done─ ─done─
        │   ▼
        │  Stage 4: Mesh-State Refresh
        │  (PEER_LIST_WANT to all known peers,
        │   50 ms spacing, 150 ms tail-wait)
        │     │
        │     ├─ any reply ──► retry Stage 1 with refreshed cache
        │     └─ no reply ───► Stage 5
        │                        │
        │                        ▼
        │                Stage 5: Re-Discovery
        │                (3-burst + Subnet-Scan,
        │                 same as startup,
        │                 plus blanket pkStale=true)
        │                        │
        │                        ├─ peer found ──► retry Stage 1
        │                        └─ silent ──────► §5.4 Erasure / §5.6 Mailbox
        │
        └──► Stage 2 fires fire-and-forget; sender continues to Stage 3 in parallel
```

**Cooldowns** (per-peer, in-memory):

| Stage | Cooldown |
|---|---|
| 2 (Stale-PK probe) | 30 s |
| 4 (Mesh refresh) | 60 s |
| 5 (Re-Discovery) | none — single-shot per cascade-fail |

**Out-of-scope** (intentionally): persistent retry storage (covered by §5.4 + §5.6); security implications of accepting stale-PK overwrites (covered by §4.10 Closed-Network HMAC + the firstParty Self-Broadcast trust anchor — both preserved by the §5.10.5 carve-out: the HMAC still gates every BOOT packet, and only `firstParty` writes are allowed to overwrite, never `thirdParty` hearsay).

---

## 6. Identity Recovery

This chapter describes the most innovative aspect of Cleona's architecture: how a user recovers their identity and complete chat history after device loss, without any server or cloud backup. Recovery in v3.0 builds on the layered wire-format (§2) — restore-related payloads ride as `ApplicationFrame`s inside the standard layered pipeline, but with one piece of routing-layer specialisation: the Restore Broadcast must reach _all contacts_ (and through them, all of the recovering user's group peers), so the outer `NetworkPacket` is built once per contact-device rather than once per `userId`.

### 6.1 Recovery Phrase (24 Words)

At initial setup, the app generates a 24-word recovery phrase. This phrase encodes sufficient entropy to deterministically derive the complete user-identity key pair (both encryption and signing keys). The user is prompted to write down the phrase and store it securely.

**Implementation:** The 24 words encode 264 bits (256 bits entropy + 8-bit SHA-256 checksum). The word list uses deterministic phonetic generation (consonant-vowel patterns: CV, CVC, CVCV, CVCCV, CVCVC) to create pronounceable, memorable words. Bidirectional conversion is supported: `seedToPhrase()` and `phraseToSeed()` with checksum validation. The scheme is BIP-39-style in spirit (24 words, single-shot decode, embedded checksum) but uses Cleona's own generated word list rather than the canonical BIP-39 dictionary.

From the seed, key pairs are derived using SHA-256 with context strings: `SHA-256(seed + "cleona-ed25519")` for Ed25519, etc. Post-quantum keys (ML-KEM-768, ML-DSA-65) cannot be derived deterministically from a seed (liboqs limitation) and must be backed up separately or freshly generated and re-published as part of the Restore Broadcast (see §6.3.5).

The 24-word phrase recovers the **user identity** only. Per-device signing keys (§3.5) are generated fresh on each device after restore.

### 6.2 Social Recovery (Shamir's Secret Sharing)

As an alternative to remembering a 24-word phrase, users can set up Social Recovery. The user designates 5 trusted contacts as recovery guardians. The app takes the recovery seed and splits it into 5 shares using Shamir's Secret Sharing (threshold: **3 of 5**).

**Implementation:** Uses GF(256) Galois field arithmetic with irreducible polynomial 0x11B. Each secret byte gets a random degree-(K-1) polynomial where the constant term equals the secret byte. Shares are evaluated at points 1–N. Reconstruction uses Lagrange interpolation over GF(256). Share encoding: 1-based index + base64-encoded data.

Security: An attacker would need to compromise 3 of 5 guardians simultaneously. Guardians cannot collude accidentally because they don't know who the other guardians are (unless they guess). The threshold (3 of 5) balances security against the risk of guardian unavailability.

**Guardian UI Flow:**
- **Guardian setup:** Split seed → send shares to 5 contacts (each share carried as a dedicated `ApplicationFrame`, encrypted to the guardian via Per-Message KEM, see §3.3)
- **Guardian trigger:** Contact menu → QR code + notification to other guardians
- **Guardian confirm:** Pop-up with warning, default=deny
- **Recovery:** Scan QR → collect 3/5 shares → reconstruct seed

### 6.3 Restore Broadcast

The Restore Broadcast is the mechanism that makes Cleona's recovery truly unique. After the user's key is recovered (via phrase or Social Recovery), the app emits a signed Restore Broadcast that fans out across the user's contact graph.

**Frame layout (V3.0 Welle 6):** A Restore Broadcast is an `InfrastructureFrame` (§2.3.5) of type `RESTORE_BROADCAST`, KEM-encrypted under each contact's Device-KEM-PK (§3.5b). The recipient Device-KEM-PK is fetched from the local routing-table cache, otherwise via a 2D-DHT DeviceKemRecord lookup (§4.3 step 4b). The Outer NetworkPacket is signed under the recovering peer's freshly-generated **Device**-Sig-Keys — these are independent of User-Identity rotation, so receivers verify Outer-Sig regularly. The inner `RestoreBroadcast` body carries an old-Ed25519 signature over `(oldUserId, newUserId, newPubkeys, displayName, timestamp)` — the inner authenticity that proves the sender controls the old User-Sig-Key.

`RESTORE_RESPONSE` is an `ApplicationFrame`, KEM-encrypted under the recovering peer's freshly-published User-KEM-PK (which the broadcast carried). All subsequent phases — manifests, fetch responses, payloads — use the standard encrypted `ApplicationFrame` (§3.3).

**Rationale:** The previous "signed-only" ApplicationFrame variant was a structural workaround because the recovering peer does not yet know contact User-KEM-PKs. The InfrastructureFrame path uses Device-KEM-PKs (which contacts already know from prior interaction or 2D-DHT), eliminating the workaround and aligning with §2.4.1.

**Routing:** Unlike a normal user-addressed message, the Restore Broadcast is broadcast-style: the sender enumerates all known contacts and, for each, builds a separate outer `NetworkPacket` per contact device (the Identity Resolver returns a device-set per `userId`; see §4.3). The inner `ApplicationFrame` is identical across all packets — the per-device variation is the routing envelope, not the payload.

**Critical prerequisite:** The recovering device must perform a **complete wipe** of the old profile data before restoring from a recovery phrase. Without a wipe, the existing node has an empty contact list and a different Device-Sig keypair, causing a deadlock: contacts may recognise the recovered `userId` but the routing-layer cost-model is empty, so reverse-path delivery has no targets. The correct flow is: wipe profile → enter recovery phrase → derive user keys → generate fresh device-sig keypair → rejoin network → broadcast.

#### 6.3.1 Restore Broadcast Flow

1. User recovers their user-identity private key via recovery phrase or Social Recovery.
2. App performs a complete profile wipe and re-derives user keys from the seed; a fresh per-device signing keypair is generated (§3.5).
3. App connects to the network using the recovered `userId` and the fresh `deviceId`. The Identity Resolver (§4.3) is updated so that other peers can re-discover this device.
4. App emits a `RESTORE_BROADCAST` `InfrastructureFrame` per contact device, KEM-encrypted under the contact's Device-KEM-PK (§3.5b), Outer-signed under the recovering peer's fresh Device-Sig-Keys (rotation-stable per §3.5b). The body carries an old-Ed25519 signature for inner authenticity. The frame is additionally erasure-coded into the DHT (§5.4) so offline contacts pick it up via Mailbox-Pull when they come online — the encoded blob is the canonical NetworkPacket built for the contact's first-resolved device (per §5.4: InfraFrame KEM is device-PK-keyed, so one encoded copy reaches at most one device of the contact; further devices of the same contact pick up via subsequent Direct-Send retries or via S&F on Mutual Peers, §5.5).
5. Every node that processes the broadcast checks: "Is this `userId` in my contact list?"
6. If yes, the contact's app automatically responds with: their contact information (so the recovering user rebuilds their contact list), the encrypted chat history of their shared conversation, group memberships with member crypto keys and profile data.
7. For anti-abuse protection: 3 of 5 recovery guardians must confirm the Restore Broadcast before contacts release their data. This prevents an attacker who stole the key from harvesting all chat histories.
8. The recovering device collects all responses and progressively rebuilds its complete state.

#### 6.3.2 Progressive Restoration (Manifest + Pull)

The restore is structured as a **two-step pull protocol** that scales gracefully with history size and survives partial network failures. Detailed specification in `docs/SPEC_RESTORE_PHASE3_REDESIGN.md`.

**Phase 1 — Header (seconds):** The responding contact sends a `RESTORE_RESPONSE` `ApplicationFrame` containing contacts, group memberships, and channel subscriptions. The user sees their contact list rebuild immediately. (zstd-compressed; compression sits in the standard layered pipeline §2.4.)

**Phase 2 — Manifest (seconds to minutes, depending on history size):** The contact then sends one or more `RESTORE_MANIFEST` frames. Each entry advertises a known message — `(messageId, timestamp, conversationId, senderId, type, sizeHint)` — but not the message body. Manifests are split into chunks of 2.000 entries; with zstd compression a chunk fits comfortably in a single `ApplicationFrame` (typical ~125 B/entry raw → ~42 B compressed). At >5 chunks, the sender paces 50 ms between chunks to avoid burst loss on mobile/CGNAT links.

**Phase 3 — Pull (background, controlled by recovering peer):** The recovering peer parses the merged manifests, deduplicates against its already-known message IDs, and pulls missing messages via batched `RESTORE_FETCH` frames (max 50 IDs per request). The contact replies with `RESTORE_DELIVER` frames carrying the actual `StoredMessage` payloads. The recovering peer chooses pull priority itself (default: timestamp DESC — newest first); each successfully delivered message is persisted immediately, so partial progress is durable.

**Cross-source deduplication:** When the recovering peer is in a group with N members, it receives N manifests advertising the same group messages. It maintains a global `pending_msg_assignments` map: each message ID gets one **primary** source (preferred: the conversation owner, otherwise first-responder) and a list of **alternates**. Each ID is fetched exactly once. On timeout or `missing_message_ids` response, the next alternate takes over automatically. Sender stays stateless.

**Resumability:** The recovering peer persists its `pending_msg_assignments` and per-contact fetch queues. If the app is killed mid-restore, it resumes after restart by re-issuing `RESTORE_FETCH` for whatever was still queued. No new protocol messages required for resume — if a contact is offline at resume time, the recovering peer simply waits or relies on the contact picking up its earlier S&F + Mailbox-Pull entries when the contact next comes online.

**Failure semantics:** If a contact has deleted their copy of a conversation, those entries do not appear in their manifest. In group chats, any member who still has the history can provide it (via the alternate-source mechanism above). If the conversation owner is the only holder and they have deleted, the history is genuinely lost — this is by design (data sovereignty means deletion is real).

**Group restore:** Restore responses (Phase 1) include full group membership with crypto keys (`RestoreGroupMember` proto) for each member. Since Cleona uses stateless Per-Message KEM (§3.3), the recovering node can immediately send encrypted messages to all group members using their public keys — no session re-establishment needed. Group messages carry `group_id` to route them to the correct group conversation (not the DM with the sender).

**Why this design:** The previous "send the whole history in one envelope" model failed on mobile networks: a 200-message history produced ~410 UDP packets back-to-back (170 for direct + 240 for the erasure-coded backup), which DS-Lite/CGNAT carriers systematically drop. The manifest+pull design eliminates the burst entirely — the manifest is small, individual fetch responses are batch-sized, and the erasure-coded DHT backup of the bulk history blob is no longer needed (it remains for Phase 1 and the manifest itself).

#### 6.3.3 Aggressive Mailbox Polling

After sending a Restore Broadcast, the recovering node performs aggressive mailbox polling: 10 polls at 3-second intervals. This dramatically speeds up restore on LAN networks where waiting for event-driven push delivery (which depends on at least one peer noticing the recovering node via PONG) would be unnecessarily slow. The Kademlia bootstrap itself takes ~15-20 seconds with a freshly wiped routing table, so a 30-second delay before the first broadcast is used, with an automatic retry after 30 more seconds if no contacts were restored.

Mailbox-Pull during restore is the same mechanism used for normal offline message collection (see §5.6) — the only difference is the polling cadence. Once a contact responds, the node falls back to the standard event-driven push pattern.

#### 6.3.4 Multi-Device Support

The Restore Broadcast mechanism serves as the bootstrap for multi-device support. When a user enters their 24-word seed phrase on a second device, it derives the same user keys, generates its own fresh device-sig keypair (§3.5), joins the network with a new `deviceId` mapped to the original `userId`, and performs a standard Restore Broadcast to receive the full state. After restore, the device registers itself with its twins via TWIN_ANNOUNCE and participates in ongoing Twin-Sync for local actions. See §7 for the complete multi-device architecture including device management, synchronization protocol, and revocation.

#### 6.3.5 Anti-Abuse Protections

**Rate limiting:** A maximum of one Restore Broadcast is accepted per `userId` per 5 minutes (per sender). Additionally, `RESTORE_FETCH` frames from a recovering peer are rate-limited to 8/minute per source contact, and require a valid Restore Broadcast within the last 24h (otherwise silent drop).

**Guardian confirmation:** 3 of 5 guardians must actively confirm the restore before contacts release chat data. This is the same Social Recovery threshold — the guardian confirmation serves double duty.

**Notification:** When a Restore Broadcast occurs, ALL contacts receive a visible notification: "[Name] has set up a new device." If the real user did not initiate this, they can immediately alert their contacts.

**Encrypted transfer:** All chat history sent in response to a Restore Broadcast is encrypted with Per-Message KEM (§3.3) using the recovering device's public key (the user-identity public key derived from the recovered seed). Exception: `RESTORE_BROADCAST` and `RESTORE_RESPONSE` themselves are signed only (not encrypted), since the recovering peer may not have the responding contact's current PQ public key.

**Post-quantum key handling during restore:** The recovering device generates fresh ML-KEM-768 and ML-DSA-65 key pairs (since these cannot be derived deterministically from the seed). The Restore Broadcast includes these new PQ public keys. Contacts update their stored keys for the recovering identity upon receiving the broadcast. During the brief transition window before all contacts process the broadcast, any messages encrypted with the old PQ keys fall back to X25519-only decryption (see §3.3.5 for the full security analysis).

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

The encrypted registry is split using Reed-Solomon coding (**N=10, K=7**) and distributed across the 10 DHT nodes closest to the registry's DHT key. This ensures the registry survives even when up to 3 of those nodes are offline. Retrieval uses multiple polling rounds to collect enough fragments for reassembly. The erasure-coding parameters and the fragment-distribution mechanics are the same as for offline message storage (§5.4).

#### 6.4.3 Recovery Flow

1. User enters recovery phrase → master seed derived.
2. Compute registry DHT key from master seed.
3. Retrieve erasure-coded fragments from DHT.
4. Reassemble and decrypt registry → list of active identity indices and display names.
5. For each identity index: derive Ed25519/X25519 user-identity keys from master seed + index.
6. For each identity: generate a fresh device-sig keypair (§3.5), start the identity's node, and trigger a Restore Broadcast.

---

## 7. Multi-Device Support

A UserID can be hosted on multiple devices — e.g. phone plus desktop plus tablet. V3.0 makes Multi-Device a **first-class** concept (in contrast to v2.2, where Multi-Device was an extension): the auth manifest lists all authorised DeviceIDs of a UserID, the IdentityResolver returns them as a list, and sendToUser fans out automatically.

### 7.1 Device Identity & Pairing

Every device has its own **Device-Sig keypair** (Ed25519+ML-DSA-65 hybrid, see §3.5), plus its own **DeviceID**:

```
deviceId = SHA-256(network_secret || ed25519_device_pubkey)
```

Device keys are **not** derived from the recovery phrase — they are generated locally on the first daemon start. This makes device identity disposable (device loss = a new DeviceID on the replacement device, without any risk to the user identity).

**Initial setup** (first device):
1. The user generates the master seed (24-word phrase)
2. HD-Wallet derives the user identities (§3.6)
3. Device keys are freshly generated using a cryptographic random source
4. The auth manifest is published with this single DeviceID as `authorizedDeviceIds[0]`
5. Identity Registry entry (§6.4) with display name + profile picture

**Pairing an additional device** (e.g. a new phone for an existing identity):
1. On the old device (e.g. desktop): "Pair new device" action → shows a QR code with `{userId, masterPubkey, signedPairToken}`
2. On the new device: QR scan → receives `signedPairToken`
3. The new device generates its own Device-Sig keypair
4. The new device sends `DEVICE_PAIR_REQUEST` (application frame) to the user's own devices (over the now-known UserID via `sendToUser`)
5. Existing devices confirm via `DEVICE_PAIR_APPROVE` — the master seed is transferred (KEM-encrypted under the `signedPairToken` pubkey)
6. The new device now holds the master seed and can regenerate the user keys
7. The auth manifest is extended with the new DeviceID and re-published

**Pairing security**:
- `signedPairToken` is user-signed, valid at most 5 minutes — prevents replay
- Master-seed transfer KEM-encrypted via X25519+ML-KEM-768 hybrid (standard KEM, §3.3)
- Both devices show a security code (hash of the exchanged pubkeys) for visual verification

**Pairing over NFC** (alternative): identical flow, but `signedPairToken` is conveyed via NFC pairing tap instead of QR.

**Twin-Discovery**: after pairing, devices automatically discover each other via the 2D-DHT (each device publishes its own liveness; other devices see liveness records bearing the same UserID).

### 7.2 Twin-Sync Protocol

Once Multi-Device is active, application-state changes (new contacts, conversations, message edits, etc.) must be synchronised between devices.

**Twin-Sync** is a dedicated protocol type: a `TWIN_SYNC` application frame with a sub-type discriminator.

**12 Twin-Sync types** (canonical: `proto/cleona.proto::TwinSyncType`):

| # | Type | Content |
|---|---|---|
| 0 | CONTACT_ADDED | new contact accepted (with pubkeys, display name, verification level) |
| 1 | CONTACT_DELETED | contact deleted |
| 2 | MESSAGE_SENT | message sent on one device → mirror so the other devices see it locally |
| 3 | MESSAGE_EDITED | edit within the 15-min window |
| 4 | MESSAGE_DELETED | delete within the 15-min window |
| 5 | TWIN_READ_RECEIPT | own read on one device → other devices also mark read |
| 6 | GROUP_CREATED | own device created/joined a new group *(receive-side wired; sender-side wiring pending)* |
| 7 | PROFILE_CHANGED | own profile picture / display name changed *(receive-side wired; sender-side wiring pending — `_emitProfileChange()` hook missing)* |
| 8 | SETTINGS_CHANGED | shared per-identity settings changed (currently used for seed-phrase persistence sync) |
| 9 | DEVICE_ANNOUNCE | new device pairing announce to existing twin devices (carries inner `DeviceRecord`) |
| 10 | DEVICE_RENAMED | one of own devices got renamed |
| 11 | TWIN_DEVICE_REVOKED | device removed from `authorizedDeviceIds` — revocation propagated to twins |

The set has shifted vs. v2.2: `CONTACT_VERIFIED`, `CONVERSATION_OPENED`, `GROUP_LEFT`, `CHANNEL_SUBSCRIBED`, `CHANNEL_UNSUBSCRIBED` are not (yet) in the V3.0 wire enum — verification upgrades ride on a fresh `CONTACT_ADDED`, conversation existence is implicit on first message, and group/channel leave/subscribe sync is currently routed through their respective application protocols (§9, §10) rather than Twin-Sync.

**Twin-Sync routing**: via `sendToUser(envelope, ownUserId)`. The resolver returns the own devices and fan-out happens automatically — the sender (= the device making the change) excludes itself from the fan-out.

**KEX Gate integration**: Twin-Sync frames are "intra-identity" — they must be allowed through the KEX Gate (§8.2) because sender = receiver at the user level.

**Dedup**: every Twin-Sync frame carries a `messageId`; the receiver deduplicates on multiple arrivals (multi-path delivery).

**What is NOT synced**:
- Local GUI settings (theme, skin, sound volume) — per-device individual
- Routing table (each device has its own mesh view)
- Identity-resolution storage (own replicator data)
- Call-history details (more "local" than application state)

### 7.3 Multi-Device Delivery (sendToUser fan-out)

V3.0's Multi-Device delivery aligns cleanly with the service API (§15.3). The sender invokes `sendToUser(envelope, recipientUserId)`. The resolver returns N DeviceIDs. The service iterates.

**Default behaviour**: fan-out to ALL devices. This way the user sees the same message on every device.

**Delivery result**:
- 1 of N devices delivered → sender's UI shows ✓ (at least one received)
- 0 of N devices delivered → offline fallback (S&F + Mailbox)

**No per-device ACK tracking at the user level**: the sender does not distinguish which of the N devices have received. On the receiver side, Twin-Sync READ_RECEIPT propagates "read" between the user's own devices.

**Special case: requireOnline**: for latency-critical sends (e.g. call setup) the sender can set `requireOnline=true`. In that case there is no offline fallback — `sendToUser` returns `false` immediately if no device delivery succeeded.

### 7.4 Device Revocation

When a device is lost/stolen or otherwise compromised, it must be removed from the `authorizedDeviceIds` list.

**Normal deregistration** ("Sign out from this device"):
1. The user, on another device, picks "Manage Devices" → marks the lost device
2. The auth manifest is re-signed WITHOUT the DeviceID being revoked
3. The new auth manifest is published (with incremented `seq`)
4. Replicator nodes replace the old manifest with the new one
5. Future IdentityResolver lookups no longer return the revoked device
6. Twin-Sync frames are no longer fanned out to that device

**Race window**: between republish and replicator distribution there is a ~15min-1h window in which senders may still read the old auth manifest. During that window they can send frames to the revoked DeviceID — but:
- The receiver (the old device) would have to be online and still propagating its liveness record
- If the device is stolen, the attacker can receive frames but cannot decrypt them (unless they hold the user private keys, which is unlikely with a hardware keystore)
- After the window: the liveness TTL expires and the device disappears from the DHT

**Emergency Key Rotation** (re-key identity — when user private keys may have been compromised):

Two flavors with distinct wire-paths:

**(a) Hard re-identity** (new master seed → new UserID):
1. The user generates a new master seed (new 24-word phrase)
2. A new UserID is derived (= a fully new identity at the wire level)
3. RESTORE_BROADCAST (§6.3, InfrastructureFrame path) goes to all contacts with "Here is my new UserID, replace the old one"
4. The old UserID is announced as gone via `IDENTITY_DELETED` broadcast
5. Contacts must explicitly accept the new identity (manual confirmation in the UI, because the pubkey changed)

**(b) Soft re-key** (same UserID, rotate user-sig + user-KEM keys after compromise):
1. The user generates fresh User-Ed25519 + User-ML-DSA + User-X25519 + User-ML-KEM keypairs
2. The app emits `KEY_ROTATION_BROADCAST` with the **Emergency-variant** dual-signature: `oldSignatureEd25519` (proves: I am the legitimate previous holder) AND `newSignatureEd25519` (proves: I control the new key)
3. **Wire-path:** InfrastructureFrame (§2.4.1), KEM-encrypted under each contact's Device-KEM-PK. Outer-signed under unchanged Device-Sig-Keys (§3.5b, rotation-stable). This is the path adopted in V3.0 Welle 6 — see §2.3.5 selector and the rationale in §2.4.0.
4. Contacts verify both inner signatures, replace stored User-Pubkeys, and respond with `KEY_ROTATION_ACK` (regular ApplicationFrame, now KEM-encrypted under the rotated User-KEM-PK).

Both flavors are **hard cuts** in user-perception terms — no Twin-Sync of old conversations to the new identity, no automatic migration. Variant (b) preserves the UserID but still requires the Inner Dual-Sig as the only authentication subject; receivers MUST NOT accept a key-rotation without inner dual-sig verification regardless of `senderIdentitySnapshot.outerSigStatus`.

Note on periodic KEM-only rotation: `MessageType.KEY_ROTATION` (single-sig in body, KEM keys only) remains an ApplicationFrame because Ed25519/ML-DSA do not change — Outer Device-Sig-Verify and Inner User-Sig-Verify both function regularly.

---

## 8. Identity-Authorization Protocols

Cleona distinguishes between **known** contacts (in the contact store) and **unknown** senders. The protocol between them is the Contact-Request workflow plus the KEX Gate as anti-spam filter.

### 8.1 Contact Request Protocol

A Contact Request (CR) is the only permitted form in which an **unknown** user may write to another user. All other application frames from unknown senders are silently dropped (KEX Gate, §8.2).

**CR flow**:

```
1. Alice opens Bob's profile (e.g. via QR scan, NFC pairing, channel-member click)
   → Alice has Bob's userId + pubkeys

2. Alice clicks "Send contact request"
   → Service.sendToUser(bob.userId, MessageType.CONTACT_REQUEST, payload)
     payload = ContactRequest { 
       displayName, 
       ed25519_pk, ml_dsa_pk, x25519_pk, ml_kem_pk,
       profilePictureBlob?, 
       greetingMessage? 
     }

3. The CR is fanned out as a KEM-encrypted ApplicationFrame to all of Bob's devices
   (resolver returns Bob's DeviceIDs from the auth manifest)

4. Bob's daemon receives the CR
   → KEX Gate allows CONTACT_REQUEST from unknown senders (single exception)
   → CR lands in the Inbox tab (UI: "Requests")

5. Bob decides: Accept / Reject / Ignore
   - Accept: ContactRequestResponse with Bob's own pubkeys + 
             ContactInfo is inserted into Bob's contact store
   - Reject: no response, CR removed from Inbox (Alice notices nothing —
             privacy protection, Bob does not want to say "I rejected you")
   - Ignore: CR remains in Inbox

6. Alice receives ContactRequestResponse (if accepted)
   → Bob's pubkeys are inserted into Alice's contact store
   → Status set to "accepted"
   → Alice and Bob can now communicate freely
```

**CR anti-spam** (in addition to the KEX Gate):
- Erasure-coded backup of the CR even with an online receiver (CR is "particularly important" and must not be lost)
- Per-sender rate limit: max 5 CRs per hour to the same receiver (filtered in the resolver layer)
- Receiver-side: max 100 pending CRs in the Inbox, oldest-first eviction

**Re-Contact**: when the sender is already "accepted" in the receiver's contact store and the sender sends another CR (e.g. key-change recovery), the CR is shown as a DM (Direct Message) in the Current tab instead of the Inbox tab — with the hint "Re-Contact from Alice with new keys".

**Re-Contact-Auto-Overwrite gate (V3.0 Welle 6):** The auto-overwrite of stored pubkeys for an already-accepted contact (key-change-recovery convenience path) requires `senderIdentitySnapshot.outerSigStatus == verified` (§2.4.0). If the snapshot reports `skippedBootstrap` — i.e. the receiver has no Device-Sig-Pubkey on file for the sender — the CR is treated as a fresh inbound CR and lands in the Inbox tab; the user must explicitly accept that the new keys are legitimate. This closes the F4 defensive-fallback gap from the V2 → V3 bridge.

**Bidirectional CR auto-accept**: if Alice accepts Bob's CR while Bob has already sent Alice a CR (race), both CRs are auto-accepted without further user confirmation.

### 8.1.1 ContactSeed URI Format

The ContactSeed URI is the canonical machine-readable form of "Bob's contact info" used for QR-code, NFC, and copy/paste exchange. It is the prerequisite for the First-Contact-Request bootstrap — without it, Alice has no way to address Bob.

**URI format**:

```
cleona://<userIdHex>?n=<displayName>&c=<channel>&did=<deviceIdHex>&dxk=<deviceX25519Pk_b64>&dmk=<deviceMlKemPk_b64>&a=<addresses>&s=<seedPeers>
```

**Parameters**:

| Param | Source | Format | Purpose |
|---|---|---|---|
| `<userIdHex>` (path) | UserID | 64 hex chars (32 bytes) | Bob's stable UserID |
| `n` | display name | URL-encoded UTF-8 | hint only — re-confirmed inside CONTACT_REQUEST_RESPONSE |
| `c` | channel tag | `b` (beta) or `l` (live) | mismatched channels are rejected before any send |
| `did` | DeviceID | 64 hex chars (32 bytes) | identifies the QR-emitting device of Bob, so Alice can address First-CR via `sendToDevice(deviceId)` |
| `dxk` (NEW Welle 5) | Device-X25519-PK | 32 bytes, base64 | required for InfrastructureFrame KEM-encap of First-CR |
| `dmk` (NEW Welle 5) | Device-ML-KEM-768-PK | 1184 bytes, base64 | same |
| `a` | reachable addresses | `ip:port+ip:port+...` (`+` URL-encoded as `%2B`) | Bob's current addresses for direct send |
| `s` | seed peers (≤5) | `nodeIdHex@ip:port+ip:port,...` | bootstrap routing helpers |

**No User-KEM-PK in the URI**, intentionally: Alice learns Bob's User-KEM-PK only from CONTACT_REQUEST_RESPONSE (and Bob's User-Sig-Pubkey is in the CR-payload itself). Until Bob accepts the CR, Alice has no authorization to encrypt anything to Bob's user identity. The Device-KEM-PK is sufficient for the bootstrap because the CR-payload itself is User-signed, and the Device-KEM acts purely as a transport tunnel for that signed payload.

**Backward compatibility**: legacy URIs without `dxk`/`dmk` parse fine but cannot be used as the recipient for a First-CR. The First-CR sender then falls back to a synchronous "fetch DeviceKemRecord from 2D-DHT" lookup if Bob has already published one (§4.3 step 4b). If neither URI nor 2D-DHT yields a Device-KEM-PK, the CR cannot be sent and the user receives a clear error ("Bob's contact code is too old, please ask him to re-share").

#### First-Contact-Request Bootstrap Flow

This is the only place in V3.0 where the §2.3.5 InfrastructureFrame selector list is intentionally relaxed to admit a non-infrastructure MessageType (CONTACT_REQUEST). It must remain strict for all other MessageTypes.

```
1. Alice parses Bob's URI → bobUserId, bobDeviceId, bobDeviceX25519Pk, bobDeviceMlKemPk
2. Alice builds her CR payload:
   ContactRequest {
     displayName: "Alice",
     ed25519Pk: alice.user.ed25519Pk,
     mlDsaPk: alice.user.mlDsaPk,
     x25519Pk: alice.user.x25519Pk,
     mlKemPk: alice.user.mlKemPk,
     profilePictureBlob, greetingMessage
   }
3. Alice wraps the CR as a fully User-signed ApplicationFrame:
   ApplicationFrame {
     recipientUserId: bobUserId,
     senderUserId: aliceUserId,
     messageType: CONTACT_REQUEST,
     payload: serialize(ContactRequest from step 2),
     userEd25519Sig + userMlDsaSig over the frame bytes (Alice's User-Sig)
   }
4. Alice wraps that ApplicationFrame inside an InfrastructureFrame:
   InfrastructureFrame {
     recipientDeviceId: bobDeviceId,
     senderDeviceId: aliceDeviceId,
     messageType: CONTACT_REQUEST,            // selector-relaxation marker
     payload: serialize(ApplicationFrame from step 3)
   }
5. Alice KEM-encrypts the InfrastructureFrame under Bob's Device-KEM-PK
   (X25519 + ML-KEM-768 hybrid v2, see §3.5b).
6. Alice builds the Outer NetworkPacket:
   NetworkPacket { payloadType: INFRASTRUCTURE_FRAME,
                   nextHopDeviceId: bobDeviceId,
                   payload: PerMessageKem-bytes,
                   ... Outer-Sig (Ed25519-only per §3.5 Infrastructure rule) }
7. Send via standard routing (§4.4 sendToDevice). Per §4.6 this gates on reachability, not direct-confirmed: the target is by definition not yet direct-confirmed, so the cascade attempts the URI's a= addresses directly AND relays via the s= seed peers; RUDP-Light (CR-Retry) confirms delivery.
8. Bob's daemon decrypts (using Device-KEM-SK), reads the InfrastructureFrame,
   sees messageType=CONTACT_REQUEST → CR-Bootstrap exception → unwraps the inner
   ApplicationFrame, verifies Alice's User-Sig, KEX-Gate exception applies (§8.2),
   CR lands in the Inbox.
9. Bob accepts → sends CONTACT_REQUEST_RESPONSE as a regular ApplicationFrame
   (now Bob has Alice's User-KEM-PK from the CR payload, so he can encrypt to
   her user-identity normally).
```

After step 9, all subsequent traffic between Alice and Bob runs the regular ApplicationFrame path (§2.4 main pipeline). The InfrastructureFrame-wrap of CR is purely a bootstrap mechanism — never used after the first round-trip. CR-Retry (when the CR was sent but no response arrived) re-uses the same bootstrap path, since Alice still does not have Bob's User-KEM-PK. The retry timer checks peer reachability in this order: (a) recipientUserId in routing table, (b) userId secondary index via getPeerByUserId, (c) seedDeviceIdHex from the persisted ContactSeed bundle. Fallback (c) is necessary because the DV routing table only carries deviceNodeIds — the userId secondary index is often empty for first-CR contacts whose CR-Response has not yet arrived.

### 8.2 Anti-Spam & KEX Gate

The **KEX Gate** (Key-Exchange Gate) is Cleona's primary protection against unsolicited messaging.

**Rule**: application frames from unknown senders (UserID not in the receiver's contact store) are **silently dropped**, without ACK, without notification, without logging.

**Exceptions** (single-exception list):
- `CONTACT_REQUEST` (initial outreach)
- `CONTACT_REQUEST_RESPONSE` (response to an own CR)
- `IDENTITY_DELETED` (broadcast — when the sender used to be a known user but is now deleted)
- `RESTORE_BROADCAST` (restore of a known contact with new keys)
- `TWIN_SYNC` (intra-identity, from own UserID)

**Channel/group messages**: not subject to the KEX Gate, because the sender is known via channel or group membership (even if not in the personal contact store).

**Anti-spam layers** (multi-stage, see also §13.1):
- Layer 1: KEX Gate (no known sender → drop)
- Layer 2: PoW in the Outer (no PoW → drop, in the outer NetworkPacket)
- Layer 3: per-sender rate limit (max 5 CR/h)
- Layer 4: reputation system (frequent drops → low reputation → potential ban)
- Layer 5: network-level banning (the channel owner can ban a user at channel level)

**Implementation note**: the KEX Gate check happens **after** KEM decrypt + user signature verification, because only then is the UserID verified. An attacker who cannot pass user-signature verification is dropped earlier (drop on signature mismatch, §2.4 step 13).

### 8.3 Identity Updates & Profile Sync

Users can change their display name, profile picture or description. These updates are propagated to all contacts.

**Profile update flow**:

```
1. User changes display name or profile picture in Settings
2. Service builds a PROFILE_UPDATE application frame:
   { 
     newDisplayName, 
     newProfilePictureBlob?,    // ≤4KB (compressed JPEG)
     newDescription?,
     timestamp 
   }
3. Frame is fanned out to all contacts via sendToUser per contact
4. Receiver updates its local contact-store entry
5. Twin-Sync: PROFILE_CHANGED to own devices
```

**Profile-picture constraints**:
- Max 4 KB after JPEG compression
- Auto-resize to 256×256 px when larger
- Optional: the user may set "NO_PICTURE" (a default avatar is shown)

**Description**: max 500 characters, plain text (no Markdown, no HTML — anti-XSS).

**Update-frequency limit**: max 1 profile update per hour (anti-flood, protects receivers from mass updates).

**PK propagation** (special case): when sender pubkeys change (KEM version update, key rotation), this goes through the `RESTORE_BROADCAST` frame instead of PROFILE_UPDATE — see §6.3.

### 8.4 Identity Deletion

A user can delete an identity entirely (also one of several in a multi-identity daemon).

**Identity-deletion flow**:

```
1. User selects "Delete identity" in Settings → confirmation dialog
2. Daemon broadcasts IDENTITY_DELETED to all contacts:
   { 
     deletedUserId,
     timestamp,
     ed25519Sig,        // signed by deleted user (proof of authorization)
     mlDsaSig
   }
3. The auth manifest is published with the `tombstone` flag (for IdentityResolver caches)
4. Local data deleted:
   - identity_db.sqlite.enc
   - identity_meta.json.enc
   - identity_resolution_state.json.enc
5. The HD-Wallet index for this identity is marked "tombstoned" (re-use as a new identity is possible, but at a different index position)
6. The user is redirected to the identity list (or to the master recovery phrase, if it was the last identity)
```

**Receiver behaviour** on IDENTITY_DELETED:
- The KEX Gate allows this message (even from a user who has just been deleted — they hold the last valid signature)
- The contact-store entry for `deletedUserId` is marked "deleted" (not removed — the user should see "Bob has deleted his identity")
- Conversations with that UserID are archived (read-only; new sends go nowhere)
- Profile picture / display name remain shown with a "(deleted)" suffix

**Tombstone TTL in the DHT**: 30 days. After that the tombstone is pruned, and the UserID could in theory be reused (but the pubkey hash makes it unlikely that anyone obtains the same hash).

**Multi-Device handling**: when an identity is deleted on one of three devices, the delete propagates via Twin-Sync to the other two. All of them remove local data.

---
## 9. Group Features

Cleona's group features cover three closely related layers: invitation-only **Private Channels** (and their group-chat siblings), openly discoverable **Public Channels** with content moderation, and the network-level **Anti-Sybil** plumbing that protects the moderation primitives. Group chats and private channels share the same role hierarchy and pairwise encryption pipeline; public channels add discovery, content rating, and a decentralized jury process on top.

### 9.1 Private Channels

#### 9.1.1 Concept

Private Channels are invitation-only broadcast channels with a clear role hierarchy. They enable one-to-many communication (announcements, communities, interest groups) while maintaining full E2E encryption.

#### 9.1.2 Role Model

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

##### 9.1.2.1 Leave Semantics & Ownership Transfer

**Conversation is removed on leave (not archived).** When a member leaves a group or channel, the local chat conversation is removed together with the membership record (`conversations.remove(id)` in `leaveGroup` / `leaveChannel`). Rationale: a former member has no way to interact with the group anymore — receiving, sending, inviting, and role changes are all gated on membership. Keeping a dead read-only archive creates "Leichen im Keller" without user-visible value, while widening the attack surface for accidental data retention.

The `staleConvs`-Cleanup on startup (`CleonaService._initState`) remains as a safety net: conversations referencing a group/channel that no longer exists in `_groups` / `_channels` are removed and re-saved. This catches edge cases where a membership record was removed through a side channel (recovery, migration) without its conversation being cleaned.

**Automatic ownership transfer on Owner-leave:** If the leaving user is the Owner and other members remain, ownership is **automatically reassigned** before the GROUP_LEAVE broadcast fires. Order of promotion:

1. First member with `role == 'admin'` (insertion order of the `members` map)
2. Otherwise, the first remaining member (insertion order)

The new Owner is promoted locally (`role = 'owner'`, `group.ownerNodeIdHex = newOwner.nodeIdHex`), a `_broadcastGroupUpdate(group)` reaches the remaining members with the new role assignment, and then `GROUP_LEAVE` is sent per-member (fire-and-forget, pairwise-encrypted via `sendToUser`). Receiver-side handlers apply the same transfer logic independently to stay convergent with the new owner identity.

**Last-member-leave:** If `group.members.length == 1` at leave time (the Owner is the only remaining member), no transfer occurs, no `_broadcastGroupUpdate` is sent, and the group record is silently removed locally.

**UI safeguards against accidental leave:** The user-facing Leave action is guarded by a two-step dialog sequence in `chat_screen.dart`:

1. **Group/Channel-info dialog** uses clearly differentiated button labels: "Abbrechen" (dialog cancel) + "Einladen" (secondary action) + "Verlassen" (destructive, FilledButton with `colorScheme.error` styling). A previous "Schließen" label was removed because users confused it with "Verlassen".
2. **Confirmation sub-dialog** always shows before the Service is invoked. For Owners, the dialog body additionally names the automatic transfer recipient (e.g. "Owner role will be transferred to **X**.") so the consequence is visible before commit. For the last-member case, the text explains that the group will be dissolved.

Together these safeguards make accidental leave a three-click path (menu → Verlassen-button → Confirm-Verlassen) with explicit description of the destructive consequence, rather than a one-click accident.

#### 9.1.3 Technical Implementation

**Encryption:** Pairwise E2E encryption, identical to regular group chats (see §9.1.x — group encryption pipeline). Each channel post is individually encrypted into one `ApplicationFrame` per recipient and delivered via `sendToUser(userId)` using Per-Message KEM. Relay nodes see only encrypted fragments.

**Invitations:** The Owner or Admin generates a signed invite link or QR code. The invite contains the channel ID, channel name, optional channel picture, and optional channel description, encrypted to the invitee's public key. Only the intended recipient can join. The invite must include the complete member list so the invitee knows all participants.

**Discovery:** Private Channels are NOT listed in any public DHT index. Members can only join via direct invitation from an Owner or Admin. This makes channels legally and practically equivalent to private group chats.

**Scalability:** Pairwise encryption has O(n) cost per post. For channels with up to ~50 members this is acceptable. A future migration to MLS (RFC 9420) with O(log n) member changes is architecturally possible for larger channels.

**Media in channels:** File attachments, voice messages, and pasted clipboard content are supported via the `ChannelPost` protobuf's `content_data` field. Media is embedded directly in channel posts and delivered with one `sendToUser` per recipient. Received media files are saved locally to the recipient's `downloads/` or `voice/` directory with image preview support in the UI.

**Profile data:** Groups and channels can have optional pictures (JPEG, max 64 KB) and descriptions. These are set during creation, included in invites, and updated via `updateGroupProfile()` / `updateChannelProfile()`. Profile data is persisted in the group/channel JSON state and included in restore responses.

### 9.2 Public Channels

Public, openly discoverable broadcast channels with decentralized content moderation.

> Full specification: `docs/CHANNELS.md`

#### 9.2.1 Channel Discovery & Index

Public channels are listed in a **compressed DHT index** (~200–300 bytes per channel). Users discover channels via a searchable "Suche" tab (default on first app start). The index stores: name, language, content rating (adult/general), description snippet, subscriber count, Bad Badge status (level + timestamps for badge set and correction submitted).

**Uniqueness:** Channel names are globally unique via `SHA-256("channel-name:" + lowercase(name))` as DHT key. First-come-first-served with squatting protection (identity must be 7+ days old).

**Channel creation fields:** Name (required, unique), Language (required: DE/EN/ES/HU/SV/multi), Public/Private toggle. Optional: image, description. For public channels, a "Not safe for minors" toggle appears (default ON — must be explicitly disabled to allow minors).

**Replication:** Each channel entry is stored on the 10 DHT nodes closest to its DHT key (standard Kademlia replication). Since entries are small (~300 bytes), simple replication is used rather than erasure coding. Channel updates (subscriber count changes, Bad Badge updates, tombstone markers) are propagated via gossip: each node storing a channel entry sends periodic updates (once per hour) to the 10 closest nodes. Tombstone entries (deleted channels) are replicated for 30 days before removal.

**Storage estimate:** 10,000 channels × 300 bytes ≈ 3 MB total index. A Bloom filter for name uniqueness checks requires significantly less.

#### 9.2.2 Content Rating & Age Verification

Public channels have a **"Not safe for minors" toggle**, which defaults to ON — the creator must explicitly disable it to make the channel available to minors. This is intentionally conservative.

Channels marked as not safe for minors are **invisible** to identities without the `isAdult` flag (self-declaration, see Identity Detail Screen). These channels do not appear in search results and cannot be subscribed to or read without the flag.

#### 9.2.3 Roles for Public Channels

Public channels add a new role **"Everyone"** (all network users):

| Role | Read | Post | Admin |
|------|------|------|-------|
| Owner | ✓ | ✓ | ✓ |
| Admin | ✓ | ✓ | partial |
| Subscriber | ✓ | ✗ | ✗ |
| **Everyone** | ✓* | ✗ | ✗ |

\* Restricted: NSFW channels require `isAdult` flag for read access.

### 9.3 Decentralized Moderation

#### 9.3.1 Decentralized Content Moderation

Six report categories: Not safe for minors (mislabeled), Wrong content (doesn't match description), Illegal: drugs, Illegal: weapons, Illegal: CSAM, Illegal: other.

**Single post reports** → Channel admins are notified; escalation to channel-level report after 7 days if unresolved.

**Channel-level reports** → Reporter selects 3-10 specific posts as evidence. When the report counter reaches a threshold, a **jury of 5-11 randomly selected users** reviews the evidence and votes with 2/3 majority required. Jury members have 2 days to respond; abstentions and timeouts are replaced.

**Jury language selection:** The language for jury selection comes from the **reported channel's language field** (set at creation, stored in the DHT index), not from any attribute on the juror's identity. A node is eligible for jury duty if it subscribes to at least one channel with the same language setting — a behavioral proxy for language competence that requires no metadata on the identity itself. For channels with `language: multi`, nodes of all languages are eligible. This preserves the anonymity principle (see §3.1 Identity Model): no language attribute is stored on or published with any identity. Eligibility is determined locally from the node's own subscription list and answered as a simple yes/no to jury requests.

**Consequences:** NSFW reclassification, Bad Badge (3-stage escalation, see §9.3.2), or Tombstone deletion (DHT entry marking channel as removed).

#### 9.3.2 Bad Badge System

A trust signal for misleading channel descriptions. 3-stage escalation:

| Stage | Trigger | Label | Probation |
|-------|---------|-------|-----------|
| 1 | First confirmed report | "Content questionable" | 30 days after admin correction |
| 2 | Second confirmed report during probation | "Repeatedly misleading" | 90 days after correction |
| 3 | Third confirmed report | **Permanent** | — |

Badge stays until admin corrects name/description. After correction, probation phase starts. Channels with badges are **never hidden** — only deprioritized in search with visual warning.

#### 9.3.3 CSAM Special Procedure

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

#### 9.3.4 Moderation Timer

All time-based moderation limits are enforced by a **periodic timer** (`_moderationTimer`) in `CleonaService`. Without this timer, time-dependent actions (badge expiry, jury timeouts) would only fire when triggered by unrelated events — which in production (30-day probation, 2-day jury timeout) might never happen.

**Timer interval:** Adaptive — 1/6 of the shortest configured timeout, clamped to [5 seconds, 5 minutes]. When the test preset is active with sub-5-second timeouts, the timer ticks every 1 second.

**Four checks per tick:**

1. **Jury vote timeout:** Active jury sessions that exceed `juryVoteTimeout` are resolved with whatever votes have been cast (partial quorum).
2. **Badge probation:** Channels with `correctionSubmitted=true` and `badBadgeSince` older than the probation period (`badgeProbationLevel1` / `badgeProbationLevel2`) have their badge level decremented.
3. **CSAM temp-hide lift:** Channels with `isCsamHidden=true` and `csamHiddenSince` older than `csamTempHideDuration` are unhidden.
4. **Single-post escalation:** Pending `PostReport` entries older than `singlePostEscalationTimeout` are escalated to `ChannelReport` entries and checked against the jury threshold.

**Cleanup:** Completed jury sessions are discarded after 1 hour.

**Config switch:** When `moderationConfig` is changed via IPC (`set_moderation_config`), the timer is automatically restarted with the new interval.

### 9.4 Anti-Sybil

#### 9.4.1 Social Graph Reachability Check

Open-source code enables bot software that creates fake identities with simulated social activity to file coordinated false reports. Defense: **network-level validation** of the reporter's social graph connectivity.

**Independence criteria (size-based):** Two identities are considered "connected" if they share a group/channel with fewer than `max(50, total_users × 0.05)` members. Direct contacts are always connected. This is size-based, not public/private-based — a private group with 500 members indicates no more coordination than a public channel with 500 subscribers.

**Reachability algorithm:** When a CSAM report is filed, K random validator nodes check whether they can reach the reporter's identity within 5 hops through their social graph. If ≥60% of validators can reach the reporter, the report is accepted. Bot clusters form isolated islands with no paths to the real network, causing validator checks to fail.

**Privacy:** Each node maintains a Bloom filter of contacts up to depth 5. Reachability is a local lookup (yes/no), not a graph traversal. No social graph data is exposed.

**Critical: Network validation, not app validation.** All checks are performed by receiving nodes, not the reporter's app. A modified client (fork) can submit a report, but the network ignores it if criteria are not met.

Reports from senders that are not yet whitelisted by the receiving node are silently dropped at the protocol entry point (KEX Gate, see §8.2). This means jury announcements, vote requests, and report deliveries all share the same anti-spam baseline as regular contact messages — there is no privileged moderation channel that bypasses the gate.

#### 9.4.2 ModerationConfig: Configurable Thresholds & Test Presets

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

---

## 10. Calls

Real-time voice and video calls require a different encryption and delivery approach than chat messages. Per-Message KEM (§3.3) adds ~1.1 KB overhead and a KEM operation per packet — unacceptable for voice (50 packets/second) and video (hundreds of packets/second). Calls use an **ephemeral symmetric key** negotiated once at call start and use a separate, optimised frame pipeline that bypasses the standard ApplicationFrame steps that do not pay for themselves on per-frame ciphertext.

### 10.1 Voice/Video Calls (1:1)

A 1:1 call between two users consists of two phases:

1. **Setup phase** — `CALL_INVITE` and `CALL_ANSWER` are exchanged as ordinary `ApplicationFrame`s via `sendToUser(userId)`. They run through the full layered encryption pipeline (§2.4), including per-message KEM and full hybrid Ed25519 + ML-DSA-65 signatures. This is where authenticity for the entire call is established.
2. **Live-media phase** — `CALL_AUDIO` and `CALL_VIDEO` frames are sent device-to-device via `sendToDevice(deviceId)` against the resolved peer device, encrypted under the negotiated `call_key`, and bypass two of the standard frame steps (see §10.3 below).

Video uses **libvpx VP8** for compression with adaptive bitrate; audio is uncompressed PCM (see §10.4). Both audio and video frames are passed through a **JitterBuffer** on the receive side to absorb network reordering and short bursts of loss before playback.

#### 10.1.1 Call Key Negotiation

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

### 10.2 Group Calls

Group calls use a **shared symmetric call key** distributed to all participants and an **Overlay Multicast Tree** for efficient media distribution.

#### 10.2.1 Group Call Setup

1. The call initiator generates a random 256-bit `call_key`.
2. The `call_key` is encrypted individually to each participant using Per-Message KEM (§3.3) and distributed via `CALL_INVITE` as an `ApplicationFrame` per participant (`sendToUser(userId)` per recipient).
3. All media packets are encrypted with `call_key` via AES-256-GCM (SRTP) and sent device-to-device via `sendToDevice(deviceId)` along the multicast tree.

**Key rotation during group calls:**

| Event | Action |
|-------|--------|
| Participant leaves voluntarily | No key rotation (they already knew the key) |
| Participant crashes + rejoins | No key rotation (they had the key before) |
| Participant is **kicked** | Key rotation → new key distributed to all remaining participants |
| New participant joins | Key rotation → new key distributed to all including new participant |

Key rotation is triggered only when the **authorized participant set** changes. A crash + rejoin does not change authorization.

**Rejoin after crash:** The rejoining participant sends a `CALL_REJOIN` `ApplicationFrame`. Any active participant responds with the current `call_key` encrypted via Per-Message KEM to the rejoining participant's public key.

#### 10.2.2 Overlay Multicast Tree

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

Each participant uploads at most **2–3 streams** regardless of total group size. The tree is a **degree-constrained, RTT-based Minimum Spanning Tree (RTT-MST)** over the participant set. Each candidate edge is weighted by measured RTT and available bandwidth between the two endpoints, and the MST builder enforces a per-node fan-out cap (typically 2–3) so that no single node is overloaded as a relay. Nodes with the best connectivity and lowest RTT to multiple participants are naturally chosen as relay points.

**Tree construction uses the existing routing table:** The overlay multicast tree is not constructed blindly. It uses the Distance-Vector routing table (§4.4) as a weighted graph. If Alice cannot reach Bob directly but has a relay route via Charlie, Charlie is placed as a relay point in the tree. The MST is computed over all participants using route costs as edge weights, then the degree constraint is applied.

**Signaling via chat channel:** `CALL_INVITE`, `CALL_ANSWER`, and tree topology updates are delivered through the normal `ApplicationFrame` channel via `sendToUser(userId)` (Per-Message KEM, Three-Layer Delivery — §5.1). This channel already handles NAT traversal and relay transparently — no separate signaling infrastructure is needed.

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

### 10.3 Live-Media Frame Authenticity

> **Onion-Routing Tabu.** Live-media frames are explicitly **Onion-Tabu** — see §2.5 Onion-Routing Hook for the full tabu list. Live audio and video frames travel direct device-to-device (or through the call-specific Overlay Multicast Tree, §10.2.2), without any onion layers. Onion encryption would multiply per-frame CPU and bandwidth cost beyond what 20 ms-deadline media can absorb, and the call key already provides end-to-end confidentiality and authenticity for every frame.

`CALL_AUDIO` and `CALL_VIDEO` `ApplicationFrame`s are classified as **ephemeral media** in the frame pipeline and **skip two of the standard ApplicationFrame steps**:

1. **No ML-DSA signature on the inner frame.** Post-quantum authenticity is established at call setup: the `CALL_INVITE` and `CALL_ANSWER` `ApplicationFrame`s carry full Ed25519 + ML-DSA-65 dual signatures, and the resulting `call_key` is mixed from a hybrid X25519 + ML-KEM-768 KEM (§10.1.1). Once both sides hold the call key, every audio/video frame is authenticated by AES-256-GCM (16-byte tag, fresh random nonce) under that key — a quantum adversary cannot forge frames without first breaking the setup handshake. A per-frame ML-DSA signature would add ~3500 bytes wire and ~600 µs CPU per frame on top of authentication that is already post-quantum-secure.
2. **No zstd compression probe.** Frame payloads are already AES-256-GCM ciphertext (high entropy) — zstd cannot compress them, and running the probe just costs CPU.

**What is still strict on every frame:**

- **Inner ApplicationFrame:** AES-256-GCM under the negotiated `call_key` (instead of the per-message User-KEM that ordinary application traffic uses) — confidentiality and content authenticity.
- **Outer NetworkPacket:** Ed25519 device signature only (no hybrid Ed25519 + ML-DSA), since outer packet-level auth is a single-hop spoofing defence and the underlying call key already covers end-to-end authenticity. See §2.4 + §4.10 for the general packet-auth model.

The optimisation only removes the redundant outer post-quantum signature on per-frame traffic; it does not weaken the cryptographic envelope around the call as a whole.

### 10.4 Cross-Platform Audio Stack

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

**Capture-isolate pattern:** The Dart side keeps the Capture-Isolate architecture: a dedicated isolate consumes 20 ms frames from a native ring buffer that the shim fills from a miniaudio capture callback. The isolate runs encryption (`AES-256-GCM` with the Call Session Key from §10.1.1) and forwards ciphertext frames to the main isolate via `SendPort`. No Dart code changes are needed at the layer above `AudioEngine` — the swap is transparent at the FFI seam.

**Why no codec:** With 16 kHz mono PCM at 640 bytes/frame, the on-wire bandwidth before AES-GCM overhead is ~256 kbps per direction. This is well within consumer broadband and 4G/5G mobile budgets, and the simplicity buys the project (a) a single ciphertext path, (b) no codec licensing concerns, (c) trivial AEC reference signal (the same PCM that goes to playback). A codec layer (Opus) can be added later behind the shim if metered-data deployments need it.

#### 10.4.1 Per-Call-Session Route Cache

A typical 1:1 audio call generates 50 `ApplicationFrame`s per second per direction (20 ms frames). Re-running the full Identity Resolution → Routing → Transport pipeline (§5.1) for each frame — including peer-table reads, NAT context filtering, and address-priority sorting — is wasteful when the destination is a single, known peer device for the lifetime of the call.

Each `CallSession` therefore caches the resolved `PeerInfo` and selected device address at the first outgoing frame. Subsequent frames send directly through the cached peer via `sendToDevice(deviceId)` against that cached address. The cache is invalidated by the existing `DvRouting.onRouteDown(deviceId)` callback — when the route to the call peer's device is marked DOWN (3× ACK timeout, poison-reverse, or peer-leave), the next frame falls back to a fresh resolution and the call follows the same recovery cascade as any other ephemeral frame. This is a per-session optimisation; it does not bypass routing health-checks, it only short-circuits the lookup on the hot path.

### 10.5 In-Call Collaboration

**Status:** planned, not implemented in v3.0 (design preview).

Group calls (§10.2) can be enhanced with real-time collaboration features: shared whiteboard, file/clipboard exchange, and screen sharing. All collaboration data is encrypted with the active call key (§10.1.1) and distributed via the Overlay Multicast Tree (§10.2.2).

#### 10.5.1 Design Principles

1. **Call-scoped:** All collaboration features are available only during an active call. When the call ends, shared content is discarded unless explicitly saved.
2. **Same encryption:** Collaboration data uses the same AES-256-GCM call key as audio/video streams. No separate key negotiation.
3. **Bandwidth-aware:** Collaboration data is lower priority than audio. If bandwidth is constrained, whiteboard updates and screen sharing quality are reduced before audio quality drops.
4. **No server:** All data flows P2P via the existing Overlay Multicast Tree. Screen sharing frames and whiteboard strokes are distributed the same way as video frames.

#### 10.5.2 Shared Whiteboard

A collaborative canvas where all call participants can draw, write, and annotate simultaneously.

##### 10.5.2.1 Architecture

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

##### 10.5.2.2 Data Model

```
WhiteboardStroke {
  strokeId:     UUID
  authorId:     bytes (drawer's userId)
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

##### 10.5.2.3 Synchronization

- **Real-time streaming:** Strokes are streamed point-by-point as the user draws. A `StrokeBegin` message starts the stroke, `StrokePoints` messages add points in batches (every 50ms), and `StrokeEnd` finalizes it. This gives remote participants a smooth live drawing experience.
- **Late join:** When a participant joins an ongoing call with whiteboard content, any active participant sends a full `WhiteboardSnapshot` (all strokes, all pages) encrypted to the joiner's public key.
- **Conflict resolution:** Strokes from different users never conflict — they simply overlay. For UNDO/REDO, each user can only undo their own strokes. CLEAR_ALL requires Owner/Admin permission.
- **Multi-page:** The whiteboard supports multiple pages (like a flipchart). Any participant can add a page. Page navigation is synchronized — when the presenter switches pages, all participants follow (with an option to browse independently).

##### 10.5.2.4 Features

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

#### 10.5.3 File & Clipboard Exchange

During a call, participants can share files and clipboard content directly with all call members.

##### 10.5.3.1 Architecture

File sharing during calls uses the existing media transfer infrastructure (§5.7 Two-Stage Media) but scoped to the call session:

```
CallFileShare {
  fileId:       UUID
  fileName:     string
  fileSize:     int64
  mimeType:     string
  thumbnailData: bytes (optional, for images/videos, max 16 KB)
  sharedBy:     bytes (sharer's userId)
  sharedByName: string
}
```

**Flow:**
1. User clicks "Share File" in the call UI or pastes from clipboard.
2. A `CallFileShare` announcement is sent to all call participants (via Overlay Multicast).
3. Each participant sees the file in a "Shared Files" panel.
4. Clicking "Download" triggers a direct P2P transfer (Two-Stage Media, §5.7) encrypted with the call key. The transport adresses the sharing user via `sendToUser(userId)`; the resolver fans out to all of that user's online devices.

**Clipboard sharing:** The "Paste to Call" button sends the current clipboard content (text, image, or file) to all participants. Text appears inline in the call chat. Images are displayed as thumbnails.

##### 10.5.3.2 Call Chat

A lightweight text chat within the call, separate from the group's persistent chat:

```
CallChatMessage {
  messageId:    UUID
  senderId:     bytes (userId)
  senderName:   string
  text:         string
  timestamp:    int64
  replyToId:    UUID (optional)
}
```

Messages are delivered via the Overlay Multicast Tree and encrypted with the call key. Call chat is ephemeral — it is not persisted after the call ends (unless a participant explicitly saves the transcript). Because call chat lives only inside the active call session, it does **not** flow through S&F + Mailbox-Pull; offline recipients simply do not see it.

#### 10.5.4 Screen Sharing

A participant can share their screen (or a specific window) with all call members.

##### 10.5.4.1 Architecture

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

Screen sharing reuses the entire video pipeline (§10, VP8 encoding, Overlay Multicast Tree) but captures from the screen instead of the camera. It is treated as a second video stream alongside the camera feed.

##### 10.5.4.2 Capture Sources

| Platform | Capture Method | Window Selection |
|----------|---------------|-----------------|
| Linux | PipeWire / XDG Desktop Portal (`org.freedesktop.portal.ScreenCast`) | Portal picker dialog |
| Windows | Windows.Graphics.Capture API | System picker dialog |
| Android | MediaProjection API | System permission dialog |
| iOS | ReplayKit (RPSystemBroadcastPickerView) | System picker |

**Privacy:** All platforms show a system-level indicator when screen sharing is active (overlay icon, status bar indicator). The sharing participant sees a colored border around the shared region.

##### 10.5.4.3 Adaptive Quality

Screen sharing adapts to available bandwidth:

| Bandwidth | Resolution | FPS | Quality |
|-----------|-----------|-----|---------|
| > 2 Mbps | Native (up to 1920x1080) | 15 | High (sharp text) |
| 1–2 Mbps | 1280x720 | 10 | Medium |
| 500 Kbps–1 Mbps | 960x540 | 5 | Low |
| < 500 Kbps | 640x360 | 3 | Minimal |

**Text optimization:** Screen content is mostly static text and UI elements. The encoder uses a higher quality setting for static regions and lower quality for moving content (video playback on the shared screen). A "optimize for text" toggle prioritizes sharpness over framerate (2 FPS but very crisp).

##### 10.5.4.4 Remote Control (Optional)

A future extension allows the presenter to grant remote control of their screen to another participant:

- Presenter explicitly grants control via a button ("Allow [Name] to control")
- The controller's mouse/keyboard events are serialized and sent to the presenter's machine
- Only one controller at a time
- Presenter can revoke control instantly
- Not available on mobile platforms (Android/iOS)

#### 10.5.5 Collaboration UI Layout

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

#### 10.5.6 Encryption & Security

All collaboration data (whiteboard strokes, shared files, screen frames, call chat) is encrypted with the same call key used for audio/video (§10.1.1):

- **Group call key rotation** applies to collaboration data too. When a participant is kicked, the new call key is distributed and all subsequent collaboration data uses the new key.
- **Screen sharing leakage risk:** The app shows a warning before screen sharing starts: "Participants will see your screen. Make sure no sensitive information is visible." On desktop, the app offers to hide its own notification area during sharing.
- **File sharing limits:** Maximum file size during a call is 50 MB (larger files should be shared via the regular chat). Maximum concurrent shared files: 20.

#### 10.5.7 Protocol Messages (Collaboration)

The following ApplicationFrame types carry in-call collaboration payloads. All travel inside an Inner-Frame encrypted with the active call key, then are wrapped in the Outer-Frame and distributed via the Overlay Multicast Tree.

| ApplicationFrame Type | Description |
|-----------------------|-------------|
| `WHITEBOARD_STROKE` | Real-time stroke data (begin, points, end) |
| `WHITEBOARD_ACTION` | Clear, undo, redo, page navigation |
| `WHITEBOARD_SNAPSHOT` | Full state for late joiners |
| `CALL_FILE_SHARE` | File announcement (metadata + optional thumbnail) |
| `CALL_FILE_REQUEST` | Request to download a shared file |
| `CALL_CHAT_MESSAGE` | Ephemeral in-call text message |
| `SCREEN_SHARE_START` | Announce screen sharing started (with resolution info) |
| `SCREEN_SHARE_STOP` | Announce screen sharing stopped |

All frames are encrypted with the call key and distributed via the Overlay Multicast Tree.

---

## 11. Calendar & Polls

### 11.1 Calendar (Internal)

Cleona provides a fully decentralized calendar that works across all of a user's identities, enabling unified management of private and professional schedules without any server infrastructure. The calendar integrates with group calls (§10) and polls (§11.3) to provide a complete scheduling and meeting workflow.

#### 11.1.1 Design Principles

1. **Identity-spanning:** All identities derived from the same master seed (§3.6) share a single calendar view. If AllyCat has a meeting at 14:00, Alice's calendar shows that time as blocked. External contacts querying Alice's availability see "busy" without learning that it is an AllyCat appointment.
2. **Privacy-first:** No calendar data is stored in the DHT or on any remote node. All events are stored locally in the encrypted database (§3.8). Sharing happens exclusively through explicit invitations and controlled Free/Busy responses.
3. **Offline-capable:** Calendar events are local-first. Group invitations are delivered via the existing Three-Layer Delivery (§5.1) and work even when participants are offline.
4. **Standards-compatible:** The internal data model is designed for iCal/CalDAV compatibility from day one, enabling future sync with Google Calendar, Thunderbird, Nextcloud, and other calendar systems.

#### 11.1.2 Data Model

##### 11.1.2.1 CalendarEvent

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

##### 11.1.2.2 CalendarInvite (Group Events)

When a user creates an event linked to a group (`groupId` set), an invitation is distributed to all group members via Pairwise Fanout (§9.1):

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

The invite appears both in the recipient's calendar and as an interactive card in the group chat (see §11.1.7).

##### 11.1.2.3 RSVP Response

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

#### 11.1.3 Free/Busy Protocol

The Free/Busy protocol enables privacy-controlled schedule visibility during event planning, similar to Exchange/CalDAV Free/Busy but fully decentralized and end-to-end encrypted.

##### 11.1.3.1 Visibility Model

Each user configures a **default Free/Busy level** and optional **per-contact overrides**:

| Level | What the querier sees | Use case |
|-------|----------------------|----------|
| **FULL** | Title + time + location | Close team members, family |
| **TIME_ONLY** | "Busy 14:00–15:30" (no content) | Professional contacts, boss |
| **HIDDEN** | No data returned for this event | Private appointments the querier should not know about |

The default applies globally. Per-contact overrides take precedence. Example: Default = TIME_ONLY, but for contact "Max" = FULL, for contact "Recruiter" = HIDDEN.

**Cross-identity privacy:** When a Free/Busy query arrives for identity Alice, the response includes blocked times from ALL identities (Alice + AllyCat + ...) but labels them all as Alice's. The querier cannot distinguish which identity caused the block. This is the key feature enabling unified private/professional calendar management.

##### 11.1.3.2 Request/Response Protocol

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

**Rate limiting:** Free/Busy requests are subject to the same rate limits as regular messages (§13.1). A contact can query at most once per 20 seconds. Non-contacts cannot query Free/Busy at all (KEX Gate, §8.2).

#### 11.1.4 Multi-Identity Calendar Merge

Since a Cleona user can have multiple identities (§3.6), the calendar must merge events from all identities into a single view while maintaining identity separation for external queries.

**Local view (owner's device):** All events from all identities are displayed in a single calendar view. Events are color-coded or labeled by identity (e.g., Alice events in blue, AllyCat events in green). The user sees their complete schedule.

**External view (Free/Busy queries):** When contact X queries identity Alice's availability, the response includes busy blocks from ALL identities but without revealing which identity caused the block. From X's perspective, Alice is simply "busy" — they cannot infer that Alice has a second identity.

**Event ownership:** Each event is owned by exactly one identity (`identityId` field). When sending a group invite, the invite comes from the owning identity. When accepting an invite, it is stored under the identity that received it.

**Identity switching in calendar:** The calendar view shows all events by default. A filter toggle allows showing only one identity's events. Creating a new event defaults to the currently active identity but can be changed via a dropdown.

##### 11.1.4.1 Identity scoping & roles (clarification)

To avoid confusion in multi-identity setups — all the following points are part of the model:

- **CalendarManager per identity.** Every identity has its own `CalendarManager` with its own encrypted persistence (`calendar_events.json.enc`, same pattern as ContactManager / PollManager).
- **CalendarSyncService per identity.** Every identity has its own `CalendarSyncService` with its own sync configuration (`calendar_sync_config.json.enc`) and its own SyncState (`calendar_sync_state.json.enc`). Providers (CalDAV/Google/LocalIcs) are opt-in per identity — Alice can sync against Nextcloud while AllyCat syncs against nothing.
- **`CalendarEvent.identityId`** binds each event uniquely to its owning identity; cross-identity moves are not supported (recreate the event + delete the old one).
- **Roles per event.** *Creator* (`createdBy == own nodeId`): full access (edit/delete/fan-out via `CALENDAR_UPDATE`/`CALENDAR_DELETE` to group members). *Invited participant*: read only + RSVP (`CALENDAR_RSVP`). No "co-edit" — changes to the event body flow exclusively from the creator.
- **Visibility.** Per-event `freeBusyVisibility` (`FULL`/`TIME_ONLY`/`HIDDEN`) plus per-contact override (`visibilityOverrides: Map<nodeIdHex, FreeBusyLevel>`). Affects only incoming `FREE_BUSY_REQUEST`s, not group invites (which see the full event body — anyone who is invited inevitably knows the time).

#### 11.1.5 Reminders & Notifications

Reminders use the existing notification infrastructure (§15.5):

- **Desktop (Linux/Windows):** System notification via the tray icon daemon. Sound plays via pw-play/paplay (§15.5).
- **Android:** Android notification channel "Calendar Reminders" with configurable importance.
- **Multiple reminders per event:** The user can set multiple reminder offsets (e.g., 1 day before + 15 minutes before). Each fires independently.
- **Recurring events:** Reminders fire for each occurrence, not just the first.
- **Snooze:** Reminders can be snoozed (5 min, 15 min, 1 hour, custom).

**Daemon-driven:** Reminders are evaluated by the daemon, not the GUI. This ensures they fire even when the GUI is not running (Linux/Windows desktop tray mode).

#### 11.1.6 Calendar Views & Printing

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

#### 11.1.7 Chat Integration

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
- Clicking "Call" starts a group call (§10) with all accepted participants
- 15 minutes before the event, a reminder message appears in the chat
- RSVP status updates are shown as small system messages ("Bob hat zugesagt")

**Event updates:** If the creator modifies the event (time change, cancellation), a `CALENDAR_UPDATE` message is sent via Fanout. The chat card updates in-place (same `eventId`). Cancelled events show a strikethrough overlay.

#### 11.1.8 Protocol Messages (Calendar)

New MessageType entries for the calendar:

| MessageType | Direction | Description |
|-------------|-----------|-------------|
| `CALENDAR_INVITE` | Creator → all group members | Event invitation with full details |
| `CALENDAR_RSVP` | Invitee → all group members | Accept/Decline/Tentative/ProposeNewTime |
| `CALENDAR_UPDATE` | Creator → all group members | Event modification (time, title, cancel) |
| `CALENDAR_DELETE` | Creator → all group members | Event deletion |
| `FREE_BUSY_REQUEST` | Planner → individual contact | Request availability for a time window |
| `FREE_BUSY_RESPONSE` | Contact → planner | Filtered availability blocks |

All calendar messages are encrypted via Per-Message KEM (§3.3) and delivered via the Three-Layer Cascade (§5.1). Calendar adresses Users (not Devices) — outbound calls use `sendToUser(userId)`. Messages are persisted locally and erasure-coded for offline delivery.

#### 11.1.9 Storage

Calendar events are stored in the encrypted SQLite database (§3.8) in a dedicated `calendar_events` table. Indexes on `startTime`, `identityId`, and `groupId` enable efficient range queries for calendar views.

**Recurring events** are stored as a single row with the RRULE. The UI expands occurrences on the fly. Exceptions (deleted or modified occurrences) are stored in `recurrenceExceptions` or as separate events with a `recurrenceOverrideFor` reference.

**RSVP state** for group events is stored in a separate `calendar_rsvp` table keyed by `(eventId, nodeIdHex)`.

#### 11.1.10 Implementation Status

**Core calendar (implemented):**
- `CalendarManager` with encrypted persistence (`calendar_events.json.enc`), proxy mode for IPC client.
- `RecurrenceEngine` (RFC 5545 RRULE: DAILY/WEEKLY/MONTHLY/YEARLY, BYDAY, BYMONTHDAY, INTERVAL, COUNT, UNTIL).
- Six protocol message handlers (CALENDAR_INVITE/RSVP/UPDATE/DELETE, FREE_BUSY_REQUEST/RESPONSE).
- Service-interface CRUD (`createCalendarEvent`/`updateCalendarEvent`/`deleteCalendarEvent`) — works both in-process (Android) and via IPC (Desktop).
- IpcClient calendar proxy with 4 event handlers (`calendar_invite`, `calendar_rsvp`, `calendar_event_updated`, `calendar_reminder`).
- Event editor (title, 5 categories, date/time, location, recurrence, reminders, group, RSVP, free/busy visibility, task priority).
- Chat-integration card for group events (RSVP buttons, call start, status display).
- iCal import/export (`ical_engine.dart`) — RFC 5545 VCALENDAR/VEVENT/VTODO/VALARM, RRULE, EXDATE, priority mapping, text escaping.
- PDF print for 4 date-based views (A4 portrait for day/year, landscape for week/month, system print dialog via `printing`).

**Views & Reminders:**
- Five views including `CalendarView.tasks` — sorted by open/due/priority, checkbox toggle, priority badges, overdue highlighting.
- Reminders: daemon fires `onPostNotificationAndroid` + `notificationSound.playMessageSound()` + `vibrate()` when due — reaches user even when GUI is closed or in background.
- Birthdays (§11.1.4): `ContactInfo.birthdayMonth/Day/Year` fields (local-only, never broadcast), `CleonaService._syncCalendarBirthdays()` runs on identity init and after contact-accept, `contact_set_birthday` IPC + birthday dialog in `contacts_screen.dart`.

**External sync (§11.2.1–§11.2.4) implemented:**
- `CalDAVClient` (pure-Dart RFC 4791, Basic over HTTPS, no external deps).
- `GoogleCalendarClient` (OAuth2 Loopback + PKCE per RFC 8252/7636, incremental `syncToken` deltas with 410-resync fallback).
- `CalendarSyncService` orchestrator (two-phase pull→push, per-identity opt-in, encrypted config + state).

**Local ICS bridge (§11.2.5):** `LocalIcsPublisher` writes/reads `.ics` file for Thunderbird/Outlook/Apple Calendar subscription. Three directions (export/import/bidirectional), atomic writes (tmp+rename), mtime+content-hash dedup, UID-tracked delete detection.

**Conflict resolution (§11.2.6):** bounded (200) `SyncConflict` log with losing-event JSON snapshots, Restore action in UI, semantic-equals gating to suppress bookkeeping-only conflicts. Opt-in `askOnConflict` queues `PendingConflict` entries for user decision via `calendar_sync_conflict_pending` IPC event.

**Adaptive polling** (FCM substitute per §11.2.3): `CalendarSyncService.setForeground(bool)` + `calendar_sync_set_foreground` IPC — 3 min while calendar UI is open, 15 min otherwise. Immediate sync on background→foreground transitions.

**Settings UI:** `calendar_sync_screen.dart` with CalDAV form (server discovery), Google OAuth loopback via `url_launcher`, local-ICS file-picker, conflict-log dialog with restore, pending-conflict side-by-side decision dialog. Entry point is the calendar screen's three-dot menu (`calendar_screen.dart` PopupMenuButton, fourth item `sync`, alongside import / export / print) — not the system settings screen; calendar-sync belongs to the calendar surface. Body wrapped in `SafeArea(top: false, ...)` so the Android gesture-bar does not occlude the bottom hint on edge-to-edge devices.

**Local CalDAV server (§11.2.7):** `lib/core/calendar/sync/caldav_server.dart` — HTTP server on `127.0.0.1:19324` (configurable) that exposes each identity's calendar as a CalDAV endpoint. Desktop calendar apps (Thunderbird, Outlook 2016+, Apple Calendar, Evolution, GNOME Calendar, KDE Korganizer) sync bidirectionally **without any external server**. Subset of RFC 4791 sufficient for read-write sync: OPTIONS, PROPFIND (current-user-principal / calendar-home-set / calendar-list / calendar props with ctag / event hrefs+ETags), REPORT `calendar-query` + `calendar-multiget`, GET, PUT with `If-Match`/`If-None-Match` → 412, DELETE with `If-Match`. HTTP Basic auth over loopback. Username = first 16 hex chars of node-id; password = daemon-wide token (opt-in, regeneratable). Four IPC commands (`caldav_server_state/set_enabled/regenerate_token/set_port`). UI card in `calendar_sync_screen.dart` with copy-URL + copy-token buttons.

**Android CalendarContract bridge (§11.2.8):** `android/app/src/main/kotlin/.../CalendarContractHandler.kt` (Kotlin MethodChannel handler) + `lib/core/calendar/sync/android_calendar_bridge.dart` (Dart wrapper). Mirrors Cleona events into the Android system calendar (Samsung Calendar / Google Calendar / any CalendarContract consumer) via `account_type=ACCOUNT_TYPE_LOCAL` so the events never leave the device. Push-only (edits happen in Cleona, Android side is a read-only mirror). `SYNC_DATA1` stores Cleona's eventId so upserts can find rows without a parallel lookup. RRULE-vs-DTEND handling per CalendarContract's exclusive rules. Diff-delete pass removes Android-side rows whose Cleona pendant has vanished. Runtime `READ_CALENDAR` + `WRITE_CALENDAR` permissions (requested in-UI on first sync). The full lifecycle (ensure → upsert → remove → re-sync) is verified end-to-end on the emulator including `adb shell content query` against the system provider.

**Android in-process bridge (§11.2.9):** `lib/core/calendar/sync/in_process_bridge.dart` (`InProcessCalendarSyncBridge`) mirrors the `IpcClient` calendar-sync API 1:1 and delegates directly to `CleonaService.calendarSyncService`. `CalendarSyncScreen._ipc` is `dynamic`-typed (duck dispatch), screen code unchanged across both platforms. CalDAV + local-ICS + conflict resolution + adaptive polling all work. Stubs (hidden in the UI via `bridge.isOnAndroid`): Google OAuth loopback (activity lifecycle not reliable) and the local CalDAV server (long-running listener + wrong use case on Android — the platform-native solution is the bridge from §11.2.8).

**Tests:**
- Smoke `smoke_calendar_sync.dart`: 46 tests, PASS — config JSON round-trip for all three provider types, `SyncConflict`/`PendingConflict` persistence, CalDAV multistatus XML parsing, live `LocalIcsPublisher` export→import→conflict round-trip.
- E2E `gui-50-calendar-sync.spec.ts`: 83 tests in 13 parts A–M — including 9 extended negative tests (empty path, `/proc` write-fail, missing file on import, malformed JSON, rapid configure/remove, cleanup-on-disk-then-reconfigure, all-provider status-shape coherence) and 23 tests for the local CalDAV server (Parts K/L/M: IPC surface, real wire protocol via `ssh + curl`, negative paths).
- `test/integration/caldav_integration_test.dart` (47 tests, 10 flows) — wire-level validation of `CalDAVClient` + `CalendarSyncService` against a pure-Dart RFC-4791 fixture server.
- `test/integration/caldav_server_test.dart` (29 tests, 6 flows) — our own `CalDAVClient` talking to our own `CalDAVServer` end-to-end. Covers auth failure, discovery, REPORT, full CRUD, round-trip (GUI-created events appear to the external client), ctag changes.
- Android bridge verified live on `emulator-5554`. The adb-based verification pattern is also available as `scripts/verify-android-calendar-bridge.sh` (`list` / `events` / `expect-events` / `expect-absent` / `sync-data1` subcommands, CI-optional — requires an attached device with the bridge opt-in active).

**Security hardening:**

Post-ship security review of all §11.2 external sync code paths — the only place in the app where Cleona contacts non-P2P infrastructure. Six concrete findings fixed:

- **Constant-time token comparison on the local CalDAV server** (`caldav_server.dart`). Prior `pass != _token` leaked timing information to any local process that could measure response latency, which matters because the token grants access to every identity's calendar.
- **Cross-origin redirect refusal in the CalDAV client** (`caldav_client.dart`). A compromised or impersonated CalDAV server could have returned `302 Location: http://attacker.tld/...`, and the client would have resent the Basic-auth header there. Same-scheme/host/port redirects (e.g. `.well-known` → `/dav/`) remain allowed; any other redirect raises `CalDAVException` without the next hop being contacted.
- **5 MB request-body cap on the local CalDAV server** (`caldav_server.dart:_readBody`). Combined with the DNS-rebinding defense below this closes an OOM vector where a malicious browser page trickles gigabyte PUTs to 127.0.0.1.
- **Symlink refusal + 10 MB size cap in the local ICS bridge** (`local_ics_publisher.dart`). Export refuses to write through a symlink (would otherwise let a co-tenant swap the `.ics` path for `~/.ssh/authorized_keys`); import checks `stat.size` before `readAsString` (shared-folder OOM).
- **`http://`-in-the-clear warning in the CalDAV configure dialog** (`calendar_sync_screen.dart` + i18n for de/en/es/fr). Shown live as the user types, unless the host is `127.0.0.1` / `localhost` / `::1` where loopback http is legitimate.
- **Host-header check on the local CalDAV server** (DNS-rebinding defense-in-depth, `caldav_server.dart:_dispatch`). Only `127.0.0.1`, `localhost`, `::1` (with or without port, IPv6-brackets handled) are accepted; anything else answers `421 Misdirected Request`.

Explicitly **cleared** during the same review (no changes needed): RRULE expansion already capped at 1000 occurrences + 10 years (`recurrence_engine.dart`); Google OAuth state is 192 random bits + single-shot callback server (brute-forcing infeasible); PKCE is correct S256 with `Random.secure()`; no `badCertificateCallback` overrides anywhere; no credential strings in log statements; Android bridge correctly uses `ACCOUNT_TYPE_LOCAL`; CalDAV server path parsing already reduces to an opaque eventId lookup, not a filesystem path.

Out of scope: XML-parser hardening (code uses regex extraction, not `XmlDocument` — documented so a future refactor reinstates DTD/external-entity disabling); full WAF on loopback (a local attacker with filesystem access already has the token).

**Deliberately not implemented:**
- **FCM-style real-time push** — architecturally declined per §11.2.3 (a fully P2P client has no central HTTPS webhook for Google Calendar Watch API and no backend for FCM). Adaptive polling is the documented substitute.
- **Two-way Android sync (SyncAdapter + Account Authenticator)** — full rationale + reconsideration triggers in §11.2.8.1. Summary: ~800–1200 lines of Kotlin for a feature that would silently drop group/RSVP/identity metadata on every Android-side edit, widen the trust boundary to every app with `WRITE_CALENDAR`, and complicate the conflict story from §11.2.6. The push-only bridge covers every user-visible use case (system-calendar visibility, homescreen widget, system reminders); one-shot Android → Cleona import could be added later in ~150 lines without the SyncAdapter machinery.

---

### 11.2 Calendar External Sync

External sync connects the Cleona calendar with existing calendar systems. This is implemented as an opt-in feature because it requires network access to external servers — a concept otherwise foreign to Cleona's architecture.

**Transport duality:** On desktop the GUI talks to the daemon-internal `CalendarSyncService` over the IPC channel (`IpcClient` methods). On Android no separate daemon process runs, so there is no IPC channel either — therefore `lib/core/calendar/sync/in_process_bridge.dart` (`InProcessCalendarSyncBridge`) provides an API that mirrors the `IpcClient` calendar-sync interface 1:1 (same method names, same callback names) and forwards calls directly to `CleonaService.calendarSyncService`. The `CalendarSyncScreen._ipc` getter is `dynamic`-typed (duck dispatch), so the exact same screen code runs on both platforms. Details see §11.2.9.

#### 11.2.1 Sync Architecture

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

#### 11.2.2 CalDAV Sync (Thunderbird, Nextcloud, etc.)

- Standard CalDAV protocol (RFC 4791) with iCal data format (RFC 5545).
- The Cleona daemon acts as a CalDAV client, periodically syncing with the configured CalDAV server.
- RRULE, VTODO, VALARM are mapped 1:1 to Cleona's internal model.
- Conflict resolution: Last-write-wins with conflict notification to the user.

#### 11.2.3 Google Calendar Sync

- OAuth2 authentication via system browser (no embedded WebView).
- Google Calendar API v3 for read/write access.
- **Adaptive polling, not FCM push.** Google Calendar's real-time push delivery (Watch API) requires a publicly-reachable HTTPS webhook, which a fully P2P client has no central authority to provide. FCM itself assumes a backend server that owns the FCM API key and forwards push payloads to devices — again infrastructure Cleona deliberately does not run. Instead, the sync service runs two cadences: a **foreground interval** (default 3 min) while the user has the calendar screen open, and a **background interval** (default 15 min) otherwise. The GUI signals lifecycle transitions via the `calendar_sync_set_foreground` IPC command. Manual "Sync now" is always available. This preserves the decentralized architecture while keeping perceived latency acceptable during active use.
- Shared calendars in Google are synced as read-only imports.

#### 11.2.4 iCal File Import/Export

Even without live sync, the calendar supports one-shot import/export:
- **Import:** `.ics` files (drag & drop or file picker) are parsed and added to the local calendar.
- **Export:** Any view or date range can be exported as `.ics` file for sharing.

#### 11.2.5 Local ICS Bridge (Thunderbird / Outlook / Apple Calendar)

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

#### 11.2.6 Conflict Resolution

When the same event has been modified both locally and externally between sync runs, the service applies **last-write-wins** based on `updatedAt`. Every LWW decision is recorded in a bounded (200-entry) conflict log stored in the encrypted sync-state file:

- Each entry captures: provider (`caldav`/`google`/`localIcs`), winning side (`local` or `external`), losing side's JSON snapshot, timestamp, event title.
- The Calendar Sync settings screen exposes the log with a "Restore" action per entry — selecting it overwrites the current local event with the losing snapshot.
- The log is advisory: sync itself never stops, so automatic sync never feels interrupted.

Optionally, each provider can opt into **`askOnConflict` mode**. When enabled, a real conflict pauses the event instead of resolving it — the daemon emits a `calendar_sync_conflict_pending` IPC event with both sides' JSON, the GUI shows a dialog ("Keep local version" vs "Keep external version"), and sync picks up based on the user's choice. Pending conflicts persist across daemon restarts.

Semantic equality (title, description, location, time, recurrence, cancellation) is checked before declaring a conflict, so bookkeeping-only differences (e.g. server re-serialized `updatedAt`) do not flood the log.

#### 11.2.7 Local CalDAV Server

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

**Deliberately not implemented**: WebDAV ACL / owner / permissions (single-user), `sync-collection`/`sync-token` reports (clients fall back to ctag polling with no observable downside), server-side free/busy REPORT (Cleona has its own P2P free/busy protocol; see §11.1.3).

#### 11.2.8 Android CalendarContract Bridge

On Android, the calendar app of choice (Samsung Calendar, Google Calendar, Divoom Calendar, the launcher's "Today" widget, etc.) reads from the platform's shared `CalendarContract` provider. Cleona mirrors each identity's events into that provider so they appear alongside everything else the user already sees — no duplicate-reminder plumbing, no separate widget, and no need to open Cleona at all just to glance at the day.

The mirror is **push-only** (one-way, Cleona → Android). Edits still happen in the Cleona UI. See §11.2.8.1 below for the full rationale of that decision and the concrete signals that would trigger a reconsideration.

**Implementation (`lib/core/calendar/sync/android_calendar_bridge.dart` + Kotlin `CalendarContractHandler`):**

- One row in `CalendarContract.Calendars` per Cleona identity, with `account_type = ACCOUNT_TYPE_LOCAL` and `owner_account = "Cleona <short-id>"`. `LOCAL` means the events never leave the device — no Google sync is involved.
- Events live in `CalendarContract.Events` with Cleona's `eventId` stashed in `SYNC_DATA1`. Upserts look up the row through that column, so we never have to maintain a parallel ID map.
- RRULE support: CalendarContract requires events with `RRULE` to use `DURATION` with `DTEND = null` (and vice-versa). The bridge enforces this, converting Cleona's start/end/rrule into whichever shape the provider wants.
- Diff-delete: after each full push the bridge lists the calendar's rows and deletes any whose `SYNC_DATA1` no longer matches an active Cleona event. This keeps the Android calendar tidy when the user deletes an event in Cleona.
- Permissions (`READ_CALENDAR` + `WRITE_CALENDAR`) are requested at runtime the first time the user taps "Sync now" in Settings. If the user denies, the bridge falls back to a "permission missing" hint.
- Calendar-provider writes to `SYNC_DATA1` and deletes on `ACCOUNT_TYPE_LOCAL` rows require the request URI to carry `CALLER_IS_SYNCADAPTER=true` + `ACCOUNT_NAME` + `ACCOUNT_TYPE` query parameters. `ensureCalendar` already had them; `upsertEvent` and `deleteEvent` build a `syncAdapterEventsUri` helper and use it for every event mutation.

**Deliberately not implemented (in addition to the two-way-sync discussion in §11.2.8.1):**
- **Automatic on-event-change push.** The UI exposes a manual "Sync now" trigger. An automatic hook would couple `CalendarManager` directly to the bridge (violating the cross-platform separation, since the bridge only exists on Android) and produce inconsistent behaviour across Desktop/iOS/Android builds. Users who want continuous mirroring can tap once; the full-push diff-delete is idempotent and cheap enough to re-run.

##### 11.2.8.1 Why no two-way sync (decision record)

**The decision:** The bridge writes into `CalendarContract` but does not read back changes the user makes in the Android calendar app. Edits flow Cleona → Android only; changes on the Android side are overwritten by the next sync.

**What two-way sync would actually require:**

1. A Java/Kotlin `AbstractAccountAuthenticator` subclass + `Service` declared in the manifest with `android.accounts.AccountAuthenticator` intent filter and a matching `authenticator.xml` resource.
2. A `SyncAdapter` subclass (another service) declared with `android.content.SyncAdapter` intent filter and a matching `syncadapter.xml`. The adapter handles `onPerformSync(Account, Bundle, String authority, ContentProviderClient, SyncResult)` — a blocking method with no Flutter equivalent, so the actual sync logic would have to duplicate Dart-side logic in Kotlin or marshal it across the MethodChannel with careful lifecycle handling.
3. A real Cleona `Account` registered with the system's `AccountManager`. Each identity would need either its own account row (visible in Settings → Accounts, with the user able to delete it and silently break sync) or a shared "Cleona" account holding all identities (which breaks Android's per-account sync settings).
4. A `ContentObserver` or explicit poll loop on the Dart side to pick up Android-side edits and funnel them back into `CalendarManager`, including conflict detection against the Cleona `SyncConflict` log (§11.2.6).
5. Additional `AUTHENTICATE_ACCOUNTS` + `MANAGE_ACCOUNTS` + `WRITE_SYNC_SETTINGS` permissions in the manifest (some of these are restricted after API 23 and require user-visible grants).

Rough estimate: **~800–1200 lines of Kotlin** + ~200 lines of Dart + three new manifest entries, plus the inevitable bugfix pass after it first ships. Compare this to the ~200 lines of Kotlin + ~200 lines of Dart for the current push-only bridge.

**Why the benefit does not justify the cost:**

- **Cleona is the authoritative source of truth.** A Cleona event can belong to a group (via `CALENDAR_INVITE` in §11.1.8), carry RSVP state, reference an ongoing call, live under one specific identity in a multi-identity setup, or be a birthday mirror from a contact. The Android calendar app has no concept of any of these — it sees `title`, `dtstart`, `dtend`, `rrule`, `description`, `location`. A user who edits the event on the Android side can only modify that subset; their edit cannot express "change the group this invite targets" or "mark this as tentative for identity Alice only". Propagating an Android-side edit back into Cleona therefore silently drops meaningful state.
- **Trust boundary.** Once `WRITE_CALENDAR` is granted, *any* app with that permission (Samsung Calendar, Google Calendar, arbitrary third-party widgets) can mutate Cleona's events. Two-way sync would turn those apps into effective editors of the user's end-to-end-encrypted P2P calendar. Push-only keeps the trust boundary where it belongs: Cleona is the only writer, the system calendar is a read-only mirror.
- **Conflict resolution gets worse, not better.** §11.2.6 already defines a last-write-wins + opt-in-prompt conflict story for CalDAV and Google Calendar. Adding Android as a third conflict source means every CalendarManager write would have to check against Android's state via a `ContentObserver` — a permanent foreground thread — and the UX of conflict prompts becomes noisier without any clear win over "edit it in Cleona where you have the full picture".
- **Users rarely edit through a mirror.** The use cases driving the bridge request — seeing Cleona events next to work events in Samsung Calendar, Homescreen widget glance-ability, system-level reminders — are all read-only. Nobody has asked for "let me edit my Cleona event from Samsung Calendar".

**Concrete signals that would trigger reconsideration:**

1. Repeated user reports of "I edited a Cleona event in Samsung Calendar and it got overwritten" — this would mean users *are* using the Android side to edit, regardless of what we expected.
2. A concrete use case that requires reading from Android first — for example, importing a pre-existing Android calendar into a new Cleona identity. That would be an *import-once* feature, not full two-way sync, and could be built in ~150 lines without the SyncAdapter machinery.
3. Android introducing a simpler "observed external calendar" API that doesn't need SyncAdapter/AccountAuthenticator. Unlikely in practice.

If any of those land, the implementation plan is: start with (2) one-shot import as a separate IPC command, measure how many users invoke it, then decide whether the remaining ~1000 lines of SyncAdapter code are justified. Until then, the documented scope is firmly "push-only mirror".

#### 11.2.9 Android In-Process Bridge

On desktop (Linux/Windows) `CalendarSyncService` is part of the daemon process; the GUI talks to it via `IpcClient` (Unix socket or TCP+auth token). On Android everything runs in a single process (see §15.2), so there is no IPC channel — the GUI would have neither an `IpcClient` at hand nor would socket/TCP operations be meaningful purely locally.

`lib/core/calendar/sync/in_process_bridge.dart` (`InProcessCalendarSyncBridge`) solves this by mirroring the `IpcClient` calendar-sync API exactly 1:1 — same method signatures (`calendarSyncStatus`, `calendarSyncCalDavConfigure`, `calendarSyncLocalIcsConfigure`, `calendarSyncTriggerNow`, `calendarSyncSetForeground`, `calendarSyncResolveConflict`, `calendarSyncRestoreConflict`, …), same callback names (`onCalendarSyncStatusUpdate`, `onCalendarSyncConflictPending`, …) — and delegating directly to the active identity's `CleonaService.calendarSyncService`. The `CalendarSyncScreen._ipc` getter is `dynamic`-typed; the same screen code runs unchanged on both platforms.

**What the bridge offers on Android:** CalDAV (user/password + discovery), local-ICS export/import/bidirectional, conflict resolution including the `askOnConflict` pending queue, manual `Trigger now`, adaptive polling with `setForeground()`. Works without a daemon process because `CleonaService` itself runs in-process.

**What is deliberately stubbed** (`bridge.isOnAndroid` hides the UI cards):

- **Google OAuth loopback flow.** Requires a short-lived HTTP server on `127.0.0.1:<random>` that the system browser visits after consent (RFC 8252). On Android foreground apps this is not reliably achievable (activity lifecycle, Doze, permissions). A native Custom-Tabs implementation would be the right solution — non-trivial effort, hence `TODO`.
- **Local CalDAV server (§11.2.7).** Requires a long-lived HTTP listener on `127.0.0.1:19324`. Not guaranteed to run in the background on Android, and the use case ("desktop calendar app syncs against a local server") simply does not exist on Android — the platform-native solution is the `CalendarContract` bridge from §11.2.8.

With that, Android sync no longer has real feature gaps for the main path CalDAV+ICS+conflicts; the only loss is Google Calendar (workaround: the user sets up Google Calendar via the web interface of a third-party CalDAV gateway and gives Cleona its CalDAV URL).

---

### 11.3 Polls

Cleona supports decentralized polls in groups and channels, enabling collaborative decision-making without any central server. Poll votes are distributed via the existing message infrastructure and aggregated locally by each participant.

> **Source:** `lib/core/polls/poll_manager.dart`, handlers in `lib/core/service/cleona_service.dart`, crypto in `lib/core/crypto/linkable_ring_signature.dart` + `lib/core/crypto/sodium_ffi.dart`, UI in `lib/ui/screens/poll_editor_screen.dart` + `lib/ui/components/poll_card.dart`. Proto message types `POLL_CREATE=146`, `POLL_VOTE=147`, `POLL_UPDATE=148`, `POLL_SNAPSHOT=149`, `POLL_VOTE_ANONYMOUS=150`, `POLL_VOTE_REVOKE=151`.

#### 11.3.1 Design Principles

1. **Fully decentralized:** No central vote counter. Each node aggregates votes from received messages and arrives at the same result through message convergence.
2. **Tamper-resistant:** Every vote is signed by the voter's Ed25519 key. Votes cannot be forged or modified in transit.
3. **Integrated:** Polls appear as interactive cards in the chat. Date polls can create calendar events (§11.1). Poll results can trigger group call scheduling.
4. **Privacy-flexible:** Polls can be open (everyone sees who voted what) or anonymous (only totals visible).

#### 11.3.2 Data Model

##### 11.3.2.1 Poll Creation

```
PollCreate {
  pollId:         UUID
  question:       string (the poll question or title)
  description:    string (optional, additional context)
  pollType:       PollType
  options:        List<PollOption>
  settings:       PollSettings
  groupId:        bytes (group or channel this poll belongs to)
  createdBy:      bytes (creator's user ID)
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

##### 11.3.2.2 Poll Vote

```
PollVote {
  pollId:         UUID
  voterId:        bytes (voter's user ID)
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

##### 11.3.2.3 Poll Update

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

#### 11.3.3 Vote Distribution

##### 11.3.3.1 In Groups (Pairwise Fanout)

Votes are distributed identically to regular group messages:

1. Voter creates a `PollVote` payload, wrapped as an `ApplicationFrame`.
2. The frame is encrypted individually to each group member via Per-Message KEM (see §9.1 Group Encryption) and dispatched per recipient via `sendToUser(userId)`.
3. Each group member receives the vote, verifies the Ed25519 signature on the inner frame, and updates their local vote tally.
4. Since all members receive all votes via Fanout, every node converges to the same result.

**Duplicate detection:** Each identity can have at most one active vote per poll. The key is `(pollId, voterId)`. If `allowVoteChange` is true, a newer vote (by `votedAt` timestamp) replaces the previous one. If false, the first valid vote is permanent.

**Late joiners:** When a new member joins a group, they receive the poll state through the group's restore mechanism. The poll creator can optionally re-broadcast the current tally as a `POLL_SNAPSHOT` for immediate catch-up.

##### 11.3.3.2 In Channels (Broadcast)

For public channels with potentially hundreds of subscribers:

1. The poll creator sends `POLL_CREATE` via channel broadcast.
2. Subscribers send `POLL_VOTE` back to the creator only via `sendToUser(creatorUserId)` — not broadcast — avoiding N² message fan-out.
3. The creator periodically broadcasts `POLL_SNAPSHOT` with aggregated totals.
4. On poll close, the creator broadcasts the final `POLL_SNAPSHOT` with complete results.

This reduces message volume from O(N²) to O(N) for large channels.

```
PollSnapshot {
  pollId:         UUID
  totalVotes:     int32
  optionCounts:   List<OptionCount>  // (optionId, count) pairs
  closed:         bool
  snapshotAt:     int64
}
```

#### 11.3.4 Calendar Integration (Date Polls)

Date polls (`PollType.DATE_POLL`) bridge polls and calendar:

1. **Creation:** The poll creator selects time slots from the calendar view. Each slot becomes a `PollOption` with `dateStart` and `dateEnd`.
2. **Free/Busy overlay:** When viewing a date poll, the voter can optionally request Free/Busy data from all invitees (see §11.1 Calendar — Free/Busy Protocol) to see which slots conflict with existing appointments.
3. **Result → Event:** When the poll closes, the winning time slot can be converted to a `CalendarEvent` via `convertDatePollToEvent`. A `CALENDAR_INVITE` is sent to all participants automatically.
4. **Group Call:** If the winning event has `hasCall: true`, a group call is automatically scheduled.

#### 11.3.5 Chat Display

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

#### 11.3.6 Permissions

| Action | Groups | Channels |
|--------|--------|----------|
| Create poll | Owner, Admin, Member | Owner, Admin |
| Vote | All members | Members + Subscribers (configurable) |
| Close poll | Creator, Owner, Admin | Creator, Owner, Admin |
| Delete poll | Creator, Owner, Admin | Creator, Owner, Admin |
| View results | All members (if showResultsBeforeClose) | All subscribers (if showResultsBeforeClose) |

#### 11.3.7 Protocol Messages (Polls)

| MessageType | Direction | Description |
|-------------|-----------|-------------|
| `POLL_CREATE` | Creator → all members | New poll with question, options, settings |
| `POLL_VOTE` | Voter → all members (groups) or → creator (channels) | Individual vote |
| `POLL_UPDATE` | Creator/Admin → all members | Close, reopen, add/remove options, extend deadline |
| `POLL_SNAPSHOT` | Creator → all subscribers (channels only) | Aggregated results broadcast |

All poll messages are carried as `ApplicationFrame` payloads, encrypted via Per-Message KEM (§3.3) and delivered through the Three-Layer Delivery Pattern (§5.1) — Direct → Relay → S&F + Mailbox-Pull.

#### 11.3.8 Storage

Polls are stored in the encrypted SQLite database:
- `polls` table: poll definition (question, options, settings, creator, deadline, closed status)
- `poll_votes` table: individual votes, keyed by `(pollId, voterId)`, with timestamp for change detection

Closed polls are retained for 90 days, then auto-deleted (configurable per group in chat settings, see §14.7.2 Data Management & Storage).

### 11.4 Anonymous Voting (Linkable Ring Signatures)

When `anonymous == true`, votes are cryptographically anonymous using **Linkable Ring Signatures**. No participant — not even the poll creator — can determine who voted what, while double-voting is still detected and prevented.

#### 11.4.1 Concept

The core problem: prove you are a legitimate group member and haven't voted before, without revealing which member you are. Linkable Ring Signatures solve this with two properties:

1. **Ring Signature:** The voter signs their vote using all N group members' public keys as the "ring". The signature proves "one of these N people signed this" without revealing which one.
2. **Key Image (Linkability Tag):** A deterministic value derived from the voter's private key and the poll ID. The same voter always produces the same key image for the same poll, but the key image cannot be traced back to any specific public key. If the same key image appears on two votes, the second is rejected as a duplicate.

#### 11.4.2 Cryptographic Protocol

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

#### 11.4.3 Vote Message Format (Anonymous)

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

#### 11.4.4 Implementation

- **Curve operations:** Ed25519 scalar multiplication and point addition via libsodium (`crypto_scalarmult_ed25519`, `crypto_core_ed25519_add`). These primitives are already available in Cleona's `sodium_ffi.dart`.
- **Hash-to-point:** `crypto_core_ed25519_from_uniform()` (libsodium) maps a 64-byte hash to a valid Ed25519 point.
- **Signature size:** Proportional to group size N. For a 20-member group: 32 bytes key image + 20 × 64 bytes = ~1.3 KB. Acceptable for poll votes.
- **Verification cost:** N point multiplications per vote verification. For N=50, this takes <10ms on modern hardware. Negligible.
- **Anonymity set:** The anonymity is only as strong as the group size. A 5-person group provides limited anonymity; a 50-person channel provides strong anonymity. The UI shows a hint: "Anonymity set: N members".

#### 11.4.5 Vote Change with Anonymity

When `allowVoteChange == true` and the poll is anonymous, the voter cannot simply send a new vote — the key image would be flagged as a duplicate. Instead:

1. The voter sends a `PollVoteRevoke` with their key image and a proof of key image ownership (a signature over "revoke" using the same ring).
2. All participants remove the old vote for that key image.
3. The voter submits a new `PollVoteAnonymous` — same key image (deterministic), new choice.

This allows changing votes while maintaining anonymity.

#### 11.4.6 Limitations

- **Group size = anonymity set:** In a 3-person group, anonymous voting provides minimal privacy. The UI warns when the group has fewer than 7 members.
- **Timing analysis:** If votes arrive in rapid succession, the order of arrival could hint at identity (network proximity). Mitigation: votes are delayed by a random 0–30 second jitter before broadcast.
- **Collusion:** If N-1 members collude, they can deduce the last member's vote by elimination. This is inherent to any anonymous voting system with a known voter set.

---

## 12. Synchronization Strategy

Cleona's synchronization is fundamentally event-driven. Unlike traditional messengers that poll servers at intervals, Cleona pushes messages through the network the instant they are created. This section describes the startup sequence, background behavior per platform, and network change recovery. (Push wake-up was considered as an additional layer and rejected; see §12.4.)

### 12.1 Design Principles

1. **Push-first:** Messages flow the moment they are created. No periodic sync intervals during normal operation. The only polling is a single startup poll after launch.
2. **Battery-aware:** Wake-up cost (radio activation, crypto operations) only occurs when there is actual work — an incoming message, an outgoing message, or a startup poll. No background timer waking the device every N minutes.
3. **Resilient recovery:** Network changes (WiFi→mobile, IP change, roaming) are detected automatically and trigger a complete recovery sequence — not just a reconnect, but a full re-establishment of routing, discovery, and pending message delivery.
4. **Platform-adaptive:** Each platform (Android, iOS, Linux, Windows) has a tailored background strategy that maximizes responsiveness within OS constraints.

### 12.2 Background Timers + Startup

This section consolidates the boot-time behavior, the one-shot startup poll, the priority order during that poll, and the long-running periodic timers that keep the routing/discovery state fresh during normal operation.

#### 12.2.1 Startup Initialization Sequence

When a node starts, it follows a deterministic initialization sequence:

```
 1. Load routing table from disk (cached peer addresses)
 2. Record startup timestamp (_startedAt)
 3. Initialize components: DHT RPC, ACK tracker, MailboxStore,
    S&F + Mailbox-Pull subsystem (§5.5 / §5.6)
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
13. Start background timers (see §12.2.4):
    - Maintenance timer: 60 seconds (routing table cleanup, stale peer pruning)
    - Peer exchange timer: 120 seconds (mesh discovery propagation)
    - DV safety-net timer: 1 hour (full Distance-Vector route exchange)
```

**Subnet scan fallback:** If after step 10 no recently reachable peer exists (no peer has `lastSeen > _startedAt`), a subnet scan is triggered — unicast PING probes across the local /16 network range at /24 resolution on port 41338.

#### 12.2.2 Startup Poll

After initialization completes, the node performs a single poll to collect missed messages:

1. Send `FRAGMENT_RETRIEVE` to all recently-confirmed peers to collect erasure-coded fragments from DHT mailbox (§5.4).
2. Simultaneously, send `PEER_RETRIEVE` to all recently-confirmed peers to collect Store-and-Forward whole messages (§5.5).
3. Process and deduplicate all received messages (§5.7).

After this initial poll, the node switches to pure push-based operation. No further polling occurs during normal operation (except after network changes — see §12.3 — or Restore Broadcasts — see §6.3).

#### 12.2.3 Sync Priority During Startup

Within the startup poll window, operations are strictly prioritized:

1. Retrieve own pending message fragments from DHT mailbox (highest priority).
2. Retrieve Store-and-Forward whole messages from mutual peers (§5.5).
3. Send own queued outbound `ApplicationFrame`s from the persistent Store-and-Forward + Mailbox-Pull buffer (§5.5 / §5.6).
4. Exchange peer list deltas with contacted peers (Mesh Discovery propagation, §4.5).
5. Update DHT routing table with fresh peer information (§4.4).
6. Forward relay fragments for other users (lowest priority, only if time remains).

#### 12.2.4 Background Timers

Three periodic timers run during normal operation:

| Timer | Interval | Purpose |
|-------|----------|---------|
| Maintenance | 60 seconds | Routing table cleanup, stale peer pruning, mailbox housekeeping |
| Peer exchange | 120 seconds | Share peer list deltas with known peers (Mesh Discovery, §4.5) |
| DV safety-net | 1 hour | Full Distance-Vector route exchange with all neighbors (§4.4) |

Additionally, a **welcome route update** fires 500 ms after a new neighbor is detected, sending full DV routes to the newcomer. A **DV catch-up** is triggered when the last full route exchange was more than 60 seconds ago.

Beyond these three core timers, several long-period housekeeping checks fire less frequently and are listed here for completeness:

| Check | Interval | Purpose |
|-------|----------|---------|
| DHT update-manifest poll | 6 hours | Refresh the cached signed update manifest from DHT (§19.5.5) |
| Authorization manifest refresh | 20 hours | Re-verify identity-resolution authorization records (§4.3) |
| Liveness short-cycle | 15 minutes | Republish per-device liveness record while reachable (§4.3) |
| Liveness long-cycle | 1 hour | Liveness republication backstop when no triggering event has fired (§4.3) |

The 6-hour update-manifest poll keeps the cached manifest fresh; users with stale caches see any required UpdateRequiredScreen on the next start after the cache refreshes (see §19.5.7 for the full UX flow).

### 12.3 Network Change Detection & Recovery

Network changes (WiFi toggle, mobile data switch, roaming, IP change) are detected via two mechanisms:

1. **Platform events:** `connectivity_plus` on Flutter (GUI), periodic `NetworkInterface` polling on headless daemons.
2. **Mass route-down inference:** When ≥3 distinct peer routes fail within 30 seconds, a network change is inferred even without OS notification. This catches silent IP changes that `connectivity_plus` misses.

**Recovery sequence** (executed when a network change is detected):

```
 1. Verify IPs actually changed (skip false alarms from Android connectivity_plus)
    — Bypassed (force=true) for mass-route-down inference (ISP may change public IP
    without local IP change)
 2. Reset NAT traversal state (public IP, port mapping)
 3. Reset port mapper
 4. Reset per-address consecutiveFailures counters and exponential backoff for all peers
    (failure history from the old network is meaningless — addresses must be re-probed
    under new conditions)
 5. Mark all per-peer relay-routes and Distance-Vector routes as `stale` with a 30 s
    revalidation deadline and cost penalty +5 (instead of clearing them). Routes that
    re-confirm via PONG/DV-update within 30 s keep their topology with cost restored;
    routes missing the deadline are dropped at that point.
 6. Reset TLS fallback state (re-attempt UDP first)
 7. Trigger fast discovery burst (broadcast + multicast on all interfaces, §4.5)
 8. Update local IP address list
 9. PING all known peers with updated addresses (primary revalidation signal for stale
    routes)
10. Re-run Kademlia bootstrap (FIND_NODE for own ID) — refreshes K-buckets in place
11. Trigger IdentityPublisher.onAddressesChanged() so liveness records (§4.3) are
    republished with the new addresses
12. Broadcast address update to all contacts via PEER_LIST_PUSH (own PeerInfo only)
13. Re-query public IP via ipify (on every network change, not just startup)
14. After 5 seconds: if still no reachable peer, trigger subnet scan fallback
```

The reset is deliberately **soft, not aggressive**. Earlier versions cleared DV-routes and per-peer relay-hints outright; the rationale was that all cached state might be stale. In practice the pathology turned out to be: when several peers experience a near-simultaneous network event (ISP-wide DHCP renewal, or — more commonly — keepalive false-positives in topologies where direct LAN peers are L2-blocked while relay paths remain healthy), every node's recovery wipes the routes the others depend on, and re-establishing from scratch compounds to many minutes of message-delivery loss instead of the assumed ≤5 seconds.

The current model preserves topology knowledge (DV cost/via mappings, K-buckets, IdentityPublisher caches, the secondary `_byUserIdHex` UserID index) and only invalidates state that is genuinely network-bound (NAT classification, public-IP observation, port mapping, per-address failure counters). Routes are revalidated, not rebuilt. A peer that was reachable before the event almost always still is; the cost penalty (+5) ensures fresh post-recovery routes are preferred while stale ones remain as a fallback during the revalidation window.

### 12.4 Push Wake-Up — Rejected (Architecture Decision 2026-04-26)

A push wake-up layer (FCM, APNs, UnifiedPush, or any peer-relayed equivalent) was considered as a means to eliminate the persistent foreground-service notification on Android and the corresponding battery-optimization configuration burden. After full architectural review, all variants were rejected:

| Variant | Reason for rejection |
|---|---|
| FCM via Bootstrap relay (centralised credential holder) | Violates "no central server" — Bootstrap is itself temporary infrastructure (§4.8) |
| FCM with credentials distributed in every APK | One extracted credential enables network-wide spam through Google's quotas; Firebase project would be shut down within hours |
| Per-user Firebase project, credentials shared with wake-relay contacts | Firebase = Google = third party; user-stated constraint excludes this |
| UnifiedPush (ntfy.sh, NextPush, self-hosted) | Requires a distributor app on the recipient phone, which itself depends on a remote server; user-stated constraint excludes this |
| Per-peer WebPush+VAPID | Cannot be received natively on Android without a third-party distributor |
| Server-role rotation between Cleona peers | Solves the routing layer (which peer holds inbound responsibility) but does not bypass Android Doze; the recipient phone still requires one of the three OS wake mechanisms |

**Android wake-up reality:** The Android OS provides exactly three mechanisms for waking a Doze-suspended app: (a) FCM/APNs (Google/Apple as third party), (b) UnifiedPush distributor (third-party server behind the distributor app), (c) foreground service with persistent notification. There is no fourth path that allows a Cleona peer to wake a sleeping recipient without involving a third party.

**Decision:** Cleona accepts the persistent foreground-service notification as the canonical Android delivery mechanism. The `CleonaForegroundService` (type `dataSync`, declared in §16.2) remains the only supported background-message-delivery path on Android. The battery-optimization toggle that previously suggested otherwise has been removed from settings, as it implied user-controlled push behaviour that does not exist. The earlier Doze-whitelisting opt-out flow has likewise been retired (no v3.0 successor; see Migration Map for v2.2 §27.10 marked `DROP`).

**Implications for users:**
- Persistent notification stays visible — this is the architecturally honest signal that Cleona is reachable in the background.
- Doze-whitelisting remains the user's choice via Android system settings; Cleona no longer requests or surfaces it (foreground-service-type apps are typically Doze-exempt for the duration of their foreground state regardless of whitelist).
- Real-time delivery on Android requires the app to be running. Without the foreground service (e.g., if the OS kills it), messages are picked up at the next WorkManager wake-up window (≥15 min OS-imposed minimum, see §12.5).

**Reconsideration triggers:** This decision should be revisited only if (1) Android adds a peer-to-peer wake API that does not require a third party, or (2) the user-stated "no third party" constraint is relaxed. Neither is on any visible roadmap.

### 12.5 Platform-Specific Background Behavior

**Android:** The in-process architecture runs all networking within the Flutter app. A foreground service (`CleonaForegroundService`, type `dataSync`) keeps the process alive and the UDP socket open for pushed messages. When the OS suspends the app (Doze mode), WorkManager schedules periodic wake-ups (minimum 15-minute OS interval). The foreground service with persistent notification provides near-instant delivery. Without it, messages arrive during the next WorkManager wake-up. **Lifecycle save:** `CleonaAppState` implements `WidgetsBindingObserver` and calls both `saveState()` (conversations, contacts, groups, channels) **and `saveNetworkState()`** (routing table, DV routing table, peer addresses) when `AppLifecycleState.paused` is received. `saveState()` prevents data loss (e.g., media message types reverting to TEXT); `saveNetworkState()` prevents cold-start peer loss — without it, Android process kills lose the learned topology and the node restarts with routes=0, peers=0.

**iOS:** Background App Refresh provides periodic wake-up windows (iOS controls exact timing). During each window, the node opens its UDP socket and receives pushed messages. iOS limits background execution time; Cleona maximizes each window.

**Linux Desktop:** The daemon process (`cleona-daemon`) runs continuously as a separate process from the GUI. The UDP socket is permanently open, providing instant push delivery. The daemon survives GUI restarts. Becomes fully offline when the system enters standby. System tray icon (GTK3 + libappindicator3) provides visual status.

**Windows Desktop:** Identical architecture to Linux Desktop. The daemon runs as a user-space process (not a Windows Service) with a system tray icon (Win32 Shell_NotifyIcon). Each Windows user gets their own daemon instance with separate data in `%APPDATA%\.cleona`. The daemon starts at user login (Registry autostart) and provides the same always-on UDP connectivity as Linux. IPC via TCP loopback (127.0.0.1) with auth-token file (`cleona.port`).

---

## 13. Network Resilience

V3.0's resilience strategy combines multi-layered DoS protection (§13.1, consolidated via subagent draft) with maintainer-triggered secret rotation and service-layer fallbacks against routing failures.

### 13.1 DoS Protection (5-Layer)

#### 13.1.1 Design Principles

1. **Defense in depth:** Five independent layers, each sufficient to mitigate a class of attack. An attacker must defeat all five simultaneously.
2. **Asymmetric cost:** Sending costs more than receiving. PoW makes bulk spam expensive; rate limiting makes burst flooding ineffective.
3. **Local decisions:** No global ban list, no centralized authority. Each node independently evaluates its peers. Consensus emerges from independent local decisions.
4. **Graceful for legitimate peers:** Startup bursts, brief connectivity issues, and normal bootstrap traffic must not trigger false positives. Score-gated banning and relay exemptions prevent penalizing honest peers.

#### 13.1.2 Layer 1: Proof of Work

Every chat-content message entering the network must carry a Proof of Work (PoW) solution in its outer `NetworkPacket`. PoW is a wire-level property — it sits in the outer frame so a node can verify and drop spam *before* spending CPU on KEM decryption of the inner `ApplicationFrame`. The algorithm is SHA-256 hashcash: the sender must find an 8-byte nonce that, combined with the packet hash, produces a SHA-256 output with at least N leading zero bits.

```
PoW Parameters:
  Algorithm:           SHA-256(data || nonce_8byte_LE)
  Default difficulty:  20 leading zero bits (~1M hashes, 50-100ms desktop, 0.5-2s mobile)
  Minimum accepted:    16 leading zero bits (transition period)
  Verification:        Recompute hash, verify leading bits + hash match
```

**PoW Exemptions:** Three categories of packets are exempt:

1. **LAN peers** (private IP: 10.x, 172.16-31.x, 192.168.x): Packets between peers on the same local network skip PoW. Authenticity is still established by the outer device-signature and inner Per-Message KEM + user-signature (see §2.4 Layered Encryption Pipeline). Detection uses `_isPrivateIp()` on both sides.

2. **Infrastructure messages**: GROUP_INVITE, GROUP_LEAVE, CHANNEL_INVITE, CHANNEL_LEAVE, CHAT_CONFIG_UPDATE, KEY_ROTATION, PROFILE_UPDATE, RESTORE_BROADCAST, TYPING_INDICATOR, READ_RECEIPT, DELIVERY_RECEIPT. Authenticated by signature and encryption.

3. **Relay-bound packets**: When the routing layer reports `directBlocked` or no reachable active targets exist, PoW is skipped. Relay-delivered packets (from=0.0.0.0) are exempt from PoW verification on the receiver — the relay's own outer device-signature carries the wire-level authenticity.

Only **chat content messages** (TEXT, IMAGE, FILE, VOICE, CALL_*) sent **directly** to **non-LAN peers** require PoW.

**Async PoW Computation:** PoW is computed in a separate Dart isolate via `ProofOfWork.computeAsync()`. The isolate loads libsodium independently. The UI shows the message immediately with "sending" status (hourglass) — the full send pipeline (compress → KEM encrypt → sign → PoW → send) runs asynchronously.

#### 13.1.3 Layer 2: Rate Limiting per Device

<!-- TODO-V3-CLARIFY: per-device or per-user? Wire-level rate-limiting must key on the device identity (DeviceID = SHA-256(network_secret + device_pubkey)) because that is what appears in the outer NetworkPacket source field. A multi-device user can legitimately occupy multiple per-source budgets — this is a design choice (one user with 5 devices gets 5x the budget) that should be confirmed during §13.1 sign-off. -->

Each node tracks traffic volume per source Device-ID using a sliding time window. The source identifier is taken from the outer `NetworkPacket` (DeviceID), not from any inner `ApplicationFrame` (UserID) — rate-limiting is a wire-layer defense and must operate before inner-frame decryption.

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

Excessive traffic from a single source is silently dropped. **Exemptions:** Relay-unwrapped inner frames, reassembled media chunks, and S&F-retrieved frames are exempt — the outer packet was already counted against the relay/storage node's budget.

**Rate limiting is throughput control, not a trust signal.** Packets dropped by the rate limiter do NOT generate `recordBad()` events. A legitimate peer (e.g. Bootstrap) can exceed burst limits during startup cascades while sending exclusively valid, HMAC-authenticated packets. Penalizing valid traffic would create a perverse incentive where high-activity nodes (Bootstrap, relay hubs) accumulate bad reputation purely from serving the network. The reputation system (§13.1.4) only records bad actions for semantically invalid behavior (failed signatures, malformed frames, unauthorized operations).

**Positive reputation from accepted traffic:** Every packet that passes the rate limiter generates a `recordGood` event for the sender's reputation score. This is critical because infrastructure messages (DHT, DV-Routing, PeerList, Relay) return early in the node-level switch-case and never reach the application-level handler. Without this, new peers doing normal bootstrap traffic could never build positive reputation.

#### 13.1.4 Layer 3: Reputation System

Nodes build reputation over time based on observed behavior. Reputation is strictly local — each node independently evaluates its peers. There is no global reputation score.

<!-- TODO-V3-CLARIFY: per-device or per-user? Reputation may legitimately key on UserID rather than DeviceID — a misbehaving user should not get a clean slate by switching devices, and an honest user should carry trust across their device fleet. Wire-layer rate-limiting (§13.1.3) is per-Device, but reputation-based banning (§13.1.6) is more naturally per-User. To be confirmed during §13.1 sign-off; the per-User choice depends on whether the outer NetworkPacket is required to disclose UserID, which it is not in v3.0 base wire format. -->

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

**Score-gated banning:** A peer with good history (score >= 0.5) is NOT temporarily banned, even if it accumulates some bad actions. Only sustained misbehavior from low-reputation peers triggers bans.

**`recordBad` sources (exhaustive):** Bad actions are recorded only for semantically invalid behavior — failed outer-device-signature verification, HMAC mismatch (non-network-member), malformed protobuf, unauthorized operations (e.g. non-owner DHT mutations). Rate-limit excess does NOT generate `recordBad` (see §13.1.3). This separation ensures that high-throughput legitimate nodes (Bootstrap, relay hubs) cannot be banned by serving the network.

#### 13.1.5 Layer 4: Fragment Budgets

Each node allocates a limited relay storage budget per source Device-ID. If a single source attempts to store an excessive number of fragments, the excess is rejected with FRAGMENT_STORE_NACK. This prevents a single attacker from filling all relay storage on a victim node.

#### 13.1.6 Layer 5: Network-Level Banning

Nodes can temporarily or permanently ban other nodes based on accumulated misbehavior. Bans are strictly local decisions — no central ban list exists. When many independent nodes ban the same attacker, the attacker becomes effectively isolated from the network through emergent consensus.

**Banned node behavior:** All packets from a banned Device-ID are dropped at the transport layer before any processing. The ban is keyed by Device-ID (not IP), so IP rotation does not bypass bans. Since Device-ID = SHA-256(network_secret + device_pubkey) (see §3.5 Device Identity Sigs and §4.10 Closed Network Model), generating a new Device-ID requires a new device-keypair — and a new device must be re-authorized by the user's existing device fleet (see §7 Multi-Device), losing all contacts and reputation.

#### 13.1.7 Attack Scenarios & Mitigations

| Attack | Layer(s) | Mitigation |
|--------|----------|------------|
| Spam flood (bulk messages) | 1+2 | PoW makes each packet expensive; rate limiter drops excess |
| Sybil (fake identities) | 5 + Anti-Sybil | New IDs start at 0.5 reputation; Social Graph Reachability (§9.4) blocks coordinated reports |
| Fragment storage exhaustion | 4 | Per-source budget prevents monopolization |
| Relay abuse (relay others' traffic) | 2+3 | Rate limiter per source; relay traffic counts against relay node's budget |
| DHT poisoning (fake entries) | 1+3 | PoW on DHT operations; low-reputation entries deprioritized |
| Startup burst (legitimate new peer) | 2+3 | Rate limiter generates `recordGood` for accepted packets; score-gate prevents banning peers with score >= 0.5 |

### 13.2 Secret Rotation

The `network_secret` (see §4.10) is Cleona's closed-network authentication. When required (for example, compromise of a build artifact, or a leaked maintainer key), the maintainer can rotate the secret — old builds then lose mesh access.

**Rotation triggers** (maintainer-triggered, not automatic):
- Suspected maintainer-key compromise
- Major architecture cut (for example, v2.2 → v3.0 with profile reset)
- Forensic necessity (anti-pollution response)

**Rotation mechanics**:

1. The maintainer re-signs the `network_channel` string, but with an additional `epoch` suffix:
   ```
   network_secret_v2 = HKDF(
       salt = "cleona-network-secret-v2",
       ikm  = ed25519_sign(maintainer_sk, "live/epoch=2"),
       info = "live",
       length = 16 bytes
   )
   ```

2. New Cleona builds (v3.0+) embed the `epoch=2` tag and can derive both secrets — old and new.

3. **Dual-secret window** (typically 30 days): the daemon accepts HMAC under either the old or the new secret. This gives users time to update their builds.

4. After the window ends, old secrets are removed from the code path. Builds with the old secret can no longer enter the mesh — they are silently isolated.

**Hard-block update mechanism** (§19.5.7) complements secret rotation: the `UpdateManifest` can set `minRequiredVersion`, and old versions are placed into `ReducedMode` (no send/receive of user messages).

**Implementation**:
- `network_secret` derivation in `lib/core/crypto/network_secret.dart`
- Embedded `epoch` tag in `assets/cleona_maintainer_public.pem` companion metadata
- The daemon holds both secrets in memory during the window: `currentSecret` + `previousSecret` (optional)
- HMAC verification tries both; if both fail, drop

**User observability**: no direct notifications. Old builds simply observe "no peers available" (the same behavior as an isolated network). The update-manifest hard-block (§19.5.7) shows an explicit prompt to update.

### 13.3 Service Layer Resilience

V3.0's new service-layer API (`sendToUser`, §15.3) has clearly defined failure modes at every layer. This section documents them as a binding resilience specification.

**Failure modes and reactions**:

| Layer | Failure | Reaction |
|---|---|---|
| Identity-Resolver Auth-Manifest lookup | no manifest found | sendToUser triggers offline fallback (§5.4-5.6) — no routing attempt |
| Identity-Resolver signature verify on manifest | signature invalid | discard manifest, try another replicator, last-resort offline fallback |
| Identity-Resolver liveness lookup | no liveness record for device | device is returned with `addresses=[]` — routing layer attempts via DV instead of direct |
| Routing-layer direct send fails | all direct addresses in backoff | cascade: relay route, defaultGateway, then fail |
| Routing-layer relay send fails | RELAY_ACK timeout | surgical route DOWN, try next route |
| Routing-layer all routes exhausted | including defaultGateway failure | sendToDevice returns false |
| sendToUser: all devices failed | no DELIVERY_RECEIPT from any device | offline fallback (§5.4 + §5.5 + §5.6) |
| KEM decap fails (receiver side) | wrong recipient or forged | silent drop, no DELIVERY_RECEIPT |
| User-signature verify fails (receiver side) | unknown sender or forgery | silent drop, KEX gate triggered (§8.2) |

**Important**: no layer escalates with "I don't know why, but retry". Every failure has a clear path. **No unbounded sender-side retry** — that was v2.2's MessageQueue anti-pattern.

**Idempotency**:
- DELIVERY_RECEIPT is idempotent — sending it multiple times causes no harm
- The receiver deduplicates on `messageId`
- If the sender is uncertain whether the receipt arrived, it can re-send without harm (the receiver sends another receipt, the sender marks as delivered)

**Resolver in-flight dedup** (§4.3): two concurrent `resolveUserToDevices(sameUserId)` calls wait on the result of the first — this prevents RPC spam during burst sends, e.g. when a user types several messages in rapid succession.

**Cache invalidation**:
- Resolver cache live for 1h
- Liveness TTL 15min/1h adaptive
- onAddressesChanged → debounced 5s → own-liveness republish (sender side)
- On receive failure against a cached address: cache invalidation for the affected DeviceID, new resolver lookup

**Service-layer test suite** (§21.4): explicit smoke tests for each failure mode. This makes resolver-miss, routing-cascade exhaustion, multi-device partial delivery, defaultGateway fallback, and offline fallback all individually verifiable.

---

## 14. Storage & Data Management

### 14.1 Storage Priorities

1. **Own chats, media, and metadata:** Priority 1 — never automatically deleted. This is the user's personal data and is sacrosanct.
2. **Relay fragments for other users:** Priority 2 — deleted after confirmed delivery or TTL expiry.
3. **DHT routing data:** Priority 3 — can be rebuilt from the network.

The on-device data store is the only place where Priority-1 data lives. Network-side persistence (S&F mailboxes (§5.5), erasure-coded fragments (§5.4), Identity-Resolution records (§14.2)) is auxiliary and bounded by storage caps; the local profile remains the single authoritative source.

### 14.2 Identity-Resolution Storage

Replicator nodes participating in the 2D-DHT Identity-Resolution path (§4.3) store two record types on disk:

| Record | Content | Source of Truth |
|--------|---------|-----------------|
| **Auth-Manifest** | UserID → device-list mapping, signed by user's Ed25519 + ML-DSA-65 hybrid identity key | Owning user |
| **Liveness-Record** | DeviceID → reachability hint (last-seen timestamp, optional address tuple), signed by the device's Device-Sig keypair (§3.5) | Owning device |

**Persistence layout:**

- File: `<profileDir>/identity_dht_storage.enc`
- Encryption: `FileEncryption` wrapper (XSalsa20-Poly1305, key derived as in §3.8) — the same on-disk encryption primitive as the SQLite store, but applied as a single self-contained envelope file.
- Sidecar recovery: writes are atomic via the standard `.tmp` → `rename` pattern with an `.old` backup retained until the next successful flush. On startup, if the canonical file is missing or corrupt, the loader falls back to `.old`; if both fail, the replicator starts cold and re-acquires records from neighbours.
- Storage caps per node: ~1000 Auth-Manifests + ~5000 Liveness-Records (~5 MB on disk, dominated by the ~3.3 KB ML-DSA signature on each Auth-Manifest; ~7-9 MB resident with Dart-Map overhead).
- Eviction: LRU by XOR distance to the local NodeID — records furthest from the replicator are evicted first, because closer replicators carry that key with higher redundancy.

**Separation from other stores:** The Identity-Resolution store is independent of the Mailbox-Store (§5.6) and the Erasure-Fragment-Store (§5.4). Identity records are small, signed and self-verifying, and therefore do not require erasure coding or read-receipts — anyone can verify an Auth-Manifest or Liveness-Record by checking the signature against the user's public identity key.

**Protocol details** for how these records are looked up, refreshed, and propagated live in §4.3.

### 14.3 Database Encryption

All SQLite databases are encrypted at rest. See §3.8 for the full encryption specification. Key points:

- Algorithm: XSalsa20-Poly1305 (libsodium)
- Key derivation: `SHA-256(ed25519_sk[0:32] + "cleona-db-key-v1")`
- File format: `cleona.db.enc` = `[24-byte nonce][ciphertext]`
- Runtime: SQLite operates on a decrypted temp file; periodic encrypted flushes every 60 s
- Migration: Existing unencrypted databases are automatically encrypted on first open with a key

### 14.4 Message Deletion Model

Messages can be deleted locally (removed from the user's own device only) or with a delete request that asks the conversation partner to delete the message as well. Delete requests are best-effort — the recipient's app will delete the message, but there is no guarantee (the recipient could be running a modified client).

### 14.5 Per-Chat Message Expiry

Each conversation (1:1, group, or channel) has an individually configurable auto-deletion timer. When enabled, messages are automatically and irrevocably deleted from all participants' devices after the timer expires.

Critical implementation detail: The expiry timer starts after the message has been **READ** by the recipient, not after sending. This ensures messages are not deleted before being seen (important for offline users who might not receive a message for hours or days).

In 1:1 chats, either participant can propose a change to the expiry setting; the other must explicitly confirm. In groups and channels, the owner sets the expiry for all members. Changes apply only to future messages — existing messages keep their original expiry.

### 14.6 Per-Chat Message Editing

Each conversation has a configurable editing window that determines how long after sending a message can be edited by its author.

Only the original author can edit their messages. Edited messages display an "(edited)" label with the timestamp of the last edit. Edit history is **NOT** stored — only the current version exists (data minimization).

Enforcement is dual-sided: the sender's app removes the edit button after the window expires (client-side), AND recipients reject edit messages that arrive after the window has passed based on the original message timestamp (server-side enforcement, even though there is no server).

### 14.7 Per-Chat Configuration Protocol

Each conversation has configurable policies beyond expiry and editing: download permissions (whether received files can be saved), forwarding permissions (whether messages can be forwarded to other conversations), and the download directory.

#### 14.7.1 Configuration Change Flow

**DM conversations (mutual consent):** When a user changes a chat configuration setting, a `CHAT_CONFIG_UPDATE` ApplicationFrame (type 100) is sent to the partner containing the proposed changes. The partner's app displays a confirmation dialog showing the proposed changes. The partner can accept or reject. Their response is sent as a `CHAT_CONFIG_RESPONSE` ApplicationFrame (type 101) with an `accepted` flag and the original changes. If accepted, both sides apply the new configuration. If rejected, the proposer is notified.

**Groups and channels (owner authority):** The owner sends a `CHAT_CONFIG_UPDATE` directly to all members. The configuration takes effect immediately — no confirmation step. Group/channel configuration can be changed by the **Owner or Admin**. This is enforced both in `requestChatConfigChange()` (sender side) and `_onChatConfigUpdate()` (receiver side).

**Out-of-order delivery handling:** Since config updates and group invites are sent as separate fire-and-forget messages, a `CHAT_CONFIG_UPDATE` may arrive before the `GROUP_INVITE` that establishes the group on the receiver. To handle this, config updates for unknown groups are buffered in `_pendingGroupConfigs`. When the `GROUP_INVITE` subsequently arrives, buffered configs are applied if the sender has owner/admin role. This eliminates race conditions in asynchronous message delivery.

**Key resolution for fan-out:** When broadcasting to group/channel members, `_resolveMemberKeys()` resolves encryption keys by preferring the contact's keys (most up-to-date from key exchange) with fallback to the `GroupMemberInfo` keys (from the original `GROUP_INVITE` protobuf). This prevents delivery failures when member keys in the group record are stale or empty.

#### 14.7.2 Configurable Settings

| Setting | Type | Default | Scope |
|---------|------|---------|-------|
| `allow_downloads` | boolean | true | Whether received files can be saved to disk |
| `allow_forwarding` | boolean | true | Whether messages can be forwarded |
| `expiry_duration_ms` | int? | null (no expiry) | Message auto-delete after read |
| `edit_window_ms` | int? | null (no edits) | Time window for message editing |
| `read_receipts_enabled` | boolean | true | Whether read receipts are sent |
| `typing_indicators_enabled` | boolean | true | Whether typing indicators are sent |

#### 14.7.3 Download Directory

Each identity profile has a configurable download directory for saved files:

- **Desktop (Linux/Windows/macOS):** Defaults to the OS standard Downloads folder (`~/Downloads`).
- **Mobile (Android/iOS):** Defaults to an app-internal downloads directory. Users can optionally change to an external directory, which triggers the appropriate storage permission request at that time (not at installation).

The download directory is stored per-identity in `chat_policies.json` and can be changed in the chat settings screen.

**Self-copy protection:** When the source file already resides in the download directory, `File.copySync()` to the same path would truncate the file to 0 bytes. The save function uses `p.canonicalize()` to compare source and target paths and skips the copy if they are identical, showing an "already in download folder" notification instead.

### 14.8 Media Auto-Archive

Automatic offloading of media (images, videos, files) to a local network share. When the device connects to a configured home WLAN and the share is reachable, media files are copied to the share. After a configurable retention period, originals are deleted from the device — **never without confirmed archival**.

**Scope:** DMs and groups only. Channels are excluded.

#### 14.8.1 Tiered On-Device Storage

Instead of showing blank placeholders for archived media, Cleona retains progressively smaller representations:

| Tier | Period | On Device | On Share |
|------|--------|-----------|----------|
| 1 | 0–30 days | Original | — (not yet archived) |
| 2 | 30–90 days | Thumbnail (~20–50 KB) | Original |
| 3 | 90–365 days | Mini-thumbnail (~2–5 KB, 64 px) | Original |
| 4 | > 1 year | Metadata link only (date, size, type icon) | Original |

All tier boundaries are user-configurable. Pinned media ignores tiers entirely and remains as original on the device.

#### 14.8.2 Pin / Keep

Media can be marked as "keep" at three levels:

- **Per message:** Star/pin icon in the 3-dot menu of any media message.
- **Per chat:** "Never delete media in this chat" in chat settings.
- **Global:** "Never auto-delete" in archive settings.

Pinned media is still archived to the share (backup!), but **never deleted from the device**.

#### 14.8.3 Network Detection

Two mechanisms combined:

1. **SSID-based:** User configures one or more WLAN names → fast home-network check.
2. **Share reachability:** Periodic probe whether the share is actually accessible → robust (works via VPN too).

Archival starts only when both conditions are met (or share-reachability alone when no WLAN is configured, e.g., wired desktop).

#### 14.8.4 Supported Protocols

| Protocol | Description | Priority |
|----------|-------------|----------|
| **SMB/CIFS** | Universal NAS standard (Synology, QNAP, Fritz!NAS) | Required |
| **SFTP** | SSH-based, secure, good mobile support | Required |
| **FTPS** | FTP over TLS, for older NAS systems | Nice to have |
| **HTTP/HTTPS** | WebDAV-based, for self-hosted servers | Nice to have |

No plain FTP (insecure). No NFS (impractical on mobile).

#### 14.8.5 Directory Structure on Share

```
<Share-Root>/Cleona/<Identity>/<Chat>/YYYY-MM/<filename>_<content-hash>.ext
```

Content-hash suffix enables automatic deduplication when multiple devices/identities archive the same chat.

#### 14.8.6 Safety Rules

1. **Never delete without confirmed archival.** If the share is unreachable and the retention period expires, the original stays on the device.
2. **Reminder notification:** "You have X MB of archivable media. Connect to your home WLAN to free up storage."
3. **No encryption on share.** Media is stored decrypted so it can be viewed directly on PC/NAS. The share resides on the user's local home network.
4. **Initial sync:** When first activated, a background sync processes existing media with a progress bar. Ideally runs overnight while charging.

#### 14.8.7 Storage Budget

In addition to time-based tiers, users can set a maximum on-device media budget (e.g., "keep max 2 GB"). When the limit is reached, the oldest unpinned media is archived first — regardless of tier configuration.

Platform defaults span the 5-tier budget range from 100 MB (most constrained mobile devices) to 2 GB (desktop), reflecting per-platform storage realities. The cap is user-overridable in archive settings.

#### 14.8.8 Batch Retrieval

Instead of tapping each placeholder individually:

- "Retrieve all media from [date range]"
- "Retrieve all media from this chat"
- Requires active share connection; progress bar during download.

#### 14.8.9 Configuration

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

### 14.9 Voice Transcription

On-device speech-to-text for voice messages using whisper.cpp (OpenAI Whisper as a C library). The transcript is displayed as text below the voice message. After a configurable retention period, the audio is deleted and only the transcribed text remains permanently.

This feature works independently of the Media Archive — both can be enabled separately.

#### 14.9.1 Voice Lifecycle

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

#### 14.9.2 Transcription Engine

- **whisper.cpp** — runs fully on-device, no cloud dependency
- Model: "tiny" or "base" (~40–75 MB), sufficient quality for voice messages
- Supported languages: `auto` (default — Whisper auto-detects from ~99 languages), plus explicit selection from DE, EN, ES, HU, SV in the Settings UI (`voice_transcription_config.dart`). The explicit selection list is narrower than Cleona's 33 UI locales — a deliberate config choice, not a Whisper limitation.
- Automatic language detection or manual selection
- **Source-Side Transcription:** Sender transcribes before sending; the transcript is embedded in the `VoicePayload` protobuf carried by the audio ApplicationFrame. Receivers use the sender's transcript directly. Fallback: receiver transcribes locally if no transcript was provided by the sender.

##### 14.9.2.1 Native Dependencies (Runtime)

Voice transcription requires the following native libraries and tools at runtime. If any dependency is missing, transcription is silently disabled — voice messages still work, but without text.

**Linux (Desktop / Daemon):**

| Dependency | Purpose | Install | Package (deb) | Package (rpm) |
|------------|---------|---------|---------------|---------------|
| `libwhisper.so` | Speech-to-text engine | Build from source (whisper.cpp) | — | — |
| `libggml.so`, `libggml-base.so`, `libggml-cpu.so` | Tensor computation (whisper.cpp transitive deps) | Built alongside whisper.cpp | — | — |
| `libwhisper_wrapper.so` | Dart FFI bridge (struct-by-value ABI) | Built from `scripts/build-whisper-wrapper.sh` | — | — |
| `ffmpeg` | Audio format conversion (AAC/OGG/MP3 → WAV 16 kHz PCM) | `sudo apt install ffmpeg` | `ffmpeg` | `ffmpeg` |
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

On Android, `libwhisper.so` and `libggml*.so` must be cross-compiled for arm64-v8a with the Android NDK and bundled in `android/app/src/main/jniLibs/arm64-v8a/` (same as libsodium/liboqs/libzstd). **Critical:** GGML must be built with `-DGGML_OPENMP=OFF` — the NDK does not include `libomp.so`, and OpenMP is unnecessary since NEON SIMD provides the real speedup on mobile (whisper uses only 1–4 threads). Audio format conversion (AAC → WAV 16 kHz PCM) is handled by Android's `MediaCodec` via a `MethodChannel` (`chat.cleona/audio`), not ffmpeg. The GGML model is downloaded on first use via Settings → Transcription (Hugging Face CDN, ~75 MB for `ggml-base`).

**Linux Packaging (deb/rpm):**

For distribution as `.deb` or `.rpm` packages, the following must be declared:

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

The whisper.cpp and GGML libraries are not available in standard distro repositories and must be bundled. The model file (~75 MB for `base`) can either be included in the package or downloaded on first launch via a post-install script, depending on package size constraints.

#### 14.9.3 Configuration

```
Voice Message Settings:
├── Auto-transcription: [ON/OFF]
├── Keep audio for: [7/14/30/60/90 days] (default: 30)
├── "Never delete": [per message (pin) | per chat | global]
└── Transcription language: [Auto | DE | EN | ES | HU | SV]
```

#### 14.9.4 Scope

DMs and groups only (same as Media Archive). Channels are excluded.

---

## 15. Application Architecture

The Cleona codebase is a single Dart/Flutter codebase running on multiple platforms. Platform specifics (lifecycle, Tray, notifications) are UI- and lifecycle-level adaptations, not architectural variations.

### 15.1 Background Service + GUI Separation

V3.0 separates the **Daemon** (background service holding all network state) from the **GUI** (Flutter UI without state). This is the standard V3.0 topology on Linux and Windows. On Android both run in-process (Foreground Service plus Activity).

**Daemon responsibilities**:
- Network stack (UDP/TLS sockets, routing table, DHT, identity resolution)
- Crypto (KEM, signatures, HMAC, key storage)
- Persistent database (conversations, contacts, calendar, polls)
- IPC server (Unix socket on Linux, TCP + auth token on Windows)

**GUI responsibilities**:
- Flutter rendering (Skia)
- IPC client (connects to the daemon, calls RPC methods)
- User interaction (keyboard, mouse, touch)
- Display of push notifications (triggered by daemon events)

**Lifecycle model**:
- **Daemon**: **machine-global single-instance** (V3.1.72) — one Cleona daemon per machine per OS-user, **regardless of `--base-dir`/`--profile`**. Runs continuously in the background (Linux: systemd user service or manual start; Windows: service or schtasks; Android: Foreground Service).
- **GUI**: can be started or stopped without affecting the daemon. The daemon does not notice directly — only the IPC connection is closed.
- **Single-Instance Guard (machine-global, V3.1.72)**: on startup the daemon acquires a **machine-global** lock at a **deterministic, per-user path that is a *sibling* of the profile dir** — `$HOME/.cleona-daemon.lock` (`AppPaths.home`, i.e. `%USERPROFILE%` on Windows), flock+PID. The path must be env-independent (NOT `$XDG_RUNTIME_DIR`, which is unset under some launch contexts — start.sh vs systemd vs ssh — and would let two launches pick different paths and defeat the guard). If a live daemon already holds it, the new process refuses to start. **Why this is the authoritative guard:** Guard 0 (PID file) and Guard 1 (per-`--base-dir` `cleona.lock`) live *inside* the profile dir and are **inode-based**; an E2E/profile **wipe of `~/.cleona` deletes `cleona.lock`+`cleona.pid`**, after which a second daemon creates a *new* `cleona.lock` inode and locks it while the first still holds the old (unlinked) inode → **both run** (the V3.1.72 Node2 split-brain; inbound packets + GUI/IPC state diverged). The machine-global lock sits **outside** the profile dir, so it **survives the wipe** and refuses the duplicate. Guards 0/1 + `cleona.sock`/port-probe are retained for the GUI↔daemon handshake and PID bookkeeping, **not** as the duplicate-detection authority.
- **Intentional multi-instance (lab/test only)**: the `--ignore-single-instance` flag skips the machine-global guard. It is **honored only in beta builds** (`NetworkChannel.beta`); in live/release it is ignored and the guard is always enforced. `jury-swarm.sh` passes it to run N daemons on one host (distinct `--base-dir` + `--port`) for moderation/load testing. Any harness using the bypass **must kill all spawned instances on teardown and restart a normal single-instance daemon**.
- **GUI dies with the Daemon**: if the daemon crashes, the GUI closes immediately (no zombie mode). This prevents the user from mistakenly believing the app is "live" while the network is down.

**Six-layer architecture** (matched against the wire layers from §2):

```
┌─────────────────────────────────────────────┐
│ Layer 6: Presentation (Flutter UI)           │ in GUI process
├─────────────────────────────────────────────┤
│ Layer 5: IPC (RPC calls over Socket/TCP)     │ bridge GUI ↔ Daemon
├─────────────────────────────────────────────┤  ← Process boundary
│ Layer 4: Application Service (CleonaService) │ in Daemon
│   • Per-Identity logic                       │
│   • sendToUser, Calendar, Polls, Channels    │
├─────────────────────────────────────────────┤
│ Layer 3: Network Node (CleonaNode)           │
│   • sendToDevice, RoutingTable, DHT          │
├─────────────────────────────────────────────┤
│ Layer 2: Transport (UDP+TLS sockets)         │
├─────────────────────────────────────────────┤
│ Layer 1: OS network stack                    │
└─────────────────────────────────────────────┘
```

Mapping to wire layers:
- Layer 4 (Application Service) ↔ inner frame `ApplicationFrame` (§2.3)
- Layer 3 (Network Node) ↔ outer frame `NetworkPacket` (§2.2)

### 15.2 Platform-Specific Behavior

**Linux Desktop**:
- Daemon: `cleona-daemon` (standalone binary, dart compile exe)
- GUI: `cleona` (Flutter Linux bundle)
- IPC: Unix socket `~/.cleona/cleona.sock`
- Tray: native dart:ffi → GTK3 + libappindicator3 (NOT the system_tray plugin — proven incompatible with modern Wayland sessions)
- Notifications: `notify-send` (libnotify) or D-Bus directly
- Audio: PipeWire (`pw-play`) preferred, PulseAudio (`paplay`) fallback

**Windows Desktop**:
- Daemon: `cleona-daemon.exe`
- GUI: `cleona.exe` (Flutter Windows bundle)
- IPC: TCP 127.0.0.1 + auth token (the Unix-socket equivalent on Win32 is not reliable enough for Cleona's use case)
- Tray: native Win32 API via dart:ffi
- Notifications: Windows Toast API
- Audio: WASAPI via libcleona_audio (miniaudio)
- Single-Instance: machine-global flock+PID at `%USERPROFILE%\.cleona-daemon.lock` (cross-platform `RandomAccessFile.lock` → `LockFileEx` on Windows, `flock` on Linux at `$HOME/.cleona-daemon.lock`) — deterministic, profile-independent, sibling of the profile dir (§15.1)

**Android**:
- In-process: no separate daemon, Foreground Service with Activity lifecycle
- Multi-Identity dispatch mirrors the desktop daemon: `onApplicationFramePayload` implements the §2.4 step [9] KEM-Try-Loop (recency-ordered), `onInfrastructureFramePayload` implements service-routed InfraFrame dispatch (CR, Restore, Fragment-Store/Retrieve, etc.) — both wired in the GUI entry point (`main.dart`) rather than a separate daemon process
- Foreground Service (canonical for background delivery, see §12.4 ADR Push Wake-Up Rejected): persistent notification, runs even when the Activity is closed
- IPC: not required (in-process)
- Camera: CameraX
- Notifications: Android NotificationManager
- Audio: libcleona_audio (miniaudio with OpenSL ES backend)
- Native libs: jniLibs for arm64-v8a + x86_64 (cross-compiled via `scripts/build-android-libs.sh`)

**iOS**:
- In-process, analogous to Android
- Background modes: `audio` for live calls, `fetch` for periodic updates, `processing` for DHT maintenance
- Native libs: all 7 libraries (libsodium, liboqs, libzstd, liberasurecode, libopus, whisper.cpp, libcleona_audio) built as static `.a` archives via `scripts/build-ios-libs.sh`, packaged as XCFrameworks, linked via CleonaNative CocoaPods podspec with `-ObjC -all_load`. Dart FFI loads symbols via `DynamicLibrary.process()`.
- Build: GitHub Actions `macos-14` runner → `flutter build ipa` → IPA signed with Apple Development certificate
- Deployment Target: iOS 15.5 (required by `mobile_scanner` plugin)
- Permissions (Info.plist): microphone, camera, photo library, NFC tag reading, local network discovery, background modes
- Device install: `ideviceinstaller -i <ipa>` via USB (Development provisioning profile with registered UDID)

**macOS**:
- Daemon + GUI analogous to Linux
- IPC via Unix socket
- Native libs: `.dylib` in `Cleona.app/Contents/Frameworks/` (built via `scripts/build-macos-libs.sh`, install_name rewritten to `@rpath`)
- Build: GitHub Actions `macos-14` runner → `flutter build macos --release` + `dart compile exe service_daemon.dart` → app bundle assembly → DMG → notarization via App Store Connect API
- Tray: NSStatusBar via FFI (planned)

### 15.3 Service Layer API (sendToUser/sendToDevice)

V3.0's **canonical send API** consists of two clearly separated operations. They replace the v2.2 `node.sendEnvelope(envelope, recipientNodeId)` with its overloaded identifier parameter.

**API contract**:

```dart
// In CleonaService (Layer 4 — Application Service):
abstract class ICleonaService {
  /// Send an Application-Frame to a specific User. Resolver identifies all
  /// devices hosting this user, fan-out happens automatically.
  ///
  /// Returns true if at least one device acknowledged delivery.
  /// Returns false if no devices reachable AND offline-fallback was triggered
  /// (S&F + Mailbox).
  Future<bool> sendToUser({
    required Uint8List userId,
    required MessageType type,
    required Uint8List payload,
    bool requireOnline = false,  // if true: skip offline-fallback, return false directly
  });
}

// In CleonaNode (Layer 3 — Network Node):
class CleonaNode {
  /// Pure routing operation. Caller has already determined the deviceId
  /// (typically via IdentityResolver or as part of relay-forwarding).
  ///
  /// Cascade: cheapest-route → next-cheaper → defaultGateway.
  /// Returns true on DELIVERY_RECEIPT, false on cascade-exhausted.
  Future<bool> sendToDevice(NetworkPacket packet, Uint8List deviceId);

  /// Resolve a user to their authorized devices (Identity-Resolution-Layer).
  /// Returns empty list if user has no published Auth-Manifest in DHT.
  Future<List<ResolvedDevice>> resolveUserToDevices(Uint8List userId);
}
```

**Internal flow** in `sendToUser`:

```dart
Future<bool> sendToUser({...}) async {
  // 1. Build ApplicationFrame
  final frame = _buildApplicationFrame(userId, type, payload);
  _signApplicationFrame(frame);  // User-Sig hybrid

  // 2. Identity-Resolution
  final devices = await node.resolveUserToDevices(userId);

  if (devices.isEmpty) {
    // No published Auth-Manifest — go straight to offline-fallback
    if (requireOnline) return false;
    return _offlineFallback(frame, userId);
  }

  // 3. Per-Device Routing fan-out
  var anyDelivered = false;
  for (final device in devices) {
    final packet = _wrapInOuter(frame, device.deviceId);
    final success = await node.sendToDevice(packet, device.deviceId);
    if (success) anyDelivered = true;
  }

  // 4. Offline-Fallback if NO device acknowledged
  if (!anyDelivered && !requireOnline) {
    await _offlineFallback(frame, userId);
  }

  return anyDelivered;
}

Future<bool> _offlineFallback(ApplicationFrame frame, Uint8List userId) async {
  // Erasure-coded across K=10 closest DHT replicators
  await erasureBackup.store(frame, userId);

  // S&F copy on 3 mutual peers
  await sfStore.distribute(frame, userId);

  // Mailbox notification
  await mailbox.notify(userId, frame.messageId);

  return false;  // technically not delivered live
}
```

**API callers in v3.0**:

| Caller | Operation |
|---|---|
| GUI (via IPC) → CleonaService.sendToUser | Text, media, reactions, edit, delete, read receipt |
| Calendar Manager | CALENDAR_INVITE, CALENDAR_RSVP, FREE_BUSY_REQUEST |
| Polls Manager | POLL_CREATE, POLL_VOTE, POLL_UPDATE |
| Contact Manager | CONTACT_REQUEST, CONTACT_REQUEST_RESPONSE |
| Channel Manager | Channel posts (broadcast → fan-out via sendToUser per subscriber) |
| Group Manager | Group messages (pairwise via sendToUser per member) |
| Restore Broadcast | Restore message to all contacts (sendToUser per contact) |
| Twin-Sync (§7.2) | TwinSync updates to all of the user's own devices except the current one |

**Who calls `sendToDevice` directly** (without going through sendToUser):
- Routing-internal: relay forwarding (RELAY_FORWARD inner already carries the final recipient as a deviceId)
- DHT RPC: PEER_LIST_PUSH, FRAGMENT_*, IDENTITY_*_PUBLISH/RETRIEVE — all addressed to replicator DeviceIDs
- Hole-punch coordination: HOLE_PUNCH_NOTIFY, HOLE_PUNCH_PING, etc.
- Live call frames: CALL_AUDIO/VIDEO to a specific CallSession DeviceID
- Routing probes: REACHABILITY_QUERY/RESPONSE, ROUTE_UPDATE, RELAY_ACK

These are **structurally** DeviceID-addressed — no UserID resolver is required or meaningful.

**What no longer exists**:
- `node.sendEnvelope(envelope, recipientNodeId)` — removed
- `MessageQueue` — removed (S&F + mailbox pull take over)
- Default-gateway resolution fallback in the **Identity-Resolution layer** — removed; the default gateway now lives in the **routing layer** as a last resort within `sendToDevice`

### 15.4 UI Architecture & Navigation

Flutter UI with ThemeExtensions, 5 token primitives, 6 component classes, 10 Skins. The full UI spec is in `docs/UI.md` (external, not duplicated here).

**Top-level navigation**:
- Home screen with 3 tabs (Recent / Contacts / Channels)
- AppBar with 5 right-aligned actions (identity switch, calendar, network stats, settings, logout)
- Modal routes for chat, settings, calendar, etc.

**Identity switch**: immediate switch in the active daemon state (all identities run in parallel within the daemon; only the UI display changes).

**Conversation sorting**: unread first, then by descending timestamp.

**Inbox tab** (contact requests and invites): pending CR + GROUP_INVITE + CHANNEL_INVITE listed. Accept/Reject per item.

**SafeArea requirement** on Android (Edge-to-Edge mode):
- `main.dart` sets `SystemUiMode.edgeToEdge`
- Every Scaffold body with its own scroll/content MUST wrap with `SafeArea(top: false, child: ...)`
- `top: false` because the AppBar is already top-safe
- A missing SafeArea causes the Android system bar to obscure the last entry

### 15.5 Notifications, Sounds, Vibration

**Sound events**:
- New message (default tone)
- Contact request
- Call ringtone (6 selectable tones)
- Calendar reminder
- Channel post (optional, per-channel setting)

**Ringtone selection**: 6 predefined tones, plus a user-supplied custom file (stored locally).

**Vibration**: configurable per notification type (pattern + duration).

**Notification settings**:
- Per conversation: mute/unmute, custom sound
- Per identity: master mute, quiet-hours schedule
- Per platform: respect system notifications (Do Not Disturb)

**Implementation**:
- Linux: `notify-send` or D-Bus `org.freedesktop.Notifications`
- Windows: Toast API
- Android: NotificationManager
- iOS: UNUserNotificationCenter

**Suppression layers**:
- Layer 1: per-conversation mute
- Layer 2: quiet hours
- Layer 3: system DND (Do Not Disturb)
- Layer 4: active call (notifications are held back during a call)

### 15.6 Tray (Linux/Windows)

Native system Tray icon — shows the 5-tier connection status (strong/good/medium/weak/offline) plus a 30s pulse animation.

**Linux**: GTK3 + libappindicator3 via dart:ffi.
**Windows**: Win32 API directly via dart:ffi (Shell_NotifyIcon).

**Tray menu**:
- Show/Hide window
- Identity switch (quick)
- Mute notifications (toggle)
- Quit Cleona (= Daemon + GUI down)

**Pulse animation**: 30s freeze-hold to avoid software GPU drainage (no perpetual pulsing — only on state changes and for a short duration).

### 15.7 Clipboard Integration

**Linux clipboard** (X11 + Wayland): clipboard helper via dart:ffi to `wl-copy/wl-paste` (Wayland) or `xclip` (X11).

**Images via clipboard**:
- A received image in a conversation → "Copy" action stores it in the clipboard as image/png
- Pasting into other apps (browser, image editor)

**Cross-platform**: standard Flutter `Clipboard.setData` for text. Images require platform-specific code.

---
## 16. Permissions & Privacy

Cleona follows a strict minimum-permissions approach. No permission is requested at install time (except network access). Every other permission is requested at the exact moment the feature is first used, with a clear explanation of why it is needed. If the user denies a permission, the feature is gracefully disabled — the app never crashes or nags repeatedly.

### 16.1 Design Principles

1. **Just-in-time requests:** Permissions are requested when the user first triggers a feature, not at launch. This gives the user context for why the permission is needed.
2. **Graceful degradation:** If a permission is denied, the feature is silently disabled. No repeated prompts, no error dialogs, no loss of core functionality.
3. **No surveillance permissions:** Contacts, location, phone state, and call logs are never requested under any circumstances. Identity is purely cryptographic (§3.1).
4. **Platform-native channels:** Camera and audio permissions use platform-specific MethodChannels (not generic Flutter plugins) for precise control over the permission lifecycle.

### 16.2 Android Permission Model

**Declared permissions** (AndroidManifest.xml):

| Permission | Type | When Requested | Purpose |
|-----------|------|----------------|---------|
| `INTERNET` | Normal (auto-granted) | Always | UDP/TLS P2P communication |
| `ACCESS_NETWORK_STATE` | Normal (auto-granted) | Always | Network change detection |
| `FOREGROUND_SERVICE` | Normal (auto-granted) | Always | Keep daemon alive for message delivery |
| `FOREGROUND_SERVICE_DATA_SYNC` | Normal (auto-granted) | Always | Foreground service type for Android 14+ |
| `FOREGROUND_SERVICE_MICROPHONE` | Normal (auto-granted) | Always | Allows promoting the foreground service to MICROPHONE type during voice/video calls (see §10.4) |
| `VIBRATE` | Normal (auto-granted) | Always | Message/call vibration alerts |
| `CAMERA` | Dangerous (runtime) | First photo/video capture or QR scan | Media capture, video calls, contact verification |
| `RECORD_AUDIO` | Dangerous (runtime) | First voice message or call | Voice recording, audio calls |
| `POST_NOTIFICATIONS` | Dangerous (runtime, Android 13+) | First incoming message | Message and call notifications |
| `NFC` | Normal (auto-granted) | Always (hardware feature optional) | Contact pairing, peer list merge |

**Hardware feature:** `android.hardware.nfc` is declared as `required="false"` — Cleona installs and runs on devices without NFC. The NFC contact exchange button is hidden on devices without NFC hardware.

**Foreground service (canonical background-delivery path):** `CleonaForegroundService` boots as type `dataSync` and keeps the UDP socket alive for incoming message and call delivery. This is the **only** mechanism Cleona uses for background delivery on Android — push wake-up via FCM, UnifiedPush, WebPush or per-peer rotation has been architecturally evaluated and rejected (see §12.4 / ADR "Push Wake-Up Rejected"). During an active voice/video call the service is runtime-promoted to `dataSync|microphone` via the 3-arg `startForeground()` overload, after `RECORD_AUDIO` has been granted; it is demoted back to `dataSync` when the call ends. The manifest declares `foregroundServiceType="dataSync|microphone"` so the runtime promotion is permitted; calling `startForeground()` with the 2-arg overload at boot would implicitly inherit the `microphone` type and crash on freshly installed apps that have never granted `RECORD_AUDIO`. The persistent notification shows live connection status, e.g. "Connected — X peers", "Mobile — X peers", "Searching for peers…", or "Offline — no network" (actual strings come from i18n in 33 languages — see §17). Updated dynamically via MethodChannel (`updateServiceNotification`) on every state change, with dedup to avoid redundant updates. Channel importance: `IMPORTANCE_LOW` (no sound, no vibration, no badge).

### 16.3 iOS Permission Model

| Permission Key | When Requested | Usage Description |
|---------------|----------------|-------------------|
| `NSCameraUsageDescription` | First photo/video/QR | "Cleona needs camera access for photos, videos, and QR contact scanning" |
| `NSMicrophoneUsageDescription` | First voice message/call | "Cleona needs microphone access for voice messages and calls" |
| `NSPhotoLibraryUsageDescription` | First gallery pick | "Cleona needs photo library access to send images and videos" |

### 16.4 Desktop Permissions (Linux / Windows)

Desktop platforms do not use a runtime permission model. Camera and microphone access is controlled by PipeWire/PulseAudio (Linux) or Windows Audio/Video device APIs (Windows). No special permission dialogs are shown.

**External tool dependencies (Linux):**
- `wl-clipboard` / `xclip`: Required for binary clipboard paste (screenshots, images). Without them, only text paste works.
- `ffmpeg`: Required for voice transcription audio format conversion. Without it, voice messages play but show no transcription.

### 16.5 Permissions NOT Required

Cleona **never** requests:

| Permission | Why Not |
|-----------|---------|
| Contacts / Address Book | Contacts are added manually via QR, NFC, ContactSeed URI, or Mesh Discovery. No phone number or email needed. |
| Location / GPS | Never accessed. No location-based features. No geofencing. |
| Phone State / Call Logs | Cleona calls are data-only over UDP. No interaction with the cellular network. |
| Background Location | Not needed — network change detection uses `connectivity_plus`, not GPS. |
| SMS / MMS | No SMS verification. Identity is cryptographic. |
| Bluetooth | Removed from architecture (BLE presence leakage, Eclipse attack risk). Replaced by NFC. |

### 16.6 Privacy Architecture

Beyond permissions, Cleona's architecture enforces privacy at the protocol level:

- **No metadata on the wire:** Relay nodes see only encrypted fragments with mailbox IDs (§5.6.1). No sender identity, no timestamp, no message type.
- **No analytics:** No telemetry, no crash reporting, no usage tracking. Zero outbound connections except P2P communication.
- **No cloud dependencies:** No Google Play Services required. No Apple iCloud integration. (Push wake-up was considered and rejected; see §12.4.)
- **KEX Gate (§8.2):** Messages from unknown senders are silently dropped at the protocol level. No notification, no "message request" UI — invisible to the recipient.
- **Link previews:** Fetched by the sender, embedded encrypted in the message. The recipient makes zero network requests. <!-- TODO-XREF: Link-Preview detail section not yet assigned in v3.0 — v2.2 §14.8 had no clear successor in V3_MIGRATION_MAP.md. Candidate locations: §5 Message Delivery or §8 Identity-Authorization. -->

---

## 17. Internationalization

Cleona supports 33 languages including 3 RTL scripts. The localization system is built entirely in Dart — no platform-specific resource files (no Android `strings.xml`, no iOS `Localizable.strings`). All translations live in a single compile-time constant map, enabling instant language switching without app restart.

### 17.1 Design Principles

1. **Single source of truth:** All translations are in `lib/core/i18n/translations.dart` as a compile-time `const Map<String, Map<String, String>>`. No external files, no asset loading, no build step.
2. **Instant switching:** Language changes take effect immediately via `ChangeNotifier`. No restart, no page reload. The user sees the entire UI update in real time.
3. **System language detection:** On first launch, Cleona reads `Platform.localeName` and auto-selects the matching language. English is the fallback if the system locale is not supported.
4. **RTL-first:** RTL is not an afterthought. The entire widget tree is wrapped in a `Directionality` widget that switches between `TextDirection.ltr` and `TextDirection.rtl` based on the active locale.
5. **Full coverage policy:** Every translation key must carry a real string in all 33 supported locales. English-fallback at key-addition time ("`ar`, `he`, `fa` will pick up `en` via the runtime fallback chain") is not permitted. Any remaining gap is treated as a bug. The enforcement is `scripts/check_i18n_complete.dart`, run as a pre-commit / pre-push hook and a CI gate on every change that touches `translations.dart`. The runtime fallback chain in `AppLocale.get` remains as a defence-in-depth safety net against emergency misses (missing key after a refactor, new key referenced before translation), but it is not the expected path.

### 17.2 Supported Languages (33)

| Group | Languages |
|-------|-----------|
| Original 5 | German (de), English (en), Spanish (es), Hungarian (hu), Swedish (sv) |
| RTL (3) | Arabic (ar), Hebrew (he), Farsi/Persian (fa) |
| Western Europe (7) | French (fr), Italian (it), Portuguese (pt), Dutch (nl), Danish (da), Finnish (fi), Norwegian (no) |
| Eastern Europe (8) | Polish (pl), Romanian (ro), Czech (cs), Slovak (sk), Croatian (hr), Bulgarian (bg), Greek (el), Turkish (tr) |
| Slavic (2) | Ukrainian (uk), Russian (ru) |
| East Asia (3) | Chinese Simplified (zh), Japanese (ja), Korean (ko) |
| South/Southeast Asia (5) | Hindi (hi), Thai (th), Vietnamese (vi), Indonesian (id), Malay (ms) |

### 17.3 Implementation

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

**Fallback chain (defence-in-depth, not the expected path):** Current locale → `en` → `de` → key itself (raw key name as last resort). Per §17.1-5, every new key is expected to have a real translation in all 33 locales — `scripts/check_i18n_complete.dart` enforces this in CI. The runtime fallback chain exists only to avoid a crash in the edge case where coverage check was bypassed or a new key was referenced before being translated.

**Persistence:** Selected locale is stored in `SharedPreferences` with key `'cleona_locale'`. On app start, the saved locale is loaded; if none saved, system language detection runs.

### 17.4 RTL Support

Arabic, Hebrew, and Farsi use Right-to-Left layout. The implementation uses Flutter's built-in RTL infrastructure:

- `AppLocale.isRtl` returns `true` for `ar`, `he`, `fa`
- `AppLocale.textDirection` returns the appropriate `TextDirection`
- A `Directionality` widget wraps the entire `MaterialApp` in the widget tree
- Flutter automatically mirrors: navigation arrows, padding/margins, text alignment, list item layouts, message bubble alignment (sent = left in RTL, received = right)
- The language selector in the AppBar uses flag emojis for universal recognition regardless of reading direction

### 17.5 Language in Protocol Context

Language codes appear in three protocol contexts:

1. **Channel language** (see Channels section §9): Set at channel creation, stored in DHT index. Used for jury language selection in moderation.
2. **Voice transcription language** (see Archive / Voice Transcription section §14.9): Configurable per identity. Passed to whisper.cpp for speech recognition. Default: auto-detect.
3. **ContactSeed URI**: No language tag — contact exchange is language-neutral.

---

## 18. Network Statistics Dashboard

Cleona provides a dedicated, scrollable statistics page accessible from the sidebar or settings. This dashboard embodies Cleona's transparency philosophy by giving users real-time insight into the P2P network's health and their own contribution. The dashboard auto-refreshes every 5 seconds. All UI strings are fully localized (33 languages — see §17).

> **Layer note (v3.0):** The Network Statistics subsystem operates at the **routing layer** (DeviceID), **not** at the identity layer (UserID). Every connection-, latency-, NAT- and routing-table metric is intrinsically a per-Device measurement: a single device can host multiple user identities, and a single user identity can be reachable on multiple devices. The dashboard makes this distinction explicit wherever per-peer detail is shown — see §2 for the layered-frame model and §3.1 / §3.5 for the UserID/DeviceID split.

### 18.1 Design Principles

1. **Full transparency:** Users see exactly what their node is doing — how much data it stores for others, how many peers it knows, what its latency looks like. No hidden activity.
2. **Health at a glance:** A single color-coded badge (green/yellow/red) summarizes network health without requiring technical knowledge.
3. **Privacy-preserving metrics:** All statistics are computed locally from the node's own observations. Metrics are stored locally only — they are **never** aggregated across the network, never shared with other nodes, never sent to an external service. There is no telemetry endpoint, no analytics backend, no opt-in "help us improve" toggle.
4. **Layer-honest reporting:** Per-peer metrics are reported at the layer where they actually exist. RTT, NAT type, packet loss, k-bucket placement, address scoring are all DeviceID-keyed (routing layer, see §4.4). UserID-keyed metrics (e.g. messages exchanged with contact "Alice") are explicitly resolved into the underlying device set before any technical detail is shown.

### 18.2 Section 1: Network Health & Active Nodes

| Metric | Source | Description |
|--------|--------|-------------|
| Active peer count | `activePeerCount()` | Devices seen within last 120 seconds (not total ever-seen) |
| Total known peers | `totalKnownPeers` | All devices in routing table (14-day pruning window) |
| NAT type | `natType` | Detected NAT type (Full Cone, Restricted, Symmetric, etc.) |
| Public IP:Port | `publicIp`, `publicPort` | Externally visible address (from peer-reported STUN) |
| Uptime | `uptime` | Time since daemon start, formatted as "Xh Ym" |
| Status | online/offline | Current connectivity state |

**Health badge thresholds:**

| Active Peers | Badge | Label |
|-------------|-------|-------|
| >= 10 | Green | "good" |
| 3-9 | Yellow | "warning" |
| < 3 | Red | "critical" |

> **DeviceID, not UserID:** "Active peer count" counts **devices** reachable on the network, not user identities. A single user with three devices online contributes three entries. This matches the routing layer's view (see §4.4) and is what the routing table actually balances against k-bucket capacity.

**Network size estimation:** Since no single node has a complete view, the total network size is estimated via random DHT address space sampling: the node queries multiple random 256-bit IDs distributed across the address space and measures the density of responses. From the observed device density in sampled address regions, the total network size is estimated statistically. The estimate is **device-scoped** — the user-identity count is not directly observable from the routing layer.

### 18.3 Section 2: Personal Data Usage

| Metric | Granularity | Description |
|--------|-------------|-------------|
| Bytes sent (total) | Lifetime | Total outbound traffic |
| Bytes received (total) | Lifetime | Total inbound traffic |
| Bytes sent today | Daily reset | Today's outbound traffic |
| Bytes received today | Daily reset | Today's inbound traffic |
| Application frames sent | Lifetime counter | Total ApplicationFrames sent (chat, calls, control — see §2) |
| Application frames received | Lifetime counter | Total ApplicationFrames received |
| Chat messages sent | Lifetime counter | Subset of frames: user-visible chat content |
| Chat messages received | Lifetime counter | Subset of frames: user-visible chat content |

> **Wire vs application counters:** Bytes are measured at the transport layer (post-fragmentation, pre-decryption). Frame counters are measured at the application layer (one logical send = one frame, regardless of how many UDP fragments it produces). Chat-message counters are a strict subset and exclude control traffic (DV updates, ACKs, PING/PONG, mailbox-pull, calendar-sync).

### 18.4 Section 3: Relay Contribution

| Metric | Description |
|--------|-------------|
| Fragments stored | Erasure-coded fragments currently held for other users (see §5.4) |
| Frames relayed | Lifetime counter of successfully relayed ApplicationFrames (see §5.3) |
| Relay data volume | Total bytes relayed for other devices |
| Storage used | Current on-disk storage in bytes (S&F frames + fragments + DB) |
| Database size | SQLite database file size |

> **Relay = device-to-device:** Relay accounting is per **forwarding hop**, which is inherently a routing-layer (DeviceID) concept. The relay contribution does not distinguish which user identity originated or terminated the traffic — the relaying node only sees the outer frame's next-hop DeviceID. This is by design: it preserves sender-identity unlinkability against intermediate forwarders.

### 18.5 Section 4: Connection Details (Technical)

This section exposes the routing-layer view of the network. **All entries are keyed by DeviceID.** A single contact (UserID) may appear here as multiple device rows, each with its own connection state, addresses, RTT, and route.

| Metric | Description |
|--------|-------------|
| Direct connections | Number of currently active direct device-to-device connections |
| Routing table size | Total devices in DHT routing table |
| Average latency | Mean RTT to all reachable devices (ms) |
| Min/Max latency | Lowest and highest observed RTT |
| K-bucket fill | Bar chart: device count per k-bucket (capacity: 20 per bucket) |
| Device latencies | List of top 10 devices with individual RTT values, NAT type, current route, and packet-loss estimate |

**Per-device row format** (Device Latencies list and "Connection Details" expandable views):

```
Device:        7af3...2c8e  (12 hex chars + ellipsis)
Hosting users: Alice, Workshop-Bot          (resolved via Identity-Resolver, §4.3)
Transport:     Direct UDP via 192.0.2.5:39874
Route:         Direct (cost 1) | fallback: relay via 9b21...ef04 (cost 6)
RTT-EMA:       12 ms
Packet loss:   0.2 % (last 100 frames)
NAT type:      Full Cone
Last seen:     3 s ago
```

> **Why DeviceID, not UserID:** RTT, packet loss, NAT type and the chosen route are all properties of a **physical network endpoint**, not a logical identity. If contact "Alice" runs a phone behind CGNAT and a desktop in a clean LAN, those two endpoints have completely different connection characteristics. Aggregating them under a single "Alice" row would collapse meaningful detail and produce nonsense averages. v3.0 surfaces the routing layer truthfully: one row per device.

**User-tab cross-link:** Where the Contacts UI exposes a "Connection details" affordance for a contact, it routes the user into this section pre-filtered to the device set hosting that user. The header of the filtered view names the user (e.g. "Alice — 2 devices"); the rows below remain device-keyed. The mapping from UserID to the underlying DeviceID set is provided by the Identity-Resolver (see §4.3) and is cached locally per user.

**Multi-Identity on the local node:** A device may host several local user identities (see §3.6). Connection statistics for the local node are reported once (one DeviceID, one routing table, one set of RTTs) and are independent of which local identity is currently active in the GUI. Identity-switching never restarts the transport layer, so all metrics persist across switches.

**K-bucket visualization:** A bar chart where each bar represents one k-bucket in the Kademlia routing table. Bar height scales from 0 to capacity (20 devices). Tooltip shows bucket index and current fill ratio. This gives advanced users immediate insight into routing table balance — uneven fill indicates proximity clustering in the DHT address space.

### 18.6 Data Collection

All metrics are collected by a `NetworkStatsCollector` component in `CleonaService`. The collector:

- Tracks bytes sent/received at the transport layer (every UDP/TLS send/receive)
- Counts ApplicationFrames at the application layer (every processed frame, see §2)
- Samples per-device latency from ACK round-trip times (RTT-EMA in `AckTracker`, see §5.8)
- Polls routing table fill status from `RoutingTable.getBucketStats()` (see §4.4)
- Resolves UserID -> DeviceID-set mappings on demand via the Identity-Resolver cache (see §4.3) — never on the hot path of metric collection
- Persists counters to disk periodically (survives daemon restarts)

**Privacy:** No metrics are shared with any other device. The dashboard is purely a local view of this node's own activity. There is no telemetry, no analytics endpoint, no crash reporting, no remote aggregation. The only outbound traffic generated by the dashboard is the periodic Identity-Resolver lookup for device-set resolution, which is indistinguishable from any other identity-resolution query and is rate-limited and cached locally.

---

## 19. Licensing, Funding & Donation

### 19.1 Source Available Model

Cleona Chat's source code is publicly visible on GitHub for transparency, security auditing, and community trust. The custom license permits: reading and studying the source code, auditing the cryptographic implementation, submitting bug reports and feature requests, and building from source for personal use.

### 19.2 Publishing Infrastructure

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

### 19.3 Name & Brand Protection

The name "Cleona Chat" and its associated logo are protected by trademark registration, separate from the source code license. This ensures that even if someone were to create a modified version (in violation of the license), they cannot use the Cleona name or logo.

### 19.4 Funding Sources

- GitHub Sponsors for direct sponsorship on the project page.
- Open Collective for transparent donation management (all finances publicly visible).
- Liberapay for recurring donations without platform commission.
- Cryptocurrency (Bitcoin, Monero) for privacy-respecting donations.

### 19.5 In-App Donation Banner (Signal-Style)

Inspired by Signal's approach, Cleona includes a non-intrusive donation banner. The design philosophy: visible enough to generate necessary funding, gentle enough to never annoy users or create a negative experience.

#### 19.5.1 Placement & Behavior

Location: Displayed at the top of the chat list (conversation overview screen) only. Never appears inside an active conversation, never during typing or reading. Appearance: Small, subtle card with a friendly message and a "Donate" button.

#### 19.5.2 Design Principles

Never a popup, modal, or full-screen overlay — always an inline card element. No guilt-tripping or dark patterns — positive, grateful tone only. Rotating message texts to keep it fresh: "Cleona has no ads and no investors. Your support keeps it running."

#### 19.5.3 Donation Options

**Bank Transfer (SEPA):** IBAN with EPC QR code (EPC069-12 standard) for one-tap SEPA transfers from banking apps. Details (IBAN, BIC, recipient, institute) displayed with individual copy buttons. Ed25519-signed for fork protection.

**Cryptocurrency:** Bitcoin with QR code. Monero planned for users who prefer maximum privacy.

One-time donations with predefined amounts (€3, €5, €10, €25) plus custom amount entry planned. Recurring monthly donations via supported platforms planned.

#### 19.5.4 Fork Protection for Donations

Fork protection for donations operates in two layers:

**Primary protection (network-level):** The Closed Network Model (Section 4.10) ensures that only official maintainer-signed builds can participate in the Cleona network. A forked build without the correct network secret is cryptographically isolated — it cannot connect to any existing Cleona users. An app with zero connectivity generates zero donations. This is the primary defense and renders most fork-based donation scams impractical.

**Secondary protection (in-app verification):** Donation targets (IBAN, BTC address) are additionally signed with the Ed25519 maintainer keypair. The public key is embedded in the app (`assets/cleona_maintainer_public.pem`), the private key is kept offline by the maintainer. On the donation screen, the app verifies the Ed25519 signature and displays a trust indicator: green checkmark ("Official Cleona donation address") when the signature matches, or a red warning when it does not. This catches the edge case where someone modifies only the donation addresses in an otherwise official build without re-signing.

**Implementation details:** The donation config (address + base64-encoded signature) is stored in `lib/ui/screens/donation_screen.dart`. To update the address, the maintainer signs the new address with the private key: `echo -n "new_address" | openssl pkeyutl -sign -inkey cleona_maintainer_private.pem -rawin -out sig.bin && base64 sig.bin`. The app uses libsodium's `crypto_sign_verify_detached` (via `SodiumFFI.verifyEd25519()`) for verification.

**Residual risk:** A determined attacker who reverse-engineers the network secret from an official build AND replaces both the donation addresses and the maintainer public key could theoretically create a functional fork with redirected donations. This requires significant reverse engineering effort and is mitigated by secret rotation (Section 13.2), binary obfuscation (Section 4.10), and legal protection (Sections 19.1, 19.3).

#### 19.5.5 App-Wide Code Signing

All three signing mechanisms are implemented:

1. **Android APK Signing:** RSA 2048-bit Keystore (`key.properties`), release signing config in `build.gradle.kts`. Required for Play Store distribution.
2. **Linux Release Signing:** `scripts/sign-release.sh` generates tarball + SHA-256 checksum + GPG signature. Users can verify authenticity before installation.
3. **Signed Update Manifest (DHT):** `lib/core/update/update_manifest.dart` — Ed25519-signed version manifest with `UpdateChecker` that verifies signature against maintainer public key. Manifest signing via `scripts/sign-update-manifest.sh`. The manifest also carries optional `minRequiredVersion` and `minRequiredReason` fields for **Hard-Block-Update-Enforcement** — see Section 19.5.7.

The existing maintainer Ed25519 keypair (used for donation verification) is reused for the DHT update manifest. Android and Linux signing use platform-specific keys (Android Keystore, GPG respectively).

#### 19.5.6 Android Flavors — Beta/Live Parallel Install

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

#### 19.5.7 Hard-Block Update Enforcement

When a release introduces a backward-incompatible change (e.g., a Per-Message-KEM HKDF-Salt cutover), pre-release clients would silently lose messages because their wire format is no longer accepted by updated peers. Hard-Block-Update-Enforcement prevents this silent failure mode.

**Mechanism:**

The Signed Update Manifest (Section 19.5.5) carries two optional fields:

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
- User-message Receive (TEXT, FILE, IMAGE, VIDEO, VOICE_MESSAGE, EMOJI_REACTION, MESSAGE_EDIT, MESSAGE_DELETE, CHANNEL_POST, CALENDAR_*, POLL_*) is gated — silently dropped at frame dispatch.
- Existing conversations remain readable and scrollable (DB-stored plaintext, not affected).
- Settings screen is accessible (allows identity export, profile inspection, etc.).
- DHT-Participation continues (PEER_LIST_PUSH, presence, routing-table maintenance) — kept fresh in case the user later updates and re-enters normal operation without a cold network start.
- A persistent red banner at the top of the home screen reminds the user of the limited mode.

**Persistence:** Reduced-Mode is per-session, not persisted. Every app restart re-evaluates the manifest and re-shows `UpdateRequiredScreen` if still applicable. This prevents users from "forgetting" they are in limited mode.

**Multi-Identity scope:** The hard-block applies at the daemon process level — all identities of the installation are gated together. Multi-Identity does not provide a per-identity bypass.

**Rollback story:** If a release with `minRequiredVersion = X` introduces a critical bug, the rollback release re-publishes a manifest with `minRequiredVersion = null`. Cached manifests refresh within the 6h DHT-poll window, so the worst-case net-split lasts ~6h. Pre-release verification on the Beta cluster is the primary defense; rollback is a fallback with cost. Stability validation happens organically through real Beta usage (Multi-Identity traffic across the maintainer's own cluster) — issues surface as concrete user reports rather than synthetic soak loops.

---

## 20. Tech Stack

### 20.1 Design Principles

1. **No cloud dependencies:** Every library runs on-device. No Google Play Services required. No Firebase. No external APIs. (Push wake-up via Firebase was considered and rejected; see §12.4.)
2. **FFI for performance-critical code:** Cryptography, compression, audio/video codecs, and speech recognition use native C/C++ libraries via Dart FFI. Pure Dart fallbacks exist where feasible (Reed-Solomon).
3. **Cross-platform via Flutter:** A single Dart codebase targets Linux, Windows, Android, and iOS. Platform-specific code is isolated in `lib/core/platform/` and `lib/core/tray/`.

### 20.2 Application Framework

| Component | Technology | Version | Rationale |
|-----------|-----------|---------|-----------|
| Framework | Flutter (Dart) | SDK >=3.11.0 | Single codebase for 4 platforms, native performance, rich widget system |
| State management | Provider | ^6.1.0 | Simple, well-tested, no boilerplate |
| Serialization | Protocol Buffers (protobuf) | ^4.0.0 | Compact binary format, schema evolution, language-neutral |
| Database | SQLite via drift ORM | — | Embedded, zero-config, encrypted at rest |
| UUID generation | uuid | ^4.0.0 | RFC 4122 v4 for message and event IDs |

### 20.3 Native Libraries (FFI)

| Library | Dart FFI Binding | Provides | Notes |
|---------|-----------------|----------|-------|
| **libsodium** | `sodium_ffi.dart` | Ed25519, X25519, AES-256-GCM, XSalsa20-Poly1305, SHA-256, HMAC-SHA256, HKDF, Argon2id, BLAKE2b | System package (`libsodium-dev`). 32-byte keys, 64-byte sigs. On iOS: static-linked, `DynamicLibrary.process()`. |
| **liboqs** | `oqs_ffi.dart` | ML-KEM-768 (post-quantum KEM), ML-DSA-65 (post-quantum signatures) | Built from source (not in distro repos). `OQS_init()` required before first use. |
| **libzstd** | `compression.dart` | Zstandard compression/decompression | System package (`libzstd-dev`). All payloads compressed before encryption. |
| **liberasurecode** | `reed_solomon.dart` | Reed-Solomon erasure coding (N=10, K=7) | System package. Pure Dart fallback on platforms without it. |
| **libwhisper** | `whisper_ffi.dart` | On-device speech-to-text (whisper.cpp) | Built from source + GGML deps. Optional — voice messages work without it. |
| **libopus** | `opus_ffi.dart` | Opus audio codec (legacy path) | Retained as a build artefact for the prior FFI binding; the live audio path uses raw PCM via `libcleona_audio` (see §10.4). May be reintroduced behind the shim later for metered links. |
| **libvpx** | `vpx_ffi.dart` (via cleona_vpx shim) | VP8 video codec (I420/YUV 4:2:0, CBR, real-time) | For video calls. Adaptive bitrate. Error-resilient mode. |
| **miniaudio** | via `libcleona_audio` C shim | Cross-platform audio capture + playback (PulseAudio/ALSA on Linux, AAudio/OpenSL on Android, WASAPI on Windows, Core Audio on macOS/iOS) | Single-header library, version 0.11.21, vendored at SHA256 `6b2029714f8634c4d7c70cc042f45074e0565766113fc064f20cd27c986be9c9`. See §10.4. |
| **speexdsp** | via `libcleona_audio` C shim | Acoustic Echo Cancellation + Noise Suppression for the audio capture path | Version 1.2.1, **vendored as full source** under `native/cleona_audio/vendor/speexdsp/` (SHA256 `d17ca363654556a4ff1d02cc13d9eb1fc5a8642c90b40bd54ce266c3807b91a7`), statically linked. AEC tail = 250 ms @ 16 kHz. |
| **cleona_net** | `native_udp_sender.dart` via `libcleona_net` C shim | Direct-syscall UDP send-path. Wraps POSIX `sendto` on Linux and Win32 `WSASendTo` on Windows synchronously. Required on both desktop platforms (no runtime fallback). See §4.5.2 for the architectural rationale and §20.3a below for the build details. |

The **cleona_net** entry in the table above deserves a longer explanation because, unlike the other native libraries in this list, it does not unlock a feature that would otherwise be unavailable — Dart already ships a perfectly working `RawDatagramSocket`. We introduced the shim because Dart's implementation on Windows silently drops roughly 89 percent of sustained UDP send calls during the LAN-Discovery subnet-scan phase, while the very same workload (200-15000 packets at up to 500 pps to many different destinations) goes through with zero drops when issued by PowerShell's `.NET UdpClient`. The forensic chain that established this is documented at §4.5.2 — pktmon-counters on the Windows TCPIP layer confirm the dropped sends never reach the kernel, and raising the kernel `SO_SNDBUF` to 4 MB did not change the drop rate. The defect therefore lives inside Dart's Windows I/O implementation (likely the IOCP-based UDP send path), below where any Dart-level workaround can reach. Linux is unaffected — Dart's POSIX path uses blocking `sendto` and behaves identically to the C shim. We build and link the shim on Linux as well for the **discovery send path** (`LocalDiscovery`, port 41338). The **main data-port** transport (`Transport.sendUdp`), however, uses the native sender **only on Windows** (V3.1.72). Rationale: `cleona_udp_open` binds a real `SO_REUSEADDR` UDP socket on the given port; when opened on the *data* port in addition to Dart's receive socket, the Linux kernel delivered inbound datagrams to the send-only native socket — which is never read — starving the Dart `RawDatagramSocket` and breaking **all** inbound processing (no PONG → no peer ever confirmed → dead mesh). This was a regression introduced by commit `2fbc879` (it extended the Windows send-fix to the main port without updating this section). Because Dart's POSIX send path is unaffected (stated above), the Linux main port now uses `RawDatagramSocket` for both send and receive — exactly **one** socket per data port. `Transport.start()` enforces this with a `/proc/net/udp` self-check that logs an error if a second IPv4 socket ever binds the data port again. A behavioural regression guard lives in `test/smoke/smoke_udp_receive_path.dart`.

The native library is a hard dependency on Linux and Windows desktop builds. If `libcleona_net.so` (Linux) or `cleona_net.dll` (Windows) is missing at daemon startup, the daemon refuses to start and prints a clear error message naming the expected file path. There is no fallback to the Dart send path. This is deliberate: a silent fallback would mask a broken build or a missed deployment step exactly the way the Windows drops themselves went unnoticed for weeks, and we would risk discarding a working architectural fix as "useless" because operations look identical to the un-fixed state.

Android, iOS, and macOS builds do not include `libcleona_net` and continue to use Dart's `RawDatagramSocket` directly. On those platforms the Dart-RawDatagramSocket implementation has no observed drop pattern, so introducing the shim there would only enlarge the trusted native-code surface without functional benefit. If a regression appears on one of those platforms in a future release, the shim can be extended (Phase 2) — the C source is platform-agnostic POSIX on those targets.

### 20.3a Build Mechanics for cleona_net

C sources live under `native/cleona_net/` (parallel to `native/cleona_audio/`) with a CMakeLists.txt that produces `libcleona_net.so` on Linux and `cleona_net.dll` on Windows. The Linux build is bundled into the Flutter Linux release alongside `libcleona_audio.so`; the Windows build drops into `build/windows/x64/runner/Release/` next to `libsodium.dll` and `liboqs.dll`. Exact build invocations and packaging steps are kept with the source tree rather than duplicated here — see `native/cleona_net/README.md` for the build recipe and `docs/PUBLISHING.md` for the release-bundle assembly.

### 20.3b iOS and macOS Native Library Build Pipeline

iOS forbids loading custom dynamic libraries at runtime — all native code must be statically linked into the app binary. Dart FFI accesses symbols via `DynamicLibrary.process()` (the process-global symbol table). macOS uses traditional dynamic libraries (`.dylib`) loaded from `Cleona.app/Contents/Frameworks/`.

**iOS build** (`scripts/build-ios-libs.sh`, must run on macOS):
- Cross-compiles all 7 native libraries (libsodium, liboqs, libzstd, liberasurecode, libopus, whisper.cpp, libcleona_audio) as **static archives** (`.a`) for two platforms: `arm64-iphoneos` (device) and `arm64-iphonesimulator`.
- Packages each library as an **XCFramework** (`xcodebuild -create-xcframework`) in `build/ios-frameworks/`.
- XCFrameworks are integrated via `ios/CleonaNative/CleonaNative.podspec` (vendored_frameworks, `-ObjC -all_load` linker flags to force-export all symbols for FFI).
- `libcleona_audio` requires Objective-C compilation on Apple platforms (miniaudio.h includes AVFoundation ObjC headers); CMakeLists.txt conditionally enables `project(cleona_audio C OBJC)` and links AudioToolbox + AVFoundation frameworks.
- iOS Deployment Target: 15.5 (required by `mobile_scanner` plugin).

**macOS build** (`scripts/build-macos-libs.sh`, must run on macOS):
- Builds all libraries as shared `.dylib` for arm64 (Apple Silicon), x86_64 (Intel), or universal (lipo merge).
- `install_name_tool` rewrites LC_LOAD_DYLIB to `@rpath/<name>.dylib`; all dylibs are ad-hoc signed.
- `scripts/deploy-macos-app.sh` assembles the final `Cleona.app` bundle: Flutter GUI + headless daemon + dylibs in Contents/Frameworks/.

**CI/CD** (`.github/workflows/ios-build.yml`, GitHub Actions `macos-14` runner):
- Workflow "Apple Build (iOS + macOS)" with platform selector (both/ios/macos) and channel selector (beta/live).
- iOS pipeline: build native libs → upload XCFrameworks artifact → flutter build ipa → code sign (manual, Apple Development certificate) → upload IPA artifact.
- macOS pipeline (parallel): build native dylibs → flutter build macos → dart compile daemon → assemble app bundle → code sign → create DMG → notarize via App Store Connect API.
- Signing credentials (certificate .p12, provisioning profile, API key) stored as GitHub Secrets (base64-encoded). The .p12 must use legacy PKCS12 format (3DES+SHA1) because macOS `security import` on CI runners rejects the OpenSSL 3.x default cipher suite.

### 20.4 Flutter Packages

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

### 20.5 External Tools (Runtime)

| Tool | Platform | Purpose | Required? |
|------|----------|---------|-----------|
| `ffmpeg` | Linux/Windows | Audio format conversion (AAC/OGG -> WAV 16 kHz PCM) for whisper.cpp | Optional (voice transcription only) |
| `wl-clipboard` | Linux (Wayland) | Binary clipboard paste (screenshots, images) | Optional (text paste works without) |
| `xclip` | Linux (X11) | Binary clipboard paste (screenshots, images) | Optional (text paste works without) |
| `pw-play` | Linux (PipeWire) | Notification sounds, ringtones | Falls back to `paplay` (PulseAudio) |

### 20.6 Platform Targets

| Platform | Role | Architecture | Binary |
|----------|------|-------------|--------|
| Linux Desktop (x86_64) | Primary development | Daemon + GUI (separate processes, IPC via Unix socket) | `cleona-daemon` + `cleona` (Flutter bundle) |
| Windows Desktop (x86_64) | Test | Daemon + GUI (IPC via TCP loopback + auth-token) | `cleona-daemon.exe` + `cleona.exe` |
| Android (arm64-v8a, x86_64) | Release | In-process (single Flutter app) | APK with jniLibs |
| iOS (arm64) | Release | In-process (static native libs via XCFrameworks, `DynamicLibrary.process()`) | IPA (via GitHub Actions macOS-14 runner) |
| macOS (arm64) | Release | Daemon + GUI (separate processes, IPC via Unix socket) | `cleona-daemon` + `Cleona.app` (DMG, via GitHub Actions) |

---

*Section 21 is omitted from the public edition.*


---

*Section 22 is omitted from the public edition.*


---

## 23. V2.2 → V3.0 Migration

This chapter documents the migration from Cleona Architecture v2.2 to v3.0. It remains in the spec long-term as a reference — both for developers who want to understand historical v2.2 concepts and as the rationale for why v3.0 became a hard cut rather than a patch.

### 23.1 Why a Cut, Not a Patch

V2.2 evolved over ~12 months from a clean architectural design into a patchwork spec of ~5750 lines. The last 30 days were dominated by an accumulating bug cascade: the 2D-DHT hard cut (commit `db14d0a`, 2026-04-26) removed the default-gateway resolution fallback and replaced it with sole identity resolution via the 2D-DHT. This made send success dependent on **five simultaneously satisfied conditions** (receiver publish, K=10 reachability, auth-manifest replication, liveness TTL, correct ID type at the resolver call) where previously **one** condition had been sufficient (default GW knows the target). Consequence: user tests reproducibly failed to deliver.

Reactive patches (DV-1 surgical markRouteDown, DV-3 cost bias, DV-5 retry order, DV-6 dynamic cap, DV-7 step-2d fanout, DV-8 welcome-storm) cured symptoms but not the root cause. The user reality-check statement "before the 2D-DHT upgrade everything worked without issue" and the structural forensics in session 2026-05-01 led to the decision: no further quick fix, but a layer split in wire format and API layer.

Because the refactor:
- Changes the wire format incompatibly (NetworkPacket instead of MessageEnvelope)
- Renames API callers in 38+ locations (sendEnvelope → sendToUser/sendToDevice)
- Introduces the device-sig keypair as a new crypto-subject class
- Removes MessageQueue completely

a v2.2-to-v3.0 backwards compatibility is not practical. Cleona is in beta state with ~7 active nodes, no productive data inventory that would justify a migration layer. Instead of a half-refactor with compat bridges (which would themselves be sources of bugs), the cut is performed cleanly: all nodes upgrade to v3.0 simultaneously, profile reset.

### 23.2 Profile Reset & Wire-Format Cut

**Profile reset on upgrade**: A v3.0 daemon cannot read v2.2 profiles. Concretely affected:
- Identities (regenerate user keys + device keys — the device key is new in v3.0)
- Conversations (local message database lost)
- Contacts (lost — recovery via QR-code reshare or restore broadcast)
- Routing table (lost — rebuilt via mesh discovery: LAN burst, Subnet-Scan-Fallback, ContactSeed import)

**Recovery path** for affected users:
1. Install v3.0 daemon
2. On first start: enter the 24-word recovery phrase (regenerates user identities via HD wallet)
3. Restore broadcast (§6.3) reaches online contacts → contact list is rebuilt
4. Local conversations are lost — but by Cleona's privacy model they are never backed up to a server anyway
5. Multi-device setup (§7) is set up freshly, because device keys are new

**Wire-format cut**: V3.0 nodes and v2.2 nodes cannot talk to each other:
- The HMAC in the NetworkPacket outer (v3.0) has a different position and format than the HMAC in the MessageEnvelope (v2.2)
- v2.2 nodes expect a `MessageEnvelope` top-level — v3.0 sends NetworkPacket
- v3.0 nodes expect NetworkPacket — v2.2 nodes send MessageEnvelope (but the HMAC does not match, drop before parse)
- In practice: both ignore each other — no crash risk, only "no peer there"

**Deployment requirement**: All active Cleona nodes must upgrade to v3.0 **within a short time window** (~24h). Bootstrap nodes first, so the network does not fall apart.

### 23.3 Code-Migration Map

Overview of the code refactors needed to bring the v2.2 codebase up to v3.0 spec. The map is grouped by subsystem. **Estimate: ~1500-2500 LOC change.**

**Wire-format layer** (`lib/core/network/`, `lib/generated/proto/cleona.pb.dart`):
- Restructure proto file `proto/cleona.proto`: remove `MessageEnvelope`, add `NetworkPacket` + `ApplicationFrame`
- Remove old fields (`senderId`, `senderDeviceNodeId`, `recipientId` as top-level)
- Re-run `proto-gen` → new Dart classes
- `transport.dart`: adapt send/receive paths to the new format

**Routing layer** (`lib/core/network/`, `lib/core/dht/`):
- `dv_routing.dart`: works with DeviceID instead of generic `nodeId` — terminology hygiene
- `routing_table.dart`: `getPeer`, `getPeerByUserId` become `getPeerByDeviceId`, `getDevicesByUserId`. The secondary UserID index stays, but is now clearly communicated as a "User → List<Device>" map
- `kbucket.dart`: keyed by deviceId, unchanged in substance

**Identity-resolution layer** (`lib/core/identity_resolution/`):
- `identity_resolver.dart`: contract stays (`resolve(userId) → List<ResolvedDevice>`), but is now called **before** routing (in the service layer), not in the send path
- `identity_publisher.dart`: unchanged
- `identity_dht_handler.dart`: unchanged

**Crypto layer** (`lib/core/crypto/`):
- New file: `device_signature.dart` — device-sig keypair generation, sign/verify operations
- `key_manager.dart`: extend HD-wallet derivation with a device-key branch (locally generated, NOT seed-derived)
- `per_message_kem.dart`: unchanged (KEM v2 stays)
- Switch sig verify in `verify_outer_envelope.dart` to device sig instead of user sig

**Service layer** (`lib/core/service/cleona_service.dart`, `lib/core/services/message_sender.dart`):
- **Migrate 38 sendEnvelope callers**: each call is classified and switched to `sendToUser(userId)` or `sendToDevice(deviceId)`
- New API in `cleona_node.dart`:
  ```dart
  Future<bool> sendToDevice(NetworkPacket packet, Uint8List deviceId);
  Future<List<DeviceId>> resolveUserToDevices(Uint8List userId);
  ```
- New API in `cleona_service.dart`:
  ```dart
  Future<bool> sendToUser(MessageType type, Uint8List payload, Uint8List userId);
  ```
- **Remove** `sendEnvelope` as a function — not deprecated, but gone

**MessageQueue removal** (`lib/core/network/message_queue.dart`):
- Remove the file completely
- Remove the `messageQueue` reference in `cleona_node.dart`
- `message_queue.json` persistence no longer needed — old files can be deleted with the profile reset
- Failure modes: on "all routes exhausted", `sendToDevice` simply returns `false`. The caller (sendToUser) decides whether the S&F backup (`_storeErasureCodedBackup`) is triggered

**Receive pipeline** (`lib/core/services/message_receiver.dart`, `lib/core/services/message_handler.dart`):
- Two-stage decap: first NetworkPacket layer (outer sig + HMAC + PoW + routing decision), then ApplicationFrame layer (KEM decrypt + user sig + identity dispatch)
- Use `recipientUserId` from the ApplicationFrame for user-tab dispatch

**Test files**: see §23.4

**CLAUDE.md / architecture doc**:
- `Cleona_Chat_Architecture_v2_2.md` gets a DEPRECATED header
- Switch the `CLAUDE.md` pointer to `Cleona_Chat_Architecture_v3_0.md`
- Update project memory (create v3.0-relevant project files)

### 23.4 Test-Migration Map

**Smoke tests** (`test/smoke/`):
- **New wire-format tests**:
  - `smoke_network_packet.dart` — parse/serialize roundtrip, version field, default values
  - `smoke_application_frame.dart` — parse/serialize, KEM roundtrip
  - `smoke_layered_pipeline.dart` — full sender + receiver pipeline, all failure modes
- **Adapt existing tests**:
  - `smoke_routing.dart` — switch from sendEnvelope to sendToDevice
  - `smoke_identity_resolver.dart` — resolver contract stays, test setup adapted
  - `smoke_dv_*.dart` — routing tests stay in substance, correct ID-type annotations
  - `smoke_dht_*.dart` — test DHT replication with the new identity records
- **Tests that fall away**:
  - `smoke_message_queue.dart` (if it exists) — MessageQueue is gone
  - Various v2.2-specific edge cases that are no longer possible due to the layer split

**E2E tests** (`test/e2e/`):
- **GUI tests are largely wire-format-agnostic** — they test the user view ("user types Hello, recipient sees Hello"). The code migration in the daemon is transparent to the GUI.
- **IPC tests** (setup/teardown via IPC): remain functional, but the internal implementation of the IPC commands may change. `sendText` IPC, for example, stays semantically identical, internally now calls `sendToUser`.
- **Cross-platform call tests** (gui-25, gui-34): should stay green unchanged, because calls have their own crypto pipeline (call_key in inner, device sig in outer)
- **2D-DHT tests** (gui-55): resolver tests stay structurally the same, since the resolver contract remains stable

**Migration test suite (NEW)** in `test/smoke/migration/`:
- `smoke_v3_wire_format.dart` — wire-frame parse, roundtrip, failure modes
- `smoke_v3_layered_encryption.dart` — sender → receiver end-to-end
- `smoke_v3_service_api.dart` — sendToUser, multi-device fanout, sendToDevice, routing cascade
- `smoke_v3_default_gateway_fallback.dart` — routing cascade hits defaultGW as last resort
- `smoke_v3_no_message_queue.dart` — verifies that no MessageQueue persistence happens any more
- `smoke_v3_profile_reset.dart` — daemon comes up cleanly after reset

Detailed in §21.4 V3.0 Migration Tests.

### 23.5 Git-Pipeline Adjustments

Cleona's publishing pipeline (see `docs/PUBLISHING.md`) uses a 4-script pipeline with hookify enforcement. For the v2.2 → v3.0 cut, several places must be adjusted:

**`scripts/sync-to-git.sh`**:
- The master architecture file path changes: `Cleona_Chat_Architecture_v2_2.md` → `Cleona_Chat_Architecture_v3_0.md`
- Hash snapshot before/after now for the v3.0 file
- The public variant in `CleonaGit/docs/ARCHITECTURE.md` is generated from v3.0 (master copy + scrub + INTERNAL-marker stripping)
- The v2.2 file is **not** touched by the sync script — it stays in the master repo as history, but does not land in the public repo

**Hookify rules** (`docs/hookify_rules/`):
- Extend the `block-master-arch-write` filename match to v3.0
- `require-neutralized-cleonagit-commit` stays unchanged
- `block-push-from-cleona` stays unchanged

**v2.2 DEPRECATED header**:
- `Cleona_Chat_Architecture_v2_2.md` gets a block at the top:
  ```markdown
  > **DEPRECATED — V2.2 is no longer the authoritative spec.**
  > Active spec: [Cleona_Chat_Architecture_v3_0.md](Cleona_Chat_Architecture_v3_0.md)
  > V2.2 is kept as history but no longer maintained. Cross-walk at §-level see `docs/V3_MIGRATION_MAP.md`.
  ```
- Body unchanged — no modifications to the body

**`CLAUDE.md` pointer updates**:
- Sentences referring to `Cleona_Chat_Architecture_v2_2.md` → switch to v3.0
- Working rule #4 stays in substance, only the filename reference changes

**Allowlist in the sync script**:
- No change to the allowlist needed — v3.0 replaces v2.2 1:1, both have identical allowlist behavior

**CleonaGit repo sync**:
- After the first v3.0 sync: the old `ARCHITECTURE.md` in the public repo is overwritten with the v3.0-generated version
- Public description in the public repo (`README.md`) optionally extended with a v3.0 hint

### 23.6 v2.2 Sections Index (Cross-Walk)

The full cross-walk table is maintained in `docs/V3_MIGRATION_MAP.md` — it is the primary tracking document that stays active during implementation. Here only a top-level summary:

| v2.2 area | Fate | v3.0 position |
|---|---|---|
| §1 Executive Summary | REWRITE | §1 (with V3.0 Architecture Highlights as §1.2) |
| §2 Network Architecture | SPLIT + REWRITE | §2 Wire-Format (NEW), §4 Network |
| §3 Erasure Coding & Message Delivery | REWRITE | §5 Message Delivery |
| §4 Encryption & Cryptography | REWRITE | §3 Identity & Cryptography |
| §5 Identity & Authentication | REWRITE | §3 Identity (merged with §4) |
| §6 Identity Recovery | PORT | §6 Identity Recovery |
| §7 Synchronization Strategy | PORT | §12 Synchronization Strategy |
| §8 App Permissions & Privacy | PORT | §16 Permissions & Privacy |
| §9 DoS Protection | PORT | §13.1 DoS Protection |
| §10 Channels & Moderation | PORT | §9 Group Features |
| §11 Network Statistics | REWRITE | §18 Network Statistics |
| §12 Tech Stack | PORT | §20 Tech Stack |
| §13 i18n | PORT | §17 Internationalization |
| §14 Feature Roadmap | REWRITE | §24 Roadmap |
| §15 Data Management & Storage | PORT | §14 Storage & Data Management |
| §16 Licensing, Funding & Donation | PORT | §19 Licensing, Funding & Donation |
| §17 Security Considerations | SPLIT | §13 Network Resilience, §4.10 Closed Network Model |
| §18 Application Architecture | REWRITE | §15 Application Architecture |
| §19 Testing & Development Strategy | PORT + ADD | §21 Testing Strategy (+§21.4 V3.0 Migration Tests NEW) |
| §20 Linux Development Environment | PORT | §22.1 Linux Setup |
| §21 VM Test Infrastructure | PORT | §22.2 VM Test Infrastructure |
| §22 Development Plan | REWRITE | §24 Roadmap |
| §23 Calendar | PORT | §11.1 + §11.2 |
| §24 Polls | PORT | §11.3 + §11.4 |
| §25 In-Call Collaboration | PORT | §10.5 |
| §26 Multi-Device Support | REWRITE | §7 Multi-Device Support |
| §27 IPv6 Dual-Stack & CGNAT | PORT | §4.7 IPv6 Dual-Stack & CGNAT |
| §28 Appendix Protocol Format | REWRITE | Appendix A: Protocol Message Format |

**NEW v3.0 sections without a v2.2 counterpart**:
- §1.2 V3.0 Architecture Highlights
- §2 (complete: Wire-Format & Layered Frames, 6 subs)
- §2.5 Onion-Routing Hook
- §3.5 Device Identity Sigs
- §13.3 Service Layer Resilience
- §21.4 V3.0 Migration Tests
- §23 V2.2 → V3.0 Migration (this chapter)
- Appendix B: Frame Examples
- Appendix C: V2.2 → V3.0 Section Cross-Walk

**Section cross-walk in Appendix C**: at the end of the spec, automatically generated from `docs/V3_MIGRATION_MAP.md`. Identical to the table above, but per v2.2 subsection (not only top-level), fully end-to-end.

---
## 24. Roadmap

### 24.1 V3.0 Status

V3.0 is an architectural major revision (see §1.2 V3.0 Architecture Highlights and §23 V2.2 → V3.0 Migration). Implementation status is tracked in the code repository via tags (`v3.0.0-beta.X`) and in the project memory — this spec is the authoritative architectural reference, not a project-plan tracker.

**What V3.0 delivers** (compressed list, in full in §1.2):

- 2-layer wire format (NetworkPacket Outer + ApplicationFrame Inner)
- Service API separation (sendToUser + sendToDevice)
- Default-Gateway fallback in the routing layer
- MessageQueue retired, S&F + Mailbox take over offline delivery
- Onion-routing hook prepared, not activated
- Device-Sig keypair as its own crypto-subject class
- Profile reset on upgrade (no v2.2 backwards compatibility)

**What V3.0 does not change** (see §1.2 "What remains unchanged"):
- Crypto primitives (KEM v2, hybrid sigs, HMAC, PoW, erasure, DB encryption)
- Calendar, Polls, Channels, Calls functionality (only API callers migrated)
- Multi-Identity HD-Wallet derivation
- 2D-DHT identity resolution (mechanism retained, only clearly framed as a pre-send step)

### 24.2 Post-V3.0 Plans

Concrete items to be addressed post-V3.0 — not part of V3.0, but deliberately staked out architecturally:

**Activate onion routing** (in V3.x or V4.0):
- The Outer-Frame format is already onion-capable (see §2.5)
- Activation requires: path-selection algorithm, hop-diversity heuristic, anti-correlation logic, optionally decoy traffic
- Reasonable only at mesh size ≥1000 active nodes (anonymity-set constraint)
- The taboo list (§2.5) remains binding: live calls, DHT infrastructure, hole punch never via onion

**macOS port** (V3.x):
- Currently uncommitted v1 state
- Daemon + GUI analogous to Linux, tray via NSStatusBar FFI
- IPC via Unix socket (analogous to Linux)

**iOS polishing** (V3.x):
- Background modes: voip + audio + processing
- BGProcessing tasks for mailbox polling
- Static linking of all native libs

**Multi-Interface Send** (V3.x — spec from 2026-04-30 exists as a draft):
- Per-peer multi-path over Wi-Fi + cellular in parallel
- Sockets list instead of XOR
- Per-interface ACK tracking
- Address tagging with `local_interface` enum
- Architectural decision pending (battery, data consumption, default setting)

**In-Call Collaboration** (V3.x phase 2 — spec in §10.5):
- Whiteboard, file exchange, screen sharing, remote control
- Currently documented as "planned"; implementation outstanding

**Public-channel mass adoption** (V3.x or V4.0):
- Decentralized moderation (§9.3) is designed but little field-tested
- Anti-Sybil (§9.4) needs real channel sizes for validation
- ContentRating workflow (§9.2.2) requires UI polishing

**Calendar External Sync extensions** (V3.x):
- Deliberately NOT 2-way Android sync (see §11.2.8 ADR)
- Possible new sync targets: CalDAV discovery via Bonjour, EWS (Exchange Web Services)

**Performance profile**:
- KEM decryption throughput on mobile (currently ~1000 frames/s, target ~5000)
- DB read latency on large conversations (>10k messages)
- UI render performance on low-end Android (jank-free on 4-core ARMv8)

**Sec-hardening backlog**:
- Sig-verify constant-time audit (side-channel protection)
- Memory-leak detection for private keys
- Threat-model extension by network-observer class (leads to onion activation)

The roadmap is planned in the project memory with concrete sessions/sprints — this spec only links the architectural end goals.

---
## Appendix A. Protocol Message Format

V3.0 wire-format definitions. All frames are Protocol-Buffer-serialized. The canonical `.proto` file lives in `proto/cleona.proto`; the Dart classes are generated from it via `protoc-gen-dart`.

### A.1 NetworkPacket (Outer Layer)

This is the physical UDP packet (or TLS frame). What relays see.

```protobuf
syntax = "proto3";
package cleona;

message NetworkPacket {
  uint32      version          = 1;   // V3.0 = 1
  uint32      flags            = 2;   // bit-flags, default 0
  bytes       nextHopDeviceId  = 3;   // 32 bytes — destination
  bytes       senderDeviceId   = 4;   // 32 bytes — sender device
  uint64      timestampMs      = 5;
  uint32      ttl              = 6;   // default 64
  uint32      hopCount         = 7;   // +1 per relay
  bytes       networkTag       = 8;   // 16 bytes HMAC-SHA256-128
  bytes       pow              = 9;   // PoW solution

  // Sig (subject = device keypair)
  bytes       deviceEd25519Sig = 10;  // 64 bytes, always
  bytes       deviceMlDsaSig   = 11;  // ~3300 bytes — empty for infrastructure

  // Payload discriminator
  PayloadType payloadType      = 12;
  bytes       payload          = 13;  // serialized ApplicationFrame, InfrastructureFrame, or nested NetworkPacket (onion)
}

enum PayloadType {
  APPLICATION_FRAME    = 0;   // payload = KEM-encrypted ApplicationFrame (Identity layer)
  ONION_LAYER          = 1;   // payload = KEM-encrypted nested NetworkPacket (V3.0 not active, §2.5)
  INFRASTRUCTURE_FRAME = 2;   // payload = KEM-encrypted InfrastructureFrame (Device-targeted, §2.3.5, NEW Welle 5)
}
```

### A.2 ApplicationFrame (Inner Layer)

KEM-encrypted under the recipient user pubkey. Only the recipient device can decrypt.

```protobuf
message ApplicationFrame {
  uint32      version          = 1;
  bytes       recipientUserId  = 2;   // 32 bytes
  bytes       senderUserId     = 3;   // 32 bytes
  uint64      timestampMs      = 4;
  bytes       messageId        = 5;   // 16 bytes UUID v4
  MessageType messageType      = 6;
  bytes       payload          = 7;   // type-specific protobuf

  // Sig (subject = user keypair)
  bytes       userEd25519Sig   = 10;  // 64 bytes, always
  bytes       userMlDsaSig     = 11;  // ~3300 bytes, always for user frames

  // Optional metadata
  ContentMetadata    contentMetadata    = 12;  // Reply-To, Quote, Attachments
  EditMetadata       editMetadata       = 13;
  ExpiryMetadata     expiryMetadata     = 14;
  ErasureCodingMetadata erasureMetadata = 15;
  CompressionType    compression        = 16;

  // Conversation routing
  bytes       groupId          = 17;  // empty for DM; set for group/channel pairwise fan-out
                                      // (receiver dispatches to group/channel conversation;
                                      // payload-internal group_ids in Calendar/Polls are
                                      // semantically distinct linked-event-association)
}
```

### A.2b InfrastructureFrame (Device-targeted Inner Layer, NEW in V3.0 Welle 5)

KEM-encrypted under the recipient device-KEM pubkey (X25519+ML-KEM-768 hybrid v2). Only the recipient device can decrypt. **No User-Sig fields** — there is no UserID subject; the Outer Device-Sig provides routing-layer authenticity. Used for DHT operations, routing probes, NAT/hole-punch, reachability, fragment/S&F, peer-list gossip, and 2D-DHT identity-resolution traffic. See §2.3.5 for the normative MessageType selector list.

```protobuf
message InfrastructureFrame {
  uint32      version            = 1;   // V3.0 = 1
  bytes       recipientDeviceId  = 2;   // 32 bytes
  bytes       senderDeviceId     = 3;   // 32 bytes (= NetworkPacket.senderDeviceId)
  uint64      timestampMs        = 4;
  bytes       messageId          = 5;   // 16 bytes UUID v4 — end-to-end dedup
  MessageType messageType        = 6;   // restricted to §2.3.5 selector list
  bytes       payload            = 7;   // type-specific protobuf
                                        // (CR-Bootstrap special case: serialized
                                        //  ApplicationFrame bytes — see §8.1.1)
}
```

When the Outer NetworkPacket carries `payloadType = INFRASTRUCTURE_FRAME`, the payload bytes are a `PerMessageKem` whose `aeadCiphertext` field contains the AEAD-encrypted serialized `InfrastructureFrame`.

### A.3 PerMessageKem (Inner-Frame KEM Header)

Carried inside `NetworkPacket.payload` as a KEM-encrypted ApplicationFrame **or** InfrastructureFrame (V3.0 Welle 5+).

```protobuf
message PerMessageKem {
  bytes  x25519Ciphertext = 1;   // 32 bytes
  bytes  mlKemCiphertext  = 2;   // 1088 bytes ML-KEM-768
  bytes  aeadCiphertext   = 3;   // ChaCha20-Poly1305(serialized ApplicationFrame) + 16-byte tag
  bytes  aeadNonce        = 4;   // 12 bytes
  uint32 version          = 5;   // KEM version, V3.0 = 2 (Sec H-5)
}
```

### A.4 MessageType Enum

Complete list of all MessageTypes in V3.0. They are referenced in the `ApplicationFrame.messageType` field. (NetworkPacket itself has no MessageType — the outer layer carries only routing metadata.)

Grouped by category:

```protobuf
enum MessageType {
  // ── Core Messaging ────────────────────────────────────────
  TEXT                       = 0;
  MEDIA_INLINE               = 1;   // <=256KB, in payload
  MEDIA_ANNOUNCE             = 2;   // Two-Stage Stage 1
  MEDIA_REQUEST              = 3;   // Two-Stage Stage 2 trigger
  MEDIA_CHUNK                = 4;   // Two-Stage Stage 2 data
  MEDIA_COMPLETE             = 5;
  MEDIA_REJECT               = 6;
  REACTION                   = 7;
  REPLY                      = 8;   // metadata in ContentMetadata
  EDIT                       = 9;   // EditMetadata carries original messageId + new content
  DELETE                     = 10;  // soft-delete within 15min window
  TYPING_INDICATOR           = 15;  // ephemeral, no ACK
  READ_RECEIPT               = 16;  // ephemeral, no ACK
  DELIVERY_RECEIPT           = 17;  // ACK for non-ephemeral types
  VOICE_MESSAGE              = 22;  // AAC, with optional transcription

  // ── Recovery & Identity ───────────────────────────────────
  RESTORE_BROADCAST          = 30;  // to all contacts
  RESTORE_RESPONSE           = 31;  // from contact, return
  IDENTITY_DELETED           = 32;
  PROFILE_UPDATE             = 33;
  KEY_ROTATION_BROADCAST     = 34;

  // ── Contact Requests ──────────────────────────────────────
  CONTACT_REQUEST            = 40;
  CONTACT_REQUEST_RESPONSE   = 41;

  // ── Groups (Pairwise Fanout) ──────────────────────────────
  GROUP_CREATE               = 50;
  GROUP_INVITE               = 51;
  GROUP_LEAVE                = 52;
  GROUP_KEY_UPDATE           = 53;

  // ── Channels (Decentralized Public) ───────────────────────
  CHANNEL_CREATE             = 60;
  CHANNEL_POST               = 61;
  CHANNEL_INVITE             = 62;
  CHANNEL_LEAVE              = 63;
  CHANNEL_ROLE_UPDATE        = 64;
  CHANNEL_BAD_BADGE_REPORT   = 65;
  CHANNEL_JURY_VOTE          = 66;
  CHANNEL_MOD_DECISION       = 67;
  CHANNEL_SUBSCRIBE_PROBE    = 68;

  // ── Calls ─────────────────────────────────────────────────
  CALL_INVITE                = 70;
  CALL_ANSWER                = 71;
  CALL_REJECT                = 72;
  CALL_HANGUP                = 73;
  ICE_CANDIDATE              = 74;
  CALL_REJOIN                = 75;

  // Live-Media Frames (skip ML-DSA + zstd; AES-GCM under call_key)
  CALL_AUDIO                 = 76;
  CALL_VIDEO                 = 77;
  CALL_GROUP_AUDIO           = 78;
  CALL_GROUP_VIDEO           = 79;
  CALL_GROUP_LEAVE           = 80;
  CALL_GROUP_KEY_ROTATE      = 81;
  CALL_RTT_PING              = 82;
  CALL_RTT_PONG              = 83;
  CALL_TREE_UPDATE           = 84;

  // ── DHT Operations ────────────────────────────────────────
  PEER_LIST_PUSH             = 100;
  PEER_LIST_SUMMARY          = 101;
  PEER_LIST_WANT             = 102;

  DHT_PING                   = 110;
  DHT_PONG                   = 111;
  DHT_FIND_NODE              = 112;
  DHT_FIND_NODE_RESPONSE     = 113;
  DHT_STORE                  = 114;
  DHT_STORE_RESPONSE         = 115;
  DHT_FIND_VALUE             = 116;
  DHT_FIND_VALUE_RESPONSE    = 117;

  // ── Fragment Storage (Erasure-Coded) ──────────────────────
  FRAGMENT_STORE             = 120;
  FRAGMENT_STORE_ACK         = 121;
  FRAGMENT_RETRIEVE          = 122;
  FRAGMENT_RETRIEVE_RESPONSE = 123;
  FRAGMENT_DELETE            = 124;

  // ── Store-and-Forward on Mutual Peers ─────────────────────
  PEER_STORE                 = 130;
  PEER_STORE_ACK             = 131;
  PEER_RETRIEVE              = 132;
  PEER_RETRIEVE_RESPONSE     = 133;

  // ── Per-Chat Configuration ────────────────────────────────
  CHAT_CONFIG_UPDATE         = 140;
  CHAT_CONFIG_RESPONSE       = 141;

  // ── Routing & Reachability ────────────────────────────────
  ROUTE_UPDATE               = 150;
  REACHABILITY_QUERY         = 151;
  REACHABILITY_RESPONSE      = 152;
  RELAY_FORWARD              = 153;
  RELAY_ACK                  = 154;

  // ── Hole-Punch ────────────────────────────────────────────
  HOLE_PUNCH_REQUEST         = 160;
  HOLE_PUNCH_NOTIFY          = 161;
  HOLE_PUNCH_PING            = 162;
  HOLE_PUNCH_PONG            = 163;

  // ── 2D-DHT Identity Resolution ────────────────────────────
  IDENTITY_AUTH_PUBLISH      = 170;
  IDENTITY_AUTH_RETRIEVE     = 171;
  IDENTITY_AUTH_RESPONSE     = 172;
  IDENTITY_LIVE_PUBLISH      = 173;
  IDENTITY_LIVE_RETRIEVE     = 174;
  IDENTITY_LIVE_RESPONSE     = 175;

  // ── Multi-Device (§7) ─────────────────────────────────────
  TWIN_SYNC                  = 180;   // 12 sub-types via TwinSyncType enum
  DEVICE_PAIR_REQUEST        = 181;
  DEVICE_PAIR_APPROVE        = 182;
  DEVICE_REVOCATION          = 183;

  // ── Calendar (§11.1) ──────────────────────────────────────
  CALENDAR_INVITE            = 190;
  CALENDAR_RSVP              = 191;
  CALENDAR_UPDATE            = 192;
  CALENDAR_DELETE            = 193;
  FREE_BUSY_REQUEST          = 194;
  FREE_BUSY_RESPONSE         = 195;

  // ── Polls (§11.3) ─────────────────────────────────────────
  POLL_CREATE                = 200;
  POLL_VOTE                  = 201;
  POLL_VOTE_ANONYMOUS        = 202;
  POLL_UPDATE                = 203;
  POLL_SNAPSHOT              = 204;
  POLL_REVOKE                = 205;

  // ── In-Call Collaboration (§10.5, planned) ────────────────
  WHITEBOARD_STROKE          = 210;
  WHITEBOARD_PAGE            = 211;
  FILE_EXCHANGE              = 212;
  CLIPBOARD_EXCHANGE         = 213;
  SCREEN_SHARE_FRAME         = 214;
  CALL_CHAT                  = 215;
  REMOTE_CONTROL_INPUT       = 216;
}
```

### A.5 Type-Specific Payload Definitions

A selection of the most important types — for the complete list see `proto/cleona.proto`.

**TextMessage** (for TEXT):
```protobuf
message TextMessage {
  string text         = 1;
  string formatHint   = 2;   // "plain" | "markdown" (V3.0 plain only)
}
```

**MediaInline** (for MEDIA_INLINE, ≤256 KB):
```protobuf
message MediaInline {
  string mimeType     = 1;
  bytes  data         = 2;
  string caption      = 3;
}
```

**MediaAnnounce** (for MEDIA_ANNOUNCE, Stage 1):
```protobuf
message MediaAnnounce {
  bytes  mediaId           = 1;
  string mimeType          = 2;
  uint64 totalSize         = 3;
  uint32 totalChunks       = 4;
  bytes  thumbnailBlob     = 5;   // ≤4 KB
  string caption           = 6;
  uint64 expirySeconds     = 7;
}
```

**ContactRequest** (for CONTACT_REQUEST):
```protobuf
message ContactRequest {
  string displayName       = 1;
  bytes  ed25519Pk         = 2;
  bytes  mlDsaPk           = 3;
  bytes  x25519Pk          = 4;
  bytes  mlKemPk           = 5;
  bytes  profilePictureBlob = 6;   // ≤4 KB
  string greetingMessage   = 7;
}
```

**RelayForward** (for RELAY_FORWARD, carried in the inner frame):
```protobuf
message RelayForward {
  bytes  relayId            = 1;   // 16 bytes random — anti-loop
  bytes  finalRecipientId   = 2;   // = deviceId of final destination
  bytes  wrappedPacket      = 3;   // serialized NetworkPacket of original
  uint32 hopCount           = 4;
  uint32 maxHops            = 5;   // = 3
  uint32 ttl                = 6;
  bytes  originDeviceId     = 7;
  uint64 createdAtMs        = 8;
  repeated bytes visited    = 9;
}
```

**AuthManifest** (for IDENTITY_AUTH_PUBLISH/RESPONSE, §4.3):
```protobuf
message AuthManifestProto {
  bytes           userId               = 1;
  repeated bytes  authorizedDeviceIds  = 2;
  uint64          ttlSeconds           = 3;   // 24h = 86400
  uint64          sequenceNumber       = 4;
  uint64          publishedAtMs        = 5;
  bytes           ed25519Sig           = 6;
  bytes           mlDsaSig             = 7;
  bytes           userEd25519Pk        = 8;   // for verification
  bytes           userMlDsaPk          = 9;
}
```

**LivenessRecord** (for IDENTITY_LIVE_PUBLISH/RESPONSE):
```protobuf
message LivenessRecordProto {
  bytes               userId           = 1;
  bytes               deviceNodeId     = 2;
  repeated PeerAddressProto addresses  = 3;
  uint64              ttlSeconds       = 4;   // 15min or 1h
  uint64              sequenceNumber   = 5;
  uint64              publishedAtMs    = 6;
  bytes               ed25519Sig       = 7;
  bytes               deviceEd25519Pk  = 8;   // Sig is by user-key, not device
}
```

**DeviceKemRecord** (for the third 2D-DHT record class — NEW in V3.0 Welle 5, §3.5b + §4.3):
```protobuf
message DeviceKemRecord {
  bytes  userId            = 1;   // 32 bytes
  bytes  deviceId          = 2;   // 32 bytes
  bytes  deviceX25519Pk    = 3;   // 32 bytes
  bytes  deviceMlKemPk     = 4;   // 1184 bytes (ML-KEM-768 public key)
  uint64 ttlSeconds        = 5;   // 86400 (24h)
  uint64 sequenceNumber    = 6;
  uint64 publishedAtMs     = 7;
  bytes  ed25519Sig        = 8;   // signed by user master Ed25519 key
  bytes  userEd25519Pk     = 9;   // for in-place verify
}
// Storage key: SHA-256("kem" || userId || deviceId)
// Lifecycle: 24h TTL, refreshed every 20h by IdentityPublisher (parallel to AuthManifest).
// Deliberately separated from LivenessRecord because Device-KEM-PK changes only at
// device-key-reset (multi-year cadence) while Liveness flips every 15 min.
```

**PeerListEntry** (for PEER_LIST_PUSH):
```protobuf
message PeerListEntry {
  bytes               deviceId           = 1;
  repeated PeerAddressProto addresses    = 2;
  uint64              lastSeenMs         = 3;
  uint64              ageHours           = 4;   // routing-table-age hint
  ConnectionType      connectionType     = 5;
}
```

**PeerAddressProto**:
```protobuf
message PeerAddressProto {
  string      ip          = 1;
  uint32      port        = 2;
  AddressType addressType = 3;
}

enum AddressType {
  IPV4_PRIVATE = 0;   // RFC 1918
  IPV4_PUBLIC  = 1;
  IPV6_GLOBAL  = 2;
  IPV6_LINK    = 3;   // fe80::/10
  IPV6_SITE    = 4;   // fec0::/10 (legacy)
  IPV6_ULA     = 5;   // fc00::/7
}
```

**ProofOfWork**:
```protobuf
message ProofOfWork {
  bytes  hash       = 1;   // SHA-256 of payload + nonce
  uint64 nonce      = 2;
  uint32 difficulty = 3;
}
```

**EditMetadata** (for EDIT):
```protobuf
message EditMetadata {
  bytes  originalMessageId  = 1;
  uint64 originalTimestamp  = 2;
  uint64 editTimestamp      = 3;
  bytes  newPayload         = 4;
}
```

**ContentMetadata** (for REPLY, quotes, attachments):
```protobuf
message ContentMetadata {
  bytes  replyToMessageId   = 1;
  string replyExcerpt       = 2;   // first ~100 chars for display
  repeated bytes attachmentMessageIds = 3;
}
```

**ErasureCodingMetadata** (for FRAGMENT_*):
```protobuf
message ErasureCodingMetadata {
  bytes  messageId         = 1;
  uint32 fragmentIndex     = 2;
  uint32 totalFragments    = 3;   // = 10 (N)
  uint32 minFragments      = 4;   // = 7 (K)
  bytes  fragmentData      = 5;
}
```

### A.6 Ephemeral Frames

The following MessageTypes are "ephemeral" — no DELIVERY_RECEIPT, no S&F backup, no re-send on failure:

- TYPING_INDICATOR
- READ_RECEIPT
- DELIVERY_RECEIPT (ephemeral itself — otherwise an endless loop)
- HOLE_PUNCH_*
- DHT_PING / DHT_PONG
- CALL_RTT_PING / CALL_RTT_PONG
- CALL_AUDIO / CALL_VIDEO / CALL_GROUP_* (live media: on loss → skip frame, no retry)
- ROUTE_UPDATE (re-updates arrive via the DV logic itself)
- IDENTITY_*_RESPONSE (responses are per-request, not persistent)

### A.7 Wire-Format Versioning

V3.0 uses `version=1` in NetworkPacket and ApplicationFrame. PerMessageKem uses `version=2` (Sec H-5 v2).

**Future bumps**:
- NetworkPacket.version=2 → would, for instance, introduce a new top-level field (Onion activation could happen without a bump because the PayloadType discriminator is already in place).
- ApplicationFrame.version=2 → e.g. new signature algorithms or new metadata fields.
- PerMessageKem.version=3 → e.g. switching to a new KEM algorithm.

**Interop policy** for wire-version mismatch: silent drop. No bounce-backs, no version negotiation. If versions are incompatible → the update-manifest hard-block (§19.5.7) forces a user update.

---

## Appendix B. Frame Examples (Hex Dumps)

Concrete wire-format examples from the V3.0 layered-frame stack. All hex values are illustrative — sigs/HMACs/KEM ciphertexts are abbreviated with `...` because they differ on every send.

### B.1 Simple TEXT Message (Direct, No Relay)

**Context**: Alice (daemon device `0xa5fa07...`) sends "Hallo" to Bob (user `0x677af2...`, one device `0xf52b81...`).

**ApplicationFrame (Inner, before KEM encryption)**:

```
field 1 (version)          = 1
field 2 (recipientUserId)  = 677af2c0 ... (32 bytes)
field 3 (senderUserId)     = a1b2c3d4 ... (32 bytes — Alice)
field 4 (timestampMs)      = 1714555200000
field 5 (messageId)        = 16 random bytes
field 6 (messageType)      = TEXT (0)
field 7 (payload)          = TextMessage { text="Hallo", formatHint="plain" }
                             ≈ 12 bytes after protobuf-encoding
field 10 (userEd25519Sig)  = 64 bytes  (Alice User-Ed25519 sig over fields 1-7)
field 11 (userMlDsaSig)    = 3293 bytes (Alice User-ML-DSA-65 sig)
```

Serialized size ≈ 3450 bytes.

**After zstd compression** (effective on structured protobuf bytes): ≈ 3380 bytes.

**After KEM encryption** (PerMessageKem wrapper):

```
PerMessageKem {
  x25519Ciphertext  = 32 bytes (X25519 encap to Bob's X25519 pubkey)
  mlKemCiphertext   = 1088 bytes (ML-KEM-768 encap)
  aeadCiphertext    = 3380 bytes (zstd'd ApplicationFrame) + 16 bytes Poly1305 tag
  aeadNonce         = 12 bytes
  version           = 2
}
```

Serialized size ≈ 4538 bytes — this is `NetworkPacket.payload`.

**NetworkPacket (Outer)**:

```
field 1 (version)              = 1
field 2 (flags)                = 0
field 3 (nextHopDeviceId)      = f52b8135 ... (32 bytes — Bob's device, direct)
field 4 (senderDeviceId)       = a5fa0794 ... (32 bytes — Alice's device)
field 5 (timestampMs)          = 1714555200042
field 6 (ttl)                  = 64
field 7 (hopCount)             = 0
field 8 (networkTag)           = 16 bytes HMAC-SHA256-128
field 9 (pow)                  = 0 bytes (LAN-peer, PoW skipped)
field 10 (deviceEd25519Sig)    = 64 bytes (Alice's device Ed25519 sig)
field 11 (deviceMlDsaSig)      = 3293 bytes (Alice's device ML-DSA-65 sig)
field 12 (payloadType)         = APPLICATION_FRAME (0)
field 13 (payload)             = 4538 bytes (PerMessageKem)
```

Total wire size ≈ **8090 bytes** (≈ 7.9 KB).

**Breakdown**:
| Component | Bytes | % |
|---|---|---|
| Inner application payload | 12 | 0.1% |
| User sig (inner) | 3357 (Ed25519+ML-DSA) | 41.5% |
| KEM setup (inner KEM wrapper) | 1136 | 14.0% |
| Device sig (outer) | 3357 (Ed25519+ML-DSA) | 41.5% |
| Outer header | 228 | 2.8% |

The ML-DSA sigs (user + device, hybrid) account for 83% of the wire size for a short text message. That is the price for post-quantum security at the application layer.

### B.2 Live Call Audio Frame (Onion-Taboo, Optimized)

**Context**: Alice sends a 20 ms Opus audio frame to Bob during a live call.

**Live-media optimizations**:
- KEM replaced by `call_key` AES-GCM (per-session ephemeral)
- zstd skipped (audio is already compressed)
- Inner sig skipped (frame authenticity comes from the AES-GCM tag)
- Device sig is Ed25519 only (no ML-DSA — latency + bandwidth)

**ApplicationFrame** (simplified for live media):
```
recipientUserId = bob.userId
senderUserId    = alice.userId
messageType     = CALL_AUDIO (76)
payload         = AES-GCM(call_key, opus_frame_bytes) + 16-byte Tag
                ≈ Opus-Frame (24-160 bytes) + 16 = 40-176 bytes
```

Serialized size ≈ 90-220 bytes.

**NetworkPacket (Outer)**:
```
nextHopDeviceId   = bob.deviceId (direct)
senderDeviceId    = alice.deviceId
ttl, hopCount, networkTag, pow=0 (Live), payloadType=APPLICATION_FRAME
deviceEd25519Sig  = 64 bytes
deviceMlDsaSig    = 0 bytes (Infrastructure-style, Live-Media exempt)
```

Total wire size for an audio frame ≈ **400-540 bytes** — on average ~470 bytes per 20 ms frame.

**Bandwidth per audio stream**: 50 frames/s × 470 bytes = ~23 KB/s per direction. For comparison, hybrid sigs would add ~20 KB per frame = ~1 MB/s. Unacceptable — hence the selectivity (§3.5).

### B.3 IDENTITY_AUTH_PUBLISH (DHT Replicator Replication)

**Context**: Alice publishes her auth manifest to one of the K=10 closest replicators (e.g. `0xc8b73e...`).

**ApplicationFrame** (no KEM because records are self-validating):
```
recipientUserId   = c8b73e... (replicator user ID — actually a replicator device, but the format reuses the user ID slot)
senderUserId      = alice.userId
messageType       = IDENTITY_AUTH_PUBLISH (170)
payload           = AuthManifestProto {
                      userId = alice.userId,
                      authorizedDeviceIds = [alice.device1, alice.device2],
                      ttlSeconds = 86400,
                      sequenceNumber = 17,
                      publishedAtMs = 1714555200000,
                      ed25519Sig = 64 bytes,
                      mlDsaSig = 3293 bytes,
                      userEd25519Pk = 32 bytes,
                      userMlDsaPk = 1952 bytes
                    }
                  ≈ 5400 bytes
userEd25519Sig    = 64 bytes
userMlDsaSig      = 3293 bytes
```

Serialized inner ≈ 8800 bytes. Because of DHT-infrastructure status: no KEM, the payload goes straight into the outer frame.

**NetworkPacket (Outer)**:
```
nextHopDeviceId   = c8b73e... (replicator device)
deviceEd25519Sig  = 64 bytes
deviceMlDsaSig    = 0 bytes (Infrastructure exempt)
payloadType       = APPLICATION_FRAME
payload           = 8800 bytes (serialized ApplicationFrame, no KEM wrap)
```

Total ≈ **9100 bytes**. Per auth-manifest refresh (every 20 h) × K=10 replicators = 91 KB per refresh cycle per user identity. Acceptable.

### B.4 RELAY_FORWARD (Multi-Hop Relay)

**Context**: Alice's NetworkPacket to Bob (B.1 above, 8090 bytes) has to traverse relay Carol (`0x6c39f8...`) because the direct path fails.

**Outer NetworkPacket** (Alice → Carol):
```
nextHopDeviceId   = 6c39f8... (Carol)
senderDeviceId    = a5fa07... (Alice)
deviceEd25519Sig  = 64 bytes
deviceMlDsaSig    = 3293 bytes (Application-Frame style)
payloadType       = APPLICATION_FRAME
payload           = ApplicationFrame {
                      messageType = RELAY_FORWARD (153)
                      senderUserId = alice
                      recipientUserId = bob
                      payload = RelayForward {
                                  relayId = 16 random,
                                  finalRecipientId = bob.deviceId (32 bytes),
                                  wrappedPacket = Alice's ORIGINAL NetworkPacket from B.1 (8090 bytes),
                                  hopCount = 1,
                                  maxHops = 3,
                                  ttl = 64,
                                  originDeviceId = alice.device,
                                  visited = [alice.device]
                                }
                                ≈ 8200 bytes
                      userEd25519Sig = 64 bytes (Alice signs the relay-frame)
                      userMlDsaSig = 3293 bytes
                    }
                  ≈ 11600 bytes after KEM encryption for Carol
```

Total wire size for relay hop 1 ≈ **15 KB**. At 3 hops the total would be similar (each hop only unwraps and rewraps, adding its own outer sig, but the `wrappedPacket` stays the same).

**Observation**: Relay frames are expensive because of the doubled signature layers (Alice user sig in the inner frame + Alice device sig in the outer frame + Carol device sig when she forwards). That is an architectural cost — the trade-off for a clean trust boundary.

### B.5 Size Budget for Typical Messages

| Message | Inner | KEM wrap | Outer header+sig | Total wire |
|---|---|---|---|---|
| Text "Hallo" (direct) | 3450 | 4538 | 3585 | ~8.1 KB |
| Reaction (👍, direct) | 3380 | 4470 | 3585 | ~7.8 KB |
| 256 KB image (inline, direct) | ~263 KB | ~264 KB | 3585 | ~265 KB |
| Audio frame live (20 ms, direct) | 90-220 | n/a (call_key AES) | 290 | 0.4-0.5 KB |
| Auth-manifest publish (infrastructure) | 8800 | n/a | 290 | 9.1 KB |
| Liveness-record publish (infrastructure) | 200-500 | n/a | 290 | 0.5-0.8 KB |
| RELAY_FORWARD wrapped text (1 hop) | 11600 | 12700 | 3585 | ~16 KB |

**Optimization headroom**:
- ML-DSA sigs are dominant — no savings without loss of security.
- KEM setup is ~1.1 KB constant — no headroom.
- Outer header (228 bytes) is minimal.
- Compression helps most with large payloads (e.g. a 256 KB image can shrink to ~230 KB if it is not already compressed).

---

## Appendix C. V2.2 → V3.0 Section Cross-Walk

Complete sub-section cross-walk table, derived from `docs/V3_MIGRATION_MAP.md`. Use it to find every v2.2 statement again in the v3.0 spec. Use Ctrl-F on the v2.2 § number.

| v2.2 § | v2.2 title | Status | v3.0 § |
|---|---|---|---|
| 1.1 | Core Principles | REWRITE | 1.1 |
| 1.2 | Unique Innovations | REWRITE | 1.2 |
| 2.1 | Communication Port | PORT | 4.1 |
| 2.2 | Distributed Hash Table (intro) | PORT | 4.2 |
| 2.2.1 | Node Identity | REWRITE | 3.1 + 3.5 |
| 2.2.2 | Virtual Mailbox | PORT | 5.6 |
| 2.2.3 | Routing Table (DV V3) | REWRITE | 4.4 |
| 2.2.3.1 | User×Device dedup ADR | PORT | 7.1 |
| 2.2.4 | Identity Resolution (2D-DHT) | REWRITE | 4.3 |
| 2.3 | Mesh Discovery | PORT | 4.5 |
| 2.3.1-2.3.6 | Mesh Discovery Subs | PORT | 4.5.1-4.5.6 |
| 2.4 | NAT Traversal & Reachability | PORT | 4.6 |
| 2.4.1-2.4.2 | NAT Subs | PORT | 4.6.1-4.6.2 |
| 2.4.3 | Route-Based Delivery | REWRITE | 4.4 |
| 2.4.4 / 4a | Connection Order + Address Priority | PORT | 4.6.3 / 4.6.3a |
| 2.4.4b | Relay Route Learning | REWRITE | 5.3 |
| 2.4.5 | IPv6 Advantage | PORT | 4.7 |
| 2.4.6 | Active UDP Hole Punch | PORT | 4.6.4 |
| 2.5 | Bootstrap Node + Subs | PORT | 4.8 + 4.8.x |
| 2.6 | Complete Discovery Chain | PORT | 4.5.7 |
| 2.7 / 2.7.x | Network Change Detection | PORT | 4.9 / 4.9.x |
| 2.8 | Data Compression | PORT | 5.9 |
| 2.9 / 2.9.1-4 / 2.9.6-10 | RUDP | PORT | 5.8 / 5.8.x |
| 2.9.5 | SendQueue (MessageQueue) | DROP | — (S&F + mailbox take over) |
| 3.1 / 3.2 | Erasure Coding | PORT | 5.4 |
| 3.3 | Message Flow | REWRITE | 5.1 |
| 3.3.1 | Three-Layer Delivery | REWRITE | 5.1 |
| 3.3.2 | Recipient Online | REWRITE | 5.2 |
| 3.3.3 | Recipient Offline | REWRITE | 5.4 + 5.5 |
| 3.3.4 | Message Deduplication | PORT | 5.7 |
| 3.3.5 / 5a / 6 | Mailbox & PK Lookup | PORT | 5.6 |
| 3.3.7 | S&F on Mutual Peers | REWRITE | 5.5 |
| 3.4 / 3.4.1-3 | Two-Stage Media | PORT | 5.7 / 5.7.x |
| 3.5 | Relay Storage Management | PORT | 5.5.x |
| 4.1 / 4.2 | Crypto Philosophy + Primitives | PORT/REWRITE | 3.2 |
| 4.3 / 4.3.1-7 | Per-Message KEM | REWRITE/PORT | 3.3 |
| 4.4 / 4.4.1-6 | Call Encryption | PORT | 10.x |
| 4.5 | Group Encryption | REWRITE | 9.1.x |
| 4.6 | Encryption Order | REWRITE | 2.4 |
| 4.7 / 4.7.x | Database Encryption | PORT | 3.8 |
| 5.1 | Identity Model | REWRITE | 3.1 |
| 5.2 / 5.2.x | Multi-Identity | REWRITE | 3.6 |
| 5.3 | Profile Pictures | PORT | 8.3 |
| 5.4 | Key Storage | REWRITE | 3.7 |
| 5.5 | Contact Verification | PORT | 3.9 |
| 5.6 | Contact Request Protocol | REWRITE | 8.1 |
| 5.6.1 / 5.6.2 | Anti-Spam + KEX Gate | PORT | 8.2 |
| 6.1 | Recovery Phrase | PORT | 6.1 |
| 6.2 | Social Recovery (Shamir) | PORT | 6.2 |
| 6.3 / 6.3.1-5 | Restore Broadcast | REWRITE/PORT | 6.3 / 6.3.x |
| 6.4 / 6.4.1-3 | DHT Identity Registry | PORT | 6.4 / 6.4.x |
| 7.1-7.5 | Sync Strategy + Background Timers | PORT | 12.1 / 12.2.x |
| 7.6 | Network Change Recovery | PORT | 12.3 |
| 7.7 | Platform-Specific Background | PORT | 12.5 |
| 7.8 | Push Wake-Up Rejected (ADR) | PORT | 12.4 |
| 8.1-8.6 | App Permissions | PORT | 16.1-16.6 |
| 9.1-9.6 | DoS Protection (5 Layer) | PORT | 13.1.2-13.1.7 |
| 10.1-10.3 | Private Channels | PORT | 9.1.x |
| 10.4 / 10.4.1-3 | Public Channels | PORT | 9.2.x |
| 10.4.4-6 | Decentralized Moderation | PORT | 9.3.1-9.3.3 |
| 10.4.7-8 | Anti-Sybil + ModerationConfig | PORT | 9.4.1 / 9.4.2 |
| 10.7 | Moderation Timer | PORT | 9.3.4 |
| 11.1-11.6 | Network Statistics | REWRITE | 18.1-18.6 |
| 12.1-12.6 | Tech Stack | PORT | 20.1-20.6 |
| 13.1-13.5 | i18n | PORT | 17.1-17.5 |
| 14.1-14.9 | Feature Roadmap | REWRITE | 24 |
| 15.1 | Storage Priorities | PORT | 14.1 |
| 15.1.x | Identity-Resolution Storage | REWRITE | 14.2 |
| 15.2-15.6 | Storage + Per-Chat Config | PORT | 14.3-14.7 |
| 15.7 / 15.7.x | Media Auto-Archive | PORT | 14.8 / 14.8.x |
| 15.8 / 15.8.x | Voice Transcription | PORT | 14.9 / 14.9.x |
| 16.1 / 16.1.1 | Source Available + Publishing | PORT | 19.1 / 19.2 |
| 16.2-16.4 | Brand + Funding + Donation | PORT | 19.3-19.5 |
| 16.4.1-7 | Donation/Update Subs | PORT | 19.5.x |
| 17.1-17.3 / 17.4 | Security Considerations + Audit | PORT | 13.x |
| 17.5 / 17.5.1-3 | Closed Network Model | REWRITE/PORT | 4.10 |
| 17.5.4 | Packet-Level Authentication | REWRITE | 2.4 + 4.10 |
| 17.5.5 | Secret Rotation | REWRITE | 13.2 |
| 17.5.6-7 | Obfuscation + Defense-in-Depth | PORT | 4.10 |
| 18.1 / 18.1.1 | Service+GUI + Six-Layer Model | REWRITE | 15.1 |
| 18.2 | Platform-Specific Behavior | PORT | 15.2 |
| 18.3 | Bootstrap Headless | PORT | 4.8 |
| 18.4 / 18.5 | Service Layer Architecture | REWRITE | 15.3 |
| 18.6 / 18.6.x | UI Message Chain | PORT | 15.4 |
| 18.7 | Clipboard Integration | PORT | 15.7 |
| 18.8 / 18.8.x | Notifications | PORT | 15.5 |
| 19.1-19.9 | Testing | PORT | 21.x (+ 21.4 NEW) |
| 20.1-20.5 | Linux Dev Environment | PORT | 22.1.x |
| 21.1-21.8 | VM Test Infrastructure | PORT | 22.2.x |
| 22.1-22.4 | Development Plan | REWRITE | 24 |
| 23.1-23.11 | Calendar (all subs) | PORT | 11.1.x + 11.2.x |
| 24.1-24.9 | Polls (all subs) | PORT | 11.3.x + 11.4.x |
| 25.1-25.7 | In-Call Collaboration | PORT | 10.5.x |
| 26.1 | Multi-Device Design | PORT | 7 (intro) |
| 26.2.1-3 | Device Identity & Pairing | REWRITE/PORT | 7.1 |
| 26.3 / 26.3.x | Twin-Sync Protocol | PORT | 7.2 |
| 26.4 | Delivery to Multiple Devices | REWRITE | 7.3 |
| 26.5-26.9 | Multi-Device Mgmt + Presence | PORT | 7.4 |
| 27.1-27.10 | IPv6 Dual-Stack & CGNAT | PORT | 4.7 |
| 27.10 | Doze-Whitelisting (Retired) | DROP | — |
| 28 | Appendix Protocol Format | REWRITE | Appendix A |

**Completely DROP** (no longer present in v3.0):
- §2.9.5 SendQueue / MessageQueue — sender-side retry mechanism. S&F + mailbox-pull take over. See §1.2 highlight #4.
- §27.10 Doze-Whitelisting Opt-out — already marked retired in v2.2.

**NEW v3.0 sections without a v2.2 counterpart**:
- §1.2 V3.0 Architecture Highlights
- §2 Wire-Format & Layered Frames (complete, 6 subs)
- §2.5 Onion-Routing Hook (format preparation)
- §3.5 Device Identity Sigs
- §4.3 Identity Resolution (REWRITE — structurally separated as a pre-send step)
- §13.3 Service Layer Resilience
- §15.3 Service Layer API (sendToUser/sendToDevice)
- §21.4 V3.0 Migration Tests
- §23 V2.2 → V3.0 Migration (entire chapter)
- Appendix B: Frame Examples (Hex Dumps)
- Appendix C: V2.2 → V3.0 Section Cross-Walk (this chapter)
