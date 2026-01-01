/// The two questions of the durable-object class (v4_2 §16.0 "The stock at
/// an edge", §16.7 "Before a deposit the device asks"; `0x95`–`0x98`).
/// S407 SK-1.
///
/// **The stock at an edge.** At start, on a network change, when a new
/// neighbour is found ([DurableNode.edge], called by the application at
/// exactly these three edges) and when the user opens a channel
/// ([DurableNode.channelOpened]), a node asks ONE neighbour that has shown
/// the capability: "identifiers of channel K since T" with its own state
/// root. Agreeing roots give one packet, "same"; otherwise the list, and
/// the node fetches what it lacks from the node that answered. At an edge
/// the node asks for every channel it holds and fetches; for every channel
/// it only reads (a phone) it learns the identifiers and hands them to the
/// application as new without fetching (§16.7); on opening it fetches that
/// channel. A node that knows no capable neighbour keeps the edge pending
/// and asks when the first one shows itself; the capable nodes are kept by
/// the application across a restart (`DurableStock.rememberedCapable`).
///
/// **The fingerprint question.** Before the preview the device asks the
/// holder it would deposit with first; the answer is the head of the group
/// or "unknown". A holder that does not answer gives way to the next, at
/// most [kDepositHolders] are asked.
///
/// Each question is sent once and waits for its answer ([DurableAsk]); the
/// repeats on silence belong to the transport (§11.3a). A question the node
/// took and left unanswered marks it as failed only if it never showed the
/// capability (§16.0 "Older 4.2 versions", `DurableNode.failed`, S424 F-9);
/// a capable node that stayed silent, and one the question never reached
/// (handshake unanswered), is skipped only until the next edge or opening
/// (S420, BL-2). Either way the question goes to the next capable node.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/durable_ask.dart';
import 'package:mycelium/durable_deposit.dart'
    show kDepositHolders, kStockAskOpenAtMost;
import 'package:mycelium/durable_fetch.dart' show nodeKey;
import 'package:mycelium/durable_node.dart';
import 'package:mycelium/durable_packets.dart';
import 'package:mycelium/durable_serve.dart' show stateRootOf;
import 'package:mycelium/durable_stock.dart';
import 'package:mycelium/durable_trace.dart';
import 'package:mycelium/kinds.dart' as kinds;

class _Fingerprint {
  final int channel;
  final Uint8List fingerprint;
  final List<CardAddress> holders;
  final Completer<FingerprintAnswer> done = Completer();
  int next = 0;
  DurableAsk? ask;
  CardAddress? at;
  _Fingerprint(this.channel, this.fingerprint, this.holders);
}

class DurableQuestions {
  final DurableNode d;
  final Random _random = Random.secure();

  /// Running stock questions by channel: the node asked, the request, and
  /// whether the answer is fetched (held channel, or the user opened it) or
  /// only learned (a read channel at an edge, §16.7).
  final Map<int, (CardAddress, DurableAsk, bool)> _stock = {};

  /// When a read channel last learned its list — the next edge asks only
  /// since then. Memory only; after a restart it asks from the beginning.
  final Map<int, DateTime> _learnedAt = {};
  final Map<String, _Fingerprint> _prints = {};
  bool _edgePending = false;

  /// The nodes the running questions went to (D73B-2, `durable_node.dart`).
  Iterable<CardAddress> get askedAt => [
        for (final s in _stock.values) s.$1,
        for (final s in _spread.values) s.$1,
        for (final f in _prints.values)
          if (f.at != null) f.at!,
      ];

  /// Capable nodes a stock question did not reach since the last edge or
  /// opening: skipped by [ask] until then, so a failed question does not
  /// go to the same node again at once, and the capability memory stays.
  final Set<String> _unreached = {};

  /// Diagnostics.
  int stockAsked = 0;
  int sameAnswers = 0;

  DurableQuestions(this.d);

  /// An edge of §16.0 (start, network change, new neighbour), called by the
  /// application: held channels are asked and fetched, read channels (a
  /// phone) only learned.
  void edge() {
    _unreached.clear();
    if (d.capableNodes.isEmpty) {
      _edgePending = true;
      durableTraceEdge(d.report, 'kept back — no capable node known');
      return;
    }
    final held = d.stock.heldChannels();
    durableTraceEdge(d.report, '— ${d.capableNodes.length} capable node(s), '
        'held ch=${held.join(',')}, read ch=${d.stock.readChannels().join(',')}');
    for (final c in held) {
      ask(c, fetch: true);
      _spreadAsk(c);
    }
    for (final c in d.stock.readChannels()) {
      if (!held.contains(c)) ask(c, fetch: false);
    }
  }

  /// The first capable node ([who]) became known.
  void capableKnown([CardAddress? who]) {
    // Only when it releases something — otherwise it is idle (§16.7).
    if (_edgePending || _openPending.isNotEmpty) {
      durableTraceEdge(d.report, 'first capable node ${who == null ? '-' : nodeKey(who)} — '
          'edge kept back: $_edgePending, opened channels waiting: ${_openPending.length}');
    }
    final opened = List.of(_openPending);
    _openPending.clear();
    for (final c in opened) {
      scheduleMicrotask(() => ask(c, fetch: true));
    }
    if (!_edgePending) return;
    _edgePending = false;
    scheduleMicrotask(edge);
  }

  /// Channels the user opened while no capable node was known.
  final Set<int> _openPending = {};

  /// The user opened [channel] — an edge for every capable node (§16.0).
  void opened(int channel) {
    _unreached.clear();
    ask(channel, fetch: true);
    _spreadAsk(channel);
  }

  /// S426 V3 (§16.0 "each of its open neighbours"): the further stock
  /// questions of one edge — channel and node → the running question.
  final Map<String, (CardAddress, DurableAsk)> _spread = {};

  /// Asks every OTHER open neighbour that has shown the capability (at most
  /// [kStockAskOpenAtMost] together with the question of [ask]) — the
  /// anti-entropy half of epidemic dissemination: with one neighbour per
  /// edge, an object that neighbour lacks stays hidden from this node. One
  /// packet each, and one back when the roots agree. A silent one is simply
  /// not asked again before the next edge; [ask] keeps its own fallback.
  void _spreadAsk(int channel) {
    final primary = _stock[channel]?.$1;
    final open = d.openNodeKeys();
    var asked = primary == null ? 0 : 1;
    for (final to in d.capableNodes) {
      if (asked >= kStockAskOpenAtMost) break;
      final k = nodeKey(to);
      if (primary != null && nodeKey(primary) == k) continue;
      if (!open.contains(k) || _unreached.contains(k)) continue;
      final key = '$channel|$k';
      if (_spread.containsKey(key)) continue;
      final held = d.stock.held(channel);
      final since = held.isNotEmpty ? held.first.ageHours : kSinceBeginning;
      final p = stockAskPacket(channel, since, stateRootOf(d.stock, channel));
      final a = DurableAsk(() => d.send(p, to), (why, reached) {
        _spread.remove(key);
        _unreached.add(k);
        d.report('Durable: stock question to $k failed — $why');
      });
      _spread[key] = (to, a);
      asked++;
      stockAsked++;
      a.start();
      durableTraceStockAsk(d.report, channel, to, since: since, fetch: true);
    }
  }

  /// "Identifiers of channel [channel] since T" to the most recent capable
  /// node — unless such a question for [channel] is already running.
  void ask(int channel, {required bool fetch}) {
    final running = _stock[channel];
    if (running != null) {
      // An opening during a learning question: its answer is fetched.
      if (fetch && !running.$3) _stock[channel] = (running.$1, running.$2, true);
      return;
    }
    final capable = d.capableNodes;
    final to = capable
        .where((c) => !_unreached.contains(nodeKey(c)))
        .firstOrNull;
    // Capable nodes exist, but none was reached since the last edge: the
    // next edge or opening asks again (§16.0, no clock).
    if (to == null && capable.isNotEmpty) return;
    if (to == null) {
      durableTraceStockAsk(d.report, channel, null);
      if (fetch && !d.stock.heldChannels().contains(channel)) {
        _openPending.add(channel);
      } else {
        _edgePending = true;
      }
      return;
    }
    final held = d.stock.held(channel);
    final learned = _learnedAt[channel];
    final since = held.isNotEmpty
        ? held.first.ageHours
        // Opening fetches everything it lacks, also what earlier edges
        // only learned; an edge learns only what is newer than the last.
        : fetch || learned == null
            ? kSinceBeginning
            : DateTime.now().difference(learned).inHours + 1;
    final p = stockAskPacket(channel, since, stateRootOf(d.stock, channel));
    final a = DurableAsk(() => d.send(p, to), (why, reached) {
      final f = _stock.remove(channel)?.$3 ?? fetch;
      d.report('Durable: stock question to ${nodeKey(to)} failed — $why');
      // Locked out only a node that never showed the capability; a capable
      // one, reached or not, is skipped until the next edge (S424 F-9).
      if (!(reached && d.failed(to))) {
        _unreached.add(nodeKey(to));
      }
      ask(channel, fetch: f); // the next capable node, if any
    });
    _stock[channel] = (to, a, fetch);
    stockAsked++;
    a.start();
    durableTraceStockAsk(d.report, channel, to, since: since, fetch: fetch);
  }

  Future<FingerprintAnswer> fingerprint(int channel, Uint8List fingerprint) {
    final f = _Fingerprint(channel, fingerprint, d.holders());
    _printNext(f);
    return f.done.future;
  }

  void _printNext(_Fingerprint f) {
    if (f.next >= f.holders.length || f.next >= kDepositHolders) {
      f.done.complete(const FingerprintAnswer(null, unanswered: true));
      return;
    }
    final to = f.holders[f.next++];
    final r = Uint8List.fromList(
        List.generate(kAskRandomBytes, (_) => _random.nextInt(256)));
    final key = _hex(r);
    f.at = to;
    f.ask = DurableAsk(
        () => d.send(fingerprintAskPacket(f.channel, r, f.fingerprint), to),
        (_, reached) {
      _prints.remove(key);
      if (reached) d.failed(to);
      _printNext(f);
    });
    _prints[key] = f;
    f.ask!.start();
  }

  /// `0x96` and `0x98`.
  void receive(Uint8List p, CardAddress from) {
    if (p[0] == kinds.kDurableStockAnswer) {
      final a = stockAnswerRead(p);
      if (a == null) return;
      final run = _stock[a.channel];
      final bool fetch;
      if (run != null && nodeKey(run.$1) == nodeKey(from)) {
        run.$2.answered();
        _stock.remove(a.channel);
        fetch = run.$3;
      } else {
        // S426 V3: the answer of a further open neighbour asked at the edge.
        final s = _spread.remove('${a.channel}|${nodeKey(from)}');
        if (s == null) return;
        s.$2.answered();
        fetch = true;
      }
      d.capable(from);
      durableTraceStockAnswer(d.report, a.channel, from,
          same: a.same, ids: a.ids.length);
      if (a.same) {
        sameAnswers++;
        return;
      }
      if (!fetch) {
        // A read channel at an edge: handed over as new, not fetched (§16.7).
        _learnedAt[a.channel] = DateTime.now();
        final fresh = [
          for (final id in a.ids)
            if (id.channel == a.channel && !d.stock.isHeldOrRejected(id)) id
        ];
        if (fresh.isNotEmpty) d.stock.learned(a.channel, fresh);
        return;
      }
      for (final id in a.ids) {
        if (id.channel == a.channel) d.want(id, from);
      }
      return;
    }
    final a = fingerprintAnswerRead(p);
    if (a == null) return;
    final f = _prints[_hex(a.random)];
    if (f == null || f.channel != a.channel || nodeKey(f.at!) != nodeKey(from)) {
      return;
    }
    _prints.remove(_hex(a.random));
    f.ask?.answered();
    d.capable(from);
    f.done.complete(FingerprintAnswer(a.head));
  }

  void stop() {
    for (final r in _stock.values) {
      r.$2.cancel();
    }
    _stock.clear();
    for (final s in _spread.values) {
      s.$2.cancel();
    }
    _spread.clear();
    for (final f in _prints.values) {
      f.ask?.cancel();
      if (!f.done.isCompleted) {
        f.done.complete(const FingerprintAnswer(null, unanswered: true));
      }
    }
    _prints.clear();
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
