import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef _SendtoFdC = ffi.Int32 Function(
    ffi.Int32 fd,
    ffi.Pointer<Utf8> destIp,
    ffi.Uint16 destPort,
    ffi.Pointer<ffi.Uint8> data,
    ffi.Int32 len);
typedef _SendtoFdDart = int Function(
    int fd,
    ffi.Pointer<Utf8> destIp,
    int destPort,
    ffi.Pointer<ffi.Uint8> data,
    int len);

typedef _FindUdp4FdC = ffi.Int32 Function(ffi.Uint16 localPort);
typedef _FindUdp4FdDart = int Function(int localPort);

typedef _FindUdp6FdC = ffi.Int32 Function(ffi.Uint16 localPort);
typedef _FindUdp6FdDart = int Function(int localPort);

typedef _VersionC = ffi.Pointer<Utf8> Function();
typedef _VersionDart = ffi.Pointer<Utf8> Function();

class AndroidUdpSender {
  final int _fd4;
  final int _fd6;
  final _SendtoFdDart _sendtoFd;

  AndroidUdpSender._(this._fd4, this._fd6, this._sendtoFd);

  static ffi.DynamicLibrary? _libCache;

  static AndroidUdpSender? open(int localPort) {
    if (!Platform.isAndroid) return null;

    final lib = _loadLibrary();
    if (lib == null) return null;

    final findFd4 =
        lib.lookupFunction<_FindUdp4FdC, _FindUdp4FdDart>('cleona_find_udp4_fd');
    final findFd6 =
        lib.lookupFunction<_FindUdp6FdC, _FindUdp6FdDart>('cleona_find_udp6_fd');
    final sendtoFd =
        lib.lookupFunction<_SendtoFdC, _SendtoFdDart>('cleona_udp_sendto_fd');

    final fd4 = findFd4(localPort);
    if (fd4 < 0) return null;

    final fd6 = findFd6(localPort);

    return AndroidUdpSender._(fd4, fd6, sendtoFd);
  }

  bool get hasIpv6 => _fd6 >= 0;

  /// Returns bytes sent (>0) on success, or negative errno on failure.
  /// Key errnos: -100 ENETDOWN, -101 ENETUNREACH, -113 EHOSTUNREACH,
  /// -111 ECONNREFUSED, -11 EAGAIN.
  int send(String destIp, int destPort, Uint8List data) {
    final ipPtr = destIp.toNativeUtf8();
    final dataPtr = calloc<ffi.Uint8>(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      return _sendtoFd(_fd4, ipPtr.cast(), destPort, dataPtr, data.length);
    } finally {
      calloc.free(ipPtr);
      calloc.free(dataPtr);
    }
  }

  int send6(String destIp, int destPort, Uint8List data) {
    if (_fd6 < 0) return -97; // EAFNOSUPPORT
    final ipPtr = destIp.toNativeUtf8();
    final dataPtr = calloc<ffi.Uint8>(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      return _sendtoFd(_fd6, ipPtr.cast(), destPort, dataPtr, data.length);
    } finally {
      calloc.free(ipPtr);
      calloc.free(dataPtr);
    }
  }

  /// Re-discover the socket fds (after reconnectUdpSockets).
  AndroidUdpSender? reopen(int localPort) => open(localPort);

  static ffi.DynamicLibrary? _loadLibrary() {
    if (_libCache != null) return _libCache;
    try {
      _libCache = ffi.DynamicLibrary.open('libcleona_net.so');
      return _libCache;
    } catch (_) {
      return null;
    }
  }

  static String? libraryVersion() {
    final lib = _loadLibrary();
    if (lib == null) return null;
    try {
      final fn = lib.lookupFunction<_VersionC, _VersionDart>('cleona_net_version');
      return fn().toDartString();
    } catch (_) {
      return null;
    }
  }

  /// Whether this errno indicates the socket/route is dead (not just peer-specific).
  static bool isSocketDeadErrno(int negErrno) {
    final e = negErrno.abs();
    return e == 100 || // ENETDOWN
        e == 101 || // ENETUNREACH
        e == 99 || // EADDRNOTAVAIL (interface removed)
        e == 9; // EBADF (socket closed)
  }
}
