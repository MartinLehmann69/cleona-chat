// ignore_for_file: constant_identifier_names
import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/calls/audio_engine_shim.dart';

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
/// Owns its own AudioEngineShim handle and SodiumFFI instance.
void _captureIsolateEntry(_CaptureInit init) {
  // Bug 2026-04-26: previously the parent created the command ReceivePort and
  // tried to send it across `Isolate.spawn` — newer Dart SDKs reject this
  // ("object is unsendable - _ReceivePortImpl"). The receive-port has to live
  // in the isolate that owns it. So the child now creates its own command RX
  // and ships its SendPort back to the parent as the first wire message; the
  // ready-flag follows as the second message before any audio frames.
  final commandPort = ReceivePort();
  final frameSendPort = init.frameSendPort;
  frameSendPort.send(commandPort.sendPort);

  final shim = AudioEngineShim.load();
  final engine = shim.create(
    sampleRate: AudioEngine.sampleRate,
    channels: AudioEngine.channels,
    frameSamples: AudioEngine.samplesPerFrame,
    ringCapacityFrames: 8,
  );
  if (engine.address == 0) {
    frameSendPort.send(null);
    commandPort.close();
    return;
  }

  final startRc = shim.start(engine);
  if (startRc != 0) {
    shim.destroy(engine);
    frameSendPort.send(null);
    commandPort.close();
    return;
  }

  final sodium = SodiumFFI();
  final sharedSecret = init.sharedSecret;

  // Signal success (second handshake message after the SendPort)
  frameSendPort.send(true);

  var running = true;
  var muted = false;
  var seqNum = 0;

  commandPort.listen((message) {
    if (message == _CaptureCommand.stop) {
      running = false;
    } else if (message == _CaptureCommand.mute) {
      muted = true;
      shim.setMute(engine, true);
    } else if (message == _CaptureCommand.unmute) {
      muted = false;
      shim.setMute(engine, false);
    }
  });

  // Allocate one PCM buffer (320 int16 samples = 640 bytes)
  final pcmPtr = calloc<Int16>(AudioEngine.samplesPerFrame);

  while (running) {
    final r = shim.captureRead(engine, pcmPtr, /*timeout_ms*/ 100);
    if (r == -1) break; // engine stopped
    if (r == 0) continue; // timeout — retry

    if (!muted) {
      // Read PCM data — view it as Uint8List for AES-GCM
      final pcmData = Uint8List.fromList(
          pcmPtr.cast<Uint8>().asTypedList(AudioEngine.frameSize));

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
  calloc.free(pcmPtr);
  shim.stop(engine);
  shim.destroy(engine);
}

// ── AudioEngine ───────────────────────────────────────────────────────────

/// Audio engine using the cross-platform cleona_audio shim
/// (miniaudio + speex AEC/NS).
///
/// Captures microphone audio at 16 kHz mono 16-bit PCM in a separate isolate,
/// encrypts each 20ms frame (640 bytes) with AES-256-GCM, and provides
/// encrypted frames for sending over UDP. Incoming encrypted frames are
/// decrypted and pushed to the playback ring in the main isolate.
class AudioEngine {
  final Uint8List sharedSecret; // 32 bytes AES-256 key
  final CLogger _log;
  final SodiumFFI _sodium = SodiumFFI();

  // Shim handle (main isolate — playback only; capture-isolate has its own)
  late final AudioEngineShim _shim;
  Pointer<CleonaAudioEngine>? _engine;

  // Capture isolate state
  Isolate? _captureIsolate;
  SendPort? _captureCommandPort;
  ReceivePort? _frameReceivePort;
  StreamSubscription? _frameSubscription;

  // Pre-allocated playback buffer (reused per frame to avoid alloc churn)
  Pointer<Int16>? _playbackPcmPtr;

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
  static const int samplesPerFrame =
      sampleRate * channels * frameDurationMs ~/ 1000; // 320
  static const int frameSize = samplesPerFrame * bytesPerSample; // 640

  AudioEngine({
    required this.sharedSecret,
    required String profileDir,
  }) : _log = CLogger.get('audio', profileDir: profileDir) {
    _shim = AudioEngineShim.load();
  }

  /// Start audio capture (in isolate) and playback (in main isolate).
  Future<bool> start() async {
    if (_running) return true;

    // Open playback engine in main isolate
    _engine = _shim.create(
      sampleRate: sampleRate,
      channels: channels,
      frameSamples: samplesPerFrame,
      ringCapacityFrames: 8,
    );
    if (_engine == null || _engine!.address == 0) {
      _log.error('cleona_audio_create failed');
      return false;
    }
    final startRc = _shim.start(_engine!);
    if (startRc != 0) {
      _log.error('cleona_audio_start failed: rc=$startRc');
      _shim.destroy(_engine!);
      _engine = null;
      return false;
    }

    _playbackPcmPtr = calloc<Int16>(samplesPerFrame);

    // Start capture isolate (which has its OWN shim handle)
    final ok = await _startCaptureIsolate();
    if (!ok) {
      _log.error('Capture isolate failed to start');
      _shim.stop(_engine!);
      _shim.destroy(_engine!);
      _engine = null;
      calloc.free(_playbackPcmPtr!);
      _playbackPcmPtr = null;
      return false;
    }

    _running = true;
    _log.info(
        'Audio engine started (cross-platform shim, capture in isolate)');
    return true;
  }

  Future<bool> _startCaptureIsolate() async {
    _frameReceivePort = ReceivePort();
    final init = _CaptureInit(_frameReceivePort!.sendPort, sharedSecret);

    // Two-stage handshake: child sends back its command SendPort first,
    // then a ready-flag (true/null), then audio frames. See the
    // _captureIsolateEntry comment for the rationale.
    final commandPortCompleter = Completer<SendPort>();
    final readyCompleter = Completer<bool>();

    _frameSubscription = _frameReceivePort!.listen((message) {
      if (!commandPortCompleter.isCompleted) {
        if (message is SendPort) {
          commandPortCompleter.complete(message);
        } else {
          // Child died before sending the command port.
          commandPortCompleter.completeError(
              StateError('capture isolate did not send command port'));
        }
        return;
      }
      if (!readyCompleter.isCompleted) {
        readyCompleter.complete(message == true);
        return;
      }
      if (message is Uint8List) {
        onAudioFrame?.call(message);
      }
    });

    _captureIsolate = await Isolate.spawn(_captureIsolateEntry, init);

    try {
      _captureCommandPort = await commandPortCompleter.future.timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      _captureIsolate?.kill();
      _captureIsolate = null;
      _frameSubscription?.cancel();
      _frameReceivePort?.close();
      return false;
    }

    final ok = await readyCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    if (!ok) {
      _captureIsolate?.kill();
      _captureIsolate = null;
      _frameSubscription?.cancel();
      _frameReceivePort?.close();
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
    if (!_running || _engine == null || _playbackPcmPtr == null) return;
    if (!_speakerEnabled) return;

    final pcmData = _decryptFrame(encryptedFrame);
    if (pcmData == null) return;
    if (pcmData.length != frameSize) return;

    // Copy decrypted PCM bytes into the int16 pointer
    final byteView = _playbackPcmPtr!.cast<Uint8>().asTypedList(frameSize);
    byteView.setAll(0, pcmData);

    _shim.playbackWrite(_engine!, _playbackPcmPtr!, samplesPerFrame);
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

    if (_engine != null) {
      _shim.stop(_engine!);
      _shim.destroy(_engine!);
      _engine = null;
    }
    if (_playbackPcmPtr != null) {
      calloc.free(_playbackPcmPtr!);
      _playbackPcmPtr = null;
    }

    _log.info('Audio engine stopped');
  }

  bool get isRunning => _running;

  /// Mikrofon stummschalten/aktivieren.
  bool get isMuted => _muted;
  set muted(bool value) {
    _muted = value;
    _captureCommandPort
        ?.send(value ? _CaptureCommand.mute : _CaptureCommand.unmute);
    _log.info('Microphone ${value ? "muted" : "unmuted"}');
  }

  /// Lautsprecher ein-/ausschalten.
  bool get isSpeakerEnabled => _speakerEnabled;
  set speakerEnabled(bool value) {
    _speakerEnabled = value;
    _log.info('Speaker ${value ? "enabled" : "disabled"}');
  }
}
