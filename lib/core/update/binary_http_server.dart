import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/log/clogger.dart';

/// §19.6.6 — Embedded HTTP server for censorship-resistant binary
/// distribution. Serves the bootstrap web app and binary/fragment
/// downloads over plain HTTP on the shared UDP/TLS TCP port.
///
/// Does NOT bind its own socket: [Transport] First-Byte-Sniffs incoming
/// TCP connections (`GET `/`HEAD` vs. `0x16 0x03` TLS ClientHello) and
/// hands HTTP connections to [handleConnection].
class BinaryHttpServer {
  /// How long a connection takes to deliver its request header.
  ///
  /// **5 s, and the number does not come from here (E-83, E-123(iii)).** It
  /// stood at 10 s until 2026-08-20, and that was a
  /// **distinguishing feature**: this server shares its port number
  /// with the link handshake (§2.1a, §19.6.5), and the switch between the two
  /// falls after **four bytes**. If one branch closes after 5 s and the
  /// other after 10 s, a single probe of four bytes reveals that
  /// the port carries two protocols — and exactly that is what §19.6.5 does not want
  /// ("it keeps automatic scanners away"), while RL-12 limits the promise to
  /// "learns that something is listening, but not what".
  ///
  /// Of the two existing numbers the normative one wins: §2.6 records with
  /// **E-83** that a node "reads, stays silent, and closes on the
  /// sniff timeout that already exists (**5 s**)" — decided, with a number,
  /// in the leading document. The 10 s were a code constant **without a
  /// normative anchor** (searched with four search phrasings over architecture doc,
  /// decision log and migration plan: no hit). So
  /// the code is pulled to the spec, not the other way round.
  ///
  /// **The price is narrowly limited:** the deadline covers solely the receipt of the
  /// request header — `tryHandle` cancels it as soon as `\r\n\r\n` is there,
  /// i.e. **before** any delivery. Downloads, fragments and the
  /// bootstrap web app are untouched. Affected is solely a browser
  /// that does not deliver its header within 5 s — it goes out in the first segment
  /// anyway.
  static const _requestTimeout = Duration(seconds: 5);
  static const _maxRequestLineBytes = 8192;

  /// Upper limit of simultaneously **open connections**.
  ///
  /// **The predecessor form was a no-op, and that is measured.** It was called
  /// `_maxActiveConnections = 3`, was checked in `_handleRequest`, incremented there
  /// and decremented again in the `finally` of the same **synchronous** body
  /// — between `++` and `--` there is **not a single `await`**.
  /// On a single-threaded event loop a second
  /// `_handleRequest` can therefore never run while the counter is incremented: it is 0 at
  /// every check and reaches 1 as the maximum, never 3. Measured
  /// were 0 of 30 requests rejected and 200 of 200 half-open
  /// connections held. It counted "am I currently IN this function".
  ///
  /// Now it counts the **life cycle of the connection** — incremented on
  /// entry, decremented when the socket is closed.
  ///
  /// **Why not still 3.** A browser opens several connections in parallel per remote side
  /// (usually six). A cap of 3 on
  /// **connections** would have made the bootstrap web app unusable for every normal
  /// browser — repairing the counter without
  /// raising the number would have been worse than the no-op.
  ///
  /// **64 is SET, not derived**, and that stands here so that
  /// nobody takes it for derived. The corpus yields no number for this surface
  /// (§16.7 does not list resource exhaustion;
  /// `connection limit`, `backlog`, `half-open`: zero hits in the
  /// architecture document). The reliable limit comes with the
  /// stream listener: §19.6.5 puts both branches on **one** port behind
  /// **one** four-byte switch, so the HTTP branch belongs under the same
  /// admission rule (`lib/core/link/admission.dart`, pot B / pot U).
  /// Until then 64 is a number that does not break a browser and does not
  /// kill a process.
  static const _maxOpenConnections = 64;

  final CLogger _log;
  bool _enabled = true;
  int _openConnections = 0;

  /// Static HTML+JS served at GET /cleona.
  Uint8List? bootstrapWebApp;

  /// File path for `GET /cleona/binary/<platform>` (streamed in 64KB chunks).
  String? Function(String platform)? binaryProvider;

  /// Single fragment for `GET /cleona/fragment/<platform>/<index>`.
  Uint8List? Function(String platform, int index)? fragmentProvider;

  /// Invoked when `GET /cleona/binary/<platform>` 404s, i.e. a visitor needs a
  /// platform this node does not hold (§19.6.4). Fire-and-forget: the node may
  /// start acquiring it, the visitor polls `/cleona/status/<platform>`.
  void Function(String platform)? onForeignBinaryRequested;

  /// JSON body for `GET /cleona/status/<platform>` — acquisition progress.
  Map<String, dynamic>? Function(String platform)? foreignStatusProvider;

  /// Platforms accepted in a path segment. The segment reaches a file store,
  /// so it is validated against a fixed list rather than interpolated.
  static const Set<String> _knownPlatforms = {
    'android', 'linux', 'windows', 'macos', 'ios',
  };

  BinaryHttpServer({String? profileDir})
      : _log = CLogger.get('http-srv', profileDir: profileDir);

  void dispose() {
    _enabled = false;
  }

  /// Handle a raw TCP connection whose first bytes were sniffed as HTTP by
  /// `Transport._onRawTcpConnection`. [bufferedData], if given, is the
  /// prefix already consumed during sniffing — it must be re-injected into
  /// the request buffer, not dropped, since the caller's subscription (if
  /// passed as [subscription]) only delivers bytes that arrive *after* it.
  ///
  /// [subscription]: a `Socket`'s stream can only ever be listened to once.
  /// Since [Transport] already called `client.listen(...)` to sniff the
  /// first bytes, this method MUST reuse that (paused) subscription by
  /// rewiring its callbacks rather than calling `client.listen(...)` again
  /// — a second `listen()` throws `Bad state: Stream has already been
  /// listened to`. When null (e.g. a future caller hands over a fresh,
  /// never-listened `Socket`), falls back to listening directly.
  void handleConnection(Socket client,
      {Uint8List? bufferedData, StreamSubscription<Uint8List>? subscription}) {
    if (!_enabled) {
      subscription?.cancel();
      client.destroy();
      return;
    }

    // **The cap takes effect on entry, not on delivery.** The
    // descriptor is already occupied at this point; only counting it
    // when a complete header is there would mean not counting exactly the
    // connections that never send one.
    if (_openConnections >= _maxOpenConnections) {
      _log.debug('HTTP connection cap reached ($_maxOpenConnections) — '
          'refusing');
      subscription?.cancel();
      client.destroy();
      return;
    }
    _openConnections++;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      _openConnections--;
    }

    // **Decrementing happens at EVERY exit, and `Socket.done` is not
    // the right hook for that.** The first version hung the release solely
    // there — but `done` is the **send** future of a socket, it
    // completes when WE have finished writing, not when the
    // other side hangs up. Measured: after closing 64 held
    // connections not a single new one was accepted — the counter
    // was stuck. The guard caught that before it was committed.
    //
    // It now hangs at the places where the connection really
    // ends: at the end of the incoming stream (the other side hangs up), at
    // every own teardown, and additionally still at `done` for the
    // case that the answer closes the socket. [release] is
    // idempotent, multiple calls are the normal case.
    unawaited(client.done.then((_) => release()).catchError((Object _) {
      release();
    }));

    final buffer = BytesBuilder();
    if (bufferedData != null && bufferedData.isNotEmpty) {
      buffer.add(bufferedData);
    }
    Timer? timeout;
    StreamSubscription<Uint8List>? sub = subscription;

    void finish() {
      timeout?.cancel();
      sub?.cancel();
    }

    // Returns true once the connection has been fully handled (request
    // dispatched, or destroyed for being malformed/oversized) and no
    // further listening is needed.
    bool tryHandle() {
      if (buffer.length > _maxRequestLineBytes) {
        _log.debug('HTTP request line too large — destroying connection');
        finish();
        release();
        client.destroy();
        return true;
      }
      final bytes = buffer.toBytes();
      final headerEnd = _findHeaderEnd(bytes);
      if (headerEnd == -1) return false; // wait for more data

      finish();
      try {
        _handleRequest(client, bytes, headerEnd);
      } catch (e) {
        _log.debug('HTTP request handling error: $e');
        try {
          _sendResponse(client, 404);
        } catch (_) {}
      }
      return true;
    }

    timeout = Timer(_requestTimeout, () {
      _log.debug('HTTP request timed out — destroying connection');
      finish();
      release();
      client.destroy();
    });

    // A short GET/HEAD request can fit entirely in the sniffed prefix
    // (single TCP segment) — check before subscribing for more data.
    if (tryHandle()) return;

    void onData(Uint8List data) {
      buffer.add(data);
      tryHandle();
    }

    void onDone() {
      finish();
      release();
      client.destroy();
    }

    void onError(Object e) {
      _log.debug('HTTP connection error: $e');
      finish();
      release();
      client.destroy();
    }

    if (sub != null) {
      sub
        ..onData(onData)
        ..onDone(onDone)
        ..onError(onError)
        ..resume();
    } else {
      sub = client.listen(onData, onDone: onDone, onError: onError);
    }
  }

  /// Index of the byte right after the blank line terminating the HTTP
  /// header block (`\r\n\r\n`), or -1 if not yet fully received.
  int _findHeaderEnd(Uint8List bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 0x0D &&
          bytes[i + 1] == 0x0A &&
          bytes[i + 2] == 0x0D &&
          bytes[i + 3] == 0x0A) {
        return i + 4;
      }
    }
    return -1;
  }

  /// **No connection counter any more.** It stood here and was a no-op —
  /// `++` and `--` lay in the same synchronous body, with no
  /// `await` between them, the counter never reached more than 1. It now counts the
  /// life cycle of the connection, in [handleConnection].
  void _handleRequest(Socket client, Uint8List bytes, int headerEnd) {
    {
      final headerBlock = ascii.decode(bytes.sublist(0, headerEnd), allowInvalid: true);
      final lines = headerBlock.split('\r\n');
      final requestLine = lines.isNotEmpty ? lines.first : '';
      final parts = requestLine.split(' ');
      if (parts.length < 2) {
        _sendResponse(client, 400);
        return;
      }

      final method = parts[0].toUpperCase();
      if (method != 'GET' && method != 'HEAD') {
        _sendResponse(client, 405);
        return;
      }

      final rawPath = parts[1];
      final path = rawPath.split('?').first;
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();

      if (segments.length == 1 && segments[0] == 'cleona') {
        _serveBootstrapWebApp(client, path, method);
        return;
      }
      if (segments.length == 3 && segments[0] == 'cleona' && segments[1] == 'binary') {
        if (!_knownPlatforms.contains(segments[2])) {
          _sendResponse(client, 404);
          _logRequest(method, path, 404, 0);
          return;
        }
        _serveBinary(client, path, method, segments[2]);
        return;
      }
      if (segments.length == 3 && segments[0] == 'cleona' && segments[1] == 'status') {
        _serveForeignStatus(client, path, method, segments[2]);
        return;
      }
      if (segments.length == 4 && segments[0] == 'cleona' && segments[1] == 'fragment') {
        final index = int.tryParse(segments[3]);
        if (index == null || !_knownPlatforms.contains(segments[2])) {
          _sendResponse(client, 404);
          _logRequest(method, path, 404, 0);
          return;
        }
        _serveFragment(client, path, method, segments[2], index);
        return;
      }

      _sendResponse(client, 404);
      _logRequest(method, path, 404, 0);
    }
  }

  void _serveBootstrapWebApp(Socket client, String path, String method) {
    final body = bootstrapWebApp;
    if (body == null) {
      _sendResponse(client, 404);
      _logRequest(method, path, 404, 0);
      return;
    }
    _sendResponse(client, 200,
        contentType: 'text/html; charset=utf-8',
        body: method == 'HEAD' ? null : body,
        bodyLength: body.length);
    _logRequest(method, path, 200, body.length);
  }

  void _serveBinary(Socket client, String path, String method, String platform) {
    String? filePath;
    try {
      filePath = binaryProvider?.call(platform);
    } catch (e) {
      _log.debug('binaryProvider threw for platform=$platform: $e');
      filePath = null;
    }
    if (filePath == null) {
      // §19.6.4: this node does not hold that platform. Ask the service to
      // acquire it; the visitor polls /cleona/status/<platform>. Gating,
      // rate limiting and storage caps live in the acquirer, not here.
      try {
        onForeignBinaryRequested?.call(platform);
      } catch (e) {
        _log.debug('onForeignBinaryRequested threw for $platform: $e');
      }
      _sendResponse(client, 404);
      _logRequest(method, path, 404, 0);
      return;
    }
    final ext = switch (platform) {
      'android' => '.apk',
      'windows' => '.exe',
      'macos'   => '.dmg',
      _         => '',
    };
    final mime = platform == 'android'
        ? 'application/vnd.android.package-archive'
        : 'application/octet-stream';
    try {
      final file = File(filePath);
      final fileLength = file.lengthSync();
      if (method == 'HEAD') {
        _sendResponse(client, 200,
            contentType: mime,
            bodyLength: fileLength,
            extraHeaders: {
              'Content-Disposition': 'attachment; filename="cleona$ext"',
            });
        _logRequest(method, path, 200, fileLength);
        return;
      }
      _streamFile(client, file, fileLength, mime, 'cleona$ext');
      _logRequest(method, path, 200, fileLength);
    } catch (e) {
      _log.debug('_serveBinary file streaming failed: $e');
      _sendResponse(client, 404);
      _logRequest(method, path, 404, 0);
    }
  }

  /// `GET /cleona/status/<platform>` — on-demand acquisition progress
  /// (§19.6.4). Always 200 with a JSON body so the browser can poll without
  /// special-casing errors; unknown platforms report `idle`.
  void _serveForeignStatus(
      Socket client, String path, String method, String platform) {
    Map<String, dynamic>? status;
    if (_knownPlatforms.contains(platform)) {
      try {
        status = foreignStatusProvider?.call(platform);
      } catch (e) {
        _log.debug('foreignStatusProvider threw for $platform: $e');
      }
    }
    final body = utf8.encode(jsonEncode(status ?? {'state': 'idle'}));
    if (method == 'HEAD') {
      _sendResponse(client, 200,
          contentType: 'application/json', bodyLength: body.length);
    } else {
      _sendResponse(client, 200,
          contentType: 'application/json', body: Uint8List.fromList(body));
    }
    _logRequest(method, path, 200, body.length);
  }

  void _streamFile(Socket client, File file, int fileLength, String mime,
      String filename) {
    final reason = _reasonPhrases[200] ?? 'OK';
    final header = StringBuffer()
      ..write('HTTP/1.1 200 $reason\r\n')
      ..write('Content-Type: $mime\r\n')
      ..write('Content-Length: $fileLength\r\n')
      ..write('Content-Disposition: attachment; filename="$filename"\r\n')
      ..write('Access-Control-Allow-Origin: *\r\n')
      ..write('Connection: close\r\n')
      ..write('\r\n');

    try {
      client.add(ascii.encode(header.toString()));
      const chunkSize = 65536;
      final raf = file.openSync();
      try {
        var remaining = fileLength;
        while (remaining > 0) {
          final toRead = remaining < chunkSize ? remaining : chunkSize;
          final chunk = raf.readSync(toRead);
          if (chunk.isEmpty) break;
          client.add(chunk);
          remaining -= chunk.length;
        }
      } finally {
        raf.closeSync();
      }
      client.flush().then((_) => client.close()).catchError((_) {}).whenComplete(() {
        final destroyDelay = Duration(
            seconds: fileLength > 0 ? (fileLength ~/ 500000).clamp(30, 600) : 30);
        Future.delayed(destroyDelay, () {
          try { client.destroy(); } catch (_) {}
        });
      });
    } catch (e) {
      _log.debug('_streamFile write failed: $e');
      try { client.destroy(); } catch (_) {}
    }
  }

  void _serveFragment(
      Socket client, String path, String method, String platform, int index) {
    Uint8List? body;
    try {
      body = fragmentProvider?.call(platform, index);
    } catch (e) {
      _log.debug('fragmentProvider threw for platform=$platform index=$index: $e');
      body = null;
    }
    if (body == null) {
      _sendResponse(client, 404);
      _logRequest(method, path, 404, 0);
      return;
    }
    _sendResponse(client, 200,
        contentType: 'application/octet-stream',
        body: method == 'HEAD' ? null : body,
        bodyLength: body.length);
    _logRequest(method, path, 200, body.length);
  }

  void _logRequest(String method, String path, int statusCode, int bodyLength) {
    _log.debug('HTTP $method $path -> $statusCode (${bodyLength}B)');
  }

  static const _reasonPhrases = {
    200: 'OK',
    400: 'Bad Request',
    404: 'Not Found',
    405: 'Method Not Allowed',
    503: 'Service Unavailable',
  };

  /// Builds and writes a raw HTTP/1.1 response, then closes the connection.
  /// No `Server`/`X-Powered-By` header — no version disclosure.
  void _sendResponse(
    Socket client,
    int statusCode, {
    String contentType = 'text/plain',
    Uint8List? body,
    int? bodyLength,
    Map<String, String>? extraHeaders,
  }) {
    final reason = _reasonPhrases[statusCode] ?? 'Error';
    final contentLength = bodyLength ?? body?.length ?? 0;

    final header = StringBuffer()
      ..write('HTTP/1.1 $statusCode $reason\r\n')
      ..write('Content-Type: $contentType\r\n')
      ..write('Content-Length: $contentLength\r\n')
      ..write('Access-Control-Allow-Origin: *\r\n')
      ..write('Connection: close\r\n');

    extraHeaders?.forEach((k, v) => header.write('$k: $v\r\n'));
    header.write('\r\n');

    try {
      client.add(ascii.encode(header.toString()));
      if (body != null) {
        const chunkSize = 65536;
        for (var i = 0; i < body.length; i += chunkSize) {
          client.add(body.sublist(i, i + chunkSize > body.length ? body.length : i + chunkSize));
        }
      }
      client.flush().then((_) => client.close()).catchError((_) {}).whenComplete(() {
        final destroyDelay = Duration(
            seconds: contentLength > 0 ? (contentLength ~/ 500000).clamp(30, 600) : 30);
        Future.delayed(destroyDelay, () {
          try { client.destroy(); } catch (_) {}
        });
      });
    } catch (e) {
      _log.debug('HTTP response write failed: $e');
      try {
        client.destroy();
      } catch (_) {}
    }
  }
}
