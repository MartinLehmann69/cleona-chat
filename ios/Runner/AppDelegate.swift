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

    // 1:1 video calls: register AVFoundation camera capture handler
    // (iOS counterpart to Android's CameraXHandler.kt).
    if let cameraRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "CameraHandler") {
      CameraHandler.register(with: cameraRegistrar)
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

    case "cancelBackgroundFetch":
      BackgroundFetchHandler.shared.cancelPendingTasks()
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
