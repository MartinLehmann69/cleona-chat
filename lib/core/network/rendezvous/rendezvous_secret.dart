/// Pairwise Rendezvous Secret derivation and Lookup Tag computation.
///
/// Architecture §4.11.3 (Pairwise Secret) + §4.11.4 (Lookup Tag & Epoch).
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

/// Computes the lookup tag for a specific epoch + direction.
///
/// [rendezvousSecret] — 32-byte pairwise secret from [derivePairwiseSecret]
/// [epochString] — e.g. "2026-06-28-12" (UTC, 6h boundary)
/// [publisherUserIdHex] — userId of the publishing side
/// [resolverUserIdHex] — userId of the resolving side
Uint8List computeLookupTag(
  Uint8List rendezvousSecret,
  String epochString,
  String publisherUserIdHex,
  String resolverUserIdHex,
) {
  final direction = publisherUserIdHex.toLowerCase()
              .compareTo(resolverUserIdHex.toLowerCase()) <
          0
      ? '0'
      : '1';
  final info = '$epochString/$direction';

  return SodiumFFI().hkdfSha256(
    rendezvousSecret,
    salt: Uint8List.fromList(utf8.encode(_tagSalt)),
    info: Uint8List.fromList(utf8.encode(info)),
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
