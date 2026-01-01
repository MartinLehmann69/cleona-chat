import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// HD-Wallet style key derivation from a master seed.
///
/// Ed25519 and X25519 keys are deterministically derived via HKDF.
/// ML-DSA and ML-KEM keys are NOT deterministic (PQ algorithms use
/// internal randomness), so they are generated fresh and stored separately.
class HdWallet {
  /// Derive Ed25519 keypair from master seed + identity index.
  /// Deterministic: same seed + index always gives same keys.
  static ({Uint8List publicKey, Uint8List secretKey}) deriveEd25519(
    Uint8List masterSeed,
    int index,
  ) {
    final sodium = SodiumFFI();

    // Derive 32-byte Ed25519 seed via HKDF
    final ed25519Seed = sodium.hkdfSha256(
      masterSeed,
      info: Uint8List.fromList('cleona-ed25519-$index'.codeUnits),
      length: 32,
    );

    // Generate Ed25519 keypair from seed
    return sodium.generateEd25519KeyPairFromSeed(ed25519Seed);
  }

  /// Derive X25519 keypair from Ed25519 keys.
  static ({Uint8List publicKey, Uint8List secretKey}) deriveX25519(
    Uint8List ed25519Pk,
    Uint8List ed25519Sk,
  ) {
    final sodium = SodiumFFI();
    return (
      publicKey: sodium.ed25519PkToX25519(ed25519Pk),
      secretKey: sodium.ed25519SkToX25519(ed25519Sk),
    );
  }

  /// Compute User-ID from public key and network secret (Architecture §26).
  /// user_id = SHA-256(network_secret + ed25519_public_key)
  /// This is the stable identity, unchanged across devices.
  static Uint8List computeUserId(Uint8List ed25519Pk, Uint8List networkSecret) {
    final sodium = SodiumFFI();
    final combined = Uint8List(networkSecret.length + ed25519Pk.length);
    combined.setRange(0, networkSecret.length, networkSecret);
    combined.setRange(networkSecret.length, combined.length, ed25519Pk);
    return sodium.sha256(combined);
  }

  /// Legacy alias — returns User-ID (same formula as old Node-ID).
  /// Used during migration; new code should call computeUserId() directly.
  static Uint8List computeNodeId(Uint8List ed25519Pk, Uint8List networkSecret) =>
      computeUserId(ed25519Pk, networkSecret);

  /// Compute Device-Node-ID for network routing (Architecture §3.1, §7.1).
  /// device_id = SHA-256(network_secret + ed25519_device_public_key)
  ///
  /// **Daemon-global identifier**: derived from the daemon's Device-Sig keypair
  /// (lives in `~/.cleona/device_keys.enc`, see §3.5/§3.7), NOT from any User-
  /// keypair. A daemon hosting N UserIDs has exactly one DeviceID — Multi-
  /// Identity is a User-Layer property and has no Device-Layer consequence
  /// (§3.1).
  ///
  /// Multi-Device (one UserID on N physical devices) yields N distinct
  /// DeviceIDs — one per device, each computed from its own device-keypair.
  static Uint8List computeDeviceNodeId(Uint8List deviceEd25519Pk, Uint8List networkSecret) {
    final sodium = SodiumFFI();
    final combined = Uint8List(networkSecret.length + deviceEd25519Pk.length);
    combined.setRange(0, networkSecret.length, networkSecret);
    combined.setRange(networkSecret.length, combined.length, deviceEd25519Pk);
    return sodium.sha256(combined);
  }

  /// Derive the DHT registry key for multi-identity backup.
  static Uint8List registryId(Uint8List masterSeed) {
    final sodium = SodiumFFI();
    return sodium.sha256(Uint8List.fromList([
      ...'cleona-registry-id'.codeUnits,
      ...masterSeed,
    ]));
  }

  /// Derive the encryption key for the registry.
  static Uint8List registryKey(Uint8List masterSeed) {
    final sodium = SodiumFFI();
    return sodium.sha256(Uint8List.fromList([
      ...'cleona-registry-key'.codeUnits,
      ...masterSeed,
    ]));
  }

  // ── Linked-Device Delegation (§7.1 LD-1) ─────────────────────────────

  /// Derive a per-device delegated Ed25519 sig keypair for a Linked Device.
  /// Deterministic: same (masterSeed, deviceId) always yields the same keys.
  static ({Uint8List publicKey, Uint8List secretKey}) deriveDelegatedEd25519(
    Uint8List masterSeed,
    Uint8List deviceId,
  ) {
    final sodium = SodiumFFI();
    final info = Uint8List.fromList([
      ...'cleona-deleg-ed25519-v1'.codeUnits,
      ...deviceId,
    ]);
    final seed = sodium.hkdfSha256(masterSeed, info: info, length: 32);
    return sodium.generateEd25519KeyPairFromSeed(seed);
  }

  /// Derive the HKDF seed for deterministic ML-DSA-65 delegation keygen.
  /// The actual keypair generation requires OQS_SIG_keypair_derand (LD-2).
  static Uint8List deriveDelegatedMlDsaSeed(
    Uint8List masterSeed,
    Uint8List deviceId,
  ) {
    final sodium = SodiumFFI();
    final info = Uint8List.fromList([
      ...'cleona-deleg-mldsa-v1'.codeUnits,
      ...deviceId,
    ]);
    return sodium.hkdfSha256(masterSeed, info: info, length: 64);
  }
}
