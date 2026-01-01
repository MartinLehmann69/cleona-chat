// The cover stream — the egress of a node, and the place where
// indistinguishability either holds or falls.
//
// THE ONE PROPERTY THAT CARRIES EVERYTHING.
//
// The slot plan is drawn BEFORE it is known whether there is something to send,
// and it does not change because there is something. A real cell
// SITS DOWN IN a slot that is due anyway; it does not add one
// (Arch §5.1, invariant 1). If this property falls, the whole
// cover idea falls: the positive control M1a has measured that an
// additionally sent cell collapses the inter-arrival time from 10 s to ~0 s
// — the moment of sending would again be an event.
//
// Therefore `_drawInterval()` draws exclusively from the random stream and
// never sees the queue. `smoke_cover_stream.dart` checks this
// mechanically: the same seed, once with and once without traffic, must
// yield the same slot sequence.
//
// WHAT IS IN HERE (and what not).
//
// In: the clock, the shared jitter, the aggregation per recipient,
// and the priority rule for ephemeral signals.
// Not in: the sealing (link layer) and the choice of the target relay
// (WP-3/WP-4). Invariant 4 — "target independent of the payload" — this
// file therefore cannot hold; it knows no target. That is stated here
// so that nobody gets the impression all four invariants have their
// place here.
//
// PARAMETER: `R_cover = 1/8 s` (E-C′). The value is explicitly
// revisable if practice speaks against it — it stands in exactly one
// place so that this stays one change.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/link/cell.dart' show kMaxFrameBodySize;
import 'package:cleona/core/sync/aggregate.dart';
import 'package:cleona/core/link/frame.dart' show LinkFrameType;

/// The cell size on the wire (Arch §5.1, AP-3a).
const int kCellBytes = 1200;

/// How much of it carries payload — from the frozen AP-3a format
/// (`link/cell.dart`), not guessed. The 950 that formerly stood here was
/// assumption A2 from M10.
const int kCellPayloadBytes = kMaxFrameBodySize;

/// How much payload may be AGGREGATED.
///
/// Not the same as [kCellPayloadBytes]: the onion (WP-3) uses
/// 128 B for seed, r2 identifier, path block and tag. What fits in here
/// is the message area of the onion — 1041 B, i.e. FIVE aggregated
/// short messages instead of the four that E-K had computed with the 950 B
/// assumption.
const int kAggregationBudgetBytes = kCellPayloadBytes - 128;

/// Builds the finished cell from an aggregated payload.
///
/// Passed in so that this file need not know the onion — and
/// so that it stays testable without cryptography. Gets `null` as
/// recipient when a dummy cell is due, and the partner over
/// which the slot goes.
typedef CellBuilder = Uint8List Function(
    String? recipient, Uint8List payload, int partner);

/// Mean distance between two slots.
///
/// ── CHANGED 11.09.2026 FROM 8 s TO 2 s (S381) ──────────────────────
///
/// **NEEDS THE OWNER'S RATIFICATION — §5.3 names `R_cover =
/// 1/8 s` and §31.5 the resulting 12.96 MB/day.** Both numbers
/// no longer match this value; the architecture text has NOT been
/// touched.
///
/// WHY, computed instead of estimated. A contact request is three
/// pieces; each costs `m x R` = 3 x 18..20 cells. Measured on
/// 11.09.2026 on `.201`: **162 frames for ONE request.** At one
/// cell per 8 s that is 21.6 minutes in which the node sends nothing
/// else — and `1a.03` gives up after 20 minutes. At 2 s it is
/// 5.4 minutes.
///
/// WHAT IT COSTS: 86400/2 = 43200 cells per day at 1200 B =
/// **51.84 MB/day** instead of 12.96. Saver mode absorbs this for Android
/// — [kDataSaverSlotFactor] goes from 4 to 16 in the same move, so that
/// tier 4 stays at an unchanged 3.24 MB/day (§31.3 "2-5 MB/day").
///
/// WHAT IT DOES NOT COST: §5.1. Indistinguishability depends on the
/// CONSTANT clock, not on its rate — an observer still sees
/// a byte-identical cell in a fixed rhythm, regardless of
/// whether the node has something to say.
const Duration kSlotInterval = Duration(seconds: 2);

/// ── DATA SAVER MODE (§24.4.2) ───────────────────────────────────────
///
/// By how much the slot clock is stretched in saver mode.
///
/// ── WHERE THE 4 COMES FROM (not guessed, computed) ─────────────────
///
/// The starting point is the one value the egress depends on:
/// `R_cover = 1/8 s` (E-C′, §5.3). That is `86400 / 8 = 10800` cells
/// per day at [kCellBytes] = 1200 B, i.e. **12.96 MB/day** — exactly the
/// number that §5.3 and the parameter table in §31.5 name.
///
/// The target is likewise in the document, namely where
/// saver mode is needed at all: §31.3 tier 4 (Android,
/// retention-bounded) gives as guideline **"2–5 MB/day cover"**.
/// The stretch factor `f` leads to `12,96 / f` MB/day:
///
///   f = 2,592  ->  5,00 MB/day   (upper band edge, no margin)
///   f = 4      ->  3,24 MB/day   (in the middle of the band)
///   f = 6,48   ->  2,00 MB/day   (lower band edge)
///
/// **f = 4** is chosen. Two reasons, both recomputable: the value
/// lies in the middle of the band instead of on an edge (the liveness cost
/// `1,15 + 0,23*S` MB/day from §6/M5 is NOT lowered by this mode — it is
/// pairwise and depends on the mode choice per chat, not on the cover), and
/// 8000 ms / 4 = 2000 ms divides evenly, so that the jitter span
/// (+/- 25 %) scales along without rounding drift.
///
/// ── WHAT IT SAVES ──────────────────────────────────────────────────
///
///   Cover:            12,96  ->  3,24 MB/day   (-9,72 MB/day)
///   Sum at S=10:      16,4   ->  6,7  MB/day   (-59 %)
///   Sum at S=20:      18,7   ->  9,0  MB/day   (-52 %)
///
/// The sums are those from §1.1 ("16–19 MB/day in total") and §5.3
/// (16.4 and 18.7 respectively); only the cover share is subtracted.
///
/// ── WHAT IT COSTS ──────────────────────────────────────────────────
///
/// Exactly what the consequence text MUST tell the user (§23.7 RL-8):
/// "a reduced cover share is visible from outside". Whoever sends less
/// than everyone else looks different. Moreover, every transmission stretches with the
/// clock: a Secure message costs `m x R` = 60 cells
/// (§9.2), i.e. 480 s at 8 s per slot and 1920 s at 32 s. That is the
/// reason why Secure is exempt from the mode — see [CoverSaver].
/// **CHANGED 11.09.2026 FROM 4 TO 16 (S381), together with
/// [kSlotInterval].** The purpose is unchanged: tier 4 is to lie in the
/// band "2-5 MB/day" from §31.3. With the new clock it is
/// `51,84 / 16 = 3,24 MB/Tag` — **exactly the same value as before with
/// 12,96/4.** The calculation in the text above thus still applies, only with
/// the new starting value. 2000 ms x 16 = 32 s divides just as evenly
/// as before 8000/4 = 2000 ms.
const int kDataSaverSlotFactor = 16;

/// What the setter reports back.
enum CoverSaverOutcome {
  /// The mode is now on.
  enabled,

  /// The mode is now off.
  disabled,

  /// **Refused** because at least one chat is set to Secure (§24.4.2).
  refusedSecureActive,
}

/// The data saver mode — a state, node-wide.
///
/// ── THE FOUR CONSTRAINTS FROM §24.4.2, AND WHERE THEY ARE HERE ──────
///
/// 1. "a visible state, not a setting buried in a submenu" — carried by the
///    UI (`settings_screen`, `network_stats_screen` §25.4).
/// 2. The consequence must be named ("less cover traffic — this makes
///    your node easier to recognize from outside") — i18n
///    `datasaver_consequence`.
/// 3. "the app may suggest but must never activate it itself" — in
///    this file there is NO caller of [request]; the only way
///    in leads via `ICleonaService.setDataSaver`, and the only
///    caller of that is a user press. `smoke_data_saver.dart` checks
///    this mechanically on the source text.
/// 4. **Secure is exempt without exception** (owner, 2026-08-30).
///
/// ── ON 4: WHY THE LATCH SITS AT THE SETTER AND NOT AT THE DISPLAY ───
///
/// §24.4.2: "The cover stream is a node-wide stream, not per chat — so a
/// node holding even one Secure chat keeps it in full, and the switch is
/// then locked with its reason named." A greyed-out switch is
/// too little for that: it holds exactly as long as nobody sets it
/// past the UI. Therefore the latch lies HERE, at the
/// only place that knows the clock.
///
/// It acts twice, and both are needed:
///
///   • [request] REFUSES as long as a Secure chat exists. The wish
///     is not remembered — a remembered wish that later strikes by
///     itself would be the automatic activation from constraint 3.
///   • [slotFactor] asks again on EVERY draw. If Secure is
///     switched on while saver mode runs, the stream returns to full rate
///     at the same moment — without anyone having to call a
///     setter. Without this second half there would be a
///     time window in which a Secure chat lay in thinned cover,
///     and that is exactly the silent mode switch that §12 excludes:
///     "Speed may fall back to Secure, Secure NEVER silently to Speed."
///
/// ── WHY NODE-WIDE AND NOT PER SERVICE ──────────────────────────────
///
/// Because the cover stream is. A process can carry several identities
/// (multi-identity), they share the egress — so the
/// Secure question must be asked over ALL of them. [bindSecureProbe] therefore collects
/// probes instead of replacing one: a single identity with
/// one Secure chat keeps the stream full for the whole node.
///
/// ── WHY A PROCESS-WIDE OBJECT AND NOT A CONSTRUCTOR ARGUMENT ────────
///
/// The `CoverStream` instance is created in `V41Node` (`speed_egress.dart`),
/// and the only handle the service has on it is the
/// interface `V41Delivery` — it carries pairs and bytes, no
/// clock. The state is node-wide anyway (see above), so a
/// node-wide object is not the detour, but the form. Whoever may later
/// extend `V41Delivery` can pass the probe in instead;
/// the effect would stay the same, because [slotFactor] is the
/// only place that hands out the factor.
final class CoverSaver {
  /// The one state of the node.
  ///
  /// **The name is `instance` and not `node`**, although the state
  /// is node-wide: `smoke_seam_node_member_guard.dart` counts in `lib/`
  /// every `…node.<member>` as an access of the application to the
  /// V3 transport (AP-1 step 7). `CoverSaver.node.slotFactor` reads
  /// exactly like that for this guard — measured 2026-08-31, it turned
  /// red because of it. Extending the exception list would have made a
  /// naming accident a permanently blind spot; the name
  /// is the cheaper and right correction.
  static final CoverSaver instance = CoverSaver._();

  CoverSaver._();

  bool _wanted = false;

  final Map<Object, bool Function()> _secureProbes =
      <Object, bool Function()>{};

  /// Probes for the consented LAN switch-off (S373).
  ///
  /// SEPARATE from [_secureProbes] and deliberately not mixed into them:
  /// the two answer opposite questions. A Secure probe
  /// says "keep the stream FULL", a LAN probe says "here it may be off".
  /// Merged, one answer would run into the other, and the latch
  /// that carries the hard rule would hang on the same loop as its
  /// exception.
  final Map<Object, bool Function()> _lanProbes = <Object, bool Function()>{};

  /// Registers a probe that says whether [owner] currently has a
  /// Secure chat. A second call with the same [owner]
  /// replaces the probe.
  void bindSecureProbe(Object owner, bool Function() probe) {
    _secureProbes[owner] = probe;
  }

  /// Unregisters the probe again (identity deleted, service ended).
  void unbindSecureProbe(Object owner) {
    _secureProbes.remove(owner);
  }

  /// Whether anywhere on this node a chat is set to Secure.
  ///
  /// If a probe throws, that counts as "yes". Fail-closed is the
  /// only defensible direction here: the opposite direction would thin
  /// the stream of a Secure chat in the error case.
  bool get lockedBySecure {
    for (final probe in _secureProbes.values) {
      try {
        if (probe()) return true;
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  /// Registers a probe that says whether [owner] currently is EXCLUSIVELY
  /// in a consented segment (S373).
  void bindLanConfinedProbe(Object owner, bool Function() probe) =>
      _lanProbes[owner] = probe;

  /// Unregisters it again (identity deleted, node stopped).
  void unbindLanConfinedProbe(Object owner) => _lanProbes.remove(owner);

  /// Is the whole node in a consented segment?
  ///
  /// ── FAIL-CLOSED, THREEFOLD — AND THE OTHER WAY ROUND FROM [lockedBySecure] ──
  ///
  /// [lockedBySecure] falls to "yes, lock" in doubt. Here the
  /// safe answer is the opposite, so doubt falls to
  /// "no, do not switch off":
  ///
  ///  * **NO probe registered -> `false`.** Whoever says nothing has
  ///    not consented. A `true` for an empty set would be a
  ///    switch-off arising from a MISSING wiring — exactly
  ///    the error class that S360 and S367 each found four times
  ///    ("built, never entered"), only here with a loss of anonymity
  ///    as the consequence instead of an outage.
  ///  * **ONE probe with no suffices.** The egress is node-wide; a
  ///    single identity with an outside partner keeps the stream
  ///    full for all. The same reasoning as for [bindSecureProbe],
  ///    only with the opposite sign.
  ///  * **A probe that THROWS -> `false`.** An error must never
  ///    lead to a switch-off.
  bool get lanConfined {
    if (_lanProbes.isEmpty) return false;
    for (final probe in _lanProbes.values) {
      try {
        if (!probe()) return false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Is the LAN switch-off in effect NOW?
  ///
  /// ── SECURE OVERRIDES IT, WITHOUT EXCEPTION ─────────────────────────
  ///
  /// The same latch as in saver mode and for the same reason (§24.4.2,
  /// owner 2026-08-30): the cover stream is node-wide, so a
  /// single Secure chat keeps it full. And as there, it is asked anew on EVERY
  /// draw instead of being cached once — if a
  /// Secure chat arises while the switch-off runs, the stream returns to full rate in the
  /// same slot, without anyone having to call a setter.
  /// Without this second half there would be a window in
  /// which a Secure chat ran uncovered, and that is the silent
  /// mode switch from §12: "Speed may fall back to Secure, Secure
  /// NEVER silently to Speed."
  ///
  /// The consent itself stays in place ([lanConfined] still says
  /// "yes") — it is not revoked, but overridden. The
  /// difference between "the user has withdrawn it" and "the
  /// situation does not allow it right now" must stay readable, otherwise
  /// the UI shows a revocation that nobody has explained.
  bool get lanShapingActive => lanConfined && !lockedBySecure;

  /// Whether the user has chosen the mode. **Not** the same as
  /// [active]: the latch can override it.
  bool get requested => _wanted;

  /// Whether the mode is IN EFFECT.
  bool get active => _wanted && !lockedBySecure;

  /// The factor by which the slot distance is stretched — 1 means
  /// "full rate". Asked anew on every draw.
  int get slotFactor => active ? kDataSaverSlotFactor : 1;

  /// The ONLY way to set the mode. Only the user calls this
  /// (constraint 3, §24.4.2).
  CoverSaverOutcome request(bool on) {
    if (on) {
      if (lockedBySecure) return CoverSaverOutcome.refusedSecureActive;
      _wanted = true;
      return CoverSaverOutcome.enabled;
    }
    // SWITCHING OFF ALWAYS WORKS. The latch protects the cover stream, not
    // the switch: switching it off leads to MORE cover, never to
    // less.
    _wanted = false;
    return CoverSaverOutcome.disabled;
  }

  /// Resets the state — exclusively for tests, so that one
  /// case does not colour the next.
  void resetForTest() {
    _wanted = false;
    _secureProbes.clear();
    _lanProbes.clear();
  }
}

/// How many self-initiated control frames may wait at most.
///
/// A DEADLINE, EXPRESSED IN SLOTS. The time slice carries exactly one
/// cell (§5.1 invariant 1), so the queue depth IS the waiting time:
/// 120 frames are 120 time slices are, at `kSlotInterval` = 8 s,
/// **960 s, i.e. 16 min**.
///
/// ── WHERE THE 120 COME FROM ────────────────────────────────────────
//
/// Not from a feeling for "enough buffer", but from the largest
/// frame group that a node regularly queues. `V41Node.placeSecure`
/// places a Secure message with ALL responsible ones: `m x R` =
/// `kDeliveryFamilies` (3) x `kResponsibleRelays` (20) = **60 frames at
/// once**, and §9.2 budgets exactly that. A cap below 60 would
/// cut off a single, entirely regular Secure transmission midway
/// — the redundancy would be silently halved, and the cap would create a
/// defect instead of preventing one. 2 x 60 lets a second transmission
/// join before the node starts to discard.
///
/// THE COUPLING IS CHECKED, NOT INHERITED. `core/sync/` lies BELOW
/// `core/tagline/` (this file is imported there, not the other way round);
/// pulling the constants from there in here would invert the layering.
/// The number is therefore written out, and
/// `smoke_control_queue_backlog.dart` checks `kMaxControlBacklog >= m x R`
/// against the real constants — if `kResponsibleRelays` grows, the
/// test turns red instead of the node going silent.
///
/// ── WHAT THE CAP IS NOT ────────────────────────────────────────────
//
/// It is no throughput solution. The throughput is fixed: 60 cells per
/// Secure message against one cell per 8 s are **480 s per message**,
/// i.e. at most three in 24 minutes. This bound comes from §9.2 and
/// §5.3 and does not change with any queue size. The cap
/// alone decides what happens when more is queued than
/// can go out: discard instead of grow.
/// ── CHANGED 11.09.2026 FROM 120 TO 360 (S381) ─────────────────────
///
/// **TOUCHES THE OWNER'S DECISION C (31.08.) AND NEEDS HIS
/// RATIFICATION.** Decision C says: the cap does NOT grow with the
/// SAVER FACTOR. That stays so — here it depends on no saver-mode
/// quantity. What changes is the derivation above, and it was
/// demonstrably incomplete.
///
/// THE ERROR IN THE OLD DERIVATION: it names as the largest group
/// "`m x R` = 60 frames at once" and doubles to 120. The
/// PIECE factor is missing. §9.2 states it explicitly: "Per *message* the
/// figure is a multiple of that wherever the sealed payload spans more
/// than one cell." A contact request is three pieces.
///
/// MEASURED on 11.09.2026, `.201`, contact request `mOYZm0qv`:
///
///     Family 0:  piece 0 = 18 of 18 discarded | piece 1 = 17/18
///     Family 1:  piece 0 = 18 of 18 discarded | piece 1 = 17/18
///     Family 2:  piece 0 = 18 of 18 discarded | piece 1 = 18/18
///
/// Piece 0 went out in NO family; the recipient stood at
/// `empfangen 0` after twenty minutes. The cap here created exactly the
/// defect that its own justification claims to
/// prevent ("a cap below 60 would cut off a single, entirely
/// regular Secure transmission midway").
///
/// THE NEW NUMBER: `2 x 3 pieces x m(3) x R(20)` = 360. The same
/// construction as before — two full transmissions —, only with the piece factor
/// in it. At [kSlotInterval] = 2 s, 360 frames are **12 minutes**
/// of backlog, i.e. LESS than the 16 min that 120 frames at 8 s
/// meant. The objection from section 6 of the saver-mode guard
/// ("a frame could get 4.3 h old") thus does not apply.
// UPDATED 18:10 (S381): 360 did not suffice in the field. Measured on
// `.202` in the run 17:49: `Kontrollschlange 323/360, verworfen 181,
// Ablagen verworfen 165` — the acceptance answer was still being
// cut. 1024 covers two full transmissions PLUS the liveness of a
// node with several pairs; at 2 s per slot that is 34 min of
// backlog in the theoretical full state, in measured operation around 400
// frames = 13 min.
const int kMaxControlBacklog = 1024;

/// ── AND IT DOES NOT GROW WITH SAVER MODE (owner, 31.08.2026) ──────────
///
/// With [kDataSaverSlotFactor] = 4 the slot becomes 32 s, the 120 frames are
/// then **64 min** instead of 16. The obvious answer would be to scale the cap
/// along (120 -> 480). It is rejected, for two
/// computed reasons:
///
///   * 480 frames at 1200 B are **576 KB** of queue, and a frame
///     could get up to 4.3 h old before it leaves — it would then
///     possibly have been built for an epoch that is over.
///   * The case does not occur at all where it would hurt. Saver mode is
///     **exempt** for Secure (§24.4.2, `CoverSaver.lockedBySecure`),
///     and only Secure queues `m x R` = 60 frames at once. Speed
///     queues **one** per message; the cap is never
///     reached there.
///
/// The decision thus reads: saver mode applies to pure
/// Speed operation, and there the cap suffices. Whoever runs Secure has
/// the full clock and the full 16 min — not as a makeshift, but as an
/// intended state.

/// A piece of payload that is to go on its way.
final class Outgoing {
  /// To whom — only equal recipients may share a cell.
  final String recipient;
  final Uint8List payload;

  /// Ephemeral signals (typing indicator, read receipt, reaction) ride along
  /// only on free capacity and are DISCARDED instead of queued.
  final bool ephemeral;

  Outgoing(this.recipient, this.payload, {this.ephemeral = false});
}

/// What a slot outputs: always exactly one cell.
final class SlotOutput {
  /// The frame, always [kCellPayloadBytes] long, padded.
  final Uint8List frame;

  /// To whom the cell goes — `null` for a dummy cell.
  ///
  /// **Local only.** This distinction exists for statistics and
  /// tests; on the wire both cases are byte-identical.
  final String? recipient;

  /// How many payloads are in this cell (E-K, aggregation).
  final int packed;

  /// Over which partner the slot goes — drawn by the plan, not
  /// chosen (invariant 4).
  final int partner;

  /// The raw, unpacked PAYLOADS (not ephemeral) that `takeSlot()`
  /// has already taken out of the queue for [recipient] — `null`
  /// for a dummy cell or a control frame.
  ///
  /// SOLELY FOR A RE-OFFER ON FAILED SENDING (D-3,
  /// S372): if the send attempt in `DeliveryNode.tick()` fails AFTER
  /// `takeSlot()` has already removed them, they would otherwise be gone without replacement —
  /// the slot is used up (invariant 1), but the payload must not
  /// be. Ephemeral signals are deliberately NOT included: they ride
  /// only on free capacity and are discarded instead of queued anyway
  /// ([Outgoing.ephemeral]) — a send failure must not lift them
  /// into guaranteed delivery.
  final List<Uint8List>? rawPayloads;

  /// Whether this cell is NOT to see the wire (S373).
  ///
  /// ══════════════════════════════════════════════════════════════════
  /// WHICH OF THE FOUR INVARIANTS FROM §5.1 FALLS HERE — AND WHICH NOT
  /// ══════════════════════════════════════════════════════════════════
  ///
  /// **Invariant 1 (constant rate, no-spike) IS GIVEN UP.** As long as
  /// this mark is set, a cell only goes out when
  /// it carries something. The number of cells per time thus IS the
  /// demand: `I(r; t) > 0`. That is exactly the property whose
  /// loss the user has consented to, and it is not glossed over
  /// here — the positive control M1a describes exactly this
  /// state as the error case that the cover stream otherwise prevents.
  ///
  /// **Invariant 2 (fixed size, 1200 B) STAYS.** A cell that
  /// goes out runs through the same construction as before.
  ///
  /// **Invariant 3 (sealed content) STAYS.** Nothing changes about the
  /// sealing.
  ///
  /// **Invariant 4 (target independent of the payload) STAYS — and
  /// MECHANICALLY, not as an assurance.** The suppression applies
  /// strictly AFTER `drawInterval()` and `drawPartner()`; both draw
  /// unchanged from the demand-independent stream and consume
  /// the same random values as without it. The plan thus shifts
  /// by not a single draw — if the consent is dropped, the
  /// stream continues exactly where it would stand without it.
  /// Were it otherwise, even the RETURN to full cover would be an event, and the
  /// switch-off would have betrayed itself.
  /// `smoke_lan_cover_shaping.dart` section 5 measures exactly that, with
  /// counter-check.
  ///
  /// ── WHAT THIS TRADES AGAINST, AND WHAT NOT ─────────────────────────
  ///
  /// What is given up is indistinguishability TOWARDS THE OWN
  /// SEGMENT — and only there. The condition for this mark is that
  /// EVERY partner of this cell lies in the consented segment
  /// (`V41Node.lanConfined`); there is then no cell flow that leaves the
  /// segment. What an observer outside sees is the
  /// egress of the forwarding neighbour, and that is its own,
  /// untouched cover stream. The observer who gains something here
  /// sits by construction in the user's living room — and exactly
  /// therefore, and only therefore, is the consent one that a human
  /// can give at all.
  final bool suppressed;

  bool get isDummy => recipient == null;

  SlotOutput(this.frame, this.recipient, this.packed, this.partner,
      {this.rawPayloads, this.suppressed = false});
}

final class CoverStream {
  final Duration meanInterval;

  /// How much may be aggregated per cell.
  final int aggregationBudget;

  /// How a cell is made from the payload. Without it the payload stays
  /// as it is — that is the test case without cryptography.
  final CellBuilder? cellBuilder;

  /// The cap of the control queue. See [kMaxControlBacklog];
  /// mutable only so that a test can tighten it.
  final int maxControlBacklog;

  /// Over how many partners the slots rotate.
  ///
  /// **Invariant 4 (§5.1): the target does not depend on the payload.** If
  /// dummy cells went to other partners than real ones, the TARGET would reveal
  /// the content — the sealing would be in vain. Therefore the
  /// SLOT PLAN also draws the partner, from the same demand-independent
  /// stream as the time. Whoever wants to send builds for the partner they
  /// get; they do not choose it.
  ///
  /// Mutable because connections come and go. That does NOT touch the
  /// demand independence: `_rng.nextInt(n)` consumes one
  /// draw, no matter how large `n` is — the SEQUENCE of draws stays
  /// the same, only its mapping onto partners changes. And the
  /// partner count depends on reachability, not on whether there is something to
  /// send.
  int partnerCount;

  /// Randomness EXCLUSIVELY for the slot plan (time AND partner).
  final Random _rng;

  /// Randomness for the padding — STRICTLY SEPARATE.
  ///
  /// If the filling drew from the same stream, the slot plan would again depend
  /// on the demand: without traffic more dummy bytes are drawn, the
  /// interval sequence would shift, and invariant 1 would be broken —
  /// exactly this way, through the back door. The test caught it.
  final Random _padRng;

  /// Queue of real payloads, in the arrival order of the
  /// recipients — whoever had something pending first gets the slot.
  final List<String> _order = <String>[];
  final Map<String, List<Uint8List>> _real = <String, List<Uint8List>>{};
  final Map<String, List<Uint8List>> _ephemeral = <String, List<Uint8List>>{};

  int _droppedEphemeral = 0;

  /// Self-initiated control frames (placement, harvest, peer exchange).
  ///
  /// They take a SLOT because they originate from the node — unlike
  /// answers, which are forwarding traffic (`CellTransport.emitControl`).
  /// They have priority over messages: a harvest that waits behind
  /// chat traffic delays delivery for all contacts.
  ///
  /// `group` holds together what `enqueueFrames` queued as ONE split payload
  /// — see [_pushControl] for why that matters when discarding.
  ///
  /// `forwarded` says whether the frame is FOREIGN traffic running
  /// through this node. It is almost always `false` — the queue carries
  /// self-initiated frames by definition —, but exactly one place
  /// queues foreign traffic: `DeliveryNode.redispatchBlind` forwards a blindly
  /// kept foreign placement, and does so via THIS queue instead of
  /// immediately, because an immediate spike would reveal the size and timing of the
  /// blind stock (reasoning there).
  ///
  /// WHY THE FLAG TRAVELS ALONG HERE AND IS NOT BOOKED ON QUEUEING:
  /// this queue DISCARDS on overflow (`_pushControl`, `_droppedControl`).
  /// Whoever booked on queueing would count bytes as forwarded that never
  /// saw the wire — the same class "number that looks like a
  /// measurement" against which `smoke_network_stats` is built. Booking
  /// therefore happens only where the frame actually goes out
  /// (`DeliveryNode.tick`).
  final List<
      ({
        int type,
        Uint8List body,
        int group,
        bool sacrificable,
        bool forwarded
      })> _control = [];

  /// Running number of the frame groups. A frame queued individually is
  /// a group of its own.
  int _nextControlGroup = 0;

  int _droppedControl = 0;
  int _maxControlDepth = 0;

  CoverStream({
    this.meanInterval = kSlotInterval,
    this.aggregationBudget = kAggregationBudgetBytes,
    this.cellBuilder,
    this.partnerCount = 1,
    this.maxControlBacklog = kMaxControlBacklog,
    required int seed,
  })  : seed = seed,
        _rng = Random(seed),
        _padRng = Random(seed ^ 0x5f5f5f);

  /// The seed from which the slot plan of this stream is drawn.
  ///
  /// ── WHY IT IS MANDATORY AND NO LONGER HAS A DEFAULT (S376) ────────
  ///
  /// Until S375 this said `int seed = 0`. The only producer in `lib/`
  /// — `V41Node.start` via `SpeedEgress` — accepted the default
  /// (`v41_node.dart`, `seed: 0`, unchanged since `98836b2a`). Thus
  /// EVERY shipped node drew the same interval and
  /// partner sequence: `Random(0)` is deterministic in Dart and
  /// publicly recomputable. An observer who sees a few
  /// inter-arrivals of any node thereafter knows
  /// its entire future slot sequence — and that of every other
  /// node too. §5.2 ("shared jitter") and §7.3 (window "one
  /// slot interval plus jitter") presuppose exactly the opposite:
  /// the jitter is to hide the moment of sending. A predictable
  /// jitter hides nothing.
  ///
  /// A default can only repeat this error — it is by
  /// construction the same on all nodes. Therefore there is none anymore:
  /// whoever builds a stream must say where its seed comes from. Tests
  /// deliberately set fixed seeds (reproducibility is the purpose
  /// there); the node draws it from the CSPRNG.
  ///
  /// Readable because the statement "two nodes have different
  /// slot plans" would otherwise only be checkable by consuming the running plan.
  /// The value is process-local and never leaves the
  /// node.
  final int seed;

  /// The partner over which the next slot goes. From the slot stream,
  /// not from the queue.
  int drawPartner() => partnerCount <= 1 ? 0 : _rng.nextInt(partnerCount);

  /// How many ephemeral signals have been discarded so far.
  int get droppedEphemeral => _droppedEphemeral;

  /// The distance to the next slot.
  ///
  /// Drawn from a uniformly distributed span around the mean — the
  /// **shared jitter** from §5.2: it applies to dummy and real slots
  /// alike, otherwise the two would separate on the variance. The
  /// queue does not enter here, and that is the whole point.
  ///
  /// ── THE ONE INPUT FOR DATA SAVER MODE (§24.4.2) ───────────────────
  ///
  /// [CoverSaver.slotFactor] stretches the fully drawn distance. The
  /// order is essential: first draw, then stretch. If the
  /// factor entered the draw (say via `spread`), a
  /// saver-mode run would consume different random values than a full one — the slot sequence
  /// would then depend on the switch instead of only the scale, and the comparison that
  /// `smoke_cover_stream.dart` makes for invariant 1 would lose its
  /// reference point. This way the SEQUENCE stays the same, only its scale
  /// changes.
  ///
  /// The factor is asked anew on EVERY draw, not cached
  /// once: only thus does the stream fall back to full rate at the moment
  /// a Secure chat arises anywhere.
  Duration drawInterval() {
    final ms = meanInterval.inMilliseconds;
    final spread = (ms * 0.5).round();
    final drawn = ms - spread ~/ 2 + _rng.nextInt(spread + 1);
    return Duration(milliseconds: drawn * CoverSaver.instance.slotFactor);
  }

  /// Queues a self-initiated control frame.
  ///
  /// [sacrificable] marks frames that may fall FIRST on overflow
  /// — see [_pushControl]. They are the repeated queries
  /// (harvest, liveness follow-up): they come back by themselves, whereas
  /// a placement is the message ITSELF and is lost with it.
  /// Default is `false`: whoever says nothing is not sacrificed.
  ///
  /// [forwarded] marks FOREIGN traffic running through this node
  /// (see [_control]). Default is `false`, because this queue by
  /// definition carries self-initiated frames; only `redispatchBlind`
  /// sets it. The flag decides in `DeliveryNode.tick` whether the bytes
  /// are booked as forwarding when going out.
  void enqueueControl(Uint8List frameBody,
          {bool sacrificable = false, bool forwarded = false}) =>
      _pushControl([(type: LinkFrameType.control, body: frameBody)],
          sacrificable: sacrificable, forwarded: forwarded);

  /// Queues a control frame at the FRONT.
  ///
  /// ── WHAT FOR, AND WHY THIS IS NO PRIVILEGE (S354, field finding) ────
  ///
  /// Measured on 30.08. in the lab network: a text message without a Speed route
  /// queues `m x R` = 60 placements (four pieces x three families x five
  /// known relays). The queue then stood at 76 frames, i.e. about
  /// ten minutes. The request for the liveness — the ONE cell that
  /// ends this state — stood at the back and would have gone out at the earliest after
  /// these ten minutes. As long as it waits, EVERY
  /// further message again costs 60 cells.
  ///
  /// The priority is therefore not favouritism, but a calculation:
  /// one cell now saves sixty per message afterwards. And what it
  /// overtakes is the redundancy of a message that is already in transit
  /// — being placed one slot later costs it nothing
  /// measurable.
  ///
  /// NOTHING CHANGES TOWARDS THE OUTSIDE. The slot clock still emits exactly one
  /// byte-identical cell per slot; only which
  /// ciphertext sits in which slot is swapped. Invariant 1 speaks about the
  /// RHYTHM, not about the order.
  ///
  /// The caller must restrict itself — there is no cap here that would
  /// do it for it. `V41Node.prepareSpeed` does it
  /// (`kLivenessAttemptsPerEpoch`).
  void enqueueControlFirst(Uint8List frameBody) {
    final g = _nextControlGroup++;
    // `forwarded: false` — the priority exists for self-initiated
    // frames (liveness, own entry record). Foreign
    // traffic does not jump the queue here.
    _control.insert(
        0,
        (
          type: LinkFrameType.control,
          body: frameBody,
          group: g,
          sacrificable: false,
          forwarded: false
        ));
    if (_control.length > _maxControlDepth) {
      _maxControlDepth = _control.length;
    }
  }

  /// Puts back a control frame that `takeControl()` had already
  /// taken out but whose send attempt failed (D-3, S372).
  ///
  /// At the FRONT, for the same reason as [enqueueControlFirst]: the frame was
  /// already due, a re-delivery should not fall back behind younger
  /// requests. UNLIKE [enqueueControlFirst] this
  /// method passes [forwarded] through instead of fixing it to `false` —
  /// otherwise a later successful forwarding would wrongly be booked as
  /// own traffic, because `DeliveryNode.tick()` hangs the booking on exactly
  /// this flag.
  void requeueControl(int type, Uint8List body, {bool forwarded = false}) {
    final g = _nextControlGroup++;
    _control.insert(
        0,
        (
          type: type,
          body: body,
          group: g,
          sacrificable: false,
          forwarded: forwarded,
        ));
    if (_control.length > _maxControlDepth) {
      _maxControlDepth = _control.length;
    }
  }

  /// Queues a split payload at the FRONT, as one group.
  ///
  /// ── WHAT FOR (S355) ───────────────────────────────────────────────
  ///
  /// For the own entry record when building a session. It
  /// is the reason why a partner appears in the responsibility calculation
  /// at all: `responsibleRelays` demands a record for every position
  /// (`entries.lookup(...) == null -> continue`), and
  /// a session delivers only the POSITION, not the record.
  ///
  /// In the field on 30.08. that was the closed circle: the queue stood
  /// at 116 of 120, the announcement would have waited in it about a quarter of an hour,
  /// so the record was missing — and without it, of all things,
  /// the two LIVE relays fell out of the responsibility set, while
  /// phantoms (records without a reachable node) stayed in it. The
  /// recipient then asked 8 relays, of which 6 did not exist, and
  /// harvested nothing. Because nothing arrived, no receipt came; because no
  /// receipt came, the day capsule kept travelling along; because it travelled along,
  /// every message cost two pieces instead of one and thus 120 frames
  /// instead of 60. The circle closes at this one cell.
  ///
  /// TWO FRAMES, ONCE PER SESSION. That is the whole calculation; a
  /// quota is not needed because sessions do not arise
  /// arbitrarily often. Queued as a GROUP so that the record is not
  /// halved (see `_pushControl`).
  ///
  /// NOTHING CHANGES TOWARDS THE OUTSIDE: same clock, same cell count,
  /// only a different order (invariant 1 speaks about the
  /// rhythm).
  void enqueueFramesFirst(List<({int type, Uint8List body})> frames) {
    if (frames.isEmpty) return;
    final g = _nextControlGroup++;
    for (var i = 0; i < frames.length; i++) {
      _control.insert(i, (
        type: frames[i].type,
        body: frames[i].body,
        group: g,
        sacrificable: false,
        // The own entry record — own traffic, not forwarding.
        forwarded: false
      ));
    }
    if (_control.length > _maxControlDepth) {
      _maxControlDepth = _control.length;
    }
  }

  /// Queues fully split frames — the return value of
  /// `fragmentFrame`. Several fragments occupy several slots; that is
  /// intended and the price for a large content not
  /// bulging the stream.
  void enqueueFrames(List<({int type, Uint8List body})> frames,
          {bool sacrificable = false}) =>
      _pushControl(frames, sacrificable: sacrificable);

  /// Queues a frame group and keeps the queue at [maxControlBacklog].
  ///
  /// ── WHY DISCARDING HAPPENS HERE AT ALL (S353) ──────────────────────
  //
  /// The inflow is larger than the outflow, and structurally, not
  /// at load peaks. `DeliveryNode.tick()` takes exactly
  /// ONE frame per time slice — it must not be more, see below. More is
  /// queued, measured over 400 time slices with the real cadence from
  /// `V41Node.run()`:
  ///
  ///   `kHarvestRequestsPerRun` = 6  ->  1,625 in / 1,0 out,
  ///                                     +281 frames per hour
  ///   `kHarvestRequestsPerRun` = 60 -> 15,125 in / 1,0 out,
  ///                                    +6356 frames per hour
  ///
  /// The second line is the current state (`m x R`, S353). Without a cap
  /// the queue keeps growing linearly, and with it the waiting time of every
  /// newly queued frame — after one hour a fresh
  /// harvest job leaves 14 hours later. That is no memory problem,
  /// but a delivery problem.
  ///
  /// ONLY THE INFLOW HELPS AGAINST THE INFLOW. For this the harvest has had
  /// its own brake since S353 (`V41Node.kHarvestBacklogLimit`: a run
  /// pauses as long as frames are already waiting here). All
  /// other sources stay unbraked — `placeSecure` (60 at once), `probePlacement`,
  /// `publishLiveness`, `announcePeers`, `requestEntries`,
  /// `DeliveryNode.redispatchBlind` —, and none of them asks beforehand how
  /// full it is. This cap is the safety net underneath, not the
  /// replacement for the brake.
  ///
  /// ── WHY NO MORE IS TAKEN OUT ───────────────────────────────────────
  //
  /// Because it costs anonymity, not because it would be inconvenient. §5.1
  /// invariant 1: "A real cell *replaces* an already-scheduled dummy slot;
  /// it does not add a cell." A time slice carries exactly ONE cell. Whoever
  /// took out two with a full queue would make the number of cells per
  /// time slice depend on the queue's fill level — and that depends on
  /// the demand. `I(r; t) > 0`, exactly the spike that the
  /// positive control M1a measured. Moreover it would double the
  /// output volume from 12.96 to 25.9 MB/day and thus leave the band
  /// from §5.3 (15–25 MB/day).
  ///
  /// ── WHY THE OLDEST GO ──────────────────────────────────────────────
  //
  /// A waiting harvest job ages badly. It carries the relay that was
  /// looked up on queueing, and the have-list
  /// (`HarvestMemo.declare`) from back then; the next harvest run asks
  /// the same families again with fresher data. And at some point it can
  /// no longer be matched: `V41Node` remembers the request identifiers in
  /// a FIFO of `kOwnRequestMemory` = 256 entries that is filled on QUEUEING
  /// — if a job waits longer than 256 subsequent ones,
  /// its identifier is displaced and the answer to it undeliverable. The
  /// youngest job is thus the better one in every respect.
  ///
  /// ── WHY GROUP-WISE ─────────────────────────────────────────────────
  //
  /// `enqueueFrames` queues the pieces of ONE split payload
  /// (`announceOwnEntry`: an entry record ~1.3 KB, i.e. two
  /// pieces). If only the head piece falls out of it, the rest
  /// still go out, occupy slots and are discarded at the recipient by
  /// `FrameReassembler` as orphans — paid cells without
  /// effect. Therefore the whole oldest group is always discarded.
  ///
  /// The youngest group is NEVER discarded: otherwise a payload
  /// that is by itself already larger than the cap could throw itself
  /// away. The cap is thereby exceeded by at most one group
  /// — bounded above by
  /// `FrameReassembler.maxPayloadBytes` (16 KB), i.e. at most 15 pieces.
  ///
  /// ── WHAT IS SACRIFICED IS NOT IRRELEVANT (S355) ────────────────────
  ///
  /// What was discarded was the OLDEST group, regardless of what it
  /// carries. In a queue that a Secure transmission fills with `m x R`
  /// placements and into which queries move up afterwards, the
  /// oldest group is almost always a PLACEMENT — i.e. exactly what makes up the
  /// message. The queries, which come back by themselves,
  /// survived.
  ///
  /// Measured on 30.08.: after the harvest cap
  /// (`kHarvestMaxSkips`) let the harvest start again,
  /// `droppedControl` rose from 102 to 512 (Alice) and from 25 to 628 (Bob) —
  /// and 0 of 6 messages arrived instead of 1 and 2. The harvest ran
  /// (24 requests per node instead of 3 and 0), but it displaced the
  /// placements it should have harvested.
  ///
  /// THEREFORE: on overflow the oldest SACRIFICABLE group falls first.
  /// Only if there is none does the oldest overall fall — the old
  /// path, as a last resort. A harvest request that falls is
  /// asked again 32 s later; a placement that falls is gone.
  ///
  /// NOTHING CHANGES TOWARDS THE OUTSIDE: the number of outgoing cells
  /// and their rhythm are unchanged, only which
  /// ciphertext is discarded changes (invariant 1 speaks about the rhythm).
  /// Counts WHO queues control frames — per calling site.
  ///
  /// -- WHY THIS EXISTS (S381, 11.09.2026) ----------------------------
  ///
  /// B-2 from `BUGFIX_CURRENT.md` — "control queue chronically at the
  /// limit, harvest is suspended" — had stood since 07.09. with the
  /// open question WHO fills it: "is **not measured**".
  ///
  /// Re-measured in a controlled way on 11.09.2026, the same empty node without
  /// a single contact, same running time, only the number of
  /// identities different:
  ///
  ///     1 identity:     control queue  2-5 / 22,   0 pauses
  ///     2 identities:   control queue 58-67 / 67, 12 pauses
  ///
  /// And the harvest is the VICTIM here, not the cause: in the same
  /// ten minutes it queued FIVE requests while the queue
  /// rose to 94. Around nine of ten queueings had no
  /// log line at all — the question could not be answered from the
  /// logs.
  ///
  /// What is counted is the CALLER, read from the stack. That costs one
  /// `StackTrace.current` per queueing; at the measured ~90 frames in
  /// ten minutes that is nothing, and not a byte goes to the wire.
  final Map<String, int> _controlReasons = {};

  /// Who has queued how many control frames since the node has been running.
  Map<String, int> get controlReasons => Map.unmodifiable(_controlReasons);

  /// The caller's line, shortened to `datei:zeile`.
  static String _caller() {
    final lines = StackTrace.current.toString().split('\n');
    // 0 = _caller, 1 = _pushControl, 2 = enqueueControl*, 3 = the caller
    for (var i = 3; i < lines.length && i < 8; i++) {
      final m = RegExp(r'\(([^)]*\.dart):(\d+)').firstMatch(lines[i]);
      if (m == null) continue;
      final file = m.group(1)!.split('/').last;
      if (file == 'cover_stream.dart') continue;
      return '$file:${m.group(2)}';
    }
    return 'unbekannt';
  }

  void _pushControl(List<({int type, Uint8List body})> frames,
      {bool sacrificable = false, bool forwarded = false}) {
    if (frames.isEmpty) return;
    final who = _caller();
    _controlReasons[who] = (_controlReasons[who] ?? 0) + frames.length;
    final g = _nextControlGroup++;
    for (final f in frames) {
      _control.add((
        type: f.type,
        body: f.body,
        group: g,
        sacrificable: sacrificable,
        forwarded: forwarded
      ));
    }
    while (_control.length > maxControlBacklog &&
        _control.first.group != _control.last.group) {
      // THE YOUNGEST GROUP IS PROTECTED — BUT ONLY IF IT IS NOT
      // SACRIFICABLE. The protection exists so that a payload that is by
      // itself already larger than the cap does not throw itself
      // away (see above). For a just-queued query that does not
      // fit: it is ONE frame, and dropping it immediately
      // is exactly the right answer to a full queue — otherwise
      // a placement would have to give way in its place, and that is the
      // error this place fixes.
      final newest = _control.last.group;
      final newestSacrificable = _control.last.sacrificable;
      int? victim;
      for (final e in _control) {
        if (e.sacrificable && (newestSacrificable || e.group != newest)) {
          victim = e.group;
          break;
        }
      }
      victim ??= _control.first.group;
      _control.removeWhere((e) {
        if (e.group != victim) return false;
        _droppedControl++;
        // -- A DISCARDED FRAME IS REPORTED (S381, 11.09.2026) --
        //
        // Until here the loss was a NUMBER. `droppedControl` counted
        // it, nobody read the counter, and the sender considered its
        // message placed.
        //
        // Measured on 11.09.2026 on Node1 during `gui-01a 1a.03`: a
        // contact request (3317 B) falls apart into FIVE pieces, each
        // costs `m x R` frames — together 156 against a cap of 120.
        // `verworfen 168`. What falls, when there is no sacrificable
        // group, is the OLDEST, i.e. the placements of the message that
        // is just being placed; at Alice, Bob's answer arrived as
        // `empfangen 2, zusammengesetzt 0`.
        //
        // This place knows only bytes. WHICH message is affected is
        // known to the node (`_ownDeposits`), and that is where the
        // callback goes. Reporting does not belong in the queue.
        onControlDropped?.call(e.body);
        return true;
      });
    }
    if (_control.length > _maxControlDepth) {
      _maxControlDepth = _control.length;
    }
  }

  /// Is called for EVERY discarded control frame, with its
  /// body. See the reasoning at the discard site.
  ///
  /// `null` means "nobody is listening" — then it stays with the counter, as
  /// before. That is the state for probes that have no node.
  void Function(Uint8List body)? onControlDropped;

  /// How many control frames are pending.
  int get pendingControl => _control.length;


  /// How many control frames were discarded because the queue was full.
  ///
  /// A number > 0 means: the node queues more than one cell per
  /// time slice can carry out. That is a finding on the INFLOW
  /// (`kHarvestRequestsPerRun`, `harvestEverySlots`), not on this
  /// queue — it only prevents it from turning into a memory leak.
  int get droppedControl => _droppedControl;

  /// The largest queue depth ever reached — for the status line.
  int get maxControlDepth => _maxControlDepth;

  /// Takes the next pending control frame, if there is one.
  ///
  /// The caller decides what happens with it — this file does not know
  /// the frame content.
  ///
  /// `forwarded` passes the classification out along with it, so that the
  /// send site can book it when going out (see [_control]).
  ({int type, Uint8List body, bool forwarded})? takeControl() {
    if (_control.isEmpty) return null;
    final e = _control.removeAt(0);
    return (type: e.type, body: e.body, forwarded: e.forwarded);
  }

  void enqueue(Outgoing item) {
    final map = item.ephemeral ? _ephemeral : _real;
    map.putIfAbsent(item.recipient, () => <Uint8List>[]).add(item.payload);
    if (!item.ephemeral && !_order.contains(item.recipient)) {
      _order.add(item.recipient);
    }
  }

  /// Occupies the due slot.
  ///
  /// A cell ALWAYS comes out. If nothing is pending, it is a
  /// dummy cell — not because that would be pretty, but because a
  /// skipped slot carries the same information as an additional one.
  /// The padding. From the OWN random stream, not from that of the
  /// slot plan — a shared stream would have made the plan sequence depend on the
  /// fill amount and thus lost invariant 1.
  Uint8List _fill(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _padRng.nextInt(256)));

  SlotOutput takeSlot({int partner = 0, bool idle = false}) {
    // ── THE IDLE SLOT (S376, finding 2) ───────────────────────────────
    //
    // A slot that would go into the void anyway TAKES NOTHING. The
    // caller (`DeliveryNode.tick`) sets this exactly when it has
    // no partner: then there is nobody to whom the cell could
    // go, and everything taken out here would be lost without a
    // wire.
    //
    // Until S375 this branch did not exist. `takeSlot` ALWAYS took the
    // payload — even without a partner —, and the caller threw the
    // result away afterwards. In addition, the loop further below emptied
    // all ephemeral queues on EVERY call; a partnerless
    // node thus discarded every transient payload that arrived,
    // silently and without a counter.
    //
    // WHAT THE BRANCH DOES NOT TOUCH: the slot plan. `drawInterval` and
    // `drawPartner` hang on `_rng` and have already run here; the
    // padding hangs on `_padRng`. The SEQUENCE of slots thus stays
    // independent of whether this node currently has partners —
    // invariant 1 (§5.1) applies unchanged, and an observer sees
    // nothing anyway, because without a partner no cell goes out.
    if (idle) {
      final buf = _fill(aggregationBudget);
      return SlotOutput(
          cellBuilder == null ? buf : cellBuilder!(null, buf, partner),
          null,
          0,
          partner,
          suppressed: CoverSaver.instance.lanShapingActive);
    }
    // COLLECTION IS IN ENTRIES, not in bytes. Until IP-1 a
    // byte counter ran here against a fixed budget; thus the cell was full
    // as soon as the RAW messages filled it. Since `Aggregate` compresses
    // before sealing (§4.3), the PACKED size decides —
    // and that is only known once one has tried.
    final entries = <Uint8List>[];
    // ONLY the real (not ephemeral) entries, kept separately — for
    // a re-offer on failed sending (D-3, S372, see
    // `SlotOutput.rawPayloads`). Ephemeral entries must NOT
    // get in there, their loss is deliberately irrelevant.
    final realEntries = <Uint8List>[];
    var packed = 0;
    String? recipient;

    while (_order.isNotEmpty) {
      final r = _order.first;
      final q = _real[r];
      if (q == null || q.isEmpty) {
        _order.removeAt(0);
        _real.remove(r);
        continue;
      }
      recipient = r;
      while (q.isNotEmpty) {
        final candidate = [...entries, q.first];
        if (Aggregate.pack(candidate, aggregationBudget) == null) break;
        final taken = q.removeAt(0);
        entries.add(taken);
        realEntries.add(taken);
        packed++;
      }
      if (q.isEmpty) {
        _order.removeAt(0);
        _real.remove(r);
      }
      break;
    }

    final target = recipient;
    if (target != null) {
      final eq = _ephemeral[target];
      if (eq != null) {
        while (eq.isNotEmpty) {
          final candidate = [...entries, eq.first];
          if (Aggregate.pack(candidate, aggregationBudget) == null) break;
          entries.add(eq.removeAt(0));
          packed++;
        }
      }
    }
    for (final eq in _ephemeral.values) {
      _droppedEphemeral += eq.length;
      eq.clear();
    }

    final buf = recipient == null
        ? _fill(aggregationBudget)
        : (Aggregate.pack(entries, aggregationBudget, filler: _fill) ??
            _fill(aggregationBudget));

    final frame =
        cellBuilder == null ? buf : cellBuilder!(recipient, buf, partner);
    // ── THE CONSENTED SWITCH-OFF, ONLY MARKED HERE ───────────────────
    //
    // IT IS ASKED ONLY NOW, after the build — not at the start of the
    // method. Whoever exited earlier here would jump past `Aggregate.pack`
    // and leave payload lying in the queue although the
    // slot is used up; the message would then be delayed by one slot
    // without anyone seeing it.
    //
    // ONLY THE EMPTY CELL. `recipient != null` means that real
    // payload rides along — it goes out, otherwise the switch-off would
    // not be a cover switch-off, but a delivery failure.
    // Control frames do not come past here at all: they take their slot
    // one level higher (`DeliveryNode.tick`, `ctrl != null`).
    //
    // NOT SENDING HAPPENS ELSEWHERE. This mark decides nothing, it
    // only informs; it takes effect in `DeliveryNode.tick`. The
    // reason is the layering: this file knows no partner and
    // no wire, and it is to stay checkable without both.
    final suppressed =
        recipient == null && CoverSaver.instance.lanShapingActive;
    return SlotOutput(frame, recipient, packed, partner,
        suppressed: suppressed,
        rawPayloads:
            recipient == null || realEntries.isEmpty ? null : realEntries);
  }

  int get pendingReal =>
      _real.values.fold<int>(0, (a, q) => a + q.length);

  /// Puts back real payloads that `takeSlot()` had already taken out for [recipient]
  /// (`SlotOutput.rawPayloads`), but whose send attempt
  /// failed (D-3, S372).
  ///
  /// At the FRONT of the queue of [recipient], in the original
  /// order — [items] already carries them that way, `takeSlot()` appends them
  /// in removal order. [recipient] moves to the START of
  /// `_order`, even if it was already there (further back): the payload
  /// was already due, a re-delivery should not fall back behind younger
  /// recipients — the same priority reasoning as for
  /// [requeueControl].
  void requeueReal(String recipient, List<Uint8List> items) {
    if (items.isEmpty) return;
    final q = _real.putIfAbsent(recipient, () => <Uint8List>[]);
    q.insertAll(0, items);
    _order.remove(recipient);
    _order.insert(0, recipient);
  }
}
