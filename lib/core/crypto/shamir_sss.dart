import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Shamir's Secret Sharing over GF(256).
///
/// Splits a secret (arbitrary bytes) into N shares with threshold K.
/// Any K shares can reconstruct the secret, fewer reveal nothing.
///
/// Arithmetic in GF(256) with irreducible polynomial 0x11B (AES field).
/// Share format: [1-byte index (1-based)][secret.length bytes share data]
class ShamirSSS {
  /// Default: 5 shares, threshold 3.
  static const int defaultN = 5;
  static const int defaultK = 3;

  final SodiumFFI _sodium = SodiumFFI();

  /// Split a secret into [n] shares with threshold [k].
  /// Returns a list of n shares, each is [1 + secret.length] bytes.
  /// Share format: [index_byte][share_data...]
  List<Uint8List> split(Uint8List secret, {int n = defaultN, int k = defaultK}) {
    if (n < 2 || n > 255) throw ArgumentError('n must be 2..255');
    if (k < 2 || k > n) throw ArgumentError('k must be 2..n');
    if (secret.isEmpty) throw ArgumentError('Secret must not be empty');

    // For each byte of the secret, generate a random polynomial of degree k-1
    // and evaluate it at x=1..n to produce n shares.
    final shares = List.generate(n, (_) => Uint8List(1 + secret.length));

    // Set share indices (1-based)
    for (var i = 0; i < n; i++) {
      shares[i][0] = i + 1;
    }

    // For each byte of the secret
    for (var byteIdx = 0; byteIdx < secret.length; byteIdx++) {
      // Polynomial coefficients: a[0] = secret byte, a[1..k-1] = random
      final coeffs = Uint8List(k);
      coeffs[0] = secret[byteIdx];
      final randomCoeffs = _sodium.randomBytes(k - 1);
      for (var j = 1; j < k; j++) {
        coeffs[j] = randomCoeffs[j - 1];
      }

      // Evaluate polynomial at x=1..n
      for (var i = 0; i < n; i++) {
        final x = i + 1; // 1-based
        shares[i][1 + byteIdx] = _evalPoly(coeffs, x);
      }
    }

    return shares;
  }

  /// Reconstruct the secret from [k] or more shares.
  /// Shares must have the same length and valid 1-based indices.
  Uint8List reconstruct(List<Uint8List> shares) {
    if (shares.length < 2) throw ArgumentError('Need at least 2 shares');

    final shareLen = shares[0].length;
    if (shareLen < 2) throw ArgumentError('Invalid share length');
    for (final s in shares) {
      if (s.length != shareLen) throw ArgumentError('All shares must have same length');
    }

    final secretLen = shareLen - 1;
    final secret = Uint8List(secretLen);

    // Extract x-coordinates (indices) and y-values
    final xs = shares.map((s) => s[0]).toList();

    // Check for duplicate indices
    if (xs.toSet().length != xs.length) {
      throw ArgumentError('Duplicate share indices');
    }

    // For each byte position, perform Lagrange interpolation at x=0
    for (var byteIdx = 0; byteIdx < secretLen; byteIdx++) {
      final ys = shares.map((s) => s[1 + byteIdx]).toList();
      secret[byteIdx] = _lagrangeInterpolate(xs, ys, 0);
    }

    return secret;
  }

  /// Evaluate polynomial with [coeffs] at point [x] in GF(256).
  /// coeffs[0] + coeffs[1]*x + coeffs[2]*x^2 + ...
  int _evalPoly(Uint8List coeffs, int x) {
    var result = 0;
    var xPow = 1; // x^0 = 1
    for (var i = 0; i < coeffs.length; i++) {
      result = _gfAdd(result, _gfMul(coeffs[i], xPow));
      xPow = _gfMul(xPow, x);
    }
    return result;
  }

  /// Lagrange interpolation at point [x] in GF(256).
  int _lagrangeInterpolate(List<int> xs, List<int> ys, int x) {
    final k = xs.length;
    var result = 0;

    for (var i = 0; i < k; i++) {
      var num = 1;
      var den = 1;
      for (var j = 0; j < k; j++) {
        if (i == j) continue;
        num = _gfMul(num, _gfAdd(x, xs[j])); // (x - x_j) = (x + x_j) in GF(256)
        den = _gfMul(den, _gfAdd(xs[i], xs[j])); // (x_i - x_j) = (x_i + x_j)
      }
      // Lagrange basis: l_i = num / den
      final basis = _gfMul(num, _gfInv(den));
      result = _gfAdd(result, _gfMul(ys[i], basis));
    }

    return result;
  }

  // ── GF(256) Arithmetic ──────────────────────────────────────────────

  /// Addition in GF(256) = XOR
  static int _gfAdd(int a, int b) => a ^ b;

  /// Multiplication in GF(256) with irreducible polynomial 0x11B.
  static int _gfMul(int a, int b) {
    var result = 0;
    var aa = a;
    var bb = b;
    for (var i = 0; i < 8; i++) {
      if (bb & 1 != 0) {
        result ^= aa;
      }
      final carry = aa & 0x80;
      aa = (aa << 1) & 0xFF;
      if (carry != 0) {
        aa ^= 0x1B; // Reduce by x^8 + x^4 + x^3 + x + 1
      }
      bb >>= 1;
    }
    return result;
  }

  /// Multiplicative inverse in GF(256) via extended Euclidean or Fermat.
  /// a^254 = a^(-1) in GF(256) since a^255 = 1 for a != 0.
  static int _gfInv(int a) {
    if (a == 0) throw ArgumentError('Cannot invert 0 in GF(256)');
    // Use repeated squaring: a^254 = a^(11111110_2)
    var result = a;
    for (var i = 0; i < 6; i++) {
      result = _gfMul(result, result); // square
      result = _gfMul(result, a); // multiply by a
    }
    result = _gfMul(result, result); // final square (bit 0 is 0 in 254)
    return result;
  }
}
