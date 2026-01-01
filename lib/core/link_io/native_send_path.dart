/// Dart binding to `native/cleona_net` — the syscall-near send path of the
/// **data port**, exclusively under Windows.
///
/// ── WHY THIS FILE EXISTS ────────────────────────────────────────
///
/// `Cleona_Chat_Architecture_v4_1.md` §27.3 records in the table row
/// `cleona_net` as an external measurement:
///
///   "under Windows Dart's `RawDatagramSocket` lost **87.9 %** of the
///    send calls under sustained load, without them ever reaching the
///    kernel; a larger `SO_SNDBUF` changed nothing about it — the
///    defect sits in the IOCP-based send implementation of the
///    Dart VM, not in Cleona's network layer. On the **data port**
///    the native sender is used **only under Windows** (under Linux
///    a second `SO_REUSEADDR` socket on the same port would draw off incoming
///    datagrams and starve the reception)."
///
/// Both stand like this in the leading document; this file builds it, it does not
/// re-measure it. The measurement itself (pktmon counters on Windows) lies in the
/// header comment of `native/cleona_net/include/cleona_net.h`.
///
/// ── TWO REASONS, NOT ONE — AND ONLY ONE DEPENDS ON THE LOAD ─────
///
/// Re-read 06.09.2026 in `Cleona_Chat_Architecture_v3_0.md` §4.5.2
/// (the original source §27.3 goes back to). Whoever only knows the
/// percentage later draws the wrong conclusion:
///
/// **(1) The loss is LOAD-BOUND.** §4.5.2 measures it at the
/// LAN discovery subnet scan "at roughly 500 packets per second": "only
/// about 11 percent of the issued sends actually left the host". §4.5.3
/// then expressly records that lowering to 50 pps "also
/// eliminates the Windows IOCP burst-drop issue that required the native
/// send shim (§4.5.2) at higher rates". The V4.1 data port sends at a
/// constant cell rate (§4.3, `sync/cover_stream.dart`) and lies far
/// below that. **For this reason alone the switch here would thus not be
/// compelling** — whoever only knows this one considers it superfluous.
///
/// **(2) The second reason depends on NO load at all, and §27.3 does not name it.**
/// §4.5.2, paragraph "IPv6 native sender and Dart socket.send()
/// safety net (V3.1.145)": Dart's IOCP `RawDatagramSocket.send()` can
/// under Windows **crash the Dart VM**
/// (`GetStackPointerForStackBounds failed`) when sending to an IPv6 destination without
/// a valid route — "the crash occurs below any Dart-level
/// try-catch". That is why V3 under Windows sent **all** IPv6 sends
/// of the data port through `cleona_udp_send6`.
///
/// Exactly this case is in V4.1 the NORMAL case, not the special case: the
/// punch window (§17.3) deliberately sends to foreign candidates of the
/// other side, and a dual-stack peer names IPv6 addresses that
/// an IPv4 network does not reach. That is the same observation that the
/// S361 error branch in `udp_sockets.dart` records for LINUX (there an
/// asynchronous `SocketException` on the socket stream, here a crash
/// below every `try`).
///
/// **Unverified, and that belongs to it:** whether (2) still occurs on today's Dart versions
/// cannot be measured from here — this tree has no
/// Windows access. The finding stands as documentary evidence, not as
/// an own measurement.
///
/// **Why there is nonetheless a fallback here where §4.5.2 wanted none.**
/// There it says: "a silent fallback would mask exactly the
/// conditions we built the shim to fix". The objection concerns the SILENT
/// fallback, and it is valid. The one built here is loud — every
/// fallback point in [tryOpen] logs with cause. This keeps
/// visible what §4.5.2 wanted to keep visible, without a missing
/// bundle piece preventing the whole node from starting.
///
/// ── WHAT THIS FILE DOES NOT DO ────────────────────────────────────────
///
/// **No reception.** The defect only affects the send path; `socket.listen`
/// of the Dart VM is unharmed. The library does export
/// `cleona_find_udp4_fd`/`…6` and `cleona_udp_sendto_fd*`, but those are
/// POSIX-only (they read `/proc/self/fd`) and ineffective on Windows —
/// they are deliberately NOT bound here.
///
/// **No multicast management.** The data port joins no group;
/// the LAN entry (`tagline/lan_entry.dart`, `kLanEntryPort` = 41340)
/// has its own socket and is not touched by this file.
///
/// **No broadcast.** `cleona_udp_open` gets `broadcast_enable = 0`.
/// The V4.1 data port sends exclusively unicast (§4.3: one cell per
/// slot to one partner); `SO_BROADCAST` would be a right that is never
/// needed. The V3 carrier set it because it served the
/// LAN discovery port 41338 — a different port, a different
/// purpose.
///
/// ── ORIGIN, AND WHAT OF IT WAS V3 ───────────────────────────────────
///
/// The previously existing carrier was called
/// `lib/core/network/native_udp_sender.dart` and disappeared with the V3 teardown
/// (`7f1b19b9`) together with the whole `lib/core/network/`. Four
/// properties from back then are DELIBERATELY not taken over here — they
/// were V3, not the core of the matter:
///
///   1. **Linux belonged to the platform set.** V3 used the native
///      sender under Linux too. §27.3 rules that out for the data port
///      (reception starvation through the second
///      `SO_REUSEADDR` socket). This file loads nothing under Linux.
///   2. **`$HOME/cleona-app/lib/…` as search path.** A Linux location; falls
///      away with Linux.
///   3. **`File(Platform.resolvedExecutable).parent.path` as
///      bundle root.** Since S367 the daemon lies in `<bundleDir>/bin/`,
///      its own directory is NO longer the root. All nine
///      other load points are switched to [AppPaths.bundleDir]
///      (`abd9811e`, `61911a3f`); this one follows the same pattern.
///   4. **"Hard dependency, no fallback" — the daemon died.** The
///      V3 carrier threw on a load error, and the start error path of the
///      daemon kicked in. Here it is the other way round: [tryOpen] returns `null`,
///      the caller keeps using `RawDatagramSocket` — and the
///      fallback is logged LOUDLY. Justification: a silent
///      fallback to a path that loses 87.9 % looks like
///      "running" and is thus worse than a loud error.
///
/// The header comment of `native/cleona_net/include/cleona_net.h` and
/// `native/cleona_net/README.md` still refer to
/// `Cleona_Chat_Architecture_v3_0.md §4.5.2/§20.3a`. That is an
/// outdated reference to a document of the OTHER line — for the
/// V4.1 line §27.3 leads. The reference is noted here, not
/// changed: architecture documents are not touched without owner approval
/// (working rule #4).
///
/// ── LOADING PATTERN ──────────────────────────────────────────────────────
///
/// Candidate list as in `link/elligator_ffi.dart` and
/// `crypto/proof_of_work.dart`: first the bare name (the Windows loader
/// searches next to the running `.exe`), then the computed location in the
/// bundle. The second candidate is the one that carries for the DAEMON — it
/// lies in `<bundleDir>\bin\`, the DLL on the other hand in `<bundleDir>\`, where
/// `windows/runner/CMakeLists.txt` copies it POST_BUILD next to `cleona.exe`.
library;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:cleona/core/platform/app_paths.dart';

// ── C-Signaturen (native/cleona_net/include/cleona_net.h) ─────────────

// cleona_udp_socket_t* cleona_udp_open(uint16_t, int reuse_addr, int broadcast)
typedef _OpenC = ffi.Pointer<ffi.Void> Function(
    ffi.Uint16 localPort, ffi.Int32 reuseAddr, ffi.Int32 broadcastEnable);
typedef _OpenDart = ffi.Pointer<ffi.Void> Function(
    int localPort, int reuseAddr, int broadcastEnable);

// cleona_udp_socket_t* cleona_udp_open6(uint16_t, int reuse_addr)
typedef _Open6C = ffi.Pointer<ffi.Void> Function(
    ffi.Uint16 localPort, ffi.Int32 reuseAddr);
typedef _Open6Dart = ffi.Pointer<ffi.Void> Function(
    int localPort, int reuseAddr);

// int cleona_udp_set_buffers(cleona_udp_socket_t*, int rcv, int snd)
typedef _SetBuffersC = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Int32 rcvBytes, ffi.Int32 sndBytes);
typedef _SetBuffersDart = int Function(
    ffi.Pointer<ffi.Void>, int rcvBytes, int sndBytes);

// int cleona_udp_send (cleona_udp_socket_t*, const char*, uint16_t,
//                      const uint8_t*, int)
// int cleona_udp_send6(… same shape, IPv6 address string)
typedef _SendC = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Utf8> destIp,
    ffi.Uint16 destPort,
    ffi.Pointer<ffi.Uint8> data,
    ffi.Int32 len);
typedef _SendDart = int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Utf8> destIp,
    int destPort,
    ffi.Pointer<ffi.Uint8> data,
    int len);

// void cleona_udp_close(cleona_udp_socket_t*)
typedef _CloseC = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _CloseDart = void Function(ffi.Pointer<ffi.Void>);

// const char* cleona_net_version(void)
typedef _VersionC = ffi.Pointer<Utf8> Function();
typedef _VersionDart = ffi.Pointer<Utf8> Function();

/// Send buffer that [NativeSendPath] sets on the native socket.
///
/// 4 MiB, taken over from the V3 carrier. `SO_RCVBUF` stays UNSET (0 =
/// "skip option", C contract): nothing is ever received on this socket,
/// a receive buffer would be allocated memory without use.
///
/// The value is expressly NOT a remedy against the §27.3 finding —
/// it says there that a larger `SO_SNDBUF` changed nothing about the Dart loss.
/// It is the ordinary precaution against short backlogs on
/// the native path.
const int kNativeSendBufferBytes = 4 * 1024 * 1024;

/// A native UDP send path on **one** local port and **one**
/// address family.
///
/// Not concurrency-protected: the underlying socket carries
/// no Dart-side lock. The data port is served from exactly one isolate
/// (`UdpSocketSet` in `udp_sockets.dart`), which fulfils that.
final class NativeSendPath {
  /// Whether this platform uses the native send path on the data port.
  ///
  /// **Windows only** — §27.3. Under Linux the second
  /// `SO_REUSEADDR` socket on the same port would draw off incoming datagrams and
  /// starve the reception; under Android, iOS and macOS the
  /// IOCP defect this library works around does not exist. Whoever
  /// softens this line loses cells in RECEPTION on Linux without gaining
  /// anything for it.
  static bool get usesNativeSendPath => Platform.isWindows;

  static ffi.DynamicLibrary? _lib;

  final ffi.Pointer<ffi.Void> _handle;
  final _SendDart _sendFn;
  final _CloseDart _closeFn;
  final bool ipv6;
  final int localPort;
  bool _closed = false;

  NativeSendPath._(this._handle, this._sendFn, this._closeFn,
      {required this.ipv6, required this.localPort});

  /// Opens the native send path — or returns `null` and says LOUDLY
  /// why.
  ///
  /// `null` means for the caller: keep using `RawDatagramSocket`.
  /// Under Windows that is the path that according to §27.3 loses 87.9 % —
  /// that is why every fallback is logged. On every other
  /// platform `null` is the normal case and logs nothing.
  static NativeSendPath? tryOpen({
    required int port,
    required bool ipv6,
    required void Function(String message) log,
  }) {
    if (!usesNativeSendPath) return null;

    final ffi.DynamicLibrary lib;
    try {
      lib = _lib ??= _openLibrary();
    } catch (e) {
      log('cleona_net: NOT LOADED — the data port keeps sending on port $port '
          'through the RawDatagramSocket of Dart. Under Windows that loses, '
          'according to Cleona_Chat_Architecture_v4_1.md 27.3, 87,9 % of the '
          'send calls. Most likely cause: cleona_net.dll is missing from the '
          'bundle (expected next to cleona.exe, see EXPECTED_DLLS in '
          'windows/runner/CMakeLists.txt). Cause: $e');
      return null;
    }

    try {
      final ffi.Pointer<ffi.Void> handle;
      if (ipv6) {
        final open6 =
            lib.lookupFunction<_Open6C, _Open6Dart>('cleona_udp_open6');
        // reuse_addr = 1: the Dart receive socket holds the same port.
        handle = open6(port, 1);
      } else {
        final open = lib.lookupFunction<_OpenC, _OpenDart>('cleona_udp_open');
        // broadcast_enable = 0 — see library header: the data port
        // sends exclusively unicast.
        handle = open(port, 1, 0);
      }
      if (handle == ffi.nullptr) {
        log('cleona_net: cleona_udp_open${ipv6 ? "6" : ""} returned NULL for '
            'port $port — the data port falls back to RawDatagramSocket '
            '(27.3: 87,9 % loss under Windows). Possible causes: port '
            'taken without SO_REUSEADDR by another process, WSAStartup '
            'failed, no handles left.');
        return null;
      }

      final setBuffers = lib.lookupFunction<_SetBuffersC, _SetBuffersDart>(
          'cleona_udp_set_buffers');
      // Return value deliberately NOT treated as an error: the C contract says
      // expressly "does not invalidate the socket". A socket with
      // OS default buffers is better than none at all.
      if (setBuffers(handle, 0, kNativeSendBufferBytes) != 0) {
        log('cleona_net: SO_SNDBUF to $kNativeSendBufferBytes B '
            'failed (port $port, ${ipv6 ? "v6" : "v4"}) — the socket '
            'stays in operation with OS default buffers.');
      }

      final sendFn = lib.lookupFunction<_SendC, _SendDart>(
          ipv6 ? 'cleona_udp_send6' : 'cleona_udp_send');
      final closeFn =
          lib.lookupFunction<_CloseC, _CloseDart>('cleona_udp_close');

      log('cleona_net: native send path active on port $port '
          '(${ipv6 ? "IPv6" : "IPv4"}), ${_version(lib)} — 27.3.');
      return NativeSendPath._(handle, sendFn, closeFn,
          ipv6: ipv6, localPort: port);
    } catch (e) {
      log('cleona_net: symbol not resolvable or open failed '
          '(port $port, ${ipv6 ? "v6" : "v4"}) — the data port falls back to '
          'RawDatagramSocket (27.3: 87,9 % loss under Windows). '
          'Cause: $e');
      return null;
    }
  }

  /// Sends a datagram. Return: bytes sent (== `data.length`)
  /// or a NEGATIVE errno-like code.
  ///
  /// Does not throw: the C call carries ordinary network errors as
  /// return value across the FFI boundary, not as an exception. That is the
  /// difference from the Dart path, whose send errors appear ASYNCHRONOUSLY on the
  /// socket stream (see the error branch in `udp_sockets.dart`,
  /// S361) — here the error is visible at the call site.
  int send(String destIp, int destPort, Uint8List data) {
    if (_closed) return -1;
    final ipPtr = destIp.toNativeUtf8();
    final dataPtr = malloc.allocate<ffi.Uint8>(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      return _sendFn(_handle, ipPtr, destPort, dataPtr, data.length);
    } finally {
      malloc.free(dataPtr);
      malloc.free(ipPtr);
    }
  }

  /// Closes the native socket. Calling it multiple times is harmless.
  void close() {
    if (_closed) return;
    _closed = true;
    _closeFn(_handle);
  }

  /// Version string of the loaded library, for diagnostics.
  static String _version(ffi.DynamicLibrary lib) {
    try {
      return lib
          .lookupFunction<_VersionC, _VersionDart>('cleona_net_version')()
          .toDartString();
    } catch (_) {
      return 'cleona_net (version unknown)';
    }
  }

  /// Candidate list — Windows only, because only there is it loaded.
  static ffi.DynamicLibrary _openLibrary() {
    final candidates = <String>['cleona_net.dll'];
    try {
      candidates.add('${AppPaths.bundleDir}\\cleona_net.dll');
    } catch (_) {
      // `Platform.resolvedExecutable` can throw in unusual
      // embeddings; then the bare name remains.
    }
    Object? lastError;
    for (final c in candidates) {
      try {
        return ffi.DynamicLibrary.open(c);
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('cleona_net.dll not loadable. Tried: '
        '${candidates.join(", ")} — last: $lastError');
  }
}
