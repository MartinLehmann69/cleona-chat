/// First contact through the post box — proposal E (V4.2 §8.2, §15.1,
/// §15.6; owner approval 28.09.2026).
///
/// A `cleona:2:` line carries the issuer's bundle and `pk_inv`; the requester
/// needs no bundle round trip and leaves its request (2) under the
/// invitation value `dayValue(pk_inv)` while the issuer is off. Three things
/// make that work, and they stand here:
///
///  * **the requester's step 4** — a line join's request carries its
///    invitation value in the ladder's target and is left there, the card's
///    neighbour first — the holder the issuer asks (`node_step_four.dart`,
///    [depositNamed]; OP-20, S398);
///  * **the issuer's questions** — at each collection, per invitation that
///    still accepts, its value, proven with the `pk_inv` pair
///    ([invitationQuestions], [invitationHolders]);
///  * **the mark "collected"** — a request from a post box is no evidence of
///    an address: the address it "came from" is the holder's
///    ([feedCollected], read in `node_invitation.dart`).
///
/// No clock: the questions ride on the edges of `node_post_box.dart`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/forward_family.dart' show isSelf;
import 'package:mycelium/identity.dart';
import 'package:mycelium/neighbourhood.dart' show Neighbourhood;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/pair.dart' show dayValue;
import 'package:mycelium/post_box_deposit.dart'
    show Neighbour, Question, kAtMostValues;
import 'package:mycelium/post_box_holders.dart';

extension NodeFirstContactBox on Node {
  /// Whether the packets being fed right now came out of a post box.
  bool get feedingCollected => _collected[this] == true;

  /// Feeds [pieces] collected from a post box, as if they had just arrived
  /// from [holder] — flagged as collected while they are fed. [Node.feed] is
  /// synchronous, so the mark covers exactly these pieces.
  void feedCollected(List<Uint8List> pieces, Neighbour holder) {
    _collected[this] = true;
    try {
      for (final s in pieces) {
        feed(s, holder.$1, holder.$2, withoutReturnRoute: true);
      }
    } finally {
      _collected[this] = null;
    }
  }

  /// The holders a deposit addresses: [named] first where usable, then the
  /// own holders ranked — three NODES in all (§8.2; OP-19 parts A/B, S398).
  /// [at]: the recipient's own addresses — no node of them holds, named or
  /// own: the recipient never asks itself.
  List<Neighbour> holdersNamedFirst(List<CardAddress> named,
      {List<CardAddress> at = const []}) {
    final not = [
      for (final c in at)
        (InternetAddress.fromRawAddress(Uint8List.fromList(c.address)), c.port),
    ];
    final away = {for (final (a, p) in not) readiness.nodeOf(a, p)};
    return depositHolders(
        named,
        ownHolders(not: not, n: 2 * kDepositHolders),
        (a) =>
            speaks(a.$1) &&
            Neighbourhood.possible(a.$1, a.$2) &&
            !isSelf(this, a.$1, a.$2) &&
            !away.contains(readiness.nodeOf(a.$1, a.$2)),
        node: (a) => readiness.nodeOf(a.$1, a.$2));
  }

  /// Leaves [content] under [value] with [named] holders first, none at
  /// [at]. Does not throw (see [NodePostBox.deposit]).
  Future<(bool done, int acknowledged)> depositNamed(
          Uint8List content, Uint8List value, List<CardAddress> named,
          {List<CardAddress> at = const [], bool Function()? ended}) =>
      deposit(content, value,
          withWhom: holdersNamedFirst(named, at: at), ended: ended);

  /// The questions under which [i]'s invitation post boxes are collected:
  /// per invitation that still accepts (standing or in its grace period,
  /// §15.3 — the window a request in a post box may take), its value with
  /// the `pk_inv` pair; at most [kAtMostValues] per question.
  List<List<Question>> invitationQuestions(Identity i) {
    final pairs = [
      for (final e in i.invitations.accepting())
        if (e.box case final b?) b, // random per invitation (E-A4)
    ];
    final List<Question> all = [
      for (final p in pairs) (value: dayValue(p.pk), pair: p),
    ];
    return [
      for (var k = 0; k < all.length; k += kAtMostValues)
        all.sublist(k, k + kAtMostValues > all.length ? all.length : k + kAtMostValues),
    ];
  }

  /// Whom those questions ask: [neighbours] (the collection's), plus the
  /// neighbour each accepting invitation's card named — the holder a
  /// requester leaves post with first.
  List<Neighbour> invitationHolders(Identity i, List<Neighbour> neighbours) =>
      holdersJoin(neighbours, [
        for (final e in i.invitations.accepting())
          if (e.cardNeighbour case final n?)
            (InternetAddress.fromRawAddress(Uint8List.fromList(n.address)), n.port),
      ]);
}

final Expando<bool> _collected = Expando<bool>('feedingCollected');
