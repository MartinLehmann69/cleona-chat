// Flutter-bound implementation: queries `getAudioDiagnostics` over the
// existing `chat.cleona/audio` MethodChannel (AudioDiagnostics.kt on the
// Android side) and folds the result into one greppable log line.
// No-op on every non-Android platform. Selected via the conditional export
// in android_audio_diagnostics.dart when `dart.library.ui` IS available.
import 'dart:io';

import 'package:flutter/services.dart';

class AndroidAudioDiagnostics {
  AndroidAudioDiagnostics._();

  static const MethodChannel _channel = MethodChannel('chat.cleona/audio');

  /// Collects the platform AEC/NS state and renders it as a single line.
  ///
  /// Returns null on non-Android platforms and whenever the platform side is
  /// unreachable — the caller then simply logs nothing. Purely diagnostic:
  /// no effect is created on the live capture session, nothing is switched.
  ///
  /// [probe] additionally opens (but never starts) a throwaway AudioRecord on
  /// the `VOICE_COMMUNICATION` source to read the platform's *default* AEC/NS
  /// enable state. Call this BEFORE the native engine opens its capture
  /// device so the probe session is long gone by then.
  ///
  /// What the line answers:
  ///  - `available`  — does the device offer a platform AEC at all
  ///  - `impl`       — which implementation (vendor HAL vs. AOSP software)
  ///  - `defaultOn`  — would the platform auto-enable it for a
  ///                   voice_communication capture session on this device
  ///  - `mode` / `speaker` / `nativeRate` / `framesPerBuffer` / `lowLatency`
  ///                 — the routing + fast-path context the streams were
  ///                   opened in
  ///
  /// What it does NOT answer (`active=unknown`): whether the AEC is attached
  /// to the stream miniaudio actually opened. miniaudio requests
  /// AAUDIO_SESSION_ID_NONE, so that stream has no session id reachable from
  /// Java/Kotlin and no public API enumerates effects on a foreign stream.
  static Future<String?> summarize({bool probe = true}) async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getAudioDiagnostics',
        {'probe': probe},
      );
      if (raw == null) return null;
      final d = <String, Object?>{
        for (final e in raw.entries) '${e.key}': e.value,
      };
      return _format(d);
    } catch (_) {
      // MissingPluginException (no Activity engine), or platform failure.
      return null;
    }
  }

  static String _format(Map<String, Object?> d) {
    final b = StringBuffer('Android AEC:');
    b.write(' available=${d['aecAvailable']}');
    // `active` is intentionally hard-coded: it is not observable, and an
    // omitted field would read as "forgot to log it" instead of "cannot know".
    b.write(' active=unknown(native-stream-has-no-session-id)');
    if (d.containsKey('aecDefaultOn')) {
      b.write(' defaultOnProbe=${d['aecDefaultOn']}');
    }
    if (d['aecImpl'] != null) b.write(' impl=${d['aecImpl']}');
    b.write(' nsAvailable=${d['nsAvailable']}');
    if (d.containsKey('nsDefaultOn')) {
      b.write(' nsDefaultOnProbe=${d['nsDefaultOn']}');
    }
    if (d['nsImpl'] != null) b.write(' nsImpl=${d['nsImpl']}');
    b.write(' mode=${d['mode']}');
    b.write(' speaker=${d['speakerphoneOn']}');
    b.write(' micMute=${d['micMute']}');
    b.write(' nativeRate=${d['nativeOutputSampleRate']}');
    b.write(' framesPerBuffer=${d['outputFramesPerBuffer']}');
    b.write(' lowLatency=${d['featureLowLatencyAudio']}');
    if (d['featureProAudio'] == true) b.write(' proAudio=true');
    if (d['communicationDevice'] != null) {
      b.write(' commDevice=${d['communicationDevice']}');
    }
    if (d['probePermission'] == false) b.write(' probe=no-permission');
    if (d['probeError'] != null) b.write(' probeError=${d['probeError']}');
    if (d['audioManagerError'] != null) {
      b.write(' amError=${d['audioManagerError']}');
    }
    if (d['error'] != null) b.write(' error=${d['error']}');
    // speexdsp AEC runs unconditionally in cleona_audio.c on every platform —
    // logged as a constant so the line alone shows both halves of the chain.
    b.write(' speexAec=on');
    return b.toString();
  }
}
