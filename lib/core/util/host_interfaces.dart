/// Which network interfaces of this device lead to the OUTSIDE.
///
/// ── WHY THIS FILE STANDS HERE AND NOT IN `tagline/` (S376, P2-4) ──
///
/// [isHostInternalInterface] arose on 07.09.2026 in
/// `tagline/local_addresses.dart` (S374, finding B-4) and was also only used
/// there: in the two enumerations of `dialableLocalAddresses`.
/// Six further loops in the tree ask the same question — "which of my
/// addresses/interfaces count" — and none of them could call the
/// filter without drawing an edge that must not exist:
/// `link_io/nat_pmp.dart` and `link_io/upnp_igd.dart` lie BELOW
/// `tagline/` (measured 08.09.2026: `link_io/` imports `tagline/` at
/// zero places), and `lib/service_daemon.dart` as well as
/// `ui/components/share_cleona_dialog.dart` lie next to it.
///
/// The filter therefore belongs where every layer may read it.
/// **Moved completely, no forwarding** left behind in
/// `local_addresses.dart`: a forwarding would be a
/// second access to the same function — the pattern that AP-1b records as
/// harmful and that was measured a second time in P2-3 on the same day
/// (two literals for one port).
///
/// ── WHAT CARRIES THE DISTINCTION ──────────────────────────────────
///
/// Virtual bridges carry ordinary RFC 1918 addresses: `virbr0`
/// gets `192.168.122.1` from libvirt, `docker0` typically
/// `172.17.0.1`. A judgement on the ADDRESS cannot catch them — as an
/// address `192.168.122.1` is flawless. Whether an address leaves the host
/// is a property of the INTERFACE, and that stands in the
/// enumeration (`NetworkInterface.name`).
///
/// MEASURED ON THE WIRE, 07.09.2026, Android emulator via tcpdump:
///
///     Out IP 10.0.2.16.56688 > 192.168.122.1.25577: Flags [S], length 0
///     Out IP 10.0.2.16.52204 > 192.168.122.1.14984: Flags [S], length 0
///     Out IP 10.0.2.16.51064 > 192.168.122.1.46950: Flags [S], length 0
///     Out IP 10.0.2.16.40952 > 192.168.122.1.47367: Flags [S], length 0
///
/// `192.168.122.1` is the libvirt bridge of the HOST. A node had announced it
/// as its own address; every reader of the record dialled it
/// and ran into the void. None of these SYNs was answered.
library;

/// Interfaces whose addresses do NOT LEAVE the HOST.
///
/// CONSERVATIVE ON PURPOSE: a bridge with an unlisted name
/// still slips through. The filter thus cannot worsen reachability
/// — it only takes away what demonstrably does not carry.
///
/// The comparison is a PREFIX, not a substring: otherwise an
/// interface that happens to carry `tap` or `br-` in the middle would drop out too
/// (`wlan-tap-frei`, `enbr-0`). Compared in lower case, because
/// Windows delivers interface names in mixed case.
bool isHostInternalInterface(String name) {
  const prefixes = <String>[
    'virbr', // libvirt
    'docker', // Docker
    'br-', // Docker bridges per network
    'veth', // Container-Gegenstueck
    'vboxnet', // VirtualBox Host-only
    'vmnet', // VMware Host-only
    'lxcbr', // LXC
    'tap', // TAP devices
  ];
  final k = name.toLowerCase();
  return prefixes.any(k.startsWith);
}

/// Does this interface count for the question "where am I reachable, and
/// where is my gateway"?
///
/// ── WHY THIS SECOND PREDICATE EXISTS (S376, P2-4) ──────────────
///
/// Before 08.09.2026 the answer stood written out at six places,
/// and at five of them it read only `name != 'lo'`:
///
///   `link_io/nat_pmp.dart`      `detectGatewayIp` (heuristic)
///   `link_io/nat_pmp.dart`      `detectOwnPrivateIpv4`
///   `link_io/upnp_igd.dart`     `gatewayCandidates`, source 1
///   `tagline/lan_segment.dart`  `currentLanSegments` (no filter at all)
///   `service_daemon.dart`       ContactSeed output (no filter at all)
///   `ui/components/share_cleona_dialog.dart`  `_getLanIp` (no filter at all)
///
/// The consequence was measurably inconsistent: `dialableLocalAddresses` no longer announced
/// `virbr0` since S374, while the port mapping kept reporting the same
/// bridge as its own address to the gateway (PCP
/// `clientIp`, UPnP `NewInternalClient`) and the gateway heuristic output the
/// bridge itself as the gateway. A mapping obtained this way points
/// to a device that does not exist outside the host — and
/// `portMappingConfirmed` is set nonetheless.
///
/// One predicate, six callers. `lo` belongs in as well, because the five
/// places excluded it each for themselves anyway; whoever answers the loopback question
/// via `InternetAddress.isLoopback` (as
/// `local_addresses.dart` does) may do both — the name is the
/// cheaper half and excludes nothing that that check
/// would let through.
bool interfaceLeadsAfterOutside(String name) {
  if (name == 'lo' || name == 'lo0') return false;
  return !isHostInternalInterface(name);
}
