// Integration tests: internationalisation (i18n) — language switching and translations
// Tests LanguageSelector, language switching (EN, ES, DE), tabs, settings and network stats.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/main.dart';
import 'package:cleona/ui/components/language_selector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SodiumFFI();
  OqsFFI().init();
  FlutterError.onError = (d) {
    if (d.library == 'flutter test framework') FlutterError.presentError(d);
  };

  testWidgets('i18n: Flaggen-Icon im AppBar sichtbar (LanguageSelector)', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 1. LANGUAGE SELECTOR IM APPBAR ────────────────────────────────
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '1.01 LanguageSelector widget must be present in the AppBar');

    // LanguageSelector is a PopupMenuButton — must be visible
    final popupMenu = find.byType(PopupMenuButton<String>);
    expect(popupMenu, findsWidgets,
        reason: '1.02 PopupMenuButton must be in the widget tree');

    // Flag (emoji text) must be visible — it is a Text widget inside the selector
    // The flag is rendered as text with fontSize 20
    final flagFinder = find.descendant(
      of: languageSelector,
      matching: find.byType(Text),
    );
    expect(flagFinder, findsOneWidget,
        reason: '1.03 Flag emoji must be visible in the LanguageSelector');
  });

  testWidgets('i18n: Sprache auf Englisch wechseln — Tabs zeigen englische Texte', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 2. SWITCH LANGUAGE TO ENGLISH ─────────────────────────────
    // Open LanguageSelector (tap on the flag widget)
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '2.01 LanguageSelector must be present');

    await tester.tap(languageSelector);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // PopupMenu must be open — "English" must be visible
    final englishOption = find.text('English');
    expect(englishOption, findsOneWidget,
        reason: '2.02 English option must be visible in the PopupMenu');

    // Auf "English" tappen
    await tester.tap(englishOption);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Tabs must now show English texts
    expect(find.text('Aktuell'), findsWidgets,
        reason: '2.03 Tab "Recent" must be visible after switching language to EN');
    expect(find.text('Favorites'), findsWidgets,
        reason: '2.04 Tab "Favorites" must be visible after switching language to EN');
    expect(find.text('Contacts'), findsWidgets,
        reason: '2.05 Tab "Contacts" must be visible after switching language to EN');
    expect(find.text('Groups'), findsWidgets,
        reason: '2.06 Tab "Groups" must be visible after switching language to EN');
    expect(find.text('Kanäle'), findsWidgets,
        reason: '2.07 Tab "Channels" must be visible after switching language to EN');
    expect(find.text('Requests'), findsWidgets,
        reason: '2.08 Tab "Requests" must be visible after switching language to EN');

    // German texts must NO LONGER be visible
    expect(find.text('Aktuell'), findsNothing,
        reason: '2.09 German tab "Aktuell" must no longer be visible after switching to EN');
    expect(find.text('Gruppen'), findsNothing,
        reason: '2.10 German tab "Gruppen" must no longer be visible after switching to EN');
    expect(find.text('Anfragen'), findsNothing,
        reason: '2.11 German tab "Anfragen" must no longer be visible after switching to EN');
  });

  testWidgets('i18n: Sprache auf Spanisch wechseln — Tabs zeigen spanische Texte', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 3. SWITCH LANGUAGE TO SPANISH ────────────────────────────────
    // First open LanguageSelector
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '3.01 LanguageSelector must be present');

    await tester.tap(languageSelector);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Auf "Espanol" tappen
    final spanishOption = find.text('Español');
    expect(spanishOption, findsOneWidget,
        reason: '3.02 Español option must be visible in the PopupMenu');

    await tester.tap(spanishOption);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Tabs must now show Spanish texts
    expect(find.text('Recientes'), findsWidgets,
        reason: '3.03 Tab "Recientes" must be visible after switching language to ES');
    expect(find.text('Favoritos'), findsWidgets,
        reason: '3.04 Tab "Favoritos" must be visible after switching language to ES');
    expect(find.text('Contactos'), findsWidgets,
        reason: '3.05 Tab "Contactos" must be visible after switching language to ES');
    expect(find.text('Grupos'), findsWidgets,
        reason: '3.06 Tab "Grupos" must be visible after switching language to ES');
    expect(find.text('Canales'), findsWidgets,
        reason: '3.07 Tab "Canales" must be visible after switching language to ES');
    expect(find.text('Solicitudes'), findsWidgets,
        reason: '3.08 Tab "Solicitudes" must be visible after switching language to ES');

    // English texts must NO LONGER be visible
    expect(find.text('Aktuell'), findsNothing,
        reason: '3.09 English tab "Recent" must no longer be visible after switching to ES');
    expect(find.text('Groups'), findsNothing,
        reason: '3.10 English tab "Groups" must no longer be visible after switching to ES');
    expect(find.text('Requests'), findsNothing,
        reason: '3.11 English tab "Requests" must no longer be visible after switching to ES');
  });

  testWidgets('i18n: Sprache zurueck auf Deutsch — Tabs zeigen deutsche Texte', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 4. LANGUAGE BACK TO GERMAN ───────────────────────────────────
    // Open LanguageSelector
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '4.01 LanguageSelector must be present');

    await tester.tap(languageSelector);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Auf "Deutsch" tappen
    final germanOption = find.text('Deutsch');
    expect(germanOption, findsOneWidget,
        reason: '4.02 "Deutsch" option must be visible in the PopupMenu');

    await tester.tap(germanOption);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Tabs must now show German texts
    expect(find.text('Aktuell'), findsWidgets,
        reason: '4.03 Tab "Aktuell" must be visible after switching language to DE');
    expect(find.text('Favoriten'), findsWidgets,
        reason: '4.04 Tab "Favoriten" must be visible after switching language to DE');
    expect(find.text('Kontakte'), findsWidgets,
        reason: '4.05 Tab "Kontakte" must be visible after switching language to DE');
    expect(find.text('Gruppen'), findsWidgets,
        reason: '4.06 Tab "Gruppen" must be visible after switching language to DE');
    expect(find.text('Kanäle'), findsWidgets,
        reason: '4.07 Tab "Kanäle" must be visible after switching language to DE');
    expect(find.text('Anfragen'), findsWidgets,
        reason: '4.08 Tab "Anfragen" must be visible after switching language to DE');

    // Spanish texts must NO LONGER be visible
    expect(find.text('Recientes'), findsNothing,
        reason: '4.09 Spanish tab "Recientes" must no longer be visible after switching to DE');
    expect(find.text('Grupos'), findsNothing,
        reason: '4.10 Spanish tab "Grupos" must no longer be visible after switching to DE');
    expect(find.text('Solicitudes'), findsNothing,
        reason: '4.11 Spanish tab "Solicitudes" must no longer be visible after switching to DE');
  });

  testWidgets('i18n: Network Stats Screen — Ueberschriften in aktueller Sprache', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 5. NETWORK STATS SCREEN IN CURRENT LANGUAGE ─────────────────
    // Make sure we are in German
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '5.01 LanguageSelector must be present');

    // First switch to German (for a consistent initial state)
    await tester.tap(languageSelector);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final germanOption = find.text('Deutsch');
    if (germanOption.evaluate().isNotEmpty) {
      await tester.tap(germanOption);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } else {
      // Close PopupMenu if German was not found
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    // Open Network Stats (bar_chart icon button)
    final statsButton = find.byIcon(Icons.bar_chart);
    expect(statsButton, findsOneWidget,
        reason: '5.02 Network Stats button (bar_chart) must be visible in the AppBar');

    await tester.tap(statsButton);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Title must be "Netzwerkstatistik" (German)
    expect(find.text('Netzwerkstatistik'), findsOneWidget,
        reason: '5.03 Title "Netzwerkstatistik" must be visible in DE');

    // Check headings
    expect(find.text('Netzwerk-Gesundheit'), findsOneWidget,
        reason: '5.04 "Netzwerk-Gesundheit" section must be visible in DE');

    // Navigate back
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Now switch to English and check again
    await tester.tap(find.byType(LanguageSelector));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final englishOption = find.text('English');
    expect(englishOption, findsOneWidget,
        reason: '5.05 English option must be visible in the PopupMenu');
    await tester.tap(englishOption);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Open Network Stats again
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Title must now be "Network Statistics" (English)
    expect(find.text('Network Statistics'), findsOneWidget,
        reason: '5.06 Title "Network Statistics" must be visible in EN');

    // Check headings
    expect(find.text('Network Health'), findsOneWidget,
        reason: '5.07 "Network Health" section must be visible in EN');

    // Navigate back
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Set language back to German (cleanup)
    await tester.tap(find.byType(LanguageSelector));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final germanReset = find.text('Deutsch');
    if (germanReset.evaluate().isNotEmpty) {
      await tester.tap(germanReset);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
  });

  testWidgets('i18n: Settings Screen — Ueberschriften in aktueller Sprache', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 6. SETTINGS SCREEN IN CURRENT LANGUAGE ──────────────────────
    // Make sure we are in German
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '6.01 LanguageSelector must be present');

    await tester.tap(languageSelector);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final germanOption = find.text('Deutsch');
    if (germanOption.evaluate().isNotEmpty) {
      await tester.tap(germanOption);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } else {
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    // Open settings (settings tooltip in German)
    final settingsButton = find.byIcon(Icons.settings);
    expect(settingsButton, findsOneWidget,
        reason: '6.02 Settings button must be visible in the AppBar');

    await tester.tap(settingsButton);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Title must be "Einstellungen" (German)
    expect(find.text('Einstellungen'), findsWidgets,
        reason: '6.03 Title "Einstellungen" must be visible in DE');

    // Check section headings (German)
    expect(find.text('Profil'), findsOneWidget,
        reason: '6.04 Section "Profil" must be visible in DE');
    expect(find.text('Netzwerk'), findsOneWidget,
        reason: '6.05 Section "Netzwerk" must be visible in DE');
    expect(find.text('Darstellung'), findsOneWidget,
        reason: '6.06 Section "Darstellung" must be visible in DE');

    // Scroll down for further sections
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      try {
        await tester.scrollUntilVisible(
          find.text('Sicherung'),
          200,
          scrollable: scrollables.last,
        );
        await tester.pumpAndSettle();
      } catch (_) {
        await tester.drag(scrollables.last, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
    }

    expect(find.text('Sicherung', skipOffstage: false), findsOneWidget,
        reason: '6.07 Section "Sicherung" must be visible in DE');
    expect(find.text('Info', skipOffstage: false), findsOneWidget,
        reason: '6.08 Section "Info" must be visible in DE');

    // Navigate back
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Now switch to English
    await tester.tap(find.byType(LanguageSelector));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final englishOption = find.text('English');
    expect(englishOption, findsOneWidget,
        reason: '6.09 English option must be visible in the PopupMenu');
    await tester.tap(englishOption);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Open Settings again
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Title must now be "Settings" (English)
    expect(find.text('Settings'), findsWidgets,
        reason: '6.10 Title "Settings" must be visible in EN');

    // Check section headings (English)
    expect(find.text('Profile'), findsOneWidget,
        reason: '6.11 Section "Profile" must be visible in EN');
    expect(find.text('Network'), findsOneWidget,
        reason: '6.12 Section "Network" must be visible in EN');
    expect(find.text('Appearance'), findsOneWidget,
        reason: '6.13 Section "Appearance" must be visible in EN');

    // Scroll down for further sections
    final scrollables2 = find.byType(Scrollable);
    if (scrollables2.evaluate().isNotEmpty) {
      try {
        await tester.scrollUntilVisible(
          find.text('Backup'),
          200,
          scrollable: scrollables2.last,
        );
        await tester.pumpAndSettle();
      } catch (_) {
        await tester.drag(scrollables2.last, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
    }

    expect(find.text('Backup', skipOffstage: false), findsOneWidget,
        reason: '6.14 Section "Backup" must be visible in EN');
    expect(find.text('Info', skipOffstage: false), findsOneWidget,
        reason: '6.15 Section "Info" must be visible in EN');

    // Navigate back
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Set language back to German (cleanup)
    await tester.tap(find.byType(LanguageSelector));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final germanReset = find.text('Deutsch');
    if (germanReset.evaluate().isNotEmpty) {
      await tester.tap(germanReset);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
  });
}
