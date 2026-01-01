/// The keep-alive per address type (V4.2 §8.1, owner decision E1,
/// 17.09.2026; measured interval and resting IPv4, 24.09.2026).
///
/// A path through an address translation or a stateful
/// firewall stays open only as long as packets go OUT on it; outgoing
/// traffic alone refreshes it (RFC 4787 REQ-6, RFC 6092 REC-16). The
/// packet therefore needs no answer: it is a cover packet with content
/// `0x04` (§5.5) — device code and a random token, so that the fixed
/// neighbour can follow and report a move (`mapping_echo.dart`) — and
/// looks like cover on the wire.
///
/// | Path | Interval | when |
/// |---|---|---|
/// | IPv4 | [kKeepAliveTick] until measured, then the measured one | to one neighbour — preferably one that also answers over IPv6; rests under [v4Rests] |
/// | IPv6 | [kKeepAliveV6] until measured, then the measured one | to each fixed contact neighbour with IPv6, the card's seat while an invitation stands; where none, to one (`keep_alive_fixed.dart`) |
///
/// Why 30 s for IPv4: translators are often shorter than RFC 4787 asks —
/// 74 % expire idle UDP state after one minute or less, values 10-200 s,
/// median 65 s in mobile and 35 s in fixed-line carrier translation
/// (Richter et al., "A Multi-perspective Analysis of Carrier-Grade NAT
/// Deployment", IMC 2016, arXiv:1605.05606, §6 "Mapping Timeouts"). No
/// carrier documents its value; the node measures its own
/// (`keep_alive_measure.dart`). Why 60 s for IPv6: RFC 6092 REC-14, a
/// firewall keeps UDP state for at least two minutes.
///
/// No packet on an address type under which the own address is reachable
/// (public IPv4, granted mapping or granted pinhole, or the family found
/// open by `open_check.dart`), and
/// none to a neighbour to which the cover has already sent within this
/// interval. Where both address types are kept, a packet on one takes the other
/// along once it is [kAlongShare] through its interval — one wake of the
/// radio modem instead of two.
///
/// Besides the cover stream this is the only standing traffic on the
/// data port (§5.4, working rule 5).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/keep_alive_fixed.dart' as fixed_v6;
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show interfaces;
import 'package:mycelium/neighbourhood.dart';

/// The IPv4 interval until measured (§8.1).
const Duration kKeepAliveTick = Duration(seconds: 30);

/// The IPv6 interval until measured (§8.1) — within RFC 6092 REC-14.
const Duration kKeepAliveV6 = Duration(seconds: 60);

/// IPv6 counts as carrying (condition 2 of [KeepAlive.v4Rests]) from this
/// measured holding time on.
const Duration kV6Carries = Duration(seconds: 60);

/// Share of its interval after which a family goes along with the other.
const double kAlongShare = 0.75;

/// A little slack, so that a cover packet shortly before the due time counts.
const Duration _slack = Duration(seconds: 2);

/// Tokens of the last keep-alives, to recognise a move report (`0x47`).
const int kTokensKept = 8;

/// What a measurement found for one address family (§8.1).
class Held {
  /// The longest silence that held; `null`: none held (not holdable).
  final Duration? longest;
  final DateTime at;
  const Held(this.longest, this.at);

  /// Three quarters of [longest] — `null` if not holdable.
  Duration? get interval {
    final l = longest;
    return l == null ? null : Duration(milliseconds: l.inMilliseconds * 3 ~/ 4);
  }
}

class KeepAlive {
  final Node _k;

  /// Whether the own router has granted an IPv4 mapping or an IPv6 pinhole
  /// (§7.3) — set by the app seam.
  bool Function() ipv4Mapped = () => false;
  bool Function() ipv6Mapped = () => false;

  /// Whether the open check (§8.1, `open_check.dart`) found [type] open —
  /// set by the host network.
  bool Function(InternetAddressType type) familyOpen = (_) => false;

  /// The own addresses — different only for probes.
  final List<InternetAddress> Function() ownAddresses;

  /// Whether this node holds an IPv6 socket (§11.1, S394 V1) — the wire's
  /// answer in operation, different only for probes.
  final bool Function() ipv6Socket;

  /// Sends ONE keep-alive with [content] (device code + token); in
  /// operation `CoverStream.keepAliveSend`.
  final bool Function((InternetAddress, int) target, Uint8List content) _send;

  /// The measured results (`keep_alive_measure.dart`); `null`: defaults.
  Held? heldV4;
  Held? heldV6;

  /// A move report dropped a family back to its default (§8.1).
  void Function(InternetAddressType type)? onFallback;

  final Random _random = Random.secure();
  final Map<String, DateTime> _sentAt = {};
  final List<(String, InternetAddressType)> _tokens = [];
  Timer? _clock;

  /// Counters for probes and the network statistics (§25).
  int sentV4 = 0;
  int sentV6 = 0;
  int replacedThroughCover = 0;
  int moves = 0;

  KeepAlive(this._k,
      {List<InternetAddress> Function()? ownAddresses,
      bool Function()? ipv6Socket,
      bool Function((InternetAddress, int) target)? send})
      : ownAddresses = ownAddresses ??
            (() => [
                  for (final s in interfaces)
                    for (final a in s.addresses) a
                ]),
        ipv6Socket =
            ipv6Socket ?? (() => _k.speaks(InternetAddress.loopbackIPv6)),
        _send = send != null
            ? ((t, _) => send(t))
            : ((t, c) => _k.coverStream.keepAliveSend(t, c));

  bool get runs => _clock != null;

  Duration get intervalV4 => heldV4?.interval ?? kKeepAliveTick;
  Duration get intervalV6 => heldV6?.interval ?? kKeepAliveV6;

  void start() {
    if (_clock == null) _plan(kKeepAliveTick);
  }

  void stop() {
    _clock?.cancel();
    _clock = null;
  }

  /// An edge (measurement, new fixed neighbour): look NOW, then plan anew.
  void edgeNow() {
    if (_clock == null) return;
    _plan(tick());
  }

  void _plan(Duration d) {
    _clock?.cancel();
    _clock = Timer(d, () {
      if (_clock == null) return;
      _plan(tick());
    });
  }

  /// A measurement for [type] (§8.1).
  void measured(InternetAddressType type, Held h) {
    if (type == InternetAddressType.IPv4) {
      heldV4 = h;
    } else {
      heldV6 = h;
    }
    edgeNow();
  }

  /// Network change: what was measured belongs to the old network.
  void networkChanged() {
    heldV4 = null;
    heldV6 = null;
    _sentAt.clear();
    _tokens.clear();
    edgeNow();
  }

  /// A `0x47` with [token]: the mapping of that family lapsed despite the
  /// interval — back to the default (§8.1).
  void moved(Uint8List token) {
    final h = _hex(token);
    final i = _tokens.indexWhere((e) => e.$1 == h);
    if (i < 0) return; // not ours, or too old
    final type = _tokens.removeAt(i).$2;
    moves++;
    if (type == InternetAddressType.IPv4) {
      heldV4 = null;
    } else {
      heldV6 = null;
    }
    _k.report('Keep-alive: the neighbour saw the ${type.name} path move — '
        'back to the default interval (§8.1)');
    onFallback?.call(type);
    edgeNow();
  }

  /// IPv4 rests (§8.1) while all three hold: (1) IPv4 measured below 30 s
  /// or not holdable; (2) IPv6 measured holding at least [kV6Carries], or a
  /// granted pinhole; (3) the fixed neighbour answers under IPv6 and — in
  /// this run — under IPv4 too, so it forwards between the address types.
  bool v4Rests(DateTime now) {
    final h4 = heldV4;
    if (h4 == null) return false;
    final i4 = h4.interval;
    if (i4 != null && i4 >= kKeepAliveTick) return false;
    final h6 = heldV6?.longest;
    // An IPv6 found open carries like a granted pinhole (§8.1): nothing in
    // between needs state, and no measurement runs on it any more.
    if (!ipv6Mapped() &&
        !familyOpen(InternetAddressType.IPv6) &&
        (h6 == null || h6 < kV6Carries)) {
      return false;
    }
    if (!_needsV6(ownAddresses()) && !ipv6Mapped()) return false;
    final f = _k.neighbourhood.fixedNeighbour;
    final a6 = f?.confirmedIn(
        InternetAddressType.IPv6, now.subtract(Neighbourhood.staleAfter));
    return a6 != null && _k.readiness.doubleStack(a6.address, a6.port);
  }

  /// Whom the keep-alive of [type] goes to — `null` if that family needs
  /// none; for IPv6 the first of [targetsV6]. The measurement asks it.
  NeighbourAddress? targetFor(InternetAddressType type, DateTime now) {
    if (type == InternetAddressType.IPv4) {
      return _needsV4(ownAddresses()) && !familyOpen(type)
          ? _targetV4(_k.neighbourhood.confirmed(now), now)
          : null;
    }
    final v6 = targetsV6(now);
    return v6.isEmpty ? null : v6.first;
  }

  /// The IPv6 keep-alive targets (§8.1, `keep_alive_fixed.dart`): each
  /// fixed contact neighbour with IPv6, the card's seat while an invitation
  /// names it; otherwise one neighbour. Empty where IPv6 needs none.
  List<NeighbourAddress> targetsV6(DateTime now) {
    const t = InternetAddressType.IPv6;
    if (!_needsV6(ownAddresses()) || ipv6Mapped() || familyOpen(t)) {
      return const [];
    }
    final fixed = fixed_v6.fixedV6Targets(_k.neighbourhood, now);
    if (fixed.isNotEmpty) return fixed;
    final one = _targetV6(_k.neighbourhood.confirmed(now), now);
    return [if (one != null) one];
  }

  /// [n] could reach this node only over IPv4 on a metered link — it does
  /// not count as a fixed contact neighbour there (§8.1, `keep_alive_fixed.dart`).
  /// Where the own IPv4 needs no keep-alive at all — public, mapped by the
  /// router, or found open — nobody is limited to one IPv4 path, and the
  /// rule has no reason to apply (its reason is the one IPv4 path, proposal
  /// "contacts as fixed neighbours", version 3, 3b).
  bool v4OnlyOnMetered(Neighbour n) => fixed_v6.v4OnlyOnMetered(n,
      metered: _k.coverStream.metered &&
          _needsV4(ownAddresses()) &&
          !familyOpen(InternetAddressType.IPv4),
      ownV6: _needsV6(ownAddresses()),
      public: _k.neighbourhood.openNetwork);

  bool _needsV4(List<InternetAddress> own) =>
      !ipv4Mapped() &&
      !own.any((a) =>
          a.type == InternetAddressType.IPv4 && fromOutsideReachable(a));

  // §11.1 (S394 V1): IPv6 is kept alive only with an IPv6 socket.
  bool _needsV6(List<InternetAddress> own) =>
      ipv6Socket() &&
      own.any((a) =>
          a.type == InternetAddressType.IPv6 && fromOutsideReachable(a));

  /// ONE look. Public so that probes can check without real time. Returns
  /// how long until the next look. Every path due or [kAlongShare] through
  /// its interval goes in this same look — one radio wake (§8.1).
  Duration tick([DateTime? now]) {
    final t = now ?? DateTime.now();
    final t4 = v4Rests(t) ? null : targetFor(InternetAddressType.IPv4, t);
    final paths = [
      if (t4 != null) (t4, intervalV4),
      for (final a in targetsV6(t)) (a, intervalV6),
    ];
    final shares = [for (final (a, i) in paths) _share(a, i, t)];
    final due = shares.any((s) => s >= 1);
    for (var j = 0; j < paths.length; j++) {
      if (due && shares[j] >= kAlongShare) {
        if (_hold(paths[j].$1, t)) {
          paths[j].$1.address.type == InternetAddressType.IPv4
              ? sentV4++
              : sentV6++;
        }
      } else {
        replacedThroughCover++;
      }
    }
    Duration? next;
    for (final (target, interval) in paths) {
      final left = interval - t.difference(_last(target) ?? t);
      if (next == null || left < next) next = left;
    }
    if (next == null || next < const Duration(seconds: 1)) {
      return next == null ? kKeepAliveTick : const Duration(seconds: 1);
    }
    return next;
  }

  DateTime? _last(NeighbourAddress n) {
    final own = _sentAt[n.key];
    final cover = _k.coverStream.lastTo((n.address, n.port));
    if (own == null) return cover;
    if (cover == null) return own;
    return own.isAfter(cover) ? own : cover;
  }

  /// How far through [interval] the path to [n] is — 1 or more is due.
  double _share(NeighbourAddress n, Duration interval, DateTime now) {
    final last = _last(n);
    if (last == null) return double.infinity;
    return (now.difference(last) + _slack).inMilliseconds /
        interval.inMilliseconds;
  }

  bool _hold(NeighbourAddress n, DateTime now) {
    final token = Uint8List.fromList(
        List<int>.generate(8, (_) => _random.nextInt(256)));
    final content = Uint8List(_k.devicesCode.length + token.length)
      ..setRange(0, _k.devicesCode.length, _k.devicesCode)
      ..setRange(_k.devicesCode.length, _k.devicesCode.length + 8, token);
    if (!_send((n.address, n.port), content)) return false;
    _sentAt[n.key] = now;
    _tokens.add((_hex(token), n.address.type));
    while (_tokens.length > kTokensKept) {
      _tokens.removeAt(0);
    }
    return true;
  }

  /// Per confirmed neighbour its address of type [t] confirmed within
  /// [Neighbourhood.staleAfter] — a neighbour is a node with up to one
  /// address per family (S394 V4), and the path is kept per family.
  List<(Neighbour, NeighbourAddress)> _in(
      List<Neighbour> confirmed, InternetAddressType t, DateTime now) {
    final notBefore = now.subtract(Neighbourhood.staleAfter);
    return [
      for (final n in confirmed)
        if (n.confirmedIn(t, notBefore) case final a?) (n, a)
    ];
  }

  /// The fixed neighbour if it is IPv4 and dual-stack; otherwise a
  /// dual-stack neighbour; otherwise the fixed one; otherwise the most
  /// recently confirmed IPv4 neighbour.
  NeighbourAddress? _targetV4(List<Neighbour> confirmed, DateTime now) {
    final v4 = _in(confirmed, InternetAddressType.IPv4, now);
    if (v4.isEmpty) return null;
    final fixed = _k.neighbourhood.fixedNeighbour;
    NeighbourAddress? fixedOne;
    for (final (n, a) in v4) {
      if (n.id == fixed?.id) fixedOne = a;
    }
    bool dual(NeighbourAddress a) => _k.readiness.doubleStack(a.address, a.port);
    if (fixedOne != null && dual(fixedOne)) return fixedOne;
    for (final (_, a) in v4) {
      if (dual(a)) return a;
    }
    return fixedOne ?? v4.first.$2;
  }

  /// Without a fixed contact neighbour: the card's seat if it has IPv6
  /// (§8.1); otherwise the most recently confirmed IPv6 neighbour.
  NeighbourAddress? _targetV6(List<Neighbour> confirmed, DateTime now) {
    final v6 = _in(confirmed, InternetAddressType.IPv6, now);
    if (v6.isEmpty) return null;
    final fixed = _k.neighbourhood.fixedNeighbour;
    for (final (n, a) in v6) {
      if (n.id == fixed?.id) return a;
    }
    return v6.first.$2;
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
