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
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/service/service_context.dart';
import 'package:cleona/core/service/service_types.dart';
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
      onCallAccepted?.call(session.toCallInfo());
      onStateChanged?.call();
    };
    callManager.onCallRejected = (session, reason) {
      _stopAudioEngine();
      onCallRejected?.call(session.toCallInfo(), reason);
      onStateChanged?.call();
    };
    callManager.onCallEnded = (session) {
      _stopAudioEngine();
      onCallEnded?.call(session.toCallInfo());
      onStateChanged?.call();
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
      groups: _ctx.groups,
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
    await notificationSound.stopRingtone();
    await callManager.acceptCall();
  }

  Future<void> rejectCall({String reason = 'busy'}) async {
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

  void _sendAudioFrame(CallSession session, Uint8List encryptedFrame) {
    if (session.state == CallState.ended) return;
    session.framesSent++;
    final peerNodeId = hexToBytes(session.peerNodeIdHex);

    if (session.cachedRoute == null) {
      final peer = _ctx.node.routingTable.getPeer(peerNodeId) ??
          _ctx.node.routingTable.getPeerByUserId(peerNodeId);
      if (peer != null) {
        session.cachedRoute = peer;
        session.cachedRouteAt = DateTime.now();
      }
    }

    unawaited(_ctx.sendToUser(
      recipientUserId: peerNodeId,
      messageType: proto.MessageTypeV3.MTV3_CALL_AUDIO,
      payload: encryptedFrame,
    ));
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
  }

  void handleCallAnswerV3(proto.ApplicationFrameV3 f, Uint8List sd,
      SenderIdentitySnapshot s) {
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
    onVideoFrameReceived?.call(Uint8List.fromList(f.payload));
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
