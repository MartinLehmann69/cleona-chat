/// "Who are you" (V4.2 §11.8, D-87): the request that lets two addresses of
/// one node become one neighbour within a run.
///
/// §11.8 joins two addresses when "within one run, it names the same node
/// identifier (§7.2) in answers to this node's requests from both". The
/// address question `0x40` that §11.8.5 and §11.8.6 prescribe answers without
/// an identifier, so that way was never fed: a node arriving from a new address
/// over a new handshake stayed a second neighbour (S411). The answer names the
/// node identifier, drawn anew at every start; the DeviceID stays off the wire
/// (§14.1).
///
/// ── Sent ──────────────────────────────────────────────────────────────
///
/// Beside the `0x40` of §11.8.5 and §11.8.6; once to an address that answers
/// for the first time without having named an identifier (§11.8.2); and to an
/// address first heard through a new shell handshake. At most one per address
/// and edge of [Readiness.resets]; a caller asking many at one edge takes at
/// most `kPathChecksAtMost`. Nothing here runs on a clock (§1.2).
///
/// ── Silence says nothing ──────────────────────────────────────────────
///
/// A 4.2.3 or 4.2.4 node drops the kind without an answer (`OutsideRoute`
/// there knows only its own kinds) and stays handled as before. So silence
/// here fails no address and marks none as silent (`Silence.ask`,
/// `evidence: false`), and a repeat goes out only while the path itself is
/// unproven: once the address has answered anything, an unanswered question
/// means the other side does not know the kind, and that costs one packet,
/// not four. The price is that a question lost on a proven path waits for the
/// next edge; until then the node may count twice, as §11.8.6 allows.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_call.dart';
import 'package:mycelium/node_helpers.dart' show hexFrom;
import 'package:mycelium/node_silence.dart';

/// The random bytes that bind an answer to its question.
const int kWhoRandomLength = 16;

/// The node identifier in an answer (`node_call.dart`).
const int kWhoNodeLength = 16;

/// The answer to [question], a `0x4B`: the same bytes and [node]. `null` if
/// the question is malformed.
Uint8List? whoAnswer(Uint8List question, Uint8List node) {
  if (question.length != 1 + kWhoRandomLength || node.length != kWhoNodeLength) {
    return null;
  }
  return (BytesBuilder()
        ..addByte(kinds.kIAm)
        ..add(question.sublist(1))
        ..add(node))
      .toBytes();
}

class _Open {
  final InternetAddress address;
  final int port;
  final Completer<void> done = Completer<void>();
  _Open(this.address, this.port);
}

class WhoQuestion {
  final Node _k;
  final Random _random = Random.secure();

  /// The random bytes of a running question -> who was asked.
  final Map<String, _Open> _open = {};

  /// Addresses asked at this edge; bounded like the path requests (§20.2).
  final Set<String> _asked = {};
  int _edge = -1;

  /// At most this many addresses are remembered; the oldest gives way.
  static const int rememberedAtMost = 64;

  WhoQuestion(this._k);

  /// Asks [a]:[p] unless it was asked at this edge. `true` if it went out.
  bool ask(InternetAddress a, int p) {
    final edge = _k.readiness.resets;
    if (edge != _edge) {
      _edge = edge;
      _asked.clear();
    }
    if (!_asked.add('${a.address}:$p')) return false;
    if (_asked.length > rememberedAtMost) _asked.remove(_asked.first);
    unawaited(_question(a, p));
    return true;
  }

  Future<void> _question(InternetAddress a, int p) async {
    final random = Uint8List(kWhoRandomLength);
    for (var i = 0; i < random.length; i++) {
      random[i] = _random.nextInt(256);
    }
    final key = random.join(',');
    final open = _Open(a, p);
    _open[key] = open;
    final packet = (BytesBuilder()
          ..addByte(kinds.kWhoAreYou)
          ..add(random))
        .toBytes();
    try {
      await _k.silence.ask(open.done.future,
          to: a,
          port: p,
          send: (x, y) async => _k.outsideRoute.send(packet, x, y),
          others: false,
          evidence: false,
          cancelled: () => _pathProven(a, p),
          what: 'who question');
    } finally {
      _open.remove(key);
    }
  }

  /// The address answered something in this run: the path stands.
  bool _pathProven(InternetAddress a, int p) =>
      _k.neighbourhood
          .holding(a, p)
          ?.addresses
          .any((x) => x.isAt(a, p) && x.answering) ??
      false;

  /// A `0x4B` or `0x4C` from the outside route.
  void receive(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.isEmpty) return;
    if (packet[0] == kinds.kWhoAreYou) {
      final answer = whoAnswer(packet, _k.nodeIdentifier);
      if (answer != null) _k.outsideRoute.send(answer, from, fromPort);
    } else if (packet[0] == kinds.kIAm) {
      _onAnswer(packet, from, fromPort);
    }
  }

  void _onAnswer(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.length != 1 + kWhoRandomLength + kWhoNodeLength) return;
    final key = packet.sublist(1, 1 + kWhoRandomLength).join(',');
    final open = _open[key];
    if (open == null || open.done.isCompleted) return; // never asked
    if (open.address.address != from.address || open.port != fromPort) {
      return; // the right bytes from another address: discarded
    }
    final node = hexFrom(packet.sublist(1 + kWhoRandomLength));
    if (node == hexFrom(_k.nodeIdentifier)) {
      open.done.complete();
      return; // an own former address: no neighbour
    }
    _k.readiness.dropped.forget(from, fromPort); // its answer lifts a removal
    _k.readiness.nodeLearn(from, fromPort, node);
    open.done.complete();
  }
}

final Expando<WhoQuestion> _who = Expando<WhoQuestion>('who question');

extension NodeWho on Node {
  WhoQuestion get who => _who[this] ??= WhoQuestion(this);
}
