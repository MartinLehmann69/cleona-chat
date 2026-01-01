import 'dart:async';
import 'dart:typed_data';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
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

  // ── Per-Call Route Cache (Plan §D2) ──────────────────────────────
  // Caches the resolved peer for the duration of a call so audio frames
  // (~50/sec for Opus 20ms) don't repeat the routing-table lookup on
  // every send. Refreshed when DV-Routing's `onRouteDown` fires for this
  // peer — the next frame then falls through to the normal resolve path
  // in `node.sendEnvelope()`.
  //
  // Note on plan adaptation: the plan referenced `findBestRoute(...)` and
  // `sendEnvelopeViaPeer(...)` APIs that don't exist in the actual code.
  // The real APIs are `routingTable.getPeer(nodeId)` (or `getPeerByUserId`)
  // for resolution and `node.sendEnvelope(envelope, peer.nodeId)` for the
  // send. The cache stores the resolved `PeerInfo` and the call-site keeps
  // using `node.sendEnvelope` with the cached peer's nodeId — saving the
  // double-hashing work of re-keying the routing table on every frame.
  PeerInfo? cachedRoute;
  DateTime? cachedRouteAt;

  /// Invalidate cached route — next frame send will resolve fresh via
  /// `routingTable.getPeer(...)`. Called from the DV-Routing
  /// `onRouteDown` callback when this peer's path drops.
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

    // Send CALL_INVITE with ephemeral public key
    final invite = proto.CallInvite()
      ..callId = callId
      ..callerEphX25519Pk = ephKp.publicKey
      ..isVideo = video;
    if (kemCt != null) {
      invite.callerKemCiphertext = kemCt;
    }

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CALL_INVITE,
      invite.writeToBuffer(),
      recipientId: hexToBytes(peerNodeIdHex),
    );

    // §26 Phase 3: fan-out to ALL devices so any device can pick up the call
    final sent = await node.sendToAllDevices(envelope, hexToBytes(peerNodeIdHex));
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

    final answer = proto.CallAnswer()
      ..callId = call.callId
      ..calleeEphX25519Pk = ephKp.publicKey;
    if (kemCt != null) {
      answer.calleeKemCiphertext = kemCt;
    }

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CALL_ANSWER,
      answer.writeToBuffer(),
      recipientId: hexToBytes(call.peerNodeIdHex),
    );

    await node.sendEnvelope(envelope, hexToBytes(call.peerNodeIdHex));
    onCallAccepted?.call(call);
    _log.info('Call accepted with ${call.peerNodeIdHex.substring(0, 8)}');
  }

  /// Reject an incoming call.
  Future<void> rejectCall({String reason = 'busy'}) async {
    final call = _currentCall;
    if (call == null || call.state != CallState.ringing) return;

    _cancelRingingTimeout();
    call.state = CallState.ended;

    final reject = proto.CallReject()
      ..callId = call.callId
      ..reason = reason;

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CALL_REJECT,
      reject.writeToBuffer(),
      recipientId: hexToBytes(call.peerNodeIdHex),
    );

    await node.sendEnvelope(envelope, hexToBytes(call.peerNodeIdHex));
    _currentCall = null;
    _log.info('Call rejected: $reason');
  }

  /// Hang up an active call.
  Future<void> hangup() async {
    final call = _currentCall;
    if (call == null) return;

    _cancelRingingTimeout();
    call.state = CallState.ended;

    final hangup = proto.CallHangup()..callId = call.callId;

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CALL_HANGUP,
      hangup.writeToBuffer(),
      recipientId: hexToBytes(call.peerNodeIdHex),
    );

    await node.sendEnvelope(envelope, hexToBytes(call.peerNodeIdHex));
    onCallEnded?.call(call);
    _currentCall = null;
    _log.info('Call ended');
  }

  // ── Incoming message handling (called from CleonaService) ──────

  void handleCallInvite(proto.MessageEnvelope envelope) {
    if (_currentCall != null) {
      // Already in a call, auto-reject
      _sendReject(envelope, 'busy');
      return;
    }

    final invite = proto.CallInvite.fromBuffer(envelope.encryptedPayload);
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Store caller's ephemeral PK for key exchange on accept
    if (invite.callerEphX25519Pk.isNotEmpty) {
      _callerEphPk = Uint8List.fromList(invite.callerEphX25519Pk);
    }
    // Store caller's KEM ciphertext for decapsulation on accept
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

    // 60s Ringing Timeout — auto-reject if not answered
    _startRingingTimeout();

    onIncomingCall?.call(session);
    _log.info('Incoming ${invite.isVideo ? "video" : "audio"} call from ${senderHex.substring(0, 8)}');
  }

  void handleCallAnswer(proto.MessageEnvelope envelope) {
    final answer = proto.CallAnswer.fromBuffer(envelope.encryptedPayload);
    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, answer.callId)) return;

    // Derive shared secret: HKDF-SHA256(DH + KEM) — per CALLS.md spec
    if (call.ephX25519Sk != null && answer.calleeEphX25519Pk.isNotEmpty) {
      final sodium = SodiumFFI();
      final calleePk = Uint8List.fromList(answer.calleeEphX25519Pk);
      final dhSecret = sodium.x25519ScalarMult(call.ephX25519Sk!, calleePk);

      // Decapsulate callee KEM ciphertext
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

      // IKM: DH secret + KEM secrets (hybrid post-quantum)
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
    _log.info('Call answered by ${call.peerNodeIdHex.substring(0, 8)}');
  }

  void handleCallReject(proto.MessageEnvelope envelope) {
    final reject = proto.CallReject.fromBuffer(envelope.encryptedPayload);
    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, reject.callId)) return;

    _cancelRingingTimeout();
    call.state = CallState.ended;
    onCallRejected?.call(call, reject.reason);
    _currentCall = null;
    _log.info('Call rejected: ${reject.reason}');
  }

  void handleCallHangup(proto.MessageEnvelope envelope) {
    final hangup = proto.CallHangup.fromBuffer(envelope.encryptedPayload);
    final call = _currentCall;
    if (call == null || !_callIdMatches(call.callId, hangup.callId)) return;

    _cancelRingingTimeout();
    call.state = CallState.ended;
    onCallEnded?.call(call);
    _currentCall = null;
    _log.info('Call hung up by remote');
  }

  void _sendReject(proto.MessageEnvelope incoming, String reason) {
    try {
      final invite = proto.CallInvite.fromBuffer(incoming.encryptedPayload);
      final reject = proto.CallReject()
        ..callId = invite.callId
        ..reason = reason;
      final env = identity.createSignedEnvelope(
        proto.MessageType.CALL_REJECT,
        reject.writeToBuffer(),
        recipientId: Uint8List.fromList(incoming.senderId),
      );
      node.sendEnvelope(env, Uint8List.fromList(incoming.senderId));
    } catch (_) {}
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
