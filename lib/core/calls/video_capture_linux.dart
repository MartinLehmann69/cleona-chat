/// V4L2 camera capture for Linux via libcleona_v4l2 shim.
///
/// Provides non-blocking frame grabbing from USB/built-in cameras.
/// Supports I420 (native) and YUYV (converted to I420) pixel formats.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ── V4L2 pixel format codes ──────────────────────────────────────────

/// V4L2_PIX_FMT_YUV420 (I420)
const int v4l2FmtI420 = 0x32315559; // 'YU12'

/// V4L2_PIX_FMT_YUYV
const int v4l2FmtYuyv = 0x56595559; // 'YUYV'

/// V4L2_PIX_FMT_MJPEG
const int v4l2FmtMjpeg = 0x47504A4D; // 'MJPG'

// ── Native Function Types ────────────────────────────────────────────

typedef _OpenNative = Pointer<Void> Function(
    Pointer<Utf8>, Int32, Int32, Int32);
typedef _OpenDart = Pointer<Void> Function(Pointer<Utf8>, int, int, int);

typedef _GetSizeNative = Void Function(
    Pointer<Void>, Pointer<Int32>, Pointer<Int32>, Pointer<Uint32>);
typedef _GetSizeDart = void Function(
    Pointer<Void>, Pointer<Int32>, Pointer<Int32>, Pointer<Uint32>);

typedef _StartNative = Int32 Function(Pointer<Void>);
typedef _StartDart = int Function(Pointer<Void>);

typedef _GrabFrameNative = Pointer<Uint8> Function(
    Pointer<Void>, Pointer<Int32>);
typedef _GrabFrameDart = Pointer<Uint8> Function(
    Pointer<Void>, Pointer<Int32>);

typedef _YuyvToI420Native = Void Function(
    Pointer<Uint8>, Pointer<Uint8>, Int32, Int32);
typedef _YuyvToI420Dart = void Function(
    Pointer<Uint8>, Pointer<Uint8>, int, int);

typedef _StopNative = Int32 Function(Pointer<Void>);
typedef _StopDart = int Function(Pointer<Void>);

typedef _CloseNative = Void Function(Pointer<Void>);
typedef _CloseDart = void Function(Pointer<Void>);

typedef _AvailableNative = Int32 Function();
typedef _AvailableDart = int Function();

// ── VideoCaptureLinux ────────────────────────────────────────────────

/// V4L2 camera capture for Linux.
///
/// Usage:
/// ```dart
/// final cam = VideoCaptureLinux('/dev/video0', width: 640, height: 480, fps: 30);
/// cam.start();
/// final frame = cam.grabI420Frame(); // Returns I420 Uint8List or null
/// cam.stop();
/// cam.close();
/// ```
class VideoCaptureLinux {
  DynamicLibrary? _lib;
  Pointer<Void>? _handle;
  bool _closed = false;

  late int width;
  late int height;
  late int pixelFormat;

  // Cached function pointers
  late _StartDart _start;
  late _GrabFrameDart _grabFrame;
  late _YuyvToI420Dart _yuyvToI420;
  late _StopDart _stop;
  late _CloseDart _closeHandle;

  // Reusable native buffers
  late Pointer<Int32> _frameSizePtr;
  Pointer<Uint8>? _i420ConvertBuf;
  int _i420BufSize = 0;

  /// Open a V4L2 camera.
  ///
  /// [device]: e.g., "/dev/video0".
  /// [width], [height]: requested resolution (may be adjusted by driver).
  /// [fps]: requested framerate.
  VideoCaptureLinux(String device, {
    int width = 640,
    int height = 480,
    int fps = 30,
  }) {
    _loadLibrary();
    _openDevice(device, width, height, fps);
    _frameSizePtr = calloc<Int32>();
  }

  void _loadLibrary() {
    final paths = _shimSearchPaths();
    for (final path in paths) {
      try {
        _lib = DynamicLibrary.open(path);
        break;
      } catch (_) {
        continue;
      }
    }
    if (_lib == null) {
      throw V4l2NotAvailableException(
          'libcleona_v4l2.so not found. Build: cd native && gcc -shared -fPIC -O2 -o libcleona_v4l2.so v4l2_shim.c');
    }

    _start = _lib!.lookupFunction<_StartNative, _StartDart>('cleona_v4l2_start');
    _grabFrame = _lib!.lookupFunction<_GrabFrameNative, _GrabFrameDart>(
        'cleona_v4l2_grab_frame');
    _yuyvToI420 = _lib!.lookupFunction<_YuyvToI420Native, _YuyvToI420Dart>(
        'cleona_v4l2_yuyv_to_i420');
    _stop = _lib!.lookupFunction<_StopNative, _StopDart>('cleona_v4l2_stop');
    _closeHandle =
        _lib!.lookupFunction<_CloseNative, _CloseDart>('cleona_v4l2_close');
  }

  void _openDevice(String device, int reqWidth, int reqHeight, int fps) {
    final open =
        _lib!.lookupFunction<_OpenNative, _OpenDart>('cleona_v4l2_open');
    final devicePtr = device.toNativeUtf8();
    try {
      _handle = open(devicePtr, reqWidth, reqHeight, fps);
    } finally {
      calloc.free(devicePtr);
    }
    if (_handle == null || _handle == nullptr) {
      throw V4l2NotAvailableException('Failed to open camera: $device');
    }

    // Read back negotiated size/format
    final getSize =
        _lib!.lookupFunction<_GetSizeNative, _GetSizeDart>('cleona_v4l2_get_size');
    final wPtr = calloc<Int32>();
    final hPtr = calloc<Int32>();
    final fmtPtr = calloc<Uint32>();
    try {
      getSize(_handle!, wPtr, hPtr, fmtPtr);
      width = wPtr.value;
      height = hPtr.value;
      pixelFormat = fmtPtr.value;
    } finally {
      calloc.free(wPtr);
      calloc.free(hPtr);
      calloc.free(fmtPtr);
    }
  }

  /// Start streaming.
  void start() {
    if (_closed || _handle == null) return;
    final ret = _start(_handle!);
    if (ret != 0) {
      throw V4l2Exception('Failed to start streaming: error $ret');
    }
  }

  /// Grab the latest frame as I420 data. Non-blocking.
  /// Returns null if no frame is ready.
  Uint8List? grabI420Frame() {
    if (_closed || _handle == null) return null;

    final framePtr = _grabFrame(_handle!, _frameSizePtr);
    if (framePtr == nullptr || _frameSizePtr.value <= 0) return null;

    final i420Size = width * height * 3 ~/ 2;

    if (pixelFormat == v4l2FmtI420) {
      // Native I420 — copy directly
      return Uint8List.fromList(framePtr.asTypedList(i420Size));
    } else if (pixelFormat == v4l2FmtYuyv) {
      // YUYV → I420 conversion
      _ensureI420Buffer(i420Size);
      _yuyvToI420(framePtr, _i420ConvertBuf!, width, height);
      return Uint8List.fromList(_i420ConvertBuf!.asTypedList(i420Size));
    } else {
      // MJPEG or unsupported — skip (TODO: add MJPEG decoding if needed)
      return null;
    }
  }

  void _ensureI420Buffer(int size) {
    if (_i420ConvertBuf == null || _i420BufSize < size) {
      if (_i420ConvertBuf != null) calloc.free(_i420ConvertBuf!);
      _i420ConvertBuf = calloc<Uint8>(size);
      _i420BufSize = size;
    }
  }

  /// Stop streaming.
  void stop() {
    if (_closed || _handle == null) return;
    _stop(_handle!);
  }

  /// Close camera and free resources.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_handle != null && _handle != nullptr) {
      _closeHandle(_handle!);
      _handle = null;
    }
    calloc.free(_frameSizePtr);
    if (_i420ConvertBuf != null) {
      calloc.free(_i420ConvertBuf!);
      _i420ConvertBuf = null;
    }
  }

  /// I420 frame size for current resolution.
  int get i420Size => width * height * 3 ~/ 2;

  /// Whether any V4L2 camera is available.
  static bool isAvailable() {
    try {
      final paths = _shimSearchPaths();
      for (final path in paths) {
        try {
          final lib = DynamicLibrary.open(path);
          final check = lib.lookupFunction<_AvailableNative, _AvailableDart>(
              'cleona_v4l2_available');
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
    final exeDir = exe.substring(0, exe.lastIndexOf('/'));
    return [
      'libcleona_v4l2.so',
      '$exeDir/libcleona_v4l2.so',
      '$exeDir/lib/libcleona_v4l2.so',
      '$exeDir/../native/libcleona_v4l2.so',
      'native/libcleona_v4l2.so',
      '/home/claude/Cleona/native/libcleona_v4l2.so',
    ];
  }
}

/// V4L2 capture not available.
class V4l2NotAvailableException implements Exception {
  final String message;
  V4l2NotAvailableException(this.message);

  @override
  String toString() => 'V4l2NotAvailableException: $message';
}

/// V4L2 capture error.
class V4l2Exception implements Exception {
  final String message;
  V4l2Exception(this.message);

  @override
  String toString() => 'V4l2Exception: $message';
}
