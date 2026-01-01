/// Derivations of the two rendezvous paths that still exist on the V4.1
/// line: first contact (§4.11.10, URI-bound) and binary distribution
/// (§19.6.5), plus the shared 6 h epoch (§4.11.4).
///
/// ── WHAT STOOD HERE UNTIL S362 AND WHY IT IS GONE ─────────────────────
///
/// Owner decision of 02.09.2026: "We still need Nostr to find access to the
/// network at the IP level. This must be rebuilt V4.1-compatible.
/// V3 compatibility on the other hand is no longer necessary!"
///
/// Removed were therefore six derivations with together zero
/// production callers, which exclusively served the two never created
/// managers:
///
///   `derivePairwiseSecret`, `computeLookupTag`, `deriveNostrSecretKey`
///       — §4.11.3/§4.11.4/§4.11.6, carrier `RendezvousManager`. In V4.1
///         replaced by the pairwise liveness (§6, §8) and the
///         entry cascade (§11).
///   `computeInfraTag`, `deriveInfraKey`, `deriveInfraNostrSecretKey`
///       — §4.11.9, carrier `InfraRendezvousManager`. Replaced by
///         `ExternalEntrySource` (`service_daemon.dart:636-642`).
///
/// Both derivation families drew their tag from the **network secret**
/// or from a pair secret of the founding Ed25519 keys — V3
/// terms that mean nothing on this line any more. The external
/// entry derives its tag from the **channel constant** and the **day**
/// and lies in `tagline/external_entry.dart:45-62`, not here.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int kRendezvousEpochHours = 6;

const String _fcTagSalt = 'cleona-rv-fc-tag-v1';
const String _fcKeySalt = 'cleona-rv-fc-key-v1';
const String _fcNostrSalt = 'cleona-nostr-fc-v1';
const String _binaryTagSalt = 'cleona-rv-binary-v1';
const String _binaryKeySalt = 'cleona-rv-binary-key-v1';
const String _binaryNostrSalt = 'cleona-nostr-binary-v1';

/// First-Contact Rendezvous role of the URI creator (§4.11.10).
const String kFcRoleOwner = 'owner';

/// First-Contact Rendezvous role of the URI consumer (§4.11.10).
const String kFcRoleScanner = 'scanner';

// ---------------------------------------------------------------------------
// First-Contact Rendezvous (§4.11.10) — URI-scoped, nonce-based
// ---------------------------------------------------------------------------

/// Computes the First-Contact lookup tag for an epoch and role.
///
/// [nonce] — 32-byte random nonce from the ContactSeed-URI `r` parameter
/// [epochString] — e.g. "2026-06-28-12" (UTC, 6h boundary)
/// [role] — [kFcRoleOwner] (URI creator) or [kFcRoleScanner] (URI consumer)
Uint8List computeFcTag(Uint8List nonce, String epochString, String role) {
  return SodiumFFI().hkdfSha256(
    nonce,
    salt: Uint8List.fromList(utf8.encode(_fcTagSalt)),
    info: Uint8List.fromList(utf8.encode('$epochString/$role')),
    length: 32,
  );
}

/// Derives the encryption key for First-Contact endpoint records.
/// Shared by both roles within one epoch (each side decrypts the other's
/// record with the same key; the tag in the AAD keeps roles apart).
Uint8List deriveFcKey(Uint8List nonce, String epochString) {
  return SodiumFFI().hkdfSha256(
    nonce,
    salt: Uint8List.fromList(utf8.encode(_fcKeySalt)),
    info: Uint8List.fromList(utf8.encode(epochString)),
    length: 32,
  );
}

/// Derives a deterministic secp256k1 secret key for Nostr First-Contact
/// publishing per device. Different scanners get different Nostr pubkeys,
/// so NIP-33 replaceable events do not overwrite each other cross-device
/// and the owner's d-tag query returns ALL scanner records (same pattern
/// as Infrastructure Rendezvous §4.11.9).
Uint8List deriveFcNostrSecretKey(Uint8List nonce, Uint8List ownDeviceId) {
  final deviceHex =
      ownDeviceId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return SodiumFFI().hkdfSha256(
    nonce,
    salt: Uint8List.fromList(utf8.encode(_fcNostrSalt)),
    info: Uint8List.fromList(utf8.encode(deviceHex)),
    length: 32,
  );
}

/// Returns the epoch string for the given UTC time.
///
/// Format: "YYYY-MM-DD-HH" where HH is snapped to 6h boundaries (00/06/12/18).
String epochStringFor(DateTime utcTime) {
  final y = utcTime.year.toString().padLeft(4, '0');
  final m = utcTime.month.toString().padLeft(2, '0');
  final d = utcTime.day.toString().padLeft(2, '0');
  final h = ((utcTime.hour ~/ kRendezvousEpochHours) * kRendezvousEpochHours)
      .toString()
      .padLeft(2, '0');
  return '$y-$m-$d-$h';
}

/// Returns the epoch string for the current UTC time.
String currentEpochString() => epochStringFor(DateTime.now().toUtc());

/// Returns the epoch string for the next 6h epoch.
String nextEpochString() {
  final now = DateTime.now().toUtc();
  final nextEpoch = now.add(const Duration(hours: kRendezvousEpochHours));
  // Snap to next boundary
  final snapped = DateTime.utc(
    nextEpoch.year,
    nextEpoch.month,
    nextEpoch.day,
    (nextEpoch.hour ~/ kRendezvousEpochHours) * kRendezvousEpochHours,
  );
  return epochStringFor(snapped);
}

/// Returns the epoch string for the previous 6h epoch.
String previousEpochString() {
  final now = DateTime.now().toUtc();
  final prevEpoch = now.subtract(const Duration(hours: kRendezvousEpochHours));
  return epochStringFor(prevEpoch);
}

// ---------------------------------------------------------------------------
// Binary Distribution Rendezvous (§19.6.5)
// ---------------------------------------------------------------------------

/// Computes the network-wide binary-distribution lookup tag for an epoch
/// and platform (e.g. "linux-x64", "android-arm64").
Uint8List computeBinaryTag(
  Uint8List networkSecret,
  String epochString,
  String platform,
) {
  return SodiumFFI().hkdfSha256(
    networkSecret,
    salt: Uint8List.fromList(utf8.encode(_binaryTagSalt)),
    info: Uint8List.fromList(utf8.encode('$epochString/$platform')),
    length: 32,
  );
}

/// Derives the encryption key for binary-distribution manifest records.
Uint8List deriveBinaryKey(Uint8List networkSecret, String epochString) {
  return SodiumFFI().hkdfSha256(
    networkSecret,
    salt: Uint8List.fromList(utf8.encode(_binaryKeySalt)),
    info: Uint8List.fromList(utf8.encode(epochString)),
    length: 32,
  );
}

/// Derives a deterministic secp256k1 secret key for Nostr binary-distribution
/// publishing per device (same pattern as Infrastructure Rendezvous §4.11.9).
Uint8List deriveBinaryNostrSecretKey(
    Uint8List networkSecret, Uint8List deviceId) {
  final deviceHex =
      deviceId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return SodiumFFI().hkdfSha256(
    networkSecret,
    salt: Uint8List.fromList(utf8.encode(_binaryNostrSalt)),
    info: Uint8List.fromList(utf8.encode(deviceHex)),
    length: 32,
  );
}
