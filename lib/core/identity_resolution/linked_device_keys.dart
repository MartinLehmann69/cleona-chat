import 'dart:typed_data';
import 'package:cleona/core/identity_resolution/device_delegation.dart';

/// §7.1 LD-2/LD-3: Key material that a Linked Device stores after pairing.
/// Separate file to avoid circular imports (identity_context ↔ device_pairing_service).
class LinkedDeviceKeys {
  final Uint8List delegatedEd25519Pk;
  final Uint8List delegatedEd25519Sk;
  final Uint8List delegatedMlDsaPk;
  final Uint8List delegatedMlDsaSk;
  final Uint8List userX25519Sk;
  final Uint8List userMlKemSk;
  final DeviceDelegation delegationCert;
  final Uint8List userId;
  final String displayName;

  LinkedDeviceKeys({
    required this.delegatedEd25519Pk,
    required this.delegatedEd25519Sk,
    required this.delegatedMlDsaPk,
    required this.delegatedMlDsaSk,
    required this.userX25519Sk,
    required this.userMlKemSk,
    required this.delegationCert,
    required this.userId,
    required this.displayName,
  });
}
