// V4.2 §14.4 "Device side", §14.7 Type 16 DEVICE_SET_CHANGED (S414 phase 2,
// S400 §9 E-c step 2): the key package of one remaining device.
//
// At a lock-out or an Emergency Key Rotation the rotating device places, for
// every remaining own device, ONE package under that device's value in the
// OLD line, sealed against that device's KEM keys — the ones the device set
// of this identity names (§14.9.1; D-101 changes only where they come from).
// A locked-out device sees the deposits and opens none (§14.7).
//
// The package carries what the receiving device needs to continue the
// identity under the new keys: the identity signing secret keys and the user
// KEM secret keys with their public halves, the whole rotation chain (the
// last link signed by the previous keys — the SAME link the rotating device
// keeps, so every device holds the same chain), the reason, and the device
// set after the change.
//
// Wire: magic "CDK\0", version 1, the hybrid KEM header of `PerMessageKem`
// (X25519 + ML-KEM-768) and the AEAD ciphertext of a JSON body. Read only by
// this version; 4.2.3 to 4.2.6 skip Type 16 as unknown (`_handleTwinSync`).

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/identity/identity_context.dart'
    show StoredRotationLink;

const List<int> _kMagic = <int>[0x43, 0x44, 0x4b, 0x00]; // "CDK\0"
const int _kVersion = 1;

/// Why the keys changed (§14.8 `approval_kind` names the same).
enum KeyPackageReason { lockout, emergency }

/// The content of one key package, unsealed.
final class DeviceKeyPackage {
  DeviceKeyPackage({
    required this.reason,
    required this.chain,
    required this.ed25519Sk,
    required this.mlDsaSk,
    required this.x25519Pk,
    required this.x25519Sk,
    required this.mlKemPk,
    required this.mlKemSk,
    required this.remaining,
    required this.atMs,
  });

  final KeyPackageReason reason;

  /// The whole rotation chain, founding first; its last link ends at the new
  /// signing keys.
  final List<StoredRotationLink> chain;
  final Uint8List ed25519Sk;
  final Uint8List mlDsaSk;
  final Uint8List x25519Pk;
  final Uint8List x25519Sk;
  final Uint8List mlKemPk;
  final Uint8List mlKemSk;

  /// The DeviceIDs (hex) of the device set after the change.
  final List<String> remaining;

  /// The rotating device's time of the change.
  final int atMs;

  /// The new signing public keys — the end of [chain].
  Uint8List get ed25519Pk => chain.last.newEd25519Pk;
  Uint8List get mlDsaPk => chain.last.newMlDsaPk;

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode({
        'reason': reason.name,
        'chain': [for (final l in chain) l.toJson()],
        'ed25519Sk': _hex(ed25519Sk),
        'mlDsaSk': _hex(mlDsaSk),
        'x25519Pk': _hex(x25519Pk),
        'x25519Sk': _hex(x25519Sk),
        'mlKemPk': _hex(mlKemPk),
        'mlKemSk': _hex(mlKemSk),
        'remaining': remaining,
        'at': atMs,
      })));

  /// Reads a package body, or `null` if it is not one (never throws). The
  /// key lengths are checked here; whether the keys continue the identity is
  /// the receiver's check.
  static DeviceKeyPackage? read(Uint8List bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final reason = KeyPackageReason.values.byName(j['reason'] as String);
      final chain = [
        for (final l in j['chain'] as List)
          StoredRotationLink.fromJson((l as Map).cast<String, dynamic>())
      ];
      final p = DeviceKeyPackage(
        reason: reason,
        chain: chain,
        ed25519Sk: _bytes(j['ed25519Sk']),
        mlDsaSk: _bytes(j['mlDsaSk']),
        x25519Pk: _bytes(j['x25519Pk']),
        x25519Sk: _bytes(j['x25519Sk']),
        mlKemPk: _bytes(j['mlKemPk']),
        mlKemSk: _bytes(j['mlKemSk']),
        remaining: [for (final r in j['remaining'] as List) r as String],
        atMs: j['at'] as int,
      );
      if (chain.isEmpty ||
          p.ed25519Sk.length != 64 ||
          p.x25519Pk.length != 32 ||
          p.x25519Sk.length != 32 ||
          p.mlKemPk.length != OqsFFI.mlKemPublicKeyLength ||
          p.mlKemSk.length != OqsFFI.mlKemSecretKeyLength ||
          p.mlDsaPk.length != OqsFFI.mlDsaPublicKeyLength) {
        return null;
      }
      return p;
    } catch (_) {
      return null;
    }
  }
}

/// Seals [p] against the device KEM public keys of the receiving device.
Uint8List sealDeviceKeyPackage(DeviceKeyPackage p,
    {required Uint8List x25519Pk, required Uint8List mlKemPk}) {
  final (h, ct) = PerMessageKem.encrypt(
      plaintext: p.encode(),
      recipientX25519Pk: x25519Pk,
      recipientMlKemPk: mlKemPk);
  return (BytesBuilder()
        ..add(_kMagic)
        ..addByte(_kVersion)
        ..add(h.ephemeralX25519Pk)
        ..add(h.mlKemCiphertext)
        ..add(h.aesNonce)
        ..addByte(h.version)
        ..add(ct))
      .toBytes();
}

/// Opens a sealed package with this device's KEM secret keys, or `null` —
/// not a package, not for this device, or bent. Never throws.
DeviceKeyPackage? openDeviceKeyPackage(Uint8List sealed,
    {required Uint8List x25519Sk, required Uint8List mlKemSk}) {
  try {
    const head = 4 + 1 + 32 + OqsFFI.mlKemCiphertextLength + 12 + 1;
    if (sealed.length <= head) return null;
    for (var i = 0; i < 4; i++) {
      if (sealed[i] != _kMagic[i]) return null;
    }
    if (sealed[4] != _kVersion) return null;
    var o = 5;
    Uint8List take(int n) {
      final out = Uint8List.fromList(Uint8List.sublistView(sealed, o, o + n));
      o += n;
      return out;
    }

    final header = KemHeader(
        ephemeralX25519Pk: take(32),
        mlKemCiphertext: take(OqsFFI.mlKemCiphertextLength),
        aesNonce: take(12),
        version: take(1)[0]);
    final clear = PerMessageKem.decrypt(
        kemHeader: header,
        ciphertext: Uint8List.sublistView(sealed, o),
        ourX25519Sk: x25519Sk,
        ourMlKemSk: mlKemSk);
    return DeviceKeyPackage.read(clear);
  } catch (_) {
    return null;
  }
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(Object? hex) {
  final s = hex as String;
  if (s.length.isOdd) throw const FormatException('odd hex');
  return Uint8List.fromList([
    for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)
  ]);
}
