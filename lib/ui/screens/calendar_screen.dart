import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/ical_engine.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/ui/components/app_bar_scaffold.dart';
import 'package:cleona/ui/screens/calendar_sync_screen.dart';
import 'package:cleona/ui/screens/event_editor_screen.dart';

/// Calendar main screen with 4 views: Day, Week, Month, Year.
/// Accessible via calendar icon in home screen AppBar.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

enum CalendarView { day, week, month, year, tasks }

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarView _currentView = CalendarView.month;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _setSyncForeground(true);
  }

  @override
  void dispose() {
    _setSyncForeground(false);
    super.dispose();
  }

  /// Signal the daemon whether the calendar is currently being viewed,
  /// so it can adapt the external-sync polling cadence (§23.8 P2P
  /// substitute for FCM push).
  void _setSyncForeground(bool foreground) {
    final appState = context.read<CleonaAppState?>();
    final svc = appState?.service;
    if (svc is IpcClient) {
      // Fire-and-forget — the daemon replies to keep the IPC pipeline happy
      // but the UI doesn't need the response.
      svc.setCalendarSyncForeground(foreground);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final locale = AppLocale.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final service = appState.service;
    if (service == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Collect events from the active identity's calendar
    final allOccurrences = <CalendarOccurrence>[];
    final windowStart = _windowStart.millisecondsSinceEpoch;
    final windowEnd = _windowEnd.millisecondsSinceEpoch;
    allOccurrences.addAll(service.calendarManager.getEventsInRange(windowStart, windowEnd));

    return AppBarScaffold(
      title: _appBarTitle(locale),
      subtitle: _appBarSubtitle(locale),
      opaqueBody: true,
      leading: const BackButton(),
      actions: [
        // View switcher
        PopupMenuButton<CalendarView>(
          icon: Icon(_viewIcon),
          onSelected: (view) => setState(() => _currentView = view),
          itemBuilder: (_) => [
            PopupMenuItem(value: CalendarView.day, child: Text(locale.get('calendar_day'))),
            PopupMenuItem(value: CalendarView.week, child: Text(locale.get('calendar_week'))),
            PopupMenuItem(value: CalendarView.month, child: Text(locale.get('calendar_month'))),
            PopupMenuItem(value: CalendarView.year, child: Text(locale.get('calendar_year'))),
            PopupMenuItem(value: CalendarView.tasks, child: Text(locale.get('calendar_tasks'))),
          ],
        ),
        // More actions: import, export, print, sync
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            switch (action) {
              case 'import':
                _importIcs(context, service);
              case 'export':
                _exportIcs(context, service);
              case 'print':
                _printCalendar(context, service, allOccurrences);
              case 'sync':
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CalendarSyncScreen(service: service),
                  ),
                );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'import', child: Row(children: [
              const Icon(Icons.file_upload, size: 20), const SizedBox(width: 8),
              Text(locale.get('calendar_import')),
            ])),
            PopupMenuItem(value: 'export', child: Row(children: [
              const Icon(Icons.file_download, size: 20), const SizedBox(width: 8),
              Text(locale.get('calendar_export')),
            ])),
            PopupMenuItem(value: 'print', child: Row(children: [
              const Icon(Icons.print, size: 20), const SizedBox(width: 8),
              Text(locale.get('calendar_print')),
            ])),
            PopupMenuItem(value: 'sync', child: Row(children: [
              const Icon(Icons.event_repeat, size: 20), const SizedBox(width: 8),
              Text(locale.get('calendar_sync_title')),
            ])),
          ],
        ),
        // Today button
        IconButton(
          icon: const Icon(Icons.today),
          onPressed: () => setState(() => _selectedDate = DateTime.now()),
        ),
      ],
      body: Column(
        children: [
          // Navigation header (date prev/next chevrons)
          _buildNavigationHeader(locale, colorScheme),
          // Calendar view
          Expanded(
            child: switch (_currentView) {
              CalendarView.day => _DayView(
                  date: _selectedDate,
                  occurrences: allOccurrences,
                  colorScheme: colorScheme,
                  onEventTap: _openEventDetail,
                ),
              CalendarView.week => _WeekView(
                  date: _selectedDate,
                  occurrences: allOccurrences,
                  colorScheme: colorScheme,
                  onEventTap: _openEventDetail,
                  onDayTap: (d) => setState(() {
                    _selectedDate = d;
                    _currentView = CalendarView.day;
                  }),
                ),
              CalendarView.month => _MonthView(
                  date: _selectedDate,
                  occurrences: allOccurrences,
                  colorScheme: colorScheme,
                  onDayTap: (d) => setState(() {
                    _selectedDate = d;
                    _currentView = CalendarView.day;
                  }),
                ),
              CalendarView.year => _YearView(
                  date: _selectedDate,
                  occurrences: allOccurrences,
                  colorScheme: colorScheme,
                  onMonthTap: (d) => setState(() {
                    _selectedDate = d;
                    _currentView = CalendarView.month;
                  }),
                ),
              CalendarView.tasks => _TasksView(
                  service: service,
                  colorScheme: colorScheme,
                  locale: locale,
                  onTaskTap: _openTaskDetail,
                  onTaskToggle: (task) {
                    service.updateCalendarEvent(
                      task.eventId,
                      taskCompleted: !task.taskCompleted,
                    );
                    setState(() {});
                  },
                ),
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNewEvent(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  IconData get _viewIcon => switch (_currentView) {
        CalendarView.day => Icons.view_day,
        CalendarView.week => Icons.view_week,
        CalendarView.month => Icons.calendar_view_month,
        CalendarView.year => Icons.calendar_today,
        CalendarView.tasks => Icons.checklist,
      };

  /// Dynamic AppBar title: month+year for day/week/month, year for year view,
  /// empty string for tasks (subtitle carries the meaning there).
  String _appBarTitle(AppLocale locale) {
    switch (_currentView) {
      case CalendarView.day:
      case CalendarView.week:
      case CalendarView.month:
        return '${_monthName(_selectedDate.month, locale)} ${_selectedDate.year}';
      case CalendarView.year:
        return '${_selectedDate.year}';
      case CalendarView.tasks:
        return locale.get('calendar');
    }
  }

  /// Subtitle is the current view name, localized.
  String _appBarSubtitle(AppLocale locale) {
    return switch (_currentView) {
      CalendarView.day => locale.get('calendar_day'),
      CalendarView.week => locale.get('calendar_week'),
      CalendarView.month => locale.get('calendar_month'),
      CalendarView.year => locale.get('calendar_year'),
      CalendarView.tasks => locale.get('calendar_tasks'),
    };
  }

  DateTime get _windowStart {
    switch (_currentView) {
      case CalendarView.day:
        return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      case CalendarView.week:
        final weekday = _selectedDate.weekday;
        return DateTime(_selectedDate.year, _selectedDate.month,
            _selectedDate.day - (weekday - 1));
      case CalendarView.month:
        return DateTime(_selectedDate.year, _selectedDate.month, 1);
      case CalendarView.year:
        return DateTime(_selectedDate.year, 1, 1);
      case CalendarView.tasks:
        // Tasks view is date-independent — read everything the CalendarManager has.
        return DateTime(_selectedDate.year - 1);
    }
  }

  DateTime get _windowEnd {
    switch (_currentView) {
      case CalendarView.day:
        return DateTime(_selectedDate.year, _selectedDate.month,
            _selectedDate.day + 1);
      case CalendarView.week:
        final weekday = _selectedDate.weekday;
        return DateTime(_selectedDate.year, _selectedDate.month,
            _selectedDate.day + (8 - weekday));
      case CalendarView.month:
        return DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
      case CalendarView.year:
        return DateTime(_selectedDate.year + 1, 1, 1);
      case CalendarView.tasks:
        return DateTime(_selectedDate.year + 5);
    }
  }

  Widget _buildNavigationHeader(AppLocale locale, ColorScheme colorScheme) {
    // Tasks view has no date navigation — just a plain title bar.
    if (_currentView == CalendarView.tasks) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        child: Text(
          locale.get('calendar_tasks'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      );
    }

    final title = switch (_currentView) {
      CalendarView.day => _formatDayTitle(_selectedDate, locale),
      CalendarView.week => _formatWeekTitle(_selectedDate, locale),
      CalendarView.month => _formatMonthTitle(_selectedDate, locale),
      CalendarView.year => '${_selectedDate.year}',
      CalendarView.tasks => '', // handled above
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _navigateBack()),
          ),
          Text(title, style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          )),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _navigateForward()),
          ),
        ],
      ),
    );
  }

  void _navigateBack() {
    setState(() {
      switch (_currentView) {
        case CalendarView.day:
          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
        case CalendarView.week:
          _selectedDate = _selectedDate.subtract(const Duration(days: 7));
        case CalendarView.month:
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
        case CalendarView.year:
          _selectedDate = DateTime(_selectedDate.year - 1, _selectedDate.month, 1);
        case CalendarView.tasks:
          break; // no temporal navigation
      }
    });
  }

  void _navigateForward() {
    setState(() {
      switch (_currentView) {
        case CalendarView.day:
          _selectedDate = _selectedDate.add(const Duration(days: 1));
        case CalendarView.week:
          _selectedDate = _selectedDate.add(const Duration(days: 7));
        case CalendarView.month:
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
        case CalendarView.year:
          _selectedDate = DateTime(_selectedDate.year + 1, _selectedDate.month, 1);
        case CalendarView.tasks:
          break; // no temporal navigation
      }
    });
  }

  /// Open the event editor for a bare CalendarEvent (used by the tasks view,
  /// which hands over CalendarEvent rather than an occurrence).
  void _openTaskDetail(CalendarEvent task) {
    if (!mounted) return;
    final appState = context.read<CleonaAppState>();
    final locale = AppLocale.read(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: locale),
        ],
        child: EventEditorScreen(event: task, isNew: false),
      ),
    )).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openEventDetail(CalendarOccurrence occurrence) {
    if (!mounted) return;
    final appState = context.read<CleonaAppState>();
    final locale = AppLocale.read(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: locale),
        ],
        child: EventEditorScreen(event: occurrence.event, isNew: false),
      ),
    )).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _createNewEvent(BuildContext context) {
    final appState = context.read<CleonaAppState>();
    final service = appState.service;
    if (service == null) return;

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, now.hour + 1);
    final identityId = service.nodeIdHex;
    final event = CalendarEvent(
      eventId: _generateUuid(),
      identityId: identityId,
      title: '',
      startTime: start.millisecondsSinceEpoch,
      endTime: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      createdBy: identityId,
    );

    final locale = AppLocale.read(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: locale),
        ],
        child: EventEditorScreen(event: event, isNew: true),
      ),
    )).then((_) {
      if (mounted) setState(() {});
    });
  }

  static String _generateUuid() {
    final rng = DateTime.now().millisecondsSinceEpoch;
    return rng.toRadixString(16).padLeft(32, '0');
  }

  String _formatDayTitle(DateTime d, AppLocale locale) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return '${weekdays[d.weekday - 1]}, ${d.day}. ${_monthName(d.month, locale)} ${d.year}';
  }

  String _formatWeekTitle(DateTime d, AppLocale locale) {
    final weekStart = d.subtract(Duration(days: d.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    return '${weekStart.day}. – ${weekEnd.day}. ${_monthName(weekEnd.month, locale)} ${weekEnd.year}';
  }

  String _formatMonthTitle(DateTime d, AppLocale locale) =>
      '${_monthName(d.month, locale)} ${d.year}';

  String _monthName(int month, AppLocale locale) {
    const names = ['', 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
                   'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    return names[month];
  }

  // ── iCal Import ─────────────────────────────────────────────────────

  Future<void> _importIcs(BuildContext context, ICleonaService service) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    try {
      final content = File(path).readAsStringSync();
      final events = ICalEngine.importFromIcs(
        content,
        identityId: service.nodeIdHex,
        createdBy: service.nodeIdHex,
      );

      if (events.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Keine Termine in der Datei gefunden')),
          );
        }
        return;
      }

      int imported = 0;
      for (final event in events) {
        await service.createCalendarEvent(event);
        imported++;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$imported Termine importiert')),
        );
        setState(() {});
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import fehlgeschlagen: $e')),
        );
      }
    }
  }

  // ── iCal Export ─────────────────────────────────────────────────────

  Future<void> _exportIcs(BuildContext context, ICleonaService service) async {
    final events = service.calendarManager.events.values
        .where((e) => !e.cancelled)
        .toList();

    if (events.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Termine zum Exportieren')),
        );
      }
      return;
    }

    final icsContent = ICalEngine.exportToIcs(events, calendarName: 'Cleona Calendar');

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Kalender exportieren',
      fileName: 'cleona_calendar_${DateTime.now().toString().substring(0, 10)}.ics',
      type: FileType.custom,
      allowedExtensions: ['ics'],
    );

    if (savePath == null) return;

    try {
      File(savePath).writeAsStringSync(icsContent);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${events.length} Termine exportiert')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $e')),
        );
      }
    }
  }

  // ── PDF Print ───────────────────────────────────────────────────────

  Future<void> _printCalendar(
    BuildContext context,
    ICleonaService service,
    List<CalendarOccurrence> occurrences,
  ) async {
    final locale = AppLocale.read(context);
    // Tasks view is not paginated by date — skip PDF print and show a hint.
    if (_currentView == CalendarView.tasks) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('calendar_tasks_no_print'))),
      );
      return;
    }
    final isLandscape = _currentView == CalendarView.week || _currentView == CalendarView.month;
    final doc = pw.Document();

    doc.addPage(pw.MultiPage(
      pageFormat: isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Cleona Calendar', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(_formatViewTitle(locale), style: const pw.TextStyle(fontSize: 14)),
          ]),
          pw.SizedBox(height: 4),
          pw.Divider(),
        ],
      ),
      footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Exported ${DateTime.now().toString().substring(0, 16)}', style: const pw.TextStyle(fontSize: 8)),
        pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
      ]),
      build: (ctx) => switch (_currentView) {
        CalendarView.day => _buildPdfDay(occurrences),
        CalendarView.week => _buildPdfWeek(occurrences),
        CalendarView.month => _buildPdfMonth(occurrences),
        CalendarView.year => _buildPdfYear(occurrences),
        CalendarView.tasks => const <pw.Widget>[], // guarded above
      },
    ));

    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  String _formatViewTitle(AppLocale locale) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    final d = _selectedDate;
    return switch (_currentView) {
      CalendarView.day => '${d.day}. ${months[d.month - 1]} ${d.year}',
      CalendarView.week => () {
        final ws = d.subtract(Duration(days: d.weekday - 1));
        final we = ws.add(const Duration(days: 6));
        return '${ws.day}.${ws.month}. – ${we.day}.${we.month}.${we.year}';
      }(),
      CalendarView.month => '${months[d.month - 1]} ${d.year}',
      CalendarView.year => '${d.year}',
      CalendarView.tasks => locale.get('calendar_tasks'),
    };
  }

  List<pw.Widget> _buildPdfDay(List<CalendarOccurrence> occurrences) {
    final dayStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final dayOccs = occurrences.where((o) {
      final s = DateTime.fromMillisecondsSinceEpoch(o.occurrenceStart);
      return !s.isBefore(dayStart) && s.isBefore(dayEnd);
    }).toList();
    final widgets = <pw.Widget>[];
    final allDay = dayOccs.where((o) => o.event.allDay).toList();
    if (allDay.isNotEmpty) {
      widgets.add(pw.Container(padding: const pw.EdgeInsets.all(4), color: PdfColors.grey200,
        child: pw.Text('All-Day', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))));
      for (final occ in allDay) {
        widgets.add(pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Text(occ.event.title, style: const pw.TextStyle(fontSize: 10))));
      }
      widgets.add(pw.SizedBox(height: 8));
    }
    for (var hour = 0; hour < 24; hour++) {
      final hStart = dayStart.add(Duration(hours: hour)).millisecondsSinceEpoch;
      final hEnd = dayStart.add(Duration(hours: hour + 1)).millisecondsSinceEpoch;
      final hOccs = dayOccs.where((o) => !o.event.allDay && o.occurrenceStart < hEnd && o.occurrenceEnd > hStart).toList();
      widgets.add(pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: 40, child: pw.Text('${hour.toString().padLeft(2, '0')}:00',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
        pw.Expanded(child: pw.Container(
          constraints: const pw.BoxConstraints(minHeight: 18),
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3, color: PdfColors.grey300))),
          child: hOccs.isEmpty ? pw.SizedBox() : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: hOccs.map((o) {
              final s = DateTime.fromMillisecondsSinceEpoch(o.occurrenceStart);
              final e = DateTime.fromMillisecondsSinceEpoch(o.occurrenceEnd);
              return pw.Container(margin: const pw.EdgeInsets.only(bottom: 1),
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1), color: PdfColors.blue50,
                child: pw.Text('${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')} – '
                  '${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}  ${o.event.title}'
                  '${o.event.location != null ? '  (${o.event.location})' : ''}', style: const pw.TextStyle(fontSize: 8)));
            }).toList()),
        )),
      ]));
    }
    return widgets;
  }

  List<pw.Widget> _buildPdfWeek(List<CalendarOccurrence> occurrences) {
    final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
    const dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final rows = <pw.TableRow>[];
    rows.add(pw.TableRow(children: dayNames.asMap().entries.map((e) {
      final day = weekStart.add(Duration(days: e.key));
      return pw.Container(padding: const pw.EdgeInsets.all(4), color: PdfColors.grey200,
        child: pw.Text('${e.value} ${day.day}.${day.month}.', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)));
    }).toList()));
    final dayColumns = <List<CalendarOccurrence>>[];
    for (var i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      final ds = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
      final de = ds + 24 * 60 * 60 * 1000;
      dayColumns.add(occurrences.where((o) => o.occurrenceStart < de && o.occurrenceEnd > ds).toList());
    }
    final maxEvt = dayColumns.fold<int>(0, (m, d) => d.length > m ? d.length : m);
    for (var row = 0; row < (maxEvt > 0 ? maxEvt : 1); row++) {
      rows.add(pw.TableRow(children: dayColumns.map((dc) {
        if (row >= dc.length) {
          return pw.Container(constraints: const pw.BoxConstraints(minHeight: 14),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.2, color: PdfColors.grey300))));
        }
        final o = dc[row];
        final s = DateTime.fromMillisecondsSinceEpoch(o.occurrenceStart);
        final t = o.event.allDay ? '●' : '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}';
        return pw.Container(padding: const pw.EdgeInsets.all(2), constraints: const pw.BoxConstraints(minHeight: 14),
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.2, color: PdfColors.grey300))),
          child: pw.Text('$t ${o.event.title}', style: const pw.TextStyle(fontSize: 7), maxLines: 2));
      }).toList()));
    }
    return [pw.Table(border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
      columnWidths: {for (var i = 0; i < 7; i++) i: const pw.FlexColumnWidth()}, children: rows)];
  }

  List<pw.Widget> _buildPdfMonth(List<CalendarOccurrence> occurrences) {
    final year = _selectedDate.year, month = _selectedDate.month;
    final firstDay = DateTime(year, month, 1);
    final dim = DateTime(year, month + 1, 0).day;
    final off = (firstDay.weekday - 1) % 7;
    const dn = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final rows = <pw.TableRow>[pw.TableRow(children: dn.map((d) => pw.Container(padding: const pw.EdgeInsets.all(4),
      color: PdfColors.grey200, child: pw.Center(child: pw.Text(d, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))))).toList())];
    for (var w = 0; w < 6; w++) {
      final cells = <pw.Widget>[]; var has = false;
      for (var c = 0; c < 7; c++) {
        final di = w * 7 + c - off + 1;
        if (di < 1 || di > dim) { cells.add(pw.Container(constraints: const pw.BoxConstraints(minHeight: 50))); continue; }
        has = true;
        final ds = DateTime(year, month, di).millisecondsSinceEpoch, de = ds + 86400000;
        final do_ = occurrences.where((o) => o.occurrenceStart < de && o.occurrenceEnd > ds).toList();
        cells.add(pw.Container(padding: const pw.EdgeInsets.all(2), constraints: const pw.BoxConstraints(minHeight: 50),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('$di', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ...do_.take(4).map((o) { final s = DateTime.fromMillisecondsSinceEpoch(o.occurrenceStart);
              return pw.Text('${o.event.allDay ? '' : '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')} '}${o.event.title}',
                style: const pw.TextStyle(fontSize: 6), maxLines: 1); }),
            if (do_.length > 4) pw.Text('+${do_.length - 4}', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey500)),
          ])));
      }
      if (has) rows.add(pw.TableRow(children: cells));
    }
    return [pw.Table(border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
      columnWidths: {for (var i = 0; i < 7; i++) i: const pw.FlexColumnWidth()}, children: rows)];
  }

  List<pw.Widget> _buildPdfYear(List<CalendarOccurrence> occurrences) {
    final year = _selectedDate.year;
    const mn = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
    final rows = <pw.TableRow>[];
    for (var r = 0; r < 4; r++) {
      rows.add(pw.TableRow(children: List.generate(3, (c) {
        final m = r * 3 + c + 1;
        return pw.Container(padding: const pw.EdgeInsets.all(6), child: _buildPdfMiniMonth(year, m, mn[m - 1], occurrences));
      })));
    }
    return [pw.Table(columnWidths: {for (var i = 0; i < 3; i++) i: const pw.FlexColumnWidth()}, children: rows)];
  }

  pw.Widget _buildPdfMiniMonth(int year, int month, String name, List<CalendarOccurrence> occs) {
    final fd = DateTime(year, month, 1), dim = DateTime(year, month + 1, 0).day, off = (fd.weekday - 1) % 7;
    final dwe = <int>{}; for (final o in occs) { final d = DateTime.fromMillisecondsSinceEpoch(o.occurrenceStart); if (d.year == year && d.month == month) dwe.add(d.day); }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Row(children: ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'].map((d) =>
        pw.SizedBox(width: 18, child: pw.Center(child: pw.Text(d, style: pw.TextStyle(fontSize: 6, color: PdfColors.grey500))))).toList()),
      ...List.generate(6, (w) => pw.Row(children: List.generate(7, (c) {
        final di = w * 7 + c - off + 1;
        if (di < 1 || di > dim) return pw.SizedBox(width: 18, height: 12);
        return pw.SizedBox(width: 18, height: 12, child: pw.Center(child: pw.Text('$di',
          style: pw.TextStyle(fontSize: 7, fontWeight: dwe.contains(di) ? pw.FontWeight.bold : null))));
      }))),
    ]);
  }
}

// ── Day View ─────────────────────────────────────────────────────────────

class _DayView extends StatelessWidget {
  final DateTime date;
  final List<CalendarOccurrence> occurrences;
  final ColorScheme colorScheme;
  final void Function(CalendarOccurrence) onEventTap;

  const _DayView({
    required this.date,
    required this.occurrences,
    required this.colorScheme,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    final dayStart = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    final dayEnd = dayStart + 24 * 60 * 60 * 1000;
    final dayOccs = occurrences
        .where((o) => o.occurrenceEnd > dayStart && o.occurrenceStart < dayEnd)
        .toList();

    // All-day events at the top
    final allDay = dayOccs.where((o) => o.event.allDay).toList();
    final timed = dayOccs.where((o) => !o.event.allDay).toList();

    return ListView(
      children: [
        // All-day events
        if (allDay.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 4,
              children: allDay.map((o) => _AllDayChip(
                occurrence: o,
                colorScheme: colorScheme,
                onTap: () => onEventTap(o),
              )).toList(),
            ),
          ),
        if (allDay.isNotEmpty) const Divider(height: 1),
        // Hourly timeline
        for (var hour = 0; hour < 24; hour++)
          _HourRow(
            hour: hour,
            dayStart: dayStart,
            events: timed,
            colorScheme: colorScheme,
            onEventTap: onEventTap,
          ),
      ],
    );
  }
}

class _HourRow extends StatelessWidget {
  final int hour;
  final int dayStart;
  final List<CalendarOccurrence> events;
  final ColorScheme colorScheme;
  final void Function(CalendarOccurrence) onEventTap;

  const _HourRow({
    required this.hour,
    required this.dayStart,
    required this.events,
    required this.colorScheme,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    final hourStart = dayStart + hour * 60 * 60 * 1000;
    final hourEnd = hourStart + 60 * 60 * 1000;
    final hourEvents = events
        .where((o) => o.occurrenceStart < hourEnd && o.occurrenceEnd > hourStart)
        .toList();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Text(
                '${hour.toString().padLeft(2, '0')}:00',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          VerticalDivider(width: 1, color: colorScheme.onSurface.withValues(alpha: 0.1)),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(
                  color: colorScheme.onSurface.withValues(alpha: 0.05),
                )),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: hourEvents.map((o) => _EventBlock(
                  occurrence: o,
                  colorScheme: colorScheme,
                  onTap: () => onEventTap(o),
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventBlock extends StatelessWidget {
  final CalendarOccurrence occurrence;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _EventBlock({required this.occurrence, required this.colorScheme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final event = occurrence.event;
    final start = DateTime.fromMillisecondsSinceEpoch(occurrence.occurrenceStart);
    final end = DateTime.fromMillisecondsSinceEpoch(occurrence.occurrenceEnd);
    final color = event.color != null
        ? Color(event.color!)
        : colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.title.isEmpty ? '(Kein Titel)' : event.title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: colorScheme.onSurface,
                decoration: event.cancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            Text(
              '${_formatTime(start)} – ${_formatTime(end)}',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            if (event.location != null && event.location!.isNotEmpty)
              Text(
                event.location!,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _AllDayChip extends StatelessWidget {
  final CalendarOccurrence occurrence;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _AllDayChip({required this.occurrence, required this.colorScheme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final event = occurrence.event;
    final color = event.color != null ? Color(event.color!) : colorScheme.primary;
    return ActionChip(
      label: Text(
        event.title.isEmpty ? '(Kein Titel)' : event.title,
        style: TextStyle(
          fontSize: 12,
          color: Colors.white,
          decoration: event.cancelled ? TextDecoration.lineThrough : null,
        ),
      ),
      backgroundColor: color,
      onPressed: onTap,
    );
  }
}

// ── Week View ────────────────────────────────────────────────────────────

class _WeekView extends StatelessWidget {
  final DateTime date;
  final List<CalendarOccurrence> occurrences;
  final ColorScheme colorScheme;
  final void Function(CalendarOccurrence) onEventTap;
  final void Function(DateTime) onDayTap;

  const _WeekView({
    required this.date,
    required this.occurrences,
    required this.colorScheme,
    required this.onEventTap,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    final now = DateTime.now();
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(7, (i) {
        final day = DateTime(monday.year, monday.month, monday.day + i);
        final dayStart = day.millisecondsSinceEpoch;
        final dayEnd = dayStart + 24 * 60 * 60 * 1000;
        final dayOccs = occurrences
            .where((o) => o.occurrenceEnd > dayStart && o.occurrenceStart < dayEnd)
            .toList();
        final isToday = day.year == now.year && day.month == now.month && day.day == now.day;

        return Expanded(
          child: GestureDetector(
            onTap: () => onDayTap(day),
            child: Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(
                  color: colorScheme.onSurface.withValues(alpha: 0.1),
                )),
                color: isToday ? colorScheme.primary.withValues(alpha: 0.05) : null,
              ),
              child: Column(
                children: [
                  // Day header
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Text(weekdays[i], style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        )),
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isToday ? colorScheme.primary : Colors.transparent,
                          ),
                          alignment: Alignment.center,
                          child: Text('${day.day}', style: TextStyle(
                            fontSize: 14,
                            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                            color: isToday ? Colors.white : colorScheme.onSurface,
                          )),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Events
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(2),
                      children: dayOccs.map((o) => _CompactEventTile(
                        occurrence: o,
                        colorScheme: colorScheme,
                        onTap: () => onEventTap(o),
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _CompactEventTile extends StatelessWidget {
  final CalendarOccurrence occurrence;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _CompactEventTile({required this.occurrence, required this.colorScheme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final event = occurrence.event;
    final color = event.color != null ? Color(event.color!) : colorScheme.primary;
    final start = DateTime.fromMillisecondsSinceEpoch(occurrence.occurrenceStart);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          event.allDay
              ? event.title
              : '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} ${event.title}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.onSurface,
            decoration: event.cancelled ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

// ── Month View ───────────────────────────────────────────────────────────

class _MonthView extends StatelessWidget {
  final DateTime date;
  final List<CalendarOccurrence> occurrences;
  final ColorScheme colorScheme;
  final void Function(DateTime) onDayTap;

  const _MonthView({
    required this.date,
    required this.occurrences,
    required this.colorScheme,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(date.year, date.month, 1);
    final startWeekday = firstOfMonth.weekday; // 1=Mon
    final now = DateTime.now();
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

    return Column(
      children: [
        // Weekday headers
        Row(
          children: weekdays.map((d) => Expanded(
            child: Center(
              child: Text(d, style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              )),
            ),
          )).toList(),
        ),
        const Divider(height: 1),
        // Day grid
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.8,
            ),
            itemCount: 42, // 6 weeks
            itemBuilder: (context, index) {
              final dayOffset = index - (startWeekday - 1);
              final day = DateTime(date.year, date.month, dayOffset + 1);
              final isCurrentMonth = day.month == date.month;
              final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
              final dayStart = day.millisecondsSinceEpoch;
              final dayEnd = dayStart + 24 * 60 * 60 * 1000;
              final dayOccs = occurrences
                  .where((o) => o.occurrenceEnd > dayStart && o.occurrenceStart < dayEnd)
                  .toList();

              return GestureDetector(
                onTap: () => onDayTap(day),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.onSurface.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Day number
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isToday ? colorScheme.primary : Colors.transparent,
                              ),
                              alignment: Alignment.center,
                              child: Text('${day.day}', style: TextStyle(
                                fontSize: 12,
                                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                color: isToday
                                    ? Colors.white
                                    : isCurrentMonth
                                        ? colorScheme.onSurface
                                        : colorScheme.onSurface.withValues(alpha: 0.3),
                              )),
                            ),
                          ],
                        ),
                      ),
                      // Event indicators
                      ...dayOccs.take(3).map((o) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                          margin: const EdgeInsets.only(bottom: 1),
                          decoration: BoxDecoration(
                            color: (o.event.color != null
                                    ? Color(o.event.color!)
                                    : colorScheme.primary)
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            o.event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9, color: colorScheme.onSurface),
                          ),
                        ),
                      )),
                      if (dayOccs.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            '+${dayOccs.length - 3}',
                            style: TextStyle(
                              fontSize: 9,
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Year View ────────────────────────────────────────────────────────────

class _YearView extends StatelessWidget {
  final DateTime date;
  final List<CalendarOccurrence> occurrences;
  final ColorScheme colorScheme;
  final void Function(DateTime) onMonthTap;

  const _YearView({
    required this.date,
    required this.occurrences,
    required this.colorScheme,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    const monthNames = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    final now = DateTime.now();

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        final month = index + 1;
        final monthStart = DateTime(date.year, month, 1).millisecondsSinceEpoch;
        final monthEnd = DateTime(date.year, month + 1, 1).millisecondsSinceEpoch;
        final monthOccs = occurrences
            .where((o) => o.occurrenceEnd > monthStart && o.occurrenceStart < monthEnd)
            .toList();
        final isCurrentMonth = date.year == now.year && month == now.month;

        // Days with events
        final daysWithEvents = <int>{};
        for (final o in monthOccs) {
          final d = DateTime.fromMillisecondsSinceEpoch(o.occurrenceStart);
          daysWithEvents.add(d.day);
        }

        return GestureDetector(
          onTap: () => onMonthTap(DateTime(date.year, month, 1)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCurrentMonth
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.1),
                width: isCurrentMonth ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(monthNames[index], style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isCurrentMonth ? colorScheme.primary : colorScheme.onSurface,
                  )),
                ),
                Expanded(
                  child: _MiniMonthGrid(
                    year: date.year,
                    month: month,
                    daysWithEvents: daysWithEvents,
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniMonthGrid extends StatelessWidget {
  final int year, month;
  final Set<int> daysWithEvents;
  final ColorScheme colorScheme;

  const _MiniMonthGrid({
    required this.year,
    required this.month,
    required this.daysWithEvents,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startOffset = firstDay.weekday - 1;
    final now = DateTime.now();

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        final dayNum = index - startOffset + 1;
        if (dayNum < 1 || dayNum > daysInMonth) {
          return const SizedBox();
        }
        final isToday = year == now.year && month == now.month && dayNum == now.day;
        final hasEvent = daysWithEvents.contains(dayNum);

        return Center(
          child: Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isToday
                  ? colorScheme.primary
                  : hasEvent
                      ? colorScheme.primary.withValues(alpha: 0.3)
                      : Colors.transparent,
            ),
            child: Center(
              child: Text('$dayNum', style: TextStyle(
                fontSize: 8,
                color: isToday ? Colors.white : colorScheme.onSurface.withValues(alpha: 0.6),
              )),
            ),
          ),
        );
      },
    );
  }
}

/// Tasks view — shows every event with category=task across the active
/// identity's calendar. Open first, then by due date asc, then by priority
/// desc (high first). Each row has a checkbox to toggle taskCompleted.
class _TasksView extends StatelessWidget {
  final ICleonaService service;
  final ColorScheme colorScheme;
  final AppLocale locale;
  final void Function(CalendarEvent task) onTaskTap;
  final void Function(CalendarEvent task) onTaskToggle;

  const _TasksView({
    required this.service,
    required this.colorScheme,
    required this.locale,
    required this.onTaskTap,
    required this.onTaskToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = service.calendarManager.getTasks(includeCompleted: true);

    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            locale.get('calendar_tasks_empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
      itemBuilder: (_, i) {
        final task = tasks[i];
        final due = task.taskDueDate ?? task.endTime;
        final dueDt = DateTime.fromMillisecondsSinceEpoch(due);
        final now = DateTime.now();
        final isOverdue = !task.taskCompleted && dueDt.isBefore(now);

        return ListTile(
          leading: Checkbox(
            value: task.taskCompleted,
            onChanged: (_) => onTaskToggle(task),
          ),
          title: Text(
            task.title,
            style: TextStyle(
              decoration: task.taskCompleted
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              color: task.taskCompleted
                  ? colorScheme.onSurface.withValues(alpha: 0.5)
                  : colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            _formatDue(dueDt, locale),
            style: TextStyle(
              color: isOverdue
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          trailing: _priorityBadge(task.taskPriority, colorScheme),
          onTap: () => onTaskTap(task),
        );
      },
    );
  }

  Widget? _priorityBadge(int priority, ColorScheme cs) {
    if (priority <= 0) return null;
    final (color, label) = switch (priority) {
      3 => (cs.error, '!!!'),
      2 => (cs.tertiary, '!!'),
      _ => (cs.secondary, '!'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatDue(DateTime due, AppLocale locale) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    final today = DateTime.now();
    final diff = DateTime(due.year, due.month, due.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    final base = '${due.day}. ${months[due.month - 1]} ${due.year}';
    if (diff == 0) return '${locale.get('calendar_tasks_today')} · $base';
    if (diff == 1) return '${locale.get('calendar_tasks_tomorrow')} · $base';
    if (diff < 0) return '${locale.get('calendar_tasks_overdue')} · $base';
    return base;
  }
}
