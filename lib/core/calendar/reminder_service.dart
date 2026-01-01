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

  /// How often to check for reminders (default: every 30 seconds).
  Duration checkInterval;

  /// How far ahead to look for reminders.
  Duration lookAheadWindow;

  ReminderService({
    this.checkInterval = const Duration(seconds: 30),
    this.lookAheadWindow = const Duration(minutes: 5),
  });

  /// Start the reminder timer.
  void start(Map<String, CalendarManager> identityCalendars) {
    stop();
    _timer = Timer.periodic(checkInterval, (_) {
      _checkReminders(identityCalendars);
    });
    // Also check immediately
    _checkReminders(identityCalendars);
    _log.info('Reminder service started (check every ${checkInterval.inSeconds}s)');
  }

  /// Stop the reminder timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Snooze a reminder by re-scheduling it.
  void snooze(String eventId, CalendarManager calendar, int snoozeMinutes) {
    final event = calendar.events[eventId];
    if (event == null) return;

    // Remove from fired set so it can fire again
    _firedReminders.removeWhere((k) => k.startsWith('$eventId:'));
    _log.info('Snoozed reminder for $eventId by $snoozeMinutes minutes');
  }

  void _checkReminders(Map<String, CalendarManager> calendars) {
    final windowMs = lookAheadWindow.inMilliseconds;

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

    // Clean up old fired reminders (older than 24h)
    final cutoff = DateTime.now().millisecondsSinceEpoch - 24 * 60 * 60 * 1000;
    _firedReminders.removeWhere((key) {
      final parts = key.split(':');
      if (parts.length < 2) return true;
      final eventStart = int.tryParse(parts[1]) ?? 0;
      return eventStart < cutoff;
    });
  }

  void dispose() {
    stop();
    _firedReminders.clear();
  }
}
