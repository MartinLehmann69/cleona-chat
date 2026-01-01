/// The new device's side of an enrolment (V4.2 §14.6.1 steps 2 and 4,
/// D-39): it lays its request under `value_E(i, d)`, calls it on the LAN,
/// and waits for the answer under values of its own.
///
///  * **The request** is one post-box deposit under `value_E` of today,
///    named first at the existing device's own fixed neighbours (the bundle
///    names them, §13.3.2) — the holders that device asks (§8.2) — and one
///    `0x80` to each node of the own segment ([EnrolWait.call]).
///  * **The answer** — handover pieces or a rejection — comes under the
///    values of the reply day keys the request carried: directly (`0x82`,
///    acknowledged with `0x83`) while both devices are present, else from
///    the post box, asked at every collection edge while waiting. No timer
///    (§5.4); the wait ends when the application detaches it.
///
/// Before the handover nothing is done in the identity's name (§14.6.1):
/// the reply keys are random, not the identity's day keys, and the identity
/// itself stays held (`node_enrolment.dart`, D-40).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_collect_edge.dart';
import 'package:mycelium/node_enrolment.dart';
import 'package:mycelium/node_first_contact_box.dart';
import 'package:mycelium/node_helpers.dart' show outTheSegment;
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/pair.dart' show dayValue;
import 'package:mycelium/post_box_deposit.dart'
    show DayPair, Neighbour, Question, kAtMostValues;

/// How long a LAN call waits for its `0x81`.
const Duration kEnrolCallDeadline = Duration(seconds: 2);

class EnrolWait {
  final Node node;

  /// The reply key pairs the request named (at most seven: one question).
  final List<DayPair> pairs;
  final DateTime Function() now;
  final void Function(String)? report;

  /// What arrived under the reply values — sealed pieces, opened by the
  /// application. A piece may come twice (direct and post box).
  final void Function(List<Uint8List> pieces) onPieces;

  /// A device with an open window heard the LAN call.
  bool heard = false;

  /// Diagnostics: questions asked while waiting.
  int asks = 0;

  bool _attached = false;
  late final EnrolReceiver _receiver = _receive;

  EnrolWait(
    this.node, {
    required List<DayPair> pairs,
    required this.onPieces,
    this.report,
    this.now = DateTime.now,
  }) : pairs = List.unmodifiable(pairs) {
    if (pairs.isEmpty || pairs.length > kAtMostValues) {
      throw ArgumentError('1 to $kAtMostValues reply pairs');
    }
  }

  /// The reply values, in the order of [pairs].
  List<Uint8List> get values => [for (final p in pairs) dayValue(p.pk)];

  /// From now on at every collection edge and for every direct piece. Once.
  void attach() {
    if (_attached) return;
    _attached = true;
    node.addCollectEdge(_edge);
    node.enrolReceiverAdd(_receiver);
  }

  void detach() {
    _attached = false;
    node.enrolReceiverRemove(_receiver);
  }

  /// Lays [sealed] under [valueE], named first at [named] (the existing
  /// device's fixed neighbours), and calls it on the LAN — at [lan], else
  /// at the nodes of the own segment. Returns the acknowledgements of the
  /// deposit. Does not throw.
  Future<int> request(Uint8List sealed, Uint8List valueE,
      {List<CardAddress> named = const [], List<CardAddress>? lan}) async {
    final to = lan ?? segmentNodes();
    // §14.6.1 step 2 "on the LAN it also sends it as an enrolment call":
    // a segment node that becomes known only after this moment is called at
    // the next collection edge ([_callLate]). An explicit [lan] is the whole
    // list (the smoke's choice).
    if (lan == null) {
      _laid = (sealed: sealed, valueE: valueE);
      for (final t in to) {
        _called.add(_key(t));
      }
    }
    unawaited(call(sealed, valueE, to));
    final (done, n) = await node.depositNamed(sealed, valueE, named);
    _say('request ${sealed.length} B '
        '${done ? "placed" : "NOT placed"} with $n receipt(s)');
    return n;
  }

  /// The enrolment call: `0x80` once to each of [to]; [heard] turns `true`
  /// when a device with an open window answers.
  Future<void> call(Uint8List sealed, Uint8List valueE, List<CardAddress> to) async {
    if (to.isEmpty) return;
    final answered = node.enrolCallHeard(valueE, kEnrolCallDeadline);
    for (final t in to) {
      node.enrolSend(kinds.kEnrolCall, valueE, sealed, t);
    }
    _say('call sent to ${to.length} node(s) of the segment');
    if (await answered) heard = true;
  }

  /// The nodes the own segment holds (the neighbour call found them).
  List<CardAddress> segmentNodes() => [
        for (final n in node.foundNeighbours)
          if (outTheSegment(n.address))
            CardAddress(Uint8List.fromList(n.address.rawAddress), n.port),
      ];

  void _edge(List<Neighbour>? only, Future<int>? _) {
    if (!_attached) return;
    unawaited(collect(withWhom: only));
    _callLate();
  }

  /// The request as laid (segment mode) and the segment nodes already called
  /// — S425-E1: the existing device was admitted as a neighbour 10 s after
  /// the request and never heard the call. Each node is called once; no
  /// clock (§5.4): only at a collection edge, and only until a device with
  /// an open window answered ([heard]).
  ({Uint8List sealed, Uint8List valueE})? _laid;
  final Set<String> _called = {};

  static String _key(CardAddress a) =>
      '${a.address.join('.')}:${a.port}';

  void _callLate() {
    final laid = _laid;
    if (laid == null || heard) return;
    final fresh = [
      for (final t in segmentNodes())
        if (_called.add(_key(t))) t,
    ];
    if (fresh.isEmpty) return;
    _say('call to ${fresh.length} segment node(s) known since the request');
    unawaited(call(laid.sealed, laid.valueE, fresh));
  }

  /// Asks for the answer under the reply values; every piece goes to
  /// [onPieces] when it arrives. Returns how many came, once every asked
  /// holder is done (§8.2). Does not throw.
  Future<int> collect({List<Neighbour>? withWhom}) async {
    asks++;
    final List<Question> q = [
      for (final p in pairs) (value: dayValue(p.pk), pair: p),
    ];
    final to = withWhom ?? node.collectNeighbours;
    final found = await node.compartmentCollect(q, withWhom: to, onPiece: (p) {
      onPieces([p]);
      return true;
    });
    _say('waiting: asked ${to.length} holder(s) — '
        '${found == null ? "not asked" : "${found.length} piece(s)"}');
    return found?.length ?? 0;
  }

  bool _receive(int kind, Uint8List value, Uint8List rest, CardAddress from) {
    if (kind != kinds.kEnrolPiece || rest.isEmpty) return false;
    if (!values.any((v) => enrolSame(v, value))) return false;
    node.enrolSend(kinds.kEnrolPieceHeard, value, enrolDigest(rest), from);
    onPieces([rest]);
    return true;
  }

  void _say(String s) => report?.call('enrolment: $s');
}
