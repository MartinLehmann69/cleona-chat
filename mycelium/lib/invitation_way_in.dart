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
/// ── ASKING THE SEAT ONCE (owner decision 09.10.2026, A) ─────────────────
///
/// An address counts as answering only after it answered a request of THIS
/// node (W8, S391); a packet that merely arrives does not confirm it. At home
/// the seat may be reached only over its private address — the one that
/// worked last (§6.2) — while its global IPv6 address, reachable from the open
/// network, is used only when the seat calls this node, and so is never
/// confirmed (`berichte/S407-IPV6-STUMM.md`). Before giving up, the wait
/// therefore asks ONCE over each address of the seat that is reachable from
/// the open network but not confirmed in this run, with the address question
/// `0x40` the stale-entry try of §11.8 uses (`host_network.dart` `staleTry`):
/// its answer confirms the address (`outsideRoute.onAnswerReceived`), which is
/// the edge [wayInEdge] above. At most [kWayInSeatAsksAtMost] requests per
/// wait — one per user action, no clock, no repetition. Silence is no use
/// failed (§11.8): the address stays as it was.
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
import 'package:mycelium/neighbour_keys.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show cardFor, hexFrom;
import 'package:mycelium/node_invitation.dart';
import 'package:mycelium/node_outside.dart' show NodeOutside;
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;
import 'package:mycelium/own_entries.dart' show cardOwnAddresses;
import 'package:mycelium/pair.dart' show firstContactCode;

/// §12.4: "Until such invitation data can be made, the device shows a waiting
/// indicator — at most 30 s."
const Duration kWayInWaitAtMost = Duration(seconds: 30);

/// At most this many requests a wait sends to its seat (one per address family
/// a card can name — IPv4 and IPv6; owner decision 09.10.2026: at most
/// 2 × 1200 B per attempt).
const int kWayInSeatAsksAtMost = 2;

/// The way in invitation data carry (§12.4).
enum WayIn { ownAddress, invitationNeighbour }

/// The invitation neighbour as invitation data may name it NOW (§15.2): of
/// the card's seat the address that answered in this run, reachable from the
/// open network, never a contact's device (`neighbourhood_card.dart`).
CardAddress? invitationNeighbourNow(Node k) {
  final seat = cardSeatForStrangers(k.neighbourhood);
  final a = seat?.cardAddress((a) =>
      k.readiness.responding.contains(a.key) &&
      k.neighbourhood.openNetwork(a.address));
  // S407 a': with the record key the seat named, so a reader whose address
  // has gone silent looks the current one up (§11.9).
  return seat == null || a == null ? a : k.keyedOf(seat, a);
}

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

/// Asks the card's seat ONCE over each of its addresses that is reachable from
/// the open network and not confirmed in this run (see the head) — at most
/// [kWayInSeatAsksAtMost]. Returns how many requests went out.
int wayInSeatAsk(Node k) {
  final seat = cardSeatForStrangers(k.neighbourhood);
  if (seat == null) return 0;
  final responding = k.readiness.responding;
  var asked = 0;
  for (final a in seat.addresses) {
    if (asked == kWayInSeatAsksAtMost) break;
    if (!k.neighbourhood.openNetwork(a.address)) continue;
    if (responding.contains(a.key)) continue;
    if (!k.speaks(a.address)) continue;
    asked++;
    unawaited(k.outsideRoute.whatIsMyAddress(a.address, a.port));
  }
  if (asked > 0) {
    k.report('Invitation: asked the seat once over $asked unconfirmed '
        'open-network address(es)');
  }
  return asked;
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
      neighbour: invitationNeighbourNow(node), relay: node.knownRelay,
      publisherKey: node.publisherKey); // as `invitationIssue`: §15.2, §11.9

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
    // Not shown yet: ask the seat once over its unconfirmed open-network
    // addresses (owner decision 09.10.2026, A; see the head).
    if (!done.isCompleted && !e.revoke) wayInSeatAsk(node);
    return done.future;
  }
}
