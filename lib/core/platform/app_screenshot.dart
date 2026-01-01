import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The result of the application's own screenshot function.
class AppScreenshotResult {
  final bool saved;
  final String? uri;
  final String? error;

  AppScreenshotResult._({required this.saved, this.uri, this.error});

  factory AppScreenshotResult.saved(String uri) =>
      AppScreenshotResult._(saved: true, uri: uri);

  factory AppScreenshotResult.failure(String code) =>
      AppScreenshotResult._(saved: false, error: code);

  factory AppScreenshotResult.notAvailable() =>
      AppScreenshotResult._(saved: false, error: 'NOT_AVAILABLE');
}

/// The application's own screenshot (§23.10).
///
/// The picture is made HERE, from the application's own drawing: the whole
/// application sits under one [RepaintBoundary] ([boundaryKey], placed in
/// `main.dart`), and its layer is turned into an image. That is independent
/// of the capture exclusion of the window — the exclusion keeps OTHER
/// programs from reading the window, this reads nothing back from it — and
/// it is the same on every platform. Only the saving into the user's picture
/// collection is the platform's part.
///
/// Reading the window back on the native side is not a way: Flutter draws
/// into a surface of its own, and a copy of the Android activity window is
/// an empty picture (measured on the emulator, API 35, 03.10.2026).
class AppScreenshot {
  static const MethodChannel _channel = MethodChannel('chat.cleona/screenshot');

  /// Key of the one [RepaintBoundary] around the application.
  static final GlobalKey boundaryKey = GlobalKey(debugLabel: 'app-screenshot');

  /// Whether this platform offers the function: where the window is
  /// excluded from capture AND the saving side is built. Android today;
  /// Windows and macOS follow with their capture exclusion. Linux excludes
  /// nothing (§23.10), the system's own screenshot works there.
  static bool get isOffered => Platform.isAndroid;

  /// PNG of what the application shows right now, in device pixels, or null
  /// when the boundary is not in the tree.
  static Future<Uint8List?> renderPng() async {
    final context = boundaryKey.currentContext;
    final boundary = context?.findRenderObject();
    if (context == null || boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(
        pixelRatio: View.of(context).devicePixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  /// Makes the picture and saves it as `Pictures/Cleona/cleona_<time>.png`.
  ///
  /// Returns [AppScreenshotResult.saved] with the `content://` URI on success,
  /// or [AppScreenshotResult.failure] with a stable error code on failure.
  static Future<AppScreenshotResult> capture() async {
    if (!isOffered) return AppScreenshotResult.notAvailable();
    try {
      final png = await renderPng();
      if (png == null || png.isEmpty) {
        return AppScreenshotResult.failure('NO_PICTURE');
      }
      final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'savePng',
        {'png': png},
      );
      final uri = response?['uri'] as String?;
      if (uri != null && uri.isNotEmpty) return AppScreenshotResult.saved(uri);
      return AppScreenshotResult.failure('NO_URI');
    } on PlatformException catch (e) {
      return AppScreenshotResult.failure(e.code);
    } catch (e) {
      return AppScreenshotResult.failure('UNKNOWN: $e');
    }
  }
}
