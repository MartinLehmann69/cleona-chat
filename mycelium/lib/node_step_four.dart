/// Step 4 of the ladder at the node — which value a packet is left under
/// (V4.2 §8.2, §15.1; OP-20, S398).
///
/// Two cases, told apart by the [Target] alone:
///
///  * **a line join's request (2)** carries the invitation value
///    `dayValue(pk_inv)` ([Target.boxValue]): it is left there, the card's
///    neighbour first — the holder the issuer asks (§8.2) — never on a
///    device of the issuer ([Target.lan], its card address). No contact is
///    looked up: until OP-20 step 4 asked every mailbox of the host for the
///    issuer, and when ANOTHER identity of this node had it as a contact the
///    request went under that contact's day value (lab E/O2, T2/T3). That
///    linked the node's identities at the holders and told the issuer that
///    the requester's device hosts one of its contacts (§9.2 "a friend of
///    one identity is never named to the contacts of another").
///  * **everything else** — messages, answers, the receipt (4) — goes under
///    the recipient's day value ([NodePostBox.stepFourForIdentifier]).
///
/// A QR or NFC join has no post box before the contact (§15.1 "a card read
/// from them is redeemable only while the issuer is on"): `node_join.dart`
/// does not make step 4 applicable for it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/ladder.dart' show Target;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_first_contact_box.dart';
import 'package:mycelium/node_post_box.dart';

extension NodeStepFour on Node {
  /// The post box step of the ladder (`Ladder.inPostBox`). [ended] is asked
  /// once the proof of work is ready: an acknowledged sending leaves nothing
  /// (§7.1). Returns the placing (`ladder.dart`, `DepositSend`): whether two
  /// holders acknowledged; `null` if nothing was left.
  Future<bool>? stepFour(
      Uint8List packet, Target target, bool Function() ended) {
    final value = target.boxValue;
    if (value != null) {
      return depositNamed(packet, value, [
        if (target.neighbour case final n?) n,
      ], at: [
        if (target.lan case final l?) l,
      ], ended: ended)
          .then((r) => r.$1);
    }
    final identifier = target.identifier;
    if (identifier == null) {
      report('Post box step without target identifier — not deposited');
      return null;
    }
    // M3: under the day value
    return stepFourForIdentifier(identifier, packet, ended: ended);
  }
}
