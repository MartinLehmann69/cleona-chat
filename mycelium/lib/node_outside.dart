import 'dart:io';

import 'package:mycelium/card.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart';

/// The outside of the node: learning how one looks from outside,
/// and punching through a NAT.
///
/// Its own file for the same reason as `node_invitation.dart` — the
/// line budget of `node.dart` knows no exception. The cut follows
/// the question WHOM one asks: here someone who stands outside the own
/// segment, over there the own parts.
///
/// It gets by with the public side of [Node]: [Node
/// .outsideRoute], [Node.report] and [Node.publicAddress].
extension NodeOutside on Node {

  /// Asks [neighbour] how the own address looks from there, and remembers
  /// it as [Node.publicAddress] — but only if it is not
  /// private.
  ///
  /// A neighbour in the own segment sees the LAN address. Writing it as
  /// "public" into a card would be worse than leaving the
  /// field empty: the counterpart would try for a whole
  /// ladder step an address under which it never finds anyone.
  /// This question is therefore only useful towards a counterpart
  /// OUTSIDE the own segment — and thus only once there is a
  /// second neighbour source (remembered neighbours, card, external entry).
  Future<CardAddress?> publicAddressLearn(
      InternetAddress neighbour, int neighbourPort) async {
    final seen = await outsideRoute.whatIsMyAddress(neighbour, neighbourPort);
    if (seen == null) {
      report('$neighbour:$neighbourPort did not say how I look');
      return null;
    }
    final asAddress = InternetAddress.fromRawAddress(seen.address);
    if (isPrivate(asAddress)) {
      report('seen from $neighbour: ${asAddress.address}:'
          '${seen.port} — private, not remembered as public address');
      return null;
    }
    publicAddress = seen;
    report('own public address: ${asAddress.address}:'
        '${seen.port}');
    return seen;
  }

  /// Knocks at [target] so that a NAT in front of it opens the return route.
  /// `true` as soon as the counterpart knocks in turn.
  Future<bool> knock(InternetAddress target, int targetPort) =>
      outsideRoute.knock(target, targetPort);
}
