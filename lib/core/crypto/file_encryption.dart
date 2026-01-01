import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/storage/atomic_replace.dart';

/// Encrypts/decrypts JSON files on disk using XSalsa20-Poly1305.
///
/// Key source (Architecture §3.7 / v4_1 §4.5.3, §21.4):
/// - **The key is PASSED IN**, seed-derived
///   (`HdWallet.deriveFileEncKey` / `deriveSharedFileEncKey`).
/// - Legacy holdings may still lie under the random `db.key`; that is
///   READ via [legacyOrNull] in order to replace it — never to keep
///   writing it.
///
/// ── THIS CLASS NO LONGER GENERATES A KEY (S368) ──────────────
///
/// Until S368 the keyless constructor CREATED 32 random bytes as
/// `<baseDir>/db.key` when needed (`_loadOrCreateLegacyKey`). That was the
/// producer of the plaintext key through which, on a freshly created
/// profile, the whole chain ran:
///
///     db.key (plaintext, 32 B)
///       -> master_seed.json.enc
///       -> master_seed
///       -> deriveFileEncKey(seed, hdIndex)
///       -> messages.db          (the entire message storage)
///
/// The target state had been built since 3.2.2 and was never disputed:
/// the seed lies in the keyring, and the file next to it is deleted as
/// soon as it lies there (`maintenance/3.2:key_migration.dart:251-252`). A
/// post-quantum-secure messenger does not store a key in plaintext.
///
/// The constructor WITHOUT [key] therefore **throws** if no legacy key
/// is present. Whoever wants to read legacy holdings takes [legacyOrNull]
/// and handles `null`.
///
/// Format: [24-byte nonce][ciphertext with 16-byte MAC]
class FileEncryption {
  final String baseDir;
  late final Uint8List _key;
  final SodiumFFI _sodium = SodiumFFI();

  /// Create a FileEncryption instance.
  ///
  /// [key] is the normal case (seed-derived, §3.7). Without [key] an
  /// EXISTING legacy key is read; if there is none, it throws —
  /// none is generated any more.
  FileEncryption({required this.baseDir, Uint8List? key}) {
    _key = key ?? _loadLegacyKeyOrThrow(baseDir);
  }

  /// The storage of legacy holdings, or `null` if there is no legacy
  /// key. **Never creates one.**
  ///
  /// This is the only permissible path to a `db.key`-sealed holding: it
  /// has a `null` that the caller must handle, instead of silently
  /// inventing a fresh random key and then failing on a ciphertext that
  /// it has itself made unreadable.
  static FileEncryption? legacyOrNull(String baseDir) {
    final bytes = legacyKeyBytes(baseDir);
    if (bytes == null) return null;
    return FileEncryption(baseDir: baseDir, key: bytes);
  }

  /// Whether this profile carries a legacy key at all any more.
  static bool hasLegacyKey(String baseDir) => legacyKeyBytes(baseDir) != null;

  /// Reads the legacy key without ever generating one: `db.key`, otherwise
  /// `.db.key.migrated` (the takeover that existed until S368 left that
  /// behind). `null` if neither is present in usable form.
  static Uint8List? legacyKeyBytes(String baseDir) {
    for (final name in ['db.key', '.db.key.migrated']) {  // V3-TOUCH-OK: legacy key fallback, normative in v4_1 §4.5.3 (db.key is one of the six files that never move into the database)
      final f = File('$baseDir/$name');
      if (!f.existsSync()) continue;
      final bytes = f.readAsBytesSync();
      if (bytes.length == 32) return Uint8List.fromList(bytes);
      stderr.writeln('[FileEncryption] WARNING: $name has ${bytes.length} B '
          '(expected 32) — ignored, NOT replaced');
    }
    return null;
  }

  static Uint8List _loadLegacyKeyOrThrow(String baseDir) {
    final bytes = legacyKeyBytes(baseDir);
    if (bytes != null) return bytes;
    throw StateError(
        'FileEncryption without a key and no legacy key file in $baseDir — '  // V3-TOUCH-OK: legacy key fallback, normative in v4_1 §4.5.3 (db.key is one of the six files that never move into the database)
        'refusing to mint a random db.key (S368: that file was the plaintext '
        'root of the chain db.key -> master_seed.json.enc -> message store). '
        'Pass a seed-derived key, or use FileEncryption.legacyOrNull().');
  }

  /// The key under which this storage works — seed-derived
  /// or (legacy profile, linked device without seed) the legacy `db.key`.
  ///
  /// **What for.** `MediaStore` (S362) seals the attachments and must use
  /// THE SAME base key as the messages they hang on — otherwise a profile
  /// would have two key classes, and a seed change would make one
  /// unreadable and the other not. The separation of the two uses happens
  /// one level deeper, via separate HKDF identifiers in `MediaCipher`
  /// (`cleona-media-enc-v1`, `cleona-media-hdr-v1`) — the base key itself
  /// is never used raw for encryption.
  Uint8List get effectiveKey => _key;

  /// Read and decrypt a JSON file. Returns null if file doesn't exist or
  /// cannot be decrypted (logs error details to stderr for diagnostics).
  /// Falls back to reading plain JSON for migration from unencrypted files.
  /// Recovery: if `$path.enc` is missing or corrupt but `$path.enc.tmp` or
  /// `$path.enc.old` exist (crash mid-write), they are probed as fallback.
  Map<String, dynamic>? readJsonFile(String path) {
    final encFile = File('$path.enc');
    final plainFile = File(path);

    // Throws on any corruption (truncated, bad MAC, bad UTF-8, bad JSON) so
    // readJsonFile can distinguish "file ok, nothing to decode" from "retry sidecars".
    Map<String, dynamic> decryptOrThrow(File f) {
      final data = f.readAsBytesSync();
      if (data.length <= 24) {
        throw StateError('truncated (${data.length} bytes, need >24)');
      }
      final nonce = Uint8List.fromList(data.sublist(0, 24));
      final ciphertext = Uint8List.fromList(data.sublist(24));
      final plaintext = _sodium.secretBoxDecrypt(ciphertext, _key, nonce);
      return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    }

    if (encFile.existsSync()) {
      Map<String, dynamic>? decrypted;
      try {
        decrypted = decryptOrThrow(encFile);
      } catch (e) {
        stderr.writeln('[FileEncryption] WARNING: $path.enc exists (${encFile.lengthSync()} bytes) '
            'but decryption failed: $e — attempting crash-recovery from sidecars.');
        // fall through to sidecar recovery below
      }
      if (decrypted != null) {
        // S362: the migration path below cleans up here. The call stands
        // DELIBERATELY outside the `try` above — if it stood inside it and
        // threw, decryption would run into the sidecar branch although the
        // ciphertext was flawless.
        _dropRedundantPlaintext(path, plainFile, decrypted);
        return decrypted;
      }
    }

    // Crash-recovery: probe tmp/old sidecars (atomic-write interrupted).
    for (final suffix in ['.enc.tmp', '.enc.old']) {
      final side = File('$path$suffix');
      if (!side.existsSync()) continue;
      try {
        final recovered = decryptOrThrow(side);
        stderr.writeln('[FileEncryption] INFO: recovered $path from $suffix sidecar.');
        // Promote sidecar to canonical via atomic write.
        writeJsonFile(path, recovered);
        return recovered;
      } catch (e) {
        stderr.writeln('[FileEncryption] WARNING: sidecar $path$suffix unreadable: $e');
      }
    }

    if (encFile.existsSync()) return null; // canonical present but corrupt, no usable sidecar

    // ── S368: A PLAINTEXT WITHOUT CIPHERTEXT IS NO LONGER TAKEN OVER ──
    //
    // Here stood the takeover: read plaintext, write encrypted, delete
    // plaintext, return content ("Migration: read plain JSON
    // and re-encrypt"). It was the intake path for profiles from the time
    // before encryption of data at rest.
    //
    // Such profiles do not reach this version (`FirstStartWipe`), and the
    // owner excluded their takeover literally six times
    // ("Nothing is migrated!", "Neither data - nor on the network!",
    // 05.09.2026). For every foreign format on this line: REJECT.
    //
    // REJECTING HERE MEANS LOUDLY, NOT SILENTLY. A `return null` alone
    // would have the same value as "file not present" — and the plaintext
    // would keep lying openly on the disk without anyone learning of it.
    // Hence the message. It is NOT DELETED: we do not read it, so we also
    // do not know what would be lost.
    //
    // The cleanup [_dropRedundantPlaintext] above REMAINS untouched —
    // it is the enforcer, not an intake path: it deletes a plaintext only
    // if a READABLE ciphertext with the SAME content lies next to it.
    if (plainFile.existsSync()) {
      stderr.writeln('[FileEncryption] WARNING: $path lies in PLAINTEXT and '
          'without ciphertext next to it. V4.1 takes over no unencrypted '
          'old stock (S368) — the file is NOT read and NOT '
          'deleted. It still lies open on the disk.');
      return null;
    }

    return null;
  }

  /// Cleans up a plaintext version that has been left lying NEXT TO a
  /// readable ciphertext.
  ///
  /// **The leak this method closes.** The migration branch at the end of
  /// [readJsonFile] takes three steps: read plaintext, write encrypted,
  /// delete plaintext. If the process dies between step 2 and
  /// 3 — crash, `SIGKILL`, power failure, Android process death —, then
  /// the `.enc` lies there completely AND the plaintext next to it. On the
  /// next read the `.enc` branch at the very top takes over and returns
  /// immediately: the plaintext is never touched again and stays lying
  /// open **forever**. Exactly the file that was supposed to be encrypted
  /// is then permanently readable in plaintext, and nothing reports it.
  ///
  /// **Why the cleanup sits here and not in a file list.** The leak is in
  /// the migration path itself, so the seal belongs in the same place. A
  /// list of affected file names — e.g. in `PlaintextSweep` — would only
  /// ever cover the names someone entered, and would lag behind every new
  /// file. [readJsonFile] carries ALL of them, today and in future.
  ///
  /// **Deletion only on equality.** A mere "`.enc` is there, away with the
  /// plaintext" would be wrong: if the plaintext is present because an
  /// older write path wrote it AFTER the ciphertext, it would be the more
  /// recent version and deleting it a data loss. The content is therefore
  /// compared; on inequality both files stay and there is a message. The
  /// same order — first compare, then delete — is followed by
  /// `PlaintextSweep.sweepOne`.
  void _dropRedundantPlaintext(
      String path, File plainFile, Map<String, dynamic> decrypted) {
    if (!plainFile.existsSync()) return;
    try {
      final raw = jsonDecode(plainFile.readAsStringSync());
      if (raw is! Map<String, dynamic> ||
          jsonEncode(raw) != jsonEncode(decrypted)) {
        stderr.writeln('[FileEncryption] WARNING: $path lies in plaintext '
            'next to a readable $path.enc, but has a DIFFERENT content '
            '— both stay in place (the plaintext version could be the '
            'newer one).');
        return;
      }
      plainFile.deleteSync();
      stderr.writeln('[FileEncryption] INFO: $path was a remnant of an '
          'aborted migration (ciphertext written, plaintext no '
          'longer deleted) — the plaintext version is now removed.');
    } catch (e) {
      stderr.writeln('[FileEncryption] WARNING: plaintext remnant $path could '
          'not be checked/removed: $e — it stays in place.');
    }
  }

  /// Read and decrypt a binary blob. Returns null if the file doesn't exist
  /// or cannot be decrypted (truncated / bad MAC). Mirrors `readJsonFile`'s
  /// crash-recovery sweep over `.enc.tmp` / `.enc.old` sidecars.
  ///
  /// Use this for fixed-shape on-disk artefacts like the Device-Sig keypair
  /// (`device_keys.bin.enc`, 6096 bytes) where JSON wrapping would only add
  /// base64 overhead and a parse step that buys nothing.
  Uint8List? readBinaryFile(String path) {
    final encFile = File('$path.enc');

    Uint8List decryptOrThrow(File f) {
      final data = f.readAsBytesSync();
      if (data.length <= 24) {
        throw StateError('truncated (${data.length} bytes, need >24)');
      }
      final nonce = Uint8List.fromList(data.sublist(0, 24));
      final ciphertext = Uint8List.fromList(data.sublist(24));
      return _sodium.secretBoxDecrypt(ciphertext, _key, nonce);
    }

    if (encFile.existsSync()) {
      try {
        return decryptOrThrow(encFile);
      } catch (e) {
        stderr.writeln('[FileEncryption] WARNING: $path.enc exists '
            '(${encFile.lengthSync()} bytes) but binary decryption failed: $e '
            '— attempting crash-recovery from sidecars.');
      }
    }

    for (final suffix in ['.enc.tmp', '.enc.old']) {
      final side = File('$path$suffix');
      if (!side.existsSync()) continue;
      try {
        final recovered = decryptOrThrow(side);
        stderr.writeln('[FileEncryption] INFO: recovered binary $path '
            'from $suffix sidecar.');
        writeBinaryFile(path, recovered);
        return recovered;
      } catch (e) {
        stderr.writeln('[FileEncryption] WARNING: sidecar $path$suffix '
            'unreadable: $e');
      }
    }
    return null;
  }

  /// Encrypt and atomically write a binary blob via tmp+rename. Same atomic
  /// guarantees as [writeJsonFile]; callers do NOT need their own locking.
  /// Here too the Windows three-step ran until S371 — see
  /// [writeJsonFile] and [atomicReplace].
  void writeBinaryFile(String path, Uint8List plaintext) {
    final nonce = _sodium.randomBytes(24);
    final ciphertext = _sodium.secretBoxEncrypt(plaintext, _key, nonce);

    final output = Uint8List(24 + ciphertext.length);
    output.setRange(0, 24, nonce);
    output.setRange(24, output.length, ciphertext);

    final encFile = File('$path.enc');
    final tmpFile = File('$path.enc.tmp');
    encFile.parent.createSync(recursive: true);

    try {
      tmpFile.writeAsBytesSync(output, flush: true);
      atomicReplace(tmpFile, encFile);
    } catch (e) {
      if (tmpFile.existsSync()) {
        try { tmpFile.deleteSync(); } catch (_) {}
      }
      rethrow;
    }
  }

  /// Deletes an encrypted storage completely — ciphertext AND the two
  /// sidecars `.enc.tmp` / `.enc.old`.
  ///
  /// Whoever only calls `File('$path.enc').deleteSync()` does not delete:
  /// if a sidecar from an aborted write stays behind, [readJsonFile]
  /// fetches the supposedly deleted content back from it on the next read
  /// and even writes it back up to the canonical one (crash-recovery
  /// branch above). Exactly that hits deleted user content — a removed
  /// profile picture would be back.
  void deleteFile(String path) {
    for (final suffix in ['.enc', '.enc.tmp', '.enc.old']) {
      final f = File('$path$suffix');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (e) {
          stderr.writeln('[FileEncryption] WARNING: could not delete '
              '$path$suffix: $e');
        }
      }
    }
  }

  /// Encrypt and atomically write a JSON file via tmp+rename.
  ///
  /// Until S371 here stood "Windows: `renameSync` cannot overwrite, so we
  /// stage canonical→.enc.old first". **The claim is refuted by
  /// measurement** (Windows machine, 05.09.2026: `MoveFileExW` with
  /// `MOVEFILE_REPLACE_EXISTING`, 8 of 8 runs complete). The three-step
  /// it justified left the canonical name missing in about a third of all
  /// looks and is deleted; measurement table and reasoning for the retry
  /// stand at [atomicReplace].
  ///
  /// POSIX as well as Windows: ONE `renameSync`, crash-atomic. `.enc.old`
  /// is no longer produced — [readJsonFile] and [deleteFile] still handle
  /// it, because a profile from an older version may carry one.
  void writeJsonFile(String path, Map<String, dynamic> json) {
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final nonce = _sodium.randomBytes(24);
    final ciphertext = _sodium.secretBoxEncrypt(plaintext, _key, nonce);

    final output = Uint8List(24 + ciphertext.length);
    output.setRange(0, 24, nonce);
    output.setRange(24, output.length, ciphertext);

    final encFile = File('$path.enc');
    final tmpFile = File('$path.enc.tmp');
    encFile.parent.createSync(recursive: true);

    try {
      tmpFile.writeAsBytesSync(output, flush: true);
      atomicReplace(tmpFile, encFile);
    } catch (e) {
      if (tmpFile.existsSync()) {
        try { tmpFile.deleteSync(); } catch (_) {}
      }
      rethrow;
    }
  }
}
