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
    unawaited(call(sealed, valueE, lan ?? segmentNodes()));
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
    if (_attached) unawaited(collect(withWhom: only));
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
