/// The waiting contact request — moved here from `first_contact_invitation.dart`
/// when proposal M (S391) gave it neighbour and answer code
/// and that file rose above 400 lines. It is created ONLY by
/// [Invitation] (`buffered`); until S391 this was secured by a private
/// constructor, which no longer works across the file boundary.
library;

import 'dart:typed_data';

import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/first_contact_invitation.dart' show Invitation;
import 'package:mycelium/card.dart';
import 'package:mycelium/envelope.dart';
import 'package:mycelium/introduction.dart';

/// A received request whose proof and code are checked and which
/// waits for the user's decision. No contact (§12.5).
class ContactRequest implements inv.WaitingRequest {
  /// The invitation on which it came — it alone can answer.
  final Invitation invitation;
  @override
  final Address who;

  /// Where it came from; the answer goes there, and when accepted it becomes the
  /// route to the new contact.
  @override
  final CardAddress origin;
  @override
  final Introduction? introduction;
  @override
  final DateTime at;
  @override
  final CardAddress? neighbour;
  @override
  final Uint8List? answerCode;

  /// On a card handed over in person (§15.5)? Accepted without a second question.
  bool get inPerson => invitation.entry?.inPerson ?? false;

  ContactRequest.buffered(this.invitation, this.who, this.origin, this.introduction,
      this.at, this.neighbour, this.answerCode);
}
