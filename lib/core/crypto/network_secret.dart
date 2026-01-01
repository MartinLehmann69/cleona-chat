import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/constant_time.dart';
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
  // V1 key material (Architecture 17.5.6).
  // Interleaved pairs at permuted positions — run _reassemble() to recover
  // the 16-byte secret.  See scripts/gen_secret_table.dart for generation.
  // ---------------------------------------------------------------------------
  static const _betaTable = [0x67, 0x7f, 0x8d, 0x00, 0x7d, 0xf4, 0x13, 0x86, 0x53, 0x52, 0xb1, 0xb4, 0x31, 0x99, 0x77, 0xcb, 0xef, 0x45, 0x85, 0x72, 0x15, 0x15, 0x1b, 0x75, 0x1b, 0xb5, 0x59, 0xc5, 0x29, 0x51, 0x6f, 0x56];
  static const _liveTable = [0x67, 0x9b, 0x8d, 0x81, 0x7d, 0xd6, 0x13, 0xb4, 0x53, 0x71, 0xb1, 0xdc, 0x31, 0x0c, 0x77, 0x89, 0xef, 0xfe, 0x85, 0xb2, 0x15, 0x0f, 0x1b, 0x77, 0x1b, 0xa6, 0x59, 0xcb, 0x29, 0x02, 0x6f, 0x99];
  static const _perm = [11, 4, 14, 1, 8, 13, 2, 7, 15, 6, 9, 0, 5, 10, 3, 12];

  // ---------------------------------------------------------------------------
  // V2 key material would go here when rotating:
  //
  // When rotating to V2:
  // 1. Generate new secret: HMAC-SHA256(maintainer_key, "cleona-network-beta-v2")[:16]
  // 2. Generate V2 tables via scripts/gen_secret_table.dart
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
    final table = ch == NetworkChannel.live ? _liveTable : _betaTable;
    final result = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      result[_perm[i]] = table[2 * i] ^ table[2 * i + 1];
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
    return constantTimeEquals(tag, expected);
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
    return constantTimeEquals(
        Uint8List.fromList(hmacBytes.sublist(0, hmacPrefixLength)), expected);
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
