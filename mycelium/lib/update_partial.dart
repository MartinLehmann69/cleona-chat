/// The partial state of the update target ON DISK (S406-UPDPKG, P2) —
/// v4_2 §26.6.1 "transient errors (too few blocks available) delete
/// nothing, the partial state stays in place for resumption".
///
/// Until S406 the state lived only in a `FountainDecoder` in memory: a run
/// that ended without the object — 2.4 s of silence, a process end, a
/// network change — dropped everything it had (07.10.2026 21:00:54: ~37 MB
/// after 8 min 48 s). Here it lies in the profile, under the object's
/// SHA-256, and survives abort, network change and restart. It is discarded
/// only on a failed check or when another object becomes the target
/// ([UpdateAssembler.expect]).
///
/// ── WHAT LIES ON DISK, AND WHY THREE FILES ─────────────────────────────
///
/// `<base>/<object hex>/`
///  * `length` — the object length (text); another length = another state.
///  * `object` — the source blocks resolved so far, each at `index × 1024`
///    (a sparse file until the end); at the end cut to `length`: the object.
///  * `resolved` — the bitmap: bit i = source block i is in `object`.
///  * `blocks` — every received block that could not be resolved yet, as it
///    arrived: block seed (4 B) + payload (1024 B).
///
/// The third file is needed because of how peeling works, measured on
/// 07.10.2026 (k = 20 000, the codec of `lib/core/fountain/`): after 1.0 k
/// received blocks only 7.6 % of the source blocks are resolved, 92 % of
/// what arrived still waits; the object completes at 1.05 k. A state of
/// "resolved blocks + bitmap" alone would keep almost nothing.
///
/// ── WHAT LIES IN MEMORY ───────────────────────────────────────────────
///
/// No payload, and no object per block: plain number arrays. Per stored
/// block its seed, a counter and an XOR sum (12 B); per edge "source block
/// → stored block" 8 B (a list linked through two arrays); per source block
/// the head of its list and one bit for "resolved". The payload is read from
/// disk only when a block resolves ("lazy XOR": every edge is XORed exactly
/// once, as in the in-memory decoder). Measured S406-UPDPKG: see the report.
/// A block that arrives twice is stored twice and resolves to nothing the
/// second time — with random 32-bit seeds that is a handful per 200 MB.
///
/// No clock, no packet: this class only reads and writes files.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/fountain/block_xor.dart';
import 'package:cleona/core/fountain/degree_distribution.dart';
import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:cleona/core/fountain/fountain_decoder.dart' show FountainOffer;

const int _kRecord = 4 + kFountainBlockPayloadBytes;

/// A growable array of 32-bit numbers (grows by half, no object per element).
class _Ints {
  Int32List _a = Int32List(1024);
  int length = 0;
  int operator [](int i) => _a[i];
  void operator []=(int i, int v) => _a[i] = v;
  void add(int v) {
    if (length == _a.length) {
      _a = Int32List(_a.length + (_a.length >> 1))..setRange(0, length, _a);
    }
    _a[length++] = v;
  }
}

String partialHex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

class UpdatePartial {
  final String dir;
  final Uint8List object;
  final int length;
  final int sourceBlocks;
  final DegreeDistribution _dist;
  final RandomAccessFile _obj;
  final RandomAccessFile _bits;
  RandomAccessFile? _log;
  final Uint8List _known;

  /// Per stored block (index = its record in `blocks`): seed, unknown
  /// neighbours (-1 = done), XOR of their indices.
  final _Ints _seed = _Ints(), _remaining = _Ints(), _sum = _Ints();

  /// Edges: per source block the first, per edge the record and the next.
  final Int32List _head;
  final _Ints _edgeRecord = _Ints(), _edgeNext = _Ints();

  /// Source blocks resolved whose waiting blocks are not worked off yet —
  /// the peeling wave, worked off in batches ([drain]).
  final List<int> _work = <int>[];
  final Uint8List _scratch = Uint8List(kFountainBlockPayloadBytes);
  int _resolved = 0;
  int _records = 0;
  int _waiting = 0;
  bool _closed = false;

  /// Whether the state came from disk ([open] found one).
  final bool resumed;

  UpdatePartial._(this.dir, this.object, this.length, this._obj, this._bits,
      this._log, this.resumed)
      : sourceBlocks = FountainBlock.sourceBlockCount(length),
        _dist = DegreeDistribution(FountainBlock.sourceBlockCount(length)),
        _known = Uint8List((FountainBlock.sourceBlockCount(length) + 7) >> 3),
        _head = Int32List(FountainBlock.sourceBlockCount(length))..fillRange(
            0, FountainBlock.sourceBlockCount(length), -1);

  /// The directory of [object] under [base].
  static String dirFor(String base, Uint8List object) =>
      '$base${Platform.pathSeparator}${partialHex(object)}';

  /// Opens the state of [object] ([length] B) under [base] — the one on
  /// disk if its length matches, otherwise a fresh one. Replays what is
  /// there: the bitmap, then every stored block (a torn last record from a
  /// process end in the middle of a write is cut off).
  static UpdatePartial open(String base, Uint8List object, int length) {
    final d = Directory(dirFor(base, object));
    final lengthFile = File('${d.path}/length');
    var resumed = false;
    if (d.existsSync()) {
      int? had;
      try {
        had = int.tryParse(lengthFile.readAsStringSync().trim());
      } on Object {
        had = null;
      }
      if (had == length) {
        resumed = true;
      } else {
        d.deleteSync(recursive: true);
      }
    }
    d.createSync(recursive: true);
    if (!resumed) lengthFile.writeAsStringSync('$length', flush: true);
    RandomAccessFile f(String name) {
      final file = File('${d.path}/$name');
      if (!file.existsSync()) file.createSync();
      // `append` neither truncates nor forces writes to the end: the
      // position set before each write is where it lands.
      return file.openSync(mode: FileMode.append);
    }

    final p = UpdatePartial._(d.path, Uint8List.fromList(object), length,
        f('object'), f('resolved'), f('blocks'), resumed);
    p._replay();
    return p;
  }

  int get resolved => _resolved;

  /// Whether the peeling wave has work left ([drain]).
  bool get busy => _work.isNotEmpty && !_closed && !isComplete;
  int get waiting => _waiting;

  /// Blocks stored in `blocks` (received and not resolvable on arrival).
  int get stored => _records;
  bool get isComplete => _resolved == sourceBlocks;
  String get objectPath => '$dir/object';

  /// One line for reports and the diagnosis.
  String describe() => '$_resolved/$sourceBlocks resolved, $_waiting waiting, '
      '$_records block(s) stored';

  void _replay() {
    _bits.setPositionSync(0);
    final have = _bits.readSync(_known.length);
    _known.setRange(0, have.length, have);
    for (var i = 0; i < sourceBlocks; i++) {
      if (_isKnown(i)) _resolved++;
    }
    final log = _log!;
    final len = log.lengthSync();
    final whole = len ~/ _kRecord;
    if (whole * _kRecord != len) log.truncateSync(whole * _kRecord);
    _records = whole;
    if (isComplete) return;
    final seed = Uint8List(4);
    for (var r = 0; r < whole && !isComplete; r++) {
      log.setPositionSync(r * _kRecord);
      log.readIntoSync(seed);
      _take(r, ByteData.sublistView(seed).getUint32(0), null);
    }
    while (drain(1 << 30)) {}
  }

  bool _isKnown(int i) => (_known[i >> 3] & (1 << (i & 7))) != 0;

  /// Accepts a block; the same answers as `FountainDecoder.offer`.
  FountainOffer offer(FountainBlock block) {
    if (_closed || isComplete) return FountainOffer.complete;
    if (block.objectLength != length ||
        !FountainBlock.sameObject(
            block.objectId, object.sublist(0, kFountainObjectIdBytes))) {
      return FountainOffer.foreign;
    }
    final n = _dist.neighbours(block.blockSeed);
    var open = 0;
    for (final s in n) {
      if (!_isKnown(s)) open++;
    }
    if (open == 0) return FountainOffer.redundant;
    if (open == 1) return _take(-1, block.blockSeed, block.payload);
    final log = _log!;
    log.setPositionSync(_records * _kRecord);
    final head = ByteData(4)..setUint32(0, block.blockSeed);
    log.writeFromSync(head.buffer.asUint8List());
    log.writeFromSync(block.payload);
    return _take(_records++, block.blockSeed, block.payload);
  }

  /// [record] is the block's place in `blocks`, or -1 if it was not stored
  /// (then [payload] is its payload).
  FountainOffer _take(int record, int seed, Uint8List? payload) {
    final n = _dist.neighbours(seed);
    var open = 0;
    var sum = 0;
    for (final s in n) {
      if (!_isKnown(s)) {
        open++;
        sum ^= s;
      }
    }
    if (open == 0) return FountainOffer.redundant;
    if (open == 1) {
      final acc = payload != null
          ? Uint8List.fromList(payload)
          : _readRecord(record);
      _resolve(sum, acc, n);
      _cascade(sum);
      return FountainOffer.resolved;
    }
    while (_seed.length <= record) {
      _seed.add(0);
      _remaining.add(-1);
      _sum.add(0);
    }
    _seed[record] = seed;
    _remaining[record] = open;
    _sum[record] = sum;
    for (final s in n) {
      if (_isKnown(s)) continue;
      _edgeRecord.add(record);
      _edgeNext.add(_head[s]);
      _head[s] = _edgeRecord.length - 1;
    }
    _waiting++;
    return FountainOffer.stored;
  }

  /// Source block [index] = [acc] XOR every other neighbour in [n] (all of
  /// them resolved), written to `object`, its bit to `resolved`.
  void _resolve(int index, Uint8List acc, Uint32List n) {
    for (final s in n) {
      if (s == index) continue;
      _obj.setPositionSync(s * kFountainBlockPayloadBytes);
      _obj.readIntoSync(_scratch);
      BlockXor.xorInto(acc, _scratch);
    }
    _obj.setPositionSync(index * kFountainBlockPayloadBytes);
    _obj.writeFromSync(acc);
    _known[index >> 3] |= 1 << (index & 7);
    _bits.setPositionSync(index >> 3);
    _bits.writeByteSync(_known[index >> 3]);
    _resolved++;
  }

  void _cascade(int first) {
    _work.add(first);
    drain();
  }

  /// Works off the peeling wave until [batch] blocks resolved (each reads
  /// its neighbours from disk); `true` while more is left — a list cut in
  /// the middle goes on where it stopped. The wave at the end of a ~200 MB object reads every edge
  /// from disk — 11.9 s in one piece on the workstation (S406-UPDPKG); the
  /// caller hands the event loop a turn between batches (as §11.1 does for
  /// sending), so a node in the same process as its surface never stalls.
  /// Iterative, as in the in-memory decoder.
  bool drain([int batch = 64]) {
    if (_closed || isComplete) {
      _work.clear();
      return false;
    }
    var n = 0;
    while (_work.isNotEmpty) {
      final index = _work.removeLast();
      var e = _head[index];
      _head[index] = -1;
      for (; e != -1; e = _edgeNext[e]) {
        if (n >= batch) {
          _head[index] = e;
          _work.add(index);
          return busy;
        }
        final r = _edgeRecord[e];
        final left = _remaining[r] - 1;
        if (left < 0) continue; // done before
        final sum = _sum[r] ^ index;
        _sum[r] = sum;
        if (left > 1) {
          _remaining[r] = left;
          continue;
        }
        _remaining[r] = -1;
        _waiting--;
        if (left == 0 || _isKnown(sum)) continue;
        _resolve(sum, _readRecord(r), _dist.neighbours(_seed[r]));
        _work.add(sum);
        n++;
      }
    }
    return busy;
  }

  Uint8List _readRecord(int record) {
    final out = Uint8List(kFountainBlockPayloadBytes);
    final log = _log!;
    log.setPositionSync(record * _kRecord + 4);
    log.readIntoSync(out);
    return out;
  }

  /// Once complete: `object` cut to the object length, `blocks` deleted.
  /// Returns the path of the object. The caller checks it.
  String finish() {
    if (!isComplete) throw StateError('not complete');
    if (!_closed) {
      _obj.truncateSync(length);
      _obj.flushSync();
      close();
    }
    final log = File('$dir/blocks');
    if (log.existsSync()) log.deleteSync();
    return objectPath;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _obj.closeSync();
    _bits.closeSync();
    _log?.closeSync();
    _log = null;
  }

  /// Closes and deletes the whole state.
  void delete() {
    close();
    final d = Directory(dir);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}
