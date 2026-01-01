/// The addresses this node left behind in this run (§11.8.3, §11.8.9).
///
/// After a move a neighbour's address list (§5.5, §11.8a) still names this
/// node under its old address: the entry stays confirmed for a day there, and
/// nothing tells the neighbour otherwise (§11.8.5). [ownTarget] knows only the
/// current addresses, so such an entry became a hint, a handshake and, without
/// an answer, a removal — an edge (§11.8.2). Field 30.10.–02.11.2026
/// (`berichte/S411-HINWEISE-NACHBARN.md`): 66 of 163 admitted hints, none of
/// which could answer.
///
/// Only a hint is refused here. A foreign node that happens to hold the
/// address and port now loses one hint and stays reachable by every other way.
/// Memory only, per run: an entry lives a day at most, and no format changes.
library;

import 'dart:io';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/own_entries.dart' show cardOwnAddresses;

/// Addresses kept per node, at most (§20.2); the oldest gives way.
const int kOwnFormerAtMost = 64;

final Expando<Set<String>> _former = Expando<Set<String>>('own former');

String _key(CardAddress a) =>
    '${InternetAddress.fromRawAddress(a.address).address}:${a.port}';

/// To be called at the edge network change, BEFORE the interfaces are read
/// anew: what the node stands under now is what it may be leaving.
void ownFormerNote(Node k) {
  final s = _former[k] ??= <String>{}; // insertion order: a default Set is linked
  for (final a in cardOwnAddresses(k)) {
    final key = _key(a);
    s.remove(key);
    s.add(key);
  }
  while (s.length > kOwnFormerAtMost) {
    s.remove(s.first);
  }
}

/// Whether this node stood under [a] earlier in this run.
bool ownFormer(Node k, CardAddress a) => _former[k]?.contains(_key(a)) ?? false;
