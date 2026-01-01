// Responsibility — who holds a tag, and when does it move on.
//
// WHAT IS DECIDED HERE (and where it comes from).
//
// E-H (arch §9.1): responsible for a tag `T` in epoch `e` are the
// R relays whose `L_node` has the smallest XOR distance to `H(T ‖ e)`.
// Responsibility is thus COMPUTABLE FROM THE TAG — and only by whoever
// has the tag (KEX gate, §10.1). No directory, no announcement, no
// roster.
//
// E-J: the epoch is 24 h. E-M: its boundary is OFFSET PER TAG,
// `offset = H(tag) mod 86400`. The offset costs nothing — both sides
// compute it from the tag they share anyway — and it removes
// two things at once: the lookup storm at the common hour (M9 measured
// 4.4x above the cover rate in the one-minute window) and the network-wide
// traffic pattern at a fixed time of day, which would be an identifying feature.
//
// Decision A (2026-08-22): the position in the metric space is `L_node` — the
// rotating node identifier of the link layer, NOT a stable
// identity-derived ID. On a rotation the node appears at a
// new place and the old one drops out; the 30-day overlap of
// `L_node` covers handshakes and entry records, not the metric position.
//
// NO STATE, NO I/O. This file opens no socket and reads
// no clock on its own — the time comes in as an argument, so that every
// statement here stays testable.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Length of an epoch in seconds (E-J: 24 h).
const int kEpochSeconds = 86400;

/// Size of the responsibility set `R_relay` (E-H, M6).
const int kResponsibleRelays = 20;

/// Size of the responsibility set of the SIGNAL line, `R_signal`.
///
/// ── THE NUMBER IS COMPUTED FROM THE DEADLINE, NOT CHOSEN ─────────────
///    (owner decision 2026-08-31, §17.2)
///
/// The outflow is fixed: the cover stream emits ONE control frame per
/// slot, a slot is `kSlotInterval` = 8 s (`R_cover` = 1/8 s,
/// E-C′). Call signaling has exactly 120 s according to §17.2
/// (`kInteractiveDeliveryTtl` in `delivery_api.dart`). In 120 s
/// `120 / 8` = **15** placements thus flow out.
///
///   `kFamilies` (3, D1)  x  `kSignalRelays` (5)  =  15  =  120 s
///
/// The families stay at 3 — they are the lever against censorship (D1), and
/// cutting them would have turned the trade from "less redundancy" into "no
/// redundancy". Instead `R` is cut: 20 -> 5.
///
/// **WHAT IT COSTS, openly stated.** M6 computes the censorship cost as
/// `P1 = 1 − exp(−R·f)` over the whole responsibility set. With a
/// hostile fleet of `f` = 25 %, the hit probability per family
/// falls from `1 − exp(−5)` = 0.993 to `1 − exp(−1,25)` = 0.713. Across
/// m = 3 families the probability that ALL three
/// are suppressed stays at `(1 − 0,713)^3` = 2.4 % versus 3 x 10⁻⁷ at
/// R = 20. That is the price, and the owner named it: "Aren't we
/// censorable during a phone call anyway? […] no more than a
/// long ringing time."
///
/// It applies EXCLUSIVELY to signaling. A text keeps running
/// over [kResponsibleRelays] — there timeliness is not the
/// binding value.
const int kSignalRelays = 5;

/// How many relays carry LIVENESS (§6) — write AND read side.
///
/// ── WHY THIS THIRD NUMBER EXISTS (S381, 11.09.2026, owner approval)
///
/// MEASURED in the field, Node2 after one hour of operation with several pairs:
///
///     queuers    placeSecure 720 | publishLiveness 415 | harvest 358
///                requestEntries 209 | probe 171   = ~1873 frames
///     outflow    30 frames/min  ->  62 minutes of demand
///     control queue 1021/1026, discarded 89 and rising
///
/// `publishLiveness` placed per pair on the WHOLE responsibility set
/// and was, with 415 frames, the second largest item. What matters is
/// not the number but its growth: liveness scales LINEARLY
/// with the number of Speed-capable contacts, the payload does not.
/// A node with enough contacts fills its control queue by itself
/// with return paths, and then no message goes out anymore — in the field
/// on 11.09. it happened exactly like that, a contact request from the phone
/// therefore had not arrived after twenty minutes.
///
/// ── WHY NOT SIMPLY SAMPLE ───────────────────────────────────
///
/// The obvious answer would be to sample the write side like the
/// harvest. That is WRONG, and §9.2 also says why: "Placement covers
/// the set; harvest samples it" — full coverage when writing is
/// the precondition for the sample when reading finding anything
/// at all. The read side already samples here
/// (`V41Node._abtasten`, [kHarvestRelaysPerFamily] = 1 per run, with
/// rotating offset). Whoever cuts ONLY the write side lets both
/// sides miss each other.
///
/// ── SO: BOTH SIDES, THE SAME NUMBER ──────────────────────────────
///
/// What is cut is the SET from which both sides compute — from the same
/// tag, with the same `count`. The sample of the read side thus
/// still hits in the first run, because every relay of the set
/// is written to. The same design as [kSignalRelays], and for the
/// same reason: a line of its own with its own binding value.
///
/// **WHAT IT COSTS, openly stated.** The return path lies on 5 instead of
/// 20 relays. If all five are gone at the same time, the partner finds
/// no return path — and then sends via Secure instead of Speed. That is
/// **slower, not broken**, and it is exactly the gradation that §7.2
/// provides for the epoch cold start anyway; `publishLiveness`
/// justifies the fallback on the spot with the same sentence. The
/// liveness is INFORMATION about a live path, not a placement
/// of a message: if it is lost, no content is lost.
///
/// The cost formula from §6/M5 (`1,15 + 0,23*S` MB/day) falls with
/// the same division by four to `1,15 + 0,0575*S`.
const int kLivenessRelays = 5;

/// Length of a node position in bytes (`L_node`, §4.3).
const int kNodePositionBytes = 32;

/// The epoch offset of this tag in seconds, `H(tag) mod 86400` (E-M).
///
/// Both pair partners compute the same value from the same tag — there is
/// nothing to coordinate. Uniformly distributed over all tags, so that the
/// network's epoch changes spread over the day instead of
/// bunching.
int epochOffsetFor(Uint8List tag) {
  final h = SodiumFFI().sha256(tag);
  var v = 0;
  for (var i = 0; i < 8; i++) {
    v = ((v << 8) | h[i]) % kEpochSeconds;
  }
  return v;
}

/// The epoch number of this tag at time [utc].
///
/// Rounding down, also before the offset: `((t - offset) / 86400).floor()`.
/// Dart's `~/` truncates towards zero and would be off by one before the zero point
/// — no production time lies there, but a test must be allowed to hit the
/// edge.
int epochFor(Uint8List tag, DateTime utc) {
  final secs = utc.toUtc().millisecondsSinceEpoch ~/ 1000;
  return ((secs - epochOffsetFor(tag)) / kEpochSeconds).floor();
}

/// The epoch of a NODE — without offset.
///
/// A node has no pair epoch of its own; that only exists per pair (E-M,
/// offset from the tag). For bookkeeping — replay guard, expiry in the
/// placement store — it still needs a number, and that is the
/// unshifted one.
///
/// **Why the ±1 tolerance of the relays works out exactly** (and that is
/// no coincidence but the reason why it is ±1): a pair epoch
/// is `floor((t − offset)/86400)` with `offset ∈ [0, 86400)`, the
/// node epoch is `floor(t/86400)`. The difference is thus **always 0
/// or 1** — never more. A relay that tries the tolerated epochs `e`,
/// `e−1`, `e+1` covers every possible offset, and the
/// clock drift on top.
int nodeEpochNow([DateTime? utc]) =>
    ((utc ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000) ~/
    kEpochSeconds;

/// The point in the metric space around which the responsible relays lie:
/// `H(T ‖ e)` (E-H).
Uint8List targetFor(Uint8List tag, int epoch) {
  final buf = Uint8List(tag.length + 8);
  buf.setRange(0, tag.length, tag);
  var e = epoch;
  for (var i = 7; i >= 0; i--) {
    buf[tag.length + i] = e & 0xff;
    e >>= 8;
  }
  return SodiumFFI().sha256(buf);
}

/// Compares the XOR distances of [a] and [b] to [target].
///
/// Negative if [a] is closer. Without an intermediate buffer: the distance is
/// needed nowhere, only its ordering.
int compareDistance(Uint8List target, Uint8List a, Uint8List b) {
  final n = target.length;
  for (var i = 0; i < n; i++) {
    final there = a[i] ^ target[i];
    final db = b[i] ^ target[i];
    if (there != db) return there < db ? -1 : 1;
  }
  return 0;
}

/// The [count] candidates with the smallest distance to [target].
///
/// [positionOf] extracts the position from the candidate type, so that this
/// file needs to know nothing about nodes except their position.
List<T> closestTo<T>(
  Uint8List target,
  Iterable<T> candidates,
  Uint8List Function(T) positionOf, {
  int count = kResponsibleRelays,
}) {
  final list = candidates.toList()
    ..sort((x, y) => compareDistance(target, positionOf(x), positionOf(y)));
  return list.length <= count ? list : list.sublist(0, count);
}


/// Which partner is closer to [target] than [own]?
///
/// The rule behind passing on a placement (§11.1). It is
/// deliberately a pure function: it knows no session, no socket and
/// no node, only positions — and can therefore be tested without
/// building a network.
///
/// Returns the INDEX in [partners], or `null` if none is
/// closer. That it is then `null` and not, say, the best one available, is
/// the termination condition: whoever knows no closer one is the local
/// minimum, and there the path ends. Without this condition a placement would
/// run in circles until the hops are used up.
int? closerPartner(
  Uint8List target,
  Uint8List own,
  List<Uint8List?> partners,
) {
  var bestIdx = -1;
  Uint8List? best;
  for (var i = 0; i < partners.length; i++) {
    final p = partners[i];
    if (p == null) continue;
    if (compareDistance(target, p, own) >= 0) continue;
    if (best == null || compareDistance(target, p, best) < 0) {
      best = p;
      bestIdx = i;
    }
  }
  return bestIdx < 0 ? null : bestIdx;
}
