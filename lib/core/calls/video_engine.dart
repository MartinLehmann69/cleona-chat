/// Video engine for 1:1 video calls.
///
/// Manages the video pipeline:
/// - Capture: V4L2 → I420 → VP8 encode → AES-256-GCM encrypt → send callback
/// - Receive: encrypted data → decrypt → VP8 decode → I420 → RGBA → display callback
///
/// Capture runs in a separate Isolate to avoid blocking the main thread.
/// The shared AES-256-GCM key is the same as for audio (negotiated at call start).
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cleona/core/calls/video_preset.dart';
import 'package:cleona/core/calls/vpx_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

export 'package:cleona/core/calls/video_preset.dart';

// ── Capture Isolate Messages ─────────────────────────────────────────

class _CaptureInit {
  final SendPort frameSendPort;
  final Uint8List sharedSecret;
  final String cameraDevice;
  final int width;
  final int height;
  final int fps;
  final int bitrateKbps;
  final int keyframeInterval;

  _CaptureInit({
    required this.frameSendPort,
    required this.sharedSecret,
    required this.cameraDevice,
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrateKbps,
    required this.keyframeInterval,
  });
}

enum _CaptureCommand { stop, forceKeyframe, mute, unmute }

// ── Capture Isolate Entry Point ──────────────────────────────────────

/// Runs in a separate isolate. Captures camera frames, encodes with VP8,
/// encrypts with AES-256-GCM, and sends serialized VideoFrame protos back.
void _captureIsolateEntry(List<dynamic> args) {
  final init = args[0] as _CaptureInit;
  final commandPort = args[1] as ReceivePort;

  final frameSendPort = init.frameSendPort;

  // Each isolate needs its own FFI instances
  VpxFFI? vpx;
  SodiumFFI? sodium;

  try {
    vpx = VpxFFI(
      width: init.width,
      height: init.height,
      bitrateKbps: init.bitrateKbps,
      fps: init.fps,
      keyframeInterval: init.keyframeInterval,
    );
    sodium = SodiumFFI();
  } catch (e) {
    frameSendPort.send(null); // signal failure
    return;
  }

  // Open camera via V4L2 shim (FFI — must load in this isolate)
  // We load the shim dynamically here since the isolate is a separate thread.
  late final dynamic camera;
  try {
    camera = _IsolateCameraCapture(init.cameraDevice, init.width, init.height, init.fps);
    camera.start();
  } catch (e) {
    vpx.dispose();
    frameSendPort.send(null); // signal failure
    return;
  }

  frameSendPort.send(true); // signal success

  var running = true;
  var muted = false;
  var forceNextKeyframe = false;
  var seqNum = 0;

  // Listen for commands
  commandPort.listen((msg) {
    if (msg == _CaptureCommand.stop) {
      running = false;
    } else if (msg == _CaptureCommand.forceKeyframe) {
      forceNextKeyframe = true;
    } else if (msg == _CaptureCommand.mute) {
      muted = true;
    } else if (msg == _CaptureCommand.unmute) {
      muted = false;
    }
  });

  // Capture loop
  final frameDurationUs = 1000000 ~/ init.fps;
  final sharedSecret = init.sharedSecret;

  while (running) {
    final startUs = DateTime.now().microsecondsSinceEpoch;

    // Grab frame from camera
    final i420Frame = camera.grabI420Frame();
    if (i420Frame == null || muted) {
      // No frame or muted — sleep for one frame period
      final elapsed = DateTime.now().microsecondsSinceEpoch - startUs;
      final sleepUs = frameDurationUs - elapsed;
      if (sleepUs > 0) {
        // Busy-wait is not ideal but Isolate has no microsleep
        final endTime = DateTime.now().microsecondsSinceEpoch + sleepUs;
        while (DateTime.now().microsecondsSinceEpoch < endTime) {}
      }
      continue;
    }

    // Encode with VP8
    final forceKf = forceNextKeyframe;
    forceNextKeyframe = false;
    final encoded = vpx.encode(i420Frame, forceKeyframe: forceKf);
    if (encoded == null) continue;

    // Encrypt with AES-256-GCM
    final nonce = sodium.generateNonce(); // 12 bytes
    final encrypted = sodium.aesGcmEncrypt(encoded.data, sharedSecret, nonce);

    // Build VideoFrame proto
    final videoFrame = proto.VideoFrame()
      ..sequenceNumber = seqNum++
      ..flags = (encoded.isKeyframe ? 0x01 : 0)
      ..width = init.width
      ..height = init.height
      ..nonce = nonce
      ..encryptedData = encrypted
      ..timestampMs = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;

    // Send serialized proto back to main isolate
    frameSendPort.send(videoFrame.writeToBuffer());

    // Frame rate control
    final elapsed = DateTime.now().microsecondsSinceEpoch - startUs;
    final sleepUs = frameDurationUs - elapsed;
    if (sleepUs > 1000) {
      // Busy-wait for sub-millisecond precision
      final endTime = DateTime.now().microsecondsSinceEpoch + sleepUs;
      while (DateTime.now().microsecondsSinceEpoch < endTime) {}
    }
  }

  // Cleanup
  camera.stop();
  camera.close();
  vpx.dispose();
}

/// Minimal camera wrapper for use inside the capture isolate.
/// Loads libcleona_v4l2.so independently (each isolate needs its own FFI handle).
class _IsolateCameraCapture {
  final int width;
  final int height;
  bool _started = false;

  _IsolateCameraCapture(String device, this.width, this.height, int fps);

  void start() {
    // Load the V4L2 shim — this is a simplified in-isolate loader.
    // The full VideoCaptureLinux class can't be used because it may
    // reference main-isolate state. We use raw FFI calls instead.
    _started = true;
  }

  Uint8List? grabI420Frame() {
    // In the actual implementation, this would call the v4l2 shim FFI functions.
    // For now, return a synthetic I420 frame (gray) for testing.
    // TODO: Wire up actual v4l2 FFI calls when capture isolate is fully integrated.
    if (!_started) return null;
    final i420Size = width * height * 3 ~/ 2;
    final frame = Uint8List(i420Size);
    // Gray frame: Y=128, U=128, V=128
    frame.fillRange(0, width * height, 128);
    frame.fillRange(width * height, i420Size, 128);
    return frame;
  }

  void stop() { _started = false; }
  void close() {}
}

// ── VideoEngine ──────────────────────────────────────────────────────

/// Manages video capture, encoding, decoding, and display for a video call.
class VideoEngine {
  final Uint8List sharedSecret; // 32 bytes AES-256-GCM key
  final CLogger _log;
  final SodiumFFI _sodium;

  // Capture isolate
  Isolate? _captureIsolate;
  SendPort? _captureCommandPort;
  ReceivePort? _frameReceivePort;

  // Decoder (runs in main isolate — decoding is fast enough)
  VpxFFI? _decoder;

  // State
  bool _running = false;
  bool _muted = false;
  final VideoPreset _preset;
  final String _cameraDevice;

  /// Called when an encrypted video frame is ready to send to the peer.
  void Function(Uint8List serializedVideoFrame)? onVideoFrame;

  /// Called when a decoded video frame (RGBA) is ready for display.
  void Function(ui.Image image)? onDecodedFrame;

  /// Called when a decoded I420 frame is available (for testing/alternative rendering).
  void Function(Uint8List i420Data, int width, int height)? onDecodedI420;

  VideoEngine({
    required this.sharedSecret,
    VideoPreset preset = VideoPreset.medium,
    String cameraDevice = '/dev/video0',
    CLogger? log,
  })  : _log = log ?? CLogger('VideoEngine'),
        _sodium = SodiumFFI(),
        _preset = preset,
        _cameraDevice = cameraDevice;

  bool get isRunning => _running;
  bool get isMuted => _muted;
  VideoPreset get preset => _preset;

  /// Start video capture and encoding.
  Future<bool> start() async {
    if (_running) return true;

    // Create decoder for incoming frames
    try {
      _decoder = VpxFFI(
        width: _preset.width,
        height: _preset.height,
        bitrateKbps: _preset.bitrateKbps,
        fps: _preset.fps,
      );
    } catch (e) {
      _log.error('Failed to create VP8 decoder: $e');
      return false;
    }

    // Start capture isolate
    _frameReceivePort = ReceivePort();
    final commandReceivePort = ReceivePort();

    try {
      _captureIsolate = await Isolate.spawn(
        _captureIsolateEntry,
        [
          _CaptureInit(
            frameSendPort: _frameReceivePort!.sendPort,
            sharedSecret: sharedSecret,
            cameraDevice: _cameraDevice,
            width: _preset.width,
            height: _preset.height,
            fps: _preset.fps,
            bitrateKbps: _preset.bitrateKbps,
            keyframeInterval: _preset.fps * 2, // keyframe every 2 seconds
          ),
          commandReceivePort,
        ],
      );
    } catch (e) {
      _log.error('Failed to spawn capture isolate: $e');
      _decoder?.dispose();
      _decoder = null;
      return false;
    }

    _captureCommandPort = commandReceivePort.sendPort;

    // Wait for initialization result
    final completer = Completer<bool>();
    late StreamSubscription sub;
    sub = _frameReceivePort!.listen((msg) {
      if (msg == true) {
        // Init success — switch to frame handling
        if (!completer.isCompleted) completer.complete(true);
        sub.cancel();
        _startFrameListener();
      } else if (msg == null) {
        // Init failure
        if (!completer.isCompleted) completer.complete(false);
        sub.cancel();
      }
    });

    final success = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );

    if (!success) {
      _log.error('Capture isolate failed to initialize');
      stop();
      return false;
    }

    _running = true;
    _log.info('Video engine started (${_preset.label}, ${_preset.bitrateKbps}kbps)');
    return true;
  }

  void _startFrameListener() {
    _frameReceivePort?.listen((msg) {
      if (msg is Uint8List) {
        // Encrypted video frame from capture isolate
        onVideoFrame?.call(msg);
      }
    });
  }

  /// Process an incoming encrypted video frame from the peer.
  void processReceivedFrame(Uint8List serializedFrame) {
    if (!_running || _decoder == null) return;

    try {
      final videoFrame = proto.VideoFrame.fromBuffer(serializedFrame);

      // Decrypt
      final Uint8List decrypted;
      try {
        decrypted = _sodium.aesGcmDecrypt(
          Uint8List.fromList(videoFrame.encryptedData),
          sharedSecret,
          Uint8List.fromList(videoFrame.nonce),
        );
      } catch (_) {
        _log.debug('Video frame decrypt failed (seq=${videoFrame.sequenceNumber})');
        return;
      }

      // Decode VP8 → I420
      final decoded = _decoder!.decode(decrypted);
      if (decoded == null) return;

      // Notify I420 listener (for testing)
      onDecodedI420?.call(decoded.i420Data, decoded.width, decoded.height);

      // Convert I420 → RGBA for Flutter display
      if (onDecodedFrame != null) {
        _i420ToRgbaImage(decoded.i420Data, decoded.width, decoded.height)
            .then((image) {
          if (image != null) onDecodedFrame?.call(image);
        });
      }
    } catch (e) {
      _log.debug('Video frame processing error: $e');
    }
  }

  /// Convert I420 YUV data to a Flutter ui.Image (RGBA8888).
  static Future<ui.Image?> _i420ToRgbaImage(
      Uint8List i420, int width, int height) async {
    final rgba = i420ToRgba(i420, width, height);

    final completer = Completer<ui.Image?>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) => completer.complete(img),
    );
    return completer.future;
  }

  /// Convert I420 (YUV 4:2:0) to RGBA8888.
  /// Exported for testing.
  static Uint8List i420ToRgba(Uint8List i420, int width, int height) {
    final ySize = width * height;
    final uvSize = ySize ~/ 4;
    final rgba = Uint8List(width * height * 4);

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final yIdx = row * width + col;
        final uvIdx = (row ~/ 2) * (width ~/ 2) + (col ~/ 2);

        final y = i420[yIdx] - 16;
        final u = i420[ySize + uvIdx] - 128;
        final v = i420[ySize + uvSize + uvIdx] - 128;

        // ITU-R BT.601 conversion
        var r = ((298 * y + 409 * v + 128) >> 8).clamp(0, 255);
        var g = ((298 * y - 100 * u - 208 * v + 128) >> 8).clamp(0, 255);
        var b = ((298 * y + 516 * u + 128) >> 8).clamp(0, 255);

        final rgbaIdx = (row * width + col) * 4;
        rgba[rgbaIdx] = r;
        rgba[rgbaIdx + 1] = g;
        rgba[rgbaIdx + 2] = b;
        rgba[rgbaIdx + 3] = 255; // alpha
      }
    }
    return rgba;
  }

  /// Force next captured frame to be a keyframe.
  void forceKeyframe() {
    _captureCommandPort?.send(_CaptureCommand.forceKeyframe);
  }

  /// Mute/unmute video capture (sends black frames when muted).
  set muted(bool value) {
    _muted = value;
    _captureCommandPort
        ?.send(value ? _CaptureCommand.mute : _CaptureCommand.unmute);
  }

  /// Stop video engine and release resources.
  void stop() {
    if (!_running && _captureIsolate == null) return;
    _running = false;

    _captureCommandPort?.send(_CaptureCommand.stop);

    // Give the isolate time to clean up, then kill
    Future.delayed(const Duration(milliseconds: 200), () {
      _captureIsolate?.kill(priority: Isolate.immediate);
      _captureIsolate = null;
    });

    _frameReceivePort?.close();
    _frameReceivePort = null;
    _captureCommandPort = null;

    _decoder?.dispose();
    _decoder = null;

    _log.info('Video engine stopped');
  }
}
