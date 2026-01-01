// What the app icon and the message notifications show on Android — derived
// from ONE truth: the unread counts of the identities running in this process.
//
// Owner requirement (S410 E1, 29.10.2026): the app icon carries a badge only
// while there is really something unread. On Android every active
// notification in a channel that shows a badge puts the badge on the icon
// (the message channel `cleona_messages`, `setShowBadge(true)` in
// `MainActivity.kt`). So "badge only while unread" means two things:
//
//   * the number is the sum over EVERY identity in the process (one icon,
//     one number — bug #U3), and
//   * a message notification stands only while its conversation still has
//     something unread in one of the identities.
//
// Until S410-F the second half was a separate state: a notification was
// cancelled only on the paths that read a conversation or remove it. Every
// other way the count drops — the author deletes the unread message, an
// identity is deleted here or from another own device — left notifications
// (and with them the badge) behind. Now every badge update hands the platform
// the list of conversations that still have something unread, and the
// platform cancels every message notification outside that list
// (`MainActivity.kt` `updateBadgeCount`).
//
// Pure Dart: no channel is called here; `main.dart` (`_updateAndroidBadge`)
// sends [AndroidBadge.toArguments] over `chat.cleona/notification`.

import '../channels/system_channels.dart';
import '../service/service_types.dart';

/// The badge state of the whole process.
class AndroidBadge {
  /// The number on the icon: unread items over every identity.
  final int count;

  /// The conversations that still have something unread, over every
  /// identity, without duplicates. A message notification is posted under
  /// its conversation identifier (`postMessageNotification`), so these are
  /// exactly the notifications that may stay.
  final List<String> unreadConversationIds;

  const AndroidBadge(this.count, this.unreadConversationIds);

  /// [identities]: the conversations of each identity running in this
  /// process — an identity that has left the process is not in it, and
  /// neither are its conversations.
  ///
  /// The two system channels never count (§9.5; the same rule as
  /// `CleonaService._updateBadgeCount`, F10).
  factory AndroidBadge.of(Iterable<Map<String, Conversation>> identities) {
    var count = 0;
    final ids = <String>{};
    for (final conversations in identities) {
      // The key, as in `_updateBadgeCount`: it is the identifier the
      // notification was posted under.
      for (final e in conversations.entries) {
        if (e.value.unreadCount <= 0) continue;
        if (SystemChannels.isSystemChannel(e.key)) continue;
        count += e.value.unreadCount;
        ids.add(e.key);
      }
    }
    return AndroidBadge(count, ids.toList(growable: false));
  }

  /// The arguments of the platform method `updateBadge`.
  Map<String, Object> toArguments() =>
      {'count': count, 'conversationIds': unreadConversationIds};
}
