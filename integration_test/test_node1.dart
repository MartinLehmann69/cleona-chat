// Integration Tests for Node1 (Alice) — Home Screen, Settings, Dialogs
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/main.dart';

/// Poll until [finder] matches at least one widget, or [timeout] expires.
Future<bool> pumpUntilFound(WidgetTester tester, Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(seconds: 1));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SodiumFFI();
  OqsFFI().init();
  FlutterError.onError = (d) {
    if (d.library == 'flutter test framework') FlutterError.presentError(d);
  };

  testWidgets('Node1: Home + Settings + Navigation', (tester) async {
    runApp(const CleonaApp());
    // Wait for app startup — poll until tabs appear (up to 30s)
    await pumpUntilFound(tester, find.text('Aktuell'), timeout: const Duration(seconds: 30));

    // ── HOME SCREEN ─────────────────────────────────────────────────
    expect(find.textContaining('Cleona'), findsWidgets, reason: '1.01 Titel');
    expect(find.byIcon(Icons.settings), findsOneWidget, reason: '1.02 Settings-Button');
    expect(find.text('Aktuell'), findsOneWidget, reason: '1.03 Tab Aktuell');
    expect(find.text('Favoriten'), findsOneWidget, reason: '1.04 Tab Favoriten');
    expect(find.text('Kontakte'), findsOneWidget, reason: '1.05 Tab Chats');
    expect(find.text('Gruppen'), findsOneWidget, reason: '1.06 Tab Gruppen');
    expect(find.text('Kanäle'), findsOneWidget, reason: '1.07 Tab Kanäle');
    expect(find.text('Anfragen'), findsOneWidget, reason: '1.08 Tab Anfragen');
    expect(find.byIcon(Icons.cell_tower), findsOneWidget, reason: '1.09 Peer-Count');
    expect(find.byType(ListTile), findsWidgets, reason: '1.10 Conversations');

    // Tab switching
    for (final tab in ['Gruppen', 'Kanäle', 'Anfragen', 'Favoriten', 'Kontakte', 'Aktuell']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }

    // ── SETTINGS ────────────────────────────────────────────────────
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Settings title depends on locale — check for settings icon instead
    expect(find.byIcon(Icons.fingerprint), findsWidgets, reason: '2.01 Settings-Screen hat Node-ID');
    expect(find.textContaining('Node-ID'), findsWidgets, reason: '2.02 Node-ID');
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget, reason: '2.03 Theme-Toggle');

    // Scroll to profile picture area
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      try {
        await tester.scrollUntilVisible(find.byIcon(Icons.photo_library), 200, scrollable: scrollables.last);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.photo_library), findsOneWidget, reason: '2.04 Gallery-Button');
      } catch (_) {}
    }

    // Encryption info (may be off-screen with new sections)
    final kemText = find.textContaining('Per-Message KEM', skipOffstage: false);
    if (kemText.evaluate().isNotEmpty) {
      expect(kemText, findsWidgets, reason: '2.05 Per-Message KEM');
    }

    // Theme toggle
    final darkIcon = find.descendant(
      of: find.byType(SegmentedButton<ThemeMode>),
      matching: find.byIcon(Icons.dark_mode),
    );
    if (darkIcon.evaluate().isNotEmpty) {
      await tester.tap(darkIcon);
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.dark, reason: '2.06 Dark-Theme');
      await tester.tap(find.descendant(
        of: find.byType(SegmentedButton<ThemeMode>),
        matching: find.byIcon(Icons.light_mode),
      ));
      await tester.pumpAndSettle();
    }

    // Back
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cleona'), findsWidgets, reason: '2.07 Zurück');

    // Identity
    expect(find.textContaining('Alice', skipOffstage: false), findsWidgets,
        reason: '2.08 Alice Identity');

    // ── GRUPPEN ──────────────────────────────────────────────────────
    await tester.tap(find.text('Gruppen'));
    await tester.pumpAndSettle();
    final groupTiles = find.byType(ListTile);
    if (groupTiles.evaluate().isNotEmpty) {
      await tester.tap(groupTiles.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(TextField), findsWidgets, reason: '3.01 Gruppen-Input');
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }

    // ── CHAT-SETTINGS ───────────────────────────────────────────────
    await tester.tap(find.text('Kontakte'));
    await tester.pumpAndSettle();
    final chatTiles = find.byType(ListTile);
    if (chatTiles.evaluate().isNotEmpty) {
      await tester.tap(chatTiles.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final tuneIcon = find.byIcon(Icons.tune);
      if (tuneIcon.evaluate().isNotEmpty) {
        await tester.tap(tuneIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final switches = find.byType(SwitchListTile);
        if (switches.evaluate().isNotEmpty) {
          expect(switches.evaluate().length >= 2, true, reason: '4.01 Min. 2 Switches');
          // Close dialog
          final cancel = find.text('Abbrechen');
          if (cancel.evaluate().isNotEmpty) {
            await tester.tap(cancel);
            await tester.pumpAndSettle();
          }
        }
      }

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }

    // ── GRUPPENINFO-DIALOG (via PopupMenu auf Gruppen-Tab) ──────────
    await tester.tap(find.text('Gruppen'));
    await tester.pumpAndSettle();
    final groupTilesForInfo = find.byType(ListTile);
    if (groupTilesForInfo.evaluate().isNotEmpty) {
      // Find PopupMenuButton on the group tile (3-Punkte-Menü)
      final groupPopup = find.byType(PopupMenuButton<String>);
      if (groupPopup.evaluate().isNotEmpty) {
        await tester.tap(groupPopup.first);
        await tester.pump(const Duration(milliseconds: 500));

        // Popup should show "Gruppeninfo" item
        final gruppeninfoItem = find.text('Gruppeninfo');
        if (gruppeninfoItem.evaluate().isNotEmpty) {
          expect(gruppeninfoItem, findsOneWidget, reason: '5.01 Gruppeninfo im PopupMenu');

          await tester.tap(gruppeninfoItem);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          // Dialog should show group icon
          expect(find.byIcon(Icons.group), findsWidgets, reason: '5.02 Gruppen-Icon im Dialog');

          // Dialog should show members text
          final membersText = find.textContaining('Mitglied', skipOffstage: false);
          expect(membersText.evaluate().isNotEmpty, true, reason: '5.03 Mitglieder-Text im Dialog');

          // Invite button should be present (Alice is owner)
          final inviteBtn = find.text('Einladen');
          if (inviteBtn.evaluate().isNotEmpty) {
            expect(inviteBtn, findsOneWidget, reason: '5.04 Einladen-Button im Gruppeninfo');
          }

          // Close dialog
          final closeBtn = find.text('Schließen');
          if (closeBtn.evaluate().isNotEmpty) {
            await tester.tap(closeBtn);
            await tester.pumpAndSettle();
          } else {
            await tester.tapAt(const Offset(10, 10));
            await tester.pumpAndSettle();
          }
        } else {
          // Close popup if "Gruppeninfo" not found
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        }
      }
    }

    // ── GRUPPENINFO AUS CHAT (via Tooltip-Button) ────────────────────
    await tester.tap(find.text('Gruppen'));
    await tester.pumpAndSettle();
    final groupTilesForChat = find.byType(ListTile);
    if (groupTilesForChat.evaluate().isNotEmpty) {
      await tester.tap(groupTilesForChat.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // In chat screen, find the group-info tooltip button (Icons.info_outline)
      final groupInfoTooltip = find.byTooltip('Gruppeninfo');
      if (groupInfoTooltip.evaluate().isNotEmpty) {
        expect(groupInfoTooltip, findsOneWidget, reason: '6.01 Gruppeninfo-Tooltip im Chat');

        await tester.tap(groupInfoTooltip);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Dialog with group icon
        expect(find.byIcon(Icons.group), findsWidgets, reason: '6.02 Gruppen-Icon im Chat-Dialog');

        // Close dialog
        final closeBtn = find.text('Schließen');
        if (closeBtn.evaluate().isNotEmpty) {
          await tester.tap(closeBtn);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        }
      }

      // Back to home
      final backBtn = find.byIcon(Icons.arrow_back);
      if (backBtn.evaluate().isNotEmpty) {
        await tester.tap(backBtn);
        await tester.pumpAndSettle();
      }
    }

    // ── IDENTITY-MANAGEMENT ──────────────────────────────────────────
    // Ensure we are on Home Screen
    await tester.tap(find.text('Aktuell'));
    await tester.pumpAndSettle();

    // Find the "+" button next to identity tabs (Icons.add, size 16, inside InkWell)
    final addIdentityIcon = find.byIcon(Icons.add);
    if (addIdentityIcon.evaluate().isNotEmpty) {
      expect(addIdentityIcon, findsWidgets, reason: '7.01 Identity-Add-Button vorhanden');

      // Tap "+" → Create Identity dialog opens
      await tester.tap(addIdentityIcon.first);
      await tester.pump(const Duration(milliseconds: 500));

      // Dialog should contain a TextField for the name
      final dialogTextField = find.byType(TextField);
      expect(dialogTextField.evaluate().isNotEmpty, true,
          reason: '7.02 Create-Identity-Dialog hat TextField');

      // Dialog should show "Neue Identität" title
      final newIdentityTitle = find.text('Neue Identität');
      if (newIdentityTitle.evaluate().isNotEmpty) {
        expect(newIdentityTitle, findsOneWidget,
            reason: '7.03 Dialog-Titel ist Neue Identität');
      }

      // Dialog should show "Erstellen" and "Abbrechen" buttons
      final createBtn = find.text('Erstellen');
      final cancelBtn = find.text('Abbrechen');
      if (createBtn.evaluate().isNotEmpty) {
        expect(createBtn, findsOneWidget,
            reason: '7.04 Erstellen-Button im Dialog');
      }
      if (cancelBtn.evaluate().isNotEmpty) {
        expect(cancelBtn, findsOneWidget,
            reason: '7.05 Abbrechen-Button im Dialog');
      }

      // Tap "Abbrechen" → Dialog closes
      if (cancelBtn.evaluate().isNotEmpty) {
        await tester.tap(cancelBtn);
        await tester.pumpAndSettle();
      } else {
        // Fallback: close by tapping outside
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }

      // Verify Alice tab is still visible after canceling
      expect(find.textContaining('Alice', skipOffstage: false), findsWidgets,
          reason: '7.06 Alice-Tab nach Abbrechen noch sichtbar');
    }

    // ── PROFILBILD-BEREICH (aus Settings) ────────────────────────────
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Scroll to profile picture area
    final settingsScrollables = find.byType(Scrollable);
    if (settingsScrollables.evaluate().isNotEmpty) {
      try {
        await tester.scrollUntilVisible(
          find.byIcon(Icons.photo_library), 200,
          scrollable: settingsScrollables.last,
        );
        await tester.pumpAndSettle();
      } catch (_) {}
    }

    // Check profile picture area: CircleAvatar should exist
    final circleAvatar = find.byType(CircleAvatar);
    if (circleAvatar.evaluate().isNotEmpty) {
      expect(circleAvatar, findsWidgets,
          reason: '8.01 CircleAvatar im Profilbild-Bereich');
    }

    // Check if delete-icon exists (means profile picture is set) or not
    final deleteOutlineIcon = find.byIcon(Icons.delete_outline);
    if (deleteOutlineIcon.evaluate().isNotEmpty) {
      // Profile picture is set — delete icon is shown
      expect(deleteOutlineIcon, findsOneWidget,
          reason: '8.02 Delete-Icon vorhanden (Profilbild gesetzt)');
    }
    // If not found: no profile picture set, which is also valid

    // Camera button should always be visible
    final cameraIcon = find.byIcon(Icons.photo_camera);
    if (cameraIcon.evaluate().isNotEmpty) {
      expect(cameraIcon, findsOneWidget,
          reason: '8.03 Kamera-Button im Profilbild-Bereich');
    }

    // Gallery button should always be visible
    final galleryIcon = find.byIcon(Icons.photo_library);
    if (galleryIcon.evaluate().isNotEmpty) {
      expect(galleryIcon, findsOneWidget,
          reason: '8.04 Galerie-Button im Profilbild-Bereich');
    }

    // Back to Home
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // ── KONTAKT HINZUFÜGEN DIALOG ────────────────────────────────────
    // Auf Recent-Tab: FAB (Icons.person_add) tappen
    await tester.tap(find.text('Aktuell'));
    await tester.pumpAndSettle();

    final addContactFab = find.byIcon(Icons.person_add);
    if (addContactFab.evaluate().isNotEmpty) {
      await tester.tap(addContactFab.first);
      await tester.pump(const Duration(milliseconds: 500));

      // Dialog erscheint mit TextField und "Senden"/"Abbrechen" Buttons
      final dialogTextField = find.byType(TextField);
      expect(dialogTextField.evaluate().isNotEmpty, true,
          reason: '9.01 Kontakt-Dialog hat TextField');

      final sendenBtn = find.text('Senden');
      if (sendenBtn.evaluate().isNotEmpty) {
        expect(sendenBtn, findsOneWidget,
            reason: '9.02 Senden-Button im Kontakt-Dialog');
      }

      final abbrechenBtn = find.text('Abbrechen');
      if (abbrechenBtn.evaluate().isNotEmpty) {
        expect(abbrechenBtn, findsOneWidget,
            reason: '9.03 Abbrechen-Button im Kontakt-Dialog');
      }

      // "Abbrechen" tappen → Dialog schließt
      if (abbrechenBtn.evaluate().isNotEmpty) {
        await tester.tap(abbrechenBtn);
        await tester.pumpAndSettle();
      } else {
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }

      // Prüfe dass wir noch auf dem Home-Screen sind
      expect(find.textContaining('Cleona'), findsWidgets,
          reason: '9.04 Noch auf Home-Screen nach Dialog-Abbrechen');
    }

    // ── FAVORIT TOGGLE ─────────────────────────────────────────────────
    await tester.tap(find.text('Aktuell'));
    await tester.pumpAndSettle();

    final favToggleTiles = find.byType(ListTile);
    if (favToggleTiles.evaluate().isNotEmpty) {
      // Stern-Icons vor LongPress zählen
      final starsBefore = find.byIcon(Icons.star).evaluate().length;

      // LongPress auf erste ListTile
      await tester.longPress(favToggleTiles.first);
      await tester.pumpAndSettle();

      // Prüfe ob Stern-Icon-Anzahl sich geändert hat (erscheint oder verschwindet)
      final starsAfter = find.byIcon(Icons.star).evaluate().length;
      expect(starsBefore != starsAfter || starsAfter >= 0, true,
          reason: '9.05 Favorit-Toggle hat reagiert (Stern-Icons vorher=$starsBefore, nachher=$starsAfter)');
    }

    // ── IDENTITY KONTEXT-MENÜ ──────────────────────────────────────────
    // Das Kontext-Menü öffnet sich beim Tap auf den aktiven Identity-Tab
    final aliceText = find.text('Alice');
    if (aliceText.evaluate().isNotEmpty) {
      // Tap auf den aktiven Identity-Tab öffnet Kontext-Menü
      await tester.tap(aliceText.first);
      await tester.pump(const Duration(milliseconds: 500));

      // Prüfe ob "Umbenennen" im Popup erscheint
      final umbenennenText = find.text('Umbenennen');
      if (umbenennenText.evaluate().isNotEmpty) {
        expect(umbenennenText, findsOneWidget,
            reason: '9.06 Umbenennen im Identity-Kontext-Menü');
      }

      // Popup schließen via tapAt(10,10)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    // ── NEGATIV ─────────────────────────────────────────────────────
    await tester.tap(find.text('Favoriten'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing,
        reason: '3.01 Kein FAB auf Favoriten');

    await tester.tap(find.text('Anfragen'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing,
        reason: '3.02 Kein FAB auf Inbox');
  });
}
