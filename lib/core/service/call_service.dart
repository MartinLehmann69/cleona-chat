import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/calls/audio_mixer.dart';
import 'package:cleona/core/calls/collaboration/screen_share_manager.dart';
import 'package:cleona/core/calls/jitter_buffer.dart';
import 'package:cleona/core/calls/session_behaviour.dart';
import 'package:cleona/core/calls/voice_codec.dart';
import 'package:cleona/core/calls/voice_event_dispatch.dart';
import 'package:cleona/core/calls/voice_session.dart';
import 'package:cleona/core/calls/audio_permissions.dart';
import 'package:cleona/core/calls/call_integration.dart';
import 'package:cleona/core/calls/call_manager.dart';
import 'package:cleona/core/calls/call_transport.dart';
import 'package:cleona/core/calls/call_transport_v41.dart';
import 'package:cleona/core/calls/upload_probe.dart';
import 'package:cleona/core/link_io/d_frame.dart';
// `d_socket.dart` stood here and was removed on 2026-09-03: the
// analyzer reported it as `unused_import`, and re-measured, not a single identifier from
// this library occurs in this file. The
// two remaining mentions (`:187`, `:341`) are COMMENTS that refer to
// `attachDSocket` or `DSession.lastFrameAt` — references, not
// use. The D plane stays reachable via `d_frame.dart`.
import 'package:cleona/core/calls/foreground_service.dart';
import 'package:cleona/core/calls/group_call_manager.dart';
import 'package:cleona/core/calls/group_call_session.dart';
import 'package:cleona/core/calls/group_video_receiver.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/service/service_context.dart';
import 'package:cleona/core/service/app_version.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/harvest_event.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;
import 'package:cleona/generated/proto/transport_v3.pb.dart' as proto;

class CallService {
  final ServiceContext _ctx;
  final NotificationSoundService notificationSound;
  final CLogger _log;

  late final CallManager callManager;
  late final GroupCallManager groupCallManager;

  /// The one upload probe of this node (S368, task 2).
  ///
  /// **One, not two.** It measures the LINE, and that is the same whether
  /// a 1:1 call is currently running or a group call. Two probes
  /// would mean that the value falls back to `unknown` on switching between both paths
  /// — i.e. is empty precisely when a
  /// group call begins and the weighting would need it.
  ///
  /// Fed from both send paths: [sendLiveMediaFrame] (1:1) and
  /// `GroupCallManager._sendGroupLiveMediaFrame` (group), each only on
  /// success. The value is NOT distributed — the control channel for that is missing
  /// (§17.1), and one is not invented here.
  final UploadProbe uploadProbe = UploadProbe();

  VoiceSession? _voiceSession;
  VoiceCodec? _captureCodec;
  VoiceCodec? _playbackCodec;
  Timer? _captureTimer;
  Int16List? _captureBuf;
  JitterBuffer? _jitterBuffer;
  bool _speakerEnabled = true;

  /// The caller `route_policy.dart`'s file doc says `RoutePolicy` needs but
  /// never gets on its own (S367): drains `VoiceSession.pollEvent()` on
  /// every capture tick and applies the resulting route switches. `null`
  /// outside an active voice session — see [_startVoiceSession]/
  /// [_stopVoiceSession].
  VoiceEventDispatcher? _voiceEventDispatcher;

  AudioMixer? _audioMixer;
  dynamic _groupVideoEngine;
  GroupVideoReceiver? _groupVideoReceiver;
  Timer? _audioLevelTimer;

  // 1:1 video (§ F-B). `dynamic` because the concrete VideoEngine lives in
  // video_engine.dart, which pulls in dart:ui — call_service.dart must stay
  // daemon-safe (dart compile exe lib/service_daemon.dart has no
  // dart.library.ui). The engine is constructed
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
  /// A group participant's video became renderable under [textureId], or is
  /// gone again when it is null. Replaces the superseded `onGroupVideoI420Frame`:
  /// pixels no longer cross the video ABI (I10), so what the UI gets is an
  /// opaque texture id for a Flutter `Texture` widget.
  void Function(String senderHex, int? textureId)? onGroupVideoTexture;
  dynamic Function(Uint8List callKey, void Function(Uint8List) onVideoFrame)?
      createVideoEngine;
  void Function()? onStateChanged;
  void Function(String callerName, String callId)? onPostCallNotificationAndroid;
  void Function()? onCancelCallNotificationAndroid;
  void Function(bool speaker)? onSetCallAudioModeAndroid;
  void Function()? onResetCallAudioModeAndroid;

  /// §10.4 "Session behaviour" (V1.10): AudioFocus / interruption handling +
  /// earpiece-only proximity monitoring (S367).
  ///
  /// Injected from `main.dart`, not called directly, for the same reason
  /// [callIntegration] is: `SessionBehaviourChannel`
  /// (`session_behaviour_channel.dart`) imports `package:flutter/services.dart`
  /// and therefore `dart:ui`, which this file must not pull in. The daemon
  /// (no system audio session to claim) simply leaves these `null` — every
  /// call site below already tolerates that (`?.call`), so a missing
  /// platform bridge degrades to "AudioFocus/proximity not managed", never a
  /// dropped call, exactly like [callIntegration]'s best-effort contract.
  ///
  /// [onRequestAudioFocus] / [onAbandonAudioFocus] bridge to
  /// `SessionBehaviourChannel.requestAudioFocus`/`.abandonAudioFocus`.
  /// [onSetProximityMonitoring] bridges to
  /// `SessionBehaviourChannel.setProximityMonitoring`, called with
  /// `shouldMonitorProximity(activeRoute)` at call start and after every
  /// `RoutePolicy` decision.
  Future<bool> Function()? onRequestAudioFocus;
  Future<void> Function()? onAbandonAudioFocus;
  void Function(bool enabled)? onSetProximityMonitoring;

  /// Fired whenever [SessionBehaviour] (owned by the active call's
  /// `VoiceEventDispatcher`) reports an actual interruption transition — a
  /// foreign call, Siri, or another app took the OS audio session, or gave
  /// it back. `null` outside an active call. Never fired for "no change".
  void Function(bool interrupted)? onCallInterruptionChanged;

  /// Whether the current call is considered interrupted by the OS audio
  /// session right now (architecture §10.4, "Interruption"). `false` when no
  /// call is active — an interruption cannot outlive the call it belongs to.
  bool get isCallInterrupted =>
      _voiceEventDispatcher?.sessionBehaviour.isInterrupted ?? false;

  /// Feeds one interruption event that arrived through
  /// `SessionBehaviourChannel.onInterruption` (Android `AudioFocusChangeListener`
  /// / Apple interruption notification, bridged rather than posted through
  /// the `cleona_voice` ABI queue — see `session_behaviour_channel.dart`'s
  /// file doc for why). `main.dart` calls this from that callback; a no-op
  /// outside an active voice session (the OS can report a focus change after
  /// this side already tore its session down — the bridge itself has no
  /// notion of "is a Cleona call still running").
  void feedVoiceInterruptionEvent(VoiceEventRecord event) =>
      _voiceEventDispatcher?.feedBridgedEvent(event);

  /// §10.4 stage 7 (V3.2): CallKit / self-managed `ConnectionService`.
  ///
  /// Injected, not constructed here, for the same reason [createVideoEngine]
  /// is: the `MethodChannel` implementation imports
  /// `package:flutter/services.dart` and therefore `dart:ui`, which this file
  /// must not pull in — `dart compile exe lib/service_daemon.dart` fails
  /// outright if it does. A Flutter-context caller (`main.dart`) assigns a
  /// `MethodChannelCallIntegration`; the daemon keeps the no-op, which is
  /// correct there anyway since it has no system call UI.
  ///
  /// Best-effort by construction — never load-bearing: every method answers
  /// `false` instead of throwing where the platform has no such concept
  /// (Linux, Windows, Android < API 26).
  ///
  /// The setter re-attaches the OS-intent callbacks. Without that, injecting
  /// the real implementation after [init] would silently drop them and the
  /// system UI's answer and hang-up buttons would do nothing — a failure that
  /// only shows up on a device, which is the worst place to find it.
  CallIntegration get callIntegration => _callIntegration;
  set callIntegration(CallIntegration value) {
    _callIntegration = value;
    _attachCallIntegrationCallbacks();
  }

  CallIntegration _callIntegration = NoopCallIntegration();

  // Until S392 a slot `resolveCallDisplayName` stood here, which was supposed to
  // resolve the real name of a contact into the call display of the OPERATING
  // SYSTEM. It was never filled — not on 4.2 and not on
  // 3.2.2 (there `call_service.dart:113`, assignment in the whole tree: none).
  // Removed instead of wired, owner decision 22.09.2026: what goes to the
  // operating system is the identifier on all platforms; real names
  // are shown only by the own UI. See [_osDisplayName].

  /// §10.4 stage 7 (V3.2). The OS drives these; they are requests, not
  /// confirmations. Each is routed into the SAME `CallManager` entry point the
  /// in-app buttons use, so there is exactly one answer path and one teardown
  /// path regardless of where the intent came from. Re-run whenever
  /// [callIntegration] is replaced.
  void _attachCallIntegrationCallbacks() {
    _callIntegration.onAnswerCall = (callId) {
      final call = callManager.currentCall;
      if (call == null || call.callIdHex != callId) return;
      callManager.acceptCall();
    };
    _callIntegration.onEndCall = (callId) {
      final call = callManager.currentCall;
      if (call == null || call.callIdHex != callId) return;
      // Ringing but not yet accepted is a rejection, anything later is a
      // hang-up — the same distinction the in-app UI makes.
      if (call.state == CallState.ringing &&
          call.direction == CallDirection.incoming) {
        callManager.rejectCall(reason: 'declined');
      } else {
        callManager.hangup();
      }
    };
  }

  /// What stands in the call display of the OPERATING SYSTEM: the shortened
  /// identifier of the peer, never a real name.
  ///
  /// This string leaves the application and lands in a store
  /// that Cleona no longer controls — on iOS in `CXHandle` and
  /// `localizedCallerName` (`ios/Runner/CallKitHandler.swift:212-213`) and
  /// thus in the phone's call list, on Android in
  /// `Connection.setCallerDisplayName(…, PRESENTATION_ALLOWED)`
  /// (`CleonaCallIntegration.kt:301`). It thus falls outside §4.5.3:
  /// everything Cleona knows about a human otherwise lies encrypted
  /// in its own storage.
  ///
  /// **That is why the identifier stands here, and the same on every platform**
  /// (owner decision 22.09.2026). The real name belongs in the own
  /// UI — for instance in the notification that
  /// [onPostCallNotificationAndroid] posts: Cleona shows that itself, it
  /// does not wander into the phone book.
  ///
  /// Shortened to eight characters, because a 64-character identifier is unreadable on a
  /// lock screen. That is the ONE place where this
  /// length is fixed for the way outside.
  static String _osDisplayName(String identifierHex) =>
      identifierHex.length >= 8 ? identifierHex.substring(0, 8) : identifierHex;

  String _displayNameFor(CallSession call) =>
      _osDisplayName(call.peerNodeIdHex);
  void Function(String reason)? onVideoUnavailable;

  /// A call was refused BECAUSE plane D cannot carry anything (§17).
  ///
  /// [reason] is the diagnostic line from
  /// `CallTransport.mediaUnavailableReason` — log and support text, not a
  /// UI string; it is not translated.
  ///
  /// **TODAY NOBODY HANGS ON THIS, and that is reported.**
  /// `chat_screen.dart:2653` throws a `null` from [startCall] away without a word,
  /// and `main.dart` does not wire this callback (yet) — both
  /// files do not belong to this work package. Until that happens,
  /// the reason stands in the log and the user sees nothing. The callback
  /// exists so that the wiring is one line and not a search.
  void Function(String reason)? onCallUnavailable;

  /// §10.4 / E5 — an inbound CALL_INVITE was refused because the caller runs
  /// a build that does not speak the new voice stack.
  ///
  /// Arguments: caller user-id hex, the advertised `major * 1000 + minor`
  /// (0 when the build predates the field), and the wire reason code
  /// [rejectReasonIncompatibleVersion]. The UI turns the code into text via
  /// the i18n key `call_rejected_incompatible_version`; the raw version is
  /// passed so a support view can show what the other side actually claimed.
  void Function(String callerUserIdHex, int callerAppMajorMinor, String reason)?
      onIncompatibleCallRejected;

  CallService(this._ctx, {required this.notificationSound, required this._log})
      :
        // The transport arises in the CONSTRUCTOR, not in `init()`.
        // As `late final` in `init()` it was a trap: `sendLiveMediaFrame`
        // is reachable without `init()` having run, and then ran into
        // a LateInitializationError instead of sending. In production the
        // service always calls `init()` first — but an assurance that only holds
        // through call order is exactly the class that AP-1
        // step 7 replaced at `NodeHost.start()` with a runtime guard.
        // Here the earliest construction time suffices:
        // everything needed hangs on the `_ctx`, which is already there.
        //
        // WITHOUT `dSocket` IN THE CONSTRUCTOR, and that is no longer a defect,
        // but the order: the D socket belongs to the NODE, and
        // that arises once per process, not per service. `attachV41`
        // supplies it afterwards (`attachCallDSocket` -> [attachDSocket]).
        // Until then — and permanently if V4.1 delivery is switched
        // off — `callTransport.mediaUnavailableReason` reports a reason
        // and [startCall] refuses with it, instead of setting up a call
        // that then stays silent.
        _v41Transport = CallTransportV41(
          profileDir: _ctx.profileDir,
          // `skipL3: true` is the class switch of the signalling.
          // The name is a V3 remnant; on the V4.1 line it chooses according to
          // §17.2 the HARVEST path (`sendeModus` -> `SendMode.secure`),
          // so that a device in the background can ring at all.
          sendSignalViaUser: (recipientUserId, type, payload) =>
              _ctx.sendToUser(
                recipientUserId: recipientUserId,
                messageType: type,
                payload: payload,
                skipL3: true,
              ),
        );

  /// The plane D API of this identity (§17). Public because the
  /// call managers need it; the implementation behind it is
  /// exchangeable.
  ///
  /// TWO HANDLES ON THE SAME OBJECT, and the reason is the contract:
  /// [callTransport] is the narrow plane D API from §17 ("call code does
  /// not access transport internals"), [_v41Transport] is the concrete
  /// version. Registering the D socket is not a plane D OPERATION,
  /// but the setup of the transport itself — it therefore does not belong
  /// in `CallTransport` but here.
  CallTransport get callTransport => _v41Transport;
  final CallTransportV41 _v41Transport;

  /// Hooks in plane D of the node (§17.3/§17.4). Called by `attachV41`
  /// via `CleonaService.attachCallPlaneD` as soon as node and service
  /// both stand.
  void attachPlaneD(CallPlaneD? planeD) =>
      _v41Transport.attachPlaneD(planeD);

  /// The network has changed (§17.4 path migration, S376/A-2).
  ///
  /// Called by `CleonaService.onNetworkChanged`. **For the same reason
  /// here and not in `CallTransport`** as [attachPlaneD] one line
  /// above: a network change is not a plane D OPERATION that the
  /// call code triggers, but an event at the transport itself. §17
  /// records that "call code does not access transport internals" —
  /// the narrow API therefore stays as it is.
  ///
  /// Without a running call the call costs zero packets.
  void onNetworkChanged() => _v41Transport.onNetworkChanged();

  void init() {
    callManager = CallManager(
      identity: _ctx.identity,
      transport: callTransport,
      contacts: _ctx.contacts,
      profileDir: _ctx.profileDir,
    );
    // S368: here stood `= minCallerAppMajorMinor` (3002). The node thus advertised
    // on the wire the SMALLEST ACCEPTED version as its own
    // — V4.1 announced itself as 3.2.0. That confuses "what am I" with "what
    // do I admit"; it was not a decision but an error in its
    // application. The node now reports its own version, derived
    // from `kCurrentAppVersion`.
    callManager.callerAppMajorMinor = ownAppMajorMinor;
    // Without `outLegs` (S357): the parameter solely carried the
    // INVITE repetition that §17.2 forbids.
    callManager.sendViaUser = (recipientUserId, type, payload) =>
        _ctx.sendToUser(
          recipientUserId: recipientUserId,
          messageType: type,
          payload: payload,
          skipL3: true,
        );
    _attachCallIntegrationCallbacks();

    callManager.onIncomingCall = (session) {
      callIntegration.reportIncomingCall(
        callId: session.callIdHex,
        displayName: _displayNameFor(session),
        hasVideo: session.isVideo,
      );
      onIncomingCall?.call(session.toCallInfo());
      onStateChanged?.call();
    };
    // §17.2: the ringback tone hangs on the first harvested RING_ACK, not
    // on sending the INVITE. Previously it ran from `startCall()` — against a
    // device of which nobody knew whether it was ever reached ("no fake
    // ringing against a device that was never reached").
    //
    // `onRemoteRinging` fires only for the FIRST ringing device; the
    // further RING_ACKs the manager only counts along. A second
    // tone start would be audible.
    callManager.onRemoteRinging = (session) {
      notificationSound.playRingback();
      onStateChanged?.call();
    };
    // §17.3: the punch window found no carrying address pair.
    //
    // THE CALL ENDS, and with a reason. The alternative would be a
    // conversation that looks established and stays silent — exactly the
    // version that `_mediaCarrierReady` rules out before the INVITE. Allowing it
    // here would mean making the same decision differently in the second
    // place.
    //
    // `onCallUnavailable` carries the text; §17.3 expressly demands a "clear message"
    // for the case without a shared address family.
    callManager.onMediaPathUnavailable = (session, reason) {
      _log.error('Layer D carries no media for '
          '${session.peerNodeIdHex.substring(0, 8)}: $reason');
      onCallUnavailable?.call(reason);
      unawaited(callManager.hangup());
    };
    callManager.onCallAccepted = (session) {
      _startVoiceSession(session);
      _startVideoEngine(session);
      // Only now is there audio. On Android this is what moves the Telecom
      // connection out of RINGING/DIALING — without it the system UI shows a
      // call that rings forever and the connection leaks.
      callIntegration.reportCallConnected(session.callIdHex);
      onCallAccepted?.call(session.toCallInfo());
      onStateChanged?.call();
    };
    callManager.onCallRejected = (session, reason) {
      // Same justification as with onCallEnded: every teardown path must stop the
      // tone, regardless of which entry it came through.
      onCancelCallNotificationAndroid?.call();
      try {
        notificationSound.stopRingtone();
      } catch (_) {}
      _stopVoiceSession();
      _stopVideoEngine();
      callIntegration.endCall(session.callIdHex);
      onCallRejected?.call(session.toCallInfo(), reason);
      onStateChanged?.call();
    };
    callManager.onCallEnded = (session) {
      // A-3 (2nd half): the ringtone MUST stop here, not only in the
      // user-initiated wrappers and the three wire handlers. The
      // 60 s ringing timeout calls `CallManager.rejectCall('timeout')` directly
      // on the manager and thus runs past `CallService.rejectCall()` —
      // that is where the stopRingtone() stands. Without this line the callback
      // does fire (A-3, 1st half), clears voice/video/telecom and leaves the
      // tone running: exactly the field symptom from MIGRATION §5.4.
      // Idempotent — stops a non-running loop without consequence.
      onCancelCallNotificationAndroid?.call();
      try {
        notificationSound.stopRingtone();
      } catch (_) {}
      _stopVoiceSession();
      _stopVideoEngine();
      // Unconditional: a locally ended call that is not reported leaves the OS
      // believing a call is still running.
      callIntegration.endCall(session.callIdHex);
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

    // The loss of the media path comes via the plane D API (§17.4: "10 s
    // without valid media frames end the session").
    //
    // **NOBODY FIRES THIS TODAY.** The 10 s loss rule is not
    // built — `DSession.lastFrameAt` (`d_socket.dart:87`) is the quantity
    // it would read, and it has no reader in `lib/`. The callback
    // stands here nonetheless and not set aside as an empty lambda: it is the
    // place where the call belongs to be ended as soon as the rule is built.
    callTransport.onMediaPathLost = (peerHex) {
      final call = callManager.currentCall;
      if (call == null || call.peerNodeIdHex != peerHex) return;
      _log.warn('Plane D: media path to ${peerHex.substring(0, 8)} lost '
          '(§17.4) — call is being ended');
      callManager.hangup();
    };

    // The receive side of plane D (§17.1). A D-frame carries its
    // sequence number INSIDE the AEAD (`kind ‖ seq ‖ len`), and its
    // payload is the raw Opus frame — the encryption IS the AEAD
    // under the `call_key`. That is why nothing goes through a second
    // decryption here any more, unlike in `handleCallAudioV3`.
    callTransport.onMediaFrame = (peerHex, frame) {
      final call = callManager.currentCall;
      if (call == null || call.peerNodeIdHex != peerHex) {
        // ── THIS BRANCH WAS MISSING UNTIL S368 (05.09.2026) ────────────
        //
        // Here stood `return` — and thereby EVERY group frame fell away
        // silently, because `callManager.currentCall` is `null` in the
        // group call. The group path hung completely on the
        // `HarvestEvent` path of the delivery layer; a plane D frame
        // never reached it, no matter whether a session would have carried it.
        // The second half-sentence of the S368 finding "group calls deliver
        // NOTHING today": the RECEIVE SIDE was not wired either.
        groupCallManager.handleGroupMediaFrame(peerHex, frame);
        return;
      }
      switch (frame.kind) {
        case DFrameKind.voice:
          call.framesReceived++;
          _jitterBuffer?.push(
              AudioFrame(seqNum: frame.seq, data: frame.payload));
          _drainPlayback();
        case DFrameKind.video:
          call.videoFramesReceived++;
          _feedVideoFrame(frame.payload);
        case DFrameKind.stream:
          // §17.6 is the media stream lane, not the call. A
          // stream block has no business in a call session.
          _log.debug('Layer D: stream block in a call session of '
              '${peerHex.substring(0, 8)} — discarded (§17.6)');
        case DFrameKind.punch:
          // DOES NOT REACH THIS BRANCH, and the branch stands here nonetheless.
          // `CallTransportV41` sifts out probes before [onMediaFrame] — they
          // have already done their work when `DSession._deliver` made
          // the carrying path from their origin (§17.3). The branch is
          // the assurance that a DIFFERENT transport version does not
          // accidentally put them into the JitterBuffer as speech; a
          // `default` would have done exactly that.
          _log.debug('Plane D: probe from ${peerHex.substring(0, 8)} passed through into '
              'the media layer — discarded (§17.3)');
        case DFrameKind.pathChallenge:
        case DFrameKind.pathResponse:
          // DOES NOT REACH THIS BRANCH EITHER, for the same reason as
          // the probe: `CallTransportV41` sifts out path validation before
          // [onMediaFrame]. Its work is done before it would arrive
          // here — `DSession._deliver` has challenged or
          // answered (§17.4 + RFC 9000 §8.2). The branch stands here because
          // the `switch` has no `default`: it demanded exactly this
          // decision of S377, instead of silently putting the two new kinds
          // into the JitterBuffer as speech.
          _log.debug('Plane D: path validation from '
              '${peerHex.substring(0, 8)} passed through into the media layer '
              '— discarded (§17.4)');
        case DFrameKind.control:
          // DOES NOT REACH THIS BRANCH — the same assurance as with
          // `punch` one line above. `CallTransportV41` diverts
          // control frames before [onMediaFrame] to [onControlRecord]
          // (§17.1.1: "It is **not** a media frame — it carries no media
          // and is never handed to a codec"). The branch stands here so that
          // a DIFFERENT transport version does not put a control frame into the
          // JitterBuffer as speech; a `default` would have done exactly
          // that.
          _log.debug('Plane D: control frame from ${peerHex.substring(0, 8)} '
              'passed through into the media layer — discarded '
              '(§17.1.1)');
      }
    };

    groupCallManager = GroupCallManager(
      identity: _ctx.identity,
      transport: callTransport,
      contacts: _ctx.contacts,
      getGroups: () => _ctx.groups,
      profileDir: _ctx.profileDir,
      uploadProbe: uploadProbe,
    );
    // §17.1.1: the control plane of the group call. It hangs here and
    // not on the 1:1 call, because only there does it have something to say —
    // tree assignment, speech level, readiness and RTT are information
    // about a GROUP. Set only after the manager has been built: a
    // control frame that arrived before it would have no recipient.
    callTransport.onControlRecord = groupCallManager.handleControlRecord;

    groupCallManager.sendViaUser = (recipientUserId, type, payload) =>
        _ctx.sendToUser(
          recipientUserId: recipientUserId,
          messageType: type,
          payload: payload,
          skipL3: true,
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
      if (state == ParticipantState.joined) {
        // Participant indicator tone: join beep
        try { notificationSound.playParticipantJoined(); } catch (_) {}
      } else if (state == ParticipantState.left ||
          state == ParticipantState.crashed) {
        // Participant indicator tone: leave beep
        try { notificationSound.playParticipantLeft(); } catch (_) {}
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
    groupCallManager.onScreenSharePresetChanged = (preset) {
      _applyScreenSharePreset(preset);
    };
    // ── THE WAY BACK INTO PLAYBACK (S369) ──────────────────────────
    //
    // Until now a group media frame from plane D ended in
    // forwarding. Only what came via the DELIVERY LAYER was played
    // (`handleCallGroupAudioV3`) — and exactly this path does not exist in V4.1:
    // §17.1, "media does **not** run in delivery cells". A node
    // thus forwarded for its children and heard nothing itself.
    groupCallManager.onGroupMediaBody = (senderHex, kind, body) {
      switch (kind) {
        case DFrameKind.video:
          _groupVideoReceiver?.addFrame(senderHex, Uint8List.fromList(body));
        case DFrameKind.voice:
          _audioMixer?.addFrame(senderHex, Uint8List.fromList(body));
        case DFrameKind.stream:
        case DFrameKind.punch:
        case DFrameKind.control:
        case DFrameKind.pathChallenge:
        case DFrameKind.pathResponse:
          // Does not reach this way back — `handleGroupMediaFrame` is
          // only called for voice and video frames. The branch stands here
          // so that a new kind does not silently land in the mixer as sound;
          // a `default` would have done exactly that.
          _log.debug('Group media: ${kind.name} on the playback path from '
              '${senderHex.substring(0, 8)} — discarded');
      }
    };
  }

  Future<void> dispose() async {
    _stopAudioMixer();
    _stopGroupVideo();
    if (callManager.currentCall != null) {
      await callManager.hangup();
    }
    await groupCallManager.leaveGroupCall();
  }

  /// Can plane D carry media at all today (§17)?
  ///
  /// ── WHY THE QUESTION STANDS BEFORE THE INVITE AND NOT AFTER ──────────
  ///
  /// The signalling runs via the delivery layer (§17.2) and
  /// works. The media run via plane D (§17.1) and do not
  /// today: there is nobody who admits a plane D session
  /// (§17.3 punch window unbuilt, `LinkDemux.dAdmission` not set in `lib/`).
  /// Without this gate the INVITE would go out, the
  /// peer's device would ring, both pick up — and then nobody hears
  /// anything. A call that looks established and is silent is the
  /// worst version of all: it costs the peer a real
  /// reach for the device and delivers no hint of what is missing.
  ///
  /// The refusal is therefore LOUD: an `error` line with the reason,
  /// plus [onCallUnavailable]. No `false` without a name.
  bool _mediaCarrierReady(String what) {
    final reason = callTransport.mediaUnavailableReason;
    if (reason == null) return true;
    _log.error('$what rejected — Layer D carries no media: $reason');
    onCallUnavailable?.call(reason);
    return false;
  }

  // ── 1:1 Calls ──────────────────────────────────────────────────────

  CallInfo? get currentCall => callManager.currentCall?.toCallInfo();

  Future<CallInfo?> startCall(String peerNodeIdHex, {bool video = false}) async {
    if (groupCallManager.currentGroupCall != null) return null;
    if (!_mediaCarrierReady('1:1-Anruf')) return null;
    // §17.2: NO ringback tone here.
    //
    // Previously at this place stood `notificationSound.playRingback()`, with
    // the justification that the crypto pipeline (KEM + ML-DSA + PoW, 1-3 s on
    // the phone) must not delay the tone. That produced exactly what
    // §17.2, lines 5409-5413 rules out: "After placing the INVITE,
    // the caller shows ,reaching …' — **no** ringtone. Ringtone and the
    // 60-s answer timeout start only once the callee's `RING_ACK` cell has
    // been harvested … This means there is no fake ringing against a device
    // that was never reached."
    //
    // The tone now starts in [onRemoteRinging] (wired in the
    // constructor) as soon as the first RING_ACK has been harvested.
    //
    // **What is still missing here lies outside this work package:** the
    // visible display "reaching …". It needs a `CallState.reaching`
    // in `service_types.dart`, an i18n key in all 34 locales and
    // the display in `call_screen.dart` — three foreign files. Until then
    // the user sees the existing state and hears nothing until it
    // really rings.
    final session = await callManager.startCall(peerNodeIdHex, video: video);
    if (session == null) {
      return null;
    }
    // §10.4 stage 7: only after the invite actually went out — reporting an
    // outgoing call that then fails to start would leave a dialing entry in
    // the system UI with nothing to end it.
    callIntegration.reportOutgoingCall(
      callId: session.callIdHex,
      displayName: _displayNameFor(session),
      hasVideo: session.isVideo,
    );
    return session.toCallInfo();
  }

  Future<void> acceptCall() async {
    onCancelCallNotificationAndroid?.call();
    await notificationSound.stopRingtone();
    // The same gate as with [startCall], and it is NOT
    // superfluous here: the caller can run an older version in which
    // the media still ran differently. Accepting and then staying silent would be the
    // worst answer. Instead the regular refusal with reason —
    // §17.2 provides it as an ordinary cell, and the caller sees
    // "refused" instead of endless "ringing".
    if (!_mediaCarrierReady('Anrufannahme')) {
      await callManager.rejectCall(reason: 'media-unavailable');
      return;
    }
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
    return _voiceSession?.micMuted ?? false;
  }

  void toggleMute() {
    if (_audioMixer != null) {
      _audioMixer!.muted = !_audioMixer!.isMuted;
    } else if (_voiceSession != null) {
      _voiceSession!.micMuted = !_voiceSession!.micMuted;
    }
  }

  bool get isSpeakerEnabled {
    if (_audioMixer != null) return _audioMixer!.isSpeakerEnabled;
    return _speakerEnabled;
  }

  void toggleSpeaker() {
    if (_audioMixer != null) {
      _audioMixer!.speakerEnabled = !_audioMixer!.isSpeakerEnabled;
    } else if (_voiceSession != null) {
      _speakerEnabled = !_speakerEnabled;
      final route =
          _speakerEnabled ? VoiceRoute.speaker : VoiceRoute.earpiece;
      final rc = _voiceSession!.setRoute(route);
      if (rc < 0) {
        _log.debug('setRoute(${route.logName}) returned $rc');
      }
    }
  }

  // ── Group Calls ─────────────────────────────────────────────────

  GroupCallInfo? get currentGroupCall =>
      groupCallManager.currentGroupCall?.toGroupCallInfo();

  Future<GroupCallInfo?> startGroupCall(String groupIdHex) async {
    if (callManager.currentCall != null) return null;
    if (!_mediaCarrierReady('Gruppenanruf')) return null;
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

  Future<void> rejoinGroupCall() async {
    await groupCallManager.rejoinGroupCall();
    final session = groupCallManager.currentGroupCall;
    if (session != null && session.state == GroupCallState.inCall) {
      await _startAudioMixer(session);
      await _startGroupVideo(session);
    }
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
      _audioMixer!.onSpeakerToggle = (speaker) {
        onSetCallAudioModeAndroid?.call(speaker);
      };
      // Mode before stream-open — see _startVoiceSession for the rationale.
      onSetCallAudioModeAndroid?.call(true);
      await _audioMixer!.start();
      // Poll audio levels at 4 Hz for active speaker detection + mute inference.
      _audioLevelTimer?.cancel();
      _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final mixer = _audioMixer;
        if (mixer == null || !mixer.isRunning) return;
        final levels = mixer.peerAudioLevels;
        for (final entry in levels.entries) {
          groupCallManager.updateParticipantAudioLevel(entry.key, entry.value);
          // Infer mute: sustained silence (level < 0.001) across consecutive polls.
          groupCallManager.updateParticipantMuteState(entry.key, entry.value < 0.001);
        }
      });
    } catch (e) {
      _log.error('Audio mixer start failed: $e');
    }
  }

  void _stopAudioMixer() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
    try {
      _audioMixer?.stop();
    } catch (e) {
      _log.warn('AudioMixer stop threw (swallowed): $e');
    }
    _audioMixer = null;
    onResetCallAudioModeAndroid?.call();
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
    _groupVideoReceiver!.onPeerTexture = (senderHex, textureId) {
      onGroupVideoTexture?.call(senderHex, textureId);
    };
    // A peer's decoder that has lost its keyframe cannot recover on its own —
    // asking the sender is signalling, which the video ABI deliberately does
    // not do. Reuses the 1:1 keyframe request path.
    _groupVideoReceiver!.onKeyframeNeeded = (_) => onKeyframeRequested?.call();
  }

  void _applyScreenSharePreset(ScreenSharePreset? preset) {
    final engine = _groupVideoEngine;
    if (engine == null) return;

    try {
      if (preset != null) {
        (engine as dynamic).reconfigureForScreenShare(
            preset.width, preset.height, preset.fps, preset.bitrateKbps);
      } else {
        (engine as dynamic).restoreCameraDefaults();
      }
    } catch (e) {
      _log.debug('Screen share reconfigure skipped (engine has no support): $e');
    }
  }

  void _stopGroupVideo() {
    try {
      (_groupVideoEngine as dynamic)?.stop();
    } catch (_) {}
    _groupVideoEngine = null;
    _groupVideoReceiver?.dispose();
    _groupVideoReceiver = null;
  }

  // ── Voice Session (1:1) ───────────────────────────────────────────

  Future<void> _startVoiceSession(CallSession session) async {
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
      final lib = VoiceNativeLibrary.platform();
      final voiceSession = VoiceSession.open(library: lib);
      final format = voiceSession.format;

      _voiceSession = voiceSession;
      _captureCodec = VoiceCodec.fromFormat(format);
      _playbackCodec = VoiceCodec.fromFormat(format);
      _captureBuf = Int16List(format.frameSamples);
      _jitterBuffer = JitterBuffer(bufferDepth: 2, maxBufferSize: 6);
      _speakerEnabled = true;

      onSetCallAudioModeAndroid?.call(true);
      voiceSession.start();

      // S367: RoutePolicy (architecture §10.4) had no caller — it computed
      // decisions nobody applied. Constructed right after start() so the
      // dispatcher's initial RoutePolicy reads the route set the session is
      // actually live with, not a pre-start snapshot.
      final dispatcher = VoiceEventDispatcher.forSession(voiceSession);
      _voiceEventDispatcher = dispatcher;

      // §10.4 "Session behaviour" (V1.10, S367): proximity monitoring must
      // track the active route "at call start and after every RoutePolicy
      // decision" (session_behaviour_channel.dart) — the initial state has
      // no RoutePolicy decision to hang off of, so it is set explicitly here.
      onSetProximityMonitoring
          ?.call(shouldMonitorProximity(dispatcher.routePolicy.activeRoute));
      dispatcher.onRouteDecision = (decision) =>
          onSetProximityMonitoring?.call(shouldMonitorProximity(decision.route));
      dispatcher.onSessionBehaviourAction = (action) =>
          onCallInterruptionChanged?.call(dispatcher.sessionBehaviour.isInterrupted);

      // Claim OS audio-session priority (AudioFocus/AVAudioSession) for the
      // call — best-effort, never load-bearing (see onRequestAudioFocus'
      // field doc): a call must connect and carry audio even where no
      // platform bridge is wired (daemon, Linux, Windows).
      unawaited(onRequestAudioFocus?.call());

      _captureTimer =
          Timer.periodic(const Duration(milliseconds: 5), (_) {
        _captureAndSend(session);
      });

      _log.info('Voice session started (rate=${format.sampleRate}, '
          'channels=${format.channels}, frame=${format.frameSamples})');
    } catch (e) {
      _log.error('Voice session start failed: $e');
      _stopVoiceSession();
    }
  }

  void _captureAndSend(CallSession session) {
    final vs = _voiceSession;
    if (vs == null) return;

    // S367: drains VoiceSession.pollEvent() and applies RoutePolicy's route
    // switches — see VoiceEventDispatcher's file doc for why this belongs on
    // the existing capture tick rather than a new timer (I5). A backend
    // rejecting a route switch (VoiceSessionException) must not take the
    // capture tick down with it — the call keeps running on whatever route
    // was already active.
    try {
      _voiceEventDispatcher?.pump(vs);
    } catch (e) {
      _log.debug('Voice event dispatch failed: $e');
    }

    final status = vs.readCaptureFrameInto(_captureBuf!, timeoutMs: 0);
    if (status != VoiceCaptureStatus.frame) return;

    try {
      final pcmBytes = _captureBuf!.buffer.asUint8List(
          _captureBuf!.offsetInBytes, _captureBuf!.lengthInBytes);
      final opusData = _captureCodec!.encode(pcmBytes);

      // RAW OPUS FRAME. §17.1 calculates the voice class exactly like this: "70 B
      // of payload per frame" plus 43 B D overhead — "cookie 8 + nonce 12 +
      // AEAD tag 16 + inner header 7 (`kind ‖ seq ‖ len`)" — gives 113 B
      // unpadded. The class has measured 176 B with 133 B
      // payload since 06.09.2026 (160/117 on 05.09., before that 128/85) — the measured
      // worst Opus frame of 91-95 B thus fits completely,
      // which did not hold at 85 B.
      //
      // Until the CUT an OWN layer stood here: `seq(4) ‖ nonce(12) ‖
      // AES-GCM(opus)` under the same key. It is duplicated with the
      // D-frame — whose AEAD runs under exactly this
      // `call_key`, and whose inner header carries exactly this
      // sequence number. Recalculated, it cost 32 B: 70 + 32 = 102 B against
      // the then 85 B capacity — the voice class would NEVER have
      // held, and the frame would have been discarded as `tooLarge` on every recording.
      // With 133 B it would fit arithmetically today; it
      // stays removed nonetheless, because it is duplicated and not because it
      // was too large.
      _sendAudioFrame(session, opusData);
    } catch (e) {
      _log.debug('Capture encode/encrypt failed: $e');
    }
  }

  void _stopVoiceSession() {
    _captureTimer?.cancel();
    _captureTimer = null;

    try {
      _voiceSession?.stop();
      _voiceSession?.close();
    } catch (e) {
      _log.warn('VoiceSession stop/close threw (swallowed): $e');
    }

    _voiceSession = null;
    _voiceEventDispatcher = null;
    _captureCodec?.dispose();
    _captureCodec = null;
    _playbackCodec?.dispose();
    _playbackCodec = null;
    _captureBuf = null;
    _jitterBuffer = null;

    onResetCallAudioModeAndroid?.call();
    // §10.4 "Session behaviour" (S367): release what onRequestAudioFocus
    // claimed. Never from an interruption handler (see that field's doc) —
    // only here, at hangup, mirroring SessionBehaviourChannel.abandonAudioFocus's
    // own contract. Proximity monitoring is switched off with the same call
    // a platform bridge already exposes for "disabled".
    unawaited(onAbandonAudioFocus?.call());
    onSetProximityMonitoring?.call(false);
    if (Platform.isAndroid) {
      ForegroundServiceControl.demoteAfterCall();
    }
  }

  // ── Video Engine (1:1) ────────────────────────────────────────────

  /// Starts the 1:1 video pipeline for a video call once it reaches
  /// [CallState.inCall] (mirrors [_startVoiceSession], called from the same
  /// `onCallAccepted` hook so both caller-on-answer and callee-on-accept
  /// wire up identically). No-op for audio-only calls or when no video
  /// engine factory has been injected (daemon builds without a
  /// Flutter context, or platforms where camera capture is out of scope).
  Future<void> _startVideoEngine(CallSession session) async {
    if (!session.isVideo) return;
    if (session.sharedSecret == null) return;
    if (createVideoEngine == null) {
      _log.debug('Video call requested but no video engine factory wired '
          '— continuing audio-only');
      onVideoUnavailable?.call('Video not available (no video engine)');
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
      onVideoUnavailable?.call('Video not available (codec error)');
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

  /// The one place where a 1:1 media frame leaves the service
  /// (§17.1).
  ///
  /// **Plane D, and nothing else.** Until the CUT a case distinction stood here:
  /// if a `peerDeviceId` was present, the frame went
  /// device-addressed via the V3 transport, otherwise via
  /// `ServiceContext.sendToUser`. Both branches have fallen, and the
  /// second is the more important loss: on the V4.1 line —
  /// where `peerDeviceId` is ALWAYS `null` according to §14.2 — it would have put every single one of the
  /// 50 voice frames per second into the cover stream. With `m x R`
  /// control frames per store and a drain of one cell every 8 s
  /// (B-13) that would not have been a call, but a clogging of the
  /// delivery layer. §17.1 says it directly: "Media does **not** run in
  /// delivery cells."
  ///
  /// [payload] goes in as PLAINTEXT. The encryption is the AEAD
  /// of the D-frame under the `call_key` (§17.1: "AES-256-GCM under
  /// `call_key` … the AEAD under `call_key` provides per-frame
  /// authenticity"), and the sequence number is the inner `seq` of the frame.
  /// Keeping both twice costs 30 B per frame. Against the then
  /// 85 B that burst the class; since 06.09.2026 it carries 133 B and
  /// it would "only" be waste. The reason for leaving it out is
  /// the duplication, not the size.
  void sendLiveMediaFrame({
    required CallSession session,
    required proto.MessageTypeV3 messageType,
    required Uint8List payload,
  }) {
    if (session.state == CallState.ended) return;
    final failure = callTransport.sendMedia(
      peerHex: session.peerNodeIdHex,
      kind: messageType == proto.MessageTypeV3.MTV3_CALL_VIDEO
          ? DFrameKind.video
          : DFrameKind.voice,
      payload: payload,
    );
    if (failure == null) {
      // S368 task 2: the only place where this node has provably pushed
      // something up in a 1:1 call. Counted is the
      // wire length of the size class (§17.1: 176 B voice, 1200 B
      // stream), not the payload — a 12 B Opus frame costs the same
      // 176 B as a full one, and counting the payload would let the
      // measured upload collapse in every speech pause. The number stands
      // here only in the comment; counted is `frameClass.wireSize`.
      uploadProbe.recordSent(
        (messageType == proto.MessageTypeV3.MTV3_CALL_VIDEO
                ? DFrameKind.video
                : DFrameKind.voice)
            .frameClass
            .wireSize,
      );
      return;
    }
    // 50 frames/s: a log line per frame would itself be the damage.
    // Reported is the FIRST failure per call, loudly, with reason.
    if (!session.mediaFailureLogged) {
      session.mediaFailureLogged = true;
      _log.error('Layer D: ${messageType.name} to '
          '${session.peerNodeIdHex.substring(0, 8)} not deliverable '
          '(${failure.name}) — ${callTransport.mediaUnavailableReason ?? "—"}'
          '. Further frames of this call are silently discarded.');
    }
  }

  void _sendAudioFrame(CallSession session, Uint8List opusFrame) {
    session.framesSent++;
    sendLiveMediaFrame(
      session: session,
      messageType: proto.MessageTypeV3.MTV3_CALL_AUDIO,
      payload: opusFrame,
    );
  }

  /// Is [senderDeviceId] the device of the peer of a running
  /// call?
  ///
  /// **On the V4.1 line ALWAYS `false`, and that is right.** The path
  /// this gate protected was the V3 fast path for media from
  /// a cell; §17.1 carries media exclusively via plane D, and
  /// there the admission is a different one: "a valid AEAD under `call_key`
  /// plus a session cookie … Whoever does not have the `call_key` from
  /// signaling does not exist for the socket" (§17.4). `peerDeviceId` is
  /// moreover always `null` according to §14.2 (B-32).
  ///
  /// The method stays because `cleona_service_receive.dart:54` calls it.
  /// It returns `false` instead of being left out — a gate that lets nothing
  /// through is not a hole.
  bool isLiveMediaSender(Uint8List senderDeviceId) {
    final call = callManager.currentCall;
    if (call != null &&
        call.state == CallState.inCall &&
        call.peerDeviceId != null &&
        bytesToHex(call.peerDeviceId!) == bytesToHex(senderDeviceId)) {
      return true;
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
  void _sendVideoFrame(CallSession session, Uint8List videoFrame) {
    session.videoFramesSent++;
    sendLiveMediaFrame(
      session: session,
      messageType: proto.MessageTypeV3.MTV3_CALL_VIDEO,
      payload: videoFrame,
    );
  }

  void sendKeyframeRequest() {
    final session = callManager.currentCall;
    if (session == null || session.state != CallState.inCall) return;
    // DETACHED, BUT OBSERVED: the same class as in
    // `CleonaService._detachedSend`. `sendToUser` is `async` and therefore
    // NEVER throws synchronously — every throw lands in this discarded
    // `Future` and from there in the zone of `service_daemon.dart`
    // (~L424), which answers everything outside its survival list with `exit(99)`.
    // An undeliverable keyframe request must not kill a
    // daemon.
    _ctx
        .sendToUser(
          recipientUserId: hexToBytes(session.peerNodeIdHex),
          messageType: proto.MessageTypeV3.MTV3_CALL_KEYFRAME_REQUEST,
          payload: Uint8List(0),
        )
        .catchError((Object e, StackTrace st) {
      _log.error('CALL_KEYFRAME_REQUEST threw (detached): $e\n$st');
      return false;
    });
  }

  // ── V3 Handlers ─────────────────────────────────────────────────

  // ── §10.4 / erratum E5: version gate on CALL_INVITE ────────────────

  /// Wire reason code sent in [proto.CallReject.reason] when an invite is
  /// refused by the version gate.
  ///
  /// A stable code, not a sentence: `call_service.dart` is daemon-safe and
  /// must not import `dart:ui`, so it cannot localise — and localising on
  /// the sender would ship the CALLEE's language to the CALLER. The UI maps
  /// this code onto the i18n key `call_rejected_incompatible_version`,
  /// which carries all 34 locales.
  static const String rejectReasonIncompatibleVersion =
      'incompatible_version';

  /// The OWN version as `major * 1000 + minor`, derived from the
  /// only source in the tree.
  ///
  /// **Derived, not typed in** — and that is the core of the S368 fix.
  /// `CleonaService.kCurrentAppVersion` is the one place where the version
  /// stands (`pubspec.yaml` holds the same value, `scripts/preflight.sh`
  /// check 1 holds both against each other). A handwritten number next to it is
  /// exactly the path by which the 3002 got into the wrong place.
  ///
  /// Encoding as described in `app_payloads.proto`: 3.1.x -> 3001,
  /// 3.2.0 -> 3002, 4.0.0 -> 4000, 4.1.0 -> 4001. The patch digit is
  /// deliberately NOT included: 4.1.0 and 4.1.1 are the same line and must
  /// be able to phone each other.
  /// No own calculation: `kAppMajorMinor` from `app_version.dart` IS the
  /// derived number. A second derivation here would again be a second
  /// source.
  static int get ownAppMajorMinor => kAppMajorMinor;

  /// Does a peer that advertises [callerAppMajorMinor] speak THE SAME
  /// line?
  ///
  /// ── WHY EQUALITY STANDS HERE AND NO LONGER `>=` (S368) ──────────
  ///
  /// Until S368 the rule was `callerAppMajorMinor >= 3002`. Both have
  /// fallen, and for two different reasons:
  ///
  /// **The number.** 3002 was the smallest accepted version, decided
  /// by the owner on 2026-07-30 (formerly `BUILD_REQUEST_V1.12.md`, today
  /// `BUGFIX_CURRENT.md AV-V1.12`, "decision of the project owner"), when
  /// 3.2.x was the current line. The decision
  /// has not been bypassed, but has **become moot**: it governed
  /// which OLDER peer may still take part, and older peers
  /// no longer exist on this line (owner, 05.09.2026: "V3 no longer exists in
  /// V4.1 and there is no backward compatibility or
  /// migration!", "No interoperability with a V3 node").
  ///
  /// **The form.** `>=` was built for a world in which there are older AND
  /// newer peers. It has a defect that
  /// `media_format_version.dart:19` itself names: a state with a
  /// concreted-in lower bound "thus takes every future version"
  /// unchecked. A 4.1 node with `>= 4001` would thus accept a
  /// 5.0 node about whose voice stack it knows nothing —
  /// the same error one generation later.
  ///
  /// (Here it said "before its removal". This file is NOT removed:
  /// the deletion from P-2 was measured against the branch point and has been
  /// reverted, because `call_manager.dart` has wired it on the target state since
  /// S367.)
  ///
  /// Hence equality: **V4.1 talks to V4.1.** The patch digit is not contained in
  /// the encoding, 4.1.0 and 4.1.9 are the same value.
  ///
  /// **Price, named:** a future 4.2 can no longer call a 4.1,
  /// and vice versa. That is intended — two lines that do not
  /// know each other —, but it means that a version jump needs both sides
  /// at the same time. Whoever wants to loosen that changes it here and nowhere
  /// else.
  ///
  /// `0` — the proto3 default value of a missing field — thus
  /// also falls through, and without a special case.
  static bool isCompatibleCallerVersion(int callerAppMajorMinor) =>
      callerAppMajorMinor == ownAppMajorMinor;

  /// Refuse an invite from an incompatible build.
  ///
  /// Mirrors [CallManager.rejectCall]'s wire signal, but deliberately does
  /// not go through it: no [CallSession] is ever created for this invite, so
  /// there is nothing to tear down, and `rejectCall` would no-op on a null
  /// `_currentCall`. Local teardown first, wire signal best-effort second —
  /// same ordering as the rest of the call teardown paths.
  void _rejectIncompatibleCallInvite(proto.CallInvite invite, HarvestEvent event) {
    final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
    _log.warn('CALL_INVITE rejected — incompatible caller version '
        '${invite.callerAppMajorMinor} (need == $ownAppMajorMinor) '
        'from ${senderHex.substring(0, 8)} (§10.4 / E5)');

    // Surface it locally too. The callee gets no ringtone and no call entry,
    // so without this the refusal would be invisible on THIS device as well
    // — the same silent failure, just on the other end.
    onIncompatibleCallRejected?.call(
        senderHex, invite.callerAppMajorMinor, rejectReasonIncompatibleVersion);

    try {
      final reject = proto.CallReject()
        ..callId = invite.callId
        ..reason = rejectReasonIncompatibleVersion;
      // A-1 (S352): this `try` is synchronous — it catches an error while
      // building `reject` (which practically never occurs here), but NEVER a
      // throw from `sendToUser`, because `async` functions never throw synchronously.
      // `.catchError` on the `Future` itself is the only place that reaches the
      // actual error channel.
      _ctx
          .sendToUser(
            recipientUserId: Uint8List.fromList(event.senderUserId),
            messageType: proto.MessageTypeV3.MTV3_CALL_REJECT,
            payload: reject.writeToBuffer(),
            skipL3: true,
          )
          .catchError((Object e, StackTrace st) {
        _log.error(
            'Incompatible-version reject signal threw (detached): $e\n$st');
        return false;
      });
    } catch (e) {
      _log.warn('Incompatible-version reject signal failed to send: $e');
    }
  }

  void handleCallInviteV3(HarvestEvent event) {
    // `claimedSentAt` is the unverified sender statement (V4 §15.5.3). The
    // factory maps `timestampMs == 0` to null; the old version computed
    // against 0 in that case, which gave a huge age and discarded the invite as
    // stale. The `?? 0` records exactly that.
    final ageMs = DateTime.now().millisecondsSinceEpoch -
        (event.claimedSentAt?.millisecondsSinceEpoch ?? 0);
    if (ageMs > 60000) {
      _log.info('Stale CALL_INVITE (${(ageMs / 1000).toStringAsFixed(0)}s old) '
          'from ${bytesToHex(Uint8List.fromList(event.senderUserId)).substring(0, 8)} '
          '— discarded (S&F ghost prevention)');
      return;
    }
    proto.CallInvite invite;
    try {
      invite = proto.CallInvite.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('CALL_INVITE V3: payload parse failed: $e');
      return;
    }
    // §10.4 / Erratum E5 — version gate. A call between an old and a new
    // voice stack must be rejected EXPLICITLY, with a reason the user can
    // see: "never allowed to fail silently, which would reproduce exactly
    // the field symptoms this rewrite removes". Checked before anything
    // rings, so an incompatible caller never produces a call the callee
    // could pick up into silence.
    if (!isCompatibleCallerVersion(invite.callerAppMajorMinor)) {
      _rejectIncompatibleCallInvite(invite, event);
      return;
    }
    // A-4: the handler reports whether this INVITE created a NEW ringing call.
    // Previously it was `void` and everything below ran
    // unconditionally — also for the repetition of the same INVITE (the
    // sender repeats every 3 s) and for a call we are just refusing because of
    // busy.
    final ringing = invite.isGroupCall
        ? groupCallManager.handleGroupCallInviteV3(event)
        : callManager.handleCallInviteV3(event);
    if (!ringing) return;

    notificationSound.startRingtone();
    notificationSound.vibrate(VibrationType.call);
    if (Platform.isAndroid) {
      final senderHex = bytesToHex(Uint8List.fromList(event.senderUserId));
      final contact = _ctx.contacts[senderHex];
      final callerName = contact?.displayName ?? senderHex.substring(0, 8);
      // The `return` above stands deliberately BEFORE this block, not only before the
      // ringtone: on the busy path `currentCall` is the EXISTING
      // call, the telecom notification was thus posted with the callId of the
      // running conversation and the name of the refused caller.
      final callId = callManager.currentCall?.callIdHex ?? '';
      onPostCallNotificationAndroid?.call(callerName, callId);
    }
  }

  void handleCallAnswerV3(HarvestEvent event) {
    onCancelCallNotificationAndroid?.call();
    try { notificationSound.stopRingtone(); } catch (_) {}
    try { notificationSound.stopRingback(); } catch (_) {}
    try { notificationSound.playConnected(); } catch (_) {}
    if (groupCallManager.currentGroupCall != null) {
      groupCallManager.handleGroupCallAnswerV3(event);
    } else {
      callManager.handleCallAnswerV3(event);
    }
  }

  void handleCallRejectV3(HarvestEvent event) {
    onCancelCallNotificationAndroid?.call();
    try { notificationSound.stopRingtone(); } catch (_) {}
    try { notificationSound.stopRingback(); } catch (_) {}
    if (groupCallManager.currentGroupCall != null) {
      groupCallManager.handleGroupCallRejectV3(event);
    } else {
      callManager.handleCallRejectV3(event);
    }
  }

  /// CANCEL_OTHERS (§17.2) — the caller's arbitration.
  ///
  /// **Deliberately WITHOUT the `onCancelCallNotificationAndroid` / `stopRingtone` /
  /// `stopRingback` prelude of the three neighbours.** The reason is the
  /// difference that justifies the own message type at all:
  /// a refusal ends the call for the whole identity, an
  /// arbitration spares exactly one device. The cell reaches via the
  /// tag of the identity ALSO the device that has just picked up (§14.2)
  /// — on it this entry point must clear nothing.
  ///
  /// The clearing on the LOSING devices is not lost: there
  /// [CallManager] fires `onCallEnded`, and the callback further up in
  /// this file stops ringtone, voice/video and the
  /// Android notification. The path via the callback is the right one,
  /// because only the manager knows whether this device has won or lost.
  /// RING_ACK (§17.2) — "it really is ringing at theirs".
  ///
  /// Like [handleCallCancelOthersV3] deliberately WITHOUT the
  /// `stopRingtone`/`stopRingback` prelude of the refusal neighbours: here
  /// nothing is ended, here something begins. The ringback tone runs via
  /// [CallManager.onRemoteRinging], so that it only starts the first time.
  void handleCallRingAckV3(HarvestEvent event) {
    callManager.handleCallRingAckV3(event);
  }

  void handleCallCancelOthersV3(HarvestEvent event) {
    if (groupCallManager.currentGroupCall != null) {
      groupCallManager.handleGroupCallCancelOthersV3(event);
    } else {
      callManager.handleCallCancelOthersV3(event);
    }
  }

  void handleCallHangupV3(HarvestEvent event) {
    onCancelCallNotificationAndroid?.call();
    try { notificationSound.stopRingtone(); } catch (_) {}
    try { notificationSound.stopRingback(); } catch (_) {}
    if (groupCallManager.currentGroupCall != null) {
      groupCallManager.handleGroupCallHangupV3(event);
    } else {
      callManager.handleCallHangupV3(event);
    }
  }

  void handleIceCandidateV3(HarvestEvent event) {
    _log.debug('ICE_CANDIDATE V3: not wired yet — drop');
  }

  void handleCallRejoinV3(HarvestEvent event) {
    groupCallManager.handleCallRejoinV3(event);
  }

  /// **Media via the DELIVERY LAYER — that does not exist in V4.1.**
  ///
  /// Same justification as with [handleCallVideoV3]. Until the CUT
  /// the counterpart of the old send path stood here: `seq(4) ‖ nonce(12) ‖
  /// AES-GCM(opus)` from a cell. §17.1 puts both into the D-frame —
  /// `seq` into the inner header, the encryption into the AEAD under the
  /// `call_key` — and the delivery layer no longer carries media.
  void handleCallAudioV3(HarvestEvent event) {
    _log.warn('CALL_AUDIO received via the delivery layer — V4.1 carries '
        'media exclusively via Layer D (§17.1); discarded');
  }

  void _drainPlayback() {
    final vs = _voiceSession;
    final codec = _playbackCodec;
    if (vs == null || codec == null) return;

    for (var frame = _jitterBuffer?.pop();
        frame != null;
        frame = _jitterBuffer?.pop()) {
      try {
        final pcmBytes = codec.decode(frame.data);
        final pcm16 = Int16List.view(
            pcmBytes.buffer, pcmBytes.offsetInBytes, pcmBytes.length ~/ 2);
        vs.writePlaybackFrame(pcm16);
      } catch (e) {
        _log.debug('Audio decode/playback failed: $e');
      }
    }
  }

  /// A video frame into the display and into decoding.
  ///
  /// Extracted so that the plane D path (`onMediaFrame`) and the old
  /// delivery path ([handleCallVideoV3]) have the same body and do not
  /// drift apart.
  void _feedVideoFrame(Uint8List payload) {
    onVideoFrameReceived?.call(payload);
    try {
      (_videoEngine as dynamic)?.processReceivedFrame(payload);
    } catch (e) {
      _log.debug('Video frame decode dispatch failed: $e');
    }
  }

  /// **Media via the DELIVERY LAYER — that does not exist in V4.1.**
  ///
  /// §17.1: media run via plane D, "media does **not** run in
  /// delivery cells". This entry point stays because
  /// `cleona_service_receive.dart` calls it for the message type;
  /// but it no longer accepts anything. A frame that arrives here comes
  /// from a sender that does not send according to §17 — and that should be
  /// seen, not silently processed.
  void handleCallVideoV3(HarvestEvent event) {
    _log.warn('CALL_VIDEO received via the delivery layer — V4.1 carries '
        'media exclusively via Layer D (§17.1); discarded');
  }

  /// **Group media via the DELIVERY LAYER — that does not exist in V4.1.**
  ///
  /// The same situation as with [handleCallVideoV3] next to it, and until S369 the
  /// opposite stood here: the place unpacked a `GroupCallAudio` and
  /// fed the mixer. That was the ONLY path on which group sound ever
  /// reached playback — and §17.1 excludes it ("media does **not**
  /// run in delivery cells"). The path via plane D has been wired since S369
  /// (`GroupCallManager.onGroupMediaBody`); this one no longer accepts anything.
  ///
  /// `GroupCallAudio` is moreover no longer produced — the send path
  /// has packed according to `group_media_frame.dart` since S369. A parser for a
  /// format nobody writes any more would be backward compatibility, and
  /// that does not exist on this line.
  void handleCallGroupAudioV3(HarvestEvent event) {
    _log.warn('CALL_GROUP_AUDIO received via the delivery layer — V4.1 '
        'carries media exclusively via Layer D (§17.1); discarded');
  }

  /// See [handleCallGroupAudioV3] — same reasoning, same consequence.
  void handleCallGroupVideoV3(HarvestEvent event) {
    _log.warn('CALL_GROUP_VIDEO received via the delivery layer — V4.1 '
        'carries media exclusively via Layer D (§17.1); discarded');
  }

  void handleCallGroupLeaveV3(HarvestEvent event) {
    groupCallManager.handleGroupCallLeaveV3(event);
  }

  // S368: `handleCallGroupKeyRotateV3` is removed — see the justification
  // above `handleGroupCallSenderKeyV3` in `group_call_manager.dart`.

  void handleCallRttPingV3(HarvestEvent event) {
    groupCallManager.handleCallRttPingV3(event);
  }

  void handleCallRttPongV3(HarvestEvent event) {
    groupCallManager.handleCallRttPongV3(event);
  }

  void handleCallTreeUpdateV3(HarvestEvent event) {
    groupCallManager.handleCallTreeUpdateV3(event);
  }

  // ── §10.5 In-Call Collaboration ─────────────────────────────────────

  void handleWhiteboardStrokeV3(HarvestEvent event) {
    groupCallManager.handleWhiteboardStrokeV3(event);
  }

  void handleWhiteboardPageV3(HarvestEvent event) {
    groupCallManager.handleWhiteboardPageV3(event);
  }

  void handleFileExchangeV3(HarvestEvent event) {
    groupCallManager.handleFileExchangeV3(event);
  }

  void handleClipboardExchangeV3(HarvestEvent event) {
    groupCallManager.handleClipboardExchangeV3(event);
  }

  void handleScreenShareFrameV3(HarvestEvent event) {
    groupCallManager.handleScreenShareV3(event);
  }

  void handleCallChatV3(HarvestEvent event) {
    groupCallManager.handleCallChatV3(event);
  }

  void handleRemoteControlInputV3(HarvestEvent event) {
    // Remote control not yet implemented (§10.5.4 planned)
  }
}
