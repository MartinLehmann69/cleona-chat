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
// Phase 3: Cross-node CR + messaging (runs when ALICE/ALLYCAT_CONTACT_SEED set)
//   - Send CR to Alice (Node 1 identity 1) → auto-accepted by IPC watcher
//   - Send CR to AllyCat (Node 1 identity 2) → auto-accepted by IPC watcher
//   - Send test messages to both, receive CI-ACK messages back
//
// All phases run in a single testWidgets — Flutter integration tests
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

  final aliceSeedUri = Platform.environment['ALICE_CONTACT_SEED'];
  final allyCatSeedUri = Platform.environment['ALLYCAT_CONTACT_SEED'];
  final hasPhase3 = aliceSeedUri != null && aliceSeedUri.isNotEmpty &&
      allyCatSeedUri != null && allyCatSeedUri.isNotEmpty;

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

    // ── Phase 3: Cross-Node CR + Messaging ──────────────────────────
    if (!hasPhase3) {
      printOnFailure('Phase 3 skipped: ALICE/ALLYCAT_CONTACT_SEED not set');
      return;
    }

    // 3.1 Parse Alice's and AllyCat's ContactSeeds
    final aliceSeed = ContactSeed.fromUri(aliceSeedUri);
    final allyCatSeed = ContactSeed.fromUri(allyCatSeedUri);
    expect(aliceSeed, isNotNull, reason: '3.1 Alice ContactSeed parsed');
    expect(allyCatSeed, isNotNull, reason: '3.1 AllyCat ContactSeed parsed');

    // Helper: import seed + send CR
    Future<void> importAndSendCR(ContactSeed cs) async {
      final sp = cs.seedPeers
          .map((p) => (nodeIdHex: p.nodeIdHex, addresses: p.addresses))
          .toList();
      service.addPeersFromContactSeed(
        cs.nodeIdHex,
        cs.ownAddresses,
        sp,
        targetDeviceIdHex: cs.deviceIdHex,
        targetDxkB64: cs.deviceX25519Pk != null
            ? base64.encode(cs.deviceX25519Pk!)
            : null,
        targetDmkB64: cs.deviceMlKemPk != null
            ? base64.encode(cs.deviceMlKemPk!)
            : null,
      );
      await service.sendContactRequest(
        cs.nodeIdHex,
        seedDeviceIdHex: cs.deviceIdHex,
        seedDxkB64: cs.deviceX25519Pk != null
            ? base64.encode(cs.deviceX25519Pk!)
            : null,
        seedDmkB64: cs.deviceMlKemPk != null
            ? base64.encode(cs.deviceMlKemPk!)
            : null,
      );
    }

    // 3.2 Send CRs to Alice and AllyCat
    await importAndSendCR(aliceSeed!);
    await tester.pump(const Duration(seconds: 2));
    await importAndSendCR(allyCatSeed!);
    await tester.pump(const Duration(seconds: 2));

    // 3.3 Wait for both contacts to be accepted (120s timeout)
    var aliceAccepted = false;
    var allyCatAccepted = false;
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(seconds: 5));
      for (final c in service.acceptedContacts) {
        if (c.nodeIdHex == aliceSeed.nodeIdHex) aliceAccepted = true;
        if (c.nodeIdHex == allyCatSeed.nodeIdHex) allyCatAccepted = true;
      }
      if (aliceAccepted && allyCatAccepted) break;
    }

    expect(aliceAccepted, isTrue,
        reason: '3.3 Alice accepted CR within 120s');
    expect(allyCatAccepted, isTrue,
        reason: '3.3 AllyCat accepted CR within 120s');

    // 3.4 Send test messages to Alice and AllyCat
    final aliceMsg = await service.sendTextMessage(
        aliceSeed.nodeIdHex, 'CI-PING-Alice');
    expect(aliceMsg, isNotNull, reason: '3.4 Message to Alice queued');

    await tester.pump(const Duration(seconds: 1));

    final allyCatMsg = await service.sendTextMessage(
        allyCatSeed.nodeIdHex, 'CI-PING-AllyCat');
    expect(allyCatMsg, isNotNull, reason: '3.4 Message to AllyCat queued');

    // 3.5 Wait for CI-ACK messages from the IPC watcher (120s timeout)
    var aliceAck = false;
    var allyCatAck = false;
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(seconds: 5));

      final aliceConv = service.conversations[aliceSeed.nodeIdHex];
      if (aliceConv != null) {
        for (final msg in aliceConv.messages) {
          if (msg.text.startsWith('CI-ACK-')) {
            aliceAck = true;
            break;
          }
        }
      }

      final allyCatConv = service.conversations[allyCatSeed.nodeIdHex];
      if (allyCatConv != null) {
        for (final msg in allyCatConv.messages) {
          if (msg.text.startsWith('CI-ACK-')) {
            allyCatAck = true;
            break;
          }
        }
      }

      if (aliceAck && allyCatAck) break;
    }

    expect(aliceAck, isTrue,
        reason: '3.5 Received CI-ACK from Alice within 120s');
    expect(allyCatAck, isTrue,
        reason: '3.5 Received CI-ACK from AllyCat within 120s');
  });
}
