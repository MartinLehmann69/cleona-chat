import 'dart:math';
import 'package:cleona/core/calendar/recurrence_engine.dart';
import 'package:cleona/core/storage/message_store.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart';

/// CalendarManager — local calendar CRUD, multi-identity merge, persistence.
///
/// Each identity has its own CalendarManager instance (same pattern as
/// PollManager). Events are stored as encrypted JSON, keyed by eventId.
///
/// The comparison used to name ContactManager. That was wrong twice over: the
/// class was removed in S290, and it wrote PLAINTEXT — it was never an example
/// of encrypted persistence. PollManager is — today via [MessageStore].
///
/// S366: the store is the encrypted SQLite store per identity
/// (areas `calendar_events` and `calendar_settings`), no longer
/// `calendar_events.json` / `calendar_settings.json`.
///
/// WHY. `calendar_events` grows without bound — no cap, no deadline —
/// and was rewritten in full on EVERY change. A single
/// RSVP answer cost the entire stock of events. That is the same
/// pattern that led to the quadratic curve for messages.
/// Therefore the methods that change exactly ONE event write
/// one row via [persistEvent]; [save] stays for the paths that really
/// set the whole state (full sync with an external calendar,
/// birthday sync) — there deletion also occurs, which a
/// single write would not see.
class CalendarManager {
  final String profileDir;
  final String identityId;
  final MessageStore? _store;
  final CLogger _log;

  /// All events owned by this identity, keyed by eventId.
  final Map<String, CalendarEvent> events = {};

  /// Free/Busy settings for this identity.
  FreeBusySettings freeBusySettings = FreeBusySettings();

  bool _loaded = false;

  CalendarManager({
    required this.profileDir,
    required this.identityId,
    this._store,
  })  : // profileDir is a constructor parameter (per identity) -> directly usable.
        _log = CLogger.get('calendar[${shortHex(identityId)}]',
            profileDir: profileDir);

  // ── Persistence ─��──────────────────────────────────────────────────────

  /// Area of the events in the store.
  static const String kEventsArea = 'calendar_events';

  /// Area of the free/busy settings. A single entry — the
  /// settings are one object, not a collection.
  static const String kSettingsArea = 'calendar_settings';
  static const String _settingsKey = 'settings';

  void load() {
    final store = _store;
    if (store == null) { _loaded = true; return; } // Proxy mode
    try {
      // S366: from the store (area `calendar_events`) instead of from
      // `calendar_events.json`.
      for (final entry in store.loadArea(kEventsArea).entries) {
        try {
          events[entry.key] = CalendarEvent.fromJson(entry.value);
        } catch (e) {
          _log.warn('Skipping corrupt calendar event ${entry.key}: $e');
        }
      }
      _log.info('Loaded ${events.length} calendar events');
      _loaded = true;
    } catch (e) {
      // Do NOT mark as loaded: otherwise empty counts as the stock, and the
      // latch in [save] would let a full overwrite through.
      _log.warn('Failed to load calendar events: $e');
    }

    try {
      final json = store.loadArea(kSettingsArea)[_settingsKey];
      if (json != null) {
        freeBusySettings = FreeBusySettings.fromJson(json);
      }
    } catch (e) {
      _log.warn('Failed to load calendar settings: $e');
    }
  }

  /// Writes the ENTIRE stock of events.
  ///
  /// Only for the paths that really set the whole state: the
  /// full sync with an external calendar and the
  /// birthday sync also remove events, and a single write does not
  /// see a deletion. Whoever changes exactly ONE event calls
  /// [persistEvent].
  void save() {
    final store = _store;
    if (store == null) return; // Proxy mode
    // DATA-LOSS LATCH (S366): it now asks the STORE, no longer
    // just the loaded flag.
    //
    // Until now only `!_loaded && events.isEmpty` stood here. After the
    // switchover `calendar_events.json` is never written again; a
    // latch that checks a file would be silently dead. This one checks the
    // place where the events really lie now — and fails
    // closed if the store cannot be read: not
    // saving is always right when we do not know what is on the
    // disk.
    if (!_loaded && events.isEmpty) {
      var present = false;
      try {
        present = store.countArea(kEventsArea) > 0;
      } catch (e) {
        _log.warn('REFUSED to save calendar — store unreadable: $e');
        return;
      }
      if (present) {
        _log.warn('REFUSED to save empty calendar — load failed but the '
            'store still holds events. Would cause data loss!');
        return;
      }
    }
    try {
      store.replaceArea(kEventsArea, {
        for (final e in events.entries) e.key: e.value.toJson(),
      });
    } catch (e) {
      _log.warn('Failed to save calendar events: $e');
    }
  }

  /// Writes EXACTLY ONE event — or removes it if it is no longer
  /// in memory.
  ///
  /// §21.4.1: `calendar_events.json` was rewritten in full on every change
  /// — 12 triggers, no cap, no deadline. The model is
  /// `PollManager.persistPoll`.
  void persistEvent(String eventId) {
    final store = _store;
    if (store == null) return; // Proxy mode
    final event = events[eventId];
    try {
      if (event == null) {
        store.removeEntry(kEventsArea, eventId);
      } else {
        store.putEntry(kEventsArea, eventId, event.toJson());
      }
    } catch (e) {
      _log.warn('Failed to persist calendar event $eventId: $e');
    }
  }

  void saveSettings() {
    final store = _store;
    if (store == null) return; // Proxy mode
    try {
      // One object, one entry — `replaceArea` thus keeps the area
      // at exactly one row and clears out old stock along the way.
      store.replaceArea(
          kSettingsArea, {_settingsKey: freeBusySettings.toJson()});
    } catch (e) {
      _log.warn('Failed to save calendar settings: $e');
    }
  }

  // ── CRUD ────────────────────────���──────────────────────────────────────

  /// Create a new calendar event. Returns the eventId.
  String createEvent(CalendarEvent event) {
    events[event.eventId] = event;
    persistEvent(event.eventId);
    _log.info('Created event ${event.eventId}: ${event.title}');
    return event.eventId;
  }

  /// Update an existing event. Returns true if found and updated.
  bool updateEvent(String eventId, {
    String? title,
    String? description,
    String? location,
    int? startTime,
    int? endTime,
    bool? allDay,
    String? timeZone,
    String? recurrenceRule,
    bool? hasCall,
    bool? cancelled,
    List<int>? reminders,
    FreeBusyLevel? freeBusyVisibility,
    bool? taskCompleted,
    int? taskPriority,
    List<String>? attendeeNodeIds,
  }) {
    final event = events[eventId];
    if (event == null) return false;

    if (title != null) event.title = title;
    if (description != null) event.description = description;
    if (location != null) event.location = location;
    if (startTime != null) event.startTime = startTime;
    if (endTime != null) event.endTime = endTime;
    if (allDay != null) event.allDay = allDay;
    if (timeZone != null) event.timeZone = timeZone;
    if (recurrenceRule != null) event.recurrenceRule = recurrenceRule;
    if (hasCall != null) event.hasCall = hasCall;
    if (cancelled != null) event.cancelled = cancelled;
    if (reminders != null) event.reminders = reminders;
    if (freeBusyVisibility != null) event.freeBusyVisibility = freeBusyVisibility;
    if (taskCompleted != null) event.taskCompleted = taskCompleted;
    if (taskPriority != null) event.taskPriority = taskPriority;
    if (attendeeNodeIds != null) event.attendeeNodeIds = attendeeNodeIds;
    event.updatedAt = DateTime.now().millisecondsSinceEpoch;

    persistEvent(eventId);
    _log.info('Updated event $eventId');
    return true;
  }

  /// Delete an event. Returns true if it existed.
  bool deleteEvent(String eventId) {
    final removed = events.remove(eventId);
    if (removed != null) {
      persistEvent(eventId);
      _log.info('Deleted event $eventId');
      return true;
    }
    return false;
  }

  /// Record an RSVP response for a group event.
  void setRsvp(String eventId, String responderNodeIdHex, RsvpStatus status) {
    final event = events[eventId];
    if (event == null) return;
    event.rsvpResponses[responderNodeIdHex] = status;
    event.updatedAt = DateTime.now().millisecondsSinceEpoch;
    // An answer changes exactly one event. Until S366 it wrote the
    // entire stock — the main reason for the switchover.
    persistEvent(eventId);
  }

  // ── Queries ────────────────────────────────────────────────────────────

  /// Get all events (including expanded recurrences) within a time window.
  List<CalendarOccurrence> getEventsInRange(int windowStart, int windowEnd) {
    final results = <CalendarOccurrence>[];

    for (final event in events.values) {
      if (event.cancelled) continue;

      if (event.recurrenceRule != null && event.recurrenceRule!.isNotEmpty) {
        // Expand recurring event
        final duration = event.endTime - event.startTime;
        final occurrences = RecurrenceEngine.expandOccurrences(
          eventStart: event.startTime,
          eventDurationMs: duration,
          rrule: event.recurrenceRule!,
          windowStart: windowStart,
          windowEnd: windowEnd,
          exceptions: event.recurrenceExceptions,
        );
        for (final occStart in occurrences) {
          results.add(CalendarOccurrence(
            event: event,
            occurrenceStart: occStart,
            occurrenceEnd: occStart + duration,
          ));
        }
      } else {
        // Non-recurring: check if it overlaps the window
        if (event.endTime >= windowStart && event.startTime <= windowEnd) {
          results.add(CalendarOccurrence(
            event: event,
            occurrenceStart: event.startTime,
            occurrenceEnd: event.endTime,
          ));
        }
      }
    }

    results.sort((a, b) => a.occurrenceStart.compareTo(b.occurrenceStart));
    return results;
  }

  /// Get all tasks, sorted by due date then priority.
  List<CalendarEvent> getTasks({bool includeCompleted = false}) {
    return events.values
        .where((e) =>
            e.category == EventCategory.task &&
            !e.cancelled &&
            (includeCompleted || !e.taskCompleted))
        .toList()
      ..sort((a, b) {
        // Uncompleted first, then by due date, then by priority descending
        if (a.taskCompleted != b.taskCompleted) {
          return a.taskCompleted ? 1 : -1;
        }
        final aDue = a.taskDueDate ?? a.endTime;
        final bDue = b.taskDueDate ?? b.endTime;
        if (aDue != bDue) return aDue.compareTo(bDue);
        return b.taskPriority.compareTo(a.taskPriority);
      });
  }

  /// Get all birthday events, sorted by next occurrence.
  List<CalendarEvent> getBirthdays() {
    return events.values
        .where((e) => e.category == EventCategory.birthday && !e.cancelled)
        .toList()
      ..sort((a, b) => _nextBirthday(a).compareTo(_nextBirthday(b)));
  }

  int _nextBirthday(CalendarEvent e) {
    final now = DateTime.now();
    final start = DateTime.fromMillisecondsSinceEpoch(e.startTime);
    var next = DateTime(now.year, start.month, start.day);
    if (next.isBefore(now)) next = DateTime(now.year + 1, start.month, start.day);
    return next.millisecondsSinceEpoch;
  }

  // ── Free/Busy ───��──────────────────────────────────────────────────────

  /// Generate Free/Busy blocks for a querier within [queryStart, queryEnd].
  ///
  /// [querierNodeIdHex] determines the visibility level.
  /// [allIdentityManagers] enables cross-identity merge (§23.4).
  List<FreeBusyBlockResult> generateFreeBusyResponse({
    required int queryStart,
    required int queryEnd,
    required String querierNodeIdHex,
    List<CalendarManager>? allIdentityManagers,
  }) {
    final managers = allIdentityManagers ?? [this];
    final blocks = <FreeBusyBlockResult>[];

    for (final mgr in managers) {
      final occurrences = mgr.getEventsInRange(queryStart, queryEnd);
      for (final occ in occurrences) {
        final event = occ.event;
        // Determine visibility for this querier
        final level = event.visibilityOverrides[querierNodeIdHex] ??
            mgr.freeBusySettings.contactOverrides[querierNodeIdHex] ??
            event.freeBusyVisibility;

        if (level == FreeBusyLevel.hidden) continue;

        blocks.add(FreeBusyBlockResult(
          start: occ.occurrenceStart,
          end: occ.occurrenceEnd,
          level: level,
          title: level == FreeBusyLevel.full ? event.title : null,
          location: level == FreeBusyLevel.full ? event.location : null,
        ));
      }
    }

    blocks.sort((a, b) => a.start.compareTo(b.start));
    return blocks;
  }

  // ── Birthday Auto-Generation ──────────────────────────────────────────

  /// Create birthday events from contacts that have birthday info.
  /// [contacts] is a map of nodeIdHex → {displayName, birthdayYear, birthdayMonth, birthdayDay}.
  void syncBirthdaysFromContacts(Map<String, Map<String, dynamic>> contacts) {
    // S366: this path creates and updates, it NEVER DELETES — so
    // it does not write the whole state either, but exactly the
    // events touched. It runs at every start and at every
    // birthday change on a contact; with `save()` a
    // single changed date of birth would have rewritten the complete stock
    // of events.
    final touched = <String>{};
    // Find existing birthday events by contactId
    final existing = <String, String>{}; // contactId → eventId
    for (final e in events.values) {
      if (e.category == EventCategory.birthday && e.birthdayContactId != null) {
        existing[e.birthdayContactId!] = e.eventId;
      }
    }

    for (final entry in contacts.entries) {
      final nodeIdHex = entry.key;
      final info = entry.value;
      final month = info['birthdayMonth'] as int?;
      final day = info['birthdayDay'] as int?;
      if (month == null || day == null) continue;

      final name = info['displayName'] as String? ?? 'Contact';
      final year = info['birthdayYear'] as int?;

      if (existing.containsKey(nodeIdHex)) {
        // Update existing birthday event
        final event = events[existing[nodeIdHex]!];
        if (event != null) {
          event.title = '$name Geburtstag';
          event.birthdayYear = year;
          event.updatedAt = DateTime.now().millisecondsSinceEpoch;
          touched.add(event.eventId);
        }
      } else {
        // Create new birthday event
        final now = DateTime.now();
        var eventDate = DateTime.utc(now.year, month, day);
        if (eventDate.isBefore(now)) {
          eventDate = DateTime.utc(now.year + 1, month, day);
        }
        final eventId = _generateUuid();
        events[eventId] = CalendarEvent(
          eventId: eventId,
          identityId: identityId,
          title: '$name Geburtstag',
          startTime: eventDate.millisecondsSinceEpoch,
          endTime: eventDate.add(const Duration(days: 1)).millisecondsSinceEpoch,
          allDay: true,
          category: EventCategory.birthday,
          birthdayContactId: nodeIdHex,
          birthdayYear: year,
          recurrenceRule: 'FREQ=YEARLY',
          freeBusyVisibility: FreeBusyLevel.hidden,
          reminders: [1440], // 1 day before
          createdBy: identityId,
        );
        touched.add(eventId);
      }
    }
    for (final id in touched) {
      persistEvent(id);
    }
  }

  // ── Upcoming Reminders ─────────────────────────────────────────────────

  /// Get all reminders that should fire within the next [windowMs] milliseconds.
  List<ReminderInfo> getUpcomingReminders(int windowMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowEnd = now + windowMs;
    final results = <ReminderInfo>[];

    final occurrences = getEventsInRange(now, windowEnd + 24 * 60 * 60 * 1000);
    for (final occ in occurrences) {
      for (final minutesBefore in occ.event.reminders) {
        final reminderTime = occ.occurrenceStart - minutesBefore * 60 * 1000;
        if (reminderTime >= now && reminderTime <= windowEnd) {
          results.add(ReminderInfo(
            eventId: occ.event.eventId,
            title: occ.event.title,
            reminderTime: reminderTime,
            eventStart: occ.occurrenceStart,
            minutesBefore: minutesBefore,
          ));
        }
      }
    }

    results.sort((a, b) => a.reminderTime.compareTo(b.reminderTime));
    return results;
  }

  static String _generateUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// A single occurrence of a (possibly recurring) event within a time window.
class CalendarOccurrence {
  final CalendarEvent event;
  final int occurrenceStart; // Unix ms
  final int occurrenceEnd;   // Unix ms

  CalendarOccurrence({
    required this.event,
    required this.occurrenceStart,
    required this.occurrenceEnd,
  });

  Map<String, dynamic> toJson() => {
        ...event.toJson(),
        'occurrenceStart': occurrenceStart,
        'occurrenceEnd': occurrenceEnd,
      };
}

/// A Free/Busy block for query responses.
class FreeBusyBlockResult {
  final int start;
  final int end;
  final FreeBusyLevel level;
  final String? title;
  final String? location;

  FreeBusyBlockResult({
    required this.start,
    required this.end,
    required this.level,
    this.title,
    this.location,
  });

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'level': level.index,
        if (title != null) 'title': title,
        if (location != null) 'location': location,
      };
}

/// Information about an upcoming reminder.
class ReminderInfo {
  final String eventId;
  final String title;
  final int reminderTime;  // Unix ms — when to fire
  final int eventStart;    // Unix ms — when event starts
  final int minutesBefore;

  ReminderInfo({
    required this.eventId,
    required this.title,
    required this.reminderTime,
    required this.eventStart,
    required this.minutesBefore,
  });

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'title': title,
        'reminderTime': reminderTime,
        'eventStart': eventStart,
        'minutesBefore': minutesBefore,
      };
}
