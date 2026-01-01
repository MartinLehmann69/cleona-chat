/// Source 4 (V4.2 §11.8, §11.9): the external address entries — when
/// read, when written, when nothing.
///
/// ── WHEN READING HAPPENS — NEW SINCE S391 ────────────────────────────────────
///
/// §11.9: "A node reads the records while it is below 32 answering
/// neighbours, and only at the edges of §11.8". A ROUND begins at start
/// and at every network change; sources 1–3 are done in it when the
/// query of the remembered neighbours AND the call series are finished. After that, and
/// BEFORE the entries, the board is asked ONCE (§11.8a,
/// `board.dart`); then reading happens as long as fewer than
/// [Neighbourhood.atMost] neighbours answer. Until S390 only a node that had
/// no answering or reported neighbour at all read.
///
/// ── WHEN WRITING HAPPENS — NEW SINCE S390 ────────────────────────────────
///
/// §11.9 (version 16.09.2026): "Reading and publishing are SEPARATE
/// decisions. […] Publishing follows reachability, not need: every node that
/// has an address through which it can be reached — a global IPv6, or a
/// public IPv4 — publishes its record, whether or not it ever needed the
/// relay itself. A node behind CGNAT has no such address and publishes
/// nothing."
///
/// Until S390 writing depended on `_gebraucht` — only a node that had itself read source 4
/// in this run entered itself. That turned the relay
/// on its head: entered was whoever found NOBODY, i.e. precisely the one whose
/// address helps a newcomer least. The condition is gone without replacement;
/// in its place stands the one question "is there a reachable address"
/// (`outside_address.dart`), and it decides BOTH branches — the
/// confirmed public address as well as that of an own interface
/// (D2-7).
///
/// ── THE REFRESH, AND WHY IT MOSTLY DOES NOTHING ─────────────────────
///
/// §11.9: "the check suppresses the publish while the addresses are
/// byte-identical AND less than 80 % of the record's lifetime has elapsed.
/// Only a genuine address change, or an approaching expiry, produces a single
/// write to 2–3 relays."
///
/// §5.4 lists this check as the SECOND clock in the system — explicitly not
/// on the data port, "a clock that usually decides to do nothing". It
/// therefore does not compete with delivery for socket, queue or budget,
/// and that is the reason why §5.4 permits it at all. What it costs at
/// rest: ONE event per ~19 h to 2–3 relays, a few hundred
/// bytes — under 2 KB/day, over TCP to the relay. Behind CGNAT: nothing.
///
/// The flag for it (`outside_state.dart`) is RESTART-PROOF. Without it
/// every start would write an entry although the old one is still valid for almost a day
/// — exactly the traffic the gate is meant to prevent.
///
/// ── DELETION ─────────────────────────────────────────────────────────────
///
/// §11.9: "a node leaving for good may additionally delete its record,
/// because it still holds the key." Orderly leaving here means: the
/// user switches the source off ([Host.outsideSourceOn]) or the application
/// calls [entryDelete]. NOT on ordinary stopping — a node
/// that goes off overnight is back tomorrow under the same address,
/// and its entry is still valid.
///
/// ── WHICH RELAYS ────────────────────────────────────────────────────────
///
/// `Node.knownRelay`: configured ones first, then those from read
/// cards (§11.9 "learned from the relay lists of cards it has read"), the
/// first three.
///
/// ── SWITCHED OFF ─────────────────────────────────────────────────────────
///
/// §11.9: "A node with it switched off neither reads nor publishes." [to]
/// is set by the host from its memory; it is flipped by the user.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/outside_address.dart';
import 'package:mycelium/outside_entry.dart';
import 'package:mycelium/outside_relay.dart';
import 'package:mycelium/outside_state.dart';
import 'package:mycelium/card.dart' show CardAddress, CardAddressType;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_outside.dart';
import 'package:mycelium/node_invitation.dart';
import 'package:mycelium/node_helpers.dart' show cardChannel, interfaces;
import 'package:mycelium/node_call.dart';
import 'package:mycelium/board.dart';
import 'package:mycelium/neighbourhood.dart';

/// §11.9 „relays written and read: 2–3" — the upper limit.
const int kOutsideRelayAtMost = 3;

/// At most how many found addresses are asked for the own public
/// address — as many as a deposit addresses neighbours
/// (§8.2 "three"). Every question is a round trip.
const int kOutsideAskAtMost = 3;

/// §5.4: "checked hourly, written at most once per ~19 h". The interval of the
/// check, not of writing — the check mostly does nothing.
const Duration kRefreshCheck = Duration(hours: 1);

/// §11.9: "less than 80 % of the record's lifetime has elapsed" — as a fraction,
/// so that the computation stays integral and does not round.
const int kRefreshCounter = 4;
const int kRefreshDenominator = 5;

class OutsideSource {
  final Node _k;
  final OutsideState _state;
  final void Function(List<int> ip, int port) _neighbourRemember;
  final void Function(String)? _report;
  final Duration _checkInterval;
  final int Function() _responding;

  /// §11.8a: asked once per round after sources 1–3; `null` =
  /// not attached yet (the wiring sets it).
  Board? answer;

  /// §11.9: on, or switched off by the user.
  bool to;

  Timer? _clock;
  DateTime _roundsStart;
  CardAddress? _publicBeforeRound;

  /// What the last round decided — the probes check with it that
  /// what stands on the wire is what was decided here.
  ({int responding, int reported, int answerAsk, bool read})?
      lastRound;

  /// What the last write check decided, and why. `grund` is
  /// for humans and for the probes — a gate that only lets "at most
  /// one" be counted would be a proxy.
  ({bool written, String reason})? lastSpelling;

  /// [directory] and [key] say where the stable key lies; without
  /// them it is transient (probes, and a node without storage).
  ///
  /// THE CLOCK RUNS FROM CONSTRUCTION, and that is intentional: an outside source that
  /// lives keeps its entry alive (§11.9). Arming it with a second
  /// call would mean that a forgotten call lets a node
  /// silently fall out of the relay — an error that nobody sees.
  /// [stop] is the counterpart; [checkInterval] `Duration.zero` leaves out
  /// the clock.
  OutsideSource(this._k,
      {required this.to,
      required DateTime roundsStart,
      required void Function(List<int> ip, int port) neighbourRemember,
      Directory? directory,
      Uint8List? key,
      Duration checkInterval = kRefreshCheck,
      int Function()? responding,
      void Function(String)? report})
      : _roundsStart = roundsStart,
        _state = directory == null || key == null
            ? OutsideState.ephemeral()
            : OutsideState.open(directory, key),
        _checkInterval = checkInterval,
        _responding = responding ?? (() => _k.readiness.respondingCount),
        _neighbourRemember = neighbourRemember,
        _report = report {
    if (_checkInterval > Duration.zero) {
      _clock = Timer.periodic(_checkInterval, (_) => unawaited(write()));
    }
  }

  /// The public key under which this node publishes —
  /// the same across restarts.
  String get publicHex => _state.publicHex;

  /// What this node last published, and with what. Readable because
  /// the refresh gate could otherwise only be measured via 19 hours of waiting
  /// — a probe that nobody runs is none.
  OutsideState get state => _state;

  /// Stops the clock. NO deletion — the entry stays valid (§11.9:
  /// deletion happens on leaving, not on stopping).
  void stop() {
    _clock?.cancel();
    _clock = null;
  }

  /// Flips the user's switch (§11.9 "The source can be switched off
  /// by the user"). Switching off is orderly leaving: the own
  /// entry is withdrawn. [to] takes effect IMMEDIATELY, the deletion runs
  /// afterwards — otherwise a caller reading directly after flipping would still read the
  /// old value.
  Future<void> move(bool fresh) {
    to = fresh;
    return fresh ? afterSources(Future.value()) : entryDelete();
  }

  /// A round begins (network change) — BEFORE call and query. The public address
  /// confirmed up to then no longer counts as current from here on.
  void roundStarts() {
    _roundsStart = DateTime.now();
    _publicBeforeRound = _k.publicAddress;
    answer?.networkChanged();
  }

  /// The edge "sources 1–3 done": [settled] ends with query AND
  /// call series. Does not throw.
  Future<void> afterSources(Future<void> settled) async {
    try {
      await settled;
      // §11.8a: after 1–3, before the entries — and independent of the switch
      // of source 4, which only concerns the relays.
      final ask = await answer?.toTheEdge() ?? 0;
      if (!to) return;
      final responding = _responding();
      final reported = _k.neighbourhood.all
          .where((n) =>
              !n.last.isBefore(_roundsStart) &&
              _k.readiness.knows(n.address, n.port))
          .length;
      final read = responding < Neighbourhood.atMost;
      lastRound = (
        responding: responding,
        reported: reported,
        answerAsk: ask,
        read: read
      );
      if (read) {
        await _read();
      } else {
        _report?.call('Source 4 not read: $responding responding '
            'neighbours (target ${Neighbourhood.atMost})');
      }
      await write();
    } on Object catch (e) {
      _report?.call('Source 4: round aborted: $e');
    }
  }

  /// Writes the own entry — if there is a reachable address
  /// AND the gate of §11.9 does not suppress it. Does not throw.
  ///
  /// Called at three places, and none of them is a clock on the
  /// data port: at the end of a round ([afterSources]), at the edge "own
  /// public address learned" (`Host.addressLearned`) and from the clock
  /// of §5.4 ([auffrischungStarten]).
  Future<void> write() async {
    if (!to) return;
    try {
      final addresses = _addresses();
      if (addresses.isEmpty) {
        _say(false, 'no reachable address — no own entry');
        return;
      }
      final now = nowSeconds();
      final inhibit = _gate(addresses, now);
      if (inhibit != null) {
        _say(false, inhibit);
        return;
      }
      final relay = _relay;
      if (relay.isEmpty) {
        _say(false, 'no relay known');
        return;
      }
      final event = entryEvent(
          AddressRecord(
              channel: cardChannel,
              node: _k.nodeIdentifier,
              addresses: addresses,
              expiry: now + kEntryLifetime),
          secret: _state.secret,
          now: now);
      final ok = await Future.wait([
        for (final r in relay) entryDeposit(r, event, report: _report)
      ]);
      final number = ok.where((x) => x).length;
      if (number > 0) _state.remember(addresses, now);
      _say(number > 0,
          '${addresses.join(', ')} at $number of ${relay.length} relays');
    } on Object catch (e) {
      _say(false, 'writing aborted: $e');
    }
  }

  /// §11.9, NIP-09: deletes the own entry at all known relays —
  /// for orderly leaving. The key stays; whoever
  /// comes back continues publishing under the same name. Does not throw.
  Future<void> entryDelete() async {
    try {
      if (_state.lastCreated == null) return;
      final relay = _relay;
      if (relay.isNotEmpty) {
        final event =
            deleteEvent(_state.secret, channel: cardChannel);
        final ok = await Future.wait([
          for (final r in relay) entryDeposit(r, event, report: _report)
        ]);
        _report?.call('Source 4: own entry withdrawn at '
            '${ok.where((x) => x).length} of ${relay.length} relay(s)');
      }
      _state.forget();
    } on Object catch (e) {
      _report?.call('Source 4: deletion aborted: $e');
    }
  }

  /// The addresses under which this node is reachable from outside — up to
  /// three, confirmed public ones first (§11.9, D2-8), own address family only (V1).
  List<CardAddress> _addresses() {
    final o = _k.publicAddress;
    return outsideAddresses(
            confirmed: identical(o, _publicBeforeRound) ? null : o,
            port: _k.port,
            interfaces: interfaces)
        .where((a) => _k.speaks(InternetAddress.fromRawAddress(a.address)))
        .toList();
  }

  /// `null` = write. Otherwise the reason why not (§11.9: byte-identical
  /// AND under 80 % of the validity elapsed — BOTH must apply).
  String? _gate(List<CardAddress> fresh, int now) {
    final created = _state.lastCreated;
    if (created == null) return null;
    if (!addressesEqual(fresh, _state.lastAddresses)) return null;
    final elapsed = now - created;
    // A clock set backwards does not fall into the gate: otherwise the
    // entry would expire without ever being refreshed.
    if (elapsed < 0) return null;
    if (elapsed * kRefreshDenominator >=
        kRefreshCounter * kEntryLifetime) {
      return null;
    }
    return 'unchanged, ${elapsed}s of $kEntryLifetime s '
        'elapsed (< $kRefreshCounter/$kRefreshDenominator)';
  }

  void _say(bool written, String reason) {
    lastSpelling = (written: written, reason: reason);
    _report?.call('Source 4 ${written ? 'written' : 'not '
        'written'}: $reason');
  }

  List<String> get _relay =>
      _k.knownRelay.take(kOutsideRelayAtMost).toList();

  Future<void> _read() async {
    final relay = _relay;
    if (relay.isEmpty) {
      _report?.call('Source 4: no relay known (neither configured nor '
          'from a card)');
      return;
    }
    final filter =
        entryFilter(cardChannel, limit: Neighbourhood.atMost);
    final answers = await Future.wait([
      for (final r in relay) entriesFetch(r, filter, report: _report)
    ]);
    final finds = <String, CardAddress>{};
    var own = 0;
    for (final ev in answers.expand((x) => x)) {
      // D2-6: the OWN entry still lies in the relay at the next start.
      // Behind NAT the published address stands on no own
      // interface, so `neighbourAdd` does not recognise it — the node
      // would enter itself as a neighbour. With the STABLE key
      // the comparison is a string comparison, and it holds even across
      // a restart (the node identifier does not, it is drawn anew
      // per start).
      if (ev['pubkey'] == _state.publicHex) {
        own++;
        continue;
      }
      final e = eventCheck(ev, cardChannel);
      if (e == null) continue;
      for (final a in e.addresses) {
        finds.putIfAbsent('$a', () => a);
      }
    }
    // S394 V1: no candidate of a family without socket — it takes a place.
    final taken = finds.values
        .where((a) => _k.speaks(InternetAddress.fromRawAddress(a.address)))
        .take(Neighbourhood.atMost)
        .toList();
    _report?.call('Source 4: ${relay.length} relay(s) read, '
        '${taken.length} address(es)'
        '${own > 0 ? ', $own own skipped' : ''}');
    for (final a in taken) {
      _neighbourRemember(a.address, a.port);
    }
    // The own public address can only be named by a counterpart outside the
    // segment — and a node that needs source 4 has nobody else to ask.
    final o = _k.publicAddress;
    if (o != null && !identical(o, _publicBeforeRound)) return;
    var asked = 0;
    for (final a in taken) {
      // ONLY IPv4: `OutsideRoute._onWhatIsMyAddress` rejects a packet from an
      // IPv6 address (`outside_route.dart`, "Karte kennt nur IPv4"). Asking via
      // IPv6 would cost a round trip that is never answered.
      if (a.kind != CardAddressType.ipv4) continue;
      final ip = InternetAddress.fromRawAddress(a.address);
      if (!fromOutsideReachable(ip)) continue;
      if (asked++ >= kOutsideAskAtMost) break;
      if (await _k.publicAddressLearn(ip, a.port) != null) break;
    }
  }
}
