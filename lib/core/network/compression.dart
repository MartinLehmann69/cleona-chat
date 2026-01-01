import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// --- Zstd FFI type definitions ---

typedef _ZstdCompressNative = IntPtr Function(
    Pointer<Void> dst,
    IntPtr dstCapacity,
    Pointer<Void> src,
    IntPtr srcSize,
    Int32 compressionLevel);
typedef _ZstdCompressDart = int Function(
    Pointer<Void> dst,
    int dstCapacity,
    Pointer<Void> src,
    int srcSize,
    int compressionLevel);

typedef _ZstdDecompressNative = IntPtr Function(
    Pointer<Void> dst,
    IntPtr dstCapacity,
    Pointer<Void> src,
    IntPtr compressedSize);
typedef _ZstdDecompressDart = int Function(
    Pointer<Void> dst, int dstCapacity, Pointer<Void> src, int compressedSize);

typedef _ZstdIsErrorNative = Uint32 Function(IntPtr code);
typedef _ZstdIsErrorDart = int Function(int code);

typedef _ZstdGetFrameContentSizeNative = Uint64 Function(
    Pointer<Void> src, IntPtr srcSize);
typedef _ZstdGetFrameContentSizeDart = int Function(
    Pointer<Void> src, int srcSize);

typedef _ZstdCompressBoundNative = IntPtr Function(IntPtr srcSize);
typedef _ZstdCompressBoundDart = int Function(int srcSize);

/// Zstandard compression via FFI to libzstd.
///
/// Usage:
/// ```dart
/// final compressed = ZstdCompression.instance.compress(payload);
/// final original = ZstdCompression.instance.decompress(compressed);
/// ```
class ZstdCompression {
  ZstdCompression._() {
    _lib = DynamicLibrary.open(_libName());
    _compress =
        _lib.lookupFunction<_ZstdCompressNative, _ZstdCompressDart>(
            'ZSTD_compress');
    _decompress =
        _lib.lookupFunction<_ZstdDecompressNative, _ZstdDecompressDart>(
            'ZSTD_decompress');
    _isError =
        _lib.lookupFunction<_ZstdIsErrorNative, _ZstdIsErrorDart>(
            'ZSTD_isError');
    _getFrameContentSize = _lib.lookupFunction<
        _ZstdGetFrameContentSizeNative,
        _ZstdGetFrameContentSizeDart>('ZSTD_getFrameContentSize');
    _compressBound =
        _lib.lookupFunction<_ZstdCompressBoundNative, _ZstdCompressBoundDart>(
            'ZSTD_compressBound');
  }

  static final ZstdCompression instance = ZstdCompression._();

  static String _libName() {
    if (Platform.isWindows) return 'libzstd.dll';
    if (Platform.isMacOS) return 'libzstd.dylib';
    return 'libzstd.so'; // Linux, Android
  }

  late final DynamicLibrary _lib;
  late final _ZstdCompressDart _compress;
  late final _ZstdDecompressDart _decompress;
  late final _ZstdIsErrorDart _isError;
  late final _ZstdGetFrameContentSizeDart _getFrameContentSize;
  late final _ZstdCompressBoundDart _compressBound;

  /// Sentinel returned by ZSTD_getFrameContentSize when the size is unknown.
  static const int _contentSizeUnknown = -1; // ZSTD_CONTENTSIZE_UNKNOWN
  /// Sentinel returned when the frame header is invalid.
  static const int _contentSizeError = -2; // ZSTD_CONTENTSIZE_ERROR

  /// Initial buffer size used when decompressed size is unknown.
  static const int _defaultDecompressBuffer = 256 * 1024; // 256 KiB

  /// Compress [data] using Zstandard at the given [level] (1-22, default 3).
  ///
  /// Returns the compressed bytes. Throws [ZstdException] on failure.
  Uint8List compress(Uint8List data, {int level = 3}) {
    if (data.isEmpty) return Uint8List(0);

    final srcSize = data.length;
    final dstCapacity = _compressBound(srcSize);

    final src = malloc.allocate<Uint8>(srcSize);
    final dst = malloc.allocate<Uint8>(dstCapacity);

    try {
      src.asTypedList(srcSize).setAll(0, data);

      final result = _compress(
          dst.cast<Void>(), dstCapacity, src.cast<Void>(), srcSize, level);

      if (_isError(result) != 0) {
        throw ZstdException('ZSTD_compress failed (code $result)');
      }

      return Uint8List.fromList(dst.asTypedList(result));
    } finally {
      malloc.free(src);
      malloc.free(dst);
    }
  }

  /// Decompress Zstandard-compressed [data].
  ///
  /// Uses `ZSTD_getFrameContentSize` to determine the output buffer size.
  /// Falls back to a growing-buffer approach when the content size is unknown.
  /// Throws [ZstdException] on failure.
  Uint8List decompress(Uint8List data) {
    if (data.isEmpty) return Uint8List(0);

    final srcSize = data.length;
    final src = malloc.allocate<Uint8>(srcSize);

    try {
      src.asTypedList(srcSize).setAll(0, data);

      final frameSize =
          _getFrameContentSize(src.cast<Void>(), srcSize);

      if (frameSize == _contentSizeError) {
        throw ZstdException(
            'ZSTD_getFrameContentSize: invalid frame header');
      }

      if (frameSize != _contentSizeUnknown && frameSize >= 0) {
        return _decompressKnownSize(src, srcSize, frameSize);
      }

      // Unknown content size -- use a growing buffer.
      return _decompressUnknownSize(src, srcSize);
    } finally {
      malloc.free(src);
    }
  }

  Uint8List _decompressKnownSize(
      Pointer<Uint8> src, int srcSize, int dstCapacity) {
    final dst = malloc.allocate<Uint8>(dstCapacity);
    try {
      final result = _decompress(
          dst.cast<Void>(), dstCapacity, src.cast<Void>(), srcSize);

      if (_isError(result) != 0) {
        throw ZstdException('ZSTD_decompress failed (code $result)');
      }

      return Uint8List.fromList(dst.asTypedList(result));
    } finally {
      malloc.free(dst);
    }
  }

  Uint8List _decompressUnknownSize(Pointer<Uint8> src, int srcSize) {
    var dstCapacity = _defaultDecompressBuffer;

    // Try increasing buffer sizes until decompression succeeds.
    for (var attempt = 0; attempt < 10; attempt++) {
      final dst = malloc.allocate<Uint8>(dstCapacity);
      try {
        final result = _decompress(
            dst.cast<Void>(), dstCapacity, src.cast<Void>(), srcSize);

        if (_isError(result) != 0) {
          // Buffer too small -- double and retry.
          dstCapacity *= 2;
          continue;
        }

        return Uint8List.fromList(dst.asTypedList(result));
      } finally {
        malloc.free(dst);
      }
    }

    throw ZstdException(
        'ZSTD_decompress: failed after growing buffer to $dstCapacity bytes');
  }
}

/// Exception thrown when a Zstandard operation fails.
class ZstdException implements Exception {
  ZstdException(this.message);

  final String message;

  @override
  String toString() => 'ZstdException: $message';
}
