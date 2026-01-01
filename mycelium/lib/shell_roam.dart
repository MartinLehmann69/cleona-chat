/// Roaming of a neighbour to a new address (V4.2 §11.8 "a neighbour that is
/// gone returns … from whatever address"; owner 14.10.2026; the pattern of
/// QUIC connection migration and WireGuard roaming, validated as in §17.4).
///
/// The shell is anonymous and keyed by address and port (`shellWho`): a
/// packet from a moved neighbour's NEW address finds no link. Before such a
/// packet is taken as half of a foreign flight 1, it is tried under the keys
/// of the links that stand ([kLinksAtMost] at most). If it opens under the
/// key of address X, the node of X has moved: the new address is a HINT.
/// Its content is NOT delivered — the shell has no replay protection
/// (`shell.dart` head), so a replayed old packet from a forged address
/// would otherwise count. The new address becomes the node's current one
/// only when a request sent to it under X's key is answered
/// (`Shell.roamValidate`, path validation): a replay cannot answer a fresh
/// question. Nothing extra goes on the wire.
///
/// **Cost, named:** a 1200-B packet from an address without a link and
/// without a running handshake costs up to [kLinksAtMost] (64) trial
/// opens (one AEAD verification each, ~1 µs for 1200 B) before it is
/// treated as before. A forger can make the node do that per forged packet;
/// the bound is the number of links, not the traffic.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/shell_link.dart';
import 'package:mycelium/shell_start.dart' show unpack;

/// The address [w] (`shellWho` form) names, or `null`.
(InternetAddress, int)? whoAddress(String w) {
  final i = w.lastIndexOf(':');
  if (i <= 0) return null;
  final a = InternetAddress.tryParse(w.substring(0, i));
  final p = int.tryParse(w.substring(i + 1));
  return a == null || p == null ? null : (a, p);
}

/// The link (by its `shellWho` key) under whose receive key [p] opens, or
/// `null`. [except]: the key the packet came from (already tried). A link lent
/// to a moved counterpart stands under several keys: the newest one wins — the
/// address it last moved to, not the first it was ever heard under, which may
/// have been removed long ago (S411).
String? roamOpen(Map<String, Link> links, Uint8List p, String except) {
  for (final e in links.entries.toList().reversed) {
    if (e.key == except) continue;
    if (unpack(p, e.value.receiveKey) != null) return e.key;
  }
  return null;
}

/// A moved neighbour: [old] (`shellWho`) was its address, [to]:[toPort] is
/// the one its packet came from.
typedef Moved = void Function(
    InternetAddress oldAddress, int oldPort, InternetAddress to, int toPort);
