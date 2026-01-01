import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/service/service_types.dart';

/// Mirrors a Cleona identity's calendar into the Android system calendar
/// (CalendarContract). Pushed one-way from Cleona → Android — the user
/// edits events in the Cleona UI, the bridge keeps a read-only mirror in
/// Samsung / Google / any Android calendar app for at-a-glance visibility.
///
/// Bidirectional sync would require a Sync Adapter (Android service
/// responding to sync requests) which is a much larger scope; we ship
/// the push-only bridge first and treat two-way as follow-up work.
class AndroidCalendarBridge {
  static const MethodChannel _channel =
      MethodChannel('chat.cleona/calendar_contract');

  final CLogger _log = CLogger.get('android-cal');

  /// Per-identity state: calendarId once the Android-side row exists.
  final Map<String, int> _calendarIds = {};

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Whether the app currently has READ_CALENDAR + WRITE_CALENDAR granted.
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('checkPermissions');
      return ok ?? false;
    } catch (e) {
      _log.warn('checkPermissions failed: $e');
      return false;
    }
  }

  /// Ask the user to grant calendar permissions. Returns after firing
  /// the request — the user's answer arrives asynchronously in the
  /// Android lifecycle; call [hasPermission] again to re-check.
  Future<void> requestPermission() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('requestPermissions');
    } catch (e) {
      _log.warn('requestPermissions failed: $e');
    }
  }

  /// Ensure the Android-side calendar row for the identity exists and
  /// return its calendarId.
  Future<int?> _ensureCalendar(String shortId, String displayName) async {
    if (!isSupported) return null;
    if (_calendarIds.containsKey(shortId)) return _calendarIds[shortId];
    try {
      final id = await _channel.invokeMethod<int>('ensureCalendar', {
        'shortId': shortId,
        'displayName': displayName,
      });
      if (id != null) _calendarIds[shortId] = id;
      return id;
    } catch (e) {
      _log.warn('ensureCalendar failed: $e');
      return null;
    }
  }

  Future<bool> _upsertEvent(int calendarId, CalendarEvent e) async {
    try {
      final ok = await _channel.invokeMethod<bool>('upsertEvent', {
        'calendarId': calendarId,
        'eventId': e.eventId,
        'title': e.title,
        'description': e.description,
        'location': e.location,
        'startMs': e.startTime,
        'endMs': e.endTime,
        'allDay': e.allDay,
        'timeZone': e.timeZone,
        'rrule': e.recurrenceRule,
      });
      return ok ?? false;
    } catch (err) {
      _log.warn('upsertEvent ${e.eventId} failed: $err');
      return false;
    }
  }

  /// Full push: ensure calendar + upsert every non-cancelled event +
  /// delete any Android-side events that are no longer in Cleona.
  Future<AndroidCalendarSyncResult> syncAll({
    required String shortId,
    required String displayName,
    required CalendarManager calendar,
  }) async {
    if (!isSupported) {
      return AndroidCalendarSyncResult.unsupported();
    }
    if (!await hasPermission()) {
      return AndroidCalendarSyncResult.needsPermission();
    }
    final calendarId = await _ensureCalendar(shortId, displayName);
    if (calendarId == null) {
      return AndroidCalendarSyncResult.failed('ensureCalendar returned null');
    }

    var upserted = 0;
    var deleted = 0;

    // Upsert all active events.
    for (final e in calendar.events.values) {
      if (e.cancelled) continue;
      if (await _upsertEvent(calendarId, e)) upserted++;
    }

    // Diff: delete any Android-side row whose Cleona eventId is no
    // longer in our calendar (or is cancelled).
    try {
      final existing = await _channel.invokeMethod<List<dynamic>>(
        'listEvents',
        {'calendarId': calendarId},
      );
      if (existing != null) {
        for (final row in existing) {
          final map = (row as Map).cast<String, dynamic>();
          final eid = map['eventId'] as String? ?? '';
          if (eid.isEmpty) continue;
          final local = calendar.events[eid];
          if (local == null || local.cancelled) {
            final ok = await _channel.invokeMethod<bool>('deleteEvent', {
              'calendarId': calendarId,
              'eventId': eid,
            });
            if (ok == true) deleted++;
          }
        }
      }
    } catch (e) {
      _log.warn('listEvents/delete-diff failed: $e');
    }

    _log.info('Android sync $shortId: upserted=$upserted, deleted=$deleted');
    return AndroidCalendarSyncResult(
      ok: true,
      upserted: upserted,
      deleted: deleted,
    );
  }

  /// Remove the Android-side calendar and all its events for the
  /// identity. Called when the user disables the bridge.
  Future<bool> removeCalendar(String shortId) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('deleteCalendar', {
        'shortId': shortId,
      });
      if (ok == true) _calendarIds.remove(shortId);
      return ok ?? false;
    } catch (e) {
      _log.warn('deleteCalendar failed: $e');
      return false;
    }
  }
}

class AndroidCalendarSyncResult {
  final bool ok;
  final bool needsPermission;
  final bool unsupported;
  final int upserted;
  final int deleted;
  final String? error;

  AndroidCalendarSyncResult({
    required this.ok,
    this.needsPermission = false,
    this.unsupported = false,
    this.upserted = 0,
    this.deleted = 0,
    this.error,
  });

  factory AndroidCalendarSyncResult.unsupported() =>
      AndroidCalendarSyncResult(ok: false, unsupported: true);

  factory AndroidCalendarSyncResult.needsPermission() =>
      AndroidCalendarSyncResult(ok: false, needsPermission: true);

  factory AndroidCalendarSyncResult.failed(String reason) =>
      AndroidCalendarSyncResult(ok: false, error: reason);

  Map<String, dynamic> toJson() => {
        'ok': ok,
        if (needsPermission) 'needsPermission': true,
        if (unsupported) 'unsupported': true,
        'upserted': upserted,
        'deleted': deleted,
        if (error != null) 'error': error,
      };
}

// Avoid taking the extra dependency on flutter/foundation.dart for a
// single constant; kIsWeb is trivial to polyfill.
// ignore: constant_identifier_names
const bool kIsWeb = bool.fromEnvironment('dart.library.js_util');
