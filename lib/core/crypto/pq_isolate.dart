/// Background isolate wrappers for CPU-intensive post-quantum crypto.
///
/// All PQ operations (ML-KEM-768, ML-DSA-65) use FFI calls to liboqs that
/// block the calling thread. On Android, Dart runs on the UI thread — blocking
/// for >5s triggers ANR (Application Not Responding).
///
/// These functions run PQ crypto in a fresh Dart isolate via [Isolate.run()],
/// keeping the UI thread responsive. Each isolate creates its own [OqsFFI]
/// singleton (statics are per-isolate) and calls [OqsFFI.init()] before use.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';

// ---------------------------------------------------------------------------
// Key generation (startup + rotation — the main ANR culprit: 15-30s each)
// ---------------------------------------------------------------------------

/// Generate ML-DSA-65 + ML-KEM-768 keypairs concurrently in two isolates.
/// Each keypair takes ~15s on slow devices — running them in parallel cuts
/// fresh-profile startup from ~30s to ~15s on multi-core hardware.
Future<({Uint8List mlDsaPk, Uint8List mlDsaSk, Uint8List mlKemPk, Uint8List mlKemSk})>
    generatePqKeysIsolated() async {
  final dsaFuture = Isolate.run(_generateMlDsa);
  final kemFuture = Isolate.run(_generateMlKem);
  final dsa = await dsaFuture;
  final kem = await kemFuture;
  return (
    mlDsaPk: dsa.publicKey,
    mlDsaSk: dsa.secretKey,
    mlKemPk: kem.publicKey,
    mlKemSk: kem.secretKey,
  );
}

({Uint8List publicKey, Uint8List secretKey}) _generateMlDsa() {
  final oqs = OqsFFI();
  oqs.init();
  return oqs.mlDsaKeypair();
}

/// Generate ML-KEM-768 keypair in a background isolate (for key rotation).
Future<({Uint8List publicKey, Uint8List secretKey})>
    generateMlKemIsolated() {
  return Isolate.run(_generateMlKem);
}

({Uint8List publicKey, Uint8List secretKey}) _generateMlKem() {
  final oqs = OqsFFI();
  oqs.init();
  return oqs.mlKemKeypair();
}

/// Generate both ML-DSA-65 + ML-KEM-768 keypairs for emergency rotation.
/// Returns all four keys needed for rotateIdentityFull().
Future<({
  ({Uint8List publicKey, Uint8List secretKey}) mlDsa,
  ({Uint8List publicKey, Uint8List secretKey}) mlKem,
})> generatePqKeypairsIsolated() {
  return Isolate.run(_generatePqKeypairs);
}

({
  ({Uint8List publicKey, Uint8List secretKey}) mlDsa,
  ({Uint8List publicKey, Uint8List secretKey}) mlKem,
}) _generatePqKeypairs() {
  final oqs = OqsFFI();
  oqs.init();
  return (
    mlDsa: oqs.mlDsaKeypair(),
    mlKem: oqs.mlKemKeypair(),
  );
}
