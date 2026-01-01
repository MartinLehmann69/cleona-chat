import 'dart:async';
import 'dart:io';
import 'dart:typed_data';


import '../config/network_channel.dart';
import '../config/rendezvous_relays.dart';
import '../crypto/file_encryption.dart';
import '../crypto/oqs_ffi.dart';
import '../rendezvous/nostr_provider.dart';
import '../rendezvous/rendezvous_provider.dart' show EndpointAddress;
import 'package:cleona/generated/proto/transport_v3.pb.dart' as pb;
import 'package:cleona/generated/proto/transport_v3.pbenum.dart' as pe;
import 'invite_line.dart';
import 'package:cleona/core/sync/cold_start.dart';
import 'device_line.dart';
import 'entry_sources.dart';
import 'package:cleona/core/sync/external_entry.dart';
import '../calls/call_transport_v41.dart' show CallPlaneD;
import '../link/node_keys.dart';
// Only for the address book from §17.3 — `V41Node.host` holds it, and
// `setzeAnsageadressen` asks it.
import '../link_io/link_host.dart' show ObservedAddressBook;
import '../service/cleona_service.dart';
import '../storage/message_store.dart' show MessageStore;
import '../service/media_bulk_lane.dart' show MediaBulkLane;
import '../service/media_bulk_transport_v41.dart'
    show V41MediaBulkTransport, bulkCacheForPlatform;
import '../service/v41_routing.dart' show shortPairLabel;
// §26.6.5 — the HTTP switch of the data port. Permitted: the separation that
// `smoke_link_io_milestone` section 5 and `smoke_link_axis_guard`
// guard applies against the five V3 trees (`network`, `node`, `dht`,
// `erasure`, `identity_resolution`). `lib/core/update/` is none of them,
// but a permanent V4 module (§26.6.8 lists it in the
// component table).
import '../update/binary_http_server.dart' show BinaryHttpServer;
// Only `normalizeIp`, and only for the SOURCE ADDRESS of an incoming
// session — see [_merkeEingang]. The address classification itself comes
// from `local_addresses.dart`; `IpAddressClass.isPrivate` knows neither
// `169.254/16` nor the four WIN-2 pseudo forms.
import '../util/ip_address_class.dart' show IpAddressClass;
import '../util/hex.dart' show bytesToHex;
// Only the flat record that the sending side of the entry bridge passes via
// `ContactSeedDataSource` (G-11). No builder, no format.
import '../contact/contact_seed.dart' show EntrySeedCandidate;
import 'package:cleona/core/sync/entry_record.dart';
import 'lan_entry.dart' show kLanEntryMulticastV4;
import 'eligibility.dart' show EligibilityRegistry;
import 'lan_entry_wiring.dart';
import 'package:cleona/core/util/local_addresses.dart';
import 'message_seal.dart';
import 'own_line.dart';
import 'port_map_wiring.dart';
import 'prekey_pool.dart';
import 'readiness.dart' show Readiness;
import 'recovery_line.dart';
import 'package:cleona/core/bulk/responsibility.dart' show nodeEpochNow;
import 'secure_mode.dart' show kMobileSecureStoreCapBytes;
import 'v41_host.dart';
import 'v41_node.dart';

/// How many start-peer candidates from the entry supply are passed at most to the
/// ContactSeed builder (§11, gap G-11).
///
/// SIXTEEN, and the number is derived: the builder takes five
/// (`ContactSeedBuilder.kMaxSeedPeers`, a format limit) and before that
/// grabs one carrier per address family ahead. So that this grab has something to
/// choose from, the list must reach beyond the cap — a
/// candidate set of exactly five would not be a selection but an
/// allocation. Upwards it needs no reserve: the supply comes from
/// `dialCandidates()` and is already ordered there by reachability and freshness,
/// so candidates 17 and following are consistently the
/// worse ones. The limit only exists so that a supply of 512
/// records is not passed through completely at every glance at the QR code.
const int kSeedCandidatesCap = 16;

/// Hooks the V4.1 delivery onto a service (IP-4).
///
/// ONE FUNCTION, because the service is built in TWO places — in the
/// daemon (`service_daemon.dart`, after `host.start()`) and in-process
/// (`main.dart`). Exactly this duplication was the reason why
/// `NodeHost` exists; whoever reopens it here builds in the same drift a
/// second time.
///
/// IT IS ON. `CLEONA_V41=0` switches it off.
///
/// The first version was the other way round — off by default, with the
/// reasoning that switching over the message path was a
/// release decision. That was wrongly thought: there is no product in
/// which 3.x and 4.1 run side by side and one would switch between them.
/// **This branch IS the V4.1 line.** A switch that turns it off
/// would have produced exactly what this migration has removed everywhere
/// else: a code path that nothing enters.
///
/// The switch remains nevertheless — but as an OFF switch, for
/// comparison measurements against the V3 path. Whoever uses it knows what he
/// is doing.
///
/// WHAT IT DOES NOT DO: remove the V3 path. Media keep running via
/// the two-stage path (§5.3/B-13), and the switch sends them there.
/// „V3 out" means here: the V3 delivery path is no longer entered for SMALL messages,
/// not that it disappears.
/// The ONE V4.1 node of this process, together with its LAN entry.
///
/// TWO SCOPES, which used to be one. The node is
/// daemon-global: `L_node` belongs to the node, not to the identity, it
/// holds ONE port, ONE session set, ONE cover cycle. The
/// sealing on the other hand is pairwise — a prekey supply applies per
/// `K_AB`, i.e. per (own identity, counterpart).
///
/// EARLIER `attachV41` RAN IN THE SERVICE LOOP, i.e. once per
/// identity, each time with `port: nodePort + 1`. On a node with
/// two identities there were then TWO `V41Node` on the same UDP port
/// with the same `NodeKeys` — re-measured in the field (25.08., `ss -lunp`:
/// two sockets on 44301 and 44302, plus two separate LAN entries
/// with different random ports for the same position). Which of the
/// two nodes got an incoming datagram was decided by the kernel.
///
/// The comment at the old call site had even named the principle
/// correctly — „NODE-bound, not identity-bound" — and
/// applied it to the KEYS, but not to the node itself. The
/// guard `smoke_link_node_keys_scope_guard` checks the key scope;
/// it does not check the node scope.
/// [entryPersist] is the debounce timer that writes the entry supply to
/// disk. It stands IN THE RETURN VALUE and not only in the body, because
/// a `Timer.periodic` keeps the Dart VM alive: without a handle to
/// cancel it, every standalone test that starts a node would have hung
/// at the end — the same trap that `run-e2e.sh` describes for the logger timer
/// and because of which smoke files need a symmetric `exit`.
/// `null` if no supply directory was passed.
typedef V41Runtime = ({
  V41Node node,
  LanEntryHandle? lanEntry,
  Timer? entryPersist,
  // ── THE ADDRESS RESOLVER (S360) ──────────────────────────────────────
  //
  // It stands here because it is needed TWICE: at start, to set the
  // announcement address, and at every network change, to set it
  // anew. At start it is a parameter of [startV41Node] — but the
  // network change comes via `attachV41`, and there the parameter is
  // no longer within reach.
  //
  // Simply replacing it there with `dialableLocalAddresses` would be
  // a silent drift: a test that passes its own resolver at start
  // would get the real one at the network change — and that reads the
  // interfaces of the test machine. One handle, ONE source.
  Future<List<String>> Function() localAddresses,
  // ── THE PORT MAPPING (S373) ────────────────────────────────────────
  //
  // It stands here for the same reason as [entryPersist]: its
  // renewal timer runs for up to an hour, and a pending
  // timer keeps the Dart VM alive. Without a handle in the
  // return value no entry point could shut it down, and the
  // daemon would no longer end after `stopAll()`.
  //
  // And for the second reason for which [localAddresses] stands here: it
  // is needed TWICE — at start and at every network change. The
  // network change comes via `attachV41`, and there the construction of
  // `startV41Node` is no longer within reach.
  //
  // `null` if the node runs without port mapping (today only in the
  // test setup, which inserts its own coordinator).
  PortMapBinding? portMapping,
});

/// Enters the addresses under which this node can be dialled into its
/// announcement (§11, §17.3).
///
/// ── WHY THIS IS A FUNCTION OF ITS OWN (S360) ──────────────────────
///
/// It stood as a block in the body of [startV41Node] and was thus computed EXACTLY
/// ONCE: at the start of the process. After a network change
/// the node kept announcing the address of the old network — an
/// entry record that is formally fine and points to nothing.
/// That is the same class of bug as the loopback announcement of 25.08.
/// (S349), only delayed.
///
/// As a function it has two callers (start and network change) and
/// still ONE implementation. Two copies would be the drift against which
/// `attachV41` itself is built as one function.
///
/// [dialable] is already filtered (`isUndialableIpv4`:
/// DS-Lite/464XLAT, CGNAT, link-local — B-26).
///
/// ── AND SINCE S373 ALSO THE OBSERVED EXTERNAL ADDRESS (§17.3) ────────
///
/// Until S373 EVERY announced address came from `NetworkInterface.list`. A
/// node behind NAT thus announced exclusively its LAN address,
/// although it had long known its external address: flight 2 of the handshake
/// mirrors it back in the AEAD, `ObservedAddressBook` holds it, and
/// `agreed(`/`disagrees(` had ZERO callers in `lib/`. The guard
/// `smoke_delivery_layer_unwalked_guard` listed both on its
/// exception list with exactly this wording: „built and not asked".
///
/// **WHAT AN OBSERVED ADDRESS PROVES, AND WHAT NOT.** It proves
/// that the OUTGOING NAT mapping exists — a partner has seen a
/// datagram of this node arrive under this address. It does
/// NOT prove that someone gets in unsolicited: for that the
/// mapping would also have to apply to a foreign sender (endpoint-
/// independent filtering), and only whoever has tried it knows that.
/// This function therefore builds NO assurance — it puts a
/// candidate into the record, not a promise.
void setAnnounceAddresses({
  required V41Node node,
  required List<String> dialable,
  required int port,
  void Function(String)? log,
}) {
  // -- IPv6 IS NO SECOND CHOICE (S380, 10.09.2026) ----------------
  //
  // Here stood `if (v4.isEmpty) return;`. This one line made IPv6
  // structurally dependent on IPv4: without a usable IPv4 the
  // function returned BEFORE it even looked at the IPv6, and
  // `advertiseHost` stayed at its default value `127.0.0.1`.
  //
  // MEASURED IN THE FIELD on 10.09.2026 on the owner's phone, WLAN off:
  // two global mobile IPv6 (`2a01:599:...`, `2a01:59f:...`), as the
  // only IPv4 the DS-Lite address `192.0.0.4`, which `isUndialableIpv4`
  // rightly discards. Result: "keine von aussen anwaehlbare Adresse
  // (127.0.0.1)". A device with two public addresses announced
  // loopback.
  //
  // That does not only affect mobile: DS-Lite is in Germany the regular case
  // on cable connections too, and there IPv6 is the ONLY
  // end-to-end family. v3_0 says so for the predecessor line
  // explicitly ("DS-Lite mobile carriers ... provide only global IPv6
  // for end-to-end connectivity").
  //
  // NOW: the first announcement address is the first USABLE one, regardless of
  // family. IPv4 keeps precedence where it exists - it is the
  // more frequent counterpart -, but its absence no longer ends the function.
  // Only when BOTH families yield nothing does it stay at
  // loopback, and then the sentence is also true.
  final v4 = dialable.firstWhere((ip) => !ip.contains(':'), orElse: () => '');
  final v6First =
      dialable.firstWhere((ip) => ip.contains(':'), orElse: () => '');
  final primary = v4.isNotEmpty ? v4 : v6First;
  if (primary.isEmpty) {
    log?.call('V4.1: no non-local address found — the node '
        'announces loopback and is reachable for no one');
    return;
  }
  node.advertiseHost = primary;
  // The remaining families as an addition — §17.3 looks for
  // `v4-only <-> v6-only` for an intermediary with BOTH, and whoever
  // names only one is none.
  // SELECT, DO NOT TAKE EVERYTHING. An entry record carries
  // at most [kMaxEntryAddresses] addresses (format limit, it is
  // signed and travels in one cell). On 28.08. a phone had EIGHT
  // address families; the unfiltered list made `EntryRecord` throw —
  // from within a stream callback of the LAN entry, i.e. uncaught.
  //
  // SELECTION IS BY FAMILY DIVERSITY, not by order: §17.3
  // looks for `v4-only <-> v6-only` calls for an intermediary with BOTH
  // families. Whoever names four IPv4 and no IPv6 is none. Hence
  // first one address per family, only then fill up.
  // EACH WITHOUT THE PRIMARY - it already stands as `advertiseHost`. Until
  // S380 that could only be the IPv4; now it can also be the first IPv6,
  // and then it must come out of the v6 list.
  final v6 =
      dialable.where((ip) => ip.contains(':') && ip != primary).toList();
  final furtherV4 =
      dialable.where((ip) => !ip.contains(':') && ip != primary).toList();
  // THE OBSERVED ONES STAND BEHIND THE FAMILY-DIVERSITY SLOT AND BEFORE THE
  // FURTHER LOCAL ONES. That is calculated, not a matter of taste: there are three
  // additional slots, observation yields at most two (one per
  // family), and the first slot still belongs to the second family —
  // otherwise the node drops out as intermediary for `v4-only <-> v6-only`
  // (§17.3). Thus in the regular case all three concerns fit in at once.
  // Only a FOURTH local address is displaced by an observed one,
  // and that is the right direction: a second address of the same
  // family tells a partner outside the LAN nothing.
  final observed = observedAnnounceAddresses(
      book: node.host.observed, local: dialable, log: log);
  final extra = <EntryAddress>[
    if (v6.isNotEmpty) EntryAddress(v6.first, port),
    ...observed,
    for (final ip in furtherV4) EntryAddress(ip, port),
    for (final ip in v6.skip(1)) EntryAddress(ip, port),
  ];
  // DEDUPLICATED VIA THE ADDRESS BYTES, not via the text. An
  // observed IPv6 comes from 16 bytes, a local one from
  // `NetworkInterface.list`; the same address can appear in two spellings
  // (`fd00::1` against `fd00:0:0:0:0:0:0:1`) and would textually
  // occupy two slots. Of four slots that is one too many.
  final seen = <String>{_addressKey(primary, port)};
  final chosen = <EntryAddress>[];
  for (final e in extra) {
    if (!seen.add(_addressKey(e.host, e.port))) continue;
    chosen.add(e);
    if (chosen.length == kMaxEntryAddresses - 1) break;
  }
  node.advertiseExtra = chosen;
  final outBook = chosen.where(observed.contains).length;
  // $primary, NOT $v4: since the IPv4 is no longer a condition, the
  // announcement address can be an IPv6 — and then this line would report
  // "announce address :8081" about an address that does exist.
  log?.call('V4.1: announce address $primary:$port'
      '${node.advertiseExtra.isEmpty ? '' : ' (+${node.advertiseExtra.length} more famil(y/ies))'}'
      '${outBook == 0 ? '' : ', of which $outBook observed (§17.3)'}');
}

/// The comparison key of an announcement address: the parsed address bytes
/// plus port. If parsing fails, the text applies — then the address
/// is none anyway.
String _addressKey(String host, int port) {
  final a = InternetAddress.tryParse(host);
  return '${a == null ? host : a.rawAddress.join(".")}|$port';
}

/// The own external address per family, as SEVERAL partners have seen it
/// in agreement — and only if it is usable (§17.3).
///
/// ── THE CONTRADICTION IS THE ANSWER, NOT THE ERROR ───────────────
///
/// If two partners see different addresses or ports of the same family,
/// a **symmetric NAT** is present: every counterpart gets its
/// own port mapping. Then the observed address is worthless as an ANNOUNCEMENT
/// — whoever reads it from the record dials a port that
/// never applied to him. At this point §17.3 sets the honest
/// refusal („no call possible") and the port prediction of the
/// punch window; neither belongs in a signed
/// entry record that circulates for days. Here therefore
/// nothing is averaged and nothing guessed: on contradiction the
/// family drops out.
///
/// ── WHAT IS ALSO NOT ANNOUNCED ───────────────────────────────
///
///  * **Loopback and `0.0.0.0`.** Two nodes on one machine
///    observe each other on `127.0.0.1` — unanimously, and worthless for
///    every third party. That is the loopback announcement of 25.08.
///    (S349) on a new path.
///  * **CGNAT, DS-Lite/464XLAT, link-local** (`isUndialableIpv4`, B-26).
///    From these ranges no call comes back, regardless of who
///    observed them.
///  * **IPv6 pseudo-interfaces** (`isTunnelIpv6`, WIN-2).
///  * **The echo of the own LAN.** If a partner in the same
///    segment observes a private address in THE SAME RFC1918 class in which
///    this node itself stands, it says nothing new — it already stands
///    as a local address in the record.
///
/// ── AND WHAT IS VERY MUCH ANNOUNCED ─────────────────────────────────
///
/// A private observation in a DIFFERENT RFC1918 class than the
/// own addresses is a real exit, not an echo. This finding is
/// taken over from V3 and proven in the field there
/// (`NatTraversal.addObservation` on the 3.2.2 return path, branch
/// `s330/ap1-naht-sanieren`; the file does not lie on THIS branch, it
/// was dropped with the CUT of 2026-08-31 — that is why a name stands here
/// and no line number):
/// an Android emulator on `10.0.2.x` leaves the host through its
/// LAN `192.168.x.x`, and exactly this address is the one under which a
/// neighbour reaches it.
///
/// **Limit of the class check, explicitly:** it works on the
/// class (10/8, 172.16/12, 192.168/16), not on the subnet. A
/// real exit from `192.168.178.x` to `192.168.5.x` is thus discarded as
/// echo. That is the harmless one of the two errors — one
/// address too few instead of a wrong one — and it is the same layout
/// that V3 ran.
///
/// [local] are the local addresses currently being announced.
List<EntryAddress> observedAnnounceAddresses({
  required ObservedAddressBook book,
  required List<String> local,
  void Function(String)? log,
}) {
  final out = <EntryAddress>[];
  for (final isV6 in const <bool>[false, true]) {
    final name = isV6 ? 'IPv6' : 'IPv4';
    if (book.disagrees(ipv6: isV6)) {
      log?.call('V4.1 §17.3: $name — the partners see different '
          'external addresses (${book.candidates(ipv6: isV6).join(", ")}). '
          'Symmetric NAT: it is NOT announced.');
      continue;
    }
    final a = book.agreed(ipv6: isV6);
    if (a == null) continue;
    // Rebuilt from the bytes and not taken over from `ObservedAddress.host`:
    // the text builder there writes IPv6 without `::` shortening.
    // Both are valid, but the canonical form compares with
    // what `NetworkInterface.list` supplies.
    final host = InternetAddress.fromRawAddress(a.rawAddress).address;
    final bad = _unfit(host, isV6, local);
    if (bad != null) {
      log?.call('V4.1 §17.3: $name — the observed address $host:${a.port} '
          'is not announced ($bad).');
      continue;
    }
    out.add(EntryAddress(host, a.port));
  }
  return out;
}

/// `null` if the observed address is usable; otherwise the reason in plain text
/// for the log line.
String? _unfit(String host, bool isV6, List<String> local) {
  if (isV6) {
    final a = InternetAddress.tryParse(host);
    if (a == null) return 'not readable';
    if (a.isLoopback) return 'Loopback';
    if (a.isLinkLocal) return 'link-local';
    if (isTunnelIpv6(host)) return 'Pseudointerface (WIN-2)';
    return null;
  }
  if (host.startsWith('127.') || host == '0.0.0.0') return 'Loopback';
  if (isUndialableIpv4(host)) return 'CGNAT/DS-Lite/link-local (B-26)';
  if (isPrivateIpv4(host)) {
    final privateLocal = local.where(isPrivateIpv4).toList();
    // NO private local context does NOT mean „therefore public":
    // without an own private address echo and exit cannot be
    // told apart, and no guessing happens here. V3 also rejected at this
    // point.
    if (privateLocal.isEmpty) return 'private, without own LAN context';
    if (privateLocal.any((l) => samePrivateClass(host, l))) {
      return 'echo of the own LAN';
    }
  }
  return null;
}

/// Updates the announcement when the book knows something new — and announces
/// the record only if it has REALLY changed.
///
/// Returns `true` if the record has changed.
///
/// ── THE UPDATE PATH, AND WHY IT LOOKS THIS WAY (S373) ─────────
///
/// `setzeAnsageadressen` has two callers: start and network change.
/// The book is EMPTY at start — it fills with every handshake that
/// this node opens itself. Without a third path the
/// external address would thus only stand in the record after the next network change,
/// and on a desktop there is none for days.
///
/// **NO TIMER** (work rule #5). The trigger is
/// `ObservedAddressBook.onAgreedChanged`, and it only reports when
/// the UNANIMOUS statement changes — not at every handshake.
///
/// **NO CACHED ADDRESS LIST.** The [resolver] is
/// the same one the node was started with (`V41Runtime.localAddresses`).
/// A copy of the local list held here would go stale after a
/// network change and write the freshly set announcement back to the dead network at the next
/// handshake — the same drift
/// against which `V41Runtime.localAddresses` exists at all.
///
/// **THE ANNOUNCEMENT HANGS ON THE RESULT, not on the event.** If
/// nothing changes, nothing goes on the wire. The SECOND half of
/// propagation needs nothing here at all: the external store compares
/// the fingerprint of the addresses at every pass anyway
/// (`AblageMarke.verlangtAblage`) and stores anew by itself on „address change".
Future<bool> announcementFollowUp({
  required V41Node node,
  required Future<List<String>> Function() resolver,
  required int port,
  void Function(String)? log,
  bool announce = true,
}) async {
  final before = _announcementFingerprint(node);
  final ips = await resolver();
  setAnnounceAddresses(node: node, dialable: ips, port: port, log: log);
  if (_announcementFingerprint(node) == before) return false;
  log?.call('V4.1 §17.3: the entry record carries a new address '
      '(${_announcementFingerprint(node)}) — it is announced. This proves the '
      'outgoing NAT mapping, not incoming reachability.');
  if (announce) node.announceOwnEntry(priority: true);
  return true;
}

/// The addresses of the own record as text — the comparison value of
/// [announcementFollowUp]. Deliberately no hash: the question is „has
/// something changed", and for that the text suffices, without libsodium.
String _announcementFingerprint(V41Node node) =>
    node.ownEntry.addresses.map((a) => '${a.host}:${a.port}').join('|');

/// Starts the V4.1 node. ONCE PER PROCESS, before `attachV41`.
///
/// The `entryTargets` parameter formerly accepted here has been
/// dropped (S351): it carried a V3 handle in from the callers.
/// The unicast targets for step 2 now come exclusively from
/// the own V4.1 supply (`vorratUnicastTargets`, below).
Future<V41Runtime?> startV41Node({
  required NodeKeys keys,
  required int port,
  void Function(String)? log,
  bool? enabled,
  Future<List<String>> Function()? localAddresses,
  String? entryStoreDir,
  // ── THE KEY FOR THE SUPPLY (S362) ─────────────────────────
  //
  // Until S362 this file built its `FileEncryption` WITHOUT a key. That
  // is the legacy path of `file_encryption.dart:23`: a random
  // key in `$entryStoreDir/db.key`, which lies next to the ciphertext
  // and wanders with it into every backup and every disk image.
  // The supply says WHOM this node knows — exactly the information the
  // comment below calls worth protecting.
  //
  // DEVICE-WIDE, not per identity: §21.4 lists supply and peer age
  // as device-bound, which is why they lie next to the node keys.
  // The matching key is thus `HdWallet.deriveSharedFileEncKey(
  // masterSeed)` — the same one under which `device_keys.bin` already lies
  // (`identity_context.dart:407-409`) —, NOT `deriveFileEncKey(seed,
  // hdIndex)`: hanging on an identity-bound key
  // the supply would be unreadable when the active identity changes, although it
  // describes the same neighbourhood of the same node.
  //
  // `null` remains permissible and means „no master seed reachable"
  // (linked device, §7.6.2 „NOT: the seed"). Then the supply falls back to
  // the legacy path — deliberately, because the alternative would be to
  // not save the neighbourhood at all and to start at step 2 at every start.
  // The fallback is logged so that it is not
  // silent.
  Uint8List? entryStoreKey,
  // Wire accounting (§25.5) — passed through to `UdpSocketSet`. See the
  // comment at `V41Node.start`: bare callbacks, so that this layer
  // stays testable without the statistics layer. (Until 2026-09-03 this said
  // „so that the layer boundary to `lib/core/network/` does not fall" — the
  // tree has been empty since the CUT of 2026-08-31, and the collector lies in
  // `lib/core/stats/`.)
  void Function(int bytes)? onWireBytesSent,
  void Function(int bytes)? onWireBytesReceived,
  void Function(int bytes)? onRelayBytes,
}) async {
  final to = enabled ?? Platform.environment['CLEONA_V41'] != '0';
  if (!to) return null;

  // Platform derivation for the total byte cap of the delivery storage
  // (§21.3.3, option C from `S361-VORLAGE-mobilfrist-21-3-3.md`, approved by the
  // owner on 02.09.2026). The same construction as
  // `cleona_service_update.dart:218-222`: `-1` (unlimited) on desktop,
  // otherwise [kMobileSecureStoreCapBytes]. The three periods stay
  // unchanged and platform-independent — only the total storage is
  // capped here.
  final maxStoreBytes =
      (Platform.isAndroid || Platform.isIOS) ? kMobileSecureStoreCapBytes : -1;

  // ── THE BULK QUOTA, AND IT IS NOT A CAP BUT A SWITCH
  //
  // §21.3.3 no. 3 / E-53: „**Desktop installations only**; mobile nodes
  // carry no bulk." Unlike the delivery storage above, a
  // mobile device thus gets here not LESS but NONE — the
  // reasoning is at `BulkCache.forBudgetClass`: a small
  // quota would be worse than none, because it would attract stored items that
  // it immediately evicts again, and would cost mobile data volume for it.
  //
  // The platform derivation stands HERE and not in `lib/core/bulk/`,
  // for the same layer boundary as [maxStoreBytes]: the delivery layer
  // and the bulk lane do not read `Platform.*` (`smoke_link_axis_guard`).
  final bulkCache = bulkCacheForPlatform(
      mobile: Platform.isAndroid || Platform.isIOS);

  final v41 = await V41Node.start(
      port: port,
      keys: keys,
      log: log,
      onWireBytesSent: onWireBytesSent,
      onWireBytesReceived: onWireBytesReceived,
      onRelayBytes: onRelayBytes,
      maxStoreBytes: maxStoreBytes,
      bulkCache: bulkCache);
  v41.advertisePort = port;
  // ── THE INBOUND PROOF (S4/S373) ───────────────────────────────────
  //
  // A node may publish itself on the global board if it
  // can PROVE that it is reachable from outside. One of the two sources
  // for that is an incoming session from an address outside the
  // own network — V4.1's substitute for the V3 port probe, and it costs
  // no additional traffic: what is evaluated is what comes in
  // anyway. The second source is the confirmed port mapping
  // (`V41Node.portMappingConfirmed`, fed at the merge of
  // `s373-portmapping`).
  //
  // ── WHY HERE AND NOT AT `syncPartnersInbound` ─────────────────
  //
  // `syncPartnersInbound` (`v41_node.dart`) would be a PROXY: the
  // number follows from `_partnerKeys(inbound: true)`, and that counts via
  // `LinkChannel.peerPosition`. The interface `LinkChannel`
  // (`lib/core/link/connect.dart`) carries NO address AT ALL — from
  // it „from outside" cannot be read, only „incoming at
  // all". A node with LAN neighbours would thus have a proof that
  // it does not have.
  //
  // The address exists one layer further out: `UdpLinkChannel.peer`
  // and `TcpLinkChannel.peer` are `LinkEndpoint(host, port)`, and for
  // incoming sessions `host` is the SOURCE reported by the operating system
  // (`link_demux.dart` `_handleInit` -> `origin`, `tcp_listener.dart`
  // -> `_address`). Both `accepted` streams are broadcast controllers,
  // so a second listener next to that of the node is possible — without
  // extending the interface and without breaking the twelve test dummies
  // that implement `LinkChannel`.
  //
  // NO FALSE PROOF. The `accepted` stream does not let through the case
  // „simultaneous open, in which this side stepped back"
  // (`link_demux.dart`: there the own completer is
  // fulfilled and returned). And a node behind NAT cannot be dialled from
  // outside at all: its addresses are not on the board after the
  // filter, its mapped port address lands in
  // no `EntryRecord`, and `dialFromEntries` dials exclusively from
  // records.
  v41.host.accepted.listen((ch) => _rememberInbound(v41, ch.peer.host, log));
  v41.tcp.accepted.listen((ch) => _rememberInbound(v41, ch.peer.host, log));

  // ANNOUNCE THE OWN ADDRESS — otherwise the node announces loopback.
  //
  // `V41Node.advertiseHost` is set to `'127.0.0.1'`, and that is right as a
  // default: the delivery layer knows no network and must not know
  // one. So far ONLY the lab program set it
  // (`bin/cleona_v41_node.dart:73`, from a call parameter) — the app
  // never. Measured in the field (25.08., node 1 and 2 in the same segment):
  //
  //     `LAN: Knoten gefunden 127.0.0.1:13143 — Datensatz geprueft`
  //
  // The record was formally fine, only loopback stood in it. Node 1
  // then dialled itself, node 2 stepped back because of the smaller
  // position („the other one dials"), and both waited. Result:
  // zero sessions, `readiness` stayed at `searching`, and `V41Node.send`
  // rejected EVERY message with `notReady` — before the mode branch.
  // The nodes thus found each other the whole time and just could not
  // reach each other.
  //
  // ── WHERE THE LIST COMES FROM (S350) ──────────────────────────────────
  //
  // From `local_addresses.dart`, no longer from `Transport.getAllLocalIps()`.
  // The V3 version hung, via `lib/core/network/transport.dart`, the
  // entire V3 transport layer onto every process that starts a V4.1 node
  // — the bug D-5 that `smoke_link_io_milestone` section 5
  // measures — and also answered a different question („which IPs do I
  // have" instead of „under which am I dialable"), which had to be
  // corrected here already before (B-26). Reasoning in full in the header
  // of `local_addresses.dart`.
  //
  // [localAddresses] lets the caller pass its own resolver
  // — for tests, and for the day on which daemon and
  // in-process start pass along their shared address source instead of letting it be
  // determined here.
  // ONE resolver, and it is needed three times: here, at the edge of the
  // address book right below, and in the network change via
  // `V41Runtime.localAddresses`. Two expressions would be two sources —
  // a test that passes its own resolver at start
  // would get the real one at the edge and thus the interfaces of the
  // test machine.
  final resolver = localAddresses ?? dialableLocalAddresses;
  final ownIps = await resolver();

  setAnnounceAddresses(
      node: v41, dialable: ownIps, port: port, log: log);

  // ── THE EXTERNAL ADDRESS LEARNED LATER (§17.3, S373) ───────────────
  //
  // The call above runs with an EMPTY address book: it only fills
  // from flight 2 of every handshake that this node opens itself. Without
  // this edge the own external address would only stand in the record after the next
  // network change.
  //
  // LIMIT THAT CANNOT BE CLOSED HERE: a node that is only
  // DIALLED learns nothing at all. The mirror stands in flight 2, and
  // it is reported solely in `LinkDemux._claimAsFlight2` — i.e. at the
  // INITIATOR. Whoever never dials has an empty book and keeps announcing
  // only its local addresses. Changing that would mean extending the handshake by
  // a mirror in flight 3; that is a protocol change
  // and does not belong in this seam.
  //
  // WITHOUT `await` AND WITH OWN try/catch IN THE BODY. The edge is
  // synchronous (it happens in the receive path), the update needs the
  // resolver and is thus asynchronous. A `try` AROUND `unawaited(...)`
  // catches nothing in Dart (S351/B-2) — that is why the catch is inside.
  var followUpRuns = false;
  var followUpOpen = false;
  Future<void> followUp() async {
    if (followUpRuns) {
      // Arrived during a run: do NOT discard. The last
      // change is the one that must stand in the record.
      followUpOpen = true;
      return;
    }
    followUpRuns = true;
    try {
      do {
        followUpOpen = false;
        await announcementFollowUp(
            node: v41, resolver: resolver, port: port, log: log);
      } while (followUpOpen);
    } catch (e) {
      log?.call('V4.1 §17.3: the announcement could not be updated ($e) — '
          'the record stays at the last valid state.');
    } finally {
      followUpRuns = false;
    }
  }

  v41.host.observed.onAgreedChanged = () => unawaited(followUp());

  // ── THE PORT MAPPING (§23.4, §25.9, E-64; gap G-12) ───────────
  //
  // The line above announces under which LOCAL address this
  // node can be dialled. Behind a NAT that is usable exactly as far
  // as the own segment reaches: a stranger can reach this
  // node only as long as own outgoing traffic keeps a
  // hole open. A confirmed mapping on the other hand yields an
  // address that can be dialled without prior effort — §23.4 calls that „it
  // turns the node into a point of contact for others", §26.6.5 lists
  // „public IPv4 (bootstrap, port forwarding)" as carrier of the
  // binary distribution, and E-64 presupposes a `publicPort` assigned by UPnP-IGD
  // for the invitation link. The mapping was thus
  // never architecturally abolished, only deleted along with `lib/core/network/`
  // (CUT, 31.08.); the owner approved bringing it back on
  // 07.09.2026.
  //
  // NOT AWAITED. A detection run can in the worst case take
  // eight and a half minutes (RFC 6886 backoff), and no node start
  // may hang on it. The result comes via the event stream and
  // enters itself into `V41Node.advertiseMapped`
  // (`port_map_wiring.dart`).
  final portMapping = PortMapBinding.bind(node: v41, port: port, log: log);
  unawaited(portMapping.mapper.start());

  // ── STEP 1 OF THE ENTRY CASCADE: THE STORED SUPPLY ─────────
  //
  // The app forgot its neighbourhood at EVERY restart. `EntryStore`
  // has `loadJson`/`toJson`, `V41Node` has `onEntriesChanged` — in `lib/`
  // no one called that. Only the lab program
  // (`bin/cleona_v41_node.dart:84-97`) loaded at start and saved every
  // 30 s. The application thus started with ZERO records, even if
  // it knew a hundred yesterday.
  //
  // What that costs is in the cascade itself: step 1 IS the
  // stored supply. Without it every app start begins at step 2
  // (LAN call) or 3 (external rendezvous) — and if the rendezvous is
  // blocked and no neighbour happens to answer, the node does not get
  // in, although it KNOWS twenty paths. Exactly this situation the
  // phone had on 28.08.
  //
  // ENCRYPTED, and not out of habit: the supply says WHOM this
  // node knows. That is its neighbourhood, and it would otherwise lie in
  // plaintext on disk. §21.4 lists it as device-bound, not
  // identity-bound — that is why it lies next to the node keys
  // and not in the identity directory.
  //
  // SAVING HANGS ON A CLOCK, and that is permissible here: it is
  // a DISK rhythm, not egress. Invariant 1 protects against
  // a second cycle becoming visible on the WIRE; what the node writes to
  // its own disk no one sees from outside. Debounced,
  // so that a burst of learned records does not trigger one write per
  // record.
  Timer? poolTimer;
  if (entryStoreDir != null) {
    final path = '$entryStoreDir/v41_entries.json';
    if (entryStoreKey == null) {
      log?.call('V4.1: pool and peer age lie under the legacy '
          'random key db.key — no master seed reachable '
          '(linked device?). The key thus lies next to the '
          'ciphertext and does not protect against a disk image.');
    }
    final enc = FileEncryption(baseDir: entryStoreDir, key: entryStoreKey);
    try {
      final present = enc.readJsonFile(path);
      if (present != null) {
        v41.entries.loadJson(present);
        log?.call('V4.1: pool loaded — ${v41.entries.size} '
            'entry record(s) from the last run');
      }
    } catch (e) {
      // An unreadable supply is no start error — the node then falls
      // back to step 2/3, exactly as at the very first start.
      log?.call('V4.1: pool not readable ($e) — cold start via LAN '
          'and external rendezvous');
    }
    // ── AND THE AGE OF THE PEERS (§10.3, first condition) ─────────────
    //
    // „`firstSeenEpoch` has to survive a daemon restart. Held only in
    // memory, every peer is 'fresh' after every restart and the node
    // finds no responsible relay for ten days." Until S354 the
    // register lived only in memory — and the failure was invisible, because the
    // gate lets through below `eligibleCount >= R` anyway: after
    // every restart it stood at 0, the gate was open, and it looked
    // like „running".
    //
    // OWN FILE, not mixed into the supply: the one is an
    // address list with expiry time, the other an observation over
    // time. A supply that discards expired items on loading must not
    // discard the age along with them — exactly then the peer would run in anew.
    final altersPath = '$entryStoreDir/v41_ages.json';
    try {
      final age = enc.readJsonFile(altersPath);
      if (age != null) {
        // WRONG VERSION MEANS: DO NOT READ (S376, P4-2). A
        // v1 file carries a first-seen date without a single
        // proof behind it — exactly the number the finding rejected.
        // Continuing to compute with it would rescue the attack via the
        // format change.
        if (v41.eligibility.loadJson(age)) {
          log?.call('V4.1: age loaded — ${v41.eligibility.known} '
              'position(s), of which '
              '${v41.eligibility.eligibleCount(nodeEpochNow())} eligible');
        } else {
          log?.call('V4.1: age file in foreign format (expected v'
              '${EligibilityRegistry.formatVersion}) — the peers are learned '  // V3-TOUCH-OK: V4.1's own format version (tagline/), not a V3 format — foreign versions are discarded, not migrated (owner 08.09.2026)
              'anew');
        }
      }
    } catch (e) {
      log?.call('V4.1: age not readable ($e) — the peers run in anew');
    }

    var dirty = false;
    v41.onEntriesChanged = () => dirty = true;
    // SINCE S376 THE AGE HAS ITS OWN DIRTY MARK. Until then it hung
    // on the supply, because it changed exactly when the
    // supply changed too (`_learn` ran at `remember`). A proof from a
    // storing receipt however does not touch the supply — without this line
    // it would get lost at the next restart.
    v41.eligibility.onChanged = () => dirty = true;
    poolTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!dirty) return;
      dirty = false;
      try {
        enc.writeJsonFile(path, v41.entries.toJson());
      } catch (e) {
        log?.call('V4.1: pool cannot be saved ($e)');
      }
      // THE AGE HANGS ON THE SAME CYCLE — but on its OWN
      // dirty mark (see above): since S376 it can change without
      // the supply moving.
      try {
        v41.eligibility.expire(nodeEpochNow());
        enc.writeJsonFile(altersPath, v41.eligibility.toJson());
      } catch (e) {
        log?.call('V4.1: age cannot be saved ($e)');
      }
    });
  } else {
    log?.call('V4.1: no pool directory passed — the '
        'neighbourhood does not survive this process');
  }

  v41.run();

  // ── STEP 3 OF THE ENTRY CASCADE: THE EXTERNAL RENDEZVOUS (§11.3) ──
  //
  // WHY IT IS INDISPENSABLE, and not just a third option. Steps
  // 1 and 2 both presuppose that an ADDRESS is still right:
  // step 1 the stored supply, step 2 the local segment. Behind
  // CGNAT and in mobile networks addresses change constantly, and a
  // broadcast does not even get through in a guest WLAN — on 28.08.
  // measured in the field: the phone saw **zero** calls in 60 s and therefore had
  // zero sessions. An entry that relies on valid IPs
  // does not hold exactly when one needs it.
  //
  // The external rendezvous is the only way in that presupposes **no**
  // previous address: both sides derive a tag from a
  // channel constant and the day and store their
  // encrypted entry record under it.
  //
  // EVERYTHING WAS BUILT — `ColdStart`, `ExternalEntrySource`,
  // `NostrRendezvous`, `secp256k1_schnorr`. What was missing was the call:
  // `ColdStart` had in `lib/` **not a single caller**. The same
  // class of bug as with the receiving side (S349) and the entry
  // cascade (S347): both halves complete, the seam not laid.
  //
  // IT RUNS ALONGSIDE. A network service must not hold up the node start;
  // whoever waits here also delays the LAN entry, which
  // might hold immediately.
  // Step 2 of the entry cascade. WITHOUT IT THE LAYER IS DEAD: no call,
  // no partner, `readiness` stays at `searching`, and `V41Node.send`
  // rejects EVERY message — before the mode branch, Speed as well as Secure.
  // Exactly so it stood in the field until 2026-08-22; the wiring lay solely in the
  // lab program. If the start fails here (port taken, no broadcast
  // permitted), the service does NOT die — it then keeps running without LAN entry,
  // and that is in the log instead of staying silent.
  //
  // WHERE THE ADDITIONAL TARGETS NOW COME FROM (S351, `smoke_seam_node_
  // member_guard`). Until here `entryTargets` (passed in from `main.dart`/
  // `service_daemon.dart`) accessed `node.routingTable.allPeers`
  // — the V3 node, exactly the layer this migration removes.
  // The reason was necessity: before `95b2b104` V4.1 had NOTHING of its own across
  // a restart, but the V3 node already knew peers (via its
  // own unicast-capable bootstrap). Since the supply (above, step 1)
  // `v41.entries` holds exactly the same information — signed
  // `EntryRecord`s WITH addresses — and is moreover the set that
  // `dialFromEntries` (step 3) already searches for the same purpose
  // anyway. The V3 handle was thus no longer needed, only not yet
  // removed.
  final entry = await _startLanEntryFromPool(v41, keys, port, log);

  // ── AND NOW THE CASCADE, ALL FIVE STEPS, IN ORDER ────
  //
  // IT STANDS HERE AND NOT FURTHER UP, and that is the point of the
  // rearrangement: step 2 (the LAN entry) must be RUNNING before the cascade
  // can ask it. Until S356 the external block ran BEFORE `startLanEntry`,
  // alongside and as the only step — the cascade thus could not wait for the LAN entry
  // at all, and did not do so either.
  //
  // WHAT WAS WRONG ABOUT THAT, in three sentences. First, the report always said
  // „one step, zero skipped" — indistinguishable from
  // a complete cascade that found nothing. Second, the
  // external rendezvous ran at EVERY start, even with a full supply and
  // an answering neighbour, although §11.3 and the header of `ColdStart`
  // explicitly say that it ends at the first hit („every
  // further source costs and reveals something"; the price stands as
  // B-24/RL-13). Third, the step that §11.3 calls „the normal way
  // in" was missing completely.
  //
  // ALONGSIDE STAYS ALONGSIDE. A network service must not hold up the node start;
  // whoever waits here delays everything else with it.
  unawaited(_cascadeRun(
    v41: v41,
    entry: entry,
    relayBaseDir: entryStoreDir,
    depositKey: entryStoreKey,
    log: log,
  ));

  log?.call('V4.1 node running (port $port)');
  return (
    node: v41,
    lanEntry: entry,
    entryPersist: poolTimer,
    localAddresses: resolver,
    portMapping: portMapping,
  );
}

/// The channel under which the external rendezvous derives its tag.
String get _appointmentChannel =>
    activeNetworkChannel == NetworkChannel.live ? 'cleona-live' : 'cleona-beta';

/// Builds the external source with a configured relay list and a real
/// log target.
///
/// TWO THINGS THAT WERE MISSING BEFORE. First, `NostrProvider()` stood without
/// arguments — the relay list was a `const` in the code, without any way
/// to change it except a new build (`RendezvousRelays` fixes that
/// without making the selection itself). Second, `profileDir` was missing, and
/// thus the lines of the substrate landed in NO log file — in the
/// lab run on 30.08. verbatim:
///
///     `[WARN] [clogger] Modul "nostr" hat keinen Log-Buffer`
///     `(profileDir=null) — seine Zeilen landen in KEINEM Logfile`
///
/// Precisely the step that brings a node in when nothing else
/// holds was thus not readable afterwards in the field.
ExternalEntrySource _externalSource(String? baseDir, void Function(String)? log) {
  final relay = RendezvousRelays.forNode(baseDir,
      onNote: (m) => log?.call('V4.1 $m'));
  return ExternalEntrySource(
    rendezvous: NostrRendezvous(
        NostrProvider(relays: relay, profileDir: baseDir)),
    channel: _appointmentChannel,
  );
}

/// How many DIFFERENT paths suffice to stop.
///
/// Three, as before — but now three NODES instead of three records. In the
/// lab run on 30.08. the external rendezvous delivered five clumps for
/// a single node (5 of 7 relays had accepted the same stored item).
/// With `bisher.length >= 3` the cascade would have stopped there and believed
/// it knew three paths.
const int _enoughRoutes = 3;

/// When the cascade stops asking.
///
/// ── THE FIRST CONDITION IS THE ACTUAL ONE (§11.3) ──────────────────
///
/// The header of `ColdStart` says: „whoever is already IN need not
/// knock any more." One is in with a SESSION, not with a record —
/// and exactly that can be read here instead of estimated. The
/// LAN entry dials by itself as soon as it hears someone
/// (`lan_entry_wiring.dart`, `unawaited(node.dialRecord(r))` — until S373
/// it said `node.connect(r.host, r.port)` there, i.e. only the first of up
/// to four addresses); so if
/// a partner arises during step 2, the node is in the network before the
/// cascade would even be at step 5.
///
/// WHY THE SECOND CONDITION STAYS NEVERTHELESS. A dial may still be
/// running when the step returns. Three known paths are then the
/// substitute proof: more than enough to make it on its own, and
/// the rest comes via the set request in the network (`requestEntrySet`).
///
/// MEASURED IN THE LAB why it must NOT be the record count alone:
/// with `distinctPositionsOf(...) >= 3` as the only condition, on
/// 30.08. **all four** nodes asked the external rendezvous, although each
/// already had a partner via the segment — step 2 delivered in
/// its window only one or two records, because the other answers
/// only trickled in seconds later.
///
/// ── A PARTNER IN THE OWN BLOCK IS NOT „IN" (S380, 10.09.2026) ─
///
/// Here stood `v41.partnerCount > 0` as the first condition. It measures
/// ACQUAINTANCE, and §22.7 explicitly builds readiness on
/// „evidence, not acquaintance": `ready` demands TWO relays from
/// DIFFERENT network blocks (`Partition`, `/24` and `/48`).
///
/// MEASURED IN THE FIELD on 10.09.2026, Node1 and Node2 in
/// `192.168.10.0/24`: both found each other via step 2, both thus had
/// `partnerCount == 1`, and both aborted the cascade exactly there
/// — before step 5. The report says it word for word:
///
///     `V4.1 Kaskade: store:2/2 lan:0/0 — 2 verschiedene(r) Knoten,`
///     `0 neu, 0 Stufe(n) uebersprungen`
///
/// Two steps of five, NONE skipped — they were never asked.
/// At the same time the bootstrap lay on the board with public
/// IPv4 and IPv6, i.e. the second block both needed. They
/// only learned about it ten minutes later, from the cycle of
/// `_appointmentMaintain` — and until then `searching`/
/// `connecting` blocked the Secure path.
///
/// NOW BLOCKS COUNT, NOT PARTNERS. Stopping happens as soon as two
/// independent blocks are known — exactly the number that `ready`
/// demands. The reason of the old comment stays preserved: a node
/// whose supply already knows two blocks (the regular case after the first
/// run) still stops after step 1 and knocks nowhere.
///
/// THE SECOND CONDITION STAYS unchanged: three different NODES
/// are enough even if they sit in one block — more than enough
/// to make it on its own.
/// Visible for the gate, like `PortMapper.generation`: an
/// abort condition that would only be measurable via its effect in the running network
/// is no guard — it would sometimes be green and sometimes red.
bool enoughForEntry(List<EntryRecord> until) =>
    distinctPartitionsOf(until) >= _enoughBlocks ||
    distinctPositionsOf(until) >= _enoughRoutes;

/// How many INDEPENDENT network blocks suffice to stop.
///
/// Two — the same number that §22.7.1 demands for `ready`. Fewer would be
/// the situation out of which Node1 and Node2 did not get on 10.09.2026;
/// demanding more would mean going to step 5 every time in a young network.
const int _enoughBlocks = 2;

/// Runs the cascade and books what it brought.
Future<void> _cascadeRun({
  required V41Node v41,
  required LanEntryHandle? entry,
  required String? relayBaseDir,
  // ── THE SAME DEVICE-WIDE KEY AS FOR THE SUPPLY (S362) ────
  //
  // The storing mark is of the same kind as `v41_entries.json`: it
  // describes what THIS NODE last published, not an
  // identity. It came in with the Nostr rebuild, while the
  // keyless `FileEncryption` in the same file was just being removed
  // — two work trees that did not see each other. The merge brought
  // both together, and `smoke_device_scoped_key_guard` caught it:
  // 2 instead of 0 keyless constructions.
  Uint8List? depositKey,
  void Function(String)? log,
}) async {
  ExternalEntrySource? isExternal;
  try {
    isExternal = _externalSource(relayBaseDir, log);

    final cascade = ColdStart(sources: [
      // Step 1 — what was already there. Costs nothing, involves no one.
      StoreEntrySource(() => v41.entries.dialCandidates()),

      // Step 2 — the local segment. `startLanEntry` calls once immediately
      // at start (`rufen()` before the timer), this step triggers
      // the same call once more and then watches what comes in.
      DirectedEntrySource(
        kind: EntrySourceKind.lan,
        snapshot: () => v41.entries.all(),
        usable: () => entry != null,
        nudge: () => entry?.service.announce(
            const ['255.255.255.255', kLanEntryMulticastV4]),
      ),

      // Step 3 — a person. The entry hints from a
      // ContactSeed (§15) are asked DIRECTLY: the call alone would
      // make us known to the host, not the other way round.
      DirectedEntrySource(
        kind: EntrySourceKind.person,
        snapshot: () => v41.entries.all(),
        usable: () => entry != null && !personEntryHints.isEmpty,
        // ── ON THE PORT OF THE HINT, NOT ON 41340 (S372) ────
        //
        // `askHints` sends the record request to exactly the port
        // that the hint names — the V4.1 data port of the other side.
        // Until S372 it went to the fixed `kLanEntryPort`, and the host
        // had to bind the wildcard for it: a second fixed point,
        // switchable off network-wide with one block rule (RL-14), and every
        // responder recognisable as a Cleona node.
        //
        // A host that for another reason MUST have a fixed port
        // — the bootstrap behind a firewall rule — needs
        // no special case for that: its port stands in its
        // ContactSeed, and exactly that one is used.
        nudge: () => entry?.askHints(personEntryHints.hints),
      ),

      // Step 4 — the doors of the network. NOT BUILT, and that stands here
      // explicitly instead of being missing: a cascade silently missing a step
      // looks like a complete one that found nothing.
      // E-52 names the condition under which it holds at all
      // (>= 50 nodes with >= 30 days of stable reachability over 8
      // weeks, plus family diversity) — that is not measurable today and
      // would not be fulfilled anyway.
      const UnbuiltSource(EntrySourceKind.doors,
          'public door service (E-52) not built'),

      // Step 5 — the external rendezvous. The anchor.
      isExternal,
    ]);

    final result = await cascade.run(enough: enoughForEntry);

    var fresh = 0;
    for (final r in result.records) {
      // The source stands at the record, because `EntryCache` keeps a quota per
      // origin. Which step brought it the cascade knows —
      // here only the collected state remains.
      if (v41.entries.remember(r, source: 'kaskade')) fresh++;
    }
    final report = result.steps
        .map((s) => '${s.kind.name}:${s.accepted}/${s.found}')
        .join(' ');
    log?.call('V4.1 cascade: $report — ${result.distinctPositions} '
        'distinct node(s), $fresh new, '
        '${result.skipped} step(s) skipped');

    // AND NOW DIAL. A filled supply is not yet a
    // connection — on 28.08. the phone fetched 18 records and
    // still had zero sessions, because dialling lay solely in the LAN path
    // (B-28).
    final dialed = await v41.dialFromEntries();
    if (dialed > 0) {
      log?.call('V4.1 cascade: $dialed node(s) dialed');
    }
  } catch (e) {
    // A network service that is not reachable is no start error.
    log?.call('V4.1 cascade: did not run through completely ($e)');
  }

  // ── AND THE OWN RECORD IN, AGAIN AND AGAIN ──────────────────
  //
  // E-63 stays preserved („being reachable and publishing oneself are
  // two decisions"): only whoever makes himself known anyway
  // is published.
  if (isExternal != null) {
    unawaited(_appointmentMaintain(
        v41: v41,
        isExternal: isExternal,
        relayBaseDir: relayBaseDir,
        depositKey: depositKey,
        log: log));
  }
}

/// Keeps the external rendezvous alive — the storing AND the fetching.
///
/// ── TWO DEFECTS THAT COINCIDE HERE (S356) ──────────────────────
///
/// **First: the own record was stored exactly ONCE.**
/// `publishOwn` had a single caller in `lib/`, in the start block. The
/// tag however moves DAILY (`ExternalTag.forDay`, `dayOf` = UTC day) —
/// exactly that is what it is for, „so that an observer of the substrate cannot follow a
/// single tag over months". A node running past
/// midnight UTC then lay under YESTERDAY's tag
/// and was invisible to every new searcher. The same figure as the
/// liveness epoch that S354 fixed at the same place: „whoever runs longer
/// than an epoch without a new session becomes invisible to new
/// senders".
///
/// **Second: the fetch ran exactly ONCE.** The start block was
/// `unawaited` and without repetition. If the app starts before the WLAN
/// is connected — the regular case on mobile devices —, the only
/// attempt fails, and the node does not try again until restart.
/// The redial from S354 (`dialFromEntries` in the slot cycle) does NOT help against that:
/// it dials from the supply, and in the cold case that is empty.
///
/// WHEN FOLLOW-UP HAPPENS. Only if this node has too FEW partners.
/// Whoever stands in the network does not need the rendezvous — it costs a
/// fixed point and is enumerable (B-24/RL-13). The cycle is deliberately
/// coarse: a network service that does not answer should not be asked
/// every minute.
const Duration _appointmentTick = Duration(minutes: 10);

/// Stores the own entry record when the tag of the day
/// has moved. Returns the day under which it now lies.
///
/// OWN FUNCTION instead of a closure in the body, for two reasons.
/// First, it is testable this way without a running loop. Second,
/// `smoke_tagline_lab_only_guard` recognises declarations by two spaces of
/// indentation — a closure in the function body looks to it like
/// a component of the layer without a consumer, and it promptly
/// reported it. The underscore tells it that it is none.
Future<DepositMark> _depositIfNecessary({
  required V41Node v41,
  required ExternalEntrySource isExternal,
  required DepositMark last,
  _DeclineMemory? decline,
  void Function(String)? log,
}) async {
  // WHAT MAY GO ON THE BOARD IS DECIDED BY [brettEntscheid] — until
  // S373 here stood `final eigen = v41.ownEntry;`, i.e. the record for ALL paths.
  final decision = brettDecision(v41);
  final own = decision.record;
  if (own == null) {
    decline?.report(decision.reason, log);
    return last;
  }
  decline?.report(null, log);
  final today = ExternalTag.dayOf(DateTime.now().toUtc());
  // VIA THE FILTERED record, not via `ownEntry`: otherwise every
  // change of a PRIVATE address — DHCP renewal, second WLAN —
  // would trigger a re-storing, although nothing changes on the board.
  final fingerprint = DepositMark.fingerprintFrom(own);
  if (!last.demandsDeposit(today, fingerprint)) return last;
  await isExternal.publishOwn(own);
  final reason = last.tag != today ? 'Tageswechsel' : 'Adresswechsel';
  log?.call('V4.1 rendezvous: own entry record stored '
      '($reason, mark of the day $today, ${decision.reason}, '
      '${own.addresses.map((a) => a.host).join(', ')})');
  return DepositMark(tag: today, addresses: fingerprint);
}

/// Enters an incoming session as reachability proof (S4/S373).
///
/// `normalizeIp` is mandatory and not decoration: a dual-stack socket reports
/// IPv4 counterparts in the mapped form `::ffff:a.b.c.d`, and
/// [isExternallyReachable] rightly discards that — on the OWN
/// interface it is a Windows pseudo-interface (WIN-2). As
/// SOURCE ADDRESS the same form is a valid IPv4 partner. Without the
/// conversion every proof that comes in over IPv4 would fail.
void _rememberInbound(V41Node v41, String source, void Function(String)? log) {
  if (v41.externalInboundProven) return;
  if (!isExternallyReachable(IpAddressClass.normalizeIp(source))) return;
  v41.externalInboundProven = true;
  log?.call('V4.1: inbound evidence — incoming session from $source, i.e. from '
      'outside the own network. This node may publish itself on the '
      'global entry board (§11.3).');
}

/// How long a record is valid on the GLOBAL board.
///
/// ── TWO DAYS, AND THEY ARE NOT GRABBED FROM THE AIR ────────────────────────
///
/// It is exactly the fetch window of the board: `ExternalEntrySource` queries
/// `daysBack = 2` day tags (`external_entry.dart`), so an older
/// record is not found there at all any more. A longer
/// validity would have no reader.
///
/// ── AND IT IS THE PROTECTION OF THE COMPLETE RECORD ──────────
///
/// `EntryCache.remember` records: „THE YOUNGER WINS, ALWAYS", and
/// `expiryMs` is compared (`entry_record.dart`). The board record
/// is a true SUBSET of `ownEntry` — it does not carry the private
/// addresses. With the same validity of seven days it would
/// displace the complete record at the receiver as soon as it is
/// issued later (and it is issued anew daily). What that
/// costs is in `V41Node.dialFromEntries`: there `r.host` is
/// dialled, i.e. the FIRST address. A LAN neighbour would thus lose
/// exactly the private address under which alone it reaches the node.
///
/// With two days against seven `ownEntry` wins every comparison, and the
/// board record only holds where there is no other one — at
/// cold start, which is what it is for.
/// ── ONE DAY, NOT TWO (owner, 07.09.2026) ──────────────────────
///
/// The reasoning is the durability of the described thing, not that
/// of the record: **a public IP is usually valid for 24 h.** An
/// entry that stands longer than the address it names is, after the
/// change, not invalid but WRONG — and every reader dials it.
/// Measured on 07.09.2026: of 50 dials on .201, 40 failed,
/// on the emulator 247 of 272, consistently against addresses that had once
/// been right.
///
/// THE RENEWAL CYCLE FITS WITH IT, without anything being added:
/// `_ablegenWennNoetig` stores anew at DAY CHANGE or ADDRESS CHANGE
/// (`AblageMarke.verlangtAblage`). The renewal thus falls at
/// UTC midnight, the validity runs from the time of issue —
/// so there is always an overlap, never a gap.
///
/// THE OLD REASONING STAYS FULFILLED. The two days stood here
/// so that `ownEntry` (seven days) wins every comparison at the receiver
/// and a LAN neighbour does not lose the private address under which it
/// alone is reachable. One day against seven enlarges this
/// gap, it does not shrink it.
///
/// WHAT IT COSTS, named instead of hidden: a node that was off for longer than
/// one day finds its own entry expired
/// and can only be found via other paths until its next own storing.
/// That is the knowingly paid price for the board becoming
/// honest faster.
const Duration kBrettValidity = Duration(days: 1);

/// What of this node may go onto the GLOBAL entry board.
///
/// [record] is `null` if NOTHING may be stored; [reason] is
/// always set and in both cases meant for the log line.
final class BrettDecision {
  final EntryRecord? record;
  final String reason;
  const BrettDecision(this.record, this.reason);
}

/// The decision about storing on the global board (§11.3).
///
/// ── THE FINDING (06.09.2026, S373) ──────────────────────────────────
///
/// A `resolve` on the public board of the channel `cleona-beta`
/// delivered 17 records: 30 private IPv4, ZERO public IPv4, 3
/// global IPv6, 2 ULA. **15 of the 17 carried no address dialable from
/// outside.** The path there went via `V41Node.ownEntry`, and that MUST
/// carry the private ones — step 2 of the cascade, the LAN call, lives on them.
/// Two questions that the code treated as one.
///
/// §11.3 demands the filter normatively: „every **externally reachable**
/// node publishes an encrypted endpoint record". It was an
/// unimplemented rule, not a new idea — the siblings have had it
/// for a long time (`binary_rendezvous_manager.dart`,
/// `first_contact_rendezvous_manager.dart`, `invite_link_service.dart`),
/// and V3.2.2 had it too (`infra_rendezvous_manager.dart`).
///
/// ── TWO CONDITIONS, NOT ONE ───────────────────────────────────
///
///  1. **The addresses.** Only what is dialable from outside goes onto the board
///     ([isExternallyReachable]). If nothing remains, NOTHING is
///     stored — the same stance as the sibling, which returns on an empty
///     list instead of producing an empty stored item.
///
///     **ADDITIONALLY since S379 (owner, 09.09.2026): one
///     host candidate per family.** If a family has no address dialable from
///     outside, its private one comes along — never alone, always next to
///     at least one dialable one. Without that a
///     dual-stack node behind NAT44 drops out on the board as v6-only and
///     can no longer mediate for `v4-only <-> v6-only` (§17.3, §25).
///     The price lies on the dialling side and is paid
///     there (`dialAddressOrder`: private address only with the same
///     RFC1918 class).
///  2. **The proof.** A global IPv6 on the interface is no
///     proof of reachability; most home routers block incoming
///     IPv6 by default, and exactly three of those lay on the board. Reachability
///     is proven by a **confirmed port mapping**
///     (`V41Node.portMappingConfirmed` — the router has agreed) OR
///     by an **incoming session from outside**
///     (`V41Node.externalInboundProven` — it demonstrably worked).
///
///     TWO SOURCES, ONE RULE, NO SPECIAL CASE. It applies equally to every
///     node; a bootstrap is a node like any other
///     (owner, 07.09.2026). Until then an operator switch
///     (`--public-ip`) stood here as a third condition — it was a crutch for
///     exactly the case that the port mapping now solves itself, and is
///     out without replacement.
///
///     Without the first source there would be a loop: a freshly mapped
///     node has no inbound, does not publish, is not
///     dialled, never gets an inbound.
///
/// AN OWN RECORD IS ISSUED, not `ownEntry` with fewer
/// addresses: the record is signed over its addresses, a
/// subsequent truncation would no longer be a valid signature. The shorter
/// validity ([kBrettValidity]) ensures that this second
/// record does not displace the complete one at any receiver.
BrettDecision brettDecision(V41Node v41, {DateTime? now}) {
  // E-63: being reachable and publishing oneself are two
  // decisions. Whoever does not make himself known does not store anything either.
  if (!v41.publishEntry || v41.advertisePort <= 0) {
    return const BrettDecision(null, 'Announcement held back (E-63)');
  }
  final all = <EntryAddress>[
    EntryAddress(v41.advertiseHost, v41.advertisePort),
    // ── THE MAPPED ADDRESS BELONGS ON THE BOARD (S380, 10.09.2026) ─
    //
    // It was missing here, and that was the most expensive single bug of the day.
    // `V41Node.advertiseMapped` is an OWN field next to `advertiseHost`
    // and `advertiseExtra` — written by `port_map_wiring.dart` when
    // the router confirms a mapping. `V41Node.ownEntry` reads all
    // three fields (`v41_node.dart:1112-1119`), `ownDialHosts` reads all
    // three (`entry_record.dart:208-216`) — this function read only two.
    //
    // CONSEQUENCE, measured in the field: the bootstrap behind the FRITZ!Box has
    // no public IPv4 on an interface. Its only
    // public IPv4 IS the mapped one (188.174.130.132:8081). It
    // stood in `advertiseMapped` — and never got onto the board. The node
    // published itself as v6-only, and the three test nodes in
    // `192.168.10.0/24` without global IPv6 did not find it: "keine
    // anwaehlbare Adresse in [<ip6>]:8081 — eigene Familien: v4".
    //
    // The reasoning line below names "Portabbildung bestaetigt" as the
    // first of the three paths from §11.3. Without this line exactly
    // this path could never carry the storing — it only proved what it did not
    // contribute.
    ?v41.advertiseMapped,
    ...v41.advertiseExtra,
  ];
  // THE ADDRESS IS JUDGED, NOT ITS ORIGIN. An external address obtained
  // via port mapping and one observed via §17.3
  // therefore get through without a special case as soon as they stand in the
  // announcement addresses — they are public. A function that asked about
  // the source would have to be updated with every new path.
  final outside = <EntryAddress>[
    for (final a in all)
      if (isExternallyReachable(a.host)) a,
  ].toList();
  if (outside.isEmpty) {
    return BrettDecision(
        null,
        'no address dialable from outside '
        '(${all.map((a) => a.host).join(', ')})');
  }

  // ── THE BOARD CARRIES ONLY PUBLIC ADDRESSES (§11.3, S380) ──────
  //
  // Two things stood here, and both were dropped with the owner approval of
  // 10.09.2026:
  //
  // 1. A PRIVATE HOST CANDIDATE PER FAMILY (S379). It came in because
  //    the bootstrap stood on the board as v6-only and the nodes in
  //    `192.168.10.0/24` without global IPv6 did not reach it — two
  //    islands instead of one network. The path was wrong: §11.3 says
  //    „never on the public board", and a private address is by definition
  //    not reachable from outside. The reason drops away with
  //    point 2 — the bootstrap now stands on the board with its PUBLIC
  //    IPv4, and exactly that is what those nodes reach.
  //
  // 2. THE ADDITIONAL PROOF CHECK. It demanded a confirmed
  //    port mapping or an incoming session from outside. Since S380 §11.3
  //    knows THREE paths that make an address announceable —
  //    port mapping, incoming session, or an address observed unanimously by all partners
  //    (§17.3) —, and all three end in
  //    exactly what is checked here anyway: a public
  //    address in the announcement. A second check next to it excluded the
  //    two most frequent cases: every node behind a
  //    UPnP-refusing router and every mobile device.
  //
  // WHAT REMAINS: `isExternallyReachable` above. What does not pass this probe
  // does not go onto the board — nothing changes about that.
  return BrettDecision(
    EntryRecord.issue(
      keys: v41.keys,
      addresses: outside,
      now: now ?? DateTime.now(),
      validFor: kBrettValidity,
    ),
    // WHICH OF THE THREE PATHS yielded the address is in the
    // message — not because it decides the board, but because it is the
    // first question when reading the log afterwards (§11.3).
    v41.portMappingConfirmed
        ? 'port mapping confirmed'
        : v41.externalInboundProven
            ? 'Inbound proof present'
            : 'public address announced (§17.3)',
  );
}

/// Remembers why storing did NOT happen last time.
///
/// Without that a node without a public address — per the finding
/// of 06.09. the regular case — would cost a log line with
/// the same content every ten minutes, i.e. about 144 per day. Therefore only the
/// CHANGE is reported: the first rejection, a different reason, and the return to
/// storing.
///
/// As a class at column position zero and not as a closure in the body
/// of [_appointmentMaintain]: a declaration with two spaces of
/// indentation looks to `smoke_tagline_lab_only_guard` and
/// `smoke_delivery_layer_unwalked_guard` like a component of the layer
/// without a consumer — the same mix-up that had to be documented once already at
/// `_ablegenWennNoetig`.
final class _DeclineMemory {
  String? _last;
  bool _first = true;

  void report(String? reason, void Function(String)? log) {
    if (!_first && reason == _last) return;
    _first = false;
    final before = _last;
    _last = reason;
    if (reason != null) {
      log?.call('V4.1 rendezvous: own entry record NOT '
          'deposited — $reason');
    } else if (before != null) {
      log?.call('V4.1 rendezvous: the deposit is possible again');
    }
  }
}

/// Where the storing mark lies. Own file next to the supply, for the same
/// reason for which the age has its own too: the supply discards expired items
/// on loading, and an observation over time must not be
/// discarded along with them.
String _marksPath(String baseDir) => '$baseDir/v41_rendezvous_deposit.json';

DepositMark _markRead(
    String? baseDir, Uint8List? key, void Function(String)? log) {
  if (baseDir == null || baseDir.isEmpty) return DepositMark.never;
  try {
    return DepositMark.fromJson(
        FileEncryption(baseDir: baseDir, key: key)
            .readJsonFile(_marksPath(baseDir)));
  } catch (e) {
    // An unreadable mark costs at most one storing too many — exactly
    // the state from before S362, and thus no step backwards.
    log?.call('V4.1 rendezvous: deposit mark not readable ($e) — it is '
        'deposited once');
    return DepositMark.never;
  }
}

void _markWrite(String? baseDir, Uint8List? key, DepositMark m,
    void Function(String)? log) {
  if (baseDir == null || baseDir.isEmpty) return;
  try {
    FileEncryption(baseDir: baseDir, key: key)
        .writeJsonFile(_marksPath(baseDir), m.toJson());
  } catch (e) {
    log?.call('V4.1 rendezvous: deposit mark not writable ($e)');
  }
}

Future<void> _appointmentMaintain({
  required V41Node v41,
  required ExternalEntrySource isExternal,
  required String? relayBaseDir,
  Uint8List? depositKey,
  void Function(String)? log,
}) async {
  // ── THE MARK OUTLIVES THE PROCESS (S362) ─────────────────────────
  //
  // Here stood `var abgelegterTag = -1;` — a process-local variable.
  // Thus the condition „only store when the day has moved" was never
  // fulfilled at start, and EVERY process start stored. Under the
  // throwaway key of the external entry (v4_1 §11.3) no
  // stored item replaces the previous one, so the heap under the network-wide
  // shared day tag grew with every app start. Reasoning and calculation:
  // `AblageMarke` in `external_entry.dart`.
  var mark = _markRead(relayBaseDir, depositKey, log);
  final decline = _DeclineMemory();

  try {
    final fresh = await _depositIfNecessary(
        v41: v41,
        isExternal: isExternal,
        last: mark,
        decline: decline,
        log: log);
    if (fresh != mark) {
      mark = fresh;
      _markWrite(relayBaseDir, depositKey, mark, log);
    }
  } catch (e) {
    log?.call('V4.1 rendezvous: deposit not possible ($e)');
  }

  // NO `Timer.periodic`, but a loop on the `V41Node`.
  //
  // A periodic timer keeps the Dart VM alive — exactly the trap
  // that `V41Runtime.entryPersist` describes in its comment and because of which
  // that timer stands in the return value at all. The loop here
  // ends as soon as the node stands still (`stopped`), and therefore needs no
  // own handle for cancelling.
  while (!v41.stopped) {
    await Future<void>.delayed(_appointmentTick);
    if (v41.stopped) return;
    try {
      // ALWAYS check the storing — it hangs on the day and on the
      // address change, not on the number of partners. A well-connected
      // node that no longer publishes itself is exactly the one
      // a cold node would need.
      final newMark = await _depositIfNecessary(
          v41: v41,
          isExternal: isExternal,
          last: mark,
          decline: decline,
          log: log);
      if (newMark != mark) {
        mark = newMark;
        _markWrite(relayBaseDir, depositKey, mark, log);
      }

      if (v41.partnerCount >= v41.policy.target) continue;

      final erg = await ColdStart(sources: [isExternal]).run(
          enough: (until) => distinctPositionsOf(until) >= _enoughRoutes);
      var fresh = 0;
      for (final r in erg.records) {
        if (v41.entries.remember(r, source: 'kaskade')) fresh++;
      }
      if (fresh > 0) {
        log?.call('V4.1 rendezvous: $fresh new entry record(s) '
            '(partners ${v41.partnerCount} of ${v41.policy.target})');
        await v41.dialFromEntries();
      }
    } catch (e) {
      log?.call('V4.1 rendezvous: pass failed ($e)');
    }
  }
}

// ── `vorratUnicastTargets` IS GONE (S372) ──────────────────────────────
//
// It delivered HOSTS WITHOUT PORT, to which the LAN call additionally went by unicast
// on the fixed `kLanEntryPort` — every 30 seconds, also to
// public addresses. Thus the fixed port left the local network,
// and exactly that is unacceptable: a block rule on UDP/41340 kills the
// path network-wide (RL-14 „no well-known port"), and whoever answers there is
// recognised as a Cleona node.
//
// Without replacement, not replaced, and that is the point:
//
//  * An address FROM THE SUPPLY comes from an `EntryRecord` — we
//    therefore already have it. One does not call to it, one dials it
//    (`V41Node.dialFromEntries`). The unicast call to it was redundant.
//  * A HINT from a person gets, since S372, a directed
//    portal request on the port it names itself
//    (`tagline/entry_portal.dart`), once per hint instead of every
//    30 seconds. B-27 (guest WLAN in which no broadcast gets through,
//    measured 28.08.) thus remains served.
//
// The filtering to IPv4 that stood in this function drops away with
// it: the portal sends via `UdpSocketSet`, which chooses the family from the
// target address and binds both.

/// The entry points of this node as BINARY SOURCES (§26.6.4).
///
/// ── WHAT §26.6.4 DEMANDS, AND WHAT WAS MISSING UNTIL HERE ─────────────────
///
/// „A publishing node that holds a complete binary set is reachable
/// through the same entry cascade the inviter's `s=` ContactSeed encodes;
/// the browser assembler (§26.6.5) walks the entry hints, contacting
/// directly-reachable nodes in turn until one serves the matching
/// platform." The paragraph puts the entry cascade (§11) in place
/// of the external carrier.
///
/// Measured on 06.09.2026 (S372), the source discovery of the
/// update download ran via exactly one class: `_startInNetworkUpdate` called
/// `BinaryRendezvousManager.resolve()`, and that asks Nostr
/// (`binary_rendezvous_manager.dart`, `_providersOrDefault`). The supply
/// of the entry cascade had **zero** reference in the whole update path —
/// re-measured with nine search patterns over `lib/core/update/`,
/// `cleona_service_update.dart` and `binary_rendezvous_manager.dart`:
/// `EntryCache` 0, `EntryRecord` 0, `dialCandidates` 0, `EntryAddress` 0,
/// `ColdStart` 0; the nine hits on `entries` were all
/// `Map.entries`. If Nostr stayed silent, the click path aborted with „no binary
/// sources found", although reachable neighbours stood in the supply.
///
/// **This function does NOT clear away Nostr.** Whether the external carrier
/// falls per §26.6.4 or stays per §26.7 is an open
/// owner decision (the two paragraphs contradict each other; the
/// finding is at `BinaryRendezvousManager.publish`). A wiring does not
/// make it on the side — the cascade joins the
/// Nostr sources, and in the caller comes behind them.
///
/// ── WHY THE PORT NUMBER OF THE RECORD IS RIGHT ──────────────────────
///
/// The entry record names ONE port for UDP and TCP (E-60;
/// `v41_node.dart`, at the construction of `TcpLinkListener`:
/// „THE SAME PORT NUMBER AS UDP"), and `attachV41` hangs the
/// [BinaryHttpServer] on the four-byte switch of exactly this listener.
/// `http://<host>:<port>/cleona/binary/<plattform>` is thus the right address
/// without additional knowledge — exactly the model that §26.6.5
/// describes („the shared port number for UDP and TCP").
///
/// ── THE VERSION IS NOT ON THE RECORD, AND THAT COSTS NOTHING ──────
///
/// Unlike the Nostr record (`ResolvedBinaryEndpoint.version`),
/// an entry record says nothing about WHICH version the neighbour
/// holds. A filter is nevertheless not needed, and that is measured,
/// not hoped: `BinaryFetchClient.fetch` rejects an answer whose
/// `Content-Length` does not EXACTLY match the size expected from the signed manifest
/// (`binary_fetch_client.dart`,
/// „Content-Length … != expected … — rejecting early") — a neighbour with
/// a different version drops out BEFORE the first payload byte. What
/// would still get through after that is caught by the hash and signature check
/// (§26.6.1 step 5, `BinaryUpdateManager.verify`).
///
/// ── ORDER AND CAP ───────────────────────────────────────────────
///
/// `dialCandidates()` already delivers the order of the cascade (fresh before
/// expired, not failed before deferred). It is taken over,
/// not re-sorted. [max] caps the list, because every address costs an
/// HTTP attempt (work rule #5); the default corresponds to that of
/// [vorratUnicastTargets].
///
/// **Private addresses stay in, and that is intentional.** §26.6.4 says
/// „LAN nodes are found via LAN discovery, not via the entry cascade" —
/// that concerns the QUESTION of who holds binaries, not the fetch. For the
/// fetch a neighbour in the same segment is the cheapest source
/// of all, and `cleona_service_update.dart` lists the loss of exactly
/// these addresses as part of gap G-11.
///
/// Takes [EntryCache] and not `V41Node` — for the same reason
/// as [vorratUnicastTargets]: testable without a running node.
List<EndpointAddress> entryBinarySources(EntryCache entries,
    {int max = 12}) {
  final out = <EndpointAddress>[];
  final seen = <String>{};
  for (final r in entries.dialCandidates()) {
    for (final a in r.addresses) {
      if (out.length >= max) return out;
      final host = a.host;
      if (host.isEmpty || a.port == 0) continue;
      // Calling itself yields the version that is running anyway.
      if (host == '0.0.0.0' ||
          host == '::' ||
          host == '::1' ||
          host.startsWith('127.')) {
        continue;
      }
      if (!seen.add('$host|${a.port}')) continue;
      out.add(EndpointAddress(host, a.port));
    }
  }
  return out;
}

Future<LanEntryHandle?> _startLanEntryFromPool(
    V41Node v41, NodeKeys keys, int port, void Function(String)? log) async {
  try {
    return await startLanEntry(
      node: v41,
      keys: keys,
      dataPort: port,
      log: log,
      // ── WHERE THE HINTS COME FROM (S372) ────────────────────────────
      //
      // UNTIL S372 here stood `unicastTargets` — a list of HOSTS
      // without port, to which the call additionally went by unicast on 41340,
      // every 30 seconds, also to public addresses. That was the
      // second path on which the fixed port left the LAN.
      //
      // NOW: the hints WITH their port, and the cycle asks each
      // of them exactly once via a directed portal request on the
      // data port of the other side. The supply (`vorratUnicastTargets`)
      // is deliberately no longer in it: for an address from the supply
      // we have the record and dial it instead of calling to it.
      hints: () => personEntryHints.hints,
    );
  } catch (e) {
    log?.call('V4.1: LAN entry not started ($e) — the node finds '
        'no partners via this segment');
    return null;
  }
}

/// Areas of the store (`MessageStore.state`) for the two secrets
/// that §21.4 lists „mandatorily under the DB key" (S372 — before, separate
/// files `v41_prekeys.json.enc`/`v41_daily_secrets.json.enc`, see
/// [attachV41]). Per identity only ONE entry — the key material
/// does not grow in its number of rows, only in its content — hence the
/// fixed key [keyOneLiner], the same construction as
/// `IdentityContext.schluesselKeys`.
const String areaV41Prekeys = 'v41_prekeys';
const String areaV41DailySecrets = 'v41_daily_secrets';
const String keyOneLiner = '_';

/// Loads the prekey supply of this identity into [host] (§21.4, §4.6).
///
/// §21.4 demands it verbatim „mandatorily under the DB key", and §4.6
/// point 3 gives the reason why: retention must outlast the full delivery period,
/// „or cells from days 9-14 become unopenable (silent
/// message loss)".
///
/// SOURCE, IN THIS ORDER: (1) the area [areaV41Prekeys] of the
/// store — the operational case from S372; (2) if nothing lies there yet,
/// a found `v41_prekeys.json` — a profile that already carried a V4.1 prekey supply
/// before S372. That is NO old-profile migration
/// (there is none, first-start wipe), but a format change during
/// running V4.1 operation — the same figure as
/// `KeyMigration.migrateDeviceScopedFiles`: it does not ask by the file name,
/// but by whether the area already holds something.
///
/// A TAKEN-OVER OLD STOCK IS WRITTEN INTO THE STORE IMMEDIATELY, and
/// the old file falls ONLY after a read-back from the store has confirmed the
/// content — the same order as with the
/// keyring conversion (`LegacyKeyPurge`): a crash between
/// writing and deleting may at most let the old file survive,
/// never lose the content.
///
/// Own function (S372), so that a test can run it without the full
/// `attachV41` setup (real `V41Node`, real sockets) against a real
/// profile — `test/smoke/smoke_v41_prekey_daily_secrets_ablage.dart`.
void ladePrekeyPool({
  required CleonaService service,
  required V41Host host,
  void Function(String)? log,
}) {
  final deposit = service.storeOrNull;
  final oldPrekeyPath = '${service.profileDir}/v41_prekeys.json';
  try {
    var deposited = deposit?.loadArea(areaV41Prekeys)[keyOneLiner];
    if (deposited == null) {
      final legacyData = service.fileEnc.readJsonFile(oldPrekeyPath);
      if (legacyData != null) {
        deposited = legacyData;
        if (deposit != null) {
          deposit.putEntry(areaV41Prekeys, keyOneLiner, legacyData);
          if (deposit.loadArea(areaV41Prekeys)[keyOneLiner] !=
              null) {
            service.fileEnc.deleteFile(oldPrekeyPath);
            log?.call('V4.1: prekey pool taken over from the old file — '
                'the store demonstrably holds it now, the file is gone');
          }
        }
      }
    }
    if (deposited != null) {
      final n = host.importPrekeyState(deposited, now: DateTime.now().toUtc());
      log?.call('V4.1: prekeys loaded — ${n.own} own secrets in '
          '${n.pools} pool(s), ${n.theirs} foreign');
    }
  } catch (e) {
    // No start error: without supply the sealing falls back to step 3
    // — worse, but deliverable. Exactly as at the very first
    // start, and as the entry supply next to it handles it.
    log?.call('V4.1: prekey pool not readable ($e) — static fallback');
  }
}

/// Loads the receiver's daily secrets into [host.opener] (§21.4, §4.3).
///
/// Approved on 30.08. and normative since: §21.4 lists them next to
/// `inbox_key` and the prekey supply „mandatorily under the DB key",
/// „retained no longer than the identity KEM rotation interval (7 days)".
/// Without that the receiver was deaf after every restart for the rest of the
/// day: the sender rightly keeps its capsule proof and leaves out the
/// 1088 B, but the receiver no longer has the secret.
///
/// S372: the same area change as with the prekey supply (see
/// [ladePrekeyPool] for the full reasoning), into the area
/// [areaV41DailySecrets] — with the same old-stock takeover and
/// the same order (first write, then check by reading, only then
/// delete the old file). Does nothing if [V41Host.opener] is `null`
/// (no receive path without an opener).
void ladeDailySecrets({
  required CleonaService service,
  required V41Host host,
  void Function(String)? log,
}) {
  final opener = host.opener;
  if (opener == null) return;
  final deposit = service.storeOrNull;
  final secretPath = '${service.profileDir}/v41_daily_secrets.json';
  try {
    var deposited =
        deposit?.loadArea(areaV41DailySecrets)[keyOneLiner];
    if (deposited == null) {
      final legacyData = service.fileEnc.readJsonFile(secretPath);
      if (legacyData != null) {
        deposited = legacyData;
        if (deposit != null) {
          deposit.putEntry(
              areaV41DailySecrets, keyOneLiner, legacyData);
          if (deposit.loadArea(areaV41DailySecrets)[keyOneLiner] !=
              null) {
            service.fileEnc.deleteFile(secretPath);
            log?.call('V4.1: daily secrets taken over from the old file '
                '— the store demonstrably holds them now, '
                'the file is gone');
          }
        }
      }
    }
    if (deposited != null) {
      opener.loadJson(deposited.cast<String, Object?>(),
          now: DateTime.now().toUtc());
      log?.call('V4.1: daily secrets loaded — '
          '${opener.secretsLoaded} adopted, '
          '${opener.expiredSecretsDropped} expired and discarded');
    }
  } catch (e) {
    // As with the supply: no start error. Without stock the
    // other side carries the capsule along again after an hour (path 3b) —
    // slower, but deliverable.
    log?.call('V4.1: daily secrets not readable ($e) — '
        'the capsule comes back via the evidence expiry');
  }
}

/// Hooks ONE identity onto the running node.
///
/// Per call an own prekey supply and an own
/// sealing arise — that MUST be so: `peer` in the body of `sendToUser` is
/// only the receiver UserID (`cleona_service.dart`, `_hexOf(recipientUserId)`)
/// and does not carry the sender identity. Two identities on one
/// node writing to the same counterpart would otherwise have shared a
/// supply and mutually consumed foreign one-time prekeys.
/// What is shared is the NODE, not the key state.
/// The receiver of the readiness edge — TWO objects that do not
/// have the same direction.
///
/// ── 1. THE DRAIN OF THE OUTBOX: ONLY UPWARDS (§21.2, gap G-4) ──────
///
/// If readiness falls from `ready` to `connecting`, a
/// proof has just DROPPED AWAY — a resubmission then all the more has no
/// addressee and would only use up one of the three attempts per entry.
///
/// ── 2. THE DISPLAY: IN BOTH DIRECTIONS (§25.4) ──────────────────────
///
/// §25.4 verbatim: „The badge mirrors the readiness state 1:1 and applies
/// no threshold logic of its own." A mirror that only shows the rises
/// is none. Measured in the field (S372): a node fell at 10:21:58
/// from `ready` to `connecting`, the UI still showed „Bereit" 11.5 minutes
/// later — the readiness edge was the ONLY path
/// on which the change could have arrived, and it discarded it.
///
/// THE SAME NOTIFICATION CARRIES BOTH PLATFORMS, and without a second path:
/// `CleonaService.onStateChanged` feeds under Linux/Windows the
/// IPC event `state_changed` (`ipc_server.dart`, field `readiness`), from
/// which `IpcClient` fills its buffer; under Android in-process
/// `notifyListeners()` hangs on it, whose override in `main.dart` sets the
/// foreground notification anew. The finding showed both sides
/// hanging — desktop badge too high, Android notification too low —,
/// but it is ONE defect at ONE edge, not two.
///
/// ── WHY AS A NAMED FUNCTION ──────────────────────────────────────
///
/// So that a test can feed it with a real transition without building a
/// `V41Node` with sockets (`V41Node._` is private, the path there
/// leads via `startV41Node()` and thus via a `LinkHost`). The
/// setup below hands in exactly the two capabilities it uses.
///
/// ── `finally`, NOT ONE AFTER THE OTHER ────────────────────────────────────
///
/// `flushV41Outbox` can throw (`v41PairKeyFor` throws on a deleted
/// contact; the bolt per entry sits one level deeper, the cap
/// around it does not). If the notification stood after it, such a throw would tear
/// the display along — and precisely on the rise, i.e. the case
/// the user wants to see. The throw itself goes on to the bolt in
/// `V41Node._meldeBereitschaft`, which logs it.
/// The sink for „the control queue has room again" (S381).
///
/// A factory, so that every identity gets its OWN object and the
/// deregistration finds it again — the same reasoning as for
/// [_readinessEdgeFor].
/// NO own `try` here: `V41Node._egressPlatzPruefen` catches and
/// logs what a sink throws — just as
/// `_meldeBereitschaft` does for the neighbour edge. Two bolts
/// on top of each other would be two places for the same statement.
void Function(String) _egressEdgeFor(CleonaService service) =>
    (String reason) => service.flushV41Outbox(reason: reason);

void onReadinessEdge({
  required Readiness before,
  required Readiness after,
  required void Function(String reason) outflow,
  required void Function() report,
}) {
  try {
    if (after.index > before.index) {
      outflow('Bereitschaft ${after.name}');
    }
  } finally {
    report();
  }
}

V41Host attachV41({
  required CleonaService service,
  required V41Runtime runtime,
  required NodeKeys keys,
  void Function(String)? log,
}) {
  final theirs = PeerPrekeys();
  // BOUND LATE, because the host only exists afterwards: the fallbacks
  // read the keys of the COUNTERPART from the host, and the body of
  // `sendToUser` puts them there as soon as it has resolved them.
  late final V41Host host;
  final pool = PoolPrekeys(theirs,
      mlKemOf: (peer) => host.peerMlKem(peer) ?? keys.nMlKemPublic);
  final boot = BootstrapPrekeys(
    pool: pool,
    // Until the first prekey batch is there, against the long-lived
    // keys of the RECEIVER — visibly counted, not
    // silently.
    //
    // UNTIL S349 THIS SAID `(_) => keys.nMlKemPublic`, i.e. the own
    // node key regardless of the counterpart (B-19). The sender
    // thus sealed to itself. The fallback to the own
    // key stays as last resort — it is then useless,
    // but it does not throw, and `fallbackCount` counts it.
    staticMlKem: (peer) => host.peerMlKem(peer) ?? keys.nMlKemPublic,
    staticX25519: (peer) => host.peerX25519(peer) ?? keys.nX25519Public,
  );
  host = V41Host(
    delivery: runtime.node,
    sealer: MessageSealer(boot),
    prekeys: boot,
    theirs: theirs,
  );
  host.lanEntry = runtime.lanEntry;

  // THE RECEIVER SIDE — it belongs to the IDENTITY, not to the node.
  // The sealing runs against the user KEM keys of this
  // identity, so the opener must hold its secrets. A node
  // with two identities registers two sinks; the node offers every
  // reassembled payload to both and does not ask which one was meant
  // — it could not know (invariant 3).
  //
  // THE PREVIOUS KEM GENERATION COMES ALONG (§4.5.4, S362). Without these two
  // lines the fallback in the opener is built and never entered: without a callback it falls
  // back to `null` and behaves as before.
  //
  // WHY CALLBACKS AND NOT VALUES: `previousX25519Sk`/`previousMlKemSk`
  // are set at runtime (every rotation) and set back to `null`
  // (`discardPreviousKeysIfExpired`, 32 days). A value frozen
  // here would be the wrong one after the first rotation and,
  // after discarding, a key the identity no longer
  // holds — i.e. exactly the retention that §4.5.4 limits, undermined at a
  // place no one checks any more.
  host.opener = MessageOpener(
    ownMlKemSecret: () => service.identity.mlKemSecretKey,
    ownX25519Secret: () => service.identity.x25519SecretKey,
  )
    ..previousX25519Secret = (() => service.identity.previousX25519Sk)
    ..previousMlKemSecret = (() => service.identity.previousMlKemSk);


  attachV41Sink(
      node: runtime.node, host: host, service: service, log: log);

  service.v41Delivery = runtime.node;
  service.v41Host = host;
  // ── THE PORT MAPPING TO THE SERVICE (gap G-12, S373) ───────────
  //
  // The same seam as two lines above: the coordinator belongs to the
  // NODE (one port, one process, one mapping), the display belongs to
  // the SERVICE (per identity), and `attachV41` is the only place at
  // which both are available.
  //
  // WITHOUT THIS LINE `CleonaService.hasPortMapping` stays blind. Until
  // today a constant `false` stood there, and four display places
  // permanently showed „no UPnP" — `system_channel_post.dart:340/:441`,
  // `system_channels.dart:282/:300/:396`, `crash_reporter.dart:273`,
  // `contact_issue_reporter.dart:74` —, regardless of what the router did.
  //
  // TWO IDENTITIES ON ONE NODE SEE THE SAME MAPPING, and that
  // is right: there is one port and one release. The same
  // reasoning as for the wire numbers further below.
  service.v41PortMapper = runtime.portMapping?.mapper;
  // ── FIRST HARVEST, THEN ANNOUNCE (§4.5.4, S363) ──────────────────
  //
  // Without this line the cold-start gate in `CleonaService` is built and
  // never entered: it would only open with the fallback period (one hour),
  // instead of with the first harvest run (~32 s). The same half-measure that
  // `smoke_bulk_lane_effect.dart` measures for `bindTransport`/`onBulkScanned`
  // — built, set, but only on one side.
  //
  // ── REGISTERED, NOT SET (S376, P5 finding 1) ─────────────────
  //
  // Here stood `runtime.node.onHarvestRun = service.meldeErnteLauf`, a
  // SINGLE SLOT — and this function runs per identity against the same
  // node. With three identities the node reported the harvest run only to
  // the last attached one; for the other two the
  // cold-start gate stayed closed until the fallback period of one hour.
  runtime.node.addHarvestRunListener(service.reportHarvestRun);
  host.deregistrations
      .add(() => runtime.node.removeHarvestRunListener(service.reportHarvestRun));

  // ── THE HARVEST HORIZON TO THE NODE (E5, S363) ────────────────────
  //
  // The horizon belongs to the IDENTITY — it travels in
  // `v41_prekeys.json` with the supply whose period it carries. It is KEPT
  // by the NODE, because only `harvestTick` knows whether a catch-up
  // is open. `attachV41` is the only place at which both are available
  // at the same time — the same reasoning as two lines higher and as for
  // level D further below.
  //
  // WITHOUT THIS LINE E5 IS BUILT AND NEVER ENTERED: the supply would ask
  // a horizon that no one ever advances, and would only throw something away at the cap
  // (`ErnteHorizont.deckelUeberFrist`). Exactly the class
  // „set, but only on one side" that
  // `smoke_bulk_lane_effect.dart` measures — here it is measured by
  // `smoke_ernte_horizont.dart`.
  //
  // ── AND ONE PER IDENTITY (owner decision V-1 = B, S376) ───
  //
  // Here stood `runtime.node.ernteHorizont = host.ernteHorizont`, a
  // SINGLE SLOT against the same node. With three identities the
  // node kept the horizon of the last attached one; the other two
  // never advanced and after a restart never triggered a
  // catch-up.
  //
  // THE OWNER DECIDED AGAINST A SHARED HORIZON
  // (08.09.2026, variant B). Reasoning: a shared horizon
  // does not let a rarely used identity catch up on harvesting after a restart
  // — silent message loss. The bundling that carries the
  // price is at `V41Node.aeltesterHorizont`.
  runtime.node.addHarvestHorizon(host.harvestHorizon);
  host.deregistrations
      .add(() => runtime.node.removeHarvestHorizon(host.harvestHorizon));

  // ── AND THE REPORT OF A STALE PREKEY BATCH (E6, S363) ────
  //
  // `PeerPrekeys` is pure data keeping and deliberately holds no
  // `CLogger` (that hangs a timer on the process, S360). Without this
  // line the counter `veralteteZiehungen` would run, but nothing would be in the log
  // — and the finding that E6 is meant to make visible would only be visible in
  // a field no one queries.
  theirs.report = (m) => log?.call('§4.6/E6: $m');

  // ── AND THE FALLBACK TO THE PAIR ANCHOR (variant E, S367) ───────
  //
  // The same reason and the same construction one line higher, only the
  // other half of the finding: `theirs.melde` says that there was DRAWING from dead
  // material, this one says that the anchor was taken because of it.
  // Without this line [V41Host.ankerWegenVeraltung] would run
  // and nothing would be in the log — and the change of security posture
  // would be silent. Exactly that is forbidden in substance by the invariant „Speed may fall back to
  // Secure, Secure never silently to Speed".
  host.report = (m) => log?.call('§4.6/E anchor: $m');

  // ── LEVEL D TO THIS IDENTITY (§17.4) ───────────────────────────
  //
  // The socket belongs to the NODE (one cookie table, one demux branch),
  // the call transport belongs to the IDENTITY. `attachV41` is the
  // only place at which both are available at the same time — the same reasoning
  // for which two lines higher `v41Delivery` and `v41Host` are set here
  // and not in the node.
  //
  // Two identities in one process get THE SAME socket. That
  // is not a matter of economy: a D frame carries no identity identifier, it
  // is according to §17.4 solely „authentic via AEAD under the `call_key`",
  // and the cookie names the session. Which identity conducts the call
  // is decided by the signalling, not by the socket.
  //
  // SINCE S361 MORE THAN THE SOCKET GOES ACROSS (§17.3). The punch window
  // also needs the port under which this node is REALLY bound,
  // and the address mirror — both belong to the node, both are available here
  // at the same time. `host.sockets.port` and not `advertisePort`: the
  // announcement is one thing, the binding another, and a punch packet arrives
  // at the binding or nowhere.
  //
  // AND SINCE S376 THE PORT MAPPING (§25.9, A-1). It goes across as a FUNCTION,
  // not as a value: `advertiseMapped` arises seconds to
  // minutes after this call (`PortMapBinding` searches for the mapping
  // alongside), is renewed hourly and drops away at a network change.
  // A value copied here would be `null` and would stay so.
  service.attachCallPlaneD(CallPlaneD(
    socket: runtime.node.dSocket,
    ownPort: runtime.node.host.sockets.port,
    observed: runtime.node.host.observed,
    mapped: () => runtime.node.advertiseMapped,
  ));

  // ── THE BULK LANE TO THIS IDENTITY (§9.3) ──────────────────────
  //
  // The same construction and the same reasoning as level D above: the
  // HOLDER belongs to the node (one quota, one wire, one outflow),
  // the TRANSFERS belong to the identity (`MediaBulkLane` carries
  // tags, tickets and receipts of one identity), and `attachV41` is
  // the only place at which both are available at the same time.
  //
  // **`bindTransport` AND `onBulkScanned` — both, or nothing works.**
  // `bindTransport` hooks the sink of the lane into the transport; the
  // back side, via which a scan answer finds its way from the node into the
  // transport, is `DeliveryNode.onBulkScanned`. Whoever sets only one
  // of the two gets a lane that stores and never harvests — and
  // that is traffic no one collects (work rule 5). Exactly this
  // half-measure is measured by `smoke_bulk_lane_effect.dart` in its reverse test.
  //
  // WITH TWO IDENTITIES THE LAST ONE WINS — and that is without
  // consequences here, unlike with the HTTP switch below: `acceptScanned`
  // looks up the identifier in its OWN book and discards what
  // is not in it. An answer to the request of the other
  // identity would find nothing there and silently drops — it would not land
  // in the wrong harvest. The price is that two simultaneous
  // bulk harvests in one process can take each other's answers
  // away; that is reported and not hidden.
  final bulkTransport = V41MediaBulkTransport(runtime.node, log: log);
  service.mediaBulkTransport = bulkTransport;
  final MediaBulkLane lane = service.mediaBulkLane;
  lane.bindTransport(bulkTransport);
  runtime.node.delivery.onBulkScanned = bulkTransport.acceptScanned;
  // THE ROUND END BELONGS TO IT, and necessarily so: on it — not on the
  // block input — the resubmission of the scanning hangs
  // (`BulkOp.scanEnd`). Whoever sets only `onBulkScanned` gets a
  // harvest that stands still after the FIRST round.
  runtime.node.delivery.onBulkScanEnd = bulkTransport.acceptScanEnd;
  // And the cleanup: the transport carries rounds per tag and a hop counter per
  // holder. Without this call a remainder would stay after every
  // received file.
  lane.onTagForgotten = bulkTransport.forgetTag;
  // Only for the status line — see `V41Node.bulkEgress`.
  runtime.node.bulkEgress = bulkTransport.egress;
  runtime.node.bulkSenderStatus = bulkTransport.statusLine;

  // ── THE HTTP SWITCH OF THE DATA PORT (§26.6.5, E-118, gap G-20) ───
  //
  // The same construction and the same reasoning as level D a hand's breadth
  // higher: the LISTENER belongs to the node (one port, one process), the
  // DELIVERY SERVER belongs to the service (it reads from its
  // fragment store), and `attachV41` is the only place at which both
  // are available at the same time. The node stands in both composition points
  // BEFORE the services — it supplies them the port —, so the sink
  // cannot already be set at its construction.
  //
  // Until S361 NOTHING stood here, and `TcpLinkListener` was constructed
  // nowhere in `lib/`. What hung on that: the delivery of
  // binaries (§26.6.4), the bootstrap web app of the invitation link
  // (step 3 of the distribution ladder §26.6.7) — and, one size larger than
  // the reported gap, EVERY incoming TCP link handshake.
  //
  // ── FIRST SERVICE WINS, AND THAT IS A DECISION ───────────
  //
  // There is ONE port and ONE switch, but per identity an own
  // `BinaryHttpServer` (`cleona_service_update.dart`, built from
  // `profileDir`). Exactly one can serve the port. The chosen one is the
  // FIRST attached service — deterministic, because both
  // composition points run their service loop over a map in
  // insertion order and the primary identity is inserted
  // first.
  //
  // The price is small and is named here nevertheless: what the switch
  // delivers is the running binary, and that is the same for all
  // identities — every service seeds it into its store anyway
  // (`_selfSeedCurrentBinary`). The only difference is the
  // FOREIGN-PLATFORM stock (§26.6.4): if identity 2 fetches a
  // Windows binary and identity 1 does not, this node does not
  // deliver it. The alternatives — lifting the server from the service into the process
  // or chaining the providers of the switch across all services —
  // stand with calculated price in
  // `docs/v4-redesign/S361-VORLAGE-tcp-lauscher.md`, section 5.
  final BinaryHttpServer? http = service.binaryHttpServer;
  if (http == null) {
    log?.call('V4.1: this service has no delivery server — the '
        'HTTP switch of the data port stays open (§26.6.5)');
  } else if (runtime.node.tcp.httpSink != null) {
    log?.call('V4.1: the HTTP switch is already taken — this service '
        'does not deliver (one port, one switch)');
  } else {
    // The signature is that of `LinkHttpSink`: socket, bytes already read,
    // and the PAUSED subscription. All three must go across —
    // a `Socket` is a single-subscription stream, a second
    // `listen()` throws, and a `cancel()` shuts down the receive direction
    // of the raw socket (the header of `LinkHttpSink` carries the
    // finding).
    runtime.node.tcp.httpSink = (Socket client, Uint8List buffered,
            StreamSubscription<Uint8List> sub) =>
        http.handleConnection(client, bufferedData: buffered, subscription: sub);
    log?.call('V4.1: delivery server at the HTTP switch of the '
        'data port (§26.6.5)');
  }

  // ── THE ENTRY CASCADE AS BINARY SOURCE (§26.6.4, S372) ─────────
  //
  // The same construction and the same reason as for the HTTP switch a
  // hand's breadth higher, only in the opposite direction: the SUPPLY belongs to the
  // node (`V41Node.entries`, one process), the UPDATE FETCH belongs to the
  // service (it holds manifest and fragment store), and `attachV41` is
  // the only place at which both are available at the same time.
  //
  // What this line switches on is at [eintrittsBinaerQuellen]: until
  // S372 `_startInNetworkUpdate` knew exactly ONE source class (Nostr)
  // and aborted without it, although the supply held reachable neighbours
  // whose data port the delivery server serves.
  //
  // FIRST SERVICE WINS is NOT needed here — the source is a
  // pure reader without state, every service may see the same supply.
  service.binarySourcesOutEntry =
      () => entryBinarySources(runtime.node.entries);

  // ── THE COVER FILL (§5.5) ────────────────────────────────────────
  //
  // The same construction and the same reason as for the HTTP switch above:
  // the SLOT PLAN belongs to the node (one cycle, one process), the
  // MANIFEST belongs to the service (it checks it and holds the
  // fragment store), and `attachV41` is the only place at which both
  // are available at the same time.
  //
  // ── WHAT THESE TWO LINES SWITCH ON ────────────────────────────────
  //
  // `lib/core/update/cover_fill_blocks.dart` had been built since S365 and
  // had ZERO callers in all of `lib/` — the hook in
  // `DeliveryNode.tick` (l. 425-435, behind `takeSlot`) asked a
  // callback no one set, and every due cover slot went out with
  // 1169 B of randomness. Exactly this class of bug — built, never entered,
  // smoke green anyway — cost S349 a whole session.
  //
  // ── RULE 1 HOLDS STRUCTURALLY, NOT THROUGH ASSURANCE ──────────
  //
  // The callback is only asked after the control queue has had its
  // slot AND `takeSlot` has decided that no payload
  // rides along (`slot.isDummy`). It does not know the slot plan and cannot
  // touch it. Rule 2 likewise: the partner is fixed since
  // `drawPartner()`, and the callback has no parameters.
  //
  // ── FIRST SERVICE WINS ───────────────────────────────────────────
  //
  // As with the HTTP switch: there is ONE slot plan, but per identity
  // one service. What is distributed is the binary of this device —
  // the same for all identities —, so the choice is without consequence.
  if (runtime.node.delivery.coverFill == null) {
    runtime.node.delivery.coverFill = service.nextCoverFillBlock;
    runtime.node.delivery.onCoverFillBlock = service.takeCoverFillBlock;
    log?.call('V4.1: cover fill carries fountain blocks (§5.5)');
  }

  // ── THE NETWORK NUMBERS TO THE DISPLAY (§25.5, gap G-10) ────────────
  //
  // Four tiles of the network statistics had stood at 0 since the CUT: sent
  // and received wire bytes, forwarded messages and
  // relay volume. The collector sits at the service (i.e. per identity), the
  // counters belong to the node (i.e. the process) — here both
  // meet, as already with `v41Delivery` and `v41Host` two screen lines
  // higher.
  //
  // TWO IDENTITIES ON ONE NODE SEE THE SAME WIRE NUMBERS, and
  // that is right: there is one socket, one cover cycle, one
  // forwarding. The cells of one identity cannot be computed out of the wire
  // — exactly that is the purpose of the cover traffic (§5).
  // The MESSAGE counters stay unaffected by that and per identity.
  // ── THE NETWORK CHANGE (§22.6) ───────────────────────────────────────
  //
  // Until S360 the delivery layer learned nothing of a network change —
  // `CleonaService.onNetworkChanged` refreshed a local address list
  // and was done. What stayed wrong in the process is at
  // `V41Node.onNetworkChanged`; here is what the NODE cannot do
  // alone.
  //
  // The node knows no network interfaces (it knows no
  // `dart:io` apart from the socket, and that is to stay so), so it cannot
  // determine its own new address. This seam knows both:
  // the node and the address resolver it was started with.
  //
  // ORDER, and it is not arbitrary: first set the new announcement,
  // then drop the sessions, then propagate the record.
  // The other way round the node would still announce the dead address in the window in between
  // — and exactly this record would be harvested by the
  // neighbours it is just dialling anew.
  //
  // ── AND IT BELONGS TO THE PROCESS, NOT TO THE IDENTITY (S376, finding 5)
  //
  // Since S376 the body stands in [v41KnotenNetzwechsel] — a function
  // over the RUNTIME, not over the service. `attachV41` runs per
  // identity and set an own closure here per identity; the
  // caller loops of the three entry points then called it N times.
  // What ran N times however belongs entirely to the node: N session teardowns, N
  // priority announcements, N LAN calls for ONE event. The
  // reasoning in detail is at the function.
  //
  // THE SEAM STAYS AT THE SERVICE NEVERTHELESS, and that is no contradiction:
  // there are callers that ARE really single and still need the
  // node part — `importPeerBundle` calls
  // `onNetworkChanged(force: true)` after reading in a
  // rescue bundle, and there the one service is the whole occasion.
  // Whoever has already run the node part himself says so via
  // `triggerNodeReset: false` — the parameter that is there exactly for that
  // and whose contract has always stood in `service_interface.dart`.
  service.v41OnNetworkChanged = () => v41NodeNetworkChange(runtime, log: log);

  // ── AND THE FOREGROUND EDGE (§22.6, variant C, S362) ───────────
  //
  // The second of the two edges on which the catch-up harvest hangs. It
  // happens HERE and not in the node, because the node does not know the life cycle of the
  // app — the same seam as `v41OnNetworkChanged` above.
  //
  // WITHOUT `setzeAnsageadressen`, without session teardown, without announcement: a
  // return to foreground is no network change. The address stays valid,
  // the partners stay — what is to be caught up is solely what
  // remained lying at the responsible relays during the absence.
  //
  // IT TOO BELONGS TO THE PROCESS (S376, finding 5): `nachholErnte` is
  // a matter of the NODE, and N identities would mean N harvest runs for
  // a single return to the foreground. See
  // [v41KnotenVordergrund].
  service.v41OnForeground = () => v41NodeForeground(runtime);

  // ── THE OWN LINE (§14.7, gap G-14) ─────────────────────────
  //
  // Since the CUT the twin sync had been running against a wall: `sendToUser`
  // reported "Selbstversand — V4.1 hat keine Geraete-Marke" and did not
  // send. Affected were all 14 sync types, device pairing
  // and `TWIN_ANNOUNCE`. It only stayed invisible because `_sendTwinSync`
  // bails out beforehand with a single device.
  //
  // HERE, because `K_own` is derived from the user KEM secrets of the IDENTITY
  // and the registry belongs to the NODE — the same seam as
  // `v41Delivery`/`v41Host` two screen pages higher.
  //
  // WITH EQUAL INPUT AND OUTPUT DIRECTION, and that only works via the
  // concrete registry: the `V41Delivery` interface only knows the
  // output direction. Why the own line needs it is in the header
  // of `own_line.dart`.
  service.v41ArmOwnLine = () {
    try {
      final kOwn = deriveKOwn(
        userX25519Secret: service.identity.x25519SecretKey,
        userMlKemSecret: service.identity.mlKemSecretKey,
      );
      runtime.node.pairs.remember(
        ownPeerKey(service.identity.userId),
        kOwn,
        outDirection: kOwnLineDirection,
        inDirection: kOwnLineDirection,
      );

      // ── AND THE OWN DEVICE LINE (§14.1, §14.7) ─────────────────
      //
      // The second line from §14.7 — the one for everything that differs PER DEVICE.
      // It is entered HERE and not at sending,
      // because this device must HARVEST it: the key package (type 16),
      // the initial sync (§14.6.3) and the delivery of delegated
      // keys come from a sibling, not from here. A line
      // that only arose at the first own send would be exactly the
      // trap in which the twin sync has sat since the CUT.
      //
      // HARVESTED, THUS WITHOUT `harvest: false` — the default value is
      // right. The line of a SIBLING by contrast is only supplied;
      // that is set by the sending side (`sendToUser`).
      //
      // SECURE, and that is not caution but §14.7: all three
      // uses of this line ride Secure („Key packages (Type 16)
      // ride Secure with the 31-day management TTL"). The entry thus saves
      // the liveness publication that `publishLiveness` performs for
      // every non-Secure counterpart.
      final deviceLine = deviceLineKey(
          service.identity.userId, service.identity.deviceNodeId);
      runtime.node.pairs.remember(
        deviceLine,
        deriveKDevice(
            kOwn: kOwn, deviceNodeId: service.identity.deviceNodeId),
        outDirection: kDeviceLineDirection,
        inDirection: kDeviceLineDirection,
      );
      runtime.node.setChatMode(deviceLine, secure: true);
    } catch (e) {
      // Without user KEM secrets there is no own line. That is
      // a finding and not operational noise: then this
      // identity syncs with none of its devices, and the user sees on
      // the second device nothing of what he does on the first.
      log?.call('V4.1: no own line for '
          '${shortPairLabel(service.identity.userIdHex)} ($e) — the '
          'twin sync fails for this identity (§14.7), '
          'and with it the device line (§14.1): no key package, '
          'no initial sync, no delegated keys');
    }
  };
  service.v41ArmOwnLine!();

  service.v41NodeCounters = () => (
        wireSent: runtime.node.wireBytesSent,
        wireReceived: runtime.node.wireBytesReceived,
        relayBytes: runtime.node.relayBytes,
        relayCells: runtime.node.relayCells,
      );

  // ── THE SENDING SIDE OF THE ENTRY BRIDGE (§11, gap G-11) ─────────
  //
  // Until today a ContactSeed carried no `s=`: the builder read the
  // V3 peer address list, and that is intentionally empty on this line
  // (`CleonaService.peerSummaries`). MEASURED IN THE FIELD on 10.09.2026 an
  // issued code looked like this — a single, PRIVATE address:
  //
  //     cleona://<userid>?n=Bob&c=b&did=…&a=192.0.2.202:13086
  //
  // Whoever scans that outside that home network has no way into the network.
  // The entry is exactly what is missing without start peers.
  //
  // WHAT IS READ OUT HERE, and why with these predicates:
  //
  //   * `entries.dialCandidates()` instead of `entries.all()`: the order is
  //     already the right one (whoever never failed first, then the
  //     younger publication), resting and expired ones are out,
  //     and the own record does not even get into the supply
  //     (`EntryCache.ownPosition`).
  //   * `externallyDialableAddresses` per record. A start peer with a
  //     private address is of no use to the foreign scanner and incidentally reveals
  //     the topology of the own segment.
  //
  // WHY `externallyDialableAddresses` and not `dialAddressOrder`:
  // the reasoning is at the function itself (`entry_record.dart`),
  // in one sentence — `dialAddressOrder` answers „what can I dial
  // NOW", the ContactSeed asks „what can a STRANGER dial".
  //
  // THE CAP deliberately does NOT stand here but at the builder: it hangs
  // on the format of the code (five start peers, two to three addresses per
  // start peer, zstd-compressed QR), and the format is known by
  // `contact_seed.dart`. Here it is only capped far enough that the list
  // does not grow without limit — `kSeedKandidatenDeckel` is a multiple
  // of the format cap, so that the family grab of the builder still has
  // something to choose from.
  service.v41EntrySeedCandidates = () {
    final out = <EntrySeedCandidate>[];
    for (final r in runtime.node.entries.dialCandidates()) {
      final outside = externallyDialableAddresses(r.addresses);
      if (outside.isEmpty) continue;
      out.add(EntrySeedCandidate(
        nodeIdHex: bytesToHex(r.lNode),
        addresses: outside,
        expiryMs: r.expiryMs,
      ));
      if (out.length >= kSeedCandidatesCap) break;
    }
    return out;
  };

  // ── THE REMAINING FIGURES OF THE DELIVERY LAYER (§25.4, G-10) ────────
  //
  // UNTIL S361 THIS SAID „gap G-2" — a wrong number. G-2 is the
  // propagation of the system channels; the figures are G-10, and this
  // block is exactly the place that closes G-10.
  //
  // WHY A SECOND SET AND NOT THE SAME ONE. The four numbers above
  // are BOOKED: the collector forms the difference to the last glance
  // and carries it over two periods („total" and „today"). These
  // here are STATES — „waiting for pieces", „control queue",
  // „held cells" also fall again, and a sum over them would be
  // no quantity. They are passed through, not added.
  //
  // WHY THEY STAND HERE AND NOT IN THE NODE. The same reason as two
  // screen lines higher: an import edge from `lib/core/tagline/`
  // to the display layer is the layer boundary that
  // `smoke_link_io_milestone` (section 5) guards and that the comment
  // at `V41Node.start` justifies. The set is a RECORD and thus
  // structural — this file builds it without knowing
  // `network_stats.dart`.
  //
  // WHAT THEY HAVE COST UNTIL HERE. `droppedControl`,
  // `maxControlDepth`, `controlFailures`, `droppedEphemeral`,
  // `payloadsAssembled`, `payloadsOpened` and `discarded` were built,
  // measured and stood exclusively in the status line of the node —
  // a log line no user sees. `SecureStore.evicted` and
  // `BlindStore.evicted` had no reader at all, although §21.3.3
  // no. 4 demands them verbatim: „a node that evicts under budget
  // pressure shows this visibly in the network statistics (§25). A
  // silently shrinking delivery layer is the storage variant of the
  // failure mode §1.2 rules out for delivery."
  service.v41NodeGauges = () {
    final n = runtime.node;
    final stream = n.egress.stream;
    return (
      entryRecords: n.entries.size,
      slotsEmitted: n.driver.slotsEmitted,
      slotsSkipped: n.driver.slotsSkipped,
      slotsFailed: n.driver.slotsFailed,
      harvestRuns: n.harvestRuns,
      lookupRuns: n.lookupRuns,
      payloadsAssembled: n.payloadsAssembled,
      payloadsOpened: n.payloadsOpened,
      openTransfers: n.openTransfers,
      piecesDiscarded: n.discardedPieces,
      controlQueueDepth: stream.pendingControl,
      controlQueueMax: stream.maxControlDepth,
      droppedControl: stream.droppedControl,
      droppedEphemeral: stream.droppedEphemeral,
      controlFailures: n.delivery.controlFailures,
      storedCells: n.delivery.store.cellCount,
      storedEvicted: n.delivery.store.evicted,
      blindHeld: n.delivery.blind.count,
      blindEvicted: n.delivery.blind.evicted,
      blindRefused: n.delivery.blind.refused,
    );
  };

  // ── THE PRODUCER OF `placed` (§22.5.1) ───────────────────────────
  //
  // HERE and not in the node: the delivery layer knows no messages,
  // only pairs and bytes. It passes the proof through, the delivery register
  // of the service makes the judgement. Without this one line
  // `notePlaced` would stay without a caller — exactly the state that the
  // lab-only guard carried as a named debt until S357.
  //
  // REGISTERED INSTEAD OF SET (S376, P5 finding 1): since S376 `bindPlacementAcked`
  // APPENDS a sink instead of replacing the previous one. The
  // old contract („a second call REPLACES the first") was incompatible with
  // multi-identity — `attachV41` runs per identity against
  // the same node, and only the last one got its receipts.
  runtime.node.bindPlacementAcked(service.noteV41Placement);
  host.deregistrations.add(
      () => runtime.node.unbindPlacementAcked(service.noteV41Placement));

  // ── AND THE LOCAL OUTBOX (§21.2, gap G-4) ─────────────────────
  //
  // Three lines, three different objects:
  //
  //   1. The drain hangs on the READINESS EDGE. It is the
  //      V4.1 counterpart of the V3 edge `onNetworkChanged`: a
  //      message that was rejected with `notReady` did NOT go
  //      out, and exactly that changes when a relay confirms.
  //      No timer — §21.2 „no timer retry", §5.1 invariant 1.
  //   2./3. The drain needs the fill level of the control queue and
  //      its cap before it enqueues: a Secure resubmission
  //      costs `m x R` = 60 frames at once, the queue holds 120,
  //      and on overflow `CoverStream` discards the OLDEST whole
  //      group — possibly a message that is just regularly
  //      in transit.
  //
  // HERE and not in the node, for the same reason as with
  // `bindPlacementAcked` two lines higher: the queue belongs to the
  // NODE (one socket, one cover cycle), the outbox to the IDENTITY (one
  // plaintext frame, one `K_AB`). `attachV41` is the only place at which
  // both are available.
  //
  // TWO IDENTITIES ON ONE NODE share the queue and thus
  // the cap. That is right and not stingy: there IS only one
  // egress, and whoever enqueues 60 frames twice has 120 in a queue
  // of 120 — regardless of which identity enqueued them.
  service.v41PendingControl = () => runtime.node.pendingControlFrames;
  service.v41ControlBacklogLimit = () => runtime.node.controlBacklogLimit;
  //
  // REGISTERED, NOT SET (S376, P5 finding 1) — as with
  // `bindPlacementAcked` above. A single slot left, with three
  // identities, two of them without the ONLY edge at which a message left lying because of
  // `SendRefusal.notReady` goes out again
  // (§21.2), and without the display of the readiness state (§25.4).
  //
  // ── THE EGRESS CAP CARRIES THAT (re-measured, S376) ─────────────
  //
  // At the edge `flushV41Outbox` now runs N times instead of once. That
  // is no N-fold traffic: EVERY drain asks BEFORE enqueuing
  // `v41PendingControl`/`v41ControlBacklogLimit` — i.e. the live
  // fill level of THE SAME control queue of the node (the two lines
  // above) — and bails out as soon as fewer than `m x R` = 60 frames
  // are free. With a queue of 120 frames at most
  // two resubmissions thus enqueue, whether they come from one identity
  // or from three. What runs N-fold are two counter glances per
  // identity.
  //
  // A `final` VARIABLE FROM A FACTORY, NOT A NESTED FUNCTION
  // (S376, added later). The first version wrote here
  // `void bereitschaftskante(...) => ...` in the middle of the body of
  // `attachV41`. That is an indented DECLARATION, and
  // `smoke_delivery_layer_unwalked_guard` reads it as such: from
  // this line on it was the CARRIER for everything that follows in
  // `attachV41` — and because no one calls it from outside,
  // `onBereitschaftskante`, `ladePrekeyVorrat` and
  // `ladeTagesgeheimnisse` suddenly counted as never entered. The header of that
  // guard already describes exactly this case once, measured on
  // THIS file („the call `setzeAnsageadressen(` counted as a
  // declaration").
  //
  // ONE VARIABLE AND NOT A SECOND EXPRESSION: the deregistration below needs
  // THE SAME object. Two identical-looking closures are in Dart
  // not equal — `removeReadinessListener` would then find nothing, and the
  // dispatcher would keep the entry of a removed identity.
  final readinessEdge = _readinessEdgeFor(service);
  runtime.node.addReadinessListener(readinessEdge);
  host.deregistrations
      .add(() => runtime.node.removeReadinessListener(readinessEdge));

  // ── THE SECOND EDGE OF THE EXIT (S381, 11.09.2026) ───────────────
  //
  // Until S381 the drain of the local outbox hung on EXACTLY ONE edge:
  // the rise of readiness. With `SendRefusal.egressFull` there is
  // a second reason for which a message stays lying — the
  // control queue was full —, and that has nothing to do with readiness.
  // A node that is already `ready` would have waited for a rise
  // that no longer comes.
  //
  // THE SAME FACTORY FORM as above, and for the same reason: the
  // deregistration below needs THE SAME object (two identical-looking
  // closures are not equal in Dart).
  final egressEdge = _egressEdgeFor(service);
  runtime.node.addEgressFreeListener(egressEdge);
  host.deregistrations
      .add(() => runtime.node.removeEgressFreeListener(egressEdge));

  // ── AND THE RESCUE BUNDLE (§13.3, gap G-3) ───────────────────
  //
  // HERE and not in the node, for exactly the same reason as with
  // `bindPlacementAcked` and the outbox above: the bundle line
  // needs BOTH. The tags and the storing belong to the NODE (one
  // cover cycle, one routing table), the content to the IDENTITY (one
  // master seed, one contact list). `attachV41` is the only place at
  // which both are available.
  //
  // WHAT THESE LINES CLOSE, measured: `recovery/recovery_keys.dart`
  // had since S360 **eleven derivations and zero callers in `lib/`** —
  // tags no one computed, for a line no one populated.
  // The call edge begins here.
  //
  // NO OWN TIMER: `attach()` hangs the line on
  // `V41Node.addSlotTick`, i.e. on the cover slot that the node beats anyway
  // (§13.3.4 verbatim: „it hangs off a tick the node keeps
  // anyway (§19: no polling)").
  final bundle = RecoveryBundleLine(
    node: runtime.node,
    source: service.recoveryBundleMaterial,
    log: (s) => runtime.node.log(s),
  )..attach();
  service.v41RecoveryBundle = bundle;

  // AND THE SEARCH, if this start is a recovery case
  // (§13.1.3: seed yes, counterpart no). The check costs two
  // counter glances; a normally used account never makes a request.
  // It stands HERE because it is the counterpart of `primeV41Pairs` below:
  // one starts when there ARE pairs, this one when there are none.
  service.beginRecoveryBundleHarvestIfLost();
  // AND THE LINE INTO THE LOG. §13.3.4 demands visibility („An expired
  // bundle must not lapse silently"); the UI for it is a
  // separate, open item. Until then the state at least stands in the
  // field log — otherwise a missing bundle is noticed at the earliest after 31
  // days, i.e. when it is gone.
  runtime.node.log('V4.1: ${service.recoveryBundleStatus}');

  // THE HARVEST NEEDS ALL PAIR KEYS, not only those of the contacts
  // this node happens to have written to already (B-23). Without
  // this call a freshly started node is deaf to incoming
  // messages until the user sends something himself.
  final pairs = service.primeV41Pairs();

  // ── AND THE INVITATION LINES (§15.3.2) ────────────────────────────
  //
  // The counterpart of `primeV41Pairs` for first contact: without this
  // call the issuer does not harvest the tags of its own invitations,
  // and every incoming contact request lies at the responsible
  // relays until it expires — both sides would see only silence.
  final lines = service.armV41InviteLines();

  // ── THE PREKEY SUPPLY SURVIVES THE RESTART (§21.4, §4.6) ─────────
  //
  // §21.4 demands it verbatim „mandatorily under the DB key", and §4.6
  // point 3 gives the reason why: retention must outlast the full delivery period,
  // „or cells from days 9-14 become unopenable (silent
  // message loss)". Until 30.08. `PrekeyPool` had no
  // serialisation at all — the supply disappeared at every process start, and the
  // failure was invisible, because the sender silently falls back to the long-lived
  // key (step 3 of the ladder).
  //
  // IDENTITY DIRECTORY, not node directory: `v41_entries.json`
  // and `v41_ages.json` lie device-bound next to the node keys
  // (§21.4), the prekeys by contrast hang on the identity — like the
  // pairs and `K_AB`. With multi-identity every identity needs its
  // own store, otherwise two identities mix their counting spaces and
  // assign the same index twice.
  //
  // THE STORE CONTAINS `sk_i` and the daily secrets — S372: no longer
  // one file each (`v41_prekeys.json.enc`/`v41_daily_secrets.json.enc`)
  // under `FileEncryption`, but the areas [bereichV41Prekeys]/
  // [bereichV41DailySecrets] in `MessageStore` (`service.storeOrNull`) —
  // the same identity-derived key as before
  // (`deriveFileEncKey`, now as `PRAGMA hexkey` of the store), only without
  // the own files and their own full write per save cycle.
  // None of it ever in plaintext. Details including the old-stock takeover
  // are at [ladePrekeyVorrat]/[ladeTagesgeheimnisse] — OWN
  // functions (S372), so that a test can run them without the full
  // `attachV41` setup (real `V41Node`, real sockets) against a real
  // profile, the same seam as with `KaltstartRotationsTor`.
  final deposit = service.storeOrNull;
  ladePrekeyPool(service: service, host: host, log: log);
  ladeDailySecrets(service: service, host: host, log: log);
  // LOADING HAPPENS BEFORE THE FIRST SEND/RECEIVE. A second load into
  // a running host is rejected by the supplies themselves (`acceptsSnapshot`),
  // so that an old stored item does not revive an already deleted `sk_i`.
  // ONE CYCLE FOR BOTH STORES, not two. They change at
  // the same occasions (an opened cell consumes a prekey
  // AND can learn a daily secret), and two timers would be two
  // rhythms that can diverge.
  //
  // ── AND SINCE S376 IT HAS A HANDLE (P5 finding 3) ──────────────
  //
  // Until then a bare `Timer.periodic(...)` stood here: not in the
  // return value, in no variable, with no `cancel` in the whole
  // tree. The reasoning why that does not work already stands twice
  // in this file — at [V41Runtime.entryPersist] and at
  // `portMapping`. It applies here just the same, and more sharply: this cycle
  // runs per IDENTITY, the other two per process.
  //
  // TWO PARTS, because they have two life situations. `sichern()` writes
  // what only this cycle writes — prekey supply and daily secrets;
  // it is the part that [V41Host.dispose] must run one last time.
  // The invitation lines belong to running operation and not to the
  // final run: a host that is being shut down needs no fresh
  // lines any more.
  // FROM A FACTORY, for the same reason as with
  // `bereitschaftskante` further above: an indented
  // `void sichern() {` declaration in the middle of the body would take over, from this
  // line, the carriership for everything that follows.
  final save = _saverFor(
    host: host,
    deposit: deposit,
    key: keyOneLiner,
    log: log,
  );

  host.saveNow = save;
  host.saveTick = Timer.periodic(const Duration(seconds: 30), (_) {
    // ── THE HARVEST WINDOW OF AN INVITATION EXPIRES (§15.3.3) ─────────
    //
    // An expired or revoked invitation must LOSE its line,
    // otherwise it stays open until the next restart — and
    // §15.1 explicitly calls an unlimited, irrevocable invitation
    // a „permanent write right into the inbox".
    //
    // IN THE EXISTING CYCLE AND WITHOUT A SECOND TIMER. The call is cheap
    // as long as nothing has changed: `armV41InviteLines` first compares
    // the identifier set and bails out immediately if unchanged, without
    // `forgetPeer` — that is essential, because `forgetPeer` deletes the
    // have list of the harvest (B-32), and throwing it away every 30 s would mean
    // fetching again at every cycle everything the node already has.
    try {
      service.armV41InviteLines();
    } catch (e) {
      log?.call('§15.3.2: invitation lines not updated ($e)');
    }
    save();
  });

  // S369: here stood `${service.displayName}`. The callback `log` is bound to
  // `log.info` (`service_daemon.dart:764, :880, :1124`, in the
  // UI `main.dart:2352` among others) — the line thus wrote the
  // display name at `info`, against the owner decision of
  // 02.09.2026. Measured on a real daemon run on 06.09.2026:
  //
  //   "[INFO ] [daemon] V4.1-Zustellung eingehaengt fuer Alice — …"
  //
  // The guard did not see it: it is NEITHER `_log.info` NOR a
  // call on `.info|warn|error|event`, but a function callback.
  // The callback knows only ONE level, so there is no `debug` here
  // to which the name could move — it drops out without replacement. The
  // identifier takes its place; it stands on the wire anyway.
  // ── HOW MANY IDENTITIES NOW HANG ON THE DISPATCHER (S376, finding 1)
  //
  // NOT ONLY A MEASURE FOR THE GUARD. Exactly these four numbers
  // were the finding: until S376 the node's callbacks were
  // single slots, every further identity threw out the previous one — and
  // that was visible NOWHERE. No log, no counter, no display; the
  // failure only showed in `placed` not arriving for two of three
  // identities. One line per attach operation turns that into
  // an observation that stands in the field log before anyone looks for it.
  //
  // NO CYCLE AND NO TRAFFIC: it happens at the edge `attachV41`, i.e.
  // once per identity and process start.
  //
  // IF THE FOUR NUMBERS DIFFER FROM EACH OTHER, that is a finding: they
  // are set in the same function, there is no path on which
  // an identity would get one edge and not the other.
  runtime.node.log('V4.1: ${runtime.node.placementSinksNumber} identity(ies) '
      'at the placement distributor, ${runtime.node.readinessSinksNumber} at the '
      'readiness edge, ${runtime.node.harvestRunSinksNumber} at the '
      'harvest reporter, ${runtime.node.harvestHorizonNumber} harvest horizon(s)');

  log?.call('V4.1 delivery attached for '
      '${shortPairLabel(service.identity.userIdHex)} — '
      'the switch in the body is active from now on'
      '${pairs > 0 ? ' ($pairs pair key(s)' : ''}'
      '${pairs > 0 && lines > 0 ? ', ' : ''}'
      '${lines > 0 ? '$lines invitation line(s)' : ''}'
      '${pairs > 0 ? ')' : ''}');
  return host;
}

/// Only so that the import of `OqsFFI` does not count as unused: the
/// PQ side must be initialised before the first daily capsule is
/// formed.
void ensurePqReady() => OqsFFI().init();

/// Connects a running node with a service: sender MAC and
/// RECEIVE SINK.
///
/// ── WHY THIS IS A FUNCTION OF ITS OWN (S360) ───────────────────────
///
/// Both stood in the body of [attachV41] and were thus only reachable via the
/// whole setup — with LAN entry, cold start and rendezvous.
/// A guard that wants to measure the receiving side on REAL nodes
/// therefore had to REBUILD it, and a rebuilt guard measures
/// itself.
///
/// Here stands the seam at which three decisions are made that cannot be made
/// anywhere else: whether a payload that cannot be opened gets a line,
/// whether the pair identifier is passed up, and the
/// type binding of the invitation line (§15.3.2). All three need
/// at the same time the opened frame AND the tag under which harvesting
/// happened — one level lower there is no message type, one level
/// higher no tag.
void attachV41Sink({
  required V41Node node,
  required V41Host host,
  required CleonaService service,
  void Function(String)? log,
}) {
  // ── AUTHENTICATE INSTEAD OF SIGN (§4.4.3, S352) ─────────────────
  //
  // HERE STOOD AN ED25519 SIGNATURE over every application frame. It
  // directly contradicted the normative signature rule: §4.4.3 lists
  // „1:1 message" and „Group leg (pairwise)" both with **none** and
  // explains: „**Cleona is deniable.** Without a signature in the
  // message path, no receiver can prove to a third party that a specific
  // person said something." With the 64 B the receiver held exactly
  // this proof — transferable to any third party.
  //
  // In its place comes what the same line of §4.4.3 provides: the
  // MAC under `K_AB`. It closes the same gap (B-20: a freely
  // claimed `senderUserId`), because only the two parties of the
  // pair can form it — and it proves nothing to a third party, because
  // BOTH can form it.
  //
  // THE KEY COMES FROM THE PAIR REGISTRY, not from a second
  // derivation: `sendToUser` enters it there with `rememberPeer` before
  // it calls `sendFrame`, and `secureTag` reads it from the same place.
  // An own derivation in the host could deviate from that — and then the
  // stored item would lie under a tag that does not match the MAC in the frame.
  host.pairKeyFor = (peer) => node.pairs.kAbFor(peer);

  // THE SENDER FROM THE TAG LINE IS PASSED THROUGH (path A, S352).
  // Until here `acceptSealed` threw it away (`accept(peer: '')`), although
  // the harvest knew it — that was the actual reason for the
  // signature. In the Secure path [peer] now carries the pair identifier
  // `<own64>/<foreign64>`; in the Speed path it is empty, because there is no
  // field tag there (§4.3).
  node.addSink((peer, sealed) {
    // COUNTER STATE BEFORE THE ATTEMPT — the difference afterwards says WHERE it
    // failed.
    final oe = host.opener;
    final beforeThrottled = oe?.throttled ?? 0;
    final beforeUnresolved = oe?.unresolvedSelectors ?? 0;
    final beforeUnopened = oe?.unopened ?? 0;
    // S362: the case „addressed to US and still closed" has had its own counter
    // since the predecessor change. Without it it fell here
    // under „Selektor passte, AEAD fiel" and could not be told apart from a corrupted
    // ciphertext.
    final beforeForUnsTo = oe?.sealedForMeButUnopened ?? 0;

    final onto = host.acceptSealed(peer: peer, sealed: sealed);
    if (onto == null) {
      // ── THE ONE SILENT LOSS THAT MUST NOT STAY SILENT ────────
      //
      // E-83 keeps errors silent, because a line per discarded cell would be
      // a channel to the outside. THIS case is a different one: a
      // payload that was completely reassembled on the tag line of A PAIR
      // is by construction meant for us —
      // `secureTag` cannot be computed without `K_AB` (§10.1), and a
      // cover cell does not assemble over `m x R` stored items. The
      // sender is fixed with [peer] and is logged one line further anyway
      // (`Selbsternte`, `Ernte fuer`).
      //
      // WHAT THE MISSING LINE COST, measured on 30.08.: the phone
      // ran on the state before `616779ad` (seal without the 4-B selector and
      // without AAD), the nodes on the state after it. Every Secure message
      // arrived, was stored, harvested and reassembled — and died in
      // `MessageOpener.open`. In the log that could not be told apart from „nothing
      // came".
      //
      // ONLY THE SECURE PATH. In the Speed path [peer] is empty (§4.3, no
      // field tag) — there a payload that cannot be opened is the normal case
      // and stays silent.
      // ALSO IN THE SPEED PATH (30.08., second version). Here stood
      // `peer.isNotEmpty`, i.e. only Secure — with the reasoning that a
      // payload that cannot be opened is the normal case in the Speed path.
      // That was wrong and cost a measurement: the filter only applies
      // when a payload is COMPLETELY REASSEMBLED, and
      // that is no cover cell — padding traffic does not assemble over
      // several pieces into an addressed payload. In the field
      // on 30.08.: `zusammengesetzt 3, geoeffnet 0` on node1, without
      // a single line naming the reason.
      if (oe != null) {
        // Order not arbitrary: `message_seal.dart` increments BOTH counters on an
        // unresolvable selector, so the more specific one must
        // be checked first.
        final reason = oe.throttled > beforeThrottled
            ? 'cap applied (maxProbesPerSecond)'
            : oe.unresolvedSelectors > beforeUnresolved
                ? 'no prekey candidate matched — selector/seal format '
                    '(other side on a different version?)'
                : oe.sealedForMeButUnopened > beforeForUnsTo
                    ? 'addressed to us, but no key opened it '
                        '— capsule against a KEM generation that we no '
                        'longer hold (§4.5.4: current + one previous), '
                        'or corrupted ciphertext. The sender holds a '
                        'too old copy of our keys and does not learn of it '
                        '(§4.5.4: "the loss is silent"). '
                        'Since process start: ${oe.sealedForMeButUnopened}'
                    : oe.unopened > beforeUnopened
                        ? 'selector matched, AEAD failed — capsule or '
                            'key'
                        : 'opened, but no application frame '
                            '(late delivery or unknown kind)';
        log?.call('V4.1 UNOPENED from '
            '${peer.isEmpty ? 'speed (no field tag)' : shortPairLabel(peer)}: '
            '${sealed.length} B assembled — $reason');
      }
      return false;
    }
    // ── THE INVITATION LINE IS NO PAIR LINE (§15.3.2, §15.4) ─────
    //
    // Two things distinguish a cell that arrived under an invitation tag
    // from every other — and both must be decided HERE,
    // because further up no one knows any more under which tag
    // harvesting happened.
    //
    // **1. The pair identifier is NOT passed through.** Here it proves
    // no sender. `verifyV41Sender` checks `peer == '<own>/<foreign>'`
    // and would judge an invitation identifier as `forged` — the
    // request would drop away. But even without this check passing
    // it through would be wrong: the tag is derived from `K_inv(i)`, and with the class
    // „published" everyone holds that (§15.3.1). It says „someone
    // with this invitation", not „this person". An empty identifier
    // leads to `unverifiable` -> `OuterSigStatus.skippedBootstrap`, and
    // that is the honest information. (Here it said that `_handleContactRequestV3`
    // thereby allowed no silent key takeover — the handler was
    // dropped with S388-BAU-KONTAKT; a CONTACT_REQUEST no longer has a
    // receiver.)
    //
    // **2. The type binding from §15.3.2, normative:** „A cell harvested under
    // `tag_I(i,e)` **MUST** be interpreted as a contact request. Every
    // other inner message type is **discarded**." It is needed because the
    // seal carries no type binding: whoever knows `K_inv(i)` can seal
    // ANY payload under it — without this rule one could slip a call INVITE
    // to a stranger and the phone would ring
    // for every holder of a printed business card. §15.6 lists it
    // explicitly as a „checkable invariant for §28".
    //
    // THE CHECK HAPPENS AFTER OPENING, and only that works: before,
    // no one sees a type. Exactly for that reason §15.3.2 says the rule is
    // „locally enforceable" and belongs normatively demanded.
    final outInvitation = isInvitePeer(onto.peer);
    if (outInvitation) {
      final allowed = isContactRequestFrame(onto.frame);
      if (!allowed) {
        host.inviteTypeViolations++;
        log?.call('V4.1 INVITATION LINE: cell under '
            '${onto.peer.substring(0, 15)}… is NOT a contact request — '
            'discarded (§15.3.2 type binding, '
            '${host.inviteTypeViolations} so far)');
        return false;
      }
    }
    // ── THE ASSIGNMENT GOES ALONG, THE SENDER PROOF DOES NOT (§15.3.3) ────
    //
    // Until S361 the information „under which invitation did this arrive?"
    // ended here: the identifier was set to `''` and was gone forever one line
    // later. That was right for the PAIR IDENTIFIER
    // (reasoning above) and wrong for the ASSIGNMENT — §15.3.3
    // demands it explicitly: „Every incoming request is shown
    // attributed to the invitation … If a URI leaks, the issuer sees
    // *which* invitation is flooding, and revokes exactly that one."
    // And without it §15.4 cannot redeem its single-use invitation:
    // `consumeSingleUse` had not a single caller in `lib/`.
    //
    // TWO FIELDS, NOT ONE. The difference is the whole point:
    // [peer] is a PROOF (the tag cannot be computed without `K_AB`),
    // [inviteLine] is an ASSIGNMENT (the tag is derived from `K_inv(i)`,
    // and with the class „published" everyone holds that). If they were
    // the same field, `verifyV41Sender` would read the assignment as
    // sender proof and judge `forged` — the request would drop away.
    // Kept separate, the verdict stays `skippedBootstrap`, i.e.
    // still NO silent key takeover, and the assignment
    // still reaches the place where acceptance is decided.
    //
    // Deliberately not awaited: the node stands here in the receive path
    // of a cell, and the cycle must not hang on the application
    // (invariant 1). Errors land in the zone handler of the service.
    unawaited(service.acceptV41Frame(
        // The ASSIGNMENT to the invitation (`inviteLine`) had as its only
        // consumer `_handleContactRequestV3` and was dropped with it
        // (S388-BAU-KONTAKT).
        peer: outInvitation ? '' : onto.peer,
        mac: onto.mac,
        frameBytes: onto.frame));
    return true;
  });
}

/// The type binding of the invitation line (§15.3.2, normative).
///
/// PUBLIC, because §15.3.2 explicitly lists it as a „testable invariant for
/// the test strategy (§28)": „A cell under an invitation tag whose
/// inner type is not a contact request is discarded and counted against
/// the buffer." A rule no guard can call is no
/// checkable invariant.
///
/// True exactly when [frame] is an application frame with
/// `MTV3_CONTACT_REQUEST`.
///
/// ── WHY THE CHECK STANDS HERE AND NOT IN THE SERVICE ────────────────
///
/// It must lie between „opened" and „handed to the application".
/// Further down (in the delivery layer) there is no message type,
/// here there is both. The service could since S361 also make it
/// — it now gets the assignment handed as `inviteLine` —,
/// but it must not: §15.3.2 demands that a cell with
/// a wrong inner type is DISCARDED and counts against the buffer, and
/// „discarded" means it does not reach the application at all. A
/// check behind the hand-over would be a filter, not a bolt.
///
/// A MALFORMED FRAME IS NO CONTACT REQUEST and thus falls
/// under the same rule — `false`, discarded, counted. It must not be
/// passed on: the rule reads „every other inner message type
/// is discarded", and „no readable type at all" is the stronger case.
bool isContactRequestFrame(Uint8List frame) {
  try {
    return pb.ApplicationFrameV3.fromBuffer(frame).messageType ==
        pe.MessageTypeV3.MTV3_CONTACT_REQUEST;
  } catch (_) {
    return false;
  }
}


// ══════════════════════════════════════════════════════════════════════
// THE TWO EDGES OF THE NODE (S376, P5 finding 5)
// ══════════════════════════════════════════════════════════════════════
//
// ── WHY THEY STAND OVER THE RUNTIME AND NOT AT THE SERVICE ──────────
//
// Both callbacks were set in `attachV41`, and `attachV41` runs
// PER IDENTITY. The caller loops of the three entry points also run
// per identity:
//
//   service_daemon.dart  `for (final service in _services.values)`
//                        (Windows/macOS poll AND Linux `ip monitor`)
//   main.dart            `for (final service in _inProcessServices.values)`
//                        in the debounce timer of the connectivity observer
//   main.dart            `for (…) service.setAppResumed(isResumed)`
//
// What ran N times in the process however belongs entirely to the NODE — there is one
// socket, one session set, one entry record, one LAN call.
// With N = 3 identities and ONE network change that was:
//
//   3 x `portMapping.onNetworkChanged()`   (clear announcement, search anew)
//   3 x `localAddresses()`                 (enumerate interfaces)
//   3 x `observed.clearAll()`
//   3 x `setzeAnsageadressen(...)`
//   3 x `V41Node.onNetworkChanged()`       — ALL sessions every time
//   3 x `announceOwnEntry(vorrangig: true)` — on the wire
//   3 x `lanEntry.announceNow()`            — on the wire
//
// The last two are network traffic and thus a violation of
// work rule 5. The fifth is worse than redundant: the second and
// third pass tear down sessions that the partner selection has just rebuilt after the
// first pass.
//
// ── WHO RUNS THE NODE PART ───────────────────────────────────────
//
// The PROCESS, once, and then the service loop with
// `triggerNodeReset: false`. Exactly for that this parameter exists: its
// contract in `service_interface.dart` says verbatim „Daemon-style
// callers that already invoke `node.onNetworkChanged()` once for all
// identities should pass `false` to avoid the N+1 multiplication (one
// node-reset per identity on top of the direct one)". The three
// entry points ALWAYS passed it; since S360 it was
// ignored, and the comment at the evaluation justified that by saying
// that there was „exactly ONE seam" to the node. There is exactly one seam —
// but N services that reach through it.

/// The NODE PART of a network change (§22.6). Once per process.
///
/// ORDER, and it is not arbitrary: first clear the port mapping,
/// then set the new announcement, then drop the sessions,
/// then propagate the record. The other way round the
/// node would still announce the dead address in the window in between — and exactly
/// this record would be harvested by the neighbours it is just
/// dialling anew.
Future<void> v41NodeNetworkChange(V41Runtime runtime,
    {void Function(String)? log}) async {
  // FIRST THE PORT MAPPING, and that is part of the same order
  // as below (S373): the mapping of the old network points to a
  // gateway this node no longer reaches. If it were only cleared
  // after `announceOwnEntry`, exactly the record carrying the dead
  // external address would go out in the window in between — and
  // the neighbours that are just being dialled anew would harvest it.
  // `onNetworkChanged` clears the announcement immediately and searches for the new
  // mapping alongside (it can take minutes).
  await runtime.portMapping?.onNetworkChanged();
  final ips = await runtime.localAddresses();
  // ── THE BOOK FIRST, THEN THE ANNOUNCEMENT (§17.3, S373) ──────────────
  //
  // Since the announcement carries the observed external address along, the
  // order here is strict: `V41Node.onNetworkChanged` further below
  // empties the address book — but ONLY AFTER `setzeAnsageadressen`. Without
  // this line the call below would write the external address of the
  // DEAD network into the record and `announceOwnEntry(vorrangig)`
  // would carry it out immediately. Exactly that is what the header of
  // `ObservedAddressBook.clearAll` warns about: a unanimously wrong candidate
  // is the most expensive form of wrong.
  //
  // The second `clearAll()` in `onNetworkChanged` stays and is
  // without consequence — it is the node's self-protection for the case that
  // it is called via a path other than this seam.
  runtime.node.host.observed.clearAll();
  setAnnounceAddresses(
      node: runtime.node,
      dialable: ips,
      port: runtime.node.advertisePort,
      log: log);
  runtime.node.onNetworkChanged();
  // WITH PRIORITY. The record is the only thing that tells a neighbour
  // where this node can be reached now; it must not queue behind
  // the ordinary cycle.
  runtime.node.announceOwnEntry(priority: true);
  // And the LAN call: in the new segment there is with some
  // probability a neighbour that has never heard this node.
  // Step 2 of the entry cascade, the same as at start.
  runtime.lanEntry?.announceNow();
}

/// The NODE PART of a return to foreground (§22.6, variant C).
/// Once per process.
///
/// WITHOUT `setzeAnsageadressen`, without session teardown, without announcement: a
/// return to foreground is no network change. The address stays valid,
/// the partners stay — what is to be caught up is solely what
/// remained lying at the responsible relays during the absence.
void v41NodeForeground(V41Runtime runtime, {String reason = 'Vordergrund'}) {
  runtime.node.catchUpHarvest(reason: reason);
}


// ══════════════════════════════════════════════════════════════════════
// TWO FACTORIES, SO THAT THE BODY OF `attachV41` CARRIES NO DECLARATION
// ══════════════════════════════════════════════════════════════════════
//
// Until S376 both closures stood as indented
// `void name(...)` declarations IN the body of [attachV41]. That is
// valid Dart and still wrong at this place: an indented
// declaration takes over, for `smoke_delivery_layer_unwalked_guard`, from
// its line on the CARRIERSHIP, and everything that follows in the body
// then hangs on a carrier no one calls from outside. Measured on
// 08.09.2026: three symbols (`onBereitschaftskante`, `ladePrekeyVorrat`,
// `ladeTagesgeheimnisse`) suddenly counted as never entered, although nothing
// had changed in their use.
//
// As PRIVATE functions at the end of the file they carry nothing away: they stand
// behind [attachV41], and their name starts with `_`.

/// Builds the readiness edge of ONE identity.
///
/// The return value is the object that is registered AND deregistered — a
/// second call would yield a different closure, and
/// `removeReadinessListener` would not find it again.
void Function(Readiness, Readiness) _readinessEdgeFor(
        CleonaService service) =>
    (Readiness before, Readiness after) => onReadinessEdge(
          before: before,
          after: after,
          outflow: (reason) => service.flushV41Outbox(reason: reason),
          report: service.notifyStateChanged,
        );

/// Builds the final run of ONE identity: prekey supply and
/// daily secrets into the store.
///
/// The body is unchanged that of the 30-s cycle; it stands here because
/// [V41Host.dispose] must run it one last time and `attachV41` needs it
/// as a value for that.
void Function() _saverFor({
  required V41Host host,
  required MessageStore? deposit,
  required String key,
  void Function(String)? log,
}) =>
    () {
    if (host.prekeyStateDirty) {
      try {
        // No `await` may lie between the export and the receipt —
        // `putEntry` writes synchronously (SQLite transaction), which is why
        // the mark is only reset AFTER the successful write.
        // A failure leaves it standing and the next cycle tries
        // again.
        deposit?.putEntry(
            areaV41Prekeys, key, host.exportPrekeyState());
        host.markPrekeyStateSaved();
      } catch (e) {
        log?.call('V4.1: prekey pool cannot be saved ($e)');
      }
    }
    // ONLY ON ACTUAL CHANGE (S366). Until then an UNCONDITIONAL
    // write stood here, and the comment next to it justified
    // that with "no second dirty mark that someone forgets to set".
    // The objection was right and has remained - the solution is therefore
    // no mark but a comparison on the PLAINTEXT state
    // (`MessageOpener.geaenderterStand`, written out there). As measured,
    // the old path at a 30 s cycle caused 2880 encryptions and 2880
    // writes per day, almost all with the same content.
    //
    // THE CYCLE STAYS, because it does more than write: `geaenderterStand`
    // calls `toJson` and thus `_verfalleneWegwerfen` - the expiry of the
    // daily secrets hangs on exactly this call.
    //
    // CONFIRMATION ONLY HAPPENS AFTER WRITING. A failure leaves the
    // comparison value standing, the next cycle tries again -
    // the same construction as for the supply above.
    final o = host.opener;
    if (o != null) {
      final state = o.changedState(now: DateTime.now().toUtc());
      if (state != null) {
        try {
          deposit?.putEntry(areaV41DailySecrets, key, state);
          o.depositConfirmed(state);
        } catch (e) {
          log?.call('V4.1: daily secrets cannot be saved ($e)');
        }
      }
    }
    };
