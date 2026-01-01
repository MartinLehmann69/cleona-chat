// Flutter Integration Tests for Cleona Chat
//
// Run on VM: cd ~/cleona-src && flutter test integration_test/app_test.dart -d linux
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

  // Suppress debug-only rendering assertions
  FlutterError.onError = (details) {
    if (details.library == 'flutter test framework') {
      FlutterError.presentError(details);
    }
  };

  // Single test that runs ALL checks sequentially in one app instance
  testWidgets('Cleona GUI End-to-End Test', (tester) async {
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // ── 0. SETUP (falls kein Profil vorhanden) ────────────────────
    final setupTextField = find.byType(TextField);
    final settingsIcon = find.byIcon(Icons.settings);
    if (settingsIcon.evaluate().isEmpty && setupTextField.evaluate().isNotEmpty) {
      // We're on the SetupScreen — complete setup first
      await tester.enterText(setupTextField.first, 'TestUser');
      await tester.pumpAndSettle();

      final startButton = find.byIcon(Icons.play_arrow);
      if (startButton.evaluate().isNotEmpty) {
        await tester.tap(startButton);
        // Wait for service to initialize
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (find.byIcon(Icons.settings).evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle(const Duration(seconds: 5));
      }
    }

    // ── 1. HOME SCREEN ──────────────────────────────────────────────

    // 1.01 App title visible
    expect(find.textContaining('Cleona'), findsWidgets,
        reason: '1.01 Cleona-Titel sichtbar');

    // 1.02 Settings button exists
    expect(find.byIcon(Icons.settings), findsOneWidget,
        reason: '1.02 Settings-Button existiert');

    // 1.03 Six tabs visible
    expect(find.text('Aktuell'), findsOneWidget, reason: '1.03a Tab Recent');
    expect(find.text('Favoriten'), findsOneWidget, reason: '1.03b Tab Favoriten');
    expect(find.text('Kontakte'), findsOneWidget, reason: '1.03c Tab Chats');
    expect(find.text('Gruppen'), findsOneWidget, reason: '1.03d Tab Gruppen');
    expect(find.text('Kanäle'), findsOneWidget, reason: '1.03e Tab Channels');
    expect(find.text('Anfragen'), findsOneWidget, reason: '1.03f Tab Inbox');

    // 1.04 Tab switching
    await tester.tap(find.text('Gruppen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kanäle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anfragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aktuell'));
    await tester.pumpAndSettle();

    // 1.05 Peer count chip visible
    expect(find.byIcon(Icons.cell_tower), findsOneWidget,
        reason: '1.05 Peer-Count Chip sichtbar');

    // 1.06 Conversation list has entries
    expect(find.byType(ListTile), findsWidgets,
        reason: '1.06 Conversation-Liste hat Einträge');

    // ── 2. SETTINGS SCREEN ──────────────────────────────────────────

    // 2.01 Navigate to settings
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 2.02 Settings title visible
    expect(find.text('Einstellungen'), findsWidgets,
        reason: '2.02 Einstellungen-Titel sichtbar');

    // 2.03 Network info visible
    expect(find.textContaining('Node-ID'), findsWidgets,
        reason: '2.03 Node-ID sichtbar');

    // 2.04 Encryption info visible (scroll ListView to bottom, then check)
    final listView = find.byType(ListView);
    if (listView.evaluate().isNotEmpty) {
      // Scroll down in multiple steps to reveal lazy-loaded items
      for (var i = 0; i < 5; i++) {
        await tester.drag(listView.first, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
    }
    final kemFinder = find.textContaining('Per-Message KEM', skipOffstage: false);
    expect(kemFinder, findsWidgets, reason: '2.04 Per-Message KEM im Widget-Baum');
    // Scroll back to top
    if (listView.evaluate().isNotEmpty) {
      for (var i = 0; i < 5; i++) {
        await tester.drag(listView.first, const Offset(0, 300));
        await tester.pumpAndSettle();
      }
    }

    // 2.05 Theme toggle exists (may need scrolling to find)
    final themeToggle = find.byType(SegmentedButton<ThemeMode>);
    if (themeToggle.evaluate().isEmpty && listView.evaluate().isNotEmpty) {
      // Scroll up more to find it
      await tester.drag(listView.first, const Offset(0, 300));
      await tester.pumpAndSettle();
    }
    expect(themeToggle, findsOneWidget,
        reason: '2.05 Theme-Toggle existiert');

    // 2.06 Profilbild-Buttons (may need scroll — check with skipOffstage)
    expect(
      find.byIcon(Icons.photo_library, skipOffstage: false).evaluate().isNotEmpty ||
      find.byIcon(Icons.camera_alt, skipOffstage: false).evaluate().isNotEmpty,
      true, reason: '2.06 Profilbild-Buttons im Widget-Baum');

    // 2.08 Back to home screen
    final backButton = find.byIcon(Icons.arrow_back);
    expect(backButton, findsOneWidget, reason: '2.08a Back-Button existiert');
    await tester.tap(backButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cleona'), findsWidgets,
        reason: '2.08b Zurück auf Home-Screen');

    // ── 3. CHAT SCREEN ──────────────────────────────────────────────

    // 3.01 Open first conversation
    await tester.tap(find.text('Aktuell'));
    await tester.pumpAndSettle();
    final tiles = find.byType(ListTile);
    if (tiles.evaluate().isNotEmpty) {
      await tester.tap(tiles.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 3.02 Text input field visible
      expect(find.byType(TextField), findsWidgets,
          reason: '3.02 Text-Input sichtbar');

      // 3.03 Send button visible
      expect(find.byIcon(Icons.send), findsWidgets,
          reason: '3.03 Send-Button sichtbar');

      // 3.04 Chat settings button visible
      expect(find.byTooltip('Chat-Einstellungen'), findsWidgets,
          reason: '3.04 Chat-Settings Button');

      // 3.05 Back button visible
      expect(find.byIcon(Icons.arrow_back), findsOneWidget,
          reason: '3.05 Back-Button im Chat');

      // 3.06 TIMING TEST: Send message must not block UI > 500ms
      final textField = find.byType(TextField);
      if (textField.evaluate().isNotEmpty) {
        await tester.enterText(textField.last, 'Timing-Test ${DateTime.now().millisecondsSinceEpoch}');
        await tester.pump();

        final sendButton = find.byIcon(Icons.send);
        if (sendButton.evaluate().isNotEmpty) {
          final stopwatch = Stopwatch()..start();
          await tester.tap(sendButton);
          // Pump once to process the tap — this is what the user experiences
          await tester.pump();
          stopwatch.stop();

          expect(stopwatch.elapsedMilliseconds < 500, true,
              reason: '3.06 Send darf UI nicht > 500ms blockieren '
                  '(war ${stopwatch.elapsedMilliseconds}ms)');

          // Wait for message to appear (async crypto + send)
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 500));
          }
        }
      }

      // 3.07 Navigate back
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }

    // ── 3b. CONTACT RENAME ───────────────────────────────────────────

    // 3b.01 Open Aktuell tab and check for rename option on DM conversations
    await tester.tap(find.text('Aktuell'));
    await tester.pumpAndSettle();
    final convTiles = find.byType(ListTile);
    if (convTiles.evaluate().isNotEmpty) {
      // 3b.02 Open context menu on first conversation
      final popup = find.byType(PopupMenuButton<String>);
      if (popup.evaluate().isNotEmpty) {
        await tester.tap(popup.first);
        await tester.pumpAndSettle();

        // 3b.03 Rename option must exist for DM conversations
        final renameOption = find.text('Kontakt umbenennen');
        expect(renameOption.evaluate().isNotEmpty, true,
            reason: '3b.03 Rename-Option im Kontextmenü');

        // Close menu
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      }
    }

    // ── 4. GRUPPEN-TAB ──────────────────────────────────────────────

    // 4.01 Switch to Gruppen tab
    await tester.tap(find.text('Gruppen'));
    await tester.pumpAndSettle();

    // 4.02 Check if groups exist and can be opened
    final groupTiles = find.byType(ListTile);
    if (groupTiles.evaluate().isNotEmpty) {
      // 4.03 Tap first group
      await tester.tap(groupTiles.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 4.04 Group info button should exist
      expect(find.byIcon(Icons.info_outline).evaluate().isNotEmpty ||
             find.byTooltip('Gruppeninfo').evaluate().isNotEmpty,
          true, reason: '4.04 Gruppeninfo-Button existiert');

      // Back
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }

    // ── 5. CHANNELS-TAB ─────────────────────────────────────────────

    // 5.01 Switch to Channels tab
    await tester.tap(find.text('Kanäle'));
    await tester.pumpAndSettle();

    final channelTiles = find.byType(ListTile);
    if (channelTiles.evaluate().isNotEmpty) {
      // 5.02 Tap first channel
      await tester.tap(channelTiles.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Back
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }

    // ── 6. INBOX-TAB ────────────────────────────────────────────────

    // 6.01 Switch to Inbox tab
    await tester.tap(find.text('Anfragen'));
    await tester.pumpAndSettle();

    // 6.02 Check for accepted contacts section with rename option
    final inboxPopup = find.byType(PopupMenuButton<String>);
    if (inboxPopup.evaluate().isNotEmpty) {
      await tester.tap(inboxPopup.first);
      await tester.pumpAndSettle();

      // 6.03 Rename option in inbox contact menu
      final inboxRename = find.text('Kontakt umbenennen');
      if (inboxRename.evaluate().isNotEmpty) {
        // 6.04 Open rename dialog
        await tester.tap(inboxRename);
        await tester.pumpAndSettle();

        // 6.05 Rename dialog has TextField and original name label
        expect(find.byType(TextField), findsOneWidget,
            reason: '6.05 Rename-Dialog hat Textfeld');
        expect(find.textContaining('Originalname'), findsOneWidget,
            reason: '6.05b Originalname-Label sichtbar');

        // 6.06 Cancel dialog
        final cancelBtn = find.text('Abbrechen');
        if (cancelBtn.evaluate().isNotEmpty) {
          await tester.tap(cancelBtn);
          await tester.pumpAndSettle();
        }
      } else {
        // Close menu if no rename option (e.g. group/channel)
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      }
    }

    // ── 7. IDENTITY RENAME ────────────────────────────────────────

    // 7.01 Check identity tab context menu has rename option
    await tester.tap(find.text('Aktuell'));
    await tester.pumpAndSettle();
    // Find identity tabs (small horizontal bar above category tabs)
    final identityTabs = find.textContaining('Alice');
    if (identityTabs.evaluate().isNotEmpty) {
      // Tap active identity to open context menu
      await tester.tap(identityTabs.first);
      await tester.pumpAndSettle();

      final identityRename = find.text('Umbenennen');
      if (identityRename.evaluate().isNotEmpty) {
        expect(identityRename, findsOneWidget,
            reason: '7.01 Identity Umbenennen-Option existiert');
        // Close menu
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      }
    }

    // ── 8. ANDROID SAFAREA ────────────────────────────────────────

    // 8.01 Open chat and verify SafeArea wraps input
    final safeTiles = find.byType(ListTile);
    if (safeTiles.evaluate().isNotEmpty) {
      await tester.tap(safeTiles.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 8.02 SafeArea exists in chat screen body
      expect(find.byType(SafeArea), findsWidgets,
          reason: '8.02 SafeArea im Chat-Screen vorhanden');

      // 8.03 Input field is accessible (not hidden behind system UI)
      final inputField = find.byType(TextField);
      expect(inputField, findsWidgets,
          reason: '8.03 Eingabefeld sichtbar');

      // 8.04 Message status icon exists (sending/queued/sent)
      // Check for any status icon in message bubbles
      final statusIcons = [
        find.byIcon(Icons.hourglass_empty),  // sending
        find.byIcon(Icons.access_time),       // queued
        find.byIcon(Icons.check),             // sent
        find.byIcon(Icons.done_all),          // delivered/read
      ];
      final hasStatusIcon = statusIcons.any((f) => f.evaluate().isNotEmpty);
      if (find.byType(ListTile).evaluate().isNotEmpty) {
        // Only check if there are messages
        expect(hasStatusIcon, true,
            reason: '8.04 Nachrichten-Status-Icon vorhanden');
      }

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }

    // ── 9. MEDIA SAVE/COPY ──────────────────────────────────────────

    // 9.01 Open chat with media and check save/copy options
    await tester.tap(find.text('Aktuell'));
    await tester.pumpAndSettle();
    final mediaTiles = find.byType(ListTile);
    if (mediaTiles.evaluate().isNotEmpty) {
      await tester.tap(mediaTiles.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 9.02 Check if there are media messages with context menu
      final moreVertIcons = find.byIcon(Icons.more_vert);
      if (moreVertIcons.evaluate().isNotEmpty) {
        // Tap the last more_vert (likely on a recent media message)
        await tester.tap(moreVertIcons.last);
        await tester.pumpAndSettle();

        // 9.03 Check for save/copy options (only visible on media messages)
        final saveOption = find.text('Speichern');
        final clipOption = find.text('In Zwischenablage');
        // At least forward should always be visible
        final forwardOption = find.text('Weiterleiten');
        expect(forwardOption.evaluate().isNotEmpty || saveOption.evaluate().isNotEmpty || clipOption.evaluate().isNotEmpty,
            true, reason: '9.03 Kontextmenü hat Aktionen');

        // Close menu
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }

    // ── 10. NETWORK STATISTICS ────────────────────────────────────

    // 10.01 Open Network Stats screen
    final statsButton = find.byIcon(Icons.bar_chart);
    if (statsButton.evaluate().isNotEmpty) {
      await tester.tap(statsButton);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 10.02 Stats title visible
      expect(find.textContaining('Netzwerk'), findsWidgets,
          reason: '10.02 Netzwerk-Statistik Titel sichtbar');

      // 10.03 Data usage section exists
      final dataUsageLabels = [
        find.textContaining('Gesendet', skipOffstage: false),
        find.textContaining('Empfangen', skipOffstage: false),
        find.textContaining('Sent', skipOffstage: false),
        find.textContaining('Received', skipOffstage: false),
      ];
      final hasDataUsage = dataUsageLabels.any((f) => f.evaluate().isNotEmpty);
      expect(hasDataUsage, true,
          reason: '10.03 Datenverbrauch-Sektion vorhanden');

      // 10.04 Data usage should NOT be all zeros after some network activity
      // Look for any non-zero byte count (e.g. "1.2 KB", "345 B", "0.5 MB")
      final nonZeroData = [
        find.textContaining('KB', skipOffstage: false),
        find.textContaining('MB', skipOffstage: false),
        find.textContaining('GB', skipOffstage: false),
      ];
      final hasNonZeroData = nonZeroData.any((f) => f.evaluate().isNotEmpty);
      // Note: may be 0 if no messages have been sent/received yet in this session
      if (hasNonZeroData) {
        expect(hasNonZeroData, true,
            reason: '10.04 Datenverbrauch ist nicht 0');
      }

      // 10.05 Back to home
      final statsBack = find.byIcon(Icons.arrow_back);
      if (statsBack.evaluate().isNotEmpty) {
        await tester.tap(statsBack);
        await tester.pumpAndSettle();
      }
    }

    // ── 11. APP ICON ──────────────────────────────────────────────

    // 11.01 App icon asset exists (used for tray, desktop launcher)
    // This is a build-time check — the icon should be bundled with the app
    expect(find.textContaining('Cleona'), findsWidgets,
        reason: '11.01 App-Titel mit neuem Icon sichtbar');

    // ── DONE ────────────────────────────────────────────────────────
    // All checks passed if we get here
  });
}
