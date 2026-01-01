/// The own-device line (V4.2 §14.7, D-37): twin sync between the devices of
/// ONE identity, over the post box of §8.2 and nothing else.
///
/// ── WHY DEVICE VALUES, NOT THE DAY VALUE ─────────────────────────────────
///
/// All devices of an identity hold the same day keys (§8.2), and a holder
/// deletes a packet after the FIRST collector's acknowledgement. Deposited
/// under the day value, the sending device would collect its own mirror
/// first and delete it — with two devices the other one would never see it
/// (proposal B-4, K1). So each device has values of its own: the post-box
/// value of the Ed25519 pair derived from
/// `HKDF(K_own, "device" ‖ deviceId ‖ d)`, `d` the UTC day. For a holder
/// that is indistinguishable from a day value. Each device asks only its own
/// seven values and deletes after collection like any collector.
///
/// ── K_own ────────────────────────────────────────────────────────────────
///
/// Until the shared key of §14.4 is built,
/// `K_own = HKDF(current identity Ed25519 secret key, "own-line")` (§14.7).
/// The secret key enters as its 32-B seed ([PostBox.daySeed]) — the same
/// input the day keys take; the secret key does not leave [PostBox]. It
/// rotates with the signing keys (lock-out, Emergency Key Rotation), not at
/// adding a device and not at the routine KEM rotation.
///
/// ── NO CLOCK, NO RECEIPT ─────────────────────────────────────────────────
///
/// The questions ride on the collection edges of `node_post_box.dart`
/// (D-9); a device whose line is inactive asks exactly what it asked before.
/// Twin-sync deliveries carry no acknowledgement (§9.2): placed is their
/// final observation (`message.dart` sends no 0x11 to the own identity).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/envelope.dart';
import 'package:mycelium/identity.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/message.dart' show kIdentifierLength, messagePlaintext;
import 'package:mycelium/pair.dart' show dayValue, utcDay;
import 'package:mycelium/post_box_proof.dart'
    show DayPair, Question, kAtMostValues;

/// A DeviceID (§14.1) is 16 bytes — the app's device UUID.
const int kDeviceIdLength = 16;

final SodiumFFI _na = SodiumFFI();

/// What an identity on this node knows of its own devices: [device] is this
/// one, [others] the rest of the set (§14.7: taken from Types 9 and 16).
/// Set by the application (`MailboxOwnLine.ownLineSet`); the delivery layer keeps no
/// device list of its own.
class OwnLine {
  final Uint8List device;
  final List<Uint8List> others;

  OwnLine(Uint8List device, Iterable<Uint8List> others)
      : device = Uint8List.fromList(device),
        others = [
          for (final o in others)
            if (!_same(o, device)) Uint8List.fromList(o),
        ] {
    if (device.length != kDeviceIdLength ||
        this.others.any((o) => o.length != kDeviceIdLength)) {
      throw ArgumentError('a DeviceID is $kDeviceIdLength B');
    }
  }

  /// The line is active only while another own device exists.
  bool get active => others.isNotEmpty;
}

final Expando<OwnLine> _lines = Expando<OwnLine>('ownLine');

/// The own line of [i], or `null` while none was set.
OwnLine? ownLineOf(Identity i) => _lines[i];

/// Sets (or with `null` clears) the own line of [i].
void ownLinePut(Identity i, OwnLine? line) => _lines[i] = line;

/// `K_own` of [me] — see the file header.
Uint8List ownKey(PostBox me) => _na.hkdfSha256(me.daySeed,
    info: Uint8List.fromList(utf8.encode('own-line')), length: 32);

/// The Ed25519 pair of [deviceId] on UTC day [day] under [kOwn].
DayPair devicePair(Uint8List kOwn, Uint8List deviceId, int day) {
  final seed = _na.hkdfSha256(kOwn,
      info: (BytesBuilder()
            ..add(utf8.encode('device'))
            ..add(deviceId)
            ..add(Uint8List(4)..buffer.asByteData().setUint32(0, day)))
          .toBytes(),
      length: 32);
  final p = _na.generateEd25519KeyPairFromSeed(seed);
  return (pk: p.publicKey, sk: p.secretKey);
}

/// The value under which a mirror for [deviceId] is deposited on [day].
Uint8List deviceValue(PostBox me, Uint8List deviceId, int day) =>
    dayValue(devicePair(ownKey(me), deviceId, day).pk);

/// The questions of THIS device of [i]: its values of today and the six days
/// before (§8.2 retention) — one question, or none while the line is
/// inactive. Asked at the same edges as the day values (`node_post_box.dart`).
List<List<Question>> ownLineAsk(Identity i, DateTime now) {
  final line = ownLineOf(i);
  if (line == null || !line.active) return const [];
  final kOwn = ownKey(i.postBox);
  final today = utcDay(now);
  return [
    [
      for (var d = 0; d < kAtMostValues; d++)
        if (devicePair(kOwn, line.device, today - d) case final p)
          (value: dayValue(p.pk), pair: p),
    ],
  ];
}

/// One own-line packet: an ordinary message envelope from [me] to its own
/// address — kind `0x10`, identifier ‖ empty neighbour list ‖ [content]
/// (`message.dart`). The own devices share the identity's keys (§14.2), so
/// every one of them opens it; no fixed neighbours ride along, a device does
/// not name its neighbours to itself.
Uint8List ownLinePacket(PostBox me, Uint8List content) {
  final envelope = Envelope.seal(
    plaintext: messagePlaintext(
        _na.randomBytes(kIdentifierLength), const [], content),
    recipient: me.address,
    sender: me,
  );
  return Uint8List.fromList([kinds.kMessage, ...envelope]);
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
