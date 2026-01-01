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
        reason: '1.2 network stats badge visible');

    // ── Phase 2: Network Integration — REMOVED (S389) ─────────────
    //
    // Phase 2 read a ContactSeed URI from the environment variable
    // `BOOTSTRAP_CONTACT_SEED`, parsed it with `ContactSeed.fromUri` and
    // entered its start peers via `addPeersFromContactSeed`; after that it
    // waited 60 s for a confirmed peer.
    //
    // Two reasons, and both are final:
    //
    // 1. `ContactSeed.fromUri` no longer exists. The read side of the seed
    //    was removed with package 17 = A (finding K-1, owner decision
    //    15.09.2026): v4_2 §4.1 derives the identifier from Ed25519 AND
    //    ML-DSA-65, but the seed only carries the Ed25519 anchor.
    // 2. The entry here depends on an ENVIRONMENT VARIABLE that points to
    //    a specific node. v4_2 §11.7 rules out exactly that:
    //    "No address, no port, no host is built into the app or configuration,
    //    and nothing depends on a specific node
    //    existing" — not even an environment variable.
    //
    // A replacement tests the entry the way the product takes it: via the
    // card of the first contact (§15.2) and the neighbour sources 1-3 (§11.8).
    // That needs a card export of the remote side in CI — the same
    // open prerequisite as for phase 3, in the report S389-BAU-APP.md.
    if (hasContactSeed) {
      printOnFailure('Phase 2 dropped (V3 ContactSeed reader + fixed '
          'entry via BOOTSTRAP_CONTACT_SEED, S389) — the variable is '
          'no longer read');
    }

    // ── Phase 3: Cross-Node CR + Messaging — REMOVED ──────────────
    //
    // Phase 3 sent one contact request each via `sendContactRequest` to
    // the ContactSeeds from ALICE_/ALLYCAT_CONTACT_SEED and waited for the
    // acceptance by an IPC guard. Both are the V3 first contact that
    // V4.2 no longer has (S388-BAU-KONTAKT): a request only arises when
    // redeeming an invitation card (§15.5). A replacement via the card
    // needs a card export of the remote side in CI — open, in the report.
    if (hasPhase3) {
      printOnFailure('Phase 3 dropped (V3 first contact, S388-BAU-KONTAKT) — '
          'ALICE/ALLYCAT_CONTACT_SEED are no longer read');
    }
  });
}
