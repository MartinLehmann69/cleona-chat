// Integration test: ML-DSA-65 deterministic keygen via NativeCallable on Android.
//
// Verifies that the OQS_randombytes_custom_algorithm + NativeCallable.isolateLocal
// pattern works on Android ARM64/x86_64 (different liboqs build, Android runtime).
//
// Run: flutter test integration_test/test_mldsa_derand.dart -d emulator-5554
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final sodium = SodiumFFI();
  final oqs = OqsFFI();
  oqs.init();

  bool bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  testWidgets('ML-DSA derand: determinism', (tester) async {
    final seed = sodium.randomBytes(64);
    final kp1 = oqs.mlDsaKeypairDerand(seed);
    final kp2 = oqs.mlDsaKeypairDerand(seed);
    expect(bytesEqual(kp1.publicKey, kp2.publicKey), true,
        reason: 'Same seed must produce same PK');
    expect(bytesEqual(kp1.secretKey, kp2.secretKey), true,
        reason: 'Same seed must produce same SK');
  });

  testWidgets('ML-DSA derand: separation', (tester) async {
    final seed1 = sodium.randomBytes(64);
    final seed2 = sodium.randomBytes(64);
    final kp1 = oqs.mlDsaKeypairDerand(seed1);
    final kp2 = oqs.mlDsaKeypairDerand(seed2);
    expect(bytesEqual(kp1.publicKey, kp2.publicKey), false,
        reason: 'Different seeds must produce different PKs');
  });

  testWidgets('ML-DSA derand: sign+verify', (tester) async {
    final seed = sodium.randomBytes(64);
    final kp = oqs.mlDsaKeypairDerand(seed);
    final msg = Uint8List.fromList('android-derand-test'.codeUnits);
    final sig = oqs.mlDsaSign(msg, kp.secretKey);
    expect(oqs.mlDsaVerify(msg, sig, kp.publicKey), true,
        reason: 'Derand key must sign+verify on Android');
  });

  testWidgets('ML-DSA derand: system DRBG restored', (tester) async {
    final seed = sodium.randomBytes(64);
    oqs.mlDsaKeypairDerand(seed);
    final kpRandom = oqs.mlDsaKeypair();
    expect(kpRandom.publicKey.length, OqsFFI.mlDsaPublicKeyLength,
        reason: 'Random keygen must work after derand');
    final msg = Uint8List.fromList('post-derand'.codeUnits);
    final sig = oqs.mlDsaSign(msg, kpRandom.secretKey);
    expect(oqs.mlDsaVerify(msg, sig, kpRandom.publicKey), true,
        reason: 'Random key sign+verify after derand');
  });

  testWidgets('ML-DSA derand: HKDF delegation flow', (tester) async {
    final masterSeed = sodium.randomBytes(32);
    final deviceId = sodium.randomBytes(32);
    final mlDsaSeed = HdWallet.deriveDelegatedMlDsaSeed(masterSeed, deviceId);
    expect(mlDsaSeed.length, 64, reason: 'HKDF seed must be 64 bytes');
    final kp = oqs.mlDsaKeypairDerand(mlDsaSeed);
    expect(kp.publicKey.length, OqsFFI.mlDsaPublicKeyLength);
    expect(kp.secretKey.length, OqsFFI.mlDsaSecretKeyLength);
    final msg = Uint8List.fromList('delegation-test'.codeUnits);
    final sig = oqs.mlDsaSign(msg, kp.secretKey);
    expect(oqs.mlDsaVerify(msg, sig, kp.publicKey), true,
        reason: 'HKDF-derived ML-DSA key must sign+verify');
    final kp2 = oqs.mlDsaKeypairDerand(mlDsaSeed);
    expect(bytesEqual(kp.publicKey, kp2.publicKey), true,
        reason: 'HKDF-derived ML-DSA must be deterministic');
  });

  testWidgets('ML-DSA derand: seed length validation', (tester) async {
    expect(() => oqs.mlDsaKeypairDerand(Uint8List(32)),
        throwsA(isA<ArgumentError>()),
        reason: 'Must reject 32-byte seed');
  });
}
