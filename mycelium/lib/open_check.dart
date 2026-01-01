/// The device's half of the open check (V4.2 §8.1 "Is the family open?",
/// proposal 24.09.2026 3b/6.11): is an address family of this node open
/// from outside, without state in a translator or firewall?
///
/// A global IPv6 address says nothing about a firewall (§11.8a), and no
/// carrier documents one. So the node checks, per family, at the edges of
/// §11.8 — start, network change, a neighbour confirmed:
///
/// 1. It opens an **untouched port**: a second UDP socket that has never
///    sent anything, with a shell of its own (§4.2).
/// 2. From its DATA port it sends `0x48` to its fixed neighbour: the
///    untouched port's number and 16 random bytes.
/// 3. The neighbour takes the address it SAW the `0x48` come from and asks
///    one other open neighbour to try (`0x49`, `open_check_answer.dart`).
/// 4. That neighbour sends `0x4A` with the 16 bytes once to the address and
///    the untouched port.
///
/// If `0x4A` arrives within [kOpenDeadline], nothing in between needed
/// state to let it in: the family is **open**. No keep-alive runs on it
/// (`keep_alive.dart`), and the node's reachability is evidenced (§11.8a,
/// `board_proof.dart`). If nothing arrives, the family counts as not open
/// and the keep-alive runs as before — silence is not evidence of anything
/// else (§11.8): the neighbour may not know the device yet, or be rate
/// limited.
///
/// The untouched port carries only `0x4A` (and the shell's handshake it
/// answers after the first packet has already arrived), never delivery,
/// like the probe port (§11.1). It is closed after every check.
///
/// ── HOW OFTEN ────────────────────────────────────────────────────────
///
/// Per family and per (network, fixed neighbour) at most [kOpenAttempts]
/// checks, the second only [kOpenAgainAfter] after the first and only if
/// the first found nothing — a lost race against the device's own code
/// registration must not settle "not open" for the whole network. An open
/// family stays open until the next network change or fixed neighbour.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/board_node.dart' show NodeAnswer;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show interfaces;
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;
import 'package:mycelium/outside_route.dart' show kIdentifierLength;
import 'package:mycelium/shell.dart';
import 'package:mycelium/split.dart';
import 'package:mycelium/wire.dart';

/// How long the `0x4A` may take — it costs the helper's handshake first.
const Duration kOpenDeadline = Duration(seconds: 5);

/// Checks per family and (network, fixed neighbour).
const int kOpenAttempts = 2;

/// The second check comes no sooner — the neighbour answers a device at
/// most once a minute (`open_check_answer.dart`).
const Duration kOpenAgainAfter = Duration(minutes: 1);

/// What the node knows about one family.
enum FamilyOpen { unknown, open, notOpen }

class _Done {
  final String key;
  int attempts = 0;
  DateTime last;
  _Done(this.key, this.last);
}

class OpenCheck {
  final Node _k;
  final Duration deadline;

  /// Whether the fixed neighbour lies outside the own segment — different
  /// only for probes on 127.0.0.1: towards a neighbour in the own segment
  /// nothing in between is checked.
  bool Function(InternetAddress a) outside = fromOutsideReachable;

  /// A family was found open — the host network lets the keep-alive look.
  void Function(InternetAddressType type)? onOpen;

  /// Changeable ONLY for tests.
  DateTime Function() now = DateTime.now;

  final Random _random = Random.secure();
  final Map<InternetAddressType, FamilyOpen> _state = {};
  final Map<InternetAddressType, _Done> _done = {};
  final Set<InternetAddressType> _running = {};
  final Set<void Function()> _open = {};
  int _network = 0;
  bool _stopped = false;

  /// Counters for probes and the network statistics (§25) — read only.
  int checks = 0;
  int foundOpen = 0;

  /// The untouched port of the last check — ONLY for probes.
  int? lastUntouchedPort;

  OpenCheck(this._k, {this.deadline = kOpenDeadline});

  FamilyOpen stateOf(InternetAddressType type) =>
      _state[type] ?? FamilyOpen.unknown;

  bool isOpen(InternetAddressType type) => stateOf(type) == FamilyOpen.open;

  /// Edge network change: what was found belongs to the old network.
  void networkChanged() {
    _network++;
    _state.clear();
    _done.clear();
    edge();
  }

  /// The node stops: a running check ends at once.
  void stop() {
    _stopped = true;
    for (final c in List.of(_open)) {
      c();
    }
    _open.clear();
  }

  /// An edge: check every family the fixed neighbour is confirmed in.
  void edge() {
    if (_stopped) return;
    final t = now();
    final f = _k.neighbourhood.fixedNeighbour;
    if (f == null) return;
    for (final type in [InternetAddressType.IPv4, InternetAddressType.IPv6]) {
      if (_running.contains(type)) continue;
      if (!_k.speaks(type == InternetAddressType.IPv4
          ? InternetAddress.loopbackIPv4
          : InternetAddress.loopbackIPv6)) {
        continue;
      }
      final a =
          f.confirmedIn(type, t.subtract(Neighbourhood.staleAfter));
      if (a == null || !outside(a.address)) continue;
      final key = '$_network/${f.id}';
      var d = _done[type];
      if (d != null && d.key != key) {
        _state.remove(type); // another fixed neighbour: ask anew
        d = null;
      }
      if (d != null &&
          (_state[type] == FamilyOpen.open ||
              d.attempts >= kOpenAttempts ||
              t.difference(d.last) < kOpenAgainAfter)) {
        continue;
      }
      d ??= _done[type] = _Done(key, t);
      d
        ..attempts += 1
        ..last = t;
      unawaited(_run(type, (a.address, a.port)));
    }
  }

  Future<void> _run(
      InternetAddressType type, (InternetAddress, int) target) async {
    _running.add(type);
    final network = _network;
    try {
      final r = await check(target);
      if (_stopped || network != _network || r == null) return;
      _state[type] = r ? FamilyOpen.open : FamilyOpen.notOpen;
      _k.report('Open check ${type.name} towards '
          '${target.$1.address}:${target.$2}: '
          '${r ? "open — no keep-alive on it, reachability evidenced" : "nothing arrived — not open, keep-alive stays"}'
          ' (§8.1)');
      if (r) {
        foundOpen++;
        _k.passiveProof?.evidenced('open check ${type.name}');
        onOpen?.call(type);
      }
    } finally {
      _running.remove(type);
    }
  }

  /// ONE check towards the fixed neighbour at [target]: `true` open,
  /// `false` nothing arrived, `null` no untouched port could be opened.
  Future<bool?> check((InternetAddress, int) target) async {
    if (_stopped) return null;
    checks++;
    Wire? wire;
    Shell? shell;
    Splitter? splitter;
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      splitter?.close();
      shell?.close();
      wire?.close();
    }

    _open.add(close);
    try {
      wire = await Wire.open(port: 0, interfaces: interfaces, report: (_) {});
      if (target.$1.type == InternetAddressType.IPv6 && !wire.hasIpv6) {
        return null;
      }
      shell = Shell(wire, report: (_) {});
      final nonce = Uint8List.fromList(
          List<int>.generate(kIdentifierLength, (_) => _random.nextInt(256)));
      final arrived = Completer<bool>();
      splitter = Splitter(shell, onShipment: (data, from, fromPort) {
        if (data.length == 1 + kIdentifierLength &&
            data[0] == kinds.kOpen &&
            _same(data, 1, nonce) &&
            !arrived.isCompleted) {
          arrived.complete(true);
        }
      });
      final port = wire.port;
      lastUntouchedPort = port;
      final ask = Uint8List(3 + kIdentifierLength)
        ..[0] = kinds.kIsMyFamilyOpen
        ..[1] = port & 0xFF
        ..[2] = (port >> 8) & 0xFF
        ..setRange(3, 3 + kIdentifierLength, nonce);
      _k.outsideRoute.send(ask, target.$1, target.$2);
      return await arrived.future.timeout(deadline, onTimeout: () => false);
    } on Object catch (e) {
      _k.report('Open check: untouched port failed ($e)');
      return null;
    } finally {
      _open.remove(close);
      close();
    }
  }

  static bool _same(Uint8List a, int offset, Uint8List b) {
    for (var i = 0; i < b.length; i++) {
      if (a[offset + i] != b[i]) return false;
    }
    return true;
  }
}
