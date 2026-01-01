// S281 — read-only introspection of the Android platform AEC/NS stack.
//
// Background: since S278 the native audio shim asks AAudio/OpenSL for the
// `voice_communication` input preset, i.e. it *requests* the platform echo
// canceller, while speexdsp AEC keeps running on top of it in
// `native/cleona_audio/cleona_audio.c`. Whether the HAL AEC actually engages
// was never observable from the app, so the question "are we cancelling twice"
// could not be decided. This bridge makes the observable part of that question
// answerable from a single real call — it changes no behaviour whatsoever.
//
// Conditional export so `dart compile exe` (daemon, no dart.library.ui) uses
// the pure-Dart stub instead of pulling in package:flutter/services.
export 'android_audio_diagnostics_stub.dart'
    if (dart.library.ui) 'android_audio_diagnostics_flutter.dart';
