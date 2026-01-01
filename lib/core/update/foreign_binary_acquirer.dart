/// On-demand acquisition of a binary for a platform this node does not run
/// (Architecture §19.6.4).
///
/// Why this exists: an invite link points at the INVITER's node, not at a
/// bootstrap. A node self-seeds only its own platform, so a cross-platform
/// invite (Android inviter, Linux visitor) hits a 404 on
/// `GET /cleona/binary/linux` and dead-ends — the visitor is pushed to the
/// external `f=` fallback, i.e. exactly the gatekeeper §19.6 exists to avoid.
/// This component lets the serving node fetch the missing platform's binary
/// from the network, verify it against the maintainer-signed manifest, and
/// serve it.
///
/// Deliberately kept OUT of [BinaryUpdateManager]:
///   * That manager carries a single shared mutable state (`_state`,
///     `_targetPlatform`, `_targetVersion`, `_progress`, `_cancelled`). Two
///     concurrent acquisitions for different platforms would corrupt each
///     other's status, and `cancel()` would kill both.
///   * On a successful `verify()` it fires `onUpdateReady` and copies the
///     result into `update/verified/`, which feeds THIS node's installer. A
///     foreign binary must never reach that path — an Android APK is a ZIP,
///     and the desktop installer's is-zip branch would happily unpack it over
///     the application directory.
///
/// Always active: there is no off switch. The acquisition is bounded instead
/// of gated — one at a time node-wide, one foreign binary stored, 24 h TTL,
/// excluded from the bootstrap storage-budget exemption — and everything it
/// fetches is verified against the maintainer-signed manifest before it is
/// stored or served.
///
/// Full binaries only: sources advertising `hasFullBinary` are used, Reed-
/// Solomon reassembly is not attempted. A node holding a foreign platform's
/// complete binary is precisely what we are looking for (bootstrap-class
/// nodes hold all platforms, §19.6.1 principle 5), and skipping reassembly
/// avoids both the shared-state problem above and the padding-trim size
/// dependency.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/network/rendezvous/binary_rendezvous_manager.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart'
    show EndpointAddress;
import 'package:cleona/core/update/binary_fetch_client.dart';
import 'package:cleona/core/update/binary_fragment_store.dart';
import 'package:cleona/core/update/update_manifest.dart';

/// Platforms a visitor may request. The path segment reaches the fragment
/// store, so it is validated against this list rather than interpolated.
const List<String> kAcquirablePlatforms = [
  'android',
  'linux',
  'windows',
  'macos',
  'ios',
];

/// At most one foreign-platform binary is kept on disk at a time.
const int kMaxStoredForeignPlatforms = 1;

/// A foreign binary is evicted this long after it was acquired.
const Duration kForeignBinaryTtl = Duration(hours: 24);

/// After a failed acquisition, the same platform is not retried for this long.
const Duration kForeignAcquireCooldown = Duration(minutes: 10);

/// Marker file written next to a foreign binary so the GC can tell it apart
/// from this node's own seeded platform.
const String _onDemandMarker = '.ondemand';

enum ForeignAcquireState { idle, resolving, downloading, verifying, ready, failed }

class ForeignAcquireStatus {
  final ForeignAcquireState state;
  final double progress;
  final String? error;

  const ForeignAcquireStatus(this.state, {this.progress = 0.0, this.error});

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'progress': progress,
        if (error != null) 'error': error,
      };
}

class ForeignBinaryAcquirer {
  final BinaryFragmentStore _store;
  final BinaryFetchClient _fetch;
  final BinaryRendezvousManager? Function() _rendezvous;
  final CLogger _log;

  final Map<String, ForeignAcquireStatus> _status = {};
  final Map<String, DateTime> _cooldownUntil = {};
  Future<bool>? _inFlight;
  String? _inFlightPlatform;

  /// Injected clock so tests can drive TTL and cooldown without sleeping.
  final DateTime Function() _now;

  ForeignBinaryAcquirer({
    required BinaryFragmentStore store,
    required BinaryFetchClient fetchClient,
    required BinaryRendezvousManager? Function() rendezvous,
    required String profileDir,
    CLogger? logger,
    DateTime Function()? now,
  })  : _fetch = fetchClient,
        _store = store,
        _rendezvous = rendezvous,
        _log = logger ?? CLogger.get('foreign-bin', profileDir: profileDir),
        _now = now ?? DateTime.now;

  // --- Status --------------------------------------------------------------

  ForeignAcquireStatus statusFor(String platform) =>
      _status[platform] ?? const ForeignAcquireStatus(ForeignAcquireState.idle);

  void _set(String platform, ForeignAcquireState s,
      {double progress = 0.0, String? error}) {
    _status[platform] = ForeignAcquireStatus(s, progress: progress, error: error);
  }

  // --- Acquisition ---------------------------------------------------------

  /// Kicks off acquisition for [platform] if allowed. Returns immediately;
  /// callers poll [statusFor]. Never throws.
  void requestAcquire(String platform, UpdateManifest? manifest) {
    if (!kAcquirablePlatforms.contains(platform)) {
      _log.debug('requestAcquire: unknown platform "$platform" — ignored');
      return;
    }
    if (manifest == null) {
      _set(platform, ForeignAcquireState.failed,
          error: 'No signed update manifest available on this node yet.');
      return;
    }
    if (_store.hasCompleteSync(platform, manifest.version)) {
      _set(platform, ForeignAcquireState.ready, progress: 1.0);
      return;
    }
    final until = _cooldownUntil[platform];
    if (until != null && _now().isBefore(until)) {
      _set(platform, ForeignAcquireState.failed,
          error: 'Recently failed — not retrying yet.');
      return;
    }
    // One acquisition at a time, node-wide.
    if (_inFlight != null) {
      if (_inFlightPlatform != platform) {
        _set(platform, ForeignAcquireState.failed,
            error: 'This node is already fetching another platform.');
      }
      return;
    }
    _inFlightPlatform = platform;
    _inFlight = _acquire(platform, manifest).whenComplete(() {
      _inFlight = null;
      _inFlightPlatform = null;
    });
  }

  Future<bool> _acquire(String platform, UpdateManifest manifest) async {
    final version = manifest.version;
    final expectedHash = manifest.binaryHashes?[platform];
    final signatureB64 = manifest.binarySignatures?[platform];
    final expectedSize = manifest.binarySizes?[platform];
    if (expectedHash == null || signatureB64 == null || expectedSize == null) {
      return _fail(platform,
          'The signed manifest carries no hash/signature/size for $platform.');
    }
    final Uint8List signature;
    try {
      signature = base64Decode(signatureB64);
    } catch (e) {
      return _fail(platform, 'Malformed signature in manifest for $platform.');
    }

    _set(platform, ForeignAcquireState.resolving);
    final brm = _rendezvous();
    if (brm == null) {
      return _fail(platform, 'Binary discovery is not available on this node.');
    }

    List<ResolvedBinaryEndpoint> endpoints;
    try {
      endpoints = await brm.resolve(platform);
    } catch (e) {
      return _fail(platform, 'Could not look up sources: $e');
    }

    final sources = <EndpointAddress>[];
    for (final ep in endpoints) {
      if (!ep.hasFullBinary) continue;
      if (ep.version != version) continue;
      sources.addAll(ep.addresses);
    }
    if (sources.isEmpty) {
      return _fail(platform,
          'No node currently offers a complete $platform binary for v$version.');
    }

    _set(platform, ForeignAcquireState.downloading);
    for (final addr in sources) {
      Uint8List? bytes;
      try {
        bytes = await _fetch.fetch(addr, platform, -1, expectedSize: expectedSize);
      } catch (e) {
        _log.debug('fetch from ${addr.ip}:${addr.port} failed: $e');
        continue;
      }
      if (bytes == null || bytes.length != expectedSize) continue;

      _set(platform, ForeignAcquireState.verifying, progress: 0.9);
      final hash = SodiumFFI().sha256(bytes);
      if (bytesToHex(hash).toLowerCase() != expectedHash.toLowerCase()) {
        _log.warn('Hash mismatch for $platform from ${addr.ip} — discarded');
        continue;
      }
      final pk = hexToBytes(UpdateChecker.maintainerPublicKeyHex);
      if (!SodiumFFI().verifyEd25519(hash, signature, pk)) {
        _log.warn('Maintainer signature invalid for $platform — discarded');
        continue;
      }

      try {
        await _evictOtherForeign(platform);
        await _store.storeComplete(platform, version, bytes);
        _markOnDemand(platform, version);
      } catch (e) {
        return _fail(platform, 'Could not store the downloaded binary: $e');
      }
      _set(platform, ForeignAcquireState.ready, progress: 1.0);
      _log.info('Acquired $platform v$version on demand '
          '(${bytes.length} bytes) from ${addr.ip}:${addr.port}');
      return true;
    }
    return _fail(platform, 'No source delivered a verifiable $platform binary.');
  }

  bool _fail(String platform, String message) {
    _cooldownUntil[platform] = _now().add(kForeignAcquireCooldown);
    _set(platform, ForeignAcquireState.failed, error: message);
    _log.debug('Foreign acquire failed ($platform): $message');
    return false;
  }

  // --- On-demand bookkeeping ----------------------------------------------

  Directory _versionDir(String platform, String version) =>
      File(_store.completePath(platform, version)).parent;

  void _markOnDemand(String platform, String version) {
    try {
      final f = File('${_versionDir(platform, version).path}/$_onDemandMarker');
      f.writeAsStringSync(_now().toUtc().toIso8601String());
    } catch (e) {
      _log.debug('Could not write on-demand marker: $e');
    }
  }

  /// True when this platform/version was fetched on demand rather than
  /// self-seeded. The GC uses it to keep foreign binaries out of the
  /// bootstrap-budget exemption and to evict them on TTL.
  bool isOnDemand(String platform, String version) {
    try {
      return File('${_versionDir(platform, version).path}/$_onDemandMarker')
          .existsSync();
    } catch (_) {
      return false;
    }
  }

  DateTime? _acquiredAt(String platform, String version) {
    try {
      final f = File('${_versionDir(platform, version).path}/$_onDemandMarker');
      if (!f.existsSync()) return null;
      return DateTime.tryParse(f.readAsStringSync().trim())?.toLocal();
    } catch (_) {
      return null;
    }
  }

  /// All (platform, version) pairs currently held as on-demand acquisitions.
  List<(String, String)> storedOnDemand() {
    final out = <(String, String)>[];
    for (final p in kAcquirablePlatforms) {
      for (final v in _store.storedVersionsSync(p)) {
        if (isOnDemand(p, v)) out.add((p, v));
      }
    }
    return out;
  }

  Future<void> _evictOtherForeign(String keepPlatform) async {
    final held = storedOnDemand();
    // Keep at most kMaxStoredForeignPlatforms-1 others, so that adding the new
    // one lands exactly on the cap.
    final others = held.where((e) => e.$1 != keepPlatform).toList();
    final overBy = others.length - (kMaxStoredForeignPlatforms - 1);
    for (var i = 0; i < overBy && i < others.length; i++) {
      await _deleteForeign(others[i].$1, others[i].$2);
    }
  }

  Future<void> _deleteForeign(String platform, String version) async {
    try {
      await _store.deleteVersion(platform, version);
      _log.info('Evicted on-demand binary $platform v$version');
    } catch (e) {
      _log.debug('Eviction failed for $platform v$version: $e');
    }
  }

  /// Drops on-demand binaries older than [kForeignBinaryTtl]. Awaited by the
  /// hourly binary GC before it decides the storage budget, so the budget sees
  /// the post-eviction state.
  Future<int> evictExpired() async {
    var n = 0;
    for (final (platform, version) in storedOnDemand()) {
      final at = _acquiredAt(platform, version);
      if (at == null) continue;
      if (_now().difference(at) < kForeignBinaryTtl) continue;
      await _deleteForeign(platform, version);
      n++;
    }
    return n;
  }
}
