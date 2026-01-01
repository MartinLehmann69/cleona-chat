/// How long before its event a reminder fires, as an i18n key and the
/// number that goes into its `{count}` — `count` is `null` where the key
/// takes none ("at the time").
///
/// ONE rule for the two places that say it: the event editor, where the
/// user chooses the reminder, and the system notification the reminder
/// posts (§22.8 "A reminder shows the event's title and how long until it
/// starts"). The keys exist in all 34 locales.
({String key, int? count}) reminderOffsetText(int minutesBefore) {
  if (minutesBefore <= 0) return (key: 'reminder_at_time', count: null);
  if (minutesBefore < 60) {
    return (key: 'reminder_minutes_before', count: minutesBefore);
  }
  if (minutesBefore < 1440) {
    return (key: 'reminder_hours_before', count: minutesBefore ~/ 60);
  }
  if (minutesBefore < 10080) {
    return (key: 'reminder_days_before', count: minutesBefore ~/ 1440);
  }
  return (key: 'reminder_weeks_before', count: minutesBefore ~/ 10080);
}

/// How a log line names the event of a reminder: the beginning of its
/// identifier. Never its title — the title is what the notification shows,
/// and that "is not written to a log" (§22.8).
String reminderLogName(String eventId) =>
    eventId.length > 8 ? eventId.substring(0, 8) : eventId;
