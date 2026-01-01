/// `SessionBehaviour` — Android AudioFocus / Apple interruption handling and
/// earpiece-only proximity monitoring for calls (architecture §10.4,
/// "Session behaviour" table; work package
/// docs/SPEC_VOICE_VIDEO_REWORK.md V1.10).
///
/// ## What this is
///
/// §10.4 lists four concerns entirely absent from the superseded stack
/// (defect #8 of the old stack: "Audio focus, interruption handling,
/// proximity and call integration were entirely absent" —
/// `grep 'requestAudioFocus\|AudioFocus\|proximity\|CallKit\|CXProvider\|
/// ConnectionService\|TelecomManager'` = 0 in the old code). This file covers
/// the first three; call integration (CallKit / self-managed
/// `ConnectionService`) is a later, separate stage (V3.2), "deliberately
/// after the two layers above" (§10.4).
///
/// ## I2 / I6 by construction, not by discipline
///
/// Exactly like `RoutePolicy` (V1.5, `route_policy.dart`), the decision class
/// in this file ([SessionBehaviour]) never holds a reference to a
/// `VoiceSession` and therefore cannot call `stop()` / `start()` / `close()`
/// — there is nothing here to call them with. An interruption only changes
/// [SessionBehaviour.isInterrupted]; nothing about the duplex session's
/// lifecycle moves. "Cleona releases it cleanly and reclaims it afterwards"
/// (§10.4, "Interruption") is about the OS-level audio-focus / audio-session
/// *claim* — never the `cleona_voice` session itself, which I6 requires to
/// stay open regardless of who else is talking to the OS voice chain right
/// now.
///
/// ## Where the interruption signal comes from, on Android today
///
/// `native/cleona_voice/cleona_voice.h` defines `EV_INTERRUPTION_BEGIN` /
/// `EV_INTERRUPTION_END` as ABI events, delivered by polling
/// (`cleona_voice_poll_event`, surfaced in Dart as
/// `VoiceSession.pollEvent()`). [SessionBehaviour.onVoiceEvent] therefore
/// consumes exactly that shape ([VoiceEventRecord]) and nothing more
/// specific — it is ready for any backend that posts those events through
/// the ABI, today or later.
///
/// As of this package, none does. `VoiceSession.kt` (V1.2,
/// `android/.../VoiceSession.kt`, read but not owned by this package) never
/// calls its own private `postEvent` for an interruption: Android's own
/// interruption signal — a cellular call, Siri-equivalent, or another VoIP
/// app taking the device — surfaces through
/// `AudioManager.OnAudioFocusChangeListener`, which is application-level API
/// surface that the JNI voice backend never touches (it has no `Context` of
/// its own; only `VoiceSession.kt`'s Kotlin half does, via
/// `VoiceSession.install(context)`). `VoiceSession.postEvent` is private and
/// `VoiceSession.kt` is V1.2's file (SPEC §9), not this package's — this
/// package cannot inject into the ABI's own queue without asking V1.2 to add
/// a public entry point for it.
///
/// That request was deliberately not made: routing an application-level
/// signal (`AudioFocusChangeListener`) through a component that cannot
/// itself observe it (the JNI facade has no route to `AudioManager`) would
/// be the wrong layer to own the translation. Instead
/// [SessionBehaviourChannel] bridges the same `AudioFocusChangeListener` /
/// `AVAudioSessionInterruptionNotification` signal through its OWN platform
/// channel (`chat.cleona/session_behaviour` — `MainActivity.kt` and
/// `ios/Runner/SessionBehaviourHandler.swift`, both this package's own
/// files, SPEC §9) and re-expresses it as the identical [VoiceEventRecord]
/// shape the ABI would have used. [SessionBehaviour] itself cannot tell the
/// two origins apart and does not need to — which is also why its smoke test
/// drives it with real, ABI-wire-decoded events from the compiled mock
/// (`native/cleona_voice/mock/`) rather than only with hand-built Dart
/// values: the translation from wire int to [VoiceEvent] is V0.2's code, not
/// this package's, and re-exercising it here catches drift in that
/// dependency, not just in this file.
library;

import 'package:flutter/services.dart';

import 'package:cleona/core/calls/voice_session.dart';

// ─────────────────────────────────────────────────────────────────────────
// Decisions — pure, no dart:ffi, no VoiceSession reference (see file doc).
// ─────────────────────────────────────────────────────────────────────────

/// What a caller (the eventual `CallService`, V2.1, running in parallel)
/// should do in reaction to one polled/bridged event. A value, not an
/// instruction — [SessionBehaviour] itself performs no side effect beyond
/// updating [SessionBehaviour.isInterrupted].
enum SessionBehaviourAction {
  /// Nothing relevant happened.
  none,

  /// Another call, Siri, or the system took the audio session. The duplex
  /// `VoiceSession` stays open throughout (I2/I6) — this only updates state
  /// for the UI, so a call "behaves like a telephony call" (§10.4) instead
  /// of silently going quiet.
  interruptionBegan,

  /// The interruption ended. Cleona "reclaims [the session] afterwards"
  /// (§10.4) — on Apple that can mean re-activating `AVAudioSession`, which
  /// [SessionBehaviourChannel]'s native side does when the OS reports
  /// `shouldResume` (see [InterruptionEndInfo]); nothing in `VoiceSession`'s
  /// own lifecycle needs to move either way.
  interruptionEnded,
}

/// Platform-independent session-behaviour policy (architecture §10.4,
/// "Session behaviour" table; work package V1.10).
///
/// Deliberately free of `dart:ffi` and of any `VoiceSession` reference — see
/// the file doc for why that is what makes I2/I6 structural here rather than
/// merely intended, exactly as `RoutePolicy` does for route switching.
class SessionBehaviour {
  bool _interrupted = false;

  /// Whether the session is currently considered interrupted (a foreign call
  /// or the system took the audio session). Purely informational: nothing in
  /// this class stops or starts anything because of it.
  bool get isInterrupted => _interrupted;

  /// Feed one event — from `VoiceSession.pollEvent()` on a backend that
  /// posts interruption events through the ABI, or from
  /// [SessionBehaviourChannel]'s native bridge, which re-expresses the same
  /// shape from `AudioFocusChangeListener` / the Apple interruption
  /// notification (see the file doc for why). Returns the
  /// [SessionBehaviourAction] the caller should react to — e.g. surfacing a
  /// "call paused" indicator.
  SessionBehaviourAction onVoiceEvent(VoiceEventRecord event) {
    switch (event.event) {
      case VoiceEvent.interruptionBegin:
        _interrupted = true;
        return SessionBehaviourAction.interruptionBegan;
      case VoiceEvent.interruptionEnd:
        _interrupted = false;
        return SessionBehaviourAction.interruptionEnded;
      case VoiceEvent.none:
      case VoiceEvent.routesChanged:
      case VoiceEvent.formatChanged:
      case VoiceEvent.invalid:
        return SessionBehaviourAction.none;
    }
  }
}

/// Architecture §10.4, "Proximity": "screen off if and only if the active
/// route is the earpiece." Stated once, here, so neither platform bridge has
/// to restate the rule — each only has to call
/// [SessionBehaviourChannel.setProximityMonitoring] with the result.
///
/// A pure function on purpose (like [SessionBehaviour], no session
/// reference): the caller derives [activeRoute] from `RoutePolicy` /
/// `VoiceSession.getRoutes()` (V1.5's job, not repeated here) and this
/// function only states what to do with whichever route is active,
/// including one I7 just chose after a route loss. This is deliberately NOT
/// I7 itself — I7 decides *which* route to fall back to; this decides
/// whether *the currently active* route, whatever chose it, should also
/// darken the screen.
///
/// Unknown/invalid routes resolve to `false` (no proximity monitoring)
/// rather than guessing: a screen that stays lit is recoverable by the user,
/// a screen that goes dark without a real earpiece pressed to the ear is
/// not (§10.4 "Proximity" only ever names the earpiece as the "on" case).
bool shouldMonitorProximity(VoiceRoute activeRoute) =>
    activeRoute == VoiceRoute.earpiece;

// ─────────────────────────────────────────────────────────────────────────
// Platform bridge
// ─────────────────────────────────────────────────────────────────────────

/// One interruption-end observation from the native bridge: the event shape
/// plus whether the OS asked Cleona to resume.
///
/// Apple states this explicitly
/// (`AVAudioSessionInterruptionOptionKey` / `.shouldResume`, surfaced by
/// `ios/Runner/SessionBehaviourHandler.swift`). Android has no equivalent
/// flag: `AUDIOFOCUS_GAIN` IS the resume signal on that platform (there is no
/// "focus returned but do not resume" case in the Android focus model), so
/// [shouldResume] is always `true` there.
class InterruptionEndInfo {
  const InterruptionEndInfo({required this.shouldResume});
  final bool shouldResume;

  @override
  String toString() => 'InterruptionEndInfo(shouldResume: $shouldResume)';
}

/// Bridges Android `AudioFocusRequest` / Apple interruption notifications +
/// `duckOthers`, and earpiece-only proximity monitoring, through
/// `chat.cleona/session_behaviour`.
///
/// Native counterparts, both this package's own files (SPEC §9):
///   - `android/app/src/main/kotlin/chat/cleona/cleona/MainActivity.kt`
///   - `ios/Runner/SessionBehaviourHandler.swift`
///
/// This class makes NO decisions of its own — it only carries method calls
/// and events across the platform-channel boundary. [SessionBehaviour] and
/// [shouldMonitorProximity] above own every decision; this class is
/// deliberately as thin as `VoiceSession`'s FFI binding is for the native
/// ABI, and for the same reason (SPEC §4: "one binding, once").
class SessionBehaviourChannel {
  SessionBehaviourChannel._();

  static const MethodChannel _channel =
      MethodChannel('chat.cleona/session_behaviour');

  static bool _handlerInstalled = false;

  /// Called whenever the native side observes an interruption boundary,
  /// shaped exactly like a polled ABI event
  /// (`VoiceEvent.interruptionBegin` / `.interruptionEnd`) — see the file doc
  /// for why this bridges rather than posts through the ABI queue directly.
  /// [endInfo] is non-null only alongside `VoiceEvent.interruptionEnd`.
  static void Function(VoiceEventRecord event, InterruptionEndInfo? endInfo)?
      onInterruption;

  /// Registers the handler for native → Dart calls. Idempotent and safe to
  /// call more than once (e.g. across a `configureFlutterEngine` re-run on
  /// Android, where the Activity — and therefore this call site — can be
  /// recreated while the engine survives).
  static void ensureHandlerInstalled() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onInterruptionBegin':
          onInterruption?.call(
            const VoiceEventRecord(VoiceEvent.interruptionBegin, 0),
            null,
          );
          break;
        case 'onInterruptionEnd':
          final args = call.arguments as Map?;
          final shouldResume = args?['shouldResume'] as bool? ?? true;
          onInterruption?.call(
            const VoiceEventRecord(VoiceEvent.interruptionEnd, 0),
            InterruptionEndInfo(shouldResume: shouldResume),
          );
          break;
      }
      return null;
    });
  }

  /// Requests audio focus / session priority for the call:
  ///  - Android: `AudioFocusRequest` with `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE`
  ///    (architecture §10.4, "Session behaviour" table).
  ///  - Apple: activates `AVAudioSession` with category `playAndRecord`, mode
  ///    `voiceChat`, and the `duckOthers` option.
  ///
  /// Returns whether focus/activation was granted. A call is not blocked on
  /// `false` by this layer — that policy decision belongs to the caller
  /// (`CallService`, V2.1) — but a caller that ignores it reproduces exactly
  /// the defect §10.4 names for the superseded stack: "media from other apps
  /// keeps playing through the call."
  static Future<bool> requestAudioFocus() async {
    ensureHandlerInstalled();
    final granted = await _channel.invokeMethod<bool>('requestAudioFocus');
    return granted ?? false;
  }

  /// Releases the focus/activation claimed by [requestAudioFocus]. Call once
  /// per call, at hangup — never from an interruption handler, which is a
  /// temporary OS-driven loss, not an app-driven release. Either way I2/I6
  /// hold: this method never touches a `VoiceSession`, because it does not
  /// have one.
  static Future<void> abandonAudioFocus() async {
    await _channel.invokeMethod<void>('abandonAudioFocus');
  }

  /// Enables or disables proximity-based screen-off
  /// (`PROXIMITY_SCREEN_OFF_WAKE_LOCK` on Android,
  /// `UIDevice.isProximityMonitoringEnabled` on Apple). Call with the result
  /// of [shouldMonitorProximity] whenever the active route changes —
  /// including at call start and after every `RoutePolicy` decision.
  static Future<void> setProximityMonitoring(bool enabled) async {
    await _channel
        .invokeMethod<void>('setProximityMonitoring', {'enabled': enabled});
  }
}
