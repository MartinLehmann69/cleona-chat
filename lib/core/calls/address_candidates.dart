// The address candidates of the punch window (§17.3).
//
// ══ WHAT §17.3 REQUIRES, VERBATIM ══════════════════════════════════════
//
//   "**Candidates in signaling:** INVITE and ANSWER carry the address
//    candidates of both sides (local addresses + observed addresses, both
//    families kept separate — a narrow ICE without TURN)."
//
//   "**Symmetric NAT:** port prediction is a candidate generator — it
//    guesses the NAT's next port assignment within a window of ±10 ports
//    around the most recently observed port."
//
//   "**Address families:** v4-only ↔ v6-only has no common pair — clear
//    message ,no common connection type'."
//
// This file builds the own list, encodes it for INVITE/ANSWER, reads
// that of the other side and generates the prediction. It sends nothing —
// that is done by `punch_window.dart`.
//
// ══ TWO SOURCES, AND WHY BOTH ══════════════════════════════════════
//
//  1. **Local addresses** — `tagline/local_addresses.dart`. That is the
//     set under which a partner in the SAME network arrives; in the LAN
//     the call carries without any NAT.
//  2. **Observed addresses** — the node's `ObservedAddressBook`, the
//     §17.3 mirror from flight 2 of the handshake. That is the outer
//     address behind the NAT, and it is the only one that reaches beyond the
//     own network.
//
// MEASURED on 01.09.2026 in this tree (development machine, two
// `LinkHost` over loopback, one real handshake):
//
//     dialableLocalAddresses(): [192.168.10.92, 192.0.2.250, 192.168.122.1]
//     A.observed: ObservedAddressBook(1 Partner, v4=[127.0.0.1:56403], v6=[])
//     B.observed: ObservedAddressBook(0 Partner, ...)   (B only answered)
//
// Three local plus one observed address — four candidates. And the
// second part of the measurement is the more important one: **whoever only answers learns
// nothing about themselves.** The mirror lies in flight 2, which the answering side
// WRITES; only whoever OPENED the handshake gets an observation about
// themselves. A node without its own outgoing handshakes
// therefore has no observed address and names only local ones — that is
// not an error, but the reason why §17.3 hangs the mirror on the
// synchronisation that runs anyway.
//
// ══ WHY A TYPE OF ITS OWN AND NOT `ObservedAddress` ══════════════════
//
// `ObservedAddress` (`link/handshake.dart`) carries the same three items
// and has a proven, strict read function. It is nevertheless
// not taken over, for two reasons, both of which lie on the wire:
//
//   * **Its encoding is a FIXED 19 B** — the field in flight 2 has a fixed
//     size, which is right there. On signaling it is
//     waste: an IPv4 needs 7 B, and the INVITE lies close to
//     a cell boundary (see [encodeCandidates]).
//   * **It is a STATEMENT BY A PARTNER.** A local address is
//     not an observation. Putting both into one type would mean losing the
//     question of origin in the type — and exactly that decides whether
//     port prediction is applicable.
//
// [CallCandidate.fromObserved] is the bridge; it is the only place
// where the two forms touch.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/link/handshake.dart' show ObservedAddress;
import 'package:cleona/core/link_io/link_host.dart' show ObservedAddressBook;
import 'package:cleona/core/sync/entry_record.dart' show EntryAddress;
import 'package:cleona/core/util/local_addresses.dart';

/// Family byte on the wire. 4 and 6, not 0 and 1 — the same choice as
/// in `ObservedAddress.encode`, and for the same reason: **0 means "nothing
/// said"**, and a reader that accepts 0 as a family builds a candidate
/// `0.0.0.0:0` from zero padding.
const int kCandidateFamilyV4 = 4;
const int kCandidateFamilyV6 = 6;

/// What a candidate costs on the wire: `fam(1) ‖ addr(4|16) ‖ port(2)`.
const int kCandidateWireV4 = 7;
const int kCandidateWireV6 = 19;

/// How many own candidates are named at most.
///
/// ── OWN CHOICE, §17.3 NAMES NO NUMBER (step C finding S361) ────────
///
/// §17.3 says "to **all** of the other side's candidates" and leaves open
/// how many that may be. Without a cap the number grows with the number
/// of network interfaces and sync partners — and neither is controlled
/// by the other side, so the number of packets it can coax out of us
/// is unbounded. A cap is thus not frugality but
/// the condition for the price being computable at all.
///
/// **The number 8, derived.** Measured on the development machine:
/// 3 local + 1 observed = 4. The most expensive realistic node is a
/// dual-stack mobile device with two active paths: Wi-Fi v4, Wi-Fi v6,
/// mobile v4, mobile v6 = 4 local, plus one observed per family
/// = 6. 8 leaves room for exactly one more interface and lies below the
/// number at which the window becomes more expensive than the conversation it sets up
/// (calculation in `punch_window.dart`).
const int kMaxCallCandidates = 8;

/// An address candidate: an address, a port, a family.
final class CallCandidate {
  /// IPv6 if true; otherwise IPv4. No `null` case — §17.3 keeps the
  /// families separate, and a candidate without a family could not be
  /// assigned to either side of that separation.
  final bool isIpv6;

  /// 4 B for IPv4, 16 B for IPv6, in network order.
  final Uint8List rawAddress;

  final int port;

  /// Does this candidate come from the §17.3 mirror (instead of from the own
  /// interface list)?
  ///
  /// **Is NOT transmitted and need not be.** The other side does not need
  /// the origin: it sends to all candidates alike. It is needed
  /// on the OWN side — port prediction (§17.3) only applies
  /// to observed addresses, because only they have passed through a NAT.
  /// On the receiving side the attribute is therefore always `false`, and the
  /// recognition path there is a different one (see [predictPorts]).
  final bool fromMirror;

  CallCandidate._(this.isIpv6, this.rawAddress, this.port, this.fromMirror);

  /// Builds a candidate from raw address bytes.
  ///
  /// Returns `null` instead of throwing — unlike
  /// `ObservedAddress.fromRaw`, and the difference is intended: there
  /// the caller is the receive path with bytes from the operating system, here
  /// the caller may be foreign signaling. A throw on foreign
  /// bytes would be a crash surface.
  static CallCandidate? of(Uint8List rawAddress, int port,
      {bool fromMirror = false}) {
    if (port < 1 || port > 65535) return null;
    if (rawAddress.length == 4) {
      return CallCandidate._(
          false, Uint8List.fromList(rawAddress), port, fromMirror);
    }
    if (rawAddress.length != 16) return null;
    // IPv4-mapped is unwrapped — the same rule as in
    // `ObservedAddress.fromRaw`: passing on `::ffff:a.b.c.d` as an IPv6 candidate
    // produces an address at which nobody listens
    // (`local_addresses.dart`, `isTunnelIpv6`, WIN-2).
    if (_isV4Mapped(rawAddress)) {
      return CallCandidate._(
          false, Uint8List.fromList(rawAddress.sublist(12, 16)), port,
          fromMirror);
    }
    return CallCandidate._(
        true, Uint8List.fromList(rawAddress), port, fromMirror);
  }

  /// The bridge to the §17.3 mirror — the only place where the two
  /// address forms touch.
  static CallCandidate? fromObserved(ObservedAddress o) =>
      CallCandidate.of(o.rawAddress, o.port, fromMirror: true);

  static bool _isV4Mapped(Uint8List a) {
    for (var i = 0; i < 10; i++) {
      if (a[i] != 0) return false;
    }
    return a[10] == 0xff && a[11] == 0xff;
  }

  InternetAddress get address =>
      InternetAddress.fromRawAddress(rawAddress,
          type: isIpv6 ? InternetAddressType.IPv6 : InternetAddressType.IPv4);

  int get wireSize => isIpv6 ? kCandidateWireV6 : kCandidateWireV4;

  /// Equality over family, address and port — NOT over [fromMirror].
  ///
  /// Otherwise the same address would be in the list twice if it happens
  /// to be local and observed at the same time (the normal case without NAT), and the
  /// punch window would pay for it twice.
  @override
  bool operator ==(Object other) =>
      other is CallCandidate &&
      other.isIpv6 == isIpv6 &&
      other.port == port &&
      _sameBytes(other.rawAddress, rawAddress);

  @override
  int get hashCode => Object.hash(isIpv6, port, Object.hashAll(rawAddress));

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => '${address.address}:$port${fromMirror ? "*" : ""}';
}

/// The own candidates for INVITE/ANSWER (§17.3).
///
/// Order: **local first, observed after**, within both
/// IPv4 before IPv6. The order is a statement, not taste:
///
///   * **Local before observed**, because a hit on a local address
///     is the better path (no NAT in the path, no NAT timeout during
///     the conversation) and the window takes the FIRST carrying path
///     (§17.3: "the first address pair on which valid AEAD responses arrive
///     carries the session").
///   * **The observed ones in address book order, the youngest
///     last** — [predictPorts] relies on this ("around the **most
///     recently observed** port", §17.3).
///
/// The cap [kMaxCallCandidates] cuts off at the end, so it hits
/// the observed ones first. That is the right direction: more than two
/// observed addresses per family mean symmetric NAT, and then
/// none of them carries anyway — the prediction has to solve that, not
/// the enumeration.
///
/// ── THE THIRD SOURCE: [mapped] (§25.9, S376/A-1) ────────────────────
///
/// The CONFIRMED port mapping of the node
/// (`V41Node.advertiseMapped`). It comes **after the local ones and BEFORE the
/// observed ones**, and both halves of the order are a statement:
///
///   * **After the local ones**, for the same reason as the mirror: a
///     local address has no NAT in the path and no NAT timeout
///     during the conversation.
///   * **Before the observed ones**, because a confirmed mapping is STRONGER
///     than an observation: it is the router's PROMISE to
///     forward incoming packets to exactly this port, while
///     the mirror is the after-the-fact finding that an OUTgoing
///     datagram once carried a certain outer address.
///     `V41Node.ownEntry` already applies exactly this ranking (the
///     mapped address is in second place there, directly after the
///     local one), and the cap cuts off at the back — standing before the observed ones
///     is therefore at the same time the survival spot.
///
/// **It is NOT [CallCandidate.fromMirror].** The attribute controls whether
/// port prediction is applicable, and that only applies to addresses that
/// have passed through a NAT OUTGOING. A mapped one has not.
///
/// **WHAT IT COSTS, COMPUTED (working rule 5).** One candidate more:
/// [kCandidateWireV4] = 7 B in the INVITE/ANSWER, and in the punch window one
/// packet per round (128 B, §17.1). The **worst case stays
/// unchanged**, because [kMaxCallCandidates] = 8 stays unchanged: an
/// INVITE still carries at most 8 x 7 = 56 B of candidates, a round
/// still at most `kMaxPunchPacketsPerRound` packets. What changes
/// is the USUAL CASE: three local + one mapped + one observed =
/// 5 instead of 4 candidates, i.e. +7 B once and in phase 1 of the window
/// +1 packet per round = 15 x 128 B = **1.9 kB per call attempt**, and even
/// that only if no local candidate carries immediately (in the LAN it carries in
/// round 0). Against that stands a call that would otherwise fall to the relay path §17.6
/// — there the ENTIRE media stream runs via a third party,
/// 6.4 kB/s per direction for the duration of the conversation.
///
/// **A SIDE EFFECT, named instead of skipped.** If the mapped
/// address carries the same IP as an observed one, but a different port, then
/// the other side sees two ports for one address and [predictPorts]
/// fires — the sign by which it recognises a symmetric NAT.
/// That is no misinterpretation here but the finding itself: a fixed
/// mapping next to a deviating outgoing assignment IS a
/// destination-dependent port allocation. And it is without consequence where it contributes
/// nothing: the prediction only runs from round `kPlainRounds` = 15, i.e.
/// only if the mapped address has not carried by then.
Future<List<CallCandidate>> ownCallCandidates({
  required int ownPort,
  required ObservedAddressBook observed,
  EntryAddress? mapped,
  Future<List<String>> Function()? localAddresses,
}) async {
  final out = <CallCandidate>[];
  void add(CallCandidate? c) {
    if (c == null) return;
    if (out.contains(c)) return;
    out.add(c);
  }

  if (ownPort >= 1 && ownPort <= 65535) {
    final local = await (localAddresses ?? dialableLocalAddresses)();
    for (final ip in local) {
      final addr = InternetAddress.tryParse(ip);
      if (addr == null) continue;
      add(CallCandidate.of(
          Uint8List.fromList(addr.rawAddress), ownPort));
    }
  }
  final wasMapped = mapped;
  if (wasMapped != null) {
    // Port 0 is not a mapping but an unfilled promise; the
    // guard in [CallCandidate.of] catches it anyway, it stands here only
    // because `InternetAddress.tryParse` returns `null` on a host name and
    // a mapping always carries an ADDRESS (§25.9).
    final addr = InternetAddress.tryParse(wasMapped.host);
    if (addr != null) {
      add(CallCandidate.of(
          Uint8List.fromList(addr.rawAddress), wasMapped.port));
    }
  }
  for (final o in observed.allCandidates) {
    add(CallCandidate.fromObserved(o));
  }

  if (out.length > kMaxCallCandidates) {
    return out.sublist(0, kMaxCallCandidates);
  }
  return out;
}

/// Packs the candidates for `CallInvite.caller_candidates` /
/// `CallAnswer.callee_candidates`.
///
/// ── WHY PACKED AND NOT `repeated bytes` ──────────────────────────
///
/// A `repeated bytes` costs 2 B of framing per entry. Eight candidates are
/// 16 B in framing alone — and the INVITE already carries the 1088 B
/// ML-KEM ciphertext. Delivery splits a sealed payload into
/// pieces of `kMaxPieceBytes - kSplitHeaderBytes` = 1026 B
/// (`tagline/frame_split.dart`), and one more cell on the signal line
/// costs `m x R_signal` = 15 placements = **120 s of egress** (§17.2) —
/// the full TTL of an INVITE. A byte at this place is therefore not
/// irrelevant.
///
/// Price of the packed form, computed: 8 IPv4 candidates = 56 B, plus 2 B
/// protobuf framing for the one field = **58 B**. As `repeated bytes` with
/// the 19 B encoding of `ObservedAddress` it would be 8 x 21 = **168 B**.
Uint8List encodeCandidates(List<CallCandidate> candidates) {
  var n = 0;
  for (final c in candidates) {
    n += c.wireSize;
  }
  final out = Uint8List(n);
  var i = 0;
  for (final c in candidates) {
    out[i++] = c.isIpv6 ? kCandidateFamilyV6 : kCandidateFamilyV4;
    out.setRange(i, i + c.rawAddress.length, c.rawAddress);
    i += c.rawAddress.length;
    out[i++] = (c.port >> 8) & 0xff;
    out[i++] = c.port & 0xff;
  }
  return out;
}

/// Reads what the other side named.
///
/// **Stops at the first unintelligible item and returns what was there
/// up to that point.** No skipping, no guessing on: the form is
/// self-delimiting only as long as every family byte is right — whoever reads on
/// after an unknown byte assembles candidates from foreign remainder
/// and then sends packets to addresses nobody named.
///
/// The cap [kMaxCallCandidates] applies here too, and here it is the
/// actual gate: the number is in a FOREIGN message.
List<CallCandidate> decodeCandidates(List<int> packed) {
  final b = packed is Uint8List ? packed : Uint8List.fromList(packed);
  final out = <CallCandidate>[];
  var i = 0;
  while (i < b.length && out.length < kMaxCallCandidates) {
    final fam = b[i];
    final addrLen = fam == kCandidateFamilyV4
        ? 4
        : fam == kCandidateFamilyV6
            ? 16
            : -1;
    if (addrLen < 0) break;
    if (i + 1 + addrLen + 2 > b.length) break;
    final addr = b.sublist(i + 1, i + 1 + addrLen);
    final port = (b[i + 1 + addrLen] << 8) | b[i + 2 + addrLen];
    final c = CallCandidate.of(addr, port);
    if (c == null) break;
    if (!out.contains(c)) out.add(c);
    i += 1 + addrLen + 2;
  }
  return out;
}

/// Do both sides have at least one common address family?
///
/// §17.3: "v4-only ↔ v6-only has no common pair — clear message ,no common
/// connection type', delivery-layer messaging unaffected". The caller
/// thus gets the MESSAGE instead of a window that sends against
/// nothing for 30 s.
bool haveCommonFamily(List<CallCandidate> a, List<CallCandidate> b) {
  var a4 = false, a6 = false, b4 = false, b6 = false;
  for (final c in a) {
    if (c.isIpv6) {
      a6 = true;
    } else {
      a4 = true;
    }
  }
  for (final c in b) {
    if (c.isIpv6) {
      b6 = true;
    } else {
      b4 = true;
    }
  }
  return (a4 && b4) || (a6 && b6);
}

/// How far port prediction reaches around the most recently observed port
/// (§17.3: "within a window of ±10 ports around the most recently observed
/// port"). From the spec, not chosen.
const int kPortPredictionSpan = 10;

/// Port prediction from §17.3 — a CANDIDATE GENERATOR, not a replacement.
///
/// ── WHEN IT FIRES AT ALL, and why that is derivable ──────────
///
/// It only fires for an address for which the other side named **more than one
/// port**. That is not an economy measure but the definition
/// of the case:
///
///   * A **cone NAT** assigns the same outer port mapping for all destinations.
///     All sync partners of the other side see the same port,
///     its address book agrees (`ObservedAddressBook.agreed`), and it
///     names ONE port. This port carries for us too — there is nothing
///     to predict.
///   * A **symmetric NAT** assigns its own mapping per destination.
///     Different sync partners see different ports, the address book
///     contradicts itself (`ObservedAddressBook.disagrees` — exactly the
///     finding that §17.3 lists as "the textbook finding of a symmetric NAT"),
///     and the other side names SEVERAL. None of them carries for
///     us, because our datagram is a new destination. Only here does the
///     prediction have an object.
///
/// The origin (`fromMirror`) is not available on the receiving side
/// (it is not on the wire — see [CallCandidate.fromMirror]), and
/// it is not needed either: **more than one port for the same address
/// can only come from the mirror.** The local half names every
/// address with the same one data port (`ownCallCandidates`).
///
/// ── AROUND WHICH PORT ──────────────────────────────────────────────────
///
/// Around the **last** of those named — `ownCallCandidates` outputs the
/// observed ones in address book order, the youngest last, and
/// `encodeCandidates` keeps them. That is the literal reading of "most
/// recently observed". Not the highest port: that would be a
/// proxy that only coincides with the statement as long as the NAT
/// allocates in ascending order.
///
/// ── PRICE ────────────────────────────────────────────────────────────
///
/// 2 x 10 = 20 additional candidates per affected address. What that
/// costs and how it is capped is in `punch_window.dart` — here
/// it is only generated.
List<CallCandidate> predictPorts(List<CallCandidate> peer) {
  // Group by (family, address), keeping the order of naming.
  final groups = <String, List<CallCandidate>>{};
  for (final c in peer) {
    groups.putIfAbsent(c.address.address, () => <CallCandidate>[]).add(c);
  }
  final out = <CallCandidate>[];
  for (final g in groups.values) {
    final ports = <int>{for (final c in g) c.port};
    if (ports.length < 2) continue; // cone NAT — nothing to predict
    final basis = g.last;
    for (var d = -kPortPredictionSpan; d <= kPortPredictionSpan; d++) {
      if (d == 0) continue;
      final p = basis.port + d;
      if (p < 1 || p > 65535) continue;
      final c = CallCandidate.of(basis.rawAddress, p);
      if (c == null) continue;
      if (peer.contains(c) || out.contains(c)) continue;
      out.add(c);
    }
  }
  return out;
}
