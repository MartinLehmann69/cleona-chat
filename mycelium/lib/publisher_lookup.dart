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
/// request rests in the post boxes until the issuer collects. Nothing here
/// runs for it.
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

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card.dart';
import 'package:mycelium/host_outside.dart' show kOutsideRelayAtMost;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_invitation.dart' show NodeInvitation;
import 'package:mycelium/node_helpers.dart' show cardChannel, hexFrom;
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
  for (final ev in answers.expand((x) => x)) {
    if (ev['pubkey'] != hex) continue;
    final e = eventCheck(ev, cardChannel);
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

/// The card to try once more after [card]'s round trip found nobody: the same
/// invitation, its own addresses replaced by those the issuer's record names
/// now, without the neighbour (it did not answer either). `null` — and no
/// query at all — when the card carries no publisher key or the user
/// switched source 4 off; `null` too when the record names no address the
/// card did not already carry (those did not answer).
Future<Card?> cardFromPublisher(Mailbox m, Card card) async {
  final key = card.publisherKey;
  if (key == null) return null;
  if (!m.host.outsideSourceOn) {
    m.report?.call('Publisher lookup: source 4 switched off — not asked (§11.9)');
    return null;
  }
  final found = await publisherLookup(m.node, key);
  final fresh = found
      .where((a) => !card.ownAddresses.any((c) => c.equal(a)))
      .take(kOwnAddressesAtMost)
      .toList();
  if (fresh.isEmpty) return null;
  return Card(
    channel: card.channel,
    letterKeyX25519: card.letterKeyX25519,
    fingerprint: card.fingerprint,
    ownAddresses: fresh,
    publisherKey: key,
    relay: card.relay,
    difficulty: card.difficulty,
    code: card.code,
    expiryUnixSeconds: card.expiryUnixSeconds,
  );
}
