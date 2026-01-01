import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/calendar/recurrence_engine.dart';
import 'package:cleona/core/calls/group_call_manager.dart';
import 'package:cleona/ui/theme/theme_access.dart';

/// Density control for [CalendarEventCard].
///
/// - [compact]     — tight vertical padding (4 px); ideal for list views.
/// - [comfortable] — default padding (8 px); balanced for chat bubbles.
/// - [spacious]    — generous padding (12 px); suitable for standalone event
///                   previews where breathing room aids readability.
enum CardDensity { compact, comfortable, spacious }

/// Interactive calendar event card displayed inline in group chat.
/// Shows event details, RSVP status, and action buttons.
class CalendarEventCard extends StatelessWidget {
  final CalendarEvent event;

  /// Controls vertical padding of the card body. Defaults to [CardDensity.comfortable].
  final CardDensity density;

  /// When true, renders a 4 px colour stripe at the left edge keyed to
  /// [event.category].
  ///
  /// S368: here stood "Defaults to false for backward compatibility".
  /// This reasoning is wrong — there is no "backward" against which
  /// a default would have to protect.
  ///
  /// ── AND HERE STOOD A SECOND FALSE CLAIM, MINE ────────────
  ///
  /// First I wrote at this place "this component has ZERO users
  /// in `lib/`". That was measured against the branch point of this branch
  /// and is wrong against the TARGET STATE `v4/knoten-host`: commit
  /// `b1926e45` (S367 3.6) hangs the card on the chat history, and
  /// `chat_screen.dart:4548` calls it with `showCategory: true` — so the
  /// only production caller flips the default anyway.
  ///
  /// The default stays `false`, but now for a load-bearing reason:
  /// whoever uses the card elsewhere gets the narrow form, and the
  /// one place that wants the colour stripe says so. That is a
  /// design default, not consideration for legacy data.
  final bool showCategory;

  const CalendarEventCard({
    super.key,
    required this.event,
    this.density = CardDensity.comfortable,
    this.showCategory = false,
  });

  // ---------------------------------------------------------------------------
  // Density + category helpers
  // ---------------------------------------------------------------------------

  double _verticalPadding(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    switch (density) {
      case CardDensity.compact:
        return tokens.spacing.xs;
      case CardDensity.comfortable:
        return tokens.spacing.sm;
      case CardDensity.spacious:
        return tokens.spacing.md;
    }
  }

  Widget _categoryStripe() {
    return Container(width: 4, color: _categoryColor(event.category));
  }

  static Color _categoryColor(EventCategory category) {
    switch (category) {
      case EventCategory.meeting:
        return Colors.blue;
      case EventCategory.appointment:
        return Colors.teal;
      case EventCategory.task:
        return Colors.orange;
      case EventCategory.birthday:
        return Colors.pink;
      case EventCategory.reminder:
        return Colors.grey;
    }
  }

  // ---------------------------------------------------------------------------
  // Call button decision (§18.1.7)
  // ---------------------------------------------------------------------------

  /// What the "Call" button of [event] does.
  ///
  /// §18.1.7: a group event offers a group-call start only up to the
  /// full-mesh ceiling of §17.7 ([GroupCallManager.maxParticipantsMesh]);
  /// above it, no start. A 1:1 event starts a 1:1 call without condition.
  ///
  /// The group size counted is the one [GroupCallManager.startGroupCall]
  /// invites: every member who accepted plus the caller; with nobody who
  /// accepted there is nobody to call and no button. An event without a
  /// group whose only other party is one contact is a 1:1 event; the other
  /// party is the attendee for the creator and the creator for an attendee.
  /// An event without a group and with several other parties has no call
  /// path (a group call needs a group) and therefore no button.
  static EventCallAction resolveCallAction(
    CalendarEvent event, {
    required String? selfId,
    required Map<String, GroupInfo> groups,
  }) {
    final groupId = event.groupId;
    if (groupId != null) {
      final group = groups[groupId];
      if (group == null) return const EventCallAction(EventCallKind.none);
      // §18.1.7: "a click starts a group call with everyone who accepted".
      // Until S407 this counted and rang the whole group. The organizer
      // counts as accepted unless it declined — as in iCalendar, where
      // the ORGANIZER is a participant without answering its own
      // invitation (RFC 5545 §3.8.4.3, §3.2.12 PARTSTAT).
      final invitees = <String>{
        for (final id in group.members.keys)
          if (id != selfId &&
              (event.rsvpResponses[id] == RsvpStatus.accepted ||
                  (id == event.createdBy &&
                      event.rsvpResponses[id] != RsvpStatus.declined)))
            id,
      };
      if (invitees.isEmpty) return const EventCallAction(EventCallKind.none);
      final participants = {...invitees, ?selfId};
      if (participants.length > GroupCallManager.maxParticipantsMesh) {
        return EventCallAction(EventCallKind.groupTooLarge,
            target: groupId, invitees: invitees);
      }
      return EventCallAction(EventCallKind.group,
          target: groupId, invitees: invitees);
    }
    final others = {...event.attendeeNodeIds, event.createdBy}
      ..remove(selfId)
      ..removeWhere((id) => id.isEmpty);
    if (others.length != 1) return const EventCallAction(EventCallKind.none);
    return EventCallAction(EventCallKind.oneToOne, target: others.single);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final locale = AppLocale.of(context);
    final appState = context.watch<CleonaAppState>();
    final service = appState.service;

    final vPad = _verticalPadding(context);

    final start = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(event.endTime);
    final now = DateTime.now();
    final isUpcoming = start.isAfter(now) && start.difference(now).inMinutes <= 15;
    final callAction = resolveCallAction(
      event,
      selfId: service?.nodeIdHex,
      groups: service?.groups ?? const {},
    );

    // Card body (column of header + details + actions)
    final cardBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: vPad),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: showCategory
                ? BorderRadius.zero
                : const BorderRadius.vertical(top: Radius.circular(12)),
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
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: vPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.allDay
                    ? formatDate(start, locale)
                    : '${formatDate(start, locale)}, ${_formatTime(start)} – ${_formatTime(end)}',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
              if (event.recurrenceRule != null)
                Text(
                  RecurrenceEngine.formatRrule(event.recurrenceRule!,
                      AppLocale.of(context).currentLocale),
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
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: vPad),
            child: Wrap(
              spacing: 8,
              children: _buildRsvpSummary(colorScheme),
            ),
          ),

        // Action buttons
        if (!event.cancelled)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: vPad),
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
                // Call (only at event time, if hasCall) — §18.1.7
                if (event.hasCall && isUpcoming &&
                    callAction.kind != EventCallKind.none)
                  _ActionButton(
                    icon: Icons.call,
                    label: locale.get('calendar_start_call'),
                    color: Colors.blue,
                    onTap: switch (callAction.kind) {
                      EventCallKind.oneToOne => () =>
                          service?.startCall(callAction.target!),
                      EventCallKind.group => () => service?.startGroupCall(
                          callAction.target!,
                          invitees: callAction.invitees),
                      // Above the full-mesh ceiling: no start (§18.1.7).
                      EventCallKind.groupTooLarge => null,
                      EventCallKind.none => null,
                    },
                  ),
              ],
            ),
          ),
        if (!event.cancelled &&
            event.hasCall &&
            isUpcoming &&
            callAction.kind == EventCallKind.groupTooLarge)
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, vPad),
            child: Text(
              locale.get('calendar_call_too_many').replaceAll(
                  '{max}', '${GroupCallManager.maxParticipantsMesh}'),
              style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
      ),
      // ClipRRect ensures the category stripe is clipped to the card's rounded corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: showCategory
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _categoryStripe(),
                    Expanded(child: cardBody),
                  ],
                ),
              )
            : cardBody,
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

  /// The date in the reader's language (S410: stood as German weekday and
  /// month abbreviations in every language).
  static String formatDate(DateTime dt, AppLocale locale) =>
      locale.tr('calendar_card_date', {
        'weekday': locale.get('weekday_short_${dt.weekday}'),
        'day': '${dt.day}',
        'month': locale.get('month_${dt.month}'),
        'm': '${dt.month}',
        'year': '${dt.year}',
      });

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

/// What the "Call" button of an event card does (§18.1.7).
enum EventCallKind {
  /// No button: no call path for this event.
  none,

  /// 1:1 event: starts a 1:1 call with [EventCallAction.target].
  oneToOne,

  /// Group event within the full-mesh ceiling: starts a group call.
  group,

  /// Group event above the full-mesh ceiling: button disabled, hint shown.
  groupTooLarge,
}

/// Result of [CalendarEventCard.resolveCallAction].
class EventCallAction {
  final EventCallKind kind;

  /// Peer user id (1:1) or group id (group); `null` for [EventCallKind.none].
  final String? target;

  /// For [EventCallKind.group]: the members to ring — "everyone who
  /// accepted" (§18.1.7), without the own identity.
  final Set<String>? invitees;

  const EventCallAction(this.kind, {this.target, this.invitees});
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  /// `null` draws the button disabled.
  final VoidCallback? onTap;

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
