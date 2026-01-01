import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Atomically writes/reads JSON files with crash-recovery from sidecars.
///
/// Pattern mirrors [FileEncryption.writeJsonFile] but without the crypto
/// layer — for files whose contents are not sensitive enough to require
/// encryption-at-rest but still need data-integrity guarantees against
/// mid-write process kill.
///
/// Sidecar layout during write:
///   `<path>` — canonical (atomic destination)
///   `<path>.tmp` — staged write before rename
///   `<path>.old` — Windows-only: previous canonical, briefly held during rename
///
/// On read, if canonical is missing or corrupt, .tmp and .old are tried in
/// order; a recovered sidecar is promoted to canonical via writeJsonFile.
class AtomicJsonWriter {
  /// Encode `json` to UTF-8 and atomically write to `path` via tmp+rename.
  ///
  /// POSIX: `renameSync` is crash-atomic (old or new, never torn).
  /// Windows: `renameSync` cannot overwrite, so we stage canonical→`.old`
  /// first; readers recover from `.tmp`/`.old` if we crash between steps.
  static void writeJsonFile(String path, Map<String, dynamic> json) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final canonical = File(path);
    final tmp = File('$path.tmp');
    final old = File('$path.old');
    canonical.parent.createSync(recursive: true);

    try {
      tmp.writeAsBytesSync(bytes, flush: true);
      if (Platform.isWindows && canonical.existsSync()) {
        if (old.existsSync()) old.deleteSync();
        canonical.renameSync(old.path);
        try {
          tmp.renameSync(canonical.path);
        } catch (e) {
          // rollback: restore the old canonical so we don't lose state.
          if (old.existsSync() && !canonical.existsSync()) {
            old.renameSync(canonical.path);
          }
          rethrow;
        }
        if (old.existsSync()) old.deleteSync();
      } else {
        tmp.renameSync(canonical.path);
      }
    } catch (e) {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Read a JSON map from `path`. If canonical is missing or corrupt,
  /// try `.tmp` then `.old` and promote a recovered sidecar to canonical.
  /// Returns null if all paths fail.
  static Map<String, dynamic>? readJsonFile(String path) {
    Map<String, dynamic>? tryParse(File f) {
      try {
        return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }

    final canonical = File(path);
    if (canonical.existsSync()) {
      final parsed = tryParse(canonical);
      if (parsed != null) return parsed;
      stderr.writeln(
          '[AtomicJsonWriter] WARNING: $path corrupt — attempting sidecar-recovery.');
    }
    for (final suffix in ['.tmp', '.old']) {
      final side = File('$path$suffix');
      if (!side.existsSync()) continue;
      final parsed = tryParse(side);
      if (parsed != null) {
        stderr.writeln(
            '[AtomicJsonWriter] INFO: recovered $path from $suffix sidecar.');
        writeJsonFile(path, parsed);
        return parsed;
      }
    }
    return null;
  }
}
