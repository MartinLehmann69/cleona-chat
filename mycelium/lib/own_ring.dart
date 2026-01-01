/// The own-device code of a call signal's mirror (V4.2 §14.7, §17.2, D-46).
///
/// The device a call signal reaches mirrors it at once to each other own
/// device on ladder steps 1 and 3 only — never through the post box, which
/// would ring for nobody. Step 3 needs a code the other device registered
/// with its fixed neighbours (§8.1). Between own devices there is no pair
/// secret, so the code comes from the own material:
///
/// ```
/// ring(A→B, d) = first 16 B of HKDF(K_own, "ring" ‖ deviceId_A ‖ deviceId_B ‖ d)
/// ```
///
/// `K_own` as for the own line (`own_line.dart`), `d` the UTC day as four
/// bytes big-endian (the same day encoding as the device values there).
/// Every device registers `ring(other → itself, d)` for each other own
/// device like a contact's code ([ownRingInbound], `host_codes.dart`): the
/// neighbour learns codes, never a person or a device set.
///
/// Sending the mirror: `mailbox_own_signal.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/identity.dart';
import 'package:mycelium/own_line.dart';
import 'package:mycelium/pair.dart' show kCodeLength;

final SodiumFFI _na = SodiumFFI();

/// `ring(from → to, day)` under [kOwn] — see the file header.
Uint8List ringCode(Uint8List kOwn, Uint8List from, Uint8List to, int day) {
  if (from.length != kDeviceIdLength || to.length != kDeviceIdLength) {
    throw ArgumentError('a DeviceID is $kDeviceIdLength B');
  }
  final out = _na.hkdfSha256(kOwn,
      info: (BytesBuilder()
            ..add(utf8.encode('ring'))
            ..add(from)
            ..add(to)
            ..add(Uint8List(4)..buffer.asByteData().setUint32(0, day)))
          .toBytes(),
      length: 32);
  return Uint8List.sublistView(out, 0, kCodeLength);
}

/// The codes under which a mirror for THIS device of [i] comes on [day]:
/// `ring(other → this, day)` for every other own device. Empty while the
/// own line is inactive (one device, or none set).
List<Uint8List> ownRingInbound(Identity i, int day) {
  final line = ownLineOf(i);
  if (line == null || !line.active) return const [];
  final kOwn = ownKey(i.postBox);
  return [for (final o in line.others) ringCode(kOwn, o, line.device, day)];
}
