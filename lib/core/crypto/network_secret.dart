import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/platform/app_paths.dart';

/// Network channel identifiers.
enum NetworkChannel {
  beta,
  live;

  /// Default bootstrap port for this channel.
  /// Live = 8080 (production, established DNAT chain).
  /// Beta = 8081 (development/testing).
  int get defaultBootstrapPort => switch (this) {
        NetworkChannel.live => 8080,
        NetworkChannel.beta => 8081,
      };

  /// Resolve from string (e.g. --dart-define=NETWORK_CHANNEL=live).
  static NetworkChannel fromString(String s) => switch (s.toLowerCase()) {
        'live' => NetworkChannel.live,
        _ => NetworkChannel.beta,
      };
}

/// Closed Network Model (Architecture 17.5).
///
/// The network secret is derived offline from the maintainer's Ed25519 private key:
///   network_secret = HMAC-SHA256(maintainer_key, "cleona-network-" + channel + "-v" + version)[:16]
///
/// It is embedded at build time in XOR-masked fragments (Architecture 17.5.6).
/// Nodes without the correct secret cannot parse, generate, or respond to
/// Cleona network traffic — they are cryptographically isolated.
///
/// Secret Rotation (Architecture 17.5.5):
/// - Each major release rotates the secret version
/// - During transition (90 days), both current and previous secrets are accepted
/// - Outgoing packets always use the current secret
/// - After 90 days, the previous secret is dropped
class NetworkSecret {
  /// The active channel, determined at compile time via --dart-define.
  /// On Android: automatically inferred from package name suffix (.beta → beta).
  static const _channelStr =
      String.fromEnvironment('NETWORK_CHANNEL', defaultValue: '');

  static NetworkChannel? _cachedChannel;

  static NetworkChannel get channel {
    if (_cachedChannel != null) return _cachedChannel!;
    if (_channelStr.isNotEmpty) {
      _cachedChannel = NetworkChannel.fromString(_channelStr);
      return _cachedChannel!;
    }
    // Auto-detect from Android package name
    if (Platform.isAndroid) {
      _cachedChannel = AppPaths.packageName.endsWith('.beta')
          ? NetworkChannel.beta
          : NetworkChannel.live;
    } else {
      // Desktop default: beta (dev environment)
      _cachedChannel = NetworkChannel.beta;
    }
    return _cachedChannel!;
  }

  /// Current secret version. Increment when rotating secrets.
  static const int currentSecretVersion = 1;

  /// Previous secret version (0 = no previous secret / first version).
  /// Set to currentSecretVersion - 1 during transition periods.
  /// Set to 0 to disable dual-secret acceptance.
  static const int previousSecretVersion = 0;

  /// Transition period in days. After this many days since build,
  /// the previous secret is no longer accepted.
  static const int transitionDays = 90;

  // ---------------------------------------------------------------------------
  // Beta secret V1 fragments (XOR-masked, Architecture 17.5.6)
  // secret = HMAC-SHA256(maintainer_seed, "cleona-network-beta")[:16]
  // Note: V1 uses the original derivation string without "-v1" suffix
  // for backwards compatibility with the initial release.
  // ---------------------------------------------------------------------------
  static const _f0 = [0x00, 0xa5, 0x59, 0xba];
  static const _m0 = [0x6e, 0x30, 0xf1, 0xc2];
  static const _f1 = [0x47, 0xd9, 0x6e, 0xcb];
  static const _m1 = [0xca, 0x77, 0x99, 0x77];
  static const _f2 = [0x46, 0xc7, 0x92, 0x8a];
  static const _m2 = [0x47, 0xc7, 0x0e, 0x92];
  static const _f3 = [0x35, 0x79, 0xa2, 0x90];
  static const _m3 = [0x0c, 0x7c, 0x2b, 0x3a];

  // ---------------------------------------------------------------------------
  // Live secret V1 fragments (XOR-masked)
  // secret = HMAC-SHA256(maintainer_seed, "cleona-network-live")[:16]
  // ---------------------------------------------------------------------------
  static const _lf0 = [0xdb, 0x39, 0x86, 0xec];
  static const _lm0 = [0xb7, 0x9e, 0xbb, 0xc7];
  static const _lf1 = [0x3e, 0xcf, 0x65, 0x4b];
  static const _lm1 = [0x32, 0x72, 0x52, 0xb5];
  static const _lf2 = [0x2d, 0xa8, 0xa0, 0x0e];
  static const _lm2 = [0x0f, 0xb2, 0x32, 0xf2];
  static const _lf3 = [0x32, 0xca, 0x4d, 0x99];
  static const _lm3 = [0xc4, 0xa7, 0xe6, 0x88];

  // ---------------------------------------------------------------------------
  // V2 secret fragments would go here when rotating:
  //
  // When rotating to V2:
  // 1. Generate new secret: HMAC-SHA256(maintainer_key, "cleona-network-beta-v2")[:16]
  // 2. Add V2 fragments below (XOR-masked as usual)
  // 3. Set currentSecretVersion = 2, previousSecretVersion = 1
  // 4. After 90 days: remove V1 fragments, set previousSecretVersion = 0
  // ---------------------------------------------------------------------------

  static Uint8List? _cached;
  static Uint8List? _cachedPrevious;

  /// Returns the 16-byte network secret for the current version.
  /// Reassembled from XOR-masked fragments at runtime.
  static Uint8List get secret {
    if (_cached != null) return _cached!;
    _cached = _secretForVersion(currentSecretVersion);
    return _cached!;
  }

  /// Returns the previous secret (if in transition period), or null.
  static Uint8List? get previousSecret {
    if (previousSecretVersion == 0) return null;
    _cachedPrevious ??= _secretForVersion(previousSecretVersion);
    return _cachedPrevious;
  }

  /// Whether dual-secret acceptance is active.
  static bool get isInTransition => previousSecretVersion > 0;

  /// Returns the secret for the given version.
  static Uint8List _secretForVersion(int version) {
    // Currently only version 1 exists.
    // When adding V2, add a case here.
    switch (version) {
      case 1:
        return _reassemble(channel);
      default:
        throw ArgumentError('Unknown secret version: $version');
    }
  }

  static Uint8List _reassemble(NetworkChannel ch) {
    final List<List<int>> frags;
    final List<List<int>> masks;
    if (ch == NetworkChannel.live) {
      frags = [_lf0, _lf1, _lf2, _lf3];
      masks = [_lm0, _lm1, _lm2, _lm3];
    } else {
      frags = [_f0, _f1, _f2, _f3];
      masks = [_m0, _m1, _m2, _m3];
    }
    final result = Uint8List(16);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        result[i * 4 + j] = frags[i][j] ^ masks[i][j];
      }
    }
    return result;
  }

  /// Length of the HMAC prefix on all UDP packets.
  static const hmacPrefixLength = 8;

  /// Compute 8-byte truncated HMAC-SHA256 for packet authentication.
  /// Prepended to every outgoing UDP packet (Architecture 17.5.4).
  /// Always uses the CURRENT secret.
  static Uint8List computePacketHmac(Uint8List payload) {
    return _computeHmacWith(secret, payload);
  }

  /// Compute HMAC with a specific secret.
  static Uint8List _computeHmacWith(Uint8List secretBytes, Uint8List payload) {
    final sodium = SodiumFFI();
    // HMAC-SHA256 expects 32-byte key — pad 16-byte secret to 32
    final key = Uint8List(32);
    key.setRange(0, 16, secretBytes);
    final full = sodium.hmacSha256(key, payload);
    return Uint8List.fromList(full.sublist(0, hmacPrefixLength));
  }

  /// Verify the 8-byte HMAC prefix of a received packet.
  /// Returns true if valid against the current secret.
  static bool verifyPacketHmac(Uint8List hmacBytes, Uint8List payload) {
    return _verifyHmacWith(secret, hmacBytes, payload);
  }

  /// Verify HMAC with a specific secret.
  static bool _verifyHmacWith(
      Uint8List secretBytes, Uint8List hmacBytes, Uint8List payload) {
    final expected = _computeHmacWith(secretBytes, payload);
    if (hmacBytes.length < hmacPrefixLength) return false;
    // Constant-time comparison
    var diff = 0;
    for (var i = 0; i < hmacPrefixLength; i++) {
      diff |= hmacBytes[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// Prepend 8-byte HMAC to a packet payload.
  /// Always uses the CURRENT secret.
  static Uint8List wrapPacket(Uint8List payload) {
    final hmac = computePacketHmac(payload);
    final wrapped = Uint8List(hmacPrefixLength + payload.length);
    wrapped.setRange(0, hmacPrefixLength, hmac);
    wrapped.setRange(hmacPrefixLength, wrapped.length, payload);
    return wrapped;
  }

  /// Verify and unwrap a received packet.
  /// Tries the current secret first, then the previous secret (if in transition).
  /// Returns payload if valid, null if invalid against all accepted secrets.
  static Uint8List? unwrapPacket(Uint8List packet) {
    if (packet.length <= hmacPrefixLength) return null;
    final hmac = Uint8List.fromList(packet.sublist(0, hmacPrefixLength));
    final payload = Uint8List.fromList(packet.sublist(hmacPrefixLength));

    // Try current secret first (fast path, most common case)
    if (_verifyHmacWith(secret, hmac, payload)) return payload;

    // Try previous secret if in transition period (Architecture 17.5.5)
    final prev = previousSecret;
    if (prev != null && _verifyHmacWith(prev, hmac, payload)) return payload;

    return null;
  }

  /// Clear cached secrets (for testing).
  static void clearCache() {
    _cached = null;
    _cachedPrevious = null;
  }
}
