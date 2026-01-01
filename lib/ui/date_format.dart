import 'package:cleona/core/i18n/app_locale.dart';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _hhmm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

String _weekday(AppLocale locale, int weekday) =>
    locale.get('weekday_$weekday');

String _weekdayShort(AppLocale locale, int weekday) =>
    locale.get('weekday_short_$weekday');

String _month(AppLocale locale, int month) =>
    locale.get('month_$month');

/// Label for a date separator in the chat message list.
/// Today → "Heute", Yesterday → "Gestern", this week → weekday name,
/// this year → "9. Juli", older → "9. Juli 2025".
String formatDateSeparator(DateTime dt, AppLocale locale) {
  final now = DateTime.now();
  if (_isSameDay(dt, now)) return locale.get('date_today');

  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDay(dt, yesterday)) return locale.get('date_yesterday');

  final daysAgo = DateTime(now.year, now.month, now.day)
      .difference(DateTime(dt.year, dt.month, dt.day))
      .inDays;
  if (daysAgo >= 2 && daysAgo <= 6) return _weekday(locale, dt.weekday);

  final month = _month(locale, dt.month);
  if (dt.year == now.year) return '${dt.day}. $month';
  return '${dt.day}. $month ${dt.year}';
}

/// Compact timestamp for the conversation list.
/// Today → "14:30", Yesterday → "Gestern", 2-6 days → "Mo",
/// this year → "9.7.", older → "9.7.25".
String formatConversationTime(DateTime dt, AppLocale locale) {
  final now = DateTime.now();
  if (_isSameDay(dt, now)) return _hhmm(dt);

  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDay(dt, yesterday)) return locale.get('date_yesterday');

  final daysAgo = DateTime(now.year, now.month, now.day)
      .difference(DateTime(dt.year, dt.month, dt.day))
      .inDays;
  if (daysAgo >= 2 && daysAgo <= 6) return _weekdayShort(locale, dt.weekday);

  if (dt.year == now.year) return '${dt.day}.${dt.month}.';
  return '${dt.day}.${dt.month}.${dt.year % 100}';
}

/// Whether two messages need a date separator between them.
bool needsDateSeparator(DateTime? prev, DateTime current) =>
    prev == null || !_isSameDay(prev, current);
