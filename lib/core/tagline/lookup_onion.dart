// The state a BLIND RELAY holds for a lookup onion (E-L).
//
// WHY IT EXISTS.
//
// An onion-routed search runs in `kLookupOnionShells + 1` legs —
// since S377 that is three:
//
//   Leg 1   A   ->  …  ->  r1        outermost identifier, open
//   Leg 2   r1  ->  …  ->  r2        second identifier, was sealed
//   Leg 3   r2  ->  …  ->  target relay   third identifier, was sealed
//
// The answer goes the same way back. `PendingRequests` carries it
// hop by hop — but every hop knows only ONE identifier. A blind relay
// is the only node that knows the two identifiers of ITS two legs,
// and therefore the only one that has to relabel the answer at this seam.
// This map is exactly this assignment, and nothing
// else.
//
// PER NODE AND OPERATION AT MOST ONE ENTRY, even with more shells:
// a node may occur only once in the same chain (the searcher
// draws without replacement, the receiver rejects the rest), so it is
// at most ONE seam. The cap [LookupOnionAliases.capacity]
// therefore does NOT grow with the number of shells — what grows is the
// number of nodes that hold a seam at all.
//
// WHY NOT ONE IDENTIFIER FOR BOTH LEGS. Two reasons, and the first
// is correctness, not anonymity:
//
//   1. `PendingRequests.remember` OVERWRITES when the same identifier
//      comes in over a different neighbour („Same identifier over
//      a different neighbour: the return path changes"). Both legs
//      run greedily through the same network; a node that lies on both
//      would thereby lose the return path of the first leg. In a small
//      network — and that is today's situation — almost every node lies on
//      both.
//   2. First hop and target relay would otherwise have a shared,
//      unmistakable number. Whoever holds both would thereby link
//      „A asks" and „H(T ‖ e) is being asked for" without any
//      time correlation — i.e. exactly the linkage again against which
//      the onion is built.
//
// Equal identifiers on NEIGHBOURING legs are rejected by the blind relay
// in between. The pairing of non-neighbouring legs (with two shells
// leg 1 and leg 3) is seen by not a single node and is structurally not
// checkable at the receiver; it is guaranteed by the searcher
// (`V41Node.lookupQuery`, independently drawn 16-B values).
//
// NO CLOCK IN THE MODULE, as everywhere in this layer: the time is
// handed in so that expiry is testable without waiting.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The mapping inner identifier -> outer identifier at the blind relay.
final class LookupOnionAliases {
  /// Maximum number of operations remembered at the same time.
  ///
  /// The same order of magnitude as `PendingRequests.capacity`: the
  /// entry arises at the same moment and dies with the same
  /// operation. An entry is two 16-B identifiers and a timestamp.
  final int capacity;

  /// How long an entry is remembered.
  ///
  /// Must be at least as long as the period of `PendingRequests`
  /// (2 min) — if the alias expires earlier than the return path, the
  /// answer comes this far and then stays put, and the bug would look
  /// like a mute target relay. Equally long, not longer: the
  /// entry arises at someone else's instigation.
  final Duration lifetime;

  final Map<String, ({Uint8List outer, DateTime seen})> _aliases = {};

  /// How often an alias expired without having been used — the
  /// number from which a dead onion route can be read.
  int expired = 0;

  /// How often there was no room left.
  int dropped = 0;

  LookupOnionAliases({
    this.capacity = 1024,
    this.lifetime = const Duration(minutes: 2),
  });

  int get length => _aliases.length;

  static String _key(Uint8List id) => base64.encode(id);

  /// Remembers that [inner] stands for [outer] on the second leg.
  ///
  /// `false` if there was no room — the caller then does NOT forward,
  /// because the answer would not find its way home anyway.
  bool remember(Uint8List inner, Uint8List outer, DateTime now) {
    _sweep(now);
    final k = _key(inner);
    if (!_aliases.containsKey(k) && _aliases.length >= capacity) {
      dropped++;
      return false;
    }
    _aliases[k] = (outer: Uint8List.fromList(outer), seen: now);
    return true;
  }

  /// The outer identifier for [inner], or `null`.
  ///
  /// NOT CONSUMING, for the same reason for which
  /// `PendingRequests.peekRoute` is not: a search may get several
  /// answers (several target relays per round share no
  /// identifier, but a repetition is allowed). The entry dies at
  /// the period, not at first use.
  Uint8List? outerFor(Uint8List inner, DateTime now) {
    _sweep(now);
    return _aliases[_key(inner)]?.outer;
  }

  /// If the sessions drop away, the state does not drop with them — it hangs
  /// on the identifier, not on the partner. For cleaning up from outside.
  void clear() => _aliases.clear();

  void _sweep(DateTime now) {
    if (_aliases.isEmpty) return;
    final route = <String>[];
    _aliases.forEach((k, v) {
      if (now.difference(v.seen) > lifetime) route.add(k);
    });
    for (final k in route) {
      _aliases.remove(k);
      expired++;
    }
  }
}
