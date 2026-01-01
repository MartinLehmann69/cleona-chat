import 'dart:io';

import 'package:cleona/core/config/network_channel.dart';
import 'package:flutter/services.dart';

/// Capture exclusion of the application window (architecture §23.10).
///
/// The native side excludes the window from screen capture before the first
/// frame — Android `FLAG_SECURE` (MainActivity.kt), Windows
/// `WDA_EXCLUDEFROMCAPTURE` (flutter_window.cpp), macOS
/// `NSWindow.sharingType = .none` (MainFlutterWindow.swift), iOS covers the
/// content while the screen is captured and in the app switcher
/// (SceneDelegate.swift). Linux excludes nothing (§23.10).
///
/// One switch turns it off, and only the test run sets it, because the E2E
/// guideline verifies by screenshot (§28.1). Android reads its switch
/// natively (system property `debug.cleona.capture`). Everywhere else the
/// test run starts the application with `CLEONA_CAPTURE=1`, and this class
/// asks the native side to lift the exclusion. Where every program of the
/// same user can set a process environment (Windows, macOS), the switch is
/// honoured only in beta builds; on iOS no other application can set it,
/// so the live build honours it too (§23.10).
class CaptureExclusion {
  static const MethodChannel _channel = MethodChannel('chat.cleona/capture');

  /// Name of the environment variable the test run sets.
  static const String testSwitch = 'CLEONA_CAPTURE';

  /// Whether this platform excludes the window from capture, so that the
  /// application offers its own screenshot instead (§23.10).
  static bool get excludesWindow =>
      Platform.isAndroid || Platform.isWindows || Platform.isMacOS;

  /// Whether the test switch lifts the exclusion on [platform] for a build
  /// of [channel] with process environment [env]. Android is not handled
  /// here (native system property).
  static bool switchHonoured({
    required String platform,
    required NetworkChannel channel,
    required Map<String, String> env,
  }) {
    if (env[testSwitch] != '1') return false;
    switch (platform) {
      case 'windows':
      case 'macos':
        return channel == NetworkChannel.beta;
      case 'ios':
        return true;
      default:
        return false;
    }
  }

  /// Lifts the exclusion when the test switch is set and honoured on this
  /// platform. Called once at start, after the binding exists.
  static Future<bool> applyTestSwitch() async {
    final platform = Platform.operatingSystem;
    if (!switchHonoured(
        platform: platform,
        channel: activeNetworkChannel,
        env: Platform.environment)) {
      return false;
    }
    try {
      await _channel.invokeMethod<void>('allowCapture');
      return true;
    } on MissingPluginException {
      return false;
    }
  }
}
