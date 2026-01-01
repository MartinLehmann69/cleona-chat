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

typedef _RecvFromC = ffi.Int32 Function(
    ffi.Int32 fd,
    ffi.Pointer<ffi.Uint8> buf,
    ffi.Int32 buflen,
    ffi.Pointer<ffi.Uint8> srcIp,
    ffi.Int32 srcIpLen,
    ffi.Pointer<ffi.Int32> srcPort);
typedef _RecvFromDart = int Function(
    int fd,
    ffi.Pointer<ffi.Uint8> buf,
    int buflen,
    ffi.Pointer<ffi.Uint8> srcIp,
    int srcIpLen,
    ffi.Pointer<ffi.Int32> srcPort);

class IosRecvResult {
  final Uint8List data;
  final String sourceIp;
  final int sourcePort;
  IosRecvResult(this.data, this.sourceIp, this.sourcePort);
}

class IosUdpSender {
  final int _fd;
  final int _fd6;
  final _SendtoDart _sendto;
  final _SendtoDart _sendto6;
  final _RecvPeekDart? _recvPeek;
  final _RecvFromDart? _recvFrom;
  IosUdpSender._(this._fd, this._fd6, this._sendto, this._sendto6,
      this._recvPeek, this._recvFrom);

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

    _RecvFromDart? recvFrom;
    try {
      recvFrom = lib
          .lookupFunction<_RecvFromC, _RecvFromDart>('cleona_ios_recvfrom');
    } catch (_) {}

    final fd = findFd(localPort);
    if (fd < 0) return null;

    // If the native cleona_ios_sendto6 symbol is missing (old binary before
    // this shim landed), force fd6 = -1 rather than substituting the IPv4
    // sendto() function for IPv6 sends. hasIpv6/send6()'s `_fd6 < 0` guard
    // then degrades IPv6 cleanly (falls through to IPv4/Dart-socket paths
    // at the call site in transport.dart) instead of silently calling
    // sendto() with an IPv6 destination string, which would fail every
    // time via inet_pton(AF_INET, ...) inside cleona_ios_sendto (Befund 12).
    final fd6 = (sendto6 != null && findFd6 != null)
        ? (findFd6.call(localPort))
        : -1;

    return IosUdpSender._(
        fd, fd6, sendto, sendto6 ?? sendto, recvPeek, recvFrom);
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

    return IosUdpSender._(fd, -1, sendto, sendto, null, null);
  }

  int get fd => _fd;
  int get fd6 => _fd6;
  bool get hasIpv6 => _fd6 >= 0;
  bool get hasRecvFrom => _recvFrom != null;

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
  int recvPeek6() => (_fd6 >= 0) ? (_recvPeek?.call(_fd6) ?? -999) : -999;

  /// Non-blocking native recvfrom() on IPv4 fd. Returns null on EAGAIN/error.
  IosRecvResult? recvFrom() => _recvFromFd(_fd);

  /// Non-blocking native recvfrom() on IPv6 fd. Returns null on EAGAIN/error.
  IosRecvResult? recvFrom6() => (_fd6 >= 0) ? _recvFromFd(_fd6) : null;

  IosRecvResult? _recvFromFd(int fd) {
    if (_recvFrom == null) return null;
    final buf = calloc<ffi.Uint8>(65536);
    final srcIp = calloc<ffi.Uint8>(46); // INET6_ADDRSTRLEN
    final srcPort = calloc<ffi.Int32>(1);
    try {
      final n = _recvFrom(fd, buf, 65536, srcIp, 46, srcPort);
      if (n <= 0) return null;
      final data = Uint8List(n);
      data.setAll(0, buf.asTypedList(n));
      final ip = srcIp.cast<Utf8>().toDartString();
      return IosRecvResult(data, ip, srcPort.value);
    } finally {
      calloc.free(buf);
      calloc.free(srcIp);
      calloc.free(srcPort);
    }
  }

  /// Whether this send() / send6() return value indicates the socket/route
  /// is dead (not just peer-specific), for Darwin (iOS/macOS) errno values.
  ///
  /// Return-value inventory for send()/send6() on this class (verified
  /// against cleona_udp_ios.c and the sentinels below — Befund 11/12):
  ///   - `> 0`                bytes sent (success, never reaches this gate).
  ///   - `-errno` (Darwin)    from cleona_ios_sendto/cleona_ios_sendto6's
  ///                          `sendto()` failing at the OS level. Real
  ///                          socket/route errors are classified as dead
  ///                          below; peer-specific errors (e.g. EHOSTUNREACH
  ///                          = 65, ECONNREFUSED = 61) are deliberately
  ///                          excluded — the peer being unreachable is not
  ///                          evidence the local socket is dead.
  ///   - `-22` (EINVAL)       returned by cleona_ios_sendto/6 when
  ///                          inet_pton() fails to parse the destination
  ///                          address. This is a genuine Darwin errno value
  ///                          (not a fake sentinel like Android's -2), but
  ///                          it is still a per-destination data problem,
  ///                          not a socket/route failure — deliberately
  ///                          excluded, same reasoning as Befund 7 for
  ///                          Android's isSocketDeadErrno.
  ///   - `-97`                Dart-level sentinel from send6() when
  ///                          `_fd6 < 0` ("no IPv6 fd available"). This
  ///                          reuses AndroidUdpSender's Linux/glibc
  ///                          EAFNOSUPPORT numbering (97) for consistency
  ///                          across platforms in logs — it is NOT the
  ///                          real Darwin EAFNOSUPPORT (47) and must not be
  ///                          matched against Darwin errno 47 or any other
  ///                          Darwin errno. It correctly falls through as
  ///                          "not dead" below since 97 is not in the set.
  ///   - `-999`               recvPeek()/recvFrom() "unavailable" sentinel;
  ///                          never returned by send()/send6(), not
  ///                          relevant to this gate.
  static bool isSocketDeadErrnoDarwin(int sendResult) {
    final e = -sendResult;
    return e == 9 || // EBADF (socket closed)
        e == 50 || // ENETDOWN
        e == 51 || // ENETUNREACH
        e == 57 || // ENOTCONN
        e == 47; // EAFNOSUPPORT (real Darwin value; NOT the -97 Dart sentinel above)
  }
}
