import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/log/clogger.dart';

/// Result of a cleanup run over ONE file at rest.
enum SweepOutcome {
  /// There was no plaintext version (any more) — nothing to do.
  nothingToDo,

  /// A readable ciphertext was already present; the plaintext version
  /// lying next to it was removed.
  plaintextRemoved,

  /// The plaintext version was written encrypted, read back, checked and
  /// only then deleted.
  migrated,

  /// The run deleted NOTHING. The plaintext version lies on unchanged —
  /// deliberately, so that an error costs no data.
  failed,
}

/// One-time cleaner for user content at rest that lay in plaintext in the
/// profile directory before S362.
///
/// **Why this cleaner is needed at all.** A switch of the write path alone
/// protects only what is written from now on. What lies openly in the
/// profile today — the wording of every transcribed voice message, the
/// own profile picture, the self-description — would stay lying open and
/// nobody would ever come past it again.
///
/// **The order is the whole security.** Writing comes first, reading back
/// and checking second, deleting last. Every abort in between is without
/// consequence:
///
/// * Abort while writing — [FileEncryption.writeJsonFile] goes via
///   `$path.enc.tmp` and `renameSync`; there is either no `.enc` or a
///   complete one. The plaintext is untouched, the next start begins
///   from scratch.
/// * Abort after writing, before deleting — `.enc` is complete, the
///   plaintext still lies next to it. The next start finds a readable
///   ciphertext, removes the plaintext and reports [SweepOutcome.plaintextRemoved].
/// * Abort while deleting — `deleteSync` is a single `unlink`, it
///   happens entirely or not at all.
///
/// **What the cleaner does NOT do:** it does not overwrite an existing but
/// unreadable `.enc`. Unreadable as a rule means "written with a different
/// key" — then the ciphertext would be the more recent version and the
/// plaintext the older one, and an overwrite would throw away the more
/// recent one. It reports [SweepOutcome.failed] and leaves both files.
/// `CleonaService._loadContacts` follows the same pattern for
/// `contacts.json.enc`.
class PlaintextSweep {
  PlaintextSweep._();

  /// Converts exactly one file.
  ///
  /// [path] is the PLAINTEXT path (without `.enc`) — the same path that
  /// [FileEncryption.readJsonFile] expects.
  ///
  /// [toJson] translates the raw file content into the JSON form in which
  /// it is stored encrypted. For a file that is already JSON, that is
  /// `jsonDecode`; for a plain text file a wrapping like
  /// `(raw) => {'text': raw}`. If [toJson] throws, the run counts as
  /// failed and the plaintext stays.
  static SweepOutcome sweepOne({
    required FileEncryption fileEnc,
    required String path,
    required Map<String, dynamic> Function(String raw) toJson,
    CLogger? log,
  }) {
    final plain = File(path);
    if (!plain.existsSync()) return SweepOutcome.nothingToDo;

    // ── 1. Is there already a ciphertext? ────────────────────────────────────
    // Then it is authoritative — but only if it can also be READ.
    // The probe is the statement ("the content is recoverable in
    // encrypted form"), not the proxy "an .enc file is there".
    if (File('$path.enc').existsSync()) {
      final probe = fileEnc.readJsonFile(path);
      if (probe != null) {
        // `existsSync` BEFORE deleting, because the read itself may already
        // have deleted: since S362 `FileEncryption.readJsonFile` itself
        // cleans away a content-identical plaintext remnant next to a
        // readable ciphertext (`_dropRedundantPlaintext`). Exactly this
        // case is present here. Without the check `deleteSync` throws a
        // `PathNotFoundException` — and precisely when both mechanisms
        // have worked correctly.
        if (plain.existsSync()) plain.deleteSync();
        log?.info('Sweeper: $path was present twice — the ciphertext is '
            'readable, the plaintext version is removed.');
        return SweepOutcome.plaintextRemoved;
      }
      log?.warn('Sweeper: $path.enc is present but can NOT be '
          'decrypted. The plaintext version stays untouched — overwriting '
          'it could cost the newer version.');
      return SweepOutcome.failed;
    }

    // ── 2. Plaintext is the only version: write ──────────────────
    final Map<String, dynamic> json;
    try {
      json = toJson(plain.readAsStringSync());
    } catch (e) {
      log?.warn('Sweeper: $path cannot be read/interpreted: $e — '
          'nothing deleted.');
      return SweepOutcome.failed;
    }

    try {
      fileEnc.writeJsonFile(path, json);
    } catch (e) {
      log?.warn('Sweeper: $path could not be written encrypted: '
          '$e — the plaintext stays in place.');
      return SweepOutcome.failed;
    }

    // ── 3. Read back and compared BEFORE deleting ────────────
    // Without this step "written" would only mean "writeJsonFile did not
    // throw". What is checked is that the same content comes out again.
    final Map<String, dynamic>? back;
    try {
      back = fileEnc.readJsonFile(path);
    } catch (e) {
      log?.warn('Sweeper: $path.enc written, but the read-back check threw '
          '$e — the plaintext stays in place.');
      return SweepOutcome.failed;
    }
    if (back == null || jsonEncode(back) != jsonEncode(json)) {
      log?.warn('Sweeper: $path.enc written, but the read-back check did '
          'not yield the same content — the plaintext stays in place.');
      return SweepOutcome.failed;
    }

    // ── 4. Only now does the plaintext go ───────────────────────────────
    //
    // `existsSync` for the same reason as in step 1: the check-back
    // above runs via `readJsonFile`, and since S362 that itself cleans
    // away a content-identical plaintext remnant. Here it is
    // content-identical by construction — the `.enc` has just been
    // written FROM this plaintext. The state this step is meant to
    // produce ("the plaintext is gone") is then already reached; without
    // the check the run would end with a `PathNotFoundException` and tear
    // down the whole cleaner with it.
    if (plain.existsSync()) plain.deleteSync();
    log?.info('Sweeper: $path is stored encrypted and the '
        'plaintext version removed.');
    return SweepOutcome.migrated;
  }

  /// Wrapping for a file that already contains JSON.
  static Map<String, dynamic> asJson(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  /// Wrapping for a plain text file under the key [key].
  static Map<String, dynamic> Function(String) asText(String key) =>
      (raw) => <String, dynamic>{key: raw.trim()};
}
