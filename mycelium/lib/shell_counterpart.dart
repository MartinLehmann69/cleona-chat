/// One link per counterpart (V4.2 §11.8.7, D-92 A): a link may stand under
/// several addresses of one node, and it changes under all of them at once.
///
/// The shell keys its maps by address and port (`shellWho`); a node under
/// two addresses — Wi-Fi and cable, IPv4 and IPv6, a workstation with a
/// bridge — was therefore two counterparts with two keys. Its counterpart
/// keeps ONE key for this node (it sees one sender address), so every
/// second handshake to the other address replaced that key, and for the
/// node that started it the answer came from the wrong address (S412 RCA
/// B-1, gui-34: 14 s in which neither side could open the other's packets).
///
/// The rules here, each named in §11.8.7:
///
/// * An address its list joins to a neighbour that holds a link uses that
///   link ([nodeLink]); no second handshake is started to it.
/// * The answer to a handshake is bound to that handshake (§4.2: both
///   Elligator shares are its additional data, `shell_start.dart`), not to
///   an address: arriving from another address under the same port it is
///   the answer all the same ([answerElsewhere]), and the link stands under
///   both.
/// * A new key for one address of a counterpart is the new key for every
///   address holding the same link ([linkPut]); a link that expires,
///   expires under all of them ([linkDrop]).
///
/// **What it costs, named.** No packet, no clock, nothing on the wire. A
/// packet that opens under no link and answers no start at its own address
/// is tried against the running starts under the same port at OTHER
/// addresses — one X25519 and one AES-GCM verification each (the ML-KEM
/// decapsulation runs only once that verification held), well under a
/// millisecond; without a running start under that port, nothing. A forger
/// gains nothing by it: without the Elligator share of the start nothing
/// opens.
///
/// **The bound** stays the one of `capLinks`: at most [kLinksAtMost]
/// entries, so at most that many links; a link under two addresses takes
/// two of them.
///
/// Separate from `shell.dart`, which is at the line budget of 400
/// (mycelium/README.md rule 2).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/shell_link.dart';
import 'package:mycelium/shell_start.dart' show Start, complete;

/// The other addresses the neighbour list holds for the node at [a]:[port]
/// (§11.8: "a neighbour is a node, not an address"); empty if none.
typedef SameNode = List<(InternetAddress, int)> Function(
    InternetAddress a, int port);

/// The link for [w]: its own, or — if it has none — the link of another
/// address of the same node ([others], `shellWho` form), which [w] then
/// holds as well. `null` if neither holds one.
Link? nodeLink(Map<String, Link> links, String w, Iterable<String> others) {
  final own = links[w];
  if (own != null) return own;
  for (final o in others) {
    final l = links[o];
    if (l != null) return links[w] = l;
  }
  return null;
}

/// [n] stands under [w] and under every address that held [w]'s link.
void linkPut(Map<String, Link> links, String w, Link n) {
  final old = links[w];
  if (old != null) {
    for (final e in links.entries.toList()) {
      if (identical(e.value, old)) links[e.key] = n;
    }
  }
  links[w] = n;
}

/// [l] leaves every address it stands under; [gone] is told each.
void linkDrop(Map<String, Link> links, Link l, void Function(String) gone) {
  for (final e in links.entries.toList()) {
    if (!identical(e.value, l)) continue;
    links.remove(e.key);
    gone(e.key);
  }
}

/// A packet from [w] opened under the link of [moved], not under [w]'s own
/// key [l] (none, or one that opened nothing). `true`: [w] holds a link now
/// under which the packet is read.
///
/// * [w] and [moved] are one node by the list ([same]): [w] takes that link
///   (D-92 A.3, receiving side).
/// * Otherwise — no key at [w], or a key that is not that node's by the
///   list — the path request decides (§11.8.6 "a packet opens under a link
///   and comes from an address that is not a confirmed address of that
///   counterpart"): [move] (`Shell.onMoved`) may lend [moved]'s link to [w]
///   for it, so the standing key gives way meanwhile; when no request was
///   started, it stays. Never a silent drop (S412 E2E run 8,
///   `smoke_media_seed_kept_run`: a counterpart restarted under the same
///   port, its second address a neighbour of its own — four packets gone).
///
/// The price (rule 5): at most the one request of §11.8.6 per address and
/// edge (`node_roam.dart`); nothing periodic. A packet of a third node
/// replayed with [w] as its sender costs [w] its standing key once the
/// request fails (`roamUnlend`); [w]'s owner then sets up anew after two
/// unreadable packets (§11.8.7) — the class of a forged flight 1, named.
bool roamReceive(Map<String, Link> links, String w, String moved, Link? l,
    Iterable<String> same, void Function()? move) {
  if (l != null && same.contains(moved)) {
    linkPut(links, w, links[moved]!);
    return true;
  }
  if (move == null) return false;
  if (l != null) links.remove(w);
  move();
  if (links.containsKey(w)) return true;
  if (l != null) links[w] = l;
  return false;
}

/// The start (its `shellWho` key) at ANOTHER address than [w] under the
/// same [port] that [p] answers, with the link key — or `null`.
(String, Uint8List)? answerElsewhere(
    Map<String, Start> running, Uint8List p, String w, int port) {
  final tail = ':$port';
  for (final e in running.entries.toList()) {
    if (e.key == w || !e.key.endsWith(tail)) continue;
    final k = complete(e.value, p);
    if (k != null) return (e.key, k);
  }
  return null;
}

/// A move (`shell_roam.dart`): [to] borrows [old]'s link; `false` if [old]
/// holds none or [to] holds one already.
bool roamLend(Map<String, Link> links, String to, String old) {
  final l = links[old];
  if (l == null || links.containsKey(to)) return false;
  links[to] = l;
  return true;
}

/// The path request failed: [to] loses the borrowed link again.
void roamUnlend(Map<String, Link> links, String to, String old) {
  if (identical(links[to], links[old])) links.remove(to);
}
