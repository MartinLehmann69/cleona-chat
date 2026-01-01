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
  // §10.2.1 per-sender media keys. `_ownSendKey` (secret to us) encrypts our
  // outgoing frames; `_peerSendKeys` maps an authenticated sender userId-hex to
  // their announced key and decrypts THEIR frames.
  Uint8List _ownSendKey;
  int _ownSendKeyVersion;
  final Map<String, Uint8List> _peerSendKeys = {};
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
    required Uint8List ownSendKey,
    required String profileDir,
    int ownSendKeyVersion = 1,
  })  : _ownSendKey = ownSendKey,
        _ownSendKeyVersion = ownSendKeyVersion,
        _log = CLogger.get('group-audio', profileDir: profileDir) {
    _shim = AudioEngineShim.load();
  }

  /// Register an authenticated peer's secret media key (decrypt side).
  void setPeerSendKey(String senderUserHex, Uint8List key) {
    _peerSendKeys[senderUserHex] = key;
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
    final init = _MixerCaptureInit(_frameReceivePort!.sendPort, _ownSendKey);

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

    final pcm = _decryptFrame(encryptedAudio, senderNodeIdHex);
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

  /// Decrypt an audio frame using the sender's own secret key (§10.2.1).
  /// A frame whose sender key we have not yet learned is dropped (the signed
  /// announcement lands sub-second at join). AES-GCM auth means a frame that
  /// decrypts under sender X's key genuinely came from X — a co-participant
  /// without X's secret key cannot forge it.
  Uint8List? _decryptFrame(Uint8List packet, String senderUserHex) {
    if (packet.length < 16 + cryptoAeadAes256GcmABytes) return null;

    final key = _peerSendKeys[senderUserHex];
    if (key == null) {
      _log.debug('Audio drop: no send_key yet for ${senderUserHex.substring(0, 8)}');
      return null;
    }
    try {
      final nonce = Uint8List.sublistView(packet, 4, 16);
      final ciphertext = Uint8List.sublistView(packet, 16);
      return _sodium.aesGcmDecrypt(ciphertext, key, nonce);
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

  /// Update OUR own send key after rotation (§10.2.1). Switches the encrypt
  /// side (capture isolate) to the new key.
  void updateOwnSendKey(Uint8List newKey, int version) {
    if (version <= _ownSendKeyVersion) return; // Ignore old versions
    _ownSendKey = newKey;
    _ownSendKeyVersion = version;
    _captureCommandPort?.send(Uint8List.fromList(newKey));
    _log.info('Own send_key updated to version $version');
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

    _frameSubscription?.cancel();
    _frameSubscription = null;

    _captureCommandPort?.send(_MixerCaptureCommand.stop);
    _captureIsolate?.kill(priority: Isolate.beforeNextEvent);
    _captureIsolate = null;
    _captureCommandPort = null;
    _frameReceivePort?.close();
    _frameReceivePort = null;

    if (_engine != null) {
      try {
        _shim.stop(_engine!);
        _shim.destroy(_engine!);
      } catch (e) {
        _log.warn('cleona_audio stop/destroy threw (mixer): $e');
      }
      _engine = null;
    }
    if (_playbackPcmPtr != null) {
      try {
        calloc.free(_playbackPcmPtr!);
      } catch (e) {
        _log.warn('calloc.free(_playbackPcmPtr) threw (mixer): $e');
      }
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
