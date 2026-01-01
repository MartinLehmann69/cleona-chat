import 'dart:typed_data';

import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/service/service_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

class CalendarProtocolService {
  CalendarProtocolService(this._ctx, this.calendarManager);

  final ServiceContext _ctx;
  final CalendarManager calendarManager;
  late final CLogger _log;

  // ── State ─────────────────────────────────────────────────────────
  final Map<String, List<FreeBusyBlockResult>> freeBusyResults = {};
  final Map<String, void Function(List<FreeBusyBlockResult>)> freeBusyCallbacks = {};

  // ── Callbacks (wired from CleonaService) ──────────────────────────
  void Function(String senderHex, String eventIdHex, String title)? onCalendarInviteReceived;
  void Function(String eventIdHex, String senderHex, RsvpStatus status)? onCalendarRsvpReceived;
  void Function(String eventIdHex)? onCalendarEventUpdated;

  void init() {
    _log = CLogger.get('calendar-proto', profileDir: _ctx.identity.profileDir);
  }

  // ── Public API ────────────────────────────────────────────────────

  Future<String> createCalendarEvent(CalendarEvent event) async {
    if (_ctx.reducedMode) {
      _log.warn('createCalendarEvent blocked: reducedMode active');
      return '';
    }
    calendarManager.createEvent(event);
    if (event.groupId != null) {
      await sendCalendarInvite(event);
    }
    return event.eventId;
  }

  Future<bool> updateCalendarEvent(String eventIdHex, {
    String? title, String? description, String? location,
    int? startTime, int? endTime, bool? allDay, bool? hasCall,
    List<int>? reminders, String? recurrenceRule,
    bool? taskCompleted, int? taskPriority, bool? cancelled,
  }) async {
    if (_ctx.reducedMode) {
      _log.warn('updateCalendarEvent blocked: reducedMode active');
      return false;
    }
    final ok = calendarManager.updateEvent(eventIdHex,
      title: title, description: description, location: location,
      startTime: startTime, endTime: endTime, allDay: allDay,
      hasCall: hasCall, reminders: reminders, recurrenceRule: recurrenceRule,
      taskCompleted: taskCompleted, taskPriority: taskPriority,
      cancelled: cancelled,
    );
    if (ok) {
      final evt = calendarManager.events[eventIdHex];
      if (evt?.groupId != null && evt?.createdBy == _ctx.identity.userIdHex) {
        await sendCalendarUpdate(eventIdHex);
      }
    }
    return ok;
  }

  Future<bool> deleteCalendarEvent(String eventIdHex) async {
    if (_ctx.reducedMode) {
      _log.warn('deleteCalendarEvent blocked: reducedMode active');
      return false;
    }
    final evt = calendarManager.events[eventIdHex];
    if (evt?.groupId != null && evt?.createdBy == _ctx.identity.userIdHex) {
      await sendCalendarDelete(eventIdHex);
    } else {
      calendarManager.deleteEvent(eventIdHex);
    }
    return true;
  }

  // ── Senders ───────────────────────────────────────────────────────

  Future<void> sendCalendarInvite(CalendarEvent event) async {
    if (_ctx.reducedMode) {
      _log.warn('sendCalendarInvite blocked: reducedMode active');
      return;
    }
    if (event.groupId == null) return;

    final group = _ctx.groups[event.groupId!];
    if (group == null) {
      _log.warn('Cannot send calendar invite: group ${event.groupId} not found');
      return;
    }

    final invite = proto.CalendarInviteMsg()
      ..eventId = hexToBytes(event.eventId)
      ..title = event.title
      ..description = event.description ?? ''
      ..location = event.location ?? ''
      ..startTime = Int64(event.startTime)
      ..endTime = Int64(event.endTime)
      ..allDay = event.allDay
      ..timeZone = event.timeZone
      ..recurrenceRule = event.recurrenceRule ?? ''
      ..hasCall = event.hasCall
      ..groupId = hexToBytes(event.groupId!)
      ..createdBy = _ctx.identity.userId
      ..createdByName = _ctx.displayName
      ..category = proto.EventCategory.valueOf(event.category.index) ?? proto.EventCategory.APPOINTMENT;
    for (final m in event.reminders) {
      invite.reminders.add(proto.CalendarReminderOffset()..minutesBefore = m);
    }

    final payload = invite.writeToBuffer();
    for (final memberHex in group.members.keys) {
      if (memberHex == _ctx.identity.userIdHex) continue;
      await _ctx.sendEncryptedPayload(
        hexToBytes(memberHex),
        proto.MessageTypeV3.MTV3_CALENDAR_INVITE,
        Uint8List.fromList(payload),
      );
    }

    _log.info('Sent CALENDAR_INVITE for ${event.title} to ${group.members.length - 1} members');
  }

  Future<void> sendCalendarRsvp(String eventIdHex, RsvpStatus status, {
    int? proposedStart,
    int? proposedEnd,
    String? comment,
  }) async {
    if (_ctx.reducedMode) {
      _log.warn('sendCalendarRsvp blocked: reducedMode active');
      return;
    }
    final event = calendarManager.events[eventIdHex];
    if (event == null || event.groupId == null) return;

    final group = _ctx.groups[event.groupId!];
    if (group == null) return;

    final rsvp = proto.CalendarRsvpMsg()
      ..eventId = hexToBytes(eventIdHex)
      ..response = proto.RsvpStatus.valueOf(status.index) ?? proto.RsvpStatus.RSVP_ACCEPTED
      ..comment = comment ?? '';
    if (proposedStart != null) rsvp.proposedStart = Int64(proposedStart);
    if (proposedEnd != null) rsvp.proposedEnd = Int64(proposedEnd);

    calendarManager.setRsvp(eventIdHex, _ctx.identity.userIdHex, status);

    final payload = rsvp.writeToBuffer();
    for (final memberHex in group.members.keys) {
      if (memberHex == _ctx.identity.userIdHex) continue;
      await _ctx.sendEncryptedPayload(
        hexToBytes(memberHex),
        proto.MessageTypeV3.MTV3_CALENDAR_RSVP,
        Uint8List.fromList(payload),
      );
    }

    _log.info('Sent CALENDAR_RSVP for $eventIdHex: $status');
  }

  Future<void> sendCalendarUpdate(String eventIdHex) async {
    if (_ctx.reducedMode) {
      _log.warn('sendCalendarUpdate blocked: reducedMode active');
      return;
    }
    final event = calendarManager.events[eventIdHex];
    if (event == null || event.groupId == null) return;

    final group = _ctx.groups[event.groupId!];
    if (group == null) return;

    final update = proto.CalendarUpdateMsg()
      ..eventId = hexToBytes(eventIdHex)
      ..title = event.title
      ..description = event.description ?? ''
      ..location = event.location ?? ''
      ..startTime = Int64(event.startTime)
      ..endTime = Int64(event.endTime)
      ..allDay = event.allDay
      ..timeZone = event.timeZone
      ..recurrenceRule = event.recurrenceRule ?? ''
      ..hasCall = event.hasCall
      ..cancelled = event.cancelled
      ..updatedAt = Int64(event.updatedAt);
    for (final m in event.reminders) {
      update.reminders.add(proto.CalendarReminderOffset()..minutesBefore = m);
    }

    final payload = update.writeToBuffer();
    for (final memberHex in group.members.keys) {
      if (memberHex == _ctx.identity.userIdHex) continue;
      await _ctx.sendEncryptedPayload(
        hexToBytes(memberHex),
        proto.MessageTypeV3.MTV3_CALENDAR_UPDATE,
        Uint8List.fromList(payload),
      );
    }

    _log.info('Sent CALENDAR_UPDATE for $eventIdHex');
  }

  Future<void> sendCalendarDelete(String eventIdHex) async {
    if (_ctx.reducedMode) {
      _log.warn('sendCalendarDelete blocked: reducedMode active');
      return;
    }
    final event = calendarManager.events[eventIdHex];
    if (event == null || event.groupId == null) return;

    final group = _ctx.groups[event.groupId!];
    if (group == null) return;

    final del = proto.CalendarDeleteMsg()
      ..eventId = hexToBytes(eventIdHex)
      ..deletedAt = Int64(DateTime.now().millisecondsSinceEpoch);

    final payload = del.writeToBuffer();
    for (final memberHex in group.members.keys) {
      if (memberHex == _ctx.identity.userIdHex) continue;
      await _ctx.sendEncryptedPayload(
        hexToBytes(memberHex),
        proto.MessageTypeV3.MTV3_CALENDAR_DELETE,
        Uint8List.fromList(payload),
      );
    }

    calendarManager.deleteEvent(eventIdHex);
    _log.info('Sent CALENDAR_DELETE for $eventIdHex');
  }

  Future<String> sendFreeBusyRequest(String contactNodeIdHex, int queryStart, int queryEnd) async {
    if (_ctx.reducedMode) {
      _log.warn('sendFreeBusyRequest blocked: reducedMode active');
      return '';
    }
    final requestIdBytes = SodiumFFI().randomBytes(16);
    final requestIdHex = bytesToHex(requestIdBytes);

    final req = proto.FreeBusyRequestMsg()
      ..queryStart = Int64(queryStart)
      ..queryEnd = Int64(queryEnd)
      ..requestId = requestIdBytes;

    await _ctx.sendEncryptedPayload(
      hexToBytes(contactNodeIdHex),
      proto.MessageTypeV3.MTV3_FREE_BUSY_REQUEST,
      req.writeToBuffer(),
    );

    _log.info('Sent FREE_BUSY_REQUEST to ${contactNodeIdHex.substring(0, 8)} '
        '(${DateTime.fromMillisecondsSinceEpoch(queryStart)} – '
        '${DateTime.fromMillisecondsSinceEpoch(queryEnd)})');
    return requestIdHex;
  }

  // ── V3 Application Frame Handlers ────────────────────────────────

  void handleCalendarInviteV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final invite = proto.CalendarInviteMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final eventIdHex = bytesToHex(Uint8List.fromList(invite.eventId));

      final event = CalendarEvent(
        eventId: eventIdHex,
        identityId: _ctx.identity.userIdHex,
        title: invite.title,
        description: invite.description.isNotEmpty ? invite.description : null,
        location: invite.location.isNotEmpty ? invite.location : null,
        startTime: invite.startTime.toInt(),
        endTime: invite.endTime.toInt(),
        allDay: invite.allDay,
        timeZone: invite.timeZone.isNotEmpty ? invite.timeZone : 'UTC',
        recurrenceRule: invite.recurrenceRule.isNotEmpty ? invite.recurrenceRule : null,
        hasCall: invite.hasCall,
        groupId: invite.groupId.isNotEmpty ? bytesToHex(Uint8List.fromList(invite.groupId)) : null,
        category: EventCategory.values[invite.category.value.clamp(0, EventCategory.values.length - 1)],
        reminders: invite.reminders.map((r) => r.minutesBefore).toList(),
        createdBy: senderHex,
      );
      calendarManager.createEvent(event);

      if (event.groupId != null && _ctx.conversations.containsKey(event.groupId)) {
        final senderName = _ctx.contacts[senderHex]?.displayName ?? invite.createdByName;
        _ctx.addMessageToConversation(event.groupId!, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: event.groupId!,
          senderNodeIdHex: '',
          text: '$senderName hat einen Termin erstellt: ${event.title}',
          timestamp: DateTime.now(),
          type: UiMessageType.calendarInvite,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      _log.info('Received calendar invite: ${event.title} from ${senderHex.substring(0, 8)}');
      onCalendarInviteReceived?.call(senderHex, eventIdHex, event.title);
      _ctx.notifyStateChanged();
    } catch (e) {
      _log.warn('handleCalendarInviteV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void handleCalendarRsvpV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final rsvp = proto.CalendarRsvpMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final eventIdHex = bytesToHex(Uint8List.fromList(rsvp.eventId));

      final status = RsvpStatus.values[rsvp.response.value.clamp(0, RsvpStatus.values.length - 1)];
      calendarManager.setRsvp(eventIdHex, senderHex, status);

      final event = calendarManager.events[eventIdHex];
      if (event?.groupId != null && _ctx.conversations.containsKey(event!.groupId)) {
        final senderName = _ctx.contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        final statusText = switch (status) {
          RsvpStatus.accepted => 'hat zugesagt',
          RsvpStatus.declined => 'hat abgesagt',
          RsvpStatus.tentative => 'hat vorläufig zugesagt',
          RsvpStatus.proposeNewTime => 'schlägt eine andere Zeit vor',
        };
        _ctx.addMessageToConversation(event.groupId!, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: event.groupId!,
          senderNodeIdHex: '',
          text: '$senderName $statusText',
          timestamp: DateTime.now(),
          type: UiMessageType.calendarRsvp,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      _log.info('RSVP for $eventIdHex from ${senderHex.substring(0, 8)}: $status');
      onCalendarRsvpReceived?.call(eventIdHex, senderHex, status);
      _ctx.notifyStateChanged();
    } catch (e) {
      _log.warn('handleCalendarRsvpV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void handleCalendarUpdateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final update = proto.CalendarUpdateMsg.fromBuffer(frame.payload);
      final eventIdHex = bytesToHex(Uint8List.fromList(update.eventId));

      final event = calendarManager.events[eventIdHex];
      if (event == null) {
        _log.debug('CALENDAR_UPDATE for unknown event $eventIdHex');
        return;
      }

      calendarManager.updateEvent(eventIdHex,
        title: update.title.isNotEmpty ? update.title : null,
        description: update.description.isNotEmpty ? update.description : null,
        location: update.location.isNotEmpty ? update.location : null,
        startTime: update.startTime.toInt() > 0 ? update.startTime.toInt() : null,
        endTime: update.endTime.toInt() > 0 ? update.endTime.toInt() : null,
        allDay: update.allDay,
        hasCall: update.hasCall,
        cancelled: update.cancelled,
        reminders: update.reminders.isNotEmpty
            ? update.reminders.map((r) => r.minutesBefore).toList()
            : null,
      );

      if (event.groupId != null && _ctx.conversations.containsKey(event.groupId)) {
        final action = update.cancelled ? 'hat den Termin abgesagt' : 'hat den Termin geändert';
        final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
        final senderName = _ctx.contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        _ctx.addMessageToConversation(event.groupId!, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: event.groupId!,
          senderNodeIdHex: '',
          text: '$senderName $action: ${event.title}',
          timestamp: DateTime.now(),
          type: UiMessageType.calendarUpdate,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      _log.info('Calendar event updated: $eventIdHex');
      onCalendarEventUpdated?.call(eventIdHex);
      _ctx.notifyStateChanged();
    } catch (e) {
      _log.warn('handleCalendarUpdateV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void handleCalendarDeleteV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final del = proto.CalendarDeleteMsg.fromBuffer(frame.payload);
      final eventIdHex = bytesToHex(Uint8List.fromList(del.eventId));

      final event = calendarManager.events[eventIdHex];
      if (event != null && event.groupId != null) {
        final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
        final senderName = _ctx.contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        _ctx.addMessageToConversation(event.groupId!, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: event.groupId!,
          senderNodeIdHex: '',
          text: '$senderName hat den Termin gelöscht: ${event.title}',
          timestamp: DateTime.now(),
          type: UiMessageType.calendarDelete,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      calendarManager.deleteEvent(eventIdHex);
      _log.info('Calendar event deleted: $eventIdHex');
      onCalendarEventUpdated?.call(eventIdHex);
      _ctx.notifyStateChanged();
    } catch (e) {
      _log.warn('handleCalendarDeleteV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  Future<void> handleFreeBusyRequestV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) async {
    try {
      final req = proto.FreeBusyRequestMsg.fromBuffer(frame.payload);
      final querierHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final requestIdBytes = Uint8List.fromList(req.requestId);

      if (_ctx.contacts[querierHex]?.status != 'accepted') {
        _log.debug('FREE_BUSY_REQUEST from non-contact ${querierHex.substring(0, 8)}, ignoring');
        return;
      }

      final blocks = calendarManager.generateFreeBusyResponse(
        queryStart: req.queryStart.toInt(),
        queryEnd: req.queryEnd.toInt(),
        querierNodeIdHex: querierHex,
      );

      final response = proto.FreeBusyResponseMsg()
        ..requestId = requestIdBytes;
      for (final block in blocks) {
        response.blocks.add(proto.FreeBusyBlock()
          ..start = Int64(block.start)
          ..end = Int64(block.end)
          ..level = proto.FreeBusyLevel.valueOf(block.level.index) ?? proto.FreeBusyLevel.FB_TIME_ONLY
          ..title = block.title ?? ''
          ..location = block.location ?? '');
      }

      await _ctx.sendEncryptedPayload(
        Uint8List.fromList(frame.senderUserId),
        proto.MessageTypeV3.MTV3_FREE_BUSY_RESPONSE,
        response.writeToBuffer(),
      );

      _log.info('Sent FREE_BUSY_RESPONSE to ${querierHex.substring(0, 8)} '
          '(${blocks.length} blocks)');
    } catch (e) {
      _log.warn('handleFreeBusyRequestV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void handleFreeBusyResponseV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final resp = proto.FreeBusyResponseMsg.fromBuffer(frame.payload);
      final requestIdHex = bytesToHex(Uint8List.fromList(resp.requestId));

      final blocks = <FreeBusyBlockResult>[];
      for (final b in resp.blocks) {
        blocks.add(FreeBusyBlockResult(
          start: b.start.toInt(),
          end: b.end.toInt(),
          level: FreeBusyLevel.values[b.level.value.clamp(0, FreeBusyLevel.values.length - 1)],
          title: b.title.isNotEmpty ? b.title : null,
          location: b.location.isNotEmpty ? b.location : null,
        ));
      }

      freeBusyResults.putIfAbsent(requestIdHex, () => []).addAll(blocks);

      final cb = freeBusyCallbacks[requestIdHex];
      if (cb != null) {
        cb(freeBusyResults[requestIdHex]!);
      }

      _log.info('Received FREE_BUSY_RESPONSE for $requestIdHex '
          '(${blocks.length} blocks)');
    } catch (e) {
      _log.warn('handleFreeBusyResponseV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────

  static String _hexShort(Uint8List bytes) {
    final n = bytes.length < 4 ? bytes.length : 4;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
