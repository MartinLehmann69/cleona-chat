import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/shell.dart';
import 'package:mycelium/shell_link.dart' show kAnswerDeadline;
import 'package:mycelium/send_batch.dart';
import 'package:mycelium/split_flow.dart';
import 'package:mycelium/split_missing.dart';
import 'package:mycelium/trace.dart' show traceSplitFailed;
import 'package:mycelium/wire.dart';
import 'package:mycelium/shell_start.dart' show kPayloadAtMost;

export 'package:mycelium/split_flow.dart' show SendEnd, SplitFlow;
export 'package:mycelium/send_batch.dart' show kSendBatch;

/// Splitting and reassembling — a sealed envelope (~8400 B) does not fit
/// into a UDP packet (~1200 B safe), hence ONE level above the wire.
///
/// Header, 12 B, for BOTH packet types: identifier (8 B random) + field1 (u16
/// LE) + field2 (u16 LE). Part packet: field1 = number of parts, field2 = seq no.
/// Re-request: field2 = sentinel 0xFFFF (never valid as seq no, since always
/// `< Anzahl <= 65535`, so it needs no type byte of its own), field1 = number
/// of missing numbers, then per 2 B (u16 LE) one missing seq no —
/// limited to 594 numbers/packet, for the sendings intended here
/// (one envelope, ~8 parts) that suffices. The header stays at the proposed
/// 12 B; the only deviation from the proposal is that there is none.
/// End mark (§11.3, D-41): the same request with field1 = 0 — no index
/// missing, once per complete transmission of two or more parts; the sender
/// starts its next transmission to that hop on it (`split_flow.dart`).
///
/// **Why 1170 and not 1200** (S390, package 7): under the splitter lies
/// since the shell (`shell.dart`) a pairwise wrapping that brings every packet
/// to EXACTLY 1200 B — 12 B nonce, 16 B authenticator, 2 B length field.
/// A part packet may therefore measure at most 1170 B so that 1200 B lie on the wire.
/// The number does not stand twice: it comes from `kPayloadAtMost`.
const int kMaxPacket = kPayloadAtMost;
const int kHeader = 12;
const int kMaxPayload = kMaxPacket - kHeader; // 1158

/// Quiet period without a new part packet before checking whether something
/// is missing. No standing timer: it exists only while a sending is unfinished.
const Duration kRestPeriod = Duration(milliseconds: 300);

/// §11.3: without end mark and without request a transmission counts as ended
/// this long after its last part — quiet period plus one answer deadline, 1.1 s.
Duration endedAfter(Duration restPeriod) => restPeriod + kAnswerDeadline;

/// After this many re-request rounds IN A ROW that brought no new part the
/// sending counts as failed (D-43, §11.3). A round with progress resets
/// the count; [kDropAfter] stays the hard bound.
const int kAtMostAttempts = 3;

/// Absolute upper limit after which an unfinished sending is discarded —
/// independent of the quiet period. Catches the case that constantly new (but never
/// all) part packets keep postponing the quiet period without an
/// attempt ever being counted.
const Duration kDropAfter = Duration(seconds: 30);


/// One event-loop turn: lets read events (§11.1) in between two batches.
Future<void> _yield() => Future<void>(() {});

final _random = Random.secure();

Uint8List _randomIdentifier() {
  final b = Uint8List(8);
  for (var i = 0; i < 8; i++) {
    b[i] = _random.nextInt(256);
  }
  return b;
}

/// Splits [data] into part packets of at most [kMaxPacket] B (header
/// included). Pure function, no state, no network contact.
List<Uint8List> splitUp(Uint8List data) {
  final count = data.isEmpty ? 1 : (data.length / kMaxPayload).ceil();
  if (count > 0xFFFF) {
    throw ArgumentError('Transfer too large for split.dart: ${data.length} B '
        'would need $count parts, maximum 65535');
  }
  final identifier = _randomIdentifier();
  final parts = <Uint8List>[];
  for (var no = 0; no < count; no++) {
    final start = no * kMaxPayload;
    final end = start + kMaxPayload < data.length ? start + kMaxPayload : data.length;
    final payload = data.sublist(start, end);
    final p = Uint8List(kHeader + payload.length);
    p.setRange(0, 8, identifier);
    final bd = ByteData.sublistView(p);
    bd.setUint16(8, count, Endian.little);
    bd.setUint16(10, no, Endian.little);
    p.setRange(kHeader, p.length, payload);
    parts.add(p);
  }
  return parts;
}

class _IncomingShipment {
  final Uint8List identifier;
  final int count;
  final InternetAddress from;
  final int fromPort;
  final Map<int, Uint8List> parts = {};
  int attempt = 0; // rounds in a row without progress (D-43)
  int heldAtRequest = 0; // parts held when the last request went out
  Timer? restTimer;
  Timer? dropTimer;
  _IncomingShipment(this.identifier, this.count, this.from, this.fromPort);
}

String _key(Uint8List identifier, InternetAddress address, int port) =>
    '${String.fromCharCodes(identifier)}|${address.address}|$port';

/// Reassembles sendings over a [Wire], re-requests what is missing and
/// answers re-requests for sendings it sent itself — one instance takes
/// over both roles. The wire (in operation the shell) stays the caller's.
class Splitter {
  final PacketRoute _wire;
  final void Function(Uint8List data, InternetAddress from, int fromPort) onShipment;
  final void Function(Uint8List identifier, InternetAddress from, int fromPort)? onFailure;
  final Duration restPeriod;
  final int atMostAttempts;
  final Duration dropAfter;

  /// ONLY for tests: discards an incoming part packet (by seq no).
  final bool Function(int seqNo)? testDropPart;

  final Map<String, _IncomingShipment> _incoming = {};
  final void Function(String) _say; // also the `TRACE split … FAILED` line (`trace.dart`)
  /// Whether parts of a transmission from that hop are arriving (§8.2).
  bool receivingFrom(InternetAddress a, int p) => _incoming.values
      .any((s) => s.fromPort == p && s.from.address == a.address);

  /// One transmission of two or more parts at a time per next hop (D-41).
  late final SplitFlow flow;

  /// End marks sent as recipient — for probes and §25, read only.
  int endMarksSent = 0;

  /// Whether the shell still holds packets for a hop (set by [attach]).
  bool Function(InternetAddress, int) _held = (_, __) => false;

  Splitter(
    this._wire, {
    required this.onShipment,
    this.onFailure,
    this.restPeriod = kRestPeriod,
    this.atMostAttempts = kAtMostAttempts,
    this.dropAfter = kDropAfter,
    this.testDropPart,
    void Function(String)? report,
  }) : _say = report ?? ((String s) => stderr.writeln(s)) {
    flow = SplitFlow(_sendLoop, (a, p) => _held(a, p), _say,
        quietAfter: endedAfter(restPeriod), dropAfter: dropAfter);
    _wire.listen(_onPacket);
  }

  /// Lets [shell] tell this splitter whether it still holds a hop's packets
  /// for a handshake — then the quiet clock rests, because those parts have
  /// not left yet — and how the handshake ended (§20.2 "packets waiting for
  /// a link"). The shell lies below the splitter, in the node behind the
  /// cover switch — hence explicit.
  void attach(Shell shell) {
    shell.onHopEnd = (target, port, unreachable) => unreachable
        ? flow.unreachableHop(hopKey(target, port))
        : flow.released(hopKey(target, port));
    _held = shell.holds;
  }

  /// Transmissions whose parts wait for a re-request — at most one per hop.
  int get outgoing => flow.running;

  /// Whether others' transmission of [bytes] to [target]:[targetPort] would
  /// be refused — the bound per target of §20.2 is reached (§8.1: the
  /// forwarder answers `0x21`). A single part never waits.
  bool refuses(InternetAddress target, int targetPort, int bytes) =>
      bytes > kMaxPayload && flow.refuses(target, targetPort, bytes);

  /// Send loops that have not yet handed all their parts to the wire.
  int _loops = 0;
  Completer<void>? _idle;
  bool _ending = false;

  /// Whether a begun send loop still has parts to hand to the wire.
  bool get sending => _loops > 0;

  /// The orderly end (R-1, S399 finding 6): accepts nothing new and
  /// completes once every begun send loop has handed its parts to the wire
  /// — at most one event-loop turn per batch of [kSendBatch], no clock.
  /// Only then may the owner close the wire below. Only what has begun leaves
  /// on stop; a transmission still waiting behind another ends unreachable,
  /// and its message, open in the outbox, goes out again at the next start
  /// — an edge of §8.2 (§9.3).
  Future<void> finish() {
    _ending = true;
    if (_loops == 0) return Future<void>.value();
    return (_idle ??= Completer<void>()).future;
  }

  void _loopEnd() {
    if (--_loops > 0) return;
    _idle?.complete();
    _idle = null;
  }

  /// Splits [data] and sends it. One part goes out at once and ends
  /// [SendEnd.sent] — or, held by the shell for a handshake, when the
  /// handshake ends; two or more wait behind the running transmission to
  /// the same next hop (`split_flow.dart`), never evicted. [foreign]: others'
  /// transmission (forwarding, a holder handing out), bounded per target
  /// (§20.2) — beyond the bound it ends [SendEnd.refused] at once. The
  /// future tells how it ended. After [finish] nothing new is accepted.
  Future<SendEnd> send(Uint8List data, InternetAddress target, int targetPort,
      {bool foreign = false}) {
    if (_ending) return Future.value(SendEnd.unreachable);
    final parts = splitUp(data);
    if (parts.length == 1) {
      _wire.send(parts.single, target, targetPort);
      return _held(target, targetPort)
          ? flow.heldSingle(target, targetPort)
          : Future.value(SendEnd.sent);
    }
    return flow.offer(parts, target, targetPort, data.length, foreign: foreign);
  }

  /// Hands all parts of [t] to the wire, [kSendBatch] per event-loop turn
  /// (§11.1). Only the hop giving up or the drop deadline stops it early;
  /// the node's stop does not (R-1, [finish]).
  Future<void> _sendLoop(Transmission t) async {
    if (_ending) return; // nothing new starts; [close] ends it
    _loops++;
    try {
      for (var i = 0; i < t.parts.length; i++) {
        if (i > 0 && i % kSendBatch == 0) {
          await _yield();
          if (t.cut) return;
        }
        _wire.send(t.parts[i], t.target, t.targetPort);
      }
    } finally {
      _loopEnd();
    }
    flow.active(t); // the last part has left: the quiet clock counts from here
  }

  void _onPacket(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.length < kHeader) return;
    final bd = ByteData.sublistView(packet);
    final identifier = packet.sublist(0, 8);
    final field1 = bd.getUint16(8, Endian.little);
    final field2 = bd.getUint16(10, Endian.little);
    if (field2 == kSentinelMissingRequest) {
      _onMissingRequest(identifier, field1, packet, from, fromPort);
    } else {
      _onPartPacket(identifier, field1, field2, packet, from, fromPort);
    }
  }

  void _onPartPacket(Uint8List identifier, int count, int seqNo, Uint8List packet,
      InternetAddress from, int fromPort) {
    if (seqNo < 0 || seqNo >= count) return; // broken or malicious packet
    if (testDropPart != null && testDropPart!(seqNo)) return;
    final key = _key(identifier, from, fromPort);
    final s = _incoming.putIfAbsent(key, () {
      final fresh = _IncomingShipment(identifier, count, from, fromPort);
      // §11.3 "after 3 rounds without progress, or 30 s": the hard bound
      // tells the caller too — with rounds that keep progressing it is the
      // one that ends a transmission that never completes.
      fresh.dropTimer = Timer(dropAfter, () {
        if (identical(_incoming[key], fresh)) _fail(key, fresh);
      });
      return fresh;
    });
    s.parts[seqNo] = packet.sublist(kHeader);
    s.restTimer?.cancel();
    s.restTimer = Timer(restPeriod, () => _onRest(key));
    _checkComplete(key, s);
  }

  void _checkComplete(String key, _IncomingShipment s) {
    if (s.parts.length != s.count) return;
    final totalLength = s.parts.values.fold<int>(0, (a, b) => a + b.length);
    final result = Uint8List(totalLength);
    var pos = 0;
    for (var i = 0; i < s.count; i++) {
      final t = s.parts[i]!;
      result.setRange(pos, pos += t.length, t);
    }
    s.restTimer?.cancel();
    s.dropTimer?.cancel();
    _incoming.remove(key);
    // The end mark (§11.3), once for 2+ parts, AFTER the hand-on: a holder's
    // `0x31` leaves before it (§8.2, S399 step 4).
    try {
      onShipment(result, s.from, s.fromPort);
    } finally {
      if (s.count >= 2) {
        endMarksSent++;
        _wire.send(buildMissingRequest(s.identifier, const []), s.from, s.fromPort);
      }
    }
  }

  void _fail(String key, _IncomingShipment s) {
    s.restTimer?.cancel();
    s.dropTimer?.cancel();
    _incoming.remove(key);
    traceSplitFailed(_say, s.identifier, s.parts.length, s.count, s.from, s.fromPort);
    onFailure?.call(s.identifier, s.from, s.fromPort);
  }

  void _onRest(String key) {
    final s = _incoming[key];
    if (s == null) return; // already done or discarded
    final missing = <int>[
      for (var i = 0; i < s.count; i++)
        if (!s.parts.containsKey(i)) i,
    ];
    if (missing.isEmpty) return; // already gone through [_checkComplete]
    // D-43 (§11.3): a round counts only if it brought no new part. A burst
    // that the receive buffer thinned out comes back round by round; it
    // fails after three rounds in a row without progress, or after
    // [dropAfter].
    if (s.parts.length > s.heldAtRequest) s.attempt = 0;
    if (s.attempt >= atMostAttempts) return _fail(key, s);
    s.attempt++;
    s.heldAtRequest = s.parts.length;
    _wire.send(buildMissingRequest(s.identifier, missing), s.from, s.fromPort);
    s.restTimer = Timer(restPeriod, () => _onRest(key));
  }

  /// A request for the running transmission to that hop: an empty one is
  /// its end mark, otherwise the named parts go out again (§11.3) —
  /// [kSendBatch] per event-loop turn, as in [_sendLoop].
  Future<void> _onMissingRequest(
      Uint8List identifier, int countMissing, Uint8List packet, InternetAddress from, int fromPort) async {
    final hop = hopKey(from, fromPort);
    final t = flow.runningFor(hop, identifier);
    if (t == null) return; // we do not know (any more)
    if (countMissing == 0) {
      flow.endMark(hop); // the recipient holds it whole
      return;
    }
    flow.active(t);
    final bd = ByteData.sublistView(packet);
    var sent = 0;
    _loops++;
    try {
      for (var i = 0; i < countMissing; i++) {
        final off = kHeader + i * 2;
        if (off + 2 > packet.length) break;
        final seqNo = bd.getUint16(off, Endian.little);
        if (seqNo >= t.parts.length) continue;
        if (sent > 0 && sent % kSendBatch == 0) {
          await _yield();
          if (t.cut || t.how == SendEnd.delivered) return;
        }
        _wire.send(t.parts[seqNo], t.target, t.targetPort);
        sent++;
      }
    } finally {
      _loopEnd();
    }
    flow.active(t);
  }

  /// Ends the own state (timers, open and waiting transmissions — these
  /// end [SendEnd.unreachable]); the [Wire] stays with the caller and is
  /// NOT closed here. A begun send loop is not cut — see [finish] for
  /// waiting on it before the wire closes.
  void close() {
    for (final s in _incoming.values) {
      s.restTimer?.cancel();
      s.dropTimer?.cancel();
    }
    _incoming.clear();
    flow.close();
  }
}
