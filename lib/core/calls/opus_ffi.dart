/// FFI bindings for libopus (audio codec).
///
/// Opus is the standard codec for VoIP (RFC 6716).
/// Reduces audio bandwidth from 256 kbps (raw PCM) to ~32-64 kbps.
///
/// Configuration:
/// - 16 kHz sample rate (matches PulseAudio capture)
/// - Mono
/// - 20ms frame duration (960 samples at 48kHz, 320 at 16kHz)
/// - Bitrate: 32 kbps (VOIP Application)
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

/// Sample rate for Cleona audio.
const int opusSampleRate = 16000;

/// Mono.
const int opusChannels = 1;

/// Frame duration in samples (20ms at 16kHz = 320 samples).
const int opusFrameSamples = opusSampleRate * 20 ~/ 1000; // 320

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

// ── OpusFFI Class ────────────────────────────────────────────────────────

/// FFI wrapper for the libopus audio codec.
///
/// Usage:
/// ```dart
/// final opus = OpusFFI();
/// final encoded = opus.encode(pcm16Data);  // PCM → Opus
/// final decoded = opus.decode(encoded);     // Opus → PCM
/// opus.dispose();
/// ```
class OpusFFI {
  DynamicLibrary? _lib;
  Pointer<Void>? _encoder;
  Pointer<Void>? _decoder;
  bool _disposed = false;

  // Lazy-initialized function pointers
  _OpusEncoderCreateDart? _encoderCreate;
  _OpusEncoderDestroyDart? _encoderDestroy;
  _OpusEncodeDart? _encode;
  _OpusDecoderCreateDart? _decoderCreate;
  _OpusDecoderDestroyDart? _decoderDestroy;
  _OpusDecodeDart? _decode;

  /// Initialize the Opus codec.
  ///
  /// Loads libopus and creates encoder + decoder.
  /// Throws [OpusNotAvailableException] if libopus is not found.
  OpusFFI() {
    _loadLibrary();
    _createEncoder();
    _createDecoder();
  }

  void _loadLibrary() {
    final libNames = _libSearchPaths();

    for (final name in libNames) {
      try {
        _lib = DynamicLibrary.open(name);
        break;
      } catch (_) {
        continue;
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
  }

  static List<String> _libSearchPaths() {
    if (Platform.isMacOS || Platform.isIOS) {
      // iOS: Embedded Framework via DynamicLibrary.process() würde sauberer
      // sein; bis das Pod-Setup steht, nutzen wir die gleichen .dylib-Namen
      // wie macOS (failt zur Runtime falls nicht gebaut).
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
          opusSampleRate, opusChannels, opusApplicationVoip, err);
      if (err.value != opusOk || _encoder == null || _encoder == nullptr) {
        throw OpusNotAvailableException(
            'Failed to create Opus encoder: error=${err.value}');
      }
    } finally {
      calloc.free(err);
    }
  }

  void _createDecoder() {
    final err = calloc<Int32>();
    try {
      _decoder = _decoderCreate!(opusSampleRate, opusChannels, err);
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
  /// [pcm16]: Int16 PCM data (mono, 16kHz, 20ms = 640 bytes = 320 samples).
  /// Returns compressed Opus packet (~40-120 bytes at 32kbps).
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
  /// Returns PCM-16 data (mono, 16kHz, 640 bytes = 320 samples).
  Uint8List decode(Uint8List opusData) {
    if (_disposed || _decoder == null) {
      throw OpusNotAvailableException('Decoder disposed');
    }

    final inputPtr = calloc<Uint8>(opusData.length);
    final outputPtr = calloc<Int16>(opusFrameSamples);

    try {
      inputPtr.asTypedList(opusData.length).setAll(0, opusData);

      final decodedSamples = _decode!(
        _decoder!,
        inputPtr,
        opusData.length,
        outputPtr,
        opusFrameSamples,
        0, // decode_fec: 0 = no Forward Error Correction
      );

      if (decodedSamples < 0) {
        throw OpusCodecException('Opus decode failed: $decodedSamples');
      }

      // Int16 → Uint8 (Little-Endian)
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

    final outputPtr = calloc<Int16>(opusFrameSamples);
    try {
      final decodedSamples = _decode!(
        _decoder!,
        nullptr.cast<Uint8>(),
        0, // len = 0 → PLC
        outputPtr,
        opusFrameSamples,
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
