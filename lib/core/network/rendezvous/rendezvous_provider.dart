/// Abstract RendezvousProvider interface + SignedEndpointRecord model.
///
/// Architecture §4.11.2 (Interface) + §4.11.5 (SignedEndpointRecord).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

// ---------------------------------------------------------------------------
// RendezvousProvider Interface (§4.11.2)
// ---------------------------------------------------------------------------

abstract class RendezvousProvider {
  /// Publish a signed, encrypted endpoint record under the derived lookup tag.
  Future<void> publish(Uint8List lookupTag, SignedEndpointRecord record);

  /// Resolve the record under the tag. Returns null if nothing found or
  /// the channel is blocked in the current network.
  Future<SignedEndpointRecord?> resolve(Uint8List lookupTag);

  /// Whether this provider is usable in the current network context.
  bool get isAvailable;
}

// ---------------------------------------------------------------------------
// EndpointRecord (plaintext, inside AEAD)
// ---------------------------------------------------------------------------

class EndpointAddress {
  final String ip;
  final int port;

  const EndpointAddress(this.ip, this.port);

  Map<String, dynamic> toJson() => {'i': ip, 'p': port};

  static EndpointAddress fromJson(Map<String, dynamic> j) =>
      EndpointAddress(j['i'] as String, j['p'] as int);
}

class EndpointRecord {
  final List<EndpointAddress> addresses;
  final int seq;
  final int publishedAt;
  final Uint8List deviceId;

  const EndpointRecord({
    required this.addresses,
    required this.seq,
    required this.publishedAt,
    required this.deviceId,
  });

  Uint8List serialize() {
    final json = {
      'a': addresses.map((a) => a.toJson()).toList(),
      's': seq,
      't': publishedAt,
      'd': base64Encode(deviceId),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  static EndpointRecord? deserialize(Uint8List data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      return EndpointRecord(
        addresses: (json['a'] as List)
            .map((e) => EndpointAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
        seq: json['s'] as int,
        publishedAt: json['t'] as int,
        deviceId: base64Decode(json['d'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// SignedEndpointRecord (§4.11.5) — substrate-facing envelope
// ---------------------------------------------------------------------------

class SignedEndpointRecord {
  final Uint8List nonce;
  final Uint8List ciphertext;
  final int seq;

  const SignedEndpointRecord({
    required this.nonce,
    required this.ciphertext,
    required this.seq,
  });

  /// Serialize for transport (base64 content on Nostr).
  Uint8List serialize() {
    // Format: [1B version][12B nonce][8B seq BE][ciphertext...]
    final bb = BytesBuilder(copy: false);
    bb.addByte(0x01); // version
    bb.add(nonce);
    final seqBytes = ByteData(8)..setUint64(0, seq);
    bb.add(seqBytes.buffer.asUint8List());
    bb.add(ciphertext);
    return bb.toBytes();
  }

  static SignedEndpointRecord? deserialize(Uint8List data) {
    // version(1) + nonce(12) + seq(8) + min ciphertext(16 tag) = 37
    if (data.length < 37) return null;
    if (data[0] != 0x01) return null;
    final nonce = Uint8List.sublistView(data, 1, 13);
    final seqBytes = ByteData.sublistView(data, 13, 21);
    final seq = seqBytes.getUint64(0);
    final ciphertext = Uint8List.sublistView(data, 21);
    return SignedEndpointRecord(nonce: nonce, ciphertext: ciphertext, seq: seq);
  }
}

// ---------------------------------------------------------------------------
// Encrypt / Decrypt helpers
// ---------------------------------------------------------------------------

/// Encrypts an [EndpointRecord] into a [SignedEndpointRecord].
///
/// Uses AES-256-GCM with AAD = lookupTag (binds the ciphertext to the
/// specific tag, preventing record relocation attacks).
SignedEndpointRecord encryptEndpointRecord(
  EndpointRecord record,
  Uint8List rendezvousSecret,
  Uint8List lookupTag,
) {
  final sodium = SodiumFFI();
  final plaintext = record.serialize();
  final nonce = sodium.generateNonce(); // 12 bytes for AES-256-GCM
  final ciphertext = sodium.aesGcmEncrypt(
    plaintext,
    rendezvousSecret,
    nonce,
    ad: lookupTag,
  );
  return SignedEndpointRecord(
    nonce: nonce,
    ciphertext: ciphertext,
    seq: record.seq,
  );
}

/// Decrypts a [SignedEndpointRecord] back to an [EndpointRecord].
///
/// Returns null if decryption or authentication fails (wrong key, tampered
/// data, or lookupTag mismatch).
EndpointRecord? decryptEndpointRecord(
  SignedEndpointRecord record,
  Uint8List rendezvousSecret,
  Uint8List lookupTag,
) {
  try {
    final plaintext = SodiumFFI().aesGcmDecrypt(
      record.ciphertext,
      rendezvousSecret,
      record.nonce,
      ad: lookupTag,
    );
    return EndpointRecord.deserialize(plaintext);
  } catch (_) {
    return null;
  }
}
