/// FFI bindings for VP8 video codec via libcleona_vpx shim.
///
/// VP8 is patent-free (BSD license), suitable for real-time video.
/// The shim wraps libvpx complexity behind a simple opaque-pointer API.
///
/// Configuration:
/// - VP8 encoder with CBR (Constant Bit Rate)
/// - Real-time encoding (VPX_DL_REALTIME, CPUUSED=8)
/// - Error resilient mode (packet loss tolerant)
/// - I420 pixel format (YUV 4:2:0)
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ── Native Function Types ────────────────────────────────────────────

// void* cleona_vpx_encoder_create(int w, int h, int bitrate, int fps, int kf_interval)
typedef _EncoderCreateNative = Pointer<Void> Function(
    Int32, Int32, Int32, Int32, Int32);
typedef _EncoderCreateDart = Pointer<Void> Function(int, int, int, int, int);

// int cleona_vpx_encoder_encode(void*, uint8_t*, int, uint8_t**, int*, int*)
typedef _EncoderEncodeNative = Int32 Function(Pointer<Void>, Pointer<Uint8>,
    Int32, Pointer<Pointer<Uint8>>, Pointer<Int32>, Pointer<Int32>);
typedef _EncoderEncodeDart = int Function(Pointer<Void>, Pointer<Uint8>, int,
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Pointer<Int32>);

// int cleona_vpx_encoder_set_bitrate(void*, int)
typedef _EncoderSetBitrateNative = Int32 Function(Pointer<Void>, Int32);
typedef _EncoderSetBitrateDart = int Function(Pointer<Void>, int);

// void cleona_vpx_encoder_destroy(void*)
typedef _EncoderDestroyNative = Void Function(Pointer<Void>);
typedef _EncoderDestroyDart = void Function(Pointer<Void>);

// void* cleona_vpx_decoder_create()
typedef _DecoderCreateNative = Pointer<Void> Function();
typedef _DecoderCreateDart = Pointer<Void> Function();

// int cleona_vpx_decoder_decode(void*, uint8_t*, int, uint8_t*, int, int*, int*)
typedef _DecoderDecodeNative = Int32 Function(Pointer<Void>, Pointer<Uint8>,
    Int32, Pointer<Uint8>, Int32, Pointer<Int32>, Pointer<Int32>);
typedef _DecoderDecodeDart = int Function(Pointer<Void>, Pointer<Uint8>, int,
    Pointer<Uint8>, int, Pointer<Int32>, Pointer<Int32>);

// void cleona_vpx_decoder_destroy(void*)
typedef _DecoderDestroyNative = Void Function(Pointer<Void>);
typedef _DecoderDestroyDart = void Function(Pointer<Void>);

// int cleona_vpx_available()
typedef _AvailableNative = Int32 Function();
typedef _AvailableDart = int Function();

// ── VpxFFI Class ─────────────────────────────────────────────────────

/// VP8 video encoder/decoder via libcleona_vpx shim + libvpx.
///
/// Usage:
/// ```dart
/// final vpx = VpxFFI(width: 640, height: 480, bitrateKbps: 1000, fps: 30);
/// final encoded = vpx.encode(i420Data);       // I420 → VP8
/// final decoded = vpx.decode(encoded.data);   // VP8 → I420
/// vpx.dispose();
/// ```
class VpxFFI {
  DynamicLibrary? _lib;
  Pointer<Void>? _encoder;
  Pointer<Void>? _decoder;
  bool _disposed = false;

  final int width;
  final int height;
  final int bitrateKbps;
  final int fps;
  final int keyframeInterval;

  // Cached native function pointers
  _EncoderEncodeDart? _encode;
  _EncoderSetBitrateDart? _setBitrate;
  _EncoderDestroyDart? _encoderDestroy;
  _DecoderDecodeDart? _decode;
  _DecoderDestroyDart? _decoderDestroy;

  // Reusable native buffers for encode output
  late Pointer<Pointer<Uint8>> _outDataPtr;
  late Pointer<Int32> _outSizePtr;
  late Pointer<Int32> _outKeyframePtr;

  // Reusable native buffers for decode output
  Pointer<Uint8>? _decodeOutBuf;
  int _decodeOutBufSize = 0;
  late Pointer<Int32> _decWidthPtr;
  late Pointer<Int32> _decHeightPtr;

  /// I420 frame size in bytes for the configured resolution.
  int get i420Size => width * height * 3 ~/ 2;

  /// Create a VP8 encoder + decoder.
  ///
  /// [width], [height]: frame dimensions (must be even).
  /// [bitrateKbps]: target bitrate in kbps (e.g., 1000 = 1 Mbps).
  /// [fps]: target framerate (e.g., 30).
  /// [keyframeInterval]: max frames between keyframes (e.g., 60 = 2s at 30fps).
  VpxFFI({
    required this.width,
    required this.height,
    this.bitrateKbps = 1000,
    this.fps = 30,
    this.keyframeInterval = 60,
  }) {
    _loadLibrary();
    _createEncoder();
    _createDecoder();
    _allocBuffers();
  }

  void _loadLibrary() {
    final shimPaths = _shimSearchPaths();
    for (final path in shimPaths) {
      try {
        _lib = DynamicLibrary.open(path);
        break;
      } catch (_) {
        continue;
      }
    }
    if (_lib == null) {
      final suffix = Platform.isMacOS ? 'dylib' : (Platform.isWindows ? 'dll' : 'so');
      throw VpxNotAvailableException(
          'libcleona_vpx.$suffix not found. Build: cd native && '
          'gcc -shared -fPIC -O2 -o libcleona_vpx.$suffix vpx_shim.c -ldl');
    }

    // Check that libvpx itself is loadable
    final available = _lib!
        .lookupFunction<_AvailableNative, _AvailableDart>('cleona_vpx_available');
    if (available() != 0) {
      throw VpxNotAvailableException(
          'libvpx not found. Please install: apt install libvpx9');
    }

    _encode = _lib!.lookupFunction<_EncoderEncodeNative, _EncoderEncodeDart>(
        'cleona_vpx_encoder_encode');
    _setBitrate = _lib!
        .lookupFunction<_EncoderSetBitrateNative, _EncoderSetBitrateDart>(
            'cleona_vpx_encoder_set_bitrate');
    _encoderDestroy = _lib!
        .lookupFunction<_EncoderDestroyNative, _EncoderDestroyDart>(
            'cleona_vpx_encoder_destroy');
    _decode = _lib!.lookupFunction<_DecoderDecodeNative, _DecoderDecodeDart>(
        'cleona_vpx_decoder_decode');
    _decoderDestroy = _lib!
        .lookupFunction<_DecoderDestroyNative, _DecoderDestroyDart>(
            'cleona_vpx_decoder_destroy');
  }

  void _createEncoder() {
    final create = _lib!
        .lookupFunction<_EncoderCreateNative, _EncoderCreateDart>(
            'cleona_vpx_encoder_create');
    _encoder = create(width, height, bitrateKbps, fps, keyframeInterval);
    if (_encoder == null || _encoder == nullptr) {
      throw VpxNotAvailableException(
          'Failed to create VP8 encoder (${width}x$height, ${bitrateKbps}kbps)');
    }
  }

  void _createDecoder() {
    final create = _lib!
        .lookupFunction<_DecoderCreateNative, _DecoderCreateDart>(
            'cleona_vpx_decoder_create');
    _decoder = create();
    if (_decoder == null || _decoder == nullptr) {
      throw VpxNotAvailableException('Failed to create VP8 decoder');
    }
  }

  void _allocBuffers() {
    _outDataPtr = calloc<Pointer<Uint8>>();
    _outSizePtr = calloc<Int32>();
    _outKeyframePtr = calloc<Int32>();
    _decWidthPtr = calloc<Int32>();
    _decHeightPtr = calloc<Int32>();
  }

  /// Encode one I420 frame to VP8.
  ///
  /// [i420Data]: Raw I420 pixel data (width * height * 3/2 bytes).
  /// [forceKeyframe]: Force this frame to be a keyframe.
  /// Returns [VpxEncodeResult] with encoded data, or null if buffering.
  VpxEncodeResult? encode(Uint8List i420Data, {bool forceKeyframe = false}) {
    if (_disposed || _encoder == null) {
      throw VpxNotAvailableException('Encoder disposed');
    }
    if (i420Data.length < i420Size) {
      throw VpxCodecException(
          'I420 data too small: ${i420Data.length} < $i420Size');
    }

    final inputPtr = calloc<Uint8>(i420Data.length);
    try {
      inputPtr.asTypedList(i420Data.length).setAll(0, i420Data);

      final ret = _encode!(_encoder!, inputPtr, forceKeyframe ? 1 : 0,
          _outDataPtr, _outSizePtr, _outKeyframePtr);

      if (ret < 0) {
        throw VpxCodecException('VP8 encode failed: $ret');
      }
      if (ret == 1) return null; // buffering

      final size = _outSizePtr.value;
      if (size <= 0) return null;

      // Copy output data (pointer is only valid until next encode call)
      final outPtr = _outDataPtr.value;
      final data = Uint8List.fromList(outPtr.asTypedList(size));

      return VpxEncodeResult(
        data: data,
        isKeyframe: _outKeyframePtr.value != 0,
      );
    } finally {
      calloc.free(inputPtr);
    }
  }

  /// Decode one VP8 frame to I420.
  ///
  /// [vpxData]: Compressed VP8 frame data.
  /// Returns [VpxDecodeResult] with decoded I420 pixels and dimensions.
  VpxDecodeResult? decode(Uint8List vpxData) {
    if (_disposed || _decoder == null) {
      throw VpxNotAvailableException('Decoder disposed');
    }

    // Ensure decode output buffer is large enough.
    // Max: 1920*1080*3/2 = ~3.1MB (should be sufficient for any call).
    final maxSize = 1920 * 1080 * 3 ~/ 2;
    if (_decodeOutBuf == null || _decodeOutBufSize < maxSize) {
      if (_decodeOutBuf != null) calloc.free(_decodeOutBuf!);
      _decodeOutBuf = calloc<Uint8>(maxSize);
      _decodeOutBufSize = maxSize;
    }

    final inputPtr = calloc<Uint8>(vpxData.length);
    try {
      inputPtr.asTypedList(vpxData.length).setAll(0, vpxData);

      final ret = _decode!(_decoder!, inputPtr, vpxData.length,
          _decodeOutBuf!, _decodeOutBufSize, _decWidthPtr, _decHeightPtr);

      if (ret < 0) {
        throw VpxCodecException('VP8 decode failed: $ret');
      }
      if (ret == 1) return null; // no frame yet

      final w = _decWidthPtr.value;
      final h = _decHeightPtr.value;
      if (w <= 0 || h <= 0) return null;

      final frameSize = w * h * 3 ~/ 2;
      final i420 = Uint8List.fromList(_decodeOutBuf!.asTypedList(frameSize));

      return VpxDecodeResult(i420Data: i420, width: w, height: h);
    } finally {
      calloc.free(inputPtr);
    }
  }

  /// Update target bitrate (for adaptive bitrate control).
  void setBitrate(int kbps) {
    if (_disposed || _encoder == null) return;
    _setBitrate!(_encoder!, kbps);
  }

  /// Release all resources.
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
    calloc.free(_outDataPtr);
    calloc.free(_outSizePtr);
    calloc.free(_outKeyframePtr);
    calloc.free(_decWidthPtr);
    calloc.free(_decHeightPtr);
    if (_decodeOutBuf != null) {
      calloc.free(_decodeOutBuf!);
      _decodeOutBuf = null;
    }
  }

  /// Check if VP8 codec is available on the system.
  static bool isAvailable() {
    try {
      final paths = _shimSearchPaths();
      for (final path in paths) {
        try {
          final lib = DynamicLibrary.open(path);
          final check = lib.lookupFunction<_AvailableNative, _AvailableDart>(
              'cleona_vpx_available');
          return check() == 0;
        } catch (_) {
          continue;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static List<String> _shimSearchPaths() {
    final exe = Platform.resolvedExecutable;
    final sep = Platform.isWindows ? '\\' : '/';
    final lastSep = exe.lastIndexOf(sep);
    final exeDir = lastSep > 0 ? exe.substring(0, lastSep) : '.';

    if (Platform.isMacOS) {
      return [
        'libcleona_vpx.dylib',
        '$exeDir/libcleona_vpx.dylib',
        '$exeDir/../Frameworks/libcleona_vpx.dylib',
        '$exeDir/../native/libcleona_vpx.dylib',
        'native/libcleona_vpx.dylib',
      ];
    }
    if (Platform.isWindows) {
      return [
        'cleona_vpx.dll',
        '$exeDir\\cleona_vpx.dll',
        '$exeDir\\native\\cleona_vpx.dll',
        'native\\cleona_vpx.dll',
      ];
    }
    // Linux + Android
    return [
      'libcleona_vpx.so',
      '$exeDir/libcleona_vpx.so',
      '$exeDir/lib/libcleona_vpx.so',
      '$exeDir/../native/libcleona_vpx.so',
      'native/libcleona_vpx.so',
      '/home/claude/Cleona/native/libcleona_vpx.so',
    ];
  }
}

/// Result of VP8 encoding.
class VpxEncodeResult {
  final Uint8List data;
  final bool isKeyframe;

  VpxEncodeResult({required this.data, required this.isKeyframe});
}

/// Result of VP8 decoding.
class VpxDecodeResult {
  final Uint8List i420Data;
  final int width;
  final int height;

  VpxDecodeResult({
    required this.i420Data,
    required this.width,
    required this.height,
  });
}

/// libcleona_vpx or libvpx not available.
class VpxNotAvailableException implements Exception {
  final String message;
  VpxNotAvailableException(this.message);

  @override
  String toString() => 'VpxNotAvailableException: $message';
}

/// VP8 codec error.
class VpxCodecException implements Exception {
  final String message;
  VpxCodecException(this.message);

  @override
  String toString() => 'VpxCodecException: $message';
}
