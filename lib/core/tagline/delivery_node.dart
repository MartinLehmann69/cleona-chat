// The node that operates the delivery layer.
//
// It holds three things together: the cover stream (when and where does
// something go out), the bridges to the partners (how), and the assignment
// of what comes in (what do I do with it).
//
// NO TIMER HERE. `tick()` processes ONE slot; when it is due is
// decided by the caller. A `Timer` in the module would not be
// controllable in the test, and the slot times come from the plan of the
// cover stream anyway, not from the wall clock.
//
// A PROPERTY THAT BELONGS SAID OPENLY HERE.
//
// A relay forwards IMMEDIATELY, not on its cadence (§7 — that is
// the source of the sub-second latency). The cover stream thus protects
// the OWN messages of a node, not its forwardings. Whoever
// observes a node sees it forward — and the times of
// its forwardings lie between the sender's slot and the
// arrival at the recipient. That is the same two-egress class that §7.3
// already explains for Speed, one hop further in. It is no new
// weakness, but it is not covered by the cover either, and therefore
// it stands here and not in a footnote.
library;

import 'dart:typed_data';

import 'package:cleona/core/bulk/bulk_cache.dart' show BulkCache;
import 'package:cleona/core/bulk/bulk_frames.dart';
import 'package:cleona/core/sync/cover_stream.dart';

import '../link/frame.dart';
import 'cell_transport.dart';
import 'package:cleona/core/sync/entry_record.dart';
import 'lookup_onion.dart';
import 'pending_requests.dart';
import 'reassembly.dart';
import 'relay.dart' show RelayReject;
import 'secure_frames.dart';
import 'secure_mode.dart';
import 'speed_egress.dart';

/// Finds the partner index for a hop identifier. `null` if this
/// node does not know the successor — then the cell stays.
typedef PartnerFor = int? Function(Uint8List hopId);

/// The first four bytes of a tag, for the log.
///
/// WHY IT IS IN PLAINTEXT. Placement and harvest compute the same tag from
/// `K_AB`, epoch, family and direction — if the two calculations
/// diverge, one sees in the log only "placed" on one side and
/// "geerntet: 0" on the other, and both lines taken by themselves
/// are unremarkable. Exactly that cost three hours in the field finding of 29.08.
/// A prefix makes the two lines COMPARABLE
/// without revealing the tag: four bytes are too few to compute the
/// tagline from them, and the target `H(T ‖ e)` is already in the
/// log (`_posLabel`), derived from the same quantity.
String tagLabel(Uint8List t) =>
    t.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// What a tick or a receipt has brought about.
/// Every how many slots the expiry of the bulk quota runs.
///
/// 450 x `kSlotInterval` (8 s) = 3600 s = one hour. Computed against the
/// two deadlines it enforces: `TTL_media` = 7 d and the
/// follow-up time after the DECODED receipt = 24 h (`bulk_params.dart`).
/// One hour of resolution on a 24 h deadline is 4 % inaccuracy at the
/// end — and the price of the alternative is a pass over up to
/// 256 000 blocks every 8 s.
const int kBulkExpiryEverySlots = 450;

/// How many unsolicited cover-fill blocks (§5.5) a partner may place per
/// slot time slice.
///
/// ── COMPUTED, NOT SET ────────────────────────────────────────────────
///
/// **The honest rate is 1.** A partner puts a block into a
/// DUE cover slot (§5.5 rule 1: "never a slot of its own"), and a
/// slot falls every `kSlotInterval` = 8 s. More than one block per
/// time slice an honest node cannot send at all without breaking the
/// rule from which the whole cover fill derives its
/// freedom from cost.
///
/// **Why 3 nevertheless and not 1.** The time slice here is aligned to the
/// wall clock of the RECIPIENT, the slot to the clock of the SENDER;
/// the two do not run synchronously. Two honest blocks can therefore fall into
/// the same slice if one lies at the edge. Plus a margin
/// for catch-up after a connection disturbance. At 1 an
/// honest partner would regularly have lost a block — and because there is
/// no back channel (rule 4), nobody would have noticed.
///
/// **What it cuts, measured.** Without a limit a rejected
/// block costs 24.89 us (`test/perf/probe_acceptance_point_last_s368.dart`, six
/// registered objects, i.e. the most expensive case). At 1 Gbit/s
/// continuous bombardment with 1200 B cells that is about 104 000 cells/s and
/// **259 % of a core**. With the cap 3 blocks per 8 s and
/// partner remain, i.e. 0.375/s — at P = 4 sync partners 1.5/s and thus
/// 37 us/s, a hundred-thousandth of a core. The rest falls at an
/// integer comparison.
///
/// **Memory was never the problem** and is not even without this
/// cap: the same probe measures 0 B taken in after 22 000
/// unsolicited blocks. The four caps in `cover_fill_blocks.dart`
/// hold. This one caps the COMPUTE TIME that they do not cover.
const int kCoverFillMaxPerPartnerPerSlot = 3;

final class NodeAction {
  /// WHAT happened — the statement itself, and only it.
  ///
  /// ── WHY THE DIAGNOSIS DOES NOT BELONG IN HERE (S353) ───────────────
  ///
  /// The tag prefixes first stood in this field, appended to the
  /// text. Three assertions in two smoke tests turned red because of it
  /// (`smoke_v41_lab`, `smoke_blind_storage`) — they compare `what`
  /// exactly, and rightly so: "exactly three families found" is a
  /// statement about a NUMBER, not about a log line. Whoever then
  /// loosens the tests to `contains` has watered down the check
  /// so that a presentation change gets through — the wrong direction.
  ///
  /// So the other way round: `what` stays the datum, [detail] carries the
  /// diagnosis, and `toString` puts both together. The field log sees
  /// the tags unchanged, the tests see the statement unchanged.
  final String what;

  final int? partner;

  /// Addition for the log — tag prefixes, numbers, state snippets.
  /// NEVER becomes part of [what], so that no assertion hangs on it.
  final String? detail;

  NodeAction(this.what, {this.partner, this.detail});

  @override
  String toString() {
    final header = detail == null ? what : '$what $detail';
    return partner == null ? header : '$header -> Partner $partner';
  }
}

final class DeliveryNode {
  final SpeedEgress egress;

  /// One bridge to the link layer per partner, same order as
  /// `egress.partnerLinkKeys`.
  final List<CellTransport> partners;

  final PartnerFor partnerFor;

  /// The current epoch — passed in, this file reads no clock.
  final int Function() epochNow;

  /// Is called for every announced node position. `true` if it
  /// was new. What happens with it — routing table, suitability register —
  /// is decided by the node, not by this file.
  final bool Function(Uint8List position)? onPeerLearned;

  /// What this node holds as a responsible relay (Secure mode).
  ///
  /// The total byte cap comes from outside ([DeliveryNode.new] `maxStoreBytes`)
  /// — this file does not know `Platform.*` and is not supposed to
  /// (layer boundary, see header of this file); the platform derivation
  /// sits at `startV41Node` (§21.3.3, option C).
  final SecureStore store;

  /// What this node holds as the LOCAL MINIMUM without being able to
  /// open it (§11.2). Separate from the tag store because it is ordered by target tags
  /// and answers no harvest — reasoning in
  /// `secure_mode.dart`.
  final BlindStore blind = BlindStore();

  /// The bulk quota of this node (§9.3, §21.2, §21.3.3 no. 3).
  ///
  /// ── THE FOURTH STORAGE CLASS, AND WHY IT IS NOT [store] ───────────
  ///
  /// §21.2 literally: "Bulk blocks are uniform cells on the wire (entry
  /// type 0x05) but they are **not** delivery-layer cells: they live in
  /// their own budget class (E-53), are evicted first under pressure, and
  /// their placement is addressed per holder (§9.3), not replicated
  /// `m × R`."
  ///
  /// Measured why [store] cannot do it: `SecureStore.maxCellsPerTag`
  /// is 32, and the SMALLEST permissible bulk transfer
  /// (`kFountainWorthwhileBytes` = 32 KiB) is 47 blocks under ONE
  /// line. 15 would be displaced immediately — and with a 5 MB photo
  /// (6348 blocks) it would be 99.5 %.
  ///
  /// **On mobile it is switched off, not small** (E-53). The derivation
  /// from the budget class happens at `startV41Node`, where `Platform.*`
  /// is known; only the finished quota arrives here. Without a value
  /// a desktop quota — the same default as for `maxStoreBytes`.
  final BulkCache bulk;

  /// Where a sampled block is reported whose request came from
  /// this node itself.
  ///
  /// Separate from `onHarvested` for the same reason for which
  /// `_marksRequest` is separate from `_requestPeer`: a bulk answer
  /// is not a piece of a cell transfer. If it ran there, it would occupy
  /// a place in the reassembler and wait for continuations that
  /// never come (the same error as with the liveness answer before S354).
  void Function(Uint8List requestId, Uint8List line, Uint8List sealed)?
      onBulkScanned;

  /// Where the end of an own sampling round is reported.
  ///
  /// SEPARATE from [onBulkScanned] because it says something different: not
  /// "here is a block", but "this holder is done with this request,
  /// and with this many". On this signal — and NOT on
  /// the block arrival — hangs the requester's re-offer.
  void Function(Uint8List requestId, Uint8List line, int count)?
      onBulkScanEnd;

  /// Where a block for a cover slot that is due anyway comes from (§5.5).
  ///
  /// **`null` means: random as before.** The callback is asked ONLY
  /// when the slot is a dummy — it can thus neither create a slot
  /// nor take one away from a payload or a control frame
  /// (rule 1). It is not told the partner (rule 2).
  /// It has no way back (rule 4).
  ///
  /// A callback and not an object, because this layer is not supposed to know the
  /// binary distribution: `tagline/` knows nothing of
  /// `update/`, and this direction must not be reversed.
  Uint8List? Function()? coverFill;

  /// Where an UNSOLICITED block is reported (§5.5).
  ///
  /// The callback returns nothing, and that is the construction of rule 4
  /// ("no back channel"): there is no answer this node could send,
  /// so there is also no return value from which one could
  /// arise.
  void Function(Uint8List sealed)? onCoverFillBlock;

  /// How many blocks this node has put into its own cover slots.
  int coverFillSent = 0;

  /// How many cover cells did NOT go out because of the consented LAN switch-off
  /// (S373, §5.1 exception).
  ///
  /// COUNTED AND NOT CONCEALED (E-83). This number is the only
  /// place where one can read how much cover a node has actually
  /// given up — `lanShapingActive` only says whether the switch-off
  /// APPLIES, not whether it has taken effect. A node where it applies and the
  /// number is at 0 has a wiring error and not a quiet
  /// day.
  int coverSuppressed = 0;

  /// How many unsolicited blocks arrived at it.
  int coverFillReceived = 0;

  /// How many unsolicited blocks were rejected at the rate limit
  /// ([kCoverFillMaxPerPartnerPerSlot]).
  int coverFillRateDropped = 0;

  /// Time slice and counter per partner for the rate limit.
  final Map<int, (int, int)> _coverFillRate = <int, (int, int)>{};

  /// How many blocks this node has taken in as a HOLDER.
  int bulkPlacementsHeld = 0;

  /// How many blocks it has handed out on sampling requests.
  int bulkBlocksServed = 0;

  /// How many bulk frames it has passed on.
  int bulkForwarded = 0;

  /// How many partners were there at the last look. No timer, no
  /// callback: the re-offer hangs on exactly ONE event, and that
  /// is a new session (`V41Node.adopt` appends to both lists).
  int _partnerCountSeen = -1;

  /// Control frames whose processing threw. A number > 0 is a
  /// finding, not operational noise.
  int controlFailures = 0;

  /// How many placement receipts this node has sent back along the
  /// remembered return path for FOREIGN placements.
  ///
  /// The number measures exactly what is new since S357. Before S357 it was
  /// structurally 0: the placement remembered no return path when passing on,
  /// so `takeRoute` never found anything, and every receipt ended
  /// at the predecessor hop — which then even read it as its OWN.
  ///
  /// It is the reliable measuring point for the return path, and
  /// regardless of whether the sender later happens to get the storing relay
  /// as a partner itself. Exactly this made a first
  /// version of the proof test fail: it counted at the SENDER the
  /// receipts of non-partners, and as soon as `dialFromEntries` made the
  /// target relay a partner after the fact, the same receipt was
  /// a session credit instead of a foreign proof. The return path had
  /// worked, the number nevertheless said 0.
  int returnedReceipts = 0;

  /// The last caught throw, together with its opcode. Without it a number > 0 is
  /// an alarm without an address — exactly the situation in which S357 searched
  /// for an hour.
  String lastControlFailure = '';

  DeliveryNode({
    required this.egress,
    required this.partners,
    required this.partnerFor,
    required this.epochNow,
    this.onPeerLearned,
    // `-1` = unlimited (desktop, unchanged behaviour). On mobile
    // `startV41Node` passes [kMobileSecureStoreCapBytes] through.
    int maxStoreBytes = -1,
    // The bulk quota (§9.3). Without a value a desktop quota;
    // on mobile devices `startV41Node` passes a switched-off one through
    // (E-53: "mobile nodes carry no bulk" — none, not little).
    BulkCache? bulkCache,
    // ── THE RETENTION DEADLINE COMES FROM THE DEFAULT (S363) ─────────
    //
    // `keepEpochs` is deliberately NOT set here: the ordinary
    // deadline is ONE quantity and stands in ONE place
    // (`kNormalKeepEpochs` = 14, §21.1 "14 d default"). A second
    // writer here would be the drift that S363 has just closed.
    //
    // Until S363 this default was `kHarvestEpochs` = 3 — the
    // subscription depth from §22.4.1 —, and because THIS is the only
    // construction of a `SecureStore` in `lib/`, in operation
    // EVERY ordinary cell rested three instead of fourteen days. The place
    // where the error took effect is exactly this line; it is healed
    // in the default, not here.
  })  : store = SecureStore(maxTotalBytes: maxStoreBytes),
        bulk = bulkCache ?? BulkCache() {
    if (partners.length != egress.partnerLinkKeys.length) {
      throw ArgumentError('exactly one bridge per partner');
    }
    // Both lists are mutable and grow together when a
    // session is added (V41Node.adopt).
  }

  /// Processes ONE slot: the plan draws time and partner, the cell
  /// goes out — real or dummy, that looks the same from outside.
  /// Counts the slots for the alternation between control and
  /// payload — see `tick`.
  int _slotCounter = 0;

  /// Counts the slots until the next expiry run of the bulk quota.
  int _bulkExpiryCounter = 0;

  SlotOutput tick() {
    // ── THE BLIND STORE HANGS ON THE CLOCK, NOT ON A CLOCK TIME ──────
    //
    // The tag store is swept by the node's harvest run
    // (`V41Node.harvestTick` calls `store.expire`). The blind store cannot
    // ride along there: a node that harvests nobody — a pure
    // relay without a Secure contact — never runs the harvest run and would
    // never forget its blind stock. Exactly this class of defect was
    // B-32/S350 ("`SecureStore.expire` had NO caller in lib/").
    // The slot clock, by contrast, runs in EVERY node, and it is already there —
    // no second rhythm arises (invariant 1).
    blind.expire(epochNow());

    // ── AND THE BULK QUOTA ON THE SAME CLOCK, ONLY LESS OFTEN ────────
    //
    // The same reasoning as one line above: no second
    // rhythm (invariant 1), so the expiry hangs on the slot that exists
    // anyway. But NOT in every slot, and that is computed:
    // `BulkCache.expire` runs over every line and every block, and
    // a 200 MB video is ~256 000 blocks. Running over a
    // quarter of a million entries every 8 s would be permanent load for nothing —
    // `TTL_media` is 7 days, the follow-up time after the receipt 24 h.
    // [kBulkExpiryEverySlots] = 450 is, at `kSlotInterval` = 8 s, exactly
    // one hour: fine enough for both deadlines, coarse enough not to
    // stand out. And the call is dropped entirely as long as the node
    // holds nothing.
    //
    // OWN COUNTER, NOT `_slotCounter`: that is only incremented
    // when a payload is waiting (`(_slotCounter++ & 1) == 0` stands behind
    // an `||` and otherwise does not run at all). Whoever read it here would have
    // an expiry that never applies on a quiet node — exactly the
    // class of defect that B-32 was.
    if (++_bulkExpiryCounter >= kBulkExpiryEverySlots) {
      _bulkExpiryCounter = 0;
      if (bulk.blockCount > 0) bulk.expire(nowUtc());
    }

    if (partners.length != _partnerCountSeen) {
      _partnerCountSeen = partners.length;
      redispatchBlind();
    }

    final p = egress.stream.drawPartner();

    // ── WITHOUT A PARTNER NOTHING IS TAKEN OUT (S376, finding 2) ──────
    //
    // HERE LAY A SILENT LOSS, and in two queues at once.
    // The order was: first `takeControl()`, then check whether there
    // is a partner at all. Both failed:
    //
    //   * The control frame had been taken out before `partners.isNotEmpty`
    //     was asked. If the list was empty, the frame fell through both
    //     branches and was gone — without putting back, without
    //     counter, without log. A Secure placement costs `m x R` = up to 60
    //     such frames (§9.2); they were all lost while the
    //     sender saw an accepted message.
    //   * `takeSlot()` further below took out the payload as well, and the
    //     line `if (partners.isEmpty) return slot;` threw it away. On top of that
    //     `takeSlot` emptied the ephemeral queues on every call.
    //
    // The order is reversed: first check, then take out. The
    // SLOT is used up nevertheless — `drawPartner` has run, the
    // driver draws its next interval as always, and `takeSlot`
    // finishes building the dummy cell. The clock must not depend on
    // whether someone is reachable right now, otherwise its start would reveal the
    // start of reachability; exactly that already stood here as
    // justification, only one removal too late.
    //
    // WHAT IS NOT REPAIRED BY THIS, and where it is: that a
    // Secure placement at 0 partners queues 60 frames in the first place.
    // The control queue holds [kMaxControlBacklog] = 120 frames and
    // discards the oldest WHOLE group on overflow — two
    // messages fill it. The latch against this sits at the
    // send site (`V41Node.send`, `SendRefusal.notReady` at 0
    // partners), so that the message stays in the local outbox
    // (§21.2) instead of in a queue that silently drops it.
    if (partners.isEmpty) {
      return egress.stream.takeSlot(partner: p, idle: true);
    }

    // Self-initiated control frames take THIS slot. They must
    // not go out immediately past `emitControl` — that would be a
    // spike (invariant 1).
    //
    // ── BUT NO LONGER UNCONDITIONALLY (30.08.) ────────────────────────
    //
    // The priority was absolute: `takeControl()` was asked first in EVERY slot,
    // so a waiting payload only got its turn when the
    // control queue stood at EXACTLY ZERO. It practically never stands at
    // zero — the harvest queues three requests every 32 s, the outflow is
    // one cell per 8 s, plus liveness and receipts.
    //
    // Consequence, measured in the field: EVERY Speed message starved, while
    // every Secure placement delivered — it travels itself as a control frame.
    //
    //   A->B  speed  (2 legs)   16:30:36 -> never arrived
    //   A->B  secure (6 legs)   16:34:25 -> 16:35:03   (38 s)
    //   B->A  speed  (2 legs)   16:30:46 -> never arrived
    //   B->A  secure (6 legs)   16:34:34 -> 16:37:03   (2 min 29 s)
    //
    // and at the time of measurement on BOTH nodes simultaneously
    // `Nutzlast wartet 1` at `Kontrollschlange 7/49` and `8/29` — the
    // message lay in the sender and got no slot.
    //
    // ALTERNATED, NOT REVERSED. Whoever simply swaps the priority
    // starves the harvest, and then nobody finds anything anymore. As long as
    // a payload is waiting, both share the slots half and half; if
    // none is waiting, the control queue gets every slot as before.
    //
    // INVARIANT 1 STAYS: exactly ONE cell per slot still goes out,
    // the clock does not change, and which kind it carries is in the
    // ciphertext. The same argument already carries `enqueueControlFirst`.
    //
    // THE PRICE is stated openly: while a payload is waiting, the
    // throughput of the control queue halves — harvest and placements then take
    // twice as long. That is a redistribution, not an improvement at
    // both ends.
    final payloadWaits = egress.stream.pendingReal > 0;
    final controlOnIt = !payloadWaits || (_slotCounter++ & 1) == 0;
    final ctrl = controlOnIt ? egress.stream.takeControl() : null;
    // `partners.isNotEmpty` no longer stands here: the case is caught
    // a hand's breadth further up, BEFORE anything was taken out (S376).
    if (ctrl != null) {
      try {
        partners[p % partners.length].emitFrame(ctrl.type, ctrl.body);
      } catch (e) {
        // D-3 (S372): `takeControl()` has already taken the frame out —
        // without putting it back it would be lost with the throw, although the
        // slot stays used up anyway (invariant 1). `forwarded`
        // is passed through, otherwise a later successful
        // forwarding would wrongly count as own traffic.
        egress.stream.requeueControl(ctrl.type, ctrl.body,
            forwarded: ctrl.forwarded);
        onSendFailed?.call(null, e);
        return SlotOutput(ctrl.body, null, 0, p);
      }
      if (ctrl.forwarded) onRelay?.call(ctrl.body.length);
      // MIXED SEND SITE — the only one in this file, and therefore
      // the booking one line higher hangs on a CONDITION instead of on
      // a mark.
      //
      // The control queue carries almost only own traffic: placements, harvest,
      // liveness, entry requests, peer announcement — all initiated by this
      // node (`v41_node.dart`, eleven queueing sites). Exactly
      // ONE place queues foreign traffic: `redispatchBlind` below forwards a
      // blindly kept FOREIGN placement. That is forwarding, and
      // until S363 it ran along unobserved because no distinction was made
      // here.
      //
      // Booking happens HERE and not on queueing, because the queue discards on
      // overflow (`CoverStream._pushControl`): a booking at
      // queueing would count bytes that never saw the wire.
      return SlotOutput(ctrl.body, null, 1, p);
    }

    final slot = egress.stream.takeSlot(partner: p);
    // ── THE CONSENTED LAN SWITCH-OFF (S373) ─────────────────────────
    //
    // The one place where it takes effect. Everything before — slot draw,
    // partner draw, aggregation, cell build — has run unchanged;
    // here only the GOING OUT of a cell that carries nothing is
    // dropped. Which invariant that costs and which it does not cost
    // is stated completely at `SlotOutput.suppressed`.
    //
    // ── HERE AND NOT LATER ──────────────────────────────────────────
    //
    // The cover fill (§5.5) stands three lines further down, and its
    // rule 1 reads "never a slot of its own": a fountain block may
    // ride along BECAUSE the cell goes out anyway. If it is
    // suppressed, that no longer applies — a block that still
    // rode along would create the cell that no longer exists, and
    // would be a spike in the otherwise quiet stream. Exactly the spike
    // that would make a binary distribution readable from outside.
    //
    // ── HERE AND NOT EARLIER ────────────────────────────────────────
    //
    // Control frames (above, `ctrl != null`) are real traffic —
    // placements, harvest, liveness — and must go out. They return
    // already before this line. Suppressed is exclusively
    // the EMPTY cell.
    if (slot.suppressed) {
      coverSuppressed++;
      return slot;
    }
    // ── COVER FILL (§5.5): THE SLOT WAS DUE ANYWAY ───────────────────
    //
    // Rule 1 ("never a slot of its own") arises here STRUCTURALLY and
    // is not assured after the fact: the question is asked only after
    //
    //   * the control queue had its slot (above, `ctrl != null`
    //     returns) and
    //   * `takeSlot` has decided whether a payload rides along
    //     (`slot.isDummy` is true exactly when none was pending).
    //
    // Rule 2 ("the schedule draws the partner") likewise: `p` has been fixed since
    // `drawPartner()`, long before the fill is asked, and
    // it is not even told it.
    //
    // THE Z-9 PROBE THUS FALLS TO ZERO EFFORT: slot sequence and
    // partner sequence are computed before this line and depend on
    // no quantity that the fill influences. `smoke_update_cover_fill`
    // measures exactly that — the same sequence with a full and an empty
    // block queue.
    //
    // NOTHING CHANGES ON THE WIRE: `emitFrame` builds the same
    // `buildInner` cell plaintext of exactly `kCellPlaintextSize` bytes as
    // `emit`, only with frame type `0x05` instead of `0x01` — and that is INSIDE,
    // under the link seal.
    if (slot.isDummy) {
      final block = coverFill?.call();
      if (block != null) {
        try {
          partners[p % partners.length]
              .emitFrame(LinkFrameType.fountain, buildBulkPublicBlock(block));
        } catch (e) {
          onSendFailed?.call(null, e);
          // NO FORWARDING — cover fill, no foreign frame. And
          // NO payload loss to put back: the block comes from
          // the own `BulkCache` supply, not from a queue
          // that `coverFill?.call()` would have emptied.
          return slot;
        }
        // NO FORWARDING — the same reason as one line further down: this
        // is the own cover slot of this node. And NO
        // `onRelay` booking, because no foreign frame passes through.
        coverFillSent++;
        return slot;
      }
    }
    // D-3 (S372): `takeSlot()` has already taken out the payload above — without
    // putting it back on a send failure it would be lost with the throw,
    // although the slot stays used up anyway (invariant 1,
    // §5.1: the slot plan draws the partner, not the sender; the clock
    // must not shift, otherwise the egress becomes distinguishable).
    try {
      partners[p % partners.length].emit(slot.frame);
    } catch (e) {
      if (slot.recipient != null && slot.rawPayloads != null) {
        egress.stream.requeueReal(slot.recipient!, slot.rawPayloads!);
      }
      onSendFailed?.call(slot.recipient, e);
      // NO FORWARDING, no recipient outward: nothing arrived.
      return SlotOutput(slot.frame, null, 0, slot.partner);
    }
    // NO FORWARDING — this is the own cover slot of this node,
    // not the cell of another. The mark is no decoration:
    // `smoke_network_stats` demands that EVERY send site of the
    // delivery layer either entails `onRelay?.call(...)` or is
    // marked like this. Without the mark a newly added
    // send site silently drops out of the booking — exactly the class of
    // error because of which the relay tiles stood at 0 for months.
    return slot;
  }

  /// Checks the blind stock: if meanwhile a partner is known that is closer to a
  /// target tag than this node itself, the placement moves
  /// on — otherwise it stays (§11.2, path a). Triggered by a
  /// changed partner count in [tick], never by an own clock.
  ///
  /// THE SAME DISTANCE CALCULATION AS WHEN PLACING. [nextHopToward] is, at
  /// `V41Node`, `_nextHopToward`, and that computes via `closerPartner`
  /// the same `compareDistance(target, keys.lNode, candidate.lNode)` that
  /// `placeSecure` also uses for the initial placement — the same metric on
  /// both sides, otherwise a moving placement would never find its target.
  ///
  /// GOES VIA THE CONTROL QUEUE, NOT IMMEDIATELY ONTO THE WIRE.
  /// `_handleControl` passes an INCOMING placement on immediately — that is
  /// answer traffic to a cell that has just arrived (§7). Here there is
  /// no triggering cell: the trigger is a partner change, and that
  /// is visible from outside. If sending happened here immediately, a
  /// spike would arise exactly at the time of the new session — size and
  /// timing of the blind stock would be readable. `enqueueControl` instead queues
  /// into the same channel that `tick()` empties PER SLOT anyway
  /// (one frame, not all at once) — no second rhythm
  /// (invariant 1). Which partner then carries the cell is decided by
  /// the same random draw as for every self-initiated placement
  /// (`placeSecure` runs the same way) — the further path choice
  /// is made anyway by the partner that accepts it, from its own
  /// position.
  void redispatchBlind() {
    for (final held in blind.holdings) {
      if (nextHopToward?.call(held.target) == null) {
        continue; // still the local minimum — leave it lying
      }
      final further = decrementHops(held.frame);
      blind.release(held);
      if (further != null) {
        // FORWARDING, and the only one that goes through the control queue:
        // the frame belongs to someone else. The booking sits at the
        // send site in `tick()`, not here — this queue discards on
        // overflow, and what is discarded has never been forwarded.
        egress.stream.enqueueControl(further, forwarded: true);
      }
      // `further == null` would mean: the hops were already used up.
      // Cannot happen for a held placement (`hold` demands
      // `c.hops > 0` before acceptance, and the frame does not change during
      // the holding time) — the branch stays nevertheless, because
      // `decrementHops` is a public function and nobody here is supposed to
      // guarantee that it stays that way.
    }
  }

  /// Placement and harvest — the role as responsible relay.
  ///
  /// The node does NOT check whether it is really responsible for this tag.
  /// It could: responsibility can be computed from the tag
  /// (§9.1). It deliberately does not, because a refusal "not mine"
  /// would reveal to the placer where the border of its neighbourhood lies —
  /// information about the own position that nobody needs. The
  /// quota (`SecureStore.maxCellsPerTag`) limits abuse instead of
  /// a responsibility check.
  /// Delivers the entry record for a position if the node
  /// knows it. Deliberately a callback: the delivery layer holds no supply,
  /// it asks whoever holds it.
  EntryRecord? Function(Uint8List position)? entryProvider;

  /// Reports a learned record upward. `true` if it was new.
  bool Function(EntryRecord record, int fromPartner)? onEntryLearned;

  /// An `entryResponse` has arrived — whatever its content.
  ///
  /// Separate from [onEntryLearned] because these are two different
  /// questions: "have I learned something" and "has the partner answered".
  /// The node hangs its set lock on the second (S376, P4-3).
  void Function()? onEntryResponse;

  /// The own position — to recognise whether a placement ends here.
  Uint8List? ownPosition;

  /// The own static X25519 part — to open a placement addressed to us.
  Uint8List? ownX25519Secret;

  /// Delivers the partner that is closer to [target] than this node, or
  /// `null` if there is none.
  int? Function(Uint8List target)? nextHopToward;

  bool _amTarget(Uint8List target) {
    final mine = ownPosition;
    if (mine == null) return true; // without an own position everything ends here
    if (mine.length != target.length) return false;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != target[i]) return false;
    }
    return true;
  }

  /// Return paths for requests and placements that ran through this node.
  ///
  /// ── THE DEADLINE IS IN [PendingRequests], AND IT IS BASED ON THE RTT ──
  ///
  /// A first version of S357 set 32 minutes here with the
  /// reasoning "backlog on both sides" (`kMaxControlBacklog` x
  /// `kSlotInterval`). The cross-reading overturned that, and it was
  /// right: the backlog is in the egress queue of the SENDER.
  /// Its book is `V41Node._ownDeposits`, and the long deadline is
  /// there too. An entry HERE only arises when passing on —
  /// afterwards —, and passing on happens with `emitControl`, which sends
  /// immediately. The long deadline would have rescued no honest return path
  /// and only left the foreign state lying 16 times as long.
  ///
  /// Since the same cross-reading the cap is **per partner** and not
  /// only global: incoming frames are not throttled, and harvest as well as
  /// search tie their PASSING ON to a free place — a single
  /// neighbour could otherwise have switched off the node as a relay for
  /// all others.
  final PendingRequests pending = PendingRequests();

  /// What this node holds as the BLIND RELAY of a lookup onion (E-L).
  ///
  /// Only the blind relay knows both identifiers of an operation; every
  /// other hop knows exactly one. Reasoning in the module header of
  /// `lookup_onion.dart`.
  final LookupOnionAliases onionAliases = LookupOnionAliases();

  /// How often this node has passed on a search as a blind relay.
  int blindRelayHandovers = 0;

  /// How often a search answer was relabelled in the process.
  int blindRelayAnswer = 0;

  /// The current time — passed in so that deadlines are checkable.
  DateTime Function() nowUtc = () => DateTime.now().toUtc();

  /// The node positions this node knows close to a search point
  /// — the answer side of the lookup (§9.1, S356).
  ///
  /// Deliberately a callback, for the same reason as [entryProvider]: the
  /// delivery layer holds no routing table, it asks whoever
  /// holds it. The node delivers at most [kMaxFindNodePositions].
  ///
  /// NO RESPONSIBILITY CHECK, and that is the same reasoning as
  /// for placement a few lines further up: whoever refused a request with
  /// "not my area" would reveal where its
  /// neighbourhood ends. What one knows is answered.
  List<Uint8List> Function(Uint8List searchPoint)? nearestKnown;

  /// Positions that came back on an OWN search request.
  ///
  /// The identifier comes along because `iterativeLookup` runs several requests
  /// at the same time (alpha = 3) and the answers could otherwise not
  /// be assigned to their round.
  void Function(Uint8List requestId, List<Uint8List> positions)? onNodesFound;

  /// A cell that came back on an OWN harvest request.
  ///
  /// The request identifier comes along: only through it can the cell
  /// be assigned to the counterpart that was asked — and without this
  /// assignment the harvest of all contacts would run through one shared
  /// buffer (B-22).
  void Function(Uint8List requestId, Uint8List cell)? onHarvested;

  /// A cell that was addressed to THIS node.
  ///
  /// WHY THIS MUST EXIST. Until S349 the receive path ended here: a
  /// cell that resolved neither as r1 nor as r2 was
  /// counted as `CellRole.mine` and dropped (`_uninteresting`).
  /// But exactly there lies EVERY message delivered to this node —
  /// r2 has stripped its layer, what remains is the message area, and
  /// that naturally no longer resolves a relay role at B. The whole
  /// Speed path thus ended one step before the target.
  ///
  /// WHAT COMES IN HERE IS NOT YET ASSIGNED. The body is an
  /// aggregate of sealed payloads (§4.3) — from whom is nowhere in
  /// plaintext (invariant 3). This file knows neither pairs nor
  /// sealing; it passes the bytes up and lets whoever has the keys
  /// assign them. A dummy cell of a partner looks exactly the same at this
  /// place and is silently discarded above — that is the
  /// normal case, not an error.
  ///
  /// The partner index comes ALONG: the reassembler of the level above
  /// works per session (the transfer identifier is chosen by the sender and
  /// is not unique across senders). Passing it in afterwards via a field
  /// would be a state that can flip between two cells
  /// — here it is an argument.
  void Function(int fromPartner, Uint8List body)? onInbound;

  /// A cell has left this node FOR SOMEONE ELSE (§25.5).
  ///
  /// Called at the three places in [receive] where a foreign cell
  /// actually runs on: r1 forwards, r2 delivers, and the
  /// case r1 = r2, in which the same node does both. NOT called for
  /// own mail (`CellRole.mine`) and not for a cell that ends here
  /// because no path was found — otherwise the display would count
  /// forwardings that never took place.
  ///
  /// BARE CALLBACK, without any reference to the statistics collector. The
  /// reason is stated in detail at `V41Node.start` at
  /// `onWireBytesSent`/`onWireBytesReceived`: an import edge from the
  /// delivery layer onto the display layer would lift the layer boundary
  /// that `smoke_link_io_milestone` guards. Wiring happens at the
  /// composition point.
  void Function(int bytes)? onRelay;

  /// A send attempt in [tick] has failed at the transport (D-3, S372).
  ///
  /// Called AFTER the payload or control frame has already been
  /// put back via `CoverStream.requeueReal`/`requeueControl` —
  /// this is the report "to the delivery state", not the mechanism
  /// that rescues the payload (that is done by [tick] itself, BEFORE this
  /// call). [recipient] is `null` for a failed
  /// control frame. `tick()` no longer THROWS in this case — the
  /// caller (`SlotDriver`) stays a pure safety net for everything else,
  /// see its header comment.
  void Function(String? recipient, Object error)? onSendFailed;

  /// A relay has confirmed (or refused) a placement.
  /// A placement receipt for an OWN placement.
  ///
  /// The first parameter is the identifier from [placeRequestId], not the
  /// tag: the tag is the mailbox line of a pair and has no business on the
  /// return path (IP-1). Whoever wants to know WHICH placement
  /// was confirmed looks up the identifier in their own book —
  /// only the sender has it.
  void Function(Uint8List requestId, bool stored, int fromPartner,
      Uint8List rawAck)? onPlaceAck;

  /// Delivers up to N arbitrary entry records for passing on.
  ///
  /// What comes out here is determined by the node — the delivery layer knows
  /// neither the supply nor the question of who wants to publish themselves.
  List<EntryRecord> Function(int count)? entrySetProvider;

  // ═════════════════════════════════════════════════════════════════
  // THE HOLDER SIDE OF THE BULK LANE (§9.3)
  // ═════════════════════════════════════════════════════════════════
  //
  // ── WHAT IS HERE AND WHAT DELIBERATELY IS NOT ────────────────────
  //
  // Here is the role of the HOLDER and that of the passing-through hop.
  // The SENDER is not here — it chooses holders in turn, clocks at
  // `R_bulk` and lives in `service/media_bulk_transport_v41.dart`. The
  // separation is the same as between `_handleControl` (holder) and
  // `V41Node.placeSecure` (sender): for foreign transfers a node is
  // almost always only a holder, and the holder role must
  // know nothing about the send state.
  //
  // ── RESPONSIBILITY IS NOT CHECKED, AND DELIBERATELY SO ───────────
  //
  // As with the placement of the delivery layer (see the comment at
  // `_handleControl`): a refusal "this line is not mine"
  // would reveal to the placer where the border of the own neighbourhood
  // lies. The limit is via the QUOTA (`BulkCache`, 1 GB, and
  // none at all on mobile), not via information.
  //
  // ── ANSWERS GO OUT IMMEDIATELY, BUT CAPPED ───────────────────────
  //
  // An answer is forwarding traffic (appendix B-17) and therefore
  // takes no slot. Uncapped it would nevertheless violate
  // work rule 5: handing out a line with 256 000 blocks at once
  // would be 274 MB from a single request.
  // [kBulkScanResponseLimit] caps it at 32 — one second of
  // `R_bulk` —, and the REQUESTER determines the clock by sampling
  // again. That is exactly how §9.3 is meant: "harvested by the recipient on
  // its own cadence".
  // ── THE BOOKING (§25.5/§25.6), AND THE RULE BEHIND IT ────────────
  //
  // What this node passes on for ANOTHER is booked
  // (`onRelay`); what it answers from its OWN supply is not — there
  // it is the endpoint, not a relay. The same separation as for cells.
  //
  // WHY THE BORDER LIES EXACTLY THERE (v4_1 §25.6): "Speed forwarding is
  // transient — the onion is forwarded per-hop, not stored — so there is
  // no storage contribution from forwarding to account for. […] A relay
  // may count the onions it forwards as a local diagnostic." The
  // forwarding counter is thus the PASSING-THROUGH cell. What a
  // node holds and hands out is the other role and has its
  // own quantities in §25.6 ("cells held", occupancy, displacement).
  // Whoever additionally booked delivery from the own supply as
  // forwarding would count the holder role twice — and
  // "forwarded messages" would include cells that this node did
  // not pass on, but answered.
  //
  // RE-MEASURED (S376, P4-1): this file has 26 send sites —
  // 4x `.emit(`, 12x `.emitFrame(`, 10x `.emitControl(`, each counted without
  // comment lines. Here stood "22 … 4x/9x/9x" (S363); already
  // before this session it was 4/10/9 = 23, so the number was already
  // an epoch old. It is prose and not a gate — the guard
  // `smoke_network_stats` saw until S363 only the 4 on `.emit(`; its
  // search set was a CHARACTER STRING instead of its statement. It now derives it
  // from `cell_transport.dart` (which methods reach `channel.send`)
  // and checks all of `lib/`.
  NodeAction _handleBulk(int fromPartner, BulkFrame b) {
    switch (b.op) {
      case BulkOp.place:
        if (!_amTarget(b.holder!)) {
          return _forwardBulk(b, 'Bulk-Ablage');
        }
        // ARRIVED. The holder stamps with ITS clock (`BulkCache`
        // explains why not with that of the placer).
        final ok = bulk.place(b.line!, b.sealedBlock!, nowUtc());
        if (ok) bulkPlacementsHeld++;
        return NodeAction(ok
            ? 'Bulk block held (${bulk.blockCount} in total)'
            : 'Bulk block rejected (quota)');
      case BulkOp.scanRequest:
        if (!_amTarget(b.holder!)) {
          // REMEMBER THE RETURN PATH, otherwise the answer does not find home —
          // word for word as with the harvest request, and that is intentional: whoever builds
          // something of their own here rebuilds 28.08.
          if (b.hops > 0) {
            final next = nextHopToward?.call(b.holder!);
            final further =
                next == null ? null : decrementBulkHops(b.raw);
            if (next != null &&
                further != null &&
                pending.remember(b.requestId!, fromPartner, nowUtc())) {
              partners[next].emitFrame(LinkFrameType.fountain, further);
              onRelay?.call(further.length);
              bulkForwarded++;
              return NodeAction('Bulk probe passed on',
                  partner: next);
            }
          }
          return NodeAction('Bulk probe ends here '
              '(return paths of this partner: '
              '${pending.openFor(fromPartner)}/${pending.perPartner})');
        }
        // `scanFrom` AND NOT `scan`: what is reported is the distance
        // COVERED, not the number of hits. The two are
        // different as soon as the have-list has filtered something out,
        // and the sampler keeps computing with the distance — the
        // reasoning is at `BulkCache.scanFrom`.
        final run = bulk.scanFrom(b.line!,
            have: b.have, limit: b.limit, offset: b.count);
        final found = run.entries;
        for (final e in found) {
          partners[fromPartner].emitFrame(LinkFrameType.fountain,
              buildBulkBlock(b.requestId!, b.line!, e.sealed));
          // NO FORWARDING — this node IS the holder and hands out from
          // its own `BulkCache`. The block does not run through
          // it, it ends and begins here. The holder role has
          // its own quantities (§25.6, held blocks); additionally booking it
          // as forwarding would count it twice.
        }
        // ── THE ROUND IS CLOSED, EVEN AT ZERO ────────────────────────
        //
        // Without this frame the requester would have to hang its re-offer on
        // the individual block arrival — 128 arrivals per round,
        // each would trigger a new one (reasoning at `BulkOp.scanEnd`).
        // And with ZERO hits it would have no signal at all and
        // would have to wait or poll; both are excluded here
        // (§19: no polling).
        //
        // The number is how many entries this holder has handed out for this
        // request — the requester adds it to its
        // `skip` for EXACTLY THIS holder.
        partners[fromPartner].emitFrame(LinkFrameType.fountain,
            buildBulkScanEnd(b.requestId!, b.line!, run.advanced));
        // NO FORWARDING — the round end is this holder's own answer
        // to the own sampling above, not a foreign
        // frame running on. It belongs to the same delivery
        // as the blocks a hand's breadth higher.
        bulkBlocksServed += found.length;
        return NodeAction('Bulk probed: ${found.length}',
            partner: fromPartner);
      case BulkOp.scanResponse:
        final back = pending.peekRoute(b.requestId!, nowUtc());
        if (back != null) {
          partners[back].emitFrame(LinkFrameType.fountain, b.raw);
          onRelay?.call(b.raw.length);
          bulkForwarded++;
          return NodeAction('Bulk answer passed on', partner: back);
        }
        // If we do not know the return path, the request was our own.
        onBulkScanned?.call(b.requestId!, b.line!, b.sealedBlock!);
        return NodeAction('Bulk block received');
      case BulkOp.scanEnd:
        // WORD FOR WORD AS THE ANSWER ABOVE, and that is intentional: the same
        // return path, the same distinction "foreign or own". Whoever builds
        // something of their own here rebuilds 28.08. (54 crashes because
        // a frame type did not follow the shared path).
        //
        // `peekRoute` and not `takeRoute`: for ONE request come
        // several blocks AND this end; whoever used up the path at the first
        // frame would leave all following ones lying.
        final home = pending.peekRoute(b.requestId!, nowUtc());
        if (home != null) {
          partners[home].emitFrame(LinkFrameType.fountain, b.raw);
          onRelay?.call(b.raw.length);
          bulkForwarded++;
          return NodeAction('Bulk-Rundenende weitergereicht', partner: home);
        }
        onBulkScanEnd?.call(b.requestId!, b.line!, b.count);
        return NodeAction('Bulk round ended: ${b.count}');
      case BulkOp.publicBlock:
        // ── THE COVER FILL ENDS HERE (§5.5) ───────────────────────────
        //
        // Three things do NOT happen, and all three are rules:
        //
        //   * no passing on — it would be an additional cell and
        //     thus rule 1 ("never a slot of its own"). That is why
        //     [BulkOp.publicBlock] is not in [kForwardableBulkOps] either;
        //   * no answer, no receipt — rule 4 ("no back
        //     channel"). The callback returns nothing;
        //   * no entry in the `BulkCache`. That belongs to the
        //     HOLDER SERVICE for foreign transfers (§9.3, placement under
        //     a tagline); an unsolicited block has no
        //     tagline and is destined for this node itself.
        //
        // The spreading arises from every node filling its
        // OWN due cover slots, not from a
        // frame running on.
        //
        // ── THE RATE LIMIT, AND WHY IT IS HERE (S368) ─────────────────
        //
        // §5.5 opens a door for UNSOLICITED data. The four
        // caps in `UpdateCoverFill` limit the MEMORY, and
        // hard: measured 0 B taken in after 22 000 unsolicited
        // blocks of an unregistered object
        // (`probe_acceptance_point_last_s368.dart`). What they do NOT
        // limit is the COMPUTE TIME — every rejected block costs
        // up to [kCoverFillMaxObjects] unsuccessful AEAD openings,
        // measured **24.89 us**. And `PendingRequests` states above
        // explicitly: "incoming frames are not throttled".
        //
        // Computed what that would mean without a limit: with 1200 B cells
        // 1 Gbit/s is about 104 000 cells/s, i.e. **259 % of a core** —
        // a single sync partner could tie up two and a half cores
        // without placing a single byte. At 100 Mbit/s it is
        // 26 %.
        //
        // **The honest rate is in the protocol, therefore the limit is
        // sharp and not guessed.** An honest partner puts one
        // block into a DUE cover slot (rule 1), and a slot falls
        // every `kSlotInterval` = 8 s. More than one block per slot it
        // cannot send at all without breaking rule 1. The cap lies
        // at [kCoverFillMaxPerPartnerPerSlot] and thus a multiple
        // above what is honestly possible — it costs
        // no honest block and cuts the bombardment by a factor of
        // ~35 000.
        //
        // NO ANSWER TO THE REJECTION. A hint would be a
        // back channel (rule 4) and would look to an observer exactly like
        // the distinction that §5.1 is meant to prevent.
        final slice =
            nowUtc().millisecondsSinceEpoch ~/ kSlotInterval.inMilliseconds;
        final (last, number) = _coverFillRate[fromPartner] ?? (slice, 0);
        if (last == slice && number >= kCoverFillMaxPerPartnerPerSlot) {
          coverFillRateDropped++;
          return NodeAction('cover fill above the rate discarded');
        }
        _coverFillRate[fromPartner] =
            last == slice ? (slice, number + 1) : (slice, 1);
        coverFillReceived++;
        onCoverFillBlock?.call(b.sealedBlock!);
        return NodeAction('cover fill received');
      default:
        return NodeAction('unknown bulk operation ${b.op}');
    }
  }

  /// Passes a bulk PLACEMENT on greedily.
  ///
  /// WITHOUT a return-path memo, unlike sampling: a placement gets
  /// no answer. §9.3 knows no placement receipt for the bulk lane —
  /// the redundancy is the overhead factor `F`, not a confirmation
  /// per block. A receipt per block would moreover be a second
  /// back channel of the same order of magnitude as the payload
  /// (work rule 5).
  ///
  /// IMMEDIATELY AND NOT VIA THE OUTFLOW: forwarding traffic is clocked by
  /// the arrival, not by the node (B-17). The sender has already
  /// thinned the blocks to `R_bulk`; whoever put them into a queue of their own
  /// here again would double the latency per hop and
  /// get nothing for it.
  NodeAction _forwardBulk(BulkFrame b, String what) {
    if (b.hops <= 0) return NodeAction('$what ends here (hops used up)');
    final next = nextHopToward?.call(b.holder!);
    if (next == null) return NodeAction('$what ends here (no path)');
    final further = decrementBulkHops(b.raw);
    if (further == null) return NodeAction('$what cannot be passed on');
    partners[next].emitFrame(LinkFrameType.fountain, further);
    onRelay?.call(further.length);
    bulkForwarded++;
    return NodeAction('$what weitergereicht', partner: next);
  }

  NodeAction _handleControl(int fromPartner, SecureFrame c) {
    switch (c.op) {
      case SecureOp.place:
        // WHO AM I FOR THIS PLACEMENT? If I am the target, I store.
        // If I am not, I pass on to a partner that is CLOSER to the
        // target than I am — greedy, and therefore finite. If I know
        // no closer one, I am the local minimum: then I store
        // instead of dropping the cell. A target that nobody knows
        // is better kept at its nearest neighbour than nowhere.
        // WHAT AN INTERMEDIATE NODE SEES: the target, nothing else. Tag and
        // content are sealed to the target (IP-1) — before, every hop read
        // the tag along, and the tag is the mailbox line of a pair.
        final notForUns = !_amTarget(c.target!);
        if (notForUns) {
          if (c.hops > 0) {
            final next = nextHopToward?.call(c.target!);
            final further =
                next == null ? null : decrementHops(c.raw!);
            // ── REMEMBER THE RETURN PATH, OTHERWISE THE RECEIPT DOES NOT FIND HOME
            //
            // WORD FOR WORD AS HARVEST AND `findNode` — and that is the
            // point: until S357, as the ONLY multi-hop frame, there was
            // no `pending.remember` line here. The placement ran over
            // any number of hops to the relay, the relay confirmed
            // to its PREDECESSOR, and there the receipt ended. The
            // sender learned of not a single placement that did not lie
            // with a direct neighbour.
            //
            // Worse than the silence was what the predecessor hop
            // did instead: it took the foreign receipt as its OWN
            // proof (`onPlaceAck` was called unconditionally) and let
            // its readiness rise from it. §22.7 bases it on
            // "evidence, not acquaintance" — that was acquaintance
            // posing as proof.
            //
            // The identifier is NOT on the wire, it is computed from the
            // frame (`placeRequestId`): every hop arrives at
            // the same number, and the placement costs no byte for it.
            if (next != null && further != null) {
              // THE RETURN PATH IS BEST EFFORT, THE DELIVERY IS NOT.
              // Unlike with harvest, passing on does NOT depend here on
              // the return path: a harvest without a return path is pointless,
              // a placement without a return path still stores the cell.
              // If the return-path store is full, the cell thus
              // goes out and the receipt expires — that is exactly the
              // behaviour from before S357, and thus never worse than
              // before. `pending.dropped` counts these cases.
              pending.remember(
                  placeRequestId(c.raw!), fromPartner, nowUtc());
              partners[next].emitControl(further);
              onRelay?.call(further.length);
              return NodeAction('Placement passed on', partner: next);
            }
          }
          // No closer partner, or the hops are used up.
        }
        // NEVERTHELESS TRY TO OPEN FIRST, even if the target is not our
        // position. `L_node` rotates (decision A, §9.1): a placement
        // can be addressed to our PREVIOUS position while our
        // static X25519 part has stayed the same. Whoever relies here on
        // the position comparison alone throws their own mail
        // into custody.
        final opened = ownX25519Secret == null
            ? null
            : openPlace(c.raw!, ownX25519Secret!);
        if (opened == null) {
          // ── BLIND PLACEMENT AT THE LOCAL MINIMUM (§11.2, path a) ─────
          //
          // "a relay that knows no nearer partner is the local minimum and
          // stores rather than dropping — a target nobody knows is better
          // kept at its nearest neighbour than nowhere."
          //
          // WHEN EXACTLY WE ARE HERE. Only if (a) the target is not us,
          // (b) hops were still left and (c) `nextHopToward`
          // nevertheless returned `null`. That is the definition of the
          // local minimum. If the hops were used up, we would
          // NOT be it — then there would be a closer neighbour and the
          // frame would only have used up its loop protection; keeping it
          // nevertheless would turn the protection into a lever
          // (unload `hops = 1` at every neighbour).
          //
          // NO CONFIRMATION. `buildPlaceAck` needs the tag, and that
          // we just do not have — it lies under the seal. That is
          // no flaw, but right: §22.7 bases readiness
          // on "evidence, not acquaintance", and a blind keeper
          // has no proof that it can place FOR THIS TAG.
          if (notForUns && c.hops > 0) {
            final ok = blind.hold(c.target!, c.raw!, fromPartner, epochNow());
            return NodeAction(ok ? 'stored blind' : 'Blind quota full');
          }
          // Addressed to us, but cannot be opened — or we have
          // no key. Discard silently; a confirmation would
          // here be information about our keys.
          return NodeAction('Placement cannot be opened');
        }
        // THE BUCKET IS STAMPED HERE, not delivered along (§17.2,
        // S358). The same reasoning as for `epochNow()` one line
        // further: if the placer could choose it, a sender could
        // claim a bucket in the future and let its signal cell
        // lie on foreign relays for arbitrarily long. The CLASS,
        // on the other hand, comes from the seal — it is the sender's intention
        // and readable only by whoever opens the placement.
        final ok = store.place(opened.tag, opened.cell, epochNow(),
            retention: opened.retention,
            bucket: retentionBucket(nowUtc()));
        // Confirmation is answer traffic and may go out immediately (B-17).
        // REFUSED is confirmed just like accepted: if the
        // relay stayed silent at a full quota, a full relay could not be told apart from a dead
        // one, and the sender would wait for both
        // equally long.
        partners[fromPartner].emitControl(buildPlaceAck(
            placeRequestId(c.raw!),
            stored: ok,
            ackKey: opened.ackKey));
        // NO FORWARDING — this node has accepted (or refused) the placement ITSELF
        // and acknowledges as the endpoint. The
        // frame arises here, it does not run through. The passed-on
        // receipt is the branch `SecureOp.placeAck` below, and that one
        // books.
        return NodeAction(ok ? 'abgelegt' : 'Quota full',
            partner: fromPartner, detail: tagLabel(opened.tag));
      case SecureOp.placeAck:
        // If we know the identifier, we passed this placement on —
        // then the receipt does not belong to us, but to the one from whom
        // it came. The return path is USED UP in the process (`takeRoute`, not
        // `peekRoute`): a placement has EXACTLY ONE receipt. If the
        // identifier stayed, a relay could push arbitrarily many
        // receipts into the same path with one identifier.
        final back = pending.takeRoute(c.requestId!, nowUtc());
        if (back != null) {
          returnedReceipts++;
          partners[back].emitControl(c.raw!);
          onRelay?.call(c.raw!.length);
          return NodeAction('Placement receipt passed on',
              partner: back);
        }
        // If we do not know it, the placement was our own. The RAW
        // frame goes along: only the sender has the key under which
        // the MAC verifies, so only it can decide whether the receipt
        // comes from the target relay.
        final stored = c.cell != null && c.cell![0] == kPlaceStored;
        onPlaceAck?.call(c.requestId!, stored, fromPartner, c.raw!);
        return NodeAction(
            stored ? 'Placement confirmed' : 'Relay quota full');
      case SecureOp.harvestRequest:
        // Not for us? Then the same path as a placement — greedy to the
        // target. Remember the return path first, otherwise the answer does not find
        // home.
        if (!_amTarget(c.target!)) {
          if (c.hops > 0) {
            final next = nextHopToward?.call(c.target!);
            final further =
                next == null ? null : decrementHops(c.raw!);
            if (next != null &&
                further != null &&
                pending.remember(c.requestId!, fromPartner, nowUtc())) {
              partners[next].emitControl(further);
              onRelay?.call(further.length);
              return NodeAction('Harvest passed on', partner: next);
            }
          }
          // WHY IT ENDS HERE is in the text — otherwise a
          // stopping relay cannot be told apart from a dead one.
          // The number of open return paths of THIS neighbour names the
          // case in which the partner cap applied: then the
          // node is not overloaded, but ONE neighbour is.
          return NodeAction('Harvest ends here '
              '(return paths of this partner: '
              '${pending.openFor(fromPartner)}/${pending.perPartner})');
        }
        final request = ownX25519Secret == null
            ? null
            : openHarvestRequest(c.raw!, ownX25519Secret!);
        if (request == null) {
          return NodeAction('Harvest request cannot be opened');
        }
        // THE HAVE-LIST IS RESPECTED (B-32). What the requester already
        // has completely does not go out again — but the cell
        // stays, because §14.2 owes it to the second device of the same
        // identity.
        final found = store.harvest(request.tags, exclude: request.have);
        for (final s in found) {
          partners[fromPartner]
              .emitControl(buildHarvestResponse(c.requestId!, s.cell));
          // NO FORWARDING — the cell comes from the OWN
          // `SecureStore`. This node is the responsible relay and
          // delivers, it passes nothing through. Its holder performance
          // is in the quantities of §25.6 (held cells, occupancy,
          // displacement); booking it here a second time as forwarding
          // would make two numbers out of one role. The
          // passed-on answer is the branch `harvestResponse`
          // below, and that one books.
        }
        // THE QUERIED TAGS BELONG TO IT, not only the hit count.
        // "geerntet: 0" alone does not say whether the requester named the wrong
        // tag or whether nothing lies under the right one — that is
        // the difference between a derivation error and a
        // lost placement. The decoys are included; the relay
        // cannot tell them apart anyway, and whoever reads the log sees
        // four prefixes, of which exactly one also appears on the placement side.
        return NodeAction('geerntet: ${found.length}',
            partner: fromPartner,
            detail: '[${request.tags.map(tagLabel).join(' ')}]');
      case SecureOp.harvestResponse:
        // If the identifier belongs to a path we remembered,
        // the answer goes back the same way. If we do not know it, the
        // request was our own.
        final back = pending.peekRoute(c.requestId!, nowUtc());
        if (back != null) {
          partners[back].emitControl(c.raw!);
          onRelay?.call(c.raw!.length);
          return NodeAction('Harvest answer passed on', partner: back);
        }
        onHarvested?.call(c.requestId!, c.cell!);
        return NodeAction('harvest answer received');
      case SecureOp.findNodeOnion:
        {
          // ── LEG 1: up to the blind relay ───────────────────────────
          //
          // Up to here this is WORD FOR WORD as the search request: greedy to
          // `target`, remember the return path, subtract hops. The difference
          // lies solely in what `target` is — here the BLIND RELAY,
          // which has nothing to do with the search point. A hop on this
          // leg therefore sees neither the target relay nor the search point.
          if (!_amTarget(c.target!)) {
            if (c.hops > 0) {
              final next = nextHopToward?.call(c.target!);
              final further = next == null ? null : decrementHops(c.raw!);
              if (next != null &&
                  further != null &&
                  pending.remember(c.requestId!, fromPartner, nowUtc())) {
                partners[next].emitControl(further);
                onRelay?.call(further.length);
                return NodeAction('Suchzwiebel weitergereicht',
                    partner: next);
              }
            }
            return NodeAction('Lookup onion ends here '
                '(return paths of this partner: '
                '${pending.openFor(fromPartner)}/${pending.perPartner})');
          }

          // ── THIS NODE IS THE BLIND RELAY ──────────────────────
          final insideRaw = ownX25519Secret == null
              ? null
              : openFindNodeOnion(c.raw!, ownX25519Secret!);
          if (insideRaw == null) {
            return NodeAction('Lookup onion cannot be opened');
          }
          final inside = parseSecureFrame(insideRaw);
          if (inside == null ||
              (inside.op != SecureOp.findNode &&
                  inside.op != SecureOp.findNodeOnion)) {
            // No error, but a malformed frame from the wire
            // (E-83). An onion that carries something other than a
            // search request or the next layer would be a lever: it
            // would let a stranger put arbitrary frames into the network under the
            // sender address of this node.
            //
            // EXACTLY TWO CASES, since S377 (`kLookupOnionShells = 2`).
            // The depth itself is already capped in the LENGTH
            // (`lookupOnionDepth`, checked in `parseSecureFrame` and in
            // `openFindNodeOnion`) — here only the question remains WHAT
            // kind of frame it is.
            return NodeAction('Lookup onion carries no lookup request');
          }
          // TWO DIFFERENT IDENTIFIERS, otherwise leg 2 kills the
          // return path of leg 1 (`PendingRequests.remember`
          // overwrites on the same identifier from another neighbour).
          // That is a check at the RECIPIENT and not only a
          // promise of the sender — a sender that chooses both
          // equal would otherwise break the return path of foreign operations.
          var equal = inside.requestId!.length == c.requestId!.length;
          if (equal) {
            for (var i = 0; i < inside.requestId!.length; i++) {
              if (inside.requestId![i] != c.requestId![i]) {
                equal = false;
                break;
              }
            }
          }
          if (equal) {
            return NodeAction('search onion with the same identifier on '
                'both legs — discarded');
          }
          // TWO LAYERS ON THE SAME NODE — DISCARDED (S377).
          //
          // The searcher excludes that (`_blindRelayChain` draws
          // WITHOUT replacement), but a stranger may build it, so it must
          // hold here. Rejecting it is not tidiness: if
          // both layers ran over ONE node, that node would see both ends of the
          // chain and collusion would again need only two nodes
          // instead of three — a silent fallback from two layers to one,
          // while the frame still looks like two. That is
          // the same class as `kein_stiller_moduswechsel`.
          //
          // The alternative — stripping the own layer right away —
          // would moreover be an amplifier: one frame, arbitrarily many
          // decryptions on one node.
          if (inside.op == SecureOp.findNodeOnion && _amTarget(inside.target!)) {
            return NodeAction('search onion points to the same node '
                '— discarded');
          }
          if (!onionAliases.remember(
              inside.requestId!, c.requestId!, nowUtc())) {
            // Without an alias the answer would find the way up to here and
            // then no further. Better not to pass on at all than to
            // produce an answer that gets lost.
            return NodeAction('no room for the return path of the lookup onion');
          }

          // SPECIAL CASE: the blind relay is itself the target relay. The
          // searcher rules that out (it excludes it), but a
          // stranger may build it — so it must hold here. The answer
          // is then given with the OUTER identifier, because the neighbour knows
          // only that one.
          if (inside.op == SecureOp.findNode && _amTarget(inside.target!)) {
            final point = ownX25519Secret == null
                ? null
                : openFindNode(insideRaw, ownX25519Secret!);
            if (point == null) {
              return NodeAction('Lookup request in the onion cannot be opened');
            }
            final near = nearestKnown?.call(point) ?? const <Uint8List>[];
            partners[fromPartner]
                .emitControl(buildFindNodeResponse(c.requestId!, near));
            // NO FORWARDING — this node IS the target relay and
            // answers from its OWN table (`nearestKnown`); no
            // foreign frame goes on. The same class as the
            // ordinary search answer and as the round end of the
            // bulk sampling above.
            //
            // The mark has been here since the merge of P4 and P9
            // (S376): P9 brought this send site, P4 sharpened the
            // guard behind it in the same session. In the
            // single tree neither of the two could see that — the corpus
            // on the collecting line could.
            return NodeAction(
                'Lookup from the onion answered: ${near.length} positions',
                partner: fromPartner);
          }

          // ── THE NEXT LEG ───────────────────────────────────────────
          //
          // The inner frame goes out UNCHANGED — with the full
          // hop supply that the searcher put in. For the
          // next recipient it thus looks like a request that
          // this blind relay made itself. That is exactly the
          // purpose.
          //
          // It is THE SAME piece of code for every layer (S377): if the
          // inner frame is again an onion, it goes to the next
          // blind relay; if it is the search request, it goes to the
          // target relay. `inside.target` says which case applies, and
          // this node need not know the difference — it only ever sees
          // its two neighbouring legs of the chain.
          final next = nextHopToward?.call(inside.target!);
          if (next == null) {
            return NodeAction('Lookup onion opened, but no path to the '
                'target relay');
          }
          if (!pending.remember(inside.requestId!, fromPartner, nowUtc())) {
            return NodeAction('Lookup onion opened, but no return path '
                'free (partner $fromPartner: '
                '${pending.openFor(fromPartner)}/${pending.perPartner})');
          }
          partners[next].emitControl(insideRaw);
          onRelay?.call(insideRaw.length);
          blindRelayHandovers++;
          return NodeAction('Lookup passed on as blind relay',
              partner: next);
        }
      case SecureOp.findNode:
        // WORD FOR WORD AS THE HARVEST REQUEST, and that is intentional: the same
        // return-path memo, the same hop counting, the same greedy
        // passing on. Whoever builds something of their own here rebuilds 28.08.
        if (!_amTarget(c.target!)) {
          if (c.hops > 0) {
            final next = nextHopToward?.call(c.target!);
            final further = next == null ? null : decrementHops(c.raw!);
            if (next != null &&
                further != null &&
                pending.remember(c.requestId!, fromPartner, nowUtc())) {
              partners[next].emitControl(further);
              onRelay?.call(further.length);
              return NodeAction('Lookup passed on', partner: next);
            }
          }
          // WHY IT ENDS HERE is in the text — otherwise a
          // stopping relay cannot be told apart from a dead one.
          // The number of open return paths of THIS neighbour names the
          // case in which the partner cap applied: then the
          // node is not overloaded, but ONE neighbour is.
          return NodeAction('Lookup ends here '
              '(return paths of this partner: '
              '${pending.openFor(fromPartner)}/${pending.perPartner})');
        }
        final point = ownX25519Secret == null
            ? null
            : openFindNode(c.raw!, ownX25519Secret!);
        if (point == null) {
          return NodeAction('Lookup request cannot be opened');
        }
        final near = nearestKnown?.call(point) ?? const <Uint8List>[];
        // AN ANSWER IS FORWARDING TRAFFIC and may go out immediately
        // (appendix B-17) — one cell, no fragmentation.
        partners[fromPartner]
            .emitControl(buildFindNodeResponse(c.requestId!, near));
        // NO FORWARDING — the positions come from the OWN
        // routing table (`nearestKnown`). The frame arises here; the
        // passed-on answer is the branch `findNodeResponse`
        // below, and that one books.
        return NodeAction('Lookup answered: ${near.length} positions',
            partner: fromPartner);
      case SecureOp.findNodeResponse:
        // ── THE BLIND RELAY RELABELS (E-L) ──────────────────────────
        //
        // This answer carries the INNER identifier; the neighbour to which
        // it goes on knows only the outer one. Only this node
        // knows both — therefore the rewriting is here and nowhere
        // else. No alias: ordinary answer, unchanged path.
        final outside = onionAliases.outerFor(c.requestId!, nowUtc());
        if (outside != null) {
          final back = pending.peekRoute(c.requestId!, nowUtc());
          final at = relabelFindNodeResponse(c.raw!, outside);
          if (back != null && at != null) {
            partners[back].emitControl(at);
            onRelay?.call(at.length);
            blindRelayAnswer++;
            return NodeAction('Lookup answer passed on relabelled',
                partner: back);
          }
          return NodeAction('Lookup answer at the blind relay without return path');
        }
        final home = pending.peekRoute(c.requestId!, nowUtc());
        if (home != null) {
          partners[home].emitControl(c.raw!);
          onRelay?.call(c.raw!.length);
          return NodeAction('Lookup answer passed on', partner: home);
        }
        // WHAT DOES NOT HAPPEN HERE: the positions do NOT move by
        // themselves into the routing table. The lookup needs them for its
        // round; whether one of them is learned permanently is decided by the
        // node (`_learn`) — and §9.1/finding 3 says why that is not
        // the same: the R nearest to a FOREIGN target lie almost
        // all in ONE bucket, and that holds k = 20.
        onNodesFound?.call(c.requestId!, c.tags);
        return NodeAction('Lookup answer received: ${c.tags.length}');
      case SecureOp.entryRequest:
        // ── DIRECTED, WITH PASSING ON (S376, P4-1) ───────────────────
        //
        // Here stood: "Only what the node knows ITSELF is answered
        // — nothing is asked onward. Otherwise a request would be a
        // lever with which a stranger makes the node search the network."
        // The CONCERN was right, the answer to it wrong: the frame
        // does not make the node search anything now either. It PASSES
        // on — one hop, greedy to the target, with a hop counter
        // that every hop decrements. That is the same movement as with
        // the harvest request and with `findNode` and costs the node
        // exactly one frame, not a search.
        //
        // Whoever passes nothing on lets the request end at whoever
        // chance chose. §11.1 demands the opposite:
        // "fetched on demand … ask the one who announced the position."
        //
        // FIRST THE OWN SUPPLY, then passing on: the normal case is
        // that a neighbour of the searched position knows it. A frame
        // that can be answered here runs no further hop.
        final have = entryProvider?.call(c.target!);
        if (have != null) {
          // Answer: forwarding traffic, may go out immediately (B-17).
          // It is larger than a cell and gets split.
          final frames = fragmentFrame(LinkFrameType.control,
              buildEntryResponse([have], requestId: c.requestId));
          for (final f in frames) {
            partners[fromPartner].emitFrame(f.type, f.body);
            // NO FORWARDING — the record comes from the OWN
            // supply (`entryProvider`). Here this node is the endpoint
            // and not a relay; the fragments arise at this place,
            // no foreign frame runs through. Only the
            // passing on in the branch below is booked (§25.6: "the onion is
            // forwarded per-hop" — what a node holds and hands out
            // is the other role).
          }
          return NodeAction(
              'Entry record sent (${frames.length} cells)',
              partner: fromPartner);
        }
        if (c.hops > 0) {
          final next = nextHopToward?.call(c.target!);
          final further = next == null ? null : decrementHops(c.raw!);
          if (next != null &&
              next != fromPartner &&
              further != null &&
              pending.remember(c.requestId!, fromPartner, nowUtc())) {
            partners[next].emitControl(further);
            onRelay?.call(further.length);
            return NodeAction('entry request passed on',
                partner: next);
          }
        }
        // ── IT ENDS HERE, BUT NOT SILENTLY ───────────────────────────
        //
        // An EMPTY answer instead of silence, for the same reason as with
        // the set request (P4-3): the requester otherwise waits for something
        // that never comes, and keeps its place in
        // `V41Node._openEntryRequests` occupied. 18 B (measured), i.e.
        // one cell, on a slot that carries one anyway.
        final empty = fragmentFrame(LinkFrameType.control,
            buildEntryResponse(const <EntryRecord>[], requestId: c.requestId));
        for (final f in empty) {
          partners[fromPartner].emitFrame(f.type, f.body);
          // NO FORWARDING — the empty answer ARISES here, it
          // is not a passing-through frame. It says "I do not have it
          // and get no further"; the passing on that just did NOT
          // take place is therefore not booked.
        }
        return NodeAction('Entry request ends here '
            '(return paths of this partner: '
            '${pending.openFor(fromPartner)}/${pending.perPartner})',
            partner: fromPartner);
      case SecureOp.entrySetRequest:
        final howMany = c.cell == null ? 0 : c.cell![0];
        final currentSet = entrySetProvider?.call(howMany) ?? const <EntryRecord>[];
        // ── THE EMPTY SET IS ANSWERED TOO (S376, P4-3) ───────────────
        //
        // Here stood `if (menge.isEmpty) return NodeAction(...)` — i.e.
        // silence. But the requester holds a lock that only an
        // ANSWER releases; a partner without entries thus blocked
        // the neighbourhood extension for it until restart. The empty answer
        // is 18 B long (measured) and rides a slot that carries a cell
        // anyway — it costs no additional datagram
        // (work rule 5).
        //
        // NO LEAK: that this node has nothing to pass on it says
        // anyway as soon as it has something next time. And the set
        // is drawn randomly (`_entrySet`), it reveals no
        // neighbourhood.
        final frame = fragmentFrame(
            LinkFrameType.control, buildEntryResponse(currentSet));
        for (final f in frame) {
          partners[fromPartner].emitFrame(f.type, f.body);
          // NO FORWARDING — as with `entryRequest` above: the
          // set comes from the OWN stock (`entrySetProvider`).
        }
        return NodeAction(
            'Entry set sent: ${currentSet.length} (${frame.length} cells)',
            partner: fromPartner);
      case SecureOp.entryResponse:
        // ── FIRST THE RETURN PATH (S376, P4-1) ───────────────────────
        //
        // An answer to a DIRECTED request carries its identifier
        // and belongs to the one from whom the request came. The return path
        // is USED UP in the process (`takeRoute`, not `peekRoute`): a request
        // has exactly one answer. An UNSOLICITED answer
        // (`announceOwnEntry`, answer to a set request) carries the
        // zero identifier and can therefore not redeem a foreign return path.
        final backEntry = c.requestId == null ||
                isUnsolicited(c.requestId!)
            ? null
            : pending.takeRoute(c.requestId!, nowUtc());
        if (backEntry != null) {
          // SPLIT ANEW and not passed through: the answer is larger
          // than a cell, and the fragment identifiers apply per session
          // (`CellTransport.reassembler`). The frame itself goes on
          // unchanged — the identifier in it is the return path of the
          // next hop.
          for (final f
              in fragmentFrame(LinkFrameType.control, c.raw!)) {
            partners[backEntry].emitFrame(f.type, f.body);
          }
          onRelay?.call(c.raw!.length);
          return NodeAction('Entry answer passed on',
              partner: backEntry);
        }
        var adopted = 0;
        for (final r in c.records) {
          if (onEntryLearned?.call(r, fromPartner) ?? false) adopted++;
        }
        // THE LOCK OF THE SET REQUEST (S376, P4-3): it hangs on the
        // ANSWER, not on its content. Until S376 it hung in
        // `V41Node._learnEntry` and thus on a taken-over
        // record — an empty answer, one with only already
        // known records or one with the own record
        // did not release it.
        //
        // ONLY FOR THE ZERO IDENTIFIER (P4-1): an answer to a
        // DIRECTED request is no answer to the set request.
        // That an unsolicited `announceOwnEntry` of a partner also releases the
        // lock is harmless and costs NO frame —
        // `requestEntrySet` falls only every
        // `entrySetEverySlots` slots anyway.
        if (c.requestId == null || isUnsolicited(c.requestId!)) {
          onEntryResponse?.call();
        }
        return NodeAction('Entry data learned: $adopted '
            '(${c.records.length} received)');
      case SecureOp.peerAnnounce:
        var fresh = 0;
        for (final pos in c.tags) {
          if (onPeerLearned?.call(pos) ?? false) fresh++;
        }
        return NodeAction('$fresh new nodes learned');
      default:
        return NodeAction('unknown control frame');
    }
  }

  /// Assigns an incoming frame stream and acts accordingly.
  List<NodeAction> receive(int fromPartner, Uint8List inner) {
    final out = <NodeAction>[];
    for (final cell in partners[fromPartner].classify(inner, epochNow())) {
      switch (cell.role) {
        case CellRole.forward:
          final next = partnerFor(cell.nextHop!);
          if (next == null) {
            // ── AM I MYSELF THE NEXT HOP? (S354) ─────────────────────
            //
            // `r1 == r2` is no special case, but in small networks
            // the normal case: the sender's slot plan chooses r1
            // (invariant 4), the recipient names r2 in its liveness
            // (§6), and both choices know nothing of each other. If the
            // recipient has only one partner and the sender too, it is
            // the same node.
            //
            // `classify` tries in order and stops at the
            // first matching role — as r1 it hits, as r2 it is
            // no longer checked at all. The cell would silently fall to the
            // floor here, and under a message ("kein Weg zum
            // naechsten Hop") that looks like a routing problem,
            // although the path lies in the same process.
            //
            // NO TRIAL AT RANDOM: only if the identifier is the
            // OWN position. Trying every unknown identifier
            // would mean feeding the pass budget of the path-block resolver to foreign
            // cells (`resetScanBudget`, S353).
            //
            // WHAT IT COSTS, said openly: for this one cell
            // a single node sees the sender AND the handle of the
            // recipient — the two-egress situation of §7.3, collapsed onto one hop.
            // That is a property of small networks,
            // not of these lines: without them the message would not arrive at all,
            // and the node would see exactly the same.
            RelayReject? selfDeclined;
            if (ownPosition != null && _amTarget(cell.nextHop!)) {
              final self =
                  partners[fromPartner].redeemLocally(cell.body, epochNow());
              if (self.ok != null) {
                final to = partnerFor(self.ok!.handle);
                if (to == null) {
                  out.add(NodeAction('no path to the recipient',
                      detail: 'r1=r2, Handle '
                          '${tagLabel(self.ok!.handle)}'));
                  break;
                }
                partners[to].emit(self.ok!.message);
                onRelay?.call(self.ok!.message.length);
                out.add(
                    NodeAction('ausgeliefert', partner: to, detail: 'r1=r2'));
                break;
              }
              selfDeclined = self.reject;
            }
            // WHY IT DID NOT GO ON, in the diagnosis column. Without it
            // two completely different situations are indistinguishable: "I
            // do not know this node" and "I AM this node, but could
            // not redeem the path block". The first is topology,
            // the second a key or epoch error.
            out.add(NodeAction('no path to the next hop',
                detail: 'Hop ${tagLabel(cell.nextHop!)}'
                    '${ownPosition != null && _amTarget(cell.nextHop!) ? ', das bin ich selbst, '
                        'Einloesung ${selfDeclined?.name ?? "ohne Grund"}' : ''}'));
            break;
          }
          // IMMEDIATELY onward, not on the own cadence (§7).
          partners[next].emit(cell.body);
          onRelay?.call(cell.body.length);
          out.add(NodeAction('weitergereicht', partner: next));
        case CellRole.deliver:
          // r2 HAS REDEEMED THE PATH BLOCK — and thus holds B's handle
          // in its hand. Until S349 the cell ended here: it was
          // REPORTED as `ausgeliefert` and nothing was delivered. The lab test
          // even wrote that down as target behaviour
          // (`smoke_v41_lab`: "r2TOb.sent == 0").
          //
          // WHAT r2 LEARNS IN THE PROCESS, and why that is no new limit: the
          // handle is B's position, and r2 knows it anyway — B built the
          // path block under the link key B<->r2, so r2 is
          // by construction B's partner (§7). r2 learns nothing here that it
          // would not already know from the session.
          final to = partnerFor(cell.nextHop!);
          if (to == null) {
            // No path to this handle. Silently — a message to the
            // predecessor would be the information "B is no longer here" (E-83).
            out.add(NodeAction('no path to the recipient'));
            break;
          }
          partners[to].emit(cell.body);
          onRelay?.call(cell.body.length);
          out.add(NodeAction('ausgeliefert', partner: to));
        case CellRole.mine:
          // The body goes upward. Whether there is anything in it that belongs to this
          // node is decided by the layer with the keys.
          onInbound?.call(fromPartner, cell.body);
          out.add(NodeAction('for me or unknown'));
        case CellRole.unknown:
          out.add(NodeAction('abgewiesen: ${cell.reject}'));
        case CellRole.control:
          // A FRAME MUST NOT TEAR DOWN THE NODE. `receive` runs from
          // a stream callback; a throw from here leaves it and
          // reaches the daemon's zone handler — the same class that
          // led to `exit(99)` in S348 as B-14. On 28.08. it hit the
          // phone 54 times (B-29). The error must be fixed, catching
          // does not replace that — it only limits the damage to the one
          // cell that triggered it.
          try {
            out.add(_handleControl(fromPartner, cell.control!));
          } catch (e) {
            controlFailures++;
            lastControlFailure = '$e (op ${cell.control!.op})';
            out.add(NodeAction('Control frame failed: $e'));
          }
        case CellRole.bulk:
          // The same latch as for the control frame and for the same
          // reason: `receive` runs from a stream callback, a throw
          // from here reaches the daemon's zone handler.
          try {
            out.add(_handleBulk(fromPartner, cell.bulk!));
          } catch (e) {
            controlFailures++;
            lastControlFailure = '$e (bulk-op ${cell.bulk!.op})';
            out.add(NodeAction('Bulk frame failed: $e'));
          }
      }
    }
    return out;
  }
}
