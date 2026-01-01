// The clock generator — the only place with a clock.
//
// Everything below is clock-free and therefore testable: `tick()` works
// through one slot; when it is due used to be the caller's business. Here
// it is.
//
// TWO THINGS THAT ARE EASY TO GET WRONG.
//
// 1. **No drift.** The next slot is computed against the PLANNED time
//    of the previous one, not against „now". Otherwise every
//    processing time adds to the interval, the cycle becomes systematically
//    slower, and the shared jitter would no longer be shared —
//    a node with much traffic would run measurably more sluggishly than one without.
//    Exactly on that the demand would hang again otherwise.
//
// 2. **The interval is drawn BEFORE the slot**, not after it. It comes
//    from the demand-independent stream anyway, but the order
//    keeps it visible: first plan, then see what rides along.
//
// NO CATCHING UP. If the process stands still (sleep, debugger, doze),
// the missed time is NOT made up. A burst of made-up cells
// would be a spike, and a spike is exactly what the whole
// construction avoids — better a hole in the stream than a peak in it.
library;

import 'dart:async';

import 'package:cleona/core/sync/cover_stream.dart';

import 'delivery_node.dart';

final class SlotDriver {
  final DeliveryNode delivery;

  /// Called after every slot — for statistics and tests.
  final void Function(SlotOutput slot)? onSlot;

  /// Where a failed slot is reported. `null` means: silent —
  /// then the number in [slotsFailed] is the only trace.
  final void Function(String)? log;

  /// Called after every slot, after it has been worked through.
  ///
  /// Separate from [onSlot], because this hook feeds the EGRESS (the
  /// harvest enqueues control frames) and does not merely observe. An
  /// error in it must not stop the cycle — the same rule as for the
  /// slot itself.
  void Function()? onSlotDone;

  Timer? _timer;
  DateTime? _plannedAt;
  int _slots = 0;
  int _skipped = 0;
  int _failed = 0;

  SlotDriver(this.delivery, {this.onSlot, this.log});

  int get slotsEmitted => _slots;

  /// How many slots have elapsed without anything being sent — the
  /// process stood still. They are counted and NOT made up.
  int get slotsSkipped => _skipped;

  /// How many slots have failed on an error. A number > 0 is
  /// a finding, not operational noise: it says that the delivery layer
  /// threw in a slot.
  int get slotsFailed => _failed;

  bool get running => _timer != null;

  void start() {
    if (_timer != null) return;
    _plannedAt = DateTime.now();
    _schedule();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _plannedAt = null;
  }

  void _schedule() {
    final interval = delivery.egress.stream.drawInterval();
    final planned = _plannedAt!.add(interval);
    _plannedAt = planned;

    var delay = planned.difference(DateTime.now());
    if (delay.isNegative) {
      // The point in time already lies behind us: the process stood still. Do not
      // catch up — count the slot as missed and plan on immediately.
      _skipped++;
      delay = Duration.zero;
    }

    _timer = Timer(delay, () {
      _timer = null;
      // SECOND LINE OF DEFENCE, no substitute for the fix.
      //
      // An error in ONE slot must not kill the node. Until S348
      // it did exactly that: a closed partner made `tick()` throw,
      // the error left this timer callback, reached the
      // zone handler of the daemon and led to `exit(99)` — with all
      // identities, because of a torn connection.
      //
      // The cycle keeps running anyway, and that is the point: a stream
      // that stops at a disturbance would reveal the disturbance
      // (invariant 1). The slot counts as used, the next one is
      // planned, and the error is in the log instead of staying silent.
      SlotOutput? slot;
      try {
        slot = delivery.tick();
      } catch (e) {
        _failed++;
        log?.call('Slot failed ($e) — clock keeps running '
            '($_failed in total)');
      }
      _slots++;
      if (slot != null) onSlot?.call(slot);
      try {
        onSlotDone?.call();
      } catch (e) {
        _failed++;
        log?.call('Post-slot hook failed ($e) — clock keeps '
            'running ($_failed in total)');
      }
      if (_plannedAt != null) _schedule();
    });
  }
}
