// D3 Admission-PoW (Architecture §13.1.2 / §13.1.8) — insider Sybil cost anchor.
//
// Static, reusable proof per device keypair: an 8-byte nonce, such that
// SHA-256("cleona-id-pow-v1" || device_ed25519_pk || nonce) has at least
// [difficultyBits] leading zero bits. Computed once at keypair generation
// (isolate), persisted in device_keys.bin (v3 container), travels as
// PeerInfoProto.device_id_pow_nonce with the pubkey it certifies.
//
// Bound to the PUBKEY, not to the device ID — survives secret rotation.
// The recipient additionally checks SHA-256(secret || pk) == senderDeviceId
// (binding to the wire identity, on the caller side in cleona_node).
//
// Phase 1 (observe-only): the verification result lands as
// PeerInfo.idPowVerified in the routing table + network stats; nothing is
// gated. Phase-2 role gating comes behind minRequiredVersion (§19.5.7).

import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/crypto/proof_of_work.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

class AdmissionPow {
  /// Production difficulty (~4M hashes, 50-100ms desktop, <=2s mobile).
  static const int difficultyBits = 22;

  /// Test-Preset (Unit-Tests grinden in Mikrosekunden).
  static const int testDifficultyBits = 8;

  static const String _context = 'cleona-id-pow-v1';

  /// Nonce length on the line (8 bytes little-endian).
  static const int nonceLength = 8;

  static Uint8List _buildBuffer(Uint8List deviceEd25519Pk) {
    final ctx = _context.codeUnits;
    final buf = Uint8List(ctx.length + deviceEd25519Pk.length + nonceLength);
    buf.setRange(0, ctx.length, ctx);
    buf.setRange(ctx.length, ctx.length + deviceEd25519Pk.length, deviceEd25519Pk);
    return buf;
  }

  /// Grind synchronously. Only for tests/isolate body — the production
  /// path uses [computeAsync].
  static Uint8List compute(Uint8List deviceEd25519Pk,
      {int difficulty = difficultyBits}) {
    final sodium = SodiumFFI();
    final buf = _buildBuffer(deviceEd25519Pk);
    final nonceView = ByteData.sublistView(buf, buf.length - nonceLength);
    for (int nonce = 0;; nonce++) {
      nonceView.setUint64(0, nonce, Endian.little);
      final hash = sodium.sha256(buf);
      if (ProofOfWork.hasLeadingZeroBits(hash, difficulty)) {
        return Uint8List.fromList(
            buf.sublist(buf.length - nonceLength));
      }
    }
  }

  /// Grind in the isolate (pattern like ProofOfWork.computeAsync); fallback
  /// synchronous if FFI init fails in the isolate (Android).
  static Future<Uint8List> computeAsync(Uint8List deviceEd25519Pk,
      {int difficulty = difficultyBits}) async {
    try {
      return await Isolate.run(() {
        SodiumFFI(); // Init FFI in isolate
        return AdmissionPow.compute(deviceEd25519Pk, difficulty: difficulty);
      });
    } catch (_) {
      return compute(deviceEd25519Pk, difficulty: difficulty);
    }
  }

  /// Verify [nonce] against [deviceEd25519Pk] — exactly one SHA-256.
  static bool verify(Uint8List deviceEd25519Pk, Uint8List nonce,
      {int difficulty = difficultyBits}) {
    if (nonce.length != nonceLength) return false;
    final buf = _buildBuffer(deviceEd25519Pk);
    buf.setRange(buf.length - nonceLength, buf.length, nonce);
    final hash = SodiumFFI().sha256(buf);
    return ProofOfWork.hasLeadingZeroBits(hash, difficulty);
  }
}
