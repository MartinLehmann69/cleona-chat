# CLEONA CHAT

## Architecture & Technical Specification — v3.0

**Status:** v3.0 Major Architecture Refactor (2026-05-01+)
**Predecessor:** v2.2 (archived, see git history)

**v3.0 key features:**
- **2-layer wire format**: Outer Frame (routing, device-signed) wraps Inner Frame (identity, KEM-encrypted)
- **Clear API separation**: `service.sendToUser(userId)` for identity addressing, `node.sendToDevice(deviceId)` for pure routing
- **Privacy improvement**: relays no longer see UserIDs — only device-to-device topology

<!-- AUTO-GENERATED from Cleona_Chat_Architecture_v3_0.md (sha256:1b857c394868, 2026-07-09). -->
<!-- Edits to this file will be overwritten. Edit the master in Cleona/. -->

- **Default-Gateway resilience**: re-enabled as a routing-layer fallback when the DV routing table does not know the target device
- **MessageQueue retired**: when "routes exhausted" the sender stops; S&F + mailbox pull take over offline delivery
- **Onion-routing hook**: Outer-Frame format prepared for later multi-layer encryption, not active in V3.0
- **Hard cut**: wire format and profile format incompatible with v2.2 (migration completed May 2026)

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
9. Group Features
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
23. Roadmap
24. Platform Suitability

Appendix A. Protocol Message Format
Appendix B. Frame Examples (Hex Dumps)

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

**4. MessageQueue retired** (§5.5, §5.6). v2.2 held failed sends for 7 days in a local MessageQueue and retried periodically — often with the same (potentially wrong) ID that had already failed on the first attempt. V3.0 removes the MessageQueue entirely: when "all routes exhausted" the sender stops, S&F (on contact peers, §5.5) plus mailbox pull (the receiver pulls upon coming online) take over offline delivery. There is no longer any sender-side retry.

**5. Onion-routing hook prepared, not active** (§2.5). The Outer-Frame format has a `payloadType` discriminator: `payload` can be an ApplicationFrame (V3.0 default) or a nested NetworkPacket (onion layer). This makes multi-hop onion routing activatable in a later version **without another hard break**. V3.0 implements only 1 hop. When activation occurs later, a taboo list is firmly planned: live calls, DHT infrastructure, hole punch, routing updates must never traverse onion layers — latency and functionality forbid it.

**6. Device-Sig keypair as its own crypto-subject class** (§3.5). User identities have user-sig keys (Ed25519+ML-DSA-65 hybrid). In addition, every device has its own sig keypair (Ed25519+ML-DSA-65 hybrid for application frames, Ed25519-only for infrastructure frames to conserve bandwidth). This allows outer signatures to be device-attributed without leaking UserID information.

**7. Layered encryption pipeline** (§2.4). A precisely prescribed order on the sender and receiver side: Serialize → Sign Inner → Compress → KEM-Encrypt → Wrap Outer → Sign Outer → HMAC → PoW. The receiver mirrors the steps. Failure modes at every stage are documented (silent drop), no bounce-back, in order to avoid information leaks. This pipeline replaces the less formalized encryption-order block from v2.2 §4.6.

**8. Profile reset on upgrade.** Because of wire-format incompatibility and new sig keypairs, v2.2 profiles must be created from scratch when v3.0 is brought up. Restore Broadcast permits recovery of an identity (recovery phrase or contacts), but local conversations are lost. This is an acceptable cut: v3.0 is a beta-grade build, no productive data set needs to be migrated.

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

enum PayloadType {                  // proto: PayloadTypeV3, on-wire values PAYLOAD_*-prefixed
  APPLICATION_FRAME              = 0; // payload = ApplicationFrame (Identity layer)
  ONION_LAYER                    = 1; // payload = nested NetworkPacket (onion layer — V3.0 not active, §2.5)
  INFRASTRUCTURE_FRAME           = 2; // device-targeted InfrastructureFrame, KEM-encrypted (§2.3.5)
  BOOTSTRAP_INFRASTRUCTURE_FRAME = 3; // BOOT-path InfrastructureFrame (§2.3.5 / §2.4.1a)
}
// Unknown/future payloadType → silent drop (forward-only). This is the single
// canonical numbering; it matches the proto enum and Appendix A.1.
```

**Field explanation:**

- **`version`**: V3.0 sets `1`. Prevents replay/mismatch between v2.2 nodes (which do not know NetworkPacket — wire reject) and v3.0 nodes.
- **`flags`**: Reserved for future extensions (e.g. EXPRESS for latency-critical frames, NEEDS_PADDING for anti-traffic-analysis padding). V3.0: typically `0`.
- **`nextHopDeviceId`**: SHA-256(network_secret + device_pubkey_ed25519) — the canonical device ID. The receiver of this physical UDP packet checks: is `nextHopDeviceId == myDeviceId`? If yes → unwrap. If no → I am a relay → forward toward `nextHopDeviceId`.
- **`senderDeviceId`**: For the reverse path (e.g. routing DELIVERY_RECEIPT back) and for sig-verify (relay fetches the sender device pubkey from DHT/RoutingTable).
- **`timestampMs`**: Replay window. Frames older than 60s are discarded. Within the window, byte-identical replays are caught by the duplicate-frame cache (§2.4 step [3b]). Closed-network nodes keep their clocks synchronized via NTP/Bootstrap.
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
  bytes  aeadCiphertext     = 3;   // AES-256-GCM(serialized ApplicationFrame)
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
| S&F on contact peers (§5.5) | PEER_STORE, PEER_STORE_ACK, PEER_RETRIEVE, PEER_RETRIEVE_RESPONSE | KEM |
| Peer-list gossip | PEER_LIST_PUSH, PEER_LIST_SUMMARY, PEER_LIST_WANT, PEER_KEY_REQUEST, PEER_KEY_RESPONSE | **BOOT** |
| Routing — DV updates | ROUTE_UPDATE | **BOOT** |
| Reachability probes | REACHABILITY_QUERY, REACHABILITY_RESPONSE | **BOOT** |
| Relay forwarding | RELAY_FORWARD, RELAY_ACK | KEM |
| NAT/hole-punch | HOLE_PUNCH_REQUEST, HOLE_PUNCH_NOTIFY, HOLE_PUNCH_PING, HOLE_PUNCH_PONG | **BOOT** |
| Delivery ACK | DELIVERY_RECEIPT (when targeting senderDeviceId without UserID context) | KEM |
| Identity-Layer Infrastructure (Welle 6) | RESTORE_BROADCAST, KEY_ROTATION_BROADCAST (Emergency-variant only — when both `oldSignatureEd25519` and `newSignatureEd25519` are set in the body) | KEM |
| Deferred Key Exchange (rev3) | DEVICE_KEM_REQUEST, DEVICE_KEM_OFFER | **BOOT** |
| First-CR-Mailbox (rev3) | FIRST_CR_STORE, FIRST_CR_STORE_ACK, FIRST_CR_DELIVER | **BOOT** |
| System-Channel record gossip (§9.5.7) | SYSCHAN_DIGEST, SYSCHAN_SUMMARY, SYSCHAN_WANT, SYSCHAN_PUSH | **BOOT** |

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
  [10] Compute PoW                (skip if recipient is LAN-peer, Infrastructure-Frame, or live-media frame — §10.3/§13.1.2 #4)
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
  [3b] Duplicate-frame check (replay dedup)
          │   → key: networkTag — the HMAC covers the full packet incl.
          │     timestampMs, so a byte-identical replay maps to the identical tag
          │   → LRU cache, TTL 120s (= 2× timestamp window), capacity-capped
          │     (8192 entries); purely local, zero network traffic
          │   → if seen: drop silently (replay of an HMAC-valid frame —
          │     closes replay of BOOT-RPCs, HOLE_PUNCH_*, DHT_PING/PONG,
          │     DELIVERY_RECEIPT and call frames inside the 60s window)
          │   → no false positives: relay re-wraps (ttl-1) produce a new
          │     networkTag (multi-path duplicates unaffected); sender-rebuilt
          │     retransmits carry a fresh timestampMs → fresh tag
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
  [5] Verify PoW                  (skip if Infrastructure-Frame, if from LAN/relay, or if senderDeviceId is on the live-media allowlist of an active call — §13.1.2 #4)
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
  [10] AEAD-Decrypt aeadCiphertext  (AES-256-GCM)
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
  [10'] AEAD-Decrypt aeadCiphertext  (AES-256-GCM)
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
| messageType outside §2.3.5 selector | Cross-layer abuse attempt | Drop; reputation hit only if the outer device-sig verified for this packet (§13.1.4 attribution precondition) |
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
| messageType outside BOOT-subset | Cross-layer abuse attempt (KEM-required type promoted to BOOT) | Drop; reputation hit only if the outer device-sig verified for this packet (§13.1.4 attribution precondition) |
| recipientDeviceId mismatch | Misdelivery | Drop |
| Inner-record sig verify (PUBLISH) | Forged record under fake user identity | Drop, **no** reputation hit — a poisoned record's delivering device is usually an innocent DHT server, and the forged identity has no valid sig to attribute to (§13.1.4) |
| Outer HMAC fails | Forged Closed-Network membership | Silent drop (already at §2.4 step 1) |

**Wire-format change**: `NetworkPacket.payloadType` carries `BOOTSTRAP_INFRASTRUCTURE_FRAME = 3`, completing the canonical enum `APPLICATION_FRAME = 0`, `ONION_LAYER = 1`, `INFRASTRUCTURE_FRAME = 2`, `BOOTSTRAP_INFRASTRUCTURE_FRAME = 3` (identical to the proto enum and §2.2 / Appendix A.1). No existing fields move; older receivers drop the unknown enum value silently — forward-only behaviour.

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
                 │      ├─ try cheapest route, max 3 retries (ACK timeout 0.5-2s direct RTT-based, 8s relay)
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

The old v2.2 API `node.sendEnvelope(envelope, recipientNodeId)` with its overloaded, type-undifferentiated identifier parameter no longer exists in V3.0. All call sites have been migrated (see §15.3 Service Layer API).

---
## 3. Identity & Cryptography

Cleona identities are cryptographic keypairs — without email, phone number, or central verification. V3.0 explicitly separates two identity classes that were often mixed in v2.2: **UserID** (stable cross-device identity, what the app UI presents to a user as a "contact") and **DeviceID** (physical hosting of an identity on a concrete device, what the mesh routing requires). Each has its own Sig-Keypair, its own crypto responsibilities, and its own lifecycle.

This separation is the cryptographic foundation of the 2-Layer wire format from §2: Outer-Frames are Device-signed (routing authenticity), Inner-Frames are User-signed (identity authenticity).

### 3.1 Identity Model (UserID vs DeviceID)

**UserID** (or "User Identity") represents a person, i.e. a logical identity that the UI maps to a contact. A UserID can be hosted on multiple devices (Multi-Device, §7), and a single daemon can host multiple UserIDs concurrently (Multi-Identity, §3.6).

```
userId = SHA-256(network_secret || ed25519_user_pubkey)    // 32 bytes, founding derivation
```

The formula above is the **founding** derivation, computed once at identity creation. The UserID is thereafter a **stable anchor**: it is pinned to the founding Ed25519 pubkey and does **not** change when the underlying user keys change. Emergency Key Rotation (§7.4b / §26.6.2) replaces all user keys but preserves the UserID by carrying a dual-signed old→new key-continuity proof that contacts follow — so after a rotation `userId` no longer equals `SHA-256(network_secret || current_pubkey)`. Onboarding a *new* contact to a rotated identity via ContactSeed is handled by the optional `fp` (founding-pubkey) seed field (§8.1.1, SR-2): the seed's integrity check anchors on the founding key (`SHA-256(secret || fp) == userId`); the binding founding→current `ep` is proven by the rotation chain inside the D1-verified Auth-Manifest at first resolution (§4.3 path 2).

UserID properties:
- **Stable anchor**: persists across device changes, recovery, Multi-Device additions, **and Emergency Key Rotation** — the identifier outlives any individual key
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
- The historical v2.2 term "nodeId" is **avoided** in v3.0 because it carried both meanings, which is exactly how the v2.2 ID-Mismatch bug arose. All `nodeId` sites have been renamed to either `userId` or `deviceId`.

### 3.2 Cryptographic Primitives

Cleona uses exclusively audited, established primitives from two C libraries via FFI:

| Library | Primitives | Use |
|---|---|---|
| **libsodium** (1.0.20+) | Ed25519, X25519, AES-256-GCM, XSalsa20-Poly1305, BLAKE2b, SHA-256, HMAC-SHA-256, HKDF | Classical crypto + DB-Encryption |
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
- **No AES-CBC, AES-CTR**. AES-256-GCM is AEAD, integrates the MAC, and has hardware acceleration on all target platforms (AES-NI on x86, ARMv8 Cryptography Extensions on modern ARM). Early designs considered ChaCha20-Poly1305 for ARM without AES-NI, but all current Android/iOS devices ship with ARMv8-CE, making AES-GCM the faster choice.

### 3.3 Per-Message KEM (X25519+ML-KEM-768 hybrid v2)

Cleona's E2E encryption mechanism. Every application message carries its own ephemeral key setup — no session state, no desync risk.

**Hybrid KEM = X25519 + ML-KEM-768 combined**:
- Sender generates an ephemeral X25519 keypair
- Sender encapsulates against the recipient's X25519 pubkey → `x25519_ct` (32 bytes) + `x25519_shared` (32 bytes)
- Sender encapsulates against the recipient's ML-KEM-768 pubkey → `mlkem_ct` (1088 bytes) + `mlkem_shared` (32 bytes)
- Combined key: `combined = HKDF-SHA-256(x25519_shared || mlkem_shared, salt, info)`
- AEAD encrypt: `aead_ct = AES-256-GCM(combined, nonce, plaintext)`

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

#### 3.3.5 PQ Key Recovery — Security Analysis

All four user-key pairs — Ed25519, ML-DSA-65, X25519, ML-KEM-768 — are deterministically derived from the master seed (§3.6). For the post-quantum pair this uses FIPS 203 (ML-KEM) and FIPS 204 (ML-DSA) deterministic key-generation: a per-key 32/64-byte seed obtained via HKDF from the master seed is fed to `OQS_KEM_keypair_derand` / `OQS_SIG_keypair_derand` (liboqs ≥ 0.15.0). The same master seed therefore always reproduces the identical PQ keypair.

**Recovery property.** After device loss, the replacement device regenerates the exact same User-KEM keypair from the recovery phrase and can decrypt every previously received Per-Message-KEM ciphertext (the messages themselves are re-delivered by contacts via Restore Broadcast, §6.3). No PQ key material has to be backed up out of band, and a seed recovery requires no key re-publication.

**No downgrade.** There is no X25519-only decryption mode. The hybrid combiner always requires both the X25519 and the ML-KEM shared secret (§3.3); a recipient never falls back to classical-only, so neither a sender nor an on-path attacker can force a PQ downgrade by feigning a recovery or a transition window.

**Forward-secrecy trade-off (accepted).** The flip side of seed-derivable keys is that the master seed is a permanent root secret: anyone who obtains the 24-word phrase (or a 3-of-5 guardian quorum, §6.2) can regenerate all user keys and decrypt the entire recorded ciphertext history — there is no forward secrecy for either the classical or the PQ half. This is the deliberate consequence of choosing stateless Per-Message KEM over a Double Ratchet (§3.2): no session state to desync, at the cost of no post-compromise secrecy. The seed must be protected accordingly (offline backup, optional Shamir split, §6.2).

**Pairwise Rendezvous Secret (§4.11.3).** In addition to the ephemeral Per-Message KEM, a deterministic, long-lived pairwise secret exists between any two contacts. It is derived via X25519-DH on the founding keys (stable across Emergency Key Rotation) and serves exclusively as input for the External Rendezvous lookup-tag computation (§4.11). It is **never** used for message encryption. Full derivation specified in §4.11.3.

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

**Key rotation**: User-Keys do not rotate in normal operation. There are two explicit compromise responses: **(a) Hard re-identity** — new seed → new UserID, contacts re-verify (§7.4a); **(b) Emergency Key Rotation / Soft re-key** (§7.4b / §26.6.2) — new seed and new keys under the **same** UserID, authorized by a dual-signed old→new continuity proof, propagated to the user's own devices via Twin-Sync and to contacts via `KEY_ROTATION_BROADCAST`. The UserID is a stable anchor (§3.1); the dual-sig chain is the only sanctioned way to change user keys without abandoning the identity. Verification-level retention on re-verification: §3.9. (ContactSeed coherence after rotation is solved via the founding-pubkey seed field, §8.1.1 / SR-2. The rotation-**authorization** weakness — the old key alone authorizes, SR-1 — remains tracked in the security review.)

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

1. **Infrastructure-Frame KEM** (§2.3.5) — DHT pings, routing probes, NAT/hole-punch, reachability queries, peer-list gossip, fragment storage, S&F on contact peers (§5.5), 2D-DHT identity-resolution operations. Sender encapsulates under recipient Device-KEM-PK; recipient decapsulates with Device-KEM-PrivKey.
2. **First-Contact-Request bootstrap** (§8.1.1) — when Alice scans Bob's ContactSeed she knows his DeviceID and userEd25519Pk (from the QR/URI). She resolves his Device-KEM-PK via DHT lookup (primary, §4.3) or DEVICE_KEM_REQUEST/OFFER handshake (fallback, §8.1.1 rev3). She does not yet know his User-KEM-PK (which she only learns from CONTACT_REQUEST_RESPONSE). The CONTACT_REQUEST itself is therefore wrapped as `InfrastructureFrame.payload` (KEM under Bob's Device-KEM-PK), with Alice's full user-signed ApplicationFrame carried as the inner payload.
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

- Inside the **DeviceKemRecord** in the 2D-DHT (§4.3 — separate record with 24h TTL, storage-key `SHA-256("kem" || userId || deviceId)`) — primary distribution channel
- Via **Deferred Key Exchange** (§8.1.1 rev3): `DEVICE_KEM_REQUEST` → signed `DEVICE_KEM_OFFER` — synchronous fallback when DHT record is unavailable
- Cached in the local routing table once a `ResolvedDevice` has been observed
- Inside the **ContactSeed URI** (clipboard/share path): parameters `dxk` (X25519, 32B) + `dmk` (ML-KEM-768, 1184B), standard base64. Enables offline first-CR (FIRST_CR_STORE on seed peers) without synchronous DEVICE_KEM_REQUEST/OFFER — critical for CGNAT-to-CGNAT clipboard exchange where both phones may not be online simultaneously. QR binary format (camera scan) remains compact v2 (ep only) since QR implies physical co-presence

**Key generation**: locally on the device using cryptographic randomness (NOT derived from the User-Master-Seed). The same rationale as §3.5 applies: device-key independence ensures that a seed compromise does not retroactively compromise the device's KEM state. See §3.6 #5 for the unified explanation that covers both Sig and KEM device keys.

**Key rotation**: once at device setup. On device loss, the old device is removed from the AuthManifest via §7.4 Device-Revocation. The DeviceKemRecord becomes implicitly invalid because the resolver-cascade filters by AuthManifest membership (§4.3 step 5) — even if a stale DeviceKemRecord lingers in the DHT, it is rejected by the receiver because the deviceId is no longer authorized.

### 3.6 Multi-Identity HD-Wallet Derivation

Every User-Identity is based on a 32-byte Master-Seed (derived from the 24-word Recovery-Phrase). **All** Cleona keys are deterministically derived from the Master-Seed — Multi-Identity, all Sig-Keys, all KEM-Keys (Device-Keys are the documented exception: locally generated, see the schema below). The post-quantum keys (ML-DSA-65, ML-KEM-768) use FIPS 203/204 deterministic key-generation from a per-key HKDF seed (liboqs `_derand`), so they regenerate identically from the master seed just like the classical keys (§3.3.5).

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
1. The **OS keyring** protects `master_seed.enc` and `device_keys.enc` (which contains both the Device-Sig keypairs Ed25519+ML-DSA-65 and the Device-KEM keypairs X25519+ML-KEM-768; see §3.5 + §3.5b). On Linux: libsecret (GNOME Keyring / KWallet). On Windows: DPAPI (CurrentUser scope) with a **round-trip probe** at `init()` — a 4-byte test value is encrypted, decrypted, and compared; if the probe fails (Session-0 context, corrupted master keys, service accounts), the Windows backend falls back to `_FileKeyringFallback` instead of silently producing unreadable ciphertext. The DPAPI wrapper validates that ciphertext files contain strict base64 only before passing them to `PowerShell`, preventing injection via tampered `.dpapi` files. On Android: AndroidKeyStore with a biometric/device-credential gate. On macOS: Keychain via `security` CLI. When no OS keyring is available (headless daemons, iOS, unsupported platforms, or Windows DPAPI probe failure), a **file-based fallback** encrypts key material at rest using XSalsa20-Poly1305 (secretbox) with a key derived from `SHA-256(hostname + salt)` (v2 — baseDir was removed from the derivation in S106 because path changes silently broke all stored secrets; v1 files are transparently migrated on first load). The master seed is dual-written to both keyring and legacy file as defence-in-depth against keyring loss; `_storeMasterSeed()` checks the keyring `store()` return value and logs a warning on failure. Both `DeviceKeysStore.loadOrCreate()` and `loadMasterSeed()` refuse to silently regenerate keys when encrypted key material exists on disk but cannot be decrypted — `DeviceKeysStore` tries legacy `db.key` fallback first then fails loud; `loadMasterSeed()` throws `StateError` when a `.dpapi` file exists but DPAPI decryption fails and no file fallback is available (preventing the catastrophic cascade: null seed → null fileEncKey → new random keys → silent identity loss). This is not equivalent to hardware-backed protection (the key is reconstructible from machine context), but prevents plaintext seed exposure via backup copies, accidental file access, or forensic disk reads.
2. The **Master-Seed** is held in RAM after daemon start (in a protected memory region via libsodium `sodium_mlock`).
3. **HD-Wallet derivation** (§3.6) generates all further keys on demand — the private keys live only in protected memory.
4. The **DB-Encryption-Key** is derived from the User-Identity Ed25519 private key (§3.8).
5. The **FileEncryption-Key** for `identity_meta.json.enc` and `identity_resolution_state.json.enc` is derived separately from the Master-Seed (`m/identity/N/file_enc_key`).

**Memory hygiene**:
- libsodium `sodium_mlock` prevents swap-out of the keys
- private keys and intermediate KEM session material (DH shared secret, KEM shared secret, IKM, derived message key) are actively overwritten with `sodium_memzero` / `fillRange(0)` after use — in both `encrypt()` and `decrypt()` paths of `PerMessageKem`
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

The verification level is reset to `unverified` until the user actively re-verifies. **This path also covers Emergency Key Rotation (SR-1):** even though a soft re-key carries a valid dual-sig + rotation chain (§7.4b), the receiver does not follow it silently at full trust — it applies the new keys but runs the same key-change warning + verification reset, because a valid chain does not prove the rotation was authorized by the legitimate owner rather than a seed-holding thief (§7.4b rotation-authorization threat model). A `contact_identity_rotated` IPC event carries the warning to the UI. As of RC-1, Key-Change-Detection fires on all four overwrite paths: `RESTORE_BROADCAST`, `KEY_ROTATION`, `CONTACT_REQUEST` (re-contact), and `CONTACT_REQUEST_RESPONSE` (re-contact response).

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
- **Mobile/desktop daemons**: a random port in `[1024, 65535]`, fixed on first start and persisted in `identities.json`. It remains stable across daemon restarts — important for NAT hole punching and for stored routing-table entries. Manual port changes via Settings are persisted to the same file (`IdentityManager.updatePort()`) so they survive restarts.

**Protocol Escalation** (order applied as payload size or unreliability grows):
1. **UDP single-shot** (default): payload ≤ 1200 bytes → one UDP packet
2. **UDP fragmented + NACK retry**: payload > 1200 bytes → app-level fragmentation (max 255 fragments, Fragment-NACK CFNK §5.8)
3. **TLS on the same port** (fallback): after 15 consecutive UDP failures or on anti-censorship indicators → TLS frame instead of UDP datagram
4. **HTTP on the same TCP port** (binary distribution only): First-Byte-Sniffing multiplexes `GET` → embedded HTTP server (§19.6.6) vs. `0x16 0x03` → TLS handshake on the same listener

TLS serves exclusively as a **transport fallback** for reachability — the end-to-end encryption (KEM layer) is unaffected. TLS provides no additional security, only additional reachability against operator DPI filters. **Socket lifecycle:** inbound TLS connections that send an invalid or unparseable frame are immediately destroyed (`client.destroy()`) to prevent socket leaks from malformed or probing connections. **TLS capability cache:** per-peer tristate (capable / incapable / unknown) with 24h TTL eviction and 1000-entry hard cap. Eviction causes a re-probe on next bulk send (graceful: unknown defaults to "try TLS"); no mid-transfer impact since entries are written after the send completes.

### 4.2 DHT (Kademlia, Closed Network)

Cleona uses a Kademlia DHT as the backbone for peer discovery, mailbox lookup, erasure-coded fragment storage, and 2D-DHT identity resolution. Kademlia was chosen for its O(log n) routing, natural redundancy via k-bucket replication, and long-standing use in BitTorrent, IPFS, and Ethereum.

**DHT address space**: 256-bit, identical key space as DeviceIDs and Mailbox IDs.

**k-bucket configuration**: 256 buckets (one per XOR-distance bit), with 200 entries per bucket. Standard Kademlia uses k=20, designed for networks with millions of nodes. Cleona operates in the 10–500 node range, where SHA-256-based Node-IDs cause ~50% of peers to land in bucket 255 — a k=20 bucket overflows at just ~40 peers, causing routing-table rejections and DV-routing desync (3,400+ failed sends/day observed on a mobile node, 2026-06-20). k=200 eliminates this failure mode with negligible memory overhead (~200 PeerInfo × ~1KB ≈ 200KB per bucket worst case).

**Closed Network authentication**: every DHT operation is authenticated by the HMAC in the outer frame (§4.10). Nodes without the `network_secret` can neither perform DHT operations nor interpret responses.

**Kademlia operations in v3.0**:

| Operation | Key type | Value type | Purpose |
|---|---|---|---|
| `findClosestPeers(key)` | DeviceID hash or any 256-bit key | list of DeviceIDs | routing lookup, K=10 closest |
| `store(key, value)` | Mailbox-ID, Auth-Manifest key, Liveness key, Fragment key | bytes | replicator operation for mailbox / 2D-DHT / erasure |
| `retrieve(key)` | as for `store` | bytes | lookup operation |
| `pingPong(deviceId)` | DeviceID | reachability + RTT | liveness checks |

**Replication factor**: K=10 (Kademlia convention). DHT records survive the loss of 9 replicator nodes, which remains safe for small mesh sizes (10–100 nodes).

**Eviction**: oldest-entry-first eviction when a bucket exceeds k=200 — the oldest entry is pinged and replaced by the new candidate if the ping times out (stale threshold: 4 hours). With k=200 and realistic mesh sizes (10–500 nodes), eviction is a safety net that rarely triggers, not a load-shedding mechanism. Note: periodic self-broadcasts (§5.11 `_dvSafetyNetExchange`, hourly) refresh `lastSeen` for all peers — only truly departed nodes (offline >4h) become eviction candidates.

### 4.3 Identity Resolution (2D-DHT)

Identity resolution answers the question: *"which devices currently host this UserID?"* — it is the **first** step on every user-addressed send path (see §5.1). It runs **before** the routing layer, not intermixed with it.

**Three-lookup steps** in the 2D-DHT:

1. **Auth-Manifest lookup** (long-lived, 24h TTL):
   ```
   key = SHA-256("auth" || userId)
   value = AuthManifest { userId, authorizedDeviceIds[], ttl=24h, seq,
                          userEd25519Pk, userMlDsaPk,    // D1: embedded trust anchor
                          rotationChain[],               // D1: empty unless soft re-key (§7.4b)
                          ed25519Sig, mlDsaSig }
   ```
   - hybrid-signed by the user's master keypair
   - **self-certifying** — the embedded pubkeys are covered by the hybrid signature and anchored to the userId (see *Trust anchor & record verification* below); without them a resolver holding only the userId (a hash) has no key to verify against — the original v3.0 cascade silently presumed a `userMasterEd25519Pubkey` it never sourced
   - refreshed every 20h by the IdentityPublisher (see §3.4)
   - returns the list of `authorizedDeviceIds` for this user

2. **Liveness-record lookup per device** (short-lived, adaptive 15min/1h):
   ```
   key = SHA-256("live" || userId || deviceId)
   value = LivenessRecord { userId, deviceId, currentAddresses[], ttl, seq, ed25519Sig }
   ```
   - signed Ed25519-only by the user key
   - refreshed every 15 min (foreground) or 1 h (background); **change-gated**: the periodic timer fires but `_skipBecauseNoChange()` suppresses the DHT publish when addresses are byte-identical AND < 80% of TTL has elapsed — only genuine address changes or TTL-expiry-proximity trigger actual wire traffic. Event-driven publishes (`onAddressesChanged`, `onPeerJoined` while under peer threshold) bypass the skip gate.
   - returns the current addresses for this device

3. **DeviceKem-record lookup per device** (long-lived, 7-day TTL — NEW in V3.0 Welle 5):
   ```
   key = SHA-256("kem" || userId || deviceId)
   value = DeviceKemRecord { userId, deviceId, deviceX25519Pk, deviceMlKemPk,
                             ttl=7d, seq, publishedAtMs, ed25519Sig, userEd25519Pk }
   ```
   - signed by the user master Ed25519 key (same trust anchor as AuthManifest — the user vouches for the device's KEM-PK)
   - refreshed every 3 days by the IdentityPublisher (well within the 7-day TTL)
   - returns the device's KEM pubkey set, sufficient for KEM-encap when sending an InfrastructureFrame to this device (§2.3.5)
   - **separated from LivenessRecord** because Device-KEM-PK changes only at device-key-reset (multi-year cadence) while Liveness must refresh every 15 min — different lifecycles. Co-locating them would re-publish the KEM-PK every 15 min for no semantic gain
   - **TTL raised to 7 days** to match the Mailbox/S&F retention window: a contact that has been offline up to 7 days remains KEM-resolvable, so a Deferred-Key-Exchange First-CR (§8.1.1) can still be encrypted and the First-CR-Mailbox (§5.5b) filled. The longer TTL is also **traffic-negative** — fewer republishes for a key that only changes at multi-year cadence

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
     authManifest = highest-seq VERIFIED AuthManifest from responses
                    (legacy-unverified only if no verified response exists —
                     see "Trust anchor & record verification" below)
     if none found: return []  ← Empty result triggers offline-delivery (§5.5/§5.6)

     **Wire-path**: each `kademlia.retrieve` call sends an
     `IDENTITY_AUTH_RETRIEVE` request via the BOOTSTRAP_INFRASTRUCTURE_FRAME
     pipeline (§2.4.1a) — replicator's Device-KEM-PK is unknown at this point,
     so KEM-encryption is impossible. The Auth-Manifest reply carries its own
     hybrid Ed25519+ML-DSA signature (verified in step 3 below).

  3. Verify Auth-Manifest (anchor + signature):
     per "Trust anchor & record verification" below —
     hybrid sig against the EMBEDDED pubkeys, identity binding
     via founding-key hash / rotation chain / contact match.
     The anchored userEd25519Pk of the winning manifest is the
     trust anchor for steps 4 and 4b.

  4. Liveness lookup per authorized device (parallel):
     for each deviceId in authManifest.authorizedDeviceIds:
       liveKey = SHA-256("live" + userId + deviceId)
       replicators = kademlia.findClosestPeers(liveKey, count=10)
       responses = parallel retrieve
       liveness = highest-seq LivenessRecord whose ed25519Sig verifies
                  against the ANCHORED user pubkey from step 3
                  (legacy-unverified accepted per transition rules below)
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
        verify ed25519Sig against the ANCHORED user pubkey from step 3;
        the record's embedded userEd25519Pk MUST equal the anchored key
        (closes the self-referential check where a record was validated
         against the pubkey it carried itself)
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

**Trust anchor & record verification (D1 — insider-forgery exclusion):**

A manifest is **verified** iff (a) its hybrid signature validates against the **embedded** pubkeys, and (b) the embedded identity is **bound to the userId** via one of three equivalent paths:

1. **Founding key:** `SHA-256(network_secret || userEd25519Pk) == userId` — the same self-certification pattern as the ContactSeed integrity check (§8.1.1).
2. **Rotation chain** (soft re-key, §7.4b): the chain starts at a founding pubkey whose hash equals the userId; each link carries the old key's Ed25519 signature over the successor pubkeys (reusing the `KeyRotationBroadcast` link shape, Appendix A); the final link's pubkeys equal the embedded ones.
3. **Contact match:** the embedded pubkeys equal the stored contact pubkeys for this userId (contacts track rotations via KEY_ROTATION_BROADCAST, so their stored key is current).

**Contact continuity (mandatory):** if the userId is a stored contact, path 3 MUST hold (or a valid rotation chain must bridge old→new); a mismatch triggers a **self-heal check**: if path 1 (founding-key binding `SHA-256(network_secret || embeddedPk) == userId`) verifies for the AuthManifest's embedded pubkey, the stored contact key is updated to the AuthManifest key automatically (local-only, no network traffic). This covers stale contact keys caused by delete+re-add scenarios where the contact was re-added from a fresh CR but the stored key was not yet updated. If neither path 1 nor a valid rotation chain bridges the mismatch, the record is rejected and the existing key-change-detection event (§8.3) is raised. **Resolver continuity (TOFU):** once a verified manifest is cached, later manifests must verify against the cached anchor or present a valid chain — a higher `seq` alone never replaces a verified anchor.

**Selection rule:** verified beats legacy-unverified; highest `seq` within the class.

**Liveness / DeviceKem:** both verify against the anchored user pubkey from the verified manifest of the same cascade. The DeviceKemRecord's embedded `userEd25519Pk` MUST equal the anchored key — this closes the self-referential check where a record was validated against the pubkey it carried itself, which any insider could satisfy with a self-made record.

**Transition & compatibility:** Legacy records without embedded pubkeys are accepted as **legacy-unverified** (lower precedence, never override a cached verified anchor) until the Phase-2 enforcement gate (`minRequiredVersion`, §19.5.7). Old builds are unaffected — they never verified records and ignore the new fields. Old replicators that round-trip a new record through their typed decode/encode drop the new fields; the record then degrades to legacy-unverified at the resolver — correctness is unaffected, only the verification benefit is lost on that path. Size/traffic: the embedded ML-DSA-65 pubkey adds ~2.0 KB to a record republished once per 20 h to K=10 replicators (~20 KB/day/user) — negligible, carried by the existing app-level UDP fragmentation (§2.4).

**Publisher cold-start semantics** (V3.0 Welle 5 — small-network correctness): the IdentityPublisher does NOT gate on a hard peer-count threshold. Instead:

1. **Burst-grace** (1s): poll the routing table at 100ms; if `peerCount >= peerThreshold (5)` mid-poll, publish immediately to the K-closest set (best case — the LAN multicast burst delivered the full neighbourhood before we publish).
2. **Single-peer fallback**: after the burst-grace expires, if at least one peer is reachable, publish anyway. `findClosestPeers(K=10)` returns `min(K, available)` — a single-peer publish is well-defined.
3. **Re-publish on join**: every `onPeerJoined()` callback while `peerCount < peerThreshold` re-broadcasts the current Liveness record so newly-arrived peers also receive a replica without waiting for the 15-min refresh tick.
4. **Cold-zero retry**: if no peer is reachable after the full `coldStartTimeout` (30s), schedule a 60s retry; the timer is superseded by `onPeerJoined()` when the first peer arrives.

`peerThreshold = 5` is no longer a hard publish gate but a "sufficient-redundancy goal". Small LANs and 2-node test setups MUST be able to publish identity records — otherwise resolution stalls indefinitely.

**Publisher self-store**: the publisher persists every Auth-Manifest / LivenessRecord / DeviceKemRecord it broadcasts into the local IdentityDhtHandler before sending to the K-closest replicators. Standard Kademlia convention publishes records to the K-closest peers including the publisher when it ranks among the K-closest; an explicit self-store makes this invariant uniform across small networks (where the publisher *always* ranks closest to its own dht-keys) and avoids the silent gap where a 2-node cluster has the records nowhere — the only candidate replicator (`findClosestPeers` returns the *other* peer, not self) is the publisher itself, but it never stored its own record.

**Replicator & lookup diversity (D4 — eclipse cost binding):** the K-closest selection for identity-record replication and retrieval prefers **IP-subnet diversity**: at most 2 peers per IP group (IPv4 /16, IPv6 /32; private LAN addresses group by /24; address-less peers share a single group) are taken in XOR-distance order; remaining slots are filled with the closest skipped peers — the selection **never returns fewer peers than the undiversified one**, so single-subnet LANs and small networks keep full replication. The rule applies on **both sides** (publish in IdentityPublisher, retrieve in IdentityResolver) and to the other replicator selections of the same store/retrieve pattern (erasure offline-delivery, identity-registry store, guardian restore), so store-set and lookup-set converge on the same diverse neighbourhood. The DHT `FIND_NODE` *response* path stays distance-pure (protocol semantics — the asker merges and re-sorts). Rationale (§13.1.8): ID grinding lets an insider occupy a victim's K-closest set with minted IDs; post-D1 that only censors. Diversity binds censorship to the genuinely scarce resource — an attacker confined to one subnet holds at most 2 of K=10 replicator slots while ≥8 candidates from other groups exist; majority occupation now requires presence in ≥4 distinct IP groups instead of ≥6 cheap keypairs.

**Publisher self-verify (D4):** after every Auth-Manifest publish cycle (start + 20h refresh) the publisher performs **one** delayed self-lookup (~10 s, lets the stores land): `IDENTITY_AUTH_RETRIEVE` fanned out to the current K-closest replicators, deliberately **bypassing the local self-store** (which would trivially succeed). Pass: at least one response carries the manifest at the just-published `seq`. Miss: warn-log plus exactly **one** re-publish to a freshly computed replicator set — edge-triggered, no retry timer. Honest limitation: a replicator that serves the publisher but censors third parties is indistinguishable from an honest one here; self-verify catches store failures and naive withholding, the structural defense against targeted censorship is the diversity rule above. Liveness/DeviceKem publishes are deliberately not self-verified per refresh (15-min cadence would triple identity traffic); they are protected by the same diverse selection. Observability: `idSelfVerifyOk` / `idSelfVerifyMiss` counters in network stats.

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

**Threat model for the trust anchor (D1):** Record forgery by replicators or any insider is excluded by the anchor — an eclipse of the K-closest set can now only **censor** (withhold records), not substitute identities (censorship resistance: replicator/lookup diversity + publisher self-verify, see the D4 blocks above and the §13.1 insider addendum). Honest limitation: the userId anchors only the Ed25519 key; the ML-DSA pubkey is bound transitively through the hybrid-signed content. For **non-contact** resolution the anchor is therefore classical — a future quantum adversary could swap the ML-DSA key in a fresh manifest. Real first contact is unaffected (the ContactSeed carries both pubkeys out-of-band, §8.1.1; unknown senders are KEX-gated, §8.2). Hybrid-anchoring the userId itself is a §3.1 identity-format decision, out of scope here. The rotation-chain links are Ed25519-only today (`old_signature_ed25519`) — they inherit the SR-1/H-2 classical-link weakness tracked in the security review.

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
- **DV-update propagation (traffic-bounded, delta-based)**: route changes fire `onRouteChanged`, which adds the destination to a pending-changes set (`_dvPendingChanges`, dedup by destination). A **2-second debounce timer** (`_dvPropagationDebounce`) accumulates all changes within the window; after 2s of silence, `_flushDvUpdates()` sends **one delta `ROUTE_UPDATE` per confirmed neighbor** containing only the changed destinations (Split Horizon applied, via `buildDeltaFor`), then clears the set. Additionally, a **per-neighbor hold-down of 10 seconds** suppresses further updates to the same neighbor even if the debounce timer fires again — changes accumulate and ship with the next permitted flush. This bounds worst-case DV traffic to 6 updates/minute/neighbor regardless of topology churn. The `_pushSelfToNeighborsExcept` self-broadcast is separately throttled to at most once per 30 seconds (global). Full-table updates (`buildUpdateFor`, `buildFullUpdate`) are reserved for welcome updates (new neighbor) and the 1h safety-net exchange.
- **Stale-route revalidation**: when an incoming direct packet calls `addDirectNeighbor()` and a stale route from the same `connType` already exists, the route is revalidated in-place (`revalidate()`) without triggering a new-neighbor event or incrementing `routeEpoch`. Previously, the stale route's inflated cost (+5 penalty from `onNetworkChanged`) was compared against the fresh cost — the fresh route always "won", causing every inbound packet from a known peer to fire new-neighbor logic (welcome route update + mesh broadcast), even though the peer was already established. The fix is surgical: only stale direct routes with the same connection type are revalidated; genuinely new connection types (e.g. a peer appearing on a new network interface) still trigger a full new-neighbor event. **V3.1.111:** `processRouteUpdateDetailed` no longer counts revalidation (un-staling) as a topology change — the stale penalty is a local selection bias that neighbors never see, so removing it does not warrant `routeEpoch++` or update propagation.
- **Receive-side `_touchPeer`**: every successfully verified incoming V3 packet calls `_touchPeer(senderDeviceId, from.address, fromPort)` immediately after `dvRouting.addDirectNeighbor`. This keeps `routingTable` (peer info + addresses) and `dvRouting._neighbors` in sync regardless of the discovery channel (LAN multicast, cross-subnet unicast scan, third-party `PEER_LIST_PUSH`) — without it, cross-subnet peers would land in `dvRouting` but never in `routingTable`, leaving the send cascade with `routes=0` despite a "DV: New neighbor" log line.
- **Split Horizon**: routes are NOT advertised back to the neighbor they were learned from.
- **Poison Reverse**: when a route fails, it is advertised with `cost=65535` (infinity) to all neighbors — accelerating loop detection.
- **Cost sanity bounds**: an advertised route is rejected if its claimed `cost` is non-positive or below `hopCount × minLinkCost` (minLinkCost = 1) — a path of *h* hops cannot physically cost less than *h* (cost is cumulative and every link costs ≥ 1). This blocks gross under-bidding (a neighbor advertising `cost=1` for a 5-hop path to attract traffic). It does **not** catch a plausible-but-false `cost=hopCount` claim (see threat model below). The bound applies only to *advertised* entries on the wire, never to internally derived routes.
- **Confirmed beats unconfirmed (all route classes)**: routes are sorted in two tiers — a route over which an end-to-end `DELIVERY_RECEIPT` has returned (`ackConfirmed=true`) outranks **any** route that has not, regardless of advertised cost; within a tier the existing cost ordering (incl. the direct-route DV-3 bias) and hopCount decide. This is a lexicographic partition, **not** an additive bias — so the direct-vs-relay balance among *unproven* routes is unchanged (an additive relay bias would distort it and was rejected during implementation). A receipt — even one that returns over a relay path (`wasDirect=false`) — marks the **specific route used** (via its `nextHop`) `ackConfirmed`, so a route earns its preference by demonstrated delivery, not by the advertisement alone; the default-gateway "relay-confirmed beats unconfirmed" rule (below) now holds *between competing relay routes* too. At first contact all routes to a destination share one tier → cost-only ordering until the first receipt proves one.

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
    // ACK timeout 0.5-2s direct (RTT-based), 8s relay, surgical mark route DOWN
  // Direct-target attempt: target is in routing table (e.g. from
  // addPeersFromContactSeed) with addresses but is NOT yet a DV neighbor
  // — the PING→PONG round-trip hasn't completed. Fire-and-forget UDP
  // to all reachable addresses. The relay cascade below runs regardless.
  if deviceId NOT in dvRouting.neighbors:
    targetPeer = routingTable.getPeer(deviceId)
    if targetPeer != null:
      reachableAddrs = filterNatContext(targetPeer.allAddresses)
      for addr in reachableAddrs:
        transport.sendUdp(packet, addr)   // best-effort, no ACK wait
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

**Default-Gateway Selection (V3.1)**: `updateDefaultGateway()` scores each DV neighbor by five criteria in strict priority order:
1. **relay-confirmed** — neighbors through which a DELIVERY_RECEIPT has been received beat unconfirmed neighbors unconditionally.
2. **unique destination coverage** — count of destinations reachable ONLY through this neighbor. A neighbor that is the sole relay to mobile/CGNAT devices (e.g. Bootstrap) scores higher than a LAN peer with many routes but no exclusive destinations. Prevents high-route-count LAN neighbors from shadowing the only relay path to hard-to-reach devices.
3. **route count** — total alive destinations reachable via this neighbor.
4. **average cost** — lower is better.
5. **recency** — most recent `lastConfirmed` timestamp breaks ties.

**Threat model — DV trusts insiders.** In the closed-network model every DV participant is an authenticated insider; advertisements are not cryptographically bound to a real path. The consequences and their mitigations:
- **Under-bidding / unique-coverage (traffic attraction → blackhole):** mitigated. Cost-sanity bounds reject impossible costs, and the confirmed-beats-unconfirmed rule means an advertised route attracts no *sustained* traffic until it has actually delivered end-to-end — a blackhole never produces the receipt that would earn it preference, so it stays demoted behind any proven route.
- **Wormhole (attacker faithfully forwards but observes/correlates):** **not prevented.** Detecting it would require signed path-vectors (S-BGP-style), disproportionate here — a wormhole sees only routing metadata (the same class of insider leakage discussed in §4.10), while message content stays KEM-encrypted and user-signed end-to-end.
- **Reverse attack (on-path receipt-dropping forces a victim off a good direct route onto relay):** on-path dropping is not generically preventable; surgical route-down (§5.8) plus the multipath fallback bound the damage. This affects deliverability, not confidentiality.

**Important**: when `sendToDevice` returns `false`, the sender has tried every available path including the default gateway. The caller (typically `service.sendToUser`) then decides on the failover path: erasure-coded S&F on contact peers (§5.5) plus a mailbox entry (§5.6) for receiver pull-up.

**MessageQueue no longer exists.** v2.2's MessageQueue retried the same send for 7 days. v3.0 stops after cascade exhaustion. The receiver pulls offline messages from the mailbox itself.

**Loading & pruning** (two-phase startup):
- Phase 1: pure deserialization of `routing_table.json.enc` — all peers are loaded, regardless of age.
- Phase 2: the caller (`CleonaNode.start()`) invokes `prune(maxAge: 2h)` separately.
- Safety net: if the 2h prune would remove **all** peers, the table is re-loaded without pruning.

**Maintenance pruning**: a scheduled run every 15 minutes prunes peers older than 24h (V3.1.111, previously 4h — overnight-offline devices were lost by morning; `evictStalePeers()` catches high-failure zombies sooner, `pruneStaleAddresses()` handles stale addresses at 14d TTL).

**Preference**: `findClosestPeers()` partitions into "recent" (< 10 min) and "stale", preferring recent peers by XOR distance. DHT/resolution lookups select by **age and XOR distance only** — they are **not** filtered by `direct-confirmed` (the V3.1.71 `defaultPeerFilter = isPeerConfirmed` is removed in V3.1.72: it broke first-contact identity resolution, which must reach replicators chosen by distance, not by whether we recently heard from them directly).

**Periodic-Operations Inventory** (V3.0 — event-driven where possible):

| Mechanism | Frequency | Network traffic? | Replaceable by event? |
|---|---|---|---|
| Maintenance prune | 15 min | none (internal only) | no — bounded internal scan, fine as a low-rate timer |
| Peer-Exchange tick (legacy 120 s) | **removed** | — | yes, replaced by event triggers (below) |
| DV Safety-Net + liveness heartbeat | 1 h | full `ROUTE_UPDATE` to all neighbours, a piggy-backed slim `PEER_LIST_PUSH` (Self-Broadcast) per §5.10.5 cold-path, **and a gate-bypassing liveness-PING sweep to all known peers — incl. LAN/IPv6/same-WAN — via the direct `_sendInfraDirect` path (jittered), refreshing `direct-confirmed` (§4.6)** | partially — once-per-hour backstop; the PING sweep is the **sole periodic refresh** of direct-confirmed for non-NAT peers, which `UdpKeepalive` deliberately does not cover (V3.1.72) |

**Event triggers replacing the periodic Peer-Exchange tick**:

1. **New-neighbor event** — when `_touchPeer` reports `isNewNeighbor=true` for an incoming sender, the node fires one slim `PEER_LIST_PUSH` to its **confirmed** neighbours only (shuffled, 200 ms spacing per peer, §4.4 confirmed-peer gate) so the mesh learns the new peer immediately. Unconfirmed peers are skipped — they pull via Mesh-Refresh when they come back online. **Additionally, the node sends one slim `PEER_LIST_PUSH` (Self-Broadcast) directly back to the new neighbor** — carrying the node's own PeerInfo including `device_id_pow_nonce` (§13.1.2). This ensures the new neighbor can verify admission PoW within 1 RTT and elect the node as relay/gateway without waiting for the 1 h cold-path. The return-push is critical for the ContactSeed bootstrap (§8.1.1): seed peers learned from a QR/URI carry no PK or nonce — only the Self-Broadcast delivers the admission proof. Logged as `§5.11: new-peer-event → broadcasting PEER_LIST_PUSH to N neighbors (200ms jitter)` (mesh-facing) and `§5.11: new-neighbor self-push to <hex>` (return-push).
2. **Identity-rotation event** — on local signing-key rotation (`_performKeyRotation`, `rotateIdentityKeys`, `_handleTwinSettingsChanged`), the service calls `node.broadcastAddressUpdate()` which fires one slim firstParty `PEER_LIST_PUSH` (Self-Broadcast, 200 ms jitter per peer) to all known peers. This lets every peer's stale-PK cache heal under §5.10.5 — see §5.10.2 hot path for the receive-side mechanism.

The replacement is not a 1:1 mapping — the old 120 s tick produced ~30 `PEER_LIST_SUMMARY` per hour per node regardless of whether anything had changed. The event triggers fire only when there is something to report. Measured reduction in periodic chatter: ~30× (from ~30/h to ~1/h via the safety-net piggy-back).

**Slim PEER_LIST_PUSH and on-demand PQ-key fetch** (V3.1.71):

All `PEER_LIST_PUSH` paths (new-neighbor, address-update, safety-net, `_pushSelfToPeer`) now serialize `PeerInfoProto` in **slim** mode: the five PQ key/signature fields (`ml_dsa_pk` 1952 B, `ml_kem_pk` 1184 B, `x25519_pk` 32 B, `device_ml_dsa_pk` 1952 B, `ml_dsa_sig` 3309 B) are omitted. Instead, a `key_fingerprint` field (32 B, `SHA-256(ed25519_pk ‖ ml_dsa_pk ‖ x25519_pk ‖ ml_kem_pk ‖ device_ed25519_pk ‖ device_ml_dsa_pk)`) is included so the receiver can detect key changes without the full material.

Result: a slim PeerInfoProto is ~450 B — fits in a single UDP datagram (MTU 1200 B) without app-level fragmentation. The previous full PeerInfoProto was ~8,800 B = 8 UDP fragments per push. Under congestion (e.g. 20-node simultaneous startup), fragment-loss triggered NACK-retransmit spirals.

**On-demand PQ-key fetch**: when the receiver processes a slim `PEER_LIST_PUSH` and detects that the sender's PQ keys are missing from its cache **or** the received `key_fingerprint` differs from the locally computed fingerprint, it sends a `PEER_KEY_REQUEST` (empty payload, BOOT path) to the sender. The sender responds with a `PEER_KEY_RESPONSE` carrying the full `PeerInfoProto` (including all PQ keys) for each hosted identity. Cooldown: max 1 request per peer per 60 s.

**Push jitter**: both `_pushSelfToNeighborsExcept` and `_broadcastAddressUpdate` filter to confirmed peers (§4.4), shuffle the list, and space sends at 200 ms per peer. Combined with the 0–3 s cold-start jitter (§4.5), this limits the peak burst rate even when many nodes join simultaneously. Additionally, `_pushSelfToNeighborsExcept` is **globally throttled to at most once per 30 seconds** — the new-neighbor event that triggers it can fire repeatedly during revalidation bursts (e.g. after `onNetworkChanged`), and without throttling each revalidation would fire a full mesh broadcast.

The PEER_LIST_WANT → PEER_LIST_PUSH response path (`_handlePeerListWantInfra`) continues to deliver **full** PeerInfoProto — the WANT is an explicit key-material request and the response must carry the complete PQ keys.

### 4.5 Mesh Discovery

Cleona nodes find each other through a **cascading discovery sequence**. Each tier fires only if the previous tier failed to produce a confirmed peer with a fresh peer list. This minimises startup traffic to the bare minimum required for mesh entry — in the common case (at least one stored peer is online), discovery completes with 3 packets (1 PING + 1 PEER_LIST_WANT + 1 PEER_LIST_PUSH) instead of thousands. No BLE (presence leakage, eclipse attack).

**Discovery channels** (available to the cascade):

| Channel | Mechanism | Use case |
|---|---|---|
| **IPv4 Broadcast** | UDP broadcast 255.255.255.255 on the local subnet | LAN, same subnet |
| **IPv4 Multicast** | 239.192.67.76, TTL=4 | LAN, cross-subnet with IGMP snooping |
| **IPv6 Multicast** | ff02::1 (link-local) + ff15::cleona (site-local) | LAN, IPv6-only networks |
| **NFC** | pairing bump between two devices | first introduction, contact exchange |
| **QR code** | device pubkey + addresses encoded as QR | visual pairing path |
| **ContactSeed URI** | `cleona://...` link, copy/paste | sharing via email or messenger |
| **Channel URI** | `cleona://channel/<id>?n=<name>` link, share/deep-link | subscribing to a public channel via link (§9.2.1) |

**Discovery cascade** (startup and Stage-5 Re-Discovery §5.10.5):

| Tier | Mechanism | Fires when | Traffic cost |
|---|---|---|---|
| **1 — Stored peers** | Probe peers from persisted routing table (§4.4), sorted by **stability tier (§4.9.2) first, then lastSeen recency** — Anchor/Stable peers (same address ≥30d/7d) are probed first because they have the highest probability of still being reachable after extended offline. One `DHT_PING` per peer, 2 s timeout, max 5 peers probed sequentially. First `PONG` triggers `PEER_LIST_WANT` → peer replies with live `PEER_LIST_PUSH`. | Always (if routing table non-empty) | 1–5 PINGs + 1 WANT + 1 PUSH |
| **2 — LAN Discovery** | 3× burst on IPv4-Broadcast + IPv4-Multicast (239.192.67.76, TTL=4) + IPv6-Multicast, then silence. | Tier 1 exhausted (all stored peers unreachable or routing table empty) | 9 datagrams (3 × 3 channels) |
| **3 — Bootstrap** | Unicast probe to cached bootstrap addresses: stored peers with public WAN IPs are probed on both their stored port and the channel-default bootstrap port (8081 beta / 8080 live — §17.5). Bootstrap is an accelerator (§4.7), not a first resort. | Tier 2 exhausted (no LAN peer responded) | 1–4 PINGs |
| **3b — External Rendezvous** | Two parallel resolve paths: **(A) Contact-Rendezvous** — for each unreachable contact: look up cached AuthManifest (§4.3) → device list; for each device: compute device-scoped lookup tag (§4.11.4), query all providers. First valid record per device yields the device's externally reachable addresses → direct UDP contact attempt. Falls back to previous epoch if current yields no hits. **(B) Infrastructure Rendezvous (§4.11.9)** — compute network-wide infra tag, query all providers → returns current addresses of all publicly reachable network nodes (bootstrap, port-forwarded peers). Connect to any hit → enter the mesh → reach remaining contacts via DV routing. Both paths fire in parallel; first successful connection from either path triggers discovery-complete. Timeout: 10 s per provider. | Tier 3 exhausted AND at least 1 accepted contact exists (path A) OR network secret available (path B) | < 50 KB (a few WebSocket requests) |
| **4 — Subnet Scan** | Unicast probe over the local /16 (port 41338), DHCP-priority hosts first, then sweep. Rate-limited to ~50 pps to avoid flooding upstream WAN links (§4.5.3). Last resort. | Tier 3b exhausted (no external rendezvous hit or no contacts) | ~65 000 probes over ~22 min |

**Discovery-complete gate**: the node-level flag `_discoveryComplete` is set when **any** tier produces a confirmed peer that delivers a `PEER_LIST_PUSH` with ≥1 entry. Once set:
- All pending discovery timers are cancelled (no further tier escalation).
- Kademlia bootstrap, proactive rendezvous (§4.6), welcome route floods, and address broadcasts are suppressed — they are not needed because the live peer list already provides current addresses and routes.
- DV route propagation (`_onDvRouteChanged` / `_flushDvUpdates`) and normal peer maintenance proceed normally — these are operational, not discovery.
- The flag is reset on network-change events (§4.9) so the cascade re-runs with fresh conditions.

**Isolated-node exception.** A node at **`peerCount == 0`** (empty persisted routing table — fresh install or long offline) skips Tier 1 and starts at Tier 2. If all tiers exhaust without success, it runs a self-terminating **re-discovery retry** with exponential backoff (1 min → 5 min → 30 min, capped at 60 min). Each tick re-runs the full cascade from Tier 2. The retry stops the instant the first peer is confirmed. Traffic cost is O(1) (an isolated node has no peers to storm) and the timer is never armed in a populated mesh. See §12.3 for the shared recovery sequence it feeds into.

**Cold-start jitter**: after discovery completes, the node delays 0–3 s (uniform random) before the first DV route propagation and address broadcast round. This staggers the O(N²) `PEER_LIST_PUSH` cascade that occurs when many nodes boot simultaneously (e.g. a mod-lab cluster or power-cycle event). After the jitter, the node also **retries deferred reachability probes**: if ipify discovered the external IP before discovery completed but the IPv4 port probe failed due to "no confirmed peer available", the probe is re-issued now that a live peer exists. Similarly, the IPv6 inbound probe (§4.7) is retried if it was deferred at startup. This is a one-shot per network-join (guarded by `_discoveryComplete`); three event-driven opportunities exist in total: (1) ipify callback at startup, (2) `_onDiscoveryComplete` retry, (3) next `onNetworkChanged` which resets `_discoveryComplete` and re-runs ipify. No periodic timer. This closes a timing gap where nodes behind NAT (especially bootstrap nodes starting with zero peers) never confirmed their external IPv4 despite it being port-forwarded and fully reachable — the unconfirmed address was absent from `ownPeerInfo()`, `PEER_LIST_PUSH`, and ContactSeed URIs, making the node invisible for cross-network peers.

#### 4.5.2 Native UDP Send Path (libcleona_net)

LAN-Discovery's send path on Linux and Windows desktop runs through a small C library, **`libcleona_net`**, instead of Dart's built-in `RawDatagramSocket.send()`. The shim wraps the host operating system's native UDP send call — `sendto()` from POSIX on Linux, `WSASendTo()` from WinSock2 on Windows — and exposes a tiny synchronous API to Dart through FFI. This subsection explains why the indirection was necessary, what exactly the shim does and does not do, how it behaves when something is wrong, and what the consequences are for receive, security, and other platforms.

**The reason this exists at all.** When Cleona has no known peer addresses on startup, `LocalDiscovery` enters a subnet-scan phase that probes the local /16 network at /24 resolution, sending one CLEO discovery datagram per host at roughly 50 packets per second (~22 minutes for a full /16; rate-limited from the original 500 pps to avoid flooding upstream WAN links — see §4.5.3). On Windows at the original 500 pps rate, only about 11 percent of the issued sends actually left the host — pktmon counters at the Windows TCPIP layer confirm that the dropped sends never reach the kernel network stack. Raising the kernel send buffer to 4 MB does not change the drop rate. The defect therefore lives in Dart's Windows I/O implementation, specifically in the IOCP-based UDP send routine that the VM substitutes for the simpler POSIX path. PowerShell's `.NET UdpClient` doing the equivalent work shows zero drops, which both proves the underlying network can carry the traffic and gives us a reference for what "correct" looks like. The C shim adopts the `.NET UdpClient` strategy: each `cleona_udp_send` call invokes `WSASendTo` synchronously and returns either the number of bytes sent or a negative error code, with no IOCP queueing layer between the Dart caller and the kernel.

**What the shim does.** A single C source file under `native/cleona_net/` exposes four functions: open a UDP socket bound to a given local port, configure send and receive buffer sizes, send one datagram to a destination IP and port (returning the byte count or a negative error), and close the socket. The Dart side wraps each function in a small `dart:ffi` binding under `lib/core/network/native_udp_sender.dart`. `LocalDiscovery` holds one `NativeUdpSender` instance for the lifetime of the daemon, opened against the well-known discovery port 41338. The shim is **send-only** — no recv, no select, no epoll. Receive remains in Dart's `RawDatagramSocket.listen()` callback as before, because the receive path has no observable defect on any platform we tested.

**What the shim does not do.** It does not wrap multicast group membership management, broadcast permission flags, or the routing-related socket options that LocalDiscovery already configures on the Dart-owned listening socket. Both sockets — the Dart-owned receive socket and the shim-owned send socket — are bound to the same local port 41338 using `SO_REUSEADDR` (Linux/Windows) so that they can coexist; multicast group membership remains on the Dart socket where the listener actually reads incoming traffic. The shim is purely a syscall conduit for outgoing datagrams.

**What happens when something is wrong.** The shim is a hard dependency on Linux x86_64 and Windows x86_64 desktop builds. On daemon startup, if the dynamic library cannot be opened — file missing from the bundle, wrong CPU architecture, broken build — the daemon logs a single explicit error line that names the expected library path (`libcleona_net.so` or `cleona_net.dll`) and exits with a non-zero status. There is **no fallback to the Dart send path**. We considered a fallback and rejected it: a silent fallback would mask exactly the conditions we built the shim to fix — broken builds, missed deployment steps, or platform mismatches would all manifest as "subnet-scan still drops 89 percent of sends" and operations would look indistinguishable from the un-shimmed state. The architectural fix would then risk being declared "useless" and reverted, when in reality the shim simply was not being used. By failing closed at startup we make this class of failure visible and immediate.

**Security model.** The shim sees raw UDP datagrams that the rest of Cleona has already constructed — CLEO discovery probes (38 bytes including magic) for the LAN-Discovery send path, no other payload types. The shim performs no cryptography, validates no headers, and has no awareness of the Closed-Network HMAC framing (§4.10) — that wrapping happens above the FFI seam on the Dart side. The C source has no parsing, no allocation past the per-call buffer, and no state beyond the socket handle. The trusted native code surface introduced by this shim is therefore small and self-contained.

**UDP receive buffer sizing (V3.1.85).** `Transport.start()` sets `SO_RCVBUF` to 2 MB on every bound socket (initial bind and `reconnectSockets()`). Dart's `setRawOption` requires raw `(SOL_SOCKET, SO_RCVBUF)` constants which differ by platform: Linux uses POSIX values (`SOL_SOCKET=1`, `SO_RCVBUF=8`), while Windows, macOS, and iOS use BSD values (`SOL_SOCKET=0xFFFF`, `SO_RCVBUF=0x1002`). Prior to V3.1.85 the code used Linux constants on all platforms, causing errno 10022 (`WSAEINVAL`) on Windows — the buffer remained at the OS default (~8 KB on Windows). The fix applies `Platform.isWindows || Platform.isMacOS || Platform.isIOS` to select the correct constant family. Failure to set the buffer is caught and logged but not fatal — the daemon continues with the OS default.

**Build and deployment.** The C source lives under `native/cleona_net/` with a CMakeLists.txt that produces `libcleona_net.so` on Linux and `cleona_net.dll` on Windows. Linux builds are bundled into the Flutter Linux release alongside `libcleona_audio.so`; Windows builds drop into `build/windows/x64/runner/Release/` next to `libsodium.dll`. Android and macOS desktop builds skip the shim entirely — those platforms continue to use Dart's `RawDatagramSocket` directly, with no functional regression observed. iOS uses a separate native send strategy described below.

**iOS send path (IosUdpSender).** iOS exhibits the same symptom as Windows — Dart's `RawDatagramSocket.send()` returns 0 for all destinations — but the root cause differs: the kqueue-based I/O path reports errno 64 (EHOSTUNREACH) or 65 (ENETDOWN) silently as a zero return value. The fix follows a different strategy than `libcleona_net`: instead of opening a second socket, `IosUdpSender` (`ios_udp_sender.dart`) locates the Dart socket's existing file descriptors — one for IPv4 (`cleona_ios_find_udp_fd`) and one for IPv6 (`cleona_ios_find_udp6_fd`) — by scanning open fds for `AF_INET`/`AF_INET6` `SOCK_DGRAM` sockets bound to the transport port, and calls native `sendto()` / `sendto6()` directly via FFI (`cleona_udp_ios.c`). The dual-fd approach is required because DS-Lite mobile carriers (common in Germany) provide only global IPv6 for end-to-end connectivity; IPv4 is tunneled through CGNAT and unreliable. `send()` dispatches to the IPv4 fd, `send6()` to the IPv6 fd. This preserves the one-socket-per-protocol-family invariant — no additional bound sockets, no receive-path starvation risk. For the discovery port (41338), a separate send-only socket is created via `createSendOnly()` because iOS aggressively recycles the Dart discovery socket's fd (ENOTSOCK on reuse). The native library is statically linked into the Runner binary (`cleona_exported_symbols.txt` controls symbol visibility against the linker's `-dead_strip`).

**iOS receive path (native recvfrom polling).** Dart's kqueue/CFSocket integration on iOS stops delivering `RawSocketEvent.read` events after a burst of native `sendto()` calls on the same fd — the kernel buffer fills but the event loop never fires. `IosUdpSender` provides a 50ms polling timer that calls native `recvfrom()` (via `cleona_ios_recvfrom()` in `cleona_udp_ios.c`) to drain the kernel buffer directly. The C function uses `sockaddr_storage` and handles both `AF_INET` and `AF_INET6` source addresses. On the Dart side, `recvFrom()` polls the IPv4 fd and `recvFrom6()` polls the IPv6 fd — both are called on every 50ms tick. The IPv6 poll is critical for DS-Lite mobile carriers where peers respond exclusively on IPv6; without it, the node can send but never receive, leading to 0 routes despite known peers. Diagnostics (`recvPeek()` / `recvPeek6()`) probe both fds on each 10s diagnostic tick.

#### 4.5.3 Subnet-Scan Rate Limiting (V3.1.95)

The subnet scan probes ~65 000 hosts across the local /16 range. All probes to /24 subnets outside the node's own directly-connected network traverse the default gateway. When that gateway leads to the internet — a common topology where a consumer router (e.g. Fritzbox on a 5.5 Mbit/s VDSL line) serves as both internet gateway and local LAN router — the probes are forwarded upstream as WAN traffic. At the original 500 pps (~400 kbps sustained for 130 s), this overwhelmed asymmetric consumer uplinks, caused seconds of added latency for all LAN traffic, and saturated the router's NAT/conntrack table.

**Why not skip non-local subnets?** The default gateway cannot be classified as purely "internet-facing" or purely "local router" — a Fritzbox simultaneously routes to the ISP, bridges additional LAN segments (e.g. a secondary WLAN radio on a different VLAN), and provides a guest WiFi network on its own /24. Blocking the scan for "internet-facing" gateways would prevent discovery of Cleona peers on these legitimate local networks.

**Solution:** rate-limit the scan from 500 pps to **50 pps** (~40 kbps). At this rate the bandwidth consumption is <1 % of even a 5 Mbit/s uplink — imperceptible to the user. The trade-off is scan duration: ~22 minutes for a full /16 instead of ~130 seconds. This is acceptable because:

1. The subnet scan is **Tier 4** — a last resort that fires only after stored-peer probes, LAN broadcast/multicast, and bootstrap all failed.
2. The node's own /24 is already covered by Tier 2 LAN broadcast; the scan's value lies in reaching *other* /24 subnets.
3. The stoppage gate (`_discoveryComplete` / `_hasCrossSubnetPeer()`) aborts the scan immediately when a peer is found — typical discovery time is seconds, not minutes.
4. The reduced batch size (1 packet per 20 ms tick) also eliminates the Windows IOCP burst-drop issue that required the native send shim (§4.5.2) at higher rates.

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
- The coordinator (bootstrap or shared contact peer) sends `HOLE_PUNCH_NOTIFY` to both endpoints simultaneously.
- Both endpoints send `HOLE_PUNCH_PING` to each other's observed IP.
- The NAT mapping opens on both sides → communication becomes possible.

**Keepalive** (`UdpKeepalive`, §4.6.4): HOLE_PUNCH_PING packets are sent to each **confirmed** NAT-traversal peer at an **adaptive per-peer interval** to maintain carrier-NAT pinholes. The interval starts at 20 s and is probed upward (×1.5 after 3 consecutive PONGs: 20 s → 30 s → 45 s → 67 s → 101 s, capped at 120 s). When a probe fails (2 consecutive missed PONGs at the higher interval), the peer falls back to the last confirmed-safe interval and stops probing. This converges to ≈80 % of the actual NAT timeout (the ×1.5 probe overshoots by at most 50 %, so the fallback lands at 67–100 % of the true timeout). On network change all peers reset to 20 s and re-probe (the NAT context may have changed). Registration gate (`_needsKeepalive`): on desktop platforms, IPv6 peers are not registered because standard IPv6 has no NAT and therefore no pinholes to maintain. On mobile platforms (Android and iOS), however, IPv6 peers **are** registered for keepalive because mobile carriers deploy stateful firewalls that drop UDP bindings after 30–120 seconds of silence — the same timeout behaviour as carrier-grade NAT on IPv4, even though no address translation takes place. Without periodic keepalive packets these firewall bindings expire and the peer becomes unreachable for inbound UDP until the next outbound packet re-opens the path. Private-IPv4 peers are never registered (LAN-reachable without NAT traversal), and public-IPv4 peers sharing the node's own WAN IP are never registered (behind the same NAT, reachable on the LAN side). Newly registered peers start **unconfirmed** and receive at most 3 pings; a PONG promotes to **confirmed** (= successful NAT traversal, pinged indefinitely). Unconfirmed peers that exhaust their attempts are **suspended** until a network-change event resets them. After 3 consecutive rounds where all active (non-suspended) peers fail to PONG, `onAllPeersFailed` triggers a full network-change cycle (5-min cooldown). Peers that fail ≥5 consecutive rounds are excluded from the quorum (structurally unreachable). (V3.1.90) **NAT-keepalive (pinhole maintenance, cross-NAT public-IPv4 only) is distinct from the confirmation heartbeat (§4.4): the IPv6/private-LAN/same-WAN exclusions here apply *only* to pinhole maintenance — `direct-confirmed` for those peer types is refreshed by the once-per-hour liveness-PING sweep instead. (V3.1.72)** **IPv6-First keepalive gate (V3.1.94):** peers that have at least one global IPv6 address (not link-local `fe80:`, not ULA `fd`) are excluded from IPv4 keepalive registration entirely — the IPv6 path is end-to-end routable without pinhole maintenance, so maintaining an IPv4 pinhole is wasteful. This is applied at both registration sites (`_syncKeepalivePeers` and `_touchPeer`). Additionally, `onAllPeersFailed` checks for **outbound-confirmed liveness** before triggering a network-change cycle: suppression requires proof within the last ≈50 s (2× initial keepalive interval + margin) that **our own sends arrive** — a received PONG, DELIVERY_RECEIPT, or DHT/infra response. If such proof exists, the keepalive failure is structural (CGNAT), not a network outage — `onNetworkChanged` is suppressed. **(V3.1.120, replaces the V3.1.94 `_confirmedPeers`-TTL check:** the 1-h confirmed-peer window proves only the *receive* path; 2026-07-03 field evidence showed a receive-only bootstrap trickle holding it fresh for 2 h 23 min while the send path was dead, vetoing every recovery mechanism.)

**Dead-socket edge & send-path recovery (V3.1.120):** Dart's `RawDatagramSocket.send()` returns **0 without throwing** when the OS `sendto()` fails (dead WLAN uplink, interface in zombie state with addresses still assigned). The transport counts consecutive zero-byte sends (fragment groups count in bulk); crossing the threshold (10) fires the `onUdpSocketDead` **edge exactly once** — one warn line, one trigger — and disarms until a successful send or a completed socket rebind re-arms it (pre-fix every further zero-send re-fired warn+trigger: 36 000 log lines/min in the field). The first edge runs the classic heal: `onNetworkChanged(force)` → `reconnectUdpSockets()` (close + rebind on `anyIPv4`/`anyIPv6`, same port). A **second edge within 60 s of a completed rebind** proves the rebind healed nothing (same dead default route) and escalates directly to the **mobile-fallback probe** — ungated by confirmed-peer state; only "fallback already active" blocks it, and the probe itself verifies the mobile interface before switching. The three send-path recovery gates (keepalive network-change suppression above, the mobile-fallback gate in `onNetworkChanged`, the zero-peer recovery loop) all key on outbound-confirmed liveness; the zero-peer recovery timer is likewise cancelled only on outbound confirmation, **not** on arbitrary inbound BOOT frames (pre-fix any receive-only trickle deactivated it). `_confirmedPeers` (1 h TTL) remains unchanged for routing/ranking purposes.

**Address priority by type**:

| Priority | Address type | Rationale |
|---|---|---|
| 1 | Same-subnet LAN (private IPv4 same /24, IPv6 link-local) | Direct L2 path, <1ms, no NAT, no routing, no cost |
| 2 | Global IPv6 | End-to-end routable without NAT, no pinhole maintenance. **IPv6-First (V3.1.94):** DS-Lite/CGNAT bypass — on mobile carriers IPv6 is the only native path; IPv4 is tunneled through carrier NAT and unreliable. Promoted from priority 3 because IPv6 has objectively fewer failure modes than any IPv4 path (no NAT, no pinhole timeout, no CGNAT drop). |
| 3 | Other-subnet LAN (private IPv4 other /24, IPv6 ULA/site-local) / Public IPv4 (port-mapped via UPnP/PCP/NAT-PMP) | Routed L3 or port-mapped. LAN paths preferred over hole-punched/CGNAT IPv4 — a relay peer on the private network typically has a wired internet connection. |
| 4 | Hole-punched IPv4 | Short-lived, NAT-dependent, requires keepalive |
| 5 | CGNAT/DS-Lite IPv4 (100.64.0.0/10, 192.0.0.0/24) | Carrier NAT; rarely directly reachable. Includes DS-Lite well-known prefix (RFC 7335). |
| 6 | Relay (multi-hop via DV routing) | Additive latency (sum of individual links) |

**Cost optimization for relay:** When a peer is reachable via both a private and a public address, the private address is preferred (priority 3 < priority 4/5). This is architecturally intentional: a relay peer on the private network (e.g. bootstrap) typically has a wired internet connection. The path Phone → (LAN) → Relay → (wired internet) → Target is cheaper and faster than Phone → (mobile data) → Target. Mobile devices benefit most because mobile data traffic incurs both financial cost and higher latency. When the peer has both IPv6 global (priority 2) and LAN (priority 3), IPv6 is tried first — on mobile networks LAN addresses are unreachable anyway (`isReachableFromCurrentNetwork` filters them); on WiFi the latency difference is negligible.

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

**Single-success-return for confirmed peers** (V3.1.86): `_sendV3ViaHop` sends to the peer's known addresses in priority order. For **confirmed** peers (at least one prior successful exchange), the function returns immediately after the first successful UDP send — it does not continue to remaining addresses. For **unconfirmed** peers, all addresses are attempted (scatter-shot) to maximize first-contact probability, followed by a TLS fallback. Previously, large payloads (≥ 2 UDP fragments) were sent to ALL known addresses of a confirmed peer, causing 3–4× amplification per send (e.g. a 6-fragment route update sent to 4 addresses = 24 UDP packets instead of 6).

### 4.7 IPv6 Dual-Stack & CGNAT Bypass

V3.0 nodes operate **dual-stack** (IPv4 + IPv6 in parallel). IPv6 is increasingly important because of DS-Lite and CGNAT at mobile carriers.

**Problem: DS-Lite and CGNAT**:
- Carriers (especially mobile in DE) hand out only a shared CGNAT IPv4 plus a global IPv6.
- IPv4-direct is usually impossible inside CGNAT (source-NAT mappings are under operator control).
- IPv6-direct is trivial — every device has its own global IPv6.
- **CGNAT address ranges:** RFC 6598 `100.64.0.0/10` (Shared Address Space) **and** RFC 7335 `192.0.0.0/24` (DS-Lite well-known prefix, typically `192.0.0.4/32` on `rmnet`). Both MUST be detected by `_isCgnat()` and `_filterNatContext` — failure to recognize `192.0.0.x` as CGNAT caused the V3.1.93 Mobilfunk zero-peer bug (node sent to RFC 1918 addresses behind an unreachable NAT). (V3.1.94)

**Solution: IPv6 as primary transport** when both endpoints have global IPv6:

- The sender checks: does the local node have a global IPv6? does the receiver have a global IPv6 in the liveness record?
- If yes: try IPv6 first (address priority 2, ahead of all IPv4 paths).
- IPv6 reachability check: `PeerAddress.isReachableFromCurrentNetwork` checks for at least one global IPv6 (excluding fe80/fec0/fc/fd/::1/ff*).

**IPv4 CGNAT bypass techniques**:
- UPnP (when the router is IPv4 and the user has port-forwarding permission)
- Coordinated hole punch (rarely successful with symmetric NAT)
- Port prediction for symmetric NAT (heuristic)
- Mobile fallback socket (§4.6.4): after 15 consecutive sendUdp failures → all non-LAN traffic is shifted onto the mobile socket. Since V3.1.120 additionally reachable via the dead-socket edge escalation (second edge < 60 s after a completed rebind, see "Dead-socket edge & send-path recovery" above) — previously the fallback was gated on the receive-only confirmed-peer window and structurally unreachable in the WLAN-zombie failure mode.

**Bridging architecture** (dual-stack nodes as IPv4↔IPv6 bridges):
- A node with both IPv4 and global IPv6 automatically becomes a bridge between IPv4-only and IPv6-only nodes.
- When sender (IPv4-only) and receiver (IPv6-only) share contact peers via a dual-stack node, multi-hop relay implicitly acts as a bridge.
- **Invariant:** A dual-stack relay node MUST forward incoming packets on IPv6 to recipients on IPv4 (and vice versa). The relay-forward logic (`_sendV3ViaHop`) selects the best address of the next hop independent of the IP version of the incoming packet — the bridge function follows implicitly from address selection.

**CGNAT address reachability (V3.1.90+, updated V3.1.94):** The `isReachableFromCurrentNetwork` filter and `_filterNatContext` distinguish RFC 1918 private addresses from CGNAT addresses (RFC 6598 `100.64.0.0/10` + RFC 7335 `192.0.0.0/24` DS-Lite). A node on a CGNAT address **must not** send to RFC 1918 targets and vice versa — these address spaces have zero routing relationship. Cross-class private-to-private is permitted only within RFC 1918 (e.g. two RFC 1918 ranges behind the same gateway, common in home/lab networks). This eliminates guaranteed-futile UDP sends that waste traffic and obscure real delivery failures in logs.

**Reachability precondition, relay selection & inbound probe.** Online delivery between two endpoints that have **no** common direct path — both behind DS-Lite/CGNAT, or one IPv4-only and the other IPv6-only — depends on at least one **inbound-reachable relay** being online (global-IPv6-inbound, public-IPv4-with-port-mapping, or shared LAN; for the IPv4↔IPv6 case that relay must additionally be **dual-stack**). This is a hard precondition, not an emergent property — the word "implicit" above refers only to the address-selection mechanism, not to the availability of such a node. Relay-candidate selection therefore filters on `isReachableFromCurrentNetwork` (and, for cross-family delivery, dual-stack capability); a relay that the sender cannot itself reach is never chosen. To verify that a node's *self-announced* global IPv6 is actually **inbound-reachable** (network topology or local firewall rules may block incoming IPv6 despite a global address), each node runs a one-shot **IPv6 inbound probe** at every network-join: a peer/bootstrap echoes the self-announced global IPv6 back. If no PONG returns, the address is flagged `ipv6InboundVerified=false` but **remains advertised** in `currentSelfAddresses()` and `PEER_LIST_PUSH` broadcasts. On mobile carriers the inbound probe frequently fails because the carrier's stateful firewall blocks unsolicited inbound UDP, yet the address is genuinely valid for outbound-initiated connections: when both peers send to each other's IPv6 simultaneously, the carrier firewall opens in both directions (simultaneous-open). For a **first contact** — where the URI issuer does not yet know the scanner's address and thus cannot initiate its half of the simultaneous send — the coordinated mutual send is arranged by the First-Contact Rendezvous (§4.11.10). Suppressing the address entirely would prevent peers from ever attempting direct IPv6 delivery to mobile nodes. The `ipv6InboundVerified=false` flag is cleared on the first successful inbound packet from any peer on that address. This is the IPv6 analogue of the existing IPv4 STUN ping-pong (§4.6) — one round-trip per join, no timer. Note that the TLS transport fallback (§4.1) and the mobile fallback socket address **DPI/censorship**, not NAT reachability — neither makes a CGNAT endpoint inbound-reachable; under mutual CGNAT, relay remains the only online path.

**IPv6 Reception Bug (V3.1.x fix):** Investigation of the 2026-06-04 finding (Phone→Bootstrap IPv6 packet lost) revealed two root causes: (1) `MulticastDiscovery` bound a second IPv6 socket to `nodePort` with `SO_REUSEPORT` — on Linux the kernel distributed inbound IPv6 unicast packets between Transport and MulticastDiscovery; packets that landed on MulticastDiscovery were silently dropped (same class as the 2fbc879 IPv4 regression, §4.5.2). Fix: MulticastDiscovery now binds to `discoveryPort` (41338) like LocalDiscovery does for IPv4. The §4.5.2 invariant check was extended to also verify `/proc/net/udp6`. (2) `currentSelfAddresses()` classified all local IPv6 as `IPV6_GLOBAL` — ULA/link-local addresses were advertised as globally routable and tried by remote peers. Fix: uses `PeerAddress.classifyIp()` for correct classification.

*A section is omitted from the public edition.*


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
- **≥N independent inbound-reachable always-on nodes** (confirmed port-mapping or stable global-IPv6-inbound, measured via the same `hasPortMapping`/inbound-probe telemetry the seed-peer selection uses) — without this floor, a post-decommission mesh of CGNAT-only mobile/desktop nodes would have no relay entry point and CGNAT↔CGNAT pairs could not be served (§4.7)
- ≥30 days of stability without bootstrap intervention
- Mesh discovery operates self-organizing through peer lists

Until then, bootstrap nodes are the initial single-point-of-failure — if they are down, fresh daemon starts cannot enter the mesh.

**Bootstrap resilience**: stored routing-table entries (after pruning at §4.4) are the primary discovery source (Tier 1 of the §4.5 cascade). The daemon probes them first — only if all stored peers are unreachable does it escalate to LAN discovery (Tier 2), then bootstrap (Tier 3), then subnet scan (Tier 4). A fresh install with an empty routing table starts at Tier 2 directly.

### 4.9 Network Change Detection

Mobile devices change networks frequently: WiFi → mobile, new WiFi, VPN toggle, etc. Cleona reacts to such changes with re-discovery and a liveness republish.

**Detection mechanisms**:
- **Platform-API subscriptions**: Android `ConnectivityManager` callbacks, Linux `NetworkManager` D-Bus signals, Windows `INetworkListManager`.
- **Periodic polling fallback**: every 30s, re-read the local addresses via `getAllLocalIps()` and compare against the last state.
- **Network tag**: an HMAC mismatch on incoming packets can hint at a network change (an old network cache is still alive).

**Recovery actions on a network change**:
1. Retry public-IP discovery via STUN/UPnP.
2. Liveness republish (debounced 5s, see §3.5/§4.3).
3. External Rendezvous republish (debounced 10s, §4.11.7) — updates endpoint records on all RendezvousProviders with new addresses. The 10s debounce (5s after Liveness) ensures addresses are confirmed before external publication.
4. Soft-reset of the routing table: stale routes get a mark-stale flag, prune after 30s.
5. Topology-aware keepalive filter: ignore keepalives from old WLAN peers when in mobile-only mode.
6. Re-ping the bootstrap (no re-discovery — the bootstrap entry is kept).
7. Drain the send queue (S&F pull, mailbox pull) — new messages may arrive on the new addresses.

**Topology-aware keepalive filter**: mobile-only devices ignore keepalives from WLAN peers when the WLAN has been switched. This prevents stale WLAN addresses from staying "alive" in the cache.

**Routing-table audit on daemon start**: on every start `auditAddresses(currentLocalIps)` runs — pruning carrier-NAT addresses (100.64.0.0/10 RFC 6598, 192.0.0.0/24). All RFC 1918 private IPv4 are kept when the local node itself is on a private network (cross-subnet private peers are L3-routable via the gateway). Public IPv4 + IPv6 are kept (score-decay handles staleness).

#### 4.9.2 Address Stability Score (V3.1.113)

The short-term `effectiveScore` (24h half-life) answers "did the last send work?" but loses all memory after 48h offline. For cold-start recovery after extended offline (weekend, vacation), long-term address persistence matters: a server reachable under the same IP:port for 6 months is qualitatively different from a phone that changes IP every 24h.

**Per-address tracking:** `PeerAddress.stableSince` records the timestamp of the first successful contact under a given ip:port. Set once by `recordSuccess()`, never overwritten, persisted across daemon restarts in `routing_table.json`. Survives address-merge in KBucket (transferred to matching ip:port on firstParty updates).

**Per-peer tracking:** `PeerInfo.addressChangeCount` counts how often the peer's public address set has changed (a public ip:port disappeared AND a new one appeared in the same firstParty update). This distinguishes static-IP servers (count=0) from dynamic-IP DSL connections (count grows with each ISP reconnect).

**StabilityTier classification** (computed property on `PeerInfo`, not persisted — derived from persisted `stableSince` and `addressChangeCount`):

| Tier | Criteria | Semantics |
|---|---|---|
| **anchor** | oldest `stableSince` ≥ 30 days, `addressChangeCount` = 0 | Quasi-infrastructure: static IP, always-on. Contacted first on cold start (§4.5 Tier 1), preferred in ContactSeed (§8.1.1). |
| **stable** | oldest `stableSince` ≥ 7 days, `addressChangeCount` ≤ 2 | Reliable but not permanent (e.g. home server with rare ISP reconnects). |
| **normal** | everything else | Default — scored by `effectiveScore` as before. |
| **volatile** | `addressChangeCount` > 10 | Frequently changing address (mobile, dynamic IP). Used only when no better option exists. |

**Usage:**
- §4.5 Tier-1 Discovery sorts by stability tier before `lastSeen` recency. Anchor peers are probed first — they have the highest probability of still being reachable after extended offline.
- §8.1.1 ContactSeed peer selection fills anchor/stable peers with public addresses first (up to 3 slots), then remaining relay-capable peers.

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
- **Anti-Sybil**: an attacker **without the network secret** cannot operate fake nodes en masse — for the insider case (extracted secret) see the threat-model addendum §13.1.8.
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
| Anti-replay | timestamp window 60s + duplicate-frame cache (LRU, TTL 120s) | NetworkPacket.timestampMs + .networkTag |
| Anti-spam | PoW (selective) | NetworkPacket.pow |

**Defense in depth**: HMAC is the first filter stage (rejected without sig-verify, without KEM decap, cheap). Only after the HMAC passes are the replay window, the duplicate-frame cache and the device signature checked (cheap before expensive). Only then comes the routing decision or KEM decap.

**Application-layer dedup**: in addition to the transport-layer duplicate-frame cache, `CleonaService` maintains a `processedMessageIds` set (LRU, cap 4096) that deduplicates by `MessageEnvelope.messageId`. This set is persisted to disk (encrypted, alongside contacts/conversations) at daemon shutdown and restored at startup, closing the replay window across daemon restarts for Store-and-Forward and Reed-Solomon recovery messages.

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

### 4.11 External Rendezvous (Cold-Start Recovery)

#### 4.11.1 Problem & Design Principle

When a node is offline for more than 24 hours, its ISP may assign a new IP (dynamic IPv4, CGNAT remapping). The stored peer addresses in its routing table are stale, and the internal Cleona DHT (§4.2/§4.3) cannot help — it is only as alive as the node's own peers. The §4.5 Discovery Cascade escalates to LAN discovery (local only), bootstrap (may also have rotated), and subnet scan (22 minutes, local only). For peers on other networks (mobile carrier, different ISP, different city), there is **no** recovery path.

**Solution**: Each of Bob's **devices** independently publishes its own current endpoint on **external, permanently running networks** under a device-scoped, privacy-preserving key. The resolver uses the 2D DHT AuthManifest (§4.3, cached or live) to map Bob's userId to his device list, then resolves each device's endpoint via device-scoped lookup tags. This makes External Rendezvous a pure **deviceId → IP:port** directory — the userId → deviceId mapping is handled by the existing Identity Resolution (§4.3).

**Scope**: External Rendezvous handles only cold-start address resolution. Once a single live peer is found, all further traffic flows over the existing Closed-Network (§4.10) with HMAC authentication. The external networks **never** carry Cleona message traffic — they are a pure `lookupTag → encryptedEndpoint` directory.

**Design principle**: Apply **hardening layers** over a small number of substrates, rather than many substrates without hardening. Four orthogonal layers (§4.11.4–§4.11.5) each cover a different attack axis and compose to close the weaknesses of the individual substrates.

#### 4.11.2 RendezvousProvider Interface

All substrates implement a common interface. The existing IdentityResolver (§4.3) operates as the implicit Tier-0 provider (resolving via the internal Cleona DHT). External providers add parallel resolution channels.

```dart
abstract class RendezvousProvider {
  /// Publish a signed, encrypted endpoint record under the derived lookup tag.
  /// The tag is NOT the identity pubkey — it is an HKDF-derived, epoch-rotated
  /// value that only the specific contact pair can compute (§4.11.4).
  Future<void> publish(Uint8List lookupTag, SignedEndpointRecord record);

  /// Resolve the record under the tag. Returns null if nothing found or
  /// the channel is blocked in the current network.
  Future<SignedEndpointRecord?> resolve(Uint8List lookupTag);

  /// Whether this provider is usable in the current network context
  /// (e.g. WebSocket connectivity for Nostr, Tor circuit for Onion).
  bool get isAvailable;
}
```

The cascade logic remains simple: query all available providers in parallel (Happy-Eyeballs), take the first signature-verified hit with the highest `seq`. No provider-specific logic leaks into the caller.

#### 4.11.3 Pairwise Rendezvous Secret

The lookup tag must be unlinkable to the identity pubkey — an observer who knows Bob's public key must not be able to compute the tag and poll for his online presence. This requires a **shared secret** between Alice and Bob that an observer cannot derive.

**Derivation** (deterministic, no round-trip, both sides compute independently):

```
// Step 1: Convert founding Ed25519 keys to X25519 (libsodium built-in)
own_x25519_sk     = crypto_sign_ed25519_sk_to_curve25519(own_founding_ed25519_sk)
contact_x25519_pk = crypto_sign_ed25519_pk_to_curve25519(contact_founding_ed25519_pk)

// Step 2: X25519 Diffie-Hellman
pairwise_dh = crypto_scalarmult(own_x25519_sk, contact_x25519_pk)

// Step 3: Domain-separated HKDF
rendezvous_secret = HKDF-SHA-256(
    ikm  = pairwise_dh,
    salt = "cleona-rendezvous-v1",
    info = min(own_userId_hex, contact_userId_hex)
         || max(own_userId_hex, contact_userId_hex),
    length = 32
)
```

**Why founding keys**: The founding Ed25519 key is the stable identity anchor (§3.1) — it survives Emergency Key Rotation (§7.4b). Using the current key would require a transition window after rotation where both old and new tags are published; the founding key avoids this entirely.

**Symmetry**: `info = sorted(userId_A, userId_B)` ensures both sides derive the same secret regardless of who initiated the contact exchange.

**No new crypto**: `crypto_sign_ed25519_pk_to_curve25519` and `crypto_scalarmult` are existing libsodium functions already linked into Cleona. HKDF-SHA-256 is used elsewhere (§3.3, §7.1.1).

#### 4.11.4 Lookup Tag & Epoch

```
lookup_tag = HKDF-SHA-256(
    ikm    = rendezvous_secret,
    salt   = "cleona-rv-tag-v1",
    info   = epoch_string || "/" || hex(publisher_device_id),
    length = 32
)

epoch_string = "YYYY-MM-DD-HH"  (UTC, 6-hour boundaries: 00/06/12/18)
```

The `publisher_device_id` is the 32-byte Device-Node-ID of the publishing device (HD-Wallet-derived, §7, stable across IP changes). The resolver obtains the publisher's device list from the cached AuthManifest (§4.3) and computes the matching tag for each device.

**Properties**:
- **Pairwise**: each contact pair has a unique tag per epoch → perfect unlinkability. An observer who compromises one contact's key learns only that pair's tags, not the publisher's presence as seen by other contacts.
- **Device-scoped**: each device's tag is unique via its stable `device_id`. No direction bit needed — unlike the user-level design where both sides of a contact pair shared the same rendezvous secret and needed a direction bit to avoid tag collisions, each device already has a globally unique ID. Alice's desktop and Bob's phone naturally produce different tags even for the same contact pair and epoch.
- **6-hour epochs**: balance between publish frequency (4×/day per contact per device) and correlation window. Short enough that an old tag cannot be polled indefinitely; long enough that publisher and resolver don't need tight clock sync.
- **Overlap publish**: the publisher always publishes for both the current and the next epoch. This covers the transition window where Alice's clock may be in the next epoch while the record was published under the current one. Cost: 2× records per contact per device, negligible at Nostr's traffic level.

**Resolver device-list source**: the resolver needs the publisher's device IDs to compute lookup tags. These come from the cached AuthManifest (§4.3), which is fetched automatically on first contact and refreshed every 24h while online. Device IDs are HD-Wallet-derived (§7) and stable — a cached manifest from days ago still lists the correct device IDs even if the devices' IPs have changed. This is the key property that makes cold-start resolution work: the AuthManifest cache survives extended offline.

**Clock tolerance**: 6-hour epochs tolerate clock skew of up to ±3 hours (the overlap publish extends coverage to ±6 hours). Cleona's existing NTP sync (§2.4.1) keeps clocks within seconds — this is more than adequate.

#### 4.11.5 SignedEndpointRecord

The record stored on external substrates is encrypted and signed:

```
// Plaintext payload
endpoint_record = {
  addresses:    [PeerAddressProto, ...],   // current EXTERNALLY reachable addresses (public IPv4, global IPv6 only — no RFC 1918/RFC 4193 private addresses)
  seq:          uint64,                     // monotonically increasing
  published_at: uint64,                     // ms since epoch
  device_id:    bytes[32],                  // publisher's device ID
}

// Encryption (receiver-specific, only the contact can decrypt)
nonce      = random 12 bytes
ciphertext = crypto_aead_aes256gcm_encrypt(
    plaintext = serialize(endpoint_record),
    aad       = lookup_tag,
    key       = rendezvous_secret,
    nonce     = nonce
)

// Outer envelope (substrate-facing)
signed_endpoint_record = {
  nonce:      nonce,              // 12 bytes (AES-256-GCM)
  ciphertext: ciphertext,
  seq:        uint64,             // duplicated outside for cross-provider comparison
}
```

**Why AES-256-GCM**: Already bound in `sodium_ffi.dart` (no new FFI binding needed). Provides AEAD with AAD support (lookup-tag binding). The 12-byte nonce is safe here — each record uses a fresh random nonce and the key is pairwise-unique per contact pair, so nonce collision probability is negligible at this traffic volume (< 1000 encryptions per key per epoch).

**PQ residual risk (accepted)**: The key agreement (§4.11.3) relies on X25519-DH, which is not post-quantum secure. No PQ-safe non-interactive key agreement primitive exists today (ML-KEM requires a round-trip). The protected data (current IP addresses) is ephemeral (6h epoch rotation) and worthless for harvest-now-decrypt-later attacks. If a PQ-NIKE is standardized in the future, it can replace the X25519-DH step without changing the record format.

**What the substrate sees**: an opaque blob under an opaque tag. No IP addresses, no identity information, no correlation to Cleona.

**What the resolver does**: look up the contact's device list from the cached AuthManifest (§4.3), compute a device-scoped `lookup_tag` per device from the pairwise secret + epoch + `device_id` (§4.11.4), fetch each record, decrypt with `rendezvous_secret`, verify `seq` is highest seen, extract per-device addresses, attempt direct UDP contact.

**Cross-provider consistency**: `seq` is outside the ciphertext so the cascade can compare records from different providers without decrypting all of them. Highest `seq` wins. A provider returning a stale record (lower `seq` than one already seen from another provider) is ignored.

#### 4.11.6 Nostr Provider (NIP-01, NIP-33)

The first external substrate. Chosen for minimal integration effort, negligible traffic overhead, and no participation obligation (unlike Mainline DHT). Used for two publish categories: **(1) Contact-Rendezvous** (per-contact endpoint records, this section) and **(2) Binary Discovery** (network-wide software distribution records, §19.6.5).

**Identity**: a deterministic secp256k1 keypair derived per contact×device combination:

```
nostr_sk = HKDF-SHA-256(
    ikm  = pairwise_rendezvous_secret,
    salt = "cleona-nostr-v1",
    info = hex(own_device_id),
    length = 32
)
nostr_pk = secp256k1_pubkey(nostr_sk)   // x-only, 32 bytes
```

Each contact pair sees a different Nostr pubkey (different `pairwise_rendezvous_secret`), preventing cross-contact correlation by relay operators. The key is stable across publishes, which is **critical** for NIP-33: the relay replaces the previous event only when `(pubkey, kind, d-tag)` matches — a throwaway key would accumulate garbage entries instead of updating in place. **No** correlation to the Cleona Ed25519 identity. The real authenticity is inside the encrypted payload (`rendezvous_secret`).

**Event format** (NIP-01 + NIP-33 Parameterized Replaceable Events):

```json
{
  "id":         "<sha256 of serialized event>",
  "pubkey":     "<hex deterministic secp256k1 pubkey (per contact×device)>",
  "created_at": 1719561600,
  "kind":       30078,
  "tags":       [["d", "<hex(lookup_tag)>"]],
  "content":    "<base64(signed_endpoint_record)>",
  "sig":        "<schnorr signature with deterministic key>"
}
```

- **Kind 30078**: Parameterized Replaceable Event (NIP-33). The relay keeps only the latest version per `(pubkey, d-tag)` combination — no garbage accumulation, always-current endpoint.
- **Tag `["d", hex(lookup_tag)]`**: the relay indexes this for filter queries. The resolver subscribes with `{"#d": [hex(tag)], "kinds": [30078]}`.
- **Content**: base64-encoded `SignedEndpointRecord` (§4.11.5). Opaque to the relay.

**Relay selection**: 5–10 well-known public relays (`wss://relay.damus.io`, `wss://nos.lol`, `wss://relay.nostr.band`, etc.). Hardcoded initial set, user-configurable. Publisher pushes to all; resolver queries all in parallel, first valid hit wins.

**Protocol flow**:

Publish (one of Bob's devices goes online or its addresses change):
1. For each accepted contact:
   a. Derive deterministic Nostr keypair from `pairwise_rendezvous_secret` + `own_device_id`
   b. Compute device-scoped `lookup_tag` (current + next epoch, §4.11.4)
   c. Build `SignedEndpointRecord` with **this device's** current addresses + `device_id`
   d. Create Nostr event (kind 30078, d-tag = hex(lookup_tag), content = base64(record))
   e. Sign event with deterministic key
   f. WebSocket connect to each relay, send `["EVENT", event]`, await `["OK", ...]`, close
Each of Bob's devices publishes independently — there is no "primary publishes for all" coordinator.

Resolve (Alice cold-starts after 48h offline, Tier 3b):
1. For each unreachable contact:
   a. Look up AuthManifest (cached from last online session, or live DHT if reachable) → `authorizedDeviceIds[]`
   b. For each `deviceId`: compute device-scoped `lookup_tag` (current epoch, §4.11.4)
2. Query relays for all tags in parallel, send `["REQ", "sub1", {"#d": [hex(tag)], "kinds": [30078]}]`
3. First relay response per tag: parse content, decrypt with `rendezvous_secret`, verify `seq`
4. Send `["CLOSE", "sub1"]`, close WebSocket
5. Extracted per-device addresses → direct UDP contact attempt → back in the mesh
6. If current epoch yields no hits for a device, retry with previous epoch tag

**Traffic budget (per device)**: < 1 MB/day. Publish: 20 contacts × 2 epochs × 5 relays × ~1 KB per event = 200 KB per publish cycle. Each device publishes only its own addresses — traffic per device is unchanged from the user-level design. With 4h refresh interval (within 6h epoch) = ~1.2 MB/day worst case per device. Resolve: typically 1–2 unreachable contacts × 2 devices(avg) × 2 epochs × 5 relays × ~0.5 KB = < 20 KB per cold-start.

**Dependencies**: secp256k1 Schnorr signing (libsecp256k1 via FFI or pure-Dart implementation), WebSocket client (Dart standard library `web_socket_channel`), JSON serialization (trivial). No new native C shim required.

#### 4.11.7 Publish Triggers & Lifecycle

| Trigger | Action | Debounce |
|---|---|---|
| Startup (after §4.5 discovery-complete) | Publish current addresses to all providers for all contacts | none (first publish) |
| Network change (§4.9) | Republish with new addresses | 10 s (5 s after Liveness, ensures addresses are stable) |
| Periodic refresh | Republish to survive relay eviction | every 4 h (within 6h epoch) |
| Epoch boundary | Publish under new epoch tag, retain previous-epoch record | at epoch transition |
| Contact added/removed | Add/remove lookup tags from publish set | on contact-status change |

**Per-device independence**: every device in a multi-device setup (§7) publishes its own endpoint records independently. There is no coordinator or "primary publishes for all" pattern. Each device runs its own publish cycle on the triggers above, using its own addresses and its own `device_id` in the lookup tag (§4.11.4). This scales to the §7 limit of 5 devices without coordination overhead. On Android (in-process mode), the RendezvousManager is initialized per CleonaService — not gated by a "first service wins" check.

**Address filter**: before building the EndpointRecord, the publisher filters the address list to externally reachable addresses only: public IPv4 (STUN/UPnP-discovered `_advertisedPublicIp`, port-forwarded addresses), global IPv6 (not link-local `fe80:`, not ULA `fd`/`fc`). Private addresses (RFC 1918 `10.x`, `172.16–31.x`, `192.168.x`; RFC 4193 ULA) are excluded — they are unreachable from other networks and leak internal topology to Nostr relays. A node behind CGNAT that discovered its public IP via STUN publishes that mapped public IP (the CGNAT gateway's external address). A node with both a NAT-mapped public IPv4 and a global IPv6 publishes both. The publish is skipped only when zero externally reachable addresses remain after filtering — a rare case (isolated LAN, double-NAT without STUN success, no IPv6).

**Shutdown**: no explicit unpublish needed. Records become obsolete via `seq` monotonicity (the next publish supersedes) and relay-side eviction (NIP-33 replaceable events are overwritten on next publish from the same deterministic pubkey+d-tag).

**Publish budget (per device)**: for N contacts, each publish cycle generates `N × 2` (current + next epoch) records across `M` relays = `2NM` WebSocket messages. At N=50, M=5: 500 messages × ~1 KB = ~500 KB per cycle per device. Acceptable even on mobile data (< 2 MB/day at 4h refresh). Total across D devices: `2NMD` — at D=5 (maximum): 2.5 MB/cycle, ~10 MB/day worst case, distributed across independent devices.

#### 4.11.8 Future Substrates (Planned)

The `RendezvousProvider` interface is designed for multiple substrates. Only the Nostr provider (§4.11.6) is implemented in V3.1.x. The following are architecturally planned and will be added as separate providers behind the same interface:

**(a) Tor Onion (§4.11.8a)** — requires Arti (Rust Tor client) integration via C-shim or sidecar process. Provides the cleanest resolve (no IP leak to relays) and doubles as transport layer for Nostr lookups (Nostr-over-Tor). Highest implementation effort. Additionally serves as **Hardening Layer 3** (§4.11.1): routing all resolve traffic through Tor so the relay/DHT-node cannot see Alice's IP or her interest in a specific tag.

**(b) Mainline DHT BEP44 (§4.11.8b)** — maximum reach (millions of BitTorrent nodes, un-censorable). However: full DHT participation generates 70–250 MB/day background traffic (DHT routing maintenance from millions of foreign nodes), making it impractical as always-on substrate on mobile. Viable only as **on-demand fallback**: bootstrap into DHT, resolve, disconnect. Loses the publish side (records not durable without participation). BEP44 mutable items use ed25519 (not secp256k1), requiring a separate signing path.

**(c) Email Dead-Drop (§4.11.8c)** — lowest priority. Operationally fragile: free email accounts require phone verification, automated access triggers lockouts, rate limits are aggressive. Useful only as last-resort "nothing else works" substrate in extreme censorship environments.

**Substrate cascade**: all available providers are queried in parallel (Happy-Eyeballs). The first valid, signature-verified record with the highest `seq` wins. A provider being blocked in the current network (Nostr relays firewalled, Tor blocked) does not delay the cascade — `isAvailable` returns false and the provider is skipped.

#### 4.11.9 Infrastructure Rendezvous

The contact-scoped rendezvous (§4.11.3–§4.11.8) requires a pairwise secret between two contacts. Infrastructure nodes (bootstrap relays, community relays) have no user identity and no contacts — they cannot participate in contact rendezvous. Yet they are the network entry points that nodes behind NAT depend on. If Bootstrap's IP changes while a client is offline, the client has no way back into the mesh.

**Solution**: any node with at least one externally reachable address publishes an Infrastructure Endpoint Record under a network-wide tag derived from the network secret (§4.10). Every network member can resolve this tag to find current entry points.

```
// Lookup tag — identical for ALL infra publishers per epoch
infra_tag = HKDF-SHA-256(
    ikm  = network_secret,
    salt = "cleona-rv-infra-v1",
    info = epoch_string,
    length = 32
)

// Encryption key — any network member can decrypt
infra_key = HKDF-SHA-256(
    ikm  = network_secret,
    salt = "cleona-rv-infra-key-v1",
    info = epoch_string,
    length = 32
)

// Nostr identity — deterministic per device (different pubkeys
// → NIP-33 does not overwrite across devices → relay returns ALL infra nodes)
nostr_sk = HKDF-SHA-256(
    ikm  = network_secret,
    salt = "cleona-nostr-infra-v1",
    info = hex(own_device_id),
    length = 32
)
```

**Who publishes**: every node that has at least one externally reachable address after the address filter (§4.11.7) — public IPv4 via STUN/UPnP or global IPv6. This naturally includes bootstrap nodes (always publicly reachable), port-forwarded desktops, and IPv6-capable mobile nodes. Headless daemons (`cleona-headless`) participate without a user identity — only the network secret and the device's own nodeId are needed.

**Who resolves**: any node where Tier 1–3 of the discovery cascade (§4.5) failed. The infra-resolve runs in **parallel** with the contact-resolve (§4.11.4) inside Tier 3b.

**NIP-33 multi-publisher**: all infra nodes publish under the **same** d-tag (same `infra_tag` per epoch) but with **different** Nostr pubkeys (different `own_device_id` → different `nostr_sk`). NIP-33 replaces only per `(pubkey, kind, d-tag)` — different pubkeys produce separate events. The resolver query `{"#d": [hex(infra_tag)], "kinds": [30078]}` returns events from ALL infra nodes. Each event decrypts independently with `infra_key`.

**EndpointRecord format**: identical to §4.11.5, encrypted with `infra_key` instead of `rendezvous_secret`, AAD = `infra_tag`. The `device_id` field identifies the publishing node.

**Publish triggers**: same as §4.11.7 (startup, network change, 4h refresh, epoch boundary). No contact-add/remove trigger (infra is contact-independent).

**Security**: anyone who knows the network secret can resolve all infra nodes. This is by design — the network secret is the Closed Network admission token (§4.10). An outsider sees opaque blobs under opaque tags on Nostr. The infra tag does not correlate with any contact-rendezvous tag (different salt, different IKM path).

**Headless daemon integration**: `cleona-headless` initializes an `InfraRendezvousManager` at startup (no `RendezvousManager` — no user identity, no contacts). It publishes the daemon's externally reachable addresses under the infra tag. This is the only rendezvous path available to identity-less infrastructure nodes.

**End-to-end cold-start example**: Alice's phone was offline over the weekend. Monday morning: Tier 1–3 fail (all cached IPs stale). Tier 3b fires both paths in parallel: (A) contact-resolve for her contacts → succeeds if any contact has a public IP and published; (B) infra-resolve → finds Bootstrap's current public IP → connects → enters the mesh → DV routing delivers the rest.

#### 4.11.10 First-Contact Rendezvous (URI-scoped) (V3.1.116)

Contact rendezvous (§4.11.3) requires a pairwise secret between existing contacts; infrastructure rendezvous (§4.11.9) covers only publicly reachable infra nodes. Neither serves the **first contact between two fresh devices**: two phones on mobile data, no mesh membership, exchanging a ContactSeed URI over an out-of-band channel (messenger, email, note). The First-Contact Rendezvous closes this gap using the same substrate, record format (§4.11.5), and epoch scheme (§4.11.4) — only the key material differs: the shared secret is the random 32-byte nonce `r` embedded in the clipboard/share URI (§8.1.1). Possession of the URI **is** the access authorization.

```
fc_tag(role)  = HKDF-SHA-256(ikm=r, salt="cleona-rv-fc-tag-v1",  info=epoch + "/" + role)   // role ∈ {"owner","scanner"}
fc_key        = HKDF-SHA-256(ikm=r, salt="cleona-rv-fc-key-v1",  info=epoch)
fc_nostr_sk   = HKDF-SHA-256(ikm=r, salt="cleona-nostr-fc-v1",   info=hex(own_device_id))
```

**Roles.** The URI issuer ("owner") publishes its externally reachable addresses (address filter of §4.11.7) under the owner tag and polls the scanner tag (30s initial, 90s interval, backoff to 10min after 30min without a hit — no flooding). The URI recipient ("scanner") resolves the owner tag on paste (fresher addresses than the URI's `a=` snapshot), publishes its own record under the scanner tag, and re-resolves before each CR retry (piggybacked on the existing CR retry timer — no additional timer). Multiple scanners of the same URI coexist via distinct device-derived Nostr pubkeys (NIP-33 multi-publisher, same pattern as §4.11.9).

**Simultaneous-open.** When the owner discovers a scanner record, it sends PINGs to all scanner addresses while the scanner is sending its CR toward the owner — both carrier firewalls open (§4.7 simultaneous-open). This makes direct mobile↔mobile IPv6 first contact work **regardless of carrier inbound filtering**, with zero Cleona infrastructure involved.

**Layering.** The record maps **device → addresses** (`device_id` in every EndpointRecord), consistent with the IP–device–user layering: rendezvous never references user identity; the user layer enters only afterwards, inside the KEM-encrypted CONTACT_REQUEST.

**Lifetime & privacy.** Sessions are persisted per profile and expire hard **72h** after ContactSeed creation (`t`); they end early once the first CR of this exchange is received (owner) or confirmed (scanner). After expiry neither side publishes or polls — a leaked or archived URI cannot be used to track addresses beyond the window. Records are encrypted with `fc_key`; relays see opaque blobs under opaque tags, uncorrelated with contact- or infra-tags (distinct salts, distinct IKM paths).

**Scope.** Like all of §4.11: pure `lookupTag → encryptedEndpoint` directory. No message traffic, no CR content over the substrate.

#### 4.11.11 Reactive Resolve Triggers (V3.1.117)

Once initial discovery has completed, a node must re-resolve contacts that became unreachable *later* — not only at first discovery. §4.11.4/§4.11.9 describe *how* a record is resolved; this subsection specifies *when* `resolveUnreachableContacts` is invoked reactively. Three edge-triggered events (no timers):

1. **`onRetryExhausted`** — when `sendToDevice` exhausts the full DV cascade for a contact without a `DELIVERY_RECEIPT` (§5.10.3, the Layer-3 edge). The contact is marked unreachable; the resolve is batched.
2. **`onNetworkChanged` + 8 s** — piggy-backed onto `_tryProactiveRendezvous`, so a network re-join immediately re-resolves contacts that were unreachable under the old network context.
3. **`onDiscoveryComplete`** — once at the end of every discovery cycle.

**Gating (amplification protection):**
- **Unreachable filter:** only contacts currently flagged unreachable are resolved (no re-resolve of healthy contacts).
- **15 min cooldown per contact:** a contact resolved <15 min ago is not re-resolved (rate-limit against Nostr provider load + epoch-rotation cost).
- **60 s batch gate:** resolve requests within a 60 s window are coalesced into a single provider query batch (Nostr resolve collect-window 1.5–2 s at highest seq, §4.11.6).

The Tier 3b external rendezvous is **not** decoupled from the cascade (rejected alternative): resolve runs inside the existing discovery/edge plumbing so it inherits the same edge-trigger discipline as §5.1 (no timer-based retry). Fragment-NACK (CFNK) is orthogonal and analysed separately.

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
      → direct-target attempt (routing-table addresses, fire-and-forget)
      → defaultGateway as last resort
      → returns true on DELIVERY_RECEIPT, false on cascade-exhausted

Layer 3 — Offline Delivery (§5.4 + §5.5 + §5.6)
  if Layer 2 returned false for ALL resolved devices (or Layer 1 was empty):
    → Erasure-coded backup on K=10 closest DHT nodes (§5.4)
    → S&F copy on up to 3 contact peers (§5.5, receiver-validated)
    → For First-CRs (no shared contacts exist): First-CR-Mailbox on SeedPeers (§5.5b)
    → Mailbox entry (§5.6) for receiver pull
    → Sender is done if placement succeeded; on placement failure the message is parked in the outbox (§5.1) for re-attempt
    → Receiver will poll on next coming-online
```

**Comparison with v2.2's "Direct → Relay → S&F" pattern**:
- v2.2 chained Direct/Relay/S&F as three attempt stages WITHIN the send operation
- v3.0 separates them by **responsibility**: the identity layer determines the WHO (which devices), the routing layer the HOW (which path), and S&F+Mailbox the WHAT-IF-OFFLINE (asynchronous fallback)

**Important**: in V3.0, Direct and Relay are both sub-strategies inside `sendToDevice` (§4.4) — the distinction is transparent to the service layer. The caller only sees "sendToDevice success" or "sendToDevice failed".

**Sender-side retries no longer exist.** Once all Layer-2 routes are exhausted and Layer-3 (S&F + Mailbox) has been triggered, the sender has done its duty. The receiver will pull the message from its mailbox on next coming-online. The outbox (see below) provides **crash-safety** rather than retry semantics: every ACK-worthy message is persisted at send time and removed when the corresponding `DELIVERY_RECEIPT` arrives. If the daemon is killed between Layer-2 dispatch and Layer-3 placement — or between Layer-2 dispatch and receipt of the `DELIVERY_RECEIPT` — the outbox entry survives and the full cascade is re-attempted once on the next `onNetworkChanged` edge. This is distinct from v2.2's `MessageQueue`, which retried against reachable network on a timer.

**Persistent outbox (crash-safe delivery).** Every ACK-worthy message is written to the local **outbox** (`outbox.json.enc`, encrypted, survives daemon crashes) at send time. When the corresponding `DELIVERY_RECEIPT` arrives, the entry is removed. If the `DELIVERY_RECEIPT` never arrives — because the recipient was unreachable, the relay path failed, or the daemon was killed before the ACK timeout could trigger Layer 3 — the outbox entry persists. On daemon restart (or on any `onNetworkChanged` / first-peer-confirmed / contact-endpoint-confirmed / verified-inbound-from-recipient edge — the last one (F3′, V3.1.118) fires user-scoped when a fully verified application frame arrives from a user with parked entries, covering the recipient reappearing while the sender's own connectivity never changed; gated 60 s per sender), the outbox is flushed: each entry re-attempts the **full cascade** (Layer 1+2 first — the recipient may now be online — then Layer 3 on Layer-2 failure). On L1+2 send success, the message status is set to `sent` (single checkmark) and the AckTracker is registered for proper receipt tracking — the outbox entry is retained until the actual `DELIVERY_RECEIPT` confirms delivery (V3.1.130+; prior: L1+2 success falsely set `delivered`). On L3 placement, the entry is cleared (`queuedOffline`); on continued failure (still zero peers), the entry is retained for the next edge. After 7 days (`_offlineTtlMs`), undelivered entries are marked `expired` — the user can manually retry or delete. This covers three previously distinct failure modes in a single mechanism: (a) zero sender connectivity (airplane mode, dead network), (b) daemon crash between Layer-2 dispatch and ACK timeout, and (c) daemon crash between ACK-timeout-triggered Layer-3 and successful placement. The outbox is **not** a retry queue: there is no timer, no periodic retry against reachable network, and no re-send of an already-placed message.

**Cascade latency budget.** Layer 2 attempts routes sequentially — each route waits for `DELIVERY_RECEIPT` or ACK timeout (`max(2 × RTT × hopCount, 8s)`, capped 30s) before trying the next. With up to 3 alive routes per device, the worst-case Layer-2 latency per device is ~30s (typical: 8–16s). Layer 3 begins only after Layer 2 is exhausted for ALL resolved devices. For latency-sensitive sends (call setup), `sendToUser` accepts `requireOnline=true` — Layer 3 is skipped entirely and the call returns `false` immediately on Layer-2 failure. **Speculative Layer-3 placement is intentionally omitted.** Placing erasure fragments while Layer 2 is still running would waste storage bandwidth for messages that may yet be delivered directly. The sequential model trades worst-case placement latency (~30s) for storage efficiency — fragments are placed only on confirmed send failure. This is acceptable because the delay affects only the *placement* timing, not the *delivery* timing to the receiver.

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

**Relay throughput control (v3.0):** the V3 relay-forward path is bounded by the wire-layer rate limiter at the relay node — relayed packets carry the **originator's** Device-ID in the outer packet, so the per-source and global limits (§13.1.3) apply to the origin before any forward. (The v2.2 "in-flight storage budget" does not exist in the V3 forward path — doc-vs-code drift corrected in the D5 review; the legacy `RelayBudget` class is test-only.) **D5:** relay forwards for origins that are not *introduced* (§13.1.3 collective quota) additionally share a collective forward slice of **2 MB + 1,000 messages per minute**, so minted origin IDs cannot multiply relay amplification beyond that slice. Counter: `poolDropsRelay`.

**Relay-Route-Learning (V3 — ACK-based)**:
- The sender learns successful relay routes via RELAY_ACK
- Future sends use the learned route directly — no fresh discovery
- On RELAY_ACK timeout: the relay route is marked DOWN (surgical, §4.4)
- No timer-based expiry — only failures cause marking

**Reverse-Relay-Path-Learning (V3.1)**:
When a node receives a relayed packet (`hopCount > 0`) from sender S, the transport-layer source address identifies the relay node R. The receiver records a DV relay-route hint: "S is reachable via R" with `cost = connectionTypeCost(self→R) + 10` (relay penalty), `ackConfirmed=false`. This hint enables reply-path symmetry for NAT-asymmetric scenarios: a mobile device behind CGNAT sends via Bootstrap with `hopCount=0`; Bootstrap relays to Alice with `hopCount=1`; Alice learns "mobile is reachable via Bootstrap" and can use Bootstrap as relay for the reply. The hint does NOT override existing alive confirmed routes — it is a low-priority fallback tried after confirmed routes in the `sendToDevice` cascade (§5.1 Step 1). If an alive route via the same relay already exists, only `lastConfirmed` is refreshed. The hint follows standard DV route aging and pruning.

**Chunking for large payloads**: when a packet to be relayed exceeds `relayBudget.maxFrameSize` (300 KB), it is chunked and forwarded in multiple parts — with its own reassembly semantics on the receiver.

### 5.4 Erasure Coding (Offline Delivery)

If the receiver is offline, the message is stored on the K=10 closest DHT nodes as Reed-Solomon erasure-coded fragments. The receiver pulls the fragments on coming online and reassembles them.

**Parameters**:
- **N=10, K=7** (Reed-Solomon code rate): 10 fragments are produced, at least 7 must be available for reassembly
- **1.43× storage overhead** (10/7)
- **Resilience**: up to 3 fragment nodes may fail

**Fragment storage**:
- Key: `Hash("fragment" || messageId || fragmentIndex)`
- Fragments are placed on the K=10 closest DHT replicators of the recipient's **mailbox-ID** (the receiver's fragment lookup is likewise mailbox-ID-keyed; the `Hash("fragment"…)` key above addresses the individual fragment record, not the replicator locus)
- Max 5 copies per fragment in the network (storage-budget limit)

**Encoded payload (V3.0)**: each fragment carries a slice of the complete V3 `NetworkPacket` bytes (Outer-Device-Sig + KEM-payload + Inner). The sender does not build a separate "offline-delivery envelope" — the canonical packet is identical-or-equivalent to one of the per-device packets already built for direct delivery in §2.4.

- For **ApplicationFrame** payloads (User-KEM-targeted, see §3.3): one erasure-coded copy per recipient **user** suffices, because the inner KEM-ciphertext is identical across all devices of the recipient user (KEM is User-PK-keyed). All devices polling the user's mailbox find the same fragments and reassemble independently.
- For **InfrastructureFrame** payloads on the §2.3.5 Identity-Layer Infrastructure list (`RESTORE_BROADCAST`, Emergency `KEY_ROTATION_BROADCAST`): KEM is **Device**-PK-keyed (§3.5b), so the encoded blob can only reach one specific device. The sender takes the per-device packet built for the contact's first-resolved device as the canonical erasure-source; other devices of the same contact pick up via subsequent Direct-Send retries or via S&F on contact peers (§5.5).

**Receiver polling**:
- At daemon startup: mailbox + fragment lookup for own UserID
- `Hash("fragment" || messageId || index)` for `index ∈ [0..9]` queried in parallel
- As soon as 7 fragments are available: Reed-Solomon decode → re-inject the reassembled `NetworkPacket` bytes into the standard receive pipeline (§2.4 Receiver pipeline). Outer-Device-Sig-Verify, KEM-Decap, Inner-User-Sig-Verify (or Inner-Device-Auth for InfrastructureFrame), dispatch run identically to a UDP-received packet — no separate verification path.

**Lifetime**: fragments are stored for 7 days, after which replicator nodes verify them. If the receiver has not picked up: the fragment is pruned (storage recovery).

**Erasure is push-based**: the sender places fragments on send-failure, not on every send. Storage efficiency stays bounded. If erasure placement fails (**fewer than K=7 distinct fragment indices confirmed** after the wave budget below, or zero DHT peers reachable at placement time), the serialized packet is parked in the persistent outbox (§5.1) and placement is re-attempted on the next `onNetworkChanged` edge — the sender does not silently drop unplaceable messages.

**ACK-verified placement (D-c fix, V3.1.120):** the sender counts `FRAGMENT_STORE_ACK`s per **distinct fragment index** (matched on `(messageId, fragmentIndex)` — no protocol change; replicators have always sent these ACKs on successful store, the sender previously discarded them). Wave 1 is the classic 10-fragments-×-3-replica spread; the sender then waits up to 8 s (edge-driven completers, no polling). Placement succeeds only when **≥K=7 distinct indices** are confirmed by at least one replicator each; 7–9 confirmed logs an "erasure placement fragile" warning. Unconfirmed indices are re-sent in up to 2 additional waves (+1 copy per fragment per wave, respecting the 5-copies-per-fragment bound) to fresh replicators from a deeper closest-peer pool (30, confirmed-first per the §5.5 Phase-1 ranking rationale). Below K after the wave budget, placement counts as **failed** and the message is parked in the outbox unless §5.5 S&F succeeded. Pre-fix the placement was fire-and-forget and "success" meant "dispatched" (2026-07-03 field evidence: 222 FRAGMENT_STOREs sent, 0 received by the addressed replicator, unnoticed — the message was unreconstructable while the sender reported `queuedOffline`). The same ACK now also cancels the replicator-side proactive-push retry backoffs (previously a dead code path — every replicator burned all 3 push attempts even after the owner had acknowledged).

### 5.5 Store-and-Forward on Contact Peers

In addition to erasure-coded fragments, on failure the sender also stores a **complete copy** of the message on up to 3 **contact peers** — peers from the sender's own accepted-contact list that have alive routes. The sender selects by route quality (most alive routes first), falling back to well-connected routing-table peers if no contacts are currently reachable. This way the message is held on intentionally trustworthy nodes, not only on random DHT replicators.

**Sender-side peer selection** (`_findMutualPeerDeviceIds`):
- **Phase 1**: Iterate own accepted contacts (excluding the recipient), filter for alive DV routes, rank by number of alive routes, pick top 3.
- **Phase 1 ranking (V3.1.117 field amendment)**: candidates that are *confirmed* (bidirectional UDP contact within the confirmation TTL) rank strictly above candidates that merely have alive DV routes — relay routes without traffic are never pruned and can point at devices that have been offline for days (2026-07-03 field evidence: an S&F copy was placed on a days-dead contact device).
- **Phase 2 (always appended)**: Confirmed routing-table peers (e.g. Bootstrap) are **always included** in the candidate pool after Phase 1 candidates, ranked by alive-route count. Phase 1 contacts may all reject the store because the recipient is not *their* contact (receiver-enforced criterion 3); the wave-retry mechanism (F1) then falls through to Phase 2 candidates in the same pool. Pre-fix (V3.1.124), Phase 2 was gated on `candidates.isEmpty` — if Phase 1 found *any* contact with an alive route, Bootstrap was never even tried, making S&F undeliverable when no Phase 1 candidate was mutual (2026-07-06 field evidence: Martin→Alice, 0/6 stores accepted, Bootstrap online and willing but excluded). **Infrastructure exception (F4, V3.1.117):** headless/bootstrap nodes accept `PEER_STORE` for **any** recipient within the standard budgets (criterion 3 below does not apply to them — they have no contacts by design). This mirrors the §5.5b First-CR-Mailbox precedent (SeedPeers already store first-CRs for non-contacts, budgeted).
- **Observability**: if the total number of selected peers (Phase 1 + Phase 2) is less than 3, the sender logs a warning (`S&F: only N/3 mutual peers — offline delivery fragile`). In small networks where only one or two relay peers are available, S&F redundancy is reduced and delivery depends on those peers remaining online until the recipient polls. The warning aids operational diagnosis without altering the placement logic.

**Storage-peer validation (receiver-side):** On receiving a `PEER_STORE` infrastructure message, the storage peer validates:

1. Valid Closed-Network HMAC (official builds)
2. Valid outer Device-Sig (sender authentication)
3. `recipientUserId` is a **known contact** of the storage peer (exists in the peer's local contact store with status `accepted`)
4. Per-recipient budget: max 30 messages
5. Per-sender rate limit: max 10 stores per hour
6. Dedup via `SHA-256(wrappedEnvelope)`

Criterion 3 transforms "mutual" from a sender-side heuristic into a **receiver-enforced property**: only peers that are genuinely contacts of both sender and recipient will accept a store. No contact-list exchange is needed — the check is a local lookup in the storage peer's own contact DB. Stores for unknown recipients are rejected with `PEER_STORE_ACK{accepted:false}`; the sender detects this (or a missing ACK) and tries the next candidate. This is consistent with the First-CR-Mailbox (§5.5b), which already validates `recipient_device_id is in the SeedPeer's routing table`. **Exception:** infrastructure nodes (headless/bootstrap, `acceptAnyPeerStore`) skip criterion 3 and accept within budgets — see the Phase-2 infrastructure exception above.

**ACK-verified placement (F1, V3.1.117):** the sender assigns a distinct `store_id` per candidate, waits up to 8 s for each `PEER_STORE_ACK`, counts only `accepted:true`, and draws replacement candidates in waves (pool 3×3) until 3 confirmed copies exist or the pool is exhausted. Placement counts as successful from ≥1 confirmed copy; anything less than 3 logs an "offline delivery fragile" warning. Pre-F1 the store was fire-and-forget and "success" meant "attempted" — rejected or lost stores were indistinguishable from placed ones (2026-07-03 field evidence: all three copies of a message were rejected/lost while the sender reported `queuedOffline`).

**S&F storage**:
- Same inner frame (`ApplicationFrame`) as the original send target
- Outer wrap to the storage peer as a `PEER_STORE` InfrastructureFrame (Device-KEM-encrypted)
- The storage peer holds the message for at most 7 days or until the receiver retrieves it

**Receiver pull**:
- On coming online: `PEER_RETRIEVE` to all confirmed peers
- Confirmed peers check their local S&F store and return stored messages
- Dedup via `messageId`

**Connection to the disappearance of MessageQueue**:
- v2.2 additionally maintained a local MessageQueue at the sender for 7-day retry of the same message
- v3.0 removes this queue entirely — S&F takes over the responsibility
- Benefit: receiver-pull instead of sender-push, less traffic, less ID confusion

**Storage limit**: per receiver, max 30 stored messages on a single storage peer. On overflow: oldest-first eviction.

### 5.5b First-CR-Mailbox (Store-and-Forward for Non-Contacts)

Regular S&F (§5.5) requires contact peers (peers that are contacts of the recipient, enforced receiver-side). For First-Contact-Requests this precondition is never met — the sender and receiver do not know each other yet. The First-CR-Mailbox extends S&F to cover this gap.

**Mechanism**: The SeedPeers listed in the ContactSeed (§8.1.1) serve as the "contact peers" for the First-CR. They are the only nodes known to both sides: the ContactSeed-generator selected them from its routing table, and the scanner learned about them from the QR/URI. Any node can be a SeedPeer — there is no special bootstrap role, no hardcoded addresses, no central infrastructure.

**New message types** (Infrastructure-Level, §2.3.5 selector list):

| Type | Code | Direction | Purpose |
|---|---|---|---|
| `MTV3_FIRST_CR_STORE` | 222 | Scanner → SeedPeer | Request to store an encrypted First-CR |
| `MTV3_FIRST_CR_STORE_ACK` | 223 | SeedPeer → Scanner | Confirmation of storage |
| `MTV3_FIRST_CR_DELIVER` | 224 | SeedPeer → Recipient | Push stored CRs on recipient connect |

```protobuf
message FirstCrStore {
  bytes recipient_device_id = 1;  // 32B: delivery target
  bytes encrypted_payload = 2;    // opaque KEM-encrypted First-CR (InfrastructureFrame bytes)
  int64 stored_at_ms = 3;
  bytes sender_device_id = 4;     // 32B: for dedup and rate-limiting
}

message FirstCrDeliver {
  repeated bytes encrypted_payloads = 1;  // stored CRs, each an opaque InfrastructureFrame blob
}
```

**Flow**:

1. Scanner (A) builds First-CR (KEM-encrypted under B's Device-KEM-PK, see §8.1.1 rev3 step 6)
2. A sends First-CR to recipient (B) via normal routing cascade (§4.4 sendToDevice)
3. If no `DELIVERY_RECEIPT` after 15 seconds: A sends `FIRST_CR_STORE` to each reachable SeedPeer from the ContactSeed. `FIRST_CR_STORE` is sent as a **direct infrastructure message** (`sendInfraTo`) to **every known address** of each seed peer (IPv4 + IPv6, private + public — fire-and-forget to all, first-ACK-wins) — **not** via the DV relay cascade (`sendToDevice`). This multi-address send is critical for DS-Lite/CGNAT scanners: the seed peer's private IPv4 is unreachable from mobile data, but its global IPv6 is. This is architecturally critical: the D3 admission gate (§13.1.2) applies to relay candidacy, but a direct infra send to a known address bypasses the relay path entirely. The scanner knows the seed peer's addresses from the ContactSeed; it does not need to relay through the seed peer to reach it.
4. SeedPeer validates (see acceptance criteria below) and stores; responds with `FIRST_CR_STORE_ACK`. Receipt of ≥1 ACK transitions the CR to `storedForDelivery` on the scanner — the canonical success signal for asynchronous ContactSeeds (§8.1.1 CR Bootstrap Delivery Lifecycle).
5. When B sends any firstParty packet to the SeedPeer (PONG, DV-Update, DHT-Request — **not** relayed packets): SeedPeer checks mailbox for B's `deviceId` → pushes `FIRST_CR_DELIVER`
6. B receives, decrypts with Device-KEM-SK, processes as normal First-CR (§8.1.1 step 8)

**Acceptance criteria** (all must be true for a SeedPeer to store):

1. Valid Closed-Network HMAC on the outer packet (only official builds)
2. `recipient_device_id` is in the SeedPeer's routing table — the SeedPeer "knows" the recipient. This is guaranteed by construction: the ContactSeed-generator selected this SeedPeer from its own routing table (freshness < 30 min), so the SeedPeer has bidirectional contact with the generator's device.
3. Budget: max 10 CRs per recipient, max 1 MB total mailbox per node
4. Rate limit: max 5 `FIRST_CR_STORE` per sender per hour
5. No duplicate: `SHA-256(encrypted_payload)` dedup

**Storage**:

- TTL: 7 days (consistent with regular S&F §5.5 and erasure §5.4)
- Cleanup: lazy on access + periodic GC (1-hour interval)
- Persistence: in-memory + write-through to disk (survives daemon restart)

**Security**:

- **Confidentiality**: SeedPeer sees only `recipient_device_id` and an opaque KEM-encrypted blob. No plaintext, no UserIDs, no message content.
- **Integrity**: the encrypted CR contains the sender's User-Signature — verified by recipient on decryption (§8.1.1 step 8).
- **DoS**: rate-limiting + budget-cap + Closed-Network HMAC. An attacker needs the Network Secret to even send packets.
- **Privacy**: `deviceId ≠ userId ≠ nodeId` (§4) — SeedPeer cannot correlate the delivery target to a user identity.
- **No trust center**: every node participates equally. If a SeedPeer is compromised, it cannot read stored CRs (KEM-encrypted) and can at worst withhold delivery — mitigated by redundancy (CR is stored on **all** reachable SeedPeers from the ContactSeed).

**No special node role**: The First-CR-Mailbox is a protocol-level capability of every Cleona node, not a special-purpose service. A desktop node that runs 24/7, a friend's phone, a community relay — any node that appears as a SeedPeer in someone's ContactSeed participates automatically. Bootstrap is one such node today; when it is decommissioned, any other long-running node fills the same role without code changes.

### 5.6 Mailbox (UserID-based Pull)

Every user has a **virtual mailbox** in the DHT — addressed via `mailbox_id_primary` and `mailbox_id_fallback`. The receiver polls on coming online.

**Mailbox-ID derivation**:
```
mailbox_id_primary  = SHA-256("mailbox" || ed25519_user_pubkey)        // 32 bytes
mailbox_id_fallback = SHA-256("mailbox-nid" || userId)                 // 32 bytes
```

- **Primary**: pubkey-based, used by senders that already know the receiver's pubkey (contact store)
- **Fallback**: UserID-based, used by senders that do not yet have the pubkey (e.g. first KEM encapsulation toward a new contact)

The receiver polls **both** (primary + fallback) on every mailbox poll, so no send is lost.

**Key-rotation transition (§7.4b):** when the user's Ed25519 key rotates, `mailbox_id_primary` changes (new pubkey → new hash). Contacts that still cache the old pubkey will store under the old primary ID until they refresh via Auth-Manifest (up to 20 hours). To prevent message loss during this window, the receiver retains the **previous primary mailbox ID** and polls it alongside the current primary + fallback for **7 days** post-rotation (matching the mailbox-storage lifetime). After 7 days, the old primary is dropped — any undelivered messages stored there have expired on the DHT side anyway. Implementation: `_pollMailbox()` maintains a `_previousMailboxPrimary` field, set during key rotation in `_onKeyRotated()`, cleared after 7 days.

**Mailbox storage**:
- Key: mailbox_id_*
- Value: small per-recipient records keyed by `mailboxId` — encrypted fragments (erasure path) or a wrapped envelope (S&F). The hosting node learns only the recipient `mailboxId` and a `messageId`; the **senderUserId, message type and content stay inside the KEM-encrypted payload** and are not visible to the host.
- The receiver then fetches and decrypts the full message via S&F pull or fragment reassembly

**Polling schedule** (event-driven, not periodic):
- At daemon startup: aggressive polling, 10× every 3s after discovery-complete (~30s total)
- After restore broadcast: aggressive polling, 10× every 3s
- On `onNetworkChanged`: one-shot re-poll (edge-triggered, no timer)
- Steady state: **push-first** — relay nodes forward fragments immediately (< 1s); **no timer-based polling** (Arbeitsregel #5)

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
- Timeout = max(2 × RTT + 50ms, floor) — Direct: floor 500ms (LAN, RTT<50ms) / 2s (WAN), Relay (hopCount>1): floor 8s
- On timeout: per-route failure counter +1
- After 3 consecutive timeouts on the same route: route DOWN (surgical)

**Important**: NO timer-based expiry. Routes live until they accrue 3 ACK timeouts. This prevents short burst failures (e.g. WiFi glitch) from prematurely deleting routes.

**Fragment-NACK** (CFNK, "Cleona Fragment Negative ACK"):
- Used with app-level fragmentation (>1200 bytes → fragmented into 1200-byte pieces)
- The receiver collects fragments; the reassembly buffer is keyed by `(senderDeviceId, messageId)`
- If after 500ms a fragment is missing: NACK with `missingFragmentIndices`
- The sender resends the missing fragments
- NACKs continue with exponential backoff (500ms→750ms→1s→1.5s→2s cap) until reassembly completes or hard timeout (10s) expires — no fixed retry limit, but bounded by the hard timeout (V3.1.92+, previously capped at 3 retries)
- Sender-side fragment cache (30s TTL, 500-entry cap) is refreshed on each NACK receipt, staying alive as long as the receiver actively requests retransmissions. When the cap is reached, the oldest entry is evicted; the NACK handler gracefully skips missing cache entries (the upper-layer retry mechanism handles full retransmission)
- Inter-fragment pacing: 2ms (≤5 fragments), 4ms (>5 fragments) to reduce burst loss at receiver kernel buffers

**App-level UDP fragmentation** (V3):
- Payload >1200 bytes → fragments of ≤1200 bytes
- Max 255 fragments per application frame (= ~300 KB max)
- Each fragment is an own UDP packet with fragment header (`groupId`, `index`, `total`)
- Reassembly on the receiver after all fragments arrive or after NACK retry

**Message-status lifecycle** in the UI:
- `pending` — created by the sender, not yet sent
- `sent` — UDP send completed
- `delivered` — DELIVERY_RECEIPT received (at least one)
- `queued_offline` — Layer-3 artifacts placed (S&F/erasure/mailbox); awaiting receiver pull, clock running against the 7-day TTL
- `failed` — Layer-3 placement could **not** be performed (zero sender connectivity, or daemon crash between Layer-2 dispatch and Layer-3 placement); the serialized packet is held in the persistent outbox (§5.1) and re-attempts the full cascade on the next `onNetworkChanged` edge
- `expired` — set **locally** by a timestamp comparison (no network traffic) when a `queued_offline` message reaches the 7-day TTL with no DELIVERY_RECEIPT; the UI offers a resend
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

**Trigger**: an incoming packet from `senderDeviceId == X` fails Outer-Device-Sig verification against the cached Device-Sig PK for X (`PeerInfo.deviceEd25519PublicKey` / `deviceMlDsaPublicKey` per §3.5 Welle-3 layout), regardless of whether the PK was learned `firstParty` (direct exchange) or `thirdParty` (gossip/relay). The HMAC already proves network membership; a sig mismatch on a peer with *any* cached PK almost always means key rotation (profile wipe, device restart, key regeneration), not malice.

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

After 3× ACK timeout on the cheapest route, the AckTracker marks that route DOWN (surgical, §4.4) and `sendToDevice` falls through to the next-cheaper route — up to 3 packets there. Stage 3 reuses the existing DV cascade unchanged. When the entire DV route cascade is exhausted without a DELIVERY_RECEIPT, `onRetryExhausted` fires and the message enters the Layer-3 offline path: Store-and-Forward placement on mutual contact peers plus Reed-Solomon erasure coding on DHT peers (§5.4–§5.5). If the offline placement itself fails — for example because the sender has zero connectivity or insufficient mutual peers — the message is parked in the persistent outbox (`outbox.json.enc`) so that it survives a daemon crash and is retried on the next network-join event (§5.1).

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

1. Reset `_discoveryComplete = false` and re-execute the §4.5 discovery cascade from Tier 1 (stored peers). The cascade escalates through Tier 2 (LAN burst), Tier 3 (bootstrap), Tier 4 (subnet scan) only if each prior tier fails — the same cascading logic as startup.
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

From the seed, key pairs are derived using SHA-256 with context strings: `SHA-256(seed + "cleona-ed25519")` for Ed25519, etc. Post-quantum keys (ML-KEM-768, ML-DSA-65) are **also** deterministically seed-derived: a per-key seed (HKDF from the master seed) feeds FIPS 203/204 deterministic key-generation (`OQS_KEM_keypair_derand` / `OQS_SIG_keypair_derand`, liboqs ≥ 0.15.0), so the same seed always regenerates the identical PQ keypair. No separate PQ backup and no key re-publication on recovery are required. Full security analysis: §3.3.5.

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

**Frame layout (V3.0 Welle 6):** A Restore Broadcast is an `InfrastructureFrame` (§2.3.5) of type `RESTORE_BROADCAST`, KEM-encrypted under each contact's Device-KEM-PK (§3.5b). The recipient Device-KEM-PK is fetched from the local routing-table cache, otherwise via a 2D-DHT DeviceKemRecord lookup (§4.3 step 4b). The Outer NetworkPacket is signed under the recovering peer's freshly-generated **Device**-Sig-Keys — these are independent of User-Identity rotation, so receivers verify Outer-Sig regularly. The inner `RestoreBroadcast` body carries a **hybrid** signature (Ed25519 `signature` + ML-DSA-65 `signature_ml_dsa`) over `(oldUserId, newUserId, newPubkeys, displayName, timestamp)` — the inner authenticity that proves the sender controls the old User-Sig-Key.

**Inner authenticity is hybrid (H-2):** the receiver verifies BOTH the old-Ed25519 signature against the contact's stored `ed25519Pk` AND the old-ML-DSA signature against the contact's stored `mlDsaPk` (the keys it already holds, *before* applying the broadcast's new keys). A classical-only forge — breaking or stealing just the contact's Ed25519 key — no longer suffices to forge a restore takeover and harvest the full chat history; the attacker must break both the classical and the PQ signature key. Because PQ keys are deterministically seed-derived (§3.6 / §6.3.5), a legitimate same-seed recovery regenerates the *identical* ML-DSA key, so the contact's stored `mlDsaPk` matches the signer — the hybrid check passes without any extra key exchange. **Transition:** broadcasts carrying only the Ed25519 signature (pre-H-2 senders, `signature_ml_dsa` absent) are accepted as legacy-classical until a Phase-2 enforcement gate (`minRequiredVersion`, §19.5.7), mirroring the D1/SR-2 legacy-record handling.

`RESTORE_RESPONSE` is an `ApplicationFrame`, KEM-encrypted under the recovering peer's freshly-published User-KEM-PK (which the broadcast carried). All subsequent phases — manifests, fetch responses, payloads — use the standard encrypted `ApplicationFrame` (§3.3).

**Rationale:** The previous "signed-only" ApplicationFrame variant was a structural workaround because the recovering peer does not yet know contact User-KEM-PKs. The InfrastructureFrame path uses Device-KEM-PKs (which contacts already know from prior interaction or 2D-DHT), eliminating the workaround and aligning with §2.4.1.

**Routing:** Unlike a normal user-addressed message, the Restore Broadcast is broadcast-style: the sender enumerates all known contacts and, for each, builds a separate outer `NetworkPacket` per contact device (the Identity Resolver returns a device-set per `userId`; see §4.3). The inner `ApplicationFrame` is identical across all packets — the per-device variation is the routing envelope, not the payload.

**Critical prerequisite:** The recovering device must perform a **complete wipe** of the old profile data before restoring from a recovery phrase. Without a wipe, the existing node has an empty contact list and a different Device-Sig keypair, causing a deadlock: contacts may recognise the recovered `userId` but the routing-layer cost-model is empty, so reverse-path delivery has no targets. The correct flow is: wipe profile → enter recovery phrase → derive user keys → generate fresh device-sig keypair → rejoin network → broadcast.

#### 6.3.1 Restore Broadcast Flow

1. User recovers their user-identity private key via recovery phrase or Social Recovery.
2. App performs a complete profile wipe and re-derives user keys from the seed; a fresh per-device signing keypair is generated (§3.5).
3. App connects to the network using the recovered `userId` and the fresh `deviceId`. The Identity Resolver (§4.3) is updated so that other peers can re-discover this device.
4. App emits a `RESTORE_BROADCAST` `InfrastructureFrame` per contact device, KEM-encrypted under the contact's Device-KEM-PK (§3.5b), Outer-signed under the recovering peer's fresh Device-Sig-Keys (rotation-stable per §3.5b). The body carries an old-Ed25519 signature for inner authenticity. The frame is additionally erasure-coded into the DHT (§5.4) so offline contacts pick it up via Mailbox-Pull when they come online — the encoded blob is the canonical NetworkPacket built for the contact's first-resolved device (per §5.4: InfraFrame KEM is device-PK-keyed, so one encoded copy reaches at most one device of the contact; further devices of the same contact pick up via subsequent Direct-Send retries or via S&F on contact peers, §5.5).
5. Every node that processes the broadcast checks: "Is this `userId` in my contact list?"
6. If yes, the contact's app automatically responds with: their contact information (so the recovering user rebuilds their contact list), the encrypted chat history of their shared conversation, group memberships with member crypto keys and profile data.
7. For anti-abuse protection the recovery is made **visible and authenticated**, not silently followed: the inner hybrid signature (H-2) binds the proof to both the contact's stored Ed25519 and ML-DSA keys, and a restore that actually changes the contact's identity key routes through §8.3 Key-Change-Detection (verification reset + warning, §6.3.5). (Guardian-quorum gating of data release is documented as an aspiration in §6.3.5 but is **not** cryptographically enforced — see there.)
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

**Inner hybrid signature (H-2):** the inner restore proof is hybrid-signed (Ed25519 + ML-DSA-65) and the receiver verifies both against the contact's stored keys before releasing any data (see §6.3 *Inner authenticity is hybrid*). A break/theft of a contact's classical key alone can no longer forge a restore takeover + history harvest.

**Key-change visibility (H-2, SR-1-consistent):** every accepted Restore Broadcast surfaces a `contact_restore_detected` IPC event so the contact's UI can show "[Name] has set up a new device" — if the real user did not initiate it they can alert their contacts. When the restore additionally *changes* the contact's identity key (i.e. a new-seed re-identity or a forge attempt, as opposed to a deterministic same-seed recovery where the keys are unchanged, §6.3.5 PQ-handling), it is routed through §8.3 Key-Change-Detection: the verification level is reset and a key-change warning is raised, exactly as for Emergency Key Rotation (§7.4b step 6). It is never followed silently at full trust.

**Guardian confirmation (aspirational — NOT enforced):** the original design called for 3 of 5 guardians to confirm the restore before contacts release chat data. This is **not cryptographically enforced** and the current build does not gate data release on it: a contact cannot verify a guardian quorum because guardians are secret by design (§6.2) — a contact does not know who the recovering user's guardians are, so it has no key set to check a quorum token against. This is the same key-distribution wall as the SR-1 rotation co-authorization, and a verifiable guardian-quorum token is deferred to the linked-device / guardian-attestation redesign tracked in the security review. The realized anti-abuse protections are: rate-limiting (above), the inner hybrid signature, key-change visibility, and encrypted transfer (below).

**Encrypted transfer:** All chat history sent in response to a Restore Broadcast is encrypted with Per-Message KEM (§3.3) using the recovering device's public key (the user-identity public key derived from the recovered seed). Exception: `RESTORE_BROADCAST` and `RESTORE_RESPONSE` themselves are signed only (not encrypted), since the recovering peer may not have the responding contact's current PQ public key.

**Post-quantum key handling during restore:** Because ML-KEM-768 and ML-DSA-65 are deterministically seed-derived (§3.6, FIPS 203/204 keygen), a seed recovery regenerates the **identical** PQ keypairs. The recovering device therefore does **not** create new PQ keys, the Restore Broadcast does **not** carry replacement PQ public keys, and contacts do **not** update stored keys — the keys are unchanged. There is no X25519-only fallback mode: the X25519 + ML-KEM hybrid is always enforced, so no transition window or forced classical-only decryption exists. (A genuine key *change* happens only on the compromise path — Identity-Deletion + new identity, §3.4 — which is a manual re-verification, not a seed recovery.) Full security analysis: §3.3.5.

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

**Seed-distribution limitation (SR-1 / Multi-Device-Seed — resolved, LD-1 through LD-12):** the previous pairing flow transferred the **master seed** to each new device, so every paired device could derive the full User-Sig key. A stolen device therefore held the user identity itself, not just a disposable device key. **Resolved:** the linked-device model (§7.1.1–§7.1.3) replaces the seed-transfer with per-device **delegation**: linked devices receive a per-device HKDF-derived sig-subkey plus a user-signed `DeviceDelegationCert` authorizing that subkey to act for the identity with bounded capabilities, plus the User-KEM-SK for decryption — but **not** the master seed. The seed never leaves the Primary device; a stolen linked device can be revoked without touching the identity, and user-key rotation requires the actual seed. This resolves SR-1 (rotation authorization), the Multi-Device-Seed finding, and the Twin-PQ-divergence finding (delegation keys are deterministically derived per §7.1.1, so all devices share identical sig-material without independent random generation). Legacy twin-devices (seed on every device) can soft-migrate to the delegation model via §7.1.3.

**Initial setup** (first device):
1. The user generates the master seed (24-word phrase)
2. HD-Wallet derives the user identities (§3.6)
3. Device keys are freshly generated using a cryptographic random source
4. The auth manifest is published with this single DeviceID as `authorizedDeviceIds[0]`
5. Identity Registry entry (§6.4) with display name + profile picture

**Pairing an additional device** (linked-device delegation model, LD-1 through LD-12):
1. On the new device: "Request Pairing" action in Settings → Devices → generates its own Device-Sig keypair, sends `MTV3_DEVICE_PAIR_REQUEST` to own userId via `sendToUser` (carries `deviceEd25519Pk` + `deviceMlDsaPk`)
2. On the Primary device: receives the request, shows an approval dialog with the requesting device ID
3. The Primary derives per-device delegation keys (§7.1.1) and builds a `DevicePairApproveV3` payload containing: `delegatedEd25519Pk/Sk`, `delegatedMlDsaPk/Sk`, `userX25519Sk`, `userMlKemSk`, `DeviceDelegationCert` (proto), `userId`, `displayName`
4. The Primary sends `MTV3_DEVICE_PAIR_APPROVE` (KEM-encrypted to the new device) and adds the `DeviceDelegationCert` to the Auth-Manifest (field 11), re-publishes
5. The new device receives the approval, verifies the delegation cert signature against its own User-PK copy, persists the delegation keys to `linked_device_keys.json.enc` (XSalsa20-Poly1305 via FileEncryption), and applies them — `identity.isLinkedDevice` becomes `true`, all Inner-Sigs switch to the delegated keys
6. The master seed is **not** transferred — the new device holds only delegation material

**What the Linked Device receives:**
- **Delegated Sig-Keys** (Ed25519 + ML-DSA-65): deterministically derived from the Primary's seed + device ID via HKDF (§7.1.1). Used for all Inner-Sig operations. The receiver can verify them via the `DeviceDelegationCert` in the Auth-Manifest.
- **User-KEM-SK** (X25519 + ML-KEM): the actual user decryption keys. Shared across all devices so every device can decrypt messages addressed to the UserID.
- **DeviceDelegationCert**: a hybrid-signed (Ed25519+ML-DSA) certificate authorizing the delegated PK to act for the identity (§7.1.1).
- **NOT the master seed**: the linked device cannot derive new keys, rotate the identity, or pair additional devices.

**Pairing security**:
- Delegation cert is hybrid-signed by User-Key (Ed25519 + ML-DSA-65) — forging requires both keys
- Approval payload KEM-encrypted via X25519+ML-KEM-768 hybrid (standard KEM, §3.3)
- Cert verification on the Linked Device side: `delegationCert.verify(ownUserEd25519Pk, ownUserMlDsaPk)` — rejects invalid signatures before persisting
- Dead-man-switch expiry (`maxValidUntilMs`) — delegation auto-expires if the Primary does not renew (default: 30 days, 0 = no expiry)
- Max 5 devices per UserID (Auth-Manifest `authorizedDeviceIds` limit)

**Pairing over NFC** (alternative): identical delegation flow, but the initial contact between devices is conveyed via NFC pairing tap instead of QR.

**Pairing from Settings** (soft migration, §7.1.3): existing twin-devices (legacy seed-on-every-device model) can initiate pairing from Settings → Devices → "Request Pairing". The Primary approves, the device receives delegation keys and transitions to `isLinkedDevice=true` — the seed remains on disk but is no longer used for signing.

**Twin-Discovery**: after pairing, devices automatically discover each other via the 2D-DHT (each device publishes its own liveness; other devices see liveness records bearing the same UserID).

#### 7.1.1 Linked-Device Key Derivation

Delegation keys are **deterministically derived** from the Primary's master seed + the linked device's DeviceID, ensuring that re-pairing or recovery produces identical keys without transferring the seed.

**Ed25519 delegation keypair:**
```
ikm   = HKDF-Extract(salt="", ikm=masterSeed)
okm   = HKDF-Expand(prk=ikm, info="cleona-deleg-ed25519-v1" || deviceId, L=32)
ed25519_sk = crypto_sign_seed_keypair(okm)   // libsodium deterministic keygen
```

**ML-DSA-65 delegation keypair:**
```
ikm   = HKDF-Extract(salt="", ikm=masterSeed)
seed  = HKDF-Expand(prk=ikm, info="cleona-deleg-ml-dsa-v1" || deviceId, L=64)
```
liboqs SIG API has no `keypair_derand` (only KEM does). The implementation injects a seeded **SHA-256 counter-mode PRNG** via `OQS_randombytes_custom_algorithm` using a Dart `NativeCallable`, calls `OQS_SIG_keypair`, and immediately restores the system DRBG via `OQS_randombytes_switch_algorithm("system")`. Thread-safe because Dart is single-threaded per isolate and OQS keygen is synchronous. The PRNG produces `SHA-256(seed || counter)` blocks (counter starts at 0, increments per call), providing deterministic randomness for the ML-DSA key generation internals.

**DeviceDelegationCert** (proto: `DeviceDelegationCertV3`, Auth-Manifest field 11):
```
message DeviceDelegationCertV3 {
  bytes  deviceId            = 1;   // SHA-256(network_secret || device_ed25519_pk)
  bytes  delegatedEd25519Pk  = 2;   // HKDF-derived delegation pubkey
  bytes  delegatedMlDsaPk    = 3;   // HKDF-derived ML-DSA delegation pubkey
  uint32 capabilities        = 4;   // bitmask (see below)
  int64  issuedAtMs           = 5;   // milliseconds since epoch
  int64  maxValidUntilMs      = 6;   // 0 = no expiry (dead-man-switch)
  bytes  userEd25519Sig       = 7;   // User-Ed25519 signature over fields 1-6
  bytes  userMlDsaSig         = 8;   // User-ML-DSA signature over fields 1-6
}
```

**Capabilities bitmask** (standard = 0x0F):
| Bit | Capability |
|-----|------------|
| 0   | `capSend` — send messages on behalf of the UserID |
| 1   | `capReceive` — decrypt incoming messages |
| 2   | `capSync` — participate in Twin-Sync |
| 3   | `capRelay` — relay messages for other peers |

**Cert verification**: hybrid — both Ed25519 AND ML-DSA signatures must verify against the User-PKs in the Auth-Manifest. Forging a delegation requires breaking both signature schemes. The signed payload is `deviceId || delegatedEd25519Pk || delegatedMlDsaPk || capabilities(LE32) || issuedAtMs(LE64) || maxValidUntilMs(LE64)`.

**Expiry**: `maxValidUntilMs > 0 && now > maxValidUntilMs` → cert is expired. Default 30 days. The Primary must re-pair (renew the cert) before expiry; the linked device degrades to offline-only if the cert expires. `maxValidUntilMs == 0` means no expiry (permanent delegation).

#### 7.1.2 Signing Key Indirection

With the linked-device model, the **signing path** changes:

- **Primary device**: `identity.signingEd25519Sk` returns the User-Key (unchanged behavior).
- **Linked device**: `identity.signingEd25519Sk` returns the **delegated** Ed25519 SK from `linkedDeviceKeys`. Same for ML-DSA. The getter checks `linkedDeviceKeys != null` and returns the delegation key if present.

**Sender side** (linked device signing a message):
```
V3FrameCodec.signApplicationFrameInner(
  inner: inner,
  senderUserEd25519Sk: identity.signingEd25519Sk,  // = delegated SK
  senderUserMlDsaSk:   identity.signingMlDsaSk,    // = delegated ML-DSA SK
)
```
The signature is over the same `ApplicationFrameV3` fields as before — only the key is different.

**Receiver side** (verifying a delegated signature):
`V3FrameCodec.decryptAndVerifyInner` first tries the User-PK (standard path). If that fails, it calls `lookupDelegatedKeys(senderUserId)` — a callback that returns the list of `(edPk, mlDsaPk)` tuples from the sender's Auth-Manifest delegation certs. If any tuple's Ed25519+ML-DSA verify the signature, the frame is accepted. Without the callback (old builds), delegated-key signatures are silently rejected — **wire-compatible**: old builds ignore Auth-Manifest field 11 (proto3 unknown field behavior) and reject the frame normally, no crash.

**Auth-Manifest distribution**: the `DeviceDelegationCert` is embedded in Auth-Manifest field 11 (repeated). The IdentityPublisher adds it on approval; resolvers extract it in the D1 cascade. Contacts that have resolved the sender's Auth-Manifest use the embedded certs to populate `lookupDelegatedKeys`.

#### 7.1.3 Soft Migration (Legacy Twin → Linked Device)

Existing twin-devices (seed-on-every-device, pre-LD model) can migrate to the delegation model without re-pairing from scratch:

1. On the legacy twin: Settings → Devices → "Request Pairing" sends `MTV3_DEVICE_PAIR_REQUEST` to own userId
2. The Primary device (= the device the user designates as authoritative, typically the device that originally generated the seed) receives the request and shows the approval dialog
3. On approval, the Primary derives delegation keys (§7.1.1) and sends `MTV3_DEVICE_PAIR_APPROVE`
4. The twin receives the delegation, persists it to `linked_device_keys.json.enc`, and sets `identity.linkedDeviceKeys` — `isLinkedDevice` becomes `true`
5. The master seed remains on disk (not wiped) but is no longer used for signing — all Inner-Sigs switch to the delegated keys

**Non-destructive**: the seed is kept as a local backup. The user can explicitly wipe it later via a future "Destroy local seed" action (not yet implemented). The migration is one-way: once delegated, the device cannot self-promote back to Primary without the seed.

**IPC**: `send_device_pair_request` (IPC command) → `CleonaService.sendDevicePairRequest()`. On Android (in-process): `service.sendDevicePairRequest()` directly. Status: `get_linked_device_status` returns `{isLinkedDevice, delegationCaps, expiresAtMs, deviceIdHex}`.

**GUI**: Settings → Devices shows the linked-device status (Primary/Linked icon + capabilities + expiry). The "Request Pairing" button is only shown on non-linked devices.

#### 7.1.4 Delegation Rotation (LD-8)

When the Primary device performs an **emergency key rotation** (§7.4b variant b), linked devices must receive **new delegation keys** derived from the new master seed — but must **not** receive the new seed itself. This preserves the LD security boundary across rotations.

**Sender (Primary, pre-rotation):** for each linked device (identified via `IdentityPublisher.delegations`), the Primary:
1. Derives new delegation keys via HKDF from the **new** master seed + deviceId (§7.1.1 formulas, deterministic).
2. Signs the new `DeviceDelegationCert` with the **old** User-Keys (the linked device can verify against its current User-PK reference).
3. Sends a `TWIN_SYNC/SETTINGS_CHANGED` with `delegationRotation=true` payload containing: per-device delegation keys (Ed25519 + ML-DSA SK/PK), new User-PKs (Ed25519, ML-DSA, X25519, ML-KEM), new User-KEM-SK, and the signed delegation cert.
4. Legacy twins (no delegation cert) still receive the `newEntropy` via the existing `emergencyRotation` path — they already hold the seed, so this does not weaken security.

**Receiver (Linked Device):** on receiving `delegationRotation=true`:
1. Checks `targetDeviceId` matches own Device-Node-ID (device-targeting; other devices silently ignore).
2. Verifies the delegation cert against the **current** (pre-rotation) User-PKs.
3. Appends a rotation chain link (old Ed25519 SK signs `newEd25519Pk || newMlDsaPk`) — the linked device still holds the seed-derived Ed25519-SK for this purpose.
4. Updates: User-PKs, User-KEM-SK, delegation keys, keeps old KEM-SK as `previous` for 7-day transit-message grace.
5. Persists new `LinkedDeviceKeys` to `linked_device_keys.json.enc`.
6. Triggers Auth-Manifest republish + PeerInfo broadcast.

**Defense-in-depth (LD-5):** if a linked device receives an `emergencyRotation` entropy payload (e.g. from a legacy sender or race condition), it rejects and logs a warning instead of deriving keys. The `rotateIdentityKeys()` entry point is also blocked on linked devices (seed required).

**Cross-device key leakage:** the `TWIN_SYNC` fan-out sends all delegation-rotation messages to all devices (each device receives all per-device payloads). Since all devices share the User-KEM-SK, each device can decrypt payloads targeted at other devices. This is accepted as minor residual exposure — the shared KEM-SK model already implies that any device can decrypt any user-addressed message. Delegation key cross-visibility affects forensic attribution but does not expand the attack surface.

#### 7.1.5 Cert Auto-Renewal (LD-9)

Delegation certificates have a 30-day expiry (`maxValidUntilMs`). The linked device monitors expiry with a **1-hour periodic timer** (`_delegationRenewalTimer`). When the cert is within **7 days** of expiry (or already expired), the linked device automatically sends a `DEVICE_PAIR_REQUEST` to the Primary — reusing the existing pairing protocol.

**Primary auto-approve:** when the Primary receives a `DEVICE_PAIR_REQUEST` from a device whose `deviceId` is already registered in `IdentityPublisher.delegations` (i.e., a known linked device), it **auto-approves** without user interaction. This issues a fresh `DeviceDelegationCert` with a new 30-day window and sends `DEVICE_PAIR_APPROVE` back. The linked device applies the new cert transparently.

**Manual renewal:** the GUI exposes a "Renew now" button in Settings → Devices when the cert is within 7 days of expiry or already expired. This triggers `requestDelegationRenewal()` which calls `sendDevicePairRequest()`.

**Degraded state:** if the cert expires without renewal (Primary offline for >30 days), the linked device's delegated signatures will fail verification by contacts who re-resolve the Auth-Manifest. The device can still receive and decrypt messages (shared User-KEM-SK) but cannot effectively send. Renewal restores full operation.

#### 7.1.6 Device Status Screen (LD-11)

Settings → Devices shows enhanced linked-device status:

- **Device type icon:** shield (Primary) or chain-link (Linked), colored red if cert expired.
- **Capability chips:** visual display of the 4 delegation capabilities (Send, Contacts, Groups, Channels) — active caps highlighted in `primaryContainer`, inactive in `surfaceContainerHighest`.
- **Expiry countdown:** date + remaining days. Warning (orange) at ≤7 days, error (red) when expired.
- **Renew button:** appears when cert is within 7 days of expiry or expired.
- **Soft migration button:** "Request Pairing" shown for non-linked devices when >1 device exists (§7.1.3 flow via GUI).

`LinkedDeviceStatus` data class (`service_types.dart`) provides `daysRemaining`, `expiresWithin7Days`, `capabilityNames`, `expiryDate` — consumed by both the GUI and the IPC layer.

### 7.2 Twin-Sync Protocol

Once Multi-Device is active, application-state changes (new contacts, conversations, message edits, etc.) must be synchronised between devices.

**Twin-Sync** is a dedicated protocol type: a `TWIN_SYNC` application frame with a sub-type discriminator.

**12 Twin-Sync types** (canonical: `proto/cleona.proto::TwinSyncType`):

| # | Type | Content |
|---|---|---|
| 0 | CONTACT_ADDED | new contact accepted (with pubkeys, display name, verification level) |
| 1 | CONTACT_DELETED | contact deleted (source-tagged: `inbox_reject`, `conversation_dialog`, `contacts_dialog`, `ipc`) |
| 2 | MESSAGE_SENT | message sent on one device → mirror so the other devices see it locally |
| 3 | MESSAGE_EDITED | edit within the per-chat editing window (default 60 min, see §14.6) |
| 4 | MESSAGE_DELETED | delete is **unbounded** — the author may delete their own message at any time (no time window); the receiver admits the delete as long as the sender is the original author (§14.6). Only `MESSAGE_EDITED` is window-bound. |
| 5 | TWIN_READ_RECEIPT | own read on one device → other devices also mark read |
| 6 | GROUP_CREATED | own device created/joined a new group *(receive-side wired; sender-side wiring pending)* |
| 7 | PROFILE_CHANGED | own profile picture / display name changed *(receive-side wired; sender-side wiring pending — `_emitProfileChange()` hook missing)* |
| 8 | SETTINGS_CHANGED | shared per-identity settings changed (emergency rotation sync: entropy for legacy twins, delegation rotation for linked devices §7.1.4) |
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
4. **Stable anchor (SR-2):** the rotating identity does **NOT** recompute its UserID — it stays pinned to the founding key (§3.1). At rotation time the identity appends a `RotationChainLink` (old key signs `newEd25519Pk || newMlDsaPk`, the §4.3 link shape) to its **persisted rotation chain**; the IdentityPublisher embeds the chain in every subsequent Auth-Manifest, so resolvers verify the embedded keys via the chain path (§4.3 verification path 2) and TOFU anchors bridge old→new.
5. Contacts verify both inner signatures and replace the stored User-Pubkeys **in place** — the contact's UserID, groups and channels are untouched; there is no contact re-keying. They respond with `KEY_ROTATION_ACK` (regular ApplicationFrame, now KEM-encrypted under the rotated User-KEM-PK).
6. **Visibility (SR-1):** an accepted emergency rotation is routed through the §8.3 **Key-Change-Detection** path, exactly like any other change of a contact's identity key — the contact's verification level is reset (`verified`/`trusted` → `unverified`) and a key-change warning is surfaced in the chat. The new keys ARE applied (the dual-sig + chain make the rotation cryptographically valid, so communication keeps working and a legitimate rotation is not blocked), but it is **not silently followed at full trust**. See the authorization threat model below.

**Rotation-authorization threat model (SR-1 — structurally resolved by linked-device model):** the dual-sig proves only that the broadcaster controls the old AND the new key — it does **not** distinguish the legitimate owner from anyone else who holds the old key. **With the linked-device model (§7.1.1–§7.1.3, LD-1 through LD-12):** linked devices hold only per-device delegation subkeys + User-KEM-SK, **not** the master seed. A stolen linked device cannot rotate the identity (rotation requires the seed, which resides only on the Primary). The attack surface is reduced to: (a) theft of the Primary device itself (which holds the seed — same exposure as any self-custody wallet), or (b) extraction of the seed from the 24-word recovery phrase. **Defense-in-depth remains**: step 6's visibility mitigation (key-change warning + verification reset at every contact) applies regardless, so even a Primary-device theft is detectable. **Receiver-enforced co-authorization** is implemented in §7.5: the AuthManifest carries Device-Sig pubkeys (field 12) and the KeyRotationBroadcast carries Device-Sig countersigs (field 7); contacts verify a `max(2, ceil(N/2))` quorum against cached Device-Sig keys and escalate the warning when quorum is not met.

*Doc-vs-code drift corrected (SR-2 review, 2026-06-12):* the previous implementation recomputed the UserID on both sides and migrated contacts/groups/channels to the new hex — contradicting §3.1, leaving the D1 chain path unused, and making rotation a free identity reset (moderation age, TOFU anchors and per-identity history wiped). Mixed-network honesty: pre-SR-2 builds still perform the migration on receive; a rotation initiated by a current build degrades those contacts until they upgrade (emergency rotation is rare and the beta field small — corrected now rather than never).

Both flavors are **hard cuts** in user-perception terms — no Twin-Sync of old conversations to the new identity, no automatic migration. Variant (b) preserves the UserID but still requires the Inner Dual-Sig as the only authentication subject; receivers MUST NOT accept a key-rotation without inner dual-sig verification regardless of `senderIdentitySnapshot.outerSigStatus`.

Note on periodic KEM-only rotation: `MessageType.KEY_ROTATION` (single-sig in body, KEM keys only) remains an ApplicationFrame because Ed25519/ML-DSA do not change — Outer Device-Sig-Verify and Inner User-Sig-Verify both function regularly.

### 7.5 Device Co-Authorization for Key Rotation

**Motivation:** §7.4b rotation-authorization threat model notes that the dual-sig proves key control but not legitimate ownership — anyone holding the old key (seed thief) can rotate. The linked-device model (§7.1) introduces **Device-Sig keys** that are locally generated (CSPRNG, NOT seed-derived). A seed thief cannot forge Device-Sig countersignatures. §7.5 leverages this for **receiver-enforced co-authorization**.

**Mechanism:**

1. **AuthManifest extension (field 12):** every Auth-Manifest now carries `repeated AuthorizedDeviceSigningKeys device_sig_keys` — the Device-Sig Ed25519 + ML-DSA pubkeys for each authorized device (Primary + all Linked). Contacts cache these on resolution.

2. **Quorum formula:** `max(2, ceil(N/2))` where N = total authorized devices. N=1 → no co-auth (single-device identity, same threat model as before). N=2 → both must sign. N=3 → 2. This is the minimum number of `RotationApprovalToken` entries required in a `KeyRotationBroadcast`.

3. **Rotation flow (sender-side):**
   - Primary generates new keys (unchanged from §7.4b steps 1-2).
   - Primary computes `rotationHash = SHA-256(newEd25519Pk || newMlDsaPk || newX25519Pk || newMlKemPk || userId)`.
   - Primary signs `rotationHash` with its own Device-Sig keys (Primary's own token).
   - Primary sends `ROTATION_APPROVAL_REQUEST` (TwinSync type 12) to all Linked Devices.
   - Linked Devices sign `rotationHash` with their Device-Sig keys and respond with `ROTATION_APPROVAL_RESPONSE` (TwinSync type 13).
   - Primary waits up to 5 minutes for responses.
   - Primary embeds collected `approval_tokens` + `pre_rotation_device_count` in the `KeyRotationBroadcast` (fields 7-8).
   - Broadcast proceeds regardless of quorum result (visibility, not prevention — SR-1 principle).

4. **Rotation flow (receiver-side):**
   - Contact receives `KeyRotationBroadcast`, verifies dual-sig as before (§7.4b).
   - Contact looks up cached `device_sig_keys` from the pre-rotation AuthManifest.
   - Contact calls `verifyRotationCoAuth()`:
     - `legacy` (no cached device_sig_keys) → standard Key-Change-Detection (pre-§7.5 builds).
     - `singleDevice` (N≤1) → standard Key-Change-Detection.
     - `quorumMet` → standard Key-Change-Detection (elevated confidence, legitimate rotation).
     - `quorumNotMet` → **escalated warning**: "Key rotation without device quorum — possible Primary theft." Callback `onRotationCoAuthWarning` fires in addition to the standard `onContactIdentityRotated`.
   - Keys are **always applied** (rotation is never blocked — SR-1 visibility principle).

5. **Active Rejection (Rejection Token):**
   - A Linked Device that detects an unauthorized rotation (e.g. user explicitly rejects via UI) sends `ROTATION_APPROVAL_RESPONSE` with `rejected=true`.
   - The receiving Primary (possibly compromised) relays this as `MTV3_ROTATION_REJECTION_ALERT` directly to all contacts.
   - Contact receives the alert → `onRotationRejectionAlert` callback → strongest possible theft signal.
   - The Rejection Alert carries `device_node_id` + `rotation_hash` + Device-Sig hybrid signature for authenticity.

6. **Device-Set Shrink Co-Auth (field 13):**
   - When devices are **removed** from the AuthManifest, the new manifest carries a `DeviceSetChangeProof` with `previousDeviceCount`, `changeHash = SHA-256(userId || sorted(newDeviceNodeIds) || newSeq)`, and `approvals` from remaining devices.
   - This prevents the attack: steal Primary → remove all Linked Devices from manifest → rotate without quorum (because there are now "no" linked devices to check against).
   - Contacts that see a device-set shrink without co-auth proof treat it as suspicious (same escalated warning).

7. **Mixed-Network Transition:**
   - proto3 unknown-field behavior: old builds ignore `device_sig_keys` (field 12), `device_set_change_proof` (field 13), `approval_tokens` (field 7), `pre_rotation_device_count` (field 8).
   - Old builds receive rotations and apply them via standard Key-Change-Detection — no regression.
   - Phase 2 enforcement (future): `minRequiredVersion` gate where contacts reject rotations without quorum from builds that should support it.

**Wire types:**

```
TwinSyncType:
  ROTATION_APPROVAL_REQUEST  = 12
  ROTATION_APPROVAL_RESPONSE = 13

MessageTypeV3:
  MTV3_ROTATION_REJECTION_ALERT = 184

AuthManifestProto:
  repeated AuthorizedDeviceSigningKeys device_sig_keys = 12;
  DeviceSetChangeProof device_set_change_proof         = 13;

KeyRotationBroadcast:
  repeated RotationApprovalToken approval_tokens = 7;
  uint32 pre_rotation_device_count               = 8;
```

**Implementation:** `lib/core/identity_resolution/rotation_co_auth.dart` (model classes, quorum math, verification), wired in `cleona_service.dart` (sender: co-auth collection in `rotateIdentityKeys()`, receiver: verification in `_handleEmergencyKeyRotation()`).

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

**Re-Contact-Auto-Overwrite-Gate (V3.0 Wave 6 + RC-1 Hardening):** The auto-overwrite of stored pubkeys for an already `accepted` contact requires **two cumulative proofs** — a verified outer Device-Sig (`senderIdentitySnapshot.outerSigStatus == verified`, §2.4.0) **and** an inner User-Sig that verifies against the **stored** User-Keys of the contact (§3.5/`v3_frame_codec` Inner-Sig-Verify; the `trustBootstrapPubkeys` fallback to payload keys applies exclusively while **no** User-Keys are stored yet). A device-key compromise alone is therefore **not** sufficient to replace a contact's User-Keys — the attacker would additionally need the old User-Signing-Key, which already amounts to full identity compromise.

**Continuity Proof on Key-Change (RC-1):** When a re-contact CR (or a CR-Response) carries **different** User-Keys than the stored ones, `identityKeyChanged` is evaluated before any overwrite. An actual key change is **never** followed silently via the CR path:

| Case | Condition | Behavior |
|------|-----------|----------|
| Same-Seed-Reinstall | Keys unchanged | Refresh keys/device-ID, re-accept (silently ok) |
| Key changed | `ed25519Pk` differs from stored | Overwrite + §8.3 Key-Change-Detection (verification reset + warning + `contact_identity_rotated` IPC event) |
| Contact without stored User-Key | `ed25519Pk` null/empty | Keys filled silently from CR (same as Same-Seed-Reinstall), re-accept — never downgrade accepted→pending |

The CR/CRR path is thereby consistent with RESTORE_BROADCAST (§6.3, H-2) and Emergency Key Rotation (§7.4b, SR-1): **a real identity-key change is never silent**, regardless of the transport carrier. The prior state (overwrite solely on `outerSigStatus==verified`, without §8.3) allowed a takeover via the CR path around Key-Change-Detection — RC-1 hardening closes this door.

**Cross-reference §8.3:** Key-Change-Detection (§8.3) is the **only** permitted reaction path to an identity-key change of a known contact and MUST be traversed by **all** overwrite paths (RESTORE, KEY_ROTATION, CONTACT_REQUEST, CONTACT_REQUEST_RESPONSE) whenever `ed25519Pk` changes.

**CR-from-accepted-contact suppression (V3.1.130+):** if a CR arrives for a contact that is already `accepted` but the outer Device-Sig is unverified (`skippedBootstrap`), the CR is silently dropped. An `accepted` contact is **never** downgraded to `pending` — neither by the F4-Gate path nor by the Restlücke-A (missing stored key) path. The `accepted→pending` transition is architecturally forbidden; all four sub-paths within the `accepted`-contact branch now terminate with `return`. A legitimate re-install from the same sender will be handled by the next direct-path CR (verified outer-sig), which triggers Same-Seed-Reinstall or §8.3 Key-Change-Detection as appropriate.

**Mixed-Net:** Receiver-side hardening — an RC-1 receiver protects itself regardless of the sender build. Legacy builds still overwrite silently on receive; enforcement via `minRequiredVersion` (§19.5.7 Phase-2 pattern), as with SR-2.

**Inbox reject UX (V3.1.130+):** the "reject" action on pending contact requests in the Inbox tab requires explicit user confirmation via an AlertDialog before calling `deleteContact()`, consistent with the conversation-dialog and contacts-dialog delete paths. All three delete paths are source-tagged for diagnostics (`inbox_reject`, `conversation_dialog`, `contacts_dialog`).

**Bidirectional CR auto-accept**: if Alice accepts Bob's CR while Bob has already sent Alice a CR (race), both CRs are auto-accepted without further user confirmation.

**Previously-deleted-contact auto-accept (V3.1.130+):** if a CR arrives from a userId that is in the `_deletedContacts` set (the user had previously accepted and then deleted this contact), the CR is auto-accepted without user interaction. This is safe because `userId = SHA-256(network_secret + pubkey)` cryptographically binds the identity — no attacker can forge a CR with the correct userId without the corresponding private key. The `_deletedContacts` entry is cleared on acceptance. This eliminates the manual re-accept step when one side deletes a contact and the other re-initiates via `sendContactRequest` (re-contact path).

### 8.1.1 ContactSeed Format (rev3 — Compact ContactSeed + Deferred Key Exchange)

The ContactSeed is the canonical machine-readable form of "Bob's contact info" used for QR-code, NFC, and copy/paste exchange. It is the prerequisite for the First-Contact-Request bootstrap — without it, Alice has no way to address Bob.

Two format generations coexist (backward-compatible):

#### ContactSeed v2 (rev3, current)

**URI format** (compact, SMS-safe, base64url throughout):

```
cleona://<userIdHex>?n=<displayName>&c=<channel>&did=<deviceIdHex>&ep=<userEd25519Pk_base64url>&t=<createdAtMs>&a=<addresses>&s=<seedPeers>
```

**QR binary format** (format byte `0x07` = zstd-compressed, `0x08` = uncompressed; legacy `0x03`/`0x04` without the timestamp are still parsed, age then reported as unknown):

```
[32B userId] [32B deviceId] [32B userEd25519Pk] [8B createdAtMs]
[1B channel] [1B nameLen] [nameUTF8]
[1B addrCount] [{1B len, addrUTF8}...]
[1B peerCount] [{32B peerNodeId, 1B addrCount, {1B len, addrUTF8}...}...]
```

**Size**: ~130-180 bytes binary (QR Version 8-10, camera scan), ~300-400 chars URI without Device-KEM (QR text fallback, SMS). The clipboard/share URI (V3.1.96+) includes `dxk`+`dmk` and is ~1900-2100 chars — see "Synchronous vs. asynchronous exchange channels" below for the rationale.

**Parameters** (v2):

| Param | Source | Format | Purpose |
|---|---|---|---|
| `<userIdHex>` (path) | UserID | 64 hex chars (32 bytes) | Bob's stable UserID |
| `n` | display name | URL-encoded UTF-8 | hint only — re-confirmed inside CONTACT_REQUEST_RESPONSE |
| `c` | channel tag | `b` (beta) or `l` (live) | mismatched channels are rejected before any send |
| `did` | DeviceID | 64 hex chars (32 bytes) | identifies the QR-emitting device of Bob |
| `ep` (NEW rev3) | userEd25519Pk | 32 bytes, **base64url** (RFC 4648 §5, no `+`/`/`/`=`) | Trust-anchor for Deferred Key Exchange and DHT record verification |
| `t` (NEW) | ContactSeed creation time | 8-byte ms epoch, base64url | Age hint — lets the scanner distinguish a stale seed from an offline target |
| `a` | reachable addresses | `ip:port+[ipv6]:port+...` (`+` URL-encoded as `%2B`) | Bob's current addresses for direct send — includes private IPv4 (LAN, max 2), public IPv4 (if port-mapped), and first global IPv6 (not link-local, not ULA). IPv6 addresses are bracket-wrapped per RFC 2732. |
| `s` | seed peers (≤5) | `nodeIdHex@ip:port+ip:port,...` | routing helpers (any node, not necessarily bootstrap) |
| `fp` (NEW SR-2) | founding userEd25519Pk | 32 bytes, base64url; **only emitted when the identity has rotated** (`fp != ep`) | Founding anchor — integrity-check target for rotated identities (§3.1 stable anchor) |
| `r` (NEW V3.1.116) | random | 32 bytes, base64url; **clipboard/share URI only** (like `dxk`/`dmk`) | First-Contact Rendezvous secret (§4.11.10) — lets holder and issuer of this URI find each other's current addresses via the external rendezvous substrate, without any mesh contact. Absent in QR binary and NFC (synchronous channels need no rendezvous). Older URIs without `r` parse unchanged. |

**ContactSeed readiness (V3.1.116).** A ContactSeed is issued as soon as the node knows **at least one externally reachable own address** — a STUN/UPnP-discovered public IPv4 or a global IPv6 (not link-local, not ULA). Confirmed peers are **not** required: a factory-fresh device on mobile data (global IPv6, no mesh contact yet) issues a valid ContactSeed whose `s=` seed-peer list may be empty. Delivery paths for such a seed are direct send to the `a=` addresses plus the First-Contact Rendezvous (§4.11.10); the FIRST_CR_STORE mailbox (§5.5b) is skipped when no seed peers exist. The only case still gated on session-confirmed peers is the LAN-only node (no externally reachable address): here the seed is issued once at least one LAN peer is confirmed, since LAN addresses are the only usable content. (Previously the gate additionally required ≥1 session-confirmed peer in all cases, which blocked the fresh-device-with-IPv6 scenario entirely.)

**Integrity check**: the scanner verifies `SHA-256(networkSecret + fp) == userIdHex` when `fp` is present, else `SHA-256(networkSecret + ep) == userIdHex` (unchanged — all existing seeds and all non-rotated identities). A manipulated QR fails this check. When `fp` is present, `ep` is provisional until the first D1-verified Auth-Manifest proves the rotation chain founding→`ep` (§4.3 path 2) — the Deferred Key Exchange already defers key use to that resolution step, so no additional roundtrip is introduced.

**QR binary (rotated identities)**: format bytes `0x09` (zstd) / `0x0A` (uncompressed) = the v2 layout with `[32B foundingEd25519Pk]` appended after `createdAtMs`. Non-rotated identities keep emitting `0x07`/`0x08` — zero impact on the existing field.

**Seed age**: the scanner surfaces the seed's age from `t` and distinguishes "code is stale — request a fresh one" from "target is offline", instead of silently retrying a seed whose addresses have long expired. The `t` field is outside the integrity-check input (it is not part of the `userId` derivation), so its presence is backward-compatible with legacy seeds.

**Rationale for removing dxk/dmk from QR binary format**: The 1184-byte ML-KEM-768-PK dominated the QR payload, producing QR Version 26-28 — too dense for reliable phone-to-phone camera scanning, especially in low light. The 32-byte `userEd25519Pk` replaces 1216 bytes in the QR with a trust-anchor that enables runtime key resolution via DHT or Deferred Key Exchange. QR implies physical co-presence (both phones running, same room), so the synchronous DKE round-trip completes reliably.

**Rationale for re-including dxk/dmk in the clipboard/share URI (V3.1.96)**: The Deferred Key Exchange (DEVICE_KEM_REQUEST → DEVICE_KEM_OFFER) requires both phones to be **simultaneously online and reachable** — the request is fire-and-forget with no offline store. On CGNAT/Mobilfunk this fails: the recipient's app gets killed by the OS, the NAT mapping expires, and the request goes into the void. The retry timer re-sends every 10s–600s (exponential backoff), but without a guaranteed simultaneous-online window the DKE round-trip never completes. Without `dxk`/`dmk` the sender cannot build the KEM-encrypted CR, and without the CR the FIRST_CR_STORE (§5.5b offline mailbox) cannot be deposited either — the entire offline delivery chain is dead. Clipboard/share URIs are exchanged **asynchronously** (via messenger, email, note) — the recipient may open the seed hours or days later. URI length is unconstrained, so including the 1622-char overhead is costless. The original URI-corruption concern (standard base64 `+`/`/`/`=` mangled by messaging-app link detection) does not apply to clipboard copy-paste of the full `cleona://` URI.

#### Synchronous vs. asynchronous exchange channels

| Channel | Format | Device-KEM inline | Both online required | Async-capable |
|---------|--------|-------------------|---------------------|---------------|
| **QR** (camera scan) | Binary v2 (`ep` only) | No — DKE at runtime | Yes (face-to-face) | No |
| **NFC** (tap) | Own protocol (§8.1.3) | N/A — exchanges full User-Keys directly | Yes (phones touching) | No |
| **Clipboard/URI** (copy-paste, share) | URI with `dxk`+`dmk`+`r` (§4.11.10) | Yes | No | **Yes** |

QR and NFC are inherently synchronous (physical co-presence guarantees both devices are running). The DKE round-trip completes within the scan/tap session. Clipboard/URI is the only channel that must work asynchronously — therefore the only one that carries Device-KEM-PK inline and the First-Contact-Rendezvous nonce `r` (§4.11.10).

#### ContactSeed dxk/dmk parameters

**URI format** (V3.1.96+): `cleona://...&dxk=<base64>&dmk=<base64>&r=<base64url>...` (standard base64, ~2163 chars with Device-KEM-PK, ~540 chars without; `r` since V3.1.116). The `dxk`/`dmk` parameters are present in every URI generated by V3.1.96+ nodes. Older URIs without these parameters are still fully parsed — the receiver falls back to the Deferred Key Exchange round-trip (§8.1.1 step 2).

**QR binary format**: format byte `0x02` (v2), carries only `ep` (userEd25519Pk) + seed peers. Device-KEM-PK is NOT included — resolved at runtime via DKE (see rationale above).

#### dxk/dmk parameter reference

| Param | Format | Purpose |
|---|---|---|
| `dxk` | 32 bytes, standard base64 | Device-X25519-PK — enables direct KEM-encap of the First-CR InfrastructureFrame without DKE round-trip |
| `dmk` | 1184 bytes, standard base64 | Device-ML-KEM-768-PK — hybrid KEM counterpart to `dxk` |

#### Channel URI (V3.1.130+)

**URI format:** `cleona://channel/<channelIdHex>?n=<encodedName>`

| Param | Format | Purpose |
|---|---|---|
| `<channelIdHex>` | 64-char hex | Channel identity (same as the key used in `ChannelIndex` and `joinPublicChannel`) |
| `n` | URL-encoded UTF-8 | Human-readable channel name (display only — the `channelIdHex` is authoritative) |

**Contrast with ContactSeed URI:** ContactSeed URIs (`cleona://<userIdHex>?...`) carry cryptographic identity material (Ed25519 pubkeys, X25519/ML-KEM device keys, seed peers) because the recipient must establish a KEM-encrypted channel to the contact. Channel URIs carry **no** cryptographic material — the join flow resolves the channel's owner and membership via the DHT-backed `ChannelIndex` (§9.2.1), sends a `CHANNEL_JOIN_REQUEST` to the owner, and the owner auto-accepts (public channels) or manually approves (private channels).

**URI disambiguation:** Parsers distinguish the two URI types by path prefix: `cleona://channel/` → channel link; `cleona://<64-hex-chars>?` → ContactSeed. The path component `channel/` is reserved and cannot collide with a valid 64-char hex userId.

**Deep-link platform registration (V3.1.130+):** The `cleona://` URI scheme is registered as a system-level deep link on mobile platforms so that tapping a channel (or contact) link in an external app (Signal, WhatsApp, email, browser) opens Cleona directly. Android: `ACTION_VIEW` intent-filter with `<data android:scheme="cleona"/>` on `MainActivity` (`singleTop` launch mode — warm-start reuses the existing activity). iOS: `CFBundleURLSchemes` entry in `Info.plist`, URL delivered via `application(_:open:options:)` in `AppDelegate`. Both platforms stash the URI for Dart-side consumption via `MethodChannel` drain on app resume. Desktop platforms (Linux, Windows, macOS) do not register the scheme — URI sharing on desktop uses clipboard copy-paste into the existing ContactSeed/Channel input fields.

**Seed-peer selection criteria** (V3.1.113):

Peers are sorted by **stability tier (§4.9.2) first, then by public-address availability**. Selection proceeds in three passes:

1. **Pass 1: Anchor/Stable peers with public address** (up to 3 slots) — peers classified as `anchor` or `stable` by the Address Stability Score (§4.9.2) that have at least one public IPv4 or global IPv6 address (not link-local `fe80:` and not ULA `fd`/`fc`). These peers have the highest probability of still being reachable when the ContactSeed is scanned days or weeks later. Sorted by stability tier (anchor before stable). All known addresses of each peer are included (private IPv4 + IPv6 + public IPv4 + IPv6), so the scanner can choose the optimal address for its network position.

2. **Pass 2: Remaining relay-capable peers** (up to 5 total) — peers with at least one public IPv4 or global IPv6 address, regardless of stability tier. Fills remaining slots after Pass 1. A global-IPv6 peer is end-to-end reachable from any IPv6-capable network — including DS-Lite mobile carriers where IPv4 is CGNAT-tunneled — and therefore qualifies as relay entry point.

3. **Pass 3: LAN peers** (remaining capacity up to 5 total) — private IPv4 peers, deduplicated by nodeId. Useful when scanner is on the same network.

4. **Fallback:** When no peer with public address exists (e.g. all nodes behind CGNAT without UPnP), the 5 peers with the greatest address diversity are chosen. The scanner will attempt to find a peer through discovery burst (LAN multicast/broadcast) + subnet scan.

**Rationale (V3.1.113):** The previous selection (1 relay-capable + freshness/score) optimized for the synchronous scan case (QR/NFC, both devices online). For asynchronous ContactSeeds (clipboard/email), the seed may be scanned hours or days later — address freshness at generation time is irrelevant; long-term address stability determines whether the seed peers are still reachable. A server with a static IP for 6 months (`anchor` tier) is qualitatively more valuable in a ContactSeed than a phone that was "freshly seen 5 minutes ago" but will have a different IP tomorrow. Without a publicly reachable seed peer in the ContactSeed, a scanner in a different network segment (AP isolation, different subnet, mobile data) has no relay entry point. Since V3.1.116 this no longer means permanent isolation: direct IPv6 to the `a=` addresses and the First-Contact Rendezvous (§4.11.10) provide a mesh-independent path — the seed-peer list accelerates and hardens first contact but is no longer a hard precondition.

**IPv6 address inclusion (V3.1.90+):** When a seed peer qualifies as relay-capable through a global IPv6 address, that IPv6 address **must** be included in the ContactSeed address list, even if the per-peer address limit (currently 3) would otherwise exclude it. Global IPv6 is the DS-Lite bypass path (§4.7) — omitting it from the ContactSeed defeats the relay-capable selection criterion. Implementation: the address list includes up to 3 addresses **plus** any global IPv6 not already in the top 3.

**CR Bootstrap Delivery Lifecycle (V3.1.90+):**

After `addPeersFromContactSeed` (§8.1.1), the scanner waits until at least one seed peer reaches `idPowVerified=true` (triggered by the §5.11 new-neighbor Self-Broadcast) or a timeout of 5 seconds:

1. **Layer 1+2 (target online):** `sendToDevice` — direct addresses from ContactSeed + relay via admitted seed peers (§13.1.2 protected-seed fallback if admission pending).
2. **If no `DELIVERY_RECEIPT` within 15 s (target offline):** Layer 3 — `FIRST_CR_STORE` to each reachable seed peer (§5.5b). `FIRST_CR_STORE` is a **direct infrastructure send** (`sendInfraTo`) to the seed peer's known address — **not** via the DV relay cascade (`sendToDevice`) — and therefore not subject to the D3 relay gate (§13.1.2). The scanner knows the seed peer's addresses from the ContactSeed.
3. **`FIRST_CR_STORE_ACK` from ≥1 seed peer** → message status `storedForDelivery`. The CR is safely parked. Sender shows "zugestellt (gespeichert)" / "delivered (stored)".
4. **`DELIVERY_RECEIPT` from target** → message status `delivered`. The target has the CR.
5. **Neither within retry budget** → status stays `pending_outgoing`, retry timer continues (exponential backoff 10 s → 600 s cap).

The `storedForDelivery` status is the canonical success signal for asynchronous ContactSeeds (email, copy-paste, messaging app). The sender does not need to stay online — the seed peer delivers via `FIRST_CR_DELIVER` when the target reconnects (§5.5b step 5). The event-driven admission wait replaces the previous fixed 3 s delay — on LAN, admission completes in <100 ms; over mobile, the 5 s timeout plus protected-seed fallback ensures the CR proceeds.

#### 8.1.2 Peer-List Rescue Bundle (out-of-band re-entry)

A rescue bundle re-admits an **existing** identity to the mesh when all automatic paths fail — distinct from the ContactSeed, which bootstraps a *first* contact. It carries a snapshot of currently reachable peers, signed by the exporter, and is transferred entirely out-of-band (file, email, messenger, USB, QR). There is **no network-side request for a peer list** — that would be a poll/flood and a storage/eclipse surface; the human in the loop is what keeps this both traffic-free and authenticated.

**Binary format** (format byte `0x05` zstd-compressed, `0x06` uncompressed); URI scheme `cleona://reconnect?...`:

```
[1B version] [8B createdAtMs] [1B channel] [32B exporterDeviceId]
[1B peerCount] [{32B peerNodeId, 1B addrCount, {1B len, addrUTF8}...}...]
[64B exporterEd25519Sig  over all preceding bytes]
[32B networkTag = HMAC(networkSecret, all preceding bytes)]
```

**Peer selection.** Up to ~10 peers, **inbound-reachable first** (`hasPortMapping == true`, all addresses each), then by freshness/score/address-diversity — the same reachability criterion as the relay-capable seed peer in §8.1.1, but a larger set, because a rescue bundle's value is precisely that at least one listed peer is reachable from a foreign network.

**Import validation order:** (1) `networkTag` HMAC — rejects bundles from outside the Closed Network; (2) `exporterEd25519Sig` — if the exporter is a known contact, verify against the stored device key (full provenance; defends against an eclipse bundle injected via a hijacked mail account); otherwise accept HMAC-only at reduced trust; (3) surface the bundle **age** from `createdAtMs` ("list is 6 h old"); (4) contact the listed peers and enter the §12.3 recovery sequence.

**Export privacy.** A peer list is IP↔DeviceID metadata leaving the device into an unencrypted channel; the export action requires a one-time confirmation ("contains your peers' network addresses — share only with someone you trust") and may optionally be passphrase-encrypted (the peer block under a key derived from the passphrase).

**Boundaries:** no `MessageType`, no DHT publish, no auto-retry — a rescue bundle is a static, human-carried artifact only.

**Mesh-convergence gate (cold-start protection):**

After a daemon restart, the `_confirmedPeers` map is empty — no peer has been confirmed by a direct packet in the current session yet. A QR code generated in this window contains incomplete or no seed peers, rendering it useless for scanners on isolated networks. The QR screen therefore implements a **convergence gate**:

- **State tracking:** A session-scoped flag `_hasSessionConfirmedPeers` starts `false` and flips to `true` when the first peer is confirmed by a direct packet (`hopCount == 0`) in the current daemon session. The `_confirmedPeers` map is additionally persisted to disk (via `saveNetworkState()`) and reloaded on start as a warm-start hint — but persisted timestamps do NOT satisfy the convergence gate (they may be stale after a network change).
- **QR screen behavior:**
  - While `_hasSessionConfirmedPeers == false`: the QR screen shows a **convergence indicator** (progress bar or percentage) with the text "Connecting to mesh — QR code will be ready shortly" (i18n). The progress reflects elapsed time since node start relative to typical convergence time (~10s LAN, ~30s cross-subnet). The QR code itself is NOT displayed.
  - Once `_hasSessionConfirmedPeers == true`: the convergence indicator disappears and the QR code is displayed normally with confirmed seed peers.
- **Rationale:** Displaying a QR code with stale or empty seed peers wastes the user's time (scanner cannot connect) and creates a confusing failure mode. The brief wait for mesh convergence is preferable. Persisted `_confirmedPeers` accelerate subsequent sessions where the network hasn't changed (warm start: first PONG arrives within 1-2s from a known peer).

**No User/Device-KEM-PK in the v2 URI**, intentionally:

- **User-KEM-PK**: Alice learns Bob's User-KEM-PK only from CONTACT_REQUEST_RESPONSE. Until Bob accepts the CR, Alice has no authorization to encrypt anything to Bob's user identity.
- **Device-KEM-PK in QR** (removed in rev3 QR binary format): the 1184-byte ML-KEM-768-PK dominated the QR payload, producing QR Version 26-28 (unreliable for phone cameras). The 32-byte `userEd25519Pk` (`ep` parameter) replaces these keys as a **trust-anchor**: it allows verifying DHT-published DeviceKemRecords (§3.5b) and DEVICE_KEM_OFFER signatures. Key material is resolved at runtime via the Deferred Key Exchange (steps 1a-1c below).
- **Device-KEM-PK in URI** (V3.1.96+): the clipboard/share URI **includes** `dxk`+`dmk` (§3.5b Distribution bullet 4). URI length is unconstrained; the 1622-char overhead enables offline first-CR via FIRST_CR_STORE (§5.5b) without a synchronous DEVICE_KEM_REQUEST round-trip. Critical for CGNAT-to-CGNAT clipboard exchange where simultaneous online is not guaranteed.
- **base64url** (RFC 4648 §5): `ep` uses `-`/`_` instead of `+`/`/` and no `=` padding, eliminating the URI-corruption problem that affected v1's standard-base64 `dxk`/`dmk` in messaging apps.

#### Deferred Key Exchange

When the ContactSeed does not contain Device-KEM keys (v2 format), Alice must resolve Bob's Device-KEM-PK before she can build the InfrastructureFrame for the First-CR. The resolution is a 3-step cascade:

```
1a. DHT lookup (primary, < 1s):
    Alice queries the DHT for Bob's DeviceKemRecord (§3.5b):
      key = SHA-256("kem" + bobUserId + bobDeviceId)
    If found: verify record signature against ep (userEd25519Pk from ContactSeed).
    On success: use the enclosed Device-X25519-PK + Device-ML-KEM-768-PK.
    → proceed to step 2.

1b. DEVICE_KEM_REQUEST/OFFER handshake (fallback, if DHT miss):
    Alice sends DEVICE_KEM_REQUEST { targetUserId, targetDeviceId }
    to each SeedPeer from the ContactSeed. SeedPeers relay to Bob.
    Bob responds with DEVICE_KEM_OFFER {
      deviceX25519Pk, deviceMlKemPk,
      userEd25519Sig over (deviceX25519Pk + deviceMlKemPk + nonce)
    }
    Alice verifies the signature against ep.
    On success: cache as synthetic DeviceKemRecord, proceed to step 2.
    Timeout: 8s per SeedPeer, parallel to all SeedPeers.

1c. Inline keys (legacy v1 ContactSeed):
    dxk + dmk are present in the URI/QR → no resolution needed.
    → proceed to step 2.

    If all three paths fail: UI shows "Bob is currently unreachable.
    The contact request will be sent when a connection can be established."
    The CR is queued with exponential backoff (10s → 600s), retrying
    steps 1a-1b on each attempt.
```

**DEVICE_KEM_REQUEST / DEVICE_KEM_OFFER** are InfrastructureFrame messages (§2.3.5 selector list). They are NOT KEM-encrypted (the whole point is that Alice does not yet have Bob's Device-KEM-PK). They are Ed25519-signed at Infrastructure level (Outer-Sig). Anti-abuse: per-sender rate limit 5/min, PoW required.

#### First-Contact-Request Bootstrap Flow

This is the only place in V3 where the §2.3.5 InfrastructureFrame selector list is intentionally relaxed to admit a non-infrastructure MessageType (CONTACT_REQUEST). It must remain strict for all other MessageTypes.

```
1. Alice parses Bob's ContactSeed → bobUserId, bobDeviceId, bobUserEd25519Pk (ep),
   addresses, seedPeers. (v1: also bobDeviceX25519Pk, bobDeviceMlKemPk.)
   Integrity check: SHA-256(networkSecret + ep) == bobUserId.
1a-c. Deferred Key Exchange (see above) → obtains bobDeviceX25519Pk + bobDeviceMlKemPk.
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
7. Send via standard routing (§4.4 sendToDevice). The target is by definition
   not yet a DV neighbor (PING→PONG hasn't completed), so no learned routes
   exist. The cascade's direct-target attempt (§4.4) sends fire-and-forget UDP
   to Bob's addresses from the ContactSeed (a= parameter) — critical when both
   nodes have direct IPv6 reachability (Mobilfunk). In parallel, the relay
   cascade runs via seed peers and defaultGateway.
   RUDP-Light (DELIVERY_RECEIPT) confirms delivery.
   If Bob is OFFLINE: the CR is stored on SeedPeers via First-CR-Mailbox
   (§5.5b), delivered when Bob comes online.
8. Bob's daemon decrypts (using Device-KEM-SK), reads the InfrastructureFrame,
   sees messageType=CONTACT_REQUEST → CR-Bootstrap exception → unwraps the inner
   ApplicationFrame, verifies Alice's User-Sig, KEX-Gate exception applies (§8.2),
   CR lands in the Inbox.
9. Bob accepts → sends CONTACT_REQUEST_RESPONSE as a regular ApplicationFrame
   (now Bob has Alice's User-KEM-PK from the CR payload, so he can encrypt to
   her user-identity normally).
```

After step 9, all subsequent traffic between Alice and Bob runs the regular ApplicationFrame path (§2.4 main pipeline). The InfrastructureFrame-wrap of CR is purely a bootstrap mechanism — never used after the first round-trip. CR-Retry (when the CR was sent but no response arrived) re-uses the same bootstrap path, since Alice still does not have Bob's User-KEM-PK. The retry timer checks peer reachability in this order: (a) recipientUserId in routing table, (b) userId secondary index via getPeerByUserId, (c) seedDeviceIdHex from the persisted ContactSeed bundle. Fallback (c) is necessary because the DV routing table only carries deviceNodeIds — the userId secondary index is often empty for first-CR contacts whose CR-Response has not yet arrived. CR-Retry is triggered both edge-triggered (onPeerAdded, post-discovery, 15s second-sweep) and by a 30s periodic fallback timer that runs while pending outgoing CRs or recently accepted contacts (< 5 min) exist — the timer self-cancels when no work remains. Per-contact exponential backoff (10s, 20s, … capped at 600s) inside the retry method prevents flooding regardless of trigger source.

**Post-CR peer discovery:** After a successful CR exchange (step 9), the scanner has a confirmed contact and at least one active relay peer (from the QR's seed peers). Through this relay peer, the normal mesh-refresh cycle runs automatically: `PEER_LIST_SUMMARY → PEER_LIST_WANT → PEER_LIST_PUSH` (§5.10.5). The scanner thereby learns the **private IP addresses** of all peers in the mesh — including the relay peer itself. From this point on, the relay peer's private address is preferred (§4.6 address priority: same-subnet LAN priority 1 < global IPv6 priority 2 < other-subnet/public IPv4 priority 3), which switches the communication path from mobile data to the local network. This transition happens automatically through the address-scoring logic (PONG from private address → `lastReceivedAt` set → ranked higher) and requires no explicit network switch.

### 8.2 Anti-Spam & KEX Gate

The **KEX Gate** (Key-Exchange Gate) is Cleona's primary protection against unsolicited messaging.

**Rule**: application frames from unknown senders (UserID not in the receiver's contact store) are **silently dropped**, without ACK, without notification, without logging.

**Exceptions** (single-exception list):
- `CONTACT_REQUEST` (initial outreach)
- `CONTACT_REQUEST_RESPONSE` (response to an own CR)
- `IDENTITY_DELETED` (broadcast — when the sender used to be a known user but is now deleted)
- `RESTORE_BROADCAST` (restore of a known contact with new keys)
- `TWIN_SYNC` (intra-identity, from own UserID)

**Context-proof exception**: a frame from a sender who is **not** in the personal contact store is still admitted if it carries a verifiable **context proof** in place of a contact relationship — i.e. proven channel/group membership, a moderation context (a valid channel subscription, or the verifiable juror-selection ticket; the exact moderation admission-ticket is defined with the jury-selection mechanism in §9.3), or — for System Channels (§9.5) — a self-signed `SystemChannelRecord` (§9.5.7) whose inline-pubkey signature verifies and whose `channel_id` is one of the compile-time system-channel constants (§9.5.1). This is why channel/group messages, jury announcements, vote requests, report deliveries, and System-Channel posts (§9.5) pass the gate even though the sender is not a personal contact. It is a **narrow** exception: the proof is verified at the protocol entry point, and a sender presenting neither a valid context proof nor a contact entry is still silently dropped.

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

**Role updates:** `CHANNEL_ROLE_UPDATE` messages must be sent to ALL group/channel members, not just the affected member. The role update handler checks both `channelManager` and `groupManager` to find the correct entity. **Receiver-side epoch sync:** Receivers increment their local `membershipEpoch` on each valid `CHANNEL_ROLE_UPDATE` to stay synchronized with the sender (who incremented in `setMemberRole` per §9.1.4). Without this, a receiver who later becomes owner would broadcast `CHANNEL_INVITE`s with a stale epoch, causing GM-4 rejection by peers who received the intermediate role updates from the previous owner.

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

**Encryption:** Pairwise E2E encryption, identical to regular group chats (see §3.3 Stateless Per-Message KEM). Each channel post is individually encrypted into one `ApplicationFrame` per recipient and delivered via `sendToUser(userId)` using Per-Message KEM. Relay nodes see only encrypted fragments.

**Invitations:** The Owner or Admin generates a signed invite link or QR code. The invite contains the channel ID, channel name, optional channel picture, and optional channel description, encrypted to the invitee's public key. Only the intended recipient can join. The invite must include the complete member list so the invitee knows all participants.

**Discovery:** Private Channels are NOT listed in any public DHT index. Members can only join via direct invitation from an Owner or Admin. This makes channels legally and practically equivalent to private group chats.

**Scalability:** Pairwise encryption has O(n) cost per post. For channels with up to ~50 members this is acceptable. A future migration to MLS (RFC 9420) with O(log n) member changes is architecturally possible for larger channels.

**Media in channels:** File attachments, voice messages, and pasted clipboard content are supported via the `ChannelPost` protobuf's `content_data` field. Media is embedded directly in channel posts and delivered with one `sendToUser` per recipient. Received media files are saved locally to the recipient's `downloads/` or `voice/` directory with image preview support in the UI.

**Profile data:** Groups and channels can have optional pictures (JPEG, max 64 KB) and descriptions. These are set during creation, included in invites, and updated via `updateGroupProfile()` / `updateChannelProfile()`. Profile data is persisted in the group/channel JSON state and included in restore responses.

#### 9.1.4 Group & Channel Membership Consistency (GM-1/GM-4)

**Problem:** Without cryptographic authority enforcement, a compromised or malicious node that knows the group ID can forge GROUP_INVITE updates to inject members or remove legitimate ones (Attack A: Split-View). A removed member who missed the removal can continue posting (Attack B: Ghost Posts).

**Monotonic Epoch:** Every group carries a `membershipEpoch` counter (uint64, starts at 1 for new groups, 0 = legacy). Any membership-mutating operation (`createGroup`, `inviteToGroup`, `removeMemberFromGroup`, `setMemberRole`, `leaveGroup`) increments the epoch before broadcasting the update. Receivers reject updates with `wireEpoch <= localEpoch` (replay/downgrade protection).

**Canonical Membership Hash:** `SHA-256(epoch_le64 || groupId_bytes || Σ sorted(nodeId || role_utf8))`. Only security-relevant fields (identity + role) are included; display names and profile pictures are excluded. The hash is deterministic regardless of member insertion order.

**Hybrid Signature:** The sender (owner or admin) signs the hash with both Ed25519 (`membershipSigEd25519`) and ML-DSA-65 (`membershipSigMlDsa`). Receivers verify both signatures against the sender's public keys from the OLD group state (before applying the update). This prevents a forged update from installing new keys that would validate its own signature.

**Authority Gate (Inbound):** On receiving a GROUP_INVITE for an existing group:
1. Sender must be `owner` or `admin` in the receiver's current member list — otherwise rejected.
2. `wireEpoch > localEpoch` — otherwise rejected (replay).
3. Ed25519 signature over `membershipHash` verified against sender's stored `ed25519Pk` — otherwise rejected.
4. ML-DSA signature verified if present (mixed-net: not all nodes have PQ keys yet).
5. Recomputed hash from the wire member list must match `membershipHash` — otherwise rejected (tampered member list).

**Non-Member Post Drop (Inbound):** `_handleTextV3` checks `group.members.containsKey(senderHex)` and silently drops posts from non-members. This mitigates Attack B for the receiver side.

**Post-Tagging (GM-2 input):** Every group and channel message carries `groupMembershipEpoch` and `groupMembershipHash` in the ApplicationFrameV3 inner fields. On every incoming post, the receiver runs the GM-2 gatekeeper (§9.1.5): if the wire epoch/hash doesn't match local state, the receiver either requests a resync (stale) or logs a split-view anomaly (divergent).

**Mixed-Net Transition:** All new fields are optional (protobuf default 0/empty). Legacy nodes that don't set epoch/hash/sig are accepted as `legacy-unverified` (logged, not rejected). The `minRequiredVersion` gate (§19.5.7) will enforce GM-1 fields once the network has fully upgraded.

**Wire Format:**
| Field | Proto Message | Number | Type |
|-------|--------------|--------|------|
| `membership_epoch` | GroupInviteV3 | 7 | uint64 |
| `membership_hash` | GroupInviteV3 | 8 | bytes (32) |
| `membership_sig_ed25519` | GroupInviteV3 | 9 | bytes (64) |
| `membership_sig_ml_dsa` | GroupInviteV3 | 10 | bytes (~3300) |
| `group_membership_epoch` | ApplicationFrameV3 | 18 | uint64 |
| `group_membership_hash` | ApplicationFrameV3 | 19 | bytes (32) |

**Channel Parity (GM-4):** Private channels (§9.1) use the **identical** membership consistency protocol as groups — same epoch counter, same canonical hash algorithm, same hybrid signature, same authority gate, same wire format (ChannelInvite fields 7–10 mirror GroupInviteV3 fields 7–10). The only difference is the entity type: group operations go through `_broadcastGroupUpdate`, channel operations through `_broadcastChannelUpdate`. The GM-2 gatekeeper (§9.1.5) and resync protocol are likewise dual-mode — a single handler (`_handleGroupMembershipResyncRequest`) dispatches for both groups and channels based on entity ID lookup.

#### 9.1.5 Split-View Detection & Resync (GM-2)

Every group and channel post carries `groupMembershipEpoch` and `groupMembershipHash` in the ApplicationFrameV3 inner fields (§9.1.4 wire format). On every incoming post, the receiver runs the GM-2 gatekeeper (`_checkGroupPostMembership`):

1. **Non-member posts** are silently dropped (same as §9.1.4 Non-Member Post Drop).
2. **Legacy posts** (epoch 0 or empty hash) pass without GM-2 checks.
3. **Epoch + hash match:** Normal — post is accepted.
4. **Wire epoch > local epoch:** The sender has a newer membership state. The receiver sends a `GroupMembershipResyncRequest` to the group/channel owner (edge-triggered: only once per observed epoch, tracked via `_resyncRequestedAtEpoch` map). The post is accepted — the sender is a known member; the receiver is just behind.
5. **Same/lower epoch, different hash — Split-View Anomaly:** The receiver and sender have divergent member lists at the same epoch. This indicates a forked membership state (Attack A from §9.1.4). The anomaly is logged (`GM-2: SPLIT-VIEW`), and `membershipMismatch` is set on the displayed message for future UI surfacing.

**Resync Protocol:**

| Step | Actor | Action |
|------|-------|--------|
| 1 | Stale receiver | Sends `GroupMembershipResyncRequest` (`MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST`, type 54) with `groupId` + `localEpoch` to the group/channel owner |
| 2 | Owner | Validates: (a) is actual owner, (b) sender is member, (c) sender's epoch < owner's epoch |
| 3 | Owner | Responds with a fresh `GROUP_INVITE` / `CHANNEL_INVITE` broadcast (same signed update as §9.1.4) |

The resync request is edge-triggered per group/channel — a single request per newly observed higher epoch. This prevents resync storms when multiple posts arrive from a sender with newer state. The owner handler is dual-mode: it dispatches to `_broadcastGroupUpdate` or `_broadcastChannelUpdate` based on entity ID lookup.

**Wire Format:**

| Field | Proto Message | Number | Type |
|-------|--------------|--------|------|
| `group_id` | GroupMembershipResyncRequest | 1 | bytes |
| `local_epoch` | GroupMembershipResyncRequest | 2 | uint64 |

### 9.2 Public Channels

Public, openly discoverable broadcast channels with decentralized content moderation.

> Full specification: `docs/CHANNELS.md`

#### 9.2.1 Channel Discovery & Index

Public channels are listed in a **compressed DHT index** (~200–300 bytes per channel). Users discover channels via a searchable "Suche" tab (default on first app start). The index stores: name, language, content rating (adult/general), description snippet, subscriber count, Bad Badge status (level + timestamps for badge set and correction submitted).

**Channel-URI sharing (V3.1.130+):** In addition to DHT search, channels can be shared via `cleona://channel/<channelIdHex>?n=<encodedName>` links. The link can be forwarded within Cleona (sent as a text message to any contact, group, or channel — rendered inline as a tappable invite card with "Join" button) or shared externally via the OS share sheet (Signal, WhatsApp, email, etc.). External links open the app via deep link (Android `ACTION_VIEW` intent-filter, iOS `CFBundleURLSchemes`) and show a join confirmation dialog. The join flow uses the existing `joinPublicChannel` path: ChannelIndex lookup → local subscription → `CHANNEL_JOIN_REQUEST` to the channel owner. Unlike ContactSeed URIs, channel URIs carry no cryptographic material — the channel's identity and membership are resolved entirely via the DHT-backed ChannelIndex.

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

**Channel-level reports** → Reporter selects 3-10 specific posts as evidence. When the report counter reaches a threshold, a **jury of 5-11 deterministically selected users** reviews the evidence and votes. A verdict requires a **hard quorum** (§9.3.1a); abstentions and timeouts are replaced by deterministic re-selection (max. 2 rounds) — a jury that cannot reach quorum produces **no consequence**.

#### 9.3.1a Verifiable Juror Selection & Signed Verdicts

The jury is the trust anchor of decentralized moderation, so juror selection must be **recomputable by every node** — not asserted by whoever initiated the jury.

**Juror registry (opt-in).** Nodes with "Review channel reports" enabled publish a **JurorAvailabilityRecord** into the Kademlia ring (pattern: Liveness record, §4.3): `juror_record_id = SHA-256("juror" || userPubKey)`, the user's Ed25519 + ML-DSA public keys, creation epoch, hybrid self-signature, adaptive TTL. The record deliberately carries **no language and no adult flag** — both remain local attributes, answered as a plain yes/no when a jury request arrives (preserving the §3.1 anonymity principle and the existing §9.3.1 language-eligibility model).

**Selection point.** When the report threshold for a channel+category is crossed, the selection point is `H = SHA-256("jury-select" || channelId || categoryIndex || epochDay || juryRound)`. The jury consists of the `jurySize` registered jurors whose `juror_record_id` is XOR-closest to `H`. None of the inputs is freely grindable by a reporter (the reporter-chosen `reportId` is deliberately **excluded**); `epochDay` is the UTC day the threshold was crossed, `juryRound` starts at 0 and increments for replacement rounds. **Juror qualification** is checked by verifiers, not asserted. Three gates: (1) identity age ≥ 7 days (`jurorMinAge`, via record epoch), (2) `isAdult` flag set (`jurorRequiresAdult`, self-declaration per §9.2.2), (3) "Review channel reports" enabled in the node's settings (`jurorRequiresReviewEnabled`). Additionally, the anti-Sybil reachability check (§9.4.1) applies for CSAM-category reports.

**Juror-selection ticket.** A juror proves legitimacy by reference: its signed vote plus its registry record allow any verifier to recompute `H` and confirm the juror lies within the closest set. This is the "verifiable juror-selection ticket" referenced by the §8.2 context-proof exception and §9.4.1.

**Consistency limits (by design, stated explicitly).** The DHT has no global consensus; K-closest views differ under churn. Verifiers therefore apply a **tolerance check**: a verdict signer is accepted if it lies within the **top 2× jurySize** records closest to `H` from the verifier's own lookup. The initiator additionally embeds an **eligibility-snapshot hash** (hash of the candidate record IDs it observed) into the jury request and verdict as an audit trail. Residual risk: an attacker eclipsing the DHT region around `H` can bias both selection and verification; mitigations are the qualification gates, the epoch binding (the region is unpredictable in advance), independent verification by every gossip recipient, and the hard quorum. This residual risk is accepted and documented — full prevention would require global consensus, which Cleona does not have.

**Signed verdicts as write authorization.** Every jury vote is hybrid-signed (Ed25519 + ML-DSA, pattern H-2) over the canonical verdict core `SHA-256(juryId || channelId || reportId || vote || consequence || epochDay || juryRound)`. The jury result carries the collected per-juror signatures. **No node applies a Bad-Badge level ≥ 1 or a Tombstone unless it verifies ≥ quorum distinct valid juror signatures whose signers pass the tolerance check.** Channel-index gossip entries carrying a badge/tombstone reference the verdict via `moderation_proof_hash`; the full proof is stored as a DHT record under `SHA-256("modproof" || channelId)` and fetched on demand before the badge level is adopted. Unproven badge levels are treated as badge 0.

**Hard quorum.** A verdict passes only if `votes_approve ≥ ceil(juryMajority × nominal jury size)` — the denominator is the **nominal** jury size, never the number of respondents. With the production 5-juror minimum and 2/3 majority this means ≥ 4 approvals; partial responses never lower the bar.

**Mixed-net rollout.** Phase 1 (observe/verify-only): new builds emit and verify signatures and count verification failures as telemetry; unproven writes from legacy builds are still applied. Phase 2, gated behind `minRequiredVersion` (§19.5.7): unproven badge/tombstone values are ignored (the entry degrades to badge 0 — receipt of user payloads is **never** dropped), and unsigned votes do not count toward quorum. This mirrors the D1/SR-2/H-2 legacy-record handling.

**Jury language selection:** The language for jury selection comes from the **reported channel's language field** (set at creation, stored in the DHT index), not from any attribute on the juror's identity. A node is eligible for jury duty if it subscribes to at least one channel with the same language setting — a behavioral proxy for language competence that requires no metadata on the identity itself. For channels with `language: multi`, nodes of all languages are eligible. This preserves the anonymity principle (see §3.1 Identity Model): no language attribute is stored on or published with any identity. Eligibility is determined locally from the node's own subscription list and answered as a simple yes/no to jury requests.

**Consequences:** NSFW reclassification, Bad Badge (3-stage escalation, see §9.3.2), or Tombstone deletion (DHT entry marking channel as removed).

#### 9.3.1b Jury Configuration & Operational Parameters

All numerical parameters are centralized in `ModerationConfig` (§9.4.2). The production defaults for jury selection:

| Parameter | Value | Description |
|-----------|-------|-------------|
| Report threshold | 3 | Independent reports on a channel+category before a jury is convened |
| Jury size | 5–11 | `min(juryMaxSize, max(juryMinSize, availableJurors × juryMaxPercent))` |
| Jury max % | 1% | Maximum fraction of available jurors to select |
| Vote timeout | 2 days | After which non-responders are replaced (§9.3.4 check 1) |
| Hard quorum | ⌈2/3 × nominal⌉ | Approvals needed; denominator = selected jurors, never responders |
| Replacement rounds | 2 | Maximum re-selection attempts for non-responders |
| Tolerance factor | 2× | Verifiers accept jurors within top 2× jurySize closest to H |

Test presets with drastically shortened values exist for automated E2E testing — see §9.4.2 for the full comparison table. The config also provides calculation methods: `effectiveJurySize(availableJurors)`, `juryHardQuorum(nominalJurySize)`, `juryApproved(approvals, nominalJurySize)`, and time-based checks (`isJuryVoteExpired`, etc.).

#### 9.3.1c Jury Orchestration & Verdict Delivery

**Initiation.** A jury is convened automatically when the report counter for a channel+category reaches the `reportThresholdForJury` (production: 3 independent reports). The node that crosses the threshold becomes the **jury initiator** — it selects jurors and manages the session. There is no centralized coordinator; any node that independently observes the threshold performs the same deterministic selection (§9.3.1a) and arrives at the same jury composition.

**Juror Selection.** The initiator builds the eligible pool from its accepted contacts, excluding: (a) the initiator itself, (b) members/subscribers of the reported channel (independence), (c) reporters for this channel (conflict of interest). From this pool, `JurorRecord`s are constructed (keyed by `SHA-256("juror" || ed25519Pk)`) and the XOR-closest to the selection point `H` (§9.3.1a) are selected. The `eligibilitySnapshotHash` — a hash of all candidate record IDs — is computed as an audit trail and embedded in both the jury request and the final verdict.

**Jury Request.** A `JuryRequestMsg` is sent to each selected juror via `MTV3_CHANNEL_JURY_VOTE` (KEM-encrypted ApplicationFrame). The request contains: `juryId`, `channelId`, `reportId`, `category`, evidence post IDs, report description, `channelName`, `channelLanguage`, `epochDay`, `juryRound`, `eligibilitySnapshotHash`. The KEX Gate (§8.2) admits jury requests via the context-proof exception — the juror-selection ticket (§9.3.1a) serves as the context proof.

**Juror Response.** Each juror reviews the evidence and responds with a `JuryVoteMsg` via the same `MTV3_CHANNEL_JURY_VOTE` type: `juryId`, `reportId`, `vote` (approve/reject/abstain), `reason`, hybrid signatures (Ed25519 + ML-DSA) over the canonical verdict core hash (§9.3.1a), `epochDay`, `juryRound`. Both signatures are required for the vote to count toward quorum in Phase 2 (§9.3.1a mixed-net rollout).

**Timeout & Replacement.** The moderation timer (§9.3.4) checks active jury sessions every tick. When `juryVoteTimeout` (production: 2 days) expires, non-responding jurors are identified. A new selection point `H` is computed with `juryRound + 1` (yielding different XOR-closest jurors), and replacement jurors are selected from the remaining eligible pool — excluding all previously selected jurors. Votes and signatures from previous rounds carry over. Up to `juryReplacementRounds` (production: 2) replacement attempts are made. If the quorum is still not reached after the final round, the session resolves with **no consequence**.

**Resolution.** When all votes are in (or the final replacement round times out), the hard quorum is evaluated: `votes_approve ≥ ⌈juryMajority × nominal jury size⌉`. If met, the consequence is applied locally by the initiator (NSFW reclassification, Bad Badge increment, or Tombstone). For CSAM plausibility juries (§9.3.3), a rejection lifts the temp-hide and cancels any active Stage 3 objection window. All associated reports are marked as resolved.

**Result Broadcast.** A `JuryResultMsg` is sent to all jurors, containing: `juryId`, `reportId`, `channelId`, consequence, vote counts (approve/reject/abstain), `newBadBadgeLevel`, collected `JurorVerdictSig`s (per-juror: UserID + Ed25519 sig + ML-DSA sig + vote), `eligibilitySnapshotHash`, `epochDay`, `juryRound`.

**Verdict as DHT Proof.** The full signed verdict is stored as a `ModerationProofRecord` DHT record under `SHA-256("modproof" || channelId)`. Channel-index gossip entries carrying a badge/tombstone reference this proof via `moderation_proof_hash` (ChannelIndexEntryProto field 13). Before adopting a badge level, a receiving node fetches the proof from the DHT, verifies ≥ quorum distinct juror signatures (tolerance check + hybrid signature verification per §9.3.1a), and only then applies the badge. Unproven entries degrade to badge 0. Phase 1 (observe-only) logs a warning for unproven writes; Phase 2 rejects them (§9.3.1a mixed-net rollout).

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
| 3 | `max(20, subscribers × 0.10)` independent reports | Channel enters **extended-hide** (same as Stage 2 visibility, NOT immediate deletion). A mandatory **14-day objection window** opens; the admin can file an objection triggering a plausibility jury (identical to Stage 2). After the window closes without successful objection, a Tombstone is written — accompanied by a `CsamReporterQuorumProof` (list of reporter UserIDs + hybrid signatures over their report IDs). The proof is stored as a DHT record (`SHA-256("modproof" || channelId)`) and allows any node to verify that the Stage-3 threshold was reached by distinct, qualified reporters. Without this proof, a Tombstone is not applied. |

**Example thresholds:** 50 subscribers → 10/20 reporters; 500 subscribers → 25/50 reporters; 5,000 subscribers → 250/500 reporters. Minimum is always 10 for temporary, 20 for permanent — always double-digit.

**Admin objection (Stage 2):** When temporarily hidden, the admin can file an objection. This triggers a jury, but the jury does NOT see the content. Instead, they review: channel name/description, posting frequency, reporter text descriptions, and whether the channel's topic plausibly relates to CSAM allegations. The jury decides: "Plausible" (hiding maintained) or "Appears fabricated" (channel restored). This gives legitimate channel operators a defense against coordinated false reports.

**Elevated reporter requirements (CSAM only):** 30-day identity age, 10+ bidirectional conversations, 100+ received messages, 3+ long-term contacts (14+ days), `isAdult` flag required, 7-day reporting cooldown across all categories.

**Anti-abuse (Option C):** 7-day reporting cooldown as "stake" + strikes only for demonstrably malicious reports (channel restored AND reporter discovered channel shortly before reporting). 3 strikes = CSAM reporting permanently disabled for that identity.

#### 9.3.4 Moderation Timer

All time-based moderation limits are enforced by a **periodic timer** (`_moderationTimer`) in `CleonaService`. Without this timer, time-dependent actions (badge expiry, jury timeouts) would only fire when triggered by unrelated events — which in production (30-day probation, 2-day jury timeout) might never happen.

**Timer interval:** Adaptive — 1/6 of the shortest configured timeout, clamped to [5 seconds, 5 minutes]. When the test preset is active with sub-5-second timeouts, the timer ticks every 1 second.

**Four checks per tick:**

1. **Jury vote timeout:** Active jury sessions that exceed `juryVoteTimeout` trigger **deterministic replacement** of non-responders: the next-closest registered jurors at `juryRound + 1` are selected (same algorithm as §9.3.1a, incremented round parameter). Votes and signatures from the previous round carry over. A maximum of `juryReplacementRounds` rounds are attempted (production: 2). If the quorum is still not reached after the final round, the session resolves with **no consequence** — verdicts are never derived from "whatever votes happen to be cast".
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

Moderation messages (jury announcements, vote requests, report deliveries) come from nodes that are typically **not** personal contacts, so they are admitted via the §8.2 **context-proof exception** — each carries a verifiable moderation context (channel subscription / juror-selection ticket) that the gate checks at the protocol entry point. This is **not** a privileged bypass: a moderation frame without a valid, verifiable context proof is silently dropped exactly like an unsolicited message, sharing the same anti-spam baseline. (The verifiable juror-selection ticket itself is specified with the jury mechanism in §9.3 — see the security review.)

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
| Jury hard quorum (approvals) | 4 | 2 |
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
| Juror-set tolerance factor | 2 | 2 |
| Jury replacement rounds | 2 | 2 |
| CSAM objection window | 14 days | 10 seconds |

The config also provides calculation methods: `independenceThreshold(totalUsers)`, `effectiveJurySize(availableJurors)`, `csamStage2Threshold(subscribers)`, `csamStage3Threshold(subscribers)`, `hasJuryMajority(votesFor, totalVotes)`, `juryHardQuorum(nominalJurySize)` / `juryApproved(...)` (hard quorum against the nominal jury size, §9.3.4), and time-based checks (`isJuryVoteExpired`, `isProbationComplete`, etc.).

**Enums:** `ReportCategory` (6 categories), `JuryVote` (approve/reject/abstain), `JuryConsequence` (reclassifyNsfw/addBadBadge/deleteChannel/noAction), `BadBadgeLevel` (none/questionable/repeatedlyMisleading/permanent), `VerdictVerification` (verified/legacyUnproven/failed — used by receive-side gossip verification, §9.3.1a).

### 9.5 System Channels — Bug Log & Feature Requests

Cleona ships two **default public channels** that every node knows at compile time. They provide decentralized, opt-in bug reporting and community-driven feature prioritization — without any external service, telemetry endpoint, or analytics backend. Both channels are moderated by the same jury mechanism as all other public channels (§9.3).

#### 9.5.1 Channel Identity

Both channels have deterministic, well-known IDs derived from fixed strings:

```
BUG_LOG_CHANNEL_ID      = SHA-256("cleona-system-channel-bug-log")
FEATURE_REQ_CHANNEL_ID  = SHA-256("cleona-system-channel-feature-requests")
```

These IDs are compile-time constants. The channels are pre-seeded in the DHT index on first node boot (if not already present). They have no owner — the `ownerNodeId` field is set to the zero hash (`0x00…00`), and owner-only actions (delete channel, change settings) are disabled for zero-owner channels. Moderation is handled exclusively by the jury system (§9.3).

Both channels appear in every node's channel list under a "System" category. They are not auto-subscribed — the user sees them listed and can choose to subscribe. Posts to these channels are always visible to all nodes (public channel semantics, §9.2).

#### 9.5.2 Bug Log Channel — Automatic Crash Reporting

**Crash detection:** A global `FlutterError.onError` + `PlatformDispatcher.onError` + Dart `Zone.onError` handler catches uncaught exceptions and assertion failures. On crash, the handler collects a structured report:

```
CrashReport {
  fingerprint:    SHA-256(exceptionType + top5FramesNormalized)   // line numbers stripped
  appVersion:     string        // e.g. "3.1.72"
  platform:       string        // e.g. "linux-x86_64", "android-arm64", "ios-arm64"
  dartVersion:    string
  timestamp:      int64         // Unix ms
  exceptionType:  string        // e.g. "StateError"
  exceptionMsg:   string        // truncated to 500 chars
  stackTrace:     string        // top 20 frames, normalized (no absolute paths)
  logTail:        string        // last 30 log lines from CLogger ring buffer
  peerCount:      int32
  uptime:         int64         // seconds
  memoryUsage:    int64         // bytes, from ProcessInfo
}
```

**No private data:** The report deliberately excludes: message content, encryption keys, contact lists, IP addresses, node IDs, identity names, conversation history, and file paths (normalized to relative).

**Fingerprint:** The fingerprint is computed from the exception type and the top 5 stack frames with line numbers stripped and paths normalized. This groups crashes by root cause — the same bug on different versions or platforms produces the same fingerprint.

**Duplicate detection and counting:**

Before showing the popup, the node checks its local copy of the Bug Log channel for an existing post with the same fingerprint.

- **No match (new crash):** The node shows the **consent popup** (§9.5.4 Variant 1). If the user approves, a new `CrashReport` post is published to the channel.
- **Match found (known crash):** The node shows the **known-crash popup** (§9.5.4 Variant 2) with a link to the existing post. A lightweight "+1" reply is silently posted to the original (no second opt-in needed — the reply contains only platform, version, and timestamp, no new data). The original post's UI displays an aggregated counter: "47× reported by 12 nodes".
- **Rate limit reached:** The node shows the **rate-limit popup** (§9.5.4 Variant 3).

**+1 reply format:**

```
CrashDuplicateReply {
  fingerprint:    bytes         // must match parent post
  appVersion:     string
  platform:       string
  timestamp:      int64
}
```

**No manual text input:** The Bug Log channel does not provide a free-text input field. All posts are structured: automatic `CrashReport` posts (§9.5.2), manual `ContactIssueReport` posts (§9.5.2a), or manual `LogReport` posts (§9.5.2b). The input area shows a read-only info bar ("Crash-Reports werden automatisch gepostet") and a "Log veröffentlichen" button.

#### 9.5.2a Contact Issue Reporting — Manual Diagnostic Reports

When a contact exchange fails silently (`pending_outgoing` contact does not transition to `accepted`), the user can trigger a structured diagnostic report from the contact list.

**Trigger:** Contacts with status `pending_outgoing` appear in a dedicated "Wartende Kontakte" section of the contact list. Each entry shows a three-dot menu with "Problem melden".

**ContactIssueReport:**

```
ContactIssueReport {
  fingerprint:        SHA-256("contact-issue" + targetUserIdHex)
  appVersion:         string
  platform:           string
  timestamp:          int64
  contactIdShort:     string        // first 16 hex chars of target user ID
  contactName:        string
  seedAgeSeconds:     int64         // time since CR was sent
  natType:            string        // fullCone / symmetric / unknown / …
  peerCount:          int32         // active peers in routing table
  confirmedPeerCount: int32         // bidirectionally confirmed this session
  hasPortMapping:     bool          // UPnP/PCP success
  peerSeenInDht:      bool          // target user found in routing table
  logTail:            string        // last 30 CLogger lines
  uptimeSeconds:      int64
}
```

**Fingerprint:** Deterministic per target contact (`SHA-256("contact-issue" + userId)`), enabling dedup across multiple reports for the same failed contact exchange.

**Dual-path export (Henne-Ei-Problem):** A node attempting its first contact may not yet be connected to the Cleona network, making the Bug Log channel unreachable. The dialog therefore offers two paths:

- **Export (always available):** Saves a human-readable `.txt` file via the platform file picker (`FilePicker.saveFile`). The user can send this file via email, Signal, or any other channel to the developer or the other party.
- **Post to Bug Log (only when `peerCount > 0`):** Publishes the report as a structured JSON post to the Bug Log channel, rendered with the same card UI as crash reports but with a distinct tertiary-color scheme and contact-specific fields. When no peers are connected, this button is hidden and an info text explains the limitation.

**Privacy:** The report contains no message content, no full node IDs (only first 16 hex chars), no encryption keys, and no IP addresses. The log tail is the same truncated, path-normalized excerpt used by CrashReport.

#### 9.5.2b Manual Log Report — User-Triggered Diagnostics

When no crash occurs but the application behaves unexpectedly (logic error, missing message, wrong routing), the user can publish a diagnostic log snapshot from the Bug Log channel's input area via "Log veröffentlichen".

**LogReport:**

```
LogReport {
  appVersion:     string
  platform:       string
  timestamp:      int64
  logTail:        string        // last 50 CLogger lines, paths normalized
  peerCount:      int32
  uptimeSeconds:  int64
  memoryBytes:    int64
  natType:        string        // fullCone / symmetric / unknown
  hasPortMapping: bool
  routeCount:     int32         // active DV routes
}
```

**Preview and consent:** Clicking "Log veröffentlichen" opens a preview dialog showing the exact report content (system info + all log lines) in a scrollable monospace view. A privacy notice explains that file paths are anonymized but network data (IPs, node IDs in log lines) is preserved for diagnostic value. The user must explicitly confirm with "Veröffentlichen" before the report is posted.

**Rate limiting:** Shares the same rate limiter as CrashReport (3/hour, 10/day per node).

**Rendering:** Displayed as a card with secondary-color scheme, showing system info chips (platform, NAT, UPnP status) and the first 8 log lines with a "… N weitere Zeilen" indicator.

#### 9.5.3 Feature Request Channel — Community Voting

Users post feature requests as free-text posts. On submission, a **poll is automatically attached** to the post:

```
Auto-Poll {
  question:    "<first line of feature request, truncated to 100 chars>"
  pollType:    SINGLE_CHOICE
  options:     ["Ja, umsetzen", "Nein", "Egal"]
  settings:    { anonymous: false, allowVoteChange: true, showResultsBeforeClose: true }
}
```

The poll uses the existing §11.3 infrastructure. No additional protocol messages are needed.

**Sorting:** The channel UI sorts feature requests by vote count (descending: "Ja" votes minus "Nein" votes), with ties broken by newest first. This is a local UI sort — no network-level ordering.

**Manual posting without poll:** Not supported. Every post in this channel gets an auto-poll. This keeps the channel focused and sortable.

**Programmatic submission API (D3, V3.1.117):** `submitFeatureRequest(title, body)` posts a `SystemChannelRecord` (§9.5.7) with an embedded auto-poll whose default vote is "Ja" (Auto-Ja embedded) — the submitter implicitly supports their own request. Receiver-side rate limit: 3 FR posts/day per node (enforced on receive, not on send — a sender cannot spam a receiver's storage beyond the receiver's daily cap; the §9.5.5 storage cap + eviction is the backstop). Sorting is `net_votes = Ja − Nein` (unchanged formula, applied consistently across the embedded-poll path and the manual-post path).

#### 9.5.4 Crash Popup UX

Three popup variants, shown as a modal dialog over the current screen:

**Variant 1 — New crash (consent required):**
```
┌─────────────────────────────────────────┐
│  ⚠ Ein Fehler ist aufgetreten           │
│                                         │
│  Folgende Daten würden im öffentlichen  │
│  Bug-Log-Kanal veröffentlicht:          │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Version: 3.1.72                 │    │
│  │ Plattform: linux-x86_64        │    │
│  │ Fehler: StateError — No elem…  │    │
│  │ Stack: _handleTap (chat_scr…   │    │
│  │        build (message_bubbl…   │    │
│  │        ... (18 weitere)        │    │
│  │ Logs: [letzte 30 Zeilen]       │    │
│  └─────────────────────────────────┘    │
│                                         │
│  [ Veröffentlichen ]    [ Verwerfen ]   │
│                                         │
│  Bei "Verwerfen" wird der Bug nicht     │
│  erfasst und kann nicht bearbeitet      │
│  werden.                                │
└─────────────────────────────────────────┘
```

**Variant 2 — Known crash (info + link):**
```
┌─────────────────────────────────────────┐
│  ℹ Bekanntes Problem                    │
│                                         │
│  Dieses Problem ist bereits erfasst     │
│  (47 Meldungen).                        │
│                                         │
│       [ Zum Bericht → ]    [ OK ]       │
└─────────────────────────────────────────┘
```

"Zum Bericht" navigates to the Bug Log channel, scrolled to the matching post. "OK" dismisses the popup.

**Variant 3 — Rate limit reached:**
```
┌─────────────────────────────────────────┐
│  ℹ Fehler aufgetreten                   │
│                                         │
│  Tägliches Meldelimit erreicht.         │
│  Der Fehler wurde lokal protokolliert.  │
│                                         │
│                  [ OK ]                 │
└─────────────────────────────────────────┘
```

#### 9.5.5 Storage Limits & Eviction

| Parameter | Bug Log | Feature Requests |
|-----------|---------|------------------|
| Max channel storage | 25 MB | 25 MB |
| Max single post (auto) | 256 KB | — |
| Max single post (manual) | 2 MB | 2 MB |
| Max contact issue report | 2 MB | — |
| Max log report | 256 KB | — |
| Rate limit | 3 reports/hour, 10/day per node | 3 posts/day per node |
| Eviction strategy | Oldest posts first | Fewest votes first, then oldest |

**Eviction** is enforced locally: when the local storage for a system channel exceeds 25 MB, posts are evicted according to the channel's strategy. Evicted posts are removed from local storage only — other nodes may still retain them until their own storage limit triggers eviction. This is consistent with standard channel post lifecycle (§9.2).

**Feature Request eviction detail:** Posts are ranked by `net_votes = count("Ja") - count("Nein")`. Posts with the lowest `net_votes` are evicted first. Among posts with equal `net_votes`, the oldest is evicted first. This ensures popular requests survive and low-interest requests are naturally pruned.

#### 9.5.6 Moderation

Both system channels are public channels and subject to the full moderation pipeline (§9.3):

- **Content reports** trigger the jury mechanism (§9.3.1). Spam, off-topic, or abusive posts are handled identically to any public channel.
- **Bad Badge** applies to both channels (§9.3.2).
- **CSAM procedure** applies (§9.3.3) — though extremely unlikely given the channels' purpose.
- **Anti-Sybil** (§9.4) protects against vote manipulation on feature requests and fake crash reports.
- **KEX Gate** (§8.2) applies via the **context-proof exception**: System-Channel posts are admitted on a self-signed `SystemChannelRecord` (§9.5.7) whose inline-pubkey signature verifies and whose `channel_id` is one of the compile-time system-channel constants (§9.5.1) — not on personal-contact status and not on a subscriber-registry membership (system channels carry no subscriber registry by design, §9.5.7). A post whose inline-pubkey signature does not verify, or whose `channel_id` is not a known system-channel constant, is silently dropped.

No special moderation rules are needed. The existing infrastructure covers all abuse scenarios.

#### 9.5.7 SystemChannelRecord-Gossip, Anti-Entropy & RETRACT (V3.1.117)

System channels are ownerless (zero-hash owner, §9.5.1) and intentionally carry no subscriber registry — a fresh or long-offline node must still receive every system-channel post without depending on a fan-out owner. Normal channels rely on the owner's per-recipient `sendToUser` fan-out (§9.2); system channels have neither owner nor subscriber list, so a dedicated gossip-based distribution is required.

**Record model (D1):**
- `SystemChannelRecord` is a **new wire type** (D1-S1), distinct from `CHANNEL_POST`. It is a self-contained, self-signed record carrying the post content plus the author's inline pubkeys.
- **Self-signed (hybrid, pattern H-2):** the record carries both an Ed25519 and an ML-DSA-65 signature over its canonical content, plus the author's inline Ed25519 and ML-DSA-65 pubkeys. A receiver that has never seen the author verifies the signature from the inline pubkeys alone — no prior Contact lookup or KEX round-trip is required (this is the KEX-Gate context-proof criterion, §8.2 / §9.5.6).
- **UserID-Founding-Binding:** the record binds the author `UserID` to its founding key set. Later key rotations chain through the AuthManifest rotation chain (§4.3); the founding binding is the trust anchor for unknown-author admission, mirroring the D1 trust-anchor pattern.
- **`channel_id`:** one of the two compile-time system-channel constants (§9.5.1). A record whose `channel_id` is not a known system-channel constant is silently dropped at admission (§8.2).

**Anti-Entropy (D1-S2 — InfrastructureFrame gossip transport):**

The four gossip messages `SYSCHAN_DIGEST`, `SYSCHAN_SUMMARY`, `SYSCHAN_WANT`, `SYSCHAN_PUSH` are **InfrastructureFrame** messages (added to the §2.3.5 selector list, BOOT path — mirroring peer-list gossip, §2.3.5). They are routing-metadata anti-entropy, not user content; the Closed-Network HMAC plus the inner record's self-signature provide authenticity. Insider visibility of "which system-channel records a peer holds" is by design (same rationale as all BOOT-path routing metadata, §4.10 threat-model addendum).

- **Cadence:** piggy-backed on the existing hourly channel-index gossip slot (§9.2 channel-index gossip) — no new timer, no new periodicity.
- **Flow:** Digest → Summary → Want → Push. A peer advertises a digest of its local record set; the counterpart returns a summary of what it lacks; the first peer issues Want for the missing records; the second responds with Push carrying the self-signed `SystemChannelRecord` blobs.
- **Initial sync:** a freshly-subscribing node requests the full record set once (edge-triggered on subscribe), then participates in the hourly anti-entropy.
- **No subscriber registry:** the anti-entropy set is the full local record set per system channel; a peer compares digests and pulls what it lacks. The 25 MB storage cap (§9.5.5) bounds the set.
- **Push budget:** `k` adaptive (rate-limited per relay, §4.11-style backoff), TTL 5, dedup by record fingerprint — no per-event connection (the Nostr provider reuses a single WebSocket per relay/cycle, §4.11.6 / C2).

**Feature-Request channel integration:**
- The FR auto-poll is **embedded** in the `SystemChannelRecord` (no separate `POLL_CREATE` round-trip). Votes are open records tallied locally — no snapshot fan-out (the §11.3.3.2 channel-poll pattern inverted for an ownerless channel).

**RETRACT Tombstone (D2):**
- **Author-only:** the retract signer must match the `SystemChannelRecord` author (same inline-pubkey signature path).
- **Persisted as a tombstone** (not an in-place delete), so a late-joining node sees "this was retracted by author" and does not resurrect the post via anti-entropy.
- **GC rule:** the tombstone plus the record's fingerprint metadata are retained past the tombstone itself, so the `+1` dedup counter (§9.5.2) for the same fingerprint is not re-incremented by a re-surfaced original.
- **No time window:** an author may retract their own system-channel post at any time — consistent with the general unbounded-deletion model (§14.6: deletion is unbounded for all chats). System-channel retraction needs no special time-window exception; only the tombstone mechanism is added (to survive anti-entropy).
- **UX:** long-press → retract sheet on a `SystemChannelPost`. Gesture collision with the A1 SelectionArea/SelectableText work is resolved in the implementation.

**Spam posture (unchanged):** admission is the §8.2 context-proof (self-signed record + known `channel_id`); the per-identity cost is the existing admission PoW (§13.1.2, already required for network roles since V3.1.90, enforced via the D5 collective quota, §13.1.8) plus the receiver-side rate limits (§9.5.5: 3 posts/day FR, 10/day Bug-Log) and jury moderation (§9.3). No new admission-PoW gate is added at the KEX-Gate layer — message delivery remains ungated by admission, per the §13.1.2 Phase-2 principle.

---

## 10. Calls

Real-time voice and video calls require a different encryption and delivery approach than chat messages. Per-Message KEM (§3.3) adds ~1.1 KB overhead and a KEM operation per packet — unacceptable for voice (50 packets/second) and video (hundreds of packets/second). Calls use an **ephemeral symmetric key** negotiated once at call start and use a separate, optimised frame pipeline that bypasses the standard ApplicationFrame steps that do not pay for themselves on per-frame ciphertext.

### 10.1 Voice/Video Calls (1:1)

A 1:1 call between two users consists of two phases:

1. **Setup phase** — `CALL_INVITE` and `CALL_ANSWER` are exchanged as ordinary `ApplicationFrame`s via `sendToUser(userId)`. They run through the full layered encryption pipeline (§2.4), including per-message KEM and full hybrid Ed25519 + ML-DSA-65 signatures. This is where authenticity for the entire call is established.
2. **Live-media phase** — `CALL_AUDIO` and `CALL_VIDEO` frames are sent device-to-device via `sendToDevice(deviceId)` against the resolved peer device, encrypted under the negotiated `call_key`, and bypass two of the standard frame steps (see §10.3 below).

Video uses **libvpx VP8** for compression with adaptive bitrate; audio is uncompressed PCM (see §10.4). Both audio and video frames are passed through a **JitterBuffer** on the receive side to absorb network reordering and short bursts of loss before playback.

**Camera Rotation (Mobile):** CameraX (Android) and AVFoundation (iOS) deliver I420 frames in sensor orientation (typically 90° CW on portrait phones). The `chat.cleona/camera` MethodChannel includes `rotationDegrees` alongside frame data. The Dart `cam.onFrame` callback applies `VideoEngine.rotateI420()` (0/90/180/270° CW) before VP8 encoding, so the sent frame is upright. The local preview additionally applies `VideoEngine.mirrorI420Horizontal()` for the expected selfie-mirror effect; the outgoing frame is NOT mirrored.

**Call UI Controls:** The `CallScreen` toggles for Mute and Speaker update both local UI state and the service layer (`toggleMute()` / `toggleSpeaker()`), which respectively gate the Capture Isolate's frame submission and the Main Isolate's `playFrame()` path.

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

Group calls use **per-sender media keys** — each participant encrypts its own stream under a secret key only it holds, authenticated to the others — together with an **Overlay Multicast Tree** for efficient media distribution. (A single shared key cannot provide sender authenticity in a group: every holder could forge frames as any other — see §10.3.)

#### 10.2.1 Group Call Setup

1. The initiator generates a 16-byte `call_id` and sends a `CALL_INVITE` `ApplicationFrame` (full Ed25519 + ML-DSA dual-sig, Per-Message KEM) to each invited participant carrying the participant set and `call_id`. It does **not** carry a shared media key.
2. On joining (initiator at setup, invitees on accept), each participant generates a random 256-bit **`send_key`** known only to itself and announces it to every other joined participant via a `GroupCallSenderKey` `ApplicationFrame` (`sendToUser(userId)` per recipient, full dual-sig + KEM). The recipient's verification of that frame's inner user-signature binds `send_key` to its owner.
3. Each participant encrypts **its own** audio/video frames with AES-256-GCM under **its own `send_key`** (fresh random nonce per frame; the per-sender keyspace removes any cross-sender nonce-reuse risk) and sends them device-to-device via `sendToDevice(deviceId)` along the multicast tree. A receiver decrypts an incoming frame with the `send_key` it learned for that frame's `sender_node_id`; a frame whose sender key is not yet known is dropped (it arrives once the signed announcement lands, sub-second at join). Because each `send_key` is secret to its owner, a relaying participant cannot forge frames as any other participant.

**Key rotation during group calls:**

| Event | Action |
|-------|--------|
| Participant leaves / is kicked / crashes out | **Forward secrecy:** every *remaining* participant generates a fresh `send_key` (version++) and re-announces it to the remaining set, so the departed node's cached peer keys go stale and cannot decrypt subsequent media. |
| New participant joins | **Backward secrecy:** the newcomer announces its `send_key` to all and each existing participant announces its `send_key` to the newcomer; the newcomer never held the prior keys, so pre-join frames stay unreadable. |

Rotation is edge-triggered by authorized-set changes only — O(N²) signed announcements per change, **zero** steady-state cost.

**Rejoin after crash:** The rejoining participant sends a `CALL_REJOIN` `ApplicationFrame` and re-announces its `send_key` (new version) to all active participants; each active participant re-announces its own `send_key` to the rejoiner. No global rotation — the authorized set did not change.

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

> **Onion-Routing Tabu.** Live-media frames are explicitly **Onion-Tabu** — see §2.5 Onion-Routing Hook for the full tabu list. Live audio and video frames travel direct device-to-device (or through the call-specific Overlay Multicast Tree, §10.2.2), without any onion layers. Onion encryption would multiply per-frame CPU and bandwidth cost beyond what 20 ms-deadline media can absorb, and per-frame authenticity is provided by the call key (1:1) or the sender's own `send_key` (group, §10.2.1).

`CALL_AUDIO` and `CALL_VIDEO` `ApplicationFrame`s are classified as **ephemeral media** in the frame pipeline and **skip two of the standard ApplicationFrame steps**:

1. **No ML-DSA signature on the inner frame.** Post-quantum authenticity is established at call setup: the `CALL_INVITE` and `CALL_ANSWER` `ApplicationFrame`s carry full Ed25519 + ML-DSA-65 dual signatures, and the resulting `call_key` is mixed from a hybrid X25519 + ML-KEM-768 KEM (§10.1.1). Once both sides hold the call key, every audio/video frame is authenticated by AES-256-GCM (16-byte tag, fresh random nonce) under that key — a quantum adversary cannot forge frames without first breaking the setup handshake. A per-frame ML-DSA signature would add ~3500 bytes wire and ~600 µs CPU per frame on top of authentication that is already post-quantum-secure. In **1:1** calls the `call_key` is a two-party secret, so AES-GCM under it authenticates the peer. In **group** calls a shared key cannot — authenticity instead comes from each sender's secret `send_key`, whose ownership is established by the dual-signed `GroupCallSenderKey` announcement (§10.2.1); a relay or co-participant cannot forge frames it has no `send_key` for.
2. **No zstd compression probe.** Frame payloads are already AES-256-GCM ciphertext (high entropy) — zstd cannot compress them, and running the probe just costs CPU.

**What is still strict on every frame:**

- **Inner ApplicationFrame:** AES-256-GCM under the negotiated `call_key` (1:1) or the sender's `send_key` (group) — instead of the per-message User-KEM that ordinary application traffic uses — confidentiality and content authenticity.
- **Outer NetworkPacket:** Ed25519 device signature only (no hybrid Ed25519 + ML-DSA), since outer packet-level auth is a single-hop spoofing defence and the underlying call key already covers end-to-end authenticity. See §2.4 + §4.10 for the general packet-auth model.

The optimisation only removes the redundant outer post-quantum signature on per-frame traffic; it does not weaken the cryptographic envelope around the call as a whole.

**Receiver-side PoW handling:** Live-media frames carry `pow=0`. The receiver cannot classify them by messageType before KEM decap, so acceptance is bound to the call session: on call establishment both endpoints register the peer's device ID(s) in the PoW live-media allowlist (§13.1.2 exemption #4); teardown unregisters. Frames from non-allowlisted, non-LAN, non-relay sources without valid PoW are dropped before decryption — exactly as ordinary application traffic.

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

**Directed start and Capture-Isolate pattern:** Each `cleona_audio_start_directed(engine, direction)` call opens only the requested devices: direction 1 = capture-only (Capture Isolate), direction 2 = playback-only (Main Isolate). The legacy `cleona_audio_start(engine)` remains as a direction=0 (both) alias for non-call callers. The Capture-Isolate architecture is unchanged: a dedicated Dart isolate consumes 20 ms frames from the native capture ring buffer, runs AES-256-GCM encryption with the Call Session Key (§10.1.1), and forwards ciphertext to the main isolate via `SendPort`. The Main Isolate owns the playback engine exclusively. This split eliminates double-device contention on platforms where the audio backend enforces exclusive device access (notably Android AAudio in low-latency mode).

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

  // Participants: individual contacts OR group (mutually exclusive)
  attendeeNodeIds:  List<bytes> (individual invitees, node IDs; empty for personal/group events)
  groupId:          bytes (optional, linked group/channel ID; empty when attendeeNodeIds is set)
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

##### 11.1.2.2 CalendarInvite (Contact & Group Events)

An event can target either **individual contacts** (`attendeeNodeIds` set) or an **entire group** (`groupId` set). The two modes are mutually exclusive — the UI enforces this. When saving, the invite is sent to the resolved recipient list:

- **Contact event:** invite is sent to each node in `attendeeNodeIds` via `sendEncryptedPayload()`.
- **Group event:** invite is sent to all group members (minus self) via Pairwise Fanout (§9.1).

```
CalendarInvite {
  eventId:          UUID
  title:            string
  description:      string
  location:         string
  startTime:        int64
  endTime:          int64
  allDay:           bool
  timeZone:         string
  recurrenceRule:   string (optional)
  hasCall:          bool
  groupId:          bytes (set for group events)
  attendeeNodeIds:  repeated bytes (set for contact events)
  createdBy:        bytes (inviter's node ID)
  createdByName:    string (inviter's display name)
  rsvpDeadline:     int64 (optional, Unix ms)
}
```

The same `_resolveRecipients()` helper is used for RSVP, Update and Delete — it checks `groupId` first (group members minus self), falling back to `attendeeNodeIds`. For group events the invite additionally appears as an interactive card in the group chat (see §11.1.7).

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

When `anonymous == true`, votes are protected by **Linkable Ring Signatures**: the vote payload carries no voter ID, group membership is proven by the ring, and double-voting is detected via the key image. **Scope of this guarantee (honest):** in the current transport (Phase 1), the anonymity holds at the *application and persistence layer* — tallies, snapshots, exports and the UI identify votes only by key image. It does **not** yet hold at the *transport layer*: see §11.4.7. A planned anonymous submission path (single re-origination hop) will extend the guarantee to the transport layer in a later phase.

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

#### 11.4.7 Honest Limitations: Transport Deanonymization & Quantum

**Transport deanonymization (Phase 1, current behavior).** `POLL_VOTE_ANONYMOUS` and `POLL_VOTE_REVOKE` are delivered through the standard pairwise send path (§2.6): each recipient receives a KEM-encrypted Inner ApplicationFrame that carries the voter's `senderUserId` and hybrid user signature, wrapped in an Outer NetworkPacket carrying the voter's `senderDeviceId`, hybrid device signature and — on direct routes — source IP. **Every recipient of the vote therefore learns who voted and when**, even though the vote *content* record is keyed only by the key image. The ring signature currently protects the persisted tally (DB, snapshots, exports, UI) and any party that obtains vote records without having received the frames — it does not protect against the participants themselves. In channels, anonymous votes follow the same creator-only path as non-anonymous votes (§11.3.3.2) — this limits the transport-layer observer to the poll creator rather than all subscribers. In groups, the pairwise fan-out exposes the voter to all members. Until the planned anonymous submission path (a single re-origination hop, scheduled for a later phase) extends the guarantee to the transport layer, the UI must state this scope explicitly ("anonymous in results, not on the network").

**Retroactive quantum deanonymization.** The ring construction is classical Ed25519 (§11.4.2). The `ringMembers` public keys travel in cleartext inside the (hybrid-KEM-protected) vote message and are held by all participants. A future CRQC can recover each member's secret scalar from its public key, recompute the candidate key image `I' = sk · H_p(pollId ‖ P)` for every ring member and match it against the recorded key image — identifying the voter retroactively — and can equally forge ring signatures for any poll whose ring keys it has. No production-grade post-quantum linkable ring signature library exists (liboqs ships plain signatures only; lattice LRS schemes are research code with signatures in the tens-to-hundreds of KB). **Decision:** Cleona accepts this limitation and documents it instead of shipping home-grown research cryptography. Anyone whose vote must remain secret against a decades-horizon quantum adversary should not use anonymous polls. In practice the dominant risks remain the anonymity-set size and N−1 collusion (§11.4.6), both of which are quantum-independent.

#### 11.4.8 Anonymous Submission Path (Re-Broadcaster)

To extend vote anonymity to the transport layer without activating full onion routing (rejected for V3.0, §2.5), anonymous votes use a single re-origination hop:

1. **De-attributed inner frame.** For `POLL_VOTE_ANONYMOUS` / `POLL_VOTE_REVOKE` only, the Inner ApplicationFrame is built with empty `senderUserId` and **no** user signatures — authenticity is carried entirely by the ring signature, which every participant verifies anyway. The receive pipeline (§2.4 step [13]) special-cases exactly these two MessageTypes: the user-sig verify is skipped and the frame is dispatched straight to the ring-signature handler; all other types keep the mandatory user-sig + KEX gate unchanged.
2. **Submission bundle.** The voter KEM-encrypts one inner blob per recipient (as today), packs them into a `PollAnonSubmitMsg { entries: [(recipientUserId, kemBlob, deviceIds)] }` and sends it KEM-encrypted under the **Device-KEM public key** (§3.5b) of one uniformly random routing-table peer R that is neither a poll participant nor the voter's contact. R is the only party that links the voter's device to the act of voting; it never sees poll choice or content (end-to-end KEM).
3. **Re-origination.** R validates limits (bundle ≤ 64 KB, ≤ 64 entries, standard rate limiting) and emits each entry as a **fresh** APPLICATION_FRAME NetworkPacket under **R's own** deviceId and device signature. The closed-network invariant (device sig on every packet) is preserved; recipients see R as the transport sender. R acknowledges acceptance with `POLL_ANON_SUBMIT_ACK`; on timeout the voter retries with a different R (max 3), then falls back to the legacy attributed path (§11.4.7).
4. **Residual exposure (by design):** R learns "device X submitted an anonymous vote to recipient set {…}" (the set approximates the group); collusion between R and a participant deanonymizes; a global passive observer can correlate timing (mitigated by the 0–30 s jitter, §11.4.6). This is a deliberate reduction from "all N participants see the voter" to "one random third party sees participation" — not a mixnet.

**Transition (mixed net):** old builds drop de-attributed frames (user-sig verify fails, silent drop) and cannot act as R. The legacy attributed path therefore remains the fallback. The re-broadcaster path activates as default behind the `minRequiredVersion` hard-block (§19.5.7), mirroring the D1/SR-2/H-2 legacy-handling pattern.

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
 5. Start transport (bind UDP socket, set SO_RCVBUF=2MB)
 6. Start LAN discovery (IPv4 broadcast + IPv6 multicast)
 7. Start UPnP/NAT-PMP port mapping (non-blocking)
 8. Register self in routing table
 9. Send PING to all bootstrap seed peers
10. Wait 3 seconds for PONG responses
11. Run Kademlia bootstrap: FIND_NODE for own ID to up to 10 peers
    → Learn closer peers from responses → PING newly learned peers
12. Broadcast own PeerInfo to all known peers
13. Start background timers (see §12.2.4):
    - Maintenance timer: 15 minutes (routing table cleanup, stale peer pruning)
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
2. Retrieve Store-and-Forward whole messages from contact peers (§5.5).
3. Send own queued outbound `ApplicationFrame`s from the persistent Store-and-Forward + Mailbox-Pull buffer (§5.5 / §5.6).
4. Exchange peer list deltas with contacted peers (Mesh Discovery propagation, §4.5).
5. Update DHT routing table with fresh peer information (§4.4).
6. Forward relay fragments for other users (lowest priority, only if time remains).

#### 12.2.4 Background Timers

Four periodic timers run during normal operation:

| Timer | Interval | Purpose |
|-------|----------|---------|
| Daemon heartbeat | 5 seconds | Drift detection (WARN if tick >6.5s — indicates blocked main isolate), receive-health self-probe (`checkReceiveHealth`). At tick 12 (~60s uptime): **firewall blockade heuristic** — if `externalPacketsReceived == 0` (zero non-loopback inbound packets since start), log WARN suggesting OS firewall blocks inbound UDP. Fires once per session. |
| Maintenance | 15 minutes | Routing table cleanup, stale peer pruning, mailbox housekeeping |
| Peer exchange | 120 seconds | Share peer list deltas with known peers (Mesh Discovery, §4.5) |
| DV safety-net | 1 hour | Full Distance-Vector route exchange with all neighbors (§4.4) |

**UDP receive-health self-probe.** `checkReceiveHealth()` (called by the 5s daemon heartbeat) sends a 4-byte raw probe (`0x43 0x50 0x52 0x42` = "CPRB") to 127.0.0.1 on the node's own port. The probe is intentionally too short for V3 outer-frame parsing — it serves solely to set `_lastUdpReceiveMs` in the `onUdpEvent` handler *before* any HMAC/parse step, confirming that the Dart `RawDatagramSocket` listen callback is alive. If no UDP event (including the self-probe) fires within 30 seconds, the socket is considered dead and `reconnectSockets()` triggers. The probe's parse failure is suppressed in the V3 parser (loopback + ≤4 bytes → no "HMAC fail" log line) to avoid misleading log noise. On iOS, an additional `recvPeek()` path detects EBADF socket death (see §24.2).

Additionally, a **welcome route update** fires 500 ms after a new neighbor is detected, sending full DV routes to the newcomer. A **DV catch-up** is **epoch-gated**: each `_maybeSendCatchUpRouteUpdate` compares a monotonic `routeEpoch` counter (incremented only on genuine topology changes — new neighbor, neighbor removal, route-down, stale-route pruning, or `processRouteUpdateDetailed` with at least one changed destination) against the last epoch sent to that specific neighbor. If the epoch has not advanced, the catch-up is suppressed. This replaces the previous 60 s time-based throttle, which still caused O(N) full route-table sends per minute in a stable mesh (N = neighbor count).

Beyond these three core timers, several long-period housekeeping checks fire less frequently and are listed here for completeness:

| Check | Interval | Purpose |
|-------|----------|---------|
| DHT update-manifest poll | 6 hours | Refresh the cached signed update manifest from DHT (§19.5.5) |
| Authorization manifest refresh | 20 hours | Re-verify identity-resolution authorization records (§4.3) |
| Liveness short-cycle | 15 minutes | Republish per-device liveness record while reachable (§4.3) |
| Liveness long-cycle | 1 hour | Liveness republication backstop when no triggering event has fired (§4.3) |

The 6-hour update-manifest poll keeps the cached manifest fresh; users with stale caches see any required UpdateRequiredScreen on the next start after the cache refreshes (see §19.5.7 for the full UX flow).

### 12.3 Network Change Detection & Recovery

Network changes (WiFi toggle, mobile data switch, roaming, IP change) are detected via three mechanisms:

1. **Platform events:** `connectivity_plus` on Flutter (GUI), periodic `NetworkInterface` polling on headless daemons.
2. **Mass route-down inference:** When ≥3 distinct peer routes fail within 30 seconds, a network change is inferred even without OS notification. This catches silent IP changes that `connectivity_plus` misses. **V3.1.111:** the mass-route-down path no longer bypasses the IP-change check (`force` removed) — if IPs are unchanged, no stale-marking occurs. On bootstrap nodes with many offline peers, the previous `force=true` caused a false-positive feedback loop (3 ACK timeouts to offline peers in 30s → `markAllRoutesStale` → revalidation → epoch bump → full-table catch-up → repeat every ~20s).
3. **Manual user trigger:** the user can invoke the recovery sequence on demand (see §12.3.1). This is the explicit escape hatch when a user suspects a connection loss that the automatic detectors have not yet caught.

**Recovery sequence** (executed when a network change is detected):

```
 1. Verify IPs actually changed (skip false alarms from Android connectivity_plus
    and mass-route-down false positives on bootstrap nodes with offline peers)
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

#### 12.3.1 Recovery Triggers (automatic, manual, out-of-band)

The recovery sequence above is reached through a three-tier escalation, designed so that none of the tiers introduces background traffic that scales with network size:

1. **Automatic (isolated-node re-discovery).** While `peerCount == 0`, the backoff retry from §4.5 re-enters discovery on its own. Self-terminating, O(1) traffic, never armed in a populated mesh.
2. **Manual reconnect.** A user-facing "Reconnect" action runs the full §12.3 recovery sequence on demand. It is **debounced** (minimum 10 s between invocations, reusing the Stage-4/5 cooldowns of §5.10) so repeated taps cannot produce a burst storm. The action reports its result to the UI ("N peers found" / "no peer reachable"), which routes a failed result toward tier 3.
3. **Out-of-band peer-list import.** When tiers 1–2 find nothing (e.g. bootstrap down and no LAN peer), the user imports a peer-list rescue bundle received from a known contact via an external channel (§8.1.2). Zero background traffic — the data is human-carried.

Tiers 2 and 3 are surfaced in one shared connection sheet (§18).

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

**Basic decision B2 — two-process model on Android (REJECTED, S120, 2026-07-03):** The current in-process architecture (§16.2) runs all networking inside the single Flutter-Activity-plus-FGS process. B2 asked whether the headless engine (`CleonaService` networking core, today the `cleona-headless` binary on Linux, §15.2) should instead run in a *separate process* owned by the Foreground Service, decoupled from the Activity lifecycle. S119 deferred this, gated on memory profiling. **S120 performed that profiling (Pixel 8 Pro, v3.1.116-beta, 7h40m-old process, background, FGS active, no kill-loop) and the two-process model is rejected on the evidence:**

- Steady-state background PSS was 676 MB — the S119 hypothesis that the earlier ~816 MB reading was kill-loop-inflated is refuted; high usage *is* steady state on the debug beta build.
- The UI contributes only ~20-30 MB (foreground PSS 694 MB vs 676 MB background; Graphics 60→80 MB). >95% of memory is engine-side and would live in the FGS process under any split — a second process saves nothing and *adds* a second engine, an Android-only IPC layer, and lifecycle complexity.
- The dominant consumers are process-model-independent: (1) a never-used resident whisper.cpp context in the main isolate — the full ggml-base model (144 MB, fully resident) plus ~560 MB VSS of untouched KV/compute buffers, loaded eagerly at service start although every actual transcription loads and frees its own context in a worker isolate (fixed in V3.1.117: main isolate only probes library + model-file presence); (2) debug-build overhead in the beta flavor (~80 MB `kernel_blob.bin` + JIT code + a larger JIT Dart heap) absent from release builds.
- The Problem-10 restarts were watchdog self-kills and FGS-timeout crashes (§16.2), not memory (LMK) kills.

Expected steady-state PSS after the whisper fix on a release build: ~250-350 MB. **What survives of B2:** only the *single-process* service-owned-engine variant (the FGS boots a headless Dart engine after a START_STICKY resurrection so delivery resumes without user interaction) remains a candidate — as a delivery fix for the resurrection gap, not a memory fix. It is considered only if post-Block-E field testing shows genuine process kills with dead resurrections are frequent enough to cost real delivery.

**BGTaskScheduler distinction (iOS):** The iOS background delivery described in §12.5 (BGAppRefreshTask + BGProcessingTask, dual-task strategy) is **not** a push wakeup and does not fall under this rejection. BGTaskScheduler is an OS-controlled pull mechanism: the operating system wakes the app periodically, the app actively connects to the P2P network and retrieves pending messages. No third-party server, no APNs, no Firebase. The limitations (OS-controlled timing, bounded execution time) are accepted — they are the price for background delivery without central infrastructure.

### 12.5 Platform-Specific Background Behavior

**Android:** The in-process architecture runs all networking within the Flutter app. A foreground service (`CleonaForegroundService`, type `dataSync`) keeps the process alive and the UDP socket open for pushed messages. When the OS suspends the app (Doze mode), WorkManager schedules periodic wake-ups (minimum 15-minute OS interval). The foreground service with persistent notification provides near-instant delivery. Without it, messages arrive during the next WorkManager wake-up. **Lifecycle save:** `CleonaAppState` implements `WidgetsBindingObserver` and calls both `saveState()` (conversations, contacts, groups, channels) **and `saveNetworkState()`** (routing table, DV routing table, peer addresses) when `AppLifecycleState.paused` is received. `saveState()` prevents data loss (e.g., media message types reverting to TEXT); `saveNetworkState()` prevents cold-start peer loss — without it, Android process kills lose the learned topology and the node restarts with routes=0, peers=0.

**iOS:** No daemon process — the app runs in-process like Android. In the foreground, the node is fully active (UDP socket open, real-time delivery). In the background, Cleona uses Apple's `BGTaskScheduler` framework for periodic message retrieval via two independent task types (dual-task strategy):

**Task 1 — BGAppRefreshTask ("Background App Refresh"):**
- Identifier: `chat.cleona.cleona.refresh`
- Scheduling: `BGAppRefreshTaskRequest` with `earliestBeginDate` = 1 minute. The OS decides the actual execution time (depends on user behavior, battery level, network availability). The short hint signals urgency; the OS honors it more frequently for apps the user opens regularly.
- **Runtime:** ~30 seconds (OS limit)
- **Execution per wakeup:**
  1. Load persisted routing table (peers, addresses, scores — saved on `AppLifecycleState.paused`)
  2. Open UDP socket on the persisted port
  3. Contact known peers: PING top-3 peers (sorted by score)
  4. Retrieve Store-and-Forward: ask contact peers for pending messages
  5. Fetch Reed-Solomon fragments from DHT (for messages that arrived while offline)
  6. Decrypt received messages + display as local iOS notifications (`UNUserNotificationCenter`)
  7. Persist routing table + messages
  8. Close socket, schedule both task types for next wakeup
  9. Call `task.setTaskCompleted(success: true)`

**Task 2 — BGProcessingTask ("Background Processing"):**
- Identifier: `chat.cleona.cleona.processing`
- Scheduling: `BGProcessingTaskRequest` with `requiresNetworkConnectivity = true`, `requiresExternalPower = false`, `earliestBeginDate = nil` (immediate execution permitted).
- **Runtime:** several minutes (OS limit, typically 1–5 min)
- **Execution:** Identical flow to Task 1 (steps 1–9), but with an extended time budget. The longer runtime additionally allows:
  - Contacting more than 3 peers (up to 10, time budget permitting)
  - More thorough fragment retrieval when multiple Reed-Solomon sets are pending
- **Scheduling behavior:** The OS prefers processing tasks during idle/charging phases but also schedules them without external power when `requiresExternalPower = false`.

**Dual-task rationale:** BGAppRefreshTask and BGProcessingTask are two independent scheduling queues in the OS. Registering both gives the OS two separate triggers — a refresh wakeup and a processing wakeup can fire at different times. In practice, this yields a higher effective wakeup frequency than a single task type.

- **Scheduling chain:** Every completed task (of either type) re-schedules both task types (`scheduleAppRefresh()` + `scheduleProcessing()`). Both are also scheduled on first app launch and on every foreground→background transition.
- **Limitations (accepted):**
  - No real-time messaging in the background (expected delay with dual-task: 5–30 min for regularly-used apps, up to 60 min for rarely-used apps — improved over single-task but not guaranteed)
  - OS may suppress tasks entirely if the app is rarely opened
  - No persistent UDP socket (unlike Android Foreground Service)

**Lifecycle integration:**
- `AppLifecycleState.paused` (app enters background): `saveState()` + `saveNetworkState()` + shut down node (close UDP socket, stop timers) + schedule both BGTask types
- `AppLifecycleState.resumed` (app enters foreground): full node start (UDP socket, DHT, Discovery) — full mode as on first launch, but with a warm routing table
- Task expiration handler: `task.expirationHandler` cleanly shuts down the mini-node when the OS cuts time

**Notification bridge:** Messages received in the background are displayed as local notifications via `UNUserNotificationCenter.add()` (sender name, message preview — decrypted on-device, no server sees the content). The app badge is set to the unread message count (`UNMutableNotificationContent.badge`).

**Info.plist entries:**
- `UIBackgroundModes`: `fetch`, `processing`
- `BGTaskSchedulerPermittedIdentifiers`: `chat.cleona.cleona.refresh`, `chat.cleona.cleona.processing`

**Implementation:** Native Swift code (`ios/Runner/BackgroundFetchHandler.swift`) communicates with the Dart layer via `MethodChannel("cleona/background_fetch")`. The Dart code provides a minimal node start path (`CleonaNode.startQuick()` + `CleonaService.fetchPendingMessages()`) that skips the heavy parts (discovery burst, subnet scan, DHT bootstrap) and only contacts known peers. The processing task uses the same Dart entry point but passes a `taskType: "processing"` argument so the Dart layer can extend the peer-contact budget from 3 to 10 when time allows.

**No APNs, no push, no third party.** This is a pure pull mechanism based exclusively on OS APIs and the existing P2P network. See §12.4 for the distinction from the rejected push variants.

**Linux Desktop:** The daemon process (`cleona-daemon`) runs continuously as a separate process from the GUI. The UDP socket is permanently open, providing instant push delivery. The daemon survives GUI restarts. Becomes fully offline when the system enters standby. System tray icon (GTK3 + libappindicator3) provides visual status.

**Windows Desktop:** Identical architecture to Linux Desktop. The daemon runs as a user-space process (not a Windows Service) with a system tray icon (Win32 Shell_NotifyIcon). Each Windows user gets their own daemon instance with separate data in `%APPDATA%\.cleona`. The daemon starts at user login (Registry autostart) and provides the same always-on UDP connectivity as Linux. IPC via TCP loopback (127.0.0.1) with auth-token file (`cleona.port`). **Firewall auto-rule (V3.1.85):** On first daemon start the daemon attempts to add a Windows Firewall inbound-UDP rule for its own executable via `netsh advfirewall firewall add rule`. A marker file (`firewall_rule_added`) prevents re-running. If the process lacks admin privileges, the attempt fails gracefully (logged, no crash) — the user must then add the rule manually or run the daemon once elevated. Without this rule, Windows Firewall silently blocks all inbound UDP and the node cannot receive any traffic from the network.

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

Every chat-content message entering the network must carry a Proof of Work (PoW) solution in its outer `NetworkPacket`. PoW is a wire-level property — it sits in the outer frame so a node can verify and drop spam *before* spending CPU on KEM decryption of the inner `ApplicationFrame`. The algorithm is SHA-256 hashcash with pre-hashing: the sender first reduces the payload to a 32-byte digest via SHA-256, then finds an 8-byte nonce such that SHA-256(digest || nonce) has at least N leading zero bits.

```
PoW Parameters:
  Algorithm:           SHA-256(SHA-256(data) || nonce_8byte_LE)
  Default difficulty:  20 leading zero bits (~1M hashes, ~20ms regardless of payload size)
  Minimum accepted:    16 leading zero bits (transition period)
  Verification:        Pre-hash first, legacy full-data fallback; verify leading bits + hash match
```

**Pre-Hash Rationale (V3.1.92):** The previous formula `SHA-256(data || nonce)` iterated over the full KEM-encrypted payload on every hash attempt — O(payload_size × 2^d). For a 131 KB inline image (137 KB after KEM encrypt), this produced ~136 GB of SHA-256 throughput (~66 s on ARM64), which caused Android to kill the PoW isolate (silent message loss). Pre-hashing reduces the per-iteration input to a fixed 40 bytes (32-byte digest + 8-byte nonce), making PoW time O(2^d) independent of payload size. Measured improvement: 131 KB payload from 66 000 ms to 17 ms (3 800×). Verify accepts both formats for backward compatibility with S&F-cached messages.

**PoW Exemptions:** Four categories of packets are exempt:

1. **LAN peers** (private IP: 10.x, 172.16-31.x, 192.168.x): Packets between peers on the same local network skip PoW. Authenticity is still established by the outer device-signature and inner Per-Message KEM + user-signature (see §2.4 Layered Encryption Pipeline). Detection uses `_isPrivateIp()` on both sides.

2. **Infrastructure messages**: GROUP_INVITE, GROUP_LEAVE, CHANNEL_INVITE, CHANNEL_LEAVE, CHAT_CONFIG_UPDATE, KEY_ROTATION, PROFILE_UPDATE, RESTORE_BROADCAST, TYPING_INDICATOR, READ_RECEIPT, DELIVERY_RECEIPT. Authenticated by signature and encryption.

3. **Relay-bound packets**: When the routing layer reports `directBlocked` or no reachable active targets exist, PoW is skipped. Relay-delivered packets (from=0.0.0.0) are exempt from PoW verification on the receiver — the relay's own outer device-signature carries the wire-level authenticity.

4. **Live-media frames (call-session-scoped):** CALL_AUDIO (76), CALL_VIDEO (77), CALL_GROUP_AUDIO (78), CALL_GROUP_VIDEO (79) carry `pow=0` (§10.3, Appendix B.2) — at 50 frames/s per direction, a ~20 ms PoW grind per 20 ms frame is physically impossible. Since PoW verification is a pre-decrypt gate and the inner messageType is not visible before KEM decap, the receiver scopes the exemption by **sender device ID**: for the lifetime of an active call session, the peer's device ID (1:1: the device that sent CALL_ANSWER / CALL_INVITE; group: all participant devices) is registered in a **live-media allowlist**; ApplicationFrames whose outer `senderDeviceId` is allowlisted skip PoW verification. The entry is removed at call teardown (hangup, reject, timeout — teardown always runs locally, so entries cannot leak). DoS posture: the exemption is reachable only *after* a fully dual-signed (Ed25519 + ML-DSA) call handshake, is bounded to the ≤N devices of one active call, and removes only the PoW layer — outer device-signature verification, rate limiting (Layer 2), and reputation (Layer 3) remain fully active. An allowlisted peer could send non-media traffic PoW-free for the call's duration; this is accepted (the peer is an authenticated contact mid-call, and Layer-2 budgets bind).

Only **chat content messages** (TEXT, IMAGE, FILE, VOICE), **call signaling** (CALL_INVITE, CALL_ANSWER, CALL_REJECT, CALL_HANGUP, CALL_REJOIN) and **deferred-key-exchange messages** (DEVICE_KEM_REQUEST, DEVICE_KEM_OFFER) sent **directly** to **non-LAN peers** require PoW. **Live-media frames (76–79) never carry PoW** — neither on LAN nor WAN paths.

**Async Crypto Pipeline:** The full inner send pipeline (User-Sign → zstd → KEM-Encrypt → PoW) runs in a single background isolate via `V3FrameCodec.buildAndEncryptInnerWithPowAsync()`. The isolate loads libsodium and liboqs independently. Two performance optimizations reduce per-message overhead: (1) **Native PoW loop (`libcleona_pow`):** the SHA-256 hashcash iteration runs in C (`cleona_pow_find_nonce`), eliminating ~1M Dart↔C FFI transitions per message. On platforms where `libcleona_pow` is not deployed, the Dart-side iteration loop serves as transparent fallback. (2) **OQS context caching:** the `OQS_SIG` and `OQS_KEM` context handles for ML-DSA-65 and ML-KEM-768 are allocated once per isolate and reused across calls, eliminating per-operation `OQS_*_new`/`OQS_*_free` overhead. Pre-hashing (§13.1.2) ensures PoW iteration time is constant regardless of payload size. The UI shows the message immediately with "sending" status (hourglass).

**Admission PoW (identity-bound, D3 — Phase 1 observe-only):** distinct from the per-message PoW above, the admission proof prices **ID minting** (insider-Sybil cost anchor, §13.1.8):

```
Admission PoW:
  Algorithm:    SHA-256("cleona-id-pow-v1" || device_ed25519_pk || nonce_8byte_LE)
  Difficulty:   22 leading zero bits (production), 8 (test preset)
  Computed:     once at device-keypair creation (isolate); existing devices
                compute lazily on first start after upgrade
  Persisted:    device_keys.json, alongside the device keypair
```

- **Bound to the pubkey, not the Device-ID** — it survives secret rotation (Device-IDs change with the secret, the proof does not). The receiver additionally checks `SHA-256(network_secret || pk) == senderDeviceId`, binding the proof to the wire identity.
- **Transport — no additional packets:** the proof travels alongside the device pubkey it certifies, as `PeerInfoProto.device_id_pow_nonce` (field 21) in self-broadcast `PEER_LIST_PUSH` and `PEER_KEY_RESPONSE`. The 8-byte nonce is part of the **slim** PEER_LIST_PUSH field set (§4.5.x slim mode). Legacy builds ignore the field; legacy gossipers drop it on re-serialization — the peer then simply stays non-admitted until direct contact (harmless in Phase 1).
- **Verification:** on the key-learning path (`setSigningKeys`): two SHA-256 invocations per newly learned peer; result cached as `idPowVerified` in the PeerInfo and persisted with the routing table.
- **Phase 2 semantics (V3.1.90+, hard break):** admission PoW is **required** for privileged network roles. Peers without verified admission proof are excluded from: (1) relay candidacy — not selected as relay hop in DV neighbor spray, (2) DV route acceptance — ROUTE_UPDATEs from non-admitted neighbors are silently dropped, (3) DHT fragment storage — FRAGMENT_STORE from non-admitted senders is rejected. **Exception (§8.1.1 bootstrap):** peers with `isProtectedSeed=true` (ContactSeed-derived, §8.1.1, max 5 per ContactSeed) are exempt from relay-candidacy, ROUTE_UPDATE gating, and FRAGMENT_STORE gating. The §5.11 new-neighbor Self-Broadcast normally resolves admission within 1 RTT; the protected-seed exemption is the safety net for UDP loss, high-latency mobile paths, or timing races where the Self-Broadcast arrives after the CR send window. Protected seeds are bounded (≤5), ephemeral (pruned after contact success or aging timeout), and integrity-anchored via the ContactSeed (SHA-256 check, §8.1.1) — they are not a Sybil vector. Basic packet receive, self-broadcast, and message delivery are **never** gated — a non-admitted peer can still send and receive chat messages on direct paths; admission gates only trust-bearing infrastructure roles. The `minRequiredVersion` transition gate was removed — all pre-V3.1.90 builds are de-facto deprecated (beta distribution only, no external user base). The admission nonce is computed synchronously (awaited) during node startup to ensure the first self-broadcast carries the proof.

#### 13.1.3 Layer 2: Rate Limiting per Device

**Keying sign-off (D2):** rate limiting keys **per-Device**. The wire layer sees only the outer `NetworkPacket` source Device-ID — the UserID is intentionally not disclosed at this layer. A multi-device user legitimately occupies one per-source budget per device (one user with 5 devices gets 5× the budget); this is a deliberate design choice. Against insider ID minting, per-source budgets are a fairness mechanism, not a hard bound — see §13.1.8.

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

**Collective quota for non-introduced sources (D5):** in addition to the per-source limits, all senders that have not *introduced* themselves share one collective slice of the global budget. A sender counts as **introduced** once its admission PoW verified (D3, §13.1.2) **or** its Device-Sig-PK was learned **firstParty** from its own self-broadcast — every build does this as part of normal discovery, so legacy builds leave the pool within seconds and contact devices are firstParty by construction. All other (anonymous/unknown) senders collectively share **50% of the global packet and byte budgets** (1,000 packets / 10 MB per 10 s window); per-source limits apply unchanged on top. N minted IDs that never introduce themselves compete with each other inside this slice instead of multiplying per-source budgets. The pool is deliberately generous — it binds only under attack, never during cold-start (the first packet from a new peer is typically the self-broadcast that lifts it out of the pool). Pool drops generate no `recordBad` (rule above unchanged). **Phase-2 enforcement (V3.1.90+):** "introduced" now requires `idPowVerified == true` — the `pkSource == firstParty` exemption is removed. Every source must carry a verified admission proof to escape the collective pool. This makes pool exemption CPU-bound per ID (22-bit PoW ≈ 4M hashes per identity). The pool is deliberately generous (50%) so that cold-start traffic from honest peers that have not yet exchanged self-broadcasts is not impacted — the first self-broadcast carries the nonce, verification is immediate (two SHA-256), and the peer leaves the pool within the same packet batch. Observability: `poolDropsRate` / `poolDropsRelay` counters in network stats.

#### 13.1.4 Layer 3: Reputation System

Nodes build reputation over time based on observed behavior. Reputation is strictly local — each node independently evaluates its peers. There is no global reputation score.

**Keying sign-off (D2):** reputation keys **per-Device** and stays that way. Per-User keying is not available at the wire layer (the outer NetworkPacket does not disclose the UserID in the v3.0 base wire format, by design — §16.6) and would buy nothing against the relevant adversary: an insider can mint User-IDs exactly as cheaply as Device-IDs (§13.1.8), so a per-User clean slate is equally free. Honest multi-device users build per-device reputation organically through normal traffic (`recordGood` on accepted packets, §13.1.3).

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

**`recordBad` sources (exhaustive):** Bad actions are recorded only for semantically invalid behavior whose origin Device-ID is **cryptographically proven in the same packet** — i.e. the outer device signature verified and a *subsequent* check failed (invalid PoW, malformed inner frame, unauthorized operation such as a non-owner DHT mutation). Rate-limit excess does NOT generate `recordBad` (see §13.1.3).

**Attribution precondition (anti-framing) — global invariant.** This rule governs *every* reputation attribution in the system, wire-level and any future handler-level penalty alike: a penalty may be attributed to a `senderDeviceId` (or UserID) only after that identity's signature has verified **in the very packet/record that triggered the penalty**. A *failed* outer-device-signature verification must therefore NOT generate `recordBad` against the claimed `senderDeviceId`. The closed-network HMAC proves only network membership (a shared secret held by every insider), not sender authenticity; at the moment a device-sig fails, `senderDeviceId` is precisely the unproven field. Penalizing it would let any insider frame an arbitrary victim — forge a packet carrying the victim's `senderDeviceId`, a valid HMAC and a deliberately broken device-sig, then repeat to drive the victim past the ban threshold on the receiving node (Ban-DoS-by-framing). Sig-invalid packets are therefore dropped **silently, without reputation effect**. The same gate applies to checks that run *after* the device-sig step but are themselves independent of `senderDeviceId` (e.g. PoW, which only covers the payload): `pow_invalid` is recorded only when the outer device-sig verified (`outerStatus == verified`); under a bootstrap/stale-PK lenient pass the id is unproven and no penalty is attributed. This ensures both that high-throughput legitimate nodes (Bootstrap, relay hubs) cannot be banned by serving the network, and that no node can be banned by an attacker spoofing its Device-ID.

#### 13.1.5 Layer 4: Fragment Budgets

Each node allocates a limited relay storage budget. **Keying honesty (D5 review):** in v3.0 the per-source cap is keyed per **mailbox** (recipient mailbox-ID, 20% of the total budget) plus the total budget bound — a *source-device*-keyed ingest limit does not exist; the original "per source Device-ID" claim was doc-vs-code drift. Excess stores are silently dropped (no ACK sent; the sender infers rejection by ACK timeout and retries on another replicator), preventing a single mailbox from monopolizing relay storage. Fragments are deliberately NOT part of the D5 collective-quota pool — source-pooled ingest would require persistent sender attribution in the fragment store format (tracked in the security review).

#### 13.1.6 Layer 5: Network-Level Banning

Nodes can temporarily or permanently ban other nodes based on accumulated misbehavior. Bans are strictly local decisions — no central ban list exists. When many independent nodes ban the same attacker, the attacker becomes effectively isolated from the network through emergent consensus.

**Banned node behavior:** All packets from a banned Device-ID are dropped at the transport layer before any processing. The ban is keyed by Device-ID (not IP), so IP rotation does not bypass bans. Generating a new Device-ID, however, costs only a fresh keypair plus the (extractable, §4.10) network secret. Fleet re-authorization (§7 Multi-Device) gates only the **user layer** — acting as a device of a user (contacts, Auth-Manifest membership). **Network participation** (relay, DHT replication, DV routing) requires admission PoW (§13.1.2 Phase 2, V3.1.90+). A banned insider can re-enter under a fresh ID with neutral reputation, but must pay the CPU cost of a 22-bit PoW per minted identity. This does not prevent Sybil attacks but raises the per-identity cost from negligible to measurable. See the insider addendum (§13.1.8).

#### 13.1.7 Attack Scenarios & Mitigations

| Attack | Layer(s) | Mitigation |
|--------|----------|------------|
| Spam flood (bulk messages) | 1+2 | PoW makes each packet expensive; rate limiter drops excess |
| Sybil (outsider, no secret) | HMAC | without the network secret no valid IDs exist — the closed-network filter holds |
| Sybil (insider, extracted secret) | §13.1.8 | ID minting is CPU-bound (22-bit admission PoW per identity, Phase 2); minted IDs without PoW are excluded from relay/DV/DHT roles and share collective rate-limit quota (D5). Global caps, KEX gate (§8.2), moderation costs (§9.4), D1 record anchor (§4.3), and D4 replicator diversity remain effective |
| Fragment storage exhaustion | 4 | Per-source budget prevents monopolization |
| Relay abuse (relay others' traffic) | 2+3 | Rate limiter per source; relay traffic counts against relay node's budget |
| DHT poisoning (fake entries) | 3+4 | DHT/infrastructure ops are PoW-exempt (§13.1.2) — addressed instead by per-source storage quota + record-ownership proof on DHT-STORE; low-reputation entries deprioritized. (Storage-poisoning hardening tracked in the security review.) |
| Startup burst (legitimate new peer) | 2+3 | Rate limiter generates `recordGood` for accepted packets; score-gate prevents banning peers with score >= 0.5 |
| Ban-DoS by framing (forge victim's Device-ID) | 5 | `recordBad` requires a verified outer device-sig in the same packet; sig-invalid and unproven-sender frames drop silently without attribution (§13.1.4 attribution precondition) |

#### 13.1.8 Threat-Model Addendum — Insider Sybil

The DoS layers keyed on Device-IDs (Layer 2 rate limiting, Layer 3 reputation, Layer 5 banning) are **outsider-grade** defenses. They are effective against actors without the network secret and against careless insiders. A determined insider who has extracted the secret from an official build (the obfuscation is explicitly not crypto-secure, §4.10) defeats per-device keying by **ID minting**: `deviceId = SHA-256(network_secret || ed25519_device_pubkey)` means every fresh keypair yields a valid Device-ID, offline and at negligible cost.

**What the insider gains:**

- **Per-source budget multiplication.** N minted IDs hold N× the per-source rate/relay/fragment budgets. The **global** caps per node (Layer 2 global limits, relay total budget) still bound the absolute intake — the attack degrades to fairness starvation within the global budget, not unbounded exhaustion.
- **Reputation/ban evasion.** Each fresh ID starts at neutral 0.5; bans are local and per-ID. Banning a disposable identity has no lasting effect.
- **DHT position grinding.** Because Device-IDs are hashes, the insider can grind pubkeys until his IDs are XOR-close to any target DHT key and occupy a victim's K-closest replicator set. Since the trust anchor (§4.3 D1) made identity records self-certifying, this is reduced from **identity forgery** to **censorship** (withholding records).

**What holds against the insider:** the global per-node caps; the KEX gate (§8.2 — Sybils cannot reach users at the application layer); the moderation costs that do not scale with IDs (identity age, bidirectional partners, social-graph reachability, §9.4); and the §4.3 record anchor (no forgery). Replay (§2.4 dedup cache) and Ban-DoS-by-framing (§13.1.4) are closed independently of ID count.

**Hardening roadmap (decided, security review cycle D):**

- **D3 — Admission PoW per device keypair.** A static, reusable proof — nonce such that `SHA-256("cleona-id-pow-v1" || ed25519_device_pk || nonce)` has ≥ N leading zero bits — computed once at device creation and carried **alongside the device pubkey it certifies** (`PeerInfoProto.device_id_pow_nonce`, PEER_LIST_PUSH / PEER_KEY_RESPONSE — no additional packets), verified and cached by receivers (two hashes). Bound to the **pubkey**, not the Device-ID, so it survives secret rotation. Legacy builds ignore the unknown field. This raises ID minting from free to CPU-bound; it is a cost factor, not a prevention. Spec: §13.1.2.
- **D4 — Replicator/lookup diversity + publisher self-verify.** K-closest selection prefers IP-subnet diversity (binds eclipse to the genuinely scarce resource — addresses); the publisher verifies its own records with one self-lookup per publish cycle. Spec: §4.3 (*Replicator & lookup diversity* / *Publisher self-verify*).
- **D5 — Collective quotas.** Non-admitted/unknown sources additionally share a collective fraction of the global budgets, so N minted IDs compete with each other instead of multiplying. Spec: §13.1.3 (*Collective quota for non-introduced sources*) + §5.3 (relay budget); fragments deliberately excluded (§13.1.5).
- **Phase-2 enforcement (V3.1.90+, hard break):** role gating is **unconditionally active** — admission PoW required for relay candidacy, DV route acceptance, and fragment storage. **Protected-seed exception:** `isProtectedSeed` peers (ContactSeed-derived, §8.1.1) are exempt from relay, ROUTE_UPDATE, and FRAGMENT_STORE gating — see §13.1.2 Phase 2 for rationale. The `minRequiredVersion` transition gate was removed (no external user base to protect). Basic packet receive is **never** dropped for missing admission — message delivery on direct paths remains unaffected. Default-gateway election (§4.4) additionally prefers admitted neighbors over non-admitted ones as the top-priority sort criterion.

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

3. **Dual-secret window** (typically 90 days): the daemon accepts HMAC under either the old or the new secret. This gives users time to update their builds.

4. **Outbound backward-compatibility**: during the dual-secret window, outgoing packets use the **previous** (old) secret — not the current one. This ensures that un-updated peers (who only know the old secret) can still verify incoming packets. Updated peers accept both secrets, so the old-secret outbound is transparent to them. After the window closes, outbound switches to the current secret. Implementation: `NetworkSecret.outboundSecret` returns `previousSecret ?? secret`.

5. After the window ends, old secrets are removed from the acceptance path. Builds with the old secret can no longer enter the mesh.

6. **EPOCH_EXPIRED update hint**: when the window is closed, a one-generation-old secret (`expiredHintSecretVersion`) is retained solely for **detecting** expired peers. When the daemon receives a packet whose HMAC fails against both current and previous secrets but matches the expired-hint secret, it responds with a compact `EPOCH_EXPIRED` packet (magic `CEEP`, 16 bytes on wire) wrapped with the expired peer's old secret — so the expired peer can verify the HMAC and display an update notification. Rate-limited to 1 hint per source-IP per hour (amplification prevention). The receive-side parser (`NetworkSecret.parseEpochExpiredPayload`) is shipped in the **current** build so that future secret rotations can notify today's builds.

**Hard-block update mechanism** (§19.5.7) complements secret rotation: the `UpdateManifest` can set `minRequiredVersion`, and old versions are placed into `ReducedMode` (no send/receive of user messages).

**Implementation**:
- `network_secret` derivation in `lib/core/crypto/network_secret.dart`
- Embedded `epoch` tag in `assets/cleona_maintainer_public.pem` companion metadata
- Three secret tiers: `secret` (current), `previousSecret` (transition window), `expiredHintSecret` (detection-only)
- Outbound: `outboundSecret` = previous during transition, current after
- HMAC verification: tries current → previous → (if both fail) expired-hint for CEEP response
- EPOCH_EXPIRED: `Transport._maybeSendEpochExpiredHint` / `_maybeSendEpochExpiredHintV3` with per-IP rate-limit

**User observability**: expired builds that encounter a newer peer receive an `EPOCH_EXPIRED` hint via the `Transport.onEpochExpired` callback. Additionally, the update-manifest hard-block (§19.5.7) shows an explicit prompt to update when a peer is reachable to deliver the manifest.

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

**Service-layer test suite**: explicit smoke tests for each failure mode. This makes resolver-miss, routing-cascade exhaustion, multi-device partial delivery, defaultGateway fallback, and offline fallback all individually verifiable.

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

Enforcement is dual-sided with asymmetric defaults for mixed-version safety:
- **Sender-side (UI):** The edit button is removed after 15 minutes (`_defaultEditWindowMs`). This is purely cosmetic — it controls what the sender *sees*, not what the receiver accepts.
- **Receiver-side (enforcement):** Recipients reject edit messages that arrive more than 60 minutes after the original message timestamp (`_receiverEditToleranceMs`). This generous tolerance ensures edits from older app versions (which used 60 min sender-side) are still accepted during rollout.

The asymmetry is intentional: tightening the sender-side window improves UX (edits feel more "in the moment") while the wider receiver tolerance prevents silent edit rejection on mixed-version networks. The per-chat `edit_window_ms` override (§14.7) replaces both values when set.

**Deletion is unbounded (V3.1.117 doc correction):** an author may delete their own message at any time — there is no delete window. Sender UI (`_canDelete`) and receiver (`_handleDeleteV3`) check authorship only, not age; neither references `edit_window_ms` or any tolerance. Only **editing** is window-bound. This corrects an earlier doc statement that coupled `MESSAGE_DELETED` to the per-chat editing window (§8.1); the implementation never enforced a delete window.

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
| `edit_window_ms` | int? | null → 60 min default | Time window for message editing (dual-enforced: sender + receiver; changing the default requires coordinated rollout across all nodes to avoid silent edit rejection on mixed-version networks) |
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

No plain FTP (insecure). No NFS (impractical on mobile). **Credential protection (FTPS):** FTPS credentials are never passed on the command line. The curl-based FTPS transport writes a temporary `--netrc-file` (mode 0600) for authentication and deletes it immediately after the transfer completes.

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

**Building whisper.cpp from source** (pinned to v1.7.1 — all platform build scripts use the same tag to guarantee ABI-compatible struct layouts across Linux, Android, iOS, macOS):
```bash
git clone --depth 1 --branch v1.7.1 https://github.com/ggerganov/whisper.cpp.git
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
- Firewall: on first start, `netsh advfirewall` adds inbound-UDP rule for the daemon exe (marker file, graceful on non-admin)

**Android**:
- In-process: no separate daemon, Foreground Service with Activity lifecycle
- Multi-Identity dispatch mirrors the desktop daemon: `onApplicationFramePayload` implements the §2.4 step [9] KEM-Try-Loop (recency-ordered), `onInfrastructureFramePayload` implements service-routed InfraFrame dispatch (CR, Restore, Fragment-Store/Retrieve, etc.) — both wired in the GUI entry point (`main.dart`) rather than a separate daemon process
- Foreground Service (canonical for background delivery, see §12.4 ADR Push Wake-Up Rejected): persistent notification, runs even when the Activity is closed
- IPC: not required (in-process)
- Camera: CameraX (delivers I420 + rotationDegrees; Dart-side rotation before VP8 encode)
- Notifications: Android NotificationManager
- Incoming Call Notification: channel `cleona_calls` (IMPORTANCE_HIGH, CATEGORY_CALL, `fullScreenIntent=true`) — launches Activity and routes to CallScreen even when backgrounded or screen-locked. Auto-cancels on accept/reject/hangup/60 s timeout. Sound via NotificationSoundService Dart loop (not notification channel sound).
- Ringtone Looping: Dart-side async loop calling `playSound` MethodChannel repeatedly (500 ms gap); vibration loops 500 ms pulses at 1000 ms intervals until `stopRingtone()`.
- Audio: libcleona_audio (miniaudio with AAudio/OpenSL ES backend)
- Native libs: jniLibs for arm64-v8a + x86_64 (cross-compiled via `scripts/build-android-libs.sh`)

**iOS**:
- In-process, analogous to Android
- Background modes: `audio` for live calls, `fetch` for periodic updates, `processing` for DHT maintenance
- Native libs: all 7 libraries built as static `.a` archives, merged into `libcleona_all_device.a`, linked via CleonaNative CocoaPods podspec with `-force_load` + `EXPORTED_SYMBOLS_FILE` + `STRIP_STYLE=non-global`. See §20.3b for the full explanation of why each setting is needed.
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

  // S&F copy on up to 3 contact peers (receiver-validated)
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

**Conversation-list timestamps**: today shows `HH:MM`, yesterday shows localized "Yesterday" label, 2-6 days shows short weekday abbreviation (Mo/Di/...), same year shows `d.M.`, older shows `d.M.YY`.

**Chat date separators**: a centered date label is inserted between messages from different calendar days. Labels: today = "Heute"/"Today"/..., yesterday = "Gestern"/"Yesterday"/..., 2-6 days = full weekday name, same year = "d. Month", older = "d. Month YYYY". Skipped for vote-sorted channels (Feature Requests). Individual message bubbles continue to show only `HH:MM` — the separator provides the date context. i18n keys: `date_today`, `date_yesterday`, `weekday_1`-`weekday_7` (full), `weekday_short_1`-`weekday_short_7`, `month_1`-`month_12` (all 33 locales).

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

**Lifecycle invariants (Problem-10 hardening, V3.1.117):**
- `startForeground` is idempotent in `onStartCommand` (re-issued on every entry; no "already running" short-circuit that could skip a needed re-promotion after an OS kill).
- `onStartCommand` never swallows an exception and falls through to `stopSelf`: a caught error is reported via `PlatformDispatcher.onError` and the service continues under a degraded "pausiert" notification rather than terminating. The watchdog-kill path is removed — a service killing itself from inside its own lifecycle recreates the OS-restart loop.
- Heartbeat: the heartbeat file is deleted at service start (not guarded by an `isRunning` check) and stamped early; a stale heartbeat from a crashed previous instance must not suppress a fresh start.
- `MainActivity.ensureForegroundService` runs in `onCreate` + `onResume`, but only when the service is not already running (cheap probe, no re-bind storm).
- `runZonedGuarded` is removed from the service path; `PlatformDispatcher.onError` is the single global error sink (defence-in-depth via the existing `FlutterError.onError` + `PlatformDispatcher.onError` pair, §9.5.2).

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

- **Metadata on the wire — by path:**
  - *Fragment / erasure path (§5.6.1):* relay and storage nodes see only a recipient `mailboxId` and encrypted fragments — no sender, no recipient UserID, no timestamp, no message type.
  - *Relay / infrastructure path (§2.2, §2.4.1a):* an on-path relay sees the outer `senderDeviceId`, `timestampMs` and `hopCount` (device-level routing topology and timing), but **not** the UserID, message type or payload — the inner frame is KEM-encrypted (§2.3). This is the deliberate cost of DeviceID-based routing; see the §4.10 routing-metadata threat-model addendum.
  - *DHT identity resolution (§4.3):* a `LivenessRecord` (`userId → deviceId → addresses`) is signed but **not** encrypted in the DHT. An insider who knows a UserID can therefore poll that identity's online status, address changes and device count. This is a conscious trade-off — discovery needs reachable addresses, and in the closed-network insider model (§4.10) DHT records are inherently insider-visible. Encrypting the address set to authorized contacts is a possible future hardening step, weighed against the First-Contact discovery path (a brand-new ContactSeed peer must still resolve the identity) and the fact that the record's existence and refresh cadence would still leak online status.
  - *Structurally protected on every path:* the UserID↔content binding, message type and payload — no relay ever sees "User A messages User B".
- **No analytics:** No telemetry, no crash reporting, no usage tracking. Zero outbound connections except P2P communication.
- **No cloud dependencies:** No Google Play Services required. No Apple iCloud integration. (Push wake-up was considered and rejected; see §12.4.)
- **KEX Gate (§8.2):** Messages from unknown senders are silently dropped at the protocol level. No notification, no "message request" UI — invisible to the recipient.
- **Link previews:** Fetched by the sender, embedded encrypted in the message. The recipient makes zero network requests. SSRF hardening: DNS resolution is checked against private/reserved/loopback ranges before connection; the TCP socket is pinned to the validated IP via `connectionFactory`; HTTP redirects are followed manually with full SSRF re-validation on every hop; IPv6 NAT64 (`64:ff9b::/96`) and 6to4 (`2002::/16`) embeddings are decoded and their inner IPv4 checked. HTTPS only.
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
| K-bucket fill | Bar chart: device count per k-bucket (capacity: 200 per bucket) |
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

**K-bucket visualization:** A bar chart where each bar represents one k-bucket in the Kademlia routing table. Bar height scales from 0 to capacity (200 devices). Tooltip shows bucket index and current fill ratio. This gives advanced users immediate insight into routing table balance — uneven fill indicates proximity clustering in the DHT address space.

**Connection sheet (recovery actions).** Tapping **"Active Peers"** (this dashboard) or **"Connected Peers"** (Settings → Network) opens a shared connection sheet that keeps the dashboard itself read-only while giving recovery actions a home: (1) the live active-peer list, (2) a debounced **Reconnect** button (§12.3.1 tier 2), (3) **import / share peer-list rescue bundle** (§8.1.2 / §12.3.1 tier 3), co-located with manual peer entry.

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

**Distribution channels (external, for initial installation):** GitHub Releases (signed binaries), Google Play (maintainer-signed APK), project website. F-Droid is not possible (requires OSS license). See `docs/PUBLISHING.md` for the full publishing strategy. For censorship-resistant distribution and in-network updates, see §19.6.

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
   - Primary button: attempts In-Network Update first (§19.6.2), falls back to `manifest.downloadUrl` externally (browser / Play Store)
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

### 19.6 Censorship-Resistant Software Distribution

Cleona's distribution currently depends entirely on external gatekeepers: GitHub Releases, Google Play, Apple App Store, and the project website. Each can be individually censored. This section introduces in-network updates, Nostr-based binary discovery, an embedded HTTP server for initial installation, and invite-driven onboarding — so that an installed Cleona network can update itself and onboard new users through existing users without centralized infrastructure.

#### 19.6.1 Design Principles

1. **No single gatekeeper.** Every distribution stage has at least two independent channels.
2. **Person-to-person trust.** The inviter is the trust anchor — not a store, not a label, not a certificate.
3. **Tiered model.** Convenient channels (stores, GitHub) remain as the primary path. Decentralized channels are fallback. Not either-or.
4. **Bootstrapping honesty.** The very first installation always requires an external touchpoint. It can only be made as decentralized and redundant as possible — but not eliminated.
5. **Bootstrap = launch helper, not permanent infrastructure.** The bootstrap node takes on disproportionate load during the network's early phase (complete binaries for all platforms, primary download source). Once enough nodes hold sufficient fragments, the bootstrap can relinquish this role and reduce to its core function (network entry point) — or be shut down entirely. The architecture must never assume the bootstrap as a permanent dependency.
6. **Explicit release.** In-network updates are never triggered automatically from the development process. Only a manually signed manifest triggers an update. Development and test versions stay in the local/beta network.

#### 19.6.2 In-Network Binary Updates

For users who already have Cleona installed. The network delivers updates itself — no external dependency required.

**Flow:**

1. Maintainer signs the new binary (all platforms) with the Ed25519 maintainer key.
2. Maintainer node erasure-codes the binary per platform and distributes fragments to DHT peers.
3. The Update Manifest (§19.5.5) gains new fields alongside the existing `downloadUrl` (external fallback):
   - `dhtBinaryTag: Map<String, String>?` — per platform (linux, windows, android, macos, ios) the DHT lookup tag for erasure fragments.
   - `deltaBinaryTag: Map<String, Map<String, String>>?` — per platform a map from source version to DHT tag for delta patches.
   - `minMonotoneSeq: int` — monotonically increasing sequence number. Nodes reject any manifest with a `minMonotoneSeq` lower than or equal to the highest previously seen value. Prevents downgrade attacks via replayed old (but validly signed) manifests.
4. Receiver node reads the manifest (existing 6h poller), detects new version.
5. Receiver fetches K fragments from N over DHT, assembles the binary, verifies SHA-256 hash + Ed25519 signature.
6. User is prompted for installation (no auto-install — user consent required).

**Release protection — no dev builds in the network:**

The update manifest must be signed with the **Ed25519 maintainer private key**. Without a valid signature, every node ignores the manifest. This prevents development or test builds from accidentally being published as updates.

| Protection | What it prevents |
|---|---|
| Manifest signature (maintainer key) | No node accepts an unsigned or incorrectly signed manifest — dev builds without signature trigger no update |
| Explicit release script (`scripts/publish-in-network-update.sh`) | Manual act, no automatic pipeline trigger — analogous to the existing 4-script push pipeline |
| Beta/Live network separation (§19.5.6) | Different network secrets = different DHT tags — beta updates never reach the live network |
| Monotone sequence number (`minMonotoneSeq`) | Prevents downgrade attacks via replayed old manifests. Each new release increments the sequence; nodes reject manifests with equal or lower sequence than the highest seen |

**Erasure coding parameters — adapted to storage budgets:**

Fragment sizes must fit within the tightest storage budget (mobile: 5 MB). The N/K ratio is chosen so that individual fragments stay below the mobile limit while maintaining the same 1.43x redundancy ratio as message erasure coding (§5.7).

| Platform | Binary size | N | K | Overhead | Fragment size | Fits mobile (5 MB) |
|---|---|---|---|---|---|---|
| Android | ~50 MB | 30 | 21 | ~72 MB | ~2.4 MB | Yes |
| Linux | ~100 MB | 50 | 35 | ~143 MB | ~2.9 MB | Yes |
| Windows | ~90 MB | 50 | 35 | ~129 MB | ~2.6 MB | Yes |
| macOS | ~110 MB | 50 | 35 | ~157 MB | ~3.1 MB | Yes |
| iOS | ~80 MB | 40 | 28 | ~114 MB | ~2.9 MB | Yes |

Higher N means more fragments must be distributed, but each fragment is small enough for any node to hold. K/N = 0.7 (same ratio as message erasure coding: 70% of fragments required for reconstruction).

**Storage budget per node:**

| Node type | Budget | What it holds |
|---|---|---|
| **Bootstrap** (early phase only) | All platforms, complete | Primary download source during network bootstrap. This role is relinquished once sufficient fragment coverage exists across regular nodes. |
| **Desktop node** | Max. 20 MB | ~6-8 fragments of own platform + optionally other platforms |
| **Mobile node** | Max. 5 MB | 1-2 fragments of own platform |

**Fragment garbage collection:** Fragments of older versions are discarded once >90% of reachable peers report the new version (via manifest version in PING). Minimum retention: 30 days. The >90% threshold is measured conservatively: only peers seen in the last 7 days count toward the denominator. Offline nodes are excluded from the calculation — they may still need old fragments when they come back online.

**Maintainer key considerations (roadmap):** The Ed25519 maintainer key is a single point of coercion — a compromised or compelled key signs malicious updates for the entire network. Threshold signing (e.g., 2-of-3 maintainer keys required to sign a manifest) is a future hardening step, tracked in the post-V3.0 roadmap. For now, the single-key model is accepted with the mitigation that reproducible builds (§19.2) allow any user to verify that official binaries match the published source.

#### 19.6.3 Delta Updates

Full binary updates are expensive on mobile data. Delta updates reduce the volume to the actual changes between versions.

**Mechanism:** bsdiff/bspatch. The maintainer generates deltas from V-1 to V and V-2 to V (two generations). Deltas are erasure-coded and distributed analogously to §19.6.2.

**Expected savings:** Typical minor version: 2-5 MB instead of 50-100 MB (>90% reduction).

**Fallback:** If no matching delta is available (version too old, node was >2 releases offline), the updater falls back to full binary (§19.6.2).

#### 19.6.4 Invite Link for Initial Installation

An existing user (Alice) generates a link containing everything a new user (Bob) needs: network access, download source, verification.

**Link format (HTTP, works in any browser):**

```
http://<node-ip>:<port>/cleona#s=<ContactSeed>&h=<BinaryHashMap>&m=<MaintainerSig>&v=<Version>
```

| Parameter | Content | Purpose |
|---|---|---|
| `s` | ContactSeed (Base64) | Alice becomes Bob's first peer (existing §8.1.1 mechanism) |
| `h` | SHA-256 hashes per platform (compressed, Base64) | Bob can verify the downloaded binary |
| `m` | Ed25519 maintainer signature over the hash map | Proves that the hashes come from the maintainer |
| `v` | Version number | Platform detection + version assignment |
| `f` | Fallback URL (optional) | GitHub Release etc. as external fallback |

**Why HTTP, not HTTPS:** Nodes have no domain — no TLS certificate possible. Self-signed certificates trigger browser warnings. Plain HTTP avoids this. Integrity is secured through the SHA-256 hash in the link, authenticity through the Ed25519 maintainer signature. TLS authenticity would be redundant — verification runs through stronger mechanisms.

**Why `http://`, not `cleona://`:** A custom URI scheme only works if Cleona is already installed — chicken-and-egg. An HTTP link opens in the browser on any device. The hash fragment (`#...`) is not sent to the server (browser privacy).

**Inviter privacy consideration:** The invite link contains Alice's IP address. When shared over insecure channels (email, other messengers), this exposes Alice's home IP. Mitigation: (a) dynamic IPs change within 24h, limiting the exposure window; (b) Alice can generate an invite that points to a different public node instead of herself (the ContactSeed `s=` parameter is independent of the download source); (c) for high-threat environments, the physical transfer path (§19.6.8 Stufe 4) avoids IP exposure entirely.

**Cross-platform:** Alice runs on iOS, Bob needs Linux — no problem. The binary source is the network (§19.6.5), not Alice's own binary. Alice provides only the trust anchor (signature, hashes). Bob's browser receives the bootstrap web app from the node and the web app finds nodes with the right platform binary via Nostr lookup.

**Android signing caveat — installSource-based update routing:**

A sideloaded APK (from invite link or physical transfer) and a Play Store APK have different signing keys (Play App Signing vs. maintainer key). Android enforces signature consistency across updates — there is no update path between the two without uninstalling and reinstalling (which loses local data). The app therefore detects its installation source at first launch and permanently routes all future updates through the matching channel:

| `installSource` | Detection | Update channel |
|---|---|---|
| `PLAY_STORE` | `PackageManager.getInstallSourceInfo().installingPackageName == "com.android.vending"` | Google Play (existing store update mechanism, no in-network update) |
| `SIDELOAD` | Any other `installingPackageName` (null, file manager, browser) | In-network update (§19.6.2) — same maintainer signing key, Android accepts the update |

The `installSource` is persisted in the encrypted database at first launch (immutable after that). The update manifest (§19.5.5) includes `downloadUrl` (Play Store link) alongside `dhtBinaryTag` (in-network). The app shows only the update path that matches its `installSource`.

**Consequence for users:** A Play Store user who wants to switch to in-network updates must uninstall and reinstall via sideload (losing local data unless they have a seed-phrase backup). This is Android platform behavior, not a Cleona design choice.

#### 19.6.5 Nostr as Binary Discovery Directory

Extension of the existing Nostr usage (§4.11.6) with a third publish category alongside contact rendezvous (§4.11.6) and infrastructure rendezvous (§4.11.9).

**Problem:** Cleona nodes have dynamic IPs (new every 24h). An invite link cannot contain fixed IPs. Nostr solves this: nodes publish their current IP, Bob looks them up on Nostr.

**Who publishes:** Only nodes that are **directly reachable** publish binary availability records. The address filter from §4.11.7 applies analogously:

- Public IP (bootstrap, port-forwarded): **yes**
- Global IPv6 (not link-local, not ULA): **yes**
- Same LAN as requester (via LAN discovery): **yes** (but not via Nostr — LAN nodes are found through existing LAN discovery §4.5)
- Behind NAT, only reachable via relay: **no** — relay download makes no sense because the relay node itself can offer the packages as a download source

**Binary availability record:**

Every directly reachable node willing to serve binaries (opt-in, default: on) publishes:

```
binary_tag = HKDF-SHA-256(
    ikm    = network_secret,
    salt   = "cleona-rv-binary-v1",
    info   = epoch_string + "/" + platform,
    length = 32
)

binary_key = HKDF-SHA-256(
    ikm    = network_secret,
    salt   = "cleona-rv-binary-key-v1",
    info   = epoch_string,
    length = 32
)

nostr_sk = HKDF-SHA-256(
    ikm    = network_secret,
    salt   = "cleona-nostr-binary-v1",
    info   = hex(own_device_id),
    length = 32
)
```

**Record content (encrypted with `binary_key`):**

```json
{
  "device_id":        "<hex>",
  "platform":         "android|linux|windows|macos|ios",
  "version":          "3.1.125",
  "addresses":        ["1.2.3.4:41338", "[2001:db8::1]:41338"],
  "binary_hash":      "<SHA-256 of the complete binary>",
  "has_full_binary":  true,
  "fragment_indices": [0, 3, 7],
  "seq":              42
}
```

**NIP-33 multi-publisher:** As with infrastructure rendezvous (§4.11.9) — different nodes publish under the same d-tag with different Nostr pubkeys. The resolver query returns all available nodes for a platform.

**Invite-scoped records:**

Bob has no `network_secret` yet. The invite link therefore contains a derived key (not the secret itself):

```
invite_binary_key = HKDF-SHA-256(
    ikm    = network_secret,
    salt   = "cleona-invite-binary-v1",
    info   = invite_nonce,
    length = 32
)
```

The inviting node publishes an invite-scoped record in parallel under a separate tag (derived from `invite_nonce`), encrypted with `invite_binary_key`. TTL: 72h (analogous to first-contact rendezvous §4.11.10). Bob can decrypt it with the key from the link.

**Security note:** A captured invite link yields the `invite_binary_key`, which allows Nostr queries that reveal IP addresses of publishing nodes. The 72h TTL limits the exposure window. This is an accepted trade-off — the same risk profile exists for first-contact rendezvous (§4.11.10), where captured ContactSeed URIs similarly reveal endpoint addresses.

#### 19.6.6 Embedded HTTP Server + Bootstrap Assembler

Every Cleona node includes a minimal HTTP server that delivers the bootstrap web app and binary fragments. No external hosting needed — every directly reachable node is a complete download source.

**Protocol multiplexing on the existing port:**

Cleona already uses TCP on the same port as UDP (TLS fallback, §4.5). HTTP is also TCP. The node identifies the protocol at the start of each incoming TCP connection:

| First bytes | Protocol | Handler |
|---|---|---|
| `GET ` / `HEAD` | HTTP | Static HTTP handler (§19.6.6) |
| `0x16 0x03` (ClientHello) | TLS | Existing TLS fallback (§4.5) |

No additional port required. UDP (SOCK_DGRAM) and TCP (SOCK_STREAM) share the port number kernel-side without conflict — this is already architectural baseline.

**What the HTTP server delivers:**

| Path | Content | Size |
|---|---|---|
| `/cleona` | Bootstrap web app (static HTML + JS) | ~200-400 KB |
| `/cleona/binary/<platform>` | Complete binary (bootstrap nodes in early phase) | 50-110 MB |
| `/cleona/fragment/<platform>/<index>` | Single erasure fragment | 2-3 MB |

**What the HTTP server does NOT do:** No dynamic processing, no CGI, no API, no upload, no directory listing. Only GET on fixed paths. Minimal attack surface. Returns 404 for any unknown path — no server identification headers, no version disclosure.

**DPI fingerprint mitigation:** The HTTP endpoint only responds to specific `/cleona` paths. All other requests receive a generic 404 with no identifying information. The endpoint does not respond to HTTP probes on `/`, `/index.html`, or other common paths. This is not stealth (any sufficiently motivated censor can fingerprint the protocol), but it avoids casual detection by automated scanners.

**Bootstrap assembler flow:**

Bob clicks the invite link. His browser connects via HTTP to the Cleona node:

1. Node delivers the bootstrap web app (static HTML + JS, part of the Cleona binary).
2. Web app reads parameters from the hash fragment (never sent to the server).
3. Web app detects Bob's platform (User-Agent).
4. Web app contacts Nostr relays via WebSocket — finds additional nodes with binary fragments for Bob's platform.
5. Web app downloads the binary (or erasure fragments from multiple nodes) via HTTP.
6. Assembles the complete binary in the browser (WebAssembly for Reed-Solomon).
7. Verifies SHA-256 hash against the hash in the invite link.
8. Verifies Ed25519 maintainer signature (libsodium.js).
9. Offers the verified binary for download.

**Download fallback cascade:**

1. Complete binary from the initial node (if bootstrap with `has_full_binary: true`).
2. Erasure fragments from multiple nodes (Nostr lookup, bandwidth distributed).
3. External fallback (GitHub Release URL in the invite link as `f=` parameter, optional).

**Trust model and MITM analysis:**

The bootstrap assembler is a **best-effort convenience channel**, not a high-security path. The security analysis splits into two distinct layers:

*Layer 1 — Binary integrity (strong):* The binary itself is protected by Ed25519 maintainer signature + SHA-256 hash. The hash and signature travel through the **invite link** — a separate channel (email, SMS, verbal). Even a compromised assembler cannot forge the maintainer signature to make a malicious binary pass verification. Additionally, erasure fragments are fetched from **multiple independent nodes** (via Nostr lookup) — a MITM would need to simultaneously intercept all connections to substitute coherent fake fragments.

*Layer 2 — Assembler integrity (weak):* The bootstrap assembler (HTML+JS) is served over unauthenticated HTTP. A network-level attacker (MITM) could replace the assembler entirely — removing the signature check and delivering arbitrary malware instead. This is the genuine attack surface, and it is **not specific to Cleona**: any software download over HTTP has this property. Mitigations:
- The assembler is deliberately kept small (~50 KB source) — small enough for a technical user to inspect in the browser's developer tools before running.
- The binary hash in the invite link enables **out-of-band verification**: even if the assembler is compromised, Bob can manually compare `sha256sum <downloaded-file>` against the hash from the invite link.
- Fragment downloads from multiple independent nodes make single-point interception insufficient for a coherent binary substitution.
- The closed network model (§4.10) provides **post-installation verification**: a fake binary without the `network_secret` cannot communicate with any legitimate node — the deception is discovered immediately on first launch.

*Why alternative protocols (SFTP, FTPS) do not help:* The assembler runs in a browser, which speaks only HTTP(S). SFTP requires SSH host-key trust (TOFU — no better than self-signed HTTPS). FTPS requires X.509 certificates (same problem as HTTPS — no domain, no CA validation possible). Any protocol that provides transport authentication ultimately requires a pre-shared trust anchor, which is the exact chicken-and-egg problem the invite link solves for the binary (but not for the assembler itself).

*HTTPS is not viable:* Nodes have no domain — Let's Encrypt and all public CAs require domain-based validation (ACME HTTP-01/DNS-01), not IP-based. Self-signed certificates trigger browser warnings that are worse UX than plain HTTP. IP-based certificates from public CAs do not exist. Even if they did, a certificate could be revoked under legal pressure — the integrity guarantee must not depend on a CA's cooperation.

Users in high-threat environments should use the physical transfer path (§19.6.8 Stufe 4) or receive the binary directly from a known contact.

**Browser HTTP download restrictions:** Modern browsers (Chrome, Edge) may block or warn about executable downloads over plain HTTP ("insecure download"). This affects the UX of Stufe 3. Mitigation: the web app can instruct the user to explicitly confirm the download, or the user can copy the direct download URL and use a command-line tool (`wget`, `curl`). The binary hash verification is independent of the transport — the file is verified after download regardless of how it was obtained. This limitation is documented in the UX flow, not hidden.

**iOS special case:** The web app can download an IPA, but iOS does not install it (no sideloading, except EU-DMA markets from iOS 17.4). The web app detects iOS and shows: "On iOS, Cleona is available through the App Store" + Store link.

**Platform-specific installation (implemented):** Once §19.6.2 delivers the verified binary, installation is platform-specific: **Linux** — `applyDesktopUpdate()` backs up the current binary (`.bak`), replaces it, writes an `update-pending.json` marker, and requires a daemon restart. **Android** — `ApkInstaller` copies the verified binary to `cacheDir`, obtains a `content://` URI via `FileProvider`, and launches `ACTION_VIEW` for the system package installer (requires `REQUEST_INSTALL_PACKAGES` permission). **Windows** — same desktop flow as Linux (backup + replace + restart). **macOS** — App Store distribution only; in-network updates are not applicable. **iOS** — no sideloading; `shouldUseInNetworkUpdate()` returns `false`.

**No user-facing rollback (architectural decision, 2026-07-08).** Cleona does NOT offer a rollback/downgrade mechanism to the user, for three reasons: (1) **Forward-only database migrations.** Drift/SQLite schema migrations are irreversible — a newer version may alter tables that the older binary cannot read, causing data loss or crashes on downgrade. (2) **Cryptographic protocol evolution.** Newer versions may rotate KEM parameters, key formats, or message envelope fields. A rolled-back binary may fail to decrypt messages sent by peers who already upgraded, silently dropping traffic. (3) **Monotone sequence enforcement.** The `minMonotoneSeq` field in signed update manifests prevents downgrade attacks (§19.6.2). Accepting a rollback would require bypassing this security gate, weakening the update chain's integrity. Instead: if a release introduces a critical bug, the maintainer publishes a hotfix release (new version, forward migration) within the same distribution pipeline. The Beta cluster provides early detection; the 6h DHT manifest refresh cycle bounds worst-case exposure. Desktop nodes retain a `.bak` backup internally for crash recovery (auto-restore if the app fails within 30s of an update), but this is a safety net, not a user-facing feature — it does not survive across database migrations.

#### 19.6.7 Physical Binary Transfer

For environments where network-based distribution is compromised or unavailable. The ultimate fallback — not censorable except by physical confiscation.

**Supported transfer methods:**

| Method | Platforms | Mechanism |
|---|---|---|
| USB file transfer | Android, Linux, Windows, macOS | Copy APK/binary to device, sideload/execute |
| NFC (Android Beam / HCE) | Android | Tap-to-transfer APK between devices |
| Bluetooth file transfer | Android, Linux, Windows | OBEX file push |
| Local Wi-Fi (HTTP) | All | Sender's Cleona node serves binary via §19.6.6 HTTP server on LAN IP |

**Not supported:** AirDrop (Apple proprietary, and iOS does not allow sideloading anyway).

**Verification after physical transfer:** The transferred binary is verified by SHA-256 hash comparison against a hash the sender communicates verbally or via a separate channel. After installation, the closed network model (§4.10) provides the ultimate verification — a fake binary cannot join the network.

#### 19.6.8 Multi-Fallback Strategy (Overview)

| Tier | Channel | Censorable by | Target |
|---|---|---|---|
| 1 | Google Play / App Store | Apple / Google alone | Initial install (convenient) |
| 2 | GitHub Releases | Microsoft / DMCA | Initial install (sideload) |
| 3 | Invite link + Nostr discovery + node HTTP download | Nostr + all directly reachable nodes blocked | Initial install (decentralized) |
| 4 | Physical (USB / NFC / Bluetooth / LAN Wi-Fi) | Not censorable (except confiscation) | Initial install (ultimate fallback) |
| 5 | In-network update via DHT | Not censorable (as long as 1 peer is reachable) | Updates for existing users |
| 6 | In-network delta update via DHT | Not censorable | Updates (bandwidth-efficient) |

**Once installed = never dependent on externals again.** Tiers 5+6 operate entirely within the Cleona network. External channels (1-4) are only needed for initial installation, and no single one is critical.

#### 19.6.9 Implementation Map

| Concept | Class / File | Key API |
|---|---|---|
| Binary Fragment Store | `BinaryFragmentStore` (`lib/core/update/binary_fragment_store.dart`) | `storeFragment()`, `storeComplete()`, `getFragment()`, `getComplete()`, sync variants, `garbageCollect()`, `enforceBudget()` |
| Reed-Solomon Seeder | `BinarySeeder` (`lib/core/update/binary_seeder.dart`) | `seed()`, `paramsFor()`, `isSeeding()` |
| Update Manager (§19.6.2) | `BinaryUpdateManager` (`lib/core/update/binary_update_manager.dart`) | `checkForUpdate()`, `startDownload()`, `assemble()`, `verify()`, `gc()` |
| Delta Updates (§19.6.3) | `DeltaUpdateManager` (`lib/core/update/delta_update_manager.dart`) | `findDeltaPath()`, `tryDeltaUpdate()` — bsdiff/bspatch glue, falls back to full binary when no path exists |
| HTTP Fragment Server (§19.6.6) | `BinaryHttpServer` (`lib/core/update/binary_http_server.dart`) | `handleConnection()` behind the existing First-Byte-Sniffing multiplexer; serves `/cleona`, `/cleona/binary/<platform>`, `/cleona/fragment/<platform>/<index>` |
| HTTP Fragment Client | `BinaryFetchClient` (`lib/core/update/binary_fetch_client.dart`) | `fetch()` |
| Bootstrap Web App (§19.6.6) | `BootstrapWebApp` (`lib/core/update/bootstrap_web_app.dart`) | `html()` — self-contained HTML+JS assembler (Reed-Solomon + Ed25519 verification client-side) |
| Install Source (§19.6.4) | `InstallSourceDetector` (`lib/core/update/install_source.dart`) | `detect()`, `cached` — Play Store vs. sideload update routing |
| Invite Links (§19.6.4) | `InviteLink`/`InviteLinkGenerator` (`lib/core/update/invite_link.dart`), `InviteLinkService` (`lib/core/update/invite_link_service.dart`) | `InviteLinkGenerator.create()`, `InviteLink.fromUrl()`/`verifySignature()`, `createInviteLink()`, `publishInviteScopedRecord()` |
| Physical Transfer (§19.6.7) | `PhysicalTransferHelper` (`lib/core/update/physical_transfer_helper.dart`) | `exportBinary()`, `exportFragment()`, `importAndVerifyBinary()`, `lanTransferUrl()` |
| Binary Rendezvous (§19.6.5) | `BinaryRendezvousManager`/`BinaryAvailabilityRecord` (`lib/core/network/rendezvous/binary_rendezvous_manager.dart`) | `publish()`, `resolve()`, `resolveAll()` |
| HKDF Derivations (§19.6.5) | `rendezvous_secret.dart` (`lib/core/network/rendezvous/`) | `computeBinaryTag()`, `deriveBinaryKey()`, `deriveBinaryNostrSecretKey()`, `deriveInviteBinaryKey()` |
| Manifest Extensions (§19.6.2) | `UpdateManifest` (`lib/core/update/update_manifest.dart`) | Fields `dhtBinaryTag`, `deltaBinaryTag`, `minMonotoneSeq`, `binaryHashes`, `binarySignatures`, `binarySizes` |
| Orchestration | `CleonaService` (`lib/core/service/cleona_service.dart`) | `startInNetworkUpdate()`, `_selfSeedCurrentBinary()`, `_buildBinaryAvailabilityRecord()` |

**Erasure parameters as implemented** (`BinarySeeder.platformParams`, matches §19.6.2 table): Android N=30/K=21, Linux/Windows/macOS N=50/K=35, iOS N=40/K=28. **Storage budgets as implemented** (`BinaryFragmentStore.kMobileBudgetBytes`/`kDesktopBudgetBytes`, enforced via `enforceBudget()`): mobile 5 MB, desktop 20 MB — matches the §19.6.2 storage budget table.

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
| **cleona_pow** | `proof_of_work.dart` (inline FFI) | PoW SHA-256 iteration loop in C — calls `crypto_hash_sha256` in a tight loop without per-iteration Dart↔C transitions | Links against libsodium. Build: `cmake -B build -S native/cleona_pow && cmake --build build`. Graceful fallback: platforms without the library use the Dart-side iteration loop transparently. |

The **cleona_net** entry in the table above deserves a longer explanation because, unlike the other native libraries in this list, it does not unlock a feature that would otherwise be unavailable — Dart already ships a perfectly working `RawDatagramSocket`. We introduced the shim because Dart's implementation on Windows silently drops roughly 89 percent of sustained UDP send calls during the LAN-Discovery subnet-scan phase, while the very same workload (200-15000 packets at up to 500 pps to many different destinations) goes through with zero drops when issued by PowerShell's `.NET UdpClient`. The forensic chain that established this is documented at §4.5.2 — pktmon-counters on the Windows TCPIP layer confirm the dropped sends never reach the kernel, and raising the kernel `SO_SNDBUF` to 4 MB did not change the drop rate. The defect therefore lives inside Dart's Windows I/O implementation (likely the IOCP-based UDP send path), below where any Dart-level workaround can reach. Linux is unaffected — Dart's POSIX path uses blocking `sendto` and behaves identically to the C shim. We build and link the shim on Linux as well for the **discovery send path** (`LocalDiscovery`, port 41338). The **main data-port** transport (`Transport.sendUdp`), however, uses the native sender **only on Windows** (V3.1.72). Rationale: `cleona_udp_open` binds a real `SO_REUSEADDR` UDP socket on the given port; when opened on the *data* port in addition to Dart's receive socket, the Linux kernel delivered inbound datagrams to the send-only native socket — which is never read — starving the Dart `RawDatagramSocket` and breaking **all** inbound processing (no PONG → no peer ever confirmed → dead mesh). This was a regression introduced by commit `2fbc879` (it extended the Windows send-fix to the main port without updating this section). Because Dart's POSIX send path is unaffected (stated above), the Linux main port now uses `RawDatagramSocket` for both send and receive — exactly **one** socket per data port. `Transport.start()` enforces this with a `/proc/net/udp` self-check that logs an error if a second IPv4 socket ever binds the data port again. A behavioural regression guard lives in `test/smoke/smoke_udp_receive_path.dart`.

The native library is a hard dependency on Linux and Windows desktop builds. If `libcleona_net.so` (Linux) or `cleona_net.dll` (Windows) is missing at daemon startup, the daemon refuses to start and prints a clear error message naming the expected file path. There is no fallback to the Dart send path. This is deliberate: a silent fallback would mask a broken build or a missed deployment step exactly the way the Windows drops themselves went unnoticed for weeks, and we would risk discarding a working architectural fix as "useless" because operations look identical to the un-fixed state.

Android, iOS, and macOS builds do not include `libcleona_net` and continue to use Dart's `RawDatagramSocket` directly. On those platforms the Dart-RawDatagramSocket implementation has no observed drop pattern, so introducing the shim there would only enlarge the trusted native-code surface without functional benefit. If a regression appears on one of those platforms in a future release, the shim can be extended (Phase 2) — the C source is platform-agnostic POSIX on those targets.

### 20.3a Build Mechanics for cleona_net

C sources live under `native/cleona_net/` (parallel to `native/cleona_audio/`) with a CMakeLists.txt that produces `libcleona_net.so` on Linux and `cleona_net.dll` on Windows. The Linux build is bundled into the Flutter Linux release alongside `libcleona_audio.so`; the Windows build drops into `build/windows/x64/runner/Release/` next to `libsodium.dll` and `liboqs.dll`. Exact build invocations and packaging steps are kept with the source tree rather than duplicated here — see `native/cleona_net/README.md` for the build recipe and `docs/PUBLISHING.md` for the release-bundle assembly.

### 20.3b iOS Native Library Build Pipeline

Dieses Kapitel erklaert wie die nativen C-Bibliotheken fuer iOS gebaut und ins App-Binary gelinkt werden. Es beschreibt jede Einstellung und warum sie genau so sein muss. Die Erkenntnisse stammen aus einer mehrtaegigen Debugging-Session (2026-06-01 bis 2026-06-04) mit ueber 15 CI-Iterationen und On-Device-Diagnostik.

#### Das Grundproblem: iOS erlaubt keine eigenen dynamischen Bibliotheken

Auf Linux, Android, Windows und macOS laedt Cleona seine nativen Bibliotheken (libsodium, liboqs usw.) als separate Dateien zur Laufzeit: `.so` auf Linux/Android, `.dylib` auf macOS, `.dll` auf Windows. Jede Bibliothek ist eine eigene Datei mit eigenem Namensraum. Duplikate zwischen Bibliotheken sind kein Problem weil sie nie zusammengefuegt werden.

**iOS verbietet das.** Apple erlaubt in App-Bundles keine eigenen `.dylib`-Dateien. Aller nativer Code muss statisch in das Runner-Binary (die ausfuehrbare Datei der App) gelinkt werden. Darts `DynamicLibrary.process()` sucht die Funktionen dann mit `dlsym(RTLD_DEFAULT, "funktionsname")` in der Symboltabelle des eigenen Prozesses.

Daraus folgt eine Kette von Problemen die auf keiner anderen Plattform auftreten:
1. Alle neun Bibliotheken muessen in EIN Binary
2. Dabei entstehen doppelte Symbole (gleicher Funktionsname in mehreren Bibliotheken)
3. Der Linker muss diese Duplikate aufloesen ohne Fehler
4. Die Symbole muessen nach dem Linken fuer `dlsym()` sichtbar bleiben
5. Der Xcode-Stripping-Schritt darf die Sichtbarkeit nicht zerstoeren

#### Schritt 1: Native Bibliotheken kompilieren

Das Script `scripts/build-ios-libs.sh` kompiliert alle neun Bibliotheken (libsodium, liboqs, libzstd, liberasurecode, libopus, whisper.cpp, libcleona_audio, libvpx, libcleona_vpx) als statische Archive (`.a`-Dateien) fuer iOS arm64. Es laeuft auf macOS (braucht Xcode mit iOS SDK) und wird im CI auf einem GitHub Actions `macos-14` Runner ausgefuehrt.

Jede Bibliothek wird fuer zwei Zielplattformen gebaut: `arm64-iphoneos` (echtes Geraet) und `arm64-iphonesimulator`. Die Ergebnisse werden als XCFrameworks verpackt (`xcodebuild -create-xcframework`).

Besonderheit `libcleona_audio`: Verwendet miniaudio das auf Apple-Plattformen Objective-C-Header (AVFoundation) einbindet. Deshalb muss CMake mit `project(cleona_audio C OBJC)` konfiguriert werden und die Quelldatei `miniaudio_impl.c` als Objective-C kompiliert werden. Ausserdem baut CMakes Ninja-Generator auf iOS die vendored speexdsp-Objekte direkt in `libcleona_audio.a` ein (anders als auf anderen Plattformen wo speexdsp in die Shared Library eingebettet wird). Deshalb darf `speexdsp/lib` NICHT zusaetzlich in den Merge-Schritt.

#### Schritt 2: Alle Archive in eines zusammenfuehren

Das Build-Script fuehrt alle einzelnen `.a`-Dateien mit `xcrun libtool -static` in ein einziges Archiv zusammen: `libcleona_all_device.a`. Dieses eine Archiv wird dann ins App-Binary gelinkt.

Dabei werden bestimmte Unter-Bibliotheken uebersprungen weil ihr Inhalt bereits in der Haupt-Bibliothek enthalten ist:

| Uebersprungen | Grund |
|---|---|
| `libggml-base.a`, `libggml-cpu.a` | Inhalt steckt bereits in `libggml.a` (der Umbrella-Bibliothek von whisper.cpp) |

Alle anderen Bibliotheken bleiben im Merge, auch die Unter-Bibliotheken von liberasurecode (`libXorcode.a`, `libnullcode.a`, `liberasurecode_rs_vand.a`), weil `liberasurecode.a` deren Funktionen referenziert aber NICHT einbettet.

Nach dem Merge enthaelt das Archiv etwa 9 doppelte Symbole:

| Duplikate | Herkunft | Warum doppelt |
|---|---|---|
| 4 C++-Runtime-Stubs (`__clang_call_terminate` usw.) | liboqs und whisper.cpp kompilieren beide C++-Code, der identische Compiler-Hilfsfunktionen erzeugt | Beide Bibliotheken brauchen diese Stubs eigenstaendig |
| 5 `rs_galois_*`-Funktionen | liberasurecode und liberasurecode_rs_vand teilen Galois-Feld-Code | Historisches Build-Artefakt der liberasurecode-Bibliothek |

Diese 9 Duplikate werden NICHT im Build-Script behoben. Sie werden vom Linker aufgeloest (siehe Schritt 3).

#### Schritt 3: Die drei kritischen Xcode-Einstellungen

Die Datei `ios/CleonaNative/CleonaNative.podspec` setzt drei Xcode-Build-Einstellungen die zusammenarbeiten. Jede einzelne ist zwingend notwendig. Wird eine entfernt oder geaendert, bricht entweder der Build oder die App.

**Einstellung 1: `OTHER_LDFLAGS = -force_load <pfad>`**

Sagt dem Linker: Lade ALLE Objekt-Dateien aus dem Archiv in das Binary, auch wenn kein Swift- oder Objective-C-Code sie referenziert. Ohne dieses Flag wuerde der Linker das gesamte Archiv ignorieren weil aus seiner Sicht niemand die C-Funktionen aufruft (der Aufruf kommt erst zur Laufzeit ueber `dlsym`).

**Einstellung 2: `EXPORTED_SYMBOLS_FILE = <pfad>`**

Verweist auf die Datei `ios/CleonaNative/cleona_exported_symbols.txt`. Diese Datei listet alle 67 C-Funktionen auf die Dart zur Laufzeit per `dlsym()` sucht (z.B. `_sodium_init`, `_OQS_init`, `_ZSTD_compress`, `_opus_encode`, `_whisper_init_from_file`, `_cleona_audio_create`).

Diese Einstellung hat zwei Effekte:
1. Die aufgelisteten Funktionen werden als Wurzeln fuer die Entfernung von totem Code markiert. Der Linker behaelt sie und alles was von ihnen erreichbar ist. Nicht erreichbarer Code (einschliesslich der 9 doppelten Symbole) wird stillschweigend entfernt. So werden die Duplikate aufgeloest ohne dass der Linker einen Fehler meldet.
2. Die aufgelisteten Funktionen werden in die Export-Tabelle des Binarys geschrieben. Nur Funktionen in der Export-Tabelle sind fuer `dlsym()` zur Laufzeit sichtbar.

**WICHTIG:** Wenn eine neue FFI-Funktion in Dart hinzugefuegt wird (ein neuer `lookupFunction()`-Aufruf), MUSS das entsprechende Symbol in `cleona_exported_symbols.txt` eingetragen werden. Sonst wird die Funktion vom Linker als toter Code entfernt und die App stuerzt zur Laufzeit ab.

**Einstellung 3: `STRIP_STYLE = non-global`**

Nach dem Linken entfernt Xcode Symbole aus dem Binary um die Dateigroesse zu reduzieren (Stripping). Die Standard-Einstellung `all` entfernt ALLE Symbole einschliesslich der Export-Tabelle. Das bedeutet: der Linker schreibt die Export-Tabelle korrekt, aber Xcode loescht sie danach wieder. `dlsym()` findet dann zur Laufzeit nichts.

`non-global` sagt Xcode: Entferne nur lokale Symbole (Debugging-Informationen, interne Hilfsfunktionen), aber behalte die globalen/exportierten Symbole. Damit bleibt die Export-Tabelle intakt und `dlsym()` funktioniert.

#### Zusammenspiel der drei Einstellungen

```
force_load               → Alle Objekt-Dateien werden geladen (auch ohne statische Referenz)
EXPORTED_SYMBOLS_FILE    → Markiert FFI-Funktionen als Wurzeln + schreibt sie in die Export-Tabelle
                           + loest Duplikate auf (toter Code wird entfernt, inkl. doppelter Definitionen)
STRIP_STYLE=non-global   → Bewahrt die Export-Tabelle beim Stripping

Fehlt force_load         → Keine nativen Symbole im Binary (Linker ignoriert das Archiv)
Fehlt EXPORTED_SYMBOLS   → Alle Symbole als toter Code entfernt ODER Duplikat-Fehler beim Linken
Fehlt STRIP_STYLE        → Export-Tabelle geloescht, dlsym findet nichts (weisser Bildschirm)
```

#### Was NICHT funktioniert (getestete Sackgassen)

Die folgenden Ansaetze wurden zwischen 2026-06-01 und 2026-06-04 getestet und verworfen. Sie sind hier dokumentiert damit sie nicht erneut versucht werden.

| Ansatz | Warum gescheitert |
|---|---|
| `DEAD_CODE_STRIPPING = NO` (ohne EXPORTED_SYMBOLS_FILE) | Alle Symbole bleiben erhalten, aber die 9 Duplikate erzeugen Linker-Fehler. Auch mit `-ld_classic` Flag nicht loesbar. |
| `-ObjC -all_load` statt `-force_load` | Laedt Objekt-Dateien aus ALLEN statischen Bibliotheken, nicht nur aus unserer. Konflikte mit System-Bibliotheken. |
| `ld -r` (Pre-Link) zum Deduplizieren | Scheitert an den 9 starken (nicht-schwachen) Duplikaten. `ld -r` toleriert nur schwache Duplikate. |
| Separate `-force_load` pro Bibliothek (statt Merge) | Gleiche Duplikat-Fehler, nur mit mehr Pfaden. |
| `ar`-basierte Deduplizierung nach dem Merge | Fragil, scheitert an `set -euo pipefail` wenn `grep` keine Treffer findet. Objekt-Dateinamen kollidieren beim Extrahieren. |
| xcconfig-Injection nach `pod install` | `flutter build ipa` fuehrt intern nochmal `pod install` aus und regeneriert die xcconfigs. |
| `sed` in `project.pbxproj` | Pods-xcconfig hat hoehere Prioritaet und ueberschreibt pbxproj-Settings. |
| `-exported_symbols_list` in `OTHER_LDFLAGS` (statt als eigene Einstellung) | Xcode interpretierte nachfolgende Flags (`-lc++`) als Dateipfade. |
| Nur `EXPORTED_SYMBOLS_FILE` ohne `STRIP_STYLE=non-global` | Symbole werden korrekt gelinkt (nm bestaetigt 81 exportierte Symbole im xcarchive), aber das Standard-Stripping (`all`) loescht die Export-Tabelle. `dlsym()` findet zur Laufzeit nichts. |

#### macOS Build Pipeline

macOS verwendet im Gegensatz zu iOS normale dynamische Bibliotheken (`.dylib`). Es gibt keine der oben beschriebenen Komplikationen.

`scripts/build-macos-libs.sh` baut alle Bibliotheken als Shared Libraries fuer arm64 (Apple Silicon), x86_64 (Intel) oder universal (lipo merge). `install_name_tool` setzt die Lade-Pfade auf `@rpath/<name>.dylib`. Alle dylibs werden ad-hoc signiert.

`scripts/deploy-macos-app.sh` baut das endgueltige `Cleona.app` Bundle zusammen: Flutter GUI + headless Daemon + dylibs in `Contents/Frameworks/`.

#### CI/CD

Der GitHub-Actions-Workflow `.github/workflows/ios-build.yml` baut iOS und macOS auf einem `macos-14` Runner.

Die iOS-Pipeline: Native Bibliotheken kompilieren und mergen → XCFrameworks als Artifact hochladen → `flutter build ipa` → Code-Signierung (Apple Development Zertifikat, manuelles Provisioning Profile) → IPA als Artifact hochladen.

Die macOS-Pipeline (parallel): Native dylibs bauen → `flutter build macos` → Daemon kompilieren → App-Bundle zusammenbauen → Code-Signierung → DMG erstellen → Notarisierung ueber App Store Connect API.

Signatur-Credentials (Zertifikat als .p12, Provisioning Profile, API Key) liegen als GitHub Secrets (base64-kodiert). Die .p12-Datei muss im Legacy-PKCS12-Format (3DES+SHA1) vorliegen weil der `security import`-Befehl auf macOS CI-Runnern das OpenSSL-3.x-Standardformat ablehnt.

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
## 23. Roadmap

### 23.1 V3.0 Status

V3.0 is an architectural major revision (see §1.2 V3.0 Architecture Highlights). Implementation status is tracked in the code repository via tags (`v3.0.0-beta.X`) and in the project memory — this spec is the authoritative architectural reference, not a project-plan tracker.

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

### 23.2 Post-V3.0 Plans

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

## 24. Platform Suitability

Cleona is a serverless P2P messenger. Its architecture requires: a permanently open UDP port, a long-running background process, and unrestricted network access. How well each operating system supports these requirements directly determines the user experience.

### 24.1 Ranking

| Rank | Platform | Verdict |
|------|----------|---------|
| 1 | Linux Desktop | Best possible experience |
| 2 | macOS | Near-Linux experience |
| 3 | Windows Desktop | Full experience, platform-specific workarounds required |
| 4 | Android | Good experience with one architectural compromise |
| 5 | iOS | Significantly degraded background delivery |

### 24.2 Platform Details

**Tier 1 — Linux Desktop**

The reference platform. The daemon runs without restrictions, UDP works natively, IPC uses Unix sockets, and the OS imposes no limits on background execution or networking. Users get instant message delivery, reliable calls, and full offline-recovery — exactly as the architecture intends.

**Tier 2 — macOS**

Architecturally almost identical to Linux: Unix foundation, daemon + GUI over Unix-socket IPC, no background execution limits, no sandbox enforcement (outside App Store distribution). The only friction is distribution-side: Apple requires notarization and Gatekeeper approval, and builds need a macOS runner. At runtime, the user experience matches Linux.

**Tier 3 — Windows Desktop**

Conceptually a good fit — Windows allows background services without restrictions, and ports can be opened freely. However, Dart's `RawDatagramSocket` on Windows exhibited an 87.9% UDP packet drop rate due to IOCP (I/O Completion Port) behavior, which required a native C shim (`libcleona_net`, direct `WSASendTo`) to work around (see §4.5). IPC uses TCP + auth token instead of Unix sockets, adding complexity. Process management (Scheduled Task, PID/lock files) proved more error-prone than on Unix. These are solved problems, but each Windows-specific behavior costs disproportionate development effort. Users get the full experience after these workarounds.

**Tier 4 — Android**

The first platform where the OS actively works against Cleona's architecture. There is no separate daemon — everything runs in-process. Background message delivery relies on a Foreground Service with a persistent notification (all push-based alternatives were evaluated and rejected — see §12.4). Google's battery optimization (Doze, App Standby) can delay or kill background processes despite the Foreground Service contract. Mobile networks typically use CGNAT/DS-Lite, making direct peer connections unreliable and forcing the relay cascade (Direct → Relay → Store-and-Forward). **User impact:** messages generally arrive promptly while the app is in foreground or the Foreground Service is active, but aggressive OEM battery management (Samsung, Xiaomi, Huawei) may occasionally delay delivery. Users must exempt Cleona from battery optimization for reliable background operation.

**Tier 5 — iOS**

The most restrictive platform for Cleona's use case. Apple does not offer a Foreground Service equivalent. Background execution is limited to BGTaskScheduler. Cleona registers two independent task types — a BGAppRefreshTask (~30s runtime) and a BGProcessingTask (minutes of runtime) — to maximize wakeup frequency within Apple's constraints (dual-task strategy, §12.5). There is no way to maintain a persistent UDP socket in the background. **User impact:** while the app is open, messages arrive instantly. When the app is in the background, message delivery is delayed until the next BGTask window or until the user opens the app. With the dual-task strategy, typical delays are 5–30 minutes for regularly-used apps (improved from 15–60 minutes with a single task type), though the OS remains in full control of scheduling. Calls cannot be received in the background without the VoIP push exception (which Apple restricts to apps using CallKit). This is not a bug or missing feature — it is a fundamental conflict between iOS's design philosophy (apps should not run in the background) and Cleona's architecture (peers must be reachable). The full P2P experience is only available while the app is in the foreground.

**Dart Socket Constraints on iOS.** Beyond the background-execution limitations, Dart's `RawDatagramSocket` on iOS has two platform-specific behaviors that require architectural mitigation:

*Send path failure.* `RawDatagramSocket.send()` silently returns 0 for all destinations (errno 64/65 from the kqueue I/O path). Cleona uses `IosUdpSender` to call native `sendto()` on the Dart socket's own file descriptor — see §4.5.2 for details.

*Receive path failure (kqueue event stall).* After a burst of native `sendto()` calls, Dart's kqueue event loop stops delivering `RawSocketEvent.read` on the transport sockets. The kernel receive buffer accumulates packets but neither `_onUdpEvent` nor `_onUdpEvent6` fires. **Recovery:** `IosUdpSender` runs a 50ms polling timer (`_iosNativeRecvPoll`) that calls native `recvfrom()` on both the IPv4 fd (`recvFrom()`) and the IPv6 fd (`recvFrom6()`), bypassing Dart's event delivery entirely. This is the **primary receive path** on iOS — the Dart kqueue handlers serve as a secondary path that may occasionally work. Diagnostics peek both fds (`recvPeek()` / `recvPeek6()`) every 10s; EBADF (-9) on either fd triggers the socket-death recovery described below. A 30-second silence watchdog (mirroring the Windows `checkReceiveHealth` mechanism) triggers the same recovery if both the Dart kqueue path and the native polling path receive zero packets for 30+ consecutive seconds — defense-in-depth against stall modes that bypass the per-fd EBADF check.

*Socket file-descriptor death.* iOS closes Dart's UDP socket file descriptors approximately 40–60 seconds after app start (EBADF, errno 9, on both IPv4 and IPv6). This appears related to iOS's network-route lifecycle: sockets opened before the WiFi route is fully established are invalidated when iOS finalizes the route. After socket death, both the Dart listen stream and `IosUdpSender`'s cached fd become stale. **Recovery:** Transport runs a 10-second diagnostic timer that calls `recvPeek()` on the native fd. When the return value is -9 (EBADF), it fires `onUdpSocketDead`, which triggers the full network-change recovery cycle: close dead sockets, bind fresh ones on the same port, rescan the new fd for `IosUdpSender`, re-PING all neighbors, re-publish identity. The gap between socket death and recovery is at most one timer tick (10 seconds); any ACK-worthy message whose DELIVERY_RECEIPT has not yet been received at the time of socket death is parked in the persistent outbox (`outbox.json.enc`, §5.1) and re-attempted on the recovery event — there is no persistent SendQueue (removed in V3.0). The socket `onError` stream handlers provide a faster parallel detection path for the same condition.

*Async error propagation.* Fire-and-forget UDP sends (LAN discovery broadcasts, UPnP SSDP probes) throw `SocketException` asynchronously via the socket's error stream when iOS has no network route at startup — not synchronously from `send()`. Every `RawDatagramSocket.listen()` call in iOS-reachable code paths must include an `onError` handler; omitting it causes the exception to propagate as an unhandled zone error.

These three constraints apply only to the foreground session. The BGTaskScheduler path (§12.5) opens fresh sockets per wakeup cycle and closes them before completion, sidestepping the fd-lifecycle issue entirely.

### 24.3 Summary

The core pattern: the less a platform restricts background execution and network access, the better Cleona works. Linux and macOS let the daemon run as designed. Windows requires workarounds but achieves the same result. Android compromises with a Foreground Service. iOS cannot deliver the real-time P2P experience that the other platforms provide — background message delivery is at the mercy of the OS scheduler.

Users who rely on instant, reliable message delivery should prefer desktop platforms. Mobile platforms trade some reliability for portability, with Android offering a significantly better background experience than iOS.

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

enum PayloadType {                   // proto: PayloadTypeV3, on-wire values PAYLOAD_*-prefixed
  APPLICATION_FRAME              = 0; // payload = KEM-encrypted ApplicationFrame (Identity layer)
  ONION_LAYER                    = 1; // payload = KEM-encrypted nested NetworkPacket (V3.0 not active, §2.5)
  INFRASTRUCTURE_FRAME           = 2; // payload = KEM-encrypted InfrastructureFrame (Device-targeted, §2.3.5)
  BOOTSTRAP_INFRASTRUCTURE_FRAME = 3; // payload = BOOT-path InfrastructureFrame (§2.3.5 / §2.4.1a)
}
// Unknown/future payloadType → silent drop (forward-only). Canonical numbering, matches §2.2.
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
  bytes  aeadCiphertext   = 3;   // AES-256-GCM(serialized ApplicationFrame) + 16-byte tag
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

  // ── Store-and-Forward on Contact Peers ─────────────────────
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
  IDENTITY_KEM_PUBLISH       = 176;  // DeviceKemRecord publish (§4.3 / §2.3.5)
  IDENTITY_KEM_RETRIEVE      = 177;
  IDENTITY_KEM_RESPONSE      = 178;

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

  // ── Deferred Key Exchange (§8.1.1) ────────────────────────
  DEVICE_KEM_REQUEST         = 220;  // request a device's KEM-PK set via SeedPeers
  DEVICE_KEM_OFFER           = 221;  // signed response carrying deviceX25519Pk + deviceMlKemPk

  // ── First-CR-Mailbox (§5.5b) ──────────────────────────────
  FIRST_CR_STORE             = 222;  // store an encrypted First-CR blob on a SeedPeer
  FIRST_CR_STORE_ACK         = 223;
  FIRST_CR_DELIVER           = 224;  // SeedPeer delivers the stored blob to the recipient
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
field 10 (userEd25519Sig)  = 64 bytes  (Alice User-Ed25519 sig over the full serialized ApplicationFrame with the sig fields cleared — all content fields, not just 1-7; see signApplicationFrameInner)
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

**InfrastructureFrame** (BOOT path, §2.3.5 — no KEM and no frame-level user sig; the record is self-validating via its own internal signatures):
```
recipientDeviceId = c8b73e... (replicator device)
senderDeviceId    = alice.device
messageType       = IDENTITY_AUTH_PUBLISH (170)
payload           = AuthManifestProto {
                      userId = alice.userId,
                      authorizedDeviceIds = [alice.device1, alice.device2],
                      ttlSeconds = 86400,
                      sequenceNumber = 17,
                      publishedAtMs = 1714555200000,
                      ed25519Sig = 64 bytes,      ← internal sigs validate the record
                      mlDsaSig = 3293 bytes,
                      userEd25519Pk = 32 bytes,
                      userMlDsaPk = 1952 bytes
                    }
                  ≈ 5400 bytes
(no frame-level userEd25519Sig / userMlDsaSig — BOOT InfrastructureFrames carry no user sig, §2.3.5)
```

Serialized inner ≈ 5450 bytes. BOOT path: no KEM, the InfrastructureFrame payload goes straight into the outer frame.

**NetworkPacket (Outer)**:
```
nextHopDeviceId   = c8b73e... (replicator device)
deviceEd25519Sig  = 64 bytes
deviceMlDsaSig    = 0 bytes (Infrastructure exempt)
payloadType       = BOOTSTRAP_INFRASTRUCTURE_FRAME
payload           = 5450 bytes (serialized InfrastructureFrame, no KEM wrap)
```

Total ≈ **5750 bytes**. Per auth-manifest refresh (every 20 h) × K=10 replicators ≈ 57 KB per refresh cycle per user identity. Acceptable.

### B.4 RELAY_FORWARD (Multi-Hop Relay)

**Context**: Alice's NetworkPacket to Bob (B.1 above, 8090 bytes) has to traverse relay Carol (`0x6c39f8...`) because the direct path fails.

**Outer NetworkPacket** (Alice → Carol):
```
nextHopDeviceId   = 6c39f8... (Carol)
senderDeviceId    = a5fa07... (Alice)
deviceEd25519Sig  = 64 bytes
deviceMlDsaSig    = 3293 bytes
payloadType       = INFRASTRUCTURE_FRAME
payload           = KEM-encap(Carol.deviceKemPk, InfrastructureFrame {
                      recipientDeviceId = 6c39f8... (Carol — the decrypting hop)
                      messageType = RELAY_FORWARD (153)
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
                      (no user sig — RELAY_FORWARD is KEM-Infrastructure, §2.3.5)
                    })
                  ≈ 9400 bytes after KEM encryption for Carol
```

Total wire size for relay hop 1 ≈ **9.6 KB** (the inner carries no user sig — only the wrapped original packet plus Carol's KEM wrap). At 3 hops the total stays similar (each hop only unwraps and rewraps, adding its own outer sig, but the `wrappedPacket` stays the same).

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

