// Storing and harvest on the wire.
//
// WHERE THE FORMAT BELONGS. AP-3a froze four frame types and
// explicitly left the control channel `0x04` open — its INNER
// format is not part of the frozen wire format. Exactly there
// storing and harvest belong, and that is why no new outer
// type is invented here.
//
// WHAT THE PARTNER LEARNS IN THE PROCESS — and why that is fine. A
// relay that is to store a cell under a tag MUST know the tag;
// a relay that answers a harvest must know the queried
// tags. Both are unavoidable and both are harmless as long as
// the tag cannot be computed without `K_AB` (§10.1) and the query
// is decoy-mixed (§6). The control channel furthermore lies WITHIN
// the link sealing — on the wire an observer only sees a
// cell like any other.
//
// NO ANSWER SIZE AS A SIGNAL. A harvest answer carries as many
// cells as were found — that is a number the partner
// knows anyway (it picked them out). To the outside it stays
// invisible, because the answer also runs in cells of fixed size.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../crypto/sodium_ffi.dart';
import 'package:cleona/core/sync/entry_record.dart';
import 'harvest_memo.dart' show kCellDigestBytes, kHarvestHaveSlots;

/// The frame body of a cell (AP-3a, `core/link/cell.dart`: 1172 − 3).
///
/// Until S358 it stood three times as a bare 1169 in this file — once in
/// [kMaxPlaceContentBytes], once as a gate in `buildHarvestRequest`,
/// once in the text of [kMaxFindNodePositions]. Three copies of one number from
/// which three different capacities follow are three opportunities
/// to forget one of them.
const int kControlBodyBytes = 1169;

/// The trailer of an AES-GCM seal (`cryptoAeadAes256GcmABytes`).
const int kAeadTagBytes = 16;

/// The messages of the control channel that the delivery layer needs.
abstract final class SecureOp {
  /// Store this cell under this tag.
  static const int place = 0x01;

  /// Give me everything under these tags.
  static const int harvestRequest = 0x02;

  /// Here is what I found.
  static const int harvestResponse = 0x03;

  /// I know these node positions.
  ///
  /// Without something like this a node only knows who connected to it —
  /// and then there is no lookup, only a neighbourhood.
  ///
  /// **What this reveals to the partner:** which RELAYS I know. Relays are
  /// infrastructure, not contacts; whoever knows them learns nothing about
  /// my acquaintances. What he learns is the layout of my
  /// neighbourhood in the metric space — that is why a LIMITED and
  /// random selection is announced, not the whole stock.
  static const int peerAnnounce = 0x04;

  /// Ask for the entry records for these positions.
  ///
  /// A position says WHERE a node lies; one cannot reach it with that.
  /// Whoever really wants to address an announced position fetches
  /// the static material with this.
  static const int entryRequest = 0x05;

  /// The requested records. Larger than one cell, so
  /// fragmented (0x02/0x03).
  static const int entryResponse = 0x06;

  /// Give me entry records — any, not specific ones.
  ///
  /// Step 3 of the entry cascade (§11): "the entry cascade hands the list out
  /// on request". From a single reached neighbour a
  /// neighbourhood arises this way; without that a node would stay stuck on the one it
  /// happened to find first.
  static const int entrySetRequest = 0x07;

  /// The relay confirms having stored a cell.
  ///
  /// The TRANSPORT ack from `delivery_state.dart` — fast, useful and
  /// not trustworthy. It does NOT flip „delivered"; only the
  /// E2E receipt of the receiver can do that. What it serves for then: it is the proof
  /// that this relay CAN store at all, and exactly on that
  /// §22.7 bases readiness — „evidence, not acquaintance".
  static const int placeAck = 0x08;

  /// Which nodes do you know near this point?
  ///
  /// THE QUESTION THAT WAS MISSING ON THE WIRE UNTIL S356. `iterativeLookup` was
  /// built and had no caller — not because the caller was missing,
  /// but because there was nothing it could have handed into
  /// `LookupQuery`. None of the eight opcodes before it is
  /// targeted: [peerAnnounce] names a RANDOM selection (so that
  /// the answer does not reveal the own neighbourhood), [entryRequest]
  /// names EXPLICIT positions (so one must already know them), and
  /// [entrySetRequest] fetches ANY. Without this question §9.1 computes
  /// responsibility against the own table instead of against the network —
  /// and exactly that made delivery mute on 29.08.
  ///
  /// **The search point lies in the seal, the target relay does not.** That is the
  /// difference from the harvest request, and it is the whole purpose: a
  /// forwarding hop must know WHERE the frame goes, and must
  /// not know WHAT is being searched for. `H(T ‖ e)` is computed from the tag,
  /// and the tag is the mailbox line of a pair.
  static const int findNode = 0x09;

  /// The answer to it: positions, not records.
  ///
  /// WHY ONLY POSITIONS. The same two-stage approach as with
  /// [peerAnnounce]/[entryRequest] (see `entry_record.dart`): a
  /// position costs 32 B, a record over 1.2 KB and thus two
  /// cells. Twenty records would be forty cells — more than five
  /// minutes of sending time for a single answer. Twenty positions are
  /// 658 B and fit into ONE cell. Whoever really wants to address a find
  /// fetches its record afterwards with [entryRequest].
  static const int findNodeResponse = 0x0a;

  /// A search request in an onion shell (E-L, §9.1 finding 1).
  ///
  /// ── WHY A SECOND WRAPPING AROUND AN ALREADY SEALED FRAME ──────
  ///
  /// [findNode] seals the SEARCH POINT, but not the TARGET RELAY — that
  /// must lie open, otherwise no hop can forward. Thus the
  /// first hop learns two things which together yield the linkage that
  /// §10.1 declares closed:
  ///
  ///   1. WHO is searching. `hops == kMaxPlaceHops` exists only at the originator;
  ///      a neighbour that sees this value knows it with certainty.
  ///   2. WHAT FOR. The target relay is, according to the searcher's table, the
  ///      nearest node to the search point — measured (S376, 800 nodes)
  ///      it shares on average 6.7 leading bits with `H(T ‖ e)`.
  ///
  /// This frame separates the two. It openly names a BLIND RELAY that
  /// has nothing to do with the search point (chosen randomly, see
  /// `V41Node._blindrelaisKette`), and carries the frame underneath in
  /// a seal only this blind relay can open.
  ///
  /// ── SINCE S377 THERE ARE TWO SHELLS ─────────────────────────────────
  ///
  /// The number stands as [kLookupOnionShells] and is the adjusting screw
  /// (owner decision V-9a of 09.09.2026 = B). The frame is
  /// NESTABLE: the payload of a shell is either the
  /// [findNode] itself or again a shell. On the wire format that changes
  /// nothing — the same header, the same splitting, the same rails
  /// ([kForwardableOps], `decrementHops`, `_amTarget`, `nextHopToward`,
  /// `PendingRequests`). What changes is solely the permissible
  /// LENGTH, and that is at the same time the depth cap ([lookupOnionDepth]).
  ///
  /// The path thus falls into `kLookupOnionShells + 1` legs:
  ///
  ///     A → … → r1        outermost identifier, open
  ///     r1 → … → r2       second identifier, was sealed in shell 1
  ///     r2 → … → target   third identifier, was sealed in shell 2
  ///
  /// After that:
  ///
  ///   * the first hop and all hops up to `r1` see ONLY `r1` — not the
  ///     target relay, not the search point, not `r2`;
  ///   * `r1` sees `r2`, but neither the searcher nor the search point
  ///     nor the target relay (the frame came over a neighbour, and
  ///     the hop counter no longer stands at the initial value);
  ///   * `r2` sees the target relay, but not the searcher;
  ///   * the target relay sees the search point as before and as sender
  ///     `r2` — exactly what §9.1 demands normatively („The queried node
  ///     then sees r2's address, not the seeker's").
  ///
  /// The property gained is a NUMBER, not a new quality: a
  /// collusion now needs `kLookupOnionShells + 1 = 3` nodes instead of
  /// two. No single node ever saw both ends; the first shell already
  /// achieved that.
  ///
  /// ONE IDENTIFIER PER LEG, AND THAT IS NO ORNAMENT. The outermost
  /// stands in plaintext (the return path of `PendingRequests` hangs
  /// on it), each further one lies one shell deeper. Without the separation
  /// THE SAME identifier would carry several legs of the path — and a node
  /// that lies on two would then overwrite its first return path
  /// (`PendingRequests.remember`, same identifier from another neighbour).
  /// The second gain falls out in the process: first hop and target relay have
  /// no shared identifier any more over which they could
  /// collude.
  ///
  /// WHAT THE RECEIVER CAN CHECK OF THIS, AND WHAT NOT. Every
  /// blind relay sees exactly the two identifiers of the two legs that
  /// it connects, and rejects them if they are equal
  /// (`DeliveryNode`). The identifiers of NON-neighbouring legs — with
  /// two shells the first and the third — are seen by not a single
  /// node; this pairing is structurally not checkable at the receiver
  /// and is guaranteed by the searcher (`kLookupOnionShells + 1`
  /// independent 16-B random values). Whoever deliberately chooses them equal
  /// only smashes the return path of his OWN search.
  static const int findNodeOnion = 0x0b;
}

/// How much content a stored item carries.
///
/// **A stored item carries NO onion.** The Speed path puts a finished
/// [kControlBodyBytes] cell on the wire; the Secure storing stores the
/// sealed spore, and that must fit into the control frame. Whoever
/// wants to put a whole cell in here arrives at 1202 B and needs
/// fragmentation (frame types 0x02/0x03) — two cells per stored item, and
/// that multiplies with every family and every responsible one. The
/// layout avoids that.
///
/// Header: `op(1) ‖ hops(1) ‖ ziel(32) ‖ eph(32) ‖ nonce(12)`, plus inside
/// the retention class (1) and the tag (32), outside the AEAD suffix
/// (16).
///
/// **1043 -> 1042 with S358.** The one byte is the
/// retention class ([kRetentionNormal]/[kRetentionSignal]); why it
/// must exist is at [kRetentionSignal]. Measured whom it breaks: the
/// largest payload this layer accepts at all is
/// `V41Node.maxPayloadBytes` = `min(kMaxPlaceContentBytes,
/// kMaxOnionMessageBytes)` — and `kMaxOnionMessageBytes` is 1041
/// (`onion.dart`), i.e. SMALLER than both values. The minimum does not change
/// through the byte, and no send path loses a payload that
/// went through before.
const int kMaxPlaceContentBytes =
    kControlBodyBytes - 1 - 1 - 32 - 32 - 12 - kAeadTagBytes - 32 - 1;

/// Retention class: the ordinary period (`keepEpochs`,
/// `kNormalKeepEpochs` = **14** epochs, §21.1 „14 d default").
///
/// **Until S363 this said „3 epochs"**, and that was the actual state: the
/// default of `SecureStore.keepEpochs` hung on `kHarvestEpochs`,
/// i.e. on the subscription depth from §22.4.1. Owner decision D2 of
/// 03.09.2026 separated the two quantities; the derivation is at
/// `kNormalKeepEpochs` in `secure_mode.dart`.
const int kRetentionNormal = 0;

/// Retention class: the short period of call signalling.
///
/// ── WHY A SECOND CLASS (§17.2, owner decision 2026-08-31) ────
///
/// §17.2 demands verbatim a „**Short ,interactive' delivery TTL
/// (120 s)** […] It buys **freshness** (an INVITE cannot ring days later)
/// and keeps dead ring signals off the relays."
///
/// Until S358 there was ONE period for everything: `SecureStore.keepEpochs` times
/// `kEpochSeconds` = 86400 — back then three days (since S363 fourteen, see
/// `kRetentionNormal`), for an INVITE cell just as for a
/// text. The sentence from §17.2 did not
/// apply, and `delivery_api.dart` had carried that since S357 as an open finding
/// at `kInteractiveDeliveryTtl`.
///
/// **THE CLASS STANDS IN THE SEAL, NOT IN THE HEADER.** The owner has
/// conceded that the class becomes „visible on the wire"; here however it becomes visible
/// only to whoever OPENS the stored item — i.e. to the
/// responsible relay, which holds the cell anyway and MUST apply its period.
/// A forwarding hop does not see it. That is
/// a smaller price than conceded, and it is the right layout:
/// if the class stood in the plaintext header, every hop on the path could
/// record when a pair is on the phone — exactly the linkage that
/// §9.1/E-L wants to avoid.
///
/// **WHAT THIS DOES NOT COVER, and that is measured, not assumed:**
/// the blind storing at the local minimum (`BlindStore`) by precondition cannot open the stored item
/// and therefore does not see the class;
/// a blindly held signal cell stays for `kBlindHoldKeepEpochs`
/// node epochs (until S363 this number was called `kHarvestEpochs`; the value
/// 3 has stayed the same, the reasoning is now at its
/// own constant). That is a capped remainder (64 entries, §11.2) and
/// no delivery path — a blindly held cell is forwarded, not
/// harvested. Whoever wants to close it needs the class in the plaintext header
/// and pays for it with the paragraph above.
const int kRetentionSignal = 1;

/// Retention class: the LONG period of management deliveries.
///
/// ── THE DECISION (owner, 01.09.2026) ──────────────────────────
///
/// Verbatim: „the recovery phrase must survive at least 31 days offline (not from
/// creation — that would be pointless anyway)."
///
/// The addition in brackets is the core and determines the construction: the
/// period runs from ARRIVAL at the holding relay, not from the
/// creation of the recovery phrase. Whoever loses his device has
/// 31 days from the day of the last renewal — not from the day on which
/// he wrote down the 24 words. Exactly so the
/// `SecureStore` stamps anyway (`retentionBucket` or the node epoch of
/// arrival, never a claim of the sender).
///
/// ── WHAT THE DOCUMENT SAYS ABOUT IT ────────────────────────────────────
///
/// §13.3.4 names for the rescue bundle „TTL 31 days, recovery epoch
/// 14 days"; §14.4 lists for the key package „management-TTL
/// delivery, 31 days" and §14.9 the sentence „A device that was switched off
/// for more than 31 days is …"; §21.1 combines both classes in one line
/// : „TTL expiry (**14 d default, 31 d for management types**)".
/// So there are THREE classes, not two — and this one here is the
/// third.
///
/// ── WHY A THIRD VALUE AND NOT RAISING THE NORMAL PERIOD ─────
///
/// Because they buy different things. The normal period carries the
/// ordinary mail; holding it for 31 days would cost every relay
/// ten times its current delivery storage, without any delivery
/// succeeding that failed before — a message that
/// no one harvests within days will not be collected in a month
/// either. The rescue bundle by contrast is BY CONSTRUCTION only
/// needed when no one has been there for a long time.
///
/// ── THE NUMBER, CALCULATED ─────────────────────────────────────────────
///
/// [kManagementKeepEpochs] = 31 node epochs of `kEpochSeconds` =
/// 86 400 s each. §21.3.2 calculates the delivery storage of a desktop node
/// for the ordinary class; the management class comes on top and
/// is populated orders of magnitude more thinly: one rescue bundle per
/// USER and renewal period of 14 days, not per message.
///
/// ── A LIMIT THAT CANNOT BE CLOSED HERE ───────────────────
///
/// §21.3.3 sets 48 h for MOBILE nodes as the normative upper limit of the
/// delivery storage. A mobile relay in the responsibility set therefore throws
/// the bundle away after two days, whatever class is on it
/// — **the rescue bundle can structurally only be held by
/// desktop relays.** That is stated nowhere in §13 and is
/// reported, not secretly healed here: this constant cannot
/// heal it, because it describes the class and not the platform.
///
/// **ADDENDUM (option C, 02.09.2026):** the 48-h period itself is NOT
/// built — only the second half of §21.3.3 point 1, the total byte
/// cap (`kMobileSecureStoreCapBytes`, `SecureStore.maxTotalBytes`). It
/// displaces class-prioritised (management last), thus gives the
/// management class a real but FINITE priority — no
/// substitute for the statement above: a mobile relay under
/// continuous load still clears it, only later than a normal cell instead of
/// flatly after 48 h.
const int kRetentionManagement = 2;

/// Does [retention] count as a retention class of this version?
///
/// ONE PLACE where the set of valid classes stands. Before, it
/// was written out twice as `!= a && != b` — when adding
/// the third class, the probability of forgetting exactly one of the two
/// places would have been a tipping into silence: `openPlace`
/// would have discarded the cell, `buildPlace` built it, and no one
/// would have seen an error — only a message that does not arrive.
bool isKnownRetention(int retention) =>
    retention == kRetentionNormal ||
    retention == kRetentionSignal ||
    retention == kRetentionManagement;

/// Length of the ephemeral X25519 part in a stored item.
const int kPlaceEphBytes = 32;

/// Nonce length of the seal.
const int kPlaceNonceBytes = 12;

/// Where the sealed part begins.
const int kPlaceSealOffset = 1 + 1 + 32 + 32 + 12;

/// Maximum number of forwardings of a stored item.
///
/// AGAINST LOOPS, and the number is calculated: with k-buckets of size
/// 20 every hop gains about `log2(20) ~ 4,3` bits of closeness, at 10^5
/// nodes (17 bits) that is about four hops. Eight allows double
/// and still ends every loop.
const int kMaxPlaceHops = 8;

/// Builds the body of a `place` frame: `op(1) ‖ tag(32) ‖ inhalt`.
/// Builds a stored item whose tag and content only the TARGET can read.
///
/// WHY SEALED. A stored item is passed greedily over several hops to the target
/// (§11.2). Until IP-1 the tag was in plaintext — every
/// forwarding relay could record it. The KEX gate (§10.1)
/// only prevents a stranger from COMPUTING a tag; that he SEES it
/// in transit it does not prevent. And the tag is exactly the quantity
/// on which the mailbox line of a pair hangs.
///
/// WHAT MUST STAY VISIBLE: the target. Without it no intermediate node can
/// decide where to pass it. Visible is thus „someone stores at P",
/// not „who with whom".
///
/// CLASSICAL, NOT POST-QUANTUM — and that is calculated, not convenient:
/// an ML-KEM capsule measures 1088 B, the frame body 1169. With header, tag
/// and AEAD suffix nothing would be left for the content (−13 B). The CONTENT is
/// end-to-end post-quantum sealed anyway; only the
/// confidentiality of the tag towards intermediate nodes is classical here. Declared limit.
({Uint8List frame, Uint8List ackKey}) buildPlace(
  Uint8List target,
  Uint8List targetX25519Public,
  Uint8List tag,
  Uint8List cell, {
  int hops = kMaxPlaceHops,
  Uint8List? ephemeralSeed,
  int retention = kRetentionNormal,
}) {
  if (!isKnownRetention(retention)) {
    throw ArgumentError('unknown retention class $retention');
  }
  if (target.length != 32) throw ArgumentError('Target must be 32 B');
  if (targetX25519Public.length != 32) {
    throw ArgumentError('Target X25519 must be 32 B');
  }
  if (tag.length != 32) throw ArgumentError('Tag must be 32 B');
  if (hops < 0 || hops > kMaxPlaceHops) {
    throw ArgumentError('Hops 0..$kMaxPlaceHops');
  }
  if (cell.length > kMaxPlaceContentBytes) {
    throw ArgumentError('Placement carries ${cell.length} B, the limit is '
        '$kMaxPlaceContentBytes');
  }

  final sodium = SodiumFFI();
  // Ephemeral key pair. With a seed reproducible for tests; without
  // seed from system randomness. An X25519 secret may be any 32 bytes
  // — the clamping happens in the scalar product.
  final Uint8List ephSk;
  final Uint8List ephPk;
  if (ephemeralSeed != null) {
    if (ephemeralSeed.length != 32) {
      throw ArgumentError('Seed must be 32 B');
    }
    ephSk = Uint8List.fromList(ephemeralSeed);
    ephPk = sodium.x25519ScalarMult(ephSk, _basepoint);
  } else {
    final kp = sodium.generateX25519KeyPair();
    ephSk = kp.secretKey;
    ephPk = kp.publicKey;
  }
  final ss = sodium.x25519ScalarMult(ephSk, targetX25519Public);
  final key = _placeKey(ss, target);
  final ackKey = _placeAckKey(ss, target);
  final nonce = sodium.randomBytes(kPlaceNonceBytes);

  // `klasse(1) ‖ tag(32) ‖ inhalt` — the class IN FRONT, so that `openPlace`
  // can read it without knowing the length of the content.
  final clear = Uint8List(1 + 32 + cell.length)
    ..[0] = retention
    ..setRange(1, 33, tag)
    ..setRange(33, 33 + cell.length, cell);
  final ct = sodium.aesGcmEncrypt(clear, key, nonce);

  final out = Uint8List(kPlaceSealOffset + ct.length);
  var o = 0;
  out[o++] = SecureOp.place;
  out[o++] = hops;
  out.setRange(o, o += 32, target);
  out.setRange(o, o += 32, ephPk);
  out.setRange(o, o += kPlaceNonceBytes, nonce);
  out.setRange(o, out.length, ct);
  return (frame: out, ackKey: ackKey);
}

/// Opens a stored item addressed to this node.
///
/// Returns `null` if it is not for us or does not hold —
/// silently (E-83).
({Uint8List tag, Uint8List cell, Uint8List ackKey, int retention})? openPlace(
    Uint8List body, Uint8List ownX25519Secret) {
  if (body.length <= kPlaceSealOffset + kAeadTagBytes + 32 + 1) return null;
  final sodium = SodiumFFI();
  final target = Uint8List.sublistView(body, 2, 34);
  final eph = Uint8List.sublistView(body, 34, 66);
  final nonce = Uint8List.sublistView(body, 66, kPlaceSealOffset);
  final ct = Uint8List.sublistView(body, kPlaceSealOffset);
  final Uint8List clear;
  final Uint8List ackKey;
  try {
    final ss = sodium.x25519ScalarMult(
        ownX25519Secret, Uint8List.fromList(eph));
    clear = sodium.aesGcmDecrypt(
        Uint8List.fromList(ct), _placeKey(ss, Uint8List.fromList(target)),
        Uint8List.fromList(nonce));
    ackKey = _placeAckKey(ss, Uint8List.fromList(target));
  } catch (_) {
    return null;
  }
  if (clear.length < 1 + 32) return null;
  // AN UNKNOWN CLASS IS A MALFORMED FRAME, not an occasion for
  // guessing. Whoever let it pass as „normal" would silently give a future
  // SHORT class the LONG period — the direction in which an error
  // must not run here.
  final klass = clear[0];
  if (!isKnownRetention(klass)) return null;
  return (
    tag: Uint8List.fromList(clear.sublist(1, 33)),
    cell: Uint8List.fromList(clear.sublist(33)),
    ackKey: ackKey,
    retention: klass,
  );
}

/// The X25519 base point.
final Uint8List _basepoint = Uint8List(32)..[0] = 9;

/// The key under which the STORING relay authenticates its receipt.
///
/// ── WHY THE RECEIPT NEEDS A MAC (S357, counter-reading) ────────
///
/// Without it it is forgeable, namely by the FIRST HOP: the identifier
/// [placeRequestId] is computed from `ephPk`, and `ephPk` lies in the
/// plaintext of the stored item. A malicious direct neighbour thus reads the
/// identifier, throws away the frame and itself sends back
/// `placeAck(kennung, stored: true)`. The sender finds the
/// identifier in its book, takes from it the INTENDED relay — which it
/// entered itself — and credits it with a proof that no one ever
/// earned. Over several stored items at relays in different
/// network blocks a SINGLE malicious neighbour thus reaches `ready` and
/// thereby opens the Speed gate and the system channel gate (§22.7.2).
///
/// THE SECRET IS ALREADY THERE. Sender and target relay share `ss` from
/// the storing seal: the sender computed it with `ephSk`, the
/// relay computes it with its static secret. **A
/// forwarding hop cannot** — it sees `ephPk`, not `ephSk`,
/// and does not have the private part of the target. Exactly this separation
/// is needed by §22.7: „evidence, not acquaintance" demands a proof that
/// only the prover can issue.
///
/// Own `info` string, so that the same `ss` does not carry two roles in
/// one key.
Uint8List _placeAckKey(Uint8List ss, Uint8List target) =>
    SodiumFFI().hkdfSha256(
      ss,
      salt: target,
      info: Uint8List.fromList(utf8.encode('cleona-place-ack-mac/v1')),
      length: 32,
    );

Uint8List _placeKey(Uint8List ss, Uint8List target) => SodiumFFI().hkdfSha256(
      ss,
      salt: target,
      info: Uint8List.fromList(utf8.encode('cleona-place/v1')),
      length: 32,
    );

/// The same frame with one hop fewer — for forwarding.
///
/// ── APPLIES TO STORING **AND** HARVEST (B-29, S349) ──────────────────────
///
/// Both frames carry the same header `op(1) ‖ hops(1) ‖ …`, and both
/// are forwarded greedily to the target — `DeliveryNode._handleControl`
/// says so in its own comment ("the same path as a stored item").
/// Nevertheless this function checked `body[0] != SecureOp.place` and threw
/// on every harvest request.
///
/// In the field on 28.08. on the phone: **54 crashes**, all with
/// `Invalid argument(s): kein weiterleitbarer Ablage-Rahmen`, from within a
/// stream callback and thus uncaught. It only became visible
/// when the node really got partners via the entry cascade and
/// began to work as a relay — before that no harvest was ever
/// forwarded.
///
/// `null` is returned instead of thrown: a frame that cannot be
/// forwarded is not a program error but a cell from the
/// wire (E-83). The caller leaves it lying.
/// ── THE ALLOW LIST IS THE DANGEROUS LINE (S356) ─────────────
///
/// Every frame that runs greedily over several hops to the target MUST
/// stand here. If it does not, this function returns `null`, the
/// forwarding node leaves it lying — and the frame never arrives,
/// without an error becoming visible anywhere.
///
/// Exactly that happened on 28.08., when the harvest request was missing: on the
/// phone **54 crashes** with "kein weiterleitbarer Ablage-Rahmen", and
/// it only became visible when the node began to work as a relay
/// at all. `findNode` has been the third such frame since S356.
///
/// That is why the list stands as [kForwardableOps] also as DATA
/// and not only as an `if` chain: `smoke_v41_network_responsibility.dart`
/// checks every multi-hop opcode individually against it. A comment
/// would not have prevented the 28.08.
const Set<int> kForwardableOps = <int>{
  SecureOp.place,
  SecureOp.harvestRequest,
  SecureOp.findNode,
  // Since S376 TWO more are added, from two packages of the same session.
  //
  // The fourth (P4-1): the entry request is directed and runs
  // greedily to the target. The fifth (P9): the lookup onion, whose
  // blind-relay leg carries the same header as the open search request.
  //
  // For both the same sentence applies: without the entry `decrementHops` would return
  // `null`, the intermediate hop would leave the frame lying — and SILENTLY,
  // exactly the 28.08. that the paragraph above describes.
  SecureOp.entryRequest,
  SecureOp.findNodeOnion,
};

Uint8List? decrementHops(Uint8List body) {
  if (body.length < 2 || body[1] == 0) return null;
  if (!kForwardableOps.contains(body[0])) {
    return null;
  }
  final out = Uint8List.fromList(body);
  out[1] = body[1] - 1;
  return out;
}

/// Builds a peer announcement: `op(1) ‖ anzahl(2) ‖ positionen(32 je)`.
Uint8List buildPeerAnnounce(List<Uint8List> positions) {
  final out = Uint8List(3 + positions.length * 32);
  out[0] = SecureOp.peerAnnounce;
  out[1] = (positions.length >> 8) & 0xff;
  out[2] = positions.length & 0xff;
  for (var i = 0; i < positions.length; i++) {
    if (positions[i].length != 32) {
      throw ArgumentError('Position must be 32 B');
    }
    out.setRange(3 + i * 32, 3 + (i + 1) * 32, positions[i]);
  }
  return out;
}

/// Builds a harvest query: `op(1) ‖ anzahl(2) ‖ tags`.
///
/// The order of the tags comes from the caller and is already mixed
/// (§6, `secure_mode.dart`) — NO sorting happens here, that would
/// undo the mixing.
/// Length of the request identifier.
const int kRequestIdBytes = 16;

/// Header length of the harvest request up to the seal.
const int kHarvestSealOffset = 1 + 1 + kRequestIdBytes + 32 + 32 + 12;

/// How many tags — REAL AND DECOYS TOGETHER — fit into ONE harvest request.
///
/// ── THE CALCULATION, AND WHY IT IS HERE (S358) ────────────────────
///
/// `buildHarvestRequest` has always accepted `1..255` tags and
/// only throws afterwards when the finished frame bursts the cell. The
/// limit could thus only be learned by trial — and whoever
/// exceeds it gets no shorter request, but an
/// ArgumentError from a send path.
///
///   Header    [kHarvestSealOffset]                    94 B
///   Plaintext 1 (tag count)
///           + 32 per tag
///           + 1 (length of the have list)
///           + [kHarvestHaveSlots] x [kCellDigestBytes] = 32 x 8 = 256 B
///   Seal     [kAeadTagBytes]                         16 B
///
///   1169 = 94 + 16 + 2 + 256 + 32 x T   ->   T = 801 / 32 = 25,03
///
/// Re-measured on 2026-08-31 against `buildHarvestRequest` itself (full
/// have list): T = 25 yields 1168 B, T = 26 is rejected.
///
/// **THOSE ARE NOT 25 REAL TAGS.** Every real tag travels with
/// `kDecoyCount` decoys (§6, E-C′: d = 3), otherwise it could be
/// recognised by coming alone. 25 total tags are thus
/// `25 ~/ 4 = 6` real ones — the number the harvest computes with stands as
/// `kMaxRealHarvestTags` in `secure_mode.dart`, where `kDecoyCount` is known.
const int kMaxHarvestTagsTotal = (kControlBodyBytes -
        kHarvestSealOffset -
        kAeadTagBytes -
        2 -
        kHarvestHaveSlots * kCellDigestBytes) ~/
    32;

/// Builds a harvest request whose TAGS only the target can read.
///
/// `op ‖ hops ‖ kennung(16) ‖ ziel(32) ‖ eph(32) ‖ nonce(12) ‖ AEAD(tags)`
///
/// WHY SEALED — the same reasoning as for storing: the request
/// runs over several hops to the responsible relay, and a tag is the
/// mailbox line of a pair. If it lay open in transit, every hop could
/// record what is being searched for here — and that is the same number that
/// the stored item carries too.
///
/// WHY AN IDENTIFIER. The answer must find its way back without the
/// responsible relay learning WHO asked. Every hop remembers
/// „identifier came from this partner" and sends the answer back the same way.
/// No node thereby knows more than its two neighbours.
///
/// ── THE HAVE LIST (B-32, S350) ────────────────────────────────────────
///
/// [have] tells the relay which cells the asker already has completely;
/// the relay leaves exactly those out. Without it, it delivers at every
/// run again EVERYTHING that lies under the tag — in the field on 28.08.
/// twenty-one times the same message, and without expiry of the storage
/// it would never have ended (`harvest_memo.dart`).
///
/// WHY NOT DELETE. §14.2: all devices of an identity harvest
/// the same tag line. Whoever deletes after the first fetch takes the cell away
/// from the second device. The list leaves the cell lying and still saves
/// the wire.
///
/// IT STANDS WITHIN THE SEAL. A forwarding hop does not see it
/// — the same reasoning as for the tags. And it is ALWAYS equally
/// long ([kHarvestHaveSlots], padded by the caller), otherwise its
/// length itself would be the information „this much I already have".
///
/// S368: here stood „BACKWARD COMPATIBLE: the list is appended AT THE END.
/// A relay with the old reading side reads `anzahl` and the tags,
/// ignores the rest and sends everything as before". A relay with an
/// old reading side does not exist on this line — and the list is
/// ALWAYS written by this function, always in the same length. Its absence
/// is therefore not an older sender but a malformed frame;
/// the reading side rejects it (see [parseHarvestRequest]).
Uint8List buildHarvestRequest(
  Uint8List target,
  Uint8List targetX25519Public,
  Uint8List requestId,
  List<Uint8List> tags, {
  List<Uint8List> have = const <Uint8List>[],
  int hops = kMaxPlaceHops,
  Uint8List? ephemeralSeed,
}) {
  if (target.length != 32) throw ArgumentError('Target must be 32 B');
  if (requestId.length != kRequestIdBytes) {
    throw ArgumentError('identifier must be $kRequestIdBytes B');
  }
  if (tags.isEmpty || tags.length > 255) {
    throw ArgumentError('1..255 Tags');
  }
  if (have.length > 255) throw ArgumentError('at most 255 marks');
  if (hops < 0 || hops > kMaxPlaceHops) {
    throw ArgumentError('Hops 0..$kMaxPlaceHops');
  }
  final clear = Uint8List(
      1 + tags.length * 32 + 1 + have.length * kCellDigestBytes);
  clear[0] = tags.length;
  for (var i = 0; i < tags.length; i++) {
    if (tags[i].length != 32) throw ArgumentError('Tag must be 32 B');
    clear.setRange(1 + i * 32, 1 + (i + 1) * 32, tags[i]);
  }
  var ho = 1 + tags.length * 32;
  clear[ho++] = have.length;
  for (final m in have) {
    if (m.length != kCellDigestBytes) {
      throw ArgumentError('Tag must be $kCellDigestBytes B');
    }
    clear.setRange(ho, ho += kCellDigestBytes, m);
  }

  final sodium = SodiumFFI();
  final Uint8List ephSk;
  final Uint8List ephPk;
  if (ephemeralSeed != null) {
    ephSk = Uint8List.fromList(ephemeralSeed);
    ephPk = sodium.x25519ScalarMult(ephSk, _basepoint);
  } else {
    final kp = sodium.generateX25519KeyPair();
    ephSk = kp.secretKey;
    ephPk = kp.publicKey;
  }
  final key =
      _placeKey(sodium.x25519ScalarMult(ephSk, targetX25519Public), target);
  final nonce = sodium.randomBytes(12);
  final ct = sodium.aesGcmEncrypt(clear, key, nonce);
  if (kHarvestSealOffset + ct.length > kControlBodyBytes) {
    // THE NUMBER BELONGS IN THE MESSAGE. Whoever lands here has planned how
    // many tags he fits in — he must learn which limit
    // he should have computed with. [kMaxHarvestTagsTotal] is the limit with
    // a FULL have list; without it more fit, which is why the
    // authoritative check stays here on the finished frame and not on the
    // tag count.
    throw ArgumentError('too many tags for a cell: ${tags.length} tags '
        'and ${have.length} proofs give ${kHarvestSealOffset + ct.length} B '
        '> $kControlBodyBytes B (with a full have-list '
        '$kMaxHarvestTagsTotal tags fit)');
  }

  final out = Uint8List(kHarvestSealOffset + ct.length);
  var o = 0;
  out[o++] = SecureOp.harvestRequest;
  out[o++] = hops;
  out.setRange(o, o += kRequestIdBytes, requestId);
  out.setRange(o, o += 32, target);
  out.setRange(o, o += 32, ephPk);
  out.setRange(o, o += 12, nonce);
  out.setRange(o, out.length, ct);
  return out;
}

/// Opens a harvest request addressed to this node.
///
/// Returned are the queried tags AND the have list of the asker.
/// If the list is missing (old counterpart), it is empty — then the
/// relay behaves as before B-32 and sends everything.
({List<Uint8List> tags, List<Uint8List> have})? openHarvestRequest(
    Uint8List body, Uint8List ownX25519Secret) {
  if (body.length <= kHarvestSealOffset + 16) return null;
  final sodium = SodiumFFI();
  final target = Uint8List.fromList(
      body.sublist(2 + kRequestIdBytes, 2 + kRequestIdBytes + 32));
  final eph = Uint8List.fromList(
      body.sublist(2 + kRequestIdBytes + 32, 2 + kRequestIdBytes + 64));
  final nonce = Uint8List.fromList(
      body.sublist(2 + kRequestIdBytes + 64, kHarvestSealOffset));
  final Uint8List clear;
  try {
    clear = sodium.aesGcmDecrypt(
        Uint8List.fromList(body.sublist(kHarvestSealOffset)),
        _placeKey(sodium.x25519ScalarMult(ownX25519Secret, eph), target),
        nonce);
  } catch (_) {
    return null;
  }
  if (clear.isEmpty) return null;
  final n = clear[0];
  if (n == 0 || 1 + n * 32 > clear.length) return null;
  final tags = [
    for (var i = 0; i < n; i++)
      Uint8List.fromList(clear.sublist(1 + i * 32, 1 + (i + 1) * 32))
  ];
  final have = <Uint8List>[];
  var o = 1 + n * 32;
  // S368: here stood `if (o < klar.length)` — a MISSING list counted as
  // „older counterpart" and was let through. The sending side always
  // appends it; its absence is a malformed frame, not an old sender.
  // Letting it through would mean answering a request without knowledge of the
  // asker's stock — i.e. sending everything.
  if (o >= clear.length) return null;
  {
    final h = clear[o++];
    // A list announced but not supplied is a
    // malformed frame. It carries no information (§2.6) — the
    // request is then silently discarded and not half answered.
    if (o + h * kCellDigestBytes > clear.length) return null;
    for (var i = 0; i < h; i++) {
      have.add(Uint8List.fromList(
          clear.sublist(o + i * kCellDigestBytes,
              o + (i + 1) * kCellDigestBytes)));
    }
  }
  return (tags: tags, have: have);
}

/// Builds a harvest answer: `op(1) ‖ kennung(16) ‖ zelle`.
Uint8List buildHarvestResponse(Uint8List requestId, Uint8List cell) {
  if (requestId.length != kRequestIdBytes) {
    throw ArgumentError('identifier must be $kRequestIdBytes B');
  }
  final out = Uint8List(1 + kRequestIdBytes + cell.length);
  out[0] = SecureOp.harvestResponse;
  out.setRange(1, 1 + kRequestIdBytes, requestId);
  out.setRange(1 + kRequestIdBytes, out.length, cell);
  return out;
}

// ── THE SEARCH (S356, §9.1 „Still an approximation") ─────────────────

/// Header length of the search request up to the seal — the same layout as for
/// the harvest request, because it uses the same rails: sealed to
/// the target relay, forwarded greedily, answer back via the identifier
/// (`delivery_node.dart`, `PendingRoutes`).
const int kFindNodeSealOffset = kHarvestSealOffset;

/// Maximum number of positions in a search answer.
///
/// Twenty, because the responsibility set `R = 20` is large (E-H) — an
/// answer must be able to carry a FULL set, otherwise the lookup would be
/// restricted by format to a subset. The frame thus measures
/// `1 + 16 + 1 + 20*32 = 658 B` and stays below the frame body of
/// 1169 B: one cell, no fragmentation.
///
/// The number stands here as a format limit and not as a reference to
/// `kResponsibleRelays`: the wire format must not change when
/// someone turns the policy constant. Whoever raises R must consciously
/// follow up here and recalculate the cell limit.
const int kMaxFindNodePositions = 20;

/// Builds a search request whose SEARCH POINT only the target relay can read.
///
/// `op ‖ hops ‖ kennung(16) ‖ zielrelais(32) ‖ eph(32) ‖ nonce(12)
///  ‖ AEAD(suchpunkt(32))` = 142 B.
///
/// TWO DIFFERENT POINTS, and keeping them apart is the purpose
/// of this frame:
///
///   * [targetRelay] is the position of the node we ASK. It
///     lies open because every hop needs it for forwarding
///     (`nextHopToward`).
///   * [searchPoint] is `H(T ‖ e)`, i.e. WHAT is being asked for. It
///     lies in the seal because it is computed from the tag and the tag is the
///     mailbox line of a pair. If it lay open, every hop could
///     record which pair is searching at the moment — and §9.1 (finding 1,
///     E-L) names exactly this linkage as what is to be avoided.
///
/// With the harvest request both coincide (there the target is also
/// the salt); here not, and that is why the salt is still
/// [targetRelay] — only the target relay can open the seal.
Uint8List buildFindNode(
  Uint8List targetRelay,
  Uint8List targetX25519Public,
  Uint8List requestId,
  Uint8List searchPoint, {
  int hops = kMaxPlaceHops,
  Uint8List? ephemeralSeed,
}) {
  if (targetRelay.length != 32) throw ArgumentError('Target relay must be 32 B');
  if (searchPoint.length != 32) throw ArgumentError('Search point must be 32 B');
  if (requestId.length != kRequestIdBytes) {
    throw ArgumentError('identifier must be $kRequestIdBytes B');
  }
  if (hops < 0 || hops > kMaxPlaceHops) {
    throw ArgumentError('Hops 0..$kMaxPlaceHops');
  }
  final sodium = SodiumFFI();
  final Uint8List ephSk;
  final Uint8List ephPk;
  if (ephemeralSeed != null) {
    ephSk = Uint8List.fromList(ephemeralSeed);
    ephPk = sodium.x25519ScalarMult(ephSk, _basepoint);
  } else {
    final kp = sodium.generateX25519KeyPair();
    ephSk = kp.secretKey;
    ephPk = kp.publicKey;
  }
  final key = _placeKey(
      sodium.x25519ScalarMult(ephSk, targetX25519Public), targetRelay);
  final nonce = sodium.randomBytes(12);
  final ct = sodium.aesGcmEncrypt(
      Uint8List.fromList(searchPoint), key, nonce);

  final out = Uint8List(kFindNodeSealOffset + ct.length);
  var o = 0;
  out[o++] = SecureOp.findNode;
  out[o++] = hops;
  out.setRange(o, o += kRequestIdBytes, requestId);
  out.setRange(o, o += 32, targetRelay);
  out.setRange(o, o += 32, ephPk);
  out.setRange(o, o += 12, nonce);
  out.setRange(o, out.length, ct);
  return out;
}

/// Opens a search request addressed to this node.
///
/// Returned is the search point `H(T ‖ e)`. `null` for everything that
/// cannot be opened — a foreign request is not an error but
/// the normal case on a forwarding node.
Uint8List? openFindNode(Uint8List body, Uint8List ownX25519Secret) {
  if (body.length != kFindNodeSealOffset + 32 + 16) return null;
  final sodium = SodiumFFI();
  final targetRelay = Uint8List.fromList(
      body.sublist(2 + kRequestIdBytes, 2 + kRequestIdBytes + 32));
  final eph = Uint8List.fromList(
      body.sublist(2 + kRequestIdBytes + 32, 2 + kRequestIdBytes + 64));
  final nonce = Uint8List.fromList(
      body.sublist(2 + kRequestIdBytes + 64, kFindNodeSealOffset));
  try {
    final clear = sodium.aesGcmDecrypt(
        Uint8List.fromList(body.sublist(kFindNodeSealOffset)),
        _placeKey(
            sodium.x25519ScalarMult(ownX25519Secret, eph), targetRelay),
        nonce);
    return clear.length == 32 ? Uint8List.fromList(clear) : null;
  } catch (_) {
    return null;
  }
}

/// Builds the search answer: `op(1) ‖ kennung(16) ‖ anzahl(1) ‖ positionen`.
///
/// UNSEALED, and that is not an oversight. The return path runs via the
/// identifier through the same hops as the request; a seal would need a
/// secret of the asker, and exactly that the answering relay does
/// not have — it does not even know who asked. What a hop learns
/// are node positions: infrastructure, not contact knowledge (see
/// [SecureOp.peerAnnounce], which announces the same openly). What it does NOT
/// learn is the search point — that lay in the seal of the request.
Uint8List buildFindNodeResponse(
    Uint8List requestId, List<Uint8List> positions) {
  if (requestId.length != kRequestIdBytes) {
    throw ArgumentError('identifier must be $kRequestIdBytes B');
  }
  if (positions.length > kMaxFindNodePositions) {
    throw ArgumentError('at most $kMaxFindNodePositions positions');
  }
  final out = Uint8List(1 + kRequestIdBytes + 1 + positions.length * 32);
  out[0] = SecureOp.findNodeResponse;
  out.setRange(1, 1 + kRequestIdBytes, requestId);
  out[1 + kRequestIdBytes] = positions.length;
  var o = 2 + kRequestIdBytes;
  for (final p in positions) {
    if (p.length != 32) throw ArgumentError('Position must be 32 B');
    out.setRange(o, o += 32, p);
  }
  return out;
}

// ── THE LOOKUP ONION (S376, E-L) ─────────────────────────────────────

/// Header length of the lookup onion up to the seal.
///
/// The same layout as [buildFindNode] itself — `op(1) ‖ hops(1) ‖
/// kennung(16) ‖ blindrelais(32) ‖ eph(32) ‖ nonce(12)` —, and that is
/// no coincidence but the reason why this shell manages without a new
/// forwarding path: `decrementHops`, `_amTarget` and
/// `nextHopToward` read exactly this header.
const int kFindNodeOnionSealOffset = kFindNodeSealOffset;

/// What a shell encloses: the inner [SecureOp.findNode] frame.
const int kFindNodeInnerBytes = kFindNodeSealOffset + 32 + 16;

/// What ONE shell costs: header plus AEAD tag.
///
/// `94 + 16 = 110` B. The payload of a shell is the frame underneath,
/// unchanged — that is why the price per shell is a fixed summand and
/// not a function of depth.
const int kFindNodeOnionShellBytes = kFindNodeOnionSealOffset + 16;

/// ══ THE ADJUSTING SCREW: how many blind relays a search passes through ══
///
/// **(a) WHAT HANGS ON THIS NUMBER.** It is exactly the number of
/// blind relays on the outward path of a search, and thus it determines how
/// many nodes must COLLUDE to link „A searches" with „a search for
/// `H(T ‖ e)` is happening": **`kLookupOnionShells + 1`**. At
/// 1 that is two (first hop and target relay), at 2 it is three. No
/// single node ever sees both ends — one shell already achieves
/// that; the second only raises the number of necessary accomplices. The
/// residual risk of a collusion per search falls, with a share of
/// hostile nodes `f = 25 %`, from 32 % to 9 % (owner approval
/// V-9a, 09.09.2026).
///
/// **(b) THE MEASURED PRICE PER SHELL.** Not calculated, measured —
/// `smoke_v41_lookup_zwiebel.dart`, part 3, 30 searches, 800 nodes:
///
///   * Cells per request in the network (outward path): 2.46 without shell · **4.48**
///     with one · **6.49** with two. Factor on the lookup outward path
///     1.82 and **2.64** respectively.
///   * Frame size: 142 B · 252 B · **362 B**, per shell `+110` B
///     ([kFindNodeOnionShellBytes]) of a 1169 B frame body. Up to and
///     including eight shells (1022 B) a search stays ONE
///     cell.
///   * Egress cells of the searcher per request: **1, independent of the
///     depth** (§9.1 „no additional egress cells"). That is the quantity
///     that does NOT grow along, and the reason why this screw can be
///     turned at all.
///
/// **(c) WHAT TO WATCH OUT FOR WHEN ADJUSTING.**
///
///   1. **Upwards** it ends at eight: `142 + 8 * 110 = 1022` B; the
///      ninth shell (1132 B) still fits, the tenth (1242 B) bursts
///      the frame body and the search would fragment. Whoever goes beyond eight
///      must first recalculate `kMaxFrameBodySize` (1169 B) — there is
///      no promise here beyond that.
///   2. **The hop supply multiplies.** Every leg starts with
///      [kMaxPlaceHops]; with N shells there are `N + 1` legs, i.e. up
///      to `(N + 1) * kMaxPlaceHops` hops. That is the actual
///      traffic price, not the 110 B.
///   3. **The cold start becomes stricter.** The searcher needs N
///      DIFFERENT relays outside its own sessions; if it has
///      fewer, the search DOES NOT HAPPEN (`V41Node.lookupQuery`,
///      `lookupsOhneBlindrelais`) — there is no fallback to the
///      open request.
///   4. **Roll out all nodes together.** A receiver only accepts
///      depths `1..kLookupOnionShells` ([lookupOnionDepth]); a
///      node with a smaller number rejects the deeper onion, and
///      silently — the search then dies of the hop supply. V4.1 knows
///      no downward compatibility, that is permissible, but it
///      means: a change here is a network cut.
///   5. **It stands exactly once.** No literal 2 elsewhere; whoever looks for the
///      number looks for this name.
///
/// Owner decision of 09.09.2026 (V-9a = B): two shells. If the
/// total traffic later turns out too high, THIS number is the first knob.
const int kLookupOnionShells = 2;

/// The total size of the lookup onion as the searcher builds it.
///
/// `94 * 2 + 142 + 16 * 2 = 362` B of a 1169 B frame body at
/// [kLookupOnionShells] `= 2`.
const int kFindNodeOnionBytes =
    kFindNodeInnerBytes + kLookupOnionShells * kFindNodeOnionShellBytes;

/// The shell depth of a frame of this length — `0` if it is not a
/// valid lookup onion.
///
/// ── WHY THE LENGTH IS A CAP HERE, NOT INCIDENTAL ──────────────
///
/// The frame is nestable: a shell encloses the frame
/// underneath, and that may itself be a shell again. Exactly that
/// makes it a lever without a cap — a stranger would put
/// arbitrarily many shells on top of each other and let every node of the
/// chain compute a decryption for it. The permissible lengths
/// are therefore a COUNTABLE set, and everything outside is no
/// frame (§2.6: a malformed frame carries no information).
///
/// Accepted are the depths `1..kLookupOnionShells` — not only the
/// full one: a node on leg 2 sees an onion from which one shell
/// has already been stripped.
int lookupOnionDepth(int frameLength) {
  // THE CAP STANDS IN BYTES, and that is not a detour: the deepest
  // onion a searcher builds at all measures
  // [kFindNodeOnionBytes]. Everything above is no frame — and the
  // size the receiver has to check is the same that pins the
  // searcher's output to one cell.
  if (frameLength > kFindNodeOnionBytes) return 0;
  final via = frameLength - kFindNodeInnerBytes;
  if (via <= 0) return 0;
  if (via % kFindNodeOnionShellBytes != 0) return 0;
  return via ~/ kFindNodeOnionShellBytes;
}

/// Puts [innerFrame] into a shell that only [blindRelay] can open.
///
/// [outerRequestId] is the identifier of the OUTER leg and lies open;
/// the identifier of the inner leg is inside [innerFrame] and stays
/// sealed. Both must be DIFFERENT — see [SecureOp
/// .findNodeOnion].
Uint8List buildFindNodeOnion({
  required Uint8List blindRelay,
  required Uint8List blindRelayX25519Public,
  required Uint8List outerRequestId,
  required Uint8List innerFrame,
  int hops = kMaxPlaceHops,
  Uint8List? ephemeralSeed,
}) {
  if (blindRelay.length != 32) {
    throw ArgumentError('Blind relay must be 32 B');
  }
  if (outerRequestId.length != kRequestIdBytes) {
    throw ArgumentError('identifier must be $kRequestIdBytes B');
  }
  // THE PAYLOAD IS EITHER THE SEARCH REQUEST ITSELF OR A SHALLOWER
  // ONION. There are no more cases, and that is the cap: without it
  // an arbitrary frame could be put into the network under a foreign sender address
  // (the same reasoning as at the blind relay in
  // `DeliveryNode`). The outermost shell may become at most
  // [kLookupOnionShells] deep.
  final insideDepth = innerFrame.length == kFindNodeInnerBytes
      ? 0
      : lookupOnionDepth(innerFrame.length);
  if (innerFrame.length != kFindNodeInnerBytes && insideDepth == 0) {
    throw ArgumentError('inner frame must be a search request '
        '($kFindNodeInnerBytes B) or a flatter onion, '
        'not ${innerFrame.length} B');
  }
  if (insideDepth + 1 > kLookupOnionShells) {
    throw ArgumentError('at most $kLookupOnionShells shells '
        '(kLookupOnionShells), requested ${insideDepth + 1}');
  }
  if (hops < 0 || hops > kMaxPlaceHops) {
    throw ArgumentError('Hops 0..$kMaxPlaceHops');
  }
  final sodium = SodiumFFI();
  final Uint8List ephSk;
  final Uint8List ephPk;
  if (ephemeralSeed != null) {
    ephSk = Uint8List.fromList(ephemeralSeed);
    ephPk = sodium.x25519ScalarMult(ephSk, _basepoint);
  } else {
    final kp = sodium.generateX25519KeyPair();
    ephSk = kp.secretKey;
    ephPk = kp.publicKey;
  }
  final key = _placeKey(
      sodium.x25519ScalarMult(ephSk, blindRelayX25519Public), blindRelay);
  final nonce = sodium.randomBytes(12);
  final ct = sodium.aesGcmEncrypt(innerFrame, key, nonce);

  final out = Uint8List(kFindNodeOnionSealOffset + ct.length);
  var o = 0;
  out[o++] = SecureOp.findNodeOnion;
  out[o++] = hops;
  out.setRange(o, o += kRequestIdBytes, outerRequestId);
  out.setRange(o, o += 32, blindRelay);
  out.setRange(o, o += 32, ephPk);
  out.setRange(o, o += 12, nonce);
  out.setRange(o, out.length, ct);
  return out;
}

/// Opens a shell addressed to this node and returns the inner
/// frame.
///
/// `null` for everything that cannot be opened — a foreign shell
/// is not an error but the normal case on a node that
/// forwards (E-83).
Uint8List? openFindNodeOnion(Uint8List body, Uint8List ownX25519Secret) {
  // EVERY permissible depth, not only the full one: whoever lies on leg 2
  // sees an onion from which one shell has already been stripped.
  final depth = lookupOnionDepth(body.length);
  if (depth == 0) return null;
  final sodium = SodiumFFI();
  final blindRelay = Uint8List.fromList(
      body.sublist(2 + kRequestIdBytes, 2 + kRequestIdBytes + 32));
  final eph = Uint8List.fromList(
      body.sublist(2 + kRequestIdBytes + 32, 2 + kRequestIdBytes + 64));
  final nonce = Uint8List.fromList(
      body.sublist(2 + kRequestIdBytes + 64, kFindNodeOnionSealOffset));
  try {
    final clear = sodium.aesGcmDecrypt(
        Uint8List.fromList(body.sublist(kFindNodeOnionSealOffset)),
        _placeKey(sodium.x25519ScalarMult(ownX25519Secret, eph), blindRelay),
        nonce);
    // What comes out must be the frame the depth promises —
    // one shell fewer. Otherwise someone has put a shell over something
    // else, and nothing is forwarded.
    final expected =
        kFindNodeInnerBytes + (depth - 1) * kFindNodeOnionShellBytes;
    return clear.length == expected ? Uint8List.fromList(clear) : null;
  } catch (_) {
    return null;
  }
}

/// Rewrites the identifier of a search answer.
///
/// The blind relay needs this: it knows two identifiers for the same
/// operation (outer and inner), and the hops before it only know the
/// outer one. Without the rewriting the answer would find its way up to the
/// blind relay and no further there.
///
/// Returns `null` if [response] is not a search answer — the
/// caller then leaves it lying instead of mutilating a foreign
/// frame.
Uint8List? relabelFindNodeResponse(Uint8List response, Uint8List newId) {
  if (newId.length != kRequestIdBytes) return null;
  if (response.length < 1 + kRequestIdBytes + 1) return null;
  if (response[0] != SecureOp.findNodeResponse) return null;
  final out = Uint8List.fromList(response);
  out.setRange(1, 1 + kRequestIdBytes, newId);
  return out;
}

/// What was in a control frame.
final class SecureFrame {
  final int op;
  final Uint8List? tag;
  final Uint8List? cell;
  final List<Uint8List> tags;

  /// Only populated for [SecureOp.entryResponse].
  final List<EntryRecord> records;

  /// Only for [SecureOp.place]: the TARGET relay, remaining hops and
  /// the unchanged frame for forwarding.
  ///
  /// WHY THE STORED ITEM CARRIES A TARGET. Without a target every copy of the same
  /// tag would converge at the nearest node — the R responsible ones
  /// would get ONE stored item instead of R, and `P1 = 1 - exp(-R*f)` from M6 (and
  /// thus every number in §10.2) would be void. The target is at the same time the
  /// answer to the question what happens at the last hop: whoever is the
  /// target itself stores; whoever is not forwards. No
  /// separate flag is needed for that.
  final Uint8List? target;
  final int hops;
  final Uint8List? raw;

  /// Only for harvest request and answer: the identifier by which the answer
  /// finds its return path.
  final Uint8List? requestId;

  SecureFrame(this.op,
      {this.tag,
      this.cell,
      this.tags = const [],
      this.records = const [],
      this.target,
      this.hops = 0,
      this.raw,
      this.requestId});
}

/// Reads a control frame. `null` for everything that does not fit — a
/// malformed frame carries no information (§2.6).
SecureFrame? parseSecureFrame(Uint8List body) {
  if (body.isEmpty) return null;
  switch (body[0]) {
    case SecureOp.place:
      // Tag and content are sealed — only what an
      // intermediate node NEEDS for forwarding comes out here.
      // +1 since S358: the retention class stands in the seal (see
      // [kRetentionSignal]), so the sealed part is one byte
      // longer than the minimum length before it.
      if (body.length <= kPlaceSealOffset + kAeadTagBytes + 32 + 1) return null;
      if (body[1] > kMaxPlaceHops) return null;
      return SecureFrame(SecureOp.place,
          hops: body[1],
          target: Uint8List.fromList(body.sublist(2, 34)),
          raw: Uint8List.fromList(body));
    case SecureOp.harvestRequest:
      // As with storing: only what an intermediate node
      // needs for forwarding comes out here. The tags are sealed.
      if (body.length <= kHarvestSealOffset + 16) return null;
      if (body[1] > kMaxPlaceHops) return null;
      return SecureFrame(SecureOp.harvestRequest,
          hops: body[1],
          requestId:
              Uint8List.fromList(body.sublist(2, 2 + kRequestIdBytes)),
          target: Uint8List.fromList(
              body.sublist(2 + kRequestIdBytes, 2 + kRequestIdBytes + 32)),
          raw: Uint8List.fromList(body));
    case SecureOp.peerAnnounce:
      if (body.length < 3) return null;
      final n = (body[1] << 8) | body[2];
      if (body.length < 3 + n * 32) return null;
      return SecureFrame(SecureOp.peerAnnounce, tags: [
        for (var i = 0; i < n; i++)
          Uint8List.fromList(body.sublist(3 + i * 32, 3 + (i + 1) * 32))
      ]);
    case SecureOp.entryRequest:
      // DIRECTED since S376 (P4-1): `op ‖ hops ‖ kennung ‖ ziel`.
      // `raw` MUST come along — an intermediate hop forwards the frame and
      // needs it whole for that (the same lesson as with `placeAck`).
      if (body.length != kEntryRequestBytes) return null;
      if (body[1] > kMaxPlaceHops) return null;
      return SecureFrame(SecureOp.entryRequest,
          hops: body[1],
          requestId: Uint8List.fromList(body.sublist(2, 2 + kRequestIdBytes)),
          target: Uint8List.fromList(
              body.sublist(2 + kRequestIdBytes, kEntryRequestBytes)),
          raw: Uint8List.fromList(body));
    case SecureOp.placeAck:
      if (body.length != kPlaceAckBytes) return null;
      // `raw` MUST stand here since the receipt has a return path
      // (S357): an intermediate hop forwards it unchanged, and for that
      // it needs the frame, not its components. Without this line
      // `c.raw!` throws at the first forwarded ack — measured as
      // „Null check operator used on a null value (op 8)", several times
      // per node, and the frame was gone afterwards. The same lesson as
      // `kForwardableOps`: whoever forwards a frame must have it
      // whole.
      return SecureFrame(SecureOp.placeAck,
          requestId:
              Uint8List.fromList(body.sublist(2, 2 + kRequestIdBytes)),
          cell: Uint8List.fromList([body[1]]),
          raw: Uint8List.fromList(body));
    case SecureOp.entrySetRequest:
      if (body.length < 2) return null;
      final n = body[1];
      if (n < 1 || n > kMaxEntryRequestPositions) return null;
      return SecureFrame(SecureOp.entrySetRequest, tags: [], records: const [],
          cell: Uint8List.fromList([n]));
    case SecureOp.entryResponse:
      // `op ‖ kennung(16) ‖ anzahl ‖ datensaetze` (S376, P4-1). The
      // identifier carries the return path of a DIRECTED request; an
      // unsolicited answer (`announceOwnEntry`, set answer)
      // carries the zero identifier.
      if (body.length < 2 + kRequestIdBytes) return null;
      final n = body[1 + kRequestIdBytes];
      // `n == 0` IS VALID (S376, P4-3): the empty answer says „I
      // have nothing" and releases the block at the asker. Here stood
      // `n < 1 → null`, and thus the frame could not even be built
      // without the decoder throwing it away.
      if (n > kMaxEntryRequestPositions) return null;
      final recs = <EntryRecord>[];
      var off = 2 + kRequestIdBytes;
      for (var i = 0; i < n; i++) {
        final r = EntryRecord.decodeAt(body, off);
        if (r == null) return null;
        recs.add(r.record);
        off = r.next;
      }
      return SecureFrame(SecureOp.entryResponse,
          requestId: Uint8List.fromList(body.sublist(1, 1 + kRequestIdBytes)),
          records: recs,
          raw: Uint8List.fromList(body));
    case SecureOp.harvestResponse:
      if (body.length < 1 + kRequestIdBytes + 1) return null;
      return SecureFrame(SecureOp.harvestResponse,
          requestId:
              Uint8List.fromList(body.sublist(1, 1 + kRequestIdBytes)),
          cell: Uint8List.fromList(body.sublist(1 + kRequestIdBytes)),
          raw: Uint8List.fromList(body));
    case SecureOp.findNode:
      // As with storing and harvest: only what an
      // intermediate node needs for forwarding comes out here. `target` is the
      // TARGET RELAY, not the search point — that lies in the seal.
      if (body.length != kFindNodeSealOffset + 32 + 16) return null;
      if (body[1] > kMaxPlaceHops) return null;
      return SecureFrame(SecureOp.findNode,
          hops: body[1],
          requestId: Uint8List.fromList(body.sublist(2, 2 + kRequestIdBytes)),
          target: Uint8List.fromList(
              body.sublist(2 + kRequestIdBytes, 2 + kRequestIdBytes + 32)),
          raw: Uint8List.fromList(body));
    case SecureOp.findNodeOnion:
      // The same header as the search request, hence the same parsing.
      // `target` is here the BLIND RELAY — the target relay lies in the
      // seal and is not present for a forwarding hop.
      //
      // The length is the depth cap (see [lookupOnionDepth]): it
      // admits 1..[kLookupOnionShells] shells and nothing else. A
      // forwarding hop thereby checks the depth without being able to open
      // the shell.
      if (lookupOnionDepth(body.length) == 0) return null;
      if (body[1] > kMaxPlaceHops) return null;
      return SecureFrame(SecureOp.findNodeOnion,
          hops: body[1],
          requestId: Uint8List.fromList(body.sublist(2, 2 + kRequestIdBytes)),
          target: Uint8List.fromList(
              body.sublist(2 + kRequestIdBytes, 2 + kRequestIdBytes + 32)),
          raw: Uint8List.fromList(body));
    case SecureOp.findNodeResponse:
      if (body.length < 2 + kRequestIdBytes) return null;
      final count = body[1 + kRequestIdBytes];
      if (count > kMaxFindNodePositions) return null;
      if (body.length != 2 + kRequestIdBytes + count * 32) return null;
      final from = 2 + kRequestIdBytes;
      return SecureFrame(SecureOp.findNodeResponse,
          requestId: Uint8List.fromList(body.sublist(1, 1 + kRequestIdBytes)),
          tags: [
            for (var i = 0; i < count; i++)
              Uint8List.fromList(body.sublist(from + i * 32, from + (i + 1) * 32))
          ],
          raw: Uint8List.fromList(body));
    default:
      return null;
  }
}

/// Maximum number of positions per entry request.
///
/// WHY A LIMIT AT ALL. The answer is forwarding traffic and
/// may go out immediately, without a slot (appendix B-17). What was small as long as an
/// answer fit into one cell would be a burst here: every record
/// costs two cells, eight positions thus sixteen cells in a row. Four
/// limits the swing to eight cells and still leaves enough to build a
/// neighbourhood in a few rounds.
const int kMaxEntryRequestPositions = 4;

/// How many DIRECTED entry requests a run enqueues at most.
///
/// TWO, and the number is a slot calculation. Until S376 ONE frame carried
/// up to [kMaxEntryRequestPositions] positions; directed it is one
/// frame PER position, i.e. up to four slots instead of one. Four per run
/// would be, with a run every [V41Node.entryFetchEverySlots] = 8 slots,
/// half a slot of continuous load for procurement alone — and the
/// lookup enqueues as many again in the same round.
///
/// Two directed requests carry more than four undirected ones: they
/// reach the one who has the record, instead of the one chance
/// chose.
const int kEntryRequestsPerRound = 2;

/// Maximum number of missed positions a node remembers.
///
/// The memo is filled by foreign search answers
/// (`responsibleRelays` sees positions that came from the network); without
/// a cap a neighbour could inflate it at will. Twenty is a
/// full responsibility set ([kResponsibleRelays]) — no one needs more
/// at the same time.
const int kMaxMissingEntries = 20;

/// Length of a directed entry request.
///
/// `op(1) ‖ hops(1) ‖ kennung(16) ‖ ziel(32)` = 50 B — far below the
/// frame body of 1169 B, i.e. one cell without fragmentation.
const int kEntryRequestBytes = 2 + kRequestIdBytes + 32;

/// Builds a DIRECTED entry request for ONE position.
///
/// ══════════════════════════════════════════════════════════════════════
/// WHY DIRECTED AND NO LONGER A LIST (S376, P4-1)
/// ══════════════════════════════════════════════════════════════════════
///
/// Until S376 the frame was `op ‖ anzahl ‖ positionen` — without target and
/// without hop counter. It thus went to ONE random partner
/// (`DeliveryNode.tick` chooses round-robin), and its handler answered
/// it exclusively from its OWN supply and asked nothing further.
/// Whoever did not have the record stayed silent.
///
/// The consequence showed in the lookup: `netzZustaendig` finds the R nearest
/// positions of the NETWORK, `responsibleRelays` throws out every one of them without
/// an entry record (it is not addressable — `buildPlace`
/// needs `x25519Public` from the record). The searched network set
/// could thus become SMALLER than the table set, and procurement
/// was a lucky hit at the randomly chosen partner.
///
/// §11.1 demands „fetched on demand … ask the one who announced the
/// position". The frame therefore now runs like [buildFindNode]
/// and the harvest request: greedily to the TARGET, with hop counter and
/// return-path identifier. Every hop that has the record answers immediately
/// (that is the regular case — the neighbours of a position know it);
/// whoever does not have it forwards.
///
/// ONE position per frame, and that is not a restriction but the
/// consequence of the direction: two positions have two targets and run
/// different paths. The cap against too many requests now lies with the
/// caller ([V41Node.requestEntries]), where it belongs.
///
/// NO SEAL over the target, unlike with [buildFindNode]. There the
/// search point lies closed because it is computed from a PAIR tag
/// and would reveal the linkage „which pair is searching at the moment" (§9.1,
/// E-L). Here the target is the position of a RELAY — infrastructure that
/// is announced openly anyway (`peerAnnounce`) and that every hop
/// MUST read for forwarding. A seal would protect nothing here and
/// would make the frame unroutable.
Uint8List buildEntryRequest(
  Uint8List target,
  Uint8List requestId, {
  int hops = kMaxPlaceHops,
}) {
  if (target.length != 32) throw ArgumentError('Target must be 32 B');
  if (requestId.length != kRequestIdBytes) {
    throw ArgumentError('identifier must be $kRequestIdBytes B');
  }
  if (hops < 0 || hops > kMaxPlaceHops) {
    throw ArgumentError('Hops 0..$kMaxPlaceHops');
  }
  final out = Uint8List(kEntryRequestBytes);
  var o = 0;
  out[o++] = SecureOp.entryRequest;
  out[o++] = hops;
  out.setRange(o, o += kRequestIdBytes, requestId);
  out.setRange(o, o += 32, target);
  return out;
}

/// The identifier of an UNSOLICITED entry answer: all zeros.
///
/// `announceOwnEntry` and the answer to a set request belong to
/// no directed request. They therefore carry the zero identifier, and
/// `PendingRequests` carries no such one — an unsolicited answer
/// can thus not redeem a foreign return path.
final Uint8List kUnsolicitedRequestId = Uint8List(kRequestIdBytes);

/// Is this identifier the zero identifier?
bool isUnsolicited(Uint8List id) {
  for (final b in id) {
    if (b != 0) return false;
  }
  return true;
}

/// Builds an entry answer: `op(1) ‖ count(1) ‖ records`.
///
/// The result is larger than a frame body and must go through
/// `fragmentFrame` — the caller does that, because only it knows whether it sends in
/// slots or immediately.
///
/// ── THE EMPTY ANSWER IS PERMISSIBLE (S376, P4-3) ─────────────────────
///
/// "I have nothing" is an answer and ends the waiting of the
/// asker. Until S376 this place threw on `records.isEmpty`, the
/// receiver therefore stayed silent (`delivery_node.dart`, "keine
/// Eintrittsdaten zum Weitergeben") — and the block of the set request
/// at the asker stood until restart. A frame with `n = 0` is
/// 18 B long (`op ‖ identifier(16) ‖ count`, measured) and costs a
/// slot that carries a cell anyway.
Uint8List buildEntryResponse(List<EntryRecord> records,
    {Uint8List? requestId}) {
  if (records.length > kMaxEntryRequestPositions) {
    throw ArgumentError(
        '0..$kMaxEntryRequestPositions records, not ${records.length}');
  }
  final id = requestId ?? kUnsolicitedRequestId;
  if (id.length != kRequestIdBytes) {
    throw ArgumentError('identifier must be $kRequestIdBytes B');
  }
  final parts = records.map((r) => r.encode()).toList();
  final total = parts.fold<int>(0, (a, b) => a + b.length);
  final out = Uint8List(2 + kRequestIdBytes + total);
  var o = 0;
  out[o++] = SecureOp.entryResponse;
  out.setRange(o, o += kRequestIdBytes, id);
  out[o++] = records.length;
  for (final p in parts) {
    out.setRange(o, o += p.length, p);
  }
  return out;
}

/// Builds the request for arbitrary entry records.
Uint8List buildEntrySetRequest(int count) {
  if (count < 1 || count > kMaxEntryRequestPositions) {
    throw ArgumentError('1..$kMaxEntryRequestPositions, not $count');
  }
  return Uint8List.fromList([SecureOp.entrySetRequest, count]);
}

/// Deposit accepted.
const int kPlaceStored = 0x01;

/// Storing rejected — the relay's quota is full.
const int kPlaceRefused = 0x00;

/// The identifier by which a storing confirmation finds its return path.
///
/// **It does NOT stand on the wire — it is computed from the frame.**
/// Every hop that sees a stored item computes the same number; the
/// sender computes it from the frame it has just built. Thus
/// the stored item needs no additional field, and `kMaxPlaceContentBytes`
/// stays at 1041 B — the number on which §9.2 and AP-7 calculate.
///
/// IT IS COMPUTED FROM THE EPHEMERAL PUBLIC KEY. It is fresh per
/// [buildPlace] call, so different per leg (the sender stores
/// the same cell at `m x R` relays and must be able to tell the confirmations
/// apart), and it lies in plaintext, so every
/// hop can read it. It survives forwarding: [decrementHops] touches
/// only byte 1.
///
/// WHY HASHED AND NOT TRUNCATED. The value travels to nodes that
/// never saw the frame themselves (along the return path). A
/// prefix of the key would be a piece of key material there; a
/// hash is an identifier.
Uint8List placeRequestId(Uint8List placeBody) {
  if (placeBody.length < 66) {
    throw ArgumentError('Not a store frame: ${placeBody.length} B');
  }
  final eph = Uint8List.sublistView(placeBody, 34, 66);
  final h = SodiumFFI().hkdfSha256(
    Uint8List.fromList(eph),
    salt: Uint8List(0),
    info: Uint8List.fromList(utf8.encode('cleona-place-ack/v1')),
    length: kRequestIdBytes,
  );
  return h;
}

/// Builds the storing confirmation: `op(1) ‖ status(1) ‖ kennung(16)`.
///
/// ── HERE STOOD THE TAG, AND THAT WAS A LEAK (S357) ──────────────────
///
/// Until S357 the body read `op(1) ‖ status(1) ‖ tag(32)`. The tag is
/// the mailbox line of a pair — exactly the value that IP-1 removed from the
/// plaintext of the stored item, with the reasoning in the header of
/// [buildPlace]: „before, every hop read the tag along, and the tag is the
/// mailbox line of a pair". The confirmation handed it back to the
/// predecessor hop in plaintext and thus took back on the return path
/// what the outward path had just protected.
///
/// The identifier achieves the same without revealing anything: it relates the
/// confirmation to EXACTLY THIS leg (see [placeRequestId]), and it
/// is a random value for everyone except the sender.
Uint8List buildPlaceAck(Uint8List requestId,
    {required bool stored, required Uint8List ackKey}) {
  if (requestId.length != kRequestIdBytes) {
    throw ArgumentError('identifier must be $kRequestIdBytes B');
  }
  final out = Uint8List(kPlaceAckBytes);
  out[0] = SecureOp.placeAck;
  out[1] = stored ? kPlaceStored : kPlaceRefused;
  out.setRange(2, 2 + kRequestIdBytes, requestId);
  // THE MAC ALSO COVERS THE STATUS BYTE. If it lay only over the identifier,
  // a hop could rewrite a real rejection into an acceptance —
  // and the acceptance is the proof.
  out.setRange(2 + kRequestIdBytes, kPlaceAckBytes,
      _placeAckMac(ackKey, Uint8List.sublistView(out, 1, 2 + kRequestIdBytes)));
  return out;
}

/// Length of the storing confirmation: `op(1) ‖ status(1) ‖ kennung(16) ‖ mac(16)`.
const int kPlaceAckBytes = 2 + kRequestIdBytes + kPlaceAckMacBytes;

/// How many bytes of the HMAC travel along.
///
/// 16 B, not 32: the frame should stay small, and 128 bits are by far
/// enough for an authentication that applies only within one epoch and whose
/// identifier is consumed after first use.
const int kPlaceAckMacBytes = 16;

Uint8List _placeAckMac(Uint8List ackKey, Uint8List covered) =>
    Uint8List.sublistView(
        SodiumFFI().hmacSha256(ackKey, Uint8List.fromList(covered)),
        0,
        kPlaceAckMacBytes);

/// Does the confirmation [rawAck] carry the MAC of the relay at which storing
/// happened?
///
/// [ackKey] comes from the sender's book — it computed it from `ss` when building the
/// stored item (see [_placeAckKey]). If the MAC does not match,
/// the receipt was not issued by the target relay but by someone
/// on the way.
bool verifyPlaceAck(Uint8List rawAck, Uint8List ackKey) {
  if (rawAck.length != kPlaceAckBytes) return false;
  final expected = _placeAckMac(
      ackKey, Uint8List.sublistView(rawAck, 1, 2 + kRequestIdBytes));
  // Constant time: an early exit would be measurable.
  var diff = 0;
  for (var i = 0; i < kPlaceAckMacBytes; i++) {
    diff |= expected[i] ^ rawAck[2 + kRequestIdBytes + i];
  }
  return diff == 0;
}
