import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

}

/// §23.10 on iOS: a single screenshot cannot be prevented, but while the
/// screen is recorded or mirrored the content is covered, and it is covered
/// in the app switcher as well. Only the test run lifts the cover
/// (`chat.cleona/capture` → `allowCapture`, decided on the Dart side:
/// capture_exclusion.dart).
///
/// Built on the system notifications rather than by overriding the scene
/// delegate: `FlutterSceneDelegate` implements the scene callbacks but does
/// not declare them in its header, so a Swift subclass cannot override them.
final class CaptureCover {
  static let shared = CaptureCover()

  /// Set by the test run's switch; then nothing is covered.
  var allowed = false {
    didSet { refreshAll() }
  }

  private var covers: [ObjectIdentifier: UIView] = [:]
  private var observers: [NSObjectProtocol] = []

  /// Starts observing. Called once from AppDelegate at launch.
  func start() {
    guard observers.isEmpty else { return }
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: UIScene.willDeactivateNotification, object: nil, queue: .main
    ) { [weak self] note in
      // The app switcher takes its snapshot after the scene resigns active.
      if let scene = note.object as? UIWindowScene { self?.update(scene, inactive: true) }
    })
    observers.append(center.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { [weak self] note in
      if let scene = note.object as? UIWindowScene { self?.update(scene, inactive: false) }
    })
    observers.append(center.addObserver(
      forName: UIScene.didDisconnectNotification, object: nil, queue: .main
    ) { [weak self] note in
      if let scene = note.object as? UIWindowScene {
        self?.covers.removeValue(forKey: ObjectIdentifier(scene))
      }
    })
    observers.append(center.addObserver(
      forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.refreshAll()
    })
  }

  private func refreshAll() {
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      update(scene, inactive: scene.activationState != .foregroundActive)
    }
  }

  private func update(_ scene: UIWindowScene, inactive: Bool) {
    guard let window = scene.windows.first else { return }
    let key = ObjectIdentifier(scene)
    let shouldCover = !allowed && (inactive || scene.screen.isCaptured)
    if shouldCover {
      let view = covers[key] ?? {
        let v = UIView(frame: window.bounds)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.backgroundColor = .systemBackground
        window.addSubview(v)
        covers[key] = v
        return v
      }()
      window.bringSubviewToFront(view)
    } else if let view = covers.removeValue(forKey: key) {
      view.removeFromSuperview()
    }
  }
}
