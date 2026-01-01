/// The Emergency Key Rotation of a RUNNING mailbox (V4.2 §4.5.4, §8.2,
/// §15.3; D-33, proposal A step 3).
///
/// Until S398 the delivery layer learned new signing keys only at the next
/// start: the running post box kept signing with the replaced keys, a
/// contact that had already adopted the new ones discarded every envelope,
/// and whoever held the old keys kept reading along
/// (`berichte/S398-ROTATION-REST.md`, finding 3).
///
/// What the rotation does here, in this order:
///  1. the post box takes the new keys and the chain the app made
///     ([PostBox.signingAdopt]) — identifier and founding key stay, the
///     current KEM generation and day-key seed become the previous ones;
///  2. every contact is set back to "chain not acknowledged" (the chain
///     rides again in every envelope to it, E-A7) and "day keys due";
///  3. the new day keys go to every contact at once, regardless of the
///     14-day rule (§8.2);
///  4. every open own message goes out again, sealed and signed with the
///     new keys — also what is running (under the old keys it would be
///     superseded at a contact that adopted the new ones);
///  5. every standing invitation is revoked (§15.3, E-A3): its line and card
///     name this identity's old bundle, and its secrets may be in the hands
///     that caused the rotation; new ones are issued by the user.
///
/// It sends NO announcement: that is the app's KEY_ROTATION_BROADCAST,
/// sent after this call — its envelope is the first to carry the chain.
library;

import 'package:mycelium/envelope.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_invitation.dart' show MailboxInvitation;
import 'package:mycelium/mailbox_outbound.dart' show MailboxOutbound;
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/memory_contact.dart' show contactWithChainState;

extension MailboxRotation on Mailbox {
  /// Takes the Emergency Key Rotation into the running mailbox — [fresh] is
  /// the app's post box after `rotateIdentityFull` (`postBoxFrom`). Throws
  /// [ArgumentError] if [fresh] is not this identity one rotation further;
  /// then nothing has changed.
  void identityRotate(PostBox fresh, {DateTime? now}) {
    identity.postBox.signingAdopt(fresh, now: now);
    ownPostBoxSave();
    for (final k in contacts) {
      contactPut(contactWithChainState(k, acked: false, dayKeysDue: true));
    }
    final sent = dayKeyDistribute(now: now);
    giveUpAgain(reseal: true);
    final revoked = allInvitationsRevoke();
    node.codeRoute.codesChanged();
    report?.call('emergency key rotation taken over: chain '
        '${identity.postBox.address.chain.length} link(s), day keys to '
        '$sent contact(s), $revoked invitation(s) revoked (§4.5.4, §15.3)');
  }
}
