// cleona-ipc — ONE request to the daemon over the protected connection
// (S403, step 2; v4_2 §22.1: "tools and tests connect through the same
// exchange").
//
//   cleona-ipc <socket_path> '<json request>'
//   cleona-ipc <socket_path> --events <seconds> '<json request>'
//   cleona-ipc <socket_path> -            (the request on stdin)
//   cleona-ipc <socket_path> --timeout <seconds> …   (default 60 s)
//
// `<socket_path>` is the daemon's `cleona.sock` (on Windows the path with
// `.sock`, the port is read from `cleona.port` beside it, as `IpcClient`
// does). The profile directory is the directory of that path; the tool
// opens the keyring of the OS for it, reads the master seed, opens the
// device database and takes the secret of the connection from there — the
// same steps the GUI takes. Then it runs the exchange, sends the request
// sealed and prints the matching response as ONE line of JSON on stdout.
//
// With `--events <seconds>` every event that arrives within that time is
// printed as well, one JSON line each, before the response line.
//
// When there is no answer — no endpoint, the exchange fails, timeout — it
// prints a response with `success: false` and the reason, so that a caller
// parsing stdout always finds one line, and exits non-zero.
//
// Replaces the Python snippets and `test/e2e/lib/ipc_bridge.dart`, which
// wrote plaintext lines to the socket; the daemon serves those no more.
//
// Built with the daemon (`scripts/build-daemon.sh`, `bin/cleona-ipc`),
// because it needs the same build hooks (the device database).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/ipc/ipc_channel.dart';
import 'package:cleona/core/ipc/ipc_probe.dart' show parseCleonaPortFile;
import 'package:cleona/core/ipc/ipc_secret.dart';
import 'package:cleona/core/log/clogger.dart';

Never _answer(int id, String error, int code) {
  stdout.writeln(jsonEncode({
    'type': 'response',
    'id': id,
    'success': false,
    'error': error,
    'data': <String, dynamic>{},
  }));
  exit(code);
}

Future<void> main(List<String> args) async {
  // stdout carries JSON lines only — the callers parse it. The keyring and
  // the device database log through CLogger, which would print there too.
  CLogger.consoleEnabled = false;
  int eventSeconds = 0;
  // How long to wait for the response. The callers it replaces waited 60 s
  // by default and took the test's own budget where one was given.
  int responseSeconds = 60;
  bool usable = args.length >= 2 && args.length.isEven;
  for (var i = 1; usable && i < args.length - 1; i += 2) {
    final value = int.tryParse(args[i + 1]);
    if (value == null || value < 0) {
      usable = false;
    } else if (args[i] == '--events') {
      eventSeconds = value;
    } else if (args[i] == '--timeout' && value > 0) {
      responseSeconds = value;
    } else {
      usable = false;
    }
  }
  if (!usable) {
    stderr.writeln("usage: cleona-ipc <socket_path> [--events <seconds>] "
        "[--timeout <seconds>] '<json request>' | -");
    exit(2);
  }
  final socketPath = args[0];
  // `-`: the request comes on stdin — for callers that would otherwise
  // have to quote JSON through a remote shell (`ssh … cleona-ipc sock -`).
  final request = args.last == '-'
      ? (await stdin.transform(utf8.decoder).join()).trim()
      : args.last;

  int id = 0;
  try {
    final parsed = jsonDecode(request) as Map<String, dynamic>;
    id = parsed['id'] as int? ?? 0;
  } catch (e) {
    _answer(0, 'the request is not JSON: $e', 2);
  }

  final baseDir = ipcBaseDirOf(socketPath);
  final IpcSecureLink link;
  try {
    SodiumFFI();
    await KeyringService.init(baseDir);
    final secret = ipcConnectionSecretForClient(baseDir);
    final Socket socket;
    if (Platform.isWindows) {
      final portFile = File(socketPath.replaceAll('.sock', '.port'));
      final port = parseCleonaPortFile(portFile.readAsStringSync())?.port;
      if (port == null) {
        throw const IpcChannelException('cleona.port holds no port number');
      }
      socket = await Socket.connect(InternetAddress.loopbackIPv4, port)
          .timeout(const Duration(seconds: 10));
    } else {
      socket = await Socket.connect(
              InternetAddress(socketPath, type: InternetAddressType.unix), 0)
          .timeout(const Duration(seconds: 10));
    }
    link = await IpcSecureLink.open(socket, secret);
  } catch (e) {
    _answer(id, 'no protected connection: $e', 3);
  }

  final done = Completer<int>();
  final eventsUntil = DateTime.now().add(Duration(seconds: eventSeconds));
  String? response;
  link.lines.listen((line) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (msg['type'] == 'event' && eventSeconds > 0) {
      stdout.writeln(line);
      return;
    }
    if (msg['type'] == 'response' && msg['id'] == id && response == null) {
      response = line;
      if (eventSeconds == 0 || DateTime.now().isAfter(eventsUntil)) {
        if (!done.isCompleted) done.complete(0);
      }
    }
  }, onError: (Object e) {
    if (!done.isCompleted) done.complete(4);
  }, onDone: () {
    if (!done.isCompleted) done.complete(response == null ? 4 : 0);
  });

  link.send(request);
  if (eventSeconds > 0) {
    Timer(Duration(seconds: eventSeconds), () {
      if (response != null && !done.isCompleted) done.complete(0);
    });
  }
  final code = await done.future
      .timeout(Duration(seconds: responseSeconds + eventSeconds),
          onTimeout: () => 5);
  link.close();
  if (response == null) {
    _answer(id, code == 5 ? 'timeout' : 'the connection ended', code);
  }
  stdout.writeln(response);
  exit(0);
}
