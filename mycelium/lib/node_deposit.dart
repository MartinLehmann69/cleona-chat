/// The sender side of the node's post box (V4.2 §8.2): step 4 of the
/// ladder leaves a packet under the recipient's day value with holders.
///
/// Split off from `node_post_box.dart` (S407-VB20, line budget); the
/// collector side stays there, and `node_post_box.dart` exports this file,
/// so every importer keeps seeing both.
///
/// ── INTERFACE (M3) ───────────────────────────────────────────────
///
/// Called by step 4 of the ladder:
/// ```
/// Future<(bool done, int acknowledged)>? depositFor(Address recipient, Uint8List content)
/// void stepFourForIdentifier(Uint8List identifier, Uint8List content)
/// ```
/// Deposited under `dayValue(dayPkFrom(recipient, utcDay(now)))`.
/// Without a known day pubkey step 4 is dropped for this sending —
/// `null` or no deposit, and [Node.report] says so.
/// Wired are [dayPkFrom] and [contactFrom] (integrator/M1).
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_first_contact_box.dart' show NodeFirstContactBox;
import 'package:mycelium/pair.dart' show dayValue, utcDay;
import 'package:mycelium/post_box_deposit.dart' show Neighbour;
import 'package:mycelium/post_box_disk.dart' show kValueLength;
import 'package:mycelium/post_box_holders.dart';
import 'package:mycelium/post_box_log.dart' show holdersNamed;

/// The day pubkey (32 B) of [contact] on UTC day [day], or `null`
/// if none is known. Supplied by the mailbox (M1: contacts get
/// the public day keys sealed, proposal M 5.4).
typedef DayPkFrom = Uint8List? Function(Address contact, int day);

/// The contact for a 32-B identifier, or `null`. Needed because step 4
/// of the ladder only names the identifier (`ladder.dart`, `AblageSenden`), but the
/// day pubkey hangs on the contact.
typedef ContactFrom = Address? Function(Uint8List identifier);

/// `named`: the fixed neighbours [contact] last told this node (§9.2); `at`:
/// its own addresses, only to leave them out as holders (OP-19 part B).
typedef NeighboursFrom = ({List<CardAddress> named, List<CardAddress> at})
    Function(Address contact);

extension NodeDeposit on Node {
  /// The own holders of a deposit: [n] NODES (§8.2: three addressed, two
  /// suffice; B1) in the order of `ownHoldersRanked` (OP-19 part A, S398),
  /// none on the node of an address in [not] — the recipient's (part B).
  List<Neighbour> ownHolders({Iterable<Neighbour> not = const [], int n = 3}) =>
      readiness.different([
        for (final x in ownHoldersRanked(neighbourhood.all,
            live: linkLive, answered: readiness.answeredRecently)) // S398 L2-1
          (address: x.address, port: x.port)
      ], n, not: not);
  List<Neighbour> get depositNeighbours => ownHolders();

  /// Where the fixed neighbours of a contact come from — see [NeighboursFrom].
  set neighboursFrom(NeighboursFrom? f) => _neighboursFrom[this] = f;

  /// Where the day pubkey of a contact comes from — see [DayPkFrom].
  set dayPkFrom(DayPkFrom? f) => _dayPkFrom[this] = f;

  /// Where the contact for an identifier comes from — see [ContactFrom].
  set contactFrom(ContactFrom? f) => _contactFrom[this] = f;

  /// The value under which deposits for [recipient] are made TODAY (UTC), or
  /// `null` without a known day pubkey.
  Uint8List? depositValueFor(Address recipient) {
    final pk = _dayPkFrom[this]
        ?.call(recipient, utcDay(postBoxDeposit.now()));
    return pk == null ? null : dayValue(pk);
  }

  /// Step 4 for [recipient]: deposits [content] under his today's
  /// day value with the own neighbours (three addressed, two
  /// receipts suffice). `null`: no day pubkey known — step 4
  /// is dropped for this sending, reported. Does not throw.
  Future<(bool done, int acknowledged)>? depositFor(
      Address recipient, Uint8List content, {bool Function()? ended}) {
    final value = depositValueFor(recipient);
    if (value == null) {
      report('Post box step dropped: no daily pubkey for '
          '${_short(recipient.identifier)}');
      return null;
    }
    // §8.2 (proposal 6.4): first the recipient's fixed neighbours, then ours
    // — never the recipient's own device (OP-19 part B).
    final f = _neighboursFrom[this]?.call(recipient);
    return depositNamed(content, value, f?.named ?? const [],
        at: f?.at ?? const [], ended: ended);
  }

  /// [depositFor] for step 4 of the ladder by the identifier. A line join's
  /// request never comes here: it carries its invitation value
  /// (`node_step_four.dart`, OP-20). Returns whether the deposit was placed
  /// (§8.2: the second `0x31`) — the sender remembers it per message
  /// (`mailbox_outbound.dart`, §9.3); `null` if nothing was left.
  Future<bool>? stepFourForIdentifier(Uint8List identifier, Uint8List content,
      {bool Function()? ended}) {
    final to = _contactFrom[this]?.call(identifier);
    if (to == null) {
      report('Post box step dropped: no contact for ${_short(identifier)}');
      return null;
    }
    return depositFor(to, content, ended: ended)?.then((r) => r.$1);
  }

  /// Deposits [content] under the 16-B value [underValue] (day value, manifest
  /// compartment, recovery bundle) with the own neighbours; it ends on
  /// events (§8.2). Does not throw: another length ends `(false, 0)`,
  /// reported. [ended]: see `PostBoxDeposit.deposit`. Without [withWhom]
  /// the own neighbours by rank are the candidates: the first three are
  /// addressed, the others stand in for a holder that fails (§8.2). With
  /// [withWhom], [reserve] names the candidates after them.
  Future<(bool done, int acknowledged)> deposit(Uint8List content,
      Uint8List underValue,
      {List<Neighbour>? withWhom,
      List<Neighbour> reserve = const [],
      bool Function()? ended}) {
    if (underValue.length != kValueLength) {
      report('deposit: ${underValue.length} B is not a daily value '
          '($kValueLength B) — not deposited');
      return Future.value((false, 0));
    }
    final all = withWhom == null ? ownHolders(n: neighbourhood.all.length) : null;
    final to = withWhom ?? all!.take(kDepositHolders).toList();
    final rest = all?.skip(kDepositHolders).toList() ?? reserve;
    // S394 diagnosis: the deposit had no line of its own — whether it was
    // placed, and with how many receipts, could not be read.
    report('deposit: ${content.length} B under ${_short(underValue)} '
        'to ${to.length} neighbour(s): ${holdersNamed(to)}'); // O2
    return postBoxDeposit
        .deposit(
            content: content,
            underValue: underValue,
            withWhom: to,
            reserve: rest,
            ended: ended)
        .then((r) {
      report('deposit under ${_short(underValue)}: '
          '${r.$1 ? "placed" : "NOT placed"}, ${r.$2} receipt(s)');
      return r;
    });
  }
}

/// The callbacks of the sender side per node — see [NodeDeposit.dayPkFrom],
/// [NodeDeposit.contactFrom] and [NodeDeposit.neighboursFrom].
final Expando<DayPkFrom> _dayPkFrom = Expando<DayPkFrom>('dayPkOf');
final Expando<ContactFrom> _contactFrom = Expando<ContactFrom>('contactOf');
final Expando<NeighboursFrom> _neighboursFrom =
    Expando<NeighboursFrom>('neighboursOf');

String _short(Uint8List b) => b
    .sublist(0, 4)
    .map((x) => x.toRadixString(16).padLeft(2, '0'))
    .join();
