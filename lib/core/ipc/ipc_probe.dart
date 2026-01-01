import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cleona/core/ipc/ipc_messages.dart';

/// Asks an IPC endpoint WHETHER A CLEONA DAEMON SITS THERE — instead of
/// only asking whether anything is listening there.
///
/// ── THE FINDING THAT TRIGGERED THIS FILE (finding 3, S370) ───────
///
/// `service_daemon.dart`'s guard 2 read the port from `cleona.port`, set
/// up a TCP connection and took the mere success as "another daemon is
/// running" — then `exit(1)`. On Windows this port is an EPHEMERAL port
/// from 49152-65535; after a hard abort (`taskkill /F`, power failure)
/// the file stays lying there and any other program gets the number.
///
/// MEASURED on 06.09.2026 on the Windows build VM 192.168.10.74, with a
/// pure PowerShell `TcpListener` on 127.0.0.1:49999 and a `cleona.port`
/// that points to 49999:
///
///   > netstat -ano | findstr :49999
///     TCP  127.0.0.1:49999  0.0.0.0:0  ABHOEREN  6508
///   > cleona-daemon.exe --base-dir ... --port 4499
///     [INFO ] Another daemon is listening on TCP port 49999, exiting.
///     ERROR: Another daemon is listening on TCP port 49999. ...
///   > Test-Path ...\cleona.port
///     True
///
/// The daemon never started again as long as the foreign process lived,
/// and did not heal either: the only deletion of the port file lay in the
/// `catch` branch — i.e. exactly where the case does not occur. Under
/// Linux this does not exist, there the same latch checks a Unix socket
/// PATH that no foreign process can occupy.
///
/// ── WHY A PID CHECK IS NOT THE FIX ────────────────────────
///
/// The obvious one would be "living PID AND listening port". Re-measured
/// against the latch order: **guard 0 already leaves the process** if
/// `cleona.pid` names a living PID with the same process name
/// (`_processNameOf`, which already catches PID reuse). If guard 2 is
/// reached at all, the PID is thus by construction not that of a running
/// daemon of our kind — the conjunction would be dead code. And guard 2
/// has a task of its own that no PID answers: it catches the daemon that
/// guard 0 and guard 1 have lost because someone deleted `cleona.lock`
/// AND `cleona.pid` from outside. There the endpoint is the only
/// remaining witness — so one must QUESTION it.
///
/// The question is asked with the token from the same port file and the
/// side-effect-free `ping` (`ipc_server.dart`, answer
/// `{'pong': true}`). A foreign listener does not answer that.

/// An endpoint read from `cleona.port`.
class CleonaPortFile {
  final int port;

  /// The auth token. `null` if the file carries none — then the endpoint
  /// cannot be questioned (the IPC server disconnects unauthenticated
  /// connections), and the caller must treat that as "not confirmed",
  /// not as "occupied".
  final String? token;

  const CleonaPortFile(this.port, this.token);
}

/// Splits the content of `cleona.port` (`"<port>:<token>"`).
///
/// Returns `null` for everything that does not yield a valid port number
/// — an unreadable port file is no evidence of a running daemon.
CleonaPortFile? parseCleonaPortFile(String? contents) {
  if (contents == null) return null;
  final parts = contents.trim().split(':');
  if (parts.isEmpty) return null;
  final port = int.tryParse(parts[0]);
  if (port == null || port <= 0 || port > 65535) return null;
  final token = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  return CleonaPortFile(port, token);
}

/// Does a Cleona IPC server sit on `127.0.0.1:[port]`?
///
/// `true` only if the endpoint answers an authenticated `ping` with a
/// well-formed `IpcResponse` of the same request number and `pong: true`.
/// Every other outcome — no connection established, silence, foreign
/// chatter, timeout, missing token — yields `false`.
///
/// `false` explicitly means "NOT CONFIRMED", not "nobody there". The
/// caller bears the burden of this distinction; in the daemon's latch it
/// is acceptable, because guard 0 (PID + process name) and guard 1
/// (exclusive lock on `cleona.lock`) carry the actual single-instance
/// promise — both proven in a run on Windows on 06.09.2026 — and because
/// a false "occupied" locks the user out permanently, whereas a false
/// "free" is caught by the two latches in front.
Future<bool> cleonaIpcEndpointAnswers({
  required int port,
  required String? token,
  Duration timeout = const Duration(seconds: 2),
  InternetAddress? address,
}) async {
  // Without a token the endpoint cannot be questioned: the IPC server
  // discards every unauthenticated connection, so a real daemon would look
  // exactly like a foreign listener.
  if (token == null) return false;

  Socket? sock;
  try {
    sock = await Socket.connect(
      address ?? InternetAddress.loopbackIPv4,
      port,
    ).timeout(timeout);

    final operation = Random().nextInt(0x7fffffff);
    final answer = Completer<bool>();
    final buffer = StringBuffer();

    sock.cast<List<int>>().transform(utf8.decoder).listen(
      (piece) {
        if (answer.isCompleted) return;
        buffer.write(piece);
        final text = buffer.toString();
        final lines = text.split('\n');
        // The last element is the incomplete remainder.
        buffer
          ..clear()
          ..write(lines.removeLast());
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final msg = parseIpcMessage(line);
            // Events may lie in between (the server sends them
            // unsolicited); what is sought is the answer to OUR ping.
            if (msg is IpcResponse &&
                msg.id == operation &&
                msg.success &&
                msg.data['pong'] == true) {
              if (!answer.isCompleted) answer.complete(true);
              return;
            }
          } catch (_) {
            // Not a Cleona frame — keep reading, do not discard at once:
            // a real server could theoretically put something in front.
          }
        }
      },
      onError: (_) {
        if (!answer.isCompleted) answer.complete(false);
      },
      onDone: () {
        if (!answer.isCompleted) answer.complete(false);
      },
      cancelOnError: true,
    );

    sock.write('${jsonEncode({'type': 'auth', 'token': token})}\n');
    sock.write(IpcRequest(id: operation, command: 'ping').toJsonLine());
    await sock.flush();

    return await answer.future.timeout(timeout, onTimeout: () => false);
  } catch (_) {
    return false;
  } finally {
    try {
      sock?.destroy();
    } catch (_) {}
  }
}
