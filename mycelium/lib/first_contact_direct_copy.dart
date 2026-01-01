/// The direct copy of a request that came first another way (§15.5, S411).
///
/// A requester sends its request (2) on every step at once (§7.1): directly,
/// under the card's code through the issuer's neighbour, into the post box.
/// Whichever copy arrives first is handled; the others are repeats and the
/// retry store drops them before unsealing (`first_contact_invitation.dart`).
/// A copy that was forwarded or collected is no evidence of an address
/// (proposal E), so an answer to it leaves without step 1. When the direct
/// copy arrives a few milliseconds later, it IS that evidence — until S411
/// it was dropped with the rest, and a requester without a fixed neighbour of
/// its own (no answer code) had only its post box left
/// (`mycelium/berichte/S411-E2E-BAU-ABBRUCH.md`).
///
/// Here the issuer keeps, per requester, what the direct copy changes:
/// * an answer that already left without step 1 goes once more, unchanged,
///   to the address of the direct copy — the requester drops a second copy
///   like any repeat (§9.2);
/// * a request still waiting for the user's decision (§15.4) gets that
///   address for its answer.
/// No new packet, no clock: only what a copy arriving anyway sets off.
library;

import 'dart:typed_data';

import 'package:mycelium/address.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/first_contact.dart' show Report, Send;
import 'package:mycelium/invitation_buffer.dart' show kBufferPerInvitation;
import 'package:mycelium/node_helpers.dart' show hexFrom;

class DirectCopy {
  /// Bounded like the request buffer (§15.4): the oldest gives way.
  static const int rememberedAtMost = kBufferPerInvitation;

  /// Requester -> address its direct copy came from.
  final Map<String, CardAddress> _origin = {};

  /// Requester -> answer that left without step 1, not yet sent again.
  final Map<String, Uint8List> _answer = {};

  /// Random value of an unsealed request (header, §15.5) -> its requester.
  /// A repeat is matched by it and NEVER unsealed: a replayed request must
  /// stay as cheap to drop as before (`smoke_first_contact`).
  final Map<String, String> _requester = {};

  static String _key(Address who) => hexFrom(who.identifier);

  /// The request with [randomValue] was unsealed and came from [who].
  void opened(Uint8List randomValue, Address who) {
    _requester[hexFrom(randomValue)] = _key(who);
    _bound(_requester);
  }

  static void _bound<T>(Map<String, T> m) {
    while (m.length > rememberedAtMost) {
      m.remove(m.keys.first);
    }
  }

  /// The address a direct copy of [who]'s request showed, if one came.
  CardAddress? originOf(Address who) => _origin[_key(who)];

  /// The answer to [who] left without step 1: kept for its direct copy.
  void answeredWithout(Address who, Uint8List answer) {
    _answer[_key(who)] = answer;
    _bound(_answer);
  }

  /// A repeat of the request with [randomValue] came DIRECTLY from [from].
  /// An answer that left without step 1 goes there now, once; otherwise
  /// [from] waits for the decision. A random value never unsealed here
  /// (not this invitation's) changes nothing.
  void repeatCame(Uint8List randomValue, CardAddress from, Send send, Report? report) {
    final k = _requester[hexFrom(randomValue)];
    if (k == null) return;
    final again = _answer.remove(k);
    if (again != null) {
      report?.call('direct copy of an answered request — the answer goes there once (§15.5)');
      send(again, from);
      return;
    }
    _origin[k] = from;
    _bound(_origin);
  }
}
