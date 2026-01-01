import Foundation
import BackgroundTasks
import UserNotifications
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
                NSLog("[BackgroundFetch] Zweite Quittung verworfen (\(taskType), \(reason))")
                return
            }
            alreadyCompleted = true
            completionLock.unlock()
            NSLog("[BackgroundFetch] Quittung (\(taskType), \(reason)): success=\(success)")
            task.setTaskCompleted(success: success)
            self?.isFetching = false
            self?.scheduleBothTasks()
        }

        task.expirationHandler = {
            NSLog("[BackgroundFetch] Task expired by OS (type: \(taskType))")
            complete(false, "vom Betriebssystem abgelaufen")
        }

        guard let channel = methodChannel else {
            NSLog("[BackgroundFetch] No MethodChannel available -- engine not running?")
            complete(false, "kein MethodChannel")
            return
        }

        DispatchQueue.main.async {
            channel.invokeMethod("performBackgroundFetch", arguments: ["taskType": taskType]) { [weak self] result in
                guard let self = self else {
                    complete(false, "AppDelegate weg")
                    return
                }

                if let error = result as? FlutterError {
                    NSLog("[BackgroundFetch] Dart error: \(error.code) - \(error.message ?? "")")
                    complete(false, "Dart-Fehler")
                    return
                }

                guard let response = result as? [String: Any] else {
                    NSLog("[BackgroundFetch] Unexpected response type")
                    complete(false, "unerwarteter Antworttyp")
                    return
                }

                let messageCount = response["messageCount"] as? Int ?? 0
                let senderNames = response["senderNames"] as? [String] ?? []
                let previews = response["previews"] as? [String] ?? []

                NSLog("[BackgroundFetch] Completed (\(taskType)): \(messageCount) messages from \(senderNames.count) senders")

                if messageCount > 0 {
                    self.postLocalNotifications(
                        messageCount: messageCount,
                        senderNames: senderNames,
                        previews: previews
                    )
                }

                complete(true, "Dart fertig")
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

    private func postLocalNotifications(messageCount: Int, senderNames: [String], previews: [String]) {
        let center = UNUserNotificationCenter.current()

        for i in 0..<min(senderNames.count, previews.count) {
            let content = UNMutableNotificationContent()
            content.title = senderNames[i]
            content.body = previews[i]
            content.sound = .default
            content.badge = NSNumber(value: messageCount)

            let request = UNNotificationRequest(
                identifier: "cleona_bg_\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                if let error = error {
                    NSLog("[BackgroundFetch] Failed to post notification: \(error.localizedDescription)")
                }
            }
        }

        if senderNames.isEmpty && messageCount > 0 {
            let content = UNMutableNotificationContent()
            content.title = "Cleona Chat"
            content.body = messageCount == 1
                ? "1 neue Nachricht"
                : "\(messageCount) neue Nachrichten"
            content.sound = .default
            content.badge = NSNumber(value: messageCount)

            let request = UNNotificationRequest(
                identifier: "cleona_bg_summary_\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                if let error = error {
                    NSLog("[BackgroundFetch] Failed to post summary notification: \(error.localizedDescription)")
                }
            }
        }

        NSLog("[BackgroundFetch] Posted \(min(senderNames.count, max(1, messageCount))) notification(s)")
    }
}
