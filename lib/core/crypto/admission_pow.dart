// D3 Admission-PoW (Architektur §13.1.2 / §13.1.8) — Insider-Sybil-Kostenanker.
//
// Statischer, wiederverwendbarer Beweis pro Device-Keypair: eine 8-Byte-Nonce,
// sodass SHA-256("cleona-id-pow-v1" || device_ed25519_pk || nonce) mindestens
// [difficultyBits] fuehrende Nullbits hat. Einmalig bei Keypair-Erzeugung
// berechnet (Isolate), in device_keys.bin (v3-Container) persistiert, reist
// als PeerInfoProto.device_id_pow_nonce mit dem Pubkey, den er zertifiziert.
//
// An den PUBKEY gebunden, nicht an die Device-ID — ueberlebt Secret-Rotation.
// Der Empfaenger prueft zusaetzlich SHA-256(secret || pk) == senderDeviceId
// (Binding an die Wire-Identitaet, Aufrufer-seitig in cleona_node).
//
// Phase 1 (observe-only): Verifikationsergebnis landet als
// PeerInfo.idPowVerified in der Routing-Table + Network-Stats; nichts wird
// gegated. Phase-2-Rollen-Gating kommt hinter minRequiredVersion (§19.5.7).

import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/crypto/proof_of_work.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

class AdmissionPow {
  /// Produktions-Schwierigkeit (~4M Hashes, 50-100ms Desktop, <=2s Mobile).
  static const int difficultyBits = 22;

  /// Test-Preset (Unit-Tests grinden in Mikrosekunden).
  static const int testDifficultyBits = 8;

  static const String _context = 'cleona-id-pow-v1';

  /// Nonce-Laenge auf der Leitung (8 Byte little-endian).
  static const int nonceLength = 8;

  static Uint8List _buildBuffer(Uint8List deviceEd25519Pk) {
    final ctx = _context.codeUnits;
    final buf = Uint8List(ctx.length + deviceEd25519Pk.length + nonceLength);
    buf.setRange(0, ctx.length, ctx);
    buf.setRange(ctx.length, ctx.length + deviceEd25519Pk.length, deviceEd25519Pk);
    return buf;
  }

  /// Grind synchron. Nur fuer Tests/Isolate-Body — Produktionspfad nutzt
  /// [computeAsync].
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

  /// Grind im Isolate (Pattern wie ProofOfWork.computeAsync); Fallback
  /// synchron, falls FFI-Init im Isolate scheitert (Android).
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

  /// Verifiziere [nonce] gegen [deviceEd25519Pk] — genau ein SHA-256.
  static bool verify(Uint8List deviceEd25519Pk, Uint8List nonce,
      {int difficulty = difficultyBits}) {
    if (nonce.length != nonceLength) return false;
    final buf = _buildBuffer(deviceEd25519Pk);
    buf.setRange(buf.length - nonceLength, buf.length, nonce);
    final hash = SodiumFFI().sha256(buf);
    return ProofOfWork.hasLeadingZeroBits(hash, difficulty);
  }
}
