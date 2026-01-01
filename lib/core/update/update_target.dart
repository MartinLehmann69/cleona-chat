import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/update/delta/bspatch.dart';
import 'package:cleona/core/update/update_manifest.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;

/// What a node collects for an update: the full binary or a delta
/// (v4_2 §26.6.2 "A delta is simply a smaller object on the same path as the
/// full binary").
enum UpdateObjectKind { full, delta }

/// THE update target (S406-UPDPKG, P1): an object, named by its SHA-256 —
/// not by the version string — together with the manifest that names it.
///
/// v4_2 §26.6.1 "A newer manifest while collecting. The node switches to the
/// newest target at once; pieces that do not serve it are discarded."
/// Until S406 the target was `manifest.version` (`_updateCollectTarget`):
/// the same version with a higher sequence number named another object
/// under the same key, so the old run went on and the new one failed
/// (S406-UPD2 finding B-3).
class UpdateTarget {
  /// SHA-256 of the object collected — what the fetch path asks for.
  final Uint8List object;

  /// Its length in bytes.
  final int length;
  final UpdateObjectKind kind;

  /// The manifest's sequence number (§26.6.1 `minMonotoneSeq`).
  final int seq;

  /// The version the object leads to.
  final String version;
  final String platform;

  /// For a delta: the installed version it applies to; `null` for full.
  final String? fromVersion;

  /// The manifest that names this target — its `binaryHashes` and
  /// `binarySignatures` check the binary the object becomes.
  final UpdateManifest manifest;

  const UpdateTarget({
    required this.object,
    required this.length,
    required this.kind,
    required this.seq,
    required this.version,
    required this.platform,
    required this.manifest,
    this.fromVersion,
  });

  /// Two targets are the same when they name the same object at the same
  /// sequence number.
  bool sameAs(UpdateTarget? o) {
    if (o == null || o.seq != seq || o.object.length != object.length) {
      return false;
    }
    for (var i = 0; i < object.length; i++) {
      if (o.object[i] != object[i]) return false;
    }
    return true;
  }

  @override
  String toString() => '${kind.name} v$version seq $seq ($length B)';
}

/// The platforms whose updates come as deltas (S406-DELTA). Android only:
/// the desktop update objects are compressed archives (tar.gz/zip), on which
/// a delta saves next to nothing. Desktop delta updates — owner decision
/// 07.10.2026 E-D2 A, planned. Until then linux and windows always collect
/// the full binary, even if a manifest names a delta for them.
const Set<String> kDeltaPlatforms = {'android'};

/// Deltas (SHA-256 hex) that could not be made into the binary in this
/// process — wrong or missing installed file, bspatch error, result that
/// fails its check. [updateTargetFor] never chooses them again: "fallback to
/// the full binary" (§26.6.2). In memory on purpose: after a restart the
/// delta is tried once more (it is small), and a base that has meanwhile
/// become right is not locked out for good.
final Set<String> _failedDeltas = <String>{};

/// Marks the delta of [target] as not usable — the next [updateTargetFor]
/// for the same manifest returns the full binary.
void updateDeltaFailed(UpdateTarget target) {
  if (target.kind == UpdateObjectKind.delta) {
    _failedDeltas.add(bytesToHex(target.object));
  }
}

final RegExp _hexHash = RegExp(r'^[0-9a-fA-F]{64}$');

/// THE ONE place where the target is chosen (v4_2 §26.6.2 "Which object a
/// node collects follows only from its installed version and the newest
/// manifest: V-1 or V-2 → the matching delta, anything older → the full
/// binary. The choice is local and asks no one").
///
/// The delta from [installedVersion] when [platform] is in
/// [kDeltaPlatforms] and the manifest names it with hash AND length (§26.6.2
/// "without both, a node can neither derive the delta's key nor tell when it
/// is complete") and it has not failed here before ([updateDeltaFailed]);
/// otherwise the full binary — `binaryHashes`/`binarySizes` — or `null` when
/// the manifest names none. The pipeline writes deltas from V-1 and V-2 only
/// (`sign-update-manifest.sh` refuses a third), so "anything older" finds no
/// entry. What a delta becomes is [updateBinaryFromObject]'s job; nothing
/// else in the update path decides which object is collected.
UpdateTarget? updateTargetFor(
    UpdateManifest manifest, String installedVersion, String platform) {
  final hash = manifest.binaryHashes?[platform];
  final size = manifest.binarySizes?[platform];
  if (hash == null || size == null || size <= 0 || !_hexHash.hasMatch(hash)) {
    return null;
  }
  final dHash = manifest.deltaHashes?[platform]?[installedVersion];
  final dSize = manifest.deltaSizes?[platform]?[installedVersion];
  final delta = kDeltaPlatforms.contains(platform) &&
      dHash != null &&
      _hexHash.hasMatch(dHash) &&
      dSize != null &&
      dSize > 0 &&
      !_failedDeltas.contains(dHash.toLowerCase());
  return UpdateTarget(
    object: hexToBytes(delta ? dHash : hash),
    length: delta ? dSize : size,
    kind: delta ? UpdateObjectKind.delta : UpdateObjectKind.full,
    seq: manifest.minMonotoneSeq ?? 0,
    version: manifest.version,
    platform: platform,
    manifest: manifest,
    fromVersion: delta ? installedVersion : null,
  );
}

/// THE ONE place "object complete → the binary": the full binary from the
/// collected object of [target] at [objectPath] — its path, or `null` when
/// it cannot be made. For [UpdateObjectKind.full] the object IS the binary.
/// For [UpdateObjectKind.delta] bspatch (bsdiff 4.3, `delta/bspatch.dart`)
/// applies the object to the installed file [basePath] ([deltaBasePath]) in
/// an isolate and writes `<objectPath>.binary`; the delta's header refuses a
/// base that is not the file it was made from before a byte is written.
/// Whatever comes out is checked against the manifest's `binaryHashes` and
/// maintainer signature afterwards — for a delta too; if that or this fails,
/// the caller marks the delta failed ([updateDeltaFailed]) and the full
/// binary becomes the target (§26.6.2 "fallback to the full binary").
Future<String?> updateBinaryFromObject(UpdateTarget target, String objectPath,
    {String? basePath}) async {
  switch (target.kind) {
    case UpdateObjectKind.full:
      return objectPath;
    case UpdateObjectKind.delta:
      if (basePath == null) return null;
      final out = '$objectPath.binary';
      final ok = await Isolate.run(() async {
        try {
          await bspatchFile(
              oldPath: basePath,
              patch: File(objectPath).readAsBytesSync(),
              outPath: out);
          return true;
        } on Object {
          return false;
        }
      });
      return ok ? out : null;
  }
}

/// Where the installed object of [platform] lies, to patch it.
///
///  * android: the installed APK (`ApplicationInfo.sourceDir`, via
///    [apkPath] — `MainActivity.kt` `getApkSourcePath`). Android keeps the
///    APK exactly as it was installed; that is the file the delta was made
///    from.
///  * every other platform: `null` — no deltas there ([kDeltaPlatforms]).
///
/// Whether the file is really the right base decides the delta's own header
/// (size and SHA-256 of the base, `bspatch.dart`), not this function.
Future<String?> deltaBasePath({
  required String platform,
  Future<String?> Function()? apkPath,
}) async {
  if (platform != 'android') return null;
  String? path;
  try {
    path = await apkPath?.call();
  } on Object {
    path = null;
  }
  if (path == null || !File(path).existsSync()) return null;
  return path;
}

/// Directory of the delta objects an always-on node holds for others — the
/// release pipeline puts the android deltas there on the bootstrap
/// (`release-build.sh` phase 8, `<data dir>/update-deltas/<sha256>.delta`).
String deltaDir(String dataDir) =>
    '$dataDir${Platform.pathSeparator}update-deltas';

/// The file of the delta object [hash] in [dataDir].
String deltaFile(String dataDir, String hash) =>
    '${deltaDir(dataDir)}${Platform.pathSeparator}$hash.delta';

/// The delta files of [manifest] present in [dataDir], as (hash, path) for
/// the holder (`UpdateCarrier.objectHoldFile`). Only what the manifest names
/// is held — an outdated delta is never handed out. Nothing is deleted here:
/// at start the node may still know an older manifest than the files the
/// pipeline has just placed; the pipeline clears the directory.
List<(String, String)> deltaObjectsHeld(UpdateManifest manifest, String dataDir) {
  final named = <String>{};
  for (final perSource in (manifest.deltaHashes ?? const {}).values) {
    for (final h in perSource.values) {
      named.add(h.toLowerCase());
    }
  }
  final dir = Directory(deltaDir(dataDir));
  if (!dir.existsSync()) return const [];
  final held = <(String, String)>[];
  for (final e in dir.listSync().whereType<File>()) {
    final name = e.uri.pathSegments.last;
    final hash = name.endsWith('.delta')
        ? name.substring(0, name.length - '.delta'.length)
        : '';
    if (named.contains(hash)) held.add((hash, e.path));
  }
  return held;
}
