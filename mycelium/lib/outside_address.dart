/// Which address of this device is reachable from OUTSIDE (V4.2 §11.9) —
/// and how many of them belong in an address entry.
///
/// ── WHY A FILE OF ITS OWN ────────────────────────────────────────────────────
///
/// §11.9 (version 16.09.2026) makes this question the ONLY condition for
/// publishing: „Publishing follows reachability, not need: every node
/// that has an address through which it can be reached — a global IPv6, or a
/// public IPv4 — publishes its record […] A node behind CGNAT has no such
/// address and publishes nothing."
///
/// Until S390 the verdict stood as a private `_global` in `host_outside.dart`,
/// and it had two holes (S390-INVENTUR-IPV6-KARTE, D2-7 and D2-8):
/// a confirmed public address went past it unchecked, and
/// IPv6 did not occur at all. Both are closed here, at ONE
/// place through which both routes run.
///
/// ── WHAT IS REJECTED, AND BY WHICH RFC ─────────────────────────────
///
/// IPv4
///   * `0.0.0.0/8`        „this network"            RFC 1122 §3.2.1.3
///   * `10/8`, `172.16/12`, `192.168/16`  private   RFC 1918 §3
///   * `100.64.0.0/10`    CGNAT                     RFC 6598 §7
///   * `127/8`            loopback                  RFC 1122 §3.2.1.3
///   * `169.254.0.0/16`   link-local                RFC 3927 §2.1
///   * `192.0.0.0/24`     IETF assignments, within
///                        DS-Lite `192.0.0.0/29`    RFC 6890 §2.1, RFC 6333 §5.7
///   * `224.0.0.0/4`      multicast                 RFC 5771 §1
///   * `240.0.0.0/4`      reserved, with
///                        `255.255.255.255`         RFC 1112 §4, RFC 919 §7
///
/// IPv6
///   * `::`               unspecified               RFC 4291 §2.5.2
///   * `::1`              loopback                  RFC 4291 §2.5.3
///   * `::ffff:0:0/96`    IPv4-mapped               RFC 4291 §2.5.5.2
///   * `64:ff9b::/96`     NAT64 prefix              RFC 6052 §2.1
///   * `100::/64`         discard range             RFC 6666 §2
///   * `2001:0::/32`      Teredo tunnel             RFC 4380 §2.6
///   * `2002::/16`        6to4 tunnel               RFC 3056 §2, RFC 7526
///   * `fc00::/7`         ULA                       RFC 4193 §3
///   * `fe80::/10`        link-local                RFC 4291 §2.5.6
///   * `ff00::/8`         multicast                 RFC 4291 §2.7
///
/// Teredo and 6to4 are here because on the OWN interface they are
/// pseudo-interfaces — measured under Windows (WIN-2,
/// `lib/core/util/local_addresses.dart::isTunnelIpv6`). They are globally
/// routed, but nothing answers under them; publishing them is
/// the same error as D2-7, just on a different platform.
///
/// NOT rejected are the documentation ranges `192.0.2.0/24`,
/// `198.51.100.0/24`, `203.0.113.0/24` (RFC 5737 §3) and `2001:db8::/32`
/// (RFC 3849 §4). That is a DECISION, not a gap: the probes
/// of this area imitate a public address with exactly these addresses,
/// without ever touching a real one. A filter on them would make
/// every probe of the write path impossible and would never take effect in operation —
/// no interface carries them.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/own_address.dart' show linkKindFrom;
import 'package:mycelium/outside_entry.dart' show kEntryAddressesAtMost;
import 'package:mycelium/card.dart' show CardAddress, CardAddressType;

/// `true` if [a] is an address under which a node can be reached from the
/// public network. See the header for every
/// rejected class and its RFC.
bool fromOutsideReachable(InternetAddress a) {
  final b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4) {
    if (b.length != 4) return false;
    if (b[0] == 0) return false; // 0.0.0.0/8
    if (b[0] == 10) return false; // 10/8
    if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return false; // 100.64/10
    if (b[0] == 127) return false; // 127/8
    if (b[0] == 169 && b[1] == 254) return false; // 169.254/16
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return false; // 172.16/12
    if (b[0] == 192 && b[1] == 0 && b[2] == 0) return false; // 192.0.0.0/24
    if (b[0] == 192 && b[1] == 168) return false; // 192.168/16
    if (b[0] >= 224) return false; // 224/4 Multicast, 240/4 reserviert
    return true;
  }
  if (b.length != 16) return false;
  if (b[0] == 0xFF) return false; // ff00::/8
  if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) return false; // fe80::/10
  if ((b[0] & 0xFE) == 0xFC) return false; // fc00::/7
  if (_prefix(b, const [0x00, 0x64, 0xFF, 0x9B], 12)) return false; // 64:ff9b::/96
  if (_prefix(b, const [0x01, 0x00], 8)) return false; // 100::/64
  if (b[0] == 0x20 && b[1] == 0x02) return false; // 2002::/16 6to4
  if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0 && b[3] == 0) {
    return false; // 2001:0::/32 Teredo
  }
  // `::`, `::1` and `::ffff:0:0/96` share ten leading zero bytes.
  if (_prefix(b, const [], 10)) return false;
  return true;
}

/// `true` if [b] begins with [header] and after that carries only zero bytes
/// up to [until] — the prefix checks above in one line.
bool _prefix(Uint8List b, List<int> header, int until) {
  for (var i = 0; i < header.length; i++) {
    if (b[i] != header[i]) return false;
  }
  for (var i = header.length; i < until; i++) {
    if (b[i] != 0) return false;
  }
  return true;
}

/// Up to [kEntryAddressesAtMost] addresses under which this node is
/// reachable from outside — or empty. Called `outsideAddresses` and
/// not `erreichbareAdressen` because [OutsideSource] until S392 carried a
/// method of the same name and the call there would otherwise have pointed
/// at itself; the method fell as dead code, the name
/// stays so that the repetition does not return.
///
/// ORDER, and it is the statement (§11.9 „addresses", plural):
///   1. [confirmed] — what a counterpart outside the segment has seen.
///      It is the only one that knows a mapping through a NAT,
///      and therefore the most valuable.
///   2. global IPv6 of an own interface — no NAT in front of it (§11.1).
///   3. global IPv4 of an own interface.
/// Duplicates drop out; [confirmed] is sent through the same check
/// as everything else (D2-7).
///
/// [port] is the fixed data port of the node; the interface addresses
/// carry none.
///
/// [interfaces] has carried BOTH address types since S390
/// (`interfacesRead` calls `NetworkInterface.list()` without filter) —
/// as long as `type: InternetAddressType.IPv4` stood there, a node never saw
/// its own global IPv6 and therefore wrote no entry,
/// although it was reachable from outside.
List<CardAddress> outsideAddresses({
  required CardAddress? confirmed,
  required int port,
  required List<NetworkInterface> interfaces,
}) {
  final out = <String, CardAddress>{};
  void take(CardAddress a) {
    if (out.length >= kEntryAddressesAtMost) return;
    out.putIfAbsent('$a', () => a);
  }

  if (confirmed != null &&
      fromOutsideReachable(
          InternetAddress.fromRawAddress(confirmed.address))) {
    take(confirmed);
  }
  // Within an address type the LINK decides (§10, §23.1:
  // „cellular as the last choice"). A phone with WLAN and cellular possibly has
  // a global IPv6 under both; the entry gets the
  // WLAN one first, because the route there costs nothing.
  final ordered = List<NetworkInterface>.of(interfaces)
    ..sort((x, y) => linkKindFrom(y.name)
        .priority
        .compareTo(linkKindFrom(x.name).priority));
  for (final kind in const [CardAddressType.ipv6, CardAddressType.ipv4]) {
    for (final s in ordered) {
      for (final a in s.addresses) {
        if (a.rawAddress.length != kind.addressLength) continue;
        if (!fromOutsideReachable(a)) continue;
        take(CardAddress(Uint8List.fromList(a.rawAddress), port));
      }
    }
  }
  return out.values.toList();
}

/// `true` if both lists carry the same addresses in the same order
/// — the byte equality on which the refresh gate depends
/// (§11.9 „while the addresses are byte-identical").
bool addressesEqual(List<CardAddress> a, List<CardAddress> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!a[i].equal(b[i])) return false;
  }
  return true;
}
