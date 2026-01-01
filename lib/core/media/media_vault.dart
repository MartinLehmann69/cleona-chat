import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/constant_time.dart';
import 'package:cleona/core/crypto/media_cipher.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/media/media_store.dart';

/// The decrypting reader on `127.0.0.1` (S362, variant B).
///
/// ## Why it exists
///
/// Media are read via PATHS in this tree, and part of them by
/// FOREIGN programs. Before S362 (state `d4d1f680`) these were `Image.file`
/// (`chat_screen.dart:2915`, `:3507`, `:4465`),
/// `VideoPlayerController.file` (`:3222`), `just_audio.setFilePath`
/// (`:3330`), `ffprobe` (`:3349`), `ffplay` (`:3367`) and `ffmpeg`
/// (`voice_transcription_service.dart:345`). None of these tools ever learns
/// to read a `.cmenc` — but they all take an `http://` source.
///
/// Today the same places hold `Image.network`
/// (`chat_screen.dart:3584`, `:4543`), `VideoPlayerController.networkUrl`
/// (`:3263`), `just_audio.setUrl` (`:3381`), `ffprobe` (`:3402`), `ffplay`
/// (`:3422`) and `ffmpeg` (`voice_transcription_service.dart:354`) — all
/// via `_mediaUrl` or [urlFor].
///
/// The plaintext thus never reaches the disk: it arises frame by frame in
/// memory and goes over the loopback to the consumer.
///
/// ## The security question that had to be answered before building
///
/// **A listener on `127.0.0.1` is reachable by every other process on
/// the same device — on Android by every other app.** A
/// path that protects the media from the disk image and at the same time
/// offers them to every installed app over HTTP would be no gain but
/// a trade. Measured and decided:
///
/// 1. **Loopback only.** `HttpServer.bind(InternetAddress.loopbackIPv4,
///    0)`. No port to the outside (working rule 5). The port is
///    ephemeral — the operating system assigns it, it is not a secret
///    and is not treated as one either.
///
/// 2. **A path secret per process start.** 32 random bytes from
///    `randombytes_buf` (`SodiumFFI.randomBytes`), base64url, 43 characters.
///    It stands in the PATH, not in a header — only thus do
///    `Image.network` and `MediaExtractor.setDataSource` carry it along. It lives exactly
///    as long as the process; a restart invalidates every old URL.
///
/// 3. **Comparison in constant time** via `constantTimeEquals`
///    (`crypto/constant_time.dart:25`). A `==` on strings aborts
///    at the first difference and would reveal the secret character by
///    character via the response time — at 8000 requests per second over
///    the loopback that is not a theoretical attack.
///
/// 4. **No directory listing, no paths on the wire.** The
///    second path part is a 16-byte random identifier from a
///    process table, not a file name. Path traversal
///    (`../../.cleona/db.key`) is thus not fended off but **impossible**: there
///    is no way to pass a file name. `/` alone
///    answers 404 without a body.
///
/// 5. **No CORS, and the `Host` must be the loopback.** Without
///    `Access-Control-Allow-Origin` no web page reads the response. The
///    `Host` check defeats DNS rebinding: a page whose name resolves to
///    `127.0.0.1` carries its own name in the `Host` and
///    falls to 403 — even before the secret is checked.
///
/// 6. **Only `GET` and `HEAD`.** Everything else 405.
///
/// ### Does the secret end up in logs, argument lists, crash reports?
///
/// * **Logs:** no, and that is checked. [_log] only gets to see the
///   port and error texts, never the path and never the secret.
///   The guard `test/smoke/smoke_media_at_rest_guard.dart` searches for the
///   secret byte by byte across all files of the profile.
///
/// * **Argument lists:** yes, on the DESKTOP — and there it is without consequence.
///   `ffprobe`, `ffplay`, `ffmpeg` and `xclip` get the URL as
///   argument; on Linux every process of THE SAME user reads it in
///   `/proc/<pid>/cmdline`. But that gives it nothing it would not already
///   have: the same user reads `db.key` (`0600`, belonging to him) and
///   `.master_seed.keyring` and can thus open every file of the profile
///   anyway. The threat model of this work is the stolen
///   device, the disk image and the backup (S362 report section 3)
///   — not the separation of two processes of the same user.
///
///   On **Android**, where the neighbour is a different UID and the separation
///   thus actually carries, the question does not arise at all: there there is
///   NO `Process.run` consumer of a media path. Measured on
///   02.09.2026:
///   `_justAudioSupported = Platform.isAndroid || Platform.isIOS ||
///   Platform.isMacOS` (`chat_screen.dart:3355`) keeps `ffprobe`/`ffplay`
///   on the desktop branch; `xclip`/`wl-copy` stand behind
///   `Platform.isLinux` (`chat_screen.dart:904`); and `ffmpeg` only runs
///   when `platformAudioDecoder` is NULL
///   (`voice_transcription_service.dart:323`) — on Android it is set
///   and goes via `MediaExtractor.setDataSource`
///   (`MainActivity.kt:928`), which according to the Android contract takes "a file path or an
///   http URL". Moreover `/proc/<pid>/cmdline` of foreign apps has not been readable on
///   Android since N.
///
/// * **Crash reports:** the bug log channel (§9.5) sends logs.
///   Because the secret stands in no log, it stands in no
///   report either. The same guard covers both.
///
/// ## Seeking
///
/// `Range: bytes=a-b` is answered (206 + `Content-Range`), otherwise
/// video would be unusable: `video_player` requests exactly one
/// excerpt when seeking. Only the touched frames are decrypted —
/// that is why the memory peak stays at around 192 KiB, no matter how large the
/// file is and where one seeks to.
class MediaVault {
  MediaVault._();

  static final MediaVault instance = MediaVault._();

  /// Only created at [start], because the log directory is not settled
  /// before: this reader is process-wide, the directory is not.
  /// Without `profileDir` the logger would write into NO file — exactly that is what
  /// `check_clogger_profiledir.dart` caught here, and precisely the
  /// message "could not be started" would have been unfindable in the field.
  ///
  /// `late` and no fallback to `CLogger.get('mediavault')` without
  /// directory: such a fallback would look like a logger but would
  /// write into no file — exactly the state the gate reports. Every
  /// use lies behind [start], which sets it first thing; the listener
  /// does not even exist before.
  ///
  /// `late` (not `late final`) and guarded via [_logSet]: `start`
  /// can fail — if `HttpServer.bind` does not bind, `_server` stays
  /// null and the next attempt runs through this line again. A
  /// `late final` would then have thrown `LateInitializationError`, and
  /// precisely in the retry after an error.
  late CLogger _log;
  bool _logSet = false;

  HttpServer? _server;
  String? _token;
  int? _port;

  /// Identifier -> (plaintext path, content type). Only in memory, falls with
  /// the process.
  ///
  /// **Why the type travels along.** The URL carries no file extension — the
  /// second path part is a random identifier, so that no file name goes over
  /// the wire. A player that gets neither extension nor `Content-Type`
  /// must guess the container from the bytes; ExoPlayer otherwise chooses
  /// its extractor blindly. The type already stands in
  /// `UiMessage.mimeType` anyway and is not a secret.
  final Map<String, ({String path, String? mimeType})> _handles =
      <String, ({String path, String? mimeType})>{};

  /// Plaintext path -> identifier, so that the same file keeps the same URL across rebuilds of the
  /// UI. Without that `Image.network` would get a new URL on
  /// every `build` and would run past its own image cache.
  final Map<String, String> _byPath = <String, String>{};

  bool get isRunning => _server != null;
  int? get port => _port;

  /// Starts the reader. Calling it multiple times has no effect.
  ///
  /// [profileDir] only determines where logging goes — the reader
  /// itself is process-wide and serves every registered profile.
  Future<void> start({String? profileDir}) async {
    if (_server != null) return;
    if (!_logSet) {
      _log = CLogger.get('mediavault', profileDir: profileDir);
      _logSet = true;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    _server = server;
    _port = server.port;
    _token = base64Url.encode(SodiumFFI().randomBytes(32)).replaceAll('=', '');
    // The port may go into the log, the secret may not.
    _log.info('Media reader runs on 127.0.0.1:$_port (loopback only, '
        'path secret per process start)');
    unawaited(server.forEach(_handle).catchError((Object e) {
      _log.warn('Medienleser: Annahmeschleife endete: $e');
    }));
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _port = null;
    _token = null;
    _handles.clear();
    _byPath.clear();
    await s?.close(force: true);
  }

  /// Releases [plainPath] and returns the URL under which the plaintext
  /// can be read. `null` if the reader is not running, no
  /// key is registered or the ciphertext is missing — the caller then falls
  /// back to its substitute display (thumbnail, placeholder).
  String? urlFor(String plainPath, {String? mimeType}) {
    if (_server == null || _token == null) return null;
    if (!MediaStore.instance.existsEitherWay(plainPath)) return null;
    final handle = _byPath[plainPath] ??= _newHandle(plainPath, mimeType);
    return 'http://127.0.0.1:$_port/$_token/$handle';
  }

  String _newHandle(String plainPath, String? mimeType) {
    final h = SodiumFFI()
        .randomBytes(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _handles[h] = (path: plainPath, mimeType: mimeType);
    return h;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    // No CORS: without this header no foreign page reads the response.
    // No cache: the URL only lives as long as this process.
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    res.headers.set('X-Content-Type-Options', 'nosniff');

    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        await _deny(res, HttpStatus.methodNotAllowed);
        return;
      }

      // DNS rebinding: a page whose name points to 127.0.0.1 carries
      // its name in the `Host`. Checked BEFORE the secret, so that the
      // rejection reveals nothing about the secret.
      final host = req.headers.host;
      if (host != null && host != '127.0.0.1' && host != 'localhost') {
        await _deny(res, HttpStatus.forbidden);
        return;
      }

      final parts = req.uri.pathSegments;
      final token = _token;
      if (token == null || parts.length != 2) {
        await _deny(res, HttpStatus.forbidden);
        return;
      }
      if (!constantTimeEquals(
          Uint8List.fromList(utf8.encode(parts[0])),
          Uint8List.fromList(utf8.encode(token)))) {
        await _deny(res, HttpStatus.forbidden);
        return;
      }

      final entry = _handles[parts[1]];
      if (entry == null) {
        await _deny(res, HttpStatus.notFound);
        return;
      }

      final reader = MediaStore.instance.openEitherWay(entry.path);
      if (reader == null) {
        await _deny(res, HttpStatus.notFound);
        return;
      }
      try {
        await _serve(req, res, reader, entry.mimeType);
      } finally {
        reader.close();
      }
    } catch (e) {
      // The identifier may go into the log, the path and the secret may not.
      _log.warn('Media reader: request failed: $e');
      try {
        await _deny(res, HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  Future<void> _serve(HttpRequest req, HttpResponse res, MediaSource reader,
      String? mimeType) async {
    final total = reader.length;
    var start = 0;
    var end = total;
    var partial = false;

    final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      final r = _parseRange(rangeHeader, total);
      if (r == null) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await res.close();
        return;
      }
      start = r.$1;
      end = r.$2;
      partial = true;
    }

    res.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    res.headers.set(HttpHeaders.contentTypeHeader,
        mimeType ?? 'application/octet-stream');
    res.headers.contentLength = end - start;
    if (partial) {
      res.headers.set(
          HttpHeaders.contentRangeHeader, 'bytes $start-${end - 1}/$total');
    }

    if (req.method == 'HEAD') {
      await res.close();
      return;
    }

    // Frame by frame. `addStream` never holds more than one frame — that is
    // the fixed memory peak that justifies this whole construction.
    await res.addStream(reader.streamRange(start, end));
    await res.close();
  }

  /// `bytes=a-b`, `bytes=a-`, `bytes=-n`. Returns `[start, end)` or
  /// `null` if the range is not satisfiable. Multiple ranges are
  /// deliberately not served — no consumer in the tree requests them, and a
  /// half-built multipart path would be worse than none.
  static (int, int)? _parseRange(String header, int total) {
    if (!header.startsWith('bytes=')) return null;
    final spec = header.substring(6).trim();
    if (spec.contains(',')) return null;
    final dash = spec.indexOf('-');
    if (dash < 0) return null;
    final lhs = spec.substring(0, dash).trim();
    final rhs = spec.substring(dash + 1).trim();

    int start;
    int end;
    if (lhs.isEmpty) {
      final n = int.tryParse(rhs);
      if (n == null || n <= 0) return null;
      start = n >= total ? 0 : total - n;
      end = total;
    } else {
      final s = int.tryParse(lhs);
      if (s == null || s < 0 || s >= total) return null;
      start = s;
      if (rhs.isEmpty) {
        end = total;
      } else {
        final e = int.tryParse(rhs);
        if (e == null || e < s) return null;
        end = e + 1 > total ? total : e + 1;
      }
    }
    if (start >= end) return null;
    return (start, end);
  }

  Future<void> _deny(HttpResponse res, int status) async {
    res.statusCode = status;
    res.headers.contentLength = 0;
    await res.close();
  }
}
