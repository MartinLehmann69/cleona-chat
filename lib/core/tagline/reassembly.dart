import 'dart:typed_data';

import '../link/cell.dart';
import '../link/frame.dart';

/// Reassembles frames that were fragmented over several cells.
///
/// AP-3a froze the frame types 0x02 (`fragmentStart`) and 0x03 (`fragmentCont`),
/// but left the state machine behind them open. This here
/// is it.
///
/// WHAT THE REASSEMBLED PAYLOAD IS — AP-3a does not fix that, so
/// it is fixed here: the payload is `typ(1) ‖ koerper`, i.e. a
/// complete frame without length field. Thus a fragmented
/// frame lands after reassembly in exactly the same dispatcher as an
/// unfragmented one — there is no second path through the code on which
/// checks could be missing. A fragment can thus carry any type, not
/// only control.
///
/// WHY THE GATES ARE THE ACTUAL THING. A fragment start announces a
/// total length and thereby binds memory before any of it has
/// arrived. Without a gate a counterpart can begin arbitrarily many
/// transfers and finish none — memory would be the
/// attack surface, not the crypto. Hence: hard upper limit per
/// transfer, hard upper limit for the sum, hard upper limit for the
/// number. When the number is reached, the oldest incomplete
/// transfer is discarded — not the new one rejected, otherwise a
/// partner with four corpses could block the channel permanently.
///
/// WHY STRICTLY IN ORDER. The offset is accepted if it exactly
/// matches what has been filled so far — otherwise the transfer is discarded.
/// Overlapping or backwards-running offsets would need a
/// gap management, and that would be a second attack surface (keeping many
/// tiny holes open). Over one connection cells come in order
/// anyway; where they would not, the connection is the problem.
///
/// ERRORS ARE SILENT (E-83). Nothing is logged, everything is counted.
/// A log line per discarded fragment would be a channel to the outside and put into
/// the file exactly the pattern that is hidden on the wire.
final class FrameReassembler {
  /// Largest payload that is reassembled. An entry record is
  /// at ~1.3 KB the largest known case; 16 KB leaves room without
  /// a single transfer binding significant memory.
  static const int maxPayloadBytes = 16 * 1024;

  /// Largest sum over all open transfers of this counterpart.
  static const int maxBufferedBytes = 64 * 1024;

  /// Largest number of simultaneously open transfers per counterpart.
  static const int maxOpenTransfers = 4;

  final Map<int, _Transfer> _open = {};
  int _buffered = 0;
  int _sequence = 0;

  /// Discarded fragments since the node has been running. Only a counter, never log.
  int discarded = 0;

  /// Number of open transfers — for the status line.
  int get openTransfers => _open.length;

  /// Accepts a frame.
  ///
  /// If it is not a fragment, the frame comes back unchanged: the
  /// caller pushes every frame through here and does not itself need to know
  /// whether fragmentation happened.
  ///
  /// If it is a fragment, `null` comes back as long as the transfer
  /// is incomplete — and at the last piece the reassembled
  /// frame.
  ReassembledFrame? offer(int type, Uint8List body) {
    if (type == LinkFrameType.fragmentStart) return _start(body);
    if (type == LinkFrameType.fragmentCont) return _continue(body);
    return ReassembledFrame(type, body);
  }

  ReassembledFrame? _start(Uint8List body) {
    final FragmentStartBody f;
    try {
      f = FragmentStartBody.decode(body);
    } on FormatException {
      discarded++;
      return null;
    }
    if (f.totalLength < 1 || f.totalLength > maxPayloadBytes) {
      discarded++;
      return null;
    }
    if (f.bytes.length > f.totalLength) {
      discarded++;
      return null;
    }
    // A second start on the same identifier throws away the first. That is
    // the only interpretation that does not guess: either the first
    // got lost, or someone is trying to overwrite — in both
    // cases the older state is worthless.
    _drop(f.transferId);
    _makeRoom(f.totalLength);
    if (_buffered + f.totalLength > maxBufferedBytes) {
      discarded++;
      return null;
    }

    final t = _Transfer(f.totalLength, _sequence++);
    t.buffer.setRange(0, f.bytes.length, f.bytes);
    t.filled = f.bytes.length;
    _open[f.transferId] = t;
    _buffered += f.totalLength;
    return _finishIfDone(f.transferId, t);
  }

  ReassembledFrame? _continue(Uint8List body) {
    final FragmentContBody f;
    try {
      f = FragmentContBody.decode(body);
    } on FormatException {
      discarded++;
      return null;
    }
    final t = _open[f.transferId];
    if (t == null) {
      discarded++;
      return null;
    }
    if (f.offset != t.filled || t.filled + f.bytes.length > t.total) {
      _drop(f.transferId);
      discarded++;
      return null;
    }
    t.buffer.setRange(t.filled, t.filled + f.bytes.length, f.bytes);
    t.filled += f.bytes.length;
    return _finishIfDone(f.transferId, t);
  }

  ReassembledFrame? _finishIfDone(int id, _Transfer t) {
    if (t.filled < t.total) return null;
    _drop(id);
    final payload = t.buffer;
    // The reassembled payload is `typ(1) ‖ koerper`. A payload of
    // exactly one byte carries a type without body — permissible.
    final inner = payload[0];
    if (inner == LinkFrameType.fragmentStart ||
        inner == LinkFrameType.fragmentCont) {
      // Fragments within fragments do not exist. Otherwise the gate could
      // be bypassed via nesting.
      discarded++;
      return null;
    }
    return ReassembledFrame(
        inner, Uint8List.sublistView(payload, 1));
  }

  void _drop(int id) {
    final t = _open.remove(id);
    if (t != null) _buffered -= t.total;
  }

  /// Makes room for a new transfer by letting the oldest
  /// incomplete one yield.
  void _makeRoom(int incoming) {
    while (_open.length >= maxOpenTransfers ||
        (_open.isNotEmpty && _buffered + incoming > maxBufferedBytes)) {
      var oldestId = -1;
      var oldestSeq = 1 << 62;
      _open.forEach((id, t) {
        if (t.sequence < oldestSeq) {
          oldestSeq = t.sequence;
          oldestId = id;
        }
      });
      if (oldestId < 0) return;
      _drop(oldestId);
      discarded++;
    }
  }
}

/// A frame as it comes out of the reassembler.
final class ReassembledFrame {
  final int type;
  final Uint8List body;
  const ReassembledFrame(this.type, this.body);
}

final class _Transfer {
  final int total;
  final int sequence;
  final Uint8List buffer;
  int filled = 0;
  _Transfer(this.total, this.sequence) : buffer = Uint8List(total);
}

/// Splits a payload into fragment frames.
///
/// The payload is `typ(1) ‖ koerper` — the same definition as above.
/// Returned is a list of `(typ, koerper)` pairs that the caller
/// puts into cells in this order. If everything fits into one frame,
/// the unfragmented frame comes back: fragmenting where it is not needed
/// costs a cell and thus a slot.
List<({int type, Uint8List body})> fragmentFrame(
  int type,
  Uint8List body, {
  int transferId = 0,
  int maxBodyBytes = kMaxFrameBodySize,
}) {
  if (body.length <= maxBodyBytes) {
    return [(type: type, body: body)];
  }
  final payload = Uint8List(1 + body.length)
    ..[0] = type
    ..setRange(1, 1 + body.length, body);
  if (payload.length > FrameReassembler.maxPayloadBytes) {
    throw ArgumentError(
        'Payload ${payload.length} B exceeds the reassembly limit '
        'of ${FrameReassembler.maxPayloadBytes} B');
  }

  final out = <({int type, Uint8List body})>[];
  final firstChunk = maxBodyBytes - 5; // transferId(2) + totalLength(3)
  final contChunk = maxBodyBytes - 5; // transferId(2) + offset(3)
  var off = firstChunk < payload.length ? firstChunk : payload.length;
  out.add((
    type: LinkFrameType.fragmentStart,
    body: FragmentStartBody(
            transferId, payload.length, Uint8List.sublistView(payload, 0, off))
        .encode()
  ));
  while (off < payload.length) {
    final end =
        (off + contChunk < payload.length) ? off + contChunk : payload.length;
    out.add((
      type: LinkFrameType.fragmentCont,
      body: FragmentContBody(
              transferId, off, Uint8List.sublistView(payload, off, end))
          .encode()
    ));
    off = end;
  }
  return out;
}
