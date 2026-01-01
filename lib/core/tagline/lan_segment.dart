// The LAN leg: which segment is this, and has the user consented FOR THIS
// segment to suspend the cover?
//
// ══════════════════════════════════════════════════════════════════════════
// THE ONE RULE THAT SHAPES THIS FILE
// ══════════════════════════════════════════════════════════════════════════
//
// „Speed may fall back to Secure, Secure NEVER silently to Speed"
// (owner, S355; §12). A cover that switches itself off as soon as the
// detection says „pure LAN" would be exactly such a silent mode change —
// and a particularly insidious one, because „pure LAN" cannot be told
// apart from inside from a hotel's guest WLAN.
//
// Hence the split: **DETECTION automatic, SWITCHING OFF only with
// a one-time, visible consent per segment.** This file carries
// both halves and keeps them apart: [LanSegment] and
// [addressInSegment] detect, [SegmentConsentStore] consents. No
// path in this file grants a consent by itself — the only
// setter is [SegmentConsentStore.grant], and its only caller is
// a user tap (the same construction as `CoverSaver.request`, §24.4.2
// condition 3).
//
// ══════════════════════════════════════════════════════════════════════════
// HOW A SEGMENT IS NAMED — AND WHY NOT VIA THE GATEWAY MAC
// ══════════════════════════════════════════════════════════════════════════
//
// The identifier must be three things at once: STABLE (the same network must
// be recognised tomorrow), PORTABLE (Linux, Windows, macOS, Android,
// iOS — the same code base) and CHEAP (no packet, no permission request).
//
// Rejected: **the MAC address of the default gateway.** It would be the
// best identifier — practically unique, does not change — and it cannot be
// obtained portably. It is in the system's ARP table; Dart
// has no interface for it, Android no longer supplies it since API 30 for
// foreign devices without location permission, and iOS not at all.
// A path that runs on two of five platforms is no path for a
// security decision.
//
// Rejected: **the SSID.** Only WLAN, permission-bound on Android,
// and trivially forgeable — an attacker names his hotspot like the
// home network and inherits the consent.
//
// Chosen: **interface name ‖ /24 prefix of the own address**, i.e.
// e.g. `wlan0|192.168.10.0/24`. Both can be had everywhere from
// `NetworkInterface.list`, without permission and without a packet.
//
// ── THE /24 ASSUMPTION, STATED OPENLY ────────────────────────────────────
//
// Dart does not expose the NETMASK. `NetworkInterface` carries name and
// addresses, nothing else — re-measured, there is no `prefixLength`.
// Therefore /24 is assumed, the same approximation that
// `IpAddressClass.sameSubnet24` already carries in the tree.
//
// The error this produces goes in the SAFE direction: a house with
// a /16 falls apart for this file into many /24, and a consent
// for one of them does NOT apply to the others. That costs convenience
// (the user may consent several times) and gives away nothing
// in protection. The other way round — an assumed /16 that in truth is a /24
// — would be the expensive error: the consent would then cover neighbours
// the user has never seen.
//
// Concretely this affects the multicast call: `kLanEntryMulticastHops` = 4
// lets the call run across segment boundaries via IGMP (measured 25.08.);
// the neighbours found this way carry a different private address and are
// thus OUTSIDE the consented segment. They therefore keep the cover
// on. That is intended, not overlooked.
//
// ══════════════════════════════════════════════════════════════════════════
// THE WITNESS — AND WHY THE IDENTIFIER ALONE IS NOT ENOUGH
// ══════════════════════════════════════════════════════════════════════════
//
// `wlan0|192.168.1.0/24` is at home the same string as in a
// hotel's guest WLAN. Without more, the consent granted there would —
// no, worse: the consent granted AT HOME would keep acting in the
// hotel, and exactly that case is the reason this
// consent exists at all. An identifier that collides is none.
//
// The consent therefore carries WITNESSES: the positions (`L_node`) of the
// nodes that sat in this segment at the moment of consent — the
// own other devices, the family's computers. It applies only as long as
// at least one of these witnesses is back.
//
// Why that holds: a position is the hash over the static
// keys of a node (§9.1) and is IMPLICITLY authenticated in the handshake
// — whoever forges it cannot open anything we send
// (`lan_entry.dart`, „SELF-CERTIFYING"). An attacker in the hotel can
// rebuild the address, the interface name anyway, but not the
// key of a device that stands in my home.
//
// Price, stated openly: whoever consents at home while only ONE other
// device was running, and later sells that device, must consent anew.
// That is the right direction — the loss of a witness leads to MORE
// cover, never to less.
library;

import 'dart:io';

import '../util/host_interfaces.dart';
import 'package:cleona/core/util/local_addresses.dart';

/// A network segment as this node sees it.
final class LanSegment {
  /// The name of the interface over which this segment hangs
  /// (`wlan0`, `eth0`, `Ethernet`, …).
  final String interfaceName;

  /// The own address in this segment.
  final String ownAddress;

  /// The first three octets, i.e. the assumed /24 (see module header).
  final String prefix24;

  const LanSegment({
    required this.interfaceName,
    required this.ownAddress,
    required this.prefix24,
  });

  /// The stable identifier. It goes as-is into the consent and into the
  /// UI — the user should recognise what he consents to.
  String get id => '$interfaceName|$prefix24.0/24';

  @override
  String toString() => id;
}

/// Splits an IPv4 into its /24 prefix (`192.168.10.7` -> `192.168.10`),
/// or `null` if that is not a usable IPv4.
String? prefix24Of(String ip) {
  if (ip.contains(':')) return null;
  final p = ip.split('.');
  if (p.length != 4) return null;
  for (final chunk in p) {
    final n = int.tryParse(chunk);
    if (n == null || n < 0 || n > 255) return null;
  }
  return '${p[0]}.${p[1]}.${p[2]}';
}

/// Is [ip] in [segment]?
///
/// ONLY IPv4, and that is not a gap but the scope: the LAN call
/// is IPv4-only today (`lan_entry_wiring` binds IPv4 sockets,
/// `vorratUnicastTargets` filters accordingly). An IPv6 address is therefore
/// NOT a segment member from here, and the cover then stays on —
/// the cautious direction.
bool addressInSegment(String ip, LanSegment segment) {
  final p = prefix24Of(ip);
  if (p == null) return false;
  return p == segment.prefix24;
}

/// The segments in which this node currently sits.
///
/// ONLY PRIVATE IPv4. A publicly routable address is by definition
/// no „own network" — there the node stands directly in the internet, and
/// a consent „in this segment the cover may be off" would there be
/// a consent to switch off the cover towards the internet.
/// `istSegmentQuelle` draws the same boundary for the call.
///
/// The undialable ranges (CGNAT, DS-Lite CLAT, link-local) also
/// drop out: under them the node sits in a network whose
/// extent it does not know. A CGNAT segment can be a whole city.
///
/// DOES NOT THROW — the enumeration can fail during an interface change
/// (regularly on iOS). An empty result means „no
/// own network detected", and that keeps the cover on.
///
/// NO VIRTUAL HOST BRIDGES (S376, P2-4). Until then this
/// loop, as the only one of the six, had no interface filter at all. On
/// a development machine with libvirt this produced a segment
/// `virbr0 / 192.168.122.0/24` — an „own network" whose only
/// neighbour is the host itself. For exactly this segment the
/// UI could have offered a consent under §5.1 („consented LAN suspension"),
/// i.e. switching off the cover for a network that is
/// not even known to the user as „my LAN". The cautious
/// direction is not to carry it as a segment.
Future<List<LanSegment>> currentLanSegments() async {
  final out = <LanSegment>[];
  try {
    for (final iface
        in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      if (!interfaceLeadsAfterOutside(iface.name)) continue;
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (addr.isLoopback || ip == '0.0.0.0') continue;
        if (isUndialableIpv4(ip)) continue;
        if (!isPrivateIpv4(ip)) continue;
        final p = prefix24Of(ip);
        if (p == null) continue;
        final s = LanSegment(
            interfaceName: iface.name, ownAddress: ip, prefix24: p);
        if (out.any((e) => e.id == s.id)) continue;
        out.add(s);
      }
    }
  } catch (_) {
    // Interface change — silent (E-83). The next occasion asks again.
  }
  return out;
}

/// A granted consent.
final class SegmentConsent {
  /// For which segment ([LanSegment.id]).
  final String segmentId;

  /// When it was granted — it appears like this in the UI so that
  /// „I clicked that at some point" becomes traceable.
  final DateTime grantedAt;

  /// The positions of the neighbours present at the grant, in
  /// hex. See module header: without one of them the consent does
  /// not apply.
  final List<String> witnesses;

  const SegmentConsent({
    required this.segmentId,
    required this.grantedAt,
    required this.witnesses,
  });

  Map<String, Object?> toJson() => {
        'segment': segmentId,
        'granted': grantedAt.toUtc().millisecondsSinceEpoch,
        'witnesses': witnesses,
      };

  /// `null` if the record is unusable. **A broken
  /// consent is no consent** — it is not repaired and
  /// not guessed, it drops away, and the user is asked again.
  static SegmentConsent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['segment'];
    final ms = raw['granted'];
    final w = raw['witnesses'];
    if (id is! String || id.isEmpty) return null;
    if (ms is! int) return null;
    if (w is! List) return null;
    final witnessList = <String>[];
    for (final e in w) {
      if (e is String && e.isNotEmpty) witnessList.add(e);
    }
    // NO WITNESSES, NO CONSENT. A record with an empty witness list
    // would be one that hangs on the colliding identifier alone — exactly
    // the case the module header excludes.
    if (witnessList.isEmpty) return null;
    return SegmentConsent(
      segmentId: id,
      grantedAt:
          DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal(),
      witnesses: witnessList,
    );
  }
}

/// The granted consents, one per segment.
///
/// NO EXPIRY OVER TIME, and that is intentional: a consent that
/// silently expires after N days would be a state change without action —
/// just in the other direction. It loses its effect
/// exclusively because the situation no longer fits (no witness present,
/// a foreign partner joined), and it disappears exclusively
/// through [revoke]. Both are traceable; a date in the background
/// would not be.
final class SegmentConsentStore {
  final Map<String, SegmentConsent> _byId = <String, SegmentConsent>{};

  /// Called when something has changed — the service then
  /// writes out. Handed in so that this file knows no storage.
  void Function()? onChanged;

  /// All consents, for the UI.
  List<SegmentConsent> get all => List.unmodifiable(_byId.values);

  SegmentConsent? consentFor(String segmentId) => _byId[segmentId];

  /// Grants the consent. **The only setter.**
  ///
  /// Returns `false` and changes nothing if no witnesses are named
  /// — then there would be nothing for the consent to bind to,
  /// and it would be valid in every segment of the same name in the
  /// world. The caller displays that instead of swallowing it.
  bool grant(String segmentId, List<String> witnesses, {DateTime? now}) {
    final witnessList = witnesses.where((w) => w.isNotEmpty).toSet().toList()
      ..sort();
    if (witnessList.isEmpty) return false;
    _byId[segmentId] = SegmentConsent(
      segmentId: segmentId,
      grantedAt: now ?? DateTime.now(),
      witnesses: witnessList,
    );
    onChanged?.call();
    return true;
  }

  /// Withdraws it. ALWAYS works — a revocation leads to MORE cover,
  /// never to less, and therefore needs no condition (the same
  /// reasoning as for `CoverSaver.request(false)`).
  bool revoke(String segmentId) {
    final route = _byId.remove(segmentId) != null;
    if (route) onChanged?.call();
    return route;
  }

  /// Does the consent apply to [segment] NOW?
  ///
  /// Two conditions, both necessary:
  ///
  ///  1. There is a consent for exactly this identifier.
  ///  2. At least one witness from the consent is among
  ///     [presentPositions] — the positions of the currently present
  ///     neighbours. See module header: without that, everything hangs on a
  ///     string that can be the same in the hotel.
  bool appliesTo(LanSegment segment, Iterable<String> presentPositions) {
    final c = _byId[segment.id];
    if (c == null) return false;
    for (final p in presentPositions) {
      if (c.witnesses.contains(p)) return true;
    }
    return false;
  }

  List<Map<String, Object?>> toJson() =>
      _byId.values.map((c) => c.toJson()).toList();

  void loadJson(Object? raw) {
    _byId.clear();
    if (raw is! List) return;
    for (final e in raw) {
      final c = SegmentConsent.fromJson(e);
      if (c != null) _byId[c.segmentId] = c;
    }
  }

  void clearForTest() {
    _byId.clear();
  }
}
