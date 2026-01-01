import 'dart:typed_data';

import 'block_xor.dart';
import 'degree_distribution.dart';
import 'fountain_block.dart';

/// Encoding side of the rateless codec (§9, E-42: LT codes in pure Dart).
///
/// ── WHAT "RATELESS" MEANS HERE ───────────────────────────────────────
///
/// A Reed-Solomon encoder produces N fragments, and whoever distributes
/// them must keep books on which one went where — otherwise at the end
/// five copies of fragment 3 lie in the network and none of fragment 8.
/// Exactly this bookkeeping is ruled out by §19.
///
/// Instead of N fragments this encoder produces **2^32 equivalent
/// blocks**. Every caller draws seeds as it suits him; any
/// `k * (1 + overhead figure)` **distinct** ones among them suffice for
/// reconstruction. No block is special, none has to be assigned, and
/// from possessing a block nothing follows about who holds what
/// (§9, §26.6.1).
///
/// ── LIFETIME AND MEMORY ─────────────────────────────────────────
///
/// The encoder holds the **whole** object in memory (for every block it
/// needs random access to up to `k` source blocks). For today's consumers
/// — media bulk and binary distribution up to ~200 MB — that is
/// acceptable; a file-backed version is open work and noted as such in
/// `test/perf/perf_fountain.dart`.
///
/// The source blocks are **views** onto the passed buffer, not copies.
/// Only the last block is copied, because it must be padded with zeros
/// to 1024 B.
class FountainEncoder {
  /// Prefix of the content hash; goes unchanged into every block header.
  final Uint8List objectId;

  /// Length of the original object.
  final int objectLength;

  /// `k = ceil(objectLength / 1024)`.
  final int sourceBlocks;

  /// Degree distribution of this object.
  final DegreeDistribution distribution;

  final List<Uint8List> _source;

  FountainEncoder._(
    this.objectId,
    this.objectLength,
    this.sourceBlocks,
    this.distribution,
    this._source,
  );

  /// Encoder for [data].
  ///
  /// [objectId] is the [kFountainObjectIdBytes] B long prefix of the
  /// content hash that the caller keeps anyway (manifest hash for binary
  /// distribution, blob hash for media). The codec does **not** compute it
  /// itself — it thus depends on no crypto library (E-42: pure Dart,
  /// no FFI).
  factory FountainEncoder({
    required Uint8List objectId,
    required Uint8List data,
    double c = DegreeDistribution.defaultC,
    double failureBound = DegreeDistribution.defaultFailureBound,
  }) {
    if (objectId.length != kFountainObjectIdBytes) {
      throw ArgumentError('objectId must be $kFountainObjectIdBytes B');
    }
    if (data.isEmpty) {
      throw ArgumentError('empty object has nothing to encode');
    }
    if (data.length > kFountainMaxObjectBytes) {
      throw ArgumentError(
        'Object larger than $kFountainMaxObjectBytes B — '
        'the object length in the block header is 4 B wide',
      );
    }

    final k = FountainBlock.sourceBlockCount(data.length);
    final src = <Uint8List>[];
    for (var i = 0; i < k; i++) {
      final start = i * kFountainBlockPayloadBytes;
      final end = start + kFountainBlockPayloadBytes;
      if (end <= data.length) {
        src.add(
          Uint8List.view(
            data.buffer,
            data.offsetInBytes + start,
            kFountainBlockPayloadBytes,
          ),
        );
      } else {
        // Last block: padded with zeros to full block size. The padding
        // bytes are harmless, because `objectLength` in the header says
        // where the object ends — the decoder cuts them off.
        final tail = Uint8List(kFountainBlockPayloadBytes);
        tail.setRange(0, data.length - start, data, data.offsetInBytes + start);
        src.add(tail);
      }
    }

    return FountainEncoder._(
      Uint8List.fromList(objectId),
      data.length,
      k,
      DegreeDistribution(k, c: c, failureBound: failureBound),
      src,
    );
  }

  /// The block for the seed [blockSeed].
  ///
  /// Deterministic: the same seed on the same object always yields the
  /// same bytes — on every node, in every session. That is the property
  /// from which the content-addressed storage in the fountain erasure
  /// cache draws its benefit (§26.6.1): two seeders that draw the same
  /// seed produce the same block, and the cache holds it once instead of
  /// twice.
  FountainBlock blockAt(int blockSeed) {
    if (blockSeed < 0 || blockSeed > 0xFFFFFFFF) {
      throw ArgumentError.value(blockSeed, 'blockSeed', 'must be 32 bits');
    }
    final neigh = distribution.neighbours(blockSeed);
    final payload = Uint8List(kFountainBlockPayloadBytes);
    payload.setRange(0, kFountainBlockPayloadBytes, _source[neigh[0]]);
    for (var i = 1; i < neigh.length; i++) {
      BlockXor.xorInto(payload, _source[neigh[i]]);
    }
    return FountainBlock(
      objectId: objectId,
      objectLength: objectLength,
      blockSeed: blockSeed,
      payload: payload,
    );
  }

  /// Consecutive blocks from [startSeed], generated lazily.
  ///
  /// Without [count] infinite — that is the point. The caller stops when
  /// his budget is exhausted or the recipient has enough.
  Iterable<FountainBlock> blocks({int startSeed = 0, int? count}) sync* {
    var seed = startSeed;
    var made = 0;
    while (count == null || made < count) {
      yield blockAt(seed & 0xFFFFFFFF);
      seed++;
      made++;
    }
  }

  /// How many blocks the caller should generate so that the recipient
  /// reconstructs with high probability.
  ///
  /// [overhead] is the **measured** overhead figure (upper end, not the
  /// mean — the promise hangs on the bad case), [loss] the expected share
  /// of blocks lost or never harvested.
  int recommendedBlockCount({required double overhead, double loss = 0.0}) {
    if (overhead < 1.0) {
      throw ArgumentError.value(overhead, 'overhead', 'must be >= 1.0');
    }
    if (loss < 0 || loss >= 1) {
      throw ArgumentError.value(loss, 'loss', 'must lie in [0,1)');
    }
    return (sourceBlocks * overhead / (1.0 - loss)).ceil();
  }
}
