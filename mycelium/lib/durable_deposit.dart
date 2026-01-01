/// The deposit of a durable object with three holders (v4_2 §16.7 "How a
/// report leaves the device", §11.5 `0x90`/`0x91`). S407 SK-1.
///
/// **Holder choice** (§16.7, §9.4 lane 3): evidenced reachability, desktops
/// first — the order of `bulkHolderOrder` (`host_media.dart`), taken as it
/// is —, then devices of non-contacts before devices of contacts
/// ([durableHolderOrder]). Within each, a node that has already shown the
/// capability (named an identifier, answered `0x91`/`0x96`/`0x98`) goes
/// first, and a node that was reached and stayed silent this run is left
/// out: an older 4.2 version discards `0x90` without an answer (D-21) and is
/// asked once, not again (§16.0 "Older 4.2 versions"). A node the request
/// never reached (handshake unanswered) is not left out (S420, BL-2).
///
/// **Proof of work.** The deposit carries `D_box` (§16.7, §8.2), computed
/// once per object before the first `0x90` (`durable_proof.dart`).
///
/// **Placing.** Three holders at once; a holder that answers `0x94` or does
/// not answer ([DurableAsk], §11.3a) gives way to the next candidate. Two
/// `0x91` make "published" and end the stream; when no candidate is left
/// before that, the stream ends with the reason, and the report rests until
/// it is deposited again at the next edge (§16.7, D-47) — that is the
/// application's call, not a clock here.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/durable_ask.dart';
import 'package:mycelium/durable_fetch.dart' show DurableSend, nodeKey;
import 'package:mycelium/durable_packets.dart';
import 'package:mycelium/durable_proof.dart';
import 'package:mycelium/durable_stock.dart';
import 'package:mycelium/durable_trace.dart';

/// Holders a deposit goes to (§16.7).
const int kDepositHolders = 3;

/// Acknowledgements that make a report "published" (§16.7).
const int kDepositPublished = 2;

/// At most this many open neighbours are asked for the stock at one edge
/// (§16.0, S426 V3) — the open set has four places (§11.8.8).
const int kStockAskOpenAtMost = 4;

/// The candidates of [order] (§9.4 lane 3 order) for a deposit: non-contacts
/// before contacts; within each, [capable] ones first; [failed] ones out.
List<CardAddress> durableHolderOrder(List<CardAddress> order,
    {required bool Function(String node) isContact,
    required bool Function(String node) capable,
    required bool Function(String node) failed}) {
  final ranks = [<CardAddress>[], <CardAddress>[], <CardAddress>[], <CardAddress>[]];
  for (final c in order) {
    final k = nodeKey(c);
    if (failed(k)) continue;
    ranks[(isContact(k) ? 2 : 0) + (capable(k) ? 0 : 1)].add(c);
  }
  return [for (final r in ranks) ...r];
}

class DurableDeposit {
  final int channel;
  final Uint8List object;
  final Uint8List hash;
  final List<CardAddress> _candidates;

  /// The holders this deposit may ask (D73B-2, `durable_node.dart`).
  List<CardAddress> get candidates => _candidates;
  final bool Function(String node) _isContact;
  final DurableSend _send;

  /// A holder answered (`true`) or was reached and stayed silent (`false`) —
  /// the node's capability memory (`durable_node.dart`). A holder the
  /// deposit never reached is not reported (S420, BL-2): unreachable says
  /// nothing about the capability, and the next edge asks it again.
  final void Function(CardAddress holder, bool answered) onHolder;

  /// The node's report, for the success lines (`durable_trace.dart`).
  final void Function(String)? report;
  final StreamController<DepositEvent> _events = StreamController();
  final Map<String, DurableAsk> _asks = {};
  final Set<String> _acked = {};
  int _next = 0;
  bool _over = false;

  DurableDeposit(this.channel, this.object, this._candidates,
      {required bool Function(String node) isContact,
      required DurableSend send,
      required this.onHolder,
      this.report})
      : hash = DurableId.of(channel, object).hash,
        _isContact = isContact,
        _send = send;

  Stream<DepositEvent> get events => _events.stream;

  Uint8List? _proof;

  /// Computes the proof of work once (§16.7, `durable_proof.dart`), then
  /// asks the first three candidates.
  Future<void> start() async {
    if (_candidates.isEmpty) {
      return _end('no holder known');
    }
    try {
      _proof = await durableProof(channel, object);
    } on Object catch (e) {
      return _end('proof of work not computed: $e');
    }
    if (_over) return;
    while (_asks.length < kDepositHolders && _next < _candidates.length) {
      _ask(_candidates[_next++]);
    }
  }

  void _ask(CardAddress holder) {
    final k = nodeKey(holder);
    final ask = DurableAsk(
        () => _send(depositPacket(channel, _proof!, object), holder),
        (why, reached) => _failed(holder, why, reached: reached));
    _asks[k] = ask;
    ask.start();
  }

  /// `0x91` or `0x94` from [from].
  void receive(Uint8List p, CardAddress from) {
    final k = nodeKey(from);
    final ask = _asks[k];
    if (ask == null || _over) return;
    final ok = depositedRead(p);
    if (ok != null) {
      if (ok.channel != channel || !_equal(ok.hash, hash)) return;
      ask.answered();
      _asks.remove(k);
      onHolder(from, true);
      if (!_acked.add(k)) return;
      durableTraceDepositAck(
          report, hash, channel, from, _acked.length, kDepositPublished);
      _events.add(DepositEvent(_acked.length,
          holder: k, contactHolder: _isContact(k)));
      if (_acked.length >= kDepositPublished) {
        _close();
      } else if (_next >= _candidates.length && _asks.isEmpty) {
        // S425 N4-2: the last open answer was a receipt and no candidate is
        // left — the run ends here as it does after a refusal or a silence,
        // otherwise it stays open forever and no edge deposits again (§16.7).
        _end('no holder left after ${_acked.length} receipt(s)');
      }
      return;
    }
    final no = notHeldRead(p);
    if (no == null || no.channel != channel || !_equal(no.hash, hash)) return;
    // It answered, but holds nothing: neither capable for questions about
    // the stock nor failed — also when it refused the object for a limit
    // (D-123 (10)): the holder stays askable for the next object.
    ask.answered();
    durableTraceDepositRefused(report, hash, channel, from);
    _gone(k, 'not held there (0x94)');
  }

  void _failed(CardAddress holder, String why, {required bool reached}) {
    durableTraceDepositGone(report, hash, channel, holder, why,
        reached: reached);
    if (reached) onHolder(holder, false);
    _gone(nodeKey(holder), why);
  }

  void _gone(String k, String why) {
    _asks.remove(k);
    if (_over) return;
    if (_next < _candidates.length) {
      _ask(_candidates[_next++]);
    } else if (_asks.isEmpty) {
      _end('no holder left: $why');
    }
  }

  void _end(String reason) {
    if (_over) return;
    _events.add(DepositEvent(_acked.length, ended: true, reason: reason));
    _close();
  }

  void _close() {
    _over = true;
    for (final a in _asks.values) {
      a.cancel();
    }
    _asks.clear();
    unawaited(_events.close());
  }

  /// The node stops.
  void stop() => _end('stopped');

  bool get over => _over;
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
