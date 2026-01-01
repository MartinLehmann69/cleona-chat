/// When the keep-alive interval is measured (V4.2 §8.1) — at edges only,
/// never on a clock (§5.4, working rule 5).
///
/// | Edge | What |
/// |---|---|
/// | a neighbour is confirmed (start included) | measure each family not yet measured in this network |
/// | network change | forget what was measured, measure anew |
/// | move report (`0x47`) | the family is back at its default; measure anew unless measured within [kMeasureAgainAfter] |
///
/// Only towards a neighbour reachable from the open network: towards one
/// in the own segment no translator lies in between, and a measurement
/// there would say "holds for ever" about a path nobody needs held.
///
/// A measurement that fails its control (probe port blocked, neighbour
/// does not answer) counts as done for this network: the defaults stand,
/// and the next edge does not try again.
library;

import 'dart:async';
import 'dart:io';

import 'package:mycelium/keep_alive.dart';
import 'package:mycelium/mapping_probe.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;

/// A move report triggers a new measurement only this long after the last.
const Duration kMeasureAgainAfter = Duration(minutes: 30);

class KeepAliveMeasure {
  final Node _k;
  final KeepAlive _o;
  final MappingProbe probe;

  /// Whether a neighbour address lies behind the own translator — different
  /// only for probes on 127.0.0.1.
  bool Function(InternetAddress a) outside = fromOutsideReachable;

  int _network = 0;
  bool _stopped = false;
  final Set<InternetAddressType> _running = {};
  final Map<InternetAddressType, int> _doneIn = {};
  final Map<InternetAddressType, DateTime> _lastAt = {};

  /// Counters for probes and the network statistics (§25) — read only.
  int measurements = 0;

  KeepAliveMeasure(this._k, this._o, {MappingProbe? probe})
      : probe = probe ?? MappingProbe(_k) {
    _o.onFallback = (type) {
      final last = _lastAt[type];
      if (last != null &&
          DateTime.now().difference(last) < kMeasureAgainAfter) {
        return;
      }
      _doneIn.remove(type);
      edge();
    };
  }

  /// Edge network change.
  void networkChanged() {
    _network++;
    _doneIn.clear();
    _o.networkChanged();
    edge();
  }

  /// The node stops: running tests end at once.
  void stop() {
    _stopped = true;
    probe.close();
  }

  /// An edge: measure every family that needs a keep-alive and has not
  /// been measured in this network.
  void edge() {
    if (_stopped) return;
    final now = DateTime.now();
    for (final type in [InternetAddressType.IPv4, InternetAddressType.IPv6]) {
      if (_running.contains(type) || _doneIn[type] == _network) continue;
      final target = _o.targetFor(type, now);
      if (target == null || !outside(target.address)) continue;
      unawaited(_measure(type, (target.address, target.port)));
    }
  }

  Future<void> _measure(
      InternetAddressType type, (InternetAddress, int) target) async {
    _running.add(type);
    final network = _network;
    try {
      _k.report('Keep-alive measurement ${type.name} towards '
          '${target.$1.address}:${target.$2} begins (§8.1)');
      final i = await probe.measure(target);
      if (_stopped || network != _network) return;
      _doneIn[type] = network;
      _lastAt[type] = DateTime.now();
      measurements++;
      if (i == null) {
        _k.report('Keep-alive measurement ${type.name}: no control answer — '
            'the defaults stand');
        return;
      }
      final h = Held(i < 0 ? null : probe.points[i], DateTime.now());
      _o.measured(type, h);
      _k.report('Keep-alive measurement ${type.name}: '
          '${h.longest == null ? "not holdable (below ${probe.points.first.inSeconds} s)" : "held ${h.longest!.inSeconds} s"}'
          ' — interval ${(type == InternetAddressType.IPv4 ? _o.intervalV4 : _o.intervalV6).inSeconds} s'
          '${type == InternetAddressType.IPv4 || !_o.v4Rests(DateTime.now()) ? "" : ", IPv4 rests"}');
    } finally {
      _running.remove(type);
      // The network changed meanwhile: its edge found this family running.
      if (!_stopped && network != _network) edge();
    }
  }
}
