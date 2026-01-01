import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart'
    show EndpointAddress;

/// HTTP client for fetching binaries/fragments from other Cleona nodes'
/// embedded HTTP servers (§19.6.6). Used as the `fetchFragment` callback
/// for [BinaryUpdateManager.startDownload] / [DeltaUpdateManager.downloadDelta].
///
/// Talks plain HTTP (no TLS) — the same trust model as the rest of §19.6:
/// transport integrity doesn't matter here because the assembled binary is
/// verified independently (SHA-256 hash + Ed25519 maintainer signature)
/// before it is ever installed or seeded onward.
class BinaryFetchClient {
  /// Connection + response timeout for individual fragment fetches.
  static const Duration kFetchTimeout = Duration(seconds: 30);

  final CLogger _log;
  final HttpClient _client;

  BinaryFetchClient({String? profileDir})
      : _log = CLogger.get('bin-fetch', profileDir: profileDir),
        _client = HttpClient()
          ..connectionTimeout = kFetchTimeout
          ..idleTimeout = kFetchTimeout;

  /// Fetch a fragment (or complete binary when [index] == -1) from [address].
  /// Returns the raw bytes, or null on failure (timeout, HTTP error, etc.).
  Future<Uint8List?> fetch(
      EndpointAddress address, String platform, int index) async {
    if (address.ip.isEmpty || address.port == 0) return null;

    final host = address.ip.contains(':') ? '[${address.ip}]' : address.ip;
    final path = index == -1
        ? '/cleona/binary/$platform'
        : '/cleona/fragment/$platform/$index';
    final url = 'http://$host:${address.port}$path';

    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(url);
      final request = await _client.getUrl(uri).timeout(kFetchTimeout);
      final response = await request.close().timeout(kFetchTimeout);

      if (response.statusCode != 200) {
        _log.debug('fetch $url -> HTTP ${response.statusCode}');
        await response.drain<void>();
        return null;
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(kFetchTimeout)) {
        builder.add(chunk);
      }
      final bytes = builder.toBytes();
      sw.stop();
      _log.info('fetch $platform#$index from $host:${address.port} -> '
          '${bytes.length}B in ${sw.elapsedMilliseconds}ms');
      return bytes;
    } catch (e) {
      sw.stop();
      _log.debug('fetch $url failed after ${sw.elapsedMilliseconds}ms: $e');
      return null;
    }
  }

  void dispose() {
    _client.close(force: true);
  }
}
