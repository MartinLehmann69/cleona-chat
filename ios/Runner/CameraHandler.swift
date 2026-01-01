import Flutter
import AVFoundation
import CoreVideo
import CoreMedia
import Foundation

/// AVFoundation camera handler for video capture during calls.
///
/// This is the iOS counterpart to Android's `CameraXHandler.kt`. It serves
/// the exact same MethodChannel contract ("chat.cleona/camera") so that
/// `lib/core/calls/video_capture_android.dart` (channel-based, platform
/// neutral in implementation) can drive it unmodified:
/// - isAvailable() → Bool: hardware capability check, no permission needed
/// - requestPermission() → Bool: true if already granted, else fires the
///   OS permission dialog asynchronously and returns false immediately
///   (mirrors CameraXHandler.kt — the caller re-checks/retries afterwards)
/// - startCapture({width, height, facing}) → Bool: starts YUV frame capture
/// - stopCapture() → Bool: stops capture and tears down the session
/// - switchCamera() → Bool: toggles front/back, restarting capture if active
///
/// Frames are delivered to Dart via `channel.invokeMethod("onFrame", ...)`
/// with the same payload shape as Android: {"data": <I420 bytes>,
/// "width": Int, "height": Int} — I420 layout: [Y plane][U plane][V plane],
/// size = width * height * 3 / 2. The camera outputs
/// kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange (NV12 — interleaved
/// Cb/Cr); we deinterleave into planar I420 before sending, matching
/// CameraXHandler.kt's yuv420ToI420() conversion.
class CameraHandler: NSObject, FlutterPlugin, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let channelName = "chat.cleona/camera"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = CameraHandler(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private let channel: FlutterMethodChannel
    private let captureQueue = DispatchQueue(label: "chat.cleona.camera.capture")

    private var session: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentInput: AVCaptureDeviceInput?

    private var useFrontCamera = true
    private var capturing = false
    private var lastWidth = 640
    private var lastHeight = 480

    /// Sensible upper bound on capture frame rate — avoids 60/120fps modes
    /// some devices default to, keeping frame delivery cost predictable.
    private let maxFps: Int32 = 30

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    // MARK: - MethodChannel

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(cameraAvailable())

        case "requestPermission":
            requestPermission(result: result)

        case "startCapture":
            let args = call.arguments as? [String: Any]
            let width = args?["width"] as? Int ?? 640
            let height = args?["height"] as? Int ?? 480
            let facing = args?["facing"] as? String ?? "front"
            useFrontCamera = (facing == "front")
            startCapture(width: width, height: height, result: result)

        case "stopCapture":
            stopCapture()
            result(true)

        case "switchCamera":
            useFrontCamera.toggle()
            if capturing {
                let width = lastWidth
                let height = lastHeight
                stopCapture()
                startCapture(width: width, height: height, result: result)
            } else {
                result(true)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Availability & Permission

    private func cameraAvailable() -> Bool {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return !discovery.devices.isEmpty
    }

    private func hasCameraPermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    private func requestPermission(result: @escaping FlutterResult) {
        if hasCameraPermission() {
            result(true)
            return
        }
        // Fire-and-forget, matching CameraXHandler.kt's requestPermission:
        // the OS dialog is shown asynchronously; the Dart caller re-checks
        // (e.g. by retrying startCapture) rather than awaiting this result.
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        result(false)
    }

    // MARK: - Capture lifecycle

    private func startCapture(width: Int, height: Int, result: @escaping FlutterResult) {
        guard hasCameraPermission() else {
            result(FlutterError(code: "NO_PERMISSION",
                                 message: "Camera permission not granted",
                                 details: nil))
            return
        }

        lastWidth = width
        lastHeight = height

        captureQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.configureSession(width: width, height: height)
                self.session?.startRunning()
                DispatchQueue.main.async {
                    self.capturing = true
                    result(true)
                }
            } catch let error as CameraSessionError {
                DispatchQueue.main.async {
                    result(FlutterError(code: "CAMERA_ERROR", message: error.message, details: nil))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "CAMERA_ERROR",
                                         message: "Failed to start camera: \(error.localizedDescription)",
                                         details: nil))
                }
            }
        }
    }

    private enum CameraSessionError: Error {
        case noDevice
        case cannotAddInput
        case cannotAddOutput

        var message: String {
            switch self {
            case .noDevice: return "No camera device available"
            case .cannotAddInput: return "Cannot add camera input"
            case .cannotAddOutput: return "Cannot add video output"
            }
        }
    }

    /// Must be called on captureQueue.
    private func configureSession(width: Int, height: Int) throws {
        // Tear down any previous session before building the new one.
        session?.stopRunning()
        session = nil
        videoOutput = nil
        currentInput = nil

        let newSession = AVCaptureSession()
        newSession.beginConfiguration()

        newSession.sessionPreset = presetFor(width: width, height: height)

        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video) else {
            newSession.commitConfiguration()
            throw CameraSessionError.noDevice
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard newSession.canAddInput(input) else {
            newSession.commitConfiguration()
            throw CameraSessionError.cannotAddInput
        }
        newSession.addInput(input)
        currentInput = input

        clampFrameRate(device: device)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard newSession.canAddOutput(output) else {
            newSession.commitConfiguration()
            throw CameraSessionError.cannotAddOutput
        }
        newSession.addOutput(output)

        // Upright frames — no mirroring is applied here (matches
        // CameraXHandler.kt's ImageAnalysis output, which also does not
        // mirror). Any "selfie view" mirroring for local preview only
        // belongs in the Dart/UI layer, not in the transmitted bytes.
        if let connection = output.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        newSession.commitConfiguration()

        session = newSession
        videoOutput = output
    }

    private func clampFrameRate(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            let duration = CMTimeMake(value: 1, timescale: maxFps)
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            // Non-fatal — camera still works at its default frame rate.
        }
    }

    private func presetFor(width: Int, height: Int) -> AVCaptureSession.Preset {
        let longEdge = max(width, height)
        if longEdge >= 1920 { return .hd1920x1080 }
        if longEdge >= 1280 { return .hd1280x720 }
        if longEdge >= 640 { return .vga640x480 }
        return .cif352x288
    }

    /// Stops capture and releases the session. Synchronous (via
    /// captureQueue.sync) so callers observe a fully torn-down state before
    /// this returns — mirrors CameraXHandler.kt's stopCapture(), which
    /// unbinds the CameraX use cases inline before returning.
    private func stopCapture() {
        capturing = false
        captureQueue.sync { [weak self] in
            self?.session?.stopRunning()
            self?.session = nil
            self?.videoOutput = nil
            self?.currentInput = nil
        }
    }

    // MARK: - Frame delivery

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard capturing, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let i420 = Self.nv12ToI420(pixelBuffer: pixelBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Deliver on the main (platform) thread, as required by Flutter
        // MethodChannels — mirrors CameraXHandler.kt's activity.runOnUiThread.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.capturing else { return }
            self.channel.invokeMethod("onFrame", arguments: [
                "data": FlutterStandardTypedData(bytes: i420),
                "width": width,
                "height": height,
            ])
        }
    }

    /// Convert a biplanar NV12 (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    /// pixel buffer to a planar I420 byte buffer: [Y plane][U plane][V plane],
    /// size = width * height * 3 / 2. Mirrors CameraXHandler.kt's
    /// yuv420ToI420() plane layout exactly.
    private static func nv12ToI420(pixelBuffer: CVPixelBuffer) -> Data? {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2,
              let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return nil
        }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let yRowStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        let uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)   // width / 2
        let uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1) // height / 2
        let uvRowStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        let ySize = width * height
        let uvSize = uvWidth * uvHeight // U or V plane size in I420 (each = ySize/4)

        var i420 = Data(count: ySize + uvSize * 2)
        let ySrc = yBase.assumingMemoryBound(to: UInt8.self)
        let uvSrc = uvBase.assumingMemoryBound(to: UInt8.self)

        i420.withUnsafeMutableBytes { (rawBuffer: UnsafeMutableRawBufferPointer) in
            guard let dst = rawBuffer.baseAddress else { return }

            // Y plane — row-by-row copy to strip any row-stride padding.
            let yDst = dst.assumingMemoryBound(to: UInt8.self)
            for row in 0..<height {
                memcpy(yDst + row * width, ySrc + row * yRowStride, width)
            }

            // U/V planes — deinterleave NV12's Cb,Cr pairs into separate
            // planar U and V buffers (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            // stores Cb at the even byte offset, Cr at the odd offset, same
            // order as Android's yPlane/uPlane/vPlane extraction).
            let uDst = dst.advanced(by: ySize).assumingMemoryBound(to: UInt8.self)
            let vDst = dst.advanced(by: ySize + uvSize).assumingMemoryBound(to: UInt8.self)
            for row in 0..<uvHeight {
                let rowBase = row * uvRowStride
                let uRow = uDst + row * uvWidth
                let vRow = vDst + row * uvWidth
                for col in 0..<uvWidth {
                    let srcIdx = rowBase + col * 2
                    uRow[col] = uvSrc[srcIdx]     // Cb (U)
                    vRow[col] = uvSrc[srcIdx + 1] // Cr (V)
                }
            }
        }

        return i420
    }
}
