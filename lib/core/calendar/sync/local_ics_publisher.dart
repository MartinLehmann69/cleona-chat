import 'dart:async';
import 'dart:io';

import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/ical_engine.dart';
import 'package:cleona/core/calendar/sync/sync_types.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/service/service_types.dart';

/// Bridges the local calendar to a plain `.ics` file on disk.
///
/// Use-cases:
/// - Thunderbird → "Subscribe to a local calendar file" pointing at the path.
/// - Outlook → "Add internet calendar" with a `file://` URL.
/// - Apple Calendar → File → New Calendar Subscription.
/// - Any backup / export workflow that consumes iCalendar files.
///
/// Unlike CalDAV this is not a live server — external apps poll the file at
/// their own rate (typically minutes to hours). The publisher:
/// - on `export()` writes a fresh `.ics` snapshot atomically
/// - on `importIfChanged()` re-reads the file when mtime advanced
///
/// Conflict handling mirrors CalDAV: last-write-wins based on `updatedAt`,
/// with the losing side recorded via [onConflict] so the caller can feed
/// the sync-state's conflict log.
class LocalIcsPublisher {
  final String identityId;
  final CalendarManager calendar;
  final CLogger _log;

  LocalIcsPublisher({
    required this.identityId,
    required this.calendar,
  }) : _log = CLogger.get('icspub[$identityId]');

  static const int _maxImportBytes = 10 * 1024 * 1024;

  /// Last mtime we observed on disk — used so importIfChanged only re-parses
  /// when the file genuinely moved.
  int _lastSeenMtimeMs = 0;

  /// Hashes of exported content by eventId → so we don't re-detect our own
  /// writes as "file changed externally".
  String? _lastExportHash;

  /// Export every non-cancelled event to [filePath] atomically.
  ///
  /// Atomicity: writes to `<path>.tmp` then renames — readers on Thunderbird
  /// et al. never see a half-finished file even if we're killed mid-write.
  Future<LocalIcsResult> export(String filePath) async {
    final result = LocalIcsResult();
    try {
      // Refuse if either the target or its tmp sibling is a symlink —
      // another user or app on the same machine could otherwise swap the
      // path to point at a privileged file (e.g. ~/.ssh/authorized_keys)
      // and hijack our write.
      final targetType =
          FileSystemEntity.typeSync(filePath, followLinks: false);
      if (targetType == FileSystemEntityType.link) {
        result.errors
            .add('export $filePath: refusing to overwrite a symlink');
        _log.warn('Refused symlink target at $filePath');
        return result;
      }
      final tmpPath = '$filePath.tmp';
      final tmpType =
          FileSystemEntity.typeSync(tmpPath, followLinks: false);
      if (tmpType == FileSystemEntityType.link) {
        result.errors
            .add('export $filePath: $tmpPath is a symlink, aborting');
        _log.warn('Refused symlink tmp at $tmpPath');
        return result;
      }

      final events = calendar.events.values
          .where((e) => !e.cancelled)
          .toList(growable: false);
      final ics = ICalEngine.exportToIcs(events, calendarName: 'Cleona');
      final tmp = File(tmpPath);
      await tmp.parent.create(recursive: true);
      await tmp.writeAsString(ics, flush: true);
      await tmp.rename(filePath);

      // Record mtime + content hash so the subsequent watcher call doesn't
      // treat *our own write* as an external change.
      final stat = File(filePath).statSync();
      _lastSeenMtimeMs = stat.modified.millisecondsSinceEpoch;
      _lastExportHash = _hashContent(ics);

      result.eventsExported = events.length;
      _log.info('Exported ${events.length} event(s) to $filePath');
    } catch (e) {
      result.errors.add('export $filePath: $e');
      _log.warn('Export failed: $e');
    }
    return result;
  }

  /// Import from [filePath] if the file has changed since the last check.
  ///
  /// Returns the diff (pulledNew, pulledUpdated, pulledDeleted) and any
  /// conflicts produced by last-write-wins resolution.
  Future<LocalIcsResult> importIfChanged(
    String filePath, {
    required void Function(SyncConflict) onConflict,
    required bool askOnConflict,
    required void Function(PendingConflict) onPendingConflict,
  }) async {
    final result = LocalIcsResult();
    final file = File(filePath);
    if (!file.existsSync()) {
      result.errors.add('file not found: $filePath');
      return result;
    }

    try {
      final stat = file.statSync();
      final mtimeMs = stat.modified.millisecondsSinceEpoch;
      // Skip if mtime hasn't moved past what we've already processed.
      if (mtimeMs <= _lastSeenMtimeMs) return result;

      // Bounded read — an attacker-controlled shared directory could drop
      // a multi-gigabyte file here and OOM the daemon otherwise. 10 MB
      // accommodates calendars with thousands of events plus attendee
      // lists and recurrence exceptions.
      if (stat.size > _maxImportBytes) {
        result.errors.add(
            'import $filePath: file exceeds ${_maxImportBytes ~/ (1024 * 1024)} MB (${stat.size} bytes)');
        _log.warn('Refused oversized ICS file at $filePath (${stat.size} bytes)');
        _lastSeenMtimeMs = mtimeMs;
        return result;
      }

      final text = await file.readAsString();
      // Skip if the content is byte-identical to our last export (it's our
      // own write bouncing back through the watcher).
      final hash = _hashContent(text);
      if (_lastExportHash != null && _lastExportHash == hash) {
        _lastSeenMtimeMs = mtimeMs;
        return result;
      }

      final parsedEvents = ICalEngine.importFromIcs(
        text,
        identityId: identityId,
        createdBy: identityId,
      );
      final parsedByUid = {for (final e in parsedEvents) e.eventId: e};

      // Apply adds/updates.
      for (final incoming in parsedEvents) {
        final existing = calendar.events[incoming.eventId];
        if (existing == null) {
          calendar.events[incoming.eventId] = incoming;
          result.pulledNew++;
          continue;
        }
        if (existing.updatedAt == incoming.updatedAt &&
            _semanticEquals(existing, incoming)) {
          continue; // Nothing to do — identical content.
        }
        if (existing.updatedAt >= incoming.updatedAt) {
          // Local wins under LWW — but only a *real* conflict if content differs.
          if (_semanticEquals(existing, incoming)) continue;
          if (askOnConflict) {
            onPendingConflict(PendingConflict(
              id: _mkId(incoming.eventId, 'localIcs'),
              eventId: incoming.eventId,
              source: 'localIcs',
              localEvent: existing.toJson(),
              externalEvent: incoming.toJson(),
              detectedAtMs: DateTime.now().millisecondsSinceEpoch,
            ));
            continue; // don't apply yet
          }
          onConflict(SyncConflict(
            id: _mkId(incoming.eventId, 'localIcs'),
            eventId: incoming.eventId,
            source: 'localIcs',
            winner: 'local',
            detectedAtMs: DateTime.now().millisecondsSinceEpoch,
            title: existing.title,
            losingEvent: incoming.toJson(),
          ));
          continue;
        }
        // External wins.
        if (!_semanticEquals(existing, incoming)) {
          onConflict(SyncConflict(
            id: _mkId(incoming.eventId, 'localIcs'),
            eventId: incoming.eventId,
            source: 'localIcs',
            winner: 'external',
            detectedAtMs: DateTime.now().millisecondsSinceEpoch,
            title: incoming.title,
            losingEvent: existing.toJson(),
          ));
        }
        calendar.events[incoming.eventId] = incoming;
        result.pulledUpdated++;
      }

      // Detect removed events — anything we had referenced before that isn't
      // in the new snapshot. Only applies to events we previously imported
      // via this path (tracked via `source: localIcs` is not stored, so
      // instead we use the simpler rule: if the event only exists locally
      // AND no other provider is responsible, a missing UID from a
      // full-snapshot file means "deleted externally").
      //
      // To avoid wiping events the user created in Cleona that were never
      // in the file, we only remove events whose UID *previously* appeared
      // in this file — tracked by the eventId set we observed last time.
      // We keep that set in `_previouslySeenUids`.
      final seenNow = parsedByUid.keys.toSet();
      for (final id in _previouslySeenUids.difference(seenNow).toList()) {
        // Extra guard: only delete if the local event's updatedAt hasn't
        // changed since we last saw the file (otherwise the user edited it
        // locally and we shouldn't silently drop it).
        final local = calendar.events[id];
        if (local == null) {
          _previouslySeenUids.remove(id);
          continue;
        }
        if (local.updatedAt > _lastSeenMtimeMs) continue;
        calendar.events.remove(id);
        result.pulledDeleted++;
        _previouslySeenUids.remove(id);
      }
      _previouslySeenUids.addAll(seenNow);

      _lastSeenMtimeMs = mtimeMs;
      calendar.save();
      _log.info('Import diff: ${result.pulledNew} new, '
          '${result.pulledUpdated} updated, ${result.pulledDeleted} deleted');
    } catch (e) {
      result.errors.add('import $filePath: $e');
      _log.warn('Import failed: $e');
    }
    return result;
  }

  /// State for delete-detection — UIDs we observed on the last successful
  /// file read. Persisted via the sync state map.
  final Set<String> _previouslySeenUids = {};

  Map<String, dynamic> toJson() => {
        'lastSeenMtimeMs': _lastSeenMtimeMs,
        'previouslySeenUids': _previouslySeenUids.toList(),
        if (_lastExportHash != null) 'lastExportHash': _lastExportHash,
      };

  void fromJson(Map<String, dynamic> json) {
    _lastSeenMtimeMs = json['lastSeenMtimeMs'] as int? ?? 0;
    _previouslySeenUids
      ..clear()
      ..addAll((json['previouslySeenUids'] as List?)?.cast<String>() ?? []);
    _lastExportHash = json['lastExportHash'] as String?;
  }

  /// Two events are considered "semantically equal" when none of the
  /// user-visible fields differ. Used to suppress spurious conflicts when
  /// only bookkeeping (e.g. updatedAt) changed.
  static bool _semanticEquals(CalendarEvent a, CalendarEvent b) {
    return a.title == b.title &&
        a.description == b.description &&
        a.location == b.location &&
        a.startTime == b.startTime &&
        a.endTime == b.endTime &&
        a.allDay == b.allDay &&
        a.recurrenceRule == b.recurrenceRule &&
        a.cancelled == b.cancelled;
  }

  static String _hashContent(String s) {
    // Fast, collision-tolerant digest — purely used to skip re-imports of
    // our own writes. Not cryptographic.
    var h = 0x811c9dc5; // FNV-1a 32-bit offset basis
    for (final codeUnit in s.codeUnits) {
      h ^= codeUnit;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  static String _mkId(String eventId, String source) =>
      '$source:$eventId:${DateTime.now().millisecondsSinceEpoch}';
}

/// Counters + errors for a single export/import invocation.
class LocalIcsResult {
  int eventsExported = 0;
  int pulledNew = 0;
  int pulledUpdated = 0;
  int pulledDeleted = 0;
  final List<String> errors = [];

  bool get hasErrors => errors.isNotEmpty;
}
