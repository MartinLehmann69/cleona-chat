// CI Integration Test for Cleona Chat — macOS GitHub Actions Runner
//
// Phase 1: Startup smoke (always runs)
//   - FFI loading (SodiumFFI, OqsFFI)
//   - App launch, Setup flow, Home screen, Settings navigation
//
// Phase 2: Network integration (runs when BOOTSTRAP_CONTACT_SEED is set)
//   - ContactSeed import via Add-Contact dialog
//   - Peer connection verification (peer count > 0)
//
// Run: flutter test integration_test/app_test_ci.dart -d macos
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';

import 'package:cleona/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Phase 1.0: FFI Loading ──────────────────────────────────────
  // This is THE critical check — catches dylib loading failures
  // (white screen bug, Session 33).
  SodiumFFI();
  OqsFFI().init();

  FlutterError.onError = (details) {
    if (details.library == 'flutter test framework') {
      FlutterError.presentError(details);
    }
  };

  testWidgets('Phase 1: Startup Smoke', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 1.1 Setup (fresh install) ─────────────────────────────────
    final setupTextField = find.byType(TextField);
    final settingsIcon = find.byIcon(Icons.settings);
    if (settingsIcon.evaluate().isEmpty && setupTextField.evaluate().isNotEmpty) {
      await tester.enterText(setupTextField.first, 'CI-TestNode');
      await tester.pumpAndSettle();

      final startButton = find.byIcon(Icons.play_arrow);
      if (startButton.evaluate().isNotEmpty) {
        await tester.tap(startButton);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (find.byIcon(Icons.settings).evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle(const Duration(seconds: 5));
      }
    }

    // ── 1.2 Home Screen ───────────────────────────────────────────
    expect(find.byIcon(Icons.settings), findsOneWidget,
        reason: '1.2 Settings-Button existiert');

    // Cell-tower icon (peer count chip)
    expect(find.byIcon(Icons.cell_tower), findsOneWidget,
        reason: '1.2 Peer-Count Chip sichtbar');

    // ── 1.3 Settings Screen ───────────────────────────────────────
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.textContaining('Node-ID'), findsWidgets,
        reason: '1.3 Node-ID sichtbar');

    // Scroll to find Per-Message KEM
    final listView = find.byType(ListView);
    if (listView.evaluate().isNotEmpty) {
      for (var i = 0; i < 5; i++) {
        await tester.drag(listView.first, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
    }
    expect(find.textContaining('Per-Message KEM', skipOffstage: false), findsWidgets,
        reason: '1.3 Per-Message KEM im Widget-Baum');

    // ── 1.4 Back to Home ──────────────────────────────────────────
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.settings), findsOneWidget,
        reason: '1.4 Zurueck auf Home-Screen');
  });

  // ── Phase 2: Network Integration ────────────────────────────────
  // Only runs when BOOTSTRAP_CONTACT_SEED env var is set.
  final contactSeedUri = Platform.environment['BOOTSTRAP_CONTACT_SEED'];

  final hasContactSeed = contactSeedUri != null && contactSeedUri.isNotEmpty;

  testWidgets('Phase 2: Network (ContactSeed)', skip: !hasContactSeed,
      (tester) async {
    // App is already running from Phase 1 — pump to settle
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 2.1 Tap FAB (add contact) on Recent tab
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget, reason: '2.1 FAB sichtbar');
    await tester.tap(fab);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 2.2 Enter ContactSeed URI in the dialog TextField
    final dialogTextField = find.byType(TextField);
    expect(dialogTextField, findsOneWidget, reason: '2.2 Dialog-TextField sichtbar');
    await tester.enterText(dialogTextField, contactSeedUri!);
    await tester.pumpAndSettle();

    // 2.3 Tap the confirm button (FilledButton in dialog)
    final confirmButton = find.byType(FilledButton);
    expect(confirmButton, findsOneWidget, reason: '2.3 Confirm-Button sichtbar');
    await tester.tap(confirmButton);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 2.4 Wait for peer connection (§5.8: relay timeout ~16s, 60s total)
    var peerConnected = false;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 5));
      // Peer count chip shows "N Peers" — check if text contains a digit > 0
      final cellTower = find.byIcon(Icons.cell_tower);
      if (cellTower.evaluate().isNotEmpty) {
        final chipWidget = find.ancestor(
          of: cellTower,
          matching: find.byType(Row),
        );
        if (chipWidget.evaluate().isNotEmpty) {
          final textWidgets = find.descendant(
            of: chipWidget.first,
            matching: find.byType(Text),
          );
          for (final tw in textWidgets.evaluate()) {
            final text = (tw.widget as Text).data ?? '';
            final count = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), ''));
            if (count != null && count > 0) {
              peerConnected = true;
              break;
            }
          }
        }
      }
      if (peerConnected) break;
    }

    expect(peerConnected, isTrue,
        reason: '2.4 Peer-Count > 0 nach ContactSeed-Import (60s Timeout)');
  });
}
