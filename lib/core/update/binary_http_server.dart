import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/network/clogger.dart';

/// §19.6.6 — Embedded HTTP server for censorship-resistant binary
/// distribution. Serves the bootstrap web app and binary/fragment
/// downloads over plain HTTP on the shared UDP/TLS TCP port.
///
/// Does NOT bind its own socket: [Transport] First-Byte-Sniffs incoming
/// TCP connections (`GET `/`HEAD` vs. `0x16 0x03` TLS ClientHello) and
/// hands HTTP connections to [handleConnection].
class BinaryHttpServer {
  static const _requestTimeout = Duration(seconds: 10);
  static const _maxRequestLineBytes = 8192;
  static const _maxActiveConnections = 3;

  final CLogger _log;
  bool _enabled = true;
  int _activeConnections = 0;

  /// Static HTML+JS served at GET /cleona.
  Uint8List? bootstrapWebApp;

  /// File path for `GET /cleona/binary/<platform>` (streamed in 64KB chunks).
  String? Function(String platform)? binaryProvider;

  /// Single fragment for `GET /cleona/fragment/<platform>/<index>`.
  Uint8List? Function(String platform, int index)? fragmentProvider;

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
      client.destroy();
    }

    void onError(Object e) {
      _log.debug('HTTP connection error: $e');
      finish();
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

  void _handleRequest(Socket client, Uint8List bytes, int headerEnd) {
    if (_activeConnections >= _maxActiveConnections) {
      _sendResponse(client, 503);
      return;
    }
    _activeConnections++;

    try {
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
        _serveBinary(client, path, method, segments[2]);
        return;
      }
      if (segments.length == 4 && segments[0] == 'cleona' && segments[1] == 'fragment') {
        final index = int.tryParse(segments[3]);
        if (index == null) {
          _sendResponse(client, 404);
          _logRequest(method, path, 404, 0);
          return;
        }
        _serveFragment(client, path, method, segments[2], index);
        return;
      }

      _sendResponse(client, 404);
      _logRequest(method, path, 404, 0);
    } finally {
      _activeConnections--;
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
