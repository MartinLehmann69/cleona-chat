/// The card never names a contact (proposal "contacts as fixed neighbours",
/// version 3, rule 6 and 6.5; V4.2 §15.2).
///
/// A card travels to people the issuer has not accepted yet and is passed
/// on; a contact's address in it would hand a friend's address and a piece
/// of the issuer's social graph to every reader. The same holds for the
/// way back of a first contact, which names the reader's fixed neighbour in
/// the clear to the issuer's neighbour (§15.2 "the first-contact code").
///
/// The seat rule already keeps contacts off the card's seat where it can
/// (`neighbourhood_seat.dart`); what is left — a contact's device that took
/// the seat while nobody else answered, or a neighbour that became a
/// contact after it took it — is closed HERE, at the one place every
/// stranger-facing reader asks. A seat that is a contact's device names
/// nobody: a card without a neighbour costs a first contact from the open
/// internet its step 3 (§15.2 names that price), a friend's address in a
/// passed-on text line costs more.
library;

import 'package:mycelium/neighbourhood.dart';

/// The card's seat as a stranger may learn it — `null` if there is none or
/// it is a contact's device.
Neighbour? cardSeatForStrangers(Neighbourhood n) {
  final f = n.cardNeighbour;
  return f == null || n.isContactDevice(f) ? null : f;
}
