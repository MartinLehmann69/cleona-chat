import Flutter
import CallKit
import AVFoundation
import Foundation

/// Call integration (V3.2): CallKit — architecture §10.4, "Session behaviour"
/// table, row "Call integration": *"CallKit (Apple) and a self-managed
/// `ConnectionService` (Android) — a **later stage**, deliberately after the
/// two layers above. Otherwise the call sounds right and behaves wrong."*
/// Staging table §10.4, stage 7 ("CallKit / `ConnectionService` — system
/// integration"); work package `docs/SPEC_VOICE_VIDEO_REWORK.md` V3.2.
///
/// Counterpart on the other platform: the self-managed `ConnectionService` in
/// `android/app/src/main/kotlin/**` (a different package's file, SPEC §9).
/// Both serve the **same** MethodChannel contract so the Dart side is written
/// once and is platform-neutral:
///
///   Dart -> platform (`chat.cleona/call_integration`)
///     reportIncomingCall  {callId: String, displayName: String, hasVideo: Bool}
///     reportOutgoingCall  {callId: String, displayName: String, hasVideo: Bool}
///     reportCallConnected {callId: String}
///     endCall             {callId: String}
///     setMuted            {callId: String, muted: Bool}
///
///   platform -> Dart (same channel)
///     onAnswerCall               {callId: String}
///     onEndCall                  {callId: String}
///     onSetMuted                 {callId: String, muted: Bool}
///     onAudioSessionActivated    {}     (iOS only)
///     onAudioSessionDeactivated  {}     (iOS only)
///
/// # I2/§10.4: this class does not touch the audio session
///
/// Cleona does no audio DSP of its own and the OS voice session belongs to
/// `native/cleona_voice` — on iOS specifically to
/// `native/cleona_voice/apple/cleona_voice_apple_ios.m`, whose
/// `cva_platform_open()` sets `AVAudioSessionCategoryPlayAndRecord` +
/// `AVAudioSessionModeVoiceChat` and calls `setActive:YES` (see
/// `cleona_voice_apple_platform.h`, `cva_platform_open` doc comment: *"sets
/// AVAudioSession category `playAndRecord` + mode `voiceChat` and activates
/// the session ... Activation happens HERE rather than in
/// `cleona_voice_start()` on purpose"*).
///
/// This handler therefore **never** calls `setCategory`, `setMode`,
/// `setActive` or `setPreferred*` on `AVAudioSession`. It only observes
/// `provider(_:didActivate:)` / `provider(_:didDeactivate:)` and re-expresses
/// them as `onAudioSessionActivated` / `onAudioSessionDeactivated`, so that
/// Dart can order the `cleona_voice` session against CallKit's activation
/// instead of racing it. The ordering requirement that follows from this split
/// is documented in this package's report, not silently worked around here.
///
/// # Threading
///
/// Everything in this class runs on the main thread and mutates its state only
/// there, so no lock is needed:
///   * `handle(_:result:)` is invoked by Flutter on the platform thread, which
///     on iOS is the main thread;
///   * the `CXProvider` delegate queue is `nil` == main queue
///     (`setDelegate(self, queue: nil)`);
///   * `CXCallController()` (the no-argument initialiser) delivers its
///     request completions on the main queue.
/// `invokeMethod` calls are nevertheless wrapped in `DispatchQueue.main.async`
/// where they sit inside a completion handler, matching `CameraHandler`.
class CallKitHandler: NSObject, FlutterPlugin, CXProviderDelegate {
    static let channelName = "chat.cleona/call_integration"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = CallKitHandler(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private let channel: FlutterMethodChannel
    private let provider: CXProvider
    private let callController: CXCallController

    /// callId (as Dart sent it) -> the UUID CallKit knows the call by.
    private var uuidByCallId: [String: UUID] = [:]
    /// The inverse, so a delegate callback can hand Dart back the *exact*
    /// string it passed in rather than a re-formatted one.
    private var callIdByUuid: [UUID: String] = [:]
    /// Calls this device placed. `reportCallConnected` maps to
    /// `reportOutgoingCall(with:connectedAt:)` only for these — an incoming
    /// call is "connected" the moment `CXAnswerCallAction` is fulfilled and
    /// has no separate report (there is no `reportIncomingCall(connectedAt:)`
    /// in CallKit).
    private var outgoingUuids: Set<UUID> = []
    /// Guards against echoing a state change back to the side that asked for
    /// it: `endCall`/`setMuted` from Dart go through a `CXTransaction`, which
    /// makes the provider delegate fire for an action Dart already knows
    /// about. Without this, `endCall` from Dart would come straight back as
    /// `onEndCall` and Dart would tear the call down twice.
    private var locallyEndingUuids: Set<UUID> = []
    private var pendingMuteUuids: Set<UUID> = []

    init(channel: FlutterMethodChannel) {
        self.channel = channel

        // `CXProviderConfiguration()` (no-argument, iOS 14+) takes the
        // localised app name from the bundle; the `init(localizedName:)`
        // form is deprecated. Deployment target here is 15.5.
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        // Cleona has no hold, no conferencing and no call merging: one call
        // per group, one group. Advertising more would put buttons in the
        // system call UI that map to nothing.
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        // §4 of this project: identity is purely cryptographic — no phone
        // numbers, no e-mail addresses. `.generic` is the only handle type
        // that can carry a Cleona peer, and offering `.phoneNumber` or
        // `.emailAddress` would advertise a lookup Cleona cannot perform.
        configuration.supportedHandleTypes = [.generic]
        // Keep Cleona calls out of the system Phone app's Recents. Recents is
        // shared, un-encrypted OS state and would leak contact display names
        // and call times out of the app; it also makes Siri offer "call back",
        // which would arrive here as a `CXStartCallAction` for a call this
        // handler never created (see `provider(_:perform: CXStartCallAction)`).
        configuration.includesCallsInRecents = false

        self.provider = CXProvider(configuration: configuration)
        self.callController = CXCallController()
        super.init()
        self.provider.setDelegate(self, queue: nil)
    }

    deinit {
        provider.invalidate()
    }

    // MARK: - Dart -> platform

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "reportIncomingCall":
            guard let args = call.arguments as? [String: Any],
                  let callId = args["callId"] as? String, !callId.isEmpty,
                  let displayName = args["displayName"] as? String else {
                result(Self.invalidArgs("callId and displayName required"))
                return
            }
            let hasVideo = args["hasVideo"] as? Bool ?? false
            reportIncomingCall(callId: callId, displayName: displayName,
                               hasVideo: hasVideo, result: result)

        case "reportOutgoingCall":
            guard let args = call.arguments as? [String: Any],
                  let callId = args["callId"] as? String, !callId.isEmpty,
                  let displayName = args["displayName"] as? String else {
                result(Self.invalidArgs("callId and displayName required"))
                return
            }
            let hasVideo = args["hasVideo"] as? Bool ?? false
            reportOutgoingCall(callId: callId, displayName: displayName,
                               hasVideo: hasVideo, result: result)

        case "reportCallConnected":
            guard let args = call.arguments as? [String: Any],
                  let callId = args["callId"] as? String, !callId.isEmpty else {
                result(Self.invalidArgs("callId required"))
                return
            }
            reportCallConnected(callId: callId, result: result)

        case "endCall":
            guard let args = call.arguments as? [String: Any],
                  let callId = args["callId"] as? String, !callId.isEmpty else {
                result(Self.invalidArgs("callId required"))
                return
            }
            endCall(callId: callId, result: result)

        case "setMuted":
            guard let args = call.arguments as? [String: Any],
                  let callId = args["callId"] as? String, !callId.isEmpty,
                  let muted = args["muted"] as? Bool else {
                result(Self.invalidArgs("callId and muted required"))
                return
            }
            setMuted(callId: callId, muted: muted, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func invalidArgs(_ message: String) -> FlutterError {
        return FlutterError(code: "INVALID_ARGS", message: message, details: nil)
    }

    private static func unknownCall(_ callId: String) -> FlutterError {
        return FlutterError(
            code: "UNKNOWN_CALL",
            message: "no CallKit call is registered for callId \"\(callId)\"",
            details: nil
        )
    }

    /// Rings the system incoming-call UI. Errors from CallKit are real and
    /// user-visible (the OS refuses e.g. while the user has the app blocked
    /// under Focus, or when a cellular call already owns the UI), so they are
    /// surfaced to Dart rather than swallowed.
    private func reportIncomingCall(callId: String, displayName: String,
                                    hasVideo: Bool,
                                    result: @escaping FlutterResult) {
        let uuid = registerCall(callId: callId, outgoing: false)

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: displayName)
        update.localizedCallerName = displayName
        update.hasVideo = hasVideo
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    NSLog("[CallKit] reportNewIncomingCall failed: \(error)")
                    self?.forget(uuid)
                    result(FlutterError(code: "CALLKIT_ERROR",
                                        message: "reportNewIncomingCall: \(error.localizedDescription)",
                                        details: nil))
                } else {
                    result(true)
                }
            }
        }
    }

    /// Announces an outgoing call to the system. Two steps, both required:
    /// the `CXStartCallAction` transaction is what makes CallKit own the call,
    /// `reportOutgoingCall(with:startedConnectingAt:)` is what makes the system
    /// UI show "calling…" instead of a connected timer from the first second.
    /// The latter is sent from the `CXStartCallAction` delegate callback, which
    /// is where CallKit expects it.
    private func reportOutgoingCall(callId: String, displayName: String,
                                    hasVideo: Bool,
                                    result: @escaping FlutterResult) {
        let uuid = registerCall(callId: callId, outgoing: true)

        let handle = CXHandle(type: .generic, value: displayName)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.isVideo = hasVideo

        callController.request(CXTransaction(action: action)) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    NSLog("[CallKit] CXStartCallAction failed: \(error)")
                    self?.forget(uuid)
                    result(FlutterError(code: "CALLKIT_ERROR",
                                        message: "CXStartCallAction: \(error.localizedDescription)",
                                        details: nil))
                } else {
                    // The display name is only known here, not in the delegate
                    // callback, so push it as an update right away.
                    let update = CXCallUpdate()
                    update.remoteHandle = handle
                    update.localizedCallerName = displayName
                    update.hasVideo = hasVideo
                    update.supportsHolding = false
                    update.supportsGrouping = false
                    update.supportsUngrouping = false
                    update.supportsDTMF = false
                    self?.provider.reportCall(with: uuid, updated: update)
                    result(true)
                }
            }
        }
    }

    /// Stops the "calling…" state in the system UI. Outgoing only — see
    /// `outgoingUuids`. For an incoming call this is a no-op that still
    /// returns `true`, because the contract is platform-neutral and Dart
    /// calls it for both directions.
    private func reportCallConnected(callId: String,
                                     result: @escaping FlutterResult) {
        guard let uuid = uuidByCallId[callId] else {
            result(Self.unknownCall(callId))
            return
        }
        if outgoingUuids.contains(uuid) {
            provider.reportOutgoingCall(with: uuid, connectedAt: Date())
        }
        result(true)
    }

    /// Ends the call in the system UI.
    ///
    /// The request goes through a `CXEndCallAction` transaction, which is the
    /// correct path for a hangup the local user triggered inside the Flutter
    /// UI. If the transaction fails — which is what happens when CallKit no
    /// longer knows the call, e.g. because the remote party ended it and the
    /// provider already tore it down — it falls back to
    /// `reportCall(with:endedAt:reason:)`. Leaving a stale call in the system
    /// UI is worse than an inexact end reason, so this path recovers and
    /// returns `true` instead of throwing.
    private func endCall(callId: String, result: @escaping FlutterResult) {
        guard let uuid = uuidByCallId[callId] else {
            result(Self.unknownCall(callId))
            return
        }
        locallyEndingUuids.insert(uuid)

        let action = CXEndCallAction(call: uuid)
        callController.request(CXTransaction(action: action)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else {
                    result(true)
                    return
                }
                if let error = error {
                    NSLog("[CallKit] CXEndCallAction failed, reporting directly: \(error)")
                    self.locallyEndingUuids.remove(uuid)
                    self.provider.reportCall(with: uuid, endedAt: Date(),
                                             reason: .remoteEnded)
                    self.forget(uuid)
                }
                result(true)
            }
        }
    }

    /// Mirrors Dart's mute state into the system call UI. This only keeps the
    /// UI in sync — the actual muting is the `cleona_voice` session's job
    /// (I2), and nothing here touches it.
    private func setMuted(callId: String, muted: Bool,
                          result: @escaping FlutterResult) {
        guard let uuid = uuidByCallId[callId] else {
            result(Self.unknownCall(callId))
            return
        }
        pendingMuteUuids.insert(uuid)

        let action = CXSetMutedCallAction(call: uuid, muted: muted)
        callController.request(CXTransaction(action: action)) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    NSLog("[CallKit] CXSetMutedCallAction failed: \(error)")
                    self?.pendingMuteUuids.remove(uuid)
                    result(FlutterError(code: "CALLKIT_ERROR",
                                        message: "CXSetMutedCallAction: \(error.localizedDescription)",
                                        details: nil))
                } else {
                    result(true)
                }
            }
        }
    }

    // MARK: - callId <-> UUID

    /// CallKit addresses calls by `UUID`; Cleona addresses them by a callId
    /// string. `CallManager` builds that id from 16 random bytes
    /// (`call_manager.dart:167`) and hands it out hex-encoded
    /// (`callIdHex`), i.e. 32 hex characters — exactly a UUID's worth of
    /// entropy, so the two can be mapped **deterministically** instead of
    /// through a table lookup that would break the moment the handler is
    /// recreated. The table is still maintained, because the reverse
    /// direction has to return the exact string Dart passed in, and because a
    /// callId in some other shape must still work.
    private func registerCall(callId: String, outgoing: Bool) -> UUID {
        if let existing = uuidByCallId[callId] {
            if outgoing { outgoingUuids.insert(existing) }
            return existing
        }
        let uuid = UUID(uuidString: callId)
            ?? Self.uuidFromHex(callId)
            ?? UUID()
        uuidByCallId[callId] = uuid
        callIdByUuid[uuid] = callId
        if outgoing { outgoingUuids.insert(uuid) }
        return uuid
    }

    private func forget(_ uuid: UUID) {
        if let callId = callIdByUuid.removeValue(forKey: uuid) {
            uuidByCallId.removeValue(forKey: callId)
        }
        outgoingUuids.remove(uuid)
        locallyEndingUuids.remove(uuid)
        pendingMuteUuids.remove(uuid)
    }

    /// 32 hex characters -> `UUID`. `nil` for anything else, including the
    /// dashed UUID form (which `UUID(uuidString:)` handles before this is
    /// reached).
    private static func uuidFromHex(_ hex: String) -> UUID? {
        guard hex.count == 32 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        var index = hex.startIndex
        for _ in 0..<16 {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - platform -> Dart (CXProviderDelegate)

    /// CallKit lost its state (provider invalidated, system restarted the
    /// call service). Every call it knew about is gone; Dart has to be told,
    /// or it keeps sessions alive that the system UI no longer shows.
    func providerDidReset(_ provider: CXProvider) {
        NSLog("[CallKit] providerDidReset — dropping \(callIdByUuid.count) call(s)")
        let callIds = Array(callIdByUuid.values)
        uuidByCallId.removeAll()
        callIdByUuid.removeAll()
        outgoingUuids.removeAll()
        locallyEndingUuids.removeAll()
        pendingMuteUuids.removeAll()
        for callId in callIds {
            channel.invokeMethod("onEndCall", arguments: ["callId": callId])
        }
    }

    /// The user accepted from the system call UI (or the lock screen).
    ///
    /// I2: Apple's own CallKit sample configures `AVAudioSession` here, before
    /// fulfilling. This handler deliberately does not — the session belongs to
    /// `native/cleona_voice/apple/cleona_voice_apple_ios.m`. Dart is told
    /// first and fulfils by opening the voice session; CallKit then activates
    /// it and `provider(_:didActivate:)` reports that back. The ordering
    /// consequence is written up in this package's report.
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let callId = callIdByUuid[action.callUUID] else {
            NSLog("[CallKit] answer for unknown call \(action.callUUID)")
            action.fail()
            return
        }
        channel.invokeMethod("onAnswerCall", arguments: ["callId": callId])
        action.fulfill()
    }

    /// The user hung up. Either from the system call UI — then Dart has to be
    /// told — or as the tail of Dart's own `endCall`, in which case the echo
    /// is suppressed (`locallyEndingUuids`).
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let uuid = action.callUUID
        let callId = callIdByUuid[uuid]
        let echoSuppressed = locallyEndingUuids.contains(uuid)
        forget(uuid)
        action.fulfill()
        if !echoSuppressed, let callId = callId {
            channel.invokeMethod("onEndCall", arguments: ["callId": callId])
        }
    }

    /// The user toggled mute in the system call UI. Suppressed when it is the
    /// echo of Dart's own `setMuted` (`pendingMuteUuids`).
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let uuid = action.callUUID
        let echoSuppressed = pendingMuteUuids.remove(uuid) != nil
        action.fulfill()
        guard !echoSuppressed, let callId = callIdByUuid[uuid] else { return }
        channel.invokeMethod("onSetMuted",
                             arguments: ["callId": callId, "muted": action.isMuted])
    }

    /// Fires for the transaction `reportOutgoingCall` requested. It can also
    /// fire for a call this handler never created — Siri or a Recents entry
    /// asking to place a call. Cleona cannot serve that: there is no
    /// `INStartCallIntent` handler and no way to resolve a `.generic` handle
    /// back to a peer from outside the app, so such an action is failed
    /// rather than silently dropped. `includesCallsInRecents = false` keeps
    /// the Recents half of that from arising in the first place.
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let uuid = action.callUUID
        guard callIdByUuid[uuid] != nil else {
            NSLog("[CallKit] system-initiated CXStartCallAction for unknown call \(uuid) — failing")
            action.fail()
            return
        }
        action.fulfill()
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
    }

    /// CallKit activated the shared `AVAudioSession`. Reported to Dart, not
    /// acted on here (I2) — see the class doc.
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        channel.invokeMethod("onAudioSessionActivated",
                             arguments: [String: Any]())
    }

    /// CallKit deactivated the shared `AVAudioSession`.
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        channel.invokeMethod("onAudioSessionDeactivated",
                             arguments: [String: Any]())
    }

    /// CallKit gives an action a few seconds; past that the call is in an
    /// undefined state as far as the system is concerned. Log it — a silent
    /// timeout here is exactly the "sounds right, behaves wrong" class of
    /// defect §10.4 puts this stage last to avoid.
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        NSLog("[CallKit] timed out performing \(type(of: action))")
    }
}
