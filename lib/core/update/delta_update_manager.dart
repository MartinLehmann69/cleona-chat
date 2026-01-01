import 'dart:typed_data';

import 'package:cleona/core/erasure/reed_solomon.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart'
    show EndpointAddress;
import 'package:cleona/core/update/binary_fragment_store.dart';
import 'package:cleona/core/update/binary_update_manager.dart'
    show FragmentSource, BinaryUpdateState;
import 'package:cleona/core/update/update_manifest.dart';

/// §19.6.3 — delta (differential) update mechanism. Instead of transferring
/// a full binary, downloads a small bsdiff-style patch that turns the
/// already-installed version into the target version. Falls back to the
/// full-binary path (via [BinaryUpdateManager]) whenever no delta is
/// available or the patch cannot be applied.
///
/// The maintainer publishes deltas for the two most recent generations
/// (V-1→V and V-2→V) — see [UpdateManifest.deltaBinaryTag]. Older installs
/// simply fall back to a full binary download.
///
/// Storage reuses [BinaryFragmentStore], with delta patches kept under a
/// synthetic "delta-" version directory so they never collide with full
/// binaries of the same platform (e.g. `delta-3.1.124-from-3.1.123`).
class DeltaUpdateManager {
  static const int _maxConcurrentFetches = 4;

  final BinaryFragmentStore _store;
  final CLogger _log;

  BinaryUpdateState _state = BinaryUpdateState.idle;
  double _progress = 0.0;
  String? _errorMessage;
  bool _cancelled = false;

  DeltaUpdateManager({
    required BinaryFragmentStore store,
    required CLogger log,
  })  : _store = store,
        _log = log;

  BinaryUpdateState get state => _state;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;

  /// Synthetic version directory used to store a delta patch's fragments,
  /// distinct from any real full-binary version directory.
  static String deltaVersionTag(String fromVersion, String toVersion) =>
      'delta-$toVersion-from-$fromVersion';

  /// Check if a delta update is available for [manifest] from
  /// [currentVersion] on [platform]. Returns the `fromVersion` string that
  /// should be used to request the patch, or null if no delta path exists
  /// (caller should fall back to a full binary download).
  String? findDeltaPath({
    required UpdateManifest manifest,
    required String currentVersion,
    required String platform,
  }) {
    final perPlatform = manifest.deltaBinaryTag?[platform];
    if (perPlatform == null || perPlatform.isEmpty) {
      _log.debug('No deltaBinaryTag for platform=$platform in manifest');
      return null;
    }
    if (!perPlatform.containsKey(currentVersion)) {
      _log.debug('No delta path from $currentVersion for platform=$platform '
          '(available: ${perPlatform.keys.toList()})');
      return null;
    }
    _log.info('Delta path found: $currentVersion -> ${manifest.version} '
        'for $platform');
    return currentVersion;
  }

  /// Download delta-patch fragments from the DHT. Mirrors
  /// [BinaryUpdateManager.startDownload], but writes into the synthetic
  /// delta version directory instead of a real binary version directory.
  Future<void> downloadDelta({
    required String platform,
    required String fromVersion,
    required String toVersion,
    required int n,
    required int k,
    required String expectedDeltaHash,
    required List<FragmentSource> sources,
    required Future<Uint8List?> Function(
            EndpointAddress address, String platform, int index)
        fetchFragment,
  }) async {
    _cancelled = false;
    _setState(BinaryUpdateState.downloading, 0.0);
    final versionTag = deltaVersionTag(fromVersion, toVersion);

    try {
      final fullSource = sources.firstWhere(
        (s) => s.hasFullBinary,
        orElse: () => const FragmentSource(
            address: EndpointAddress('', 0),
            fragmentIndices: [],
            hasFullBinary: false),
      );
      if (fullSource.hasFullBinary) {
        _log.info('Fetching delta patch in one shot from '
            '${fullSource.address.ip}:${fullSource.address.port}');
        final data = await fetchFragment(fullSource.address, platform, -1);
        if (_cancelled) return;
        if (data != null) {
          await _store.storeComplete(platform, versionTag, data);
          _setState(BinaryUpdateState.downloading, 1.0);
          return;
        }
        _log.warn('Full delta-patch fetch failed, falling back to fragments');
      }

      final have = (await _store.availableFragments(platform, versionTag)).toSet();
      final needed = <int>[];
      for (var i = 0; i < n && have.length + needed.length < k; i++) {
        if (!have.contains(i)) needed.add(i);
      }

      final plan = <int, EndpointAddress>{};
      for (final index in needed) {
        final source = sources.firstWhere(
          (s) => s.fragmentIndices.contains(index),
          orElse: () => const FragmentSource(
              address: EndpointAddress('', 0),
              fragmentIndices: [],
              hasFullBinary: false),
        );
        if (source.address.port != 0) {
          plan[index] = source.address;
        }
      }

      if (have.length + plan.length < k) {
        _fail('Not enough delta fragment sources: have=${have.length} '
            'planned=${plan.length} need=$k');
        return;
      }

      var completed = 0;
      final total = plan.length;
      final entries = plan.entries.toList();
      for (var i = 0; i < entries.length; i += _maxConcurrentFetches) {
        if (_cancelled) return;
        final batch = entries.skip(i).take(_maxConcurrentFetches);
        await Future.wait(batch.map((entry) async {
          if (_cancelled) return;
          try {
            final data = await fetchFragment(entry.value, platform, entry.key);
            if (data != null) {
              await _store.storeFragment(platform, versionTag, entry.key, data);
            } else {
              _log.warn('Delta fragment ${entry.key} fetch returned null');
            }
          } catch (e) {
            _log.warn('Delta fragment ${entry.key} fetch failed: $e');
          }
          completed++;
          _setState(BinaryUpdateState.downloading,
              total == 0 ? 1.0 : completed / total);
        }));
      }

      final gotCount = (await _store.availableFragments(platform, versionTag)).length;
      if (gotCount < k) {
        _fail('Delta download incomplete: got $gotCount fragments, need $k');
        return;
      }
      _setState(BinaryUpdateState.downloading, 1.0);
    } catch (e) {
      _fail('downloadDelta failed: $e');
    }
  }

  /// Assemble a downloaded delta patch from its fragments via Reed-Solomon
  /// decode, same pattern as [BinaryUpdateManager.assemble].
  Future<Uint8List?> _assembleDelta({
    required String platform,
    required String fromVersion,
    required String toVersion,
    required int n,
    required int k,
    required int originalSize,
  }) async {
    final versionTag = deltaVersionTag(fromVersion, toVersion);
    _setState(BinaryUpdateState.assembling, 0.0);
    try {
      final existing = await _store.getComplete(platform, versionTag);
      if (existing != null) {
        _setState(BinaryUpdateState.assembling, 1.0);
        return existing;
      }

      final available = await _store.availableFragments(platform, versionTag);
      if (available.length < k) {
        _fail('Cannot assemble delta: have ${available.length} fragments, need $k');
        return null;
      }

      final fragments = <int, Uint8List>{};
      for (final index in available) {
        final data = await _store.getFragment(platform, versionTag, index);
        if (data != null) fragments[index] = data;
        if (fragments.length >= k) break;
      }
      if (fragments.length < k) {
        _fail('Cannot assemble delta: only ${fragments.length} fragments loaded, need $k');
        return null;
      }

      final patch = n == ReedSolomon.defaultN && k == ReedSolomon.defaultK
          ? ReedSolomon().decode(fragments, originalSize)
          : ReedSolomon.decodeWithParams(fragments, originalSize, n, k);

      await _store.storeComplete(platform, versionTag, patch);
      _setState(BinaryUpdateState.assembling, 1.0);
      return patch;
    } catch (e) {
      _fail('assembleDelta failed: $e');
      return null;
    }
  }

  /// Apply a bsdiff-style delta patch to [baseBinary] to produce the target
  /// binary.
  ///
  /// PLACEHOLDER: bsdiff/bspatch requires a native library
  /// (`libcleona_bsdiff`) that does not exist yet. Until it is built and
  /// wired up via FFI, this always logs and returns null so callers fall
  /// back to the full-binary update path.
  Future<Uint8List?> applyDelta({
    required Uint8List baseBinary,
    required Uint8List deltaPatch,
  }) async {
    _log.info('bsdiff not available — delta updates require libcleona_bsdiff');
    return null;
  }

  /// Full delta-update flow: locate a delta path, download + assemble the
  /// patch, apply it against the currently installed binary, and return the
  /// resulting binary. Returns null at any step that cannot be completed —
  /// the caller should then fall back to a full binary update via
  /// [BinaryUpdateManager].
  Future<Uint8List?> tryDeltaUpdate({
    required UpdateManifest manifest,
    required String currentVersion,
    required String platform,
    required int n,
    required int k,
    required String expectedDeltaHash,
    required int deltaOriginalSize,
    required List<FragmentSource> sources,
    required Future<Uint8List?> Function(
            EndpointAddress address, String platform, int index)
        fetchFragment,
  }) async {
    try {
      final fromVersion = findDeltaPath(
        manifest: manifest,
        currentVersion: currentVersion,
        platform: platform,
      );
      if (fromVersion == null) return null;

      final baseBinary = await _store.getComplete(platform, currentVersion);
      if (baseBinary == null) {
        _log.warn('No stored base binary for $platform/$currentVersion — '
            'cannot apply delta, falling back to full binary');
        return null;
      }

      await downloadDelta(
        platform: platform,
        fromVersion: fromVersion,
        toVersion: manifest.version,
        n: n,
        k: k,
        expectedDeltaHash: expectedDeltaHash,
        sources: sources,
        fetchFragment: fetchFragment,
      );
      if (_state == BinaryUpdateState.failed || _cancelled) return null;

      final deltaPatch = await _assembleDelta(
        platform: platform,
        fromVersion: fromVersion,
        toVersion: manifest.version,
        n: n,
        k: k,
        originalSize: deltaOriginalSize,
      );
      if (deltaPatch == null) return null;

      final patched = await applyDelta(
        baseBinary: baseBinary,
        deltaPatch: deltaPatch,
      );
      if (patched == null) {
        _log.info('Delta patch application unavailable — caller should '
            'fall back to full binary download');
        return null;
      }

      _setState(BinaryUpdateState.ready, 1.0);
      return patched;
    } catch (e) {
      _fail('tryDeltaUpdate failed: $e');
      return null;
    }
  }

  void cancel() {
    _cancelled = true;
    _setState(BinaryUpdateState.idle, 0.0);
  }

  void dispose() {
    _cancelled = true;
  }

  void _setState(BinaryUpdateState state, double progress) {
    _state = state;
    _progress = progress;
  }

  void _fail(String message) {
    _errorMessage = message;
    _log.error(message);
    _setState(BinaryUpdateState.failed, _progress);
  }
}
