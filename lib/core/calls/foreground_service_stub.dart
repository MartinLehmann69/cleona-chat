// Stub for daemon / pure-Dart contexts that don't link Flutter. The
// foreground-service-type promotion is meaningless outside of an Android
// embedder, so both methods are no-ops. Selected via conditional export
// in foreground_service.dart when `dart.library.ui` is NOT available.

class ForegroundServiceControl {
  ForegroundServiceControl._();

  static Future<void> promoteForCall() async {}

  static Future<void> demoteAfterCall() async {}
}
