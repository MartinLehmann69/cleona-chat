import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/link_io/native_send_path.dart';

import 'package:mycelium/wire_target.dart';
import 'package:mycelium/own_address.dart' show usableIpv6Present;

/// What a caller needs from the wire — packet out, packet in. Nothing more.
///
/// This contract exists since `shell.dart` lies between [Wire] and `Splitter`
/// (§4.2: „an additional shell underneath it"): [Splitter] and
/// [OutsideRoute] serve either the naked wire (probes) or the
/// shell (operation), and neither of the two has to know which of the two
/// it currently has.
abstract interface class PacketRoute {
  /// Sends [packet] to [target]:[targetPort]. See [Wire.send] — the
  /// return value says whether it was accepted, not whether it arrived.
  bool send(Uint8List packet, InternetAddress target, int targetPort);

  /// Calls [onPacket] for every arriving packet.
  void listen(
      void Function(Uint8List packet, InternetAddress from, int fromPort) onPacket);
}

/// The wire.
///
/// Two UDP sockets on THE SAME port number, one per address type (§11.1:
/// „sockets | one IPv4, one IPv6, both bound to the same port number",
/// „Both sockets carry the same traffic"). Packet out, packet in. That is
/// everything this file will ever do. No queue, no clock,
/// no cap, no acknowledgement, no encryption — whoever needs that
/// builds it ONE level higher and leaves this file alone.
///
/// The only thing besides packets that belongs in here is the care for the
/// sockets themselves — because apart from this file nobody has them. Which targets
/// destroy them is written, with the measurement, in `wire_target.dart`.
///
/// ── WHY TWO SOCKETS AND NOT ONE ───────────────────────────────────
///
/// A single socket on `anyIPv6` carries both address types on Linux,
/// but presents IPv4 traffic as `::ffff:a.b.c.d` with 16 bytes. Thereby
/// the same neighbour would get two keys (`shell.dart`,
/// `readiness.dart`, `post_box_*.dart`), and `neighbourhood.dart`
/// would not even remember him. On Windows the same socket carries no
/// IPv4 at all. Two sockets avoid both — and are what the spec says.
///
/// **Each side lives for itself.** A throw at an IPv6 target to which this
/// host has no route ends the IPv6 socket (errno 101, asynchronous,
/// measured S390) — that does not touch the IPv4 socket (measured, case F),
/// and the same the other way round (case E). Both heal themselves individually on the same
/// port number; the port is the address of the node (§11.1), every
/// issued card names it.
class Wire implements PacketRoute {
  late final _Side _v4;
  _Side? _v6;
  final void Function(String)? _report;

  /// Who gets the packets — remembered because a new socket (see
  /// [_Side.againOpen]) needs it again.
  void Function(Uint8List packet, InternetAddress from, int fromPort)? _onPacket;
  bool _to = false;

  Wire._(this._report);

  /// Opens the wire. [port] 0 = the operating system chooses one.
  /// [report] gets send errors that the operating system only reports back
  /// later (see [listen]); without [report] they go to stderr.
  ///
  /// **First IPv4, then IPv6 on THE port number that resulted from it.**
  /// The order is not arbitrary: the IPv4 socket must stand (§11.1
  /// lets the node continue if need be „with IPv4 alone", never with IPv6
  /// alone), and its number is the number that goes into every card.
  /// Measured on 16.09.2026: both bind orders work, and in BOTH
  /// the IPv4 socket got the IPv4 traffic.
  ///
  /// **The IPv6 socket is only bound if this host has an
  /// IPv6 address under which someone can reach it** — asked is
  /// [usableIpv6Present] over [interfaces] (in operation the list
  /// that `interfacesRead` fetches at every edge anyway; if it is missing,
  /// this place fetches it itself). A bind „on suspicion" namely succeeds even
  /// without any IPv6, and the error then only occurs at the first throw —
  /// one layer and some seconds later, and it ends the socket.
  /// A node knows its network environment instead of exploring it by
  /// failing (owner decision 16.09.2026). If the bind fails
  /// nevertheless, that is not an error either (§11.1: „that is not an error and
  /// the node continues with IPv4 alone") — see [_ipv6Open].
  ///
  /// [toAddress] and [toAddress6] are the wildcards in operation and stay
  /// so. They are there because with them a probe can REALLY trigger
  /// what otherwise only happens on foreign hosts: a wire at the
  /// loopback and a target outside yield errno 22 (measured S389,
  /// case O), and a [toAddress6] that does not exist on this machine
  /// yields a real bind error (errno 99, measured S390, case H) — the
  /// only way to check the branch „no IPv6" without a dummy. The same
  /// reasoning as with [Neighbours] `beitritt`/`freigabe`: a tolerance
  /// of which nobody can show that it takes effect is none.
  static Future<Wire> open(
      {int port = 0,
      InternetAddress? toAddress,
      InternetAddress? toAddress6,
      List<NetworkInterface>? interfaces,
      void Function(String)? report}) async {
    final to4 = toAddress ?? InternetAddress.anyIPv4;
    final s4 = await RawDatagramSocket.bind(to4, port);
    final d = Wire._(report);
    d._v4 = _Side(d, to4, 'IPv4', s4);
    if (toAddress6 != null) {
      // An explicitly named address is an announcement, not a question:
      // the probe wants to see exactly this bind, succeeded or failed.
      await d._ipv6Open(toAddress6);
    } else {
      await d.ipv6FollowUp(interfaces ?? await NetworkInterface.list());
    }
    return d;
  }

  /// Brings the IPv6 socket to the state that the network environment yields —
  /// at opening and at every edge at which the interfaces
  /// can change (§11.1, §11.8). Returns whether afterwards an
  /// IPv6 socket stands.
  ///
  /// Both directions, and the second is the one that is easily forgotten:
  /// a phone that leaves the WLAN and has no IPv6 any more in cellular
  /// would otherwise keep a socket whose first throw ends it.
  Future<bool> ipv6FollowUp(List<NetworkInterface> interfaces) async {
    final should = usableIpv6Present(interfaces);
    if (should == hasIpv6) return hasIpv6;
    if (!should) {
      _v6?.shut();
      _v6 = null;
      _say('Wire: IPv6 socket closed — this host has no '
          'IPv6 address any more under which someone can reach it (§11.1).');
      return false;
    }
    return _ipv6Open(InternetAddress.anyIPv6);
  }

  /// The bind itself. A failure is NOT an error (§11.1: „that is not an
  /// error and the node continues with IPv4 alone") — it is reported,
  /// [hasIpv6] stays `false`, and an IPv6 target is rejected in [send]
  /// instead of thrown.
  Future<bool> _ipv6Open(InternetAddress to6) async {
    try {
      final sock = await RawDatagramSocket.bind(to6, port);
      _v6 = _Side(this, to6, 'IPv6', sock);
      return true;
    } on Object catch (e) {
      _say('wire: no IPv6 socket on port $port ($e) — this '
          'node carries on with IPv4 alone. That is not an error (§11.1).');
      return false;
    }
  }

  /// The port number of both sockets. It comes from the IPv4 socket, because that one
  /// always stands — the IPv6 one was bound to exactly this number.
  int get port => _v4.sock.port;

  /// Whether this wire has an IPv6 socket. `false` means: the bind
  /// failed or the socket could not be had again — not an error,
  /// but IPv6 targets are then not reachable.
  bool get hasIpv6 => _v6 != null;

  /// Sends [packet] to [target]:[targetPort].
  ///
  /// The return value says whether the kernel accepted the packet —
  /// NOT whether it arrived. Nobody knows that at this level,
  /// and nobody should pretend here that he knows it.
  ///
  /// A target that does not work on the data path is REPORTED and not
  /// sent (`false`). That is not caution but measured necessity:
  /// a single throw at the broadcast without permission, at port 0 or with too
  /// large a payload ends the socket forever, in both directions
  /// (S389, `wire_target.dart`).
  ///
  /// The address type decides which of the two sockets throws. A
  /// v4-mapped target (`::ffff:a.b.c.d`) goes via the IPv4 socket, not
  /// via the IPv6 one — see [asAddressKind].
  @override
  bool send(Uint8List packet, InternetAddress target, int targetPort) {
    final z = asAddressKind(target);
    final reason = impossibleTarget(z, targetPort, packet.length);
    if (reason != null) {
      _say('wire: not sent to ${target.address}:$targetPort — $reason');
      return false;
    }
    final side = z.type == InternetAddressType.IPv4 ? _v4 : _v6;
    // Until S390 here stood the block against EVERY IPv6 target, because it
    // destroyed the one IPv4 socket (errno 97, asynchronous). It is not
    // gone, it has shrunk: it only takes effect when the second
    // socket is missing. Without it the throw would take place anyway — via the
    // IPv4 socket, with the same deadly outcome.
    if (side == null) {
      _say('wire: not sent to ${target.address}:$targetPort — this '
          'wire has no IPv6 socket, and the operating system closes '
          'the IPv4 socket on a target of another address family (errno 97). '
          '§11.1: the node carries on with IPv4 alone.');
      return false;
    }
    // Windows: Dart's IOCP path returns 0 for a datagram sent while the
    // previous one is still pending (`eventhandler_win.cc` `Handle::SendTo`,
    // Dart 3.12.2) — the second part of every handshake flight 1 never left
    // the NIC (S397-1, pktmon). v4_2 §27: the data port sends through the
    // native shim on Windows.
    final n = side.native;
    if (n != null) return n.send(z.address, targetPort, packet) == packet.length;
    return side.sock.send(packet, z, targetPort) == packet.length;
  }

  /// Calls [onPacket] for every arriving packet — from both sockets,
  /// indistinguishably (§11.1: „Both sockets carry the same traffic").
  ///
  /// A failed send does NOT come from [send], but later
  /// as an error event on this stream (measured: ALL, none synchronous).
  /// Without `onError` it ended the whole process (S388, B-1).
  @override
  void listen(
    void Function(Uint8List packet, InternetAddress from, int fromPort) onPacket,
  ) {
    _onPacket = onPacket;
    _v4.subscribe();
    _v6?.subscribe();
  }

  /// A side that has not got its socket back drops away.
  /// Only the IPv6 side may do that: it is the one that §11.1 calls dispensable.
  void _lost(_Side s) {
    if (identical(s, _v6)) _v6 = null;
  }

  void _say(String what) => (_report ?? stderr.writeln)(what);

  void close() {
    _to = true;
    _v4.shut();
    _v6?.shut();
  }
}

/// One side of the wire: a socket, the address to which it is bound,
/// and the care for it. Present twice, once per address type.
///
/// It is a class of its own and not a pair of fields, because the
/// self-healing would otherwise stand there twice — and a second copy is
/// exactly the place where one half is repaired later and the
/// other is not.
class _Side {
  final Wire _d;
  final InternetAddress to;
  final String kind;
  RawDatagramSocket sock;

  /// The native send path of this side — only on Windows, `null` elsewhere
  /// ([NativeSendPath.usesNativeSendPath]); receiving stays on [sock].
  NativeSendPath? native;

  _Side(this._d, this.to, this.kind, this.sock) {
    _nativeOpen();
  }

  void _nativeOpen() => native = NativeSendPath.tryOpen(
      port: sock.port, ipv6: kind == 'IPv6', log: _d._say);

  void shut() {
    native?.close();
    native = null;
    sock.close();
  }

  void subscribe() {
    sock.listen((e) {
      if (e != RawSocketEvent.read) return;
      final g = sock.receive();
      if (g == null) return;
      // [asAddressKind]: what comes in as `::ffff:a.b.c.d` goes up as the
      // four bytes behind it. As measured, the IPv4 socket got the
      // IPv4 traffic, so the form never occurred — that is not promised,
      // and above it the neighbour list and four address keys depend on it.
      _d._onPacket
          ?.call(Uint8List.fromList(g.data), asAddressKind(g.address), g.port);
    }, onError: error);
  }

  /// The operating system error for an earlier throw.
  ///
  /// Measured (S389): afterwards this socket is dead — it sends nothing any more
  /// AND receives nothing any more, permanently, while `port` still names the old
  /// number. Since B-1 the process no longer dies of it; without the
  /// following, the node would instead be silently deaf, and that is worse than
  /// a crash, because nobody sees it.
  void error(Object e) {
    // `sock.port` still names the old number even on the dead socket
    // (measured S389) — exactly the one that is about to be bound anew.
    _d._say('wire: send error from the operating system ($e) — the $kind socket '
        'is dead with that, port ${sock.port} is opened again');
    againOpen();
  }

  /// Reopen the same port. Measured: after `close()` the same
  /// port number binds again immediately, and sending as well as receiving work again —
  /// repeatably, and also when the OTHER side holds the same number the
  /// whole time (measured S390, case E). ANOTHER port would be
  /// out of the question: the port is the address of the node (§11.1), every
  /// issued card names it.
  Future<void> againOpen() async {
    if (_d._to) return;
    final old = sock.port;
    shut();
    try {
      sock = await RawDatagramSocket.bind(to, old);
    } on Object catch (e) {
      _d._say('Wire: port $old cannot be had again for $kind ($e) — '
          '${kind == 'IPv6' ? 'this node continues with IPv4 alone '
              '(§11.1).' : 'this node no longer accepts anything.'}');
      _d._lost(this);
      return;
    }
    if (_d._to) return sock.close();
    _nativeOpen();
    subscribe();
    _d._say('wire: port $old open again ($kind).');
  }
}
