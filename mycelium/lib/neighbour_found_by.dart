/// Where a neighbour was found — the row "Found by" of V4.2 §25.7.
///
/// Memory of this run only: never on the wire, never on disk. After a restart
/// every neighbour taken over from memory is `remembered`, which is what §25.7
/// names. Next to [Neighbourhood] instead of in it: that file is at the line
/// budget, and nothing there decides by this.
///
/// A neighbour learned from an address entry in cover (§5.5) or from the source
/// of a genuine packet (§11.8.6) has no entry: §25.7 lists neither, and a guess
/// would be a claim (§25.2 rule 4). The display then leaves the line out.
library;

import 'package:mycelium/neighbour.dart' show Neighbour;
import 'package:mycelium/neighbourhood.dart' show Neighbourhood;

enum NeighbourSource { remembered, localSegment, invitation, externalRecords, board }

/// Keyed by [Neighbour.id], which survives a merge and a new stamp.
final Expando<Map<int, NeighbourSource>> _book = Expando('neighbourFoundBy');

extension NeighbourFoundBy on Neighbourhood {
  Map<int, NeighbourSource> get _sources => _book[this] ??= {};

  /// The first source stands: a later hint on a known neighbour found nothing.
  /// Entries of neighbours that left are dropped here, so the book stays
  /// bounded by the list.
  void noteFoundBy(Neighbour n, NeighbourSource source) {
    final book = _sources;
    final live = {for (final x in [...all, ...waiting]) x.id};
    book.removeWhere((id, _) => !live.contains(id));
    book.putIfAbsent(n.id, () => source);
  }

  NeighbourSource? foundBy(Neighbour n) => _sources[n.id];
}
