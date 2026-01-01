// lib/core/calls/voice_lab_tone.dart
//
// The lab tone: a LAB daemon's microphone replaced by the sine of the
// voice mock (`native/cleona_voice/mock/`), one frequency per participant,
// so that the E2E case "group call with 7 participants" (D-81, §17.7) can
// tell at every receiver whose voice arrived (`peer_hearing.dart`).
//
// ── HOW IT IS SWITCHED ON ────────────────────────────────────────────────
//
// A file `voice_test_tone.json` in the daemon's device directory
// (`--base-dir`), the same way `rendezvous_relays.json` configures a lab
// node (`rendezvous_relays.dart`):
//
//     {"toneHz": 600}            (optional "amplitude": 1..32767)
//
// It is read whenever a voice session opens, so a test lays it down before
// a call and removes it afterwards; no daemon restart.
//
// ── WHERE THE MOCK COMES FROM — AND FROM NOWHERE ELSE ────────────────────
//
// Only under its fixed name from the daemon's OWN library directory,
// `<bundleDir>/lib/libcleona_voice_mock.so` ([AppPaths.bundleLibDir]) —
// the directory the daemon loads its other libraries from already. No path
// from the file, no search path, no environment variable: the file names a
// tone, never code. A file that still carries a `library` field is refused
// (an old test setup must not silently do something else).
//
// The mock lies there only in a lab: `scripts/build-daemon.sh
// --with-voice-mock` (workstation daemons, `build/daemon/lib/`) and
// `scripts/e2e-ensure.sh` (Node1/Node2, `~/cleona-app/lib/`). No shipping
// path puts it there (`scripts/preflight.sh` Check 15; build-daemon removes
// it without the switch; `vm-deploy.sh` skips it).
//
// ── WHY IT CANNOT BE SWITCHED ON IN A SHIPPED INSTALL ───────────────────
//
//  1. Only a daemon process on Linux reads the file: [deviceDir] is set by
//     `service_daemon.dart` alone, and [read] answers `null` elsewhere.
//  2. The library must lie under the fixed name in the daemon's own lib/
//     AND export `cleona_voice_mock_set_config` (`voice_session.dart`); a
//     shipped bundle has no such file.
//  3. A file that is there but unusable fails the voice session: the call
//     gets NO microphone rather than silently the real one
//     ([VoiceLabToneInvalid]).
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'package:cleona/core/platform/app_paths.dart';

/// The lab tone switch is present but cannot be honoured.
class VoiceLabToneInvalid implements Exception {
  VoiceLabToneInvalid(this.message);
  final String message;
  @override
  String toString() => 'VoiceLabToneInvalid: $message';
}

/// A valid lab tone switch.
class VoiceLabTone {
  VoiceLabTone({
    required this.toneHz,
    required this.library,
    this.amplitude = defaultAmplitude,
  });

  static const String fileName = 'voice_test_tone.json';

  /// The one name the mock is loaded under, inside the daemon's own lib/.
  static const String mockFileName = 'libcleona_voice_mock.so';
  static const int defaultAmplitude = 8000;
  static const int minHz = 100;
  static const int maxHz = 4000;

  /// The daemon's device directory; set once by `service_daemon.dart`.
  /// `null` in every other process — then there is no lab tone.
  static String? deviceDir;

  /// Probes only: stands in for the daemon's own lib/, because a smoke runs
  /// under the Dart SDK's executable. `null` in the product.
  @visibleForTesting
  static String? libDirForTesting;

  /// The daemon's own library directory.
  static String get libDir => libDirForTesting ?? AppPaths.bundleLibDir;

  final int toneHz;
  final int amplitude;

  /// `<libDir>/libcleona_voice_mock.so` — derived, never read from the file.
  final String library;

  /// The switch of this process, or `null` if there is none.
  ///
  /// Throws [VoiceLabToneInvalid] when the file exists but is unusable.
  static VoiceLabTone? read() {
    final dir = deviceDir;
    if (dir == null || !Platform.isLinux) return null;
    final f = File('$dir/$fileName');
    if (!f.existsSync()) return null;
    return parse(f.readAsStringSync());
  }

  /// Parses the file content; throws [VoiceLabToneInvalid] on any defect,
  /// including a mock missing from [libDir].
  static VoiceLabTone parse(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (e) {
      throw VoiceLabToneInvalid('$fileName is not JSON: $e');
    }
    if (j is! Map) throw VoiceLabToneInvalid('$fileName is not an object');
    if (j.containsKey('library')) {
      throw VoiceLabToneInvalid('$fileName names a library — the mock is '
          'loaded only as $mockFileName from the daemon\'s own lib/');
    }
    final hz = j['toneHz'];
    if (hz is! int || hz < minHz || hz > maxHz) {
      throw VoiceLabToneInvalid(
          'toneHz must be an integer in $minHz..$maxHz, is $hz');
    }
    final amp = j['amplitude'] ?? defaultAmplitude;
    if (amp is! int || amp < 1 || amp > 32767) {
      throw VoiceLabToneInvalid('amplitude must be 1..32767, is $amp');
    }
    final lib = '$libDir/$mockFileName';
    if (!File(lib).existsSync()) {
      throw VoiceLabToneInvalid('no $mockFileName in the daemon\'s lib/ ($lib)');
    }
    return VoiceLabTone(toneHz: hz, library: lib, amplitude: amp);
  }
}
