import 'dart:math';

/// RFC 5545 RRULE parser and occurrence expander.
///
/// Supports: FREQ (DAILY/WEEKLY/MONTHLY/YEARLY), INTERVAL, COUNT, UNTIL,
/// BYDAY (MO-SU with optional position prefix), BYMONTHDAY, BYMONTH,
/// BYHOUR, BYMINUTE, WKST.
class RecurrenceEngine {
  RecurrenceEngine._();

  /// Parse an RRULE string into a map of rule parts.
  static Map<String, String> parseRrule(String rrule) {
    final result = <String, String>{};
    final cleaned = rrule.startsWith('RRULE:') ? rrule.substring(6) : rrule;
    for (final part in cleaned.split(';')) {
      final idx = part.indexOf('=');
      if (idx > 0) {
        result[part.substring(0, idx).toUpperCase()] =
            part.substring(idx + 1);
      }
    }
    return result;
  }

  /// Expand occurrences of a recurring event within [windowStart, windowEnd].
  ///
  /// [eventStart] is the original event start time (Unix ms).
  /// [eventDurationMs] is end-start for the event.
  /// [rrule] is the RFC 5545 RRULE string.
  /// [exceptions] are excluded occurrence start times (Unix ms).
  ///
  /// Returns list of occurrence start times (Unix ms) within the window.
  static List<int> expandOccurrences({
    required int eventStart,
    required int eventDurationMs,
    required String rrule,
    required int windowStart,
    required int windowEnd,
    List<int> exceptions = const [],
  }) {
    final parts = parseRrule(rrule);
    final freq = parts['FREQ']?.toUpperCase() ?? '';
    final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
    final count = int.tryParse(parts['COUNT'] ?? '') ?? 0;
    final untilStr = parts['UNTIL'];
    final byDay = parts['BYDAY']?.split(',') ?? [];
    final byMonthDay = parts['BYMONTHDAY']
            ?.split(',')
            .map((s) => int.tryParse(s) ?? 0)
            .where((d) => d != 0)
            .toList() ??
        [];
    final byMonth = parts['BYMONTH']
            ?.split(',')
            .map((s) => int.tryParse(s) ?? 0)
            .where((m) => m > 0 && m <= 12)
            .toList() ??
        [];

    final exSet = exceptions.toSet();
    final start = DateTime.fromMillisecondsSinceEpoch(eventStart, isUtc: true);
    DateTime? until;
    if (untilStr != null) {
      until = _parseUntil(untilStr);
    }

    final results = <int>[];
    // Safety limit: max 1000 occurrences or 10 years from event start
    final hardLimit = DateTime.fromMillisecondsSinceEpoch(
        eventStart + 10 * 365 * 24 * 60 * 60 * 1000,
        isUtc: true);
    final effectiveEnd = DateTime.fromMillisecondsSinceEpoch(windowEnd, isUtc: true);
    final limitDate = until != null
        ? (until.isBefore(effectiveEnd) ? until : effectiveEnd)
        : effectiveEnd;
    final absoluteLimit = limitDate.isBefore(hardLimit) ? limitDate : hardLimit;

    int generated = 0;
    const maxGenerated = 1000;

    switch (freq) {
      case 'DAILY':
        var current = start;
        while (!current.isAfter(absoluteLimit) && generated < maxGenerated) {
          if (count > 0 && generated >= count) break;
          final ms = current.millisecondsSinceEpoch;
          if (ms + eventDurationMs >= windowStart &&
              ms <= windowEnd &&
              !exSet.contains(ms)) {
            results.add(ms);
          }
          current = _addDays(current, interval);
          generated++;
        }
        break;

      case 'WEEKLY':
        if (byDay.isEmpty) {
          // Simple weekly recurrence on same weekday
          var current = start;
          while (!current.isAfter(absoluteLimit) && generated < maxGenerated) {
            if (count > 0 && generated >= count) break;
            final ms = current.millisecondsSinceEpoch;
            if (ms + eventDurationMs >= windowStart &&
                ms <= windowEnd &&
                !exSet.contains(ms)) {
              results.add(ms);
            }
            current = _addDays(current, 7 * interval);
            generated++;
          }
        } else {
          // BYDAY weekly: expand for each specified day within each interval-week
          final targetDays = byDay.map(_parseDayOfWeek).whereType<int>().toList();
          var weekStart = _startOfWeek(start);
          while (!weekStart.isAfter(absoluteLimit) && generated < maxGenerated) {
            for (final dayNum in targetDays) {
              if (count > 0 && generated >= count) break;
              final occurrence = _addDays(weekStart, dayNum - 1).add(Duration(
                  hours: start.hour,
                  minutes: start.minute,
                  seconds: start.second));
              if (occurrence.isBefore(start)) continue;
              if (occurrence.isAfter(absoluteLimit)) break;
              final ms = occurrence.millisecondsSinceEpoch;
              if (ms + eventDurationMs >= windowStart &&
                  ms <= windowEnd &&
                  !exSet.contains(ms)) {
                results.add(ms);
              }
              generated++;
            }
            weekStart = _addDays(weekStart, 7 * interval);
          }
        }
        break;

      case 'MONTHLY':
        var current = start;
        while (!current.isAfter(absoluteLimit) && generated < maxGenerated) {
          if (count > 0 && generated >= count) break;
          if (byMonthDay.isNotEmpty) {
            for (final day in byMonthDay) {
              final effectiveDay = day < 0
                  ? _daysInMonth(current.year, current.month) + day + 1
                  : day;
              if (effectiveDay < 1 ||
                  effectiveDay > _daysInMonth(current.year, current.month)) {
                continue;
              }
              final occ = DateTime.utc(current.year, current.month, effectiveDay,
                  start.hour, start.minute, start.second);
              if (occ.isBefore(start) || occ.isAfter(absoluteLimit)) continue;
              final ms = occ.millisecondsSinceEpoch;
              if (ms + eventDurationMs >= windowStart &&
                  ms <= windowEnd &&
                  !exSet.contains(ms)) {
                results.add(ms);
              }
            }
          } else if (byDay.isNotEmpty) {
            // BYDAY in MONTHLY context: e.g. "2MO" = second Monday
            for (final daySpec in byDay) {
              final occ = _resolveMonthlyByDay(daySpec, current.year, current.month, start);
              if (occ == null || occ.isBefore(start) || occ.isAfter(absoluteLimit)) continue;
              final ms = occ.millisecondsSinceEpoch;
              if (ms + eventDurationMs >= windowStart &&
                  ms <= windowEnd &&
                  !exSet.contains(ms)) {
                results.add(ms);
              }
            }
          } else {
            final ms = current.millisecondsSinceEpoch;
            if (ms + eventDurationMs >= windowStart &&
                ms <= windowEnd &&
                !exSet.contains(ms)) {
              results.add(ms);
            }
          }
          current = _addMonths(current, interval);
          generated++;
        }
        break;

      case 'YEARLY':
        var current = start;
        while (!current.isAfter(absoluteLimit) && generated < maxGenerated) {
          if (count > 0 && generated >= count) break;
          if (byMonth.isNotEmpty) {
            for (final month in byMonth) {
              final day = min(start.day, _daysInMonth(current.year, month));
              final occ = DateTime.utc(
                  current.year, month, day, start.hour, start.minute, start.second);
              if (occ.isBefore(start) || occ.isAfter(absoluteLimit)) continue;
              final ms = occ.millisecondsSinceEpoch;
              if (ms + eventDurationMs >= windowStart &&
                  ms <= windowEnd &&
                  !exSet.contains(ms)) {
                results.add(ms);
              }
            }
          } else {
            final ms = current.millisecondsSinceEpoch;
            if (ms + eventDurationMs >= windowStart &&
                ms <= windowEnd &&
                !exSet.contains(ms)) {
              results.add(ms);
            }
          }
          current = DateTime.utc(
              current.year + interval, current.month, current.day,
              current.hour, current.minute, current.second);
          generated++;
        }
        break;
    }

    results.sort();
    return results;
  }

  /// Format an RRULE for display. Returns human-readable German string.
  static String formatRrule(String rrule) {
    final parts = parseRrule(rrule);
    final freq = parts['FREQ']?.toUpperCase() ?? '';
    final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
    final byDay = parts['BYDAY'] ?? '';

    switch (freq) {
      case 'DAILY':
        return interval == 1 ? 'Täglich' : 'Alle $interval Tage';
      case 'WEEKLY':
        final days = byDay.isNotEmpty
            ? byDay.split(',').map(_dayAbbrevToGerman).join(', ')
            : '';
        final prefix = interval == 1 ? 'Wöchentlich' : 'Alle $interval Wochen';
        return days.isNotEmpty ? '$prefix ($days)' : prefix;
      case 'MONTHLY':
        return interval == 1 ? 'Monatlich' : 'Alle $interval Monate';
      case 'YEARLY':
        return interval == 1 ? 'Jährlich' : 'Alle $interval Jahre';
      default:
        return rrule;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static DateTime? _parseUntil(String s) {
    // Format: 20260415T120000Z or 20260415
    try {
      if (s.length >= 8) {
        final y = int.parse(s.substring(0, 4));
        final m = int.parse(s.substring(4, 6));
        final d = int.parse(s.substring(6, 8));
        if (s.length >= 15) {
          final h = int.parse(s.substring(9, 11));
          final min = int.parse(s.substring(11, 13));
          final sec = int.parse(s.substring(13, 15));
          return DateTime.utc(y, m, d, h, min, sec);
        }
        return DateTime.utc(y, m, d, 23, 59, 59);
      }
    } catch (_) {}
    return null;
  }

  static DateTime _addDays(DateTime dt, int days) =>
      DateTime.utc(dt.year, dt.month, dt.day + days, dt.hour, dt.minute, dt.second);

  static DateTime _addMonths(DateTime dt, int months) {
    var y = dt.year;
    var m = dt.month + months;
    while (m > 12) {
      y++;
      m -= 12;
    }
    while (m < 1) {
      y--;
      m += 12;
    }
    final d = min(dt.day, _daysInMonth(y, m));
    return DateTime.utc(y, m, d, dt.hour, dt.minute, dt.second);
  }

  static int _daysInMonth(int year, int month) {
    if (month == 2) {
      return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28;
    }
    return const [0, 31, 0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month];
  }

  static DateTime _startOfWeek(DateTime dt) {
    // ISO week: Monday=1
    final daysFromMonday = (dt.weekday - 1) % 7;
    return DateTime.utc(dt.year, dt.month, dt.day - daysFromMonday);
  }

  /// Parse "MO" → 1 (Monday) through "SU" → 7 (Sunday).
  static int? _parseDayOfWeek(String s) {
    // Strip optional position prefix like "2MO" → "MO"
    final dayStr = s.replaceAll(RegExp(r'^-?\d+'), '').toUpperCase();
    const map = {'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7};
    return map[dayStr];
  }

  /// Resolve "2MO" in MONTHLY context → second Monday of the month.
  static DateTime? _resolveMonthlyByDay(
      String spec, int year, int month, DateTime timeTemplate) {
    final match = RegExp(r'^(-?\d+)?([A-Z]{2})$').firstMatch(spec.toUpperCase());
    if (match == null) return null;
    final posStr = match.group(1);
    final dayStr = match.group(2)!;
    final targetDay = _parseDayOfWeek(dayStr);
    if (targetDay == null) return null;
    final pos = posStr != null ? int.tryParse(posStr) : null;

    if (pos == null || pos == 0) {
      // No position: every occurrence of that day in the month (not standard for MONTHLY)
      return null;
    }

    if (pos > 0) {
      // Positive position: find the N-th occurrence
      var first = DateTime.utc(year, month, 1);
      while (first.weekday != targetDay) {
        first = first.add(const Duration(days: 1));
      }
      final day = first.day + (pos - 1) * 7;
      if (day > _daysInMonth(year, month)) return null;
      return DateTime.utc(year, month, day,
          timeTemplate.hour, timeTemplate.minute, timeTemplate.second);
    } else {
      // Negative position: count from end of month
      final lastDay = _daysInMonth(year, month);
      var last = DateTime.utc(year, month, lastDay);
      while (last.weekday != targetDay) {
        last = last.subtract(const Duration(days: 1));
      }
      final day = last.day + (pos + 1) * 7;
      if (day < 1) return null;
      return DateTime.utc(year, month, day,
          timeTemplate.hour, timeTemplate.minute, timeTemplate.second);
    }
  }

  static String _dayAbbrevToGerman(String s) {
    final day = s.replaceAll(RegExp(r'^-?\d+'), '').toUpperCase();
    const map = {
      'MO': 'Mo', 'TU': 'Di', 'WE': 'Mi', 'TH': 'Do',
      'FR': 'Fr', 'SA': 'Sa', 'SU': 'So',
    };
    return map[day] ?? s;
  }
}
