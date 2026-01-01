import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/network/v3_frame_codec.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Represents an active or pending call with crypto state.
class CallSession {
  final Uint8List callId;
  final String peerNodeIdHex;
  final CallDirection direction;
  final bool isVideo;
  CallState state;
  DateTime startedAt;

  // Ephemeral key exchange for audio encryption
  Uint8List? ephX25519Pk;
  Uint8List? ephX25519Sk;
  Uint8List? sharedSecret; // 32 bytes AES-256 key for audio
  Uint8List? kemSharedSecret; // ML-KEM shared secret from caller's encapsulation

  // Audio frame counters for E2E verification
  int framesSent = 0;
  int framesReceived = 0;

  // Video frame counters
  int videoFramesSent = 0;
  int videoFramesReceived = 0;

  // ── Per-Call Route Cache (Architecture §10.4.1) ──────────────────
  // Caches the resolved peer for the duration of a call so audio frames
  // (~50/sec for 20ms PCM) don't repeat the routing-table lookup on every
  // send. Refreshed when DV-Routing's `onRouteDown` fires for this peer
  // — the next frame then falls through to the normal resolve path.
  PeerInfo? cachedRoute;
  DateTime? cachedRouteAt;

  /// Invalidate cached route — next frame send will resolve fresh.
  void invalidateCachedRoute() {
    cachedRoute = null;
    cachedRouteAt = null;
  }

  CallSession({
    required this.callId,
    required this.peerNodeIdHex,
    required this.direction,
    this.isVideo = false,
    this.state = CallState.idle,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  String get callIdHex => bytesToHex(callId);

  CallInfo toCallInfo() => CallInfo(
        callId: callIdHex,
        peerNodeIdHex: peerNodeIdHex,
        direction: direction,
        isVideo: isVideo,
        state: state,
        startedAt: startedAt,
        framesSent: framesSent,
        framesReceived: framesReceived,
        videoFramesSent: videoFramesSent,
        videoFramesReceived: videoFramesReceived,
      );
}

/// Manages call signaling over the Cleona P2P network.
///
/// V3 Send Model (Architecture §10.1 + §10.3):
///   * Setup frames (CALL_INVITE/ANSWER/REJECT/HANGUP) → `sendViaUser`
///     callback (resolves to `service.sendToUser` in CleonaService): full
///     hybrid Ed25519+ML-DSA Inner-User-Sig, Per-Message KEM, fan-out to
///     all of the peer user's authorized devices for the multi-device
///     ringing UX (§26).
///   * Live-media frames (CALL_AUDIO/VIDEO) and ephemeral outer-replies
///     (busy auto-reject) → built inline via `V3FrameCodec.buildAndEncryptInner`
///     + `V3FrameCodec.buildOuter(applicationFlavor=false, skipPoW=true)`
///     and dispatched directly via `node.sendToDevice(packet, deviceId)`.
///     The outer carries Ed25519-only device-sig per §10.3 — post-quantum
///     authenticity is anchored at call setup, AES-GCM under the call_key
///     authenticates each subsequent frame.
class CallManager {
  final IdentityContext identity;
  final CleonaNode node;
  final Map<String, ContactInfo> contacts;
  final CLogger _log;

  CallSession? _currentCall;
  Timer? _ringingTimeout;

  /// Ringing timeout in seconds (auto-hangup if not answered).
  static const int ringingTimeoutSec = 60;

  // Callbacks for UI
  void Function(CallSession call)? onIncomingCall;
  void Function(CallSession call)? onCallAccepted;
  void Function(CallSession call, String reason)? onCallRejected;
  void Function(CallSession call)? onCallEnded;

  /// V3 setup-path send callback — wired by `CleonaService` to its
  /// `sendToUser` orchestrator (Architecture §2.6.2 / §10.1). Used for
  /// CALL_INVITE/ANSWER/REJECT/HANGUP. Returns true if at least one
  /// device-leg of the recipient fan-out dispatched.
  Future<bool> Function(
    Uint8List recipientUserId,
    proto.MessageTypeV3 type,
    Uint8List payload,
  )? sendViaUser;

  // Temporarily holds caller's ephemeral PK until we accept
  Uint8List? _callerEphPk;
  Uint8List? _callerKemCt; // KEM ciphertext from caller

  CallManager({required this.identity, required this.node, required this.contacts, required String profileDir})
      : _log = CLogger.get('calls', profileDir: profileDir);

  CallSession? get currentCall => _currentCall;
  bool get inCall => _currentCall?.state == CallState.inCall;
  bool get isRinging => _currentCall?.state == CallState.ringing;

  /// Initiate a call to a contact.
  Future<CallSession?> startCall(String peerNodeIdHex, {bool video = false}) async {
    if (_currentCall != null) {
      _log.warn('Already in a call');
      return null;
    }

    final sodium = SodiumFFI();
    final callId = sodium.randomBytes(16);

    // Generate ephemeral X25519 keypair for call encryption
    final ephKp = sodium.generateX25519KeyPair();

    final session = CallSession(
      callId: callId,
      peerNodeIdHex: peerNodeIdHex,
      direction: CallDirection.outgoing,
      isVideo: video,
      state: CallState.ringing,
    );
    session.ephX25519Pk = ephKp.publicKey;
    session.ephX25519Sk = ephKp.secretKey;

    // ML-KEM-768 encapsulation for post-quantum security
    Uint8List? kemCt;
    final contact = contacts[peerNodeIdHex];
    if (contact?.mlKemPk != null) {
      try {
        final oqs = OqsFFI();
        final kem = oqs.mlKemEncapsulate(contact!.mlKemPk!);
        kemCt = kem.ciphertext;
        session.kemSharedSecret = kem.sharedSecret;
      } catch (e) {
        _log.warn('KEM encapsulation failed: $e');
      }
    }

    _currentCall = session;

    // Send CALL_INVITE with ephemeral public key.
    // TODO(v3-sub-message): use a dedicated `CallInviteV3` proto once that
    // sub-message lands. The V3 wire-format is sub-message-agnostic — the
    // bytes payload is opaque to the codec.
    final invite = proto.CallInvite()
      ..callId = callId
      ..callerEphX25519Pk = ephKp.publicKey
      ..isVideo = video;
    if (kemCt != null) {
      invite.callerKemCiphertext = kemCt;
    }

    final sent = await sendViaUser?.call(
          hexToBytes(peerNodeIdHex),
          proto.MessageTypeV3.MTV3_CALL_INVITE,
          invite.writeToBuffer(),
        ) ??
        false;
    _log.info('Call invite sent to ${peerNodeIdHex.substring(0, 8)}: ${sent ? "OK" : "FAILED"}');

    // 60s Ringing Timeout — auto-hangup if not answered
    _startRingingTimeout();

    return session;
  }

  /// Accept an incoming call.
  Future<void> acceptCall() async {
    final call = _currentCall;
    if (call == null || call.state != CallState.ringing || call.direction != CallDirection.incoming) {
      return;
    }

    final sodium = SodiumFFI();

    // Generate our ephemeral X25519 keypair
    final ephKp = sodium.generateX25519KeyPair();
    call.ephX25519Pk = ephKp.publicKey;
    call.ephX25519Sk = ephKp.secretKey;

    // ML-KEM-768 encapsulation (callee → caller's ML-KEM PK)
    Uint8List? kemCt;
    Uint8List? kemSecret;
    final contact = contacts[call.peerNodeIdHex];
    if (contact?.mlKemPk != null) {
      try {
        final oqs = OqsFFI();
        final kem = oqs.mlKemEncapsulate(contact!.mlKemPk!);
        kemCt = kem.ciphertext;
        kemSecret = kem.sharedSecret;
      } catch (e) {
        _log.warn('KEM encapsulation failed: $e');
      }
    }

    // Decapsulate caller's KEM ciphertext
    Uint8List? callerKemSecret;
    if (_callerKemCt != null && _callerKemCt!.isNotEmpty) {
      try {
        final oqs = OqsFFI();
        callerKemSecret = oqs.mlKemDecapsulate(_callerKemCt!, identity.mlKemSecretKey);
      } catch (e) {
        _log.warn('KEM decapsulation failed: $e');
      }
    }

    // Derive shared secret: HKDF-SHA256(DH + KEM) — per CALLS.md spec
    if (_callerEphPk != null) {
      final dhSecret = sodium.x25519ScalarMult(ephKp.secretKey, _callerEphPk!);
      // IKM: DH secret + KEM secrets (hybrid post-quantum)
      final ikm = <int>[
        ...dhSecret,
        if (callerKemSecret != null) ...callerKemSecret,
        if (kemSecret != null) ...kemSecret,
      ];
      call.sharedSecret = sodium.hkdfSha256(
        Uint8List.fromList(ikm),
        info: Uint8List.fromList('cleona-call-v1'.codeUnits),
        length: 32,
      );
      _callerEphPk = null;
      _callerKemCt = null;
    }

    call.state = CallState.inCall;
    _cancelRingingTimeout();

    // TODO(v3-sub-message): swap to `CallAnswerV3` once defined.
    final answer = proto.CallAnswer()
      ..callId = call.callId
      ..calleeEphX25519Pk = ephKp.publicKey;
    if (kemCt != null) {
      answer.calleeKemCiphertext = kemCt;
    }

    await sendViaUser?.call(
      hexToBytes(call.peerNodeIdHex),
      proto.MessageTypeV3.MTV3_CALL_ANSWER,
      answer.writeToBuffer(),
    );
    onCallAccepted?.call(call);
    _log.info('Call accepted with ${call.peerNodeIdHex.substring(0, 8)}');
  }

  /// Reject an incoming call.
  ///
  /// Local-first teardown (see [hangup] for rationale). A reject that
  /// throws on the wire must NOT leave the ringing call object active.
  Future<void> rejectCall({String reason = 'busy'}) async {
    final call = _currentCall;
    if (call == null || call.state != CallState.ringing) return;

    _cancelRingingTimeout();
    call.state = CallState.ended;
    _currentCall = null;
    _log.info('Call rejected (local teardown done): $reason');

    // Best-effort wire signal — failure does not undo the teardown.
    try {
      // TODO(v3-sub-message): swap to `CallRejectV3` once defined.
      final reject = proto.CallReject()
        ..callId = call.callId
        ..reason = reason;
      await sendViaUser?.call(
        hexToBytes(call.peerNodeIdHex),
        proto.MessageTypeV3.MTV3_CALL_REJECT,
        reject.writeToBuffer(),
      );
    } catch (e) {
      _log.warn('Reject signal send failed (call already torn down locally): $e');
    }
  }

  /// Hang up an active call.
  ///
  /// Cleanup-Reihenfolge ist bewusst lokal-zuerst:
  /// 1) Lokalen Call-State teardownen (state=ended, _currentCall=null,
  ///    onCallEnded → CleonaService stoppt die Audio-Engine).
  /// 2) DANACH best-effort CALL_HANGUP an die Gegenseite senden.
  ///
  /// Damit bleibt der Call lokal NICHT „active" hängen wenn `sendViaUser`
  /// throwt, hängt oder das Multi-Identity-Wiring den Send droppt
  /// (`sendToUser` gibt `false` zurück bei senderUserId-Mismatch). Aus
  /// Anwendersicht ist „hangup" ein lokaler Akt; das Network-Signal an
  /// die Gegenseite ist Höflichkeit. Ohne diese Reihenfolge kann
  /// `_currentCall` nach `hangup()` weiter `!= null` bleiben (B-7,
  /// Test gui-33-video-calls 33.10).
  Future<void> hangup() async {
    final call = _currentCall;
    if (call == null) return;

    _cancelRingingTimeout();
    call.state = CallState.ended;
    onCallEnded?.call(call);
    _currentCall = null;
    _log.info('Call ended (local teardown done)');

    // Best-effort signal to the remote side. Failures here do not undo
    // the local teardown above.
    try {
      // TODO(v3-sub-message): swap to `CallHangupV3` once defined.
      final hangup = proto.CallHangup()..callId = call.callId;
      await sendViaUser?.call(
        hexToBytes(call.peerNodeIdHex),
        proto.MessageTypeV3.MTV3_CALL_HANGUP,
        hangup.writeToBuffer(),
      );
    } catch (e) {
      _log.warn('Hangup signal send failed (call already torn down locally): $e');
    }
  }

  // ── Incoming message handling (V3 — called from CleonaService) ──
  //
  // V3 receive-side handlers take an `ApplicationFrameV3` (whose
  // `payload` is the already-decrypted + user-sig-verified inner
  // proto-bytes) plus the wire-level `senderDeviceId` from
  // `NetworkPacketV3`, plus the `SenderIdentitySnapshot` produced by
  // §2.4 [4] outer-sig-verify.

  /// V3: handle inbound CALL_INVITE.
  ///
  /// `frame.senderUserId` is the inviter's user-id (== `peerNodeIdHex`
  /// for 1:1 calls in the current build). `senderDeviceId` is the
  /// concrete device that sent the invite — used by the busy auto-reject
  /// path.
  void handleCallInviteV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot snapshot,
  ) {
    if (_currentCall != null) {
      _sendRejectV3(frame, senderDeviceId, 'busy');
      return;
    }

    final invite = proto.CallInvite.fromBuffer(frame.payload);
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    if (invite.callerEphX25519Pk.isNotEmpty) {
      _callerEphPk = Uint8List.fromList(invite.callerEphX25519Pk);
    }
    if (invite.callerKemCiphertext.isNotEmpty) {
      _callerKemCt = Uint8List.fromList(invite.callerKemCiphertext);
    }

    final session = CallSession(
      callId: Uint8List.fromList(invite.callId),
      peerNodeIdHex: senderHex,
      direction: CallDirection.incoming,
      isVideo: invite.isVideo,
      state: CallState.ringing,
    );
    _currentCall = session;

    _startRingingTimeout();

    onIncomingCall?.call(session);
    _log.info(
        'V3 incoming ${invite.isVideo ? "video" : "audio"} call from ${senderHex.substring(0, 8)}');
  }

  /// V3: handle inbound CALL_ANSWER.
  void handleCallAnswerV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot snapshot,
  ) {
    final answer = proto.CallAnswer.fromBuffer(frame.payload);
    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, answer.callId)) return;

    if (call.ephX25519Sk != null && answer.calleeEphX25519Pk.isNotEmpty) {
      final sodium = SodiumFFI();
      final calleePk = Uint8List.fromList(answer.calleeEphX25519Pk);
      final dhSecret = sodium.x25519ScalarMult(call.ephX25519Sk!, calleePk);

      Uint8List? calleeKemSecret;
      if (answer.calleeKemCiphertext.isNotEmpty) {
        try {
          final oqs = OqsFFI();
          calleeKemSecret = oqs.mlKemDecapsulate(
            Uint8List.fromList(answer.calleeKemCiphertext),
            identity.mlKemSecretKey,
          );
        } catch (e) {
          _log.warn('KEM decapsulation failed: $e');
        }
      }

      final ikm = <int>[
        ...dhSecret,
        if (call.kemSharedSecret != null) ...call.kemSharedSecret!,
        if (calleeKemSecret != null) ...calleeKemSecret,
      ];
      call.sharedSecret = sodium.hkdfSha256(
        Uint8List.fromList(ikm),
        info: Uint8List.fromList('cleona-call-v1'.codeUnits),
        length: 32,
      );
    }

    _cancelRingingTimeout();
    call.state = CallState.inCall;
    onCallAccepted?.call(call);
    _log.info('V3 call answered by ${call.peerNodeIdHex.substring(0, 8)}');
  }

  /// V3: handle inbound CALL_REJECT.
  void handleCallRejectV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot snapshot,
  ) {
    final reject = proto.CallReject.fromBuffer(frame.payload);
    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, reject.callId)) return;

    _cancelRingingTimeout();
    call.state = CallState.ended;
    onCallRejected?.call(call, reject.reason);
    _currentCall = null;
    _log.info('V3 call rejected: ${reject.reason}');
  }

  /// V3: handle inbound CALL_HANGUP.
  void handleCallHangupV3(
    proto.ApplicationFrameV3 frame,
    Uint8List senderDeviceId,
    SenderIdentitySnapshot snapshot,
  ) {
    final hangup = proto.CallHangup.fromBuffer(frame.payload);
    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, hangup.callId)) return;

    _cancelRingingTimeout();
    call.state = CallState.ended;
    onCallEnded?.call(call);
    _currentCall = null;
    _log.info('V3 call hung up by remote');
  }

  /// V3 busy auto-reject — uses the wire-carried `senderDeviceId`
  /// directly (no routing-table lookup needed) per Architecture
  /// §2.6 receiver step 4. Builds a V3 inner+outer for CALL_REJECT and
  /// dispatches via `node.sendToDevice` to the inviter's specific device.
  void _sendRejectV3(
    proto.ApplicationFrameV3 incoming,
    Uint8List senderDeviceId,
    String reason,
  ) {
    try {
      final invite = proto.CallInvite.fromBuffer(incoming.payload);
      final senderUserId = Uint8List.fromList(incoming.senderUserId);
      final senderHex = bytesToHex(senderUserId);
      final contact = contacts[senderHex];
      if (contact == null ||
          contact.x25519Pk == null ||
          contact.mlKemPk == null) {
        _log.debug('V3 busy-reject: missing KEM pubkeys for '
            '${senderHex.substring(0, 8)} — drop');
        return;
      }

      final reject = proto.CallReject()
        ..callId = invite.callId
        ..reason = reason;

      final inner = proto.ApplicationFrameV3()
        ..version = 1
        ..recipientUserId = senderUserId
        ..senderUserId = identity.userId
        ..messageType = proto.MessageTypeV3.MTV3_CALL_REJECT
        ..messageId = SodiumFFI().randomBytes(16)
        ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
        ..payload = reject.writeToBuffer();
      final innerBytes = V3FrameCodec.buildAndEncryptInner(
        inner: inner,
        senderUserEd25519Sk: identity.signingEd25519Sk,
        senderUserMlDsaSk: identity.signingMlDsaSk,
        recipientUserX25519Pk: contact.x25519Pk!,
        recipientUserMlKemPk: contact.mlKemPk!,
      );
      final outer = V3FrameCodec.buildOuter(
        nextHopDeviceId: senderDeviceId,
        senderDeviceId: node.primaryIdentity.deviceNodeId,
        deviceKeys: node.deviceKeyPair,
        innerPayload: innerBytes,
        payloadType: proto.PayloadTypeV3.PAYLOAD_APPLICATION_FRAME,
        applicationFlavor: true,
        skipPoW: false,
      );
      // ignore: discarded_futures
      node.sendToDevice(outer, senderDeviceId);
    } catch (e) {
      _log.debug('V3 busy-reject build failed: $e');
    }
  }

  // ── Ringing Timeout ─────────────────────────────────────────────

  void _startRingingTimeout() {
    _cancelRingingTimeout();
    _ringingTimeout = Timer(Duration(seconds: ringingTimeoutSec), () {
      final call = _currentCall;
      if (call == null || call.state != CallState.ringing) return;

      _log.info('Ringing timeout (${ringingTimeoutSec}s) — auto-hangup');
      if (call.direction == CallDirection.outgoing) {
        hangup();
      } else {
        rejectCall(reason: 'timeout');
      }
    });
  }

  void _cancelRingingTimeout() {
    _ringingTimeout?.cancel();
    _ringingTimeout = null;
  }

  bool _callIdMatches(Uint8List a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
