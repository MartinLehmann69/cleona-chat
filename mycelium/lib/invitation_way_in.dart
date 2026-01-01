/// When an invitation is shown (V4.2 §12.4, owner decision 06.10.2026,
/// version B).
///
/// An invitation — QR code, NFC exchange, out-of-band invitation — is shown
/// once its invitation data carry a way in from the open network. Until then
/// the device waits, at most [kWayInWaitAtMost]; after that the front end
/// says so and offers it anyway, labelled "same W/LAN only".
///
/// ── WHAT COUNTS AS A WAY IN (the narrowest reading of §12.4) ──────────────
///
/// * **An own address reachable from the open network**: an own address the
///   invitation data carry, of a class reachable from outside
///   ([fromOutsideReachable]), whose reachability is EVIDENCED — its family
///   found open by the open check of §8.1 (`open_check.dart`), a mapping or
///   pinhole the router granted (§7.3), or the board's proof (§11.8a). The
///   same evidence that makes a desktop a holder (`reachableEvidenced`,
///   `host_media.dart`). A global IPv6 address alone says nothing about a
///   firewall (§11.8a), and an address confirmed from outside answers behind
///   a translator only whom it asked — neither is a way in by itself.
/// * **The verified invitation neighbour**: the invitation data name it
///   (§15.2: answered under that address in this run, reachable from the
///   open network, never a contact's device — [invitationNeighbourNow]),
///   AND it confirmed holding the invitation's first-contact code with a
///   `0x25` (§15.2: "registers it with its fixed neighbour before the
///   invitation leaves the device"; `RegistrationSend.holds`).
///
/// ── HOW IT WAITS ─────────────────────────────────────────────────────────
///
/// No clock on the network, no polling (working rule 5). The invitation is
/// looked at again at local edges only: a neighbour confirmed (that includes
/// every `0x25`, `Neighbourhood.observe`), a family found open
/// (`HostNetwork`, `OpenCheck.onOpen`) and a router mapping granted (the app
/// seam). [wayInEdge] is that one edge. The one timer is local: the 30 s of
/// §12.4.
///
/// When the way in appears, the card is rebuilt from the SAME invitation —
/// same code, expiry, keys — with the current addresses and neighbour, and
/// that is what is shown (`berichte/S405-ERSTKONTAKT-GESAMTANALYSE.md` E-2:
/// a card computed once before the neighbour answered stayed without it).
library;

import 'dart:async';
import 'dart:io';

import 'package:mycelium/board_node.dart' show NodeAnswer;
import 'package:mycelium/bundle.dart' show lineBundleBuild;
import 'package:mycelium/card.dart';
import 'package:mycelium/card_text.dart';
import 'package:mycelium/host_media.dart' show bulkFamilyOpen;
import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/neighbourhood_card.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show cardFor, hexFrom;
import 'package:mycelium/node_invitation.dart';
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;
import 'package:mycelium/own_entries.dart' show cardOwnAddresses;
import 'package:mycelium/pair.dart' show firstContactCode;

/// §12.4: "Until such invitation data can be made, the device shows a waiting
/// indicator — at most 30 s."
const Duration kWayInWaitAtMost = Duration(seconds: 30);

/// The way in invitation data carry (§12.4).
enum WayIn { ownAddress, invitationNeighbour }

/// The invitation neighbour as invitation data may name it NOW (§15.2): of
/// the card's seat the address that answered in this run, reachable from the
/// open network, never a contact's device (`neighbourhood_card.dart`).
CardAddress? invitationNeighbourNow(Node k) =>
    cardSeatForStrangers(k.neighbourhood)?.cardAddress((a) =>
        k.readiness.responding.contains(a.key) &&
        k.neighbourhood.openNetwork(a.address));

/// The way in [card] of [p] carries — `null` if none (see the head).
WayIn? invitationWayIn(Mailbox p, Card card) {
  final k = p.node;
  final proven = k.board?.reachableProven ?? false;
  for (final a in card.ownAddresses) {
    final ip = InternetAddress.fromRawAddress(a.address);
    if (fromOutsideReachable(ip) &&
        (proven || bulkFamilyOpen(p.host.network, ip.type))) {
      return WayIn.ownAddress;
    }
  }
  final named = card.neighbourAddress;
  final seat = cardSeatForStrangers(k.neighbourhood);
  if (named != null &&
      seat != null &&
      seat.knows(named) &&
      k.codeRoute.registration.holds(seat, firstContactCode(card.code))) {
    return WayIn.invitationNeighbour;
  }
  return null;
}

/// The local edge "a way in may have appeared" for [k] (see the head).
void wayInEdge(Node k) {
  for (final look in List.of(_watchers[k] ?? const <void Function()>{})) {
    look();
  }
}

final Expando<Set<void Function()>> _watchers = Expando('way-in watchers');

Set<void Function()> _watchersOf(Node k) {
  var s = _watchers[k];
  if (s == null) {
    s = _watchers[k] = {};
    // Once per node: `observe` keeps its listeners for the node's life.
    k.neighbourhood.observe(removed: (_) {}, onConfirmed: (_) => wayInEdge(k));
  }
  return s;
}

/// A card and its out-of-band line, with the way in it carries.
typedef WayInCard = ({Card card, String text, WayIn? way});

extension MailboxWayIn on Mailbox {
  /// The out-of-band line of [card] for [e] (§15.6): the card, `pk_inv` and
  /// the key bundle, signed by the identity, with the rotation chain.
  String invitationLine(Card card, inv.Invitation e) {
    final me = identity.postBox;
    final pkInv = e.box!.pk; // random per invitation (E-A4)
    final bundle = lineBundleBuild(me.address, e.kem!.mlKemPk);
    return asInvitationLine(card, pkInv, bundle,
        me.signEd25519(lineSignedData(card, pkInv, bundle)),
        chain: me.address.chain.toWire());
  }

  /// The card of [e] as it would be issued NOW — same invitation, current
  /// own addresses and neighbour (§15.2). Changes nothing.
  Card _cardNow(inv.Invitation e) => cardFor(identity, e, cardOwnAddresses(node),
      neighbour: invitationNeighbourNow(node), relay: node.knownRelay);

  /// Waits until the invitation data of [e] carry a way in (§12.4) and
  /// returns the card rebuilt with it — at once if they already do; after
  /// [within] the card as it stands then, with `way` `null`. The neighbour it
  /// names becomes the invitation's (S394 V6: the seat keeps it while the
  /// invitation stands) and is saved — without a new registration: the code
  /// list did not change.
  Future<WayInCard> invitationWayInAwait(inv.Invitation e,
      {Duration within = kWayInWaitAtMost}) {
    final done = Completer<WayInCard>();
    final watchers = _watchersOf(node);
    Timer? clock;
    late final void Function() look;
    void finish(Card card, WayIn? way) {
      if (done.isCompleted) return;
      clock?.cancel();
      watchers.remove(look);
      final before = e.cardNeighbour;
      final after = card.neighbourAddress;
      if (!(before == null ? after == null : after != null && before.equal(after))) {
        e.cardNeighbour = after;
        invitationsRemember(codes: false);
      }
      node.report('Invitation ${hexFrom(e.code).substring(0, 8)}: '
          '${way == null ? 'no way in from the open network within ${within.inSeconds} s' : 'way in ${way.name}'}'
          ' — neighbour ${after ?? 'none'}');
      // Revoked during the wait (the view closed, S406-QR2): `withdraw` has
      // dropped `pk_inv` and the key bundle — there is no line any more, and
      // building one threw out of the way-in edge (`e.box!`).
      done.complete(
          (card: card, text: e.revoke ? '' : invitationLine(card, e), way: way));
    }

    look = () {
      if (e.revoke) return finish(_cardNow(e), null);
      final card = _cardNow(e);
      final way = invitationWayIn(this, card);
      if (way != null) finish(card, way);
    };
    watchers.add(look);
    clock = Timer(within, () {
      final card = _cardNow(e);
      finish(card, e.revoke ? null : invitationWayIn(this, card));
    });
    look();
    return done.future;
  }
}
