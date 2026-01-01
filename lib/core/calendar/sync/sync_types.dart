/// Types for external calendar sync (CalDAV + Google Calendar).
///
/// Per §23.8 — external sync is opt-in per identity. Config + state are
/// persisted encrypted in the identity profile directory.
library;

enum CalendarSyncProvider {
  caldav,
  google,
  localIcs,
}

/// Direction of sync between Cleona and the external calendar.
enum CalendarSyncDirection {
  /// Cleona → External only (push).
  export,
  /// External → Cleona only (pull).
  import_,
  /// Two-way sync.
  bidirectional,
}

extension CalendarSyncDirectionX on CalendarSyncDirection {
  String get wire {
    switch (this) {
      case CalendarSyncDirection.export:
        return 'export';
      case CalendarSyncDirection.import_:
        return 'import';
      case CalendarSyncDirection.bidirectional:
        return 'bidirectional';
    }
  }

  static CalendarSyncDirection parse(String? s) {
    switch (s) {
      case 'export':
        return CalendarSyncDirection.export;
      case 'import':
        return CalendarSyncDirection.import_;
      default:
        return CalendarSyncDirection.bidirectional;
    }
  }
}

/// Configuration for a CalDAV account (Nextcloud, Thunderbird, Baikal, etc.).
class CalDAVConfig {
  /// Server base URL, e.g. `https://cloud.example.com/remote.php/dav`.
  final String serverUrl;
  final String username;
  /// App password or plain password. Stored encrypted on disk.
  final String password;
  /// Specific calendar URL to sync with (discovered or set manually).
  /// Null means: sync with the principal's default calendar.
  final String? calendarUrl;
  final CalendarSyncDirection direction;
  /// Only export events marked for sync (via tag or flag).
  final bool exportAllEvents;
  /// If true, queue conflicts for user resolution instead of last-write-wins.
  final bool askOnConflict;

  CalDAVConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.calendarUrl,
    this.direction = CalendarSyncDirection.bidirectional,
    this.exportAllEvents = true,
    this.askOnConflict = false,
  });

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        if (calendarUrl != null) 'calendarUrl': calendarUrl,
        'direction': direction.wire,
        'exportAllEvents': exportAllEvents,
        'askOnConflict': askOnConflict,
      };

  static CalDAVConfig fromJson(Map<String, dynamic> json) => CalDAVConfig(
        serverUrl: json['serverUrl'] as String,
        username: json['username'] as String,
        password: json['password'] as String,
        calendarUrl: json['calendarUrl'] as String?,
        direction: CalendarSyncDirectionX.parse(json['direction'] as String?),
        exportAllEvents: json['exportAllEvents'] as bool? ?? true,
        askOnConflict: json['askOnConflict'] as bool? ?? false,
      );

  /// Redacted form for status display (no password).
  Map<String, dynamic> toPublicJson() => {
        'serverUrl': serverUrl,
        'username': username,
        if (calendarUrl != null) 'calendarUrl': calendarUrl,
        'direction': direction.wire,
        'exportAllEvents': exportAllEvents,
        'askOnConflict': askOnConflict,
      };
}

/// Configuration for a Google Calendar account.
///
/// OAuth2 tokens are persisted encrypted. The refresh token is long-lived;
/// the access token is refreshed as needed.
class GoogleCalendarConfig {
  /// OAuth2 client ID (public, identifies the Cleona app).
  final String clientId;
  /// Account email of the signed-in user (for display).
  final String accountEmail;
  /// OAuth2 refresh token — the long-lived credential.
  final String refreshToken;
  /// OAuth2 access token — short-lived, refreshed as needed.
  String accessToken;
  /// Unix ms when the access token expires.
  int accessTokenExpiresAt;
  /// Google Calendar ID to sync with (e.g. `primary` or a specific calendar).
  final String calendarId;
  final CalendarSyncDirection direction;
  /// If true, queue conflicts for user resolution instead of last-write-wins.
  final bool askOnConflict;

  GoogleCalendarConfig({
    required this.clientId,
    required this.accountEmail,
    required this.refreshToken,
    this.accessToken = '',
    this.accessTokenExpiresAt = 0,
    this.calendarId = 'primary',
    this.direction = CalendarSyncDirection.bidirectional,
    this.askOnConflict = false,
  });

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'accountEmail': accountEmail,
        'refreshToken': refreshToken,
        'accessToken': accessToken,
        'accessTokenExpiresAt': accessTokenExpiresAt,
        'calendarId': calendarId,
        'direction': direction.wire,
        'askOnConflict': askOnConflict,
      };

  static GoogleCalendarConfig fromJson(Map<String, dynamic> json) =>
      GoogleCalendarConfig(
        clientId: json['clientId'] as String? ?? '',
        accountEmail: json['accountEmail'] as String? ?? '',
        refreshToken: json['refreshToken'] as String? ?? '',
        accessToken: json['accessToken'] as String? ?? '',
        accessTokenExpiresAt: json['accessTokenExpiresAt'] as int? ?? 0,
        calendarId: json['calendarId'] as String? ?? 'primary',
        direction:
            CalendarSyncDirectionX.parse(json['direction'] as String?),
        askOnConflict: json['askOnConflict'] as bool? ?? false,
      );

  /// Redacted form for status display (no tokens).
  Map<String, dynamic> toPublicJson() => {
        'accountEmail': accountEmail,
        'calendarId': calendarId,
        'direction': direction.wire,
        'askOnConflict': askOnConflict,
      };
}

/// Configuration for a local `.ics` file bridge.
///
/// Target audience: users who want their Cleona events visible in a desktop
/// calendar app (Thunderbird, Outlook, Apple Calendar) without involving a
/// CalDAV server. Thunderbird and Outlook can "subscribe" to a local `.ics`
/// file or URL and refresh it periodically.
///
/// - `export`: the daemon writes `filePath` whenever local events change,
///   plus on a timer as a safety net. The external app subscribes read-only.
/// - `import`: the daemon polls `filePath`'s mtime and re-imports when the
///   file changes on disk (e.g. the user drops in a fresh export from
///   another program).
/// - `bidirectional`: export + import, with the same last-write-wins rules
///   as CalDAV. Only meaningful if another program actually writes the file.
class LocalIcsConfig {
  /// Absolute filesystem path, e.g. `/home/alice/cleona-calendar.ics`.
  final String filePath;
  final CalendarSyncDirection direction;
  /// If true, queue conflicts for user resolution instead of last-write-wins.
  final bool askOnConflict;

  LocalIcsConfig({
    required this.filePath,
    this.direction = CalendarSyncDirection.export,
    this.askOnConflict = false,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'direction': direction.wire,
        'askOnConflict': askOnConflict,
      };

  static LocalIcsConfig fromJson(Map<String, dynamic> json) => LocalIcsConfig(
        filePath: json['filePath'] as String,
        direction: CalendarSyncDirectionX.parse(json['direction'] as String?),
        askOnConflict: json['askOnConflict'] as bool? ?? false,
      );

  Map<String, dynamic> toPublicJson() => {
        'filePath': filePath,
        'direction': direction.wire,
        'askOnConflict': askOnConflict,
      };
}

/// A recorded conflict between local and external versions of the same event.
///
/// Stored in the sync state so the user can inspect and, if desired, restore
/// the losing version. [source] identifies the provider that produced the
/// conflict; [winner] is the version that was kept (LOCAL or EXTERNAL);
/// [losingEvent] is the JSON snapshot of the discarded version.
class SyncConflict {
  final String id;
  final String eventId;
  final String source;        // "caldav" | "google" | "localIcs"
  final String winner;        // "local" | "external"
  final int detectedAtMs;
  final String? title;        // for display convenience
  final Map<String, dynamic> losingEvent;  // JSON snapshot
  bool resolved;
  bool restored;

  SyncConflict({
    required this.id,
    required this.eventId,
    required this.source,
    required this.winner,
    required this.detectedAtMs,
    required this.losingEvent,
    this.title,
    this.resolved = false,
    this.restored = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventId': eventId,
        'source': source,
        'winner': winner,
        'detectedAtMs': detectedAtMs,
        if (title != null) 'title': title,
        'losingEvent': losingEvent,
        'resolved': resolved,
        'restored': restored,
      };

  static SyncConflict fromJson(Map<String, dynamic> json) => SyncConflict(
        id: json['id'] as String,
        eventId: json['eventId'] as String,
        source: json['source'] as String,
        winner: json['winner'] as String,
        detectedAtMs: json['detectedAtMs'] as int? ?? 0,
        title: json['title'] as String?,
        losingEvent: (json['losingEvent'] as Map).cast<String, dynamic>(),
        resolved: json['resolved'] as bool? ?? false,
        restored: json['restored'] as bool? ?? false,
      );
}

/// A pending conflict awaiting user decision. Emitted when a provider has
/// `askOnConflict=true`. The user picks one side; sync then proceeds
/// accordingly and the entry is removed.
class PendingConflict {
  final String id;
  final String eventId;
  final String source;
  final Map<String, dynamic> localEvent;
  final Map<String, dynamic> externalEvent;
  final int detectedAtMs;

  PendingConflict({
    required this.id,
    required this.eventId,
    required this.source,
    required this.localEvent,
    required this.externalEvent,
    required this.detectedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventId': eventId,
        'source': source,
        'localEvent': localEvent,
        'externalEvent': externalEvent,
        'detectedAtMs': detectedAtMs,
      };

  static PendingConflict fromJson(Map<String, dynamic> json) => PendingConflict(
        id: json['id'] as String,
        eventId: json['eventId'] as String,
        source: json['source'] as String,
        localEvent: (json['localEvent'] as Map).cast<String, dynamic>(),
        externalEvent:
            (json['externalEvent'] as Map).cast<String, dynamic>(),
        detectedAtMs: json['detectedAtMs'] as int? ?? 0,
      );
}

/// Persistent per-event sync state.
///
/// Maps a Cleona eventId to the ETag/sequence of the last-synced version
/// on the external server, so we can detect conflicts and unchanged events.
class SyncedEventRef {
  /// Cleona event ID.
  final String eventId;
  /// External identifier (CalDAV href or Google event id).
  final String externalId;
  /// ETag or equivalent version token from the server.
  String etag;
  /// Unix ms — last server-observed modification time.
  int lastSeenMs;
  /// Unix ms — Cleona updatedAt at the time of last push/pull.
  int lastLocalUpdatedMs;

  SyncedEventRef({
    required this.eventId,
    required this.externalId,
    required this.etag,
    required this.lastSeenMs,
    required this.lastLocalUpdatedMs,
  });

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'externalId': externalId,
        'etag': etag,
        'lastSeenMs': lastSeenMs,
        'lastLocalUpdatedMs': lastLocalUpdatedMs,
      };

  static SyncedEventRef fromJson(Map<String, dynamic> json) => SyncedEventRef(
        eventId: json['eventId'] as String,
        externalId: json['externalId'] as String,
        etag: json['etag'] as String? ?? '',
        lastSeenMs: json['lastSeenMs'] as int? ?? 0,
        lastLocalUpdatedMs: json['lastLocalUpdatedMs'] as int? ?? 0,
      );
}

/// Aggregate sync status for an identity (CalDAV + Google + local ICS).
class SyncStatus {
  final bool caldavConfigured;
  final bool googleConfigured;
  final bool localIcsConfigured;
  final int lastSyncMs;         // 0 if never synced
  final bool lastSyncOk;
  final String? lastError;
  final int syncedEventCount;
  final int conflictsResolved;
  final int pendingConflicts;

  SyncStatus({
    this.caldavConfigured = false,
    this.googleConfigured = false,
    this.localIcsConfigured = false,
    this.lastSyncMs = 0,
    this.lastSyncOk = true,
    this.lastError,
    this.syncedEventCount = 0,
    this.conflictsResolved = 0,
    this.pendingConflicts = 0,
  });

  Map<String, dynamic> toJson() => {
        'caldavConfigured': caldavConfigured,
        'googleConfigured': googleConfigured,
        'localIcsConfigured': localIcsConfigured,
        'lastSyncMs': lastSyncMs,
        'lastSyncOk': lastSyncOk,
        if (lastError != null) 'lastError': lastError,
        'syncedEventCount': syncedEventCount,
        'conflictsResolved': conflictsResolved,
        'pendingConflicts': pendingConflicts,
      };
}

/// Result of a single sync run — counters + error list for logging/telemetry.
class SyncResult {
  int pulledNew = 0;
  int pulledUpdated = 0;
  int pulledDeleted = 0;
  int pushedNew = 0;
  int pushedUpdated = 0;
  int pushedDeleted = 0;
  int conflictsResolved = 0;
  final List<String> errors = [];

  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() => 'SyncResult(pulled: $pulledNew new / $pulledUpdated upd / $pulledDeleted del, '
      'pushed: $pushedNew new / $pushedUpdated upd / $pushedDeleted del, '
      'conflicts: $conflictsResolved, errors: ${errors.length})';
}
