import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/first_contact.dart';
import 'package:mycelium/identity.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/address_class.dart' show routesFromCard;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show hexFrom, shortFrom;
import 'package:mycelium/ladder.dart';
import 'package:mycelium/pair.dart' show firstContactCode;

/// How THIS side joins — and why that is a file of its own.
///
/// The join is the only send path of the node that **has no
/// contact**. `Node._viaLadder` asks `routesTo` and gets the
/// three addresses from the mailbox; here there is no mailbox and no
/// contact that one could ask. The routes are exclusively in the
/// CARD (§15.2), and that is the only reason why this file
/// exists: it is the place where a card becomes a [Target].
///
/// Until S390 nothing was sent here at all — `Join` itself chose an
/// address (`oeffentlich ?? nachbar ?? lan`) and went via `rohSenden` past
/// the ladder. That had two consequences, and the second is the
/// worse one:
///
///  1. Of three addresses of a card exactly one carried (§7.1 requires all
///     applicable steps simultaneously).
///  2. If the public address was missing — the normal case behind CGNAT —,
///     the join went to the **neighbour address**. That belongs to a
///     third party. §8.1 FORWARDS via him with `0x20`; a
///     first-contact packet to him himself belongs to no invitation at his side
///     and is discarded. The join failed silently.
extension NodeJoin on Node {
  /// Joins via a card. [introduction] stands in the request (2) and
  /// is what the inviter sees in his question (§15.5).
  Join join(Card card,
      {Identity? forField, Introduction? introduction}) {
    final asValue = forField ?? main;
    late final Join b;
    b = Join(
      me: asValue.postBox,
      card: card,
      send: (p, proof) => _viaTheLadder(b, p, card, asValue, proof),
      report: report,
      introduction: introduction,
    );
    asValue.joins.add(b);
    // EDGE (§8.1): the join's one-time answer code joins the list, and it
    // must be at the fixed neighbour BEFORE the request goes out — the
    // acceptance comes back under it. Missing until S394: the code went
    // with the next cover packet, 25 s after the request (handset, 24.09.).
    codeRoute.codesChanged();
    b.start();
    return b;
  }

  /// Put a first-contact packet on the ladder (§7.1).
  ///
  /// [proof] is the address from which the packet just answered came.
  /// It overrides the LAN role — evidence beats the claim
  /// of the card (`memory.dart`) — and it makes the post box
  /// moot: §8.2 keeps it for a recipient who is OFF,
  /// and whoever has just sent a packet is ON. Without evidence the
  /// post box applies, and if the card is empty too, it is the only route —
  /// exactly as it should be.
  ///
  /// Identifier and code travel ALONG: without the identifier the
  /// post box step cannot deposit, without the code the neighbour step cannot
  /// forward. The target identifier is the fingerprint of the card (§15.2
  /// „The fingerprint is the identifier"); the code is the
  /// first-contact code of the card (proposal M 5.7), which the issuer registers with
  /// his fixed neighbour (S391: registration builds M1).
  void _viaTheLadder(Join b, Uint8List packet, Card card,
      Identity asValue, CardAddress? proof) {
    // A new packet of this join means: the previous one is answered.
    // The five packets form a chain (0 → 2 → 4), each link is the
    // answer to the previous one. Without this line the bundle request (0)
    // would still deposit into three post boxes after [kVersatzBriefkasten], although the
    // bundle (1) has long been there — three deposits with 18 bits of
    // proof of work each (§8.2) for a packet that nobody needs any more.
    _running[b]?.acknowledged();
    // The ONE line that makes the first contact via step 3 measurable: the
    // code under which the issuer should be registered with his fixed neighbour,
    // and whether the card names a neighbour at all —
    // without it the ladder SILENTLY does not plan step 3 (`ladder.dart`,
    // `ziel.nachbar != null && ziel.code != null`). The code prefix is
    // the same under which the issuer registers: this lets both
    // logs be brought together.
    final kn = card.neighbourAddress;
    final where = kn == null
        ? 'NONE — step 3 is dropped'
        : '${InternetAddress.fromRawAddress(kn.address).address}:${kn.port}';
    report('Join: first-contact code '
        '${shortFrom(hexFrom(firstContactCode(card.code)))}, card neighbour $where, '
        'proof ${proof == null ? "none" : "present"}');
    _running[b] = ladder.send(
        packet,
        Target.outDueTo(routesFromCard(card),
            lan: proof,
            identifier: card.fingerprint,
            code: firstContactCode(card.code),
            postBoxApplicable: proof == null));
  }
}

/// The running sending per join. An [Expando] and not a map in the
/// node: the key is weak, so an abandoned join takes
/// its entry with it without anyone having to clean up.
final Expando<Shipment> _running = Expando('running first contact send');
