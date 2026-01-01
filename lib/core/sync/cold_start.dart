import 'dart:async';

import 'entry_record.dart';
import 'partition.dart';

/// Where a node gets its first entry point from.
///
/// The order is the decision (§11.3, 2026-08-22): **all three**,
/// staggered, and the external source stays.
enum EntrySourceKind {
  /// What was already there — the stored supply (step 1).
  store,

  /// The local network (step 2).
  lan,

  /// A human: ContactSeed via QR, NFC or link.
  ///
  /// The normal way in. A messenger without a contact has nobody
  /// to talk to anyway.
  person,

  /// The network's own doors — reachable nodes with a
  /// minimal public door service. Carries only once the network is large
  /// enough to carry itself (E-52).
  doors,

  /// The external rendezvous. Starting aid as long as the network is young, and
  /// anchor when the others do not carry.
  external,
}

/// A source that can deliver entry records.
///
/// Deliberately narrow: the cascade wants records, nothing else. What a
/// source does for it — a socket, a camera, a foreign service — is
/// its own business.
abstract interface class EntrySource {
  EntrySourceKind get kind;

  /// Is this source usable at all? One that is not is
  /// skipped and counted — not silently ignored.
  bool get available;

  /// Fetches what it has. Empty is a valid answer.
  Future<List<EntryRecord>> fetch();
}

/// What a cold-start run has yielded.
final class ColdStartResult {
  /// Records per source, in the order in which they were asked.
  ///
  /// TWO NUMBERS, NOT ONE. `found` is what the source DELIVERED;
  /// `accepted` is what of it was genuine and fresh. Until S356 only
  /// the first stood here, and the report could thus not distinguish the two situations
  /// that lie furthest apart: "the source
  /// answers, but someone puts nonsense under our tag" and "the source
  /// answers with nothing but valid material". The own smoke test
  /// (`smoke_cold_start`, "delivered and accepted are two numbers")
  /// already named the difference — the data structure did not carry it.
  final List<({EntrySourceKind kind, int found, int accepted})> steps;

  /// How many sources were skipped because they were not there.
  final int skipped;

  /// Everything that came together.
  final List<EntryRecord> records;

  const ColdStartResult(this.steps, this.skipped, this.records);

  bool get anyFound => records.isNotEmpty;

  /// How many DIFFERENT nodes are contained in it.
  ///
  /// WHY THAT IS THE NUMBER THAT COUNTS. A substrate with several relays
  /// returns the same record several times — in the lab run on 30.08.
  /// the external rendezvous delivered **five** lumps for **one**
  /// node (5/7 relays had accepted the placement). Whoever counts records
  /// instead of nodes takes a single reachable neighbour for
  /// five and stops searching. But the cascade is to stop when
  /// it has ENOUGH PATHS, not when it has enough copies of one path.
  int get distinctPositions {
    final seen = <String>{};
    for (final r in records) {
      seen.add(r.lNode.map((b) => b.toRadixString(16)).join(':'));
    }
    return seen.length;
  }
}

/// How many DIFFERENT nodes are contained in [soFar].
///
/// As a free function, so that a caller can base its `enough` on it
/// without counting through the intermediate state itself — exactly the error that
/// `v41_attach` made until S356 (`bisher.length >= 3`).
int distinctPositionsOf(List<EntryRecord> soFar) {
  final seen = <String>{};
  for (final r in soFar) {
    seen.add(r.lNode.map((b) => b.toRadixString(16)).join(':'));
  }
  return seen.length;
}

/// How many INDEPENDENT network blocks the found records cover.
///
/// ── WHAT FOR (S380, 10.09.2026) ────────────────────────────────────
///
/// `distinctPositionsOf` counts NODES. For the question "is that enough to
/// be in the network?" that is the wrong quantity: §22.7.1 ties `ready`
/// to TWO INDEPENDENT relays, and independent per
/// `Partition` means a different network block (`/24`, `/48`) — two nodes in the
/// same WLAN are ONE hand.
///
/// Measured on 10.09.2026 on Node1/Node2 in `192.168.10.0/24`: both
/// found each other via the local segment, both thus held one
/// partner, both stayed at `connecting` and knew nothing outside
/// their block.
int distinctPartitionsOf(List<EntryRecord> soFar) {
  final seen = <String>{};
  for (final r in soFar) {
    for (final a in r.addresses) {
      final p = Partition.of(a.host);
      if (p != null) seen.add(p);
    }
  }
  return seen.length;
}

/// The cascade: asks one after another until it is enough.
///
/// WHY THE ORDER IS AS IT IS. First, what costs nothing and involves
/// nobody — the own supply. Then the local network: also cheap, and
/// it does not leave the segment. Then a human, because that is the
/// normal way into a messenger. Then the doors of the network itself. And
/// last the external rendezvous, the only one that needs a fixed
/// point.
///
/// WHY THE LAST ONE STAYS NEVERTHELESS. A young network has no
/// doors yet, and whoever has only their 24 words reaches neither a
/// neighbour in the segment nor a human. It is starting aid AND anchor.
/// Its price — a fixed point, enumerable by every app owner —
/// is listed as B-24 in the declared limits and is not argued away.
///
/// WHY IT STOPS AT THE FIRST HIT. Every further source costs and
/// reveals something; whoever is already in need not knock anymore.
final class ColdStart {
  /// The sources in the order in which they are asked.
  final List<EntrySource> sources;

  /// How long a single source may take.
  final Duration perSourceTimeout;

  const ColdStart({
    required this.sources,
    this.perSourceTimeout = const Duration(seconds: 20),
  });

  /// The intended order. Whoever hooks in a source sorts
  /// by it — not by convenience.
  static const List<EntrySourceKind> order = [
    EntrySourceKind.store,
    EntrySourceKind.lan,
    EntrySourceKind.person,
    EntrySourceKind.doors,
    EntrySourceKind.external,
  ];

  /// Runs the cascade until [enough] is satisfied or nothing more comes.
  Future<ColdStartResult> run({
    required bool Function(List<EntryRecord> soFar) enough,
  }) async {
    final steps = <({EntrySourceKind kind, int found, int accepted})>[];
    final all = <EntryRecord>[];
    var skipped = 0;

    for (final kind in order) {
      for (final s in sources.where((s) => s.kind == kind)) {
        if (!s.available) {
          skipped++;
          continue;
        }
        List<EntryRecord> got;
        try {
          got = await s.fetch().timeout(perSourceTimeout);
        } on TimeoutException {
          got = const <EntryRecord>[];
        } catch (_) {
          // A source that throws is a source that has nothing.
          got = const <EntryRecord>[];
        }
        // Only genuine and fresh; the check lives in the record itself.
        final now = DateTime.now();
        var accepted = 0;
        for (final r in got) {
          if (r.isAuthentic && r.isFresh(now)) {
            all.add(r);
            accepted++;
          }
        }
        steps.add((kind: kind, found: got.length, accepted: accepted));
        if (enough(all)) {
          return ColdStartResult(steps, skipped, all);
        }
      }
    }
    return ColdStartResult(steps, skipped, all);
  }
}

/// A source that does not exist yet.
///
/// Stands explicitly in the list instead of being absent: a cascade
/// silently missing a step looks like a complete one that
/// found nothing. That is the difference between "nobody there" and
/// "not built", and it belongs in the report.
final class UnbuiltSource implements EntrySource {
  @override
  final EntrySourceKind kind;

  /// What is missing, in one sentence — for the report, not for the user.
  final String missing;

  const UnbuiltSource(this.kind, this.missing);

  @override
  bool get available => false;

  @override
  Future<List<EntryRecord>> fetch() async => const <EntryRecord>[];
}
