// ignore_for_file: constant_identifier_names
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';

// ── PulseAudio Simple API FFI ─────────────────────────────────────────────

// pa_sample_format_t
const int _PA_SAMPLE_S16LE = 3;

// pa_stream_direction_t
const int _PA_STREAM_PLAYBACK = 1;
const int _PA_STREAM_RECORD = 2;

// pa_sample_spec struct: { format: uint32, rate: uint32, channels: uint8 }
final class _PaSampleSpec extends Struct {
  @Uint32()
  external int format;
  @Uint32()
  external int rate;
  @Uint8()
  external int channels;
}

// Native function types
typedef _PaSimpleNewNative = Pointer<Void> Function(
    Pointer<Utf8>, // server (NULL)
    Pointer<Utf8>, // name
    Int32, // dir
    Pointer<Utf8>, // dev (NULL)
    Pointer<Utf8>, // stream_name
    Pointer<_PaSampleSpec>, // ss
    Pointer<Void>, // channel_map (NULL)
    Pointer<Void>, // attr (NULL)
    Pointer<Int32> // error
    );
typedef _PaSimpleNewDart = Pointer<Void> Function(
    Pointer<Utf8>,
    Pointer<Utf8>,
    int,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<_PaSampleSpec>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Int32>);

typedef _PaSimpleReadNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Size, Pointer<Int32>);
typedef _PaSimpleReadDart = int Function(
    Pointer<Void>, Pointer<Uint8>, int, Pointer<Int32>);

typedef _PaSimpleWriteNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Size, Pointer<Int32>);
typedef _PaSimpleWriteDart = int Function(
    Pointer<Void>, Pointer<Uint8>, int, Pointer<Int32>);

typedef _PaSimpleFreeNative = Void Function(Pointer<Void>);
typedef _PaSimpleFreeDart = void Function(Pointer<Void>);

typedef _PaSimpleDrainNative = Int32 Function(
    Pointer<Void>, Pointer<Int32>);
typedef _PaSimpleDrainDart = int Function(Pointer<Void>, Pointer<Int32>);

// ── Capture Isolate ───────────────────────────────────────────────────────

/// Message sent from main isolate to capture isolate to initialize it.
class _CaptureInit {
  final SendPort frameSendPort; // Send encrypted frames back to main
  final Uint8List sharedSecret; // AES-256 key
  _CaptureInit(this.frameSendPort, this.sharedSecret);
}

/// Commands sent from main isolate to control the capture isolate.
enum _CaptureCommand { mute, unmute, stop }

/// Top-level function that runs in the capture isolate.
/// Owns its own PulseAudio record handle and SodiumFFI instance.
void _captureIsolateEntry(List<dynamic> args) {
  final init = args[0] as _CaptureInit;
  final commandPort = args[1] as ReceivePort;

  // FFI setup (each isolate needs its own)
  final lib = DynamicLibrary.open('libpulse-simple.so.0');
  final paNew = lib.lookupFunction<_PaSimpleNewNative, _PaSimpleNewDart>(
      'pa_simple_new');
  final paRead = lib.lookupFunction<_PaSimpleReadNative, _PaSimpleReadDart>(
      'pa_simple_read');
  final paFree = lib.lookupFunction<_PaSimpleFreeNative, _PaSimpleFreeDart>(
      'pa_simple_free');

  final sodium = SodiumFFI();
  final frameSendPort = init.frameSendPort;
  final sharedSecret = init.sharedSecret;

  // Open PulseAudio record stream
  final spec = calloc<_PaSampleSpec>();
  spec.ref.format = _PA_SAMPLE_S16LE;
  spec.ref.rate = AudioEngine.sampleRate;
  spec.ref.channels = AudioEngine.channels;

  final err = calloc<Int32>();
  final appName = 'Cleona'.toNativeUtf8();
  final recName = 'capture'.toNativeUtf8();

  final recordHandle = paNew(
    nullptr.cast(), appName, _PA_STREAM_RECORD,
    nullptr.cast(), recName, spec,
    nullptr, nullptr, err,
  );

  calloc.free(spec);
  calloc.free(err);
  calloc.free(appName);
  calloc.free(recName);

  if (recordHandle == nullptr) {
    // Signal failure — send null to indicate capture failed
    frameSendPort.send(null);
    return;
  }

  // Signal success
  frameSendPort.send(true);

  var running = true;
  var muted = false;
  var seqNum = 0;

  // Listen for commands from main isolate
  commandPort.listen((message) {
    if (message == _CaptureCommand.stop) {
      running = false;
    } else if (message == _CaptureCommand.mute) {
      muted = true;
    } else if (message == _CaptureCommand.unmute) {
      muted = false;
    }
  });

  // Capture loop — blocking pa_simple_read is fine here, we're in our own isolate
  final buf = calloc<Uint8>(AudioEngine.frameSize);
  final readErr = calloc<Int32>();

  while (running) {
    final rc = paRead(recordHandle, buf, AudioEngine.frameSize, readErr);
    if (rc < 0 || !running) break;

    if (!muted) {
      // Read PCM data
      final pcmData = Uint8List.fromList(buf.asTypedList(AudioEngine.frameSize));

      // Encrypt frame: [4-byte seqNum] [12-byte nonce] [ciphertext+tag]
      final seqBytes = Uint8List(4);
      ByteData.sublistView(seqBytes).setUint32(0, seqNum++, Endian.big);

      final nonce = sodium.generateNonce(); // 12 bytes
      final ciphertext = sodium.aesGcmEncrypt(pcmData, sharedSecret, nonce);

      final packet = Uint8List(4 + 12 + ciphertext.length);
      packet.setAll(0, seqBytes);
      packet.setAll(4, nonce);
      packet.setAll(16, ciphertext);

      frameSendPort.send(packet);
    }
  }

  // Cleanup
  calloc.free(buf);
  calloc.free(readErr);
  paFree(recordHandle);
}

// ── AudioEngine ───────────────────────────────────────────────────────────

/// Audio engine using PulseAudio Simple API for Linux.
///
/// Captures microphone audio at 16 kHz mono 16-bit PCM in a separate isolate,
/// encrypts each 20ms frame (640 bytes) with AES-256-GCM,
/// and provides encrypted frames for sending over UDP.
/// Incoming encrypted frames are decrypted and played back in the main isolate.
class AudioEngine {
  final Uint8List sharedSecret; // 32 bytes AES-256 key
  final CLogger _log;
  final SodiumFFI _sodium = SodiumFFI();

  // PulseAudio playback handle (main isolate only)
  Pointer<Void>? _playHandle;

  // FFI functions (main isolate — playback only)
  late final _PaSimpleNewDart _paNew;
  late final _PaSimpleWriteDart _paWrite;
  late final _PaSimpleFreeDart _paFree;
  late final _PaSimpleDrainDart _paDrain;

  // Capture isolate state
  Isolate? _captureIsolate;
  SendPort? _captureCommandPort;
  ReceivePort? _frameReceivePort;
  StreamSubscription? _frameSubscription;

  // State
  bool _running = false;
  bool _muted = false;
  bool _speakerEnabled = true;

  // Callback: encrypted audio frame ready to send
  void Function(Uint8List encryptedFrame)? onAudioFrame;

  // Audio parameters
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bytesPerSample = 2; // 16-bit
  static const int frameDurationMs = 20;
  static const int frameSize =
      sampleRate * channels * bytesPerSample * frameDurationMs ~/ 1000; // 640 bytes

  AudioEngine({
    required this.sharedSecret,
    required String profileDir,
  }) : _log = CLogger.get('audio', profileDir: profileDir) {
    if (!Platform.isLinux) {
      throw UnsupportedError('AudioEngine currently only supports Linux');
    }
    _initFfi();
  }

  void _initFfi() {
    final lib = DynamicLibrary.open('libpulse-simple.so.0');

    _paNew = lib.lookupFunction<_PaSimpleNewNative, _PaSimpleNewDart>(
        'pa_simple_new');
    _paWrite = lib.lookupFunction<_PaSimpleWriteNative, _PaSimpleWriteDart>(
        'pa_simple_write');
    _paFree = lib.lookupFunction<_PaSimpleFreeNative, _PaSimpleFreeDart>(
        'pa_simple_free');
    _paDrain = lib.lookupFunction<_PaSimpleDrainNative, _PaSimpleDrainDart>(
        'pa_simple_drain');
  }

  Pointer<_PaSampleSpec> _createSampleSpec() {
    final spec = calloc<_PaSampleSpec>();
    spec.ref.format = _PA_SAMPLE_S16LE;
    spec.ref.rate = sampleRate;
    spec.ref.channels = channels;
    return spec;
  }

  /// Start audio capture (in isolate) and playback.
  Future<bool> start() async {
    if (_running) return true;

    // Open playback stream in main isolate
    final spec = _createSampleSpec();
    final err = calloc<Int32>();
    final appName = 'Cleona'.toNativeUtf8();
    final playName = 'playback'.toNativeUtf8();

    try {
      _playHandle = _paNew(
        nullptr.cast(),
        appName,
        _PA_STREAM_PLAYBACK,
        nullptr.cast(),
        playName,
        spec,
        nullptr,
        nullptr,
        err,
      );
      if (_playHandle == null || _playHandle == nullptr) {
        _log.error('PulseAudio playback open failed: error=${err.value}');
        return false;
      }
    } finally {
      calloc.free(spec);
      calloc.free(err);
      calloc.free(appName);
      calloc.free(playName);
    }

    // Start capture isolate
    final started = await _startCaptureIsolate();
    if (!started) {
      _log.error('Capture isolate failed to start');
      _paFree(_playHandle!);
      _playHandle = null;
      return false;
    }

    _running = true;
    _log.info('Audio engine started (capture in isolate)');
    return true;
  }

  Future<bool> _startCaptureIsolate() async {
    _frameReceivePort = ReceivePort();
    final commandReceivePort = ReceivePort();

    final init = _CaptureInit(_frameReceivePort!.sendPort, sharedSecret);

    // Wait for the isolate to signal success/failure
    final readyCompleter = Completer<bool>();
    var firstMessage = true;

    _frameSubscription = _frameReceivePort!.listen((message) {
      if (firstMessage) {
        firstMessage = false;
        // First message is success indicator (true) or failure (null)
        readyCompleter.complete(message == true);
        return;
      }
      // Subsequent messages are encrypted audio frames
      if (message is Uint8List) {
        onAudioFrame?.call(message);
      }
    });

    _captureIsolate = await Isolate.spawn(
      _captureIsolateEntry,
      [init, commandReceivePort],
    );

    _captureCommandPort = commandReceivePort.sendPort;

    // Wait for capture isolate to open PulseAudio
    final ok = await readyCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );

    if (!ok) {
      _captureIsolate?.kill();
      _captureIsolate = null;
      _frameSubscription?.cancel();
      _frameReceivePort?.close();
      commandReceivePort.close();
      return false;
    }

    // Apply current mute state
    if (_muted) {
      _captureCommandPort?.send(_CaptureCommand.mute);
    }

    return true;
  }

  /// Play received encrypted audio frame.
  void playFrame(Uint8List encryptedFrame) {
    if (!_running || _playHandle == null) return;
    if (!_speakerEnabled) return;

    final pcmData = _decryptFrame(encryptedFrame);
    if (pcmData == null) return;

    final buf = calloc<Uint8>(pcmData.length);
    final err = calloc<Int32>();

    try {
      buf.asTypedList(pcmData.length).setAll(0, pcmData);
      final rc = _paWrite(_playHandle!, buf, pcmData.length, err);
      if (rc < 0) {
        _log.debug('pa_simple_write error: ${err.value}');
      }
    } finally {
      calloc.free(buf);
      calloc.free(err);
    }
  }

  /// Decrypt an audio frame packet.
  Uint8List? _decryptFrame(Uint8List packet) {
    if (packet.length < 16 + cryptoAeadAes256GcmABytes) return null;

    try {
      // Skip seqNum(4), extract nonce(12), then ciphertext
      final nonce = Uint8List.sublistView(packet, 4, 16);
      final ciphertext = Uint8List.sublistView(packet, 16);
      return _sodium.aesGcmDecrypt(ciphertext, sharedSecret, nonce);
    } catch (e) {
      _log.debug('Audio decrypt failed: $e');
      return null;
    }
  }

  /// Stop audio engine.
  void stop() {
    if (!_running) return;
    _running = false;

    // Stop capture isolate
    _captureCommandPort?.send(_CaptureCommand.stop);
    _captureIsolate?.kill(priority: Isolate.beforeNextEvent);
    _captureIsolate = null;
    _captureCommandPort = null;
    _frameSubscription?.cancel();
    _frameReceivePort?.close();

    final err = calloc<Int32>();
    try {
      if (_playHandle != null) {
        _paDrain(_playHandle!, err);
        _paFree(_playHandle!);
        _playHandle = null;
      }
    } finally {
      calloc.free(err);
    }

    _log.info('Audio engine stopped');
  }

  bool get isRunning => _running;

  /// Mikrofon stummschalten/aktivieren.
  bool get isMuted => _muted;
  set muted(bool value) {
    _muted = value;
    _captureCommandPort?.send(value ? _CaptureCommand.mute : _CaptureCommand.unmute);
    _log.info('Microphone ${value ? "muted" : "unmuted"}');
  }

  /// Lautsprecher ein-/ausschalten.
  bool get isSpeakerEnabled => _speakerEnabled;
  set speakerEnabled(bool value) {
    _speakerEnabled = value;
    _log.info('Speaker ${value ? "enabled" : "disabled"}');
  }
}
