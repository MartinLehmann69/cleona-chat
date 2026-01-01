// Flutter-bound implementation: forwards promote/demote over the
// `chat.cleona/foreground_service` MethodChannel on Android, no-op
// elsewhere. Selected via conditional export in foreground_service.dart
// when `dart.library.ui` IS available.
import 'dart:io';

import 'package:flutter/services.dart';

class ForegroundServiceControl {
  ForegroundServiceControl._();

  static const MethodChannel _channel =
      MethodChannel('chat.cleona/foreground_service');

  /// Re-call startForeground with type bitmask DATA_SYNC|MICROPHONE so the
  /// OS allows the mic stream and shows the mic-in-use indicator. Must be
  /// called BEFORE the AudioEngine opens its capture device on API 34+.
  static Future<void> promoteForCall() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('promoteForCall');
    } catch (_) {
      // Non-fatal — older API levels or service not yet running.
    }
  }

  /// Demote back to plain DATA_SYNC after the call ends so the OS removes
  /// the mic-in-use indicator.
  static Future<void> demoteAfterCall() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('demoteAfterCall');
    } catch (_) {
      // Non-fatal.
    }
  }
}
