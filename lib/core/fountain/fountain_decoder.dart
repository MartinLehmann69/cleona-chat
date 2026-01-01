import 'dart:typed_data';

import 'block_xor.dart';
import 'degree_distribution.dart';
import 'fountain_block.dart';

/// What a [FountainDecoder.offer] did with a block.
enum FountainOffer {
  /// The block resolved at least one source block.
  resolved,

  /// The block is taken in but has (not yet) resolved anything — it waits
  /// for its neighbours to melt.
  stored,

  /// All neighbours were already known: the block contributed nothing.
  /// **Not an error** — normal with rateless coding, especially at the
  /// end.
  redundant,

  /// The same block seed was already present.
  duplicate,

  /// The block belongs to a different object (identifier or length
  /// differ). The normal case when scanning a tag line, not a protocol
  /// violation.
  foreign,

  /// The decoder was already complete.
  complete,
}

/// An encoded block not yet resolved.
///
/// ── WHY THERE IS NO NEIGHBOUR LIST HERE ──────────────────────────────
///
/// The block must be able to answer two questions: *how many* neighbours
/// are still unknown, and — as soon as it is exactly one — *which*.
/// The obvious answer is a list from which resolved neighbours are
/// struck out. It was the first version built and is **quadratic in the
/// degree**: striking out requires a search over the remaining list, and
/// that per neighbour. At k = 204 800 the spike of the robust soliton
/// distribution lies at degree **583** (with today's defaults) up to
/// **2972** (with the smallest value of the measurement grid, c = 0.01);
/// a single such block then costs degree-squared-halved steps, and there
/// are hundreds of those per run. Measured: the grid run over
/// k = 204 800 did not get through a single row in ten minutes.
///
/// The list is not needed at all either. What is needed is a **count**
/// and, at the end, a **single index** — and a single index can be
/// recovered from an XOR sum:
///
/// * [remaining] counts the unknown neighbours,
/// * [remainingSum] is the XOR of their indices.
///
/// When [remaining] drops to 1, [remainingSum] **is** the index sought —
/// all others have cancelled each other out pairwise while being computed
/// out. That presupposes that the neighbours of a block are pairwise
/// distinct; exactly that is guaranteed by `FountainPrng.distinctIndices`.
///
/// Cost per edge: one subtraction and one XOR on an integer — instead of
/// a search. And the memory per waiting block drops by the whole
/// neighbour list.
class _Pending {
  /// The partial expression: payload of the block, out of which all
  /// already known neighbours have been computed.
  final Uint8List acc;

  /// Number of still unknown neighbours.
  int remaining;

  /// XOR of the indices of the still unknown neighbours.
  int remainingSum;

  /// Does this block stand in at least one `_waitingOn` list?
  /// Only registered blocks count in `_pendingCount`.
  bool registered = false;

  /// Done — resolved or become useless. Leftover references in
  /// `_waitingOn` are recognised by this and skipped.
  bool retired = false;

  _Pending(this.acc, this.remaining, this.remainingSum);
}

/// Decoding side of the rateless codec: **peeling**.
///
/// ── THE PROCEDURE ────────────────────────────────────────────────────
///
/// Every arriving block is the XOR of a neighbourhood of source blocks;
/// which one follows from `(k, blockSeed)` in the header — nothing about
/// it stands on the wire (`degree_distribution.dart`).
///
/// 1. Known neighbours are immediately computed out of the block.
/// 2. If exactly **one** remains, the block is this source block.
/// 3. A freshly resolved source block is computed out of all waiting
///    blocks that contain it — that may push further ones down to a
///    remainder of one. The wave runs until it stops.
///
/// ── THE PROMISE THIS CLASS MUST GIVE ──────────────────────────
///
/// **An incomplete decoder delivers nothing.** [takeObject] returns
/// `null` as long as not **all** `k` source blocks are resolved. That is
/// not convenience but the core promise: a fountain decoding that stops
/// at 99 % and delivers the missing blocks as zeros would be silently
/// wrong — the recipient would get a file that looks like a file. The
/// full content hash does catch that later (§26.6.1 step 5), but a codec
/// that relies on the caller's check is the wrong place for this
/// responsibility.
///
/// ── WHAT IT DOES NOT CHECK ──────────────────────────────────────────────
///
/// The authenticity of the content. The 8 B object identifier binds a
/// block to an object, it does not prove it. An attacker who can slip
/// in a valid block header with a wrong payload destroys the
/// reconstruction — and is caught by the caller's content hash, which
/// then discards the whole version state and fetches it anew (§26.6.1,
/// "Self-healing on failed verification"). On the transport path the
/// AEAD of the cell additionally protects (§5.2).
class FountainDecoder {
  /// Identifier of the object this decoder assembles.
  final Uint8List objectId;

  /// Expected length of the original object.
  final int objectLength;

  /// `k = ceil(objectLength / 1024)`.
  final int sourceBlocks;

  /// Degree distribution — must match that of the encoder.
  final DegreeDistribution distribution;

  final List<Uint8List?> _source;
  final List<List<_Pending>?> _waitingOn;
  final Set<int> _seenSeeds = <int>{};

  int _resolved = 0;
  int _accepted = 0;
  int _rejected = 0;
  int _pendingCount = 0;

  FountainDecoder._(
    this.objectId,
    this.objectLength,
    this.sourceBlocks,
    this.distribution,
    this._source,
    this._waitingOn,
  );

  /// Decoder for an object whose identifier and length are known
  /// (from the manifest, from the media offer).
  factory FountainDecoder({
    required Uint8List objectId,
    required int objectLength,
    double c = DegreeDistribution.defaultC,
    double failureBound = DegreeDistribution.defaultFailureBound,
  }) {
    if (objectId.length != kFountainObjectIdBytes) {
      throw ArgumentError('objectId must be $kFountainObjectIdBytes B');
    }
    if (objectLength <= 0 || objectLength > kFountainMaxObjectBytes) {
      throw ArgumentError.value(
        objectLength,
        'objectLength',
        'must lie in [1, $kFountainMaxObjectBytes]',
      );
    }
    final k = FountainBlock.sourceBlockCount(objectLength);
    return FountainDecoder._(
      Uint8List.fromList(objectId),
      objectLength,
      k,
      DegreeDistribution(k, c: c, failureBound: failureBound),
      List<Uint8List?>.filled(k, null),
      List<List<_Pending>?>.filled(k, null),
    );
  }

  /// Decoder from the first harvested block.
  ///
  /// The header carries everything needed — identifier and length.
  /// Whoever, while scanning, comes across a block whose object he wants
  /// needs no second source to start (§9: "scan instead of query").
  factory FountainDecoder.forBlock(
    FountainBlock first, {
    double c = DegreeDistribution.defaultC,
    double failureBound = DegreeDistribution.defaultFailureBound,
  }) {
    final d = FountainDecoder(
      objectId: first.objectId,
      objectLength: first.objectLength,
      c: c,
      failureBound: failureBound,
    );
    d.offer(first);
    return d;
  }

  /// Aufgeloeste Quellbloecke.
  int get resolvedSourceBlocks => _resolved;

  /// Blocks that were accepted as usable (not foreign, not duplicate) —
  /// the counter on which the overhead figure is measured.
  int get blocksAccepted => _accepted;

  /// Blocks that were discarded as foreign or duplicate.
  int get blocksRejected => _rejected;

  /// Stored blocks not yet resolved.
  int get pendingBlocks => _pendingCount;

  /// Are all source blocks present?
  bool get isComplete => _resolved == sourceBlocks;

  /// Share of the source blocks already resolved, `[0,1]`.
  double get progress => _resolved / sourceBlocks;

  /// Accepts a block.
  ///
  /// The decoder **copies** the payload; the caller may reuse its block
  /// afterwards.
  FountainOffer offer(FountainBlock block) {
    if (isComplete) return FountainOffer.complete;
    if (!FountainBlock.sameObject(block.objectId, objectId) ||
        block.objectLength != objectLength) {
      _rejected++;
      return FountainOffer.foreign;
    }
    if (!_seenSeeds.add(block.blockSeed)) {
      _rejected++;
      return FountainOffer.duplicate;
    }
    _accepted++;

    final neigh = distribution.neighbours(block.blockSeed);
    final acc = Uint8List.fromList(block.payload);

    // Step 1: compute known neighbours out immediately; of the unknown
    // ones only the count and the XOR sum of their indices remain.
    final open = Uint32List(neigh.length);
    var openCount = 0;
    var openSum = 0;
    for (var i = 0; i < neigh.length; i++) {
      final s = neigh[i];
      final known = _source[s];
      if (known != null) {
        BlockXor.xorInto(acc, known);
      } else {
        open[openCount++] = s;
        openSum ^= s;
      }
    }

    if (openCount == 0) return FountainOffer.redundant;

    final p = _Pending(acc, openCount, openSum);

    if (openCount == 1) {
      final before = _resolved;
      _cascade(p);
      return _resolved > before
          ? FountainOffer.resolved
          : FountainOffer.redundant;
    }

    for (var i = 0; i < openCount; i++) {
      (_waitingOn[open[i]] ??= <_Pending>[]).add(p);
    }
    p.registered = true;
    _pendingCount++;
    return FountainOffer.stored;
  }

  /// The peeling wave, starting from a block with remainder 1.
  ///
  /// Iterative with its own work list instead of recursive: the wave can
  /// run tens of thousands of steps deep for large `k`, and a recursive
  /// descent of that depth blows the stack. (Exactly this error is the
  /// most frequent one in LT decoders in the literature.)
  void _cascade(_Pending start) {
    final work = <_Pending>[start];
    while (work.isNotEmpty) {
      final p = work.removeLast();
      if (p.retired || p.remaining != 1) continue;
      _retire(p);

      final idx = p.remainingSum;
      if (_source[idx] != null) continue; // was already resolved otherwise
      _source[idx] = p.acc;
      _resolved++;

      final waiters = _waitingOn[idx];
      if (waiters == null) continue;
      _waitingOn[idx] = null;
      for (final w in waiters) {
        if (w.retired) continue;
        // Compute `idx` out of the block: XOR the payload, lower the
        // counter, remove the index from the XOR sum. No searching.
        // Every waiting block stands exactly once in this list, because
        // the neighbours of a block are pairwise distinct — so `idx`
        // cannot be subtracted twice here.
        BlockXor.xorInto(w.acc, p.acc);
        w.remaining--;
        w.remainingSum ^= idx;
        if (w.remaining == 0) {
          // All neighbours became known otherwise: the block contributes
          // nothing any more.
          _retire(w);
        } else if (w.remaining == 1) {
          work.add(w);
        }
      }
    }
  }

  /// Takes a block out of circulation — exactly once.
  ///
  /// The counter [pendingBlocks] is lowered **here** and only here. An
  /// earlier version lowered it on the transition to remainder 1 AND on
  /// the transition to remainder 0; a block that went through both
  /// before the wave reached it was subtracted twice.
  void _retire(_Pending p) {
    if (p.retired) return;
    p.retired = true;
    if (p.registered) _pendingCount--;
  }

  /// The reconstructed object — or `null` as long as even a single
  /// source block is missing.
  ///
  /// **Never a partial result.** See class documentation.
  Uint8List? takeObject() {
    if (!isComplete) return null;
    final out = Uint8List(objectLength);
    var written = 0;
    for (var i = 0; i < sourceBlocks && written < objectLength; i++) {
      final b = _source[i]!;
      final n = objectLength - written < kFountainBlockPayloadBytes
          ? objectLength - written
          : kFountainBlockPayloadBytes;
      out.setRange(written, written + n, b);
      written += n;
    }
    return out;
  }
}
