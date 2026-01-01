import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/calendar/recurrence_engine.dart';

/// Interactive calendar event card displayed inline in group chat.
/// Shows event details, RSVP status, and action buttons.
class CalendarEventCard extends StatelessWidget {
  final CalendarEvent event;

  const CalendarEventCard({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final locale = AppLocale.of(context);
    final appState = context.watch<CleonaAppState>();
    final service = appState.service;

    final start = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(event.endTime);
    final now = DateTime.now();
    final isUpcoming = start.isAfter(now) && start.difference(now).inMinutes <= 15;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorScheme.onSurface,
                      decoration: event.cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Date/Time
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.allDay
                      ? _formatDate(start)
                      : '${_formatDate(start)}, ${_formatTime(start)} – ${_formatTime(end)}',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
                if (event.recurrenceRule != null)
                  Text(
                    RecurrenceEngine.formatRrule(event.recurrenceRule!),
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                if (event.location != null && event.location!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text(event.location!, style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        )),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // RSVP summary
          if (event.rsvpResponses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(
                spacing: 8,
                children: _buildRsvpSummary(colorScheme),
              ),
            ),

          // Action buttons
          if (!event.cancelled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Accept
                  _ActionButton(
                    icon: Icons.check,
                    label: locale.get('calendar_accept'),
                    color: Colors.green,
                    onTap: () => service?.sendCalendarRsvp(event.eventId, RsvpStatus.accepted),
                  ),
                  // Decline
                  _ActionButton(
                    icon: Icons.close,
                    label: locale.get('calendar_decline'),
                    color: Colors.red,
                    onTap: () => service?.sendCalendarRsvp(event.eventId, RsvpStatus.declined),
                  ),
                  // Call (only at event time, if hasCall)
                  if (event.hasCall && isUpcoming)
                    _ActionButton(
                      icon: Icons.call,
                      label: 'Call',
                      color: Colors.blue,
                      onTap: () {
                        // Start group call via existing call infrastructure
                        if (event.groupId != null) {
                          service?.startGroupCall(event.groupId!);
                        }
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildRsvpSummary(ColorScheme colorScheme) {
    int accepted = 0, declined = 0, tentative = 0;
    for (final status in event.rsvpResponses.values) {
      switch (status) {
        case RsvpStatus.accepted: accepted++;
        case RsvpStatus.declined: declined++;
        case RsvpStatus.tentative: tentative++;
        case RsvpStatus.proposeNewTime: tentative++;
      }
    }

    return [
      if (accepted > 0)
        _RsvpBadge(count: accepted, icon: Icons.check, color: Colors.green, colorScheme: colorScheme),
      if (tentative > 0)
        _RsvpBadge(count: tentative, icon: Icons.help, color: Colors.orange, colorScheme: colorScheme),
      if (declined > 0)
        _RsvpBadge(count: declined, icon: Icons.close, color: Colors.red, colorScheme: colorScheme),
    ];
  }

  String _formatDate(DateTime dt) {
    const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    const months = ['', 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    return '${weekdays[dt.weekday - 1]}, ${dt.day}. ${months[dt.month]} ${dt.year}';
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }
}

class _RsvpBadge extends StatelessWidget {
  final int count;
  final IconData icon;
  final Color color;
  final ColorScheme colorScheme;

  const _RsvpBadge({
    required this.count,
    required this.icon,
    required this.color,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text('$count', style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurface.withValues(alpha: 0.6),
        )),
      ],
    );
  }
}
