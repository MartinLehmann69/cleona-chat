import 'dart:typed_data';

import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/first_contact.dart';
import 'package:mycelium/memory.dart'
    show RememberedInvitation, rememberedFrom, stillAccepts;
import 'package:mycelium/node_helpers.dart';
import 'package:mycelium/message.dart' show Messages, Back;
import 'package:mycelium/amendment.dart';
import 'package:mycelium/envelope.dart';

/// An identity on this node.
///
/// A node holds several of them AT THE SAME TIME — one socket, one port,
/// all active. What all share is the infrastructure: wire,
/// splitter, forwarder, storage, neighbours, ladder. What belongs
/// separately per identity stands here.
///
/// **It belongs separately because two identities of the same human must not
/// be connected with each other.** Shared
/// contacts or a shared message store would be exactly the
/// connection that must not exist.
class Identity {
  final PostBox postBox;

  /// The own message path. Every identity has its own, because
  /// the receipts go to its key.
  final Messages messages;

  /// The own amendment path — reactions, edits, read marks.
  /// Belongs to the identity for the same reason as [messages]: it
  /// takes and gives sealed packets to ITS key.
  late final Amendments amendments;

  /// Who wrote the message with this identifier, and when.
  /// For own messages the answer comes from [messages], for
  /// foreign ones from what has been received.
  final Map<String, ({Address who, DateTime at})> author = {};

  /// The invitations that THIS identity has issued — those of this
  /// run AND those restored from memory
  /// (`NodeInvitation.invitationRestore`, S388). ONE list: revocation,
  /// counter and the cap from `inv.kAtMostStanding` see both. Until
  /// S388 the loaded ones stood as a second field beside it, which was neither
  /// revocable nor answered on the wire (B3).
  final inv.Invitations invitations = inv.Invitations();

  /// The current invitations, by code.
  final Map<String, Invitation> open = {};

  /// The current joins of this identity.
  final List<Join> joins = [];

  /// A display name for the UI — purely local, never goes out.
  final String name;

  Identity({
    required this.postBox,
    required this.messages,
    this.name = '',
  });

  /// What of the issued invitations belongs on disk: each in
  /// [invitations] — the restored ones have stood there too since S388.
  ///
  /// Order: those still accepting first. The format's cap
  /// cuts off at the back, and what falls should be what
  /// nobody redeems any more anyway.
  List<RememberedInvitation> invitationsSave({int? now}) {
    final t = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final out = [for (final e in invitations.all) rememberedFrom(e)];
    return [
      for (final g in out)
        if (stillAccepts(g, t)) g,
      for (final g in out)
        if (!stillAccepts(g, t)) g,
    ];
  }


  /// Wires up the amendment path of this identity.
  ///
  /// It arises here and not in the node because it belongs to THIS identity:
  /// it takes and gives sealed packets to its key
  /// and answers its authorship question from its memory.
  void amendmentsWireUp(
    Back send,
    Report report, {
    void Function(Reaction)? onReaction,
    void Function(Edit)? onEdit,
    void Function(ReadMark)? onReadMark,
  }) {
    amendments = Amendments(
      me: postBox,
      send: send,
      authorFrom: (k) => author[hexFrom(k)],
      onReaction: onReaction,
      onEdit: onEdit,
      onReadMark: onReadMark,
      report: report,
    );
  }

  Uint8List get identifier => postBox.address.identifier;
  String get identifierHex => hexFrom(identifier);

  @override
  String toString() =>
      'Identity(${name.isEmpty ? identifierHex.substring(0, 8) : name})';
}

/// Finds the right identity for an incoming packet.
///
/// A packet does not name its recipient — precisely therefore an
/// observer does not see which identity is addressed. The price is
/// that trying through is necessary: measured around 4 ms per identity that
/// does NOT fit, because the decapsulation runs through before the check
/// fails. With five identities that would be 20 ms per packet.
///
/// Therefore this dispatcher remembers which identity last
/// fitted a sender address, and tries it first. In the
/// normal case that is ONE attempt instead of N; the expensive case remains only
/// for the first packet of a sender.
///
/// **This is an order, not a shortcut.** If the remembered one does not
/// fit, all others are tried — a wrong flag costs
/// one attempt, never a delivery. And nothing leaks outside:
/// the flag is purely local.
class Dispatcher {
  final List<Identity> identities;

  /// Sender address -> last matching identity. Purely local.
  final Map<String, Identity> _last = {};

  /// How many unseal attempts were needed — for the measurement.
  int attempts = 0;

  Dispatcher(this.identities);

  /// Tries [deliver] for every identity, the remembered one first.
  /// Returns the identity for which it opened, otherwise null.
  Identity? distribute(
    String sender,
    void Function(Identity) deliver,
  ) {
    final remembered = _last[sender];
    final row = <Identity>[
      if (remembered != null) remembered,
      for (final i in identities)
        if (!identical(i, remembered)) i,
    ];
    for (final i in row) {
      attempts++;
      try {
        deliver(i);
        _last[sender] = i;
        return i;
      } on Object {
        continue; // not for this one — try the next
      }
    }
    return null;
  }

  /// Forgets what was remembered for [sender] — for instance when its address
  /// changes.
  void forget(String sender) => _last.remove(sender);

  /// Forgets every flag that points to [i] — when deregistering an
  /// identity. Otherwise the dispatcher would try one that no longer exists.
  void identityForget(Identity i) =>
      _last.removeWhere((_, v) => identical(v, i));
}
