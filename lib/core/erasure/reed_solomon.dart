import 'dart:math';
import 'dart:typed_data';
import 'package:cleona/core/network/clogger.dart';

/// Reed-Solomon erasure coding.
/// Default: N=10 total fragments, K=7 data fragments (3 parity).
///
/// Uses a Cauchy-matrix encoding in GF(256) with the AES irreducible polynomial
/// (x^8 + x^4 + x^3 + x + 1). Cauchy matrices guarantee the MDS property:
/// any K of N fragments suffice to reconstruct the original data.
/// Decoding uses Gaussian elimination to invert the encoding sub-matrix.
class ReedSolomon {
  static const int defaultN = 10;
  static const int defaultK = 7;
  static const int defaultM = 3; // N - K = parity fragments

  static ReedSolomon? _instance;
  final CLogger _log = CLogger.get('erasure');

  factory ReedSolomon() {
    _instance ??= ReedSolomon._();
    return _instance!;
  }

  ReedSolomon._() {
    _log.info('Reed-Solomon initialized (K=$defaultK, M=$defaultM, N=$defaultN)');
  }

  /// Encode data into N fragments (K data + M parity).
  List<Uint8List> encode(Uint8List data) {
    // Pad data to be divisible by K
    final paddedLen = ((data.length + defaultK - 1) ~/ defaultK) * defaultK;
    final padded = Uint8List(paddedLen);
    padded.setRange(0, data.length, data);

    final fragSize = paddedLen ~/ defaultK;
    final fragments = <Uint8List>[];

    // K data fragments
    for (var i = 0; i < defaultK; i++) {
      fragments.add(Uint8List.fromList(padded.sublist(i * fragSize, (i + 1) * fragSize)));
    }

    // M parity fragments using Cauchy-matrix coefficients in GF(256)
    for (var p = 0; p < defaultM; p++) {
      final parity = Uint8List(fragSize);
      for (var i = 0; i < defaultK; i++) {
        final coeff = _cauchyCoeff(p, i);
        for (var j = 0; j < fragSize; j++) {
          parity[j] ^= _gfMul(fragments[i][j], coeff);
        }
      }
      fragments.add(parity);
    }

    return fragments;
  }

  /// Reconstruct original data from K or more fragments.
  /// fragments: map of fragmentIndex -> fragmentData (at least K entries needed).
  Uint8List decode(Map<int, Uint8List> fragments, int originalSize) {
    if (fragments.length < defaultK) {
      throw StateError('Need at least $defaultK fragments, got ${fragments.length}');
    }

    // Check if all K data fragments are present — fast path
    final dataFragments = <int, Uint8List>{};
    for (var i = 0; i < defaultK; i++) {
      if (fragments.containsKey(i)) {
        dataFragments[i] = fragments[i]!;
      }
    }

    if (dataFragments.length == defaultK) {
      final fragSize = dataFragments.values.first.length;
      final result = Uint8List(fragSize * defaultK);
      for (var i = 0; i < defaultK; i++) {
        result.setRange(i * fragSize, (i + 1) * fragSize, dataFragments[i]!);
      }
      return Uint8List.fromList(result.sublist(0, originalSize));
    }

    // Missing data fragments — reconstruct via Gaussian elimination in GF(256).
    // Build KxK sub-matrix from the encoding matrix rows of available fragments,
    // invert it, and multiply by available fragment data.
    final fragSize = fragments.values.first.length;

    // Pick exactly K available fragment indices (prefer data fragments first)
    final available = <int>[];
    for (var i = 0; i < defaultK; i++) {
      if (fragments.containsKey(i)) available.add(i);
    }
    for (var p = 0; p < defaultM && available.length < defaultK; p++) {
      if (fragments.containsKey(defaultK + p)) available.add(defaultK + p);
    }

    if (available.length < defaultK) {
      throw StateError(
          'Need at least $defaultK fragments, got ${available.length}');
    }

    // Build KxK encoding sub-matrix for the available rows.
    // Full encoding matrix (NxK): rows 0..K-1 = identity, rows K..N-1 = parity coefficients.
    final matrix =
        List.generate(defaultK, (_) => List.filled(defaultK, 0));
    for (var r = 0; r < defaultK; r++) {
      final rowIdx = available[r];
      if (rowIdx < defaultK) {
        matrix[r][rowIdx] = 1;
      } else {
        final p = rowIdx - defaultK;
        for (var c = 0; c < defaultK; c++) {
          matrix[r][c] = _cauchyCoeff(p, c);
        }
      }
    }

    // Gaussian elimination on augmented matrix [matrix | I] → [I | inverse]
    final w = 2 * defaultK;
    final aug = List.generate(
        defaultK, (r) => List.filled(w, 0));
    for (var r = 0; r < defaultK; r++) {
      for (var c = 0; c < defaultK; c++) {
        aug[r][c] = matrix[r][c];
      }
      aug[r][defaultK + r] = 1;
    }

    for (var col = 0; col < defaultK; col++) {
      // Find pivot row
      var pivotRow = -1;
      for (var r = col; r < defaultK; r++) {
        if (aug[r][col] != 0) {
          pivotRow = r;
          break;
        }
      }
      if (pivotRow < 0) {
        throw StateError('Encoding matrix is singular — cannot decode');
      }
      if (pivotRow != col) {
        final tmp = aug[col];
        aug[col] = aug[pivotRow];
        aug[pivotRow] = tmp;
      }

      // Scale pivot row so pivot element = 1
      final pivotInv = _gfInv(aug[col][col]);
      for (var c = 0; c < w; c++) {
        aug[col][c] = _gfMul(aug[col][c], pivotInv);
      }

      // Eliminate this column in all other rows
      for (var r = 0; r < defaultK; r++) {
        if (r == col) continue;
        final factor = aug[r][col];
        if (factor == 0) continue;
        for (var c = 0; c < w; c++) {
          aug[r][c] ^= _gfMul(factor, aug[col][c]);
        }
      }
    }

    // Extract inverse matrix (right half of augmented)
    final inv = List.generate(
        defaultK, (r) => List.generate(defaultK, (c) => aug[r][defaultK + c]));

    // Multiply inverse by available fragment data → original K data fragments
    final result = Uint8List(fragSize * defaultK);
    for (var j = 0; j < fragSize; j++) {
      for (var d = 0; d < defaultK; d++) {
        var val = 0;
        for (var k = 0; k < defaultK; k++) {
          val ^= _gfMul(inv[d][k], fragments[available[k]]![j]);
        }
        result[d * fragSize + j] = val;
      }
    }
    return Uint8List.fromList(result.sublist(0, originalSize));
  }

  /// GF(256) multiplication using AES polynomial (x^8 + x^4 + x^3 + x + 1).
  static int _gfMul(int a, int b) {
    a &= 0xFF;
    b &= 0xFF;
    var result = 0;
    for (var i = 0; i < 8; i++) {
      if ((b & 1) != 0) result ^= a;
      final hi = a & 0x80;
      a = (a << 1) & 0xFF;
      if (hi != 0) a ^= 0x1B; // AES irreducible polynomial
      b >>= 1;
    }
    return result;
  }

  /// GF(256) multiplicative inverse via brute force (small field).
  static int _gfInv(int a) {
    if (a == 0) return 0;
    for (var i = 1; i < 256; i++) {
      if (_gfMul(a, i) == 1) return i;
    }
    return 0;
  }

  /// Cauchy matrix coefficient: C[p][i] = 1 / (x_p XOR y_i) in GF(256).
  /// x and y are disjoint sets of distinct elements, guaranteeing every
  /// square sub-matrix is non-singular (MDS property).
  static const _cauchyX = [1, 2, 3]; // M=3 parity rows
  static const _cauchyY = [4, 5, 6, 7, 8, 9, 10]; // K=7 data columns

  static int _cauchyCoeff(int p, int i) {
    return _gfInv(_cauchyX[p] ^ _cauchyY[i]);
  }

  /// Threshold above which encodeStreaming should be used (1 MB).
  static const int streamingThreshold = 1024 * 1024;

  /// Default window size for streaming encoding (64 KB).
  static const int defaultWindowSize = 64 * 1024;

  /// Streaming encode for large data: processes in windows to limit peak RAM.
  ///
  /// Instead of loading all N fragments into memory at once, processes the
  /// data in windows of [windowSize] bytes. Each window produces K+M fragments
  /// which are appended to per-fragment BytesBuilders.
  ///
  /// Peak RAM: ~K * windowSize * 2 (current window + fragments) instead of
  /// ~N * dataLength for the monolithic encode().
  ///
  /// The output is identical in structure to encode() — N fragments that can
  /// be decoded with decode() or decodeStreaming().
  List<Uint8List> encodeStreaming(Uint8List data, {int windowSize = defaultWindowSize}) {
    // For small data, just use regular encode
    if (data.length <= windowSize * defaultK) {
      return encode(data);
    }

    final windowDataSize = windowSize * defaultK;
    final totalWindows = (data.length + windowDataSize - 1) ~/ windowDataSize;
    final builders = List.generate(defaultN, (_) => BytesBuilder(copy: false));

    for (var w = 0; w < totalWindows; w++) {
      final windowStart = w * windowDataSize;
      final windowEnd = min(windowStart + windowDataSize, data.length);
      final windowData = Uint8List.fromList(data.sublist(windowStart, windowEnd));

      // Encode this window (small: at most K * windowSize bytes)
      final windowFragments = encode(windowData);

      for (var i = 0; i < defaultN; i++) {
        builders[i].add(windowFragments[i]);
      }
    }

    final result = <Uint8List>[];
    for (final builder in builders) {
      result.add(builder.toBytes());
    }
    _log.debug('Streaming encode: ${data.length}B → $totalWindows windows, '
        '${result.length} fragments');
    return result;
  }

  /// Streaming decode: reconstructs from windowed fragments.
  ///
  /// Fragments produced by encodeStreaming() contain concatenated window chunks.
  /// This method splits them back into per-window fragments, decodes each window,
  /// and concatenates the results.
  Uint8List decodeStreaming(
    Map<int, Uint8List> fragments,
    int originalSize, {
    int windowSize = defaultWindowSize,
  }) {
    if (fragments.length < defaultK) {
      throw StateError('Need at least $defaultK fragments, got ${fragments.length}');
    }

    // Determine window structure from fragment sizes
    final windowDataSize = windowSize * defaultK;
    final totalWindows = (originalSize + windowDataSize - 1) ~/ windowDataSize;

    // For single-window data, use regular decode
    if (totalWindows <= 1) {
      return decode(fragments, originalSize);
    }

    // Pre-compute per-window fragment sizes and cumulative offsets
    final fragSizes = <int>[];
    final offsets = <int>[];
    var cumulativeOffset = 0;
    var remaining = originalSize;

    for (var w = 0; w < totalWindows; w++) {
      final thisWindowDataSize = min(windowDataSize, remaining);
      final paddedLen = ((thisWindowDataSize + defaultK - 1) ~/ defaultK) * defaultK;
      final fragSize = paddedLen ~/ defaultK;
      fragSizes.add(fragSize);
      offsets.add(cumulativeOffset);
      cumulativeOffset += fragSize;
      remaining -= thisWindowDataSize;
    }

    // Decode each window
    final result = BytesBuilder(copy: false);
    remaining = originalSize;

    for (var w = 0; w < totalWindows; w++) {
      final thisWindowDataSize = min(windowDataSize, remaining);
      final fragSize = fragSizes[w];
      final offset = offsets[w];

      // Extract per-window fragments at the correct offset
      final windowFragments = <int, Uint8List>{};
      for (final entry in fragments.entries) {
        if (offset + fragSize <= entry.value.length) {
          windowFragments[entry.key] = Uint8List.fromList(
            entry.value.sublist(offset, offset + fragSize),
          );
        } else if (offset < entry.value.length) {
          windowFragments[entry.key] = Uint8List.fromList(
            entry.value.sublist(offset),
          );
        }
      }

      if (windowFragments.length < defaultK) {
        throw StateError('Window $w: need $defaultK fragments, got ${windowFragments.length}');
      }

      final decoded = decode(windowFragments, thisWindowDataSize);
      result.add(decoded);
      remaining -= decoded.length;
    }

    final bytes = result.toBytes();
    return Uint8List.fromList(bytes.sublist(0, originalSize));
  }

  void dispose() {}
}
