// The cold-start gate before the routine rotation (§4.5.4, S363).
//
// ── THE FINDING ──────────────────────────────────────────────────────────
//
// `CleonaService.startService()` contains no harvest call. The harvest
// has its own clock (`V41Node.run`, every `harvestEverySlots` = 4 slots
// of 8 s, i.e. ~32 s after the start at the earliest), and the catch-up
// harvest is an explicit no-op at cold start
// (`V41Node.catchUpHarvest`: `if (last == null) { … return 0; }` — the
// clock of the absence lives only in memory).
//
// At the same time `startService()` fired the own rotation IMMEDIATELY:
//
//     identity.discardPreviousKeysIfExpired();
//     if (identity.needsRotation()) { _performKeyRotation(); }
//
// So a device that comes back up after days seals its rotation
// announcement against exactly the contact keys it did NOT keep up to
// date during its absence — although the counterpart's announcements are
// lying at the responsible relay at this moment and could be fetched on
// the first harvest run. A case the management class would have healed
// becomes a lost one again.
//
// And the sharper form, measured on 03.09.2026: `service_daemon.dart`
// calls `await service.startService()` (line 779) and `attachV41(...)`
// (line 790) ONE AFTER THE OTHER. At the time of the rotation call
// `service.v41Delivery` is thus still `null`, and the switch in
// `sendToUser` (`if (v41 != null && v41HostRef != null)`) falls through to
// the end of the method — there, for everything V4.1 does not carry,
// stands a `_log.error(... Nicht gesendet.)`. Whether the announcement has
// a carrier at all today depends solely on whether the ML-KEM generation
// in the isolate takes longer than the ten lines up to `attachV41`. That
// is a race, not an order.
//
// ── WHAT THIS GATE DOES AND WHAT NOT ────────────────────────────────────
//
// It reverses the order: first harvest, then announce. It does NOT cancel
// the rotation — a rotation that never takes place would be the worse
// error (§4.5.4 ties forward secrecy level 3 to the 7-day clock). Hence
// the [fallbackPeriod]: a node that does not manage a single harvest run
// in this time has not reached a responsible relay — then the
// announcement cannot be delivered anyway, and waiting buys nothing more,
// but costs the key hygiene.
//
// ── THE PRICE, CALCULATED ────────────────────────────────────────────────
//
// At COLD START: zero. `_performKeyRotation()` is called without `await`
// already today; `startService()` does not wait for it. The gate moves a
// call that runs concurrently anyway.
//
// At the ANNOUNCEMENT: at most one harvest interval, i.e.
// `harvestEverySlots x kSlotInterval` = 4 x 8 s = 32 s, until the first
// run is QUEUED. What is measured is the run, not its answer — the answer
// hangs on the other side and could not be capped without turning the
// gate into a bet.
//
// This file is pure: no clock, no timer, no FFI. Every time is passed in,
// and it can thus be checked without a network.

/// Why the gate opened — the guard's measured quantity.
enum RotationsTorReason {
  /// A harvest run was reported. The regular case.
  harvest,

  /// The [ColdStartRotationsTor.fallbackPeriod] has expired without a
  /// single harvest run coming about.
  fallback,
}

/// Holds ONE deferred cold-start rotation until a harvest has happened.
class ColdStartRotationsTor {
  /// How long to wait at most for the first harvest run.
  ///
  /// One hour. With a harvest run every good 32 s that is around 112
  /// missed opportunities — whoever did not have a single one of them has
  /// no responsible relay, and then the announcement cannot be delivered,
  /// regardless of when it is sealed.
  final Duration fallbackPeriod;

  ColdStartRotationsTor({this.fallbackPeriod = const Duration(hours: 1)});

  DateTime? _sharpSince;
  bool _consumed = false;

  /// Whether a rotation is currently deferred.
  bool get sharp => _sharpSince != null && !_consumed;

  /// Whether the gate has done its one task.
  ///
  /// After that it is DEAD: the later rotations from the 6 h clock run
  /// without a gate. They need none — by then the harvest has been running
  /// for hours.
  bool get consumed => _consumed;

  /// Defers a rotation. Arming it several times changes nothing — the
  /// start time of the [fallbackPeriod] stays the first one.
  void defer(DateTime now) {
    if (_consumed) return;
    _sharpSince ??= now;
  }

  /// Reports a harvest run. Returns the reason if the gate opens with it,
  /// otherwise `null`.
  RotationsTorReason? harvestRun() {
    if (!sharp) return null;
    _consumed = true;
    return RotationsTorReason.harvest;
  }

  /// Checks the fallback period. Returns the reason if the gate opens with
  /// it, otherwise `null`.
  RotationsTorReason? deadlineCheck(DateTime now) {
    final since = _sharpSince;
    if (!sharp || since == null) return null;
    if (now.difference(since) < fallbackPeriod) return null;
    _consumed = true;
    return RotationsTorReason.fallback;
  }

  /// A gate that never deferred counts as used up — otherwise a later
  /// rotation without a cold start would get stuck on it.
  void withoutDeferralConsume() {
    if (_sharpSince == null) _consumed = true;
  }
}
