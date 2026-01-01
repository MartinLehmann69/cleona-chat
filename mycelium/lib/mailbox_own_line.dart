import 'dart:typed_data';

import 'package:mycelium/mailbox.dart';
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/own_line.dart';
import 'package:mycelium/pair.dart' show utcDay;
import 'package:mycelium/post_box_deposit.dart' show Neighbour;

/// The own-device line of the mailbox (V4.2 §14.7, §22.5.2, D-37): what the
/// application sends to its own UserID goes out here — one post-box deposit
/// per other own device under that device's value (`own_line.dart`).
///
/// No history, no re-dispatch, no receipt: a twin-sync delivery is placed or
/// not (§9.2), and its duplicate detection is the application's `sync_id`.
/// Stage 4 only — step 2 carries no message (D-4), and a mirror appears at
/// the other device's next collection edge (§8.2).
///
/// Holders: the own holders ranked as for every deposit (§8.2, OP-19). The
/// sender does not know another own device's fixed neighbours; §8.2's first
/// tier is empty here, and the own neighbours are the tier that remains.
extension MailboxOwnLine on Mailbox {
  /// Tells the delivery layer this device ([thisDevice]) and the other own
  /// devices ([others]) — at start and at every change of the device set.
  /// With no other device the line is inactive: nothing is asked, nothing
  /// sent. Setting it is no collection edge of its own (§8.2 names them):
  /// the device values are asked at the next one.
  void ownLineSet(Uint8List thisDevice, Iterable<Uint8List> others) {
    final line = OwnLine(thisDevice, others);
    ownLinePut(identity, line);
    report?.call('own line: ${line.others.length} other own device(s)'
        '${line.active ? '' : ' — inactive'}');
  }

  /// Deposits [content] once per own device of [toDevices] (default: every
  /// other own device, §14.7) under its value of today. Returns how many
  /// deposits were placed (§8.2: two acknowledgements). `0` without an active
  /// line. [withWhom] names the holders instead of the own ranking — for a
  /// probe that must not depend on the network of the test machine.
  Future<int> ownSend(Uint8List content,
      {List<Uint8List>? toDevices, List<Neighbour>? withWhom}) async {
    final line = ownLineOf(identity);
    if (line == null || !line.active) {
      report?.call('own line: inactive — nothing sent');
      return 0;
    }
    final day = utcDay(node.postBoxDeposit.now());
    final to = toDevices ?? line.others;
    var placed = 0;
    for (final device in to) {
      if (!line.others.any((o) => _same(o, device))) {
        report?.call('own line: ${_short(device)} is not another own '
            'device — skipped');
        continue;
      }
      // Sealed per device: one envelope under several values would tell a
      // holder that those values belong together.
      final (done, _) = await node.deposit(
          ownLinePacket(identity.postBox, content),
          deviceValue(identity.postBox, device, day),
          withWhom: withWhom);
      if (done) placed++;
    }
    report?.call('own line: $placed of ${to.length} deposit(s) placed');
    return placed;
  }
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _short(Uint8List b) =>
    b.take(4).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
