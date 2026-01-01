/// Linkable Ring Signatures on Ed25519 (§24.4).
///
/// Construction: MLSAG-style. Signer proves "one of N ring members signed
/// this" while leaking a key image I that is deterministic for (sk, context)
/// so double-signing for the same context is detectable without revealing
/// the signer.
///
/// For a signer at index j with secret scalar a_j and public key P_j:
///   I  = a_j · H_p(context || P_j)
///   For each i ≠ j: sample random c_i, r_i and commit to
///     L_i = r_i · G  + c_i · P_i
///     R_i = r_i · H_p(context || P_i) + c_i · I
///   For i = j: sample random α and commit to
///     L_j = α · G
///     R_j = α · H_p(context || P_j)
///   c_sum = H(message || context || P_1 || … || P_N || L_1 || R_1 || … || L_N || R_N)
///   c_j   = c_sum − Σ_{i ≠ j} c_i   mod L
///   r_j   = α − c_j · a_j           mod L
///
/// Verification recomputes L_i, R_i from (c_i, r_i) and checks
///   H(message || context || ring || {L_i, R_i}) == Σ c_i  mod L.
/// Key-image reuse detection is the caller's responsibility.
library;

import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Fixed sizes per signature slot: 32-byte c_i || 32-byte r_i.
const int _slotBytes = 64;

/// Result of signing: opaque signature blob, plus the key image for the
/// caller's double-spend index.
class RingSignatureResult {
  final Uint8List keyImage;   // 32 bytes, the linkability tag
  final Uint8List signature;  // N * 64 bytes (c_i || r_i per ring member)
  RingSignatureResult({required this.keyImage, required this.signature});
}

class LinkableRingSignature {
  /// Derive the key image for a signer without producing a full signature.
  ///
  /// Uses the same formula as [sign] so the caller can pre-compute the
  /// double-vote tag (e.g. to reject a duplicate locally before broadcasting).
  static Uint8List deriveKeyImage({
    required Uint8List signerSk,
    required Uint8List signerPk,
    required Uint8List context,
  }) {
    final a = SodiumFFI().ed25519ScalarFromSecretKey(signerSk);
    final hp = _hashToPoint(context, signerPk);
    return SodiumFFI().ed25519Scalarmult(a, hp);
  }

  /// Produce a linkable ring signature over [message].
  ///
  /// [ringMembers] MUST include [signerPk] and SHOULD be sorted deterministically
  /// by the caller so both sides agree on the canonical order. [context] is
  /// folded into the hash-to-point and challenge inputs and domain-separates
  /// signatures across polls / contexts.
  ///
  /// When [presetKeyImage] is provided (revoke flow), it overrides the
  /// deterministic derivation. Callers must ensure it matches
  /// [deriveKeyImage] output for the same signer + context.
  static RingSignatureResult sign({
    required Uint8List message,
    required Uint8List context,
    required List<Uint8List> ringMembers,
    required Uint8List signerSk,
    required Uint8List signerPk,
    Uint8List? presetKeyImage,
  }) {
    if (ringMembers.isEmpty) {
      throw ArgumentError('Ring must contain at least one member');
    }
    final sodium = SodiumFFI();

    // Locate signer index in the ring.
    var signerIndex = -1;
    for (var i = 0; i < ringMembers.length; i++) {
      if (_bytesEqual(ringMembers[i], signerPk)) {
        signerIndex = i;
        break;
      }
    }
    if (signerIndex < 0) {
      throw ArgumentError('Signer public key must be present in the ring');
    }

    // Derive scalar and key image.
    final a = sodium.ed25519ScalarFromSecretKey(signerSk);
    final keyImage = presetKeyImage ?? deriveKeyImage(
      signerSk: signerSk,
      signerPk: signerPk,
      context: context,
    );

    final n = ringMembers.length;

    // Precompute H_p for every ring member.
    final hps = <Uint8List>[
      for (final pk in ringMembers) _hashToPoint(context, pk),
    ];

    // Allocate per-slot scalars. For i ≠ j we pick random c_i, r_i.
    // For i = j we pick random α and derive c_j, r_j after computing the
    // aggregate challenge.
    final cs = List<Uint8List>.filled(n, Uint8List(32));
    final rs = List<Uint8List>.filled(n, Uint8List(32));
    final ls = List<Uint8List>.filled(n, Uint8List(32));
    final rsPoints = List<Uint8List>.filled(n, Uint8List(32));

    // Signer's random nonce α.
    final alpha = sodium.ed25519ScalarRandom();

    for (var i = 0; i < n; i++) {
      if (i == signerIndex) {
        // L_j = α · G ; R_j = α · H_p(P_j)
        ls[i] = sodium.ed25519ScalarmultBase(alpha);
        rsPoints[i] = sodium.ed25519Scalarmult(alpha, hps[i]);
      } else {
        final ci = sodium.ed25519ScalarRandom();
        final ri = sodium.ed25519ScalarRandom();
        cs[i] = ci;
        rs[i] = ri;
        // L_i = r_i · G + c_i · P_i
        final riG = sodium.ed25519ScalarmultBase(ri);
        final ciPi = sodium.ed25519Scalarmult(ci, ringMembers[i]);
        ls[i] = sodium.ed25519Add(riG, ciPi);
        // R_i = r_i · H_p(P_i) + c_i · I
        final riHp = sodium.ed25519Scalarmult(ri, hps[i]);
        final ciI = sodium.ed25519Scalarmult(ci, keyImage);
        rsPoints[i] = sodium.ed25519Add(riHp, ciI);
      }
    }

    // Aggregate challenge:
    //   c_sum = H(message || context || keyImage || ring_i || L_i || R_i…)  mod L
    final cSum = _challenge(
      message: message,
      context: context,
      keyImage: keyImage,
      ring: ringMembers,
      lPoints: ls,
      rPoints: rsPoints,
    );

    // Sum of all c_i for i ≠ signerIndex.
    var summed = Uint8List(32);
    for (var i = 0; i < n; i++) {
      if (i == signerIndex) continue;
      summed = sodium.ed25519ScalarAdd(summed, cs[i]);
    }
    final cJ = sodium.ed25519ScalarSub(cSum, summed);
    final cJa = sodium.ed25519ScalarMul(cJ, a);
    final rJ = sodium.ed25519ScalarSub(alpha, cJa);
    cs[signerIndex] = cJ;
    rs[signerIndex] = rJ;

    // Serialise signature as c_1||r_1 || c_2||r_2 || ... || c_n||r_n.
    final sig = Uint8List(n * _slotBytes);
    for (var i = 0; i < n; i++) {
      sig.setRange(i * _slotBytes, i * _slotBytes + 32, cs[i]);
      sig.setRange(i * _slotBytes + 32, i * _slotBytes + 64, rs[i]);
    }

    return RingSignatureResult(keyImage: keyImage, signature: sig);
  }

  /// Verify a ring signature. Returns true iff the aggregate challenge
  /// recomputed from (L_i, R_i) matches Σ c_i. Key-image reuse is NOT
  /// checked here — callers must track seen key images per context.
  static bool verify({
    required Uint8List message,
    required Uint8List context,
    required Uint8List keyImage,
    required List<Uint8List> ringMembers,
    required Uint8List signature,
  }) {
    if (ringMembers.isEmpty) return false;
    if (signature.length != ringMembers.length * _slotBytes) return false;
    if (keyImage.length != 32) return false;
    final sodium = SodiumFFI();
    if (!sodium.ed25519IsValidPoint(keyImage)) return false;
    for (final pk in ringMembers) {
      if (pk.length != 32 || !sodium.ed25519IsValidPoint(pk)) return false;
    }

    final n = ringMembers.length;
    final hps = <Uint8List>[
      for (final pk in ringMembers) _hashToPoint(context, pk),
    ];

    final cs = <Uint8List>[];
    final rs = <Uint8List>[];
    for (var i = 0; i < n; i++) {
      cs.add(Uint8List.fromList(
          signature.sublist(i * _slotBytes, i * _slotBytes + 32)));
      rs.add(Uint8List.fromList(
          signature.sublist(i * _slotBytes + 32, i * _slotBytes + 64)));
    }

    final ls = <Uint8List>[];
    final rsPoints = <Uint8List>[];
    for (var i = 0; i < n; i++) {
      try {
        final riG = sodium.ed25519ScalarmultBase(rs[i]);
        final ciPi = sodium.ed25519Scalarmult(cs[i], ringMembers[i]);
        ls.add(sodium.ed25519Add(riG, ciPi));

        final riHp = sodium.ed25519Scalarmult(rs[i], hps[i]);
        final ciI = sodium.ed25519Scalarmult(cs[i], keyImage);
        rsPoints.add(sodium.ed25519Add(riHp, ciI));
      } catch (_) {
        return false;
      }
    }

    final cSum = _challenge(
      message: message,
      context: context,
      keyImage: keyImage,
      ring: ringMembers,
      lPoints: ls,
      rPoints: rsPoints,
    );

    var summed = Uint8List(32);
    for (var i = 0; i < n; i++) {
      summed = sodium.ed25519ScalarAdd(summed, cs[i]);
    }
    return _bytesEqual(summed, cSum);
  }

  // ── internals ─────────────────────────────────────────────────────────

  /// Hash a (context, pk) pair to an Ed25519 point.
  ///
  /// Using SHA-512 over "cleona-ringsig-v1" || context || pk and folding the
  /// first 32 bytes via crypto_core_ed25519_from_uniform yields a uniformly
  /// distributed curve point. The domain-separation prefix prevents
  /// cross-protocol collisions.
  static Uint8List _hashToPoint(Uint8List context, Uint8List pk) {
    final buf = BytesBuilder()
      ..add('cleona-ringsig-v1\u0000hashpoint'.codeUnits)
      ..add(context)
      ..add(pk);
    final h = SodiumFFI().sha512(buf.toBytes());
    final uniform = Uint8List.fromList(h.sublist(0, 32));
    return SodiumFFI().ed25519FromUniform(uniform);
  }

  /// Aggregate challenge scalar in [0, L).
  static Uint8List _challenge({
    required Uint8List message,
    required Uint8List context,
    required Uint8List keyImage,
    required List<Uint8List> ring,
    required List<Uint8List> lPoints,
    required List<Uint8List> rPoints,
  }) {
    final buf = BytesBuilder()
      ..add('cleona-ringsig-v1\u0000challenge'.codeUnits)
      ..add(context)
      ..add(_uint32LE(message.length))
      ..add(message)
      ..add(keyImage)
      ..add(_uint32LE(ring.length));
    for (final pk in ring) {
      buf.add(pk);
    }
    for (final l in lPoints) {
      buf.add(l);
    }
    for (final r in rPoints) {
      buf.add(r);
    }
    final h = SodiumFFI().sha512(buf.toBytes());
    return SodiumFFI().ed25519ScalarReduce(h);
  }

  static Uint8List _uint32LE(int value) {
    final b = Uint8List(4);
    b[0] = value & 0xff;
    b[1] = (value >> 8) & 0xff;
    b[2] = (value >> 16) & 0xff;
    b[3] = (value >> 24) & 0xff;
    return b;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
