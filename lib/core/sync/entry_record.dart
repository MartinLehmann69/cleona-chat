import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../crypto/sodium_ffi.dart';
import '../link/node_keys.dart';
import '../link_io/link_host.dart';
import '../util/ip_address_class.dart';
import 'package:cleona/core/util/local_addresses.dart';

/// How many addresses an entry record carries.
///
/// Four, and that is a format limit, not a preference: the record is
/// signed and travels in one cell. Whoever has more addresses must CHOOSE
/// — see `startV41Node`, where exactly that was missing on 28.08. and a phone with
/// eight address families made the entry handler run into an exception.
const int kMaxEntryAddresses = 4;

/// An address under which a node is reachable.
final class EntryAddress {
  final String host;
  final int port;
  const EntryAddress(this.host, this.port);

  bool get isV6 => host.contains(':');

  @override
  bool operator ==(Object other) =>
      other is EntryAddress && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => isV6 ? '[$host]:$port' : '$host:$port';
}

/// How many addresses of ONE record a dial round tries
/// at most.
///
/// ── TWO, AND THE NUMBER IS DERIVED, NOT PICKED ──────────────────────
///
/// [kMaxEntryAddresses] is four, but the four is a FORMAT limit
/// (the record is signed and travels in one cell) and no measure
/// of how many paths really exist. The reason why a
/// record carries several addresses at all is at
/// [EntryRecord.addresses] and names exactly two quantities: §17.3
/// (dual-stack mediator) and §25 (family share). Both speak of
/// FAMILIES, and there are two of those. [dialAddressOrder] therefore tries
/// at most one address PER FAMILY and round; the two falls out of that,
/// it is not set.
///
/// ── WHAT THAT COSTS IN PACKETS (work rule 5), MEASURED ──────────────
///
/// A failed attempt runs the cascade from §4.8. Measured on 07.09.2026 on a
/// running node against a dead loopback port:
///
///     `Fehlversuch: ok=false, 1538 ms, Draht-Bytes 1200`
///
/// So EXACTLY ONE UDP datagram (flight 1, 1200 B) on the step
/// `udpOwnPort` plus one `Socket.startConnect` on `tcpOwnPort`;
/// `tcp443` and `icmpKnock` are immediate refusals without I/O
/// (`link_host.dart:346-354`) and cost nothing. On loopback
/// TCP answers with RST, hence 1.5 s instead of 3 s — in the field the
/// TCP step costs its own step timeout.
///
/// `V41Node.dialFromEntries` chooses at most FOUR records per round
/// and runs every `V41Node.dialEverySlots` slots (6 x 8 s = 48 s), and
/// only as long as partners are missing. The upper bound thus rises from 4 to
/// 4 x 2 = 8 attempts per round, about 16-24 instead of 8-12 packets per 48 s —
/// and the eight only if ALL four candidates are dual-stack AND every
/// first attempt fails. A record with only one family still costs
/// exactly one attempt.
const int kDialAddressesPerRecord = 2;

/// The addresses of a record in the order in which they are
/// to be dialled — at most [max], at most one per family.
///
/// ── WHY THIS FUNCTION MUST EXIST (S373) ─────────────────────────────
///
/// [EntryRecord.host]/[EntryRecord.port] are `addresses.first`, and until
/// S373 that was the only address ever dialled — at both
/// dial points, `V41Node.dialFromEntries` and `lan_entry_wiring`. A
/// dead first address thus burnt the WHOLE record: the
/// failed-attempt memory hangs on the POSITION
/// ([EntryCache.noteUnreachable]), not on the address, so a
/// failed first attempt booked against the record as a whole, and after
/// [kDialFailureLimit] rounds it fell out of the supply together with its never tried
/// addresses.
///
/// MEASURED ON 06.09.2026 ON THE PUBLIC BOARD: three global IPv6
/// in two records — reachable addresses that were never dialled
/// because in the same records a private IPv4 stood in front.
/// Reproduced on 07.09. on two running nodes: record with dead
/// IPv4 at position 0 and live IPv6 at position 1 yielded
/// `Partner 0` and a failed attempt; the same record without the dead
/// IPv4 yielded `Partner 1`.
///
/// ── THE ORDER, AND WHAT THE DOCUMENTS REALLY SAY ABOUT IT ───────────
///
/// An "IPv6-first" rule in §4.6 DOES NOT EXIST — re-measured on
/// 07.09.2026 against all three architecture documents:
///
///   * v4_1 §4.6 is "Forward Secrecy: One-Time Prekey Pool" (l. 1127)
///     and has nothing to do with addresses.
///   * v4_0 §4.6 is "Address Families and Network Segments" (l. 2924)
///     and specifies four family rules — but NO ranking between
///     the addresses of ONE record. Rule 2 ("single-stack nodes
///     prefer partners announced as dual-stack") orders RECORDS.
///   * The actual rule is in v3_0 §4.7 (l. 1955): "If yes:
///     try IPv6 first (address priority 2, ahead of all IPv4 paths)" —
///     and it is CONDITIONAL: "does the local node have a global IPv6?
///     does the receiver have a global IPv6?". Only then.
///
/// It is adopted in exactly this conditional form, and the
/// condition here is harder than a preference: [v6Available] comes from
/// `V41Node.usableFamilies` — bound socket AND a usable
/// own source address of this family. **Until S379 only
/// `LinkHost.families` stood here, i.e. the bound socket alone.** On Linux
/// `::` binds even without any global IPv6; the node then dialled
/// IPv6 candidates and got `Network is unreachable` (errno 101,
/// measured three times on 09.09.2026 on `.202`). If the
/// family is missing, `UdpSocketSet.send` throws a `StateError`; the connector
/// catches it and reports a refusal — the attempt costs no
/// packet, but a failed attempt on the record. And under Windows
/// the same case is the crash class from v4_1 §27.3: Dart's IOCP
/// `RawDatagramSocket.send()` tears down the VM when sending to an IPv6 without
/// a route, and BELOW every try/catch. An address
/// of an unbound family is therefore not sorted, but
/// DROPPED.
///
/// ── THE RANK, FIVE LEVELS ───────────────────────────────────────────
///
///   0. IPv4 in the OWN segment ([IpAddressClass.isInLocalSubnet] against
///      [localIps]). Before everything else, and that is no detail: a
///      private address in the own segment IS the LAN entry (§11.1
///      step 2), the only path that carries without a NAT hole. Whoever
///      filters here instead of ordering breaks it.
///   1. Global IPv6 — v3_0 §4.7: "IPv6-direct is trivial — every device
///      has its own global IPv6", no NAT in front.
///   2. Public IPv4.
///   3. ULA IPv6 (`fc`/`fd`) — carries within a site.
///   4. Everything else: private IPv4 outside the own segment,
///      CGNAT, loopback, tunnel IPv6 (Teredo/6to4/documentation prefix, see
///      [isTunnelIpv6]). NOT discarded, only at the back — v3_0 §4.7 explicitly
///      allows "cross-class private-to-private … within RFC 1918"
///      ("two RFC 1918 ranges behind the same gateway, common in
///      home/lab networks"). The cap takes care of them, not a filter.
///
/// ── WHAT IS DROPPED, AND WHY ONLY THAT ──────────────────────────────
///
/// Only what PROVABLY has no path, not what is unlikely:
/// an address of an unbound family (see above), IPv6
/// link-local (`fe80:` without a zone index cannot be dialled) and IPv4
/// `169.254.` (self-configuration without DHCP). `local_addresses.dart`
/// already excludes the same three on the OWN side — it is
/// the same question, only asked the other way round.
///
/// MAPPED ADDRESSES (`::ffff:a.b.c.d`) are normalised for rank and family
/// via [IpAddressClass.normalizeIp], but returned in the
/// ORIGINAL: `V41Node`'s `peers` lookup goes via
/// `EntryCache.lookupEndpoint(host, port)`, and that is keyed on the
/// string of the record. Without the normalisation
/// a mapped IPv4 would run as "global IPv6" at rank 1.
///
/// ── [roundOffset] — WHY THE CAP WOULD OTHERWISE BE A DEAD END ──────────
///
/// A record with two IPv4 (LAN and public) and no IPv6
/// would, with "one per family", ALWAYS get the same first address, in every
/// round — the second would never see a packet, and the cap would have
/// merely moved the finding. [roundOffset] is the number of previous
/// failed attempts on this record ([EntryCache.failuresFor]);
/// within a family the choice thus moves on by one address per round.
/// Over the [kDialFailureLimit] rounds until expiry
/// every address of every family thus gets its chance, without any round
/// getting more expensive.
/// The hosts that this node ITSELF is — and that therefore may never be a
/// dial target (`ownHosts` in [dialAddressOrder]).
///
/// ── WHY THIS IS A FUNCTION AND NOT A HAND-MAINTAINED SET ─────────────
///
/// The set existed already, inline in the caller, and it was wrong: it
/// named `advertiseHost` TWICE (once via `_ownIps`, once as a
/// supposed addition for the hairpin case) and the mapped
/// address NOT AT ALL. The comment next to it claimed the opposite.
/// A set built inline has no place where one can measure it,
/// and no place where a fourth address source would have to register.
///
/// THE THREE SOURCES, and they are exactly the three from which
/// `V41Node.ownEntry` also builds its record:
///   * [advertiseHost] — the announce address.
///   * [advertiseMapped] — the CONFIRMED port mapping (UPnP/NAT-PMP).
///     Own source (the gateway), own life cycle, therefore a
///     field of its own — and therefore it got lost here.
///   * [advertiseExtra] — the remaining address families.
///
/// UNCAPPED, unlike `ownEntry`: there
/// `.take(kMaxEntryAddresses)` cuts off because the wire format carries at most four
/// addresses. Here the same cut-off would be a hole — an
/// own address that no longer fits into the own record is
/// still the own address.
///
/// What is compared is the HOST, not host+port: the port of the own
/// old stock is a different one than the running one (newly rolled on
/// every deleted profile), and exactly this case was the field finding
/// of 07.09.2026.
Set<String> ownDialHosts({
  required String advertiseHost,
  EntryAddress? advertiseMapped,
  Iterable<EntryAddress> advertiseExtra = const <EntryAddress>[],
}) =>
    <String>{
      if (advertiseHost.isNotEmpty) advertiseHost,
      if (advertiseMapped != null && advertiseMapped.host.isNotEmpty)
        advertiseMapped.host,
      for (final a in advertiseExtra)
        if (a.host.isNotEmpty) a.host,
    };

/// Which of these addresses drop out of dialling as the OWN host?
///
/// ── WHY THE EXCLUSION NEEDS A NAME (S377) ────────────────────────────
///
/// [dialAddressOrder] returns `null` for an excluded address
/// — and `null` there means THREE different things: "family
/// not bound", "link-local without zone" and "that is myself". The
/// only caller that reacts to an empty target list
/// (`V41Node.dialRecord`) therefore could not distinguish them and
/// logged across the board "keine anwaehlbare Adresse … eigene Familien:
/// v4,v6" — a line that explicitly EXCLUDES the applicable cause,
/// because the family was bound and the address was v4.
///
/// MEASURED what that cost: `smoke_v41_redial` had stood since S354 at
/// `4 passed, 2 failed`, and the S376 report (P1, l. 1146) recorded after
/// the investigation "the node does not dial, other cause" —
/// the cause was in the log, only under a wrong name. That is the same
/// class as the finding from which `_attemptAddress` has written along the
/// `LinkAttemptOutcome` since S374: a failure without a reason is a
/// session of measurement work.
///
/// THE COMPARISON IS NORMALISED, exactly as in [dialAddressOrder]: there
/// the host runs through [IpAddressClass.normalizeIp] before
/// `ownHosts.contains` applies. A diagnosis that compares differently
/// from the decision would be a second exclusion and thus again
/// a wrong answer.
List<EntryAddress> ownHostsAmong(
  List<EntryAddress> addresses,
  Iterable<String> ownHosts,
) {
  final currentSet = ownHosts.toSet();
  return <EntryAddress>[
    for (final a in addresses)
      if (currentSet.contains(IpAddressClass.normalizeIp(a.host))) a,
  ];
}

/// The addresses of a record that a FOREIGN node can dial —
/// as `ip:port` or `[v6]:port`.
///
/// ── WHY THIS IS NOT [dialAddressOrder] (S380, gap G-11) ──────────────
///
/// Both functions sieve addresses, but they answer different
/// questions. [dialAddressOrder] asks "which of these addresses can THIS
/// node dial NOW" and therefore depends on three local quantities:
/// `v4Available`/`v6Available` (the bound families of this node),
/// `localIps` (rank 0 for the OWN segment, and the leniency
/// towards private addresses of the same RFC1918 class) and
/// `ownHosts`.
///
/// For a ContactSeed each of these three quantities is the wrong side:
/// the code goes into the hands of a STRANGER, at a foreign connection,
/// perhaps on another continent. A node without global IPv6
/// would, with [dialAddressOrder], leave out the IPv6 of its neighbours — although
/// precisely they bring the scanner in; and a private address from the
/// own class would go out too, although it is of no use to the scanner
/// and incidentally reveals the topology of the own segment.
///
/// What remains is exactly one question — "is this address dialable
/// from outside at all" —, and for that there is [isExternallyReachable].
/// It covers everything that [dialAddressOrder] would exclude here:
/// `fe80:` (also with zone index), `169.254.`, loopback, `::`/`::1`, ULA
/// `fc00::/7`, the four WIN-2 pseudo forms (Teredo, 6to4, `2001:db8:`,
/// `::ffff:`), RFC1918 and the undialable IPv4 ranges (DS-Lite, CGNAT).
///
/// CHECKED NORMALISED **AND** OUTPUT NORMALISED, unlike
/// [dialAddressOrder]: there the string of the record must
/// come back, because `EntryCache.lookupEndpoint` is keyed on it.
/// This lookup does not exist here — the address goes onto a
/// QR code and becomes an entry hint at the scanner. Outputting a mapped
/// `::ffff:a.b.c.d` as `[::ffff:…]:port` would mean handing it an IPv4
/// as IPv6.
///
/// The ORDER stays that of the record. Whoever has to order it by families
/// does so where the cap is
/// (`ContactSeedBuilder._familiesChange`) — here it would be a second,
/// quieter order.
List<String> externallyDialableAddresses(List<EntryAddress> addresses) {
  final out = <String>[];
  for (final a in addresses) {
    final h = IpAddressClass.normalizeIp(a.host);
    if (!isExternallyReachable(h)) continue;
    final s = h.contains(':') ? '[$h]:${a.port}' : '$h:${a.port}';
    if (!out.contains(s)) out.add(s);
  }
  return out;
}

List<EntryAddress> dialAddressOrder(
  List<EntryAddress> addresses, {
  required bool v4Available,
  required bool v6Available,
  Iterable<String> localIps = const <String>[],
  Iterable<String> ownHosts = const <String>[],
  int roundOffset = 0,
  int max = kDialAddressesPerRecord,
}) {
  int? rank(String h) {
    // ── THE OWN ADDRESS IS NO TARGET (S374, B-1) ──────────────────────
    //
    // [localIps] only ranked so far: an address in the own subnet
    // gets rank 0 and is dialled FIRST. For the own address
    // that is the wrong direction — it is preferred by this instead of
    // excluded.
    //
    // §11.1 says the own record is refused. That is enforced
    // in `EntryStore.ownPosition` — via the POSITION. The
    // assumption behind it is in the comment there: "the node keys
    // are persistent, the position thus the same across
    // restarts". Exactly that breaks when the profile is deleted (the
    // E2E preparation does that on every run): new keys, new
    // position, new rolled data port — and the own record
    // from before carries the OLD position, and thus cannot be told apart from a foreign
    // node at the same address.
    //
    // Measured in the field on 07.09.2026 on .201: the node announces itself
    // as `<ip4-priv#0b8a8d35>:13834` and dials in the same round
    // `<ip4-priv#0b8a8d35>:24300` — the same IP, a dead port from an
    // earlier run. Of 50 dials 40 failed; on the emulator
    // it was 247 of 272.
    //
    // The comparison is EXACT and not at subnet level: a neighbour in the
    // same segment has a DIFFERENT address and should still get rank 0.
    // Only what this machine itself is is excluded.
    if (ownHosts.contains(h)) return null;
    if (h.contains(':')) {
      if (!v6Available) return null;
      final k = h.toLowerCase();
      if (k.startsWith('fe80:')) return null; // link-local without zone
      if (isTunnelIpv6(h)) return 4;
      if (k.startsWith('fc') || k.startsWith('fd')) return 3; // ULA
      if (!IpAddressClass.isPrivate(h)) return 1; // global
      return 4; // ::1 and whatever else counts as private
    }
    if (!v4Available) return null;
    if (h.startsWith('169.254.')) return null; // without DHCP
    if (IpAddressClass.isInLocalSubnet(h, localIps)) return 0;
    if (!IpAddressClass.isPrivate(h)) return 2;
    // ── A PRIVATE ADDRESS FROM A FOREIGN CLASS IS NO TARGET ───────────
    //
    // Until S379 it stood at rank 4 and was thus dialled — last,
    // but still. That was bearable as long as private addresses only came via
    // the LAN call and via partner links, i.e. from nodes with
    // which this node shares a segment anyway.
    //
    // Since `brettDecision` passes one host candidate per family
    // (S379), private addresses also stand on the PUBLIC board.
    // Without this probe every board reader on the internet would pay a failed attempt
    // for every such record — and that books on the
    // record, not on the address (`noteUnreachable`).
    //
    // THE PROBE IS THE SAME one that `observedAnnounceAddresses` performs
    // (`samePrivatklasse`), and it is deliberately coarse: whoever is
    // in `192.168/16` themselves tries a `192.168` address. In a
    // routed intranet — two segments, one router — that is exactly the
    // path that carries; measured on 09.09.2026 between `192.0.2.202`
    // and the bootstrap's LAN address (`192.168.178.x`): ping and TCP 8081 open, while the
    // record from the board carried only an IPv6 that this node cannot
    // reach.
    // LOOPBACK IS EXEMPT. `127.0.0.0/8` counts as private, but belongs
    // to no RFC1918 class: the probe would discard every
    // loopback address. It only reaches the same machine anyway,
    // and the failed attempt there costs no packet on the
    // wire.
    if (h.startsWith('127.')) return 4;
    // IF THIS NODE DOES NOT YET KNOW ITS OWN ADDRESSES, the
    // old behaviour applies. At start the announcement is not yet set
    // (`setAnnounceAddresses` only runs after the enumeration), and a
    // node that discards the private address of its neighbour in this gap
    // does not come up in the own segment. An EMPTY set
    // means "unknown"; a known set WITHOUT a private address on the other hand means
    // "this node is in no RFC1918 network" — and then
    // the probe rightly applies.
    final own = localIps.where((l) => l.isNotEmpty).toList();
    if (own.isEmpty) return 4;
    final ownPrivate = own
        .map(IpAddressClass.normalizeIp)
        .where((l) => !l.contains(':') && IpAddressClass.isPrivate(l));
    if (!ownPrivate.any((l) => samePrivateClass(h, l))) return null;
    return 4;
  }

  // The index is CARRIED ALONG and not produced by pre-sorting:
  // `List.sort` is not stable in Dart, and within a rank
  // the order of the record applies — the same reasoning as in
  // [EntryCache.dialCandidates].
  final rated = <({EntryAddress a, bool isV6, int rank, int idx})>[];
  for (var i = 0; i < addresses.length; i++) {
    final h = IpAddressClass.normalizeIp(addresses[i].host);
    final r = rank(h);
    if (r == null) continue;
    rated.add((a: addresses[i], isV6: h.contains(':'), rank: r, idx: i));
  }
  rated.sort((x, y) => x.rank != y.rank ? x.rank - y.rank : x.idx - y.idx);

  final perFamily = <bool, List<EntryAddress>>{};
  for (final e in rated) {
    (perFamily[e.isV6] ??= <EntryAddress>[]).add(e.a);
  }
  // The iteration is over the RANKING: which family comes first
  // is decided by its best-placed member. On the first occurrence of a
  // family its `roundOffset`-th address is taken, after that the
  // family is done.
  final chosen = <EntryAddress>[];
  final seen = <bool>{};
  for (final e in rated) {
    if (!seen.add(e.isV6)) continue;
    final group = perFamily[e.isV6]!;
    chosen.add(group[roundOffset.abs() % group.length]);
    if (chosen.length >= max) break;
  }
  return chosen;
}

/// An entry record: everything needed to START a connection
/// to a node.
///
/// WHY IT MUST EXIST. The §2.6 handshake cannot be started
/// without knowing the static material of the other side — flight 1 could
/// otherwise not be MACed. Whoever knows only a position can compute (distance,
/// responsibility) and nothing else. In the lab this was so far passed
/// by hand (`--peer-material`); this here replaces the crutch.
///
/// WHY TWO-STAGE — that is the actual decision. A record
/// is over 1.2 KB large with the ML-KEM key and thus does NOT fit into
/// a cell (frame body 1169 B); it must be fragmented and costs
/// two slots. A position costs 32 B, i.e. one thirty-fifth
/// of a cell. If records were announced, making
/// eight neighbours known would cost over two minutes of send time — and that for nodes with
/// which one may never talk. Therefore: positions are ANNOUNCED
/// (cheap, sufficient for routing table and distance calculation), the record is REQUESTED
/// only when one really wants to reach the node. The
/// effort thus arises where the benefit also lies.
///
/// WHOM ONE ASKS: the one who announced the position. It knows it, otherwise
/// it would not have named it.
final class EntryRecord {
  /// Netzposition (L_node), 32 B.
  final Uint8List lNode;

  /// Static Ed25519 part (`E_node`).
  ///
  /// It enters no handshake — it is here because the position is computed from
  /// all three static keys and the record would otherwise
  /// not be recomputable.
  final Uint8List eNodePublic;

  /// Static X25519 share.
  final Uint8List x25519Public;

  /// Static ML-KEM-768 share.
  final Uint8List mlKemPublic;

  /// Until when this record is to be valid (ms since epoch, UTC).
  ///
  /// Without expiry a record once issued would circulate forever —
  /// even long after the node no longer has the address.
  final int expiryMs;

  /// Ed25519 signature of the issuer over everything before.
  ///
  /// WHY THE HASH BINDING DOES NOT SUFFICE. `L_node` is the hash over the
  /// three static keys — it does not cover the ADDRESS. Without a
  /// signature someone could deliver real keys with a wrong address;
  /// the handshake would then fail (the keys do not
  /// match the operator of the address), but every
  /// connection attempt to this position would run into the void. That is no
  /// identity theft, but a redirection — and exactly against that
  /// the issuer signs with `E_node`, which otherwise lay around unused.
  ///
  /// The chain thus closes: position <- keys <- signature <-
  /// address and expiry.
  final Uint8List signature;

  /// Addresses at which a connection attempt is to be made.
  ///
  /// SEVERAL, not one — and that is no convenience. A node with
  /// IPv4 AND IPv6 must be recognisable as such:
  ///
  ///   * §17.3 resolves `v4-only <-> v6-only` for calls via a
  ///     "dual-stack volunteer" as media relay. Whoever names only one address
  ///     cannot be found as a volunteer.
  ///   * §25 measures the share of the weaker address family among the
  ///     sync partners. With one address per node one measures which
  ///     family it happened to name, not which it has.
  ///   * And whoever is reachable on both families is simply better
  ///     reachable.
  ///
  /// Addresses are volatile — that is no flaw of the record, but
  /// the situation. A record with dead addresses stays valid for the
  /// key part; only the connection attempt fails.
  final List<EntryAddress> addresses;

  /// The first address — for everything that needs only one.
  String get host => addresses.first.host;
  int get port => addresses.first.port;

  /// Is this node reachable on both address families?
  ///
  /// That is the property that §17.3 demands for the media volunteer:
  /// only a node with both families can mediate between a
  /// v4-only and a v6-only counterpart.
  bool get isDualStack {
    var v4 = false;
    var v6 = false;
    for (final a in addresses) {
      if (a.host.contains(':')) {
        v6 = true;
      } else {
        v4 = true;
      }
    }
    return v4 && v6;
  }

  EntryRecord({
    required this.lNode,
    required this.eNodePublic,
    required this.x25519Public,
    required this.mlKemPublic,
    required this.addresses,
    required this.expiryMs,
    required this.signature,
  }) {
    if (lNode.length != 32) throw ArgumentError('L_node must be 32 B');
    if (eNodePublic.length != 32) throw ArgumentError('E_node must be 32 B');
    if (x25519Public.length != 32) throw ArgumentError('X25519 must be 32 B');
    if (mlKemPublic.length != NodeKeys.nMlKemPublicLength) {
      throw ArgumentError('ML-KEM must be ${NodeKeys.nMlKemPublicLength} B');
    }
    if (addresses.isEmpty) throw ArgumentError('at least one address');
    if (addresses.length > kMaxEntryAddresses) {
      throw ArgumentError('at most $kMaxEntryAddresses addresses');
    }
    if (signature.length != 64) throw ArgumentError('Signature must be 64 B');
  }

  /// True if the position matches the keys.
  ///
  /// THAT IS THE WHOLE POINT. As long as `L_node` was random, anyone who
  /// answered a request could write arbitrary keys under a foreign
  /// position — imitation of any position without owning it, and
  /// cheaper than any Sybil grind. Since the position is
  /// computed from the keys, exactly that gets noticed.
  bool get isAuthentic {
    if (!NodeKeys.verifyPosition(
      claimed: lNode,
      eNodePublic: eNodePublic,
      nX25519Public: x25519Public,
      nMlKemPublic: mlKemPublic,
    )) {
      return false;
    }
    return SodiumFFI().verifyEd25519(_signedPart(), signature, eNodePublic);
  }

  /// Is the record still valid at this point in time?
  ///
  /// Separate from [isAuthentic], because authenticity is timeless and freshness is not:
  /// an expired record is not forged, only old. Decoding
  /// therefore checks only authenticity — a clock does not belong in a
  /// parser.
  bool isFresh(DateTime now) => now.millisecondsSinceEpoch < expiryMs;

  /// Was this record issued LATER than [other]?
  ///
  /// WHY THE EXPIRY SHOULD ORDER THE ISSUANCE. A record carries
  /// no issuance time — only `expiryMs`, and that is
  /// `issuance + validFor`. If both deadlines are equal, the
  /// expiry orders the issuance.
  ///
  /// ── THIS PRECONDITION NO LONGER HOLDS (S381, 11.09.2026) ────────────
  ///
  /// This said: "`validFor` is the same constant ([EntryRecord.issue]
  /// has **exactly one caller** with the default value)". Re-measured,
  /// `issue` has **two** callers with **different** `validFor`:
  /// `V41Node.ownEntry` (`v41_node.dart:1101`) with the default value of
  /// SEVEN days and `brettDecision` (`v41_attach.dart:1436`) with
  /// `kBrettValidity` = ONE day. Both end up at a counterpart in the
  /// same [EntryCache].
  ///
  /// Computed: an `ownEntry` from time `t` expires at `t + 7 days`,
  /// a FRESH board record at `now + 1 day`. The fresh one
  /// counts as older as long as the `ownEntry` is younger than six days —
  /// **so for six days an outdated `ownEntry` beats every
  /// fresh board record of the same node.** Exactly the case against
  /// which the B-33 paragraph in [EntryCache.remember] was written ("an
  /// old one with a dead port, a new one with a live one").
  ///
  /// The comparison stays as it is for now: the remedy is a
  /// first-capture timestamp in the record, and that changes the
  /// wire format (version byte 4 → 5). That is an owner decision —
  /// proposal: `docs/v4-redesign/S381-VORLAGE-eintrittsdatensatz-stabilitaet.md`.
  ///
  /// Across different nodes the comparison says nothing, and it
  /// is needed only per position anyway.
  ///
  /// WHAT FOR. The external rendezvous places records SIDE BY SIDE, not
  /// on top of each other (§11.3: "a throwaway keypair per event so a query
  /// returns *every* publisher rather than the last one"). A query
  /// therefore returns EVERY publication of a node of the last two
  /// days — with the addresses it had back then. Without this
  /// comparison the order in which the relays answer decides
  /// which address lands in the supply; on 29.08. four relays delivered 86
  /// lumps, and the last one processed won.
  bool issuedAfter(EntryRecord other) => expiryMs > other.expiryMs;

  /// Issues a signed record for the own keys.
  static EntryRecord issue({
    required NodeKeys keys,
    required DateTime now,
    String? host,
    int? port,
    List<EntryAddress>? addresses,
    Duration validFor = const Duration(days: 7),
  }) {
    final addr = addresses ??
        [EntryAddress(host!, port!)];
    final expiry = now.add(validFor).millisecondsSinceEpoch;
    final body = _encodeBody(
      lNode: keys.lNode,
      eNodePublic: keys.eNodePublic,
      x25519Public: keys.nX25519Public,
      mlKemPublic: keys.nMlKemPublic,
      expiryMs: expiry,
      addresses: addr,
    );
    return EntryRecord(
      lNode: keys.lNode,
      eNodePublic: keys.eNodePublic,
      x25519Public: keys.nX25519Public,
      mlKemPublic: keys.nMlKemPublic,
      addresses: addr,
      expiryMs: expiry,
      signature: SodiumFFI().signEd25519(body, keys.eNodeSecret),
    );
  }

  Uint8List _signedPart() => _encodeBody(
        lNode: lNode,
        eNodePublic: eNodePublic,
        x25519Public: x25519Public,
        mlKemPublic: mlKemPublic,
        expiryMs: expiryMs,
        addresses: addresses,
      );

  static Uint8List _encodeBody({
    required Uint8List lNode,
    required Uint8List eNodePublic,
    required Uint8List x25519Public,
    required Uint8List mlKemPublic,
    required int expiryMs,
    required List<EntryAddress> addresses,
  }) {
    final parts = <List<int>>[];
    for (final a in addresses) {
      final h = utf8.encode(a.host);
      if (h.length > 255) throw ArgumentError('Host too long');
      parts.add(h);
    }
    final n = NodeKeys.nMlKemPublicLength;
    var length = 1 + 32 + 32 + 32 + n + 8 + 1;
    for (final h in parts) {
      length += 2 + 1 + h.length;
    }
    final out = Uint8List(length);
    var o = 0;
    out[o++] = 4;
    out.setRange(o, o += 32, lNode);
    out.setRange(o, o += 32, eNodePublic);
    out.setRange(o, o += 32, x25519Public);
    out.setRange(o, o += n, mlKemPublic);
    ByteData.sublistView(out, o, o + 8).setInt64(0, expiryMs, Endian.little);
    o += 8;
    out[o++] = addresses.length;
    for (var i = 0; i < addresses.length; i++) {
      out[o++] = (addresses[i].port >> 8) & 0xff;
      out[o++] = addresses[i].port & 0xff;
      out[o++] = parts[i].length;
      out.setRange(o, o + parts[i].length, parts[i]);
      o += parts[i].length;
    }
    return out;
  }


  /// `ver(1) ‖ lNode(32) ‖ eNode(32) ‖ x25519(32) ‖ mlkem(n) ‖ port(2) ‖ hostLen(1) ‖ host`
  ///
  /// The host is at the end as text, because that is the only form that
  /// treats IPv4, IPv6 and a later name alike — a
  /// family identifier would only have produced case distinctions here.
  Uint8List encode() {
    final body = _signedPart();
    final out = Uint8List(body.length + 64);
    out.setRange(0, body.length, body);
    out.setRange(body.length, out.length, signature);
    return out;
  }


  static const int _fixed = 1 + 32 + 32 + 32 + 8 + 1 + 3 + 64;

  /// Length of an encoded record with a given host length.
  static int encodedLength(int hostLength) =>
      _fixed + NodeKeys.nMlKemPublicLength + hostLength;

  /// Reads a record from [offset]. Returns `null` if the bytes
  /// do not fit — silently, as everywhere (E-83).
  static ({EntryRecord record, int next})? decodeAt(Uint8List b, int offset) {
    final n = NodeKeys.nMlKemPublicLength;
    if (offset + _fixed + n > b.length) return null;
    var o = offset;
    if (b[o++] != 4) return null;
    final lNode = Uint8List.fromList(b.sublist(o, o += 32));
    final e = Uint8List.fromList(b.sublist(o, o += 32));
    final x = Uint8List.fromList(b.sublist(o, o += 32));
    final mk = Uint8List.fromList(b.sublist(o, o += n));
    final expiry = ByteData.sublistView(b, o, o + 8).getInt64(0, Endian.little);
    o += 8;
    final count = b[o++];
    if (count < 1 || count > 4) return null;
    final addr = <EntryAddress>[];
    for (var i = 0; i < count; i++) {
      if (o + 3 > b.length) return null;
      final port = (b[o] << 8) | b[o + 1];
      o += 2;
      final hostLen = b[o++];
      if (o + hostLen > b.length) return null;
      final String host;
      try {
        host = utf8.decode(b.sublist(o, o + hostLen));
      } on FormatException {
        return null;
      }
      o += hostLen;
      if (port < 1 || port > 65535) return null;
      addr.add(EntryAddress(host, port));
    }
    if (o + 64 > b.length) return null;
    final sig = Uint8List.fromList(b.sublist(o, o += 64));
    try {
      final rec = EntryRecord(
          lNode: lNode,
          eNodePublic: e,
          x25519Public: x,
          mlKemPublic: mk,
          addresses: addr,
          expiryMs: expiry,
          signature: sig);
      // Position does not match the keys, or the signature does not
      // hold -> does not even get into the process. Silently (E-83). The
      // EXPIRY is not checked here; a clock does not belong in a
      // parser.
      if (!rec.isAuthentic) return null;
      return (record: rec, next: o);
    } on ArgumentError {
      return null;
    }
  }




  /// The key part in the form the connection setup expects.
  PeerNodeMaterial toMaterial() => PeerNodeMaterial(
        lNode: lNode,
        x25519Public: x25519Public,
        mlKemPublic: mlKemPublic,
      );

  Map<String, Object?> toJson() => {
        'lNode': base64.encode(lNode),
        'eNode': base64.encode(eNodePublic),
        'x25519': base64.encode(x25519Public),
        'mlkem': base64.encode(mlKemPublic),
        'addr': addresses.map((a) => {'h': a.host, 'p': a.port}).toList(),
        'expiry': expiryMs,
        'sig': base64.encode(signature),
      };

  static EntryRecord? fromJson(Map<String, Object?> j) {
    try {
      return EntryRecord(
        lNode: Uint8List.fromList(base64.decode(j['lNode']! as String)),
        eNodePublic:
            Uint8List.fromList(base64.decode(j['eNode']! as String)),
        x25519Public:
            Uint8List.fromList(base64.decode(j['x25519']! as String)),
        mlKemPublic: Uint8List.fromList(base64.decode(j['mlkem']! as String)),
        addresses: [
          for (final a in (j['addr']! as List))
            EntryAddress(
                (a as Map)['h']! as String, a['p']! as int)
        ],
        expiryMs: j['expiry']! as int,
        signature: Uint8List.fromList(base64.decode(j['sig']! as String)),
      );
    } catch (_) {
      return null;
    }
  }
}

/// How many unsuccessful dial attempts a position tolerates before its
/// record falls out of the supply.
///
/// THREE, and the number is not picked: a single failed attempt is
/// the normal case (a node is just changing network, a packet gets
/// lost), two can still be, three in a row no longer are.
/// Work rule 5 binds from above — every attempt costs packets.
const int kDialFailureLimit = 3;

/// Rest period after the n-th failed attempt: `n x kDialBackoff`.
const Duration kDialBackoff = Duration(seconds: 60);

/// How long a position is left alone after [kDialFailureLimit] failed attempts
/// — even if it announces itself anew in the meantime.
///
/// WHY THE ANNOUNCEMENT DOES NOT SUFFICE. The LAN entry calls every 30 s
/// and issues a fresh own record EVERY TIME
/// (`lan_entry_wiring.dart:75`, `ownRecord: () => node.ownEntry`). If
/// every newer announcement cleared the counter, this node would dial
/// an unreachable counterpart again every 30 s, forever — exactly
/// the "incessant new connections" from B-33. A newer announcement
/// therefore GIVES one attempt (it is a sign of life), but it does
/// not delete the history. Only after the quarantine does the
/// count start over; the node thus forgets, but not immediately.
const Duration kDialQuarantine = Duration(minutes: 15);

/// What this node knows about its own dial attempts to a position.
/// Pure local knowledge: it arises only from own attempts and
/// never goes onto the wire.
final class _DialMemo {
  int failures = 0;

  /// Before this point in time there is no re-dial.
  DateTime? until;
}

/// What the node knows of entry records.
///
/// WHY WITH AN UPPER BOUND. A supply that only grows is a lever: whoever
/// sends many records makes the node grow. Once the limit is
/// reached, the least recently used entry gives way — not the
/// oldest overall, otherwise exactly what currently carries falls out.
final class EntryCache {
  final int capacity;
  final Map<String, EntryRecord> _byPosition = {};

  /// Second index: `host:port` -> record.
  ///
  /// The connection setup asks by ENDPOINT, not by position — it
  /// does not yet know who sits there. Without this index the
  /// supply would have to be searched linearly on every connection attempt.
  final Map<String, EntryRecord> _byEndpoint = {};
  final List<String> _lru = [];

  /// How many records come from which source — for the quota.
  final Map<Object, int> _bySource = {};
  final Map<String, Object> _sourceOf = {};

  /// The own position — records about it are refused.
  ///
  /// §11.1: "A node's own record is refused when it comes back from a
  /// partner — it looks harmless and would put the node's own position
  /// into its own routing table, making it consider itself a responsible
  /// relay." The rule was so far only in `V41Node._learnEntry`, i.e. on
  /// the path via a partner. The external rendezvous goes past it
  /// and returns the own earlier publications too
  /// — the node keys are persistent
  /// (`NodeKeys.loadOrCreate`), the position thus the same across restarts.
  /// The rule therefore belongs in the supply, through which every path
  /// must go.
  Uint8List? ownPosition;

  /// Is called when a record has been taken into the supply.
  ///
  /// ── WHY THIS CALLBACK MUST EXIST ─────────────────────────────────────
  ///
  /// Supply and routing table are TWO views of the same knowledge:
  /// the supply says how to reach someone, the table where they lie in the
  /// metric space. Whoever has a record also knows the position —
  /// it is in it. Nevertheless the two diverged: `_learnEntry`
  /// (the path via a partner) filled both, but the cold-start cascade
  /// writes directly into the supply (`v41_attach.dart:200`,
  /// `v41.entries.remember(r, source: 'extern')`) and thus past the table.
  ///
  /// THE CONSEQUENCE IS NOT COSMETIC. `placeSecure` and `harvestTick`
  /// choose their relay with `table.closest(ziel, count: 8)`. On 29.08.
  /// Node 1 and Node 2 each held 83 entry records — and their
  /// routing tables knew only their own session partners (two and
  /// one respectively). Two nodes that map the same tag onto two tiny, different
  /// neighbourhoods end up at different targets:
  /// Alice places at X, Bob asks at Y — `geerntet: 0`, on every
  /// node, in every round.
  void Function(EntryRecord r)? onRemembered;

  /// Reachability memory per position.
  ///
  /// SEPARATE FROM THE RECORD, and that is the point: it must
  /// OUTLIVE the record. If a record falls out after [kDialFailureLimit]
  /// failed attempts and a partner passes it back in right after,
  /// the history would otherwise be deleted and the node would dial
  /// the same dead address again.
  final Map<String, _DialMemo> _dial = {};

  EntryCache({this.capacity = 512});

  int get size => _byPosition.length;

  static String keyOf(Uint8List lNode) => base64.encode(lNode);

  EntryRecord? lookup(Uint8List lNode, {DateTime? now}) {
    final k = keyOf(lNode);
    final r = _byPosition[k];
    if (r == null) return null;
    if (!r.isFresh(now ?? DateTime.now())) {
      _forget(k);
      return null;
    }
    _lru.remove(k);
    _lru.add(k);
    return r;
  }

  bool has(Uint8List lNode) => _byPosition.containsKey(keyOf(lNode));

  /// Takes in a record.
  ///
  /// [source] is who delivered it. If it is set, a quota applies:
  /// at most a quarter of the supply may come from ONE source. Without
  /// it a single partner could flood the supply with its acquaintances
  /// and thus determine whom this node can reach at all
  /// (Doc Z-22).
  bool remember(EntryRecord r, {DateTime? now, Object? source}) {
    if (!r.isAuthentic) return false;
    final own = ownPosition;
    if (own != null && keyOf(own) == keyOf(r.lNode)) return false;
    final current = now ?? DateTime.now();
    if (!r.isFresh(current)) return false;
    final k = keyOf(r.lNode);
    // ── THE YOUNGER ONE WINS, ALWAYS (B-33) ───────────────────────────
    //
    // Until here the last PROCESSED one won — `_byPosition[k]`
    // was overwritten unconditionally. That is harmless as long as a
    // source delivers exactly one record per position; but the external
    // rendezvous delivers EVERY publication of the last two
    // days side by side (§11.3, deliberately so), and the relays answer in
    // arbitrary order. On 29.08. the phone fetched 86 lumps; where
    // two records of the same node lay among them — an old one with a
    // dead port, a new one with a live one —, the chance of the
    // answer order decided which address stayed in the supply.
    //
    // A TIE COUNTS AS OLD. Two lumps with identical expiry are
    // the same record from two relays; entering it again costs
    // index work and makes the caller count 86 "new" ones where there were
    // perhaps twenty.
    final present = _byPosition[k];
    if (present != null && !r.issuedAfter(present)) return false;
    // A younger record is a sign of life: the position has reported anew
    // since the last failed attempt and is given one attempt.
    // The quarantine survives that (see [kDialQuarantine]).
    if (present != null) _grantRetry(k);
    if (source != null && !_byPosition.containsKey(k)) {
      final quote = capacity ~/ 4;
      final already = _bySource[source] ?? 0;
      if (already >= quote) return false;
      _bySource[source] = already + 1;
      _sourceOf[k] = source;
    }
    if (!_byPosition.containsKey(k) && _byPosition.length >= capacity) {
      final evict = _lru.first;
      _forget(evict);
    }
    final old = present;
    if (old != null) {
      for (final a in old.addresses) {
        _byEndpoint.remove(endpointKey(a.host, a.port));
      }
    }
    _byPosition[k] = r;
    // ALL addresses into the index: the connection setup takes the one on
    // its family, and must also find the record via it.
    for (final a in r.addresses) {
      _byEndpoint[endpointKey(a.host, a.port)] = r;
    }
    _lru.remove(k);
    _lru.add(k);
    onRemembered?.call(r);
    return true;
  }

  void _forget(String k) {
    final gone = _byPosition.remove(k);
    if (gone != null) {
      for (final a in gone.addresses) {
        _byEndpoint.remove(endpointKey(a.host, a.port));
      }
    }
    _lru.remove(k);
    final src = _sourceOf.remove(k);
    if (src != null) {
      final n = (_bySource[src] ?? 1) - 1;
      if (n <= 0) {
        _bySource.remove(src);
      } else {
        _bySource[src] = n;
      }
    }
  }

  static String endpointKey(String host, int port) => '$host:$port';

  /// Record for an endpoint — the path the connection setup takes.
  EntryRecord? lookupEndpoint(String host, int port, {DateTime? now}) {
    final r = _byEndpoint[endpointKey(host, port)];
    if (r == null) return null;
    if (!r.isFresh(now ?? DateTime.now())) {
      _forget(keyOf(r.lNode));
      return null;
    }
    return r;
  }

  // ── REACHABILITY AND EXPIRY (B-33) ─────────────────────────────────
  //
  // WHY THE EXPIRY DOES NOT SUFFICE. `expiryMs` is the only ageing
  // a record brings along, and it is set to seven days
  // ([EntryRecord.issue], `validFor`). A node that was switched off an hour ago
  // is thus still "fresh" for six days and twenty-three
  // hours — for this supply, for `dialFromEntries`,
  // for `_entrySet` and thus for every partner to whom it is passed on.
  // The supply can measure expiry, it does not measure reachability.
  //
  // WHAT IT HAS INSTEAD: its own dial attempts. That is the
  // only evidence about reachability that this node produces
  // itself — "evidence not acquaintance" (§22.7.1), applied to the
  // supply. It is node-local and never goes onto the wire.

  _DialMemo _memo(String k) => _dial.putIfAbsent(k, () {
        // CAPPED like everything else here: the memory outlives the
        // record, so it needs a limit of its own. The
        // oldest entry falls — for a map in insertion order the
        // first.
        while (_dial.length >= capacity) {
          _dial.remove(_dial.keys.first);
        }
        return _DialMemo();
      });

  void _grantRetry(String k) {
    final m = _dial[k];
    if (m == null) return;
    // After the limit the quarantine applies, and nobody gives that away.
    if (m.failures >= kDialFailureLimit) return;
    m.until = null;
  }

  /// Clears away a memory whose deadline has expired.
  void _dialGc(String k, DateTime now) {
    final m = _dial[k];
    if (m == null) return;
    final until = m.until;
    if (until == null) return;
    if (now.isBefore(until)) return;
    if (m.failures >= kDialFailureLimit) {
      // Quarantine survived — the node starts over at this position.
      // A network in which an address once dead stayed dead forever
      // could not recover from an outage.
      _dial.remove(k);
    } else {
      m.until = null;
    }
  }

  /// How many dial attempts to this position remained unsuccessful.
  int failuresFor(Uint8List lNode) => _dial[keyOf(lNode)]?.failures ?? 0;

  /// Is this position currently in a rest period?
  bool isBackedOff(Uint8List lNode, {DateTime? now}) {
    final k = keyOf(lNode);
    final current = now ?? DateTime.now();
    _dialGc(k, current);
    final until = _dial[k]?.until;
    return until != null && current.isBefore(until);
  }

  /// A session to this position is up — the history is settled.
  void noteReachable(Uint8List lNode) => _dial.remove(keyOf(lNode));

  /// A dial attempt remained unsuccessful.
  ///
  /// Returns `true` if the record has thereupon fallen out of the supply
  /// — THAT is the expiry path that so far did not exist for
  /// reachability.
  bool noteUnreachable(Uint8List lNode, {DateTime? now}) {
    final k = keyOf(lNode);
    final current = now ?? DateTime.now();
    final m = _memo(k);
    m.failures++;
    if (m.failures >= kDialFailureLimit) {
      m.until = current.add(kDialQuarantine);
      final route = _byPosition.containsKey(k);
      if (route) _forget(k);
      return route;
    }
    m.until = current.add(kDialBackoff * m.failures);
    return false;
  }

  /// Throws away everything that has expired. Returns how many.
  ///
  /// A REAL EXPIRY PATH WITH A CALLER. Until S350 only
  /// [lookup]/[lookupEndpoint] cleaned up incidentally — i.e. exactly the paths that
  /// USE a record. What was never looked up stayed until
  /// displacement and was still handed out by [all]. The
  /// caller is `V41Node.harvestTick`, the only regular clock
  /// of this layer that does not hang on the slot plan (invariant 1) — there
  /// `delivery.store.expire` has stood since S350 for the same reason.
  int expire(DateTime now) {
    final dead = <String>[];
    for (final e in _byPosition.entries) {
      if (!e.value.isFresh(now)) dead.add(e.key);
    }
    for (final k in dead) {
      _forget(k);
    }
    return dead.length;
  }

  /// Whom this node should dial, in the order in which it
  /// pays off.
  ///
  /// ── WHY THIS METHOD MUST EXIST (B-33) ─────────────────────────────
  ///
  /// `dialFromEntries` so far ran over [all], and [all] hands out
  /// `_byPosition.values` — the INSERTION ORDER. After a
  /// cold start via the external rendezvous that is the order in
  /// which the relays answered, i.e. chance without order. On
  /// 29.08. at 12:26:48 the phone fetched 86 records and dialled the
  /// FIRST ones among them. If only the three youngest of them were alive, a
  /// cap of four would hit a live node at all with probability
  /// `1 − C(83,4)/C(86,4) ≈ 13,5 %`.
  ///
  /// THE ORDER, IN THREE LEVELS:
  ///
  ///   1. Whoever has never failed comes before the one who has
  ///      failed. Resting positions drop out entirely.
  ///   2. Then the younger PUBLICATION — to the hour,
  ///      not to the millisecond. Whoever reported an hour ago
  ///      is more likely running than whoever reported three days
  ///      ago.
  ///   3. Within an hour: CHANCE. RL-1 states that
  ///      sync partners are chosen randomly; a strict order
  ///      would draw all nodes into the same corner — the same
  ///      reasoning from which `_entrySet` draws randomly.
  List<EntryRecord> dialCandidates({DateTime? now}) {
    final current = now ?? DateTime.now();
    // The random key is CARRIED ALONG, not produced by shuffling before
    // sorting: `List.sort` is not stable in Dart, so a
    // prior shuffle would not reliably survive the comparison.
    final rnd = Random();
    final candidates = <({EntryRecord r, int fails, int hour, int throwValue})>[];
    for (final r in _byPosition.values) {
      if (!r.isFresh(current)) continue;
      if (isBackedOff(r.lNode, now: current)) continue;
      candidates.add((
        r: r,
        fails: failuresFor(r.lNode),
        hour: r.expiryMs ~/ 3600000,
        throwValue: rnd.nextInt(1 << 30),
      ));
    }
    candidates.sort((a, b) {
      if (a.fails != b.fails) return a.fails - b.fails;
      if (a.hour != b.hour) return b.hour - a.hour;
      return a.throwValue - b.throwValue;
    });
    return [for (final k in candidates) k.r];
  }

  /// Why a record is currently NOT dialled — one line per
  /// position, at most [atMost].
  ///
  /// ── WHY THIS IS A CALL OF ITS OWN (S380, 10.09.2026) ──────────────
  ///
  /// `dialFromEntries` reports "N of M records dialable (rest
  /// expired OR in rest period)". The word "or" cost an hour on 10.09.2026:
  /// on the board lay the bootstrap with its
  /// public IPv4, in the node's supply it lay too — and it was
  /// not dialled. From the line one could not tell whether it had
  /// expired, was resting, or had not come in at all. Each
  /// of the three answers would have pointed to a different place in the code.
  ///
  /// It runs only when something is really missing, and caps itself.
  List<String> heldBack({DateTime? now, int atMost = 6}) {
    final current = now ?? DateTime.now();
    final lines = <String>[];
    for (final r in _byPosition.values) {
      if (lines.length >= atMost) break;
      final where = r.addresses.isEmpty
          ? '(no address)'
          : '${r.addresses.first.host}:${r.addresses.first.port}';
      if (!r.isFresh(current)) {
        lines.add('$where expired since '
            '${current.difference(DateTime.fromMillisecondsSinceEpoch(r.expiryMs)).inMinutes} min');
        continue;
      }
      final k = keyOf(r.lNode);
      final until = _dial[k]?.until;
      if (until != null && current.isBefore(until)) {
        lines.add('$where cooldown still ${until.difference(current).inSeconds} s '
            'after ${failuresFor(r.lNode)} failed attempt(s)');
      }
    }
    return lines;
  }

  /// All known records — for persistence.
  List<EntryRecord> all() => _byPosition.values.toList(growable: false);

  Map<String, dynamic> toJson() =>
      {'v': 1, 'e': all().map((r) => r.toJson()).toList()};

  String toJsonString() => jsonEncode(toJson());

  /// Loads from what [toJson] delivered. Unreadable content is silently
  /// skipped — a broken supply must not prevent the start,
  /// and a record whose position does not match its keys
  /// does not get through [EntryRecord.fromJson] anyway.
  void loadJson(Map<String, dynamic> j, {DateTime? now}) {
    if (j['v'] != 1) return;
    final e = j['e'];
    if (e is! List) return;
    for (final item in e) {
      if (item is! Map) continue;
      final r = EntryRecord.fromJson(item.cast<String, Object?>());
      if (r != null) remember(r, now: now);
    }
  }

  /// Loads from what [toJsonString] wrote. Unreadable content is
  /// silently skipped — a broken supply must not prevent the start.
  void loadJsonString(String s) {
    try {
      final j = jsonDecode(s);
      if (j is! Map) return;
      loadJson(j.cast<String, dynamic>());
    } catch (_) {
      // still
    }
  }
}
