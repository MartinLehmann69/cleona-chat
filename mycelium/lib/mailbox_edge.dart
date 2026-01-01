/// AN EDGE of V4.2 §8.2 for one identity — the ONE way what rests goes again.
///
/// §9.3: "At the edges of §8.2 the node sends again, under the same
/// identifier, what is neither acknowledged nor placed". What rests for a
/// peer is two things: own messages in the history
/// ([MailboxOutbound.giveUpAgain]) and the day-key notice that is still
/// uncounted ([MailboxPair.dayKeyDistribute]; it counts only with its receipt
/// or its placing, `day_key_notice.dart`). Both are idempotent: they send
/// only what is due, and without anything due an edge costs no packet.
///
/// Who calls it (S408-RESEND; until then each edge called its own subset —
/// S403 finding 2: network change and "application opened" sent no message
/// again; S407-OLAPPW W-2: two edges sent no day-key notice again):
///
///  * `Host.networkChanged`, `Host.applicationOpened`, the new neighbour
///    (`host.dart`, `host_codes.dart`) — for every peer;
///  * the answer to an own `0x23` (§8.1 "and what rests for it goes again",
///    D-76; `where_are_you_answer.dart`) — for that peer only.
///
/// Start and "mailbox registered" keep their own order (`Host.start`,
/// `Host.register`, `HostCodes.codesAdmit`): the day keys go at the
/// admission, before the first re-dispatch.
///
/// No clock and no repetition of its own (§5.4, §11.3a): an edge is an
/// event; between two edges nothing is sent.
library;

import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_outbound.dart' show MailboxOutbound;
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;

extension MailboxEdge on Mailbox {
  /// What rests goes again — for every peer, or with [only] for that one.
  void atEdge({Address? only}) {
    giveUpAgain(only: only);
    dayKeyDistribute(only: only);
  }
}
