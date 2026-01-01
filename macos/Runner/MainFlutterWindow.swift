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

    // §23.10: exclude the main window from sharing — screenshots and
    // recorders of other programs do not get its content — on every build,
    // before the first frame. Only the test run lifts it (`allowCapture`,
    // beta builds only, decided on the Dart side: capture_exclusion.dart).
    self.sharingType = .none

    let captureChannel = FlutterMethodChannel(
      name: "chat.cleona/capture",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    captureChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "allowCapture" {
        self?.sharingType = .readOnly
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // §23.10: the saving side of the application's own screenshot. The
    // picture goes to ~/Pictures/Cleona, unencrypted — the user asked for
    // it (§21.4.2). The app is not sandboxed (Release.entitlements).
    let screenshotChannel = FlutterMethodChannel(
      name: "chat.cleona/screenshot",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    screenshotChannel.setMethodCallHandler { call, result in
      guard call.method == "savePng" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let png = args["png"] as? FlutterStandardTypedData,
            !png.data.isEmpty else {
        result(FlutterError(code: "NO_PNG", message: "missing picture", details: nil))
        return
      }
      let fm = FileManager.default
      guard let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first else {
        result(FlutterError(code: "SAVE_FAILED", message: "no Pictures folder", details: nil))
        return
      }
      let dir = pictures.appendingPathComponent("Cleona", isDirectory: true)
      let stamp = DateFormatter()
      stamp.dateFormat = "yyyyMMdd_HHmmss"
      let file = dir.appendingPathComponent("cleona_\(stamp.string(from: Date())).png")
      do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.data.write(to: file)
        result(["uri": file.path])
      } catch {
        result(FlutterError(code: "SAVE_FAILED", message: error.localizedDescription, details: nil))
      }
    }

    super.awakeFromNib()
  }
}
