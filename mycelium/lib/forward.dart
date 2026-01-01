/// Forwarding via codes — step 3 (V4.2 §8.1; proposal M, S391).
///
/// A packet names neither person nor device. It carries a **code**
/// (`pair.dart`), and the recipient's neighbour knows only the codes that
/// the recipient device has registered with it (`code_table.dart`). The
/// sender sends via its OWN fixed neighbour (`0x22`) to the
/// recipient's neighbour (`0x20`); no place on the path sees both
/// ends. This file knows no network: it gets functions for sending
/// and looking up and is fed with incoming packets.
///
/// ## Packet layout
/// | Kind | Layout |
/// |---|---|
/// | `0x20` pass on | kind 1 · hop count 1 (start 3) · code 16 · content |
/// | `0x21` unknown to me | kind 1 · code 16 |
/// | `0x22` pass to these addresses | kind 1 · hop count 1 (start 3) · count 1 (1–3) · addresses · inner `0x20` (`forward_detour.dart`) |
/// | `0x23` where are you | kind 1 · hop count 1 (start 2) · code 16 · content (ONE part) |
///
/// Until S390 the identifier of the target AND of the sender stood here in plain text,
/// and the forwarder learned a way back from it. Both went away without
/// replacement (4.2: no legacy format, no way back).
///
/// ## What a forwarder does (§8.1)
/// 1. `0x22`: the inner packet to each next address — all of them only for a
///    device registered here ([Forwarder.registered]), else the first; per
///    address without a socket for its family to another address of the same
///    neighbour, else as `0x22`, hop count − 1, to one open neighbour that has
///    that family ([Forwarder.nextStep], `forward_family.dart`). It remembers
///    for [Forwarder.loopGuardDuration] from whom the `0x22` with this code
///    came — ONLY to return a `0x21` there (the recipient's neighbour only
///    sees its predecessor). It learns nothing it did not see anyway.
/// 2. `0x20`: own code → deliver. Registered code → to the device.
/// 3. Otherwise `0x21` with the code to the predecessor.
/// 4. `0x23`: own code → to [Forwarder.onSuchTarget], NOT to
///    [Forwarder.onTarget] (the content is no message, §8.1);
///    registered → to the device; otherwise
///    to every neighbour once, hop count − 1, discarded at 0. At most
///    one `0x23` per [Forwarder.suchThrottle] per incoming neighbour.
///
/// Loop guard: 8 B SHA-256 of the content, 60 s.
///
/// ## What a forwarder can NOT do
/// Read the content (envelope, §4) — and since S391 also not say for
/// whom it is: it sees code, hop count and addresses of the neighbours.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/card_address.dart';
import 'package:mycelium/forward_detour.dart';
import 'package:mycelium/pair.dart' show kCodeLength;
import 'package:mycelium/kinds.dart' as kinds;

/// Where a packet goes — fits directly onto `Splitter.send`.
typedef Send = void Function(Uint8List packet, InternetAddress target, int targetPort);

/// Network address of a neighbour or device.
typedef NeighbourTarget = ({InternetAddress address, int port});

/// Where the inner packet of a `0x22` goes: to [target] as it is, or —
/// [detour] — wrapped again as a `0x22` with hop count − 1 (§8.1, V5).
typedef NextStep = ({NeighbourTarget target, bool detour});

/// Start value of the hop count for `0x20` and `0x22`.
const int kStartHopCount = 3;

/// Start value of the hop count for `0x23` — reaches every node in two
/// hops (§8.1, around 1,000 packets at 32 neighbours).
const int kStartHopCountSearch = 2;

const int _kPacketIdentifierLength = 8;
const int _kHeaderCode = 1 + 1 + kCodeLength; // 18
const int _kHeaderUnknownCode = 1 + kCodeLength; // 17

class ForwardError implements Exception {
  final String reason;
  ForwardError(this.reason);
  @override
  String toString() => 'WeiterreichenFehler: $reason';
}

/// Receives, checks, passes on or delivers — sender, forwarder and target.
class Forwarder {
  /// Does the code belong to a mailbox of THIS device?
  final bool Function(Uint8List code) isOwnCode;
  /// Which device has registered the code here (`code_table.dart`)?
  final NeighbourTarget? Function(Uint8List code) codeSearch;

  /// All neighbours — for `0x23`.
  final List<NeighbourTarget> Function() neighbours;

  /// Is this address the node itself? Then a `0x22` is unpacked here.
  final bool Function(InternetAddress address, int port) isSelf;

  /// The step for a `0x22` to `next` from `from`:`fromPort`; `null` = none
  /// (no socket, no neighbour of that address family). Default: as it is.
  final NextStep? Function(CardAddress next, InternetAddress from, int fromPort)
      nextStep;

  /// Has the device at this address registered codes here? Only then does
  /// a `0x22` go to more than its first address (`forward_detour.dart`).
  final bool Function(InternetAddress from, int fromPort) registered;

  final Send send;

  /// A code of this device: the content, still sealed.
  final void Function(Uint8List content, InternetAddress from, int fromPort)?
      onTarget;

  /// The same for a `0x23` — with the code, without the origin address. A
  /// SEPARATE DOOR: its content is no message (§8.1 "one part, **no message
  /// inside**"), only the sender's fixed neighbour sealed under `K_AB`.
  final void Function(Uint8List code, Uint8List content)? onSuchTarget;

  /// A `0x21` for a code this node did not pass on — it was the sender.
  final void Function(Uint8List code)? onUnknown;

  final void Function(String)? report;
  final Duration loopGuardDuration;
  final Duration suchThrottle;

  /// Changeable ONLY for tests.
  DateTime Function() now;

  final Map<String, DateTime> _seen = {};
  final Map<String, ({NeighbourTarget from, DateTime at})> _detourFrom = {};
  final Map<String, DateTime> _searchFrom = {};

  /// Counters for probes and the network statistics (§25) — read only.
  int passed = 0;
  int detours = 0;
  int unknown = 0;
  int searchFurther = 0;
  int searchThrottled = 0;

  Forwarder({
    required this.isOwnCode,
    required this.codeSearch,
    required this.send,
    List<NeighbourTarget> Function()? neighbours,
    bool Function(InternetAddress address, int port)? isSelf,
    NextStep? Function(CardAddress next, InternetAddress from, int fromPort)?
        nextStep,
    bool Function(InternetAddress from, int fromPort)? registered,
    this.onTarget,
    this.onSuchTarget,
    this.onUnknown,
    this.report,
    this.loopGuardDuration = const Duration(seconds: 60),
    this.suchThrottle = const Duration(minutes: 1),
    this.now = DateTime.now,
  })  : neighbours = neighbours ?? (() => const []),
        isSelf = isSelf ?? ((_, __) => false),
        registered = registered ?? ((_, __) => false),
        nextStep = nextStep ?? _asItIs;

  static NextStep _asItIs(CardAddress n, InternetAddress _, int __) => (
        target: (address: InternetAddress.fromRawAddress(n.address), port: n.port),
        detour: false
      );

  static void _codeCheck(Uint8List code) {
    if (code.length != kCodeLength) {
      throw ArgumentError('Code must have $kCodeLength B, has ${code.length}');
    }
  }

  static Uint8List _withCode(int kind, int hopCount, Uint8List code, Uint8List content) {
    _codeCheck(code);
    if (hopCount < 0 || hopCount > 0xFF) {
      throw ArgumentError('Hop count must be between 0 and 255, was $hopCount');
    }
    return (BytesBuilder(copy: false)
          ..addByte(kind)
          ..addByte(hopCount)
          ..add(code)
          ..add(content))
        .toBytes();
  }

  /// `0x20` — pass on under [code].
  static Uint8List build(
          {required Uint8List code,
          required Uint8List content,
          int hopCount = kStartHopCount}) =>
      _withCode(kinds.kForward, hopCount, code, content);

  /// `0x23` — where are you.
  static Uint8List buildWhereAreYou(
          {required Uint8List code,
          required Uint8List content,
          int hopCount = kStartHopCountSearch}) =>
      _withCode(kinds.kWhereAreYou, hopCount, code, content);

  /// `0x22` — hand [inner] (a `0x20`) to each of [next] (1–3).
  static Uint8List buildDetour(List<CardAddress> next, Uint8List inner,
          {int hopCount = kStartHopCount}) =>
      detourBuild(next, inner, hopCount: hopCount);

  /// `0x21` — unknown to me.
  static Uint8List buildUnknownCode(Uint8List code) {
    _codeCheck(code);
    return (BytesBuilder(copy: false)
          ..addByte(kinds.kUnknownCode)
          ..add(code))
        .toBytes();
  }

  /// Feeds in an incoming packet. `true` if it was a kind
  /// of this file.
  bool receive(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.isEmpty) return false;
    _clearOld();
    switch (packet[0]) {
      case kinds.kForward:
        _onCode(packet, from, fromPort);
      case kinds.kUnknownCode:
        _onUnknownCode(packet);
      case kinds.kDetour:
        _onDetour(packet, from, fromPort);
      case kinds.kWhereAreYou:
        _onSearch(packet, from, fromPort);
      default:
        return false;
    }
    return true;
  }

  void _onCode(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.length < _kHeaderCode) {
      throw ForwardError('0x20 too short: ${packet.length} B');
    }
    final hopCount = packet[1];
    final code = _cut(packet, 2, _kHeaderCode);
    final content = _cut(packet, _kHeaderCode, packet.length);
    // Delivering is not forwarding — hop count and loop guard
    // do not apply to it.
    if (isOwnCode(code)) {
      report?.call('0x20: own code ${_short(code)} arrived '
          '(${content.length} B)');
      onTarget?.call(content, from, fromPort);
      return;
    }
    if (!_firstTimes(content)) return;
    if (hopCount == 0) return;
    final device = codeSearch(code);
    if (device == null) {
      unknown++;
      report?.call('0x20: code ${_short(code)} not registered here — 0x21 '
          'to ${from.address}:$fromPort');
      send(buildUnknownCode(code), from, fromPort);
      return;
    }
    passed++;
    report?.call('0x20: code ${_short(code)} handed to its device '
        '${device.address.address}:${device.port}');
    send(build(code: code, content: content, hopCount: hopCount - 1),
        device.address, device.port);
  }

  void _onDetour(Uint8List packet, InternetAddress from, int fromPort) {
    final Detour d;
    try {
      d = detourRead(packet);
    } on Exception catch (e) {
      throw ForwardError('0x22 unreadable: $e');
    }
    final hopCount = d.hopCount, inner = d.inner;
    if (hopCount == 0) return;
    if (inner.length < _kHeaderCode || inner[0] != kinds.kForward) {
      report?.call('0x22 without inner 0x20 — discarded');
      return;
    }
    final next = detourSpread(d.next, registered(from, fromPort));
    if (next.isEmpty || !_firstTimes(inner)) return;
    final code = _cut(inner, 2, _kHeaderCode);
    _detourFrom[_hex(code)] = (from: (address: from, port: fromPort), at: now());
    detours++;
    // A code registered HERE means this node is a fixed neighbour of the
    // recipient (§8.1: a device registers only with its own) — even when
    // the sender names it by an address [isSelf] cannot know (S394: a port
    // forward's public IPv4 while the sender reaches it by IPv6). It is
    // handled here AND still handed to the next addresses, so a device that
    // moved loses nothing; a copy that comes back is dropped by the loop
    // guard. Handled here at most once per packet.
    var here = _heldHere(inner);
    if (here) _onCode(inner, from, fromPort);
    for (final n in next) {
      final target = InternetAddress.fromRawAddress(n.address);
      if (isSelf(target, n.port)) {
        report?.call('0x22 to this node itself — unpacked here');
        if (!here) _onCode(inner, from, fromPort);
        here = true;
        continue;
      }
      final s = nextStep(n, from, fromPort);
      final on = s == null || (s.detour && hopCount <= 1) ? null : s;
      final via = on == null || on.target.address.address == target.address
          ? ''
          : ' via ${on.target.address.address}:${on.target.port}'
              '${on.detour ? " (0x22, hop count ${hopCount - 1})" : ""}';
      report?.call('0x22: code ${_short(code)} '
          '${on == null ? "not handed on (no socket, no neighbour of that address "
              "family within hop count $hopCount) to " : "handed on to "}'
          '${target.address}:${n.port}$via (${next.length}/${d.next.length})');
      if (on == null) continue;
      send(on.detour ? buildDetour([n], inner, hopCount: hopCount - 1) : inner,
          on.target.address, on.target.port);
    }
  }

  /// Is the code of the inner `0x20` [inner] registered with this node?
  bool _heldHere(Uint8List inner) {
    final code = _cut(inner, 2, _kHeaderCode);
    return isOwnCode(code) || codeSearch(code) != null;
  }

  void _onSearch(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.length < _kHeaderCode) {
      throw ForwardError('0x23 too short: ${packet.length} B');
    }
    final code = _cut(packet, 2, _kHeaderCode);
    final content = _cut(packet, _kHeaderCode, packet.length);
    if (isOwnCode(code)) {
      onSuchTarget?.call(code, content);
      return;
    }
    if (!_firstTimes(content)) return;
    final rest = packet[1] - 1;
    final device = codeSearch(code);
    if (device == null && rest <= 0) return; // Reichweite erschoepft
    final who = '${from.address}:$fromPort';
    final last = _searchFrom[who];
    if (last != null && now().difference(last) < suchThrottle) {
      searchThrottled++;
      report?.call('0x23 from $who throttled');
      return;
    }
    _searchFrom[who] = now();
    final further = buildWhereAreYou(
        code: code, content: content, hopCount: rest < 0 ? 0 : rest);
    if (device != null) {
      send(further, device.address, device.port);
      return;
    }
    for (final n in neighbours()) {
      if (n.port == fromPort && n.address.address == from.address) continue;
      searchFurther++;
      send(further, n.address, n.port);
    }
  }

  void _onUnknownCode(Uint8List packet) {
    if (packet.length != _kHeaderUnknownCode) {
      throw ForwardError(
          '0x21 has ${packet.length} B, expected $_kHeaderUnknownCode B');
    }
    final code = _cut(packet, 1, _kHeaderUnknownCode);
    // If the 0x20 came via a detour through THIS node, the message goes
    // to the one who gave it — once.
    final origin = _detourFrom.remove(_hex(code));
    if (origin != null) {
      send(packet, origin.from.address, origin.from.port);
      return;
    }
    onUnknown?.call(code);
  }

  /// `true` if this content has not yet come through within the period.
  bool _firstTimes(Uint8List content) {
    final k = _hex(_cut(SodiumFFI().sha256(content), 0, _kPacketIdentifierLength));
    if (_seen.containsKey(k)) return false;
    _seen[k] = now();
    return true;
  }

  void _clearOld() {
    final t = now();
    final limit = t.subtract(loopGuardDuration);
    _seen.removeWhere((_, time) => time.isBefore(limit));
    _detourFrom.removeWhere((_, e) => e.at.isBefore(limit));
    final suchLimit = t.subtract(suchThrottle);
    _searchFrom.removeWhere((_, time) => time.isBefore(suchLimit));
  }
}

/// Real copy of a slice — the slices outlive the packet.
Uint8List _cut(Uint8List b, int from, int until) =>
    Uint8List.fromList(Uint8List.sublistView(b, from, until));

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

String _short(Uint8List code) => _hex(code).substring(0, 8);
