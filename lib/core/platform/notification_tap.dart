import 'package:cleona/core/service/notification_content.dart'
    show kFirstCollectionNotificationId;

/// The prefix of a reminder's notification identifier
/// (`reminder:<eventId>:<start>`, formed where the reminder service fires,
/// `calendar_wiring.dart`). A reminder is not a conversation: tapping it opens
/// the app only.
const String kReminderNotificationPrefix = 'reminder:';

/// The conversation a tapped system notification belongs to (§22.8
/// "Tapping a message notification opens its conversation; the batch
/// notification opens the app", D-125 (3)).
///
/// Pure Dart (no platform channel), so the decision what a tap opens can be
/// checked at run time (`smoke_notification_tap.dart`).
class NotificationTap {
  const NotificationTap(this.conversationId, this.identity);

  /// The identifier the service posted the notification under — for a
  /// message, invitation or missed call the conversation's id.
  final String conversationId;

  /// nodeIdHex of the identity whose service posted the notification; empty
  /// when the notification carries none (posted before this field existed).
  final String identity;

  /// What the native side stashed (`consumeNotificationTap`:
  /// `{conversationId, identity}`), or null when the tap opens the app only:
  /// nothing stashed, no identifier, the batch notification of the first
  /// collection (no single conversation, D-124), or a reminder.
  static NotificationTap? fromNative(Map<Object?, Object?>? stashed) {
    if (stashed == null) return null;
    final conversationId = stashed['conversationId'];
    if (conversationId is! String || conversationId.isEmpty) return null;
    if (!opensConversation(conversationId)) return null;
    final identity = stashed['identity'];
    return NotificationTap(conversationId, identity is String ? identity : '');
  }

  /// Whether a notification posted under [notificationId] opens a
  /// conversation when tapped.
  static bool opensConversation(String notificationId) =>
      notificationId.isNotEmpty &&
      notificationId != kFirstCollectionNotificationId &&
      !notificationId.startsWith(kReminderNotificationPrefix);
}
