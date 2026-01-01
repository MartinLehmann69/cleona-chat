import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/storage/atomic_replace.dart';

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
///   `<path>.old` — **is no longer created** (S371). A profile from an
///     older version may carry one, therefore [readJsonFile] still reads
///     it; see [writeJsonFile].
///
/// On read, if canonical is missing or corrupt, .tmp and .old are tried in
/// order; a recovered sidecar is promoted to canonical via writeJsonFile.
class AtomicJsonWriter {
  /// Encode `json` to UTF-8 and atomically write to `path` via tmp+rename.
  ///
  /// ── HERE STOOD THE SENTENCE THAT BRED FOUR DEFECTS (S371) ───────────
  ///
  /// Until S371 this said: "Windows: `renameSync` cannot overwrite, so we
  /// stage canonical→`.old` first". **The claim is refuted by
  /// measurement** — Dart maps `File.rename` there to `MoveFileExW` with
  /// `MOVEFILE_REPLACE_EXISTING`, the replacement succeeds over an
  /// existing file (Windows machine, 05.09.2026, 8 of 8 runs
  /// complete and valid). The sentence was the justification for the
  /// three-step here, for two more in `file_encryption.dart` and
  /// for a two-step in `media_cipher.dart`; all four are
  /// removed. What the three-step cost and why the retry
  /// is no convenience is at [atomicReplace] — there with the
  /// measurement table.
  ///
  /// POSIX as Windows: ONE `renameSync`, crash-atomic (old or new, never
  /// torn). The canonical name exists throughout.
  static void writeJsonFile(String path, Map<String, dynamic> json) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final canonical = File(path);
    final tmp = File('$path.tmp');
    canonical.parent.createSync(recursive: true);

    try {
      tmp.writeAsBytesSync(bytes, flush: true);
      atomicReplace(tmp, canonical);
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
