/// The acknowledgement's way (V4.2 §9.2, D-44; S399 step 3).
///
/// > The acknowledgement takes the way the message came; it is left in a post
/// > box only when the message was collected from one.
///
/// Until S399 this rule stood nowhere and a "sign of life" did its work in
/// hiding: an acknowledgement went up the whole ladder, and a packet from the
/// sender paused its post box step before the offset ran out (S398 draft,
/// §3). With the sign of life gone, the way is said here, from how the
/// message arrived:
///
/// | message came | acknowledgement takes |
/// |---|---|
/// | directly, from an address | step 1, to that address |
/// | under a code (step 3) | step 3, under the reverse code |
/// | collected from a post box | steps 1, 3 and 4 |
///
/// A held-back acknowledgement (§9.4 Q1) takes the way its message came: the
/// way is kept when it is held back ([NodeReceipt.receiptWays]). Only when that
/// is no longer known — after a restart, or beyond [kHeldWaysAtMost] — it takes
/// steps 1 and 3 and never the post box: §9.2 allows the post box only for
/// collected post, and at the edges of §9.3 the sender sends again what is
/// neither acknowledged nor placed; the duplicate is acknowledged anew.
///
/// Its own file for the line budget of `node.dart`.
library;

import 'dart:typed_data';

import 'package:mycelium/card.dart';
import 'package:mycelium/ladder.dart' show Target;
import 'package:mycelium/message.dart' show Messages;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_first_contact_box.dart' show NodeFirstContactBox;
import 'package:mycelium/node_helpers.dart' show hexFrom;

/// At most this many held-back acknowledgements keep their way per node
/// (§20.1: every buffer has a declared bound). Set, not measured; the oldest
/// falls out and then takes steps 1 and 3.
const int kHeldWaysAtMost = 256;

typedef _Way = ({bool collected, bool underCode, CardAddress? origin});

final Expando<Map<String, _Way>> _held = Expando('held-back receipt ways');
final Expando<_Way> _replay = Expando('held-back receipt way being sent');

extension NodeReceipt on Node {
  /// Wires [n] so that a held-back acknowledgement keeps the way its message
  /// came and takes it when the application sends it later.
  Messages receiptWays(Messages n) {
    final held = _held[this] ??= {};
    n.onHeld = (identifier, origin) {
      // The FIRST copy's way (§7.1: the same message comes by several steps;
      // the first to arrive came the fastest way). Measured S399 finding 9:
      // with the last copy's way the receipt went by step 3 only, although
      // the message had come directly.
      held.putIfAbsent(hexFrom(identifier),
          () => (collected: feedingCollected, underCode: feedingUnderCode, origin: origin));
      while (held.length > kHeldWaysAtMost) {
        held.remove(held.keys.first);
      }
    };
    n.heldBack = (identifier, send) {
      final w = held.remove(hexFrom(identifier));
      if (w == null) return send(null);
      _replay[this] = w;
      try {
        send(w.origin);
      } finally {
        _replay[this] = null;
      }
    };
    return n;
  }

  /// The [Target] of an acknowledgement to [identifier]: [three] the
  /// contact's addresses, [origin] the address the message came from
  /// (`null` when it came forwarded or collected), [c] code and fixed
  /// neighbours of the pair. Read while the message is being fed —
  /// [feedingCollected] and [Node.feedingUnderCode] cover exactly it — or
  /// while a held-back one is sent ([receiptWays]).
  Target receiptTarget(Routes? three, CardAddress? origin,
      ({Uint8List code, List<CardAddress> neighbours})? c, Uint8List identifier) {
    final r = _replay[this];
    if (r?.collected ?? feedingCollected) {
      return Target.outDueTo(three,
          neighbours: c?.neighbours ?? const [], code: c?.code, identifier: identifier);
    }
    if (r?.underCode ?? feedingUnderCode) {
      // No identifier: it would start a search call, and the way is known.
      return Target(
          neighbour: c?.neighbours.firstOrNull,
          neighbours: c?.neighbours ?? const [],
          code: c?.code,
          postBoxApplicable: false);
    }
    if (origin != null) return Target(lan: origin, postBoxApplicable: false);
    // Way no longer known (see the file header): steps 1 and 3, no post box.
    return Target.outDueTo(three,
        neighbours: c?.neighbours ?? const [], code: c?.code, postBoxApplicable: false);
  }
}
