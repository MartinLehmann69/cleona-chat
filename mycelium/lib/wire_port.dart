/// The data port is the node's alone (V4.2 §11.1: one socket per family on
/// the data port, the calls on their own socket on port 41341).
///
/// ── WHY THIS FILE EXISTS (S413) ─────────────────────────────────────────
///
/// `RawDatagramSocket.bind` binds with reuseAddress: true by default. On
/// Linux two sockets that both set it share a UDP port without any error,
/// and a unicast datagram goes to the one bound last. A device that drew the
/// call port 41341 as its data port bound beside its own call listener and
/// received nothing on its data port — permanently, because the port is
/// remembered (S413, smoke_link_preview_group run 12). The same happens with
/// any foreign program that holds the drawn port with SO_REUSEADDR, and the
/// redraw in `Host.start` never ran, because no bind failed.
///
/// A bind WITHOUT reuseAddress fails on any holder; that is the question
/// asked here, and its socket is closed again before the wire binds. The
/// wire itself keeps reuseAddress: its IPv6 socket must share the number
/// with the IPv4 one (measured S413, probe 4: "IPv6 with reuseAddress false:
/// Address already in use").
///
/// ── THE CLOSE IS NOT IMMEDIATE ──────────────────────────────────────────
///
/// Dart closes the descriptor after `close()` returns. A bind right after
/// it failed in 74 of 2000 runs (probe closed, wire binds) and in 12 of 2000
/// (wire closed, probe on the same port, the restart); a second probe needed
/// one wait of 1 ms in 260 and 322 of 2000, and after it every bind
/// succeeded (measured S413, report
/// `berichte/S413-FIX-RUFPORT.md`). Hence [_bindAgain]: a holder from this
/// process is gone within milliseconds, a foreign one stays.
///
/// The window between the probe's close and the wire's bind remains: a
/// program that takes the same number exactly then is not seen. That is no
/// worse than before, when no holder was seen at all.
library;

import 'dart:io';

import 'package:mycelium/neighbours_packet.dart' show kCallPort;

/// At most this many binds, [_apart] from each other — together 100 ms
/// before a port counts as held.
const int _tries = 20;
const Duration _apart = Duration(milliseconds: 5);

/// Binds the IPv4 socket of the wire on [to4]:[port], but only if no other
/// socket holds that number; [port] 0 lets the operating system pick one.
/// Throws [SocketException] for the call port and for a held port —
/// `Host.start` then draws anew; a named port is never replaced.
Future<RawDatagramSocket> bindAlone(InternetAddress to4, int port) async {
  if (port == kCallPort) {
    throw SocketException(
        'port $port is the call port, never a data port (V4.2 §11.1)',
        port: port);
  }
  final number = await _freeNumber(to4, port);
  return _bindAgain(() => RawDatagramSocket.bind(to4, number));
}

/// A number nobody holds: [port] itself, or for 0 the pick of the operating
/// system — which may be the call port while no listener holds it yet on
/// this host. Then that probe stays bound until the second pick, which
/// therefore cannot be the call port again.
Future<int> _freeNumber(InternetAddress to4, int port) async {
  RawDatagramSocket? onCallPort;
  try {
    while (true) {
      final probe = await _bindAgain(
          () => RawDatagramSocket.bind(to4, port, reuseAddress: false));
      if (probe.port != kCallPort) {
        probe.close();
        return probe.port;
      }
      onCallPort = probe;
    }
  } finally {
    onCallPort?.close();
  }
}

/// EADDRINUSE as the operating systems report it: Linux and Android 98,
/// macOS and iOS 48, Windows WSAEADDRINUSE 10048 — and Windows WSAEACCES
/// 10013 (S414): the probe binds WITHOUT SO_REUSEADDR, the wire WITH it
/// (Dart sets SO_REUSEADDR only for reuseAddress: true, `socket_win.cc`
/// `Socket::CreateBindDatagram`), and for that pair on the wildcard address
/// Windows answers WSAEACCES, not WSAEADDRINUSE, while the first socket
/// still exists (Microsoft Learn, "Using SO_REUSEADDR and
/// SO_EXCLUSIVEADDRUSE", table "same user account": Default/Wildcard then
/// SO_REUSEADDR/Wildcard = ACCESS). Measured S414 on the Windows lab VM
/// (`mycelium/berichte/S414-FIX-WINDOWS-DATENPORT.md`): 165 of 300 wire binds
/// right after the probe's close failed with 10013, every one succeeded on
/// the first retry, at most 38 ms — inside [_tries] x [_apart]. Without it
/// the Windows daemon ended at start with the remembered port (lab
/// 07.11.2026). A foreign exclusive holder still fails after the budget.
const Set<int> _addressInUse = {98, 48, 10048, 10013};

/// [bind], tried again while a socket of this process may still be closing —
/// only on the codes of [_addressInUse]. Every other error is no lingering
/// socket and is thrown at once.
Future<RawDatagramSocket> _bindAgain(
    Future<RawDatagramSocket> Function() bind) async {
  for (var attempt = 1;; attempt++) {
    try {
      return await bind();
    } on SocketException catch (e) {
      final inUse = _addressInUse.contains(e.osError?.errorCode);
      if (!inUse || attempt >= _tries) rethrow;
      await Future<void>.delayed(_apart);
    }
  }
}
