/// The pair state at the mailbox (proposal M, part M1 — S391, §4.3, §8.1,
/// §8.2 of the proposal; owner approval 17.09.2026, D1 = a, D2 = a).
///
/// Here stands what the mailbox KNOWS about its pairs and to whom it
/// SAYS something about it:
///
///  * [MailboxPair.inboundCodes] — under which codes packets for this
///    identity come (registered with the fixed neighbour, part M2);
///  * [MailboxPair.pairFrom], [MailboxPair.dayPkFrom] — what a sender
///    needs for a contact;
///  * [MailboxPair.dayKeyDistribute] — the own public
///    day keys to the contacts, only at edges and at most every
///    14 days per contact (no clock, working rule 5);
///  * [MailboxPair.neighboursHeard] — a contact's fixed neighbours, as they
///    ride sealed in its messages and acknowledgements (§9.2, proposal
///    "contacts as fixed neighbours" rule 5 — the former notice `0x17` sent to
///    every contact at a change is gone without replacement);
///  * [MailboxPair.whereAreYouContent], [MailboxPair.whereAreYouAccept] — the
///    fixed neighbours once more, when NO route carries any more: as the
///    content of a `0x23` (§8.1), sealed symmetrically under `K_AB`.
///
/// The day key notice is an ordinary sealed message with its own kind
/// (`kinds.dart`), receipted like any, without a history entry.
/// The `0x23` content is explicitly NOT — it is no
/// message at all (§8.1 "no message inside"); the reasoning stands at
/// [suchContentSeal].
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/first_contact_pair.dart';
import 'package:mycelium/invitation.dart' as inv show kGracePeriodSeconds;
import 'package:mycelium/memory.dart' show Reader, kDayKeyAtMost;
import 'package:mycelium/card_address.dart';
import 'package:mycelium/message.dart' show Inbound;
import 'package:mycelium/neighbour_list.dart';
import 'package:mycelium/neighbourhood_card.dart';
import 'package:mycelium/pair.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/host_contact_seats.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/envelope.dart';

/// How many days one shipment of the own day keys covers.
const int kDayKeyDays = 31;

/// Earlier than after this interval no new shipment of the day keys
/// goes out to the same contact.
const Duration kDayKeyInterval = Duration(days: 14);

extension MailboxPair on Mailbox {
  /// Connects the first contact of this identity with the mailbox
  /// (`first_contact_pair.dart`). Once when creating the mailbox.
  void pairHookSet() {
    pairHook[identity.postBox] = PairHook(
      knownRandom: (who) => contactOrNull(identifierFrom(who))?.pairRandom,
      // EDGE (§8.1): with `s_AB` the code contact→me arises. Without the
      // report it would stay unknown for up to one second, and exactly in
      // this second the answer of the first contact comes.
      onPair: (who, s, neighbour) {
        contactRemember(who,
            pairRandom: s, neighbours: neighbour == null ? null : [neighbour]);
        node.codeRoute.codesChanged();
      },
      onContactStands: (who) {
        dayKeyDistribute(only: who);
        host.contactSeatsEdge(); // §5.2: the new contact may take a seat
        node.codeRoute.codesChanged(); // EDGE (§8.1), receipt (4)
      },
      // In the clear to a stranger's neighbour: never a contact (6.5).
      ownNeighbour: () => cardSeatForStrangers(node.neighbourhood)?.asCardAddress,
      underCodeSend: (code, neighbour, packet) {
        final f = underCodeSend;
        f == null
            ? report?.call('under code: no route connected (M2) — '
                '${packet.length} B not sent')
            : f(code, neighbour, packet);
      },
    );
  }

  /// All codes under which packets for this identity come on UTC day [day]:
  /// per contact with `s_AB` code(contact→me, day), per invitation
  /// whose acceptance window is open, its first-contact code (even
  /// used up — a recontact comes under the same one), per open
  /// join its one-time answer code.
  List<Uint8List> inboundCodes(int day, {int? nowSeconds}) {
    final me = identity.postBox;
    final now =
        nowSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return [
      for (final k in contacts)
        if (k.pairRandom case final s?)
          pairCode(pairSecret(me, k.address, s),
              fromPk: k.address.ed25519Pk,
              toPk: me.address.ed25519Pk,
              day: day),
      for (final e in identity.invitations.all)
        if (!e.revoke &&
            now <= e.expiryUnixSeconds + inv.kGracePeriodSeconds)
          firstContactCode(e.code),
      for (final b in identity.joins)
        if (!b.done && !b.declined) b.answerCode,
    ];
  }

  /// `K_AB` and fixed neighbours of a contact, or `null` without `s_AB`.
  /// Step 3 names each of them in its one `0x22` (§8.1, `code_send.dart`).
  ({Uint8List kAB, List<CardAddress> neighbours})? pairFrom(Address contact) {
    final k = contactOrNull(identifierFrom(contact));
    final s = k?.pairRandom;
    if (k == null || s == null) return null;
    return (kAB: pairSecret(identity.postBox, k.address, s), neighbours: k.neighbours);
  }

  /// The fixed neighbours this identity names to its contacts (D3):
  /// `host_contact_seats.dart`, [HostContactSeats.namedTo].
  List<CardAddress> get ownNeighbours =>
      host.namedTo(this, node.neighbourhood.fixedNeighbours);

  /// A peer's fixed neighbours arrived sealed in a message or an
  /// acknowledgement (§9.2). Only for a KNOWN contact, and only when they
  /// differ — every remembering writes the memory. `true` if adopted.
  ///
  /// An empty list never arrives here (`message.dart`): a peer that names
  /// none has just not found one yet; its old ones stay as a hint — a stale
  /// hint costs a `0x21`, no error (§15.2).
  bool neighboursHeard(Address from, List<CardAddress> list) {
    final k = contactOrNull(identifierFrom(from));
    if (k == null || list.isEmpty || neighbourListEqual(k.neighbours, list)) {
      return false;
    }
    contactRemember(k.address, neighbours: neighbourListClean(list));
    return true;
  }

  /// The sealed content of a `0x23` to [contact] ("where are you", §8.1):
  /// the own fixed neighbours ([ownNeighbours]), sealed with [suchContentSeal] —
  /// BUILT, not sent.
  ///
  /// It is not sent via the ladder, but by the forwarder
  /// under the pair code, because no route carries any more — that is the occasion
  /// of the search. The recipient takes it in [whereAreYouAccept]
  /// and afterwards knows the neighbour via which it can answer.
  ///
  /// `null` if this mailbox does not know the contact (then there is
  /// no `K_AB`) or if there is no fixed neighbour — then the
  /// search has nothing to communicate, and `node_codes.dart` leaves out the `0x23`.
  Uint8List? whereAreYouContent(Address contact) {
    final p = pairFrom(contact);
    final n = ownNeighbours;
    if (p == null || n.isEmpty) return null;
    return suchContentSeal(p.kAB, n);
  }

  /// Opposite direction to [whereAreYouContent]: a `0x23` content has arrived here
  /// under [code] (§8.1). Which contact of THIS mailbox sends under
  /// this code — and does its seal open? Then its fixed neighbours stand
  /// in it; they are remembered and returned, otherwise `null`.
  ///
  /// The packet names no identifier, only the code (proposal M) — the
  /// assignment therefore runs via the code, not via a sender.
  /// The computation covers yesterday/today/tomorrow, as `isOwnCode`
  /// does: two clocks never stand at the same second, and a `0x23`
  /// travels over two hops.
  ///
  /// The effort is one X25519 per contact. That is acceptable because only
  /// what [CodeRoute.isOwnCode] has already affirmed arrives here: only a contact
  /// can form an own code.
  List<CardAddress>? whereAreYouAccept(Uint8List code, Uint8List content,
      {DateTime? now}) {
    final me = identity.postBox;
    final today = utcDay(now ?? DateTime.now());
    for (final k in contacts) {
      final s = k.pairRandom;
      if (s == null) continue;
      final kAB = pairSecret(me, k.address, s);
      for (var day = today - 1; day <= today + 1; day++) {
        final c = pairCode(kAB,
            fromPk: k.address.ed25519Pk,
            toPk: me.address.ed25519Pk,
            day: day);
        if (!_equal(c, code)) continue;
        final n = suchContentOpen(kAB, content);
        if (n == null) {
          report?.call('0x23 from ${identifierFrom(k.address).substring(0, 8)}: '
              'seal does not open — discarded');
          return null;
        }
        contactRemember(k.address, neighbours: n);
        return n;
      }
    }
    return null;
  }

  /// The public day key of a contact for the day, or `null`.
  Uint8List? dayPkFrom(Address contact, int day) =>
      contactOrNull(identifierFrom(contact))?.dayKey[day];

  /// Edge "start", "network change" or "new contact": gives every contact
  /// (with [only]: only this one) the own day keys of the next
  /// [kDayKeyDays] days — only if it has none yet or the
  /// last shipment lies at least [kDayKeyInterval] back.
  /// Returns the number of shipments.
  int dayKeyDistribute({Address? only, DateTime? now}) {
    final at = now ?? DateTime.now();
    final due = [
      for (final k in contacts)
        if ((only == null || k.address.sameIdentity(only)) &&
            (k.dayKeySent == null ||
                at.difference(k.dayKeySent!) >=
                    kDayKeyInterval))
          k,
    ];
    if (due.isEmpty) return 0;
    final today = utcDay(at);
    final content = dayKeyBuild({
      for (var t = today; t < today + kDayKeyDays; t++)
        t: deriveDayKey(identity.postBox, t).pk,
    });
    for (final k in due) {
      node.send(content, k.address, routeTo(k),
          forField: identity, kind: kinds.kDayKey);
      contactRemember(k.address, dayKeySent: at);
    }
    return due.length;
  }

  /// A pair notice has arrived ([Inbound.kind]). Only from a
  /// KNOWN contact; no history entry, no callback upwards.
  void pairNoticeAccept(Inbound e, {DateTime? now}) {
    final k = contactOrNull(identifierFrom(e.from));
    if (k == null) {
      report?.call('Pair notice from unknown identifier — discarded');
      return;
    }
    try {
      switch (e.kind) {
        case kinds.kDayKey:
          final today = utcDay(now ?? DateTime.now());
          final fresh = dayKeyRead(e.content);
          final all = {...k.dayKey, ...fresh}
            ..removeWhere((t, _) => t < today - 1 || t > today + kDayKeyDays);
          final days = all.keys.toList()..sort();
          contactRemember(k.address, dayKey: {
            for (final t in days.take(kDayKeyAtMost)) t: all[t]!,
          });
        default:
          report?.call('pair notice of unknown kind ${e.kind} — discarded');
      }
    } on Object catch (f) {
      report?.call('Pair notice discarded: $f');
    }
  }
}

/// The content of a `0x23` ("where are you", §8.1): `nonce 24 ‖
/// AEAD(fixed neighbours)` — the list of `neighbour_list.dart`, count 1..3
/// + addresses: **48 B for one IPv4, 98 B for three IPv6**, against
/// `kSuchContentAtMost` = 1140 B (`node_codes.dart`). XSalsa20-
/// Poly1305 under [suchSealKey], as `group.dart` demonstrates it for `K_C`.
///
/// ── WHY SYMMETRIC, AND WHY WITHOUT A SIGNATURE ──────────────────────
///
/// §8.1 says "one part, **no message inside**". An ordinary
/// message does not even fit in here: the hybrid envelope (§4)
/// costs a FIXED overhead of 7736 B — measured on 22.09.2026 for
/// plaintexts of 4 to 40 B, i.e. for every payload down to the
/// empty one. Even without the inner signature it would stay above the limit,
/// solely because of the ML-KEM-768 ciphertext (1088 B).
///
/// **AUTHENTICITY** therefore does not come from a signature, but
/// from the fact that only two devices have `K_AB`. That is the same assumption
/// on which the pair code already rests (`pair.dart`): whoever can form the code of one
/// direction IS the contact. Poly1305 carries it here — whoever
/// does not have the key does not get the seal open and cannot
/// forge it either. A signature on top says nothing
/// additional and costs 3309 B.
///
/// **NAMED EXCEPTION to §4.6** (owner decision 22.09.2026):
/// per-message forward secrecy deliberately does NOT apply here. `K_AB` is
/// long-lived, so a recorded `0x23` can be opened later. But whoever
/// breaks `K_AB` can anyway compute all pair codes of this pair for
/// every day and thereby assign both sides to each other at the fixed neighbour
/// — the neighbour address adds nothing to that which they would not
/// already have. The exception stands here at the code; the owner enters it into the architecture document
/// himself.
Uint8List suchContentSeal(Uint8List kAB, List<CardAddress> neighbours) {
  final clear = BytesBuilder();
  neighbourListWrite(clear, neighbourListClean(neighbours), least: 1);
  final na = SodiumFFI();
  final nonce = na.randomBytes(cryptoSecretBoxNonceBytes);
  return (BytesBuilder()
        ..add(nonce)
        ..add(na.secretBoxEncrypt(
            clear.toBytes(), suchSealKey(kAB), nonce)))
      .toBytes();
}

/// Counterpart to [suchContentSeal]. `null` if the seal does not open under
/// [kAB] or if behind it there is not EXACTLY one list of 1..3 —
/// a foreign key, a twisted byte and an appended remainder
/// all fall through the same door.
List<CardAddress>? suchContentOpen(Uint8List kAB, Uint8List content) {
  if (content.length <= cryptoSecretBoxNonceBytes) return null;
  try {
    final l = Reader(SodiumFFI().secretBoxDecrypt(
        Uint8List.sublistView(content, cryptoSecretBoxNonceBytes),
        suchSealKey(kAB),
        Uint8List.sublistView(content, 0, cryptoSecretBoxNonceBytes)));
    final a = neighbourListRead(l.bytes, 'neighbours of the search', least: 1);
    l.done();
    return a;
  } on Object {
    return null;
  }
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Payload of the day keys: count (1 B), per day u32 + 32 B.
Uint8List dayKeyBuild(Map<int, Uint8List> days) {
  final b = BytesBuilder()..addByte(days.length);
  for (final e in days.entries) {
    b.add((ByteData(4)..setUint32(0, e.key, Endian.big)).buffer.asUint8List());
    b.add(e.value);
  }
  return b.toBytes();
}

/// Counterpart to [dayKeyBuild]; throws on every form error.
Map<int, Uint8List> dayKeyRead(Uint8List content) {
  final l = Reader(content);
  final n = l.byte();
  if (n == 0 || n > kDayKeyDays) {
    throw FormatException('$n day keys, allowed 1..$kDayKeyDays');
  }
  final out = <int, Uint8List>{};
  for (var i = 0; i < n; i++) {
    final t = l.u32();
    if (out.containsKey(t)) throw FormatException('Day $t duplicated');
    out[t] = l.bytes(32);
  }
  l.done();
  return out;
}
