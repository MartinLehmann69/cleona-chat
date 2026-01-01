/// The enrolment window of an existing device (V4.2 §14.6.1 step 1, D-39):
/// while it is open, the device asks `value_E(i, d)` of the window's days at
/// its collection edges and hears the enrolment call on the LAN.
///
/// mycelium knows neither the seed nor what a request says: the application
/// supplies the enrol box key per UTC day (`enrol_box(i, d)`, formed from
/// `recovery_key(i)` like the bundle's box key, §13.3.1) and opens what is
/// found. Here stands only WHEN it is asked and WHERE it comes from.
///
///  * **No question of its own, no timer (§5.4).** The values ride on the
///    collection edges of the node (`node_collect_edge.dart`), as the
///    bundle's search does; a shut window asks nothing — idle: nothing.
///  * **The window's days.** A request lies under the value of the day it
///    was laid (§14.6.1 step 2); a 24-hour window touches two UTC days, so
///    the question carries the values from the opening day to today.
///  * **The LAN call.** A `0x80` whose value is one of the window's is taken
///    and answered with `0x81`; with a shut window, or another value,
///    nothing is answered — a device reveals no window it does not have.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_collect_edge.dart';
import 'package:mycelium/node_enrolment.dart';
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/pair.dart' show dayValue, utcDay;
import 'package:mycelium/post_box_deposit.dart'
    show DayPair, Neighbour, Question, kAtMostValues;

/// The enrol box key pair of UTC day `d` — from the application.
typedef EnrolKeyFor = DayPair Function(int day);

/// The window of ONE identity, at the node of its mailbox.
class EnrolWindow {
  final Node node;
  final EnrolKeyFor keyFor;
  final DateTime Function() now;
  final void Function(String)? report;

  /// What a question or a call brought — sealed requests, opened by the
  /// application; [from] is the caller's address for a LAN call, `null`
  /// for a request from the post box.
  final void Function(List<Uint8List> sealed, CardAddress? from) onRequests;

  DateTime? _openedAt;
  DateTime? _until;

  /// Diagnostics: questions this window asked.
  int asks = 0;

  bool _attached = false;
  late final EnrolReceiver _receiver = _receive;

  EnrolWindow(
    this.node, {
    required this.keyFor,
    required this.onRequests,
    this.report,
    this.now = DateTime.now,
  });

  /// Until when the window is open, or `null`.
  DateTime? get until => isOpen ? _until : null;

  bool get isOpen {
    final u = _until;
    return u != null && now().isBefore(u);
  }

  /// Opens the window until [until] (§14.6.1: 24 hours); [from] when it was
  /// opened before a restart.
  void open(DateTime until, {DateTime? from}) {
    _openedAt = from ?? now();
    _until = until;
    _say('window open until ${until.toUtc().toIso8601String()}');
  }

  /// Shuts it: after the handover, a rejection, or the user's cancel.
  void close() {
    if (_until == null) return;
    _until = null;
    _openedAt = null;
    _say('window shut');
  }

  /// From now on at every collection edge and for every LAN call. Once.
  void attach() {
    if (_attached) return;
    _attached = true;
    node.addCollectEdge(_edge);
    node.enrolReceiverAdd(_receiver);
  }

  /// The edge stays registered at the node; it does nothing any more.
  void detach() {
    _attached = false;
    node.enrolReceiverRemove(_receiver);
  }

  /// The values of the window's days, newest first, at most seven.
  List<Question> windowAsk() {
    final opened = _openedAt;
    if (!isOpen || opened == null) return const [];
    final first = utcDay(opened);
    final today = utcDay(now());
    return [
      for (var d = today; d >= first && today - d < kAtMostValues; d--)
        if (keyFor(d) case final p) (value: dayValue(p.pk), pair: p),
    ];
  }

  void _edge(List<Neighbour>? only, Future<int>? _) {
    if (_attached && isOpen) unawaited(ask(withWhom: only));
  }

  /// Asks for requests — [withWhom], else the holders a collection asks
  /// (own fixed neighbours first). Nothing while shut. Every request goes
  /// to [onRequests] when it arrives. Returns how many came, once every
  /// asked holder is done (§8.2). Does not throw.
  Future<int> ask({List<Neighbour>? withWhom}) async {
    final q = windowAsk();
    if (q.isEmpty) return 0;
    asks++;
    final to = withWhom ?? node.collectNeighbours;
    final found = await node.compartmentCollect(q, withWhom: to, onPiece: (p) {
      onRequests([p], null);
      return true;
    });
    _say('window asked ${q.length} value(s) at ${to.length} holder(s) — '
        '${found == null ? "not asked" : "${found.length} request(s)"}');
    return found?.length ?? 0;
  }

  bool _receive(int kind, Uint8List value, Uint8List rest, CardAddress from) {
    if (kind != kinds.kEnrolCall || rest.isEmpty) return false;
    if (!windowAsk().any((q) => enrolSame(q.value, value))) return false;
    node.enrolSend(kinds.kEnrolHeard, value, Uint8List(0), from);
    _say('call heard from ${from.port} (${rest.length} B)');
    onRequests([rest], from);
    return true;
  }

  void _say(String s) => report?.call('enrolment: $s');
}
