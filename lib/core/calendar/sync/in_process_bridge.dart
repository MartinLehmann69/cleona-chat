/// In-process bridge for the Calendar-Sync UI on Android.
///
/// On Desktop the GUI talks to the daemon via [IpcClient] which proxies
/// every Calendar-Sync call over the IPC socket. On Android the GUI runs
/// in-process — there is no IPC, just a direct [CleonaService]. The
/// [CalendarSyncScreen] is identical on both platforms but used to early-exit
/// with "Sync UI requires the IPC client (desktop GUI)" when handed an
/// in-process service.
///
/// This bridge mirrors the IpcClient Calendar-Sync surface 1:1 (same method
/// names, same signatures, same callback fields) but delegates directly to
/// `service.calendarSyncService`. The screen accepts either an IpcClient or
/// this bridge via a `dynamic`-typed `_ipc` getter — duck-typed dispatch
/// keeps the screen code unchanged.
///
/// Local-CalDAV-server endpoints (`caldav_server_*`) and the loopback Google
/// OAuth flow are deliberately stubbed out — they only make sense on
/// long-running desktop daemons (server lifetime + open ports). The screen
/// hides those sections when running on Android via `isOnAndroid`.
library;

import 'dart:async';

import 'package:cleona/core/calendar/sync/caldav_client.dart';
import 'package:cleona/core/calendar/sync/calendar_sync_service.dart';
import 'package:cleona/core/calendar/sync/sync_types.dart';
import 'package:cleona/core/service/cleona_service.dart';

class InProcessCalendarSyncBridge {
  final CleonaService _service;
  CalendarSyncService get _sync => _service.calendarSyncService;

  /// True when the local CalDAV server section should be hidden in the UI.
  /// On Android we don't run a long-running HTTP server.
  bool get isOnAndroid => true;

  // ── Event callbacks (same names/types as IpcClient) ───────────────
  void Function(Map<String, dynamic>)? onCalendarSyncCompleted;
  void Function(String accountEmail)? onCalendarSyncGoogleConnected;
  void Function(String error)? onCalendarSyncGoogleError;
  void Function(Map<String, dynamic>)? onCalendarSyncConflictPending;

  StreamSubscription<dynamic>? _sub;

  InProcessCalendarSyncBridge(this._service) {
    // Wire the in-service pending-conflict callback through to the screen.
    // Note: the IpcServer multiplexes one global subscription across all
    // GUIs — we replace that here with the bridge's own callback.
    _sync.onPendingConflictQueued = (conflict) {
      onCalendarSyncConflictPending?.call(conflict.toJson());
    };
  }

  /// Detach the conflict callback so we don't leak a closure when the
  /// screen disposes.
  void dispose() {
    _sync.onPendingConflictQueued = null;
    _sub?.cancel();
  }

  // ── Status / trigger ─────────────────────────────────────────────

  Future<Map<String, dynamic>> getCalendarSyncStatus() async {
    return _sync.publicStatusJson();
  }

  Future<bool> triggerCalendarSync() async {
    // Fire-and-forget; emit completion event when done so the screen
    // refreshes the same way it would after an IPC-triggered sync.
    unawaited(_sync.syncAll().then((result) {
      onCalendarSyncCompleted?.call({
        'ok': !result.hasErrors,
        'pulledNew': result.pulledNew,
        'pulledUpdated': result.pulledUpdated,
        'pulledDeleted': result.pulledDeleted,
        'pushedNew': result.pushedNew,
        'pushedUpdated': result.pushedUpdated,
        'pushedDeleted': result.pushedDeleted,
        'conflictsResolved': result.conflictsResolved,
        'errors': result.errors,
      });
    }));
    return true;
  }

  Future<void> setCalendarSyncForeground(bool foreground) async {
    _sync.setForeground(foreground);
  }

  // ── CalDAV ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> caldavListCalendars({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    // One-shot discovery without persisting — same flow the IpcServer uses.
    final cfg = CalDAVConfig(
      serverUrl: serverUrl,
      username: username,
      password: password,
      calendarUrl: null,
    );
    final calendars = await CalDAVClient.discoverAndList(cfg);
    return calendars.map((c) => c.toJson()).toList();
  }

  Future<Map<String, dynamic>> configureCaldav({
    required String serverUrl,
    required String username,
    required String password,
    String? calendarUrl,
    String direction = 'bidirectional',
  }) async {
    await _sync.configureCalDAV(CalDAVConfig(
      serverUrl: serverUrl,
      username: username,
      password: password,
      calendarUrl: calendarUrl,
      direction: CalendarSyncDirectionX.parse(direction),
    ));
    return _sync.publicStatusJson();
  }

  Future<void> removeCaldavSync() async {
    _sync.removeCalDAV();
  }

  // ── Google ───────────────────────────────────────────────────────
  // OAuth needs a loopback HTTP server which doesn't make sense on Android
  // (no permanent port + no system-browser-redirect to localhost).
  // The screen detects isOnAndroid and hides the Google section.

  Future<String> startGoogleOauth({required String clientId}) async {
    throw UnsupportedError(
      'Google Calendar OAuth uses a localhost-loopback flow which is not '
      'available on Android. Use CalDAV with an app-password or run Cleona '
      'on Desktop to set up the Google connection there (synced via S&F).',
    );
  }

  Future<void> removeGoogleSync() async {
    _sync.removeGoogle();
  }

  // ── Local ICS bridge ─────────────────────────────────────────────

  Future<void> configureLocalIcs({
    required String filePath,
    String direction = 'export',
    bool askOnConflict = false,
  }) async {
    await _sync.configureLocalIcs(LocalIcsConfig(
      filePath: filePath,
      direction: CalendarSyncDirectionX.parse(direction),
      askOnConflict: askOnConflict,
    ));
  }

  Future<void> removeLocalIcsSync() async {
    _sync.removeLocalIcs();
  }

  // ── Conflicts ────────────────────────────────────────────────────

  Future<Map<String, List<Map<String, dynamic>>>>
      listCalendarConflicts() async {
    return {
      'conflicts': _sync.conflicts.map((c) => c.toJson()).toList(),
      'pending': _sync.pendingConflicts.map((p) => p.toJson()).toList(),
    };
  }

  Future<void> clearCalendarConflicts() async {
    _sync.clearConflicts();
  }

  Future<bool> restoreCalendarConflict(String conflictId) async {
    return _sync.restoreConflict(conflictId);
  }

  Future<bool> resolvePendingCalendarConflict(
      String conflictId, String keep) async {
    return _sync.resolvePendingConflict(conflictId, keep);
  }

  // ── Local CalDAV server (Desktop-only) ────────────────────────────
  // Screen hides this section on Android.

  Future<Map<String, dynamic>> getCalDAVServerState() async => {};

  Future<Map<String, dynamic>> setCalDAVServerEnabled(bool enabled) async {
    throw UnsupportedError(
        'Local CalDAV server is desktop-only (long-running listener).');
  }

  Future<Map<String, dynamic>> regenerateCalDAVServerToken() async {
    throw UnsupportedError(
        'Local CalDAV server is desktop-only.');
  }

  Future<Map<String, dynamic>> setCalDAVServerPort(int port) async {
    throw UnsupportedError(
        'Local CalDAV server is desktop-only.');
  }
}
