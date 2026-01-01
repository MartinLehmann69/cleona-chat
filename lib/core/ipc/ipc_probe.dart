import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/ipc/ipc_channel.dart';

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
/// ── THE QUESTION SINCE S403 ──────────────────────────────────────────
///
/// Until S403 it was an authenticated `ping` with the token from the port
/// file. The token is gone (§22.1: `cleona.port` carries the port number
/// only), and every connection begins with the protected exchange
/// (`ipc_channel.dart`). Its first step is open: the client sends a hello
/// with 32 fresh random bytes, and a Cleona daemon — and only one —
/// answers with a hello of the same version and 32 random bytes of its own.
/// That answers "is this a Cleona daemon?" without the secret, which guard
/// 2 does not have at that moment (it runs before the keyring is opened). A
/// foreign listener does not speak the hello; one that merely echoes what
/// it gets sends back OUR random bytes and is recognised by that.

/// An endpoint read from `cleona.port`.
class CleonaPortFile {
  final int port;

  const CleonaPortFile(this.port);
}

/// Reads the content of `cleona.port`: the port number and nothing else
/// (§22.1). The `<port>:<token>` of an earlier build is no port file of
/// this line — there is no way back to it — and yields `null` like any
/// other content that is not a port number.
///
/// Returns `null` for everything that does not yield a valid port number
/// — an unreadable port file is no evidence of a running daemon.
CleonaPortFile? parseCleonaPortFile(String? contents) {
  if (contents == null) return null;
  final port = int.tryParse(contents.trim());
  if (port == null || port <= 0 || port > 65535) return null;
  return CleonaPortFile(port);
}

/// Does a Cleona IPC server sit on `127.0.0.1:[port]`?
///
/// `true` only if the endpoint answers the open hello of the protected
/// exchange with a hello of the same version and random bytes other than
/// ours. Every other outcome — no connection established, silence, foreign
/// chatter, an echo, timeout — yields `false`.
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
  Duration timeout = const Duration(seconds: 2),
  InternetAddress? address,
}) async {
  Socket? sock;
  try {
    sock = await Socket.connect(
      address ?? InternetAddress.loopbackIPv4,
      port,
    ).timeout(timeout);

    final ours = IpcHello.freshNonce();
    final answer = Completer<bool>();
    final buffer = StringBuffer();

    sock.cast<List<int>>().transform(utf8.decoder).listen(
      (piece) {
        if (answer.isCompleted) return;
        buffer.write(piece);
        final text = buffer.toString();
        final at = text.indexOf('\n');
        if (at < 0) return;
        final theirs = IpcHello.parse(text.substring(0, at).trim());
        var echo = theirs != null;
        for (var i = 0; echo && i < ours.length; i++) {
          if (theirs![i] != ours[i]) echo = false;
        }
        answer.complete(theirs != null && !echo);
      },
      onError: (_) {
        if (!answer.isCompleted) answer.complete(false);
      },
      onDone: () {
        if (!answer.isCompleted) answer.complete(false);
      },
      cancelOnError: true,
    );

    sock.write('${IpcHello.line(ours)}\n');
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
