/// FFI bindings for libopus (audio codec).
///
/// Opus is the standard codec for VoIP (RFC 6716).
/// Reduces audio bandwidth from 256 kbps (raw PCM) to ~24-32 kbps.
///
/// Configuration (V1.9):
/// - Sample rate and frame size come from the caller (VoiceSession.format)
///   to respect invariant I3 ("no assumed sample rate").
/// - Mono, 20 ms frame duration.
/// - DTX enabled, Inband-FEC enabled, target bitrate 28 kbps.
///
/// The legacy no-arg constructor [OpusFFI()] remains for backward
/// compatibility (16 kHz, 320 samples) but new callers must use
/// [OpusFFI.withFormat].
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ── Opus Constants ──────────────────────────────────────────────────────

/// Opus Application Type: Optimized for speech (VoIP).
const int opusApplicationVoip = 2048;

/// Opus OK Return Code.
const int opusOk = 0;

/// Maximum packet size for an Opus frame.
const int opusMaxPacketSize = 4000;

/// Legacy sample rate for backward compatibility.
/// New code must NOT use this — sample rate comes from VoiceSession.format.
const int opusSampleRate = 16000;

/// Mono.
const int opusChannels = 1;

/// Legacy frame duration in samples (20ms at 16kHz = 320 samples).
/// New code must NOT use this — frame size comes from VoiceSession.format.
const int opusFrameSamples = opusSampleRate * 20 ~/ 1000; // 320

// ── Opus CTL Constants ──────────────────────────────────────────────────

/// `OPUS_SET_BITRATE` — sets the encoder bitrate in bits/second.
const int _opusSetBitrate = 4002;

/// `OPUS_SET_INBAND_FEC` — enables (1) or disables (0) inband FEC.
const int _opusSetInbandFec = 4012;

/// `OPUS_SET_PACKET_LOSS_PERC` — expected packet loss percentage (0-100).
const int _opusSetPacketLossPerc = 4014;

/// `OPUS_SET_DTX` — enables (1) or disables (0) discontinuous transmission.
const int _opusSetDtx = 4016;

/// Target bitrate (bits/second). 28000 is the midpoint of the spec range
/// (24-32 kbps).
const int _opusTargetBitrate = 28000;

/// Expected packet loss percentage for FEC tuning. 10% is typical for
/// VoIP over UDP with relay hops.
const int _opusExpectedLossPerc = 10;

// ── Native Function Types ────────────────────────────────────────────────

// OpusEncoder* opus_encoder_create(int Fs, int channels, int application, int *error)
typedef _OpusEncoderCreateNative = Pointer<Void> Function(
    Int32, Int32, Int32, Pointer<Int32>);
typedef _OpusEncoderCreateDart = Pointer<Void> Function(
    int, int, int, Pointer<Int32>);

// void opus_encoder_destroy(OpusEncoder *st)
typedef _OpusEncoderDestroyNative = Void Function(Pointer<Void>);
typedef _OpusEncoderDestroyDart = void Function(Pointer<Void>);

// int opus_encode(OpusEncoder*, const opus_int16*, int frame_size, unsigned char*, int max_data_bytes)
typedef _OpusEncodeNative = Int32 Function(
    Pointer<Void>, Pointer<Int16>, Int32, Pointer<Uint8>, Int32);
typedef _OpusEncodeDart = int Function(
    Pointer<Void>, Pointer<Int16>, int, Pointer<Uint8>, int);

// OpusDecoder* opus_decoder_create(int Fs, int channels, int *error)
typedef _OpusDecoderCreateNative = Pointer<Void> Function(
    Int32, Int32, Pointer<Int32>);
typedef _OpusDecoderCreateDart = Pointer<Void> Function(
    int, int, Pointer<Int32>);

// void opus_decoder_destroy(OpusDecoder *st)
typedef _OpusDecoderDestroyNative = Void Function(Pointer<Void>);
typedef _OpusDecoderDestroyDart = void Function(Pointer<Void>);

// int opus_decode(OpusDecoder*, const unsigned char*, int len, opus_int16*, int frame_size, int decode_fec)
typedef _OpusDecodeNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Int16>, Int32, Int32);
typedef _OpusDecodeDart = int Function(
    Pointer<Void>, Pointer<Uint8>, int, Pointer<Int16>, int, int);

// int opus_encoder_ctl(OpusEncoder *st, int request, int value)
// Dart FFI has no varargs — we use the 3-arg (encoder, request, int) form
// and look it up under the same symbol name.
typedef _OpusEncoderCtlIntNative = Int32 Function(
    Pointer<Void>, Int32, Int32);
typedef _OpusEncoderCtlIntDart = int Function(Pointer<Void>, int, int);

// ── OpusFFI Class ────────────────────────────────────────────────────────

/// FFI wrapper for the libopus audio codec.
///
/// Usage (new — device rate from VoiceSession.format):
/// ```dart
/// final opus = OpusFFI.withFormat(
///   sampleRate: format.sampleRate,
///   frameSamples: format.frameSamples,
/// );
/// final encoded = opus.encode(pcm16Data);  // PCM -> Opus
/// final decoded = opus.decode(encoded);     // Opus -> PCM
/// opus.dispose();
/// ```
///
/// Legacy usage (hardcoded 16 kHz / 320 samples):
/// ```dart
/// final opus = OpusFFI();
/// ```
class OpusFFI {
  DynamicLibrary? _lib;
  Pointer<Void>? _encoder;
  Pointer<Void>? _decoder;
  bool _disposed = false;

  /// The sample rate this codec instance was created with.
  final int sampleRate;

  /// The number of samples per 20 ms frame at [sampleRate].
  final int frameSamples;

  // Lazy-initialized function pointers
  _OpusEncoderCreateDart? _encoderCreate;
  _OpusEncoderDestroyDart? _encoderDestroy;
  _OpusEncodeDart? _encode;
  _OpusDecoderCreateDart? _decoderCreate;
  _OpusDecoderDestroyDart? _decoderDestroy;
  _OpusDecodeDart? _decode;
  _OpusEncoderCtlIntDart? _encoderCtl;

  /// Legacy constructor. Uses hardcoded 16 kHz / 320 samples.
  ///
  /// Exists for backward compatibility with existing callers. New code must
  /// use [OpusFFI.withFormat].
  OpusFFI()
      : sampleRate = opusSampleRate,
        frameSamples = opusFrameSamples {
    _loadLibrary();
    _createEncoder();
    _createDecoder();
  }

  /// Creates an Opus encoder/decoder pair at the given [sampleRate] and
  /// [frameSamples].
  ///
  /// Both values must come from the platform (VoiceSession.format), never
  /// from a constant (I3, I4). The encoder is configured with DTX, FEC and
  /// a 28 kbps target bitrate per spec V1.9.
  ///
  /// Throws [OpusNotAvailableException] if libopus is not found.
  /// Throws [ArgumentError] if [sampleRate] is not an Opus-supported rate
  /// or [frameSamples] does not match 20 ms at [sampleRate].
  OpusFFI.withFormat({
    required this.sampleRate,
    required this.frameSamples,
  }) {
    // Opus supports exactly these rates.
    const supportedRates = {8000, 12000, 16000, 24000, 48000};
    if (!supportedRates.contains(sampleRate)) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'Opus supports only $supportedRates',
      );
    }
    final expected = sampleRate * 20 ~/ 1000;
    if (frameSamples != expected) {
      throw ArgumentError.value(
        frameSamples,
        'frameSamples',
        'must be sampleRate * 20 / 1000 = $expected for $sampleRate Hz',
      );
    }

    _loadLibrary();
    _createEncoder();
    _configureEncoder();
    _createDecoder();
  }

  void _loadLibrary() {
    if (Platform.isIOS) {
      _lib = DynamicLibrary.process();
    } else {
      final libNames = _libSearchPaths();
      for (final name in libNames) {
        try {
          _lib = DynamicLibrary.open(name);
          break;
        } catch (_) {
          continue;
        }
      }
    }

    if (_lib == null) {
      throw OpusNotAvailableException(
          'libopus not found. Install hint — Linux: apt install libopus0. '
          'macOS: brew install opus, or drop libopus.dylib into '
          'Cleona.app/Contents/Frameworks/. Windows: libopus.dll beside cleona.exe.');
    }

    _encoderCreate = _lib!.lookupFunction<_OpusEncoderCreateNative,
        _OpusEncoderCreateDart>('opus_encoder_create');
    _encoderDestroy = _lib!.lookupFunction<_OpusEncoderDestroyNative,
        _OpusEncoderDestroyDart>('opus_encoder_destroy');
    _encode = _lib!
        .lookupFunction<_OpusEncodeNative, _OpusEncodeDart>('opus_encode');
    _decoderCreate = _lib!.lookupFunction<_OpusDecoderCreateNative,
        _OpusDecoderCreateDart>('opus_decoder_create');
    _decoderDestroy = _lib!.lookupFunction<_OpusDecoderDestroyNative,
        _OpusDecoderDestroyDart>('opus_decoder_destroy');
    _decode = _lib!
        .lookupFunction<_OpusDecodeNative, _OpusDecodeDart>('opus_decode');
    _encoderCtl = _lib!
        .lookupFunction<_OpusEncoderCtlIntNative, _OpusEncoderCtlIntDart>(
            'opus_encoder_ctl');
  }

  static List<String> _libSearchPaths() {
    if (Platform.isMacOS) {
      return const [
        'libopus.dylib',
        'libopus.0.dylib',
        '@executable_path/../Frameworks/libopus.dylib',
        '/opt/homebrew/lib/libopus.dylib',
        '/opt/homebrew/lib/libopus.0.dylib',
        '/usr/local/lib/libopus.dylib',
        '/usr/local/lib/libopus.0.dylib',
      ];
    }
    if (Platform.isWindows) {
      return const ['libopus.dll', 'opus.dll'];
    }
    return const [
      'libopus.so.0',
      'libopus.so',
      '/usr/lib/libopus.so.0',
      '/usr/local/lib/libopus.so.0',
    ];
  }

  void _createEncoder() {
    final err = calloc<Int32>();
    try {
      _encoder = _encoderCreate!(
          sampleRate, opusChannels, opusApplicationVoip, err);
      if (err.value != opusOk || _encoder == null || _encoder == nullptr) {
        throw OpusNotAvailableException(
            'Failed to create Opus encoder: error=${err.value}');
      }
    } finally {
      calloc.free(err);
    }
  }

  /// Configures encoder with DTX, FEC, bitrate and packet loss percentage.
  ///
  /// Called only from [OpusFFI.withFormat] — the legacy constructor does not
  /// configure these so that smoke_calls.dart keeps passing unchanged.
  void _configureEncoder() {
    void ctl(int request, int value, String name) {
      final rc = _encoderCtl!(_encoder!, request, value);
      if (rc != opusOk) {
        throw OpusCodecException(
            'opus_encoder_ctl($name=$value) failed: $rc');
      }
    }

    ctl(_opusSetBitrate, _opusTargetBitrate, 'OPUS_SET_BITRATE');
    ctl(_opusSetDtx, 1, 'OPUS_SET_DTX');
    ctl(_opusSetInbandFec, 1, 'OPUS_SET_INBAND_FEC');
    ctl(_opusSetPacketLossPerc, _opusExpectedLossPerc,
        'OPUS_SET_PACKET_LOSS_PERC');
  }

  void _createDecoder() {
    final err = calloc<Int32>();
    try {
      _decoder = _decoderCreate!(sampleRate, opusChannels, err);
      if (err.value != opusOk || _decoder == null || _decoder == nullptr) {
        throw OpusNotAvailableException(
            'Failed to create Opus decoder: error=${err.value}');
      }
    } finally {
      calloc.free(err);
    }
  }

  /// Compress PCM-16 audio to Opus.
  ///
  /// [pcm16]: Int16 PCM data (mono, [frameSamples] samples = [frameSamples]*2
  /// bytes).
  /// Returns compressed Opus packet.
  Uint8List encode(Uint8List pcm16) {
    if (_disposed || _encoder == null) {
      throw OpusNotAvailableException('Encoder disposed');
    }

    final numSamples = pcm16.length ~/ 2; // 16-bit = 2 bytes per sample
    final inputPtr = calloc<Int16>(numSamples);
    final outputPtr = calloc<Uint8>(opusMaxPacketSize);

    try {
      // Copy PCM data into native memory.
      final view = ByteData.view(pcm16.buffer, pcm16.offsetInBytes);
      for (var i = 0; i < numSamples; i++) {
        inputPtr[i] = view.getInt16(i * 2, Endian.little);
      }

      final encodedBytes = _encode!(
        _encoder!,
        inputPtr,
        numSamples,
        outputPtr,
        opusMaxPacketSize,
      );

      if (encodedBytes < 0) {
        throw OpusCodecException('Opus encode failed: $encodedBytes');
      }

      return Uint8List.fromList(outputPtr.asTypedList(encodedBytes));
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
    }
  }

  /// Decompress Opus packet to PCM-16 audio.
  ///
  /// [opusData]: Compressed Opus packet.
  /// [decodeFec]: if true, decode the FEC data from this packet to recover
  /// the *previous* frame. Call with the **next** received packet after a
  /// gap to recover the lost frame.
  /// Returns PCM-16 data (mono, [frameSamples]*2 bytes).
  Uint8List decode(Uint8List opusData, {bool decodeFec = false}) {
    if (_disposed || _decoder == null) {
      throw OpusNotAvailableException('Decoder disposed');
    }

    final inputPtr = calloc<Uint8>(opusData.length);
    final outputPtr = calloc<Int16>(frameSamples);

    try {
      inputPtr.asTypedList(opusData.length).setAll(0, opusData);

      final decodedSamples = _decode!(
        _decoder!,
        inputPtr,
        opusData.length,
        outputPtr,
        frameSamples,
        decodeFec ? 1 : 0,
      );

      if (decodedSamples < 0) {
        throw OpusCodecException('Opus decode failed: $decodedSamples');
      }

      // Int16 -> Uint8 (Little-Endian)
      final result = Uint8List(decodedSamples * 2);
      final view = ByteData.view(result.buffer);
      for (var i = 0; i < decodedSamples; i++) {
        view.setInt16(i * 2, outputPtr[i], Endian.little);
      }
      return result;
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
    }
  }

  /// Packet Loss Concealment: replace missing frame with interpolation.
  Uint8List decodePlc() {
    if (_disposed || _decoder == null) {
      throw OpusNotAvailableException('Decoder disposed');
    }

    final outputPtr = calloc<Int16>(frameSamples);
    try {
      final decodedSamples = _decode!(
        _decoder!,
        nullptr.cast<Uint8>(),
        0, // len = 0 -> PLC
        outputPtr,
        frameSamples,
        0,
      );

      if (decodedSamples < 0) {
        throw OpusCodecException('Opus PLC failed: $decodedSamples');
      }

      final result = Uint8List(decodedSamples * 2);
      final view = ByteData.view(result.buffer);
      for (var i = 0; i < decodedSamples; i++) {
        view.setInt16(i * 2, outputPtr[i], Endian.little);
      }
      return result;
    } finally {
      calloc.free(outputPtr);
    }
  }

  /// Whether this codec instance has been disposed.
  bool get isDisposed => _disposed;

  /// Release resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_encoder != null && _encoder != nullptr) {
      _encoderDestroy!(_encoder!);
      _encoder = null;
    }
    if (_decoder != null && _decoder != nullptr) {
      _decoderDestroy!(_decoder!);
      _decoder = null;
    }
  }

  /// Whether libopus is available on the system.
  static bool isAvailable() {
    try {
      DynamicLibrary.open('libopus.so.0');
      return true;
    } catch (_) {
      try {
        DynamicLibrary.open('libopus.so');
        return true;
      } catch (_) {
        return false;
      }
    }
  }
}

/// libopus not available.
class OpusNotAvailableException implements Exception {
  final String message;
  OpusNotAvailableException(this.message);

  @override
  String toString() => 'OpusNotAvailableException: $message';
}

/// Opus codec error.
class OpusCodecException implements Exception {
  final String message;
  OpusCodecException(this.message);

  @override
  String toString() => 'OpusCodecException: $message';
}
