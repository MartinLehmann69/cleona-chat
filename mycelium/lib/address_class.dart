/// Who CLASSIFIES an address — and why the reader does that, never the
/// issuer.
///
/// ── WHY A SEPARATE FILE ───────────────────────────────────────────
///
/// Since S390 the card no longer carries roles (§15.2): it names the
/// addresses of its issuer in the issuer's order of preference, and which
/// of them ladder step 1 serves and which step 2 is decided by the READER.
/// That is no matter of taste: whether an issuer's `192.168.1.5`
/// lies in the own segment only the own segment knows — the issuer
/// cannot answer it at all. A classification written along in the card or in memory
/// would be a second truth — and wrong already at the reader's next
/// network change.
///
/// Thus there is exactly ONE place where classification happens, and it stands
/// here. `node_helpers.dart` keeps the address questions themselves
/// ([outTheSegment], `isPrivate`); this file uses them to answer the two
/// questions that the ladder asks. The cut also has a plain
/// reason: `node_helpers.dart` stood at 395 of 400 lines
/// (`mycelium/README.md` rule 2).
library;

import 'dart:io';

import 'package:mycelium/memory.dart' show Contact;
import 'package:mycelium/card.dart' show Card;
import 'package:mycelium/card_address.dart' show CardAddress, Routes;
import 'package:mycelium/node_helpers.dart' show outTheSegment;

/// Whether [a] lies in the own segment from the view of THIS node.
bool _inSegment(CardAddress a) =>
    outTheSegment(InternetAddress.fromRawAddress(a.address));

/// The first address from [addresses] that [fits] — the issuer's order
/// is its recommendation, and it is followed as long as it is
/// usable (§15.2).
CardAddress? _first(
    List<CardAddress> addresses, bool Function(CardAddress) fits) {
  for (final a in addresses) {
    if (fits(a)) return a;
  }
  return null;
}

/// The routes to the node that issued [k] (§7.1).
///
/// If nothing is found for a step, it stays empty; the ladder then
/// skips it — it does not fail (§7.1). Without any address
/// §8.2 carries.
Routes routesFromCard(Card k) => (
      lan: _first(k.ownAddresses, _inSegment),
      public: _first(k.ownAddresses, (a) => !_inSegment(a)),
      neighbour: k.neighbourAddress,
    );

/// The routes to a remembered contact (§6.2, §6.3, §7.1).
///
/// **The EVIDENCE beats the claim.** In the role `lan`
/// [Contact.lastSeen] wins — a packet demonstrably came from there —,
/// regardless of how the card was sorted. A card address
/// never overrides an observed route; otherwise a card would send a
/// node to a third address.
///
/// Classification happens anew on every call, not when remembering. Exactly that is
/// the point: the same contact whose address lay in the Wi-Fi segment yesterday
/// lies outside in cellular today — the bytes have not
/// changed, the answer has.
Routes routesToContact(Contact k) {
  final proof = k.lastSeen;
  final outCard = k.cardsAddresses;
  return (
    lan: proof ?? _first(outCard, _inSegment),
    public: _first(outCard, (a) => !_inSegment(a)),
    neighbour: k.neighbours.firstOrNull, // the first of the peer's fixed ones
  );
}
