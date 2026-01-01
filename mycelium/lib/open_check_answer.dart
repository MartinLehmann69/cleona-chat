/// The neighbours' half of the open check (V4.2 §8.1 "Is the family
/// open?", `open_check.dart`).
///
/// ── THE FIXED NEIGHBOUR: `0x48` ──────────────────────────────────────
///
/// * Only for a device registered here (`code_table.dart`), recognised by
///   the address the `0x48` came from; anybody else gets nothing.
/// * At most once per [kOpenAnswerEvery] per device.
/// * The target is the address it SAW the `0x48` come from — never one the
///   device claims; only the port number comes from the device.
/// * `0x49` goes to ONE other open neighbour (§5.2) — not the asker, with a
///   confirmed address in the asker's family and outside the own segment,
///   so that nothing in between is left out.
///
/// ── THE OTHER NEIGHBOUR: `0x49` ──────────────────────────────────────
///
/// * Only from a node in this node's neighbourhood (§11.8), under the
///   address it is held by.
/// * Sends `0x4A` with the 16 bytes exactly once to the named address and
///   port, at most once per [kOpenAnswerEvery] per target address.
///
/// ── WHY NOBODY CAN AIM IT ────────────────────────────────────────────
///
/// One packet in, one on, one out, none larger than the question. The
/// target is the asker's own observed address, so the check can neither
/// amplify nor be aimed at a third party by a device; a neighbour that
/// names a foreign address in `0x49` gets one 17-byte packet to it per
/// minute — what it could send itself.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;
import 'package:mycelium/outside_route.dart' show kIdentifierLength;

/// At most one answer per device, and one `0x4A` per target address.
const Duration kOpenAnswerEvery = Duration(minutes: 1);

class OpenCheckAnswer {
  final Node _k;

  /// Changeable ONLY for tests.
  DateTime Function() now = DateTime.now;

  /// Whether a helper's address lies outside the own segment — different
  /// only for probes on 127.0.0.1.
  bool Function(InternetAddress a) outside = fromOutsideReachable;

  /// Whether the `0x4A` to [address]:[port] is lost on the way. In the
  /// product nothing is dropped here; probes on 127.0.0.1, where no firewall
  /// exists, replace it to play one (the same pattern as [now]).
  bool Function(InternetAddress address, int port) droppedOnTheWay =
      _nothingDropped;

  static bool _nothingDropped(InternetAddress address, int port) => false;

  /// ONLY for observation: a `0x4A` leaves for [address]:[port].
  void Function(InternetAddress address, int port)? onTry;

  final Map<String, DateTime> _answered = {};
  final Map<String, DateTime> _tried = {};

  /// Counters for probes and the network statistics (§25) — read only.
  int passedOn = 0;
  int tried = 0;
  int droppedNotRegistered = 0;
  int droppedRate = 0;
  int droppedNoHelper = 0;
  int droppedNotNeighbour = 0;

  OpenCheckAnswer(this._k);

  /// `0x48` and `0x49` at the data port. A `0x4A` belongs to an untouched
  /// port and is dropped here.
  void receive(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.isEmpty) return;
    switch (packet[0]) {
      case kinds.kIsMyFamilyOpen:
        _onAsk(packet, from, fromPort);
      case kinds.kTryFromHere:
        _onTry(packet, from, fromPort);
    }
  }

  void _onAsk(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.length != 3 + kIdentifierLength) return;
    final device = _k.codeRoute.table.deviceAt(from, fromPort);
    if (device == null) {
      droppedNotRegistered++;
      return;
    }
    final t = now();
    _answered.removeWhere((_, v) => t.difference(v) >= kOpenAnswerEvery);
    if (_answered.containsKey(device)) {
      droppedRate++;
      return;
    }
    final helper = _helper(from, fromPort, t);
    if (helper == null) {
      droppedNoHelper++;
      _k.report('Open check for ${from.address}:$fromPort: no other open '
          'neighbour in its family — not answered (§8.1)');
      return;
    }
    _answered[device] = t;
    final port = packet[1] | (packet[2] << 8);
    final b = BytesBuilder()..addByte(kinds.kTryFromHere);
    addressWrite(b, CardAddress(Uint8List.fromList(from.rawAddress), port));
    b.add(Uint8List.sublistView(packet, 3));
    _k.outsideRoute.send(b.toBytes(), helper.address, helper.port);
    passedOn++;
  }

  /// One other open neighbour with a confirmed address in the asker's
  /// family, outside the own segment; never the asker.
  NeighbourAddress? _helper(InternetAddress from, int fromPort, DateTime t) {
    final notBefore = t.subtract(Neighbourhood.staleAfter);
    for (final n in _k.neighbourhood.openSet()) {
      if (n.has(from, fromPort)) continue;
      final a = n.confirmedIn(from.type, notBefore);
      if (a == null || !outside(a.address)) continue;
      if (a.address.address == from.address && a.port == fromPort) continue;
      return a;
    }
    return null;
  }

  void _onTry(Uint8List packet, InternetAddress from, int fromPort) {
    // Only from a node in this node's neighbourhood, under the address it
    // is held by — a stranger cannot make this node send.
    if (_k.neighbourhood.holding(from, fromPort) == null) {
      droppedNotNeighbour++;
      return;
    }
    final t = now();
    var at = 1;
    Uint8List read(int length) {
      if (at + length > packet.length) throw const FormatException('short');
      final r = Uint8List.sublistView(packet, at, at + length);
      at += length;
      return r;
    }

    final CardAddress target;
    final Uint8List nonce;
    try {
      target = addressRead(read, '0x49 target');
      nonce = read(kIdentifierLength);
    } on Object catch (_) {
      return; // unparseable: no answer (§11.6)
    }
    if (at != packet.length || target.port == 0) return;
    final address = InternetAddress.fromRawAddress(target.address);
    if (!_k.speaks(address)) return;
    _tried.removeWhere((_, v) => t.difference(v) >= kOpenAnswerEvery);
    if (_tried.containsKey(address.address)) {
      droppedRate++;
      return;
    }
    _tried[address.address] = t;
    tried++;
    onTry?.call(address, target.port);
    if (droppedOnTheWay(address, target.port)) return;
    final open = Uint8List(1 + kIdentifierLength)
      ..[0] = kinds.kOpen
      ..setRange(1, 1 + kIdentifierLength, nonce);
    _k.outsideRoute.send(open, address, target.port);
  }
}
