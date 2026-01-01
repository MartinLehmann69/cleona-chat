import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/first_contact.dart'
    show Join, ContactRequest, Introduction;
import 'package:mycelium/memory.dart' show Contact;
import 'package:mycelium/card.dart';
import 'package:mycelium/card_text.dart';
import 'package:mycelium/node_outside.dart';
import 'package:mycelium/node_join.dart';
import 'package:mycelium/node_invitation.dart';
import 'package:mycelium/node_helpers.dart' show outTheSegment, cardChannel;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_outbound.dart';
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/envelope.dart' show Address;

/// How a contact comes about: issue an invitation, join
/// one, decide a request — always AS the identity of this
/// mailbox.
///
/// A separate file for the same reason as `mailbox_amendment.dart` — the
/// line budget of `mailbox.dart` knows no exception. The cut is
/// the same as one level lower between `node.dart` and
/// `node_invitation.dart`: here stands how a counterpart COMES IN,
/// over there how it is used afterwards.
///
/// It gets by with the public side of [Mailbox]:
/// [Mailbox.node], [Mailbox.identity], [Mailbox.contactRemember],
/// [Mailbox.contactOrNull], [Mailbox.waitFor] and
/// [MailboxOutbound.giveUpAgain].
extension MailboxInvitation on Mailbox {
  /// Issues an invitation and returns card (QR) and invitation text
  /// (copy/paste). [inPerson]: the card is being handed over
  /// face to face right now (NFC, QR on site) — a request
  /// on it is accepted without a second question (§15.5).
  /// [days]/[unlimited] choose the validity (§15.3), [label] the
  /// label for attributing incoming requests (§15.3
  /// "Attribution"). All three only at the issuer — of these the card carries
  /// only the expiry.
  ({Card card, String text}) invitationIssue({
    bool open = false,
    bool inPerson = false,
    int? days,
    bool unlimited = false,
    String label = '',
  }) {
    final (card, _) = node.invite(
        open: open,
        inPerson: inPerson,
        days: days,
        unlimited: unlimited,
        label: label,
        forField: identity);
    invitationsRemember();
    return (card: card, text: asInvitationText(card));
  }

  /// Revokes the invitation with [code] (§15.3): from now on a request
  /// on it is silently rejected, waiting ones are no question any more, and the
  /// revocation is saved — it survives the restart. `false` if no
  /// non-revoked invitation of this identity carries the code.
  bool invitationRevoke(Uint8List code) {
    final e = identity.invitations.toCode(code);
    if (e == null || e.revoke) return false;
    e.withdraw();
    invitationsRemember();
    return true;
  }

  /// §15.3 "Bulk revocation": revokes every not yet revoked
  /// invitation of this identity and saves. Returns their number.
  int allInvitationsRevoke() {
    final n = identity.invitations.allWithdraw();
    invitationsRemember();
    return n;
  }

  /// The contact requests waiting for the user's decision
  /// (§12.5, §15.4), the oldest first. At most 20 per invitation and
  /// 100 on the node; beyond that the oldest falls.
  List<ContactRequest> get contactRequests =>
      node.contactRequestsFor(identity);

  /// The ONE decision about a waiting request — [who] is the
  /// identifier of the requester ([identifierFrom]). Accept: answer (3) with the
  /// own introduction, the requester becomes a contact, its route remembered.
  /// Decline: answer with `0x00`, no contact (§15.5). `false` if no request
  /// from [who] is waiting or the invitation has been consumed in the meantime.
  /// [recontact]: the caller already keeps [who] as an accepted
  /// contact with the same keys (§15.5 re-contact) — the answer goes
  /// out without consuming the invitation (ES-11), even if it has been
  /// consumed in the meantime.
  bool contactRequestDecide(String who,
      {required bool accept, bool recontact = false, Introduction? self}) {
    for (final a in contactRequests) {
      if (identifierFrom(a.who) == who) {
        // S394-11: the own introduction goes into the answer (3), so the
        // requester holds the name at once instead of a placeholder.
        if (self != null) a.invitation.introduction = self;
        final decided = a.invitation
            .decide(a, accept: accept, recontact: recontact);
        // Since S389 the buffer stands inside the invitation (§15.4, E-1) —
        // so the DECISION must be saved too. Without that a
        // declined request would stand there as a question again after the next start;
        // for an acceptance `requestAccepted` already saves, but
        // the rejection has no such path.
        if (decided) invitationsRemember();
        return decided;
      }
    }
    return false;
  }

  /// Joins via a pasted invitation text.
  ///
  /// Two steps, two time scales. Step 1 — fetch bundle, send request —
  /// is a round trip in the network: 5 s, otherwise [MailboxError]. Step 2 — the
  /// answer — comes when the inviter has DECIDED (§12.5), and that
  /// can take hours; there is no deadline for it. The future ends with
  /// the contact, or with [MailboxError] if declined. The
  /// contact is remembered even if nobody is waiting for the future any more.
  ///
  /// A card of the FOREIGN network channel immediately throws [CardChannelError], before
  /// any packet (§15.2).
  ///
  /// [onSent] reports the end of step 1: the bundle is checked,
  /// the request is out, [Address] is the counterpart. Whoever wants to display "request
  /// sent" hooks in HERE and not on the future —
  /// that only ends with the decision (S388). [introduction] stands in the
  /// request so that the inviter knows who is asking (§15.5).
  Future<Contact> join(String text,
      {Introduction? introduction,
      void Function(Address counterpart)? onSent}) async {
    final card = _cardRead(text);
    // The relay list of the read card is remembered (§11.9 "learned from
    // the relay lists of cards it has read") — it has been read here, no matter
    // how the join turns out.
    host.relayRemember(card.relay);
    // ALL addresses of the card become neighbours (§11.8 source 3: "the
    // addresses and relays carried in the card") — IMMEDIATELY, not only after
    // a successful join: precisely whoever does not reach the inviter directly
    // (cellular) needs the others. Until S388 only the
    // neighbour address; but the inviter is itself a node that
    // holds post boxes. Only IPv4 is remembered (like the neighbourhood),
    // the own address never (`neighbourAdd`). Remembered here also means
    // restart-proof: every new neighbour is saved immediately (source 1).
    // S390: three fixed roles became the neighbour address plus the
    // issuer's address list (§15.2). EVERYTHING is entered that
    // `Neighbourhood.possible` lets through — which of them lies in the own
    // segment does not matter here: a neighbour is a neighbour.
    for (final a in [card.neighbourAddress, ...card.ownAddresses]) {
      // S390: here stood `a.typ == KarteAdressTyp.ipv4`. A card with
      // IPv6 addresses is per §15.2 a completely ordinary card ("an
      // IPv6 LAN address next to an IPv4 public address is an ordinary
      // card, not a special case") — from it ZERO neighbours were entered until then,
      // without a message. What is unfit is rejected by
      // `Neighbourhood.possible`, and with a reason.
      if (a != null) host.neighbourRemember(a.address, a.port);
    }
    final result = Completer<Contact>();
    // A rejection that nobody is waiting for any more is not a crash.
    result.future.ignore();
    final joining = node.join(card,
        forField: identity, introduction: introduction)
      ..onCompletion = (b) => unawaited(_complete(b, card, result));
    final sent = await waitFor(
        () => joining.counterpart != null || joining.declined,
        const Duration(seconds: 5));
    final counterpart = joining.counterpart;
    if (!sent || counterpart == null) {
      throw MailboxError('Join did not come about '
          '(no bundle from the other side)');
    }
    onSent?.call(counterpart);
    return result.future;
  }

  /// Reads the card in the own channel ([cardChannel]). The text reader
  /// deliberately wraps a channel error as `wrongVersion`
  /// (`card_text.dart`, "Deliberately NO sixth error kind"). Only on this
  /// error path is it therefore re-read in the foreign channel: if that succeeds, it is
  /// a card of the other network, and [CardChannelError] says so by
  /// name — without evaluating the message text.
  Card _cardRead(String text) {
    try {
      return outInvitationText(text, expectedChannel: cardChannel);
    } on CardTextError catch (error) {
      if (error.kind != CardTextErrorKind.wrongVersion) rethrow;
      final foreign =
          cardChannel == Card.channelLive ? Card.channelBeta : Card.channelLive;
      final Card inForeign;
      try {
        inForeign = outInvitationText(text, expectedChannel: foreign);
      } on CardTextError {
        // Not readable in the foreign channel either: a really foreign version.
        throw error;
      }
      throw CardChannelError(inForeign.channel, cardChannel);
    }
  }

  Future<void> _complete(
      Join b, Card card, Completer<Contact> result) async {
    final counterpart = b.counterpart;
    if (b.declined || !b.done || counterpart == null) {
      if (!result.isCompleted) {
        result.completeError(MailboxError('Join refused'));
      }
      return;
    }
    // ALL THREE addresses of the card are remembered (§15.2 → §6.3
    // `cardAddresses`, §7.1 "up to three addresses ... from the card"). Until
    // S390 ONE was selected here and the other two
    // irretrievably discarded; the ladder in the application therefore had
    // only step 1 (finding B-1).
    //
    // Since S390 the PROVEN route is no longer a third selection from the
    // card, but the address from which the answer (3) really came
    // ([Join.provenRoute]). `memory.dart` keeps `letzteIpv4` as
    // evidence — "a packet came from there" —, and a card address is a
    // claim. Until S390 the same wrong choice stood here as in
    // `first_contact.dart` (`oeffentlich ?? nachbar ?? lan`, finding B2-4):
    // behind CGNAT the address of a THIRD party thereby wandered into the
    // evidence role of the contact.
    //
    // S390: the type filter `beleg.typ == ipv4` has fallen here. It was the
    // precondition of a builder that threw at 16 bytes; since version
    // 12 `memory.dart` keeps the evidence typed (§6.3).
    final proof = b.provenRoute;
    contactRemember(counterpart,
        ip: proof?.address,
        port: proof?.port,
        cardsAddresses: card.ownAddresses,
        neighbours: card.neighbourAddress == null ? null : [card.neighbourAddress!],
        pairRandom: b.pairRandom, // proposal M: s_AB from the acceptance
        // S394-11: the name from the introduction in answer (3) — until then
        // the requester showed a placeholder until a later profile message.
        displayName: (b.counterpartIntroduction?.name ?? '').isEmpty
            ? null
            : b.counterpartIntroduction!.name);
    // EDGE (§8.1): the same reason as in `mailbox_pair.dart` — the code
    // contact→me exists only now, and the answer comes immediately.
    node.codeRoute.codesChanged();
    // EDGE: the same case as with an accepted request, only from the
    // joining side. Whoever already wrote before the join
    // should not wait until the next start. WITHOUT a condition: §8.2 carries
    // even without any address, and `giveUpAgain` knows the case
    // (`mailbox_outbound.dart`, finding B-2).
    giveUpAgain(only: counterpart);
    // EDGE "new contact" (proposal M §8.2): the own day keys.
    dayKeyDistribute(only: counterpart);
    // If the answer came from OUTSIDE the own segment, then someone stands there
    // right now who can say how one looks from outside oneself —
    // and that is the only way to get to the own public address.
    // In the LAN the question is not even asked: a neighbour in the same
    // segment only sees the LAN address.
    //
    // S390: here stood `istIpv4 && !istPrivat(…)`. Both were wrong. The
    // type filter never let a node that reaches its inviter via IPv6
    // ask for its own address — and §11.4 makes
    // this question the ONLY way there. `isPrivate` was moreover a
    // proxy: the comment above says "outside the own
    // segment", but `isPrivate` answers the other question ("is this fit
    // as a public address in a card", as its own
    // comment in `node_helpers.dart` also says) and returns `false` for EVERY 16 B address.
    // Now the function is asked that really carries the statement
    // and knows `fe80::/10`, `fc00::/7` and `169.254/16`.
    if (proof != null &&
        !outTheSegment(InternetAddress.fromRawAddress(proof.address))) {
      final learned = await node.publicAddressLearn(
          InternetAddress.fromRawAddress(proof.address), proof.port);
      // Edge for source 4 (§11.9): an own entry follows the address.
      if (learned != null) host.addressLearned();
    }
    if (!result.isCompleted) {
      result.complete(contactOrNull(identifierFrom(counterpart))!);
    }
  }
}
