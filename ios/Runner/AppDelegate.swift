import Flutter
import UIKit
import BackgroundTasks
import UserNotifications
import Network
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// NWBrowser triggers the "Local Network" permission dialog on iOS 14+.
  /// Raw UDP sockets alone do NOT trigger it — without this, iOS silently
  /// drops all incoming LAN packets while outgoing sends succeed.
  private var localNetworkBrowser: NWBrowser?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register BGTaskScheduler BEFORE super.application returns.
    // Apple requires registration during didFinishLaunchingWithOptions.
    BackgroundFetchHandler.shared.registerBackgroundTasks()

    // -- SCHEDULE AT STARTUP (F-8, S370) -----------------------------
    //
    // Architecture v3_0 §12.5 ("Scheduling chain", l. 6460) explicitly
    // requires: "Both are also scheduled on first app launch and on
    // every foreground->background transition." The transition to the
    // background was wired (Dart: `didChangeAppLifecycleState` ->
    // `scheduleBackgroundFetch` -> `scheduleBothTasks`, main.dart:989),
    // the program start was NOT.
    //
    // What that cost: after a crash, a device restart or
    // a reinstall nothing was in the queue until the
    // user next opened AND left the app again. Exactly
    // in the window in which background delivery is worth the most,
    // there was none.
    //
    // Must come AFTER `registerBackgroundTasks()`: `BGTaskScheduler.submit`
    // throws for an unregistered identifier.
    //
    // UNVERIFIED: code reading only. There is no Apple machine in this
    // session, and the CI path is not usable (GitHub only holds
    // `main` @ v3.2.2-beta, this branch is 2930 commits ahead -- a
    // run there would measure the wrong tree). A device run must show
    // that the two `submit` calls here do not end with
    // `BGTaskSchedulerErrorCodeTooManyPendingTaskRequests` when requests
    // from the last session are still pending at startup -- the
    // `catch` branch in `scheduleRefreshTask`/`scheduleProcessingTask`
    // then logs this without crashing.
    BackgroundFetchHandler.shared.scheduleBothTasks()

    // Request notification permission for background-fetched messages.
    BackgroundFetchHandler.shared.requestNotificationAuthorization()

    // S422 N-2: the delegate of the notification center, set before the
    // launch ends (Apple:
    // https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/delegate).
    // Without it iOS shows no notification of an app in the foreground —
    // and `inactive` (Control Center over the app) is foreground for iOS
    // but not "resumed" for Cleona's L5 gate.
    UNUserNotificationCenter.current().delegate = self

    // Trigger the Local Network permission dialog. This MUST happen before
    // the Dart node opens UDP sockets, otherwise iOS silently drops inbound
    // packets (sends work, receives don't — the classic iOS UDP gotcha).
    triggerLocalNetworkPermission()

    // §23.10: cover the content while the screen is captured and in the
    // app switcher (SceneDelegate.swift, CaptureCover).
    CaptureCover.shared.start()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // S422 N-2: a notification arriving while the app is in the foreground for
  // iOS. Shown only when the running app's Dart service handed it over
  // (`BackgroundFetchHandler.postedByDartKey`): the service's L5 gate
  // already decided (§22.8) — it lets a notification through only when the
  // app is not "resumed" (e.g. `inactive`, Control Center over the app).
  // `override`: `FlutterAppDelegate` carries the method (it forwards it to
  // plugins, `FlutterAppDelegate.mm`).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    if userInfo[BackgroundFetchHandler.postedByDartKey] as? Bool == true {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([])
    }
  }

  /// §22.8 (D-125 (3)): the conversation and identity of a tapped
  /// notification, drained by Dart via `consumeNotificationTap` on
  /// `chat.cleona/notification`. The channel is kept to signal the tap
  /// (`notificationTapped`) while the engine runs.
  private var pendingNotificationTap: [String: String]?
  private var notificationChannel: FlutterMethodChannel?

  // S422 N-2, D-125 (3): the user tapped a notification. iOS brings the app
  // to the front; the tap is stashed for Dart, which opens the conversation
  // on its home screen (Dart decides: not the batch notification, not a
  // reminder). Also the cold start through a tap arrives here: the delegate
  // is set before the launch ends (see above). The completion handler is
  // called on every way out (`defer`), as Apple requires
  // (https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:didreceive:withcompletionhandler:)).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    defer { completionHandler() }
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
    let info = response.notification.request.content.userInfo
    guard let conversationId = info["conversationId"] as? String, !conversationId.isEmpty else { return }
    pendingNotificationTap = [
      "conversationId": conversationId,
      "identity": info["identity"] as? String ?? "",
    ]
    // No id in the log line (§22.8: what a notification shows goes nowhere else).
    NSLog("[Notification] tap stashed")
    // Engine running: Dart drains now. At a cold start before the engine,
    // the channel is nil and Dart drains after its first frame.
    notificationChannel?.invokeMethod("notificationTapped", arguments: nil)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // §4.5.2 OS Keyring: register Keychain MethodChannel handler.
    if let keyringRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeyringHandler") {
      KeyringHandler.register(with: keyringRegistrar)
    }

    // Session behaviour (V1.10): AudioFocus/interruption/proximity — iOS
    // counterpart to Android's session-behaviour channel in MainActivity.kt.
    if let sessionBehaviourRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "SessionBehaviourHandler") {
      SessionBehaviourHandler.register(with: sessionBehaviourRegistrar)
    }

    // Call integration (V3.2): CallKit — iOS counterpart to Android's
    // self-managed ConnectionService. Same MethodChannel contract
    // ("chat.cleona/call_integration") on both platforms.
    if let callKitRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "CallKitHandler") {
      CallKitHandler.register(with: callKitRegistrar)
    }

    // §23.10: the test run's switch lifts the capture cover
    // (SceneDelegate.swift, CaptureCover).
    if let captureRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "CaptureHandler") {
      let captureChannel = FlutterMethodChannel(
        name: "chat.cleona/capture",
        binaryMessenger: captureRegistrar.messenger()
      )
      captureChannel.setMethodCallHandler { (call, result) in
        if call.method == "allowCapture" {
          CaptureCover.shared.allowed = true
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Deep link drain: Dart calls consumePendingDeepLink to pick up
    // cleona:// URIs that opened the app (cold or warm start).
    if let deepLinkRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeepLinkHandler") {
      let deepLinkChannel = FlutterMethodChannel(
        name: "chat.cleona/deeplink",
        binaryMessenger: deepLinkRegistrar.messenger()
      )
      deepLinkChannel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "consumePendingDeepLink" {
          let link = self?.pendingDeepLink
          self?.pendingDeepLink = nil
          result(link)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Storage channel: free disk space query for dynamic S&F storage budget.
    if let storageRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "StorageHandler") {
      let storageChannel = FlutterMethodChannel(
        name: "chat.cleona/storage",
        binaryMessenger: storageRegistrar.messenger()
      )
      storageChannel.setMethodCallHandler { (call, result) in
        if call.method == "getFreeDiskSpace" {
          do {
            let path = call.arguments as? String ?? NSHomeDirectory()
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            let freeBytes = (attrs[.systemFreeSize] as? Int64) ?? 0
            result(freeBytes)
          } catch {
            result(Int64(0))
          }
        } else if call.method == "getDeviceName" {
          // S398, B-3: the device's name for the device set and the
          // enrolment request (device_name.dart chooses; never "localhost").
          // Since iOS 16 `name` is the generic model name ("iPhone") unless
          // the app holds the user-assigned-device-name entitlement.
          result([
            "name": UIDevice.current.name,
            "manufacturer": "Apple",
            "model": UIDevice.current.model,
          ])
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // S420 IB-1: the app icon badge, on the same channel and with the same
    // arguments as Android's `MainActivity.kt` (`updateBadge`: `count`,
    // `conversationIds`). Dart sends it on every unread change and on every
    // return to the front (`main.dart` `_updateAndroidBadge`); the number is
    // the unread sum over every identity without the system channels.
    //
    // S422 (N-1, N-3): the same channel carries the system notification the
    // Dart service formed (`postNotification`, `cancelNotification` — one per
    // conversation, `main.dart` `onPostNotificationIos`) and the vibration of
    // a message (`vibrate`); S422 T-1 adds the app's own sound (`playSound`).
    // Android's other methods of this channel (loop sounds, call audio mode,
    // incoming call) are never sent on iOS.
    if let notificationRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "NotificationBadgeHandler") {
      let notificationChannel = FlutterMethodChannel(
        name: "chat.cleona/notification",
        binaryMessenger: notificationRegistrar.messenger()
      )
      self.notificationChannel = notificationChannel
      // S422 T-1: the `.caf` sounds into `Library/Sounds` for the
      // notifications; the registrar finds them among the Flutter assets.
      BackgroundFetchHandler.shared.installNotificationSounds(
        assetKey: { notificationRegistrar.lookupKey(forAsset: $0) })
      notificationChannel.setMethodCallHandler { [weak self] (call, result) in
        let args = call.arguments as? [String: Any]
        if call.method == "consumeNotificationTap" {
          // §22.8: the stashed tap, handed over once.
          let tap = self?.pendingNotificationTap
          self?.pendingNotificationTap = nil
          result(tap)
        } else if call.method == "updateBadge" {
          let count = args?["count"] as? Int ?? 0
          BackgroundFetchHandler.shared.applyBadge(count: count)
          result(nil)
        } else if call.method == "postNotification" {
          BackgroundFetchHandler.shared.postNotification(
            title: args?["title"] as? String ?? "",
            body: args?["body"] as? String ?? "",
            conversationId: args?["conversationId"] as? String ?? "",
            identity: args?["identity"] as? String ?? "",
            soundName: args?["soundName"] as? String)
          result(nil)
        } else if call.method == "playSound" {
          // S422 T-1: the app's own sound in the foreground, a `.caf` asset.
          BackgroundFetchHandler.shared.playSound(asset: args?["asset"] as? String ?? "")
          result(nil)
        } else if call.method == "scheduleReminders" {
          // §18.1.6, D-125 (2): reminders scheduled with the system ahead.
          BackgroundFetchHandler.shared.scheduleReminders(
            args?["reminders"] as? [[String: Any]] ?? [])
          result(nil)
        } else if call.method == "withdrawReminder" {
          BackgroundFetchHandler.shared.withdrawReminder(
            id: args?["id"] as? String ?? "")
          result(nil)
        } else if call.method == "cancelNotification" {
          BackgroundFetchHandler.shared.cancelNotification(
            conversationId: args?["conversationId"] as? String ?? "")
          result(nil)
        } else if call.method == "vibrate" {
          // The system's vibration; the duration Android takes has no
          // counterpart here (https://developer.apple.com/documentation/audiotoolbox/1405248-audioservicesplaysystemsound).
          AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Set up the MethodChannel for background fetch communication with Dart.
    // The FlutterEngine is now available via the plugin registry's messenger.
    guard let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundFetchPlugin")?.messenger() else {
      NSLog("[AppDelegate] Could not obtain BinaryMessenger from engine bridge")
      return
    }

    let channel = FlutterMethodChannel(
      name: "cleona/background_fetch",
      binaryMessenger: messenger
    )

    // Store the channel so BackgroundFetchHandler can call into Dart.
    BackgroundFetchHandler.shared.methodChannel = channel

    // Handle method calls FROM Dart (schedule/cancel).
    channel.setMethodCallHandler { [weak self] (call, result) in
      self?.handleMethodCall(call, result: result)
    }
  }

  // Deep link: cleona:// URI scheme, stashed for Dart drain via MethodChannel.
  private var pendingDeepLink: String?

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if url.scheme == "cleona" {
      pendingDeepLink = url.absoluteString
    }
    return super.application(app, open: url, options: options)
  }

  /// Trigger Local Network permission via NWBrowser. The browse itself is
  /// ephemeral — we start it, the OS shows the dialog, and we cancel after 2s.
  /// The Bonjour service type matches NSBonjourServices in Info.plist.
  private func triggerLocalNetworkPermission() {
    let params = NWParameters()
    params.includePeerToPeer = true
    let browser = NWBrowser(for: .bonjour(type: "_cleona._udp", domain: nil), using: params)
    browser.stateUpdateHandler = { state in
      NSLog("[LocalNetwork] Browser state: \(state)")
    }
    browser.start(queue: .main)
    localNetworkBrowser = browser
    // Keep browsing for 2s to ensure the dialog appears, then cancel.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
      self?.localNetworkBrowser?.cancel()
      self?.localNetworkBrowser = nil
      NSLog("[LocalNetwork] Browser cancelled (permission dialog should have appeared)")
    }
  }

  /// Handle method calls from the Dart side.
  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "scheduleBackgroundFetch":
      BackgroundFetchHandler.shared.scheduleBothTasks()
      result(true)

    // `cancelBackgroundFetch` was removed with S370 -- the Dart side
    // had zero callers, and v3_0 §12.5 knows no cancellation, only a
    // scheduling chain. Full rationale in
    // `lib/core/platform/ios_background_fetch.dart`.

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
