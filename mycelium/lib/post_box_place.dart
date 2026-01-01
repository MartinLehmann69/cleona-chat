/// The sender role of the post box: placing an own packet with holders
/// (V4.2 §8.2) — send `0x30`, count the receipts `0x31`, take a refusal
/// `0x37` as an answer.
///
/// Split off from `post_box_deposit.dart` (S407-VB20, line budget); the cut
/// follows WHO processes a packet, as for the holder
/// (`post_box_holder.dart`) and the collector (`post_box_collect.dart`).
/// [PostBoxDeposit] holds all three and dispatches the packets.
///
/// **Events, not clocks** (§8.2, D-44): placing ends at the second `0x31`,
/// or not placed when the transmission to every holder has ended without
/// it — never on a deadline. Every `0x30` is a request of the transport
/// ([Silence], §11.3a), which repeats it and gives up; nothing here repeats,
/// counts or times anything.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/post_box_disk.dart' show kIdLength, kValueLength;
import 'package:mycelium/post_box_holder.dart'
    show Neighbour, Send, kNodeIdentifierLength;
import 'package:mycelium/post_box_log.dart' show ackNoted, depositOutcome;
import 'package:mycelium/post_box_proof.dart' show kRequestIdLength;
import 'package:mycelium/post_box_proof_of_work.dart';
import 'package:mycelium/post_box_runs.dart';
import 'package:mycelium/silence.dart';
import 'package:mycelium/split.dart' show endedAfter, kRestPeriod;
import 'package:mycelium/kinds.dart' as kinds;

class PostBoxPlacing {
  final Send send;
  final Silence silence;

  /// An asked holder has answered with its node identifier (hex) — see
  /// `PostBoxDeposit.onNode`.
  final void Function(InternetAddress from, int port, String node)? onNode;
  final void Function(String)? report;

  /// The bound of the own running deposits — [kDepositsAtMost].
  final int atMost;

  /// This node's identifier (hex), as its own holder names it in a receipt.
  /// A sender that holds its own post (S407-VB20) counts that receipt as
  /// one node, but tells [onNode] nothing: the own node is no neighbour.
  final String ownNode;

  PostBoxPlacing(
      {required this.send,
      required this.silence,
      required this.atMost,
      required this.ownNode,
      this.onNode,
      this.report});

  /// Own running deposits, by id (hex), oldest first. At most [atMost]
  /// (§20.2): beyond it the oldest ends with the receipts it has, without
  /// counting a use. A run leaves when every holder has acknowledged or its
  /// transmission has ended; only a [send] without flow (probes) gives no
  /// end, and such a run stays until its receipts or the cap.
  final Map<String, DepositRun> _deposits = {};

  int get runs => _deposits.length;

  /// The node stops: every own run ends with what it has.
  void close() {
    for (final h in _deposits.values) {
      h
        ..release()
        ..complete();
    }
    _deposits.clear();
  }

  /// How a run sends its `0x30` to one holder — kept per run so that a
  /// holder that gives way can hand the same packet to the next ([_giveWay]).
  final Expando<void Function(Neighbour n)> _ask = Expando('ask');

  /// See `PostBoxDeposit.deposit`. [reserve]: the candidates after
  /// [withWhom], in their order (§8.2 "gives way to the next holder").
  Future<(bool done, int acknowledged)> deposit({
    required Uint8List content,
    required Uint8List underValue,
    required List<Neighbour> withWhom,
    List<Neighbour> reserve = const [],
    bool Function()? ended,
  }) {
    final id = depositId(underValue, content, kIdLength);
    final idHex = asHex(id);
    // The same packet still being placed (B-18): the new run replaces it,
    // as a new sending of the same packet replaces the previous one.
    _deposits.remove(idHex)?..release()..complete();
    final h = DepositRun();
    _deposits[idHex] = h;
    while (_deposits.length > atMost) {
      final old = _deposits.remove(_deposits.keys.first)!
        ..release()
        ..complete();
      report?.call('deposit under ${old.valueShort}: more than '
          '$atMost runs — the oldest ends with ${old.node} receipt(s)');
    }
    if (withWhom.isEmpty) {
      _depositEnd(idHex); // nobody there: nothing to compute
      return h.result.future;
    }
    // Compute (F3), then send. A failure ends (false, 0), never an error in
    // an `unawaited`.
    unawaited(() async {
      try {
        final proofOfWork = await depositProofOfWork(id, underValue, content);
        if (!identical(_deposits[idHex], h)) return; // replaced meanwhile
        if (ended?.call() ?? false) {
          report?.call('deposit dropped — acknowledged before its proof of work (§7.1)');
          _depositEnd(idHex);
          return;
        }
        final packet = (BytesBuilder()
              ..addByte(kinds.kDeposit)
              ..add(id)
              ..add(underValue)
              ..add(proofOfWork)
              ..add(content))
            .toBytes();
        // The run state stands BEFORE dispatch: a receipt that arrives while
        // still in the send loop would otherwise find an empty list of the
        // asked and end the run.
        h
          ..asked = List.of(withWhom)
          ..reserve.addAll(reserve)
          ..sentAt = DateTime.now()
          ..value = asHex(underValue)
          ..valueShort = asHex(underValue).substring(0, 8);
        // Placed at the second `0x31` (§8.2), or the sending was
        // acknowledged (§7.1): nothing more is asked, and nobody gives way.
        bool over() =>
            !identical(_deposits[idHex], h) ||
            h.placed != null ||
            (ended?.call() ?? false);
        void one(Neighbour n) {
          final answer = Completer<void>();
          unawaited(silence
              .ask(answer.future,
                  to: n.$1,
                  port: n.$2,
                  send: (a, p) {
                    h.answers['${a.address}:$p'] = answer;
                    return send(packet, (a, p));
                  },
                  wait: endedAfter(kRestPeriod),
                  cancelled: over,
                  what: 'deposit 0x30')
              .then((_) => _transmissionEnded(idHex, h, n, over)));
        }

        _ask[h] = one;
        withWhom.forEach(one);
      } on Object {
        if (identical(_deposits[idHex], h)) _depositEnd(idHex);
      }
    }());
    return h.result.future;
  }

  /// The request to [n] has ended: answered, or it and its repeats stayed
  /// without an answer at every address of that holder (§11.3a — the
  /// transport has declared what failed; nothing is counted here). The
  /// answer wait of a single part is [endedAfter] its leaving — 1.1 s, the
  /// rule of §11.3 for a sender without end mark or request.
  void _transmissionEnded(
      String idHex, DepositRun run, Neighbour n, bool Function() over) {
    // Ended, or replaced by the same packet sent again (B-18).
    if (!identical(_deposits[idHex], run)) return;
    final k = neighbourKey(n);
    run.ended.add(k);
    if (!run.acknowledged.containsKey(k)) _giveWay(run, n, over);
    if (run.finished) _depositEnd(idHex);
  }

  /// [n] ended without a receipt — failed (§11.3a) or refused (`0x37`): it
  /// gives way to the next candidate not asked yet (§8.2 "once failed,
  /// gives way to the next holder"), while the run is not placed, the
  /// sending not acknowledged, and a candidate is left. The same packet, the
  /// same proof of work; the replacement is one more request of the
  /// transport — nothing here repeats or times anything.
  void _giveWay(DepositRun run, Neighbour n, bool Function() over) {
    final one = _ask[run];
    if (one == null || over()) return;
    final next = run.giveWay();
    if (next == null) return;
    report?.call('deposit under ${run.valueShort}: ${neighbourKey(n)} ended '
        'without a receipt — gives way to ${neighbourKey(next)} '
        '(${run.reserve.length} candidate(s) left)');
    one(next);
  }

  /// The run has ended: every holder acknowledged or its transmission
  /// ended (or there was nobody to ask, or nothing was sent).
  void _depositEnd(String idHex) {
    final h = _deposits.remove(idHex);
    if (h == null) return;
    h
      ..release()
      ..complete();
    if (h.sentAt != null) report?.call(depositOutcome(h, h.valueShort));
  }

  /// A `0x31`: `true` when it acknowledges an own running deposit (or is
  /// too short to be anything); `false` — it is the delete receipt of a
  /// collector for an entry this node holds (0x31 carries both roles,
  /// distinguished only by the id).
  bool acknowledged(Uint8List packet, Neighbour from) {
    if (packet.length < 1 + kIdLength) return true;
    final idHex = asHex(packet.sublist(1, 1 + kIdLength));
    final h = _deposits[idHex];
    if (h == null) return false;
    const at = 1 + kIdLength + kNodeIdentifierLength;
    if (packet.length != at + kRequestIdLength) return true;
    final node = asHex(packet.sublist(1 + kIdLength, at));
    final key = neighbourKey(from);
    ackNoted(h, key); // log only (O2)
    h.acknowledged[key] = node;
    final answer = h.answers[key];
    if (answer != null && !answer.isCompleted) answer.complete();
    if (node != ownNode) onNode?.call(from.$1, from.$2, node);
    if (h.node >= 2) h.complete(); // placed at the second 0x31 (§8.2)
    if (h.finished) _depositEnd(idHex);
    return true;
  }

  /// `0x37 | value | id` naming an own running deposit (§8.2): the asked
  /// holder answered and did not take it — the run ends for that holder
  /// without counting it mute (§11.3a: an answer is not silence). Any other
  /// `0x37` belongs to the collector (`false`).
  bool refused(Uint8List packet, Neighbour from) {
    const at = 1 + kValueLength;
    if (packet.length != at + kRequestIdLength) return false;
    final idHex = asHex(packet.sublist(at));
    final h = _deposits[idHex];
    final key = neighbourKey(from);
    if (h == null ||
        h.value != asHex(packet.sublist(1, at)) ||
        !h.asked.any((n) => neighbourKey(n) == key)) {
      return false;
    }
    h.refused.add(key);
    // An answer ends that holder's request (§11.3a): nothing is repeated.
    // Its end ([_transmissionEnded]) lets the next candidate in; only a
    // request that had ended already is settled here.
    final answer = h.answers[key];
    if (answer != null && !answer.isCompleted) {
      answer.complete();
      return true;
    }
    h.ended.add(key);
    if (h.finished) _depositEnd(idHex);
    return true;
  }
}
