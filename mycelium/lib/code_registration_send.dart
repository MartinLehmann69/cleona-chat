/// Sending the code registration to a fixed neighbour and its answer
/// (V4.2 §8.1 "How a node learns codes", §11.3a, §11.6; F-B, owner decision
/// 06.10.2026).
///
/// ── WHY ─────────────────────────────────────────────────────────────────
///
/// Field test 06.10.2026, phone WLAN -> LTE: the first-contact reply code
/// went to the fixed neighbour only under its first remembered address —
/// the old private WLAN address — inside a cover packet nobody answered. It
/// arrived 11 s later with a later cover packet, and the issuer's answer
/// reached the neighbour 1 s before the code ("code … not registered here —
/// 0x21"). The norm has the registration in packets of its own, each
/// answered; this file is that.
///
/// ── WHAT HAPPENS ────────────────────────────────────────────────────────
///
/// * At an edge every piece goes as one `0x24` to the fixed neighbour's
///   first address in a family this node speaks (§11.1).
/// * The neighbour answers each with `0x25` (day, piece). That answer
///   confirms the address it came from (§11.8 "every packet that expects an
///   answer confirms the entry"); the confirmation puts that address first,
///   so later sendings go there.
/// * A piece without `0x25` is a packet without an answer like any other:
///   the transport repeats it and, when it and its repeats stay silent,
///   declares that address failed and sends it to the next address of the
///   same neighbour the same way (§11.3a, `silence.dart` — the WLAN -> LTE
///   case). Nothing is repeated, counted or timed here; until S407 this file
///   had its own "one second attempt".
///
/// No clock runs between edges. The UTC day change is an edge of §8.1;
/// [UtcDayEdge] fires once at the day's end and arms itself for the next one.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/code_registration.dart';
import 'package:mycelium/neighbour.dart';
import 'package:mycelium/card_address.dart';
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;
import 'package:mycelium/silence.dart';

/// The pieces of one edge to one fixed neighbour that wait for `0x25`.
class _Round {
  /// `day/piece` -> the piece, while it waits for its `0x25`.
  final Map<String, Uint8List> open;

  /// `day/piece` -> the answer its request waits for (`silence.dart`).
  final Map<String, Completer<void>> answers = {};

  /// `address:port` each sending of this round went to — a `0x25` from any
  /// of them answers it.
  final Set<String> sentTo = {};

  /// Who waits for the piece carrying a code ([RegistrationSend.whenRegistered]).
  final List<_Waiter> waiters = [];
  _Round(this.open);

  bool carries(Uint8List code) => open.values.any((p) => _holds(p, code));
}

typedef _Waiter = (Uint8List code, void Function(CardAddress? answered) then);

bool _holds(Uint8List piece, Uint8List code) =>
    registrationRead(piece)?.codes.any((c) => _same(c, code)) ?? false;

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _keyOf(int day, int piece) => '$day/$piece';

class RegistrationSend {
  /// Sends one packet; its future says how the sending ended (`SendEnd`).
  final FutureOr<Object?> Function(Uint8List packet, CardAddress destination) _out;

  /// The fixed neighbour with this [Neighbour.id] as it stands NOW — `null`
  /// if it is gone.
  final Neighbour? Function(int id) _neighbour;
  final bool Function(InternetAddress a) _speaks;

  /// Where a piece is repeated and given up (§11.3a).
  final Silence _silence;

  /// The confirmation of an address that answered (`Neighbourhood.confirm`).
  final void Function(InternetAddress a, int port) _confirm;
  final void Function(String) _report;

  /// A fixed neighbour named its record key in its `0x25` (S407 a').
  void Function(CardAddress by, Uint8List key)? onRecordKey;

  /// By [Neighbour.id].
  final Map<int, _Round> _rounds = {};

  /// The address that last answered a `0x25`, by [Neighbour.id].
  final Map<int, CardAddress> _answeredBy = {};

  /// The codes a `0x25` confirmed, by [Neighbour.id]: code -> its day. The
  /// neighbour keeps a code until the end of the day after its day (§8.1).
  final Map<int, Map<String, int>> _held = {};

  /// Counters for probes and the network statistics — read only. The repeats
  /// are counted where they happen ([Silence.repeated]).
  int sent = 0;
  int answered = 0;
  int unanswered = 0;

  RegistrationSend(this._out,
      {required Neighbour? Function(int id) neighbour,
      required bool Function(InternetAddress a) speaks,
      required Silence silence,
      required void Function(InternetAddress a, int port) confirm,
      required void Function(String) report})
      : _neighbour = neighbour,
        _speaks = speaks,
        _silence = silence,
        _confirm = confirm,
        _report = report;

  /// The pieces of an edge for [n]. A round still open for [n] is
  /// superseded: its pieces belong to a list that has changed.
  void send(Neighbour n, List<Uint8List> pieces) {
    if (pieces.isEmpty) return;
    final to = n.addresses.where((a) => _speaks(a.address)).firstOrNull;
    if (to == null) {
      _report('0x24 registration: ${n.key} has no address in a family this '
          'node speaks — not sent (§11.1)');
      return;
    }
    final old = _rounds.remove(n.id);
    old?.answers.values.where((a) => !a.isCompleted).forEach((a) => a.complete());
    final r = _Round({
      for (final p in pieces)
        _keyOf(pieceKey(p).day, pieceKey(p).piece): p
    });
    _rounds[n.id] = r;
    sent += r.open.length;
    for (final MapEntry(:key, value: p) in r.open.entries) {
      _ask(r, n.id, key, p, to);
    }
    for (final w in old?.waiters ?? const <_Waiter>[]) {
      r.carries(w.$1) ? r.waiters.add(w) : w.$2(_answeredBy[n.id]);
    }
  }

  /// One piece as a request that expects its `0x25` (§11.3a).
  void _ask(_Round r, int id, String key, Uint8List p, NeighbourAddress to) {
    final answer = r.answers[key] = Completer<void>();
    final a = registrationRead(p);
    final what = 'piece ${a == null ? "?" : "${a.piece + 1}/${a.pieces}"}';
    unawaited(_silence
        .ask(answer.future,
            to: to.address,
            port: to.port,
            send: (ip, port) {
              final at = '${ip.address}:$port';
              r.sentTo.add(at);
              _report('0x24 registration: $what out to $at — day '
                  '${a?.day ?? "?"}, ${a?.codes.length ?? 0} code(s), first '
                  '${a == null || a.codes.isEmpty ? "-" : _short(a.codes.first)}');
              return _out(registrationPacket(p),
                  CardAddress(Uint8List.fromList(ip.rawAddress), port));
            },
            cancelled: () => !identical(_rounds[id], r),
            what: '0x24 registration $what')
        .then((_) => _askEnded(r, id, key)));
  }

  /// The request for [key] has ended — answered ([answer] took the piece out
  /// of [_Round.open]) or silent at every address of the neighbour.
  void _askEnded(_Round r, int id, String key) {
    if (!identical(_rounds[id], r)) return; // superseded: its waiters moved on
    final piece = r.open.remove(key);
    if (piece != null) {
      unanswered++;
      final n = _neighbour(id);
      if (n == null) _held.remove(id);
      _report('0x24 registration: a piece without 0x25 at every address'
          '${n == null ? " — the neighbour is gone" : ""}; no more until the '
          'next edge (§8.1)');
      final done = [for (final w in r.waiters) if (_holds(piece, w.$1)) w];
      r.waiters.removeWhere(done.contains);
      for (final w in done) {
        w.$2(null);
      }
    }
    if (r.open.isEmpty) _rounds.remove(id);
  }

  /// §15.5 "The way back for the bundle": [then] runs once the piece to [n]
  /// that carries [code] is answered by `0x25` — with the address that
  /// answered —, or once that piece and its repeats stayed unanswered at
  /// every address (`null`). At once if no piece carrying [code] waits for [n].
  void whenRegistered(Neighbour n, Uint8List code,
      void Function(CardAddress? answered) then) {
    final r = _rounds[n.id];
    if (r == null || !r.carries(code)) {
      then(_answeredBy[n.id]);
      return;
    }
    r.waiters.add((code, then));
  }

  /// Whether [n] confirmed holding [code] with a `0x25` (§8.1) — what §15.2
  /// asks of an invitation's code before its invitation data leave the device
  /// (§12.4, `invitation_way_in.dart`).
  bool holds(Neighbour n, Uint8List code) =>
      _held[n.id]?.containsKey(_codeKey(code)) ?? false;

  static String _codeKey(Uint8List c) => String.fromCharCodes(c);

  void _hold(int id, Uint8List piece) {
    final a = registrationRead(piece);
    if (a == null) return;
    final held = _held[id] ??= {};
    held.removeWhere((_, day) => day < a.day - 1);
    for (final c in a.codes) {
      held[_codeKey(c)] = a.day;
    }
  }

  /// The address of [n] a first-contact request names (§15.5): the one that
  /// answered this node's last `0x25` — the address under which [n] surely
  /// holds this device's codes —, unless that is not reachable from outside
  /// while [n]'s card address is: a stranger cannot reach a private address.
  CardAddress namedAddress(Neighbour n) {
    final card = n.asCardAddress;
    final a = _answeredBy[n.id];
    if (a == null || !n.has(_ip(a), a.port)) return card;
    final outside = fromOutsideReachable(_ip(card));
    // The issuer reads this address from elsewhere: a private one it cannot reach.
    return outside && !fromOutsideReachable(_ip(a)) ? card : a;
  }

  static InternetAddress _ip(CardAddress c) =>
      InternetAddress.fromRawAddress(Uint8List.fromList(c.address));

  /// A `0x25` from [from]:[port]. Only the answer to a piece this node sent
  /// to exactly that address counts — and confirms it (W8); anything else
  /// is discarded. `true` if it answered a piece.
  bool answer(Uint8List packet, InternetAddress from, int port) {
    final a = registeredRead(packet);
    final at = '${from.address}:$port';
    if (a == null) {
      _report('0x25 from $at unreadable — discarded');
      return false;
    }
    final key = _keyOf(a.day, a.piece);
    for (final e in _rounds.entries) {
      final r = e.value;
      if (!r.sentTo.contains(at)) continue;
      final piece = r.open.remove(key);
      if (piece == null) continue;
      answered++;
      final by = CardAddress(Uint8List.fromList(from.rawAddress), port);
      _answeredBy[e.key] = by;
      _hold(e.key, piece); // before [_confirm]: its listeners read [holds]
      final done = [for (final w in r.waiters) if (_holds(piece, w.$1)) w];
      r.waiters.removeWhere(done.contains);
      final wait = r.answers[key];
      if (wait != null && !wait.isCompleted) wait.complete();
      _report('0x25 registered from $at: day ${a.day} piece ${a.piece + 1}, '
          '${r.open.length} piece(s) still open');
      _confirm(from, port); // its listeners may start the next edge
      final rk = a.recordKey;
      if (rk != null) onRecordKey?.call(by, rk);
      for (final w in done) {
        w.$2(by);
      }
      return true;
    }
    _report('0x25 from $at for day ${a.day} piece ${a.piece + 1} answers no '
        'open piece — discarded');
    return false;
  }

  void stop() {
    for (final r in _rounds.values) {
      r.answers.values.where((a) => !a.isCompleted).forEach((a) => a.complete());
    }
    _rounds.clear();
  }
}

/// The edge "the UTC day changes" (§8.1): fires once just after the day's
/// end and arms itself for the next. One timer, one firing per day — the
/// registration of today and tomorrow is then rebuilt and sent.
class UtcDayEdge {
  final void Function() _onDay;
  final DateTime Function() _now;
  Timer? _clock;

  UtcDayEdge(this._onDay, this._now);

  /// Arms the timer if it does not run.
  void arm() {
    if (_clock != null) return;
    final u = _now().toUtc();
    final end = DateTime.utc(u.year, u.month, u.day + 1);
    _clock = Timer(end.difference(u) + const Duration(seconds: 1), () {
      _clock = null;
      _onDay();
      arm();
    });
  }

  void stop() {
    _clock?.cancel();
    _clock = null;
  }
}

String _short(Uint8List b) =>
    b.take(4).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
