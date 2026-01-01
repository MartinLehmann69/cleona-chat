package chat.cleona.cleona

import android.content.Context

// The words of the system notifications in the language chosen in the app
// (S410-F, working rule 7). They come from `translations.dart` over
// `chat.cleona/notification` (`setNotificationTexts`, built by
// `androidNotificationTexts` in lib/core/platform/android_notification_texts.dart)
// and are stored, because two of them are shown when Dart cannot be asked:
// the "paused" line of the service notice (Dart's heartbeat is stale) and the
// service notice and channels before the Flutter engine runs.
object NotificationTexts {
    private const val PREFS = "cleona_notification_texts"

    // Only for the moment before Dart has EVER handed its texts over (the
    // very first start of an install, before the engine runs). Defence in
    // depth like the runtime fallback of `AppLocale`, not the expected path:
    // Dart replaces every one of them on its first adoption of the language,
    // and the stored texts outlive the process.
    private val BOOTSTRAP = mapOf(
        "unreadSummary" to "Unread: {count}",
        "channelMessagesName" to "Messages",
        "channelMessagesDesc" to "Notifications for new messages",
        "channelCallsName" to "Calls",
        "channelCallsDesc" to "Incoming calls",
        "channelServiceDesc" to "Connection status",
        "servicePaused" to "Paused — open Cleona to continue",
        "serviceStarting" to "Looking for neighbours",
        "incomingCall" to "Incoming call...",
        "unknownCaller" to "Unknown contact",
    )

    fun store(context: Context, texts: Map<String, String>) {
        val edit = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        for ((key, value) in texts) edit.putString(key, value)
        edit.apply()
    }

    fun get(context: Context, key: String): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(key, null)
            ?: BOOTSTRAP[key] ?: key
}
