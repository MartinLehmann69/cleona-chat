// lib/ui/components/app_screenshot_button.dart
//
// §23.10: "Where the window is excluded from capture, the application
// offers a screenshot function of its own. … The button is always shown.
// In a conversation in which forwarding is not allowed (§21.5.4) it takes
// no picture and says instead that a screenshot is not possible because
// forwarding is not allowed there."
//
// One button for every view with a title bar, so that "always shown" does
// not depend on each screen remembering it: `AppBarScaffold` appends it to
// its header row, and every plain `AppBar` lists it among its actions
// (guard: test/smoke/smoke_app_screenshot_everywhere.dart).

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/platform/app_screenshot.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/main.dart' show CleonaAppState;

class AppScreenshotButton extends StatelessWidget {
  /// False in a conversation whose `allow_forwarding` is off (§21.5.4):
  /// the button is still shown, but refuses instead of taking a picture.
  final bool forwardingAllowed;

  const AppScreenshotButton({super.key, this.forwardingAllowed = true});

  /// Stable key for widget tests and the E2E guideline.
  static const ValueKey<String> buttonKey = ValueKey('app-screenshot-button');

  /// Tests only: stands in for the platform decision of
  /// [AppScreenshot.isOffered] (the platforms that exclude the window from
  /// capture: Android, Windows, macOS).
  @visibleForTesting
  static bool? debugOfferedOverride;

  /// Tests only: stands in for [AppScreenshot.capture].
  @visibleForTesting
  static Future<AppScreenshotResult> Function()? debugCaptureOverride;

  /// Tests only: receives the feedback instead of the device
  /// (`saved` = the picture was saved; false = refused or failed).
  @visibleForTesting
  static Future<void> Function(bool saved)? debugFeedbackOverride;

  static bool get offered => debugOfferedOverride ?? AppScreenshot.isOffered;

  @override
  Widget build(BuildContext context) {
    if (!offered) return const SizedBox.shrink();
    final locale = AppLocale.read(context);
    return IconButton(
      key: buttonKey,
      icon: const Icon(Icons.screenshot),
      tooltip: locale.get('screenshot_action'),
      onPressed: () => take(context, forwardingAllowed: forwardingAllowed),
    );
  }

  /// Takes the application's own screenshot, or refuses where forwarding is
  /// not allowed, and tells the user the outcome in their language.
  static Future<void> take(BuildContext context,
      {required bool forwardingAllowed}) async {
    final locale = AppLocale.read(context);
    final messenger = ScaffoldMessenger.of(context);

    final sound = _soundOf(context);

    if (!forwardingAllowed) {
      messenger.showSnackBar(
        SnackBar(content: Text(locale.get('screenshot_refused_forwarding'))),
      );
      await _feedback(sound, saved: false);
      return;
    }

    final capture = debugCaptureOverride ?? AppScreenshot.capture;
    final result = await capture();
    final saved = result.saved && result.uri != null;
    // The feedback comes even if the view went away meanwhile — the
    // picture was taken (or not) either way.
    await _feedback(sound, saved: saved);
    if (!context.mounted) return;

    messenger.showSnackBar(SnackBar(
      content: Text(locale.get(saved ? 'screenshot_saved' : 'screenshot_failed')),
    ));
  }

  /// Felt and heard feedback (S412, owner 05.11.2026: the snackbar alone was
  /// missed, two pictures were taken). Saved: the shutter click — it follows
  /// the app's sound switch and, on Android, the ringer (decision A: silent
  /// or vibrate-only → no click) — and one 40-ms vibration. Refused or
  /// failed: two short vibrations, no click, so the two outcomes feel
  /// different. iOS has the haptic engine instead of the vibrator; the
  /// desktop has no vibration and keeps the click.
  static Future<void> _feedback(NotificationSoundService? sound,
      {required bool saved}) async {
    final override = debugFeedbackOverride;
    if (override != null) return override(saved);
    try {
      if (saved && sound != null) await sound.playScreenshotShutter();
    } catch (_) {}
    try {
      if (Platform.isAndroid) {
        const vibration = MethodChannel('chat.cleona/vibration');
        await vibration.invokeMethod('vibrate', {'duration': 40});
        if (!saved) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await vibration.invokeMethod('vibrate', {'duration': 40});
        }
      } else if (Platform.isIOS) {
        await (saved
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.heavyImpact());
      }
    } catch (_) {}
  }

  /// The sound service of the running app, or null where there is none
  /// (widget tests without the app state).
  static NotificationSoundService? _soundOf(BuildContext context) {
    try {
      return context.read<CleonaAppState>().service?.notificationSound;
    } catch (_) {
      return null;
    }
  }
}
