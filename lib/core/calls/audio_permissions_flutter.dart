// Flutter-bound implementation: forwards has*/request* over the
// `chat.cleona/audio_permissions` MethodChannel on Android, no-op
// elsewhere. Selected via conditional export in audio_permissions.dart
// when `dart.library.ui` IS available (= running under a Flutter
// embedder, GUI process or Android in-process).
import 'dart:io';

import 'package:flutter/services.dart';

class AudioPermissions {
  AudioPermissions._();

  static const MethodChannel _channel =
      MethodChannel('chat.cleona/audio_permissions');

  /// Returns true if RECORD_AUDIO is currently granted. On non-Android
  /// platforms this always returns true (no runtime permission concept).
  static Future<bool> hasRecordAudio() async {
    if (!Platform.isAndroid) return true;
    try {
      final result =
          await _channel.invokeMethod<bool>('hasRecordAudioPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Requests RECORD_AUDIO. If already granted, returns true immediately.
  /// Otherwise the system dialog appears and this future resolves once the
  /// user answers. Returns true on grant, false on deny / cancel / error.
  ///
  /// Concurrent requests are not supported — a second call while the first
  /// is still pending will preempt the first (it resolves with `false`).
  static Future<bool> requestRecordAudio() async {
    if (!Platform.isAndroid) return true;
    try {
      final result =
          await _channel.invokeMethod<bool>('requestRecordAudioPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
