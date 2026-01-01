import Flutter
import UIKit
import BackgroundTasks
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register BGTaskScheduler BEFORE super.application returns.
    // Apple requires registration during didFinishLaunchingWithOptions.
    BackgroundFetchHandler.shared.registerBackgroundTask()

    // Request notification permission for background-fetched messages.
    BackgroundFetchHandler.shared.requestNotificationAuthorization()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

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

  /// Handle method calls from the Dart side.
  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "scheduleBackgroundFetch":
      BackgroundFetchHandler.shared.scheduleAppRefresh()
      result(true)

    case "cancelBackgroundFetch":
      BackgroundFetchHandler.shared.cancelPendingTasks()
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
