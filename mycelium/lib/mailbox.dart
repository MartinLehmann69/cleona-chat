/// The mailbox — ONE identity with everything that belongs only to it:
/// post box, contacts, histories, running shipments, re-dispatch,
/// invitations, groups. The rest (wire, fixed port, neighbourhood,
/// cover stream, ladder, storage for third parties, state checker) is held by the
/// [Host], once for all mailboxes (V4.2 §4.5.1, S385 cut F).
///
/// A caller that serves an identity needs only THIS class. The mailboxes
/// are separate because two identities of the same human must not be
/// connected (`identity.dart`) — a mailbox never asks another's contacts.
///
/// RESTART: post box + contacts lie in the mailbox's [Memory], every own
/// message that is still open in the peer's [History] (`history.dart`), the
/// identifier of every received one in the identity's received memory
/// (§20.2). A message neither receipted nor placed at stopping stands as
/// open there AND goes back onto the ladder (§9.3).
///
/// WHERE A ROUTE COMES FROM: exactly three sources, and there should not be more
/// — every further one could learn a wrong address. (1)
/// [join]: the address stood in the pasted card. (2) the
/// request at the inviter ([requestAccepted]): the joiner dialled the
/// card itself, the packet came directly. (3) a find of the
/// search call in the own segment (call D, S385). NOT fit as a source is an
/// arbitrary incoming message: passed on or fetched from a post box,
/// its sender address does not belong to the contact (`P14-dienst.md`).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/address_class.dart' show routesToContact;
import 'package:mycelium/first_contact.dart' show ContactRequest;
import 'package:mycelium/memory.dart';
import 'package:mycelium/group.dart';
import 'package:mycelium/identity.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_invitation.dart' show NodeInvitation;
import 'package:mycelium/invitation_face_to_face.dart' show MailboxFaceToFace;
import 'package:mycelium/media.dart';
import 'package:mycelium/message.dart' show Outbound, Inbound;
import 'package:mycelium/mailbox_parked.dart' show parkedAttach;
import 'package:mycelium/amendment.dart' show Edit, ReadMark, Reaction;
import 'package:mycelium/first_contact_pair.dart' show CodeSend;
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/mailbox_first_contact.dart';
import 'package:mycelium/mailbox_book.dart';
import 'package:mycelium/mailbox_history.dart';
import 'package:mycelium/mailbox_start.dart';
import 'package:mycelium/envelope.dart';
import 'package:mycelium/history.dart';
import 'package:mycelium/host.dart';
import 'package:mycelium/host_contact_seats.dart' show HostContactSeats;
export 'package:mycelium/mailbox_in_transit.dart' show MailboxInTransit;

/// Unknown identifier, or no known route to a contact.
class MailboxError implements Exception {
  final String reason;
  MailboxError(this.reason);
  @override
  String toString() => 'MailboxError: $reason';
}

/// Identifier of an identity or of a contact, hex-encoded — computed
/// in ONE place ([Address.identifier]), here only as text.
String identifierFrom(Address a) => _hex(a.identifier);

/// The name a contact carries until its introduction is known — ONE source,
/// so the application can tell it from a real name without guessing.
String contactPlaceholderName(String identifierHex) =>
    'Contact-${identifierHex.substring(0, 8)}';

typedef InTransit = ({
  Address to, Outbound outbound, Uint8List identifierInHistory, bool withoutRoute});

class Mailbox {
  /// The host that carries this mailbox.
  final Host host;
  final Identity identity;
  final Memory _memory;
  final void Function(String)? report;
  final void Function(ContactRequest a)? _onContactRequest;
  /// The callback upwards — public like [onReaction] and the
  /// two others, since the inbound lies in `mailbox_inbound.dart`.
  final void Function(Inbound)? onMessage;
  final void Function(Reaction)? onReaction;
  final void Function(Edit)? onEdit;
  final void Function(ReadMark)? onReadMark;

  /// The groups of THIS identity, by their identifier.
  final Map<String, Group> groups = {};
  /// The histories, in the store the caller gave (`mailbox_history.dart`).
  final MailboxHistories histories;
  /// The running shipments, by the identifier of the shipment — public for
  /// `mailbox_in_transit.dart` and `mailbox_outbound.dart`, which ends those
  /// of a forgotten entry.
  final Map<String, InTransit> inTransit = {};

  /// The route under a code (proposal M, part M2 connects it); without
  /// it there is only a report (`mailbox_pair.dart`).
  CodeSend? underCodeSend;

  /// What ARRIVES for THIS identity stands in `mailbox_inbound.dart`
  /// — for the same reason as the outbound: the line budget.
  ///
  /// Only the [Host] creates mailboxes ([Host.start], [Host.register]).
  Mailbox(this.host, this.identity, this._memory, MailboxDetails a)
      : histories = MailboxHistories.forRegistration(a, host.report),
        report = host.report,
        _onContactRequest = a.onContactRequest,
        onMessage = a.onMessage,
        onReaction = a.onReaction,
        onEdit = a.onEdit,
        onReadMark = a.onReadMark {
    // RESTART (S388, ES-7/B3): the issued invitations become living ones
    // again, with what their waiting requests carry beyond the memory, and
    // the open joins wait again for their answer (proposal E).
    mailboxBookAttach(this, a); // the prior state of every acceptance (A)
    parkedAttach(this, a.directory, a.key); // cells awaiting a generation (D-40)
    firstContactOpen(a);
    historiesSettle(a); // old files taken over, ended peers' records gone
    for (final g in _memory.rememberedInvitations) {
      node.invitationRestore(identity, firstContactInvitation(g));
    }
    faceToFaceClose(atStart: true); // §15.3: 60 s since shown, or never shown
    pairHookSet(); // proposal M: first contact → pair data
    joinsRestore();
  }

  /// Writes the issued invitations of THIS identity into
  /// memory — at every change: issue, accept, revoke. [codes] `false`: the
  /// code list did not change (a renewed card, `invitation_way_in.dart`).
  void invitationsRemember({bool codes = true}) {
    _memory.rememberedInvitations
      ..clear()
      ..addAll(identity.invitationsSave());
    _memory.save();
    firstContactSave(); // day keys and marks of the waiting requests (E)
    if (codes) node.codeRoute.codesChanged(); // EDGE §8.1: own incoming codes
  }

  Node get node => host.node;
  int get port => node.port;

  /// The dispatch of large payloads belongs to the host: a media object
  /// carries no sender (S385-WIDERLEGUNG W2).
  MediaSender get media => host.media;

  /// Own identifier, hex-encoded — see [identifierFrom].
  String get ownIdentifier => _hex(identity.identifier);
  Address get address => identity.postBox.address;

  /// All remembered contacts of THIS identity.
  List<Contact> get contacts => _memory.contacts;

  /// §15.9: [a] is no longer a contact — deleted or blocked; a later request is again a
  /// question, its history leaves with it (`mailbox_history.dart`). Its delivery
  /// identifiers stay in the received memory (§20.2, V-3 = a): a late copy stays refused.
  void contactForget(Address a) {
    _memory.contactForget(a);
    _memory.save();
    histories.drop(identifierFrom(a));
    host.contactSeatsEdge(); // S405 V1: "stops being a contact" frees its seat now
  }

  /// Routine KEM rotation of THIS identity (V4.2 §4.5.4). The keys
  /// are created by the caller — the app (W1, `_performKeyRotation`);
  /// mycelium swaps them into the RUNNING post box (the current generation
  /// becomes the one previous) and saves. From here on every envelope of
  /// this identity carries the new address.
  ///
  /// NO ANNOUNCEMENT OF ITS OWN (S398): the app's KEY_ROTATION_BROADCAST,
  /// sent right after as an ordinary message, carries the new address in its
  /// envelope — the contact's mailbox and app learn from ONE packet. The
  /// Emergency Key Rotation stands in `mailbox_rotation.dart`.
  void keyChange(KemParts fresh, {DateTime? now}) {
    identity.postBox.rotate(fresh, now: now);
    ownPostBoxSave();
  }

  /// Writes [k] as it is — for what [contactRemember] does not name (the
  /// chain state, `mailbox_rotation.dart`). The address still goes through
  /// the adoption rule.
  void contactPut(Contact k) {
    _memory.contactRemember(k);
    _memory.save();
  }

  /// Writes the running post box into memory — after every change of it.
  void ownPostBoxSave() {
    _memory.ownPostBox = ownPostBoxOf(identity.postBox);
    _memory.save();
  }

  /// A request on a card of THIS identity (V4.2 §12.5, §15.5).
  /// The mailbox DOES NOT DECIDE: `true` only if [who] is already a contact
  /// with the same keys (recontact — the answer got
  /// lost); otherwise `null`: the request waits for
  /// `contactRequestDecide`. A way to accept immediately does not
  /// exist (ES-10). A different key set is never silently adopted
  /// (§15.8).
  bool? requestCheck(Address who, CardAddress origin) {
    final k = contactOrNull(identifierFrom(who));
    if (k != null && k.address.equal(who)) return true;
    return null;
  }

  /// A request is accepted — immediately or after the decision.
  /// [origin] is the address from which it arrived. Remembering it here is
  /// the only way in which the INVITING side ever learns where it
  /// can answer — the card names its own address, not that of the
  /// joiner. `null` for a request from a post box: no route (proposal E).
  void requestAccepted(Address who, CardAddress? origin) {
    invitationsRemember(); // the counter has changed
    origin == null ? host.giveUpAgainFor(this, who) : _routeRemember(who, origin);
  }

  /// A request is waiting — passed on to whoever asks the user.
  ///
  /// It waits for a decision that can take hours (§12.5), and
  /// must survive the restart (§15.4, E-1): it is saved WITH its
  /// invitation ([invitationsRemember]). That is the only place where a
  /// mailbox learns of a newly arrived request.
  void contactRequestReported(ContactRequest a) {
    invitationsRemember();
    _onContactRequest?.call(a);
  }

  /// ALL routes to [a] from THIS mailbox — for [Node.routesTo]. Three
  /// addresses (§7.1), not one; `null` only if [a] is not a contact here.
  Routes? routesToAddress(Address a) {
    final k = contactOrNull(identifierFrom(a));
    return k == null ? null : routesToContact(k);
  }

  // ── Contacts, routes, histories ───────────────────────────────────────

  /// The contact for [identifier] including a proven route to it — or
  /// [MailboxError].
  (Contact, CardAddress) reachable(String identifier) {
    final k = contact(identifier);
    final destination = routeTo(k);
    if (destination == null) throw MailboxError('no known route to $identifier');
    return (k, destination);
  }

  /// The history entries with the contact [contactIdentifier], in the order
  /// of sending — own entries only: a received delivery keeps no entry since
  /// S403, its identifier lives in the identity's received memory (§20.2).
  List<HistoryEntry> historyRead(String contactIdentifier) =>
      historyFor(contact(contactIdentifier).address).entries;

  /// Remembers [a] and the route [origin] from which a packet from it arrived.
  /// Only for places where the sender address provably belongs to the contact
  /// itself.
  /// S390: here stood a filter `woher.adresse.length == 4`, and a packet
  /// via IPv6 thereby fell through SILENTLY — no entry, no edge, no
  /// message. It was the precondition of the builder of [Contact], which
  /// threw at 16 bytes; since version 12 the memory carries the evidence
  /// typed, and the filter has no reason any more.
  void _routeRemember(Address a, CardAddress origin) {
    final changed =
        contactRemember(a, ip: origin.address, port: origin.port);
    // EDGE: a route has just arisen. What is resting for this contact
    // goes out NOW — not only at the next start. (If at the same time
    // the address changed, [contactRemember] has already done that.)
    if (!changed) host.giveUpAgainFor(this, a);
  }

  /// Remembers [a]; the address goes via the adoption rule
  /// ([Memory.contactRemember]). If it changes, that is an EDGE: what
  /// is resting for the contact goes out newly sealed (sealing happens
  /// on every attempt against the remembered address), and the groups carry
  /// the new address. Says whether the address has changed.
  ///
  /// [cardsAddresses] and [neighbours] come from the card of this
  /// counterpart (§15.2) — only the ONE place that has read a card
  /// passes them along ([MailboxInvitation.join]). Without specification what is
  /// already remembered stays: an inbound knows nothing
  /// about the card and therefore must not delete it either.
  ///
  /// **The list is passed, not the classification.** Until S390
  /// a [Routes] stood here — i.e. lan/public already separated —, and with that the
  /// classification lay in memory. It does not belong there: it depends on the
  /// own segment, and that changes (`address_class.dart`).
  bool contactRemember(Address a,
      {Uint8List? ip,
      int? port,
      List<CardAddress>? cardsAddresses,
      List<CardAddress>? neighbours,
      bool? neverFixedNeighbour,
      Uint8List? pairRandom,
      Map<int, Uint8List>? dayKey,
      DateTime? dayKeySent,
      String? displayName}) {
    final identifier = identifierFrom(a);
    final soFar = contactOrNull(identifier);
    final changed = _memory.contactRemember(Contact(
      address: a,
      displayName: displayName ??
          soFar?.displayName ?? contactPlaceholderName(identifier),
      since: soFar?.since ?? DateTime.now(),
      // [ip] carries 4 or 16 bytes; [CardAddress] sets the type byte and
      // rejects every other length. Without [ip] the remembered evidence
      // stays — an inbound does not delete it.
      lastSeen:
          ip == null ? soFar?.lastSeen : CardAddress(ip, port!),
      cardsAddresses: cardsAddresses ?? soFar?.cardsAddresses ?? const [],
      neighbours: neighbours ?? soFar?.neighbours ?? const [],
      neverFixedNeighbour: neverFixedNeighbour ?? soFar?.neverFixedNeighbour ?? false,
      // Proposal M: without specification what is remembered stays (as above).
      pairRandom: pairRandom ?? soFar?.pairRandom,
      dayKey: dayKey ?? soFar?.dayKey ?? const {},
      dayKeySent: dayKeySent ?? soFar?.dayKeySent,
      chainAcked: soFar?.chainAcked ?? false, // set only by `contactPut`
    ));
    _memory.save();
    if (changed) {
      for (final g in groups.values) {
        g.memberAddressAdopt(a);
      }
      host.giveUpAgainFor(this, a);
    }
    return changed;
  }

  Contact? contactOrNull(String identifier) {
    for (final k in _memory.contacts) {
      if (identifierFrom(k.address) == identifier) return k;
    }
    return null;
  }

  /// The contact for [identifier] — or [MailboxError]. No waiting helps
  /// against it, therefore this is an error and not a resting.
  Contact contact(String identifier) =>
      contactOrNull(identifier) ??
      (throw MailboxError('unknown identifier $identifier'));

  /// Known route to [k]: the most recently observed address. `null` does
  /// NOT mean "never works" — it means "not right now", and that flips at each
  /// of the three edges.
  ///
  /// Until S385 a neighbour from the call that carried the
  /// identity identifier of [k] came into question here as a fallback. Since call D the call carries no
  /// identity identifier any more; its place is taken by the search call, whose
  /// find sets the observed address itself.
  CardAddress? routeTo(Contact k) => k.lastSeen;

  History historyFor(Address a) => histories.of(a);

  Future<bool> waitFor(bool Function() condition, Duration deadline) async {
    final limit = DateTime.now().add(deadline);
    while (!condition()) {
      if (DateTime.now().isAfter(limit)) return false;
      await Future.delayed(const Duration(milliseconds: 10));
    }
    return true;
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
