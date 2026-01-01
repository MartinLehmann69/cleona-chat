import 'dart:async';
import 'dart:convert';

import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/ical_engine.dart';
import 'package:cleona/core/calendar/sync/caldav_client.dart';
import 'package:cleona/core/calendar/sync/google_calendar_client.dart';
import 'package:cleona/core/calendar/sync/local_ics_publisher.dart';
import 'package:cleona/core/calendar/sync/sync_types.dart';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/service/service_types.dart';

/// Per-identity calendar sync orchestrator.
///
/// Each identity owns at most one [CalDAVConfig] and one [GoogleCalendarConfig].
/// On start(), a periodic timer drives [syncAll]. Configs and per-event
/// sync refs are persisted encrypted under the identity's profile directory.
class CalendarSyncService {
  final String profileDir;
  final String identityId;
  final CalendarManager calendar;
  final FileEncryption fileEnc;
  final CLogger _log;

  /// Background sync cadence — used when the app is NOT in the foreground.
  /// FCM-style push is not available to a fully P2P client (no central
  /// HTTPS webhook to receive Google Calendar Watch notifications), so the
  /// service uses adaptive polling instead: aggressive when the user is
  /// actively looking at the calendar, conservative otherwise.
  final Duration backgroundInterval;

  /// Foreground sync cadence — used while the app signals it is in the
  /// foreground (e.g. the Calendar screen is open). Short enough to feel
  /// near-realtime, long enough to avoid rate limits.
  final Duration foregroundInterval;

  CalDAVConfig? _caldav;
  GoogleCalendarConfig? _google;
  LocalIcsConfig? _localIcs;
  late LocalIcsPublisher _icsPublisher;

  /// eventId → SyncedEventRef for CalDAV.
  final Map<String, SyncedEventRef> _caldavRefs = {};
  /// eventId → SyncedEventRef for Google.
  final Map<String, SyncedEventRef> _googleRefs = {};
  /// Google incremental sync token (per calendar).
  String? _googleSyncToken;

  /// Conflict log — kept bounded at [_maxConflictHistory] newest entries
  /// so long-running users don't accumulate unbounded state.
  final List<SyncConflict> _conflicts = [];
  /// Pending conflicts awaiting user decision (askOnConflict=true).
  final List<PendingConflict> _pendingConflicts = [];
  static const int _maxConflictHistory = 200;

  /// Callback invoked when a new pending conflict is queued. The daemon
  /// wires this to an IPC broadcast so the UI can show a dialog.
  void Function(PendingConflict conflict)? onPendingConflictQueued;

  Timer? _timer;
  bool _foreground = false;
  int _lastSyncMs = 0;
  bool _lastSyncOk = true;
  String? _lastError;
  bool _syncInProgress = false;

  CalendarSyncService({
    required this.profileDir,
    required this.identityId,
    required this.calendar,
    required this.fileEnc,
    Duration? interval,
    this.foregroundInterval = const Duration(minutes: 3),
    Duration? backgroundInterval,
  })  : backgroundInterval =
            backgroundInterval ?? interval ?? const Duration(minutes: 15),
        _log = CLogger.get('calsync[$identityId]') {
    _icsPublisher =
        LocalIcsPublisher(identityId: identityId, calendar: calendar);
  }

  /// Back-compat: legacy callers may read .interval as "the currently-active
  /// polling interval".
  Duration get interval =>
      _foreground ? foregroundInterval : backgroundInterval;

  /// Load persisted config + refs from disk. Safe to call repeatedly.
  void load() {
    try {
      final cfgJson = fileEnc.readJsonFile('$profileDir/calendar_sync_config.json');
      if (cfgJson != null) {
        final caldavRaw = cfgJson['caldav'] as Map<String, dynamic>?;
        if (caldavRaw != null) _caldav = CalDAVConfig.fromJson(caldavRaw);
        final googleRaw = cfgJson['google'] as Map<String, dynamic>?;
        if (googleRaw != null) _google = GoogleCalendarConfig.fromJson(googleRaw);
        final icsRaw = cfgJson['localIcs'] as Map<String, dynamic>?;
        if (icsRaw != null) _localIcs = LocalIcsConfig.fromJson(icsRaw);
      }
      final stateJson = fileEnc.readJsonFile('$profileDir/calendar_sync_state.json');
      if (stateJson != null) {
        final caldavRefs = stateJson['caldavRefs'] as Map<String, dynamic>? ?? {};
        for (final e in caldavRefs.entries) {
          _caldavRefs[e.key] =
              SyncedEventRef.fromJson(e.value as Map<String, dynamic>);
        }
        final googleRefs = stateJson['googleRefs'] as Map<String, dynamic>? ?? {};
        for (final e in googleRefs.entries) {
          _googleRefs[e.key] =
              SyncedEventRef.fromJson(e.value as Map<String, dynamic>);
        }
        _googleSyncToken = stateJson['googleSyncToken'] as String?;
        _lastSyncMs = stateJson['lastSyncMs'] as int? ?? 0;
        _lastSyncOk = stateJson['lastSyncOk'] as bool? ?? true;
        _lastError = stateJson['lastError'] as String?;
        final icsState = stateJson['localIcsState'] as Map<String, dynamic>?;
        if (icsState != null) _icsPublisher.fromJson(icsState);
        final conflicts = stateJson['conflicts'] as List?;
        if (conflicts != null) {
          for (final c in conflicts) {
            try {
              _conflicts
                  .add(SyncConflict.fromJson((c as Map).cast<String, dynamic>()));
            } catch (_) {/* ignore corrupt entry */}
          }
        }
        final pending = stateJson['pendingConflicts'] as List?;
        if (pending != null) {
          for (final c in pending) {
            try {
              _pendingConflicts.add(PendingConflict.fromJson(
                  (c as Map).cast<String, dynamic>()));
            } catch (_) {/* ignore */}
          }
        }
      }
      _log.info('Sync state loaded: caldav=${_caldav != null} '
          'google=${_google != null} localIcs=${_localIcs != null} '
          'refs=${_caldavRefs.length}+${_googleRefs.length} '
          'conflicts=${_conflicts.length}+${_pendingConflicts.length}pending');
    } catch (e) {
      _log.warn('Failed to load sync state: $e');
    }
  }

  void _saveConfig() {
    final json = <String, dynamic>{};
    if (_caldav != null) json['caldav'] = _caldav!.toJson();
    if (_google != null) json['google'] = _google!.toJson();
    if (_localIcs != null) json['localIcs'] = _localIcs!.toJson();
    fileEnc.writeJsonFile('$profileDir/calendar_sync_config.json', json);
  }

  void _saveState() {
    final json = <String, dynamic>{
      'caldavRefs': _caldavRefs.map((k, v) => MapEntry(k, v.toJson())),
      'googleRefs': _googleRefs.map((k, v) => MapEntry(k, v.toJson())),
      if (_googleSyncToken != null) 'googleSyncToken': _googleSyncToken,
      'lastSyncMs': _lastSyncMs,
      'lastSyncOk': _lastSyncOk,
      if (_lastError != null) 'lastError': _lastError,
      'localIcsState': _icsPublisher.toJson(),
      'conflicts': _conflicts.map((c) => c.toJson()).toList(),
      'pendingConflicts':
          _pendingConflicts.map((c) => c.toJson()).toList(),
    };
    fileEnc.writeJsonFile('$profileDir/calendar_sync_state.json', json);
  }

  /// Start the periodic timer. No-op if already running.
  void start() {
    _restartTimer();
    _log.info('Sync timer started (foreground=${foregroundInterval.inMinutes}min, '
        'background=${backgroundInterval.inMinutes}min, current=${interval.inMinutes}min)');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Switch between foreground (aggressive polling) and background
  /// (conservative polling) cadence. Called by the daemon when the UI
  /// reports app lifecycle changes.
  ///
  /// - `true` → poll every [foregroundInterval] (default 3 min). Use this
  ///   while the user has the Calendar screen open or the app in focus.
  /// - `false` → poll every [backgroundInterval] (default 15 min).
  ///
  /// When transitioning to foreground, also fire an immediate sync so the
  /// user sees fresh external state without waiting a full interval.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _log.info('Calendar sync interval → ${interval.inMinutes}min '
        '(${foreground ? "foreground" : "background"})');
    _restartTimer();
    if (foreground && (_caldav != null || _google != null)) {
      unawaited(syncAll());
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      if (_caldav == null && _google == null) return;
      unawaited(syncAll());
    });
  }

  // ── Config management ──────────────────────────────────────────────

  CalDAVConfig? get caldavConfig => _caldav;
  GoogleCalendarConfig? get googleConfig => _google;

  Future<void> configureCalDAV(CalDAVConfig config) async {
    // Validate — a probe of the principal URL verifies auth + server.
    final client = CalDAVClient(
      serverUrl: config.serverUrl,
      username: config.username,
      password: config.password,
    );
    try {
      final principal = await client.discoverPrincipal();
      _log.info('CalDAV principal: $principal');
      // If no calendar URL given, pick the first found.
      var effective = config;
      if (config.calendarUrl == null) {
        final home = await client.discoverCalendarHome(principal);
        final cals = await client.listCalendars(home);
        if (cals.isEmpty) {
          throw CalDAVException('No calendars found on server.');
        }
        effective = CalDAVConfig(
          serverUrl: config.serverUrl,
          username: config.username,
          password: config.password,
          calendarUrl: cals.first.url,
          direction: config.direction,
          exportAllEvents: config.exportAllEvents,
          askOnConflict: config.askOnConflict,
        );
        _log.info('Auto-selected calendar: ${cals.first.displayName} (${cals.first.url})');
      }
      _caldav = effective;
    } finally {
      client.close();
    }
    // Reset refs since we may have changed server/calendar.
    _caldavRefs.clear();
    _saveConfig();
    _saveState();
  }

  void configureGoogle(GoogleCalendarConfig config) {
    _google = config;
    _googleRefs.clear();
    _googleSyncToken = null;
    _saveConfig();
    _saveState();
  }

  void removeCalDAV() {
    _caldav = null;
    _caldavRefs.clear();
    _saveConfig();
    _saveState();
  }

  void removeGoogle() {
    _google = null;
    _googleRefs.clear();
    _googleSyncToken = null;
    _saveConfig();
    _saveState();
  }

  LocalIcsConfig? get localIcsConfig => _localIcs;

  /// Configure the local `.ics` bridge. [config.filePath] is validated by
  /// attempting an immediate export (if direction includes export) or an
  /// import read (if import-only).
  Future<void> configureLocalIcs(LocalIcsConfig config) async {
    _localIcs = config;
    _saveConfig();
    _saveState();
    // Fire an immediate export/import so the file exists right away.
    unawaited(syncAll());
  }

  void removeLocalIcs() {
    _localIcs = null;
    _saveConfig();
    _saveState();
  }

  // ── Conflict log accessors ────────────────────────────────────────

  /// All recorded conflicts, newest first.
  List<SyncConflict> get conflicts =>
      List.unmodifiable(_conflicts.reversed);

  /// Conflicts awaiting user decision (askOnConflict mode).
  List<PendingConflict> get pendingConflicts =>
      List.unmodifiable(_pendingConflicts);

  /// Wipe the conflict log. Does not affect any events.
  void clearConflicts() {
    _conflicts.clear();
    _saveState();
  }

  /// Restore the losing version of a conflict by overwriting the current
  /// local event with the snapshot. Returns true if the conflict existed
  /// and the losing event was a sensible replacement.
  bool restoreConflict(String conflictId) {
    final idx = _conflicts.indexWhere((c) => c.id == conflictId);
    if (idx < 0) return false;
    final c = _conflicts[idx];
    try {
      final losing = CalendarEvent.fromJson(c.losingEvent);
      calendar.events[losing.eventId] = losing;
      calendar.save();
      _conflicts[idx] = SyncConflict(
        id: c.id,
        eventId: c.eventId,
        source: c.source,
        winner: c.winner,
        detectedAtMs: c.detectedAtMs,
        title: c.title,
        losingEvent: c.losingEvent,
        resolved: true,
        restored: true,
      );
      _saveState();
      _log.info('Restored losing event ${losing.eventId} from conflict $conflictId');
      return true;
    } catch (e) {
      _log.warn('restoreConflict failed: $e');
      return false;
    }
  }

  /// Resolve a pending (askOnConflict) conflict by picking one side.
  /// [keep] is "local" or "external".
  bool resolvePendingConflict(String conflictId, String keep) {
    final idx = _pendingConflicts.indexWhere((c) => c.id == conflictId);
    if (idx < 0) return false;
    final c = _pendingConflicts[idx];
    try {
      final winner = (keep == 'external')
          ? CalendarEvent.fromJson(c.externalEvent)
          : CalendarEvent.fromJson(c.localEvent);
      // Bump updatedAt so the decision sticks against stale external copies.
      winner.updatedAt = DateTime.now().millisecondsSinceEpoch;
      calendar.events[winner.eventId] = winner;
      calendar.save();
      // Record a resolved-history entry too, for transparency.
      _recordConflict(SyncConflict(
        id: c.id,
        eventId: c.eventId,
        source: c.source,
        winner: keep == 'external' ? 'external' : 'local',
        detectedAtMs: c.detectedAtMs,
        title: winner.title,
        losingEvent:
            keep == 'external' ? c.localEvent : c.externalEvent,
        resolved: true,
      ));
      _pendingConflicts.removeAt(idx);
      _saveState();
      return true;
    } catch (e) {
      _log.warn('resolvePendingConflict failed: $e');
      return false;
    }
  }

  void _recordConflict(SyncConflict c) {
    _conflicts.add(c);
    // Keep the newest [_maxConflictHistory] entries — drop the oldest.
    while (_conflicts.length > _maxConflictHistory) {
      _conflicts.removeAt(0);
    }
  }

  void _queuePending(PendingConflict c) {
    // Dedup: if an unresolved conflict for the same (source, eventId) is
    // already queued, replace it with the newer evidence.
    _pendingConflicts.removeWhere(
        (p) => p.source == c.source && p.eventId == c.eventId);
    _pendingConflicts.add(c);
    onPendingConflictQueued?.call(c);
  }

  SyncStatus get status => SyncStatus(
        caldavConfigured: _caldav != null,
        googleConfigured: _google != null,
        localIcsConfigured: _localIcs != null,
        lastSyncMs: _lastSyncMs,
        lastSyncOk: _lastSyncOk,
        lastError: _lastError,
        syncedEventCount: _caldavRefs.length + _googleRefs.length,
        conflictsResolved: _conflicts.length,
        pendingConflicts: _pendingConflicts.length,
      );

  /// Redacted public representation for status UI.
  Map<String, dynamic> publicStatusJson() => {
        ...status.toJson(),
        if (_caldav != null) 'caldav': _caldav!.toPublicJson(),
        if (_google != null) 'google': _google!.toPublicJson(),
        if (_localIcs != null) 'localIcs': _localIcs!.toPublicJson(),
      };

  // ── Sync logic ────────────────────────────────────────────────────

  /// Sync every configured provider.
  Future<SyncResult> syncAll() async {
    if (_syncInProgress) {
      _log.debug('syncAll: already in progress, skipping');
      return SyncResult()..errors.add('already in progress');
    }
    _syncInProgress = true;
    final merged = SyncResult();
    try {
      if (_caldav != null) {
        try {
          final r = await _syncCalDAV();
          _mergeResult(merged, r);
        } catch (e) {
          _log.warn('CalDAV sync failed: $e');
          merged.errors.add('caldav: $e');
        }
      }
      if (_google != null) {
        try {
          final r = await _syncGoogle();
          _mergeResult(merged, r);
        } catch (e) {
          _log.warn('Google sync failed: $e');
          merged.errors.add('google: $e');
        }
      }
      if (_localIcs != null) {
        try {
          final r = await _syncLocalIcs();
          _mergeResult(merged, r);
        } catch (e) {
          _log.warn('Local ICS sync failed: $e');
          merged.errors.add('localIcs: $e');
        }
      }
      _lastSyncMs = DateTime.now().millisecondsSinceEpoch;
      _lastSyncOk = !merged.hasErrors;
      _lastError = merged.hasErrors ? merged.errors.join('; ') : null;
      _saveState();
      _log.info('Sync complete: $merged');
    } finally {
      _syncInProgress = false;
    }
    return merged;
  }

  void _mergeResult(SyncResult target, SyncResult source) {
    target.pulledNew += source.pulledNew;
    target.pulledUpdated += source.pulledUpdated;
    target.pulledDeleted += source.pulledDeleted;
    target.pushedNew += source.pushedNew;
    target.pushedUpdated += source.pushedUpdated;
    target.pushedDeleted += source.pushedDeleted;
    target.conflictsResolved += source.conflictsResolved;
    target.errors.addAll(source.errors);
  }

  // ── CalDAV sync ───────────────────────────────────────────────────

  Future<SyncResult> _syncCalDAV() async {
    final cfg = _caldav!;
    if (cfg.calendarUrl == null) {
      throw CalDAVException('CalDAV config has no calendar URL.');
    }
    final client = CalDAVClient(
      serverUrl: cfg.serverUrl,
      username: cfg.username,
      password: cfg.password,
    );
    final result = SyncResult();
    try {
      // Step 1 — pull. List server event ETags.
      final serverRefs = await client.listEvents(cfg.calendarUrl!);
      final serverByHref = {for (final r in serverRefs) r.href: r};

      if (cfg.direction != CalendarSyncDirection.export) {
        await _caldavPullPhase(client, serverRefs, result);
      }

      // Step 2 — push local events (insert / update / delete).
      if (cfg.direction != CalendarSyncDirection.import_) {
        await _caldavPushPhase(client, cfg, serverByHref, result);
      }
    } finally {
      client.close();
    }
    return result;
  }

  Future<void> _caldavPullPhase(
    CalDAVClient client,
    List<CalDAVEventRef> serverRefs,
    SyncResult result,
  ) async {
    // Map href → ref in our local state (inverse of _caldavRefs).
    final localByHref = <String, SyncedEventRef>{};
    for (final r in _caldavRefs.values) {
      localByHref[r.externalId] = r;
    }
    final serverHrefs = serverRefs.map((e) => e.href).toSet();

    // Fetch new / updated events.
    for (final ref in serverRefs) {
      final local = localByHref[ref.href];
      if (local != null && local.etag == ref.etag) {
        continue; // Unchanged since last sync.
      }
      try {
        final data = await client.getEvent(ref.href);
        final events = ICalEngine.importFromIcs(
          data.icalData,
          identityId: identityId,
          createdBy: identityId,
        );
        for (final event in events) {
          final existing = calendar.events[event.eventId];
          if (existing != null) {
            // Conflict resolution — newer wins (last-write-wins per §23.8.2),
            // unless askOnConflict is on, in which case we queue for prompt.
            if (existing.updatedAt > event.updatedAt) {
              if (_caldav?.askOnConflict == true) {
                _queuePending(PendingConflict(
                  id: 'caldav:${event.eventId}:${DateTime.now().millisecondsSinceEpoch}',
                  eventId: event.eventId,
                  source: 'caldav',
                  localEvent: existing.toJson(),
                  externalEvent: event.toJson(),
                  detectedAtMs: DateTime.now().millisecondsSinceEpoch,
                ));
                continue;
              }
              _recordConflict(SyncConflict(
                id: 'caldav:${event.eventId}:${DateTime.now().millisecondsSinceEpoch}',
                eventId: event.eventId,
                source: 'caldav',
                winner: 'local',
                detectedAtMs: DateTime.now().millisecondsSinceEpoch,
                title: existing.title,
                losingEvent: event.toJson(),
              ));
              result.conflictsResolved++;
              continue;
            }
            if (existing.updatedAt < event.updatedAt) {
              _recordConflict(SyncConflict(
                id: 'caldav:${event.eventId}:${DateTime.now().millisecondsSinceEpoch}',
                eventId: event.eventId,
                source: 'caldav',
                winner: 'external',
                detectedAtMs: DateTime.now().millisecondsSinceEpoch,
                title: event.title,
                losingEvent: existing.toJson(),
              ));
            }
            calendar.events[event.eventId] = event;
            result.pulledUpdated++;
          } else {
            calendar.events[event.eventId] = event;
            result.pulledNew++;
          }
          _caldavRefs[event.eventId] = SyncedEventRef(
            eventId: event.eventId,
            externalId: ref.href,
            etag: data.etag.isNotEmpty ? data.etag : ref.etag,
            lastSeenMs: DateTime.now().millisecondsSinceEpoch,
            lastLocalUpdatedMs: event.updatedAt,
          );
        }
      } catch (e) {
        result.errors.add('caldav pull ${ref.href}: $e');
      }
    }
    calendar.save();

    // Detect server-side deletes — entries we had in refs but no longer on server.
    final toForget = <String>[];
    for (final entry in _caldavRefs.entries) {
      if (!serverHrefs.contains(entry.value.externalId)) {
        // Server deleted it — remove locally unless local is newer (rare).
        final local = calendar.events[entry.key];
        if (local != null &&
            local.updatedAt > entry.value.lastLocalUpdatedMs + 1000) {
          // Local edit since last sync — keep it; will be re-pushed.
          continue;
        }
        calendar.deleteEvent(entry.key);
        result.pulledDeleted++;
        toForget.add(entry.key);
      }
    }
    for (final id in toForget) {
      _caldavRefs.remove(id);
    }
  }

  Future<void> _caldavPushPhase(
    CalDAVClient client,
    CalDAVConfig cfg,
    Map<String, CalDAVEventRef> serverByHref,
    SyncResult result,
  ) async {
    // For each local event, push if new or modified since last sync.
    for (final event in calendar.events.values.toList()) {
      if (event.cancelled) continue;
      final ref = _caldavRefs[event.eventId];
      final icalData = ICalEngine.exportEventToIcs(event);
      if (ref == null) {
        // New local event — insert.
        final href = _joinPath(cfg.calendarUrl!, '${event.eventId}.ics');
        try {
          final etag = await client.putEvent(
            href,
            icalData: icalData,
            ifNoneMatch: '*',
          );
          _caldavRefs[event.eventId] = SyncedEventRef(
            eventId: event.eventId,
            externalId: href,
            etag: etag ?? '',
            lastSeenMs: DateTime.now().millisecondsSinceEpoch,
            lastLocalUpdatedMs: event.updatedAt,
          );
          result.pushedNew++;
        } catch (e) {
          result.errors.add('caldav push ${event.eventId}: $e');
        }
      } else if (event.updatedAt > ref.lastLocalUpdatedMs) {
        // Local changed since last sync — update.
        try {
          final etag = await client.putEvent(
            ref.externalId,
            icalData: icalData,
            ifMatch: ref.etag.isNotEmpty ? '"${ref.etag}"' : null,
          );
          ref.etag = etag ?? ref.etag;
          ref.lastSeenMs = DateTime.now().millisecondsSinceEpoch;
          ref.lastLocalUpdatedMs = event.updatedAt;
          result.pushedUpdated++;
        } catch (e) {
          // If If-Match failed (412), server has newer version; pull will fix it next run.
          result.errors.add('caldav push update ${event.eventId}: $e');
        }
      }
    }

    // For each local deletion (ref exists but event gone), DELETE on server.
    final removedRefs = <String>[];
    for (final entry in _caldavRefs.entries.toList()) {
      if (!calendar.events.containsKey(entry.key)) {
        try {
          await client.deleteEvent(entry.value.externalId);
          removedRefs.add(entry.key);
          result.pushedDeleted++;
        } catch (e) {
          result.errors.add('caldav delete ${entry.key}: $e');
        }
      }
    }
    for (final id in removedRefs) {
      _caldavRefs.remove(id);
    }
  }

  // ── Google sync ───────────────────────────────────────────────────

  Future<SyncResult> _syncGoogle() async {
    final cfg = _google!;
    final client = GoogleCalendarClient(cfg);
    final result = SyncResult();
    try {
      await client.ensureAccessToken();
      // Persist any refreshed tokens.
      _google = client.config;
      _saveConfig();

      // Pull phase — use incremental sync token where possible.
      if (cfg.direction != CalendarSyncDirection.export) {
        try {
          await _googlePullPhase(client, result);
        } on GoogleSyncTokenExpired {
          _log.info('Google sync token expired, doing full re-sync.');
          _googleSyncToken = null;
          _googleRefs.clear();
          await _googlePullPhase(client, result);
        }
      }

      // Push phase.
      if (cfg.direction != CalendarSyncDirection.import_) {
        await _googlePushPhase(client, result);
      }
    } finally {
      client.close();
    }
    return result;
  }

  Future<void> _googlePullPhase(
      GoogleCalendarClient client, SyncResult result) async {
    String? pageToken;
    String? nextSyncToken;

    // Cap the first full sync to a reasonable window (±2 years) to avoid
    // pulling years of historical events on first connect.
    final now = DateTime.now();
    final timeMin = now.subtract(const Duration(days: 730));
    final timeMax = now.add(const Duration(days: 730));

    while (true) {
      final page = await client.listEvents(
        syncToken: _googleSyncToken,
        pageToken: pageToken,
        timeMin: _googleSyncToken == null ? timeMin : null,
        timeMax: _googleSyncToken == null ? timeMax : null,
      );

      for (final googleEvent in page.events) {
        _applyGoogleEvent(googleEvent, result);
      }

      nextSyncToken = page.nextSyncToken ?? nextSyncToken;
      pageToken = page.nextPageToken;
      if (pageToken == null) break;
    }

    if (nextSyncToken != null) _googleSyncToken = nextSyncToken;
    calendar.save();
  }

  void _applyGoogleEvent(Map<String, dynamic> ge, SyncResult result) {
    final status = ge['status'] as String?;
    final googleId = ge['id'] as String?;
    if (googleId == null) return;

    // Look for an existing local event by externalId.
    String? localEventId;
    for (final entry in _googleRefs.entries) {
      if (entry.value.externalId == googleId) {
        localEventId = entry.key;
        break;
      }
    }

    if (status == 'cancelled') {
      if (localEventId != null) {
        calendar.deleteEvent(localEventId);
        _googleRefs.remove(localEventId);
        result.pulledDeleted++;
      }
      return;
    }

    final event = _googleEventToCleona(ge);
    if (event == null) return;

    if (localEventId != null) {
      final existing = calendar.events[localEventId];
      if (existing != null && existing.updatedAt > event.updatedAt) {
        // Local is newer — honor askOnConflict if set.
        if (_google?.askOnConflict == true) {
          _queuePending(PendingConflict(
            id: 'google:$localEventId:${DateTime.now().millisecondsSinceEpoch}',
            eventId: localEventId,
            source: 'google',
            localEvent: existing.toJson(),
            externalEvent: event.toJson(),
            detectedAtMs: DateTime.now().millisecondsSinceEpoch,
          ));
          return;
        }
        _recordConflict(SyncConflict(
          id: 'google:$localEventId:${DateTime.now().millisecondsSinceEpoch}',
          eventId: localEventId,
          source: 'google',
          winner: 'local',
          detectedAtMs: DateTime.now().millisecondsSinceEpoch,
          title: existing.title,
          losingEvent: event.toJson(),
        ));
        result.conflictsResolved++;
        return;
      }
      if (existing != null && existing.updatedAt < event.updatedAt) {
        _recordConflict(SyncConflict(
          id: 'google:$localEventId:${DateTime.now().millisecondsSinceEpoch}',
          eventId: localEventId,
          source: 'google',
          winner: 'external',
          detectedAtMs: DateTime.now().millisecondsSinceEpoch,
          title: event.title,
          losingEvent: existing.toJson(),
        ));
      }
    }

    final eventId = localEventId ?? event.eventId;
    final effective = CalendarEvent.fromJson({
      ...event.toJson(),
      'eventId': eventId,
      'identityId': identityId,
    });

    final existed = calendar.events.containsKey(eventId);
    calendar.events[eventId] = effective;
    if (existed) {
      result.pulledUpdated++;
    } else {
      result.pulledNew++;
    }
    _googleRefs[eventId] = SyncedEventRef(
      eventId: eventId,
      externalId: googleId,
      etag: ge['etag'] as String? ?? '',
      lastSeenMs: DateTime.now().millisecondsSinceEpoch,
      lastLocalUpdatedMs: effective.updatedAt,
    );
  }

  Future<void> _googlePushPhase(
      GoogleCalendarClient client, SyncResult result) async {
    for (final event in calendar.events.values.toList()) {
      if (event.cancelled) continue;
      final ref = _googleRefs[event.eventId];
      final body = _cleonaEventToGoogle(event);
      if (ref == null) {
        try {
          final inserted = await client.insertEvent(body);
          _googleRefs[event.eventId] = SyncedEventRef(
            eventId: event.eventId,
            externalId: inserted['id'] as String? ?? '',
            etag: inserted['etag'] as String? ?? '',
            lastSeenMs: DateTime.now().millisecondsSinceEpoch,
            lastLocalUpdatedMs: event.updatedAt,
          );
          result.pushedNew++;
        } catch (e) {
          result.errors.add('google insert ${event.eventId}: $e');
        }
      } else if (event.updatedAt > ref.lastLocalUpdatedMs) {
        try {
          final updated =
              await client.updateEvent(ref.externalId, body);
          ref.etag = updated['etag'] as String? ?? ref.etag;
          ref.lastSeenMs = DateTime.now().millisecondsSinceEpoch;
          ref.lastLocalUpdatedMs = event.updatedAt;
          result.pushedUpdated++;
        } catch (e) {
          result.errors.add('google update ${event.eventId}: $e');
        }
      }
    }

    final removedRefs = <String>[];
    for (final entry in _googleRefs.entries.toList()) {
      if (!calendar.events.containsKey(entry.key)) {
        try {
          await client.deleteEvent(entry.value.externalId);
          removedRefs.add(entry.key);
          result.pushedDeleted++;
        } catch (e) {
          result.errors.add('google delete ${entry.key}: $e');
        }
      }
    }
    for (final id in removedRefs) {
      _googleRefs.remove(id);
    }
  }

  // ── Google ⇄ Cleona conversion ───────────────────────────────────

  /// Convert a Google Calendar event JSON to a [CalendarEvent].
  /// Returns null if the event lacks required fields.
  CalendarEvent? _googleEventToCleona(Map<String, dynamic> ge) {
    final summary = ge['summary'] as String? ?? '';
    if (summary.isEmpty) return null;

    final start = _googleDateTime(ge['start']);
    final end = _googleDateTime(ge['end']);
    if (start == null) return null;

    final allDay = (ge['start'] as Map?)?['date'] != null;

    final recurrence = ge['recurrence'];
    String? rrule;
    if (recurrence is List) {
      for (final line in recurrence.whereType<String>()) {
        if (line.startsWith('RRULE:')) {
          rrule = line.substring(6);
          break;
        }
      }
    }

    final updatedStr = ge['updated'] as String?;
    final updatedAt = updatedStr != null
        ? DateTime.tryParse(updatedStr)?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch
        : DateTime.now().millisecondsSinceEpoch;
    final createdStr = ge['created'] as String?;
    final createdAt =
        createdStr != null ? DateTime.tryParse(createdStr)?.millisecondsSinceEpoch : null;

    final duration = end != null ? end - start : 60 * 60 * 1000;

    // Reminders
    final reminders = <int>[];
    final overrides = (ge['reminders'] as Map?)?['overrides'];
    if (overrides is List) {
      for (final o in overrides.whereType<Map>()) {
        final minutes = (o['minutes'] as num?)?.toInt();
        if (minutes != null && minutes > 0) reminders.add(minutes);
      }
    }

    return CalendarEvent(
      eventId: ge['id'] as String? ?? _newId(),
      identityId: identityId,
      title: summary,
      description: ge['description'] as String?,
      location: ge['location'] as String?,
      startTime: start,
      endTime: start + duration,
      allDay: allDay,
      timeZone: (ge['start'] as Map?)?['timeZone'] as String? ?? 'UTC',
      recurrenceRule: rrule,
      reminders: reminders.isNotEmpty ? reminders : null,
      createdBy: identityId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Convert a [CalendarEvent] to Google Calendar event JSON.
  Map<String, dynamic> _cleonaEventToGoogle(CalendarEvent event) {
    final body = <String, dynamic>{
      'summary': event.title,
      if (event.description != null) 'description': event.description,
      if (event.location != null) 'location': event.location,
      'start': _googleTimeField(event.startTime, event.allDay, event.timeZone),
      'end': _googleTimeField(event.endTime, event.allDay, event.timeZone),
    };
    if (event.recurrenceRule != null && event.recurrenceRule!.isNotEmpty) {
      final rule = event.recurrenceRule!.startsWith('RRULE:')
          ? event.recurrenceRule!
          : 'RRULE:${event.recurrenceRule}';
      body['recurrence'] = [rule];
    }
    if (event.reminders.isNotEmpty) {
      body['reminders'] = {
        'useDefault': false,
        'overrides': [
          for (final m in event.reminders)
            {'method': 'popup', 'minutes': m},
        ],
      };
    }
    return body;
  }

  static int? _googleDateTime(dynamic field) {
    if (field is! Map) return null;
    final dt = field['dateTime'] as String?;
    final d = field['date'] as String?;
    if (dt != null) {
      return DateTime.tryParse(dt)?.millisecondsSinceEpoch;
    }
    if (d != null) {
      return DateTime.tryParse('${d}T00:00:00Z')?.millisecondsSinceEpoch;
    }
    return null;
  }

  static Map<String, dynamic> _googleTimeField(
      int unixMs, bool allDay, String timeZone) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true);
    if (allDay) {
      final date =
          '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      return {'date': date};
    }
    return {
      'dateTime': dt.toIso8601String(),
      'timeZone': timeZone,
    };
  }

  static String _newId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'gcal-$now-${now.hashCode.toRadixString(16)}';
  }

  static String _joinPath(String base, String segment) {
    final normalized = base.endsWith('/') ? base : '$base/';
    return '$normalized$segment';
  }

  /// Diagnostic dump for the status IPC.
  String debugDump() => jsonEncode({
        'caldav': _caldav?.toPublicJson(),
        'google': _google?.toPublicJson(),
        'localIcs': _localIcs?.toPublicJson(),
        'caldavRefs': _caldavRefs.length,
        'googleRefs': _googleRefs.length,
        'googleSyncToken': _googleSyncToken,
        'lastSyncMs': _lastSyncMs,
        'conflicts': _conflicts.length,
        'pendingConflicts': _pendingConflicts.length,
      });

  // ── Local ICS sync ────────────────────────────────────────────────

  Future<SyncResult> _syncLocalIcs() async {
    final cfg = _localIcs!;
    final result = SyncResult();

    // Import phase first — pull external edits before we potentially
    // overwrite them with our own export.
    if (cfg.direction != CalendarSyncDirection.export) {
      final imported = await _icsPublisher.importIfChanged(
        cfg.filePath,
        onConflict: (c) {
          _recordConflict(c);
          result.conflictsResolved++;
        },
        askOnConflict: cfg.askOnConflict,
        onPendingConflict: _queuePending,
      );
      result.pulledNew += imported.pulledNew;
      result.pulledUpdated += imported.pulledUpdated;
      result.pulledDeleted += imported.pulledDeleted;
      result.errors.addAll(imported.errors);
    }

    if (cfg.direction != CalendarSyncDirection.import_) {
      final exported = await _icsPublisher.export(cfg.filePath);
      result.pushedNew += exported.eventsExported;
      result.errors.addAll(exported.errors);
    }

    return result;
  }
}
