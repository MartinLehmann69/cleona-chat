import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_sha256.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex;

/// Manages the complete update objects on disk (v4_2 §26.6.1 step 3:
/// desktops "hold the complete objects of the current manifest"; step 2:
/// fountain blocks are encoded from the object per request, "nothing is
/// placed in advance").
///
/// Layout: `<profileDir>/binary-updates/<platform>/<version>/`
///   - `complete.bin` (the complete object)
///   - `meta.json` ({"storedAt": unix_ts_ms, "binaryHash": "..."})
///
/// The class keeps its 3.x name: until S407 the same directories also held
/// Reed-Solomon fragments (`fragment-NNN.bin`, §19.6.2 of the 3.x line) next
/// to `complete.bin`. Nothing writes them any more; [dropFragmentFiles]
/// removes what an earlier version left behind (S407-UPDATEFRAGMENTE).
class UpdateBinaryStore {
  final String profileDir;
  final String _storageDir;
  final CLogger _log;

  // The budgets of its own (§19.6.2 of the 3.x line: bootstrap unlimited,
  // desktop 32 MiB, mobile 5 MB) fell with S407-UPDATEFRAGMENTE: the store
  // is part of the bulk-cache class (`update_store_budget.dart`).

  UpdateBinaryStore(this.profileDir)
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

  String completePath(String platform, String version) =>
      '${_versionDir(platform, version)}/complete.bin';

  String _metaPath(String platform, String version) =>
      '${_versionDir(platform, version)}/meta.json';

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
  /// and, until V9 A1, the relay record providers of the binary
  /// distribution).
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

  /// Synchronous variant of [hasComplete] — see [getCompleteSync].
  bool hasCompleteSync(String platform, String version) {
    try {
      return File(completePath(platform, version)).existsSync();
    } catch (e) {
      _log.error('hasCompleteSync $platform/$version failed: $e');
      return false;
    }
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

  /// Fragment files an earlier version left in the directory of
  /// [platform]/[version] (`fragment-NNN.bin`, also an unfinished `.tmp`).
  /// Nothing reads them in 4.2; only [dropFragmentFiles] and the budget
  /// look for them.
  Future<List<File>> _leftoverFragmentFiles(
      String platform, String version) async {
    final files = <File>[];
    try {
      final dir = Directory(_versionDir(platform, version));
      if (!await dir.exists()) return files;
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        if (_fragmentName.hasMatch(entry.uri.pathSegments.last)) {
          files.add(entry);
        }
      }
    } catch (e) {
      _log.error('leftover fragments $platform/$version: $e');
    }
    return files;
  }

  /// Static, so the isolate closure captures the path only — a closure
  /// made inside an instance method would carry `this` (and its logger's
  /// timer, which no isolate message can hold).
  static Future<Uint8List> _hashInIsolate(String path) =>
      Isolate.run(() => sha256OfFile(path));

  static final RegExp _fragmentName = RegExp(r'^fragment-\d+\.bin(\.tmp)?$');

  /// Enforcer (S407-UPDATEFRAGMENTE): removes the Reed-Solomon fragment
  /// files of every version directory whose complete object is present AND
  /// checked — its streamed SHA-256 equals [expectedHash] for that
  /// directory, or, where that returns null, the `binaryHash` its own
  /// `meta.json` recorded when the object was stored. Without a checked
  /// object the fragments stay: they go with their version once it is
  /// superseded ([garbageCollect]), or here once the object is present.
  ///
  /// The hash runs in an isolate: the android object is ~390 MB, and a
  /// check of that size on the main isolate delays the event loop by
  /// seconds (S407-BOOTSTRAPSPEICHER: `DRIFT — main loop delayed 6464ms`).
  /// A directory without fragments costs one directory listing and no hash.
  ///
  /// Returns the number of bytes released.
  Future<int> dropFragmentFiles(
      {String? Function(String platform, String version)? expectedHash}) async {
    var released = 0;
    try {
      final root = Directory(_storageDir);
      if (!await root.exists()) return 0;
      await for (final platformEntry in root.list()) {
        if (platformEntry is! Directory) continue;
        final platform = platformEntry.path.split(Platform.pathSeparator).last;
        for (final version in await storedVersions(platform)) {
          final fragments = await _leftoverFragmentFiles(platform, version);
          if (fragments.isEmpty) continue;
          final complete = completePath(platform, version);
          if (!await File(complete).exists()) {
            _log.info('dropFragmentFiles: $platform/$version has '
                '${fragments.length} fragment file(s) but no complete object '
                '— kept until the object is present or the version is '
                'superseded');
            continue;
          }
          final want = (expectedHash?.call(platform, version) ??
                  await getBinaryHash(platform, version))
              ?.toLowerCase();
          if (want == null) {
            _log.warn('dropFragmentFiles: $platform/$version has no known '
                'hash — complete object not checkable, fragments kept');
            continue;
          }
          final got = bytesToHex(await _hashInIsolate(complete));
          if (got != want) {
            _log.warn('dropFragmentFiles: $platform/$version complete object '
                'does not match its hash ($got != $want) — fragments kept');
            continue;
          }
          var bytes = 0;
          for (final f in fragments) {
            try {
              final n = await f.length();
              await f.delete();
              bytes += n;
            } catch (e) {
              _log.error('dropFragmentFiles: ${f.path}: $e');
            }
          }
          released += bytes;
          _log.info('dropFragmentFiles: $platform/$version complete object '
              'checked (SHA-256 matches) — ${fragments.length} fragment '
              'file(s), $bytes bytes released');
        }
      }
    } catch (e) {
      _log.error('dropFragmentFiles failed: $e');
    }
    return released;
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

  /// Releases what is superseded: every stored version OLDER than [current]
  /// goes, on every platform, at once. Returns the number of version
  /// directories deleted.
  ///
  /// [current] is the version of the newest manifest the node knows, or its
  /// running version while it knows none. v4_2 §26.6.1 step 3: "desktop
  /// installations hold the complete objects of the current manifest";
  /// "An outdated version is never offered"; §5.5: the own target is kept
  /// "until installed or superseded". A version NEWER than [current] stays
  /// (seeded before the node read its manifest), and so does [keep] — the
  /// install target the caller protects.
  ///
  /// Until S407 this kept the newest older version as a "delta baseline"
  /// and everything else for 30 days (§19.6.2 of the 3.x line): in 4.2 a
  /// delta is made by the release pipeline and applied to the INSTALLED
  /// binary (`deltaBasePath`), never to a stored one, so the baseline had no
  /// reader — and on the bootstrap 4.2.2 (491 MB) outlived 4.2.3 by a week
  /// with no end (S407-BOOTSTRAPSPEICHER).
  Future<int> garbageCollect(String current,
      {bool Function(String platform, String version)? keep}) async {
    var deleted = 0;
    try {
      final root = Directory(_storageDir);
      if (!await root.exists()) return 0;
      await for (final platformEntry in root.list()) {
        if (platformEntry is! Directory) continue;
        final platform = platformEntry.path.split(Platform.pathSeparator).last;
        for (final version in await storedVersions(platform)) {
          if (_compareVersions(version, current) >= 0) continue;
          if (keep?.call(platform, version) ?? false) continue;
          await deleteVersion(platform, version);
          _log.info('garbageCollect: $platform/$version superseded by '
              '$current — released');
          deleted++;
        }
      }
    } catch (e) {
      _log.error('garbageCollect failed: $e');
    }
    return deleted;
  }

  /// Enforce a storage budget by deleting fragment files left by an earlier
  /// version (oldest stored version first, [dropFragmentFiles]), then
  /// `complete.bin` files (oldest version first), until under
  /// [budgetBytes]. A negative budget means unlimited (no-op).
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
  ///
  /// [protect] exempts further (platform, version) pairs the same way — the
  /// objects a desktop holds for others (`heldForOthers`,
  /// S407-UPDATEFRAGMENTE): they are never evicted.
  Future<void> enforceBudget(int budgetBytes,
      {String? protectPlatform,
      String? protectVersion,
      bool Function(String platform, String version)? protect}) async {
    if (budgetBytes < 0) return;
    try {
      var total = await totalStorageUsed();
      if (total <= budgetBytes) return;

      final fragmentCandidates = <({String platform, String version,
          String name, File file, int size, DateTime storedAt})>[];
      final completeCandidates = <({String platform, String version,
          File file, int size, DateTime storedAt})>[];
      final root = Directory(_storageDir);
      if (!await root.exists()) return;
      await for (final platformEntry in root.list()) {
        if (platformEntry is! Directory) continue;
        final platform = platformEntry.path.split(Platform.pathSeparator).last;
        for (final version in await storedVersions(platform)) {
          final storedAt = await _storedAt(platform, version) ?? DateTime.now();
          for (final file in await _leftoverFragmentFiles(platform, version)) {
            try {
              fragmentCandidates.add((
                platform: platform,
                version: version,
                name: file.uri.pathSegments.last,
                file: file,
                size: await file.length(),
                storedAt: storedAt,
              ));
            } catch (_) {}
          }

          final isProtected =
              (platform == protectPlatform && version == protectVersion) ||
                  (protect?.call(platform, version) ?? false);
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
        return byAge != 0 ? byAge : b.name.compareTo(a.name);
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

      // Leftover fragments alone may not suffice (a single complete.bin can dwarf the
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
      // `fragmentCount` (3.x layout) is no longer written; a value an
      // earlier version left is dropped with the next write.
      meta.remove('fragmentCount');
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
