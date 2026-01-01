// Bug #U10b — Android RECORD_AUDIO runtime-permission bridge.
//
// On Android API 23+, RECORD_AUDIO is a dangerous permission that must be
// granted at runtime. The system permission dialog is owned by the host
// Activity (MainActivity.kt), so this helper forwards has*/request* over
// the `chat.cleona/audio_permissions` MethodChannel and awaits a single
// bool answer.
//
// On non-Android platforms RECORD_AUDIO is not a runtime permission, so we
// short-circuit to true.
//
// Conditional export so `dart compile exe` (daemon, no dart.library.ui)
// uses the pure-Dart stub instead of pulling in package:flutter/services.
export 'audio_permissions_stub.dart'
    if (dart.library.ui) 'audio_permissions_flutter.dart';
