import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/wire.dart';
import 'package:mycelium/shell_start.dart' show kPayloadAtMost;

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
///
/// **Why 1170 and not 1200** (S390, package 7): under the splitter lies
/// since the shell (`shell.dart`) a pairwise wrapping that brings every packet
/// to EXACTLY 1200 B — 12 B nonce, 16 B authenticator, 2 B length field.
/// A part packet may therefore measure at most 1170 B so that 1200 B lie on the wire.
/// The number does not stand twice: it comes from
/// `kNutzlastHoechstens`.
const int kMaxPacket = kPayloadAtMost;
const int kHeader = 12;
const int kMaxPayload = kMaxPacket - kHeader; // 1158
const int _kSentinelMissingRequest = 0xFFFF;

/// Quiet period without a new part packet before checking whether something is missing.
/// NO permanently running timer: it is reset with every part packet
/// and exists only while a sending is unfinished.
const Duration kRestPeriod = Duration(milliseconds: 300);

/// After this many re-requests without success the sending counts as
/// failed.
const int kAtMostAttempts = 3;

/// Absolute upper limit after which an unfinished sending is discarded —
/// independent of the quiet period. Catches the case that constantly new (but never
/// all) part packets keep postponing the quiet period without an
/// attempt ever being counted.
const Duration kDropAfter = Duration(seconds: 30);

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
  int attempt = 0;
  Timer? restTimer;
  Timer? dropTimer;
  _IncomingShipment(this.identifier, this.count, this.from, this.fromPort);
}

class _OutgoingShipment {
  final List<Uint8List> parts; // full packets incl. header, index = sequence no.
  final InternetAddress target;
  final int targetPort;
  Timer? dropTimer;
  _OutgoingShipment(this.parts, this.target, this.targetPort);
}

String _key(Uint8List identifier, InternetAddress address, int port) =>
    '${String.fromCharCodes(identifier)}|${address.address}|$port';

/// Reassembles sendings over a [Wire], re-requests what is missing and
/// answers re-requests for sendings it sent itself — one
/// instance takes over both roles, as the same wire does in real operation.
/// The wire — in operation the shell above it — stays the property of the
/// caller, [close] only cleans up the own state.
class Splitter {
  final PacketRoute _wire;
  final void Function(Uint8List data, InternetAddress from, int fromPort) onShipment;
  final void Function(Uint8List identifier, InternetAddress from, int fromPort)? onFailure;
  final Duration restPeriod;
  final int atMostAttempts;
  final Duration dropAfter;

  /// ONLY for tests: discards an incoming part packet (by seq no) to
  /// reproduce network loss without touching the wire.
  final bool Function(int seqNo)? testDropPart;

  final Map<String, _IncomingShipment> _incoming = {};
  final Map<String, _OutgoingShipment> _outgoing = {};

  Splitter(
    this._wire, {
    required this.onShipment,
    this.onFailure,
    this.restPeriod = kRestPeriod,
    this.atMostAttempts = kAtMostAttempts,
    this.dropAfter = kDropAfter,
    this.testDropPart,
  }) {
    _wire.listen(_onPacket);
  }

  /// Splits [data], sends all parts, remembers the sending for
  /// later re-requests.
  Future<void> send(Uint8List data, InternetAddress target, int targetPort) async {
    final parts = splitUp(data);
    final identifier = parts.first.sublist(0, 8);
    final key = _key(identifier, target, targetPort);
    final s = _OutgoingShipment(parts, target, targetPort);
    s.dropTimer = Timer(dropAfter, () => _outgoing.remove(key));
    _outgoing[key] = s;
    for (final t in parts) {
      _wire.send(t, target, targetPort);
    }
  }

  void _onPacket(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.length < kHeader) return;
    final bd = ByteData.sublistView(packet);
    final identifier = packet.sublist(0, 8);
    final field1 = bd.getUint16(8, Endian.little);
    final field2 = bd.getUint16(10, Endian.little);
    if (field2 == _kSentinelMissingRequest) {
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
      fresh.dropTimer = Timer(dropAfter, () => _incoming.remove(key));
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
    onShipment(result, s.from, s.fromPort);
  }

  void _onRest(String key) {
    final s = _incoming[key];
    if (s == null) return; // already done or discarded
    final missing = <int>[
      for (var i = 0; i < s.count; i++)
        if (!s.parts.containsKey(i)) i,
    ];
    if (missing.isEmpty) return; // should already be gone through _pruefeVollstaendig
    if (s.attempt >= atMostAttempts) {
      s.dropTimer?.cancel();
      _incoming.remove(key);
      onFailure?.call(s.identifier, s.from, s.fromPort);
      return;
    }
    s.attempt++;
    _wire.send(_buildMissingRequest(s.identifier, missing), s.from, s.fromPort);
    s.restTimer = Timer(restPeriod, () => _onRest(key));
  }

  void _onMissingRequest(
      Uint8List identifier, int countMissing, Uint8List packet, InternetAddress from, int fromPort) {
    final key = _key(identifier, from, fromPort);
    final s = _outgoing[key];
    if (s == null) return; // we do not know (any more)
    final bd = ByteData.sublistView(packet);
    for (var i = 0; i < countMissing; i++) {
      final off = kHeader + i * 2;
      if (off + 2 > packet.length) break;
      final seqNo = bd.getUint16(off, Endian.little);
      if (seqNo < s.parts.length) _wire.send(s.parts[seqNo], s.target, s.targetPort);
    }
  }

  /// Ends the own state (timers, open sendings); the [Wire]
  /// stays with the caller and is NOT closed here.
  void close() {
    for (final s in _incoming.values) {
      s.restTimer?.cancel();
      s.dropTimer?.cancel();
    }
    for (final s in _outgoing.values) {
      s.dropTimer?.cancel();
    }
    _incoming.clear();
    _outgoing.clear();
  }
}

Uint8List _buildMissingRequest(Uint8List identifier, List<int> missing) {
  final n = missing.length > kMaxPayload ~/ 2 ? kMaxPayload ~/ 2 : missing.length;
  final p = Uint8List(kHeader + n * 2);
  p.setRange(0, 8, identifier);
  final bd = ByteData.sublistView(p);
  bd.setUint16(8, n, Endian.little);
  bd.setUint16(10, _kSentinelMissingRequest, Endian.little);
  for (var i = 0; i < n; i++) {
    bd.setUint16(kHeader + i * 2, missing[i], Endian.little);
  }
  return p;
}

