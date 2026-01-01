// The bulk lane on the WIRE (§9.3) — placement, scanning, answer.
//
// ── THE 27 BYTES, AND WHY THEY ARE NOT A QUESTION OF THE NUMBER ─────────────
//
// A sealed block measures [kSealedBulkBlockBytes] = 1069 B
// (`bulk_block_seal.dart`: 12 + 1041 + 16). A PLACE frame of the
// delivery layer carries `kMaxPlaceContentBytes` = 1042 B
// (`tagline/secure_frames.dart`). 27 B too many, and `buildPlace` throws.
//
// Three ways out were on the table. Two were ruled out by measurement:
//
//   (a) **Make the PLACE frame larger.** Not possible. Its overhead
//       is 1169 - 1042 = 127 B and every byte of it carries something:
//       `op(1) ‖ hops(1)` for the greedy forwarding, `ziel(32)` for the
//       route choice, `eph(32) ‖ nonce(12) ‖ AEAD(16)` for the seal that
//       hides the tag from the intermediate nodes, `tag(32)` and
//       `klasse(1)` inside. To gain 27 B the seal would have to
//       go — and then it is no longer a PLACE frame.
//
//   (b) **Make the block smaller.** The most expensive of the three. 1041 B is
//       not a constant but the reference point of a MEASUREMENT: the
//       whole overhead curve in `bulk_params.dart`
//       (`measuredFountainOverhead`, 16 KiB -> 1,546 … 200 MiB -> 1,021)
//       is measured at 1024 B payload per block. Whoever
//       trims the block turns a measured curve into a claim —
//       and §9.3 moreover explicitly freezes the size
//       ("block payload frozen against the 1041 B AP-7 reference").
//
//   (c) **Its own frame class without the PLACE header.** Chosen — and
//       not as a way out, but because §9.3 says so verbatim:
//       "The payload is emitted as uniform 1200 B cells of **entry type
//       `0x05`**". The frame type has been frozen since AP-7
//       (`link/frame.dart:79`), `bulk_block_seal.dart:112` has built it since
//       30.08. — only the content around it was missing. The PLACE
//       frame was never the intended carrier; forcing it would have been
//       the detour, not doing without it.
//
// ── WHAT THE CHOICE COSTS, AND WHAT IT DOES NOT COST ────────────────────
//
// A PLACE frame hides the tag from every forwarding hop. These
// frames do not — and not out of convenience, but because
// it does not fit into one cell. Recomputed, with the same shape
// as `buildPlace`:
//
//   op(1) + hops(1) + target(32) + eph(32) + nonce(12) + AEAD(16)
//         + line(32) + block(1069)                           = 1195 B
//   + frame header(3)                                        = 1198 B
//   against kCellPlaintextSize                               = 1172 B
//                                                            ---------
//                                                       26 B too many
//
// A sealed bulk frame thus needs TWO cells per block. That
// doubles the price of the whole lane — §9.3 computes a 5 MB photo at
// 7.6 MB and a 200 MB video at 304.7 MB; sealed it would be 15.2 MB
// and 609 MB — and it breaks the sentence "one block rides in **one** cell
// and is never fragmented" from `link/frame.dart:66-79`. The price is too
// high for what it buys, and what it buys is little:
//
// **On the wire stands NOT the transfer tag, but its
// epoch line** `linie = targetFor(marke, epoche)` = `H(marke ‖ e)`.
// That is the same value that the responsibility calculation forms anyway
// (§9.1) — it costs no additional bytes, because a target must be in the frame,
// and it is a ONE-WAY image of the tag. A hop that
// records it learns:
//
//   * that a transfer is running and how many of its blocks run over it
//     — that is B-29 ("start, end, rate and approximate size are
//     visible at both egresses"), i.e. an already declared limit;
//   * a 32 B string that falls out of `HKDF(K_T, "bulk/tag")`, and
//     `K_T` is DRAWN PER TRANSFER (`bulk_keys.dart`,
//     `BulkTransferKeys.fresh`) — not derived from `K_AB` since the
//     correction of 31.08. It can thus be bound to no identity, no pair
//     and no second transfer.
//
// In particular it does NOT learn the tag itself and therefore cannot
// precompute the lines of other epochs of the same transfer.
//
// **What goes beyond B-29 here and is therefore reported:** B-29
// names the HOLDER ("a holding relay sees uploader and downloader of
// the same transfer tag"), not the forwarding hop. That a
// hop too sees the epoch line is an — smaller — additional
// visibility. It is not introduced secretly: the proposal
// `docs/v4-redesign/S363-VORLAGE-bulk-drahtformat.md` puts it to the owner
// to update the sentence in B-29/§9.3. Nothing is changed in the document
// (working rule 4).
//
// ── THE SIZES, RECOMPUTED ──────────────────────────────────────
//
//   cell plaintext                     kCellPlaintextSize  = 1172 B
//   of which frame header `typ(1) ‖ len(2)`                =    3 B
//   thus frame body                                        = 1169 B
//
//   BULK_PLACE  op(1) hops(1) holder(32) line(32) block(1069) = 1135  ok (34 free)
//   BULK_SCAN   op(1) hops(1) holder(32) id(16) line(32)
//               limit(2) havecount(2) have(32 each)          <= 1169  ok
//   BULK_BLOCK  op(1) id(16) line(32) block(1069)             = 1118  ok (51 free)
//
// [kBulkFrameFitsCell] pins this down at build time — a later change
// to the block size or to a header is noticed immediately.
//
// NO STATE, NO I/O, NO CLOCK.
library;

import 'dart:typed_data';

import 'package:cleona/core/link/cell.dart'
    show kCellPlaintextSize, kMaxFrameBodySize;
import 'package:cleona/core/link/frame.dart' show LinkFrame, LinkFrameType;

import 'bulk_block_seal.dart' show kSealedBulkBlockBytes;

/// The actions of the bulk lane. First byte in the body of a
/// `0x05` frame.
///
/// **They live INSIDE the frame type 0x05 and not next to it.**
/// The same shape as for the control channel `0x04`: AP-3a froze the
/// outer frame types and explicitly left their INSIDE open.
/// Whoever invented new outer types here would thaw the freeze.
abstract final class BulkOp {
  /// Place this block under this line.
  static const int place = 0x01;

  /// Give me what lies under this line (scanning, §26.6.1).
  static const int scanRequest = 0x02;

  /// A block as the answer to a scan.
  static const int scanResponse = 0x03;

  /// End of a scan round: "that was everything I had for this
  /// request" — even if it was nothing.
  ///
  /// ── WHY THIS FRAME MUST EXIST, COMPUTED ──────────────────
  ///
  /// Without it the asker has no signal when a ROUND is finished,
  /// and must hang its resubmission on the individual block arrival.
  /// With [kBulkScanRelaysPerRound] holders of
  /// [kBulkScanResponseLimit] blocks each, that is 128 arrivals per round —
  /// and each would trigger a new round. An avalanche, not scanning.
  ///
  /// One end PER REQUEST on the other hand costs 4 cells at 51 B against up to 128
  /// blocks at 1118 B, i.e. roughly **3 %**. And because it comes EVEN with zero
  /// hits, the asker distinguishes "this holder has
  /// nothing more" from "the answer is still in transit" — without a clock and
  /// without polling (working rule 5, §19 "no polling").
  static const int scanEnd = 0x04;

  /// An UNSOLICITED block in a cover cell that is due anyway
  /// (§5.5 "Cover fill carries fountain blocks").
  ///
  /// ── WHY IT CANNOT BE ONE OF THE FOUR ABOVE ──────────────
  ///
  /// The four above are the BULK LANE: demand-driven and declared
  /// (§9.3, B-29). Each of them presupposes something that the fill
  /// lacks:
  ///
  ///   * [place] and [scanRequest] carry a HOLDER and run greedily
  ///     on towards it — the fill goes to the partner that the
  ///     slot plan draws (§5.5 rule 2), and does NOT run on;
  ///   * [scanResponse] and [scanEnd] carry a REQUEST IDENTIFIER — there
  ///     is no request (§5.5 rule 4: no return channel).
  ///
  /// It is thus the THIRD path next to the stream lane and the bulk lane, and that
  /// is stated nowhere in the architecture document so far — the clarifying sentence
  /// lies with the owner as a proposal
  /// (`docs/v4-redesign/S365-VORLAGE-dritter-weg-und-wurzel.md`,
  /// section 2). Until then this place carries the rationale.
  ///
  /// ── WHY THE BODY CARRIES ONLY THE BLOCK AND NO IDENTIFIER ───────
  ///
  /// The obvious thing would have been to put the `objectId` (8 B prefix of the
  /// content hash) in front of the block, so that the receiver knows
  /// which key to take. That is NOT built, for
  /// two reasons, of which the second is the weightier:
  ///
  ///   1. **Leaving it out costs nothing.** The receiver holds
  ///      at most a handful of known update objects (running
  ///      version per platform) and tries them one after the other —
  ///      `openBulkBlock` fails at the AEAD in a few microseconds, and
  ///      at most ONE cell per slot comes in.
  ///   2. **An identifier would be a version-state leak.** The `objectId`
  ///      names exactly one binary of exactly one version and
  ///      platform. Whoever pushes it tells its sync partner which
  ///      version it has — and §26.6.2 explicitly states that the
  ///      fetch path "reveals nothing about the fetcher's starting
  ///      version". The push path must not be worse than the
  ///      fetch path.
  ///
  /// **Not forwardable** ([kForwardableBulkOps]): a forwarding
  /// would be an additional cell and thus violate §5.5 rule 1 ("never a slot
  /// of its own"). The spread comes about because EVERY node
  /// fills its OWN due cover slots, not because a
  /// frame runs on.
  static const int publicBlock = 0x05;
}

/// Length of the request identifier — the same as for the harvest
/// (`tagline/secure_frames.dart`, `kRequestIdBytes`).
///
/// Deliberately the same number and yet its own constant: it stands
/// here so that this module does not have to point to the delivery layer.
/// `smoke_bulk_wire.dart` keeps
/// both numbers together.
const int kBulkRequestIdBytes = 16;

/// Maximum number of forwardings. The same calculation as `kMaxPlaceHops`.
const int kMaxBulkHops = 8;

/// The frame body that a cell carries: 1172 − 3.
const int kBulkBodyBytes = kCellPlaintextSize - 3;

/// Size of a placement: `op ‖ hops ‖ halter(32) ‖ linie(32) ‖ block`.
const int kBulkPlaceBytes = 1 + 1 + 32 + 32 + kSealedBulkBlockBytes;

/// Fixed header of a scan request, without the have-list:
/// `op ‖ hops ‖ halter(32) ‖ id ‖ linie(32) ‖ limit(2) ‖ skip(2) ‖ n(2)`.
const int kBulkScanHeaderBytes =
    1 + 1 + 32 + kBulkRequestIdBytes + 32 + 2 + 2 + 2;

/// How many block tags the have-list of a request carries at most.
///
/// COMPUTED, NOT SET: what fits into the frame body after the header.
/// Whoever adds a field automatically shrinks the list along with it
/// and does not have to think of it.
const int kBulkScanHaveSlots = (kBulkBodyBytes - kBulkScanHeaderBytes) ~/ 32;

/// Size of a scan answer: `op ‖ id ‖ linie(32) ‖ block`.
const int kBulkBlockBytes =
    1 + kBulkRequestIdBytes + 32 + kSealedBulkBlockBytes;

/// Size of a round end: `op ‖ id ‖ line(32) ‖ count(2)`.
const int kBulkScanEndBytes = 1 + kBulkRequestIdBytes + 32 + 2;

/// Size of a cover fill: `op ‖ block`. Nothing else — the rationale
/// is at [BulkOp.publicBlock].
const int kBulkPublicBlockBytes = 1 + kSealedBulkBlockBytes;

/// Proof at build time that all frames fit into ONE cell.
const bool kBulkFrameFitsCell = kBulkPlaceBytes <= kBulkBodyBytes &&
    kBulkScanHeaderBytes + kBulkScanHaveSlots * 32 <= kBulkBodyBytes &&
    kBulkBlockBytes <= kBulkBodyBytes &&
    kBulkScanEndBytes <= kBulkBodyBytes &&
    kBulkPublicBlockBytes <= kBulkBodyBytes &&
    kBulkBodyBytes <= kMaxFrameBodySize;

/// How many blocks a holder returns at most for ONE scan.
///
/// ── WHY IT NEEDS A CAP (working rule 5) ──────────────────
///
/// A tag line can hold tens of thousands of blocks (a 200 MB video is
/// ~256 000). If a holder answered everything at once, that would be a
/// traffic burst of 274 MB from a single request — exactly what
/// `R_bulk` is supposed to limit, only on the answer side, where the asker cannot
/// throttle it.
///
/// With the cap the ASKER sets the pace: it scans again
/// when it wants more. The number is chosen so that one answer occupies about
/// one second of bulk rate (`kBulkRateCellsPerSecond` = 32) — a
/// holder that sends a burst thus sends at most as
/// much as a sender would be allowed to place in the same time.
const int kBulkScanResponseLimit = 32;

/// How many responsible relays ONE scan run addresses.
///
/// ── WHY NOT ALL TWENTY AND NOT JUST ONE ───────────────────
///
/// §9.3 distributes the blocks ROUND-ROBIN over the responsible relays — whoever asks only
/// one gets on average one twentieth of the object and is
/// never finished. Asking all twenty at once, on the other hand, is a burst
/// of up to 640 blocks (684 KB) from a single action.
///
/// Four per run, with rotating offset: after five runs the
/// set has been covered once, and a run carries at most 128 blocks
/// (137 KB). The number stands here and not at the transport, because
/// [BulkOp.scanEnd] refers to it in its rationale.
const int kBulkScanRelaysPerRound = 4;

/// Builds a placement: one block, one holder, one line.
///
/// [holder] is the position (`L_node`) of the CHOSEN responsible
/// relay — the caller chooses it round-robin (`BulkPlacementPlan`), exactly
/// as §9.3 requires ("round-robin across the set"). The forwarding
/// runs greedily there, as with a placement of the delivery layer.
///
/// [line] is `targetFor(marke, epoche)` — NOT the tag. See the
/// file header.
Uint8List buildBulkPlace(
  Uint8List holder,
  Uint8List line,
  Uint8List sealedBlock, {
  int hops = kMaxBulkHops,
}) {
  if (holder.length != 32) throw ArgumentError('Holder must be 32 B');
  if (line.length != 32) throw ArgumentError('Line must be 32 B');
  if (sealedBlock.length != kSealedBulkBlockBytes) {
    throw ArgumentError('Block must be $kSealedBulkBlockBytes B, is '
        '${sealedBlock.length}');
  }
  if (hops < 0 || hops > kMaxBulkHops) {
    throw ArgumentError('Hops 0..$kMaxBulkHops');
  }
  final out = Uint8List(kBulkPlaceBytes);
  var o = 0;
  out[o++] = BulkOp.place;
  out[o++] = hops;
  out.setRange(o, o += 32, holder);
  out.setRange(o, o += 32, line);
  out.setRange(o, out.length, sealedBlock);
  return out;
}

/// Builds a scan request.
///
/// [have] is the have-list (`BulkReceiver.haveList`, block tags). It
/// is truncated to [kBulkScanHaveSlots] — what no longer fits in,
/// the asker simply gets once more and discards itself. A
/// scan must not fail because of it.
/// [skip] skips the first so many entries of THIS line at
/// THIS holder before the have-list is applied.
///
/// ── WHY THE HAVE-LIST ALONE IS NOT ENOUGH, COMPUTED ────────────
///
/// [kBulkScanHaveSlots] = 33 tags fit into the frame. A 5 MB photo
/// is 6348 blocks. From the third round on the asker thus declares
/// only the first 33 of its tags, the holder skips exactly
/// these and sends from index 33 — of which the asker already has everything except
/// ONE block. Recomputed: **+1 new block per round with
/// 31 discarded**, i.e. roughly 200 000 blocks on the wire instead of 6348.
/// Factor 32, and thus a violation of working rule 5 that only becomes visible in
/// a REAL transfer — in the smallest admissible
/// transfer (47 blocks) it goes unnoticed.
///
/// [skip] fixes that with two bytes: the asker keeps PER HOLDER
/// how many entries this holder has already offered it — the number
/// is in the [BulkOp.scanEnd] of the previous round. **Per holder and not per
/// transfer**: because of the round-robin from §9.3 every holder holds its
/// own subset, a shared counter would skip the wrong thing at all
/// the others.
///
/// The have-list stays alongside and does not become superfluous:
/// [skip] is a POSITION in a list that can shift through eviction
/// (`BulkCache.evicted`) and expiry; the have-list
/// is content-based and catches exactly that.
Uint8List buildBulkScan(
  Uint8List holder,
  Uint8List requestId,
  Uint8List line, {
  Iterable<Uint8List> have = const <Uint8List>[],
  int limit = kBulkScanResponseLimit,
  int skip = 0,
  int hops = kMaxBulkHops,
}) {
  if (holder.length != 32) throw ArgumentError('Holder must be 32 B');
  if (line.length != 32) throw ArgumentError('Line must be 32 B');
  if (requestId.length != kBulkRequestIdBytes) {
    throw ArgumentError('identifier must be $kBulkRequestIdBytes B');
  }
  if (hops < 0 || hops > kMaxBulkHops) {
    throw ArgumentError('Hops 0..$kMaxBulkHops');
  }
  final capped = <Uint8List>[];
  for (final h in have) {
    if (capped.length >= kBulkScanHaveSlots) break;
    if (h.length != 32) continue;
    capped.add(h);
  }
  final n = limit < 1
      ? 1
      : (limit > kBulkScanResponseLimit ? kBulkScanResponseLimit : limit);
  final out = Uint8List(kBulkScanHeaderBytes + capped.length * 32);
  var o = 0;
  out[o++] = BulkOp.scanRequest;
  out[o++] = hops;
  out.setRange(o, o += 32, holder);
  out.setRange(o, o += kBulkRequestIdBytes, requestId);
  out.setRange(o, o += 32, line);
  out[o++] = (n >> 8) & 0xff;
  out[o++] = n & 0xff;
  // CLAMPED TO 16 BITS, NOT THROWN: `skip` is an acceleration,
  // not a condition. An asker with more than 65 535 already seen
  // entries at ONE holder gets duplicates again from then on and thus
  // falls back to the behaviour without `skip` — slower, never wrong.
  // A throw at this place would turn a slow harvest into a
  // failed one.
  final sk = skip < 0 ? 0 : (skip > 0xffff ? 0xffff : skip);
  out[o++] = (sk >> 8) & 0xff;
  out[o++] = sk & 0xff;
  out[o++] = (capped.length >> 8) & 0xff;
  out[o++] = capped.length & 0xff;
  for (final h in capped) {
    out.setRange(o, o += 32, h);
  }
  return out;
}

/// Builds an answer: ONE block, with the request's identifier.
///
/// One block per frame and not several — the same rationale as in
/// `bulk_block_seal.dart`: two blocks do not fit into one cell, and
/// spreading one over two cells would be the fragmentation that the
/// block size precisely avoids.
Uint8List buildBulkBlock(
    Uint8List requestId, Uint8List line, Uint8List sealedBlock) {
  if (requestId.length != kBulkRequestIdBytes) {
    throw ArgumentError('identifier must be $kBulkRequestIdBytes B');
  }
  if (line.length != 32) throw ArgumentError('Line must be 32 B');
  if (sealedBlock.length != kSealedBulkBlockBytes) {
    throw ArgumentError('Block must be $kSealedBulkBlockBytes B');
  }
  final out = Uint8List(kBulkBlockBytes);
  var o = 0;
  out[o++] = BulkOp.scanResponse;
  out.setRange(o, o += kBulkRequestIdBytes, requestId);
  out.setRange(o, o += 32, line);
  out.setRange(o, out.length, sealedBlock);
  return out;
}

/// Concludes a scan round: "this many I had for this
/// request" — **even for zero**.
///
/// The rationale is at [BulkOp.scanEnd]. [count] is the DISTANCE
/// the holder covered in its line in the process — not the
/// number of hits. The two differ as soon as the have-list
/// has filtered something out, and whoever took the hit count would let the
/// asker fall behind the true position
/// (`BulkCache.scanFrom` computes it and explains it).
Uint8List buildBulkScanEnd(Uint8List requestId, Uint8List line, int count) {
  if (requestId.length != kBulkRequestIdBytes) {
    throw ArgumentError('identifier must be $kBulkRequestIdBytes B');
  }
  if (line.length != 32) throw ArgumentError('Line must be 32 B');
  final n = count < 0 ? 0 : (count > 0xffff ? 0xffff : count);
  final out = Uint8List(kBulkScanEndBytes);
  var o = 0;
  out[o++] = BulkOp.scanEnd;
  out.setRange(o, o += kBulkRequestIdBytes, requestId);
  out.setRange(o, o += 32, line);
  out[o++] = (n >> 8) & 0xff;
  out[o++] = n & 0xff;
  return out;
}

/// Builds a cover fill: ONE public block, without identifier, without
/// line, without hop counter (§5.5).
///
/// The frame is NOT passed on and NOT answered. What distinguishes it from
/// the four others and why it carries no object identifier
/// is at [BulkOp.publicBlock].
Uint8List buildBulkPublicBlock(Uint8List sealedBlock) {
  if (sealedBlock.length != kSealedBulkBlockBytes) {
    throw ArgumentError('Block must be $kSealedBulkBlockBytes B, is '
        '${sealedBlock.length}');
  }
  final out = Uint8List(kBulkPublicBlockBytes);
  out[0] = BulkOp.publicBlock;
  out.setRange(1, out.length, sealedBlock);
  return out;
}

/// A parsed bulk frame. Fields that do not belong to the action
/// stay `null`.
final class BulkFrame {
  final int op;

  /// Hop counter — only for [BulkOp.place] and [BulkOp.scanRequest].
  final int hops;

  /// The target position of the forwarding — only for [BulkOp.place] and
  /// [BulkOp.scanRequest].
  final Uint8List? holder;

  /// The epoch line `H(marke ‖ e)`.
  ///
  /// **`null` for [BulkOp.publicBlock]** — the cover fill has no
  /// tag line, because it is placed nowhere and scanned nowhere.
  /// Until S365 it was not optional; so the class comment
  /// ("Fields that do not belong to the action stay `null`") did not hold for
  /// this one field.
  final Uint8List? line;

  final Uint8List? requestId;
  final Uint8List? sealedBlock;
  final List<Uint8List> have;
  final int limit;

  /// For [BulkOp.scanRequest]: how many entries of the line are to be
  /// skipped. For [BulkOp.scanEnd]: which DISTANCE the holder
  /// covered in the process (not the hit count — see
  /// [buildBulkScanEnd]). Otherwise 0.
  final int count;

  /// The unparsed frame — for forwarding.
  final Uint8List raw;

  const BulkFrame({
    required this.op,
    required this.hops,
    required this.holder,
    this.line,
    required this.raw,
    this.requestId,
    this.sealedBlock,
    this.have = const <Uint8List>[],
    this.limit = 0,
    this.count = 0,
  });
}

/// Parses a bulk frame — or returns `null`.
///
/// **NO `throw`.** What comes from the wire is raw material (E-83): a
/// malformed frame is a cell one leaves lying, not a
/// program error. The same stance as `parseSecureFrame` and
/// `openBulkBlock`.
BulkFrame? parseBulkFrame(Uint8List body) {
  if (body.isEmpty) return null;
  switch (body[0]) {
    case BulkOp.place:
      if (body.length != kBulkPlaceBytes) return null;
      return BulkFrame(
        op: BulkOp.place,
        hops: body[1],
        holder: Uint8List.fromList(body.sublist(2, 34)),
        line: Uint8List.fromList(body.sublist(34, 66)),
        sealedBlock: Uint8List.fromList(body.sublist(66)),
        raw: body,
      );
    case BulkOp.scanRequest:
      if (body.length < kBulkScanHeaderBytes) return null;
      final haveNumber = (body[kBulkScanHeaderBytes - 2] << 8) |
          body[kBulkScanHeaderBytes - 1];
      if (body.length != kBulkScanHeaderBytes + haveNumber * 32) return null;
      if (haveNumber > kBulkScanHaveSlots) return null;
      final skip =
          (body[kBulkScanHeaderBytes - 4] << 8) | body[kBulkScanHeaderBytes - 3];
      final limit =
          (body[kBulkScanHeaderBytes - 6] << 8) | body[kBulkScanHeaderBytes - 5];
      final have = <Uint8List>[
        for (var i = 0; i < haveNumber; i++)
          Uint8List.fromList(body.sublist(
              kBulkScanHeaderBytes + i * 32, kBulkScanHeaderBytes + (i + 1) * 32))
      ];
      return BulkFrame(
        op: BulkOp.scanRequest,
        hops: body[1],
        holder: Uint8List.fromList(body.sublist(2, 34)),
        requestId: Uint8List.fromList(body.sublist(34, 34 + kBulkRequestIdBytes)),
        line: Uint8List.fromList(body.sublist(
            34 + kBulkRequestIdBytes, 66 + kBulkRequestIdBytes)),
        limit: limit < 1
            ? 1
            : (limit > kBulkScanResponseLimit ? kBulkScanResponseLimit : limit),
        count: skip,
        have: have,
        raw: body,
      );
    case BulkOp.scanEnd:
      if (body.length != kBulkScanEndBytes) return null;
      return BulkFrame(
        op: BulkOp.scanEnd,
        hops: 0,
        holder: null,
        requestId: Uint8List.fromList(body.sublist(1, 1 + kBulkRequestIdBytes)),
        line: Uint8List.fromList(
            body.sublist(1 + kBulkRequestIdBytes, 33 + kBulkRequestIdBytes)),
        count: (body[kBulkScanEndBytes - 2] << 8) | body[kBulkScanEndBytes - 1],
        raw: body,
      );
    case BulkOp.scanResponse:
      if (body.length != kBulkBlockBytes) return null;
      return BulkFrame(
        op: BulkOp.scanResponse,
        hops: 0,
        holder: null,
        requestId: Uint8List.fromList(body.sublist(1, 1 + kBulkRequestIdBytes)),
        line: Uint8List.fromList(
            body.sublist(1 + kBulkRequestIdBytes, 33 + kBulkRequestIdBytes)),
        sealedBlock: Uint8List.fromList(body.sublist(33 + kBulkRequestIdBytes)),
        raw: body,
      );
    case BulkOp.publicBlock:
      if (body.length != kBulkPublicBlockBytes) return null;
      return BulkFrame(
        op: BulkOp.publicBlock,
        hops: 0,
        holder: null,
        sealedBlock: Uint8List.fromList(body.sublist(1)),
        raw: body,
      );
    default:
      return null;
  }
}

/// The same frame with one hop less — for forwarding.
///
/// ── THE ALLOW LIST IS THE DANGEROUS LINE HERE TOO ─────────
///
/// The same trap as with `decrementHops` in the delivery layer: a
/// frame that runs on greedily and is not listed here never arrives,
/// without an error becoming visible anywhere (28.08.2026, 54
/// crashes). Therefore the set stands there as DATA and is checked
/// individually by `smoke_bulk_wire.dart`.
const Set<int> kForwardableBulkOps = <int>{
  BulkOp.place,
  BulkOp.scanRequest,
};

Uint8List? decrementBulkHops(Uint8List body) {
  if (body.length < 2 || body[1] == 0) return null;
  if (!kForwardableBulkOps.contains(body[0])) return null;
  final out = Uint8List.fromList(body);
  out[1] = body[1] - 1;
  return out;
}

/// Wraps a bulk frame body as a `0x05` frame.
LinkFrame bulkLinkFrame(Uint8List body) =>
    LinkFrame(LinkFrameType.fountain, body);
