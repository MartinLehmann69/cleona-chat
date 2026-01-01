import 'dart:typed_data';

import 'package:mycelium/identity.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/envelope.dart';

/// The amendment side of the node — reactions, edits,
/// read marks.
///
/// It lives in its own file because `node.dart` would otherwise exceed
/// the line budget. The budget has no exception mechanism: if it does
/// not fit, the design is wrong, not the limit. An extension
/// instead of inheritance, so that there is still ONE node and not
/// two kinds of it.
///
/// Everything here uses only the public side of [Node]
/// ([identities], [Node.dispatcher], [Node.report], [Node.main]) —
/// it needs no access to its internals.
extension NodeAmendments on Node {
  /// An amendment that goes to an identity but does not say
  /// which one — the same order as for a message.
  void amendmentToOneIdentity(Uint8List data, CardAddress origin) {
    final hit = dispatcher.distribute(
      origin.toString(),
      (i) => i.amendments.receive(data, origin),
    );
    if (hit == null) {
      report('Amendment for none of the ${identities.length} identities');
    }
  }

  /// Reacts to a message.
  void react(Uint8List identifier, String chars, Address to,
      CardAddress destination,
      {bool isSet = true, Identity? forField}) {
    (forField ?? main)
        .amendments
        .react(identifier, chars, to, destination, isSet: isSet);
  }

  /// Changes the content of one's own message. [newContent] is raw
  /// bytes — this layer does not interpret them (see `message.dart`).
  void edit(Uint8List identifier, Uint8List newContent, Address to,
      CardAddress destination, {Identity? forField}) {
    (forField ?? main).amendments.edit(identifier, newContent, to, destination);
  }

  /// Notes towards the sender that it was read.
  void read(Uint8List identifier, Address to, CardAddress destination,
      {Identity? forField}) {
    (forField ?? main).amendments.read(identifier, to, destination);
  }
  /// A packet that goes to an identity but does not say which one.
  /// The order is decided by the [Dispatcher] (§see there).
  /// [origin] assigns the packet to an identity (only a key for
  /// the distributor); [returnRoute] is the address to which a receipt may
  /// go FIRST — `null` if the piece came from a post box
  /// and the address belongs to the holder.
  void toOneIdentity(
      Uint8List data, CardAddress origin, CardAddress? returnRoute) {
    final hit = dispatcher.distribute(
      origin.toString(),
      (i) => i.messages.receive(data, returnRoute),
    );
    if (hit == null) {
      report('Packet for none of the ${identities.length} identities');
    }
  }
}
