import 'dart:async';

import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/reminder_service.dart';
import 'package:cleona/core/calendar/reminder_text.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/service/notification_content.dart';

/// One reminder handed to the system's own schedule ahead of time (iOS,
/// §18.1.6): shown at [fireAtMs] even while the app is suspended. [title]
/// and [body] are already what §22.8 lets the notification show — reduced
/// when "notification without content" is on.
class ScheduledReminder {
  final String id;
  final String title;
  final String body;
  final int fireAtMs;

  const ScheduledReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAtMs,
  });

  Map<String, Object> toArguments() =>
      {'id': id, 'title': title, 'body': body, 'fireAtMs': fireAtMs};
}

/// The calendar's own clocks, wired ONCE for every host that runs services:
/// the daemon (`service_daemon.dart`) and the app process that is its own
/// node (Android, iOS, macOS without daemon — `main.dart` `_initInProcess`).
/// Until S422 only the daemon started them; the app process had neither a
/// reminder nor a sync cadence (S422-RCA-ERINNERUNGEN-MOBIL E-1,
/// S422-RCA-BAU-KALENDER-HANDY K-1).
///
/// Two clocks, both owned here:
/// * the [ReminderService] (§18.1.6): one for all identities, local, no
///   network. A due reminder goes to the identity's service, which posts it
///   on the platform's way (§22.8: the event's title and how long until it
///   starts).
/// * each identity's `CalendarSyncService` (§18.2): the adaptive cadence,
///   3 min while the calendar is open in the foreground, else 15 min. It
///   only talks to a provider the user configured for that identity
///   (opt-in, §18.2); without one its tick sends nothing.
///
/// On iOS, whose system suspends a backgrounded app, every upcoming reminder
/// is additionally scheduled with the system in advance ([scheduleAhead])
/// and withdrawn when its event changes or is cancelled (§18.1.6, D-125 (2)):
/// the whole set is handed over again after every change of a calendar, when
/// an identity comes or goes, and when the app leaves the foreground. A
/// reminder the running app fires itself is withdrawn from the schedule
/// first ([withdrawAhead]) and is not scheduled again — one notification,
/// not two.
///
/// The local CalDAV server (§18.2, loopback listener) is not part of this:
/// it stays with the daemon, see S422-RCA-BAU-KALENDER-HANDY K-3.
class CalendarWiring {
  /// The system keeps at most 64 scheduled local notifications per app and
  /// drops the rest (Apple, https://developer.apple.com/forums/thread/811171);
  /// §18.1.6 "the system keeps at most the 64 soonest of them".
  static const int maxScheduledAhead = 64;

  /// The services of this host, read on every use — identities added or
  /// removed at runtime are followed without a restart.
  final Map<String, CleonaService> Function() services;

  /// Process log line (no event title ever goes here, §22.8).
  final void Function(String line) report;

  final ReminderService reminders;

  /// Hands the full set of upcoming reminders to the system's schedule,
  /// replacing the set handed before (iOS; `null` elsewhere).
  final Future<void> Function(List<ScheduledReminder> set)? scheduleAhead;

  /// Withdraws one scheduled reminder by its [ScheduledReminder.id].
  final Future<void> Function(String id)? withdrawAhead;

  /// How far ahead reminders are looked for when scheduling. §18.1.6 asks
  /// for every upcoming reminder, bounded only by the system's 64; the
  /// window only bounds the expansion of recurring events. One year, so an
  /// app left unopened for weeks still has its reminders scheduled (S422).
  final Duration aheadHorizon;

  /// Calendar writes come in bursts (an external sync writes event by
  /// event); the set is handed over once the burst is over.
  final Duration aheadSettle;

  bool _started = false;
  bool _calendarOpen = false;
  bool _appResumed = true;
  Timer? _aheadTimer;
  final Set<CalendarManager> _watched = {};

  CalendarWiring({
    required this.services,
    required this.report,
    ReminderService? reminders,
    this.scheduleAhead,
    this.withdrawAhead,
    this.aheadHorizon = const Duration(days: 365),
    this.aheadSettle = const Duration(seconds: 1),
  }) : reminders = reminders ?? ReminderService();

  /// The identifier of one reminder in the system's schedule — one per
  /// event occurrence and lead time.
  static String scheduledId(ReminderInfo r) =>
      'reminder:${r.eventId}:${r.eventStart}:${r.minutesBefore}';

  bool get isStarted => _started;

  /// Whether the sync of every identity runs at the foreground cadence:
  /// a calendar is on screen AND the app is in the foreground. The daemon
  /// has no app life cycle of its own; there only the calendar counts.
  bool get foreground => _calendarOpen && _appResumed;

  void start() {
    if (_started) return;
    _started = true;
    reminders.onReminderDue = _reminderDue;
    reminders.start(_calendars(), calendarGetter: _calendars);
    final all = services();
    for (final service in all.values) {
      _syncStart(service);
      _watch(service.calendarManager);
    }
    report('Calendar wiring started: reminders + sync for '
        '${all.length} identities');
    _scheduleAheadNow();
  }

  /// An identity joined after [start]: its sync joins the cadence. Its
  /// reminders follow by themselves (the calendars are read every cycle).
  void identityAdded(CleonaService service) {
    if (!_started) return;
    _syncStart(service);
    _watch(service.calendarManager);
    _scheduleAheadSoon();
  }

  /// An identity leaves: its sync clock stops with it, and its reminders
  /// leave the system's schedule (the set is handed over without them).
  void identityRemoved(CleonaService service) {
    service.calendarSyncService.stop();
    _unwatch(service.calendarManager);
    if (_started) _scheduleAheadNow();
  }

  /// The calendar is shown or closed (app process; the daemon gets the
  /// same signal over IPC `calendar_sync_set_foreground`).
  void calendarOpen(bool open) {
    _calendarOpen = open;
    _applyForeground();
  }

  /// The app went to the foreground or left it (app process only).
  void appResumed(bool resumed) {
    final leaving = _appResumed && !resumed;
    _appResumed = resumed;
    _applyForeground();
    // The last moment before the system may suspend the app: the schedule
    // gets the current set (words and the "without content" setting as
    // they are now).
    if (leaving && _started) _scheduleAheadNow();
  }

  /// Stops every clock this wiring started. Call before the services are
  /// dropped from the map, so their sync clocks are still reachable. The
  /// system's schedule is left as it is: it is what reminds while the app
  /// does not run.
  void dispose() {
    _aheadTimer?.cancel();
    _aheadTimer = null;
    for (final calendar in _watched.toList()) {
      _unwatch(calendar);
    }
    reminders.dispose();
    for (final service in services().values) {
      service.calendarSyncService.stop();
    }
    if (_started) report('Calendar wiring stopped');
    _started = false;
  }

  /// The set of reminders the system's schedule should hold now: the
  /// [maxScheduledAhead] soonest within [aheadHorizon] over every identity,
  /// without those the running app has already shown.
  List<ScheduledReminder> upcomingAhead() {
    final all = <(ReminderInfo, CleonaService)>[];
    for (final service in services().values) {
      for (final r in service.calendarManager
          .getUpcomingReminders(aheadHorizon.inMilliseconds)) {
        if (reminders.hasFired(r)) continue;
        all.add((r, service));
      }
    }
    all.sort((a, b) => a.$1.reminderTime.compareTo(b.$1.reminderTime));
    return [
      for (final (r, service) in all.take(maxScheduledAhead))
        () {
          final shown = notificationShown(
              kind: NotificationKind.reminder,
              title: r.title,
              body: _leadText(service, r.minutesBefore),
              withoutContent: service.notificationWithoutContent,
              words: service.notificationWord);
          return ScheduledReminder(
              id: scheduledId(r),
              title: shown.title,
              body: shown.body,
              fireAtMs: r.reminderTime);
        }(),
    ];
  }

  void _watch(CalendarManager calendar) {
    if (scheduleAhead == null) return;
    calendar.onChanged = _scheduleAheadSoon;
    _watched.add(calendar);
  }

  void _unwatch(CalendarManager calendar) {
    if (!_watched.remove(calendar)) return;
    if (calendar.onChanged == _scheduleAheadSoon) calendar.onChanged = null;
  }

  void _scheduleAheadSoon() {
    if (scheduleAhead == null || !_started) return;
    _aheadTimer?.cancel();
    _aheadTimer = Timer(aheadSettle, _scheduleAheadNow);
  }

  void _scheduleAheadNow() {
    final hand = scheduleAhead;
    if (hand == null) return;
    _aheadTimer?.cancel();
    _aheadTimer = null;
    final set = upcomingAhead();
    unawaited(hand(set).catchError((Object e) {
      // The type only: the platform's error may quote a title.
      report('Scheduling reminders ahead failed: ${e.runtimeType}');
    }));
    report('Reminders scheduled ahead: ${set.length}');
  }

  static String _leadText(CleonaService service, int minutesBefore) {
    final (:key, :count) = reminderOffsetText(minutesBefore);
    final word = service.notificationWord(key);
    return count == null ? word : word.replaceAll('{count}', '$count');
  }

  void _syncStart(CleonaService service) {
    final sync = service.calendarSyncService;
    sync.setForeground(foreground);
    sync.start();
  }

  void _applyForeground() {
    if (!_started) return;
    final fg = foreground;
    for (final service in services().values) {
      service.calendarSyncService.setForeground(fg);
    }
  }

  Map<String, CalendarManager> _calendars() => {
        for (final e in services().entries) e.key: e.value.calendarManager,
      };

  void _reminderDue(String identityId, ReminderInfo reminder) {
    // The event's identifier, not its title: the title is what the
    // notification shows, and that is "not written to a log" (§22.8).
    report('Reminder due: event ${reminderLogName(reminder.eventId)} '
        '(identity=$identityId, ${reminder.minutesBefore}min before event)');
    final service = services()[identityId];
    if (service == null) return;

    // 0. iOS: the app runs and shows it itself — out of the system's
    //    schedule first, so it does not come a second time. `hasFired`
    //    keeps it out of every later set.
    final withdraw = withdrawAhead;
    if (withdraw != null) {
      unawaited(withdraw(scheduledId(reminder)).catchError((Object e) {
        report('Withdrawing a scheduled reminder failed: ${e.runtimeType}');
      }));
    }

    // 1. The event to a connected GUI (IPC `calendar_reminder`).
    service.onCalendarReminderDue
        ?.call(reminder.eventId, reminder.title, reminder.minutesBefore);

    // 2. System notification, sound and vibration (§18.1.6), in the words
    //    the host set on the service (`notificationWords`: the daemon's
    //    tray language, the app's chosen language). §22.8: "A reminder
    //    shows the event's title and how long until it starts."
    service.notifyReminderDue(
        reminder.title,
        _leadText(service, reminder.minutesBefore),
        'reminder:${reminder.eventId}:${reminder.eventStart}');
  }
}
