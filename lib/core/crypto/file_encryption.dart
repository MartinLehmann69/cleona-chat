import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Encrypts/decrypts JSON files on disk using XSalsa20-Poly1305.
///
/// Key is stored in `<baseDir>/db.key` with restricted permissions.
/// Format: [24-byte nonce][ciphertext with 16-byte MAC]
class FileEncryption {
  final String baseDir;
  late final Uint8List _key;
  final SodiumFFI _sodium = SodiumFFI();

  FileEncryption({required this.baseDir}) {
    _key = _loadOrCreateKey();
  }

  Uint8List _loadOrCreateKey() {
    final keyFile = File('$baseDir/db.key');
    if (keyFile.existsSync()) {
      final bytes = keyFile.readAsBytesSync();
      if (bytes.length == 32) return Uint8List.fromList(bytes);
    }

    // Generate new random key
    final key = _sodium.randomBytes(32);
    Directory(baseDir).createSync(recursive: true);
    keyFile.writeAsBytesSync(key);

    // Restrict permissions (owner-only read/write)
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
