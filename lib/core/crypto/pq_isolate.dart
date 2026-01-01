/// Post-quantum key generation — ON THE CALLING ISOLATE, never in a second one.
///
/// Until S398 these functions ran liboqs in a fresh isolate via
/// [Isolate.run], on the belief that keygen took 15-30 s on slow devices
/// (V3.1.55). Measured on 28.09.2026 on x86_64: ML-DSA-65 keygen 673 µs,
/// ML-KEM-768 keygen 55 µs, the deterministic derivations 355 µs / 79 µs.
///
/// The second isolate was not only unnecessary, it crashed the process:
/// `mlDsaKeypairDerand` points liboqs's PROCESS-GLOBAL randomness source
/// (`OQS_randombytes_custom_algorithm`) at an isolate-local callback, and an
/// ML-KEM encapsulation on the main isolate in the same instant calls that
/// callback from the wrong isolate — "Cannot invoke native callback from a
/// different isolate" (S398, 3 of ~12 multi-node smoke runs). With every
/// liboqs call on one isolate nothing runs concurrently with the hook.
///
/// The names keep "Isolated" and the [Future] return so that no caller has
/// to change; the work is scheduled on the event loop, not moved off it.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';

typedef PqKeys = ({
  Uint8List mlDsaPk,
  Uint8List mlDsaSk,
  Uint8List mlKemPk,
  Uint8List mlKemSk,
});

typedef PqKeypair = ({Uint8List publicKey, Uint8List secretKey});

/// Fresh ML-DSA-65 + ML-KEM-768 keypairs.
Future<PqKeys> generatePqKeysIsolated() => Future(() {
      final oqs = OqsFFI()..init();
      final dsa = oqs.mlDsaKeypair();
      final kem = oqs.mlKemKeypair();
      return (
        mlDsaPk: dsa.publicKey,
        mlDsaSk: dsa.secretKey,
        mlKemPk: kem.publicKey,
        mlKemSk: kem.secretKey,
      );
    });

/// A fresh ML-KEM-768 keypair (key rotation).
Future<PqKeypair> generateMlKemIsolated() =>
    Future(() => (OqsFFI()..init()).mlKemKeypair());

/// Deterministic PQ keypairs from master seed + HD index. Same seed + index
/// always yields identical keys — critical for seed recovery.
Future<PqKeys> generatePqKeysDeterministicIsolated(
        Uint8List masterSeed, int hdIndex) =>
    Future(() {
      OqsFFI().init();
      final dsa = HdWallet.deriveMlDsa(masterSeed, hdIndex);
      final kem = HdWallet.deriveMlKem(masterSeed, hdIndex);
      return (
        mlDsaPk: dsa.publicKey,
        mlDsaSk: dsa.secretKey,
        mlKemPk: kem.publicKey,
        mlKemSk: kem.secretKey,
      );
    });

/// Both fresh keypairs for emergency rotation (`rotateIdentityFull()`).
Future<({PqKeypair mlDsa, PqKeypair mlKem})> generatePqKeypairsIsolated() =>
    Future(() {
      final oqs = OqsFFI()..init();
      return (mlDsa: oqs.mlDsaKeypair(), mlKem: oqs.mlKemKeypair());
    });
