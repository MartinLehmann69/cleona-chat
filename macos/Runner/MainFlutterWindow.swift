import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Window-channel: Dart side (lib/core/platform/window_show.dart) calls
    // `chat.cleona.cleona/window` with method `show` to raise the main
    // window when the daemon or single-instance guard signals it.
    let windowChannel = FlutterMethodChannel(
      name: "chat.cleona.cleona/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "show":
        NSApp.activate(ignoringOtherApps: true)
        self.deminiaturize(nil)
        self.makeKeyAndOrderFront(nil)
        result(nil)
      case "hide":
        self.orderOut(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
