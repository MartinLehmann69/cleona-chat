import 'dart:typed_data';

import 'block_xor.dart';
import 'degree_distribution.dart';
import 'fountain_block.dart';

/// Fills [into] completely with the object bytes from [offset] on — the
/// source of [FountainEncoder.reader].
typedef FountainRangeRead = void Function(int offset, Uint8List into);

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
/// Every block needs random access to up to `k` source blocks. There are
/// two ways to give it that:
///
/// * [FountainEncoder.new] holds the **whole** object in memory. The
///   source blocks are **views** onto the passed buffer, not copies; only
///   the last block is copied, because it must be padded with zeros to
///   1024 B. Right for small objects (media bulk, probes).
/// * [FountainEncoder.reader] holds **nothing** of the object: every
///   source block a block needs is read through a [FountainRangeRead]
///   into one 1024 B scratch buffer. Memory is O(1 block) instead of
///   O(object). The update holder serves a ~200 MB APK this way — held in
///   memory, that object OOM-killed the bootstrap daemon (1.6 GB RAM, no
///   swap, S406-OOM, 07.10.2026).
///
/// Both produce the same bytes for the same seed — the block format does
/// not know where the source came from.
class FountainEncoder {
  /// Prefix of the content hash; goes unchanged into every block header.
  final Uint8List objectId;

  /// Length of the original object.
  final int objectLength;

  /// `k = ceil(objectLength / 1024)`.
  final int sourceBlocks;

  /// Degree distribution of this object.
  final DegreeDistribution distribution;

  /// In-memory source blocks — `null` for [FountainEncoder.reader].
  final List<Uint8List>? _source;

  /// Range read of [FountainEncoder.reader] — `null` for the in-memory one.
  final FountainRangeRead? _read;

  /// One source block of a reader encoder, reused for every read.
  final Uint8List _scratch = Uint8List(kFountainBlockPayloadBytes);

  FountainEncoder._(
    this.objectId,
    this.objectLength,
    this.sourceBlocks,
    this.distribution,
    this._source,
    this._read,
  );

  /// Encoder that reads the object through [read] instead of holding it.
  ///
  /// [read] must fill `into` completely with the object bytes from
  /// `offset` on; the encoder never asks beyond [objectLength] and pads
  /// the last block with zeros itself. Whatever [read] throws comes out of
  /// [blockAt] unchanged — the caller decides what an unreadable source
  /// means.
  factory FountainEncoder.reader({
    required Uint8List objectId,
    required int objectLength,
    required FountainRangeRead read,
    double c = DegreeDistribution.defaultC,
    double failureBound = DegreeDistribution.defaultFailureBound,
  }) {
    _checkObject(objectId, objectLength);
    final k = FountainBlock.sourceBlockCount(objectLength);
    return FountainEncoder._(
      Uint8List.fromList(objectId),
      objectLength,
      k,
      DegreeDistribution(k, c: c, failureBound: failureBound),
      null,
      read,
    );
  }

  static void _checkObject(Uint8List objectId, int objectLength) {
    if (objectId.length != kFountainObjectIdBytes) {
      throw ArgumentError('objectId must be $kFountainObjectIdBytes B');
    }
    if (objectLength <= 0) {
      throw ArgumentError('empty object has nothing to encode');
    }
    if (objectLength > kFountainMaxObjectBytes) {
      throw ArgumentError(
        'Object larger than $kFountainMaxObjectBytes B — '
        'the object length in the block header is 4 B wide',
      );
    }
  }

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
    _checkObject(objectId, data.length);

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
      null,
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
    final source = _source;
    if (source != null) {
      payload.setRange(0, kFountainBlockPayloadBytes, source[neigh[0]]);
      for (var i = 1; i < neigh.length; i++) {
        BlockXor.xorInto(payload, source[neigh[i]]);
      }
    } else {
      _readBlock(neigh[0], payload);
      for (var i = 1; i < neigh.length; i++) {
        _readBlock(neigh[i], _scratch);
        BlockXor.xorInto(payload, _scratch);
      }
    }
    return FountainBlock(
      objectId: objectId,
      objectLength: objectLength,
      blockSeed: blockSeed,
      payload: payload,
    );
  }

  /// Source block [index] into [into] (1024 B) through [_read]; the tail
  /// of the last block is zero, exactly like the padded in-memory copy.
  void _readBlock(int index, Uint8List into) {
    final start = index * kFountainBlockPayloadBytes;
    final n = objectLength - start < kFountainBlockPayloadBytes
        ? objectLength - start
        : kFountainBlockPayloadBytes;
    if (n < kFountainBlockPayloadBytes) {
      into.fillRange(n, kFountainBlockPayloadBytes, 0);
      _read!(start, Uint8List.view(into.buffer, into.offsetInBytes, n));
    } else {
      _read!(start, into);
    }
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
