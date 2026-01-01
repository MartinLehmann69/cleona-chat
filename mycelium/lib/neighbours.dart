import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/wire_target.dart';
import 'package:mycelium/neighbours_listener.dart';
import 'package:mycelium/neighbours_channel.dart';
import 'package:mycelium/neighbours_packet.dart';

/// What the search can do and how it says so stands in `neighbours_channel.dart` —
/// passed on from here so that a caller imports only one name.
export 'package:mycelium/neighbours_channel.dart';

/// How often a call goes out.
///
/// Three, because two nodes never start at the same moment: whoever calls first
/// finds nobody as long as the other's listener (port 41341) is not yet
/// open. A single call that falls into this gap or gets lost as a UDP packet
/// means PERMANENTLY no neighbour — afterwards there is silence, and there is
/// nothing that catches up on it. Three calls cover the start offset of two
/// processes and survive two lost packets.
const int kCalls = 3;

/// Interval between two calls of a series.
///
/// An answer on the wire is there in under a millisecond as soon as both
/// sides are up — so the interval does not cover the running time but
/// the start offset. 300 ms times two yields a 600 ms window; that bridges
/// two separately started processes without a find coming noticeably
/// later.
const Duration kCallInterval = Duration(milliseconds: 300);

/// Find neighbours in the LAN — without any prior knowledge, in milliseconds.
///
/// [call] sends a series of [kCalls] packets with call code at an interval of
/// [kCallInterval] via multicast AND broadcast to port [_port]. **Afterwards there is
/// silence** — there is no clock, no follow-up, no polling. Whoever wants to repeat the
/// search calls [call] again; if a series is still running,
/// the call is folded into it and creates no second one.
///
/// Every neighbour that hears the call answers the sender directly via
/// unicast with a packet with answer code, its own DATA PORT and its
/// own identifier — to the port from which the call was actually sent.
///
/// **BOTH directions teach a neighbour.** Whoever receives an answer
/// reports the find via callback ([_onAnswer]) — and whoever hears a foreign call
/// reports the caller just the same ([_onCall]).
///
/// Until S384 only the answering side did this. And [call] depends on sending:
/// `node.dart` calls it when opening the ladder. So whoever never
/// sends themselves — a pure holder — never called, never got an answer and never learned
/// a neighbour. Measured in the field (S384, three nodes): a third
/// node stood permanently at `STATUS kontakte=0 nachbarn=0`, although the
/// two others had found it and it heard their calls. It could
/// thus forward nothing and could not get at its OWN mail,
/// because `Node.collect` asks exactly these neighbours. The call packet carries
/// identifier AND data port — the information was there all the time and was
/// thrown away.
///
/// **What this opens up, and what it costs.** A mere call now writes the
/// caller into the neighbourhood of every listener. The price is capped
/// and small: `neighbourhood.dart` holds at most 32 entries and
/// on overflow displaces the one silent longest, an entry is an
/// address and a port, and the call goes via multicast/broadcast — so only
/// whoever stands in the same segment hears it anyway. Two things are
/// nevertheless true and belong on the table at the next design: the
/// list is thus fillable from outside (32 calls with invented identifiers
/// displace every real neighbour), and it is NO measure of trust —
/// whoever ever makes it one must re-evaluate this place.
///
/// **The data port stands IN the packet** — why: `neighbours_packet.dart`.
///
/// This file keeps NO list of the neighbours found — every find goes
/// out immediately via callback and is forgotten afterwards. The list (and thus
/// also its cap) lies with the caller, today `node.dart`.
///
/// WHICH sockets exist and why is stated together with the measurement in
/// `neighbours_listener.dart`: [_listen] listens and answers, [_call] calls and
/// hears the answer, [_segment] proves that a search call came via group or
/// broadcast (F-7). The wire stays out of it — its public
/// interface offers neither group joining nor broadcast release.
class Neighbours {
  static final InternetAddress _group = InternetAddress('239.192.67.76');
  static final InternetAddress _broadcastCallTarget =
      InternetAddress('255.255.255.255');
  static const int _port = 41341;

  static const int _callCode = 0x52; // 'R'
  static const int _answerCode = 0x41; // 'A'

  /// Search call and find (call D, S385; signed since S388). The call port's own
  /// number space, not `kinds.dart`. Only whoever holds the
  /// sought identity answers, with its signature (`neighbours_packet.dart`).
  static const int _suchCode = 0x53; // 'S'
  static const int _findCode = 0x46; // 'F'

  /// The listener on [_port]. NULL if the port could not be had — then
  /// this node hears no calls, but keeps calling and receives answers
  /// (on [_call]). Why this is no abort (measured 14.09.2026, an
  /// occupied port paralysed the whole service): `smoke_neighbours.dart` case 11.
  final RawDatagramSocket? _listen;
  final RawDatagramSocket _call;

  /// The listeners that get ONLY segment-wide packets (group, broadcast) —
  /// the evidence for F-7. See `neighbours_listener.dart`. Can be empty; then
  /// no search call is answered, and that was said on opening.
  final List<RawDatagramSocket> _segment;
  final String _ownIdentifier;

  /// The port under which this node accepts data — [Wire.port],
  /// NOT [_port] and not the port of [_call]. It goes into every own
  /// packet, because the recipient cannot get it from anywhere else.
  final int _ownDataPort;
  final void Function(String identifier, InternetAddress address, int port)
      _found;

  /// What this instance can actually do. See [CallRoute].
  final CallRoute route;

  final void Function(String)? _report;

  Timer? _row;
  Completer<void>? _rowDone;
  bool _to = false;

  Sign? _sign; // `null` or return `null`: not answered
  OnFind? _onFind;
  // S391/W8: answer to the own call (confirmation), otherwise [_found].
  void Function(String, InternetAddress, int)? _onAnswerFind;

  /// Running searches per identifier, with their random value (only the first valid find).
  final Map<String, ({Timer clock, Uint8List random})> _search = {};

  Neighbours._(this._listen, this._call, this._segment, this._ownIdentifier,
      this._ownDataPort, this._found, this.route, this._report);

  /// Opens neighbours: binds port [_port] for incoming calls (group
  /// joined) and a port of its own for calling itself. [myIdentifier]
  /// and [dataPort] go into every own packet, [found] is called for every
  /// neighbour found (can fire several times on multiple reception)
  /// — with the neighbour's DATA PORT, not the sender port.
  ///
  /// [dataPort] is `Wire.port` of the own node — mandatory, because this
  /// file holds two sockets of its own and does not know the wire.
  ///
  /// If joining the group or the broadcast release fails, that does
  /// NOT throw — both sockets stay bound to the wildcard address, and
  /// the node continues with the remaining channel (ch07.md:39-42). What
  /// came out of it stands in [route] and is said via [report] (without
  /// [report] to stderr) — quietly being able to do less WITHOUT saying so is not allowed.
  ///
  /// [join]/[release] are for the probe; [onAnswer] gets the
  /// answers to the own call instead of [found] (S391, W8).
  static Future<Neighbours> open(
    String myIdentifier,
    void Function(String identifier, InternetAddress address, int port) found, {
    required int dataPort,
    void Function(String)? report,
    GroupJoin join = realGroupJoin,
    BroadcastRelease release = realBroadcastRelease,
    ListenerBinding listener = realListenerBinding,
    SegmentBinding segment = realSegmentBinding,
    Sign? sign,
    OnFind? onFind,
    void Function(String identifier, InternetAddress address, int port)? onAnswer,
  }) async {
    nodeIdCheck(myIdentifier); // BF-1: vor jedem Socket
    if (dataPort < 1 || dataPort > 0xFFFF) {
      throw ArgumentError('dataPort must be between 1 and 65535, was '
          '$dataPort — 0 means "not bound yet", and an address with '
          'port 0 is exactly the error the port field is meant to fix.');
    }
    final g = await listenerOpen(
        port: _port,
        group: _group,
        broadcastCall: _broadcastCallTarget,
        listener: listener,
        join: join,
        release: release,
        segment: segment,
        report: report);

    final n = Neighbours._(g.listen, g.call, g.segment, myIdentifier, dataPort,
        found, g.route, report)
      .._sign = sign
      .._onFind = onFind
      .._onAnswerFind = onAnswer;
    g.listen?.listen(n._onCall, onError: n._error); // B-1: otherwise process end
    g.call.listen(n._onAnswer, onError: n._error);
    for (final s in g.segment) {
      s.listen((e) => n._onSegmentCall(s, e), onError: n._error);
    }
    return n;
  }

  /// Sends out [kCalls] calls at interval [kCallInterval], then silence. The
  /// first goes immediately. If a series is already running, the call only returns its end:
  /// [call] hangs on every shipment (rest rule).
  ///
  /// THE END (S388) lies ONE interval after the last call — that long
  /// the answer to it has time. At it §11.8 reads sources 1–3 as done
  /// (`host_outside.dart`). No clock of its own: the same timer, one tick more.
  Future<void> call() {
    final running = _rowDone;
    if (_to || running != null) return running?.future ?? Future.value();
    final done = _rowDone = Completer<void>();
    _aCall();
    var left = kCalls;
    _row = Timer.periodic(kCallInterval, (t) {
      if (--left > 0) return _aCall();
      t.cancel();
      _row = null;
      _rowDone = null;
      done.complete();
    });
    return done.future;
  }

  /// The end of the running series — immediately if none is running.
  Future<void> get rowDone => _rowDone?.future ?? Future.value();

  /// Searches the identity [identifier] in the segment: [kCalls] search calls with ONE
  /// fresh random value at interval [kCallInterval], then silence. If a series is already running for this
  /// identifier, the call does nothing. A find goes to
  /// `onFind`; after the first accepted one the series ends.
  ///
  /// This is called ONLY when a shipment to a contact has no route
  /// (ladder step 1, S385 owner decision) — never on suspicion.
  void search(String identifier) {
    if (_to || _search.containsKey(identifier)) return;
    final random = suchRandom();
    final packet =
        callPacketWithField(_suchCode, _ownDataPort, random, identifier);
    _out(packet);
    var left = kCalls - 1;
    final clock = Timer.periodic(kCallInterval, (t) {
      if (left-- > 0) return _out(packet);
      t.cancel();
      _search.remove(identifier);
    });
    _search[identifier] = (clock: clock, random: random);
  }

  void _aCall() => _out(_packet(_callCode));

  /// A packet via group and/or broadcast, depending on [route].
  void _out(Uint8List packet) {
    if (_to) return;
    if (route == CallRoute.groupAndBroadcastCall || route == CallRoute.onlyGroup) {
      _send(packet, _group, 'Gruppe');
    }
    if (route == CallRoute.groupAndBroadcastCall || route == CallRoute.onlyBroadcastCall) {
      _send(packet, _broadcastCallTarget, 'Rundruf');
    }
  }

  /// A single throw. A send error (network just gone, interface
  /// changing) must not abort the running series — the next calls
  /// are there exactly for this case.
  ///
  /// The `catch` catches ONLY what goes wrong before the actual throw.
  /// Measured (S389): not a single operating system error comes synchronously out of
  /// `send`; they all come as error events and land in [_error].
  void _send(Uint8List packet, InternetAddress target, String what) {
    try {
      _call.send(packet, target, _port);
    } catch (e) {
      _report?.call('Neighbour search: call via $what did not go out ($e).');
    }
  }

  /// An answer to the one from whom the packet came. Its sender is
  /// unchecked foreign material: a packet with sender port 0 or a
  /// broadcast address as sender would CLOSE this socket on answering
  /// — permanently, in both directions (measured, S389,
  /// `wire_target.dart`). Then this node would never be found again.
  void _answer(RawDatagramSocket via, Uint8List packet, Datagram d) {
    final reason = impossibleTarget(d.address, d.port, packet.length);
    if (reason != null) {
      _report?.call('Neighbour search: no answer to ${d.address.address}:'
          '${d.port} — $reason');
      return;
    }
    via.send(packet, d.address, d.port);
  }

  /// Measured (S389): after such an event this socket is dead — it
  /// no longer sends and no longer receives (open finding N-3).
  void _error(Object e) => _report?.call('Neighbour search: socket error ($e) — '
      'this socket accepts nothing more afterwards.');

  /// Whether this node can HEAR calls. `false` means: it still finds
  /// others, but is not found itself.
  bool get audible => _listen != null;

  void _onCall(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final listen = _listen;
    if (listen == null) return;
    final d = listen.receive();
    if (d == null) return;
    // F-7: a search call is never answered HERE. This listener hangs on the
    // wildcard address and also gets what someone from outside the
    // segment sends here via unicast — the amplifier. What came via group
    // or broadcast lies identically at [_segment] and is
    // answered there. Reasoning and measurement: `neighbours_listener.dart`.
    if (d.data.isNotEmpty && d.data[0] == _suchCode) return;
    final read = callPacketRead(d.data, _callCode);
    if (read == null) return; // broken or foreign kind -> gone
    if (read.$1 == _ownIdentifier) return; // own call, no echo

    // First answer, then learn. The answer is the ONLY opportunity
    // for the other side to find us; it must not depend on what
    // our own caller does with the find (the callback goes to
    // `node_call.dart` and from there on into neighbourhood and cover stream).
    _answer(listen, _packet(_answerCode), d);

    // And now the find. `read.$2` is the data port from the CALL packet,
    // not `d.port`: `d.port` is the sender's call socket, which accepts
    // nothing — the same error as over there in [_onAnswer], only from
    // the other side. See the header of this file, section "both
    // directions".
    _found(read.$1, d.address, read.$2);
  }

  /// A packet that went to the group or the broadcast — and only such
  /// a one: [_segment] hangs on exactly these addresses (F-7, measured in
  /// `neighbours_listener.dart`). Evidence, not a word in the packet.
  ///
  /// Only the holder of the identifier answers, signed; all others
  /// discard silently. Answering happens via [_listen] — a socket at the
  /// group address carries it as sender.
  void _onSegmentCall(RawDatagramSocket s, RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final d = s.receive();
    if (d == null) return;
    if (d.data.isEmpty || d.data[0] != _suchCode) return; // Ruf: [_beiRuf]
    final listen = _listen;
    if (listen == null) return;
    final f = callPacketWithFieldRead(d.data, _suchCode, kSuchRandomLength);
    final z = f == null
        ? null
        : _sign?.call(
            f.identifier, findData(f.field, f.identifier, _ownDataPort));
    if (f == null || z == null) return;
    _answer(listen,
        callPacketWithField(_findCode, _ownDataPort, z, f.identifier), d);
  }

  void _onAnswer(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final d = _call.receive();
    if (d == null) return;
    if (d.data.isNotEmpty && d.data[0] == _findCode) {
      // Only for a running search. FIRST check, then end: if
      // an invalid find ended the search, the first forger would displace the
      // real one. It is signed against the random value of THIS search (proposal C).
      final f = callPacketWithFieldRead(d.data, _findCode, kFindSignatureLength);
      final s = f == null ? null : _search[f.identifier];
      if (f == null || s == null) return;
      final data = findData(s.random, f.identifier, f.dataPort);
      if (_onFind?.call(f.identifier, d.address, f.dataPort, data, f.field) !=
          true) {
        return;
      }
      _search.remove(f.identifier)?.clock.cancel();
      return;
    }
    final read = callPacketRead(d.data, _answerCode);
    if (read == null) return; // broken or foreign kind -> gone
    if (read.$1 == _ownIdentifier) return; // own answer, no echo
    // read.$2 and NOT d.port: d.port is the sender port of the
    // answer packet, thus always _port (41341) — the call port on which the
    // neighbour accepts nothing. See the header of this file.
    (_onAnswerFind ?? _found)(read.$1, d.address, read.$2);
  }

  /// An own packet with [code] — layout in `neighbours_packet.dart`.
  Uint8List _packet(int code) =>
      callPacket(code, _ownDataPort, _ownIdentifier);

  void close() {
    _to = true;
    _row?.cancel();
    _row = null;
    final f = _rowDone; // whoever waits for the end does not hang
    _rowDone = null;
    if (f != null && !f.isCompleted) f.complete();
    for (final t in _search.values) {
      t.clock.cancel();
    }
    _search.clear();
    _listen?.close();
    for (final s in _segment) {
      s.close();
    }
    _call.close();
  }
}
