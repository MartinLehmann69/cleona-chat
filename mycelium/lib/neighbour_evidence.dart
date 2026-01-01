/// What a fixed neighbour said about its own reachability in its `0x25`
/// (V4.2 §5.2, §8.1, §11.8a; D-113, S417).
///
/// A contact's device holds a contact's place only while its reachability is
/// evidenced — an address class is not evidence (§11.8a). Only the device
/// itself has the evidence (its open check, a granted mapping, its board's
/// proof); it says it in the evidence byte of every `0x25` that answers a
/// `0x24` with bit 0x40 (`code_registration.dart`). This file keeps the last
/// statement per neighbour:
///
///  * `true`  — evidenced: the device qualifies (§5.2);
///  * `false` — not evidenced: it gives up its place at that edge and takes
///    none until an edge of its own (it leaves the list and comes back as a
///    new neighbour) or the own network change;
///  * `null`  — nothing said since the last start or network change, or a
///    device of an earlier 4.2 version whose `0x25` carries no byte: the
///    address rule decides as before (§5.2).
///
/// No packet of its own, no clock, no repeat (rule 5): the statement rides
/// the `0x25` the registration edges of §8.1 bring anyway. In memory only,
/// like the record keys (`neighbour_keys.dart`). Keyed by [Neighbour.id] —
/// local, per run, kept across a merge — and by the network change count
/// (`Readiness.resets`): a statement from before the last network change
/// says nothing about the new network.
library;

import 'package:mycelium/neighbour.dart' show Neighbour;
import 'package:mycelium/node.dart';

final Expando<Map<int, ({bool evidenced, int resets})>> _said =
    Expando('reachability evidence of fixed neighbours');

extension NeighbourEvidence on Node {
  /// The `0x25` of the neighbour [id] said [evidenced] (`null`: no byte).
  /// `true` if that changed what [evidenceOf] answers. Statements of
  /// neighbours no longer in the list are dropped here — leaving the list is
  /// an edge of that neighbour, and its next arrival is a new one.
  bool evidenceHeard(int id, bool? evidenced) {
    final before = evidenceOf(id);
    final m = _said[this] ??= {};
    final ids = {for (final n in neighbourhood.all) n.id, id};
    m.removeWhere((k, _) => !ids.contains(k));
    if (evidenced == null) {
      m.remove(id);
    } else {
      m[id] = (evidenced: evidenced, resets: readiness.resets);
    }
    return before != evidenced;
  }

  /// What the last `0x25` of the neighbour [id] said since the last start or
  /// network change; `null`: nothing (address rule, §5.2).
  bool? evidenceOf(int id) {
    final s = _said[this]?[id];
    return s == null || s.resets != readiness.resets ? null : s.evidenced;
  }

  /// [evidenceOf] for the log: "yes", "no" or "unknown".
  String evidenceWord(Neighbour n) => switch (evidenceOf(n.id)) {
        true => 'yes',
        false => 'no',
        null => 'unknown',
      };
}
