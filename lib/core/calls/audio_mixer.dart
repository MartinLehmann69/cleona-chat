// ignore_for_file: constant_identifier_names
import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/calls/jitter_buffer.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/calls/audio_engine_shim.dart';

// ── Audio Constants ──────────────────────────────────────────────────────

const int _sampleRate = 16000;
const int _channels = 1;
const int _frameDurationMs = 20;
const int _samplesPerFrame =
    _sampleRate * _channels * _frameDurationMs ~/ 1000; // 320
const int _frameSize = _samplesPerFrame * 2; // 640 bytes

// ── Capture Isolate ──────────────────────────────────────────────────────

class _MixerCaptureInit {
  final SendPort frameSendPort;
  final Uint8List callKey;
  _MixerCaptureInit(this.frameSendPort, this.callKey);
}

enum _MixerCaptureCommand { mute, unmute, stop }

void _mixerCaptureIsolateEntry(_MixerCaptureInit init) {
  // See audio_engine.dart 2026-04-26 fix: a parent-created ReceivePort can't
  // travel through Isolate.spawn ("object is unsendable - _ReceivePortImpl").
  // Child owns its own command RX and sends its SendPort back as the first
  // wire message; ready-flag follows.
  final commandPort = ReceivePort();
  final frameSendPort = init.frameSendPort;
  frameSendPort.send(commandPort.sendPort);

  final shim = AudioEngineShim.load();
  final engine = shim.create(
    sampleRate: _sampleRate,
    channels: _channels,
    frameSamples: _samplesPerFrame,
    ringCapacityFrames: 8,
  );
  if (engine.address == 0) {
    frameSendPort.send(null);
    commandPort.close();
    return;
  }
  if (shim.start(engine) != 0) {
    shim.destroy(engine);
    frameSendPort.send(null);
    commandPort.close();
    return;
  }

  final sodium = SodiumFFI();
  var callKey = init.callKey;

  frameSendPort.send(true);

  var running = true;
  var muted = false;
  var seqNum = 0;

  commandPort.listen((message) {
    if (message == _MixerCaptureCommand.stop) {
      running = false;
    } else if (message == _MixerCaptureCommand.mute) {
      muted = true;
      shim.setMute(engine, true);
    } else if (message == _MixerCaptureCommand.unmute) {
      muted = false;
      shim.setMute(engine, false);
    } else if (message is Uint8List) {
      callKey = message;
    }
  });

  final pcmPtr = calloc<Int16>(_samplesPerFrame);

  while (running) {
    final r = shim.captureRead(engine, pcmPtr, 100);
    if (r == -1) break;
    if (r == 0) continue;

    if (!muted) {
      final pcmData = Uint8List.fromList(
          pcmPtr.cast<Uint8>().asTypedList(_frameSize));
      final seqBytes = Uint8List(4);
      ByteData.sublistView(seqBytes).setUint32(0, seqNum++, Endian.big);
      final nonce = sodium.generateNonce();
      final ciphertext = sodium.aesGcmEncrypt(pcmData, callKey, nonce);

      final packet = Uint8List(4 + 12 + ciphertext.length);
      packet.setAll(0, seqBytes);
      packet.setAll(4, nonce);
      packet.setAll(16, ciphertext);
      frameSendPort.send(packet);
    }
  }

  calloc.free(pcmPtr);
  shim.stop(engine);
  shim.destroy(engine);
}

// ── AudioMixer ───────────────────────────────────────────────────────────

/// Mixes audio from multiple group call participants for playback.
///
/// Each peer has its own JitterBuffer. Incoming encrypted frames are decrypted,
/// PCM samples are summed with int16 clamping, and the mixed result is played
/// via the cross-platform cleona_audio shim (miniaudio + speex AEC/NS).
///
/// Also owns a capture isolate for microphone input (same pattern as AudioEngine
/// but encrypts with the shared group call key).
class AudioMixer {
  Uint8List _callKey; // Shared AES-256 key
  int _callKeyVersion;
  final CLogger _log;
  final SodiumFFI _sodium = SodiumFFI();

  // Per-peer jitter buffers
  final Map<String, JitterBuffer> _peerBuffers = {};

  // cleona_audio shim
  late final AudioEngineShim _shim;
  Pointer<CleonaAudioEngine>? _engine;
  Pointer<Int16>? _playbackPcmPtr;

  // Capture isolate
  Isolate? _captureIsolate;
  SendPort? _captureCommandPort;
  ReceivePort? _frameReceivePort;
  StreamSubscription? _frameSubscription;

  // Mix timer (20ms)
  Timer? _mixTimer;

  // State
  bool _running = false;
  bool _muted = false;
  bool _speakerEnabled = true;

  // Callback: encrypted audio frame ready to send
  void Function(Uint8List encryptedFrame)? onAudioFrame;

  AudioMixer({
    required Uint8List callKey,
    required String profileDir,
    int callKeyVersion = 0,
  })  : _callKey = callKey,
        _callKeyVersion = callKeyVersion,
        _log = CLogger.get('group-audio', profileDir: profileDir) {
    _shim = AudioEngineShim.load();
  }

  /// Start capture isolate, playback, and mix timer.
  Future<bool> start() async {
    if (_running) return true;

    _engine = _shim.create(
      sampleRate: _sampleRate,
      channels: _channels,
      frameSamples: _samplesPerFrame,
      ringCapacityFrames: 8,
    );
    if (_engine == null || _engine!.address == 0) {
      _log.error('cleona_audio_create failed (mixer)');
      return false;
    }
    if (_shim.start(_engine!) != 0) {
      _log.error('cleona_audio_start failed (mixer)');
      _shim.destroy(_engine!);
      _engine = null;
      return false;
    }
    _playbackPcmPtr = calloc<Int16>(_samplesPerFrame);

    final captureOk = await _startCaptureIsolate();
    if (!captureOk) {
      _log.error('Mixer capture isolate failed to start');
      _shim.stop(_engine!);
      _shim.destroy(_engine!);
      _engine = null;
      calloc.free(_playbackPcmPtr!);
      _playbackPcmPtr = null;
      return false;
    }

    _mixTimer = Timer.periodic(
      const Duration(milliseconds: _frameDurationMs),
      (_) => _mixAndPlay(),
    );

    _running = true;
    _log.info('AudioMixer started (cross-platform shim)');
    return true;
  }

  Future<bool> _startCaptureIsolate() async {
    _frameReceivePort = ReceivePort();
    final init = _MixerCaptureInit(_frameReceivePort!.sendPort, _callKey);

    // Two-stage handshake (see audio_engine.dart 2026-04-26 fix): SendPort,
    // then ready-flag, then audio frames.
    final commandPortCompleter = Completer<SendPort>();
    final readyCompleter = Completer<bool>();

    _frameSubscription = _frameReceivePort!.listen((message) {
      if (!commandPortCompleter.isCompleted) {
        if (message is SendPort) {
          commandPortCompleter.complete(message);
        } else {
          commandPortCompleter.completeError(
              StateError('mixer capture isolate did not send command port'));
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

    _captureIsolate =
        await Isolate.spawn(_mixerCaptureIsolateEntry, init);

    try {
      _captureCommandPort = await commandPortCompleter.future
          .timeout(const Duration(seconds: 5));
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
      _captureCommandPort?.send(_MixerCaptureCommand.mute);
    }

    return true;
  }

  /// Add an incoming encrypted audio frame from a peer.
  void addFrame(String senderNodeIdHex, Uint8List encryptedAudio) {
    if (!_running) return;

    final pcm = _decryptFrame(encryptedAudio);
    if (pcm == null) return;

    // Extract sequence number from the packet
    final seqNum =
        ByteData.sublistView(encryptedAudio).getUint32(0, Endian.big);

    // Get or create peer's JitterBuffer
    final buffer = _peerBuffers.putIfAbsent(
      senderNodeIdHex,
      () => JitterBuffer(bufferDepth: 3, maxBufferSize: 20),
    );

    buffer.push(AudioFrame(seqNum: seqNum, data: pcm));
  }

  /// Decrypt an audio frame.
  Uint8List? _decryptFrame(Uint8List packet) {
    if (packet.length < 16 + cryptoAeadAes256GcmABytes) return null;

    try {
      final nonce = Uint8List.sublistView(packet, 4, 16);
      final ciphertext = Uint8List.sublistView(packet, 16);
      return _sodium.aesGcmDecrypt(ciphertext, _callKey, nonce);
    } catch (e) {
      _log.debug('Audio decrypt failed: $e');
      return null;
    }
  }

  /// Mix all peer streams and play (called every 20ms).
  void _mixAndPlay() {
    if (!_running || _engine == null || _playbackPcmPtr == null) return;
    if (!_speakerEnabled) return;

    // Drain one frame from each peer's buffer
    final pcmFrames = <Uint8List>[];
    for (final entry in _peerBuffers.entries) {
      final frame = entry.value.pop();
      if (frame != null) {
        pcmFrames.add(frame.data);
      }
    }

    if (pcmFrames.isEmpty) return;

    // Mix and play
    final mixed = mixPcm(pcmFrames);
    if (mixed.length != _frameSize) return;

    final byteView = _playbackPcmPtr!.cast<Uint8>().asTypedList(_frameSize);
    byteView.setAll(0, mixed);
    _shim.playbackWrite(_engine!, _playbackPcmPtr!, _samplesPerFrame);
  }

  /// Mix N PCM buffers (16-bit mono) into one by sample-wise addition
  /// with clamping to [-32768, 32767].
  static Uint8List mixPcm(List<Uint8List> pcmBuffers) {
    if (pcmBuffers.isEmpty) return Uint8List(_frameSize);
    if (pcmBuffers.length == 1) return Uint8List.fromList(pcmBuffers.first);

    final result = Uint8List(_frameSize);
    final resultView = ByteData.sublistView(result);

    for (var i = 0; i < _samplesPerFrame; i++) {
      var sum = 0;
      for (final pcm in pcmBuffers) {
        if (pcm.length >= (i + 1) * 2) {
          sum += ByteData.sublistView(pcm).getInt16(i * 2, Endian.little);
        }
      }
      // Clamp to int16 range
      if (sum > 32767) sum = 32767;
      if (sum < -32768) sum = -32768;
      resultView.setInt16(i * 2, sum, Endian.little);
    }

    return result;
  }

  /// Update the call key after key rotation.
  void updateCallKey(Uint8List newKey, int version) {
    if (version <= _callKeyVersion) return; // Ignore old versions
    _callKey = newKey;
    _callKeyVersion = version;
    // Update capture isolate's key
    _captureCommandPort?.send(Uint8List.fromList(newKey));
    _log.info('Call key updated to version $version');
  }

  /// Remove a peer (left/crashed).
  void removePeer(String nodeIdHex) {
    _peerBuffers.remove(nodeIdHex);
  }

  /// Stop everything.
  void stop() {
    if (!_running) return;
    _running = false;

    _mixTimer?.cancel();
    _mixTimer = null;

    // Stop capture isolate
    _captureCommandPort?.send(_MixerCaptureCommand.stop);
    _captureIsolate?.kill(priority: Isolate.beforeNextEvent);
    _captureIsolate = null;
    _captureCommandPort = null;
    _frameSubscription?.cancel();
    _frameReceivePort?.close();

    // Close engine
    if (_engine != null) {
      _shim.stop(_engine!);
      _shim.destroy(_engine!);
      _engine = null;
    }
    if (_playbackPcmPtr != null) {
      calloc.free(_playbackPcmPtr!);
      _playbackPcmPtr = null;
    }

    _peerBuffers.clear();
    _log.info('AudioMixer stopped');
  }

  bool get isRunning => _running;

  bool get isMuted => _muted;
  set muted(bool value) {
    _muted = value;
    _captureCommandPort?.send(
        value ? _MixerCaptureCommand.mute : _MixerCaptureCommand.unmute);
    _log.info('Microphone ${value ? "muted" : "unmuted"}');
  }

  bool get isSpeakerEnabled => _speakerEnabled;
  set speakerEnabled(bool value) {
    _speakerEnabled = value;
    _log.info('Speaker ${value ? "enabled" : "disabled"}');
  }
}
