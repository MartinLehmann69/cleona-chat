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

import 'package:flutter/material.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/platform/app_screenshot.dart';

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

    if (!forwardingAllowed) {
      messenger.showSnackBar(
        SnackBar(content: Text(locale.get('screenshot_refused_forwarding'))),
      );
      return;
    }

    final capture = debugCaptureOverride ?? AppScreenshot.capture;
    final result = await capture();
    if (!context.mounted) return;

    messenger.showSnackBar(SnackBar(
      content: Text(locale.get(result.saved && result.uri != null
          ? 'screenshot_saved'
          : 'screenshot_failed')),
    ));
  }
}
