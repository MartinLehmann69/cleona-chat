import Foundation
import BackgroundTasks
import UserNotifications
import Flutter

/// iOS Background Fetch handler for Cleona P2P messenger (Architecture S12.5).
///
/// Uses BGTaskScheduler to periodically wake the app and retrieve pending
/// messages from the P2P network. All heavy lifting (node startup, peer
/// contact, S&F retrieval, Reed-Solomon fragment fetch, decryption) happens
/// on the Dart side via MethodChannel. This Swift class orchestrates the
/// OS integration: task registration, scheduling, expiration handling, and
/// local notification posting.
///
/// NO APNs, NO Firebase, NO push -- pure OS-controlled pull.
class BackgroundFetchHandler {

    static let shared = BackgroundFetchHandler()
    static let taskIdentifier = "chat.cleona.cleona.refresh"

    /// MethodChannel to communicate with the Dart layer.
    /// Set from AppDelegate once the FlutterEngine is available.
    var methodChannel: FlutterMethodChannel?

    /// Whether a background fetch is currently in progress.
    private var isFetching = false

    private init() {}

    // MARK: - Task Registration

    /// Register the BGAppRefreshTask with the system. Must be called
    /// in `application(_:didFinishLaunchingWithOptions:)` BEFORE the
    /// app finishes launching.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundFetchHandler.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundFetch(task: refreshTask)
        }
        NSLog("[BackgroundFetch] Registered task: \(BackgroundFetchHandler.taskIdentifier)")
    }

    // MARK: - Scheduling

    /// Schedule the next background app refresh. Called after each completed
    /// task and when the app transitions to background.
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundFetchHandler.taskIdentifier)
        // Earliest: 15 minutes from now. The OS decides the actual time based
        // on user behavior, battery, network availability.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[BackgroundFetch] Scheduled next refresh (earliest: 15 min)")
        } catch {
            NSLog("[BackgroundFetch] Failed to schedule: \(error.localizedDescription)")
        }
    }

    /// Cancel any pending background fetch tasks.
    func cancelPendingTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundFetchHandler.taskIdentifier)
        NSLog("[BackgroundFetch] Cancelled pending tasks")
    }

    // MARK: - Task Execution

    /// Handle the background fetch task. The 9-step wakeup chain from S12.5:
    /// 1. Load saved routing state (Dart side)
    /// 2. Open UDP socket (Dart CleonaNode.startQuick())
    /// 3. Contact known peers (PING top-3)
    /// 4. Retrieve Store-and-Forward messages
    /// 5. Retrieve Reed-Solomon fragments
    /// 6. Decrypt & notify (post local iOS notifications)
    /// 7. Persist state (saveNetworkState)
    /// 8. Close socket (node shutdown)
    /// 9. Schedule next task
    ///
    /// Steps 1-8 happen on the Dart side. This handler calls into Dart,
    /// receives results, posts notifications, and manages the task lifecycle.
    private func handleBackgroundFetch(task: BGAppRefreshTask) {
        NSLog("[BackgroundFetch] Task started")

        guard !isFetching else {
            NSLog("[BackgroundFetch] Already fetching, completing task")
            task.setTaskCompleted(success: true)
            scheduleAppRefresh()
            return
        }
        isFetching = true

        // Expiration handler: clean shutdown if the OS cuts our time (~30s).
        task.expirationHandler = { [weak self] in
            NSLog("[BackgroundFetch] Task expired by OS")
            self?.isFetching = false
            // The Dart side will handle cleanup on its own timeout path.
            // We just mark the task as incomplete so the OS knows.
            task.setTaskCompleted(success: false)
            self?.scheduleAppRefresh()
        }

        guard let channel = methodChannel else {
            NSLog("[BackgroundFetch] No MethodChannel available -- engine not running?")
            isFetching = false
            task.setTaskCompleted(success: false)
            scheduleAppRefresh()
            return
        }

        // Call into Dart to perform the actual P2P work.
        // The Dart side returns: {messageCount: int, senderNames: [String], previews: [String]}
        DispatchQueue.main.async {
            channel.invokeMethod("performBackgroundFetch", arguments: nil) { [weak self] result in
                guard let self = self else { return }
                defer {
                    self.isFetching = false
                    self.scheduleAppRefresh()
                }

                if let error = result as? FlutterError {
                    NSLog("[BackgroundFetch] Dart error: \(error.code) - \(error.message ?? "")")
                    task.setTaskCompleted(success: false)
                    return
                }

                guard let response = result as? [String: Any] else {
                    NSLog("[BackgroundFetch] Unexpected response type")
                    task.setTaskCompleted(success: false)
                    return
                }

                let messageCount = response["messageCount"] as? Int ?? 0
                let senderNames = response["senderNames"] as? [String] ?? []
                let previews = response["previews"] as? [String] ?? []

                NSLog("[BackgroundFetch] Completed: \(messageCount) messages from \(senderNames.count) senders")

                if messageCount > 0 {
                    self.postLocalNotifications(
                        messageCount: messageCount,
                        senderNames: senderNames,
                        previews: previews
                    )
                }

                task.setTaskCompleted(success: true)
            }
        }
    }

    // MARK: - Local Notifications

    /// Request notification authorization. Called once at app startup.
    func requestNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                NSLog("[BackgroundFetch] Notification auth error: \(error.localizedDescription)")
            }
            NSLog("[BackgroundFetch] Notification auth granted: \(granted)")
        }
    }

    /// Post local notifications for messages retrieved during background fetch.
    /// Each sender gets a separate notification with their first message preview.
    /// The badge is updated to the total unread count.
    private func postLocalNotifications(messageCount: Int, senderNames: [String], previews: [String]) {
        let center = UNUserNotificationCenter.current()

        // Post one notification per sender
        for i in 0..<min(senderNames.count, previews.count) {
            let content = UNMutableNotificationContent()
            content.title = senderNames[i]
            content.body = previews[i]
            content.sound = .default
            content.badge = NSNumber(value: messageCount)

            let request = UNNotificationRequest(
                identifier: "cleona_bg_\(UUID().uuidString)",
                content: content,
                trigger: nil  // Deliver immediately
            )

            center.add(request) { error in
                if let error = error {
                    NSLog("[BackgroundFetch] Failed to post notification: \(error.localizedDescription)")
                }
            }
        }

        // If we have messages but no per-sender breakdown, post a summary
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
