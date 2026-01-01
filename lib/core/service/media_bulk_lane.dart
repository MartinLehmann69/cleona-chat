// The bulk lane, bound to the application (§9.3, step 1 of the CUT).
//
// ── WHAT LIVES HERE AND WHAT NOT ─────────────────────────────────────
//
// `lib/core/bulk/` computes a bulk transfer completely: key and mark
// (`bulk_keys.dart`), seal per block (`bulk_block_seal.dart`), round-robin
// over the responsible ones (`bulk_placement.dart`), the four control
// messages (`bulk_control.dart`), sender and receiver. But it knows no
// chat, no contact and no network.
//
// This file is the link: it keeps the transfers of ONE identity, draws the
// blocks in batches, hands them down to the transport and takes scanned
// ones back. It sends nothing itself — the four control messages go out
// as ORDINARY messages (§9.3: "rides the delivery layer in the chat's
// mode"), and how that happens only the service knows. That is why it
// gets a callback for it instead of a dependency on `CleonaService` — so
// it can be checked without network, without daemon and without profile
// (`test/smoke/smoke_media_bulk_lane_guard.dart`).
//
// ── FIVE GATES THAT MUST NOT SOFTEN HERE ───────────────
//
//  1. **Exactly one deposit per block.** This file hands the transport a
//     list of blocks, not a multiple of it. `m x R` would be a factor of
//     60 (§9.3).
//  2. **`delivered` flips only on the DECODED receipt.** Not on a
//     placement receipt, not on a relay signal (§9.3, D2). Exactly this
//     defect stood on the cell path in S354 ("every unproven receipt
//     flipped `delivered`").
//  3. **A secure chat does not silently become fast.** The lane choice is
//     made in `chooseMediaLane`; without explicit consent PER TRANSFER
//     nothing goes out at all (§9.3 "Mode coupling", §12).
//  4. **No transfer key from `K_AB`** (31.08.2026). `K_T` is DRAWN per
//     transfer and travels in the offer via the cell path, i.e. under the
//     hybrid of X25519 and ML-KEM-768. Derived from `K_AB`, the media
//     content was the only payload stream without PQ coverage and without
//     forward secrecy (`bulk_keys.dart` explains it,
//     `test/smoke/smoke_bulk_pq_guard.dart` measures it).
//  5. **It is PULLED, not pushed** (S363, 03.09.2026). The lane never
//     queues more blocks than the drain can accept, and tops up when it
//     reports space. Before, [MediaBulkLane.emit] handed over all `N`
//     planned blocks in ONE synchronous run; because the drain's timer
//     cannot fire in the meantime, at 200 MB 98.4 % of the blocks fell
//     before a single cell went out (B-1 in
//     `docs/v4-redesign/S363-messungen-bulk-und-mobilanteil.md`). The
//     `FountainEncoder` produces on demand, so pulling costs no memory —
//     only what also goes out is created.
library;

import 'dart:typed_data';

import 'package:cleona/core/bulk/bulk_codec.dart';
import 'package:cleona/core/bulk/bulk_control.dart';
import 'package:cleona/core/bulk/bulk_keys.dart';
import 'package:cleona/core/bulk/bulk_placement.dart' show BulkHolder;
import 'package:cleona/core/bulk/bulk_receiver.dart';
import 'package:cleona/core/bulk/bulk_sender.dart';
import 'package:cleona/core/codec/erasure_placement.dart';
import 'package:cleona/core/codec/erasure_stripes.dart' show erasureLaneN;
import 'package:cleona/core/fountain/fountain_block.dart' show FountainBlock;
import 'package:cleona/core/service/media_bulk_transport.dart';

/// How many blocks are drawn and handed over at once.
///
/// NOT ALL AT ONCE, and that is a memory question with a number: a 200 MB
/// object is ~205 000 blocks of 1069 B sealed = ~219 MB — in addition to
/// the object that `FountainEncoder` holds whole in memory anyway (open
/// point 5 in `fountain.dart`). A batch of 512 instead binds ~547 KB.
///
/// The CLOCK nevertheless does not live here: `R_bulk` (32 cells/s) is a
/// property of the egress, and whoever built it in here would have two
/// clocks in the program (the same justification as in the header of
/// `bulk_sender.dart`).
const int kBulkEmitBatchBlocks = 512;

/// A transport whose drain has a LIMITED intake.
///
/// ── WHY THIS DOES NOT STAND IN `MediaBulkTransport` ───────────────────
///
/// That interface says what the lane NEEDS from the network — deposit,
/// scan, a sink —, and it says so for EVERY source of the same blocks: the
/// bulk lane today, the stream lane from §17.6 later. An intake limit,
/// however, only a carrier with its own RATE has. `R_bulk` (32 cells/s,
/// appendix A) is a property of `bulk_egress.dart`, not of the lane; a
/// carrier without a rate — a holder in memory, say — takes everything,
/// and for it the question would be pointless.
///
/// Whoever fulfils it promises two things:
///
///  * [placementCapacity] is the number up to which `placeOnce` discards
///    NO block, and
///  * [onPlacementCapacity] is called as soon as there is space again.
///
/// Whoever does NOT fulfil it thereby says "I take everything" — and must
/// then also take everything. It is fulfilled by `V41MediaBulkTransport`.
///
/// It EXTENDS [MediaBulkTransport] instead of standing next to it. Not for
/// convenience: Dart promotes a variable only to a SUBtype of its declared
/// type — if the two stood side by side, every site would have to cast
/// blindly, and a transport could fulfil the capacity without being able
/// to deposit at all.
abstract interface class BulkPlacementCapacity implements MediaBulkTransport {
  /// How many blocks the drain accepts NOW without discarding one.
  int get placementCapacity;

  /// Is called as soon as there is space for a whole batch again.
  set onPlacementCapacity(void Function() sink);
}

/// A transport that can say that a scan round came up EMPTY.
///
/// ── WHY THIS NEEDS A SIGNAL OF ITS OWN (S363) ─────────────────────
///
/// [MediaBulkTransport.onScanned] reports BLOCKS. A round that brought not
/// a single one has nothing to report — and that is exactly the interesting
/// case: there the harvest chain ends (§9.3, "harvested by the recipient
/// on its own cadence"), and there, and only there, a refill request is
/// due. Without this signal the state "the harvest hangs" could be read
/// nowhere in `lib/`; `MediaBulkLane.refillRequestFor` therefore had not a
/// single caller (finding 3.3 in
/// `docs/v4-redesign/S363-VORLAGE-bulk-drahtformat.md`).
///
/// **It is not a clock.** The trigger is the end of a round, i.e. an
/// EVENT; if nothing arrives any more and nobody asks for more, nobody
/// calls any more either. A timer at this place would be the polling that
/// working rule 5 rules out.
abstract interface class BulkScanExhaustion implements MediaBulkTransport {
  /// Is called when a scan round for [tag] brought NOTHING.
  set onScanExhausted(void Function(Uint8List tag) sink);
}

/// How often at most a refill is requested per harvest.
///
/// ── A POLICY, NOT A MEASUREMENT — AND THAT STANDS HERE ON PURPOSE ────
///
/// The PRICE is measured (S363, section 1.5): a refill request in a secure
/// chat is **60 cells / 8.0 min** of egress (120 / 16 min if it is the
/// first message of the day), in speed one cell / 8 s. The ANSWER costs 2
/// to 1271 bulk cells. The number 3, by contrast, is not measured, it is
/// chosen: three attempts cover the case "the answer itself got lost"
/// twice, and if nothing arrives after that, the refill request is not the
/// problem. The cap thus binds the price per harvest to 180 cells.
///
/// It is the SECOND latch. The first is the occasion: a request is only
/// made when a scan round came up empty ([BulkScanExhaustion]) and the
/// harvest still needs something. Without the first even a small cap
/// would be polling; without the second a harvest that keeps coming up
/// empty could ask an unlimited number of times.
const int kBulkRefillMaxRequests = 3;

/// A running send from the application's point of view.
final class BulkSendTicket {
  /// The chat in which it is visible.
  final String conversationId;

  /// The message identifier whose delivery status hangs on it.
  final String messageId;

  final BulkSender sender;

  /// How many deposits the transport has accepted.
  int placementsAccepted = 0;

  /// ── THE COMPLETE BOOKKEEPING OF A SEND (S363) ────────────
  ///
  /// Four numbers, and their sum is always [blocksPlanned]:
  ///
  ///   [placementsAccepted] + [placementsRefused] + [blocksUndrawn]
  ///                        + [blocksRemaining] == [blocksPlanned]
  ///
  /// They stand here because the caller could previously ask only ONE
  /// question — "has anything been deposited at all?" —, and §9.3 permits
  /// `failed` exactly for that ("no volunteer and no holder accepted
  /// anything"). A PARTIAL loss was thus invisible: at 200 MB 98.4 % of the
  /// blocks got lost, and the send reported success (B-1).
  ///
  /// How many blocks the plan requires (`BulkSender.plannedBlocks`, or the
  /// explicit number given to [MediaBulkLane.emit]).
  int blocksPlanned = 0;

  /// How many of them are still to be deposited. > 0 means: the send is
  /// still running and waiting for space in the drain.
  int blocksRemaining = 0;

  /// How many blocks the transport REJECTED.
  ///
  /// Not "discarded because the queue was full" — that can no longer
  /// happen since the pull model. This number counts those for which there
  /// was no responsible holder or no way to it
  /// (`V41MediaBulkTransport.noHolder`). It is real loss and is therefore
  /// COUNTED instead of swallowed.
  int placementsRefused = 0;

  /// How many blocks never came into being in the first place.
  ///
  /// `BulkSender.nextBlocks` may deliver fewer than asked — with
  /// [KeyedSeeds] two indices can yield the same seed (expected value at
  /// 205 000 blocks: 0.005). The case is rare, but it is a shortfall
  /// against the plan and not a rounding.
  int blocksUndrawn = 0;

  /// Did the deposit run through without any shortfall?
  bool get placementLossless =>
      blocksRemaining == 0 && placementsRefused == 0 && blocksUndrawn == 0;

  /// Is the deposit finished — regardless of whether lossless or not?
  bool get placementDone => blocksRemaining == 0;

  /// Whether [MediaBulkLane.onPlacementDone] has already run for this send.
  bool placementReported = false;

  /// Was this send deposited WITHOUT directed placement?
  ///
  /// Only possible with [BulkCodecKind.reedSolomon], and only on a carrier
  /// that does not fulfil [BulkDirectedPlacement]. The round-robin plan is
  /// the same; what is missing is the resubmission for a fragment to whose
  /// holder no way was known. With a stripe encoding that is the difference
  /// between one missing spot and — from the fifth in a stripe — the whole
  /// object, and a refill request does not heal it (O-3). That is why it
  /// stands here and not only in the comment.
  bool placementUndirected = false;

  /// Has the DECODED receipt of this object arrived?
  ///
  /// The ONLY value on which `delivered` may hang (§9.3, D2).
  bool decoded = false;

  BulkSendTicket(this.conversationId, this.messageId, this.sender);

  Uint8List get tag => sender.keys.tag;
}

/// A running harvest from the application's point of view.
final class BulkReceiveTicket {
  final String conversationId;
  final String messageId;

  /// Who sent the offer — hex, 64 digits.
  ///
  /// SEPARATE FROM [conversationId], and that is not a duplicate: in a 1:1
  /// chat both are the same, in a GROUP [conversationId] is the group
  /// identifier and the announcer a single member. The DECODED receipt is
  /// a statement about ONE leg (§9.3, D2) and goes to them, not to the
  /// group. Without this field it would go, in the group case, to an
  /// identifier behind which nobody stands.
  final String announcerHex;

  final BulkReceiver receiver;

  /// How often scanning has already happened. Diagnostics only.
  int scans = 0;

  /// How often a refill has already been requested for this harvest (§9.3
  /// "refill").
  ///
  /// Capped at [kBulkRefillMaxRequests] — the price per refill request is
  /// measured and stands there.
  int refillsRequested = 0;

  BulkReceiveTicket(
      this.conversationId, this.messageId, this.announcerHex, this.receiver);

  Uint8List get tag => receiver.keys.tag;
}

/// What came out at the completion of a harvest.
///
/// THE RECEIPT TRAVELS ALONG HERE, instead of being retrievable
/// separately. It is the ONLY statement that flips `delivered` at the
/// sender (§9.3, D2) — if it were a method of its own, someone could
/// retrieve it without a checked object and thus claim a delivery that
/// never took place. Here it only exists together with the bytes, and
/// `BulkReceiver.take` does not hand those out outside of
/// `BulkVerdict.verified`.
typedef BulkDecodedSink = void Function(
    BulkReceiveTicket ticket, Uint8List object, BulkDecodedReceipt receipt);

/// Keeps the bulk transfers of one identity.
final class MediaBulkLane {
  /// The seam to the network. `null` means: the lane can deposit nothing
  /// and scan nothing — then it is REJECTED, not fallen back to V3.
  MediaBulkTransport? transport;

  /// Is called as soon as an object is complete AND checked against its
  /// content hash (`BulkVerdict.verified`). Only then.
  BulkDecodedSink? onDecoded;

  /// Why the last [beginSend] yielded nothing. Only for the caller's
  /// log — the lane itself does not log (it shall stay checkable without a
  /// daemon).
  String? _lastError;
  String? get lastError => _lastError;

  final Map<String, BulkSendTicket> _sends = <String, BulkSendTicket>{};
  final Map<String, BulkReceiveTicket> _receives = <String, BulkReceiveTicket>{};

  /// Running sends (diagnostics).
  int get activeSends => _sends.length;

  /// Running harvests (diagnostics).
  int get activeReceives => _receives.length;

  /// Attaches the transport's sink. Must be called as soon as [transport]
  /// is set — otherwise a scanned block never arrives.
  void bindTransport(MediaBulkTransport t) {
    transport = t;
    t.onScanned = _sampled;
    // THE PULL IN THE PULL MODEL (S363, gate 5 in the file header). Without
    // this call a send would stay stuck after the first full drain — `emit`
    // only deposits what fits in NOW, and the rest comes only via this.
    if (t is BulkPlacementCapacity) {
      t.onPlacementCapacity = _followUp;
    }
    // THE OCCASION OF THE REFILL REQUEST (§9.3 "refill"). Without this call
    // `refillRequestFor` would still have no caller in `lib/` — the refill
    // request was built and never entered (finding 3.3).
    if (t is BulkScanExhaustion) {
      t.onScanExhausted = _harvestHangs;
    }
  }

  // ── SENDESEITE ─────────────────────────────────────────────────────

  /// Creates a send and returns the offer that precedes it to the
  /// receiver.
  ///
  /// ── ONE PATH, NO LONGER TWO (31.08.2026) ──────────────────────────
  ///
  /// Until today a switch stood here: group -> drawn root,
  /// 1:1 -> `K_T = HKDF(K_AB, "media/<hash>")`. The pairwise branch is
  /// struck (`bulk_keys.dart` justifies it in detail: `K_AB` is pure
  /// X25519, i.e. no PQ protection of the content, no forward secrecy and
  /// a confirmation oracle). The root is now ALWAYS drawn and ALWAYS
  /// travels in the offer; the parameter `kAb` has thus gone away, not
  /// become unused.
  ///
  /// [preview] is the micro preview. **It is no longer truncated, but
  /// omitted if it does not fit.** The cut stood here until today with the
  /// justification "a preview image, not a contract" — only a JPEG cut off
  /// at byte 969 is not a smaller image but broken bytes on which
  /// `Image.memory` fails at the receiver. The caller who wants a preview
  /// builds one that fits in a cell (`cleona_service.dart`); whoever hands
  /// over one that is too large gets none — and the transfer goes ahead
  /// anyway, because the preview really is not a contract.
  ({BulkSendTicket ticket, BulkAnnounce announce})? beginSend({
    required String conversationId,
    required String messageId,
    required Uint8List object,
    Uint8List? preview,
  }) {
    final keys = BulkTransferKeys.fresh();
    final BulkSender sender;
    try {
      // THE CODEC FOLLOWS FROM THE SIZE, and from THE SAME function that the
      // receiver computes on `announce.objectLength`. That is why it does
      // not stand on the wire (§9.3, `mediaCodecFor`).
      sender = BulkSender(
          object: object,
          keys: keys,
          codec: mediaCodecFor(object.length));
    } on ArgumentError catch (e) {
      // `null` INSTEAD OF A THROW, and that is not hiding: the caller is
      // `CleonaService._sendOnBulkLane`, an `async` method. A throw from
      // there would escape as an unhandled future error into the zone of
      // `service_daemon.dart`, and `ArgumentError` is not in its survival
      // allowlist: `exit(99)`. Exactly this chain killed the daemon in S351
      // (`smoke_self_send_v41_guard.dart`).
      //
      // Two cases can trigger it, both from `FountainEncoder`: an EMPTY
      // object and one above 4 GiB - 1 (the object length in the block
      // header is 4 B wide). Via today's path both are unreachable —
      // `chooseMediaLane` catches them beforehand —, and precisely for that
      // reason the latch stands here: a second entry into the bulk lane
      // would otherwise not have it.
      _lastError = '$e';
      return null;
    }
    final ticket = BulkSendTicket(conversationId, messageId, sender);
    _sends[_key(keys.tag)] = ticket;
    final matching = (preview != null &&
            preview.isNotEmpty &&
            preview.length <= kAnnouncePreviewBudgetBytes)
        ? preview
        : null;
    return (ticket: ticket, announce: sender.announce(preview: matching));
  }

  /// Is called as soon as a send has deposited all planned blocks —
  /// lossless or not.
  ///
  /// **THE PLACE AT WHICH A PARTIAL LOSS BECOMES VISIBLE.** In the pull
  /// model [emit] returns as soon as the drain is full; at 200 MB that is
  /// after 4096 of 253 907 blocks. The rest runs on for hours, and nobody
  /// can wait for that — the offer must go out at once, otherwise the
  /// receiver has nothing to scan. The caller therefore learns the result
  /// here, with [BulkSendTicket.placementLossless] and the four counters
  /// next to it.
  void Function(BulkSendTicket ticket)? onPlacementDone;

  /// Plans [blocks] blocks and deposits as much as fits in now.
  ///
  /// Without an argument: as many as the measured overhead requires
  /// (`BulkSender.plannedBlocks`).
  ///
  /// ── IT IS PULLED, NOT PUSHED (S363) ──────────────────────
  ///
  /// Until 03.09.2026 a SYNCHRONOUS loop over all `N` planned blocks stood
  /// here. It was the self-inflicted loss B-1: the drain's timer cannot
  /// fire during a synchronous run, so the queue never emptied, and
  /// `BulkEgress.enqueue` silently discarded everything above
  /// `kMaxBulkBacklog` = 4096. Measured: 5 MB lost 35.5 %, 200 MB lost
  /// 98.4 % — and the caller reported success, because it only checked for
  /// "nothing deposited at all".
  ///
  /// Now this method asks the transport how much it takes, and tops up
  /// exactly that much; the rest is fetched by the drain itself when it has
  /// space ([_followUp], attached in [bindTransport]).
  ///
  /// **Why not simply `await` until everything is deposited?** Because the
  /// offer goes out AFTER this method (`cleona_service.dart`,
  /// `_sendOnBulkLane`). An `emit` that only returns after 2.2 h would
  /// delay the offer by the same time — until then the receiver would not
  /// know that there is anything to scan. The pull model lets the offer
  /// out at once and tops up alongside; that is exactly how §9.3 describes
  /// the flow ("harvested by the recipient on its own cadence").
  ///
  /// Returns how many deposits the transport accepted in THIS attempt —
  /// `0` means "nothing deposited", and §9.3 permits `failed` exactly then:
  /// "no volunteer and no holder accepted anything".
  int emit(BulkSendTicket ticket, {int? blocks}) {
    final planned = blocks ?? ticket.sender.plannedBlocks;
    ticket.blocksPlanned += planned;
    ticket.blocksRemaining += planned;
    ticket.placementReported = false;
    return _deposit(ticket);
  }

  /// Deposits as much as the drain takes NOW.
  int _deposit(BulkSendTicket ticket) {
    final t = transport;
    if (t == null) return 0;
    if (ticket.sender.codec == BulkCodecKind.reedSolomon) {
      if (t is BulkDirectedPlacement) return _depositStripe(ticket, t);
      // ── WITHOUT DIRECTED PLACEMENT: ROUND-ROBIN, BUT BOOKED (S372) ────────
      //
      // The round-robin plan is THE SAME — `BulkPlacementPlan.forBlocks`
      // puts block `i` at holder `i mod R`, and with `N <= R` the `N`
      // fragments of a stripe thus lie on `N` different holders anyway.
      // What is missing is solely the RESUBMISSION for a fragment to whose
      // holder no way was known; that needs a feedback per fragment, and
      // only [BulkDirectedPlacement] gives it.
      //
      // That is why it is not rejected here but booked: rejecting would
      // mean that a media send fails on a carrier that in the normal case
      // (no route failure) would deposit it to the letter. The loss is thus
      // visible ([BulkSendTicket.placementUndirected]) and not silent — what
      // §9.3 requires is visibility, not abstention.
      //
      // The batch stays a multiple of `N`, so that no stripe falls apart
      // across a batch boundary: `BulkPlacementPlan` starts its round-robin
      // at zero again per `placeOnce` call, so half a stripe in the next
      // call would lie on the same holders as the start of the previous one.
      ticket.placementUndirected = true;
      return _depositRoundRobin(ticket, t, multiple: erasureLaneN());
    }
    return _depositRoundRobin(ticket, t);
  }

  /// The round-robin path: draw batches, `placeOnce`, book shortfalls.
  ///
  /// Until S372 this was the body of [_deposit]; pulled out because two
  /// cases need it now (the rateless codec always, the stripe encoding on
  /// a carrier without directed placement).
  ///
  /// [multiple] rounds the batch size down to a multiple — the
  /// justification stands at the only place that sets it.
  int _depositRoundRobin(BulkSendTicket ticket, MediaBulkTransport t,
      {int multiple = 1}) {
    var accepted = 0;
    while (ticket.blocksRemaining > 0) {
      // HOW MUCH FITS? A transport without an intake limit
      // ([BulkPlacementCapacity]) thereby says "I take everything"; then the
      // limit is the rest of the plan, and the flow is the same as before
      // S363.
      final place = t is BulkPlacementCapacity
          ? t.placementCapacity
          : ticket.blocksRemaining;
      if (place <= 0) break;
      var n = ticket.blocksRemaining;
      if (n > kBulkEmitBatchBlocks) n = kBulkEmitBatchBlocks;
      if (n > place) n = place;
      if (multiple > 1) {
        n = (n ~/ multiple) * multiple;
        if (n <= 0) break;
      }
      final stack = ticket.sender.nextBlocks(n);
      if (stack.isEmpty) {
        // NO MORE BLOCK TO DRAW. `nextBlocks` only returns nothing at all
        // when its seed source only yields duplicates any more. The rest of
        // the plan thus never comes into being — that is a shortfall and is
        // booked, not swallowed.
        ticket.blocksUndrawn += ticket.blocksRemaining;
        ticket.blocksRemaining = 0;
        break;
      }
      final ok = t.placeOnce(
          ticket.tag, <Uint8List>[for (final (sealed, _) in stack) sealed]);
      accepted += ok;
      // What the transport did not take is loss (no holder, no way). What
      // was not drawn at all is a second, different shortfall. Both are
      // kept separately, because they have different causes.
      ticket.placementsRefused += stack.length - ok;
      ticket.blocksUndrawn += n - stack.length;
      // `blocksRemaining` drops by the REQUESTED number, not by the
      // delivered one: whoever dropped it by the delivered one would let the
      // loop run forever with a broken seed source.
      ticket.blocksRemaining -= n;
    }
    ticket.placementsAccepted += accepted;
    if (ticket.blocksRemaining == 0 && !ticket.placementReported) {
      ticket.placementReported = true;
      onPlacementDone?.call(ticket);
    }
    return accepted;
  }

  /// Deposits a STRIPE send — per stripe `K` of `N` across different
  /// holders (§9.3, decision E-3 = D).
  ///
  /// ── WHY THIS IS NOT THE SAME MOVE AS ABOVE ──────────────────
  ///
  /// `placeOnce` hands the transport a LIST and gets a NUMBER back. For the
  /// rateless lane that suffices: there every block is equivalent, and `F`
  /// covers the loss. With a stripe encoding it is not — a stripe needs `K`
  /// of its `N` fragments, and the design `N = K + d`
  /// (`codec/erasure_stripes.dart`) only holds as long as the `N` lie on
  /// `N` DIFFERENT holders.
  ///
  /// What would happen today without this branch is measured: `placeOnce`
  /// SILENTLY drops a block for whose holder no next hop is known right
  /// now. Four such spots in a stripe, and the object is irretrievable —
  /// there is no refill request for this lane (O-3, `BulkReceiver.refill`).
  ///
  /// `ErasurePlacementCoordinator` (`codec/erasure_placement.dart`) is
  /// built exactly for this and until S372 had **not a single caller** in
  /// `lib/`. Per owner decision that is a wiring error and not dead code;
  /// here is the wiring.
  ///
  /// ── WHAT THE RECEIPT MEANS HERE, AND WHAT NOT ────────────────
  ///
  /// `runSync` instead of `run`: on this wire there is no placement
  /// receipt (`bulk_frames.dart:BulkOp` knows five actions, none of them
  /// acknowledges). `true` means **handed to this holder**, not **stored by
  /// it**. That is less than `run` requires and still the difference that
  /// matters: the silent loss becomes a resubmission to another holder.
  /// The wire change for the stronger promise is before the owner.
  int _depositStripe(BulkSendTicket ticket, BulkDirectedPlacement t) {
    final capacity = t is BulkPlacementCapacity
        ? t as BulkPlacementCapacity
        : null;
    final n = erasureLaneN();
    var accepted = 0;
    // Which holders have ever accepted anything at all. Kept over the whole
    // send, not per stripe: a holder that has just refused will do so
    // again at the next stripe, and `ErasurePlacementCoordinator` sorts
    // proven ones to the front if one tells it which they are.
    final established = <String>{};
    while (ticket.blocksRemaining > 0) {
      // A WHOLE STRIPE AT ONCE. A half-deposited stripe would be a deposit
      // whose holder distribution nobody has an overview of any more: the
      // round-robin offset of the second part then hangs on the fill level
      // of the drain.
      final place = capacity?.placementCapacity ?? ticket.blocksRemaining;
      if (place < n) break;
      final stack = ticket.sender.nextBlocks(n);
      if (stack.isEmpty) {
        // The set is exhausted. For this lane that is not a defect of a seed
        // source, but the end — `ceil(k/K) * N` blocks and no more.
        ticket.blocksUndrawn += ticket.blocksRemaining;
        ticket.blocksRemaining = 0;
        break;
      }
      // The stripe follows from the seed of the first fragment.
      final stripe = (stack.first.$2 >> 16) & 0xFFFF;
      final holder = t.holdersFor(ticket.tag);
      // THE OFFSET REPRODUCES THE ROUND-ROBIN `i mod R` over the global
      // block index — and with it the measured property on which
      // `N = K + d` rests: with `gcd(N, R) = 1` every stripe touches a
      // DIFFERENT set of holders (measured: 20 different ones in 40 stripes
      // at N=11/R=20, versus 2 at N=10).
      final offset = holder.isEmpty ? 0 : (stripe * n) % holder.length;
      final rotated = holder.isEmpty
          ? holder
          : <BulkHolder>[
              ...holder.sublist(offset),
              ...holder.sublist(0, offset),
            ];
      // Which holders THIS stripe already occupies. A second fragment of the
      // same stripe on the same holder would be exactly the break against
      // which `N = K + d` is calculated: the loss of one holder would then
      // cost two spots instead of one.
      final proven = <String>{};
      final coordinator = ErasurePlacementCoordinator<BulkHolder>(
        totalFragments: stack.length,
        // ALL `N`, not `K`. `K` would only suffice if nothing failed
        // afterwards — but the coverage `N - K = d` is meant precisely for
        // what happens AFTER the deposit.
        requiredFragments: stack.length,
        peerId: (h) => h.id,
        // ONE copy per fragment. A second would be `m x R` on a small scale:
        // redundancy lives in `N`, not in copies (§9.3).
        initialReplicaCount: 1,
        // At most a second attempt per fragment, and only for one that found
        // no way. The cap binds the price of a stripe to 2N cells in the
        // worst case.
        maxCopiesPerFragment: 2,
        maxRetryWaves: 1,
        distinctPeerPerWave: true,
        isPeerConfirmed: (h) => established.contains(h.id),
      );
      final result = coordinator.runSync(
        initialPool: rotated,
        // ONLY UNOCCUPIED HOLDERS ANY MORE. The coordinator by itself only
        // checks whether a holder has already been tried for THIS INDEX;
        // that it must also be new for the STRIPE is known only to the
        // caller, who knows the stripe.
        deeperPool: () => <BulkHolder>[
          for (final h in t.holdersFor(ticket.tag))
            if (!proven.contains(h.id)) h,
        ],
        send: (i, h) {
          proven.add(h.id);
          final ok = t.placeAt(ticket.tag, h, stack[i].$1);
          if (ok) established.add(h.id);
          return ok;
        },
      );
      accepted += result.confirmedCount;
      ticket.placementsRefused += stack.length - result.confirmedCount;
      ticket.blocksRemaining -= stack.length;
      if (ticket.blocksRemaining < 0) ticket.blocksRemaining = 0;
    }
    ticket.placementsAccepted += accepted;
    if (ticket.blocksRemaining == 0 && !ticket.placementReported) {
      ticket.placementReported = true;
      onPlacementDone?.call(ticket);
    }
    return accepted;
  }

  /// The drain has reported space — all running sends top up.
  ///
  /// Over ALL sends, not over one: an identity can send more than one file
  /// at the same time, and they share the same drain. The first in order
  /// fills first; that is not a preference, but the only order there is
  /// here — a weighting would be a second policy next to `R_bulk`.
  void _followUp() {
    if (_sends.isEmpty) return;
    for (final ticket in _sends.values.toList(growable: false)) {
      if (ticket.blocksRemaining > 0) _deposit(ticket);
    }
  }

  /// Answers a refill request with FRESH seeds (§9.3 "refill").
  ///
  /// Not with the old ones: the receiver already had them. Returns how many
  /// deposits were accepted, or `0` if the refill request belongs to no
  /// running send.
  int refill(BulkRefillRequest req) {
    for (final ticket in _sends.values) {
      // ONLY CHECK THE MEMBERSHIP, do not draw any blocks here yet:
      // `BulkSender.refill` would draw `req.wantedBlocks` pieces at once, and
      // with a large object that is up to 253 907 at a time — the same
      // self-inflicted loss as in [emit] before S363. The refill request
      // therefore goes through THE SAME bookkeeping: plan it, and draw what
      // the drain takes.
      if (!FountainBlock.sameObject(req.objectId, ticket.sender.objectId)) {
        continue;
      }
      // ── THE STRIPE LANE STAYS OUTSIDE (S372, O-3) ────────────────
      //
      // Its set has `ceil(k/K) * N` blocks and no more; `emit` would PLAN
      // `req.wantedBlocks`, not be able to draw a single one and book the
      // difference as `blocksUndrawn`. The four numbers of the ticket would
      // afterwards add up to a send that never existed — a bookkeeping that
      // is later read as a finding.
      //
      // The own receiver does not request here at all
      // (`BulkReceiver.refill` returns `wantedBlocks == 0` for this codec,
      // and `_harvestHangs` sends nothing on that). What can reach this
      // branch thus comes from outside — and precisely for that the latch
      // stands here and not only at the own receiver.
      if (ticket.sender.codec == BulkCodecKind.reedSolomon) return 0;
      return emit(ticket, blocks: req.wantedBlocks);
    }
    return 0;
  }

  /// Accepts a DECODED receipt.
  ///
  /// **This is the ONLY place at which a media message may become
  /// `delivered`** (§9.3, D2). A placement receipt does not reach this
  /// method and must not.
  ///
  /// Returns the ticket whose delivery is thereby proven, or `null` if the
  /// receipt fits no running send — then someone has sent a hash that
  /// nobody promised.
  BulkSendTicket? acceptReceipt(BulkDecodedReceipt receipt) {
    for (final ticket in _sends.values) {
      if (!ticket.sender.acceptsReceipt(receipt)) continue;
      ticket.decoded = true;
      return ticket;
    }
    return null;
  }

  /// Forgets a completed or aborted send.
  void endSend(BulkSendTicket ticket) => _sends.remove(_key(ticket.tag));

  // ── EMPFANGSSEITE ──────────────────────────────────────────────────

  /// Creates a harvest from an offer.
  ///
  /// The root stands IN THE OFFER — since 31.08.2026 always, also in the
  /// 1:1 case. The receiver no longer needs a pair key for it; what it
  /// needs is the ability to OPEN the offer, and only the KEX-gated cell
  /// path under X25519 + ML-KEM-768 has that. Exactly there now lies the PQ
  /// coverage of the media content.
  BulkReceiveTicket? beginReceive({
    required String conversationId,
    required String messageId,
    required BulkAnnounce announce,
    String announcerHex = '',
  }) {
    final keys = BulkTransferKeys.fromRoot(announce.transferRoot);
    final ticket = BulkReceiveTicket(
        conversationId,
        messageId,
        announcerHex.isEmpty ? conversationId : announcerHex,
        BulkReceiver.fromAnnounce(announce, keys,
            codec: mediaCodecFor(announce.objectLength)));
    _receives[_key(keys.tag)] = ticket;
    return ticket;
  }

  /// Scans the holders (§9.3: the receiver SCANS, it does not ask).
  ///
  /// The have-list goes along, so that a holder does not send back what is
  /// already there.
  bool scan(BulkReceiveTicket ticket) {
    final t = transport;
    if (t == null) return false;
    ticket.scans++;
    t.scan(ticket.tag, ticket.receiver.haveList);
    return true;
  }

  /// The refill request that the receiver sends back as an ordinary
  /// message when scanning does not yield enough.
  BulkRefillRequest refillRequestFor(BulkReceiveTicket ticket) =>
      ticket.receiver.refill();

  /// Is called when a harvest hangs and a refill must be requested.
  ///
  /// **The caller sends it via the CELL PATH, not via the bulk lane.** §9.3
  /// puts the control flow on the delivery layer ("announce …, request,
  /// refill, DECODED receipt — rides the delivery layer in the chat's
  /// mode"); a refill request on frame type `0x05` would be a fifth opcode
  /// with its own format and without sender binding. That is why it is a
  /// CALLBACK and not a method that sends here itself — this file knows
  /// neither contact nor network.
  void Function(BulkReceiveTicket ticket, BulkRefillRequest request)?
      onHarvestStalled;

  /// A scan round came up empty — here it is decided whether a refill is
  /// requested.
  ///
  /// ── THREE GATES, AND EACH CATCHES SOMETHING DIFFERENT ────────────────
  ///
  ///  1. **Only for a running harvest.** An empty round for a mark that
  ///     nobody harvests any more is no occasion.
  ///  2. **Only if anything is still missing at all.** A complete decoder
  ///     requests nothing, and `BulkReceiver.refill` would then return
  ///     `wantedBlocks == 0` — a message about nothing that would still
  ///     cost 60 cells.
  ///  3. **At most [kBulkRefillMaxRequests] times.** The justification of
  ///     the number stands there.
  ///
  /// What DELIBERATELY does not stand here is a deadline. The trigger is
  /// the end of a round, i.e. an event; a timer next to it would be polling.
  void _harvestHangs(Uint8List tag) {
    final ticket = _receives[_key(tag)];
    if (ticket == null) return;
    if (ticket.receiver.isComplete) return;
    if (ticket.refillsRequested >= kBulkRefillMaxRequests) return;
    final req = ticket.receiver.refill();
    if (req.wantedBlocks <= 0) return;
    ticket.refillsRequested++;
    onHarvestStalled?.call(ticket, req);
  }

  /// The running harvest for a message identifier, or `null`.
  ///
  /// WHAT FOR. The user can also accept a media message by hand (the
  /// self-acceptance only applies by type and size, §3.4.3). On the V3 path
  /// this move sent a MEDIA_REQUEST; on the bulk lane there is nobody who
  /// would have to answer that — the receiver SCANS (§9.3). The action is
  /// thus a scan, and for that the move must find its harvest again.
  BulkReceiveTicket? receiveFor(String messageId) {
    for (final t in _receives.values) {
      if (t.messageId == messageId) return t;
    }
    return null;
  }

  /// Forgets a completed or aborted harvest.
  ///
  /// AND TELLS THE TRANSPORT. It keeps rounds, yield and per holder a hop
  /// counter per mark; without this call a remainder of it would stay
  /// behind after every received file — for a user who receives a lot, a
  /// slow leak. `onTagForgotten` is a callback and not a method of the
  /// interface: `MediaBulkTransport` describes what the lane needs from the
  /// NETWORK, and cleaning up is not part of that.
  void endReceive(BulkReceiveTicket ticket) {
    _receives.remove(_key(ticket.tag));
    onTagForgotten?.call(ticket.tag);
  }

  /// Is called when a mark is no longer needed.
  void Function(Uint8List tag)? onTagForgotten;

  /// What the transport has scanned.
  ///
  /// FOREIGN BLOCKS ARE THE NORMAL CASE, not a protocol violation: a
  /// tagline can carry old and new blocks at the same time during a
  /// version change (`fountain_block.dart`, justification of the 8 B object
  /// identifier). `BulkReceiver` counts them and discards them.
  /// Marks that are currently inside [_sampled].
  ///
  /// ── THE LATCH AGAINST THE OWN CALLBACK ────────────────────────
  ///
  /// [_sampled] requests a further scan at the end, and a transport MAY
  /// serve its sink synchronously out of [MediaBulkTransport.scan] — the
  /// built one does so for the OWN pool, because that can be read without
  /// a single cell. Without this latch `scan -> sink -> scan -> …` would
  /// run into the same frame.
  ///
  /// Measured that it is not a theoretical case: `Stack Overflow` in
  /// `smoke_media_lane_guard.dart` as soon as a scan delivers blocks that
  /// do NOT make the decoder complete (there: an offer with a foreign
  /// content hash). Then the termination condition "complete" is never
  /// reached by construction.
  ///
  /// **It does not replace the damping in the transport.** That one limits
  /// the ROUNDS on the wire; this one limits the STACK DEPTH in the
  /// process. Two different errors, two separate latches.
  final Set<String> _inSample = <String>{};

  void _sampled(Uint8List tag, List<Uint8List> sealed) {
    final ticket = _receives[_key(tag)];
    if (ticket == null) return;
    for (final block in sealed) {
      ticket.receiver.offerSealed(block);
    }
    if (_inSample.contains(_key(tag))) return;
    if (!ticket.receiver.isComplete) {
      // ── THE RECEIVER'S CADENCE (§9.3), AND IT IS NOT POLLING ─
      //
      // §9.3: "harvested by the recipient **on its own cadence**". A scan
      // run addresses four responsible ones and gets at most 32 blocks
      // each — for a 5 MB photo (6348 blocks) that is around 50 runs.
      // Without resubmission it would stay at the first, and the harvest
      // would never get beyond 2 %.
      //
      // **THIS FILE DOES NOT DAMP, IT ONLY ASKS.** It calls again on every
      // inbound as long as the harvest is incomplete; whether a new ROUND
      // comes of it is decided by the transport
      // (`V41MediaBulkTransport.scan`), because only it keeps the rounds.
      // The cut is intentional: the lane knows no holders and no
      // responsibility, so it cannot know "a round is still running" at
      // all. A damping HERE would be a second, half-informed bookkeeping
      // next to the right one.
      //
      // IT IS NEVERTHELESS NOT POLLING: the trigger is an INBOUND, never a
      // clock. If nothing comes any more, nobody asks any more; the
      // transport ends the chain as soon as a round brought nothing. The
      // user can follow up by hand (`receiveFor` + [scan],
      // `cleona_service.dart`).
      //
      // The refill request to the SENDER (§9.3 "refill") is something else
      // and stays with the caller: it goes as an ordinary message via the
      // cell path, not via the bulk lane.
      _inSample.add(_key(tag));
      try {
        scan(ticket);
      } finally {
        _inSample.remove(_key(tag));
      }
      return;
    }
    // FINAL CHECK (§26.6.1 step 5): outside of `verified` no bytes come
    // out, and that is decided by `BulkReceiver`, not this file.
    final take = ticket.receiver.take();
    final obj = take.object;
    final receipt = ticket.receiver.receiptAfter(take);
    if (obj == null || receipt == null) return;
    onDecoded?.call(ticket, obj, receipt);
  }

  static String _key(Uint8List tag) =>
      tag.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
