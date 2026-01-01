import 'package:flutter/foundation.dart';

import 'package:cleona/core/log/log_redaction.dart';

/// Routes every `debugPrint` of the Flutter process through [LogRedaction].
///
/// `debugPrint` is a mutable top-level callback of the Flutter framework,
/// and it is not stripped from release builds. The GUI process writes about
/// a hundred lines through it (`lib/main.dart`, the iOS background fetch,
/// several screens) — paths under the home directory, identity names,
/// addresses — and the framework itself reports widget errors through it
/// (`FlutterError.dumpErrorToConsole`). Rebinding the callback once, at the
/// top of the only Flutter entry point (`main()` in `lib/main.dart`), covers
/// every one of those lines including the framework's own, without touching
/// a hundred call sites that a later edit could get wrong again.
///
/// Kept apart from `redacted_console.dart` because the daemon is a pure-Dart
/// binary and must not import `package:flutter` (S299).
///
/// Idempotent: a second call does not wrap the callback twice.
abstract final class RedactedDebugPrint {
  static bool _installed = false;

  /// Whether [install] has run in this process.
  static bool get installed => _installed;

  static void install() {
    if (_installed) return;
    _installed = true;
    final inner = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => inner(
        message == null ? null : LogRedaction.apply(message),
        wrapWidth: wrapWidth);
  }
}
