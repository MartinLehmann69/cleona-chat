// The ONE connection indicator — for tray and GUI.
//
// ══════════════════════════════════════════════════════════════════════
// WHY THIS FILE EXISTS (S376/P8, §22.9)
// ══════════════════════════════════════════════════════════════════════
//
// §22.9 requires the tray to show the readiness state. Until S376
// nothing of it was built: `NativeTray` offered exactly
// `updateMenu(serviceRunning:, unreadCount:)` — a boolean and
// a number. The tray could not say whether the node can deliver,
// and exactly that was the unanswered question for days in S373 and S374.
//
// ── ONE QUANTITY (S388, owner decision E3 = A, E5 = a, E6 = a) ─────
//
// V4.2 §22.9 in the version of the approved proposal A2
// (`mycelium/berichte/S387-VORLAGE-ARCHITEKTUR.md`): "The tray and the GUI
// show **one** indicator: the readiness state of §22.7 (`searching` /
// `connecting` / `ready`), with a 30-s pulse freeze … There is no
// separate connection tier and no reachability mark (§12.3)".
//
// Until S388 three quantities stood here: readiness, a five-tier
// connection tier (`ConnectionTier`, computed from outgoing
// sync partners, connection type and port mapping) and a
// reachability mark from incoming partners. Both of the latter have
// gone: the tier was a second calculation that needs no user action,
// and the sync partners on which it rested do not exist in V4.2
// (readiness is based on answering neighbours, §22.7.1).
//
// ── WHY THE MAPPING LIES HERE AND NOT IN THE GUI ──────────────
//
// The tray runs in the DAEMON (`lib/service_daemon.dart`, `dart compile
// exe`), and that has no Flutter. The mapping state -> image therefore stands
// ONCE here; `home_screen.dart` calls it. Two copies would diverge
// as soon as one is maintained.
//
// This file is PURE DART (no `package:flutter`). The smoke corpus
// runs with `dart run` — a file with a Flutter import would not be
// checkable there.
//
// ── NO TIMER, NO POLLING (working rule 5) ────────────────────────
//
// [TrayStatusBinder] hangs on the state edge that already exists:
// `CleonaService.onStateChanged`. No network traffic and no
// wake-up arises — the binder only computes when the service reports anyway, and
// passes on to the sink only what has CHANGED.
library;

import 'dart:io' show Platform;

import 'package:cleona/core/i18n/translations.dart';
import 'package:cleona/core/service/readiness_names.dart';

/// What ONE identity contributes to the process state.
///
/// Deliberately a pure value type without reference to `CleonaService`: so
/// the guard can create it without dragging half the application along, and
/// the aggregation can be checked without a running service.
///
/// S388: `syncPartnersOutbound`, `syncPartnersInbound`, `hasPortMapping`
/// and `hasNetwork` have gone — they fed only the tier and the
/// reachability mark.
class IdentityStatus {
  /// One of [kReadinessNames].
  final String readiness;
  final int unreadCount;

  /// The name under which this identity stands in the menu (V-10-c = b,
  /// 09.09.2026). Empty means: no line of its own.
  final String displayName;

  const IdentityStatus({
    required this.readiness,
    this.unreadCount = 0,
    this.displayName = '',
  });
}

/// A line in the tray menu: an identity with ITS state.
///
/// V-10-c = b (owner decision 09.09.2026). The aggregation over
/// N identities says "bereit 2/3"; which two they are stands here —
/// otherwise the number would be information nobody can do anything
/// with.
class TrayIdentityLine {
  final String displayName;

  /// One of [kReadinessNames].
  final String readiness;

  const TrayIdentityLine({required this.displayName, required this.readiness});

  @override
  bool operator ==(Object other) =>
      other is TrayIdentityLine &&
      other.displayName == displayName &&
      other.readiness == readiness;

  @override
  int get hashCode => Object.hash(displayName, readiness);

  @override
  String toString() => '$displayName:$readiness';
}

/// The state the tray displays — one process, one icon, one line.
class TrayStatus {
  /// Is the service running at all? `false` after "Dienst stoppen" in the menu.
  final bool serviceRunning;

  /// Sum of unread messages over all identities.
  final int unreadCount;

  /// One of [kReadinessNames] — the ONE indicator (§22.9, E3 = A).
  final String readiness;

  /// How many identities are `ready` (V-10-c = b, 09.09.2026).
  final int readyCount;

  /// How many identities this process keeps at all.
  final int identityCount;

  /// The identities with their own respective state — the lines of the
  /// menu. With a single identity it stays empty: the
  /// state line then already says everything.
  final List<TrayIdentityLine> identities;

  const TrayStatus({
    required this.serviceRunning,
    required this.unreadCount,
    required this.readiness,
    this.readyCount = 0,
    this.identityCount = 0,
    this.identities = const [],
  });

  @override
  bool operator ==(Object other) =>
      other is TrayStatus &&
      other.serviceRunning == serviceRunning &&
      other.unreadCount == unreadCount &&
      other.readiness == readiness &&
      other.readyCount == readyCount &&
      other.identityCount == identityCount &&
      _linesEqual(other.identities, identities);

  static bool _linesEqual(
      List<TrayIdentityLine> a, List<TrayIdentityLine> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(serviceRunning, unreadCount, readiness,
      readyCount, identityCount, Object.hashAll(identities));

  @override
  String toString() => 'TrayStatus(running=$serviceRunning, unread=$unreadCount, '
      'readiness=$readiness, ready=$readyCount/$identityCount)';
}

/// Rank of a readiness name; unknown names count as `searching`.
int readinessRank(String name) {
  final i = kReadinessNames.indexOf(name);
  return i < 0 ? 0 : i;
}

/// One process, ONE tray — so N identities must become one statement.
///
/// ── THE AGGREGATION RULES, AND WHY EXACTLY THESE ────────────────
///
/// **Readiness: the MAXIMUM, and in addition the NUMBER.**
///
/// ── THE DECISION AND ITS REASONING (V-10-c = b, 09.09.2026) ────
///
/// Until S376 the MINIMUM stood here, and the report on P8 itself marked it
/// as an interpretation ("§22.9 speaks throughout of the node, not of
/// N identities in one process"). The owner decided on 09.09.2026
/// against the minimum: it produces a PERMANENT WARNING — "a
/// warning that fires in the good case is worse than none". An
/// unused or freshly created identity would have held the tray permanently
/// at `searching`, although two of three identities deliver.
///
/// §22.7.1 ("progress, not success") remains UNTOUCHED by this: the sentence
/// applies to the path of ONE identity to readiness, not to the
/// aggregation over several. Each individual identity reports its
/// own progress, and exactly those stand as [TrayStatus.identities]
/// in the menu.
///
/// The maximum alone, however, would be the exaggeration against which the
/// minimum was meant to protect. That is why the NUMBER travels along
/// ([TrayStatus.readyCount] / [TrayStatus.identityCount]): "Bereit 2/3"
/// claims nothing that is not true, and at the same time names what is missing.
/// Without identity: `searching`, `0/0`.
///
/// **Unread: the sum.** Messages differ per identity;
/// `_updateTrayBadge` has always computed exactly so.
TrayStatus aggregateTrayStatus({
  required bool serviceRunning,
  required Iterable<IdentityStatus> identities,
}) {
  var unread = 0;
  var rank = -1;
  var ready = 0;
  var total = 0;
  final lines = <TrayIdentityLine>[];
  for (final i in identities) {
    unread += i.unreadCount;
    final r = readinessRank(i.readiness);
    // MAXIMUM (V-10-c = b) — until S376 `r < rang` stood here.
    rank = rank < 0 ? r : (r > rank ? r : rank);
    if (i.readiness == kReadinessReady) ready++;
    total++;
    lines.add(TrayIdentityLine(
        displayName: i.displayName, readiness: i.readiness));
  }
  if (rank < 0) rank = 0;
  // A stopped service is not ready — and not as a
  // substitute assumption: `stopAll()` shuts down the node, after that
  // `readinessState` reports `searching`. The line only records that the
  // display need not wait for the next state report, which a
  // stopped service no longer sends.
  if (!serviceRunning) {
    return TrayStatus(
      serviceRunning: false,
      unreadCount: unread,
      readiness: kReadinessSearching,
      readyCount: 0,
      identityCount: total,
      identities: const [],
    );
  }
  return TrayStatus(
    serviceRunning: true,
    unreadCount: unread,
    readiness: kReadinessNames[rank],
    readyCount: ready,
    identityCount: total,
    // With ONE identity no individual line: the state line says
    // the same, and a menu that carries every piece of information twice is
    // no better information.
    identities: total > 1 ? List.unmodifiable(lines) : const [],
  );
}

// ══════════════════════════════════════════════════════════════════════
// TEXT (owner decision V-10 = A, 08.09.2026: icon AND text)
// ══════════════════════════════════════════════════════════════════════
//
// "In S373 and S374 for days nobody saw whether a node can
// deliver at all — the display is no comfort, but the
// diagnostic tool."
//
// All building blocks of the line are EXISTING i18n keys that stand in all
// 34 locales: `readiness_*` (S368), `tray_readiness_multi`,
// `tray_service_stopped` and the four menu items `tray_menu_*`. Until S388
// `conn_*` (tier) and `reach_inbound_*` (mark) were added; both parts
// of the line have gone with the tier and the mark.

/// Translation without Flutter.
///
/// `AppLocale.get` is the version for the GUI and hangs on
/// `ChangeNotifier` + `SharedPreferences`; neither exists in the daemon.
/// The fallback chain is the same (locale → en → de → key)
/// and exists for the same reason: as defence in depth against
/// an emergency miss, not as the expected path (working rule 7).
String trayTranslate(String key, String localeCode) {
  final entry = translations[key];
  if (entry == null) return key;
  return entry[localeCode] ?? entry['en'] ?? entry['de'] ?? key;
}

/// Language code for the tray.
///
/// ── MEASURED GAP, expressly named ──────────────────────────
///
/// The daemon cannot see the language CHOSEN in the GUI: `AppLocale`
/// stores it in `SharedPreferences` (`app_locale.dart:_prefsKey`), and
/// that is a Flutter plugin. What the daemon has is the language of the
/// operating system — the same quantity from which `AppLocale`
/// starts by default (`_detectSystemLocale`). Whoever switches the
/// language in the GUI keeps seeing the tray in the system language. That is
/// a deviation and not a solution; it stands in the report on P8 as an
/// open point.
String trayLocaleCode() {
  try {
    final lang =
        Platform.localeName.split('_').first.split('.').first.toLowerCase();
    if (isTrayLanguage(lang)) return lang;
  } catch (_) {}
  return 'en';
}

/// Does the tray know this language?
///
/// Supported means: the key carries it. A second list of the
/// 34 codes would be a second truth; the set stands in
/// `translations.dart` itself — and `supportedLocales` from
/// `app_locale.dart` is not reachable here, because this file
/// must stay flutter-free (see header).
///
/// This function is at the same time the CHECK at the IPC seam: the language
/// comes there from a foreign message, and what the tray does not know
/// it does not set (`ipc_server.dart:_handleRequest`, `NativeTray.setLocale`).
bool isTrayLanguage(String code) =>
    translations[_probeKey]?.containsKey(code) ?? false;

/// A key that stands in all 34 locales, as a probe for
/// [trayLocaleCode]. `readiness_ready` is the right one for that: it
/// describes exactly the statement the tray is about, and thus
/// catches the same guard's attention if it ever became incomplete.
const String _probeKey = 'readiness_ready';

/// i18n key of the readiness state.
String readinessKey(String readiness) => switch (readiness) {
      kReadinessReady => 'readiness_ready',
      kReadinessConnecting => 'readiness_connecting',
      _ => 'readiness_searching',
    };

/// i18n key of the explanatory text for the readiness state — the same
/// that the badge in the statistics screen uses
/// (`network_stats_screen.dart`), so that a tap on the icon gives the same
/// answer as the statistics screen.
String readinessHintKey(String readiness) => switch (readiness) {
      kReadinessReady => 'readiness_ready_hint',
      kReadinessConnecting => 'readiness_connecting_hint',
      _ => 'readiness_searching_hint',
    };

/// The line the tray shows — the readiness state and nothing
/// beside it (§22.9: "The readiness state is the one statement the surfaces
/// carry").
String trayStatusText(TrayStatus s, String localeCode) {
  if (!s.serviceRunning) {
    return trayTranslate('tray_service_stopped', localeCode);
  }
  return readinessText(s, localeCode);
}

/// The readiness part of the line — with a number as soon as there is more than one
/// identity (V-10-c = b, 09.09.2026).
///
/// ── WHY UNCHANGED WITH ONE IDENTITY ──────────────────────────
///
/// Measured and then decided: with exactly one identity
/// "Bereit 1/1" would be a number without a statement — it answers a question
/// ("which of several?") that does not arise. The threshold is
/// therefore [TrayStatus.identityCount] > 1, and not "always".
///
/// ── WHY THE STATE WORD IS THAT OF THE MAXIMUM ──────────────────────
///
/// "Bereit 0/3" would be a claim that the counter next to it itself
/// refutes. If the maximum stands at `connecting`, the line reads
/// "Verbindet 0/3": the word says how far the best path is, the number
/// how many of them are finished. Both are true, and together they are
/// the information.
String readinessText(TrayStatus s, String localeCode) {
  final word = trayTranslate(readinessKey(s.readiness), localeCode);
  if (s.identityCount <= 1) return word;
  return trayTranslate('tray_readiness_multi', localeCode)
      .replaceAll('{state}', word)
      .replaceAll('{ready}', '${s.readyCount}')
      .replaceAll('{total}', '${s.identityCount}');
}

/// The menu line of a single identity: name and ITS state.
///
/// Without it "Bereit 2/3" would be a number nobody can act on —
/// the user would see that an identity is hanging, but not which.
String trayIdentityLineText(TrayIdentityLine z, String localeCode) {
  final word = trayTranslate(readinessKey(z.readiness), localeCode);
  final name = z.displayName.isEmpty ? '?' : z.displayName;
  return '$name — $word';
}

/// Short form for the window bar: name, counter, state.
String trayTitleText(String basis, TrayStatus s, String localeCode) {
  final counter = s.unreadCount > 0 ? '$basis (${s.unreadCount})' : basis;
  return '$counter — ${trayStatusText(s, localeCode)}';
}

// ══════════════════════════════════════════════════════════════════════
// DIE ZUSTANDSKANTE
// ══════════════════════════════════════════════════════════════════════

/// Sink of the tray state. `NativeTray` fulfils it.
typedef TrayStatusSink = void Function(TrayStatus status);

/// Carries the readiness state EVENT-DRIVEN to the tray.
///
/// No timer and no network traffic (working rule 5): [registerIdentity]
/// hooks onto the state edge that the service reports anyway, and
/// [refresh] passes on to the sink only what has changed.
///
/// ── WHY THE REGISTRATION IS A CHAIN ───────────────────────────────
///
/// `CleonaService.onStateChanged` is ONE field, not a stream — whoever
/// sets it displaces the predecessor. `IpcServer._hookServiceCallbacks`
/// (ipc_server.dart:203) therefore already chains: it remembers the old
/// value and calls it first. [registerIdentity] does the same, and the
/// daemon registers BEFORE building the IPC server — otherwise the
/// IPC server would have nothing to chain and the tray would lose its edge again.
class TrayStatusBinder {
  TrayStatusBinder({required this.sink});

  final TrayStatusSink sink;

  final Map<String, IdentityStatus Function()> _sources = {};
  bool _serviceRunning = false;
  TrayStatus? _last;

  /// The state last given to the sink (`null` before the first).
  TrayStatus? get last => _last;

  /// Number of registered identities.
  int get identityCount => _sources.length;

  /// Registers an identity.
  ///
  /// [read] returns its current contribution, [subscribe] hooks the
  /// passed callback onto the state edge of this identity.
  void registerIdentity(
    String id,
    IdentityStatus Function() read,
    void Function(void Function() onChange) subscribe,
  ) {
    _sources[id] = read;
    subscribe(refresh);
    refresh();
  }

  void unregisterIdentity(String id) {
    if (_sources.remove(id) != null) refresh();
  }

  /// Service started/stopped — the only quantity that does not come from an
  /// identity.
  void setServiceRunning(bool running) {
    if (_serviceRunning == running) return;
    _serviceRunning = running;
    refresh();
  }

  bool get serviceRunning => _serviceRunning;

  /// Recomputes and passes to the sink — but only on change.
  ///
  /// The equality check is not cosmetics: `onStateChanged` fires
  /// on every incoming message, every typing indicator and every
  /// contact change, and the Linux branch rebuilds a GTK menu per call
  /// (`native_tray.dart:_rebuildMenu`). Without the comparison the
  /// display would have sent the tray into a menu-building storm.
  void refresh() {
    final s = aggregateTrayStatus(
      serviceRunning: _serviceRunning,
      identities: _sources.values.map((f) => f()),
    );
    if (s == _last) return;
    _last = s;
    sink(s);
  }
}

/// File name (without extension) of the icon for the readiness state.
///
/// THREE images for three states (§22.9 in version A2: "all three
/// states"; "three tier images" / "three `.ico` variants"). They are three
/// of the five tier images up to S388, under their old file names — the
/// names are historical, the mapping is not:
///
///   searching  -> conn_weak    (the starving figure; the GUI lets it
///                               pulse and freezes after 30 s)
///   connecting -> conn_medium  (the yellow figure)
///   ready      -> conn_good    (the normal figure)
///
/// `conn_skeleton` (no network) and `conn_strong` (port mapping) have gone
/// with the tier: no network is `searching` for readiness,
/// and the port mapping was a property of the tier, not of the
/// state.
///
/// The GUI (`home_screen.dart`: `assets/<name>.png`) and both trays
/// use THIS function — the same image on all surfaces, without a second
/// mapping.
String readinessIconName(String readiness) => switch (readiness) {
      kReadinessReady => 'conn_good',
      kReadinessConnecting => 'conn_medium',
      _ => 'conn_weak',
    };

/// Path of the state image NEXT TO the base icon.
///
/// Both platforms search at the same place and for the same name;
/// only the extension differs, and the reason for that is
/// technical: the notification area under Windows accepts via
/// `Shell_NotifyIcon` exclusively an `.ico` resource, whereas
/// `app_indicator_set_icon_full` under Linux reads a PNG theme directory.
/// The same three images, two containers.
///
/// ── WHY BOTH SEPARATORS ─────────────────────────────────────────
///
/// The path is MIXED under Windows: `main.dart` forms the
/// base directory with a forward slash, `service_daemon.dart` appends with
/// `Platform.pathSeparator`. Exactly on that `ipcParentDir` failed
/// until S370 (`ipc_server.dart`, finding 13a) — there ONE
/// separator was searched and it hit the wrong one. Here therefore the LAST of
/// the two is taken, not a platform-dependent one.
///
/// Returns `null` if [iconPath] names no directory at all.
String? readinessIconSiblingPath(String iconPath, String readiness,
    {required String extension}) {
  final a = iconPath.lastIndexOf('/');
  final b = iconPath.lastIndexOf('\\');
  final i = a > b ? a : b;
  if (i <= 0) return null;
  final separator = iconPath.substring(i, i + 1);
  return '${iconPath.substring(0, i)}$separator'
      '${readinessIconName(readiness)}.$extension';
}

/// The state with which the tray starts.
///
/// `serviceRunning: true` (the daemon builds the tray BEFORE the services
/// run, and the menu should then offer "Dienst stoppen" as before),
/// but `searching`: at this point demonstrably no
/// neighbour has answered yet. The first real state report overwrites it
/// fractions of a second later.
const TrayStatus kTrayStartState = TrayStatus(
  serviceRunning: true,
  unreadCount: 0,
  readiness: kReadinessSearching,
);
