/// What is bound on the call port — and why it is more than one socket.
///
/// ── WHY THIS IS A SEPARATE FILE ──────────────────────────────────────
///
/// `neighbours.dart` stood at 400 of 400 lines when F-7 (package 19,
/// owner decision 15.09.2026) came along. The budget has no
/// exception mechanism. The cut lies here because it carries: in THIS
/// file stands WHAT is bound; over there, WHO calls when and what a find
/// means. Nothing here knows an identifier, a neighbour or a find.
///
/// ── F-7: WHY THREE KINDS OF LISTENER ────────────────────────────────────────
///
/// In future the search call is answered ONLY via group or broadcast; a
/// search call via unicast gets no answer (§7.2). The reason: until S389 the holder
/// answered every search call that arrived on port 41341, and its
/// answer is 1.58 times as large as the request (find 84 B against search call
/// 83 B plus the signature) — whoever forges the sender address uses
/// every Cleona node as an amplifier against a victim of their choice. They
/// cannot use group and broadcast for that: 255.255.255.255 is not passed on by
/// any router, and 239.192.67.76 does not leave the segment.
/// Whoever calls via group thus stands in the same segment.
///
/// **Dart does not yield the TARGET of a received datagram.** There is
/// no field on the `Datagram` and no option that provides it; the question
/// "did this come via group or via unicast" is not answerable at a socket that listens on the
/// wildcard address. So the
/// BINDING answers it. Measured on 16.09.2026 (`probe_rufweg.dart`, one sender, five
/// listeners on the same port):
///
/// | bound to        | group  | broadcast | segment broadcast | unicast |
/// |-----------------|--------|-----------|-------------------|---------|
/// | 0.0.0.0         | yes    | yes       | yes               | yes     |
/// | 239.192.67.76   | **yes**| no        | no                | **no**  |
/// | 255.255.255.255 | no     | **yes**   | no                | **no**  |
///
/// A listener at the group address thus gets EXACTLY the packets that went to
/// the group, and a listener at 255.255.255.255 exactly those of the
/// broadcast — a unicast reaches neither of the two. The wildcard still gets
/// everything; it stays responsible for the NEIGHBOUR CALL, whose
/// answer anyone gives and which amplifies nothing (call 35 B, answer 35 B).
///
/// Counter-check over the real wire (`probe_rufweg2.dart`, sender on
/// 192.0.2.201, listener on this machine): the listener at
/// 255.255.255.255 got the 20 broadcasts of the peer, the one at the group
/// nothing — **and the wildcard did not get the group packets either.**
/// On this segment multicast does not arrive at all (Wi-Fi plus bridge); the
/// listener at the group address thus loses nothing there that the wildcard
/// would have. Evidence that the group binding CARRIES over a real wire
/// is thus still outstanding (§9 of the report).
library;

import 'dart:io';

import 'package:mycelium/neighbours_channel.dart';

/// Binding of a segment-wide listener — replaceable for the probe, for
/// the same reason as [ListenerBinding]: the real addresses cannot be had
/// for a probe on a machine with foreign nodes.
typedef SegmentBinding = Future<RawDatagramSocket> Function(
    InternetAddress destination, int port);

/// The real binding. Default value.
Future<RawDatagramSocket> realSegmentBinding(
        InternetAddress destination, int port) =>
    RawDatagramSocket.bind(destination, port, reuseAddress: true, reusePort: true);

/// Everything that was bound on the call port.
///
/// [listen] hears everything on the call port and is the ONLY one that answers —
/// a socket bound to the group address carries it as
/// sender, and a packet with a group address as sender is
/// useless. [segment] hears only what went to group or broadcast, and
/// is thus the evidence that F-7 demands.
typedef Listener = ({
  RawDatagramSocket? listen,
  RawDatagramSocket call,
  List<RawDatagramSocket> segment,
  CallRoute route,
});

/// Binds everything the neighbour search needs. If any of it fails, that is
/// NO abort (§7.2: "fall back to the wildcard address and
/// continue") — it is said and stands in [Listener].
Future<Listener> listenerOpen({
  required int port,
  required InternetAddress group,
  required InternetAddress broadcastCall,
  ListenerBinding listener = realListenerBinding,
  GroupJoin join = realGroupJoin,
  BroadcastRelease release = realBroadcastRelease,
  SegmentBinding segment = realSegmentBinding,
  void Function(String)? report,
}) async {
  RawDatagramSocket? listen;
  String? listenReason;
  try {
    listen = await listener(port);
  } catch (e) {
    listenReason = '$e';
  }

  var groupOpen = listen != null;
  String? groupReason = listen == null ? 'no listening' : null;
  if (listen != null) {
    try {
      join(listen, group);
    } catch (e) {
      groupOpen = false;
      groupReason = '$e';
    }
  }

  final call = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  var broadcastCallOpen = true;
  String? broadcastCallReason;
  try {
    release(call);
  } catch (e) {
    broadcastCallOpen = false;
    broadcastCallReason = '$e';
  }

  final route = groupOpen
      ? (broadcastCallOpen ? CallRoute.groupAndBroadcastCall : CallRoute.onlyGroup)
      : (broadcastCallOpen ? CallRoute.onlyBroadcastCall : CallRoute.none);

  sayWhatGoes(route, groupReason, broadcastCallReason, report);
  if (listenReason != null) {
    _say(
        report,
        'Neighbour search: port $port not available ($listenReason). This node '
        'is not FOUND in the segment, but can call itself and receive '
        'answers. Not an error.');
  }

  final segments = <RawDatagramSocket>[];
  for (final (what, destination) in [('Gruppe', group), ('Rundruf', broadcastCall)]) {
    try {
      final s = await segment(destination, port);
      if (destination == group) join(s, group);
      segments.add(s);
    } catch (e) {
      _say(
          report,
          'Neighbour search: no listening on ${destination.address}:$port ($e). A '
          'search call via $what stays unanswered here — answered is '
          'ONLY what came via group or broadcast (F-7). Not an error.');
    }
  }
  if (segments.isEmpty) {
    _say(
        report,
        'Neighbour search: no segment-wide listening. This node answers '
        'NO search call any more; it is still found via the neighbour call '
        'and via the addresses of its card.');
  }

  return (listen: listen, call: call, segment: segments, route: route);
}

/// Say where someone is listening — and otherwise to stderr: quietly being able to do less
/// is allowed, quietly being able to do less WITHOUT saying so is not.
void _say(void Function(String)? report, String text) =>
    report == null ? stderr.writeln(text) : report(text);
