// The SECOND outflow (§9.3) — and the place where §5.1 either holds
// or falls.
//
// ── WHY IT MUST EXIST, MEASURED ────────────────────────────────
//
// The blocks of a transfer cannot go through the
// control queue of the cover stream. The numbers:
//
//   5 MB photo           = 6348 blocks (`plannedBlocksFor`)
//   control queue        = `kMaxControlBacklog` 120 frames
//   outflow              = one frame per `kSlotInterval` (8 s)
//
// Queuing 6348 frames into a queue of 120 means silently losing 98.1 %
// (`CoverStream._pushControl` throws away whole groups on overflow).
// And even if they fitted: 6348 slots at 8 s are
// 14.1 hours for one photo. §9.3 therefore gives the lane its own
// outflow with its own rate.
//
// ── AND WHY THIS DOES NOT BREAK §5.1 ──────────────────────────────────
//
// §5.1 invariant 1 says: a real cell SETS ITSELF INTO a slot that is due
// anyway, it does not add one. A second outflow obviously
// adds cells. That would be a breach — if §5.1 applied to
// bulk cells. §9.3 says verbatim that it does not:
//
//   "Like Plane D it is demand-driven and declared (B-29): the §5.1
//    invariants govern the cover stream, which runs on unchanged beside
//    an active transfer; they do **not** govern bulk cells, and no
//    reading of this section may quietly extend them there."
//
// The sentence at the same time sets the CONDITION, and it is the hard one:
// **"the cover stream … runs on unchanged"**. The cover stream must not
// change because of a running transfer — neither its clock
// nor its partner choice nor the content of its cells. This class
// depends on exactly that, and it is built so that it is measurable:
//
//   1. **Own timer, own queue.** This class does not touch
//      `CoverStream` — it calls neither `enqueueControl` nor
//      `takeSlot`, and it touches neither of the two random streams
//      (`_rng` for the slot plan, `_padRng` for the padding). The
//      slot plan is a function of the seed alone; if a transfer runs
//      alongside, it draws the same sequence.
//      `smoke_bulk_lane_effect.dart` measures exactly that: same seed,
//      once with and once without a transfer, identical slot sequence
//      AND identical cell bytes.
//   2. **NO cover cells.** The cover stream sends in every slot,
//      even if nothing is pending — that is its purpose. This outflow
//      sends ONLY when something is pending, and stands still otherwise. That
//      is no oversight: 32 cells/s of permanent fill would be 38.4 KB/s =
//      3.3 GB/day and would be a factor of 130 above the band from §5.3
//      (15-25 MB/day). An outflow that only runs on demand is exactly
//      the "demand-driven" from §9.3 and B-29.
//   3. **It does not exist when nothing is running.** [BulkDrain] starts
//      its timer at the first queued frame and lays it down again when the
//      queue is empty. An observer thus sees exactly
//      what B-29 declares anyway ("start, end, rate and approximate
//      size are visible at both egresses") — and no second
//      permanent rhythm that would mark a node even in the idle state.
//
// ── THE RATE IS A PARAMETER, NOT A MEASUREMENT ────────────────────────
//
// [kBulkRateCellsPerSecond] = 32 stands in appendix A explicitly as
// *proposed — to be measured*, and the document's measurement list keeps it
// as an open duty ("the **device cost of `R_bulk`** at 32 cells/s on
// battery and CPU, with the requirement that the slot cadence must not
// suffer"). It is therefore NOT burned in here but passed through
// — [BulkEgress.rateCellsPerSecond] is a field, and the only value
// anyone in `lib/` puts in for it is the document constant.
// `media_send_estimate.dart` reads the same constant for the time shown
// in the consent dialog; so display and outflow cannot
// diverge without that one constant changing.
//
// ── WHAT DOES NOT LIVE HERE ─────────────────────────────────────────────
//
// The choice of holder (computed by `BulkPlacementPlan`), the seal (done by
// `bulk_block_seal.dart`) and the sending itself. This file
// only knows "a frame body, a partner index, and when it is
// due". [BulkEgress] is clock-free and thus testable; [BulkDrain]
// is the thin shell with the timer, built like `SlotDriver`.
library;

import 'dart:async';
import 'dart:typed_data';

import 'bulk_frames.dart' show kBulkScanRelaysPerRound;
import 'bulk_params.dart' show kBulkRateCellsPerSecond;

/// A frame waiting for its outflow.
final class BulkOutgoing {
  /// Index into the node's partner list — where the frame goes.
  final int partner;

  /// The body of a `0x05` frame (`bulk_frames.dart`).
  final Uint8List body;

  const BulkOutgoing(this.partner, this.body);
}

/// How many frames the outflow holds at most.
///
/// ── WHY IT NEEDS A CAP, AND WHY THIS ONE ─────────────────
///
/// Without a cap a 200 MB video binds 256 000 frames of 1135 B each =
/// 290 MB of RAM, in addition to the object that `FountainEncoder`
/// holds in full anyway. `MediaBulkLane.emit` already draws in batches of
/// [kBulkEmitBatchBlocks] = 512; this cap is the line below that,
/// in case someone builds a second entry point.
///
/// 4096 at [kBulkRateCellsPerSecond] = 32 are exactly 128 seconds of
/// lead and 4.6 MB of memory. More lead would buy nothing: the blocks
/// are drawn as soon as there is room.
///
/// **ON OVERFLOW THE YOUNGEST FALLS, NOT THE OLDEST** — unlike
/// in the control queue, and the difference has a reason. There
/// a waiting frame ages BADLY (it carries a looked-up
/// relay and a have-list from back then, and its identifier drops out of
/// the request book). A fountain block does not age at all: it is
/// equivalent to any other, its holder is in the frame, and the
/// receiver needs ANY k(1+F) blocks, not specific ones. Throwing away the
/// oldest would mean throwing away work that is already half
/// in transit; throwing away the youngest means slowing down the sender —
/// and that is exactly the right answer to a full outflow.
const int kMaxBulkBacklog = 4096;

/// How many places stay reserved for SCANNING.
///
/// ── WHAT FOR (S363) ─────────────────────────────────────────────────────
///
/// This queue carries TWO inflows: the placements of the sending side and
/// the requests of the receiving side (`V41MediaBulkTransport.scan` queues into
/// the same one). Until 03.09.2026 that did not matter — the
/// sending side discarded its surplus anyway, and the queue ran
/// empty after 128 s. Since the pull model the sending side KEEPS it full,
/// for a 200 MB video for over 2.2 h. Without a reserve, every own scan
/// request would be dropped during that whole time, and a sending node
/// could no longer receive anything.
///
/// Two full rounds ([kBulkScanRelaysPerRound] = 4 requests per round).
/// One would be too tight: the next round starts as soon as the previous one
/// has reported its end, and both can briefly wait at the same time.
/// More would buy nothing — the number of open requests is capped by
/// [kBulkScanRelaysPerRound], not by the space.
///
/// **It does not remove the waiting time.** A request behind 4088
/// placements only goes out after ~128 s at `R_bulk` = 32 cells/s. A
/// priority lane for requests would be a second ordering in a deliberately
/// uniform queue and is NOT built on the side — it has been
/// reported.
const int kBulkEgressScanReserve = 2 * kBulkScanRelaysPerRound;

/// The queue of the bulk lane. **Clock-free.**
final class BulkEgress {
  /// `R_bulk` in cells per second. See the file header: a parameter,
  /// not a measurement.
  final int rateCellsPerSecond;

  final int maxBacklog;

  final List<BulkOutgoing> _queue = <BulkOutgoing>[];

  /// How many frames were discarded because the queue was full.
  ///
  /// A number > 0 means: the inflow is larger than [rateCellsPerSecond]
  /// allows. That is a finding at the inflow, not at this queue —
  /// the same reading as `CoverStream.droppedControl`.
  int dropped = 0;

  /// How many frames have gone out in total.
  int emitted = 0;

  BulkEgress({
    this.rateCellsPerSecond = kBulkRateCellsPerSecond,
    this.maxBacklog = kMaxBulkBacklog,
  }) {
    if (rateCellsPerSecond < 1) {
      throw ArgumentError.value(
          rateCellsPerSecond, 'rateCellsPerSecond', 'must be >= 1');
    }
  }

  int get pending => _queue.length;

  bool get isEmpty => _queue.isEmpty;

  /// How many frames still fit in NOW without one falling.
  ///
  /// ── WHAT THIS NUMBER IS FOR (S363) ────────────────────────────────
  ///
  /// It is the reverse direction of [dropped]: whoever reads it before
  /// queuing does not queue too much in the first place. Until 03.09.2026 it
  /// did not exist, and `MediaBulkLane.emit` therefore blindly queued all `N`
  /// planned frames in one synchronous run — at 200 MB
  /// 253 907 frames into a queue of 4096. Measured, 98.4 %
  /// fell BEFORE a single cell left (B-1 in
  /// `docs/v4-redesign/S363-messungen-bulk-und-mobilanteil.md`).
  ///
  /// **It does not make [dropped] superfluous.** The cap stays the
  /// last line for a second entry point that does not ask; a
  /// number > 0 is then the finding against it.
  int get freeSlots {
    final free = maxBacklog - _queue.length;
    return free < 0 ? 0 : free;
  }

  /// The interval between two cells — UNIFORM.
  ///
  /// §9.3: "emitted as uniform 1200 B cells … at the bulk rate `R_bulk`".
  /// No jitter, and that is no oversight: the shared jitter of the
  /// cover stream (§5.2) exists so that real and dummy slots do
  /// not separate on the variance. Here there are no dummy cells from
  /// which anything could separate — there are only real ones, and that they
  /// are there is declared anyway (B-29). Jitter would buy nothing here and
  /// would only smear the rate on which the receiver aligns its
  /// cadence.
  Duration get interval =>
      Duration(microseconds: 1000000 ~/ rateCellsPerSecond);

  /// Queues a frame. Returns `false` if the queue was full.
  bool enqueue(BulkOutgoing item) {
    if (_queue.length >= maxBacklog) {
      dropped++;
      return false;
    }
    _queue.add(item);
    return true;
  }

  // `enqueueAll` STOOD HERE and was removed from `lib/` on 09.09.2026 (S377, W-1)
  // — owner approval, `docs/v4-redesign/S377-VORLAGEN-W1-W2-P12.md`
  // section W-1. It had zero callers in `lib/`, and it CANNOT get
  // one there: the two real queuing places of the media lane
  // (`media_bulk_transport_v41.dart:381-384` and `:500-505`) build the
  // frame per block from holder and partner and read the return value
  // INDIVIDUALLY — a collective function over a list has no place there.
  // Its only caller was in the test (`smoke_medienspur_budget.dart`);
  // the loop now stands where it is needed. [enqueue] is
  // unchanged, and so is the measured behaviour.

  /// Takes the next frame, if there is one.
  BulkOutgoing? take() {
    if (_queue.isEmpty) return null;
    emitted++;
    return _queue.removeAt(0);
  }

  /// Throws everything away — abort of a transfer.
  int clear() {
    final n = _queue.length;
    _queue.clear();
    return n;
  }
}

/// The timer of the second outflow — the only clock of this lane.
///
/// BUILT LIKE `SlotDriver`, with two deliberate differences:
///
///  * **It only runs when something is pending.** `SlotDriver` always ticks,
///    because a skipped slot carries the same information as an
///    additional one. Here the opposite holds: a running transfer
///    IS the event, and hiding it is not the aim at all
///    (B-29). A permanent timer would be 3.3 GB/day of fill traffic.
///  * **No catching up, but no drift either.** The same shape as
///    there: the next time is computed against the PLANNED one of the previous
///    tick. If the process stood still (Doze, sleep), the missed
///    time is not made up in one gush — a burst would be exactly the
///    spike that the uniform rate avoids.
///
/// ── AND IT PULLS (S363, 03.09.2026) ─────────────────────────────
///
/// The third difference, and it is the youngest. Until 03.09.2026
/// this outflow was purely PUSHING: the sender queued everything
/// it had, and what no longer fitted, [BulkEgress] discarded
/// silently. Because `MediaBulkLane.emit` ran synchronously, the timer
/// here could not fire a single time in the meantime — measured, at
/// 200 MB 98.4 % of the planned blocks fell BEFORE a cell left (B-1).
///
/// Since then the direction is reversed: [onRoom] is called as soon as
/// at least [refillAtFreeSlots] places are free again, and the
/// source adds exactly as much as fits. The `FountainEncoder`
/// produces blocks on demand anyway (`fountain_encoder.dart`), so
/// pulling costs no memory: only what also goes out is created.
///
/// **The clock stays here.** [BulkEgress] is and stays clock-free; it
/// only knows how much room it has ([BulkEgress.freeSlots]), and when
/// it is asked is decided by this timer.
final class BulkDrain {
  final BulkEgress egress;

  /// Where a due frame goes. Returns `true` if it
  /// really went out — on `false` the frame counts as lost
  /// (no partner, connection gone) and is NOT resubmitted: the
  /// overshoot factor `F` covers exactly that (§9.3).
  final bool Function(BulkOutgoing item) send;

  /// Where an error is reported. `null` means silent.
  final void Function(String)? log;

  /// Is called as soon as there is room for a whole batch again.
  ///
  /// **This is the pull in the pull model.** Whoever sets it promises to
  /// add at most [BulkEgress.freeSlots] frames in this call —
  /// then none falls. `null` means: purely pushing as before.
  final void Function()? onRoom;

  /// The number of free places at which [onRoom] is called.
  ///
  /// If not given, one eighth of the cap (for 4096 thus 512 — the same
  /// order of magnitude as the batch in which the lane pulls). The number
  /// only decides HOW OFTEN it is asked, not how much goes out: at
  /// `R_bulk` = 32 cells/s one eighth of 4096 is one question every 16 s.
  /// Smaller would be more frequent and cost nothing but calls; larger
  /// would let the queue run empty before it is refilled.
  final int refillAtFreeSlots;

  Timer? _timer;
  DateTime? _plannedAt;
  int _failed = 0;
  int _refills = 0;

  /// THE LATCH AGAINST A SECOND TIMER. [onRoom] queues, and
  /// every queuer may call [kick] — in the middle of a running tick
  /// `_timer` would be `null` there, [kick] would thus set a second
  /// `Timer`, and the old run would schedule a third at the end. The
  /// result would be a multiple of `R_bulk` on the wire, i.e. exactly
  /// the spike that the uniform rate is supposed to avoid.
  bool _inTick = false;

  BulkDrain({
    required this.egress,
    required this.send,
    this.log,
    this.onRoom,
    int? refillAtFreeSlots,
  }) : refillAtFreeSlots =
            refillAtFreeSlots ?? (egress.maxBacklog ~/ 8 < 1 ? 1 : egress.maxBacklog ~/ 8);

  bool get running => _timer != null;

  /// How many outflows have failed with a throw.
  int get failures => _failed;

  /// How often [onRoom] was called (diagnostics).
  int get refills => _refills;

  /// Nudges the outflow. Calling it multiple times is allowed and cheap —
  /// every queuer may do it without knowing whether it is already running.
  void kick() {
    if (_inTick || _timer != null || egress.isEmpty) return;
    _plannedAt = DateTime.now();
    _schedule();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _plannedAt = null;
  }

  void _schedule() {
    final planned = _plannedAt!.add(egress.interval);
    _plannedAt = planned;
    var delay = planned.difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    _timer = Timer(delay, () {
      _timer = null;
      _inTick = true;
      try {
        final item = egress.take();
        if (item != null) {
          // SECOND LINE OF DEFENCE, as in `SlotDriver`: a throw while
          // sending — a closed partner, say — must not kill the outflow,
          // and certainly not kill the daemon as an unhandled
          // Future error (`exit(99)`, S351).
          try {
            send(item);
          } catch (e) {
            _failed++;
            log?.call('Bulk egress failed ($e) — clock keeps running '
                '($_failed in total)');
          }
        }
        // ── PULL, BEFORE THE DECISION ABOUT LAYING DOWN ────
        //
        // The order is essential: if the tick laid itself down on an empty
        // queue BEFORE the source was asked, a
        // transfer would break off after every emptied supply — and nobody
        // would nudge it again, because [kick] comes from queuing, and
        // queuing only happens in response to [onRoom].
        if (onRoom != null && egress.freeSlots >= refillAtFreeSlots) {
          _refills++;
          try {
            onRoom!.call();
          } catch (e) {
            _failed++;
            log?.call('Bulk refill failed ($e) — clock keeps '
                'running ($_failed in total)');
          }
        }
        if (egress.isEmpty) {
          // LAY DOWN INSTEAD OF TICKING ON EMPTY. See the file header: a
          // timer that keeps running without a transfer would be a
          // second permanent rhythm.
          _plannedAt = null;
          return;
        }
        if (_plannedAt != null) _schedule();
      } finally {
        _inTick = false;
      }
    });
  }
}
