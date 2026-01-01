/// The record keys of fixed neighbours, as they named them (V4.2 §11.9;
/// S407 a', owner decision 09.10.2026).
///
/// A fixed neighbour that writes an address record names its record key in
/// the `0x25` answering a code registration (`code_registration.dart`). The
/// node keeps it per address, in memory only: every start and every new fixed
/// neighbour is an edge with a registration (§8.1), so the map fills again
/// without a packet of its own. Where this node names a fixed neighbour —
/// the card's neighbour (§15.2), the list in every message and
/// acknowledgement (§9.2) — the key goes with the address
/// ([NeighbourKeys.keyed]), so that a reader whose address has gone silent
/// can look the current one up ([neighbourLookup], `neighbour_find.dart`).
///
/// ── ONLY TO WHOM READS IT (owner 09.10.2026, mixed operation "B") ─────────
/// A 4.2.3 device rejects a keyed list (`neighbour_list.dart`) — the whole
/// message or acknowledgement. A list to a contact therefore carries keys
/// only once the contact SHOWED it reads them ([Contact.readsKeys], kept in
/// the memory): a keyed list from it, the suffix behind its invitation line
/// (`card_text_key.dart`), or one of its devices that set the bit in its
/// `0x24` to this node or named its key in a `0x25` ([readsKeysAt]). The
/// keyed list it then gets shows the same of this side, bit set even
/// without a key. Group pairs and strangers get the old form.
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/neighbour.dart' show Neighbour;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show hexFrom;

final Expando<Map<String, Uint8List>> _keys = Expando('neighbour record keys');
final Expando<Set<String>> _reads = Expando('devices reading keyed lists');

String _at(CardAddress a) => '${hexFrom(a.address)}:${a.port}';

extension NeighbourKeys on Node {
  Map<String, Uint8List> get _map => _keys[this] ??= {};

  /// The neighbour at [at] named [key] (its `0x25`).
  void recordKeyLearn(CardAddress at, Uint8List key) {
    final old = _map[_at(at)];
    if (old != null && hexFrom(old) == hexFrom(key)) return;
    _map[_at(at)] = Uint8List.fromList(key);
    readsKeysAt(at);
    report('record key of fixed neighbour $at: ${hexFrom(key).substring(0, 8)}');
  }

  /// The record key the neighbour at [at] named, or `null`.
  Uint8List? recordKeyOf(CardAddress at) => _map[_at(at)];

  /// [a] with the record key its node named, if one is known and [a] carries
  /// none yet.
  CardAddress keyed(CardAddress a) {
    if (a.recordKey != null) return a;
    final k = recordKeyOf(a);
    return k == null ? a : a.withRecordKey(k);
  }

  /// [a] — an address of [n] — with the record key [n] named under ANY of its
  /// addresses: the `0x25` may have come from another family than the one a
  /// card or list names.
  CardAddress keyedOf(Neighbour n, CardAddress a) {
    if (a.recordKey != null) return a;
    for (final x in n.addresses) {
      final k = recordKeyOf(x.asCardAddress);
      if (k != null) return a.withRecordKey(k);
    }
    return a;
  }

  /// The device at [at] showed it reads keyed lists (its `0x24` bit, its
  /// keyed `0x25`) — in memory only, like the keys; a contact it belongs to
  /// keeps the mark ([NeighbourKeysContact.readsKeysOf]).
  void readsKeysAt(CardAddress at) => (_reads[this] ??= {}).add(_at(at));

  /// Whether any of [list] showed it.
  bool readsKeysAtAny(Iterable<CardAddress> list) =>
      list.any((a) => _reads[this]?.contains(_at(a)) ?? false);

  /// [keyed] for every entry of [list].
  List<CardAddress> keyedAll(Iterable<CardAddress> list) =>
      [for (final a in list) keyed(a)];
}

extension NeighbourKeysContact on Mailbox {
  /// Whether lists to [to] may carry keys: a contact that showed it, or one
  /// whose device did at this node (then the mark is kept from now on).
  bool readsKeysOf(Address to) {
    final k = contactOrNull(identifierFrom(to));
    if (k == null) return false;
    if (k.readsKeys) return true;
    if (!node.readsKeysAtAny([if (k.lastSeen case final s?) s, ...k.cardsAddresses])) {
      return false;
    }
    readsKeysShown(to);
    return true;
  }

  /// [to] showed it reads keyed lists; kept for a contact, ignored otherwise.
  void readsKeysShown(Address to) {
    final k = contactOrNull(identifierFrom(to));
    if (k == null || k.readsKeys) return;
    contactRemember(k.address, readsKeys: true);
    report?.call('contact ${identifierFrom(to).substring(0, 8)} reads keyed '
        'neighbour lists');
  }

  /// The own fixed neighbours as a message or acknowledgement to [to]
  /// names them (§9.2), and whether with keys.
  ({List<CardAddress> list, bool keys}) namedFor(Address to) =>
      (list: ownNeighbours, keys: readsKeysOf(to));

  /// A list came from [from] in a message or acknowledgement; [keyed]: it
  /// carried the bit.
  void neighboursCame(Address from, List<CardAddress> list, bool keyed) {
    if (keyed) readsKeysShown(from);
    if (list.isNotEmpty) neighboursHeard(from, list);
  }
}
