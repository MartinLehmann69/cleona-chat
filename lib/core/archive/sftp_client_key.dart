// The identity's own SSH key for the media archive (§21.6, S423 A-1).
//
// On Android and iOS there is no `~/.ssh` of the account the app could use,
// so key login at an SFTP share needs a key that belongs to the identity.
// It is created on demand (Ed25519 through libsodium, the project's
// signature library) and kept where the share password already lies: a
// record in the identity's encrypted store (§21.4.1) — never as a file,
// never in the setting the settings screen receives. Only the public half
// leaves it, as the one line the user puts into `authorized_keys`.

import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/storage/encrypted_store.dart';

/// The store area of the key (one record).
const String kSftpClientKeyArea = 'archive_sftp_client_key';

/// The key of the ONE record in [kSftpClientKeyArea].
const String kSftpClientKeyKey = '_';

/// Comment of the public line, so the user recognises it in
/// `authorized_keys`.
const String kSftpClientKeyComment = 'cleona-archive';

class SftpClientKey {
  SftpClientKey._();

  /// The stored key (OpenSSH PEM), or `null` if none was created yet.
  /// A store that throws is not caught (unreadable ≠ empty).
  static String? readPem(EncryptedStore store) {
    final e = store.entry(kSftpClientKeyArea, kSftpClientKeyKey);
    final pem = e?['pem'];
    return pem is String && pem.isNotEmpty ? pem : null;
  }

  /// The stored key, created and stored first if there is none.
  static String ensurePem(EncryptedStore store, {SodiumFFI? sodium}) {
    final have = readPem(store);
    if (have != null) return have;
    final kp = (sodium ?? SodiumFFI()).generateEd25519KeyPair();
    // libsodium's 64-byte secret key (seed ‖ public key) is the layout the
    // OpenSSH key format stores for ssh-ed25519.
    final pem =
        OpenSSHEd25519KeyPair(kp.publicKey, kp.secretKey, kSftpClientKeyComment)
            .toPem();
    store.putEntry(kSftpClientKeyArea, kSftpClientKeyKey, {'pem': pem});
    return pem;
  }

  /// The `authorized_keys` line of [pem]: `ssh-ed25519 <base64> comment`.
  static String publicLine(String pem) {
    final kp = SSHKeyPair.fromPem(pem).first;
    return '${kp.type} ${base64.encode(kp.toPublicKey().encode())} '
        '$kSftpClientKeyComment';
  }
}
