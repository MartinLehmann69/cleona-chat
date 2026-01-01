import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/message.dart' show DeliveryState;
import 'package:mycelium/envelope.dart';

/// What a group holds — the data, not the procedure.
///
/// Moved out of `group.dart`: two things stood there, WHAT a
/// group holds and HOW it sends. The line budget made that visible,
/// it was right even before.
/// What someone in the group may do. Three levels, ascending — the order
/// is binding: `index` is the level AND the byte that stands in the
/// key delivery (0x61). Whoever pushes something in between here
/// changes the wire format.
///
/// There is deliberately no new packet kind for roles: the role is not
/// an event of its own, but a property that goes along exactly when
/// someone gets the key.
enum Role { member, manager, owner }

/// A member: [address] for the seal, [destination] for the delivery,
/// [role] for what it may do. Without specification the lowest.
class Member {
  final Address address;
  final CardAddress destination;
  final Role role;
  const Member(
      {required this.address,
      required this.destination,
      this.role = Role.member});

  /// The same member with a different role — [Member] stays
  /// immutable, the list exchanges the entry.
  Member withRole(Role newRole) =>
      Member(address: address, destination: destination, role: newRole);
}

/// ── Who may do what ─────────────────────────────────────────────────────
///
/// The four questions and their answers, as pure functions: `null` means
/// "may", a text means "may not" and is at the same time the reason that
/// `GroupsError` carries. They stand here and not in `group.dart`,
/// so that the decision can be read in ONE place and is not spread over
/// four method headers.
///
/// | | admit | remove | change role | dissolve |
/// |---|---|---|---|---|
/// | Owner | yes | yes | yes | yes |
/// | Admin | only members, only without change | no | no | no |
/// | Member | no | no | no | no |
///
/// **Why the admin may do so little.** A key change is measured on
/// every invited side by whether it comes from the one whom it
/// remembered as issuer on joining (`Group.keyCame`). That
/// is exactly one. If an admin could change keys, their change would
/// be rejected by all older members — the group would split into two
/// generations without an error showing anywhere. Therefore
/// only the owner changes keys; the admin may invite, nothing more. And
/// because removing ALWAYS changes keys (the one leaving knows the old key),
/// only the owner may remove too.
///
/// **Why [Role.owner] is not assigned.** For the same reason:
/// a second owner would be no issuer for the invited sides
/// and could change nothing. The owner is whoever created the group
/// — nobody else.

String? mayAdmit(Role who, Role newRole, bool withChange) {
  if (who == Role.owner) return null;
  if (who != Role.manager) {
    return 'only owner and admins may admit';
  }
  if (newRole != Role.member) {
    return 'an admin may only admit ordinary members';
  }
  if (withChange) return 'an admin may not change the key';
  return null;
}

String? mayRemove(Role who) => who == Role.owner
    ? null
    : 'only the owner may remove — removing changes the key';

String? mayRoleChange(Role who, Role newRole) {
  if (who != Role.owner) return 'only the owner may change roles';
  if (newRole == Role.owner) {
    return 'owner is not assigned — there is exactly one, the creator';
  }
  return null;
}

String? mayDissolve(Role who) => who == Role.owner
    ? null
    : 'only the owner may dissolve the group';

/// Real copy: `sublistView` shares the buffer, the views outlive
/// it. Stands here because `group.dart` and `group_read.dart` need the same
/// one and two copies are two opportunities to diverge.
Uint8List cut(Uint8List b, int from, int until) =>
    Uint8List.fromList(Uint8List.sublistView(b, from, until));

/// Byte for byte equal. Same reasoning as [cut].
bool byteEqual(Uint8List x, Uint8List y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

/// A leg: for a message exactly ONE ([to] is `null`) — the deposit
/// from which all collect. For a change one per member.
class GroupsLeg {
  final Address? to;
  DeliveryState state;
  GroupsLeg(this.to, [this.state = DeliveryState.resting]);
}

/// What went out: a message ([text] set) or a pure
/// key delivery ([text] `null`).
class GroupsOutbound {
  final Uint8List groupsIdentifier;
  final int generation;
  final String? text;
  final List<GroupsLeg> legs;
  final DateTime at;
  GroupsOutbound({required this.groupsIdentifier, required this.generation,
      required this.text, required this.legs, required this.at});

  /// The weakest state across all legs.
  DeliveryState get state => stateViaLegs(legs.map((b) => b.state));
}

/// A received group message, signature checked. [from] is not
/// "anyone from the group", but exactly the signing address (E-16).
class GroupsInbound {
  final Uint8List groupsIdentifier;
  final int generation;
  final String text;
  final Address from;
  final DateTime at;
  GroupsInbound({required this.groupsIdentifier, required this.generation,
      required this.text, required this.from, required this.at});
}

/// One `resting` -> `resting`; one `in transit` -> `in transit`; all
/// `delivered` -> `delivered`; otherwise `failed`. No fifth value.
DeliveryState stateViaLegs(Iterable<DeliveryState> legs) {
  final list = legs.toList();
  if (list.isEmpty) return DeliveryState.failed; // nothing went out
  if (list.any((z) => z == DeliveryState.resting)) return DeliveryState.resting;
  if (list.any((z) => z == DeliveryState.inTransit)) return DeliveryState.inTransit;
  if (list.every((z) => z == DeliveryState.delivered)) return DeliveryState.delivered;
  // Mixed and nothing in transit any more: not everyone has it, and nobody
  // can re-deliver any more.
  return DeliveryState.failed;
}

/// A group as ONE side sees it.
