/// `VoiceEventDispatcher` — the one caller `route_policy.dart` and
/// `session_behaviour.dart` describe but do not implement.
///
/// ## The gap this file closes
///
/// `route_policy.dart`'s file doc is explicit: `RoutePolicy` "does not
/// import `voice_session.dart`" — it only computes a [RouteDecision] — and
/// "the caller (V1.6's in-call UI, V2.1's `CallService` integration) is
/// responsible for turning a `RouteDecision` into an actual
/// `VoiceSession.setRouteOrThrow` call." `voice_session.dart:638` names the
/// same gap from the other side: the I7 fallback rule "is policy and lives
/// in `RoutePolicy` (V1.5), not here." Before S367 neither file ever called
/// the other — `RoutePolicy`'s only outside reference in `lib/` was a
/// comment (`voice_session.dart:638`), not a call. This file is that
/// missing caller, built once so `CallService` (`call_service.dart`, V2.1)
/// does not reimplement the drain loop and a second future caller does not
/// either.
///
/// `session_behaviour.dart`'s `SessionBehaviour.onVoiceEvent` is the same
/// shape of gap for `interruptionBegin`/`interruptionEnd`: "ready for any
/// backend that posts those events through the ABI, today or later" per its
/// own file doc, but never called. This dispatcher feeds ABI-sourced
/// interruption events into it via [pump]; the more common path on Android
/// today — `AudioFocusChangeListener` bridged through
/// `session_behaviour_channel.dart`'s `SessionBehaviourChannel`, not the ABI
/// queue (see that file's doc for why) — is fed through [feedBridgedEvent]
/// instead, called from `main.dart`'s `SessionBehaviourChannel.onInterruption`
/// glue. Both paths converge on the same [SessionBehaviour] instance, so
/// `isInterrupted` is correct regardless of which backend a platform uses.
///
/// ## Daemon safety
///
/// `route_policy.dart` and `session_behaviour.dart`'s pure decision classes
/// are both free of `dart:ffi` and of `package:flutter/`. This file adds
/// only `voice_session.dart` (FFI, no Flutter) to that — so `CallService`
/// (imported transitively by `lib/service_daemon.dart`, which must build
/// with `dart compile exe` and therefore never pull in `dart:ui`) can hold
/// one of these without breaking the daemon AOT build. Anything that needs
/// `package:flutter/services.dart` — `SessionBehaviourChannel`'s AudioFocus/
/// interruption bridge, proximity monitoring — is injected into `CallService`
/// from `main.dart` instead, exactly as `CallIntegration` /
/// `MethodChannelCallIntegration` already are (see `call_integration.dart`'s
/// and `session_behaviour_channel.dart`'s file docs for why that split
/// exists).
///
/// ## I5: no timer of its own
///
/// [pump] schedules nothing. `CallService` calls it from the existing
/// 5 ms capture-tick `Timer.periodic` (`_captureAndSend`) — this file only
/// adds work to an already-ticking loop, per I5 ("no timer in the playback
/// path", `voice_session.dart`'s file doc).
library;

import 'package:cleona/core/calls/route_policy.dart';
import 'package:cleona/core/calls/session_behaviour.dart';
import 'package:cleona/core/calls/voice_session.dart';

/// Drains `VoiceSession.pollEvent()` for one active call and applies the
/// resulting decisions back onto the session (routes) or onto an owned
/// [SessionBehaviour] (interruptions).
///
/// One instance per active [VoiceSession] — construct with [forSession] once
/// the session has `start()`ed, discard when the session is stopped.
class VoiceEventDispatcher {
  /// Reads [session]'s route set at construction time and seeds a
  /// [RoutePolicy] from it — mirrors the usage example in
  /// `route_policy.dart`'s own file doc. Also seeds a fresh
  /// [SessionBehaviour] ("Start: not interrupted" — a new call is never
  /// interrupted before its first event).
  VoiceEventDispatcher.forSession(VoiceSession session)
      : routePolicy = _initialRoutePolicy(session),
        sessionBehaviour = SessionBehaviour();

  static RoutePolicy _initialRoutePolicy(VoiceSession session) {
    final routes = session.getRoutes();
    return RoutePolicy(available: routes.available, active: routes.active);
  }

  /// The single, platform-independent route policy for this call
  /// (architecture §10.4). Exposed so a caller/test can read
  /// [RoutePolicy.activeRoute] without re-deriving it.
  final RoutePolicy routePolicy;

  /// The platform-independent AudioFocus/interruption state for this call
  /// (architecture §10.4, V1.10). One per dispatcher — not nullable, unlike
  /// `session_behaviour_channel.dart`'s `SessionBehaviourChannel` (a
  /// process-wide singleton bridge, not per-call state).
  final SessionBehaviour sessionBehaviour;

  /// Called after every [VoiceEvent.routesChanged] this dispatcher applies —
  /// i.e. after the matching `VoiceSession.setRouteOrThrow` call already
  /// happened. Optional; logging, and proximity monitoring
  /// (`shouldMonitorProximity`, wired from `main.dart`) hook in here.
  void Function(RouteDecision decision)? onRouteDecision;

  /// Called whenever [sessionBehaviour] reports an actual transition —
  /// [SessionBehaviourAction.interruptionBegan] or `.interruptionEnded` —
  /// from either [pump] (ABI-sourced events) or [feedBridgedEvent]
  /// (platform-channel-sourced events). Never called for
  /// [SessionBehaviourAction.none].
  void Function(SessionBehaviourAction action)? onSessionBehaviourAction;

  /// Called for every event this dispatcher does not itself turn into a
  /// route switch or a [SessionBehaviour] update — currently only
  /// [VoiceEvent.formatChanged] (already fully handled inside
  /// `VoiceSession.pollEvent()` itself; this callback only observes it).
  /// [VoiceEvent.none] is never passed here — it is the drain loop's exit
  /// condition, not an event.
  void Function(VoiceEventRecord event)? onOtherEvent;

  /// Drains every event currently queued on [session].
  /// `VoiceSession.pollEvent()` "dequeues at most one event" per call and
  /// documents [VoiceEvent.none] as "the normal case", so this loops until
  /// that — a single call can carry more than one pending event (e.g. a
  /// headset arriving and an interruption beginning in the same tick).
  ///
  /// [VoiceEvent.routesChanged] is turned into a real route switch: a fresh
  /// [VoiceSession.getRoutes] read (the event's own `arg` carries only the
  /// new `routes_available_mask`, not the active route — `RoutePolicy`'s own
  /// usage example reads both from `getRoutes()`), fed to
  /// [RoutePolicy.onRoutesChanged], applied via
  /// `VoiceSession.setRouteOrThrow` (rule 4: never `stop()`/`start()`).
  ///
  /// [VoiceEvent.interruptionBegin]/[VoiceEvent.interruptionEnd] are fed to
  /// [sessionBehaviour] — see [feedBridgedEvent] for the platform-channel
  /// path that reaches the same state today on Android/Apple.
  ///
  /// Returns the number of [VoiceEvent.routesChanged] events applied, for
  /// tests and logging.
  int pump(VoiceSession session) {
    var routeChanges = 0;
    while (true) {
      final record = session.pollEvent();
      if (record.isNone) break;

      switch (record.event) {
        case VoiceEvent.routesChanged:
          final fresh = session.getRoutes();
          final decision = routePolicy.onRoutesChanged(
            fresh.available,
            activeFromReport: fresh.active,
          );
          session.setRouteOrThrow(decision.route);
          onRouteDecision?.call(decision);
          routeChanges++;
          break;

        case VoiceEvent.interruptionBegin:
        case VoiceEvent.interruptionEnd:
          _applySessionBehaviourEvent(record);
          break;

        case VoiceEvent.formatChanged:
        case VoiceEvent.none:
        case VoiceEvent.invalid:
          onOtherEvent?.call(record);
          break;
      }
    }
    return routeChanges;
  }

  /// Feeds one interruption event that arrived through
  /// `session_behaviour_channel.dart`'s `SessionBehaviourChannel` — Android's
  /// `AudioFocusChangeListener` / Apple's interruption notification, bridged
  /// rather than posted through the ABI queue (see that file's doc for why).
  /// `main.dart` calls this from `SessionBehaviourChannel.onInterruption`.
  ///
  /// Not part of [pump] because this path has no `VoiceSession` tick driving
  /// it — the platform channel calls back whenever the OS decides to, not on
  /// a 5 ms cadence — and feeding it a [VoiceEventRecord] keeps
  /// [sessionBehaviour] the single place both origins converge, exactly as
  /// `session_behaviour.dart`'s file doc describes ("`SessionBehaviour`
  /// itself cannot tell the two origins apart and does not need to").
  void feedBridgedEvent(VoiceEventRecord event) =>
      _applySessionBehaviourEvent(event);

  void _applySessionBehaviourEvent(VoiceEventRecord event) {
    final action = sessionBehaviour.onVoiceEvent(event);
    if (action != SessionBehaviourAction.none) {
      onSessionBehaviourAction?.call(action);
    }
  }
}
