// The derivation run of V4.2 §13.7 (S413, finding B-1/B-4): which indices
// the identities of these words hold.
//
// There is no directory of one's own identities in the network (§13.7). A
// device set up from the words derives the indices in ascending order and
// asks, for every index, the values of the last 7 days of its recovery
// bundle — one question per index to each holder it reaches: index 0, and
// every index up to one beyond the highest whose bundle, active or not, has
// been found. A holder that holds nothing answers `0x34`; that answer is the
// existence probe. The run reads only (a found bundle stays with its holder:
// the identity created from it looks for it itself, §13.0, D-40).
//
//   * WHEN: at the collection edges of §8.2 and at every card read, together
//     with the search for the first bundle (§13.0) — never on a clock
//     (§5.4). One service of the host asks (the lowest index it carries).
//   * A FIND `active = true` → the identity is created at that index from the
//     words (`restoredFromPhrase`) and started by the host
//     ([CleonaService.onIdentityFound]); `active = false` → the index is noted
//     as deleted and never given again (§4.5.1).
//   * "No further identity" is never concluded automatically: the run stays
//     open until the user ends it; the interface shows how many identities
//     were found and lets the user name an index of their own (§13.2.2).
//
// A deleted identity keeps its place in the run (§13.7 last paragraph): the
// highest living identity of a device lays, with each of its bundles, a
// minimal bundle with `active = false` for every deleted index below it
// ([IdentityRunOps.recoveryDeletedLay]). Bundle format unchanged (D-21).

part of 'cleona_service.dart';

/// The highest index a user may name by hand (§13.7): beyond the identity
/// limit of a user (§20.2) with room for deleted ones.
const int kIdentityRunNameAtMost = 64;

/// §13.7 as a pure function: the indices a pass asks — every index from 0 up
/// to one beyond the highest known one ([carried] or [deleted]) that is
/// neither.
List<int> identityRunAsks({required Set<int> carried, required Set<int> deleted}) {
  var top = -1;
  for (final i in [...carried, ...deleted]) {
    if (i > top) top = i;
  }
  return [
    for (var i = 0; i <= top + 1; i++)
      if (!carried.contains(i) && !deleted.contains(i)) i
  ];
}

/// The opened bundle that counts for [index] (§13.3.2: of several copies the
/// one furthest along the rotation chain, among the same keys the newest;
/// copies whose chains fork give none — `null`, nothing is created). One
/// naming another index is not this index's. A minimal bundle without keys
/// (`active = false`) is weighed by its time only (`recoveryBundleChoose`).
RecoveryBundleContent? identityRunNewest(
        int index, Iterable<RecoveryBundleContent?> opened) =>
    recoveryBundleChoose([
      for (final c in opened)
        if (c != null && c.identityIndex == index) c
    ]).best;

extension IdentityRunOps on CleonaService {
  IdentityManager get _identityMgr => IdentityManager(baseDir: identity.baseDir);

  /// Hangs the run on the collection edges of [p]'s node — once per node (an
  /// edge cannot be taken back; a reopened mailbox on the same node keeps
  /// it). Called by `_recoveryBundleAttach`.
  void _identityRunAttach(mycelium.Mailbox p) {
    final node = p.node;
    if (identical(_identityRunNode, node)) return;
    _identityRunNode = node;
    node.addCollectEdge((only, _) {
      if (!identical(myceliumMailbox?.node, node)) return;
      unawaited(identityRunPass(withWhom: only));
    });
  }

  /// Whether THIS service asks for the host: the one with the lowest index
  /// among the services of the host — one question per index, not one per
  /// identity.
  bool _identityRunAsker(mycelium.Mailbox p) {
    final mine = identity.hdIndex;
    if (mine == null || identity.masterSeed == null) return false;
    for (final s in servicesOnHost(p.host, this)) {
      final i = s.identity.hdIndex;
      if (i != null && i < mine && s.myceliumMailbox != null) return false;
    }
    return true;
  }

  /// One pass of the run: asks every index of [identityRunAsks] at
  /// [withWhom] (else the holders a collection asks), and after a find the
  /// next one at once. Does nothing while the run is closed or another
  /// service asks. Does not throw.
  ///
  /// While a pass runs, an edge is not dropped (§13.7: the run repeats at
  /// the post-box edges): exactly one more pass follows the running one and
  /// asks the holders of every edge that came meanwhile (S413 — before, the
  /// holders of such an edge were never asked until the next edge). Returns
  /// how many indices were found while this call waited: by the pass that
  /// was running and by its own.
  Future<int> identityRunPass({List<(InternetAddress, int)>? withWhom}) async {
    final p = myceliumMailbox;
    final seed = identity.masterSeed;
    if (p == null || seed == null) return 0;
    if (!_identityRunAsker(p)) return 0;
    final mgr = _identityMgr;
    try {
      if (!mgr.identityRunOpen()) return 0;
    } on Object catch (e) {
      _log.warn('Identity run (§13.7): state not readable ($e) — not asked');
      return 0;
    }
    final running = _identityRunRunning;
    if (running != null) {
      final again = _identityRunAgain ??= _IdentityRunAgain(running.then((_) {
        final a = _identityRunAgain!;
        _identityRunAgain = null;
        return identityRunPass(withWhom: a.all ? null : a.holders);
      }));
      if (withWhom == null) {
        again.all = true;
      } else {
        again.holders.addAll(withWhom);
      }
      return await running + await again.result;
    }
    // Cleared before the pass is reported done: the pass that follows it
    // ([_IdentityRunAgain]) starts as a pass of its own.
    final done = Completer<int>();
    _identityRunRunning = done.future;
    var found = 0;
    try {
      found = await _identityRunAsk(p, seed, mgr, withWhom);
    } finally {
      _identityRunRunning = null;
      done.complete(found);
    }
    return found;
  }

  Future<int> _identityRunAsk(mycelium.Mailbox p, Uint8List seed,
      IdentityManager mgr, List<(InternetAddress, int)>? withWhom) async {
    var found = 0;
    try {
      final asked = <int>{};
      while (true) {
        final todo = identityRunAsks(
                carried: _identityRunCarried(mgr),
                deleted: mgr.deletedHdIndices().toSet())
            .where((i) => !asked.contains(i))
            .toList();
        if (todo.isEmpty) break;
        var more = false;
        for (final i in todo) {
          asked.add(i);
          final rk = recoveryKey(seed, i);
          final pieces = await p.node.compartmentCollect(
              mycelium.bundleAsk((d) => recoveryBoxKey(rk, d),
                  recoveryBundleClock()),
              withWhom: withWhom ?? p.node.collectNeighbours,
              keep: true);
          final best = identityRunNewest(
              i, [for (final s in pieces ?? const <Uint8List>[]) openRecoveryBundle(s)]);
          _log.info('Identity run (§13.7): index $i — '
              '${pieces == null ? "not asked" : best == null ? "nothing (${pieces.length} piece(s))" : best.active ? "found" : "found deleted"}');
          if (best == null) continue;
          if (!await _identityRunTake(mgr, best)) return found;
          found++;
          more = true;
        }
        if (!more) break;
      }
    } on Object catch (e) {
      _log.warn('Identity run (§13.7): pass ended — $e');
    }
    if (found > 0) onStateChanged?.call();
    return found;
  }

  Set<int> _identityRunCarried(IdentityManager mgr) => {
        for (final i in mgr.loadIdentities())
          if (i.hdIndex != null) i.hdIndex!
      };

  /// A find: `active` → created from the words and started by the host;
  /// otherwise noted as deleted. `false`: creating failed (named) — the pass
  /// ends, the next edge tries again.
  Future<bool> _identityRunTake(
      IdentityManager mgr, RecoveryBundleContent c) async {
    final i = c.identityIndex;
    if (!c.active) {
      mgr.markHdIndexDeleted(i);
      _log.info('Identity run (§13.7): index $i was deleted — noted, never '
          'given again (§4.5.1)');
      return true;
    }
    final Identity created;
    try {
      created = await mgr.createIdentityAtIndex(
          i, c.displayName.isEmpty ? '${i + 1}' : c.displayName,
          restoredFromPhrase: true);
    } on Object catch (e) {
      _log.warn('Identity run (§13.7): index $i found, not created — $e');
      return false;
    }
    _log.event('Identity run (§13.7): identity at index $i found and created');
    final start = onIdentityFound;
    if (start == null) {
      _log.warn('Identity run (§13.7): no host listener — the identity at '
          'index $i starts with the next start');
    } else {
      try {
        await start(created);
      } on Object catch (e) {
        _log.error('Identity run (§13.7): the identity at index $i did not '
            'start ($e) — it starts with the next start');
      }
    }
    return true;
  }

  /// A card was read (§15.2): its addresses are asked at once by the asking
  /// service of the host (§13.3.1 "at once with the addresses of any
  /// invitation it reads"). Not waited for.
  void _identityRunAtCard(mycelium.Card card) {
    final p = myceliumMailbox;
    if (p == null) return;
    final holders =
        mycelium.cardHolders(card.ownAddresses, card.neighbourAddress);
    if (holders.isEmpty) return;
    for (final s in servicesOnHost(p.host, this)) {
      final sp = s.myceliumMailbox;
      if (sp != null && s._identityRunAsker(sp)) {
        unawaited(s.identityRunPass(withWhom: holders));
        return;
      }
    }
  }

  /// The user names an index of their own (§13.7, §13.2.2): the identity is
  /// created there from the words and looks for its bundle itself (§13.0).
  /// `false`: the run is closed, the index is out of range, carried or
  /// deleted, or creating failed.
  ///
  /// Its name is its number counted from 1 until the user renames it — the
  /// bundle it finds names the old name, but taking a bundle over keeps the
  /// identity as it is (`applyRecoveryBundle`).
  Future<bool> identityRunName(int index) async {
    if (index < 0 || index >= kIdentityRunNameAtMost) return false;
    final mgr = _identityMgr;
    if (!mgr.identityRunOpen()) return false;
    final Identity created;
    try {
      created = await mgr.createIdentityAtIndex(index, '${index + 1}',
          restoredFromPhrase: true);
    } on Object catch (e) {
      _log.warn('Identity run (§13.7): named index $index not created — $e');
      return false;
    }
    _log.event('Identity run (§13.7): index $index named by the user');
    await onIdentityFound?.call(created);
    onStateChanged?.call();
    return true;
  }

  /// The user ends the run (§13.7: never automatically). New identities get
  /// an index again (§4.5.1).
  bool identityRunClose() {
    try {
      _identityMgr.identityRunClose();
    } on Object catch (e) {
      _log.warn('Identity run (§13.7): not closed — $e');
      return false;
    }
    _log.event('Identity run (§13.7): ended by the user');
    onStateChanged?.call();
    return true;
  }

  /// What the interface shows: open, and how many identities this device
  /// carries. Closed when the state is not readable.
  ({bool open, int found}) get identityRunState {
    try {
      final mgr = _identityMgr;
      if (!mgr.identityRunOpen()) return (open: false, found: 0);
      return (open: true, found: _identityRunCarried(mgr).length);
    } on Object {
      return (open: false, found: 0);
    }
  }

  /// §13.7 last paragraph: the highest living identity of this device lays a
  /// minimal bundle with `active = false` for every deleted index below it,
  /// with each of its own bundles — so the bundles live as long as its own
  /// (§13.3.4). The bundle format is the one of every bundle (D-21): own
  /// index, empty name, `active = false`, no keys, no contacts. Does not
  /// throw.
  ///
  /// The cadence is kept per deleted index, as the own bundle's
  /// (`BundleBox.lastDeposit`, §13.3.4): a minimal bundle counts as laid only
  /// when at least one holder acknowledged it; without a receipt, or when
  /// laying throws, the previous time stays and the next occasion lays it
  /// again. An index being laid by a call still running is not laid twice.
  Future<void> recoveryDeletedLay() async {
    final p = myceliumMailbox;
    final seed = identity.masterSeed;
    final mine = identity.hdIndex;
    if (p == null || seed == null || mine == null) return;
    try {
      final mgr = _identityMgr;
      final carried = _identityRunCarried(mgr);
      if (carried.any((i) => i > mine)) return;
      final below = [
        for (final j in mgr.deletedHdIndices())
          if (j < mine && !carried.contains(j)) j
      ];
      if (below.isEmpty) return;
      final now = recoveryBundleClock();
      final lays = _recoveryDeletedLaidAt;
      final due = [
        for (final j in below)
          if (!lays.laying.contains(j) &&
              mycelium.bundleRenewDue(lays.at[j], now))
            j
      ];
      if (due.isEmpty) return;
      lays.laying.addAll(due);
      try {
        await _recoveryDeletedLayDue(p, seed, due, lays);
      } finally {
        lays.laying.removeAll(due);
      }
    } on Object catch (e) {
      _log.warn('Identity run (§13.7): minimal bundles not laid — $e');
    }
  }

  /// When the minimal bundle of the deleted [index] was last acknowledged by
  /// a holder, or `null` (§13.7, §13.3.4).
  DateTime? recoveryDeletedLaidAt(int index) =>
      _recoveryDeletedLaidAt.at[index];

  Future<void> _recoveryDeletedLayDue(mycelium.Mailbox p, Uint8List seed,
      List<int> due, _DeletedIndexLays lays) async {
    final named = [
      for (final f in p.node.neighbourhood.fixedNeighbours) f.asCardAddress
    ];
    for (final j in due) {
      final at = recoveryBundleClock();
      final mini = RecoveryBundleContent(
        identityIndex: j,
        displayName: '',
        active: false,
        ed25519SecretKey: Uint8List(0),
        mlDsaSecretKey: Uint8List(0),
        x25519SecretKey: Uint8List(0),
        mlKemSecretKey: Uint8List(0),
        rotationChain: const [],
        inviteGeneration: 0,
        inviteHighwater: 0,
        depositedAtMs: at.millisecondsSinceEpoch,
        contacts: const [],
        groups: const [],
      );
      final sealed = sealBundle(bundleKey(seed),
          SodiumFFI().randomBytes(kBundleNonceBytes), mini.encode());
      final pair = recoveryBoxKey(recoveryKey(seed, j), utcDay(at));
      final (done, holders) =
          await p.node.depositNamed(sealed, dayValue(pair.pk), named);
      // As `BundleBox.lastDeposit`: laid only with a receipt (§13.3.4).
      if (holders > 0) lays.at[j] = at;
      _log.info('Identity run (§13.7): minimal bundle (active = false) for '
          'deleted index $j — ${done ? "placed" : "NOT placed"}, $holders '
          'holder(s)');
    }
  }
}

/// The minimal bundles of the deleted indices (§13.7) of this process: per
/// index the time a holder last acknowledged one ([at]) — they follow the own
/// bundle's cadence (§13.3.4) — and the indices a running call lays
/// ([laying]), so that two calls do not lay the same index twice.
class _DeletedIndexLays {
  final Map<int, DateTime> at = {};
  final Set<int> laying = {};
}

/// The one pass that follows a running pass of the run (§13.7): it asks the
/// holders of every edge that came while that pass ran — [all]: the holders
/// a collection asks, because one such edge named none.
class _IdentityRunAgain {
  _IdentityRunAgain(this.result);
  final Future<int> result;
  bool all = false;
  final List<(InternetAddress, int)> holders = [];
}
