import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card.dart' show CardAddress, CardAddressType;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart'
    show hexFrom, shortFrom, interfaces, roll;
import 'package:mycelium/neighbourhood.dart' show Neighbourhood;
import 'package:mycelium/neighbours.dart' as nb;

/// Open the call in the segment and carry its finds into the node.
///
/// Its own file, because `node.dart` is at the line budget and because the
/// cut holds: here is HOW a neighbour is found, over there, what
/// the node does with it. A free function instead of an `extension`,
/// because it runs BEFORE the finished node — while `Node.start`
/// is still building.
///
/// It gets by with the public side of [Node]:
/// [Node.neighbourhood], [Node.coverStream], [Node.identities],
/// [Node.foundNeighbours].
///
/// **At start, the call is made ONCE** (G1, S385). Until then `call()`
/// had only the ladder as caller: two freshly started nodes without remembered
/// neighbours, both sending nothing, never found each other. §11.8 requires all
/// sources at start simultaneously. Afterwards there is silence — no clock.
Future<nb.Neighbours> neighbourSearchOpen(
  Node k, {
  required int dataPort,
  required void Function(String) report,
  void Function()? onNewNeighbours,
}) async {
  // Call D (S385): a NODE identifier, rolled anew each start, with no relation to
  // any identity. Until here the identifier of the
  // first identity stood in the call — every device in the segment saw with every call
  // which identity runs under which IP, and whoever had the card
  // could compute it.
  final own = hexFrom(k.nodeIdentifier);
  // S391/W8: a foreign call is a HINT, the answer to one's own
  // call a CONFIRMATION — it answered a packet of this node
  // that expected an answer (§11.8 „Every packet that expects an answer
  // — the neighbour call, ...").
  void find(String identifier, InternetAddress address, int port, bool answer) {
    if (identifier == own) return; // one's own call
    // `neighbourAdd` reports only a NEW one as new — the edge must
    // not fire on every answer.
    final fresh = neighbourAdd(k, address.rawAddress, port);
    // B1 (S388): whoever names its node identifier counts ONCE under each of its
    // addresses (`readiness.dart`). One's own address is neither
    // entered nor confirmed.
    if (answer && !_ownTarget(k, address, port)) {
      k.readiness.nodeLearn(address, port, identifier);
    } else {
      k.readiness.identifierRemember(address, port, identifier);
    }
    if (!fresh) return;
    report('Neighbour found: ${shortFrom(identifier)} at '
        '${address.address}:$port');
    onNewNeighbours?.call();
  }

  final n = await nb.Neighbours.open(
    own,
    (identifier, address, port) => find(identifier, address, port, false),
    onAnswer: (identifier, address, port) => find(identifier, address, port, true),
    // THE DATA PORT, not the call port: the answer comes from the
    // listening post on 41341, whose sender port accepts nothing
    // (measured 14.09.2026, S384).
    dataPort: dataPort,
    report: report,
    // Call D: a search call is answered only by whoever HOLDS the identifier — with
    // the Ed25519 signature of this identity (S388, proposal C).
    sign: (identifier, data) {
      for (final i in k.identities) {
        if (i.identifierHex == identifier) return i.postBox.signEd25519(data);
      }
      return null;
    },
    onFind: (identifier, address, port, data, signature) =>
        _onFind[k]?.call(
            identifier,
            CardAddress(Uint8List.fromList(address.rawAddress), port),
            data,
            signature) ==
        true,
  );
  _search[k] = n;
  return n..call();
}

/// Enters [ip]:[port] as a HINT (without stamp, `neighbourhood.dart`)
/// and passes the list on to the cover stream. `true` if it was NEW. One's
/// own address (loopback or own interface, own port)
/// is never entered — a card or an external entry may
/// name it.
///
/// The entry path for sources 2–4 (§11.8): the call, the addresses of a
/// card and the external entries all go through here. **Source 1 bypasses
/// this** (`Neighbourhood.outMemory`) — that is why the
/// check whether an address can be a neighbour at all sits one level
/// lower in [Neighbourhood.possible] and not here.
///
/// S389: card (source 3) and relay entry (source 4) are bytes from a
/// foreign hand. A broadcast or group target in them was until here
/// remembered, saved and loaded again at the next start; the first
/// throw at a broadcast without permission closes the wire forever, in
/// both directions (`wire_target.dart`). A port 0 even threw out of the
/// constructor of `Neighbour` — in the middle of the join.
bool neighbourAdd(Node k, List<int> ip, int port) {
  // S390: here stood `ip.length != 4` — „only IPv4 is remembered". That was
  // the SECOND door next to `Neighbourhood.possible`, and it leads the
  // sources 2 (call), 3 (card, via `Host.neighbourRemember`) and 4
  // (relay entry, `host_outside.dart`). Without it the fallen
  // bolt one level lower would have remained without effect: only source 1
  // (`outMemory`, which bypasses this) would have carried IPv6.
  // The same question is checked as there — a length the card
  // knows; anything else would make `fromRawAddress` throw right below.
  if (CardAddressType.fromLength(ip.length) == null) return false;
  final a = InternetAddress.fromRawAddress(Uint8List.fromList(ip));
  // S394 diagnosis: the neighbourhood stayed at 2 although source 4 read 12
  // addresses — nothing said which door each address met.
  if (_ownTarget(k, a, port)) {
    k.report('Neighbour hint ${a.address}:$port not admitted — own address');
    return false;
  }
  final known = k.neighbourhood.holding(a, port) != null;
  final fresh = k.neighbourhood.remember(a, port);
  // S394 V1 (§11.1): a hint in an address family without socket is neither
  // stored nor tried — measured 24.09.2026, Node1 without IPv6 admitted
  // IPv6 hints and tried them.
  k.report('Neighbour hint ${a.address}:$port '
      '${fresh ? "admitted" : known ? "already known" : !k.speaks(a) ? "not admitted — no socket for its address family (§11.1)" : Neighbourhood.possible(a, port) ? "fell over the cap" : "not admitted — impossible target"}'
      ' (list ${k.neighbourhood.all.length})');
  k.coverStream.neighboursSet(
      k.foundNeighbours.map((n) => (n.address, n.port)).toList());
  return fresh;
}

/// One's own address: loopback or own interface, own port.
bool _ownTarget(Node k, InternetAddress a, int port) =>
    port == k.port && (a.isLoopback || _ownAddress(a));

bool _ownAddress(InternetAddress a) => interfaces
    .any((s) => s.addresses.any((x) => x.address == a.address));

/// The neighbour search of a node and the receiver of its finds — next to
/// the node instead of in it: `node.dart` is at the line budget.
final Expando<nb.Neighbours> _search = Expando<nb.Neighbours>('search');
final Expando<FindAccept> _onFind = Expando<FindAccept>('onFind');
final Expando<Uint8List> _nodeIdentifier = Expando<Uint8List>('nodeIdentifier');

/// Accepts a find: identifier (hex), data address of the holder, the data
/// that the searched identity must have signed, and the signature from
/// the packet. `true` only if the signature held and the route is set.
typedef FindAccept = bool Function(
    String identifier, CardAddress where, Uint8List data, Uint8List signature);

/// Search call and find at the node (call D, S385).
extension NodeCall on Node {
  /// The node identifier (16 B, new each start, without identity relation, call D).
  /// It stands in the neighbour call and since S388 (B1) in the answers of a
  /// holder (`0x31`, `0x35`), so that a node under two addresses counts
  /// once. Here instead of in `node.dart`, which is at the line budget.
  Uint8List get nodeIdentifier => _nodeIdentifier[this] ??= roll(16);

  /// Searches the identity with [identifier] (32 B) in the segment — only to be called
  /// when a sending to it has no route. See `Neighbours.search`.
  void search(Uint8List identifier) => _search[this]?.search(hexFrom(identifier));

  /// One call series in the segment — for the network change (§11.8: „the neighbour
  /// call is repeated once"). If one is already running, the call does nothing. The
  /// Future ends with the series (`Neighbours.call`).
  Future<void> call() {
    // S394 diagnosis: whether the call went out at a network change, and
    // what it found, was not readable.
    final s = _search[this];
    if (s == null) {
      report('Neighbour call: no search socket — not called');
      return Future.value();
    }
    final started = DateTime.now();
    report('Neighbour call: started');
    return s.call().then((_) => report('Neighbour call: ended after '
        '${DateTime.now().difference(started).inMilliseconds} ms — '
        '${neighbourhood.all.length} neighbour(s)'));
  }

  /// The end of the running call series — the one at start or the one last
  /// triggered; immediately if none is running.
  Future<void> get callSeriesDone => _search[this]?.rowDone ?? Future.value();

  /// Who gets a find and CHECKS it — the host, whose mailboxes hold the
  /// keys of the contacts.
  FindAccept? get onFind => _onFind[this];
  set onFind(FindAccept? f) => _onFind[this] = f;
}
