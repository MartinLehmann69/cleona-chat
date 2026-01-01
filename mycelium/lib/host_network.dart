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
/// * the app's **port mapping** — it reports its proof via
///   [HostNetwork.mappingProven].
///
/// No clock: everything here runs at edges — start, network change, new
/// neighbour, removal — or with a packet that comes anyway.
library;

import 'dart:async';
import 'dart:io';

import 'package:mycelium/address_entries.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_call.dart' show NodeCall, neighbourAdd;
import 'package:mycelium/board_node.dart';
import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/keep_alive.dart';
import 'package:mycelium/keep_alive_measure.dart';
import 'package:mycelium/mapping_echo.dart';
import 'package:mycelium/open_check.dart';
import 'package:mycelium/open_check_answer.dart';
import 'package:mycelium/host_outside.dart';
import 'package:mycelium/host_memory.dart';
import 'package:mycelium/own_entries.dart';
import 'package:mycelium/node_invitation.dart' show namedByStandingCard;
import 'package:mycelium/invitation_way_in.dart' show wayInEdge;
import 'package:mycelium/trace.dart' show traceOn;
import 'package:mycelium/trace_first_contact.dart' show seatsOf;

/// An entry whose confirmation lies further back is stale
/// (§11.8) and is not adopted from foreign lists.
final int _staleMinutes = Neighbourhood.staleAfter.inMinutes;

class HostNetwork {
  final Node _k;
  final OutsideSource _outside;
  final HostMemory _memory;

  /// The host's edge "new neighbour" (save, re-dispatch, ask the new
  /// ones, notify the app).
  final void Function(List<(InternetAddress, int)> fresh) _newNeighbour;

  /// Sets the current pass of source 4 (`Host.outsideRun`).
  final void Function(Future<void> run) _run;
  final void Function(String)? _report;

  /// Whether the own router has granted a mapping or a pinhole
  /// (§7.3) — set by the app seam. Proof for the board (§11.8a).
  bool Function() mappingProven = () => false;

  /// The keep-alive per address type (§8.1) — runs from the construction of the network.
  late final KeepAlive keepAlive = KeepAlive(_k);

  /// When its interval is measured, and the neighbour's echo (§8.1).
  late final KeepAliveMeasure measure = KeepAliveMeasure(_k, keepAlive);
  late final MappingEcho echo = MappingEcho(_k);

  /// Is a family open from outside, and the neighbours' half (§8.1).
  late final OpenCheck openCheck = OpenCheck(_k);
  late final OpenCheckAnswer openAnswer = OpenCheckAnswer(_k);

  String? _fixed;
  List<Neighbour> _fixedList = const [];

  HostNetwork(this._k, this._outside, this._memory, this._newNeighbour,
      this._run, this._report) {
    final n = _k.neighbourhood;
    // §11.8 source 1 — immediately there and "usually enough".
    n.outMemory(_memory.rememberedNeighbours);
    if (_memory.rememberedNeighbours.isNotEmpty) {
      _report?.call('${_memory.rememberedNeighbours.length} neighbour(s) taken over from '
          'the last run');
    }
    _fixedList = n.fixedNeighbours;
    _fixed = _key(_fixedList);
    _k.coverStream
      ..targets = (() => [for (final x in n.openSet()) (x.address, x.port)])
      ..entries = _entries
      ..onEntries = addressList;
    _outside.answer = _k.answerAttach(
        confirmed: n.confirmed,
        mappingProven: () => mappingProven(),
        onBoardAnswer: addressList);
    _k.outsideRoute.onAnswerReceived =
        (a, p) => n.confirm(a, p, DateTime.now());
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
    keepAlive.familyOpen = openCheck.isOpen;
    // §8.1: on a metered link a contact reachable only over IPv4 takes no
    // contact seat; the metered flag changing is an edge for the seats.
    n.v4OnlyOnMetered = keepAlive.v4OnlyOnMetered;
    _k.coverStream.onMetered = () {
      n.contactSeatsCheck();
      fixedCheck();
    };
    openCheck.onOpen = (_) {
      keepAlive.edgeNow();
      wayInEdge(_k); // §12.4: an open family can be an invitation's way in
    };
    _k.coverStream.onKeepAlive = echo.keepAlive;
    echo.onMoved = keepAlive.moved;
    keepAlive.start();
    measure.edge(); // §8.1: the edge "start"
    openCheck.edge();
  }

  /// On stopping the host: the keep-alive clock and its measurement stop.
  void stop() {
    keepAlive.stop();
    measure.stop();
    openCheck.stop();
  }

  /// EDGE network change (`Host.networkChanged`): the measured intervals
  /// belong to the old network (§8.1), stale entries are tried once (§11.8).
  void networkChanged() {
    openCheck.networkChanged(); // first: the keep-alive looks at its result
    measure.networkChanged();
    staleTry();
  }

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

  /// A received address list (cover §5.5, board §11.8a) from [from]:[port]:
  /// its own addresses are joined into ONE neighbour if the packet came
  /// from one of them (§11.8, V4) — otherwise they are hints like the rest.
  /// A loopback entry is taken only from a sender on loopback ([entryFor]).
  void addressList(AddressList l, InternetAddress from, int port) {
    final own = [for (final e in l.own) e.address];
    final r = _k.neighbourhood.ownAddresses(from, port, own);
    if (own.isNotEmpty) {
      _report?.call('Own addresses of ${from.address}:$port: ${own.join(', ')}'
          ' — ${r.bound ? 'one neighbour${r.fresh ? ' (new)' : ''}' : 'not bound '
              '(not sent from one of them) — taken as hints'}');
    }
    candidates([
      for (final e in [if (!r.bound) ...l.own, ...l.neighbours])
        if (entryFor(e.address, from)) e,
    ], fresh: [if (r.fresh) (from, port)]);
  }

  /// Learned addresses (cover stream, board) — HINTS, not neighbours.
  /// Admission happens only as long as the list lies below the optimum: a
  /// hint never displaces an entry. Stale entries stay outside.
  /// One edge, no matter how many are new; [fresh]: new ones the caller
  /// already entered.
  void candidates(List<AddressEntry> entries,
      {List<(InternetAddress, int)> fresh = const []}) {
    final n = _k.neighbourhood;
    final added = [...fresh];
    final now = DateTime.now();
    for (final e in entries) {
      if (n.count >= Neighbourhood.atMost) break;
      if (e.ageMinutes >= _staleMinutes) continue;
      final a = e.address;
      // S406: the entry's age says when its sender last confirmed it; a
      // removed address returns only with a confirmation after the removal.
      if (neighbourAdd(_k, a.address, a.port,
          confirmedAt: now.subtract(Duration(minutes: e.ageMinutes)))) {
        added.add((InternetAddress.fromRawAddress(a.address), a.port));
      }
    }
    if (added.isNotEmpty) _newNeighbour(added);
  }

  /// Edge: a removal let the list fall below 32 (§11.8). What
  /// runs is what a cold start starts — call, stale entries,
  /// board, external entries.
  void refill() {
    _report?.call('Neighbourhood below the optimum — refill round');
    staleTry();
    _run(_outside.afterSources(_k.call()));
  }

  /// Every stale entry is tried ONCE at an edge (§11.8) —
  /// with the address question whose answer confirms it. One request, never
  /// repeated; a failure is one use without an answer, and the entry goes at
  /// the second (§11.8 "two uses failed", `Readiness.mute`, S399 step 4),
  /// only with counter-evidence (E2).
  void staleTry() {
    for (final x in _k.neighbourhood.stale(DateTime.now())) {
      unawaited(_try(x));
    }
  }

  Future<void> _try(Neighbour x) async {
    if (await _k.outsideRoute.whatIsMyAddress(x.address, x.port) != null) return;
    _k.readiness.mute([(x.address, x.port)]);
  }

  /// Writes the current neighbourhood including fixed seat into memory.
  void save() {
    _memory.rememberedNeighbours
      ..clear()
      ..addAll(_k.neighbourhood.all);
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
