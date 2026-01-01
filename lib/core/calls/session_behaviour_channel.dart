/// `SessionBehaviourChannel` — the platform bridge half of
/// `session_behaviour.dart` (architecture §10.4 "Session behaviour" table;
/// work package docs/SPEC_VOICE_VIDEO_REWORK.md V1.10), split out in S367.
///
/// ## Why this is a separate file from `session_behaviour.dart`
///
/// This class imports `package:flutter/services.dart`, which pulls in
/// `dart:ui`. `session_behaviour.dart`'s [SessionBehaviour] and
/// [shouldMonitorProximity] do not need Flutter and must stay reachable from
/// `CallService` (`call_service.dart`), which is imported transitively by
/// `lib/service_daemon.dart` — a target `dart compile exe` builds without
/// `dart.library.ui`. Before S367 both halves lived in one file, so any
/// import of the decision logic dragged this bridge — and `dart:ui` — along
/// with it; `call_integration.dart`'s file doc already documents the exact
/// same failure for a sibling case ("Error: AOT compilation failed"). The
/// split mirrors that file's own `CallIntegration` /
/// `MethodChannelCallIntegration` pattern: a Flutter-free contract
/// (`session_behaviour.dart`) plus a `MethodChannel` implementation (this
/// file), injected from a Flutter-context caller (`main.dart`) into
/// `CallService`'s public callback fields rather than imported by it
/// directly. See `voice_event_dispatch.dart`'s file doc for how the two
/// halves and `main.dart`'s glue fit together at runtime.
///
/// ## Where the interruption signal comes from, on Android today
///
/// `native/cleona_voice/cleona_voice.h` defines `EV_INTERRUPTION_BEGIN` /
/// `EV_INTERRUPTION_END` as ABI events, delivered by polling
/// (`cleona_voice_poll_event`, surfaced in Dart as
/// `VoiceSession.pollEvent()`). `SessionBehaviour.onVoiceEvent` (in
/// `session_behaviour.dart`) therefore consumes exactly that shape
/// ([VoiceEventRecord]) and nothing more specific — it is ready for any
/// backend that posts those events through the ABI, today or later.
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
/// be the wrong layer to own the translation. Instead [SessionBehaviourChannel]
/// bridges the same `AudioFocusChangeListener` /
/// `AVAudioSessionInterruptionNotification` signal through its OWN platform
/// channel (`chat.cleona/session_behaviour` — `MainActivity.kt` +
/// `CleonaForegroundService.kt` and `ios/Runner/SessionBehaviourHandler.swift`,
/// both this package's own files, SPEC §9) and re-expresses it as the
/// identical [VoiceEventRecord] shape the ABI would have used.
/// `SessionBehaviour` itself cannot tell the two origins apart and does not
/// need to — which is also why its smoke test drives it with real,
/// ABI-wire-decoded events from the compiled mock (`native/cleona_voice/mock
/// /`) rather than only with hand-built Dart values: the translation from
/// wire int to `VoiceEvent` is V0.2's code, not this package's, and
/// re-exercising it there catches drift in that dependency, not just in
/// `session_behaviour.dart`.
///
/// S367 verified both native halves are already built and wired, not just
/// documented: `MainActivity.kt`'s `behaviourChannel.setMethodCallHandler`
/// answers `requestAudioFocus`/`abandonAudioFocus`/`setProximityMonitoring`,
/// `CleonaForegroundService.kt`'s `onAudioFocusChange` posts
/// `onInterruptionBegin`/`onInterruptionEnd` back through this exact channel
/// name on `AUDIOFOCUS_LOSS*`, and `AppDelegate.swift` registers
/// `SessionBehaviourHandler` for the same channel on Apple. What was missing
/// was the Dart-side caller — this file always existed and was always
/// reachable; `voice_event_dispatch.dart` + `main.dart` are S367's new glue.
library;

import 'package:flutter/services.dart';

import 'package:cleona/core/calls/voice_session.dart';

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
///   - `android/app/src/main/kotlin/chat/cleona/cleona/MainActivity.kt` +
///     `CleonaForegroundService.kt`
///   - `ios/Runner/SessionBehaviourHandler.swift`
///
/// This class makes NO decisions of its own — it only carries method calls
/// and events across the platform-channel boundary. `SessionBehaviour` and
/// `shouldMonitorProximity` (`session_behaviour.dart`) own every decision;
/// this class is deliberately as thin as `VoiceSession`'s FFI binding is for
/// the native ABI, and for the same reason (SPEC §4: "one binding, once").
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
  /// of `shouldMonitorProximity` (`session_behaviour.dart`) whenever the
  /// active route changes — including at call start and after every
  /// `RoutePolicy` decision (`voice_event_dispatch.dart`).
  static Future<void> setProximityMonitoring(bool enabled) async {
    await _channel
        .invokeMethod<void>('setProximityMonitoring', {'enabled': enabled});
  }
}
