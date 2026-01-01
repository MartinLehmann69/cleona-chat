/// Diagnosis of the first contact (S405, owner approval 06.10.2026,
/// proposal D; `trace.dart` for the layers below): the card field by field,
/// who holds which seat of the neighbourhood and why a card names no
/// neighbour, and for every arriving first-contact packet who takes it — or
/// why nobody does. Reads only; decides and sends nothing.
///
/// The reasons are the code's own predicates, asked in the same order as
/// the code asks them (`node_invitation.dart` `invite`,
/// `neighbourhood_card.dart`, `first_contact_invitation.dart`
/// `fitsProofOfWork`, `first_contact.dart` `expectedBundle`/`answerFits`) —
/// a second rule here would be a second truth.
library;

import 'dart:typed_data';

import 'package:mycelium/card.dart';
import 'package:mycelium/first_contact.dart' show PacketKind;
import 'package:mycelium/first_contact_wire.dart' show requestHeaderRead;
import 'package:mycelium/host.dart';
import 'package:mycelium/host_contact_seats.dart' show deviceOfContact;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show hexFrom, shortFrom;
import 'package:mycelium/pair.dart' show firstContactCode;
import 'package:mycelium/proof_of_work.dart';
import 'package:mycelium/trace.dart';

/// Which contact makes a neighbour "a contact's device", per neighbourhood —
/// set by the host (`host_contact_seats.dart`), read by [seatSnapshot].
final Expando<String? Function(Neighbour n)> contactWhy = Expando('contactWhy');

/// [h]'s answer for [contactWhy]: every contact of every identity whose
/// last observed address or card address [n] carries, with that address.
String? contactWhyAt(Host h, Neighbour n) {
  final hits = <String>[];
  for (final p in h.mailboxes) {
    for (final k in p.contacts) {
      if (!deviceOfContact(k, n)) continue;
      final via = [
        if (k.lastSeen case final s? when n.knows(s)) 'last observed address $s',
        for (final c in k.cardsAddresses)
          if (n.knows(c)) 'card address $c',
      ];
      hits.add('contact ${shortFrom(identifierFrom(k.address))} of identity '
          '${p.identity.identifierHex.substring(0, 8)} via ${via.join(" and ")}');
    }
  }
  return hits.isEmpty ? null : hits.join('; ');
}

/// The card field by field.
String cardDescribe(Card c) =>
    'channel ${c.channel}, fingerprint ${hexFrom(c.fingerprint).substring(0, 8)}, '
    'own addresses [${c.ownAddresses.join(", ")}], '
    'neighbour ${c.neighbourAddress ?? "NONE"}, relays ${c.relay.length}, '
    'difficulty ${c.difficulty}, first-contact code '
    '${shortFrom(hexFrom(firstContactCode(c.code)))}, expiry '
    '${DateTime.fromMillisecondsSinceEpoch(c.expiryUnixSeconds * 1000, isUtc: true).toIso8601String()}';

/// Every neighbour with its seat, addresses (responding / open network) and
/// whether it counts as a contact's device — and why.
List<String> seatSnapshot(Node k) {
  final n = k.neighbourhood;
  final responding = k.readiness.responding;
  final why = contactWhy[n];
  return [
    for (final x in n.all)
      'neighbour ${x.id}: ${x.fixed ? "CARD SEAT" : x.contactSeat > 0 ? "contact seat ${x.contactSeat}" : "no seat"}, '
          'addresses [${x.addresses.map((a) => '${a.key} ${responding.contains(a.key) ? "responding" : "silent"} '
              '${n.openNetwork(a.address) ? "open-network" : "private"}${a.confirmedEver ? "" : " unconfirmed"}').join(", ")}], '
          '${n.isContactDevice(x) ? "CONTACT'S DEVICE (${why?.call(x) ?? "?"})" : "no contact's device"}',
  ];
}

/// Why the card [k] issues now names its neighbour, or why it names none —
/// the same three questions as `invite` and `cardSeatForStrangers`.
String cardNeighbourReason(Node k) {
  final n = k.neighbourhood;
  final f = n.cardNeighbour;
  if (f == null) return 'no neighbour holds the card seat';
  if (n.isContactDevice(f)) {
    return 'the card seat holder ${f.key} is a contact\'s device '
        '(${contactWhy[n]?.call(f) ?? "?"}) — a card never names one (§15.2)';
  }
  final r = k.readiness.responding;
  final fit = [
    for (final a in f.addresses)
      if (r.contains(a.key) && n.openNetwork(a.address)) a.key,
  ];
  return fit.isNotEmpty
      ? 'the card seat holder ${f.key} answers under ${fit.join(", ")}'
      : 'the card seat holder ${f.key} has no address that is both responding '
          'and reachable from the open network: ${f.addresses.map((a) => '${a.key} '
              '${r.contains(a.key) ? "responding" : "silent"}/${n.openNetwork(a.address) ? "open" : "private"}').join(", ")}';
}

/// A card was issued by [p]: the card, the reason for its neighbour and the
/// seats — one line each.
void traceCardIssued(Mailbox p, Card card) {
  if (!traceOn) return;
  final k = p.node;
  k.report('TRACE card issued by identity ${p.identity.identifierHex.substring(0, 8)}: '
      '${cardDescribe(card)}');
  k.report('TRACE card neighbour: ${cardNeighbourReason(k)}');
  for (final s in seatSnapshot(k)) {
    k.report('TRACE seat $s');
  }
}

/// A card was read by [p] to join it.
void traceCardRead(Mailbox p, Card card, {required bool line}) {
  if (!traceOn) return;
  p.node.report('TRACE card read by identity ${p.identity.identifierHex.substring(0, 8)} '
      '(${line ? "cleona:2: line, no bundle round trip" : "QR/NFC/cleona:1:, bundle round trip"}): '
      '${cardDescribe(card)}');
  for (final s in seatSnapshot(p.node)) {
    p.node.report('TRACE seat $s');
  }
}

/// Who on [k] takes the first-contact packet [data] — or why nobody: the
/// same questions `NodeInvitation.firstContact` asks, without changing
/// anything (the probing unseals of `answerFits`/`receiptFrom` included).
String firstContactMatch(Node k, Uint8List data) {
  final kind = PacketKind.fromCode(data[0]);
  final out = <String>[];
  for (final i in k.identities) {
    final who = 'identity ${i.identifierHex.substring(0, 8)}';
    for (final b in i.joins) {
      final j = 'join ${shortFrom(hexFrom(b.answerCode))}';
      if (kind == PacketKind.bundle) {
        out.add('$j ${b.expectedBundle(data) ? "TAKES it" : "no (done, has a bundle, or random value differs)"}');
      } else if (kind == PacketKind.answer) {
        out.add('$j ${b.answerFits(data) ? "TAKES it" : "no (not sealed to it by its counterpart, or done)"}');
      }
    }
    for (final e in i.open.values) {
      final inv = 'invitation ${shortFrom(hexFrom(firstContactCode(e.code)))}';
      if (kind == PacketKind.request) {
        out.add('$who $inv ${_requestVerdict(e.code, e.difficulty, data)}'
            '${e.revoke ? " (revoked)" : e.consumed ? " (consumed)" : ""}');
      } else if (kind == PacketKind.receipt) {
        out.add('$who $inv ${e.receiptFrom(data) != null ? "TAKES it" : "no (not from one it accepted)"}');
      }
    }
    if (kind == PacketKind.bundlePlea) {
      out.add('$who standing invitations ${i.invitations.standing().length}');
    }
  }
  return out.isEmpty ? 'no join and no invitation on this node' : out.join('; ');
}

/// The proof-of-work questions of `fitsProofOfWork`, one by one — the
/// network learns nothing of them (§15.3), the local log does.
String _requestVerdict(Uint8List code, int difficulty, Uint8List data) {
  final h = requestHeaderRead(data);
  if (h == null) return 'no: header unreadable';
  final now = ProofOfWork.windowNow();
  if (!ProofOfWork.windowAccepted(h.window, now)) {
    return 'no: time window ${h.window} outside the accepted span (now $now)';
  }
  final found = ProofOfWork.codeFind([code], h.randomValue, h.counter, difficulty,
      timeWindow: h.window);
  return found == null
      ? 'no: proof of work does not fit this code at difficulty $difficulty'
      : 'TAKES it (proof fits, window ${h.window})';
}

/// For [Neighbourhood] lines without a node (`host_network.dart`).
List<String> seatsOf(Neighbourhood n, Set<String> responding) => [
      for (final x in n.all)
        '${x.key} ${x.fixed ? "CARD SEAT" : "contact seat ${x.contactSeat}"}'
            '${responding.any(x.addresses.map((a) => a.key).contains) ? " responding" : " silent"}'
            '${n.isContactDevice(x) ? " CONTACT'S DEVICE (${contactWhy[n]?.call(x) ?? "?"})" : ""}'
    ].where((s) => !s.contains('contact seat 0')).toList();
