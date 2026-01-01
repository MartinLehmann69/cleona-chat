// integration_test/session_behaviour_platform_test.dart
//
// Device test: SessionBehaviourChannel (V1.10, docs/SPEC_VOICE_VIDEO_REWORK.md
// §7 "V1.10", architecture §10.4 "Session behaviour" table).
//
// Tests exclusively the native bridge (MainActivity.kt /
// SessionBehaviourHandler.swift), NOT the full CleonaApp — CallService
// (V2.1) and CallScreen (V1.6) run in parallel and are not yet wired to
// VoiceSession, so there is no real call yet that one could
// hook into. This test only boots the minimal MaterialApp/binding
// that a MethodChannel call needs, and calls SessionBehaviourChannel
// directly. The actual claim — did requestAudioFocus() really
// register AudioFocus with the system, does setProximityMonitoring(true)
// really hold the PROXIMITY_SCREEN_OFF_WAKE_LOCK — is NOT checked here in the Dart code
// (that cannot be observed from here), but separately
// via `adb shell dumpsys audio` / `adb shell dumpsys power` while this
// test runs (see session report V1.10 for the exact dumpsys output).
//
// Run (phone, ADB local):
//   flutter test integration_test/session_behaviour_platform_test.dart \
//       -d 3A140DLJG003ZG
//
// KNOWN INFRA GAP (2026-07-30, V1.10 session, observed, not
// derived): on the real device (3A140DLJG003ZG) this run builds and installs
// the beta debug APK successfully, the app starts, the Dart VM
// service comes up ("The Dart VM service is listening on ..." in
// logcat) — then the host process `flutter test` hangs for more than 5
// minutes, without any further line appearing in logcat on the device afterwards
// (neither a Cleona log nor a test result). Root
// cause, confirmed by grep instead of assumed:
//   grep -n "testInstrumentationRunner" android/app/build.gradle.kts
// returns NOTHING. Flutter's `integration_test` package requires for the
// device driving path (`flutter test ... -d <android-device>`)
// `testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"` in
// `defaultConfig` plus the corresponding androidTest dependency — both
// are completely missing in this project (`find android/app/src/androidTest` is
// empty). Without that, the host driver cannot talk to the running app;
// the app itself demonstrably runs without errors (see report
// V1.10 for the complete logcat).
//
// This is a project infrastructure gap, not one of this package: it lies
// in `android/app/build.gradle.kts` (build owner, SPEC §9) and in
// a new `android/app/src/androidTest/**` directory, both outside
// the V1.10 ownership list. This file stays as a documented,
// functional test case — it is not invoked automatically anywhere
// (no hit in scripts/run-e2e.sh, scripts/preflight.sh),
// so it blocks no CI/gate. As soon as the instrumentation has been retrofitted,
// it should run without changes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// S367: `SessionBehaviourChannel` moved to `session_behaviour_channel.dart`
// when the §10.4 mechanisms were connected —
// `CallService` lives on the daemon path and must not pull in `package:flutter`,
// so the Flutter-free core had to be separated from the channel part.
// This device test calls the channel directly and
// therefore only needs that — the Flutter-free core no longer
// appears here.
import 'package:cleona/core/calls/session_behaviour_channel.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SessionBehaviourChannel: AudioFocus + Proximity Roundtrip',
      (tester) async {
    // Minimal tree, only so that a Flutter engine context exists — no
    // dependency on CleonaApp/CleonaService.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    // ── AudioFocus ──────────────────────────────────────────────────────
    final granted = await SessionBehaviourChannel.requestAudioFocus();
    debugPrint('V1.10-DEVICE-TEST requestAudioFocus() granted=$granted');
    expect(granted, isTrue,
        reason: 'AudioFocusRequest(AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE) '
            'was rejected by the system');

    // Time window in which `adb shell dumpsys audio` can observe the
    // focus stack from outside.
    debugPrint('V1.10-DEVICE-TEST holding audio focus for 5s window');
    await Future<void>.delayed(const Duration(seconds: 5));

    await SessionBehaviourChannel.abandonAudioFocus();
    debugPrint('V1.10-DEVICE-TEST abandonAudioFocus() called');
    await Future<void>.delayed(const Duration(seconds: 2));

    // ── Proximity ────────────────────────────────────────────────────────
    await SessionBehaviourChannel.setProximityMonitoring(true);
    debugPrint('V1.10-DEVICE-TEST setProximityMonitoring(true) called — '
        'holding for 5s window');
    await Future<void>.delayed(const Duration(seconds: 5));

    await SessionBehaviourChannel.setProximityMonitoring(false);
    debugPrint('V1.10-DEVICE-TEST setProximityMonitoring(false) called');
    await Future<void>.delayed(const Duration(seconds: 2));

    debugPrint('V1.10-DEVICE-TEST done');
  });
}
