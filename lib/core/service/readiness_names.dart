// The names of the readiness state at the service and IPC boundary (§22.7).
//
// WHY THESE THREE STRINGS ARE A LEAF OF THEIR OWN. `Readiness`
// (`lib/core/tagline/readiness.dart`) is the truth about the state,
// but it does not cross the IPC boundary: there is JSON, and JSON knows
// no enumeration. The service interface therefore carries the state
// as a string (`ICleonaService.readinessState`) — and needs
// names for it without having to import the delivery layer.
//
// This file has NO imports, so both sides can take it:
// the service interface (which pulls in Flutter and half the application)
// and a pure Dart smoke test that holds the names against the enumeration.
// Exactly this counter-check is in
// `test/smoke/smoke_delivery_api.dart` — without it the coupling would be a
// note instead of a gate: a renamed enum value would silently
// pin `isReady` to `false`, and every gate above it would stay
// closed without anything failing.
library;

/// Zero confirmed outbound relays — nothing can be placed.
const String kReadinessSearching = 'searching';

/// Exactly one. A send attempt is possible, redundancy is not.
const String kReadinessConnecting = 'connecting';

/// Two or more, independent. Placing with redundancy is possible —
/// the predicate on which §22.7.2 hangs the functional gates.
const String kReadinessReady = 'ready';

/// The three in order of increasing readiness.
///
/// Used by the display (which is to show progress, not success)
/// and by the counter-check against `Readiness.values`.
const List<String> kReadinessNames = <String>[
  kReadinessSearching,
  kReadinessConnecting,
  kReadinessReady,
];
