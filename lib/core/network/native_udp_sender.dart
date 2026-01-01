/*
 * native_udp_sender.dart
 *
 * Dart FFI binding for `libcleona_net` — the direct-syscall UDP send-path
 * shim. See Cleona_Chat_Architecture_v3_0.md §4.5.2 for the architectural
 * rationale.
 *
 * Phase 1 platform scope: Linux x86_64 + Windows x86_64 desktop.
 * Android, iOS, macOS continue to use Dart's RawDatagramSocket and do not
 * load this library.
 *
 * Loading semantics: hard dependency on supported platforms. If the dynamic
 * library cannot be opened at construction time, `NativeUdpSender.open()`
 * throws — callers (LocalDiscovery) are expected to let the exception
 * propagate to the daemon's startup error handler, which logs a clear message
 * and exits non-zero. There is no fallback to Dart's RawDatagramSocket;
 * see §4.5.2 "What happens when something is wrong" for why.
 */

import 'dart:ffi' as ffi;
import 'dart:io' show Platform, File, Directory;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// ── FFI Function Signatures ──────────────────────────────────────────

// cleona_udp_socket_t* cleona_udp_open(uint16_t local_port, int reuse_addr, int broadcast_enable)
typedef _CleonaUdpOpenC = ffi.Pointer<ffi.Void> Function(
    ffi.Uint16 localPort, ffi.Int32 reuseAddr, ffi.Int32 broadcastEnable);
typedef _CleonaUdpOpenDart = ffi.Pointer<ffi.Void> Function(
    int localPort, int reuseAddr, int broadcastEnable);

// int cleona_udp_set_buffers(cleona_udp_socket_t*, int rcv_bytes, int snd_bytes)
typedef _CleonaUdpSetBuffersC = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Int32 rcvBytes, ffi.Int32 sndBytes);
typedef _CleonaUdpSetBuffersDart = int Function(
    ffi.Pointer<ffi.Void>, int rcvBytes, int sndBytes);

// int cleona_udp_send(cleona_udp_socket_t*, const char* dest_ip, uint16_t dest_port, const uint8_t* data, int len)
typedef _CleonaUdpSendC = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Utf8> destIp,
    ffi.Uint16 destPort,
    ffi.Pointer<ffi.Uint8> data,
    ffi.Int32 len);
typedef _CleonaUdpSendDart = int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Utf8> destIp,
    int destPort,
    ffi.Pointer<ffi.Uint8> data,
    int len);

// void cleona_udp_close(cleona_udp_socket_t*)
typedef _CleonaUdpCloseC = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _CleonaUdpCloseDart = void Function(ffi.Pointer<ffi.Void>);

// const char* cleona_net_version()
typedef _CleonaNetVersionC = ffi.Pointer<Utf8> Function();
typedef _CleonaNetVersionDart = ffi.Pointer<Utf8> Function();

// ── Library Loading ──────────────────────────────────────────────────

/// Thrown when the native library cannot be loaded on a platform where it is
/// required (Linux/Windows desktop). The error message names the file that
/// could not be opened so deployment problems are visible immediately.
class NativeUdpLibraryMissingException implements Exception {
  final String expectedPath;
  final Object underlyingError;
  NativeUdpLibraryMissingException(this.expectedPath, this.underlyingError);
  @override
  String toString() =>
      'libcleona_net could not be loaded.\n'
      'Expected path: $expectedPath\n'
      'Underlying error: $underlyingError\n'
      'This is a hard dependency on Linux and Windows desktop builds — see '
      'Cleona_Chat_Architecture_v3_0.md §4.5.2 for why there is no fallback. '
      'Most likely cause: the native build artefact was not copied into the '
      'release bundle. Rebuild native/cleona_net/ and deploy the .so/.dll '
      'alongside the cleona-daemon binary.';
}

/// Thrown on `NativeUdpSender.open` if the C side returns a NULL handle
/// (socket creation, bind, or initial WSAStartup failed inside the shim).
class NativeUdpOpenException implements Exception {
  final int localPort;
  NativeUdpOpenException(this.localPort);
  @override
  String toString() =>
      'cleona_udp_open returned NULL for local port $localPort. Possible '
      'causes: port already bound by another process without SO_REUSEADDR, '
      'WSAStartup failed (Windows), out of file descriptors.';
}

/// Whether this platform participates in the native send path. Phase 1: only
/// Linux x86_64 and Windows x86_64 desktop. Other platforms fall through to
/// Dart's RawDatagramSocket without ever attempting to load the library.
bool nativeUdpSupportedPlatform() {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) return false;
  return Platform.isLinux || Platform.isWindows;
}

/// Build the ordered list of candidate library paths for the current
/// platform. The audio shim uses the same convention (see
/// `audio_engine_shim.dart::load`) and we follow it byte-for-byte so the
/// bundle assembly does not need a second special case.
List<String> _libraryCandidates() {
  final candidates = <String>[];
  if (Platform.isLinux) {
    // Bundled next to the runner (RPATH $ORIGIN/lib resolves this).
    candidates.add('libcleona_net.so');
    // Explicit fallback: <runner_dir>/lib/libcleona_net.so for tests that
    // don't run inside the bundle.
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$exeDir/lib/libcleona_net.so');
    } catch (_) {/* ignore */}
    // Fallback: binary may run from non-canonical path (e.g. ~/cleona-daemon);
    // look for the library in the user's standard cleona-app bundle directory.
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      candidates.add('$home/cleona-app/lib/libcleona_net.so');
    }
    // Build-tree fallback so `dart test` and dev runs work without install.
    candidates.add('${Directory.current.path}/native/cleona_net/build/libcleona_net.so');
  } else if (Platform.isWindows) {
    candidates.add('cleona_net.dll');
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$exeDir\\cleona_net.dll');
    } catch (_) {/* ignore */}
  }
  return candidates;
}

ffi.DynamicLibrary _openLibrary() {
  final candidates = _libraryCandidates();
  Object? lastError;
  for (final c in candidates) {
    try {
      return ffi.DynamicLibrary.open(c);
    } catch (e) {
      lastError = e;
      // try next candidate
    }
  }
  throw NativeUdpLibraryMissingException(candidates.join(', '), lastError ?? 'no candidates');
}

// ── NativeUdpSender — opinionated Dart wrapper ─────────────────────────

/// Synchronous UDP sender backed by `libcleona_net`. Open one per local port;
/// reuse for all sends. Thread-safety: the underlying socket is not protected
/// by a Dart-side mutex — call from a single isolate. (LocalDiscovery is
/// single-isolate today.)
class NativeUdpSender {
  static ffi.DynamicLibrary? _libCache;

  final ffi.Pointer<ffi.Void> _handle;
  final _CleonaUdpSendDart _send;
  final _CleonaUdpSetBuffersDart _setBuffers;
  final _CleonaUdpCloseDart _close;
  bool _closed = false;

  NativeUdpSender._(this._handle, this._send, this._setBuffers, this._close);

  /// Open a UDP socket on local IPv4 ANY:[localPort]. Throws
  /// [NativeUdpLibraryMissingException] if the .so/.dll cannot be loaded
  /// (always — no fallback). Throws [NativeUdpOpenException] if the C side
  /// returns NULL.
  ///
  /// [reuseAddr] enables `SO_REUSEADDR`, required to coexist with Dart's
  /// receive socket on the same port. Default true.
  ///
  /// [broadcastEnable] enables `SO_BROADCAST`, required to send to
  /// 255.255.255.255 or x.x.x.255. Default true.
  factory NativeUdpSender.open({
    required int localPort,
    bool reuseAddr = true,
    bool broadcastEnable = true,
  }) {
    final lib = _libCache ??= _openLibrary();
    final openFn = lib.lookupFunction<_CleonaUdpOpenC, _CleonaUdpOpenDart>('cleona_udp_open');
    final sendFn = lib.lookupFunction<_CleonaUdpSendC, _CleonaUdpSendDart>('cleona_udp_send');
    final setBuffersFn = lib.lookupFunction<_CleonaUdpSetBuffersC, _CleonaUdpSetBuffersDart>('cleona_udp_set_buffers');
    final closeFn = lib.lookupFunction<_CleonaUdpCloseC, _CleonaUdpCloseDart>('cleona_udp_close');

    final handle = openFn(localPort, reuseAddr ? 1 : 0, broadcastEnable ? 1 : 0);
    if (handle == ffi.nullptr) {
      throw NativeUdpOpenException(localPort);
    }
    return NativeUdpSender._(handle, sendFn, setBuffersFn, closeFn);
  }

  /// Set kernel send + receive buffer sizes in bytes. Pass 0 to skip an
  /// option. Returns true on success, false if either setsockopt failed (the
  /// socket remains usable; the OS-default buffer sizes apply).
  bool setBuffers({int rcvBytes = 2 * 1024 * 1024, int sndBytes = 4 * 1024 * 1024}) {
    if (_closed) return false;
    return _setBuffers(_handle, rcvBytes, sndBytes) == 0;
  }

  /// Send one UDP datagram synchronously. Returns the number of bytes sent
  /// (== [data].length on success), or a negative errno-style code on
  /// failure. Use [send]'s return value to detect failures rather than
  /// catching exceptions — the underlying C call does not throw across the
  /// FFI boundary for ordinary network errors.
  int send(String destIp, int destPort, Uint8List data) {
    if (_closed) return -1;
    final ipPtr = destIp.toNativeUtf8();
    final dataPtr = malloc.allocate<ffi.Uint8>(data.length);
    try {
      // Copy the Dart bytes into the C buffer. This is unavoidable because
      // Dart-typed-data backing memory is not directly addressable from C.
      final native = dataPtr.asTypedList(data.length);
      native.setAll(0, data);
      return _send(_handle, ipPtr, destPort, dataPtr, data.length);
    } finally {
      malloc.free(dataPtr);
      malloc.free(ipPtr);
    }
  }

  /// Close the socket. Idempotent.
  void close() {
    if (_closed) return;
    _closed = true;
    _close(_handle);
  }

  /// Diagnostic version string from the shim.
  static String libraryVersion() {
    final lib = _libCache ??= _openLibrary();
    final fn = lib.lookupFunction<_CleonaNetVersionC, _CleonaNetVersionDart>('cleona_net_version');
    return fn().toDartString();
  }
}
