/// bsdiff — the generator of an update delta (v4_2 §26.6.2). Runs only on the
/// release workstation (`bin/cleona_make_delta.dart`, `scripts/make-delta.sh`);
/// no node ever calls it.
///
/// Port of `bsdiff.c` from bsdiff 4.3:
///
///   Copyright 2003-2005 Colin Percival. All rights reserved.
///   Redistribution and use in source and binary forms, with or without
///   modification, are permitted providing that the following conditions
///   are met: 1. Redistributions of source code must retain the above
///   copyright notice, this list of conditions and the following disclaimer.
///   2. Redistributions in binary form must reproduce the above copyright
///   notice, this list of conditions and the following disclaimer in the
///   documentation and/or other materials provided with the distribution.
///   THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
///   IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
///   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
///   DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
///   INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
///   (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
///   SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
///   HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
///   STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
///   IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
///   POSSIBILITY OF SUCH DAMAGE.
///
/// The algorithm is unchanged: Larsson-Sadakane suffix sort (`qsufsort`),
/// binary search for the longest match, the forward/backward extension and
/// the overlap resolution of the original. What differs is the container
/// (`delta_format.dart`: zstd frames instead of bzip2) and the integer width:
/// the suffix arrays are [Int32List] (files up to 2 GiB - 1; the largest
/// update object today is a ~200 MB APK), which halves the generator's
/// memory against the original's `off_t`.
///
/// Memory: old + new + 8 × (old + 1) for the two suffix arrays + up to new
/// for the diff block, before compression — about 2.4 GB for a 200 MB APK.
library;

import 'dart:typed_data';

import 'package:cleona/core/update/delta/delta_format.dart';

/// Largest file the 32-bit suffix arrays can index.
const int kBsdiffMaxSize = 0x7FFFFFFE;

/// Builds the delta that turns [oldBytes] into [newBytes].
///
/// [oldSha256] and [newSha256] are written into the header; the caller
/// computes them (the generator does not depend on a hash library).
Uint8List bsdiff(Uint8List oldBytes, Uint8List newBytes,
    {required Uint8List oldSha256,
    required Uint8List newSha256,
    int level = kDeltaZstdLevel}) {
  if (oldBytes.length > kBsdiffMaxSize || newBytes.length > kBsdiffMaxSize) {
    throw ArgumentError('bsdiff: files above $kBsdiffMaxSize B are not '
        'supported (32-bit suffix array)');
  }
  final oldSize = oldBytes.length;
  final newSize = newBytes.length;
  final suffixes = _suffixSort(oldBytes);

  final control = FrameWriter(level: level);
  final diff = FrameWriter(level: level);
  final extra = FrameWriter(level: level);
  final triple = ByteData(24);

  var scan = 0, len = 0, pos = 0;
  var lastScan = 0, lastPos = 0, lastOffset = 0;
  final found = _Match();

  while (scan < newSize) {
    var oldScore = 0;
    var scsc = scan += len;
    for (; scan < newSize; scan++) {
      len = _search(suffixes, oldBytes, newBytes, scan, 0, oldSize, found);
      pos = found.pos;
      for (; scsc < scan + len; scsc++) {
        if (scsc + lastOffset < oldSize &&
            oldBytes[scsc + lastOffset] == newBytes[scsc]) {
          oldScore++;
        }
      }
      if ((len == oldScore && len != 0) || len > oldScore + 8) break;
      if (scan + lastOffset < oldSize &&
          oldBytes[scan + lastOffset] == newBytes[scan]) {
        oldScore--;
      }
    }

    if (len != oldScore || scan == newSize) {
      var s = 0, sf = 0, lenF = 0;
      for (var i = 0; lastScan + i < scan && lastPos + i < oldSize;) {
        if (oldBytes[lastPos + i] == newBytes[lastScan + i]) s++;
        i++;
        if (s * 2 - i > sf * 2 - lenF) {
          sf = s;
          lenF = i;
        }
      }

      var lenB = 0;
      if (scan < newSize) {
        var sb = 0;
        s = 0;
        for (var i = 1; scan >= lastScan + i && pos >= i; i++) {
          if (oldBytes[pos - i] == newBytes[scan - i]) s++;
          if (s * 2 - i > sb * 2 - lenB) {
            sb = s;
            lenB = i;
          }
        }
      }

      if (lastScan + lenF > scan - lenB) {
        final overlap = (lastScan + lenF) - (scan - lenB);
        var ss = 0, lenS = 0;
        s = 0;
        for (var i = 0; i < overlap; i++) {
          if (newBytes[lastScan + lenF - overlap + i] ==
              oldBytes[lastPos + lenF - overlap + i]) {
            s++;
          }
          if (newBytes[scan - lenB + i] == oldBytes[pos - lenB + i]) s--;
          if (s > ss) {
            ss = s;
            lenS = i + 1;
          }
        }
        lenF += lenS - overlap;
        lenB -= lenS;
      }

      final db = Uint8List(lenF);
      for (var i = 0; i < lenF; i++) {
        db[i] = (newBytes[lastScan + i] - oldBytes[lastPos + i]) & 0xFF;
      }
      diff.add(db);
      final extraLen = (scan - lenB) - (lastScan + lenF);
      extra.add(Uint8List.sublistView(
          newBytes, lastScan + lenF, lastScan + lenF + extraLen));

      triple
        ..setInt64(0, lenF, Endian.little)
        ..setInt64(8, extraLen, Endian.little)
        ..setInt64(16, (pos - lenB) - (lastPos + lenF), Endian.little);
      control.add(Uint8List.fromList(triple.buffer.asUint8List()));

      lastScan = scan - lenB;
      lastPos = pos - lenB;
      lastOffset = pos - scan;
    }
  }

  final c = control.finish();
  final d = diff.finish();
  final e = extra.finish();
  final header = DeltaHeader(
    newSize: newSize,
    oldSize: oldSize,
    oldSha256: oldSha256,
    newSha256: newSha256,
    controlLength: c.length,
    diffLength: d.length,
    extraLength: e.length,
  ).encode();
  return (BytesBuilder(copy: false)
        ..add(header)
        ..add(c)
        ..add(d)
        ..add(e))
      .takeBytes();
}

class _Match {
  int pos = 0;
}

/// `qsufsort` of bsdiff 4.3: returns the suffix array I (length old + 1).
Int32List _suffixSort(Uint8List old) {
  final oldSize = old.length;
  final iArr = Int32List(oldSize + 1);
  final vArr = Int32List(oldSize + 1);
  final buckets = List<int>.filled(256, 0);

  for (var i = 0; i < oldSize; i++) {
    buckets[old[i]]++;
  }
  for (var i = 1; i < 256; i++) {
    buckets[i] += buckets[i - 1];
  }
  for (var i = 255; i > 0; i--) {
    buckets[i] = buckets[i - 1];
  }
  buckets[0] = 0;

  for (var i = 0; i < oldSize; i++) {
    iArr[++buckets[old[i]]] = i;
  }
  iArr[0] = oldSize;
  for (var i = 0; i < oldSize; i++) {
    vArr[i] = buckets[old[i]];
  }
  vArr[oldSize] = 0;
  for (var i = 1; i < 256; i++) {
    if (buckets[i] == buckets[i - 1] + 1) iArr[buckets[i]] = -1;
  }
  iArr[0] = -1;

  for (var h = 1; iArr[0] != -(oldSize + 1); h += h) {
    var len = 0;
    var i = 0;
    while (i < oldSize + 1) {
      if (iArr[i] < 0) {
        len -= iArr[i];
        i -= iArr[i];
      } else {
        if (len != 0) iArr[i - len] = -len;
        len = vArr[iArr[i]] + 1 - i;
        _split(iArr, vArr, i, len, h);
        i += len;
        len = 0;
      }
    }
    if (len != 0) iArr[i - len] = -len;
  }

  for (var i = 0; i < oldSize + 1; i++) {
    iArr[vArr[i]] = i;
  }
  return iArr;
}

/// `split` of bsdiff 4.3. The trailing recursion on the upper part is a loop
/// here (same order of operations), so the stack depth only grows with the
/// lower parts.
void _split(Int32List iArr, Int32List vArr, int start, int len, int h) {
  while (true) {
    if (len < 16) {
      int j;
      for (var k = start; k < start + len; k += j) {
        j = 1;
        var x = vArr[iArr[k] + h];
        for (var i = 1; k + i < start + len; i++) {
          final v = vArr[iArr[k + i] + h];
          if (v < x) {
            x = v;
            j = 0;
          }
          if (v == x) {
            final tmp = iArr[k + j];
            iArr[k + j] = iArr[k + i];
            iArr[k + i] = tmp;
            j++;
          }
        }
        for (var i = 0; i < j; i++) {
          vArr[iArr[k + i]] = k + j - 1;
        }
        if (j == 1) iArr[k] = -1;
      }
      return;
    }

    final x = vArr[iArr[start + len ~/ 2] + h];
    var jj = 0, kk = 0;
    for (var i = start; i < start + len; i++) {
      final v = vArr[iArr[i] + h];
      if (v < x) jj++;
      if (v == x) kk++;
    }
    jj += start;
    kk += jj;

    var i = start, j = 0, k = 0;
    while (i < jj) {
      final v = vArr[iArr[i] + h];
      if (v < x) {
        i++;
      } else if (v == x) {
        final tmp = iArr[i];
        iArr[i] = iArr[jj + j];
        iArr[jj + j] = tmp;
        j++;
      } else {
        final tmp = iArr[i];
        iArr[i] = iArr[kk + k];
        iArr[kk + k] = tmp;
        k++;
      }
    }
    while (jj + j < kk) {
      if (vArr[iArr[jj + j] + h] == x) {
        j++;
      } else {
        final tmp = iArr[jj + j];
        iArr[jj + j] = iArr[kk + k];
        iArr[kk + k] = tmp;
        k++;
      }
    }

    if (jj > start) _split(iArr, vArr, start, jj - start, h);
    for (var n = 0; n < kk - jj; n++) {
      vArr[iArr[jj + n]] = kk - 1;
    }
    if (jj == kk - 1) iArr[jj] = -1;

    if (start + len > kk) {
      final upper = start + len - kk;
      start = kk;
      len = upper;
      continue;
    }
    return;
  }
}

int _matchLen(Uint8List old, int oldFrom, Uint8List newData, int newFrom) {
  var i = 0;
  final max = (old.length - oldFrom) < (newData.length - newFrom)
      ? old.length - oldFrom
      : newData.length - newFrom;
  while (i < max && old[oldFrom + i] == newData[newFrom + i]) {
    i++;
  }
  return i;
}

/// `memcmp(old + from, new + newFrom, min(...)) < 0`.
bool _oldLess(Uint8List old, int from, Uint8List newData, int newFrom) {
  final n = (old.length - from) < (newData.length - newFrom)
      ? old.length - from
      : newData.length - newFrom;
  for (var i = 0; i < n; i++) {
    final a = old[from + i], b = newData[newFrom + i];
    if (a != b) return a < b;
  }
  return false;
}

/// `search` of bsdiff 4.3, iterative.
int _search(Int32List iArr, Uint8List old, Uint8List newData, int newFrom,
    int st, int en, _Match out) {
  while (en - st >= 2) {
    final x = st + (en - st) ~/ 2;
    if (_oldLess(old, iArr[x], newData, newFrom)) {
      st = x;
    } else {
      en = x;
    }
  }
  final x = _matchLen(old, iArr[st], newData, newFrom);
  final y = _matchLen(old, iArr[en], newData, newFrom);
  if (x > y) {
    out.pos = iArr[st];
    return x;
  }
  out.pos = iArr[en];
  return y;
}
