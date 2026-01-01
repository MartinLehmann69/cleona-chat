import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Encrypts/decrypts JSON files on disk using XSalsa20-Poly1305.
///
/// Key source (Architecture §3.7):
/// - Preferred: explicit [key] parameter (seed-derived per §3.7/§3.8)
/// - Legacy fallback: random key from `<baseDir>/db.key` (pre-keyring profiles)
///
/// Format: [24-byte nonce][ciphertext with 16-byte MAC]
class FileEncryption {
  final String baseDir;
  late final Uint8List _key;
  final SodiumFFI _sodium = SodiumFFI();

  /// Create a FileEncryption instance.
  ///
  /// If [key] is provided, uses it directly (seed-derived, per §3.7).
  /// If [key] is null, falls back to the legacy db.key file (migration path).
  FileEncryption({required this.baseDir, Uint8List? key}) {
    _key = key ?? _loadOrCreateLegacyKey();
  }

  /// Legacy path: load or create a random key file. Only used for profiles
  /// that haven't been migrated to keyring-based key derivation yet.
  Uint8List _loadOrCreateLegacyKey() {
    final keyFile = File('$baseDir/db.key');
    final keyExists = keyFile.existsSync();

    if (keyExists) {
      final bytes = keyFile.readAsBytesSync();
      if (bytes.length == 32) return Uint8List.fromList(bytes);
      // Invalid length — try .migrated fallback below
    }

    // S106 defence-in-depth: if KeyMigration renamed db.key to
    // .db.key.migrated, use that instead of creating a new random key
    // (which would make all existing .enc files unreadable).
    final migratedFile = File('$baseDir/.db.key.migrated');
    if (migratedFile.existsSync()) {
      final bytes = migratedFile.readAsBytesSync();
      if (bytes.length == 32) {
        stderr.writeln('[FileEncryption] WARNING: db.key missing/corrupt but '
            '.db.key.migrated exists — using migrated key as fallback');
        return Uint8List.fromList(bytes);
      }
    }

    // §3.7 fail-loud: if db.key existed with wrong length and no
    // .migrated fallback, check if profile data would be lost.
    if (keyExists) {
      final hasProfileData = Directory('$baseDir/identities').existsSync();
      if (hasProfileData) {
        throw StateError(
            'db.key has invalid length ${keyFile.lengthSync()} '
            '(expected 32) and profile data exists — refusing to '
            'generate new key (would make encrypted data unreadable)');
      }
      stderr.writeln('[FileEncryption] WARNING: corrupt db.key '
          'with no profile data — regenerating (interrupted first write)');
    }

    // Genuine fresh install — generate new random key
    final key = _sodium.randomBytes(32);
    Directory(baseDir).createSync(recursive: true);
    keyFile.writeAsBytesSync(key);

    if (Platform.isLinux || Platform.isMacOS) {
      Process.runSync('chmod', ['600', keyFile.path]);
    }

    return key;
  }

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
      try {
        return decryptOrThrow(encFile);
      } catch (e) {
        stderr.writeln('[FileEncryption] WARNING: $path.enc exists (${encFile.lengthSync()} bytes) '
            'but decryption failed: $e — attempting crash-recovery from sidecars.');
        // fall through to sidecar recovery below
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

    // Migration: read plain JSON and re-encrypt
    if (plainFile.existsSync()) {
      try {
        final json = jsonDecode(plainFile.readAsStringSync()) as Map<String, dynamic>;
        // Re-save encrypted
        writeJsonFile(path, json);
        // Remove plain file
        plainFile.deleteSync();
        return json;
      } catch (e) {
        stderr.writeln('[FileEncryption] WARNING: Migration failed for $path: $e');
        return null;
      }
    }

    return null;
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
  void writeBinaryFile(String path, Uint8List plaintext) {
    final nonce = _sodium.randomBytes(24);
    final ciphertext = _sodium.secretBoxEncrypt(plaintext, _key, nonce);

    final output = Uint8List(24 + ciphertext.length);
    output.setRange(0, 24, nonce);
    output.setRange(24, output.length, ciphertext);

    final encFile = File('$path.enc');
    final tmpFile = File('$path.enc.tmp');
    final oldFile = File('$path.enc.old');
    encFile.parent.createSync(recursive: true);

    try {
      tmpFile.writeAsBytesSync(output, flush: true);
      if (Platform.isWindows && encFile.existsSync()) {
        if (oldFile.existsSync()) oldFile.deleteSync();
        encFile.renameSync(oldFile.path);
        try {
          tmpFile.renameSync(encFile.path);
        } catch (e) {
          if (oldFile.existsSync() && !encFile.existsSync()) {
            oldFile.renameSync(encFile.path);
          }
          rethrow;
        }
        if (oldFile.existsSync()) oldFile.deleteSync();
      } else {
        tmpFile.renameSync(encFile.path);
      }
    } catch (e) {
      if (tmpFile.existsSync()) {
        try { tmpFile.deleteSync(); } catch (_) {}
      }
      rethrow;
    }
  }

  /// Encrypt and atomically write a JSON file via tmp+rename.
  /// POSIX: `renameSync` is crash-atomic (old or new, never torn).
  /// Windows: `renameSync` cannot overwrite, so we stage canonical→.enc.old
  /// first; readJsonFile recovers from .tmp/.old sidecars if we crash between steps.
  void writeJsonFile(String path, Map<String, dynamic> json) {
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final nonce = _sodium.randomBytes(24);
    final ciphertext = _sodium.secretBoxEncrypt(plaintext, _key, nonce);

    final output = Uint8List(24 + ciphertext.length);
    output.setRange(0, 24, nonce);
    output.setRange(24, output.length, ciphertext);

    final encFile = File('$path.enc');
    final tmpFile = File('$path.enc.tmp');
    final oldFile = File('$path.enc.old');
    encFile.parent.createSync(recursive: true);

    try {
      tmpFile.writeAsBytesSync(output, flush: true);
      if (Platform.isWindows && encFile.existsSync()) {
        if (oldFile.existsSync()) oldFile.deleteSync();
        encFile.renameSync(oldFile.path);
        try {
          tmpFile.renameSync(encFile.path);
        } catch (e) {
          // rollback: restore the old canonical so we don't lose state.
          if (oldFile.existsSync() && !encFile.existsSync()) {
            oldFile.renameSync(encFile.path);
          }
          rethrow;
        }
        if (oldFile.existsSync()) oldFile.deleteSync();
      } else {
        tmpFile.renameSync(encFile.path);
      }
    } catch (e) {
      if (tmpFile.existsSync()) {
        try { tmpFile.deleteSync(); } catch (_) {}
      }
      rethrow;
    }
  }
}
