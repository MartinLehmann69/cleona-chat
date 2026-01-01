import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/calls/audio_engine.dart';
import 'package:cleona/core/calls/audio_mixer.dart';
import 'package:cleona/core/calls/audio_permissions.dart';
import 'package:cleona/core/calls/call_manager.dart';
import 'package:cleona/core/calls/foreground_service.dart';
import 'package:cleona/core/calls/group_call_manager.dart';
import 'package:cleona/core/calls/group_call_session.dart';
import 'package:cleona/core/calls/group_video_receiver.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/network/v3_frame_codec.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/service/service_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

class CallService {
  final ServiceContext _ctx;
  final NotificationSoundService notificationSound;
  final CLogger _log;

  late final CallManager callManager;
  late final GroupCallManager groupCallManager;

  AudioEngine? _audioEngine;
  AudioMixer? _audioMixer;
  dynamic _groupVideoEngine;
  GroupVideoReceiver? _groupVideoReceiver;

  // 1:1 video (§ F-B). `dynamic` because the concrete VideoEngine lives in
  // video_engine.dart, which pulls in dart:ui — call_service.dart must stay
  // headless-daemon-safe (dart compile exe lib/service_daemon.dart /
  // lib/headless.dart have no dart.library.ui). The engine is constructed
  // by [createVideoEngine], injected from a Flutter-context caller (see
  // main.dart _wireServiceCallbacks), exactly like the group video path.
  dynamic _videoEngine;
  bool _videoPaused = false;

  // Callbacks forwarded from CleonaService
  void Function(CallInfo)? onIncomingCall;
  void Function(CallInfo)? onCallAccepted;
  void Function(CallInfo, String)? onCallRejected;
  void Function(CallInfo)? onCallEnded;
  void Function(GroupCallInfo info)? onIncomingGroupCall;
  void Function(GroupCallInfo info)? onGroupCallStarted;
  void Function(GroupCallInfo info)? onGroupCallEnded;
  void Function(Uint8List serializedVideoFrame)? onVideoFrameReceived;
  void Function()? onKeyframeRequested;
  void Function(String senderHex, Uint8List i420, int width, int height)?
      onGroupVideoI420Frame;
  dynamic Function(Uint8List callKey, void Function(Uint8List) onVideoFrame)?
      createVideoEngine;
  void Function()? onStateChanged;
  void Function(String callerName, String callId)? onPostCallNotificationAndroid;
  void Function()? onCancelCallNotificationAndroid;

  CallService(this._ctx, {required this.notificationSound, required CLogger log})
      : _log = log;

  void init() {
    callManager = CallManager(
      identity: _ctx.identity,
      node: _ctx.node,
      contacts: _ctx.contacts,
      profileDir: _ctx.profileDir,
    );
    callManager.sendViaUser = (recipientUserId, type, payload) =>
        _ctx.sendToUser(
          recipientUserId: recipientUserId,
          messageType: type,
          payload: payload,
        );
    callManager.onIncomingCall = (session) {
      onIncomingCall?.call(session.toCallInfo());
      onStateChanged?.call();
    };
    callManager.onCallAccepted = (session) {
      _startAudioEngine(session);
      _startVideoEngine(session);
      onCallAccepted?.call(session.toCallInfo());
      onStateChanged?.call();
    };
    callManager.onCallRejected = (session, reason) {
      _stopAudioEngine();
      _stopVideoEngine();
      onCallRejected?.call(session.toCallInfo(), reason);
      onStateChanged?.call();
    };
    callManager.onCallEnded = (session) {
      _stopAudioEngine();
      _stopVideoEngine();
      onCallEnded?.call(session.toCallInfo());
      onStateChanged?.call();
    };

    // Receive-side keyframe recovery (mid-stream join / decode failures)
    // asks the peer for a fresh keyframe; the peer's video engine forces
    // one on its next captured/fed frame. Wired once — [_videoEngine] is
    // read dynamically at call time so this stays valid across calls.
    onKeyframeRequested = () {
      try {
        (_videoEngine as dynamic)?.forceKeyframe();
      } catch (_) {}
    };

    _ctx.node.onRouteDownForCalls = (peerHex) {
      final session = callManager.currentCall;
      if (session == null) return;
      final cachedDevHex = session.cachedRoute?.nodeIdHex;
      if (session.peerNodeIdHex == peerHex || cachedDevHex == peerHex) {
        session.invalidateCachedRoute();
      }
    };

    groupCallManager = GroupCallManager(
      identity: _ctx.identity,
      node: _ctx.node,
      contacts: _ctx.contacts,
      getGroups: () => _ctx.groups,
      profileDir: _ctx.profileDir,
    );
    groupCallManager.sendViaUser = (recipientUserId, type, payload) =>
        _ctx.sendToUser(
          recipientUserId: recipientUserId,
          messageType: type,
          payload: payload,
        );
    groupCallManager.onIncomingGroupCall = (info) {
      onIncomingGroupCall?.call(info);
      onStateChanged?.call();
    };
    groupCallManager.onGroupCallStarted = (info) {
      _startAudioMixer(groupCallManager.currentGroupCall!);
      _startGroupVideo(groupCallManager.currentGroupCall!);
      onGroupCallStarted?.call(info);
      onStateChanged?.call();
    };
    groupCallManager.onGroupCallEnded = (info) {
      _stopAudioMixer();
      _stopGroupVideo();
      onGroupCallEnded?.call(info);
      onStateChanged?.call();
    };
    groupCallManager.onParticipantChanged = (hex, state) {
      if (state == ParticipantState.left ||
          state == ParticipantState.crashed) {
        _audioMixer?.removePeer(hex);
        _groupVideoReceiver?.removePeer(hex);
      }
      onStateChanged?.call();
    };
    groupCallManager.onOwnSendKeyChanged = (ownKey, version) {
      _audioMixer?.updateOwnSendKey(ownKey, version);
      try {
        (_groupVideoEngine as dynamic)?.updateKey(ownKey);
      } catch (_) {}
    };
    groupCallManager.onPeerSendKey = (senderUserHex, key, version) {
      _audioMixer?.setPeerSendKey(senderUserHex, key);
      _groupVideoReceiver?.setPeerSendKey(senderUserHex, key);
    };
  }

  void dispose() {
    _stopAudioMixer();
    _stopGroupVideo();
    groupCallManager.leaveGroupCall();
  }

  // ── 1:1 Calls ──────────────────────────────────────────────────────

  CallInfo? get currentCall => callManager.currentCall?.toCallInfo();

  Future<CallInfo?> startCall(String peerNodeIdHex, {bool video = false}) async {
    if (groupCallManager.currentGroupCall != null) return null;
    final session = await callManager.startCall(peerNodeIdHex, video: video);
    if (session != null) notificationSound.playRingback();
    return session?.toCallInfo();
  }

  Future<void> acceptCall() async {
    onCancelCallNotificationAndroid?.call();
    await notificationSound.stopRingtone();
    await callManager.acceptCall();
  }

  Future<void> rejectCall({String reason = 'busy'}) async {
    onCancelCallNotificationAndroid?.call();
    await notificationSound.stopRingtone();
    await callManager.rejectCall(reason: reason);
  }

  Future<void> hangup() async {
    await notificationSound.stopAll();
    await callManager.hangup();
  }

  bool get isMuted {
    if (_audioMixer != null) return _audioMixer!.isMuted;
    return _audioEngine?.isMuted ?? false;
  }

  void toggleMute() {
    if (_audioMixer != null) {
      _audioMixer!.muted = !_audioMixer!.isMuted;
    } else if (_audioEngine != null) {
      _audioEngine!.muted = !_audioEngine!.isMuted;
    }
  }

  bool get isSpeakerEnabled {
    if (_audioMixer != null) return _audioMixer!.isSpeakerEnabled;
    return _audioEngine?.isSpeakerEnabled ?? true;
  }

  void toggleSpeaker() {
    if (_audioMixer != null) {
      _audioMixer!.speakerEnabled = !_audioMixer!.isSpeakerEnabled;
    } else if (_audioEngine != null) {
      _audioEngine!.speakerEnabled = !_audioEngine!.isSpeakerEnabled;
    }
  }

  // ── Group Calls ─────────────────────────────────────────────────

  GroupCallInfo? get currentGroupCall =>
      groupCallManager.currentGroupCall?.toGroupCallInfo();

  Future<GroupCallInfo?> startGroupCall(String groupIdHex) async {
    if (callManager.currentCall != null) return null;
    final session = await groupCallManager.startGroupCall(groupIdHex);
    return session?.toGroupCallInfo();
  }

  Future<void> acceptGroupCall() => groupCallManager.acceptGroupCall();

  Future<void> rejectGroupCall({String reason = 'busy'}) =>
      groupCallManager.rejectGroupCall(reason: reason);

  Future<void> leaveGroupCall() async {
    _stopAudioMixer();
    _stopGroupVideo();
    await groupCallManager.leaveGroupCall();
  }

  Future<void> _startAudioMixer(GroupCallSession session) async {
    if (Platform.isAndroid) {
      final granted = await AudioPermissions.requestRecordAudio();
      if (!granted) {
        _log.warn('RECORD_AUDIO permission denied — group call audio disabled');
        return;
      }
    }
    if (Platform.isAndroid) {
      await ForegroundServiceControl.promoteForCall();
    }
    if (session.ownSendKey == null) return;
    try {
      _audioMixer = AudioMixer(
        ownSendKey: session.ownSendKey!,
        profileDir: _ctx.profileDir,
        ownSendKeyVersion: session.ownSendKeyVersion,
      );
      session.peerSendKeys
          .forEach((hex, k) => _audioMixer!.setPeerSendKey(hex, k.key));
      _audioMixer!.onAudioFrame = (encryptedFrame) {
        groupCallManager.sendGroupAudioFrame(encryptedFrame);
      };
      await _audioMixer!.start();
    } catch (e) {
      _log.error('Audio mixer start failed: $e');
    }
  }

  void _stopAudioMixer() {
    try {
      _audioMixer?.stop();
    } catch (e) {
      _log.warn('AudioMixer stop threw (swallowed): $e');
    }
    _audioMixer = null;
    if (Platform.isAndroid) {
      ForegroundServiceControl.demoteAfterCall();
    }
  }

  Future<void> _startGroupVideo(GroupCallSession session) async {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows) ||
        session.ownSendKey == null) {
      return;
    }
    _startGroupVideoCapture(session);
    _startGroupVideoReceiver(session);
  }

  void _startGroupVideoCapture(GroupCallSession session) {
    if (session.ownSendKey == null || createVideoEngine == null) return;
    try {
      _groupVideoEngine = createVideoEngine!(
        session.ownSendKey!,
        (serializedFrame) =>
            groupCallManager.sendGroupVideoFrame(serializedFrame),
      );
    } catch (e) {
      _log.error('Group video engine start failed: $e');
      _groupVideoEngine = null;
    }
  }

  void _startGroupVideoReceiver(GroupCallSession session) {
    if (session.ownSendKey == null) return;
    _groupVideoReceiver = GroupVideoReceiver(
      profileDir: _ctx.profileDir,
    );
    session.peerSendKeys
        .forEach((hex, k) => _groupVideoReceiver!.setPeerSendKey(hex, k.key));
    _groupVideoReceiver!.onDecodedI420 = (senderHex, i420, w, h) {
      onGroupVideoI420Frame?.call(senderHex, i420, w, h);
    };
  }

  void _stopGroupVideo() {
    try {
      (_groupVideoEngine as dynamic)?.stop();
    } catch (_) {}
    _groupVideoEngine = null;
    _groupVideoReceiver?.dispose();
    _groupVideoReceiver = null;
  }

  // ── Audio Engine (1:1) ────────────────────────────────────────────

  Future<void> _startAudioEngine(CallSession session) async {
    if (Platform.isAndroid) {
      final granted = await AudioPermissions.requestRecordAudio();
      if (!granted) {
        _log.warn('RECORD_AUDIO permission denied — call audio disabled');
        return;
      }
    }
    if (Platform.isAndroid) {
      await ForegroundServiceControl.promoteForCall();
    }
    if (session.sharedSecret == null) return;
    try {
      _audioEngine = AudioEngine(
        sharedSecret: session.sharedSecret!,
        profileDir: _ctx.profileDir,
      );
      _audioEngine!.onAudioFrame = (encryptedFrame) {
        _sendAudioFrame(session, encryptedFrame);
      };
      await _audioEngine!.start();
    } catch (e) {
      _log.error('Audio engine start failed: $e');
    }
  }

  void _stopAudioEngine() {
    try {
      _audioEngine?.stop();
    } catch (e) {
      _log.warn('AudioEngine stop threw (swallowed): $e');
    }
    _audioEngine = null;
    if (Platform.isAndroid) {
      ForegroundServiceControl.demoteAfterCall();
    }
  }

  // ── Video Engine (1:1) ────────────────────────────────────────────

  /// Starts the 1:1 video pipeline for a video call once it reaches
  /// [CallState.inCall] (mirrors [_startAudioEngine], called from the same
  /// `onCallAccepted` hook so both caller-on-answer and callee-on-accept
  /// wire up identically). No-op for audio-only calls or when no video
  /// engine factory has been injected (headless daemon builds without a
  /// Flutter context, or platforms where camera capture is out of scope).
  Future<void> _startVideoEngine(CallSession session) async {
    if (!session.isVideo) return;
    if (session.sharedSecret == null) return;
    if (createVideoEngine == null) {
      _log.debug('Video call requested but no video engine factory wired '
          '— continuing audio-only');
      return;
    }
    try {
      final engine = createVideoEngine!(
        session.sharedSecret!,
        (serializedFrame) => _sendVideoFrame(session, serializedFrame),
      );
      _videoEngine = engine;
      try {
        (engine as dynamic).onKeyframeNeeded = sendKeyframeRequest;
      } catch (_) {}
    } catch (e) {
      _log.error('Video engine start failed — continuing audio-only: $e');
      _videoEngine = null;
    }
  }

  void _stopVideoEngine() {
    try {
      (_videoEngine as dynamic)?.stop();
    } catch (e) {
      _log.warn('VideoEngine stop threw (swallowed): $e');
    }
    _videoEngine = null;
    _videoPaused = false;
  }

  /// Whether outgoing video capture+send is currently paused (user toggle).
  bool get isVideoMuted => _videoPaused;

  /// Pause/resume outgoing video capture+send. No-op (with a debug log) if
  /// no video engine is active for the current call (audio-only call, or
  /// video failed to start on a platform without capture/codec support).
  void toggleVideoMute() {
    _videoPaused = !_videoPaused;
    final engine = _videoEngine;
    if (engine == null) {
      _log.debug('toggleVideoMute: no active video engine — no-op');
      return;
    }
    try {
      (engine as dynamic).muted = _videoPaused;
    } catch (e) {
      _log.debug('toggleVideoMute dispatch failed: $e');
    }
  }

  /// Switch capture camera (Android front/back). Returns false (with a
  /// debug log) on platforms without a camera-switch hook — Linux's gray
  /// isolate-capture and iOS's not-yet-implemented capture both degrade
  /// this way rather than crashing.
  Future<bool> switchCamera() async {
    final engine = _videoEngine;
    if (engine == null) {
      _log.debug('switchCamera: no active video engine — no-op');
      return false;
    }
    try {
      return await (engine as dynamic).switchCamera() as bool? ?? false;
    } catch (e) {
      _log.debug('switchCamera dispatch failed: $e');
      return false;
    }
  }

  /// V3 choke-point for 1:1 live-media frames (Architecture §10.3,
  /// Appendix B.2, F-C amendment).
  ///
  /// Live audio/video MUST NOT go through [ServiceContext.sendToUser] (full
  /// ML-DSA user-sig + zstd + PoW pipeline — latency-prohibitive at ~50
  /// frames/sec) NOR through the per-recipient KEM inner
  /// ([V3FrameCodec.buildAndEncryptInner]): [encryptedFrame] is already
  /// AES-256-GCM-encrypted under the call's negotiated `sharedSecret` by
  /// [AudioEngine], which already provides confidentiality and per-frame
  /// authenticity. Wrapping it again in a KEM + ML-DSA inner sig (~4.4 KB)
  /// is pure overhead — the field-measured bug this fixes (5,472 B/frame,
  /// 5 UDP fragments) instead of the ~470 B architecture target.
  ///
  /// The inner [proto.ApplicationFrameV3] therefore goes out **plain**
  /// (no User-Sig, no KEM) — only the outer [proto.NetworkPacketV3] keeps
  /// its Ed25519-only device-sig (`applicationFlavor: false`) and skips
  /// PoW, same as before. Fire-and-forget via [CleonaNode.sendToDevice] —
  /// no await, no ACK tracking for live media.
  void sendLiveMediaFrame({
    required CallSession session,
    required proto.MessageTypeV3 messageType,
    required Uint8List encryptedFrame,
  }) {
    if (session.state == CallState.ended) return;
    final peerUserId = hexToBytes(session.peerNodeIdHex);

    // --- Contact KEM pubkeys gate whether we can send at all --------------
    // Not needed for the plaintext inner itself, but the graceful-
    // degradation fallback below (`sendToUser`) needs them just as much as
    // the old KEM-inner path did — no KEM pubkeys, no usable send path.
    final contact = _ctx.contacts[session.peerNodeIdHex];
    if (contact == null || contact.x25519Pk == null || contact.mlKemPk == null) {
      // Graceful degradation: fall back to full sendToUser path.
      unawaited(_ctx.sendToUser(
        recipientUserId: peerUserId,
        messageType: messageType,
        payload: encryptedFrame,
      ));
      return;
    }

    // --- Resolve peer device route ----------------------------------------
    if (session.cachedRoute == null) {
      final peer = _ctx.node.routingTable.getPeer(peerUserId) ??
          _ctx.node.routingTable.getPeerByUserId(peerUserId);
      if (peer != null) {
        session.cachedRoute = peer;
        session.cachedRouteAt = DateTime.now();
      }
    }
    final peer = session.cachedRoute;
    if (peer == null) {
      // No route yet — fall back to sendToUser which runs the full cascade.
      unawaited(_ctx.sendToUser(
        recipientUserId: peerUserId,
        messageType: messageType,
        payload: encryptedFrame,
      ));
      return;
    }

    // --- Build V3 inner (ApplicationFrame, PLAIN — no KEM, no user-sig) ---
    final inner = proto.ApplicationFrameV3()
      ..version = 1
      ..recipientUserId = peerUserId
      ..senderUserId = _ctx.identity.userId
      ..messageType = messageType
      ..messageId = SodiumFFI().randomBytes(16)
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..payload = encryptedFrame;

    // --- Build V3 outer (NetworkPacket, Ed25519-only device sig, no PoW) --
    final outer = V3FrameCodec.buildOuter(
      nextHopDeviceId: peer.nodeId,
      senderDeviceId: _ctx.node.primaryIdentity.deviceNodeId,
      deviceKeys: _ctx.node.deviceKeyPair,
      innerPayload: inner.writeToBuffer(),
      payloadType: proto.PayloadTypeV3.PAYLOAD_APPLICATION_FRAME,
      applicationFlavor: false, // Ed25519-only device sig — §3.5
      skipPoW: true,
    );

    // Fire-and-forget — no await, no ACK tracking for live media.
    unawaited(_ctx.node.sendToDevice(outer, peer.nodeId));
  }

  void _sendAudioFrame(CallSession session, Uint8List encryptedFrame) {
    session.framesSent++;
    sendLiveMediaFrame(
      session: session,
      messageType: proto.MessageTypeV3.MTV3_CALL_AUDIO,
      encryptedFrame: encryptedFrame,
    );
  }

  /// True iff [senderDeviceId] is the device of an active 1:1 call's
  /// peer, or a participant device of an active group call. Cheap
  /// device-only gate used by the receive-side live-media fast path
  /// (Architecture §10.3, F-C) to decide whether a plaintext-inner parse
  /// of the inbound payload is even worth attempting.
  bool isLiveMediaSender(Uint8List senderDeviceId) {
    final call = callManager.currentCall;
    if (call != null &&
        call.state == CallState.inCall &&
        call.peerDeviceId != null &&
        bytesToHex(call.peerDeviceId!) == bytesToHex(senderDeviceId)) {
      return true;
    }
    final group = groupCallManager.currentGroupCall;
    if (group != null && group.state == GroupCallState.inCall) {
      final peer = _ctx.node.routingTable.getPeer(senderDeviceId);
      final userHex = peer?.userId != null ? bytesToHex(peer!.userId!) : null;
      if (userHex != null &&
          group.participants[userHex]?.state == ParticipantState.joined) {
        return true;
      }
    }
    return false;
  }

  /// True iff [senderUserId] is the expected peer identity for the
  /// currently active call — the second half of the live-media fast-path
  /// admission check (Architecture §10.3), applied by the caller AFTER
  /// the plaintext inner has been parsed off the wire (defence in depth:
  /// device match alone is not sufficient, the claimed user must also
  /// match).
  bool isKnownCallPeerUserId(Uint8List senderUserId) {
    final call = callManager.currentCall;
    if (call != null &&
        call.state == CallState.inCall &&
        call.peerNodeIdHex == bytesToHex(senderUserId)) {
      return true;
    }
    final group = groupCallManager.currentGroupCall;
    if (group != null && group.state == GroupCallState.inCall) {
      final p = group.participants[bytesToHex(senderUserId)];
      if (p != null && p.state == ParticipantState.joined) return true;
    }
    return false;
  }

  /// Logs once per call when the receive-side live-media fast path
  /// (Architecture §10.3) starts admitting inbound frames without the
  /// per-recipient KEM. Called from [CleonaService]'s fast path on first
  /// acceptance — never per-frame (audio alone runs at ~50 frames/sec).
  void logLiveMediaFastPathOnce(Uint8List senderDeviceId) {
    final call = callManager.currentCall;
    if (call != null &&
        call.state == CallState.inCall &&
        call.peerDeviceId != null &&
        bytesToHex(call.peerDeviceId!) == bytesToHex(senderDeviceId)) {
      if (!call.liveMediaFastPathLogged) {
        call.liveMediaFastPathLogged = true;
        _log.info('live-media fast path active for '
            '${call.peerNodeIdHex.substring(0, 8)}');
      }
      return;
    }
    final group = groupCallManager.currentGroupCall;
    if (group != null &&
        group.state == GroupCallState.inCall &&
        !group.liveMediaFastPathLogged) {
      group.liveMediaFastPathLogged = true;
      _log.info('live-media fast path active for group call '
          '${group.callIdHex.substring(0, 8)}');
    }
  }

  /// Same choke-point for 1:1 video frames — routed through
  /// [sendLiveMediaFrame] (plain inner under the call key, §10.3 /
  /// Appendix B.2) so audio and video share one envelope implementation.
  /// Called from [VideoEngine.onVideoFrame] via the injected
  /// [createVideoEngine] factory.
  void _sendVideoFrame(CallSession session, Uint8List encryptedFrame) {
    session.videoFramesSent++;
    sendLiveMediaFrame(
      session: session,
      messageType: proto.MessageTypeV3.MTV3_CALL_VIDEO,
      encryptedFrame: encryptedFrame,
    );
  }

  void sendKeyframeRequest() {
    final session = callManager.currentCall;
    if (session == null || session.state != CallState.inCall) return;
    _ctx.sendToUser(
      recipientUserId: hexToBytes(session.peerNodeIdHex),
      messageType: proto.MessageTypeV3.MTV3_CALL_KEYFRAME_REQUEST,
      payload: Uint8List(0),
    );
  }

  // ── V3 Handlers ─────────────────────────────────────────────────

  void handleCallInviteV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    proto.CallInvite invite;
    try {
      invite = proto.CallInvite.fromBuffer(f.payload);
    } catch (e) {
      _log.warn('CALL_INVITE V3: payload parse failed: $e');
      return;
    }
    if (invite.isGroupCall) {
      groupCallManager.handleGroupCallInviteV3(f, sd, s);
    } else {
      callManager.handleCallInviteV3(f, sd, s);
    }
    notificationSound.startRingtone();
    notificationSound.vibrate(VibrationType.call);
    if (Platform.isAndroid) {
      final senderHex = bytesToHex(Uint8List.fromList(f.senderUserId));
      final contact = _ctx.contacts[senderHex];
      final callerName = contact?.displayName ?? senderHex.substring(0, 8);
      final callId = callManager.currentCall?.callIdHex ?? '';
      onPostCallNotificationAndroid?.call(callerName, callId);
    }
  }

  void handleCallAnswerV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    onCancelCallNotificationAndroid?.call();
    try { notificationSound.stopRingtone(); } catch (_) {}
    try { notificationSound.stopRingback(); } catch (_) {}
    try { notificationSound.playConnected(); } catch (_) {}
    if (groupCallManager.currentGroupCall != null) {
      groupCallManager.handleGroupCallAnswerV3(f, sd, s);
    } else {
      callManager.handleCallAnswerV3(f, sd, s);
    }
  }

  void handleCallRejectV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    onCancelCallNotificationAndroid?.call();
    try { notificationSound.stopRingtone(); } catch (_) {}
    try { notificationSound.stopRingback(); } catch (_) {}
    if (groupCallManager.currentGroupCall != null) {
      groupCallManager.handleGroupCallRejectV3(f, sd, s);
    } else {
      callManager.handleCallRejectV3(f, sd, s);
    }
  }

  void handleCallHangupV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    onCancelCallNotificationAndroid?.call();
    try { notificationSound.stopRingtone(); } catch (_) {}
    try { notificationSound.stopRingback(); } catch (_) {}
    if (groupCallManager.currentGroupCall != null) {
      groupCallManager.handleGroupCallHangupV3(f, sd, s);
    } else {
      callManager.handleCallHangupV3(f, sd, s);
    }
  }

  void handleIceCandidateV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    _log.debug('ICE_CANDIDATE V3: not wired yet — drop');
  }

  void handleCallRejoinV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    groupCallManager.handleCallRejoinV3(f, sd, s);
  }

  void handleCallAudioV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    final engine = _audioEngine;
    if (engine == null || !engine.isRunning) return;
    callManager.currentCall?.framesReceived++;
    engine.playFrame(Uint8List.fromList(f.payload));
  }

  void handleCallVideoV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    final session = callManager.currentCall;
    if (session == null || session.state != CallState.inCall) return;
    session.videoFramesReceived++;
    final payload = Uint8List.fromList(f.payload);
    onVideoFrameReceived?.call(payload);
    try {
      (_videoEngine as dynamic)?.processReceivedFrame(payload);
    } catch (e) {
      _log.debug('Video frame decode dispatch failed: $e');
    }
  }

  void handleCallGroupAudioV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    groupCallManager.handleGroupCallAudioV3(f, sd, s);
    if (_audioMixer != null) {
      try {
        final audio = proto.GroupCallAudio.fromBuffer(f.payload);
        final senderHex =
            bytesToHex(Uint8List.fromList(audio.senderNodeId));
        if (senderHex != _ctx.identity.userIdHex) {
          _audioMixer!
              .addFrame(senderHex, Uint8List.fromList(audio.encryptedAudio));
        }
      } catch (e) {
        _log.debug('Group audio V3 parse failed: $e');
      }
    }
  }

  void handleCallGroupVideoV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    groupCallManager.handleGroupCallVideoV3(f, sd, s);
    if (_groupVideoReceiver != null) {
      try {
        final video = proto.GroupCallVideo.fromBuffer(f.payload);
        final senderHex =
            bytesToHex(Uint8List.fromList(video.senderNodeId));
        if (senderHex != _ctx.identity.userIdHex) {
          _groupVideoReceiver!
              .addFrame(senderHex, Uint8List.fromList(video.videoFrameData));
        }
      } catch (e) {
        _log.debug('Group video V3 parse failed: $e');
      }
    }
  }

  void handleCallGroupLeaveV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    groupCallManager.handleGroupCallLeaveV3(f, sd, s);
  }

  void handleCallGroupKeyRotateV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    groupCallManager.handleGroupCallKeyRotateV3(f, sd, s);
  }

  void handleCallRttPingV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    groupCallManager.handleCallRttPingV3(f, sd, s);
  }

  void handleCallRttPongV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    groupCallManager.handleCallRttPongV3(f, sd, s);
  }

  void handleCallTreeUpdateV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
    groupCallManager.handleCallTreeUpdateV3(f, sd, s);
  }

  // §10.5 In-Call Collaboration (planned stubs)
  void handleWhiteboardStrokeV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {}
  void handleWhiteboardPageV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {}
  void handleFileExchangeV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {}
  void handleClipboardExchangeV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {}
  void handleScreenShareFrameV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {}
  void handleCallChatV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {}
  void handleRemoteControlInputV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {}
}
