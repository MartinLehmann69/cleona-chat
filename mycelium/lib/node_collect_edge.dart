/// The edges at which a node collects (§8.2 "When the recipient asks"):
/// start, network change, a new neighbour, the application opened. All of
/// them run into `NodePostBox.collect` and `NodePostBox.collectFrom`;
/// whoever else must ask at the same moments — the bulk lane (§9.4 "Lane 3,
/// collection"), the bundle search, the enrolment — registers here instead
/// of hooking every caller a second time.
///
/// Next to the node, in an [Expando]: `node.dart` is at its line budget. No
/// clock: a registered function runs only when
/// [NodeCollectEdge.fireCollectEdge] is called at an edge (§5.4, D-9).
library;

import 'package:mycelium/node.dart';
import 'package:mycelium/post_box_holder.dart' show Neighbour;

/// What runs at a collection edge. [only]: the holders this edge asks —
/// the new neighbour alone at the edge "a new neighbour" (§8.2); `null` at
/// every other edge: whom a collection asks. [round]: ends with the number
/// of pieces once every holder of the node's own round is done — for what
/// must follow the post of this edge; it waits alone. `null`: no round.
typedef CollectEdge = void Function(List<Neighbour>? only, Future<int>? round);

final Expando<List<CollectEdge>> _edges =
    Expando<List<CollectEdge>>('collectEdges');

extension NodeCollectEdge on Node {
  /// Runs [f] at every collection edge of this node from now on.
  void addCollectEdge(CollectEdge f) => (_edges[this] ??= []).add(f);

  /// The edge — called by `NodePostBox` once its own questions are out. A
  /// failing function is reported and does not stop the others.
  void fireCollectEdge([List<Neighbour>? only, Future<int>? round]) {
    for (final f in List.of(_edges[this] ?? const <CollectEdge>[])) {
      try {
        f(only, round);
      } on Object catch (e) {
        report('Collection edge failed: $e');
      }
    }
  }
}
