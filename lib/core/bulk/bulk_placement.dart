// Where a block goes — and how often (§9.3).
//
// THE SPEC, and it is the core of this file:
//
//   "Each block is placed **once** to one of the always-on relays (§22.6)
//    responsible for the transfer tag (lookup per §9.1, round-robin across
//    the set); redundancy is the rateless overshoot factor `F`, **not** the
//    `m × R` of §9.2 — per-block `m × R` would cost a factor of ~74 on the
//    wire and buys nothing a rateless code does not already provide."
//
// THE NUMBER 74, recomputed, so that it does not stand there as a claim:
// §9.2 places every cell under m = 3 families at R = 20 responsible relays each,
// i.e. 60 placements per cell. On the bulk lane there would be the added fact that the
// rateless code already overshoots with F ~ 1.3: 60 x 1.3 = 78 placements per
// source block instead of 1.3. The factor compared with "exactly once per block" is
// 60; compared with "no redundancy at all" 78. The document names ~74 — the
// order of magnitude is right in every reading, and the statement does not depend on the
// second decimal: `m × R` is two orders of magnitude too expensive.
//
// WHAT THIS MEANS FOR THIS FILE. It produces EXACTLY ONE
// placement per block. That is not a setting and not a parameter — there is no
// way to order a second copy here. [BulkPlacementPlan.forBlocks]
// returns as many placements as there are blocks, and
// `smoke_bulk.dart` checks that against the 60 that the delivery layer
// would take.
//
// NO STATE EXCEPT THE ROUND-ROBIN POINTER, NO I/O.
library;

import 'dart:typed_data';

import 'package:cleona/core/bulk/responsibility.dart'
    show closestTo, epochFor, kResponsibleRelays, targetFor;

/// A holder as this layer needs it: an identifier for the
/// caller and a position in the metric space.
///
/// Deliberately NOT `KnownNode` from `tagline/routing_table.dart`: the
/// bulk lane needs nothing from a holder but its position, and a
/// dependency on the routing table would pull half the delivery layer into
/// a module that has nothing to do with it. The caller maps.
final class BulkHolder {
  /// How the caller addresses this holder. Opaque for this
  /// layer.
  final String id;

  /// `L_node` — the rotating node position of the link layer
  /// (decision A, §9.1). NOT an identity-derived identifier.
  final Uint8List position;

  /// Does this node hold bulk at all? Always-on/carrier only (§22.6,
  /// E-53). A harvester is not even asked.
  final bool alwaysOn;

  BulkHolder(this.id, this.position, {this.alwaysOn = true});
}

/// A single placement: this block, to this holder, under this
/// tag.
final class BulkPlacement {
  final BulkHolder holder;
  final Uint8List tag;
  final Uint8List sealedBlock;

  /// The seed of the block — only for traceability at the caller, it
  /// is (sealed) in the block anyway.
  final int blockSeed;

  BulkPlacement(this.holder, this.tag, this.sealedBlock, this.blockSeed);
}

/// The round-robin plan over the responsible relays of a tag.
final class BulkPlacementPlan {
  /// The responsible relays, ascending by distance to `H(tag ‖ epoche)`.
  final List<BulkHolder> holders;

  final Uint8List tag;

  int _next = 0;

  BulkPlacementPlan._(this.tag, this.holders);

  /// Builds the plan from the known candidates.
  ///
  /// Responsibility is the same calculation as in the delivery layer
  /// (§9.1, E-H): the [count] candidates with the smallest XOR distance to
  /// `H(tag ‖ epoche)`. The difference lies solely in what
  /// happens afterwards — there m x R placements, here one per block.
  ///
  /// Harvesters are sorted out beforehand: §21.3.3 no. 3 lets them hold no
  /// bulk, a placement there would certainly be lost.
  factory BulkPlacementPlan({
    required Uint8List tag,
    required Iterable<BulkHolder> candidates,
    required DateTime nowUtc,
    int count = kResponsibleRelays,
  }) {
    final epoch = epochFor(tag, nowUtc);
    final target = targetFor(tag, epoch);
    final eligible = candidates.where((h) => h.alwaysOn);
    final closest = closestTo<BulkHolder>(target, eligible, (h) => h.position,
        count: count);
    return BulkPlacementPlan._(Uint8List.fromList(tag), closest);
  }

  bool get isEmpty => holders.isEmpty;

  /// The next holder in the round-robin.
  BulkHolder nextHolder() {
    if (holders.isEmpty) {
      throw StateError('BulkPlacementPlan: no responsible holders');
    }
    final h = holders[_next % holders.length];
    _next++;
    return h;
  }

  /// Assigns EXACTLY ONE holder to each block.
  ///
  /// The length of the return value is the length of [sealedBlocks] — not
  /// a multiple of it. Whoever wants to serve several holders per block here
  /// would have to change the function, and exactly that is supposed to stand out.
  List<BulkPlacement> forBlocks(List<(Uint8List, int)> sealedBlocks) {
    final out = <BulkPlacement>[];
    for (final (sealed, seed) in sealedBlocks) {
      out.add(BulkPlacement(nextHolder(), tag, sealed, seed));
    }
    return out;
  }
}

/// How many placements the delivery layer (§9.2) would have produced for the same number of
/// blocks: `m x R` per block.
///
/// Stands here because `smoke_bulk.dart` checks against it. A number that is
/// tested against belongs in the production code and not in the test —
/// otherwise the test checks its own copy.
int deliveryLayerPlacementsFor(int blocks, {int families = 3, int r = kResponsibleRelays}) =>
    blocks * families * r;
