/// Minimal secp256k1 BIP-340 Schnorr signature implementation in pure Dart.
///
/// Used exclusively for Nostr event signing (throwaway keys, not
/// performance-critical). No native dependency — runs on all platforms.
///
/// References:
///   BIP-340: https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki
///   secp256k1: https://www.secg.org/sec2-v2.pdf §2.4.1
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

// ---------------------------------------------------------------------------
// secp256k1 curve parameters
// ---------------------------------------------------------------------------

final BigInt _p = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
    radix: 16);

final BigInt _n = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141',
    radix: 16);

final BigInt _gx = BigInt.parse(
    '79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798',
    radix: 16);

final BigInt _gy = BigInt.parse(
    '483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8',
    radix: 16);

// ---------------------------------------------------------------------------
// Modular arithmetic
// ---------------------------------------------------------------------------

BigInt _mod(BigInt a, BigInt m) {
  final r = a % m;
  return r.isNegative ? r + m : r;
}

BigInt _modInv(BigInt a, BigInt m) => a.modPow(m - BigInt.two, m);

BigInt _modSqrt(BigInt a, BigInt p) {
  // p ≡ 3 (mod 4) for secp256k1
  return a.modPow((p + BigInt.one) >> 2, p);
}

// ---------------------------------------------------------------------------
// Affine point operations on secp256k1
// ---------------------------------------------------------------------------

class _Point {
  final BigInt x;
  final BigInt y;
  const _Point(this.x, this.y);

  static final _Point infinity = _Point._inf();
  _Point._inf() : x = BigInt.zero, y = BigInt.zero;
  bool get isInfinity => identical(this, infinity);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _Point && x == other.x && y == other.y);

  @override
  int get hashCode => Object.hash(x, y);
}

_Point _pointAdd(_Point p1, _Point p2) {
  if (p1.isInfinity) return p2;
  if (p2.isInfinity) return p1;
  if (p1.x == p2.x && p1.y != p2.y) return _Point.infinity;

  BigInt lam;
  if (p1.x == p2.x && p1.y == p2.y) {
    lam = _mod(
        BigInt.from(3) * p1.x * p1.x * _modInv(BigInt.two * p1.y, _p), _p);
  } else {
    lam = _mod((p2.y - p1.y) * _modInv(p2.x - p1.x, _p), _p);
  }

  final x3 = _mod(lam * lam - p1.x - p2.x, _p);
  final y3 = _mod(lam * (p1.x - x3) - p1.y, _p);
  return _Point(x3, y3);
}

_Point _pointMul(_Point point, BigInt scalar) {
  var r = _Point.infinity;
  var a = point;
  var s = _mod(scalar, _n);
  while (s > BigInt.zero) {
    if (s.isOdd) r = _pointAdd(r, a);
    a = _pointAdd(a, a);
    s >>= 1;
  }
  return r;
}

final _Point _g = _Point(_gx, _gy);

// ---------------------------------------------------------------------------
// Byte conversion helpers
// ---------------------------------------------------------------------------

Uint8List _bigIntToBytes32(BigInt v) {
  final hex = v.toRadixString(16).padLeft(64, '0');
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

BigInt _bytesToBigInt(Uint8List bytes) {
  final hex =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return BigInt.parse(hex, radix: 16);
}

Uint8List _taggedHash(String tag, Uint8List msg) {
  final sodium = SodiumFFI();
  final tagHash = sodium.sha256(Uint8List.fromList(tag.codeUnits));
  final bb = BytesBuilder(copy: false)
    ..add(tagHash)
    ..add(tagHash)
    ..add(msg);
  return sodium.sha256(bb.toBytes());
}

Uint8List _xonly(_Point p) => _bigIntToBytes32(p.x);

// ---------------------------------------------------------------------------
// BIP-340 Schnorr API
// ---------------------------------------------------------------------------

/// Generates a random secp256k1 keypair.
///
/// Returns (secretKey: 32 bytes, publicKey: 32 bytes x-only).
({Uint8List secretKey, Uint8List publicKey}) generateSecp256k1Keypair() {
  final sodium = SodiumFFI();
  Uint8List sk;
  BigInt d;
  do {
    sk = sodium.randomBytes(32);
    d = _bytesToBigInt(sk);
  } while (d == BigInt.zero || d >= _n);

  final p = _pointMul(_g, d);
  // BIP-340: negate d if P.y is odd
  final dFinal = p.y.isOdd ? _n - d : d;
  return (
    secretKey: _bigIntToBytes32(dFinal),
    publicKey: _xonly(p),
  );
}

/// BIP-340 Schnorr sign.
///
/// [secretKey] — 32-byte secret key (already negated if needed by [generateSecp256k1Keypair]).
/// [message] — 32-byte message (typically a SHA-256 hash).
/// Returns 64-byte signature.
Uint8List schnorrSign(Uint8List secretKey, Uint8List message) {
  if (secretKey.length != 32) {
    throw ArgumentError('schnorrSign: secretKey must be 32 bytes');
  }
  if (message.length != 32) {
    throw ArgumentError('schnorrSign: message must be 32 bytes');
  }

  final d = _bytesToBigInt(secretKey);
  final p = _pointMul(_g, d);
  final pk = _xonly(p);

  // aux_rand: deterministic from sk for reproducibility (BIP-340 allows this)
  final aux = SodiumFFI().randomBytes(32);
  final t = _taggedHash('BIP0340/aux', aux);
  final tXor = Uint8List(32);
  final dBytes = _bigIntToBytes32(d);
  for (var i = 0; i < 32; i++) {
    tXor[i] = dBytes[i] ^ t[i];
  }

  final randBb = BytesBuilder(copy: false)
    ..add(tXor)
    ..add(pk)
    ..add(message);
  final k0 = _mod(_bytesToBigInt(_taggedHash('BIP0340/nonce', randBb.toBytes())), _n);
  if (k0 == BigInt.zero) {
    throw StateError('schnorrSign: k0 == 0 (astronomically unlikely)');
  }

  final r = _pointMul(_g, k0);
  final k = r.y.isOdd ? _n - k0 : k0;

  final eBb = BytesBuilder(copy: false)
    ..add(_xonly(r))
    ..add(pk)
    ..add(message);
  final e = _mod(_bytesToBigInt(_taggedHash('BIP0340/challenge', eBb.toBytes())), _n);

  final sig = Uint8List(64);
  sig.setRange(0, 32, _xonly(r));
  sig.setRange(32, 64, _bigIntToBytes32(_mod(k + e * d, _n)));
  return sig;
}

/// BIP-340 Schnorr verify.
///
/// [publicKey] — 32-byte x-only public key.
/// [message] — 32-byte message.
/// [signature] — 64-byte signature.
bool schnorrVerify(Uint8List publicKey, Uint8List message, Uint8List signature) {
  if (publicKey.length != 32 || message.length != 32 || signature.length != 64) {
    return false;
  }

  final px = _bytesToBigInt(publicKey);
  if (px >= _p) return false;

  final ySquared = _mod(px * px * px + BigInt.from(7), _p);
  final py = _modSqrt(ySquared, _p);
  if (_mod(py * py, _p) != ySquared) return false;
  final pPoint = _Point(px, py.isEven ? py : _p - py);

  final rx = _bytesToBigInt(Uint8List.sublistView(signature, 0, 32));
  final s = _bytesToBigInt(Uint8List.sublistView(signature, 32, 64));
  if (rx >= _p || s >= _n) return false;

  final eBb = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(signature, 0, 32))
    ..add(publicKey)
    ..add(message);
  final e = _mod(_bytesToBigInt(_taggedHash('BIP0340/challenge', eBb.toBytes())), _n);

  final r = _pointAdd(_pointMul(_g, s), _pointMul(pPoint, _n - e));
  if (r.isInfinity) return false;
  if (r.y.isOdd) return false;
  if (r.x != rx) return false;

  return true;
}
