// The onion — two shells, fixed size, both post-quantum secure.
//
// THE STRUCTURE, AND WHY IT IS THIS WAY.
//
// An ML-KEM-768 ciphertext measures 1088 B (`oqs_ffi.dart:202`), the
// frame body 1169 B. A single ciphertext thus FITS — and leaves
// 81 B over. Of that, 32 B go to the r2 identifier and 16 B to the tag:
// **33 B of message per cell.** Two shells with one KEM each are excluded
// anyway at 2176 B.
//
// (The first version of this paragraph claimed a ciphertext did not fit at
// all — that was an artefact of the wrong cell size 950 B. The
// conclusion holds, the reason is different: it fits and leaves
// nothing over.)
//
// The whole forward path is nevertheless PQ — because NO shell carries a KEM in
// the cell, but both run on keys that come from already
// conducted hybrid link handshakes:
//
//   Shell 1 (for r1): under the link key A<->r1. A already has it.
//   Shell 2 (for r2): the PATH BLOCK — prebuilt by B, under the
//     link key B<->r2. B already has it.
//
// The path block is the reason why §6 describes liveness as „onion return
// path (never a bare exit-relay)": A does not get B's own
// identifier, but an opaque block.
//
// WHAT A STILL LEARNS — read carefully, too much has been claimed here
// once already: A must tell r1 where to forward, so
// `idOfR2` stands in A's own shell. **A knows r2.** What A can NOT do:
// open the block, read what r2 will read, or learn which handle
// lies behind r2. Whoever really wants to hide r2 from A as well needs a
// third hop — that is a different construction and not this one.
//
// NO LENGTH FIELD. The message area has a fixed size; r2 passes
// it on unseen. The true length belongs to the end-to-end layer
// (§4), which has its own frame anyway. A length field here would have
// revealed the message size to r1.
//
// FIXED SIZE ACROSS ALL STAGES. When r1 strips its shell, it replaces
// it with padding (Sphinx principle) — otherwise it would be readable from the length
// how deeply a cell is still nested (§5.1 invariant 2).
//
// NONCE. Both shells run under LONG-LIVED keys. A
// reused nonce breaks AES-GCM completely, which is why
// each shell carries its own seed from which its nonce is derived.
//
// REPLAY, AND WHY THE BLOCK IS BOUND TO ITS EPOCH.
//
// Whoever sees the block — r1 first of all — can present it again. r2
// therefore holds the seen seeds per epoch (appendix B-16).
//
// That alone is NOT enough: a replay protection that forgets per epoch
// opens a new window every epoch for a recorded block.
// That is why the epoch enters the KEY DERIVATION of the block. A
// block for epoch e can no longer be opened in e+1, and the
// forgetting of the guard is thus exactly right instead of dangerous.
//
// (Found because the test „in the next epoch the same block runs
// again" PASSED — passing behaviour is not the same as
// correct behaviour.)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/link/cell.dart' show kMaxFrameBodySize;

/// Seed from which the nonce of a shell is derived.
const int kSeedBytes = 16;

/// Length of a hop identifier or a receiver handle (`L_node`).
const int kHopIdBytes = 32;

/// AES-GCM-Tag.
const int kTagBytes = 16;

/// Payload of a cell — the body of ONE frame in the frozen
/// AP-3a format, not guessed.
///
/// Cell 1200 B = nonce 12 + ciphertext + tag 16 -> 1172 B plaintext; of that
/// 3 B go to `typ(1) ‖ laenge(2)`. The first version of this file
/// computed with 950 B — that was assumption A2 from M10, not the
/// frozen format. The number now comes from `link/cell.dart`, so that
/// it stands in only ONE place.
///
/// Side finding that fits together: AP-3a reserves
/// `kSingleCellSporeContentSize = kMaxFrameBodySize - 128` — and 128 B is
/// exactly the overhead of this onion (16 seed + 32 r2 identifier + 64
/// path block + 16 tag).
const int kOnionCellBytes = kMaxFrameBodySize;

/// The path block: seed + sealed handle + tag. Fixed size, so that
/// neither its length nor its content reveals anything.
const int kReplyBlockBytes = kSeedBytes + kHopIdBytes + kTagBytes; // 64

/// How much message fits into an onion.
///
/// 1169 - 16 (seed) - 32 (r2 identifier) - 64 (path block) - 16 (tag) = 1041 B.
/// Five aggregated short messages of 200 B each fit in — one more
/// than E-K had calculated with the 950-B assumption.
const int kMaxOnionMessageBytes = kOnionCellBytes -
    kSeedBytes -
    kHopIdBytes -
    kReplyBlockBytes -
    kTagBytes;

/// What a hop holds in hand after stripping.
final class PeeledCell {
  /// Whom to forward to — at the last hop the receiver handle from the
  /// path block.
  final Uint8List nextHop;

  /// The rest, padded back to full cell size. At the last hop
  /// the message area of fixed size.
  final Uint8List payload;

  PeeledCell(this.nextHop, this.payload);
}

Uint8List _key(Uint8List base, String info, Uint8List seed) =>
    SodiumFFI().hkdfSha256(base,
        salt: seed, info: Uint8List.fromList(utf8.encode(info)), length: 32);

Uint8List _nonce(Uint8List key, String info, Uint8List seed) =>
    SodiumFFI().hkdfSha256(key,
        salt: seed, info: Uint8List.fromList(utf8.encode(info)), length: 12);

/// The replay key of a forwarded cell: a fingerprint of the
/// WHOLE cell.
///
/// ── IT WAS THE SEED OF THE PATH BLOCK, AND THAT LOCKED SPEED (S355) ──
///
/// Until 30.08. this said
///
///     Uint8List.sublistView(replyBlock, 0, kSeedBytes)
///
/// i.e. the seed of the PATH BLOCK. The path block lies in the receiver's liveness record
/// and is CONSTANT per pair and epoch — the path-block
/// resolver explicitly relies on that („Because the path block
/// is CONSTANT per pair and epoch, the cache hits from the second cell
/// on"). Thus ALL Speed cells of a pair in an epoch carried
/// the same replay key, and the guard let exactly the FIRST
/// through. Epoch = 24 h.
///
/// Measured in the field (30.08., Alice<->Bob, pure Speed mode): six
/// messages out, NONE arrived, at the relay every single cell
/// `RelayReject.replay`. Earlier the same day exactly ONE delivered
/// Speed message of the pair — the first. Over the whole day at the
/// bootstrap: 15 delivered, 22 rejected as replay.
///
/// A REPLAY IS A REPEATED CELL, not a repeated
/// path block. The fingerprint over the whole cell catches exactly that: a
/// bit-identically re-injected cell has the same fingerprint, two
/// different messages over the same path block do not. Whoever changes a byte
/// gets a new fingerprint — and fails one line
/// later at the AEAD, without anything being remembered or delivered.
///
/// PRICE: one SHA-256 over 1169 B per forwarded cell, about 1.5 us.
/// At R_cover = 1/8 s per partner that is nothing; at the upper limit that
/// the path-block resolver sets at 24 064 cells/s on one core, it is
/// a good 3 % of a core. The second price is at [ReplayGuard]: the
/// set now grows with the cells, not with the pairs.
///
/// DEVIATION FROM APPENDIX B-16, which is before the owner: there the
/// countermeasure reads „the seen block seeds, held per epoch". Exactly this
/// wording creates the defect. The protective purpose of B-16 remains
/// fulfilled unchanged.
Uint8List replayKeyOf(Uint8List forwarded) => Uint8List.sublistView(
    SodiumFFI().sha256(forwarded), 0, kSeedBytes);

/// **B builds the path block.** It tells r2 only one thing: whom to deliver to.
///
/// [linkKeyToR2] is B's existing hybrid link key to r2 —
/// that is why this shell is post-quantum secure without carrying a KEM in the cell.
Uint8List buildReplyBlock({
  required Uint8List linkKeyToR2,
  required Uint8List handleOfB,
  required Uint8List seed,
  required int epoch,
}) {
  if (seed.length != kSeedBytes) {
    throw ArgumentError('Seed must be $kSeedBytes B');
  }
  if (handleOfB.length != kHopIdBytes) {
    throw ArgumentError('Handle must be $kHopIdBytes B');
  }
  final k = _key(linkKeyToR2, 'onion/block/$epoch', seed);
  final ct = SodiumFFI()
      .aesGcmEncrypt(handleOfB, k, _nonce(k, 'onion/block/nonce', seed));
  final out = Uint8List(kReplyBlockBytes);
  out.setRange(0, kSeedBytes, seed);
  out.setRange(kSeedBytes, kReplyBlockBytes, ct);
  return out;
}

/// **A builds the cell** by putting the path block into its own shell.
///
/// A does not decrypt the block and cannot — it knows neither
/// who r2 is nor where r2 delivers to.
Uint8List buildOnion({
  required Uint8List message,
  required Uint8List linkKeyToR1,
  required Uint8List idOfR2,
  required Uint8List replyBlock,
  required Uint8List seed,
}) {
  if (message.length > kMaxOnionMessageBytes) {
    throw ArgumentError('Message is ${message.length} B, an onion '
        'carries $kMaxOnionMessageBytes B');
  }
  if (replyBlock.length != kReplyBlockBytes) {
    throw ArgumentError('Route block must be $kReplyBlockBytes B');
  }

  // Fixed message area: no message size can be read from outside,
  // and r1 does not learn it either.
  final inner = Uint8List(kHopIdBytes + kReplyBlockBytes + kMaxOnionMessageBytes);
  inner.setRange(0, kHopIdBytes, idOfR2);
  inner.setRange(kHopIdBytes, kHopIdBytes + kReplyBlockBytes, replyBlock);
  inner.setRange(kHopIdBytes + kReplyBlockBytes,
      kHopIdBytes + kReplyBlockBytes + message.length, message);

  final k1 = _key(linkKeyToR1, 'onion/hop1', seed);
  final ct = SodiumFFI()
      .aesGcmEncrypt(inner, k1, _nonce(k1, 'onion/hop1/nonce', seed));

  final cell = Uint8List(kOnionCellBytes);
  cell.setRange(0, kSeedBytes, seed);
  cell.setRange(kSeedBytes, kSeedBytes + ct.length, ct);
  if (kSeedBytes + ct.length != kOnionCellBytes) {
    throw StateError('Cell is ${kSeedBytes + ct.length} B instead of '
        '$kOnionCellBytes — the layer sizes do not match');
  }
  return cell;
}

/// **r1 strips its shell.** It learns r2 and nothing else.
PeeledCell? peelFirstHop({
  required Uint8List cell,
  required Uint8List linkKeyToR1,
}) {
  if (cell.length != kOnionCellBytes) return null;
  final seed = Uint8List.sublistView(cell, 0, kSeedBytes);
  final k1 = _key(linkKeyToR1, 'onion/hop1', seed);
  Uint8List opened;
  try {
    opened = SodiumFFI().aesGcmDecrypt(Uint8List.sublistView(cell, kSeedBytes),
        k1, _nonce(k1, 'onion/hop1/nonce', seed));
  } catch (_) {
    return null; // silent: a failure would be a measurable event (E-83)
  }
  if (opened.length < kHopIdBytes + kReplyBlockBytes) return null;

  // The stripped shell is replaced by padding — otherwise the cell would
  // visibly shrink.
  final forward = Uint8List(kOnionCellBytes);
  final rest = Uint8List.sublistView(opened, kHopIdBytes);
  forward.setRange(0, rest.length, rest);
  return PeeledCell(
      Uint8List.fromList(Uint8List.sublistView(opened, 0, kHopIdBytes)),
      forward);
}

/// **r2 redeems the path block.** It learns whom to deliver to —
/// not whom the cell came from.
PeeledCell? redeemReplyBlock({
  required Uint8List forwarded,
  required Uint8List linkKeyToB,
  required int epoch,
}) {
  if (forwarded.length < kReplyBlockBytes) return null;
  final block = Uint8List.sublistView(forwarded, 0, kReplyBlockBytes);
  final seed = Uint8List.sublistView(block, 0, kSeedBytes);
  final k = _key(linkKeyToB, 'onion/block/$epoch', seed);
  Uint8List handle;
  try {
    handle = SodiumFFI().aesGcmDecrypt(
        Uint8List.sublistView(block, kSeedBytes), k,
        _nonce(k, 'onion/block/nonce', seed));
  } catch (_) {
    return null;
  }
  if (handle.length != kHopIdBytes) return null;
  final message = Uint8List.sublistView(
      forwarded, kReplyBlockBytes, kReplyBlockBytes + kMaxOnionMessageBytes);
  return PeeledCell(Uint8List.fromList(handle), Uint8List.fromList(message));
}
