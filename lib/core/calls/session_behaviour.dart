/// `SessionBehaviour` — the platform-independent decision half of Android
/// AudioFocus / Apple interruption handling and earpiece-only proximity
/// monitoring for calls (architecture §10.4, "Session behaviour" table;
/// work package docs/SPEC_VOICE_VIDEO_REWORK.md V1.10).
///
/// ## What this is
///
/// §10.4 lists four concerns entirely absent from the superseded stack
/// (defect #8 of the old stack: "Audio focus, interruption handling,
/// proximity and call integration were entirely absent" —
/// `grep 'requestAudioFocus\|AudioFocus\|proximity\|CallKit\|CXProvider\|
/// ConnectionService\|TelecomManager'` = 0 in the old code). This file
/// covers the decision logic for the first three; call integration
/// (CallKit / self-managed `ConnectionService`) is a later, separate stage
/// (V3.2, `call_integration.dart`), "deliberately after the two layers
/// above" (§10.4).
///
/// ## I2 / I6 by construction, not by discipline
///
/// Exactly like `RoutePolicy` (V1.5, `route_policy.dart`), the decision
/// class in this file ([SessionBehaviour]) never holds a reference to a
/// `VoiceSession` and therefore cannot call `stop()` / `start()` / `close()`
/// — there is nothing here to call them with. An interruption only changes
/// [SessionBehaviour.isInterrupted]; nothing about the duplex session's
/// lifecycle moves. "Cleona releases it cleanly and reclaims it afterwards"
/// (§10.4, "Interruption") is about the OS-level audio-focus / audio-session
/// *claim* — never the `cleona_voice` session itself, which I6 requires to
/// stay open regardless of who else is talking to the OS voice chain right
/// now.
///
/// ## Where the interruption signal comes from — and why this file stays
/// `package:flutter/`-free
///
/// `native/cleona_voice/cleona_voice.h` defines `EV_INTERRUPTION_BEGIN` /
/// `EV_INTERRUPTION_END` as ABI events, delivered by polling
/// (`cleona_voice_poll_event`, surfaced in Dart as
/// `VoiceSession.pollEvent()`). [SessionBehaviour.onVoiceEvent] consumes
/// exactly that shape ([VoiceEventRecord]) and nothing more specific — it
/// is ready for any backend that posts those events through the ABI, today
/// or later (as of this package, none does — see `session_behaviour_channel
/// .dart`'s file doc for where Android's real interruption signal comes
/// from instead).
///
/// Splitting the platform bridge (`SessionBehaviourChannel`,
/// `InterruptionEndInfo`) into `session_behaviour_channel.dart` — rather
/// than keeping it in this file as originally built — is S367's fix for a
/// gap `call_integration.dart`'s file doc already names for a sibling case:
/// `package:flutter/services.dart` pulls in `dart:ui`, and `CallService`
/// (which needs [SessionBehaviour] to react to a polled/bridged event) is
/// imported transitively by `lib/service_daemon.dart`, which `dart compile
/// exe` builds without `dart.library.ui`. Importing the old combined file
/// from `call_service.dart` would have broken that build exactly the way
/// `call_integration.dart` describes it once did. `voice_event_dispatch.dart`
/// (S367) is the caller that turns [SessionBehaviour]'s decisions, and
/// `session_behaviour_channel.dart`'s bridged events, into actual state —
/// see that file's doc for the wiring.
library;

import 'package:cleona/core/calls/voice_session.dart';

// ─────────────────────────────────────────────────────────────────────────
// Decisions — pure, no dart:ffi, no VoiceSession reference (see file doc).
// ─────────────────────────────────────────────────────────────────────────

/// What a caller (`CallService`, via `voice_event_dispatch.dart`) should do
/// in reaction to one polled/bridged event. A value, not an instruction —
/// [SessionBehaviour] itself performs no side effect beyond updating
/// [SessionBehaviour.isInterrupted].
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
  /// `session_behaviour_channel.dart`'s native side does when the OS
  /// reports `shouldResume` (see `InterruptionEndInfo`); nothing in
  /// `VoiceSession`'s own lifecycle needs to move either way.
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
  /// `SessionBehaviourChannel`'s native bridge, which re-expresses the same
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
/// `SessionBehaviourChannel.setProximityMonitoring` with the result.
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
