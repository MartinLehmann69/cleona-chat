// ignore_for_file: constant_identifier_names
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/calls/jitter_buffer.dart';
import 'package:cleona/core/network/clogger.dart';

// ── PulseAudio Simple API FFI (same as AudioEngine) ──────────────────────

const int _PA_SAMPLE_S16LE = 3;
const int _PA_STREAM_PLAYBACK = 1;
const int _PA_STREAM_RECORD = 2;

final class _PaSampleSpec extends Struct {
  @Uint32()
  external int format;
  @Uint32()
  external int rate;
  @Uint8()
  external int channels;
}

typedef _PaSimpleNewNative = Pointer<Void> Function(
    Pointer<Utf8>, Pointer<Utf8>, Int32, Pointer<Utf8>, Pointer<Utf8>,
    Pointer<_PaSampleSpec>, Pointer<Void>, Pointer<Void>, Pointer<Int32>);
typedef _PaSimpleNewDart = Pointer<Void> Function(
    Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>,
    Pointer<_PaSampleSpec>, Pointer<Void>, Pointer<Void>, Pointer<Int32>);

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

typedef _PaSimpleDrainNative = Int32 Function(Pointer<Void>, Pointer<Int32>);
typedef _PaSimpleDrainDart = int Function(Pointer<Void>, Pointer<Int32>);

// ── Audio Constants ──────────────────────────────────────────────────────

const int _sampleRate = 16000;
const int _channels = 1;
const int _frameDurationMs = 20;
const int _frameSize = _sampleRate * _channels * 2 * _frameDurationMs ~/ 1000; // 640 bytes
const int _samplesPerFrame = _frameSize ~/ 2; // 320 int16 samples

// ── Capture Isolate ──────────────────────────────────────────────────────

class _MixerCaptureInit {
  final SendPort frameSendPort;
  final Uint8List callKey;
  _MixerCaptureInit(this.frameSendPort, this.callKey);
}

enum _MixerCaptureCommand { mute, unmute, stop }

void _mixerCaptureIsolateEntry(List<dynamic> args) {
  final init = args[0] as _MixerCaptureInit;
  final commandPort = args[1] as ReceivePort;

  final lib = DynamicLibrary.open('libpulse-simple.so.0');
  final paNew = lib.lookupFunction<_PaSimpleNewNative, _PaSimpleNewDart>(
      'pa_simple_new');
  final paRead = lib.lookupFunction<_PaSimpleReadNative, _PaSimpleReadDart>(
      'pa_simple_read');
  final paFree = lib.lookupFunction<_PaSimpleFreeNative, _PaSimpleFreeDart>(
      'pa_simple_free');

  final sodium = SodiumFFI();
  final frameSendPort = init.frameSendPort;
  var callKey = init.callKey;

  final spec = calloc<_PaSampleSpec>();
  spec.ref.format = _PA_SAMPLE_S16LE;
  spec.ref.rate = _sampleRate;
  spec.ref.channels = _channels;

  final err = calloc<Int32>();
  final appName = 'Cleona-Group'.toNativeUtf8();
  final recName = 'group-capture'.toNativeUtf8();

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
    frameSendPort.send(null);
    return;
  }
  frameSendPort.send(true);

  var running = true;
  var muted = false;
  var seqNum = 0;

  commandPort.listen((message) {
    if (message == _MixerCaptureCommand.stop) {
      running = false;
    } else if (message == _MixerCaptureCommand.mute) {
      muted = true;
    } else if (message == _MixerCaptureCommand.unmute) {
      muted = false;
    } else if (message is Uint8List) {
      // Key update
      callKey = message;
    }
  });

  final buf = calloc<Uint8>(_frameSize);
  final readErr = calloc<Int32>();

  while (running) {
    final rc = paRead(recordHandle, buf, _frameSize, readErr);
    if (rc < 0 || !running) break;

    if (!muted) {
      final pcmData = Uint8List.fromList(buf.asTypedList(_frameSize));

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

  calloc.free(buf);
  calloc.free(readErr);
  paFree(recordHandle);
}

// ── AudioMixer ───────────────────────────────────────────────────────────

/// Mixes audio from multiple group call participants for playback.
///
/// Each peer has its own JitterBuffer. Incoming encrypted frames are decrypted,
/// PCM samples are summed with int16 clamping, and the mixed result is played
/// via PulseAudio.
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

  // PulseAudio playback
  Pointer<Void>? _playHandle;
  late final _PaSimpleNewDart _paNew;
  late final _PaSimpleWriteDart _paWrite;
  late final _PaSimpleFreeDart _paFree;
  late final _PaSimpleDrainDart _paDrain;

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
    if (!Platform.isLinux) {
      throw UnsupportedError('AudioMixer currently only supports Linux');
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

  /// Start capture isolate, playback, and mix timer.
  Future<bool> start() async {
    if (_running) return true;

    // Open playback stream
    final spec = calloc<_PaSampleSpec>();
    spec.ref.format = _PA_SAMPLE_S16LE;
    spec.ref.rate = _sampleRate;
    spec.ref.channels = _channels;
    final err = calloc<Int32>();
    final appName = 'Cleona-Group'.toNativeUtf8();
    final playName = 'group-playback'.toNativeUtf8();

    try {
      _playHandle = _paNew(
        nullptr.cast(), appName, _PA_STREAM_PLAYBACK,
        nullptr.cast(), playName, spec,
        nullptr, nullptr, err,
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
    final captureOk = await _startCaptureIsolate();
    if (!captureOk) {
      _log.error('Capture isolate failed to start');
      _paFree(_playHandle!);
      _playHandle = null;
      return false;
    }

    // Start mix timer (20ms = 1 audio frame)
    _mixTimer = Timer.periodic(
      const Duration(milliseconds: _frameDurationMs),
      (_) => _mixAndPlay(),
    );

    _running = true;
    _log.info('AudioMixer started');
    return true;
  }

  Future<bool> _startCaptureIsolate() async {
    _frameReceivePort = ReceivePort();
    final commandReceivePort = ReceivePort();
    final init = _MixerCaptureInit(_frameReceivePort!.sendPort, _callKey);

    final readyCompleter = Completer<bool>();
    var firstMessage = true;

    _frameSubscription = _frameReceivePort!.listen((message) {
      if (firstMessage) {
        firstMessage = false;
        readyCompleter.complete(message == true);
        return;
      }
      if (message is Uint8List) {
        onAudioFrame?.call(message);
      }
    });

    _captureIsolate = await Isolate.spawn(
      _mixerCaptureIsolateEntry,
      [init, commandReceivePort],
    );

    _captureCommandPort = commandReceivePort.sendPort;

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
    final seqNum = ByteData.sublistView(encryptedAudio).getUint32(0, Endian.big);

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
    if (!_running || _playHandle == null || !_speakerEnabled) return;

    // Drain one frame from each peer's buffer
    final pcmFrames = <Uint8List>[];
    final emptyPeers = <String>[];

    for (final entry in _peerBuffers.entries) {
      final frame = entry.value.pop();
      if (frame != null) {
        pcmFrames.add(frame.data);
      }
      // Track peers with no activity for cleanup
      if (entry.value.framesReceived == 0) {
        emptyPeers.add(entry.key);
      }
    }

    if (pcmFrames.isEmpty) return;

    // Mix and play
    final mixed = mixPcm(pcmFrames);
    _writePcm(mixed);
  }

  /// Write raw PCM to PulseAudio playback.
  void _writePcm(Uint8List pcm) {
    if (_playHandle == null) return;
    final buf = calloc<Uint8>(pcm.length);
    final err = calloc<Int32>();
    try {
      buf.asTypedList(pcm.length).setAll(0, pcm);
      _paWrite(_playHandle!, buf, pcm.length, err);
    } finally {
      calloc.free(buf);
      calloc.free(err);
    }
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

    // Close playback
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

    _peerBuffers.clear();
    _log.info('AudioMixer stopped');
  }

  bool get isRunning => _running;

  bool get isMuted => _muted;
  set muted(bool value) {
    _muted = value;
    _captureCommandPort?.send(value ? _MixerCaptureCommand.mute : _MixerCaptureCommand.unmute);
    _log.info('Microphone ${value ? "muted" : "unmuted"}');
  }

  bool get isSpeakerEnabled => _speakerEnabled;
  set speakerEnabled(bool value) {
    _speakerEnabled = value;
    _log.info('Speaker ${value ? "enabled" : "disabled"}');
  }
}
