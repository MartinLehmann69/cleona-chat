// CI Integration Test for Cleona Chat — macOS GitHub Actions Runner
//
// Phase 1: Startup smoke (always runs)
//   - FFI loading (SodiumFFI, OqsFFI)
//   - App launch, Setup flow, Home screen
//
// Phase 2: Network integration (runs when BOOTSTRAP_CONTACT_SEED is set)
//   - Programmatic ContactSeed import via CleonaService API (no GUI taps)
//   - Peer connection verification (peer count > 0)
//
// Both phases run in a single testWidgets — Flutter integration tests
// don't share widget trees across testWidgets blocks.
//
// Run: flutter test integration_test/app_test_ci.dart -d macos
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/network/contact_seed.dart';
import 'package:cleona/core/service/cleona_service.dart';

import 'package:cleona/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Phase 1.0: FFI Loading ──────────────────────────────────────
  SodiumFFI();
  OqsFFI().init();

  FlutterError.onError = (details) {
    if (details.library == 'flutter test framework') {
      FlutterError.presentError(details);
    }
  };

  final contactSeedUri = Platform.environment['BOOTSTRAP_CONTACT_SEED'];
  final hasContactSeed = contactSeedUri != null && contactSeedUri.isNotEmpty;

  testWidgets('CI Integration Test', (tester) async {
    // ── Phase 1: Startup Smoke ──────────────────────────────────────
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

        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(seconds: 1));
          final dismissBtn = find.byType(FilledButton);
          if (dismissBtn.evaluate().isNotEmpty) {
            await tester.tap(dismissBtn.last);
            break;
          }
        }

        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (find.byIcon(Icons.settings).evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle(const Duration(seconds: 5));
      }
    }

    // ── 1.2 Home Screen ───────────────────────────────────────────
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byIcon(Icons.settings).evaluate().isNotEmpty &&
          find.byIcon(Icons.bar_chart).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.byIcon(Icons.settings), findsOneWidget,
        reason: '1.2 Settings-Button existiert');

    expect(find.byIcon(Icons.bar_chart), findsOneWidget,
        reason: '1.2 Network-Stats-Badge sichtbar');

    // ── Phase 2: Network Integration ────────────────────────────────
    if (!hasContactSeed) {
      printOnFailure('Phase 2 skipped: BOOTSTRAP_CONTACT_SEED not set');
      return;
    }

    // 2.1 Parse ContactSeed URI
    final seed = ContactSeed.fromUri(contactSeedUri);
    expect(seed, isNotNull, reason: '2.1 ContactSeed URI parsed successfully');

    // 2.2 Get CleonaService from widget tree
    final context = tester.element(find.byType(MaterialApp));
    final appState = Provider.of<CleonaAppState>(context, listen: false);
    expect(appState.service, isNotNull,
        reason: '2.2 CleonaService is running');

    final service = appState.service! as CleonaService;

    // 2.3 Add peers from ContactSeed programmatically
    final seedPeers = seed!.seedPeers
        .map((p) => (nodeIdHex: p.nodeIdHex, addresses: p.addresses))
        .toList();

    service.addPeersFromContactSeed(
      seed.nodeIdHex,
      seed.ownAddresses,
      seedPeers,
      targetDeviceIdHex: seed.deviceIdHex,
      targetDxkB64: seed.deviceX25519Pk != null
          ? base64.encode(seed.deviceX25519Pk!)
          : null,
      targetDmkB64: seed.deviceMlKemPk != null
          ? base64.encode(seed.deviceMlKemPk!)
          : null,
    );

    // 2.4 Send contact request
    await service.sendContactRequest(
      seed.nodeIdHex,
      seedDeviceIdHex: seed.deviceIdHex,
      seedDxkB64: seed.deviceX25519Pk != null
          ? base64.encode(seed.deviceX25519Pk!)
          : null,
      seedDmkB64: seed.deviceMlKemPk != null
          ? base64.encode(seed.deviceMlKemPk!)
          : null,
    );
    await tester.pump(const Duration(seconds: 2));

    // 2.5 Wait for peer connection (60s timeout)
    var peerConnected = false;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 5));
      final badge = find.byType(Badge);
      for (final b in badge.evaluate()) {
        final widget = b.widget as Badge;
        if (widget.label is Text) {
          final text = (widget.label as Text).data ?? '0';
          final count = int.tryParse(text);
          if (count != null && count > 0) {
            peerConnected = true;
            break;
          }
        }
      }
      if (peerConnected) break;
    }

    expect(peerConnected, isTrue,
        reason: '2.5 Peer-Count > 0 nach ContactSeed-Import (60s Timeout)');
  });
}
