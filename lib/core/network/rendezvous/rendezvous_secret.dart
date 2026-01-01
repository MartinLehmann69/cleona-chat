/// Pairwise Rendezvous Secret derivation, Lookup Tag computation,
/// Infrastructure Rendezvous key derivation, and First-Contact
/// Rendezvous derivation.
///
/// Architecture §4.11.3 (Pairwise Secret) + §4.11.4 (Lookup Tag & Epoch)
/// + §4.11.9 (Infrastructure Rendezvous) + §4.11.10 (First-Contact
/// Rendezvous, URI-scoped).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int kRendezvousEpochHours = 6;

const String _pairwiseSalt = 'cleona-rendezvous-v1';
const String _tagSalt = 'cleona-rv-tag-v1';
const String _nostrKeySalt = 'cleona-nostr-v1';
const String _infraTagSalt = 'cleona-rv-infra-v1';
const String _infraKeySalt = 'cleona-rv-infra-key-v1';
const String _infraNostrSalt = 'cleona-nostr-infra-v1';
const String _fcTagSalt = 'cleona-rv-fc-tag-v1';
const String _fcKeySalt = 'cleona-rv-fc-key-v1';
const String _fcNostrSalt = 'cleona-nostr-fc-v1';
const String _binaryTagSalt = 'cleona-rv-binary-v1';
const String _binaryKeySalt = 'cleona-rv-binary-key-v1';
const String _binaryNostrSalt = 'cleona-nostr-binary-v1';
const String _inviteBinarySalt = 'cleona-invite-binary-v1';

/// First-Contact Rendezvous role of the URI creator (§4.11.10).
const String kFcRoleOwner = 'owner';

/// First-Contact Rendezvous role of the URI consumer (§4.11.10).
const String kFcRoleScanner = 'scanner';

// ---------------------------------------------------------------------------
// Pairwise Rendezvous Secret (§4.11.3)
// ---------------------------------------------------------------------------

/// Derives a deterministic pairwise secret between two contacts.
///
/// Both sides compute the same 32-byte secret independently:
///   1. Convert founding Ed25519 keys to X25519
///   2. X25519 Diffie-Hellman
///   3. HKDF-SHA-256 with domain separation
///
/// [ownFoundingSk] — own founding Ed25519 secret key (64 bytes)
/// [contactFoundingPk] — contact's founding Ed25519 public key (32 bytes)
/// [ownUserIdHex] — own userId as lowercase hex
/// [contactUserIdHex] — contact's userId as lowercase hex
Uint8List derivePairwiseSecret(
  Uint8List ownFoundingSk,
  Uint8List contactFoundingPk,
  String ownUserIdHex,
  String contactUserIdHex,
) {
  final sodium = SodiumFFI();

  // Step 1: Convert founding keys to X25519
  final ownX25519Sk = sodium.ed25519SkToX25519(ownFoundingSk);
  final contactX25519Pk = sodium.ed25519PkToX25519(contactFoundingPk);

  // Step 2: X25519 DH
  final pairwiseDh = sodium.x25519ScalarMult(ownX25519Sk, contactX25519Pk);

  // Step 3: HKDF with sorted userIds for symmetry
  final a = ownUserIdHex.toLowerCase();
  final b = contactUserIdHex.toLowerCase();
  final info = a.compareTo(b) < 0 ? '$a$b' : '$b$a';

  return sodium.hkdfSha256(
    pairwiseDh,
    salt: Uint8List.fromList(utf8.encode(_pairwiseSalt)),
    info: Uint8List.fromList(utf8.encode(info)),
    length: 32,
  );
}

// ---------------------------------------------------------------------------
// Lookup Tag (§4.11.4)
// ---------------------------------------------------------------------------

/// Computes the device-scoped lookup tag for a specific epoch.
///
/// [rendezvousSecret] — 32-byte pairwise secret from [derivePairwiseSecret]
/// [epochString] — e.g. "2026-06-28-12" (UTC, 6h boundary)
/// [publisherDeviceIdHex] — deviceId of the publishing device (hex)
Uint8List computeLookupTag(
  Uint8List rendezvousSecret,
  String epochString,
  String publisherDeviceIdHex,
) {
  final info = '$epochString/${publisherDeviceIdHex.toLowerCase()}';

  return SodiumFFI().hkdfSha256(
    rendezvousSecret,
    salt: Uint8List.fromList(utf8.encode(_tagSalt)),
    info: Uint8List.fromList(utf8.encode(info)),
    length: 32,
  );
}

/// Derives a deterministic secp256k1 secret key for Nostr publishing
/// per contact×device combination (§4.11.6).
Uint8List deriveNostrSecretKey(
  Uint8List rendezvousSecret,
  Uint8List ownDeviceId,
) {
  final deviceHex = ownDeviceId
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return SodiumFFI().hkdfSha256(
    rendezvousSecret,
    salt: Uint8List.fromList(utf8.encode(_nostrKeySalt)),
    info: Uint8List.fromList(utf8.encode(deviceHex)),
    length: 32,
  );
}

// ---------------------------------------------------------------------------
// Infrastructure Rendezvous (§4.11.9)
// ---------------------------------------------------------------------------

/// Computes the network-wide infrastructure lookup tag for an epoch.
Uint8List computeInfraTag(Uint8List networkSecret, String epochString) {
  return SodiumFFI().hkdfSha256(
    networkSecret,
    salt: Uint8List.fromList(utf8.encode(_infraTagSalt)),
    info: Uint8List.fromList(utf8.encode(epochString)),
    length: 32,
  );
}

/// Derives the encryption key for infrastructure endpoint records.
Uint8List deriveInfraKey(Uint8List networkSecret, String epochString) {
  return SodiumFFI().hkdfSha256(
    networkSecret,
    salt: Uint8List.fromList(utf8.encode(_infraKeySalt)),
    info: Uint8List.fromList(utf8.encode(epochString)),
    length: 32,
  );
}

/// Derives a deterministic secp256k1 secret key for Nostr infra publishing
/// per device (§4.11.9).
Uint8List deriveInfraNostrSecretKey(
    Uint8List networkSecret, Uint8List deviceId) {
  final deviceHex =
      deviceId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return SodiumFFI().hkdfSha256(
    networkSecret,
    salt: Uint8List.fromList(utf8.encode(_infraNostrSalt)),
    info: Uint8List.fromList(utf8.encode(deviceHex)),
    length: 32,
  );
}

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

/// Derives the encryption key for binary-distribution records scoped to a
/// single-use invite nonce (out-of-band physical transfer / QR flow).
Uint8List deriveInviteBinaryKey(
    Uint8List networkSecret, Uint8List inviteNonce) {
  final nonceHex =
      inviteNonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return SodiumFFI().hkdfSha256(
    networkSecret,
    salt: Uint8List.fromList(utf8.encode(_inviteBinarySalt)),
    info: Uint8List.fromList(utf8.encode(nonceHex)),
    length: 32,
  );
}
