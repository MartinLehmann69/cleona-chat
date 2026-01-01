import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/services/contact_manager.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex;

// ---------------------------------------------------------------------------
// NFC Contact Exchange — Architecture Section 2.3.4
//
// Dual-purpose NFC tap:
//   1. Contact Pairing — mutual consent, Verification Level 3 (Verified)
//   2. Peer Discovery — peer lists are merged
//
// Binary payload format (signed with Ed25519):
//   [4B magic "NFCX"]
//   [1B version]
//   [4B timestamp (seconds since epoch, big-endian)]
//   [32B nodeId]
//   [1B displayNameLen][displayName UTF-8]
//   [32B ed25519PublicKey]
//   [2B mlDsaPublicKeyLen (big-endian)][mlDsaPublicKey]
//   [32B x25519PublicKey]
//   [2B mlKemPublicKeyLen (big-endian)][mlKemPublicKey]
//   [2B profilePictureLen (big-endian)][profilePicture]  — 0 if none
//   [2B descriptionLen (big-endian)][description UTF-8]  — 0 if none
//   [1B addressCount][for each: 1B len + address UTF-8]
//   [1B peerCount][for each: 32B nodeId + 1B addrCount + (1B len + addr)]
//   [64B ed25519Signature]  — over all bytes before signature
//
// Total without profile pic: ~3.5 KB (fits NFC easily)
// Max payload: ~70 KB (with 64KB profile picture)
// ---------------------------------------------------------------------------

/// Magic bytes identifying an NFC Contact Exchange payload.
const List<int> nfcMagic = [0x4E, 0x46, 0x43, 0x58]; // "NFCX"

/// Current protocol version.
const int nfcProtocolVersion = 1;

/// Maximum age of an NFC payload before it's considered stale (5 minutes).
const int nfcMaxAgeSec = 300;

/// Maximum display name length in bytes (UTF-8).
const int nfcMaxDisplayNameBytes = 200;

/// Maximum description length in bytes (UTF-8).
const int nfcMaxDescriptionBytes = 1500;

/// Maximum profile picture size in bytes.
const int nfcMaxProfilePictureBytes = 65536; // 64 KB

/// Maximum number of addresses.
const int nfcMaxAddresses = 8;

/// Maximum number of seed peers.
const int nfcMaxPeers = 10;

/// Maximum single address length in bytes.
const int nfcMaxAddressBytes = 60;

/// Ed25519 signature size.
const int _ed25519SigBytes = 64;

/// Ed25519 public key size.
const int _ed25519PkBytes = 32;

// ---------------------------------------------------------------------------
// NfcPeerEntry — compact peer info for NFC exchange
// ---------------------------------------------------------------------------

class NfcPeerEntry {
  final Uint8List nodeId; // 32 bytes
  final List<String> addresses;

  NfcPeerEntry({required this.nodeId, required this.addresses});

  @override
  String toString() =>
      'NfcPeer(${bytesToHex(nodeId).substring(0, 8)}.. ${addresses.length} addrs)';
}

// ---------------------------------------------------------------------------
// NfcContactPayload — data exchanged via NFC tap
// ---------------------------------------------------------------------------

class NfcContactPayload {
  final Uint8List nodeId; // 32 bytes
  final String displayName;
  final Uint8List ed25519PublicKey; // 32 bytes
  final Uint8List mlDsaPublicKey; // 1952 bytes (ML-DSA-65)
  final Uint8List x25519PublicKey; // 32 bytes
  final Uint8List mlKemPublicKey; // 1184 bytes (ML-KEM-768)
  final Uint8List? profilePicture; // JPEG, max 64 KB
  final String? description; // max 500 chars
  final List<String> addresses; // "ip:port" pairs
  final List<NfcPeerEntry> seedPeers; // compact peer list
  final int timestampSec; // seconds since epoch

  NfcContactPayload({
    required this.nodeId,
    required this.displayName,
    required this.ed25519PublicKey,
    required this.mlDsaPublicKey,
    required this.x25519PublicKey,
    required this.mlKemPublicKey,
    this.profilePicture,
    this.description,
    required this.addresses,
    required this.seedPeers,
    required this.timestampSec,
  });

  /// Serializes the payload to binary (WITHOUT signature).
  /// The caller signs this and appends the 64-byte signature.
  Uint8List serializeUnsigned() {
    final buf = BytesBuilder(copy: false);

    // Magic + version
    buf.add(nfcMagic);
    buf.addByte(nfcProtocolVersion);

    // Timestamp (4B big-endian)
    buf.add(_uint32BE(timestampSec));

    // NodeId (32B)
    buf.add(nodeId);

    // Display name (1B len + UTF-8)
    final nameBytes = utf8.encode(displayName);
    buf.addByte(nameBytes.length.clamp(0, 255));
    buf.add(nameBytes.length > 255
        ? nameBytes.sublist(0, 255)
        : nameBytes);

    // Ed25519 public key (32B)
    buf.add(ed25519PublicKey);

    // ML-DSA public key (2B len + data)
    buf.add(_uint16BE(mlDsaPublicKey.length));
    buf.add(mlDsaPublicKey);

    // X25519 public key (32B)
    buf.add(x25519PublicKey);

    // ML-KEM public key (2B len + data)
    buf.add(_uint16BE(mlKemPublicKey.length));
    buf.add(mlKemPublicKey);

    // Profile picture (2B len + data, 0 if none)
    if (profilePicture != null && profilePicture!.isNotEmpty) {
      buf.add(_uint16BE(profilePicture!.length));
      buf.add(profilePicture!);
    } else {
      buf.add(_uint16BE(0));
    }

    // Description (2B len + UTF-8, 0 if none)
    if (description != null && description!.isNotEmpty) {
      final descBytes = utf8.encode(description!);
      buf.add(_uint16BE(descBytes.length));
      buf.add(descBytes);
    } else {
      buf.add(_uint16BE(0));
    }

    // Addresses (1B count + for each: 1B len + UTF-8)
    final addrCount = addresses.length.clamp(0, nfcMaxAddresses);
    buf.addByte(addrCount);
    for (var i = 0; i < addrCount; i++) {
      final addrBytes = utf8.encode(addresses[i]);
      final len = addrBytes.length.clamp(0, nfcMaxAddressBytes);
      buf.addByte(len);
      buf.add(addrBytes.length > nfcMaxAddressBytes
          ? addrBytes.sublist(0, nfcMaxAddressBytes)
          : addrBytes);
    }

    // Seed peers (1B count + for each: 32B nodeId + 1B addrCount + addrs)
    final peerCount = seedPeers.length.clamp(0, nfcMaxPeers);
    buf.addByte(peerCount);
    for (var i = 0; i < peerCount; i++) {
      final peer = seedPeers[i];
      buf.add(peer.nodeId);
      final pAddrCount = peer.addresses.length.clamp(0, 4);
      buf.addByte(pAddrCount);
      for (var j = 0; j < pAddrCount; j++) {
        final ab = utf8.encode(peer.addresses[j]);
        final len = ab.length.clamp(0, nfcMaxAddressBytes);
        buf.addByte(len);
        buf.add(ab.length > nfcMaxAddressBytes ? ab.sublist(0, nfcMaxAddressBytes) : ab);
      }
    }

    return buf.toBytes();
  }

  /// Deserializes a signed payload. Returns null if malformed.
  /// Does NOT verify the signature — call [verifySignature] separately.
  static (NfcContactPayload?, Uint8List? signature) deserialize(
      Uint8List data) {
    try {
      if (data.length < 4 + 1 + 4 + 32 + 1 + 32 + 2 + 32 + 2 + 2 + 2 + 1 + 1 + _ed25519SigBytes) {
        return (null, null); // Too short
      }

      var offset = 0;

      // Magic
      if (data[0] != nfcMagic[0] ||
          data[1] != nfcMagic[1] ||
          data[2] != nfcMagic[2] ||
          data[3] != nfcMagic[3]) {
        return (null, null);
      }
      offset += 4;

      // Version
      final version = data[offset++];
      if (version != nfcProtocolVersion) {
        return (null, null);
      }

      // Timestamp (4B big-endian)
      final timestampSec = _readUint32BE(data, offset);
      offset += 4;

      // NodeId (32B)
      final nodeId = Uint8List.fromList(data.sublist(offset, offset + 32));
      offset += 32;

      // Display name (1B len + UTF-8)
      final nameLen = data[offset++];
      if (offset + nameLen > data.length - _ed25519SigBytes) return (null, null);
      final displayName = utf8.decode(data.sublist(offset, offset + nameLen),
          allowMalformed: true);
      offset += nameLen;

      // Ed25519 public key (32B)
      if (offset + 32 > data.length - _ed25519SigBytes) return (null, null);
      final ed25519Pk = Uint8List.fromList(data.sublist(offset, offset + 32));
      offset += 32;

      // ML-DSA public key (2B len + data)
      if (offset + 2 > data.length - _ed25519SigBytes) return (null, null);
      final mlDsaLen = _readUint16BE(data, offset);
      offset += 2;
      if (offset + mlDsaLen > data.length - _ed25519SigBytes) return (null, null);
      final mlDsaPk = Uint8List.fromList(data.sublist(offset, offset + mlDsaLen));
      offset += mlDsaLen;

      // X25519 public key (32B)
      if (offset + 32 > data.length - _ed25519SigBytes) return (null, null);
      final x25519Pk = Uint8List.fromList(data.sublist(offset, offset + 32));
      offset += 32;

      // ML-KEM public key (2B len + data)
      if (offset + 2 > data.length - _ed25519SigBytes) return (null, null);
      final mlKemLen = _readUint16BE(data, offset);
      offset += 2;
      if (offset + mlKemLen > data.length - _ed25519SigBytes) return (null, null);
      final mlKemPk = Uint8List.fromList(data.sublist(offset, offset + mlKemLen));
      offset += mlKemLen;

      // Profile picture (2B len + data)
      if (offset + 2 > data.length - _ed25519SigBytes) return (null, null);
      final picLen = _readUint16BE(data, offset);
      offset += 2;
      Uint8List? profilePicture;
      if (picLen > 0) {
        if (offset + picLen > data.length - _ed25519SigBytes) return (null, null);
        profilePicture = Uint8List.fromList(data.sublist(offset, offset + picLen));
        offset += picLen;
      }

      // Description (2B len + UTF-8)
      if (offset + 2 > data.length - _ed25519SigBytes) return (null, null);
      final descLen = _readUint16BE(data, offset);
      offset += 2;
      String? description;
      if (descLen > 0) {
        if (offset + descLen > data.length - _ed25519SigBytes) return (null, null);
        description = utf8.decode(data.sublist(offset, offset + descLen),
            allowMalformed: true);
        offset += descLen;
      }

      // Addresses (1B count + entries)
      if (offset + 1 > data.length - _ed25519SigBytes) return (null, null);
      final addrCount = data[offset++];
      final addresses = <String>[];
      for (var i = 0; i < addrCount; i++) {
        if (offset + 1 > data.length - _ed25519SigBytes) return (null, null);
        final aLen = data[offset++];
        if (offset + aLen > data.length - _ed25519SigBytes) return (null, null);
        addresses.add(utf8.decode(data.sublist(offset, offset + aLen),
            allowMalformed: true));
        offset += aLen;
      }

      // Seed peers (1B count + entries)
      if (offset + 1 > data.length - _ed25519SigBytes) return (null, null);
      final peerCount = data[offset++];
      final seedPeers = <NfcPeerEntry>[];
      for (var i = 0; i < peerCount; i++) {
        if (offset + 32 + 1 > data.length - _ed25519SigBytes) return (null, null);
        final peerNodeId =
            Uint8List.fromList(data.sublist(offset, offset + 32));
        offset += 32;
        final pAddrCount = data[offset++];
        final pAddrs = <String>[];
        for (var j = 0; j < pAddrCount; j++) {
          if (offset + 1 > data.length - _ed25519SigBytes) return (null, null);
          final paLen = data[offset++];
          if (offset + paLen > data.length - _ed25519SigBytes) return (null, null);
          pAddrs.add(utf8.decode(data.sublist(offset, offset + paLen),
              allowMalformed: true));
          offset += paLen;
        }
        seedPeers.add(NfcPeerEntry(nodeId: peerNodeId, addresses: pAddrs));
      }

      // Signature (last 64 bytes)
      if (data.length - offset != _ed25519SigBytes) return (null, null);
      final signature = Uint8List.fromList(
          data.sublist(data.length - _ed25519SigBytes));

      final payload = NfcContactPayload(
        nodeId: nodeId,
        displayName: displayName,
        ed25519PublicKey: ed25519Pk,
        mlDsaPublicKey: mlDsaPk,
        x25519PublicKey: x25519Pk,
        mlKemPublicKey: mlKemPk,
        profilePicture: profilePicture,
        description: description,
        addresses: addresses,
        seedPeers: seedPeers,
        timestampSec: timestampSec,
      );

      return (payload, signature);
    } catch (_) {
      return (null, null);
    }
  }

  @override
  String toString() =>
      'NfcContactPayload("$displayName" ${bytesToHex(nodeId).substring(0, 8)}.. '
      '${addresses.length} addrs, ${seedPeers.length} peers)';
}

// ---------------------------------------------------------------------------
// NfcContactExchange — business logic for NFC contact pairing
// ---------------------------------------------------------------------------

/// Result of validating an NFC contact payload.
enum NfcValidationResult {
  /// Payload is valid and ready for user confirmation.
  ok,

  /// Binary format is malformed (wrong magic, truncated, etc.).
  malformed,

  /// Protocol version is unsupported.
  unsupportedVersion,

  /// Ed25519 signature does not verify.
  invalidSignature,

  /// Timestamp is too old (>5 minutes).
  expired,

  /// Payload is from the future (>30 seconds ahead).
  futureTimestamp,

  /// NodeId is all zeros or matches our own.
  invalidNodeId,

  /// Required keys are missing or have wrong size.
  invalidKeys,

  /// Display name is empty.
  emptyDisplayName,
}

class NfcContactExchange {
  /// Our own node ID (to reject self-contact).
  final Uint8List ownNodeId;

  /// Ed25519 signer: (message) -> signature.
  /// Injected so the class doesn't depend on SodiumFFI directly.
  final Uint8List Function(Uint8List message) sign;

  /// Ed25519 verifier: (message, signature, publicKey) -> bool.
  final bool Function(Uint8List message, Uint8List signature,
      Uint8List publicKey) verify;

  NfcContactExchange({
    required this.ownNodeId,
    required this.sign,
    required this.verify,
  });

  /// Creates a signed NFC payload for our identity.
  Uint8List createPayload({
    required String displayName,
    required Uint8List ed25519PublicKey,
    required Uint8List mlDsaPublicKey,
    required Uint8List x25519PublicKey,
    required Uint8List mlKemPublicKey,
    Uint8List? profilePicture,
    String? description,
    required List<String> addresses,
    required List<NfcPeerEntry> seedPeers,
  }) {
    final payload = NfcContactPayload(
      nodeId: ownNodeId,
      displayName: displayName,
      ed25519PublicKey: ed25519PublicKey,
      mlDsaPublicKey: mlDsaPublicKey,
      x25519PublicKey: x25519PublicKey,
      mlKemPublicKey: mlKemPublicKey,
      profilePicture: profilePicture,
      description: description,
      addresses: addresses,
      seedPeers: seedPeers,
      timestampSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final unsigned = payload.serializeUnsigned();
    final signature = sign(unsigned);

    // Append signature
    final signed = BytesBuilder(copy: false);
    signed.add(unsigned);
    signed.add(signature);
    return signed.toBytes();
  }

  /// Validates a received NFC payload.
  /// Returns [NfcValidationResult.ok] and the deserialized payload if valid.
  (NfcValidationResult, NfcContactPayload?) validatePayload(
    Uint8List signedData, {
    int? nowSec, // injectable for testing
  }) {
    // 1. Deserialize
    final (payload, signature) = NfcContactPayload.deserialize(signedData);
    if (payload == null || signature == null) {
      return (NfcValidationResult.malformed, null);
    }

    // 2. Check node ID is not zeros
    if (payload.nodeId.every((b) => b == 0)) {
      return (NfcValidationResult.invalidNodeId, null);
    }

    // 3. Check not our own node ID
    if (_bytesEqual(payload.nodeId, ownNodeId)) {
      return (NfcValidationResult.invalidNodeId, null);
    }

    // 4. Check display name not empty
    if (payload.displayName.trim().isEmpty) {
      return (NfcValidationResult.emptyDisplayName, null);
    }

    // 5. Check key sizes
    if (payload.ed25519PublicKey.length != _ed25519PkBytes) {
      return (NfcValidationResult.invalidKeys, null);
    }
    if (payload.mlDsaPublicKey.isEmpty) {
      return (NfcValidationResult.invalidKeys, null);
    }
    if (payload.x25519PublicKey.length != 32) {
      return (NfcValidationResult.invalidKeys, null);
    }
    if (payload.mlKemPublicKey.isEmpty) {
      return (NfcValidationResult.invalidKeys, null);
    }

    // 6. Check timestamp freshness
    final now = nowSec ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final age = now - payload.timestampSec;
    if (age > nfcMaxAgeSec) {
      return (NfcValidationResult.expired, null);
    }
    if (age < -30) {
      return (NfcValidationResult.futureTimestamp, null);
    }

    // 7. Verify Ed25519 signature
    final unsigned =
        signedData.sublist(0, signedData.length - _ed25519SigBytes);
    if (!verify(unsigned, signature, payload.ed25519PublicKey)) {
      return (NfcValidationResult.invalidSignature, null);
    }

    return (NfcValidationResult.ok, payload);
  }

  /// Creates a [Contact] from a validated NFC payload.
  /// The contact is created as **accepted** with **Verification Level 3
  /// (Verified)** — physical NFC tap proves co-presence.
  Contact contactFromPayload(NfcContactPayload payload) {
    return Contact(
      nodeId: Uint8List.fromList(payload.nodeId),
      displayName: payload.displayName,
      ed25519Pk: Uint8List.fromList(payload.ed25519PublicKey),
      mlDsaPk: Uint8List.fromList(payload.mlDsaPublicKey),
      x25519Pk: Uint8List.fromList(payload.x25519PublicKey),
      mlKemPk: Uint8List.fromList(payload.mlKemPublicKey),
      profilePicture: payload.profilePicture != null
          ? Uint8List.fromList(payload.profilePicture!)
          : null,
      description: payload.description,
      status: ContactStatus.accepted,
      verificationLevel: VerificationLevel.verified,
      verifiedKeyFingerprint:
          bytesToHex(payload.ed25519PublicKey).substring(0, 16),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Uint8List _uint16BE(int value) {
  return Uint8List.fromList([(value >> 8) & 0xFF, value & 0xFF]);
}

Uint8List _uint32BE(int value) {
  return Uint8List.fromList([
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);
}

int _readUint16BE(Uint8List data, int offset) {
  return (data[offset] << 8) | data[offset + 1];
}

int _readUint32BE(Uint8List data, int offset) {
  return (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
