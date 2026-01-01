import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/erasure/reed_solomon.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex;
import 'package:cleona/core/update/binary_fragment_store.dart';

/// Encodes complete binaries into Reed-Solomon erasure fragments and stores
/// them in [BinaryFragmentStore], turning this node into a distribution
/// source for in-network binary updates (§19.6.2).
class BinarySeeder {
  final BinaryFragmentStore _store;
  final CLogger _log;

  BinarySeeder({required BinaryFragmentStore store, String? profileDir})
      : _store = store,
        _log = CLogger.get('bin-seeder', profileDir: profileDir);

  /// Per-platform Reed-Solomon parameters (§19.6.2).
  static const Map<String, ({int n, int k})> platformParams = {
    'android': (n: 30, k: 21),
    'linux': (n: 50, k: 35),
    'windows': (n: 50, k: 35),
    'macos': (n: 50, k: 35),
    'ios': (n: 40, k: 28),
  };

  /// Get the RS parameters for a platform. Falls back to default (N=10, K=7)
  /// for unknown platforms.
  static ({int n, int k}) paramsFor(String platform) {
    return platformParams[platform] ??
        (n: ReedSolomon.defaultN, k: ReedSolomon.defaultK);
  }

  /// Compute SHA-256 hash of the binary for the availability record.
  String computeHash(Uint8List binary) {
    return bytesToHex(SodiumFFI().sha256(binary));
  }

  /// Encode [binary] into erasure fragments and store them in the fragment
  /// store. Also stores the complete binary itself. Returns the number of
  /// fragments stored, or 0 on failure.
  ///
  /// If fragments for this platform/version already exist, skips encoding
  /// (idempotent). [maxFragments] limits how many fragments this node stores
  /// (§19.6.2: mobile=1-2, desktop=6-8, bootstrap=all). Pass null for all.
  Future<int> seed({
    required Uint8List binary,
    required String platform,
    required String version,
    int? maxFragments,
  }) async {
    try {
      final existing = await _store.availableFragments(platform, version);
      if (existing.isNotEmpty) {
        _log.debug('seed $platform/$version: already have '
            '${existing.length} fragments, skipping encode');
        return existing.length;
      }

      final params = paramsFor(platform);
      final hash = computeHash(binary);
      _log.info('seed $platform/$version: encoding ${binary.length}B '
          '(N=${params.n}, K=${params.k}, hash=$hash)');

      final sw = Stopwatch()..start();
      final rs = ReedSolomon.withParams(params.n, params.k);
      final fragments = rs.encode(binary);
      sw.stop();
      _log.info('seed $platform/$version: encoded ${fragments.length} '
          'fragments in ${sw.elapsedMilliseconds}ms');

      final storeCount = (maxFragments != null && maxFragments < fragments.length)
          ? maxFragments
          : fragments.length;

      for (var i = 0; i < storeCount; i++) {
        await _store.storeFragment(platform, version, i, fragments[i]);
      }

      _log.info('seed $platform/$version: stored $storeCount/'
          '${fragments.length} fragments');
      return storeCount;
    } catch (e) {
      _log.error('seed $platform/$version failed: $e');
      return 0;
    }
  }

  /// Check if this node has fragments worth seeding for the given
  /// platform/version.
  Future<bool> isSeeding(String platform, String version) async {
    if (await _store.hasComplete(platform, version)) return true;
    final fragments = await _store.availableFragments(platform, version);
    return fragments.isNotEmpty;
  }
}
