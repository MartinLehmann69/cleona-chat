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
  Map<String, dynamic>? readJsonFile(String path) {
    final encFile = File('$path.enc');
    final plainFile = File(path);

    if (encFile.existsSync()) {
      try {
        final data = encFile.readAsBytesSync();
        if (data.length <= 24) {
          stderr.writeln('[FileEncryption] WARNING: $path.enc exists but is truncated '
              '(${data.length} bytes, need >24) — file corrupt?');
          return null;
        }

        final nonce = Uint8List.fromList(data.sublist(0, 24));
        final ciphertext = Uint8List.fromList(data.sublist(24));
        final plaintext = _sodium.secretBoxDecrypt(ciphertext, _key, nonce);
        return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
      } catch (e) {
        stderr.writeln('[FileEncryption] WARNING: $path.enc exists (${File('$path.enc').lengthSync()} bytes) '
            'but decryption failed: $e — wrong key or corrupt file?');
        return null;
      }
    }

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

  /// Encrypt and write a JSON file.
  void writeJsonFile(String path, Map<String, dynamic> json) {
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final nonce = _sodium.randomBytes(24);
    final ciphertext = _sodium.secretBoxEncrypt(plaintext, _key, nonce);

    final output = Uint8List(24 + ciphertext.length);
    output.setRange(0, 24, nonce);
    output.setRange(24, output.length, ciphertext);

    final encFile = File('$path.enc');
    encFile.parent.createSync(recursive: true);
    encFile.writeAsBytesSync(output);
  }
}
