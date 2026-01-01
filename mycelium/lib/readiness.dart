import 'dart:io';

import 'package:mycelium/neighbourhood.dart';

/// The readiness of the node (V4.2 §22.7.1) — founded on
/// RESPONDING neighbours, not on remembered ones.
///
/// **Responding means confirmed in THIS run** (W8, S391, provisional
/// build directive): the neighbour carries a confirmation stamp
/// ([Neighbourhood.confirm]) from the time since the start or the
/// last network change — he has answered a packet of this node
/// that expected an answer. A packet that merely arrives (also
/// cover traffic, also a foreign call) is NO confirmation. Until S391
/// every incoming packet from a neighbour address counted here
/// (`belegt`); this reading has been dropped. A remembered stamp from the
/// last run does not count.
///
/// | State | responding neighbours |
/// |---|---|
/// | [ReadinessState.searching] | 0 |
/// | [ReadinessState.connecting] | 1 |
/// | [ReadinessState.ready] | [kThresholdReady] or more |
///
/// The threshold is that of the post box (§8.2/§8.3, owner decision E1):
/// two receipts make a deposit placed.
///
/// **Counting is per NODE, not per address** (B1/ES-5, S388; S394 V4).
/// Two responding addresses are the same node if the neighbourhood keeps
/// them as ONE neighbour (it named them as its own, `neighbourhood_join.dart`)
/// or if they named the same node identifier in this run (call, holder
/// answers). Neither is signed: whoever can forge a sender address can
/// thus UNDERcount, never overcount.
///
/// ── NO PACKET, NO CLOCK ────────────────────────────────────────────
///
/// This class cannot send anything. It only tips at edges: up on a
/// confirmation, down on a failed use ([mute] — the
/// neighbour is REMOVED in the process, §11.8), on every removal from the list
/// and on [reset]. A neighbour who falls silent while this
/// node asks nothing stays responding — silence is no evidence (§11.8).
enum ReadinessState {
  /// No responding neighbour.
  searching,

  /// One responding neighbour — a deposit does not reach the two receipts
  /// from §8.2.
  connecting,

  /// At least two — a deposit can count as placed.
  ready,
}

/// Callback on every change of state OR number — synchronously at the
/// edge, never on setting, never without change.
typedef OnReadiness = void Function(
    ReadinessState state, int respondingCount);

/// From this many responding neighbours on, the node is `ready` (E1, §8.2).
const int kThresholdReady = 2;

class Readiness {
  final Neighbourhood _neighbourhood;

  /// S394 diagnosis: which address confirmed a neighbour, and when.
  void Function(String)? report;

  /// `adresse:port` of the neighbours confirmed in this run.
  final Set<String> _responding = {};

  /// `adresse:port` -> node identifier (hex) — only for neighbours in the list.
  final Map<String, String> _node = {};

  /// Who learns of changes. One; whoever needs several distributes.
  OnReadiness? onChange;

  Readiness(this._neighbourhood) {
    // The ONE yardstick for "answered in this run" (§22.7.1) lives here, so
    // the neighbourhood asks it instead of keeping a second one: it needs it
    // when a removal empties the fixed seat (W7, `_moveUp`). A remembered
    // stamp must not count there — it would fill the seat with a node that
    // never answered and block the next real one from taking it.
    _neighbourhood.respondingNow =
        (n) => n.addresses.any((a) => _responding.contains(a.key));
    _neighbourhood.observe(
      // An address that leaves the list no longer responds (§22.7.1, „the
      // neighbour leaves the list of 32"; G5) — [gone] carries only the
      // addresses that left.
      removed: (gone) {
        final keys = [for (final a in gone.addresses) a.key];
        _route(keys);
        keys.forEach(_node.remove);
      },
      onConfirmed: (n) {
        final k = n.first.key; // [n] carries only the confirmed address
        if (_responding.contains(k)) return;
        report?.call('responding: $k confirmed');
        _change(() => _responding.add(k));
      },
      joined: () => _change(() {}), // two entries became ONE node
    );
  }

  /// How many different NODES answer (B1, V4).
  int get respondingCount => _responding.map(_who).toSet().length;

  /// The count last reported — [_change] compares against it, so that a
  /// change made inside the neighbourhood (a join) is reported as well.
  int _reported = 0;

  /// The responding neighbours as `adresse:port` — for diagnostics
  /// (§22.7.4). Read only. A node under two addresses stands here
  /// twice; in [respondingCount] it is counted once.
  Set<String> get responding => Set.unmodifiable(_responding);

  ReadinessState get state {
    final n = respondingCount;
    return n == 0
        ? ReadinessState.searching
        : n < kThresholdReady
            ? ReadinessState.connecting
            : ReadinessState.ready;
  }

  /// The neighbour under [from]:[port] has answered a request of THIS node
  /// and in doing so named its node identifier [identifier] (answer
  /// to the call, holder answers `0x31`/`0x35`). That is a confirmation
  /// (W8): the entry is stamped and created if need be.
  ///
  /// The identifier is learned BEFORE the stamp: otherwise a node
  /// that answers under a second address would count double for a moment,
  /// and `ready` would be reported and immediately withdrawn.
  void nodeLearn(InternetAddress from, int port, String identifier) {
    final s = '${from.address}:$port';
    _learn(s, identifier);
    _neighbourhood.confirm(from, port, DateTime.now());
    if (_neighbourhood.holding(from, port) == null) _node.remove(s);
  }

  /// The neighbour under [from]:[port] names its identifier WITHOUT having
  /// answered anything — a foreign call. No confirmation; learning happens
  /// only for an entry that is already in the list.
  void identifierRemember(InternetAddress from, int port, String identifier) {
    final s = '${from.address}:$port';
    if (_neighbourhood.holding(from, port) == null) return;
    _learn(s, identifier);
  }

  /// If an address names a NEW identifier, there is a new run there
  /// (restart, or another node): the addresses of the old identifier
  /// are no longer evidence until their next answer — otherwise a
  /// newly started node would count double under old and new identifier.
  void _learn(String s, String identifier) {
    final before = _node[s];
    if (before == identifier) return;
    _change(() {
      if (before != null) {
        _responding.removeAll([
          for (final e in _node.entries)
            if (e.value == before && e.key != s) e.key
        ]);
      }
      _node[s] = identifier;
    });
  }

  /// At most [n] entries from [neighbours], one per node, in the
  /// given order — the holders of a deposit (§8.2 „three") are supposed to be
  /// three NODES, not three addresses of the same one.
  List<(InternetAddress, int)> different(
      Iterable<({InternetAddress address, int port})> neighbours, int n) {
    final seen = <String>{};
    return [
      for (final e in neighbours)
        if (seen.length < n &&
            seen.add(_who('${e.address.address}:${e.port}')))
          (e.address, e.port)
    ];
  }

  /// Whether the neighbour under [from]:[port] has named its node identifier —
  /// answered a call, called itself or answered as holder. For
  /// the question „have sources 1–3 delivered anyone" (`host_outside.dart`).
  bool knows(InternetAddress from, int port) =>
      _node.containsKey('${from.address}:$port');

  /// The node [address] belongs to: the smallest key of its component,
  /// where addresses of ONE neighbour and addresses with the same node
  /// identifier are joined. At most 32 × 4 addresses — computed on demand.
  String _who(String address) {
    final seen = <String>{address};
    final todo = [address];
    while (todo.isNotEmpty) {
      final s = todo.removeLast();
      final n = _neighbourhood.all.where((x) => x.addresses.any((a) => a.key == s));
      final i = _node[s];
      for (final k in [
        for (final x in n) ...x.addresses.map((a) => a.key),
        if (i != null) ..._node.keys.where((k) => _node[k] == i),
      ]) {
        if (seen.add(k)) todo.add(k);
      }
    }
    return (seen.toList()..sort()).first;
  }

  /// Whether the node under [from]:[port] has in this run ALSO answered under an
  /// address of the other address type (IPv4/IPv6) — a dual-stack neighbour
  /// who can forward between IPv4 and IPv6 (§8.1). By node ([_who]).
  bool doubleStack(InternetAddress from, int port) {
    final k = _who('${from.address}:$port');
    final v6 = from.type == InternetAddressType.IPv6;
    return _responding.any((s) => _isV6(s) != v6 && _who(s) == k);
  }

  static bool _isV6(String key) =>
      key.lastIndexOf(':') != key.indexOf(':');

  /// A request to these neighbours (`0x30`, `0x32`) is completed without their answer:
  /// a failed use (§11.8). The entries
  /// are REMOVED; the removal takes them out here and is the
  /// edge for refilling.
  ///
  /// **Only with counter-evidence** (§11.8, E2): removal happens only when this
  /// node has confirmed ANOTHER neighbour in this run. Whoever
  /// confirms nobody — started offline, dead uplink — learns nothing about his
  /// neighbours from silence; the mute ones are then merely no longer
  /// responding. The second sending that §11.8 requires is done by the
  /// post box itself (`post_box_deposit.dart`) before it reports here.
  void mute(Iterable<(InternetAddress, int)> withoutAnswer) {
    final list = withoutAnswer.toList();
    final muteNode = {
      for (final (a, p) in list) _who('${a.address}:$p')
    };
    final counterProof =
        _responding.map(_who).any((k) => !muteNode.contains(k));
    if (!counterProof) {
      _route([for (final (a, p) in list) '${a.address}:$p']);
      return;
    }
    for (final (a, p) in list) {
      if (!_neighbourhood.useFailed(a, p)) _route(['${a.address}:$p']);
    }
  }

  /// Network change or stop: nobody is confirmed any more. The stamps
  /// in the list stay — they are the basis for „outdated".
  void reset() {
    _change(_responding.clear);
    _neighbourhood.runLimit();
  }

  void _route(List<String> key) =>
      _change(() => _responding.removeAll(key));

  void _change(void Function() f) {
    f();
    final n = respondingCount;
    if (n == _reported) return; // the state follows the number
    _reported = n;
    onChange?.call(state, n);
  }
}
