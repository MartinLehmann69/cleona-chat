/// Android camera capture via CameraX Platform Channel.
///
/// Uses the native CameraX API (Kotlin) to capture YUV frames,
/// converts them to I420, and delivers them to the VideoEngine.
/// Communicates with CameraXHandler.kt via MethodChannel.
library;

import 'package:flutter/services.dart';

/// Android camera capture controller.
///
/// Usage:
/// ```dart
/// final cam = VideoCaptureAndroid();
/// cam.onFrame = (i420, width, height) { /* process frame */ };
/// await cam.start(width: 640, height: 480);
/// await cam.switchCamera();
/// await cam.stop();
/// ```
class VideoCaptureAndroid {
  static const _channel = MethodChannel('chat.cleona/camera');

  bool _capturing = false;

  /// Called when a new I420 frame arrives from the camera.
  void Function(Uint8List i420Data, int width, int height)? onFrame;

  VideoCaptureAndroid() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (call.method == 'onFrame') {
      final args = call.arguments as Map;
      final data = args['data'] as Uint8List;
      final width = args['width'] as int;
      final height = args['height'] as int;
      onFrame?.call(data, width, height);
    }
  }

  /// Check if a camera is available on this device.
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Request camera permission.
  /// Returns true if already granted, false if permission dialog was shown.
  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Start camera capture.
  /// [facing]: "front" or "back" (default: "front").
  Future<bool> start({
    int width = 640,
    int height = 480,
    String facing = 'front',
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('startCapture', {
        'width': width,
        'height': height,
        'facing': facing,
      });
      _capturing = result ?? false;
      return _capturing;
    } catch (_) {
      return false;
    }
  }

  /// Stop camera capture.
  Future<void> stop() async {
    _capturing = false;
    try {
      await _channel.invokeMethod('stopCapture');
    } catch (_) {
      // Ignore errors on stop
    }
  }

  /// Switch between front and back camera.
  Future<bool> switchCamera() async {
    try {
      final result = await _channel.invokeMethod<bool>('switchCamera');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get isCapturing => _capturing;

  /// Dispose and stop listening.
  void dispose() {
    _capturing = false;
    _channel.setMethodCallHandler(null);
  }
}
