/// V2.3 video engine — the integration layer between [VideoPipeline] (V0.3),
/// [VideoRateController] (V1.17), AES-256-GCM encryption ([SodiumFFI]), and
/// the dynamic-dispatch surface that [CallService] already uses.
///
/// ## What changed (the "replaced" in V2.3's spec entry)
///
/// The superseded file imported `dart:ui`, `vpx_ffi.dart`, ran an Isolate for
/// capture, and did five per-frame pixel conversions on the Dart heap (I420
/// rotation, mirroring, two I420→RGBA conversions, `decodeImageFromPixels`).
/// This file does none of that:
///
///   * **No `dart:ui`** — the daemon can load this file, so desktop video calls
///     are no longer silently audio-only (`main.dart:2163-2171` comment is gone).
///   * **No VpxFFI** — capture, H.264 encode and decode happen inside the
///     platform backend loaded by [VideoPipeline] (V0.3, I10).
///   * **No Isolate for capture** — the native backend runs its own thread;
///     Dart polls [VideoPipeline.readEncoded] with timeout 0 on a Timer.
///   * **No pixel conversions** — [textureId] is an opaque int for a Flutter
///     `Texture` widget; no `ui.Image`, no RGBA, no `decodeImageFromPixels`.
///   * **Adaptive bitrate** — [VideoRateController] replaces the hard-coded
///     `VideoPreset.medium` (`video_engine.dart:268` in the old file).
///
/// ## Dynamic dispatch surface (call_service.dart compatibility)
///
/// [CallService] accesses the engine via `dynamic` — no import, no type.
/// Every public member name the old engine had that call_service.dart touches
/// is preserved:
///
///   [start], [stop], [processReceivedFrame], [forceKeyframe], [muted] (set),
///   [switchCamera], [isRunning], [isMuted], [onVideoFrame], [onKeyframeNeeded],
///   [onCaptureStop], [updateKey].
///
/// New: [textureId], [onVideoShutdown], [report].
///
/// Removed: `onDecodedFrame(ui.Image)`, `onDecodedI420`, `feedExternalFrame`,
/// `onSwitchCameraRequested`, `i420ToRgba`, `rotateI420`,
/// `mirrorI420Horizontal`, `useIsolateCapture`, `preset` — none of these
/// exist on the new engine. Dynamic access from call_service.dart catches
/// NoSuchMethodError silently, so removal is safe.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/calls/bandwidth_estimator.dart';
import 'package:cleona/core/calls/video_pipeline.dart';
import 'package:cleona/core/calls/video_preset.dart';
import 'package:cleona/core/calls/video_rate_control.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/udp_fragmenter.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

export 'package:cleona/core/calls/video_preset.dart';
export 'package:cleona/core/calls/video_pipeline.dart'
    show
        VideoReport,
        VideoOpenOutcome,
        VideoOpenAccepted,
        VideoOpenRateUnachievable,
        VideoLibraryNotAvailable,
        VideoPipelineException;
export 'package:cleona/core/calls/video_rate_control.dart'
    show
        VideoRateShutdownReason,
        VideoRateControlShutdown,
        VideoOpenShutdown,
        videoOpenShutdownFor;

class VideoEngine {
  VideoEngine({
    required Uint8List sharedSecret,
    CLogger? log,
  })  : _sharedSecret = Uint8List.fromList(sharedSecret),
        _log = log ?? CLogger('VideoEngine');

  Uint8List _sharedSecret;
  final CLogger _log;
  SodiumFFI? _sodium;

  VideoPipeline? _pipeline;
  VideoRateController? _rateController;
  Timer? _readTimer;
  Timer? _rateControlTimer;

  bool _running = false;
  bool _muted = false;
  int _seqNum = 0;

  bool _hasSeenKeyframe = false;
  int _consecutiveDecodeFailures = 0;

  // ── Callbacks — same names call_service.dart sets via dynamic dispatch ──

  /// Encrypted+serialized VideoFrame proto, ready for the wire.
  void Function(Uint8List serializedVideoFrame)? onVideoFrame;

  /// Peer needs a keyframe (stream desync, mid-call join).
  void Function()? onKeyframeNeeded;

  /// Capture stopped (cleanup hook for platform layer).
  void Function()? onCaptureStop;

  /// Video shut down due to insufficient bandwidth (Erratum E1).
  /// [reason] maps 1:1 to `CallVideoOffReason.bandwidthInsufficient` (V1.12).
  void Function(VideoRateShutdownReason reason, String detail)? onVideoShutdown;

  // ── Getters ────────────────────────────────────────────────────────────

  bool get isRunning => _running;
  bool get isMuted => _muted;

  /// Texture ID for the remote peer's decoded video — an opaque int for a
  /// Flutter `Texture` widget. Null when the backend has no texture path or
  /// the session is not running.
  int? get textureId => _pipeline?.textureId;

  /// The verification report (I11). Null before [start].
  VideoReport? get report {
    try {
      return _pipeline?.report();
    } catch (_) {
      return null;
    }
  }

  /// The bandwidth estimator, exposed so the caller (V2.1) can feed it
  /// network stats (`recordSent`, `recordLost`, `updateRtt`).
  BandwidthEstimator? get estimator => _rateController?.estimator;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  Future<bool> start() async {
    if (_running) return true;

    try {
      _sodium = SodiumFFI();
    } catch (e) {
      _log.warn('SodiumFFI unavailable — video disabled: $e');
      return false;
    }

    final ceiling = UdpFragmenter.liveMediaMaxFrameBytes;
    final config = VideoConfig(
      width: VideoPreset.medium.width,
      height: VideoPreset.medium.height,
      fps: VideoPreset.medium.fps,
      targetBitrateKbps: VideoPreset.medium.bitrateKbps,
      maxFrameBytes: ceiling,
    );

    final VideoOpenOutcome outcome;
    try {
      outcome = VideoPipeline.open(config);
    } on VideoLibraryNotAvailable catch (e) {
      _log.warn('No video backend: $e');
      return false;
    } on VideoPipelineException catch (e) {
      _log.warn('Video pipeline open failed: $e');
      return false;
    }

    switch (outcome) {
      case VideoOpenAccepted(:final pipeline):
        _pipeline = pipeline;
      case VideoOpenRateUnachievable():
        final shutdown = videoOpenShutdownFor(outcome);
        if (shutdown != null) {
          onVideoShutdown?.call(shutdown.reason, shutdown.detail);
        }
        _log.info('Video open: rate unachievable at ceiling=$ceiling');
        return false;
    }

    _rateController = VideoRateController(pipeline: _pipeline!);

    try {
      _pipeline!.start();
    } catch (e) {
      _log.warn('Video pipeline start failed: $e');
      _pipeline!.close();
      _pipeline = null;
      _rateController = null;
      return false;
    }

    _running = true;
    _startReadLoop();
    _startRateControlLoop();

    _log.info('Video engine started (H.264, ceiling=$ceiling, '
        'negotiated=${_pipeline!.negotiated})');
    return true;
  }

  void stop() {
    if (!_running && _pipeline == null) return;
    _running = false;

    _readTimer?.cancel();
    _readTimer = null;
    _rateControlTimer?.cancel();
    _rateControlTimer = null;

    try {
      onCaptureStop?.call();
    } catch (e) {
      _log.warn('onCaptureStop threw: $e');
    }

    try {
      _pipeline?.stop();
      _pipeline?.close();
    } catch (e) {
      _log.warn('Video pipeline close threw: $e');
    }
    _pipeline = null;
    _rateController = null;
    _hasSeenKeyframe = false;
    _consecutiveDecodeFailures = 0;

    _log.info('Video engine stopped');
  }

  // ── Outbound: capture → readEncoded → encrypt → onVideoFrame ──────────

  void _startReadLoop() {
    _readTimer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      if (!_running || _muted) return;
      _readAndSend();
    });
  }

  void _readAndSend() {
    final pipeline = _pipeline;
    if (pipeline == null) return;

    try {
      final frame = pipeline.readEncoded(timeoutMs: 0);
      if (frame == null) return;

      final nonce = _sodium!.generateNonce();
      final encrypted =
          _sodium!.aesGcmEncrypt(frame.data, _sharedSecret, nonce);

      final videoFrame = proto.VideoFrame()
        ..sequenceNumber = _seqNum++
        ..flags = frame.flags
        ..width = pipeline.negotiated.width
        ..height = pipeline.negotiated.height
        ..nonce = nonce
        ..encryptedData = encrypted
        ..timestampMs = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;

      onVideoFrame?.call(videoFrame.writeToBuffer());
      _rateController?.estimator.recordSent();
    } catch (e) {
      _log.debug('readAndSend error: $e');
    }
  }

  // ── Inbound: decrypt → submitEncoded → native decoder → texture ───────

  void processReceivedFrame(Uint8List serializedFrame) {
    if (!_running || _pipeline == null) return;

    try {
      final videoFrame = proto.VideoFrame.fromBuffer(serializedFrame);
      final isKeyframe = (videoFrame.flags & kVideoFlagKeyframe) != 0;

      if (!_hasSeenKeyframe && !isKeyframe) {
        onKeyframeNeeded?.call();
        return;
      }

      final Uint8List decrypted;
      try {
        decrypted = _sodium!.aesGcmDecrypt(
          Uint8List.fromList(videoFrame.encryptedData),
          _sharedSecret,
          Uint8List.fromList(videoFrame.nonce),
        );
      } catch (_) {
        _log.debug(
            'Video frame decrypt failed (seq=${videoFrame.sequenceNumber})');
        return;
      }

      final result =
          _pipeline!.submitEncoded(decrypted, isKeyframe: isKeyframe);
      switch (result) {
        case VideoSubmitResult.accepted:
          _hasSeenKeyframe = true;
          _consecutiveDecodeFailures = 0;
          _rateController?.estimator.recordReceived();
        case VideoSubmitResult.awaitingKeyframe:
          onKeyframeNeeded?.call();
        case VideoSubmitResult.decodeError:
          _registerDecodeFailure();
      }
    } catch (e) {
      _registerDecodeFailure();
      _log.debug('Video frame processing error: $e');
    }
  }

  void _registerDecodeFailure() {
    _consecutiveDecodeFailures++;
    if (_consecutiveDecodeFailures >= 3) {
      _consecutiveDecodeFailures = 0;
      _hasSeenKeyframe = false;
      onKeyframeNeeded?.call();
    }
  }

  // ── Rate control ──────────────────────────────────────────────────────

  void _startRateControlLoop() {
    _rateControlTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_running) return;
      _tickRateControl();
    });
  }

  void _tickRateControl() {
    final controller = _rateController;
    if (controller == null) return;

    final outcome = controller.evaluateAndApply();
    switch (outcome) {
      case VideoRateControlUnchanged(:final estimate):
        if (estimate.needsKeyframe) _pipeline?.requestKeyframe();
      case VideoRateControlStepped(:final quality, :final estimate):
        _log.debug('Video rate stepped to $quality');
        if (estimate.needsKeyframe) _pipeline?.requestKeyframe();
      case VideoRateControlShutdown(:final reason, :final detail):
        _log.info('Video rate shutdown: $detail');
        _muted = true;
        _pipeline?.captureEnabled = false;
        onVideoShutdown?.call(reason, detail);
    }
  }

  // ── Control surface (call_service.dart dynamic dispatch) ──────────────

  void forceKeyframe() {
    _pipeline?.requestKeyframe();
  }

  set muted(bool value) {
    _muted = value;
    _pipeline?.captureEnabled = !value;
  }

  Future<bool> switchCamera() async {
    try {
      return _pipeline?.switchCamera() ?? false;
    } catch (e) {
      _log.warn('switchCamera failed: $e');
      return false;
    }
  }

  void updateKey(Uint8List newKey) {
    _sharedSecret = Uint8List.fromList(newKey);
  }

  void reconfigureForScreenShare(
      int width, int height, int fps, int bitrateKbps) {
    final pipeline = _pipeline;
    if (pipeline == null) return;

    final config = VideoConfig(
      width: width,
      height: height,
      fps: fps,
      targetBitrateKbps: bitrateKbps,
      maxFrameBytes: pipeline.negotiated.maxFrameBytes,
    );

    try {
      pipeline.reconfigure(config);
      _log.info('Reconfigured for screen share: '
          '${width}x$height@${fps}fps ${bitrateKbps}kbps');
    } on VideoPipelineException catch (e) {
      _log.warn('Screen share reconfigure failed: $e');
    }
  }

  void restoreCameraDefaults() {
    final pipeline = _pipeline;
    if (pipeline == null) return;

    final config = VideoConfig(
      width: VideoPreset.medium.width,
      height: VideoPreset.medium.height,
      fps: VideoPreset.medium.fps,
      targetBitrateKbps: VideoPreset.medium.bitrateKbps,
      maxFrameBytes: pipeline.negotiated.maxFrameBytes,
    );

    try {
      pipeline.reconfigure(config);
      _rateController = VideoRateController(pipeline: pipeline);
      _log.info('Restored camera defaults');
    } on VideoPipelineException catch (e) {
      _log.warn('Camera restore reconfigure failed: $e');
    }
  }
}
