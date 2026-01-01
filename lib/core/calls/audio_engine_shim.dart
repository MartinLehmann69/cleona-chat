// FFI-Bindings für libcleona_audio (miniaudio + speex AEC/NS shim).
// Kapselt die Native-API hinter typsicheren Dart-Methoden.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// Opaque struct
final class CleonaAudioEngine extends Opaque {}

// Stats struct (sizeof = 8*4 + 4*2 = 40 bytes, with potential padding)
final class CleonaAudioStats extends Struct {
  @Int64()
  external int captureFramesTotal;
  @Int64()
  external int captureFramesDropped;
  @Int64()
  external int playbackFramesTotal;
  @Int64()
  external int playbackFramesUnderrun;
  @Int32()
  external int captureBackend;
  @Int32()
  external int playbackBackend;
}

// Native function typedefs
typedef _CreateNative = Pointer<CleonaAudioEngine> Function(
    Int32, Int32, Int32, Int32);
typedef _CreateDart = Pointer<CleonaAudioEngine> Function(
    int, int, int, int);

typedef _StartNative = Int32 Function(Pointer<CleonaAudioEngine>);
typedef _StartDart = int Function(Pointer<CleonaAudioEngine>);

typedef _StopNative = Void Function(Pointer<CleonaAudioEngine>);
typedef _StopDart = void Function(Pointer<CleonaAudioEngine>);

typedef _DestroyNative = Void Function(Pointer<CleonaAudioEngine>);
typedef _DestroyDart = void Function(Pointer<CleonaAudioEngine>);

typedef _CaptureReadNative = Int32 Function(
    Pointer<CleonaAudioEngine>, Pointer<Int16>, Int32);
typedef _CaptureReadDart = int Function(
    Pointer<CleonaAudioEngine>, Pointer<Int16>, int);

typedef _PlaybackWriteNative = Int32 Function(
    Pointer<CleonaAudioEngine>, Pointer<Int16>, Int32);
typedef _PlaybackWriteDart = int Function(
    Pointer<CleonaAudioEngine>, Pointer<Int16>, int);

typedef _SetIntNative = Void Function(Pointer<CleonaAudioEngine>, Int32);
typedef _SetIntDart = void Function(Pointer<CleonaAudioEngine>, int);

typedef _SetSpeakerNative = Int32 Function(Pointer<CleonaAudioEngine>, Int32);
typedef _SetSpeakerDart = int Function(Pointer<CleonaAudioEngine>, int);

typedef _GetStatsNative = Void Function(
    Pointer<CleonaAudioEngine>, Pointer<CleonaAudioStats>);
typedef _GetStatsDart = void Function(
    Pointer<CleonaAudioEngine>, Pointer<CleonaAudioStats>);

class AudioEngineShim {
  // Dart's `ffi` package is referenced here so the import isn't pruned by the
  // analyzer when callers haven't yet exercised the calloc allocator.
  // ignore: unused_field
  static final Allocator _alloc = calloc;

  final DynamicLibrary _lib;

  late final _CreateDart _create;
  late final _StartDart _start;
  late final _StopDart _stop;
  late final _DestroyDart _destroy;
  late final _CaptureReadDart _captureRead;
  late final _PlaybackWriteDart _playbackWrite;
  late final _SetIntDart _setMute;
  late final _SetSpeakerDart _setSpeaker;
  late final _SetIntDart _setAec;
  late final _SetIntDart _setNs;
  late final _SetIntDart _setAgc;
  late final _GetStatsDart _getStats;

  AudioEngineShim._(this._lib) {
    _create = _lib.lookupFunction<_CreateNative, _CreateDart>(
        'cleona_audio_create');
    _start = _lib.lookupFunction<_StartNative, _StartDart>(
        'cleona_audio_start');
    _stop = _lib.lookupFunction<_StopNative, _StopDart>(
        'cleona_audio_stop');
    _destroy = _lib.lookupFunction<_DestroyNative, _DestroyDart>(
        'cleona_audio_destroy');
    _captureRead =
        _lib.lookupFunction<_CaptureReadNative, _CaptureReadDart>(
            'cleona_audio_capture_read');
    _playbackWrite =
        _lib.lookupFunction<_PlaybackWriteNative, _PlaybackWriteDart>(
            'cleona_audio_playback_write');
    _setMute = _lib.lookupFunction<_SetIntNative, _SetIntDart>(
        'cleona_audio_set_mute');
    _setSpeaker = _lib.lookupFunction<_SetSpeakerNative, _SetSpeakerDart>(
        'cleona_audio_set_speaker');
    _setAec = _lib.lookupFunction<_SetIntNative, _SetIntDart>(
        'cleona_audio_set_aec');
    _setNs = _lib.lookupFunction<_SetIntNative, _SetIntDart>(
        'cleona_audio_set_ns');
    _setAgc = _lib.lookupFunction<_SetIntNative, _SetIntDart>(
        'cleona_audio_set_agc');
    _getStats = _lib.lookupFunction<_GetStatsNative, _GetStatsDart>(
        'cleona_audio_get_stats');
  }

  static AudioEngineShim load() {
    final candidates = <String>[];
    if (Platform.isLinux) {
      // 1) Bundled next to the runner (RPATH $ORIGIN/lib resolves this).
      candidates.add('libcleona_audio.so');
      // 2) Explicit fallback: <runner_dir>/lib/libcleona_audio.so for tests
      //    that don't run inside the bundle.
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        candidates.add('$exeDir/lib/libcleona_audio.so');
      } catch (_) {/* ignore */}
      // 3) Build-tree fallback so `dart test` works without installing.
      candidates.add(
          '${Directory.current.path}/native/cleona_audio/build/libcleona_audio.so');
    } else if (Platform.isAndroid) {
      candidates.add('libcleona_audio.so'); // resolved by Android linker
    } else if (Platform.isWindows) {
      candidates.add('cleona_audio.dll');
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        candidates.add('$exeDir\\cleona_audio.dll');
      } catch (_) {/* ignore */}
    } else if (Platform.isMacOS) {
      candidates.add('cleona_audio.dylib');
    } else if (Platform.isIOS) {
      // iOS: cleona_audio ist (sobald gebaut) static-linked via Embedded
      // Framework, im Process-Symbol-Table sichtbar. DynamicLibrary.process()
      // ist die korrekte Variante; .dylib-Pfade fallen auf iOS aus.
      // Build-Pipeline (scripts/build-ios-libs.sh) noch nicht vorhanden,
      // bis dahin schlägt das hier zur Runtime fehl — Audio-Engine inaktiv.
    }
    DynamicLibrary? lib;
    for (final c in candidates) {
      try {
        lib = DynamicLibrary.open(c);
        break;
      } catch (_) {
        // try next
      }
    }
    if (lib == null) {
      throw StateError('libcleona_audio not found. Searched: $candidates');
    }
    return AudioEngineShim._(lib);
  }

  Pointer<CleonaAudioEngine> create({
    required int sampleRate,
    required int channels,
    required int frameSamples,
    required int ringCapacityFrames,
  }) =>
      _create(sampleRate, channels, frameSamples, ringCapacityFrames);

  int start(Pointer<CleonaAudioEngine> e) => _start(e);
  void stop(Pointer<CleonaAudioEngine> e) => _stop(e);
  void destroy(Pointer<CleonaAudioEngine> e) => _destroy(e);

  int captureRead(
          Pointer<CleonaAudioEngine> e, Pointer<Int16> outPcm, int timeoutMs) =>
      _captureRead(e, outPcm, timeoutMs);

  int playbackWrite(
          Pointer<CleonaAudioEngine> e, Pointer<Int16> pcm, int frameSamples) =>
      _playbackWrite(e, pcm, frameSamples);

  void setMute(Pointer<CleonaAudioEngine> e, bool muted) =>
      _setMute(e, muted ? 1 : 0);
  int setSpeaker(Pointer<CleonaAudioEngine> e, bool on) =>
      _setSpeaker(e, on ? 1 : 0);

  void setAec(Pointer<CleonaAudioEngine> e, bool on) => _setAec(e, on ? 1 : 0);
  void setNs(Pointer<CleonaAudioEngine> e, bool on) => _setNs(e, on ? 1 : 0);
  void setAgc(Pointer<CleonaAudioEngine> e, bool on) => _setAgc(e, on ? 1 : 0);

  void getStats(Pointer<CleonaAudioEngine> e, Pointer<CleonaAudioStats> out) =>
      _getStats(e, out);
}
