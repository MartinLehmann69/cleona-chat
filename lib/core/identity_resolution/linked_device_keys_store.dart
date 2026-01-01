// §7.1 LD-7: Encrypted persistence for Linked-Device delegation keys.
//
// Stored per-identity in `<profileDir>/linked_device_keys.json.enc`.
// Uses the same XSalsa20-Poly1305 file encryption as the rest of the
// profile (db.key keyed) — crash-atomic write via FileEncryption.
//
// Only written on Linked Devices; the file does not exist on Primary devices.

import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/identity_resolution/device_delegation.dart';
import 'package:cleona/core/identity_resolution/linked_device_keys.dart';
import 'package:cleona/core/network/clogger.dart';

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
  static const String _filename = 'linked_device_keys.json';

  static LinkedDeviceKeys? load({
    required String profileDir,
    required FileEncryption fileEnc,
  }) {
    final path = '$profileDir/$_filename';
    final json = fileEnc.readJsonFile(path);
    if (json == null) return null;

    try {
      final certProtoHex = json['delegationCertProto'] as String;
      final certBytes = _unhex(certProtoHex);
      final cert = DeviceDelegation.fromProtoBytes(certBytes);

      return LinkedDeviceKeys(
        delegatedEd25519Pk: _unhex(json['delegatedEd25519Pk'] as String),
        delegatedEd25519Sk: _unhex(json['delegatedEd25519Sk'] as String),
        delegatedMlDsaPk: _unhex(json['delegatedMlDsaPk'] as String),
        delegatedMlDsaSk: _unhex(json['delegatedMlDsaSk'] as String),
        userX25519Sk: _unhex(json['userX25519Sk'] as String),
        userMlKemSk: _unhex(json['userMlKemSk'] as String),
        delegationCert: cert,
        userId: _unhex(json['userId'] as String),
        displayName: json['displayName'] as String,
      );
    } catch (e) {
      CLogger.get('linked-keys').error('Failed to parse $path: $e');
      return null;
    }
  }

  static void save({
    required String profileDir,
    required FileEncryption fileEnc,
    required LinkedDeviceKeys keys,
  }) {
    final path = '$profileDir/$_filename';
    fileEnc.writeJsonFile(path, {
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
