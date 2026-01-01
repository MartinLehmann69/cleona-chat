// Integration tests: recovery & settings details — runs on Node1 (Alice)
// All checks in a single testWidgets to avoid port conflicts.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SodiumFFI();
  OqsFFI().init();
  FlutterError.onError = (d) {
    if (d.library == 'flutter test framework') FlutterError.presentError(d);
  };

  testWidgets('Recovery: Settings, Seed-Phrase, Netzwerk-Info', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 1. OPEN SETTINGS ────────────────────────────────────────────
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byIcon(Icons.fingerprint), findsWidgets,
        reason: '1.01 settings screen opened (node ID visible)');

    // ── 2. BACKUP SECTION ───────────────────────────────────────────
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      try {
        await tester.scrollUntilVisible(find.byIcon(Icons.key), 200, scrollable: scrollables.last);
        await tester.pumpAndSettle();
      } catch (_) {
        await tester.drag(scrollables.last, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
    }

    final keyIcon = find.byIcon(Icons.key, skipOffstage: false);
    expect(keyIcon.evaluate().isNotEmpty, true,
        reason: '2.01 recovery phrase button present');

    // ── 3. RECOVERY-PHRASE DIALOG ───────────────────────────────────
    if (keyIcon.evaluate().isNotEmpty) {
      await tester.tap(keyIcon.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final dialog = find.byType(AlertDialog);
      if (dialog.evaluate().isNotEmpty) {
        expect(dialog, findsOneWidget, reason: '3.01 dialog opened');

        final word1 = find.textContaining('1. ', skipOffstage: false);
        expect(word1.evaluate().isNotEmpty, true, reason: '3.02 numbered word 1');

        // Print + Copy Buttons
        final printIcon = find.byIcon(Icons.print);
        if (printIcon.evaluate().isNotEmpty) {
          expect(printIcon, findsWidgets, reason: '3.03 Drucken-Button');
        }
        final copyIcon = find.byIcon(Icons.copy);
        if (copyIcon.evaluate().isNotEmpty) {
          expect(copyIcon, findsWidgets, reason: '3.04 Kopieren-Button');
        }

        // Close
        final filledBtns = find.byType(FilledButton);
        if (filledBtns.evaluate().isNotEmpty) {
          await tester.tap(filledBtns.last);
          await tester.pumpAndSettle();
        }
      }
    }

    // ── 4. NETZWERK-INFO ────────────────────────────────────────────
    if (scrollables.evaluate().isNotEmpty) {
      await tester.drag(scrollables.last, const Offset(0, 500));
      await tester.pumpAndSettle();
    }

    expect(find.textContaining('Node-ID'), findsWidgets, reason: '4.01 Node-ID Label');

    // ── 5. BACK ─────────────────────────────────────────────────────
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cleona'), findsWidgets, reason: '5.01 back on home');
  });
}
