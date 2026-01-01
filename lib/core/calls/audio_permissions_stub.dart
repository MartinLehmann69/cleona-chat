// Stub for daemon / pure-Dart contexts that don't link Flutter. RECORD_AUDIO
// is irrelevant on Linux/Windows daemons (no Android-style runtime perms),
// so both methods short-circuit to true. Selected via conditional export
// in audio_permissions.dart when `dart.library.ui` is NOT available.

class AudioPermissions {
  AudioPermissions._();

  static Future<bool> hasRecordAudio() async => true;

  static Future<bool> requestRecordAudio() async => true;
}
