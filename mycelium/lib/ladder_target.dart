/// Where a shipment of the ladder may go (`ladder.dart`, V4.2 §7.1). Out of
/// `ladder.dart` for the line budget (mycelium/README.md rule 2, S398);
/// re-exported there, so no caller needs a second import.
library;

import 'dart:typed_data';

import 'package:mycelium/card.dart';

/// Where sending is possible. Everything is optional.
class Target {
  final CardAddress? lan;

  /// The recipient's fixed neighbour — step 3 carries only with [code].
  final CardAddress? neighbour;

  /// All of the recipient's fixed neighbours (≤ 3, [neighbour] first) —
  /// step 3 names each in its one `0x22` (§8.1). Empty: [neighbour] alone.
  final List<CardAddress> neighbours;

  /// The code of this shipment (16 B, `pair.dart`) — under it the
  /// recipient's neighbour passes on (§8.1). If it is missing, step 3 drops out.
  final Uint8List? code;

  /// Identifier of the peer (32 B) — under it the post box step
  /// deposits, and the call searches for it. It belongs to the SHIPMENT:
  /// until S385 it was searched for afterwards and hit the oldest open
  /// shipment instead of this one (finding D, `smoke_deposit_identifier`).
  final Uint8List? identifier;

  /// Whether the post box step APPLIES — §7.1 starts "every applicable
  /// step", and which apply is said by the target: steps 1 and 3 via
  /// address and code, step 4 here. No order, no deadline.
  ///
  /// `false` means PROVEN reachable: the packet that this shipment
  /// answers just came in via [lan], and §8.2 keeps the
  /// post box for a recipient who is OFF. The silence of the ladder does not
  /// settle that — a shipment ends with the receipt (§7.1 "the
  /// remaining attempts are cancelled"), and to a receipt there is
  /// no receipt (§9.2). An ANSWER thus never ends by itself and deposits
  /// after `kOffsetPostBox` (`ladder.dart`), even if its recipient has long
  /// had it: measured 7 datagrams, 7886 B per holder, times three in the field, plus
  /// three proofs of work (`berichte/S389-BAU-QUITTUNG.md`).
  final bool postBoxApplicable;

  /// The invitation value `dayValue(pk_inv)` — ONLY for a line join's
  /// request (2): step 4 leaves it there, never under a day value another
  /// identity of this node knows (OP-20, S398; §15.1).
  final Uint8List? boxValue;

  /// The recipient's public address — NEVER sent to (D-4). It is held only
  /// for §7.2: an address of any kind is a way, and only a send without any
  /// way carries the search call ([noAddress]).
  final CardAddress? public;

  const Target({this.lan, this.neighbour, this.code, this.identifier,
      this.postBoxApplicable = true, this.neighbours = const [], this.boxValue, this.public});

  /// §7.2: "A send has no way when the recipient holds no address at all —
  /// none of their own, neither from the card nor observed, and no neighbour
  /// address either." Then, and only then, the search call.
  bool get noAddress => lan == null && public == null && neighbour == null && neighbours.isEmpty;

  /// From the addresses that a caller holds for a peer
  /// ([Routes] — from its card, §15.2, and from what it has observed itself,
  /// §6.2). [lan] overrides the LAN role if the caller has a
  /// PROVEN route: the address from which the answered packet came.
  ///
  /// The card's way into the ladder. Until S390 this place was called
  /// `Ziel.ausKarte`, took a whole [Card] and had in `lib/`, `bin/`
  /// and `test/` **zero callers** — the application built its [Target] with
  /// `lan:` and nothing else (finding B-1).
  /// [neighbour] overrides the neighbour address of the routes (the current one from
  /// the pair instead of the one from the card). `w.public` is carried only
  /// for the search-call test ([noAddress]); no step sends to it (D-4).
  factory Target.outDueTo(Routes? w,
          {CardAddress? lan,
          CardAddress? neighbour,
          List<CardAddress> neighbours = const [],
          Uint8List? code,
          Uint8List? identifier,
          bool postBoxApplicable = true,
          Uint8List? boxValue}) =>
      Target(
        lan: lan ?? w?.lan,
        neighbour: neighbours.firstOrNull ?? neighbour ?? w?.neighbour,
        neighbours: neighbours,
        code: code,
        identifier: identifier,
        postBoxApplicable: postBoxApplicable,
        boxValue: boxValue,
        public: w?.public,
      );

  /// No step except the post box carries.
  bool get empty => lan == null && (neighbour == null || code == null);
}
