import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/node.dart';
import 'package:mycelium/post_box_deposit.dart' show Neighbour, Question;

/// Whom a node asks beside its fixed neighbours, and the collection under a
/// foreign value. Split off `node_post_box.dart` for its line budget.
///
/// There is no row per node: every holder has its own
/// (`post_box_collect.dart`, §8.2), so a collection under a foreign value
/// and the node's own questions run side by side and meet only at a holder
/// both ask.
extension NodeCollectQueue on Node {
  /// Three NODES in list order, a fresh hint first so a collection proves it
  /// (§22.7.1, `smoke_readiness` B1/G4) — OP-19 ranks only the deposit.
  List<Neighbour> get lastHeard => readiness.different(foundNeighbours, 3);
}

/// The collection under a FOREIGN post box value.
extension NodeCompartment on Node {
  /// Collects under [ask]: the manifest compartment (§26.5.4, no proof) or up
  /// to seven values with their pairs (recovery bundle, §13.3.1);
  /// [withWhom], else the last heard. Every piece goes to [onPiece] when it
  /// arrives; the future completes with all of them once every asked holder
  /// is done — answered, unreachable, or silent after one request for what
  /// is missing (§8.2). `null`: not asked or failed — nothing deleted.
  /// Does not throw.
  /// [keep]: read only, send no delete receipt (D-40, a searching install).
  /// [onPiece] says whether it took the piece over: only then it is
  /// acknowledged for deletion (§8.2).
  Future<List<Uint8List>?> compartmentCollect(List<Question> ask,
      {List<Neighbour>? withWhom,
      bool keep = false,
      bool Function(Uint8List piece)? onPiece}) async {
    final neighbours = withWhom ?? lastHeard;
    if (neighbours.isEmpty) return null;
    try {
      return await postBoxDeposit.collect(
          ask: ask,
          withWhom: neighbours,
          keep: keep,
          onPiece: onPiece == null ? null : (piece, _) => onPiece(piece));
    } on Object catch (e) {
      report('Compartment: collect failed: $e');
      return null;
    }
  }
}
