/// Addresses the shell proved to be this node itself (D-92 A.4, owner
/// 04.11.2026; reverses the S407-SHELLSELF note "no self-memory").
///
/// When the own flight 1 comes back (`shell_start.dart` `startOf`), the
/// address it went to reaches this very node — loopback, an own interface,
/// the own public address through the router (hairpin). `ownTarget` knew
/// only the interfaces and the LEARNED public address (§7.3); the proof of
/// the shell was used once, for that one start, and forgotten. So the node
/// kept treating such an address as a stranger: it deposited post there
/// over the wire, failed, and gave the post to holders the recipient never
/// asks (S412 `smoke_media_lane2_run` section 6, 17 proofs in the log
/// unused; `berichte/S412-RCA-LANE2-UND-MESSUNG-E2.md` finding 1).
///
/// **Memory only, forgotten at the next network change** (§11.8.2): after a
/// network change a former own address may belong to another node. The
/// edge is the one `node_roam.dart` asks too — [Readiness.resets] counts
/// every network change and stop; a set of an older count is dropped on the
/// next read. Nothing on disk, nothing on the wire, no clock.
///
/// **Price, named:** a router that later gives the same outer address and
/// port to another device makes this node take it for its own until the
/// next network change. At most [kOwnProvenAtMost] addresses (§20.2); the
/// oldest gives way.
library;

import 'dart:io';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/node.dart';

/// Addresses kept per node, at most (§20.2).
const int kOwnProvenAtMost = 64;

final Expando<Set<String>> _proven = Expando<Set<String>>('own proven');
final Expando<int> _edge = Expando<int>('own proven edge');

Set<String> _thisEdge(Node k) {
  if (_edge[k] != k.readiness.resets) {
    _edge[k] = k.readiness.resets;
    _proven[k]?.clear(); // a network change: what was proven belongs to the old network
  }
  return _proven[k] ??= <String>{};
}

String _key(InternetAddress a, int port) => '${a.address}:$port';

/// The shell proved [a]:[port] to be this node (`Shell.onSelf`).
void ownProvenNote(Node k, InternetAddress a, int port) {
  final s = _thisEdge(k);
  final key = _key(a, port);
  s.remove(key);
  s.add(key); // insertion order: a default Set is linked
  while (s.length > kOwnProvenAtMost) {
    s.remove(s.first);
  }
  k.report('Own address ${a.address}:$port remembered until the next network change (D-92)');
}

/// Whether the shell proved [to] to be this node since the last network change.
bool ownProven(Node k, CardAddress to) =>
    _thisEdge(k).contains(_key(InternetAddress.fromRawAddress(to.address), to.port));
