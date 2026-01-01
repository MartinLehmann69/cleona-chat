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
/// Secret Rotation (Architecture §13.2):
/// - Each major release rotates the secret version
/// - During transition, both current and previous secrets are accepted
/// - Outgoing packets use the PREVIOUS secret (backward-compatible with
///   un-updated peers); after transition ends, outgoing uses the current
/// - A one-generation-old "expired hint" secret is kept solely to detect
///   peers whose secret has fully expired and send them an EPOCH_EXPIRED
///   update hint (wrapped with their old secret so they can parse it)
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

  /// Expired-hint secret version: the most recent secret we no longer ACCEPT
  /// but still keep to DETECT expired peers and send them an EPOCH_EXPIRED
  /// update hint. Set to the old previousSecretVersion when closing a
  /// transition window (e.g. current=2, previous=0, expiredHint=1).
  /// 0 = no expired hint secret available.
  static const int expiredHintSecretVersion = 0;

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
  // 4. After 90 days: set previousSecretVersion = 0, expiredHintSecretVersion = 1
  // ---------------------------------------------------------------------------

  static Uint8List? _cached;
  static Uint8List? _cachedPrevious;
  static Uint8List? _cachedExpiredHint;

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

  /// Returns the expired-hint secret, or null if not configured.
  static Uint8List? get expiredHintSecret {
    if (expiredHintSecretVersion == 0) return null;
    _cachedExpiredHint ??= _secretForVersion(expiredHintSecretVersion);
    return _cachedExpiredHint;
  }

  /// Whether dual-secret acceptance is active.
  static bool get isInTransition => previousSecretVersion > 0;

  /// The secret to use for all outbound packets.
  /// During transition: the PREVIOUS (old) secret — ensures backward
  /// compatibility with un-updated peers who only know the old secret.
  /// After transition: the CURRENT secret.
  static Uint8List get outboundSecret => previousSecret ?? secret;

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

  /// Length of the HMAC prefix on all non-Proto UDP packets (Discovery, CPRB,
  /// fragments). NetworkPacketV3 carries its tag in the `network_tag` field
  /// instead — see [networkTagLength].
  static const hmacPrefixLength = 8;

  /// Length of the in-frame HMAC tag for NetworkPacketV3 (V3 wire-format).
  /// HMAC-SHA256 truncated to 128 bits per Architecture v3.0 §2.4 [11].
  static const networkTagLength = 16;

  /// Compute 8-byte truncated HMAC-SHA256 for packet authentication.
  /// Prepended to every outgoing UDP packet (Architecture 17.5.4).
  /// Uses [outboundSecret] (old secret during transition for compat).
  static Uint8List computePacketHmac(Uint8List payload) {
    return _truncate(_computeHmacFull(outboundSecret, payload), hmacPrefixLength);
  }

  /// Compute the 16-byte in-frame network_tag for a NetworkPacketV3.
  /// Input must be the protobuf serialization of the packet WITHOUT the
  /// network_tag field set (Architecture v3.0 §2.4 [11]).
  /// Uses [outboundSecret] (old secret during transition for compat).
  static Uint8List computeNetworkTag(Uint8List frameBytesWithoutTag) {
    return _truncate(
        _computeHmacFull(outboundSecret, frameBytesWithoutTag), networkTagLength);
  }

  /// Verify the 16-byte network_tag of a received NetworkPacketV3.
  /// `frameBytesWithoutTag` must be the re-serialization of the parsed packet
  /// with the network_tag field cleared. Tries the current secret first, then
  /// the previous secret (if in transition).
  static bool verifyNetworkTag(
      Uint8List tag, Uint8List frameBytesWithoutTag) {
    if (tag.length != networkTagLength) return false;
    if (_verifyTagWith(secret, tag, frameBytesWithoutTag)) return true;
    final prev = previousSecret;
    if (prev != null && _verifyTagWith(prev, tag, frameBytesWithoutTag)) {
      return true;
    }
    return false;
  }

  static bool _verifyTagWith(
      Uint8List secretBytes, Uint8List tag, Uint8List payload) {
    final expected =
        _truncate(_computeHmacFull(secretBytes, payload), networkTagLength);
    return _ctEquals(tag, expected);
  }

  /// Compute full 32-byte HMAC-SHA256 with a specific secret. Internal — most
  /// callers want the 8-byte (prefix) or 16-byte (network_tag) truncation.
  static Uint8List _computeHmacFull(Uint8List secretBytes, Uint8List payload) {
    final sodium = SodiumFFI();
    // HMAC-SHA256 expects 32-byte key — pad 16-byte secret to 32
    final key = Uint8List(32);
    key.setRange(0, 16, secretBytes);
    return Uint8List.fromList(sodium.hmacSha256(key, payload));
  }

  static Uint8List _truncate(Uint8List bytes, int length) =>
      Uint8List.fromList(bytes.sublist(0, length));

  /// Verify the 8-byte HMAC prefix of a received packet.
  /// Returns true if valid against the current secret.
  static bool verifyPacketHmac(Uint8List hmacBytes, Uint8List payload) {
    return _verifyHmacWith(secret, hmacBytes, payload);
  }

  /// Verify HMAC with a specific secret.
  static bool _verifyHmacWith(
      Uint8List secretBytes, Uint8List hmacBytes, Uint8List payload) {
    final expected =
        _truncate(_computeHmacFull(secretBytes, payload), hmacPrefixLength);
    if (hmacBytes.length < hmacPrefixLength) return false;
    return _ctEquals(
        Uint8List.fromList(hmacBytes.sublist(0, hmacPrefixLength)), expected);
  }

  /// Constant-time equality on equal-length Uint8Lists.
  static bool _ctEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
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

  // ── EPOCH_EXPIRED hint (§13.2) ──────────────────────────────────────
  // Format: [8B HMAC(old_secret, payload)][payload]
  // Payload: [4B magic "CEEP"][2B minVersionLE][2B currentEpochLE]
  // Total: 16 bytes on wire (8 HMAC + 8 payload).

  /// Magic for EPOCH_EXPIRED hint packets: "CEEP" (Cleona Epoch Expired)
  static const epochExpiredMagic = [0x43, 0x45, 0x45, 0x50];

  /// Build an EPOCH_EXPIRED hint packet wrapped with [hintSecret].
  /// Returns null if no hint secret is available.
  static Uint8List? buildEpochExpiredPacket() {
    final hint = expiredHintSecret;
    if (hint == null) return null;
    final payload = Uint8List(8);
    payload[0] = epochExpiredMagic[0];
    payload[1] = epochExpiredMagic[1];
    payload[2] = epochExpiredMagic[2];
    payload[3] = epochExpiredMagic[3];
    payload[4] = currentSecretVersion & 0xFF;
    payload[5] = (currentSecretVersion >> 8) & 0xFF;
    payload[6] = currentSecretVersion & 0xFF; // epoch = version for now
    payload[7] = (currentSecretVersion >> 8) & 0xFF;
    final hmac = _truncate(_computeHmacFull(hint, payload), hmacPrefixLength);
    final packet = Uint8List(hmacPrefixLength + payload.length);
    packet.setRange(0, hmacPrefixLength, hmac);
    packet.setRange(hmacPrefixLength, packet.length, payload);
    return packet;
  }

  /// Try to parse an EPOCH_EXPIRED hint from an already-unwrapped payload.
  /// Returns the minimum required version, or null if not an EPOCH_EXPIRED.
  static int? parseEpochExpiredPayload(Uint8List payload) {
    if (payload.length < 8) return null;
    if (payload[0] != epochExpiredMagic[0] ||
        payload[1] != epochExpiredMagic[1] ||
        payload[2] != epochExpiredMagic[2] ||
        payload[3] != epochExpiredMagic[3]) {
      return null;
    }
    return payload[4] | (payload[5] << 8);
  }

  /// Check raw prefix-wrapped packet bytes against the expired-hint secret.
  /// Used when both current and previous HMAC verification failed — if this
  /// succeeds, the sender is running an expired build and we should respond
  /// with a hint. Returns true on match.
  static bool verifyPrefixHmacWithExpiredHint(Uint8List packet) {
    final hint = expiredHintSecret;
    if (hint == null) return false;
    if (packet.length <= hmacPrefixLength) return false;
    final hmac = Uint8List.fromList(packet.sublist(0, hmacPrefixLength));
    final payload = Uint8List.fromList(packet.sublist(hmacPrefixLength));
    return _verifyHmacWith(hint, hmac, payload);
  }

  /// Check a V3 in-frame network_tag against the expired-hint secret.
  static bool verifyNetworkTagWithExpiredHint(
      Uint8List tag, Uint8List frameBytesWithoutTag) {
    final hint = expiredHintSecret;
    if (hint == null) return false;
    if (tag.length != networkTagLength) return false;
    return _verifyTagWith(hint, tag, frameBytesWithoutTag);
  }

  /// Clear cached secrets (for testing).
  static void clearCache() {
    _cached = null;
    _cachedPrevious = null;
    _cachedExpiredHint = null;
  }
}
