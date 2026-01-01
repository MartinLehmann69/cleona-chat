/// bspatch — applies an update delta on the receiving node (v4_2 §26.6.2).
///
/// Port of `bspatch.c` from bsdiff 4.3 (Copyright 2003-2005 Colin Percival,
/// BSD 2-clause; the full notice stands in `bsdiff.dart`). The control loop
/// is the original's; the streams come from `delta_format.dart`.
///
/// **Pure Dart plus the zstd that every platform already links** — no native
/// shim on four platforms (S406-DELTA, report section 2).
///
/// **Streaming, file to file.** The old file is read through a
/// [RandomAccessFile], the new one written in pieces of at most [_chunk]; of
/// the three streams at most one frame each is decompressed at a time. Peak
/// memory is the delta itself plus a few MiB — not old + new + diff block
/// (~600 MB for an APK) as in the original, which loads all of them.
///
/// **Every check that can fail does so before the result counts.**
///  * The old file must have the size and SHA-256 named in the header — a
///    base that is not the file the delta was made from is refused before a
///    single byte is written.
///  * Every control triple is range-checked (the original's "Corrupt patch").
///  * The streams must be consumed exactly, and the output must have the
///    size and SHA-256 named in the header.
/// Any failure deletes the partial output and throws [DeltaFormatException].
/// Checking the result against the MANIFEST is the caller's job
/// (`update_target.dart`); the header hash is not a trust anchor, the
/// signed manifest is.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_sha256.dart';
import 'package:cleona/core/update/delta/delta_format.dart';

const int _chunk = 1024 * 1024;

/// Applies [patch] to the file at [oldPath] and writes the result to
/// [outPath]. Returns the size of the result.
Future<int> bspatchFile({
  required String oldPath,
  required Uint8List patch,
  required String outPath,
}) async {
  final header = DeltaHeader.parse(patch);

  final oldFile = File(oldPath);
  if (!oldFile.existsSync()) {
    throw DeltaFormatException('base file missing: $oldPath');
  }
  final oldSize = oldFile.lengthSync();
  if (oldSize != header.oldSize) {
    throw DeltaFormatException('base has $oldSize B, the delta was made '
        'from ${header.oldSize} B');
  }
  if (!_same(await sha256OfFile(oldPath), header.oldSha256)) {
    throw DeltaFormatException('base SHA-256 differs from the one the delta '
        'was made from');
  }

  var at = kDeltaHeaderLength;
  Uint8List section(int len) {
    final s = Uint8List.sublistView(patch, at, at + len);
    at += len;
    return s;
  }

  final control = FrameReader(section(header.controlLength));
  final diff = FrameReader(section(header.diffLength));
  final extra = FrameReader(section(header.extraLength));

  final out = File(outPath);
  final oldRaf = oldFile.openSync();
  final outRaf = out.openSync(mode: FileMode.write);
  var ok = false;
  try {
    final triple = Uint8List(24);
    final tripleView = ByteData.sublistView(triple);
    final buf = Uint8List(_chunk);
    final oldBuf = Uint8List(_chunk);
    var newPos = 0;
    var oldPos = 0;

    while (newPos < header.newSize) {
      control.read(triple, 0, 24);
      final add = tripleView.getInt64(0, Endian.little);
      final copy = tripleView.getInt64(8, Endian.little);
      final seek = tripleView.getInt64(16, Endian.little);
      if (add < 0 || copy < 0 || newPos + add > header.newSize) {
        throw DeltaFormatException('control triple out of range');
      }

      // Diff block: new[i] = diff[i] + old[i] where old[i] exists.
      var left = add;
      while (left > 0) {
        final n = left < _chunk ? left : _chunk;
        diff.read(buf, 0, n);
        final lo = oldPos < 0 ? -oldPos : 0;
        final hi = oldPos + n > oldSize ? oldSize - oldPos : n;
        if (lo < hi) {
          oldRaf.setPositionSync(oldPos + lo);
          oldRaf.readIntoSync(oldBuf, lo, hi);
          for (var i = lo; i < hi; i++) {
            buf[i] = (buf[i] + oldBuf[i]) & 0xFF;
          }
        }
        outRaf.writeFromSync(buf, 0, n);
        oldPos += n;
        newPos += n;
        left -= n;
      }

      if (newPos + copy > header.newSize) {
        throw DeltaFormatException('extra length out of range');
      }
      left = copy;
      while (left > 0) {
        final n = left < _chunk ? left : _chunk;
        extra.read(buf, 0, n);
        outRaf.writeFromSync(buf, 0, n);
        newPos += n;
        left -= n;
      }
      oldPos += seek;
    }

    if (!control.atEnd || !diff.atEnd || !extra.atEnd) {
      throw DeltaFormatException('streams not consumed exactly');
    }
    ok = true;
  } finally {
    oldRaf.closeSync();
    outRaf.closeSync();
    if (!ok && out.existsSync()) out.deleteSync();
  }

  if (out.lengthSync() != header.newSize ||
      !_same(await sha256OfFile(outPath), header.newSha256)) {
    out.deleteSync();
    throw DeltaFormatException('result does not match the header');
  }
  return header.newSize;
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
