// integration_test/session_behaviour_platform_test.dart
//
// Device test: SessionBehaviourChannel (V1.10, docs/SPEC_VOICE_VIDEO_REWORK.md
// §7 "V1.10", Architektur §10.4 "Session behaviour" table).
//
// Testet ausschliesslich die native Bruecke (MainActivity.kt /
// SessionBehaviourHandler.swift), NICHT die volle CleonaApp — CallService
// (V2.1) und CallScreen (V1.6) laufen parallel und sind noch nicht mit
// VoiceSession verdrahtet, es gibt also noch keinen echten Call, in den man
// haengen koennte. Dieser Test bootet nur den minimalen MaterialApp/Binding,
// den ein MethodChannel-Aufruf braucht, und ruft SessionBehaviourChannel
// direkt auf. Die eigentliche Behauptung — hat requestAudioFocus() wirklich
// AudioFocus beim System angemeldet, haelt setProximityMonitoring(true)
// wirklich den PROXIMITY_SCREEN_OFF_WAKE_LOCK — wird NICHT hier im Dart-Code
// geprueft (das kann von hier aus nicht beobachtet werden), sondern separat
// per `adb shell dumpsys audio` / `adb shell dumpsys power` waehrend dieser
// Test laeuft (siehe Sitzungsbericht V1.10 fuer den exakten dumpsys-Output).
//
// Lauf (Handy, ADB lokal):
//   flutter test integration_test/session_behaviour_platform_test.dart \
//       -d 3A140DLJG003ZG
//
// BEKANNTE INFRA-LUECKE (2026-07-30, V1.10-Sitzung, beobachtet, nicht
// hergeleitet): auf dem echten Geraet (3A140DLJG003ZG) baut und installiert
// dieser Lauf die Beta-Debug-APK erfolgreich, die App startet, der Dart-VM-
// Service kommt hoch ("The Dart VM service is listening on ..." in
// logcat) — dann bleibt der Host-Prozess `flutter test` laenger als 5
// Minuten haengen, ohne dass am Geraet danach irgendeine weitere Zeile in
// logcat auftaucht (weder ein Cleona-Log noch ein Testergebnis). Root
// Cause, durch grep bestaetigt statt vermutet:
//   grep -n "testInstrumentationRunner" android/app/build.gradle.kts
// liefert NICHTS. Flutters `integration_test`-Paket verlangt fuer den
// Geraete-Treib-Pfad (`flutter test ... -d <android-device>`)
// `testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"` in
// `defaultConfig` plus die zugehoerige androidTest-Abhaengigkeit — beides
// fehlt in diesem Projekt komplett (`find android/app/src/androidTest` ist
// leer). Ohne das kann der Host-Treiber nicht mit der laufenden App
// sprechen; die App selbst laeuft nachweislich fehlerfrei (siehe Bericht
// V1.10 fuer das vollstaendige logcat).
//
// Das ist eine Projekt-Infrastruktur-Luecke, keine dieses Pakets: sie liegt
// in `android/app/build.gradle.kts` (Build-Eigentuemer, SPEC §9) und in
// einem neuen `android/app/src/androidTest/**`-Verzeichnis, beides ausserhalb
// der V1.10-Eigentumsliste. Diese Datei bleibt als dokumentierter,
// funktionsfaehiger Testfall stehen — sie wird nirgends automatisiert
// aufgerufen (kein Treffer in scripts/run-e2e.sh, scripts/preflight.sh),
// haengt also kein CI/Gate auf. Sobald die Instrumentation nachgeruestet
// ist, sollte sie ohne Aenderung laufen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cleona/core/calls/session_behaviour.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SessionBehaviourChannel: AudioFocus + Proximity Roundtrip',
      (tester) async {
    // Minimaler Baum, nur damit ein Flutter-Engine-Kontext existiert — kein
    // Abhaengigkeit auf CleonaApp/CleonaService.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    // ── AudioFocus ──────────────────────────────────────────────────────
    final granted = await SessionBehaviourChannel.requestAudioFocus();
    debugPrint('V1.10-DEVICE-TEST requestAudioFocus() granted=$granted');
    expect(granted, isTrue,
        reason: 'AudioFocusRequest(AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE) '
            'wurde vom System abgelehnt');

    // Zeitfenster, in dem `adb shell dumpsys audio` von aussen den
    // Fokus-Stack beobachten kann.
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
