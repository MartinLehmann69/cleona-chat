/// What a system notification shows (§22.8 "What a system notification
/// shows", "A notification without content"; D-49, D-123 items 8 and 9).
///
/// ── THE SETTING ───────────────────────────────────────────────────────────
///
/// "A notification without content": one setting, device-wide and off by
/// default. It lies where the master mute lies — one row of
/// `DeviceStore.areaSettings` in `device.db` (§4.5.2 "device-wide
/// settings"), the same for every identity of the device.
///
/// With it on, every message notification shows only that a message arrived,
/// every invitation to a group or channel only that an invitation arrived,
/// and every reminder only that a reminder is due: the title is the product
/// name, the text one existing key (`notification_new_message`,
/// `invitation_label`, `notification_reminder_due`). A missed call is an
/// ordinary message (D-45) and is reduced with it. The ringing of a call is
/// not handed to this module at all (`CallService`, its own platform way)
/// and keeps the caller's name, as §22.8 says.
///
/// ── THE WORDS ─────────────────────────────────────────────────────────────
///
/// Every text is formed in Dart from `translations.dart` in the language of
/// the user interface (§24.1: no platform resource files). The iOS background
/// fetch hands the finished titles and texts to Swift, which only shows them.
///
/// Nothing here runs on a timer, nothing is sent, nothing is logged.
library;

import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/storage/device_store.dart';

/// The key of the row in `DeviceStore.areaSettings`.
const String kNotificationWithoutContentSettingKey =
    'notification_without_content';

/// Reads the setting; no database or no row means off (the default, D-49).
bool notificationWithoutContentRead(DeviceStore? store) {
  try {
    final row = store?.entry(
        DeviceStore.areaSettings, kNotificationWithoutContentSettingKey);
    return row?['on'] == true;
  } on Object {
    return false;
  }
}

/// Stores the setting. Returns false when there is no database to write to
/// (no master seed yet).
bool notificationWithoutContentWrite(DeviceStore? store, bool on) {
  if (store == null) return false;
  store.putEntry(DeviceStore.areaSettings,
      kNotificationWithoutContentSettingKey, {'on': on});
  return true;
}

/// The kinds of notification the setting reduces. The ringing of a call is
/// deliberately not one of them (§22.8 "A call keeps showing the caller's
/// name").
enum NotificationKind { message, invitation, reminder }

/// The name a notification without content carries as its title — the same
/// product name the desktop notifiers register (`service_daemon.dart`).
String notificationProductName([NetworkChannel? channel]) =>
    (channel ?? activeNetworkChannel) == NetworkChannel.beta
        ? 'Cleona Beta'
        : 'Cleona Chat';

/// The title and text handed to the platform's notification service.
///
/// [title] and [body] are what the notification shows without the setting;
/// with [withoutContent] both are replaced, and nothing of them remains.
({String title, String body}) notificationShown({
  required NotificationKind kind,
  required String title,
  required String body,
  required bool withoutContent,
  required String Function(String key) words,
  String? productName,
}) {
  if (!withoutContent) return (title: title, body: body);
  final key = switch (kind) {
    NotificationKind.message => 'notification_new_message',
    NotificationKind.invitation => 'invitation_label',
    NotificationKind.reminder => 'notification_reminder_due',
  };
  return (title: productName ?? notificationProductName(), body: words(key));
}

/// The text of a media message's notification: its kind in the words of the
/// interface (§22.8 "for media and files, the kind or the file name in place
/// of the text"). [filename] is shown for a file when given.
String mediaNotificationText(
  UiMessageType type,
  String? mimeType,
  String Function(String key) words, {
  String? filename,
}) {
  switch (type) {
    case UiMessageType.image:
    case UiMessageType.gif:
      return '📷 ${words('image_fallback')}';
    case UiMessageType.video:
      return '🎬 ${words('clipboard_video')}';
    case UiMessageType.voiceMessage:
      return '🎤 ${words('voice_message')}';
    default:
      if (mimeType != null && mimeType.startsWith('audio/')) {
        return '🎵 ${words('clipboard_audio')}';
      }
      if (filename != null && filename.isNotEmpty) return '📎 $filename';
      return '📎 ${words('file_fallback')}';
  }
}

/// The text of the one batch notification of the first collection after a
/// start (§22.8 "Bundling rule", D-124): [count] new messages in
/// [conversations] conversations. The title is the product name. One
/// message keeps the ordinary `notification_new_message`; both batch texts
/// are worded so they hold for every number from 2 upwards (S422
/// translations, D-124).
String firstCollectionBatchText(
    int count, int conversations, String Function(String key) words) {
  if (count <= 1) return words('notification_new_message');
  if (conversations <= 1) {
    return words('notification_batch_one_conversation')
        .replaceAll('{count}', '$count');
  }
  return words('notification_batch_conversations')
      .replaceAll('{count}', '$count')
      .replaceAll('{conversations}', '$conversations');
}

/// The identifier of the batch notification: one for the whole first
/// collection — a later batch (the next start) replaces it. Not a
/// conversation, so reading one conversation leaves it; the badge at 0
/// removes it with every other (Android `updateBadgeCount`, iOS
/// `applyBadge`).
const String kFirstCollectionNotificationId = 'first_collection';

// ── WHO RINGS (§22.8, D-125 (1)) ──────────────────────────────────────────
//
// "On Android and iOS a system notification alone carries sound and
// vibration while the app is in the background; in the foreground only the
// app plays them. On the desktop the notification is silent and Cleona
// plays its own sound (D-116)." Never both ways for one notification. Quiet
// hours, the master mute and L1–L4 have decided before either way is asked
// (`_shouldSuppressNotification`); this decides only WHICH way gives the
// signal.
//
// The one exception, Android with a mixed setting (S422, coordinator's rule
// on D-125): a channel carries sound AND vibration, a notification can only
// be silenced as a whole (`setSilent`), and further channels are not built.
// So with exactly one of sound and vibration off, the notification is silent
// and the app — kept running by the foreground service (§12.6) — gives in
// the background just what is on. Every setting holds, no double signal.

/// The platform as far as notifications go.
enum NotificationPlatform { android, ios, desktop }

/// Who gives sound and vibration for one notification (§22.8, D-125 (1)).
class NotificationSignal {
  /// The app plays its own sound.
  final bool appSound;

  /// The app vibrates itself.
  final bool appVibration;

  /// The system notification carries sound (and with it the platform's
  /// vibration); otherwise it is posted silent.
  final bool system;

  const NotificationSignal(
      {required this.appSound,
      required this.appVibration,
      required this.system});

  @override
  String toString() =>
      'NotificationSignal(appSound: $appSound, appVibration: $appVibration, '
      'system: $system)';
}

/// The rule of §22.8 after L5 (D-125 (1)) for one notification:
/// - desktop: the app, always; the notification is silent (D-116);
/// - Android and iOS in the foreground ([resumed]): the app only;
/// - iOS in the background: the notification only, ringing with the
///   message sound on (the app is suspended there and cannot play);
/// - Android in the background: the notification only when sound AND
///   vibration are on; with one of them off the notification is silent and
///   the app gives what is on (the exception above).
/// "Sound on" is the switch the app's own sound obeys
/// (`playMessageSound`: sound and message sound), "vibration on" the one
/// `vibrate` obeys.
NotificationSignal notificationSignal(NotificationSettings settings,
    {required NotificationPlatform platform, required bool resumed}) {
  final sound = settings.soundEnabled && settings.messageSoundEnabled;
  final vibration = settings.vibrationEnabled;
  if (platform == NotificationPlatform.desktop || resumed) {
    return NotificationSignal(
        appSound: sound, appVibration: vibration, system: false);
  }
  if (platform == NotificationPlatform.ios) {
    return NotificationSignal(
        appSound: false, appVibration: false, system: sound);
  }
  if (sound && vibration) {
    return const NotificationSignal(
        appSound: false, appVibration: false, system: true);
  }
  return NotificationSignal(
      appSound: sound, appVibration: vibration, system: false);
}

/// The sound of a system notification of the iOS app, as a file name in
/// `Library/Sounds` (where `UNNotificationSound(named:)` looks,
/// https://developer.apple.com/documentation/usernotifications/unnotificationsound;
/// copied there at launch, `BackgroundFetchHandler.installNotificationSounds`),
/// or `null` for a silent notification — whenever the system notification
/// does not give the signal ([bySystem], `notificationSoundBySystem`:
/// app in the foreground, or message sound off). [soundName] is the sound
/// chosen for the conversation (`notificationSoundName`, D-125 (1a): it also rings in
/// the notification on iOS); without one the standard message sound. Always
/// the same file the app plays in the foreground (`playMessageSound`), an
/// unknown name included (`Ringtone.fromName`).
String? iosNotificationSoundName(
    {required bool bySystem, String? soundName}) {
  if (!bySystem) return null;
  return NotificationSoundService.iosSoundFile(soundName == null
      ? NotificationSoundService.messageSoundFile
      : Ringtone.fromName(soundName).filename);
}

// Until S422 here stood `FetchedNotification`, `fetchedNotification` and
// `messageNotificationText`: the iOS background fetch formed its own
// notification per conversation for Swift to post. Since D-124 the services
// form and post every notification themselves (`_postSystemNotification`),
// also at the cold start of the wake-up; the native side only sets the badge.
