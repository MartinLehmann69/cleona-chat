import 'secure_mode.dart' show kManagementKeepEpochs;

/// Up to where the harvest has **sampled** the epoch axis — the clock on
/// which deadlines for opening material hang (E5, S363).
///
/// ══════════════════════════════════════════════════════════════════════
/// THE FINDING THAT MAKES THIS CLASS NECESSARY
/// ══════════════════════════════════════════════════════════════════════
///
/// `PrekeyPool` discarded unused `sk_i` by WALL-CLOCK TIME — in
/// [PrekeyPool.sweep] and, more seriously, already in
/// [PrekeyPool.loadJson], i.e. **at start and before the first harvest**.
///
/// The consequence, measured against the constants of this branch: a
/// management cell rests with the responsible relay for
/// [kManagementKeepEpochs] = 31 epochs (`secure_mode.dart:597`,
/// `kEpochSeconds` = 86 400). A device that was off for 31 days throws away on
/// startup every prekey older than
/// [PrekeyPool.retention] = 15 days — **before** the catch-up harvest has
/// fetched the corresponding cells at all. The cell still rests, it
/// is delivered, and the recipient can no longer open it. The
/// 31-day class is thus really a 15-day class on the opener's side
/// (S363 proposal, section 3.3).
///
/// And the loss is SILENT: a cell whose selector hits nothing
/// counts as `MessageOpener.unresolvedSelectors` and cannot be told apart from a
/// foreign cover cell.
///
/// ══════════════════════════════════════════════════════════════════════
/// THE RULE
/// ══════════════════════════════════════════════════════════════════════
///
/// A secret that arose at time `born` falls only when
/// the harvest has **sampled once** the epochs up to `born + deadline`.
/// Not when `born + deadline` has passed on the wall clock.
///
/// This is measured by [sampledUntil]: the time up to which ALL
/// epochs were queried. In continuous operation that is `now` (every
/// harvest run covers the current epoch, `V41Node.harvestTick`), and
/// then this class behaves **exactly like the wall clock** — E5 costs
/// nothing in the normal case. After an absence the horizon stands
/// where the node stopped, and only advances when the catch-up harvest
/// has closed the gap.
///
/// ══════════════════════════════════════════════════════════════════════
/// WHY THIS MARK AND NOT `V41Node._lastHarvestRun`
/// ══════════════════════════════════════════════════════════════════════
///
/// Re-measured on 03.09.2026 (`v41_node.dart:3575-3581`): that field is
/// **only in memory** and says so itself ("ONLY IN MEMORY, and that is
/// a reported limit"). After a restart it holds `null` — exactly
/// in the only case that matters, the value is not there.
///
/// Two quantities that must not be confused:
///
///   * `_lastHarvestRun` measures when this PROCESS last
///     harvested. It advances on EVERY run, even in the middle of a running
///     catch-up — it must, otherwise `catchUpHarvest` would find an absence again at every
///     network edge and reset the pointer to the
///     start (the catch-up would never finish).
///   * [sampledUntil] measures up to where the EPOCH AXIS has been queried.
///     It explicitly does NOT advance during an open catch-up,
///     because then the gap is still open.
///
/// Therefore it is a quantity of its own and not the same field with a
/// second reader.
///
/// ══════════════════════════════════════════════════════════════════════
/// WHERE IT LIES
/// ══════════════════════════════════════════════════════════════════════
///
/// It travels in the store of the one-time prekeys
/// (`V41Host.exportPrekeyState`, since S372 in the area `v41_prekeys` of the
/// store — before `v41_prekeys.json`) — not because that would be convenient,
/// but because it must be read together with EXACTLY THE object
/// whose deadline it carries. Two separate carriers could
/// diverge: a loaded supply without its horizon would fall back to
/// the wall clock, and the finding would be back.
///
/// It carries NO secrets — only a timestamp. It nevertheless lies
/// encrypted, because the file in which it travels does.
final class HarvestHorizon {
  /// The operational case: the horizon is kept by the harvest.
  HarvestHorizon() : _wallClock = false;

  /// The fallback: there is no harvest that keeps this horizon, so
  /// the wall clock applies as before S363.
  ///
  /// **Only for callers without a node** — tests that build a `PrekeyPool`
  /// alone. In operation it is wrong, and `V41Host` therefore passes
  /// its own through. That the production path really holds a
  /// kept horizon is measured by
  /// `test/smoke/smoke_harvest_horizon.dart` — a fallback that silently
  /// creeps in would be the same silent loss as before.
  HarvestHorizon.wallClock() : _wallClock = true;

  final bool _wallClock;

  // HERE STOOD `istWanduhr` — a getter that only said which of the
  // two constructions was present. It had ZERO readers in `lib/`; only the
  // guard asked it, and a test is no consumer
  // (`smoke_delivery_layer_unwalked_guard`, S363). The statement it
  // was meant to support — "the production path holds no fallback" —
  // is now measured by BEHAVIOUR: a kept horizon accepts
  // [runCompleted], a wall-clock fallback stays `null` afterwards.
  // That is the same statement, measured instead of claimed.

  DateTime? _sampledUntil;

  /// Up to where all epochs have been queried. `null` = never harvested yet.
  DateTime? get sampledUntil => _sampledUntil;

  bool _dirty = false;

  /// Whether the horizon has moved **noticeably** since the last save.
  ///
  /// NOTICEABLY MEANS [saveThreshold]. Without this threshold the
  /// store of the one-time prekeys would be dirty on every harvest run (every 32 s)
  /// and `v41_attach.dart` would rewrite `v41_prekeys.json` every 30 s,
  /// permanently, without a single key having changed.
  ///
  /// Why one hour is without consequence, computed: a horizon outdated by up to
  /// [saveThreshold] makes `catchUpHarvest` measure an
  /// absence of `3600 / 86 400` epochs — that is 0, and
  /// `catchUpHarvest` returns at `< 1` epoch without a single tag.
  /// For the expiry 1 h against [PrekeyPool.retention]
  /// = 15 d is likewise without consequence.
  bool get dirty => _dirty;

  /// From which advance the store must be rewritten.
  static const Duration saveThreshold = Duration(hours: 1);

  DateTime? _securedOn;

  /// Reports that the horizon was written with the store.
  void markSecured() {
    _dirty = false;
    _securedOn = _sampledUntil;
  }

  void _set(DateTime now) {
    final old = _sampledUntil;
    // NEVER BACKWARDS. A clock that jumps (time zone, NTP, a
    // test caller with an old `now`) must not cancel an already reached
    // sampling state — otherwise a long
    // expired prekey would come back to life.
    if (old != null && !now.isAfter(old)) return;
    _sampledUntil = now;
    final g = _securedOn;
    if (g == null || now.difference(g) >= saveThreshold) {
      _dirty = true;
    }
  }

  /// A harvest run is through.
  ///
  /// [catchUpOpen] is the whole decision: as long as a
  /// catch-up is running, the epoch axis between the old horizon
  /// and now is precisely NOT sampled, and the horizon stays put.
  /// Whoever fixed this parameter to `false` would rebuild the wall clock
  /// — that is the guard's reverse probe.
  void runCompleted(
      {required DateTime now, required bool catchUpOpen}) {
    if (_wallClock) return;
    if (catchUpOpen) return;
    _set(now);
  }

  // HERE STOOD `nachholungAbgeschlossen({jetzt})` — a second input
  // that let the horizon jump on completion of a catch-up. It
  // had ZERO callers in `lib/` and was superfluous, not only
  // unused: `V41Node._catchUpComplete` sets `_catchUpUntil` to 0,
  // and AFTER that the same harvest run calls [runCompleted] with
  // `nachholungOpen: false` — the horizon thus jumps in the same run,
  // via the one input that exists. Two inputs for the same
  // transition are two places where one can be forgotten
  // (`smoke_delivery_layer_unwalked_guard`, S363).

  /// The outermost deferral relative to the wall clock.
  ///
  /// WITHOUT IT THE SUPPLY GROWS WITHOUT LIMIT. A node that never harvests
  /// (no network, no partner) would have a horizon that never advances,
  /// and `sweep` would never throw anything away — the same class of error that
  /// `PrekeyPool.loadJson` already warns about ("otherwise a restart would have
  /// reset the deadline and the supply would grow beyond any limit").
  ///
  /// THE NUMBER IS DERIVED, not picked: a cell that was sealed against
  /// this prekey can rest with the relay for at most
  /// [kManagementKeepEpochs] epochs (`SecureStore`
  /// throws it away afterwards, `V41Node.harvestTick`). Sealing against it
  /// was allowed until `born + deadline`. After that no openable
  /// cell can point to it anymore, and keeping it longer buys nothing —
  /// it would only cancel forward secrecy.
  static const Duration capViaDeadline =
      Duration(days: kManagementKeepEpochs);

  /// May a secret that arose at time [born] fall?
  ///
  /// Three cases, in this order:
  ///
  ///   1. The cap is reached → yes, regardless of the horizon.
  ///   2. It has never harvested yet ([sampledUntil] `null`) → no.
  ///      A node that has not sampled anything yet knows nothing
  ///      about what rests for it.
  ///   3. Otherwise: yes, if the horizon is beyond `born + deadline`.
  bool mayTraps(
      {required DateTime born,
      required DateTime now,
      required Duration deadline}) {
    if (_wallClock) return now.difference(born) > deadline;
    if (now.difference(born) > deadline + capViaDeadline) return true;
    final h = _sampledUntil;
    if (h == null) return false;
    return h.difference(born) > deadline;
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        if (_sampledUntil != null)
          'bis': _sampledUntil!.millisecondsSinceEpoch,
      };

  /// Loads what [toJson] delivered. Unreadable content is silently skipped
  /// — then "never harvested yet" applies, and that is the cautious side:
  /// nothing is thrown away that could still be needed.
  ///
  /// ONLY RAISE, never lower — for the same reason as [_set].
  void loadJson(Map<String, Object?> j) {
    if (_wallClock) return;
    if (j['v'] != 1) return;
    final b = j['bis'];
    if (b is! int) return;
    final t = DateTime.fromMillisecondsSinceEpoch(b, isUtc: true);
    final old = _sampledUntil;
    if (old != null && !t.isAfter(old)) return;
    _sampledUntil = t;
    // FRESHLY LOADED IS NOT DIRTY — otherwise the first tick
    // after start would write the same file back once more (the same rule
    // as in `V41Host.importPrekeyState`).
    _dirty = false;
    _securedOn = t;
  }
}
