/// THE ONE SOURCE OF THE OWN VERSION.
///
/// ── WHY THIS FILE EXISTS (S368) ────────────────────────────────
///
/// Until S368 the version stood in ONE place in the code
/// (`CleonaService.kCurrentAppVersion`), but this place was not reachable for large
/// parts of the tree: `cleona_service.dart` is a large
/// library with twelve `part` files, and whoever imports it gets
/// half the service along. `call_service.dart`, for instance, does not import it.
///
/// The consequence was measurable and expensive: `call_service.dart` set the OWN
/// version advertised on the wire to `minCallerAppMajorMinor` — the
/// smallest still accepted peer version, a handwritten
/// `3002`. **V4.1 announced itself in the network as 3.2.0.** Not out of a
/// decision, but because the right source was not reachable from there
/// and a number lay nearby.
///
/// This file is deliberately a **leaf**: it imports nothing. Thus
/// every layer can include it without building a ring, and there is no
/// reason any more to copy a version number.
///
/// Owner, 05.09.2026: "V4.1 must of course not announce itself as 3.2.0 in the
/// network." and "...and nowhere else either! V4.1 = V4.1!"
library;

/// The version of this build, as a string.
///
/// **It MUST match the `version:` field in `pubspec.yaml`**
/// (there `4.2.0+1`; the build number after the `+` does not belong to it).
/// `scripts/preflight.sh` holds both against each other and blocks the
/// commit on deviation.
const String kAppVersion = '4.2.0';

/// The own version as `major * 1000 + minor`.
///
/// Encoding as described in `proto/app_payloads.proto`:
/// 3.1.x -> 3001, 3.2.0 -> 3002, 4.0.0 -> 4000, 4.1.0 -> 4001. Monotonic
/// across every version jump, and without the rollover defect of `minor >= 2`
/// (4.0.0 has `minor == 0`).
///
/// **The patch digit is deliberately NOT included.** 4.1.0 and 4.1.9 are
/// the same line and must be able to talk to each other; a
/// bug fix must not split a network.
final int kAppMajorMinor = encodeMajorMinor(kAppVersion);

/// `"4.1.0"` -> `4001`.
///
/// Throws on unreadable input instead of silently returning `0`: `0` is on the
/// wire the proto3 default value and means there "version missing". A
/// silent false statement about the own version is worse than a
/// loud error at start.
int encodeMajorMinor(String version) {
  final parts = version.split('.');
  if (parts.length < 2) {
    throw StateError('Version "$version" has no major.minor form');
  }
  final major = int.tryParse(parts[0]);
  final minor = int.tryParse(parts[1]);
  if (major == null || minor == null) {
    throw StateError('Version "$version" carries no numbers in major.minor');
  }
  return major * 1000 + minor;
}

/// The LINE of this build as `"major.minor"` — `4.1.0` -> `"4.1"`.
///
/// That is the identifier under which the architecture is kept and under
/// which `FirstStartWipe` sets its marker (`markerFormat`). It is
/// DERIVED and not typed in, for a reason that has already
/// occurred once: the settings screen showed until S368
/// "(Architecture v3.0)", because a literal stood there — the line had been
/// a different one since S345, the line kept saying it wrongly. Whoever derives it
/// cannot repeat this error.
///
/// ADDENDUM S368, BECAUSE THIS SENTENCE WAS ITSELF A FALSE STATEMENT: when it
/// was written, `FirstStartWipe.markerFormat` stood as literal `'4.1'`
/// in the code — the documentation claimed a derivation that did not exist. It was
/// found by a search of the WHOLE tree for
/// self-namings, not by the gate: that searched for three-part
/// numbers (`N.N.N`) and did not see a two-part one. Since then the marker is
/// really derived, and check E of the gate catches the next
/// two-part number.
final String kAppLine = _lineOf(kAppVersion);

String _lineOf(String version) {
  final parts = version.split('.');
  if (parts.length < 2) {
    throw StateError('Version "$version" has no major.minor form');
  }
  return '${parts[0]}.${parts[1]}';
}
