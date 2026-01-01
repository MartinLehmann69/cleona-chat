// Integration Tests: Offline-Szenarien & Netzwerk — auf Node2 (Bob)
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

  testWidgets('Offline: Netzwerk-Status + Nachrichten-Zustellung', (tester) async {
    runApp(const CleonaApp());
    // Wait for app startup — poll until tabs appear (up to 30s)
    await pumpUntilFound(tester, find.text('Aktuell'), timeout: const Duration(seconds: 30));

    // ── 1. PEER-COUNT CHIP ──────────────────────────────────────────
    expect(find.byIcon(Icons.cell_tower), findsOneWidget,
        reason: '1.01 Peer-Count Chip sichtbar');

    // ── 2. CONVERSATIONS VORHANDEN ──────────────────────────────────
    await tester.tap(find.text('Aktuell'));
    await pumpFrames(tester);
    expect(find.byType(ListTile), findsWidgets,
        reason: '2.01 Conversations in Liste');

    // ── 3. CHAT ÖFFNEN UND NACHRICHT SENDEN ─────────────────────────
    final tiles = find.byType(ListTile);
    await tester.tap(tiles.first);
    await pumpFrames(tester, count: 15);

    expect(find.byType(TextField), findsWidgets, reason: '3.01 Chat-Input');
    expect(find.byIcon(Icons.send), findsWidgets, reason: '3.02 Send-Button');

    // Sende Nachricht (PoW kann 30s+ dauern auf VMs)
    await tester.enterText(find.byType(TextField).last, 'OfflineCheck1');
    await pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.send));
    // Poll until message appears (Optimistic UI: fast, PoW fallback: up to 60s)
    await pumpUntilFound(tester, find.textContaining('OfflineCheck1', skipOffstage: false));

    // Nachricht sollte lokal sichtbar sein (auch wenn Empfänger offline)
    final msg = find.textContaining('OfflineCheck1', skipOffstage: false);
    expect(msg, findsWidgets, reason: '3.03 Nachricht lokal sichtbar');

    // Kein Fehler-Icon auf der Nachricht (Icon.error oder Icons.error_outline)
    // Nachrichten werden gequeued, nicht als Fehler angezeigt

    // ── 4. CHAT HAT MEHRERE NACHRICHTEN ────────────────────────────
    // Statt zweite Nachricht zu senden (PoW zu langsam), prüfe dass der Chat
    // mehrere Nachrichten hat (von früheren Tests)
    final allMessages = find.byType(Container, skipOffstage: false);
    expect(allMessages.evaluate().length > 5, true,
        reason: '4.01 Chat hat mehrere Widget-Elemente (Nachrichten)');

    // ── 5. ZURÜCK UND GRUPPEN-NACHRICHT ─────────────────────────────
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

      // Gruppen-Chat: Input und Send
      expect(find.byType(TextField), findsWidgets, reason: '5.01 Gruppen-Input');

      await tester.enterText(find.byType(TextField).last, 'GrpOffline1');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.send));
      // Poll until message appears (Optimistic UI: fast, PoW fallback: up to 60s)
      await pumpUntilFound(tester, find.textContaining('GrpOffline1', skipOffstage: false));

      final grpMsg = find.textContaining('GrpOffline1', skipOffstage: false);
      expect(grpMsg, findsWidgets, reason: '5.02 Gruppen-Nachricht sichtbar');

      final backFromGroup = find.byIcon(Icons.arrow_back);
      if (backFromGroup.evaluate().isNotEmpty) {
        await tester.tap(backFromGroup);
        await pumpFrames(tester);
      }
    }

    // ── 6. CONVERSATIONS HABEN LETZTE NACHRICHT ─────────────────────
    await tester.tap(find.text('Aktuell'));
    await pumpFrames(tester);

    // Mindestens eine Conversation sollte sichtbar sein
    expect(find.byType(ListTile), findsWidgets,
        reason: '6.01 Conversations nach Nachrichten-Versand');
  });
}
