/// The publisher key on the reading side (V4.2 §15.2, §5.2, §11.9): when an
/// invitation's addresses no longer answer, the reader looks the issuer's
/// CURRENT addresses up at the relays, under the key the card carries.
///
/// ── WHEN, AND ONLY THEN ───────────────────────────────────────────────────
///
/// §15.2: "a recipient whose invitation addresses no longer answer looks the
/// current ones up under it." That is established at exactly one point
/// without a clock of its own: the QR/NFC round trip's deadline has passed
/// without a bundle (`mailbox_invitation.dart`, S405 V4) — neither the card's
/// own addresses (steps 1 and 2) nor its neighbour (step 3) carried the
/// bundle request (0) to an issuer that answered. Then ONE query goes to the
/// known relays (2–3, §11.9), and the addresses found are tried ONCE, as a
/// second join with the same deadline. No timer, no repetition (rule 5).
///
/// An out-of-band line has no such point: it has no deadline (S405 F-1), its
/// request rests in the post boxes until the issuer collects. Its point is an
/// edge of §8.2 instead (S407 V2, owner decision 08.10.2026): at the first
/// edge — start, network change, new neighbour — at which its request is
/// still unanswered, ONE query, and the same request goes once to what the
/// record names ([joinsAtEdge]). Still no timer: the edges already exist.
///
/// ── WHAT IS TRUSTED ───────────────────────────────────────────────────────
///
/// Nothing beyond §11.9: a record is a hint. It must carry the card's key as
/// its author and pass [eventCheck] (signature under that key, channel,
/// expiry); an address that does not answer is simply dropped. A relay that
/// returns records of other authors is ignored for those. The issuer's
/// identity is still proven only by the bundle against the fingerprint.
///
/// Switched off by the user (§11.9 "neither reads nor publishes"): no query.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card.dart';
import 'package:mycelium/host_outside.dart' show kOutsideRelayAtMost;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/neighbour_find.dart' show neighbourLookup;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_invitation.dart' show NodeInvitation;
import 'package:mycelium/node_join.dart' show NodeJoin;
import 'package:mycelium/node_helpers.dart' show cardChannel, hexFrom;
import 'package:mycelium/outside_check.dart';
import 'package:mycelium/outside_entry.dart';
import 'package:mycelium/outside_relay.dart';

/// The addresses the newest valid record of [publisherKey] names, of the
/// address families this node speaks — empty if no relay is known, none
/// answers or none holds a valid record. One query per relay, in parallel.
Future<List<CardAddress>> publisherLookup(Node k, Uint8List publisherKey) async {
  final relay = k.knownRelay.take(kOutsideRelayAtMost).toList();
  if (relay.isEmpty) {
    k.report('Publisher lookup: no relay known');
    return const [];
  }
  final hex = hexFrom(publisherKey);
  final filter = publisherFilter(cardChannel, hex);
  final answers = await Future.wait(
      [for (final r in relay) entriesFetch(r, filter, report: k.report)]);
  AddressRecord? newest;
  var newestAt = -1;
  final ofPublisher = [
    for (final ev in answers.expand((x) => x))
      if (ev['pubkey'] == hex) ev
  ];
  // S409: off the event loop, identical records once (`outside_check.dart`).
  final checked = await eventsCheck(ofPublisher, cardChannel);
  for (var i = 0; i < ofPublisher.length; i++) {
    final ev = ofPublisher[i];
    final e = checked[i];
    final at = ev['created_at'];
    if (e == null || at is! int || at <= newestAt) continue;
    newest = e;
    newestAt = at;
  }
  final found = (newest?.addresses ?? const <CardAddress>[])
      .where((a) => k.speaks(InternetAddress.fromRawAddress(a.address)))
      .toList();
  k.report('Publisher lookup: ${relay.length} relay(s) asked, '
      '${newest == null ? "no record" : "${found.length} address(es)"} '
      'under ${hex.substring(0, 8)}');
  return found;
}

/// An edge of §8.2 for the joins of [m] (`MailboxOutbound.giveUpAgain`): the
/// out-of-band requests no post box took go out again (D-44), and every
/// out-of-band line still unanswered looks its issuer up — once per line and
/// run (`NodeJoin.joinsToLookUp`). Without a known relay or with source 4
/// off no line counts as looked up: a later edge may still ask.
void joinsAtEdge(Mailbox m) {
  m.node.joinsSendAgain(m.identity);
  if (!m.host.outsideSourceOn || m.node.knownRelay.isEmpty) return;
  for (final b in m.node.joinsToLookUp(m.identity)) {
    unawaited(cardFromPublisher(m, b.card).then((moved) {
      if (moved == null) return;
      if (!identical(moved.ownAddresses, b.card.ownAddresses)) {
        m.node.joinSendTo(b, moved);
      }
      // S407 a': the card's neighbour found again under its record key —
      // where the request rests and the issuer collects (§8.2).
      final n = moved.neighbourAddress;
      if (n != null) m.node.joinNeighbourMoved(b, n);
    }));
  }
}

/// The card to try once more after [card]'s round trip found nobody: the same
/// invitation, its own addresses replaced by those the issuer's record names
/// now, and its neighbour by the one its record key names now (S407 a') —
/// without a neighbour where that did not move. `null` — and no query at
/// all — when the card carries neither key or source 4 is switched off;
/// `null` too when nothing new was found.
Future<Card?> cardFromPublisher(Mailbox m, Card card) async {
  final key = card.publisherKey;
  final n = card.neighbourAddress;
  if (key == null && n?.recordKey == null) return null;
  if (!m.host.outsideSourceOn) {
    m.report?.call('Publisher lookup: source 4 switched off — not asked (§11.9)');
    return null;
  }
  final found = key == null ? const <CardAddress>[] : await publisherLookup(m.node, key);
  final fresh = found
      .where((a) => !card.ownAddresses.any((c) => c.equal(a)))
      .take(kOwnAddressesAtMost)
      .toList();
  // S407 a': the neighbour too, under its record key; one that did not move
  // stays out (it did not answer either).
  final neighbour = n == null ? null : await neighbourLookup(m.node, n);
  if (fresh.isEmpty && neighbour == null) return null;
  return Card(
    channel: card.channel,
    letterKeyX25519: card.letterKeyX25519,
    fingerprint: card.fingerprint,
    ownAddresses: fresh.isEmpty ? card.ownAddresses : fresh,
    neighbourAddress: neighbour,
    publisherKey: key,
    relay: card.relay,
    difficulty: card.difficulty,
    code: card.code,
    expiryUnixSeconds: card.expiryUnixSeconds,
  );
}
