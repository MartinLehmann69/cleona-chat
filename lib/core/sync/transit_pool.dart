// The transit pool — the third network storage class (V4 §14.2, E-125).
//
// WHAT IT IS FOR, AND WHAT NOT.
//
// It is **no accessory of the field and no scaling measure**. It
// carries axiom 1 towards the sync partner. The chain, in four steps:
// a sender does not subscribe to the shard of its recipient (§4.2, base 8 =
// 3 inbox epochs + 5 decoys, sigma_B is included with ~5/2^l); the
// sync partner SEES the subscription list (§4.2, §16.6); the shard of a spore is
// READABLE from it (E-73, `field_tag.dart` — the upper 4 B are sigma_B);
// so a node that offers a spore in a shard that its
// own list does not carry would be **deterministically recognisable as its author** —
// not statistically. Without a transit class there is nothing with which authorship
// could be confused, and §4.3's "no partner can tell authorship
// apart from forwarding" collapses.
//
// THE ORDER IN `offer` IS THE SECURITY-RELEVANT PART.
//
// First expiry, then cap, only then duplicate. Not the other way round.
//
// If the duplicate check ran before the cap, a
// **possession oracle** would arise: with a full pool an attacker would get a receipt
// for a spore known to him (because held) and for an unknown one
// a refusal — and could thus query which nodes the random walk
// of a particular spore has visited. He can produce the fill level himself,
// because the pool takes arbitrary non-subscribed spores
// as long as there is space. Therefore the behaviour with a full pool is
// **behaviourally identical**: what is already held is refused too.
//
// WHY REFUSE AND NOT DISPLACE.
//
// Displace-on-accept would discard already ACKNOWLEDGED but not yet
// passed-on spores — the receipt "I have it and am
// delivering it onward" (§5.3) would then be a promise that the node
// breaks in the same breath. Refusal happens **before** any receipt and
// promises nothing. Secondly, displace-on-accept would give a cheap
// pool flush: whoever feeds in 8 MB displaces every crossing honest
// random walk before its hop; with refusal he only blocks new acceptances,
// and material already taken in lives out its dwell time.
//
// §14.2's "eviction runs inside the pool, oldest first" is thus the
// **exit discipline**, not an entry pressure: it says WHICH spore
// goes when an exit is due, and that this never happens by rank and never
// across classes. §14.1 supports this literally: "dwell time
// (10 min), **then** eviction inside the pool oldest first".
//
// THE ONLY EXIT IS THE DWELL EXPIRY.
//
// A passed-on spore stays. §14.2 names exactly one
// exit cause ("Dwell time 10 minutes, **then** discarded"); an
// immediate discard after passing on would be a second one without a spec basis.
// It also has a function: the hop can **fail** (the
// chosen partner refuses or is gone). If "passed on" were the
// exit, the random walk would die at the failed hop. This way it gets
// a re-offer for free — and "fanout exactly 1" therefore counts
// **acknowledged** handovers, not attempts.
//
// Capacity here is ample, not scarce: 8e6 / 590 ~ 13 500 spores;
// even if the ENTIRE carrier traffic quota (50 MB/day) were
// incoming foreign real spores, the occupancy would be ~4.3 %.
// "Refused" is an attack regime, not a permanent state.
//
// I/O-free: this file opens no socket and reads no clock that it
// has not been given.
library;

import 'dart:typed_data';

import 'budget_class.dart';

/// What happens to an offered spore.
enum TransitOutcome {
  /// Newly taken in. Acknowledge, and offer it to **one**
  /// partner at the next breath.
  accepted,

  /// Already held. Acknowledge (possession is present), but do **not**
  /// store anew and do **not** refresh the acceptance time — otherwise
  /// a bounce would extend the dwell time without limit.
  ///
  /// Continues the random walk: the spore is passed on again **exactly once**.
  /// Without that the walk dies — without an origin rule a spore bounces
  /// back to the giver with ~1/k per hop (k = 2-4 partners),
  /// the expected walk length would be ~k hops against ~32 necessary
  /// touches at 10 000 nodes.
  duplicateContinuesWalk,

  /// No space. **Nothing** is acknowledged and nothing stored.
  /// Also applies to an already held spore (possession oracle, above).
  declined,
}

/// An entry in the pool. Carries no payload — the pool decides about
/// acceptance and passing on, it is not the place where spores lie.
final class TransitEntry {
  /// Content hash of the spore (§5.3: the receipt confirms possession "under its
  /// content hash").
  final Uint8List contentHash;

  /// Size in bytes as it counts against the quota.
  final int bytes;

  /// Time of the **first** acceptance. Is not changed by a
  /// duplicate.
  final DateTime acceptedAt;

  /// Has the handover to a further partner been acknowledged?
  ///
  /// Only that uses up the fanout of 1. An unacknowledged attempt
  /// does not count — otherwise a failed hop would have the same
  /// effect as a successful one.
  bool forwardAcknowledged = false;

  /// Counts the re-offers from [duplicateContinuesWalk]. Each allows
  /// exactly one further handover.
  int pendingWalkContinuations = 0;

  TransitEntry(this.contentHash, this.bytes, this.acceptedAt);
}

/// The pool. Hard-capped, neither lends to nor borrows from another class.
final class TransitPool {
  /// §14.2: 10 minutes, then discarded.
  static const Duration defaultDwellTime = Duration(minutes: 10);

  /// Upper bound in bytes. Never exceeded, not even briefly.
  final int capacityBytes;

  /// Dwell time. Injectable so that guards can set it without
  /// waiting ten minutes — the default value is the spec.
  final Duration dwellTime;

  final DateTime Function() _now;

  /// Insertion order is acceptance order: a duplicate does not refresh,
  /// and nothing is re-sorted afterwards. Only thereby is
  /// "oldest first" a look at the start instead of a pass.
  final Map<String, TransitEntry> _entries = <String, TransitEntry>{};

  var _occupancyBytes = 0;

  TransitPool({
    required this.capacityBytes,
    this.dwellTime = defaultDwellTime,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The pool of a node of class [cls] (§14.3.1).
  TransitPool.forClass(
    FieldBudgetClass cls, {
    Duration dwellTime = defaultDwellTime,
    DateTime Function()? now,
  }) : this(
          capacityBytes: transitPoolCapacityBytes(cls),
          dwellTime: dwellTime,
          now: now,
        );

  int get occupancyBytes => _occupancyBytes;
  int get entryCount => _entries.length;

  /// How many entries have exited so far at the dwell expiry.
  ///
  /// §18.6 (E-125) allows exactly that as a metric — occupancy and
  /// expiry discards — and explicitly forbids a **forward counter**:
  /// "occupancy, never a forward count". Occupancy is a
  /// capacity signal and says nothing about authorship.
  var discardedOnExpiry = 0;

  /// Offers a spore. See the header comment on the order.
  TransitOutcome offer(Uint8List contentHash, int bytes) {
    final now = _now();
    _expire(now);

    // Cap BEFORE duplicate — behaviourally identical for held and
    // unknown, otherwise a possession oracle arises.
    if (_occupancyBytes + bytes > capacityBytes) return TransitOutcome.declined;

    final key = _key(contentHash);
    final existing = _entries[key];
    if (existing != null) {
      existing.pendingWalkContinuations++;
      return TransitOutcome.duplicateContinuesWalk;
    }

    _entries[key] = TransitEntry(contentHash, bytes, now);
    _occupancyBytes += bytes;
    return TransitOutcome.accepted;
  }

  /// The entries that are to be offered to a partner at the next breath
  /// — in acceptance order, oldest first.
  ///
  /// Those are the not yet acknowledged ones and those with an open
  /// re-offer. An entry whose handover is acknowledged and which
  /// carries no re-offer no longer appears: its fanout of 1
  /// is used up.
  List<TransitEntry> dueForForwarding() {
    _expire(_now());
    return _entries.values
        .where((e) => !e.forwardAcknowledged || e.pendingWalkContinuations > 0)
        .toList();
  }

  /// Reports that a partner has acknowledged the handover.
  ///
  /// Uses up an open re-offer first, otherwise the original
  /// fanout. Returns whether the entry was still known — an
  /// expired one is no error, only too late.
  bool forwardAcknowledgedFor(Uint8List contentHash) {
    final e = _entries[_key(contentHash)];
    if (e == null) return false;
    if (e.pendingWalkContinuations > 0) {
      e.pendingWalkContinuations--;
    } else {
      e.forwardAcknowledged = true;
    }
    return true;
  }

  /// Does the pool hold this spore?
  ///
  /// Only for guards and the harvest side. **Not** to be used as a pre-check in
  /// [offer] — the order there is intentional.
  bool holds(Uint8List contentHash) => _entries.containsKey(_key(contentHash));

  /// Lets expired entries drop out. Idempotent.
  void expire() => _expire(_now());

  void _expire(DateTime now) {
    // Acceptance order == age, therefore the look at the
    // start suffices until the first not yet expired one. A duplicate
    // does not refresh — exactly that is why the invariant holds.
    while (_entries.isNotEmpty) {
      final first = _entries.values.first;
      if (now.difference(first.acceptedAt) < dwellTime) break;
      _entries.remove(_entries.keys.first);
      _occupancyBytes -= first.bytes;
      discardedOnExpiry++;
    }
  }

  static String _key(Uint8List hash) {
    final sb = StringBuffer();
    for (final b in hash) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
