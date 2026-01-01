import 'dart:async';
import 'dart:io';

import 'package:cleona/core/update/binary_http_server.dart';

/// The HTTP delivery at the data port (§26.6.5) — without link layer.
///
/// ── WHY THIS FILE EXISTS (14.09.2026) ─────────────────────────────
///
/// Up to the cut `BinaryHttpServer` hangs on the HTTP switch of
/// `TcpLinkListener` (`link_io/tcp_listener.dart`). This listener is built
/// solely by `tagline/v41_node.dart`, and the switch is connected solely
/// in `tagline/v41_attach.dart`. Both fall with `tagline/`. The
/// listener itself would stay lying, but it requires node keys,
/// replay buffer and admission of the V4.1 link handshake — none of which
/// is used by mycelium, which binds only UDP on its port (`mycelium/lib/wire.dart`).
/// Without this file 4.2 would have no LAN link (§26.6.6) and no
/// invitation link (§26.6.3) any more.
///
/// ── WHAT IT DOES ───────────────────────────────────────────────────────
///
/// TCP on **the same port number** as the host's UDP port (§26.6.5:
/// "the shared port number for UDP and TCP"), one listener per address family,
/// every connection goes unchanged to
/// [BinaryHttpServer.handleConnection]. Whoever sends no HTTP runs there
/// into the 5 s header deadline (E-83) and is closed — the same
/// timing behaviour as behind the four-byte switch.
///
/// A family that does not bind costs one log line and nothing else
/// (pattern E-120): the node stays fully reachable via UDP, only the
/// delivery is missing.
///
/// ── WHAT IT EXPRESSLY IS NOT ───────────────────────────────────
///
/// No switch. If a TCP link step or the door on 443 comes (§11,
/// E-64), this listener belongs behind the four-byte switch — two
/// listeners on the same TCP port number do not work.
final class DataPortHttp {
  /// The port number of the host. 0 is forbidden: a port chosen by the operating
  /// system would not be the one that link and card name.
  final int port;
  final BinaryHttpServer http;
  final void Function(String) log;

  final List<ServerSocket> _servers = [];

  DataPortHttp({required this.port, required this.http, required this.log}) {
    if (port <= 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be the port number of the host');
    }
  }

  /// Binds per address family and returns the number of bound ones.
  Future<int> start() async {
    for (final (name, address, v6Only) in [
      ('v4', InternetAddress.anyIPv4, false),
      ('v6', InternetAddress.anyIPv6, true),
    ]) {
      try {
        final s = await ServerSocket.bind(address, port, v6Only: v6Only);
        _servers.add(s);
        s.listen((c) => http.handleConnection(c), onError: (Object e) {
          log('Delivery: $name stream error — $e');
        });
      } catch (e) {
        log('Delivery server: $name not bound on port $port — $e');
      }
    }
    return _servers.length;
  }

  Future<void> close() async {
    for (final s in _servers) {
      await s.close();
    }
    _servers.clear();
  }
}
