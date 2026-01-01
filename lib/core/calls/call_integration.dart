/// `CallIntegration` — system telephony integration for calls
/// (architecture §10.4, staging plan stage 7; work package
/// docs/SPEC_VOICE_VIDEO_REWORK.md V3.2).
///
/// ## What this is
///
/// The Dart-side contract for CallKit (iOS) and the self-managed
/// `ConnectionService` (Android). §10.4 puts this stage last on purpose:
/// "deliberately after the two layers above. Otherwise the call sounds right
/// and behaves wrong."
///
/// ## Why this file has no Flutter import
///
/// `call_service.dart` must stay daemon-safe: `dart compile exe
/// lib/service_daemon.dart` runs without `dart.library.ui`, which is why the
/// video engine there is injected as `dynamic` rather than imported. A
/// `MethodChannel` lives in `package:flutter/services.dart` and therefore
/// pulls in `dart:ui` — importing it from `call_service.dart` breaks the
/// daemon AOT build outright (verified: "Error: AOT compilation failed").
///
/// So the split is the same one the video path already uses: the *contract*
/// and a do-nothing default live here, Flutter-free; the `MethodChannel`
/// implementation lives in `call_integration_channel.dart` and is injected
/// from a Flutter-context caller (`main.dart`). The daemon keeps
/// [NoopCallIntegration] and never links a channel it could not serve anyway
/// — it has no system call UI to integrate with.
///
/// ## I2: this owns no audio
///
/// Like `SessionBehaviour`, nothing here touches a `VoiceSession` or
/// configures an audio device. It reports call *state* to the OS and relays
/// the OS's *intent* back. Muting, routing, mode and the duplex session itself
/// stay with `cleona_voice` (§10.4, I2). Two consequences callers must know
/// rather than discover:
///
///   * [setMuted] does **not** mute the microphone on Android. Telecom has no
///     public API for a self-managed connection to change the system mute
///     state — that is an `InCallService` method and Cleona is not the
///     InCallService. The platform side only records the value so a later
///     system echo is not bounced back as a spurious [onSetMuted]. The actual
///     mute must be applied to the voice session by the caller, on every
///     platform, exactly as before this file existed.
///   * [onSetMuted] is therefore a *request from the OS*, not a confirmation.
///
/// ## Every call is best-effort, and that is deliberate
///
/// Nothing here is load-bearing. A call must connect and carry audio where the
/// integration is unavailable — Linux and Windows have no such concept, and
/// Android below API 26 has no self-managed Telecom (`CAPABILITY_SELF_MANAGED`
/// is API 26+ while the app's `minSdk` is 24). Implementations therefore
/// swallow platform failures and return `false`; they never throw into the
/// call path. A missing system-UI entry is a degraded experience, a thrown
/// exception in `onIncomingCall` would be a dropped call.
library;

/// Method channel name shared with `CallKitHandler.swift` and
/// `CleonaCallIntegration.kt`. It is the serialisation point between the two
/// platform packages — changing it means changing all three files. Declared
/// here rather than in the channel implementation so the constant is visible
/// without pulling in Flutter.
const String kCallIntegrationChannel = 'chat.cleona/call_integration';

abstract class CallIntegration {
  /// The OS asked to answer [callId] (Lock Screen, system call UI, headset).
  void Function(String callId)? onAnswerCall;

  /// The OS ended [callId] (system hang-up, headset button, reject).
  void Function(String callId)? onEndCall;

  /// The OS toggled mute. See the class doc: a request, not a confirmation,
  /// and it does not by itself mute anything.
  void Function(String callId, bool muted)? onSetMuted;

  /// iOS only: CallKit activated the audio session.
  void Function()? onAudioSessionActivated;

  /// iOS only: CallKit deactivated the audio session.
  void Function()? onAudioSessionDeactivated;

  Future<bool> reportIncomingCall(
      {required String callId,
      required String displayName,
      required bool hasVideo});

  Future<bool> reportOutgoingCall(
      {required String callId,
      required String displayName,
      required bool hasVideo});

  /// Moves the system's notion of the call to "connected". On Android this is
  /// what stops the system UI showing a permanently ringing call; without it
  /// the Telecom connection leaks. On iOS it applies to outgoing calls only —
  /// an incoming one counts as connected once the answer action is fulfilled —
  /// and the platform side answers `true` for the incoming case so this stays
  /// platform-neutral for callers.
  Future<bool> reportCallConnected(String callId);

  /// Tears the system-side call down. Must be called for every locally ended
  /// call, or Telecom/CallKit keeps believing a call is running.
  Future<bool> endCall(String callId);

  /// Syncs the mute indicator in the system UI. Does **not** mute — see the
  /// class doc.
  Future<bool> setMuted(String callId, bool muted);

  void dispose();
}

/// The default everywhere no platform half exists: the daemon, Linux, Windows.
/// Answers `false` to everything, which is exactly what a caller must already
/// tolerate from Android below API 26.
class NoopCallIntegration implements CallIntegration {
  @override
  void Function(String callId)? onAnswerCall;
  @override
  void Function(String callId)? onEndCall;
  @override
  void Function(String callId, bool muted)? onSetMuted;
  @override
  void Function()? onAudioSessionActivated;
  @override
  void Function()? onAudioSessionDeactivated;

  @override
  Future<bool> reportIncomingCall(
          {required String callId,
          required String displayName,
          required bool hasVideo}) async =>
      false;

  @override
  Future<bool> reportOutgoingCall(
          {required String callId,
          required String displayName,
          required bool hasVideo}) async =>
      false;

  @override
  Future<bool> reportCallConnected(String callId) async => false;

  @override
  Future<bool> endCall(String callId) async => false;

  @override
  Future<bool> setMuted(String callId, bool muted) async => false;

  @override
  void dispose() {}
}
