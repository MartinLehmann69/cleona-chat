import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/erasure/reed_solomon.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/update/binary_fragment_store.dart';
import 'package:cleona/core/update/install_source.dart';
import 'package:cleona/core/update/update_manifest.dart';

/// §19.6 — orchestrates in-network binary updates: checks a verified
/// [UpdateManifest] against the DHT binary tag, fetches erasure-coded
/// fragments from peers, assembles + verifies the binary, and hands a
/// ready-to-install path back to the caller. Pure state machine — no
/// network transport of its own (fetches happen via injected callback).
enum BinaryUpdateState {
  idle,
  checking,
  downloading,
  assembling,
  verifying,
  ready,
  failed,
}

/// Describes which fragments a particular node can serve.
class FragmentSource {
  final EndpointAddress address;
  final List<int> fragmentIndices;
  final bool hasFullBinary;

  const FragmentSource({
    required this.address,
    required this.fragmentIndices,
    required this.hasFullBinary,
  });
}

class BinaryUpdateManager {
  static const int _maxConcurrentFetches = 4;

  final BinaryFragmentStore _store;
  final UpdateChecker _checker;
  final CLogger _log;
  final String? _profileDir;

  BinaryUpdateState _state = BinaryUpdateState.idle;
  String? _targetVersion;
  String? _targetPlatform;
  double _progress = 0.0;
  String? _errorMessage;
  bool _cancelled = false;

  int _highestSeenMonotoneSeq = 0;

  void Function(BinaryUpdateState state, double progress)? onStateChanged;
  void Function(String version, String binaryPath)? onUpdateReady;

  BinaryUpdateManager({
    required BinaryFragmentStore store,
    required UpdateChecker checker,
    String? profileDir,
  })  : _store = store,
        _checker = checker,
        _profileDir = profileDir,
        _log = CLogger.get('bin-update', profileDir: profileDir);

  BinaryUpdateState get state => _state;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  String? get targetVersion => _targetVersion;

  /// Check for an available in-network update from a verified manifest.
  /// Returns true if [manifest] describes a newer version reachable via
  /// the in-network binary distribution path for [platform].
  Future<bool> checkForUpdate(
    UpdateManifest manifest,
    String currentVersion,
    String platform,
  ) async {
    _setState(BinaryUpdateState.checking, 0.0);
    try {
      if (!shouldUseInNetworkUpdate()) {
        _log.info('In-network updates disabled (Play Store install) — skipping');
        _setState(BinaryUpdateState.idle, 0.0);
        return false;
      }

      if (_checker.isDowngradeAttempt(manifest, _highestSeenMonotoneSeq)) {
        _log.warn('Rejecting manifest: monotoneSeq=${manifest.minMonotoneSeq} '
            '<= highestSeen=$_highestSeenMonotoneSeq');
        _setState(BinaryUpdateState.idle, 0.0);
        return false;
      }
      if (manifest.minMonotoneSeq != null &&
          manifest.minMonotoneSeq! > _highestSeenMonotoneSeq) {
        _highestSeenMonotoneSeq = manifest.minMonotoneSeq!;
      }

      final tag = manifest.dhtBinaryTag?[platform];
      if (tag == null) {
        _log.debug('No dhtBinaryTag for platform=$platform in manifest');
        _setState(BinaryUpdateState.idle, 0.0);
        return false;
      }

      if (!_checker.isNewer(manifest.version, currentVersion)) {
        _log.debug('Manifest v${manifest.version} not newer than $currentVersion');
        _setState(BinaryUpdateState.idle, 0.0);
        return false;
      }

      _targetVersion = manifest.version;
      _targetPlatform = platform;
      _log.info('In-network update available: v${manifest.version} for $platform');
      _setState(BinaryUpdateState.idle, 0.0);
      return true;
    } catch (e) {
      _fail('checkForUpdate failed: $e');
      return false;
    }
  }

  /// Fetch fragments from [sources] until K are available, then hand off to
  /// [assemble]. [fetchFragment] performs the actual network I/O.
  Future<void> startDownload({
    required String platform,
    required String version,
    required int n,
    required int k,
    required String expectedHash,
    required List<FragmentSource> sources,
    required Future<Uint8List?> Function(
            EndpointAddress address, String platform, int index)
        fetchFragment,
  }) async {
    _cancelled = false;
    _targetPlatform = platform;
    _targetVersion = version;
    _setState(BinaryUpdateState.downloading, 0.0);

    try {
      // Prefer a node that has the full binary — one shot, no reconstruction.
      final fullSource = sources.firstWhere(
        (s) => s.hasFullBinary,
        orElse: () => const FragmentSource(
            address: EndpointAddress('', 0), fragmentIndices: [], hasFullBinary: false),
      );
      if (fullSource.hasFullBinary) {
        _log.info('Fetching full binary from ${fullSource.address.ip}:${fullSource.address.port}');
        final data = await fetchFragment(fullSource.address, platform, -1);
        if (_cancelled) return;
        if (data != null) {
          await _store.storeComplete(platform, version, data);
          _setState(BinaryUpdateState.downloading, 1.0);
          return;
        }
        _log.warn('Full-binary fetch failed, falling back to fragments');
      }

      final have = (await _store.availableFragments(platform, version)).toSet();
      final needed = <int>[];
      for (var i = 0; i < n && have.length + needed.length < k; i++) {
        if (!have.contains(i)) needed.add(i);
      }

      // Map each needed fragment index to a source that can serve it.
      final plan = <int, EndpointAddress>{};
      for (final index in needed) {
        final source = sources.firstWhere(
          (s) => s.fragmentIndices.contains(index),
          orElse: () => const FragmentSource(
              address: EndpointAddress('', 0), fragmentIndices: [], hasFullBinary: false),
        );
        if (source.address.port != 0) {
          plan[index] = source.address;
        }
      }

      if (have.length + plan.length < k) {
        _fail('Not enough fragment sources: have=${have.length} planned=${plan.length} need=$k');
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
              await _store.storeFragment(platform, version, entry.key, data);
            } else {
              _log.warn('Fragment ${entry.key} fetch returned null');
            }
          } catch (e) {
            _log.warn('Fragment ${entry.key} fetch failed: $e');
          }
          completed++;
          _setState(BinaryUpdateState.downloading,
              total == 0 ? 1.0 : completed / total);
        }));
      }

      final gotCount = (await _store.availableFragments(platform, version)).length;
      if (gotCount < k) {
        _fail('Download incomplete: got $gotCount fragments, need $k');
        return;
      }
      _setState(BinaryUpdateState.downloading, 1.0);
    } catch (e) {
      _fail('startDownload failed: $e');
    }
  }

  /// Assemble the binary from downloaded fragments via Reed-Solomon decode.
  Future<Uint8List?> assemble(
    String platform,
    String version,
    int n,
    int k,
    int originalSize,
  ) async {
    _setState(BinaryUpdateState.assembling, 0.0);
    try {
      final existing = await _store.getComplete(platform, version);
      if (existing != null) {
        _setState(BinaryUpdateState.assembling, 1.0);
        return existing;
      }

      final available = await _store.availableFragments(platform, version);
      if (available.length < k) {
        _fail('Cannot assemble: have ${available.length} fragments, need $k');
        return null;
      }

      final fragments = <int, Uint8List>{};
      for (final index in available) {
        final data = await _store.getFragment(platform, version, index);
        if (data != null) fragments[index] = data;
        if (fragments.length >= k) break;
      }
      if (fragments.length < k) {
        _fail('Cannot assemble: only ${fragments.length} fragments loaded, need $k');
        return null;
      }

      final binary = n == ReedSolomon.defaultN && k == ReedSolomon.defaultK
          ? ReedSolomon().decode(fragments, originalSize)
          : ReedSolomon.decodeWithParams(fragments, originalSize, n, k);

      await _store.storeComplete(platform, version, binary);
      _setState(BinaryUpdateState.assembling, 1.0);
      return binary;
    } catch (e) {
      _fail('assemble failed: $e');
      return null;
    }
  }

  /// Verify assembled binary: SHA-256 hash against [expectedHash] (hex) and
  /// Ed25519 signature by the maintainer key over that hash.
  bool verify(
    Uint8List binary,
    String expectedHash,
    Uint8List maintainerSignature,
  ) {
    _setState(BinaryUpdateState.verifying, 0.0);
    try {
      final hash = SodiumFFI().sha256(binary);
      final hashHex = bytesToHex(hash);
      if (hashHex.toLowerCase() != expectedHash.toLowerCase()) {
        _fail('Hash mismatch: expected=$expectedHash got=$hashHex');
        return false;
      }

      final pubKey = hexToBytes(UpdateChecker.maintainerPublicKeyHex);
      final ok = SodiumFFI().verifyEd25519(hash, maintainerSignature, pubKey);
      if (!ok) {
        _fail('Signature verification failed');
        return false;
      }

      _setState(BinaryUpdateState.ready, 1.0);
      if (_targetVersion != null) {
        getVerifiedBinaryPath(_targetPlatform ?? '', _targetVersion!).then((path) {
          if (path != null) onUpdateReady?.call(_targetVersion!, path);
        });
      }
      return true;
    } catch (e) {
      _fail('verify failed: $e');
      return false;
    }
  }

  /// Path to the verified binary once assembled, for installation. Writes
  /// the stored complete binary out to a file so the caller (installer /
  /// package manager invocation) can reference it by path.
  Future<String?> getVerifiedBinaryPath(String platform, String version) async {
    final data = await _store.getComplete(platform, version);
    if (data == null) return null;
    try {
      final dir = Directory('$_updateDir/verified');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/cleona-$platform-$version.bin');
      await file.writeAsBytes(data, flush: true);
      return file.path;
    } catch (e) {
      _log.warn('getVerifiedBinaryPath failed: $e');
      return null;
    }
  }

  String get _updateDir => '${_profileDir ?? AppPaths.dataDir}/update';

  /// Whether to use in-network updates or redirect to Play Store.
  bool shouldUseInNetworkUpdate() {
    final source = InstallSourceDetector.cached;
    if (source == InstallSource.playStore) return false;
    return true;
  }

  /// Run housekeeping on the fragment store (called periodically by owner).
  Future<void> gc(String currentVersion, int budgetBytes) async {
    try {
      await _store.garbageCollect(currentVersion);
      await _store.enforceBudget(budgetBytes);
    } catch (e) {
      _log.warn('gc failed: $e');
    }
  }

  void cancel() {
    _cancelled = true;
    _setState(BinaryUpdateState.idle, 0.0);
  }

  void dispose() {
    _cancelled = true;
    onStateChanged = null;
    onUpdateReady = null;
  }

  void _setState(BinaryUpdateState state, double progress) {
    _state = state;
    _progress = progress;
    try {
      onStateChanged?.call(state, progress);
    } catch (_) {}
  }

  void _fail(String message) {
    _errorMessage = message;
    _log.error(message);
    _setState(BinaryUpdateState.failed, _progress);
  }
}
