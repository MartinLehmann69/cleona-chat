// V3.0 Frame Codec — build & verify NetworkPacketV3 / ApplicationFrameV3 /
// PerMessageKemV3 along the layered pipeline of Architecture v3.0 §2.4.
//
// This module is the canonical entry point for the cryptographic and
// serialization steps of the Outer (Routing) and Inner (Identity) layers.
// `transport.dart` handles the network_tag (Closed-Network HMAC) and wire
// emission; the codec handles everything else from sig+KEM+zstd inward.
//
// The codec is intentionally stateless and synchronous-where-possible — async
// is reserved for ML-DSA-65 sign/verify (CPU-heavy) and KEM ops (FFI). Callers
// own the keypairs and pass them in; the codec does not touch identity or
// device-key persistence.

import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:cleona/core/crypto/device_signature.dart' as device_sig;
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/proof_of_work.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/compression.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Verification outcome for an Inner ApplicationFrameV3 — either a parsed
/// frame or a typed failure reason for the caller's drop logic.
enum InnerVerifyError {
  kemVersionRejected,
  kemDecapFailed,
  zstdFailed,
  parseFailed,
  userSigInvalid,
  userPubkeysMissing,
}

class InnerVerifyResult {
  final proto.ApplicationFrameV3? frame;
  final InnerVerifyError? error;
  const InnerVerifyResult.ok(this.frame) : error = null;
  const InnerVerifyResult.fail(this.error) : frame = null;
  bool get success => frame != null;
}

/// Verification outcome for an Inner InfrastructureFrameV3 — either a parsed
/// frame or a typed failure reason for the caller's silent-drop logic.
///
/// Failure semantics mirror Architecture §2.4.1 receiver pipeline failure
/// table: every failure leads to silent drop (no DELIVERY_RECEIPT, no
/// reputation strike unless the caller explicitly classifies a
/// `selectorMismatch` as a cross-layer abuse attempt).
enum InfrastructureVerifyError {
  kemVersionRejected,
  kemDecapFailed,
  zstdFailed,
  parseFailed,
  selectorMismatch,
  recipientMismatch,
}

class InfrastructureVerifyResult {
  final proto.InfrastructureFrameV3? frame;
  final InfrastructureVerifyError? error;
  const InfrastructureVerifyResult.ok(this.frame) : error = null;
  const InfrastructureVerifyResult.fail(this.error) : frame = null;
  bool get success => frame != null;
}

class V3FrameCodec {
  // ───────────────────────── Sender (Inner) ─────────────────────────

  /// Build, User-Sign, zstd-compress and KEM-encrypt an ApplicationFrameV3
  /// for delivery to a single recipient user. Returns the serialized
  /// PerMessageKemV3 — that is the bytes the caller embeds as
  /// `NetworkPacketV3.payload` (with `payloadType = APPLICATION_FRAME`).
  ///
  /// Pipeline (Architecture §2.4 sender steps 2-7):
  ///   build inner → user-sign → serialize → zstd → KEM-encrypt → wrap KEM
  ///
  /// The caller is responsible for filling the application-content fields
  /// (recipientUserId, senderUserId, messageType, payload, optional
  /// metadata) on `inner` before calling. This function fills the sig fields
  /// in place and returns the wire bytes.
  /// Welle 5 Teil 4 (§8.1.1 First-CR-Bootstrap): User-sign an
  /// `ApplicationFrameV3` and return its serialized bytes WITHOUT inner KEM
  /// encryption. This is the inner-payload form that the §8.1.1 bootstrap
  /// wraps into `InfrastructureFrame.payload` — the recipient cannot decap
  /// a User-KEM-encrypted inner because the CR is what *establishes* the
  /// User-KEM-PK exchange in the first place.
  ///
  /// Mutates [inner]'s sig fields in place (same convention as
  /// [buildAndEncryptInner]).
  static Uint8List signApplicationFrameInner({
    required proto.ApplicationFrameV3 inner,
    required Uint8List senderUserEd25519Sk,
    required Uint8List senderUserMlDsaSk,
  }) {
    inner.clearUserEd25519Sig();
    inner.clearUserMlDsaSig();
    final unsigned = inner.writeToBuffer();
    final ed = SodiumFFI().signEd25519(unsigned, senderUserEd25519Sk);
    final mldsa = (OqsFFI()..init()).mlDsaSign(unsigned, senderUserMlDsaSk);
    inner.userEd25519Sig = ed;
    inner.userMlDsaSig = mldsa;
    return inner.writeToBuffer();
  }

  static Uint8List buildAndEncryptInner({
    required proto.ApplicationFrameV3 inner,
    required Uint8List senderUserEd25519Sk,
    required Uint8List senderUserMlDsaSk,
    required Uint8List recipientUserX25519Pk,
    required Uint8List recipientUserMlKemPk,
  }) {
    // 1+2. Sign inner; helper now lives in [signApplicationFrameInner] so
    //      §8.1.1 First-CR-Bootstrap can reuse the canonical sign step.
    final signedBytes = signApplicationFrameInner(
      inner: inner,
      senderUserEd25519Sk: senderUserEd25519Sk,
      senderUserMlDsaSk: senderUserMlDsaSk,
    );

    // 3. Compress + KEM-encrypt under recipient PKs.
    final compressed = ZstdCompression.instance.compress(signedBytes);
    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: compressed,
      recipientX25519Pk: recipientUserX25519Pk,
      recipientMlKemPk: recipientUserMlKemPk,
    );

    // 4. Pack the v2 KEM tuple into the v3 single-message shape.
    final kemV3 = proto.PerMessageKemV3()
      ..x25519Ciphertext = kemHeader.ephemeralX25519Pk
      ..mlKemCiphertext = kemHeader.mlKemCiphertext
      ..aeadCiphertext = ciphertext
      ..aeadNonce = kemHeader.aesNonce
      ..version = kemHeader.version;
    return kemV3.writeToBuffer();
  }

  /// §11.4.8: Build a de-attributed inner ApplicationFrame — empty
  /// senderUserId, no user signatures. Authenticity is carried by the
  /// ring signature in the payload. KEM-encrypted under recipient user PKs.
  static Uint8List buildDeAttributedInner({
    required proto.ApplicationFrameV3 inner,
    required Uint8List recipientUserX25519Pk,
    required Uint8List recipientUserMlKemPk,
  }) {
    inner.clearSenderUserId();
    inner.clearUserEd25519Sig();
    inner.clearUserMlDsaSig();
    final plainBytes = inner.writeToBuffer();
    final compressed = ZstdCompression.instance.compress(plainBytes);
    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: compressed,
      recipientX25519Pk: recipientUserX25519Pk,
      recipientMlKemPk: recipientUserMlKemPk,
    );
    final kemV3 = proto.PerMessageKemV3()
      ..x25519Ciphertext = kemHeader.ephemeralX25519Pk
      ..mlKemCiphertext = kemHeader.mlKemCiphertext
      ..aeadCiphertext = ciphertext
      ..aeadNonce = kemHeader.aesNonce
      ..version = kemHeader.version;
    return kemV3.writeToBuffer();
  }

  // ───────────────────────── Sender (Outer) ─────────────────────────

  /// Build a NetworkPacketV3 with all routing fields, payload, PoW and
  /// Device-Sig filled in. The `network_tag` field is left empty — the
  /// transport layer fills it via `Transport.serializeWithTag` immediately
  /// before wire emission.
  ///
  /// Pipeline (Architecture §2.4 sender steps 8-10):
  ///   build outer → device-sign → PoW
  ///
  /// `applicationFlavor` controls the sig-selectivity rule of §3.5:
  ///   - true  → application frame: hybrid Ed25519 + ML-DSA-65 device sig
  ///   - false → infrastructure frame (DHT, hole-punch, RTT, ACK, route
  ///             update): Ed25519 only, ML-DSA omitted (~3.3 KB saved)
  ///
  /// `skipPoW` lets callers bypass the proof-of-work step for LAN peers /
  /// infrastructure traffic (Architecture §2.4 step 10). Defaults to false.
  static proto.NetworkPacketV3 buildOuter({
    required Uint8List nextHopDeviceId,
    required Uint8List senderDeviceId,
    required device_sig.DeviceKeyPair deviceKeys,
    required Uint8List innerPayload,
    required proto.PayloadTypeV3 payloadType,
    required bool applicationFlavor,
    int ttl = 64,
    int hopCount = 0,
    int flags = 0,
    bool skipPoW = false,
  }) {
    final packet = proto.NetworkPacketV3()
      ..version = 1
      ..flags = flags
      ..nextHopDeviceId = nextHopDeviceId
      ..senderDeviceId = senderDeviceId
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..ttl = ttl
      ..hopCount = hopCount
      ..payloadType = payloadType
      ..payload = innerPayload;

    if (!skipPoW) {
      packet.pow = ProofOfWork.compute(innerPayload);
    }

    // Sign over the canonical "outer minus sig/tag/mutable-relay" bytes.
    // ttl + hopCount are excluded because relay nodes mutate them (§3.7.2).
    packet.clearDeviceEd25519Sig();
    packet.clearDeviceMlDsaSig();
    packet.clearNetworkTag();
    final saveTtl = packet.ttl;
    final saveHop = packet.hopCount;
    packet.clearTtl();
    packet.clearHopCount();
    final unsigned = packet.writeToBuffer();
    packet.ttl = saveTtl;
    packet.hopCount = saveHop;
    packet.deviceEd25519Sig = deviceKeys.signEd25519(unsigned);
    if (applicationFlavor) {
      packet.deviceMlDsaSig = deviceKeys.signMlDsa(unsigned);
    }
    return packet;
  }

  // ───────────────────────── Receiver (Outer) ───────────────────────

  /// Verify the Device-Sig on a parsed NetworkPacketV3. Strips sigs+tag,
  /// re-serializes to recover the canonical sign-input, then runs the
  /// hybrid verify (Ed25519 mandatory, ML-DSA conditional on packet flavor).
  ///
  /// Returns true iff the Ed25519 sig verifies AND, when `deviceMlDsaSig`
  /// is non-empty, the ML-DSA sig also verifies under the supplied pubkeys.
  /// Mutates `packet` (clears+restores sig+tag fields); the round-trip is
  /// invisible to callers because the packet was just parsed off the wire.
  static bool verifyOuterDeviceSig({
    required proto.NetworkPacketV3 packet,
    required Uint8List senderDeviceEd25519Pk,
    Uint8List? senderDeviceMlDsaPk,
  }) {
    final edSig = Uint8List.fromList(packet.deviceEd25519Sig);
    if (edSig.length != cryptoSignBytes) return false;
    final mlSig = Uint8List.fromList(packet.deviceMlDsaSig);
    final tag = Uint8List.fromList(packet.networkTag);

    packet.clearDeviceEd25519Sig();
    packet.clearDeviceMlDsaSig();
    packet.clearNetworkTag();
    // Exclude mutable relay fields (ttl, hopCount) — relay nodes mutate
    // them (§3.7.2), so they must not be part of the signed bytes.
    final saveTtl = packet.ttl;
    final saveHop = packet.hopCount;
    packet.clearTtl();
    packet.clearHopCount();
    final signedBytes = packet.writeToBuffer();
    // Restore for downstream readers.
    packet.ttl = saveTtl;
    packet.hopCount = saveHop;
    packet.deviceEd25519Sig = edSig;
    if (mlSig.isNotEmpty) packet.deviceMlDsaSig = mlSig;
    if (tag.isNotEmpty) packet.networkTag = tag;

    if (!device_sig.verifyEd25519(edSig, signedBytes, senderDeviceEd25519Pk)) {
      return false;
    }
    if (mlSig.isNotEmpty && senderDeviceMlDsaPk != null) {
      if (!device_sig.verifyMlDsa(mlSig, signedBytes, senderDeviceMlDsaPk)) {
        return false;
      }
    }
    return true;
  }

  // ───────────────────────── Receiver (Inner) ───────────────────────

  /// Decrypt a packet payload (serialized PerMessageKemV3) into an
  /// ApplicationFrameV3 and verify the User-Sig. Returns a typed result
  /// so the caller can apply the silent-drop policy of §2.4 [9-13]:
  /// no bounce, no error response — drop and move on (KEX-Gate trigger
  /// for `userSigInvalid` lives in cleona_service per §8.2).
  ///
  /// The user pubkey lookup is the caller's job (contact store / DHT
  /// auth-manifest) — the codec receives them ready to use.
  static InnerVerifyResult decryptAndVerifyInner({
    required Uint8List innerPayload,
    required Uint8List ourUserX25519Sk,
    required Uint8List ourUserMlKemSk,
    required Uint8List Function(Uint8List senderUserId)? lookupUserEd25519Pk,
    required Uint8List Function(Uint8List senderUserId)? lookupUserMlDsaPk,
    /// V3 §8.1.1 Trust-Bootstrap: invoked once when the lookup callbacks
    /// return empty bytes (i.e. sender not yet in the local contact store).
    /// Some message types carry the sender's User-Ed25519 / ML-DSA pubkeys
    /// inline in the body (MTV3_CONTACT_REQUEST, MTV3_CONTACT_REQUEST_RESPONSE).
    /// The callback inspects [frame] and returns the inline pubkey pair on
    /// hit, or null to keep the silent drop. The codec itself stays
    /// body-agnostic — message-type-specific extraction lives in cleona_service.
    ({Uint8List edPk, Uint8List mlDsaPk})? Function(proto.ApplicationFrameV3 frame)?
        trustBootstrapPubkeys,
    /// §7.1 LD-4: Linked-Device delegation fallback. If the User-Sig
    /// verification fails against the User-PK, this callback is consulted
    /// to check if the signer is a delegated device. Returns a list of
    /// (Ed25519-PK, ML-DSA-PK) pairs from the sender's AuthManifest
    /// delegation certs; the codec tries each until one verifies.
    List<({Uint8List edPk, Uint8List mlDsaPk})> Function(Uint8List senderUserId)?
        lookupDelegatedKeys,
  }) {
    // 1. Parse outer payload as PerMessageKemV3.
    final proto.PerMessageKemV3 kemV3;
    try {
      kemV3 = proto.PerMessageKemV3.fromBuffer(innerPayload);
    } catch (_) {
      return const InnerVerifyResult.fail(InnerVerifyError.parseFailed);
    }

    // 2. KEM-decap. Pack the V3 wire shape into the plain-Dart [KemHeader]
    //    consumed by [PerMessageKem.decrypt]; crypto is unchanged
    //    (Sec H-5 v2, Architecture §3 / KEM §3.4).
    final kemHeader = KemHeader(
      ephemeralX25519Pk: Uint8List.fromList(kemV3.x25519Ciphertext),
      mlKemCiphertext: Uint8List.fromList(kemV3.mlKemCiphertext),
      aesNonce: Uint8List.fromList(kemV3.aeadNonce),
      version: kemV3.version,
    );
    final Uint8List compressed;
    try {
      compressed = PerMessageKem.decrypt(
        kemHeader: kemHeader,
        ciphertext: Uint8List.fromList(kemV3.aeadCiphertext),
        ourX25519Sk: ourUserX25519Sk,
        ourMlKemSk: ourUserMlKemSk,
      );
    } on KemVersionRejectedException {
      return const InnerVerifyResult.fail(InnerVerifyError.kemVersionRejected);
    } catch (_) {
      return const InnerVerifyResult.fail(InnerVerifyError.kemDecapFailed);
    }

    // 3. zstd-decompress the AEAD plaintext.
    final Uint8List decompressed;
    try {
      decompressed = ZstdCompression.instance.decompress(compressed);
    } catch (_) {
      return const InnerVerifyResult.fail(InnerVerifyError.zstdFailed);
    }

    // 4. Parse decompressed bytes as ApplicationFrameV3.
    final proto.ApplicationFrameV3 frame;
    try {
      frame = proto.ApplicationFrameV3.fromBuffer(decompressed);
    } catch (_) {
      return const InnerVerifyResult.fail(InnerVerifyError.parseFailed);
    }

    // 5a. §11.4.8 de-attributed anonymous vote: empty senderUserId means
    //     the ring signature is the sole authenticator — skip user-sig verify.
    //     Strictly limited to the two anonymous poll types.
    final senderUserId = Uint8List.fromList(frame.senderUserId);
    if (senderUserId.isEmpty &&
        (frame.messageType == proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS ||
         frame.messageType == proto.MessageTypeV3.MTV3_POLL_REVOKE)) {
      return InnerVerifyResult.ok(frame);
    }

    // 5b. User-Sig-Verify over canonical "frame minus sig-fields" bytes.
    Uint8List? edPk = lookupUserEd25519Pk?.call(senderUserId);
    Uint8List? mlPk = lookupUserMlDsaPk?.call(senderUserId);
    // §8.1.1 Trust-Bootstrap: the lookup convention is to return Uint8List(0)
    // (not null) on miss, so check both. If the caller supplied a bootstrap
    // callback (CR / CRR carry their own pubkeys), consult it once.
    final missing = edPk == null || mlPk == null || edPk.isEmpty || mlPk.isEmpty;
    if (missing && trustBootstrapPubkeys != null) {
      final boot = trustBootstrapPubkeys(frame);
      if (boot != null) {
        edPk = boot.edPk;
        mlPk = boot.mlDsaPk;
      }
    }
    if (edPk == null || mlPk == null || edPk.isEmpty || mlPk.isEmpty) {
      return const InnerVerifyResult.fail(InnerVerifyError.userPubkeysMissing);
    }
    final edSig = Uint8List.fromList(frame.userEd25519Sig);
    final mlSig = Uint8List.fromList(frame.userMlDsaSig);
    frame.clearUserEd25519Sig();
    frame.clearUserMlDsaSig();
    final signedBytes = frame.writeToBuffer();
    frame.userEd25519Sig = edSig;
    frame.userMlDsaSig = mlSig;

    final edOk = device_sig.verifyEd25519(edSig, signedBytes, edPk);
    final mlOk = edOk && device_sig.verifyMlDsa(mlSig, signedBytes, mlPk);
    if (edOk && mlOk) return InnerVerifyResult.ok(frame);

    // §7.1 LD-4: User-Sig failed → try delegated keys from AuthManifest.
    if (lookupDelegatedKeys != null) {
      final delegated = lookupDelegatedKeys(senderUserId);
      for (final d in delegated) {
        if (device_sig.verifyEd25519(edSig, signedBytes, d.edPk) &&
            device_sig.verifyMlDsa(mlSig, signedBytes, d.mlDsaPk)) {
          return InnerVerifyResult.ok(frame);
        }
      }
    }
    return const InnerVerifyResult.fail(InnerVerifyError.userSigInvalid);
  }

  // ─────────────────── Sender (Infrastructure path, §2.4.1) ──────────────

  /// Build a fully-formed [proto.NetworkPacketV3] carrying an
  /// [proto.InfrastructureFrameV3] under the recipient's **Device-KEM-PK**
  /// (X25519 + ML-KEM-768 hybrid v2). This is the V3.0 Welle 5 entry point
  /// for device-targeted control-plane traffic (DHT, NAT, RUDP, Reachability,
  /// Identity-Resolution, S&F primitives — see §2.3.5 selector list).
  ///
  /// Pipeline (Architecture §2.4.1 sender steps 1'-7'; HMAC + UDP emission
  /// stay in transport.dart, PoW is skipped per [8']):
  ///
  ///   build inner → zstd → KEM-encrypt under Device-KEM-PK →
  ///   wrap as PerMessageKemV3 → build outer → device-sign (Ed25519-only)
  ///
  /// Returns the packet with `payload = serialized PerMessageKemV3`,
  /// `payloadType = PAYLOAD_INFRASTRUCTURE_FRAME`, `applicationFlavor=false`
  /// (Ed25519 only), and `pow` left empty (skipPoW).
  ///
  /// Caller MUST set `nextHopDeviceId` before send if a relay is needed —
  /// `sendToDevice()` in cleona_node patches that field per route attempt.
  /// [recipientDeviceId] populates `InfrastructureFrameV3.recipientDeviceId`
  /// and (by default) the outer `nextHopDeviceId`.
  ///
  /// The [messageType] MUST be in the §2.3.5 selector list — the receiver
  /// drops anything else as a cross-layer abuse attempt. Validation is
  /// asserted here to catch sender-side bugs early; in profile/release the
  /// assertion is removed by the dart-vm but the receiver still enforces.
  static proto.NetworkPacketV3 buildInfrastructureFrame({
    required Uint8List recipientDeviceId,
    required Uint8List senderDeviceId,
    required device_sig.DeviceKeyPair senderDeviceKeys,
    required proto.MessageTypeV3 messageType,
    required Uint8List payload,
    required Uint8List recipientDeviceX25519Pk,
    required Uint8List recipientDeviceMlKemPk,
    Uint8List? messageId,
    int ttl = 64,
    int hopCount = 0,
    int flags = 0,
  }) {
    assert(
        isInfrastructureMessageTypeV3(messageType) ||
            messageType == proto.MessageTypeV3.MTV3_CONTACT_REQUEST,
        'messageType $messageType is not in the §2.3.5 selector list and not '
        'the §8.1.1 First-CR-Bootstrap exception — use buildAndEncryptInner() '
        '+ buildOuter() for ApplicationFrame types');

    // [1'] Build InfrastructureFrameV3.
    final inner = proto.InfrastructureFrameV3()
      ..version = 1
      ..recipientDeviceId = recipientDeviceId
      ..senderDeviceId = senderDeviceId
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..messageId = messageId ?? _newMessageId()
      ..messageType = messageType
      ..payload = payload;

    // [2'] Serialize. No User-Sig fields — Outer Device-Sig provides
    //      routing-authenticity (§2.3.5).
    final innerBytes = inner.writeToBuffer();

    // [3'] zstd-compress.
    final compressed = ZstdCompression.instance.compress(innerBytes);

    // [4'] KEM-encrypt under recipient Device-KEM-PK (NOT User-KEM-PK).
    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: compressed,
      recipientX25519Pk: recipientDeviceX25519Pk,
      recipientMlKemPk: recipientDeviceMlKemPk,
    );

    // [5'] Wrap into the v3 single-message KEM shape.
    final kemV3 = proto.PerMessageKemV3()
      ..x25519Ciphertext = kemHeader.ephemeralX25519Pk
      ..mlKemCiphertext = kemHeader.mlKemCiphertext
      ..aeadCiphertext = ciphertext
      ..aeadNonce = kemHeader.aesNonce
      ..version = kemHeader.version;
    final outerPayload = kemV3.writeToBuffer();

    // [6'-7'] Build outer + Ed25519-only Device-Sig + PoW skip per [8'].
    return buildOuter(
      nextHopDeviceId: recipientDeviceId,
      senderDeviceId: senderDeviceId,
      deviceKeys: senderDeviceKeys,
      innerPayload: outerPayload,
      payloadType: proto.PayloadTypeV3.PAYLOAD_INFRASTRUCTURE_FRAME,
      applicationFlavor: false,
      ttl: ttl,
      hopCount: hopCount,
      flags: flags,
      skipPoW: true,
    );
  }

  /// Build a [proto.NetworkPacketV3] carrying an [proto.InfrastructureFrameV3]
  /// **plaintext** (no KEM, no zstd) — the BOOT path. This is the first-
  /// contact wire variant for the strict allow-list returned by
  /// [isBootstrapMessageTypeV3]. It exists because KEM-encrypting the
  /// outermost layer requires the recipient's Device-KEM-PK, which is
  /// precisely what the bootstrap RPCs (DHT_PING, IDENTITY_KEM_RETRIEVE,
  /// PEER_LIST_PUSH, …) need to discover. KEM-on-bootstrap creates an
  /// unsolvable chicken-and-egg loop on first-contact.
  ///
  /// Security properties on this path are carried by:
  ///   • Closed-Network HMAC on the Outer (transport.dart) — keeps
  ///     non-build traffic out.
  ///   • Outer Device-Sig (Ed25519-only, [3.5b]) — sender authenticity
  ///     and rotation-stable identity binding.
  ///   • Inner-record signatures on PUBLISH-RPCs (User-Sig in
  ///     IDENTITY_AUTH/LIVE/KEM publishes) — the inner record self-
  ///     authenticates regardless of outer transport.
  ///
  /// Pipeline (Architecture §2.4 sender, BOOT variant):
  ///
  ///   build inner → serialize *plaintext* → wrap as outer.payload →
  ///   build outer (PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME) →
  ///   device-sign Ed25519-only → PoW skip
  ///
  /// The receiver mirror is in [decryptAndVerifyBootstrapInfrastructure].
  static proto.NetworkPacketV3 buildBootstrapInfrastructureFrame({
    required Uint8List recipientDeviceId,
    required Uint8List senderDeviceId,
    required device_sig.DeviceKeyPair senderDeviceKeys,
    required proto.MessageTypeV3 messageType,
    required Uint8List payload,
    Uint8List? messageId,
    int ttl = 64,
    int hopCount = 0,
    int flags = 0,
  }) {
    assert(
        isBootstrapMessageTypeV3(messageType),
        'messageType $messageType is not in the BOOT-subset of §2.3.5 — '
        'use buildInfrastructureFrame() (KEM-encrypted) or '
        'buildAndEncryptInner() + buildOuter() (ApplicationFrame).');

    // Build InfrastructureFrameV3 (same inner schema as KEM path).
    final inner = proto.InfrastructureFrameV3()
      ..version = 1
      ..recipientDeviceId = recipientDeviceId
      ..senderDeviceId = senderDeviceId
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..messageId = messageId ?? _newMessageId()
      ..messageType = messageType
      ..payload = payload;

    // Serialize plaintext — outer.payload is the bare InfrastructureFrameV3
    // bytes, NOT a PerMessageKemV3 wrapper. No zstd, no KEM.
    final innerBytes = inner.writeToBuffer();

    // Build outer + Ed25519-only Device-Sig + PoW skip.
    return buildOuter(
      nextHopDeviceId: recipientDeviceId,
      senderDeviceId: senderDeviceId,
      deviceKeys: senderDeviceKeys,
      innerPayload: innerBytes,
      payloadType:
          proto.PayloadTypeV3.PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME,
      applicationFlavor: false,
      ttl: ttl,
      hopCount: hopCount,
      flags: flags,
      skipPoW: true,
    );
  }

  // ─────────────────── Receiver (Infrastructure path, §2.4.1) ────────────

  /// Decrypt a packet payload (serialized [proto.PerMessageKemV3]) into an
  /// [proto.InfrastructureFrameV3] using the local Device-KEM private keys
  /// (§3.5b), validate selector membership and recipient match, and return a
  /// typed result for silent-drop dispatch.
  ///
  /// Pipeline (Architecture §2.4.1 receiver steps 8'-14'):
  ///
  ///   parse PerMessageKemV3 → KEM-decap with Device-KEM-PrivKey →
  ///   AEAD-decrypt → zstd-decompress → parse InfrastructureFrameV3 →
  ///   validate messageType in §2.3.5 → validate recipientDeviceId
  ///
  /// Outer-HMAC + Outer-Device-Sig + Timestamp must be checked by the caller
  /// (typically transport.dart for HMAC, [verifyOuterDeviceSig] for the
  /// Device-Sig) BEFORE invoking this — the codec only owns the Inner.
  ///
  /// First-CR-Bootstrap (§8.1.1) is admitted: the codec accepts
  /// `MTV3_CONTACT_REQUEST` even though it is not on the §2.3.5 selector
  /// list, because the CR carries a fully User-signed ApplicationFrame as
  /// sub-payload that the caller will re-parse. This is the only place
  /// where the selector is intentionally relaxed.
  ///
  /// Recipient check: per §3.1 the DeviceID is daemon-global — equality
  /// against [myDeviceId] is sufficient. Multi-Identity is a User-Layer
  /// property and has no consequence here (all hosted identities share one
  /// deviceId). The Welle-5 `isLocalDeviceId` callback is no longer needed.
  static InfrastructureVerifyResult decryptAndVerifyInfrastructure({
    required Uint8List innerPayload,
    required Uint8List ourDeviceKemX25519Sk,
    required Uint8List ourDeviceKemMlKemSk,
    required Uint8List myDeviceId,
  }) {
    // [8'] Parse outer payload as PerMessageKemV3.
    final proto.PerMessageKemV3 kemV3;
    try {
      kemV3 = proto.PerMessageKemV3.fromBuffer(innerPayload);
    } catch (_) {
      return const InfrastructureVerifyResult.fail(
          InfrastructureVerifyError.parseFailed);
    }

    // [9'] KEM-decap with **Device**-KEM private keys. Reuse v2 hybrid via
    //      the plain-Dart [KemHeader] (crypto unchanged, see §3.4 / §3.5b).
    final kemHeader = KemHeader(
      ephemeralX25519Pk: Uint8List.fromList(kemV3.x25519Ciphertext),
      mlKemCiphertext: Uint8List.fromList(kemV3.mlKemCiphertext),
      aesNonce: Uint8List.fromList(kemV3.aeadNonce),
      version: kemV3.version,
    );
    final Uint8List compressed;
    try {
      compressed = PerMessageKem.decrypt(
        kemHeader: kemHeader,
        ciphertext: Uint8List.fromList(kemV3.aeadCiphertext),
        ourX25519Sk: ourDeviceKemX25519Sk,
        ourMlKemSk: ourDeviceKemMlKemSk,
      );
    } on KemVersionRejectedException {
      return const InfrastructureVerifyResult.fail(
          InfrastructureVerifyError.kemVersionRejected);
    } catch (_) {
      // [10'] AEAD-tag failures land here too — single drop bucket.
      return const InfrastructureVerifyResult.fail(
          InfrastructureVerifyError.kemDecapFailed);
    }

    // [11'] zstd-decompress.
    final Uint8List decompressed;
    try {
      decompressed = ZstdCompression.instance.decompress(compressed);
    } catch (_) {
      return const InfrastructureVerifyResult.fail(
          InfrastructureVerifyError.zstdFailed);
    }

    // [12'] Parse InfrastructureFrameV3.
    final proto.InfrastructureFrameV3 frame;
    try {
      frame = proto.InfrastructureFrameV3.fromBuffer(decompressed);
    } catch (_) {
      return const InfrastructureVerifyResult.fail(
          InfrastructureVerifyError.parseFailed);
    }

    // [13'] Validate messageType in §2.3.5 selector list. CR-Bootstrap is
    //       the explicitly relaxed exception (§8.1.1).
    if (!isInfrastructureMessageTypeV3(frame.messageType) &&
        frame.messageType != proto.MessageTypeV3.MTV3_CONTACT_REQUEST) {
      return const InfrastructureVerifyResult.fail(
          InfrastructureVerifyError.selectorMismatch);
    }

    // [14'] Validate recipientDeviceId == self.deviceId (§3.1: daemon-global).
    final rcv = Uint8List.fromList(frame.recipientDeviceId);
    if (rcv.length != myDeviceId.length) {
      return const InfrastructureVerifyResult.fail(
          InfrastructureVerifyError.recipientMismatch);
    }
    for (var i = 0; i < rcv.length; i++) {
      if (rcv[i] != myDeviceId[i]) {
        return const InfrastructureVerifyResult.fail(
            InfrastructureVerifyError.recipientMismatch);
      }
    }
    return InfrastructureVerifyResult.ok(frame);
  }

  /// Receiver mirror of [buildBootstrapInfrastructureFrame]: parses a
  /// plaintext [proto.InfrastructureFrameV3] directly out of
  /// `NetworkPacketV3.payload` (no KEM-decap, no zstd-decompress) and
  /// validates the strict BOOT-subset selector + recipient match.
  ///
  /// The caller (transport / cleona_node receive pipeline) is responsible
  /// for Outer-HMAC + Outer-Device-Sig + Timestamp validation BEFORE
  /// invoking this — same contract as [decryptAndVerifyInfrastructure].
  ///
  /// Selector here is **strict BOOT-subset only**: anything in the wider
  /// §2.3.5 selector list but NOT on the BOOT allow-list is dropped as a
  /// cross-layer abuse attempt (a malicious sender trying to skip the
  /// KEM wrapper for non-bootstrap traffic).
  static InfrastructureVerifyResult decryptAndVerifyBootstrapInfrastructure({
    required Uint8List innerPayload,
    required Uint8List myDeviceId,
  }) {
    // Parse outer payload directly as InfrastructureFrameV3 (no KEM, no zstd).
    final proto.InfrastructureFrameV3 frame;
    try {
      frame = proto.InfrastructureFrameV3.fromBuffer(innerPayload);
    } catch (_) {
      return const InfrastructureVerifyResult.fail(
          InfrastructureVerifyError.parseFailed);
    }

    // Validate messageType in BOOT-subset (strict). The wider §2.3.5
    // selector is intentionally NOT used here — a sender that wraps a
    // non-BOOT type in BOOTSTRAP_INFRASTRUCTURE_FRAME is attempting
    // cross-layer abuse and must be dropped.
    if (!isBootstrapMessageTypeV3(frame.messageType)) {
      return const InfrastructureVerifyResult.fail(
          InfrastructureVerifyError.selectorMismatch);
    }

    // Validate recipientDeviceId == self.deviceId (§3.1: daemon-global).
    final rcv = Uint8List.fromList(frame.recipientDeviceId);
    if (rcv.length != myDeviceId.length) {
      return const InfrastructureVerifyResult.fail(
          InfrastructureVerifyError.recipientMismatch);
    }
    for (var i = 0; i < rcv.length; i++) {
      if (rcv[i] != myDeviceId[i]) {
        return const InfrastructureVerifyResult.fail(
            InfrastructureVerifyError.recipientMismatch);
      }
    }
    return InfrastructureVerifyResult.ok(frame);
  }

  /// Generate a 16-byte UUID v4-shaped messageId for InfrastructureFrameV3.
  /// We do not pull `package:uuid` here — keeping the codec dep-light. The
  /// random bytes come from libsodium's CSPRNG via [SodiumFFI].
  static Uint8List _newMessageId() {
    final bytes = SodiumFFI().randomBytes(16);
    // RFC 4122 v4: set version (4) and variant bits (10).
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return bytes;
  }
}

// ───────────────────── §2.3.5 Infrastructure Selector ─────────────────────

/// Canonical selector for V3.0 §2.3.5: returns true iff [type] is permitted
/// inside an [proto.InfrastructureFrameV3]. The codec owns this predicate
/// because it is the lowest-level enforcement point — `CleonaNode` and
/// `CleonaService` delegate here so the list lives in exactly one place
/// (commit 940dfa1 mirror note in proto/cleona.proto). See Architecture
/// §2.3.5 normative selector table.
///
/// First-CR-Bootstrap (§8.1.1) is **not** included here: it is an explicit
/// exception handled at the verify call-site, not a selector entry.
///
/// Top-level function name kept identical to
/// `CleonaNode.isInfrastructureMessageTypeV3` so a search across the codebase
/// surfaces both call sites; resolve via `package:cleona/core/network/`
/// import at the call site to disambiguate from the static method.
bool isInfrastructureMessageTypeV3(proto.MessageTypeV3 type) {
  switch (type) {
    // Peer-list / DHT chatter
    case proto.MessageTypeV3.MTV3_PEER_LIST_PUSH:
    case proto.MessageTypeV3.MTV3_PEER_LIST_SUMMARY:
    case proto.MessageTypeV3.MTV3_PEER_LIST_WANT:
    case proto.MessageTypeV3.MTV3_PEER_KEY_REQUEST:
    case proto.MessageTypeV3.MTV3_PEER_KEY_RESPONSE:
    case proto.MessageTypeV3.MTV3_DHT_PING:
    case proto.MessageTypeV3.MTV3_DHT_PONG:
    case proto.MessageTypeV3.MTV3_DHT_FIND_NODE:
    case proto.MessageTypeV3.MTV3_DHT_FIND_NODE_RESPONSE:
    case proto.MessageTypeV3.MTV3_DHT_STORE:
    case proto.MessageTypeV3.MTV3_DHT_STORE_RESPONSE:
    case proto.MessageTypeV3.MTV3_DHT_FIND_VALUE:
    case proto.MessageTypeV3.MTV3_DHT_FIND_VALUE_RESPONSE:
    // Reed-Solomon fragment storage / S&F mailbox primitives
    case proto.MessageTypeV3.MTV3_FRAGMENT_STORE:
    case proto.MessageTypeV3.MTV3_FRAGMENT_STORE_ACK:
    case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE:
    case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE_RESPONSE:
    case proto.MessageTypeV3.MTV3_FRAGMENT_DELETE:
    case proto.MessageTypeV3.MTV3_PEER_STORE:
    case proto.MessageTypeV3.MTV3_PEER_STORE_ACK:
    case proto.MessageTypeV3.MTV3_PEER_RETRIEVE:
    case proto.MessageTypeV3.MTV3_PEER_RETRIEVE_RESPONSE:
    // Routing / RUDP / NAT control-plane
    case proto.MessageTypeV3.MTV3_ROUTE_UPDATE:
    case proto.MessageTypeV3.MTV3_REACHABILITY_QUERY:
    case proto.MessageTypeV3.MTV3_REACHABILITY_RESPONSE:
    case proto.MessageTypeV3.MTV3_RELAY_FORWARD:
    case proto.MessageTypeV3.MTV3_RELAY_ACK:
    case proto.MessageTypeV3.MTV3_HOLE_PUNCH_REQUEST:
    case proto.MessageTypeV3.MTV3_HOLE_PUNCH_NOTIFY:
    case proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING:
    case proto.MessageTypeV3.MTV3_HOLE_PUNCH_PONG:
    // 2D-DHT identity resolution (§4.3) — also infrastructure
    case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_PUBLISH:
    case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RETRIEVE:
    case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RESPONSE:
    case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_PUBLISH:
    case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RETRIEVE:
    case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RESPONSE:
    // Welle 5 (§4.3 + §3.5b): Device-KEM-Record class — own DHT key-space
    // ("kem"||userId||deviceId), separate TTL from Liveness, but same
    // §2.3.5 infrastructure selector membership.
    case proto.MessageTypeV3.MTV3_IDENTITY_KEM_PUBLISH:
    case proto.MessageTypeV3.MTV3_IDENTITY_KEM_RETRIEVE:
    case proto.MessageTypeV3.MTV3_IDENTITY_KEM_RESPONSE:
    // Welle 6 (§2.3.5 / §6.3 / §7.4): Identity-Layer Infrastructure —
    // RESTORE_BROADCAST and Emergency-variant KEY_ROTATION_BROADCAST migrate
    // off the ApplicationFrame path because the sender's User-Sig-Keys are
    // mid-rotation; the InfrastructureFrame path uses Device-KEM-PK and a
    // rotation-stable Device-Sig (§3.5b). Periodic KEM-only KEY_ROTATION
    // stays on ApplicationFrame.
    //
    // Predicate is MessageType-only — sender chooses InfrastructureFrame for
    // KEY_ROTATION_BROADCAST iff body carries dual-sig. Receiver enforces
    // the discriminator by checking the inner KeyRotationBroadcast body for
    // both `oldSignatureEd25519` and `newSignatureEd25519`.
    case proto.MessageTypeV3.MTV3_RESTORE_BROADCAST:
    case proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST:
    // Guardian / Shamir Social Recovery (§6.2) — same trust-bootstrap
    // rationale as RESTORE_BROADCAST: during restore the owner's
    // user-sig keys are mid-rotation, and during setup the contact
    // graph is fresh enough that the sender's User-Sig path is not
    // yet authoritative for the recipient. Carry on InfrastructureFrame
    // so the §3.5b rotation-stable Device-Sig is the outer authority.
    case proto.MessageTypeV3.MTV3_GUARDIAN_SHARE_STORE:
    case proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_REQUEST:
    case proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_RESPONSE:
    // Wave 2B.3 (§10.2): channel-index gossip rides InfraFrame because
    // recipients are arbitrary routing-table peers — Device-KEM-Decap +
    // Outer-Device-Sig (§3.5) is the wire authority; receivers treat the
    // payload as untrusted gossip regardless.
    case proto.MessageTypeV3.MTV3_CHANNEL_INDEX_EXCHANGE:
    // Deferred Key Exchange (rev3 §8.1.1) — BOOT path: sender does not yet
    // have recipient's Device-KEM-PK (that's what we're requesting).
    case proto.MessageTypeV3.MTV3_DEVICE_KEM_REQUEST:
    case proto.MessageTypeV3.MTV3_DEVICE_KEM_OFFER:
    // First-CR-Mailbox (rev3 §5.5b) — KEM path (sender has SeedPeer's
    // Device-KEM-PK from routing table).
    case proto.MessageTypeV3.MTV3_FIRST_CR_STORE:
    case proto.MessageTypeV3.MTV3_FIRST_CR_STORE_ACK:
    case proto.MessageTypeV3.MTV3_FIRST_CR_DELIVER:
    // §11.4.8: Anonymous Vote Re-Broadcaster — voter→R bundle + R→voter ACK
    case proto.MessageTypeV3.MTV3_POLL_ANON_SUBMIT:
    case proto.MessageTypeV3.MTV3_POLL_ANON_SUBMIT_ACK:
      return true;
    default:
      return false;
  }
}

/// BOOT-subset of [isInfrastructureMessageTypeV3]: the strict allow-list of
/// MessageTypes permitted on the [proto.PayloadTypeV3.PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME]
/// wire path. The BOOT path serializes [proto.InfrastructureFrameV3]
/// **plaintext** — no KEM, no zstd — so it can carry first-contact traffic
/// before the recipient's Device-KEM-PK is known. Closed-Network HMAC
/// (transport layer), Outer Device-Sig (Ed25519-only) and inner-record
/// signatures (for the PUBLISH-RPCs) carry the security properties.
///
/// This list is **strict**. Anything outside it MUST take the
/// KEM-encrypted [proto.PayloadTypeV3.PAYLOAD_INFRASTRUCTURE_FRAME] path.
/// Receivers drop on selector mismatch (cross-layer abuse attempt).
///
/// Membership rationale (each entry MUST also be in
/// [isInfrastructureMessageTypeV3] — the BOOT-subset is a strict subset of
/// the §2.3.5 selector list):
///
///   • DHT_PING / DHT_PONG, DHT_FIND_NODE / RESPONSE — Kademlia bootstrap
///     against a freshly-discovered LAN/seed peer; PK not yet learned.
///   • IDENTITY_AUTH_PUBLISH/RETRIEVE/RESPONSE — Auth-Manifest in 2D-DHT,
///     inner record carries User-Sig so plaintext outer is acceptable.
///   • IDENTITY_LIVE_PUBLISH/RETRIEVE/RESPONSE — Liveness record, same
///     reasoning (Auth-Manifest already published, signature on inner).
///   • IDENTITY_KEM_PUBLISH/RETRIEVE/RESPONSE — Device-KEM-Record (the
///     proto-canonical naming for "DEVICE_KEM_RECORD" — §3.5b/§4.3 Welle 5).
///     Without this on BOOT, learning the PK to KEM-encrypt against would
///     require already having the PK (chicken-and-egg).
///   • PEER_LIST_PUSH / SUMMARY / WANT — Routing-table gossip; first-contact
///     peer-list exchange happens before per-peer Device-KEM-PK lookup.
///   • ROUTE_UPDATE — Distance-Vector advertisement. New neighbours need
///     to receive the first DV broadcast even when their PK is unknown.
///   • REACHABILITY_QUERY / RESPONSE — Probes a fresh peer; needs to work
///     before any KEM-PK has been resolved.
///   • HOLE_PUNCH_REQUEST / NOTIFY / PING / PONG — NAT traversal probes
///     between peers that have just learned each other's address; PK is
///     resolved out-of-band via the rendezvous flow.
bool isBootstrapMessageTypeV3(proto.MessageTypeV3 type) {
  switch (type) {
    // DHT bootstrap RPCs
    case proto.MessageTypeV3.MTV3_DHT_PING:
    case proto.MessageTypeV3.MTV3_DHT_PONG:
    case proto.MessageTypeV3.MTV3_DHT_FIND_NODE:
    case proto.MessageTypeV3.MTV3_DHT_FIND_NODE_RESPONSE:
    // 2D-DHT Identity Resolution — inner record self-authenticates via
    // User-Sig, so no KEM wrapper required for the outer transport.
    case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_PUBLISH:
    case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RETRIEVE:
    case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RESPONSE:
    case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_PUBLISH:
    case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RETRIEVE:
    case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RESPONSE:
    // Device-KEM-Record (proto canonical name `IDENTITY_KEM_*`, semantically
    // the "DEVICE_KEM_RECORD" class per §3.5b/§4.3) — must be on BOOT path
    // to break the chicken-and-egg: KEM-encrypting the publish would
    // require the recipient's KEM-PK already.
    case proto.MessageTypeV3.MTV3_IDENTITY_KEM_PUBLISH:
    case proto.MessageTypeV3.MTV3_IDENTITY_KEM_RETRIEVE:
    case proto.MessageTypeV3.MTV3_IDENTITY_KEM_RESPONSE:
    // Routing-table gossip
    case proto.MessageTypeV3.MTV3_PEER_LIST_PUSH:
    case proto.MessageTypeV3.MTV3_PEER_LIST_SUMMARY:
    case proto.MessageTypeV3.MTV3_PEER_LIST_WANT:
    case proto.MessageTypeV3.MTV3_PEER_KEY_REQUEST:
    case proto.MessageTypeV3.MTV3_PEER_KEY_RESPONSE:
    // Distance-Vector advertisements
    case proto.MessageTypeV3.MTV3_ROUTE_UPDATE:
    // Reachability probes
    case proto.MessageTypeV3.MTV3_REACHABILITY_QUERY:
    case proto.MessageTypeV3.MTV3_REACHABILITY_RESPONSE:
    // NAT hole-punch probes — peers exchange addresses via rendezvous
    // before they have learned each other's KEM-PK.
    case proto.MessageTypeV3.MTV3_HOLE_PUNCH_REQUEST:
    case proto.MessageTypeV3.MTV3_HOLE_PUNCH_NOTIFY:
    case proto.MessageTypeV3.MTV3_HOLE_PUNCH_PING:
    case proto.MessageTypeV3.MTV3_HOLE_PUNCH_PONG:
    // Reed-Solomon fragment storage + S&F peer storage — payloads are
    // already User-KEM-encrypted; the outer Device-KEM wrapper only hides
    // the storage metadata ("store fragment X for recipient Y"). In the
    // Closed-Network model (HMAC + Device-Sig on every packet) this
    // metadata leakage is acceptable. Putting these on the BOOT path
    // eliminates the Device-KEM cold-start race: Layer 3 offline delivery
    // works immediately after neighbor discovery, before KEM_PUBLISH
    // records have propagated.
    case proto.MessageTypeV3.MTV3_FRAGMENT_STORE:
    case proto.MessageTypeV3.MTV3_FRAGMENT_STORE_ACK:
    case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE:
    case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE_RESPONSE:
    case proto.MessageTypeV3.MTV3_FRAGMENT_DELETE:
    case proto.MessageTypeV3.MTV3_PEER_STORE:
    case proto.MessageTypeV3.MTV3_PEER_STORE_ACK:
    case proto.MessageTypeV3.MTV3_PEER_RETRIEVE:
    case proto.MessageTypeV3.MTV3_PEER_RETRIEVE_RESPONSE:
    // Deferred Key Exchange (rev3 §8.1.1) — must be BOOT: sender needs
    // recipient's Device-KEM-PK and cannot KEM-encrypt without it.
    case proto.MessageTypeV3.MTV3_DEVICE_KEM_REQUEST:
    case proto.MessageTypeV3.MTV3_DEVICE_KEM_OFFER:
      // Sanity: every BOOT entry MUST also be in the §2.3.5 selector. If
      // these ever drift, the receiver-side `isInfrastructureMessageTypeV3`
      // gate in [decryptAndVerifyInfrastructure] would still admit BOOT
      // frames (different code path), but symbolic consistency matters
      // for callers like `_buildInfraPacket` that delegate selector
      // validation. Keep both lists in sync.
      assert(isInfrastructureMessageTypeV3(type),
          'BOOT-subset entry $type missing from §2.3.5 selector — '
          'isInfrastructureMessageTypeV3 must be a superset');
      return true;
    default:
      return false;
  }
}

