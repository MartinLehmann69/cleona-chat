import 'package:cleona/core/service/service_types.dart';

/// RFC 5545 iCalendar (.ics) import/export engine.
///
/// Converts between Cleona's CalendarEvent model and standard iCal format.
/// Supports VCALENDAR, VEVENT, VTODO, VALARM, RRULE.
class ICalEngine {
  ICalEngine._();

  // ── Export ─────────────────────────────────────────────────────────

  /// Export a list of events as a complete .ics file string.
  static String exportToIcs(List<CalendarEvent> events, {String? calendarName}) {
    final buf = StringBuffer();
    buf.writeln('BEGIN:VCALENDAR');
    buf.writeln('VERSION:2.0');
    buf.writeln('PRODID:-//Cleona Chat//Calendar//EN');
    buf.writeln('CALSCALE:GREGORIAN');
    buf.writeln('METHOD:PUBLISH');
    if (calendarName != null) {
      buf.writeln('X-WR-CALNAME:${_escapeText(calendarName)}');
    }

    for (final event in events) {
      if (event.category == EventCategory.task) {
        _writeVtodo(buf, event);
      } else {
        _writeVevent(buf, event);
      }
    }

    buf.writeln('END:VCALENDAR');
    return buf.toString();
  }

  /// Export a single event as .ics string.
  static String exportEventToIcs(CalendarEvent event) {
    return exportToIcs([event]);
  }

  static void _writeVevent(StringBuffer buf, CalendarEvent event) {
    buf.writeln('BEGIN:VEVENT');
    buf.writeln('UID:${event.eventId}@cleona.chat');

    if (event.allDay) {
      buf.writeln('DTSTART;VALUE=DATE:${_formatDateOnly(event.startTime)}');
      buf.writeln('DTEND;VALUE=DATE:${_formatDateOnly(event.endTime)}');
    } else {
      buf.writeln('DTSTART:${_formatDateTime(event.startTime)}');
      buf.writeln('DTEND:${_formatDateTime(event.endTime)}');
    }

    buf.writeln('SUMMARY:${_escapeText(event.title)}');
    if (event.description != null && event.description!.isNotEmpty) {
      buf.writeln('DESCRIPTION:${_escapeText(event.description!)}');
    }
    if (event.location != null && event.location!.isNotEmpty) {
      buf.writeln('LOCATION:${_escapeText(event.location!)}');
    }

    buf.writeln('DTSTAMP:${_formatDateTime(event.createdAt)}');
    buf.writeln('CREATED:${_formatDateTime(event.createdAt)}');
    buf.writeln('LAST-MODIFIED:${_formatDateTime(event.updatedAt)}');

    if (event.recurrenceRule != null && event.recurrenceRule!.isNotEmpty) {
      final rrule = event.recurrenceRule!.startsWith('RRULE:')
          ? event.recurrenceRule!.substring(6)
          : event.recurrenceRule!;
      buf.writeln('RRULE:$rrule');
    }

    for (final exDate in event.recurrenceExceptions) {
      buf.writeln('EXDATE:${_formatDateTime(exDate)}');
    }

    if (event.cancelled) {
      buf.writeln('STATUS:CANCELLED');
    } else {
      buf.writeln('STATUS:CONFIRMED');
    }

    // Map category
    buf.writeln('CATEGORIES:${_categoryToIcal(event.category)}');

    // Transparency for Free/Busy
    if (event.freeBusyVisibility == FreeBusyLevel.hidden) {
      buf.writeln('TRANSP:TRANSPARENT');
    } else {
      buf.writeln('TRANSP:OPAQUE');
    }

    // Alarms
    for (final minutes in event.reminders) {
      buf.writeln('BEGIN:VALARM');
      buf.writeln('TRIGGER:-PT${minutes}M');
      buf.writeln('ACTION:DISPLAY');
      buf.writeln('DESCRIPTION:Reminder');
      buf.writeln('END:VALARM');
    }

    buf.writeln('END:VEVENT');
  }

  static void _writeVtodo(StringBuffer buf, CalendarEvent event) {
    buf.writeln('BEGIN:VTODO');
    buf.writeln('UID:${event.eventId}@cleona.chat');
    buf.writeln('DTSTAMP:${_formatDateTime(event.createdAt)}');
    buf.writeln('CREATED:${_formatDateTime(event.createdAt)}');
    buf.writeln('LAST-MODIFIED:${_formatDateTime(event.updatedAt)}');
    buf.writeln('SUMMARY:${_escapeText(event.title)}');

    if (event.description != null && event.description!.isNotEmpty) {
      buf.writeln('DESCRIPTION:${_escapeText(event.description!)}');
    }

    if (event.taskDueDate != null) {
      buf.writeln('DUE:${_formatDateTime(event.taskDueDate!)}');
    } else {
      buf.writeln('DUE:${_formatDateTime(event.endTime)}');
    }

    buf.writeln('DTSTART:${_formatDateTime(event.startTime)}');

    if (event.taskCompleted) {
      buf.writeln('STATUS:COMPLETED');
      buf.writeln('PERCENT-COMPLETE:100');
    } else {
      buf.writeln('STATUS:NEEDS-ACTION');
    }

    // Priority: iCal uses 1-9 (1=high, 9=low), Cleona uses 0-3 (3=high)
    if (event.taskPriority > 0) {
      buf.writeln('PRIORITY:${_mapPriorityToIcal(event.taskPriority)}');
    }

    for (final minutes in event.reminders) {
      buf.writeln('BEGIN:VALARM');
      buf.writeln('TRIGGER:-PT${minutes}M');
      buf.writeln('ACTION:DISPLAY');
      buf.writeln('DESCRIPTION:Reminder');
      buf.writeln('END:VALARM');
    }

    buf.writeln('END:VTODO');
  }

  // ── Import ─────────────────────────────────────────────────────────

  /// Parse an .ics file string and return CalendarEvents.
  ///
  /// [identityId] is the identity that owns the imported events.
  /// [createdBy] is the node ID of the importing user.
  static List<CalendarEvent> importFromIcs(
    String icsContent, {
    required String identityId,
    required String createdBy,
  }) {
    final events = <CalendarEvent>[];
    final lines = _unfoldLines(icsContent);

    _ICalComponent? current;
    final componentStack = <String>[];

    for (final line in lines) {
      if (line.startsWith('BEGIN:VEVENT')) {
        current = _ICalComponent();
        componentStack.add('VEVENT');
      } else if (line.startsWith('BEGIN:VTODO')) {
        current = _ICalComponent();
        componentStack.add('VTODO');
      } else if (line.startsWith('BEGIN:VALARM')) {
        componentStack.add('VALARM');
      } else if (line.startsWith('END:VALARM')) {
        if (componentStack.isNotEmpty) componentStack.removeLast();
      } else if (line.startsWith('END:VEVENT')) {
        if (current != null) {
          final event = _parseVevent(current, identityId, createdBy);
          if (event != null) events.add(event);
        }
        current = null;
        if (componentStack.isNotEmpty) componentStack.removeLast();
      } else if (line.startsWith('END:VTODO')) {
        if (current != null) {
          final event = _parseVtodo(current, identityId, createdBy);
          if (event != null) events.add(event);
        }
        current = null;
        if (componentStack.isNotEmpty) componentStack.removeLast();
      } else if (current != null) {
        if (componentStack.isNotEmpty && componentStack.last == 'VALARM') {
          // Collect alarm triggers
          if (line.startsWith('TRIGGER:')) {
            current.alarms.add(line.substring(8));
          }
        } else {
          final colonIdx = line.indexOf(':');
          if (colonIdx > 0) {
            final key = line.substring(0, colonIdx);
            final value = line.substring(colonIdx + 1);
            current.properties[key] = value;
          }
        }
      }
    }

    return events;
  }

  static CalendarEvent? _parseVevent(
      _ICalComponent comp, String identityId, String createdBy) {
    final uid = comp.get('UID') ?? _generateId();
    final summary = comp.get('SUMMARY') ?? '';
    if (summary.isEmpty) return null;

    final dtStart = comp.getDateTime('DTSTART');
    final dtEnd = comp.getDateTime('DTEND');
    if (dtStart == null) return null;

    final isAllDay = comp.isDateOnly('DTSTART');
    final duration = dtEnd != null
        ? dtEnd - dtStart
        : (isAllDay ? 24 * 60 * 60 * 1000 : 60 * 60 * 1000);

    final rrule = comp.get('RRULE');
    final exDates = <int>[];
    // Collect all EXDATE entries
    for (final entry in comp.properties.entries) {
      if (entry.key.startsWith('EXDATE')) {
        final parsed = _parseICalDateTime(entry.value);
        if (parsed != null) exDates.add(parsed);
      }
    }

    final status = comp.get('STATUS')?.toUpperCase();
    final cancelled = status == 'CANCELLED';

    final transp = comp.get('TRANSP')?.toUpperCase();
    final visibility = transp == 'TRANSPARENT'
        ? FreeBusyLevel.hidden
        : FreeBusyLevel.timeOnly;

    final category = _icalToCategory(comp.get('CATEGORIES'));

    final reminders = <int>[];
    for (final trigger in comp.alarms) {
      final minutes = _parseTriggerMinutes(trigger);
      if (minutes != null && minutes > 0) reminders.add(minutes);
    }

    final eventId = _cleanUid(uid);
    final created = comp.getDateTime('CREATED') ?? comp.getDateTime('DTSTAMP');

    return CalendarEvent(
      eventId: eventId,
      identityId: identityId,
      title: _unescapeText(summary),
      description: _unescapeTextOpt(comp.get('DESCRIPTION')),
      location: _unescapeTextOpt(comp.get('LOCATION')),
      startTime: dtStart,
      endTime: dtStart + duration,
      allDay: isAllDay,
      timeZone: comp.getTimezone('DTSTART') ?? 'UTC',
      recurrenceRule: rrule,
      recurrenceExceptions: exDates.isNotEmpty ? exDates : null,
      category: category,
      freeBusyVisibility: visibility,
      reminders: reminders.isNotEmpty ? reminders : null,
      cancelled: cancelled,
      createdBy: createdBy,
      createdAt: created,
      updatedAt: comp.getDateTime('LAST-MODIFIED') ?? created,
    );
  }

  static CalendarEvent? _parseVtodo(
      _ICalComponent comp, String identityId, String createdBy) {
    final uid = comp.get('UID') ?? _generateId();
    final summary = comp.get('SUMMARY') ?? '';
    if (summary.isEmpty) return null;

    final dtStart = comp.getDateTime('DTSTART') ??
        comp.getDateTime('DTSTAMP') ??
        DateTime.now().millisecondsSinceEpoch;
    final due = comp.getDateTime('DUE') ?? dtStart + 60 * 60 * 1000;

    final status = comp.get('STATUS')?.toUpperCase();
    final completed = status == 'COMPLETED';

    final priority = _mapPriorityFromIcal(comp.get('PRIORITY'));

    final reminders = <int>[];
    for (final trigger in comp.alarms) {
      final minutes = _parseTriggerMinutes(trigger);
      if (minutes != null && minutes > 0) reminders.add(minutes);
    }

    final eventId = _cleanUid(uid);
    final created = comp.getDateTime('CREATED') ?? comp.getDateTime('DTSTAMP');

    return CalendarEvent(
      eventId: eventId,
      identityId: identityId,
      title: _unescapeText(summary),
      description: _unescapeTextOpt(comp.get('DESCRIPTION')),
      startTime: dtStart,
      endTime: due,
      category: EventCategory.task,
      taskCompleted: completed,
      taskDueDate: due,
      taskPriority: priority,
      reminders: reminders.isNotEmpty ? reminders : null,
      createdBy: createdBy,
      createdAt: created,
      updatedAt: comp.getDateTime('LAST-MODIFIED') ?? created,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────

  /// Unfold RFC 5545 continuation lines (lines starting with space/tab).
  static List<String> _unfoldLines(String content) {
    final raw = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final result = <String>[];
    for (final line in raw.split('\n')) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (result.isNotEmpty) {
          result[result.length - 1] += line.substring(1);
        }
      } else {
        result.add(line);
      }
    }
    return result;
  }

  static String _formatDateTime(int unixMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true);
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}'
        'T${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}Z';
  }

  static String _formatDateOnly(int unixMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true);
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  /// Parse iCal datetime: 20260415T100000Z or 20260415
  static int? _parseICalDateTime(String value) {
    final cleaned = value.trim();
    if (cleaned.length >= 15) {
      // Full datetime: 20260415T100000Z
      final year = int.tryParse(cleaned.substring(0, 4)) ?? 0;
      final month = int.tryParse(cleaned.substring(4, 6)) ?? 1;
      final day = int.tryParse(cleaned.substring(6, 8)) ?? 1;
      final hour = int.tryParse(cleaned.substring(9, 11)) ?? 0;
      final minute = int.tryParse(cleaned.substring(11, 13)) ?? 0;
      final second = int.tryParse(cleaned.substring(13, 15)) ?? 0;
      final isUtc = cleaned.endsWith('Z');
      return (isUtc
              ? DateTime.utc(year, month, day, hour, minute, second)
              : DateTime(year, month, day, hour, minute, second))
          .millisecondsSinceEpoch;
    } else if (cleaned.length >= 8) {
      // Date only: 20260415
      final year = int.tryParse(cleaned.substring(0, 4)) ?? 0;
      final month = int.tryParse(cleaned.substring(4, 6)) ?? 1;
      final day = int.tryParse(cleaned.substring(6, 8)) ?? 1;
      return DateTime.utc(year, month, day).millisecondsSinceEpoch;
    }
    return null;
  }

  static String _escapeText(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\n', '\\n');
  }

  static String _unescapeText(String text) {
    return text
        .replaceAll('\\n', '\n')
        .replaceAll('\\N', '\n')
        .replaceAll('\\;', ';')
        .replaceAll('\\,', ',')
        .replaceAll('\\\\', '\\');
  }

  static String? _unescapeTextOpt(String? text) {
    if (text == null || text.isEmpty) return null;
    return _unescapeText(text);
  }

  static String _categoryToIcal(EventCategory cat) {
    switch (cat) {
      case EventCategory.appointment:
        return 'APPOINTMENT';
      case EventCategory.task:
        return 'TASK';
      case EventCategory.birthday:
        return 'BIRTHDAY';
      case EventCategory.reminder:
        return 'REMINDER';
      case EventCategory.meeting:
        return 'MEETING';
    }
  }

  static EventCategory _icalToCategory(String? categories) {
    if (categories == null) return EventCategory.appointment;
    final upper = categories.toUpperCase();
    if (upper.contains('MEETING')) return EventCategory.meeting;
    if (upper.contains('BIRTHDAY')) return EventCategory.birthday;
    if (upper.contains('REMINDER')) return EventCategory.reminder;
    if (upper.contains('TASK')) return EventCategory.task;
    return EventCategory.appointment;
  }

  /// Map Cleona priority (0-3, 3=high) to iCal (1-9, 1=high).
  static int _mapPriorityToIcal(int cleonaPriority) {
    switch (cleonaPriority) {
      case 3:
        return 1; // high
      case 2:
        return 5; // medium
      case 1:
        return 9; // low
      default:
        return 0; // undefined
    }
  }

  /// Map iCal priority (1-9, 1=high) to Cleona (0-3, 3=high).
  static int _mapPriorityFromIcal(String? value) {
    final p = int.tryParse(value ?? '') ?? 0;
    if (p == 0) return 0;
    if (p <= 3) return 3; // high
    if (p <= 6) return 2; // medium
    return 1; // low
  }

  /// Parse VALARM TRIGGER like -PT15M, -PT1H, -P1D.
  static int? _parseTriggerMinutes(String trigger) {
    final cleaned = trigger.trim();
    if (!cleaned.startsWith('-P')) return null;
    final spec = cleaned.substring(2); // Remove -P

    int total = 0;
    if (spec.startsWith('T')) {
      // Time-based: PT15M, PT1H30M
      final timePart = spec.substring(1);
      final hourMatch = RegExp(r'(\d+)H').firstMatch(timePart);
      final minuteMatch = RegExp(r'(\d+)M').firstMatch(timePart);
      if (hourMatch != null) total += int.parse(hourMatch.group(1)!) * 60;
      if (minuteMatch != null) total += int.parse(minuteMatch.group(1)!);
    } else {
      // Date-based: P1D, P1W
      final dayMatch = RegExp(r'(\d+)D').firstMatch(spec);
      final weekMatch = RegExp(r'(\d+)W').firstMatch(spec);
      if (dayMatch != null) total += int.parse(dayMatch.group(1)!) * 1440;
      if (weekMatch != null) total += int.parse(weekMatch.group(1)!) * 10080;
      // Also check for T-part after date
      final tIdx = spec.indexOf('T');
      if (tIdx > 0) {
        final timePart = spec.substring(tIdx + 1);
        final hourMatch = RegExp(r'(\d+)H').firstMatch(timePart);
        final minuteMatch = RegExp(r'(\d+)M').firstMatch(timePart);
        if (hourMatch != null) total += int.parse(hourMatch.group(1)!) * 60;
        if (minuteMatch != null) total += int.parse(minuteMatch.group(1)!);
      }
    }
    return total > 0 ? total : null;
  }

  /// Remove @domain suffix from UID.
  static String _cleanUid(String uid) {
    final atIdx = uid.indexOf('@');
    return atIdx > 0 ? uid.substring(0, atIdx) : uid;
  }

  static String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'import-$now-${now.hashCode.toRadixString(16)}';
  }
}

/// Internal helper for parsing iCal components.
class _ICalComponent {
  final Map<String, String> properties = {};
  final List<String> alarms = [];

  String? get(String key) => properties[key];

  /// Parse a datetime property, handling params like DTSTART;VALUE=DATE:20260415.
  int? getDateTime(String key) {
    // Try exact key first
    if (properties.containsKey(key)) {
      return ICalEngine._parseICalDateTime(properties[key]!);
    }
    // Try with parameters (e.g., DTSTART;VALUE=DATE or DTSTART;TZID=Europe/Berlin)
    for (final entry in properties.entries) {
      if (entry.key.startsWith('$key;') || entry.key == key) {
        return ICalEngine._parseICalDateTime(entry.value);
      }
    }
    return null;
  }

  /// Check if a datetime property is date-only (VALUE=DATE).
  bool isDateOnly(String key) {
    for (final k in properties.keys) {
      if (k.startsWith('$key;') && k.contains('VALUE=DATE')) {
        // Ensure it's VALUE=DATE and not VALUE=DATE-TIME
        return k.contains('VALUE=DATE') && !k.contains('VALUE=DATE-TIME');
      }
    }
    // Also check by value format (8 chars = date only)
    final val = properties[key];
    if (val != null && val.length == 8 && !val.contains('T')) return true;
    return false;
  }

  /// Extract timezone ID from a datetime property.
  String? getTimezone(String key) {
    for (final k in properties.keys) {
      if (k.startsWith('$key;') && k.contains('TZID=')) {
        final tzStart = k.indexOf('TZID=') + 5;
        final tzEnd = k.indexOf(';', tzStart);
        return tzEnd > 0 ? k.substring(tzStart, tzEnd) : k.substring(tzStart);
      }
    }
    return null;
  }
}
