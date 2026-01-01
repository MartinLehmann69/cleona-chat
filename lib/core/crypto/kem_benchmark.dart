/// KEM (Key Encapsulation Mechanism) benchmark utility for profiling
/// encryption/decryption throughput.
///
/// Measures per-operation timings for:
/// - Full PerMessageKem encrypt/decrypt (hybrid X25519 + ML-KEM-768)
/// - X25519 DH alone
/// - ML-KEM-768 encapsulate/decapsulate alone
///
/// Usage:
/// ```dart
/// final result = await KemBenchmark.runBenchmark(iterations: 200);
/// print('Encrypt: ${result.encryptOpsPerSec.toStringAsFixed(1)} ops/s');
/// print('Decrypt: ${result.decryptOpsPerSec.toStringAsFixed(1)} ops/s');
/// ```
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Immutable result of a [KemBenchmark.runBenchmark] run.
class KemBenchmarkResult {
  final int iterations;
  final Duration encryptTotal;
  final Duration decryptTotal;
  final Duration x25519DhTotal;
  final Duration mlKemEncapsTotal;
  final Duration mlKemDecapsTotal;

  const KemBenchmarkResult({
    required this.iterations,
    required this.encryptTotal,
    required this.decryptTotal,
    required this.x25519DhTotal,
    required this.mlKemEncapsTotal,
    required this.mlKemDecapsTotal,
  });

  double get encryptOpsPerSec =>
      iterations / (encryptTotal.inMicroseconds / 1e6);

  double get decryptOpsPerSec =>
      iterations / (decryptTotal.inMicroseconds / 1e6);

  double get x25519DhOpsPerSec =>
      iterations / (x25519DhTotal.inMicroseconds / 1e6);

  double get mlKemEncapsOpsPerSec =>
      iterations / (mlKemEncapsTotal.inMicroseconds / 1e6);

  double get mlKemDecapsOpsPerSec =>
      iterations / (mlKemDecapsTotal.inMicroseconds / 1e6);

  /// Average time per encrypt operation in milliseconds.
  double get encryptAvgMs =>
      encryptTotal.inMicroseconds / iterations / 1000.0;

  /// Average time per decrypt operation in milliseconds.
  double get decryptAvgMs =>
      decryptTotal.inMicroseconds / iterations / 1000.0;

  @override
  String toString() => 'KemBenchmarkResult('
      'iterations=$iterations, '
      'encrypt=${encryptAvgMs.toStringAsFixed(2)}ms/op '
      '(${encryptOpsPerSec.toStringAsFixed(1)} ops/s), '
      'decrypt=${decryptAvgMs.toStringAsFixed(2)}ms/op '
      '(${decryptOpsPerSec.toStringAsFixed(1)} ops/s), '
      'x25519Dh=${(x25519DhTotal.inMicroseconds / iterations / 1000.0).toStringAsFixed(2)}ms/op '
      '(${x25519DhOpsPerSec.toStringAsFixed(1)} ops/s), '
      'mlKemEncaps=${(mlKemEncapsTotal.inMicroseconds / iterations / 1000.0).toStringAsFixed(2)}ms/op '
      '(${mlKemEncapsOpsPerSec.toStringAsFixed(1)} ops/s), '
      'mlKemDecaps=${(mlKemDecapsTotal.inMicroseconds / iterations / 1000.0).toStringAsFixed(2)}ms/op '
      '(${mlKemDecapsOpsPerSec.toStringAsFixed(1)} ops/s)'
      ')';
}

/// Diagnostic benchmark for KEM operations.
///
/// Runs in the main isolate (no Isolate.run) since this is intended for
/// on-demand profiling, not production hot-paths.
class KemBenchmark {
  KemBenchmark._();

  /// Run the full benchmark suite.
  ///
  /// [iterations] controls how many encrypt/decrypt/DH/encaps/decaps cycles
  /// are measured. Higher values smooth out jitter but take longer.
  static Future<KemBenchmarkResult> runBenchmark({
    int iterations = 100,
  }) async {
    final sodium = SodiumFFI();
    final oqs = OqsFFI();
    oqs.init();

    // --- Key generation (not timed, one-time setup) ---

    // Recipient Ed25519 keypair -> derive X25519 keys
    final recipientEd = sodium.generateEd25519KeyPair();
    final recipientX25519Pk = sodium.ed25519PkToX25519(recipientEd.publicKey);
    final recipientX25519Sk = sodium.ed25519SkToX25519(recipientEd.secretKey);

    // Recipient ML-KEM-768 keypair
    final recipientMlKem = oqs.mlKemKeypair();

    // Ephemeral Ed25519 keypair for isolated DH benchmarks
    final ephEd = sodium.generateEd25519KeyPair();
    final ephX25519Sk = sodium.ed25519SkToX25519(ephEd.secretKey);

    // 256-byte test plaintext
    final plaintext = Uint8List(256);
    for (var i = 0; i < plaintext.length; i++) {
      plaintext[i] = i & 0xFF;
    }

    // --- Warm-up (1 cycle, untimed) ---
    final (warmHeader, warmCt) = PerMessageKem.encrypt(
      plaintext: plaintext,
      recipientX25519Pk: recipientX25519Pk,
      recipientMlKemPk: recipientMlKem.publicKey,
    );
    PerMessageKem.decrypt(
      kemHeader: warmHeader,
      ciphertext: warmCt,
      ourX25519Sk: recipientX25519Sk,
      ourMlKemSk: recipientMlKem.secretKey,
    );

    // --- Benchmark: full encrypt ---
    final swEncrypt = Stopwatch()..start();
    final encryptedPairs = <(KemHeader, Uint8List)>[];
    for (var i = 0; i < iterations; i++) {
      encryptedPairs.add(PerMessageKem.encrypt(
        plaintext: plaintext,
        recipientX25519Pk: recipientX25519Pk,
        recipientMlKemPk: recipientMlKem.publicKey,
      ));
    }
    swEncrypt.stop();
    final encryptTotal = swEncrypt.elapsed;

    // --- Benchmark: full decrypt ---
    final swDecrypt = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      final (header, ct) = encryptedPairs[i];
      final pt = PerMessageKem.decrypt(
        kemHeader: header,
        ciphertext: ct,
        ourX25519Sk: recipientX25519Sk,
        ourMlKemSk: recipientMlKem.secretKey,
      );
      // Zero decrypted plaintext (benchmark artifact, not real data)
      for (var j = 0; j < pt.length; j++) {
        pt[j] = 0;
      }
    }
    swDecrypt.stop();
    final decryptTotal = swDecrypt.elapsed;

    // --- Benchmark: X25519 DH alone ---
    final swDh = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      final dhResult = sodium.x25519ScalarMult(
        ephX25519Sk,
        recipientX25519Pk,
      );
      // Zero intermediate
      for (var j = 0; j < dhResult.length; j++) {
        dhResult[j] = 0;
      }
    }
    swDh.stop();
    final x25519DhTotal = swDh.elapsed;

    // --- Benchmark: ML-KEM encapsulate alone ---
    final encapsResults = <({Uint8List ciphertext, Uint8List sharedSecret})>[];
    final swEncaps = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      encapsResults.add(oqs.mlKemEncapsulate(recipientMlKem.publicKey));
    }
    swEncaps.stop();
    final mlKemEncapsTotal = swEncaps.elapsed;

    // --- Benchmark: ML-KEM decapsulate alone ---
    final swDecaps = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      final ss = oqs.mlKemDecapsulate(
        encapsResults[i].ciphertext,
        recipientMlKem.secretKey,
      );
      // Zero shared secret
      for (var j = 0; j < ss.length; j++) {
        ss[j] = 0;
      }
    }
    swDecaps.stop();
    final mlKemDecapsTotal = swDecaps.elapsed;

    // --- Zero key material ---
    for (var i = 0; i < recipientEd.secretKey.length; i++) {
      recipientEd.secretKey[i] = 0;
    }
    for (var i = 0; i < recipientX25519Sk.length; i++) {
      recipientX25519Sk[i] = 0;
    }
    for (var i = 0; i < recipientMlKem.secretKey.length; i++) {
      recipientMlKem.secretKey[i] = 0;
    }
    for (var i = 0; i < ephEd.secretKey.length; i++) {
      ephEd.secretKey[i] = 0;
    }
    for (var i = 0; i < ephX25519Sk.length; i++) {
      ephX25519Sk[i] = 0;
    }
    // Zero encaps shared secrets
    for (final r in encapsResults) {
      for (var i = 0; i < r.sharedSecret.length; i++) {
        r.sharedSecret[i] = 0;
      }
    }

    return KemBenchmarkResult(
      iterations: iterations,
      encryptTotal: encryptTotal,
      decryptTotal: decryptTotal,
      x25519DhTotal: x25519DhTotal,
      mlKemEncapsTotal: mlKemEncapsTotal,
      mlKemDecapsTotal: mlKemDecapsTotal,
    );
  }
}
