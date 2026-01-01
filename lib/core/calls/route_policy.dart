/// `RoutePolicy` — the single, platform-independent audio route policy for
/// calls (architecture §10.4, "The policy lives once, in Dart", work package
/// docs/SPEC_VOICE_VIDEO_REWORK.md V1.5).
///
/// ## What this is
///
/// Each of the five native voice backends can *switch* an output route
/// (`cleona_voice_set_route`, see `native/cleona_voice/cleona_voice.h`) and
/// can *report* the route set (`cleona_voice_get_routes`,
/// `CLEONA_VOICE_EV_ROUTES_CHANGED`). None of them decides — deciding is one
/// job, done once, here.
///
/// ## Deliberately free of `dart:ffi`
///
/// This file does not import `voice_session.dart`. It operates purely on
/// [VoiceRoute] values, so it can be unit-tested — and was, per the plan in
/// `voice_report.dart`'s own file doc — without a native library present. The
/// caller (V1.6's in-call UI, V2.1's `CallService` integration) is
/// responsible for turning a [RouteDecision] into an actual
/// `VoiceSession.setRouteOrThrow` call.
///
/// ## The four rules (architecture §10.4)
///
/// 1. A headset — wired or Bluetooth — appears in the route set → switch to
///    it immediately.
/// 2. The active route disappears from the route set → fall back to the
///    **earpiece**, never the speaker (**I7** — non-negotiable: "a phone
///    does not blast the room when headphones are unplugged").
/// 3. A manual speakerphone/device choice by the user wins over the
///    automation above — until the device set changes, at which point rule 1
///    applies again.
/// 4. Every switch happens without tearing the stream down, so the AEC stays
///    converged. This class never calls `stop()`/`start()` itself (it never
///    even sees a session) — rule 4 is upheld by the caller applying a
///    [RouteDecision] via `setRoute`/`setRouteOrThrow` alone, which is why
///    [RouteDecision] carries only a route and a reason, nothing that could
///    be mistaken for a lifecycle instruction.
///
/// ## I7 and platforms without an earpiece
///
/// Architecture §10.4 states I7 in terms of a phone with an earpiece. Three
/// of the five platforms (macOS, Windows, Linux) never have
/// [VoiceRoute.earpiece] in their route set at all — for those, §10.4
/// describes the desktop experience as "the UI shows a device chooser rather
/// than a button that does nothing", not an automatic earpiece fallback that
/// cannot exist. This class resolves that by never *automatically* choosing
/// the speaker while a better alternative (the earpiece if this device has
/// one, otherwise another still-connected non-speaker route) exists, and
/// only accepting the speaker when it is the sole route left — at which
/// point it is not a preference, it is the only option the platform offers.
/// That ordering for the no-earpiece branch is this file's own reasoned
/// completion of a gap the architecture leaves to the desktop UI, not
/// literal spec text — flagged here so a reviewer can find it in one place.
library;

import 'package:cleona/core/calls/voice_report.dart' show VoiceRoute;

/// Why [RoutePolicy] chose the route it did. Carried for logging and tests;
/// never consulted by the policy itself to make its next decision — the
/// state that matters lives in the policy's own fields.
enum RouteDecisionReason {
  /// Rule 1: a wired or Bluetooth headset newly appeared.
  headsetAppeared,

  /// Rule 3: a standing manual choice is still valid and was kept.
  manualChoiceHeld,

  /// Rule 2 / I7: the previously active route disappeared; fell back to the
  /// earpiece (or, lacking one, the best remaining non-speaker route, or —
  /// only if nothing else exists — the speaker).
  activeRouteLost,

  /// [RoutePolicy.selectManualRoute] was called directly by the user.
  manualSelection,

  /// The route set changed but none of the rules above required a switch;
  /// the previously active route is still present and still applies.
  noChange,
}

/// One decision: the route that should now be active, and why.
///
/// This is a value, not an instruction — applying it (calling
/// `VoiceSession.setRouteOrThrow`, never `stop()`/`start()`, rule 4) is the
/// caller's job.
class RouteDecision {
  const RouteDecision(this.route, this.reason);

  final VoiceRoute route;
  final RouteDecisionReason reason;

  @override
  String toString() => 'RouteDecision(${route.logName}, ${reason.name})';

  @override
  bool operator ==(Object other) =>
      other is RouteDecision && other.route == route && other.reason == reason;

  @override
  int get hashCode => Object.hash(route, reason);
}

/// The routes rule 1 treats as "a headset appeared". Not [VoiceRoute.wired]
/// alone, not [VoiceRoute.earpiece] (built-in, does not "appear") and not
/// [VoiceRoute.speaker] (built-in, and the one route I7 must never prefer).
const Set<VoiceRoute> _headsetRoutes = {VoiceRoute.wired, VoiceRoute.bluetooth};

/// The platform-independent audio route policy (architecture §10.4, work
/// package V1.5). See the file doc for the four rules and the I7 invariant.
///
/// Usage:
/// ```dart
/// final policy = RoutePolicy(
///   available: report.routesAvailable,
///   active: report.routeActiveOut,
/// );
/// // ... on CLEONA_VOICE_EV_ROUTES_CHANGED:
/// final fresh = session.getRoutes();
/// final decision = policy.onRoutesChanged(
///   fresh.available,
///   activeFromReport: fresh.active,
/// );
/// session.setRouteOrThrow(decision.route); // rule 4: no stop()/start()
/// ```
class RoutePolicy {
  /// [available] and [active] are the route set and active output route at
  /// construction time — typically read straight off
  /// `VoiceSession.getRoutes()` / the verification report right after
  /// `start()`.
  ///
  /// If [active] is [VoiceRoute.unknown] or [VoiceRoute.invalid] (the ABI
  /// permits [VoiceRoute.unknown] before `start()`), the initial route is
  /// resolved through the same I7-respecting fallback used for rule 2, so
  /// construction never silently prefers the speaker either.
  RoutePolicy({required Set<VoiceRoute> available, required VoiceRoute active})
      : _available = Set.of(available),
        _active = _isConcreteRoute(active) ? active : VoiceRoute.unknown {
    if (!_isConcreteRoute(active)) {
      _active = _fallbackAfterLoss(_available);
    }
  }

  Set<VoiceRoute> _available;
  VoiceRoute _active;

  /// The route the user explicitly picked (rule 3), or `null` if automation
  /// is currently in control.
  VoiceRoute? _manualRoute;

  /// Snapshot of [_available] at the moment [_manualRoute] was set. Rule 3's
  /// pin is valid only while the device set matches this snapshot exactly.
  Set<VoiceRoute>? _manualRouteDeviceSet;

  /// The route currently considered active by this policy.
  VoiceRoute get activeRoute => _active;

  /// The route the user pinned manually, or `null` while automation decides.
  VoiceRoute? get manualRoute => _manualRoute;

  /// The route set this policy last saw.
  Set<VoiceRoute> get availableRoutes => Set.unmodifiable(_available);

  /// The user explicitly picked [route] — tapping "speakerphone", or picking
  /// a device from the desktop chooser §10.4 describes for platforms with no
  /// earpiece.
  ///
  /// Rule 3: this choice wins over the automatic rules above until the
  /// device set changes, at which point rule 1 (headset arrival) applies
  /// again on the next [onRoutesChanged] call.
  ///
  /// Throws [ArgumentError] if [route] is not currently available — picking
  /// an absent route is a caller bug (the UI should not have offered it),
  /// not a state this policy silently accepts.
  RouteDecision selectManualRoute(VoiceRoute route) {
    if (!_isConcreteRoute(route)) {
      throw ArgumentError.value(route, 'route', 'must be a concrete route');
    }
    if (!_available.contains(route)) {
      throw ArgumentError.value(
          route, 'route', 'not in the current available set $_available');
    }
    _manualRoute = route;
    _manualRouteDeviceSet = Set.of(_available);
    _active = route;
    return RouteDecision(_active, RouteDecisionReason.manualSelection);
  }

  /// Feed a fresh route snapshot, taken after
  /// `CLEONA_VOICE_EV_ROUTES_CHANGED` — call `VoiceSession.getRoutes()` (or
  /// read the verification report) and pass its result here.
  ///
  /// [available] is the new `routes_available_mask`, decoded.
  /// [activeFromReport] is what the backend itself reports as the active
  /// output route; per `native/cleona_voice/mock/cleona_voice_mock.h`, a
  /// conformant backend sets this to [VoiceRoute.unknown] when the
  /// previously active route just disappeared, precisely so this policy has
  /// to make the I7 decision instead of the backend making it silently.
  ///
  /// Returns the [RouteDecision] the caller must apply via
  /// `VoiceSession.setRouteOrThrow` — a plain route switch, never a
  /// stop()/start() pair (rule 4).
  RouteDecision onRoutesChanged(
    Set<VoiceRoute> available, {
    required VoiceRoute activeFromReport,
  }) {
    final previousAvailable = _available;
    _available = Set.of(available);

    // Rule 1: a wired or Bluetooth headset newly appeared -> switch
    // immediately. Arriving hardware is exactly the "device set changes"
    // boundary rule 3 names, so a standing manual pin is released here.
    final appearedHeadsets = available
        .difference(previousAvailable)
        .where(_headsetRoutes.contains)
        .toList(growable: false);
    if (appearedHeadsets.isNotEmpty) {
      _clearManualRoute();
      // Implementation choice, not literal spec text: if a wired route and a
      // Bluetooth route both enter the mask in the same event, prefer
      // Bluetooth — the more likely deliberate action (pairing) versus a
      // wire that was often already physically present before its mask bit
      // landed. Flagged here because architecture §10.4 does not cover the
      // simultaneous-arrival case.
      final target = appearedHeadsets.contains(VoiceRoute.bluetooth)
          ? VoiceRoute.bluetooth
          : appearedHeadsets.first;
      _active = target;
      return RouteDecision(_active, RouteDecisionReason.headsetAppeared);
    }

    // Rule 3: a manual pin survives exactly as long as the device set is
    // unchanged from the moment it was made.
    if (_manualRoute != null) {
      final pinned = _manualRoute!;
      final deviceSetUnchanged = _manualRouteDeviceSet != null &&
          _setEquals(_manualRouteDeviceSet!, available);
      if (deviceSetUnchanged && available.contains(pinned)) {
        _active = pinned;
        return RouteDecision(_active, RouteDecisionReason.manualChoiceHeld);
      }
      // The device set changed since the pin was made — even without a new
      // headset arriving, e.g. the pinned device itself disconnected — so
      // rule 3's protection lapses and automation resumes below.
      _clearManualRoute();
    }

    // Rule 2 / I7: the active route disappeared -> fall back to the
    // earpiece, never the speaker.
    final activeStillPresent =
        _isConcreteRoute(activeFromReport) && available.contains(activeFromReport);
    if (!activeStillPresent) {
      _active = _fallbackAfterLoss(available);
      return RouteDecision(_active, RouteDecisionReason.activeRouteLost);
    }

    _active = activeFromReport;
    return RouteDecision(_active, RouteDecisionReason.noChange);
  }

  void _clearManualRoute() {
    _manualRoute = null;
    _manualRouteDeviceSet = null;
  }

  /// I7, non-negotiable: prefer the earpiece over the speaker whenever this
  /// device has one at all. See the file doc for the reasoned (not
  /// spec-literal) ordering used when no earpiece exists on this platform.
  VoiceRoute _fallbackAfterLoss(Set<VoiceRoute> available) {
    if (available.contains(VoiceRoute.earpiece)) return VoiceRoute.earpiece;
    for (final route in const [VoiceRoute.wired, VoiceRoute.bluetooth]) {
      if (available.contains(route)) return route;
    }
    if (available.contains(VoiceRoute.speaker)) return VoiceRoute.speaker;
    return VoiceRoute.unknown;
  }

  static bool _isConcreteRoute(VoiceRoute route) =>
      route != VoiceRoute.unknown && route != VoiceRoute.invalid;

  static bool _setEquals(Set<VoiceRoute> a, Set<VoiceRoute> b) =>
      a.length == b.length && a.containsAll(b);
}
