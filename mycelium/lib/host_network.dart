/// The network under the network at the host (S391, §5.2, §5.5, §11.8, §11.8a).
///
/// Four parts are built individually and connected with each other here:
///
/// * the **neighbourhood** (`neighbourhood.dart`) — 32 as the optimum, the
///   stamp as confirmation, removal only after failed use,
///   a removal as an edge for refilling, the open set of four
///   with one fixed seat;
/// * the **cover stream** (`cover_stream.dart`) — draws its targets from the
///   open set and carries address entries along;
/// * the **board** (`board*.dart`) — asked at the
///   edges, given only with proven reachability;
/// * the **router mapping** ([router], `host_router.dart`) — asked at the
///   edges start and network change, its proof read by the board and the
///   keep-alive (S408-LEBENSLAUF P15, A-4).
///
/// No clock: everything here runs at edges — start, network change, new
/// neighbour, removal — or with a packet that comes anyway.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/util/local_addresses.dart' show dialableFrom;
import 'package:mycelium/address_entries.dart';
import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_call.dart' show NodeCall;
import 'package:mycelium/neighbour_found_by.dart';
import 'package:mycelium/neighbour_hints.dart';
import 'package:mycelium/node_roam.dart' show kPathChecksAtMost;
import 'package:mycelium/node_silence.dart';
import 'package:mycelium/who_question.dart';
import 'package:mycelium/board_node.dart';
import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/keep_alive.dart';
import 'package:mycelium/keep_alive_measure.dart';
import 'package:mycelium/mapping_echo.dart';
import 'package:mycelium/open_check.dart';
import 'package:mycelium/open_check_answer.dart';
import 'package:mycelium/network_watch.dart';
import 'package:mycelium/host_outside.dart';
import 'package:mycelium/host_media.dart' show bulkFamilyOpen;
import 'package:mycelium/host_router.dart';
import 'package:mycelium/node_helpers.dart' show interfaces;
import 'package:mycelium/host_memory.dart';
import 'package:mycelium/own_entries.dart';
import 'package:mycelium/node_invitation.dart' show namedByStandingCard;
import 'package:mycelium/invitation_way_in.dart' show wayInEdge;
import 'package:mycelium/trace.dart' show traceOn;
import 'package:mycelium/trace_first_contact.dart' show seatsOf;

/// One own address with its port (§17.3 candidates, [HostNetwork.ownLocal]).
typedef OwnEndpoint = ({InternetAddress address, int port});

class HostNetwork {
  final Node _k;
  final OutsideSource _outside;
  final HostMemory _memory;

  /// The admission of learned addresses (§11.8.3).
  final NeighbourHints hints;

  /// Sets the current pass of source 4 (`Host.outsideRun`).
  final void Function(Future<void> run) _run;
  final void Function(String)? _report;

  /// Whether the own router has granted a mapping or a pinhole
  /// (§7.3) — [router]'s; a probe may set its own. Proof for the board (§11.8a).
  late bool Function() mappingProven = () => router.proven;

  /// The router mapping and pinhole (§7.3); the host sets its switch.
  late final HostRouter router = HostRouter(() => _k.port, _granted, _report);

  /// The keep-alive per address type (§8.1) — runs from the construction of the network.
  late final KeepAlive keepAlive = KeepAlive(_k);

  /// When its interval is measured, and the neighbour's echo (§8.1).
  late final KeepAliveMeasure measure = KeepAliveMeasure(_k, keepAlive);
  late final MappingEcho echo = MappingEcho(_k);

  /// Is a family open from outside, and the neighbours' half (§8.1).
  late final OpenCheck openCheck = OpenCheck(_k);
  late final OpenCheckAnswer openAnswer = OpenCheckAnswer(_k);

  /// The edge "network change" decided in one place (§11.8.2, S407-LB-P14):
  /// the platform hands in its events, this says whether they are one.
  late final NetworkWatch watch = NetworkWatch(
      () => keepAlive.intervalV4 < keepAlive.intervalV6
          ? keepAlive.intervalV4
          : keepAlive.intervalV6,
      report: _report);

  String? _fixed;
  List<Neighbour> _fixedList = const [];

  HostNetwork(this._k, this._outside, this._memory,
      void Function(List<(InternetAddress, int)> fresh) newNeighbour,
      this._run, this._report)
      : hints = NeighbourHints(_k, newNeighbour, _report) {
    final n = _k.neighbourhood;
    // §11.8 source 1 — immediately there and "usually enough".
    n.outMemory(_memory.rememberedNeighbours);
    for (final x in [...n.all, ...n.waiting]) {
      n.noteFoundBy(x, NeighbourSource.remembered);
    }
    if (_memory.rememberedNeighbours.isNotEmpty) {
      _report?.call('${_memory.rememberedNeighbours.length} neighbour(s) taken over from '
          'the last run');
    }
    _fixedList = n.fixedNeighbours;
    _fixed = _key(_fixedList);
    _k.coverStream
      ..targets = (() => [for (final x in n.openSet()) (x.address, x.port)])
      ..entries = _entries
      ..onEntries = hints.addressList;
    _outside.answer = _k.answerAttach(
        confirmed: n.confirmed,
        mappingProven: () => mappingProven(),
        onBoardAnswer: (l, a, p) =>
            hints.addressList(l, a, p, source: NeighbourSource.board));
    _k.outsideRoute.onAnswerReceived =
        (a, p) => n.confirm(a, p, DateTime.now());
    // §11.8.4: every answer to a request of this node stamps the address it
    // went to — the acknowledgement, a media or stream answer, a deposit
    // receipt, a board answer, every other (S407-LB-P1 C-2). Only an address
    // the list holds: the list is filled by its sources (§11.8.3), and a
    // removed address returns only through §11.8.6.
    _k.silence.onAnswered = (a, p) {
      if (n.holding(a, p) != null) n.confirm(a, p, DateTime.now());
    };
    n.onUnderTarget = refill;
    // V6: a standing invitation keeps the fixed seat where its card points.
    n.namedByCards = (x) => namedByStandingCard(_k, x);
    // The fixed neighbour stands in every issued card: if it changes,
    // it is saved IMMEDIATELY, not only on stopping (W7).
    n.observe(removed: (_) => fixedCheck(), onConfirmed: (_) {
      fixedCheck();
      measure.edge(); // §8.1: a confirmed neighbour is the edge to measure
      openCheck.edge(); // §8.1: ... and to check whether a family is open
    });
    _k.outsideRoute
      ..onAsked = echo.asked
      ..onProbe = echo.receive
      ..onOpenCheck = openAnswer.receive;
    keepAlive
      ..familyOpen = openCheck.isOpen
      ..ipv4Mapped = (() => router.ipv4Proven) // §8.1: the router holds it
      ..ipv6Mapped = (() => router.ipv6Proven);
    // §8.1: on a metered link a contact reachable only over IPv4 takes no
    // contact seat; the metered flag changing is an edge for the seats.
    n.v4OnlyOnMetered = keepAlive.v4OnlyOnMetered;
    _k.coverStream.onMetered = () {
      n.contactSeatsCheck();
      fixedCheck();
    };
    openCheck.onOpen = (_) {
      keepAlive.edgeNow();
      _run(_outside.write()); // §11.9: the seen address is now publishable
      wayInEdge(_k); // §12.4: an open family can be an invitation's way in
    };
    // §11.9 (S410 A): a seen address is published only with its family
    // evidenced open; each evidence's first arrival is an edge to publish.
    _outside.familyEvidenced = (f) =>
        bulkFamilyOpen(this, f) || (_k.passiveProof?.provenFor(f) ?? false);
    _k.passiveProof?.onFamily = (_) => _run(_outside.write());
    _k.coverStream.onKeepAlive = echo.keepAlive;
    echo.onMoved = keepAlive.moved;
    keepAlive.start();
    measure.edge(); // §8.1: the edge "start"
    openCheck.edge();
    unawaited(watch.begin()); // the edge "start": the first report is no change
  }

  // ── The own addresses for a direct path (§17.3; S408 P17) ──────────────
  // Plane D's call candidates come from here: the interfaces read at the
  // edges, the router's grant, the mirror — one source, no own enumeration
  // beside the host. A change reaches a call through the edge network change.

  /// The own interface addresses under the data port, private IPv4 first.
  List<OwnEndpoint> get ownLocal => [
        for (final ip in dialableFrom(interfaces))
          if (InternetAddress.tryParse(ip) case final a?) (address: a, port: _k.port),
      ];

  /// The outer endpoint of a granted, unexpired router mapping (§7.3).
  OwnEndpoint? get ownMapped {
    final m = router.current?.mapper;
    final ip = InternetAddress.tryParse(m?.externalIp ?? '');
    final p = m?.externalPort ?? 0;
    return m == null || !m.hasMapping || ip == null || p <= 0
        ? null : (address: ip, port: p);
  }

  /// The own address as a neighbour outside the own segment saw it (§7.3).
  OwnEndpoint? get ownMirrored => switch (_k.publicAddress) {
        final p? => (
            address: InternetAddress.fromRawAddress(Uint8List.fromList(p.address)),
            port: p.port),
        null => null,
      };

  /// A granted mapping (IPv4: the outer address IS the public one) or
  /// pinhole is a reachable address: published (§11.9) and a way in (§12.4).
  void _granted(InternetAddress outside, int port) {
    if (outside.type == InternetAddressType.IPv4) {
      _k.publicAddress =
          CardAddress(Uint8List.fromList(outside.rawAddress), port);
    }
    _run(_outside.write());
    wayInEdge(_k);
  }

  /// On stopping the host: the keep-alive clock and its measurement stop.
  void stop() {
    keepAlive.stop();
    measure.stop();
    openCheck.stop();
    watch.stop();
  }

  /// EDGE network change (`Host.networkChanged`): the measured intervals
  /// belong to the old network (§8.1), and every remembered address is tried
  /// once (§11.8.2) — not only the stale ones: a stamp from the old network
  /// says nothing about the new one, and without a request of its own a
  /// neighbour confirmed today stayed an acquaintance until some other
  /// packet happened to reach it (S407-LB-P8 C-9). Then, as at start,
  /// source 3 ([NeighbourHints.invitationTry]): it adds only what the list does not hold,
  /// so no address is asked twice; the removal memory is already cleared
  /// (`Readiness.reset`), so a removed card address is tried again.
  void networkChanged() {
    unawaited(router.edge()); // §7.3: the router is asked at this edge too
    openCheck.networkChanged(); // first: the keep-alive looks at its result
    measure.networkChanged();
    rememberedTry();
    hints.invitationTry();
  }

  /// §25.7: source 4 is on and a record of this node stands at the relays.
  bool get ownRecordPublished => _outside.to && _outside.state.publishedAt(DateTime.now().millisecondsSinceEpoch ~/ 1000);

  /// What the cover stream takes along to [target] (§5.5): the own
  /// addresses (S394 V2, `own_entries.dart`) and the confirmed neighbours,
  /// one entry per node and at most 32, without the target itself and
  /// without loopback entries to a target that is not loopback ([entryFor]).
  AddressList _entries((InternetAddress, int) target) {
    final now = DateTime.now();
    return AddressList(
        own: [for (final a in ownEntriesFor(_k, target.$1)) AddressEntry(a, 0)],
        neighbours: [
          for (final x in _k.neighbourhood.confirmed(now))
            if (!x.has(target.$1, target.$2))
              AddressEntry.fromNeighbour(x, now, target.$1),
        ].where((e) => entryFor(e.address, target.$1))
            .take(kAddressEntriesAtMost)
            .toList());
  }

  /// Edge: a removal let the list fall below 32 (§11.8.2): sources 1–3,
  /// the board, the external records — stale entries, the invitation data
  /// (S407-LB-P8 C-10), the call, then board and external entries.
  void refill() {
    _report?.call('Neighbourhood below the optimum — refill round');
    staleTry();
    hints.invitationTry();
    _run(_outside.afterSources(_k.call()));
  }

  /// Every stale entry is tried at an edge (§11.8) — with the address
  /// question whose answer confirms it. The question is repeated and, without
  /// an answer, the address declared failed by the transport (§11.3a,
  /// `silence.dart`), only with counter-evidence; nothing is counted here.
  void staleTry() {
    var who = kPathChecksAtMost; // at most this many at one edge (D-87)
    for (final x in _k.neighbourhood.stale(DateTime.now())) {
      final what = 'Stale address ${x.address.address}:${x.port}';
      _report?.call('$what — asked (§11.8.5)');
      if (who > 0 && _k.who.ask(x.address, x.port)) who--;
      unawaited(_k.outsideRoute.whatIsMyAddress(x.address, x.port).then((seen) =>
          _report?.call(seen == null
              ? '$what — no answer (§11.3a decides)'
              : '$what — answered, confirmed')));
    }
  }

  /// Every remembered address is tried at the edge network change
  /// (§11.8.2, §11.8.5) — each address of each neighbour on its own, with
  /// the same address question as [staleTry]; its answer stamps the address,
  /// its silence is the transport's (§11.3a). Only addresses of a family this
  /// node has a socket for (§11.1): one under a lost family waits, unused.
  void rememberedTry() {
    var who = kPathChecksAtMost; // at most this many at one edge (D-87)
    for (final x in _k.neighbourhood.all) {
      for (final a in x.addresses) {
        if (!_k.speaks(a.address)) continue;
        if (who > 0 && _k.who.ask(a.address, a.port)) who--;
        unawaited(_k.outsideRoute.whatIsMyAddress(a.address, a.port));
      }
    }
  }

  /// Writes the current neighbourhood including fixed seat into memory.
  void save() {
    _memory.rememberedNeighbours
      ..clear()
      ..addAll(_k.neighbourhood.toRemember); // what waits, too (C-7)
    _memory.save();
  }

  /// The edge "the fixed neighbours may have changed" — from the
  /// neighbourhood's listeners, and from the host for a contact edge.
  void fixedCheck() {
    final list = _k.neighbourhood.fixedNeighbours;
    final now = _key(list);
    if (now == _fixed) return;
    final before = _fixedList;
    _fixed = now;
    _fixedList = list;
    if (traceOn) {
      _report?.call('TRACE seat fixed neighbours changed: '
          '${seatsOf(_k.neighbourhood, _k.readiness.responding).join(" | ")}');
    }
    save();
    // S394 V6: a new fixed NODE needs the codes before a contact sends there
    // (§8.1) — the registration goes out NOW as `0x24`.
    // Only a neighbour that lacks them gets pieces (`code_registrants.dart`).
    if (list.any((n) => !before.any((b) => b.id == n.id))) {
      _k.codeRoute.edge();
    }
    // §8.1: whether IPv4 may rest depends on the fixed neighbour.
    keepAlive.edgeNow();
    // No notice to the contacts: the list rides sealed in every message and
    // acknowledgement (`message.dart`; proposal rule 5, the 0x17 is gone).
  }

  /// The fixed neighbours with their seats as the cards name them — a new
  /// id, another seat OR another card address is a change (§8.1).
  static String _key(List<Neighbour> l) => [
        for (final n in l)
          '${n.id}/${n.fixed ? 'card' : n.contactSeat}/${n.asCardAddress}'
      ].join(' ');
}
