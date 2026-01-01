// integration_test/member_list_swipe_reach_test.dart
//
// Device test (S417 B2) for the lab Android emulator: every contact in the
// member list of "Create group" and "Create channel" can be reached by a
// swipe over the list and ticked while the REAL on-screen keyboard is open.
// Field finding (owner, handset on 4.2.6): the list showed six entries, the
// sixth came into view with a swipe, the seventh never did. The widget smoke
// `test/smoke/smoke_member_list_swipe_reach.dart` proves the same with an
// estimated keyboard height; this test runs on the device's own screen,
// fonts and keyboard.
//
// What runs: the real HomeScreen with a strict test double of the service
// (eight accepted contacts, nothing else). No network, no daemon, no
// CleonaService: the app's main() is not started. The profile on the device
// is not read or written — AppPaths points into a fresh directory under the
// app's cache, and SharedPreferences is the in-memory mock.
//
//   G  Groups tab, FAB, "Create group": tap the name field, wait until the
//      keyboard is open (viewInsets.bottom > 0 — a test without an open
//      keyboard fails, it does not pass silently), then for every contact
//      in list order swipe over the list until it can be hit, tick it.
//      Requires: the last contact is out of reach before the first swipe,
//      at least one swipe was needed, the keyboard is still open at the
//      end, all eight are ticked.
//   K  The same for "Create channel" (Channels tab). The list starts below
//      form fields there; until a list entry is in view a swipe starts on
//      the heading, the public switch or the language field — never on a
//      text field.
//
// Run (main session; installs the beta debug build of this test over the
// app on the emulator — reinstall the regular APK afterwards):
//   flutter test integration_test/member_list_swipe_reach_test.dart \
//       -d emulator-5554 --flavor beta --no-uninstall
// Without --no-uninstall `flutter test` uninstalls the app after the run and
// the app's data on the emulator goes with it.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/main.dart' show CleonaAppState;
import 'package:cleona/ui/components/skin_fab.dart';
import 'package:cleona/ui/screens/home_screen.dart';
import 'package:cleona/ui/theme/skins.dart';

const _me = 'aa00000000000000000000000000000000000000000000000000000000000000';

// One swipe: upwards by 150 dp in 400 ms — a short drag, well below the
// long-press timeout, starting on the list.
const _swipe = Offset(0, -150);
const _swipeTime = Duration(milliseconds: 400);
const _maxSwipesPerContact = 12;

/// How long the keyboard may take to come up after the tap on the name field.
const _keyboardWait = Duration(seconds: 10);

/// How long the app may take to reach the foreground after its start.
const _foregroundWait = Duration(seconds: 30);

/// A pump waits for a frame, and Android draws no frame for an app that is
/// not in the foreground — with the display asleep every pump of the test
/// waits for ever, without a line of output (S417 B2, first device runs:
/// `mWakefulness=Asleep`, logcat `isSleeping=true`, `Activity pause
/// timeout`). This check turns that into a named precondition failure; it
/// does not wake the device.
Future<void> _expectAppInForeground() async {
  final binding = WidgetsBinding.instance;
  final deadline = DateTime.now().add(_foregroundWait);
  while (binding.lifecycleState != AppLifecycleState.resumed &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  // ignore: avoid_print
  print('app lifecycle before the first pump: ${binding.lifecycleState}');
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    fail('precondition: the app is not in the foreground '
        '(lifecycle ${binding.lifecycleState} after '
        '${_foregroundWait.inSeconds} s). Android draws no frame for it, '
        'and every pump would wait for ever. Is the display asleep? '
        '(adb shell dumpsys power | grep mWakefulness)');
  }
}

const _names = [
  'Amsel', 'Buche', 'Dachs', 'Eibe', 'Fink', 'Hase', 'Linde', 'Otter', //
];

ContactInfo _contact(int n, String name) => ContactInfo(
      nodeId: Uint8List(32)..fillRange(0, 32, n),
      displayName: name,
      status: 'accepted',
    );

final _contacts = [
  for (var i = 0; i < _names.length; i++) _contact(i + 1, _names[i]),
];

/// Strict service for the home screen: every member this test does not
/// provide throws. Creating a group or channel is not part of this test.
class _Service implements ICleonaService {
  @override
  void Function()? onNatWizardTriggered;
  @override
  void Function()? onNatWizardUserRequested;

  @override
  List<ContactInfo> get acceptedContacts => _contacts;
  @override
  List<ContactInfo> get pendingContacts => const [];
  @override
  List<Conversation> get sortedConversations => <Conversation>[];
  @override
  EnrolmentView get enrolmentView => const EnrolmentView();
  @override
  bool get reducedMode => false;
  @override
  String get displayName => 'Ida';
  @override
  String get nodeIdHex => _me;
  @override
  int get independentSyncPartners => 2;
  @override
  String get readinessState => kReadinessReady;
  @override
  Map<String, GroupInfo> get groups => const {};
  @override
  Map<String, ChannelInfo> get channels => const {};
  @override
  List<JuryRequest> get pendingJuryRequests => const [];
  @override
  Future<List<ChannelIndexEntry>> searchPublicChannels(
          {String? query, String? language, bool? includeAdult}) async =>
      <ChannelIndexEntry>[];
  @override
  ContactInfo? getContact(String nodeIdHex) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by this test: ${invocation.memberName}');
}

class _AppState extends CleonaAppState {
  _AppState(this._svc);
  final ICleonaService _svc;
  @override
  ICleonaService? get service => _svc;
  // The base reads its private service field, which stays null here.
  @override
  String get readinessState => kReadinessReady;
}

Future<AppLocale> _german() async {
  final locale = AppLocale();
  await locale.setLocale('de');
  return locale;
}

Widget _home(AppLocale locale) => MultiProvider(
      providers: [
        ChangeNotifierProvider<CleonaAppState>.value(
            value: _AppState(_Service())),
        ChangeNotifierProvider<AppLocale>.value(value: locale),
      ],
      child: MaterialApp(
        theme: Skins.byId(null).toLightTheme(),
        home: const HomeScreen(),
      ),
    );

Future<void> _openTab(WidgetTester tester, String label) async {
  final tab =
      find.descendant(of: find.byType(TabBar), matching: find.text(label));
  await tester.ensureVisible(tab.first);
  await tester.pumpAndSettle();
  await tester.tap(tab.first);
  await tester.pumpAndSettle();
  // ignore: avoid_print
  print('tab open: $label');
}

Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

double _keyboardInset(WidgetTester tester) =>
    tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

/// Taps the name field (as a user does) and waits for the device's
/// on-screen keyboard. Fails when it does not come up.
Future<void> _openKeyboard(WidgetTester tester) async {
  // ignore: avoid_print
  print('dialog open, tapping the name field');
  await tester.tap(_inDialog(find.byType(TextField)).first);
  final deadline = DateTime.now().add(_keyboardWait);
  while (_keyboardInset(tester) <= 0 && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(_keyboardInset(tester), greaterThan(0),
      reason: 'the on-screen keyboard did not open within '
          '${_keyboardWait.inSeconds} s (MediaQuery.viewInsets.bottom == 0). '
          'The lab AVD has hw.keyboard = yes; Android then hides the '
          'on-screen keyboard unless "show virtual keyboard" with a physical '
          'keyboard is on. Without an open keyboard this test proves nothing.');
  await tester.pumpAndSettle();
  // ignore: avoid_print
  print('keyboard inset: ${_keyboardInset(tester).toStringAsFixed(1)} dp');
}

/// Where the next swipe starts: on the lowest list entry the user can hit;
/// while no entry is in view, on the first of [above] (what stands above
/// the list, none of it a text field) that can be hit.
Offset _swipeStart(WidgetTester tester, List<Finder> above) {
  final tiles = _inDialog(find.byType(CheckboxListTile)).hitTestable();
  final n = tiles.evaluate().length;
  if (n > 0) {
    var lowest = tester.getCenter(tiles.at(0));
    for (var i = 1; i < n; i++) {
      final c = tester.getCenter(tiles.at(i));
      if (c.dy > lowest.dy) lowest = c;
    }
    return lowest;
  }
  for (final a in above) {
    final f = _inDialog(a).hitTestable();
    if (f.evaluate().isNotEmpty) return tester.getCenter(f.first);
  }
  fail('no list entry and no text above the list can be hit — nowhere to '
      'start a swipe');
}

/// Ticks every name in list order, swiping as a user would until the name
/// can be hit. Returns the names no swipe brought within reach, and how
/// many swipes were made.
Future<(List<String>, int)> _tickAllBySwiping(
    WidgetTester tester, List<Finder> above) async {
  final missed = <String>[];
  var swipes = 0;
  for (final name in _names) {
    final target = _inDialog(find.text(name)).hitTestable();
    var tries = 0;
    while (target.evaluate().isEmpty && tries < _maxSwipesPerContact) {
      await tester.timedDragFrom(
          _swipeStart(tester, above), _swipe, _swipeTime);
      await tester.pumpAndSettle();
      tries++;
      swipes++;
    }
    if (target.evaluate().isEmpty) {
      missed.add(name);
      continue;
    }
    await tester.tap(target.first);
    await tester.pumpAndSettle();
  }
  return (missed, swipes);
}

bool _ticked(WidgetTester tester, String name) =>
    tester
        .widget<CheckboxListTile>(
            _inDialog(find.widgetWithText(CheckboxListTile, name)))
        .value ==
    true;

Future<void> _expectEveryContactReachedAndTicked(
    WidgetTester tester, List<Finder> above) async {
  expect(_inDialog(find.text(_names.last)).hitTestable(), findsNothing,
      reason: 'precondition: the last contact must be out of reach before '
          'the first swipe, or the test proves nothing about swiping');
  final (missed, swipes) = await _tickAllBySwiping(tester, above);
  // ignore: avoid_print
  print('swipes: $swipes, out of reach: $missed');
  expect(missed, isEmpty,
      reason: 'contacts no swipe over the list brought within reach');
  expect(swipes, greaterThan(0));
  expect(_keyboardInset(tester), greaterThan(0),
      reason: 'the keyboard must still be open after the last tick');
  for (final n in _names) {
    expect(_ticked(tester, n), isTrue, reason: '$n is ticked');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  // The home screen reads the list of identities from the profile
  // directory; it must not read the app's real one on the device.
  late Directory tmpHome;
  setUpAll(() async {
    await _expectAppInForeground();
    final cache = await getTemporaryDirectory();
    tmpHome = cache.createTempSync('member_list_reach_');
    AppPaths.setHome(tmpHome.path);
  });
  tearDownAll(() {
    try {
      tmpHome.deleteSync(recursive: true);
    } catch (_) {
      // Must not mask a test failure.
    }
  });

  testWidgets(
      'G: Create group — every contact reached by a swipe over the list, '
      'keyboard open', (tester) async {
    final locale = await _german();
    await tester.pumpWidget(_home(locale));
    await tester.pumpAndSettle();

    await _openTab(tester, locale.get('tab_groups'));
    await tester.tap(find.byType(SkinFab));
    await tester.pumpAndSettle();
    expect(_inDialog(find.text(locale.get('create_group'))), findsOneWidget,
        reason: 'the FAB of the Groups tab opens "Create group"');
    await _openKeyboard(tester);

    await _expectEveryContactReachedAndTicked(
        tester, [find.text(locale.get('select_members'))]);
  });

  testWidgets(
      'K: Create channel — every contact reached by a swipe over the list, '
      'keyboard open', (tester) async {
    final locale = await _german();
    await tester.pumpWidget(_home(locale));
    await tester.pumpAndSettle();

    await _openTab(tester, locale.get('tab_channels'));
    await tester.tap(find.byType(SkinFab));
    await tester.pumpAndSettle();
    expect(_inDialog(find.text(locale.get('create_channel'))), findsOneWidget,
        reason: 'the FAB of the Channels tab opens "Create channel"');
    await _openKeyboard(tester);

    await _expectEveryContactReachedAndTicked(tester, [
      find.text(locale.get('select_subscribers')),
      find.byType(SwitchListTile),
      find.byType(DropdownButtonFormField<String>),
    ]);
  });
}
