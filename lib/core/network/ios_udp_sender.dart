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
  final _SendtoDart _sendto;
  final _RecvPeekDart? _recvPeek;
  IosUdpSender._(this._fd, this._sendto, this._recvPeek);

  /// Attach to Dart's existing socket by scanning for a UDP fd on [localPort].
  /// Used for the transport socket where the fd is stable.
  static IosUdpSender? open(int localPort) {
    if (!Platform.isIOS) return null;

    final lib = ffi.DynamicLibrary.process();

    final findFd = lib.lookupFunction<_FindUdpFdC, _FindUdpFdDart>(
        'cleona_ios_find_udp_fd');
    final sendto =
        lib.lookupFunction<_SendtoC, _SendtoDart>('cleona_ios_sendto');

    _RecvPeekDart? recvPeek;
    try {
      recvPeek = lib
          .lookupFunction<_RecvPeekC, _RecvPeekDart>('cleona_ios_recv_peek');
    } catch (_) {}

    final fd = findFd(localPort);
    if (fd < 0) return null;

    return IosUdpSender._(fd, sendto, recvPeek);
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

    return IosUdpSender._(fd, sendto, null);
  }

  int get fd => _fd;

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

  int recvPeek() => _recvPeek?.call(_fd) ?? -999;
}
