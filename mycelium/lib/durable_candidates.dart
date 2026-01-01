/// Who a system-channel report is deposited with (v4_2 §16.7 "How a report
/// leaves the device", S426 V2, D-126).
///
/// Every device that answered this node in this run under the address used
/// (§11.8.4) — on the LAN as on the open network. A holder of a system
/// channel is only ever fetched from by a neighbour it named the object to
/// (§16.0), so reachability from outside is no condition here; it only
/// orders: evidenced reachability (§11.8a, the `0x25` byte of D-113) first,
/// then desktops before phones (the class a node stated in `0x53`, §9.4),
/// otherwise the order of the neighbourhood. Whether a candidate holds is
/// its own answer (`0x91`/`0x94`); the contact rule of §16.7 lies over this
/// order (`durableHolderOrder`).
///
/// This replaces the lane-3 order (`bulkHolderOrder`) for the system
/// channels: that one admits only public addresses, which left a single user
/// without a router mapping one holder at most (S426 RCA 73.W2).
library;

import 'package:mycelium/bulk_piece.dart' show BulkClass;
import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/neighbourhood.dart';

/// The candidates, one address per node: the one it answered under in this
/// run (the first such address of the node).
List<CardAddress> durableCandidates(Neighbourhood hood,
    {BulkClass Function(CardAddress holder)? classOf,
    bool? Function(Neighbour n)? evidence}) {
  final order = classOf ?? (_) => BulkClass.unknown;
  final picked = <(int, int, int, CardAddress)>[]; // evidence, class, index
  var i = 0;
  for (final n in hood.all) {
    NeighbourAddress? a;
    for (final x in n.addresses) {
      if (x.answering) {
        a = x;
        break;
      }
    }
    if (a == null) continue;
    final c = a.asCardAddress;
    picked.add((evidence?.call(n) == true ? 0 : 1, order(c).order, i++, c));
  }
  picked.sort((x, y) {
    final e = x.$1.compareTo(y.$1);
    if (e != 0) return e;
    final k = x.$2.compareTo(y.$2);
    return k != 0 ? k : x.$3.compareTo(y.$3);
  });
  return [for (final p in picked) p.$4];
}
