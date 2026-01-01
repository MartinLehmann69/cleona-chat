# Cleona Chat — Architecture & Technical Specification 4.2

<!-- AUTO-GENERATED from Cleona_Chat_Architecture_v4_2.md (sha256:55648169985d, 2026-09-25). -->
<!-- Edits to this file will be overwritten. Edit the master in Cleona/. -->

> **What this document is.** The complete, normative description of
> Cleona Chat: a decentralised, serverless, post-quantum encrypted
> messenger. It covers everything from the bytes on the wire to platform
> behaviour, and it is written to be built from. Where an
> implementation and this document disagree, this document governs.
>
> **How to read it.** Chapters 3 to 12 describe how a packet gets from
> one device to another; chapter 15 how two people become contacts;
> chapter 4 the cryptography underneath all of it. Everything after
> that builds on those. Each chapter states its parameters explicitly,
> and every number in a parameter table is a value to implement, not an
> illustration.
>
> **The principle everything else follows from:** delivery works on its
> own. Concealment runs beside it and never carries anything a delivery
> depends on. A packet
> leaves the device the moment it exists, by whichever of four ways
> reaches the recipient first. Nothing in the delivery path waits for a
> timer.
>
> **Language:** English.

---

## Chapter map

| § | Title | What it settles |
|---|---|---|
| 1 | Executive Summary | what the product is and what it guarantees |
| 2 | Threat model | who the adversary is and what is out of scope |
| 3 | The delivery architecture | the four layers, and the one rule |
| 4 | Identity & Cryptography | keys, sealing, signatures, rotation |
| 5 | The cover system | concealment beside the traffic; update pieces; bandwidth budgets |
| 6 | Reachability | how a node learns whether another can be reached |
| 7 | Direct ways (ladder steps 1 and 2) | local segment and public address |
| 8 | Indirect ways (ladder steps 3 and 4) | forwarding and the post box |
| 9 | Delivery state and acknowledgement | the four states, receipts, redundancy, media lanes |
| 10 | Sybil & censorship resistance | admission cost and what it buys |
| 11 | NAT & transport | sockets, ports, fragmentation, address discovery |
| 12 | What the interface shows | per message, per connection, per invitation, network switches |
| 13 | Identity recovery | seed phrase, recovery bundle, total loss — no guardians (§13.8) |
| 14 | Multi-Device | device keys, delegation, revocation |
| 15 | First contact & identity authorization | the card, the five packets, the KEX gate |
| 16 | Groups & Channels | private groups, public channels, moderation |
| 17 | Calls | voice, video, group topology |
| 18 | Calendar & Polls | events, recurrence, voting |
| 19 | Synchronization strategy | what is synchronised between devices |
| 20 | Network resilience | behaviour under partition and load |
| 21 | Storage & data management | what is stored, where, encrypted how, for how long |
| 22 | Application architecture | processes, seams, platform wiring |
| 23 | Permissions & privacy | what the app may access and what it never sends |
| 24 | Internationalization | 34 locales, RTL, completeness rule |
| 25 | Network statistics | what a node counts and shows |
| 26 | License & funding | licensing and funding model |
| 27 | Tech stack | languages, libraries, native code |
| 28 | Test strategy | smoke, end-to-end, field acceptance |
| 29 | Development environment | how to build and run it |
| 30 | Build order | the sequence in which the system is built |
| 31 | Platform suitability | what each platform can and cannot do |
| A | Parameters & tuning | every tunable value in one place |
| B | Declared limits | what the design does not attempt |
| C | Open work | measurement and build work still to do |
| D | Settled decisions | what is decided and must not be asked again |

---
## 1. Executive Summary

Cleona Chat is a decentralised, post-quantum encrypted messenger with no
servers. Every participant is a peer; a peer that forwards for somebody
else is still just a peer. Identity is purely cryptographic — no phone
number, no email address, no account.

This chapter states what the system must achieve, the principles it is
built on, and what it costs. Everything after it is the specification.

### 1.1 The ten requirements and one threat constraint

Cleona exists to satisfy ten equally weighted requirements and one threat
constraint, simultaneously:

| | Requirement | Where addressed |
|---|---|---|
| a | No servers | §4, §11 — peers are the network; a forwarder is just a peer |
| b | Censorship-resistant | §2, §5, §9, §10 — indistinguishable traffic, cover, redundancy, the KEX gate |
| c | Anonymous towards third parties | §5, §8 — sealed content, opaque forwarding, cover beside the traffic |
| d | Post-quantum secure | §4 — hybrid KEM and hybrid signatures, per message |
| e | Message exchange under 10 s | §7 — under 1 s in a local segment; seconds over the internet |
| f | Same behaviour on every platform | §7, §8, §11 — one port, one path; platform differences are physics only |
| g | Minimal network traffic | §5 — nothing periodic in idle except one keep-alive per address family behind translation or a firewall (§8.1), and the cover stream, which always runs: 12.96 MB/day, 1.73 MB/day on metered mobile data |
| h | Works behind address translation | §7.3, §8.1 — knocking, and forwarding through a reachable neighbour |
| i | IPv4 and IPv6 | §11 — dual-stack on a single port |
| j | Offline delivery | §8.2 — the post box; latency is the recipient's return |

**Threat constraint:** a state must not be able to read or censor the
communication. Reading is closed by post-quantum end-to-end encryption
(§4). Censoring is answered by traffic that is hard to classify,
redundancy across independent paths, and the absence of any single point
to block (§5, §9, §10). The threat model is stated in §2.

### 1.2 Core principles

1. **Delivery works on its own.** A packet leaves the device the moment
   it exists. Concealment runs beside the traffic and never carries a
   message, an acknowledgement, or anything else a delivery waits for;
   stopping it — in a test build, not as a setting — leaves delivery
   and the arrival of updates intact. This is testable and
   is the acceptance criterion for every change to the delivery layer
   (§3.1).

2. **One way to send.** There is no fast path and no private path to
   choose between. Any such choice would be set per side, and two sides
   set differently is the ordinary case — a guarantee that depends on
   both sides agreeing is not a guarantee (§3.3).

3. **Four ways, tried together.** Local segment, public address,
   through a neighbour, post box; a message takes three of them — the
   public address serves the own address and calls (§7.1). They run in parallel; the first
   acknowledgement wins. A slow way is overtaken, never waited for
   (§3.4).

4. **Nothing periodic in idle.** No published liveness, no polling, no
   scheduled maintenance traffic. Periodic traffic competes with delivery
   for the same socket and the same budget, and a queue that never empties
   throttles delivery permanently (§5.4).

5. **Sealed per message, with no session state.** Every message carries
   its own hybrid key encapsulation; there is no ratchet to desynchronise
   and no session to lose (§4).

6. **Coordinates are pairwise and minimal.** A node knows only what it
   has observed itself: the addresses in a contact's card and the address
   a packet actually arrived from. No third party is asked, and no third
   party stores the answer (§6).

7. **The invitation depends on nothing.** A contact card is built from
   the node's own keys and its local address. It is available at first
   start, on a device that has never reached another node (§12.4).

### 1.3 How a message is delivered

```
text
 │ compress
 │ seal          hybrid KEM, signature inside the seal      §4
 │ split         above 1200 B into numbered parts           §11
 ▼
 ladder, all steps at once, first acknowledgement wins      §7, §8
   1 LAN address (+ search call)         milliseconds
   2 public address, knocking if needed  seconds
   3 through a neighbour, max 3 hops     seconds
   4 post box at three neighbours        until the recipient returns
 ▼
recipient opens the seal, checks the signature, acknowledges §9.2
sender shows the double mark                                §12.2
```

**Requirement (normative).** A message must arrive within seconds as a
rule, and within 5 minutes in exceptional situations, at any number of
participants. The one named exception is iOS with the app closed, where
the delivery moment follows platform policy.

### 1.4 What this costs, honestly

| Cost | Where |
|---|---|
| Cover beside the traffic conceals volume, not its absence: individual packets are not separable, but a busy period raises the total an observer sees | §3.5, §5.2 |
| Where the empty cover packets are reduced (unmetered W/LAN only, §5.1), it is visible **when** somebody sends | §5.1 |
| A forwarding neighbour learns that two identifiers exchange packets, though not who they are or what they say | §8.1 |
| Where a contact is a fixed neighbour, that contact — not a stranger — learns when and how much the node sends and receives | §5.2 |
| Two users whose only neighbour is the same node reach each other through it, and it sees both ends (the last resort of step 3) | §8.1 |
| The post box reports "left with three, acknowledged by two" — not an arithmetic guarantee of placement | §8.2 |
| Beyond three forwarding hops a recipient is reachable only through the post box | §8.1 |
| Three copies in the post box cost three times the storage of one | §8.2 |
| A post box holds a packet for 7 days; after that it is gone | §8.2 |

None of these is a defect to be fixed later. They are the price of a
network that delivers, and they are stated here so that no
implementation has to discover them.

## 2. Threat model

**Design target — strong Jurisdictional State (D5).** The adversary has
border DPI, can compel ISPs, participates in Five-Eyes-style sharing,
and buys commercial aggregator data. Crucially, the adversary **sees the
egresses** (a sender planting, a recipient harvesting) but **not the
middle**: relays are peers that can sit outside the adversary's
jurisdiction. This jurisdictional gap is what thin cover exploits.

**Declared boundary — Global Passive Adversary (GPA).** A GPA sees the
full middle and global timing. Against a GPA, end-to-end timing
correlation engages and the required cover rate rises toward Nym scale.
The GPA is the *declared boundary, not the design target*. Content is
always safe; linkability degrades gracefully under GPA approach.

**What the state cannot do:**

- **Read** — PQ-E2E (§4). Out of scope for any network adversary.
- **Identify** — no packet names a person or a device: packets carry a
  code that changes per pair, direction and day (§8.1); the node that
  hands a packet on sees the node before and after it, never both ends;
  there is no directory (§8, §15).
- **Targeted-grind** toward a chosen victim — closed by the KEX-Gate
  (§4, §10): the harvest/liveness tag is `HKDF(K_AB, …)` and `K_AB` is
  the pairwise secret; a remote non-contact cannot compute it and does
  not know where the victim sits in the tag space.
- **Silently delete** — closed by mandatory E2E receipts plus m-family
  redundancy (§9).
- **Forge a receipt** — needs `K_AB`, which only the recipient has (§9).

**What the state can do (residual, bounded):**

- **Passive fleet coverage.** Run many relays and, by chance, observe a
  target's tags falling nearby. Modelled cost (M6): **25–40 % of all
  relays** for the 99 % coverage levels — operationally massive and
  visible as a coordinated fleet. **The coverage probability is
  target-independent** (§10.2): the same fleet covers every target at
  the same rate, so this is a network-wide availability attack, not a
  per-target price. What it still does not buy is **deanonymization**:
  an observed tag is not a person (§10.2).
- **Whitelist-total-filter.** Block the entire Cleona protocol at the
  border. This is a bounded edge (§10.4); it requires door-connect work
  and is outside the anonymity design.
- **Arrival timing, hop-exit observation, delay/drop its own copies.**
  None of these reveal content or identity (§10).

The architecture is designed against the strong state and is honest
about the GPA boundary (appendix B).

---

## 3. The delivery architecture

### 3.1 The rule everything follows from

> **Delivery works on its own. Concealment runs beside it and never
> carries anything a delivery depends on.**

A packet leaves the device the moment it exists. It is not queued behind
a timer, not scheduled into a slot, and not shaped by the cover stream.
The cover stream (§5) runs on its own clock and carries nothing a
delivery depends on. It always runs (§5.1). It may carry pieces of the
public update and address entries (§5.5); neither the update nor the
finding of neighbours depends on that.

This is a normative constraint on every future change, and it is
testable:

> Stop the cover stream in a test build. Every message still arrives
> unchanged, and a pending update still completes.

Any mechanism that makes delivery depend on concealment violates this
chapter, however desirable its other properties.

### 3.2 The four layers

| | Layer | Responsibility | Chapter |
|---|---|---|---|
| 1 | Wire | one UDP socket: packet out, packet in | §11 |
| 2 | Split | payloads above 1200 B into numbered parts; missing parts re-requested | §11 |
| 3 | Envelope | hybrid post-quantum seal, sender signature inside the seal | §4 |
| 4 | Ladder | four ways to reach the recipient, attempted together | §7, §8 |

Each layer is usable and testable without the layer above it. An
implementation that cannot exercise the wire without the envelope, or
the envelope without the ladder, is wired wrongly.

### 3.3 One way to send

There is one delivery path. The application does not choose between a
fast path and a private path, and neither does the user: any such choice
would be set per side, and two sides set differently is the ordinary
case, not the exception. Whatever concealment the design offers, it
offers on every message.

### 3.4 The ladder in one picture

```
message exists
   │
   ├── step 1  LAN address (+ search call)         ── milliseconds
   ├── step 2  public address (knocking if needed) ── seconds
   ├── step 3  via a neighbour that reaches them   ── seconds
   └── step 4  post box at three neighbours        ── until they return
        │
        first acknowledgement wins, the rest are cancelled
```

Steps are attempted **together**, staggered by a few milliseconds, never
one after the other. A slow step therefore costs nothing: it is
overtaken, not waited for.

### 3.5 What this design does not provide

Stated plainly so that no implementation is surprised by it:

| | |
|---|---|
| Traffic analysis | A cover stream running beside the traffic conceals less than one that carries it. Individual packets are not separable — cover is irregularly timed (§5.2) and indistinguishable in size, port and destination — but the *volume* is: an observer sees the sum of cover and traffic, and a busy period raises the total. |
| Timing | Without standing traffic it is visible **when** somebody sends, though not what or, beyond the first hop, to whom. |
| Placement guarantee | The post box reports "left with three, acknowledged by two". There is no arithmetic guarantee that a packet is held by a specific number of nodes. |
| Reach | Beyond three forwarding hops a recipient is reachable only through the post box. |

These are accepted properties, not defects. A network that transmits
nothing conceals nothing either.

### 3.6 Declared vocabulary

The delivery layer uses these nouns and no others:

**packet · part · address · neighbour · envelope · post box · code ·
card · identifier**

A design that needs a further noun is too complex, and the new noun is
the warning rather than the progress. This is normative: it bounds the
private vocabulary a delivery layer may accumulate, because terms whose
definitions drift apart cause measurement errors that look like protocol
errors.
## 4. Identity & Cryptography

Cleona identities are cryptographic key pairs — no email, phone
number, or central verification. The identity layer consists of:
Ed25519 + ML-DSA-65 (signature), X25519 + ML-KEM-768 (KEM), 24-word
seed, HD-wallet derivation for multi-identity, DB encryption.

Two identity classes are strictly separated: the **UserID** represents
a person (what the UI carries as a “contact"; a UserID can live on
multiple devices, a daemon can host multiple UserIDs), the **DeviceID**
represents one concrete daemon instance on one concrete device. Each
class has its own key pair, its own responsibilities, and its own
lifecycle (§4.4).

### 4.1 Identity Derivation (normative)

**Derivation.**

```
userId   = SHA-256(kIdentityDomain ‖ ed25519_user_pubkey ‖ mldsa65_user_pubkey)
deviceId = SHA-256(kIdentityDomain ‖ ed25519_device_pubkey)
```

The KEM keys are not part of the identifier: they rotate every 7 days
(§4.5.4), the identifier does not.

- `kIdentityDomain` is a **public**, network-channel-specific
  domain-separation constant (beta ≠ live — UserIDs differ between the
  network channels).
- It is **not a secret** and is never treated as one. A fail-closed
  test ensures that identity derivations compute exclusively against
  this domain constant.

**No backward compatibility for identity derivation.** `computeUserId`
and `computeDeviceNodeId` derive exclusively from `kIdentityDomain` as
shown above — never from `NetworkSecret.identitySecret` or any other
maintainer-key-derived secret. There is no transition window for
identity derivation and none is provided: the derivation takes the
break rather than carrying the maintainer key in its identities. The
fail-closed test above exists precisely to catch a regression that
reintroduces the secret, which would void the governance guarantee
under point 2 below.

**Rationale.**

1. **Underivability comes from the structure, not from the constant.**
   The property “whoever holds a pubkey cannot confirm the UserID" is
   delivered structurally: no pollable state and no pubkey-derivable
   search quantity exists for persons (the public object space from
   §16 is enumerable, but carries pseudonyms and objects, not
   identities).
2. **Governance.** Network access is not bound to any maintainer key.
   The maintainer key carries exclusively update signatures.

**Properties of the derivation:**

- **UserID as stable anchor.** The formula is the **founding**
  derivation, computed once at identity creation. The UserID hangs off
  the founding Ed25519 pubkey and does **not** change when the
  underlying keys change: after an Emergency Key Rotation,
  `userId ≠ SHA-256(kIdentityDomain ‖ current_pubkey)` holds —
  continuity is carried by the dual-signed old→new proof that contacts
  follow (§4.5.4, §14.5). The identifier survives device changes,
  recovery, multi-device, and every rotation.
- **DeviceID is daemon-global under multi-identity.** A daemon hosting
  N identities has exactly **one** DeviceID, computed from the
  daemon-global device-sig key pair (§4.4.2) and independent of every
  UserID.
- **Neither is persisted.** Neither `userId` nor `deviceId` is stored;
  both are recomputed on every identity load. A persisted copy could
  silently drift apart on a change to the derivation constant —
  recomputing makes any such change immediately and loudly visible.

### 4.2 Cryptographic Primitives

Cleona uses exclusively audited, established primitives. Two C
libraries via FFI carry all security; one further primitive exists
outside the security core:

| Library | Primitives | Use |
|---|---|---|
| **libsodium** (1.0.20+) | Ed25519, X25519, AES-256-GCM, XSalsa20-Poly1305, BLAKE2b, SHA-256, HMAC-SHA-256, HKDF | classical cryptography + file/DB encryption |
| **liboqs** (0.10+) | ML-KEM-768 (FIPS 203), ML-DSA-65 (FIPS 204) | post-quantum layer |
| **secp256k1 Schnorr** (BIP-340, `crypto/secp256k1_schnorr.dart`, pure Dart) | Schnorr signatures over secp256k1 | signing events on the public relay network (§11.9) only |

Rationale: libsodium has roughly twelve years of audit history; liboqs
is the NIST PQC reference implementation; ML-KEM-768 and ML-DSA-65 are
NIST level 3 (192-bit quantum security) and have been
FIPS-standardized since 2024 — they are not experimental.

The secp256k1 primitive exists only because the public relay network of
§11.9 accepts nothing else. It carries nothing but throwaway events on
the relays: the key is generated per published event and discarded.
Whatever a record asserts rests on the Ed25519 signature inside the
record, not on the relay signature. The implementation is a hand-written
BigInt curve and **not constant-time**; that is acceptable only because
no confidentiality or authenticity property depends on it.

**Deliberate exclusions:**

- **No RSA, no ECDSA.** Ed25519 is more modern, faster, and less
  side-channel-prone. secp256k1 appears only as BIP-340 Schnorr at the
  boundary of §11.9, never for identity, envelope or link.
- **No AES-CBC, no AES-CTR.** AES-256-GCM is AEAD, integrates the MAC,
  and is hardware-accelerated on every target platform (AES-NI,
  ARMv8-CE).
- **No Double Ratchet.** Avoids session-state complexity (desync, loss
  of forward secrecy on state corruption). §4.6 builds on this: an
  unordered, self-healing prekey pool instead of a chain. No chain
  state, no desync.
- **No TLS as a crypto layer.** The substantive statement is:
  **end-to-end encryption reaches from sender to receiver; link
  encryption always covers only one relay relationship.** Link-level
  confidentiality is carried by the link layer (an Elligator2-encoded
  X25519 handshake on the outside, an ML-KEM-768 exchange on the
  inside, link key = `KDF(kNetworkChannel ‖ x25519_ss ‖ mlkem_ss
  [‖ static_ss])`). It is not an exception to sealing, but an
  additional shell underneath it. The optional fourth term is the
  **caller authentication** (§11): it is present exactly
  when the callee already held the caller's entry record. Its presence
  changes the length of the KDF input, so an authenticated and an
  anonymous handshake can never produce the same key.

**Elligator2 sourcing.** The link handshake needs the **uniform encoding
of an existing X25519 public key**. libsodium's API does not deliver
this direction; the only thing available there is the **forward**
mapping `crypto_core_ed25519_from_uniform` (uniform bytes → curve
point), which in Cleona feeds the ring signatures
(`lib/core/crypto/linkable_ring_signature.dart`). **Sourcing: the
`native/cleona_link` C shim** (vendored Monocypher 4.0.3) provides the
reverse direction. This shim is the **cover-cell substrate** reused by
the delivery layer described in Chapters 7 and 8 — built once, shared
across every delivery stage.
The implementation is a review item (optional external crypto review,
§28). O-2 (Kemeleon / uniform ML-KEM encoding) is unaffected and is a
later optimization.

### 4.3 Per-Message KEM (X25519 + ML-KEM-768, hybrid)

The per-message KEM is the core of content encryption: every message
carries its own ephemeral key setup — no session state, no desync
risk. The PQ component runs on its own cadence.

**The combiner.** The sender generates an ephemeral X25519 key pair
and encapsulates against the receiver's public keys:

```
x25519_shared = X25519(eph_sk, empfänger_x25519_pk)
mlkem_shared  = ML-KEM-768-Encaps(empfänger_mlkem_pk)
combined      = HKDF-SHA-256(x25519_shared ‖ mlkem_shared, salt, info)
aead_ct       = AES-256-GCM(combined, nonce, plaintext)
```

The receiver decapsulates both halves with its private keys,
reconstructs `combined`, and decrypts. The attacker must break
**both** half-steps simultaneously. If X25519 falls to a CRQC,
ML-KEM-768 holds; if ML-KEM-768 falls to an implementation or
analysis flaw, X25519 holds. There is no classical-only decryption
mode — neither a sender nor an on-path attacker can force a PQ
downgrade.

**Domain separation (Sec H-5 v2):**

```
salt = SHA-256("cleona-per-message-kem/salt/v2")
info = "cleona-msg-v2"
```

**Implementation.** A full ML-KEM ciphertext (1,088 B) does not fit a
cell — a placement carries 1,043 B of content, so not even an empty
message would pass. The envelope of §3.2 implements the
cadence above: the capsule is formed once per day and contact, and only
the 32-byte X25519 ephemeral rides in the cell. Media does not go
through this per-message capsule at all: the media lanes of §9.3 seal
their blocks under a **transfer key** instead.

The domain-separation constants (salt, version stamp, acceptance set)
live in `lib/core/crypto/per_message_kem.dart`. Normatively,
`kemSendVersion = 2` and `acceptKemVersions = {2}` hold.

**PQ cadence: one ML-KEM capsule per day and contact (normative).**

```
Once per day and per contact: ss_pq = ML-KEM-Encaps(receiver's daily prekey)
Per message:                  dh    = X25519(eph_sk, receiver's one-time prekey)
                               mk    = KDF(ss_pq ‖ dh)
```

On the wire, only the X25519 ephemeral (32 B) rides in the cell — **once
the peer has been shown to hold the day's capsule.** The prekey
construction, its fallback ladder, and the resulting FS granularity are
described in full in §4.6.

**The capsule rides along until it is acknowledged (normative).**
"Once per day and per contact" is a statement about
*forming* the capsule, not about transmitting it. Delivery is unordered:
a cell can arrive directly off the wire or be harvested later out of
storage, and nothing guarantees that cells for a contact arrive in send
order (Chapters 7/8). If the capsule-bearing cell is the one
that is lost — or a later cell arrives first — the receiver lacks the
day's secret and **every further message that day is unopenable**, the
very class §4.6 rules out ("silent message loss").

The capsule therefore rides along with every message until a message from
the peer *on the same day* has been opened; that is the proof they hold
it. The price belongs in this paragraph rather than in a comment: until
the first reply, each message carries **1,088 B extra** and splits into
two cells rather than one. It is paid only where nobody answers.

**The pair secret `K_AB` (normative).**

```
dh_AB  = X25519(ed25519_to_x25519(founding_sk_A), ed25519_to_x25519(founding_pk_B))
K_AB   = HKDF-SHA-256(dh_AB ‖ s_AB, salt = SHA-256("cleona-pair/v1"),
                      info = sort(founding_pk_A, founding_pk_B))
```

`s_AB` is 32 random bytes the accepting side creates at first contact and
returns sealed in its bundle (§15.5); both sides store it with the
contact. `dh_AB` binds the secret to the founding keys, `s_AB` keeps it
safe against a future quantum attacker who holds both public keys from
cards. A contact forms `K_AB` alone and hands `s_AB` back during a
restore (§13.5). The founding key is the identity's Ed25519 key; a change
of the signing keys (emergency rotation) starts a new pair, as it starts a
new identifier (§4.1).

**Codes.** `code(A→B, d) = first 16 B of HKDF(K_AB, "code" ‖ pk_A ‖ pk_B ‖ d)`,
`d` = UTC day. A code names neither side and changes every day; two codes
of the same pair on different days cannot be linked without `K_AB`.

**Wire format: no KEM header.** Packets handed on through neighbours
(step 3) carry the code above in front of the sealed payload (§8.1);
packets left in a post box carry the recipient's day value (§8.2).
Packets sent to the recipient's own address (step 1) carry neither. The
ephemeral always sits inside the sealed part.
The prekey selection is **not** a free choice per implementation and
does not depend on the delivery stage: a 4 B pseudorandom selector
`SHA-256(pk_n ‖ eph_pk)` sits at the head of the sealed part regardless
of stage (§4.6 item 2). The wire format carries no PoW field
(`tag ‖ ttl ‖ pow ‖ sealed_payload`): proof-of-work does not defend
against a state-level adversary, and the censorship lever is
redundancy m=3, not proof-of-work (§9).
Version negotiation runs inside the sealed frame.

**Exactly one exception.** The only thing excluded from the
per-message KEM is **Plane D frames**, which are protected under
`call_key` via AES-GCM (§17.1). The link layer is **not** a second
exception: it sits underneath the sealing, not alongside it.

**Error behavior without a return channel.** A cell that cannot be
unsealed is **silently discarded**. No reverse direction results from
this: the sender cannot be addressed from a discarded cell.

**Deterministic PQ key generation.** After device loss, the
replacement device regenerates exactly the same user KEM pair from
the recovery phrase. The basis for this is deterministic key
generation in the PQ layer:

- `OqsFFI.mlDsaKeypairDerand()` — `lib/core/crypto/oqs_ffi.dart:548`
- `OqsFFI.mlKemKeypairDerand()` — `lib/core/crypto/oqs_ffi.dart:372`
- Caller: `HdWallet.deriveMlDsa()` / `HdWallet.deriveMlKem()` —
  `lib/core/crypto/hd_wallet.dart:42-67`, each with a 64-B seed from
  `hkdfSha256(masterSeed, info: "cleona-mldsa-$index" or "cleona-mlkem-$index")`

Both `_derand` functions inject a seed-fed DRBG into liboqs and then
restore the system randomness source; the same seed produces the same
key pair byte for byte.

**Scope of the determinism (normative).** The determinism commitment
applies to the **founding keys**, not to rotated KEM keys.
`IdentityContext.rotateKemKeys()` generates the new pair **randomly**,
not from the seed:

```dart
// lib/core/identity/identity_context.dart (rotateKemKeys)
final newX25519 = sodium.generateX25519KeyPair();      // random
...
final newKem = await generateMlKemIsolated();          // random
```

Consequence: from the first routine rotation onward, the **current**
KEM pair is not reproducible from the phrase. A plain seed restore
recovers the founding keys; ciphertext against a rotated pair cannot
be opened without the recovery bundle (§13). Stages 1 and 2 of the FS
ladder (§4.6) use self-erasing keys anyway. The commitment therefore
reads: **“the seed recovers the identity, not the message history"**
(history: §13).

> **Decided.** Rotated KEM keys are **not** derived deterministically
> from the seed — that would turn the 24 words into an eternal master
> key (whoever copies them once could recompute every future rotated
> key) and would void exactly what the 7-day rotation and §4.6 are
> built against. The only thing left to follow up on is the honest UI
> statement in the restore flow (§13, user level): whoever has only the
> phrase gets the identity back, not the ciphertext against rotated
> keys.

**The trade-off is named.** The master seed is a durable root secret:
whoever has the 24 words regenerates the founding keys — and nobody
else does, since there is no other route back (§13.8). §4.6 works
precisely against that — and that is exactly why the prekey pool is
load-bearing (§4.6 motivation).

### 4.4 Signatures

#### 4.4.1 User-Sig Key Pair (Ed25519 + ML-DSA-65)

Every identity holds a hybrid user-sig key pair — Ed25519 for
performance and long audit history, ML-DSA-65 for post-quantum
security. Sizes:

| Component | Size |
|---|---|
| Ed25519 public key | 32 B |
| Ed25519 signature | 64 B |
| ML-DSA-65 public key | 1,952 B |
| ML-DSA-65 signature | ~3,300 B |

**Hybrid verification:** the receiver checks both signatures
individually; acceptance requires that **both** are valid. The
combined signature is therefore never weaker than the stronger of the
two.

**Responsibilities of the user-sig pair:**

- It signs **identity statements** — profile updates, identity
  deletion, restore — as message content (§15.7, §13).
- Messages carry **no** signature, neither in 1:1 nor in groups (the
  tag `HKDF(K_AB, …)` authenticates the sender symmetrically and thus
  post-quantum-securely; non-repudiation is deliberately given up —
  deniability).
- Which remaining artifacts are signed hybrid, classically, or not at
  all is governed by the signature rule in §4.4.3.

#### 4.4.2 Device-Sig Key Pair

Authenticity exists exclusively inside the sealing. The device key pair
carries exactly three responsibilities:

| Responsibility of the device-sig key | Where |
|---|---|
| Carries the `DeviceDelegationCert` — travels with the cell, on first contact per device | §14.5 |
| Countersigns device revocation and co-authorization quorums | §14.4/§14.5 |
| Twin-sync attribution (“which of my devices") | §14.1 |

The reason for separating from the user keys is load-bearing and
sharp: a compromised device should be handleable without a user
re-setup — the device-sig key is disposable, the user-sig key is not.
The procedure for this is in §14.4 (shared-key rotation on lock-out)
and §14.5 (quorum).

**Generation:** device keys are generated **locally with
cryptographic randomness** and are **not** derived from the master
seed. The reason: a seed compromise must not retroactively compromise
older devices — neither for signatures (appearing as the device) nor
for KEM material addressed to the device. The `m/device` branch is the
documented exception to HD-wallet determinism (§4.5.1). For linked
devices, the HKDF-derived sig subkey plus delegation certificate is
added (§14, LD-1…LD-12).

#### 4.4.3 Signature rule (normative)

| Artifact | Signature | Why |
|---|---|---|
| 1:1 message | **none** | The tag `HKDF(K_AB, …)` authenticates the sender symmetrically and thus post-quantum-securely; non-repudiation is deliberately given up (deniability) |
| Group leg (pairwise) | **none** | identical to 1:1 — groups are N ordinary 1:1 deliveries (E-22) |
| Post in a large private channel (`K_C`, N > 16, §16.2.1) | **Ed25519** (64 B) | sender attribution among N receivers who all know `K_C` |
| Public object space (§16: registrations, directory entries, cases, verdicts, tombstones) | **Ed25519** | the vote is an Ed25519 ring signature, the pseudonym key **must** be an Ed25519 curve point; a hybrid outer shell would secure a door next to a missing wall and would cost a factor of ~17 in storage |
| `DeviceDelegationCert` (§14) | **hybrid** (Ed25519 + ML-DSA-65) | must be verifiable by third parties years later |
| Key continuity proof / rotation announcement (§4.5.4, §15) | **hybrid** | ditto |
| Update manifest (maintainer key) | **hybrid** | ditto |
| Plane D frames (§17.1) | **none** | AEAD under `call_key` carries per-frame authenticity |
| Link handshake | **none** | authenticity from the hybrid link key — for the **callee** always (only the holder of the static secrets can complete it), for the **caller** whenever the callee held its entry record: the static-static X25519 term enters the link key, so a caller that only *claims* a position derives a different key and can open nothing (§11). Implicit, therefore still no signature |

**Two declarations that belong to this rule and must not disappear
into a footnote:**

1. **Cleona is deniable.** Without a signature in the message path, no
   receiver can prove to a third party that a specific person said
   something. That is a gain, but it shapes the security promise — it
   belongs in the threat model (§2) and in user communication.

   **Implementation note — read this before adding a signature "just to
   be safe".** The harvest **knows** the sender from the tag, and that
   knowledge must reach the application rather than being discarded: the
   correct construction carries the tag-derived sender through to the
   application and checks the asserted `senderUserId` inside the frame
   against it, not a signature. Whoever finds an unsigned frame path
   here and is tempted: the symmetric tag *is* the authentication this
   section relies on.
2. **The public object space is classically secured.** This is a
   deliberate trade-off from the moderation ballot-secrecy-via-ring-
   signature decision and not a consequence of the signature choice:
   ballot secrecy and PQ security are mutually exclusive with today's
   building blocks.

**Reviewed and rejected variant: content-selective signing.** The
question of whether non-repudiation could be preserved for “normal"
messages and switched off only for incriminating content classes
(namely CSAM) has been reviewed and **answered no**. Three independent
reasons: (1) the protocol cannot classify content — `sealed_payload` is
random to every intermediate node, so the rule degenerates to
“signature optional, sender's choice" and binds exclusively the users
who have nothing to hide; (2) deniability is a property of the
population, not a per-message flag — it holds only as long as no one
can produce a signature, and if signing is the norm its absence itself
becomes an accusation; (3) the cost reduction would collapse.
Moreover, the variant misses its own target: every surface where third
parties must attribute is **already** signed. Unsigned is only the path
that no third party ever sees.

### 4.5 Key Derivation, Storage, and Rotation

#### 4.5.1 HD-Wallet Derivation and Multi-Identity

**All** of a user's user identities sit on **one** 32-B master seed —
one passphrase carries N identities, each at its own `identity_index`
with its own key set and its own UserID (§4.1). **All** user keys —
classical and post-quantum — are derived from it deterministically; the
device keys are the documented exception (§4.4.2).

**One daemon, one port, all identities at once.** Every identity a device
holds is active at the same time in one process and uses the device's one
data port (§11.1); switching the displayed identity changes nothing on the
network (Appendix D, D-19).

**Seed derivation (normative).** The master seed is produced from the
entropy of the recovery phrase by **one** SHA-256 round under a domain
constant:

```dart
// lib/core/crypto/seed_phrase.dart
static Uint8List entropyToSeed(Uint8List entropy) {
  final input = Uint8List.fromList([
    ...'cleona-master-seed-v1'.codeUnits,
    ...entropy,
  ]);
  return sodium.sha256(input);          // one SHA-256 round, no PBKDF2
}
```

The word list is a **custom** list of 2,048 phonetically
distinguishable words; 24 × 11 bit = 264 bit = 256 bit of entropy + 8
bit checksum (`lib/core/crypto/seed_phrase.dart`). A key-stretching
function is **deliberately not used** — adding one would be a format
break of the phrase. **Security assessment:** the entropy sits at 256 bit;
stretching protects against dictionary attacks on *user-chosen*
passphrases, not against attacks on a randomly generated 256-bit
phrase. The omission is therefore defensible — and it is explicitly
documented, not silently made.

**Derivation scheme:**

```
master_seed (32 B) = SHA-256("cleona-master-seed-v1" ‖ entropy_32B)
├── m/identity/0                        → user identity 1
│   ├── hkdf(info="cleona-ed25519-0")   → Ed25519 (sig)              [hd_wallet.dart:13-28]
│   ├── (converted from Ed25519)        → X25519 (KEM receive)       [hd_wallet.dart:30-39]
│   ├── hkdf(info="cleona-mldsa-0", 64) → ML-DSA-65   via _derand    [hd_wallet.dart:42-53]
│   ├── hkdf(info="cleona-mlkem-0", 64) → ML-KEM-768  via _derand    [hd_wallet.dart:56-67]
│   ├── deriveFileEncKey(master_seed, hd_index) → file key, identity [hd_wallet.dart:219]
│   ├── deriveSharedFileEncKey(master_seed)     → file key, device   [hd_wallet.dart:231]
│   ├── hkdf(info="cleona-file-enc-0")  → FileEncryption key         [hd_wallet.dart:120-127]
│   └── invite_root  = HKDF(master_line, "invite-root" ‖ 0 ‖ g_inv)  → invitation line (§15.3.1)
├── m/identity/1 … m/identity/N         → further identities, same scheme
├── hkdf(info="cleona-shared-file-enc-v1") → daemon-wide file key    [hd_wallet.dart:131-138]
└── m/device                            → NOT seed-derived, generated locally (§4.4.2)
```

**Not seed-derived:** the **shared key** of the device set (§14.4). It
is **random**, is re-rolled on every change to the device set, and is
wrapped individually for each remaining device. This is deliberate and
load-bearing: precisely because it is not derivable, neither
computation time nor prior knowledge helps a locked-out device (§14.4,
“the exclusion is structural, not rule-based"). `inbox_key =
HKDF(shared_key(n), "inbox")` follows from it — the address of the
inbox, not the identity.

**Invariant.** An identity with `hdIndex` set MUST have derived all
keys deterministically at that index position. An identity with
`hdIndex` and random keys is forbidden (`_preGenerateKeys()` throws
`StateError`) — otherwise the user believes the identity is
seed-recoverable, and a restore would produce different keys.

**Multi-identity is a user-layer property.** A daemon with N
identities has exactly **one** DeviceID (§4.1). Since the DeviceID
addresses nothing (§14.1), there is no way to infer the number of
hosted identities from network behavior — the liveness/cover traffic
of all identities blends into one stream, diluted by decoys.

**Identity discovery on restore.** A seed restore on a fresh device
must recognize at which indices the user's identities sit. Every
identity is derivable from the phrase; a **marker per identity** serves
as the stop criterion while deriving, and the recovery bundle carries
the identity indices along with their names explicitly (§13.3.2). A
network lookup is not needed for this (§13.7).

#### 4.5.2 Key Storage on the Device

**Profile layout:**

```
~/.cleona/                     (Linux)   %APPDATA%/Cleona/   (Windows)
files/.cleona/                 (Android, app-private)

  master_seed.enc                        # keyring-encrypted
  device_keys.enc                        # device sig + device KEM
  node_keys.enc                          # L_node + E_node + static node KEM
                                         #   node-level, identity-free,
                                         #   must survive restart
  identities/
    0/
      identity_meta.json.enc             # display name, picture, settings
      conversations.json.enc             # conversations and messages (§4.5.3)
      contacts.json.enc                  # contacts (§4.5.3)
      groups.json.enc  channels.json.enc # groups, channels (§4.5.3)
      v41_entries.json  v41_ages.json    # entry store, peer ages (§11.1)
      session_state.json.enc             # tag counter states per (pair, direction, epoch),
                                         #   expectation window, prekey-pool state (§4.6),
                                         #   shared-key wraps and transition window (§14.4),
                                         #   liveness cache + last-harvest bookkeeping (§6)
  relay_cache.json.enc                   # cached responsible-relay/liveness addresses (§6)
```

**Key cascade:**

1. The **OS keyring** protects `master_seed.enc` and `device_keys.enc`
   — libsecret (Linux), DPAPI with round-trip probe (Windows),
   AndroidKeyStore with a biometric/device-code gate, Keychain
   (macOS). Without an available keyring, the file-based fallback
   kicks in (XSalsa20-Poly1305, key from `SHA-256(hostname + salt)`,
   v2). The master seed and seed phrase are written twice, as
   defense-in-depth against keyring loss (keyring + file).
2. After daemon start, the **master seed** sits in RAM protected by
   `sodium_mlock`.
3. The **HD-wallet derivation** (§4.5.1) generates everything else on
   demand.
4. The **message-store key** is `deriveFileEncKey(master_seed,
   hd_index)` — the same identity-bound key as every other
   identity-bound artefact, never persisted, regenerable from the
   phrase (§4.5.3, §21.4.1). The older `HdWallet.deriveDbKey` was
   removed on 2026-09-09; see the note in §4.5.3.
5. **FileEncryption uses two keys, and the distinction is normative:**
   `deriveFileEncKey(master_seed, hd_index)` for identity-bound files
   and `deriveSharedFileEncKey(master_seed)` for state shared across
   identities on one device (§4.5.3). Neither is ever persisted.

**Fail-loud is normative.** `DeviceKeysStore.loadOrCreate()` and
`loadMasterSeed()` **never** silently regenerate new keys when
encrypted material sits on disk but cannot be decrypted. The same
holds for `FileEncryption._loadOrCreateLegacyKey()` on a `db.key` of
the wrong length. The only exception is a 0-byte `db.key` with no
profile data whatsoever (an aborted first write). The reason: silent
regeneration is identity loss followed by unreadable files.

**Memory hygiene:** `sodium_mlock` against swapping; active
overwriting of private keys and every KEM intermediate value
(DH-shared, KEM-shared, IKM, message key) via `sodium_memzero` /
`fillRange(0)`; `SecureMemory` / `SecureKeyHolder`
(`secure_memory.dart`); constant-time comparison on
security-critical paths (`constant_time.dart`). Public keys sit on the
normal heap.

**Profile watchdog:** the daemon's 30-second watchdog also checks
whether critical profile files still exist and writes them back from
RAM. It protects against external deletion, not against attackers.

#### 4.5.3 Encryption at rest

**Three forms, and the distinction is normative.**

1. **Messages, conversations and their indices** live in an **encrypted
   SQLite database, one per identity** (SQLite3 Multiple Ciphers,
   ChaCha20-Poly1305). Encryption covers the database file **and its
   journals**; no plaintext temporary file is produced at any point
   (`SQLITE_TEMP_STORE=3`, compiled in, not set at runtime). Details in
   §21.4.1.
2. **Structured configuration state** stays in individually encrypted
   JSON files per identity (`FileEncryption`), compressed as described
   below. At least six files can never move into a database, because
   they hold what is needed to open one: `master_seed.json`,
   `seed_phrase.json`, `identities.json`, `db.key`, and the two
   corresponding write paths.
3. **Media attachments** are stored as `<name>.cmenc` under a framed,
   streamed AEAD (`lib/core/crypto/media_cipher.dart`) and read through
   a decrypting reader on `127.0.0.1`
   (`lib/core/media/media_vault.dart`), because media are read by path
   and `FileEncryption` would hold six times the file size in memory
   (`media_cipher.dart:20-25`, measured compiled).

**The design in `docs/CRYPTO.md` remains rejected.** It placed SQLite on
a decrypted temporary file with an encrypted flush every 60 seconds —
that is the entire store in plaintext on disk (found in the field at
mode `0644`) plus a 60-second loss window against zero today. The build
chosen here has neither property, and that is why it was chosen.

**For form 2 the following applies:**

- **Algorithm:** XSalsa20-Poly1305 (`crypto_secretbox`), 192-bit nonce
  per write, 256-bit key, AEAD.
- **Compression:** the plaintext is compressed with **zstd level 3**
  before sealing, then encrypted. Level 3 is the measured optimum: level
  9 costs 12.3 ms per MB for 4 % more, level 19 costs 423.6 ms for 7 %
  more and is therefore excluded; level 3 costs **3.3 ms per MB** and is
  more than repaid by the smaller AEAD and write that follow it — the
  full cycle is **faster than before at every measured size** (x 0.81 to
  x 0.97) at **24 % of the disk footprint**.
- **Detection on read, without a format version.** The first byte of the
  **decrypted** content decides: JSON always begins with `{` (`0x7B`), a
  zstd frame always with the magic `28 B5 2F FD`. The two are disjoint.
  A reader tests one byte and decompresses or does not; files written by
  an earlier build stay readable and migrate on their next write. There
  is no format version byte, no cut-off date, no dual storage.
- **What is not compressed, and how that is decided.** Content that is
  already compressed gains nothing and costs time. The decision is
  **measured, not guessed from a file extension**: the writer compresses
  the first 128 KiB, and if the result is not at least **10 % smaller**,
  the payload is stored uncompressed. Measured rationale: chat text
  compresses **4.25x**, whereas signature- and key-dominated records
  reach **1.42x** and base64 exactly **1.33x** — that is the base64
  inflation of 4/3 coming back and nothing else, because a signature is
  indistinguishable from random or it would not be one. A threshold of
  1.1 separates these cases cleanly, and the probe costs at most 0.4 ms.
  An extension list would have to be maintained, would age in the
  harmful direction, and would say nothing about content whose type is
  unknown.
- **Binary payloads stay uncompressed.** `writeBinaryFile` /
  `readBinaryFile` carry fixed-shape artefacts — key material above all
  (`device_keys.bin.enc`, 6 096 B). Key material is indistinguishable
  from random and does not compress; and unlike the JSON path, its
  plaintext has no fixed first byte that could carry the detection. The
  binary path therefore keeps the format `[24-byte nonce][ciphertext]`
  unchanged.
- **Atomicity:** the write goes to `<name>.enc.tmp` and is then
  renamed, so an interrupted write cannot leave a torn file
  (`lib/core/crypto/file_encryption.dart`).
- **Keys — two, and the distinction is normative.** Identity-bound data
  uses `deriveFileEncKey(master_seed, hd_index)`
  (`lib/core/crypto/hd_wallet.dart:219`); state shared across
  identities on one device uses `deriveSharedFileEncKey(master_seed)`
  (`:231`). Both are deterministically derivable from the seed, never
  persisted directly, and regenerable via the phrase.
- **Note:** `HdWallet.deriveDbKey` computed
  `SHA-256(ed25519_user_sk ‖ "cleona-db-key-v1")`. It was **never** the
  key of the message store in form 1 — that store is opened with
  `deriveFileEncKey(master_seed, hd_index)` like every other
  identity-bound artefact (§21.4). It was **removed on 2026-09-09**: it
  had no caller in `lib/`, and the only two tests that kept it alive
  merely asserted that its formula was still its formula. The note
  stays so that the name does not return.

**Not encrypted with the identity key:**

- `relay_cache.json.enc` — FileEncryption instead of DB encryption,
  because the file belongs to shared, cross-identity state (liveness
  addresses are device-global under multi-identity).
- Log files — unencrypted, because they are debug output. The logger
  redacts display names (own, contacts, groups, channels), the host name,
  private IP addresses and the home directory path, replacing each with a
  keyed pseudonym drawn fresh at every process start. It does **not**
  redact the user ID, device identifiers, ports, timestamps or stack
  traces. **A log is therefore not anonymous** — it still binds to an
  identity through the user ID. That is the basis on which these files are
  left unencrypted, not an assumption that they are harmless.

**The local relay/cache holdings.** A node acting as a responsible
relay (holding mailbox placements for others, delivery stage 4,
Chapter 8) holds foreign cover cells and liveness records locally.
These are already ciphertext, so a second shell does not protect their
content. What needs protecting is the **cache index**: which tags this
node holds and which of them are inbox vs. decoy harvests — that list
narrows the contact circle. Normatively: **FileEncryption over the
cache index, raw cells remain unwrapped.** A forensic access thus
sees only indistinguishable heaps of cells. **Key assignment:** the
relay holdings are **device-bound, not identity-bound** (one daemon, N
identities, one shared relay stream). The index key is derived from
the device-sig key —
`SHA-256(device_ed25519_sk[0:32] ‖ "cleona-relay-index-v1")`, analogous
to the DB-key derivation — and not from the identity-bound DB key. The
identity-bound quantities (expectation set, `inbox_key`, prekey pool,
own outbox) sit under the DB key (§21.4).

#### 4.5.4 Key Rotation

**There are four clearly separated rotation types:**

| Type | What rotates | Trigger | Effect |
|---|---|---|---|
| **Node-key rotation** | `L_node` **together with** `E_node`, the static X25519 and the static ML-KEM-768 of the *node* (`node_keys.dart`, `rotate()`) | explicit, E-81 | new metric position (§9.1). Rotating `L_node` alone would make the rotation pointless — anyone collecting entry records would link the old and the new position by the identical remaining static keys, so all four keys rotate together. The **previous static set is retained for the 30-day overlap** and the responder tries it on flight 1, because a peer holding a pre-rotation entry record dials the old keys — without that the overlap would cover the MAC and fail at decapsulation |
| **Routine KEM rotation** | X25519 + ML-KEM-768 of the identity | every **7 days** (`kKemRotationInterval`, `kem_generation.dart`; decided by `IdentityContext.needsRotation()`, checked at startup and every 6 h) | stage 3 of the FS ladder (§4.6) — kicks in only on total exhaustion of the prekey pool |
| **Shared-key rotation** | the device set's everyday key, and from it `inbox_key`; on **lock-out**, additionally the user KEM key **and the identity sig keys** | every change to the device set, plus routine hygiene | §14.4 |
| **Emergency Key Rotation** | **all** user keys (Ed25519, ML-DSA, X25519, ML-KEM) under the same UserID | suspected compromise | §14.5, continuity proof + device quorum |

**Routine KEM rotation — retention of the previous keys.** The
previous private KEM keys are retained after rotation
(`previousX25519Sk`, `previousMlKemSk`); the receiver first attempts
unsealing with the current keys and, **if that yields nothing, with the
previous ones — both as a selector candidate and as a capsule key**, so
that senders who have not yet harvested the announcement keep getting
through. The fallback must **not** hang off `kemDecapFailed`: when
X25519 and ML-KEM rotate together, the **selector** fails first and the
capsule is never opened, so that event never occurs. Both break points
are separate and both are handled. `discardPreviousKeysIfExpired()`
deletes them once the deadline expires.

*Deadline (normative):* the retention deadline for the previous KEM keys
is the **rotation interval itself — 7 days** (32 days for the 31-day TTL
class). Exactly **one** previous generation is retained, which is what
`previousX25519Sk` / `previousMlKemSk` hold.

**The trade named, and the price named rather than hidden.** A retention
of 15 days would not fit together with the 7-day rotation interval and a
single retained previous slot: on day 14, generations N, N−1 **and**
N−2 would all have to be present at once. Keeping the retention window
at 7 days — no longer than the rotation interval itself — is what makes
one retained generation sufficient, rather than lengthening the
rotation interval or keeping a second generation on every device.

**What that costs, explicitly.** Retention no longer outlasts the full
delivery window. A cell sealed against the previous key and harvested
more than 7 days later can no longer be opened, and the loss is silent —
the receiver counts `unopened` and reports nothing (§4.3). That is the
class of error §4.6 rules out for prekeys; here it is accepted, because
the alternatives cost either a second retained generation on every device
or half the rotation frequency, and the exposure window that rotation buys
matters more than the tail of a 7-day-old undelivered cell. Anyone
reopening this decision reopens it against that trade, not against an
oversight.

*Announcement and its mode:* the rotation is announced **pairwise** as
an ordinary delivery under `tag(K_AB, …)`; there is no broadcast. This
is not a cost-saving measure but mandatory: a public object would be
third-party state about a person and would make an identity's inbox
attributable network-wide (§14.4). **The announcement must carry the
mode** the sender should use for follow-ups: a rotation notice
specifies whether the recipient's liveness/secure tags are still
valid for the new keys, so a contact does not re-derive a stale path.
`K_AB` survives every rotation (it is derived from the **founding**
keys, §4.3, §15.2), so the tag families are unaffected; what rotates is
the KEM material the sealed payload is encrypted against.

**Emergency Key Rotation.** The UserID is a stable anchor (§4.1);
continuity is carried by a **dual-signed old→new proof** that the
previous key pair lays over `newEd25519Pk ‖ newMlDsaPk`
(`identity_context.dart` `rotateIdentityFull()`,
`rotationChain.add(StoredRotationLink(…))`). The chain is signed
hybrid (§4.4.3, a long-lived verifiable artifact). In addition:

- **Distribution:** as a delivery of the 31-day TTL class, pairwise
  to contacts, via twin sync to one's own devices. It goes through the
  **mailbox (delivery stage 4)** by default (a rotation notice is not
  latency-critical and should not be session-linkable); a direct or
  relayed leg (stages 1–3) is permitted when the recipient is known
  live and the sender accepts the linkability.
- **Authorization (normative, closes security finding SR-1):** a
  rotation is valid only with the signature of the previous key pair
  **and** the **device quorum** `max(2, ⌈N/2⌉)` of countersignatures
  (§14.5) **and** a device-set shrink proof. The signature alone does
  not authorize — otherwise possession of the seed would be enough to
  rotate.
- **`K_AB` survives every rotation**, because it is derived from the
  **founding** keys (§4.3, §15.2). Contacts who missed the announcement
  lose the encryption, but not addressability — they can keep computing
  tags and get the announcement on the next harvest.

**Contact verification and key-change detection.** Four levels per
contact:

| Level | Meaning | Display |
|---|---|---|
| `unverified` | contact exists, key authenticity never checked | default avatar, no badge |
| `seen` | key material used successfully at least once | weak badge |
| `verified` | camera scan with the other person present, or an NFC touch (§15.10) | green badge |
| `trusted` | explicitly marked as trustworthy by the user | double badge |

Verification is attached to the **UserID** and survives device
changes. For `verified` and `trusted`,
`verifiedKeyFingerprint = SHA-256(ed25519_user_pk)` is stored; if the
received public key deviates from it, the key-change warning appears
and the level falls back to `unverified` until the user actively
re-verifies. **This explicitly holds even for a valid Emergency
Rotation:** a correct chain proves that *someone with the old key*
rotated, not that it was the rightful owner. The device quorum is a
second piece of evidence (§14.5), but it does not replace the user's
decision.

**Four deliveries can overwrite a stored public key:** restore response
(§13), rotation announcement (above), contact request, and contact
response (§15.4). The same rule applies to all four: **every path that
overwrites a stored public key must trigger the check.**

### 4.6 Forward Secrecy: One-Time Prekey Pool

**Motivation.** Full per-message forward secrecy is unreachable under
asynchronous delivery, and the threat model differs by delivery stage
(Chapters 7/8):

- **Mailbox placements (stage 4)** replicate ciphertext across the
  relays responsible for the recipient's tag (§7, §8). An attacker who
  runs or compromises those relays can archive what they hold; the
  KEX-Gate (§10) is what makes finding the right relays hard — without
  `K_AB`, the attacker cannot tell which relays hold a given target's
  cells. So the threat is real but gated.
- **Direct and relayed placements (stages 1–3)** are not publicly
  replicated (§7). There is no persistent public copy to archive; a
  passive archiver must sit on the forwarding path itself, which the
  sender chooses per message from liveness. This threat is therefore
  *on-path relay compromise*, not bulk archival.

The **physical lower bound is unchanged regardless of delivery stage:**
full per-message FS is unreachable under asynchronous delivery. A key
that opens a TTL-old, still-unharvested cell also opens it on a seized
device. FS granularity is bounded from below by the offline delivery
window — that holds for every store-and-forward system, and for every
delivery stage (mailbox via the replicated relays, direct/relayed via
S&F/erasure when the recipient is offline and the sender's leg could
not be placed).

**Assurance.** A seized device plus a fully archived relay holding may
only expose the cells **not yet delivered**, not the traffic of the
rotation window. The upper bound is **15 days** (32 days for the
31-day administrative TTL class) and covers exclusively undelivered
material — typically nothing, for an active conversation. It is the
deliberately paid price for the delivery window.

**Construction.** One pool of one-time **X25519** key pairs per contact.
The PQ half is deliberately *not* part of the pool: it is a single daily
ML-KEM prekey per identity (§4.3).

**Why X25519-only, not hybrid.** The reason is arithmetic, not thrift:
an ML-KEM-768 public key measures 1,184 B, a cell carries 1,043 B. A
hybrid prekey does not fit **singly** into a refill, a batch of 16
measures 19.5 KB. A hybrid pool would cost **~18x** the per-message
bandwidth (1,152 B instead of 64 B), **34x** per refill and **78x** the
storage (7.8 MB instead of 100 KB at 200 contacts) — and it would void
the receiver-side optimisation of §4.3, under which one decapsulation
per cell suffices regardless of contact count:

1. The receiver publishes the public parts as a refill delivery under
   `HKDF(K_AB, "prekey-refill", …)` as soon as **fewer than B/2 (= 8)
   unused indices** remain for the sender in the provisioned range
   — the counter progress `n` is visible on harvest, consumption is
   counted pool-wide (multi-device: `PREKEY_CONSUMED`, §14.3); the
   batch covers the next counter range. No directory, no publication to
   third parties.
2. The sender seals every cell against exactly one unused prekey, and the
   receiver must be able to **name** that prekey without trial-unsealing
   the whole batch. **The selector is the same in both modes, and it
   carries no counter:**

   `sel = SHA-256(pk_n ‖ eph_pk)` truncated to **4 B**, at the head of the
   sealed payload, bound into the AEAD as associated data. `pk_n` is the
   X25519 public part of the prekey sealed against; `eph_pk` is this
   cell's ephemeral public key. Since `eph_pk` is fresh per cell, `sel` is
   **pseudorandom per cell**: two cells to the same recipient carry
   unrelated selectors. The receiver recomputes `sel` over its unused pool
   and matches; a false match (2⁻³² per candidate) is caught by the AEAD
   immediately after. **The long-lived key is an ordinary candidate**, not
   a special case — there is no "static" marker, the sender computes the
   selector over the static public part and the receiver tries it along
   with the pool.

   `n` itself does **not** disappear: it stays the bookkeeping index of
   item 1 — it is what the refill ranges `[kB, (k+1)·B)` are counted in and
   what tells the receiver when to send the next batch. What changed is
   that it no longer travels on the wire, and therefore no longer names
   anything to anyone holding the cell.

   Two things rule out an explicit `(epoch, n)` counter on the wire:

   - **The receiver cannot locate `n` without cost.** The tag (§8)
     carries no message counter, so there is no `n` to read off it;
     locating `n` would cost additional lookup queries against the
     delivery layer, a real, measured cost there (§9.2).
   - **The counter would itself be a leak, and a load-bearing one.** It
     would be cleartext (the opener is pair-agnostic and cannot blind it
     under `K_AB`) and would run **pool-wide per recipient identity**. A
     relay holding mailbox placements (§7, §8) would therefore see
     `(tag, selector)` and could group **different** tags by adjacent
     counters — clustering its holdings by recipient without holding a
     single `K_AB`. That is precisely the linkage §10.1 declares closed.
     For a direct or relayed placement the forwarding relay knows the
     recipient's handle anyway, but the counter sequence would
     additionally disclose the recipient's total volume across **all**
     senders. The pseudorandom selector removes both problems.

   **Price, stated in full.** 4 B of 1 043 B placement payload
   (`kMaxPlaceContentBytes`) — **0.4 %**, regardless of delivery stage,
   half of what the counter would have cost. Per-message overhead
   without the daily capsule is 4 + 32 + 12 + 16 = **64 B**. No extra
   cell, no extra egress, no latency. The receiver pays `N` SHA-256 over
   64 B per incoming cell instead of one lookup, where `N` is the unused
   pool (B = 16 per range, in practice a few dozen) — microseconds, and
   the ordering that matters is unchanged: **a foreign cover cell is
   still discarded before any scalar multiplication**, which is the
   whole point of naming the prekey at all.

   Refill batches cover counter ranges `[kB, (k+1)·B)` per epoch; since
   `n` runs unbounded, B is a pure tuning parameter (**B = 16**,
   simulator-tunable).

   The selector sits **under the seal**, so an observer still sees one
   opaque cell of unchanged length. Naming the prekey this way costs 4 B
   of payload, and the price is named above.
3. The receiver deletes `sk_i` immediately after successful unsealing.
   Unused prekeys are deleted after `delivery TTL + margin` (**15
   days**) — retention MUST outlast the full delivery TTL, or cells
   from days 9–14 become unopenable (silent message loss). *This is not
   in tension with the 7-day retention decided for the previous
   **identity KEM keys** in §4.5.4: a one-time prekey is 32 B of secret,
   so a second week of them costs nothing worth weighing, whereas a
   second retained KEM generation would have to be held on every device
   of every identity. Different objects, different trade.*

**Prekey-refill delivery.** A refill is itself a delivery and must
choose a delivery stage. **Normatively, prekey refills go through the
mailbox (delivery stage 4, Chapter 8):** a refill is not
latency-critical (it is published ahead of exhaustion, with B/2
headroom), and it should not be session-linkable (publishing prekeys
on a linkable direct path leaks that a conversation is about to
happen). The cost is the mailbox harvest cadence on the refill, which
the B/2 headroom absorbs. A direct refill (stages 1–3) is permitted
only as an exception when the sender is about to send directly and the
pool is already exhausted (no headroom) — there the latency of a
mailbox refill would block the send, so the refill goes out directly
and accepts the one-time linkability. This is the one place where the
choice of delivery stage meets the prekey machinery, and it is
specified rather than left open.

**No ratchet.** A pool has no order and no chain position. A lost
cell orphans exactly one prekey (TTL cleans it up) instead of breaking
a chain; out-of-order is the normal case and unproblematic. The
design decision “per-message KEM instead of Double Ratchet — no
session state, no desync" holds and is refined here: no ratchet is
added, only soft, self-healing pool state.

**Fallback ladder on exhaustion:**

| Stage | Key | FS granularity |
|---|---|---|
| 1 | one-time prekey (destroyed on use) | per message |
| 2 | medium-term prekey, daily rotation, 15 d retention | 1 day |
| 3 | long-term KEM key (sealing directly against the 7-day-rotated identity KEM key) | rotation interval — two legitimate occasions: total exhaustion **and answering a distress call** (§13.4.3 — the recovering user's prekey pool was lost along with the devices). First contact needs no KEM stage: CR under `K_inv` hybrid, response already against the prekey batch shipped with the CR, §15 |

**Cost.** One-time prekeys are plain X25519 keys: **public 32 B,
secret 32 B**. The ML-KEM component is a single **daily prekey** per
identity, not part of the one-time pool. At batch B=16 and 200
contacts, the pool occupies ≈ **100 KB** of storage, one refill is ≈
**512 B** per batch, amortized to ≈ **32 B** per message. **B = 16**
is a simulator-tunable value, not tied to the wire format.

**FS effect in the main case:** the one-time X25519 key is destroyed
after use, so `mk` is not reconstructable even with the daily ML-KEM
key on hand. Only the composite attacker (CRQC **and** device access
within the 15-day retention) falls back to daily granularity.

**Groups inherit the 1:1 FS.** Since group messages run as pairwise
legs (§16), each leg consumes one one-time prekey of the respective
pair — groups therefore have the same per-message granularity as 1:1.
Price: one message in an N-group consumes N prekeys (one per pair); for
very active groups the refill cadence rises accordingly, the fallback
ladder catches bursts. Sender keys with epoch rotation remain
exclusively for calls (§17) and large private channels (`K_C`, §16) —
there, daily granularity plus rotation on membership change applies;
the epoch is **24 h**. For group calls, the same rule applies as a
default — one sender key per session, mandatory rotation on every
participant change, a 24 h cap for marathon sessions — the
distribution mechanism falls due with the group-call topology open
items (§17.5) and is not preempted here.

**Limits.** No substitute for post-compromise security. The recovery
bundle (§13) is by construction not forward-secret — and it also
carries the **shared key** (§14.4). A compromised seed therefore opens
not only the contact list, but the **live inbox**. That is the price
for recovery working without outside help, and it needs saying. This
is a review item (optional external crypto review, at publication
readiness, §28).

---

## 5. The cover system

### 5.1 Cover runs beside the traffic

The cover stream is a second, independent stream. It carries nothing a
delivery depends on. It has its own clock and its own buffer, and no code
path connects it to the send path.

| Property | Value |
|---|---|
| cover packet size | 1200 B — identical to a full part (§11) |
| port | the node's own data port — identical to real traffic |
| payload | never a message, acknowledgement or user object; optionally one sealed piece of the public update, or a set of address entries (§5.5) |
| effect of stalling, throttling or crashing | none on delivery, none on update availability |
| running | always while the node runs: on Android inside the foreground service (§12.6), on desktops while the daemon runs; on iOS only while the app runs — with the app closed there is no cover, the same documented limit as for incoming calls (§31) |
| rate on metered mobile data | `R_metered` = 1 packet / 60 s (§5.3) |
| reducing the empty packets | configurable on unmetered W/LAN only; update pieces and address entries keep flowing |

**The stream always runs, and it is not a setting.** A device is a
router: that it is alive must say nothing about the person behind it. Only
a stream that runs regardless of what the user does can make device
liveness unreadable, and only a running stream can carry the address
entries of §5.5. Turning it off entirely is therefore not a
configuration. §3.1 stays testable in a test build, where the stream can be
stopped.

**Reducing the empty packets gives up concealment on that link.** A node
on unmetered W/LAN may send cover only when it has an update piece or
address entries to carry. The stream is then a carrier, not a cover: an
observer on that link sees again **when** real traffic flows (§1.4). The
option exists because on a local network the observer is usually the
network itself; it never applies to metered mobile data, where the rate is
lowered instead (§5.3).

An implementation in which a real packet passes through the cover
buffer, waits for a cover tick, or is counted against a cover budget is
wrong regardless of how well it performs.

### 5.2 Timing: irregular, never a tick

**Cover is never sent on a fixed interval.** Transmission times are drawn
from an exponential distribution, so that the stream is a Poisson process
with mean rate `R_cover`.

This is not a refinement; a fixed interval would defeat the whole
mechanism. Cover runs beside the traffic, so an observer sees the sum of
two streams. If one of them ticks at a constant period, it is separated
by subtraction in a few minutes, and what remains is exactly the real
traffic — the regular stream identifies itself as the filler and hands
the observer a clean view of everything else.

With Poisson timing there is no tick to subtract. An observer can
estimate the total rate, but cannot label an individual packet as cover
or real by its arrival time.

| Parameter | Value |
|---|---|
| distribution | exponential inter-arrival |
| mean rate `R_cover` | 1 packet / 8 s |
| resulting volume | 12.96 MB/day |
| minimum gap | 200 ms (prevents pathological bursts) |
| platform variation | none |
| link variation | `R_metered` = 1 packet / 60 s on metered mobile data (§5.3) |
| open set | 4 neighbours, redrawn at the edges of §11.8 |

**Cover is addressed like real traffic.** Cover packets go to the node's
own neighbours (§11.8), in the same size (1200 B) and on the same port —
never to an address the node has no other business with. A filler
addressed to strangers would be as readable as a fixed tick.

**The draw picks from an open set of four.** Of the up to 32 neighbours,
four form the open set, drawn anew at the edges of §11.8. The Poisson
clock picks among these four only, so each receives a packet about every
32 s at `R_cover` — within the minimum UDP mapping lifetime RFC 4787
requires of a translator (2 min). A node behind address translation thereby
keeps four mappings open without sending a single packet beyond cover:
these four neighbours can reach it, forward to it (§8.1) and hold post for
it (§8.2). The other neighbours are known addresses, not open paths.

**The card's place is fixed.** It holds the neighbour the node's
cards name (§15.2), for as long as any standing invitation (§15.3) names
it. It goes to a neighbour reachable from the open network — one confirmed
under a public address (not private, not shared carrier space, not
link-local) — whenever the node has one; a neighbour known only under a
private address takes it only while there is no other, and gives it up at
the next edge to a reachable one unless a standing invitation still names
it. Otherwise the card's neighbour changes only when it is removed
(§11.8); cards issued afterwards name the new one,
and holders of older cards find the issuer through its publisher key
(§15.2). **This place never goes to a contact's device:** the card
travels to people not yet accepted and is passed on, and a contact's
address in it would hand a friend's address to every reader.

**Up to three places go to contacts.** A device of one of the node's own
contacts that is reachable from the open network under the same rule and
has answered since the last start or network change takes a place before
any other neighbour — one such contact holds one place, more hold up to
three. When a use of one fails and it is removed (§11.8), another contact
that qualifies at that moment takes its place: an edge, not a tick. A
contact the user has excluded (§15.10) never takes one. These contact
places and the card's place are the node's **fixed neighbours**; they
hold its codes (§8.1) and they are the ones step 3 reaches it through.
Where no contact qualifies, the card's neighbour is the only fixed
neighbour. Places no contact holds are redrawn at every edge.

Reachable means reachable by a stranger's neighbour: a phone behind
carrier-grade translation or a provider's IPv6 firewall accepts packets
only from where it has sent to (§8.1) and therefore qualifies only while it
is reachable — at home behind a router that granted a mapping (§7.3), for
instance. On a metered link a contact that could reach the node only over
IPv4 does not count while the own IPv4 needs a keep-alive: there is only
one kept IPv4 path (§8.1); another contact takes the place.

**Why contacts, and why fixed.** A contact's device cannot be bought with
servers; a neighbour drawn from the open network can (§10.2). And the
places stay fixed rather than being redrawn per message: with a
compromised node among five candidates, a fixed choice exposes a pair with
probability one in five and otherwise never, a choice per message after
twenty messages with probability 1 − (4/5)^20 ≈ 99 %. The fixed places are
stored with the neighbours (§21) and survive a restart. Their price is
named: a contact, not a stranger, learns when and how much the node sends
and receives, and the fixed neighbours receive more cover than the others.

**On metered mobile data cover does not hold the open set.** At
`R_metered` (§5.3) each of four open neighbours receives a packet only every
240 s on average — beyond the 2 min of RFC 4787 and RFC 6092. There the
paths rest on the keep-alive of §8.1, which cover replaces wherever it
already refreshed a path within the keep-alive interval.

### 5.3 Rate

The mean rate is bound by what a mobile user accepts as steady
background data — the practical band is 15–25 MB/day — not by desktop
headroom. The rate is set **below** that band on purpose: the stream
always runs (§5.1), so it has to be a rate nobody has a reason to
resent.

A link is **metered** when the operating system says so:
`ConnectivityManager.isActiveNetworkMetered` on Android,
`NWPath.isExpensive` on iOS and macOS, the metered-connection flag on
Windows, the NetworkManager `metered` property on Linux. Where the system
says nothing, the link is unmetered. The node re-reads the property at
every network change (§11.8).

**On metered mobile data the rate is `R_metered`**: one packet per 60 s,
1.73 MB/day. On W/LAN it is `R_cover`.

The reason is the radio, not the volume. A mobile modem stays in its
power-hungry connected state for some seconds after every packet (the
carrier's inactivity timer, typically 5–20 s). Under a Poisson clock with
mean μ and a timer T, cover alone keeps the modem awake for the share
`1 − e^(−T/μ)` of the time:

| Mean on metered data | Modem awake from cover (T = 10 s) | Data per day |
|---|---|---|
| 16 s | 46 % | 6.48 MB |
| **60 s (chosen)** | **15 %** | **1.73 MB** |
| 300 s | 3 % | 0.35 MB |

A cover stream that keeps the modem awake half of the time is felt in the
battery, and a stream users resent is one they uninstall.

The rate is uniform across platforms. Concealment is a cross-platform
property: cover must blend with other people's cover, and a
per-platform rate would make the platform itself readable off the
stream. The lower rate does not break this: it follows the **link**, not the
platform. A phone on W/LAN sends at the same rate as a desktop, and that a
device is on mobile data is visible on the path anyway — the carrier sees
it before any Cleona packet does.

`R_cover` is revisable. It is set by arithmetic, and field behaviour has
the last word.

### 5.4 No standing traffic in idle

Besides the cover stream — which always runs, on its own clock and its
own buffer, and by §5.1 has no code path to delivery — three things in
the whole system run on a clock:

| Transmission | When | To whom | Interval |
|---|---|---|---|
| keep-alive | only on a family where the node sits behind address translation or a firewall (§8.1) | one neighbour per family | measured per network (§8.1); IPv4 30 s and IPv6 60 s until measured |
| address-record refresh | only while the node has a reachable address (§11.9) | 2–3 public relays, **not** the data port | checked hourly, written at most once per ~19 h |
| port-mapping renewal | only while a mapping exists (§7.3) | the node's own router, local segment, **not** the data port | shortly before the lifetime the router granted lapses |

The second and third are clocks that touch nothing but a relay or the own
router: while nothing changes, the record check produces no traffic at all,
and the renewal is one packet into the local segment per granted lifetime.
Neither touches the data port, so neither can compete with delivery for the
socket, the queue or the budget — which is the reason this section exists.

Everything else is event-driven. The post box (§8.2) is queried once at
start and again when the network changes, when a new neighbour is found or
when the user opens the application — never on a schedule. The keep-alive interval is measured at
the same edges, on a probe port of its own (§8.1). The neighbourhood is refilled when an
entry is removed, and stale entries are retried at the next edge (§11.8) —
never on a schedule either. No liveness is published as a packet of its
own, and nothing is polled; what a node knows about reachability travels
inside cover (§5.5).

The reason is structural: periodic maintenance traffic competes with
delivery for the same socket, the same queue and the same budget, and a
queue that is never empty throttles delivery permanently.

### 5.5 Cover may carry update pieces and address entries

A cover packet may carry, instead of nothing, one piece of the signed
public update (§26.6.1) **or a set of address entries**: the sender's own
current addresses — one per address family it holds a socket for, marked as
its own — and the addresses of neighbours the sender has confirmed to answer
under exactly that address (§11.8). This adds no packet, no
byte and no change of timing. Neither is a delivery path: the update
arrives without it (§3.1), and a node finds neighbours without it
(§11.8, §11.8a).

**Address entries are how the network learns that an address changed.**
After a network change the node's new address leaves with the next cover
packet to each of its open neighbours (§5.2) — without a packet of its
own, without a clock of its own. Entries are hints like the records of
§11.9: an address that does not answer is dropped by whoever tries it.

**Pushed entries reach only open paths.** A neighbour behind address
translation receives a cover packet only while its mapping towards the
sender is open. Such a node does not wait to be told: it **asks** the board
of a reachable neighbour (§11.8a), whose answer returns through the
mapping the question has just opened.

**How a cover packet says what it carries.** The sealed payload (1170 B,
§11) opens with one **content byte**:

| Content byte | Carries |
|---|---|
| `0x00` | fill |
| `0x01` | an update piece (§26.6.1) |
| `0x02` | address entries |
| `0x03` | codes this node answers for (§8.1) — only in packets to the node's fixed neighbour |
| `0x04` | keep-alive: the device code (§8.1) and an 8-byte random token — only in keep-alive packets (§8.1) |

Address entries use the same codec as the board (§11.8a): the number of
the sender's own entries (1, at most 2) and those entries, then count (1)
and per entry type (1) + address (4/16) + port (2) + age in minutes (2); at
most 2 + 32 entries, at most 716 B. One statement — "these devices answer under
this address, last confirmed so many minutes ago" — has one format, not
two. The rest of the payload is random fill, so all three kinds look alike
on the wire. The price is one byte per packet.

The four rules below hold for both kinds of content alike.

1. **Never a packet of its own.** A piece replaces the content of a cover
   packet the Poisson clock (§5.2) has already drawn. It never creates a
   send time, never changes rate, size or destination. A stopped stream
   (§3.1, test build) sends no piece and no entry — and nothing waits for
   one.
2. **The draw picks the neighbour, and chance picks the piece.** No node
   sends a piece to the neighbour that needs it; whichever neighbour §5.2
   draws gets a piece drawn uniformly across every object the node holds
   pieces of — never preferring its own platform, which would make the
   platform readable off the stream.
3. **Every cover packet is sealed pairwise — filled or empty.** The piece
   is public; the wrapper is secret to protect the cover, not the content.
   A wrapper that more than the two ends can open turns it into a sieve:
   opens = cover, fails = real traffic.
4. **No back channel, never a packet of its own.** Nothing is requested or
   acknowledged; a request would name the version a node lacks. A received
   piece is never forwarded as a packet of its own — that would break
   rule 1. It leaves the node again only inside a later cover packet the
   clock has drawn anyway.

**What a node keeps.** Pieces of the node's own platform are stored and
assembled automatically within the retention tier's budget (§22.6); once
all pieces are present the update is offered to the user (§26.6.1).
Always-on nodes additionally keep a bounded cache of pieces for other
platforms and offer them again under rule 2 — without that cache, spread
is limited to neighbours of the same platform. Retention-bounded nodes
keep only their own platform's pieces and put none into their cover
packets.

### 5.6 Budget

| Configuration | Volume per node per day |
|---|---|
| W/LAN | traffic + 12.96 MB |
| metered mobile data | traffic + 1.73 MB |
| unmetered W/LAN, empty packets reduced | traffic + update pieces and address entries only |
| keep-alive behind translation or firewall (§8.1) | IPv4 3.46 MB at the default 30 s, 1.15 MB at the longest measured 90 s, none while it rests; IPv6 1.73 MB at the default 60 s, 1.15 MB at 90 s; less wherever cover already refreshed the path |
| metered mobile data behind CGNAT, dual-stack | traffic + cover 1.73 MB + keep-alive 5.18 MB ≈ 6.9 MB with the defaults; ≈ 3.5 MB where IPv4 rests (§8.1). With the defaults the modem is woken every 30 s — about a third of the time awake at a 10 s inactivity timer, the price of being reachable; a longer measured interval or a resting IPv4 lowers it |
| keep-alive measurement (§8.1) | ≈ 50 KB per network change, on the probe port and the data port |
| board question and answer (§11.8a) | 2.4 KB per edge, plus 3.6 KB for the handshake with a new neighbour |
| code registration (§8.1) | ≈ 6.4 KB/day per 200 contacts, inside packets already sent |
| day keys for contacts (§8.2) | ≈ 1 KB per contact every 14 days, as ordinary messages |
| message over the internet (§8.1) | 3 packets each way, acknowledgement included 6 |
| where-are-you (§8.1, exception) | ≈ 1,000 packets, 1.2 MB per event, at most one per contact per hour |

Every packet on the data port is 1200 B (§11), whatever it carries; a
figure in this table that counts only the payload is wrong.
| port-mapping request to the own router (§7.3) | 2 packets per edge, local segment only |

An implementation reports its own measured figure in the network
statistics (§25), so that a node whose traffic diverges from this table
is visible without instrumentation.
## 6. Reachability

### 6.1 Reachability is discovered, not published

No node publishes whether it is online, and no node polls another to find
out. Reachability is established at the moment it is needed, by
attempting delivery (§7, §8). A node that answers is reachable; a node
that does not is not.

**This is about people, not routers.** Whether a **contact** can be
reached is never asked of a third party and never stored by one. The
**addresses of devices** are a different matter: a device is a router,
and where routers can be found travels openly as hints — in cards
(§15.2), in the external records (§11.9), in cover (§5.5) and on the
boards of reachable nodes (§11.8a). None of these says anything about a
person, and none is trusted: an address is tried, and an address that
does not answer is dropped.

### 6.2 What a node knows about another

What it has observed itself — and, kept apart, hints it has not yet tried:

| Source | Content |
|---|---|
| the card (§15.2) | up to four addresses of their own, in their order of preference; optionally the address of a neighbour that reaches them |
| received packets | the address a packet was actually seen from |
| own attempts | which addresses worked, and when |
| hints about devices | address entries from cover (§5.5), boards (§11.8a) and external records (§11.9) — used to find **neighbours**, never taken as a statement about a contact until an attempt succeeds |

That is the complete state. There is no score, no reputation value and no
decay curve. The address that worked most recently is attempted first;
since the remaining steps run in parallel anyway (§3.4), a wrong guess
costs nothing.

### 6.3 Address records

A node keeps, per contact:

| Field | Type | Note |
|---|---|---|
| `lastSeenAddress` | typed address + port | from the most recent received packet; type (1) + address (4/16) + port (2), so an IPv6 peer is remembered as what it is |
| `lastSuccess` | timestamp | last acknowledged delivery |
| `cardAddresses` | up to three | as handed over in the card |

Records are updated on every received packet and on every
acknowledgement. They are never exchanged with third parties.

### 6.4 Declaring a contact unreachable

The delivery layer does not declare anybody unreachable. It reports what
each ladder step did; the application decides when to stop (§9.3). A
recipient who is merely offline is not an error — the message waits in a
post box (§8.2) until they return.
## 7. Direct ways (ladder steps 1 and 2)

### 7.1 All steps at once

A sender knows the recipient's own addresses from the card (§15.2), up to
four of them, plus the neighbour address and whatever it has observed
itself (§6.2). **Which step an address serves is decided by the sender,
from the address itself** — an address inside the sender's own segment
serves step 1, one reachable from the open net serves step 2, and the same
card can feed both. It attempts **every applicable step together**,
staggered by a few milliseconds. The first acknowledgement wins; the
remaining attempts are cancelled.

| Step | Way | Address from | Target |
|---|---|---|---|
| 1 | the card's addresses that lie in the sender's own segment, plus a search call where §7.2 sends one | card + call | milliseconds |
| 2 | the card's addresses that are reachable from the open net — **not for messages** (below) | card, if any | seconds |
| 3 | via the sender's and the recipient's fixed neighbours, by code (§8.1) | card, contact | seconds |
| 4 | post box under the recipient's day value (§8.2) | own neighbours | until the recipient returns |

**Messages go through steps 1, 3 and 4.** Step 2 serves learning the own
address (§7.3) and calls (§17); a message is not sent to a public address,
because that shows the path between sender and recipient to everybody on
it. The price is one or two hops on the open internet — tens of
milliseconds.

Sequential escalation is prohibited. A step that is slow must not be able
to delay a step that is fast, and the only way to guarantee that is to
start them together.

### 7.2 Step 1 — the local segment

The sender transmits to those addresses in the card that lie in its own
segment. **Only when a send to the contact has no way** does it also send
a search call on the local segment. **A send has no way when the recipient holds no address at all**
— none of their own, neither from the card nor observed, and no neighbour
address either. That is the whole test; there is nothing else to weigh. A
stale address still counts as a way: it produces no answer, and the other
steps carry in its place (§7.1).

There are two calls, and they answer different questions.

| Call | Carries | Answered by | Used for |
|---|---|---|---|
| neighbour call | the caller's data port and its node identifier | every listener, with its own data port and node identifier | finding neighbours (§11.8, source 2) |
| search call | the caller's data port, the identifier sought (§4.1) in the clear, and 16 random bytes | only a node that holds an identity with that identifier, with its data port and an Ed25519 signature of that identity over the random bytes, the identifier and the port | ladder step 1 (§7.1), when a send has no way |

**The node identifier is derived from no identity and is drawn anew at
every start.** The neighbour call never carries an identity identifier,
neither in the call nor in the answer: a listener on the segment learns
that a Cleona node runs at an address, not which identity, and cannot
link the same device across two starts by its identifier. Neighbours are
therefore held by address and port, not by node identifier (§11.8).

**The search call names the identity it looks for.** Every listener on
the segment learns that somebody is sending to that identifier, and the
answer tells it at which address that identity runs. This is listed as
RL-18 (§23.7).

Only an answer whose signature verifies against the identity sought
updates the address the sender holds for that contact (§6.3); any other
answer is discarded.

| Parameter | Value |
|---|---|
| multicast group | 239.192.67.76 |
| port | 41341 |
| also sent to | IPv4 broadcast |
| repeat | 3 calls, 300 ms apart, then silence — per call kind |
| answer | unicast, directly to the caller, carrying the answerer's data port |

An answer on the wire is below a millisecond once both sides are
listening; the repeat interval exists only because two nodes rarely start
at the same instant.

Nodes that cannot bind the multicast group or the broadcast address — a
platform restriction on some systems — fall back to the wildcard address
and continue. This is not an error condition and must not be reported as
one.

### 7.3 Step 2 — the public address

The sender transmits to those addresses in the card that are reachable
from the open net.

**Learning one's own public address.** A node asks a neighbour that is
reachable from outside. The neighbour answers with the address and port
it *saw the request arrive from*, never with an address the asker
claimed. The answer is only accepted if it carries the random value from
the request.

| Packet | Content |
|---|---|
| `0x40` ask | 16 random bytes |
| `0x41` answer | the same 16 bytes + the observed address and port, typed: type (1) + address (4/16) + port (2) |

**Knocking.** Where both sides are behind address translation, both
transmit to the other's public address at the same time. The first packet
is usually discarded by the far side's translator but opens the local
mapping; the second gets through.

| Parameter | Value |
|---|---|
| packet | `0x42` |
| attempts | at most 5 |
| interval | 250 ms |
| on success | stops immediately |
| on exhaustion | reports failure, so steps 3 and 4 carry the packet |

**Asking the own router for a way in.** Before a node asks a neighbour
what it looks like from outside, it asks **its own router** for a
**mapping (IPv4) and a pinhole (IPv6)** of its data port — NAT-PMP/PCP
first, UPnP/IGD second; PCP covers both families, UPnP through IGDv2
`WANIPv6FirewallControl` — at the
edges of §11.8 only (start, network change), never on a timer. A mapping
that succeeds turns a private address into a reachable one: the node then
publishes its record (§11.9), keeps a board (§11.8a) and receives what
others push (§5.5). A mapping that fails costs two packets in the local
segment and changes nothing; knocking and steps 3 and 4 work as before.

| Property | Value |
|---|---|
| protocols, in order | NAT-PMP/PCP, then UPnP/IGD |
| what is asked for | a mapping for IPv4, a pinhole for IPv6 |
| switch | on by default (§12.7) |
| when | start and network change (§11.8) |
| cost of a failure | 2 packets, local segment only |
| lifetime | as granted by the router; renewed shortly before it lapses — the third clock of §5.4, local segment only |

A mapping makes the **device** visible from outside — that is its purpose,
and it says nothing about the person: the cover stream (§5.1) is what
keeps device liveness unreadable. A user who does not want the mapping
switches it off; the node is then exactly as reachable as without it.

### 7.4 Acceptance

| Measurement | Target |
|---|---|
| step 1, two nodes in one segment | contact established and message delivered in under 1 s |
| whole chain: contact, message, acknowledgement, reply | under 1 s in one segment |
| step 2, address discovery | the address reported equals the address the neighbour logged |
## 8. Indirect ways (ladder steps 3 and 4)

### 8.1 Step 3 — through a neighbour

Behind address translation, and especially behind carrier-grade
translation, a public address is worthless or absent. The recipient is
then reachable only through a neighbour both sides can reach. **This is
the ordinary case on the open internet**, and the address of such a
neighbour is therefore carried in the card (§15.2).

**No packet names its ends.** A packet on this step carries a code
(§4.3) — per pair, direction and day, random to anybody without `K_AB` —
instead of an identifier. The forwarder knows which codes belong to which
device because every device tells its fixed neighbour; it never learns a
person or an identifier.

**Packet layout.**

| Field | Bytes | Content |
|---|---|---|
| kind | 1 | `0x20` hand on by code, `0x21` code not known here, `0x22` hand on to an address, `0x23` where are you |
| hops left | 1 | starts at 3 (`0x23`: at 2) |
| code | 16 | `0x20`, `0x21`, `0x23`: the code of §4.3 |
| next addresses | 1 + n × (7 or 19) | `0x22` only: count n (1–3), then type + address + port of each next neighbour |
| content | rest | opaque to every node on the way |

**How a node learns codes.** Every node tells each of its fixed neighbours
(§5.2) which codes belong to it: for every contact of every identity it holds,
the code of that contact towards it for today and tomorrow, plus the code
of every open invitation (§15.2) and the one-time reply code of every
pending first contact. The list rides inside the packets that go to the
fixed neighbour anyway (content byte `0x03`, §5.5), padded to a multiple of
64 codes so that its length says little about the number of contacts. It
is sent again when it changes, when the UTC day changes and when the fixed
neighbour changes. The neighbour keeps a code until the end of the day
after its day, at most 4,096 codes per device and 256 devices (the device
registered longest ago gives way); the first device to register a code
keeps it until it expires. A device identifies itself in every
registration by its own 16-byte code, drawn once at first start and kept
across restarts; the neighbour keys its table by that value and writes
the current source address into the entry with every registration. A
device that changes its address is therefore the same device, not a new
one. A registration names codes, never a person or an identifier.

**Sender behaviour.** The sender computes the code and builds one `0x20`
packet — the same for every fixed neighbour of the recipient, since each
of them holds the same codes. It wraps it into **one** `0x22` packet
naming up to three next addresses — the recipient's fixed neighbours as
the recipient last told them (§9.2), or for a first contact the card's
neighbour (§15.2) — and sends it to its **own** fixed neighbour, which
hands the inner packet to each of them. The first acknowledgement wins
(§7.1), a duplicate is ignored (§9.2). A sender without a fixed neighbour
sends the `0x20` packet directly. The reply and the acknowledgement travel
the same way under the reverse code.

**No node may be both hops.** A node the recipient named holds the
recipient's codes and would take the inner packet itself, seeing both
ends. The first hop is therefore the first own fixed neighbour the
recipient did not name, failing that an open neighbour that is neither a
contact's device nor named. **Last resort, named:** where the only
possible first hop is a node the recipient named too — two new users whose
one neighbour is the same node — the `0x20` goes to that node directly, as
before this rule, and the node sees both ends; without it the two could
not reach each other over the internet at all, since the post box needs
two acknowledgements (§8.2). Each such sending is reported in the log.

A contact learns its peer's fixed neighbours only from the peer, sealed:
they ride in every acknowledgement and every message the peer sends it
(§9.2), so a change costs no packet of its own; nothing about them is
published. A list that arrives with post collected from a post box may be
older than one already held; the next acknowledgement corrects it, and
until then the two other addresses and the `0x21`/`0x23` path (below)
carry.

**Forwarder behaviour.**

1. `0x22`: hand the inner packet to each next address it names (at most
   three). A packet naming more than one address is handed on only for a
   device that has registered codes here; for anybody else only the first
   address is used, so that no stranger can turn a neighbour into an
   amplifier. For each next address: if this node has no
   socket for that address's family, it uses another address of the same
   neighbour (§11.8); if it knows none, it hands the `0x22` on, hop count
   minus one, to one open neighbour (§5.2) that has an address in that
   family — at most once, the hop count bounds it. Nothing else.
2. `0x20`: is the code registered here? Hand the packet to that device.
   If the incoming hop count is zero, drop; otherwise decrement it.
3. Otherwise answer `0x21` with the code, so that the sender learns this
   way is closed instead of waiting.
4. `0x23`: code registered here — hand it to the device; otherwise hand
   it on once to every neighbour, hop count minus one, drop at zero.

**Losing the way.** A sender that receives `0x21` and has no
acknowledgement from step 4 within its window sends one `0x23` — one part,
no message inside, only its own fixed neighbours sealed to the recipient.
It reaches every node within two hops (about 1,000 packets, 1.2 MB). The
recipient answers on the ordinary way; its acknowledgement carries its
current fixed neighbours (§9.2). At most
one `0x23` per contact per hour; a node hands on at most one `0x23` per
minute per incoming neighbour.

**What each node on the way sees.** The sender's neighbour sees the sender
and the address of the recipient's neighbour; the recipient's neighbour
sees the sender's neighbour and the recipient. Nobody on the way sees both
ends, and nobody sees a person. **Limit, stated:** whoever controls both
neighbours links both ends through the code; whoever watches the sender's
provider and the recipient's neighbour can correlate timing. Cover (§5)
lowers this, it does not close it. Where the fixed neighbours are contacts
(§5.2), controlling one means controlling a device the user chose to
trust, not running a server. The last resort above is the one case in
which a single node sees both ends.

**Loop protection is mandatory.** Every forwarder remembers an identifier
of each packet it has forwarded and refuses to forward the same packet
twice.

| Parameter | Value |
|---|---|
| packet identifier | first 8 bytes of SHA-256 over the content |
| memory | 60 s |
| initial hop count | 3 |

A hop count alone bounds the damage of a loop; it does not prevent one.
Both mechanisms are required.

**The forwarder cannot read the content.** It sees a code, a hop
count and opaque bytes. An implementation must be able to demonstrate
this: a forwarder without the recipient's keys fails to open the
envelope.

**What step 3 requires of the recipient.** A path through address
translation or a stateful firewall stays open only while packets leave on
it; outbound traffic alone refreshes it (RFC 4787 REQ-6, RFC 6092
REC-16). A node behind either keeps its paths open with keep-alive
packets — sealed cover packets (content byte `0x04`, §5.5), 1200 B like
every packet on the data port, that expect no answer. On a family where
the node's own address is reachable (public IPv4, a granted mapping or
pinhole, §7.3, or the family found open, below) none runs, and none is sent
to a neighbour that received a cover packet on that family within the
interval.

**Is the family open?** A global IPv6 address says nothing about a
firewall (§11.8a), and a carrier documents nothing. At the edges of §11.8,
per family, the node checks instead of assuming:

1. It opens an **untouched port**: a second UDP socket that has never
   sent anything.
2. From its data port it sends `0x48` to its card's neighbour, carrying the
   untouched port's number and 16 random bytes.
3. The neighbour takes the address it **saw** the `0x48` come from — never
   one the node claims — and sends `0x49` with that address, the port and
   the 16 bytes to one other open neighbour outside its own segment.
4. That neighbour sends `0x4A` with the 16 bytes once to the address and
   port.

If `0x4A` arrives within 5 s at the untouched port, nothing in between
needed state to let it in: the family is **open**, no keep-alive runs on
it, and the node's reachability is evidenced (§11.8a) — it may hold a
fixed place for others (§5.2). An open IPv6 carries for the rest of IPv4
like a granted pinhole. If nothing arrives, the family counts as not open
and keep-alive runs; silence is not evidence of anything else (§11.8), and
a second check follows at the next edge, not before a minute has passed. A
neighbour answers `0x48` only for a device registered with it (§8.1), at
most once a minute per device, and a helper sends at most one `0x4A` per
target a minute; the target is always the asker's own observed address,
so the check can neither amplify nor be aimed at a third party.

| Packet | Content |
|---|---|
| `0x48` is my family open? | kind + untouched port (2) + 16 random bytes |
| `0x49` try it from here | kind + type + observed address + port + the 16 bytes |
| `0x4A` open | kind + the 16 bytes |

| Path | Interval | When |
|---|---|---|
| IPv4 | 30 s until measured, then the measured interval | always, to one neighbour — preferably one that also answers over IPv6, so that it can forward between the families; it rests under the three conditions below |
| IPv6 | 60 s until measured, then the measured interval | unless the family is open (above): to each fixed neighbour of §5.2 that is a contact and an IPv6 neighbour, and to the card's neighbour while an invitation stands; where there is none, to one neighbour — the card's where it is an IPv6 neighbour |

**All of them in one radio wake.** The keep-alive packets to the fixed
neighbours leave together, at the same instant, as the two families do — one
wake per interval, however many fixed neighbours there are. A path that
cover refreshed within the interval is left out.

Address translators are often shorter than RFC 4787 asks. A measurement
across networks found 74 % of them expiring idle UDP state after one
minute or less, values from 10 s to 200 s, and a median of 65 s in mobile
and 35 s in fixed-line carrier translation (Richter et al., "A
Multi-perspective Analysis of Carrier-Grade NAT Deployment", IMC 2016);
no carrier documents its value. IPv4 therefore starts at 30 s, and the
node measures its own (below). A firewall must keep UDP state for two
minutes (RFC 6092 REC-14), so IPv6 starts at 60 s. Where both families are
kept, a packet on one takes the other along once three quarters of its
interval have passed — one radio wake instead of two. Besides cover,
these are the only standing packets on the data port (§5.4).

**The interval is measured, not assumed.** At the edges of §11.8 — at
start, once the neighbour is confirmed, and at a network change — and on a
move report (below), the node measures per family how long its translator
or firewall holds an idle path. It measures only towards a neighbour
reachable from the open network; towards one in its own segment there is
nothing in between to measure.

1. It opens a **probe port**: a second UDP socket on a port the operating
   system picks, with a shell of its own (§4.2). The probe port never
   carries delivery (§11.1).
2. From the probe port it asks the neighbour `0x40` (§7.3). The answer
   `0x41` is the **control**: without it — a firewall blocks the probe
   port, the neighbour does not answer — the measurement ends and the
   defaults stand.
3. The probe port stays silent for `T`. Then the node sends `0x45` with
   the 16 random bytes of that `0x40` **from its data port**; the
   neighbour sends `0x46` once to the address it saw that `0x40` come
   from. If it arrives within 5 s, the path held for `T`.
4. `T` is bisected over 20, 30, 40, 60, 90 and 120 s, starting at 60 s —
   at most three tests per family, both families side by side. Every test
   uses a fresh probe port, which is closed afterwards: a lapsed mapping
   would come back under another port.

The interval is three quarters of the longest `T` that held: 15, 22, 30,
45, 67 or 90 s. A failed control leaves the defaults. If no `T` held, IPv4
counts as **not holdable** and keeps 30 s; IPv6 keeps 60 s. An interval
becomes longer than its default only on positive evidence — a lost packet
can never lengthen it. A measurement costs about 50 KB and takes at most
five minutes; the defaults apply meanwhile.

| Packet | Content |
|---|---|
| `0x45` echo request | kind + the 16 random bytes of a `0x40` this neighbour answered within the last 180 s |
| `0x46` echo | kind + the same 16 bytes, sent once to where that `0x40` came from |
| `0x47` moved | kind + the 8-byte token of the keep-alive that showed the move |

The neighbour sends an echo only to an address that asked it `0x40`
itself, once per question and no larger than the request, so nobody can
aim it at a third party.

**Safety net: the neighbour reports a move.** A keep-alive (content
`0x04`) carries the device code of this section and an 8-byte random
token. The fixed neighbour moves the device's code-table entry to the
address the keep-alive came from — step 3 follows at once instead of at the
next registration — and when the address in that family changed, it
answers once with `0x47` and the token, at most once a minute per device.
A move means the mapping lapsed despite the interval: the node falls back
to the default for that family and measures again, unless it measured
within the last 30 minutes.

**IPv4 may rest where IPv6 carries.** The IPv4 keep-alive is suspended
while all three hold: (1) IPv4 measured below 30 s or not holdable; (2)
IPv6 measured holding at least 60 s, or the own router granted a pinhole
(§7.3); (3) the fixed neighbour answers under IPv6 and under IPv4, so that
it forwards between the families. The IPv4 socket stays open: the node
still sends over IPv4 on its own initiative — post box, contacts, the local
segment — and the answers return through the mapping that sending opened.
Only unsolicited reachability over IPv4 rests. When a condition fails — a
network change, a new fixed neighbour, a move on IPv6 — the IPv4 keep-alive
resumes at that edge.

### 8.2 Step 4 — the post box

The recipient is off. The sender leaves the packet under the recipient's
day value (below) with three holders, and the recipient collects it on
return.

**The holders are chosen so that the recipient will ask them.** First the
recipient's fixed neighbours as the recipient told them (§8.1, §9.2), or
for a first contact the neighbour its card names (§15.2); then neighbours the sender
knows the recipient to hold, from address entries and boards (§5.5,
§11.8a); only then the sender's own neighbours. A post box at a holder the
recipient never asks is not redundancy — it is a packet that expires after
seven days. The recipient asks its own neighbours (below); an overlap
between the two sets is therefore not an accident to hope for but a choice
the sender makes.

| Packet | Meaning |
|---|---|
| `0x30` | hold this, under this day value |
| `0x31` | held (acknowledgement) |
| `0x32` | anything under these day values? (at most 7: the retention) |
| `0x33` | here is one |
| `0x34` | nothing here |
| `0x35` | a challenge |
| `0x36` | proof: the day public key and an Ed25519 signature over the challenge |

| Parameter | Value |
|---|---|
| neighbours addressed | 3 |
| acknowledgements required to count as placed | 2 |
| retention | 7 days |
| at most per day value | 100 packets |
| deletion | only after the collector acknowledges receipt — except the public manifest entry of §26.5.4, which is read, never deleted |
| proof of work on `0x30` | `D_box` = 18 leading zero bits |

**Day keys.** Every identity derives one Ed25519 key pair per UTC day from
its own signing key and gives each contact the public keys of the next 31
days, sealed as an ordinary message — at an edge (start, network change,
new contact), when the last such message to that contact is older than 14
days. A post-box packet is left under the day value: the first 16 B of
`SHA-256(day public key)`. Holders see only day values, never a person or
an identifier. The public manifest entry of §26.5.4 keeps its fixed public
value and needs no proof.

**Who may collect.** Anybody who knows a day public key may leave a
packet; only the recipient may collect it or have it deleted. A holder
answers `0x32` with a challenge per day value and hands out or deletes
nothing until the collector returns the day public key — which must hash
to the day value — and an Ed25519 signature over the challenge with the day
secret key. A contact knows the public key but not the secret key: it can
leave post, not collect or delete it. A challenge is used once. A deletion
acknowledgement is signed the same way.

**Leaving costs work.** A `0x30` carries a 16-byte proof of work bound to
that packet — its id, the day value and the content — in a 10-minute
window; a holder accepts the current and the previous window and discards
a packet without a valid proof silently. Without it, a hundred packets
under somebody else's day value would push that recipient's real post out
of every holder (§20.2).

Two of three is deliberate: one unavailable neighbour must not be able to
block delivery. Deletion after the collector's acknowledgement, rather
than on hand-out, is equally deliberate: a packet lost on the way to a
returning recipient would otherwise be gone permanently.

**When the recipient asks.** Once at start; again when the network
changes; again when a new neighbour is found (§11.8); again when the user
opens the application. Never on a timer (§5.4). It asks its own
neighbours and, among them, always each of its fixed neighbours (§5.2) —
the holders senders choose first.

**The holder cannot read the content.** It sees a day value and opaque
bytes, as a forwarder sees a code (§8.1).

### 8.3 Redundancy lives here and nowhere else

The direct paths carry no redundancy: a direct path either carries the
packet or it does not, and the other steps are running in parallel
anyway. Redundancy is three copies in the post box, and that is the
whole of it for cell-sized payloads. Media redundancy is a separate
mechanism (§9.4).
## 9. Delivery state, acknowledgement and large payloads

### 9.1 Four states

| State | Meaning | Shown as (§12.2) |
|---|---|---|
| `resting` | created, not yet sent | pending mark |
| `in transit` | sent, no acknowledgement yet | single mark |
| `delivered` | the recipient acknowledged | double mark |
| `failed` | given up; no way carried it | warning mark |

That is the complete set, and an implementation must not extend it. Every
additional state is a transition that can be wrong, and a state with no
consumer is a defect waiting to happen.

`in transit` deliberately covers "lying in a post box". A sender does not
learn, and does not need to learn, which rung of the ladder carried the
packet.

**A recipient who is offline is not an error.** The message stays
`in transit` while it waits in a post box. `failed` is reserved for the
case where no rung carried it at all.

### 9.2 The acknowledgement

Every non-ephemeral message is acknowledged by exactly one packet from
the recipient, carrying the message identifier and the recipient's current
fixed neighbours (§5.2, §8.1), nothing else. Ordinary messages carry the
same list, sealed, right behind their identifier; a contact keeps the
latest list it heard. An identity names to its contacts only fixed
neighbours that are its own contacts, otherwise the card's neighbour — a
friend of one identity is never named to the contacts of another.

| Property | Value |
|---|---|
| kind | `0x11` |
| content | the 8-byte message identifier; count (1) + up to three addresses, type + address + port each (≤ 58 B) |
| sealed to | the original sender |
| signed by | the recipient, inside the seal |

**The acknowledgement is sealed and signed.** An unsealed acknowledgement
could be forged by any party that saw the identifier, showing a sender a
delivery that never happened.

| Situation | Behaviour |
|---|---|
| acknowledgement from a party other than the addressee | discarded, reported as discarded |
| acknowledgement for an unknown identifier | discarded, not raised as an error |
| duplicate acknowledgement | ignored |

An acknowledgement for an unknown identifier is the expected consequence
of a retry crossing a late answer, and must never surface as a fault.

### 9.3 Giving up is the application's decision

The delivery layer never decides on its own that a message has failed. It
reports what each step did; the application decides when to stop. There
is no timer that expires messages and no background retry loop.

Where a user retries, the message is sent again under a new identifier;
the old one is closed as `failed`.

### 9.4 Large payloads — three lanes for media

Media takes one of three lanes, decided **first by size**, then by
viability — never by silent preference.

| | Lane | When | Mechanism |
|---|---|---|---|
| 1 | inline | payload below 256 KB | Reed-Solomon striped, placed like any other packet |
| 2 | streamed | at or above 256 KB, both parties online, within the relay size cap `C`, a volunteer available | Reed-Solomon pieces through a consenting neighbour; nothing stored in the network; the parties do not learn each other's addresses |
| 3 | bulk | otherwise | the same pieces placed once each with always-on holders, collected by the recipient on its own cadence |

**Lane 1, the codec.** The object is striped at cell level: `K = 7`
consecutive 1024 B source blocks per stripe, `N = K + d` fragments of
1024 B each. Overhead is fixed at `N/K`, deterministic, with no tail and
no refill round.

| Parameter | Value |
|---|---|
| size threshold between lane 1 and the others | 256 KB |
| stripe width `K` | 7 source blocks |
| block size | 1024 B |
| fragment surplus `d` | 4 |
| resulting overhead `N/K` | 1.571 |
| relay size cap `C` | 25 MB of payload (D-1) |

**Pieces are lane-neutral.** All three lanes carry the same
Reed-Solomon pieces and differ only in where those pieces go.

**Why Reed-Solomon and not a rateless code.** A rateless code needs
`K·(1+ε)` blocks and lets the sender produce as many as it likes — an
advantage when there is a back-channel saying "keep sending", or when a
recipient collects from many independent holders that each hold a random
subset. Neither applies here: a placement is one-shot, the sender learns
nothing about who collects, and the post box hands out the pieces of one
holder. Without feedback the sender has to overshoot anyway, which is
exactly what a fixed `N = K + d` does — only deterministically, with a
stated failure boundary (four of eleven may be lost, a fifth may not) and
with no refill round. At `K = 7` the simple rateless codes also carry a
poor `ε`; the good ones are a substantial build for a case the design
does not have. The receiver
derives the codec from the object length, which the announcement already
carries; no additional field is needed.

**The relay size cap `C`** protects the volunteer: above `C` a transfer
takes the bulk lane even when both parties are online (D-1). At
`C` = 25 MB a transfer is 3,488 stripes of 11 fragments; at the 1200 B
frame size of §17.6 the volunteer forwards at most 46 MB in each
direction per transfer. The cap is set, not measured; the volunteer's
real load and the share of transfers that take lane 2 at this cap are
measurement work (Appendix C).

## 10. Sybil and censorship resistance

### 10.1 Targeted grinding is closed (M6)

A remote non-contact state cannot grind toward a chosen victim: where a
message is placed and how it is retrieved is keyed to a secret that only
the two pair partners hold, and the split between a sender's and a
recipient's share of that secret is anchored to the two **founding
Ed25519 public keys** — the one value both sides already share before
first contact and that survives every later key rotation or UserID
re-mint (§4.1, §15.2; the placement and retrieval mechanics themselves
are §7-§9).

The attacker cannot compute the placement secret, does not know the
victim's neighbourhood, and the queries used to check for waiting
messages are indistinguishable from the cover system's own traffic (§5,
§6). This is the KEX-Gate (§4) doing load-bearing work: it removes the
targeted attack entirely.

### 10.2 Only passive fleet coverage remains

What an adversary can still do is run many relays and, by chance,
observe a target whose messages happen to be placed nearby (the
placement and redundancy scheme this depends on is §7-§9). At the
measured scale, reliable observation or sustained censorship of even a
single target needs a fleet running into the **tens of percent of all
relays** — operationally massive and visible as a coordinated fleet.
A fleet takes a fixed place (§5.2) only at nodes that have no reachable
contact; where a contact holds it, the fleet has to take over that
device, which servers cannot do.

**Read the number correctly: it is not per target.** The chance of
landing near a given target does not depend on which target it is, so
the same fleet covers **all** targets at the same rate — the fleet cost
is paid **once, not per target**. Two consequences, both stated plainly:

1. A fleet large enough for sustained observation of one target is
   large enough for **network-wide** censorship. That is an availability
   attack on the whole network, and it is the honest reading of the cost
   above. It sits next to the whitelist-total-filter edge (§10.4) as a
   declared availability limit (appendix B), not as an anonymity
   failure.
2. **Deanonymization still does not follow.** An observed placement is
   not a person: placements are unlinkable to an identity, and the
   lookup traffic is mixed with the cover system's own decoys (§5, §6).
   A fleet learns that some placement is active and can drop packets on
   it — not who is behind it.

### 10.3 Reputation is gated, not weighted (E-B = B1)

Relay eligibility is **gated**: a fresh **node position (`L_node`)** is
ineligible until it has aged in for roughly **ten days** of standing,
continuously paid-for fleet before a single relay counts. Under weighted
reputation, a fresh Sybil ID is merely lower-weight but still eligible
(weaker). Under gated eligibility, producing IDs does not help at all —
the adversary must deploy and *hold* a fleet for that whole window in
advance, paying roughly ten times the uptime cost of a single relay and
leaving a standing-fleet signature. Gated eligibility makes flash-Sybil
operationally impossible.

The gate is scoped to the node position, not to identity: relays are
addressed by `L_node`, which §4.5.2 keeps node-level and identity-free.
Scoping it to identity instead would mean a daemon hosting N identities
carries N aging values, which contradicts §4.5.1 (network behaviour must
not reveal how many identities a node hosts).

**Two conditions without which the gate does harm rather than good
(normative).**

1. **The aging must be persisted — and what is persisted is the
   *evidence*, not the first sighting.** What has to survive a daemon
   restart is a record of the days on which the position did verifiable
   work reaching or being reached (§7-§9), not merely the day it was
   first named. A first-named-only record is free to produce and would
   let two claims ten days apart satisfy the age check with **zero**
   uptime in between — the exact opposite of "~10 days of standing,
   continuously paid-for fleet". Held only in memory, every peer would
   be "fresh" after every restart and the node would find no eligible
   relay for ten days — an availability failure traded in for a Sybil
   fix. Eligibility requires enough such days of evidence, not
   necessarily consecutive ones: an honest node may drop out for a day;
   the adversary still has to run for the whole window. The on-disk
   format is versioned and a **prior version is not read** — it carries
   exactly the record this rule discards.
2. **A cold-start exit is required.** `isEligible` returns false for an
   unknown position, so in a young network *nobody* is eligible on day
   one. The gate must therefore take effect only once enough eligible
   positions are known; below that threshold it waves everything
   through. Without this, the first node of a new network can never
   place anything, and the network cannot start at all.

A state can block the entire Cleona protocol at its border (block the
port, the traffic shape, the relay network of §11.9). This is a bounded, declared
edge: it is not an anonymity failure (content and relationships stay
safe) but an availability failure. Closing it requires door-connect work
(bridging into the jurisdiction) and is outside the anonymity design.
Honest scope: this design does not solve total protocol blocking; it
makes targeted censorship and deanonymization infeasible.

---

## 11. Wire and transport

### 11.1 One socket

A node opens exactly one UDP socket and uses it for everything: real
packets, cover, calls. There are two exceptions. The calls of §7.2 use
their own socket on port 41341 (§11.5). The measurement of the keep-alive
interval (§8.1) opens a probe port for a few minutes at a time; it carries
only `0x40`, `0x41` and `0x46`, never delivery, and a blocked probe port
changes nothing but the measurement. The untouched port of the open check
(§8.1) lives for a few seconds; it receives `0x4A` and answers nothing but
the shell handshake of that packet, never delivery. Apart from that there is
no second port and no second protocol.

| Property | Value |
|---|---|
| protocol | UDP |
| sockets | one IPv4, one IPv6, both bound to the same port number |
| port | chosen at first start, random in 20000–60000, then stable |
| exception | none — no node uses a fixed, published port (§11.7) |

The port is fixed at first start and never changes on its own. A node
that changes its port is unreachable to everybody holding its card until
a new card is exchanged.

**Dual stack.** Both sockets carry the same traffic. A node opens the
sockets **for the address families it actually has**: it reads its
interfaces first and binds the IPv6 socket only when an IPv6 address is
present under which someone can reach it — a global address or a unique
local one. Link-local `fe80::/10` does not count: without a zone
identifier it is no destination another node can use, and it never enters
a card (§15.2). There is no speculative bind. A bind on `::` succeeds even
on a host with no usable IPv6 at all, so the error would not surface where
it arises but at the first send, asynchronously, and it ends the socket. A
node knows its network environment instead of exploring it by failing.
Should the bind fail nonetheless, that is not an error either and the node
continues with IPv4 alone. When the set of interfaces changes, the node
re-reads it at the same edge as everything else (§11.8) and opens or
closes the second socket accordingly — a phone leaving Wi-Fi for mobile
data may lose its IPv6, and keeping the socket would keep a socket whose
first send ends it.

A node with a global IPv6 address advertises it in its card (§15.2); a
node without one simply does not, and the address-type byte carries the
distinction.

**A node speaks only the families it has.** It sends to, admits as a
neighbour, names in a card (§15.2) and in a way back (§15.5) only addresses
of a family it holds a socket for. A hint in another family is not stored
and not tried.

**A node that speaks both families bridges between those that do not.** An
IPv4-only and an IPv6-only node never reach each other directly — but each
reaches a dual-stack node, and each finds one through the records of
§11.9. That node forwards (§8.1) or holds the post box (§8.2), and needs
no lookup to do it: it learns both parties from their own incoming
traffic, because both wrote to it first. This is what §25.1 measures as
family diversity.

### 11.2 Parts

Anything above the part size is split, sent as numbered parts, and
reassembled by the recipient. Nothing else in the system needs to know
whether a payload was split.

| Field | Bytes | Content |
|---|---|---|
| identifier | 8 | random per transmission |
| count | 2 | number of parts, u16 LE |
| index | 2 | this part's number, u16 LE |
| payload | up to 1188 | |

| Parameter | Value |
|---|---|
| part size including header | 1200 B |
| header | 12 B |
| payload per part | 1188 B |
| largest transmission | 65535 parts |

### 11.3 Re-requesting what is missing

The recipient does not acknowledge parts individually. It waits for a
quiet moment and then asks once for everything still missing.

| Parameter | Value |
|---|---|
| quiet period before asking | 300 ms without a new part |
| request | one packet listing the missing indices |
| rounds | at most 3 |
| after 3 rounds | the transmission fails and the caller is told |
| incomplete transmissions discarded after | 30 s |

There is no timer that runs while parts are arriving, and no
per-part acknowledgement. A transmission that never completes fails
cleanly rather than hanging.

### 11.4 Address translation

A node behind address translation learns its public address by asking a
neighbour what it saw (§7.3) and keeps the path open with the keep-alive
of §8.1 — one neighbour per address family. Where both sides are
translated, both knock simultaneously (§7.3); if knocking does not
succeed within five attempts, the ladder carries the packet through a
neighbour or the post box (§8).

A node asks its own router for a mapping and a pinhole (§7.3), on by
default, but nothing in the design depends on it: a mapping the router
refuses or revokes silently leaves the node exactly as reachable as
without it, and knocking and steps 3 and 4 carry as before. A granted
mapping is evidence of reachability only while it lasts (§11.8a).

### 11.5 Packet kinds

Every packet begins with one byte saying what it is. The ranges are
assigned once, centrally, and a module that needs a new kind takes it
from here rather than choosing one:

| Range | Subject |
|---|---|
| 0x01-0x0F | first contact (§15) |
| 0x10-0x1F | messages (§9) |
| 0x20-0x2F | handing on by code (§8.1): `0x20`–`0x23` |
| 0x30-0x3F | post box (§8.2) |
| 0x40-0x4F | public-address discovery and knocking (§7.3); board question `0x43` and answer `0x44` (§11.8a); keep-alive measurement `0x45`–`0x47` and open check `0x48`–`0x4A` (§8.1) |
| 0x50-0x5F | media (§9.4) |
| 0x60-0x6F | groups (§16.2) |
| 0x70-0xFF | free |

The calls of §7.2 are not in this table: it has its own socket on
port 41341 and therefore its own numbering.

This table is normative because its absence has already cost something:
three modules independently claimed 0x40 and 0x41 on the same socket, and
on that socket a packet would have reached the wrong recipient. Nobody
could see it while each module was built on its own.

### 11.6 What a node accepts

| Packet | Accepted from | Rule |
|---|---|---|
| parts of a transmission | anyone | reassembled; the content decides what happens next |
| sealed envelope | anyone | opened; an envelope that does not open is discarded silently |
| neighbour call, search call and their answers | the local segment only | §7.2 |
| forward request | anyone | §8.1, subject to hop count and loop memory |
| post box: hold | anyone | §8.2, subject to the per-day-value cap |
| post box: collect and delete | the recipient, proven by a signed challenge (Ed25519) | §8.2 |

A packet that cannot be parsed is discarded without an answer. A node
never answers an unparseable packet, because an answer would confirm
that something is listening.

### 11.7 The first entry

A node needs one reachable address to start from. **No address, port or
host is built into the application or its configuration — an environment
variable pointing at an entry node is configuration too —, and nothing in
the system depends on a particular node being present.** The entry comes
from the invitation card of the first contact (§15.2): its LAN, public and
neighbour addresses and its relay list. From there the node's list grows
with every neighbour it learns (§11.8); the more addresses of contacts a
node knows, the better. Where the card's addresses do not answer, the node
uses the external records of §11.9. Once stable nodes of our own exist,
their addresses travel in the card instead of or alongside the relays;
they, too, are ordinary nodes without privileges.

### 11.8 Finding neighbours

A node needs neighbours before it can do anything except show its card
(§12.4). It looks in the first three places, **all three at once**, and
keeps whatever answers first. As soon as one of them has produced a
neighbour that is reachable under its address, it asks that neighbour's
board (§11.8a). The fourth is read while the node is below 32 answering
neighbours (§11.9):

| | Source | Content | Typical result |
|---|---|---|---|
| 1 | remembered | the neighbours from the last run, stored with the contacts (§21) | instant, and usually enough |
| 2 | the local segment | the neighbour call of §7.2 | milliseconds, when anybody is on the same network |
| 3 | the first contact's card | the addresses and relays carried in the card of §15.2, and those learned from later cards | one round trip |
| 4 | external records | signed address records published on a public relay network (§11.9) | seconds, and works where none of the others do |

Sources 1–3 are attempted together, not in order: a remembered neighbour
that has moved must not delay the neighbour call, and an empty local
segment must not delay the card's addresses. Sources 1–3 count as finished
when the call's three rounds are over and the card's addresses have been
tried once; external records (§11.9) are then read if the node is still
below 32 answering neighbours.

**32 answering neighbours is the optimum, and the node works towards it.**
It is a target, not a condition: a node with one neighbour works, and two
freshly installed phones that have just found each other are a healthy
state, not a deficiency. A neighbour is a node, held as the set of
addresses it answers under, each with its port and confirmed on its own.
Two addresses belong to the same neighbour when it names them as its own
(§5.5, §11.8a) in a sealed packet that arrives from one of them; the node
identifier plays no part — it is drawn anew at every start (§7.2). A use
goes to an address of a family this node has (§11.1). 32 counts neighbours,
not addresses.
A neighbour counts only while it answers **under the address it
advertises**; only such a neighbour is passed on to others (§5.5, §11.8a,
§15.2). When the list is full, the entry confirmed longest ago gives way to
a fresher one. There is no score and no probation.

**Reachability has a direction, and the list holds the direction that
matters: outbound.** A node behind address translation reaches a node
with a public address; the reverse works only while a mapping is open
(§5.2). The far node is a good neighbour of the near one, and the near one
is not a neighbour of the far one until it sends. **Silence is therefore
never evidence that a neighbour is gone** — it is the normal state of a
path whose mapping has closed.

**An address is removed when a use of it fails, not when it is quiet; the
neighbour goes with its last address.** Every
packet that expects an answer — the neighbour call, a receipt, a board
answer, the address answer of §7.3 — confirms the entry and stamps it. An
entry not confirmed for a day is stale: at the next edge it is tried
**once**, and only a failure removes it.

A use has failed only when the request went out twice without an answer
**and** this node has confirmed at least one other neighbour since its
start or last network change. A node that confirms nobody — offline, a
dead uplink — learns nothing about its neighbours from silence and removes
none. The price is one packet more per failure, and a dead neighbour stays
one attempt longer.

**A removal is an edge.** Falling below 32 triggers what a cold start
triggers — sources 1–3, the board (§11.8a), the external records (§11.9) —
at most one round per minute, and only after something was removed. While
nothing is removed, nothing happens: no timer, no probe, no traffic.

| Parameter | Value |
|---|---|
| optimum | 32 answering neighbours |
| open set for cover | 4 of them (§5.2) |
| stale after | 1 day without confirmation |
| retry of a stale entry | once, at the next edge |
| refill after a removal | at most one round per minute |

**After a network change** — a different interface, a new address, a
return from sleep — the remembered addresses are re-attempted once and
the neighbour call is repeated once. The open set (§5.2) is redrawn, and
the node's new address leaves with the next cover packet to each open
neighbour (§5.5). Nothing else is triggered, and nothing is repeated on a
timer.

### 11.8a The board

A node whose reachability under its own address is **evidenced** keeps a
**board**: the addresses of up to 32 other nodes it has confirmed to answer
under their address, each with the age of its last confirmation.

**Reachability is evidenced, not assumed.** Evidence is a mapping or
pinhole its router granted (§7.3) and that has not lapsed, or an
unsolicited packet from a node it has never sent to. An address class
alone is not evidence: home routers commonly drop unsolicited inbound IPv6
by default, so a global IPv6 says nothing about whether anyone can reach
the device. A board that pointed at unreachable nodes would point at
exactly the addresses that help least (§11.9). Publishing a record (§11.9)
stays tied to the address class — a record is a hint, and a node cannot be
found before it publishes. The evidence costs no packet; the passive kind
arises from traffic that flows anyway.

Any node that already knows one such node may ask it for the board, once
per edge. The answer is one packet. It carries first the answering node's
own addresses, in the codec of §5.5. The board is never pushed, never
announced and never kept open; a node behind address translation asks from
the inside, and the answer returns through the mapping its question has
just opened.

| Packet | Content |
|---|---|
| `0x43` board question | 16 random bytes |
| `0x44` board answer | the same 16 bytes + the address entries of §5.5: count (1), then up to 32 entries, each type (1) + address (4/16) + port (2) + age in minutes (2) |

Both travel sealed like every packet on the data port, 1200 B each (§11);
a first question to a neighbour without a pairwise key costs a handshake
first (2400 B out, 1200 B back). **The answer is never larger than the
question**, so a board cannot be abused to amplify traffic towards a
forged sender. An answer whose 16 bytes do not match an open question is
discarded.

| Property | Value |
|---|---|
| kept by | nodes whose reachability is evidenced (above) |
| entries | at most 32, only confirmed ones (§11.8) |
| asked | once per edge, after sources 1–3 and before the external records |
| size of the answer | payload at most 32 × 21 B + 17 B = 689 B; on the wire 1200 B, the same as the question |
| trust | none — an entry is a hint like a record (§11.9) |

**The first pointer is always learned, never built in** (§11.7). It comes
from a card (§15.2: the issuer's own address or its neighbour's), from the
neighbour call in the segment (§7.2), or, once, from the external records
(§11.9). A node that has one pointer does not need the relays again.

**This is the difference to the external records, and it is deliberate.**
The relay network works without any contact because the application
carries a built-in list of foreign relays (§11.9). Cleona may not carry
addresses of its own (§11.7); its board therefore needs one pointer from
outside. In exchange it knows what the relays cannot: who actually
answers, and since when.

### 11.9 External address records

A node below 32 answering neighbours — in the extreme case one with no
remembered neighbours, on a network where the neighbour call reaches nobody
and the addresses of the first contact's card do not answer — still needs a
way to more. It reads address records that other nodes have published on a
public relay network.

| Property | Value |
|---|---|
| what is published | the node's own address record: addresses, node key, validity |
| signed with | secp256k1 Schnorr, the signature scheme the relay network requires |
| read by | any node looking for neighbours |
| trust | none — a record is a hint, and an address that does not answer is simply dropped |
| which relays | a built-in list of public relays, extended by the relay lists of cards it has read; the node's own card carries the relays it knows |
| publisher key | a node with a reachable address keeps **one key for its records**, so that a new record replaces the old one and its standing is readable; a node without a reachable address publishes nothing and therefore needs no key |
| relays written and read | 2–3 |
| lifetime of a record | 1 day |

**Reading and publishing are separate decisions.** A node reads the records
**while it is below 32 answering neighbours**, and only at the edges of
§11.8 — start, network change, a new neighbour, a removal. Reading stays a
last resort in the sense that it is never the first thing tried: sources
1–3 and the board (§11.8a) come first, and reading stops once 32 answer.
A node that has one reachable neighbour normally fills up from its board and
never reaches this step. **Publishing follows reachability, not need:** every node
that has an address through which it can be reached — a global IPv6, a
public IPv4, or a mapping its router granted (§7.3) — publishes its record,
whether or not it ever needed the relay itself; it does so at start and at
every network change. A node behind CGNAT without a mapping has no such
address and publishes nothing.

This is the point of the whole source. A node that is reachable and
well-connected is exactly the one a newcomer needs to find; if only
stranded nodes published, the relay would fill with the addresses that help
least.

**A record is kept alive, and that costs nothing while nothing changes.**
The node re-publishes at the edges of §11.8 and otherwise on a check whose
only purpose is to decide that nothing needs doing: the check suppresses
the publish while the addresses are byte-identical **and** less than 80 % of
the record's lifetime has elapsed. Only a genuine address change, or an
approaching expiry, produces a single write to 2–3 relays. Since the key is
stable, the new record **replaces** the old one at the relay; a node leaving
for good may additionally delete its record, because it still holds the key.

**Standing is readable, and it is a hint like everything else here.** The age
of the oldest record still carried under a node's key says how long that node
has been standing — the same quantity §10.3 gates relay eligibility on. It
carries no authority: an address that does not answer is dropped (§6.1),
however long it has stood.

The relay network is a start aid only:
once stable nodes of our own can be offered through the card, it may be
read in parallel or not at all.

This is the only part of the system that uses infrastructure it does not
own, and it is used for exactly one thing: learning an address to try.
Reading is the last resort: a node that finds neighbours by any of the
other three sources never reads from it (§11.8). No content passes
through it; the only thing held there is the published address record.

**It is a hint, not an authority.** A record carries no weight beyond
"somebody claims this address answers". Reachability is established by
trying (§6.1), and a signed record from an unreachable node is worth
exactly as much as an unsigned one.

The source can be switched off by the user. A node with it switched off
neither reads nor publishes; it finds neighbours by sources 1–3 alone.
## 12. What the interface shows

### 12.1 One way to send, so nothing to choose

The interface offers no delivery-mode control. There is one path (§3.3),
and whatever concealment the design provides, it provides on every
message. No per-chat setting, no explanatory dialog, no switch.

### 12.2 Per message

Exactly the four states of §9.1, and nothing that needs explaining:

| State | Shown as | User action offered |
|---|---|---|
| `resting` | pending mark | — |
| `in transit` | single mark | — |
| `delivered` | double mark | — |
| `failed` | warning mark | retry |

A recipient who is offline is shown as `in transit`, not as an error.

### 12.3 Per connection

One indicator, derived from what the node has actually observed (§6.2):
whether at least one neighbour has answered recently. No tier scale and
no derived score — a value the user cannot act on does not belong in the
interface.

The indicator is refreshed at most every 30 s, so that a rendering path
without hardware acceleration is not driven continuously.

### 12.4 The invitation is always available

The card (§15.2) is generated from the node's own keys and its LAN
address. It requires no network, no readiness state and no third party,
and is therefore offered from the first start onwards — including on a
device that has never reached another node.

Both hand-over forms are offered side by side, and both carry the same
bytes:

| Form | Use |
|---|---|
| QR code | the other person is present and can scan |
| one line of text | pasting into a chat, a mail or a message |

**Showing the card is universal:** every platform renders its own QR
code, desktops included. **Scanning follows the camera, not the
platform:** where a camera is present the app scans, and a phone held in
front of a desktop's webcam establishes the contact exactly as two phones
do. Where no camera is present, the text line carries it, passed through
any channel the two already share. **The card is always issued by the
device that holds the identity** — where that device runs a separate
service process, its front end obtains it over the local service channel.

### 12.5 Accepting a contact is an explicit act

An incoming request raises a question to the user, showing the requester's
name and verification level (§15.10). A contact exists only after an
explicit acceptance. The delivery layer exposes this as a single decision
point and holds no policy of its own.

### 12.6 Android

The application runs a foreground service with a persistent notification
carrying the live connection state. This is the supported path for
receiving messages in the background; it is not optional, and the
notification is not suppressible, because the service is what keeps the
socket alive.

### 12.7 Network switches

The network layer has exactly three switches, and their defaults are set
here, before any settings page is built:

| Switch | Default | Effect when changed |
|---|---|---|
| external records (§11.9) | on | off: neither reads nor publishes; neighbours come from sources 1–3 and boards only |
| router mapping (§7.3) | on | off: no mapping or pinhole is requested; the node is as reachable as without it and keeps no board unless otherwise evidenced (§11.8a) |
| fewer empty cover packets on W/LAN (§5.1) | **off** | on: on unmetered W/LAN cover carries only content; concealment there is given up |

There is no switch for cover as a whole (§5.1), and no switch for the rate
on metered mobile data (§5.3).
## 13. Identity Recovery

### 13.0 An Edge Case, Not Normal Operation (Reading Note)

**The most important sentence of this chapter comes first, because it frames
everything that follows: replacing a device is not a recovery case.**

If a device breaks, is stolen, or is replaced, that runs as an ordinary
device-set change under §14.4: the new device receives the Shared Key wrapped
by one of the living devices (**adding**), after which the old one is
**locked out**. No distress call, no recovery box, no network operation
involving strangers, no involvement of contacts beyond the pairwise
announcement that is due anyway.

**The decision a fresh install must make.** When Cleona is installed fresh
and the user does *not* create a new account but enters a recovery phrase,
the first thing to establish is whether **other devices already exist under
that phrase**.

* **Other devices exist** → this is *not* a recovery case. The data is
  completed from the same identity running on the other device (§14.4,
  device-set change). No distress call, no recovery box, no involvement of
  contacts.
* **No other device carries this phrase** → **this is the recovery case.**
  The data is rebuilt from the chats with the contacts, groups and channels
  the user was a member of.

The real recovery case is therefore exclusively: **all devices gone.**
House fire, theft of the entire household, loss while traveling without a
second device. This is the case the 24-word phrase exists for, and this is
the case this chapter is written for.

**Identities are not recovered one at a time.** Every identity is
HD-derived from the master seed, so the phrase brings all of them back
together — including ones the user has not touched for years. An unused
identity is therefore never a recovery case of its own: it is restored with
the rest, or it was never gone.

> **Implementation note.** A freshly created second identity has no
> contacts yet — but "no contacts" alone must not be read as "this
> identity was restored," because that is equally true of every
> brand-new identity that was never lost. Such an identity sits on a
> running device and is not a recovery case; treating it as one would
> ignite a §13.3 search on every attach, for something that never
> existed. The gate the implementation checks is
> `Identity.restoredFromPhrase` together with `restoreAwaitingPairing` —
> an explicit marker that a phrase was entered and pairing is pending —
> not the absence of contacts.

This yields an evaluation rule for everything that follows: **costs in this
chapter are rare costs.** An extra kilobyte in the recovery bundle weighs
heavily, because every user pays it on every renewal; an extra kilobyte in
the distress call weighs almost nothing, because a user sends it rarely or
never in a lifetime. §13.3 and §13.4 are therefore designed with different
degrees of frugality.

**Delivery path.** The bundle and the distress call are ordinary
deliveries under seed-derivable tags to the R responsible relays; the
restore broadcast is an ordinary pairwise delivery under `tag(K_AB)`.
The bundle, being > 10 KB, rides Reed-Solomon erasure coding rather
than fountain codes — fountain codes carry only files and updates
(AP-7), not message or recovery delivery — as described in §9 (today
K=7, N=11). Recovery traffic goes out through the store-and-harvest
leg of the delivery ladder (Chapters 7/8) by default: it is not
latency-critical, and it must not be session-linkable.

---

### 13.1 What the 24 Words Provide — and What They Don't

#### 13.1.1 What the 24 Words Provide

Four properties of the identity layer (§4) carry this chapter:

1. **24 words = 264 bits** (256 bits of entropy + 8-bit SHA-256 checksum).
   The word list is generated deterministically and phonetically
   (consonant-vowel pattern, pronounceable, memorable invented words) —
   modeled on the BIP-39 scheme (24 words, embedded checksum, one-step
   decoding), but with its own word list. The conversion is bidirectional
   with checksum validation (`seedToPhrase()` / `phraseToSeed()`) —
   `lib/core/crypto/seed_phrase.dart`.
2. **All identity keys are deterministically derivable from the seed —
   including the post-quantum keys.** ML-KEM-768 and ML-DSA-65 are
   generated via `mlKemKeypairDerand()` / `mlDsaKeypairDerand()`
   (`lib/core/crypto/oqs_ffi.dart:372` and `:548`, DRBG expanded from the
   seed). A seed restore regenerates **bit-identical** PQ key pairs; there
   is no PQ republication and no key change for the contact.
3. **`userId = SHA-256(kIdentityDomain ‖ ed25519_user_pubkey ‖ mldsa65_user_pubkey)`** (§4.1) —
   importing the 24 words into a fresh installation yields **per identity**
   the same UserID as on every other device with the same seed: one
   passphrase carries N HD-derived identities (§4.5.1), each with its own
   Ed25519 pubkey and hence its own UserID; §13.7 supplies the stopping
   criterion for the derivation. Verified fingerprints are stable per
   identity.
4. **The founding keys are stable** across every rotation (§15.2) — they
   are the anchor `K_AB` falls out of (§4.3).

#### 13.1.2 What the Seed Does **Not** Provide: One's Own Inbox

All devices of an identity share a **Shared Key** (§14.4), which on each
device lies wrapped with that device's own device key, and

```
inbox_key = HKDF(shared_key, "inbox")
```

The Shared Key is **random** and is re-rolled on every device-set change.
This is exactly where the device lock draws its force from (§14.4: “the
exclusion is structural, not rule-based") — and this is exactly what the
central statement of this chapter follows from:

> **If all devices are gone, no device still holds the Shared Key — and it
> cannot be derived from the 24 words alone.** There is exactly one place
> it still resides: in the recovery bundle held by the responsible relays
> (§13.3), whose tag line and seal are supplied exclusively by the seed. As
> long as the bundle lives — up to 31 days after the last renewal (§13.3.4)
> — the phrase therefore reopens the old inbox (§13.2.1). Only after bundle
> expiry is it finally closed (§13.2.2).

This is not a deficiency but the flip side of a property one wants to have.
An inbox key the seed could reconstruct at any time would be an inbox key a
locked-out device with seed access could reconstruct too. The price is
clearly named, small, and arises **only in the without-bundle case** — more
than 31 days with no device alive (§13.2.2): whatever still lay unharvested
in the old inbox at that point is lost — at most the delivery-window
traffic. In the normal case, with a bundle (§13.2.1), nothing is lost that
the delivery window still carries.

What is **not** lost: the identity — each identity's UserID and its
fingerprints (§13.1.1) — and the seed-derived key pairs; with the bundle
(§13.3), additionally the current key state and **the inbox itself**; and —
via §13.3 or §13.4 — the contacts.

#### 13.1.3 The Asymmetry After Entering the 24 Words

The recovering user possesses exclusively **self-referential** key
material. Everything that involves a second person or a second device is
missing; the local database is gone, and the network has nothing queryable
about persons (§23).

| Tag Family | Root | Available After Seed Entry? |
|---|---|---|
| Recovery bundle line (§13.3) | Seed | **yes** — fully |
| Distress-call and return-path line (§13.4) | Seed | **yes** — fully |
| Identity marker (§13.7) | Seed | **yes** |
| Old inbox line `σ_B = HKDF(inbox_key, epoch)` | Shared Key (random, §14.4) | **no** without a bundle — yes with a bundle |
| Own device tags `HKDF(K_own, "device" ‖ deviceId ‖ n)` (§14.1) | Shared Key | no — and moot, since no second device exists |
| Invite family `tag_I(i,e) = HKDF(K_inv(i), "cr" ‖ e)` (§15.3.2) | `invite_root` **plus** the local counters `g_inv` / `Highwater` | **only with a bundle** (K-7, §15.3.3) |
| **Pairwise tags `HKDF(K_AB, …)`** | founding keys of **both** sides (§4.3) | **no** — the other side is unknown |
| Receipt, prekey-refill, group-leg tags | all from `K_AB` | **no** — same root |
| Object-space families (§16) | public | yes, but with no bearing on one's own traffic |

**The core statement.** The recovering user can **harvest not a single
message** — harvesting is a tag match, and every tag of that user's
traffic hangs off `K_AB`, i.e., off knowledge of the other side. This is
the precise formulation of the chicken-and-egg problem: **The problem is
not where the mail is, but knowledge of the other parties.** There are
exactly two paths for this — §13.3 and §13.4.

---

### 13.2 The Inbox After a Total Loss

#### 13.2.1 With a Recovery Bundle: Back Up Immediately

The bundle contains the **Shared Key** (§13.3.2). From this, `inbox_key`
follows via HKDF; the recovering user harvests their own inbox line for
the current and the two previous epochs and keeps harvesting where the
last device left off. For the contacts, **nothing** changes at first: they
keep writing to the same address, and their messages arrive.

**During recovery, rotation is explicitly not performed.** The reason is
given in §13.6: a rotation in the middle of the process would have the
effect that every contact not yet reached would deliver into an inbox
nobody reads anymore.

#### 13.2.2 Without a Bundle: New Inbox, Old Content Lost

Without a bundle, the old Shared Key is unrecoverable. The recovering user

1. rolls a **new** Shared Key (making the device their sole device, N = 1,
   §14.4),
2. derives `inbox_key = HKDF(shared_key, "inbox")` from it,
3. communicates the new inbox to contacts via the distress-call return path
   (§13.4.3), or, once `K_AB` can be formed again, via the Restore
   Broadcast (§13.5.1).

**Declared loss, without sugarcoating:** whatever still lay unharvested in
the old inbox can no longer be opened by anyone. That is the delivery
window of undelivered traffic; typically nothing for an active conversation,
possibly everything that arrived in the meantime for an identity dormant
for weeks. Senders notice from the absent delivery receipt (§9) and can
resend — **a visible failure instead of a silent loss**, as in §14.4 for
the end of the transition window.

#### 13.2.3 When Nothing Is Found

Normative and identical in every case: **an unsuccessful search is not an
error and must not invent one.** If the recovering user finds no bundle,
that is the normal case of §13.2.2 and not a failure. The UI shows
“Recovery in progress — no response yet," not “failed"; the wording
follows the offline-is-not-an-error rule and the visibility rule from
§14.4.

---

### 13.3 Stage 1 — the Recovery Bundle

The bundle is the normal case: **no contact needs to be online, and none
needs to react at all.**

#### 13.3.1 Location, Tag Line and Delivery

```
recovery_key(i) = HKDF(seed, "recovery" ‖ i)                          // i = identity_index
σ_R(i, e)       = HKDF(recovery_key(i), "recovery-line"  ‖ epoch_e)
tag_R(i, e, j)  = HKDF(recovery_key(i), "recovery" ‖ epoch_e ‖ j)    // j = block index
```

**One bundle per identity.** Shared Key, device set, contact list,
and current key state are per-identity quantities (§14.4: “all devices
**of an identity** share a Shared Key"; §14.8: 5 devices **per identity**)
— and device sets can differ per identity. A master bundle across all
identities could not be fully built by a device that does not host a
given identity at all. That is why every device delivers its own bundle
**per identity it hosts**, into that identity's own line; the index
parameter follows the HKDF pattern of the HD derivation (§4.5.1). The
recovering user derives the indices in ascending order; the marker (§13.7)
supplies the stopping criterion.

- Both quantities are derivable **exclusively** from the seed. Neither a
  contact, nor a relay co-holder, nor a holder of the ContactSeed can
  compute the line. The bundle appears as an ordinary set of cover-traffic
  deliveries under single-use tags, planted to the R responsible relays.
- **Epoch definition.** The recovery epoch is **14 d** (distinct from the
  liveness epoch of §6/§9, which is far shorter). The recovering user
  harvests the line for **current + 2 previous** epochs (42 d coverage),
  which fully covers the bundle's 31-day TTL — no special case arises at
  the epoch boundary.
- **Finding without a directory:** the recovering user harvests `σ_R(i)`
  for the three epochs and matches via a local hash lookup against
  `tag_R` — the same mechanism as any other harvest, no special path, no
  query. Cost: **3 temporary harvest lines per identity** during recovery;
  they lapse afterward.

#### 13.3.2 Content — Minimal Bundle (normative)

**Decided: minimal bundle.** It contains only what the recovering user
cannot derive alone and what is needed to form `K_AB` and open one's own
inbox.

| Field | Purpose | Size |
|---|---|---|
| **Shared Key** (current) | `inbox_key = HKDF(shared_key, "inbox")` — one's own inbox (§13.2.1) | 32 B |
| **current User-KEM-SK** (X25519 + ML-KEM-768) | rotated KEM keys are random and not seed-derivable (§4.5, E-44) — without this entry, ciphertexts from the offline period would be unreadable | ~2.5 KB |
| **current identity sig SKs** (Ed25519 + ML-DSA-65) + continuity chain | these too rotate on lock-out and are not seed-derivable (§14.4); the chain evidences founding → current key | ~4.5 KB + chain |
| per contact: founding Ed25519 pubkey | `K_AB` derivation (§4.3) | 32 B |
| per contact: the contact's `inbox_key` | where the restore deliveries are placed (§13.5.1) | 32 B |
| per contact: display name + verification level | UI continuity, key-change detection (§15.7) | ~40 B |
| per contact: deletion marker / block state | prevents deleted contacts from resurrecting via recovery (§15.9) | 1 B |
| `g_inv`, `Highwater` of the invite line | closes K-7 (§13.10.3, §15.3.3) | 8 B |
| prekey pool identifier (current state) | basis for pool invalidation (§13.4.4) | 4 B |
| own `identity_index`, name + `active` flag | self-declaration of the identity (active index + display name) — the list as a whole arises from the derivation run over all indices (§13.7) | ~50 B |
| group/channel roster (IDs + member UserIDs) | rebuilding the sphere | variable |

Order of magnitude **per identity**: ~105 B per contact → **~21 KB** for
200 contacts, **~25 KB** with rosters; **~32 KB** with the identity's own
current key state (KEM-SK + sig SKs + chain). Being > 10 KB, the bundle
rides Reed-Solomon erasure coding as described in §9 (today K=7, N=11,
1.571× coding overhead; up to 4 holders may fail without losing the
bundle) rather than fountain codes — the same large-payload path as any
message > 10 KB. At a fragment size of ~1.1 KB that is ~29 source
fragments; with the 1.571× coding overhead, roughly **46 fragments per
identity and renewal**, monthly, at the 31-day TTL. On the wire, per the
cell packing of §9, that comes to roughly **1.863× the object** — for
example, a 262 143 B object rides 407 cells (477 KiB). Secondary
identities are typically contact-poor — their bundle sits correspondingly
far below these figures. The key state is a constant item (it does not
grow with the contact count) and changes nothing about the Rejected
verdict on the full bundle below — that concerned ~3.1 KB per contact.

**Rejected: full bundle.** It would additionally have carried the current
PQ pubkeys per contact — ML-KEM-768 pubkey **1,184 B** (`oqs_ffi.dart:196`)
+ ML-DSA-65 pubkey **1,952 B** (`oqs_ffi.dart:210`) ≈ 3.1 KB per contact,
**~640 KB** monthly at the 31-day TTL for 200 contacts, i.e., roughly
**30 times more expensive**. All it would have bought is that the
**first** delivery to a contact could already be sealed against that
contact's current KEM key instead of their long-term key (§4.6 stage 3).
Everything else — current pubkeys, prekey batch, profile data, history —
is supplied by the contact's response anyway (§13.5), just like the CR
response on first contact (§15.4). A small security gain at 30 times the
cost, at a point every user pays permanently.

#### 13.3.3 Sealing — and the Missing Forward Secrecy

The bundle is sealed **symmetrically**, with a key from the seed:
`bundle_key = HKDF(seed, "recovery-enc")`, AEAD as in §4.3.

This immediately follows the commitment from §4.6: **by construction, the
recovery bundle is not forward-secret.** Whoever obtains the seed and has
archived the responsible relays can read every bundle within the archive
window, and with it the complete contact list **and the Shared Key**. This
is not an implementation deficiency but the definition of the matter: a
backup that the seed alone is meant to open cannot have a key the seed does
not contain.

The responsible relays hold the bundle ciphertext replicated (m=3 family
redundancy, §9); an attacker who runs or compromises the relays that carry
the target's recovery tag can archive it. The KEX-Gate (§10) is what makes
grabbing the right relays hard: without the seed, the attacker cannot
compute `tag_R`. The exposure period is bounded by the 31-day TTL plus
margin (32 days) — but it renews with every bundle renewal, so it applies,
in effect, permanently to whichever state is most current.

Because the bundle also carries the Shared Key, a compromised seed opens
not only the contact list but also the **current inbox** (§4.6). This
does not fundamentally change the risk picture — whoever has the seed can
perform a recovery anyway and have the history delivered via §13.5 — but
it shortens the path from “elaborate takeover with a visible warning" to
“silent eavesdropping."

#### 13.3.4 Renewal, Carrier Set, Failure, and Hard Limit

- **Who delivers (every device, for each identity it hosts).** All
  devices have equal standing; each holds the Shared Keys of the
  identities it hosts and can form their `seed`-derived quantities,
  provided it possesses seed-derived material. Identities a device does
  not host do not concern it — those identities' bundles are maintained
  by their own devices. The identity sig keys lie under the Shared Key on
  every device and rotate along with lock-out (§14.4); there is **no
  privileged device**, every one may renew.
  As long as any device is alive, the bundle is renewed — there is no
  device whose failure halts the renewal.
- **Cadence: renewal with every recovery-epoch change, i.e., every 14
  days.** The TTL is 31 days, the recovery epoch 14 days. A renewal per
  epoch leaves a single missed date without consequence (14 + 14 < 31)
  and needs no timer of its own — it hangs off a tick the node keeps
  anyway (§19: no polling).
- **Visibility.** The bundle state belongs in the UI, following the
  pattern from §14.4: “Backup valid until <date>" or “Backup expires in
  N days." An expired bundle must not lapse silently.
- **Hard limit.** If **all** devices have been dead for longer than 31
  days plus a renewal margin, the bundle has expired off the relays.
  Stage 2 (§13.4) then takes over. This limit is unavoidable: the relays
  are a 31-day medium, and a longer-lived durable-object class for the
  bundle is ruled out — a recovery bundle readable only by its owner
  carries no checkable proof, and a deadline-bound type producible
  without limit across the network is exactly the class excluded for the
  identity tombstone.

---

### 13.4 Stage 2 — the Distress Call (Restore-Beacon)

#### 13.4.1 Why This Stage Must Exist

Stage 1 fails precisely when all devices have been dead for more than a
month. Without Stage 2, the commitment “the 24 words restore" would be
limited to one month, and that would have to read the same in onboarding
as in the architecture.

The distress call is a **consented exception**: a self-statement about
one's own identity, explicitly permitted as one of the exhaustive,
documented self-publications on the person side. This chapter invents no
new exception; it fills in the one already provided for.

#### 13.4.2 Construction: Delivery Under a Seed-Derivable Tag (normative)

**Decided: the distress call is a delivery under a seed-derivable tag to
the R responsible relays — no network-wide subscription, no global Merkle
index.** (Rejected: a network-wide subscription every node would have had
to hold for other people's distress calls — it would have permanently
cost decoy budget — and a global Merkle index of durable objects. Neither
is used; the distress call rides the same delivery path as everything
else.)

```
Identifier:  H = SHA-256(kIdentityDomain ‖ "restore" ‖ founding_pk_A ‖ epoch_e)
```

- The object is a **self-statement about one's own identity**. It carries
  no third-party state about persons.
- It is delivered to the R responsible relays under the tag `H`. A
  contact checks by harvesting under the self-computed `H` of their
  contacts — they know each contact's `founding_pk` and can form `H`.
  This costs **no additional harvest line**; the decoy budget stays
  untouched.
- Scope of the check: 1 identifier per contact and epoch, so 3 with ±1
  tolerance; **600 entries** for 200 contacts against the regular
  expectation set — **+2.5%**, uncritical.
- **Rejected: network-wide beacon space as a harvest line.** It would have
  permanently cost every node a decoy slot and, as the network grew, would
  have spread the beacon tags of one's own contacts across many prefixes
  — the subscription problem would have returned.
- **Rejected: no distress call.** Then the commitment “24 words suffice"
  would hold for only 31 days. Honest and cheap, but the commitment is the
  foundation of the entire backup concept, because the 24-word phrase is
  the only cold backup (§13.8).

**Size and form.** ~320 B — the order of magnitude of a role registration.
That is also its **form**: 23 B content + 96 B Ed25519 + `k = 2`
first-acceptance acknowledgments at ~100 B each. The distress call adopts
it, because it has the same two problems: it needs carried proof and an
anchor against backdating (the acknowledgment names the previous epoch's
identifier). **The payload part is larger than 23 B** — it carries the
return path and the pool identifier (§13.4.3/§13.4.4), on the order of
~80 B — so the object comes to **~380 B**.

**Anti-backdating without a Merkle index.** The `k = 2` first-acceptance
acknowledgments come from **independent relays in different partitions**
(E-35). Each acknowledgment is a relay-signed statement “I hold this
distress call and the previous epoch's identifier I saw was X." Two such
from different partitions make backdating expensive without requiring a
network-wide convergent index root. Cross-partition relay attestations
provide the anti-backdating property instead of a global
Merkle-convergence anchor: weaker in the global sense, but sufficient for
a one-time, 31-day, self-statement event, and it avoids the orphaned
global-index machinery (§27).

**What the delivery reveals — declared.** The tag `H` is an opaque hash:
whoever does **not** have `founding_pk_A` sees “someone is recovering," not
“A is recovering." §14.5 rejected a device-set object for a related
reason — the difference is that the distress call reports a **one-time
event** and not an ongoing state, and that it is derivable only by
whoever already has the pubkey anyway.

#### 13.4.3 The Return Path

The contact can form `K_AB` **alone** — they have A's founding pubkey
(§4.3). What they lack is the **location**: A's old `inbox_key` belongs to
the dead Shared Key; they don't know the new one. The distress call
therefore carries it:

```
restore_key = HKDF(seed, "restore")                       // derivable only by A
σ_RR(e)     = HKDF(restore_key, "restore-resp-line" ‖ e)
tag_RR(e)   = HKDF(restore_key, "restore-resp" ‖ e)       // ONE tag, many deliveries
```

- The distress call **carries** `σ_RR(e)` and `tag_RR(e)` in its payload.
- `tag_RR` is a family following the **R-26 pattern** (many deliveries
  under one tag) — the same concession the invite family (§15.3.2) makes.
  The single-use-tag invariant deliberately does not apply here; it is a
  collection inbox for a limited time.
- A harvests `σ_RR` during recovery: **1 temporary harvest line**.
- **Sealing the response:** the contact seals against A's **long-term KEM
  key** — stage 3 of the ladder from §4.6. This works because this key
  falls deterministically from the seed (§13.1.1) and A's prekey pool was
  lost along with the devices. The restore response is, besides the total
  exhaustion of the prekey pool, the second legitimate occasion for
  stage 3 (§4.6).
- **Content of the response:** the contact's current `inbox_key` (so A
  can write pairwise immediately), their current pubkeys, a fresh prekey
  batch, display name — in essence the payload of a CR response (§15.4).
  From then on everything runs under `tag(K_AB)` and is ordinary traffic.

**Why A's new `inbox_key` doesn't simply appear in the distress call.** It
would then be computable by anyone who possesses `founding_pk_A` — and
**permanently** so, not just for the duration of the process. A stranger
could harvest A's inbox line and observe its volume. `tag_RR` leaks less:
whoever reads the distress call sees the responses sitting there, but
cannot read them (sealed hybrid against A's long-term KEM), and the leak
ends with the process.

**Residual leak, declared.** Whoever sees the distress call knows `tag_RR`
and can place deliveries under the family (junk) and **see** the
responses — but not **read** them. Category “acquaintance with pubkey,"
narrowly time-bounded to the restore duration.

#### 13.4.4 Pool Identifier: the Silent Prekey Break

**The finding.** One-time prekeys are **random**, not seed-derived
(§4.6). All `sk_i` are lost along with the devices. The contacts,
however, keep holding their cached prekey batches from A and keep sealing
with them — for up to **15 days** (§4.6, retention). These deliveries are
**unsealable** for A, and the sender notices only from the absent delivery
receipt. That is silent message loss — precisely the error class §14.4
explicitly excludes.

**Decided.** The distress call carries a **pool identifier**: a monotone
`prekey_pool_epoch`. A contact who sees an identifier higher than the one
stored discards **all** cached prekeys from A and falls back to stage 2
of the ladder until the next refill (§4.6, daily granularity). Normative:

1. The pool identifier runs **not only** in the distress call, but **also
   in the Restore Broadcast** (§13.5.1) — in the bundle case there is no
   distress call, and the break exists there just the same.
2. The Restore Broadcast delivers a **fresh batch** along with it, so no
   gap arises between discarding and refill.
3. The sender **cannot** notice the failure — the only feedback would be
   the absent delivery receipt. The repair is therefore exclusively
   preventive on the receiver's side, and the rest is declared loss in the
   window between device loss and the distress call/broadcast.
4. **Interaction with the shared pool:** the pool is shared across
  devices (§14.3). On lock-out it is discarded and refilled anyway
  (§14.4) — the restore is the same operation with N = 1; no new mechanism
  is added.

**Abuse surface, named.** A forged distress call causes contacts to
discard valid prekeys. The damage is **one stage of FS for the duration of
the refill** and heals itself, because the refill runs under `K_AB`,
which a forger cannot form. It is thus small enough not to force the
signature class of the distress call (§13.4.5).

#### 13.4.5 Authenticity of the Distress Call

By its class, the distress call is a **key-continuity proof**, and the
signature rule (§4.4.3) prescribes the **hybrid** signature (Ed25519 +
ML-DSA-65) for this class. That collides with the size figure: the
ML-DSA-65 signature alone is **3,309 B** (`oqs_ffi.dart:216`); a
hybrid-signed distress call would come to **~3.6 KB** instead of ~380 B
— roughly **ten times** as large, in a class with a hard budget.

**Why Ed25519 suffices on the distress call:** the contact responds
exclusively **sealed against A's long-term KEM key** (§13.4.3) — hybrid,
X25519 + ML-KEM-768. Whoever forges the distress call without having the
seed thus only causes a response to be produced that they cannot read.
**The confidentiality barrier is the sealing, not the signature.**
Ed25519 therefore suffices on the object itself.

What a classical break still buys: triggering response traffic, the
signal “A is recovering" to whoever already has the pubkey anyway, and
the prekey discard from §13.4.4. No data access. That is a declarable
residual situation — but it is a **deviation from the hybrid-signature
rule**, declared in §4.4.3 and §23.7.

For the **Restore Broadcast** (§13.5.1), the continuity property **H-2**
applies: hybrid inner signature (Ed25519 + ML-DSA-65), checked against
the keys stored at the contact, **before** data is released — a break or
theft of the classical key alone is therefore not enough for a takeover
including a history dump. And because the PQ keys are deterministic
(§13.1.1), the stored ML-DSA pubkey matches on a genuine recovery without
any key exchange at all.

#### 13.4.6 Lifetime and Abuse Bolt

| Property | Value |
|---|---|
| Proof | self-signature over one's own identity + `k = 2` first-acceptance acknowledgments from independent relays in different partitions, acknowledgment names the previous epoch's identifier |
| Lifetime | **31 d**, no renewal |

- **31 d, not renewable** — and the prohibition on renewal is the abuse
  bolt: a distress call is an event, not a state. Whoever is not done
  after 31 days sends a new one (new epoch, new identifier).
- **R-7 concern, named openly.** The identity tombstone was struck as a
  durable object because the self-signature of a **freely creatable**
  identity yields a deadline-bound type producible without limit. The
  distress call has the structurally same problem. What distinguishes it:
  it is bound to `k = 2` first-acceptance acknowledgments from
  **different partitions**, which makes mass production more expensive
  but does not prohibit it. → **Decided: deadline sub-budget (2 MB), with
  observation** — if the space collides with the jury cases (~100 open
  cases fill the 2 MB), it moves to its own budget line.

---

### 13.5 Restore Broadcast and progressive recovery

From the moment `K_AB` is computable again for a contact — via the
bundle (§13.3) or via the distress-call response (§13.4) —, the entire
remaining procedure is **ordinary traffic**. §15.6 already establishes
this: the Restore Broadcast runs under the pairwise tag `tag(K_AB)` and
needs no KEX-gate exception.

#### 13.5.1 The broadcast

- **One** delivery per contact under `tag(K_AB, A→C)`, to that contact's
  responsible relays with **m=3 family redundancy** (§9). One delivery
  serves all of the recipient's devices (§14.2); the relays hold it
  until harvest.
- Content: `oldUserId = newUserId` (the UserID is stable, §4.1), current
  pubkeys, **new `inbox_key`**, **fresh prekey batch**, and **pool
  identifier** (§13.4.4), display name, timestamp, hybrid inner signature
  (H-2, §13.4.5).
- In the bundle case, **zero** contacts suffice, and in no case must a
  contact be online **simultaneously**: the delivery sits on the relays
  for up to the delivery window; simultaneity does not exist in the model.
- The contact processes receipt through **§15.7 key change detection**
  — the only permitted reaction path. In a genuine seed recovery, **no**
  identity key changes (deterministic derivation); what changes is
  `inbox_key`, prekeys, and the pool identifier. The IPC event
  `contact_restore_detected` fires, and the UI shows “[Name] has set up a
  new device" — a recovery is made visible to the contact, never adopted
  silently.

#### 13.5.2 Progressive recovery (manifest + pull)

Progressive recovery runs in three phases:

| Phase | Content | Carrier |
|---|---|---|
| 1 — Header | Contacts, group memberships, channel subscriptions — the recovering user's contact list is built immediately | one delivery under `tag(K_AB)`; a large roster is chunked to **≤ 32 KB** like the manifest below and stays in-band |
| 2 — Manifest | The contact announces every message it knows as an entry — `(messageId, timestamp, conversationId, senderId, type, size hint)`, without the message body. Chunks of **750 entries, ≤ 32 KB**, ~42 B/entry compressed | one chunk stays **under the built split bound** of the delivery layer (`frame_split`), so recovery stays **in-band and bulk-free**: it must not be session-linkable (§13.0), and therefore must not depend on always-on holders either (E-86). |
| 3 — Pull | The recovering user deduplicates the manifests against IDs already present and pulls what's missing in batches: `RESTORE_FETCH` (max. 50 IDs per request) / `RESTORE_DELIVER` with the message payloads; every delivered message is persisted immediately, partial progress is durable | delivery pairs under `tag(K_AB)`; large payloads via the transfer stages (§9) |

Three rules of the application logic are normative:

- **Cross-source deduplication.** In groups, N members announce the same
  messages; for each message exactly **one** primary source is chosen —
  preferably the conversation owner —, further reporters are Alternates
  and take over automatically if delivery does not arrive. Every ID is
  pulled exactly once.
- **Resumability.** Assignment and fetch queues are persisted; after an
  interruption, open fetches are reissued on restart. Unanswered fetches
  sit on the relays for up to the delivery window.
- **Deleted is deleted.** What a contact has deleted is missing from its
  manifest; in groups, every member with history serves as an alternative
  source. If the sole holder has deleted it, the history is really gone
  — data sovereignty takes precedence over recovery.

**Group restore.** Phase 1 delivers the full member roster per group,
including the crypto pubkeys per member (`RestoreGroupMember`). With the
stateless per-message KEM, the recovering user can therefore deliver to
all members immediately.

**Wipe before recovery.** Before the seed is entered, any existing
profile data is deleted completely. Recovery **takes the place of** an
identity; it does not merge into a running one.

**Distinction from multi-device.** A second device is enrolled, not
recovered (§14.6); entering the seed on another device is not a setup
path but a recovery procedure.

#### 13.5.3 Cost of recovery

Every message delivered back is a delivery and costs the **responding
contact** bandwidth. At ~590 B per delivery, 200 messages of history is
~118 KB — negligible. A history of 50,000 messages would run to ~30 MB.
The one responding pays bandwidth. That is an argument for a prioritized
pull (default: newest first) and **against** an automatic full pull.

**How a mass restore travels (E-87).** In-band is the
**default**: chunked to ≤ 32 KB like the manifest (§13.5.2), the drip
restore runs newest-first and is usable long before it finishes. The
**bulk lane (§9.3) is offered as a shortcut only**, with the same
per-transfer consent as any Secure media (§12) — it is far faster and
**linkable**, and a recovery is exactly the moment at which a user should
not lose anonymity without being asked.

#### 13.5.4 Anti-abuse

The following protective measures apply:

- **Hybrid inner signature (H-2):** the Restore Broadcast is checked
  against the keys stored at the contact before data is released
  (§13.4.5).
- **Visibility of the key change:** via §15.7 — a recovery is made visible
  to the contact, never adopted silently.
- **Rate limits as a receiver-side harvest rule:** the relays carry no
  sender state; the limits act in the acceptance logic of the responding
  contact. Normative: at most **1 broadcast per UserID per 5 min** is
  honored; `RESTORE_FETCH` is served with at most **8 requests per
  minute**, and only if a valid broadcast has been received in the last
  24 h.
- **Sealed transfer:** every delivery is sealed (§4.3) — including
  `RESTORE_BROADCAST` and `RESTORE_RESPONSE`.
- **The KEX gate protects structurally:** an attacker without `K_AB`
  cannot place a Restore Broadcast that a contact would even harvest
  (§4.3). All it can forge is a **distress call** — and its effect is
  bounded by §13.4.5/§13.4.4.

#### 13.5.5 Last stage: contact rebuild

If both fail — no bundle, no distress-call response —, what remains is
the path §15.8 already names for founding-key compromise: **contact
rebuild** via a fresh ContactSeed (§15.5) over a third-party channel.
The identity (UserID, fingerprint) is the same; the verification levels
and the history are gone. Not an elegant floor, but an honest one — and
it must be named as such in onboarding.

---

### 13.6 Completion of recovery and rotation (normative)

After a restore, the device set is **unclear**: the recovering device is
new, the old ones may be alive (theft) or dead (water damage). This
cannot be derived from the seed. Decided:

**Rotation happens — but only after recovery is complete.**

- During the procedure, everything runs over the **old** shared key
  (bundle case). If rotation happened immediately, every contact not yet
  reached would deliver into an inbox no one reads — the recovery would
  cut off its own inflow.
- The trigger is an **explicit completion in the assistant**: “12
  contacts recovered — finish and renew keys", with a **reminder after a
  few days** if the user leaves it be.
- **Until then, a stolen device can read along, and this must be made
  visible.** The assistant states this in the same language as §14.4:
  “As long as recovery is running, old devices can read along."
- The rotation itself is an ordinary device-set change per §14.4 with
  N = 1: new shared key, new user KEM key, prekey stock discarded and
  refilled, pairwise announcement to all recovered contacts, a
  transition window ending after the delivery window at the latest.
- **In the no-bundle case, this step is dropped**: a new shared key was
  already rolled at the start there (§13.2.2), there is nothing to
  rotate. Contacts not reached stay not reached — their state is the same
  as before completion.

**Quorum (§14.5).** An emergency key rotation after the restore requires
countersignatures from `max(2, ⌈N/2⌉)` devices, which the recovering user
does not have. The **visibility principle** from §14.5 applies (legacy
case, visible warning, the key is applied anyway). Likewise, the device
set shrinks from N to 1 **without** countersignatures — by construction,
the case §14.5 treats as “unknown device set".

---

### 13.7 Multi-identity: derivation instead of a directory

There is no directory of one's own identities in the network — neither a
queryable object nor a storage location; nothing about persons is
queryable (§23).

**Decided:** all identities are derivable from the passphrase (HD
derivation via `identity_index`, §4), **each identity carries its own
recovery bundle in its own tag line** (§13.3.1), and a **marker per
identity serves as the stop criterion**.

```
tag_M(i, e) = HKDF(seed, "identity-marker" ‖ i ‖ epoch_e)
```

- The marker sits in the bundle line of the respective identity
  (`σ_R(i)`, §13.3.1) and is delivered along by the same renewal run —
  **extra cost: one delivery per identity and renewal.** It is derivable
  exclusively from the seed, so it leaks nothing. Compared to the bundle
  itself, it is the **cheap existence probe**: a single delivery per
  index instead of ~42 (§13.3.2), before the actual bundle harvest begins.
- **Rule:** the recovering user derives indices in ascending order and
  harvests the marker for each index. The **first index without a marker**
  ends the derivation — the stop criterion.
- The recovery bundle of each identity carries its own `identity_index`,
  name, and `active` flag (§13.3.2). The list of all identities is the
  result of the derivation run, not an object of its own; it is readable
  only with seed-derived keys.
- **Without a bundle and without a marker** — i.e., after more than 31
  days with no living device — what remains: the user recalls how many
  identities they had, and the recovery run is carried out once per
  index. One distress call per identity, because `founding_pk` differs
  per index (§13.4.2). An index candidate cannot be checked without a
  marker; there is no target value against which it could be checked.

---

### 13.8 Limits of recovery

There is **no social-recovery procedure**. The 24-word phrase is the
**only cold backup**; multiple devices (§14.8) are the practical
protection against device loss.

**No set of other people can restore an identity — in no number, in no
combination, under no threshold.** There is no key material held in
trust, no split secret deposited with third parties, and no procedure by
which contacts vouch an identity back into existence. Whoever restores
an identity holds the phrase or a surviving device; there is no third
route, and none is planned. What contacts do carry is the *content* side
after a restore — the bundle (§13.3) and the distress call (§13.4) —
never the identity itself.

From this follows a declared limit: **the scenario “phrase and all
devices lost" is not covered.** Without the phrase and without a
surviving device, there is no recovery.

**Communication obligation:** this limit must be communicated to the user
actively and unambiguously during onboarding and at the seed display.

---

### 13.9 Assurances of recovery at a glance

- **In the bundle case, zero contacts suffice.** In no case must a
  contact be online simultaneously; a restore delivery sits on the relays
  for up to the delivery window (§13.5.1).
- **The 24 words always restore the identity** — UserID and fingerprints
  per identity (§13.1.1). The contacts come via the bundle (§13.3) or the
  distress call (§13.4), the inbox via the bundle (§13.2.1); only without
  a bundle is the old inbox content lost (§13.2.2).
- **One delivery per contact.** The Restore Broadcast serves all of the
  recipient's devices with one delivery (§13.5.1, §14.2).
- **All restore types are sealed** (§4.3, §13.5.4).
- **PQ keys are deterministic:** a seed restore regenerates bit-identical
  PQ key pairs (`oqs_ffi.dart:372,548`, §13.1.1); there is no key change
  at the contact.
- **Cached prekeys of a recovered contact are discarded:** the pool
  identifier forces the discard (§13.4.4).
- **Recovering is the edge case, enrolling is the standard path:**
  replacing a device is a device-set change per §14.4; this chapter
  applies only when all devices are gone (§13.0, §14.6).

---

### 13.10 Interactions

#### 13.10.1 Devices, lock-out, and rotation (§14.4/§14.5)

See §13.6. Core statements: the recovering user is an **ordinary device**
(all devices have equal standing); rotation happens only at explicit
completion; §14.5 treats the restore as a legacy case with a visible
warning.

#### 13.10.2 Prekey pool (§4.6, §14.3)

See §13.4.4. The pool is shared across devices; a total loss destroys it
completely; the pool identifier in the distress call and the Restore
Broadcast is the only remedy, because the sender cannot notice the
failure.

#### 13.10.3 Chapter 15 / finding K-7

`docs/analysis/v4_redteam_kap8.md:521-598` demonstrates that
`invite_root` is **not** reconstructible after a seed restore, because
`g_inv` is a purely local counter. **Decided:**

- **With a bundle:** `g_inv` and `Highwater` are in it (§13.3.2); the
  invite line is re-armed, indices `0 … Highwater + 32` (window `+32`
  confirmed). Printed invitations survive the device loss.
- **Without a bundle: fail-closed.** All existing invitations are
  invalid, new ones are issued. This only costs convenience and is the
  only claim one can honestly make without the counter.

Chapter 15 is thus explicitly dependent on this chapter; the maturity box
in chapter 15 already states this.

#### 13.10.4 Cold start

A recovery typically runs on a **fresh installation with no remembered
neighbours** and without a card to redeem. It therefore finds neighbours
through the local segment and, where that reaches nobody, through the
external records of §11.9 (§11.8). The restore is the case that depends on
these two sources most.

#### 13.10.5 Delivery states (§9)

All restore deliveries follow the four states of §9.1 — `resting`,
`in transit`, `delivered`, `failed` — with the E2E receipt (§9.2)
flipping `delivered`. There is **no** restore-specific
progress state and no timer retry. The UI shows progress as harvested
manifest/deliver deliveries, not as a progress bar.

#### 13.10.6 Anchoring in other chapters

The rules of this chapter are anchored at the following points outside
it: §4.4.3/§23.7 (Ed25519 declaration of the distress call), §4.3 (distress
call as a self-statement delivery), §4.6 (restore response as a second
stage-3 trigger; the bundle carries the shared key), §14.3/§14.4 (pool
identifier, rotation only after completion), §14.5 (restore as the
standard case of an unknown device set), §15.3.3 (K-7 cross-reference).

---

## 14. Multi-Device

### 14.1 UserID and DeviceID are two separate identifiers

UserID and DeviceID are two separate identifiers. One identity (UserID)
can live on multiple devices, and every device carries its own device
identifier (DeviceID) along with its own device key pair, which is
generated locally and is **not** derived from the seed (§14.6.1) —
device identity is disposable, user identity is not. The DeviceID is
not an addressing means; it carries exactly the following tasks:

| Task of the DeviceID | Reference |
|---|---|
| Device revocation: the revocation delivery names the device | §14.4 |
| `DeviceDelegationCert` — binds the per-device sig subkey to the identity | §14.6.2 |
| Quorum count at lock-out and at emergency key rotations — the quorum counts devices | §14.4, §14.8 |
| Twin-sync attribution (“which of my devices") | §14.7 |
| Local device-key management (`device_keys.enc`) | §14.4 |

In short: the DeviceID is a **subject**, not a **signpost** — for
authorization, revocation, and attribution.

`sendToDevice()` means: seal under this device's tag. Since one's own
devices hold shared secrets anyway, the device-scoped tag
`HKDF(K_own, "device" ‖ deviceId ‖ n)` is derivable without any lookup
— it is needed for the per-device payloads of twin sync (e.g.,
delegation rotation).

### 14.2 One delivery serves all devices

All devices of an identity hold the same receiving material:

- All devices share the `inbox_key` → they harvest **the same line**.
- All devices share the user KEM SK → all can unseal **the same cell**.

**One delivery thus serves all of the recipient's devices.** The delivery
path has no device level: no resolver, no iteration over devices, no
per-device delivery states, no “1 of N delivered" special case. One
person costs one delivery (§9), regardless of how many devices they read
on.

Twin sync (17 content types, §14.7), the delegation model (sig subkeys,
delegation certificate), device lock-out, and the lock-out quorum
(§14.8) all run over the same delivery path (§7, §8).

---

### 14.3 Prekey pool and multi-device (closes O-11)

The forward-secrecy pool (§4.6) requires the recipient to **destroy**
the one-time prekey **after use**. With multiple devices sharing key
material, this applies:

- Prekey secrets must be available to all devices — otherwise only one
  device could unseal, which breaks §14.2.
- If device A consumes a prekey and deletes it, a temporarily offline
  device B keeps holding it.

**Decided: shared pool with consumption reporting.** All devices share
the stock; whoever consumes a prekey reports it as a **twin-sync content
type** (§14.7, type 15) to the remaining devices, which then delete it.
Forward secrecy is thus as sharp as the sync latency between one's own
devices — **seconds to ~5 min** on reachable platforms (seconds when the
direct delivery stages carry it, §7; up to ~5 min via the mailbox stage,
§8), indeterminate on iOS-closed, so minutes instead of days. This is
the honest version of
the commitment from §4.6 for multi-device users: per-message granularity
holds toward third parties; toward a seized **own** second device,
sync-latency granularity holds.

**At lock-out, the entire stock is discarded and refilled** (§14.4).
Without this, the KEM rotation would not hold: a locked-out device
would still hold the old one-time secrets and could use them to open
anything still sealed against them. The refill runs as an ordinary
prekey-refill delivery under `HKDF(K_AB, "prekey-refill", …)` (§4.6,
delivered through the mailbox stage by default) to every contact — it
costs nothing new, just one round.

**Rejected: per-device pools.** They would give full per-message
security even toward one's own devices, but would require sealing
every message separately for every device of the recipient — the
fan-out §14.2 excludes would come back through the back door. The third
variant (prekeys only on one privileged device) is out, because all
devices have equal standing.

**Consequence for chapter 13.** A total loss destroys the pool
completely, and contacts keep sealing against dead prekeys for up to
**15 days** (§4.6, retention) — silent message loss. Against this stands
the **pool identifier** in the distress call and in the Restore
Broadcast (§13.4.4), which forces the contact to discard. The mechanism
is the same as at lock-out, just with N = 1.

---

### 14.4 Device keys, lock-out, and rotation

**No primary device.** All devices of an identity have equal standing.
They share a **shared key** — the everyday key that carries access to
one's own data. It sits with every device, **wrapped with that
device's own device key**:

```
for each device d:   wrap_d = Enc(device_key_d, shared_key(n))
inbox_key            = HKDF(shared_key(n), "inbox")
```

The seed from the 24 words carries the **identity** (§4.1) and opens
the recovery bundle (§13). It is **not** the everyday key and need not
sit permanently on any device.

**Rotation.** The shared key is rerolled on **every change to the
device set** and rewrapped for the then-valid set:

| Trigger | Effect |
|---|---|
| **Add a device** | New shared key, wrapped for **all** already-enrolled devices **and** the new one. No one loses access |
| **Lock out a device** | New shared key, wrapped for all **except** the locked-out one. It holds the old key and its own device key — it can neither derive nor unwrap the new one |
| **Routine hygiene** | Like “add", without a device-set change |

Because the new key is random, the locked-out device is helped by
neither computing time nor prior knowledge. That is the load-bearing
property: **the exclusion is structural, not rule-based.**

**What rotates along.** A rotation of the inbox key only hides **where**
the mail sits, not **what** is in it — the relays hold ciphertext
replicated, and a locked-out device would still hold the user KEM key.
That is why this rotates along at **lock-out** too; on mere adding, this
is not needed, because no one is excluded.

**The identity signature keys also rotate along at lock-out.** They sit
— like the user KEM SK — **under the shared key on every device**; only
this way can every device issue delegation certificates alone (“adding
may be done by any device alone"). Without co-rotation, a locked-out
device would retain the ability to sign in the identity's name. On
adding and on routine hygiene, they do **not** rotate (no one is
excluded — the same rule as for the KEM key). Rotated sig keys are —
like rotated KEM keys (§4.5) — random and **not seed-derivable**: the
founding key remains the identity anchor from the seed; the current
operational state, complete with continuity chain, belongs in the
recovery bundle (§13.3.2).

> **Interplay with the prekey pool.** For the KEM rotation to hold, a
> locked-out device must not keep working with existing one-time
> prekeys. That is why the shared pool is **discarded and refilled** at
> lock-out (§14.3). O-11 is thereby closed.

*The co-rotation described in this section is triggered by the
revocation. Which keys rotate, where the trigger sits, why the prekey
discard is currently a no-op, and the up-to-48-hour window that the
rotation does **not** close are all set out in §14.10.*

**Who is allowed to do what.** A stolen, unlocked device is a **valid**
member — the rotation does not protect against it, only against those
already locked out. Therefore:

- **Any device may add alone.** The rotation due in this case wraps for
  all already-enrolled devices too; no one loses anything, and a thief
  gains nothing they did not already have.
- **Lock-out requires a quorum** of `max(2, ⌈N/2⌉)` devices (counting
  rules in §14.8). A thief with one device cannot lock out the rest with
  it. At exactly one device, the rule does not apply — there, that one
  device suffices.

Rationale for the asymmetry: an additional device does not harm the
owner, lock-out does. That is exactly where the protection sits.

**How contacts learn of the rotation.** Only **pairwise**: `K_AB` is
independent of the shared key, every contact is reached individually.
A public object is out — it would be third-party state about a person
(§16 public-object rule) and would make an identity's inbox attributable
network-wide.

**Verification levels at sig rotation (normative).** Every lock-out
operation is a key change toward every contact. The pairwise
announcement (§14.5, path 2) carries for this the new sig pubkey, a
**hybrid-signed continuity proof** old→new (§4.4.3 lists key-rotation
continuity proofs as an ML-DSA mandatory case), and the quorum
countersignatures. The contact's verification level (verified/trusted)
**is retained** if **both** are present: (i) the continuity proof with
the old key **and** (ii) the lock-out quorum `max(2, ⌈M/2⌉)` (§14.8).
If either is missing, the visibility principle applies (§14.5): level
drops back, visible warning, the rotation is applied anyway.
Rationale: a stolen device alone can forge (i) — it holds the old key
—, but not (ii).

**The transition (normative).** A rotation does not take effect
instantly — neither at one's own devices nor at the contacts. Both
sides need a window in which **the old and the new key are valid at the
same time**.

*Device side.* The triggering device places the **package of wrapped
new keys** — one for each remaining device — into the **old** line.
At this point, every device is still reading there; each one picks up
its own packet and opens it with its own device key. A device that is
switched on again only weeks later still finds it there (management-TTL
delivery, 31 days). A locked-out device sees the same package and
cannot open a single packet — it therefore needs no channel of its own
for the distribution. Every device keeps the old key until it has the
new one, and reads **both** lines during the transition.

*Contact side.* Contacts learn of the rotation via the pairwise
announcement. Until they have harvested it, they keep writing to the
old address. If the old line were closed immediately, their messages
would be **silently lost**.

> **Honest consequence that falls out of this.** A device lock does not
> take effect **immediately, but per contact** — namely as soon as that
> contact has harvested the announcement. As long as a contact keeps
> writing to the old address, the locked-out device can read those
> messages along. This is not a negligence of the design, but the
> consequence of there being no central place where a lock could be
> deposited once and for all.

**End of the transition.** The old line is closed **as soon as all
contacts have acknowledged the announcement, but at the latest after
the delivery window** (one recovery-epoch lifetime, 14 days). In the
normal case, everyone is through after one to two days; the deadline
only kicks in for contacts who never come back — otherwise a single
orphaned contact would hold the old line open forever, and with it the
locked-out device in play. Anyone who still writes to the old address
after closing notices it by the missing delivery receipt and can send
again: a visible error instead of a silent loss.

**Visibility (normative).** The transition belongs in the UI, not in a
footnote: “Device locked — fully effective once all contacts are
informed (3 of 47 still open)". A lock that is visibly not yet in
effect is more honest than one that suggests a security it only reaches
after days.

For **adding and routine rotation**, the same window applies, but
without urgency there: no one is excluded, and the old line may be read
along until the end of the regular recovery-epoch coverage (42 days).

**Replacing a device is not a recovery case.** If a device breaks and a
new one is set up, that is an ordinary **add**: the new device gets the
shared key wrapped by one of the living devices, after which the broken
one is locked out. No distress call, no recovery box, no network
procedure with strangers. The real recovery case (§13) is exclusively:
**all devices gone** — and there, rotation happens only **after full
completion** of the recovery (§13.6), otherwise contacts not yet reached
deliver into the void. The entire chapter-13 machinery is thus an edge
case, not normal operation — that is to be kept in mind when reading
chapter 13.

### 14.5 Device proof and co-authorization

**The device set is not queried, but carried along.** There is no place
where the authorized devices of an identity could be looked up; every
contact holds the state locally and learns of changes to it because
they are delivered to it.

**Two paths that work together:**

1. **The delegation certificate travels along with the delivery.** A
   delivery from a device carries its certificate; verification needs no
   lookup. This matches the principle that proofs accompany the action.
   Because the certificate is hybrid-signed and thus a few kilobytes in
   size, it travels along **only on the first contact per device** and
   is cached afterward.
2. **The device set is announced pairwise.** Changes go out to contacts
   as an ordinary delivery; the contact holds the state. The
   announcement carries the previous device count and the
   countersignatures of the remaining devices, so that a **shrinking of
   the device set** requires proof. These very countersignatures are the
   quorum from §14.4.

**A public durable object was explicitly rejected.** It would be
formally permissible (a self-declaration about one's own identity), but
would make the device set of every identity enumerable network-wide and
turn the identity itself into a discoverable object — a breach of the
no-directory property at the person level.

**The quorum with an unknown device set.** A brand-new contact does not
know `N`, a long-absent one has a stale state. Then: the case counts as a
legacy case, the normal key change detection applies with a visible
warning, and the new key is **applied anyway** — the **visibility
principle**: a rotation is never blocked, only shown. New contacts learn
the device set at first contact (§15). A completed recovery (§13.6) is
the **standard case** of this category and not an attack signal.

Rejecting a rotation because the set is unknown would be the worse
choice: it would hit every new and every long-absent contact, and a
blocked key change means silent delivery failure — exactly the error
class this design otherwise consistently avoids.

---

### 14.6 Enrolling a device — procedure and handover

Since the device-set-change standardization, enrolling a device is the
**standard path** for every device change: a broken or lost device is
replaced by adding a new one and locking out the old one. Recovery from
the 24 words (§13) is explicitly **not** this path (§13.0).

#### 14.6.1 Procedure

The procedure consists of request and approval — an enrollment request
from the new device, an approval dialog on an existing one, and an
encrypted handover of the material. Any device may approve, and every
enrollment is a device-set change:

1. **On the new device:** “Add device" locally generates its own
   **device sig key pair** (Ed25519 + ML-DSA-65, CSPRNG, **not**
   seed-derived) and its own **device key**, and issues an enrollment
   request with `deviceEd25519Pk` + `deviceMlDsaPk`.
2. **On any existing device:** an approval dialog with the device
   identifier. **Any device may approve alone**: the rotation due wraps
   for all already-enrolled devices too, no one loses access, and a
   thief gains nothing they did not already have.
3. **Rotation (§14.4):** new shared key, wrapped for all
   already-enrolled devices **and** the new one. The user KEM key does
   **not** rotate in this case — no one is excluded.
4. **Handover** of the material from §14.6.2, sealed against the device
   KEM key of the new device.
5. **Announcement** of the changed set to the contacts (§14.5, path 2)
   and to one's own devices (§14.7, type 16).
6. **Initial reconciliation** (§14.6.3).

**Via NFC**, the same procedure runs; only the first contact between
the two devices is established by touch instead of by QR.

**First device of an identity.** Generate a seed (24 words), form
identities via HD derivation (§4), generate a fresh device key, roll a
shared key, deliver the identity marker and recovery bundle for the
first time (§13.3/§13.7).

#### 14.6.2 What the new device receives

| Item | Purpose | Origin |
|---|---|---|
| **Shared key**, wrapped with the new device's device key | everyday key; `inbox_key = HKDF(shared_key, "inbox")` | §14.4 |
| **Delegated sig subkeys** (Ed25519 + ML-DSA-65) | all of this device's inner signatures; derived deterministically via HKDF from the identity material + DeviceID | derivation labels `"cleona-deleg-ed25519-v1" ‖ deviceId` and `"cleona-deleg-ml-dsa-v1" ‖ deviceId`, respectively |
| **DeviceDelegationCert** | binds the subkey to the identity; travels along with the first delivery per device (§14.5) | hybrid-signed (Ed25519 + ML-DSA-65) |
| **User KEM SK** (X25519 + ML-KEM-768) | so **all** devices unseal the same cell | §14.2 |
| **`invite_root`** | invitation line, so the device can harvest contact requests | §15.3.1 |
| **Share of the shared prekey pool** (secrets) | unsealing incoming cells (§14.3) | shared pool |
| **UserID, display name, identity indices** | basic state of the UI | §4 |
| **NOT: the seed** | — | the seed carries the identity and opens the recovery bundle; it is not the everyday key and need not sit permanently on any device |

**Capability bitmask** (certificate structure, default `0x0F`):

| Bit | Capability |
|---|---|
| 0 | send in the identity's name |
| 1 | unseal incoming cells |
| 2 | participate in twin sync |
| 3 | reserved, no function |

**Certificate validity.** Default **30 days** (`maxValidUntilMs`, `0` =
no expiry) as a dead-man's switch. The device checks **hourly** and,
starting **7 days** before expiry, automatically requests a renewal;
an already-known device is confirmed without prompting. If the
certificate expires, the device can still **receive** (the user KEM SK
is unaffected by this), but its signatures are no longer accepted by
contacts — it must be re-enrolled. **Any** living device may renew.

> **Decided.** The delegation certificate is issued with the **identity
> signature keys**; these sit under the shared key on **every** device
> — so every device can issue — and **rotate along at lock-out**
> (§14.4). A locked-out device loses the ability to sign in the
> identity's name along with the sig rotation. Verification-level rule
> and continuity proof: §14.4.

#### 14.6.3 Initial reconciliation

A newly enrolled device obtains the application state via the **initial
reconciliation**. Because a device change has been the standard case, the
new device **must** be able to obtain it completely, otherwise a device
swap would lose all contacts.

**Normative:** the initial reconciliation uses the **manifest-and-pull
machinery from §13.5.2**, just under a different carrier — the
device-scoped tag `HKDF(K_own, "device" ‖ deviceId ‖ n)` (§14.1) instead
of `tag(K_AB)`. Everything stated there therefore also applies: header
first (contacts, groups, channels), then manifest in blocks, then
pulling with priority **newest first**, resumable after an interruption.
A full reconciliation of the history is a deliberate user decision, not
an automatism — the same rationale as in §13.5.3: the delivering partner
pays bandwidth. *(The same mechanism that already defines recovery, on
a different carrier; no new mechanism.)*

**Return after a long absence.** A device that has been off for a long
time must catch up on two things: the **key packages** of all
intervening rotations (§14.4 places them in the respective old line)
and the **twin-sync backlog**. Both are bounded by the delivery
deadlines: management deliveries sit for up to **31 days**, the
recovery-epoch coverage is **42 days**. From this follows, normatively:

> **A device that was switched off for more than 31 days is
> re-enrolled** — it no longer finds its key packet. The UI states this
> plainly (“This device was offline for too long and must be
> re-enrolled"), instead of letting it run silently into a half-dead
> state.

For shorter absences, the pattern from §15.3.3 applies generally:
**reconcile first, then act.** A returning device reconciles its
twin-sync state before it harvests invitation lines or places delivery
receipts; until then the UI shows “reconciling state" instead of a
possibly stale state.

### 14.7 Twin-Sync: 18 Content Types

When multiple devices are active, changes to application state must be
reconciled between them. The Twin-Sync content types handle this.
There are 18 of them.

**Types 0–17** (canonical `proto/app_payloads.proto::TwinSyncType`).
*Types 14–16 are assigned here and **reserved** on the wire
(`reserved 14, 15, 16;`) but not built in `lib/` yet; whoever spends one
of those numbers on something else makes this document's numbering and
the wire's permanently different.*

| # | Type | Content |
|---|---|---|
| 0 | CONTACT_ADDED | new contact accepted (pubkeys, display name, verification level) |
| 1 | CONTACT_DELETED | contact deleted, with source marker (`inbox_reject`, `conversation_dialog`, `contacts_dialog`, `ipc`) |
| 2 | MESSAGE_SENT | mirror a message sent on one device |
| 3 | MESSAGE_EDITED | edit within the edit window (default 60 min, §21.6) |
| 4 | MESSAGE_DELETED | deletion is **unbounded** — the author may delete at any time (§21.6) |
| 5 | TWIN_READ_RECEIPT | own read on one device → other devices mark it too |
| 6 | GROUP_CREATED | own device created or joined a group |
| 7 | PROFILE_CHANGED | own profile picture / own display name changed |
| 8 | SETTINGS_CHANGED | shared settings per identity |
| 9 | DEVICE_ANNOUNCE | announce a new device to the existing devices (carries a `DeviceRecord`) |
| 10 | DEVICE_RENAMED | one of the user's own devices was renamed (§14.9) |
| 11 | TWIN_DEVICE_REVOKED | device locked out — propagated to the remaining devices |
| 12 | ROTATION_APPROVAL_REQUEST | request a countersignature for a rotation (§14.5) |
| 13 | ROTATION_APPROVAL_RESPONSE | countersignature evidence or explicit rejection (§14.5) |
| 14 | INVITE_LIST | invitation list (`i`, `exp`, class, label, revoked) — in particular carries the **revocation of an invitation**, which is therefore not a purely local act (§15.3.1/§15.3.3) |
| 15 | PREKEY_CONSUMED | consumption notice: this one-time prekey has been used, delete it (§14.3) |
| 16 | DEVICE_SET_CHANGED | device-set change with the **package of wrapped new shared keys** — one packet per remaining device, placed in the **old** line. On lock-out, the rotated user KEM secret key and the identity signing secret keys travel along underneath it — they are placed under the new shared key (§14.4) |
| 17 | TWIN_IDENTITY_DELETED | the identity was deleted on another of the user's own devices (§21.5.2). The receiving device wipes its local copy **in full** — the store (`messages.db` and its journals) and every `*.json.enc`, keys first (§21.4.1) — and its host then removes the identity entry and the profile directory, attachments included. **If it was the last identity on that device, the device ends with zero identities and returns to the first-start state; it does not exit.** No second broadcast to the contacts goes out: the deletion already reached them from the deleting device (§15.7) |

The type carries **17** on the wire (`proto/app_payloads.proto`).

To distinguish Type 11 from Type 16: Type 11 is a plain notification
(“device X is out") and travels like any other sync delivery. Type 16
carries **secret material per recipient device** and therefore has its
own placement rule — it sits in the old line so that even a device
switched back on only weeks later still finds it, and it is a management
type with a **31-day** TTL, not the usual 14.
A locked-out device sees the same package and cannot open a single
packet — so distribution needs no channel of its own (§14.4).

**Deliberately not on the list:** `CONTACT_VERIFIED`,
`CONVERSATION_OPENED`, `GROUP_LEFT`, `CHANNEL_SUBSCRIBED`,
`CHANNEL_UNSUBSCRIBED`. An upgrade of verification travels as a fresh
`CONTACT_ADDED`, the existence of a conversation follows from the first
message, and group or channel joins run over their own protocols (§16).

**Transport and mode.**

- All of the user's own devices share `K_own`, so for the general types
  **a single delivery** is enough (§7-§9). The triggering sender
  recognizes its own delivery by the `sync_id` and ignores it — the
  sender excludes itself.
- **Delivery-ladder stage per content.** Twin-sync uses the same
  delivery path as any other delivery (§7, §8). Most types are not
  latency-critical and are placed only through the mailbox stage (stage
  4) — the device set changing, revocations, profile/settings changes
  should not be session-linkable. The near-realtime mirror types —
  `MESSAGE_SENT`, `MESSAGE_EDITED`, `TWIN_READ_RECEIPT` — also use the
  direct stages (stage 1/2) so a message typed on the phone appears on
  the laptop within seconds (the user is already in the chat, so the
  session-linkability of a direct path is theirs to accept). Key
  packages (Type 16) go through the mailbox stage only, with the 31-day
  management TTL.
- The **device-scoped** tag `HKDF(K_own, "device" ‖ deviceId ‖ n)`
  (§14.1) is needed only where the payload **differs per device**:
  Type 16 (key package), the initial reconciliation (§14.6.3), and the
  delivery of delegated keys.
- `K_own` is the cross-device own material; it derives from the shared
  key and therefore rotates with every device-set change (§14.4).
- **Duplicate detection:** every Twin-Sync payload carries a `sync_id`
  (16 B, `proto/app_payloads.proto::TwinSyncEnvelope.sync_id`); the
  recipient discards repeats.
- **KEX gate:** Twin-Sync needs no exception from the unknown-sender
  gate. The tag can only be formed with `K_own`; the gate is a
  mathematical property (§4.3, §15.6).

**What is not reconciled:**

| Item | Reason |
|---|---|
| Local UI settings (appearance, volume) | individual per device |
| Network view: harvest lines, decoy selection, relay partnerships | every device has its own network view and must have one, or the decoys would be correlated |
| Detailed call history | more local than application state |

**Failure mode, made explicit.** A Twin-Sync delivery is a delivery: it
has latency (§7/§8) and a TTL. A device that is offline longer than the
TTL never learns of the change and must catch up on the backlog via
§14.6.3. This is exactly what the rule in §15.3.3 rests on: a revocation
is shown as **partially effective** until acknowledged by all devices —
a silent intermediate state is ruled out.

### 14.8 Device Cap and Quorum Count

**Cap: 5 devices per identity**, for three verifiable reasons:

1. The key package on every rotation contains **one packet per device**
   (§14.4). It grows linearly with N.
2. The pairwise device-set announcement (§14.5) goes to **every
   contact** and carries the countersignatures of the remaining
   devices; it too grows with N.
3. The quorum `max(2, ⌈N/2⌉)` becomes harder to reach as N grows,
   precisely when devices are used rarely.

The limit is enforced **locally, on the enrolling device**, and is
visible in the device-set announcement. That is weaker than a centrally
checked list — a tampered device could enroll more — but it is
noticeable: contacts see the device count in the announcement, and a
jump stands out.

**Quorum count (normative).** §14.4 states `max(2, ⌈N/2⌉)` for lock-out.
What `N` is, the following counting rules decide; they solve the one
case that would otherwise be unsolvable:

- **On a device-set change, the quorum counts the *remaining* devices
  `M`, not the state before it:** `M = 0 → 0`, `M = 1 → 1`,
  `M ≥ 2 → max(2, ⌈M/2⌉)`.
  *Rationale:* if one of two devices is removed, one remains — a
  quorum over the prior state would be unreachable by construction,
  and the proof could never be produced.
  *Example that would fail without this rule:* five devices, three
  stolen in a burglary. Remaining `M = 2` → quorum 2 → the two
  survivors can lock out the three. With `N = 5` the quorum would have
  been 3, and the lock-out impossible — in the single most important
  use case of all.
- **What is counted is distinct devices, not pieces of evidence.** Two
  countersignatures from the same device are **one** approval. Without
  this rule, a single device could satisfy the quorum by submitting
  twice.
- **The reason is stated in the request** (field `approval_kind`).
  Without it, the countersigning device would describe every request as
  a key rotation, and the approval would have been obtained under a
  false description.

**With exactly one device, the rule does not apply** — that one device
is sufficient there (§14.4).

### 14.9 Device Management in the UI

#### 14.9.1 Device Name and Device Record

Every device keeps a record (`DeviceRecord`,
`proto/app_payloads.proto::DeviceRecord`) with the following fields:

| Field | Content |
|---|---|
| Device identifier | the DeviceID (§14.1: subject, not signpost) |
| **Device name** | default is the **operating system's computer name**, changeable by the user; a change travels as Twin-Sync Type 10 (`proto/app_payloads.proto::DeviceRecord.device_name`) |
| Platform (Android / iOS / Linux / Windows / macOS) | basis for the display and the expectations from §31 |
| first seen / last seen | “last seen" is fed by the last harvested Twin-Sync |
| “is this device" | marker for the locally running device |

#### 14.9.2 Settings → Devices

The devices screen shows:

- **Device list** with name, platform icon, “this device" marker, and
  “last seen".
- **No primary/linked marking.** All devices are peers (§14.4).
- **Capability chips** for the four bits from §14.6.2, active ones
  highlighted.
- **Certificate expiry:** date and remaining validity, warning from
  7 days out, error color after expiry, “Renew now" button (numbers
  from §14.6.2: 30-day validity, 7-day warning threshold).
- **“Lock out device"** with two progress indicators, both normative:
  1. *Quorum:* “Confirmation from 2 devices needed — 1 of 2 given."
  2. *Effectiveness:* “Device locked — fully effective once all
     contacts are informed (3 of 47 still open)." A lock-out that is
     visibly not yet in effect is more honest than one that suggests a
     security it will only reach in days (§14.4).
- **State of the network backup** from chapter 13: “Backup in the
  network valid until <date>" or “expires in N days" (§13.3.4).
- **“Add device"** is available on every device.

#### 14.9.3 How Devices Learn About Each Other

Devices learn about each other exclusively through the device-set-change
deliveries (Type 9 and Type 16, §14.7). There is no directory and no
published reachability (§4.1, §23); the device set is thus carried
state, not queryable state.

### 14.10 Assurances of the Device Model, at a Glance

What this chapter promises the user, as a list:

- **There is no primary device.** All devices of an identity have equal
  rights and share a common shared key; excluding a device follows from
  the randomness of the new key, not from a privilege (§14.4).
- **An additional device is enrolled by a live device** and fetches its
  application state via the initial reconciliation (§14.6). Entering the
  24 words on an additional device is a recovery operation, not pairing
  (§13).
- **Replacing a device means: add and lock out** (§14.4, §14.6). Chapter
  13 applies only when **all** devices are gone.
- **One delivery serves all devices** — shared `inbox_key`, shared user
  KEM secret key (§14.2). On the delivery path there is no device level
  and therefore no “1 of N delivered".
- **A revocation takes effect per contact**, as soon as that contact has
  harvested the pairwise announcement, at the latest when the old line
  closes after the delivery window; progress is visible in the UI
  (§14.4).
- **A locked-out device still holds the frames it already received** —
  it possesses the user keys. That is why the user KEM keys **and the
  identity signing keys** rotate along with the lock-out, and the prekey
  stock is discarded (§14.4, §14.3). A mere inbox rotation would be a
  label, not a lock.

  **Revocation triggers a full identity key rotation.** `revokeDevice`
  removes the device, retracts its `DeviceDelegationCert` and
  `DeviceSigInfo` — signing authority — and rotates the identity keys.

  - **What rotates:** all four user keys in one step — Ed25519 and
    ML-DSA-65 (identity signing), X25519 and ML-KEM-768 (user KEM) —
    through `identity_context.dart` `rotateIdentityFull()`.
  - **Where the trigger hangs:** in `revokeDevice()` and, mirror-
    symmetrically, in `_handleTwinDeviceRevoked()` — the path the primary
    takes when a linked device initiated the revocation. Both call
    exactly the same rotation function; there is no second rotation
    mechanism. The call is unconditionally safe because
    `rotateIdentityKeys()` guards itself on `isLinkedDevice` (a no-op
    with a log line there).
  - **No race with the §14.5 quorum.** `_devices.remove()` runs
    synchronously before the rotation starts, and the rotation's own
    device fan-out resolves recipients from `_devices`, never from the
    publisher's delegation list. The revoked device is out before the
    first frame is formed, however long the device-set-change approval
    round still takes.
  - **The prekey stock needs no separate discard today**, because
    `BootstrapPrekeys.oneTimePrekeysWired` is `false` (§4.6 stage 1 is
    not wired): the pool is never filled and every seal falls back to
    the long-lived user KEM keys, which the rotation above overrides.
    When that flag flips, an explicit pool discard becomes due at the
    same two sites.

  **What the lock does not close, stated plainly.** Rotating locally
  makes the revoked device blind to everything new **immediately**. It
  does not close the window until every contact has learned of the
  rotation. The rotation notice is a pairwise delivery, and a contact who
  is offline at that moment is retried on the ordinary schedule — first
  attempt at once, then +24 h, then +48 h, then the attempt expires with
  a UI warning. Until such a contact has it, they keep encrypting to the
  **old** user KEM public key, and the revoked device still holds the
  matching secret. So the honest guarantee is: *new traffic from contacts
  who have seen the notice is out of reach at once; traffic from a
  contact who has not can remain readable for up to about two to three
  days.* This is inherent to pairwise, asynchronous rotation (§14.4, "a
  revocation takes effect per contact") and not a property of the
  revocation trigger — the same window exists for a manual rotation. It
  is named here because a reader of this bullet would otherwise take
  "rotate along with the lock-out" for an instantaneous cut, and it is
  not one.
- **17 Twin-Sync content types** (§14.7), each using the delivery-ladder
  stage appropriate to its latency and linkability needs.
- **Twin-Sync needs no KEX-gate exception:** the gate is a mathematical
  property — only whoever has `K_own` can form the tag (§4.3, §14.7).
- **At most 5 devices per identity**, enforced locally on the enrolling
  device and visible in the device-set announcement (§14.8).
- **Payload that differs per device travels over Type 16** — wrapped
  shared keys and delegated partial keys, because their placement rule
  is a different one (§14.7).

---

## 15. First contact and identity authorization

First contact is the only place where two identities have to come together
without shared prior knowledge. Everything afterwards runs on keys both
sides already hold. This chapter specifies the card that one side hands
out, the five packets that turn it into a contact, and the states a
relationship can be in afterwards.

### 15.1 Overview — the five packets

The inviting side is called the **issuer**, the joining side the
**requester**. The issuer creates a card and hands it over; the card needs
nothing but the issuer's own keys and its own address, so it is available
from the first start and never waits for a network state (§12.4).

```
ISSUER                                     REQUESTER
──────────────────────────────────────────────────────────────
creates card + code
shows QR, taps NFC,           ──card──►    reads it — no network
or copies one line of text                 traffic up to this point

                              ◄──(0)──     bundle request + 16 random
                                           bytes, unsealed, no identity
(1) key bundle + the same     ───────►
    16 bytes, unsealed                     checks SHA-256(bundle)
                                           against the card fingerprint
                              ◄──(2)──     REQUEST: proof of work in
                                           the clear, then a sealed
                                           envelope with the code and
                                           the introduction
checks the proof of work,
unseals, checks the code,
asks the user, user accepts
(3) ANSWER, sealed            ───────►
                              ◄──(4)──     RECEIPT, sealed
contact stands at the issuer               contact stands at the requester
```

There is no negotiation and no state between the packets. Each of the five
is complete and checkable on its own; a lost packet is re-sent, never
resumed.

| # | Packet | Type byte | Size on the wire | Sealed |
|---|---|---|---|---|
| 0 | bundle request | `0x01` | 17, 40 or 52 B anonymous, 117 B signed | no — carries no identity in its anonymous form |
| 1 | key bundle | `0x02` | 3185 B | no — the bundle is public |
| 2 | request | `0x03` | 7729 B + payload beyond the code | partly — 17 B of proof of work lie outside the seal (§15.5.1) |
| 3 | answer | `0x04` | 7697 B + payload | yes |
| 4 | receipt | `0x05` | 7698 B | yes |

Every packet begins with its type byte. Sealed packets carry one envelope
(§4) after that byte; the envelope's fixed cost is 7696 B — 1137 B outer
header, 3168 B sender key bundle inside the seal, 2 + 64 B for the two
signatures' framing and the Ed25519 signature, up to 3309 B for the ML-DSA
signature, and 16 B authentication tag. Packets above 1200 B are split into
numbered parts by the wire layer (§11); a sealed request is seven parts.

**Why the round trip for the bundle.** A packet can be sealed only against
the full key bundle (Ed25519 + ML-KEM-768 + ML-DSA-65, 3168 B),
and that bundle does not fit in a card that a camera can scan. The card
therefore carries a 32-byte fingerprint of it, and packets (0) and (1)
fetch the bundle itself. The requester accepts the bundle only if its
SHA-256 equals the fingerprint in the card. The cost is one round trip; the
gain is that the first packet carrying anything private is already fully
post-quantum sealed, with no classical interim step.

**The random value in packets (0) and (1).** The requester puts 16 random
bytes into the bundle request; the issuer echoes them unchanged. A bundle
answer whose 16 bytes do not match the ones sent is discarded. This binds
the answer to the question and keeps an unrelated or replayed bundle from
being taken as the issuer's.

**Two forms of the bundle request.** The packet exists anonymously, for a
stranger joining from a card, and signed, for a party that is already a
contact and needs the bundle again — after a reinstallation, for instance,
where the contact list survived but the stored bundle did not.

| Field | Bytes | Anonymous form | Signed form |
|---|---|---|---|
| type | 1 | `0x01` | `0x01` |
| random value | 16 | yes | yes |
| reply code | 16 | when the requester has a fixed neighbour | — |
| requester's fixed neighbour | 7 or 19 | with the reply code: type + address + port | — |
| sender identifier | 32 | — | SHA-256 of the sender's own key bundle |
| timestamp | 4 | — | Unix seconds, u32 LE |
| Ed25519 signature | 64 | — | over the 53 preceding bytes |
| **total** | | **17 B, or 40 / 52 B with a return way** | **117 B** |

The forms are told apart by length alone: 17, 40 and 52 bytes are the
anonymous form, 117 the signed one, any other length is discarded.

**The way back for the bundle.** A requester behind address translation is
reachable only through its fixed neighbour (§8.1). It therefore registers a
one-time reply code there before the bundle request leaves the device, and
puts that code and the neighbour's address into the request. The issuer
sends the bundle (1) back like any sending to that requester: directly to
the address the request came from when it came directly, and under the
reply code through the named neighbour (`0x20` inside `0x22` via its own
fixed neighbour, §8.1) when it came through a neighbour — the address it
came from is then the forwarder's, not the requester's. The request stays
unsealed; what it shows beyond the random value is a one-time code and a
neighbour address, the same a forwarder already sees in every `0x22`.

**When a node answers.** A bundle request is answered if **either** at
least one invitation is standing — neither revoked nor expired — **or** the
request is in the
signed form, its identifier belongs to a stored contact, and the signature
verifies against that contact's stored Ed25519 key. Nothing else is
answered.

Without the second condition an established contact that lost its stored
copy of the bundle could never get it back, because the invitation it once
used is long gone. The signed form is not a liveness probe: only a party
that already holds the identity's key bundle as a contact can produce one,
and such a party already knows the identity exists.

**The timestamp bounds replay.** The signature is over fixed bytes, so a
packet captured on the wire could otherwise be resent forever by anyone as
a probe. A signed bundle request whose timestamp lies more than **300 s**
from the receiver's clock is discarded.

### 15.2 The invitation card

**The bundle holds three keys, not four.** The X25519 key in the card is
*derived* from the Ed25519 key and is therefore not part of the bundle:
32 + 1184 + 1952 = 3168 B. A fourth, independently stored X25519 key
could drift out of step with the Ed25519 key it belongs to; a derived one
cannot.


**91 bytes** in the smallest case — a device that shows its card before it
has any usable address at all (§12.4), carrying an address count of `0`
and no publisher key. **98 bytes** with one IPv4 address of its own and
nothing else. The relay list adds at most 195 bytes (three entries of 64
characters) and the publisher key 32 bytes, so the largest card — four own
addresses in IPv6, a neighbour address in IPv6, the publisher key and three
relay entries — is **413 bytes**.

**The issuer lists its addresses and judges none of them.** It carries the
addresses it is bound to, in its order of preference, link-local excluded
(§11.1); which step of the ladder an address serves is decided by the reader
(§7.2, §7.3, and below). A freshly installed device therefore carries its addresses from the
first second, before anyone has ever reached it.

**The neighbour address is carried only when it is verified**: that
neighbour has answered under exactly that address and the entry is not
stale (§11.8). And it is **one of the issuer's open neighbours** (§5.2)
**reachable from the open network (§5.2, fixed place); a private address is
never carried as the neighbour — a reader on the same segment reaches the
issuer's own addresses (§7.2) anyway, and a reader elsewhere cannot use
it**: a node behind address translation is reachable only through the mappings it
keeps open, and a sender leaves post first with the neighbour the card
names (§8.2). An unverified neighbour is left out — it would cost the
recipient a first contact and teach it nothing. **The card never names a
contact's device** (§5.2): a card travels to people the issuer has not
accepted yet and is passed on. It names the card's place; contacts learn
the other fixed neighbours sealed (§9.2).

**The publisher key lets a card outlive an address change.** It is the
stable key under which the issuing device publishes its record (§11.9); a
recipient whose card addresses no longer answer looks the current ones up
under it. The addresses stay in the card regardless: they are the only way
in that needs no third party — two phones in one W/LAN — and a device
without a reachable address has no record the key could point to.

**A card is deliberately both.** It secures the way into the network — the
device half: addresses, neighbour, publisher key, relays — and it carries
the request to a person — the user half: letter key, fingerprint, code.
Neither half works without the other. The device half names the device that
issued the card (§12.4); on a user with several devices (§14), an old card
points to the device that issued it.

| Field | Bytes | Content |
|---|---|---|
| version | 1 | `0x01` |
| channel | 1 | `0x00` live, `0x01` beta |
| letter key | 32 | the issuer's X25519 public key |
| fingerprint | 32 | the identifier of §4.1 (32 B) |
| own addresses: count | 1 | how many of the issuer's own addresses follow, 0 to 4 |
| own addresses | 0 to 4 × (7 or 19) | per entry: type (1) + address (4/16) + port (2), in the issuer's order of preference |
| flag, neighbour address | 1 | `0x00` absent, `0x01` present — present only for a verified open neighbour |
| neighbour address | 0, 7 or 19 | present only on flag `0x01`: type (1) + address (4/16) + port (2) |
| flag, publisher key | 1 | `0x00` absent, `0x01` present |
| publisher key | 0 or 32 | present only on flag `0x01`: the stable secp256k1 key of the issuing device (§11.9), under which its current address record can be looked up |
| relay count | 1 | number of relay entries that follow, 0 = none, at most 3 |
| relay entries | variable, at most 195 | per entry: length (1, at most 64) + the relay's address as text |
| difficulty | 1 | leading zero bits the proof of work on a request must show (§15.5.1) |
| code | 16 | random bytes (§15.3) |
| expiry | 4 | Unix seconds, u32 LE |

Each address carries its own type byte, so the addresses of one card may
be of different kinds — an IPv6 address next to an IPv4 one is an ordinary
card, not a special case.

**A reader rejects a card whose address type it does not know.** Only `4`
and `6` are defined; any other value makes the whole card invalid, with an
error that names the reason. Guessing the length of an address whose type
is unknown would shift every later field and turn a future extension into
silent nonsense.

The same applies to any flag byte other than `0x00` or `0x01`, to any short
read, and to any surplus byte after the expiry. A card is rejected as a
whole or accepted as a whole; there is no partial read.

**The channel byte separates the networks.** `0x00` is the live network,
`0x01` the beta network. **A reader rejects a card whose channel is not its
own immediately** — before any packet leaves — with a message that names
the reason ("this invitation belongs to the beta network"). Two networks
that share addresses but not identities would otherwise produce requests
that travel, arrive, and are then dropped for a reason nobody can see. Any
channel value other than `0x00` and `0x01` is likewise a rejected card.

**The fingerprint is the identifier.** The same 32 bytes address the node
in the post box and in forwarding (§8). One identity, one identifier, one
derivation.

**A node carries every address it can be reached at, in its own order of
preference.** A node has no roles; it has connections, and it knows all of
them. A phone on Wi-Fi and mobile data at the same time carries both. The
order follows §22.6 — wired, Wi-Fi and VPN before cellular, cellular as
the last choice (§10, §23.1) — and it is the issuer's recommendation, not
an instruction to the reader: a reader takes the entries it can use and
skips the rest, so a node without an IPv6 socket passes over an IPv6 entry
instead of failing on it. Four entries is the cap, which is what a
multihomed device needs: two families on each of two connections.

**Nothing in the card says what kind of address an entry is.** Whether an
address is reachable inside the reader's own segment, or from the open
net, is decided by the reader from the address itself (§7.2, §7.3) — the
same test that decides between ladder step 1 and step 2. A stored
classification would be a second truth that can go stale, and the issuer
is not the one who can answer it: whether its `192.168.x.y` is in *your*
segment is a fact about you. A node with no usable address at all — mobile
data behind CGNAT — carries a count of `0`, and says so rather than
inventing one.

**The neighbour address is the one entry that is not the issuer's.** It
serves ladder step 3 (§8.1) and names a third party. It is not an exotic
case: behind NAT, and especially behind CGNAT, the issuer has no address
of its own worth carrying, and a neighbour both sides can reach is then
the only way in. A card without it, and without own addresses, offers a
requester on the open internet no path except the records of §11.9.

Addresses in the card are hints for reaching the issuer; they are not
delivery state, and a stale hint produces no answer and no error.

**The card carries no signature.** It travels over a channel the user can
see. A signature by a key whose own fingerprint sits in the same card adds
nothing — forging the card requires the issuer's secret keys. The binding
that does the work is the fingerprint check on the bundle.

**What the card does not carry:** no display name, no profile picture, no
secret key material, and no delivery state. The introduction travels in the
request and the answer (§15.5), where it is sealed.

**Three ways to hand a card over.** All three carry the same bytes.

| Channel | Form | Note |
|---|---|---|
| QR code | 91–413 B binary, or 122–551 base64url characters | binary, error correction M: **version 16, 81×81 modules** for the largest card, version 6, 41×41 for the smallest. Measured 17.09.2026 with the generator in use (`package:qr` 3.0.2, `QrCode.fromUint8List` as in `invitation_card_view.dart`), per level L/M/Q/H: largest card V13 / V16 / V19 / V22, smallest V5 / V6 / V8 / V9. The publisher key moved the largest card one version up at level M (V15 at 380 B). |
| NFC touch | the packed bytes in one NDEF record | physical contact; both sides may exchange cards in one operation |
| one line of text | `cleona:1:<base64url>`, 133–563 characters | for pasting into a chat, a mail, a note, a posting (§15.6) |

The character counts follow from the byte counts: base64url without padding
is `ceil(n × 4 / 3)` characters. The text line additionally carries the
prefix `cleona:1:` (9 characters) and a 2-byte checksum (§15.6), so it is
`9 + ceil((n + 2) × 4 / 3)` characters. Checked against the implementation
on 17.09.2026 for 90, 97 and 380 B (132, 141 and 519 characters) — the
figures that stood here before, 141–468, were wrong at both ends.

| Card | Bytes | As base64url | Text form: +2 B checksum | encoded | + 9-character prefix |
|---|---|---|---|---|---|
| LAN IPv4 only | 96 | 128 | 98 | 131 | **140** |
| three IPv4 addresses | 110 | 147 | 112 | 150 | **159** |
| three IPv6 addresses | 146 | 195 | 148 | 198 | **207** |

The text line is longer than the bare encoding by more than the prefix,
because the checksum is added before encoding, not after.

**The first-contact code.** `first 16 B of HKDF(code, "first-contact")`,
from the card's code field — no field of its own. The issuer registers it
with its fixed neighbour (§8.1) before the card leaves the device, and the
reader sends its bundle request (§15.5) under it to the neighbour the card
names. The bundle request carries, in the clear, the reader's fixed neighbour
and a one-time reply code registered there, and the bundle returns under
that code (§15.5). The request carries them again, sealed; the answer
returns under that code, together with `s_AB` (§4.3).

### 15.3 The invitation code: validity, redemption, revocation, reissue

The code is 16 bytes from a cryptographic random source plus an expiry
date. Its purpose is one thing only: the issuer accepts a request from an
unknown party only if that party presents the code from a card the issuer
handed out.

**Two kinds of invitation, chosen by the user.** When an invitation is
created, the interface asks which kind it is to be. The question is put in
the user's own terms — one person, or a group — because the answer decides
how many contacts the card can produce.

| Kind | For | Spent when |
|---|---|---|
| **single** (default) | one particular person: a new colleague, someone met just now | after the **first accepted** request |
| **open** | handed to a group: "I am here too now" | after `n` accepted requests, or at expiry |

**A single invitation is spent by the first request that is accepted, not
by the first that arrives.** This is normative and the distinction matters:
if arrival spent it, any stranger could burn the invitation with one junk
request before the issuer's user was ever asked, and the person it was
meant for would find a dead card.

For the open kind the user chooses two things at creation: the acceptance
limit `n`, default **20**, and the validity, default **7 d**. The shorter
default is deliberate — a card handed to a group stays visible far longer
than the occasion that produced it, so its validity is set to outlive the
occasion and little else.

Both kinds are revocable at any time, and for the open kind revocation is
the working tool rather than an emergency measure: it is revoked once the
occasion is over.

**The kind is not in the card.** The issuer enforces it, and the other side
has no need to know it. The card's layout and size are the same either way;
what differs is the difficulty byte (§15.5.1), which is higher for the open
kind.

**Validity.** The expiry is visible in the card. Selectable 7 d / 30 d /
90 d / unlimited; default **90 d** for the single kind, **7 d** for the
open kind. Unlimited is written as `0xFFFFFFFF`, the largest u32 (year
2106).

**Checks at the issuer, in this order.** Expired → refuse. Already spent —
the single kind after one acceptance, the open kind after `n` — → refuse.
Code does not match → refuse. All three refusals are **silent
towards the network** — no answer packet of any kind — and distinguishable
in the local log, so that an issuer can diagnose what is happening without
the network learning which of the three it was.

**Checks at the requester.** A card whose expiry has passed is rejected
**before any packet leaves**, with an explicit error ("invitation expired —
ask for a fresh one") instead of a silent non-delivery. When less than 7
days of validity remain, reading the card warns ("expires in X days — an
answer may no longer be possible") rather than proceeding without comment.

**Expiry and the acceptance window are separate.** A request placed while
the code was valid can arrive later, because it may have travelled through
a post box that holds packets for 7 days (§8.2). The issuer therefore
accepts requests bearing a given code until **expiry + 7 d**. The grace
sits with the issuer, who alone knows the truth about how long it is
listening; the commitment printed in the card stays honest.

**A card shown on a screen can be photographed over the shoulder.** The
single kind is what answers that: whoever captured it in passing arrives
too late once the intended person has scanned it and been accepted. A card
handed over by NFC touch cannot be captured that way, but it is issued as
the single kind too, so that one rule covers both face-to-face paths.

**The gate is the acceptance, not the scarcity of the code.** Every
redemption produces a request carrying the requester's name, which the
issuer may check over any channel the two already share. Until the issuer
accepts, nothing is established. That is what makes an open invitation safe
to hand to a group: whoever picks it up — including someone it was not
meant for — arrives as a named question, not as a contact, and the count
`n` bounds how many such questions can turn into contacts.

**Attribution.** Every incoming request is shown attributed to the
invitation it used ("via invitation 'conference' of 3 August"). The issuer
therefore sees *which* invitation is being flooded and revokes exactly that
one, without touching the others.

**Revocation.** Revoking an invitation removes its record at the issuer.
Requests bearing it are refused silently from that moment. On a single
device this is immediate, needs no network, and cannot be denied. Where an
identity runs on several devices, the invitation list is one of the
contents the devices reconcile among themselves, and reconciliation has
latency and can fail:

* The revocation takes effect **immediately on the revoking device**.
* Until every device has acknowledged it, the invitation counts as
  **partially revoked** and is displayed exactly as that ("revoked,
  synchronization in progress"). A silent intermediate state is ruled out.
* A device returning after a longer absence **reconciles the invitation
  list before accepting any request**.

**Bulk revocation.** The invitation list can be cleared in one operation,
invalidating every standing invitation at once — the remedy when a card has
leaked and it is not known which one.

**Standing invitations are capped at 10, and on one node they all belong
to one identity.** A bundle request names no identity (§15.1), so a node
holding standing invitations of two identities could not tell which
bundle to answer with. An invitation for a second identity can be issued
only once no invitation of the first is standing any more. Each
invitation is a code the issuer must keep checking and an address hint in
circulation that it can no longer correct. The count is shown in the interface, with revocation as the
one-click remedy.

**Reissue.** Codes are random bytes in a local list, not derived from the
seed phrase. An identity restored onto a new device therefore holds no
codes: every card handed out before the loss is dead, and stays dead
silently, because such a card neither expires nor carries anything the
requester could check against. Two consequences follow, and both are
normative:

* The invitation list — code, expiry, kind and its acceptance count,
  difficulty, label, revoked flag
  — is part of the identity's backup, so that cards survive a device
  change.
* Restoring without that backup is **fail-closed**: all existing
  invitations are gone, new ones are issued. This costs convenience only,
  and it is the only statement that can honestly be made without the list.
* Restoring an older copy of the list can bring a revoked invitation back
  to life. The invitation list in the interface shows the state, and the
  remedy is to revoke again.

### 15.4 The request buffer

Requests that have arrived, passed the code check, and are waiting for the
user's decision sit in a buffer: **at most 20 per invitation, at most 100
in total**.

Behaviour at the limit decides everything, and both obvious readings are
harmful. If the issuer stops accepting, every legitimate request beyond the
limit is lost in silence. If it accepts and discards, the result for the
sender is identical. An attacker fills the buffer with twenty requests,
each from a freshly generated identity with a slightly different greeting —
deduplication recognizes identical packets, not similar intentions — and
reaches the global limit across five invitations. Therefore, normatively:

1. **Evicting, not blocking.** On overflow the **oldest unanswered**
   request is dropped and the new one is admitted. **A full buffer is never
   a closed channel.**
2. **Visible.** "This invitation is at its buffer limit" belongs in the
   interface, with the one-click remedy (create a new invitation, revoke
   the old one). A silent cap is a silent failure.
3. Packets discarded by the type rule (§15.7) **also** count against the
   buffer of the invitation they were addressed under; otherwise the type
   check would be a free bypass.

**What bounds flooding, stated plainly.** Identities are free to create, so
a limit per sender is ineffective (§15.10). Three means carry this together,
and each covers what the others cannot: the **proof of work** (§15.5.1)
bounds the *load*, because every request costs its sender about a second of
computation and the issuer at most ten hashes; the **kind of invitation**
(§15.3) bounds the *acceptances*, because a single invitation yields one
contact and an open one at most `n`; and **revocation** (§15.3) ends a
flooded invitation outright, which the attribution of every request to its
invitation makes a targeted act rather than a guess. Eviction (item 1) then
ensures that whatever load remains never closes the channel.

### 15.5 Request, answer, receipt

**Structure of the request (2).** Three fields lie in front of the
envelope, in the clear, and are checked before anything is unsealed:

| Field | Bytes | Visible |
|---|---|---|
| type byte | 1 | yes |
| random value | 8 | yes |
| counter | 8 | yes |
| envelope | rest | sealed |

Packets (3) and (4) have no such prefix; they are a type byte followed by
an envelope.

**Sealing.** Packets (2), (3) and (4) are ordinary sealed envelopes (§4).
The sender's full key bundle and both signatures lie **inside** the seal,
so an observer on the wire does not see who wrote the packet. The signature
covers the header, both parties' full key bundles and the payload, so a
packet cannot be re-sealed towards a third party with the original
signature still carrying.

Opening an envelope succeeds only if the packet was addressed to this
recipient, is unaltered, and both signatures — Ed25519 and ML-DSA-65 —
verify against the key bundle inside it. A successful open therefore yields
the sender's complete, verified key bundle; nothing needs to be looked up
anywhere to answer it.

**Payload of the request (2).**

| Field | Size | Purpose |
|---|---|---|
| code | 16 B | the code from the card |
| display name | u16 length + UTF-8, ≤ 64 characters | how the requester is announced |
| greeting | u16 length + UTF-8, ≤ 280 characters | free text shown with the question |
| picture preview | u16 length + JPEG, ≤ 4 KB | optional |
| age declaration | 1 B | the requester's own `isAdult` flag (§15.10) |

The limits are counted in **characters, not bytes**, because that is what
the user sees; the length prefix is in bytes and bounds what the parser
reads. Over-long fields are rejected on receipt, not truncated — a
truncated greeting would be attributed to its sender.

Beside the field limits the whole request payload is capped at **8 KB**,
preview included, so that a request stays within a bounded number of parts.
With a bare code payload the request is 7729 B on the wire — seven parts.

#### 15.5.1 The proof of work on a request

A request carries a proof of work that the issuer checks **before
unsealing**. Without it every junk request costs the issuer the opening of
a hybrid envelope — two signature verifications and a decapsulation — while
costing the sender almost nothing. With it, the cost sits with the sender.

**The condition.** A request is well-formed when

```
SHA-256( code ‖ random value ‖ counter ‖ time window )
```

begins with `D` zero bits, where `time window` is the Unix time in minutes
divided by ten, as an integer. The requester varies the counter until the
condition holds; the issuer computes the hash and compares.

**The code is not in the clear anywhere in the packet.** It is an input to
the hash, not a field of it. The issuer knows its own standing codes — at
most ten (§15.3) — and tries them in turn, so checking costs **at most ten
hash computations** before anything is unsealed. An eavesdropper on the wire
learns neither the code nor which invitation was used. The code itself is
checked again after unsealing, where it appears in the payload; the proof
of work does not replace that check, it precedes it.

**A solution ages.** The time window makes it valid for about ten minutes.
Beyond that, the issuer keeps the random values it has seen in the current
and the previous window — **at most 1000** — and discards a repeat. Without
that list, one solution once computed could be replayed without limit, and
the cost the proof is meant to impose would be paid once for an unbounded
flood.

**A missing, malformed or failing proof is discarded silently**, without
unsealing and without any answer. It stands on exactly the same footing as
a failed code check (§15.3): an unauthorized packet is not answered.

**The difficulty is in the card**, one byte, so that the two kinds of
invitation can demand different work — an invitation handed to a group is
seen by more parties and must cost more per request than one handed to a
single person.

| Kind | `D` |
|---|---|
| single | 20 bits |
| open | 22 bits |

> **`D` is set by measurement, not by estimate.** The two values above are
> provisional. `D` **MUST** be chosen so that producing a solution takes
> about **one second on the weakest supported target device**, and that
> duration **MUST** be measured on that device rather than derived from a
> faster one. A difficulty that is comfortable on a desktop and takes a
> minute on a phone turns the proof into a device filter instead of a cost.

The issuer's side of the check does not scale with `D`: verifying is at
most ten hashes whatever the difficulty, which is the asymmetry the whole
construction rests on.

**Payload of the answer (3).** One decision byte — `0x01` accepted, `0x00`
declined — followed, on acceptance, by the same introduction fields as the
request. After that, both sides hold the other's verified key bundle, name
and picture, and nothing further is needed to talk.

**Payload of the receipt (4).** One byte, `0x01`. It tells the issuer that
the answer arrived and the contact stands on both sides. Delivery of
ordinary messages is acknowledged separately (§9.2).

**The decision.** Packet (2) does not create a contact. It raises a
question to the user — **accept / decline / block** — and the contact
exists only after an explicit acceptance. The delivery layer exposes a
single decision point and holds no policy of its own.

**Automatic acceptance, for two paths only.** Where the issuer handed the
card over **face to face** — NFC touch or a QR code shown to the person
standing there — the request is accepted without a second dialogue, because
it would ask about something that was just done deliberately. This is a
property of the invitation record **at the issuer**, not an assertion in the
card: an attacker cannot obtain automatic acceptance by editing a card, only
by using an invitation that was issued for that path, which is of the
single kind (§15.3) and therefore works against him.

| How the card was handed over | User level |
|---|---|
| NFC touch | automatic acceptance |
| QR shown person to person | automatic acceptance |
| text line through another channel | accept / decline / block |
| posted or printed card | accept / decline / block |

**Declining** sends the answer with the decision byte `0x00`. The requester
holds a valid code and therefore already knows the issuer exists; leaving
them waiting would buy nothing and cost clarity. Refusals of the code
itself stay silent (§15.3) — that is the distinction: an authorized request
is answered, an unauthorized one is not.

**Ignoring** leaves the request in the buffer until the user decides or
eviction removes it.

**Re-contact.** If a request arrives from a party that is already an
accepted contact — for instance because the earlier answer was lost — the
answer is re-sent without asking the user again. Two exceptions: a
**blocked** party gets nothing (§15.9), and a request whose key bundle
differs from the stored one is never adopted silently (§15.8).

**No special path for simultaneous mutual requests.** If both sides send a
request at the same time, each sees one request in its buffer. Two answers
are idempotent — delivery is at-least-once in any case — and the situation
presupposes that both had handed the other a card.

### 15.6 The text form

`cleona:1:<base64url>`, where the payload is the packed card followed by a
2-byte CRC-16 (reflected, polynomial `0xA001`, initial value `0xFFFF`,
appended little endian). The base64url alphabet is used without padding
characters, so the line survives being pasted anywhere.

**Truncated and corrupted are told apart, and the order matters.** The
length of a complete card follows from a few bytes read in field order
alone — the address count, then each own address's type byte, then the
neighbour flag and, where set, that address's own type byte, then the
relay count and each relay entry's length byte — without interpreting any
address. Every combination gives exactly one length, between 90 and 380
bytes. So:

| Finding | Reported as | Advice to the user |
|---|---|---|
| decoded length ≠ the length the flags imply | truncated | "copy the whole line again" |
| length correct, checksum wrong | corrupted | "the text is complete but damaged — copy it again" |
| length and checksum correct, card still unreadable | wrong version | "this invitation comes from a different release" |
| no `cleona:1:` prefix and no plausible base64url run | not found | "no invitation in that text" |
| characters outside the alphabet, or an impossible length for base64url | bad characters | "the text was mangled in transit" |

Checking the length **before** the checksum is what makes the first two
distinguishable. Telling users their paste was truncated when it was
complete makes them copy too little again.

**Reading a pasted card tolerates what programs do to text:** line breaks
including `\r\n` inserted mid-token, surrounding whitespace, embedding in
prose, surrounding quotation marks or brackets, zero-width characters and
byte-order marks, the same card appearing twice in the text, and a missing
`cleona:1:` prefix.

### 15.7 The gate for unknown senders

From a party that is neither a contact nor the holder of a valid code,
exactly three things can reach a node, and nothing else:

| Packet | What it can achieve | What bounds it |
|---|---|---|
| bundle request `0x01` | obtain the node's public key bundle | answered only while an invitation is standing (§15.1); the bundle is public by construction |
| request `0x03` | raise one question to the user | must show a valid proof of work before it is unsealed (§15.5.1), then carry a valid, unexpired, unspent code; counts against the buffer (§15.4) |
| anything else | nothing | discarded before any processing |

**The type rule is normative, not descriptive.**

> A packet that arrives from a party which is not an established contact
> and whose type byte is neither `0x01` nor `0x03` is **discarded**, and
> counts against the request buffer. There is no third type admitted from
> an unknown party.

Without this rule, anyone holding a printed card could seal an arbitrary
payload to a node and, for instance, make a call ring on the strength of a
business card. The check is locally enforceable — it happens after opening
the envelope, where the sender is known and verified — so it is required
here rather than left to the implementer. It is carried as a checkable
invariant for the test strategy.

For everything beyond first contact the gate is structural rather than a
rule: an envelope opens only against the recipient's secret keys, and a
packet from a party whose verified key bundle is not in the contact list has
no path into the application at all. There is no downstream filter, because
nothing arrives that would need filtering.

### 15.8 Profile updates and identity deletion

**Profile update.** A user changes display name, picture or description;
the change goes to every contact as one ordinary sealed message per
contact, and the recipient updates its local contact entry. Limits:
description ≤ 500 characters of plain text (no markup, no HTML), picture
≤ 64 KB as JPEG, at most **one update per hour** — the recipients are what
that limit protects.

Note the two separate picture limits: **64 KB** for a profile update,
**≤ 4 KB** for the preview in a request (§15.5), which counts against the
request's payload cap.

**Key material never travels in a profile update.** An identity is its key
bundle, and the identifier is the SHA-256 of that bundle; a different bundle
is a different identifier. A packet that claims to come from a stored
contact but verifies against a different key bundle is therefore **never
adopted silently**: it is shown as a warning, the contact's verification
level is reset to `unverified` (§15.10), and adoption requires an explicit
act by the user. This holds for every unannounced difference, regardless of
which packet it arrives on. A key change that is **announced** takes the
path of §15.8.1 instead.

#### 15.8.1 The announced key change

An identity that deliberately replaces its key bundle — on losing a device,
on renewing after a block (§15.9), or on a routine decision to do so —
sends one key-change announcement to every contact.

The announcement is an ordinary sealed message (§4) under the **new**
bundle, so the envelope already carries the new bundle and both new
signatures. Its payload supplies what the envelope cannot: the same
assertion, signed by the **old** keys.

| Field | Bytes | Content |
|---|---|---|
| old key bundle | 3168 | must equal the bundle the recipient has stored, byte for byte |
| timestamp | 4 | Unix seconds, u32 LE |
| Ed25519 signature, old key | 64 | over new bundle ‖ old bundle ‖ timestamp |
| ML-DSA signature length | 2 | u16 BE |
| ML-DSA-65 signature, old key | ≤ 3309 | over the same bytes |

Payload at most 6547 B; the whole packet is therefore at most 14244 B on
the wire, twelve parts.

**The recipient accepts it only if all four hold:**

1. the envelope opens and both of its signatures verify — the **new** keys
   signed it;
2. the old bundle in the payload is byte for byte the bundle stored for
   this contact;
3. both old-key signatures verify against that old bundle, over new bundle
   ‖ old bundle ‖ timestamp;
4. the timestamp is not older than the timestamp of the last accepted
   announcement from this contact.

Signing over both bundles at once is what makes the announcement
non-transferable: it asserts *this* succession and no other, so it cannot
be lifted out and replayed towards a third identity.

If all four hold, the recipient replaces the stored bundle and identifier
and **keeps the verification level**. The level records how the identity
was verified in person, and an announcement proves that the same party — in
possession of the old secret keys — performed the change. An **unannounced**
difference proves nothing of the kind and resets the level to `unverified`
(§15.10).

If any of the four fails, the packet is discarded and shown as a warning;
nothing is replaced.

**A contact that never receives the announcement** keeps the old bundle and
sees the new identity as an unknown party, whose packets do not reach it
(§15.7). The remedy is the ordinary one: a fresh invitation and the five
packets of §15.1. This is the declared price of a key change and the reason
it is an act, not a routine.

**Identity deletion.** Deleting an identity sends a signed deletion notice
to every contact as an ordinary pairwise message — the departing identity
carries its own proof of authority in that last valid signature. The
recipient does **not** remove the contact: it marks it deleted, archives the
conversation read-only, and keeps showing name and picture with a
"(deleted)" suffix. There is no deletion object anywhere in the network and
no directory one could query for it; a contact that never collects the
notice simply keeps an entry that no longer answers.

### 15.9 Ending a relationship: delete, block, renew

A contact holds the other side's key bundle and addresses from the moment
of first contact, and neither expires. A relationship therefore needs
explicit states.

| State | Effect |
|---|---|
| **active** | in the contact list; packets in both directions |
| **deleted** | removed from the contact list; a persistent deletion mark prevents re-import through backup restore, device reconciliation and card exchange |
| **blocked** | as deleted, plus: a new request does **not** lift the mark |

**Deleting is not blocking.** A request from a **deleted** party reappears
as a question and, on acceptance, lifts the deletion mark. A request from a
**blocked** party is discarded after the envelope is opened, counts against
the request buffer (§15.4), and produces neither an answer nor a receipt —
silently.

**Reach of a renewed request.** After deletion the party is no longer a
contact, so it reaches the user **only through a valid, unrevoked
invitation**. Matching is against the identifier inside the request — the
fingerprint of the key bundle — not against the code, which belongs to the
invitation and not to a person.

**The honest boundary: blocking ends delivery, not the ability to send.** A
former contact still knows the identifier and the addresses. It can keep
sending packets, and it can keep leaving packets for the identifier in post
boxes (§8.2), where they occupy space against the per-day-value cap until
they expire. What it cannot do is reach the user: nothing is opened,
nothing is shown, nothing is acknowledged.

**The complete remedy: block and renew.** When blocking, the interface
additionally offers to renew the identity's key bundle. This generates a
fresh bundle, and with it a fresh identifier and fresh addresses in every
newly issued card. The occasion is a revocation, so the cut is **hard, with
no transition period** — a grace period would leave the lock-out
ineffective for exactly as long as it lasted.

Every remaining contact learns the new bundle through the key-change
announcement of §15.8.1, which is what lets them keep the verification
level they had. The blocked party is not among the recipients, and receives
nothing.

Its price is named rather than hidden: a contact that is offline long
enough to miss the announcement sends into the void and must be reached
again through a fresh invitation. The loss is visible as a missing
acknowledgement (§9), not as a silent disappearance. That is why renewal is
**an option offered when blocking**, never an automatic consequence of it.

### 15.10 Verification levels, profile, alias

**Verification levels.** A contact carries exactly one of four levels:
`unverified` / `seen` / `verified` / `trusted`. `verified` is bound to the
**transmission channel that only the application can know** — a camera scan
with the other person present, or an NFC touch — and **not** to the card
format: the same bytes travel over every channel, so the format cannot carry
the distinction. A card received through a chat therefore never inherits the
in-person level. An **unannounced** key-bundle difference resets the level
to `unverified` (§15.8); an **announced** key change that passes all four
checks of §15.8.1 leaves it untouched.

**Never a fixed neighbour.** A contact can be marked so that it never
takes a fixed place (§5.2) — for the user whose threat comes from their own
circle. The mark is local, travels nowhere, and defaults to off.

**Local alias.** Contacts can be renamed locally; `effectiveName =
localAlias ?? displayName`. If a contact with an alias set renames itself, a
banner asks "adopt / keep alias". This is interface and storage logic and
touches no packet.

**Age declaration.** `isAdult` is a local self-declaration and a property of
the identity. It is defined here, travels in the request and the answer
(§15.5), and is presupposed elsewhere rather than redefined.

**Deduplication.** Incoming requests are deduplicated by the hash of their
content. This carries no weight as flood protection — it recognizes
identical packets, not varied greetings; that is the buffer's job (§15.4).

**No rate limit per sender.** A limit of "X requests per sender per hour" is
ineffective: identities cost nothing to create, and the sender is not known
until the envelope is open. Eviction, the code and the cap on open
invitations do that work instead.

**NFC exchange.** A touch can carry both cards in one operation, so both
sides end up holding the other's card and either may start the five
packets. Addresses learned in the process are reachability hints like any
other (§6.2).

**Several identities of one user** are not listed anywhere. There is no
directory that could be queried; the association exists only on the user's
own devices.

### 15.11 Residual risks

**Residual risks.**

1. **The anonymous bundle exchange is unsealed.** Packets (0) and (1) carry
   no identity, but anyone holding a card can send the anonymous form of
   packet (0) and learn, from whether packet (1) comes back, that the node
   is running. The window is bounded by the rule that this form is answered
   only while an invitation is standing (§15.1), and by revocation and expiry —
   not closed. The signed form does not widen it: only a party that already
   holds the bundle as a contact can produce one.
2. **A decline tells the requester the request was seen.** This is a narrow
   signal and it is not a probe. It reaches only a party that sent a
   **complete sealed request bearing a valid code**, and that request was
   **shown to the issuer's user**, who acted on it. Nothing here can be
   learned quietly or in passing. The alternative — silence — would leave an
   honest requester unable to tell a decline from a loss, which is the
   larger harm (§15.5).
3. **A leaked card is a usable card** until its code expires, is revoked,
   or its acceptance count is exhausted. The acceptance question is what
   stands between a leaked code and a contact; an open invitation handed to
   a group is a deliberate standing offer, and the interface must say so
   where it is created.
4. **A flood is made expensive, not impossible.** The proof of work
   (§15.5.1) puts about a second of computation behind every request, the
   kind of invitation (§15.3) bounds how many requests can become contacts,
   and revocation ends a flooded invitation. An attacker with enough
   hardware can still occupy buffer slots for as long as the invitation
   stands; what that costs him is a second per slot, and what it costs the
   issuer is ten hashes and one revocation.
5. **A former contact keeps the identifier.** Blocking ends delivery but not
   sending; the post box entries of a blocked party occupy the per-day-value
   cap until they expire. The complete remedy is a new key bundle, at the
   price named in §15.9.
6. **Restoring an old invitation list re-arms a revoked invitation**
   (§15.3). The opposite failure — losing the list entirely — is
   fail-closed, and the two cannot both be closed by the same mechanism.
7. **Address hints in a card go stale.** A card with a long or unlimited
   validity outlives the addresses printed in it. Stale hints fail silently
   by construction; what remains is the rest of the ladder (§7, §8), and a
   card whose every hint is stale reaches nobody without producing an error.

**Open measurement.** No design question is left open in this chapter, but
one value in it is not final: the difficulty `D` (§15.5.1) is printed as 20
and 22 bits provisionally. It is fixed by measuring, on the weakest
supported target device, the time to produce a solution, and setting `D` so
that time is about one second. Until that measurement exists, the two values
are placeholders and are to be treated as such.

### 15.12 Parameters

| Name | Value |
|---|---|
| card size | **91 B** (no address at all, count `0`, no publisher key) … **98 B** (one own IPv4 address) … **413 B** (four own IPv6 addresses, a neighbour in IPv6, the publisher key, three relay entries of 64 characters) |
| card as base64url | 122 / 131 / 551 characters — `ceil(n × 4 / 3)`, no padding |
| text form, whole line | 133 / 143 / 563 characters including `cleona:1:` (9) and the 2-byte checksum |
| text form checksum | CRC-16, polynomial `0xA001`, init `0xFFFF`, 2 B little endian |
| channel byte | `0x00` live, `0x01` beta; any other value rejects the card |
| address type byte | `4` = IPv4, `6` = IPv6; any other value rejects the card |
| fingerprint | the identifier of §4.1 (32 B) |
| key bundle | 3168 B |
| code | 16 B random |
| random value in packets (0)/(1) | 16 B |
| bundle request, anonymous form | 17 B; 40 B (IPv4 neighbour) or 52 B (IPv6 neighbour) with a return way |
| bundle request, signed form | 117 B; accepted from a stored contact only |
| signed bundle request, clock window | ± 300 s |
| expiry field | u32 LE Unix seconds; `0xFFFFFFFF` = unlimited |
| validity tiers | 7 d / 30 d / 90 d / unlimited |
| default validity | **90 d** single kind, **7 d** open kind |
| expiry warning at the requester | less than 7 d remaining |
| issuer acceptance window | expiry + 7 d |
| standing invitations per node | max. **10**, all of one identity (neither revoked, expired nor used up) |
| kinds of invitation | **single** (default) or **open** |
| acceptances, open kind | `n`, default **20** |
| spent, single kind | after the first **accepted** request |
| proof of work | `SHA-256(code ‖ random ‖ counter ‖ time window)` with `D` leading zero bits |
| proof of work, visible fields | 8 B random value + 8 B counter |
| time window | Unix minutes ÷ 10 — a solution lasts about 10 min |
| replay memory | random values of the current and previous window, max. **1000** |
| difficulty `D` | **provisional**: 20 bits single, 22 bits open — to be set by measurement so that solving takes ≈ 1 s on the weakest target device |
| check cost at the issuer | at most 10 hashes, independent of `D` |
| request buffer | **20** per invitation, **100** in total, evicting |
| display name | ≤ 64 characters |
| greeting text | ≤ 280 characters |
| request payload cap | 8 KB including preview |
| picture preview in the request | ≤ 4 KB |
| picture in a profile update | ≤ 64 KB |
| profile description | ≤ 500 characters, plain text |
| profile updates | max. 1 per hour |
| envelope fixed cost | 7696 B |
| request on the wire | 7729 B with a bare code payload — seven parts |
| key-change announcement | payload ≤ 6547 B, packet ≤ 14244 B — twelve parts |
| verification levels | `unverified` / `seen` / `verified` / `trusted` |
| relationship states | active / deleted / blocked |
## 16. Groups & Channels

> **The procedural logic of moderation is fully and conclusively codified
> in §16.4–§16.6;** the delivery layer supplies the transport underneath it.
>
> **Hard constraint (project owner):** No authority solution. No special
> key, no named authority, no pinned feed with override access — not
> even for the maintainer. Capabilities that exist can be coerced,
> stolen, or inherited. Both reviewed authority variants were rejected,
> including the weak one (a public block list), because a public CSAM
> list would be a signpost. Reviewed counter-designs exist as analyses
> and remain fallback options.
>
> **Four design features carry this chapter:** the juror registry lives
> as a replicated durable object (§16.0); it lists **HD-derived role
> pseudonyms**; notification runs by **pull** (no one is addressable);
> voting runs by **Linkable Ring Signature**.
>
> **What explicitly remains open — review items, not a gap.** Three
> constructions are justified but not proven: the ring-signature vote,
> the verifiable class state together with inclusion proofs, and the
> question of whether the class-state roots converge sufficiently
> network-wide. The external crypto review of this is **optional** at
> release readiness; until a proof or review exists, registry age
> counts as a strong hurdle, not as proof.

### 16.0 The durable-object class

Moderation needs objects that **outlast a single delivery's TTL** and
**cannot be evicted by flooding**: a case must survive a 30-day
procedure, a verdict must survive indefinitely, a juror registration
must age for 7+ days. Ordinary cells (placed to relays, harvested on
cadence, TTL-bounded) do not offer this — they are a delivery
primitive, not a storage primitive. Hence the **durable-object class**:
a set of public, self-verifying objects (registrations, directory
entries, cases, verdicts, tombstones) replicated across relays by
**anti-entropy** (gossip/sync between relay pairs), with a per-class
**state root** (a Merkle root over the sorted object IDs of the class)
as the convergence anchor.

**What this is, and is not.** This is a per-class, relay-replicated
anti-entropy store for *public, verifiable* moderation objects. It is
**not** the global network-wide Merkle
index that recovery (§13) rejected: there is no single convergent root
every node must hold, and a private object readable only by its owner
(a recovery bundle) is explicitly excluded from being a durable object
(§13.3.4 — no checkable proof, unbounded producer). Public moderation
objects have neither problem: every node can verify them, and their
production is gated by registration age and the procedure.

**Feed-in via the cover stream.** Registration, case, and verdict
objects are **fed in via the cover stream** — first placed as an
ordinary cell in the cover stream and only adopted into the
class after diffusion by relays (authorship hidden within the cover; a
latency of hours is uncritical for these types). The durable-object
class therefore inherits the cover-stream mixing for feed-in, and the
anti-entropy replication for durability — two different substrates for
two different needs.

**Anti-backdating anchor.** A backdated registration acknowledgment is
checked against the **previous epoch's class-state root**, named in
`k = 2` cross-partition relay attestations (the same primitive §13.4.2
established for the distress call). Cross-partition relay attestations
provide this anti-backdating property instead of a global
Merkle-convergence anchor: weaker in the global sense but sufficient,
and it reuses one primitive across recovery and moderation.
Whether the roots converge sufficiently network-wide is **not proven**
and remains a review item; until then, registry age counts as a strong
hurdle, not proof.

### 16.1 Two spheres

| | Private sphere | Public sphere |
|---|---|---|
| Objects | contacts, groups, private channels | public channels, directory, moderation cases, system channels |
| Tags | from pairwise secrets — only participants can form them | publicly derivable **tag families**, e.g. `HKDF(objektId, zweck[, epoch])` — concrete families: §16.3 |
| Reading | tag match of the participants | passive harvesting |
| Writing | secret possession = write right (KEX gate as a structural property) | only with **carried proof** (role, verdict, registration) |
| Moderation | does not exist — no unauthorized person can reach you | core of this chapter |

The private sphere follows §4.3; groups create no shared tag-line
correlation.

**Read anonymity, honestly.** Whoever reads a public channel reveals
to their respective **sync partner** the candidate set of their
subscriptions: the directory is public, the tag-line prefix is
computable from every published `channel_secret`, and the partner sees
the subscription list. Decoy dilution works against this enumerable
target space only as a factor, not as an anonymity set; decoys for the
public sphere are therefore drawn from the same set as the real
subscriptions (tag lines of real channels). Against **all other
observers**, reading is unobservable. Only objects — never persons —
are publicly addressable.

### 16.2 Groups (private sphere)

**This section is the only place that constructs group delivery.**
Chapter 9 describes the delivery of *one* message; a group message is not
a new kind of delivery, it is N of them. Nothing about groups is defined
outside this section.

Groups use **pairwise legs** — a group message is N ordinary 1:1
deliveries, one per member, each sealed to that member alone (§4.3) and
carried by the ladder (§7, §8); no group key, no group-level address, no
inner signature (the pairwise seal authenticates each leg in a
symmetric-deniable way). Roles, invites, and member management travel the
same way, as ordinary 1:1 deliveries over the same legs.

**Fan-out does not serialize.** Every leg leaves the device the moment
it exists (§3.1); legs to different members do not wait on each other.

#### 16.2.1 The threshold, and what it buys

A group is one kind of object; a **large private channel** is another.
The line between them is a size:

| | Group, **N ≤ 16** | Large private channel, **N > 16** |
|---|---|---|
| construction | pairwise legs | shared key `K_C` |
| inner signature | none | Ed25519 (§4.4) |
| forward secrecy | **per message** (§4.6) | daily, plus rotation on membership change |
| deniability | symmetric | none — the signature attributes |
| anonymous polls (§18.4) | possible | not possible |
| subscription correlation toward the sync partner | structurally absent | mitigated only statistically (§23.6, RL-3) |

Measured cost for a short line of text:

| Members | pairwise legs | shared key |
|---|---|---|
| 3 | 23,181 B | 19,953 B |
| 10 | 77,270 B | 19,953 B |
| 16 | ~123,600 B | 19,953 B |
| 50 | 386,350 B | 19,953 B |

**Pairwise is never the cheaper way** — the two constructions meet at
N ≈ 2.6, and beyond that the pairwise cost grows by roughly 7,730 B per
member. The threshold therefore does not ask which construction is
cheaper. It asks **up to which size the four properties in the first
table are worth their bytes**, and that is a judgement, not a
calculation.

**Sixteen is set, not derived.** It caps the most expensive pairwise
group at roughly 124 KB and leaves the group sizes a private messenger
normally has inside the class that keeps everything. A different number
changes this one place and nothing else — which is the point of not
introducing a third construction.

**This is a property of the object, not a mode.** §3.3 allows exactly one
way to send, and nothing here selects a way per message or per chat: a
group is a group, a large private channel is a large private channel, and
each has exactly one construction.

**Why the shared key is not used below the threshold.** It would cost
per-message forward secrecy (down to daily), symmetric deniability (a
shared key requires an inner signature) and the property that groups
hold no subscription at all, and those three are the reason pairwise
legs exist.

#### 16.2.2 Roles, invites, membership

- **Role model.** Groups know three roles: **Owner** (full control,
  appoints admins, configures the group), **Admin** (invites/removes
  members, moderates, changes settings), **Member** (reads + posts).
  Private channels use the same hierarchy with **Subscriber** (read
  only) instead of Member. The owner decides whether members may post
  (discussion vs. announcement mode). Settings (name, description,
  image, posting policy, message expiry) are changed by the owner or
  admin. Role updates go to **all** members, not only the one affected —
  otherwise the members' views would diverge.
- **UserID invariant (normative).** Groups and channels are **user
  constructs**: the member list is keyed exclusively on the stable,
  device-independent UserID (§4), never on device identities. All
  checks — roles, administrative rights, post authorization,
  leaving/joining, ownership transfer — run against the UserID.
- **Invites.** An invitation contains the group ID, name, optionally an
  image and description, as well as the **complete member list** (the
  invitee knows every participant before joining) and travels as an
  ordinary 1:1 delivery over the pairwise leg to the invitee — only they can
  read it.
- **Membership consistency.** Every group keeps a **monotonically
  increasing membership epoch**; every mutating operation (creation,
  invite, removal, role change, leaving) increments it before sending.
  Recipients discard updates with an epoch ≤ their local state
  (replay/downgrade protection). Over (epoch, group ID, sorted
  UserID-role pairs), a **canonical membership hash** is formed —
  deterministic, independent of insertion order, without display names
  and images. Only the owner/admin may mutate; the recipient checks this
  against their **old** member state (authority gate) — the sender
  identity per leg is fixed via the pairwise secret, so no inner
  signature is needed for this. Posts from non-members are silently
  discarded. Every post carries epoch + hash: a recipient who sees a
  newer state requests a resync from the owner **once per observed
  epoch** (who responds with the full signed member state); the same
  epoch state with a differing hash is logged as a **split-view
  anomaly**.
- **Leaving & ownership transfer.** Leaving removes the local
  conversation along with the membership record (an ex-member can no
  longer interact anyway). If the owner leaves a group with remaining
  members, the owner role passes **automatically** to the first admin,
  or otherwise to the first remaining member; the transfer is
  distributed to everyone before the leave, and recipients apply the
  same transfer logic independently. If the last member leaves, the
  group is silently removed. The UI secures leaving with a two-stage
  confirmation dialog that names the transfer recipient to the owner.

There is no group-level shared addressable state: every leg is an
ordinary pairwise delivery, and a group has no address of its own that a
departed member could keep watching.

#### 16.2.3 Delivery state of a group message

The state shown for a group message is the **weakest across all members**,
using the four states of §9.1 and no others — the set of four is not
extended for groups. Members are fixed at the moment of sending: whoever
joins afterwards does not receive a message that is already on its way.

**Per-member delivery tracking:** whether delivery confirmations may
appear as a delivery symbol at the sender is decided by each recipient
**unilaterally and locally** per contact/group (default: disclose); the
setting is never negotiated but travels as a bit on the confirmation
itself. The transport consumes every confirmation unconditionally (it
is a transport primitive, §9); only the UI stage `sent → delivered`
respects the bit. A group message shows `delivered` only once **every**
leg has confirmed **and** is disclosing; a withholding leg never
contributes to the visible aggregate status — otherwise the aggregate
would reveal exactly what the member wanted to conceal. Partial
displays ("3 of 5") count only disclosing members.

### 16.3 Public channels as an object space

A public channel is an **object** with a public identity
`channelId = Hash(CreatorPubKey)` and a tag family:

```
tag_post   = HKDF(channel_secret, "post" ‖ epoch ‖ n)      // content (secret published in the directory)
tag_report = HKDF(channelId, "report" ‖ epoch)             // channel reports — derivable by anyone
tag_jury   = HKDF(fallId, "vote")                           // feed-in path of jury votes (§16.4; the vote itself is a durable object)
tag_admin  = HKDF(channelId, "admin" ‖ epoch)              // individual-post reports to admins
```

Cases and verdicts are **not** ordinary cells but durable objects
(§16.0/§16.4) — they need adversarial durability, which a TTL-bounded
delivery does not offer by construction. The category of a report
lives **in** the report content, not in the tag (one tag per channel
and epoch; the grinding surface goes away).

- **Publisher registration (occasions restricted).** Whoever operates
  public objects (channel owner) or reports countably (§16.4) does so
  under a **registered role pseudonym** (§16.5). The registration is a
  durable object with a certified registration tag; the qualifying
  quantity is the verifiable property "registration ≥ 7 days old". The
  app registers the role pseudonym proactively when "I am over 18" is
  activated, so that it has aged by the time it is needed. **A channel
  subscription explicitly does not trigger a registration:** it is a
  purely private act, and translating it into a public, dated object
  would give up read anonymity from §16.1 at its most sensitive point.
  The over-18 toggle, by contrast, is a one-time setting with no
  reference to a specific channel, and the over-18 attribute is
  already in the registration object anyway.
- **Directory:** a durable object (§16.0) per channel — name,
  language, rating, description, `channel_secret` (for public ones),
  badge state, tombstone reference. Search = harvest the directory +
  filter locally (name, language; NSFW entries are hidden client-side
  for identities without an activated over-18 self-declaration).
  **Sort signal of the search (normative):** sorting is by **post
  frequency of the last 14 days**, determined from the local relay
  holdings — the signal measures activity, not popularity, and is
  labeled as such in the UI. A subscriber count does not exist: reading
  is passive harvesting, no one registers anywhere (§16.6, §16.8).
  **Name FCFS:** the age of an entry is the day of its **earliest
  first-acceptance acknowledgment** (there is no such thing as a
  self-claimed date); on a name collision, the **older entry
  registration** wins — registration time, not identity age; this rules
  out retroactive name theft by old identities. Tiebreak on an
  identical day: the lexicographically smaller `channelId`
  (anti-entropy converges). Name equality is checked normalized to
  lowercase. Channel creation requires a **publisher registration ≥ 7
  days old**.
- **Posting:** owners/admins sign with publisher keys (asymmetric
  distribution as in §4.3); subscribers can read, not write.
- **Channel polls:** votes as cells under the poll tag family, sealed
  against the publisher pubkey (only the creator reads votes), tally
  anonymity via Linkable Ring Signature (§18.4); `POLL_SNAPSHOT` as a
  channel post. It stays O(N) rather than O(N²): voters send only to the
  creator, and the creator distributes the vote count as **one** post
  to everyone — no vote fan-out among the subscribers (§18.3.3).
- **Contact with a member:** only if the member themselves puts a
  ContactSeed into their post profile — a deliberate self-publication,
  not a system path; otherwise a person would be publicly addressable
  (a breach of §4.3).

### 16.4 Moderation of public channels

This section codifies the moderation procedure fully and conclusively;
it also describes how each procedural step maps onto the underlying
delivery primitives.

**The procedural logic (normative).** Six report categories:

| Category | Description | Procedure |
|---|---|---|
| **Not safe for minors** | channel marked safe-for-minors but contains NSFW | jury (standard) |
| **False content** | content does not match the channel description | jury (standard) |
| **Illegal: drug trafficking** | offers/trade in illegal substances | jury (standard) |
| **Illegal: weapons trafficking** | offers/trade in illegal weapons | jury (standard) |
| **Illegal: CSAM** | child pornography | **special procedure without a jury** (§16.6) |
| **Illegal: other** | other illegal content | jury (standard) |

A channel report names **3–10 concrete posts** as evidence. The jury
sees exactly: channel name, description, language, Content-Rating, the
3–10 evidence posts, and the report category — never more. Consequence
at 2/3 approval per category: *Not safe for minors* → NSFW
reclassification; *False content* → bad badge (escalation stages below);
*Illegal (not CSAM)* → channel tombstone via the consequence classes
below, i.e. only after two independent procedures.

**Numeric parameters of the procedure (normative).** The following
production values apply to the entire moderation procedure
(implementation location: `lib/core/moderation/moderation_config.dart`):

| Parameter | Value |
|---|---|
| Trigger threshold of a case | `min(50, max(5, Registrierungen_Sprache × 0.005))` valid, deduplicated reports per category (ceiling added) |
| Threshold modifiers | doubling with < 5 available jury candidates; halving on continuation of a tombstoned channel (identical evidence-post hashes, limited to 90 days, not cumulative) |
| Evidence per channel report | 3–10 concrete posts |
| Report qualification (standard) | registration ≥ 7 days |
| Report rate limit | 5 reports per pseudonym and day; exactly one report per pseudonym counts per category and epoch (publicly deduplicated) |
| Individual-post escalation | report ≥ 7 days old without an admin resolution object → counts toward the channel report counter |
| Jury size | `min(11, max(5, Kandidaten × 0.01))` — i.e. 5 up to 500 candidates, then 1 % of them, capped at 11 |
| Juror qualification | registration ≥ 7 days, over-18 flag, opt-in "evaluate channel reports" |
| Quorum | 2/3 of the **nominal** jury size, rounded up (5 jurors → 4 approvals) |
| Juror timeout | 2 days without a vote → seat becomes free |
| Replacement rounds | only as long as ≥ 5 seats are open; no round limit |
| Tolerance check | signer accepted if among the 2 × `jurySize` XOR-nearest candidates to the selection point |
| Procedural deadline (wall clock) | 30 days from case creation, thereafter closure without a result |
| Bad-badge probation | stage 1: 30 days, stage 2: 90 days after correction; stage 3 permanent |
| Channel creation | publisher registration ≥ 7 days |
| CSAM stage-2 quorum (Temp-Hide) | `min(100, max(10, Registrierungen_Sprache × 0.01))` (ceiling added) |
| CSAM stage-3 quorum (permanent) | `min(200, max(20, Registrierungen_Sprache × 0.02))` (ceiling added) |
| CSAM Temp-Hide duration | 14 days |
| CSAM appeal window (stage 3) | 14-day filing deadline; an ongoing appeal proceeding holds stage 3 until it concludes (§16.6) |
| CSAM reporting bond | 7-day report lock in **all** categories per CSAM report |
| CSAM reporter qualification | registration ≥ 30 days + over-18 flag |

**Reports.**

- *Individual post:* cell under `tag_admin`; admins decide. The 7-day
  escalation is **deterministically derivable from the holdings**: an
  individual-post report with an age ≥ 7 days for which no admin
  resolution object exists automatically counts toward the channel
  report counter — every observer evaluates it identically, no single
  reporter device has to survive. (Possible because the default TTL is
  14 d, long enough for every observer to have seen it.)
- *Channel report:* cell under `tag_report` with category + 3–10
  evidence-post references, signed by the **registered reporter
  pseudonym** (≥ 7 days, §16.3/§16.5; this closes R-10: exactly one
  report per pseudonym counts per category and epoch; multiple reports
  are publicly recognizable and get deduplicated). The report rate
  limit is bound to the registered pseudonym, not to a user or device
  identity — fresh identities are free, only aged registrations are
  scarce.
  **Eviction protection:** the publicly derivable tag families get
  their **own quota in the tag-line budget (~5 %)**, which ordinary cells
  cannot occupy; eviction inside that quota follows the same rules as
  everywhere else (§9). A relay can derive these tags itself and
  therefore recognize the cells; the public sphere is not wire-blind
  anyway. In addition, the reporter app re-places its report (the report
  feeds into the durable-object class, §16.0, so it outlasts its own
  delivery TTL).
- The report qualification is solely the **registry age of the reporter
  pseudonym** (§16.5); no connectedness check between reporters takes
  place, because the connectedness of two unrelated identities cannot be
  determined without a queryable third-party state.

**The case.** Once the locally counted report tally reaches the
threshold, the case comes into being as a **durable object** (§16.0).
**The threshold:**
`min(50, max(5, Registrierungen_Sprache × 0.005))` — the reference
quantity, as with the CSAM quorums (§16.6), is the enumerable registry of
the channel language (derivation of the denominator: §16.6).

**Why all three registry-scaled thresholds carry a ceiling.** Without
one they grow linearly and without bound, and Cleona is meant to scale
from a handful of scattered systems to a very large field. At a hundred
million registrations in one language the permanent-deletion quorum
would demand two million distinct qualified reporters **for a single
channel** — the number of people who report a given channel does not
grow with the language community, so the procedure would not become
stricter, it would become **unreachable**. §16.6 already names one half
of this ("large channels are thus relatively easier to attack than
small ones"); the other half is that legitimate deletion dies at the same
denominator. Each ceiling is **ten times its own floor**, so the
graduation between the three thresholds is preserved exactly — and
because floors and rates share that ratio, **all three ceilings take
effect at the same point: 10,000 registrations.** The percentage
therefore governs exactly one decade, from 1,000 to 10,000
registrations; below it the floor rules, above it the ceiling. The value
200 for the permanent stage is **set, not derived** — it says an attacker
needs 200 aged pseudonyms at any community size, and it is one of two
lines of defence, the other being the 14-day appeal window with its
content-blind plausibility jury (§16.6).

Two modifiers apply to the trigger threshold: doubling with fewer than
5 available jury candidates, halving for a channel that continues the
content of a tombstoned one — the trigger is **identical evidence-post
hashes**, not the name (§16.4, "Limit of enforcement"). Its proof is the
report set itself (the threshold count of valid, deduplicated report
cells is carried along). **Canonical report set:** the `threshold`
**oldest** valid reports are carried along, and the `tag` entering the
selection point H is the tag of the **latest report cell of this carried
set** — not the tag at which some individual node happened to harvest the
threshold to completion. Both quantities are thus readable from the
object content itself and identical for every checker; the attack
"delay-feed one's own report to generate two competing juries" thereby
disappears. Its content is therefore a deterministic function of the
report set — two independent placements of the same case produce
bit-identical objects and deduplicate (there is no grindable planter
role). The case contains: channel metadata, category, the
evidence-post references, the selection context (below), and — since
the procedure-fixed relay set — **all cells belonging to the procedure
follow the same responsible-relay set until closure**; this ensures that
a relay rotation in the middle of a procedure does not make parts of the
report set invisible. Cases are **discoverable** via the replicated
durable-object class — no language or jury tag line is needed.

**Jury selection (normative; implemented in
`lib/core/moderation/jury_selection.dart`).** Selection point and
selection:

```
H    = SHA-256("jury-select" ‖ channelId ‖ kategorieIndex ‖ tag ‖ juryRound)
Jury = the jurySize XOR-nearest registration objects to H
```

- None of the inputs is freely grindable by the reporter; `reportId` is
  deliberately excluded. `tag` is the tag of the **latest report cell of
  the carried evidence set** (above) — readable from the object content,
  identical for every checker, and not selectable.
- Candidate set: all registration objects of the juror registry (§16.5)
  with matching language, age ≥ 7 days, over-18 and opt-in flag in the
  registration object, that were not drawn for this channel in an
  existing earlier case (no-repeat — this holds within the lifetime of
  the case/verdict objects; the verifiable memory of the class does not
  reach further).
- Jury size (normative):
  **`min(11, max(5, Kandidaten × 0.01))`** — 5 jurors up to 500
  candidates, 1 % of them above that, capped at 11. Below 5
  candidates, no jury is formed and the trigger threshold is doubled
  instead.

  *Why the floor sits inside the formula and not beside it.* The `max`
  is what makes the band `5 ≤ Kandidaten < 500` well-defined:
  `Kandidaten × 0.01` reaches 5 only at **500** candidates, so a rule
  that stated a minimum of 5 and a cap of `min(11, Kandidaten × 0.01)`
  side by side would demand "at least 5, at most 1" across that whole
  band — at 100 candidates literally that — with nothing saying which
  bound wins. Nesting the floor inside the cap decides it. The band is
  not a corner case: `Kandidaten` is a strict subset of the
  registrations (language, registry age ≥ 7 days, over-18, opt-in, no
  repetition), so a language needs appreciably more than 500
  registrations to field 500 candidates — and the ratio between the two
  quantities is **not** specified anywhere.

  **The value is taken from the case object, not recomputed locally**;
  only plausibility is checked locally (5 ≤ `jurySize` ≤ 11). Otherwise
  the quorum denominator would hinge on the respective registry view: two
  observers with 900 and 1,150 known candidates, respectively, would
  arrive at 9 and 11 jurors, respectively, and would disagree not over a
  detail but over the procedure.
- **No-repeat is a property of the case object:** the case carries the
  excluded record IDs along with a reference to the earlier cases. If
  every observer derived the predicate "has already judged for this
  channel" from their **own** holdings, a node without the earlier case
  would draw a different jury — a divergence generator independent of
  any registry gap.

#### Verifiability of the selection (normative)

The XOR selection is **rank-based**: "the `jurySize` candidates whose
record ID lies closest to the selection point." Rank-based selection
presupposes that all participants know **the same candidate set**. The set
comes from a replicated store whose completeness cannot be established
locally. The bare tolerance check does not carry this: it tolerates at
most a **doubling** of the candidate set — the gap between a node four
weeks old and one that joined yesterday. With 5 % of the registry
missing, roughly a third of observers would reject a valid verdict, and
harvesters that do not hold the class in full could not check at all.

Therefore the case carries **two pieces of evidence** instead of just
one hash:

1. a **Merkle root over the sorted candidate record IDs** at the time
   of selection (a bare hash of the candidate IDs could indicate
   divergence but not resolve it: no set can be reconstructed from a
   hash);
2. an **inclusion proof** against this root for each drawn juror
   (11 × ~10 hashes ≈ 3.5 KB per case).

This makes the membership of every drawn candidate in the claimed
candidate set **positively verifiable without possessing the set** —
even on a mobile device. As an additional plausibility tier for nodes
that hold the registry anyway, the **tolerance check** applies: a
signer is accepted if, by their own registry view, they lie among the
2 × `jurySize` XOR-nearest candidates to the selection point.

**What this explicitly does not prove:** whether the claimed root
describes the *legitimate* candidate set. Against this stands only a
weaker rule — the root must be acknowledged by **≥ 2 independent
relays** as the current day's class state (§16.0). That is not
consensus, but it is a positive quorum instead of a self-declaration. The
construction as a whole is tracked as a review item.

**Pull instead of push.** No one addresses the drawn candidates. Every
opt-in juror pulls the **global index** of the durable-object class
(§16.0, ~48 B per object), recomputes H against it, and locally
determines whether their pseudonym was drawn. **They fetch the full case
only once they are actually affected** — against at least 2 independent
partners. This keeps the juror role portable on mobile devices and
makes the default "on" setting (the opt-in "evaluate channel reports" is
switched on by default once the over-18 declaration is activated) an
honest statement; if every juror pulled the complete case holdings of
all 34 languages, jurying would in practice be a desktop-only role, and
the node would additionally be recognizable as a juror to its sync
partner. The request then appears in the UI as a **locally computed
template** — there is no directed delivery path or receive capability;
§4.3 needs no exception.

**Vote via Linkable Ring Signature.** The juror places their vote
under `tag_jury`. **The tag is the feed-in path:** the vote is placed
as an ordinary cell (this way the cover stream conceals authorship,
§16.5) and taken over by the relays into the durable-object class,
where it neither expires with the delivery TTL nor can be evicted by
flooding. Content:

```
vote = (fallId, stimme, LRS-Signatur)
Ring = the jurySize drawn pseudonym pubkeys per the case object
Key-Image deterministic from (sk_pseudonym, fallId)
```

The primitive already exists
(`lib/core/crypto/linkable_ring_signature.dart`, MLSAG style, used by
the anonymous polls §18.4). Properties:

- **Ballot secrecy:** what is visible is *that* a drawn juror has voted
  and *how many* votes exist per option — not **which** juror voted how.
  The retaliation path against individual jurors is closed; the vote
  **distribution** is public — it is the quorum proof.
- **Double vote:** the key image is deterministic per (key, case) — two
  votes from the same juror are recognizable as a duplicate and count
  once. Across cases it remains unlinkable.
- **No last-mover advantage:** there are no tickets to underbid; the
  selection is fixed before the first vote.

**Voting and replacement (normative).** A 2/3 majority **of the
nominal jury size** is required for a measure (not of those who showed
up). Options are Approve / Reject / Abstain; only approvals count toward
the quorum.

- **Effect of the three options on the seat.** A *no* consumes the
  seat permanently — correspondingly more of the remaining seats then
  have to approve. An *abstention* frees the seat **immediately**; a
  *timeout* (2 days without a vote) does too, only later. Abstention and
  no are therefore **not** equivalent: the no blocks, the abstention
  opens a fresh juror for the case. The option exists because it speeds
  up replacement by up to two days — the price is the juror's consumed
  key image.
- **Replacement rounds.** `juryRound + 1` draws the next XOR candidates
  for the open seats, **but only as long as at least 5 seats are open**.
  If there are fewer, the case is closed with the state on hand — this
  way the ring of a replacement round can never fall below 5 members,
  and the ring signature can never shrink to an attributable individual
  signature.
- **Denominator stays nominal.** Whoever was replaced in a replacement
  round **loses their voting right**; their key image no longer counts.
  The quorum denominator therefore stays the nominal jury size and does
  not dilute over the rounds. Verifiable, because the draws of every
  round are recorded in the case object.
- **Procedure duration.** There is **no round limit**; the vote objects
  live in the durable-object class (§16.0) and do not expire with the
  delivery TTL. This also closes the eviction attack on the votes
  (there is no flooding eviction in the durable-object class).
  **Wall-clock upper bound (normative):** a case that does not reach the
  quorum closes without a result **at the latest 30 days after its
  creation**. Without this limit, there would be nothing that ever ends
  a procedure — and three kinds of harm would follow: a dead case would
  permanently occupy ~20 KB of a budget meant for ~100 cases; via the
  no-repeat rule it would consume, round after round, the jurorship of
  its language and thereby **immunize the channel against any future
  moderation**; and the channel would indefinitely and visibly carry the
  state "procedure running." The retention rule of the type table does
  not catch this — on the contrary: it counts "until closure + 30 d,"
  so its clock only starts with closure.
- Even cases without a result (rejection, closure without quorum)
  leave behind a closure object, so that no-repeat and the procedure
  history remain verifiable.

**Verdict.** The quorum of ring signatures against the selection fixed
in the case forms the **verdict proof**; it is attached as a durable
object to the channel's directory object: NSFW reclassification, bad
badge (with probation state), or tombstone. A tombstone means at the
user level: the channel disappears from search (its directory entry is
replaced, "limit of enforcement" below), the client creates no new
subscriptions to it, and the content expires on its own with the delivery
TTL. **Verdict cryptography (normative):** the verdict core hash is
SHA-256 over `juryId ‖ channelId ‖ reportId ‖ vote ‖ consequence ‖ tag
‖ juryRound`; the votes are ring signatures over this core hash.
Feedback to the reporter: no directed message — the reporter harvests
the verdict themselves (they see the result "action taken / no action";
the vote distribution is publicly viewable, above).

**Canonical form.** Ring signatures are randomized — two nodes
assembling the same verdict would otherwise produce two different, both
valid, objects that do not deduplicate and occupy the sub-budget twice.
Hence, normative: the verdict object carries **exactly `quorum` votes
— the ones with the smallest key images —, sorted ascending by key
image.** This way, two assemblers produce bit-identical objects, just as
with the case object. Any relay that has the votes is responsible; who
places it is immaterial. **Precedence:** an action verdict **takes the
place of** a closure object of the same case, never the reverse; a closure object
"without result" may only be placed after the procedural deadline has
expired.

**Consequence classes (normative).** CSAM is excluded from this and
runs via its own path in §16.6.

| Class | Actions | Procedure |
|---|---|---|
| **Reversible** | NSFW reclassification, bad badge + probation | one jury procedure |
| **Irreversible** | channel tombstone | **two independent procedures**: two cases, two draws, the second with a disjoint jury (excluding everyone drawn in the first procedure), **temporal gap ≥ 7 days**. Alternatively, an **objection period** suffices, in which the channel operator forces escalation to the second procedure by mere objection |

**Exception CSAM.** The permanent deletion in the CSAM procedure is
likewise irreversible, but does **not** run via these classes: the §16.4
jury sees the evidence-post references, which the special procedure
specifically excludes. Its own path — reporter quorum, expired appeal
window, content-blind plausibility jury — is in §16.6.

An irreversible consequence from a single procedure would be the most
dangerous combination in this chapter; the second jury is the price of
finality.

**Bad-badge escalation (normative).** The bad badge is a **trust
signal** to prospective subscribers ("caution, content and description
do not match"), not a punitive mechanism. Three stages:

| Stage | Trigger | Label | Probation |
|---|---|---|---|
| **1** | first confirmed "false content" verdict | "content questionable" | 30 days after correction |
| **2** | second confirmed verdict during probation | "repeatedly misleading" | 90 days after correction |
| **3** | third confirmed verdict | **permanent**, not removable | — |

The badge remains until the owner corrects the name or description;
probation starts after the correction. A new confirmed verdict during
probation escalates to the next stage; if probation runs out without a
new verdict, the badge state drops. Channels are **never hidden**
because of a badge — stages 1–2 sort down in search with a warning
icon, stage 3 to the end with a clearly visible warning notice; the
decision stays with the user.

**Bad-badge probation.** The transition "correction submitted" is not
a claim by the owner but a **verifiable event**: probation begins when
the channel's directory object carries a changed name or a changed
description since the verdict (comparison of object hashes; the owner's
renewal of the directory entry is a permissible object type anyway). If
the probation period expires without a new confirmed verdict, every
node lowers the badge state locally — deterministically from the
verdict timestamp + period, no timer actor needed.

**Limit of enforcement (declared).** Moderation acts against
**objects**, not against persons — this is a permanent structural
property: an operator can re-create a tombstoned channel under a new
key. Three rules take the edge off this: (1) A tombstone **takes the
place of** the directory entry of the same `channelId` and suppresses every later
renewal — its lifetime is tied to the directory semantics, not shorter
(no self-resurrection). (2) A new channel starts with a **halved report
threshold** for the same category if it continues the content of a
tombstoned channel (person-free, compatible with the
objects-not-persons property). **Binding:** the trigger is **not the
name alone** — otherwise any term could be permanently burned by
someone creating a channel of the same name themselves and bringing
about its deletion. The halving applies only if **the same
evidence-post hashes** reappear; it is limited to **90 days** after the
tombstone, **not cumulative** (multiple tombstones do not halve
repeatedly), and the name comparison is done normalized to lowercase.
(3) The owner's publisher registration must be kept 7 days old —
re-creation therefore costs at least the aging of a fresh pseudonym, if
the operator wants to avoid the link to their old pseudonym.

### 16.5 Juror Registry and Role Pseudonyms

**The registry is durable-object holdings.** Per role pseudonym,
**one** registration object:

```
registrierung = { pseudonym_pubkey, sprache(n),
                  flags (ü18, opt-in-jury), sig_pseudonym,
                  erstannahme_quittungen[k] }
```

There is **no** self-asserted registration date; age is the day of the
earliest acknowledgment. The over-18 flag is a **self-declaration** in
the registration object; it is not externally verifiable, and this is
declared as such.

**Key validity (normative).** A registration object is **only
replicated** if `pseudonym_pubkey` is a valid Ed25519 point not lying in
a small subgroup **and** the self-signature verifies. Reason:
`LinkableRingSignature.verify()` rejects the **entire** ring as soon as
a single member fails the point check — a crafted pseudonym in the draw
would otherwise render every vote of that jury unusable. If such an
object nevertheless ends up in a draw, the case is **immediately
eligible for a replacement round**, without waiting out the two days.

**Signature variant (normative): Ed25519 only** — `pseudonym_pubkey` is
an Ed25519 point (the vote's ring signature requires this
unconditionally), `sig_pseudonym` an Ed25519 self-signature. No ML-DSA:
it would prevent the forgery of *new* objects, while a CRQC attacker
simply computes the private keys of **already registered** jurors and
votes as them — at a factor-17 storage cost (~5,580 B instead of ~320 B
per object) and thus roughly 1,100 instead of 19,000 sustainable
registrations network-wide. Full rationale and the declaration "the
object space is classically secured": §4.4.

- **Age from relay attestations.** The object asserts no date. `k`
  independent relays acknowledge on acceptance (object hash ‖ own day of
  receipt); age is taken as the day of the **earliest** acknowledgment.
  One object per pseudonym (~320 B). No presence requirement: someone
  who was offline for two weeks loses nothing; the registration lapses
  only when the annual renewal is missed (90-day grace period). And
  because no time window is checked, the node may freely choose the
  feed-in time — a prerequisite for the bundling below.
- **Anchor against backdating (closes O-25).** Every acknowledgment
  **names the previous epoch's class-state root** (§16.0); a backdated
  acknowledgment can thus be checked against what other nodes saw on
  that day — collusion becomes provable rather than merely expensive. In
  addition, the `k` acknowledgments must come from different partitions,
  insofar as this is locally determinable. **Remaining:** whether the
  roots converge sufficiently network-wide is not proven (§16.0); until
  the external review confirms this, registry age counts as a **strong
  hurdle, not proof**.

**Pseudonyms.** The juror role never runs under the main identity, but
under a dedicated **HD-derived secondary identity** (multi-identity
mechanics, §4) — the registry lists exclusively role pseudonyms, never
user keys. Only this is made public: "a registered pseudonym was drawn /
has judged." The link to the main identity is never published anywhere.

**Write-path correlation (mitigated).** The durable-object path does
not automatically have the cover stream's mixing property. Hence,
normative: (1) Registration, case, and verdict objects are **fed in via
the cover stream** — first placed as an ordinary cell in the cover
stream and only adopted into the class after diffusion by relays
(authorship hidden within the cover; a latency of hours is uncritical
for these types). (2) The app **jitters** registration and renewal times
and never registers more than one of its own pseudonyms within the same
window. (3) **Bundling (normative):** a node feeds in an object of its
own only together with at least `k` **third-party** objects of the same
class — it collects until enough third-party objects have passed
through, then hands everything on together. This is necessary because
the cover-stream mixing of §5 does not fully carry for publicly
readable objects: against a single honest partner it does, but an
attacker who syncs with many relays at once (fake relays are cheap) can
narrow down the origin via the timing of first sightings. Bundling, by
contrast, establishes a genuine, if small, anonymity set; it costs
hours to days of delay, which is free — waiting only costs age, and that
grows in the reserve anyway. The remaining channel (vote times
correlate with the main identity's online times) is a documented
residual leak.

**Documented residual leaks.**

1. The **number** of registrations per language is publicly countable.
   This is simultaneously the basis of verifiability (XOR selection over
   an enumerable set) and gives an attacker the sizing target for their
   pseudonym fleet.
2. The **selection drawn per case** is public (it is the selection
   proof). It counts pseudonyms, not persons.
3. **Encrypting the registry is fundamentally impossible**: there is no
   "the network" as a trusted party — every evaluation key would sit
   with the attacker as soon as they start a node.

**The Sybil picture, honestly.** An entry costs a registered pseudonym
at least 7 days old; registrations are parallelizable, and whoever
controls the reporting time can know H days in advance and grind keys
for XOR proximity. Standing against this: the no-repetition rule, the
2/3 quorum of the nominal size, the tolerance check of independent
observers, and the consequence classes (irreversible = second,
disjoint jury). **PoW has been examined as an additional Sybil anchor
and rejected** (7 days of continuous phone grinding ≈ cent amounts of
rented GPU time; iOS cannot sustain continuous PoW, §31). Assessment
of the residual surface: external review as a subject (optional).

### 16.6 CSAM Special Procedure

The special procedure relies on a graduated response based on the number
of independent reporters — without a content-viewing jury. Temp-hide
and appeal windows (14+14 d) live as durable objects (§16.0):

| Stage | Trigger | Measure |
|---|---|---|
| **1** | first report | registered, nothing visible happens |
| **2** | reporter quorum "Temp-Hide" (table below) | channel **temporarily hidden from search** (14-day window). Admins are informed ("temporarily hidden due to multiple content reports" — without indicating the category); the admin can file an **appeal** (below). If the stage-3 quorum is not reached within the deadline, the channel is unhidden again |
| **3** | reporter quorum "permanent" (table below) | initially only **extended hiding** — no immediate deletion. A mandatory **14-day appeal window** opens; only after it elapses without a successful appeal is the tombstone placed, accompanied by the **`CsamReporterQuorumProof`** |

**`CsamReporterQuorumProof` (normative; Ed25519, §16.5).** The proof
lists the reporting registered pseudonyms together with their
signatures over the respective report cells; every node can thereby
verify that the stage-3 quorum was reached by distinct, qualified
reporters. **No tombstone is applied without this proof.** It lives as
a durable object attached to the channel's directory object.

**Basis of assessment (normative).** Public channels have no fan-out and
no subscriber list (§16.3); a subscriber count does not exist: a post is
**one** cell under a publicly derivable tag family, reading is passive
harvesting, and no one registers anywhere. Whoever reads is, by
construction, not countable; that is the gain of read anonymity and at
the same time its price. A quorum denominator must, however, be
determinable **identically and verifiably by every observer** — an
estimated or self-reported number would be worse than none at all in a
security formula. The quorum denominator is therefore the only
enumerable, proof-bound quantity of the object space, the registry
(§16.5):

| Stage | Reporter quorum |
|---|---|
| 2 — Temp-Hide (reversible) | `min(100, max(10, Registrierungen_Sprache × 0.01))` |
| 3 — permanent deletion (irreversible) | `min(200, max(20, Registrierungen_Sprache × 0.02))` |

The same measure applies to the **trigger threshold of the regular
categories** (§16.4): there too, the registry of the language is the
reference quantity. The language follows from the channel's directory
entry; the registration count is enumerable from the durable-object class
and substantiable via the class state.

**Honest consequence (declared):** the quorum measures the **language
community**, not the channel's audience. Large channels are thus
relatively easier to attack than small ones — channel size does not act
as a dampener.

**The other half of that consequence.** The same denominator that makes
large channels easier to attack also made legitimate deletion *harder*
without bound: unbounded, a language with a hundred million
registrations would have required two million distinct qualified
reporters to delete one channel permanently. The ceiling `min(200, …)`
closes that end — above 10,000 registrations the quorum stops growing.
The price is stated plainly: from there on an attacker's cost is **known
and fixed** at 200 aged pseudonyms, whatever the community size. That is
deliberate. The alternative — letting the quorum keep growing — buys
nothing against an attacker who is willing to pay, and takes permanent
deletion away from exactly the large communities that need it most.

**Procedural path.** CSAM is **excluded from the consequence classes of
§16.4**. Reason: the jury there sees the evidence-post references —
exactly what the special procedure excludes by construction: with CSAM,
even viewing is already a criminal offense; the content cannot be
presented to any jury. Stage 3 instead requires:

1. the reporter quorum from the table above,
2. the 14-day appeal window elapsing **without** a successful admin
   appeal,
3. **no** content-viewing jury.

**Admin appeal and content-blind plausibility jury (normative).** The
appeal is the counterweight of the special procedure; it gives
legitimate operators a defense against coordinated false reports. The
following applies:

- **Right of appeal and deadline:** the channel operator (owner/admin)
  is entitled to appeal from the stage-2 hiding onward — during the
  14-day Temp-Hide window as well as within the 14-day stage-3 appeal
  window. The appeal convenes a plausibility jury. The 14 days are the
  deadline for **filing**, not for deciding.
- **Suspensive effect (normative).** A timely filed appeal **stays the
  onset of stage 3** for as long as the plausibility jury is running.
  Stage 3 only takes effect once the appeal proceeding has concluded —
  through the verdict "plausible" or through the inconclusive expiry of
  the 30-day wall clock. Without this stay, the voting speed of the
  drawn jurors would decide finality: the proceeding may run for up to
  30 days, the appeal window measures 14, and every replacement round
  costs up to two more days — a timely appeal could thus run into a
  void, because the tombstone would take effect before the verdict. The
  hiding from stage 2 **remains in place during the stay**; the delay
  grants the reported content no visibility and therefore gives the
  operator no incentive to seek it out.
- **Content blindness (conclusive evidence):** this jury **never** sees
  the reported content — neither posts nor evidence-post references. It
  sees exclusively: channel name, description, posting frequency, and
  the reporters' text descriptions (of what they claim to have seen).
- **Selection and size:** identical to the standard procedure (§16.4)
  — selection point H, the `jurySize` XOR-nearest registration objects,
  size `min(11, max(5, Kandidaten × 0.01))` (see §16.4 for why the floor
  sits inside the formula), juror qualification and no-repetition as in
  the parameter table of §16.4.
- **Question and verdict:** the jury assesses whether the channel is
  thematically plausible in relation to the allegations. Two verdicts:
  "**plausible**" (the hiding remains in place) or "**fabricated**"
  (the channel is restored).
- **Quorum and procedure:** the voting mechanics of §16.4 —
  ring-signature vote, 2/3 of the nominal jury size, 2-day timeout,
  replacement rounds only at ≥ 5 open seats, 30-day wall clock. The
  quorum applies to the measure of the appeal proceeding, the verdict
  "fabricated"; if it is not reached, the verdict is "plausible".
- **Success:** an appeal is **successful** if the verdict is
  "fabricated"; it lifts the hiding. Only a successful appeal prevents
  the stage-3 tombstone.

If a second instance is wanted for finality, it must be convened as a
**second, disjoint plausibility jury** — explicitly content-blind,
never as a §16.4 jury.

**Abuse protection without person state.** Bond and rate limit are
expressed as **self-signed consumption objects** (type "self-statement
about one's own identity", compatible with the objects-not-persons
property): every CSAM report carries along an object "pseudonym P
submitted a CSAM report on day t"; the counter credits a report only if
no further such object exists for the same pseudonym within the last 7
days. Every CSAM report thus costs **7 days of a reporting lock in all
categories** — verifiable as a consumption object rather than asserted.
The reporter qualification is a registry age of ≥ 30 days for the
reporting pseudonym (§16.5) **plus** the reporter quorums from the
table above.

### 16.7 System Channels

Bug Log and Feature Requests are ordinary public objects without an
owner: structured reports as posts, crash-fingerprint dedup and vote
accumulation as durable objects (§16.0), moderation via the procedure
from §16.4. The following applies:

- **Crash reports** only after an opt-in popup with a preview of the
  exact publication; dedup via crash fingerprint with a +1 counter
  instead of a duplicate post. No free-text input in the Bug Log, only
  structured reports.
- **Contact issue reports** (failed contact exchange) with a **dual
  path**: file export is always available — a node whose first contact
  attempt fails may not have any network yet and cannot reach the Bug
  Log channel (chicken-and-egg problem); the post to the Bug Log is
  only an option if peers exist.
- **Manual Log Report** with a preview dialog (exact report content,
  privacy notice) and explicit consent before publication.
- **Feature Requests** with an automatically attached yes/no/don't-care
  poll (every post gets one; sorted by net votes, locally).
- **Limits:** a 25 MB storage limit per system channel; rate limits
  (crash/log reports 3 per hour, 10 per day; Feature Requests 3 per day,
  enforced on the receiver side).

The distribution of system-channel records runs via the anti-entropy of
the durable-object class (§16.0). RETRACT is an author tombstone object:
only the author can retract their own post (at any time, consistent with
the unbounded deletion model), the tombstone survives anti-entropy (no
resurrection by latecomers), and the fingerprint-dedup counter outlives
the retraction, so that a reappearing original does not increment the
+1 counter again.

### 16.8 Further Normative Provisions of the User Level

These provisions supplement §16.3–§16.6 and apply to the entire public
sphere.

- **Report rate limit per registered pseudonym.** The rate limit binds
  exclusively to the registered role pseudonym (§16.5), never to a user
  or device identity: 5 reports per pseudonym and day, and per category
  and epoch, exactly **one** report per pseudonym counts. Multiple
  reports from the same pseudonym are publicly recognizable and are
  deduplicated — every observer counts the same quantity. A rate limit
  at the identity level would accomplish nothing: fresh identities are
  free, only aged registrations are scarce.
- **Sorting signal instead of subscriber count.** The directory index
  maintains no subscriber count and no popularity sorting. The sorting
  signal of search is the **post frequency of the last 14 days** from the
  node's own relay holdings; it measures activity, not popularity, and
  is labeled as such in the UI. Public channels have no fan-out and no
  subscriber list, reading is passive harvesting, and no one registers
  anywhere; whoever reads is, by construction, not countable — that is
  the price of read anonymity.
- **Over-18 trait as self-declaration.** The juror and NSFW read gate "I
  am over 18" is a flag in the registration object (§16.5) and a
  **self-declaration**; it is not externally verifiable, and it is
  declared as a self-declaration. The filtering of NSFW-flagged directory
  entries occurs client-side (§16.3).
- **Contact only upon self-publication.** Contacting a channel member or
  a reporter is possible only if that person themself publishes a
  ContactSeed (for instance in the post profile). There is no system path
  that makes a person addressable from a public object — it would be a
  breach of §4.3.
- **Moderation hits objects, not persons.** All measures in this chapter
  act against objects (directory entry, channel, post). A network-wide
  state about another person is unconstructible; accordingly there is no
  sanction against persons, no strike record, and no ban on reporters or
  operators. Recreating a tombstoned channel under a new key is possible
  and is dampened solely by the halved report threshold and registration
  aging (§16.4, "limit of enforcement").

---

## 17. Calls (Plane D)

*(This chapter is organized into wire format (§17.1), signaling
(§17.2), address acquisition (§17.3), and admission (§17.4). Media
processing itself (audio, video, JitterBuffer, adaptive bitrate,
in-call collaboration) sits above the Plane D API and is summarized
in §17.5.)*

**Principle.** Plane D is the only place in the system where two
devices disclose their addresses to each other — consented, per
contact ("allow calls = disclose IP", revocable), for the duration of
the session. Everything asynchronous stays on the delivery layer. The
Plane D API is narrow and explicit; call code does not access transport
internals. The media, once connected, is real-time and IP-tolerant
("two talk again" is visible to an observer, who they are is not) —
a direct connection between the two devices once an address pair
works, by construction (§1.3). Reaching a device that may be in the
background, however, is an asynchronous problem and follows the same
delivery path used for messages (§7, §8), detailed for signaling in
§17.2.

### 17.1 D-Frame Format

Media does **not** run in delivery cells: quantizing a media frame
(orders of magnitude smaller than a cell) to cell granularity is
wasteful either way. Plane D has its own, minimal frame format:

- **AES-256-GCM under `call_key`** — live-media frames carry **no**
  ML-DSA signature and **no** zstd compression; the AEAD under
  `call_key` provides per-frame authenticity. Rationale: post-quantum
  authenticity is fixed once, at session setup (dually signed
  signaling, hybrid X25519 + ML-KEM-768 key exchange); a signature per
  frame would cost ~3,500 B wire and ~600 µs CPU on top, and frame
  payloads are already ciphertext, hence not compressible.
- **Uniform header, padding to fixed size classes.** On the wire, a
  D-frame is indistinguishable from random bytes; the size classes
  dampen bitrate fingerprinting.

  **Two classes.** The section named the
  principle without naming the classes; the numbers follow from the codec
  and are stated here so nothing has to be invented at build time.

  | Class | Carries | Derivation |
  |---|---|---|
  | **176 B** | one voice frame, 1:1 or group | The encoder runs in **constant bitrate** (`OPUS_SET_VBR = 0`), so at the configured 28 kbps with 20 ms frames = 50 frames/s a speech frame is **70 B, always** — measured across all five sample rates the codec accepts, exactly one frame size at every rate. D-overhead is **43 B** — cookie 8 + nonce 12 + AEAD tag 16 + inner header 7 (`kind ‖ seq ‖ len`). A group frame carries **33 B of its own** on top of the codec: the 16 B AEAD tag of the per-sender `send_key` (§17.5), a 12 B nonce, a 4 B end-to-end sequence number and a 1 B sender index. Worst case is therefore **70 + 33 = 103 B of payload** for a group frame and 70 B for a 1:1 frame, against the **133 B** this class carries. **The 0 % loss is a consequence of the cap, not a sample result** — left unconstrained the codec has no per-frame bound at all: measured maxima across the five rates were 88 / 92 / 94 / **119** / 98 B. It stays **one class for both**, so it reveals nothing about whether a call is a group call |

  *The encoder was measured before this class was relied upon, and the
  measurement set it. An earlier 128 B rested on "60–80 B" read as the
  codec's bound rather than as its mean range, and at that size the group
  path lost **100 %** of its frames: Opus 70 B plus the group's own 16 B
  AEAD tag is 86 B against 85 B of payload, one byte over before a single
  header field exists — which is why no header reduction could have closed
  it and the class itself had to grow. The sealer must still **fail
  loudly** on overflow rather than promote the frame to the next class,
  because a promotion is exactly the size difference these classes buy
  away.*
  | **176 B** | one **control frame** (§17.1.1) | control frames share the voice class **deliberately**: a separate size would let an observer outside the call count them, and control traffic peaks exactly when someone starts speaking or presenting |
  | **1200 B** | one video fragment, one media-stream fragment (§17.6) | video is fragmented anyway at 1187 B of payload, and §11 already fixes this class for stream frames (85.3 % efficiency) |

  **One class for everything was rejected, with the price computed:** at
  1200 B a voice call would put **480 kbps on the wire for a 28 kbps
  codec — a factor of 17.1**, about 430 MB per hour and one direction.
  Unusable on mobile.

  **The padding overrides DTX, and that is the point.** Under the
  constant-bitrate cap a frame in a speech pause no longer shrinks — it is
  70 B like any other, so the size leak is already closed at the codec and
  the padding closes the remainder. Before the cap, DTX let a pause frame
  fall to 2–3 B; unpadded that would have saved traffic — 3.3 kB/s instead
  of 8.8 at a typical 40 % speech share — and it leaks: **whoever sees the
  frame sizes sees when you speak.** That is exactly the traffic analysis these
  classes exist to dampen, so the padding is not optional and the saving
  is spent deliberately: **5.5 kB/s per direction, about 40 MB per hour of
  conversation across both directions.** A class that only sometimes
  applies is not a class.
- **No link handshake on Plane D.** The keys come from the call-key
  negotiation in signaling (§17.2) — the media path starts with **0
  additional round trips** as soon as an address pair works.
- **No routes, only address candidates (§17.3).** The media path is
  fixed with the first viable address pair; for the 50 frames per
  second, no resolution, routing, or address-prioritization chain needs
  to be traversed. RTT between participants is the one quantity that
  **is** measured — on the control plane (§17.1.1) — and it is the only
  input the group spanning tree weights by.

#### 17.1.1 Control frames

A fourth `kind` on Plane D carries what a group call needs to organize
itself: speech level, readiness, presentation role, layout size, spanning
tree updates, and RTT probes. It is **not** a media frame — it carries no
media and is never handed to a codec.

**Same class, same key, same padding.** A control frame is an AES-256-GCM
frame under `call_key` in the 176 B class, indistinguishable on the wire
from a voice frame. This is not a convenience. Who speaks when is
information the call participants **need** — the UI draws it as a frame
around the active speaker, and the relay selection in §17.7 depends on it —
but that is knowledge *inside* the call. An observer outside it must not
get the same signal for free, and a separate size class would hand it over:
control traffic peaks exactly when someone begins to speak or to present.

**Bundling is mandatory, not an optimization.** All pending messages of one
tick travel in one frame, at **1 Hz**. Sent individually, at 6.35 messages
per second per peer pair, the control plane would cost 438 kbps in a fully
meshed call of 50 — more than fifteen voice streams. Bundled at 1 Hz it
costs **69 kbps** (2.5 voice streams); a tick's payload is then 85.6 B of
the **133 B a 176 B class carries**, leaving 47 B of headroom.

**Why 1 Hz and not 2.** At the earlier 128 B class 1 Hz was arithmetically
impossible — 85.6 B of payload against 85 B of capacity — and 2 Hz was
forced. The larger class removed that constraint, and the rate then follows
the cheaper option: 1 Hz halves the control plane against 2 Hz (69 kbps
instead of 138 at 50 participants) for a bounded cost in responsiveness,
namely that a speaker change is seen up to one second late. That is the
same order as the speaker changes themselves, and the media tree is
deliberately **not** rebuilt on a speaker change anyway (§17.7) — only the
selection of forwarded streams follows it.

**The control plane is fully meshed to 25 participants and has no topology
of its own.** Every participant talks to every other directly. Three
reasons, and the saving is the weakest of them:

1. **A tree cannot repair itself over itself.** If the media topology were
   steered through the media topology, a broken branch would keep the
   repair messages from exactly the nodes that need them.
2. **It is what makes weighting measurable at all.** §17.3 has no routes,
   so `routeCostTo` has nothing to estimate and a spanning tree over it is
   unweighted. On a fully meshed control plane every node measures every
   other directly — no relay in between, no delivery latency distorting the
   value.
3. **No disagreement about state.** Who the loudest speaker is must look
   the same to everyone at the same time. Relayed through a tree, each
   level sees it later, and a layout switch flickers.

**Above 25 participants the mesh gives way to a star.**
From 26 on, one participant becomes the control root, every other talks
only to it, and the root **aggregates**. The threshold is not a preference;
three measurements turn at the same place:

| | mesh at 25 | mesh at 50 | star |
|---|---|---|---|
| control traffic per node | 34 kbps | 69 kbps | 1.4 kbps at a leaf, (N-1) x 1.4 kbps at the root |
| address pairs to establish | 300 | 1225 | N-1 |
| call setup at 2 s per punch, 20 in parallel | 30 s | 122 s | 2–5 s |

*At 1 Hz the control-traffic row carries less of the argument than it did
at 2 Hz, and it is stated rather than quietly left standing: 69 kbps at 50
is uncomfortable, not prohibitive. The threshold rests on the other two
rows — 1225 address pairs and a two-minute call setup — and on the forced
aggregation below.*

**Aggregation above the threshold is forced by the frame class, not
chosen.** The raw state — one level per participant — is 208 B at 25 and
408 B at 50, against the 133 B a 176 B class carries. The root therefore
sends a *filtered* state: the four loudest speakers, the presenting
participant, the layout version, a readiness bitmap and the tree version —
32 B at 25, 35 B at 50, 41 B at 100. That fits at every size, and it is why
the star is not merely cheaper above the threshold but **necessary**.

**What the star costs, stated plainly:** reason 2 above. Leaves no longer
measure each other, only the root, so the spanning tree above 25 is
weighted by root-relative RTT rather than by a full graph. That is a real
loss and it is accepted, because a full graph at 50 would be 1225
measurements — a quantity that was never going to be collected.

The root is chosen like any relay (§17.7): reachability first, then link
type, then power source, then measured upload. It is **not** automatically
the call initiator.

**What a control frame must never carry:** media payload, key material
beyond the session's own tree bookkeeping, or anything that would make it
worth relaying by a node that is not a call participant.

### 17.2 Signaling over the delivery layer

Signaling messages (`INVITE`, `RING_ACK`, `ANSWER`, `REJECT`,
`HANGUP`, `CANCEL_OTHERS`) are ordinary 1:1 cells under pairwise tags
— flowless, anonymous, indistinguishable from any other traffic on the
delivery layer.

- **Short "interactive" delivery TTL (120 s).** Signaling cells carry a
  short, 120-second TTL class instead of the default (§9). **The class
  is therefore visible on the wire** — a relay can tell a signaling
  cell from a message cell. That is an accepted cost, not an
  oversight: it buys **freshness** (an INVITE cannot ring days later)
  and keeps dead ring signals off the relays. There is **no PoW** on an
  INVITE — the delivery layer carries no message-level PoW at all; the
  INVITE costs one ordinary packet, nothing more. An INVITE
  is **placed once**; there is no retransmission — which is why its
  reaching the recipient in time is a delivery property, not a detail:
  the 120 s TTL must exceed the interval at which the recipient becomes
  reachable (§8). **Signaling therefore uses a smaller redundancy set
  than an ordinary message** (§9), sized so that its own delivery
  completes within the 120 s TTL rather than needing the several
  minutes an ordinary message's larger set would take. **This
  redundancy trade-off is deliberate:** a real-time signal is
  censorable by its nature, and the smaller set buys far less
  resilience than the larger one does for a message that has seven
  days — but it is not measurably worse in practice (§9). Without it, a
  call to a device in the background would not ring at all before the
  TTL expired.
- **Why signaling relies on the mailbox stage, not the direct stages.**
  The direct/relay stages of the delivery ladder (§7) only reach a
  device that is reachable *right now*; a device in the background is
  not. The mailbox stage (§8) is what reaches it regardless of
  foreground state, at a latency that depends on how often the device
  becomes reachable there: fast in the foreground, on the order of
  seconds in the background, and on a closed iOS app, possibly not
  within the 120 s TTL at all. This is the same "first contact has no
  cached direct path" situation as §15. The call, once connected, then
  uses the direct stages for the media itself (§17.1).
- **Caller state `reaching`.** After placing the INVITE, the caller
  shows "reaching …" — **no** ringtone. Ringtone and the 60-s answer
  timeout start only once the callee's `RING_ACK` cell has actually
  arrived ("it really is ringing on their end"). This means there is
  no fake ringing against a device that was never reached.
- **Ordering:** `callId` + sequence number; terminal types (`REJECT`,
  `HANGUP`) dominate any later out-of-order arrival; completed
  `callId`s are remembered for 24 h (late duplicates are no-ops).
- **Multi-device (§14):** an INVITE is **one** cell — all of the
  callee's devices see it via the shared delivery target used for
  multi-device (§14) and ring. `RING_ACK`
  carries the ringing device's **ephemeral X25519 binding marker**; the
  first `ANSWER` binds the session to one device — carrying that same
  marker — and `CANCEL_OTHERS` (TTL 120 s) names it to end the ringing of
  the others.

  **Why an ephemeral marker rather than a `deviceId`.** §14.1 holds
  the DeviceID to be "not an addressing means …
  a **subject**, not a **signpost**", and the delivery path carries
  no device level at all (§14.2), so a plain per-device field would be
  structurally unfillable there — a field that cannot be filled is a lie
  in the schema. The
  ephemeral marker delivers exactly what the clause needs — the caller
  counts ringing devices without learning *which* — and it is **one**
  marker across the whole call instead of three that can drift apart.

**Callability matrix (normative):**

| Recipient state | Incoming call |
|---|---|
| App in foreground (§8) | rings within **1–3 s** |
| Android background (foreground service) | rings within **seconds** |
| Desktop background | rings within **seconds** |
| iOS app closed | **no incoming calls** — reachability under §8 does not fall inside the 120-s TTL; documented platform limit (§31), not an error class |

Missed calls are nevertheless visible: the caller's `reaching`
cancellation can be followed up as a normal cell ("missed call") with a
standard TTL — delivery then follows the messaging model (offline is
not an error, §1.2).

### 17.3 Address Candidates and Punch Windows

- **"Observed address" instead of STUN:** the link handshake (§4.3)
  gets a closing field in which the sync partner mirrors back the
  sender address it observed. Every node thus learns its external
  address from the sync that is already running anyway — without a
  STUN server, without additional infrastructure.

  **The field goes in flight 2.** Flight 1 has no
  room for it: §11 puts its free budget at **36 B** (1124 B
  plaintext minus the 1088 B ML-KEM ciphertext), and
  that budget is already spent in full on caller authentication (§11). Flight 2
  is also the honest place for it — the mirror can only be written by
  the side that has already *seen* the sender's datagram, which is the
  responder. Since §11 fixes the handshake at two datagrams of 1200 B
  and one round trip, this is an addition to flight 2's format and not a
  third datagram; the byte layout is still to be written.
- **Candidates in signaling:** INVITE and ANSWER carry the address
  candidates of both sides — local addresses, the **mapped address** of an
  active port mapping (§25.9), and observed addresses, both families kept
  separate (a narrow ICE without TURN). *Including the mapped address
  matters concretely: §25.9 lists port mapping as the
  means for inbound calls, and without it here a callee behind NAT with an empty address book
  would offer private addresses only, and the call would fall back to the
  relay path of §17.6 even though the router had granted the forwarding.*
- **Punch window instead of a point in time:** after INVITE/ANSWER,
  both sides send for up to **30 s at 1 packet/s to all of the other
  side's candidates**. The first address pair on which valid AEAD
  responses arrive carries the session. A window needs neither
  synchronized clocks nor a third party.
- **Symmetric NAT:** port prediction is a candidate generator — it
  guesses the NAT's next port assignment within a window of ±10 ports
  around the most recently observed port. If no pair carries, this
  applies: **media-relay opt-in** via a dual-stack volunteer with
  mutual consent and a labeled metadata price — or, honestly, "no
  call".
- **Address families:** v4-only ↔ v6-only has no common pair — clear
  message "no common connection type", delivery-layer messaging
  unaffected; relay opt-in as above.
- **CGNAT/slirp without an observable external address:** no call is
  possible, messaging unaffected. Deliberately left open as a residual
  item.

**All three refusals above are call-specific.** For **media transfers**
these cases are carried by the relayed stream (§17.6), where both parties
connect outbound to a volunteer — media has no punch dependency at all.

### 17.4 Admission, DoS, and Path Migration

- **AEAD admission:** the D socket responds **exclusively** to packets
  with a valid AEAD under `call_key` plus a session cookie — statelessly
  verifiable, no response to unknown parties, so there is **no
  amplification surface** and no need for an address allowlist. Whoever
  does not have the `call_key` from signaling does not exist for the
  socket.
- **Path migration (QUIC-like, path-validated):** an authenticated
  migration packet from a new address (valid AEAD + cookie) starts a
  **path challenge** — 16 fresh random bytes to the new address — and only
  the authenticated response carrying exactly those bytes **swings the
  media path over, one round trip later**. A WLAN→LTE change survives the
  call without a delivery-layer round trip and without new signaling; the
  challenge is neither. The **first** address of a session is adopted
  without a challenge (RFC 9000 §8.1); validation governs the change of an
  **established** path. At most **3 challenges per address**, then silence
  — no timer, no polling. The call keeps running on the old path
  meanwhile.

  *Rationale: why a sequence guard alone is not enough.* The sequence guard (`highestSeqSeen`, RFC 9000 §9.3)
  stops a **replayed** migration packet, because the original has already
  arrived and raised the number. It does **not** stop an adversary who can
  suppress the original and deliver its own copy first: that frame is then
  the first with this number and redirects the media stream, and it needs
  no `call_key` to do so. The guard stays as stage one; validation is
  stage two. **Price:** 128 B challenge + 128 B
  response = **256 B per real path change**, **0 B at rest**, and half a
  round trip of delay before the new path carries. Both frames ride the
  voice size class — §17.1 freezes the size classes, not the number of
  kinds (as `DFrameKind.punch` already shows).
- **Loss detection:** 10 s without valid media frames end the session
  (UI: "connection lost"), independent of signaling.

### 17.5 Media Processing above the Plane D API

Everything that follows sits **above** the Plane D API.

**Audio — native OS voice session per platform.** Cleona runs **no
audio DSP of its own**. Echo cancellation (AEC), noise suppression (NS),
and automatic gain control (AGC) come from the operating system's voice
chain — the same chain a phone call on the device uses. Cleona accepts
already-processed PCM, encrypts it, sends it, and hands received PCM
back to the same OS session. The only boundary is a C ABI
(`native/cleona_voice/cleona_voice.h`) with five platform-native
implementations: Android via `AudioRecord`/`AudioTrack` with the
`VOICE_COMMUNICATION` source and effects attached to the session ID,
iOS/macOS via the `VoiceProcessingIO` audio unit with the
`AVAudioSession` mode `voiceChat`, Windows via WASAPI duplex with
`AudioCategory_Communications`, Linux via PipeWire duplex with the
echo-cancel module, or failing that, a directly linked WebRTC APM.
Frame contract: 16-bit PCM, mono, **sample rate as reported by the
platform** (no constant), 20 ms frames, fixed frame size guaranteed by
the platform layer, playback tick from the output device (never from a
Dart timer), **duplex mandatory** — without a shared session for
capture and playback there is no echo cancellation. Codec is Opus. A
normative part of the ABI is a **verification report** per session
(negotiated rate, frame size, per effect
`unavailable | available_off | enabled` along with the chain's
provenance, active input/output route, backend, duplex, under-/overrun
counters); `not_determinable` is an admissible value and is reported as
such, never guessed as `enabled`.

**Video — platform hardware codecs.** The platform captures, the
platform's hardware codec encodes and decodes, Cleona handles only the
encrypted bitstream; **no pixel processing in Dart**. On the wire,
**H.264 Constrained Baseline** is the mandatory interop tier — the only
codec with hardware encode *and* decode on all five platforms; HEVC,
AV1, and VP9 are negotiated if both sides have hardware for them.
`CALL_MEDIA_STATE` carries the flag "I am sending video" and, when
`false`, **a reason**, so the recipient can distinguish "video off"
from "the network can't carry it" instead of seeing a frozen picture.
As long as the capture layer still hangs off `dart:ui`, desktop video
calls remain audio-only.

**JitterBuffer and adaptive bitrate.** Received audio and video frames
pass through a JitterBuffer before playback, which absorbs reordering
and short loss bursts. The target bitrate follows the measured
available bandwidth and is tracked throughout the call; the encoder
scales down through the presets, and only once no preset fits anymore
does the video stream end — with a reason in `CALL_MEDIA_STATE`, not
silently.

**In-call encryption semantics.** As in §17.1: AES-256-GCM under the
`call_key`, no ML-DSA signature per frame, no zstd attempt. In the 1:1
case, the `call_key` is a two-party secret and thereby authenticates the
other side. For groups, **a separate `send_key` per sender** is needed,
because a shared group key cannot provide sender authenticity (any
holder could forge as any other); the group-call topology is open (below).

**In-call collaboration (planned).** During a call: a shared multi-page
whiteboard, file and clipboard exchange, call chat, screen sharing via
the platform capture APIs (Linux PipeWire/XDG portal, Windows
`Windows.Graphics.Capture`, Android `MediaProjection`, iOS ReplayKit)
with bandwidth-dependent quality tiers; remote control remains planned.
Everything is **call-scoped** (content is discarded on hangup unless
explicitly saved), runs under the same call key as audio and video,
and has lower priority than audio.

**Still open:** FREE_BUSY signaling. The group-call topology is **settled
in §17.7** (K31-3); the objection that an overlay tree
presupposes mutual addressability is answered there and by the pairwise
hop key of the paragraph above.

### 17.6 The relayed media stream — Plane D for file transfer

For media (§9.4), the volunteer relay of §17.3 is not the fallback but
the **default** (E-84). The §17 principle survives
verbatim: the two devices still disclose no address to each other —
**both connect outbound to the volunteer**, which is why the three cases
§17.3 must refuse for calls (symmetric NAT with no viable pair,
v4-only ↔ v6-only, CGNAT with no observable external address) all carry
media. There is no punch window and no port prediction on this path; two
outbound connects replace them.

**Finding the volunteer.** No directory, no fixed point, no designated
role: candidates are inbound-reachable always-on nodes that have opted in
("media relay volunteer"), drawn from two rings — the sender's current
sync partners (the ask rides the live link and adds no metadata; a sync
partner sees the sender's address anyway, RL-1), then entry-cascade
nodes, whose addresses are public by construction (RL-13). Dual-stack
candidates are preferred; the ask names the transfer size and a cookie,
no identity. Admission at the volunteer is **capped, not negotiated**
(D-1): a volunteer accepts transfers up to the protocol-wide size cap
`C` (§9.4) without any dialog; transfers above `C` never ask a
volunteer and take the bulk lane, both parties online or not. The
volunteer's price is thereby bounded and declared in RL-7 — no unbounded
third-party load, and no consent dialog on an unattended machine.

**Session.** The volunteer hands out two session cookies; the sender
places a `STREAM_OFFER` (volunteer address, cookie, transfer parameters)
as an ordinary delivery; both parties connect outbound; the volunteer
pairs the cookies and forwards frames 1:1. Following §17.4, its socket
answers exclusively to valid AEAD-plus-cookie packets — no amplification
surface — and it holds no key: frames are sealed under the transfer key
(§4.3) and are random bytes to the volunteer. Loss of the volunteer (10 s
without valid frames, the §17.4 rule) triggers one retry with the next
candidate, then the transfer finishes on the bulk lane; blocks are
lane-neutral, so received progress is never lost.

**Frames.** One Reed-Solomon fragment of §9.4 per D-frame, padded to a
**1200 B size class** — byte-uniform with the cell size. No ML-DSA per
frame, no zstd (§17.1 rationale). A stripe decodes from any 7 of its 11
fragments. Loss repair follows §11.3: after the last frame and 300 ms
without a new one, the recipient sends one request listing the missing
fragments of every stripe it cannot decode, for at most 3 rounds;
stripes still undecodable after the third round take the bulk lane.
There is no per-frame acknowledgement and no special fragment. The rate
is adaptive (§17.5 pattern). This stream carries stored media — files,
photos, recorded voice and video — whose value is the complete object.
Live call media (§17.1–§17.5) is never re-requested: a live frame is
worthless once its playback moment has passed, and the JitterBuffer
absorbs short loss instead.

**Cascade and windows** (normative defaults, to be measured): announce →
wait for the recipient's request (60 s when the announce reached the
recipient directly, rungs 1–3 of the delivery ladder / 20 min when it
was delivered via the mailbox, rung 4) → ask up to
three candidates (10 s) → `STREAM_OFFER`, connect window 30 s → stream.
Any failure at any step, including mid-stream after the retry, falls to
the bulk lane for the remainder. A failed stream attempt costs less than
10 KB and about a minute; no payload byte is sent before the session
stands. **The stream is pairwise (1:1) only:** a group transfer would
multiply the volunteer's forwarding by the member count, so group media
always take the bulk lane (encode once, place once, §9.4).

### 17.7 Group call topology

A group call carries three different things over three different shapes.
Treating them as one is what makes group calls either expensive or fragile.

| Plane | Shape | Why |
|---|---|---|
| **Control** (§17.1.1) | mesh to 25, star above | tiny payload, must survive a broken media tree, must not disagree about state |
| **Voice** | flat crystal, star in the small case | bandwidth is not the constraint here; latency is |
| **Video** | deeper crystal, layout-driven | bandwidth constrains hard; latency matters less |

**The crystal.** Media is relayed along a spanning tree whose fan-out is
**per node, not global**:

```
f_i = floor( usable_upload_i / (K x bitrate_per_stream) )
```

where `K` is the number of streams forwarded concurrently (the loudest
speakers, typically 3–4). A node that can carry much gets many children; a
node that can carry little becomes a leaf. **Star and uniform tree are both
special cases** of this — a star is the crystal whose root can carry
everyone, a uniform tree is the crystal on uniform links. There is no
separate topology to select.

Why this matters in numbers: with a uniform fan-out of 3 the per-node load
is **independent of group size** (336 kbps of voice at 8 participants and
at 50 alike), while a single relay carrying everyone needs 5.5 Mbps of
upload at 50 — and 98 Mbps if it forwards video. The price of the tree is
depth: roughly 15–25 ms per hop, so 60–100 ms at 50 participants. **The
crystal buys bandwidth with latency; the star does the reverse.** Which
trade is right differs between voice and video, which is why they do not
share a tree.

**Ranking for root and relay selection**, in this order: reachable at all →
link type (wired/WLAN before cellular) → power source (mains before
battery) → measured usable upload → RTT as a tie-break. **Throughput alone
is the wrong criterion**: a cellular participant on 100 Mbps pays for data
and drains a battery, and a well-connected node behind symmetric NAT is
useless as a relay however fast its link.

**The tree follows the role only where the role holds still.**

| Event | Frequency | Rebuild? |
|---|---|---|
| speaker change | several times a minute | **no** — change which streams are forwarded, leave the tree standing |
| screen share starts, ends, or moves | minutes apart | **yes** — the sharer carries the largest sustained load and belongs at or near the root |

**Video rate follows display size, not participant count.** A sender emits
the resolution at which it is actually shown. In a 16-tile gallery on a
1080p display each tile is 480x270, so 200 kbps rather than 500; while
someone presents, the presenter gets the full rate and everyone else
becomes a 160x90 thumbnail at roughly 60 kbps.

The consequence answers the scaling question: **the total demand of a video
conference is bounded by display area, not by participant count.** A 1080p
screen shows two megapixels however many tiles it is divided into —
measured, the total stays near 3 Mbps from 9 participants to 25, and the
presentation layout lands in the same range.

**Simulcast, not feedback.** A sender emits several rungs of the ladder at
once and the relay picks per receiver. It costs the sender about 1.5x its
highest rung and needs **no** back-channel, so a layout change takes effect
immediately; the relay only selects and never transcodes. The alternative —
receivers requesting a rung — saves upload but needs a round trip, and a
sender facing mixed layouts must emit the highest rung anyone asked for
anyway.

**Ceilings are per topology, not global.** A single figure would either
cripple the tree or promise what a mesh cannot keep: 6 for full mesh, 30
for the crystal, and the crystal ceiling holds only while a media relay
path actually carries. Where it does not, the mesh ceiling applies.

**Who speaks when is knowledge inside the call, and it is needed there.**
The relay reads a speech-level field to make its selection, and the UI
draws the same signal as a frame around the active speaker. Both are the
function, not a leak: in a group call everyone hears everyone anyway, and
every relay in the crystal **is** a participant. What must not happen is
that an observer *outside* the call gets the same signal — which is why
control frames share the voice size class (§17.1.1) instead of having one
of their own.

**Size limits of a group call.** Voice is offered up to the crystal
ceiling of 30 participants. Video is offered up to a participant count
set by measurement (Appendix C); until that count is set, video is
offered up to the mesh ceiling of 6. Voice and video carry separate
limits for the same reason they do not share a tree.

---

## 18. Calendar & Polls

*(The subject-matter logic of calendar and polls — data model,
recurrence and visibility rules, external sync, poll types, ring
signature — is transport-independent; its key points are summarized in
this chapter.)*

### 18.0 Guide through this chapter

The data model and the internal calendar logic are covered in §18.1,
delivery of the twelve protocol messages (six calendar, six poll) as
ordinary cells in §18.1.2 and §18.3.2, external sync with third-party
infrastructure in §18.2, the five poll types together with their
permission and tallying rules in §18.3, and anonymous voting in §18.4.
Free/Busy is the only calendar round trip that is open, and is worked
out in §18.1.5.

Purely local components with no delivery-layer relevance that this
chapter does not develop further:

- the RFC 5545 RRULE expansion
  (`lib/core/calendar/recurrence_engine.dart`), capped at 1,000
  occurrences or 10 years;
- iCal import and export (`lib/core/calendar/ical_engine.dart`), the
  five views, and the PDF print;
- the ReminderService (`lib/core/calendar/reminder_service.dart`,
  §18.1.6), daemon-local;
- the multi-identity merge together with cross-identity privacy — all
  identities of the same master seed appear in one calendar view, and
  Free/Busy responses contain busy blocks from all identities without
  disclosing which one caused them (§18.1.5).

---

### 18.1 Calendar (internal)

#### 18.1.1 Refining the privacy commitment

Calendar data is private, but not location-bound: shared shares do sit
on foreign relays — as sealed cells on the delivery layer, opaque to
every relay (§5, §16.1). Normative:

> Calendar data resides **locally and authoritatively** in the encrypted
> profile (§21). Invitations, RSVPs, changes, and cancellations
> additionally reside as sealed cells on the delivery layer until their
> TTL clears them (14 days default). A relay sees tag, TTL, and
> ciphertext — no event, no participant, no time. There is no PoW on a
> calendar cell; it costs one ordinary packet, nothing more.

#### 18.1.2 The six calendar messages as cells

| MessageType | Transport |
|---|---|
| `CALENDAR_INVITE` | **Contact event:** one cell delivered under `tag(K_AB)` (§9). **Group event:** N pairwise legs (§16.2) — one ordinary 1:1 cell per member |
| `CALENDAR_RSVP` | likewise N pairwise legs |
| `CALENDAR_UPDATE` | likewise |
| `CALENDAR_DELETE` | likewise |
| `FREE_BUSY_REQUEST` | see §18.1.5 — **open** |
| `FREE_BUSY_RESPONSE` | see §18.1.5 — **open** |

**Payloads.** `CalendarInvite` carries `eventId`, title, description,
location, start/end time, `allDay`, IANA time zone, optional RFC 5545
RRULE, `hasCall`, either `groupId` (group event) or `attendeeNodeIds`
(contact event) — the two modes are mutually exclusive, the UI enforces
this —, creator (`createdBy` plus display name), and an optional
`rsvpDeadline`. `CalendarRsvp` carries `eventId`, the answer (ACCEPTED
/ DECLINED / TENTATIVE / PROPOSE_NEW_TIME, the last with a proposed time
window), and an optional comment. The local `CalendarEvent` adds
category (APPOINTMENT / TASK / BIRTHDAY / REMINDER / MEETING), reminder
offsets, the Free/Busy visibility together with per-contact overrides
(§18.1.5), as well as `createdAt`/`updatedAt`.

All four carrying types are thereby **ordinary cells with no special
path**: there is only "place a cell onto the delivery layer" (§9).

**Cost.** One leg costs ~590 B. A group event in a group of 20
therefore costs ~11.8 KB per invite wave.

**Delivery tracking.** Separate per member: a group event reaches
visible `delivered` status only once every leg has received a
delivery receipt (§9) and no leg is withholding the display — the
disclosure of delivery status is a one-sided, local decision of the
recipient per chat and must not show through in the aggregate. Details:
§16.2.

**Recipient resolution.** `groupId` first (all group members excluding
self), otherwise `attendeeNodeIds`. Role logic: the creator may edit
and delete, the invitee may only RSVP. `K_AB` is deterministically
derivable from the roster pubkeys for every pair of members (§16.2) —
so a group member can be invited even if they are not a contact of the
creator.

#### 18.1.3 Ordering rule for UPDATE / DELETE (normative)

**Problem.** There is no guaranteed transport order (§9). Two cells
from the same sender can become visible in any order.

**Rule (normative):**

1. Every calendar cell carries `eventId` and `updatedAt` (both already
   exist in the data model, §18.1.2).
2. An incoming `CALENDAR_UPDATE` is **discarded** if its `updatedAt` is
   not greater than the locally stored state of the same `eventId` —
   last-write-wins on `updatedAt`, the same rule that external sync
   (§18.2) already uses for CalDAV and Google, and that carries in
   production there.
3. `CALENDAR_DELETE` **dominates regardless of timestamp**. An update
   received after the delete must not resurrect the event. The local
   delete marker (`eventId` plus delete time) is retained at least until
   the maximum delivery TTL (31 days) plus its retention margin has
   expired — after that, no cell that would need it can still arrive.
4. A `CALENDAR_UPDATE` or `CALENDAR_RSVP` for an **unknown** `eventId`
   is buffered, not discarded — the same pattern used for buffering chat
   configuration changes that arrive before the corresponding group
   invitation. When the invite arrives later, the buffered changes are
   applied. Buffer limit: the same TTL bound.

**Rationale for point 3.** A timestamp comparison is not enough here,
because cancellation and change do not commute semantically: a
participant who still has a deleted meeting in their calendar shows up
for an event that does not exist. The reverse error (the cancellation
wins even though the creator changed something afterward) only costs
the creator having to send a new invitation.

#### 18.1.4 RSVP waves

Twenty invitees answering one invite produce 20 × 19 pairwise legs —
RSVP distribution is quadratic in group size, because every RSVP goes to
**all** members so that everyone can see who has accepted. With 20
members that is ~380 cells at ~590 B ≈ 224 KB.

That is not a bug, but it is expensive. Three observations are recorded
here as application rules:

1. **RSVP is a standard-TTL cell** (14 d), not a 31-day management cell.
   It costs one ordinary packet, no PoW — the price is that of
   an ordinary message.
2. **RSVP batching.** Several RSVPs from the same sender for different
   events may be bundled into **one** cell — the same amortization
   pattern as the batched delivery receipt (§9). This is a pure
   application optimization with no protocol change.
3. **Large groups.** For groups beyond the threshold of §16.2.1,
   RSVP visibility to everyone is no longer appropriate; there the
   channel pattern applies (reply only to the creator, aggregated state
   as a post), analogous to §18.3.3. The threshold is the same as in
   §16.2, so that two thresholds do not need to be maintained.

#### 18.1.5 Free/Busy — the open point

§17 carries FREE_BUSY forward as an unresolved remainder. This section
works out the finding instead of passing it along.

**First state the diagnosis.** The finding is not "no channel", and the
distinction matters:

- Free/Busy is explicitly limited to **contacts**: whoever is not a
  contact cannot even ask — the KEX Gate silently drops messages from
  unknown senders.
- Between contacts, `K_AB` exists (§4.3). The tag can be formed, the cell
  can be placed, the recipient receives it. **The channel exists.**
- What is structurally missing is something else: the addressability of
  **non**-contacts — that affects channel votes (§18.3.3) and
  moderation reports (§16), not Free/Busy.

**The real finding** is therefore **"no round trip"**. The feature
requires an interactive flow: Alice opens the scheduling assistant, her
node queries each of the N invitees for the desired time window (e.g.,
"next 7 days"), each counterpart automatically answers with its
filtered busy blocks, and Alice sees a merged availability grid in the
style of the Outlook scheduling assistant, from which she picks a slot
on which everyone is free. Four points fail to carry this:

1. **Latency is the maximum over N, not the average.** One round trip
   costs two delivery latencies. In the foreground that is 1–3 s per
   direction when delivered directly (§7); in the background, up to ~5 min
   per direction when delivered via the mailbox stage (§8). A single invitee with a closed app turns
   that into ten minutes; on iOS with a closed app, the timing is not
   even predictable (§31). The grid is therefore never "finished", always
   "partially there".
2. **An offline invitee can answer up to 14 days later.** The
   `FreeBusyRequest` carries a `requestId` to correlate the response,
   but no expiry semantics. A response can arrive when the scheduling
   session has long since ended and the event already created.
3. **Egress-cost amplification.** The requester places **one** small
   cell and thereby triggers **N** response cells on N foreign devices.
   There is no PoW on this path; the cost is N egress cover-slots. The
   rate limit (at most one request every 20 s per contact) applies
   **only once the cell has been received and unsealed** — that is the
   only point at which the recipient knows the sender. The cost of
   receiving it accrues regardless of the rate limit, but the egress
   cost of the response is reliably capped by it.
4. **Egress quota.** A relay's per-recipient quota (§9, §16.4) governs
   how many cells it holds for a given destination. Whether automatic
   response cells are paid from it, and what happens on exhaustion, is
   not regulated.

**What the feature guarantees beyond that.** The auto-responder — the
response is generated automatically by the requested party's daemon
from the local calendar, without user interaction, even with the GUI
closed — is workable: the daemon sends and receives regardless. The
cross-identity merge — all identities of the same master seed contribute
their busy blocks into the one response, without the requester being
able to tell which identity caused a given block — is purely local. The
three-tier visibility (FULL: title, time, and location; TIME_ONLY: only
"busy from–to"; HIDDEN: the event is simply left out), together with
per-contact overrides, is likewise purely local filtering.

**OPEN (CAL-3).** The state model needs to be decided. Three options,
with cost:

| Option | Construction | Cost |
|---|---|---|
| **A — Asynchronous grid** | The request carries an `expiresAt` (proposal: 24 h, well under the 14-day TTL). The UI shows a **partial grid** with an explicit count ("3 of 8 have answered") instead of blocking. Responses after `expiresAt` are discarded. A new request is a new `requestId` | The feature is preserved, but loses the assurance of a "complete grid". The planner decides on an incomplete basis — which is what they already do today, just without knowing it |
| **B — Push instead of pull** | No request. Every user periodically (e.g., daily) places a filtered Free/Busy window as a cell to the contacts they want to show it to | No round trip, no egress amplification, an immediately available grid. Cost: traffic even without demand, and a stockpile of data — the contact learns about bookings they never asked about. This must be opt-in per contact |
| **C — Replace with date poll** | Free/Busy is not offered; the use case "find a shared time" is covered entirely by `DATE_POLL` (§18.3), which needs no round trip because every participant answers on their own | The most honest variant and the smallest amount of code. Cost: the planner only sees the offered slots, not actual bookings; there is then no Outlook-style assistant |

Plane D (§17) is **explicitly rejected** for Free/Busy: a calendar ping
is not a reason to disclose the IP address via consent (§17). The
metadata cost is out of proportion.

**OPEN (CAL-4).** Independent of the CAL-3 decision, it must be decided
from which egress quota a relay's auto-response cells are paid (§9) and
whether the response may carry a shortened TTL class to lower the
retention/cover cost. A response older than the scheduling process has
no value — the 120-s interactive class from §17.2 is too short, a
24-hour class does not exist. If one is introduced, it is a change to
the TTL ladder and belongs in the delivery chapter (§9), not here.

#### 18.1.6 ReminderService

The ReminderService runs in the daemon, fires system notification,
sound, and vibration — even with the GUI closed —, supports multiple
reminder offsets per event, recurring events, and snooze, and has no
network dependency.

**Explicitly noted** (because it would otherwise read as a gap): the
reminder itself stays latency-free. Only *shared state changes* ("event
moved", "event canceled") carry delivery latency. The case "the reminder
fires for an event whose cancellation is still in transit on the
delivery layer" is harmless — the reminder comes too often, never too
rarely — and needs no rule.

#### 18.1.7 Chat card and the "Call" button

The interactive event card in the group chat offers: RSVP buttons
directly on the card, in-place update via the same `eventId`,
strikethrough on cancellation, a reminder message 15 minutes ahead,
RSVP status changes as small system messages.

**The "Call" button at event start is bound to the full-mesh ceiling.**
As designed: with `hasCall: true`, the button appears at the start time,
a click starts a group call with everyone who accepted. The topology
itself is no longer the obstacle — §17.7 settles it (K31-3), and §17.5 gives each hop a pairwise `call_key`, so up to
the full-mesh ceiling every pair holds real material. What is still
missing above that ceiling is the relay path of the crystal.

Normative: the event card offers a group-call start **only up to the
full-mesh ceiling of §17.7**; above it, no start. A 1:1 event may show
the button unconditionally. The rule follows the core principle (§1.2:
no state asserts delivery without substantiating it) analogously at the
UI level: a button that promises a call the system cannot establish is
the same error class — and the converse holds too, so once a size is
carried, withholding the button is the same error mirrored.

#### 18.1.8 Storage and multi-device

Calendar events reside per identity in the encrypted profile
(`lib/core/calendar/calendar_manager.dart`, persistence
`calendar_events.json.enc`) — details in §21.

Multi-device: calendar changes between the devices of **one** user run
as twin sync (§14.7) and therefore over the same pairwise legs as
everything else. There is no dedicated calendar sync path, and none is
introduced.

---

### 18.2 External sync — outside Cleona's transport, with one caveat

CalDAV client (RFC 4791), Google Calendar API v3 (OAuth2 loopback +
PKCE), EWS, the local CalDAV server on `127.0.0.1:19324`, the Android
`CalendarContract` bridge, and the local ICS file bridge all talk to
external or device-local infrastructure and never touch Cleona's
transport at any point (`lib/core/calendar/sync/`, 10 files). External
sync comprises:

- the **conflict model**: last-write-wins on `updatedAt`, every LWW
  decision in a bounded conflict log with a restore action, opt-in
  `askOnConflict` with a side-by-side decision dialog;
- the **adaptive polling cadence** (3 min foreground / 15 min
  background);
- the **six security fixes** from the post-ship review of these code
  paths — the app's only place that contacts non-P2P infrastructure:
  constant-time token comparison on the local CalDAV server; refusal of
  redirects to foreign scheme/host/port combinations in the CalDAV
  client (otherwise the Basic-Auth header would travel to the
  attacker); a 5 MB cap on request bodies on the local server; symlink
  refusal on export and a 10 MB cap on import in the ICS file bridge; a
  plaintext `http://` warning in the CalDAV configuration dialog
  (except for loopback hosts); Host-header check on the local server
  against DNS rebinding (only `127.0.0.1`/`localhost`/`::1`, otherwise
  `421 Misdirected Request`);
- the **two deliberate non-implementations**: no FCM-style real-time
  push (a pure P2P client has neither a publicly reachable HTTPS webhook
  for the Google Watch API nor a backend server that could own an FCM
  API key — adaptive polling is the documented substitute) and no
  two-way Android sync (the `CalendarContract` mirroring stays
  push-only: Android-side edits would silently discard group, RSVP, and
  identity metadata and would turn any app with `WRITE_CALENDAR` into
  the effective editor of the end-to-end encrypted calendar).

Two clarifications are needed:

**(1) The local CalDAV server is an inbound listener.** The delivery
layer is outbound-initiated (a node sends and receives; it does not
listen). The CalDAV server binds on loopback, its traffic never leaves
the kernel, and it is not a delivery-layer participant. The apparent
contradiction is explicitly delineated here so that it is not later read
as a violation.

**(2) External sync breaks the cover uniformity from §5 — as a user
decision.** §5 holds that an ISP sees Poisson-timed cover packets of one
size (§5.2) beside the real traffic. For every user with active external sync,
that is untrue: the same host generates, every 3 or 15 minutes, clearly
identifiable TLS traffic to `www.googleapis.com` or to the configured
CalDAV host, with a characteristic cadence. The same applies to Media
Auto-Archive traffic (§21).

Normative: external sync is **opt-in per identity**, and the setting
names the consequence — analogous to the rule for the High-Secure
setting (§12): "Your device then regularly talks to an external server. That
is visible from the outside and distinguishable from the rest of the
traffic." A silent breach of the §5 commitment would be the worst
variant.

*Editorial note:* §5 itself does not yet carry this caveat. The cover
section needs a footnote "applies to delivery-layer traffic; opt-in
services (external calendar sync §18.2, media archive §21) generate
additional, distinguishable traffic" — otherwise the section is false as
an assurance. Changing §5 is not part of this chapter.

---

### 18.3 Polls

#### 18.3.1 Poll subject-matter logic

The five poll types (SINGLE_CHOICE, MULTIPLE_CHOICE, DATE_POLL in
Doodle style with yes/no/maybe per time window, SCALE, FREE_TEXT),
`PollOption`, `PollSettings` (anonymous yes/no, deadline,
`allowVoteChange`, `showResultsBeforeClose`, `maxChoices`, scale bounds,
`onlyMembersCanVote`), duplicate detection via `(pollId, voterId)` with
`votedAt` as tiebreaker, the permission matrix (creation: every member
in groups, only owner/admin in channels; closing and deletion: creator,
owner, or admin; seeing results: everyone, provided
`showResultsBeforeClose`), the chat representation as an interactive
card, and the date-poll→calendar bridge `convertDatePollToEvent` (the
winning slot of a closed date poll becomes a `CalendarEvent`, and
`CALENDAR_INVITE` goes out automatically to all participants) are pure
application semantics (`lib/core/polls/poll_manager.dart`).

Duplicate detection is explicitly **out-of-order-safe**: it decides by
`votedAt`, not by arrival order — see §18.1.3.

#### 18.3.2 Polls in groups — pairwise legs

Votes are distributed to all members via pairwise fanout, so that
every node tallies for itself and all converge: `POLL_CREATE`,
`POLL_VOTE`, and `POLL_UPDATE` run as N ordinary pairwise legs (§16.2),
~590 B each.

**There is no central tallier.** Every node receives all vote cells and
counts locally; that is why the "no trustworthy tallier exists"
principle (§16.1, public sphere) never even becomes a problem for
groups.

#### 18.3.3 Polls in channels — governed by §16.3

§16.3 governs the subscriber→publisher path:

> **Channel polls:** votes as cells under the poll tag family, sealed
> against the publisher pubkey (only the creator reads votes), tally
> anonymity still via ring signature; `POLL_SNAPSHOT` as a channel
> post. The creator-only path costs O(N) instead of O(N²).

From this follows, for this chapter:

1. The poll tag family is **publicly derivable** (from `pollId` or
   `channelId`), and therefore belongs to the public sphere (§16.1) and
   is read the same way as any other public tag family there (§16.1,
   §16.3) — the explicit exception to the single-use-tag invariant.
2. The vote is **sealed against the publisher pubkey**. No other
   subscriber can read it.
3. `POLL_SNAPSHOT` is an ordinary channel post under `tag_post`
   (§16.3) — **one** cell for all subscribers.

**Reason for the O(N) advantage.** A snapshot costs one cell either way;
the O(N) advantage of the creator-only path follows from subscribers
having no channel among themselves.

**Decided.** A publicly derivable tag can be written by anyone; that is
the eviction surface, and §16.4 already solves it for the moderation
tag families. **The poll tag families (channel polls and the
`tag_vote` family from §18.4.2) attach to exactly that same protection
(§16.4)** — it is the same object class of "context tags derivable
publicly or within a group", and a channel vote is therefore just as
protected against flooding as a report.

**OPEN (POLL-4) — `onlyMembersCanVote` has no denominator.**
`PollSettings.onlyMembersCanVote` distinguishes in channels between
members and mere subscribers (only members may vote). Public channels have
**no subscriber list**: §16.8 explicitly holds that they have
no membership structure, that there is no `subscriberCount`, and that
no one knows who is reading. The publisher therefore cannot enforce the
setting. Two options: (a) the field is removed, anyone who can read the
channel may vote; (b) the field stays and means "only registered role
pseudonyms with a registration age ≥ 7 days" (§16.5) — checkable, but it
forces voters into a public registration, which §16.3 just ruled out
for the mere act of subscribing. Recommendation: (a), with an honest
removal in the settings UI.

#### 18.3.4 Deadline, TTL, and convergence (normative)

`PollSettings.deadline` closes a poll by wall clock;
`PollAction.CLOSE` closes it manually. Cells trickle in until the
delivery TTL, while every node closes locally by its own clock.
Diverging tallies between nodes are possible.

**Rule (normative):**

1. A node counts every received vote whose `votedAt` lies **before**
   the deadline — regardless of when it was received. What decides is
   not the receive time, but the voting time. This makes all nodes
   converge as soon as they have received the same set of cells (§9).
2. A poll's deadline must not exceed the **default TTL of 14 days**. A
   poll with a 30-day term cannot be represented, because the first
   week's votes will already have expired from the delivery layer long
   before a long-absent participant could receive them. The UI limits
   the term selection accordingly.
3. A tally before the TTL expires is **provisional**. The UI labels it
   as such, rather than asserting a finality that the latency band
   cannot support — the same rule as the durable-object class
   ("verification state unknown" instead of "no badge", §16.0).

#### 18.3.5 Latecomers and `POLL_SNAPSHOT`

Cells sit on the delivery layer until the TTL; a latecomer simply
receives them along the way (§9). A rebroadcast of the tally to late joiners
is only needed if the poll is older than the TTL. `POLL_SNAPSHOT` is the
standard path for channels (§18.3.3), the exception for groups.

#### 18.3.6 Storage

Polls and votes reside in the encrypted profile
(`lib/core/polls/poll_manager.dart`). Closed polls are automatically
deleted after 90 days, configurable per chat in the chat settings (§22).

---

### 18.4 Anonymous voting

#### 18.4.1 The ring-signature primitive

Cleona uses an MLSAG-style Linkable Ring Signature over Ed25519
(`lib/core/crypto/linkable_ring_signature.dart`). Its construction: the
voter signs their vote over the ring of all N member pubkeys — the
signature proves "one of these N members signed", without revealing
which. The key image `I = sk · H_p(pollId ‖ P_j)` is deterministic per
`(sk, pollId)`: the same voter always produces the same key image for
the same poll (duplicate detection), without it being attributable to a
pubkey without knowledge of `sk`; across different polls, key images
are unlinkable. Hash-to-point is
`crypto_core_ed25519_from_uniform()` (libsodium); the curve operations
(`crypto_scalarmult_ed25519`, `crypto_core_ed25519_add`) come from
Cleona's `sodium_ffi.dart`. Signature size `N × 64 B + 32 B`,
verification cost N point multiplications.

**Primitive shared with §16.4.** The same construction has carried the
jury vote since the moderation procedure (§16.4). That has two
consequences that belong on record here: (a) the review item (optional
external crypto review) covers both uses — there is only one review,
not two. (b) A documented **quantum limit** applies: the `ringMembers`
pubkeys travel in plaintext inside the sealed vote; a future
cryptographically relevant quantum computer (CRQC) can back-compute the
secret scalar from any pubkey, use it to recompute the candidate key
image `I' = sk · H_p(pollId ‖ P)` for every ring member, match it against
the recorded key image, and retroactively deanonymize the voter — and
likewise forge ring signatures. A production-ready post-quantum ring
signature does not exist (liboqs delivers only plain signatures; lattice
LRS schemes are research code with signatures in the two- to
three-digit KB range); Cleona accepts and documents this limit instead
of shipping homegrown research crypto — whoever needs to vote secretly
against a quantum attacker with a decade-long horizon does not use
anonymous polls. The dominant risks remain, in practice, anonymity-set
size and N−1 collusion (§18.4.6), both quantum-independent. §4.4
explicitly declares the same limit for the entire public object space as
a deliberate decision.

#### 18.4.2 Anonymity toward fellow voters

Anonymous voting must distinguish between two different attackers:

- **Protection against the recipient** — against fellow voters. What
  is designed for this is a de-attributed inner frame: empty
  `senderUserId`, no user signature, authenticity solely from the ring
  signature, which every participant verifies anyway.
- **Protection against the transport** — against observers along the
  way. The delivery layer itself delivers this: cells are flowless and
  opaque to every relay (§5). Forwarding via a randomly chosen third
  node that resends every vote blob under its own device identifier is
  not needed for this and would be worse: the third party would learn
  that device X voted.

The difficult attacker is therefore the **recipient**: every recipient
of a vote learns who voted when — the ring signature protects the
persisted tally (DB, snapshots, exports, UI), not against the
participants themselves. The delivery layer does not help against that.

**A de-attributed frame is not enough for this.** Group messages run as
**pairwise legs** (§16.2), which explicitly holds:

> The tag authenticates the sender per leg symmetrically-deniable as in
> 1:1; an inner signature is not required.

The tag itself is derived per direction from `K_AB` (§4.3). Bob
receives a cell precisely because it sits under the
tag of the pair (Alice, Bob) in the Alice→Bob direction. **The sender
identifier sits in the tag, not in the payload.** A de-attributed inner
frame changes nothing about that: Bob knows from the tag alone that
Alice placed it.

**Finding:** *Anonymous voting in groups is structurally impossible over
pairwise legs.* Not "weak", not "limited" — anonymity toward fellow
voters cannot be established with this carrier. The problem is not the
counter space, but the tag itself.

Three options:

| Option | Construction | Cost |
|---|---|---|
| **A — Withdraw the commitment** | "Anonymous in the result, not toward fellow voters." The UI says this explicitly. The ring signature stays for tally, persistence, snapshots, and export | Honest and immediately implementable: the UI only promises anonymity in the result. Cost: the feature is worthless for the main use case (a sensitive vote in a group) |
| **B — Dedicated poll tag family for anonymous votes** | Anonymous votes run **not** over pairwise legs, but under a tag family derived from `pollId`: `tag_vote = HKDF(pollId, "vote" ‖ n)` — exactly the pattern that §16.3 already uses for channel votes and §16.4 for jury votes. The tag carries no pair information; the ring signature carries the authorization, the key image the duplicate detection. `pollId` is distributed within the group and not derivable by outsiders | The construction already exists twice in the draft and is therefore not a new building block. Cost, honestly: (1) the tag on which `tag_vote` sits must be **subscribed to** by all group members — an anonymous poll occupies one additional subscription for its runtime, while groups otherwise hold **no** subscription. The sync partner sees this subscription. (2) the tag falls under the same eviction question as the poll-tag-family quota (§18.3.3). (3) the list of exceptions to the single-use-tag invariant is extended by the family |
| **C — Vote only to the creator** (channel pattern, also for groups) | As in §18.3.3: vote sealed against the creator pubkey, creator publishes `POLL_SNAPSHOT` | No additional subscription. Cost: the creator becomes the tallier, and §16.1 rejects exactly that ("hiding them would only be possible with a trustworthy tallier, which does not exist"). Possibly acceptable for a group of acquaintances, not for the use case "anonymous vote because you don't trust the creator" |

**Decided: B is normative.** The finding is classified as a
design flaw of the procedure, not as a limit of the commitment — so it
is the **carrier** that changes, not the commitment: anonymous votes run
under the poll tag family `tag_vote = HKDF(pollId, "vote" ‖ n)`, never
over pairwise legs. The three costs are part of the decision: (1) the
runtime-limited additional subscription for all group members (joining
the decoy regime for its runtime, §5); (2) the quota question is **decided jointly with
the poll-tag-family quota** — the poll tag family attaches to the
moderation family's protection (§16.4); (3) the exception list to the
single-use-tag invariant is extended by the family. **Option A remains
the transition state until B is implemented** — until then, the UI must
not assert an anonymity that the carrier does not deliver.

#### 18.4.3 Anonymous polls in channels: no ring

`PollVoteAnonymous.ringMembers` carries the N public keys against which
verification happens. In a **group** the ring is well-defined: the
member list. In a **public channel** there is no subscriber list —
§16.8 explicitly holds that there is no subscriber structure, no
`subscriberCount`, and no knowledge of who is reading.

**Without a known set, no ring; without a ring, no ring signature.**
Anonymous polls in public channels therefore cannot be constructed.

**Decided: (a).** Anonymous polls are **not available** in
public channels; the UI hides the setting there — the honest variant.
Rejected: (b) a ring built from the registered role pseudonyms of the
channel language (§16.5) — it would be well-defined and publicly
checkable, but forces every voter into a public registration and thereby
contradicts the purpose (whoever wants to vote anonymously should not
first have to register publicly). (b) remains conceivable as a later
extension, but is not part of the current design.

Anonymous polls in **groups and private channels up to N ≤ 16**
(§16.2.1) are not affected
by this — there, distribution runs over pairwise legs (§16.2) with a
known roster, and §18.4.2 applies.

#### 18.4.4 Vote change: revoke needs an ordering rule

A vote change must not depend on ordering. A two-stage procedure —
first a `PollVoteRevoke` with a key-image possession proof (a signature
over "revoke" with the same ring), on receipt of which all participants
remove the old vote for that key image, then a new `PollVoteAnonymous`
with the same (deterministic) key image — assumes exactly that. Without
transport order, the new vote can be received before the revoke; it is
then discarded as a duplicate and the old vote remains standing — a
silent error invisible to the voter. Therefore:

**Rule (normative):**

1. Every anonymous vote carries a **monotonically increasing counter**
   `voteSeq` per key image. The recipient keeps, per key image, the vote
   with the highest `voteSeq`; lower ones are discarded, regardless of
   arrival order.
2. This makes `POLL_VOTE_REVOKE` **dispensable** for a plain vote change
   — the new vote takes the place of the old one, just as `allowVoteChange`
   already does for non-anonymous votes (the newer vote, by `votedAt`,
   overrides the older). Anonymous and non-anonymous votes thereby
   follow the same rule, just with a different key (key image instead
   of `voterId`).
3. `POLL_VOTE_REVOKE` remains in place for the **outright withdrawal**
   of a vote ("I did not want to have voted at all") and then likewise
   carries a `voteSeq`.

#### 18.4.5 Timing jitter as application-level protection

The random send offset of **0–30 s** before vote distribution is an
**application-level protection**, not a transport-level protection: the
cover stream levels timing by design (§5, Poisson-timed cover at mean
rate `R_cover`, §5.2).

As an application-level protection it carries this: if Alice's
non-anonymous presence in the group (chat message, reaction, typing
indicator) correlates in time with the moment an anonymous vote appears
in the tally, a random offset helps.

#### 18.4.6 Anonymity limits

The anonymity set is the ring size — a group of 3 offers practically no
anonymity; the UI warns below 7 members and shows the notice "anonymity
set: N members." If N−1 members collude, they deduce the last vote by
elimination — that is inherent to any anonymous voting procedure with a
known set of voters. Both are quantum-independent.

---

### 18.5 Open points of this chapter

| # | Topic | Status |
|---|---|---|
| **CAL-3** | Free/Busy: state model for the round trip. The channel exists (contacts share `K_AB`), the **round trip** does not. Options A (asynchronous partial grid with `expiresAt`) / B (push instead of pull, opt-in per contact) / C (replace with DATE_POLL). Plane D rejected | open (§18.1.5) |
| **CAL-4** | Free/Busy auto-responder: egress-quota assignment; possibly a dedicated short TTL class for the response — that would be a delivery-chapter change (§9) | open (§18.1.5) |
| **CAL-7** | Group-call start from the event card stays locked until the group-call topology (§17) is decided | bound to §17 |
| **POLL-4** | `onlyMembersCanVote` has no checkable denominator. Recommendation: remove outright | open (§18.3.3) |
| **Editorial** | §5 needs a caveat for opt-in services (external calendar sync, media archive), otherwise the cover-uniformity commitment is false as an assurance | change outside this chapter (§18.2) |

---

## 19. Synchronization strategy

*(Basics)*

- **No polling.** Delivery is event-driven (§3.1, §5.4); the cover stream
  carries no sync. There are no demand-driven queries whose occurrence
  would itself be information. **This governs the delivery layer.** Plane
  D (§17, including the media stream §17.6) and the bulk lane (§9.3) are
  declared demand-driven classes; their occurrence *is* information, and
  B-10 / B-29 price exactly that.
- **Foreground:** a standing streaming harvest subscription (§8).
- **Background:** burst harvest according to the platform's cadence
  (§8).
- **Network change:** every neighbour counts as not answering; remembered
  addresses are re-attempted once and the neighbour call is repeated once
  (§11.8). The node discards its observed public address, so no card
  issued afterwards carries a stale one. Messages already left are not
  sent again because of this edge alone. The node registers its codes
  again with its fixed neighbour (§8.1); contacts learn a new fixed
  neighbour only from the node itself, sealed (§8.1). A device address
  alone is announced to nobody.
- **Platform specifics:** the Android foreground service carries the
  sync (Arbeitsregel #8); iOS uses the background-refresh window fully
  for one burst (§31).

---

## 20. Network resilience

### 20.1 What must not happen

| | Requirement |
|---|---|
| R-1 | A node under load must not drop a message it has accepted for sending |
| R-2 | A node must not consume unbounded memory because of what others send it |
| R-3 | A partition must not corrupt state; it must only delay delivery |
| R-4 | Recovery after a partition must need no operator action |

### 20.2 Every queue is bounded, and the bound is stated

An unbounded queue is a slow crash. Every buffer in the system has a
declared limit and a declared behaviour when it is reached.

| Buffer | Bound | On overflow |
|---|---|---|
| outgoing parts awaiting re-request (§11.3) | one transmission at a time per recipient | the caller is blocked, not the socket |
| incoming reassembly (§11.3) | 30 s per transmission | oldest incomplete transmission discarded |
| post box per day value (§8.2) | 100 packets | oldest discarded |
| post box, all identifiers together (§8.2) | [OPEN: measured, not yet set] | oldest discarded |
| post box, size of one packet (§8.2) | [OPEN: measured, not yet set] | refused |
| forwarder loop memory (§8.1) | 60 s | oldest discarded |
| request buffer (§15.4) | 20 shown, 100 held | oldest evicted, never blocked |
| neighbours (§11.7) | 32 | longest silent dropped |

**Evicting beats blocking.** A full buffer that refuses new entries hands
an attacker a way to close the channel: fill it once and nothing gets in
again. A full buffer that evicts the oldest keeps working, and the cost
of an attack is that the attacker's own entries are the ones that age
out.

### 20.3 There is no queue in the delivery path

The delivery path has no queue at all. A packet is handed to the socket
when it exists (§3.1); the ladder runs its steps in parallel (§7.1) and
the first acknowledgement ends the attempt. Nothing waits for a tick,
and no buffer sits between a message and the wire.

This removes the failure that an unbounded or contended queue would
otherwise produce: a standing backlog that throttles delivery while
every individual component reports itself healthy.

### 20.4 Partition

A partition is not a distinct state and needs no detection.

| Situation | Behaviour |
|---|---|
| no neighbour answers | ladder steps 1–3 fail, step 4 places in the post box (§8.2) |
| no neighbour at all | the message stays `in transit`; the sender is told nothing is reachable |
| network returns | remembered addresses are re-attempted once, the neighbour call is repeated once (§11.8) |
| recipient returns | collects from the post box (§8.2) |

Nothing is retried on a timer, and no state needs repair. A node that
has been isolated for a week rejoins by the same three sources it used
at first start.

### 20.5 Load from other nodes

| Attack | Bound that answers it |
|---|---|
| flood of contact requests | proof of work before opening (§15.5.1), invitation kind (§15.3), revocation |
| flood of parts | reassembly discard after 30 s, one transmission at a time per sender |
| flood of post box placements | proof of work per placement, 100 per day value, 7-day retention (§8.2) |
| forwarding loop | hop count 3 and 60 s loop memory (§8.1) |
| unparseable packets | discarded without an answer (§11.5) |

Each bound is local: a node enforces it alone, needs no agreement with
anybody, and keeps working when its neighbours do not.

### 20.6 Eclipse

A node that only ever learns neighbours from one source can be fed a
false view of the network. Three properties answer this:

1. Neighbours come from three independent sources at once (§11.8):
   remembered, the local segment, and the first contact's card.
2. A contact's card carries its own addresses (§15.2), so reaching a
   contact does not depend on the neighbour set at all.
3. The post box places with three neighbours and needs two (§8.2), so a
   single dishonest neighbour cannot swallow a message.

An attacker who controls every neighbour of a node can still deny it
service. It cannot read anything, forge anything, or make the node
believe a message was delivered when it was not, because delivery is
acknowledged by the recipient under its own key (§9.2).
## 21. Storage & Data Management

*(This chapter fully describes what Cleona stores: locally on the
device, on the delivery layer, and in the durable-object class.)*

### 21.1 Storage priorities

The storage order has four tiers:

| Prio | Content | Deletion criterion |
|---|---|---|
| **1** | **Own chats, media, calendar, polls, contacts, metadata.** The user's personal data | **never automatic** — except via rules the user has set themselves (per-chat expiry §21.5.3, media archive §21.6, voice retention §21.7) |
| **2** | **Delivery-layer storage:** third-party cells of the subscribed tag lines | TTL expiry (14 d default, 31 d for management types) **or** eviction under tag-line-budget overflow, **within the quota** (§20): near-expiry/oldest first |
| **3** | **Durable-object class** (§16.0): anti-entropy replicated objects | Type rules per object (table in §16.0); on sub-budget overflow, trimming **within** the sub-budget, newest-first by first-acceptance day |
| **4** | **Operational state:** tag-line subscription list, liveness records, sync-partner statistics | discardable and re-acquirable at any time |

**The invariant.** The local data store on the device is the **only**
place priority-1 data resides. Any network-side persistence is incidental
and volume-bounded; the local profile is the sole authoritative source.
The delivery-layer share is ciphertext with no key reference (§5), not
a store from which anything could be reconstructed.

---

### 21.2 Network storage classes: delivery layer, durable objects, bulk cache

There are three network storage classes: the **delivery layer**
(§9), the **durable objects** (§16.0), and the **bulk cache** (§9.3,
§21.3.3) — the capped, lowest-priority class that holds fountain blocks
of media, file transfer, and the binary distribution on always-on nodes.
Everything a node holds for others falls into one of these three classes.
The stream lane (§17.6) stores nothing and appears in no storage class.

**Delivery layer (§9).** Third-party cells of the subscribed tag lines —
one tag-line budget, eviction only within the quota (§20), one
network-wide uniform procedure, one format for all content. Bulk blocks
are uniform cells on the wire (entry type 0x05) but they are **not**
delivery-layer cells: they live in their own budget class (E-53), are
evicted first under pressure, and are held per holder
(§9.3), not replicated at the delivery layer's redundancy factor (§9). Cells carry no attributable sender; an eviction cap "per
source" is therefore structurally impossible and is not needed either.

**Durable objects (§16.0).** Anti-entropy replicated objects across
relays, with type rules per object and fixed sub-budgets. The directory
entry of public channels lives in this class (§16.0/§16.3), not on the
delivery layer.

**No addressable storage location per recipient.** There is no mailbox
derivable from a pubkey, no special store for first-contact requests
(first contact runs over the invitation tag family, §15), and no
network-held auth manifests: no XOR metric, no replicator role, no
pollable state about a third-party identity. §4.3 / §8 list this as a
core property (liveness is pairwise-replicated, not a pollable
third-party state).

**Local outbox.** A node's own cells stay in local storage until sending
is confirmed, as described in §9 — no timer retry, no route state, no
persistent send queue.

---

### 21.3 Budgets — decided

The storage budgets are fixed, as the document's last
implementation-blocking point. This section presents the fixed values
first, then the derivation, then the decision itself.

#### 21.3.1 Fixed values

| Item | Value | Kind |
|---|---|---|
| Delivery-layer storage, **desktop** (Linux/Windows/macOS), full TTL | **~160 MB** | Storage |
| Delivery-layer storage, **mobile** (Android, iOS) | **48 h retention + 32 MB hard cap** — whichever binds first applies | Storage |
| Durable-object class per node, target size | **≤ 10 MB**, split fixed **6 / 2 / 2 MB** (directory+registrations / verdict and deadline-bound types / rolling) | Storage |
| **Bulk cache** (desktop only) | **1 GB default**, user-overridable in tiers following the §21.6 pattern | Storage, third-party data, lowest priority |
| Cover + harvest traffic, **mobile** | **~10–21 MB/day** cover (§5, M7) + `1.15+0.23·S` MB/day liveness (§8) — for iOS an upper bound, not an expectation | **Traffic, not storage** |
| Cover + harvest traffic, **desktop** | cover + liveness + bulk relay throughput | **Traffic, not storage** |
| Media-archive budget on the device | **100 MB (mobile) to 2 GB (desktop)**, freely settable; the archive's **four** storage tiers (§21.6) are a separate dial | Storage, **local, own data** |

The archive has
**four** storage tiers — `ArchiveTier` in
`lib/core/archive/archive_config.dart:14` carries `original`,
`thumbnail`, `mini`, `metadataOnly` with three boundaries (30 / 90 /
365 d). The budget
itself is not stepped at all: `settings_screen.dart:758` binds it to a
free numeric field. The tier count and the storage-budget size are two
independent dials, not to be conflated.

The risk of confusion is real and is explicitly cleared up here:
**~10–21 MB/day is not a storage value.** §5/§8 describe cover and
liveness *traffic*; how much a mobile node **holds** is given in the row
above.

#### 21.3.2 Derivation of the mobile values

The **48 h retention is normative**.

The order of magnitude can be derived from two documented figures:
~160 MB for **14 days** of full retention, i.e. **~11.4 MB/day** of
delivery-layer inflow for the base subscription set; 48 h correspond to
roughly a seventh, **~23 MB**. Add to that the observation that eases
the decision: **the traffic quota binds before the storage does.** At
~10–21 MB/day cover + liveness in the background (the cover share
dominates by design, §5), a mobile node cannot receive the 11.4 MB/day
of its subscription set at all — a pure background node accumulates real
single-digit MB per 48 h. Only in the foreground (streaming harvest,
§8) does it approach the full 48-h window. The **32 MB cap** is
therefore not a pressure point in normal operation but a device
safeguard: ~23 MB expected value for the full window plus ~40 %
headroom against volume growth.

Rejected alternatives: *retention only, normative* (if the
delivery-layer volume per tag line doubles, the mobile footprint grows
without bound — violating device-limit robustness); *storage value
only, normative* (with shrinking volume the node would hold arbitrarily
old cells, the eviction semantics would stay implicit, and the
retention rule would stay open).

#### 21.3.3 The decision (normative)

1. **Mobile double rule.** Retention **48 h** normative (older is
   evicted) **and** hard storage cap **32 MB** — whichever binds first
   applies. If the cap binds before the 48 h expire, eviction follows
   the per-tag-line quota rule (§20): near-expiry/oldest first, within
   the quota. Both values are configurable constants.
2. **Additivity with a hard ceiling per class.** Delivery layer, durable
   objects, media archive, and bulk stand side by side; no class draws on
   another. This is the only way that structurally guarantees the side
   condition: **third-party data (priority 2) never evicts own data
   (priority 1)** (§21.1). A shared quota would have to buy that
   guarantee through extra machinery and would remain error-prone —
   rejected.
3. **Bulk as its own, fourth capped class.** Desktop installations only;
   mobile nodes carry no bulk. **1 GB default**, user-overridable in
   tiers analogous to the media budget (§21.6 pattern), no automatic
   growth with disk size. **Lowest priority:** under disk pressure, bulk
   is trimmed first (ahead of the delivery layer), with eviction within
   the class by the §20 rule. Explicitly **not** decided alongside
   this: fountain block count, redundancy factor, desktop share of the
   relay set — that remains a measurement task.
4. **Visibility.** §16.0 already requires it for the durable-object
   sub-budgets; the same rule applies normatively to the delivery layer
   and bulk: a node that evicts under budget pressure shows this visibly
   in the network statistics (§25). A silently shrinking delivery layer
   is the storage variant of the failure mode §1.2 rules out for
   delivery (no state asserts delivery without substantiating it).
5. **Remaining headroom not allocated.** Redundancy m and decoy count d
   are set per the measurements (§9, M7); the base subscription count
   also applies to mobile.

**Total footprint (worst case, all caps full):**

| Platform | Delivery layer | Durable objects | Media (priority 1, user) | Bulk | Total third-party / overall |
|---|---|---|---|---|---|
| Desktop | ~160 MB | 10 MB | up to 2 GB (tiers, §21.6) | 1 GB default | ~1.2 GB third-party / ~3.2 GB |
| Mobile | ≤ 32 MB | on-demand partial cache (§16.0, does not hold the class in full) | 100 MB default | 0 (no bulk) | ~32 MB third-party / ~135 MB |

The larger desktop footprint deliberately falls on the platform class
that can carry it (§31 ranking).

---

### 21.4 Encryption of local data

**Method.** XSalsa20-Poly1305 (libsodium), key
`deriveFileEncKey(master_seed, hd_index)` for identity-bound data and
`deriveSharedFileEncKey(master_seed)` for device-wide state
(`lib/core/crypto/hd_wallet.dart:219` and `:231`), file format
`[24-byte nonce][ciphertext incl. 16-byte MAC]`
(`lib/core/crypto/file_encryption.dart:12`). Writes are atomic
(`.tmp` → `rename`).

**Persistence form.** Configuration state runs through encrypted JSON
envelopes (`FileEncryption` + `lib/core/storage/atomic_json_writer.dart`),
one file per subsystem (`calendar_events.json.enc`, `chat_policies.json`,
`calendar_sync_config.json.enc`, …), compressed per §4.5.3. Messages and
conversations do not — they live in the message store described next.

#### 21.4.1 The message store

SQLite3 Multiple Ciphers 2.5.1 on SQLite base
**3.53.4**, vendored as an amalgamation under
`native/cleona_store/vendor/sqlite3mc/` and never taken from the system
library. The base version is normative and must stay **>= 3.53.3**:
CVE-2026-11822 and CVE-2026-11824 are memory-corruption defects in the
FTS5 full-text search extension (an out-of-bounds read in
`fts5LeafSeek()`, a heap overflow in `fts5ChunkIterate()`), fixed in
3.53.2/3.53.3. Distribution libraries lag behind this; the build machine
carried 3.45.1 at the time of writing.

- **Cipher:** ChaCha20-Poly1305, the default scheme. No second large
  crypto library enters the build — the reason SQLCipher was not chosen,
  which supports only OpenSSL, LibTomCrypt and CommonCrypto, none of
  them libsodium.
- **Key:** `deriveFileEncKey(master_seed, hd_index)`, handed over as
  `PRAGMA hexkey` — the raw 32 bytes, not a passphrase. The key is
  already seed-derived; a second derivation on top would buy nothing.
- **One database per identity.** A shared one would have to sit under
  the device-wide key and would give up the separation that
  `deriveFileEncKey` establishes: the key of identity 1 does not open
  the data of identity 2. Deleting an identity stays a directory
  removal, verifiable at the directory, rather than a list of `DELETE`
  statements whose completeness nobody can check.
- **Deletion:** `SQLITE_SECURE_DELETE` is compiled in. Without it a
  database releases deleted pages for reuse instead of overwriting them,
  and "deleted" would mean "no longer indexed" — which §21.5 does not
  permit.
- **Identifiers are stored as BLOB, not as hex text.** Measured: that
  alone accounts for 27 % of the database size, more than the entire
  text compression contributes (12-17 %), because the inflation applies
  three times over — in the row, in the primary key, and in the index.
- **Defensive mode stays enabled** (`SQLITE_DBCONFIG_DEFENSIVE`), and
  the SQLite version belongs in the same preflight check that verifies
  DLL provenance today.

#### 21.4.2 Attachments: three destinations, one precedence chain

Message text
and conversation metadata always live in the message store; there is no
setting that puts them anywhere else. **Attachments** are different —
they are files, they are read by path, and the user has a legitimate
interest in reaching some of them with their own tools. Every attachment
therefore takes exactly one of three destinations:

| Destination | Form | Who can read it |
|---|---|---|
| **1 — in the store** | row in the encrypted database, compressed | the app only |
| **2 — sealed beside** | framed AEAD, `<name>.cmenc`, streamed | the app, plus foreign programs through the decrypting reader on `127.0.0.1` |
| **3 — plaintext on disk** | unencrypted file | anything, including the user's other tools |

Destination 2 is the default for attachments, not destination 1: a
500 MB attachment does not belong in a database row, and the framed AEAD
holds **0 kB** peak memory against six times the file size for a
whole-file envelope. Destination 3 is a deliberate lowering of
protection and is never a default.

**The choice is made on three levels; the most specific wins:**

| Level | Scope | Default |
|---|---|---|
| 1 — app | per file type (image, video, audio, archive, document, …) | the main setting |
| 2 — conversation | per contact, group, channel | inherits level 1 |
| 3 — file | the individual attachment | inherits level 2 |

Level 2 is congruent with level 1 out of the box — it is an opportunity
to deviate, not a second thing to maintain. **The default is
"encrypted", never plaintext.**

**Normative for the interface:** every file must show **which level
decided**. With three levels a user cannot otherwise tell why a
particular file ended up in plaintext, and a control the user cannot
read is a source of error rather than a control.

**What this costs, measured** (ext4, 150 000 messages):
opening the database costs **+38.9 ms once per program start**; the
search shows no measurable overhead from encryption; the file grows by
**1.6 %**. Against this stands the previous form with **3 497 ms** load
time and a **1 005 MB** memory peak for the same data, which is why the
store exists. The property "the file on disk is encrypted" is held by a
gate with an inverse probe
(`native/cleona_store/test/store_encryption_smoke.c`): the same source
compiled without a key must fail, or the gate would be measuring
something other than the claim.

**Normative: the harvestable-tag set needs protection.** The node
maintains a set of tags it matches incoming cells against (mechanism:
§6) — for 200 contacts, roughly **24,000 entries**, a few hundred
KB of raw 16-B tags. This set is the central correlation target:
whoever captures it in plaintext can match it against an archived
delivery-layer recording and identify all of the user's cells — without
decrypting them, but with a complete communication pattern. It
therefore lies **mandatorily under the DB key**, together with
`inbox_key`, the prekey pool (§4.6) **and the receiver's daily ML-KEM
secrets (§4.3), retained no longer than the identity KEM rotation
interval (7 days)**. The **tag-line subscription list
of the delivery-layer storage** (real and decoy tag lines are
indistinguishable without the list) is likewise mandatorily encrypted —
but it is device-bound, not identity-bound, and therefore lies under a
device-derived index key (§4.5, device-key derivation), not under the DB
key. A "cache directory" for tag prefixes outside encryption is
explicitly impermissible.

**The delivery-layer storage itself needs no additional encryption
layer.** Third-party cells are already ciphertext with no key reference
(§5). They may sit unencrypted on disk; that saves the
decryption/encryption on every cell reconciliation, and the confiscator
table (§21.8) presupposes exactly this property: "third-party cells:
ciphertext with no key reference." Only the **tag-line index** carries
an envelope (FileEncryption under the device-derived index key) — it is
the only thing in the relay holdings that would reveal anything.

**Where the profile lies.** All identity data sits in one directory,
`.cleona`, below a per-platform home:

| Platform | Location |
|---|---|
| Linux | `$HOME/.cleona` |
| Windows | `%USERPROFILE%\.cleona`, else `%APPDATA%\.cleona` |
| macOS | `$HOME/.cleona`, or Application Support where the platform resolves one |
| Android | `/data/data/<package>/files/.cleona` — app-private, and the package name carries the `.beta` suffix, so beta and live have **separate** profiles |
| iOS | the app container; where `HOME` is unset it is derived from the bundle path |

On the three desktop platforms the directory carries **no channel
suffix** — a beta build and a live build on the same account therefore
use the **same** profile directory, and only one of them can own it at a
time (§15.1 single-instance lock).

Importing the 24-word seed is the regular recovery path (§13).

---

### 21.5 Deletion and retention

#### 21.5.1 Edit window and unbounded deletion

The following applies:

- **Editing is window-bound and enforced on both sides.** Only the
  author may edit; an edited message visibly carries the suffix
  "(edited)" with the timestamp of the last change. On the sender side,
  the button disappears after 15 minutes (purely cosmetic); on the
  receiver side, edits are rejected if they arrive more than 60 minutes
  after the original. The per-chat override `edit_window_ms` overrides
  both values.
- **Deletion is unbounded.** The author may delete their message at any
  time; the sender UI and the receiver's deletion handler check only
  authorship, never age, and reference neither `edit_window_ms` nor any
  tolerance. There is no deletion window, and there is not meant to be
  one.
- **No edit history.** Only the current version exists (data
  minimization).

**On the 60-minute tolerance.** Without transport ordering, the gap
between original and edit on the receiver side is not determined by a
send delay but by arrival order (§7, §8); an edit can arrive before the
original. The receiver therefore evaluates only the **timestamps in the
content**, never the arrival order — the same rule as for the calendar
(§18.1.3) —, and an edit to a still-unknown message is buffered instead
of discarded. Precisely for this reason, the receiver-side tolerance is
set wide, at 60 minutes.

#### 21.5.2 What deletion means on the delivery layer — an honest declaration

**The deletion semantics on the delivery layer are to be declared
explicitly, not tucked into a footnote.**

A deletion has three levels of effect:

1. **Locally.** The message disappears from the user's own profile.
   Immediately and completely.
2. **On the counterparty's devices.** `MESSAGE_DELETED` is an ordinary
   cell and is sent over the same pairwise legs as any other message
   (§16.2). It takes effect once the recipient's device receives it, per
   the timing in §7 and §8 (indeterminate on iOS with the app
   closed, §31). Best-effort: the deletion request is a request, not a
   compulsion — a modified client can ignore it.
3. **On the delivery layer.** **The original cell stays put until its
   TTL clears it.** It is not revocable, not overwritable, and not
   traceable — the sender does know its tag, but has no mechanism to
   remove it from third-party relay holdings, and none is meant to exist
   (§20: "Sybil is blunt … can … **delete** nothing").

**How long.** §21.8 quantifies it for the confiscator: "With an
archived delivery-layer recording: only undelivered cells, max. 14 days
default / 31 days for management types." For a deleted message, that
means: up to 14 days after sending, its ciphertext still sits with
third-party relays.

**There is no *confirmed delivery* as a deletion criterion.** A relay
never learns whether a cell was received; there is no return channel
through which it could find out. That is exactly the property that §5
("no connection between sender and recipient") and §21.8 ("relay sees:
tag, TTL, ciphertext") establish. A cell leaves a third-party relay
holding only through TTL expiry or eviction (§20).

> **Normative:** A collected cell does not disappear any earlier. It
> **expires**. Delivery does not shorten its dwell time.

**Two approaches that were examined and rejected:**

- *A retract cell under the same tag.* It would break the
  single-use-tag invariant (§4.3) and would reveal to the relay exactly
  the linkage between two cells that the invariant prevents. The relay
  would learn "this cell belongs with that one" — the first building
  block of a traffic analysis. **Rejected.**
- *A shortened TTL for everything, so less stays put.* The 14-day TTL
  is the deliberately chosen delivery window for offline recipients.
  Taking the deletion semantics as an occasion to turn it back would
  fake security and cost deliverability. **Rejected.**

**Normative for the UI:** The UI must not present "deleted" as "removed
from the network". The deletion dialog states the effect honestly: the
message disappears on the devices, the sealed ciphertext expires on the
network within the TTL. That is the same honesty rule §5 establishes
for the cover and that §12 establishes for the interface as a whole.

#### 21.5.3 Per-chat expiry

Every conversation (1:1, group, channel) has an individually
configurable auto-delete timer. If it is set, messages disappear on all
participants' devices once the deadline elapses. Decisive: **the timer
starts after READING**, not after sending. In 1:1, one side proposes the
change and the other confirms it; in groups and channels the owner sets
it for everyone. Changes affect only future messages — existing ones
keep their original deadline.

Starting after reading is mandatory: the delivery window is 14 days, so
a recipient can stay away for a long time. A send-time-bound timer would
delete messages before anyone had seen them.

The deletion itself follows §21.5.2 — even an expired message sits as
ciphertext on the delivery layer until its TTL expires.

#### 21.5.4 Per-chat configuration

The following negotiable settings apply per conversation:

| Setting | Type | Default | Meaning |
|---|---|---|---|
| `allow_downloads` | bool | true | whether received files may be saved |
| `allow_forwarding` | bool | true | whether messages may be forwarded |
| `expiry_duration_ms` | int? | null (no expiry) | auto-delete deadline after reading (§21.5.3) |
| `edit_window_ms` | int? | null → 60 min | edit window, enforced on both sides (§21.5.1) |
| `read_receipts_enabled` | bool | true | whether read receipts are sent |
| `typing_indicators_enabled` | bool | true | whether typing indicators are sent |

**Change flow.** In 1:1, the change requires consent: the proposal goes
out as `CHAT_CONFIG_UPDATE` to the partner, whose app shows a
confirmation dialog; the reply comes back as `CHAT_CONFIG_RESPONSE` with
an `accepted` flag and the original changes. On acceptance, both sides
adopt it; on rejection, the proposer is notified. In groups and
channels, owner/admin authority applies: the change is distributed
directly to all members and takes effect immediately, with no
confirmation step; the role check happens on both sides (sender and
recipient).

**Download directory.** Configurable per identity profile, stored in
`chat_policies.json`. Desktop (Linux/Windows/macOS): the default is the
system's standard download folder (`~/Downloads`). Mobile
(Android/iOS): the default is an app-internal download directory; if the
user switches to an external directory, the storage permission is
requested **at that point**, not at install time. **Self-copy
protection:** if the source file already sits in the target directory,
a copy operation onto the same path would truncate the file to 0 bytes;
source and target are therefore compared canonically and the copy
operation is skipped, with the notice "already in the download folder".

**Buffer for configurations for unknown groups.** If a
`CHAT_CONFIG_UPDATE` arrives for a still-unknown group, it is buffered
(`_pendingGroupConfigs`) and applied once the invitation arrives,
provided the sender holds the owner or admin role. The buffer is
**mandatory**, because there is no transport ordering: the
configuration can arrive before the `GROUP_INVITE`. Buffer bound
as in §18.1.3: the maximum delivery TTL (31 days) plus retention margin,
after which no cell that would need the buffer can arrive anymore.

`typing_indicators_enabled` keeps its meaning but gets an additional
constraint: the typing indicator is sent **only in the foreground and
only over Wi-Fi**. The chat setting can turn it off; it cannot turn it
back on against that rule.

#### 21.5.5 Delivery-status display

A recipient decides, per conversation (contacts and groups; channels
excepted), whether their arrival acknowledgment may appear to the sender
as a delivery icon. The setting is **one-sided, local, and not
negotiated** — it is never proposed, never confirmed, never rejected,
and is therefore explicitly **not** part of the negotiated chat
configuration from §21.5.4. A partner may not have a say in the
recipient's visibility. Default: show.

**Carrier.** The bit rides on the delivery-receipt cell (§9.2). Since
receipts are bundled anyway, it costs **zero additional traffic** (work
rule 5). The encoding
is **withhold**, not *disclose*: a missing field reads as "show"; the
reversed encoding would silently turn every delivery-receipt cell
without the field into a suppression. Mirrored locally in
`ContactInfo.withholdDeliveryStatus` / `GroupInfo.withholdDeliveryStatus`.

**The delivery state does not hinge on how the receipt travels.** The
state is `in transit` until the receipt (§9.2) arrives, regardless of
which rung of the ladder (§7, §8) carried it there; receipts are purely
application-side. It follows
that:

| Level | Rule |
|---|---|
| Delivery (§9.1) | The state is `in transit` until a receipt arrives; nothing else changes it |
| Application/UI | `in transit` → `delivered` only on a received delivery-receipt cell **with** `disclose` |

Without a delivery-receipt cell, the sender learns nothing about the
arrival: the state stays `in transit` indefinitely — indistinguishable
from whether the recipient received and withheld it, or was never
reachable at all, and per §9.3 no timer resolves this on its own.
Whoever **sends** the receipt
**and sets withhold in it** makes a policy commitment; whoever omits it
entirely reveals nothing at all. The frame is the open field: the
display suppression is a **policy guarantee without cryptographic
force**, and that is exactly how it must be described.

**Groups.** Aggregation per leg: visible `delivered` only once **every**
leg has received a delivery-receipt cell and no leg is withholding. A
withholding leg must never contribute to a visible delivery state —
otherwise the aggregate would reveal exactly what the member wanted to
withhold. A partial display ("3 of 5") counts only members that show
status. Groups **are** pairwise legs (§16.2); the term "leg" is meant
literally.

**Channels.** No delivery signal, and hence nothing to withhold: a
channel receipt would cost **O(N) cells** — against work rule 5. There
is no PoW to amplify (dropped); the cost is pure traffic. The
setting is not offered for channels.

**UI.** The switch sits in the chat settings dialog directly below the
pair of read receipts and typing indicator and is phrased positively
("delivery status visible" — on means show). Two properties distinguish
it from every other switch in this dialog and must not be "unified"
away: it is **not** subject to the owner/admin check, because even an
ordinary group member must be able to decide their own visibility; and
it is applied on its own path, not through the negotiated chat
configuration, which would route it into the consent flow from §21.5.4.
For channels it is hidden.

**What remains unresolved** is the interaction with read receipts:
whoever withholds delivery status but leaves `read_receipts_enabled` on
reveals the arrival through the stronger signal — the transition to
"read" is directly reachable, skipping the intermediate state. That is
defensible (whoever discloses "read" has disclosed more than
"delivered"), but nobody has decided it; a user who turns off delivery
status may well expect no arrival signal at all. Until this is
clarified, the honest reading applies: the withholding takes full
effect only once read receipts are off too. The finding is open,
including both options (coupling the `read` upgrade to the same flag, or
making the dependency visible in the UI).

---

### 21.6 Media Auto-Archive

The media archive (`docs/ARCHIVE.md`, `lib/core/archive/`) automatically
offloads media to a network share on the home network: as soon as the
device is on the configured home Wi-Fi and the share is reachable,
images, videos, and files are copied there; after a configurable
deadline, the originals disappear from the device — **never without
confirmed archiving**. Scope: 1:1 chats and groups, channels excepted.
It operates on **finished local files** and with **local network
infrastructure**, and therefore has no touch point with the transport.
Properties:

- **Tiered storage**, four tiers: 0–30 d original, 30–90 d thumbnail
  (~20–50 KB), 90–365 d mini-thumbnail (~2–5 KB, 64 px), > 1 a only a
  metadata reference (date, size, type icon). On the share, the original
  sits there unchanged from tier 2 onward. All boundaries are
  user-configurable. A retrieved original counts as new: its age for the
  tiers runs from the retrieval, not from the message, so it stays on the
  device as long as tier 1 lasts (default 30 d) and then steps down again.
  The storage budget may still displace it.
- **Pin/keep** on three levels (message / chat / global); pinned media
  is archived but never deleted from the device.
- **Network detection**: the share's **identity** decides, not the
  network's name. Archiving happens when the share answers AND presents
  the identity pinned on first use (see security rules). Two optional
  narrowings come before that probe and never replace it: the local
  subnet and default-gateway address (free of any permission on all five
  platforms), and an SSID list where the platform hands the name over
  without a location permission (Linux, Windows). A configured narrowing
  that does not match skips the run; an empty one narrows nothing.
- **Protocols**: SMB/CIFS and SFTP (mandatory), FTPS and
  HTTP(S)/WebDAV (optional). No plaintext FTP, no NFS. FTPS credentials
  run through a temporary `--netrc-file` (mode 0600), never on the
  command line.
- **Directory structure**
  `<Share>/Cleona/<Identity>/<Chat>/YYYY-MM/<name>_<hash>.ext` with
  content-hash dedup across devices and identities.
- **Security rules**: **never write to an unidentified share** — on first
  use the share's identity is pinned (SFTP: the host key; FTPS/HTTPS: the
  server certificate; SMB: a marker file `Cleona/.cleona-share-id` with 32
  random bytes), and a mismatch stops the run and asks the user instead of
  authenticating. Unknown is not mismatched: an unpinned share is pinned,
  a changed one is refused. Never delete without confirmed archiving (if
  the share is unreachable, the original stays put); reminder notification
  ("X MB archivable"); no encryption on the share (deliberate — the files
  are meant to be directly readable on the NAS); initial sync in the
  background with a progress indicator.
- **Storage budget**: in addition to the time tiers, a maximum media
  budget on the device; once it is exhausted, the oldest unpinned medium
  is archived first, independent of the tier configuration.
- **Batch retrieval** by time range or chat (requires an active share
  connection).

Three touch points are worth noting:

1. **The budget stands beside the delivery-layer budget** (§21.3.3,
   point 2). It is priority-1 storage and must not be evicted by the
   delivery layer.
2. **Archive traffic breaks the cover-uniformity commitment from §5**
   — SMB or SFTP traffic to the NAS is clearly recognizable from
   outside. As with external calendar sync (§18.2), that is a user
   decision, not an architectural weakness, but it must appear in §5 as
   a caveat.
3. **There is no relationship to the file transfer tiers.** The transfer
   tiers (inline ≤ ~1 MB, delivery-layer packet up to ~100 MB, relay
   swarm, direct transfer) concern the **transfer**. The archive picks
   up afterward, on the fully received file; archive placeholders fetch
   from the **share**, never from the network.

---

### 21.7 Voice transcription

whisper.cpp on-device (`lib/core/archive/whisper_ffi.dart`),
source-side transcription at the sender with receiver fallback,
tiny/base/small models (~40 / 75 / 250 MB, selectable per identity),
beam search `beam_size = 5`, language setting per identity (default
auto-detect), two-stage lifecycle: stage 1 audio + text in parallel,
stage 2 text only, once the configurable audio retention period has
elapsed (default 30 days; the transcript stays permanently). Scope as
with the media archive: 1:1 chats and groups, channels excepted. Fully
local.

The transcript travels in **two** carriers — in the `VoicePayload` of
the inline message **and** in `ContentMetadata.transcript_text` of the
`MEDIA_ANNOUNCE` frame. The second carrier is not redundant but
mandatory, because larger voice messages take the two-stage path, whose
announce frame has an empty payload and whose follow-up stage carries
pure file bytes. The transcript belongs in the **descriptor**, so it
can be shown before the download completes.

**Model and library files** (~40/75/250 MB under `~/.cleona/models/`)
are program data, not user storage, and count toward none of the
budgets from §21.3.

---

### 21.8 What a confiscator finds

Summary across all storage classes, as the counterpart to the cover
analysis in §5:

| Location | Content | Protection |
|---|---|---|
| Local profile | Chats, media, calendar, polls, contacts, **harvestable-tag set, `inbox_key`, prekey pool** | XSalsa20-Poly1305 under the seed-derived DB key (§21.4) |
| Delivery-layer share on disk | third-party cells of the subscribed tag lines | Ciphertext with no key reference; no additional layer needed. The **tag-line index** (which tag lines, real vs. decoy) lies under the device-derived index key (§4.5) — without it, the cell heaps cannot be classified |
| Durable-object class | Directory, registrations, cases, verdicts, badges | public by construction — no secret to protect |
| Media archive on the share | originals, decrypted | deliberately unencrypted (§21.6, security rule "no encryption on the share"); the share is on the user's home network |
| Own, not-yet-placed cells (outbox) | own messages including recipient | under the DB key |

Time bound for the delivery-layer share: **max. 14 days** (default TTL)
or **31 days** (management types), plus retention margin. After that,
nothing remains, not even for the device's own operator.

---

### 21.9 Open points of this chapter

| # | Topic | Status |
|---|---|---|
| **STO-4** | Interaction between delivery-status withholding ↔ read receipt. Options: couple the `read` upgrade to the same flag, or make the dependency visible in the UI | open (§21.5.5) |
| **Editorial** | §5 needs the same caveat as in §18.2 — media-archive traffic (SMB/SFTP to the NAS) is recognizable from outside and breaks the cover-uniformity commitment for the affected user | change outside this chapter (§21.6) |

---

## 22. Application Architecture

Cleona is **one** Dart/Flutter codebase across five platforms. Platform
differences are lifecycle and UI adaptations, not architecture variants.
This chapter describes the process topology (daemon/GUI), the layer
model, the module tree under `lib/core/`, the service seam `sendToUser()`
along with its outcome semantics, as well as platform lifecycles,
notifications, and the connection display.

The seam `sendToUser()` is delivery-agnostic: it hands a sealed payload
to the delivery layer and gets back one of the four states defined in
§9.1. How the payload actually reaches the recipient — the ladder
described in §7 and §8 — is none of this chapter's concern; the seam
must simply not foreclose it.

---

### 22.1 Process-Model and Filesystem Invariants

The following stipulations are properties of the process model and the
filesystem, not of the network model. They apply on every platform and
are independent of the delivery model:

- **Daemon/GUI separation** as the default topology on Linux, Windows,
  and macOS: the daemon holds the entire network and application state
  and runs persistently in the background (Linux: systemd user service
  or manual start; Windows: autostart/schtasks; macOS analogous to
  Linux). The GUI is stateless, can start and stop at any time, and is,
  to the daemon, just an IPC connection whose teardown it notices.
  Android and iOS run in-process — no separate daemon, no IPC (foreground
  service plus activity, or app process plus UI, respectively).
- **IPC transport:** Unix socket `~/.cleona/cleona.sock` on Linux/macOS,
  TCP 127.0.0.1 + auth token on Windows. Rationale: the Unix-socket
  equivalent on Win32 is not reliable enough for Cleona's use.
- **Single-instance guard, machine-global:** exactly one Cleona daemon
  per machine and OS user, independent of `--base-dir`/`--profile`. On
  startup the daemon takes flock+PID on
  `$HOME/.cleona-daemon.lock` or `%USERPROFILE%\.cleona-daemon.lock` —
  a **sibling** of the profile directory, not inside it, and deliberately
  environment-independent (not `$XDG_RUNTIME_DIR`, which is missing
  depending on the startup context and would let two starts pick
  different paths). If a live daemon holds the lock, the new process
  refuses to start. The reason for the machine-global placement: guard 0
  (PID file) and guard 1 (`cleona.lock` per `--base-dir`) are inode-based
  and sit *inside* the profile; a wipe of `~/.cleona` deletes them, and
  two daemons end up running at the same time. Both inner guards carry
  the GUI↔daemon handshake and the PID bookkeeping, but they are not the
  duplicate authority. The failure class is a filesystem property, not a
  network one.
- **`--ignore-single-instance`** bypasses the machine-global guard and is
  honored **only in beta builds**; in live/release builds the guard
  always applies. `scripts/jury-swarm.sh` uses the flag to run N daemons
  with separate `--base-dir` + `--port` on one host; any harness that uses
  the bypass must terminate all instances it started at teardown and
  leave behind a normal single-instance daemon.
- **GUI dies with the daemon** (no zombie mode): if the daemon crashes,
  the GUI closes immediately, so the app never appears "live" while the
  network is gone. This rule carries weight: the readiness state
  (§22.7) is the only health statement the GUI has, and it comes
  exclusively from the daemon.
- **Tray** (Linux GTK3+libappindicator3 via FFI, Windows Win32
  Shell_NotifyIcon via FFI), **clipboard** (wl-copy/xclip),
  **notification backends** (notify-send/D-Bus, Windows Toast, Android
  NotificationManager, UNUserNotificationCenter) — all platform-native
  integrations with no network relation.
- **SafeArea requirement** on Android: `main.dart` sets
  `SystemUiMode.edgeToEdge`, the status bar and gesture bar sit above the
  Flutter canvas; every scaffold body with its own scroll/content wraps
  `SafeArea(top: false, ...)`, otherwise the system bar covers the last
  entry. Enforced by the preflight hook.
- **i18n requirement:** every text visible in the UI exists as a key in
  all 34 locales before it is referenced in UI code (§24).
- **UI design system, navigation, skins, sorting, date separators,
  inbox tab** are specified in `docs/UI.md`.

---

### 22.2 Responsibilities of Daemon and GUI

**Daemon.** It carries:

- **Delivery node:** the delivery layer as described in §5–§9 and §11,
  and the durable-object class (§16.0).
- **Crypto:** KEM, signatures, key storage. The beta/live network-channel
  separation runs via `kNetworkChannel` in the link KDF (§11); there is
  **no packet HMAC and no network-side admission** (§20). A **network
  secret does exist and is cryptographically live**, but only on the
  binary-distribution path (§26.6): it keys the lookup tag, the encryption
  of the rendezvous records and the Nostr publishing key, and it is
  carried across a rotation with a two-generation window. It admits
  nobody to the delivery layer.
- **Persistent database:** conversations, contacts, calendar, polls.
- **IPC server** with the fields per §22.7 and §25.

**GUI.** It carries:

- Flutter rendering (Skia), IPC client, user interaction (keyboard,
  mouse, touch), display of the notifications triggered by the daemon.
- **Normative:** the GUI derives neither delivery success nor network
  health from a number the daemon supplies, nor from the mere existence
  of the IPC connection. A standing IPC connection states that the daemon
  is running — not that a send can succeed. The GUI displays the
  readiness state that the daemon maintains (§22.7).

---

### 22.3 Layer Model

```
┌─────────────────────────────────────────────────┐
│ Layer 6: Presentation (Flutter UI)               │ in the GUI process
├─────────────────────────────────────────────────┤
│ Layer 5: IPC (RPC over socket/TCP)               │ Bridge GUI ↔ daemon
├─────────────────────────────────────────────────┤  ← process boundary
│ Layer 4: Application service (CleonaService)     │ in the daemon
│   • Identity logic, groups, channels,            │
│     calendar, polls, moderation                  │
│   • sendToUser()  ← the seam                     │
├─────────────────────────────────────────────────┤
│ Layer 3: Delivery layer (§5–§9, §11)             │
│   • Durable-object class (§16.0)                 │
├─────────────────────────────────────────────────┤
│ Layer 2: Link layer                              │
│   • outbound sync connections                    │
│   • Elligator2-X25519 outside, ML-KEM-768 inside │
│   • cells, fixed 1200 B                          │
├─────────────────────────────────────────────────┤
│ Layer 1: OS network stack (UDP/TCP)              │
└─────────────────────────────────────────────────┘
```

**Mapping onto the wire format (§4.3).** Layer 3 carries the delivery
cell defined in §4.3; Layer 2 carries the **link cell**
(1200 B, indistinguishable from randomness).

**Plane D sits beside, not beneath, this stack.** Calls and direct
transfer (§17) speak their own D-frame format under `call_key` and do
not use Layer 2. Their signaling, by contrast, rides the same delivery
path as any other cell (§17.2). The application architecture
must carry this two-way split explicitly: a narrow D API alongside the
seam, no second path through the delivery layer (§17).

---

### 22.4 Module Inventory

The module tree under `lib/core/` is organized as follows. Naming
avoids vocabulary that encodes a specific storage model where a
mechanism-neutral name says the same thing (`delivery/`);
names that are already mechanism-neutral (`link/`, `tags/`, `sync/`,
`durable/`) are kept as they stand.

#### 22.4.1 Network-Layer Modules

Six modules carry the network layer. The cut follows the sections of
the network architecture, so that chapter and directory stay mappable
onto each other.

| Module | Carries | Normative Source |
|---|---|---|
| `lib/core/link/` | Outbound sync connections; Elligator2-X25519 shell outside, ML-KEM-768 inside, `link_key = KDF(kNetworkChannel ‖ x25519_ss ‖ mlkem_ss)`; cell frame fixed at 1200 B; beta/live network-channel separation; transport-parameterized connect and listen paths; per-address transport escalation own-port/UDP → own-port/TCP → 443 → ICMP, 443 bound via kernel redirect; `drawDataPort` excludes `discoveryPort` and `10080` | §4.3, §11 |
| `lib/core/delivery/` | Cell storage and eviction, as described in §9 and §20 | §5, §9, §20 |
| `delivery/` — in the tree the package `mycelium/` | The delivery layer of §7–§9 and §11: wire, parts, envelope, ladder; the readiness state machine (§22.7); **interface precedence — wired, Wi-Fi and VPN before cellular, cellular as the last choice** (§10, §22.6, §23.1), and with it the choice of which own address a card and an address record carry (§11.1, §11.9, §15.2) | §5, §6, §8, §9, §10, §11.1, §22.7, §23.1 |
| `lib/core/tags/` | Tag derivation and matching, as described in §4.3–§6 | §4.3, §5, §6 |
| `lib/core/sync/` | Delivery-layer reconciliation, as described in §5, §6, §9 and §11; budget classes as **platform tiers** (§22.6); data-saver mode; entry cascade; entry-record type — one type, used by ContactSeed hints and the sync exchange alike (E-60) | §5, §6, §9, §11, §22.6 |
| `lib/core/durable/` | **Durable-object class (§16.0):** public verifiable moderation objects (directory, registrations, cases, verdicts, badges) as anti-entropy replicated objects across relays with per-class state root; proof verification before replication; eviction by type rules; the backdating anchor reuses the cross-partition relay-attestation primitive (§13.4.2); sub-budgets per §21.3 | §16.0, §13.4.2, §21.3 |

**Why `tags/` and `sync/` are separate.** The set a node matches
incoming cells against is an **application**-level quantity: it grows
with contacts, groups, channels, and subscriptions, and is filled by
Layer 4 (§4.3, §6). Reconciliation itself is a **transport**-level
quantity (Poisson-timed, §5.2) that must know nothing of that set —
otherwise the number of contacts would become visible on the wire
profile (a core cover-uniformity property, §5). The separation is the
structural safeguard for this commitment, not a matter of taste.

**Why `durable/` is its own module and does not live in `delivery/`.**
The durable-object class has the opposite eviction rule from the
delivery layer: delivery-layer cells are evicted by TTL + per-tag-line
quota (§20); durable objects are evicted by type rules with carried
proof (§16.0). Two storage classes with opposite eviction rules in the
same module are the kind of mixing that budget errors come from.

#### 22.4.2 Device Identity

Everything that assigns and attests devices to an identity lives in its
own module:

| File | Carries | Normative Source |
|---|---|---|
| `device_delegation.dart` | Sig-subkeys of the linked devices and the delegation cert | §14.4 |
| `rotation_co_auth.dart` | Device quorum for emergency rotation, `max(2, ceil(N/2))` | §14.5 |
| `linked_device_keys.dart` / `_store.dart` | Key material of the linked devices and its storage | §14.4 |

**Normative:** the module carries a neutral, device-related name. A
directory name must not feign a layer boundary it does not have — in
particular, it must not suggest a network-side resolution of identities:
the device quorum check is receiver-side, there is neither a published
manifest record nor a resolver nor a liveness record. The directory
name is **OPEN** (§22-O-5), proposal `lib/core/device_identity/`.

#### 22.4.3 Codec Modules

| Module | Carries | Normative Source |
|---|---|---|
| `lib/core/fountain/` | Rateless erasure coding (RaptorQ/LT class) for **large objects and the binary distribution** — not for message delivery; fountain coding covers only files and updates | §9.3 (media lanes), §17.6 (stream lane), update manifest |
| zstd FFI (`compression.dart`) | Compression in the cell assembly, before sealing | §4.3 |

**Normative:** the zstd wrapper is not transport and does not live in a
transport directory. §4.3 places zstd in the cell assembly; a cell
assembly without a compression step would only surface at runtime.

#### 22.4.4 LAN Discovery and Native Send Shims

- **LAN discovery** carries step 2 of the entry cascade, as described in
  §11. The
  implementation is the neighbour call of §7.2 with a frame
  and a port of its own (§11.1); it does not reuse a generic
  LAN-discovery module — a shared frame would carry a node-ID format and
  semantics that do not match this design, even where the socket
  mechanics themselves are worth the same approach. Like the
  rest of the delivery layer the service knows **no socket**: send and
  receive are handed in, so its rules are testable without a network.
- **Native send shim** (`link_io/native_send_path.dart`): the link layer
  relies on UDP sockets; on Windows, sending runs through a native
  `sendto`/`WSASendTo` shim, because Dart's own IOCP send path **crashes
  the VM below any Dart-level try/catch** when the destination has no
  valid route — the regular case in the punch window (§17.3), not an edge
  one. This is a property of the Dart VM, not of the Cleona network
  layer. See §27.

*(E-60 decides §22-O-4 in favor of (b): the entry record is **one** type
in **one** module, used by the ContactSeed hints and the sync exchange
alike — §11.)*

#### 22.4.5 Application and Cross-Cutting Modules

Above the seam (§22.5) sit:

`lib/core/calendar/`, `lib/core/ipc/`, `lib/core/i18n/`,
`lib/core/archive/`, `lib/core/moderation/`, `lib/core/platform/`,
`lib/core/media/`, `lib/core/identity/`, `lib/core/tray/`,
`lib/core/polls/`, `lib/core/services/`, `lib/core/storage/`.

In addition, four modules with their own normative source:

| Module | Carries | Normative Source |
|---|---|---|
| `lib/core/crypto/` | KEM, signatures, key storage; the device signature sits in the sealing of the cell | §4 |
| `lib/core/calls/` | Plane D behind its own, narrow D API (§17) | §17 |
| `lib/core/channels/` | Object-space semantics of the channels and of moderation | §16 |
| `lib/core/update/` | Manifest cell and fountain blocks of the binary distribution (`update_manifest.dart`, `binary_seeder.dart`, `binary_update_manager.dart`) | update manifest (§26.6) |

**Cross-cutting files with no transport function** live outside the
network layer: `clogger.dart` (project-wide logging, the project's
most-imported file), `contact_seed.dart` (ContactSeed format, §15),
`nfc_contact_exchange.dart`, `nfc_platform_bridge.dart`,
`nfc_android.dart` (contact exchange), and `channel_uri.dart` (channel
addressing).

#### 22.4.6 Service Layer

`lib/core/service/` is Layer 4 of the model from §22.3.
`cleona_service.dart` holds the application logic (identities, groups,
channels, calendar, polls, moderation) and provides the seam
`sendToUser()` (§22.5). **Normative:** no module above the seam reaches
past the service layer into the network layer.

---

### 22.5 The Seam: Service-Layer API

**The seam is `sendToUser()`.** It is the only place where the
application layer reaches the delivery layer.

**Normative:** infrastructure sends, too — administrative messages with
no user content — run through the service API and are documented as part
of the seam. A send path that bypasses the seam can circumvent the
delivery guarantees of §7–§9 and is impermissible.

#### 22.5.1 Signature and Outcome Semantics of `sendToUser()`

```dart
// Layer 4 — application service
abstract class ICleonaService {
  /// Sends ONE sealed payload for this user. Where it exceeds a single
  /// cell it travels as split pieces under the SAME seal (§20, split
  /// bound 32 KB); a capsule-bearing first-of-day message always does
  /// (§4.3). All of the recipient's devices share the inbox_key and
  /// receive the same cells (§14.2).
  ///
  /// How the payload actually reaches the recipient is described in §7
  /// and §8 — this seam neither knows nor selects a path.
  ///
  /// The return value is the observed send state, not a delivery claim.
  Future<DeliveryState> sendToUser({
    required Uint8List userId,
    required MessageType type,
    required Uint8List payload,
    TtlClass ttl = TtlClass.standard,         // 14 d default, 31 d administrative
    Uint8List? recipientX25519PkOverride,     // non-contacts from GROUP_INVITE
    Uint8List? recipientMlKemPkOverride,
  });
}

enum DeliveryState { resting, inTransit, delivered, failed }   // §9.1
```

**Outcome semantics.** The four states and what causes each transition
are defined in §9.1; this seam does not add to them or interpret them
further. `resting` covers a payload not yet sent. `inTransit` covers
every case up to and including a message waiting in a post box for a
recipient who is offline — **that is not an error**. `failed` means no
rung of the ladder (§7, §8) carried the payload at all. `delivered` is
set only by the mandatory receipt (§9.2), which only the recipient can
produce.

The return value is an **observation, not an intent**. Neither a
socket write, nor an address, nor a counter sets a delivery state on
its own (§9).

**Media and delivery state.** The announce cell for a media message
carries the same four states as any other cell (§9.1). The running
transfer itself is a parallel `TransferPhase`
(`negotiating` → `streaming n %` | `seeding n %` → `available`), shown as
progress and never folded into the delivery state — a running stream is
not itself `resting` or `inTransit` in the message sense. `delivered`
flips only on the decoded receipt (§9.3); `failed` covers "no volunteer
and no holder accepted anything." The announce travels with
`TTL = TTL_media`, so preview and blocks die together; the state that
produces follows the four in §9.1.

**What the signature does not know.** There is no resolution of the user
into a device list and no per-device send: **one** delivery serves every
device of the recipient, because they share the `inbox_key` (§14.2).
And there is no fallback path beside the delivery layer of §7–§9 — no
separate path cascade and no default gateway.

**The TTL class belongs to the caller.** The application layer, not the
transport layer, knows what lifetime a message needs. (There is no
PoW-priced TTL — eviction is TTL + quota, §20.)

**Delivery state over IPC, normative.** `MessageStatus` is serialized
between daemon and GUI under a **stable `wireName`**, not via the
enumeration's index; the pattern in the repo is
`RotationApprovalKind.wireName` (`lib/core/ipc/service_interface.dart`).
An index-based status value silently shifts its meaning as soon as the
enumeration grows or is reordered — including the default value a
missing field falls back to. §9 carries the delivery states
themselves.

#### 22.5.2 Device Addressing

Delivery is address-free at the seam, by construction of the ladder
described in §7 and §8. It follows that:

- **Reachability** is determined by oneself (the relays and neighbours
  one has verified, §7, §8), not queried of a central authority;
  liveness is pair-wise established (§6).
- **Direct paths** between two devices run exclusively through the
  **Plane D API** (§17); live-call frames are the only direct,
  address-bearing traffic. The punch window for Plane D lives in the D
  API (§17.3).
- **Twin sync** to one's own devices runs as a delivery to one's own
  UserID (§14); all devices share the inbox and receive the same cell
  (§14.2). It is a normal `sendToUser` to one's own UserID.

**OPEN (§22-O-1):** whether, in addition, a device-addressed send is
needed to reach a single device rather than all of a user's devices at
once. Two options:
**(a)** none — Plane D has its own, narrow API
(`dLink.send(frame, session)`), twin sync runs via `sendToUser` to
one's own UserID; **(b)** a device-addressed variant, if a use case
turns up that must address a **single** device and is not Plane D. No
such case is substantiated. Recommendation: (a).

#### 22.5.3 The receive side: `Eingang`

The seam has two directions. §22.5.1 describes sending; this section
states what the application layer receives once a cell has arrived
(mechanism: §7, §8).

**Normative:** the application layer sees **no wire frame**. What a
handler receives is a service value type that the network layer fills
from the arrived cell. A handler that carries a transport type in its
signature is a seam violation of the same class as a second send path
(§22.5).

```dart
// Layer 4 — application service, receive side
class Eingang {
  final Uint8List  senderUserId;      // who, as an identity
  final Uint8List  senderDeviceId;    // which device the cell came from
  final MessageType type;             // same enumeration as sendToUser
  final Uint8List  payload;           // decompressed, decrypted, checked
  final Uint8List  messageId;
  final DateTime   angekommenUm;      // LOCAL arrival time, observed
  final DateTime?  claimedSentAt;     // sender's assertion, unverified (see below)
  final Uint8List? groupId;           // set for group/channel traffic
  final RosterVersion? rosterVersion; // membership version + roster hash (§14)
  final ContentMetadata? contentMetadata;
  final SenderTrust senderTrust;      // result of the signature check
}

enum SenderTrust { verified, unknownKey, keyChanged }
```

**What the type does NOT carry, and why.** No protocol version field, no
signature bytes, no compression method, no erasure metadata, **no sender
address and no port**. Those are network-layer concerns; they are settled
before a handler ever runs. The address is missing for a second reason
as well: the egress is address-free by construction of the delivery
layer (§7, §8); neither leg of it
exposes a sender address to the recipient (§22.5.2). Direct traffic with
addresses remains Plane D's alone (§17).

**Time is observation, not assertion.** `angekommenUm` is the local arrival
time and the only time value that display, sorting, and expiry rules may
rely on. `claimedSentAt` is a sender assertion with no evidence behind it
whatsoever — the same stance that §9 holds for the send state and §16.0
holds for durable objects ("no self-asserted date"). Anyone who sorts by
`claimedSentAt` sorts by something the sender is free to choose.

**Trust belongs in the type, not in a side channel.** Whether the
sender's signature checked out decides whether a handler may act in a
trust-elevating way — overwrite a key, auto-confirm a contact. This
information therefore travels **inside** the event, as a required field.
A handler that wants to ignore it must do so visibly.

> **Provenance of the field list.** The list is not designed but
> measured: of the fields carried by the current wire frame,
> the layer above the seam reads
> exclusively payload (100 accesses), sender UserID (85), group ID
> (24), message ID (12), message type (8), recipient UserID (6),
> timestamp (5), content metadata (4), and the membership state (5).
> Version field, signature bytes, compression, and erasure metadata are
> **never** read — that is why they do not appear above. Sender device
> ID (131 of 133 signatures) and signature-check result (118) have so
> far traveled as separate parameters alongside the frame and are
> consolidated here. Address and port occurred in 11 signatures —
> uniformly infrastructure cases that fall away with the address-free
> egress.

**OPEN (§22-O-6):** whether `rosterVersion` (membership version + roster hash) is
needed in the event. The derivation of `K_AB`, deterministic from the
roster pubkeys and rotated on membership change (§14), may already answer the question "was the sender a member at that point
in time?" without the application layer ever seeing the version. Today,
five places read it. Decision deferred to open work (Appendix C).

---

### 22.6 Platform Specifics

Per platform: topology, packaging, and the **retention tier** —
always-on full retention vs. retention-bounded. This is a **platform
property**, not a role a message declares or a sender selects.

**Linux Desktop.** Always-on full retention (§8), automatic
relay-cache contribution. Daemon
`cleona-daemon` (standalone binary built by `scripts/build-daemon.sh`
through `dart build cli`, so that the build hooks bundle the
message-store library; `dart compile exe` produces a daemon without it),
GUI `cleona`
(Flutter Linux bundle), IPC via the Unix socket, tray native via
dart:ffi → GTK3 + libappindicator3 (deliberately not the system_tray
plugin, which breaks with modern Wayland sessions), notifications via
`notify-send`/D-Bus, sounds via PipeWire (`pw-play`) with PulseAudio
fallback (`paplay`).

**Windows Desktop.** Always-on full retention (§8). Distributed via an Inno
Setup installer to `%LOCALAPPDATA%\Cleona Chat\` (no admin rights;
start-menu entry, optional desktop shortcut, optional daemon autostart
via `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`; follow-up
updates run via the in-network update path, not via a new installer
run). Daemon `cleona-daemon.exe`, GUI `cleona.exe`, IPC via TCP
127.0.0.1 + auth token, tray via Win32 FFI, toast notifications. `netsh
advfirewall` sets up an **inbound UDP rule** on first start: inbound
reachability is not a condition for one's own delivery (§22.5.2), it is
the **contribution to others** and the prerequisite for incoming calls.
The UI text states the rule exactly that way.

**macOS.** Always-on full retention (§8). Daemon + GUI analogous to Linux,
IPC via Unix socket; native libs as `.dylib` in
`Cleona.app/Contents/Frameworks/` (`scripts/build-macos-libs.sh`); build
via GitHub Actions macOS runner, DMG + notarization; tray via
NSStatusBar FFI (planned).

**Android.** Retention-bounded (§8). In-process: no separate
daemon, no IPC — foreground service plus activity. The foreground
service (persistent notification, keeps running even with the activity
closed) is the canonical background path — push-wakeup variants (FCM,
UnifiedPush, WebPush) have been architecturally reviewed and rejected
(Appendix D, D-18) — and it keeps the delivery layer's cadence alive
(§5, §8). With multiple
local identities, an arriving cell is matched to the right identity
before unsealing (mechanism: §6). Add to this the camera pipeline, incoming-call notification
(channel `cleona_calls`, `fullScreenIntent`), ringtone loop, and the
native libs (jniLibs arm64-v8a + x86_64, `scripts/build-android-libs.sh`)
— §17, §27.

**Android accepts inbound syncs. Normative, and it is a statement of
what the code does.** §31.5 K31-4 asked whether it should and pointed at
this paragraph for the answer; the paragraph was silent, so the question
looked open. It was not — it was a documentation gap, closed here
by reading the code rather than by deciding anything:

- The link layer binds a **wildcard socket per address family** on a
  fixed port and listens unconditionally —
  `link_io/udp_sockets.dart:141-146` (`RawDatagramSocket.bind`,
  `readEventsEnabled = true`, `socket.listen(...)`), driven from
  `link_io/link_host.dart:223`.
- There is **no platform branch** in that path. Across
  `delivery/`, `Platform.isAndroid`
  and `Platform.isIOS` appear exactly twice, both in
  `link/elligator_ffi.dart:145,154` to pick a library-loading path. No
  `outboundOnly` switch exists anywhere in the tree.
- The foreground service keeps the process — and therefore the bound
  socket — alive with the activity closed (Appendix D, D-18; this section).
- The two Android branches in `network/transport.dart:411,2242` are on
  the **send** side (native `sendto()` for errno visibility) and restrict
  nothing on receive.

"Retention-bounded" therefore constrains **how long a node holds** cells
and how often it checks for new ones in the background (§8) — it never
meant outbound-only. §31.2's callability row ("inbound within seconds
(foreground service)") was correct all along; what was missing was this
paragraph saying so. The remaining Android caveat is not the tier but the
network: on carrier IPv4 behind CGNAT there is nothing to be reached at,
which is a NAT property (§11) and not a platform tier.

**iOS.** Retention-bounded (§8). In-process analogous to Android. Registered
background modes: `fetch` (`BGAppRefreshTask`) carries the burst check,
`audio` carries Plane D. The cover-budget figure (~10–21 MB/d, §5.4) is,
for iOS, an **upper bound shaped by what the OS grants, not an
expectation** — a closed iOS app cannot sustain a cover stream, which
is (f) physics, not a weakness of the delivery design (§8). Static native libs,
XCFrameworks, `DynamicLibrary.process()`, deployment target 15.5, build
via GitHub Actions macOS runner (§27).

**Callability** is platform-dependent and is specified in §17.2
(foreground 1–3 s, Android/desktop background seconds, iOS with the app
closed **no** incoming calls). This is a platform boundary, not a
failure class — the application architecture must **name** it in the UI,
not paper over it.

---

### 22.7 Readiness Gates

**Normative:** gates hang off the readiness state `ready`, never off a
raw acquaintance count. The neighbour list counts acquaintances;
readiness counts **evidence** — neighbours that have answered this node
on their data address (§8.2, §11.8).

#### 22.7.1 The readiness state

The readiness state is grounded on **answering neighbours**. A neighbour
(§11.8) is *answering* when it carries a confirmation stamp from this
start or network change (§11.8) — it has answered a packet of this node
that expected an answer — and no later request to that address (§8.2,
`0x30` or `0x32`) has completed without its answer. A packet that merely
arrives, cover included, is not a confirmation: `ready` asks whether
**this** node can leave post with the neighbour, and only the outbound
direction answers that (§11.8). A neighbour that is only remembered
from the last run, or only heard calling on the local segment (§7.2 —
the call arrives from the call port, not the data port), is an
acquaintance, not evidence.

| State | Predicate | Meaning |
|---|---|---|
| `searching` | no answering neighbour | ladder steps 1 and 2 may still carry; nothing can be left in a post box; the sources of §11.8 are being tried |
| `connecting` | one answering neighbour | a post-box placement cannot reach the two acknowledgements of §8.2 |
| `ready` | two or more answering neighbours | a post-box placement can count as placed (§8.2) |

`ready` is the threshold of §8.3: redundancy lives in the post box, and
the post box needs two acknowledgements. There is no independence
criterion by network block.

**The state changes only at edges.** Up: a packet from a neighbour's
data address. Down: a request to that neighbour completes without its
answer; the neighbour leaves the list of 32 (§11.8); the network changes
(every neighbour to not-answering, followed by the single re-attempt of
§11.8). No packet is ever sent to establish readiness; it is read off
traffic that §8.2 and §11.8 already cause. Before `ready`, the app
reports **progress, not success**.

#### 22.7.2 Functional Gates

A functional gate decides behavior, not display. There is one gate; the two points after it state where no gate applies:

- **Posting to the system channels** (bug log, issue report about a
  contact, §16.7) is possible from `ready` on. UI and service layer query
  the **same** getter; two independent copies of the same gate are
  impermissible.
- **The invitation is not gated.** The card is offered in every
  readiness state, `searching` included (§12.4).
- **Re-entry:** a node without an answering neighbour arms no retry
  timer of its own; it waits for the edges of §11.8.

**Normative, on transmission.** Readiness state and node-start timestamp
are supplied identically by **both** implementations of the service
interface — the in-process service and the IPC client. A field that the
daemon maintains but that the IPC client answers with a constant value
or hard-coded `null` is a defect: the GUI would then show an unmoving
readiness, and the observable transition `searching`/`connecting` →
`ready` would get lost in exactly the layer meant to make it visible. A
latch (set once, never reset) and a live comparison are not the same
predicate; for readiness statements, the live state governs.

#### 22.7.3 Display Gates

Display gates decide presentation, not behavior. The connection
indicator is the one indicator of §12.3 and shows the readiness state;
the count of answering neighbours may appear as a secondary detail. Affected surfaces: the home-screen connection
badge, tray icon, settings, contact list, connection sheet, and the
metrics in system-channel posts. §25 carries the definition and the
tiering.

**Normative:** no display element derives deliverability from a partner
count. Only the readiness state speaks to deliverability.

#### 22.7.4 Test Gates

**Normative:** E2E tests gate on the readiness state, not on a peer
counter, direct-connection flags, or route properties. For this there is
exactly **one** helper, `waitForReady`, in `test/e2e/lib/ipc-client.ts`;
test files call it instead of running their own convergence loops. A
second, parallel convergence check in a test file is a defect in the test
base.

**Which state is the target follows from what the test needs.** `ready`
means two or more answering neighbours, and that two is the **post box**
threshold of §8.2 — three neighbours, two receipts. A test gates on
`ready` **only** where the post box is actually used: an absent
recipient, or posting into a system channel, which is the one functional
gate §22.7 hangs on readiness. Every other test gates on `connecting`:
one answering neighbour is a route, and a route is what a message to a
present contact needs. A test that demands `ready` where the norm does
not is not stricter, it is wrong — it fails on a condition the product
never states.

**The budget is five minutes, and it is §1.3's own number.** A cold start
reaches `ready` within the delivery requirement this document already
states — "within 5 minutes in exceptional situations, seconds in the
rule" — and a cold start is exactly that exceptional situation (§7.2). A
test that waits less measures its own patience; a node that needs more has
a finding, and the gate is where it must surface. A run that exceeds the
budget reports the last readiness state and the count of answering
neighbours, so the failure names its cause instead of a timeout.

---

### 22.8 Notifications, Sounds, Vibration

Incoming messages pass through five suppression layers; they are checked
in this order, and the first hit suppresses:

- **L1 — active conversation:** the chat the user currently has on screen
  (`_isAppResumed && _activeConversationId == conversationId`) triggers
  no in-app sound, no vibration, and no Android banner.
- **L2 — conversation/type setting:** `notificationsEnabled` per
  conversation, with defaults per type (direct chats: on, groups: on,
  channels: off); defaults apply to newly created conversations and are
  overridable both per conversation and as a global default per type.
- **L3 — first harvest** (see below).
- **L4 — debounce:** at most one notification every 2 s per conversation
  — protection against group burst storms.
- **L5 — Android app-resumed gate:** if the app is in the foreground
  (`_isAppResumed`), the system banner is suppressed, but not the
  in-app sound/vibration.

Below these lie the platform gates outside Cleona's control (system DND,
notification-channel settings, POST_NOTIFICATIONS on Android 13+), as
well as the rule that notifications are held back during an active call.

**L3 in detail.** Cells up to 14 days old (default TTL, §9) are the
**normal case for harvesting**, and a retention-bounded device harvests
on its cadence (§6/§8). A message's age therefore carries no suppression
rule.

**Normative:** L3 is anchored to the **first-harvest event**, not to
message age. First harvest after a cold start, or after a readiness
transition `searching`/`connecting` → `ready`: a bundled batch
notification instead of N individual sounds. Every subsequent harvest:
individual notifications, regardless of the cell's age.

**OPEN (§22-O-2):** the concrete bundling rule. Options: **(a)** one
batch notification per first harvest ("N new messages in M
conversations"); **(b)** individual notifications up to an upper bound,
bundling above it; **(c)** bundling only when the first harvest lies
further back than a duration yet to be determined. To be decided based
on measured behavior in the lab.

Ringtones (6 predefined sounds plus a custom file; the same sound pool
for call ringtone and message sounds), per-conversation settings, global
defaults, vibration (configurable per notification type), and quiet hours
(per identity, plus a master mute) belong to the notification model of
this section.

---

### 22.9 Tray and Connection Display

The tray and the GUI show **one** indicator: the readiness state of §22.7
(`searching` / `connecting` / `ready`), with a 30-s pulse freeze (a pure
UI performance measure against software-GPU drain, independent of the
network model). The count of answering neighbours may appear as a
secondary detail. There is no separate connection tier and no
reachability mark (§12.3): a tier would be a second calculation that no
user action needs, and a reachability mark read off observed addresses
says "seen from outside", not "reachable from outside" — falsely positive
behind NAT.

**Platform limit of the tray symbol (measured, owner-approved).** On Linux the tray icon carries all three states
(AppIndicator accepts a PNG icon theme). On Windows `Shell_NotifyIcon`
requires an `.ico` resource; as long as the three images ship as PNG
only, the Windows tray carries the tier as **text** (tooltip and a disabled
first menu line) and keeps one fixed symbol. This is a stated limit, not a
fallback: the readiness statement itself is present on both platforms, only
the symbol channel differs. Closing it is an asset task (three `.ico`
variants), not a protocol change — and it is under way (owner: both,
the limit stated here **and** the assets built).

**The tray text follows the language chosen in the GUI, not the system
locale** (V-10-a = b). The GUI reports its locale over
the existing IPC hello; no new round trip and no network traffic. Stated
consequence: until a GUI has connected once, the tray stands in the system
locale — on a headless server permanently. Reading the GUI's preference
file from the daemon was rejected: the path is a platform-dependent
implementation detail of the plugin.

**With several identities in one process, the tray shows the maximum plus
a count — "ready 2/3" — not the minimum** (V-10-c = b).
This section speaks of the *node*; readiness is a property of an
*identity*, and one process holds N of them at once (§14). The rule: the
word follows the **best** identity so the tray never reads "ready 0/3",
the fraction carries the truth, and the menu lists every identity with its
own state. With a single identity the display is unchanged — no "1/1", no
extra line. *The minimum was built first and is rejected on this section's
own ground: an unused or freshly created identity without partners would
hold the tray at `searching` while two of three identities deliver — the
same permanent warning in the good case that E-6 = C rejected above.
§22.7.1's "progress, not success" is untouched: it governs one identity's
path to readiness, not the summary over several.*

The readiness state is the one statement the surfaces carry:

| Surface | Display |
|---|---|
| Android foreground notification | Readiness state as the leading statement |
| Connection indicator | Readiness state (§22.7), answering neighbours as a secondary detail |
| Tray icon | ditto |
| Statistics badge | Readiness state (§25) |

**OPEN (§22-O-3):** the text of the Android foreground notification.
Boundary condition: before `ready`, the app reports **progress, not
success**. Options: **(a)** three fixed texts per state; **(b)** state
plus the number of answering neighbours; **(c)** state plus
remaining task ("looking for a second answering neighbour"). Variant (c)
best carries the progress commitment, but costs i18n effort across
34 locales.

---

### 22.10 Open Points of This Chapter

| # | Topic | Options |
|---|---|---|
| §22-O-1 | Whether a device-addressed send is needed to reach a single device (§22.5.2) | (a) none — Plane D gets its own API, twin sync runs via `sendToUser` to one's own UserID; recommended. (b) a device-addressed variant. No use case for (b) is substantiated |
| §22-O-2 | Bundling rule for the first-harvest notification (§22.8) | (a) one batch notification; (b) individual notifications up to an upper bound; (c) time-dependent. To be decided based on lab behavior |
| §22-O-3 | Text of the Android foreground notification (§22.9) | (a) three fixed texts; (b) + partner count; (c) + remaining task |
| ~~§22-O-4~~ | ~~Whether the entry cascade carries a bundled entry-record format as its own module (§22.4.4)~~ | **Decided by E-60 in favor of (b):** one entry-record type in one module, shared by ContactSeed hints and the sync exchange (§11) |
| §22-O-5 | Directory name of the device-identity module (§22.4.2) | Proposal `lib/core/device_identity/`. The name must not suggest a network-side identity resolution |
| §22-O-6 | Whether `Eingang` carries the roster version (membership version + roster hash) (§22.5.3) | (a) no — the deterministic `K_AB` derivation from the roster pubkeys already answers the membership question (§14); (b) yes, as its own field. Today, five places read it. Decision deferred to open work (Appendix C) |

---

## 23. Permissions & Privacy

Cleona follows a strict minimal-permission principle. Besides network
access, installation requires no permission. Every other permission is
requested at the exact moment the user first triggers the corresponding
feature, with an explanation of what it is for. If it is denied, the
feature turns itself off — the app does not crash and does not ask again
repeatedly.

**Structure of this chapter.** §23.1–§23.5 describe which permissions
are declared per platform, when they are requested, and what they are
for. §23.6–§23.8 describe the privacy side: what each observer actually
sees, which metadata leaks the design deliberately does **not** close,
and what commitments to the user can be derived from that. The operating
system knows nothing of this document's delivery model — the permission
list itself therefore differs little from that of any messenger; what
matters is its **rationale**, and that follows this document's delivery
model: every connection is built outbound, cells sit on responsible
relays until their TTL expires, and inbound reachability is not a
precondition for receiving (§22.5.2, §31.1).

### 23.1 Design principles

1. **Request at time of use.** Permissions are requested the first time
   the feature is triggered, not at startup. This gives the user the
   context in which the request makes sense.
2. **Graceful failure.** If denied, the feature stays silently disabled.
   No repeat dialogs, no error messages, no loss of core functionality.
3. **No surveillance permissions.** Address book, phone state, and call
   log are never requested under any circumstances; identity is purely
   cryptographic (§4.1). *(The location question is more nuanced than a
   blanket commitment could capture — see §23.5.)*
4. **Platform-native channels.** Camera and audio permissions run through
   platform-specific MethodChannels rather than generic Flutter plugins,
   so the permission's lifecycle stays precisely controllable.
5. **Cover traffic is a deliberately granted exception to "no unnecessary
   network traffic."** Cover requires Poisson-timed packets at mean rate
   `R_cover` independent of real traffic (§5.2). That is the
   protection, not waste — but it is a privacy-for-cost trade, and it
   must be disclosed: bounded by the platform tier (§22.6), only the
   user can turn it off and only with a named consequence (data-saving
   mode), cellular as the last choice when selecting an interface.

### 23.2 Android

**Declared permissions**
(`android/app/src/main/AndroidManifest.xml`):

| Permission | Type | When requested | Purpose |
|---|---|---|---|
| `INTERNET` | normal | always | **outbound** delivery-layer sync connections (§22.5.2) as well as the Plane D media path during calls (§17). An inbound-reachable port is never assumed anywhere (§31.1) |
| `ACCESS_NETWORK_STATE` | normal | always | network-change detection; additionally **connection-type detection** for the precedence rule Wi-Fi/Ethernet/VPN before cellular (§22.6) |
| `FOREGROUND_SERVICE` | normal | always | keeps the cover tick alive |
| `FOREGROUND_SERVICE_SPECIAL_USE` | normal | always | FGS type for Android 14+, subtype `persistent_p2p_messaging_daemon`; falls back to `DATA_SYNC` before API 34 |
| `FOREGROUND_SERVICE_DATA_SYNC` | normal | always | boot type before API 34 and idle type between calls |
| `FOREGROUND_SERVICE_MICROPHONE` | normal | always | runtime upgrade of the FGS during a call |
| `WAKE_LOCK` | normal | always | **burst-harvest window** (~5 min, §22.6) or a foreground streaming subscription (§6). The window serves this node's **own outbound** reconciliation, not the processing of inbound packets — retention-bounded devices accept nothing inbound |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | special | first start | shortens **harvest latency** in Deep Doze; the effect is latency, not deliverability (see below) |
| `POST_NOTIFICATIONS` | dangerous (13+) | first inbound message | message and call notifications |
| `CAMERA` | dangerous | first capture or QR scan | media capture, video calls, contact verification |
| `RECORD_AUDIO` | dangerous | first voice message or first call | voice recording, audio calls |
| `MODIFY_AUDIO_SETTINGS` | normal | always | switching the audio mode for the native OS voice session (§17.5) |
| `MANAGE_OWN_CALLS` | normal | always | registering calls with the telephony subsystem |
| `USE_FULL_SCREEN_INTENT` | normal | always | full-screen call notification on a locked device |
| `VIBRATE` | normal | always | vibration on message and call |
| `NFC` | normal | always (hardware optional) | contact pairing, peer-list reconciliation |
| `REQUEST_INSTALL_PACKAGES` | special | when triggering an in-network update | auto-installation of the downloaded APK |
| `READ_CALENDAR` / `WRITE_CALENDAR` | dangerous | only on opt-in in settings | mirroring Cleona events into the system calendar (§18.2, Android bridge) |

**Hardware feature:** `android.hardware.nfc` is declared with
`required="false"` — Cleona installs and runs on devices without NFC;
the exchange button is hidden there.

**The foreground service is the canonical background path.**
`CleonaForegroundService` starts as `specialUse` (API 34+, subtype
`persistent_p2p_messaging_daemon`) or `dataSync` (before that), and
during a call is upgraded at runtime to `dataSync|microphone` via the
3-argument form of `startForeground()`, after `RECORD_AUDIO` has been
granted; once the call ends it falls back to `dataSync`. The manifest
declares `foregroundServiceType="specialUse|microphone|dataSync"` so
that both the boot type and the runtime upgrade are permitted — a
`startForeground()` call using the 2-argument form at start would
implicitly inherit the `microphone` type and crash on freshly installed
devices where `RECORD_AUDIO` has never been granted. The notification
channel runs at `IMPORTANCE_LOW` (no sound, no vibration, no badge); the
text is updated on every state change via the `updateServiceNotification`
MethodChannel, with dedup against redundant updates. Every push variant
(FCM, UnifiedPush, WebPush, per-peer rotation) has been architecturally
reviewed and rejected (Appendix D, D-18).

**Lifecycle invariants** (Android lifecycle, not transport):

- `startForeground` is **idempotent** in `onStartCommand`: it is
  re-issued on every entry. There is no "already running" shortcut that
  could skip a required re-upgrade after an OS kill.
- `onStartCommand` swallows **no** exception and does not fall through to
  `stopSelf`: a caught error is reported via `PlatformDispatcher.onError`,
  and the service keeps running under a degraded "paused" notification
  instead of terminating. A service that kills itself from within its own
  lifecycle produces the OS restart loop.
- **Heartbeat:** the heartbeat file is deleted at service start (not
  guarded by an `isRunning` check) and stamped early. A stale heartbeat
  from a crashed earlier service process must not suppress a fresh start.
- `MainActivity.ensureForegroundService` runs in `onCreate` **and** in
  `onResume` and always calls `startForegroundService` (no
  `instance != null` guard). This is the recovery path for Android 14+
  (One UI 6.x), where the user can swipe away a `setOngoing(true)` FGS
  notification: the process and the service singleton survive, the
  notification is gone. `onStartCommand` re-issues it from the cached
  title/text pair, not from a hardcoded default text. On the Dart side,
  the last notification text sent is reset to empty on
  `AppLifecycleState.resumed`, so the next `updateServiceNotification`
  call is not filtered out by dedup.
- `runZonedGuarded` is excluded from the service path;
  `PlatformDispatcher.onError` is the **only** global error sink
  (defense-in-depth together with `FlutterError.onError`, §16.7).

**Text of the persistent notification.** The persistent notification
carries the **readiness state** `searching` / `connecting` / `ready` as
its leading statement (§22.7); partner counts appear at most as a
secondary detail, and then **split by inbound and outbound**. A peer
counter is not a readiness measure ("the counter counts acquaintances;
readiness counts evidence"). The exact wording is open (§22-O-3,
tracked in §23.9 K23-1) and must be created in all 34 locales at the
same time (§24).

**Doze and the battery exemption.** A packet for an absent recipient
waits in the post box for up to 7 days (§8.2); delivery does not
depend on continuous reachability — **Doze costs latency, not
messages.** The battery exemption shortens collection latency; that is its
only rationale, and the user-facing explanation says exactly that.
Whether the dialog for it is shown at first start is **OPEN**
(§23.9 K23-3): it would be the only permission dialog Cleona shows
unprompted at first start.

### 23.3 iOS

Usage-description strings from `ios/Runner/Info.plist`:

| Key | When requested | Purpose |
|---|---|---|
| `NSCameraUsageDescription` | first photo/video/QR | video calls, captures, contact QR |
| `NSMicrophoneUsageDescription` | first voice message / first call | voice messages, calls |
| `NSPhotoLibraryUsageDescription` | first gallery selection | sending images and videos |
| `NSPhotoLibraryAddUsageDescription` | first time saving an image | saving received images to the photo library |
| `NFCReaderUsageDescription` | first NFC contact exchange | contact exchange via NFC |
| `NSLocalNetworkUsageDescription` | first LAN discovery attempt | finding nodes on the local network (§11, entry cascade step 2). Important because LAN discovery is one of the cold-start steps |
| `NSLocationWhenInUseUsageDescription` | forced by the QR library | **not used by Cleona** — the text says so explicitly: "Cleona does not use your location. This permission is required by a third-party library used for QR code scanning." Discussed in §23.5 |

**Background execution.** No foreground-service equivalent;
BGTaskScheduler with a dual strategy of two independently registered task
types — BGAppRefreshTask (~30 s runtime) and BGProcessingTask
(minute-scale budget) — to maximize the wake frequency within Apple's
constraints. APNs has been reviewed and rejected. The consequences are
set out in §31 (Tier 5) and §17.2: the delivery **guarantee** is the same
across platforms, the delivery **moment** while the app is closed follows
Apple's policy, and **there are no inbound calls while the app is
closed** (the 120 s signaling TTL is shorter than any guaranteed
background window).

### 23.4 Desktop (Linux / Windows / macOS)

No runtime permission model. Camera and microphone access is governed by
PipeWire/PulseAudio (Linux), the Windows audio/video device APIs
(Windows), or TCC (macOS). No app permission dialogs are shown.

**External tools (Linux):**

- `wl-clipboard` / `xclip` — needed for pasting binary content from the
  clipboard (screenshots, images). Without them, only text works.
- `ffmpeg` — needed for the audio-format conversion used by voice
  transcription. Without it, voice messages still play but show no
  transcript.

**Inbound port.** A permanently open inbound port is **not** assumed
(§31.1). Port forwarding or a global IPv6 address is useful — it turns
the node into a point of contact for others and is a precondition for
**inbound calls** (§22.5.2, §17) — but it is not a condition for
delivery. Wherever a firewall explanation appears, it must be phrased
accordingly: contribution and callability, not receiving.

### 23.5 What Cleona does not request

| Permission | Why not |
|---|---|
| Address book / contacts | Contacts come via QR, NFC, ContactSeed URI, or LAN discovery. No phone number, no email address. |
| Phone state / call log | Cleona calls are pure data connections on Plane D. No interaction with the cellular network. |
| Background location | Not needed; network-change detection runs via `connectivity_plus`, not via GPS. |
| SMS / MMS | No SMS verification. Identity is cryptographic. |
| Bluetooth / BLE | Not part of the architecture: presence leak and eclipse attack. Close-range contact exchange runs via NFC. |
| Push services (FCM, APNs, UnifiedPush, WebPush) | Architecturally reviewed and rejected (Appendix D, D-18); no forced Google Play Services, no iCloud tie-in. |

**On the location permission — the exact commitment (important).** A
blanket formula like "location is never requested" would be inaccurate
toward the user. On **Android** it holds — the manifest contains no
location permission. On **iOS** it does not:
`ios/Runner/Info.plist` declares `NSLocationWhenInUseUsageDescription`,
because the QR-scan library in use forces the key. The correct
commitment therefore reads: **Cleona evaluates no location, sends no
location, and has no location-dependent function — on iOS, the system
may still ask the user for the permission because of a third-party
library.** This wording is binding; any more blanket version is not.
Preferable in the medium term: a QR library without this key (§23.9
OPEN K23-2).

### 23.6 Privacy architecture — what each observer sees

| Observer | Sees |
|---|---|
| ISP / global passive attacker | Poisson-timed packets of one size (§5.2) to changing peers. The observable graph is the **sync graph**, decoupled from the social graph |
| Network insider | Nothing pollable **about persons** — no liveness record, no state on a third party's identity, no search quantity derivable from a pubkey. **Exception, honestly:** the public object space (§16) is enumerable — role registrations, directory entries, cases, verdicts, CSAM consumption objects (the durable-object class, §16.0). It counts **pseudonyms, not persons**, and contains no addresses; the link to the main identity is published nowhere (§16.7) |
| Sync partner | Tag-line subscriptions (diluted by decoys), cell counts, possibly a live-session signal. Not: authorship, recipiency, relationships. **Two documented exceptions.** (1) Membership in **large private channels** (N > 16, §16.2.1) is mitigated against subscription-list correlation only statistically (decoys, epoch rotation), not structurally eliminated. Groups and small private channels are free of this (pairwise legs). (2) For **public channels**, the tag secret is published, making the target space enumerable — decoy dilution here works only as a factor, **not** as an anonymity set; the partner sees the candidate set of channel subscriptions |
| Malicious contact | The epoch's inbox tag line — but the KEX-Gate (§4, §10.1) means only the pair partners can compute it, and a contact *is* a pair partner; `inbox_key` is rotatable (§14.4, §15.9) |
| Delivery-layer relay | Tag (single-use, meaningless), TTL, ciphertext — no PoW field (the lever against delivery failure is redundancy, not proof-of-work) |
| Relay-cache contributor | "some node is fetching encrypted blocks" — pseudonymous |
| Confiscator | Third-party cells: ciphertext with no key reference. With an archived delivery-layer share: only undelivered cells, max. 14 days by default / 31 days for management types (§9, §21.8) |

**Plane D (calls/direct transfer).** Consented direct connections carry
their own, honestly declared metadata price:

| Observer | Sees on Plane D |
|---|---|
| ISP / passive attacker | a consented constant flow of uniform frames between two IPs for the duration of the call |
| The called/calling contact | IP address + local address candidates of the other party — "what he has, he has"; consent is revocable, an already-seen address is not |
| Media relay volunteer (opt-in) | both IPs and the call duration — the labeled price of the relay (§17.3) |
| Delivery-layer observer | nothing new — signaling rides the harvest path as an ordinary cell (§17.2) |
| Confiscator | nothing after the fact: `call_key`s are ephemeral, recorded Plane D traffic cannot be decrypted retroactively |

**Small-network honesty:** the anonymity set is the user base; in a
tiny network, no design protects against traffic analysis. The insider
properties (rows 2–6), however, hold from node 1 onward — only GPA
resistance grows with network size.

### 23.7 Residual leaks — what the design does not hide

This chapter lists the metadata leaks exhaustively and by name. **A
leak not listed here is a defect in the document, not in the system.**

| # | Leak | Against whom | Why it remains | Mitigation |
|---|---|---|---|---|
| RL-1 | **Sync graph** — who exchanges cells with whom, when, and how much | ISP, global passive observer | Without an observable channel there would be no network | **Decoupled** from the social graph (§23.6 row 1): sync partners are chosen randomly, not contacts |
| RL-2 | **Public object space is enumerable** — role registrations, directory entries, cases, verdicts, CSAM consumption objects (durable-object class, §16.0) | every network participant | Moderation without enumerable evidence cannot be audited | Counts **pseudonyms, not persons**; no addresses; the link to the main identity is published nowhere (§16.7) |
| RL-3 | **Subscription correlation in large private channels** (N > 16, §16.2.1) | sync partner | A shared channel tag needs a shared tag line | Mitigated only **statistically** (decoys, epoch rotation), not structurally eliminated. Groups and small private channels are free of this (pairwise legs) |
| RL-4 | **Candidate set in public channels** — the tag secret is published, making the target space enumerable | sync partner | Public means public | Decoys here work only as a **factor**, not as an anonymity set |
| RL-5 | **First contact** — the invitation tag family narrows down, for the issuer, which node the requester is on (§15); the invitation family reveals to every URI holder "this invitation is open" and, for as long as the acknowledgment survives, the **issuer's reachability** | invitation issuer, or any URI holder | First contact with no shared secret at all cannot be established anonymously | Subscription asymmetric and time-limited (only the scanner subscribes, only until the answer); tag derived **per invitation**, not per issuer |
| RL-6 | **Restore-Beacon** — the one-time self-publication in the recovery case (§13 stage 2) | every network participant | Without a beacon there would be no way back if every device is gone | One-time moment, not a durable state; stage 1 (own bundle) does not need it at all |
| RL-7 | **Plane D discloses IPs** — per call to the other party, and to the volunteer on relay opt-in (§23.6 second table); **for media streams (§17.6) only to the volunteer, never to the other party**. The volunteer sees both addresses, the transfer's duration and its approximate size — bounded per transfer by the relay size cap `C` (D-1) | call partner, relay volunteer | Real time without a direct connection does not exist | Consented, per-contact togglable, revocable, labeled in the UI. **Honestly:** revocation does not take back an already-seen address |
| RL-8 | **Data-saving mode makes the node distinguishable** — a reduced cover share is visible from outside (§24.4.2, §5.4) | ISP, sync partner | Whoever sends less looks different | Never automatic, only user-chosen, as a **visible state** with a named consequence. **Locked while it would weaken protection a chat relies on** (§24.4.2): the cover stream is node-wide, not per chat |
| RL-9 | **A malicious contact knows the epoch's inbox tag line** | accepted contacts | The contact must know where their cells are placed; the KEX-Gate means only the pair can compute the tag, and the contact is a pair partner | `inbox_key` is rotatable (§14.4, §15.9); the cover stream, not a prefix-shard, is the anonymity set |
| RL-10 | **Sync-graph volume is locally observable** — a node sees how many sync partners it has and the cover-stream volume; a global network-size oracle derivable from a prefix metric is retired (no prefix sharding) | every network participant | The sync graph must be observable to function | Aggregate quantity with no link to persons |
| RL-11 | **Cleona traffic classifies as "structureless" traffic** — uniformly distributed bytes, fixed cell size 1,200 B (§4.3), constant rate, no plaintext header that ties it to a known protocol | ISP, censor with an allowlist policy | Cover uniformity (§5) makes all Cleona nodes look alike **to each other**; resemblance to **someone else's** traffic is a different goal and conflicts with it | Open — the blending options are tracked as **K23-6** (§23.9). **Honestly:** indistinguishability from randomness is not protection against an allowlist policy — it is the very trait that policy flags |
| RL-12 | **An active probe confirms a node**, provided the prober holds the link key | censor with an invitation, a ContactSeed, or a cached entry record | A reachable node must answer valid handshakes | Without the link key there is no answer and no timing difference → a blind remote scan of the **handshake path** comes up empty; replaying a captured `init` is limited to the current epoch. **Scoped:** this holds for UDP entirely and for TCP connections that are not HTTP- or TLS-shaped; on TCP the bootstrap HTTP server (update manifest) answers unauthenticated (404 without server identifiers), so a scan does learn that *something* listens, but not what |
| RL-13 | **Entry nodes are enumerable** — whoever publishes itself in the entry cascade is readable, address included, by anyone who has the app (§11); the same holds for the entry records circulating in the sync exchange. A record is signed and self-certifying (§9.1, §11.1), so it is not merely readable but verifiably attributable to a node key — see B-18 | anyone who has the app — including a censor | A cold start with no discoverable entry point is impossible | Affects the **inbound-reachable** subset, not the delivery layer: outbound-only nodes issue no record. The entry cascade hands the list out on request, the entry records only to someone who syncs — a difference in cost, not in category. **Decided by E-63:** a reachable node may withhold its record and become a **private door** (§11); its address then travels only in a ContactSeed. Publishing stays the default |
| RL-14 | **Target-port allowlist** — a node listens on a random port 10000–64999 (`drawDataPort`); a network that permits only 80/443 outbound blocks sync **and** onboarding, before any form disguise applies | corporate, hotel, guest networks with a port allowlist | A full answer would need a well-known port — hence a fixed point, excluded by the no-fixed-point property (no well-known port, no designated relay). Uniformly-blocked-outbound is declared out of scope (§31.1); per-host-only-outbound would be a designated relay, likewise excluded | Mitigated, not closed (E-64): transport escalation to TCP/443 and, as a last resort, ICMP (§11); 443 doors are a property, not a role (§23.9.3) |
| RL-15 | **Escalation stage `tcpOwnPort` is visible as a deviation** — a node that falls back to TCP on its own port (§11, E-65) carries a wire profile Cleona does not control: TCP connection setup, ACK cadence, window development, retransmissions. The constant rate of equally sized cells (§5), which cover uniformity is meant to produce, then has a second pattern laid over it that does not come from Cleona's design. **Stage 3 (ICMP) carries the same class of deviation, more strongly:** a node that keeps its cell stream alive over echo/reply pairs produces an ICMP volume no ordinary client produces, and it stands out against pure background ping traffic rather than blending into it | ISP, on-path observer | Without the stage, networks that block UDP outbound but permit arbitrary TCP ports have no path at all unless the counterpart operates a 443 door (§11) | The stage is a **fallback, not a default** (§4.3): the deviation exists only where the bare UDP path already fails, i.e. exactly where the alternative is no connection rather than an inconspicuous one. It is not mitigated beyond that, and it is not claimed to be |
| RL-16 | **Captive portal — no way out at all until a human logs in.** Before the portal conditions are satisfied, the enforcement device of a hotel, airport, or guest network discards everything except traffic to the portal (RFC 8952). Every stage of §11 fails, and no port, transport or disguise changes it; the node has no outbound path even though the platform reports a connected network | operator of a guest network — not necessarily an adversary; this is the ordinary case | Cleona cannot satisfy the portal conditions: they require a human at a browser. An automated login would be credential handling for a third party's network | Not solvable, but **nameable**: `searching` carries the reason (§22.7), worded as a possibility rather than a diagnosis, because the signal cannot distinguish captivity from a hard block. Detection uses **no external contact** — an external probe URL is rejected (no-fixed-point property, and it would disclose that this device is online). RFC 8910 (portal URL via DHCP/RA) is the clean refinement and is left open |
| RL-17 | **The update fetch reveals the installed version** — a node that still lacks pieces asks an always-on holder for one object (a delta from V-1, one from V-2, or the full binary), so the holder learns how many releases behind it is (§26.6.1) | the holder asked | The fetch path may not depend on cover (§3.1), and a request that names nothing cannot be answered | Only while an update is incomplete; the holder sees the requester's address as any neighbour does, and a version lag, nothing more |
| RL-18 | **The search call names the identity sought** — the identifier travels in the clear on the local segment, and the answer tells every listener at which address that identity runs (§7.2) | every listener on the local segment | A call that finds an identity on the segment must say which one it looks for | Sent only when a send has no way (§7.2), three calls, then silence; the neighbour call carries no identity identifier and a node identifier drawn anew at every start, so ordinary neighbour finding discloses no identity |

**The KEX gate is a structural property:** whoever cannot compute a tag
never reaches the recipient (§4, §10.1, §15). There is no protocol level
at which a message from an unknown sender first arrives and is then
dropped.

**Declared crypto deviation:** the **distress call** (§13.4.3) is signed
**Ed25519-only**, even though the architecture requires hybrid signatures
for continuity documents. A classical break of this signature buys the
attacker response traffic and prekey discard, not data access — the
confidentiality of the responses rests on the KEM sealing. The PQ
commitment from §23.8 applies to this one message type in correspondingly
limited form.

### 23.8 Commitments to the user

This section is the version that may be carried over into user
communication, the threat model, and the store description. Every
commitment is backed by the passage that supports it.

**What never leaves the device:**

| Item | Cited passage |
|---|---|
| Master seed and every private key derived from it | §4.2 — keyring, `sodium_mlock`, no network path |
| Device keys (Sig and KEM) | §14.2 — generated locally, not seed-derived, no network path |
| Plaintext of messages, media, calendar, polls | §4.3 — sealed before ever leaving the process |
| Device address book, location, phone state | §23.5 — not even requested |
| Usage data, crash reports without consent, telemetry | see "no analytics" below |
| The mapping role pseudonym → main identity | §16.7 — published nowhere |

**What leaves the device — the complete list:**

| Item | Form | Who sees what |
|---|---|---|
| Cells (messages, acknowledgments, signaling, prekey refills) | tag, TTL, ciphertext — nothing else (§4.3) | every delivery-layer relay sees the three fields, no one sees the content or the parties involved |
| Cells of the cover stream, including cover cells | 1,200 B at Poisson-distributed times (§5.2), sealed pairwise — empty, or carrying one piece of the signed public update (§5.5); indistinguishable at the egress | neighbours and the ISP see volume, not a tick and not meaning |
| Public objects (§16) | Ed25519-signed under a **pseudonym** | everyone — that is their purpose (RL-2) |
| Plane D frames during calls | AES-256-GCM under `call_key`, uniform header, size classes (§17.1) | the other party knows the IP (RL-7); the ISP sees a constant flow |
| Invitations (ContactSeed) | `K_inv(i)`, `exp`, entry hints (§15) — no KEM material in the compact profile, additionally the **public** ML-KEM key `mk` in the extended profile | whoever has the URI (RL-5) |
| Restore-Beacon in the recovery case | one cell under a tag derivable from the seed (§13) | everyone, once (RL-6) |
| Update check and update pieces | a post-box query for the manifest (§26.5.4); while an update is incomplete, a request for the pieces of one object to an always-on holder (§26.6.1). Manifest hybrid-signed, assembled binary checked against its hash | the holder learns which object is requested and thereby the installed version (RL-17); no server, no fetch from a provider |

**Metadata — the four sentences that hold:**

1. **There is no flow.** Sender and recipient never form an observable
   network relationship at any point (the no-observable-flow property).
   The observable graph is the sync graph, and it is decoupled from the
   social graph (§23.6).
2. **There is nothing queryable about persons.** No liveness record, no
   directory entry, no search quantity derivable from a public key (§4,
   §10.1). What is enumerable are **objects under pseudonyms** (RL-2).
3. **Time is coarse.** A cell carries no timestamp beyond the placement
   epoch (§4.3), and the placement epoch is **24 h** (E-J) — a stored
   cell dates to a calendar day, no finer. *This is a different clock
   from the 14-day **recovery** epoch (§13.3).*
4. **What we do not hide, we say.** §23.7 is the exhaustive list; the
   "small-network honesty" from §23.6 additionally applies to every one
   of these commitments.

**Additionally:**

- **No analytics.** No telemetry, no automatic crash reporting, no usage
  tracking. Crash reports go exclusively on opt-in in the popup and into
  the structured Bug Log channel (§16.7); there is no free-text input
  there.
- **No cloud dependency.** Google Play Services are not needed, iCloud is
  not tied in. The only external dependency is the cold-start entry
  cascade (§11) — it sits **before** joining the network and is built as
  a jettisonable booster rocket.
- **The sender fetches link previews**, embedded and encrypted. The
  recipient makes **zero** network requests. SSRF hardening: DNS
  resolution is checked against private, reserved, and loopback ranges;
  the TCP socket is pinned to the validated IP; redirects are followed
  manually with a full re-check at every hop; NAT64 (`64:ff9b::/96`) and
  6to4 (`2002::/16`) are decoded and the embedded IPv4 is checked. HTTPS
  only.

**Commitments that must be explicitly explained:**

- **Updates are collected and stored automatically.** Pieces of a pending
  update are collected in the background and stored within the platform's
  budget (§22.6) before the user is asked. Nothing is installed without the
  user's click (§26.5.4, §26.6.1).
- **Offline is the normal case, not the error case.** A message to a
  powered-off device is delivered as soon as it sits on a responsible
  relay; it waits up to 14 days (§9).
- **The delivery guarantee is the same across platforms** (§31). What
  differs between platforms is latency, contribution, and callability.
- **Cleona is deniable** (§4). No recipient can prove to a third party
  that a specific person said something. This must be actively
  communicated, not silently assumed.
- **The public object space is classically secured** — no PQ protection
  for moderation objects, because ballot secrecy and PQ security are
  mutually exclusive with today's building blocks. Moderation objects
  carry an Ed25519 self-signature under a pseudonym; this too must be
  explicitly communicated.

### 23.9 Open points of this chapter

Decided numbers from this chapter have been removed — rationale in the
decision log, the ruling recorded at the respective paragraph.

| # | Point | Options |
|---|---|---|
| K23-1 | **Wording of the Android persistent notification** for `searching` / `connecting` / `ready` (= §22-O-3). The connection indicator shows the readiness state and carries the notification, tray, and badge (§22.7, §22.9) | Define the wording and create it in all 34 locales at the same time (§24) |
| K23-2 | **iOS location key forced by a third-party library.** `NSLocationWhenInUseUsageDescription` conflicts with the user commitment, even though the description text defuses it | (a) find and replace the QR library with one that lacks this key; (b) keep the key and refine the commitment as worded in §23.5 — **minimum measure, already normative**; (c) a custom QR decoder |
| K23-3 | **Placement of the battery-exemption dialog at first start** (§23.2) | (a) no dialog — Doze costs only latency; (b) move the dialog from first start into settings, with the latency rationale; (c) show the dialog at first start |
| K23-4 | **Cover traffic in the store description.** A cover rate independent of usage (12.96 MB/day, §5.6) is a cost factor under metered plans and needs explaining | (a) explain during onboarding with a reference to the data-saving mode; (b) only in settings; (c) both. The data-saving mode itself is decided, its **discoverability** is not |
| K23-6 | **Blending against an allowlist censorship policy** (RL-11, RL-13) | **Decided (E-62): (b) transport disguise.** The link layer carries a **transport selector**, so that a disguised transport can stand *alongside* the bare one — cells wrapped in a QUIC- or DTLS-shaped frame, optionally on TCP/443 with a genuine TLS 1.3 handshake (bound via the kernel redirect of §11, not a privileged process — the port dimension itself is K23-8/E-64). See §23.9.1 for the reasoning, the residual open questions, and what (b) deliberately does **not** cover |
| K23-7 | **Enumerability of the reachable set** (RL-13), split off from K23-6 because (b) does not touch it. Anyone holding the app can ask the entry cascade for the current entry addresses; the same set circulates as entry records in the sync exchange, at the cost of participating. A censor can block the enumerated set — which closes off cold start and re-entry after an address change, not the delivery layer itself | **Decided (E-63): private doors.** Accepting inbound syncs and issuing an entry record become two decisions (§11): a node may be reachable and withhold its record, its address then travelling only in a ContactSeed. Publishing stays the default. Reasoning, the two corrected intuitions, and the named goal conflict with the stable-entry-subset threshold: §23.9.2. **Rejected:** (a) accept and state it; (b) raise the query cost — cost, not category; (c) name the ContactSeed path — it points at the *same* addresses (§22.4.4: one record type for hints and exchange alike). **Not an option:** gating the lookup behind a secret — the channel constant ships in the app, and channel separation is expressly operational, not a security boundary (§11) |
| K23-8 | **Target-port allowlist** (RL-14) — a second, independent censorship type surfaced while deciding E-62: not blocking by *form* (that is K23-6) but by *port*. A network that permits only 80/443 outbound blocks the random listen port before any disguise applies. Not previously tracked | **Decided (E-64): mitigate, do not solve.** Transport escalation per address to TCP/443 (via kernel redirect, no privileged process) and, as a last resort, ICMP echo for the door-connect (§11); 443 doors are a property, not a role; the entry-record format is untouched. Reasoning and what E-64 deliberately leaves out: §23.9.3. **Rejected:** A-3 (no doors); B-2 (transport field in the entry record — would tell a censor which nodes are 443-capable); C-2/C-3 (ICMP as signal / dropping ICMP); D-1 (a LAN-uplink node subscribing on behalf of others — a designated relay, excluded by the no-fixed-point property, standing in place of the earlier "bridge" rejection). **Out of scope:** uniformly-blocked-outbound (§31.1: Cleona then unusable by definition); per-host-only-outbound (a designated relay) |

#### 23.9.1 K23-6 — reasoning for (b), and its limits (E-62)

**The problem follows from a strength.** Cover uniformity — *uniformity
instead of obfuscation* (§5) — makes every node look identical to every
other: Poisson timing at one mean rate, fixed 1,200-B cells, uniformly distributed bytes, no
plaintext header. That is what decouples the observable sync graph from
the social graph (§23.6). Against an allowlist policy — *drop everything
that cannot be matched to a known protocol* — the very same property is
the giveaway. RL-11 states it without varnish: indistinguishability from
randomness is not protection against such a policy, it is the trait the
policy flags.

**The conflict is real and is not resolved by (b), only bounded.**
Resembling *someone else's* traffic is the opposite goal to resembling
*every other Cleona node*. A node that wraps its cells in a QUIC-shaped
frame is, by that act, distinguishable from a node that does not. (b)
keeps this bounded by making the disguise an **additional** transport,
never a replacement: whoever does not need it pays nothing, and the
anonymity price is borne only where it buys reachability. This mirrors
the pattern already decided for the data-saving mode (§24.4.2): never
automatic, visible state, the consequence named.

**What is fixed now, and what is not.** Only the **transport selector**
is deadline-bound: the link layer freeze, and a place to put a second
transport cannot be retrofitted without a second wire format and a mixed
net. The disguise itself is not deadline-bound and is deliberately **not**
specified here. A disguised transport that is not maintained is worse
than none — it promises protection it does not hold once DPI rules move.
Whoever implements it commits to maintaining it.

**Open questions, to be answered before a disguise ships:**

1. ~~Who operates the server side of a genuine TLS 1.3 handshake?~~
   **Answered (E-75): nobody — the ambition is dropped.** A genuine
   handshake needs a certificate, a certificate needs a name, and a name
   is a fixed point (no-fixed-point property). A self-signed certificate
   buys almost nothing, since a DPI that inspects certificates flags it
   at once; a real CA certificate per door would not be a *network* fixed
   point — each operator has their own — but it binds a volunteer's door
   to a registered identity, which is too high a price to ask. **The
   disguise therefore imitates the shape, not the cryptography.** What
   that gives up is already declared out of scope in §23.9.3: networks
   that inspect 443 and pass only genuine TLS. Paying twice for the same
   boundary buys nothing.
2. ~~Is imitating QUIC or DTLS realistic without pulling in a library?~~
   **Answered (E-75): yes, by hand, and a library would be worse than the
   effort it saves.** Only the visible header shape is rebuilt — no real
   QUIC. Beyond binary size and foreign attack surface, a library **owns
   the connection ID**, and that is exactly the field E-69 needs: the
   condition there is that `MAC_hdr` (E-90) sits at a fixed offset and is
   verified before anything else is interpreted, and RFC 9000 §7.2 makes
   the Destination Connection ID the natural place for it. A library
   would take that away — it would undo E-69 rather than implement it.
3. Which side selects the transport, and from what signal — a failure
   counter reproduces an escalation-ladder approach already tried and
   discarded.
   **The structural half of this is settled: the transport-parameterized
   link layer (§11) is what must not be foreclosed. Narrowed since: E-64
   forecloses both record-bearing candidates (§11 — the entry record
   gains no transport field), so the mechanism is local state on the
   connecting side plus a receiver-side demultiplex that checks both MAC
   families unconditionally (E-95) — the first byte is a hint there, not a
   decision. What its L4-protocol scope is settled too (E-69): not by
   picking a side but by a **condition** — a disguise may run on UDP if
   and only if a MAC under the key already established in that direction
   (E-91) sits at a fixed offset in the disguised header and is verified
   before anything else is interpreted; otherwise it stays on TCP.
   Checked against RFC 9000 §7.2, a QUIC-shaped disguise meets this. What
   remains open under question 3 is therefore nothing about the
   selector, only the disguise itself — questions 1 and 2 above.**

**What (b) does not cover.** Option (c) — polymorphism, size and timing
variation — was **not** adopted, because it does not answer the question
asked: varying shape does not turn traffic into a *known protocol*. It
addresses traffic analysis, a different adversary, and remains available
as a separate proposal.

**RL-13 is not covered either.** Even with a perfect disguise the entry
nodes stay enumerable: the entry cascade hands its list to anyone holding
the app (§11). What is blockable there is the **enumerability**, not the
recognizability. That is a different problem from (b) and is decided
separately as **K23-7** (§23.9.2).

#### 23.9.2 K23-7 — private doors (E-63)

**Two intuitions had to be corrected before this decision held.**

*First:* an invitation does not route around a block. The entry record
is **one type**, shared by ContactSeed hints and the sync exchange
(§22.4.4). A ContactSeed therefore points at nodes that, being
inbound-reachable, publish themselves anyway. The invitation avoids
having to *ask* the entry cascade; it does not avoid the blocked
addresses. Nor is there a time window between issuing and redeeming an
invitation: the block sits on addresses, permanently, and does not care
when an invitation was written.

*Second:* a large, daily-changing set does not protect. **The censor does
not chase a moving target — he subscribes to the same feed.** The entry
cascade publishes the current list to anyone with the app; every change
reaches him at the same moment it reaches a legitimate node. The set is
also smaller than intuition suggests: an entry record is only issued by a
node that is actually reachable, which excludes every device behind
carrier NAT and every device whose process the OS suspends. *Retention-bounded does not mean
outbound-only — Android binds and listens like any other
platform (§22.6, with citations). The set is bounded by **reachability**,
not by tier: iOS with the app closed and phones on CGNAT IPv4 fall out of
it; an Android phone on Wi-Fi with a global address does not.*

**What breadth *does* buy** is collateral damage, not evasion: entry
nodes on ordinary residential lines mean that blocking them hits
residential ranges, behind CGNAT whole customer blocks. That raises the
**political** price, not the technical one. It is a real effect and
worth having — but it protects the population, not any particular person.

**Decision (E-63): private doors.** Accepting inbound syncs and issuing an
entry record become two decisions (§11). A node may be reachable and
withhold its record; its address then travels only in a ContactSeed. It
is the only mechanism that gives **one named person** a way in that no
enumeration has ever seen.

**Three normative points.**

1. **Publishing stays the default.** A network in which withholding were
   the default could not cold-start (entry cascade step 3, §11).
2. **Withholding costs the withholder nothing.** Readiness hangs on
   answering neighbours (§22.7.1), delivery runs outbound, and inbound
   reachability — the precondition for calls (§17) — is unaffected. What
   is given up is being findable by strangers.
3. **It is not a privacy setting.** Recommending it broadly would drain
   the public entry set. It is a deliberate act for the censored case.

**Named goal conflict — new, and not a defect.** The stable-entry-subset
threshold selects the **stable** subset on purpose: nodes with long
stable reachability (§11). Stability is exactly right for cold start —
and exactly what is easiest to block permanently. The two goals pull
against each other. This document names the conflict rather than
resolving it; whoever tunes the stable-entry constants should know that
raising stability lowers the censor's cost.

---

#### 23.9.3 K23-8 — target-port allowlist (E-64)

**A second censorship type, orthogonal to K23-6.** K23-6/E-62 answers
blocking by *form* (opaque bytes flagged by a DPI allowlist). While
deciding it, a second type surfaced that no residual leak tracked:
blocking by *target port*. The two share the word "allowlist" but demand
opposite answers. The random listen port (`drawDataPort`, 10000–64999)
is the **right** answer against a *blocklist* ("block port X") and is
documented as such in the code; against an *allowlist* ("only 80/443
out") the same property guarantees the wrong port.

**What E-64 fixes, and how far.** Three measured facts frame it (o2
cellular, one device; a single carrier at a single time): an
Android app **can** bind 443 despite the unprivileged-port floor;
outbound ICMP echo **carries arbitrary payload** and returns intact;
**cold inbound** to a phone dies inside the carrier — a stateful
firewall, which also explains why established-state inbound v6 works in
practice (the phone speaks outbound first). E-64 mitigates the port
allowlist with the transport escalation of §11 (own port → 443 → ICMP)
and 443 doors as a property. It does **not** claim to solve it: a full
answer needs a well-known port, hence a fixed point, which the
no-fixed-point property forbids.

**Why the residual is not a gap but a boundary.** Whenever the
escalation does not get through, the network is either **uniformly
blocked outbound** — then no node gets out, a would-be relay least of
all, and §31.1 already declares Cleona unusable there — or **blocked per
host** with only sanctioned machines allowed out, which makes the
sanctioned machine a **designated relay**: the very thing the
no-fixed-point property excludes and the project rejected as a "bridge".
There is nothing between uniform and per-host. This is why D-1 (a
LAN-uplink node subscribing to its neighbours' tag lines) is **rejected**,
not merely costly: it is a relay by another name, and it fails on its
own terms in the uniform case. The measured architectural gap behind D-1
— a node holds only its **own** tag lines, and no "subscribe on behalf
of others" mechanism exists — is therefore left open **deliberately**,
as the price of the no-fixed-point property, not as an oversight.

**What E-64 deliberately does not cover.** Networks that inspect 443 and
pass only genuine TLS: there, opaque bytes on 443 die and only the form
disguise of E-62 helps — the two decisions are complementary, port
first, form second. And it changes nothing for a censor who blocks by
enumeration (RL-13, K23-7) rather than by port or form.

---

## 24. Internationalization

Cleona speaks 34 languages, three of them right-to-left. Localization
is not part of the network layer; it lives entirely in
`lib/core/i18n/`. This chapter lays out the complete set of
specifications — structure, language list, API, enforcement — and then
names the strings that the visible states of this document require.

### 24.1 Structure of the localization system

The localization system is built entirely in Dart. There are no
platform-specific resource files — no Android `strings.xml`, no iOS
`Localizable.strings`. All translations live in a single compile-time
constant, which is what makes the instant language switch without a
restart possible in the first place.

| Specification | Content |
|---|---|
| Single source | All translations as a compile-time `const Map<String, Map<String, String>>` in `lib/core/i18n/translations.dart`. No external files, no asset loading, no build step |
| Instant switch | Language switching via `ChangeNotifier`; the entire UI updates in real time, without a restart and without rebuilding the page |
| System language | At first start, `Platform.localeName` is read and the matching language chosen automatically; English kicks in only when the system language is not supported |
| RTL first | Right-to-left is not an afterthought: the entire widget tree sits inside a `Directionality` widget that switches between `TextDirection.ltr` and `TextDirection.rtl` |
| Complete coverage | Every key carries a real string in all 34 locales (normative, detailed in §24.2) |
| API | `AppLocale.get` / `tr(key, params)` / `setLocale(code)` / `isRtl` / `textDirection` (`lib/core/i18n/app_locale.dart`, language list starting at `:16`) |
| Persistence | The chosen language is stored in `SharedPreferences` under `cleona_locale`; it is loaded at start, otherwise system-language detection runs |

**The 34 languages:**

| Group | Languages |
|---|---|
| Original 5 | German (de), English (en), Spanish (es), Hungarian (hu), Swedish (sv) |
| RTL (3) | Arabic (ar), Hebrew (he), Farsi/Persian (fa) |
| Western Europe (7) | French (fr), Italian (it), Portuguese (pt), Dutch (nl), Danish (da), Finnish (fi), Norwegian (no) |
| Eastern Europe (9) | Polish (pl), Romanian (ro), Czech (cs), Slovak (sk), Croatian (hr), Serbian (sr), Bulgarian (bg), Greek (el), Turkish (tr) |
| Slavic (2) | Ukrainian (uk), Russian (ru) |
| East Asia (3) | Chinese simplified (zh), Japanese (ja), Korean (ko) |
| South/Southeast Asia (5) | Hindi (hi), Thai (th), Vietnamese (vi), Indonesian (id), Malay (ms) |

**Key structure.** Snake_case identifiers in English that map to
locale-specific strings — buttons, labels, dialogs, error messages,
settings, notifications, moderation, channels, calls, calendar, polls,
and system messages:

```
translations['message_sent'] = {
  'de': 'Nachricht gesendet',
  'en': 'Message sent',
  'ar': 'تم إرسال الرسالة',
  'ja': 'メッセージ送信済み',
  ...  // 34 locales
};
```

**AppLocale** (`lib/core/i18n/app_locale.dart`):

```
class AppLocale extends ChangeNotifier {
  get(String key)              → translation with fallback chain
  tr(String key, Map params)   → parameterized translation ({name} → value)
  setLocale(String code)       → switch locale, persist, notify listeners
  isRtl                        → true for ar, he, fa
  textDirection                → TextDirection.rtl or .ltr
}
```

**RTL in detail.** Arabic, Hebrew, and Farsi run right to left. The
implementation uses Flutter's built-in RTL infrastructure:
`AppLocale.isRtl` returns `true` for these three, `AppLocale.textDirection`
gives the matching direction, and a `Directionality` widget wraps the
entire `MaterialApp`. Flutter then automatically mirrors navigation
arrows, inner and outer padding, text alignment, list entries, and the
alignment of message bubbles (sent = left in RTL mode, received =
right). The language selector in the app bar uses flag emoji so that it
stays recognizable regardless of reading direction.

The key set comprises around 640 keys across 34 locales.

### 24.2 Completeness requirement (normative)

**Every key carries a real string in all 34 locales before it is
referenced in UI code.** An EN fallback at the time of addition is not
permitted — the argument "`ar`, `he`, `fa` pick up `en` via the runtime
fallback chain" explicitly does not apply; every remaining gap counts as
a defect (work rule 7 in `CLAUDE.md`).

Enforcement:

- `scripts/check_i18n_complete.dart` — an exit-1 linter that reports
  every gap; runs as a pre-commit/pre-push hook and as a CI gate on every
  change to `translations.dart`.
- `scripts/preflight.sh`, invoked by the `pre-commit` hook
  (`scripts/install-hooks.sh`), blocks the commit as soon as
  `translations.dart` is staged and locales are missing (`CLAUDE.md`,
  section "Pre-Commit & Preflight").
- The fallback chain in `AppLocale.get` (current locale → `en` → `de`
  → key name as a last resort) is defense-in-depth against emergency
  omissions — a missing key after a refactor, a new key referenced
  before it is translated — and is **not** the expected path.
- For languages without native-speaker coverage, candidates are
  generated via a subagent plus a glossary and flagged in the commit
  with `uncertain:` (work rule 7).

These rules apply equally to the strings from §24.4. They are the reason
new states must be named **before** they are wired up in the UI: every
new state costs 34 translations.

### 24.3 Language in the protocol context

Language codes appear at three places in the protocol.

**Channel language — a procedural quantity.** A channel's language is
set at its creation and recorded in the directory entry; the directory
entry is a durable object (§16.0/§16.3). The report and CSAM quorums do
not scale with the subscriber count but with the **registrations for the
channel's language** (§16.4, §16.7), and jurors register per language,
because otherwise a juror would have to carry the case load of all 34
languages (§16.4). Language choice is therefore not a display property
but a procedural quantity.

**Voice transcription.** The transcription language is configurable per
identity and passed through to whisper.cpp; the default is auto-detection
(`lib/core/archive/`, §21.6).

**ContactSeed.** The ContactSeed carries no language field — contact
exchange is language-neutral. ContactSeed carries `ki`, `exp`, `cls`,
and entry hints, but no language field (§15).

### 24.4 Strings for the visible states

Five matters must be displayed and are therefore subject to the i18n
requirement of §24.2. All five are **normatively visible** — the
architecture text names them explicitly as a display requirement, not an
option.

#### 24.4.1 Readiness state (§22.7)

The three-valued state `searching` / `connecting` / `ready` is the UI's
health metaphor and appears on four surfaces: the Android foreground
notification, the connection icon, the tray icon, and the statistics
badge (§22.7).

Strings are needed for:

- the three state names themselves and their short form in the
  notification (the text is explicitly marked "to be defined" in the
  architecture document, §22.9);
- the progress before `ready` — "Before `ready`, the app reports no
  success, only progress" (§22.7);
- the explanatory dialog of the connection icon: the top tier reads, in
  substance, "contributes to the network and is callable" (§22.9);
- the peer counts split by direction — **outbound** (sync partners
  reached) and **inbound** (partners that reach this node). Each
  direction carries its own label.

On top of that come the four delivery states of §9.1: `resting`,
`in transit`, `delivered`, `failed`. None of them is presented as an
error by default — `in transit` covers an offline recipient's post
box — and the UI offers resending on `failed`; that is an additional
action label.

#### 24.4.2 Data-saving mode and its warning (§23.1, §23.7 RL-8, §31.3, §5.4)

**A chat that relies on the delivery layer's own protection is exempt,
without exception (owner decision).** The
data-saving mode must **never** reduce or disable the cover stream while
such a chat is in use — that protection holds by construction of the
delivery design (§8, §5.1
invariant 1); a switch that thins the stream would silently remove it, and that is the silent mode
switch §12 exists to prevent. **The cover stream is a node-wide stream,
not per chat** — so a node handling even one such chat keeps it in full,
and the switch is then locked with its reason named. Outside that case
the mode may act (§7.3, B-2). The mode also suspends the update fetch
path over metered connections (§26.6.1); an update then completes through
cover fill or once an unmetered connection is available.

*The rule lives in §23.1
point 5 ("only the user can turn it off and only with a named
consequence"), §23.7 RL-8 (a reduced cover share is visible from
outside) and §31.3 tier 4 (user-side and never automatic; the app may
suggest it).*

The data-saving mode is a **visible state, not a setting buried in a
submenu**, and the explanation must name the consequence. The
architecture document already prescribes the explanatory text:

> "less cover traffic — this makes your node easier to recognize
> from outside"

Needed: a state indicator, this explanatory text, the **suggestion**
text shown when a metered connection is detected (the app may suggest but
must never activate it itself, §22.6), and the confirmation. The warning
is the core of it: a silent data-saving mode would, per §22.6, be the
worst variant, because it removes the protection unnoticed. A
translation that conceals the consequence undoes exactly this rule.

**How that check is actually made — the operating rule (owner
decision).** Verifying all 34 versions
for content before they ship has no owner: the
project has no native speaker for most of the 34 locales, so that
requirement would block every release or be quietly ignored. The
operating rule instead says the same thing about the *result* and
something
buildable about the *route*:

1. **Every text is rendered in its own language.** English in a
   non-English locale is a fallback, never a shortcut.
2. Where a locale cannot be produced at all, **the English text stays** —
   visibly English, not a mistranslation.
3. Where it can be produced but the wording is uncertain, **the uncertain
   version ships**, marked `uncertain:` in the commit (work rule 7). An
   uncertain translation that names the consequence is closer to the rule
   than English that names it perfectly and is not read.
4. **A wrong or misleading wording is corrected from operation**, through
   the bug-log system channel (§16.7) — that is the reporting path this
   architecture already has, and it reaches native speakers who actually
   use the locale.

The substantive requirement is unchanged and is not weakened by this: a
text that conceals the consequence is a defect, and it is to be reported
and fixed like any other. What changes is that the check is a **standing
process**, not a release gate that nobody could pass.

#### 24.4.3 Transition state during device lock-out (§14.4, §14.6)

A device lock does not take effect immediately, but per contact — namely
as soon as that contact has received the announcement (§14.6). The
transition "belongs in the UI, not in a footnote" (§14.6), with the
prescribed pattern:

> "Device locked — fully in effect once all contacts are informed
> (3 of 47 still open)"

This is a **parameterized** string (`AppLocale.tr` with two counters),
not a fixed one. In addition, a label and an explanation are needed for
the end of the transition: the old range closes once all contacts have
acknowledged it, at the latest after 14 days (§14.6); whoever still
writes to the old address after that sees a delivery receipt that never
arrives and can resend (§14.6) — this too needs a text, because
otherwise the case looks like a silent loss.

#### 24.4.4 Invitation classes (§15)

An invitation's commitment hangs on the channel, not the format, and
"the UI must name the consequence" (§15). The ContactSeed carries a
visible field `cls` for this (§15).

Strings needed:

- the class names and their commitment from the normative table in
  §15 — **handed over confidentially** (the symmetric component holds
  against a relay archivist with a CRQC) and **published** (it does not
  hold; PQ confidentiality only via the ML-KEM material in the seed);
- the user-level label **passed on** for a ContactSeed URI sent via a
  third-party channel (§15);
- the channel matrix from §15, which "belongs in the UI exactly as is":
  **five** rows, each with one commitment, including the explicitly
  declared row with no PQ commitment (a printed or published QR code).
  §15.5 carries five rows, and the fifth is the one that matters most — it
  separates a QR code held out to someone from one that is printed, and
  only the latter carries no PQ commitment at all;
- the note on the one-time nature of QR invitations (§15) and the
  confirmation of automatic acceptance for NFC and QR scan (§15).

#### 24.4.5 Per-transfer media consent (§9.3, §12)

*§9.3 and §12 require this text
normatively — "an explicit consent **naming the
linkability**" / "**naming the downgrade** for **this** transfer" — and
it is bound to the i18n requirement of §24.2 like every other string in
this section.*

A chat that relies on the delivery layer's own protection but cannot
carry a file on the cell path (§9.4) must ask before
using a media lane, and the dialog must name what changes. Prescribed
core, in this order:

- that the choice applies to **this one file** and the chat keeps its
  usual protection afterwards — a remembered blanket consent is the silent mode
  switch §12 exists to prevent;
- that the transfer is **an event visible from outside**: it does not
  ride the cover stream, so start, end, rate and approximate size are
  visible at both egresses (B-29);
- that **one holding relay sees both ends** of the same transfer tag —
  the uploader and the downloader (B-29). This is the linkability §9.3
  requires to be named, and it is *stronger* than an ordinary message's linkability (§7),
  where no single relay sees both ends;
- that the object **stays with strangers for up to `TTL_media`** until
  the recipient collects it;
- in a group, that the holders additionally see **which members
  collect** (B-29);
- what remains protected: the **content stays sealed**, and the
  recipient does not learn the sender's address.

Two constraints on the wording, both load-bearing:

1. **The wording must not borrow the name of a stronger guarantee.** A
   file never travels the way an ordinary message does (§7); it takes a
   media lane, and B-29 grades those guarantees **weaker or equal** to
   an ordinary message's. Borrowing that name for it promises a
   protection the lane does not provide.
2. **The claim "post-quantum" may not appear** until the built pairwise
   path actually carries it (B-29). "Encrypted" is
   the defensible word.

A duration may be shown for such a chat, and **only the sender's
upload share** (owner decision): whether the recipient is online is
not knowable at send time, so no end-to-end estimate can be honest. The
figure depends on `R_bulk`, which is unmeasured — see §9.4.

A translation that omits the consequence is a defect, not a stylistic
choice, exactly as in §24.4.2.

### 24.5 Procedure

The strings from §24.4 are created in the work package that brings the
IPC/UI/statistics contracts up to date (Appendix C), because that is
where the corresponding states arrive in the UI. The linter from §24.2
applies from the first commit that introduces a new key — there is no
transition period and no EN preliminary stage.

### OPEN

| # | Point | Options |
|---|---|---|
| I-1 | The notification and tray text for the three readiness states is marked "text to be defined" in §22.9. The icon question is **decided** (one indicator, the readiness state, carries the notification/tray/badge — §22.9, K23-1). | Open is the **key set for the translation**: create texts for `searching`/`connecting`/`ready` (= §22-O-3) in 34 locales at the same time (§24) |
| I-2 | Three labels for invitation channels stand side by side: §15 normatively knows two classes (**handed over confidentially** / **published**); the user-level table in §15 names three (**confidential** / **passed on** / **published**). | (a) three UI labels, where "passed on" is a subform of "published" with the same commitment; (b) two UI labels, with "passed on" only as a description of the route. The number of classes determines how many commitment texts per locale are needed |
| I-3 | Whether a channel's language choice under §24.3 can be changed after the fact. It is set at creation and is, via the registrations, the reference denominator for the report and CSAM quorums (§16.4, §16.7). | (a) immutable after creation — quorum denominator stable; (b) changeable with recalculation — the directory entry is a durable object and thus updatable (§16.0). §16 makes no statement on this |

---

## 25. Network Statistics

Cleona maintains its own scrollable statistics page, reachable from
Settings and from the peer badge in the AppBar. It fulfills the project's
transparency claim: the user sees in real time how the delivery layer
stands and what their own node contributes to it. The page updates itself
automatically every 5 s; all labels are localized into 34 languages
(§24).

The dashboard's metric basis is **cells, tag lines, sync partners, and
the readiness state**. The data model and collection logic live in
`lib/core/network/network_stats.dart` and
`lib/ui/screens/network_stats_screen.dart`.

---

### 25.1 Delivery-Plane / D-Plane Separation

> **Plane note.** Metrics on the **delivery layer** are anonymous and
> relationship-free: cells, tag lines, sync partners. They **never**
> carry a contact reference — there is none, and establishing one would
> be a breach of the KEX-Gate (§4, §10.1). Metrics on **Plane D** (calls,
> direct transfer, §17) are IP-based and relationship-bearing; they exist
> only during a consented session and are kept **separate and labeled**
> in the dashboard (§25.9).

---

### 25.2 Design Principles

1. **Full transparency.** The user sees what their node does: how much it
   holds for others, with whom it reconciles, how high its cover share
   is. No hidden activity.
2. **Readiness, not acquaintance.** The lead metric is the three-valued
   readiness state `searching`/`connecting`/`ready` (§22.7) — not a number
   with thresholds. §22.7 states the rule this chapter implements: *"The
   counter counts acquaintances; readiness counts evidence."* The health
   badge mirrors the state **1:1** and applies no threshold logic of its
   own.
3. **Privacy-preserving metrics.** All values are computed locally from
   the node's own observations, stored only locally, **never** aggregated
   network-wide, never sent to other nodes, never to an external service.
   No telemetry endpoint, no analytics backend, no "help us improve"
   toggle. *(The cover stream runs on its own Poisson clock, §5.2; the
   dashboard generates no outbound traffic at all — see §25.10.)*
4. **Show nothing that is not substantiated.** A metric that suggests an
   assurance without substantiating it is not displayed. This is the
   dashboard rendition of the no-observation-as-claim rule (§9, §22.5.1).
   Concretely: no "connected" that follows from a socket write; no
   "healthy" that follows from an acquaintance count.

---

### 25.3 Measurement Basics

Two measurement definitions apply to the whole dashboard and are not
reset at any individual display point:

- **Profile data on disk.** The "Profile data on disk" field measures the
  sum of the `.enc` and `.json` files in the profile directory.
- **Tag-line occupancy chart.** The chart's capacity comes from the
  platform tier (§22.6), not from a display constant.

The metrics themselves are defined in the following sections:

| Section | Content |
|---|---|
| §25.4 | Readiness and delivery layer — readiness state, sync partners, latencies, sync-graph volume, connection type, data-saving mode |
| §25.5 | Own traffic — bytes, cover and payload share, cells, reconciliations, quota utilization, cells placed |
| §25.6 | Delivery-layer contribution — tag-line subscriptions, tag-line occupancy, cells held, storage occupancy, evictions, harvest hit rate |
| §25.7 | Sync partners — per-partner row format and aggregates |
| §25.8 | Durable-object class — class occupancy, sub-budgets, overflow display, class state, and verification state |
| §25.9 | Plane D diagnostics — NAT type, public address, port mapping, callability, active D-sessions |

---

### 25.4 Section 1 — Readiness and Delivery Layer

This section answers the dashboard's lead question: is the node
deliverable, and how does the delivery layer around it stand?

| Metric | Source | Description |
|---|---|---|
| **Readiness state** | Readiness state machine (§22.7) | `searching` / `connecting` / `ready`. Lead metric of the dashboard |
| **Answering neighbours** | §22.7.1, §11.8 | Neighbours that have answered, on their data address, a packet of this node that expected an answer, since start or the last network change (confirmation stamp). `ready` hinges on this number (≥ 2) |
| **Family-diversity indicator** | §11 (dual-stack) | dual-stack only: the share of syncs over the weaker address family (sliding window). Below **25 %** the active countermeasure runs (raising to 2 partners per family) and is shown here. **Shown with its cause:** the same value arises from drifting partner choice and from neighbours with no inbound capacity left, and the countermeasure only helps against the first. The dashboard must therefore state whether cross-family attempts are failing for lack of remote capacity — otherwise it reports drift and the operator looks in the wrong place |
| **Settling time, installation → `ready`** | §22.7 | "the only settling time the system has; it is to be measured and reported" |
| **Time in current readiness state** | State machine | makes getting stuck in `connecting` immediately visible |
| **Delivery latency** | §9 | `in transit` → `delivered`, measured on the node's own sends. §7 and §8 give the expected values |
| **Sync-graph volume** | §23.7 (RL-10) | locally observable (how many neighbours, cover-stream volume). **No global network-size estimate** — a size oracle derivable from a prefix metric is retired (no prefix sharding, RL-10) |
| **Connection type** | §22.6, §11 | WLAN / Ethernet / VPN / cellular. Cellular as the last choice is normative; the user should see which link is currently carrying traffic |
| **Data-saving mode** | §22.6, §5.4 | active/inactive. §22.6 demands **visible state**, not a hidden setting, along with a named consequence |
| Uptime, status | Daemon | time since daemon start; whether the daemon is running |

**Health badge.** The badge mirrors the readiness state **1:1** and
applies no threshold logic of its own:

| Readiness | Badge |
|---|---|
| `ready` | green |
| `connecting` | yellow |
| `searching` | red |

A threshold on an acquaintance count does not carry weight here: §22.7
notes that many sync partners in the same island are not deliverable.
Deliverability follows from evidence, not from count.

---

### 25.5 Section 2 — Own Traffic

This section states what the node itself sends and receives — split by
payload and cover share, and set against the platform tier's quota.

| Metric | Description |
|---|---|
| Bytes sent / received (total) | lifetime volume at the link layer |
| Bytes sent / received (today) | daily volume at the link layer |
| **Cover share** | the share of cover cells in the sent cell stream. §5: *"The cover share dominates by design — that is the protection, not waste."* The dashboard must therefore label it **as a protection measure**, not as overhead |
| **Payload share** | the counterpart; together 100 % of the cell stream |
| **Cells per reconciliation tick** | a constant number per tick (§5). If the observed value deviates from the quota, either the saving mode is active or a budget is exhausted — both are to be made visible |
| **Reconciliations today** | always-on tier: cover tick; retention-bounded tier: burst ~5 min or streaming subscription in the foreground (§22.6). Makes platform throttling visible |
| **Quota utilization** | consumed daily volume against the platform tier's upper bound (§22.6). *"Quotas are upper bounds, not targets"* — the display must not suggest a fill bar meant to be filled up |
| **Application cells sent / received** | one logical send operation, as described in §7 and §8 |
| **Wire cells sent / received** | wire level. On the wire there are **only** cells (§4.3). Bytes are measured at the link layer (after fragmentation, before decryption); cells at the application layer (one logical send operation, regardless of how many wire cells it becomes; the split pieces of one seal count once, and `SendOutcome.pieces` reports their number separately) |
| Chat messages sent / received | a genuine subset of the sent cells |

**Control traffic.** Control traffic is link handshakes, tag-line-list
reconciliation, delivery acknowledgments (§9), durable-object class-state
reconciliation (§16.0), and cover cells. The chat counters set themselves
apart from this: they count exclusively user messages.

---

### 25.6 Section 3 — Delivery-Layer Contribution

This section shows what the node holds for others — held storage only,
not traffic passed through in transit (mechanism: §7, §8). The
contribution this section accounts for is **held storage**: cells on
tag lines and durable objects (§16.0). A relay may count pass-through
traffic as a local diagnostic, but that is not a storage-contribution
metric.

| Metric | Description |
|---|---|
| **Tag-line subscriptions** | the number of subscribed tag lines, composed as described in §6, **plus** one subscription per subscribed channel (§16) |
| **Display rule (normative)** | Real and decoy tag lines are **not shown separately**. The decoys exist precisely so the real subscriptions disappear into the list (§6); a statistic that tells them apart cancels the protection against anyone who looks at the screen — including a screenshot in a bug report |
| **Tag-line occupancy** | bar chart: cells held per subscribed tag line against the per-tag-line quota (§20). The capacity comes from the platform tier (§22.6), **not** from a display constant (§25.3) |
| **Cells held (total)** | cells this node holds for others — the actual contribution |
| **Delivery-layer storage occupancy** | bytes, broken down by: inbox tag lines / decoy tag lines / channel tag lines / fountain-erasure cache / durable-object class / profile data (§21) |
| **Evictions** | cells that yielded due to per-tag-line quota overflow (§20), and cells that expired via TTL. Two separate numbers — the first is a capacity signal, the second is normal operation. **Normative:** the overflow number is reported **per tag-line class**. A management-class overflow means setup is being lost; inside a combined counter it would hide behind the default class, which overflows continuously in normal operation (§20) |
| **Fountain-erasure cache (always-on tier)** | fountain/erasure blocks held for large payloads and the binary distribution, and their volume (§9.3 bulk lane; AP-7 fountain for files/updates) |
| **Harvest hit rate** | the share of checked tags that matched against the harvestable-tag set, per reconciliation. It is the only metric that measures the **effectiveness** of harvesting; if it falls to 0 while readiness reports `ready`, either the tag derivation or the epoch window is wrong — exactly the failure class that otherwise hides as a silent outage |
| Profile data on disk | the sum of the `.enc` and `.json` files in the profile directory (§25.3) |

**On the harvest hit rate, normative.** It is kept **exclusively locally**
and is not observable from the outside: matching happens locally (§6),
and the rate of delivery-layer reconciliation is constant and
independent of the hit (§5). The metric must therefore never trigger a
send reaction — no "sync more often at a low rate". That would be exactly
demand-driven behavior whose very occurrence is information (§19: no
polling).

**OPEN (§25-O-1):** The denominator of the rate in streaming subscription
mode. In burst mode it is well-defined (tags checked per burst); in
streaming subscription mode the partner streams entire tag lines (§6),
and the denominator grows with the tag-line volume rather than with the
node's own interest. Options: **(a)** report the rate only in burst mode,
"running" in streaming mode; **(b)** separate rates per mode; **(c)**
normalize the denominator to a fixed time window.

---

### 25.7 Section 4 — Sync Partners

This section lists the partners the node reconciles with.

**Row format per sync partner:**

```
Partner:        7af3…2c8e            (shortened partner identifier)
Direction:      outbound             (outbound / inbound / both)
Address family: IPv6                 (§11 — tracked per family)
Independent:    yes                  (§22.7, as far as locally ascertainable)
Last reconciliation: 8 s ago
Acknowledgments: received 142 / issued 138
Cells:          out 1,204 / in 1,190
```

**What this row deliberately omits and must not be added:** no contact
reference, no route, no cost, no NAT type, no `isDirect`. A sync partner
is **not** a contact, and establishing the connection between the two
would be the linkage the KEX-Gate excludes (§4, §10.1).

**Aggregates of the section:** verified partners outbound / inbound, of
which independent, distribution by address family, acknowledgment rate
(issued / received), partner turnover per period.

**Connection sheet (recovery actions).** A sheet can be opened from the
partner list. It shows readiness progress and, on request, manually
triggers the entry cascade (cached entry addresses → LAN discovery,
§11). A rescue bundle is a set of entry records in the one format
(E-60, §22.4.4).

---

### 25.8 Section 5 — Durable-Object Class

§16.0 explicitly requires that an overflowing sub-budget becomes
**visible** here. This section exists to redeem exactly that commitment.

| Metric | Description |
|---|---|
| **Class occupancy, total** | against the target size (durable-object budget, §21.3) |
| **Sub-budget: directory + registrations** | occupied / 6 MB |
| **Sub-budget: verdict and deadline-bound types** | occupied / 2 MB (cases, votes, tombstones, badges, CSAM) |
| **Sub-budget: rolling** | occupied / 2 MB (dedup counters, Feature Request votes) |
| **Overflow display (normative)** | Per sub-budget: whether it was trimmed, how many objects, and the **first-acceptance day of the newest objects still held**. §16.0 trims "newest first, ascending by first-acceptance day" — the user must see from which age onward their state was cut off. Without this number the overflow is visible but not interpretable |
| **Objects by type** | directory entries, role registrations, open cases, votes, tombstones, badges, CSAM objects, crash fingerprints, Feature Requests |
| **Per-class index** | number of entries and bytes (§16.0) |
| **Partition share** | full objects held for the node's own partition |
| **Class state (per-class state root)** | §16.0: the per-class state root, anti-entropy replicated across relays. The comparison state is displayed, **not** the hash |
| **Verification state** | "complete" (the root matches with ≥ 2 independent relays in different partitions, §13.4.2/§16.0) / "diverging" / **"verification state unknown"** before the first successful reconciliation with ≥ 2 independent relays. The third state is normative (§16.0): it prevents a node from showing "no badge" where it actually means "I don't know" |

**Retention-bounded devices show this section differently.** They do
not hold the class in full; instead they retrieve directory and badge
objects on demand (§16.0). For them there are
no sub-budget bars and no partition share; what is displayed is
verification state, class state, and the number of objects held locally.

---

### 25.9 Plane D Diagnostics *(separate and labeled)*

Five metrics concern exclusively Plane D — calls and direct transfer:
NAT type, public address, public port, UPnP/PCP status, and router
info. They appear in their own, clearly labeled block:

> **Only for calls and direct transfer.** These values do not concern
> message delivery — that runs outbound and needs no inbound
> reachability (§22.5.2).
>
> **They do, however, concern the node's contribution to others.** The
> public address is what a node needs in order to publish a usable entry
> record under §11.3 ("every externally reachable node publishes"). A
> node that does not know its external address publishes its private one,
> and the cold-start board fills with records nobody can dial. Learning
> the address (§17.3, "observed address" instead of STUN) therefore
> serves two consumers: the address candidates of a call, and the entry
> record of the cascade. Neither is a condition for one's own delivery —
> both are the "contribution to others" named in §22.6.

| Metric | Role |
|---|---|
| NAT type, public address | address candidates and punch window (§17.3) |
| UPnP/PCP status, router info | port mapping for inbound calls |
| Callability | derived from inbound reachability (§22.5.2) and the matrix from §17.2 — on iOS with the app closed, normatively "no" |
| active D-sessions | number and duration, during a call |

The **callability assistant** walks the user through port mapping and
router settings as a UI workflow when inbound reachability is missing.
**Normative:** it carries no statement about message delivery — that runs
outbound (§22.5.2). Its text exists in 34 locales, like all the rest
(§24).

**The connection indicator is not defined here.** It shows the readiness
state of §22.7, with the number of answering neighbours as a secondary
detail — **§22.9**. This chapter supplies the indicator only its input
value; it does not fix the indicator itself.

The **peer badge in the AppBar** is the entry point into the dashboard
and shows the readiness state.

---

### 25.10 Collection

A `NetworkStatsCollector` in the daemon collects all values; the UI
retrieves them via the IPC command `get_network_stats`. The sources:

| Metric group | Source |
|---|---|
| Cells out/in, split by payload and cover | link layer |
| Cells sent / received / forwarded | application-level cell counters |
| Delivery latency (`in transit` → `delivered`) | latency measurement of the node's own send path (§9) |
| Tag-line subscription state, readiness state | sync module and readiness state machine (§11, §22.7) |
| Delivery-layer storage occupancy per tag-line class and durable-object class | cell and durable-object storage (§21, §16.0) |
| Class state (per-class state root) and verification state | `durable/` (§16.0) |

**Counter persistence** across daemon restarts: the counters are written
to disk periodically.

**Privacy. Normative:** the dashboard generates **zero** network traffic;
all values come from the cover-stream reconciliation that happens anyway.
This also makes opening the statistics page unobservable from the outside
— under rate-constant reconciliation it is not observable anyway.

**What the dashboard never does:** reconcile metrics with other nodes,
send them to an external service, attach them to a bug report without
the user having seen the content first (§16.7: preview dialog and
consent). The diagnostic snapshots `LogReport`, `ContactIssueReport`, and
`CrashReport` carry the same metrics and are fed from **one** serialization
point; multiple independent points with the same field set are
impermissible.

---

### 25.11 Open points of this chapter

Decided numbers of this chapter have been removed — rationale in the
decision log, the ruling at the respective paragraph.

| # | Topic | Options |
|---|---|---|
| §25-O-1 | Denominator of the harvest hit rate in streaming subscription mode (§25.6) | (a) report only in burst mode; (b) separate rates per mode; (c) normalize to a time window |
| §25-O-2 | Whether the cover share is shown as a **number** or only as a category | A precise percentage is a self-declaration about the node's own cover strength. It is local and harmless, but travels into bug reports via screenshots. Options: (a) exact number; (b) tiers ("high / reduced"); (c) exact number only while saving mode is active, otherwise a tier |
| §25-O-3 | Which history is kept as a time series (§25.4) | (a) readiness state over time; (b) verified partners outbound/inbound; (c) both overlaid. Length and resolution: 720 entries |
| §25-O-4 | Target-value display of platform-tier utilization (§25.5) | §22.6 says "upper bounds, not targets" — a fill bar suggests the opposite. Options: (a) bar with a warning threshold; (b) plain number; (c) bar only upon reaching the limit |
| §25-O-6 | i18n scope | This chapter's metric set is to be fully carried over into `stats_*` keys before the IPC/UI work package (Appendix C) and created in **all 34 locales** (work rule #7, `dart scripts/check_i18n_complete.dart`). The scope is to be quantified beforehand |

---

## 26. License & Funding

This chapter presents the license model, publishing infrastructure,
trademark protection, funding sources, and donation banner in full.
Two decisions shape it technically:

1. **The update transport runs over the fountain-erasure cache.** The
   manifest is signed, and the binaries travel as fountain blocks over
   the fountain-erasure cache held by the always-on tier (E-40, §26.6.1).
2. **The maintainer key carries signatures exclusively.** It signs the
   update manifest and controls no network access; the donation targets
   carry their own key pair (§26.7).

The in-app update path is fully specified: signed manifest, fetching the
binaries from the network's own fountain-erasure cache, verification
against hash and signature, automatic installation once verification
passes (§26.6.1).

### 26.1 Source-available model

The source code is publicly viewable on GitHub — for transparency,
security review, and trust. The project's own license is not an OSS
license; it permits reading and studying the source code, reviewing the
cryptographic implementation, filing bug reports and feature requests,
and building from source for personal use.

### 26.2 Publishing infrastructure

Three directories separate working state, secrets, and publication:

| Directory | Purpose | In git | Public |
|---|---|---|---|
| `Cleona/` | full development environment (code, tests, VM scripts, internal docs) | yes (local) | no |
| `CleonaPrivat/` | keys, credentials, internal docs | no | never |
| `CleonaGit/` | scrubbed staging area for GitHub (source code + public docs + releases) | yes (pushed) | yes |

**The five-script pipeline is the only path to GitHub**
(`docs/PUBLISHING.md`, Work Rule 9 in `CLAUDE.md`):

1. `sync-to-git.sh` — copies scrubbed source code from `Cleona/` to
   `CleonaGit/`, allowlist-based with default-deny and tripwire security
   checks.
2. `dry-run-cleonagit-push.sh` — validates the push against a local bare
   mirror (six invariants: auto-commit, tag target, asset filter,
   `.md` allowlist, secret patterns, PEM header) and fails closed.
3. `approve-cleonagit-push.sh` — requires the interactive human approval
   `JA-PUSH`.
4. `push-cleonagit.sh` — pushes code and tag to GitHub, but does not
   create a release.
5. `release-build.sh` — orchestrates all platform builds in parallel
   (Apple CI and Windows RDP first, then Android and Linux locally),
   signs the update manifest, seeds the in-network update, creates the
   GitHub release with all artifacts, and publishes the project website
   via SFTP.

**Neutralizing the commit date:** All commits pushed to GitHub carry a
fixed neutral date (`2026-01-01T12:00:00+00:00`) so the development
timeline cannot be read off. The server-side push timestamps are
unavoidable and are accepted as they are.

**Published** are the source code (`lib/`, `proto/`, `assets/`), the
public architecture document, the security whitepaper, the user manual
in 34 languages, the scrubbed changelog, and the signed release
artifacts together with `SHA256SUMS`. **Not published** are private
keys, the test infrastructure (`test/`, `scripts/vm/`), internal
documents (`CLAUDE.md`, `HANDOVER.md`, `BUGFIX_*.md`), internal tooling
(`init_profile.dart`), debug builds, and VM credentials.

**Reproducible builds.** Every user can build from the published source
code and compare the unsigned result against the official binary. The
Ed25519 release signature is a separate step from this — it establishes
authenticity, not integrity; the private maintainer key is never needed
for verification. There is no constant that escapes publication: a
self-built binary can take part in the delivery layer (§26.5.1), and
reviewers can test their own build against the running network.

**Distribution channels for first installation are external:** GitHub
Releases (Linux tar.gz/AppImage/deb/rpm, Windows Inno Setup installer +
ZIP, Android APK, macOS DMG), Apple TestFlight (iOS, uploaded from the
Apple CI via Fastlane), Google Play (maintainer-signed APK), the
project website. F-Droid is excluded (it requires an OSS license).
Linux packaging via `scripts/build-linux-packages.sh` produces an
AppImage (universal, no installation), a `.deb` (Debian/Ubuntu/Mint), and
an `.rpm` (Fedora/openSUSE/RHEL), all installing to `/opt/cleona/` with
a wrapper at `/usr/bin/cleona-chat` and a `.desktop` entry.

**The website does not belong in this chapter.** `cleona.org` is its own
sub-project (a separate repository). Here it is named exclusively
as a distribution channel; its architecture, its tech stack, and its
deployment live there and are not mirrored into this document.

### 26.3 Name & trademark protection

The name "Cleona Chat" and the logo are trademark-protected, separately
from the source-code license. Anyone who releases a modified version
into the world — even in violation of the license — must not carry the
name and the logo. The license (§26.1) and the trademark (§26.3) are the
legal fork barrier; there is no network-side one (§26.5.1).

### 26.4 Funding sources

- **GitHub Sponsors** — direct funding on the project page.
- **Open Collective** — transparent donation management, all finances
  publicly viewable.
- **Liberapay** — recurring donations with no platform commission.
- **Cryptocurrencies** — Bitcoin, Monero planned, for donations with
  privacy in mind.

### 26.5 In-app donation banner

**Placement and behavior.** A small, unobtrusive inline card with
friendly text and a "Donate" button, exclusively at the top of the chat
list (the conversation overview). Never inside an active conversation,
never while writing or reading.

**Design principles.** Never a popup, modal, or full-screen overlay —
always an inline element. No guilt-tripping, no dark patterns, only a
positive, grateful tone. Rotating texts keep the banner fresh (example:
"Cleona has no advertising and no investors. Your support keeps it
running.").

**Donation paths.** SEPA transfer with an EPC QR code (standard
EPC069-12) for a one-tap transfer from the banking app; IBAN, BIC,
recipient, and institution are each shown with their own copy button.
Bitcoin with a QR code; Monero planned for users who prefer maximum
privacy. Also planned are one-time donations with preset amounts (3 €,
5 €, 10 €, 25 €) plus a custom-amount field, and recurring monthly
donations via the supported platforms.

#### 26.5.1 Fork protection

The **sole technical barrier** against a fork with redirected donations
is the in-app signature check on the donation targets: the IBAN and the
BTC address are Ed25519-signed, the corresponding public key is embedded
in the build, and the app verifies the signature via
`SodiumFFI.verifyEd25519()` (libsodium `crypto_sign_verify_detached`)
before it displays an address. The donation configuration — address
plus Base64 signature — lives in `lib/ui/screens/donation_screen.dart`.
The key pair is its **own** Ed25519 pair, kept permanently offline,
separate from the update key (E-43, §26.7).

**Normative:** The check is **not optional**, and a negative result
**hides the address**, instead of merely placing a warning next to it.
With a valid signature, the UI shows a trust indicator (green
checkmark); without a valid signature, there is no displayable address.

There is no network-side barrier: there is no packet HMAC and no
admission filter, every build can take part in the delivery layer (§20,
§10). A network secret exists, but it admits no one — it keys the
binary-distribution path only (§26.6). Legally, the license (§26.1) and
the trademark (§26.3) carry the load.

**Residual risk:** Anyone shipping their own build can swap out the
donation addresses and the embedded pubkey together. The signature
check protects the user of an **official** binary; it cannot detect a
fully replaced build. What works against this are reproducible builds
(§26.2) plus the license and the trademark.

#### 26.5.2 Code signing

Three mechanisms with separate roles:

1. **Android APK signing** — RSA-2048 keystore (`key.properties`), release
   signing config in `build.gradle.kts`; a prerequisite for Play Store
   distribution.
2. **Linux release signing** — `scripts/sign-release.sh` produces a
   tarball + SHA-256 checksum + GPG signature, so users can verify before
   installing.
3. **Signed update manifest** — `lib/core/update/update_manifest.dart`,
   signed via `scripts/sign-update-manifest.sh`, checked in `UpdateChecker`
   against the embedded maintainer pubkey. **The manifest is
   hybrid-signed.** E-15 removes ML-DSA from message cells, but
   explicitly names where it stays: "everywhere third parties must verify
   years later — DeviceDelegationCert, **update manifest**, key-rotation
   continuity proofs, identity anchors" (§4). An update manifest is
   exactly this case: it must still be verifiable when a node catches up
   after months of offline time, and a manifest that could be forged
   retroactively would be full access to every installation.

The fields `minRequiredVersion` and `minRequiredReason` carry the
hard-block enforcement (§26.5.4).

#### 26.5.3 Android flavors beta/live

Beta and live are installable in parallel: `chat.cleona.cleona` ("Cleona
Chat", standard icon) versus `chat.cleona.cleona.beta` ("Cleona Beta",
icon with a red BETA banner), separate data directories
(`/data/data/<package>/`), separate identities, separate contacts, no
shared state — both can run at the same time. Network-channel detection
runs on Android at runtime from the package name
(`AppPaths.packageName`: `.beta` suffix → beta network channel,
otherwise live), on desktop via `--dart-define=NETWORK_CHANNEL`;
convention "beta always `--debug`, live never `--debug`".

**The network-channel separation lives in the link-handshake KDF.** The
public constant `kNetworkChannel` (`cleona-beta` / `cleona-live`) feeds
into the KDF of the link handshake; a beta node and a live node derive
different link keys, and the handshake fails **before a single cell
flows** (§4). The link handshake is the Elligator2-based handshake
(`cleona_link/`, §22.4.1).

The network-channel separation is **not a security boundary**: the
constant is public and known to every observer (§4). It separates
operational networks, not trust domains.

The network-channel tag `c=b` / `c=l` in the ContactSeed carries the
same separation into contact exchange, including an immediate error
message when scanning, pasting, or receiving via NFC a seed from a
foreign channel — before a contact request is even sent. URIs without a
`c=` parameter are accepted as compatible.

#### 26.5.4 Hard-block update enforcement

**Purpose.** If a release introduces a non-backward-compatible change
(say, a change to the HKDF salt in the per-message KEM), older clients
would silently lose messages because updated peers no longer accept
their wire format. The hard block prevents exactly this silent failure.

The mechanism: `minRequiredVersion` (semver) blocks older clients,
`minRequiredReason` supplies the i18n key for the rationale in all 34
locales (§24); `UpdateChecker.isHardBlocked()` compares versions at
startup, and `UpdateRequiredScreen` then runs as the start route ahead
of the normal app shell, showing a title, the translated rationale, and
the side path "Open anyway (restricted)". The update banner appears
globally via `AppBarScaffold` — on every screen, not just the home
screen — **only once the update is fully assembled and verified**
(§26.6.1), with the version number, an **Install** button, and
session-scoped dismissal. Clicking **Install** starts the installation,
with no second confirmation step; Android additionally shows the system
installer dialog. While a hard-blocked node is still assembling,
`UpdateRequiredScreen` shows the assembly state instead of a button.

Reduced mode (`CleonaService._reducedMode`) gates sending (text, media,
editing, deleting, reactions, calendar, polls) and the receiving of
user messages (a silent drop at frame dispatch), leaves existing
conversations readable and scrollable, keeps settings accessible
(identity export, profile view), keeps network participation up — so a
later switch back to normal operation needs no cold start — and
permanently shows a red banner at the top of the home screen. It is
deliberately **not persistent**: every restart re-evaluates the manifest
and, if applicable, shows the lock screen again, so no one forgets they
are in restricted mode. The hard block applies process-wide across all
identities; multi-identity offers no way around it.

**Play Store installations are exempt.** An APK installed via the Store
carries a different signing key than a sideloaded one (Play App Signing
versus the maintainer key), and Android enforces signature equality
across updates — without an uninstall, there is no update path between
the two routes. The app therefore determines its installation source at
first launch (`PackageManager.getInstallSourceInfo()`;
`com.android.vending` → Play Store, anything else → sideload), stores it
immutably in the encrypted database, and from then on shows only the
matching update path: Store users are updated via the Store, sideload
users via the in-network update (§26.6.1).

**Manifest freshness.** The manifest sits in the post box (§8.2) under a
fixed public identifier derived from the network channel (beta and live
never share it). A node asks for it at the moments it asks the post box
anyway — at start, when the network changes, when the user opens the
application — and additionally when a new neighbour appears. Never on a
timer. A node holding a verified manifest newer than the one it is handed,
or hearing "nothing here", places its own copy there. Collecting the
manifest does not delete it (§8.2): it is a public object, and deletion on
collection exists to protect private post. Every node asks the
same question, so the question distinguishes no one.

**Accepted cost:** a node that runs for weeks without a restart, a network
change, an opened application or a new neighbour learns of an update late.
No time commitment is given for that case or for the worst-case
network-split window — **OPEN L-2**.

**No return path for the user.** Cleona does not offer a downgrade to an
older version, for three reasons: (1) database migrations run only
forward — an older binary cannot read the tables of a newer release;
(2) the protocol keeps evolving cryptographically, and a rolled-back
binary would silently drop messages from peers that are already updated;
(3) the monotonic sequence number in the signed manifest (§26.6.1)
prevents downgrade attacks, and a user rollback would have to get around
that gate. Instead of a rollback, a critical bug gets a hotfix version
through the same path. The internal `.bak` backup on desktop (automatic
recovery if the app crashes within 30 s of an update) is a safety net,
not a user feature.

### 26.6 Censorship-resistant software distribution

Distribution initially depends entirely on external gatekeepers —
GitHub Releases, Google Play, the App Store, the website — each of
which is individually censorable. This section describes how an
already-installed Cleona network updates itself and admits new users
through existing users. Six principles apply:

1. **No single gatekeeper.** Every distribution stage has at least two
   independent channels.
2. **Person-to-person trust.** The inviter is the trust anchor — no
   store, no label, no certificate.
3. **Tiered model.** Convenient channels (stores, GitHub) are the
   primary path, decentralized channels are the fallback. Not an
   either/or.
4. **Honesty about bootstrapping.** The very first installation always
   needs an external touchpoint. It can be made as decentralized and
   redundant as possible, but not abolished.
5. **The bootstrap is a jump start, not permanent infrastructure.** In
   the early phase, the bootstrap node carries a disproportionate load
   (full binaries for every platform, the primary source). Once enough
   nodes hold enough material, it can hand off this role or be shut down
   entirely. The architecture must never assume it as a permanent
   dependency.
6. **Explicit approval.** An update never arises automatically from the
   development process, but exclusively from a manually signed manifest.
   Development and test states stay on the local or beta network.

The last point is anchored in the pipeline: `release-build.sh` runs only
after the interactively approved push (step 3, §26.2).

#### 26.6.1 In-network updates via the fountain-erasure cache (E-40)

**Decided (E-40):** The manifest is hybrid-signed (§4), the binaries
travel as fountain blocks over the fountain-erasure cache (§9, AP-7
fountain for files/updates), and the manifest is harvested rather than
queried.

Procedure:

1. The maintainer signs the manifest with a hybrid signature (§26.5.2).
2. The binary is encoded per platform into fountain blocks (block size =
   one cell payload, ≈ 1.1 KB) and placed into the delivery layer. **Any**
   ~k·(1+ε) distinct blocks reconstruct the whole; no block is special,
   and no coordination is needed (§9).
3. The carrier is the **always-on tier** (§22.6): desktop installations
   acting as an automatic cache class with their own fountain-erasure
   cache. A cache sees only "interest in blob hash X" — not who is
   downloading (§9).
4. The node learns of the manifest via the fetch path (§26.5.4) and
   starts collecting what it needs — the delta matching its
   installed version, or the full binary (§26.6.2) — automatically, from
   cover fill (§5.5) and the fetch path, within its tier's budget (§22.6).
   Nothing is shown yet and no user action is needed.
5. Once all pieces are present, the node reconstructs and checks the
   SHA-256 and the hybrid manifest signature. Only then does the banner
   appear (§26.5.4).
6. The user clicks **Install**; installation starts — Android via the
   system package installer (OS dialog), desktop with a backup of the
   running binary and a restart. This flow is a critical
   user path and must not be changed (memory reference
   `project_android_update_flow_v145.md`).

**A newer manifest while collecting.** The node switches to the newest
target at once; pieces that do not serve it are discarded. An outdated
version is never offered.

**Decisions about the fetch path:**

- One tag per platform; the blocks sit as cells in the fountain-erasure
  cache (§9).
- **The fetch path.** Always-on nodes hold the pieces of every current
  object in their bulk cache (§21.2). A node that still lacks pieces asks
  a holder for pieces of its object at the moments of §26.5.4. Within one
  such moment the next request follows the arrival of the previous answer;
  after three answers without a new piece the node turns to the next
  holder, and after the last holder it waits for the next moment — never
  on a timer. A request names the object, never individual pieces. This path
  does not depend on the cover stream (§3.1).
- **What the holder learns.** The object names the installed version (a
  delta from V-1, one from V-2, or the full binary): RL-17 (§23.7).
- **Data-saving mode** suspends the fetch path over metered connections;
  pieces arriving by cover fill are still kept (§24.4.2).
- Rateless: no fixed block count, no index allocation (§9).
- Storage budgets follow the platform tiers from §22.6: retention-bounded
  (Android/iOS) versus always-on (desktop, "automatic fountain-erasure
  cache").
- Old blocks clear themselves via the cells' TTL plus per-tag-line
  quota eviction (§20, §21), once no one is holding them anymore. (There
  is no PoW-weighted eviction `pow/(byte × remaining TTL)` —
  there is no PoW at all, §10/§20; eviction is TTL + quota.)
- The bootstrap node is a jump start (Principle 5 in §26.6) and has no
  special role in the protocol.

**Push over cover fill (in addition to the harvest).** The same blocks also travel
as **cover fill** (§5.5): a node with blocks on hand puts one into a cover packet
the Poisson clock has already drawn, to whichever neighbour that draw selects. This
costs nothing — the packet is emitted either way — and it **pre-warms** the
neighbourhood before anybody asks. The fetch path above stays the authoritative
one: push is best-effort, carries no guarantee, and stopping cover in a test build
must leave the update intact (§3.1). Push makes fetching cheaper; it does not replace it.

**Why fountain blocks.** Fountain blocks have no indices that would need
to be allocated — any ~k·(1+ε) blocks are enough, so distribution needs
no coordination. No single block is identifiable in a way that would let
an observer infer, from its possession, who holds what. Per-head costs
fall with 1/N (§9).

**Protection mechanisms of the approval model:**

| Protection | Effect |
|---|---|
| Manifest signature (maintainer key) | Without a valid signature every node ignores the manifest — development builds do not trigger an update |
| Monotonic sequence number `minMonotoneSeq` | Every release increases the number; nodes reject manifests whose number is equal to or lower than the highest one already seen. Prevents downgrade via replayed old but validly signed manifests |
| Beta/live network-channel separation | Different link keys and different tag derivation — beta updates do not reach the live network (§4) |
| Windows code-integrity gate | Before the build on the Windows machine: `git fetch --tags`, a hard checkout of the release tag, comparing `git rev-parse HEAD` against the tag SHA — on mismatch, a hard abort, no continuing with just a warning |
| Self-healing on failed verification | On a hash or signature error, the entire version state (all blocks plus the reconstructed binary) is discarded and re-fetched, so a poisoned block cannot permanently block the update; transient errors (too few blocks available) delete nothing, the partial state stays in place for resumption |
| Pipeline approval gate | Manifest signing and seeding run as steps of `release-build.sh`, which starts only after the interactive approval |

**No numbers are fixed here.** The fountain calculation in §9 works
with a 150 MB example (≈ 135,000 blocks; at 10,000 nodes and a redundancy
of 5, each holds ~80 KB). That is an example, not a fixed operating
point — block count, redundancy, and cache budget depend on actual
operation and are to be measured, not set (**OPEN L-3**).

macOS and iOS are exempt from in-network distribution (DMG via GitHub
Release, TestFlight); `shouldUseInNetworkUpdate()` returns `false`
there.

#### 26.6.2 Delta updates

Full binaries are expensive over cellular, a delta transfers only the
change. Mechanism: bsdiff/bspatch, two generations (V-1 → V and V-2 → V),
fallback to the full binary when no matching path exists (say, because a
node was offline for more than two releases). The expected savings are
above 90 % — typically a few MB instead of several dozen MB.

The manifest names every delta together with its **content hash and
length**, per platform and per source version; without both, a node can
neither derive the delta's key nor tell when it is complete (§5.5). A
delta is simply a smaller object on the same path as the full binary.

**Which object a node collects** follows only from its installed version
and the newest manifest: V-1 or V-2 → the matching delta, anything older →
the full binary. The choice is local and asks no one.

**Release pacing.** In practice cover fill carries deltas: a full binary
exceeds what a retention-bounded node stores and takes far longer than a
release cycle at the cover rate (§5.2). A node more than two releases
behind therefore depends on the fetch path (§26.6.1). The interval between
two releases should not undercut the measured time a delta needs to spread
through the network; that value comes from simulation (§28, Z-8/Z-9), not
from a number fixed here.

#### 26.6.3 Invitation link for first installation

An existing user generates a link that contains everything a new user
needs — network access, source, verification. The link is an ordinary
HTTP link, so it opens in any browser on any device; a custom URI scheme
would presuppose an already-installed app (chicken-and-egg). The
parameters travel in the hash fragment and are therefore never sent to
the server:

| Parameter | Content | Purpose |
|---|---|---|
| `s` | ContactSeed (Base64) | the inviter becomes the new user's first contact (§15) |
| `h` | SHA-256 hashes per platform (JSON map, Base64) | the new user can verify the downloaded binary |
| `m` | Maintainer signatures per platform (JSON map, Base64) | each signature covers the raw 32-byte SHA-256 hash of the respective platform — the same signatures as in the manifest |
| `v` | Version number | platform detection and version mapping |
| `f` | Fallback URL (optional) | GitHub Release or similar as an external fallback |
| `z` | Binary sizes per platform (Base64 JSON) | see below |

No TLS: nodes have no domain and therefore no certificate; self-signed
certificates produce browser warnings that are worse than plain HTTP.
Integrity is secured by the SHA-256 hash in the link, authenticity by the
maintainer signature — transport authenticity would be redundant. That
the link discloses the inviter's address is known and is mitigated:
rotating addresses, the option to point at a different node as the
source (the `s=` parameter is independent of the source), and, for
high-threat situations, the physical path (§26.6.6).

Normative:

- `z=` carries the platform-specific binary sizes from the signed
  manifest, so the browser assembler trims the block padding correctly; a
  manipulated size leads to a SHA-256 failure and thus rejection. The
  parameter is optional when evaluating — links without it still work.
- **Demand-driven foreign-platform fetch**: a node keeps only its own
  platform on hand; if a visitor requests another one, the node fetches
  it from the network, checks it against the manifest, and serves it.
  Without this path, an invitation across platforms (say, Android
  invites, Linux visits) would fall through to the external fallback —
  landing exactly in the gatekeeper §26.6 is trying to avoid. It is
  triggered by an **unauthenticated** HTTP request from anyone who can
  reach the port; in terms of content this is harmless, because every
  byte is checked against the maintainer-signed hash. What is at stake is
  bandwidth and disk, and these are deliberately **limited rather than
  switchable** — a limit that always applies is worth more than a switch
  nobody finds, and a path that can be switched off would be a second
  behavior that has to be maintained and tested. The limits: a platform
  whitelist instead of path interpolation, only complete binaries, one
  fetch at a time per node with a 10-minute lock after a failure, one
  foreign binary at a time with a 24-hour TTL, exclusion from the budget
  exception via the `.ondemand` marker (otherwise a single visitor could
  permanently blow out a user's storage budget), no network-wide
  advertising (otherwise the node would advertise itself for 24 hours as
  a source for a platform it does not even run), strict separation from
  the installation path (an Android APK is a ZIP and would otherwise land
  in the desktop installer). Implementation:
  `lib/core/update/foreign_binary_acquirer.dart`, backed by
  `test/smoke/smoke_foreign_binary_acquire.dart`.

**Address question of the link.** The link must name its source without
presupposing a fixed address: reachability is a transient property and
not a role (§11), and the ContactSeed carries entry hints instead of
fixed addresses (§15). How the link represents this is yet to be decided
— **OPEN L-4**.

#### 26.6.4 Binary rendezvous via the entry cascade

Node addresses change (typically daily) and an invitation link cannot
carry a fixed IP. This design does **not** use an external rendezvous service
*for this* — the entry cascade (§11) is the mechanism that resolves a
ContactSeed's entry hints to live, directly-reachable nodes. *This
section decides how an invitation resolves, not
how a cold node enters the network — the cold start keeps an external
source as one of four (§11.8); the two are separate questions.* A publishing
node that holds a complete binary set is reachable through the same entry
cascade the inviter's `s=` ContactSeed encodes; the browser assembler
(§26.6.5) walks the entry hints, contacting directly-reachable nodes in
turn until one serves the matching platform.

**Who holds binaries:** only directly reachable nodes — a public IPv4
address (directly or through port forwarding) and global IPv6, yes; nodes with no inbound
reachability, no, because a fetch from them would never come together.
LAN nodes are found via LAN discovery, not via the entry cascade.

> **This design uses no external rendezvous channel such as Nostr
> here.** The entry cascade (§11) is the mechanism instead
> — consistent with the removal of Nostr from entry-node enumeration
> (RL-13, §23.7). The binary-rendezvous design therefore has no external
> service at all; the only external touchpoint that remains is the
> invitation link itself, which is carried out-of-band by the inviter.

**OPEN L-5 — invitation-related entry records.** Whether there is,
alongside the platform-related availability, an invitation-related
record category is undecided. Such a record would need its decryption
key delivered to it, and the invitation link (§26.6.3), with
`s`/`h`/`m`/`v`/`f`, carries no key field. A publish that nobody reads
violates Work Rule 5 (no unnecessary network traffic): the category must
therefore either be fully specified or dropped.

#### 26.6.5 Embedded HTTP server and browser assembler

Every node brings a minimal HTTP server that serves the bootstrap web
app (~200–400 KB of static HTML+JS, part of the Cleona binary) and binary
data — with no external hosting. It answers exclusively GET on fixed
paths under `/cleona`; no dynamic processing, no upload, no directory
listing, no server identifiers, and a generic 404 for everything else.
This is not camouflage — a determined censor can recognize the protocol —
but it keeps automatic scanners away. The model is protocol detection at
the first byte of a TCP connection (`GET`/`HEAD` → HTTP, `0x16 0x03` →
TLS) and the shared port number for UDP and TCP. This same first-byte
demultiplexing is where a TCP/443 door (§11, E-64) and, later, the form
disguise (§23.9.1, E-62) attach — no new wire format is introduced.

**Browser-blocked ports (E-64).** Two constraints, and the second is the
one that matters.

*The draw.* `drawDataPort` excludes **10080** — the only browser-blocked
port inside 10000–64999. The exclusion costs one value out of 55,000,
exactly like the existing `discoveryPort` exclusion.

*The link.* The invitation link does **not** carry the drawn port. It
carries `publicPort`: either a port the router chose when mapping via
UPnP-IGD, or one a translating NAT assigned and STUN observed. Neither
is constrained by the draw, and both can be any value in 1–65535. The
link is therefore issued **only** if `publicPort` is not a blocked port,
checked against the full list — and if it is, no link is issued at all.
A missing invitation beats a dead one: the dead link fails locally in
the recipient's browser, before a packet leaves their machine, so the
issuing node sees no request, logs no error, and goes on looking healthy
while none of its invitations can be redeemed. The `f=` fallback does
not rescue that case — it travels in the hash fragment of the very URL
the browser refuses to open.

*The list is a union.* Chromium (`net/base/port_util.cc`,
`kRestrictedPorts`) and Firefox (`netwerk/base/nsIOService.cpp`,
`gBadPortList`) do not agree: Firefox additionally blocks 4190 and 6679,
Chromium additionally 0 — 83 values together. A link has to open in the
recipient's browser, whichever that is, so the union binds. 10080 is the
Amanda backup port, blocked by both since 2021, and the only member at or
above 10000 — which is why the draw needs one value and the link needs
all 83.

The flow in the browser: the visitor opens the invitation link, receives
the web app from the node, which reads the parameters out of the hash
fragment, detects the visitor's platform, walks the entry hints from the
ContactSeed to further nodes with the matching binary, downloads, checks
the SHA-256 against the hash from the link, checks the maintainer
signature (libsodium.js), and only then offers the file for saving.
Fallback chain: complete binary from the originating node → further nodes
from the entry cascade → external fallback via `f=`.

**Trust model, honestly separated.** *Binary integrity* is strong: the
hash and the signature travel over a different channel than the binary
(the link arrives by message, email, or word of mouth), and even a
manipulated assembler cannot forge the maintainer signature. *Assembler
integrity* is weak: the HTML+JS arrives over unauthenticated HTTP, and an
attacker in the network path could swap it out and remove the check.
That is the real attack surface, and it is not Cleona-specific — every
software download over HTTP has it. Mitigations: the assembler is
deliberately small (~50 KB of source) and readable in the browser's
developer tools; the hash in the link allows verification outside the
browser (`sha256sum` against the hash from the link); fetches from
multiple independent nodes make a single-point manipulation
insufficient. HTTPS is not a way out: nodes have no domain, public CAs
validate based on domains, there are no IP certificates — and a
certificate would be revocable under legal pressure, which the integrity
commitment must not depend on. SFTP or FTPS do not help either, because
the browser does not speak them and every transport-authenticating
procedure again requires a pre-shared trust anchor. Anyone facing a
severe threat situation takes the physical path (§26.6.6) or gets the
binary directly from a known contact.

Two boundary conditions apply: modern browsers warn on, or block,
executable downloads over plain HTTP — the user may have to explicitly
confirm, or use the download address with `wget`/`curl`; verification is
independent of the transport path. And iOS cannot install a downloaded
app; the web app detects iOS and points to the App Store.

**The browser assembler checks fountain decoding and the hybrid manifest
signature.** Whether serving whole binaries suffices for this path — in
which case the browser needs no decoder — is part of **OPEN L-4**.

#### 26.6.6 Physical handover

The last-resort fallback for environments in which network-based
distribution is compromised or unavailable — not censorable except by
seizure:

| Procedure | Platforms | Mechanism |
|---|---|---|
| USB file transfer | Android, Linux, Windows, macOS | copy the APK/binary onto the device, sideload or run it |
| System share sheet | Android | the app hands its own installed APK to the system share sheet; the transfer itself (Quick Share, Bluetooth) is the operating system's |
| Bluetooth | Android, Linux, Windows | OBEX File Push |
| Local WLAN (HTTP) | all | the sender's node serves the binary via the HTTP server from §26.6.5 on its LAN address |

AirDrop is excluded (Apple-proprietary, and iOS does not allow sideloading
anyway). Verification is via a SHA-256 comparison against a separately
transmitted hash.

NFC is not a path for the binary: a tag holds a few kilobytes, and NFC
carries only the contact card (§15). Android Beam, the one NFC-initiated
file transfer Android had, negotiated over NFC but moved the bytes over
Bluetooth or Wi-Fi Direct; it was deprecated in Android 10 and removed in
Android 14.

**No downstream network criterion.** Verification ends at the SHA-256
comparison and the manifest signature. There is no membership criterion
that would afterward stop a forged binary from joining the network:
every build joins (§20). Anyone accepting a binary via a physical path
verifies it themselves — otherwise no one does.

#### 26.6.7 Multi-stage fallback (overview)

| Stage | Channel | Censorable by | Purpose |
|---|---|---|---|
| 1 | Google Play / App Store | Apple or Google alone | First installation, convenient |
| 2 | GitHub Releases | Microsoft / DMCA | First installation, sideload |
| 3 | Invitation link + entry cascade + HTTP download from a node | only if **all** directly reachable nodes are blocked | First installation, decentralized |
| 4 | physical (USB / share sheet / Bluetooth / LAN WLAN) | not censorable except by seizure | First installation, last-resort fallback |
| 5 | In-network update via the **fountain-erasure cache** | not censorable as long as a sync partner is reachable | Updates for existing users |
| 6 | In-network delta update | not censorable | Updates, bandwidth-saving |

In stages 5 and 6, the delivery layer carries the load; the condition
follows the readiness state from §22.7.

**Never dependent on outsiders again after installation** — §26.6.1
carries this claim: the fountain-erasure cache needs no reachability of
the sender and no coordination. The external channels 1–4 are needed
only for first installation, and none of them is indispensable.

#### 26.6.8 Implementation map

The distribution path consists of these building blocks:

| Building block | Role |
|---|---|
| `UpdateManifest` (`lib/core/update/update_manifest.dart`), `UpdateChecker`, `scripts/sign-update-manifest.sh` | signed version manifest with a hybrid signature (§26.5.2); the fields `dhtBinaryTag`/`deltaBinaryTag` name the tags of the full binary and the delta, plus `minMonotoneSeq`, `binaryHashes`, `binarySignatures`, `binarySizes` |
| `BinaryUpdateManager`, `DeltaUpdateManager` (`lib/core/update/`) | state machine of the update fetch: check, download, assemble, verify, clean up, or find and apply the delta path (bsdiff/bspatch, fallback to the full binary) |
| Fountain content layer | encoding and fetching of the binary blocks via the fountain-erasure cache (§9) |
| `BinaryFetchClient`, `BinaryHttpServer`, `BootstrapWebApp` (`lib/core/update/`) | HTTP path for first installation and foreign-platform fetch; the assembler decodes fountain blocks (§26.6.5) |
| `InviteLink`, `InviteLinkService`, `InstallSourceDetector` (`lib/core/update/`) | generate and evaluate the invitation link, choose the update path by installation source; link format open (§26.6.3, OPEN L-4) |
| `PhysicalTransferHelper` (`lib/core/update/physical_transfer_helper.dart`) | export/import and verification for physical handover (§26.6.6) |
| `BinaryRendezvousManager`, entry-cascade resolver (`lib/core/network/`) | binary rendezvous via the entry cascade (§11, §26.6.4) — resolves ContactSeed entry hints to live reachable nodes |
| `CleonaService` (`lib/core/service/cleona_service.dart`) | orchestration: trigger the update, provide its own binary, build the availability record |

### 26.7 The maintainer key

The maintainer key carries signatures exclusively. There are two
signatures, and they sit on two separate key pairs:

| Task | Key |
|---|---|
| Signature of the update manifest | maintainer key, hybrid-signed (§26.5.2) |
| Signature of the donation targets | its own Ed25519 pair, kept permanently offline (colder than the update key, which is needed at every release), a second pubkey in the build (E-43, §26.5.1) |

The separation of roles limits any compromise to a single capability, and
fits the threshold roadmap (below).

The network secret of the binary-distribution path **does** rotate, and
both generations are carried at once so that a rotation never tears the
network into two collection sets (§26.6). What does not exist is a
rotation **cascade**: the key alone determines what counts as an official
update — a compromised key can sign malicious updates, but it cannot lock
anyone out.

**What the key cannot do.** It does not control *who* takes part in the
network: there is no packet HMAC (§20, §10) and **no network-side
membership filter at all**. The network secret that does exist keys the
lookup tag, the record encryption and the Nostr publishing key of the
binary distribution (§26.6) — it makes the update path findable and
readable, and grants no admission to the delivery layer. The lever against abuse
is the **KEX-Gate and gated reputation** (§10), not network admission —
there is no PoW-economics admission filter (PoW is dead,
§10/§20). This means there is neither an enforceable network split, nor a
rotation cascade, nor the attack surface "membership fingerprinting".

**What stays open.** The update signature is the one central lever in the
entire system, and therefore a single point for coercion. The public
object space (§16) explicitly demands "no authority solution … not even
for the maintainer", because capabilities that exist can be coerced,
stolen, or inherited. That rule applies to the object space, not to the
build channel — but the rationale hits the build channel just the same.
The mitigation is the reproducible build (§26.2): every user can check
that an official binary matches the published source code. A hardening
through threshold signatures (say, 2 of 3 maintainer keys jointly signing
a manifest) belongs on the roadmap (§30), not in a footnote.

### 26.8 OPEN

Decided numbers from this chapter have been removed — rationale in the
decision log, the decision itself
sits at the relevant paragraph.

| # | Point | Options |
|---|---|---|
| L-2 | There is no time commitment for the freshness of the update manifest: the manifest is learned at the moments named in §26.5.4, and its latency follows from how often those moments occur. This also leaves the worst-case network-split window unnumbered for rolling back a hard-block manifest. | (a) give no time commitment, but instead tie freshness to the readiness state and the platform tier (§22.6, §8/§9) and measure the value in the lab (§28/§29); (b) introduce a separate, shorter TTL class for manifest cells — this costs delivery-layer budget and has to be weighed against §20. No numeric value is set here |
| L-3 | Fountain parameters for binaries: block count, redundancy factor, and the share an always-on node contributes to the fountain-erasure cache. §26.6.1 works with a 150 MB example. The budget question has been decided since E-53: variant (a), a **separate bulk quota** (its own class, default 1 GB, desktop only, lowest priority — §22.6/§21); the retention-bounded field values are likewise fixed (48 h / ≤ 32 MB) | The fountain parameters themselves remain a **measurement task**: to be measured, not set |
| L-4 | The invitation link must name the fetch path without presupposing the inviter's direct reachability: there is no per-block addressing (§7/§9), and the ContactSeed carries entry hints (§15). | (a) the link carries entry hints like the seed does, and the browser downloads from the first reachable node the entry cascade resolves; (b) the link stays address-bearing and is declared exclusively as a LAN/near-field path; (c) a split — entry-cascade discovery for the address, the link only for hash, signature, and size. This also affects whether the browser assembler needs a fountain decoder (§26.6.5) |
| L-5 | Whether there are invitation-related entry records (§26.6.4). Such a record needs a decryption key, and the invitation link carries no key field — a publish with no reader violates Work Rule 5. | (a) fully specify the path — the key travels along in the link, which makes any derivation question moot; (b) do not publish invitation-related records — the link already carries the source and an external fallback, and the entry cascade only covers the case "the address changed before the click happened" |

---

## 27. Tech stack

Cleona builds on the following stack: Flutter and Dart as the
application framework, Protobuf as the format of the application
content, libsodium and liboqs for cryptography, libzstd for compression,
whisper.cpp for on-device speech recognition, Opus as the audio codec,
plus the platform toolchains and the build chain for the five target
platforms. Two cryptographic-algorithmic building blocks are procured or
implemented (§27.4): the Elligator2 C shim `native/cleona_link` (E-42)
and an LT fountain codec in pure Dart (E-42). A Merkle tree over a
*global* durable-object index was considered and dropped (§27.4.3): the
durable-object class uses per-class state roots (§16.0), not a global
Merkle index.

All figures in this chapter are measured against the source tree —
`pubspec.yaml`, `scripts/build-*-libs.sh`, `scripts/preflight.sh`, and
the files named in the text.

---

### 27.1 Design principles

1. **No cloud dependency.** Every library runs on the device. No Google
   Play Services, no Firebase, no external APIs, no third-party push wake
   services (FCM, APNs, UnifiedPush, WebPush — architecturally reviewed
   and rejected, §23, §31). **The one external dependency is the
   rendezvous of the fourth neighbour source** (§11.9, Nostr) — it is not a
   booster that gets retired but a permanent part of the cascade.

   **It is channel-dependent, and that is the whole point.** On the
   **beta** channel it is indispensable and stays indispensable: the
   participants there have no stable addresses — at present the bootstrap
   node is the only externally reachable one, and even its address
   changes. Source B's gate (≥ 50 nodes with 30 days of observed stable
   reachability) can therefore not be met on beta by construction. On the
   **live** channel the dependency *may* fall away once the network is
   large and stable enough that sources B and C carry the cold start
   alone; that is a later measurement against B's gate, not a plan. Entry
   itself remains the cascade of §11, of which two of three sources are
   in-network.
2. **FFI for performance-critical code.** Cryptography, compression,
   audio/video codecs, and speech recognition run through native C/C++
   libraries via Dart FFI.
3. **Cross-platform via Flutter.** One Dart codebase for five platforms;
   platform-specific code is isolated in `lib/core/platform/` and
   `lib/core/tray/`.

---

### 27.2 Application framework

| Building block | Technology | Version | Role |
|---|---|---|---|
| Framework | Flutter (Dart) | `pubspec.yaml`: `sdk: ^3.12.0` | one Dart codebase for five platforms (§27.8) |
| State management | Provider | `^6.1.0` | state management for the Flutter UI |
| Serialization | Protocol Buffers | `^4.0.0` | format of the application content before zstd, **inside** the sealing. On the wire, only 1200-B cells exist (§4.3) |
| Persistence | three forms (§4.5.3): messages in an encrypted SQLite database per identity; configuration in encrypted files; media as `.cmenc` | SQLite3 Multiple Ciphers, vendored (`native/cleona_store/`, §21.4.1) | `lib/core/storage/message_store.dart`; `lib/core/crypto/file_encryption.dart` + `lib/core/storage/atomic_json_writer.dart`; `lib/core/crypto/media_cipher.dart` |
| Erasure coding | Reed-Solomon in pure Dart, no native erasure library | — | `lib/core/codec/reed_solomon.dart` (§9.4) |
| UUID | uuid | `^4.0.0` | generation of local object identifiers |

---

### 27.3 Native libraries (FFI)

| Library | Dart binding | Provides | Role |
|---|---|---|---|
| **libsodium** | `crypto/sodium_ffi.dart` | Ed25519, X25519, AES-256-GCM, XSalsa20-Poly1305, SHA-256, HMAC-SHA256, HKDF, Argon2id, BLAKE2b | Foundation of classical cryptography. HKDF carries the tag derivation (§4, §6, KEX-Gate) and the link key `KDF(kNetworkChannel ‖ x25519_ss ‖ mlkem_ss [‖ static_ss])` (§4, §11). SHA-256 additionally carries `L_node = SHA-256("cleona/lnode/v1" ‖ E_node ‖ n_x25519 ‖ n_mlkem)` (§9.1), Ed25519 the entry-record signature (§11.1), and SHA-256 the per-class state root (§27.4.3) |
| **liboqs** | `crypto/oqs_ffi.dart` | ML-KEM-768, ML-DSA-65 | ML-KEM-768 per message (sealing) **and** per link handshake (§4). ML-DSA-65 signs long-lived, verifiable artifacts; it is not used in the message path (E-15) or in the public object space (E-30). Pinned at `0.15.0` (`scripts/build-android-libs.sh:142`). Built from source (not from the distribution repos), `OQS_init()` before first use |
| **libzstd** | `codec/compression.dart` (FFI) | Zstandard | compression of the application content — §4.3 keeps zstd in the cell assembly |
| **libwhisper** (+ GGML) | `archive/whisper_ffi.dart` | on-device speech recognition | voice transcription; no network relevance. Pinned at `v1.8.4` (`build-android-libs.sh:55`) |
| **libopus** | `calls/opus_ffi.dart` | Opus audio codec | audio codec for calls (§17). Caller: `lib/core/calls/voice_codec.dart`. `build_libopus()` sits in `scripts/build-android-libs.sh` and places `libopus.so` into the jniLibs; `scripts/preflight.sh` requires `libopus.so` in **both** Android ABI lists. Pinned at `1.5.2` |
| **cleona_net** | `link_io/native_send_path.dart` | direct syscall UDP send path IPv4/IPv6 (`sendto` on POSIX, `WSASendTo` on Windows) | the link layer (§4/§11) relies on UDP sockets. **The reason for the shim is a crash, not a throughput loss.** Under Windows, Dart's IOCP `RawDatagramSocket.send()` **crashes the Dart VM** (`GetStackPointerForStackBounds failed`) when sending to an IPv6 destination with no valid route, and the crash occurs **below any Dart-level try/catch** — no application-side handling can survive it. This is the regular case: the punch window (§17.3) deliberately sends to foreign candidates whose route is unknown. The load-bound loss that first motivated the shim — **87.9 %** of send calls dropped under sustained sending, measured at up to 500 pps — no longer carries the decision on its own, because the data port sends at a constant cell rate far below that rate. Whoever knows only the throughput reason will later remove the shim as obsolete. On the **data port**, the native sender is used **only on Windows** (on Linux, a second `SO_REUSEADDR` socket on the same port would siphon off incoming datagrams and starve reception, which is not caution but a measured regression: no PONG → no peer ever confirmed → dead mesh) |
| **cleona_pow** | `crypto/proof_of_work.dart` | SHA-256 iteration loop in C | **not used.** Proof-of-work plays no role in the design (§10/§20): the cell frame `tag | ttl | sealed_payload` has **no `pow` field** (§4.3), and the lever against abuse is redundancy m = 3 plus the KEX-Gate and gated reputation (§10), not proof-of-work. The shim has **no protocol consumer**; it stays in the tree unused. (If a Dart fallback or the symbol is missing, the loop simply does not run — there is nothing to compute.) |
| **cleona_voice** | Kotlin/AudioToolbox backends per platform | native OS voice session (AEC/NS/AGC) | voice sessions for calls; no network relevance (§17) |
| **cleona_video** | `native/cleona_video/` + platform backends | platform hardware video codecs | video codecs for calls; no network relevance (§17) |

`native/` has seven entries: `cleona_link`, `cleona_net`, `cleona_pow`,
`cleona_store` (SQLite3 Multiple Ciphers, the message store of §21.4.1),
`cleona_video`, `cleona_voice`, and `whisper_wrapper.c`. `cleona_link` is
built and in the tree: `native/cleona_link/cleona_link.c`, its own
`CMakeLists.txt`, a `test/` directory, and Monocypher 4.0.3 vendored
under `vendor/monocypher/`; `scripts/build-ios-libs.sh:340` carries a
`build_cleona_link()`. §27.4 ("Building blocks to procure") therefore
describes decisions that have already been executed, not outstanding
ones — see the note there.

The tree contains no software audio or video codecs: capture,
playback, echo cancellation, and noise reduction run through the native
OS voice sessions, video through platform hardware codecs (§17).

---

### 27.4 Building blocks to procure

> **This section documents decisions already carried out, not a
> backlog.** Every building block it lists has been procured. The
> chapter is kept because the *rationale* below is load-bearing — anyone
> asking later why a sixth native library exists gets the answer here.

#### 27.4.1 Elligator2 — **decided (E-42): C shim `native/cleona_link`**

The link handshake requires, for its outer layer, an "Elligator2-encoded
X25519 handshake — provably uniform on the wire." That is the commitment
on which the cover-stream indistinguishability (§5) and the absence of
any structural fingerprint on the wire rest (§4.3: no HMAC prefix, no
plaintext header, no protocol magic): without uniform encoding of the
public handshake value, the first cell of a connection is distinguishable
from randomness, and the entire indistinguishability commitment falls at
its first byte.

libsodium does not provide this primitive: the system library exports
mappings of uniform bytes onto an Ed25519 point — the direction needed
for hash-to-curve. The link handshake needs the **reverse direction**
(encoding an X25519 public key as a uniform-looking string), and it
needs it for **Curve25519**, not Ed25519. The building block therefore
needs to be procured.

**Options (basis for the decision):**

| # | Option | Price |
|---|---|---|
| (a) | own implementation in Dart, on the existing Curve25519 primitives | no build overhead, but **bespoke crypto** at the most sensitive point of the design. Constant-time execution is hard to guarantee in Dart; would have to go through the external crypto review without exception |
| (b) | C shim (`native/cleona_link/`) around a vetted implementation, analogous to `cleona_pow` | a known pattern in the project, constant-time execution attainable. Price: a sixth native library on **five** platforms including the iOS merge chain and symbol export |
| (c) | wait for a libsodium primitive | not foreseeable; blocks AP-3 |

**Decided (E-42): (b).** Rationale: the link layer is the only
place where a timing leak affects directly observable traffic —
constant-time execution is practically not guaranteeable in Dart, but
is in the C shim —, and the project already has, with `cleona_pow`, a
viable pattern for small crypto shims complete with Dart-fallback
discipline. Candidate to evaluate: **Monocypher** (Elligator2 "hidden
key" API, license CC0/BSD-2 — to be verified before adoption), vendored
as a single-file source. The shim belongs in AP-0/AP-3 and is carried as
a review item (review optional, E-47).

**Kemeleon is independent of this.** The uniform ML-KEM encoding (O-2) is
a later optimization, because the inner ML-KEM exchange already sits
inside the encrypted channel and is not visible on the wire. It is **not**
a prerequisite here.

#### 27.4.2 Fountain codes — **decided (E-42): LT/online codes in pure Dart**

§9.3 requires rateless erasure coding: "content → k source blocks (block
size = 1 cell payload ≈ 1.1 KB) → arbitrarily many encoded blocks can be
generated; **any** ~k·(1+ε) distinct blocks reconstruct the whole." The
building block needs to be implemented.

**Options (basis for the decision):**

| # | Option | Price |
|---|---|---|
| (a) | RaptorQ per RFC 6330, native library + FFI | best ε (near-optimal overhead). Price: a native library on five platforms; RaptorQ's licensing and IP situation needs to be clarified **before** committing to it — this document makes no statement on that |
| (b) | LT codes or online codes in pure Dart | markedly simpler, no build chain, no third-party license. Price: worse ε, i.e. more blocks for the same reconstruction probability. For a 150 MB binary (§26.6.1: ~135,000 blocks), every additional percent hits the bulk volume immediately |
| (c) | fixed-rate block code (Reed-Solomon, parameterized) | **for the bulk lane at scale:** discards the core claim of §9 (no block is special, no coordination). **Not for the band below the fountain lower bound** — there a block *is* special by measurement, and the coordination is sender-local rather than a protocol: the sender picks a distinct holder per fragment index of a stripe, with no query, no round trip and no timer, so §19's "no polling" is untouched (the bulk lane is a declared demand-driven class there in any case). Adopted for that band with E-3 = D (§9.3) |

**Decided (E-42): (b) as the starting point.** Rationale on
the IP situation: the foundational LT patents (filed ≤ 2002) have expired
after 20 years, while the RaptorQ IP rights (RFC 6330, ~2010/2011) may
still be in force. **(a) is a later optimization**, once the bulk volume
justifies it **and** the legal situation is clarified. Bar to clear
before the §9 figures count as a commitment: ε and encode/decode
throughput on the weakest target platform (isolate offloading planned).

**OPEN (§27-O-3):** block size and target ε. §9 names the block size
"= 1 cell payload ≈ 1.1 KB" and calculates with redundancy 5 at 10,000
nodes (~80 KB per node for a 150 MB binary). The ε value is
**procedure-dependent** and is not stated in any source — it must be
measured before the figures in §9 count as a commitment.

#### 27.4.3 Per-class state root — **not a procurement item**

§16.0 requires a **per-class state root** for the durable-object class,
anti-entropy replicated across relays, carried along in every
reconciliation that happens anyway (32 B). A single global index over
the whole durable-object class was considered and rejected: the §13
design review ruled it out as a correlation surface and an
over-commitment; the durable-object class uses **per-class** state
roots instead (§16.0).

The building block is **not a library question**: a Merkle tree (now
per-class) over SHA-256 is Dart code on a primitive that is already bound
(`crypto_hash_sha256` via `crypto/sodium_ffi.dart`, the same function
that `native/cleona_pow` calls in its loop). Effort: implementation and
tests, no build or license issue.

**What remains open here is not the building block but the commitment:**
whether the per-class roots converge sufficiently network-wide is, per
E-35, **explicitly not proven** and is a subject of the external crypto
review (optional since E-47, §23.3).

#### 27.4.4 Already present in the project — no procurement need

The following existing building blocks are used:

| Building block | Where | Role |
|---|---|---|
| **Linkable ring signatures** (MLSAG-style on Ed25519, key image) | `lib/core/crypto/linkable_ring_signature.dart` | in production for anonymous poll voting (§18). The moderation jury vote needs **exactly this** construction (§16: "valid ring signature against the case's draw + a unique key image"). This is the largest already-paid-for item of the crypto needs |
| **HKDF / BLAKE2b / SHA-256** | `crypto/sodium_ffi.dart` | tag derivation (§4/§6), link KDF (§4), per-class state root (§16.0) |
| **secp256k1 Schnorr** | `crypto/secp256k1_schnorr.dart` | **Active consumer.** It signs the Nostr events of the external entry source, which is the fourth source for finding neighbours (§11.8, §11.9). A phone has entered the network **without LAN**, purely over records from the external rendezvous, several relays answering — this primitive carries that path. Named and bounded in §4.2. |
| ~~**PoW loop**~~ | ~~`native/cleona_pow`, `crypto/proof_of_work.dart`~~ | **No consumer** (PoW plays no role, §10/§20; see §27.3). The shim stays in the tree unused rather than being pulled out of the build outright; see §27-O-7 |

---

### 27.5 Own native building blocks at a glance

Consolidated from §27.3 and §27.4.1 — the project's own entries under
`native/` and their roles:

| Entry | Role |
|---|---|
| `cleona_net` | syscall UDP send path of the link layer (§4/§11); active on the data port only under Windows (§27.3) |
| `cleona_pow` | **unused** — SHA-256 iteration loop; no protocol consumer (§10/§20, §27.3) |
| `cleona_voice` | native OS voice session per platform (AEC/NS/AGC, §17) |
| `cleona_video` | platform hardware video codecs (§17) |
| `whisper_wrapper.c` | C wrapper for the whisper.cpp binding (§27.3: `libwhisper` + GGML) |
| `cleona_link` | Elligator2 encoding of the link handshake (§4) — **built** (E-42, §27.4.1): C shim over vendored Monocypher 4.0.3, Dart side `lib/core/link/elligator_ffi.dart` |

---

### 27.6 Flutter packages

Inventory per `pubspec.yaml`:

| Package | Version | Purpose |
|---|---|---|
| `ffi` | `^2.1.0` | Dart FFI types for all native bindings |
| `fixnum` | `^1.1.0` | 64-bit integers for Protobuf |
| `path` / `path_provider` | `^1.9.0` / `^2.1.0` | path arithmetic, platform-specific directories |
| `connectivity_plus` | `^6.0.0` | detection of the network state (Wi-Fi / cellular / none) |
| `qr` / `qr_flutter` | `^3.0.2` / `^4.1.0` | QR generation for ContactSeed |
| `mobile_scanner` | `^6.0.0` | QR capture via the camera |
| `video_player` | `^2.11.1` | inline video playback in chat |
| `just_audio` | `^0.10.5` | audio playback (voice messages, sounds) |
| `record` | `^6.2.0` | recording of voice messages (AAC) |
| `image_picker` | `^1.0.0` | camera and gallery |
| `file_picker` | `^8.0.0` | file selection dialog |
| `desktop_drop` | `^0.7.0` | drag-and-drop on the desktop |
| `share_plus` | `^10.1.4` | system-wide sharing |
| `emoji_picker_flutter` | `^4.4.0` | emoji selection with categories, search, skin tones |
| `nfc_manager` | `^3.5.0` | NFC contact exchange (Android) |
| `url_launcher` | `^6.3.2` | opening URLs in the browser (normal / private) |
| `pdf` / `printing` | `^3.11.2` / `^5.14.3` | PDF generation, among other things for securing the seed phrase |
| `shared_preferences` | `^2.2.0` | persistent settings |
| `image` | `^4.8.0` | image decoding and scaling (link-preview thumbnails) |
| `collection` | `^1.18.0` | collection helper functions |
| `meta` | `^1.15.0` | annotations (`@visibleForTesting`, among others) |
| `cupertino_icons` | `^1.0.8` | icon set |

Besides network-change detection, `connectivity_plus` carries the
**connection type** for the rule "cellular is the last resort" (§22.6)
and the data-saver-mode suggestion when a metered connection is detected
(E-40).

---

### 27.7 External tools (runtime)

`ffmpeg` (optional, speech transcription), `wl-clipboard` and `xclip`
(optional, binary clipboard), `pw-play` with `paplay` fallback
(notification sounds). No network relevance.

---

### 27.8 Platform targets

Five platforms, fixed roles, fixed artifacts. Linux, Windows, and macOS
run as a separate daemon plus GUI (IPC over a Unix socket, over TCP
loopback with an auth token on Windows), Android and iOS in a single
process:

| Platform | Role (build) | Runtime tier (§22.6) | Artifact |
|---|---|---|---|
| Linux Desktop x86_64 | primary development | **always-on** | `cleona-daemon` + Flutter bundle |
| Windows Desktop x86_64 | test | **always-on** | `cleona-daemon.exe` + `cleona.exe` |
| Android arm64-v8a / x86_64 | release | **retention-bounded** | APK with jniLibs |
| iOS arm64 | release | **retention-bounded** | IPA (GitHub Actions macOS-14) |
| macOS arm64 | release | **always-on** | `cleona-daemon` + `Cleona.app` (DMG) |

The runtime-tier column comes from §22.6 (the always-on / retention-bounded
field roles) and describes runtime behavior — it has **no** effect on the
build chain: the same artifacts, the same libraries.

---

### 27.9 Build chain

**iOS.** Apple does not allow custom dynamic libraries in app bundles:
all native code is statically linked into the Runner binary, and Dart
finds the functions at runtime via `DynamicLibrary.process()`, i.e.
`dlsym(RTLD_DEFAULT, …)`. `scripts/build-ios-libs.sh` therefore builds
every library for `arm64-iphoneos` **and** `arm64-iphonesimulator`,
packages them as XCFrameworks, and merges the static archives with
`xcrun libtool -static` into a single `libcleona_all_device.a` (only
`libggml-base.a` and `libggml-cpu.a` are skipped, since their contents
already sit inside the umbrella library `libggml.a`). This produces
duplicate symbols, which three cooperating Xcode settings in
`ios/CleonaNative/CleonaNative.podspec` resolve — each one is mandatory:

| Setting | Effect |
|---|---|
| `OTHER_LDFLAGS = -force_load <archive>` | loads **all** object files of the archive, even though no Swift/ObjC code references them (the call only comes at runtime via `dlsym`). Without it, not a single native symbol ends up in the binary |
| `EXPORTED_SYMBOLS_FILE = ios/CleonaNative/cleona_exported_symbols.txt` | marks the C functions looked up via FFI as roots of dead-code stripping **and** writes them into the export table. Unreachable code — including the duplicate definitions — silently drops out in the process, which resolves the duplicates without a linker error. Without it, there are either duplicate errors or no symbols at all |
| `STRIP_STYLE = non-global` | preserves the export table during Xcode stripping. The default `all` deletes it again after a successful link; `dlsym()` then finds nothing at runtime (white screen) |

Two rules follow from this chain:

1. The library list in `scripts/build-ios-libs.sh` covers every native
   library including `cleona_link` (Elligator2 shim, E-42). The fountain
   codec is pure Dart and does not touch the native chain.
2. **Every new FFI function must be entered in
   `ios/CleonaNative/cleona_exported_symbols.txt`**, or the linker
   removes it as dead code and the app crashes at runtime.

The following approaches were tried and failed — a finding from a
multi-day debugging series with more than 15 CI runs:

| Approach | Why it failed |
|---|---|
| `DEAD_CODE_STRIPPING = NO` without `EXPORTED_SYMBOLS_FILE` | all symbols remain, the duplicates produce linker errors; not resolvable even with `-ld_classic` |
| `-ObjC -all_load` instead of `-force_load` | loads object files from **all** static libraries, not just its own — conflicts with system libraries |
| `ld -r` (pre-link) to deduplicate | fails on the strong (not weak) duplicates; `ld -r` tolerates only weak ones |
| separate `-force_load` per library instead of merging | the same duplicate errors, just with more paths |
| `ar`-based deduplication after the merge | fragile; fails under `set -euo pipefail` when `grep` finds nothing, and object file names collide on extraction |
| xcconfig injection after `pod install` | `flutter build ipa` internally runs `pod install` again and regenerates the xcconfigs |
| `sed` in `project.pbxproj` | the Pods xcconfig has higher priority and overrides pbxproj settings |
| `-exported_symbols_list` in `OTHER_LDFLAGS` instead of as its own setting | Xcode interpreted subsequent flags (`-lc++`) as file paths |
| `EXPORTED_SYMBOLS_FILE` without `STRIP_STYLE=non-global` | the link is correct (`nm` shows the symbols in the xcarchive), but the default stripping deletes the export table — `dlsym()` finds nothing at runtime |

**macOS, Android, Linux, Windows.** macOS uses ordinary `.dylib` files
in `Contents/Frameworks/` and has none of the iOS complications; the
remaining platforms build their library list through their respective
build scripts without comparable special cases.

**Reproducibility.** Every build from the published source code is
comparable and eligible to participate without any special case — there
is **no packet HMAC and no placeholder** that separates public builds
from the official network (§20). The network secret that does exist is
compiled into every build from the same published source and gates
nothing at the delivery layer; it only makes the binary-distribution path
findable and readable (§26.6). The flip side belongs in the document
just as much: this means there is no first-order fork protection
(§26.5.1); what is effective is the Ed25519 signature check of the update
manifests, trademark, and license (§26).

---

### 27.10 Open points of this chapter

Decided numbers of this chapter are recorded at the respective paragraph.

| # | Topic | Options | Blocks |
|---|---|---|---|
| §27-O-3 | block size and target ε of the fountain coding (§27.4.2) | §9.4 names a 1024 B block payload; the fountain overhead is a function of size, not a constant (§9.4). What remains open is throughput on the weakest target platform and the duplicate share of blocks collected in real use (§9.3). Bar (E-42): ε + throughput on the weakest target platform | §9 figures |
| §27-O-7 | whether `cleona_pow` should be dropped from the native build | `cleona_pow` has no protocol consumer — PoW plays no role in the design (§10/§20) — so dropping it from the build chain is a packaging cleanup, not an architecture decision. `secp256k1_schnorr.dart` is a separate question, named and bounded in §4.2, not a removal question — it has an active consumer (§27.4.4) | — |

---

## 28. Test strategy

*(Basis: `docs/TESTING.md`, `CLAUDE.md` (section "E2E Test Guideline")
and `.claude/skills/e2e-gui-tests/SKILL.md`. All figures in this chapter
are counted, not estimated.)*

This chapter implements **E-40**: the **three-way split lab /
simulation / field** (§28.2). The scope and tooling of the simulation
were decided (E-49): two-stage (→ §28.9.3).

---

### 28.1 Fixed constraints of the test strategy

- **Desktop-first.** Linux Desktop is the place of iteration — hot
  reload, multi-instance operation on one machine, and direct filesystem
  access to databases and logs are available there, which keeps the
  diagnostic loop short. Windows is the second desktop platform (its own
  Windows 11 VM, same daemon+GUI architecture), Android VM and iPhone are
  the mobile verification. Mobile carries particular weight as the
  retention-bounded tier (§22.6), but it is not a place of development.
- **The GUI E2E guideline applies literally.** Every `gui-*.spec.ts`
  checks the GUI from the end user's point of view: real mouse clicks via
  `GuiDriver` (evdev/uinput), real keyboard input, visual verification via
  OCR/screenshot. IPC is allowed exclusively for setup, teardown, state
  queries, and navigation shortcuts; the allowed and forbidden lists sit
  in `.claude/skills/e2e-gui-tests/SKILL.md`. The guideline describes what
  a test is supposed to prove over a human's screen — the more mechanism
  sits beneath the surface, the more depends on the single layer that
  shows the same thing comes out on top.
- **The four-worker architecture** of `scripts/run-e2e.sh`: four workers
  start in parallel — worker 1 Linux (Node1 + Node2, GuiDriver via
  evdev/uinput), worker 2 Windows VM (WinGuiDriver via xfreerdp), worker
  3 Android emulator (AdbDriver via `adb shell input`), worker 4 smoke
  directly on the host —, which terminate independently, and whose exit
  codes and summaries the runner collects into one overall report. It is
  a platform split, not a network split.
- **The pre-E2E gate** (`scripts/pre-e2e-gate.sh`): 10 mechanical checks
  before every E2E run, of which gates 1–7 are hard failures (VM bridge
  uplink, SSH reachability of the nodes, fresh profiles, binary-size
  check against wrong-architecture deploys, entry-cascade entry
  reachable (§11), Windows VM state, Android emulator state) and gates
  8–10 are warnings that switch off optional test surfaces (archive SFTP,
  CalDAV fixture server, jury-swarm status). §28.7 defines the
  network-related gate contents.
- **The conventions for standalone smoke files** (`docs/TESTING.md`):
  temp directories inside `finally`, `exit()` after the `finally`,
  `CLEONA_KEEP_TMP=1` as an opt-out, and above all **`AppPaths.setHome(<tmp>)`
  before every `CleonaNode`/`IdentityContext`/`CleonaService` construction**.
  The last rule is strict: the DeviceID is daemon-global (§4), and an
  overwritten `device_keys.bin.enc` is not a test artifact but the device's
  identity on the network.
- **Structured logging and log retention.** Log entries are buffered per
  profile directory and written to disk in batches every two seconds (the
  two-second buffer; without it, two daemons on one VM brought the system
  to its knees via iowait), and retention is bounded two-dimensionally —
  an age cap AND a total budget per `logs/` directory, with
  channel-specific values (beta more generous than live, because field
  RCAs need several days of hindsight). The readiness state (§22.7) and
  the delivery acknowledgements (§9.2) are the only evidence a field
  finding will ever have — they **must** appear in the log (§28.8).
- **Group/channel naming convention in E2E** (`docs/TESTING.md`): unique,
  thematically distinct names per spec.

---

### 28.2 The three-way split (normative, E-40)

The design knows three classes of commitments: **local** ones (crypto,
formats) that are provable in-process; **pairwise** ones (delivery, link
handshake) that show up between two nodes; and **size-dependent** ones
that do not exist between two nodes and are not measurable in the field,
because they only appear with hundreds of participants — see §5–§9 and
§11 for which quantities these are; anonymity sets are one example. From
this follows the three-way split:

| Level | Where | What it proves | What it **cannot** prove |
|---|---|---|---|
| **Lab** | in-process (smoke) + 2–22 real nodes (E2E, jury swarm, moderation lab) | function, formats, state transitions, error paths, user interface, platform parity | anything that depends on network size |
| **Simulation** | hundreds to tens of thousands of instances of a model, deterministic, accelerated time | scaling effects of the delivery layer (§5–§9, §11), convergence, budget compliance over weeks of simulated time | that the shipped code behaves the way the model does |
| **Field** | beta network with real users and real devices | real latency, real reachability fraction, real battery/data cost, cover effect under real traffic, anonymity sets | nothing deterministic; no regression |

Field measurements are collected in the beta network channel; beta and
live are separate, non-interoperable networks (§4).

**Normative ground rule of this chapter:** *No architectural commitment
may be declared proven at a level that cannot carry it.* This is not a
formality but the direct lesson from field finding B-2
(`docs/BEFUNDE_NETZWERK_V4_INPUT.md`), which grounds §9: the sender
carried a route as direct, the send acknowledged success, the test was
green — and nothing was delivered. The test was green because it queried
an intention instead of an observation. The three-way split is the
answer to the same class of error one level up: a simulation run that
shows scaling says nothing about the shipped code; a two-node E2E that
shows delivery says nothing about a field at real network size.

**Consequence for acceptance.** Every row of the mapping table in §28.5
carries exactly one level as its *primary* evidence. Where a commitment
is provable only in simulation, it is carried in the architecture as
*modeled*, not as *verified*, until the field confirms it.

---

### 28.3 Test inventory by level

**Lab.** The lab level consists of smoke files with `check()` assertions
and E2E specs that test business logic above the service API
(`sendToUser()` / `sendToDevice()`), plus golden suites with PNG
references (components × skin/mode combinations) and the integration
tests (CalDAV fixture server + jury perf). §28.6 lists the
network-adjacent test surfaces still to be built.

**Simulation.** The simulation suites (`sim/*`) are defined in §28.9:
metric runs with a tolerance band, no red/green in the E2E runner.

**Field.** Field measurements run in the beta network channel (§28.2);
the measurement plan is open (T-7).

**Mapping rule:** whether a test checks a commitment of this document is
decided **not by file name**, but by the production module the file
imports (§28.4). That is mechanical, reproducible, and survives renaming.

The business-logic suites by area, with the evidence that carries them:

| Area | Examples | Evidence |
|---|---|---|
| Cryptography | `smoke_per_message_kem`, `smoke_mldsa_derand`, `smoke_ring_signature`, `smoke_file_encryption`, `smoke_key_rotation`, `smoke_seed_phrase_validation` | §4: identity layer (keys, derivations, formats) |
| Groups & roles | `smoke_group_membership`, `groups-and-roles.spec.ts`, `role-permissions.spec.ts`, `gui-06-groups`, `gui-40-group-channel-management` | §16: groups as pairwise legs; membership and role logic |
| Calendar | `smoke_calendar`, `smoke_calendar_recurrence`, `smoke_ical`, `smoke_calendar_sync`, `gui-49`, `gui-50`, CalDAV integration | §18: the calendar is network-independent; RFC 5545 and CalDAV |
| Polls | `smoke_polls`, `smoke_ring_signature`, `smoke_anon_rebroadcast`, `smoke_date_poll_event_bridge`, `gui-51-polls` | §18.3/§18.4; the ring signature **additionally** carries the jury vote in §16 |
| Moderation (semantics) | `smoke_moderation`, `smoke_v27_moderation`, `smoke_public_channels`, `smoke_channels`, `moderation.spec.ts`, `gui-21`, `gui-07` | §16: the moderation semantics is the middle layer (§16.8) |
| i18n | `smoke_i18n`, `gui-13-i18n`, `scripts/check_i18n_complete.dart` | §24: network-independent |
| UI / design system | golden suites, `smoke_design_tokens`, `smoke_skin_catalog`, `smoke_message_bubble`, `gui-02`, `gui-15`, `gui-38` | §22 |
| Media & chat UX | `smoke_media_transfer`, `smoke_chat_ux`, `smoke_link_preview`, `smoke_voice_transcription`, `smoke_archive` | application layer above the service API |
| Calls | `smoke_calls`, `smoke_group_calls`, `smoke_video_calls`, `smoke_overlay_tree`, `smoke_voice_codec`, `gui-25`, `gui-33`, `gui-34`, `gui-64` | §17 (E-26): Plane D with its own D-frame format; jitter buffer, codecs, state machine |
| Multi-device | `smoke_twin_sync`, `smoke_device_delegation`, `smoke_linked_device_*`, `smoke_rotation_co_auth`, `gui-48` | §14: device model, delegation and rotation logic |
| Infrastructure | `smoke_log_retention`, `smoke_atomic_json_writer`, `smoke_ipc_stability`, `smoke_update_manifest`, `gui-46-tray-icon`, `gui-63-windows-installer` | platform-bound, not network-bound |

---

### 28.4 Test principles (normative)

1. **Tests are mapped to the production module, not to the file name.**
   What decides is which modules a test file imports and which commitment
   of this document it thereby proves (§28.3).
2. **A skipped test is a failure, not a skip.** Gates whose precondition
   is missing fail, instead of silently skipping. A gate that stays
   silent when its precondition is missing is worse than no gate: it
   creates the conviction of having checked something. The runner
   reports the load-bearing quantities (e.g. the number of participating
   jurors, §28.8) as a number in the report.
3. **No commitment is declared proven at a level that cannot carry it**
   (§28.2). Where only the simulation carries it, the commitment counts
   as *modeled*, not as *verified*.
4. **Tests check observations, not intentions.** A delivery assurance
   checks the delivery acknowledgement (Z-1), never a socket write or a
   counter (§28.7).
5. **A test under reconstruction may be red, but not invisible.** A test
   whose subject continues to exist runs in the active tree; visible red
   is preferable to silent absence.
6. **A test proves exactly the assurance it was written for.** Where a
   different assurance becomes necessary at the same spot, a new test is
   created (§28.5/§28.6), instead of bending the existing one toward
   different behavior — a bent test proves nothing.

---

### 28.5 Mapping of the commitments to test levels

Legend: **L** = lab, **S** = simulation, **F** = field. Bold = primary
evidence.

| # | Commitment | Evidence | L | S | F | What exactly is measured |
|---|---|---|---|---|---|---|
| Z-1 | **Delivery acknowledgement** (§9.2): sealed and signed, addressed to the original sender only | §9.2 | **L** | | | Lab: a forged or unsealed acknowledgement is rejected; an acknowledgement from a party other than the addressee is discarded and reported; a duplicate is ignored; an acknowledgement for an unknown identifier is not raised as an error. The negative tests are the important ones: they are the direct reversal of field finding B-2 |
| Z-2 | **Readiness** `searching` / `connecting` / `ready`, `ready` = ≥ 2 answering neighbours (§22.7.1) | §22.7 | **L** | S | F | Lab: state transitions in both directions, including fallback on network change (§19). Field: time from installation to `ready` — §22.7 calls it "the only settling time the system knows; it is to be measured and reported" |
| Z-4 | **A recipient who is offline is not an error** | §9.1 | **L** | S | | Lab: the recipient is stopped, a message is sent, the state stays `in transit` while the packet waits in a post box; the recipient starts, collects, and the state becomes `delivered`. The test guards against a premature `failed` and against a permanent `in transit` after collection |
| Z-5 | **Durable-object convergence**, anti-entropy without its own tick | §16.0 | L | **S** | F | Lab: anti-entropy between 3–5 nodes converges; type rules (missing proof → no replication) apply. Simulation: convergence of the **per-class state root** across hundreds of nodes with partition and reunion. §16.0 states explicitly: "convergence of the roots is **not proven**" (O-25) |
| Z-8 | **Quotas / platform tiers:** retention-bounded 2–5 MB/day, always-on ~40–50 MB/day, field ~160 MB | §22.6 | L | **S** | **F** | Lab: the quota is met (counter). Simulation: storage per node over 14 d of simulated time at 10k / 1M nodes. Field: real data volume and battery drain on Android and iOS — §22.6 says the iOS figure is "unsubstantiated … an upper bound, not an expectation" |
| Z-9 | **Cover traffic:** Poisson timing, constant size, sealed content | §5, §5.5 | **L** | S | F | Lab: wire profile with an empty outbox indistinguishable from one with a full one, **and identical send-time and neighbour sequence with and without update pieces pending** — the positive control for rules 1 and 2 of §5.5 — **and, with cover off, a pending update still completes** (§3.1). Field: whether a real observer can infer anything — and whether **data-saver mode** (§22.6, E-40) makes the node distinguishable, as the architecture claims |
| Z-10 | **Family diffusion:** v4-only ↔ v6-only via dual-stack | §11 | **L** | S | F | Lab: three nodes (v4-only, dual, v6-only), cell diffuses. Simulation: diversity thresholds set since E-55 (25 % / target value 2, Monte Carlo pre-measurement) — re-check here under inbound limits, latency bias, and churn |
| Z-11 | **Beta/live network-channel separation:** handshake fails before a cell flows | §4 | **L** | | | Lab, two nodes with different `kNetworkChannel`: no link key, no handshake |
| Z-12 | **Identity determinism:** seed import deterministically yields the same UserID | §4 | **L** | | | Lab: byte-identical, pinned `kIdentityDomain`; 24 words → identical UserID across every reinstall. Must be in place before release |
| Z-13 | **Delivery latency across the ladder** (§7, §8): steps 1–3 resolve while the recipient is online, typically within seconds; step 4 (the post box) delivers only once the recipient returns — there is no fixed upper bound, by design | §7, §8, §9 | L | S | **F** | Honestly measurable only in the field. The lab can see a step fail to resolve, not confirm real-world timing. |
| Z-14 | **Callability matrix** (foreground 1–3 s, Android/desktop background seconds, iOS closed: no calls) | §17.2, §8 | L | | **F** | Lab: signaling state machine `reaching`/RING_ACK, 30-s punch window, 120-s TTL class. Field: the times and the iOS claim |
| Z-15 | **Ring-signature vote + verifiable class state** | §16.4/§16.7, E-25/E-29 | **L** | S | | Lab: signature correctness, key-image uniqueness, cross-poll unlinkability, inclusion proofs. Remains a **review item** (E-47: external review optional, §23.3) — a test run does not replace a proof |
| Z-16 | **Prekey pool / forward secrecy**, shared pool under multi-device | §4, §14, E-40(2) | **L** | S | | Lab: consumption, refill threshold, consumption notice as a twin-sync type, discard and refill on lock-out. Simulation: exhaustion under load (B = 16, refill threshold B/2 — E-51, simulator-tunable) |
| Z-17 | **Anonymity sets** (how large is the set a sender disappears into) | §23, §4 | | S | **F** | Simulation delivers an upper bound under model assumptions; only the field measurement is load-bearing. Until then, this commitment is carried as **modeled** |
| Z-18 | **First-contact/invite life cycle:** `exp`, revocation, multi-use with attribution, evicting request buffer | §15, E-28 | **L** | | F | The lab covers the whole cycle; the parameters are fully fixed by E-50/E-51/E-52 (`B₀` = 4 final, request factor) |
| Z-19 | **Moderation procedure end-to-end** (report → case → jury → verdict → consequence), ≥ 5 jurors, multiple nodes | §16 | **L** | S | | The evidentiary obligation is open — see §28.8 |
| Z-22 | **Entry records** (§11, E-60) | §11 | **L** | | F | Lab: a node that found neighbours by sources 1–3 issues **no** record; a node that found none issues its own record under an address through which it is reachable and issues a new one only when that address changes (§11.9); expired records are not handed on; no more than a quarter of the cache comes from one partner; a record whose signature or `expiry` fails is discarded. Field: partner acquisition after a network change with no entry-cascade entry reachable |

**What is deliberately missing from this table:** a row "delivery
works." It would be the summary of the individual rows above and exactly
the kind of aggregate that looked green in field finding B-2 while
nothing arrived. Delivery is checked through its individual pieces of
evidence or not at all.

---

### 28.6 Test surfaces still to be built

The following suites are to be built with AP-5:

| New | Level | Subject |
|---|---|---|
| `smoke_cell.dart` | L | cell codec, sizes against §4 — **both classes**: signature-free (1:1, group leg) and signed (`K_C`, object space); packing multiple cells into one wire cell |
| `smoke_tag_derivation.dart` | L | `HKDF` tag derivation (§4), `kNetworkChannel` as KDF input, group/channel tags (§16) |
| `smoke_delivery_ack.dart` | L | Z-1 in full, including the negative cases |
| `smoke_readiness.dart` | L | Z-2, all transitions, independence and family criterion |
| `smoke_dauerobjekt.dart` | L | type system, proof check, protection rule §16.0 ("an object that describes a third party is unconstructible by the type system" — a **negative test against constructibility**), sub-budgets 6/2/2 MB |
| `smoke_fountain.dart` | L | rateless codec, k·(1+ε) reconstruction from arbitrary blocks (§9) |
| `smoke_link_handshake.dart` | L | Elligator2 + ML-KEM, network-channel separation (Z-11), uniform wire profile (§4) |
| `smoke_ladder.dart` | L | the four-rung ladder (§7, §8) tried in parallel; the first acknowledgement wins and cancels the rest; `SendOutcome {placing, placed, failed}` on `sendToUser` |
| `gui-66-readiness.spec.ts` | L | readiness in the connection icon, tray, Android notification, network-stats badge (E-41); separate inbound/outbound partner counts |
| `gui-67-delivery-status.spec.ts` | L | the four states of §9.1 as icons in the bubble; an offline recipient shown as `in transit`, not as an error; retry by click |
| `gui-68-datensparmodus.spec.ts` | L | data-saver mode as a **visible state** with a named consequence (§22.6); never automatically active |
| `gui-69-no-delivery-mode-control.spec.ts` | L | negative test: no per-chat delivery-mode toggle anywhere in the interface (§12.1) — one path, nothing to switch |
| `sim/*` | S | see §28.9 |

> **Not built.** `smoke_pow_price.dart` (price curve quadratic in TTL,
> eviction rank) is not built: proof-of-work plays no role in the design
> (§10/§20), and the cell frame `tag | ttl | sealed_payload` has no `pow`
> field (§4.3) — its subject does not exist.

---

### 28.7 E2E gates: `ready` instead of peer counter

§22.7 is normative and terse at this point: *"E2E tests gate on `ready`,
not on a peer counter or route flags."* This is the test-level counterpart
of the same decision §9 makes at the product level: a peer counter counts
acquaintances; readiness counts evidence.

**The central wait helper** is `waitForReady({ target: 'ready' |
'connecting', … })`; it polls the three-valued readiness state from
§22.7.

Rule for wait conditions, in this order:

1. If the call waits for **the ability to send** → `ready`.
2. If it waits for **a partner to exist at all** → `connecting`.
3. If it checks a **display** → against the separate inbound/outbound
   partner counts (E-41, §11), not against a sum.
4. If it checks a **delivery** → not against partners at all, but against
   the delivery acknowledgement (Z-1, §9.2).

**Gates outside the specs:**

- **`scripts/pre-e2e-gate.sh`**: gates 1–7 (bridge, SSH, fresh profiles,
  binary size, entry-cascade entry reachable (§11), Windows VM, Android
  emulator), plus a gate "all test nodes reach `ready` within N seconds" —
  a running daemon is not a delivery-capable daemon.
- **`test/e2e/lib/global-setup.ts`**: building the contact mesh waits on
  `ready` per node.
- **Functional product gates**: gates in the product too (e.g. releasing
  the posting of contact issue reports) gate on `ready` (E-41). §22.7
  requires such gates to be **fully inventoried** before AP-5.

---

### 28.8 Evidentiary obligations of moderation

§16 carries two commitments with their own evidentiary obligation (§28.5):

**Z-15 — ring-signature vote and verifiable class state**
(§16.4/§16.7, E-25/E-29). Lab: signature correctness, key-image
uniqueness, cross-poll unlinkability, inclusion proofs. Z-15 is at the
same time a review item (E-47: external review optional, §23.3) — a test
run does not replace a proof.

**Z-19 — the moderation procedure end-to-end** (report → case → jury →
verdict → consequence) with ≥ 5 independent jurors across multiple
nodes, against a test preset with simulated registry aging (T-5). The
evidentiary obligation is open. The lab evidence against the T-5 preset
comes first; the simulation of the jury draw under network size
follows it and does not replace it. The evidence must
include, per consequence, at least **one** GUI verification per the
guideline from §28.1: badge visible, channel gone from the youth-safe
search, jury request clickable in the "Requests" tab.

**Logging requirement (normative):** for Z-19 to be evaluable, the event
chain (report created → case formed → request drawn → vote cast →
verdict closed) must be **logged in structured form**. Because delivery
does not confirm receipt to a UI in real time, there is no one you could
ask whether the request arrived — without a structured trail, the
procedure leaves nothing checkable behind.

**Skip prohibition:** for the moderation evidence, §28.4 point 2 applies
in a tightened form: the runner reports the number of participating jurors
as a number in the report; a run without the minimum juror count is a
**failure**, not a skip.

---

### 28.9 The simulator (O-15 — decided, E-49)

#### 28.9.1 What it must be capable of (normative)

These requirements are fixed, independent of the tooling choice:

1. **Deterministic and seedable.** Same seed → same run. Without this, a
   found bug is not reproducible, and a simulator that does not reproduce
   is an opinion with numbers.
2. **Accelerated, explicit time.** TTL 14 d, grace, probation, case
   upper bound — none of these commitments is checkable in real time. The
   simulation clock is a quantity of the model, not a wall clock.
3. **≥ 10,000 instances on one machine.** The lab's test server (32 threads, 251 GB) is
   the target hardware. This rules out "one process per node":
   `scripts/jury-swarm.sh` measurably needs ~30 MB per daemon instance,
   which carries ~100 instances, not 10,000.
4. **The delivery layer's basic operations** — whatever §5–§9 and §11
   define as constant background behavior and as a delivery attempt.
   Everything else is trimming.
5. **Storage and traffic accounting per node** against the platform tiers
   from §22.6 — the simulator must be able to say how much a
   retention-bounded node carries in one day.
6. **Adversarial roles as first-class:** Sybil mass, paying evictor
   (R-11), colluding always-on relays for backdated attestations (§16.0),
   partition and reunion. A simulator that can only do the cooperative
   case proves the numbers that are not the point.
7. **Measurement interface instead of log scraping:** metrics as a
   structured time series (message survival, delivery latency, share of
   lost messages, time to `ready`, per-class state root divergence).
8. **A shared core with the product code, wherever possible.** Whatever
   §5–§9 define as delivery-layer functions should be called as
   **the same Dart functions** as the app, not reimplemented for the
   model. Only then does the simulation test a rule and not a retelling
   of it. Everything below that (sockets,
   crypto, storage) may be a model.

#### 28.9.2 What it explicitly does not prove

- **Not that the shipped code behaves this way.** The simulator checks a
  model. Every commitment it supports **additionally** needs a lab test
  that shows the product code implements the same rule (requirement 8
  shrinks this gap, it does not close it).
- **Not anonymity.** Anonymity is a statement about observers with
  unknown capabilities. The simulator can deliver a *lower bound of the
  anonymity set under model assumptions* — nothing more. Z-17 remains a
  field matter.
- **Not latency.** Network round-trip times, cellular wake-up times, Doze
  behavior, and iOS background windows are not modelable (§31).
- **Not platform reality.** Battery, data volume, foreground-service
  survival, iOS policy: all field.
- **Not the user interface.** That is what the GUI E2E guideline is for.
- **No regression in the usual sense.** A simulation run is a measurement
  with scatter. It does not belong as red/green in the E2E runner, but as
  a **metrics run with a tolerance band** in its own, less frequently
  running job.

#### 28.9.3 Tool and scope (O-15 — decided, E-49)

**Decided (E-49): option D — two-stage.** The set of options examined
during the design phase, preserved as a source of rationale:

| Option | Description | For | Against |
|---|---|---|---|
| **A — Dart isolates, in-process** | N nodes as objects in one process, delivery as a method call, simulated clock | shares requirement 8 to the maximum (real product code, not a reconstruction); no new language; runs in the existing smoke infrastructure | memory per node bounds the size; no real concurrency pressure; risk that the model merely mimics the product code where it does not exist yet |
| **B — Event-driven simulator, its own tool** (e.g. Rust/Go, or a DES framework) | discrete event simulation, 10⁵–10⁶ nodes | scaling; clean time semantics; adversarial roles easy | second implementation of the same rules = second source of error; violates requirement 8; maintenance burden |
| **C — Containerized real daemons** (100–200 on the test server) | real binaries, real sockets | maximum evidentiary weight per node | 10,000 unreachable; exactly the order of magnitude where the design gets interesting stays out of reach |
| **D — Two-stage: A for the rules, C for reality** | Dart simulation for scaling, container swarm as a bridge to the lab | covers both ends; C validates A at small N | two tools, two maintenance costs |

**Rationale for the choice (E-49):** D is the only
option that addresses the model-reality gap from §28.9.2 instead of
ignoring it — A delivers the order of magnitude, C the reconciliation at
N ≈ 150, and the difference between the two at the same N is itself a
metric. Rejected: A alone (leaves the gap open), B (second implementation
of the same rules = second source of error, violates requirement 8), C
alone (10,000 unreachable).

**The reservation from the design phase remains normative:** the effort
is real and competes with AP-5. If the simulation is deferred, Z-5,
Z-8, and Z-17 are to be marked in the architecture as
**unsubstantiated** — not as "plausible." The follow-up question decided
with E-54: the Dart stage runs a cost model calibrated from device
measurements; real work runs in the container swarm. The
simulator needs no dedicated hardware of its own — it uses the test
server in time slices (details and measurement basis: §29.5, ch.-29-OPEN
E-3/E-4).

---

### 28.10 Release criteria before the production launch

**The lab counts as passed when all of the following points hold
simultaneously (E-44 point 3 — normative):**

| # | Condition |
|---|---|
| G-1 | Z-1, Z-2, Z-4, Z-10, Z-11, Z-12 are green in the lab — on **all five** platforms (Linux, Windows, macOS, Android, iOS), per the working rule "all platforms mandatory" |
| G-2 | The two-node full E2E across the specs (§28.3) is green |
| G-3 | Z-8 in the lab: an Android retention-bounded node keeps its daily quota over 72 h, measured on the device, not on the emulator |
| G-4 | Z-13/Z-14: real-device latency across the ladder (§7, §8) is measured and lies within the band; the callability matrix from §17.2 checks out |
| G-5 | The evidentiary obligations of moderation (§28.8) are met: Z-19 is proven in the lab |

Only after G-1…G-5 does field evidence begin in the beta network channel
(§28.2); commitments that only the field can carry (Z-13, Z-17) count as
modeled until then.

---

### 28.11 Open points of this chapter

Decided numbers of this chapter are recorded at the respective
paragraph.

| # | Point | Options / status |
|---|---|---|
| **T-2** | **Tolerance bands of the simulation metrics** | Without a band, a metrics run cannot be decided red/green. Proposal: measure first, then set the band — but before its first use as a gate |
| **T-3** | **Test surface for the identity registry** | The decision has been made (§13, E-39 point 4 + E-48: HD derivation + marker per identity, one own bundle per identity with name/`active` — not a network object). **The test surface for the §13 mechanism (marker, derivation, per-identity bundles) still needs to be built** — a pure work item, no longer an open decision |
| **T-5** | **Test preset for Z-19** | `ModerationConfig.lab()` sets `identityMinAge=0` for fresh VMs and thereby disables the age rule that the gated-reputation eligibility (§10) makes **central**. Z-19 runs against a preset with **simulated registry aging**, built before the Z-19 lab run. A pure work item |
| **T-6** | **Golden tests under skin/state extension** | The reference PNGs cover components × skin/mode combinations. If new state icons for `message_bubble` and the status bar come with Z-2/§22.7, the references grow accordingly. No conflict, just effort — noted here so it does not come as a surprise |
| **T-7** | **Field measurement plan** | §22.7 requires measuring and reporting the time to `ready`, §22.6 calls the iOS figure unsubstantiated, Z-17 is a pure field matter. There is **no** measurement plan for the beta network (What is collected? How does it reach the developer without violating §23?). That is the largest unwritten area of this chapter |

---

## 29. Development environment

The development environment depends on language, tool chain, and lab
hardware: Flutter/Dart on a Linux workstation, native libraries via FFI,
a VM lab for interactive tests (§29.3), and a test server for mass
spawning (§29.4). It additionally requires a **network simulator** for
the scaling questions (§29.5).

### 29.1 Workstation (Linux)

Ubuntu/Debian with the Flutter and Dart SDK plus a native tool chain:

| Component | Content |
|---|---|
| System packages | `curl git unzip xz-utils zip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev`, plus `wl-clipboard`/`xclip` (without them only text paste from the clipboard works, not binary) and `ffmpeg` (audio conversion to WAV for transcription) |
| Flutter | stable channel cloned from the Git repo, `~/flutter/bin` in the `PATH`, checked with `flutter doctor` |
| libsodium | distribution package `libsodium-dev`; supplies X25519, Ed25519, XSalsa20-Poly1305, SHA-256, HKDF, Argon2id, BLAKE2b; FFI bindings in `lib/core/crypto/sodium_ffi.dart` |
| liboqs | built from source (not in the Ubuntu repos), CMake/Ninja with `-DBUILD_SHARED_LIBS=ON` to `/usr/local/lib/liboqs.so`; supplies ML-KEM-768 and ML-DSA-65; FFI bindings in `lib/core/crypto/oqs_ffi.dart`; **`OQS_init()` must be called before every liboqs operation**. ML-KEM-768 carries message sealing and the link layer; ML-DSA-65 carries the update manifest, DeviceDelegationCert, continuity proofs, and identity anchors (§4) |
| libzstd | distribution package `libzstd-dev` |
| cleona_link | C shim `native/cleona_link` (Elligator2, Monocypher candidate, §27.4.1) |
| whisper.cpp | pinned to **v1.8.4**, built from source as a shared library; `libwhisper.so` and the transitive GGML dependencies (`libggml.so`, `libggml-base.so`, `libggml-cpu.so`) go to `/usr/local/lib/`; the FFI loader preloads the GGML dependencies before it opens libwhisper. The thin wrapper `libwhisper_wrapper.so` (`scripts/build-whisper-wrapper.sh`) bridges Dart FFI to the struct-by-value API `whisper_full()`; FFI bindings in `lib/core/archive/whisper_ffi.dart`. Model file under `~/.cleona/models/` (tiny ~40 MB, base ~75 MB — recommended, small ~250 MB). Without whisper.cpp and ffmpeg, voice messages still work, just without transcription text |
| Protobuf | `protobuf-compiler` plus `dart pub global activate protoc_plugin`; generated via `protoc --dart_out=lib/generated/proto -Iproto proto/app_payloads.proto proto/transport_v3.proto` into `lib/generated/proto`. The generated output is checked in and is produced by no build script — after every schema change, regenerate by hand and commit it |
| IDE | VS Code with the Flutter, Dart, GitLens, Error Lens, Todo Tree extensions |

The fountain codec needs **no** library — LT/online codes in pure Dart
(**E-42**, §27.4.2).

### 29.2 Building, checking, releasing

The command set (day-to-day reference: `CLAUDE.md`): `flutter build linux
--release` (optionally `--dart-define=NETWORK_CHANNEL=live`),
`scripts/build-daemon.sh` (daemon and `init-profile` in the shipping
layout via `dart build cli`; never `dart compile exe`, which runs no build
hooks),
`dart analyze` as a mandatory step before every deploy, the Android
cross-compile scripts (`scripts/build-android-libs.sh` with
`--arch arm64-v8a|x86_64|all`) plus `flutter build apk --debug --flavor
beta` and `flutter build apk --release --flavor live
--dart-define=NETWORK_CHANNEL=live`, the Apple scripts
(`build-ios-libs.sh`, `build-macos-libs.sh`) plus the CI workflow
`ios-build.yml` on a macOS runner, the Protobuf regeneration, the
localhost start scripts (`scripts/start-bootstrap.sh`, `start-cleona1.sh`,
`start-cleona2.sh`, `stop-all.sh`), `flutter test`, `scripts/run-e2e.sh`
(all suites or individual ones, with a lockfile and a progress display),
and `scripts/jury-swarm.sh`.

**Convention:** beta always `--debug`, live never `--debug`.

**Preflight check and Git hooks** (`CLAUDE.md`, section "Pre-Commit &
Preflight"): `scripts/install-hooks.sh` once after cloning; after that the
`pre-commit` hook calls `scripts/preflight.sh` and blocks on a version
mismatch between `pubspec.yaml` and `kCurrentAppVersion`, on i18n gaps
(§24.2), on a missing `SafeArea` in new screen files, on secret patterns,
and on missing iOS privacy keys. `scripts/preflight.sh --full` includes
`dart analyze`.

**Publishing only via the 5-script pipeline** (work rule 9,
`docs/PUBLISHING.md`, §26.2). The dry run against the local bare mirror
is mandatory and fails closed. The hookify rules `block-push-from-cleona`,
`require-neutralized-cleonagit-commit`, and `block-master-arch-write`
enforce this.

**Completion criterion for a change:** `dart analyze` green, `flutter
build linux` successful, daemon compile successful, `scripts/vm/vm-deploy.sh`
passes on all VMs.

*A section is omitted from the public edition.*


### 29.5 Network simulator

**Occasion.** E-40 fixes the test strategy as three-part: **lab /
simulation / field** (O-15). The middle part had no environment — closing
that gap is this chapter's occasion. Two VMs (§29.3) and 20 VMs (§29.4)
suffice for functional and procedural proofs, but not for the questions
the design hinges on: several commitments of §5–§11 hold only **over
node count**, and are marked there as "to be measured" — this chapter
does not restate which; it must be kept in sync with those chapters as
their scale-dependent commitments settle.

**What follows from this for the development environment (normative):**

1. The simulator is **part of the development environment**, not of the
   product — it is not shipped and does not run on user devices.
2. It must represent node counts the lab cannot provide. The scaling
   arguments run to 10,000 and 1 million nodes (§9) — the moderation lab
   has 20.
3. It must **compress time**: several retention and rotation windows in
   §5–§11 and §14 run to weeks, and none of them can be checked in real
   time.
4. It must run the same protocol as the production code, not a
   reconstructed model of it. Otherwise it measures the simulator instead
   of the system — exactly the error class that field finding B-2
   documents ("success mirrored an intention instead of an observation",
   §9).
5. It runs on the test server from §29.4 (16 cores / 32 threads, 251 GiB),
   not on the workstation.

**What the simulator explicitly does not replace:** the lab (real
operating systems, real GUI, real platform limits) and the field (real
NAT, real cellular links, real user behavior). The three-part split from
E-40 is a supplement, not a substitute for either.

**Scope and tool are decided — two-stage (E-49, §28.9.3):** in-process
Dart simulation for rules and order of magnitude (≥ 10,000 instances,
the same Dart core as the app), a container swarm of real daemons
(100–200) as a bridge to the lab (formerly OPEN E-2).

**Cost model in the simulation (ch.-29 OPEN E-3 — decided, E-54):
calibrated cost model in the Dart stage, real work in the container
swarm.** The Dart stage runs on a model clock (§28.9.1 point 2); the
cost quantities of the delivery layer are modeled there, not computed as
real bytes, and it calls the same Dart functions as the app wherever
possible (§28.9.1 point 9 — "crypto may be model"). The container swarm
computes for real: it runs in real time, and the E-49 metric "difference
between the two stages at equal N" measures the error of the cost model
along the way.

**Hardware (ch.-29 OPEN E-4 — decided, E-54): none dedicated, time
separation from the moderation lab.** Simulation runs use the idle
phases of the two-phase lifecycle from §29.4; they are rare metric jobs
with a tolerance band (§28.9.2) anyway, not a sustained load. With the
lab stopped, roughly 210 GiB of 247 GiB are free (permanent VMs ≈ 37 GB).
The Dart stage holds delivery-layer state as metadata objects, never as
payload, which is why it fits at all at 10,000-instance scale; the
container swarm needs on the order of 10–20 GB RAM and disk. Alongside
the running lab (168 GB allocated, 56 vCPUs oversubscribed on 32
threads), the Dart stage reliably does not fit — the time separation is
an operating precondition, not a cost-saving measure. The test server's
backup window must be respected. **Two reconsideration triggers**
instead of one silent standing assumption: (1) the *measured*
delivery-layer metadata size of the Dart stage exceeds what the idle
window can hold; (2) simulation time slots and moderation-lab runs
collide regularly (more often than weekly). Rejected — additional
hardware (option b): no substantiated bottleneck, and the 1-million-node
questions from §9 are not solved in RAM by new hardware either — they
remain analytical or sample-based.

### 29.6 OPEN — none

All four points of this chapter (E-1 fountain library, E-2 simulator
tool, E-3 cost model, E-4 hardware) are decided (E-42, E-49, E-54);
rationale and rejected alternatives are recorded at the determinations
in §28.9.3 and §29.5. The cost model (E-3) is the eviction/cover cost
model, since proof-of-work plays no role (§10/§20).

---

## 30. Build order

Implementing the delivery layer before the seam to the application layer
is cleanly drawn loses the test base — order matters, and getting it
wrong is expensive. This chapter lists the work packages WP-1…WP-7 with
their prerequisites, their verifications, and their dependency order.

> **No dates.** This chapter deliberately names no dates, quarters, or
> durations. None can be derived from the material at hand, and an
> invented date would be worse than none. This chapter describes
> **order and prerequisite**, not time.

### 30.1 Scope of this build

The system comprises the delivery layer — the cover system (§5),
reachability (§6), the direct and indirect delivery ways (§7, §8),
delivery states and acknowledgement (§9), Sybil & censorship resistance
(§10), NAT & transport (§11) — the fountain content layer for files and
in-network updates (§9, §26.6.1), and the application layers on top of
it: calendar, polls, archive, moderation, channels, media, identity,
IPC, i18n, storage, tray, platform binding, and the crypto primitives
(§4). `calls/` carries the Plane D API (§17).

**Exactly one delivery layer runs per installation; there is no
compatibility mode on the wire; the identity layer (seeds, keys, HD
derivation, local data handling) is part of the design.**

The cut line between the delivery layer and the application layer is the
service API. It has three access points, not one: the pair
`sendToUser()` / `sendToDevice()` — which carries a `SendOutcome
{placing, placed, failed}` result (§22.5) —, the infrastructure send path
`node.sendInfraTo()` (some application services send exclusively through
it), and the direct `node.<member>` accesses reaching all the way up into
`main.dart`, `service_daemon.dart`, `ipc/ipc_server.dart`, and
`ui/components/connection_sheet.dart`. All three access points belong to
the seam and are remediated before the delivery layer is implemented
(WP-2 before WP-4/WP-5).

### 30.2 Design maturity

The delivery core (§3, §5–§9, §11) is grounded in its own measurements
and decisions. **No decision is open in the delivery layer.** What
remains open is measurement and build work, not design — tracked in
full at §31, "Consolidated state of the open points."

### 30.3 Conditions before the production launch

Before the production launch stand the **release criteria G-1…G-5
(§28.10)**, which must be satisfied simultaneously. Alongside them stands
one point that has been optional since E-47.

#### A — External crypto review (optional, E-47)

The external review is **not a mandatory condition before going live**,
but **optional**; it is considered once the product reaches a release
maturity level. Five items are tracked as review items so that a later
review knows where to start:

| Item | Origin | What is to be checked |
|---|---|---|
| **Ring-signature vote** (E-25) | §16, maturity box | The jurors' vote runs as a Linkable Ring Signature over the registry pseudonyms. Justified, but not proven |
| **Verifiable class state** (E-29) | §16, maturity box | per-class state root over the candidate set, inclusion proofs in the case, first-acceptance acknowledgments |
| **Convergence of the per-class state roots** (E-35) | §16, maturity box | the per-class state root serves as an anchor against backdating and as a completeness check. "**Convergence of the roots is not proven** — explicit condition" |
| **Deniability instead of non-repudiation** (E-15) | Decision log | ML-DSA is dropped from message cells; authenticity is carried symmetrically |
| **FS granularity** (E-16) | Decision log | ML-KEM once per day and contact instead of per message; PQ forward secrecy under CRQC plus device access falls to day granularity. Also the prekey pool (§4) and its multi-device coupling (E-40) |

As long as no review is in hand, "registry age counts as a strong hurdle,
not as proof" applies (§16, maturity box).

#### B — Release criteria before the production launch

The five gates **G-1…G-5 from §28.10** are the yardstick for going live;
they must be satisfied **simultaneously** (E-44 point 3).

### 30.4 Work packages

The work packages WP-1…WP-7 appear with their prerequisites and
verifications below. They are **ordered by prerequisites, not by time**.

#### WP-1 — Design consistency gate

| Content | Prerequisite | End reached when |
|---|---|---|
| The architecture document is internally consistent, with no chapter left open and no architecture decision unresolved (§31 tracks what remains: measurement tasks and downstream work, not decisions) | — | No chapter is open; every architecture decision needed for the delivery layer is made; only measurement and build work remain (§31) |

Without WP-1 there is no delivery-layer implementation — building
against an inconsistent design, or against undecided parameters,
produces work that has to be redone.

#### WP-2 — Seam & Plane D API

| Package | Content | Prerequisite | Verification |
|---|---|---|---|
| AP-1a | Move non-transport code out of `lib/core/network/` into neutral modules (`clogger`, `contact_seed`, `channel_uri`, NFC) | — | Build + tests green; a pure import move |
| AP-1b | Migrate the second send path `sendInfraTo` into the service API, or document it as part of the seam | AP-1a | all callers keep working without adjustment after the move |
| AP-1 | Remediate the seam: separate the files from transport-internal state, encapsulate direct `node.<member>` accesses outside `service/`+`calls/`; **add the `SendOutcome {placing, placed, failed}` result to `sendToUser()`** (§22.5) | AP-1b | Tests green |
| AP-2 | Define the Plane D API, move calls onto it, bring along the Android video bring-up (`VideoSession.install()` in `MainActivity.kt`) | AP-1 | Call E2E green + the five reproduction cases from `docs/BUG_ANDROID_CALL_RINGTONE_ACCEPT_RACE.md` in `gui-33-video-calls` |
| AP-4a | Move `MessageStatus` onto a stable wire name (enum-index trap) | independent, any time | Daemon/GUI round trip green |
| AP-5a | Structurally rule out stubbable interface getters in the IPC client | before introducing the readiness state | Test catches stub getters |

**Bringing up the Android video path belongs to AP-2** — bring-up, not a
delivery rebuild, and therefore in WP-2.

#### WP-3 — External crypto review (parallel to WP-2; optional since E-47)

| Content | Prerequisite | End reached when |
|---|---|---|
| Review of the five items from §30.3 A | WP-1 (the constructions must be in hand as text, otherwise nothing is checkable) | Findings are in hand; conditions are incorporated or the affected construction is replaced |

WP-3 depends on WP-1, not on WP-2 — and has been **optional** since
E-47: recommended at release maturity, but not a prerequisite for the
production launch. If it is carried out, a finding can propagate onto
WP-5 (for instance if the ring-signature vote falls) — the earlier, the
cheaper.

#### WP-4 — Identity & crypto core

| Content | Prerequisite | Verification |
|---|---|---|
| Keys, HD derivation, seed phrase, identity determinism (Z-10); per-message KEM (X25519 + ML-KEM-768 hybrid); Ed25519 + ML-DSA-65 hybrid sig; **link handshake** (Elligator2 `cleona_link`, §27.4.1, E-42); pairwise secrets and tag derivation (§4, §6); FS re-derivation; prekey pool + multi-device coupling; beta/live network-channel separation (Z-11) | WP-2 (seam) | Smoke: `smoke_per_message_kem`, `smoke_mldsa_derand`, `smoke_key_rotation`, `smoke_seed_phrase_validation`, `smoke_link_handshake`, `smoke_tag_derivation` green; Z-10 byte-identical |

#### WP-5 — Cover system, reachability, delivery ways, delivery states

| Content | Prerequisite | Verification |
|---|---|---|
| **Cover system** (§5): Poisson-timed background stream beside the traffic (§5.2), platform tiers (always-on/retention-bounded, §22.6), quotas (Z-8) | WP-4 (crypto core), WP-2 (seam) | `smoke_cell`, `smoke_fountain` green; Z-5 wire-profile indistinguishable |
| **Reachability** (§6): address learning from observed traffic only, no publishing, no polling | WP-4 | Lab state transitions match §6 |
| **Delivery ways** (§7, §8): the ladder tried in parallel, first acknowledgement wins; the post box | WP-4, cover system | `smoke_ladder` green; Z-3 the ladder in parallel; Z-4 the post box |
| **Delivery states** (§9): the four states and the single acknowledgement type; large-payload lanes; **readiness** `searching`/`connecting`/`ready` (§22.7) | WP-4, delivery ways | `smoke_delivery_ack`, `smoke_readiness` green; Z-1 acknowledgement; Z-2 the four states |

#### WP-6 — Sybil & censorship, durable objects, entry cascade

| Content | Prerequisite | Verification |
|---|---|---|
| **Sybil resistance and gated reputation** (§10) | WP-4, WP-5 | `smoke_*` moderation + anti-Sybil; Z-19 moderation end-to-end |
| **Durable-object class** (§16.0): per-class state root, anti-entropy across relays, type system (missing proof → no replication), sub-budgets 6/2/2 MB; **backdating anchor** reuses the cross-partition relay-attestation primitive (§13.4.2) | WP-5 | `smoke_dauerobjekt` green; Z-5 anti-entropy convergence |
| **Entry cascade** (§11): cached entry addresses → LAN discovery → external rendezvous (Nostr), permanently, not as a booster (§11.3). On **beta** it is indispensable — the participants there have no stable addresses, so source B's gate cannot be met by construction; on **live** it may fall away once B and C carry the cold start alone | WP-4 | Z-22 entry records |

#### WP-7 — Content layer, simulator, bring-up, release

| Content | Prerequisite | Verification |
|---|---|---|
| AP-7: **fountain-erasure cache** — files (§9) and in-network updates (§26.6.1); manifest hybrid-signed, browser assembler on fountain (§26.6.5) | WP-5 | Transfer E2E; update delivery |
| Build the **network simulator** (stage 1/2, §28.9.3) and answer the scale-dependent measurement questions of §29.5 | WP-1; tool decided (E-49); cost model + hardware decided (E-54) | Metric runs with tolerance bands (T-2) |
| AP-8: cold start and rendezvous, first-launch profile path (§21), release | all previous | Field test |
| Satisfy release criteria **G-1…G-5** (§28.10) | AP-8, simulator results | G-1…G-5 green simultaneously |

Verification of AP-8: field test. The production launch requires the
release criteria G-1…G-5 (§28.10); the external crypto review (WP-3) has
been optional since E-47 and is not a prerequisite.

### 30.5 Dependencies at a glance

```
WP-1  (design consistency gate)
  ├──► WP-2  AP-1a → AP-1b → AP-1 → AP-2
  │          AP-4a (→ WP-5), AP-5a (→ WP-5)        (advance independently)
  ├──► WP-3  external crypto review                 (parallel; optional since E-47)
  └──► WP-4  identity & crypto core (link handshake, tag derivation)
              ├──► WP-5  cover + reachability + delivery ways + delivery states + readiness
              │          ├──► WP-6  Sybil + durable objects + entry cascade ──┐
              │          └──► WP-7  AP-7 fountain ─────────────────────────────┤
              │                                                               ▼
              └──►                                              WP-7  AP-8 → G-1…G-5
```

Two edges are load-bearing: **WP-2 before WP-5** protects the test base
(seam remediated before the delivery layer is implemented), **WP-1
before WP-4/WP-5** keeps implementation from starting against an
unsettled design. The production launch depends on **WP-6 and WP-7
jointly** (AP-8 = "all previous ones"), and additionally on the
moderation evidence requirement Z-19 (§28.8). AP-4a and AP-5a can be
advanced independently, but feed in as prerequisites of WP-5.

### 30.6 Items deliberately not pursued

Three items are explicitly **not** pursued — not for effort reasons, but
because the design makes them moot or solves them differently:

- **No proof-of-work admission filter.** The cell frame
  `tag | ttl | sealed_payload` has no `pow` field (§4.3); the lever
  against abuse is redundancy plus gated reputation (§10), not
  proof-of-work. `cleona_pow` has no protocol consumer (§27.3).
- **No global Merkle index.** The durable-object class uses **per-class
  state roots**, anti-entropy replicated across relays (§16.0) — a
  single global index was considered and ruled out by the §13 design
  review as a correlation surface.
- **External rendezvous is not on this list.** It belongs in §11.9 and
  §27.1 as a permanent, decided part of the cold-start cascade, not as
  an item that was tried and dropped.

### 30.7 Deferred — not required for launch

Items deliberately **not** in this build and not a prerequisite for the
production launch:

| Item | Origin |
|---|---|
| Kemeleon / uniform ML-KEM encoding (O-2) | optional points |
| Form-masquerade (benign traffic-profile imitation) — the (b)-hardening, declared boundary D1a (E-D) | §23.9.1, E-62 |
| Rendezvous phase 2 — metric-gated evolution of the entry cascade (thresholds since E-52: 50 nodes / 8 weeks / diversity floor, reversible) | §11 |
| Group calls (C-9/C-10/C-11) | §17 |
| In-call collaboration (§17.5): remote control and screen-frame transport (PipeWire/MediaProjection) | depends on the Plane D API from WP-2 |
| Threshold signatures for the update manifest (e.g., 2 of 3) — the update signature is the last remaining centralized capability (§26.7) | §26.7 |
| PQ-NIKE upgrade path for pairwise secrets — own implementation of a published candidate scheme once one is classified viable (as of 2026 none exists) | §15 |

### 30.8 Governance of this chapter

The concrete session and sprint plan is kept in the project memory, not
here — the architecture document is the architectural reference and not a
project-plan tracker. This chapter names architectural endpoints and
their order. If a work package loses its prerequisite — for instance
because the crypto review topples a construction — the graph in §30.5
is to be changed, not a date, which does not exist.

---
## 31. Platform suitability

### 31.1 What the design requires from a platform

The design requires exactly one thing from a platform: **being able to open
outbound connections regularly.** Both platform tiers — always-on and
retention-bounded (§22.6) — establish **all** delivery-layer connections
outbound; outbound connections traverse every NAT, CGNAT, and DS-Lite
without port forwarding, without hole punching, without port prediction.
**An inbound-reachable port is assumed nowhere.** The converse also
holds: where a platform *can* technically bind a privileged port, that
does not make it a door. The door role follows the always-on tier;
retention-bounded nodes stay outside it regardless of what they could
bind.

Everything beyond that determines not **whether** a message arrives,
but only **how fast** and **how much the device contributes to others.**

**The boundary of that requirement is honest and normative (E-64).** A
network that lets nothing out is not covered — Cleona is unusable there
by definition, and no in-network mechanism changes that (a node that
cannot reach out cannot relay for others either). A network that lets
**only sanctioned hosts** out is likewise not covered by a Cleona
mechanism: the sanctioned host would be a designated relay, a fixed
point excluded by the no-fixed-point rule. What E-64 does cover is the
common middle — an outbound **port** allowlist (only 80/443) — via the
transport escalation of §11. Between "uniformly blocked" and
"per-host sanctioned" there is nothing, which is why no LAN-relay
mechanism is offered (§23.9.3).

The hierarchy (Linux > macOS > Windows > Android > iOS) therefore does
not describe delivery quality — that is classless — but **how much a
device contributes to the network.**

**Inbound reachability has exactly two meanings (E-41):** it says how
much this node contributes **for others** (it accepts inbound syncs and
becomes a usable relay / door), and it is a prerequisite for **calls**
(ch. 17). It does **not** mean better reception: delivery runs outbound.
Partner counts are therefore tracked **separately** by inbound and
outbound (§22.4).

**Cellular is the last resort, not an equivalent alternative (E-41).**
If Wi-Fi, Ethernet, or VPN are available, all traffic runs over them —
including the cover stream. The rule concerns the **choice of
interface**, not the **volume**; it therefore costs no anonymity (§5).

### 31.2 Ranking

| Rank | Platform | Tier (§22.6) | Contribution to the network | Callability (§17.2) |
|---|---|---|---|---|
| 1 | Linux Desktop | always-on | highest: full-rate cover stream, unrestricted mailbox-holding for others, full retention, automatic fountain-erasure cache (§9) | inbound within seconds |
| 2 | macOS | always-on | same as Linux | inbound within seconds |
| 3 | Windows Desktop | always-on | same as Linux, after platform-specific fixes | inbound within seconds |
| 4 | Android | retention-bounded | limited: cover stream and delivery ladder run mainly in the foreground service window, retention bounded (§22.6) | inbound within seconds (foreground service) |
| 5 | iOS | retention-bounded | lowest: cover stream only while foregrounded, burst frequency fully platform-determined | **no inbound calls with the app closed** |

The delivery **guarantee** is the same in all five rows. What differs is
latency (§7, §8), contribution (§22.6), and callability (§17.2).

### 31.3 The platforms individually

**Desktop.** Always-on tier plus the automatic fountain-erasure cache
for files and in-network updates (§9, §26.6.1); inbound calls within
seconds (§17.2).

#### Tier 1 — Linux desktop

The reference platform. The daemon runs without restrictions, IPC over
Unix sockets, the operating system limits neither background execution
nor network access. **Linux contributes the most.** Specifically:

- **Always-on tier** with a continuous cover stream and a rough
  guideline of ~40–50 MB/day cover plus bulk (§5).
- **Automatic fountain-erasure cache** for the third file-transfer tier
  (fountain-erasure cache on always-on relays, §9) — this role is
  occupied exclusively by desktop installations.
- **Full retention** (always-on relays, 14 days default).
- **Accepts inbound syncs**, thus a usable relay / door for nodes that
  can themselves only go outbound (§22.4), and **callable** (§17.2).
- Reaches `ready` (§22.7) as soon as two neighbours have answered
  (§22.7.1).

Offline recovery is **platform-equal**: it runs over the recovery
bundle the user planted themselves (§6) and works identically on every
platform.

#### Tier 2 — macOS

Architecturally almost identical to Linux: Unix foundation, daemon plus
GUI over Unix-socket IPC, no limits on background execution, no sandbox
enforcement outside App Store distribution. macOS is always-on like
Linux, with the same fountain-cache role. The only friction sits on the
distribution side — Apple requires notarization and Gatekeeper approval,
and builds need a macOS runner. That is distribution friction, not a
network property; at runtime the experience matches Linux.

#### Tier 3 — Windows desktop

Conceptually well suited — Windows permits background services without
restriction and ports can be opened freely. Windows reaches **full
contribution after three platform-specific fixes**; they apply because
the link layer (§11) uses ordinary UDP sockets:

- **IOCP behavior:** Dart's `RawDatagramSocket` showed a loss rate of
  87.9% under Windows, caused by the behavior of the I/O Completion
  Ports. The fix is a native C shim (`libcleona_net`, direct
  `WSASendTo`); it sits in the link layer (§11).
- **IPC over TCP + auth token** instead of Unix sockets — additional
  complexity.
- **Process management** (scheduled task, PID and lock files) is more
  error-prone than under Unix.

The development effort per Windows quirk is disproportionately high; that
is a project problem, not a user problem.

#### Tier 4 — Android

**Android.** The foreground service is canonical; it keeps the cover
stream (§5) and the delivery ladder (§7, §8) alive — few timers, few
sockets, little battery per delivery. Inbound calls ring in the
background within seconds (always-on cadence of the FGS, §17.2).

In addition:

- **Tier: retention-bounded** (§22.6) — the cover stream and delivery
  ladder run mainly within the foreground service window. Guideline
  2–5 MB/day cover (§22.6).
- **No separate daemon** — everything runs in-process. The
  Application's own `FlutterEngine` (created in
  `CleonaApplication.onCreate()`, returned via
  `provideFlutterEngine()`) keeps the Dart isolate alive across
  Activity destruction and Share-Intent restarts.
- **CGNAT/DS-Lite has no consequence for the delivery layer
  (important).** Outbound connections traverse CGNAT and DS-Lite
  without port forwarding, and there is no relay cascade. CGNAT affects
  only **Plane D** (calls, §17.3) — there it can mean: no call, messaging
  unaffected.
- **Doze costs latency, not messages.** Deep Doze suspends network
  access after roughly 30 minutes of screen-off idle time. A message
  left in a post box (§8.2) waits there; Doze delays when the device
  comes back to collect it, it costs no message. The
  same applies to OEM battery management (Samsung, Xiaomi, Huawei),
  which can restrict beyond standard Doze — the dontkillmyapp.com note
  is useful but not urgent.
- **Connection type and saver mode (E-40/E-41).** Wi-Fi, Ethernet, or
  VPN take precedence over cellular, for all traffic. Data-saver mode is
  **user-side and never automatic**, not even on a detected metered
  connection; the app may suggest it. The typing indicator is sent only
  in the **foreground and only over Wi-Fi** (E-40).
- **Permissions and notification text:** §16.2.

#### Tier 5 — iOS

**iOS.** An iOS node is outbound-only **in effect**, and the reason is
Apple's process lifecycle, not the retention-bounded tier: a suspended
app holds no socket, so there is nothing to arrive at. Android shares
the retention-bounded tier but not this consequence — it does accept
inbound (§22.6); the tier bounds retention and background cover-stream
cadence, not direction. Sleeping = offline is therefore the center of
gravity here, waking up is an outbound connection plus a check against
what has arrived (§7, §8) and fits into a background-refresh window.
There are no keepalives. The delivery *guarantee* is platform-equal; the
delivery *moment* with the app closed is Apple policy (the APNs
rejection stands — push wake-up was evaluated and rejected, Appendix D, D-18).
**Calls (E-26):** with the app closed, iOS has **no inbound calls** — the
120-s signaling TTL sits below every guaranteed background window. That
is a documented platform limit, not an error class (callability matrix:
§17.2).

In addition:

- **Background execution:** no foreground-service equivalent,
  BGTaskScheduler with a dual strategy of two independently registered
  task types (BGAppRefreshTask ~30 s runtime, BGProcessingTask with a
  minute-scale budget), to maximize wake frequency within Apple's
  constraints. A permanently open UDP socket in the background is not
  sustainable on iOS. **These windows suffice for the delivery ladder
  and cover exchange** (§7, §8), because no socket needs to stay open
  permanently.
- **The daily figure of 2–5 MB is an upper bound for iOS, not an
  expectation** — it assumes a burst frequency that is fully determined
  by the platform (§22.6, explicitly marked as unsubstantiated). iOS
  has no sustained background cover stream, so delivery timing with the
  app closed follows Apple's background windows, not the steady-state
  figures of §7/§8; that is platform physics, not a weakness of the
  delivery layer.
- **Contribution:** the lowest of all five platforms. iOS accepts no
  inbound syncs and occupies no fountain-cache role. That is not a
  misconfiguration, but the role.

**Four Dart-socket quirks apply on iOS** — they are operating-system
behavior and independent of the transport model:

*Send path.* `RawDatagramSocket.send()` silently returns 0 for all
destinations (errno 64/65 from the kqueue path). `IosUdpSender` calls
native `sendto()` on the file descriptor of the Dart socket.

*Receive path (kqueue stall).* After a series of native `sendto()`
calls, Dart's kqueue loop no longer delivers any
`RawSocketEvent.read`; the kernel receive buffer fills up without a
handler ever firing. Fix: a 50 ms polling timer that calls native
`recvfrom()` on the IPv4 and the IPv6 descriptor. This is the **primary**
receive path on iOS; the Dart kqueue handlers are only a secondary path
that occasionally works. Diagnosis every 10 s via `recvPeek()` on both
descriptors; EBADF (-9) triggers socket recovery. In addition, a
30-second silence watchdog triggers the same recovery if not a single
packet arrives over either path for 30 seconds.

*Death of the file descriptor.* iOS closes Dart's UDP descriptors about
40–60 s after app start (EBADF, errno 9, on IPv4 and IPv6), apparently in
connection with the finalization of the Wi-Fi route. The gap between
descriptor death and recovery is at most one timer tick (10 s); the
sockets' `onError` streams form a faster parallel detection path for
the same situation.

*Asynchronous errors.* Fire-and-forget sends throw `SocketException`
**asynchronously** over the socket's error stream, not synchronously
from `send()`. Every `RawDatagramSocket.listen()` call in
iOS-reachable code MUST have an `onError` handler.

**Recovery after death of the file descriptor.** The procedure is:
**bind fresh sockets, re-read the descriptor, re-select sync partners**
(§22.4). Unsent messages sit in the outbox and are offered again on the next
opportunity (§9.3) — there is no persistent SendQueue and no
timer-based retry.

These four quirks concern only the foreground session. The BGTask path
opens fresh sockets on every wake cycle and closes them before
completion, thereby avoiding the descriptor problem entirely.

### 31.4 Summary

The platform question breaks down into two separate statements:

1. **The delivery guarantee is platform-equal.** A message left in a
   post box (§8.2) waits there until the recipient returns and collects
   it (§9.1) — every one of the five platforms can do this. No device
   "misses" messages because it was asleep. The durable-object class
   (§16.0) carries what is load-bearing beyond that: delivery does not
   depend on any device staying reachable.
2. **The hierarchy measures contribution and callability.** Desktop
   systems run the always-on tier, hold the fountain-erasure caches,
   and are callable. Mobile devices predominantly receive and
   contribute little — Android measurably more than iOS.

**For the user recommendation:**

- **For delivery**, the choice of platform is immaterial; only latency
  differs (foreground 1–3 s everywhere, background seconds on always-on
  and Android, up to ~5 min for retention-bounded bursts, iOS with the
  app closed platform-determined — §8).
- **For calls**, the called side needs inbound reachability; iOS with
  the app closed cannot accept calls (§17.2).
- **Anyone who wants to help the network** keeps a desktop installation
  running — that is the only place where the choice of platform still
  says something about contribution.

### 31.5 Open points of this chapter

Decided numbers of this chapter are recorded at the respective
paragraph.

| # | Point | Options / status |
|---|---|---|
| K31-2 | **The iOS daily figure (2–5 MB) is unsubstantiated** and already marked as such in the document (§22.6) | measure once an iOS retention-bounded node runs in the lab; until then, treat it as an upper bound, not an expectation |
| K31-3 | ~~**Group-call topology** is open across platforms (C-9/C-10/C-11); an overlay multicast tree assumes addressable participants, which the design does not have~~ **CLOSED by §17.7.** The objection held, but not as stated: *inside* a call participants are addressable (address candidates and punch windows, §17.3). What does not scale is the *number* of pairs — 300 at 25 participants, 1225 at 50 — and that is exactly what the threshold in §17.1.1 turns on. Topology is now per plane: control mesh to 25 then star, voice a flat crystal, video a deeper one | §17.7 |
| K31-5 | **Windows process management.** An always-on node without an inbound port poses its own requirements on scheduled task, PID, and lock files | inventory before WP-5; no known blocker, but unverified |

---

## Appendix A — Where the parameters are

Every tunable value is defined **once**, in the chapter that uses it, and
this appendix is an index into those chapters — not a second copy. A
table of values kept apart from its chapter drifts out of step with it
and nobody notices.

| Parameter | Defined in |
|---|---|
| key sizes, seal and signature sizes, rotation intervals | §4 |
| cover packet size, mean rate, minimum gap, addressing | §5.2, §5.3 |
| keep-alive intervals and target count | §8.1 |
| multicast group, call port, call repeats (neighbour call, search call) | §7.2 |
| public-address discovery, knock attempts and interval | §7.3 |
| forwarding hop count, loop memory, packet identifier | §8.1 |
| post box: neighbours, acknowledgements, retention, per-day-value cap | §8.2 |
| message identifier length, acknowledgement rules | §9.2 |
| media size threshold, stripe width `K`, block size, fragment surplus `d`, relay size cap `C` | §9.4 |
| part size, header layout, re-request window and rounds, discard timer | §11 |
| invitation card layout and sizes, code length, expiry, buffer sizes, field limits, channel byte | §15.2, §15.12 |
| admission cost | §10 |
| call frame sizes and budgets | §17 |

## Appendix B — Declared limits

What the design does **not** protect, at the level a threat model states
it. Every entry is a consequence of a property elsewhere in the
document, not a defect awaiting a fix. Limits that are specific to one
mechanism (a relay's forwarding, a lookup, a reply block, a media lane)
are stated at that mechanism's own chapter (§7–§11, §17) rather than
restated here — this list keeps only the limits that hold at the level
of the whole design:

| # | Limit | Class | Where |
|---|---|---|---|
| B-1 | **Global Passive Adversary.** Against an adversary who sees the full middle and global timing, end-to-end correlation engages and the required cover rate rises toward Nym scale. Content stays safe; linkability degrades gracefully | anonymity | §2 |
| B-4 | **Whitelist total filter.** A state may block the protocol at its border. Content and relationships stay safe; reachability does not | availability | §10 |
| B-5 | **Tool-user recognizability.** A permanently-on, low-rate, uniformly-encrypted stream remains weakly recognizable as an anonymity tool. This is recognition, not anonymity; full form masquerade is deferred (§30.7) | recognition | §5 |
| B-6 | **Closed-network membership fingerprint.** A state running a node can confirm that a captured public key belongs to the network. It reveals membership, not relationships | membership | §11 |
| B-9 | **Deletion is local.** A deleted message disappears on the devices, not from a neighbour that already forwarded or holds a copy in its post box | forensics | §21 |
| B-10 | **Calls disclose a conversation.** Real time requires a consented direct channel: an observer sees that two parties are talking, without learning which two | metadata | §17 |
| B-11 | **Public channels are enumerable.** The tag secret is published, so decoys act as a dilution factor, not as an anonymity set | anonymity | §23 |
| B-12 | **Moderation acts on objects, not persons.** No account-level sanction exists to reach for | product | §16 |

## Optional points

**Decided numbers have been removed from this list** — the decision,
rejected alternatives, and price sit at the respective chapter location.
What remains are exclusively **optional** items: none is a prerequisite
for the production launch (§30.7), none blocks an implementation.

| # | Topic | Class |
|---|---|---|
| O-2 | Kemeleon / uniform ML-KEM encoding | Improvement, not a prerequisite (§30.7) |
| O-8 | Retention-bounded-node upload anonymity against the sync partner | Improvement, not a prerequisite (§30.7); tracked against the retention-bounded tier (§22.6) |

---

## Appendix C — Open work

**No decision is open in the delivery layer.** Open points that concern
a single chapter are kept in that chapter's own open-points section;
where one affects an implementation choice, the chapter says so at the
point of use rather than deferring silently. What remains document-wide
is measurement and build work:

- The scale-dependent measurements of §29.5, answered by the network
  simulator (§28.9) — among them the jury draw under network size
  (§28.8), which follows the lab evidence for Z-19 and does not replace
  it.
- The cross-platform receipt-latency mix (§8, §12).
- The media-lane measurement obligations of §9.4/§17.6: throughput on
  the weakest target platform, device cost on battery and CPU, real
  bulk-holder capacity, the recognizability of a transfer, the
  volunteer's real load against `C` = 25 MB, and the share of transfers
  that take the stream lane at that cap — none of these change the
  design; each calibrates a figure already named at its own chapter,
  not here.
- The moderation evidence Z-19 in the lab (§28.8): first the T-5 preset
  with simulated registry aging is built (§28.11); then the procedure
  runs end to end — report → case → jury → verdict → consequence — with
  ≥ 5 independent jurors across multiple nodes, the structured event
  trail of §28.8 and at least one GUI verification per consequence. A
  run below the minimum juror count is a failure, not a skip.
- The participant count up to which video is offered in a group call
  (§17.7).
- The build order (§30) and its release criteria G-1…G-5 (§28.10); a
  further pass over §8; the test areas at T-3 and T-6 (§28.11); the
  review items from §30.3 A (optional, E-47); UI/i18n determinations
  (§15-O-1…O-5, K16-2…K16-4, I-2, I-3, §25-O-1…O-4/O-6, STO-4,
  CAL-3/CAL-4/CAL-7, POLL-4, C-9/C-10/C-11, L-2/L-4/L-5, R-3 procedural
  rule); the threat-model document must be kept in step with this
  chapter.

**No chapter waits on another chapter.** The measurements above gate
implementation; nothing in the delivery layer waits on a decision. What
remains is build work and the observation items named above.

---

## Appendix D — Settled decisions

These are decided by the owner. They are **not open questions**. A text
or a piece of code that contradicts one of them is **drift** and is
corrected towards the decision — it is reported as drift, never raised
again as a question. A settled decision is reopened only by the owner,
through a proposal with before, after and rationale.

| # | Decision | Decided | Normative text |
|---|---|---|---|
| D-1 | Delivery works on its own; concealment runs beside it and carries nothing a delivery depends on | owner, 13.09.2026 (S383, full reset of the delivery layer) | §3.1 |
| D-2 | One way to send — no fast or private mode, no per-chat setting; the V4.1 two-mode design is withdrawn | owner, 13.09.2026 (S383) | §3.3, §12.1 |
| D-3 | All applicable ladder steps start together; the first acknowledgement wins; sequential escalation is prohibited | normative since 4.2 | §3.4, §7.1 |
| D-4 | Messages never go to a public address (step 2); step 2 serves the own address and calls | owner, 17.09.2026 (D1 = a) | §7.1, §7.3 |
| D-5 | Step 3 by codes per pair, direction and UTC day; `K_AB` hybrid with `s_AB` | owner, 17.09.2026 (proposal M, D2 = a) | §4.3, §8.1 |
| D-6 | Post box: three neighbours, two acknowledgements, 7 days, at most 100 packets **per day value**, proof of work `D_box` = 18 bit | owner, 15.09.2026 (`D_box`) and 17.09.2026 (day values) | §8.2 |
| D-7 | The cover stream always runs and is not a setting; 1 packet / 60 s on metered links; empty packets may be reduced only on unmetered W/LAN (switch, default off) | owner, 17.09.2026 (W2 = b for the metered rate) | §5.1, §5.3, §12.7 |
| D-8 | Keep-alive behind translation or a firewall: interval measured per network, IPv6 60 s and IPv4 30 s until measured, IPv4 rests where IPv6 carries | owner, 17.09.2026 (E1), changed 24.09.2026 (see also D-27) | §8.1 |
| D-9 | Nothing periodic in idle; the post box and the neighbourhood are asked only at edges | normative since 4.2 | §1.2, §5.4, §8.2, §11.8 |
| D-10 | Stateless per-message KEM (X25519 + ML-KEM-768); no Double Ratchet | normative | §4.2, §4.3 |
| D-11 | The identifier is free of secrets; network entry is bound to no maintainer key — that key signs updates only | owner, 15.09.2026 (identifier = A) | §4.1, §26.7 |
| D-12 | No address, port, host or environment variable pointing at an entry node is built into the application or its configuration; the bootstrap is a node like any other; external records are start help only | owner (§11.7, §26.6 principle 5) | §11.7, §11.9 |
| D-13 | Four delivery states, not extensible; a recipient who is offline is not an error | normative | §9.1 |
| D-14 | Relay limit `C` = 25 MB — not to be renegotiated; media pieces Reed-Solomon `K` = 7, `d` = 4 | owner, 14.09.2026 | §9.4 |
| D-15 | Groups: N ordinary pairwise deliveries up to N ≤ 16; above, a private channel under `K_C` | owner, 16.09.2026 | §16.2 |
| D-16 | A contact exists only by explicit acceptance; automatic acceptance only for an in-person hand-over (QR shown to the present person, NFC); the medium decides, there is no choice of hand-over class | owner (§12.5); medium rule 24.09.2026 | §12.5, §15.5 |
| D-17 | No social recovery: no guardians, no split secret; the 24 words and surviving devices are the only ways back | owner | §13.8 |
| D-18 | Android: the foreground service with its persistent notification is the canonical background path. Every push variant (FCM, APNs, UnifiedPush, WebPush, per-peer rotation) is rejected. The battery-optimisation **switch in the settings** is removed; the **exemption request at first start** exists since 22.07.2026 as the fix for Doze cutting the network — only the placement of that dialog is open (§23.9 K23-3) | owner, 26.04.2026 (push rejected, switch removed); 22.07.2026 (first-start request) | §12.6, §23.2 |
| D-19 | One daemon, one data port for all identities of a device; all identities are active at once | owner, 14.09.2026 (S385) | §4.5.1, §11.1 |
| D-20 | The DHT-based anti-Sybil reachability check is removed; reputation is gated, not weighted | removed S368 (05.09.2026); E-B = B1 | §10.3 |
| D-21 | 4.2 is fully separate from V3: no migration, no old profiles, no V3 wire format, no field "for older peers"; V3.2.2 is frozen as the fallback | owner, 15.09.2026 | `docs/FALLBACK_V322.md` |
| D-22 | Persistence in three forms; messages in an encrypted SQLite database per identity (SQLite3 Multiple Ciphers, no plaintext temp); the "decrypted temp file, flush every 60 s" design is rejected | owner | §4.5.3, §21.4.1 |
| D-23 | Update: collected and assembled automatically, offered only when complete and verified, "Install" starts without a second question; no downgrade; an update comes only from a hand-signed manifest | owner, 14.09.2026 | §26.5.4, §26.6 |
| D-24 | Interface precedence: wired, Wi-Fi and VPN before cellular | owner, 16.09.2026 (S390) | §22.4.1, §23.1 |
| D-25 | The card carries up to four own addresses; they are classified by the reader, not by the issuer; the neighbour address only when verified | owner, 16.09.2026 (S390) | §15.2 |
| D-26 | Fixed neighbours come from contacts: up to three currently reachable contacts' devices, replaced at edges, fixed rather than redrawn; the card never names a contact; one `0x22` fans out to up to three, only for registered devices; the list rides in acknowledgements and messages; a contact can be excluded | owner, 24.09.2026 (proposal "contacts as fixed neighbours", version 3) | §5.2, §8.1, §9.2, §15.2, §15.10 |
| D-27 | Keep-alive only where a check shows it is needed: a family found open from outside needs none; IPv4 to at most one neighbour; IPv6 to each fixed contact neighbour, all in one radio wake | owner, 24.09.2026 (version 3) | §8.1 |
