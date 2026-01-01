/// Sending on the call port — and why a refused datagram is held, not lost.
///
/// ── WHY THIS IS A SEPARATE FILE ──────────────────────────────────────
///
/// `neighbours.dart` stands at the line budget. The cut lies here because it
/// carries: in THIS file stands HOW a packet of the search leaves its socket;
/// over there, WHAT is sent when. Nothing here knows a call, an answer or an
/// identifier.
///
/// ── WHAT WAS MEASURED (S407-WINSUCHE, 19.10.2026) ──────────────────────
///
/// `RawDatagramSocket.send` returns the number of bytes sent, or **0 when the
/// socket cannot take the datagram now** (dart:io documentation of `send`).
/// On Linux that is the rare full send buffer. On Windows it is the normal
/// case for a second datagram sent in the same event-loop turn: the IOCP path
/// of the Dart VM takes a new datagram only after the previous one has
/// completed — the same defect the data port avoids with the native send path
/// (`wire.dart`, S397-1). Measured on the Windows VM (Dart 3.12.2, pktmon on
/// the NIC):
///
/// | sent per round (6 rounds)          | returned 0 | left the NIC |
/// |------------------------------------|------------|--------------|
/// | group, broadcast, unicast — plain  | 10 of 18   |  8 of 18     |
/// | the same, held until writable      |  6 of 18   | 18 of 18     |
///
/// And with the real search: a Windows node's neighbour call left 4 times to
/// the group and **0 times** to the broadcast — every broadcast follows the
/// group send in the same turn (`Neighbours._out`). `send` was called, the
/// return value was ignored, and nothing said so.
///
/// ── THE RULE ───────────────────────────────────────────────────────────
///
/// A datagram the socket refuses is held in order and sent when the socket
/// reports [RawSocketEvent.write] — the ordinary contract of a non-blocking
/// socket (EWOULDBLOCK, then wait for writability). It is sent ONCE: this is
/// no repeat and no clock (§11.3a); it is the first send, made when the socket
/// can take it. Whatever the socket accepted is never held.
library;

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/wire_target.dart' show impossibleTarget;

/// The datagrams a socket refused, in order — next to the socket instead of
/// in it, the socket is the platform's.
final Expando<Queue<(Uint8List, InternetAddress, int)>> _held =
    Expando<Queue<(Uint8List, InternetAddress, int)>>('held');

/// Sends [packet] on [socket] to [target]:[port], or holds it until the
/// socket is writable. Behind a held datagram everything waits — the order
/// stays the order of the calls.
void sendOrHold(
    RawDatagramSocket socket, Uint8List packet, InternetAddress target, int port) {
  final q = _held[socket];
  if ((q == null || q.isEmpty) && socket.send(packet, target, port) > 0) return;
  (_held[socket] ??= ListQueue()).add((packet, target, port));
  socket.writeEventsEnabled = true;
}

/// To be called with every event of [socket]: at [RawSocketEvent.write] the
/// held datagrams go out, as many as the socket takes; the rest waits for the
/// next write event.
void heldOut(RawDatagramSocket? socket, RawSocketEvent e) {
  if (socket == null || e != RawSocketEvent.write) return;
  final q = _held[socket];
  while (q != null && q.isNotEmpty) {
    final (packet, target, port) = q.first;
    if (socket.send(packet, target, port) == 0) {
      socket.writeEventsEnabled = true;
      return;
    }
    q.removeFirst();
  }
}

/// An answer to the one from whom [d] came. Its sender is unchecked foreign
/// material: a packet with sender port 0 or a broadcast address as sender
/// would CLOSE [via] on answering — permanently, in both directions
/// (measured, S389, `wire_target.dart`). Then this node would never be found
/// again. Moved here from `neighbours.dart` (line budget, S407).
void answerTo(RawDatagramSocket via, Uint8List packet, Datagram d,
    void Function(String)? report) {
  final reason = impossibleTarget(d.address, d.port, packet.length);
  if (reason != null) {
    report?.call('Neighbour search: no answer to ${d.address.address}:'
        '${d.port} — $reason');
    return;
  }
  sendOrHold(via, packet, d.address, d.port);
}
