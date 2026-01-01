// Liveness — where a contact harvests in this epoch.
//
// WHAT FOR. A sender must know where to place. V4.0 left that to
// probability and died of it (rendezvous
// Theta(N), 53 % delivery reach at 10^4 nodes). V4.1 gives back the
// minimum of coordinate: a PAIRWISE derived record
// that only the two partners can find (Arch §6).
//
// THE CIRCLE TO BE AVOIDED HERE.
//
// E-M staggers the epoch boundary per tag: `offset = H(tag) mod 86400`. The
// liveness tag itself however hangs on the epoch — `HKDF(K_AB, "liveness",
// e)`. Whoever derived the offset from the epoch tag would need the epoch to
// determine the epoch.
//
// Resolution: an EPOCH-FREE ANCHOR per pair, `HKDF(K_AB, "anchor")`.
// From it comes the offset, from the offset the epoch, from the epoch
// the tag. The anchor never goes on the wire; it is pure computation and
// identical for both partners, because `K_AB` is.
//
// WHAT IS NOT BUILT HERE.
//
// The return path is an onion path (§6: „encoded as an onion return path,
// never a bare exit-relay"). This file treats it as **opaque
// bytes**. The onion itself is a separate, security-critical
// construction and is not invented on the side — it comes from WP-3 and
// is only carried here. Likewise the placement: which relays are responsible
// is computed by WP-0; how the cell gets there is handed in.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

import 'onion.dart';
import 'package:cleona/core/bulk/responsibility.dart';

/// How many decoys accompany a harvest query (E-C′: 3, uniform on
/// every platform — a platform-dependent value would make the platform readable
/// from the query stream, exactly as with the cover rate).
const int kDecoyCount = 3;

Uint8List _hkdf(Uint8List key, String salt, String info) => SodiumFFI().hkdfSha256(
      key,
      salt: Uint8List.fromList(utf8.encode(salt)),
      info: Uint8List.fromList(utf8.encode(info)),
      length: 32,
    );

/// The epoch-free anchor of a pair. Only for the epoch offset.
Uint8List pairAnchor(Uint8List kAb) => _hkdf(kAb, 'cleona-liveness', 'anchor');

/// The epoch of this pair at time [utc] — 24 h (E-J), boundary offset
/// per pair (E-M).
int livenessEpoch(Uint8List kAb, DateTime utc) =>
    epochFor(pairAnchor(kAb), utc);

/// Length of the publication mark in the liveness record (§6).
const int kLivenessMarkBytes = 4;

/// The whole liveness record (§6):
/// `r2 identifier (32) ‖ path block (64) ‖ publication mark (4)`.
const int kLivenessRecordBytes =
    kHopIdBytes + kReplyBlockBytes + kLivenessMarkBytes;

/// The publication mark: seconds since the start of THIS
/// pair epoch (§6, S355).
///
/// WHAT FOR. A path block is sealed under the link key `B<->r2`,
/// and that is SESSION-BOUND — `deriveLinkKey` mixes two ephemeral
/// handshake secrets, only the static-static part is
/// pair-constant and must never carry alone. Every connection drop on
/// either side thus kills every published path block.
/// The records carrying it, however, stay with the
/// responsible relays until the end of the epoch, and a relay APPENDS under a mark
/// instead of replacing (`SecureStore.place`). Without this mark a
/// harvester gets the dead record next to the live one and cannot tell them
/// apart; r2 then silently discards (E-83), the sender sees an
/// accepted message, and Speed is dark for up to 24 h. Measured in the field
/// on 30.08.: six of six Speed sends `unknownLink`.
///
/// WHY A CLOCK AND NOT A COUNTER. A counter in working memory
/// would start again at zero after a restart — and precisely the
/// restart is the case the mark is supposed to solve: the old record
/// would then have the higher number and win. Read off the clock,
/// the mark is monotonic within the epoch without anything
/// having to persist.
///
/// WHAT IT REVEALS: nothing a responsible relay does not already have.
/// It holds the tag, and the pair's epoch offset is a function
/// of the tag — so it can compute the start of the epoch anyway.
int livenessMark(Uint8List kAb, DateTime utc) {
  final anchor = pairAnchor(kAb);
  final start =
      epochFor(anchor, utc) * kEpochSeconds + epochOffsetFor(anchor);
  final mark = utc.millisecondsSinceEpoch ~/ 1000 - start;
  // Clamped so that a clock jump never bursts a field that is four bytes
  // in size: the mark is by construction in [0, kEpochSeconds).
  return mark < 0 ? 0 : (mark >= kEpochSeconds ? kEpochSeconds - 1 : mark);
}

/// Does the harvester adopt this record? (§6, S355)
///
/// Pure, so that the rule is testable and not only commented: a
/// relay APPENDS under a mark instead of replacing, so a harvest
/// supplies after every connection drop of the counterpart the dead
/// record NEXT TO the live one. Which one wins must not be decided by the
/// order in the answer.
///
/// - Nothing remembered -> adopt.
/// - Different epoch -> adopt. The mark counts seconds SINCE
///   EPOCH START and is not comparable across the epoch
///   boundary; a record of the new epoch carries a small
///   mark and would otherwise stand no chance against the large mark of the old one.
/// - Same epoch -> only the larger or equal mark.
bool livenessIsNewer({
  required int newMark,
  required int newEpoch,
  int? previousMark,
  int? previousEpoch,
}) =>
    previousMark == null ||
    previousEpoch != newEpoch ||
    newMark >= previousMark;

/// The liveness tag of the pair in [epoch] and direction [direction].
///
/// Only whoever has `K_AB` can compute it — that is the KEX gate, and it is
/// the reason why a remote non-contact cannot steer specifically at a
/// victim (§10.1).
///
/// ── THE DIRECTION (§6, owner decision 2026-08-30) ─────────────
///
/// Without it BOTH partners store under the same mark, and whoever harvests
/// gets his own record back as well. If he adopted it as a
/// route, he would send every Speed message over his own return path
/// to himself.
///
/// It is THE SAME quantity as for the Secure mark (`secureTag`,
/// §15.2) — stored under the OUTGOING direction, harvested under the
/// opposite direction. That liveness did not carry it was not a design
/// but the same gap as B-22 on the Secure side, just one
/// layer further.
///
/// It costs nothing: each side stores its own R copies anyway,
/// they just coincided on one mark so far. What is gained is that a
/// responsible relay can no longer merge the two directions of a pair under
/// one mark.
Uint8List livenessTag(Uint8List kAb, int epoch, int direction) =>
    _hkdf(kAb, 'cleona-liveness', 'liveness/$epoch/$direction');

/// The decoy tags that accompany a query.
///
/// They are derived from a DEVICE-LOCAL secret, not rolled
/// randomly: a query that asks the same epoch twice with
/// different decoys reveals through the intersection which tag
/// was the real one. Derived from the secret they are stable over the epoch
/// and indistinguishable from real tags for the observer.
List<Uint8List> decoyTags(Uint8List deviceSecret, int epoch,
        {int count = kDecoyCount}) =>
    List.generate(
        count, (i) => _hkdf(deviceSecret, 'cleona-liveness', 'decoy/$epoch/$i'));

/// What a contact publishes so that one can reach it.
final class LivenessRecord {
  final int epoch;

  /// The onion return path, **opaque**. Built by WP-3, only carried here.
  final Uint8List returnPath;

  LivenessRecord({required this.epoch, required this.returnPath});

  /// Is this record valid in [epoch]?
  ///
  /// Tolerance ±1: clocks drift apart, and at the epoch change
  /// every delivery would fail on the second without tolerance.
  bool validIn(int e) => (e - epoch).abs() <= 1;
}

/// Where this record belongs: the point in the metric space around which
/// the R responsible ones lie (WP-0).
Uint8List livenessTarget(Uint8List kAb, int epoch, int direction) =>
    targetFor(livenessTag(kAb, epoch, direction), epoch);
