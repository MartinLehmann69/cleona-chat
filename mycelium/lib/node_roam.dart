/// Return and move: one rule (V4.2 §11.8.6; owner 14.10.2026).
///
/// A packet opens under a link (§11.8.7) and comes from an address that is
/// not a confirmed address of that counterpart — the address is removed or
/// silent ([Readiness.flagged]), or the counterpart moved there (the packet
/// opened under the link of ANOTHER address, `shell_roam.dart`). Then this
/// node sends that address ONE request: the address question `0x40` of §7.3,
/// repeated as §11.3a says. Only its answer confirms the address — it lifts
/// the removal, takes the address into the list as confirmed and makes the
/// neighbour answering again ([Readiness.returned]). Until the answer the
/// packet is handled as any packet, but it confirms, lifts and adopts
/// nothing. A replayed packet, or one whose sender cannot be reached there,
/// brings no answer and changes nothing — path validation as QUIC does it
/// (RFC 9000 §8.2) and §17.4 for calls.
///
/// At most one request per address and edge: an address whose request
/// stayed unanswered is not asked again before the next network change
/// ([Readiness.resets]). At most [kPathChecksAtMost] addresses are remembered.
library;

import 'dart:async';
import 'dart:io';

import 'package:mycelium/node.dart';
import 'package:mycelium/shell.dart';

/// Addresses asked in this edge, at most (§20.2).
const int kPathChecksAtMost = 64;

/// Address → its one request in this edge; a request that stayed
/// unanswered stays here until the next network change.
final Expando<Map<String, Future<bool>>> _asked =
    Expando<Map<String, Future<bool>>>('path asked');
final Expando<int> _edge = Expando<int>('path edge');

/// A packet opened under the link of [a]:[p] itself (`Shell.onHeard`).
void nodeHeard(Node k, InternetAddress a, int p) {
  if (k.readiness.flagged(a, p)) _pathCheck(k, a, p);
}

/// A packet from [to]:[toPort] opened under the link of [old]:[oldPort]
/// (`Shell.onMoved`): its counterpart moved. [to] borrows that link at once,
/// so that the packet is read and answered (§11.8.6 "handled as any
/// packet"); the request decides whether it stays.
void nodeMoved(Node k, Shell shell, InternetAddress old, int oldPort,
    InternetAddress to, int toPort) {
  if (!shell.roamValidate(to, toPort, old, oldPort)) return;
  // Into the neighbour list only what was a neighbour (§11.8.6 "the
  // neighbour's set"); another link keeps just its new address.
  final neighbour = k.neighbourhood.holding(old, oldPort) != null ||
      k.readiness.dropped.removedAt(old, oldPort) != null;
  k.report('Roam: ${old.address}:$oldPort seen at ${to.address}:$toPort — '
      'path request');
  void end() => shell.roamEnd(to, toPort, old, oldPort);
  // Asked in this edge already without an answer: nothing is lent again.
  if (!_pathCheck(k, to, toPort, adopt: neighbour, onFail: end)) end();
}

/// Whether [a]:[p] answers its one request of this edge (§11.8.6) — for
/// the code table, which moves a device's entry only on that answer
/// (§8.1, §11.8.9; `code_move.dart`). A request already out for the address
/// is joined, not repeated; one that stayed unanswered in this edge is
/// `false` at once. The answer adopts nothing into the neighbour list.
Future<bool> nodePathAnswered(Node k, InternetAddress a, int p) {
  final asked = _thisEdge(k);
  return asked['${a.address}:$p'] ?? _request(k, asked, a, p, adopt: false);
}

/// `false` if [a]:[p] was asked in this edge already.
bool _pathCheck(Node k, InternetAddress a, int p,
    {bool adopt = true, void Function()? onFail}) {
  final asked = _thisEdge(k);
  if (asked.containsKey('${a.address}:$p')) return false;
  unawaited(_request(k, asked, a, p, adopt: adopt, onFail: onFail));
  return true;
}

Map<String, Future<bool>> _thisEdge(Node k) {
  if (_edge[k] != k.readiness.resets) {
    _edge[k] = k.readiness.resets;
    _asked[k]?.clear(); // a new edge: every address may be asked once again
  }
  return _asked[k] ??= {};
}

Future<bool> _request(
    Node k, Map<String, Future<bool>> asked, InternetAddress a, int p,
    {required bool adopt, void Function()? onFail}) {
  final key = '${a.address}:$p';
  late final Future<bool> f;
  f = k.outsideRoute.whatIsMyAddress(a, p).then((seen) {
    if (seen == null) {
      onFail?.call();
      k.report('Roam: $key did not answer its path request — nothing adopted');
      return false;
    }
    if (identical(asked[key], f)) asked.remove(key);
    if (adopt) k.readiness.returned(a, p);
    k.report('Roam: $key answered — confirmed (§11.8.6)');
    return true;
  });
  asked[key] = f;
  while (asked.length > kPathChecksAtMost) {
    asked.remove(asked.keys.first);
  }
  return f;
}
