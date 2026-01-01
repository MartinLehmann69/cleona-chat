import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/neighbour_dropped.dart';
import 'package:mycelium/own_segment.dart' show withinOwnSegment;
import 'package:mycelium/shell_link.dart' show kLinkSilence;

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
/// Two responding addresses are the same node when the neighbourhood keeps
/// them as ONE neighbour: it named them as its own (`neighbourhood_join.dart`),
/// or they named the same node identifier in this run in ANSWERS (to the
/// call, holder answers; a foreign call names nothing here, C-5) and
/// [nodeLearn] joined them (S407-N2). Neither is signed: whoever can forge a sender address can
/// thus UNDERcount, never overcount.
///
/// ── NO PACKET, NO CLOCK ────────────────────────────────────────────
///
/// This class cannot send anything. It only tips at edges: up on a
/// confirmation, down on a failed address ([addressFailed], §11.3a — the
/// address is REMOVED in the process, §11.8), on every removal from the list
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
        keys.forEach(_silent.remove);
      },
      onConfirmed: (n) {
        final k = n.first.key; // [n] carries only the confirmed address
        _silent.remove(k); // it answers again: counter-evidence again
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

  /// Whether [n] answered in this run AND within [within] — the holder rank
  /// "answered" (OP-19 part A; S398 lab run 2, finding 1). Without the
  /// window a node that answered once kept that rank until it left the
  /// list, so ended nodes stood before live ones. The window is the link
  /// silence (`kLinkSilence`, 120 s, the freshness of `Shell.stands`); the
  /// time is the address's confirmation stamp. [respondingCount] and the
  /// seat (W7) keep "in this run" without a window.
  bool answeredRecently(Neighbour n,
      {Duration within = kLinkSilence, DateTime? now}) {
    final since = (now ?? DateTime.now()).subtract(within);
    return n.addresses.any(
        (a) => _responding.contains(a.key) && !a.last.isBefore(since));
  }

  /// The address of [n] that answered in THIS run, newest stamp first;
  /// `null` if none did. Step 3 and the post box send there before an
  /// address of the same node that was only named (§6.2: "the address that
  /// worked most recently is attempted first"; §11.8). Field 09.10.2026:
  /// from its own LAN the bootstrap's public address was silent, its
  /// private one answered — an invitation waited nine hours.
  NeighbourAddress? answeringAddress(Neighbour n) {
    for (final a in n.addresses) {
      if (_responding.contains(a.key)) return a;
    }
    return null;
  }

  /// [a]:[port] itself if it answered in this run or belongs to no known
  /// neighbour; otherwise the answering address of its node, if one exists.
  (InternetAddress, int) answeringFor(InternetAddress a, int port) {
    if (_responding.contains('${a.address}:$port')) return (a, port);
    final n = _neighbourhood.holding(a, port);
    final live = n == null ? null : answeringAddress(n);
    return live == null ? (a, port) : (live.address, live.port);
  }

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
  /// §11.8 "within one run, it names the same node identifier in answers to
  /// this node's requests from both": the list entries whose addresses named
  /// [identifier] become ONE neighbour together with [from]:[port] — the
  /// same join as addresses a node names as its own (`joinOwn`), so seats
  /// and the contact's-device test hold for the node (S407-N2).
  ///
  /// Identifier and join come BEFORE the stamp: otherwise a node that
  /// answers under a second address would count double for a moment, and
  /// `ready` would be reported and immediately withdrawn.
  void nodeLearn(InternetAddress from, int port, String identifier) {
    final s = '${from.address}:$port';
    _learn(s, identifier);
    final same = [
      for (final n in _neighbourhood.all)
        for (final a in n.addresses)
          if (a.key != s && _node[a.key] == identifier) a.asCardAddress
    ];
    if (same.isNotEmpty) {
      _neighbourhood.ownAddresses(from, port,
          [CardAddress(Uint8List.fromList(from.rawAddress), port), ...same]);
    }
    _neighbourhood.confirm(from, port, DateTime.now());
    if (_neighbourhood.holding(from, port) == null) _node.remove(s);
  }

  /// If an ANSWER names a NEW identifier, there is a new run there
  /// (restart, or another node): the addresses of the old identifier
  /// are no longer evidence until their next answer (§11.8.6 last
  /// paragraph) — otherwise a newly started node would count double under
  /// old and new identifier. Only [nodeLearn] calls this: a foreign call
  /// names an identifier without answering anything and changes nothing
  /// here (C-5, S407-LB-P5).
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
  ///
  /// [not]: addresses whose NODE is left out — the recipient's devices on a
  /// deposit (OP-19 part B, S398; §8.2 "chosen so that the recipient will
  /// ask them": the recipient never asks itself). By node, not by address:
  /// the recipient under another address of the same node is left out too.
  List<(InternetAddress, int)> different(
      Iterable<({InternetAddress address, int port})> neighbours, int n,
      {Iterable<(InternetAddress, int)> not = const []}) {
    final seen = {for (final (a, p) in not) nodeOf(a, p)};
    final away = seen.length;
    return [
      for (final e in neighbours)
        if (seen.length - away < n && seen.add(nodeOf(e.address, e.port)))
          (e.address, e.port)
    ];
  }

  /// The node [a]:[port] belongs to (see [_who]) — two addresses with the
  /// same value are one place among the holders (OP-19 part A).
  String nodeOf(InternetAddress a, int port) => _who('${a.address}:$port');

  /// Whether the neighbour under [from]:[port] has named its node identifier
  /// in an answer — to the call or as holder. For
  /// the question „have sources 1–3 delivered anyone" (`host_outside.dart`).
  bool knows(InternetAddress from, int port) =>
      _node.containsKey('${from.address}:$port');

  /// The node [address] belongs to: the smallest key of the ONE neighbour
  /// holding it — the list joins the addresses of a node, whether it named
  /// them as its own or named the same node identifier in answers
  /// ([nodeLearn], §11.8); an address the list does not hold stands alone.
  String _who(String address) {
    for (final n in _neighbourhood.all) {
      if (n.addresses.any((a) => a.key == address)) {
        return (n.addresses.map((a) => a.key).toList()..sort()).first;
      }
    }
    return address;
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

  /// [a]:[port] has failed (§11.3a): a packet that expected an answer and
  /// its repeats all stayed without one (`silence.dart` — the ONE place that
  /// counts; nothing here counts uses any more). The address is REMOVED from
  /// the list (§11.8); the removal takes it out here and is the edge for
  /// refilling. The neighbour stays answering as long as another of its
  /// addresses does (§22.7.1).
  ///
  /// **Only with counter-evidence** (§11.3a, D-68): an address fails only
  /// when this node has confirmed, in this run, ANOTHER neighbour that it
  /// reaches the SAME WAY ([_way]: the same family, the same side of the own
  /// segment) and that is not itself silent. Whoever confirms nobody that
  /// way — started offline, dead uplink, a router without internet whose
  /// segment still answers, IPv6 lost while IPv4 carries — learns nothing
  /// from silence about that way and declares nothing failed on it: the
  /// address stays as it was. Returns whether the address counted as failed.
  ///
  /// [silentNow]: addresses without an answer right now (`Silence`) — no
  /// counter-evidence, so a dead uplink that silences every running request
  /// at once removes none of them. "Not itself silent" is judged per
  /// ADDRESS of that way (§11.3a "an address … to which no request of this
  /// node stands unanswered"): a silent IPv6 address of a dual-stack
  /// neighbour does not keep its answering IPv4 address from proving the
  /// IPv4 way (D-68; until S407-N2 the whole node was excluded, S407-STILLE).
  bool addressFailed(InternetAddress a, int p,
      {Set<String> silentNow = const {}}) {
    final k = '${a.address}:$p';
    final node = _who(k);
    final silent = {...silentNow, ..._silent};
    final way = _way(a);
    final counterProof = _responding
        .where((s) => !silent.contains(s) && _wayOf(s) == way)
        .map(_who)
        .any((x) => x != node);
    if (!counterProof) {
      // Not declared failed — but silent all the same until it answers
      // again: no counter-evidence for the next one to fall silent.
      if (_neighbourhood.holding(a, p) != null) _silent.add(k);
      return false;
    }
    _route([k]);
    if (_neighbourhood.useFailed(a, p)) {
      dropped.dropped(a, p, DateTime.now()); // S406: stays out (§11.8)
    }
    return true;
  }

  /// The way this node reaches [a] (§11.3a): its family and whether it lies
  /// inside the own segment (§7.1) — a LAN neighbour proves nothing about
  /// the internet, IPv4 nothing about IPv6.
  static (bool, bool) _way(InternetAddress a) =>
      (a.type == InternetAddressType.IPv6, withinOwnSegment(a));

  /// [_way] of the responding `address:port` [s] — the address as the list
  /// holds it; `null` (no way) if the list no longer holds it.
  (bool, bool)? _wayOf(String s) {
    for (final n in _neighbourhood.all) {
      for (final x in n.addresses) {
        if (x.key == s) return _way(x.address);
      }
    }
    return null;
  }

  /// Whether [a]:[p] is flagged — removed, or silent without counter-
  /// evidence (§11.8.5). A packet from it under the shell triggers the one
  /// request of §11.8.6 (`node_roam.dart`); the packet itself lifts nothing.
  bool flagged(InternetAddress a, int p) =>
      dropped.removedAt(a, p) != null || _silent.contains('${a.address}:$p');

  /// The request of §11.8.6 to [a]:[p] was answered: the removal and the
  /// silent flag are lifted, the address is taken into the list (its cap
  /// rules apply) as confirmed and counts as answering (§22.7.1 Up edge).
  void returned(InternetAddress a, int p) {
    final k = '${a.address}:$p';
    dropped.forget(a, p);
    _silent.remove(k);
    report?.call('responding: $k answered its path request — returns (§11.8.6)');
    _neighbourhood.confirm(a, p, DateTime.now());
  }

  /// The addresses removed here, and when (`neighbour_dropped.dart`, S406):
  /// a hint confirmed no later than the removal does not bring one back.
  final DroppedAddresses dropped = DroppedAddresses();

  /// Addresses of the list whose request ended without an answer but were
  /// not declared failed (no counter-evidence): they stay answering
  /// (§22.7.1) and are no counter-evidence for another until they answer
  /// again. Only list addresses — bounded by the list (§20.2).
  final Set<String> _silent = {};

  /// Network change or stop: nobody is confirmed any more. The stamps
  /// in the list stay — they are the basis for „outdated".
  /// How many network changes or stops [reset] has seen — the edge count
  /// `node_roam.dart` asks (§11.8.6 "at most one per address and edge").
  int resets = 0;

  void reset() {
    resets++;
    dropped.clear(); // §11.8: after a network change remembered ones are retried
    _silent.clear();
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
