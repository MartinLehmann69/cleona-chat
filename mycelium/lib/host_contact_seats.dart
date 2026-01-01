/// Contacts as fixed neighbours at the host (V4.2 §5.2, §8.1; proposal
/// "contacts as fixed neighbours", version 3, owner decision 24.09.2026:
/// D1 = up to three, D2 = a, D3 = a).
///
/// The neighbourhood knows no identities and no contacts; the host is the
/// only place that holds the node AND all mailboxes (§4.5.1). It therefore
/// sets the two predicates the contact seats need
/// (`neighbourhood_contacts.dart`) and decides what the contacts of each
/// identity learn when the fixed neighbours change.
///
/// ── A CONTACT'S DEVICE ─────────────────────────────────────────────────
///
/// A neighbour is the device of a contact when one of its addresses (or a
/// name it gave for itself, §8.1 V5) is the contact's last OBSERVED address
/// or one of the addresses of the contact's card (`memory_contact.dart`) —
/// for a contact of ANY identity of this device: the seats belong to the
/// device, which all identities share (D3).
///
/// A contact the user excluded (D2) never takes a seat. If a device matches
/// several contacts, one exclusion is enough: the mark protects against a
/// threat from the user's own circle, and a second identity that knows the
/// same person must not undo it.
///
/// ── WHAT THE CONTACTS LEARN (D3) ───────────────────────────────────────
///
/// An identity names to its contacts the fixed neighbours that are devices
/// of ITS OWN contacts; where there is none, the card's seat. Naming the
/// friend of identity 1 to the contacts of identity 2 would link the two
/// identities. The list rides sealed in every message and acknowledgement
/// the identity sends (`message.dart`, wired in `host_codes.dart`); no
/// packet of its own goes out when it changes (proposal rule 5).
///
/// A separate file because `host.dart` stands at the 400-line limit.
library;

import 'dart:io';

import 'package:mycelium/neighbour_keys.dart';
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;
import 'package:mycelium/own_segment.dart' show withinOwnSegment;
import 'package:mycelium/card_address.dart';
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/host.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/memory.dart' show Contact;
import 'package:mycelium/neighbour.dart';
import 'package:mycelium/trace_first_contact.dart' show contactWhy, contactWhyAt;

/// Whether [n] is a device of the contact [k]: one of [n]'s addresses or
/// names is [Contact.lastSeen] or an address of [k]'s card.
bool deviceOfContact(Contact k, Neighbour n) =>
    [if (k.lastSeen case final s?) s, ...k.cardsAddresses].any(n.knows);

extension HostContactSeats on Host {
  /// Called once from `Host.start`, after the network exists. The closures
  /// read [mailboxes] only on call, so a mailbox registered later counts.
  void contactSeatsWireUp() {
    final n = node.neighbourhood;
    contactWhy[n] = (x) => contactWhyAt(this, x); // S405 (proposal D), log only
    n.isContactDevice = (x) => mailboxes
        .any((p) => p.contacts.any((k) => deviceOfContact(k, x)));
    n.neverFixedNeighbour = (x) => mailboxes.any((p) => p.contacts
        .any((k) => k.neverFixedNeighbour && deviceOfContact(k, x)));
  }

  /// EDGE "a contact arose or its mark changed": the contact seats are
  /// checked anew, and a change is carried like any other (§8.1).
  void contactSeatsEdge() {
    node.neighbourhood.contactSeatsCheck();
    network.fixedCheck();
  }

  /// EDGE "the user set or cleared the mark on a contact" (D2, §15.10):
  /// "never use as a fixed neighbour". The mark is remembered on the
  /// contact of [p] under [a] (local, it travels nowhere) and the seats
  /// are checked at once — without this edge a seat would only be freed
  /// at the next confirmation or removal. Says whether the mark changed;
  /// an unchanged mark is no edge.
  ///
  /// A contact the mailbox does not know yet is remembered with the mark
  /// and without a route, like the app's send path does
  /// ([Mailbox.contactRemember] without ip/port).
  bool contactNeverFixedNeighbourSet(Mailbox p, Address a, bool on) {
    if (p.contactOrNull(identifierFrom(a))?.neverFixedNeighbour == on) {
      return false;
    }
    p.contactRemember(a, neverFixedNeighbour: on);
    contactSeatsEdge();
    return true;
  }

  /// The fixed neighbours the identity of [p] names to its contacts (D3):
  /// those of [fixed] with a contact seat that are devices of ITS contacts
  /// (≤ 3, in seat order); where there is none, the card's seat — unless
  /// that is the device of another identity's contact; else nothing.
  ///
  /// With a reader [to] — the list in a message or acknowledgement — each
  /// under an address [to] can use (§9.2, D-92 B, [usableAddress]); one
  /// known under no such address is left out. Without [to] (the `0x23`, the
  /// acceptance, the own devices) as before S412: [Neighbour.asCardAddress].
  List<CardAddress> namedTo(Mailbox p, List<Neighbour> fixed, {Address? to}) {
    bool own(Neighbour n) => p.contacts.any((k) => deviceOfContact(k, n));
    final inside = to != null && readerInSegment(p.contactOrNull(identifierFrom(to)));
    final open = node.neighbourhood.openNetwork; // the ONE classification
    List<CardAddress> named(bool Function(Neighbour n) which) => [
          for (final n in fixed)
            if (which(n))
              if ((to == null ? n.asCardAddress : usableAddress(n, inside, open)) case final a?)
                node.keyedOf(n, a),
        ];
    final seats = named((n) => n.contactSeat > 0 && own(n));
    if (seats.isNotEmpty) return seats;
    return named((n) => n.fixed && (own(n) || !node.neighbourhood.isContactDevice(n)));
  }
}

/// Whether the contact [k] is inside this device's own segment: the address
/// a packet of it last came from is a segment address of this device's
/// network (§7.2) — evidence, not its card (two homes share 192.168.178.x).
bool readerInSegment(Contact? k) => switch (k?.lastSeen) {
      final s? => _segment(InternetAddress.fromRawAddress(s.address)),
      null => false,
    };

bool _segment(InternetAddress a) => !a.isLoopback && withinOwnSegment(a);

/// The address of [n] a reader can use (§9.2, D-92 B): to a reader inside
/// the own segment a confirmed segment address first, to everyone a confirmed
/// address reachable from the open network (§15.2) — never a loopback, never
/// a private address to a reader outside. `null`: none, [n] is left out.
/// "Reachable from the open network" is [open] — the node passes its
/// `Neighbourhood.openNetwork`, which in the product is always
/// [fromOutsideReachable]; probes on 127.0.0.1 let the loopback play it.
CardAddress? usableAddress(Neighbour n, bool readerInside,
        [bool Function(InternetAddress a) open = fromOutsideReachable]) =>
    (readerInside ? n.cardAddress((a) => a.confirmedEver && _segment(a.address)) : null) ??
    n.cardAddress((a) => a.confirmedEver && open(a.address));
