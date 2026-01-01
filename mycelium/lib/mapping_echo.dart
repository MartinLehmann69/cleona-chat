/// The neighbour's half of the keep-alive measurement (V4.2 §8.1) — and
/// the device's reception of a move report.
///
/// ── WHAT THE NEIGHBOUR DOES ──────────────────────────────────────────
///
/// * It remembers every `0x40` it answered: identifier → where it came
///   from ([asked]).
/// * A `0x45` names such an identifier. The neighbour sends `0x46` ONCE
///   to where that `0x40` came from — the probe port of the asking device
///   (`mapping_probe.dart`). If the device's translator still holds the
///   probe port's mapping, the echo arrives; if not, it is dropped on the
///   way. That is the whole measurement.
/// * A keep-alive (cover content `0x04`) names the device code. The code
///   table follows the device to the address it came from
///   (`CodeTable.sighted`); if the address in that family changed, the
///   neighbour reports it ONCE with `0x47` and the keep-alive's token —
///   the mapping lapsed despite the interval.
///
/// ── WHY NOBODY CAN AIM IT ────────────────────────────────────────────
///
/// The echo goes only to an address that asked this neighbour `0x40`
/// itself, once per question, and is exactly as long as the request
/// (17 B, both 1200 B on the wire). The identifier travels inside the
/// shell (§4.2) — only the asker knows it. A move report goes to the
/// address the keep-alive itself came from, at most once a minute per
/// device and family.
library;

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/cover_stream_content.dart' show kKeepAliveContent;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/node.dart';
import 'package:mycelium/outside_route.dart' show kIdentifierLength;
import 'package:mycelium/pair.dart' show kCodeLength;

/// How long an answered `0x40` can be named by an echo request — above
/// the longest test of 120 s (§8.1).
const Duration kAskedLife = Duration(seconds: 180);

/// How many answered `0x40` are remembered; the oldest gives way.
const int kAskedAtMost = 256;

/// At most one move report per device and family in this time.
const Duration kMovedAtMostEvery = Duration(minutes: 1);

/// The token of a keep-alive (§8.1).
const int kTokenLength = 8;

class MappingEcho {
  final Node _k;

  /// Changeable ONLY for tests.
  DateTime Function() now = DateTime.now;

  /// ONLY for probes: plays a translator that lets a mapping lapse after
  /// this time — an echo whose `0x40` is older is not sent.
  Duration? testMappingLife;

  final LinkedHashMap<String, (InternetAddress, int, DateTime)> _asked =
      LinkedHashMap();
  final Map<String, DateTime> _reported = {};

  /// A `0x47` arrived for this node — the token of its own keep-alive.
  void Function(Uint8List token)? onMoved;

  /// Counters for probes and the network statistics (§25) — read only.
  int echoes = 0;
  int movedSent = 0;
  int movedReceived = 0;

  MappingEcho(this._k);

  /// A `0x40` from [from]:[fromPort] was answered (`OutsideRoute.onAsked`).
  void asked(Uint8List identifier, InternetAddress from, int fromPort) {
    final key = _hex(identifier);
    _asked.remove(key);
    _asked[key] = (from, fromPort, now());
    while (_asked.length > kAskedAtMost) {
      _asked.remove(_asked.keys.first);
    }
  }

  /// `0x45` (as neighbour) and `0x47` (as device) — `OutsideRoute.onProbe`.
  /// A `0x46` belongs to a probe port and never reaches the data port.
  void receive(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.isEmpty) return;
    switch (packet[0]) {
      case kinds.kEchoRequest:
        _onRequest(packet, from, fromPort);
      case kinds.kMoved:
        if (packet.length != 1 + kTokenLength) return;
        movedReceived++;
        onMoved?.call(Uint8List.fromList(packet.sublist(1)));
    }
  }

  void _onRequest(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.length != 1 + kIdentifierLength) return;
    final e = _asked.remove(_hex(packet.sublist(1)));
    if (e == null) return; // never asked, already echoed or displaced
    final age = now().difference(e.$3);
    if (age > kAskedLife) return;
    final life = testMappingLife;
    if (life != null && age > life) return;
    final echo = Uint8List(1 + kIdentifierLength)
      ..[0] = kinds.kEcho
      ..setRange(1, 1 + kIdentifierLength, packet, 1);
    _k.outsideRoute.send(echo, e.$1, e.$2);
    echoes++;
  }

  /// A keep-alive (cover content `0x04`) from [from]:[fromPort].
  void keepAlive(Uint8List content, InternetAddress from, int fromPort) {
    if (content.length != kKeepAliveContent) return;
    final device = Uint8List.sublistView(content, 0, kCodeLength);
    if (!_k.codeRoute.table.sighted(device, from, fromPort)) return;
    final t = now();
    _reported.removeWhere((_, v) => t.difference(v) >= kMovedAtMostEvery);
    final who = '${_hex(device)}/${from.type.name}';
    if (_reported.containsKey(who)) return;
    _reported[who] = t;
    final report = Uint8List(1 + kTokenLength)
      ..[0] = kinds.kMoved
      ..setRange(1, 1 + kTokenLength, content, kCodeLength);
    _k.outsideRoute.send(report, from, fromPort);
    movedSent++;
    _k.report('Keep-alive of device ${who.substring(0, 8)} from a new address '
        '${from.address}:$fromPort — move reported (0x47, §8.1)');
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
