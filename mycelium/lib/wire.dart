import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/wire_counters.dart';
import 'package:mycelium/wire_family.dart' show dartSendForbidden, noNativeIpv6Line;
import 'package:mycelium/wire_side.dart';
export 'package:mycelium/wire_counters.dart' show WireCounters;
export 'package:mycelium/wire_side.dart' show kReceiveBatch;
import 'package:mycelium/wire_target.dart';
import 'package:mycelium/wire_port.dart' show bindAlone;
import 'package:mycelium/own_address.dart' show rankTheAddress, usableIpv4Present, usableIpv6Present;
import 'package:mycelium/packet_route.dart';
import 'package:mycelium/trace.dart' show kErrorLinePrefix;
export 'package:mycelium/packet_route.dart' show PacketRoute;

/// The wire.
///
/// Two UDP sockets on THE SAME port number, one per address type (§11.1:
/// „sockets | one IPv4, one IPv6, both bound to the same port number",
/// „Both sockets carry the same traffic"). Packet out, packet in. That is
/// everything this file will ever do. No clock, no cap, no acknowledgement,
/// no encryption — whoever needs that builds it ONE level higher and leaves
/// this file alone. The one queue in here is the receive queue of §11.1
/// „Reading." (see [WireSide.subscribe]): it holds what was read and not yet
/// processed, and it evicts nothing (§20.2, D-44).
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
/// ── BOTH KINDS ARE EQUAL (S427) ───────────────────────────────────
///
/// Owner 18.11.2026: IPv4 and IPv6 are interchangeable. A node without an IP
/// address of either kind reports an error; with only an IPv4 address only
/// IPv4 is wired, with only IPv6 only IPv6, with both both — an address that
/// is present is used, where none is, socket and protocol stay off. A side is bound only while this host has an
/// address of its kind ([usableIpv4Present], [usableIpv6Present]); a carrier-
/// grade IPv4 counts. The port number belongs to the wire, not to a side: the
/// side bound first fixes it (or the requested [open] port), and every side
/// bound later takes the same number. Without any address no socket stands,
/// an ERROR line says so, and the next network change ([followUp]) binds again.
///
/// **Each side lives for itself** (measured S390, cases E and F): an error ends
/// only its own socket, which binds again on the same port (§11.1) — except
/// "no route" on the IPv6 side before a global IPv6 send was accepted on this
/// network: that closes it until the next network change ([WireSide.error], S422).
class Wire implements PacketRoute, WireSideOwner {
  WireSide? _v4; // version-name-ok: IP address family
  WireSide? _v6;
  final void Function(String)? _report;

  /// A named address ([open] `toAddress`/`toAddress6`) is an announcement:
  /// a network change never closes that side, and binds it again on exactly
  /// that address after it was lost.
  InternetAddress? _named4, _named6;

  /// The port number of both sockets — of the wire, also while no side stands.
  int _port;

  /// Who gets the packets — remembered because a new socket (see
  /// [WireSide.againOpen]) needs it again.
  void Function(Uint8List packet, InternetAddress from, int fromPort)? _onPacket;
  bool _to = false;

  /// What went out and came in on both sockets (§25.5, `wire_counters.dart`).
  @override
  final WireCounters counters = WireCounters();

  Wire._(this._report, this._port);

  /// Opens the wire. [port] 0 = the operating system chooses one.
  /// [report] gets send errors that the operating system only reports back
  /// later (see [listen]); without [report] they go to stderr.
  ///
  /// **A side only for an address kind this host has** ([interfaces], in
  /// operation the list of `interfacesRead`; without it the interfaces are
  /// read here): a bind „on suspicion" succeeds without the kind and fails at
  /// the first throw (owner decision 16.09.2026, 18.11.2026). The side bound
  /// first takes [port] through [bindAlone] and throws when it is held —
  /// `Host.start` then draws anew; a later side binds the same number.
  ///
  /// [toAddress]/[toAddress6] are announcements, bound whatever the
  /// interfaces say: a probe uses them to trigger errno 22 (loopback wire,
  /// outside target, S389 case O) and a real bind error (errno 99, S390 case
  /// H) without a dummy; the smokes use them for 127.0.0.1.
  static Future<Wire> open(
      {int port = 0,
      InternetAddress? toAddress,
      InternetAddress? toAddress6,
      List<NetworkInterface>? interfaces,
      void Function(String)? report}) async {
    final d = Wire._(report, port);
    final list = toAddress != null && toAddress6 != null
        ? const <NetworkInterface>[]
        : interfaces ?? await NetworkInterface.list();
    if (toAddress != null) {
      d._named4 = toAddress;
      await d._open4(toAddress, opening: true);
    } else if (usableIpv4Present(list)) {
      await d._open4(InternetAddress.anyIPv4, opening: true);
    }
    if (toAddress6 != null) {
      // An explicitly named address is an announcement, not a question:
      // the probe wants to see exactly this bind, succeeded or failed.
      d._named6 = toAddress6;
      await d._ipv6Open(toAddress6);
    } else if (usableIpv6Present(list)) {
      await d._ipv6Open(InternetAddress.anyIPv6, opening: true);
    }
    d._noneSaid();
    return d;
  }

  /// Brings both sides to the state that the network environment yields — at
  /// opening and at every edge at which the interfaces can change (§11.1,
  /// §11.8). Both directions: a phone leaving the WLAN without IPv6 in
  /// cellular would keep a socket whose first throw ends it; a host that
  /// gains an address of a kind gets its side. Returns whether afterwards a
  /// side stands.
  Future<bool> followUp(List<NetworkInterface> interfaces) async {
    final n4 = _named4, n6 = _named6;
    if (n4 != null && _v4 == null) await _open4(n4);
    if (n6 != null && _v6 == null) await _ipv6Open(n6);
    if (n4 == null) {
      final should = usableIpv4Present(interfaces);
      if (should && _v4 == null) {
        await _open4(InternetAddress.anyIPv4);
      } else if (!should && _v4 != null) {
        _v4!.shut();
        _v4 = null;
        _say('Wire: IPv4 socket closed — this host has no IPv4 address any '
            'more (§11.1).');
      }
    }
    if (n6 == null) {
      await _ipv6Follow(interfaces);
    } else {
      _v6?.routeSeen = false; // a new network proves its way out anew (S422)
    }
    _noneSaid();
    return hasIpv4 || hasIpv6;
  }

  Future<bool> _ipv6Follow(List<NetworkInterface> interfaces) async {
    final should = usableIpv6Present(interfaces);
    _v6?.routeSeen = false; // a new network proves its way out anew (S422)
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

  /// Binds the IPv4 side on the wire's number. At [opening], as the side
  /// bound first, it goes through [bindAlone] and throws when the number is
  /// held (as the data port always did) — `Host.start` then draws anew. At a
  /// network change a failure is no error: reported, and the node continues
  /// without IPv4 until the next change (§11.1).
  Future<bool> _open4(InternetAddress to4, {bool opening = false}) async {
    try {
      final sock = opening
          ? await bindAlone(to4, _port) // S413: no shared data port
          : await RawDatagramSocket.bind(to4, _port);
      _port = sock.port;
      _v4 = WireSide(this, to4, 'IPv4', sock);
      if (_onPacket != null) _v4!.subscribe();
      return true;
    } on Object catch (e) {
      if (opening) rethrow;
      _say('wire: no IPv4 socket on port $_port ($e) — this node carries on '
          'without IPv4. That is not an error (§11.1).');
      return false;
    }
  }

  /// The IPv6 bind on the wire's number. At [opening] with no IPv4 side it is
  /// the side bound first: through [bindAlone], throwing when the number is
  /// held, as [_open4]. Otherwise a failure is NOT an error (§11.1) — it is
  /// reported, [hasIpv6] stays `false`, and an IPv6 target is refused in
  /// [send]; a named [to6] (a probe) always takes this path.
  Future<bool> _ipv6Open(InternetAddress to6, {bool opening = false}) async {
    final strict = opening && !hasIpv4;
    try {
      final sock = strict
          ? await bindAlone(to6, _port)
          : await RawDatagramSocket.bind(to6, _port);
      _port = sock.port;
      _v6 = WireSide(this, to6, 'IPv6', sock);
      if (dartSendForbidden('IPv6') && _v6!.native == null) { _v6!.shut(); _v6 = null; _say(noNativeIpv6Line(_port)); return false; }
      if (_onPacket != null) _v6!.subscribe(); // opened after listen (S407)
      return true;
    } on Object catch (e) {
      if (strict) rethrow;
      _say('wire: no IPv6 socket on port $_port ($e) — this '
          'node carries on without IPv6. That is not an error (§11.1).');
      return false;
    }
  }

  /// No side stands: this host has no IP address of any kind (§11.1) — an
  /// error, said at the edge that found it; the next network change binds.
  void _noneSaid() {
    if (hasIpv4 || hasIpv6 || _to) return;
    _say('${kErrorLinePrefix}wire: this host has no IP address of any kind — '
        'no IPv4, no IPv6 under which someone can reach it; no socket is bound '
        'and the node is unreachable until the next network change (§11.1).');
  }

  /// The port number of both sockets — the wire's, also while no side stands.
  int get port => _port;

  /// Whether this wire has an IPv4 socket — `false`: this host has no IPv4
  /// address, or the side could not be had again; IPv4 targets are then refused.
  bool get hasIpv4 => _v4 != null;

  /// Whether this wire has an IPv6 socket — `false` as for [hasIpv4].
  bool get hasIpv6 => _v6 != null;

  /// Sends [packet] to [target]:[targetPort].
  ///
  /// The return value says whether the kernel accepted the packet —
  /// NOT whether it arrived; nobody knows that at this level.
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
    final toIpv4 = z.type == InternetAddressType.IPv4;
    final side = toIpv4 ? _v4 : _v6;
    // No socket of the target's kind: a throw via the other socket would end
    // it (errno 97, asynchronous, S390) — so the target is refused.
    if (side == null) {
      _say('wire: not sent to ${target.address}:$targetPort — this wire has '
          'no ${toIpv4 ? 'IPv4' : 'IPv6'} socket (this host has no such address, '
          '§11.1), and a socket of the other kind would be closed by it (errno 97).');
      return false;
    }
    // Windows: Dart's IOCP path returns 0 for a datagram sent while the
    // previous one is still pending (`eventhandler_win.cc` `Handle::SendTo`,
    // Dart 3.12.2) — the second part of every handshake flight 1 never left
    // the NIC (S397-1, pktmon). v4_2 §27: the data port sends through the
    // native shim on Windows.
    final n = side.native;
    final ok = side.failures.watch(() => n != null ? n.send(z.address, targetPort, packet)
        : dartSendForbidden(side.kind) ? 0 : side.sock.send(packet, z, targetPort), packet.length) == packet.length;
    if (ok) counters.sent(packet.length);
    if (ok && rankTheAddress(z) == 3) side.routeSeen = true; // global IPv6 (S422)
    return ok;
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
    _v4?.subscribe();
    _v6?.subscribe();
  }

  // ── what a side needs of its wire ([WireSideOwner]) ──
  @override
  void sideSay(String what) => _say(what);
  @override
  bool get closedForGood => _to;
  @override
  bool holds(WireSide s) => identical(s, _v4) || identical(s, _v6);
  @override
  void Function(Uint8List packet, InternetAddress from, int fromPort)? get packetTaker => _onPacket;

  /// A side that has not got its socket back, or gave it up, drops away
  /// until the next network change — either kind (S427, §11.1).
  @override
  void sideLost(WireSide s) {
    if (identical(s, _v4)) _v4 = null;
    if (identical(s, _v6)) _v6 = null;
    _noneSaid();
  }

  void _say(String what) => (_report ?? stderr.writeln)(what);

  /// Binds both sockets afresh on THE SAME port (§11.1; §31.3 "bind fresh
  /// sockets": iOS closes them while the app sleeps, and a closed one says
  /// nothing). Per kind whether a fresh socket stands; no side of a kind: `null`.
  Future<({bool? ipv4, bool? ipv6})> reopen() async {
    final four = _v4, six = _v6;
    return (ipv4: await four?.againOpen(), ipv6: await six?.againOpen());
  }

  void osClosedForProbe() { // S422 smoke
    final s = _v4;
    if (s != null) s.closedUnder(s.sock, 'probe');
  }

  void close() {
    _to = true;
    _v4?.shut();
    _v6?.shut();
  }
}
