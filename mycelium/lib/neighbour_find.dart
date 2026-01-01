/// Finding a contact's neighbours again when their addresses have gone silent
/// (V4.2 §8.1, §8.2, §11.9; S407 a' and its second stage, owner decisions
/// 09.10.2026).
///
/// ── THE OCCASION, AND ONLY IT ─────────────────────────────────────────────
///
/// A message's post-box placing ended without the second `0x31` (§8.2
/// "placing ends") and nothing acknowledged it: the holders it was left with
/// — the contact's fixed neighbours as the contact last named them (§9.2) —
/// did not answer. That is a ladder step that went silent; no clock is set
/// for it, and it happens at most once per message and run.
///
/// ── STRICTLY IN THIS ORDER ────────────────────────────────────────────────
///
/// 1. **Look up.** Every named neighbour that carried its record key
///    (`neighbour_keys.dart`) is looked up ONCE at the known relays
///    (`publisher_lookup.dart`, the same query and checks). A neighbour that
///    moved is replaced by its current address; the contact's list is
///    adopted as if the contact had named it ([MailboxPair.neighboursHeard]),
///    and what is neither acknowledged nor placed goes out again to it
///    ([MailboxOutbound.giveUpAgain], D-44) — no `0x23`.
/// 2. **Where are you.** Only when the lookup found nothing new — no key, no
///    record, the same address, or source 4 switched off (§11.9) — ONE `0x23`
///    goes out as §8.1 has it, also without a `0x21` before it: the contact's
///    neighbours were not wrong, they were gone. Its own bounds stay: one per
///    contact per hour ([CodeRoute.whereAreYou]); a call signal is no
///    message and never gets here (§8.1, §17.2).
///
/// Group pairs are not contacts and take neither stage: their legs go by code
/// and post box only (`mailbox_outbound.dart`).
library;

import 'dart:async';

import 'package:mycelium/card.dart';
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_outbound.dart' show MailboxOutbound;
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_invitation.dart' show NodeInvitation;
import 'package:mycelium/publisher_lookup.dart' show publisherLookup;

/// The current address of the node [silent] names by its record key — `null`
/// without a key, without a record, or when the record names only [silent].
Future<CardAddress?> neighbourLookup(Node k, CardAddress silent) async {
  final key = silent.recordKey;
  if (key == null || k.knownRelay.isEmpty) return null;
  final found = await publisherLookup(k, key);
  for (final a in found) {
    if (!a.equal(silent)) return a.withRecordKey(key);
  }
  return null;
}


final Expando<Set<String>> _lost = Expando('ways lost');

extension NeighbourFind on Mailbox {
  /// The placing of message [hex] to [to] ended unplaced and unacknowledged:
  /// stage 1, else stage 2 (see the head). Once per message and run.
  Future<void> wayLost(Address to, String hex) async {
    if (!(_lost[this] ??= {}).add(hex)) return;
    final c = contactOrNull(identifierFrom(to));
    if (c == null || c.neighbours.isEmpty) return;
    if (host.outsideSourceOn) {
      var moved = 0;
      final next = <CardAddress>[];
      for (final a in c.neighbours) {
        final n = await neighbourLookup(node, a);
        if (n != null) moved++;
        next.add(n ?? a);
      }
      if (moved > 0) {
        report?.call('Way lost to ${identifierFrom(to).substring(0, 8)}: '
            '$moved neighbour(s) moved, found under their record key — sent again '
            'to ${next.join(", ")}');
        neighboursHeard(to, next);
        giveUpAgain(only: to);
        return;
      }
    }
    final sent = node.codeRoute.whereAreYou(to, identity.postBox.address);
    report?.call('Way lost to ${identifierFrom(to).substring(0, 8)}: no neighbour '
        'found anew — ${sent ? "one 0x23 sent" : "no 0x23 (bound or no code)"}');
  }
}
