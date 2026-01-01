import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/calls/jitter_buffer.dart';
import 'package:cleona/core/calls/voice_codec.dart';
import 'package:cleona/core/calls/voice_session.dart';
import 'package:cleona/core/network/clogger.dart';

/// Mixes audio from multiple group call participants for playback.
///
/// Each peer has its own [JitterBuffer] and [VoiceCodec] decoder. Incoming
/// encrypted Opus frames are decrypted, decoded to PCM, mixed by sample-wise
/// addition with int16 clamping, and written to a single [VoiceSession] for
/// playback. Capture runs on a 5ms polling timer in the main isolate.
class AudioMixer {
  Uint8List _ownSendKey;
  int _ownSendKeyVersion;
  final Map<String, Uint8List> _peerSendKeys = {};
  final CLogger _log;
  final SodiumFFI _sodium = SodiumFFI();

  final Map<String, JitterBuffer> _peerBuffers = {};
  final Map<String, VoiceCodec> _peerDecoders = {};
  final Map<String, double> _peerAudioLevels = {};

  VoiceSession? _voiceSession;
  VoiceCodec? _captureCodec;
  Int16List? _captureBuf;

  Timer? _captureTimer;
  Timer? _mixTimer;

  bool _running = false;
  bool _muted = false;
  bool _speakerEnabled = true;
  int _captureSeqNum = 0;

  Map<String, double> get peerAudioLevels => Map.unmodifiable(_peerAudioLevels);

  void Function(Uint8List encryptedFrame)? onAudioFrame;
  void Function(bool speaker)? onSpeakerToggle;

  AudioMixer({
    required Uint8List ownSendKey,
    required String profileDir,
    int ownSendKeyVersion = 1,
  })  : _ownSendKey = ownSendKey,
        _ownSendKeyVersion = ownSendKeyVersion,
        _log = CLogger.get('group-audio', profileDir: profileDir);

  void setPeerSendKey(String senderUserHex, Uint8List key) {
    _peerSendKeys[senderUserHex] = key;
  }

  Future<bool> start() async {
    if (_running) return true;

    try {
      final lib = VoiceNativeLibrary.platform();
      _voiceSession = VoiceSession.open(library: lib);
      final format = _voiceSession!.format;

      _captureCodec = VoiceCodec.fromFormat(format);
      _captureBuf = Int16List(format.frameSamples);
      _captureSeqNum = 0;

      _voiceSession!.start();

      _captureTimer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => _captureAndSend(),
      );

      final frameDurationMs =
          format.frameSamples * 1000 ~/ (format.sampleRate * format.channels);
      _mixTimer = Timer.periodic(
        Duration(milliseconds: frameDurationMs),
        (_) => _mixAndPlay(),
      );

      _running = true;
      _log.info('AudioMixer started (VoiceSession, rate=${format.sampleRate}, '
          'frame=${format.frameSamples})');
      return true;
    } catch (e) {
      _log.error('AudioMixer start failed: $e');
      stop();
      return false;
    }
  }

  void _captureAndSend() {
    final vs = _voiceSession;
    if (vs == null) return;

    final status = vs.readCaptureFrameInto(_captureBuf!, timeoutMs: 0);
    if (status != VoiceCaptureStatus.frame) return;
    if (_muted) return;

    try {
      final pcmBytes = _captureBuf!.buffer.asUint8List(
          _captureBuf!.offsetInBytes, _captureBuf!.lengthInBytes);
      final opusData = _captureCodec!.encode(pcmBytes);

      final nonce = _sodium.generateNonce();
      final encrypted = _sodium.aesGcmEncrypt(opusData, _ownSendKey, nonce);

      final packet = BytesBuilder(copy: false);
      final seqBuf = ByteData(4);
      seqBuf.setUint32(0, _captureSeqNum++, Endian.big);
      packet.add(Uint8List.view(seqBuf.buffer));
      packet.add(nonce);
      packet.add(encrypted);

      onAudioFrame?.call(packet.toBytes());
    } catch (e) {
      _log.debug('Mixer capture encode/encrypt failed: $e');
    }
  }

  void addFrame(String senderNodeIdHex, Uint8List encryptedAudio) {
    if (!_running) return;

    final opusData = _decryptFrame(encryptedAudio, senderNodeIdHex);
    if (opusData == null) return;

    final seqNum =
        ByteData.sublistView(encryptedAudio).getUint32(0, Endian.big);

    final buffer = _peerBuffers.putIfAbsent(
      senderNodeIdHex,
      () => JitterBuffer(bufferDepth: 5, maxBufferSize: 20),
    );

    buffer.push(AudioFrame(seqNum: seqNum, data: opusData));
  }

  Uint8List? _decryptFrame(Uint8List packet, String senderUserHex) {
    if (packet.length < 16 + cryptoAeadAes256GcmABytes) return null;

    final key = _peerSendKeys[senderUserHex];
    if (key == null) {
      _log.debug(
          'Audio drop: no send_key yet for ${senderUserHex.substring(0, 8)}');
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

  VoiceCodec _getOrCreateDecoder(String peerHex) {
    return _peerDecoders.putIfAbsent(
      peerHex,
      () => VoiceCodec.fromFormat(_voiceSession!.format),
    );
  }

  void _mixAndPlay() {
    if (!_running || _voiceSession == null) return;

    final pcmFrames = <Int16List>[];
    for (final entry in _peerBuffers.entries) {
      final frame = entry.value.pop();
      if (frame != null) {
        try {
          final decoder = _getOrCreateDecoder(entry.key);
          final pcmBytes = decoder.decode(frame.data);
          final pcm16 = Int16List.view(
              pcmBytes.buffer, pcmBytes.offsetInBytes, pcmBytes.length ~/ 2);
          pcmFrames.add(pcm16);

          var peak = 0;
          for (var i = 0; i < pcm16.length; i++) {
            final abs = pcm16[i].abs();
            if (abs > peak) peak = abs;
          }
          _peerAudioLevels[entry.key] = (peak / 32768.0).clamp(0.0, 1.0);
        } catch (e) {
          _log.debug(
              'Opus decode failed for ${entry.key.substring(0, 8)}: $e');
          _peerAudioLevels[entry.key] = 0.0;
        }
      } else {
        _peerAudioLevels[entry.key] = 0.0;
      }
    }

    if (pcmFrames.isEmpty) return;

    final mixed = _mixPcmInt16(pcmFrames);
    _voiceSession!.writePlaybackFrame(mixed);
  }

  static Int16List _mixPcmInt16(List<Int16List> frames) {
    if (frames.length == 1) return Int16List.fromList(frames.first);

    final len = frames.first.length;
    final result = Int16List(len);
    for (var i = 0; i < len; i++) {
      var sum = 0;
      for (final f in frames) {
        if (i < f.length) sum += f[i];
      }
      if (sum > 32767) sum = 32767;
      if (sum < -32768) sum = -32768;
      result[i] = sum;
    }
    return result;
  }

  static Uint8List mixPcm(List<Uint8List> pcmBuffers) {
    if (pcmBuffers.isEmpty) return Uint8List(640);
    if (pcmBuffers.length == 1) return Uint8List.fromList(pcmBuffers.first);

    final frameSize = pcmBuffers.first.length;
    final samplesPerFrame = frameSize ~/ 2;
    final result = Uint8List(frameSize);
    final resultView = ByteData.sublistView(result);

    for (var i = 0; i < samplesPerFrame; i++) {
      var sum = 0;
      for (final pcm in pcmBuffers) {
        if (pcm.length >= (i + 1) * 2) {
          sum += ByteData.sublistView(pcm).getInt16(i * 2, Endian.little);
        }
      }
      if (sum > 32767) sum = 32767;
      if (sum < -32768) sum = -32768;
      resultView.setInt16(i * 2, sum, Endian.little);
    }

    return result;
  }

  void updateOwnSendKey(Uint8List newKey, int version) {
    if (version <= _ownSendKeyVersion) return;
    _ownSendKey = newKey;
    _ownSendKeyVersion = version;
    _log.info('Own send_key updated to version $version');
  }

  void removePeer(String nodeIdHex) {
    _peerBuffers.remove(nodeIdHex);
    _peerAudioLevels.remove(nodeIdHex);
    _peerDecoders.remove(nodeIdHex)?.dispose();
  }

  void stop() {
    if (!_running) return;
    _running = false;

    _captureTimer?.cancel();
    _captureTimer = null;
    _mixTimer?.cancel();
    _mixTimer = null;

    try {
      _voiceSession?.stop();
      _voiceSession?.close();
    } catch (e) {
      _log.warn('VoiceSession stop/close threw (mixer): $e');
    }
    _voiceSession = null;

    _captureCodec?.dispose();
    _captureCodec = null;
    _captureBuf = null;

    for (final decoder in _peerDecoders.values) {
      decoder.dispose();
    }
    _peerDecoders.clear();
    _peerBuffers.clear();
    _peerAudioLevels.clear();
    _log.info('AudioMixer stopped');
  }

  bool get isRunning => _running;

  bool get isMuted => _muted;
  set muted(bool value) {
    _muted = value;
    _log.info('Microphone ${value ? "muted" : "unmuted"}');
  }

  bool get isSpeakerEnabled => _speakerEnabled;
  set speakerEnabled(bool value) {
    _speakerEnabled = value;
    onSpeakerToggle?.call(value);
    if (_voiceSession != null) {
      final route = value ? VoiceRoute.speaker : VoiceRoute.earpiece;
      final rc = _voiceSession!.setRoute(route);
      if (rc < 0) {
        _log.debug('setRoute(${route.logName}) returned $rc');
      }
    }
    _log.info('Speaker ${value ? "enabled" : "disabled"}');
  }
}
