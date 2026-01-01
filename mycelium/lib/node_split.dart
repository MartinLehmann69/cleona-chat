/// The splitter of a node and its receive path (§11.2, §11.3, D-41).
///
/// Out of `node.dart` for the line budget (mycelium/README.md rule 2) when
/// the flow per next hop came in (S398 OP-33 B, taken over in S399 step 2);
/// the order of the parts is the statement, as in `socketBuild`: wire,
/// shell, cover switch, splitter.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show ownTarget;
import 'package:mycelium/node_roam.dart';
import 'package:mycelium/node_silence.dart';
import 'package:mycelium/shell.dart';
import 'package:mycelium/split.dart';
import 'package:mycelium/trace.dart';
import 'package:mycelium/who_question.dart';

/// Builds [k]'s splitter above the cover switch — cover packets with
/// content are branched off BEFORE the splitter (§5.5) — and attaches it to
/// [shell], so that the shell tells it whether it still holds a hop's
/// packets for a handshake and how that handshake ended (§20.2, D-41). The
/// post box's request renews a link silent for more than 2 s first (§11.6
/// variant A, S399 step 4, owner 30.09.2026).
Splitter nodeSplitter(Node k, Shell shell) {
  k.postBoxDeposit.beforeRequest = (n) => shell.renewIfSilent(n.$1, n.$2);
  k.outsideRoute.silence = k.silence; // §11.3a: the 0x40 declares a failed address
  k.outsideRoute.onWho = k.who.receive; // §11.8, D-87
  k.readiness.onFirstAnswer = k.who.ask; // §11.8.2: first answer of an address
  // §11.8.6: an address first heard through a new handshake.
  shell.onCalled = (a, p) {
    if (k.neighbourhood.holding(a, p) == null) k.who.ask(a, p);
  };
  // S405 (proposal D): the `TRACE step3` lines.
  k.codeRoute.recording = (p, out) {
    if (traceOn) k.report('TRACE step3 ${out ? "out" : "in"}: ${packetDescribe(p)}');
  };
  final s = Splitter(
      k.coverStream.coverSwitch(shell),
      onShipment: (data, from, fromPort) {
      // An arriving packet says nothing to the ladder: only the
      // acknowledgement ends a sending (§7.1; the "sign of life" is gone, S399).
      k.feed(data, from, fromPort); // learns the node identifier along the way (B1)
      // Arrival alone confirms no neighbour (W8, `readiness.dart`).
    }, report: k.report)
      ..attach(shell);
  // §11.3a: a handshake and its repeats without an answer — that address
  // has failed, and a failed first hop of step 3 hands its sending on
  // (S405, owner decision 06.10.2026: variant B + C).
  shell.onHeard = (a, p) => nodeHeard(k, a, p); // §11.8.6: one path request
  shell.onMoved = (o, op, to, tp) => nodeMoved(k, shell, o, op, to, tp); // §11.8.6
  shell.onSilent = (target, port) {
    k.silence.failedAddress(target, port, 'handshake');
    k.codeRoute.retry.silent(target, port);
  };
  // §8.2: while parts of a hand-out are arriving, the collector's quiet
  // period does not count.
  k.postBoxDeposit.arriving = (n) => s.receivingFrom(n.$1, n.$2);
  return s;
}

/// The post box's way to the splitter. A holder's hand-out (`0x33`, §8.2) is
/// others' traffic and bounded per target (§20.2 "others' transmissions
/// waiting for their next hop"); every other post box packet — a deposit,
/// a collect, their answers — is the node's own or a single part.
///
/// A packet to one of [k]'s own addresses never reaches the wire
/// ([ownTarget], S407-B19): a sender that is itself a fixed neighbour of the
/// recipient holds the post it leaves (§8.2, S407-VB20). It goes to the own
/// post box in the next microtask, with the address it was sent to as the
/// sender — packets, kinds and answers stay those of the wire, so the own
/// receipt `0x31` counts as one node like any other.
Future<SendEnd> postBoxSend(
    Node k, Splitter s, Uint8List p, (InternetAddress, int) target) {
  final (a, port) = target;
  if (ownTarget(k, CardAddress(Uint8List.fromList(a.rawAddress), port))) {
    scheduleMicrotask(() => k.postBoxDeposit.receive(p, a, port));
    return Future.value(SendEnd.sent);
  }
  return s.send(p, a, port, foreign: p.isNotEmpty && p[0] == kinds.kHereItIs);
}
