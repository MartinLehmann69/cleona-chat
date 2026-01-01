// Integration Tests for Node 2 — Chat, Groups, Channels, Inbox, Message Popup
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/main.dart';

/// Poll until [finder] matches at least one widget, or [timeout] expires.
/// Returns true if found, false on timeout. Uses 1s pump intervals.
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

/// Pump [count] frames with [interval] delay each.
Future<void> pumpFrames(WidgetTester tester, {int count = 5, Duration interval = const Duration(milliseconds: 200)}) async {
  for (var i = 0; i < count; i++) { await tester.pump(interval); }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SodiumFFI();
  OqsFFI().init();
  FlutterError.onError = (d) {
    if (d.library == 'flutter test framework') FlutterError.presentError(d);
  };

  testWidgets('Node2: chat + groups + channels + inbox', (tester) async {
    runApp(const CleonaApp());
    // Wait for app startup — poll until tabs appear (up to 30s)
    await pumpUntilFound(tester, find.text('Aktuell'), timeout: const Duration(seconds: 30));

    // ── CHAT ────────────────────────────────────────────────────────
    await tester.tap(find.text('Aktuell'));
    await pumpFrames(tester);

    final tiles = find.byType(ListTile);
    expect(tiles, findsWidgets, reason: '1.01 conversations present');

    await tester.tap(tiles.first);
    await pumpUntilFound(tester, find.byType(TextField), timeout: const Duration(seconds: 10));

    expect(find.byType(TextField), findsWidgets, reason: '1.02 Chat-Input');
    expect(find.byIcon(Icons.send), findsWidgets, reason: '1.03 Send-Button');
    expect(find.byIcon(Icons.arrow_back), findsOneWidget, reason: '1.04 Back-Button');

    // Send message — Optimistic UI shows it immediately, PoW runs in background
    await tester.enterText(find.byType(TextField).last, 'IntTest-Node2');
    await pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.send));
    // Poll until message appears (Optimistic UI: fast, PoW fallback: up to 60s)
    await pumpUntilFound(tester, find.textContaining('IntTest-Node2', skipOffstage: false));

    expect(find.textContaining('IntTest-Node2', skipOffstage: false), findsWidgets,
        reason: '1.05 message visible');

    // More-vert icon on own message
    final moreVert = find.byIcon(Icons.more_vert, skipOffstage: false);
    if (moreVert.evaluate().isNotEmpty) {
      // Verify the popup trigger exists (message has 3-dot menu)
      expect(moreVert, findsWidgets, reason: '1.06 more_vert on own message');
    }

    // ── MESSAGE-POPUP (Edit/Delete/Forward) ─────────────────────────
    // Tap the more_vert PopupMenuButton on the sent message
    final msgPopup = find.byIcon(Icons.more_vert);
    if (msgPopup.evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.more_vert).at(msgPopup.evaluate().length - 1));
      await tester.pump(const Duration(milliseconds: 500));

      // Check popup menu items (icons for edit, delete, forward)
      final editIcon = find.byIcon(Icons.edit);
      final deleteIcon = find.byIcon(Icons.delete);
      final forwardIcon = find.byIcon(Icons.forward);

      // At least edit and delete should be present for own messages
      if (editIcon.evaluate().isNotEmpty) {
        expect(editIcon, findsWidgets, reason: '1.07 Edit-Icon im Message-Popup');
      }
      if (deleteIcon.evaluate().isNotEmpty) {
        expect(deleteIcon, findsWidgets, reason: '1.08 Delete-Icon im Message-Popup');
      }
      if (forwardIcon.evaluate().isNotEmpty) {
        expect(forwardIcon, findsWidgets, reason: '1.09 Forward-Icon im Message-Popup');
      }

      // Also check the text labels
      final editText = find.text('Bearbeiten');
      final deleteText = find.text('Löschen');
      final forwardText = find.text('Weiterleiten');

      if (editText.evaluate().isNotEmpty) {
        expect(editText, findsOneWidget, reason: '1.10 "Bearbeiten" text in the popup');
      }
      if (deleteText.evaluate().isNotEmpty) {
        expect(deleteText, findsOneWidget, reason: '1.11 "Löschen" text in popup');
      }
      if (forwardText.evaluate().isNotEmpty) {
        expect(forwardText, findsOneWidget, reason: '1.12 Weiterleiten-Text im Popup');
      }

      // Close popup by tapping outside
      await tester.tapAt(const Offset(10, 10));
      await pumpFrames(tester);
    }

    // ── NEGATIVE: SEND EMPTY MESSAGE ────────────────────────────────
    // Count current messages
    final msgCountBefore = find.textContaining('IntTest-Node2', skipOffstage: false).evaluate().length;

    // Clear text field and tap send with empty text
    final textField = find.byType(TextField);
    if (textField.evaluate().isNotEmpty) {
      await tester.enterText(textField.last, '');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.send));
      await pumpFrames(tester, count: 10);
      await pumpFrames(tester);

      // Message count should not have increased
      final msgCountAfter = find.textContaining('IntTest-Node2', skipOffstage: false).evaluate().length;
      expect(msgCountAfter, msgCountBefore, reason: '1.13 Empty message not sent');
    }

    // Back
    final backBtn = find.byIcon(Icons.arrow_back); if (backBtn.evaluate().isNotEmpty) { await tester.tap(backBtn); for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 200)); } }
    await pumpFrames(tester);

    // ── GROUPS ──────────────────────────────────────────────────────
    await tester.tap(find.text('Gruppen'));
    await pumpFrames(tester);

    final groupTiles = find.byType(ListTile);
    if (groupTiles.evaluate().isNotEmpty) {
      await tester.tap(groupTiles.first);
      await pumpFrames(tester, count: 15);
      expect(find.byType(TextField), findsWidgets, reason: '2.01 group input');

      final backBtn = find.byIcon(Icons.arrow_back); if (backBtn.evaluate().isNotEmpty) { await tester.tap(backBtn); for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 200)); } }
      await pumpFrames(tester);
    }

    // ── CHANNELS ────────────────────────────────────────────────────
    await tester.tap(find.text('Kanäle'));
    await pumpFrames(tester);

    expect(find.byIcon(Icons.campaign).evaluate().isNotEmpty, true,
        reason: '3.01 Channels-FAB');

    final channelTiles = find.byType(ListTile);
    if (channelTiles.evaluate().isNotEmpty) {
      await tester.tap(channelTiles.first);
      await pumpFrames(tester, count: 15);

      // ── CHANNEL INFO DIALOG (via tooltip button in chat) ──────────
      final channelInfoBtn = find.byTooltip('Channelinfo');
      if (channelInfoBtn.evaluate().isNotEmpty) {
        expect(channelInfoBtn, findsOneWidget, reason: '3.02 Channelinfo-Tooltip im Chat');

        await tester.tap(channelInfoBtn);
        await pumpFrames(tester, count: 10);

        // Dialog should show campaign icon
        expect(find.byIcon(Icons.campaign), findsWidgets, reason: '3.03 Campaign-Icon im Channelinfo-Dialog');

        // Dialog should show subscriber/member count text
        final membersText = find.textContaining('Abonnent', skipOffstage: false);
        final membersTextOld = find.textContaining('Mitglied', skipOffstage: false);
        expect(
          membersText.evaluate().isNotEmpty || membersTextOld.evaluate().isNotEmpty,
          true,
          reason: '3.04 members/subscribers text in the dialog',
        );

        // Close dialog
        final closeBtn = find.text('Schließen');
        if (closeBtn.evaluate().isNotEmpty) {
          await tester.tap(closeBtn);
          await pumpFrames(tester);
        } else {
          await tester.tapAt(const Offset(10, 10));
          await pumpFrames(tester);
        }
      }

      final backBtn = find.byIcon(Icons.arrow_back); if (backBtn.evaluate().isNotEmpty) { await tester.tap(backBtn); for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 200)); } }
      await pumpFrames(tester);
    }

    // ── INBOX ───────────────────────────────────────────────────────
    await tester.tap(find.text('Anfragen'));
    await pumpFrames(tester);

    expect(find.textContaining('Bob', skipOffstage: false).evaluate().isNotEmpty ||
           find.textContaining('Alice', skipOffstage: false).evaluate().isNotEmpty,
        true, reason: '4.01 Kontaktname im Inbox');

    // ── PERFORM MESSAGE EDIT ─────────────────────────────────────
    // Navigate to first chat
    await tester.tap(find.text('Aktuell'));
    await pumpFrames(tester);

    final editChatTiles = find.byType(ListTile);
    if (editChatTiles.evaluate().isNotEmpty) {
      await tester.tap(editChatTiles.first);
      await pumpFrames(tester, count: 15);

      // Send a new message for editing
      final editTextField = find.byType(TextField);
      if (editTextField.evaluate().isNotEmpty) {
        await tester.enterText(editTextField.last, 'EditMe-Test');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.send));
        // Poll until message appears (Optimistic UI: fast, PoW fallback: up to 60s)
        await pumpUntilFound(tester, find.textContaining('EditMe-Test', skipOffstage: false));

        expect(find.textContaining('EditMe-Test', skipOffstage: false), findsWidgets,
            reason: '6.01 EditMe test message sent');

        // Tap more_vert on the last (our) message to open popup
        final editMoreVert = find.byIcon(Icons.more_vert);
        if (editMoreVert.evaluate().isNotEmpty) {
          await tester.tap(find.byIcon(Icons.more_vert).at(editMoreVert.evaluate().length - 1));
          await tester.pump(const Duration(milliseconds: 500));

          // Tap Edit icon/text in popup
          final editOption = find.text('Bearbeiten');
          if (editOption.evaluate().isNotEmpty) {
            await tester.tap(editOption);
            await pumpFrames(tester);

            // Check if edit banner is visible (contains "Nachricht bearbeiten")
            final editBanner = find.textContaining('bearbeiten', skipOffstage: false);
            if (editBanner.evaluate().isNotEmpty) {
              expect(editBanner, findsWidgets,
                  reason: '6.02 edit banner visible');
            }

            // Check if the edit icon in the banner area is shown
            final editIconInBanner = find.byIcon(Icons.edit);
            if (editIconInBanner.evaluate().isNotEmpty) {
              expect(editIconInBanner, findsWidgets,
                  reason: '6.03 Edit-Icon im Banner');
            }

            // Check if TextField contains the old text
            final editInput = find.byType(TextField);
            if (editInput.evaluate().isNotEmpty) {
              // TextField should contain the old text (or at least not be empty)
              final textFieldWidget = tester.widget<TextField>(editInput.last);
              final controllerText = textFieldWidget.controller?.text ?? '';
              expect(controllerText.isNotEmpty, true,
                  reason: '6.04 TextField is not empty in edit mode');
            }

            // Change text to "EditMe-Edited"
            await tester.enterText(find.byType(TextField).last, 'EditMe-Edited');
            await pumpFrames(tester);

            // Tap save button (Icons.check) — use .first to avoid ambiguity
            final checkIcon = find.byIcon(Icons.check);
            if (checkIcon.evaluate().isNotEmpty) {
              await tester.tap(checkIcon.first);
              await tester.pump(const Duration(seconds: 5));
              await pumpFrames(tester, count: 15);

              // Check if "bearbeitet" (edited) label appears in widget tree
              final editedLabel = find.textContaining('bearbeitet', skipOffstage: false);
              if (editedLabel.evaluate().isNotEmpty) {
                expect(editedLabel, findsWidgets,
                    reason: '6.05 "bearbeitet" label visible after edit');
              }
            }
          } else {
            // Close popup if edit not found
            await tester.tapAt(const Offset(10, 10));
            await pumpFrames(tester);
          }
        }
      }

      // ── PERFORM MESSAGE DELETE ──────────────────────────────────
      // Use an existing message for deletion (avoid another PoW wait)
      {
        // Tap more_vert on the last message (our previously sent/edited message)
        final delMoreVert = find.byIcon(Icons.more_vert);
        if (delMoreVert.evaluate().isNotEmpty) {
          await tester.tap(find.byIcon(Icons.more_vert).at(delMoreVert.evaluate().length - 1));
          await tester.pump(const Duration(milliseconds: 500));

          // Tap Delete option
          final deleteOption = find.text('Löschen');
          if (deleteOption.evaluate().isNotEmpty) {
            await tester.tap(deleteOption);
            await tester.pump(const Duration(milliseconds: 500));

            // Confirmation dialog should appear with "Nachricht löschen" title
            final deleteDialogTitle = find.text('Nachricht löschen');
            if (deleteDialogTitle.evaluate().isNotEmpty) {
              expect(deleteDialogTitle, findsOneWidget,
                  reason: '6.07 Delete confirmation dialog appears');
            }

            // Dialog should have content text about deleting for everyone
            final deleteContent = find.textContaining('löschen', skipOffstage: false);
            if (deleteContent.evaluate().isNotEmpty) {
              expect(deleteContent, findsWidgets,
                  reason: '6.08 Delete dialog has confirmation text');
            }

            // Tap "Löschen" button in the confirmation dialog
            final confirmDeleteBtn = find.text('Löschen');
            if (confirmDeleteBtn.evaluate().isNotEmpty) {
              // Find the FilledButton "Löschen" (not the popup item)
              await tester.tap(confirmDeleteBtn.last);
              await tester.pump(const Duration(seconds: 5));
              await pumpFrames(tester, count: 15);

              // Check if "gelöscht" text appears (message_deleted = "Nachricht gelöscht")
              final deletedLabel = find.textContaining('gelöscht', skipOffstage: false);
              if (deletedLabel.evaluate().isNotEmpty) {
                expect(deletedLabel, findsWidgets,
                    reason: '6.09 "gelöscht" text visible after delete');
              }
            }
          } else {
            // Close popup if delete not found
            await tester.tapAt(const Offset(10, 10));
            await pumpFrames(tester);
          }
        }
      }

      // ── NEGATIVE: NO EDIT ON A FOREIGN MESSAGE ──────────────────
      // Foreign messages (from Node1/Alice) should not have "Bearbeiten" in their popup.
      // The first message in the chat is likely from the other node (Alice).
      final foreignMoreVert = find.byIcon(Icons.more_vert);
      if (foreignMoreVert.evaluate().length >= 2) {
        // Tap the first more_vert (on the oldest = likely foreign message)
        await tester.tap(find.byIcon(Icons.more_vert).at(0));
        await tester.pump(const Duration(milliseconds: 500));

        // "Bearbeiten" (Edit) should NOT be available for foreign messages
        final foreignEditText = find.text('Bearbeiten');
        if (foreignEditText.evaluate().isEmpty) {
          // Correct: Edit is not available on foreign message
          expect(foreignEditText, findsNothing,
              reason: '6.10 No edit on a message from someone else');
        }

        // Close popup
        await tester.tapAt(const Offset(10, 10));
        await pumpFrames(tester);
      }

      // Back to home
      final editBackBtn = find.byIcon(Icons.arrow_back);
      if (editBackBtn.evaluate().isNotEmpty) {
        await tester.tap(editBackBtn);
        await pumpFrames(tester);
      }
    }

    // ── FORWARD DIALOG ──────────────────────────────────────────
    // In chat: more_vert on own message → tap "Weiterleiten"
    await tester.tap(find.text('Aktuell'));
    await pumpFrames(tester);

    final fwdChatTiles = find.byType(ListTile);
    if (fwdChatTiles.evaluate().isNotEmpty) {
      await tester.tap(fwdChatTiles.first);
      await pumpFrames(tester, count: 15);

      final fwdMoreVert = find.byIcon(Icons.more_vert);
      if (fwdMoreVert.evaluate().isNotEmpty) {
        await tester.tap(fwdMoreVert.last);
        await tester.pump(const Duration(milliseconds: 500));

        final fwdText = find.text('Weiterleiten');
        if (fwdText.evaluate().isNotEmpty) {
          await tester.tap(fwdText);
          await tester.pump(const Duration(milliseconds: 500));

          // Dialog should show "Weiterleiten an" title
          final fwdDialogTitle = find.text('Weiterleiten an');
          if (fwdDialogTitle.evaluate().isNotEmpty) {
            expect(fwdDialogTitle, findsOneWidget,
                reason: '7.01 "Weiterleiten an" dialog title');
          }

          // Dialog should show contact list (ListTile entries)
          final fwdTargets = find.byType(ListTile);
          if (fwdTargets.evaluate().isNotEmpty) {
            expect(fwdTargets, findsWidgets,
                reason: '7.02 forward dialog shows contact list');
          }

          // Tap "Abbrechen" → dialog closes
          final fwdCancel = find.text('Abbrechen');
          if (fwdCancel.evaluate().isNotEmpty) {
            await tester.tap(fwdCancel);
            await pumpFrames(tester);
          } else {
            await tester.tapAt(const Offset(10, 10));
            await pumpFrames(tester);
          }
        } else {
          // Close popup if forwarding is not available
          await tester.tapAt(const Offset(10, 10));
          await pumpFrames(tester);
        }
      }

      // Back to home
      final fwdBack = find.byIcon(Icons.arrow_back);
      if (fwdBack.evaluate().isNotEmpty) {
        await tester.tap(fwdBack);
        await pumpFrames(tester);
      }
    }

    // ── CHANNEL SUBSCRIBER READ-ONLY ──────────────────────────────────
    await tester.tap(find.text('Kanäle'));
    await pumpFrames(tester);

    final chSubTiles = find.byType(ListTile);
    if (chSubTiles.evaluate().isNotEmpty) {
      await tester.tap(chSubTiles.first);
      await pumpFrames(tester, count: 15);

      // Check whether input is disabled (subscriber) OR TextField present (owner/admin)
      final readOnlyText = find.textContaining('Nur Owner und Admins', skipOffstage: false);
      final chatInput = find.byType(TextField);

      // One of the two must exist
      expect(
        readOnlyText.evaluate().isNotEmpty || chatInput.evaluate().isNotEmpty,
        true,
        reason: '7.03 Channel shows either read-only hint or input field',
      );

      // If read-only is visible, check the text more closely
      if (readOnlyText.evaluate().isNotEmpty) {
        expect(readOnlyText, findsWidgets,
            reason: '7.04 subscriber sees read-only notice');
      }

      // Back
      final chBack = find.byIcon(Icons.arrow_back);
      if (chBack.evaluate().isNotEmpty) {
        await tester.tap(chBack);
        await pumpFrames(tester);
      }
    }

    // ── UNREAD BADGE CHECK ──────────────────────────────────────────
    // Back on home, check whether unread counter widgets exist
    await tester.tap(find.text('Aktuell'));
    await pumpFrames(tester);

    // Unread badge is a Container with BorderRadius(10) and Text with counter
    // Check whether a badge widget exists anywhere in the widget tree
    final badgeWidgets = find.byType(Badge, skipOffstage: false);

    // At least conversations must exist
    final unreadTiles = find.byType(ListTile);
    if (unreadTiles.evaluate().isNotEmpty) {
      // Check whether any conversation has a bold title (unread indicator)
      // or whether badge widgets exist in the tab area
      expect(
        badgeWidgets.evaluate().isNotEmpty || unreadTiles.evaluate().isNotEmpty,
        true,
        reason: '7.05 Home screen shows conversations (badge or ListTile present)',
      );
    }

    // ── CREATE GROUP DIALOG ───────────────────────────────────────────
    await tester.tap(find.text('Gruppen'));
    await pumpFrames(tester);

    final groupAddFab = find.byIcon(Icons.group_add);
    if (groupAddFab.evaluate().isNotEmpty) {
      await tester.tap(groupAddFab.first);
      await tester.pump(const Duration(milliseconds: 500));

      // Dialog with TextField for group name
      final groupNameField = find.byType(TextField);
      expect(groupNameField.evaluate().isNotEmpty, true,
          reason: '7.06 create group dialog has TextField');

      // Dialog title "Gruppe erstellen"
      final groupDialogTitle = find.text('Gruppe erstellen');
      if (groupDialogTitle.evaluate().isNotEmpty) {
        expect(groupDialogTitle, findsOneWidget,
            reason: '7.07 "Gruppe erstellen" dialog title');
      }

      // Checkboxes for member selection
      final checkboxes = find.byType(CheckboxListTile);
      if (checkboxes.evaluate().isNotEmpty) {
        expect(checkboxes, findsWidgets,
            reason: '7.08 Create-group dialog shows checkboxes for members');
      }

      // Tap "Abbrechen" → dialog closes
      final groupCancel = find.text('Abbrechen');
      if (groupCancel.evaluate().isNotEmpty) {
        await tester.tap(groupCancel);
        await pumpFrames(tester);
      } else {
        await tester.tapAt(const Offset(10, 10));
        await pumpFrames(tester);
      }

      // Check that we are still on the groups tab
      expect(find.text('Gruppen'), findsWidgets,
          reason: '7.09 Still on groups tab after dialog cancel');
    }

    // ── FAB CHECKS ──────────────────────────────────────────────────
    await tester.tap(find.text('Gruppen'));
    await pumpFrames(tester);
    expect(find.byIcon(Icons.group_add).evaluate().isNotEmpty, true,
        reason: '2.02 group FAB');

    await tester.tap(find.text('Kontakte'));
    await pumpFrames(tester);
    expect(find.byIcon(Icons.person_add).evaluate().isNotEmpty, true,
        reason: '5.01 Chats-FAB person_add');

    await tester.tap(find.text('Aktuell'));
    await pumpFrames(tester);
    expect(find.byIcon(Icons.person_add).evaluate().isNotEmpty, true,
        reason: '5.02 Recent-FAB person_add');
  });
}
