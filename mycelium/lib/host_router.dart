/// The host's router mapping and pinhole (v4_2 §7.3, §11.4, §11.8.2;
/// S408-LEBENSLAUF P15, finding A-4).
///
/// Until P15 the app seam held the mapping beside the host (an `Expando` in
/// `mycelium_seam.dart`), every start path asked it at start and laid it down
/// at stop, and the seam wrote the keep-alive flags (§8.1) and the own public
/// address (§7.3) of the delivery layer from above — a second writer of the
/// delivery layer's state. Now the host holds it: it is asked at the edges
/// start and network change (§11.8.2: "the router is asked for a mapping"),
/// laid down when the host stops, and only the host's network part reads its
/// proof. Above the seam stays the switch of §12.7 alone ([allowed]).
///
/// No clock of its own: the coordinator's renewal is the third clock of §5.4
/// (`port_mapper.dart`), towards the own router only, never the data port.
library;

import 'dart:async';
import 'dart:io';

import 'package:mycelium/router_mapping.dart';

export 'package:mycelium/router_mapping.dart' show PortMapping;

/// Builds the mapping of a host port — the real one, or a probe's.
typedef RouterMappingBuild = PortMapping Function(
    int port, bool active, void Function(String)? log);

PortMapping _real(int port, bool active, void Function(String)? log) =>
    PortMapping(port: port, active: active, log: log);

class HostRouter {
  final int Function() _port;
  final void Function(String)? _report;

  /// A granted mapping or pinhole: the outer address (§7.3, §11.9).
  final void Function(InternetAddress outside, int port) _granted;

  /// The switch "router mapping" of §12.7, read when the mapping is built;
  /// `null`: this host never asks a router (probes, a host without a
  /// switch).
  bool Function()? allowed;

  /// Replaced by probes, which bring their own gateway.
  RouterMappingBuild build = _real;

  PortMapping? _p;

  HostRouter(this._port, this._granted, [this._report]);

  /// The running mapping, `null` before the first edge or after [layDown].
  PortMapping? get current => _p;

  /// The router granted a mapping or a pinhole that has not expired —
  /// evidence for the board (§11.8a), and per family for the keep-alive.
  bool get proven => _p?.mappingProven ?? false;
  bool get ipv4Proven => _p?.ipv4Proven ?? false;
  bool get ipv6Proven => _p?.ipv6Proven ?? false;

  /// The edges start and network change: built on the first, reset and
  /// asked anew on every later one ([PortMapping.toEdge]). Callers do not
  /// await it — the RFC 6886 backoff takes minutes, and no edge waits.
  Future<void> edge() async {
    final on = allowed;
    if (on == null) return;
    try {
      var p = _p;
      if (p == null) {
        final active = on();
        if (!active) {
          _report?.call('mycelium:port mapping off by setting (§12.7) — '
              'no router is asked');
        }
        p = _p = build(_port(), active, _report);
        p.onMapping = _granted;
      }
      await p.toEdge();
    } catch (e) {
      _report?.call('Port mapping: $e');
    }
  }

  /// MANDATORY when the host stops: the renewal timer would keep the Dart
  /// VM alive for up to an hour. Lays down mapping and pinhole at the router.
  Future<void> layDown() async {
    final p = _p;
    _p = null;
    if (p == null) return;
    try {
      await p.layDown();
    } catch (e) {
      _report?.call('Port mapping (lay down): $e');
    }
  }

  /// The user turned the switch (§12.7): off lays down now ("no mapping or
  /// pinhole is requested"), on asks now, not at the next network change.
  Future<void> switched() async {
    await layDown();
    unawaited(edge());
  }
}
