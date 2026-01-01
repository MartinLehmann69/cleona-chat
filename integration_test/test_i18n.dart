// Integration Tests: Internationalisierung (i18n) — Sprachwechsel und Uebersetzungen
// Testet LanguageSelector, Sprachwechsel (EN, ES, DE), Tabs, Settings und Network Stats.
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
        reason: '1.01 LanguageSelector Widget muss im AppBar vorhanden sein');

    // LanguageSelector ist ein PopupMenuButton — muss sichtbar sein
    final popupMenu = find.byType(PopupMenuButton<String>);
    expect(popupMenu, findsWidgets,
        reason: '1.02 PopupMenuButton muss im Widget-Baum sein');

    // Flagge (Emoji-Text) muss sichtbar sein — es ist ein Text-Widget innerhalb des Selectors
    // Die Flagge wird als Text mit fontSize 20 gerendert
    final flagFinder = find.descendant(
      of: languageSelector,
      matching: find.byType(Text),
    );
    expect(flagFinder, findsOneWidget,
        reason: '1.03 Flaggen-Emoji muss im LanguageSelector sichtbar sein');
  });

  testWidgets('i18n: Sprache auf Englisch wechseln — Tabs zeigen englische Texte', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 2. SPRACHE AUF ENGLISCH WECHSELN ─────────────────────────────
    // LanguageSelector oeffnen (tap auf das Flaggen-Widget)
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '2.01 LanguageSelector muss vorhanden sein');

    await tester.tap(languageSelector);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // PopupMenu muss geoeffnet sein — "English" muss sichtbar sein
    final englishOption = find.text('English');
    expect(englishOption, findsOneWidget,
        reason: '2.02 English Option muss im PopupMenu sichtbar sein');

    // Auf "English" tappen
    await tester.tap(englishOption);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Tabs muessen jetzt englische Texte zeigen
    expect(find.text('Aktuell'), findsWidgets,
        reason: '2.03 Tab "Recent" muss nach Sprachwechsel auf EN sichtbar sein');
    expect(find.text('Favorites'), findsWidgets,
        reason: '2.04 Tab "Favorites" muss nach Sprachwechsel auf EN sichtbar sein');
    expect(find.text('Contacts'), findsWidgets,
        reason: '2.05 Tab "Contacts" muss nach Sprachwechsel auf EN sichtbar sein');
    expect(find.text('Groups'), findsWidgets,
        reason: '2.06 Tab "Groups" muss nach Sprachwechsel auf EN sichtbar sein');
    expect(find.text('Kanäle'), findsWidgets,
        reason: '2.07 Tab "Channels" muss nach Sprachwechsel auf EN sichtbar sein');
    expect(find.text('Requests'), findsWidgets,
        reason: '2.08 Tab "Requests" muss nach Sprachwechsel auf EN sichtbar sein');

    // Deutsche Texte duerfen NICHT mehr sichtbar sein
    expect(find.text('Aktuell'), findsNothing,
        reason: '2.09 Deutscher Tab "Aktuell" darf nach EN-Wechsel nicht mehr sichtbar sein');
    expect(find.text('Gruppen'), findsNothing,
        reason: '2.10 Deutscher Tab "Gruppen" darf nach EN-Wechsel nicht mehr sichtbar sein');
    expect(find.text('Anfragen'), findsNothing,
        reason: '2.11 Deutscher Tab "Anfragen" darf nach EN-Wechsel nicht mehr sichtbar sein');
  });

  testWidgets('i18n: Sprache auf Spanisch wechseln — Tabs zeigen spanische Texte', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 3. SPRACHE AUF SPANISCH WECHSELN ─────────────────────────────
    // Zuerst LanguageSelector oeffnen
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '3.01 LanguageSelector muss vorhanden sein');

    await tester.tap(languageSelector);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Auf "Espanol" tappen
    final spanishOption = find.text('Español');
    expect(spanishOption, findsOneWidget,
        reason: '3.02 Español Option muss im PopupMenu sichtbar sein');

    await tester.tap(spanishOption);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Tabs muessen jetzt spanische Texte zeigen
    expect(find.text('Recientes'), findsWidgets,
        reason: '3.03 Tab "Recientes" muss nach Sprachwechsel auf ES sichtbar sein');
    expect(find.text('Favoritos'), findsWidgets,
        reason: '3.04 Tab "Favoritos" muss nach Sprachwechsel auf ES sichtbar sein');
    expect(find.text('Contactos'), findsWidgets,
        reason: '3.05 Tab "Contactos" muss nach Sprachwechsel auf ES sichtbar sein');
    expect(find.text('Grupos'), findsWidgets,
        reason: '3.06 Tab "Grupos" muss nach Sprachwechsel auf ES sichtbar sein');
    expect(find.text('Canales'), findsWidgets,
        reason: '3.07 Tab "Canales" muss nach Sprachwechsel auf ES sichtbar sein');
    expect(find.text('Solicitudes'), findsWidgets,
        reason: '3.08 Tab "Solicitudes" muss nach Sprachwechsel auf ES sichtbar sein');

    // Englische Texte duerfen NICHT mehr sichtbar sein
    expect(find.text('Aktuell'), findsNothing,
        reason: '3.09 Englischer Tab "Recent" darf nach ES-Wechsel nicht mehr sichtbar sein');
    expect(find.text('Groups'), findsNothing,
        reason: '3.10 Englischer Tab "Groups" darf nach ES-Wechsel nicht mehr sichtbar sein');
    expect(find.text('Requests'), findsNothing,
        reason: '3.11 Englischer Tab "Requests" darf nach ES-Wechsel nicht mehr sichtbar sein');
  });

  testWidgets('i18n: Sprache zurueck auf Deutsch — Tabs zeigen deutsche Texte', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 4. SPRACHE ZURUECK AUF DEUTSCH ───────────────────────────────
    // LanguageSelector oeffnen
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '4.01 LanguageSelector muss vorhanden sein');

    await tester.tap(languageSelector);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Auf "Deutsch" tappen
    final deutschOption = find.text('Deutsch');
    expect(deutschOption, findsOneWidget,
        reason: '4.02 Deutsch Option muss im PopupMenu sichtbar sein');

    await tester.tap(deutschOption);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Tabs muessen jetzt deutsche Texte zeigen
    expect(find.text('Aktuell'), findsWidgets,
        reason: '4.03 Tab "Aktuell" muss nach Sprachwechsel auf DE sichtbar sein');
    expect(find.text('Favoriten'), findsWidgets,
        reason: '4.04 Tab "Favoriten" muss nach Sprachwechsel auf DE sichtbar sein');
    expect(find.text('Kontakte'), findsWidgets,
        reason: '4.05 Tab "Kontakte" muss nach Sprachwechsel auf DE sichtbar sein');
    expect(find.text('Gruppen'), findsWidgets,
        reason: '4.06 Tab "Gruppen" muss nach Sprachwechsel auf DE sichtbar sein');
    expect(find.text('Kanäle'), findsWidgets,
        reason: '4.07 Tab "Kanäle" muss nach Sprachwechsel auf DE sichtbar sein');
    expect(find.text('Anfragen'), findsWidgets,
        reason: '4.08 Tab "Anfragen" muss nach Sprachwechsel auf DE sichtbar sein');

    // Spanische Texte duerfen NICHT mehr sichtbar sein
    expect(find.text('Recientes'), findsNothing,
        reason: '4.09 Spanischer Tab "Recientes" darf nach DE-Wechsel nicht mehr sichtbar sein');
    expect(find.text('Grupos'), findsNothing,
        reason: '4.10 Spanischer Tab "Grupos" darf nach DE-Wechsel nicht mehr sichtbar sein');
    expect(find.text('Solicitudes'), findsNothing,
        reason: '4.11 Spanischer Tab "Solicitudes" darf nach DE-Wechsel nicht mehr sichtbar sein');
  });

  testWidgets('i18n: Network Stats Screen — Ueberschriften in aktueller Sprache', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 5. NETWORK STATS SCREEN IN AKTUELLER SPRACHE ─────────────────
    // Sicherstellen dass wir auf Deutsch sind
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '5.01 LanguageSelector muss vorhanden sein');

    // Erst auf Deutsch wechseln (fuer konsistenten Ausgangszustand)
    await tester.tap(languageSelector);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final deutschOption = find.text('Deutsch');
    if (deutschOption.evaluate().isNotEmpty) {
      await tester.tap(deutschOption);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } else {
      // PopupMenu schliessen falls Deutsch nicht gefunden
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    // Network Stats oeffnen (bar_chart Icon-Button)
    final statsButton = find.byIcon(Icons.bar_chart);
    expect(statsButton, findsOneWidget,
        reason: '5.02 Network Stats Button (bar_chart) muss im AppBar sichtbar sein');

    await tester.tap(statsButton);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Titel muss "Netzwerkstatistik" sein (Deutsch)
    expect(find.text('Netzwerkstatistik'), findsOneWidget,
        reason: '5.03 Titel "Netzwerkstatistik" muss auf DE sichtbar sein');

    // Ueberschriften pruefen
    expect(find.text('Netzwerk-Gesundheit'), findsOneWidget,
        reason: '5.04 "Netzwerk-Gesundheit" Sektion muss auf DE sichtbar sein');

    // Zurueck navigieren
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Jetzt auf Englisch wechseln und erneut pruefen
    await tester.tap(find.byType(LanguageSelector));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final englishOption = find.text('English');
    expect(englishOption, findsOneWidget,
        reason: '5.05 English Option muss im PopupMenu sichtbar sein');
    await tester.tap(englishOption);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Network Stats erneut oeffnen
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Titel muss jetzt "Network Statistics" sein (Englisch)
    expect(find.text('Network Statistics'), findsOneWidget,
        reason: '5.06 Titel "Network Statistics" muss auf EN sichtbar sein');

    // Ueberschriften pruefen
    expect(find.text('Network Health'), findsOneWidget,
        reason: '5.07 "Network Health" Sektion muss auf EN sichtbar sein');

    // Zurueck navigieren
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Sprache zurueck auf Deutsch setzen (Cleanup)
    await tester.tap(find.byType(LanguageSelector));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final deutschReset = find.text('Deutsch');
    if (deutschReset.evaluate().isNotEmpty) {
      await tester.tap(deutschReset);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
  });

  testWidgets('i18n: Settings Screen — Ueberschriften in aktueller Sprache', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 6. SETTINGS SCREEN IN AKTUELLER SPRACHE ──────────────────────
    // Sicherstellen dass wir auf Deutsch sind
    final languageSelector = find.byType(LanguageSelector);
    expect(languageSelector, findsOneWidget,
        reason: '6.01 LanguageSelector muss vorhanden sein');

    await tester.tap(languageSelector);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final deutschOption = find.text('Deutsch');
    if (deutschOption.evaluate().isNotEmpty) {
      await tester.tap(deutschOption);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } else {
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    // Settings oeffnen (Einstellungen Tooltip auf Deutsch)
    final settingsButton = find.byIcon(Icons.settings);
    expect(settingsButton, findsOneWidget,
        reason: '6.02 Settings Button muss im AppBar sichtbar sein');

    await tester.tap(settingsButton);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Titel muss "Einstellungen" sein (Deutsch)
    expect(find.text('Einstellungen'), findsWidgets,
        reason: '6.03 Titel "Einstellungen" muss auf DE sichtbar sein');

    // Sektions-Ueberschriften pruefen (Deutsch)
    expect(find.text('Profil'), findsOneWidget,
        reason: '6.04 Sektion "Profil" muss auf DE sichtbar sein');
    expect(find.text('Netzwerk'), findsOneWidget,
        reason: '6.05 Sektion "Netzwerk" muss auf DE sichtbar sein');
    expect(find.text('Darstellung'), findsOneWidget,
        reason: '6.06 Sektion "Darstellung" muss auf DE sichtbar sein');

    // Scroll nach unten fuer weitere Sektionen
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
        reason: '6.07 Sektion "Sicherung" muss auf DE sichtbar sein');
    expect(find.text('Info', skipOffstage: false), findsOneWidget,
        reason: '6.08 Sektion "Info" muss auf DE sichtbar sein');

    // Zurueck navigieren
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Jetzt auf Englisch wechseln
    await tester.tap(find.byType(LanguageSelector));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final englishOption = find.text('English');
    expect(englishOption, findsOneWidget,
        reason: '6.09 English Option muss im PopupMenu sichtbar sein');
    await tester.tap(englishOption);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Settings erneut oeffnen
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Titel muss jetzt "Settings" sein (Englisch)
    expect(find.text('Settings'), findsWidgets,
        reason: '6.10 Titel "Settings" muss auf EN sichtbar sein');

    // Sektions-Ueberschriften pruefen (Englisch)
    expect(find.text('Profile'), findsOneWidget,
        reason: '6.11 Sektion "Profile" muss auf EN sichtbar sein');
    expect(find.text('Network'), findsOneWidget,
        reason: '6.12 Sektion "Network" muss auf EN sichtbar sein');
    expect(find.text('Appearance'), findsOneWidget,
        reason: '6.13 Sektion "Appearance" muss auf EN sichtbar sein');

    // Scroll nach unten fuer weitere Sektionen
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
        reason: '6.14 Sektion "Backup" muss auf EN sichtbar sein');
    expect(find.text('Info', skipOffstage: false), findsOneWidget,
        reason: '6.15 Sektion "Info" muss auf EN sichtbar sein');

    // Zurueck navigieren
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Sprache zurueck auf Deutsch setzen (Cleanup)
    await tester.tap(find.byType(LanguageSelector));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final deutschReset = find.text('Deutsch');
    if (deutschReset.evaluate().isNotEmpty) {
      await tester.tap(deutschReset);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
  });
}
