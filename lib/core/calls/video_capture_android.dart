/// Camera capture via the shared `chat.cleona/camera` Platform Channel.
///
/// Despite the class name, this wrapper is platform-neutral: it only
/// speaks the MethodChannel contract (isAvailable/requestPermission/
/// startCapture/stopCapture/switchCamera + the "onFrame" callback with
/// I420 bytes + width/height), not any Android-specific API. On Android
/// the channel is served by CameraXHandler.kt (CameraX); on iOS it is
/// served by CameraHandler.swift (AVFoundation) — both native handlers
/// implement byte-for-byte the same channel name, methods, and frame
/// payload shape, so this one class works unmodified on either platform.
/// See [VideoCaptureIOS] below for an iOS-flavored alias.
library;

import 'package:flutter/services.dart';

/// Camera capture controller (Android: CameraX, iOS: AVFoundation — see
/// library doc comment above for why one class covers both platforms).
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

/// iOS-flavored alias for [VideoCaptureAndroid].
///
/// Deliberately a `typedef`, not a copy: both platforms share the same
/// `chat.cleona/camera` MethodChannel contract (see CameraXHandler.kt on
/// Android and CameraHandler.swift on iOS), so duplicating the class would
/// just be two implementations to keep in sync for zero behavioral
/// difference. Call sites that want the platform-appropriate name (e.g.
/// an `if (Platform.isIOS) VideoCaptureIOS() else VideoCaptureAndroid()`
/// factory) can use this without depending on the Android-specific name.
typedef VideoCaptureIOS = VideoCaptureAndroid;
