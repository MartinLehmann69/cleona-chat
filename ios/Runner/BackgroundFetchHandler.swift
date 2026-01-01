import Foundation
import UIKit
import BackgroundTasks
import UserNotifications
import AudioToolbox
import Flutter

/// iOS Background Fetch handler for Cleona P2P messenger (Architecture S12.5).
///
/// Uses BGTaskScheduler with two task types to periodically wake the app and
/// retrieve pending messages from the P2P network:
/// - BGAppRefreshTask (`chat.cleona.cleona.refresh`): ~30s window, frequent
/// - BGProcessingTask (`chat.cleona.cleona.processing`): minutes-long window, less frequent
///
/// All heavy lifting (node startup, peer contact, S&F retrieval, Reed-Solomon
/// fragment fetch, decryption) happens on the Dart side via MethodChannel.
/// This Swift class orchestrates the OS integration: task registration,
/// scheduling, expiration handling, and local notification posting.
///
/// NO APNs, NO Firebase, NO push -- pure OS-controlled pull.
class BackgroundFetchHandler {

    static let shared = BackgroundFetchHandler()
    static let refreshIdentifier = "chat.cleona.cleona.refresh"
    static let processingIdentifier = "chat.cleona.cleona.processing"

    var methodChannel: FlutterMethodChannel?

    private var isFetching = false

    private init() {}

    // MARK: - Task Registration

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundFetchHandler.refreshIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundFetch(task: refreshTask, taskType: "refresh")
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundFetchHandler.processingIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self, let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundFetch(task: processingTask, taskType: "processing")
        }

        NSLog("[BackgroundFetch] Registered tasks: refresh + processing")
    }

    // MARK: - Scheduling

    /// Schedule both background task types. Called after each completed task
    /// and when the app transitions to background.
    func scheduleBothTasks() {
        scheduleRefreshTask()
        scheduleProcessingTask()
    }

    private func scheduleRefreshTask() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundFetchHandler.refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[BackgroundFetch] Scheduled refresh (earliest: 1 min)")
        } catch {
            NSLog("[BackgroundFetch] Failed to schedule refresh: \(error.localizedDescription)")
        }
    }

    private func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: BackgroundFetchHandler.processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[BackgroundFetch] Scheduled processing")
        } catch {
            NSLog("[BackgroundFetch] Failed to schedule processing: \(error.localizedDescription)")
        }
    }

    // `cancelPendingTasks()` was removed with S370 -- its only
    // way of being reached was `AppDelegate case "cancelBackgroundFetch"`, and
    // its Dart counterpart had zero callers. Caller and
    // callee fell together; the rationale is in
    // `lib/core/platform/ios_background_fetch.dart`.

    // MARK: - Task Execution

    /// Handle a background fetch task (either refresh or processing).
    /// Both execute the same 9-step wakeup chain from S12.5, but the
    /// processing task passes taskType="processing" to Dart so it can
    /// extend the peer-contact budget from 3 to 10.
    // -- ONE COMPLETION PER TASK (F-8, S370) -----------------------------
    //
    // FINDING: `setTaskCompleted` could run TWICE on the same `BGTask`.
    // The `expirationHandler` below completed with `false`, but did NOT
    // abort the running Dart call; the Dart body waits a fixed
    // 20 s (refresh) or 120 s (processing)
    // (`lib/core/platform/ios_background_fetch.dart`, `Future.delayed`) and
    // then completed a second time.
    //
    // CAN THIS HAPPEN IN OPERATION? From code reading yes, and for the
    // refresh run even regularly: the window of a `BGAppRefreshTask`
    // is ~30 s, the Dart body uses 20 s of it just
    // waiting, plus loading identities, starting the node (up to three
    // bind attempts with 2 s pause each), starting one service per identity
    // and saving at the end. For the `processing` run it hits the case that
    // the operating system aborts early (battery, temperature, user switches
    // app).
    //
    // The second effect was just as silent: the `defer` block called
    // `scheduleBothTasks()` a second time, so there were duplicate
    // requests in the queue.
    //
    // NOT MEASURED: what exactly iOS does on the second completion (Apple
    // describes exactly one call; depending on the version a log entry
    // or an assertion violation). Because the outcome is not known,
    // it is not risked -- exactly one completes.
    //
    // NOT FIXED, and explicitly open: the Dart body keeps running after
    // expiry and holds the UDP port for up to 120 s. Aborting it
    // needs a path Swift -> Dart in the middle of the run; this
    // branch does not have it. The guard, however, is the only completion
    // here: nothing is reported twice and nothing is scheduled twice.
    private func handleBackgroundFetch(task: BGTask, taskType: String) {
        NSLog("[BackgroundFetch] Task started (type: \(taskType))")

        guard !isFetching else {
            NSLog("[BackgroundFetch] Already fetching, completing task")
            task.setTaskCompleted(success: true)
            scheduleBothTasks()
            return
        }
        isFetching = true

        // One-shot completion. The expiration handler runs on an arbitrary
        // queue, the Dart answer on the main queue --
        // hence a lock and not a mere Bool.
        let completionLock = NSLock()
        var alreadyCompleted = false
        let complete: (Bool, String) -> Void = { [weak self] success, reason in
            completionLock.lock()
            if alreadyCompleted {
                completionLock.unlock()
                NSLog("[BackgroundFetch] Second completion dropped (\(taskType), \(reason))")
                return
            }
            alreadyCompleted = true
            completionLock.unlock()
            NSLog("[BackgroundFetch] Completion (\(taskType), \(reason)): success=\(success)")
            task.setTaskCompleted(success: success)
            self?.isFetching = false
            self?.scheduleBothTasks()
        }

        task.expirationHandler = {
            NSLog("[BackgroundFetch] Task expired by OS (type: \(taskType))")
            complete(false, "expired by the operating system")
        }

        guard let channel = methodChannel else {
            NSLog("[BackgroundFetch] No MethodChannel available -- engine not running?")
            complete(false, "no MethodChannel")
            return
        }

        DispatchQueue.main.async {
            channel.invokeMethod("performBackgroundFetch", arguments: ["taskType": taskType]) { [weak self] result in
                guard let self = self else {
                    complete(false, "AppDelegate gone")
                    return
                }

                if let error = result as? FlutterError {
                    NSLog("[BackgroundFetch] Dart error: \(error.code) - \(error.message ?? "")")
                    complete(false, "Dart error")
                    return
                }

                guard let response = result as? [String: Any] else {
                    NSLog("[BackgroundFetch] Unexpected response type")
                    complete(false, "unexpected response type")
                    return
                }

                // The number of conversations with new unread (Dart
                // `_result`), for this line only.
                let messageCount = response["messageCount"] as? Int ?? 0

                NSLog("[BackgroundFetch] Completed (\(taskType)): \(messageCount) conversation(s) with new unread")

                // D-124 (S422 N-4): the Dart services posted every
                // notification of this run themselves (`postNotification`
                // below, from `_postSystemNotification` — the first
                // collection as one batch); the native side forms nothing
                // and only sets the badge — S420 IB-1: the unread sum over
                // every identity, not the number of this run. Without a
                // `badgeCount` (no identity) the badge stays as it is.
                if let badgeCount = response["badgeCount"] as? Int {
                    self.applyBadge(count: badgeCount)
                }

                complete(true, "Dart done")
            }
        }
    }

    // MARK: - Local Notifications

    func requestNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                NSLog("[BackgroundFetch] Notification auth error: \(error.localizedDescription)")
            }
            NSLog("[BackgroundFetch] Notification auth granted: \(granted)")
        }
    }

    /// The `userInfo` key that marks a notification the running app's Dart
    /// service handed over (`postNotification`). `AppDelegate`'s
    /// `willPresent` shows only these while the app is in the foreground.
    static let postedByDartKey = "cleona_posted_by_dart"

    /// One identifier per conversation: a later notification of the same
    /// conversation replaces the earlier one (Android: `conversationId.hashCode()`,
    /// `MainActivity.kt` `postMessageNotification`).
    static func notificationIdentifier(_ conversationId: String) -> String {
        return "cleona_msg_\(conversationId)"
    }

    /// Hands the title and text the Dart service formed (`_postSystemNotification`,
    /// §22.8 — behind its gates, reduced when "notification without content"
    /// is on) to the system (S422 N-1). Neither is logged. `soundName` is the
    /// `.caf` in `Library/Sounds` the notification rings with
    /// ([installNotificationSounds]), `nil` for a silent one — while the app
    /// is in the foreground it plays itself, and with the message sound off
    /// nothing rings (§22.8, D-125; Dart `iosNotificationSoundName`). The
    /// badge is not touched here; it follows `updateBadge`. `identity` (the
    /// posting identity's nodeIdHex) rides in `userInfo` next to
    /// `conversationId`, so a tap opens the conversation in it (§22.8,
    /// D-125 (3)).
    func postNotification(title: String, body: String, conversationId: String, identity: String, soundName: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = soundName.map { UNNotificationSound(named: UNNotificationSoundName($0)) }
        content.threadIdentifier = conversationId
        content.userInfo = [
            BackgroundFetchHandler.postedByDartKey: true,
            "conversationId": conversationId,
            "identity": identity,
        ]
        let request = UNNotificationRequest(
            identifier: BackgroundFetchHandler.notificationIdentifier(conversationId),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[Notification] post failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sounds (S422 T-1, §22.8, D-125 (1a))

    /// Maps a Flutter asset path (`assets/sounds/message.caf`) to its key in
    /// the main bundle (`FlutterPluginRegistrar.lookupKey(forAsset:)`; the
    /// Flutter assets lie in `App.framework`, not at the top of the bundle,
    /// https://docs.flutter.dev/ui/assets/assets-and-images#loading-flutter-assets-in-ios).
    private var soundAssetKey: ((String) -> String)?

    /// One system sound per asset, created on first use.
    private var systemSounds: [String: SystemSoundID] = [:]

    /// The bundle path of a Flutter asset, or nil.
    private func soundPath(_ asset: String) -> String? {
        guard let key = soundAssetKey?(asset) else { return nil }
        return Bundle.main.path(forResource: key, ofType: nil)
    }

    /// Copies every `.caf` of `assets/sounds/` into `Library/Sounds/` —
    /// where `UNNotificationSound(named:)` looks for a sound outside the
    /// main bundle's top level
    /// (https://developer.apple.com/documentation/usernotifications/unnotificationsound).
    /// Called at every launch, the background launch included; a file is
    /// written only when it is missing or differs (an update brings new
    /// sounds). Off the main thread: it reads about half a megabyte.
    func installNotificationSounds(assetKey: @escaping (String) -> String) {
        soundAssetKey = assetKey
        guard let probe = soundPath("assets/sounds/message.caf") else {
            NSLog("[Notification] sounds not found in the bundle")
            return
        }
        let source = URL(fileURLWithPath: (probe as NSString).deletingLastPathComponent)
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            do {
                let library = try fm.url(for: .libraryDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true)
                let target = library.appendingPathComponent("Sounds", isDirectory: true)
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                for name in try fm.contentsOfDirectory(atPath: source.path)
                where name.hasSuffix(".caf") {
                    let data = try Data(contentsOf: source.appendingPathComponent(name))
                    let destination = target.appendingPathComponent(name)
                    if (try? Data(contentsOf: destination)) == data { continue }
                    try data.write(to: destination, options: .atomic)
                }
            } catch {
                NSLog("[Notification] sounds not installed: \(error.localizedDescription)")
            }
        }
    }

    /// Plays a `.caf` asset once as a system sound — the app's own sound in
    /// the foreground (Dart `_playOnce`). A system sound follows the
    /// ring/silent switch and takes IMA4 in caf, up to 30 s
    /// (https://developer.apple.com/documentation/audiotoolbox/1405248-audioservicesplaysystemsound).
    func playSound(asset: String) {
        if let id = systemSounds[asset] {
            AudioServicesPlaySystemSound(id)
            return
        }
        guard let path = soundPath(asset) else {
            NSLog("[Notification] sound not found: \(asset)")
            return
        }
        var id: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(URL(fileURLWithPath: path) as CFURL, &id)
        guard status == kAudioServicesNoError else {
            NSLog("[Notification] sound not playable: \(asset) (\(status))")
            return
        }
        systemSounds[asset] = id
        AudioServicesPlaySystemSound(id)
    }

    // MARK: - Scheduled reminders (§18.1.6, S422 D-125 (2))

    /// Prefix of every calendar reminder in the system's schedule
    /// (§18.1.6, S422 D-125 (2)); the rest of the identifier is the Dart
    /// `CalendarWiring.scheduledId`.
    static let reminderPrefix = "cleona_reminder_"

    /// At most this many scheduled local notifications are kept per app;
    /// the system drops the rest (https://developer.apple.com/forums/thread/811171).
    /// Dart already hands over only the 64 soonest; this is the guard.
    static let maxScheduledReminders = 64

    /// Replaces the scheduled reminders with [reminders] — the full set the
    /// Dart wiring computed (`id`, `title`, `body`, `fireAtMs`; title and
    /// body already reduced when "notification without content" is on).
    /// Each fires once at its time, while the app is suspended too; it only
    /// shows, it does not wake the app (D-125 (2)). Neither text is logged.
    func scheduleReminders(_ reminders: [[String: Any]]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map { $0.identifier }
                .filter { $0.hasPrefix(BackgroundFetchHandler.reminderPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            let now = Date()
            var added = 0
            for item in reminders.prefix(BackgroundFetchHandler.maxScheduledReminders) {
                guard let id = item["id"] as? String,
                      let fireAtMs = (item["fireAtMs"] as? NSNumber)?.doubleValue else { continue }
                let fireAt = Date(timeIntervalSince1970: fireAtMs / 1000.0)
                if fireAt <= now { continue }
                let content = UNMutableNotificationContent()
                content.title = item["title"] as? String ?? ""
                content.body = item["body"] as? String ?? ""
                // A reminder rings and vibrates (§18.1.6); quiet hours do not
                // apply to it (§22.8). Cleona's standard message sound, the
                // one the running app plays for a reminder (D-125 (1a)),
                // from `Library/Sounds` (installNotificationSounds).
                content.sound = UNNotificationSound(
                    named: UNNotificationSoundName("message.caf"))
                content.threadIdentifier = id
                content.userInfo = [
                    BackgroundFetchHandler.postedByDartKey: true,
                    "reminderId": id,
                ]
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: fireAt)
                let request = UNNotificationRequest(
                    identifier: BackgroundFetchHandler.reminderPrefix + id,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                center.add(request) { error in
                    if let error = error {
                        NSLog("[Reminder] schedule failed: \(error.localizedDescription)")
                    }
                }
                added += 1
            }
            NSLog("[Reminder] scheduled ahead: \(added) (withdrawn \(stale.count))")
        }
    }

    /// Withdraws one scheduled reminder — the running app shows it itself.
    func withdrawReminder(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [BackgroundFetchHandler.reminderPrefix + id])
    }

    /// Removes the delivered notification of a read conversation (the
    /// counterpart of Android's `cancelNotification`).
    func cancelNotification(conversationId: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [BackgroundFetchHandler.notificationIdentifier(conversationId)])
    }

    /// The app icon badge follows the unread sum over every identity
    /// (owner requirement S410 E1: a badge only while something is unread;
    /// S420 IB-1). At 0 every delivered Cleona notification goes too — the
    /// same rule as Android's `updateBadgeCount`. Called by the
    /// `chat.cleona/notification` channel (`AppDelegate.swift`).
    ///
    /// Apple: `setBadgeCount(_:withCompletionHandler:)` exists from iOS 16.0
    /// (https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setbadgecount(_:withcompletionhandler:));
    /// below it `UIApplication.applicationIconBadgeNumber`, set on the main
    /// thread (https://developer.apple.com/documentation/uikit/uiapplication/applicationiconbadgenumber,
    /// deprecated in iOS 17 in favour of `setBadgeCount`). The deployment
    /// target is 15.5 (`project.pbxproj` `IPHONEOS_DEPLOYMENT_TARGET`,
    /// `Podfile` `platform :ios, '15.5'`), hence the `#available` branch.
    /// `removeAllDeliveredNotifications()` removes this app's delivered
    /// notifications from Notification Center
    /// (https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removealldeliverednotifications()).
    /// Both need the `.badge` authorization asked for in
    /// [requestNotificationAuthorization]; without it the icon shows nothing.
    func applyBadge(count: Int) {
        let center = UNUserNotificationCenter.current()
        let value = max(0, count)
        if #available(iOS 16.0, *) {
            center.setBadgeCount(value) { error in
                if let error = error {
                    NSLog("[BackgroundFetch] setBadgeCount failed: \(error.localizedDescription)")
                }
            }
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = value
            }
        }
        if value == 0 {
            center.removeAllDeliveredNotifications()
        }
    }

    // `postLocalNotifications` (the wake-up's own notifications from the
    // lists `senderNames`/`previews`) is gone (D-124, S422): every
    // notification comes from the Dart services through `postNotification`.
}
