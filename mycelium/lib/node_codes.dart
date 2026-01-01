/// Step 3 via codes at the node (V4.2 §8.1; proposal M, S391).
///
/// Here is wired what is built individually:
///
/// * the **forwarder** (`forward.dart`) — with the own codes,
///   the code table and the neighbours of this node;
/// * the **code table** (`code_table.dart`) — filled from the
///   registrations that arrive in the cover stream;
/// * the **registration** (`code_registration.dart`, `code_registrants.dart`) —
///   it travels in packets to EACH fixed neighbour (cover stream, keep-alive);
///   if the cover stream is stopped, it goes
///   out at the edges as a filler packet (§3.1);
/// * the **sender** — compute the code, ONE `0x20` for the fixed neighbours
///   of the recipient, inside ONE `0x22` to the own fixed neighbour
///   (`code_send.dart`: no node is both hops);
/// * the **route loss** — remember `0x21`, and if no receipt came from step 4 either
///   within [kRouteLossWindow], ONE `0x23` (at most one per
///   contact per [kSuchInterval]).
///
/// The mailboxes deliver via four callbacks what only they know
/// ([CodeRoute.inboundCodes], [CodeRoute.pairFrom], [CodeRoute.whereAreYouContent],
/// [CodeRoute.whereAreYouAccept]).
/// As long as nobody sets them, this node has no codes, and step 3
/// is dropped for every sending. Since S392 they are set in
/// `host_codes.dart` — there and only there, because only the host holds the node
/// AND all mailboxes. Two of them take the sending identity
/// along; the reasoning is at the fields.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/address.dart';
import 'package:mycelium/code_registration.dart';
import 'package:mycelium/code_registrants.dart';
import 'package:mycelium/code_table.dart';
import 'package:mycelium/card_address.dart';
import 'package:mycelium/code_send.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show hexFrom, shortFrom;
import 'package:mycelium/ladder.dart' show Shipment;
import 'package:mycelium/pair.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/split.dart' show kMaxPayload;
import 'package:mycelium/forward.dart';
import 'package:mycelium/forward_family.dart';

/// How long after a `0x21` a receipt (also from step 4) is
/// waited for before ONE `0x23` goes out.
const Duration kRouteLossWindow = Duration(seconds: 60);

/// At most one `0x23` per contact in this interval (§8.1).
const Duration kSuchInterval = Duration(hours: 1);

/// The largest content of a `0x23` — it is ONE part.
const int kSuchContentAtMost = kMaxPayload - 18;

/// `K_AB` and the contact's fixed neighbours as it last told them (§9.2).
typedef PairAnswer = ({Uint8List kAB, List<CardAddress> neighbours});

class CodeRoute {
  final Node _k;

  /// All inbound codes of all mailboxes on the UTC day.
  List<Uint8List> Function(int day) inboundCodes = (_) => const [];

  /// Pair secret and current fixed neighbours of a contact, asked for the
  /// SENDING identity [from]. Both arguments are required: `K_AB` depends on
  /// BOTH founding keys (§4.3); with only the contact the setter would guess
  /// the sending identity and, with more than one, deliver a silently WRONG
  /// code. The same rule as `Node.routesTo` (`host.dart`).
  PairAnswer? Function(Address contact, Address from) pairFrom =
      (_, __) => null;

  /// A `0x23` content that arrived under an own code: opened under `K_AB`,
  /// the sender's fixed neighbours remembered; `true` if it opened. Only the
  /// mailboxes know which contact sends under the code (`mailbox_pair.dart`).
  bool Function(Uint8List code, Uint8List content) whereAreYouAccept =
      (_, __) => false;

  /// The sealed content "my fixed neighbours" for a `0x23`, sealed BY the
  /// identity [from] to [contact] — [from] as with [pairFrom], and more
  /// compelling: the seal depends on `K_AB`; a guessed mailbox would seal
  /// under another identity's `K_AB`, the seal would not open, and two
  /// identities would be linked towards the contact.
  Uint8List? Function(Address contact, Address from) whereAreYouContent =
      (_, __) => null;

  /// Every packet of step 3 and every registration piece that arrives here
  /// ([out] `false`) or goes out — for probes and the statistics.
  void Function(Uint8List packet, bool out)? recording;

  /// Changeable ONLY for tests.
  DateTime Function() now = DateTime.now;
  Duration routeLossWindow = kRouteLossWindow;

  final CodeTable table;
  late final Forwarder forwarder;
  late final Registrants registrants =
      Registrants(() => Registrant(_ownAt, device: _k.devicesCode));

  final Map<int, Set<String>> _own = {};
  DateTime? _freshComputed;
  final Map<String, List<({Shipment s, Address to, Address from})>> _open = {};
  final Map<String, DateTime> _searched = {};
  final List<Timer> _clocks = [];

  /// Counters for probes and the network statistics — read only.
  int stepThreeSent = 0;
  int withoutCode = 0;
  int searchSent = 0;

  CodeRoute(this._k) : table = CodeTable(report: _k.report) {
    forwarder = Forwarder(
      isOwnCode: isOwnCode,
      codeSearch: table.who,
      registered: (a, port) => table.deviceAt(a, port) != null,
      neighbours: () => _k.neighbourhood.asEntries,
      isSelf: (a, port) => isSelf(_k, a, port),
      nextStep: (next, from, port) => familyStep(_k, next, from, port), // V5
      send: (p, target, port) =>
          _out(p, CardAddress(Uint8List.fromList(target.rawAddress), port)),
      onTarget: _onTarget,
      onSuchTarget: _onSuchTarget,
      onUnknown: _onUnknown,
      report: _k.report,
    );
    _k.coverStream
      ..registrationFor = _registrationFor
      ..registrationSent = _registrationOut
      ..onRegistration = _onRegistration;
    // A new fixed neighbour is an edge (§8.1): registration anew.
    _k.neighbourhood.observe(removed: (_) => edge(), onConfirmed: (_) => edge());
  }

  int get _today => utcDay(now());

  /// A packet of kinds `0x20`–`0x23` from the wire (`node_helpers.dart`).
  bool receive(Uint8List packet, InternetAddress from, int fromPort) {
    recording?.call(packet, false);
    return forwarder.receive(packet, from, fromPort);
  }

  void _out(Uint8List packet, CardAddress destination) {
    recording?.call(packet, true);
    _k.rawSend(packet, destination);
  }

  // ── Own codes ───────────────────────────────────────────────────────

  Set<String> _ownSet(int day) =>
      _own[day] ??= {for (final c in inboundCodes(day)) hexFrom(c)};

  Iterable<Uint8List> _ownAt(int day) => inboundCodes(day);

  /// Does [code] belong to a mailbox of this device (yesterday, today,
  /// tomorrow — for a skewed clock)?
  bool isOwnCode(Uint8List code) {
    final today = _today;
    _own.removeWhere((t, _) => t < today - 1 || t > today + 1);
    final h = hexFrom(code);
    bool search() => [today - 1, today, today + 1].any((t) => _ownSet(t).contains(h));
    if (search()) return true;
    // A new contact without a reported edge: recompute at most once per second.
    final t = now();
    final last = _freshComputed;
    if (last != null && t.difference(last) < const Duration(seconds: 1)) {
      return false;
    }
    _freshComputed = t;
    _own.clear();
    return search();
  }

  /// Edge of the mailboxes: a contact, an invitation was added or
  /// removed. Registers the whole list anew — NOW, not with the next cover
  /// packet: §15.2 wants a card's code at the neighbour before the card
  /// leaves the device, and a first contact's reply code must be there
  /// before the bundle comes back (S394: cover took 11 s; metered ~240 s).
  void codesChanged() {
    _own.clear();
    registrants.forget();
    edge(immediately: true);
  }

  /// The whole registration anew — even if nothing has changed (edge
  /// network change: the neighbour possibly sees a new address).
  void newRegister() {
    registrants.forget();
    edge();
  }

  // ── Registration ────────────────────────────────────────────────────

  /// Any address of any fixed NODE (S394 V4, §8.1 "each of its fixed
  /// neighbours") — the cover draws its first.
  Uint8List? _registrationFor((InternetAddress, int) target) => _issued =
      registrants.next(_k.neighbourhood.fixedNeighbours, target, _today);

  /// The piece [_registrationFor] last handed out — only for the report in
  /// [_registrationOut] (the cover stream asks and reports within ONE send
  /// operation). No state on which behaviour depends.
  Uint8List? _issued;

  /// A registration piece has left the wire. This place reports, and
  /// not [_registrationFor]: there it is also asked speculatively, here it is
  /// certain that it went out.
  void _registrationOut((InternetAddress, int) target) {
    final s = _issued;
    final a = s == null ? null : registrationRead(s);
    registrants.sent();
    _k.report('0x03 registration: piece ${a == null ? "?" : "${a.piece + 1}/${a.pieces}"} '
        'out to ${target.$1.address}:${target.$2} — day ${a?.day ?? "?"}, '
        '${a?.codes.length ?? 0} code(s), first '
        '${a == null || a.codes.isEmpty ? "-" : shortFrom(hexFrom(a.codes.first))}; '
        '${registrants.piecesSent} sent, ${registrants.pending} pending, '
        '${_ownSet(_today).length} own codes today');
  }

  void _onRegistration(Uint8List piece, InternetAddress from, int fromPort) {
    recording?.call(piece, false);
    final a = registrationRead(piece);
    if (a == null) {
      _k.report('Code registration from ${from.address}:$fromPort unreadable — discarded');
      return;
    }
    final taken = table.register(a.device, from, fromPort, a.day, a.codes);
    _k.report('0x03 registration from ${from.address}:$fromPort: piece '
        '${a.piece + 1}/${a.pieces} day ${a.day}, $taken/${a.codes.length} '
        'accepted, first '
        '${a.codes.isEmpty ? "-" : shortFrom(hexFrom(a.codes.first))}, '
        'table ${table.countCodes} code(s) / ${table.countDevices} '
        'device(s)');
  }

  /// An edge (list, day, fixed neighbours). If the cover stream is running,
  /// the registration travels with it; if it is stopped, it goes out NOW as
  /// filler to EACH fixed neighbour lacking it — delivery needs no cover (§3.1).
  void edge({bool immediately = false}) {
    if (_k.coverStream.runs && !immediately) return;
    final fixed = _k.neighbourhood.fixedNeighbours;
    for (final f in fixed) {
      for (var i = 0; i < 2 * kCodesPerDay ~/ kCodesPerPiece; i++) {
        if (registrants.next(fixed, (f.address, f.port), _today) == null) break;
        if (!_k.coverStream.fillSend((f.address, f.port))) break;
      }
    }
  }

  // ── Sender ──────────────────────────────────────────────────────────

  /// Code and the recipient's fixed neighbours for a sending from [from] to
  /// [to] — `null` if no pair secret is known.
  ({Uint8List code, List<CardAddress> neighbours})? codeFor(Address to, Address from) {
    final p = pairFrom(to, from);
    if (p == null) return null;
    return (
      code: pairCode(p.kAB, fromPk: from.ed25519Pk, toPk: to.ed25519Pk, day: _today),
      neighbours: p.neighbours,
    );
  }

  /// [underCodeSendTo] with the one neighbour a card names — the first
  /// contact (M1, §15.2) and its way back.
  void underCodeSend(Uint8List code, CardAddress neighbour, Uint8List packet) =>
      underCodeSendTo(code, [neighbour], packet);

  /// Sends [packet] under [code] to the recipient's fixed neighbours [next]
  /// — ONE `0x22` via the own fixed neighbour, without one directly (§8.1,
  /// the choice of the first hop: `code_send.dart`).
  void underCodeSendTo(Uint8List code, List<CardAddress> next, Uint8List packet) {
    final inside = Forwarder.build(code: code, content: packet);
    final n = _k.neighbourhood;
    final plan = stepThreePlan(
        fixed: n.fixedNeighbours,
        open: n.openSet(),
        recipient: next,
        contact: n.isContactDevice,
        speaks: (c) => _k.speaks(InternetAddress.fromRawAddress(c.address)));
    if (plan == null) {
      _k.report('Step 3: no next address this node can reach '
          '(${next.join(", ")}) — not sent (§11.1)');
      return;
    }
    final hop = plan.hop;
    stepThreeSent++;
    if (hop == null) {
      for (final a in plan.next) {
        _out(inside, a);
      }
    } else {
      _out(Forwarder.buildDetour(plan.next, inside), hop);
    }
    // AFTER sending (S392 B-3). THE funnel of every `0x20`/`0x22` of this
    // node; the code prefix is the one handle to join two logs (proposal M).
    _k.report('Step 3: ${plan.why} to ${plan.next.join(", ")}'
        '${hop == null ? "" : " (sent to $hop)"} '
        'under code ${shortFrom(hexFrom(code))} (${packet.length} B)');
  }

  /// Step 3 of the ladder: [code] missing → the step is dropped.
  void stepThree(Uint8List packet, List<CardAddress> next, Uint8List? code) {
    if (code == null) {
      withoutCode++;
      _k.report('Neighbour step without code — not sent');
      return;
    }
    underCodeSendTo(code, next, packet);
  }

  /// Remember a sending from [from] to [to] that waits for a receipt under
  /// [code].
  void shipmentRemember(Uint8List code, Shipment s, Address to, Address from) {
    _open.removeWhere((_, l) {
      l.removeWhere((e) => e.s.finished);
      return l.isEmpty;
    });
    _open.putIfAbsent(hexFrom(code), () => []).add((s: s, to: to, from: from));
  }

  // ── Reception ───────────────────────────────────────────────────────

  void _onTarget(Uint8List content, InternetAddress from, int fromPort) {
    if (content.isEmpty || kinds.isForward(content[0])) {
      _k.report('under own code: empty or nested content — discarded');
      return;
    }
    // Forwarded: `von` is the neighbour, not the sender.
    _k.feed(content, from, fromPort, withoutReturnRoute: true);
  }

  /// A `0x23` under an own code (§8.1). The content is NOT a
  /// message — it therefore does not go through [Node.feed] but
  /// to the mailboxes that hold `K_AB`.
  void _onSuchTarget(Uint8List code, Uint8List content) {
    final onto = whereAreYouAccept(code, content);
    _k.report('0x23 under own code ${shortFrom(hexFrom(code))} '
        '(${content.length} B): '
        '${onto ? "fixed neighbour of the sender adopted" : "seal does "
            "not open — discarded"}');
  }

  // ── Route loss ──────────────────────────────────────────────────────

  void _onUnknown(Uint8List code) {
    final l = _open.remove(hexFrom(code));
    final open = l?.where((e) => !e.s.finished).toList() ?? const [];
    if (open.isEmpty) {
      _k.report('0x21 for code ${shortFrom(hexFrom(code))} without open send — '
          'only noted');
      return;
    }
    final o = open.first;
    _k.report('0x21: the neighbour of ${shortFrom(hexFrom(o.to.identifier))} does not '
        'know the code — waiting ${routeLossWindow.inMilliseconds} ms for a receipt');
    late final Timer clock;
    clock = Timer(routeLossWindow, () {
      _clocks.remove(clock);
      if (open.any((e) => e.s.finished)) return;
      whereAreYou(o.to, o.from);
    });
    _clocks.add(clock);
  }

  /// ONE `0x23` to all neighbours — at most one per contact per
  /// [kSuchInterval]. `true` if it went out.
  bool whereAreYou(Address to, Address from) {
    final who = hexFrom(to.identifier);
    final last = _searched[who];
    final t = now();
    if (last != null && t.difference(last) < kSuchInterval) {
      _k.report('0x23 to ${shortFrom(who)} throttled (one per hour)');
      return false;
    }
    final code = codeFor(to, from)?.code;
    final content = whereAreYouContent(to, from);
    if (code == null || content == null || content.length > kSuchContentAtMost) {
      _k.report('0x23 to ${shortFrom(who)} not possible '
          '(${code == null ? "no code" : "no or too large content"})');
      return false;
    }
    _searched[who] = t;
    final packet = Forwarder.buildWhereAreYou(code: code, content: content);
    final all = _k.neighbourhood.asEntries;
    for (final n in all) {
      _out(packet, CardAddress(Uint8List.fromList(n.address.rawAddress), n.port));
    }
    searchSent += all.length;
    _k.report('0x23 to ${shortFrom(who)}: ${all.length} packet(s)');
    return true;
  }

  void stop() {
    for (final u in _clocks) {
      u.cancel();
    }
    _clocks.clear();
  }
}
