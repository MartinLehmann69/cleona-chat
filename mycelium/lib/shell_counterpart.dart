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

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/shell_key_history.dart' show KeyHistory;
import 'package:mycelium/shell_link.dart';
import 'package:mycelium/shell_start.dart' show Start, complete;

/// The other addresses the neighbour list holds for the node at [a]:[port]
/// (§11.8: "a neighbour is a node, not an address"); empty if none.
typedef SameNode = List<(InternetAddress, int)> Function(
    InternetAddress a, int port);

/// The link for [w]: its own, or — if it has none — the link of another
/// address of the same node ([others], `shellWho` form), which [w] then
/// holds as well. `null` if neither holds one.
/// [trace] (S425 N3-3 measurement, only with tracing): names the address
/// whose link [w] borrows.
Link? nodeLink(Map<String, Link> links, String w, Iterable<String> others,
    [void Function(String)? trace]) {
  final own = links[w];
  if (own != null) return own;
  for (final o in others) {
    final l = links[o];
    if (l != null) {
      trace?.call('TRACE shell send to $w under the link of $o (same node, D-92 A.3)');
      return links[w] = l;
    }
  }
  return null;
}

/// Whether [a] and [b] (`shellWho` form) stand under ONE link (D-92, §11.8.4,
/// S425 D73B-2): an answer from [b] to a request sent to [a] is then [a]'s
/// answer — RFC 9000 §8.2.3 (§11.8.6 "as QUIC does it"): a response on any
/// path validates the path the challenge went on. A multi-homed counterpart
/// answers from the address its routing picks, not the one it was asked at.
bool oneLink(Map<String, Link> links, String a, String b) {
  final l = links[a];
  return l != null && identical(l, links[b]);
}

/// The test the layers above the shell use (`Shell.sameCounterpart`); without
/// a shell (probes on the raw wire) they keep the strict address comparison.
typedef SameCounterpart = bool Function(
    InternetAddress a, int ap, InternetAddress b, int bp);

/// [asked] when [from] is it or stands under its link ([same]), else `null`.
(InternetAddress, int)? askedOf(SameCounterpart? same,
        (InternetAddress, int) asked, InternetAddress from, int fromPort) =>
    (asked.$1.address == from.address && asked.$2 == fromPort) ||
            (same?.call(asked.$1, asked.$2, from, fromPort) ?? false)
        ? asked
        : null;

/// The one of [asked] an answer from [from] belongs to (D73B-2, §11.8.4):
/// [from] itself when it was asked, else an asked address under the same
/// link ([same]), else [from] unchanged. For layers that key by
/// [CardAddress] (the durable-object class).
CardAddress askedCard(
    SameCounterpart? same, List<CardAddress> asked, CardAddress from) {
  String key(CardAddress c) =>
      '${InternetAddress.fromRawAddress(c.address).address}:${c.port}';
  if (asked.any((a) => key(a) == key(from))) return from;
  final f = InternetAddress.fromRawAddress(from.address);
  for (final a in asked) {
    final x = (InternetAddress.fromRawAddress(a.address), a.port);
    if (askedOf(same, x, f, from.port) != null) return a;
  }
  return from;
}

/// [n] stands under [w] and under every address that held [w]'s link.
/// [replaced] (tracing only, S426 AVM-M1) is told the link that gave way
/// and the addresses it stood under.
void linkPut(Map<String, Link> links, String w, Link n,
    [void Function(Link old, List<String> at)? replaced]) {
  final old = links[w];
  if (old != null && !identical(old, n)) {
    final at = <String>[];
    for (final e in links.entries.toList()) {
      if (identical(e.value, old)) {
        links[e.key] = n;
        at.add(e.key);
      }
    }
    replaced?.call(old, at);
  }
  links[w] = n;
}

/// [linkPut] under [w] and, when it is another key, under [also] (the
/// address the handshake went to). Out of `shell.dart` for the line budget.
void linkPutAlso(Map<String, Link> links, String w, String? also, Link n,
    [void Function(Link old, List<String> at)? replaced]) {
  linkPut(links, w, n, replaced);
  if (also != null && also != w) linkPut(links, also, n, replaced);
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

/// S425 N5-1 (73.W2) trace, used only with tracing on: "opens under no link"
/// for an address at most once per [every], with the number of such packets
/// since its last line — the once-per-life mark was blind for a sender port
/// that had been heard hours earlier. At most 64 addresses.
class UnopenedTrace {
  UnopenedTrace(this._now, [this.every = const Duration(seconds: 30)])
      : keys = KeyHistory(_now);
  final DateTime Function() _now;
  final Duration every;
  final Map<String, (DateTime, int)> _seen = {};

  /// The replaced and dropped keys (S426 AVM-M1, `shell_key_history.dart`).
  final KeyHistory keys;

  /// The line for a packet from [w], or null while [every] has not passed.
  String? note(String w, int held) {
    final now = _now();
    final s = _seen[w];
    if (s != null && now.difference(s.$1) < every) {
      _seen[w] = (s.$1, s.$2 + 1);
      return null;
    }
    if (s == null && _seen.length >= 64) _seen.remove(_seen.keys.first);
    _seen[w] = (now, 0);
    return 'TRACE shell packet from $w opens under no link ($held held)'
        '${s == null ? '' : ', ${s.$2} more since the last line'}';
  }
}
