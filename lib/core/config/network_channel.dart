/// Network channel (beta / live) — build-time configuration, not cryptography.
///
/// This lived in `crypto/network_secret.dart` because V3 derived the network
/// secret per channel. The channel itself is a plain build-time switch: it
/// separates the beta network from the live one. (Until S388 it also named
/// a per-channel bootstrap port; V4.2 §11.7 builds no port, address or host
/// into the application, so that getter is gone.) Twelve files (UI screens, tray, platform glue, `main.dart`) imported
/// the whole secret module for nothing else.
///
/// V4 keeps the channel and drops the secret: `kNetworkChannel` is a public
/// constant that feeds the link KDF (architecture v4 §2.7), and the
/// separation it provides is operational, not a security boundary. Splitting
/// it out is part of AP-1a (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §9.15.5) so that
/// `clogger.dart` — the most-imported file in the project — can leave the
/// network layer without dragging the secret material along.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/platform/app_paths.dart';

/// Network channel identifiers.
enum NetworkChannel {
  beta,
  live;

  /// Resolve from string (e.g. --dart-define=NETWORK_CHANNEL=live).
  static NetworkChannel fromString(String s) => switch (s.toLowerCase()) {
        'live' => NetworkChannel.live,
        _ => NetworkChannel.beta,
      };

  /// Wire literal of this channel — the exact bytes that feed the link KDF
  /// (V4 §2.7, docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4d.10 B). **Frozen wire-relevant
  /// value**, guarded by `test/smoke/smoke_link_kdf.dart`: changing a
  /// literal changes every link key of the channel and splits the network.
  ///
  /// The literal goes into HKDF's `info` parameter, never into the IKM —
  /// so its length is a non-issue by construction (§4d.10 B).
  String get wireName => switch (this) {
        NetworkChannel.beta => 'cleona-beta',
        NetworkChannel.live => 'cleona-live',
      };

  /// Identity domain-separation literal of this channel — see
  /// [kIdentityDomain] below for why this is NOT [wireName].
  ///
  /// **Frozen wire-relevant value**: changing a literal re-mints every UserID
  /// and DeviceID on that channel.
  String get identityDomain => switch (this) {
        NetworkChannel.beta => 'cleona-identity-beta-v1',
        NetworkChannel.live => 'cleona-identity-live-v1',
      };
}

/// The wire literal of the channel this build runs on: `"cleona-beta"` or
/// `"cleona-live"`. This is the value announced in this library's docs and
/// consumed by `LinkKdf` (lib/core/link/link_kdf.dart).
///
/// A getter, not a `const`: channel resolution is partly runtime (Android
/// infers the channel from the package-name suffix, see
/// [activeNetworkChannel]), so a compile-time constant cannot exist without
/// breaking that resolution order.
String get kNetworkChannel => activeNetworkChannel.wireName;

/// The active channel, determined at compile time via --dart-define.
/// On Android: automatically inferred from package name suffix (.beta → beta).
const String _channelStr =
    String.fromEnvironment('NETWORK_CHANNEL', defaultValue: '');

NetworkChannel? _cachedChannel;

/// The channel this build runs on. Resolution order is unchanged from the
/// previous `NetworkSecret.channel`: explicit --dart-define first, then the
/// Android package-name suffix, then the desktop development default.
NetworkChannel get activeNetworkChannel {
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

// ─────────────────────────────────────────────────────────────────────────
// Identity domain (architecture v4.2 §4.1, normative)
//
//   userId   = SHA-256(kIdentityDomain ‖ ed25519_user_pubkey ‖ mldsa65_user_pubkey)
//   deviceId = SHA-256(kIdentityDomain ‖ ed25519_device_pubkey)
//
// (S388, „identifier = A": the ML-DSA-65 key is part of the userId; the same
// value is mycelium's `Address.identifier` and the card fingerprint, §15.2.)
//
// Why a SEPARATE constant instead of reusing [kNetworkChannel]:
//
//  1. Different freeze domains. `kNetworkChannel` ("cleona-beta"/"cleona-live")
//     is the frozen wire literal of the LINK KDF (§2.7), guarded by
//     `test/smoke/smoke_link_kdf.dart`. Sharing one literal would weld two
//     independent freezes together: a future change to the link-KDF literal
//     would re-mint every UserID in the network, and a change here would
//     split every link key. Two freezes, two constants.
//  2. Domain separation is the whole point of the name. The channel literal
//     already serves as HKDF `info` for link keys; feeding the same bytes
//     into a SHA-256 identity prefix is cross-protocol reuse of one label.
//  3. Independent versioning. The `-v1` suffix belongs to the identity
//     derivation, not to the channel, so the two can never be forced to move
//     together.
//
// beta ≠ live is preserved by the literal itself — the two channels carry
// different strings, hence different UserIDs for the same key pair. That
// replaces the previous separation, which came from the per-channel network
// SECRET (`NetworkSecret.identitySecret`) and therefore bound network access
// to the maintainer key — the exact coupling §4.1 forbids ("Network access is
// not bound to any maintainer key").
// ─────────────────────────────────────────────────────────────────────────

/// The identity domain-separation literal of the channel this build runs on.
///
/// **Public by construction.** This is not key material, is not derived from
/// the maintainer key, and is never treated as a secret — it ships in clear
/// text in the published source (architecture v4.1 §4.1).
///
/// **Frozen wire-relevant value.** Changing a literal re-mints every UserID
/// and DeviceID of that channel. Guarded by
/// `test/smoke/smoke_identity_secret_pin.dart`.
String get kIdentityDomain => activeNetworkChannel.identityDomain;

Uint8List? _cachedIdentityDomainBytes;
NetworkChannel? _cachedIdentityDomainChannel;

/// [kIdentityDomain] as the exact bytes that go into the SHA-256 preimage.
///
/// ASCII, no separator, no length prefix: the domain is a fixed literal per
/// build and the public key that follows it has a fixed length (32 bytes), so
/// the concatenation is unambiguous by construction.
Uint8List get kIdentityDomainBytes {
  final channel = activeNetworkChannel;
  final cached = _cachedIdentityDomainBytes;
  if (cached != null && _cachedIdentityDomainChannel == channel) return cached;
  final bytes = Uint8List.fromList(ascii.encode(channel.identityDomain));
  _cachedIdentityDomainBytes = bytes;
  _cachedIdentityDomainChannel = channel;
  return bytes;
}

/// The active channel as a one-character mark ('b' or 'l') — the form in
/// which the ContactSeed carries it (`c=`, §8.1.1).
///
/// ── WHY THIS STANDS HERE AND NOT WITH THE MESSAGE (S368) ────────────
///
/// Until today this function lay in `contact/contact_seed_refusal.dart`.
/// That file pulls in the entire Flutter framework via `AppLocale` — it
/// has to, because it formulates translated text. Thus the MARK could
/// only be had by taking Flutter along, and a standalone smoke that
/// needs it broke off during compilation (the Dart VM's FFI transformer
/// dies on Flutter bindings in a pure Dart script: "type 'InvalidType'
/// is not a subtype of type 'FunctionType'").
///
/// The mark is pure configuration and therefore belongs next to the
/// channel, not next to its translation.
String localChannelTag() =>
    activeNetworkChannel == NetworkChannel.beta ? 'b' : 'l';
