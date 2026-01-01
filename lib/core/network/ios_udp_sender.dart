import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef _FindUdpFdC = ffi.Int32 Function(ffi.Int32 localPort);
typedef _FindUdpFdDart = int Function(int localPort);

typedef _SendtoC = ffi.Int32 Function(
    ffi.Int32 fd,
    ffi.Pointer<Utf8> destIp,
    ffi.Int32 destPort,
    ffi.Pointer<ffi.Uint8> data,
    ffi.Int32 len);
typedef _SendtoDart = int Function(
    int fd,
    ffi.Pointer<Utf8> destIp,
    int destPort,
    ffi.Pointer<ffi.Uint8> data,
    int len);

typedef _RecvPeekC = ffi.Int32 Function(ffi.Int32 fd);
typedef _RecvPeekDart = int Function(int fd);

typedef _CreateSendSocketC = ffi.Int32 Function();
typedef _CreateSendSocketDart = int Function();

class IosUdpSender {
  final int _fd;
  final int _fd6;
  final _SendtoDart _sendto;
  final _SendtoDart _sendto6;
  final _RecvPeekDart? _recvPeek;
  IosUdpSender._(this._fd, this._fd6, this._sendto, this._sendto6, this._recvPeek);

  /// Attach to Dart's existing sockets by scanning for UDP fds on [localPort].
  /// Finds both IPv4 (AF_INET) and IPv6 (AF_INET6) sockets.
  static IosUdpSender? open(int localPort) {
    if (!Platform.isIOS) return null;

    final lib = ffi.DynamicLibrary.process();

    final findFd = lib.lookupFunction<_FindUdpFdC, _FindUdpFdDart>(
        'cleona_ios_find_udp_fd');
    final sendto =
        lib.lookupFunction<_SendtoC, _SendtoDart>('cleona_ios_sendto');

    _FindUdpFdDart? findFd6;
    _SendtoDart? sendto6;
    try {
      findFd6 = lib.lookupFunction<_FindUdpFdC, _FindUdpFdDart>(
          'cleona_ios_find_udp6_fd');
      sendto6 = lib.lookupFunction<_SendtoC, _SendtoDart>(
          'cleona_ios_sendto6');
    } catch (_) {}

    _RecvPeekDart? recvPeek;
    try {
      recvPeek = lib
          .lookupFunction<_RecvPeekC, _RecvPeekDart>('cleona_ios_recv_peek');
    } catch (_) {}

    final fd = findFd(localPort);
    if (fd < 0) return null;

    final fd6 = findFd6?.call(localPort) ?? -1;

    return IosUdpSender._(fd, fd6, sendto, sendto6 ?? sendto, recvPeek);
  }

  /// Create a fresh native UDP socket for send-only use (broadcast+unicast).
  /// Used for discovery where Dart's socket fd is unstable on iOS.
  /// Receives still go through Dart's socket on the discovery port.
  static IosUdpSender? createSendOnly() {
    if (!Platform.isIOS) return null;

    final lib = ffi.DynamicLibrary.process();

    final createSocket = lib.lookupFunction<_CreateSendSocketC,
        _CreateSendSocketDart>('cleona_ios_create_send_socket');
    final sendto =
        lib.lookupFunction<_SendtoC, _SendtoDart>('cleona_ios_sendto');

    final fd = createSocket();
    if (fd < 0) return null;

    return IosUdpSender._(fd, -1, sendto, sendto, null);
  }

  int get fd => _fd;
  int get fd6 => _fd6;
  bool get hasIpv6 => _fd6 >= 0;

  int send(String destIp, int destPort, Uint8List data) {
    final ipPtr = destIp.toNativeUtf8();
    final dataPtr = calloc<ffi.Uint8>(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      return _sendto(_fd, ipPtr.cast(), destPort, dataPtr, data.length);
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
      return _sendto6(_fd6, ipPtr.cast(), destPort, dataPtr, data.length);
    } finally {
      calloc.free(ipPtr);
      calloc.free(dataPtr);
    }
  }

  int recvPeek() => _recvPeek?.call(_fd) ?? -999;
}
