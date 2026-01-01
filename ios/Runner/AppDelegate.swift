import Flutter
import UIKit
import BackgroundTasks
import UserNotifications
import Network

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

    // Trigger the Local Network permission dialog. This MUST happen before
    // the Dart node opens UDP sockets, otherwise iOS silently drops inbound
    // packets (sends work, receives don't — the classic iOS UDP gotcha).
    triggerLocalNetworkPermission()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // §3.7 OS Keyring: register Keychain MethodChannel handler.
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
