/// Link-layer connect state — local, per-target memory of the last
/// successful transport-escalation stage (AP-3a stage 3, E-89;
/// docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4d.13.2 "Zu Posten b und d gehoert dazu";
/// docs/SPEC_MYZEL_NETWORK_DRAFT.md §20 E-89; architecture v4 §2.6a/§4.8).
///
/// **What this is.** V4 §2.6a leaves open what the connect path selects a
/// transport *on* — E-64 already ruled out that the entry record itself
/// could carry it ("a censor would otherwise learn which nodes are
/// 443-capable"), which leaves only **local state on the connecting side**.
/// E-89 is the first place that state gets the five figures E-79 required
/// for the replay buffer: entry key, lifetime, eviction, hit behaviour,
/// persistence.
///
/// - **Entry key: the target address**, as a [String]. The caller composes
///   it from address and port (e.g. `"$address:$port"`); this class does
///   not parse or validate the string, it only uses it as an opaque map
///   key.
/// - **Value: the last successful escalation stage**, as an [int] stage
///   index. The caller is expected to derive it from the ordinal position
///   of the stage it just succeeded at within the §4.8 cascade order
///   (`udpOwnPort, tcpOwnPort, tcp443, icmpKnock`) — e.g. a
///   `TransportStage.index` once that enum exists. This file does not
///   import that enum: it is being built concurrently by another session,
///   and depending on it here would make this module's tests hostage to
///   that session's progress. The `int` contract is documented, not typed,
///   for exactly that reason.
/// - **Lifetime: one hour.**
/// - **Eviction: LRU, hard cap 256.**
/// - **Hit behaviour: the remembered stage is tried first** — see
///   [preferredStage].
/// - **Not persisted.** A restart begins again at `udpOwnPort`, which
///   §4d.7 C already mandates for the cascade run itself: after the last
///   stage (`icmpKnock`) the run ends **without leaving state**, and the
///   next breath starts again at the first one. This class's
///   in-memory-only nature is that same rule applied to the one piece of
///   state that "without leaving state" does *not* cover — the cascade run
///   itself never persists anything, but a *successful* connection was
///   always allowed to leave a hint for the next one, and one hour in
///   memory is that hint, not a contradiction of the no-state-across-runs
///   rule (that clause bounds the *failure*-driven cascade, not a
///   remembered success).
///
/// **What this is explicitly NOT.** This is not an error counter. §2.6a's
/// governing constraint (E-62) is that transport selection must not be
/// driven by a failure tally — "that would rebuild the V3 escalation
/// ladder V4 already rejected". This class records **successes**, never
/// failures, and counts nothing. There is no `recordFailure` method and
/// there must never be one.
///
/// **Structure and cap follow the house precedent `FrameDedupCache`**
/// (`lib/core/node/cleona_node.dart`, class `FrameDedupCache` — **historic:
/// deleted with the CUT of 2026-08-31, measured 2026-09-03**), the same
/// precedent [LinkReplayBuffer] in this directory follows: a
/// [LinkedHashMap] with TTL eviction from the front plus a hard cap.
///
/// **One deliberate difference from that precedent.** [LinkReplayBuffer]
/// (and `FrameDedupCache`) never refresh an entry on a hit, because their
/// job is to detect a repeat within a fixed window — refreshing would
/// silently extend that window and both break the "insertion order ==
/// timestamp order" invariant their O(1) front-eviction relies on *and*
/// weaken the very check they exist to perform. [ConnectState] has the
/// opposite job: [recordSuccess] is called exactly when a **new** success
/// just happened, so the one-hour lifetime is meant to measure "how long
/// ago was the last confirmed success at this target", not "how long ago
/// was the first one ever recorded". Not refreshing would let a target
/// used successfully every ten minutes still fall out of memory after an
/// hour, discarding a hint that is in fact maximally fresh. **Decision:
/// refresh on every [recordSuccess] call, implemented as remove-then-
/// reinsert** — removing the existing entry (if any) before inserting the
/// new one moves it to the back of the [LinkedHashMap], so insertion order
/// still equals timestamp order and the front-eviction sweep stays O(1)
/// amortized. [preferredStage] itself never writes, so a read-only hit
/// never refreshes anything — only a genuine new success does.
library;

import 'dart:collection';

class _Entry {
  final int stageIndex;
  final DateTime lastSuccess;
  _Entry(this.stageIndex, this.lastSuccess);
}

/// Remembers, per target address, the last transport-escalation stage that
/// succeeded — a purely local hint so the next connect attempt tries that
/// stage first instead of re-running the full §4.8 cascade from
/// `udpOwnPort`. See the library docstring above for the full rationale
/// (entry key, lifetime, cap, refresh-on-success, non-persistence, and why
/// this is not an error counter).
class ConnectState {
  /// Hard LRU cap: 256 entries — E-89.
  final int maxSize;

  /// Entry lifetime: one hour — E-89.
  final Duration ttl;

  /// Keyed on the caller-composed target address string. Insertion order
  /// equals timestamp order because [recordSuccess] always removes an
  /// existing entry before reinserting it (see the library docstring for
  /// why a hit-driven refresh is correct here, unlike in the sibling
  /// [LinkReplayBuffer]).
  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();

  ConnectState({
    this.maxSize = 256,
    this.ttl = const Duration(hours: 1),
  });

  void _evictExpired(DateTime now) {
    final cutoff = now.subtract(ttl);
    while (_entries.isNotEmpty &&
        _entries.values.first.lastSuccess.isBefore(cutoff)) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Records that [target] was just reached successfully at escalation
  /// stage [stageIndex] (the caller's ordinal for the §4.8 cascade stage,
  /// e.g. a `TransportStage.index`).
  ///
  /// If [target] already has an entry, it is replaced and its lifetime
  /// restarts from [now] — see the library docstring's "one deliberate
  /// difference" section for why refreshing on a repeated success is
  /// correct here.
  ///
  /// [now] defaults to wall-clock `DateTime.now()`; a caller (in
  /// particular the test below) can inject it to control time without
  /// sleeping.
  void recordSuccess(String target, int stageIndex, {DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    _evictExpired(effectiveNow);

    // Remove first so the reinsertion below moves this key to the back of
    // the map, keeping insertion order == timestamp order for the O(1)
    // front-eviction sweep above.
    _entries.remove(target);
    _entries[target] = _Entry(stageIndex, effectiveNow);

    if (_entries.length > maxSize) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Returns the remembered escalation stage for [target] — "the stage to
  /// try first" — or `null` if there is no live entry (never recorded, or
  /// expired more than [ttl] before [now]).
  ///
  /// This is a read-only lookup: a hit here never refreshes the entry's
  /// lifetime. Only [recordSuccess] does that, by design (see the library
  /// docstring).
  ///
  /// [now] defaults to wall-clock `DateTime.now()`; injectable for tests.
  int? preferredStage(String target, {DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    _evictExpired(effectiveNow);
    return _entries[target]?.stageIndex;
  }

  /// Throws away ALL hints.
  ///
  /// **What for (S376).** A remembered success says "on this rung I got
  /// through to this target". But whether a rung gets through is decided
  /// by the **local** network — the block stands where this node sits,
  /// not at the target. After a network change the hint is therefore a
  /// statement about a location that no longer exists.
  /// `V41Node.onNetworkChanged` clears it away for the same reason for
  /// which the observed addresses, `portMappingConfirmed` and
  /// `externalInboundProven` fall there.
  ///
  /// **No contradiction to E-89.** E-89 fixes key, deadline, eviction,
  /// hit behaviour and non-persistence; about a network change WITHIN a
  /// run it says nothing. This method counts nothing and remembers
  /// nothing — it only forgets, and forgetting is the direction E-62
  /// requires ("no error counter").
  void clear() => _entries.clear();

  /// Current entry count. Test/diagnostic use only.
  int get size => _entries.length;
}
