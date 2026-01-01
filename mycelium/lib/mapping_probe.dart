/// The device's half of the keep-alive measurement (V4.2 §8.1): how long
/// does the own translator or firewall hold an idle path?
///
/// ── ONE TEST ─────────────────────────────────────────────────────────
///
/// 1. A **probe port** opens — a second UDP socket on a port the operating
///    system picks, with a shell of its own (§4.2, §11.1). It never carries
///    delivery.
/// 2. From it the node asks the neighbour `0x40`. The answer is the
///    CONTROL: without it (a firewall blocks the probe port, the neighbour
///    does not answer) the test says `null` — nothing is known.
/// 3. The probe port stays silent for `T`. Then the node sends `0x45` with
///    the identifier of that `0x40` from its DATA port; the neighbour
///    echoes `0x46` once to where the `0x40` came from
///    (`mapping_echo.dart`). If it arrives within [kEchoDeadline], the
///    mapping held for `T`.
/// 4. The probe port closes. Every test uses a fresh one: a lapsed mapping
///    would come back under another port, and the neighbour's shell would
///    not know it.
///
/// ── THE BISECTION ────────────────────────────────────────────────────
///
/// Over [kProbePoints], starting at 60 s — at most three tests. The
/// result is the index of the longest `T` that held, `-1` if none held.
/// A blocked probe port can therefore only ever leave the defaults: an
/// interval becomes longer only on positive evidence (§8.1).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show interfaces;
import 'package:mycelium/outside_route.dart';
import 'package:mycelium/shell.dart';
import 'package:mycelium/split.dart';
import 'package:mycelium/wire.dart';

/// The points of the bisection (§8.1).
const List<Duration> kProbePoints = [
  Duration(seconds: 20),
  Duration(seconds: 30),
  Duration(seconds: 40),
  Duration(seconds: 60),
  Duration(seconds: 90),
  Duration(seconds: 120),
];

/// How long the echo may take (§8.1).
const Duration kEchoDeadline = Duration(seconds: 5);

/// How long the control may take — including the probe port's handshake.
const Duration kControlDeadline = Duration(seconds: 5);

/// One test: `true` held, `false` lapsed, `null` the control failed.
typedef ProbeTest = Future<bool?> Function(Duration t);

/// The index of the longest point in [points] that held, `-1` if none
/// held; `null` if the control failed before anything held. Pure — the
/// test is passed in.
Future<int?> bisect(List<Duration> points, ProbeTest test) async {
  var held = -1;
  var lapsed = points.length;
  while (lapsed - held > 1) {
    final mid = (held + lapsed + 1) ~/ 2;
    final r = await test(points[mid]);
    if (r == null) return held >= 0 ? held : null;
    if (r) {
      held = mid;
    } else {
      lapsed = mid;
    }
  }
  return held;
}

class MappingProbe {
  final Node _k;
  final List<Duration> points;
  final Duration echoDeadline;
  final Duration controlDeadline;

  final Random _random = Random.secure();
  final Map<Timer, Completer<void>> _silences = {};
  final Set<void Function()> _open = {};
  bool _closed = false;

  /// Counters for probes and the network statistics (§25) — read only.
  int tests = 0;
  int controlsFailed = 0;

  MappingProbe(this._k,
      {this.points = kProbePoints,
      this.echoDeadline = kEchoDeadline,
      this.controlDeadline = kControlDeadline});

  /// Measures towards [target]: see [bisect].
  Future<int?> measure((InternetAddress, int) target) =>
      bisect(points, (t) => holds(target, t));

  /// ONE test with silence [t].
  Future<bool?> holds((InternetAddress, int) target, Duration t) async {
    if (_closed) return null;
    tests++;
    Wire? wire;
    Shell? shell;
    Splitter? splitter;
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      splitter?.close();
      shell?.close();
      wire?.close();
    }

    _open.add(close);
    try {
      wire = await Wire.open(port: 0, interfaces: interfaces, report: (_) {});
      shell = Shell(wire, report: (_) {});
      final identifier = Uint8List.fromList(
          List<int>.generate(kIdentifierLength, (_) => _random.nextInt(256)));
      final echo = Completer<bool>();
      late final OutsideRoute route;
      splitter = Splitter(shell, onShipment: (data, from, fromPort) {
        if (data.isEmpty) return;
        if (data[0] == kinds.kEcho) {
          if (_same(data, identifier) && !echo.isCompleted) echo.complete(true);
        } else {
          route.receive(data, from, fromPort);
        }
      });
      final s = splitter;
      route = OutsideRoute.appended((p, a, port) => s.send(p, a, port));
      final seen = await route.whatIsMyAddress(target.$1, target.$2,
          identifier: identifier, deadline: controlDeadline);
      if (seen == null) {
        controlsFailed++;
        return null;
      }
      await _silence(t);
      if (_closed) return null;
      final request = Uint8List(1 + kIdentifierLength)
        ..[0] = kinds.kEchoRequest
        ..setRange(1, 1 + kIdentifierLength, identifier);
      _k.outsideRoute.send(request, target.$1, target.$2);
      return await echo.future.timeout(echoDeadline, onTimeout: () => false);
    } on Object catch (e) {
      _k.report('Keep-alive measurement: probe port failed ($e)');
      return null;
    } finally {
      _open.remove(close);
      close();
    }
  }

  /// Ends every running test at once — the node stops.
  void close() {
    _closed = true;
    for (final e in List.of(_silences.entries)) {
      e.key.cancel();
      if (!e.value.isCompleted) e.value.complete();
    }
    _silences.clear();
    for (final c in List.of(_open)) {
      c();
    }
    _open.clear();
  }

  Future<void> _silence(Duration t) {
    final c = Completer<void>();
    late final Timer timer;
    timer = Timer(t, () {
      _silences.remove(timer);
      c.complete();
    });
    _silences[timer] = c;
    return c.future;
  }

  static bool _same(Uint8List echo, Uint8List identifier) {
    if (echo.length != 1 + kIdentifierLength) return false;
    for (var i = 0; i < kIdentifierLength; i++) {
      if (echo[1 + i] != identifier[i]) return false;
    }
    return true;
  }
}
