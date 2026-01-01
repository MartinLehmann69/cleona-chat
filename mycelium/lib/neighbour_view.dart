/// The neighbour list as it stands, for diagnostics and the tests (IPC
/// `get_neighbours`, S411). Read only, no packet. It is never shown on the
/// screen: §25.7 forbids address and node identifier there, and the row of
/// §25.7 is built elsewhere (`NeighbourRow`).
library;

import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_call.dart';
import 'package:mycelium/node_helpers.dart' show hexFrom;

/// The state of [a] (§11.8.1). `removed` is not here: a removed address has
/// left the list ([neighbourView] names those apart).
String addressState(NeighbourAddress a, DateTime now, Duration staleAfter) =>
    !a.confirmedEver
        ? 'hint'
        : now.difference(a.last) >= staleAfter
            ? 'stale'
            : 'confirmed';

/// The list of [k] at [now]: per neighbour its addresses with state, stamp and
/// whether they answered since this start or the last network change, and the
/// node identifier they named in an answer. A removed address belongs to no
/// neighbour any more; those stand beside the list, with the time of removal.
Map<String, Object?> neighbourView(Node k, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final r = k.readiness;
  Map<String, Object?> one(NeighbourAddress a) => {
        'address': a.address.address,
        'port': a.port,
        'state': addressState(a, at, Neighbourhood.staleAfter),
        'stamp': a.confirmedEver ? a.last.toIso8601String() : null,
        'answeringSinceStart': a.answering,
        'node': r.nodeNamedBy(a.key),
      };
  return {
    'ownNode': hexFrom(k.nodeIdentifier),
    'respondingCount': r.respondingCount,
    'state': r.state.name,
    'neighbours': [
      for (final n in k.neighbourhood.all)
        {
          'fixed': n.seated,
          'answering': n.addresses.any((a) => a.answering),
          'addresses': [for (final a in n.addresses) one(a)],
        }
    ],
    // Where the devices whose fixed neighbour this node is last registered.
    'registeredDevices': [
      for (final (a, p) in k.codeRoute.table.registeredAt) '${a.address}:$p'
    ],
    // This device's own code (§8.1) and, per registration here, the device's
    // code with where and when it last registered (S418): behind address
    // translation the address does not name the device.
    'ownDevice': hexFrom(k.devicesCode),
    'registrations': [
      for (final (device, a, p, last) in k.codeRoute.table.registrations)
        {'device': device, 'at': '${a.address}:$p', 'last': last.toIso8601String()}
    ],
    'removed': [
      for (final e in r.dropped.entries)
        {'key': e.key, 'state': 'removed', 'at': e.value.toIso8601String()}
    ],
  };
}
