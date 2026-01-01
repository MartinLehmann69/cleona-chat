import 'dart:typed_data';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Per-Message Key Encapsulation: stateless E2E encryption.
/// Every message is encrypted with a fresh ephemeral key pair.
/// No session state, no handshake, no synchronization.
class PerMessageKem {
  static final _sodium = SodiumFFI();
  static final _oqs = OqsFFI();

  /// Encrypt a message for a recipient.
  static (proto.PerMessageKem, Uint8List) encrypt({
    required Uint8List plaintext,
    required Uint8List recipientX25519Pk,
    required Uint8List recipientMlKemPk,
  }) {
    // 1. Generate ephemeral X25519 key pair
    final ephEd25519 = _sodium.generateEd25519KeyPair();
    final ephX25519Pk = _sodium.ed25519PkToX25519(ephEd25519.publicKey);
    final ephX25519Sk = _sodium.ed25519SkToX25519(ephEd25519.secretKey);

    // 2. X25519 DH
    final dhSecret = _sodium.x25519ScalarMult(ephX25519Sk, recipientX25519Pk);

    // 3. ML-KEM-768 encapsulation
    final kemResult = _oqs.mlKemEncapsulate(recipientMlKemPk);
    final kemCiphertext = kemResult.ciphertext;
    final kemSecret = kemResult.sharedSecret;

    // 4. Derive message key: HKDF-SHA256(dhSecret || kemSecret, "cleona-msg-v1")
    final ikm = Uint8List(dhSecret.length + kemSecret.length);
    ikm.setRange(0, dhSecret.length, dhSecret);
    ikm.setRange(dhSecret.length, ikm.length, kemSecret);
    final msgKey = _sodium.hkdfSha256(
      ikm,
      salt: Uint8List(32),
      info: Uint8List.fromList('cleona-msg-v1'.codeUnits),
      length: 32,
    );

    // 5. Encrypt with AES-256-GCM
    final nonce = _sodium.generateNonce();
    final ciphertext = _sodium.aesGcmEncrypt(plaintext, msgKey, nonce);

    // 6. Build KEM header
    final header = proto.PerMessageKem()
      ..ephemeralX25519Pk = ephX25519Pk
      ..mlKemCiphertext = kemCiphertext
      ..aesNonce = nonce;

    // 7. Zero ephemeral secrets
    for (var i = 0; i < ephX25519Sk.length; i++) { ephX25519Sk[i] = 0; }
    for (var i = 0; i < ephEd25519.secretKey.length; i++) { ephEd25519.secretKey[i] = 0; }

    return (header, ciphertext);
  }

  /// Decrypt a message using our private keys.
  static Uint8List decrypt({
    required proto.PerMessageKem kemHeader,
    required Uint8List ciphertext,
    required Uint8List ourX25519Sk,
    required Uint8List ourMlKemSk,
  }) {
    // 1. X25519 DH with ephemeral public key
    final ephPk = Uint8List.fromList(kemHeader.ephemeralX25519Pk);
    final dhSecret = _sodium.x25519ScalarMult(ourX25519Sk, ephPk);

    // 2. ML-KEM-768 decapsulation
    final kemCiphertext = Uint8List.fromList(kemHeader.mlKemCiphertext);
    final kemSecret = _oqs.mlKemDecapsulate(kemCiphertext, ourMlKemSk);

    // 3. Derive the same message key
    final ikm = Uint8List(dhSecret.length + kemSecret.length);
    ikm.setRange(0, dhSecret.length, dhSecret);
    ikm.setRange(dhSecret.length, ikm.length, kemSecret);
    final msgKey = _sodium.hkdfSha256(
      ikm,
      salt: Uint8List(32),
      info: Uint8List.fromList('cleona-msg-v1'.codeUnits),
      length: 32,
    );

    // 4. Decrypt with AES-256-GCM
    final nonce = Uint8List.fromList(kemHeader.aesNonce);
    return _sodium.aesGcmDecrypt(ciphertext, msgKey, nonce);
  }

  /// Check if a message type should be encrypted with Per-Message KEM.
  static bool shouldEncrypt(proto.MessageType type) {
    switch (type) {
      case proto.MessageType.CONTACT_REQUEST:
      case proto.MessageType.CONTACT_REQUEST_RESPONSE:
      case proto.MessageType.RESTORE_BROADCAST:
      case proto.MessageType.RESTORE_RESPONSE:
      case proto.MessageType.DHT_PING:
      case proto.MessageType.DHT_PONG:
      case proto.MessageType.DHT_FIND_NODE:
      case proto.MessageType.DHT_FIND_NODE_RESPONSE:
      case proto.MessageType.DHT_STORE:
      case proto.MessageType.DHT_STORE_RESPONSE:
      case proto.MessageType.DHT_FIND_VALUE:
      case proto.MessageType.DHT_FIND_VALUE_RESPONSE:
      case proto.MessageType.FRAGMENT_STORE:
      case proto.MessageType.FRAGMENT_STORE_ACK:
      case proto.MessageType.FRAGMENT_RETRIEVE:
      case proto.MessageType.FRAGMENT_DELETE:
      case proto.MessageType.PEER_LIST_SUMMARY:
      case proto.MessageType.PEER_LIST_WANT:
      case proto.MessageType.PEER_LIST_PUSH:
        return false;
      default:
        return true;
    }
  }

  /// Check if a message type is ephemeral (skip erasure-coded backup).
  static bool isEphemeral(proto.MessageType type) {
    switch (type) {
      case proto.MessageType.TYPING_INDICATOR:
      case proto.MessageType.READ_RECEIPT:
      case proto.MessageType.DELIVERY_RECEIPT:
      case proto.MessageType.FREE_BUSY_REQUEST:
      case proto.MessageType.FREE_BUSY_RESPONSE:
        return true;
      default:
        return false;
    }
  }
}
