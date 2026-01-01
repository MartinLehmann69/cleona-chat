import 'dart:async';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/network/clogger.dart';

/// Daemon-driven reminder service.
///
/// Periodically checks for upcoming reminders across all identity calendars
/// and fires notifications. Works even when the GUI is not running.
class ReminderService {
  final CLogger _log = CLogger.get('reminder');
  Timer? _timer;

  /// Callback fired when a reminder is due.
  /// Parameters: identityId, ReminderInfo.
  void Function(String identityId, ReminderInfo reminder)? onReminderDue;

  /// Set of fired reminder keys to prevent duplicates.
  /// Key format: "$eventId:$occurrenceStart:$minutesBefore"
  final Set<String> _firedReminders = {};

  /// Snoozed reminders: key → snooze-until (Unix milliseconds).
  /// While snoozed the key stays in [_firedReminders] so the normal
  /// duplicate guard holds; once the snooze window expires the key is
  /// removed from both maps and the reminder re-fires on the next cycle.
  final Map<String, int> _snoozeUntil = {};

  /// How often to check for reminders (default: every 30 seconds).
  Duration checkInterval;

  /// How far ahead to look for reminders.
  Duration lookAheadWindow;

  ReminderService({
    this.checkInterval = const Duration(seconds: 30),
    this.lookAheadWindow = const Duration(minutes: 5),
  });

  /// Start the reminder timer.
  ///
  /// [identityCalendars] can be a live [Map] reference (mutations by the
  /// caller are visible on subsequent cycles) or a factory/getter passed
  /// via [calendarGetter].  When [calendarGetter] is provided it is called
  /// on **every** check-cycle so that identities added at runtime are
  /// automatically picked up.
  void start(
    Map<String, CalendarManager> identityCalendars, {
    Map<String, CalendarManager> Function()? calendarGetter,
  }) {
    stop();
    _timer = Timer.periodic(checkInterval, (_) {
      _checkReminders(calendarGetter?.call() ?? identityCalendars);
    });
    // Also check immediately
    _checkReminders(calendarGetter?.call() ?? identityCalendars);
    _log.info('Reminder service started (check every ${checkInterval.inSeconds}s)');
  }

  /// Stop the reminder timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Snooze a reminder: suppress re-firing until [snoozeMinutes] from now.
  ///
  /// The reminder keys stay in [_firedReminders] during the snooze window
  /// (preventing immediate re-fire). Once the snooze expires,
  /// [_checkReminders] removes the keys and the reminder fires again on
  /// the next qualifying cycle.
  void snooze(String eventId, CalendarManager calendar, int snoozeMinutes) {
    final event = calendar.events[eventId];
    if (event == null) return;

    final untilMs = DateTime.now()
        .add(Duration(minutes: snoozeMinutes))
        .millisecondsSinceEpoch;

    // Mark every occurrence/offset combination for this event as snoozed.
    // Keys stay in _firedReminders so the duplicate guard keeps them quiet.
    for (final key in _firedReminders.where((k) => k.startsWith('$eventId:'))) {
      _snoozeUntil[key] = untilMs;
    }
    _log.info('Snoozed reminder for $eventId by $snoozeMinutes minutes '
        '(until ${DateTime.fromMillisecondsSinceEpoch(untilMs).toIso8601String()})');
  }

  void _checkReminders(Map<String, CalendarManager> calendars) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final windowMs = lookAheadWindow.inMilliseconds;

    // --- Expire snoozed reminders whose window has elapsed ----------------
    final expiredSnoozes = <String>[];
    for (final entry in _snoozeUntil.entries) {
      if (nowMs >= entry.value) {
        expiredSnoozes.add(entry.key);
      }
    }
    for (final key in expiredSnoozes) {
      _snoozeUntil.remove(key);
      _firedReminders.remove(key); // allow re-fire on next qualifying cycle
      _log.info('Snooze expired, re-arming reminder: $key');
    }

    // --- Check each identity calendar for upcoming reminders --------------
    for (final entry in calendars.entries) {
      final identityId = entry.key;
      final calendar = entry.value;

      final reminders = calendar.getUpcomingReminders(windowMs);
      for (final reminder in reminders) {
        final key =
            '${reminder.eventId}:${reminder.eventStart}:${reminder.minutesBefore}';
        if (_firedReminders.contains(key)) continue;

        _firedReminders.add(key);
        _log.info('Firing reminder: ${reminder.title} '
            '(${reminder.minutesBefore}min before event)');
        onReminderDue?.call(identityId, reminder);
      }
    }

    // --- Clean up old fired reminders (older than 24h) --------------------
    final cutoff = nowMs - 24 * 60 * 60 * 1000;
    _firedReminders.removeWhere((key) {
      final parts = key.split(':');
      if (parts.length < 2) return true;
      final eventStart = int.tryParse(parts[1]) ?? 0;
      return eventStart < cutoff;
    });
    // Also purge stale snooze entries (safety net for orphaned keys)
    _snoozeUntil.removeWhere((key, until) => until < cutoff);
  }

  void dispose() {
    stop();
    _firedReminders.clear();
    _snoozeUntil.clear();
  }
}
