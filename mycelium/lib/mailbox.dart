/// The mailbox — ONE identity with everything that belongs only to it:
/// post box, contacts, histories, running shipments, re-dispatch,
/// invitations, groups. The rest (wire, fixed port, neighbourhood,
/// cover stream, ladder, storage for third parties, state checker) is held by the
/// [Host], once for all mailboxes (V4.2 §4.5.1, S385 cut F).
///
/// A caller that serves an identity needs only THIS class:
/// issue an invitation, join one, send, read the history,
/// see the contacts. The mailboxes are separate because two
/// identities of the same human must not be connected with each other
/// (`identity.dart`) — a mailbox never asks
/// the contacts of another.
///
/// RESTART: post box + contacts lie in the mailbox's [Memory],
/// every sent/received message in the peer's [History]. A
/// message not yet receipted at stopping afterwards stands again as
/// open in the history AND immediately goes back onto the ladder.
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
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/address_class.dart' show routesToContact;
import 'package:mycelium/first_contact.dart' show ContactRequest;
import 'package:mycelium/memory.dart';
import 'package:mycelium/group.dart';
import 'package:mycelium/identity.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_invitation.dart' show NodeInvitation;
import 'package:mycelium/media.dart';
import 'package:mycelium/message.dart'
    show Outbound, Inbound, DeliveryState, kModeRoutesApplyFurther;
import 'package:mycelium/amendment.dart' show Edit, ReadMark, Reaction;
import 'package:mycelium/first_contact_pair.dart' show CodeSend;
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/mailbox_start.dart';
import 'package:mycelium/envelope.dart';
import 'package:mycelium/history.dart';
import 'package:mycelium/host.dart';

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

typedef _InTransit = ({
  Address to, Outbound outbound, Uint8List identifierInHistory, bool withoutRoute});

class Mailbox {
  /// The host that carries this mailbox.
  final Host host;
  final Identity identity;
  final Directory _directory;
  final Uint8List _key;
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
  final Map<String, History> _histories = {};
  final Map<String, _InTransit> _inTransit = {};

  /// The route under a code (proposal M, part M2 connects it); without
  /// it there is only a report (`mailbox_pair.dart`).
  CodeSend? underCodeSend;

  /// What ARRIVES for THIS identity stands in `mailbox_inbound.dart`
  /// — for the same reason as the outbound: the line budget.
  ///
  /// Only the [Host] creates mailboxes ([Host.start], [Host.register]).
  Mailbox(this.host, this.identity, this._memory, MailboxDetails a)
      : _directory = a.directory,
        _key = a.key,
        report = host.report,
        _onContactRequest = a.onContactRequest,
        onMessage = a.onMessage,
        onReaction = a.onReaction,
        onEdit = a.onEdit,
        onReadMark = a.onReadMark {
    // RESTART (S388, ES-7/B3): the issued invitations of the last
    // run become living invitations again — revocable, capped, and
    // they answer bundle plea and request as before the restart.
    for (final g in _memory.rememberedInvitations) {
      node.invitationRestore(identity, invitationFromRemembered(g));
    }
    pairHookSet(); // proposal M: first contact → pair data
  }

  /// Writes the issued invitations of THIS identity into
  /// memory — at every change: issue, accept, revoke.
  void invitationsRemember() {
    _memory.rememberedInvitations
      ..clear()
      ..addAll(identity.invitationsSave());
    _memory.save();
    // EDGE (§8.1): with every issued, accepted or revoked
    // invitation the set of own incoming codes changes — the
    // first-contact code depends on the invitation (`mailbox_pair.dart`).
    node.codeRoute.codesChanged();
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

  /// §15.9: [a] is no longer a contact — deleted or blocked. A
  /// later request is then again a question, not a recontact.
  void contactForget(Address a) {
    _memory.contactForget(a);
    _memory.save();
  }

  /// Routine KEM rotation of THIS identity (V4.2 §4.5.4). The keys
  /// are created by the caller — the app (W1); mycelium swaps in the post box,
  /// saves, and announces PAIRWISE to every contact with a known route.
  /// Without a route no announcement, and none rests for later: accepted
  /// (owner decision) — the contact learns the address with the next
  /// message. Returns the number of announcements.
  int keyChange(KemParts fresh, {DateTime? now}) {
    final b = identity.postBox..rotate(fresh, now: now);
    final t = b.secretParts();
    _memory.ownPostBox = (
      address: b.address,
      ed25519Sk: t.ed25519Sk,
      x25519Sk: t.x25519Sk,
      mlKemSk: t.mlKemSk,
      mlDsaSk: t.mlDsaSk,
      previous: t.previous,
    );
    _memory.save();
    var number = 0;
    for (final k in contacts) {
      final destination = routeTo(k);
      if (destination == null) {
        report?.call('no announcement to ${identifierFrom(k.address)} — '
            'no route known');
        continue;
      }
      node.send(Uint8List(0), k.address, destination,
          forField: identity, mode: kModeRoutesApplyFurther);
      number++;
    }
    return number;
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
  /// joiner.
  void requestAccepted(Address who, CardAddress origin) {
    invitationsRemember(); // the counter has changed
    _routeRemember(who, origin);
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

  /// No callback available for receipt/give-up — [Outbound] is
  /// the same mutable instance that the message layer changes directly;
  /// this check enters the change into the history. The
  /// clock for it is ONE, at the host.
  void stateCheck() {
    final settled = <String>[];
    for (final e in _inTransit.entries) {
      final u = e.value;
      if (u.outbound.state == DeliveryState.inTransit) continue;
      try {
        historyFor(u.to).stateChange(u.identifierInHistory, u.outbound.state);
      } on HistoryError catch (err) {
        report?.call('State change discarded: $err');
      }
      settled.add(e.key);
    }
    for (final k in settled) {
      _inTransit.remove(k);
    }
  }

  /// ALL routes to [a] from THIS mailbox — for [Node.routesTo]. Three
  /// addresses (§7.1), not one; `null` only if [a] is not a contact here.
  Routes? routesToAddress(Address a) {
    final k = contactOrNull(identifierFrom(a));
    return k == null ? null : routesToContact(k);
  }

  // ── Contacts, routes, histories ───────────────────────────────────────

  /// Notes a running shipment, so that [stateCheck] enters its state
  /// into the history afterwards. [identifierInHistory] is the identifier of the
  /// ENTRY — for a re-dispatch a different one than that of the shipment;
  /// a re-dispatch therefore REPLACES the previous note of the same
  /// entry. [withoutRoute]: started without any address, see [runsWithoutRoute].
  void marksInTransit(Address to, Outbound outbound,
          Uint8List identifierInHistory, {bool withoutRoute = false}) =>
      _inTransit
        ..removeWhere(
            (_, u) => _hex(u.identifierInHistory) == _hex(identifierInHistory))
        ..[_hex(outbound.identifier)] = (to: to, outbound: outbound,
            identifierInHistory: identifierInHistory, withoutRoute: withoutRoute);

  /// Whether a shipment is currently running for [identifierInHistory]. The re-dispatch
  /// asks this before it dispatches something again — otherwise the same
  /// message would go out twice.
  bool runsCurrently(Uint8List identifierInHistory) => _inTransit.values
      .any((u) => _hex(u.identifierInHistory) == _hex(identifierInHistory));

  /// Whether the running shipment for [identifierInHistory] started WITHOUT any address.
  /// Such a one no longer learns an address added later
  /// — the ladder sets up its steps at start —, so it is replaced at the
  /// edge (§9.3).
  bool runsWithoutRoute(Uint8List identifierInHistory) => _inTransit.values.any((u) =>
      _hex(u.identifierInHistory) == _hex(identifierInHistory) && u.withoutRoute);

  /// The contact for [identifier] including a proven route to it — or
  /// [MailboxError].
  (Contact, CardAddress) reachable(String identifier) {
    final k = contact(identifier);
    final destination = routeTo(k);
    if (destination == null) throw MailboxError('no known route to $identifier');
    return (k, destination);
  }

  /// The messages with the contact [contactIdentifier], in the order
  /// of arrival/sending.
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
  /// already remembered stays: a publication or an inbound knows nothing
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
      // stays — a publication does not delete it.
      lastSeen:
          ip == null ? soFar?.lastSeen : CardAddress(ip, port!),
      cardsAddresses: cardsAddresses ?? soFar?.cardsAddresses ?? const [],
      neighbours: neighbours ?? soFar?.neighbours ?? const [],
      neverFixedNeighbour: neverFixedNeighbour ?? soFar?.neverFixedNeighbour ?? false,
      // Proposal M: without specification what is remembered stays (as above).
      pairRandom: pairRandom ?? soFar?.pairRandom,
      dayKey: dayKey ?? soFar?.dayKey ?? const {},
      dayKeySent: dayKeySent ?? soFar?.dayKeySent,
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

  History historyFor(Address a) => _histories.putIfAbsent(
      identifierFrom(a), () => History.load(_directory, a, _key));

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
