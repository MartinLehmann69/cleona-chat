import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/sync/partition.dart';

/// The readiness state (§22.7).
///
/// **Proofs, not acquaintances.** A counter counts whom one knows;
/// readiness counts who has already stored something for one.
/// The difference is the whole point: a routing table full of
/// positions says nothing about whether a message can be placed,
/// and a display element that infers deliverability from a number of neighbours
/// promises something no one has checked.
enum Readiness {
  /// Zero confirmed relays. Nothing can be placed; the
  /// entry cascade runs (§11).
  searching,

  /// Exactly one. A send attempt is possible — Speed can forward via one
  /// relay —, but Secure needs m = 3 families and cannot
  /// place with one relay.
  connecting,

  /// Two or more, independent. Placing with redundancy is possible,
  /// both modes work.
  ready,
}

/// Keeps book of which relays have CONFIRMED storing.
///
/// WHY A REJECTION DOES NOT COUNT. A relay with a full quota answers
/// — it has to, otherwise a full relay could not be told apart from a dead
/// one —, but it has just proven that it can NOT store.
/// Only the accepted stored item counts as proof.
///
/// WHY THE CONFIRMATION FALLS WITH THE CONNECTION. A relay that confirmed an
/// hour ago and has been gone since is no longer a proof,
/// but a memory. If the session falls, the proof falls.
final class ReadinessTracker {
  /// Positions of relays that have accepted a stored item.
  final Map<int, String> _verifiedByPartner = <int, String>{};

  /// The network blocks in which the respective relay sits.
  ///
  /// §22.5.1 demands confirmations „from independent relays in different
  /// partitions". What a partition IS was open in the draft — §9.1 had
  /// even explicitly abolished the term from V4.0. Resolved as
  /// network block (`partition.dart`): two confirmations from the same `/24`
  /// are ONE, because they can come from one hand.
  final Map<int, Set<String>> _partitionsByPartner = <int, Set<String>>{};

  /// Proofs from relays that are NOT a session of this node.
  ///
  /// ── WHY THIS SECOND SET IS NEEDED (S357) ────────────────────
  ///
  /// Since the storing receipt finds its way home over several hops,
  /// proofs arrive from relays to which this node has no connection
  /// at all. §22.7 bases readiness on „evidence, not acquaintance"
  /// — and the proof says „at THIS relay storing is possible". Whether
  /// one happens to be connected to it as well is exactly the
  /// acquaintance that is NOT supposed to matter.
  ///
  /// The session rule above („if the session falls, the proof falls")
  /// stays right, but it is only the freshness check for the case
  /// in which there IS a session. For a relay three hops further there is
  /// no session that could fall — freshness there needs a
  /// clock, and that is in [remoteEvidenceTtl].
  ///
  /// MEASURED WHY THIS CANNOT BE LEFT OUT. In the first
  /// version of S357 only relays that are also partners counted.
  /// `smoke_v41_speed_read_side` thus failed in 2 of 5 runs
  /// (`angenommen, ein Bein — abgelehnt (notReady)`), while the same
  /// test at the state before was green 10 of 10: the node stayed
  /// `searching`, and `searching` blocks the Speed path. A stricter
  /// readiness is not automatically the more correct one.
  final Map<String, ({DateTime since, Set<String> partitions})> _remote =
      <String, ({DateTime since, Set<String> partitions})>{};

  /// How long the proof of a foreign relay stays fresh.
  ///
  /// It is the counterpart of „if the session falls, the proof falls" for
  /// the case without a session. One hour: long enough to bridge the normal
  /// storing cadence (the probe runs at every new session,
  /// liveness at every session change), short enough that a
  /// vanished relay stops counting within an hour.
  /// Deliberately NOT the pair epoch (24 h): reporting „ready" for a whole day
  /// because something lay there once 23 hours ago would be the same
  /// memory-instead-of-proof that §22.7 excludes.
  final Duration remoteEvidenceTtl;

  ReadinessTracker({this.remoteEvidenceTtl = const Duration(hours: 1)});

  /// Takes up the proof of a relay that is not a session of this node.
  ///
  /// [relayPosition] is the position of the STORING relay, not that
  /// of the neighbour over which the receipt came in.
  void observeRemotePlaceAck({
    required Uint8List relayPosition,
    required bool stored,
    required DateTime now,
    Set<String> partitions = const <String>{},
  }) {
    final k = base64.encode(relayPosition);
    if (!stored) {
      // The same rule as for a partner: a rejection is no
      // proof, and it deletes the old one — the relay is just saying that
      // it cannot.
      _remote.remove(k);
      return;
    }
    _remote[k] = (since: now, partitions: partitions);
    _sweepRemote(now);
  }

  /// Throws away expired foreign proofs. Called at every intake and at
  /// every query — this file holds no clock and no timer.
  void _sweepRemote(DateTime now) {
    if (_remote.isEmpty) return;
    _remote.removeWhere((_, v) => now.difference(v.since) > remoteEvidenceTtl);
  }

  /// Takes up a storing confirmation.
  void observePlaceAck({
    required int partner,
    required Uint8List? partnerPosition,
    required bool stored,
    Set<String> partitions = const <String>{},
  }) {
    if (!stored) {
      // No proof — and the old one expires: the relay is just saying that
      // it cannot.
      _verifiedByPartner.remove(partner);
      _partitionsByPartner.remove(partner);
      return;
    }
    _partitionsByPartner[partner] = partitions;
    // Without a checked position the session itself becomes the key. It
    // then cannot be checked for independence — that is why it gets
    // an identifier of its own, session-bound, and counts only once.
    _verifiedByPartner[partner] = partnerPosition == null
        ? 'session/$partner'
        : base64.encode(partnerPosition);
  }

  /// The session is gone — and the list has moved together.
  ///
  /// ── TWO DEFECTS IN ONE LINE (S357) ────────────────────────────
  ///
  /// (1) **This method had no caller.** The contract above
  /// („If the session falls, the proof falls") had stood in the comment since the first
  /// build and was fulfilled by no one; measured with
  /// `grep -rn "forgetPartner" lib/` — one hit, the definition. The
  /// ONLY way a proof expired so far was a REJECTED
  /// place ack. If a relay vanished without a word, its proof stayed,
  /// and `state` never fell back from `ready`: statistics screen green,
  /// Android badge green, system channel posting enabled — on a
  /// node that can no longer place anything.
  ///
  /// (2) **And a mere `remove(partner)` would have been wrong.**
  /// `V41Node._dropPartner` removes the channel from a LIST
  /// (`_channels.removeAt(i)`); all higher indices move down
  /// by one. The proofs however are stored by exactly this index.
  /// Without the moving up, after the first session end every
  /// proof above [partner] carries the name of a FOREIGN partner —
  /// the same class of index shift that `V41Node.adopt` already describes in
  /// its own comment for the incoming cells
  /// („Earlier it was captured at creation — after the
  /// first `_dropPartner` this number pointed to a foreign partner").
  ///
  /// The foreign proofs in [_remote] are NOT affected: they hang on
  /// the position of the relay, not on a session number. Exactly
  /// for that reason they need a clock and no renumbering.
  void forgetPartner(int partner) {
    _verifiedByPartner.remove(partner);
    _partitionsByPartner.remove(partner);
    _moveUp(_verifiedByPartner, partner);
    _moveUp(_partitionsByPartner, partner);
  }

  /// Throws away ALL foreign proofs — the network change (S376, finding 3).
  ///
  /// ── WHY THE CLOCK IS NOT ENOUGH FOR THIS ──────────────────────────────
  ///
  /// [remoteEvidenceTtl] is one hour, and that is soundly justified for running
  /// operation (see there). A NETWORK CHANGE however is
  /// not ageing but a break: the sessions all fall
  /// (`V41Node.onNetworkChanged`), the observed addresses are
  /// forgotten, the inbound proof expires — and the proofs of relays
  /// three hops further would remain as the only ones. They say „at THIS
  /// relay storing is possible", and that was a statement about the
  /// OLD network: the path there led over partners that no longer
  /// exist.
  ///
  /// The effect was measurable and unpleasant: a node with two
  /// foreign proofs stayed on `ready` after the network change with zero partners,
  /// for up to 60 minutes. The display said „ready", the
  /// Speed path was open, and the readiness edge did not fire —
  /// so the draining of the local outbox, which hangs exactly on
  /// this edge, did not run either (§21.2, gap G-4). Afterwards the state fell
  /// back on mere READING through `_sweepRemote`, without
  /// anyone learning about it.
  ///
  /// §22.7.2 („live state governs") leaves no room for that.
  ///
  /// ONLY THE FOREIGN PROOFS. The session proofs are cleared by `forgetPartner` when
  /// dropping every single session — with the moving up of the
  /// indices, which is not needed here because foreign proofs hang on the position
  /// of the relay and not on a session number.
  void forgetRemote() => _remote.clear();

  static void _moveUp<V>(Map<int, V> m, int removed) {
    final higher = m.keys.where((k) => k > removed).toList()..sort();
    for (final k in higher) {
      m[k - 1] = m.remove(k) as V;
    }
  }

  /// How many INDEPENDENT relays have confirmed.
  ///
  /// Counted are different positions, not sessions: two
  /// connections to the same node are one relay, not a redundancy pair.
  int get verifiedRelays => verifiedRelaysAt(DateTime.now().toUtc());

  /// Like [verifiedRelays], but with handed-in time — so that the
  /// expiry of the foreign proofs is testable without waiting.
  int verifiedRelaysAt(DateTime now) {
    _sweepRemote(now);
    // First unique per node — two sessions to the same one are one relay.
    final proNode = <String, int>{};
    _verifiedByPartner.forEach((partner, identifier) {
      proNode.putIfAbsent(identifier, () => partner);
    });

    // Then the independence. Since S357 the calculation stands ONCE, in
    // `Partition.independentCount` — the delivery state needs the same
    // (§22.5.1), and two copies would be two places at which the notion
    // „independent" can diverge.
    final proRelay = <Set<String>>[
      for (final partner in proNode.values)
        _partitionsByPartner[partner] ?? const <String>{},
    ];
    var n = Partition.independentCount(proRelay);
    // Then the same independence check for the foreign proofs. A
    // relay to which a session exists at the same time is already
    // counted — that is why it drops out here.
    final alreadyCounted = _verifiedByPartner.values.toSet();
    final foreign = <Set<String>>[
      for (final e in _remote.entries)
        if (!alreadyCounted.contains(e.key)) e.value.partitions,
    ];
    // Compute together, not add separately: a foreign relay in the
    // same network block as a partner is no second hand.
    n = Partition.independentCount([...proRelay, ...foreign]);
    return n;
  }

  /// WHY `ready` DEMANDS TWO, NOT ONE (§22.7, taken over from `PartnerPolicy`
  /// — S372, E-4). With only two held sync partners
  /// every connection drop throws [n] immediately from 2 to 1 and thus
  /// readiness immediately from `ready` to `connecting` — exactly the case
  /// below. That was the reason for the lower bound of three partners in
  /// `PartnerPolicy` (hysteresis against exactly this flicker); the number
  /// itself had no reader in the tree apart from a test and is removed,
  /// the reasoning belongs here, where it actually applies.
  Readiness get state {
    final n = verifiedRelays;
    if (n == 0) return Readiness.searching;
    if (n == 1) return Readiness.connecting;
    return Readiness.ready;
  }

  /// Only for display and tests.
  Set<String> get verifiedPositions =>
      {..._verifiedByPartner.values, ..._remote.keys};

  /// Only the proofs from SESSIONS — for tests that must distinguish between both
  /// sources.
  Set<String> get sessionPositions => _verifiedByPartner.values.toSet();

  /// Only the foreign proofs.
  Set<String> get remotePositions => _remote.keys.toSet();
}
