/// Container format of a Cleona update delta (v4_2 §26.6.2, S406-DELTA).
///
/// ── WHAT IS bsdiff HERE, AND WHAT IS NOT ───────────────────────────────
///
/// The DIFFERENCING is bsdiff 4.3 (Colin Percival, 2003): suffix sort of the
/// old file, approximate matches, and the three streams of the classic
/// format — control triples (add length, copy length, seek), the bytewise
/// difference block and the extra block. `bsdiff.dart` and `bspatch.dart`
/// are a line-by-line port of that algorithm.
///
/// The CONTAINER is not the classic `BSDIFF40`. Two deviations, both named:
///
///  1. The three streams are compressed with **zstd**, not bzip2. zstd is
///     already linked on all four update platforms (`lib/core/codec/
///     compression.dart`, `libzstd` in the Android, Linux, Windows and
///     macOS bundles); bzip2 is on none of them. Classic `BSDIFF40` would
///     need a bzip2 decoder on the phone — a new native library on four
///     platforms or a new pure-Dart dependency — for a compressor that is
///     both slower and weaker than the one already there.
///  2. Each stream is cut into **frames of at most [kFrameRaw] bytes**, each
///     compressed on its own. The receiver therefore never holds a whole
///     stream decompressed: patching a ~200 MB APK on the phone needs
///     O(frame) memory for the streams instead of O(file) (S406 B-8).
///
/// Consequence: a stock `bspatch` cannot read this file, and this code cannot
/// read a stock `BSDIFF40` file. Both ends are Cleona's own (the pipeline
/// writes, the node reads), so nothing outside depends on the classic
/// container.
///
/// The header additionally carries the SHA-256 of the old and of the new file.
/// The old hash lets the receiver refuse a base that is not the file the
/// delta was made from BEFORE it writes a single byte (a same-numbered build
/// installed by hand is such a base); the new hash is a second check behind
/// the manifest's `binHash`.
///
/// Layout (all integers little-endian):
///
/// ```text
///   0  8  magic "BSDZSTD1"
///   8  8  new size (u64)
///  16  8  old size (u64)
///  24 32  SHA-256 of the old file
///  56 32  SHA-256 of the new file
///  88  8  length of the control section (bytes)
///  96  8  length of the diff section
/// 104  8  length of the extra section
/// 112  …  control section, diff section, extra section
/// ```
///
/// A section is a sequence of frames `[u32 compressed length][zstd frame]`.
/// The control stream decompresses to triples of signed 64-bit integers
/// `(add, copy, seek)`.
library;

import 'dart:typed_data';

import 'package:cleona/core/codec/compression.dart';

/// The eight bytes every delta starts with.
const List<int> kDeltaMagic = [0x42, 0x53, 0x44, 0x5A, 0x53, 0x54, 0x44, 0x31];

/// Bytes before the first section.
const int kDeltaHeaderLength = 112;

/// Largest uncompressed size of one frame. 4 MiB: far below the 64 MiB cap
/// of [ZstdCompression.decompress], large enough that the per-frame overhead
/// (4 B length + ~12 B zstd header) is negligible.
const int kFrameRaw = 4 * 1024 * 1024;

/// zstd level used by the generator (release workstation only). 19 is the
/// highest level without `--ultra`; decompression speed does not depend on it.
const int kDeltaZstdLevel = 19;

/// A malformed or mismatching delta. Every caller treats it the same way:
/// fall back to the full binary (§26.6.2).
class DeltaFormatException implements Exception {
  final String message;
  DeltaFormatException(this.message);
  @override
  String toString() => 'DeltaFormatException: $message';
}

/// The parsed fixed header of a delta.
class DeltaHeader {
  final int newSize;
  final int oldSize;
  final Uint8List oldSha256;
  final Uint8List newSha256;
  final int controlLength;
  final int diffLength;
  final int extraLength;

  DeltaHeader({
    required this.newSize,
    required this.oldSize,
    required this.oldSha256,
    required this.newSha256,
    required this.controlLength,
    required this.diffLength,
    required this.extraLength,
  });

  Uint8List encode() {
    final b = Uint8List(kDeltaHeaderLength);
    final d = ByteData.sublistView(b);
    b.setAll(0, kDeltaMagic);
    d.setUint64(8, newSize, Endian.little);
    d.setUint64(16, oldSize, Endian.little);
    b.setAll(24, oldSha256);
    b.setAll(56, newSha256);
    d.setUint64(88, controlLength, Endian.little);
    d.setUint64(96, diffLength, Endian.little);
    d.setUint64(104, extraLength, Endian.little);
    return b;
  }

  /// Reads the header of [patch] and checks that the three sections exactly
  /// fill the rest of it.
  static DeltaHeader parse(Uint8List patch) {
    if (patch.length < kDeltaHeaderLength) {
      throw DeltaFormatException('shorter than the header '
          '(${patch.length} B)');
    }
    for (var i = 0; i < kDeltaMagic.length; i++) {
      if (patch[i] != kDeltaMagic[i]) {
        throw DeltaFormatException('wrong magic');
      }
    }
    final d = ByteData.sublistView(patch);
    final h = DeltaHeader(
      newSize: d.getUint64(8, Endian.little),
      oldSize: d.getUint64(16, Endian.little),
      oldSha256: Uint8List.fromList(patch.sublist(24, 56)),
      newSha256: Uint8List.fromList(patch.sublist(56, 88)),
      controlLength: d.getUint64(88, Endian.little),
      diffLength: d.getUint64(96, Endian.little),
      extraLength: d.getUint64(104, Endian.little),
    );
    final lengths = [h.newSize, h.oldSize, h.controlLength, h.diffLength,
        h.extraLength];
    if (lengths.any((v) => v < 0)) {
      throw DeltaFormatException('negative length in the header');
    }
    final total =
        kDeltaHeaderLength + h.controlLength + h.diffLength + h.extraLength;
    if (total != patch.length) {
      throw DeltaFormatException('sections ($total B) do not fill the delta '
          '(${patch.length} B)');
    }
    return h;
  }
}

/// Collects a stream and cuts it into compressed frames of [kFrameRaw].
class FrameWriter {
  final int level;
  final BytesBuilder _out = BytesBuilder(copy: false);
  final BytesBuilder _pending = BytesBuilder();

  FrameWriter({this.level = kDeltaZstdLevel});

  void add(List<int> bytes) {
    var offset = 0;
    while (offset < bytes.length) {
      final room = kFrameRaw - _pending.length;
      final take =
          (bytes.length - offset) < room ? bytes.length - offset : room;
      _pending.add(bytes is Uint8List
          ? Uint8List.sublistView(bytes, offset, offset + take)
          : bytes.sublist(offset, offset + take));
      offset += take;
      if (_pending.length == kFrameRaw) _flush();
    }
  }

  void _flush() {
    if (_pending.isEmpty) return;
    final raw = _pending.takeBytes();
    final frame = ZstdCompression.instance.compress(raw, level: level);
    final len = ByteData(4)..setUint32(0, frame.length, Endian.little);
    _out.add(len.buffer.asUint8List());
    _out.add(frame);
  }

  /// The finished section.
  Uint8List finish() {
    _flush();
    return _out.takeBytes();
  }
}

/// Reads a section frame by frame; holds at most one decompressed frame.
class FrameReader {
  final Uint8List _section;
  int _at = 0;
  Uint8List _frame = Uint8List(0);
  int _inFrame = 0;

  FrameReader(this._section);

  /// Copies the next [n] bytes of the stream into [into] at [offset].
  void read(Uint8List into, int offset, int n) {
    var done = 0;
    while (done < n) {
      if (_inFrame == _frame.length) _next();
      final avail = _frame.length - _inFrame;
      final take = (n - done) < avail ? n - done : avail;
      into.setRange(offset + done, offset + done + take, _frame, _inFrame);
      _inFrame += take;
      done += take;
    }
  }

  /// True once every frame has been consumed completely.
  bool get atEnd => _at == _section.length && _inFrame == _frame.length;

  void _next() {
    if (_at + 4 > _section.length) {
      throw DeltaFormatException('stream ends early');
    }
    final len = ByteData.sublistView(_section, _at, _at + 4)
        .getUint32(0, Endian.little);
    _at += 4;
    if (len == 0 || _at + len > _section.length) {
      throw DeltaFormatException('frame length $len out of range');
    }
    final Uint8List raw;
    try {
      raw = ZstdCompression.instance
          .decompress(Uint8List.sublistView(_section, _at, _at + len));
    } on ZstdException catch (e) {
      throw DeltaFormatException('frame does not decompress: ${e.message}');
    }
    _at += len;
    if (raw.isEmpty || raw.length > kFrameRaw) {
      throw DeltaFormatException('frame of ${raw.length} B out of range');
    }
    _frame = raw;
    _inFrame = 0;
  }
}
