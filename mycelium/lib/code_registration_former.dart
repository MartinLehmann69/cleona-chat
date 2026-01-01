/// The code registration with the FORMER fixed neighbours after a recovery
/// (V4.2 §13.2.1 since `44bdea4c`, D-70, owner 21.10.2026; §8.1).
///
/// "At the takeover the recovering device forms `K_AB` and the codes of every
/// restored contact from the bundle (§13.3.2) and registers them (§8.1) with
/// its fixed neighbours and with the former fixed neighbours the bundle
/// names, until that contact is anchored".
///
/// A restored contact keeps sending step 3 to the fixed neighbours the lost
/// device told it last (§8.1 "as the recipient last told them", §9.2) — the
/// former ones. They learn the new device only from a registration, as after
/// a move (§11.8.9). So at every edge of §8.1 ([CodeRoute.edge]) each former
/// fixed neighbour the application names ([registerAlso]) gets its own
/// `0x24` pieces, answered with `0x25` and repeated by the transport like
/// those to a fixed neighbour (`code_registration_send.dart`, §11.3a).
///
///  * **What.** Only the codes of the contacts still waiting
///    ([waitingCodes], `mailbox_recovery_pairs.dart`) — the norm names
///    those, and an anchored contact learns the new fixed neighbours with
///    the first acknowledgement (§9.2).
///  * **Until when.** The application decides at each edge: while a
///    restored contact waits and at most 7 days after the takeover — the
///    same list the collection edge asks (`collectAlso`,
///    `cleona_service_recovery_bundle.dart`). An empty list ends it.
///  * **Idle: nothing.** No clock of its own; only the edges of §8.1.
///
/// A former fixed neighbour that is a fixed neighbour again gets the whole
/// list as one; it is not asked twice.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/neighbour.dart';
import 'package:mycelium/node_codes.dart' show CodeRoute;

/// Owner → its former fixed neighbours, read at each edge.
final _also = Expando<Map<Object, List<(InternetAddress, int)> Function()>>(
    'former fixed neighbours');

/// `address:port` → the neighbour that stands for it (a stable id per run:
/// its registration round and what it confirmed are kept by that id).
final _targets = Expando<Map<String, Neighbour>>('former fixed neighbours as targets');

final _waiting = Expando<List<Uint8List> Function(int day)>(
    'codes of restored contacts');

extension CodeRouteFormer on CodeRoute {
  /// [owner]'s former fixed neighbours from now on — asked at every edge;
  /// `null` removes them.
  void registerAlso(Object owner, List<(InternetAddress, int)> Function()? also) {
    final m = _also[this] ??= {};
    also == null ? m.remove(owner) : m[owner] = also;
  }

  /// The codes of the restored contacts that wait, on a UTC day — set by
  /// the host over all its mailboxes (`host_codes.dart`).
  set waitingCodes(List<Uint8List> Function(int day) codes) =>
      _waiting[this] = codes;

  /// What a former fixed neighbour is told on [day].
  List<Uint8List> waitingCodesAt(int day) => _waiting[this]?.call(day) ?? const [];

  /// The former fixed neighbours to register with now, none of them among
  /// [fixed] — each as a [Neighbour] that keeps its id across edges.
  List<Neighbour> formerTargets(List<Neighbour> fixed) {
    final known = _targets[this] ??= {};
    final now = <String, Neighbour>{};
    for (final f in [...?_also[this]?.values]) {
      for (final (a, port) in f()) {
        if (port < 1 || port > 0xFFFF || fixed.any((n) => n.has(a, port))) continue;
        final key = '${a.address}:$port';
        now[key] = known[key] ?? Neighbour(a, port, kUnconfirmed);
      }
    }
    known
      ..clear()
      ..addAll(now);
    return [...now.values];
  }

  /// Whether [n] stands for a former fixed neighbour ([formerTargets]).
  bool isFormerTarget(Neighbour n) =>
      _targets[this]?.values.any((t) => t.id == n.id) ?? false;
}
