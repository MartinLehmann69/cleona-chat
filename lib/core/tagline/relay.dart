// The relay side — what r1 and r2 do with a cell.
//
// r1 IS SIMPLE. The cell came in over a link, so r1 knows the
// key: strip, forward. r1 learns r2 and nothing else.
//
// r2 IS THE INTERESTING PLACE. The path block is sealed under the
// link key B<->r2 — but r2 only knows AFTER opening
// that it is about B. Chicken and egg. Two resolutions, both viable:
//
//   (a) Try and remember. r2 tries its link keys and
//       remembers the assignment seed -> link. First cell O(links), every
//       further one O(1). No wire format needed. Price: the first cell is
//       expensive, and whoever sends garbage forces r2 to a full pass every time
//       — that needs a cap.
//   (b) The block carries a link identifier in plaintext. O(1) from the first
//       cell. Price: a wire field, and r1 sees the identifier.
//
// **DECIDED 2026-08-22: (a).** Measured: with four partners a
// full pass costs 41.6 us, and only for the FIRST cell per pair and
// epoch — the path block is constant for an epoch, every further cell
// hits the cache. Whoever wants to force the node into a full pass with garbage
// must push 29 MB/s into it to saturate ONE core; that is
// a bandwidth problem, not a computing problem. Path (b) on the other hand would have cost a
// property: the path block today differs per PAIR, a
// link identifier would be the same per TARGET — r1 could group flows of different
// senders onto the same B, which it cannot today. A third
// version (identifier sealed to r2) is dominated by (a): it pays a
// scalar multiplication (37.4 us) for EVERY cell instead of only the first
// and costs an additional ~62 B of payload.
//
// The resolution is nevertheless HANDED IN as [LinkKeyLookup]
// and this file stays independent of both.
//
// WHAT r1 SEES ANYWAY — and what follows from it.
//
// The path block is CONSTANT per pair and epoch: B builds it once per
// epoch and puts it into the pairwise liveness. Every cell from A to B
// thus carries the same 64 B in this epoch. **r1 can thereby count
// how many cells A sends to the same contact** — not who the
// contact is. That is exactly the session linkability that §7.3 declares
// for Speed mode anyway, and no new limit.
//
// REPLAY. Because the block is valid for an epoch, anyone who has seen it
// can present it again — r1 first of all. r2 must therefore hold the
// seen seeds per epoch (appendix B-16). That is mandatory, not
// optional: without this state the block is, until the end of the epoch, a
// free ticket in B's direction.
library;

import 'dart:typed_data';

import 'onion.dart';

/// Finds the link key for a path-block seed. See header.
/// Resolves which link a forwarded cell belongs to.
///
/// Gets the WHOLE cell, not only the path block: the trying from
/// decision (a) calls `redeemReplyBlock`, and that also needs the part
/// behind the block.
typedef LinkKeyLookup = Uint8List? Function(Uint8List forwarded, int epoch);

/// Was r1 weiterreicht.
final class ForwardDecision {
  final Uint8List nextHop;
  final Uint8List cell;
  ForwardDecision(this.nextHop, this.cell);
}

/// Was r2 ausliefert.
final class DeliverDecision {
  final Uint8List handle;
  final Uint8List message;
  DeliverDecision(this.handle, this.message);
}

/// Why a cell did not run on.
enum RelayReject { unreadable, replay, unknownLink }

/// The seen cell fingerprints per epoch.
///
/// Deliberately simple: one set per epoch, old epochs drop away. The
/// size is the item that belongs in the memory budget (§21) — it
/// grows with the number of cells r2 delivers in this epoch.
///
/// UNTIL S355 IT DID NOT, although exactly that stood here: the
/// key was the seed of the path block, and that is constant per PAIR
/// (see `replayKeyOf`). The set grew with the pairs, and from the
/// second cell of a pair on, discarding happened silently. The comment
/// thus described the intention, the code something else.
///
/// ── AND THAT IS WHY IT NOW NEEDS A CAP ──────────────────────
///
/// Per pair a handful of entries sufficed; per cell there are at
/// R_cover = 1/8 s up to 10 800 per day PER PARTNER STREAM that r2
/// delivers. Without a cap that would be a set that only grows for an
/// epoch.
///
/// CALCULATED: the key is 7 bytes of the fingerprint, held as
/// `int`. Seven bytes stay below 2^62 and thus an unboxed
/// Smi — an entry costs about 16 B in a `Set<int>` including hashing.
/// At [maxPerEpoch] = 16384 that is 262 KB per epoch and with
/// [keepEpochs] = 2 at most three held epochs, i.e. under 800 KB.
/// The collision probability over 16384 entries at 56 bits
/// is 1.9e-9; a collision costs ONE discarded cell,
/// no more.
///
/// WHAT THE CAP GIVES UP, stated openly: if an epoch runs over 16384
/// delivered cells, the oldest fingerprint drops out, and a
/// replay of this one old cell would run once more. That is
/// a cell whose content the attacker does not know (§4) and whose
/// receiver discards it as a duplicate; the damage is one slot. The
/// alternative — growing without limit — would be a memory leak with
/// the same attack surface.
final class ReplayGuard {
  final int keepEpochs;

  /// Maximum number of fingerprints held per epoch.
  final int maxPerEpoch;

  /// Insertion order matters: `Set<int>` in Dart is a
  /// `LinkedHashSet`, so `first` is the oldest entry.
  final Map<int, Set<int>> _seen = <int, Set<int>>{};

  ReplayGuard({this.keepEpochs = 2, this.maxPerEpoch = 16384});

  /// Seven bytes of the fingerprint as `int` — below 2^62, so a Smi.
  int _k(Uint8List fingerprint) {
    var v = 0;
    for (var i = 0; i < 7 && i < fingerprint.length; i++) {
      v = (v << 8) | fingerprint[i];
    }
    return v;
  }

  /// `true` if this fingerprint already ran in this epoch.
  bool isReplay(Uint8List fingerprint, int epoch) =>
      _seen[epoch]?.contains(_k(fingerprint)) ?? false;

  void remember(Uint8List fingerprint, int epoch) {
    final currentSet = _seen.putIfAbsent(epoch, () => <int>{});
    currentSet.add(_k(fingerprint));
    while (currentSet.length > maxPerEpoch) {
      currentSet.remove(currentSet.first);
    }
    _seen.removeWhere((e, _) => e < epoch - keepEpochs);
  }

  int get trackedEpochs => _seen.length;
  int trackedIn(int epoch) => _seen[epoch]?.length ?? 0;
}

/// **r1**: strip one shell and forward.
///
/// Returns `null` instead of throwing — a failure would be a
/// time-measurable event towards the predecessor (E-83).
ForwardDecision? forwardFirstHop({
  required Uint8List cell,
  required Uint8List linkKeyOfIncoming,
}) {
  final peeled = peelFirstHop(cell: cell, linkKeyToR1: linkKeyOfIncoming);
  if (peeled == null) return null;
  return ForwardDecision(peeled.nextHop, peeled.payload);
}

/// **r2**: redeem the path block and deliver.
///
/// [epoch] is the current epoch for replay protection. A failure
/// is returned as [RelayReject] instead of thrown — the caller
/// decides whether it counts or stays silent, but the cell does not run.
({DeliverDecision? ok, RelayReject? reject}) deliverSecondHop({
  required Uint8List forwarded,
  required int epoch,
  required LinkKeyLookup lookup,
  required ReplayGuard guard,
}) {
  if (forwarded.length < kReplyBlockBytes) {
    return (ok: null, reject: RelayReject.unreadable);
  }
  final seed = replayKeyOf(forwarded);

  if (guard.isReplay(seed, epoch)) {
    return (ok: null, reject: RelayReject.replay);
  }

  // ── THE TOLERANCE MUST LIE AROUND THE LOOKUP, NOT BEHIND IT
  // (S354) ───────────────────────────────────────────────────────────
  //
  // Here the lookup stood BEFORE the epoch loop, and because the
  // resolver itself only checks the named epoch (`ReplyBlockResolver.
  // _fits`, explicitly: "the epoch tolerance lies with
  // deliverSecondHop"), the tolerance behind it had no effect: if the
  // epoch did not fit, the lookup came back with `null` and the loop
  // never ran. Result `unknownLink` — the information "I do not know this
  // link", although the link was known and only the epoch was shifted
  // by one.
  //
  // THIS IS NOT AN EDGE CASE. The path block of the liveness is built under the
  // PAIR epoch (`publishLiveness`), r2 computes with its
  // NODE epoch, and `responsibility.dart` proves that the two differ
  // by exactly 0 or 1 — depending on the offset of the pair (E-M).
  // Affected is every pair whose offset lies above the current time of day
  // — averaged over the day half, at a fixed hour
  // more or less. For these pairs EVERY Speed cell was silently discarded by r2.
  // Measured in the lab on 30.08.: `kein Weg zum naechsten
  // Hop … Einloesung unknownLink` with identical link keys.
  //
  // PRICE: in the failure case up to three passes instead of one. In the regular case
  // — epoch fits — it stays at one, because the loop breaks at the
  // first hit.
  PeeledCell? redeemed;
  var usedEpoch = epoch;
  var linkFound = false;
  for (final e in [epoch, epoch - 1, epoch + 1]) {
    // The resolver gets the whole cell, not only the seed. With the
    // seed alone one could only look up — trying, and thus path
    // (a), needs the ciphertext.
    final linkKey = lookup(forwarded, e);
    if (linkKey == null) continue;
    linkFound = true;
    redeemed =
        redeemReplyBlock(forwarded: forwarded, linkKeyToB: linkKey, epoch: e);
    if (redeemed != null) {
      usedEpoch = e;
      break;
    }
  }
  if (redeemed == null) {
    return (
      ok: null,
      reject: linkFound ? RelayReject.unreadable : RelayReject.unknownLink
    );
  }

  // Only remember when the cell really runs: otherwise an
  // attacker could burn foreign seeds with unreadable cells.
  guard.remember(seed, usedEpoch);
  return (
    ok: DeliverDecision(redeemed.nextHop, redeemed.payload),
    reject: null
  );
}
