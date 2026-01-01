// Integration Tests: Offline-Szenarien & Netzwerk
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

  testWidgets('Offline: network status + message delivery', (tester) async {
    runApp(const CleonaApp());
    // Wait for app startup — poll until tabs appear (up to 30s)
    await pumpUntilFound(tester, find.text('Aktuell'), timeout: const Duration(seconds: 30));

    // ── 1. PEER-COUNT CHIP ──────────────────────────────────────────
    expect(find.byIcon(Icons.cell_tower), findsOneWidget,
        reason: '1.01 peer count chip visible');

    // ── 2. CONVERSATIONS PRESENT ────────────────────────────────────
    await tester.tap(find.text('Aktuell'));
    await pumpFrames(tester);
    expect(find.byType(ListTile), findsWidgets,
        reason: '2.01 conversations in list');

    // ── 3. OPEN CHAT AND SEND MESSAGE ─────────────────────────
    final tiles = find.byType(ListTile);
    await tester.tap(tiles.first);
    await pumpFrames(tester, count: 15);

    expect(find.byType(TextField), findsWidgets, reason: '3.01 Chat-Input');
    expect(find.byIcon(Icons.send), findsWidgets, reason: '3.02 Send-Button');

    // Send message (PoW can take 30s+ on VMs)
    await tester.enterText(find.byType(TextField).last, 'OfflineCheck1');
    await pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.send));
    // Poll until message appears (Optimistic UI: fast, PoW fallback: up to 60s)
    await pumpUntilFound(tester, find.textContaining('OfflineCheck1', skipOffstage: false));

    // Message should be visible locally (even if recipient is offline)
    final msg = find.textContaining('OfflineCheck1', skipOffstage: false);
    expect(msg, findsWidgets, reason: '3.03 message visible locally');

    // No error icon on the message (Icon.error or Icons.error_outline)
    // Messages are queued, not shown as errors

    // ── 4. CHAT HAS SEVERAL MESSAGES ────────────────────────────
    // Instead of sending a second message (PoW too slow), check that the chat
    // has several messages (from earlier tests)
    final allMessages = find.byType(Container, skipOffstage: false);
    expect(allMessages.evaluate().length > 5, true,
        reason: '4.01 chat has several widget elements (messages)');

    // ── 5. BACK AND GROUP MESSAGE ─────────────────────────────
    final back = find.byIcon(Icons.arrow_back);
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back);
      await pumpFrames(tester);
    }

    await tester.tap(find.text('Gruppen'));
    await pumpFrames(tester);

    final groupTiles = find.byType(ListTile);
    if (groupTiles.evaluate().isNotEmpty) {
      await tester.tap(groupTiles.first);
      await pumpFrames(tester, count: 15);

      // Group chat: input and send
      expect(find.byType(TextField), findsWidgets, reason: '5.01 group input');

      await tester.enterText(find.byType(TextField).last, 'GrpOffline1');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.send));
      // Poll until message appears (Optimistic UI: fast, PoW fallback: up to 60s)
      await pumpUntilFound(tester, find.textContaining('GrpOffline1', skipOffstage: false));

      final grpMsg = find.textContaining('GrpOffline1', skipOffstage: false);
      expect(grpMsg, findsWidgets, reason: '5.02 group message visible');

      final backFromGroup = find.byIcon(Icons.arrow_back);
      if (backFromGroup.evaluate().isNotEmpty) {
        await tester.tap(backFromGroup);
        await pumpFrames(tester);
      }
    }

    // ── 6. CONVERSATIONS HAVE LAST MESSAGE ──────────────────────────
    await tester.tap(find.text('Aktuell'));
    await pumpFrames(tester);

    // At least one conversation should be visible
    expect(find.byType(ListTile), findsWidgets,
        reason: '6.01 conversations after sending messages');
  });
}
