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
  final int engineAddress; // Shared native engine pointer (direction=0)
  _CaptureInit(this.frameSendPort, this.sharedSecret, this.engineAddress);
}

/// Commands sent from main isolate to control the capture isolate.
enum _CaptureCommand { mute, unmute, stop }

/// Top-level function that runs in the capture isolate.
/// Uses the SHARED native engine (created by main isolate with direction=0)
/// so that AEC has proper far-end reference from the playback ring.
void _captureIsolateEntry(_CaptureInit init) {
  final commandPort = ReceivePort();
  final frameSendPort = init.frameSendPort;
  frameSendPort.send(commandPort.sendPort);

  final shim = AudioEngineShim.load();
  final engine =
      Pointer<CleonaAudioEngine>.fromAddress(init.engineAddress);
  if (engine.address == 0) {
    frameSendPort.send(null);
    commandPort.close();
    return;
  }

  final sodium = SodiumFFI();
  final sharedSecret = init.sharedSecret;

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

  final pcmPtr = calloc<Int16>(AudioEngine.samplesPerFrame);

  while (running) {
    final r = shim.captureRead(engine, pcmPtr, /*timeout_ms*/ 100);
    if (r == -1) break; // engine stopped (ring closed)
    if (r == 0) continue; // timeout — retry

    if (!muted) {
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

  calloc.free(pcmPtr);
  // Engine lifecycle managed by main isolate — do NOT stop/destroy here.
}

// ── AudioEngine ───────────────────────────────────────────────────────────

/// Audio engine using the cross-platform cleona_audio shim
/// (miniaudio + speex AEC/NS).
///
/// A single native engine instance (direction=0, capture+playback) is shared
/// between the main isolate (playback writes) and the capture isolate
/// (capture reads). This ensures the speexdsp AEC has proper far-end
/// reference from the playback ring — required for echo cancellation.
class AudioEngine {
  final Uint8List sharedSecret; // 32 bytes AES-256 key
  final CLogger _log;
  final SodiumFFI _sodium = SodiumFFI();

  // Shim handle — single shared engine for capture+playback (AEC needs both)
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
  /// Both share one native engine (direction=0) so AEC works.
  Future<bool> start() async {
    if (_running) return true;

    // Single engine for both capture and playback — AEC needs the
    // far_end_ring to connect playback output to the capture callback.
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
    final startRc = _shim.startDirected(_engine!, 0);
    if (startRc != 0) {
      _log.error('cleona_audio_start failed: rc=$startRc');
      _shim.destroy(_engine!);
      _engine = null;
      return false;
    }

    _playbackPcmPtr = calloc<Int16>(samplesPerFrame);

    // Capture isolate shares the same native engine via pointer address.
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
        'Audio engine started (shared engine, AEC active)');
    return true;
  }

  Future<bool> _startCaptureIsolate() async {
    _frameReceivePort = ReceivePort();
    final init = _CaptureInit(
      _frameReceivePort!.sendPort,
      sharedSecret,
      _engine!.address,
    );

    final commandPortCompleter = Completer<SendPort>();
    final readyCompleter = Completer<bool>();

    _frameSubscription = _frameReceivePort!.listen((message) {
      if (!commandPortCompleter.isCompleted) {
        if (message is SendPort) {
          commandPortCompleter.complete(message);
        } else {
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

    final byteView = _playbackPcmPtr!.cast<Uint8>().asTypedList(frameSize);
    byteView.setAll(0, pcmData);

    _shim.playbackWrite(_engine!, _playbackPcmPtr!, samplesPerFrame);
  }

  /// Decrypt an audio frame packet.
  Uint8List? _decryptFrame(Uint8List packet) {
    if (packet.length < 16 + cryptoAeadAes256GcmABytes) return null;

    try {
      final nonce = Uint8List.sublistView(packet, 4, 16);
      final ciphertext = Uint8List.sublistView(packet, 16);
      return _sodium.aesGcmDecrypt(ciphertext, sharedSecret, nonce);
    } catch (e) {
      _log.debug('Audio decrypt failed: $e');
      return null;
    }
  }

  /// Stop audio engine.
  /// Shutdown order: close rings (wakes blocked captureRead) → wait for
  /// capture isolate exit → destroy native engine. Prevents use-after-free.
  void stop() {
    if (!_running) return;
    _running = false;

    _frameSubscription?.cancel();
    _frameSubscription = null;

    // Signal capture isolate to exit, then close rings to unblock captureRead.
    _captureCommandPort?.send(_CaptureCommand.stop);

    // stop() closes the capture_ring, which makes captureRead return -1
    // and breaks the isolate's while loop. The isolate exits cleanly.
    if (_engine != null) {
      try {
        _shim.stop(_engine!);
      } catch (e) {
        _log.warn('cleona_audio stop threw: $e');
      }
    }

    // Kill isolate (belt-and-suspenders after ring close).
    _captureIsolate?.kill(priority: Isolate.beforeNextEvent);
    _captureIsolate = null;
    _captureCommandPort = null;
    _frameReceivePort?.close();
    _frameReceivePort = null;

    if (_engine != null) {
      try {
        _shim.destroy(_engine!);
      } catch (e) {
        _log.warn('cleona_audio destroy threw: $e');
      }
      _engine = null;
    }
    if (_playbackPcmPtr != null) {
      try {
        calloc.free(_playbackPcmPtr!);
      } catch (e) {
        _log.warn('calloc.free(_playbackPcmPtr) threw: $e');
      }
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
