import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/ui/theme/skins.dart';

/// Event creation/editing screen.
class EventEditorScreen extends StatefulWidget {
  final CalendarEvent event;
  final bool isNew;

  const EventEditorScreen({
    super.key,
    required this.event,
    required this.isNew,
  });

  @override
  State<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends State<EventEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _locationController;
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  late bool _allDay;
  late EventCategory _category;
  late bool _hasCall;
  late FreeBusyLevel _visibility;
  late List<int> _reminders;
  late int _taskPriority;
  String? _recurrenceRule;

  // Group selection for group events
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _titleController = TextEditingController(text: e.title);
    _descriptionController = TextEditingController(text: e.description ?? '');
    _locationController = TextEditingController(text: e.location ?? '');

    final start = DateTime.fromMillisecondsSinceEpoch(e.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(e.endTime);
    _startDate = DateTime(start.year, start.month, start.day);
    _startTime = TimeOfDay(hour: start.hour, minute: start.minute);
    _endDate = DateTime(end.year, end.month, end.day);
    _endTime = TimeOfDay(hour: end.hour, minute: end.minute);
    _allDay = e.allDay;
    _category = e.category;
    _hasCall = e.hasCall;
    _visibility = e.freeBusyVisibility;
    _reminders = List.from(e.reminders);
    _taskPriority = e.taskPriority;
    _recurrenceRule = e.recurrenceRule;
    _selectedGroupId = e.groupId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final locale = AppLocale.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final service = appState.service;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? locale.get('calendar_new_event') : locale.get('calendar_edit_event')),
        actions: [
          if (!widget.isNew)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _deleteEvent(context),
            ),
          TextButton(
            onPressed: () => _saveEvent(context),
            child: Text(locale.get('save'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _IdentityScopeHeader(
            captionKey: widget.isNew
                ? 'calendar_event_identity_caption_new'
                : 'calendar_event_identity_caption_edit',
            // For an existing event the identity is fixed (events are owned
            // by the identity that created them) — only the new-event flow
            // can re-target.
            allowSwitch: widget.isNew,
            event: widget.event,
          ),
          const SizedBox(height: 12),

          // Title
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: locale.get('calendar_title'),
              hintText: locale.get('calendar_title_hint'),
            ),
            autofocus: widget.isNew,
          ),
          const SizedBox(height: 16),

          // Category
          DropdownButtonFormField<EventCategory>(
            initialValue: _category,
            decoration: InputDecoration(labelText: locale.get('calendar_category')),
            items: EventCategory.values.map((c) => DropdownMenuItem(
              value: c,
              child: Row(
                children: [
                  Icon(_categoryIcon(c), size: 20),
                  const SizedBox(width: 8),
                  Text(_categoryName(c, locale)),
                ],
              ),
            )).toList(),
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 16),

          // All day toggle
          SwitchListTile(
            title: Text(locale.get('calendar_all_day')),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
            contentPadding: EdgeInsets.zero,
          ),

          // Start date/time
          _DateTimePicker(
            label: locale.get('calendar_start'),
            date: _startDate,
            time: _allDay ? null : _startTime,
            colorScheme: colorScheme,
            onDateChanged: (d) => setState(() => _startDate = d),
            onTimeChanged: (t) => setState(() => _startTime = t),
          ),
          const SizedBox(height: 8),

          // End date/time
          _DateTimePicker(
            label: locale.get('calendar_end'),
            date: _endDate,
            time: _allDay ? null : _endTime,
            colorScheme: colorScheme,
            onDateChanged: (d) => setState(() => _endDate = d),
            onTimeChanged: (t) => setState(() => _endTime = t),
          ),
          const SizedBox(height: 16),

          // Location
          if (_category != EventCategory.task && _category != EventCategory.birthday)
            TextField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: locale.get('calendar_location'),
                prefixIcon: const Icon(Icons.location_on),
              ),
            ),
          if (_category != EventCategory.task && _category != EventCategory.birthday)
            const SizedBox(height: 16),

          // Description
          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: locale.get('calendar_description'),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),

          // Recurrence
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.repeat),
            title: Text(_recurrenceRule != null
                ? _formatRecurrence(_recurrenceRule!)
                : locale.get('calendar_no_repeat')),
            onTap: () => _showRecurrenceDialog(context, locale),
          ),
          const Divider(),

          // Reminders
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications),
            title: Text('${_reminders.length} ${locale.get("calendar_reminders")}'),
            subtitle: Text(_reminders.map(_formatReminderMinutes).join(', ')),
            onTap: () => _showRemindersDialog(context, locale),
          ),
          const Divider(),

          // Group event / Call integration
          if (service != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.group),
              title: Text(_selectedGroupId != null
                  ? locale.get('calendar_group_event')
                  : locale.get('calendar_personal_event')),
              onTap: () => _showGroupSelector(context, locale),
            ),
            if (_selectedGroupId != null)
              SwitchListTile(
                title: Text(locale.get('calendar_start_call')),
                subtitle: Text(locale.get('calendar_start_call_hint')),
                value: _hasCall,
                onChanged: (v) => setState(() => _hasCall = v),
                contentPadding: EdgeInsets.zero,
              ),
            const Divider(),
          ],

          // Free/Busy visibility
          DropdownButtonFormField<FreeBusyLevel>(
            initialValue: _visibility,
            decoration: InputDecoration(labelText: locale.get('calendar_visibility')),
            items: FreeBusyLevel.values.map((v) => DropdownMenuItem(
              value: v,
              child: Text(_visibilityName(v, locale)),
            )).toList(),
            onChanged: (v) => setState(() => _visibility = v!),
          ),
          const SizedBox(height: 16),

          // Task-specific: Priority
          if (_category == EventCategory.task) ...[
            DropdownButtonFormField<int>(
              initialValue: _taskPriority,
              decoration: InputDecoration(labelText: locale.get('calendar_priority')),
              items: [
                DropdownMenuItem(value: 0, child: Text(locale.get('calendar_priority_none'))),
                DropdownMenuItem(value: 1, child: Text(locale.get('calendar_priority_low'))),
                DropdownMenuItem(value: 2, child: Text(locale.get('calendar_priority_medium'))),
                DropdownMenuItem(value: 3, child: Text(locale.get('calendar_priority_high'))),
              ],
              onChanged: (v) => setState(() => _taskPriority = v!),
            ),
            const SizedBox(height: 16),
          ],

          // RSVP status (for received group events)
          if (!widget.isNew && widget.event.groupId != null &&
              widget.event.createdBy != widget.event.identityId)
            _RsvpSection(event: widget.event, colorScheme: colorScheme, locale: locale),
        ],
      ),
    );
  }

  void _saveEvent(BuildContext context) {
    final appState = context.read<CleonaAppState>();
    final service = appState.service;
    if (service == null) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Titel eingeben')),
      );
      return;
    }

    final start = _allDay
        ? _startDate
        : DateTime(_startDate.year, _startDate.month, _startDate.day,
            _startTime.hour, _startTime.minute);
    final end = _allDay
        ? _endDate.add(const Duration(days: 1))
        : DateTime(_endDate.year, _endDate.month, _endDate.day,
            _endTime.hour, _endTime.minute);

    final event = widget.event;
    event.title = title;
    event.description = _descriptionController.text.isNotEmpty
        ? _descriptionController.text
        : null;
    event.location = _locationController.text.isNotEmpty
        ? _locationController.text
        : null;
    event.startTime = start.millisecondsSinceEpoch;
    event.endTime = end.millisecondsSinceEpoch;
    event.allDay = _allDay;
    event.category = _category;
    event.hasCall = _hasCall;
    event.freeBusyVisibility = _visibility;
    event.reminders = _reminders;
    event.taskPriority = _taskPriority;
    event.recurrenceRule = _recurrenceRule;
    event.groupId = _selectedGroupId;
    event.updatedAt = DateTime.now().millisecondsSinceEpoch;

    if (widget.isNew) {
      service.createCalendarEvent(event);
    } else {
      service.updateCalendarEvent(event.eventId,
        title: event.title,
        description: event.description,
        location: event.location,
        startTime: event.startTime,
        endTime: event.endTime,
        allDay: event.allDay,
        hasCall: event.hasCall,
        reminders: event.reminders,
        recurrenceRule: event.recurrenceRule,
        taskCompleted: event.taskCompleted,
        taskPriority: event.taskPriority,
      );
    }

    Navigator.pop(context);
  }

  void _deleteEvent(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Termin löschen?'),
        content: Text('${widget.event.title} wird gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () {
              final service = context.read<CleonaAppState>().service;
              if (service != null) {
                service.deleteCalendarEvent(widget.event.eventId);
              }
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRecurrenceDialog(BuildContext context, AppLocale locale) {
    final options = <String?>[
      null,
      'FREQ=DAILY',
      'FREQ=WEEKLY',
      'FREQ=WEEKLY;BYDAY=MO,WE,FR',
      'FREQ=MONTHLY',
      'FREQ=YEARLY',
    ];
    final labels = [
      locale.get('calendar_no_repeat'),
      'Täglich',
      'Wöchentlich',
      'Mo, Mi, Fr',
      'Monatlich',
      'Jährlich',
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(locale.get('calendar_recurrence')),
        children: List.generate(options.length, (i) => SimpleDialogOption(
          onPressed: () {
            setState(() => _recurrenceRule = options[i]);
            Navigator.pop(ctx);
          },
          child: Text(labels[i], style: TextStyle(
            fontWeight: _recurrenceRule == options[i] ? FontWeight.bold : FontWeight.normal,
          )),
        )),
      ),
    );
  }

  void _showRemindersDialog(BuildContext context, AppLocale locale) {
    final allOptions = [0, 5, 10, 15, 30, 60, 120, 1440, 10080]; // minutes
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(locale.get('calendar_reminders')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: allOptions.map((m) => CheckboxListTile(
              title: Text(_formatReminderMinutes(m)),
              value: _reminders.contains(m),
              onChanged: (checked) {
                setDialogState(() {
                  if (checked == true) {
                    _reminders.add(m);
                  } else {
                    _reminders.remove(m);
                  }
                });
                setState(() {});
              },
            )).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(locale.get('ok'))),
          ],
        ),
      ),
    );
  }

  void _showGroupSelector(BuildContext context, AppLocale locale) {
    final appState = context.read<CleonaAppState>();
    final service = appState.service;
    if (service == null) return;

    final groups = service.groups;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(locale.get('calendar_select_group')),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() => _selectedGroupId = null);
              Navigator.pop(ctx);
            },
            child: Text(locale.get('calendar_personal_event'),
                style: TextStyle(fontWeight: _selectedGroupId == null ? FontWeight.bold : FontWeight.normal)),
          ),
          ...groups.entries.map((e) => SimpleDialogOption(
            onPressed: () {
              setState(() => _selectedGroupId = e.key);
              Navigator.pop(ctx);
            },
            child: Text(e.value.name,
                style: TextStyle(fontWeight: _selectedGroupId == e.key ? FontWeight.bold : FontWeight.normal)),
          )),
        ],
      ),
    );
  }

  String _formatRecurrence(String rrule) {
    final parts = rrule.split(';');
    for (final p in parts) {
      if (p.startsWith('FREQ=')) {
        switch (p.substring(5)) {
          case 'DAILY': return 'Täglich';
          case 'WEEKLY': return 'Wöchentlich';
          case 'MONTHLY': return 'Monatlich';
          case 'YEARLY': return 'Jährlich';
        }
      }
    }
    return rrule;
  }

  String _formatReminderMinutes(int minutes) {
    if (minutes == 0) return 'Zum Zeitpunkt';
    if (minutes < 60) return '$minutes Min vorher';
    if (minutes < 1440) return '${minutes ~/ 60} Std vorher';
    if (minutes < 10080) return '${minutes ~/ 1440} Tag(e) vorher';
    return '${minutes ~/ 10080} Woche(n) vorher';
  }

  IconData _categoryIcon(EventCategory c) => switch (c) {
        EventCategory.appointment => Icons.event,
        EventCategory.task => Icons.check_box_outlined,
        EventCategory.birthday => Icons.cake,
        EventCategory.reminder => Icons.alarm,
        EventCategory.meeting => Icons.groups,
      };

  String _categoryName(EventCategory c, AppLocale locale) => switch (c) {
        EventCategory.appointment => locale.get('calendar_cat_appointment'),
        EventCategory.task => locale.get('calendar_cat_task'),
        EventCategory.birthday => locale.get('calendar_cat_birthday'),
        EventCategory.reminder => locale.get('calendar_cat_reminder'),
        EventCategory.meeting => locale.get('calendar_cat_meeting'),
      };

  String _visibilityName(FreeBusyLevel v, AppLocale locale) => switch (v) {
        FreeBusyLevel.full => locale.get('calendar_vis_full'),
        FreeBusyLevel.timeOnly => locale.get('calendar_vis_time_only'),
        FreeBusyLevel.hidden => locale.get('calendar_vis_hidden'),
      };
}

// ── Date/Time Picker ──────────────────────────────────────────────────────

class _DateTimePicker extends StatelessWidget {
  final String label;
  final DateTime date;
  final TimeOfDay? time;
  final ColorScheme colorScheme;
  final void Function(DateTime) onDateChanged;
  final void Function(TimeOfDay)? onTimeChanged;

  const _DateTimePicker({
    required this.label,
    required this.date,
    this.time,
    required this.colorScheme,
    required this.onDateChanged,
    this.onTimeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ', style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.6))),
        TextButton(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked != null) onDateChanged(picked);
          },
          child: Text('${date.day}.${date.month}.${date.year}'),
        ),
        if (time != null && onTimeChanged != null)
          TextButton(
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: time!,
              );
              if (picked != null) onTimeChanged!(picked);
            },
            child: Text('${time!.hour.toString().padLeft(2, '0')}:'
                '${time!.minute.toString().padLeft(2, '0')}'),
          ),
      ],
    );
  }
}

// ── RSVP Section ──────────────────────────────────────────────────────────

class _RsvpSection extends StatelessWidget {
  final CalendarEvent event;
  final ColorScheme colorScheme;
  final AppLocale locale;

  const _RsvpSection({required this.event, required this.colorScheme, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(locale.get('calendar_rsvp'), style: TextStyle(
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        )),
        const SizedBox(height: 8),
        // RSVP buttons
        Row(
          children: [
            _rsvpButton(context, RsvpStatus.accepted, Icons.check_circle, Colors.green),
            const SizedBox(width: 8),
            _rsvpButton(context, RsvpStatus.tentative, Icons.help, Colors.orange),
            const SizedBox(width: 8),
            _rsvpButton(context, RsvpStatus.declined, Icons.cancel, Colors.red),
          ],
        ),
        // Existing RSVP responses
        if (event.rsvpResponses.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...event.rsvpResponses.entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  switch (e.value) {
                    RsvpStatus.accepted => Icons.check_circle,
                    RsvpStatus.declined => Icons.cancel,
                    RsvpStatus.tentative => Icons.help,
                    RsvpStatus.proposeNewTime => Icons.schedule,
                  },
                  size: 16,
                  color: switch (e.value) {
                    RsvpStatus.accepted => Colors.green,
                    RsvpStatus.declined => Colors.red,
                    RsvpStatus.tentative => Colors.orange,
                    RsvpStatus.proposeNewTime => Colors.blue,
                  },
                ),
                const SizedBox(width: 4),
                Text(e.key.substring(0, 8), style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                )),
              ],
            ),
          )),
        ],
      ],
    );
  }

  Widget _rsvpButton(BuildContext context, RsvpStatus status, IconData icon, Color color) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 18, color: color),
      label: Text(switch (status) {
        RsvpStatus.accepted => locale.get('calendar_accept'),
        RsvpStatus.tentative => locale.get('calendar_tentative'),
        RsvpStatus.declined => locale.get('calendar_decline'),
        RsvpStatus.proposeNewTime => '',
      }),
      onPressed: () {
        final service = context.read<CleonaAppState>().service;
        service?.sendCalendarRsvp(event.eventId, status);
        Navigator.pop(context);
      },
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Identity-scope header
// ════════════════════════════════════════════════════════════════════
//
// Shown above the editor body. For an existing event the identity is
// the owner (frozen — events can't be re-targeted); for a new event the
// caption follows the active identity from the home tab and the user
// can switch in-place via [CleonaAppState.switchIdentity].
class _IdentityScopeHeader extends StatelessWidget {
  final String captionKey;
  final bool allowSwitch;
  final CalendarEvent event;
  const _IdentityScopeHeader({
    required this.captionKey,
    required this.allowSwitch,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final locale = AppLocale.of(context);
    final mgr = IdentityManager();
    final identities = mgr.loadIdentities();
    // For an existing event, show the OWNING identity (event.identityId).
    // For a new event, show the currently-active identity.
    final shownId = allowSwitch
        ? mgr.getActiveIdentity()?.id
        : identities
            .where((i) => i.id == event.identityId)
            .map((i) => i.id)
            .firstOrNull;
    final shown = identities.where((i) => i.id == shownId).firstOrNull;
    if (shown == null) return const SizedBox.shrink();
    final brightness = Theme.of(context).brightness;
    final shownColor =
        Skins.byId(shown.skinId).effectiveColor(brightness);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: shownColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locale.get(captionKey),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                  Text(shown.displayName,
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            if (allowSwitch && identities.length > 1)
              DropdownButton<String>(
                value: shown.id,
                underline: const SizedBox.shrink(),
                items: [
                  for (final id in identities)
                    DropdownMenuItem(
                      value: id.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Skins.byId(id.skinId)
                                  .effectiveColor(brightness),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(id.displayName),
                        ],
                      ),
                    ),
                ],
                onChanged: (newId) {
                  if (newId == null || newId == shown.id) return;
                  final picked =
                      identities.firstWhere((i) => i.id == newId);
                  appState.switchIdentity(picked);
                },
              ),
          ],
        ),
      ),
    );
  }
}
