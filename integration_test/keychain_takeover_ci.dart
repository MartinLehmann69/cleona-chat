// CI integration test (S413, D-95): a keychain entry of 4.2.3–4.2.6.
//
// The workflow (`.github/workflows/macos-integration-test.yml`, step
// "Keychain takeover case") puts `cleona_master_seed` into a keychain of its
// own with `security add-generic-password … -T ''` — the empty access list
// every 4.2.3–4.2.6 build wrote — and runs this test against a FRESH
// profile directory. Expected, without any dialog and without a hang:
//
//  T1  the keyring reports the entry as present but not readable;
//  T2  `hasMasterSeed()` is true, `loadMasterSeed()` throws, and
//      `generateSeedPhrase()` refuses — nothing is generated;
//  T3  the app shows the takeover screen, not the setup.
//
// The success case of the takeover (someone types the login password) is
// NOT testable here — CI has nobody at the dialog (D-95). The workflow
// checks afterwards that the entry was not rewritten (its modification
// date is unchanged).
//
// Run: flutter test integration_test/keychain_takeover_ci.dart -d macos
import 'dart:io';

import 'package:flutter/material.dart' show runApp;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/main.dart';
import 'package:cleona/ui/screens/keychain_takeover_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    AppPaths.setDataDir(
        Directory.systemTemp.createTempSync('cleona_takeover_ci_').path);
    await initUiCrypto();
  });

  testWidgets('Keychain entry of 4.2.3–4.2.6: present, takeover needed',
      (tester) async {
    // T1
    final unreadable = KeyringService.instance.unreadableEntries();
    expect(unreadable, contains('master_seed'),
        reason: 'T1 the pre-seeded entry is present but not readable');

    // T2
    final mgr = IdentityManager();
    expect(mgr.hasMasterSeed(), isTrue,
        reason: 'T2 an unreadable seed counts as present');
    expect(() => mgr.loadMasterSeed(), throwsA(isA<KeyringEntryUnreadable>()),
        reason: 'T2 loadMasterSeed throws, never null');
    expect(() => mgr.generateSeedPhrase(), throwsA(isA<StateError>()),
        reason: 'T2 no new seed over the unreadable one');

    // T3
    runApp(const CleonaApp());
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.byType(KeychainTakeoverScreen), findsOneWidget,
        reason: 'T3 the takeover screen stands, not the setup');
  });
}
