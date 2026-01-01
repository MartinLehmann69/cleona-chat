import 'dart:io';

import 'package:flutter/services.dart';

import 'package:cleona/core/platform/notification_tap.dart';

/// Picks up the tap on a system notification the native side stashed
/// (Android `MainActivity.handleNotificationTapIntent`, iOS
/// `AppDelegate.userNotificationCenter(_:didReceive:)`), §22.8, D-125 (3).
///
/// Two ways in, so the order "tap ↔ app resumed" does not matter:
///  * the native side calls `notificationTapped` on `chat.cleona/notification`
///    when the engine is running — [install] answers it by draining;
///  * [LifecycleDrainObserver] drains on every resume and once after the
///    first frame (the cold start through a tap).
/// Draining only hands the target on; opening happens on the home screen
/// (`CleonaAppState.runPendingNotificationOpen`).
class NotificationTapReceiver {
  static const _channel = MethodChannel('chat.cleona/notification');

  /// Answers the native `notificationTapped` signal. Android and iOS only.
  static void install(void Function(NotificationTap tap) onTap) {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationTapped') {
        final tap = await consume();
        if (tap != null) onTap(tap);
      }
      return null;
    });
  }

  /// Takes the stashed tap from the native side (it is gone there after
  /// this call). Null when nothing is stashed or the tap opens the app only
  /// ([NotificationTap.fromNative]).
  static Future<NotificationTap?> consume() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return null;
    try {
      final stashed = await _channel
          .invokeMapMethod<Object?, Object?>('consumeNotificationTap');
      return NotificationTap.fromNative(stashed);
    } catch (_) {
      return null;
    }
  }
}
