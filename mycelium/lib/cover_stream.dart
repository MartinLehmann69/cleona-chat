import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/address_entries.dart'
    show AddressList, kAddressEntriesAtMost, kOwnEntriesAtMost;
import 'package:mycelium/wire.dart' show PacketRoute;
import 'package:mycelium/shell_start.dart' show kShellSize;
import 'package:mycelium/cover_stream_content.dart';

/// The cover stream (§5).
///
/// Principle (§3.1): delivery works on its own, cover runs
/// alongside. This class gets a function for sending and otherwise holds
/// NOTHING of the send path of real packets — no look into a queue,
/// no coupling to ladder, splitter or wire. Whoever stops it changes
/// nothing about real traffic, because it was never connected to it.
///
/// ── ALWAYS ON (§5.1, W3) ──────────────────────────────────────────────────
///
/// The node starts the stream at start and only stops it on stopping
/// (`node.dart`): "always" means as long as the node runs — on
/// Android in the foreground service, on the desktop as long as the daemon runs,
/// on iOS as long as the app runs. Until S391 it was never started.
/// [stop] stays for the test clause of §3.1 (probe, test build).
///
/// ── CLOCK (§5.2) ──────────────────────────────────────────────────────────
///
/// A Poisson process, exponentially distributed intervals — NO fixed
/// spacing. A fixed clock could be separated out again from the sum of cover stream and real
/// traffic by subtraction. Exponentially distributed
/// intervals are memoryless; therefore a change of the rate
/// (network edge) may discard the running draw and draw anew, without
/// distorting the distribution.
///
/// Mean [kMeanWlan] in W/LAN, [kMeanMetered] in the metered network
/// (§5.3; W1: metered is what the operating system says — set via
/// [metered] at every network edge).
///
/// ── TARGETS (§5.2) ─────────────────────────────────────────────────────────
///
/// From the open set — at most [kOpenSetAtMost] neighbours,
/// drawn uniformly. The set is delivered by [targets]; as long as nobody sets it,
/// the list from [neighboursSet] applies (fallback until the
/// wiring, capped to the same maximum).
///
/// ── CONTENT (§5.5, W4) ────────────────────────────────────────────────────
///
/// A drawn packet carries, in this order of checking:
/// a piece of the code registration, if the target is the fixed neighbour and
/// [registrationFor] yields one (§8.1, S391); otherwise address entries, if the addresses have changed since the last packet to
/// THIS target; otherwise an update piece, if
/// [nextPiece] yields one; otherwise filling. No content ever creates
/// a send time of its own (§5.5 rule 1).
///
/// ── FEWER EMPTY PACKETS (§5.1) ──────────────────────────────────────────
///
/// [emptyReduce], default off: in the UNMETERED network a
/// drawn packet without content is skipped. In the metered network the option never applies
/// — there the rate is lowered, not the filling.
///
/// Size: every packet is [kCoverPayload] B payload and after the shell
/// [kCoverPacketSize] B on the wire — like a full part packet.

/// A neighbour: only its network address.
typedef Neighbour = (InternetAddress address, int port);

/// Sends a packet to a neighbour — in operation `Shell.sendCover`.
/// `false` means: not gone out (no key yet) — then the
/// content also counts as not delivered.
typedef Send = bool Function(Uint8List packet, Neighbour target);

/// Packet size on the wire (from `shell_start.dart`, not written a second time).
const int kCoverPacketSize = kShellSize;

/// No interval between two cover packets goes below this (§5.2).
const Duration kMinInterval = Duration(milliseconds: 200);

/// `R_cover` (§5.2): one packet per 8 s — 12,96 MB/day.
const Duration kMeanWlan = Duration(seconds: 8);

/// The mean in the METERED network. Owner decision W2 = b (17.09.2026):
/// 60 s, i.e. 1200 B × 86400 / 60 = 1.728 MB/day. The number stands only here.
const Duration kMeanMetered = Duration(seconds: 60);

/// Size of the open set (§5.2: "open set | 4 neighbours").
const int kOpenSetAtMost = 4;

class CoverStream {
  final Send _send;
  final Random _random;

  Duration _meanWlan;
  Duration _meanMetered;
  bool _metered = false;
  List<Neighbour> _neighbours = const [];
  bool _runs = false;
  Timer? _next;

  /// What last went to a target in addresses — one fingerprint per target.
  final Map<String, String> _entriesTo = {};

  /// The open set (§5.2). Set by the node; wins over
  /// [neighboursSet].
  List<Neighbour> Function()? targets;

  /// What address entries should travel along to [target] (§5.5): FIRST the
  /// own addresses, one per address family this node speaks, the one in
  /// the target's family as the target sees this node (S394 V2); then the
  /// confirmed neighbours.
  AddressList Function(Neighbour target)? entries;

  /// An update piece, drawn randomly by the holder (§5.5 rule 2), or
  /// `null`. At most [kPieceAtMost] B.
  Uint8List? Function()? nextPiece;

  /// Received address entries — the sender's own addresses (joined into one
  /// neighbour, `neighbourhood_join.dart`) and candidates for the
  /// neighbourhood, none of which is believed (§11.9).
  void Function(AddressList l, InternetAddress from, int fromPort)? onEntries;

  /// A received update piece (§5.5 rule 4: never passed on as a packet
  /// of its own).
  void Function(Uint8List piece, InternetAddress from, int fromPort)? onPiece;

  /// The next piece of the code registration for [target] — not `null` only for the
  /// fixed neighbour (`node_codes.dart`). If it goes out,
  /// [registrationSent] follows. [fillSend] asks too: the
  /// keep-alive carries the registration along (§3.1 — it does not depend solely
  /// on this stream).
  Uint8List? Function(Neighbour target)? registrationFor;
  void Function(Neighbour target)? registrationSent;

  /// A received code registration. [from]:[fromPort] is the address under
  /// which the device is sending AT THE MOMENT — WHICH device it is is said solely by the
  /// device code in the piece (§8.1, S392; `code_registration.dart`).
  void Function(Uint8List piece, InternetAddress from, int fromPort)?
      onRegistration;

  /// A received keep-alive (§8.1): device code 16 B + token 8 B, read by
  /// the fixed neighbour (`mapping_echo.dart`).
  void Function(Uint8List content, InternetAddress from, int fromPort)?
      onKeepAlive;

  /// Counters for probes and the network statistics (§5.6, §25) — read only.
  int sent = 0;
  int sentRegistration = 0;
  int sentFill = 0;
  int sentPiece = 0;
  int sentEntries = 0;

  /// Drawn points in time that were dropped for lack of content ([emptyReduce]).
  int skipped = 0;

  /// Received, valid cover packets (empty payloads never reach the
  /// switch — the shell already discards them).
  int receive = 0;

  /// [random] only for probes (fixed intervals and filling); in
  /// operation it stays with the cryptographically secure default.
  CoverStream(this._send,
      {Duration mean = kMeanWlan,
      Duration meanMetered = kMeanMetered,
      Random? random})
      : _meanWlan = _checked(mean),
        _meanMetered = _checked(meanMetered),
        _random = random ?? Random.secure();

  static Duration _checked(Duration mean) {
    if (mean <= Duration.zero) {
      throw ArgumentError('mean interval must be positive: $mean');
    }
    return mean;
  }

  bool get runs => _runs;
  bool get metered => _metered;

  /// The mean that applies NOW.
  Duration get mean => _metered ? _meanMetered : _meanWlan;

  /// Is a draw without content skipped? Only in the unmetered network.
  bool get reduced => emptyReduce && !_metered;

  /// Set at every network edge (W1).
  set metered(bool value) {
    if (value == _metered) return;
    _metered = value;
    _newPlan();
    onMetered?.call(); // an edge for the contact seats (§8.1)
  }

  /// The metered flag changed — set by the host network.
  void Function()? onMetered;

  /// The setting "fewer empty packets in W/LAN" (default off).
  bool emptyReduce = false;

  /// Fallback targets as long as [targets] is not set.
  void neighboursSet(List<Neighbour> neighbours) {
    _neighbours = List.unmodifiable(neighbours);
  }

  /// Sets the means — for probes that cannot wait seconds.
  void rateSet(Duration mean, {Duration? metered}) {
    _meanWlan = _checked(mean);
    if (metered != null) _meanMetered = _checked(metered);
    _newPlan();
  }

  void start() {
    if (_runs) return;
    _runs = true;
    _plan();
  }

  void stop() {
    _runs = false;
    _next?.cancel();
    _next = null;
  }

  /// The switch for receiving: set between shell and splitter
  /// (`node.dart`). It only branches off what the splitter would discard anyway.
  PacketRoute coverSwitch(PacketRoute bottom) => CoverSwitch(bottom, receiveCover);

  /// A cover packet with content byte has arrived.
  void receiveCover(Uint8List payload, InternetAddress from, int fromPort) {
    final t = coverPayloadRead(payload);
    if (t == null) return;
    receive++;
    final e = t.entries;
    if (e != null && !e.isEmpty) onEntries?.call(e, from, fromPort);
    final s = t.piece;
    if (s != null && s.isNotEmpty) onPiece?.call(s, from, fromPort);
    final a = t.registration;
    if (a != null && a.isNotEmpty) onRegistration?.call(a, from, fromPort);
    final o = t.keepAlive;
    if (o != null) onKeepAlive?.call(o, from, fromPort);
  }

  void _newPlan() {
    if (!_runs) return;
    _next?.cancel();
    _plan();
  }

  void _plan() {
    _next = Timer(meantime(mean, _random), () {
      if (!_runs) return;
      draw();
      _plan();
    });
  }

  /// The open set as it applies NOW.
  List<Neighbour> get openSet {
    final m = targets?.call() ?? _neighbours;
    return m.length <= kOpenSetAtMost
        ? m
        : m.sublist(0, kOpenSetAtMost);
  }

  /// ONE drawn point in time: choose target, choose content, send or
  /// (only with [reduced]) skip. Public so that probes can check the
  /// selection without real time. `true` if something was sent.
  bool draw() {
    final currentSet = openSet;
    if (currentSet.isEmpty) return false;
    final target = currentSet[_random.nextInt(currentSet.length)];
    final open = {for (final n in currentSet) _who(n)};
    _entriesTo.removeWhere((k, _) => !open.contains(k));

    Uint8List? payload;
    final list = _entriesNow(target);
    final fingerprint = _fingerprint(list);
    var entriesIncluded = false;
    final registration = registrationFor?.call(target);
    if (registration != null) {
      payload = _withRegistration(registration);
    } else if (!list.isEmpty && _entriesTo[_who(target)] != fingerprint) {
      payload = coverPayloadBuild(kContentEntries, _random, entries: list);
      entriesIncluded = true;
    } else {
      final s = nextPiece?.call();
      if (s != null && s.isNotEmpty && s.length <= kPieceAtMost) {
        payload = coverPayloadBuild(kContentPiece, _random, piece: s);
        sentPiece++;
      }
    }
    if (payload == null) {
      if (reduced) {
        skipped++;
        return false;
      }
      payload = coverPayloadBuild(kContentFill, _random);
      sentFill++;
    }
    // The shell never lifts cover (E3): if the packet did not go out,
    // the fingerprint stays open and the entries travel with the next
    // packet to this target.
    if (!_send(payload, target)) return false;
    _lastTo[_who(target)] = DateTime.now();
    if (registration != null) _registrationOut(target);
    if (entriesIncluded) {
      _entriesTo[_who(target)] = fingerprint;
      sentEntries++;
    }
    sent++;
    return true;
  }

  final Map<String, DateTime> _lastTo = {};

  /// When a packet of this stream last WENT OUT to [target] — for the
  /// keep-alive (§8.1), which is dropped where cover has already refreshed
  /// the path.
  DateTime? lastTo(Neighbour target) => _lastTo[_who(target)];

  /// ONE fill packet to [target], outside the clock — the keep-alive (§8.1)
  /// thus looks like cover on the wire. Independent of whether the
  /// stream runs. `true` if it went out.
  /// Carries a piece of the code registration if one is pending for [target].
  bool fillSend(Neighbour target) {
    final registration = registrationFor?.call(target);
    final payload = registration != null
        ? _withRegistration(registration)
        : coverPayloadBuild(kContentFill, _random);
    if (!_send(payload, target)) return false;
    _lastTo[_who(target)] = DateTime.now();
    if (registration != null) _registrationOut(target);
    return true;
  }

  /// ONE keep-alive to [target] (§8.1): content `0x04` with [content]
  /// (device code + token) — or the pending registration piece, which the
  /// neighbour follows the same way. `true` if it went out.
  bool keepAliveSend(Neighbour target, Uint8List content) {
    final registration = registrationFor?.call(target);
    final payload = registration != null
        ? _withRegistration(registration)
        : coverPayloadBuild(kContentKeepAlive, _random, piece: content);
    if (!_send(payload, target)) return false;
    _lastTo[_who(target)] = DateTime.now();
    if (registration != null) _registrationOut(target);
    return true;
  }

  Uint8List _withRegistration(Uint8List a) =>
      coverPayloadBuild(kContentRegistration, _random, piece: a);

  void _registrationOut(Neighbour target) {
    sentRegistration++;
    registrationSent?.call(target);
  }

  static String _who(Neighbour n) => '${n.$1.address}:${n.$2}';

  AddressList _entriesNow(Neighbour target) {
    final l = entries?.call(target) ?? const AddressList();
    return AddressList(
        own: l.own.take(kOwnEntriesAtMost).toList(),
        neighbours: l.neighbours.take(kAddressEntriesAtMost).toList());
  }

  /// Only the addresses count, not the age — otherwise every minute would count
  /// as a change, and every packet would carry entries instead of pieces.
  static String _fingerprint(AddressList l) => [
        for (final p in [l.own, l.neighbours])
          (p.map((e) => '${e.address}').toList()..sort()).join(',')
      ].join('|');
}

/// Exponentially distributed interval with mean [mean], bounded below
/// at [kMinInterval]. Inversion method: for u in (0, 1],
/// -ln(u) * mean is exponentially distributed with exactly this mean. Pure
/// (no passage of time, no state), so that the distribution can be checked without real
/// seconds.
Duration meantime(Duration mean, Random random) {
  final u = 1.0 - random.nextDouble(); // (0, 1], excludes 0
  final micro = -log(u) * mean.inMicroseconds;
  final drawn = Duration(microseconds: micro.round());
  return drawn < kMinInterval ? kMinInterval : drawn;
}
