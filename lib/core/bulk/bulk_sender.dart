// The sending side of a bulk transfer (§9.3).
//
// WHAT IT DOES: draw blocks from an object, seal each once,
// assign each to exactly one placement — and in response to a refill
// draw NEW seeds instead of repeating old ones.
//
// WHAT IT DOES NOT DO: send. No socket, no clock, no timer. `R_bulk`
// (32 cells/s, appendix A) is a property of the egress and not of
// this class; whoever built it in here would have two clocks in the program.
// [BulkSender] delivers placements, the caller hands them out on the clock.
//
// MEMORY. `FountainEncoder` holds the whole object in memory (its
// class docs say so and name the file-backed version as open
// work). For the media bulk lane up to ~200 MB on a desktop that is
// acceptable; on a phone it is the reason why the bulk lane there
// only SENDS and does not hold.
library;

import 'dart:typed_data';

import 'package:cleona/core/codec/erasure_stripes.dart';
import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:cleona/core/fountain/fountain_encoder.dart';

import 'bulk_block_seal.dart';
import 'bulk_codec.dart';
import 'bulk_control.dart';
import 'bulk_keys.dart';
import 'bulk_params.dart';
import 'bulk_placement.dart';
import 'bulk_prefix.dart';

/// The rateless codec as a [BulkBlockFactory].
///
/// A thin wrapper around `FountainEncoder` and the seed source — it
/// changes nothing about their behaviour, it only gives them the same name
/// as the stripe coding, so that [BulkSender] treats both alike.
final class _FountainFactory implements BulkBlockFactory {
  final FountainEncoder encoder;
  final BulkSeedSource seeds;

  _FountainFactory(this.encoder, this.seeds);

  @override
  int get sourceBlocks => encoder.sourceBlocks;

  @override
  int get objectLength => encoder.objectLength;

  /// `null` — rateless. That is the whole difference from the stripe lane.
  @override
  int? get totalDraws => null;

  @override
  int seedForDraw(int draw) => seeds.seedAt(draw);

  @override
  Uint8List sealedFor(int seed, BulkTransferKeys keys) =>
      sealBulkBlock(encoder.blockAt(seed), keys);
}

/// A transfer from the sender's point of view.
final class BulkSender {
  final BulkTransferKeys keys;

  /// The full content hash — it goes into the announce and comes back in the
  /// receipt.
  final Uint8List contentHash;

  final Uint8List objectId;

  /// Which codec carries this transfer (§9.3, decision E-3 = D).
  ///
  /// **It does NOT travel on the wire** — the receiver computes it from
  /// `objectLength` in the announce (`mediaCodecFor`). Whoever sets the value here
  /// by hand must supply the other side the same way.
  final BulkCodecKind codec;

  final BulkBlockFactory _factory;
  final BulkSeedSource _seeds;

  /// How many seeds have already been drawn. The progress pointer — and
  /// at the same time what a refill continues.
  int _drawn = 0;

  /// Which seeds are already out.
  ///
  /// With [SequentialSeeds] the set would be superfluous (the counter
  /// suffices); with [KeyedSeeds] not: there two indices can
  /// yield the same seed. Expected value with 205 000 blocks and
  /// 2^32 seeds: 0.005 collisions. The set thus practically never
  /// costs anything and still closes the case.
  final Set<int> _emittedSeeds = <int>{};

  /// How many blocks have already been emitted.
  int get blocksEmitted => _emittedSeeds.length;

  BulkSender._(this.keys, this.contentHash, this.objectId, this.codec,
      this._factory, this._seeds);

  /// Creates a transfer for [object].
  ///
  /// [seeds] is the seed allocation; if not given, [SequentialSeeds] — the
  /// default whose price is stated in `bulk_keys.dart` at [BulkSeedPolicy].
  /// It only applies to [BulkCodecKind.fountain]; the stripe coding
  /// draws its seeds from `(stripe, n, index)` and has nothing to allocate.
  ///
  /// [codec] is the RATELESS one by default, and that is intentional: the
  /// binary distribution (`lib/core/update/`) builds `BulkSender` too,
  /// and its objects must NOT slide onto the stripe lane by size
  /// (rationale at `mediaCodecFor`). The media lane explicitly passes
  /// `mediaCodecFor(object.length)`.
  factory BulkSender({
    required Uint8List object,
    required BulkTransferKeys keys,
    BulkSeedSource seeds = const SequentialSeeds(),
    BulkCodecKind codec = BulkCodecKind.fountain,
  }) {
    final hash = bulkContentHash(object);
    final oid = objectIdFromContentHash(hash);
    final factory = switch (codec) {
      BulkCodecKind.fountain =>
        _FountainFactory(FountainEncoder(objectId: oid, data: object), seeds),
      BulkCodecKind.reedSolomon =>
        ErasureStripeEncoder(objectId: oid, data: object),
    };
    return BulkSender._(keys, hash, oid, codec, factory, seeds);
  }

  /// `k` — the number of source blocks.
  int get sourceBlocks => _factory.sourceBlocks;

  int get objectLength => _factory.objectLength;

  int? _plannedBlocks;

  /// How many blocks are to be planned for the first attempt.
  ///
  /// ── TWO ESTIMATORS FOR THE CODING NEED, THE LARGER ONE WINS ─────
  ///                                        (31.08.2026, refined S363)
  ///
  ///   * `ceil(k * measuredFountainOverhead(bytes))` — the measured
  ///     mean curve over random seeds;
  ///   * `exactSequentialPrefix(k)` — the counted truth for the
  ///     consecutive seed stream that this sender uses by default.
  ///
  /// **Both are the need at ZERO loss.** The coverage for `d`
  /// failed holders and the measured margin come on top in
  /// [plannedBlocksFor] as FACTORS — until S363 their place was held by
  /// a floor of 1.3 that did not take effect exactly where the need
  /// was high. The rationale is at [bulkOvershoot].
  ///
  /// ── WHY THE SECOND IS NEEDED AT ALL ──────────────────────────
  ///
  /// The curve is a MEAN over random seeds; this sender
  /// however draws [SequentialSeeds]. Its block set is thus a function
  /// of k, and it deviates considerably from the mean at individual points. Counted on
  /// 31.08. over all 225 sizes of the band 32..256 KiB:
  /// **57 of them were underplanned** — the receiver did not finish with ZERO
  /// loss. (Until S363 this said 56; that was counted against
  /// `max(Kurve, 1,3)`, and the floor hid k = 199 —
  /// needed 259, curve 258, floor 259. The rationale is in the header of
  /// `bulk_prefix.dart`.) Worst was k = 42 (43 008 B): needed 117
  /// blocks, planned 60. At k = 64 (65 536 B, the support point of the
  /// curve itself!): needed 95, planned 88. It does not stop above 256 KB
  /// — in the band k = 256..2200 still 24 cases, the last at
  /// k = 1131.
  ///
  /// Without this term, lowering the lower bound to 32 KB would have forced a
  /// refill round on every fourth photo — and that costs
  /// ~1 h in Secure mode, not ~8.5 s.
  ///
  /// ── WHEN THE SECOND IS NOT ASKED ──────────────────────────────
  ///
  ///   * for [BulkSeedPolicy.keyed]: there the seeds are derived, the
  ///     prefix 0..N-1 is not the drawn set, and the number would be
  ///     a statement about a different block set;
  ///   * above [kExactPrefixMaxSourceBlocks]: there counting costs
  ///     more than it brings (there the curve holds, measured).
  ///
  /// Computed once and remembered: [BulkSender] is bound to one object,
  /// so the number does not change over its lifetime,
  /// and `MediaBulkLane.emit` asks for it per transfer.
  /// ── AND WHY THE STRIPE LANE ESTIMATES NOTHING HERE (S372) ──────
  ///
  /// For [BulkCodecKind.reedSolomon] there is no coding need to
  /// estimate: the set is `ceil(k/K) * N` in size, every block in it is
  /// necessary, and an `N+1`-th does not exist. Coverage and margin
  /// are dropped as well — they cover the rateless overshoot and the
  /// round-robin loss; for stripe coding the latter is already contained
  /// in `N = K + d` (`erasure_stripes.dart:erasureLaneN`). The number therefore comes
  /// directly from the encoder.
  int get plannedBlocks => _plannedBlocks ??= _factory.totalDraws ??
      plannedBlocksFor(objectLength, policy: _seeds.policy);

  /// The announce that precedes the receiver.
  ///
  /// **The root ALWAYS travels along** (31.08.2026). Until then it was left out in the
  /// 1:1 case because it was derivable from `K_AB`; exactly that was the
  /// security flaw — `K_AB` is pure X25519 (`pair_registry.dart`),
  /// so the media content was the only payload stream without
  /// PQ cover and without forward secrecy. The rationale as a whole is
  /// in the header of `bulk_keys.dart`.
  BulkAnnounce announce({Uint8List? preview}) => BulkAnnounce(
        contentHash: contentHash,
        objectLength: objectLength,
        transferRoot: keys.root,
        preview: preview,
      );

  /// Draws [count] further blocks and seals them.
  ///
  /// Returns pairs `(versiegelte Bytes, Keim)`. With [KeyedSeeds]
  /// indices can be skipped if their seed is already out — the
  /// return value is then shorter than [count]; that is why this
  /// method delivers pairs and not a plain byte list.
  List<(Uint8List, int)> nextBlocks(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count', 'must be >= 0');
    final out = <(Uint8List, int)>[];
    var attempts = 0;
    // Cap against a pathological seed source that permanently delivers
    // duplicates: at most twice as many indices as requested
    // blocks. Without it a broken source could let this loop
    // run forever.
    final maxAttempts = count * 2 + 16;
    // THE SET IS FINITE (stripe coding, S372). A draw beyond it
    // would make `blockAt` throw — here it ends silently, because an
    // exhausted set is not an error but the normal case at the end
    // of every Reed-Solomon transfer. For the rateless codec
    // `totalDraws` is `null` and this line has no effect.
    final limit = _factory.totalDraws;
    while (out.length < count && attempts < maxAttempts) {
      if (limit != null && _drawn >= limit) break;
      final seed = _factory.seedForDraw(_drawn);
      _drawn++;
      attempts++;
      if (!_emittedSeeds.add(seed)) continue;
      out.add((_factory.sealedFor(seed, keys), seed));
    }
    return out;
  }

  /// Placements for [count] further blocks — EXACTLY ONE per block.
  List<BulkPlacement> nextPlacements(int count, BulkPlacementPlan plan) =>
      plan.forBlocks(nextBlocks(count));

  /// Answer to a refill (§9.3 "refill").
  ///
  /// **New seeds, not the old ones.** The receiver has not said
  /// which blocks it is missing — it cannot, there are no
  /// block numbers. It has said how many source blocks it is still missing.
  /// The answer to that is fresh draws; a repetition would be
  /// certainly useless, because the receiver already had these
  /// blocks.
  ///
  /// Returns `null` if the refill does not belong to this transfer.
  List<(Uint8List, int)>? refill(BulkRefillRequest req) {
    if (!FountainBlock.sameObject(req.objectId, objectId)) return null;
    // ── THE STRIPE LANE HAS NO REFILL (S372, O-3) ──────────
    //
    // "New seeds, not the old ones" is a property of RATELESS
    // coding. Reed-Solomon has `ceil(k/K) * N` blocks and not a
    // single one more; a refill could only REPEAT, and
    // repeating only helps if the receiver does not have the block —
    // which it cannot say, because `BulkRefillRequest` asks for a NUMBER
    // and not for indices.
    //
    // Therefore nothing is half built here: the answer is EMPTY and
    // named. The other side does not even ask
    // (`BulkReceiver.refill` gives `wantedBlocks == 0` for this codec,
    // and `MediaBulkLane._erntehaengt` sends nothing on it). The lane
    // is designed with `N = K + d` precisely to get by without a return channel.
    // The format `(stripe, index)` that a real
    // refill would need lies with the owner as a proposal.
    if (codec == BulkCodecKind.reedSolomon) return const <(Uint8List, int)>[];
    return nextBlocks(req.wantedBlocks);
  }

  /// Is this receipt the one for this transfer?
  ///
  /// The caller flips `delivered` ONLY on this (§9.3, D2) — not on a
  /// placement receipt, not on a relay signal.
  bool acceptsReceipt(BulkDecodedReceipt receipt) =>
      receipt.matches(contentHash);
}

/// How many blocks a MEDIA transfer of [objectBytes] plans
/// — WITHOUT having the object in memory.
///
/// ── WHY THIS SECOND FUNCTION EXISTS SINCE S372 ────────────────────
///
/// [plannedBlocksFor] is the number of the RATELESS coding. Since
/// decision E-3 = D, Reed-Solomon carries the band 32..256 KB, and there
/// the number is a completely different one: `ceil(k/K) * N` instead of curve x coverage x
/// margin — at 256 KB 407 instead of 548.
///
/// It stands here and not at the caller, because it has two consumers
/// that must NOT differ: [BulkSender.plannedBlocks]
/// (via the encoder) and `estimateMediaSend`
/// (`service/media_send_estimate.dart`), which shows the user a DURATION in the
/// consent dialog. Two calculations would be a
/// displayed number that no code honours — exactly the finding that
/// entered the sentence "no user-visible duration may be derived
/// from it until it is measured" for `R_bulk` in appendix A. `smoke_erasure_lane.dart`
/// holds both against each other.
int plannedMediaBlocksFor(int objectBytes) =>
    mediaCodecFor(objectBytes) == BulkCodecKind.reedSolomon
        ? erasureBlocksFor(objectBytes)
        : plannedBlocksFor(objectBytes);

/// How many blocks are to be planned for [objectBytes] — WITHOUT an encoder.
///
/// ── WHY EXTRACTED (02.09.2026) ────────────────────────────────
///
/// [BulkSender.plannedBlocks] was the only place that knew this number,
/// and it required an object IN MEMORY: `FountainEncoder`
/// holds the whole buffer. The consent dialog from §9.3 ("Mode
/// coupling") however needs the number BEFORE the file is read — it
/// only has its size from the directory entry.
///
/// Copying it here would have been a proxy: two
/// calculations that agree today and diverge tomorrow,
/// and the display would not have reported the difference.
/// [BulkSender.plannedBlocks] therefore calls EXACTLY THIS function; there is
/// only one calculation.
///
/// ── THE THREE STEPS, AND WHY IN THIS ORDER (S363) ────────
///
/// 1. **Coding need.** The larger of the measured mean curve
///    (`bulkOvershoot` WITHOUT coverage, i.e. `measuredFountainOverhead`) and
///    the exactly counted prefix `exactSequentialPrefix(k)`. That is
///    the number that suffices at ZERO loss.
/// 2. **Coverage** `R/(R-d)` — the round-robin loss of `d` failed
///    holders (`holderLossCover`).
/// 3. **Margin** — the measured surcharge that the set calculation misses for
///    small objects (`measuredPlanningMargin`).
///
/// **Coverage and margin must act on BOTH estimators, not just on
/// the curve.** Until S363 this said `max(ceil(k*F), exaktesPraefix)` with
/// `F = max(Kurve, 1,3)`; where the exact prefix won — measured at
/// 27.1 % of the sizes in the band 32..256 KiB —, the reserve thus went to
/// **zero**, because the prefix by construction IS the need at zero
/// loss. Exactly there the failure of a single one out of twenty
/// holders struck through (S363 1.3(b): 68.5 % at 64 KiB).
///
/// The rationale of the two estimators and why the larger one wins
/// stands unchanged at [BulkSender.plannedBlocks].
int plannedBlocksFor(int objectBytes,
    {BulkSeedPolicy policy = BulkSeedPolicy.sequential,
    int holders = kNominalBulkHolders,
    int? failures}) {
  final k = FountainBlock.sourceBlockCount(objectBytes);
  // Step 1 — coding need at ZERO loss.
  var demand = (k * measuredFountainOverhead(objectBytes)).ceil();
  if (policy == BulkSeedPolicy.sequential && k <= kExactPrefixMaxSourceBlocks) {
    final exact = exactSequentialPrefix(k);
    // `-1` means "even 12k did not suffice" — never happened in the measured
    // range. Then the curve stays: a number that the
    // counter could not deliver is no reason to plan nothing
    // at all.
    if (exact > demand) demand = exact;
  }
  // Steps 2 and 3 — coverage and margin, applied to the need.
  final d = failures ?? coveredHolderFailures(holders: holders);
  final n = (demand *
          holderLossCover(d, holders: holders) *
          measuredPlanningMargin(objectBytes))
      .ceil();
  return n < 1 ? 1 : n;
}
