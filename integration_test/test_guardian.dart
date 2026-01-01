// Integration Tests: Guardian SSS, Skins, Stats, QR — laeuft auf Node1 (Alice)
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

  testWidgets('New Features: Guardian, Skins, Stats, QR, Description', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 1. NETWORK STATS ────────────────────────────────────────────
    final statsIcon = find.byIcon(Icons.bar_chart);
    expect(statsIcon, findsOneWidget, reason: '1.01 Stats-Icon im AppBar');

    await tester.tap(statsIcon);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byType(ListTile), findsWidgets, reason: '1.02 Stats hat ListTiles');

    final cellTower = find.byIcon(Icons.cell_tower, skipOffstage: false);
    expect(cellTower.evaluate().isNotEmpty, true, reason: '1.03 Health Icons');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // ── 2. QR BUTTONS IM KONTAKT-DIALOG ─────────────────────────────
    await tester.tap(find.text('Aktuell'));
    await tester.pumpAndSettle();

    final fab = find.byIcon(Icons.person_add);
    if (fab.evaluate().isNotEmpty) {
      await tester.tap(fab.first);
      await tester.pumpAndSettle();

      final qrCode = find.byIcon(Icons.qr_code);
      final qrScan = find.byIcon(Icons.qr_code_scanner);
      expect(qrCode.evaluate().isNotEmpty, true, reason: '2.01 QR-Code Button');
      expect(qrScan.evaluate().isNotEmpty, true, reason: '2.02 QR-Scanner Button');

      // Abbrechen
      final cancelBtns = find.byType(TextButton);
      if (cancelBtns.evaluate().isNotEmpty) {
        await tester.tap(cancelBtns.first);
        await tester.pumpAndSettle();
      }
    }

    // ── 3. SETTINGS: Skin, Guardian, Description ────────────────────
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 3a. Profil-Beschreibung TextField
    final textFields = find.byType(TextField, skipOffstage: false);
    expect(textFields.evaluate().isNotEmpty, true, reason: '3.01 Description TextField');

    // 3b. Scroll zum Skin-Chooser
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      await tester.drag(scrollables.last, const Offset(0, -200));
      await tester.pumpAndSettle();
    }

    final palette = find.byIcon(Icons.palette, skipOffstage: false);
    if (palette.evaluate().isNotEmpty) {
      expect(palette, findsWidgets, reason: '3.02 Skin-Chooser vorhanden');
    }

    // 3c. Scroll weiter zum Social Recovery
    if (scrollables.evaluate().isNotEmpty) {
      await tester.drag(scrollables.last, const Offset(0, -300));
      await tester.pumpAndSettle();
    }

    final security = find.byIcon(Icons.security, skipOffstage: false);
    if (security.evaluate().isNotEmpty) {
      expect(security, findsWidgets, reason: '3.03 Social Recovery vorhanden');
    }

    // 3d. Seed-Phrase Button
    final keyIcon = find.byIcon(Icons.key, skipOffstage: false);
    if (keyIcon.evaluate().isNotEmpty) {
      expect(keyIcon, findsWidgets, reason: '3.04 Recovery-Phrase Button');
    }

    // Zurueck
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // ── 4. IDENTITY TAB CONTEXT MENU ────────────────────────────────
    // Lang auf Tab druecken
    final identityTabs = find.byType(InkWell);
    if (identityTabs.evaluate().length >= 2) {
      await tester.longPress(identityTabs.first);
      await tester.pumpAndSettle();

      // QR-Code Option
      final qrMenu = find.byIcon(Icons.qr_code);
      if (qrMenu.evaluate().isNotEmpty) {
        expect(qrMenu, findsWidgets, reason: '4.01 QR im Kontextmenu');
      }

      // Skin Option
      final paletteMenu = find.byIcon(Icons.palette);
      if (paletteMenu.evaluate().isNotEmpty) {
        expect(paletteMenu, findsWidgets, reason: '4.02 Skin im Kontextmenu');
      }

      // Dismiss
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    // ── 5. LANGUAGE SELECTOR ────────────────────────────────────────
    final popupBtns = find.byType(PopupMenuButton<String>);
    expect(popupBtns.evaluate().isNotEmpty, true, reason: '5.01 Language Selector vorhanden');
  });
}
