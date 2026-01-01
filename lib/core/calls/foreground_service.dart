// Bug #U10b — Android foreground-service mic-type promotion bridge.
//
// API 34+ enforces that a foreground service holding an AudioRecord stream
// must declare foregroundServiceType=microphone (alone or in a bitmask) at
// the moment startForeground() was last called. CleonaForegroundService
// declares dataSync|microphone in the manifest, but we only re-startForeground
// with the MICROPHONE bit set during an actual call so the OS doesn't show
// the persistent "microphone in use" indicator while idle.
//
// On non-Android platforms this is a no-op.
//
// Conditional export so `dart compile exe` (daemon, no dart.library.ui)
// uses the pure-Dart stub instead of pulling in package:flutter/services.
export 'foreground_service_stub.dart'
    if (dart.library.ui) 'foreground_service_flutter.dart';
