import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex;

/// Manages binary update fragments/complete binaries on disk (Architektur
/// §19.6.2 — Censorship-Resistant Distribution / In-Network Binary Updates).
///
/// Layout: `<profileDir>/binary-updates/<platform>/<version>/`
///   - `fragment-NNN.bin` (zero-padded to 3 digits)
///   - `complete.bin` (fully reconstructed binary, if present)
///   - `meta.json` ({"storedAt": unix_ts_ms, "fragmentCount": N, "binaryHash": "..."})
class BinaryFragmentStore {
  final String profileDir;
  final String _storageDir;
  final CLogger _log;

  /// Minimum retention before a superseded version may be garbage-collected.
  static const Duration kMinRetention = Duration(days: 30);

  // Storage budgets (§19.6.2).
  static const int kBootstrapBudgetBytes = -1; // unlimited (all platforms, early phase)
  static const int kDesktopBudgetBytes = 32 * 1024 * 1024; // 32 MiB
  static const int kMobileBudgetBytes = 5 * 1024 * 1024; // 5 MB

  BinaryFragmentStore(this.profileDir)
      : _storageDir = '$profileDir/binary-updates',
        _log = CLogger.get('bin-store', profileDir: profileDir);

  Future<void> init() async {
    try {
      final dir = Directory(_storageDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      _log.error('init: failed to create storage dir: $e');
    }
  }

  String _versionDir(String platform, String version) =>
      '$_storageDir/$platform/$version';

  String _fragmentPath(String platform, String version, int index) =>
      '${_versionDir(platform, version)}/fragment-${index.toString().padLeft(3, '0')}.bin';

  String completePath(String platform, String version) =>
      '${_versionDir(platform, version)}/complete.bin';

  String _metaPath(String platform, String version) =>
      '${_versionDir(platform, version)}/meta.json';

  Future<void> storeFragment(
      String platform, String version, int index, Uint8List data) async {
    try {
      final dir = Directory(_versionDir(platform, version));
      if (!await dir.exists()) await dir.create(recursive: true);
      final target = _fragmentPath(platform, version, index);
      final tmpFile = File('$target.tmp');
      await tmpFile.writeAsBytes(data);
      await tmpFile.rename(target);
      await _touchMeta(platform, version);
    } catch (e) {
      _log.error('storeFragment $platform/$version#$index failed: $e');
      rethrow;
    }
  }

  Future<Uint8List?> getFragment(
      String platform, String version, int index) async {
    try {
      final f = File(_fragmentPath(platform, version, index));
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (e) {
      _log.error('getFragment $platform/$version#$index failed: $e');
      return null;
    }
  }

  Future<void> storeComplete(
      String platform, String version, Uint8List data) async {
    try {
      final dir = Directory(_versionDir(platform, version));
      if (!await dir.exists()) await dir.create(recursive: true);
      final target = completePath(platform, version);
      final tmpFile = File('$target.tmp');
      await tmpFile.writeAsBytes(data);
      await tmpFile.rename(target);
      final hash = bytesToHex(SodiumFFI().sha256(data));
      await _touchMeta(platform, version, binaryHash: hash);
    } catch (e) {
      _log.error('storeComplete $platform/$version failed: $e');
      rethrow;
    }
  }

  Future<void> deleteComplete(String platform, String version) async {
    try {
      final f = File(completePath(platform, version));
      if (await f.exists()) await f.delete();
    } catch (e) {
      _log.error('deleteComplete $platform/$version failed: $e');
    }
  }

  Future<Uint8List?> getComplete(String platform, String version) async {
    try {
      final f = File(completePath(platform, version));
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (e) {
      _log.error('getComplete $platform/$version failed: $e');
      return null;
    }
  }

  /// Synchronous variant of [getComplete] — for callers that must satisfy a
  /// synchronous callback contract (e.g. the embedded HTTP server §19.6.6,
  /// whose [BinaryHttpServer.binaryProvider] is a sync `Uint8List? Function`,
  /// and [BinaryRendezvousManager]'s record-provider callbacks).
  Uint8List? getCompleteSync(String platform, String version) {
    try {
      final f = File(completePath(platform, version));
      if (!f.existsSync()) return null;
      return f.readAsBytesSync();
    } catch (e) {
      _log.error('getCompleteSync $platform/$version failed: $e');
      return null;
    }
  }

  /// Returns the file path to `complete.bin` for a given platform/version,
  /// or null if it does not exist. Used by the HTTP server for streaming.
  String? getCompletePath(String platform, String version) {
    try {
      final path = completePath(platform, version);
      if (File(path).existsSync()) return path;
      return null;
    } catch (e) {
      _log.error('getCompletePath $platform/$version failed: $e');
      return null;
    }
  }

  /// Synchronous variant of [getFragment] — see [getCompleteSync].
  Uint8List? getFragmentSync(String platform, String version, int index) {
    try {
      final f = File(_fragmentPath(platform, version, index));
      if (!f.existsSync()) return null;
      return f.readAsBytesSync();
    } catch (e) {
      _log.error('getFragmentSync $platform/$version#$index failed: $e');
      return null;
    }
  }

  /// Synchronous variant of [hasComplete] — see [getCompleteSync].
  bool hasCompleteSync(String platform, String version) {
    try {
      return File(completePath(platform, version)).existsSync();
    } catch (e) {
      _log.error('hasCompleteSync $platform/$version failed: $e');
      return false;
    }
  }

  /// Synchronous variant of [availableFragments] — see [getCompleteSync].
  List<int> availableFragmentsSync(String platform, String version) {
    final indices = <int>[];
    try {
      final dir = Directory(_versionDir(platform, version));
      if (!dir.existsSync()) return indices;
      final re = RegExp(r'^fragment-(\d+)\.bin$');
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        final m = re.firstMatch(name);
        if (m != null) indices.add(int.parse(m.group(1)!));
      }
      indices.sort();
    } catch (e) {
      _log.error('availableFragmentsSync $platform/$version failed: $e');
    }
    return indices;
  }

  /// Synchronous, version-sorted (ascending) variant of [storedVersions] —
  /// see [getCompleteSync].
  List<String> storedVersionsSync(String platform) {
    final versions = <String>[];
    try {
      final dir = Directory('$_storageDir/$platform');
      if (!dir.existsSync()) return versions;
      for (final entry in dir.listSync()) {
        if (entry is Directory) {
          versions.add(entry.path.split(Platform.pathSeparator).last);
        }
      }
      versions.sort(_compareVersions);
    } catch (e) {
      _log.error('storedVersionsSync $platform failed: $e');
    }
    return versions;
  }

  /// Returns the `binaryHash` from meta.json for a given platform/version,
  /// or null if unavailable.
  Future<String?> getBinaryHash(String platform, String version) async {
    try {
      final metaFile = File(_metaPath(platform, version));
      if (!await metaFile.exists()) return null;
      final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final hash = meta['binaryHash'] as String?;
      return (hash != null && hash.isNotEmpty) ? hash : null;
    } catch (e) {
      _log.error('getBinaryHash $platform/$version failed: $e');
      return null;
    }
  }

  Future<List<int>> availableFragments(String platform, String version) async {
    final indices = <int>[];
    try {
      final dir = Directory(_versionDir(platform, version));
      if (!await dir.exists()) return indices;
      final re = RegExp(r'^fragment-(\d+)\.bin$');
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        final m = re.firstMatch(name);
        if (m != null) indices.add(int.parse(m.group(1)!));
      }
      indices.sort();
    } catch (e) {
      _log.error('availableFragments $platform/$version failed: $e');
    }
    return indices;
  }

  Future<bool> hasComplete(String platform, String version) async {
    try {
      return await File(completePath(platform, version)).exists();
    } catch (e) {
      _log.error('hasComplete $platform/$version failed: $e');
      return false;
    }
  }

  Future<int> totalStorageUsed() async {
    var total = 0;
    try {
      final dir = Directory(_storageDir);
      if (!await dir.exists()) return 0;
      await for (final entry in dir.list(recursive: true)) {
        if (entry is File) {
          try {
            total += await entry.length();
          } catch (_) {}
        }
      }
    } catch (e) {
      _log.error('totalStorageUsed failed: $e');
    }
    return total;
  }

  // DROPPED ON 09.09.2026 (S378): no caller in lib/ or test/.
  // The budgets are today kept by `update/cover_fill_blocks.dart`
  // (`kCoverFillBudgetBytes`, `kCoverFillMobileBudgetBytes`).

  Future<List<String>> storedVersions(String platform) async {
    final versions = <String>[];
    try {
      final dir = Directory('$_storageDir/$platform');
      if (!await dir.exists()) return versions;
      await for (final entry in dir.list()) {
        if (entry is Directory) {
          versions.add(entry.path.split(Platform.pathSeparator).last);
        }
      }
    } catch (e) {
      _log.error('storedVersions $platform failed: $e');
    }
    return versions;
  }

  Future<void> deleteVersion(String platform, String version) async {
    try {
      final dir = Directory(_versionDir(platform, version));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      _log.error('deleteVersion $platform/$version failed: $e');
    }
  }

  /// Garbage collection (§19.6.2): for every platform, keep [currentVersion]
  /// and at most one previous ("delta baseline") version. Older versions are
  /// removed once they have been superseded for more than [kMinRetention].
  /// Returns the number of version directories deleted.
  Future<int> garbageCollect(String currentVersion) async {
    var deleted = 0;
    try {
      final root = Directory(_storageDir);
      if (!await root.exists()) return 0;
      await for (final platformEntry in root.list()) {
        if (platformEntry is! Directory) continue;
        final platform = platformEntry.path.split(Platform.pathSeparator).last;
        final versions = await storedVersions(platform);
        final oldVersions = versions.where((v) => v != currentVersion).toList()
          ..sort(_compareVersions);
        final descending = oldVersions.reversed.toList(); // newest first

        for (var i = 0; i < descending.length; i++) {
          final version = descending[i];
          if (i == 0) continue; // keep newest old version as delta baseline
          final storedAt = await _storedAt(platform, version);
          if (storedAt == null) continue;
          if (DateTime.now().difference(storedAt) > kMinRetention) {
            await deleteVersion(platform, version);
            deleted++;
          }
        }
      }
    } catch (e) {
      _log.error('garbageCollect failed: $e');
    }
    return deleted;
  }

  /// Enforce a storage budget by deleting fragments (highest index first)
  /// belonging to the oldest stored versions, then `complete.bin` files
  /// (oldest version first), until under [budgetBytes]. A negative budget
  /// means unlimited (no-op).
  ///
  /// [protectPlatform]/[protectVersion] name the (platform, version) pair
  /// [BinaryUpdateManager] currently targets for local installation — its
  /// `complete.bin` is the file `applyUpdate()` hands to the OS installer
  /// (Android: `main.dart` reads it via [completePath] directly; desktop:
  /// [BinaryUpdateManager.getVerifiedBinaryPath] copies it out before
  /// install). It is exempt from deletion for as long as the manager holds
  /// that target, so a budget sweep can never remove the exact binary the
  /// user is about to install or has just handed to the installer.
  /// `complete.bin` files for any other (platform, version) — superseded
  /// local versions, or on-demand binaries fetched to serve other
  /// platforms' peers (§19.6.4) — remain fully subject to the budget.
  Future<void> enforceBudget(int budgetBytes,
      {String? protectPlatform, String? protectVersion}) async {
    if (budgetBytes < 0) return;
    try {
      var total = await totalStorageUsed();
      if (total <= budgetBytes) return;

      final fragmentCandidates = <({String platform, String version,
          int index, File file, int size, DateTime storedAt})>[];
      final completeCandidates = <({String platform, String version,
          File file, int size, DateTime storedAt})>[];
      final root = Directory(_storageDir);
      if (!await root.exists()) return;
      await for (final platformEntry in root.list()) {
        if (platformEntry is! Directory) continue;
        final platform = platformEntry.path.split(Platform.pathSeparator).last;
        for (final version in await storedVersions(platform)) {
          final storedAt = await _storedAt(platform, version) ?? DateTime.now();
          for (final index in await availableFragments(platform, version)) {
            final file = File(_fragmentPath(platform, version, index));
            try {
              fragmentCandidates.add((
                platform: platform,
                version: version,
                index: index,
                file: file,
                size: await file.length(),
                storedAt: storedAt,
              ));
            } catch (_) {}
          }

          final isProtected =
              platform == protectPlatform && version == protectVersion;
          if (isProtected) continue;
          final completeFile = File(completePath(platform, version));
          try {
            if (await completeFile.exists()) {
              completeCandidates.add((
                platform: platform,
                version: version,
                file: completeFile,
                size: await completeFile.length(),
                storedAt: storedAt,
              ));
            }
          } catch (_) {}
        }
      }

      // Oldest version first; within a version, highest fragment index first.
      fragmentCandidates.sort((a, b) {
        final byAge = a.storedAt.compareTo(b.storedAt);
        return byAge != 0 ? byAge : b.index.compareTo(a.index);
      });
      // complete.bin files: oldest version first.
      completeCandidates.sort((a, b) => a.storedAt.compareTo(b.storedAt));

      for (final c in fragmentCandidates) {
        if (total <= budgetBytes) break;
        try {
          await c.file.delete();
          total -= c.size;
        } catch (e) {
          _log.error('enforceBudget: failed to delete ${c.file.path}: $e');
        }
      }

      // Fragments alone may not suffice (a single complete.bin can dwarf the
      // whole budget, §S362 measured: 189.6 MB APK against a 5 MB mobile
      // budget) — fall back to complete.bin files, oldest first, never
      // touching the protected install target.
      for (final c in completeCandidates) {
        if (total <= budgetBytes) break;
        try {
          await c.file.delete();
          total -= c.size;
        } catch (e) {
          _log.error('enforceBudget: failed to delete ${c.file.path}: $e');
        }
      }
    } catch (e) {
      _log.error('enforceBudget failed: $e');
    }
  }

  Future<void> _touchMeta(String platform, String version,
      {String? binaryHash}) async {
    try {
      final metaFile = File(_metaPath(platform, version));
      Map<String, dynamic> meta = {};
      if (await metaFile.exists()) {
        try {
          meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        } catch (_) {}
      }
      meta['storedAt'] ??= DateTime.now().millisecondsSinceEpoch;
      meta['fragmentCount'] = (await availableFragments(platform, version)).length;
      if (binaryHash != null) meta['binaryHash'] = binaryHash;
      meta['binaryHash'] ??= '';
      await metaFile.writeAsString(jsonEncode(meta));
    } catch (e) {
      _log.error('_touchMeta $platform/$version failed: $e');
    }
  }

  Future<DateTime?> _storedAt(String platform, String version) async {
    try {
      final metaFile = File(_metaPath(platform, version));
      if (await metaFile.exists()) {
        final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        final ts = meta['storedAt'];
        if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
      }
      // Fallback: directory modification time.
      return await Directory(_versionDir(platform, version)).stat().then((s) => s.modified);
    } catch (_) {
      return null;
    }
  }

  static int _compareVersions(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }
}
