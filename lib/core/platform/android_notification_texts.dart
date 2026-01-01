// The words the Android platform side shows in system notifications — in the
// language chosen in the app (working rule 7, §24).
//
// Until S410-F `MainActivity.kt` and `CleonaForegroundService.kt` carried
// them as German literals: the unread summary ("… ungelesene Nachrichten"),
// the incoming-call line, the "paused" line of the service notice and the
// names/descriptions of the three notification channels (visible in the
// system settings). In each of the 34 languages the same German words.
//
// `main.dart` hands this map over `chat.cleona/notification`
// (`setNotificationTexts`) when the app language is adopted and whenever it
// changes. The platform side stores it, because two of the texts are shown
// when Dart cannot be asked: the "paused" line (Dart's heartbeat is stale)
// and the service notice before the Flutter engine runs.
//
// Pure Dart: no channel is called here.

/// The platform key → the key in `translations.dart`. The platform keys are
/// the ones `NotificationTexts.kt` reads.
const Map<String, String> kAndroidNotificationTextKeys = {
  // "{count}" is replaced on the platform side; label + number, so no
  // plural form is needed (the i18n has none).
  'unreadSummary': 'android_notify_unread_summary',
  'channelMessagesName': 'android_channel_messages_name',
  'channelMessagesDesc': 'android_channel_messages_desc',
  'channelCallsName': 'android_channel_calls_name',
  'channelCallsDesc': 'android_channel_calls_desc',
  'channelServiceDesc': 'android_channel_service_desc',
  'servicePaused': 'android_service_paused',
  // The first line of the service notice, before Dart reports a state:
  // the state a start begins in (§22.7).
  'serviceStarting': 'readiness_searching',
  'incomingCall': 'call_incoming',
  'unknownCaller': 'qr_unknown_contact',
};

/// The texts in the language [translate] answers in.
Map<String, String> androidNotificationTexts(
        String Function(String key) translate) =>
    {
      for (final e in kAndroidNotificationTextKeys.entries)
        e.key: translate(e.value),
    };
