// §7.1 LD-7: the storage of the linked-device delegation keys.
//
// S366: until now it lay as `linked_device_keys.json.enc` per identity in
// the profile, written via `FileEncryption`. Now in the encrypted
// storage (§21.4, area `linked_device_keys`) — the same seed-derived key,
// but ONE carrier for everything that belongs to an identity.
//
// WHAT LIES HERE, AND WHY THE LATCH BELOW THROWS. The record carries the
// DELEGATED signature secret keys of this device (Ed25519 + ML-DSA) AND
// the secret keys of the user's KEM side (X25519 + ML-KEM). On a linked
// device they are the only copy: the master seed lies with the primary,
// they cannot be recomputed from it here (HKDF subkeys, delivered at
// enrolment, §14.6). If the record is lost, this device can no longer
// sign anything and no longer decrypt anything — and the only way back
// is a renewed enrolment at the primary.
//
// Only present on linked devices; on a primary the area is empty.

import 'dart:typed_data';

import 'package:cleona/core/identity/device_delegation.dart';
import 'package:cleona/core/identity/linked_device_keys.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/storage/message_store.dart';

String _hex(Uint8List b) {
  final sb = StringBuffer();
  for (final byte in b) {
    sb.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List _unhex(String s) {
  final bytes = Uint8List(s.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

class LinkedDeviceKeysStore {
  /// The area in the table `state`.
  static const String area = 'linked_device_keys';

  /// The ONE record. A device either is a linked device or not; there is
  /// no second delegation on the side.
  static const String key = '_';

  /// Loads the delegation keys, or `null` on a primary.
  ///
  /// ── THE DATA-LOSS LATCH THAT NEVER EXISTED HERE ──────────────────
  ///
  /// The previous version caught EVERY error on unpacking, wrote a line
  /// into the log and returned `null`. But at this place `null` does not
  /// mean "broken" but **"this device is a primary"** — the only caller
  /// (`CleonaService.startService`) then skips `applyLinkedDeviceKeys` and
  /// continues with its own keys, which a linked device does not have at
  /// all. A read error thus became a silent role change; the device
  /// seemingly ran, but signed with a key that no contact knows, and the
  /// delegated copy was overwritten at the next [save].
  ///
  /// The latch now measures on the carrier: if the area holds rows
  /// (`countArea`) from which nevertheless no record can be built, it
  /// THROWS. An empty area stays `null` — that is the primary, and that is
  /// the normal case.
  ///
  /// The failure is closed: if the storage itself throws, nobody here
  /// catches it.
  static LinkedDeviceKeys? load({
    required String profileDir,
    required MessageStore store,
  }) {
    final present = store.countArea(area);
    final line = store.loadArea(area)[key];

    if (line == null) {
      if (present > 0) {
        throw StateError(
            'LinkedDeviceKeysStore: the area `$area` holds $present '
            'row(s), but no readable record — there is NO fallback to '
            '"this device is a primary". The '
            'delegated signature subkeys and the user KEM SK are on '
            'a linked device the only copy (§7.1 LD-7); a '
            'silent role change would let the device sign with a key '
            'that no contact knows.');
      }
      return null; // Primary — no record, no error.
    }

    try {
      final certProtoHex = line['delegationCertProto'] as String;
      final certBytes = _unhex(certProtoHex);
      final cert = DeviceDelegation.fromProtoBytes(certBytes);

      return LinkedDeviceKeys(
        delegatedEd25519Pk: _unhex(line['delegatedEd25519Pk'] as String),
        delegatedEd25519Sk: _unhex(line['delegatedEd25519Sk'] as String),
        delegatedMlDsaPk: _unhex(line['delegatedMlDsaPk'] as String),
        delegatedMlDsaSk: _unhex(line['delegatedMlDsaSk'] as String),
        userX25519Sk: _unhex(line['userX25519Sk'] as String),
        userMlKemSk: _unhex(line['userMlKemSk'] as String),
        delegationCert: cert,
        userId: _unhex(line['userId'] as String),
        displayName: line['displayName'] as String,
      );
    } catch (e) {
      // The row is there and could be unpacked, but its CONTENT does not
      // fit (missing field, broken certificate). That is not a primary
      // either — and here too there is no falling back.
      CLogger.get('linked-keys', profileDir: profileDir)
          .error('Record in `$area` unreadable: $e');
      throw StateError(
          'LinkedDeviceKeysStore: the record in the area `$area` could '
          'not be evaluated ($e) — there is NO fallback to "Primary" '
          '(§7.1 LD-7).');
    }
  }

  /// Writes the ONE record.
  ///
  /// `putEntry` and not `replaceArea`: the area holds exactly one row, and
  /// `replaceArea` would first delete it completely — an abort in between
  /// would leave the device without its only key copy.
  static void save({
    required String profileDir,
    required MessageStore store,
    required LinkedDeviceKeys keys,
  }) {
    store.putEntry(area, key, {
      'delegatedEd25519Pk': _hex(keys.delegatedEd25519Pk),
      'delegatedEd25519Sk': _hex(keys.delegatedEd25519Sk),
      'delegatedMlDsaPk': _hex(keys.delegatedMlDsaPk),
      'delegatedMlDsaSk': _hex(keys.delegatedMlDsaSk),
      'userX25519Sk': _hex(keys.userX25519Sk),
      'userMlKemSk': _hex(keys.userMlKemSk),
      'delegationCertProto': _hex(keys.delegationCert.toProtoBytes()),
      'userId': _hex(keys.userId),
      'displayName': keys.displayName,
    });
  }
}
