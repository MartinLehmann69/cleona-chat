// Which lane a media transfer takes — and whether it starts at all.
//
// THE SPEC (§9.3, after decision E-3 = D of 06.09.2026): "**Media
// travels one of three lanes**, decided per transfer — first by size,
// then by the viability cascade of §17.6, **never by silent
// preference**." That is why this is an extracted function and
// not a `?:` in the send path: a decision that is to be made "never by silent
// preference" must be exhaustively testable. The same
// rationale for which `delivery_api.dart:sendeModus` was extracted.
//
// NO STATE, NO I/O.
library;

import 'bulk_params.dart';

/// The three lanes from §9.3.
enum MediaLane {
  /// The media stream via a volunteer (§17.6). Stores nothing
  /// in the network, both sides connect OUTGOING to the volunteer.
  stream,

  /// The bulk lane (§9.3): each block placed once at an always-on holder,
  /// scanned by the receiver at its own cadence. The
  /// offline promise (j) beyond the cell size.
  bulk,

  /// The Reed-Solomon lane (§9.3, E-3 = D): stripes over cells, `N`
  /// fragments per `K` source blocks, fixed overhead `N/K` without
  /// a tail. It carries the band [kFountainWorthwhileBytes] to
  /// [kFountainLowerBoundBytes] — where the rateless coding according to
  /// its own measurement is worst AND most unpredictable.
  ///
  /// **Placement, holder and harvest are THE SAME as for [bulk]** — only the
  /// codec is a different one (`lib/core/codec/erasure_stripes.dart`, which
  /// also says why the wire does not change in the process).
  reedSolomon,
}

/// Why a transfer does not start at all.
enum MediaRefusal {
  /// Secure chat without explicit consent FOR THIS transfer
  /// (§9.3 "Mode coupling", §12).
  secureWithoutConsent,

  /// Too small for a media lane — that belongs on the cell path.
  ///
  /// **This is not a rejection of the TRANSFER, but of the LANE.** The
  /// caller then sends the object via `sendToUser`, where
  /// `routeFor` leads it onto the cell path (`cleona_service.dart`,
  /// branch `!aufMedienspur`). Since the lower bound lies at 32 KB and the
  /// cell path splits up to 32 768 B, the two ranges meet
  /// — there is no longer any size for which BOTH reject.
  ///
  /// Since S372 the NAME no longer says what lies behind it: below
  /// 32 KB it is no longer the fountain coding that is rejected,
  /// but every media lane. It stays nevertheless — it appears
  /// in guards, logs and field findings, and renaming it
  /// would be a change without benefit at a place where every
  /// change must be read.
  belowFountainThreshold,

  /// Larger than the block format carries (4 GiB - 1, `objectLength` is
  /// 4 B wide).
  aboveCodecLimit,
}

/// What comes out of the cascade.
final class MediaLaneDecision {
  final MediaLane? lane;
  final MediaRefusal? refusal;

  const MediaLaneDecision.take(this.lane) : refusal = null;
  const MediaLaneDecision.refuse(this.refusal) : lane = null;

  bool get accepted => lane != null;

  @override
  String toString() =>
      accepted ? 'Spur ${lane!.name}' : 'refused (${refusal!.name})';
}

/// The cascade from §9.3/§17.6.
///
/// ── SIZE COMES FIRST, THEN MODE COUPLING ─────────────────
///
/// The document names mode coupling first, and until 31.08.2026
/// it also came first here. But it only applies to a transfer that
/// enters a media lane at all: below the lower bound the
/// object travels the cell path in the chat's mode, without downgrade, i.e.
/// without anything to consent to. The rationale as a whole is
/// in the body.
///
/// For everything ABOVE the lower bound the order is unchanged:
///
/// §9.3: "A Secure chat sends media only after an explicit **per-transfer**
/// consent naming the linkability; a remembered blanket consent would be
/// the silent mode switch §12 exists to prevent. **Without consent nothing
/// is sent** — at most the one-cell micro-preview, at the ordinary §9.2
/// price."
///
/// All lanes are Speed class or weaker (B-29). A
/// media transfer in a Secure chat is thus a DOWNGRADE, and
/// the hard rule for that allows no silent path: Speed may fall back to Secure,
/// Secure never silently to Speed. [perTransferConsent] is
/// therefore a value PER TRANSFER. Whoever fills it from a stored
/// setting has broken the rule — not this function.
///
/// ── THEN THE GROUP ──────────────────────────────────────────────────
///
/// §17.6: "**The stream is pairwise (1:1) only:** a group transfer would
/// multiply the volunteer's forwarding by the member count, so group media
/// always take the bulk lane (encode once, place once, §9.3)."
///
/// ── THEN THE CAP, THEN REACHABILITY ─────────────────────────
///
/// §9.3: "Above `C` the transfer takes the bulk lane even with both
/// parties online — the cap is the volunteer's protection (D-1)."
///
/// ── AND THE REED-SOLOMON LANE COMES BEFORE ALL OF THAT (S372) ───────────
///
/// It is a CODEC decision, not a lane choice, and therefore it is decided
/// before group, cap and reachability. The evidence is in §9.3
/// itself: "**Blocks are lane-neutral.** Both lanes carry the same
/// **rateless** fountain blocks". Both previous lanes thus carry
/// the same codec — the measured weakness in the band 32..256 KB therefore hits
/// BOTH, and there is no reachability situation that would cure it.
/// A "stream, if a volunteer is there" would in this band be the
/// silent fallback to exactly the method that the decision replaces
/// there.
MediaLaneDecision chooseMediaLane({
  required int payloadBytes,
  required bool secureChat,
  required bool perTransferConsent,
  required bool isGroup,
  required bool bothOnline,
  required bool volunteerViable,
  int relayCapBytes = kRelaySizeCapBytes,
  int fountainThresholdBytes = kFountainWorthwhileBytes,
  int reedSolomonUpperBytes = kFountainLowerBoundBytes,
  int codecLimitBytes = 0xFFFFFFFF,
}) {
  // ── SIZE FIRST, THEN CONSENT (31.08.2026) ─────────
  //
  // Until today mode coupling came first. That was a
  // misordering with a visible consequence: an object BELOW the
  // lower bound enters no media lane at all — it travels the cell path
  // like any message, in the chat's mode, without any downgrade. There
  // is thus nothing there that anyone would have to consent to. Nevertheless
  // the consent dialog appeared, and a dialog that appears
  // without reason gets clicked away — and then also clicked away where it
  // means something. The point of §12 is that this question is NEVER
  // answered out of habit.
  //
  // The reverse would be wrong: for an object ABOVE the lower bound
  // consent must come before any lane choice, because ALL three
  // lanes are Speed class or weaker (B-29) — including the
  // Reed-Solomon lane that has been in between since S372. Therefore only
  // the two SIZE checks move to the front, nothing more.
  if (payloadBytes > codecLimitBytes) {
    return const MediaLaneDecision.refuse(MediaRefusal.aboveCodecLimit);
  }
  if (payloadBytes < fountainThresholdBytes) {
    return const MediaLaneDecision.refuse(MediaRefusal.belowFountainThreshold);
  }
  if (secureChat && !perTransferConsent) {
    return const MediaLaneDecision.refuse(MediaRefusal.secureWithoutConsent);
  }
  // ── THE BAND OF STRIPE CODING (S372, decision E-3 = D) ───────
  //
  // AFTER consent, because this lane too is Speed class (B-29)
  // and a Secure chat must explicitly consent for it as well —
  // but BEFORE the reachability cascade, because it chooses the codec and
  // not the carrier (rationale in the header of this function).
  //
  // Groups travel it too: §9.3 takes groups out of the STREAM lane
  // ("a group transfer would multiply the volunteer's forwarding"), and
  // that reason does not exist here — it is encoded once and
  // placed once, as with the bulk lane.
  if (payloadBytes < reedSolomonUpperBytes) {
    return const MediaLaneDecision.take(MediaLane.reedSolomon);
  }
  if (isGroup) return const MediaLaneDecision.take(MediaLane.bulk);
  if (payloadBytes > relayCapBytes) {
    return const MediaLaneDecision.take(MediaLane.bulk);
  }
  if (!bothOnline || !volunteerViable) {
    return const MediaLaneDecision.take(MediaLane.bulk);
  }
  return const MediaLaneDecision.take(MediaLane.stream);
}
