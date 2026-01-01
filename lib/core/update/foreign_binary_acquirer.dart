/// On-demand acquisition of a binary for a platform this node does not run
/// (v4_2 §26.6.3 "Demand-driven foreign-platform fetch").
///
/// Why this exists: an invite link points at the INVITER's node, not at a
/// bootstrap. A node keeps only its own platform, so a cross-platform
/// invite (Android inviter, Linux visitor) hits a 404 on
/// `GET /cleona/binary/linux` and dead-ends — the visitor is pushed to the
/// external `f=` fallback, i.e. exactly the gatekeeper §26.6 exists to avoid.
/// This component lets the serving node fetch the missing platform's binary
/// from the network, verify it against the maintainer-signed manifest, and
/// serve it.
///
/// Where it comes from (V9 A1, owner decision 08.10.2026): the same
/// in-network collection as the node's own update — the object named by the
/// manifest's hash for that platform, asked of the node's holders
/// ([UpdateCarrier.foreignFetch]). Until then it looked the platform up on
/// Nostr relays (`BinaryRendezvousManager`, a 4-hour republish) and fetched
/// it over HTTP; §26.6.4 says the binary distribution uses no external
/// rendezvous channel, and that path is gone.
///
/// Deliberately kept OUT of [BinaryUpdateManager] and the update target:
///   * The carrier fetches it with a partial state of its own; it never
///     becomes the update target, never deletes the target's state.
///   * A foreign binary must never reach `update/verified/` — an Android APK
///     is a ZIP, and the desktop installer's is-zip branch would happily
///     unpack it over the application directory. It goes to the fragment
///     store under its platform, marked `.ondemand`.
///
/// Always active: there is no off switch. The acquisition is bounded instead
/// of gated — one at a time node-wide, one foreign binary stored, 24 h TTL,
/// excluded from the bootstrap storage-budget exemption — and everything it
/// fetches is verified against the maintainer-signed manifest before it is
/// stored or served.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_sha256.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/update/update_binary_store.dart';
import 'package:cleona/core/update/update_carrier.dart';
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

/// The share of the progress bar that collecting fills; checking the hash
/// and the signature takes the rest (the visitor page, §26.6.5).
const double kForeignCollectShare = 0.9;

/// Marker file written next to a foreign binary so the GC can tell it apart
/// from this node's own seeded platform.
const String _onDemandMarker = '.ondemand';

enum ForeignAcquireState { idle, downloading, verifying, ready, failed }

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
  final UpdateBinaryStore _store;

  /// The update carrier of the delivery layer — set after the host starts,
  /// hence a function; `null` until then.
  final UpdateCarrier? Function() _carrier;
  final CLogger _log;

  final Map<String, ForeignAcquireStatus> _status = {};
  final Map<String, DateTime> _cooldownUntil = {};
  Future<bool>? _inFlight;
  String? _inFlightPlatform;

  /// The object being collected for [_inFlightPlatform] — its progress is
  /// read off the carrier's partial state when the status is asked.
  Uint8List? _inFlightObject;

  /// Injected clock so tests can drive TTL and cooldown without sleeping.
  final DateTime Function() _now;

  /// The key the binary signatures are checked against — the maintainer's;
  /// injectable so a smoke can sign a test object with its own pair.
  final Uint8List _maintainerKey;

  ForeignBinaryAcquirer({
    required this._store,
    required this._carrier,
    required String profileDir,
    CLogger? logger,
    DateTime Function()? now,
    Uint8List? maintainerKey,
  })  : _log = logger ?? CLogger.get('foreign-bin', profileDir: profileDir),
        _now = now ?? DateTime.now,
        _maintainerKey = maintainerKey ??
            hexToBytes(UpdateChecker.maintainerPublicKeyHex);

  // --- Status --------------------------------------------------------------

  /// While collecting, the progress is read off the carrier's partial state
  /// of the object (S407-N5): until then it stood at 0 until the check set
  /// [kForeignCollectShare]. Read on asking — the visitor page asks; no
  /// clock and no packet of its own.
  ForeignAcquireStatus statusFor(String platform) {
    final s = _status[platform] ??
        const ForeignAcquireStatus(ForeignAcquireState.idle);
    final object = _inFlightObject;
    if (s.state != ForeignAcquireState.downloading ||
        platform != _inFlightPlatform ||
        object == null) {
      return s;
    }
    final fraction = _carrier()?.foreignProgress(object);
    if (fraction == null) return s;
    return ForeignAcquireStatus(ForeignAcquireState.downloading,
        progress: kForeignCollectShare * fraction.clamp(0.0, 1.0));
  }

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

    final Uint8List object;
    try {
      object = hexToBytes(expectedHash);
    } catch (e) {
      return _fail(platform, 'Malformed hash in manifest for $platform.');
    }
    if (object.length != 32 || expectedSize <= 0) {
      return _fail(platform, 'Malformed hash/size in manifest for $platform.');
    }
    final carrier = _carrier();
    if (carrier == null) {
      return _fail(platform, 'The network is not ready on this node yet.');
    }

    _set(platform, ForeignAcquireState.downloading);
    _inFlightObject = object;
    String? path;
    try {
      path = await carrier.foreignFetch(
          contentHash: object, length: expectedSize);
    } catch (e) {
      return _fail(platform, 'Collecting $platform failed: $e');
    } finally {
      _inFlightObject = null;
    }
    if (path == null) {
      return _fail(platform,
          'No neighbour delivered the $platform binary for v$version.');
    }

    // The carrier checked the SHA-256 of the object; the manifest's hash is
    // checked here once more, independently, before the signature — the
    // store must hold only what the maintainer signed.
    _set(platform, ForeignAcquireState.verifying,
        progress: kForeignCollectShare);
    final Uint8List hash;
    try {
      hash = await sha256OfFile(path);
    } catch (e) {
      carrier.foreignTaken(object);
      return _fail(platform, 'Could not read the collected binary: $e');
    }
    if (bytesToHex(hash).toLowerCase() != expectedHash.toLowerCase() ||
        !SodiumFFI().verifyEd25519(hash, signature, _maintainerKey)) {
      carrier.foreignTaken(object);
      _log.warn('Collected $platform binary does not match the signed '
          'manifest — discarded');
      return _fail(platform, 'The collected $platform binary is not verifiable.');
    }

    try {
      await _evictOtherForeign(platform);
      final complete = _store.completePath(platform, version);
      File(complete).parent.createSync(recursive: true);
      try {
        File(path).renameSync(complete);
      } on FileSystemException {
        // Another file system: copy, then the state below removes the source.
        File(path).copySync(complete);
      }
      _markOnDemand(platform, version);
    } catch (e) {
      carrier.foreignTaken(object);
      return _fail(platform, 'Could not store the collected binary: $e');
    }
    carrier.foreignTaken(object);
    _set(platform, ForeignAcquireState.ready, progress: 1.0);
    _log.info('Acquired $platform v$version on demand ($expectedSize bytes) '
        'from the network');
    return true;
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
