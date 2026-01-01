// The Reed-Solomon media lane (§9.3, decision E-3 = D of 06.09.2026):
// stripes over cells, `N` fragments per `K` source blocks.
//
// ── THE CONTRADICTION THIS FILE RESOLVES ────────────────────────
//
// §9.3 names ~256 KB as the NORMATIVE lower limit of the rateless lanes
// and justifies it with its own measurement (appendix A): overhead 1.021
// at 200 MiB, 1.079 at 5 MiB, but **1.367 at 64 KiB with maximum 2.750**,
// and at 16 KiB two out of 4 000 runs did not reconstruct even with
// triple k. The code nevertheless set the limit at 32 KB — the band
// 32..256 KB, the NORMAL CASE PHOTO, thus ran exactly the lane that its
// own measurement shows to be the worst.
//
// It is resolved neither by lowering the document limit (that would be a
// refuted number in the leading document) nor by raising the cell path
// (256 KB are ~219 cells of 1200 B, at one cell per 8 s about 29 min
// per photo), but by a third lane in between.
//
// ── WHY THE WIRE DOES NOT CHANGE ───────────────────────────────
//
// A stripe fragment is **1024 B** long — exactly
// [kFountainBlockPayloadBytes]. Measured (S372):
//
//   ReedSolomon N=10 K=7, input 7 x 1024 B -> 10 fragments of 1024 B each
//   ReedSolomon N=11 K=7, input 7 x 1024 B -> 11 fragments of 1024 B each
//
// That is no coincidence but the split from `fountain_block.dart`:
// "1041 - 17 = 1024 … the payload is a power of two". `K` blocks of
// 1024 B yield an input divisible by `K`, hence fragments of the same
// size. Thus the WHOLE existing path carries the fragments unchanged:
// seal (`bulk/bulk_block_seal.dart`), frame (`bulk/bulk_frames.dart`,
// type `0x05`), egress (`bulk/bulk_egress.dart`), holder
// (`DeliveryNode._handleBulk`), scanning, harvest.
//
// And the band membership follows from `objectLength`, which is in the
// offer anyway (`BulkAnnounce`). **No new field, no new opcode, no wire
// change** — that is the reason why this lane joins the other two
// without protocol negotiation.
//
// ── THE OWN FORMAT BYTE IS NOT COSMETICS ─────────────────────────
//
// [kErasureVersion] = `0x02` versus `kFountainVersion` = `0x01`.
// `fountain_block.dart` itself describes what happens without it: the
// decoder "recomputes the neighbourhood from `(k, blockSeed)` itself",
// so it folds in EVERY payload that has a valid header — silently,
// without error, and `takeObject` delivers "a file that looks like a
// file". A stripe fragment with `0x01` in front would be exactly that.
// `FountainBlock.fromBytes` rejects `0x02`, [ErasureBlock.fromBytes]
// rejects `0x01`; the two formats cannot reach each other.
//
// NO I/O.
library;

import 'dart:typed_data';

import 'package:cleona/core/bulk/bulk_block_seal.dart';
import 'package:cleona/core/bulk/bulk_codec.dart';
import 'package:cleona/core/bulk/bulk_keys.dart';
import 'package:cleona/core/bulk/bulk_params.dart';
import 'package:cleona/core/codec/reed_solomon.dart';
import 'package:cleona/core/fountain/fountain_block.dart';

/// Format version of a stripe fragment. **Not** [kFountainVersion].
///
/// What hangs on this byte: the split of the seed into
/// `(stripe, n, index)` ([ErasureBlock]), the stripe width [kStripeK]
/// and the field GF(256) with the AES polynomial from `reed_solomon.dart`.
/// Whoever changes one of these makes every fragment unusable that
/// already lies in a tagline — and therefore increments this byte.
const int kErasureVersion = 0x02;

/// `K` — how many source blocks a stripe combines.
///
/// Taken over from [ReedSolomon.defaultK], not set anew: the same
/// number from which `recovery_line.dart` encodes the rescue bundle (§13.3).
const int kStripeK = ReedSolomon.defaultK;

/// How many bytes of an object one stripe covers: `K x 1024`.
const int kStripeSourceBytes = kStripeK * kFountainBlockPayloadBytes;

/// `N` — how many fragments a stripe produces. **DERIVED.**
///
/// ── THE DERIVATION, SO THAT NOBODY READS IT AS A CHOSEN NUMBER ───────
///
/// ```
///   N = K + d
///     = ReedSolomon.defaultK + coveredHolderFailures(holders: R)
///     = 7 + 4                                    (at R = 20)
///     = 11        ->  N/K = 1.5714
/// ```
///
/// Both summands stand in the tree and are not re-evaluated here:
/// [kStripeK] from `reed_solomon.dart`, `d` from
/// `bulk_params.dart:coveredHolderFailures`, which in turn derives from
/// [kAssumedHolderLossShare] = 0.20 (whose reasoning stands there
/// and is not repeated here).
///
/// ── WHY EXACTLY `K + d` AND NOT THE 10/7 FROM THE DOCUMENT ──────────
///
/// `holderLossCover` records the set computation on which the whole
/// design of the bulk lane stands: `BulkPlacementPlan.forBlocks` places
/// ROUND-ROBIN, block `i` goes to holder `i mod R`, so `d` failed
/// holders take away **exactly the residue classes** `i mod R`. For a
/// stripe coding that means precisely: a stripe with `N <= R`
/// fragments lies on `N` DIFFERENT holders, of which at most `d`
/// fail — so it survives for certain exactly when
/// `N - K >= d`.
///
/// With the 1.43x from §9.3 (N=10, K=7, i.e. `N-K = 3`) this is NOT
/// fulfilled at `d = 4`, and the consequence is not a loss of reserve
/// but total loss. Measured on 06.09.2026
/// (`test/perf/perf_medienspur_s372.dart`, reverse test in
/// `test/smoke/smoke_erasure_lane.dart`):
///
/// ```
/// N=10   32 KiB: worst stripe loss 4 of 10 (K=7 needs <=3)
///                holders 0..3 dead: LOST, 200 random layouts: LOST
/// N=10  256 KiB: the same
/// N=11   32 KiB: worst stripe loss 4 of 11 (K=7 needs <=4)
///                holders 0..3 dead: RECONSTRUCTED, 200 layouts: all
/// N=11  256 KiB: the same
/// ```
///
/// The cause behind the number, also measured: `gcd(10, 20) = 10`
/// lets the round-robin over 40 stripes produce only **two** different
/// holder sets (even stripes on holders 0..9, odd ones on
/// 10..19) — four failures in one half thus kill ALL stripes of
/// that parity. `gcd(11, 20) = 1` produces **twenty** different
/// sets.
///
/// ── WHAT IT COSTS, AND WHAT IT SAVES ──────────────────────────────
///
/// `N/K` = 1.5714 versus 10/7 = 1.4286, i.e. +10 %. Against the BUILT
/// rateless planner ([plannedBlocksFor], which accounts for coverage and
/// span) it is nevertheless clearly cheaper — measured over all
/// 225 sizes of the band 32..256 KiB: 72 666 cells versus 51 975,
/// **28.5 % fewer**. Per size:
///
/// ```
///    kB     k  Fountain plan  factor    RS(N=11)  factor   saving
///     32    32             79  2.469         55  1.719     30.4 %
///     64    64            160  2.500        110  1.719     31.3 %
///    128   128            285  2.227        209  1.633     26.7 %
///    256   256            548  2.141        407  1.590     25.7 %
/// ```
///
/// [holders] is an argument and not a constant, for the same reason
/// as with `bulkOvershoot`: in the small network `responsibleRelays`
/// breaks off, and there a failed holder weighs more.
int erasureLaneN({int holders = kNominalBulkHolders}) {
  final n = kStripeK + coveredHolderFailures(holders: holders);
  // GF(256) carries at most 255 fragments (`ReedSolomon.withParams`),
  // and the seed gives the index one byte. Both are far away at R = 20;
  // the latch stands for the case that someone raises `R`.
  if (n > 255) {
    throw StateError('N = K + d = $n exceeds the 255 of GF(256) — '
        'the stripe width or the covered holder load is too large');
  }
  return n;
}

/// How many stripes an object of [objectLength] bytes has.
int erasureStripesFor(int objectLength) {
  final k = FountainBlock.sourceBlockCount(objectLength);
  return (k + kStripeK - 1) ~/ kStripeK;
}

/// How many blocks the WHOLE set has: `ceil(k/K) * N`.
///
/// **A number, not an expected value.** That is the difference from the
/// rateless lane, where `plannedBlocksFor` builds an estimate from coding
/// need, coverage and measured span. Here there is nothing to
/// estimate: there are no more blocks than these, and fewer do not
/// suffice.
int erasureBlocksFor(int objectLength, {int holders = kNominalBulkHolders}) =>
    erasureStripesFor(objectLength) * erasureLaneN(holders: holders);

/// A stripe fragment: the same 17-B header as a rateless block,
/// but with format byte [kErasureVersion].
///
/// ── THE SEED CARRIES THREE NUMBERS ──────────────────────────────────────
///
/// ```
///   blockSeed = (stripe << 16) | (n << 8) | index
///                \_ 16 bit       \_ 8 bit   \_ 8 bit
/// ```
///
/// **`n` is ALSO on the wire, and that is not waste.** The
/// Cauchy coefficients in `reed_solomon.dart` depend on `m = n - k`
/// (`_cauchyY = List.generate(k, (i) => (n-k)+i+1)`): a parity piece
/// that was created under `n = 11` is something else under `n = 10`.
/// But `n` derives from [erasureLaneN] and thus from
/// [kAssumedHolderLossShare] — a number that MAY change with a new
/// build. If it were not in the block, a recipient with a different build
/// would decode a running transfer wrongly; this would only be caught
/// by the final check in `BulkReceiver.take`, i.e. after the full
/// traffic. With it in the block, the recipient decodes what the sender
/// encoded.
///
/// 16 bits for the stripe are 65 536 stripes of 7168 B each = 470 MB —
/// far above this lane, which ends at [kFountainLowerBoundBytes]
/// (37 stripes).
class ErasureBlock {
  /// Prefix of the content hash, [kFountainObjectIdBytes] bytes.
  final Uint8List objectId;

  /// Length of the original object.
  final int objectLength;

  final int stripe;

  /// The stripe width under which this fragment was created.
  final int n;

  /// 0..[n]-1. Below `K` a data piece, from `K` on a parity piece.
  final int index;

  /// Exactly [kFountainBlockPayloadBytes] bytes.
  final Uint8List payload;

  ErasureBlock({
    required this.objectId,
    required this.objectLength,
    required this.stripe,
    required this.n,
    required this.index,
    required this.payload,
  }) {
    if (objectId.length != kFountainObjectIdBytes) {
      throw ArgumentError('objectId must be $kFountainObjectIdBytes B, '
          'is ${objectId.length}');
    }
    if (payload.length != kFountainBlockPayloadBytes) {
      throw ArgumentError('payload must be $kFountainBlockPayloadBytes B, '
          'is ${payload.length}');
    }
    if (objectLength <= 0 || objectLength > kFountainMaxObjectBytes) {
      throw ArgumentError.value(objectLength, 'objectLength',
          'must lie in [1, $kFountainMaxObjectBytes]');
    }
    if (stripe < 0 || stripe > 0xFFFF) {
      throw ArgumentError.value(stripe, 'stripe', 'must be 16 bits');
    }
    if (n <= kStripeK || n > 255) {
      throw ArgumentError.value(n, 'n', 'must lie in ($kStripeK, 255]');
    }
    if (index < 0 || index >= n) {
      throw ArgumentError.value(index, 'index', 'must lie in [0, $n)');
    }
  }

  /// The seed as it stands in the header and goes into the nonce.
  int get blockSeed => seedOf(stripe, n, index);

  /// `blockSeed = (stripe << 16) | (n << 8) | index`.
  static int seedOf(int stripe, int n, int index) =>
      (stripe << 16) | (n << 8) | index;

  Uint8List toBytes() {
    final out = Uint8List(kFountainBlockBytes);
    out[0] = kErasureVersion;
    out.setRange(1, 9, objectId);
    final d = ByteData.view(out.buffer);
    d.setUint32(9, objectLength, Endian.big);
    d.setUint32(13, blockSeed, Endian.big);
    out.setRange(kFountainHeaderBytes, kFountainBlockBytes, payload);
    return out;
  }

  /// Reads a fragment from [bytes]. **No `throw`** — the harvest scans
  /// foreign cells, a miss is the normal case.
  static ErasureBlock? fromBytes(Uint8List bytes) {
    if (bytes.length < kFountainBlockBytes) return null;
    if (bytes[0] != kErasureVersion) return null;
    final d = ByteData.view(bytes.buffer, bytes.offsetInBytes);
    final len = d.getUint32(9, Endian.big);
    if (len <= 0) return null;
    final seed = d.getUint32(13, Endian.big);
    final stripe = (seed >> 16) & 0xFFFF;
    final n = (seed >> 8) & 0xFF;
    final index = seed & 0xFF;
    if (n <= kStripeK || n > 255) return null;
    if (index >= n) return null;
    return ErasureBlock(
      objectId: Uint8List.fromList(bytes.sublist(1, 1 + kFountainObjectIdBytes)),
      objectLength: len,
      stripe: stripe,
      n: n,
      index: index,
      payload: Uint8List.fromList(
          bytes.sublist(kFountainHeaderBytes, kFountainBlockBytes)),
    );
  }

  @override
  String toString() => 'ErasureBlock(stripe=$stripe, i=$index/$n, len=$objectLength)';
}

/// The send side of the stripe lane.
///
/// **The draw order is stripe by stripe** (`draw` 0..N-1 = stripe 0,
/// N..2N-1 = stripe 1, …). It has to be, because the round-robin plan
/// distributes `holders[i mod R]`: only this way do the `N` fragments of a
/// stripe lie on `N` DIFFERENT holders, and exactly on that stands the
/// derivation `N = K + d` in [erasureLaneN]. A fragment-wise
/// order (all index-0 pieces first) would put a whole stripe
/// on a single holder.
final class ErasureStripeEncoder implements BulkBlockFactory {
  @override
  final int objectLength;

  final Uint8List objectId;

  final int n;

  final int stripes;

  final ReedSolomon _rs;

  /// The fragments per stripe, computed on demand and remembered.
  ///
  /// **Only the LAST drawn stripe stays around**, not all: with
  /// stripe-wise drawing the `N` fragments of a stripe are asked for
  /// one after the other, never again afterwards. A cache over
  /// all stripes tied up an additional 407 KB at 256 KB without benefit.
  int _cachedStripe = -1;
  List<Uint8List>? _cached;

  final Uint8List _object;

  ErasureStripeEncoder._(
      this.objectId, this._object, this.objectLength, this.n, this.stripes)
      : _rs = ReedSolomon.withParams(n, kStripeK);

  /// Override [n] only for checks; in operation it derives from
  /// [erasureLaneN].
  factory ErasureStripeEncoder({
    required Uint8List objectId,
    required Uint8List data,
    int? n,
  }) {
    if (objectId.length != kFountainObjectIdBytes) {
      throw ArgumentError('objectId must be $kFountainObjectIdBytes B');
    }
    if (data.isEmpty || data.length > kFountainMaxObjectBytes) {
      throw ArgumentError.value(data.length, 'data.length',
          'must lie in [1, $kFountainMaxObjectBytes]');
    }
    final width = n ?? erasureLaneN();
    if (width <= kStripeK || width > 255) {
      throw ArgumentError.value(width, 'n', 'must lie in ($kStripeK, 255]');
    }
    final s = erasureStripesFor(data.length);
    if (s > 0xFFFF) {
      throw ArgumentError.value(
          s, 'stripes', 'the seed carries a 16-bit stripe number');
    }
    return ErasureStripeEncoder._(
        Uint8List.fromList(objectId), data, data.length, width, s);
  }

  @override
  int get sourceBlocks => FountainBlock.sourceBlockCount(objectLength);

  @override
  int? get totalDraws => stripes * n;

  @override
  int seedForDraw(int draw) =>
      ErasureBlock.seedOf(draw ~/ n, n, draw % n);

  @override
  Uint8List sealedFor(int seed, BulkTransferKeys keys) =>
      sealRawBlock(blockAt(seed).toBytes(), objectId, seed, keys);

  /// The fragment for [seed] — without seal, for checks.
  ErasureBlock blockAt(int seed) {
    final stripe = (seed >> 16) & 0xFFFF;
    final index = seed & 0xFF;
    if (stripe >= stripes) {
      throw ArgumentError.value(stripe, 'stripe', 'only 0..${stripes - 1}');
    }
    if (index >= n) {
      throw ArgumentError.value(index, 'index', 'only 0..${n - 1}');
    }
    return ErasureBlock(
      objectId: objectId,
      objectLength: objectLength,
      stripe: stripe,
      n: n,
      index: index,
      payload: _fragments(stripe)[index],
    );
  }

  List<Uint8List> _fragments(int stripe) {
    if (_cachedStripe == stripe && _cached != null) return _cached!;
    final buf = Uint8List(kStripeSourceBytes);
    final from = stripe * kStripeSourceBytes;
    if (from < _object.length) {
      final until = from + kStripeSourceBytes < _object.length
          ? from + kStripeSourceBytes
          : _object.length;
      buf.setRange(0, until - from, _object, from);
    }
    final f = _rs.encode(buf);
    _cachedStripe = stripe;
    _cached = f;
    return f;
  }
}

/// The receive side of the stripe lane.
///
/// **A stripe is complete as soon as `K` of its fragments are there** —
/// no matter which. That is the MDS property of the Cauchy matrix that
/// `reed_solomon.dart` guarantees in its header, and it is the whole reason
/// why this lane has no tail: there is no draw that
/// "contributes nothing", and no case in which `3k` blocks do not suffice.
final class ErasureStripeDecoder implements BulkBlockSink {
  final Uint8List objectId;

  final int objectLength;

  final int stripes;

  /// Fragments per stripe, until `K` are together.
  final Map<int, Map<int, Uint8List>> _parts = <int, Map<int, Uint8List>>{};

  /// Fully decoded stripes.
  final Map<int, Uint8List> _done = <int, Uint8List>{};

  /// The stripe width the SENDER used — from the first accepted
  /// fragment. Until then `null`.
  int? _n;

  ReedSolomon? _rs;

  ErasureStripeDecoder({
    required Uint8List objectId,
    required this.objectLength,
  })  : objectId = Uint8List.fromList(objectId),
        stripes = erasureStripesFor(objectLength) {
    if (objectId.length != kFountainObjectIdBytes) {
      throw ArgumentError('objectId must be $kFountainObjectIdBytes B');
    }
    if (objectLength <= 0 || objectLength > kFountainMaxObjectBytes) {
      throw ArgumentError.value(objectLength, 'objectLength',
          'must lie in [1, $kFountainMaxObjectBytes]');
    }
  }

  /// The stripe width of this harvest, as soon as the first fragment is there.
  int? get stripeWidth => _n;

  @override
  int get sourceBlocks => FountainBlock.sourceBlockCount(objectLength);

  @override
  int get resolvedSourceBlocks {
    // The last stripe often covers fewer than `K` source blocks; a
    // blanket `done * K` would report more than the object has, and
    // `progress` would run over 1.
    var r = 0;
    for (final s in _done.keys) {
      final first = s * kStripeK;
      final rest = sourceBlocks - first;
      r += rest < kStripeK ? rest : kStripeK;
    }
    return r;
  }

  @override
  bool get isComplete => _done.length == stripes;

  @override
  double get progress => resolvedSourceBlocks / sourceBlocks;

  @override
  BulkCodecOffer offerSealed(Uint8List sealed, BulkTransferKeys keys) {
    if (isComplete) return BulkCodecOffer.complete;
    final raw = openSealedBlockBytes(sealed, keys);
    if (raw == null) return BulkCodecOffer.foreign;
    final b = ErasureBlock.fromBytes(raw);
    if (b == null) return BulkCodecOffer.foreign;
    if (!sealedNonceIsCanonical(sealed, b.objectId, b.blockSeed, keys)) {
      return BulkCodecOffer.foreign;
    }
    if (!FountainBlock.sameObject(b.objectId, objectId) ||
        b.objectLength != objectLength ||
        b.stripe >= stripes) {
      return BulkCodecOffer.foreign;
    }
    // THE STRIPE WIDTH MUST BE THE SAME ACROSS THE HARVEST. Two
    // widths in one object would mean two codings; the parity pieces of
    // the one are garbage under the other (see [ErasureBlock]). Such a
    // fragment is therefore foreign, not faulty — the same stance as
    // with a foreign object identifier.
    final n = _n;
    if (n == null) {
      _n = b.n;
      _rs = ReedSolomon.withParams(b.n, kStripeK);
    } else if (n != b.n) {
      return BulkCodecOffer.foreign;
    }
    if (_done.containsKey(b.stripe)) return BulkCodecOffer.redundant;
    final have = _parts[b.stripe] ??= <int, Uint8List>{};
    if (have.containsKey(b.index)) return BulkCodecOffer.duplicate;
    have[b.index] = b.payload;
    if (have.length < kStripeK) return BulkCodecOffer.stored;
    _done[b.stripe] = _rs!.decode(have, kStripeSourceBytes);
    _parts.remove(b.stripe);
    return BulkCodecOffer.resolved;
  }

  @override
  Uint8List? takeObject() {
    if (!isComplete) return null;
    final out = Uint8List(stripes * kStripeSourceBytes);
    for (final e in _done.entries) {
      out.setRange(e.key * kStripeSourceBytes,
          (e.key + 1) * kStripeSourceBytes, e.value);
    }
    return Uint8List.fromList(out.sublist(0, objectLength));
  }

  @override
  void reset() {
    _parts.clear();
    _done.clear();
    _n = null;
    _rs = null;
  }
}
