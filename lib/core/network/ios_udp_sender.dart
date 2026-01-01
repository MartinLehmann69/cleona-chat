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

class IosUdpSender {
  final int _fd;
  final _SendtoDart _sendto;

  IosUdpSender._(this._fd, this._sendto);

  static IosUdpSender? open(int localPort) {
    if (!Platform.isIOS) return null;

    final lib = ffi.DynamicLibrary.process();

    final findFd = lib.lookupFunction<_FindUdpFdC, _FindUdpFdDart>(
        'cleona_ios_find_udp_fd');
    final sendto =
        lib.lookupFunction<_SendtoC, _SendtoDart>('cleona_ios_sendto');

    final fd = findFd(localPort);
    if (fd < 0) return null;

    return IosUdpSender._(fd, sendto);
  }

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
}
