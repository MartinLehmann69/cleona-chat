// The receiving side — and the CONTENT BINDING (§26.6.1 step 5).
//
// ── THE GAP THIS FILE CLOSES ────────────────────────────
//
// The codec deliberately computes no hashes (`fountain.dart`: "It computes
// **no** hashes and **no** signatures. The object identifier comes from the
// caller, the check of the reconstructed object against the full
// content hash … is step 5 in §26.6.1 and lies with the caller.").
// This class IS that caller.
//
// What happens without it is stated in the class docs of `FountainDecoder`:
// "An attacker who can smuggle in a valid block header with a wrong payload
// destroys the reconstruction — and is caught by the
// caller's content hash". Without the caller he is not
// caught. The decoder notices nothing: the peeling wave processes
// a wrong payload without noticing it, and `takeObject` delivers
// `k` resolved source blocks — a file that looks like a file.
// Exactly the silent failure case that the codec ruled out for itself
// and for which it needs the counterpart here.
//
// ── TWO GATES, NOT ONE ───────────────────────────────────────
//
// 1. **At the door** (`bulk_block_seal.dart`): a block that does not
//    authenticate under the transfer key does not even get into the
//    decoder. That is new compared with what the codec docs assume,
//    and it makes smuggling practically impossible — the attacker would need
//    `K_T`.
// 2. **At the exit** (here): the full SHA-256 against the hash from the
//    announce. It catches what the first does not catch: a sender whose
//    object does not match its own announce, and every error of the
//    codec itself.
//
// Leaving out either of the two would be wrong in both directions. The
// first alone would let sender and codec errors through; the second alone
// would let a forgery run for 200 MB before it is noticed.
//
// ── THE SELF-HEALING ────────────────────────────────────────────────
//
// §26.6.1: "On a hash or signature error, **the entire version state** (all
// blocks plus the reconstructed binary) is discarded and re-fetched, so a
// poisoned block cannot permanently block the update; **transient errors
// (too few blocks available) delete nothing**, the partial state stays in
// place for resumption."
//
// Both halves are built, and they differ:
//   * too few blocks -> [BulkVerdict.incomplete], NOTHING is discarded,
//     [refill] requests more.
//   * hash wrong -> [BulkVerdict.hashMismatch], the whole state is dropped,
//     and the consumed tags go into the block list, so that the
//     next attempt does not fetch the same bytes back.
//
// **And in neither case are bytes delivered.**
library;

import 'dart:typed_data';

import 'package:cleona/core/codec/erasure_stripes.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:cleona/core/fountain/fountain_decoder.dart';

import 'bulk_block_seal.dart';
import 'bulk_cache.dart';
import 'bulk_codec.dart';
import 'bulk_control.dart';
import 'bulk_keys.dart';
import 'bulk_params.dart';

/// What offering a scanned block resulted in.
enum BulkOffer {
  /// Accepted; it has resolved at least one source block.
  resolved,

  /// Accepted; it is still waiting for neighbours.
  stored,

  /// Accepted, but contributed nothing. Normal with rateless coding.
  redundant,

  /// This seed already existed.
  duplicate,

  /// Cannot be opened or belongs to another object. **When
  /// scanning, the normal case**, not a protocol violation.
  foreign,

  /// Blocked from a failed attempt (self-healing).
  quarantined,

  /// Everything is already there.
  complete,
}

/// The verdict on the assembly.
enum BulkVerdict {
  /// Not all source blocks there yet. **Not an error** — blocks
  /// are missing, nothing more.
  incomplete,

  /// Complete AND the full content hash matches.
  verified,

  /// Complete, but the hash does not match. The state is discarded.
  hashMismatch,
}

/// Was [BulkReceiver.take] herausgibt.
final class BulkTake {
  final BulkVerdict verdict;

  /// **Only set for [BulkVerdict.verified].** In every other case
  /// `null` — there is no way to get an unchecked object
  /// out of this class.
  final Uint8List? object;

  const BulkTake._(this.verdict, this.object);

  const BulkTake.incomplete() : this._(BulkVerdict.incomplete, null);
  const BulkTake.mismatch() : this._(BulkVerdict.hashMismatch, null);
  const BulkTake.verified(Uint8List o) : this._(BulkVerdict.verified, o);

  @override
  String toString() => 'BulkTake(${verdict.name}, '
      '${object == null ? 'ohne Bytes' : '${object!.length} B'})';
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// The rateless codec as a [BulkBlockSink].
///
/// Thin wrapper around `FountainDecoder`; it pulls the opening and the
/// object check inside, because the two codecs have different
/// block formats and the caller should not guess which one it has in front
/// of it (rationale at [BulkBlockSink.offerSealed]).
final class _FountainSink implements BulkBlockSink {
  final Uint8List objectId;
  final int objectLength;
  FountainDecoder _decoder;

  _FountainSink(this.objectId, this.objectLength)
      : _decoder =
            FountainDecoder(objectId: objectId, objectLength: objectLength);

  @override
  int get sourceBlocks => _decoder.sourceBlocks;

  @override
  int get resolvedSourceBlocks => _decoder.resolvedSourceBlocks;

  @override
  bool get isComplete => _decoder.isComplete;

  @override
  double get progress => _decoder.progress;

  @override
  Uint8List? takeObject() => _decoder.takeObject();

  @override
  void reset() => _decoder =
      FountainDecoder(objectId: objectId, objectLength: objectLength);

  @override
  BulkCodecOffer offerSealed(Uint8List sealed, BulkTransferKeys keys) {
    final block = openBulkBlock(sealed, keys);
    if (block == null) return BulkCodecOffer.foreign;
    if (!FountainBlock.sameObject(block.objectId, objectId) ||
        block.objectLength != objectLength) {
      return BulkCodecOffer.foreign;
    }
    return switch (_decoder.offer(block)) {
      FountainOffer.foreign => BulkCodecOffer.foreign,
      FountainOffer.duplicate => BulkCodecOffer.duplicate,
      FountainOffer.complete => BulkCodecOffer.complete,
      FountainOffer.resolved => BulkCodecOffer.resolved,
      FountainOffer.stored => BulkCodecOffer.stored,
      FountainOffer.redundant => BulkCodecOffer.redundant,
    };
  }
}

/// A transfer from the receiver's point of view.
final class BulkReceiver {
  final BulkTransferKeys keys;

  /// The full content hash from the announce — the promise against which
  /// it is checked.
  final Uint8List contentHash;

  final Uint8List objectId;
  final int objectLength;

  /// Which codec carries this harvest — **computed from `objectLength`,
  /// not read from the wire** (`mediaCodecFor`).
  final BulkCodecKind codec;

  final BulkBlockSink _decoder;

  /// Tags of the blocks already accepted. They go as the
  /// have-list into the next scan (`BulkCache.scan(have:)`), so that
  /// the same block does not come over the wire twice.
  final Set<String> _have = <String>{};

  /// Tags from a failed attempt. They are neither accepted
  /// nor requested again.
  final Set<String> _quarantined = <String>{};

  /// How often the final check has failed.
  int hashFailures = 0;

  /// How many sampled blocks were foreign.
  int foreignBlocks = 0;

  BulkReceiver._(this.keys, this.contentHash, this.objectId, this.objectLength,
      this.codec, this._decoder);

  /// Receiver from the announce.
  ///
  /// [keys] comes from `BulkAnnounce.transferRoot` — since 31.08.2026
  /// in EVERY case, also 1:1. Before, it said here "pairwise the
  /// caller derives the keys itself from `K_AB`"; exactly this
  /// derivability was the security flaw (`bulk_keys.dart`).
  ///
  /// [codec] is the RATELESS one by default — the same default as for
  /// `BulkSender`, for the same reason (binary distribution builds
  /// `BulkReceiver.fromAnnounce` too). The media lane passes
  /// `mediaCodecFor(announce.objectLength)`, and because the sender
  /// computes the same function on the same number, both sides agree
  /// without a single byte on the wire.
  factory BulkReceiver.fromAnnounce(BulkAnnounce announce,
      BulkTransferKeys keys,
      {BulkCodecKind codec = BulkCodecKind.fountain}) {
    final oid = objectIdFromContentHash(announce.contentHash);
    final sink = switch (codec) {
      BulkCodecKind.fountain => _FountainSink(oid, announce.objectLength),
      BulkCodecKind.reedSolomon => ErasureStripeDecoder(
          objectId: oid, objectLength: announce.objectLength),
    };
    return BulkReceiver._(
      keys,
      Uint8List.fromList(announce.contentHash),
      oid,
      announce.objectLength,
      codec,
      sink,
    );
  }

  int get sourceBlocks => _decoder.sourceBlocks;

  /// Aufgeloeste Quellbloecke.
  int get resolvedSourceBlocks => _decoder.resolvedSourceBlocks;

  /// Share `[0,1]`.
  double get progress => _decoder.progress;

  bool get isComplete => _decoder.isComplete;

  /// The have-list for the next scan — already accepted AND
  /// blocked tags.
  ///
  /// The blocked ones are included, because otherwise they would come along again at every pass:
  /// the holder deletes nothing, and without the information
  /// the receiver would endlessly pull the same spoiled bytes.
  List<Uint8List> get haveList => <Uint8List>[
        for (final h in _have) _unhex(h),
        for (final h in _quarantined) _unhex(h),
      ];

  /// Accepts a scanned, sealed block.
  BulkOffer offerSealed(Uint8List sealed) {
    final digest = _hex(bulkBlockDigest(sealed));
    if (_quarantined.contains(digest)) return BulkOffer.quarantined;
    if (_have.contains(digest)) return BulkOffer.duplicate;

    // OPENING AND CHECKING LIVE IN THE CODEC (S372): the format byte
    // distinguishes `0x01` (rateless) from `0x02` (stripes), and whoever
    // opened it here itself would have to guess which one it has in front of it. A
    // fragment accepted by the wrong decoder is SILENTLY
    // processed — exactly the class of error that `fountain_block.dart` describes at
    // [kFountainVersion].
    switch (_decoder.offerSealed(sealed, keys)) {
      case BulkCodecOffer.foreign:
        // Cannot be opened or belongs to another object. When
        // scanning, the normal case (§26.6.1).
        foreignBlocks++;
        return BulkOffer.foreign;
      case BulkCodecOffer.duplicate:
        // The same seed under different bytes cannot exist after the
        // nonce check — so this is a duplicate that the
        // have-list did not know yet (from a second holder, say).
        _have.add(digest);
        return BulkOffer.duplicate;
      case BulkCodecOffer.complete:
        return BulkOffer.complete;
      case BulkCodecOffer.resolved:
        _have.add(digest);
        return BulkOffer.resolved;
      case BulkCodecOffer.stored:
        _have.add(digest);
        return BulkOffer.stored;
      case BulkCodecOffer.redundant:
        _have.add(digest);
        return BulkOffer.redundant;
    }
  }

  /// Accepts everything a scan has delivered.
  int offerScan(Iterable<BulkEntry> entries) {
    var admitted = 0;
    for (final e in entries) {
      final r = offerSealed(e.sealed);
      if (r == BulkOffer.resolved ||
          r == BulkOffer.stored ||
          r == BulkOffer.redundant) {
        admitted++;
      }
    }
    return admitted;
  }

  /// **Step 5 from §26.6.1.** The only place where bytes
  /// come out.
  ///
  /// Three outcomes, and two of them return nothing:
  ///
  /// * incomplete -> [BulkVerdict.incomplete], NOTHING is discarded
  ///   ("transient errors delete nothing"), [refill] requests more;
  /// * hash wrong -> [BulkVerdict.hashMismatch], the WHOLE state
  ///   is dropped, the consumed tags are blocked, [refill] requests
  ///   a full new set;
  /// * hash matches -> [BulkVerdict.verified] with the bytes.
  BulkTake take() {
    if (!_decoder.isComplete) return const BulkTake.incomplete();
    final obj = _decoder.takeObject();
    if (obj == null) return const BulkTake.incomplete();
    final h = SodiumFFI().sha256(obj);
    if (!bytesEqualConstantTime(h, contentHash)) {
      hashFailures++;
      _reset();
      return const BulkTake.mismatch();
    }
    return BulkTake.verified(obj);
  }

  /// The refill (§9.3 "refill").
  ///
  /// It asks for a NUMBER, not for blocks: this many
  /// source blocks are still missing, times the measured overhead figure,
  /// at least one, as long as something is missing.
  ///
  /// After a hash failure the decoder is back at zero, so the
  /// refill requests the full set — exactly what §26.6.1
  /// means by "discarded and re-fetched".
  BulkRefillRequest refill() {
    // ── THE STRIPE LANE DOES NOT ASK FOR REFILLS (S372, O-3) ────────────────
    //
    // There is nothing to request: the set has `ceil(k/K) * N` blocks
    // and no more. A refill could only repeat, and
    // WHICH blocks are missing this request cannot say — it carries
    // a NUMBER, no indices. `wantedBlocks == 0` is the existing,
    // already checked form of expressing "request nothing"
    // (`MediaBulkLane._erntehaengt` sends nothing on it). The lane is
    // designed with `N = K + d` precisely to get by without a return
    // channel; the format `(stripe, index)` for a real
    // refill lies with the owner as a proposal.
    if (codec == BulkCodecKind.reedSolomon) {
      return BulkRefillRequest(objectId, 0);
    }
    final missing = sourceBlocks - _decoder.resolvedSourceBlocks;
    if (missing <= 0) return BulkRefillRequest(objectId, 0);
    final want = (missing * bulkOvershoot(objectLength)).ceil();
    return BulkRefillRequest(objectId, want < 1 ? 1 : want);
  }

  /// The request that follows an announce (§9.3 "request").
  BulkRequest request() => BulkRequest(objectId);

  /// The receipt that is the only one allowed to flip `delivered` (§9.3, D2).
  ///
  /// It is built ONLY after [BulkVerdict.verified] — that is why it stands
  /// here and not at the caller: a receipt that can also be sent without
  /// a passed check is no promise.
  BulkDecodedReceipt? receiptAfter(BulkTake take) =>
      take.verdict == BulkVerdict.verified
          ? BulkDecodedReceipt(contentHash)
          : null;

  void _reset() {
    _quarantined.addAll(_have);
    _have.clear();
    _decoder.reset();
  }

  static Uint8List _unhex(String s) {
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
