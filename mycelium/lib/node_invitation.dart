
import 'dart:typed_data';

import 'package:mycelium/neighbourhood_card.dart';
import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/first_contact.dart';
import 'package:mycelium/identity.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/neighbourhood.dart' show Neighbour;
import 'package:mycelium/own_entries.dart' show cardOwnAddresses;
import 'package:mycelium/node_helpers.dart';
import 'package:mycelium/ladder.dart' show Shipment;
import 'package:mycelium/envelope.dart' show Address;

/// Is asked before a contact request is accepted. [to] is the
/// identity whose invitation the request answers; [origin] the
/// network address from which it arrived — without it the inviting side learns
/// no route back (see [Invitation.ask]). `null` = later (§12.5).
///
/// Lives here and not in `node.dart`: the question arises on the
/// invitation side, and it is answered there too.
typedef OnRequest = bool? Function(Address to, Address who, CardAddress origin);

/// The invitation side of the node — issue a card, join via a
/// card.
///
/// Its own file for the same reason as `node_amendment.dart`: the
/// line budget of `node.dart` knows no exception. The cut is
/// not arbitrary — here is how a contact COMES ABOUT,
/// over there, how it is used afterwards.
///
/// It gets by with the public side of [Node]: [Node.main],
/// [Node.port], [Node.rawSend], [Node.report],
/// [Node.onRequest]; the interfaces come from `node_helpers.dart`.
extension NodeInvitation on Node {
  /// Issues an invitation and returns the card.
  ///
  /// Throws [StateError] as long as ANOTHER identity of this node has a
  /// standing invitation (F-1, V4.2 §15.3: "on one node they all belong
  /// to one identity"). Reason: the bundle request (0) names no identity,
  /// the node could not know whose bundle it sends. The remedy is
  /// revoking the other ones.
  ///
  /// [inPerson]: the card is handed over face to face
  /// (NFC, QR on site) — a request for it carries the mark
  /// ([ContactRequest.inPerson]), and the application accepts it without
  /// a second question (§15.5); mycelium itself does not decide. A
  /// property of the invitation at the issuer, not of the card; it is stored
  /// in memory (ES-12) and is only permitted for the single kind.
  /// [days]/[unlimited]: the validity from §15.3 ("Selectable 7 d / 30 d /
  /// 90 d / unlimited; default 90 d for the single kind, 7 d for the open
  /// kind"). `days` `null` and `unlimited` `false` means: the default of the
  /// kind. Until S390 this place passed neither on, although
  /// `Invitation.forOnePerson`/`openDistributed` already accepted `days` —
  /// the UI offered all four values and the service rejected three of them.
  ///
  /// [label]: by which the issuer recognises this invitation (§15.3
  /// "Attribution"). Only at him, never in the card, never on the wire.
  (Card, inv.Invitation) invite({
    bool open = false,
    bool inPerson = false,
    int? days,
    bool unlimited = false,
    String label = '',
    Identity? forField,
  }) {
    if (open && inPerson) {
      throw ArgumentError('a personally handed-over invitation is '
          'single-use (§15.5)');
    }
    final asValue = forField ?? main;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final other in identities) {
      if (identical(other, asValue) || !standsOneInvitation(other, now)) {
        continue;
      }
      throw StateError('on this node there are invitations of the identity '
          '${other.identifierHex.substring(0, 8)} — revoke those first '
          '(§15.3: a bundle request names no identity)');
    }
    final e = open
        ? inv.Invitation.openDistributed(
            days: days, unlimited: unlimited, label: label)
        : inv.Invitation.forOnePerson(
            inPerson: inPerson,
            days: days,
            unlimited: unlimited,
            label: label);
    asValue.invitations.admit(e);
    // S392: the neighbour is the FIXED one (§15.2, W7), and "confirmed" is
    // ASKED, not assumed (§22.7.1) — `fixed` survives the restart, the
    // proof does not. Why no falling back to another one, and what a card
    // without a neighbour costs: `berichte/S392-FIX-NACHBARSCHAFT.md`.
    // S394 V4: of the fixed NODE the address that answered in this run.
    // V7: NEVER a private one — only one reachable from the open network
    // (`Neighbourhood.openNetwork`); without it the card names no neighbour.
    // And never a contact's device (proposal 6.5, `neighbourhood_card.dart`).
    final firstNeighbour = cardSeatForStrangers(neighbourhood)?.cardAddress((a) =>
        readiness.responding.contains(a.key) &&
        neighbourhood.openNetwork(a.address));
    e.cardNeighbour = firstNeighbour; // V6: the seat keeps it while e stands
    // The own addresses (§15.2, §22.6), the confirmed public one in front,
    // only of own address families (§11.1 V1) — `own_entries.dart`.
    final addresses = cardOwnAddresses(this);
    final card = cardFor(
      asValue,
      e,
      addresses,
      neighbour: firstNeighbour,
      relay: knownRelay,
    );
    _waitingCreate(asValue, e);
    return (card, e);
  }

  /// Resumes an invitation from memory (S388, ES-7/B3):
  /// into the list of the identity (revocation, cap, F-1 see it) and as
  /// waiting invitation on the wire — a card given yesterday is
  /// answered today. With it come back the requests that wait for the
  /// user's decision (§15.4, E-1).
  ///
  /// The cap is NOT drawn here as when issuing — it was already
  /// standing when it was issued —, but F-1 is checked
  /// ([_reasonAgainstState]): whatever MAY no longer stand on this node
  /// comes back revoked, visible and revocable again (§15.3).
  /// Until S389 this check ran only when issuing, and two identities
  /// from separate runs then stood side by side (ES-S388-1).
  void invitationRestore(Identity asValue, inv.Invitation e) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final reason =
        e.validAt(now) ? _reasonAgainstState(this, asValue, now) : null;
    if (reason != null) {
      e.withdraw();
      report('Invitation from the last run revoked: $reason');
    }
    asValue.invitations.resume(e);
    _waitingCreate(asValue, e);
    // The node cap also applies to what just came from disk.
    _totalCap();
  }

  /// The waiting invitation for [e] — ONE path for issued and
  /// restored ones. It reads the state (kind, counter, revocation, in person)
  /// from [e] itself, not from a copy (B2, B4).
  void _waitingCreate(Identity asValue, inv.Invitation e) {
    final to = asValue.postBox.address;
    final waiting = Invitation(
      me: asValue.postBox,
      code: e.code,
      expiryUnixSeconds: e.expiryUnixSeconds,
      // The same number as in the card (§15.5.1) — until S388 it was missing here,
      // and an open invitation (22) was checked with the default 20.
      difficulty: e.difficulty,
      entry: e,
      send: (p, target) => rawSend(p, target),
      // Already a contact with the same keys: answer without question and without
      // consumption (§15.5 re-contact, ES-11). An OWN callback, not
      // `onRequest == true`: there `true` means „accept" (`OnRequest`).
      recontact: (who, origin) =>
          _onRecontact[this]?.call(to, who, origin) ?? false,
      // The node ALWAYS asks upwards; `null` means it is decided up there
      // (§12.5). Even a card handed over in person
      // does not decide here: the request carries the mark
      // ([ContactRequest.inPerson]), and the application accepts it without
      // a second question (§15.5). Until S388 mycelium accepted it itself — the
      // app learned nothing of it and did not keep the contact (measured,
      // S388-BAU-KONTAKT G; product rule 15.09.: mycelium makes nobody a
      // contact).
      ask: (who, origin) => onRequest(to, who, origin),
      onAccepted: (who, origin) =>
          _onAccepted[this]?.call(to, who, origin),
      acceptanceSend: (p, origin, who) => _acceptanceRoute(p, origin, who, to),
      onBuffered: (a) {
        _totalCap();
        _onContactRequest[this]?.call(to, a);
      },
      report: report,
    );
    asValue.open[hexFrom(e.code)] = waiting;
    _issued[waiting] = _nextNumber++;
  }

  /// Give an arriving first-contact packet to the join or the
  /// invitation it BELONGS to — not to the first open
  /// state of any identity (until S385, W1.a.4).
  ///
  /// By what it is recognisable, measured per packet:
  ///  * (1) bundle — by the 16 random bytes of the join;
  ///  * (2) request — by the proof of computation, which is bound to the code;
  ///  * (3) answer, (4) receipt — by the seal: to whom sealed, by whom
  ///    signed. The trial unsealing changes no state.
  ///  * (0) bundle request — by NOTHING. Per document the packet is 17/40/52 B without
  ///    identity (v42 ch15 §15.1). See [_bundleFor].
  ///
  /// If nothing fits, it is reported, not guessed.
  ///
  /// [origin] is WHERE the packet came from; [returnRoute] the same, but only
  /// when the address belongs to the COUNTERPART — with a forwarded
  /// (§8.1) or collected (§8.2) packet it belongs to the third party
  /// (`assign`, `withoutReturnRoute`). The [Join] therefore gets
  /// [returnRoute] and not [origin]: from it, it remembers the only evidence
  /// it has about the route to the counterpart.
  void firstContact(Uint8List data, CardAddress origin,
      [CardAddress? returnRoute]) {
    final kind = PacketKind.fromCode(data[0]);
    for (final i in identities) {
      for (final b in i.joins) {
        if ((kind == PacketKind.bundle && b.expectedBundle(data)) ||
            (kind == PacketKind.answer && b.answerFits(data))) {
          b.receive(data, returnRoute);
          return;
        }
      }
      for (final e in i.open.values) {
        if (kind == PacketKind.request && e.fitsProofOfWork(data)) {
          e.receive(data, origin);
          return;
        }
        final from = kind == PacketKind.receipt ? e.receiptFrom(data) : null;
        if (from != null) {
          e.receive(data, origin);
          // The receipt (4) proves: the acceptance has arrived — its
          // sending ends, more expensive steps no longer send (ES-6).
          _acceptances[this]?.remove(hexFrom(from.identifier))?.acknowledged();
          return;
        }
      }
    }
    if (kind == PacketKind.bundlePlea) {
      final e = _bundleFor();
      if (e != null) {
        e.receive(data, origin, forwarded: returnRoute == null); // §15.5 way back
        return;
      }
    }
    report('First contact packet ${kind?.name ?? data[0]} belongs to no '
        'joining and no invitation — discarded');
  }

  /// Whose bundle an anonymous bundle request (0) gets: that of the LAST
  /// issued invitation that still accepts; if there is none, that of the
  /// last issued one that is not revoked (a used-up one
  /// is needed for re-contact). A revoked one gets nothing —
  /// not even a bundle (§15.3).
  ///
  /// **This is not an assignment but a choice** — the packet carries
  /// nothing by which it could be checked. Since S387 (F-1) a node can
  /// no longer carry two identities with a STANDING invitation
  /// ([invite]); among the open ones, however, there may be revoked or
  /// expired ones of an earlier identity. They are older than every
  /// standing one, so the youngest wins. Whoever joins via such an old card
  /// gets the wrong bundle and rejects it by the fingerprint.
  /// The alternatives (send every bundle: reveals the number and the
  /// bundles of all identities; format change: contradicts §15.1) are
  /// owner decisions, `berichte/S385-SCHNITT-F.md`.
  Invitation? _bundleFor() {
    Invitation? open;
    Invitation? any;
    for (final i in identities) {
      for (final e in i.open.values) {
        if (e.revoke) continue;
        final n = _issued[e] ?? -1;
        if ((_issued[any ?? e] ?? -1) <= n) any = e;
        if (e.accepts && (_issued[open ?? e] ?? -1) <= n) open = e;
      }
    }
    return open ?? any;
  }

  /// The waiting contact requests to [i], the oldest first (§15.4).
  List<ContactRequest> contactRequestsFor(Identity i) =>
      [for (final e in i.open.values) ...e.waiting]
        ..sort((a, b) => a.at.compareTo(b.at));

  /// Who learns of an ACCEPTED request — immediately or later.
  /// [an] is the inviting identity. Set by the host.
  set onAccepted(
          void Function(Address to, Address who, CardAddress origin)? f) =>
      _onAccepted[this] = f;

  /// Is [wer] already a contact of [an] with the same keys (§15.5
  /// re-contact)? Then answer without question and without consumption (ES-11). Set by
  /// the host.
  set onRecontact(
          bool Function(Address to, Address who, CardAddress origin)? f) =>
      _onRecontact[this] = f;

  /// Who learns of a WAITING request — the question to the user
  /// (§12.5). Set by the host.
  set onContactRequest(void Function(Address to, ContactRequest a)? f) =>
      _onContactRequest[this] = f;

  /// ES-6 (a), owner decision 15.09.2026: the acceptance (3) goes via the
  /// ladder — directly to [origin] first, after the offset of the ladder into the
  /// post box under the identifier of [who], which has been known since the request.
  /// Until S388 it went ONCE directly to [origin]; behind NAT the
  /// mapping expired, and the joiner never sends again (§5.3). The
  /// receipt (4) ends the sending ([firstContact]). No timer of its own.
  void _acceptanceRoute(
      Uint8List p, CardAddress origin, Address who, Address to) {
    final open = _acceptances[this] ??= {};
    open.remove(hexFrom(who.identifier))?.giveUp(); // the newer one replaces it
    open[hexFrom(who.identifier)] = answerViaLadder(p, origin, who, to);
    // Bounded like the buffer: without a receipt an entry stays.
    while (open.length > inv.kBufferTotal) {
      open.remove(open.keys.first);
    }
  }

  /// §15.4: at most [inv.kBufferTotal] waiting ones on the node, across all
  /// identities and invitations; beyond that the oldest drop, without
  /// answer. Displace, never block.
  void _totalCap() {
    final all = [for (final i in identities) ...contactRequestsFor(i)]
      ..sort((a, b) => a.at.compareTo(b.at));
    for (var n = all.length - inv.kBufferTotal; n > 0; n--) {
      final a = all.removeAt(0);
      a.invitation.drop(a);
    }
  }

  /// The relays this node knows (V4.2 §11.9) — the own card
  /// carries them ([invite]). Set by the host: configured ones first, then
  /// those from read cards. Only fit ones are kept, without duplicates, at most three
  /// (§15.2) — an unfit entry must not blow up the issuing.
  List<String> get knownRelay => _relay[this] ?? const [];
  set knownRelay(List<String> r) => _relay[this] = List.unmodifiable(
      {for (final x in r) if (relayShortage(x) == null) x}
          .take(Card.relayAtMost));
}

final Expando<List<String>> _relay = Expando('relays');

/// Why a restored invitation may no longer STAND on this node
/// — or `null` if nothing speaks against it (F-1 at start).
///
/// Two reasons, both from §15.3/§15.12: ANOTHER identity already has
/// standing invitations („on one node they all belong to one identity" —
/// a bundle request names no identity, the node could not
/// know whose bundle it sends), or the stock of this identity
/// is at the cap of [inv.kAtMostStanding] („standing invitations per
/// node: max. 10"). The identity registered first keeps its cards;
/// that is the device's one (`Host.start`), and the order is thus
/// not random but that of registration.
String? _reasonAgainstState(Node k, Identity asValue, int now) {
  for (final i in k.identities) {
    if (identical(i, asValue) || !standsOneInvitation(i, now)) continue;
    return 'invitations of the identity '
        '${i.identifierHex.substring(0, 8)} stand on this node (§15.3: a bundle request names '
        'no identity)';
  }
  if (asValue.invitations.standing(now: now).length >=
      inv.kAtMostStanding) {
    return 'there are already ${inv.kAtMostStanding} invitations standing (§15.12)';
  }
  return null;
}

/// Does [i] have a STANDING invitation? The same predicate as the cap of
/// ten ([inv.Invitations.standing]: not revoked, not expired,
/// not used up) — one word, one meaning. Those from the last run
/// count too, because since S388 they are in the same list.
bool standsOneInvitation(Identity i, int now) =>
    i.invitations.standing(now: now).isNotEmpty;

/// S394 V6: did the card of a STANDING invitation of [k] name one of [n]'s
/// addresses? Its readers hold it; the seat stays (`neighbourhood_seat.dart`).
bool namedByStandingCard(Node k, Neighbour n) => k.identities.any((i) => i
    .invitations
    .standing(now: DateTime.now().millisecondsSinceEpoch ~/ 1000)
    .any((e) => e.cardNeighbour != null && n.knows(e.cardNeighbour!)));

/// ES-9 (owner decision 15.09.2026, V4.2 §15.4 point 2 „This invitation is
/// at its buffer limit"): the buffer of THIS invitation is full, the next
/// request displaces the oldest. A getter, not a packet. A revoked one
/// has no waiting ones ([Invitation.waiting]) and therefore never stands at it.
/// The node cap [inv.kBufferTotal] does not count here — §15.4 point 2 names
/// the invitation.
extension InvitationBuffer on Invitation {
  bool get atBufferThreshold => waiting.length >= inv.kBufferPerInvitation;
}

/// Order of issuing, across nodes and only local — the
/// only basis for [NodeInvitation._bundleFor].
final Expando<int> _issued = Expando<int>('issued');
int _nextNumber = 0;

/// The callbacks of the host per node — next to the node instead of in it:
/// `node.dart` is at the line budget.
final Expando<void Function(Address, Address, CardAddress)> _onAccepted =
    Expando('onAccepted');
final Expando<void Function(Address, ContactRequest)> _onContactRequest =
    Expando('onContactRequest');
final Expando<bool Function(Address, Address, CardAddress)>
    _onRecontact = Expando('onRecontact');

/// Running acceptance sendings per node: identifier (hex) of the joiner →
/// sending (ES-6). Next to the node for the same reason as the callbacks.
final Expando<Map<String, Shipment>> _acceptances = Expando('acceptances');
