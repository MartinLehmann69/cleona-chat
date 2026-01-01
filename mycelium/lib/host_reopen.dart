/// Opening a mailbox anew from its files (V4.2 §14.6.2, D-39): after an
/// enrolment handover wrote an identity's memory — contacts, invitations,
/// group pairs, the own key state — the running mailbox, which a fresh
/// install held while it only searched (D-40), is replaced by one read from
/// those files. The identity stays the same, the port and the node stay.
///
/// Its own file: `host.dart` is at its line budget. It gets by with the
/// public side of [Host] and [Node].
library;

import 'package:mycelium/host.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_start.dart' show MailboxDetails;

extension HostReopen on Host {
  /// Replaces [p] by a mailbox read from [a]'s directory — also the last
  /// one: between the two steps (synchronous, no packet is taken) the node
  /// holds no identity, then again the same one. Returns the new mailbox;
  /// [p] is dead afterwards.
  Mailbox reopen(Mailbox p, MailboxDetails a) {
    // `Node.deregister` keeps the last identity; taken out here first, it
    // finds nothing to keep and the host forgets the mailbox and its codes.
    node.identities.remove(p.identity);
    node.dispatcher.identityForget(p.identity);
    deregister(p);
    report?.call('mailbox ${p.ownIdentifier.substring(0, 8)} reopened from '
        'its files');
    return register(a);
  }
}
