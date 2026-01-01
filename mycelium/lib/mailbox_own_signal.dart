/// The mirror of a call signal to the other own devices (V4.2 §14.7, §17.2,
/// D-46): the device a call signal reaches passes it on at once to each
/// other own device on ladder steps 1 and 3 only.
///
/// ```
/// own line (twin sync)   step 4 only    one deposit per other device
/// call signal's mirror   steps 1 and 3  under ring(A→B, d), never a post box
/// ```
///
/// Step 1 goes to the other device's segment address, step 3 through that
/// device's fixed neighbours under the own-device code `ring(this → it, d)`
/// (`own_ring.dart`), which it registered like a contact's code (§8.1). A
/// mirror is a [Target.signal]: no proof of work, no holder, no history
/// entry, nothing sent again at an edge — it rings within the seconds of its
/// steps or not at all. Twin sync carries no acknowledgement (§9.2,
/// `message.dart` sends no `0x11` to the own identity), so its step 1
/// expects no answer and leaves once.
///
/// ── WHERE A SIBLING IS ───────────────────────────────────────────────────
///
/// "Every own-line deposit carries, sealed, the depositing device's fixed
/// neighbours and its segment addresses" (§14.7). The application carries
/// them in the twin-sync envelope it seals ([ownWhereHere] → [ownWhereWire]),
/// reads them back ([ownWhereRead]) and hands them in per DeviceID
/// ([ownWhereTake]); it keeps them with its device records. This layer keeps
/// them in memory only, next to the identity, like the own line itself.
/// "A change of fixed neighbours with no deposit pending costs one deposit
/// per other own device": [ownWhereWatch] tells the application that edge.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/identity.dart';
import 'package:mycelium/ladder.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/memory.dart' show Reader;
import 'package:mycelium/neighbour_list.dart';
import 'package:mycelium/node_helpers.dart' show interfaces;
import 'package:mycelium/own_address.dart' show announced, rankTheAddress;
import 'package:mycelium/own_line.dart';
import 'package:mycelium/own_ring.dart';
import 'package:mycelium/pair.dart' show utcDay;

/// Where an own device is reachable: its fixed neighbours (step 3) and its
/// segment addresses (step 1).
typedef OwnWhere = ({List<CardAddress> neighbours, List<CardAddress> segment});

final Expando<Map<String, OwnWhere>> _where = Expando('ownWhere');
final Expando<List<CardAddress>> _watched = Expando('ownWhereWatched');

/// What [i] knows of where its other own devices are, by DeviceID (hex).
Map<String, OwnWhere> ownWhereOf(Identity i) => _where[i] ??= {};

extension MailboxOwnSignal on Mailbox {
  /// Where THIS device is reachable for its siblings: the fixed neighbours
  /// it names (`MailboxPair.ownNeighbours`) and its segment addresses.
  OwnWhere ownWhereHere() => (
        neighbours: neighbourListClean(ownNeighbours),
        segment: ownSegmentAddresses(interfaces, node.port),
      );

  /// Takes where the own device [device] is — from its deposit, or from the
  /// application's records at start. Lists of more than three are cut.
  void ownWhereTake(Uint8List device, OwnWhere where) {
    if (device.length != kDeviceIdLength) {
      throw ArgumentError('a DeviceID is $kDeviceIdLength B');
    }
    ownWhereOf(identity)[_hex(device)] = (
      neighbours: neighbourListClean(where.neighbours),
      segment: neighbourListClean(where.segment),
    );
  }

  /// Calls [changed] whenever the fixed neighbours this device names change
  /// (a removal or a confirmation that changes the list) — the edge at which
  /// the application deposits once per other own device (§14.7). Once per
  /// mailbox; a second call replaces nothing and adds nothing.
  void ownWhereWatch(void Function() changed) {
    if (_watched[identity] != null) return;
    _watched[identity] = ownWhereHere().neighbours;
    void check() {
      final now = ownWhereHere().neighbours;
      if (neighbourListEqual(now, _watched[identity]!)) return;
      _watched[identity] = now;
      changed();
    }

    node.neighbourhood.observe(removed: (_) => check(), onConfirmed: (_) => check());
  }

  /// Mirrors [content] to each own device of [toDevices] (default: every
  /// other own device) on steps 1 and 3 — see the file header. Returns to
  /// how many devices at least one step went out; `0` without an active
  /// line. A device whose whereabouts this one does not know yet is skipped
  /// and reported: without an address and a neighbour there is no step to
  /// take, and the post box would ring for nobody.
  int ownSignal(Uint8List content, {List<Uint8List>? toDevices}) {
    final line = ownLineOf(identity);
    if (line == null || !line.active) {
      report?.call('own signal: line inactive — nothing sent');
      return 0;
    }
    final kOwn = ownKey(identity.postBox);
    final day = utcDay(node.codeRoute.now());
    var sent = 0;
    for (final device in toDevices ?? line.others) {
      if (!line.others.any((o) => _same(o, device))) {
        report?.call('own signal: ${_short(device)} is not another own '
            'device — skipped');
        continue;
      }
      final where = ownWhereOf(identity)[_hex(device)];
      final lan = where?.segment.where((a) => node.ladder.speaks(a)).firstOrNull;
      final target = Target(
        lan: lan,
        neighbour: where?.neighbours.firstOrNull,
        neighbours: where?.neighbours ?? const [],
        code: ringCode(kOwn, line.device, device, day),
        postBoxApplicable: false,
        signal: true,
      );
      if (target.empty) {
        report?.call('own signal: no segment address and no fixed neighbour '
            'known for ${_short(device)} — not carried (§17.2)');
        continue;
      }
      // Sealed per device, as on the own line: one envelope to several
      // devices would tell a forwarder that they belong together.
      node.ladder.send(ownLinePacket(identity.postBox, content), target);
      sent++;
    }
    report?.call('own signal: mirrored to $sent own device(s), steps 1 and 3');
    return sent;
  }
}

/// The segment addresses of THIS device with [port]: the best address of
/// each family (`rankTheAddress`), from the interfaces that may be named to
/// others (`announced`). At most one per family.
List<CardAddress> ownSegmentAddresses(
    List<NetworkInterface> interfaces, int port) {
  final best = <int, (int, InternetAddress)>{};
  for (final s in interfaces.where(announced)) {
    for (final a in s.addresses) {
      final r = rankTheAddress(a);
      if (r < 0) continue;
      final held = best[a.rawAddress.length];
      if (held == null || r > held.$1) best[a.rawAddress.length] = (r, a);
    }
  }
  return [
    for (final e in best.values)
      CardAddress(Uint8List.fromList(e.$2.rawAddress), port),
  ];
}

/// A list of up to three addresses as it travels in the twin-sync envelope:
/// the neighbour-list codec (`neighbour_list.dart`), with record keys.
Uint8List ownWhereWire(List<CardAddress> list) {
  final b = BytesBuilder();
  neighbourListWrite(b, neighbourListClean(list), withKeys: true);
  return b.toBytes();
}

/// Counterpart to [ownWhereWire]; an empty or broken field is no list.
List<CardAddress> ownWhereRead(Uint8List wire) {
  if (wire.isEmpty) return const [];
  try {
    final l = Reader(wire);
    final list = neighbourListRead(l.bytes, 'own where', withKeys: true);
    l.done();
    return list;
  } on Object {
    return const [];
  }
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

String _short(Uint8List b) => _hex(b).substring(0, 8);
