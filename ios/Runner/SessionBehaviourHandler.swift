import Flutter
import AVFoundation
import UIKit

/// Session behaviour (V1.10): Apple interruption notifications + `duckOthers`,
/// and earpiece-only proximity monitoring — architecture §10.4, "Session
/// behaviour" table; work package docs/SPEC_VOICE_VIDEO_REWORK.md V1.10.
///
/// Counterpart: `android/.../MainActivity.kt` (this package's own file, SPEC
/// §9) and `lib/core/calls/session_behaviour.dart`, whose file doc explains
/// why the interruption signal is bridged through this channel
/// (`chat.cleona/session_behaviour`) instead of through the `cleona_voice`
/// ABI's own `poll_event()` queue: on Android the JNI voice backend has no
/// route to `AudioManager`, only the Kotlin half does, and the same
/// layering reasoning applies here — this handler observes
/// `AVAudioSessionInterruptionNotification` at the application level and
/// re-expresses it as the same `VoiceEvent.interruptionBegin` /
/// `.interruptionEnd` shape Dart already understands from the ABI.
///
/// I2/I6 (session_behaviour.dart file doc): this class never touches a
/// `cleona_voice` session — there is not one in scope here. It only forwards
/// the OS's interruption boundary to Dart and manages the `AVAudioSession`
/// activation state, which is the "OS-level claim" §10.4 means by "Cleona
/// releases it cleanly and reclaims it afterwards" — not the voice session
/// itself, which I6 requires to stay open regardless.
///
/// **UNVERIFIED (2026-07-30, honestly labelled per this session's report):**
/// no Mac is available in this environment, and
/// `native/cleona_voice/apple/**` (V1.3, the Apple voice backend that will
/// eventually own its own `AVAudioSession` setup) does not exist yet in this
/// worktree — confirmed via `find native/cleona_voice/apple` (no such
/// directory). This handler therefore configures category/mode itself, on
/// the documented (not tested) assumption that:
///   (a) nothing else claims `AVAudioSession` category/mode today, so there
///       is nothing to conflict with yet, and
///   (b) once V1.3 lands it sets the SAME category (`playAndRecord`) and
///       mode (`voiceChat`) — architecture §10.4 names both explicitly for
///       the Apple backend — and only needs to add its own
///       `VoiceProcessingIO` AudioUnit on top of an already-active session,
///       which does not require a different category.
/// This coordination must be re-checked once V1.3 exists and a Mac build is
/// possible; it is called out again in this package's own report rather than
/// silently assumed correct.
class SessionBehaviourHandler: NSObject, FlutterPlugin {
    static let channelName = "chat.cleona/session_behaviour"
    private static var channel: FlutterMethodChannel?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        self.channel = channel
        let instance = SessionBehaviourHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private var interruptionObserver: NSObjectProtocol?
    private var holdingFocus = false

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestAudioFocus":
            result(requestAudioFocus())

        case "abandonAudioFocus":
            abandonAudioFocus()
            result(nil)

        case "setProximityMonitoring":
            let args = call.arguments as? [String: Any]
            let enabled = args?["enabled"] as? Bool ?? false
            setProximityMonitoring(enabled)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Audio focus / interruption

    /// Activates the session with `duckOthers` (architecture §10.4, "Session
    /// behaviour": "Apple interruption notifications plus duckOthers.
    /// Without it, media from other apps keeps playing through the call.")
    /// and starts observing interruptions.
    private func requestAudioFocus() -> Bool {
        let session = AVAudioSession.sharedInstance()
        registerInterruptionObserver()
        do {
            // playAndRecord / voiceChat: what V1.3 is required to set
            // (architecture §10.4). duckOthers is this package's own
            // addition — see the class doc for the coordination assumption
            // with V1.3, which does not exist yet in this worktree.
            try session.setCategory(
                .playAndRecord, mode: .voiceChat,
                options: [.duckOthers, .allowBluetooth]
            )
            try session.setActive(true)
            holdingFocus = true
            return true
        } catch {
            NSLog("[SessionBehaviour] requestAudioFocus failed: \(error)")
            holdingFocus = false
            return false
        }
    }

    /// Releases what [requestAudioFocus] claimed. Call once per call, at
    /// hangup — never from the interruption handler itself, which is a
    /// temporary OS-driven loss, not an app-driven release.
    private func abandonAudioFocus() {
        removeInterruptionObserver()
        guard holdingFocus else { return }
        holdingFocus = false
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
        } catch {
            NSLog("[SessionBehaviour] abandonAudioFocus deactivate failed: \(error)")
        }
    }

    private func registerInterruptionObserver() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
    }

    private func removeInterruptionObserver() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    /// Architecture §10.4, "Interruption": "a cellular call, Siri or another
    /// VoIP call takes the session; Cleona releases it cleanly and reclaims
    /// it afterwards. Without this the audio stays gone after the foreign
    /// call ends." The "reclaims" half is `setActive(true)` on `.ended` when
    /// the OS reports `.shouldResume` — nothing about a `cleona_voice`
    /// session moves here (I2/I6; see the class doc).
    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            SessionBehaviourHandler.channel?.invokeMethod(
                "onInterruptionBegin", arguments: nil
            )

        case .ended:
            var shouldResume = false
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    .contains(.shouldResume)
            }
            if shouldResume {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    NSLog("[SessionBehaviour] re-activate after interruption failed: \(error)")
                }
            }
            SessionBehaviourHandler.channel?.invokeMethod(
                "onInterruptionEnd", arguments: ["shouldResume": shouldResume]
            )

        @unknown default:
            break
        }
    }

    // MARK: - Proximity

    /// Architecture §10.4, "Proximity": "screen off if and only if the
    /// active route is the earpiece ... iOS isProximityMonitoringEnabled."
    /// Unlike Android there is no separate wake lock to acquire or release:
    /// enabling proximity monitoring IS the whole mechanism on this
    /// platform — iOS dims and locks the screen itself once the sensor
    /// reports "near" while this flag is set, and restores it when the flag
    /// is cleared or the sensor reports "far".
    ///
    /// Called on the platform (main) thread, same as [handle] itself — no
    /// separate dispatch needed.
    private func setProximityMonitoring(_ enabled: Bool) {
        UIDevice.current.isProximityMonitoringEnabled = enabled
    }
}
