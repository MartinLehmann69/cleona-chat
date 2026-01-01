// The seam between the media bulk lane and the network (§9.3).
//
// ── WHY THIS FILE EXISTS ────────────────────────────────────────
//
// After step 1 of the CUT (31.08.2026) `routeFor` returns
// `DeliveryRoute.bulkLane` for large media instead of the V3 two-stage
// path. All the computational work behind it is built and checked:
//
//   * `lib/core/fountain/`  — the rateless codec (E-42, pure Dart)
//   * `lib/core/bulk/`      — key, mark, seal, cache, round-robin plan,
//                             control messages, sender, receiver
//
// What lay between them and the wire was the HOLDER SIDE. This file names
// what the lane needs from the network — and the section below, from
// where it has been getting it since 02.09.2026.
//
// ── THE HOLDER SIDE IS BUILT (02.09.2026) ────────────────────
//
// Until that day `MediaBulkLane.transport` was `null` in `lib/`, and this
// header described what was missing. It was missing FOURFOLD, and each of
// the four statements was measured with a reversal probe:
//
//   1. A sealed block (1069 B) did not fit into a PLACE frame (1042 B) —
//      27 B too many, `buildPlace` threw.
//   2. `SecureStore.maxCellsPerTag` = 32 versus 47 blocks of the smallest
//      admissible transfer.
//   3. `BulkCache` had no constructor in `lib/`.
//   4. Frame type `0x05` was discarded by `CellTransport.classify`.
//
// All four are closed, and like this:
//
//   * **The 27 bytes were not a calculation problem, but a carrier
//     problem.** §9.3 says literally "uniform 1200 B cells of
//     **entry type `0x05`**" — the PLACE frame was never the intended
//     carrier. The own frame lives in `lib/core/bulk/bulk_frames.dart`,
//     including the calculation of why a SEALED bulk frame (1198 B) does
//     not fit into a cell (1172 B) and what that cost.
//   * `DeliveryNode` holds a `BulkCache` — the fourth storage class from
//     §21.2 —, and `startV41Node` switches it off on mobile devices (E-53),
//     instead of making it small.
//   * `CellTransport.classify` knows `CellRole.bulk`, and
//     `DeliveryNode._handleBulk` is the holder role: deposit, scan,
//     answer, pass on.
//   * The OWN DRAIN (`bulk_egress.dart`) runs on `R_bulk` instead of on
//     the slot clock. Via the control queue 98.1 % of the 6348 blocks of a
//     5 MB photo were silently lost.
//
// This interface is fulfilled by
// `lib/core/service/media_bulk_transport_v41.dart`; it is attached in
// `attachV41`, together with its back side `DeliveryNode.onBulkScanned`.
// Measured by `test/smoke/smoke_bulk_lane_effect.dart` — by its EFFECT:
// an object leaves the node via the bulk lane, and the receiver
// reassembles it.
//
// ── WHY THE INTERFACE STANDS UNCHANGED ───────────────────
//
// It describes what the bulk lane NEEDS from the network, and that has not
// changed through the build: one deposit per block, one scan per mark, one
// sink. What has changed is solely the answer to "who fulfils it".
//
// As long as nobody fulfils this interface — no V4.1 node at this
// identity —, a large media send is REJECTED and not sent via V3 as a
// substitute. That is the same rule under which `routeFor` has stood since
// S349 ("no fallback") — a silent V3 path would be the dual stack that §7
// rules out, and it would be invisible because both "work". And fulfilling
// it HALFWAY — depositing without a holder — would be traffic nobody
// harvests (working rule 5); precisely for that reason `attachV41`
// attaches `bindTransport` and `DeliveryNode.onBulkScanned` in ONE block.
//
// ── AND THE STREAM LANE? ──────────────────────────────────────────────
//
// It does NOT stand in this interface. §17.6 runs via level D and stores
// nothing in the network; it will later step NEXT TO the bulk lane, not
// into its place. §9.3: "Blocks are lane-neutral. Both lanes carry the
// same rateless fountain blocks … a transfer interrupted on one lane
// finishes on the other with no byte of received progress lost." That is
// exactly why the two methods here speak of BLOCKS and not of a transfer:
// whoever builds the stream lane builds a second source of the same blocks
// and does not have to change anything in this file.
library;

import 'dart:typed_data';

import 'package:cleona/core/bulk/bulk_placement.dart' show BulkHolder;

/// What the bulk lane needs from the network — two actions, nothing more.
///
/// **IT SPEAKS OF BLOCKS, NOT OF TRANSFERS.** §9.3: "Blocks are
/// lane-neutral … a block received on either lane counts." Whoever builds
/// the stream lane (§17.6) builds a second source of the same blocks and
/// does not have to change anything in this interface.
abstract interface class MediaBulkTransport {
  /// Deposits every block from [sealedBlocks] EXACTLY ONCE under [tag].
  ///
  /// The fulfiller's responsibility: look up the mark's responsible ones
  /// (§9.1) and serve EXACTLY ONE per block in round-robin —
  /// `BulkPlacementPlan` (`lib/core/bulk/bulk_placement.dart`) computes
  /// this completely and returns exactly as many deposits as there are
  /// blocks.
  ///
  /// **NOT `m x R`.** §9.3: "redundancy is the rateless overshoot
  /// factor `F`, **not** the `m × R` of §9.2 — per-block `m × R` would
  /// cost a factor of **60** on the wire and buys nothing a rateless code
  /// does not already provide."
  ///
  /// The clock lies with the fulfiller, not with the caller: `R_bulk`
  /// (32 cells/s, appendix A) is a property of the egress. Returns how
  /// many deposits were accepted.
  int placeOnce(Uint8List tag, List<Uint8List> sealedBlocks);

  /// Scans the holders of the transfer mark [tag] (§9.3: "the recipient
  /// **scans** the holding relays … deduplicates by block id").
  ///
  /// [have] are the block marks the receiver already has — they go along
  /// in the request, so that a holder does not send back what has already
  /// arrived (the same have-list as with the harvest, B-32).
  ///
  /// The answer comes back ASYNCHRONOUSLY via [onScanned]; a return value
  /// would be a promise that a scan cannot give.
  void scan(Uint8List tag, List<Uint8List> have);

  /// Where scanned blocks are reported — sealed blocks, raw.
  ///
  /// ONE sink, not many: exactly one `BulkReceiver` belongs to a mark.
  set onScanned(void Function(Uint8List tag, List<Uint8List> sealed) sink);
}

/// A transport with which the caller can say WHICH holder gets a
/// particular block.
///
/// ── WHY THE STRIPE LANE NEEDS THIS AND THE RATELESS ONE DOES NOT ───────
///
/// [MediaBulkTransport.placeOnce] returns a NUMBER: how many deposits were
/// accepted. For the rateless lane that suffices — which block got lost
/// is irrelevant there, because every block is equivalent and the overshoot
/// factor `F` covers the loss.
///
/// With a stripe encoding it is not equivalent. A stripe needs `K` of `N`
/// fragments, and the design `N = K + d` (`codec/erasure_stripes.dart`)
/// only holds as long as the `N` fragments lie on `N` DIFFERENT holders. If
/// one fails because no next hop is known for its holder right now —
/// today a silent `continue` in `V41MediaBulkTransport.placeOnce` —, the
/// stripe loses one spot of its coverage, and nobody learns of it. Four
/// such spots in a stripe, and the object is gone; there is no refill
/// request for this lane (§9.3, O-3).
///
/// That is why this interface reports back per fragment individually.
/// `ErasurePlacementCoordinator.runSync` (`codec/erasure_placement.dart`)
/// derives from it the resubmission to ANOTHER holder.
///
/// **What [placeAt] promises, and what not.** `true` means: the block has
/// been HANDED to this holder — queued in the drain or, with
/// self-responsibility, held directly. It does NOT mean that the holder
/// has stored it; there is no placement receipt on this wire
/// (`bulk_frames.dart:BulkOp` knows five actions, none of them acknowledges
/// a deposit). The wire change for that is before the owner as a proposal.
abstract interface class BulkDirectedPlacement implements MediaBulkTransport {
  /// The responsible ones of the mark, as this transport sees them NOW —
  /// the same set and the same order from which [placeOnce] builds its
  /// round-robin.
  List<BulkHolder> holdersFor(Uint8List tag);

  /// Deposits ONE block at EXACTLY THIS holder.
  ///
  /// [holder] comes from [holdersFor] of the same transport; a foreign
  /// object returns `false`.
  bool placeAt(Uint8List tag, BulkHolder holder, Uint8List sealedBlock);
}
