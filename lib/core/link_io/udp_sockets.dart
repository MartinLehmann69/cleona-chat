/// The node's UDP sockets — one set, held by the node host (D-1).
///
/// **Why this is its own class.** E-95 rules that a disguise shares **one**
/// socket with the bare path of necessity: a second port is foreclosed by
/// E-64, and a second `SO_REUSEADDR` socket on the same port is documented
/// broken. So the node has one socket per address family and everything
/// else — bind side, connect side, demux — works on that one set.
///
/// Three candidates were weighed for who holds it (D-1). Letting the
/// [LinkBinder] own it and grow a send path made the binder the host
/// without naming it so. Giving the connector its own ephemeral socket
/// broke E-95 and answerability at once: flight 2 would arrive on a
/// different source port than the one the peer was told about. What is
/// built here is the third: a holder of its own, injected into both
/// directions.
///
/// **This class interprets no byte.** It binds, it hands datagrams out, it
/// sends bytes back. Telling a handshake flight from a data cell is the
/// demux of E-95 and lives beside this file — at 1,200 B both wire units
/// are the same shape, so the split could not be made here anyway.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/link/connect.dart' show LinkEndpoint, LinkLogSink;
import 'package:cleona/core/link_io/native_send_path.dart';

/// The two address families the node attempts, independently.
///
/// V4 is dual-stack by norm, not by preference: §4.6 requires a dual-stack
/// node to hold partners in **both** families permanently, §4.7 makes
/// `ready` depend on "≥ 1 per family on dual-stack", and the family
/// diversity indicator of §4.6 rule 4 (E-55) measures the share of syncs
/// over the weaker family. None of that is expressible if the socket layer
/// collapses the families into one answer.
enum LinkAddressFamily {
  v4,
  v6;

  InternetAddress get wildcard => this == LinkAddressFamily.v4
      ? InternetAddress.anyIPv4
      : InternetAddress.anyIPv6;

  /// The family an address belongs to.
  static LinkAddressFamily of(InternetAddress address) =>
      address.type == InternetAddressType.IPv6
          ? LinkAddressFamily.v6
          : LinkAddressFamily.v4;
}

/// One datagram as it came off the wire, with the family it arrived on.
///
/// The family travels with the datagram because the answer has to leave
/// through the same one — and because §4.6 counts per family.
final class LinkDatagram {
  final Uint8List data;
  final InternetAddress source;
  final int sourcePort;
  final LinkAddressFamily family;

  const LinkDatagram({
    required this.data,
    required this.source,
    required this.sourcePort,
    required this.family,
  });

  /// The endpoint this datagram came from, in the form
  /// `lib/core/link/connect.dart` uses as its `ConnectState` key — and,
  /// since D-2, the key of the session table too.
  LinkEndpoint get origin => LinkEndpoint(source.address, sourcePort);
}

/// Raised when **no** address family could be bound.
///
/// This is the only outcome of opening that is an error. A node that binds
/// one family is a single-stack node and works — not every client has both
/// protocols (E-101). A node that binds neither is deaf, and for `bare`
/// that is what E-99 turns into `LinkBareBindFailure` one layer up.
final class LinkNoFamilyBound implements Exception {
  /// Why each family failed. A record per family, not a tally.
  final Map<LinkAddressFamily, Object> causes;

  const LinkNoFamilyBound(this.causes);

  @override
  String toString() =>
      'LinkNoFamilyBound(${causes.keys.map((f) => f.name).join(", ")})';
}

/// The node's listening sockets, one per address family, on one port.
final class UdpSocketSet {
  /// The node's data port, drawn once at first installation
  /// (`lib/core/link/data_port.dart`). Both families bind the same number.
  final int port;

  final LinkLogSink log;

  /// Called with the wire length of every datagram this set puts on the
  /// socket, and of every datagram it takes off it.
  ///
  /// **Bare `void Function(int)?`, and that is load-bearing.**
  /// `test/smoke/smoke_link_io_milestone.dart` (section 5) measures that no
  /// module under the V4 roots (`lib/core/link`, `lib/core/link_io`,
  /// `lib/core/sync`, `lib/core/tagline`, `lib/core/fountain`) imports one
  /// of the five V3 trees. The counter lives on the other side of these two
  /// function references; this file only reports lengths.
  ///
  /// **RE-MEASURED 2026-09-03 — the original justification no longer
  /// holds, the decision does.** Here it said: "A typed statistics
  /// object would be exactly such an edge", because `NetworkStatsCollector`
  /// lay in `lib/core/network/`. Since the CUT
  /// (`9d91f801`) it lies in `lib/core/stats/network_stats.dart:378`, and `stats`
  /// is NOT in `kV3Trees` — the guard even lists
  /// `import 'package:cleona/core/stats/network_stats.dart';`
  /// expressly in its `mustNotMatch` list. Section 5 would thus no longer catch such an
  /// edge. The bare callbacks stay
  /// nonetheless: wiring happens at the composition point
  /// (`service_daemon.dart`, `main.dart`), so that this file stays testable without the
  /// statistics layer.
  ///
  /// **Constructor parameters, not settable fields.** `LinkHost.start` calls
  /// `demux.start()` BEFORE it returns, so a hook installed on the returned
  /// object would miss every datagram that arrived in between — precisely
  /// the class of "number that is slightly off" this accounting exists to
  /// remove.
  ///
  /// The value is the datagram's own length: everything the peer's link
  /// layer will see, and everything below the IP/UDP headers the kernel
  /// adds. In V4.1 that is `kCellSize` = `kHandshakeFlightSize` = 1200 for
  /// every unit on the wire (§4.3), which is what makes the count
  /// falsifiable.
  final void Function(int bytes)? onWireBytesSent;
  final void Function(int bytes)? onWireBytesReceived;

  final _sockets = <LinkAddressFamily, RawDatagramSocket>{};

  /// The native send path per family — **under Windows and only there**.
  ///
  /// A missing entry means: this datagram goes through
  /// `RawDatagramSocket.send`. On Linux/macOS/Android/iOS the set is
  /// always empty by construction (see [_openNativeSendPaths]).
  final _nativeSend = <LinkAddressFamily, NativeSendPath>{};

  final _failures = <LinkAddressFamily, Object>{};
  final _inbound = StreamController<LinkDatagram>.broadcast();
  final _subscriptions = <StreamSubscription<RawSocketEvent>>[];

  UdpSocketSet({
    required this.port,
    required this.log,
    this.onWireBytesSent,
    this.onWireBytesReceived,
  });

  /// Every datagram that arrives on any bound family, undisturbed.
  Stream<LinkDatagram> get inbound => _inbound.stream;

  /// The families currently listening.
  Set<LinkAddressFamily> get families => Set.unmodifiable(_sockets.keys.toSet());

  /// Why the missing families are missing, one entry each.
  ///
  /// Kept because §4.6 rule 5 (E-71) requires two causes to stay apart: a
  /// family absent because this node has none, against a family absent
  /// because no partner offers one.
  Map<LinkAddressFamily, Object> get failures => Map.unmodifiable(_failures);

  bool get isOpen => _sockets.isNotEmpty;

  /// Attempts both families on [port], independently, with no early exit.
  ///
  /// **`reuseAddress` stays at Dart's default `true`, and that is
  /// load-bearing.** Measured on Linux for all three combinations
  /// (`lib/core/network/transport.dart:2302-2307` — **historic, the file
  /// was deleted with the CUT of 2026-08-31; `lib/core/network/` holds zero
  /// files, measured 2026-09-03**): with `bindv6only=0` the
  /// IPv6 wildcard socket also covers IPv4, so `anyIPv4:P` and `anyIPv6:P`
  /// coexist **only when both set `SO_REUSEADDR`**. Clearing it on either
  /// kills the IPv6 bind with `EADDRINUSE`. The same file recorded that
  /// `IPV6_V6ONLY=1` via `setRawOption` after the bind is rejected by Linux
  /// with `EINVAL`, which is why the separation is not attempted that way.
  ///
  /// Both families are attempted always: the receive-side counterpart of
  /// E-95 checks both MAC families unconditionally and forms its
  /// disjunction after all calls, and a loop that stopped at the first
  /// success would have to be rewritten when the second disguise exists.
  Future<void> open() async {
    if (_sockets.isNotEmpty) return;
    for (final family in LinkAddressFamily.values) {
      try {
        final socket = await RawDatagramSocket.bind(family.wildcard, port);
        socket.readEventsEnabled = true;
        _subscriptions.add(socket.listen(
          (e) => _onEvent(socket, family, e),
          // ── THE ERROR BRANCH, AND WHY IT MUST NOT BE LEFT
          //    OUT (measured 01.09.2026, S361) ────────────────────────
          //
          // `RawDatagramSocket.send` does NOT report a send error
          // synchronously. Measured with a destination in `2001:db8::/32` from a
          // machine without an IPv6 route:
          //
          //     `sendTo warf NICHT`
          //     Unhandled exception:
          //     SocketException: Send failed (OS Error: Network is
          //     unreachable, errno = 101), address = ::, port = 0
          //     #2  UdpSocketSet.send (udp_sockets.dart:198:25)
          //     <asynchronous suspension>
          //
          // The call returns normally, and the error appears
          // later on THIS stream. A `try/catch` around `send` therefore does not
          // catch it — the same class as the S351 finding
          // ("`unawaited()` behind a SYNCHRONOUS try/catch catches nothing
          // in Dart"). Without this branch it runs into the zone handler of
          // `service_daemon.dart`, and `SocketException` is not on
          // its survival list: **exit(99), the whole daemon** —
          // triggered by a packet to an address for which there is no
          // route.
          //
          // Why this only shows now: until S361 this node only sent
          // to addresses it had heard from before. The
          // punch window (§17.3) is the first sender that DELIBERATELY sends to
          // foreign candidates — "to all of the other side's
          // candidates" —, and a dual-stack peer names IPv6 that
          // an IPv4 network does not reach. That is the normal case, not the
          // special case.
          //
          // NO `cancelOnError`. An unreachable destination says nothing
          // about the socket; clearing it away because of that would mean making a
          // node deaf because of a foreign candidate.
          onError: (Object e) => log(
              'link socket ${family.name}: error on port $port — $e'),
          cancelOnError: false,
        ));
        _sockets[family] = socket;
      } catch (e) {
        _failures[family] = e;
        // One line per missing family. E-96 requires the line for a
        // disguise that falls away; a family that falls away is the same
        // kind of silence and the same kind of invisible without it.
        log('link bind: ${family.name} unavailable on port $port — $e');
      }
    }
    _openNativeSendPaths();
  }

  /// The families whose datagrams go through `cleona_net`.
  ///
  /// Empty on every platform except Windows, and empty under Windows too
  /// if the library could not be loaded. Public, so that
  /// the state can be queried instead of only logged.
  Set<LinkAddressFamily> get nativeSendFamilies =>
      Set.unmodifiable(_nativeSend.keys.toSet());

  /// ── THE PLATFORM SWITCH (v4_1 §27.3) ────────────────────────────────
  ///
  /// **Windows sends natively, all others through `RawDatagramSocket`.**
  ///
  /// The reason stands in `Cleona_Chat_Architecture_v4_1.md` §27.3,
  /// table row `cleona_net`, and is an external measurement: under
  /// Windows Dart's `RawDatagramSocket` lost **87.9 %** of the send calls
  /// under sustained load, without them ever reaching the kernel; a
  /// larger `SO_SNDBUF` changed nothing about it. The defect sits in the
  /// IOCP-based send implementation of the Dart VM. The counter-check
  /// of the same measurement: .NET's `UdpClient` showed zero
  /// losses at identical load, because it executes `WSASendTo` synchronously and without an IOCP queue
  /// — exactly what `native/cleona_net/src/cleona_net.c` does.
  ///
  /// **Why the switch does not bend every send path across the board.** §27.3
  /// speaks expressly of the **data port**, and this socket set IS
  /// the data port (`link/data_port.dart`). The remaining UDP send paths
  /// of this tree lie on other ports and are not touched here:
  /// `tagline/lan_entry_wiring.dart` (entry, `kLanEntryPort` = 41340
  /// plus an ephemeral call socket), `calls/lan_multicast.dart`
  /// (overlay multicast) and `calendar/sync/caldav_discovery.dart` (mDNS).
  ///
  /// **Why NOT under Linux**, although the V3 carrier did it: there
  /// the second `SO_REUSEADDR` socket on the same port would draw off incoming
  /// datagrams and starve the reception — the same figure that
  /// `link/data_port.dart` describes for `nodePort != discoveryPort`
  /// ("the kernel splits incoming traffic between the sockets …
  /// sending stays intact, the node looks healthy to everyone else,
  /// while its own reception is full of holes"). There would be no gain to
  /// set against it: the IOCP defect exists only under Windows.
  ///
  /// **The fallback is loud.** If loading or opening fails under
  /// Windows, it stays with `RawDatagramSocket` — i.e. with the path
  /// that according to the same measurement loses 87.9 %. That must not happen
  /// silently; [NativeSendPath.tryOpen] logs every one of these cases
  /// with cause in [log].
  void _openNativeSendPaths() {
    if (!NativeSendPath.usesNativeSendPath) return;
    for (final family in _sockets.keys) {
      final native = NativeSendPath.tryOpen(
        port: port,
        ipv6: family == LinkAddressFamily.v6,
        log: log,
      );
      if (native != null) _nativeSend[family] = native;
    }
  }

  /// Sends [data] to [target], through the socket of the target's family.
  ///
  /// Returns the number of bytes the OS accepted. The caller does not pick
  /// a socket: the family follows from the address, and answering through
  /// any other one would change the source port the peer sees.
  int send(Uint8List data, InternetAddress target, int targetPort) {
    final family = LinkAddressFamily.of(target);
    final socket = _sockets[family];
    if (socket == null) {
      throw StateError(
          'UdpSocketSet.send: no socket for ${family.name} — bound families '
          'are ${families.map((f) => f.name).join(", ")}');
    }
    // ── THE SWITCH, SECOND HALF (v4_1 §27.3) ───────────────────────
    //
    // Justification complete at [_openNativeSendPaths]. Here stands only
    // the branch: if a native send path exists for this family
    // (by construction only under Windows), the datagram goes through it;
    // otherwise through `RawDatagramSocket` as before.
    //
    // The source stays THE SAME in both cases: the native socket is
    // bound to the same port as the Dart socket. That is the
    // condition from E-95 (answerability) — the peer must be able to send the
    // response to the source port it sees.
    final native = _nativeSend[family];
    if (native != null) {
      final rc = native.send(target.address, targetPort, data);
      if (rc < 0) {
        // The native path reports the error SYNCHRONOUSLY as a negative
        // errno-like code — unlike `RawDatagramSocket.send`, whose
        // errors land asynchronously on the socket stream (see the
        // error branch in [open]). That is why it is logged here and
        // not thrown: an unreachable destination is no reason to abort the
        // caller — the same rule as there.
        log('cleona_net: send failed (errno ${-rc}) to '
            '${target.address}:$targetPort, ${data.length} B');
        return 0;
      }
      onWireBytesSent?.call(data.length);
      return rc;
    }

    final sent = socket.send(data, target, targetPort);
    // `data.length`, not `sent`: a UDP datagram is all-or-nothing on the
    // wire, and `RawDatagramSocket.send` returns 0 for "the kernel buffer
    // was full" rather than a short write. Booking the buffer length on a
    // positive return is the same rule the V3 path uses in
    // `_udpSendRaw`, so the two counters mean the same thing.
    if (sent > 0) onWireBytesSent?.call(data.length);
    return sent;
  }

  void _onEvent(
      RawDatagramSocket socket, LinkAddressFamily family, RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    // Before any interpretation — at 1200 B a handshake flight and a data
    // cell are the same shape (see the library comment), so there is
    // nothing to tell apart here and nothing that may be skipped.
    onWireBytesReceived?.call(datagram.data.length);
    _inbound.add(LinkDatagram(
      data: Uint8List.fromList(datagram.data),
      source: datagram.address,
      sourcePort: datagram.port,
      family: family,
    ));
  }

  /// Closes every socket and the inbound stream.
  Future<void> close() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    // Before the Dart sockets: the native socket holds the same port, and
    // a leftover handle would occupy it beyond the end of this
    // socket set. `close()` is safe to call multiple times.
    for (final native in _nativeSend.values) {
      native.close();
    }
    _nativeSend.clear();
    for (final socket in _sockets.values) {
      socket.close();
    }
    _sockets.clear();
    if (!_inbound.isClosed) {
      await _inbound.close();
    }
  }
}
