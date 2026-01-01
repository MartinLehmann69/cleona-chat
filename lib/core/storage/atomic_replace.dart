import 'dart:io';

/// Replaces the target with the sidecar file — **ONE** `renameSync`, with
/// retry. The one place in this tree where a write
/// becomes visible.
///
/// ── THE CLAIM THAT BRED A DEFECT FOUR TIMES HERE ─────────────────────
///
/// In `atomic_json_writer.dart` until S371 stood the sentence "Windows:
/// `renameSync` cannot overwrite". **That is not true.** Dart maps
/// `File.rename` there to `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING`;
/// the replacement is atomic and succeeds over an existing file.
/// Re-measured on the Windows machine on 05.09.2026 (S370): 8 of 8
/// runs complete and valid, never torn.
///
/// From this one wrong sentence four constructions had arisen, all under
/// `Platform.isWindows`:
///
///   * a three-step `canonical -> .old`, `tmp -> canonical`, delete `.old`
///     — in `atomic_json_writer.dart` and twice in
///     `file_encryption.dart`;
///   * a two-step `delete canonical`, `tmp -> canonical` — in
///     `media_cipher.dart`.
///
/// Both are not only superfluous, they tear a hole: between the
/// steps the canonical name does NOT exist. Measured on Windows,
/// two processes with 300 renames each, a third reads along (S370):
///
///     Path                       Errors per proc. Name MISSING  torn
///     one step                    98 / 99             0        0/4808
///     three steps                 54 / 68          1808        0/3847
///     one step + retry             3 /  2             0        0/4987
///
/// 1808 of 3847 looks — about a third — saw the canonical name
/// missing. The sidecar rescue in `AtomicJsonWriter.readJsonFile` and
/// `FileEncryption.readJsonFile` was a plaster on exactly this
/// self-made hole. With the two-step in `media_cipher.dart` it weighed
/// heavier: there is no rescue there at all, an abort between deleting
/// and renaming destroyed, when overwriting an attachment, the
/// only ciphertext.
///
/// ── WHY THE RETRY IS NO CONVENIENCE ──────────────────────────────────
///
/// The last table row is the actual yield: 98/99 errors
/// become 3/2. The case it catches is a READER that holds the
/// canonical file open at the moment of replacement (Windows:
/// `ERROR_SHARING_VIOLATION`). All callers here THROW on an error
/// through to their callers — `IdentityManager.saveIdentities`,
/// `DeviceKeysStore`, `V41Attach`, `MediaStore` —, so a lost race
/// is not a cosmetic flaw there, but an abort.
///
/// Five attempts over 12 ms: holding open lasts the length of a
/// `readAsBytesSync`, not longer. Whoever waits long here covers up a
/// hanging neighbour instead of bridging a race.
///
/// **Only [FileSystemException].** Every other error fails through
/// immediately; retrying it five times would obscure a cause.
const int atomicReplaceAttempts = 5;

/// Pause between two attempts. See [atomicReplaceAttempts].
const int atomicReplacePauseMs = 3;

/// Marker of the retry line on `stderr`. The guard
/// `smoke_atomic_replace_guard.dart` counts it; whoever renames it
/// disarms the guard — therefore it is here as a constant and not as a
/// string in the text.
const String atomicReplaceRetryMark = '[atomicReplace] retry';

/// Renames [tmp] onto the path of [target]. Replaces an existing
/// [target] atomically — on POSIX as on Windows, see [atomicReplaceAttempts].
///
/// There is **no platform branch** here, deliberately: the path
/// a Linux run takes is character-identical to the one Windows takes.
void atomicReplace(File tmp, File target) {
  for (var attempt = 1;; attempt++) {
    try {
      tmp.renameSync(target.path);
      return;
    } on FileSystemException catch (e) {
      if (attempt >= atomicReplaceAttempts) rethrow;
      stderr.writeln(
          '$atomicReplaceRetryMark $attempt/$atomicReplaceAttempts: '
          '${tmp.path} -> ${target.path} failed ($e) — new attempt in '
          '${atomicReplacePauseMs}ms');
      sleep(const Duration(milliseconds: atomicReplacePauseMs));
    }
  }
}
