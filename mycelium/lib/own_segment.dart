/// Whether an address that is not reachable from the open network lies in
/// THIS device's own segment (V4.2 §7.2 "the addresses in the card that lie
/// in its own segment", §15.2 "whether its `192.168.x.y` is in *your*
/// segment is a fact about you"; owner decision 06.10.2026, S405 V6: a
/// private target address is written to only when it is in the same
/// network, otherwise discarded).
///
/// ── THE RULE ───────────────────────────────────────────────────────────
///
/// * An address reachable from the open network (`fromOutsideReachable`) is
///   no question of this file — steps 2, 3 and 4 serve it.
/// * The loopback is the own segment.
/// * Any other address (RFC 1918, link-local, CGNAT 100.64/10, IPv6 ULA)
///   is in the own segment when one of this device's interface addresses of
///   the same family shares its network prefix: **/24 for IPv4, /64 for
///   IPv6**. Dart's `NetworkInterface` names no prefix length, so the
///   prefix is the one home and office networks use; a wider network
///   (/16, /8) whose two devices sit in different /24s loses step 1
///   between them, and steps 3 and 4 carry — nothing is sent into the void.
///
/// The interfaces are the ones read at start and at every network change
/// (`node_helpers.dart` [interfaces], `Node.networkEnvironmentNewRead`), so
/// the answer follows the device from Wi-Fi into cellular.
library;

import 'dart:io';

import 'package:mycelium/node_helpers.dart' show interfaces;
import 'package:mycelium/outside_address.dart' show fromOutsideReachable;

/// Whether [a] — not reachable from the open network — lies in the own
/// segment; `true` for every address the open network reaches (see head).
bool inOwnSegment(InternetAddress a) {
  if (_allOwn || a.isLoopback || fromOutsideReachable(a)) return true;
  final raw = a.rawAddress;
  final prefix = raw.length == 4 ? 3 : 8;
  for (final i in interfaces) {
    for (final own in i.addresses) {
      final o = own.rawAddress;
      if (o.length != raw.length) continue;
      var same = true;
      for (var k = 0; k < prefix && same; k++) {
        same = o[k] == raw[k];
      }
      if (same) return true;
    }
  }
  return false;
}

bool _allOwn = false;

/// For smokes whose fixtures invent private addresses (`10.9.x.y`) to test
/// something other than the segment rule — seats, memory, readiness: every
/// address then counts as in the own segment. Product code never calls it;
/// the rule itself is stated by `smoke_own_segment.dart`.
void ownSegmentAssumeAllForTests() => _allOwn = true;
