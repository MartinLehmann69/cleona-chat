// The routing table of the V4 node — k-buckets over `L_node`.
//
// WHY ITS OWN AND NOT THE ONE FROM `dht/`.
//
// **HISTORICAL from 2026-08-31 (CUT):** `lib/core/dht/` has zero files
// (measured 2026-09-03), so the alternative below no longer exists.
// The paragraph stays because it explains why THIS file exists.
//
// `lib/core/dht/kbucket.dart` had the same metric and would have been
// technically usable — but it was built on `PeerInfo` and had ten
// V3 consumers (delivery path, DV routing, identity resolver). Sharing it
// would have glued the two network layers together again, which the
// migration plan §7 lists as a non-goal. The metric itself is twenty
// lines; the coupling would be more expensive than the repetition. That both
// calculations agree is checked by `smoke_tagline_responsibility.dart`
// against the V3 implementation — origin proven, dependency avoided.
//
// PARAMETERS. `bucketSize` is 20, not the 200 of the V3 table:
// M9 measured with 20 (2.3 rounds, 7 requests, recall 1.00 at 10^5
// nodes). Whoever changes it changes the measurement basis along with it.
library;

import 'dart:typed_data';

import 'package:cleona/core/bulk/responsibility.dart';

/// A known node: its position and a hint how it can be
/// reached. The hint is opaque to this file.
final class KnownNode {
  final Uint8List position;
  final String? hint;

  KnownNode(this.position, {this.hint}) {
    if (position.length != kNodePositionBytes) {
      throw ArgumentError('L_node must be $kNodePositionBytes B, '
          'not ${position.length}');
    }
  }

  String get positionHex =>
      position.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  String toString() => 'KnownNode(${positionHex.substring(0, 8)}…)';
}

/// Kademlia table: one bucket per leading bit distance to the own
/// position.
final class RoutingTable {
  /// The own position (`L_node`). If the node rotates, that is a
  /// NEW table — the old neighbourhood does not carry over (decision A).
  final Uint8List ownPosition;

  /// How many nodes a bucket holds (`k`).
  final int bucketSize;

  final List<List<KnownNode>> _buckets;

  RoutingTable(this.ownPosition, {this.bucketSize = kResponsibleRelays})
      : _buckets = List.generate(kNodePositionBytes * 8, (_) => <KnownNode>[]) {
    if (ownPosition.length != kNodePositionBytes) {
      throw ArgumentError('own position must be $kNodePositionBytes B');
    }
  }

  /// Bucket index: the number of leading equal bits. A node with
  /// identical position belongs in no bucket (that would be oneself).
  int? bucketIndexFor(Uint8List other) {
    for (var i = 0; i < kNodePositionBytes; i++) {
      final x = ownPosition[i] ^ other[i];
      if (x == 0) continue;
      var bit = 0;
      for (var m = 0x80; m > 0; m >>= 1, bit++) {
        if ((x & m) != 0) return i * 8 + bit;
      }
    }
    return null;
  }

  /// Takes up a node. Full buckets accept nothing new — the
  /// oldest entry stays, because a node that was reachable for a long time
  /// is more likely to stay so than a freshly seen one.
  bool insert(KnownNode entry) {
    final idx = bucketIndexFor(entry.position);
    if (idx == null) return false;
    final bucket = _buckets[idx];
    for (final n in bucket) {
      if (compareDistance(ownPosition, n.position, entry.position) == 0) {
        return false;
      }
    }
    if (bucket.length >= bucketSize) return false;
    bucket.add(entry);
    return true;
  }

  /// The [count] nearest known nodes to [target].
  List<KnownNode> closest(Uint8List target, {int count = kResponsibleRelays}) =>
      closestTo<KnownNode>(target, _buckets.expand((b) => b), (n) => n.position,
          count: count);

  int get length => _buckets.fold<int>(0, (a, b) => a + b.length);

  /// How many buckets are occupied — the figure from which one sees whether
  /// the table covers the space or only the own neighbourhood.
  int get occupiedBuckets => _buckets.where((b) => b.isNotEmpty).length;
}
