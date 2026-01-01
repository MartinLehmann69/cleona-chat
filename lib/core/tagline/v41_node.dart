// The running V4.1 node — the place where library becomes operation.
//
// Up to here there were modules and tests. What was missing was a process that
// by itself opens a port, accepts connections, sends on the tick and
// assigns what comes in. That is this file, and it is deliberately a
// COMPOSITION: it invents nothing, it plugs together.
//
// WHAT IT PLUGS TOGETHER
//
//   LinkHost (AP-3a)          sockets, handshake, sessions
//   -> per session one CellTransport     frames in and out
//   -> SpeedEgress + CoverStream         when and via whom something goes out
//   -> DeliveryNode                      what happens with incoming traffic
//   -> SlotDriver                        the clock
//
// A PROPERTY ONE COULD LOSE HERE. The slot plan draws
// the partner (invariant 4). If connections are added or drop away,
// the PARTNER COUNT changes — that is allowed because it hangs on
// reachability and not on whether there is something to send. Whoever
// instead made the partner choice depend on the queue here would have
// silently lost the invariant.
//
// THE ONION AROUND THE LOOKUPS HAS BEEN IN SINCE S376 (E-L, §9.1 finding 1).
//
// Until 08.09.2026 this stood here: "the responsibility lookups do not yet
// run via the onion (E-L) — that needs a peer inventory
// that goes beyond the own sessions. This node only knows
// who has connected to it." The sentence was right and stood for TWO
// weeks next to an architecture document that listed E-L as closed in three places
// (§9.1, appendix A, B-15) — the module header was the
// only place in the project where the truth stood, and it is not opened when
// reading the architecture.
//
// The named prerequisite has become not a prerequisite but a CONDITION:
// [_blindrelaisKette] draws the blind relays uniformly from the
// routing table, excluding the own partners. If the node knows
// fewer of them than shells are needed, there is no chain — then
// the lookup is omitted and counted ([lookupsOhneBlindrelais]),
// instead of going out in the open.
//
// SINCE S377 THERE ARE TWO SHELLS, i.e. two different blind relays
// in a row (`kLookupOnionShells`, owner decision V-9a of
// 09.09.2026). An arrangement thus needs three nodes instead of two. The
// number is the adjusting screw for the lookup traffic and stands with its
// measured price at `kLookupOnionShells` in `secure_frames.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/bulk/bulk_cache.dart' show BulkCache;
import 'package:cleona/core/bulk/bulk_egress.dart' show BulkEgress;
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/link/admission.dart';
import 'package:cleona/core/link/connect.dart';
import 'package:cleona/core/link/node_keys.dart';
import 'package:cleona/core/link_io/d_socket.dart';
import 'package:cleona/core/link_io/link_demux.dart';
import 'package:cleona/core/link_io/link_host.dart';
import 'package:cleona/core/link_io/tcp_listener.dart';
import 'package:cleona/core/link_io/udp_sockets.dart' show LinkAddressFamily;
import 'package:cleona/core/sync/aggregate.dart';
import 'package:cleona/core/sync/cover_stream.dart';
import 'package:cleona/core/util/uplink_state.dart';

import 'cell_transport.dart';
import 'frame_split.dart';
import 'secure_frames.dart';
import 'delivery_node.dart';
import 'eligibility.dart';
import 'harvest_horizon.dart';
import 'harvest_memo.dart';
import 'lan_entry.dart';
import 'lan_segment.dart';
import '../link/frame.dart';
import 'package:cleona/core/sync/entry_record.dart';
import 'entry_set_latch.dart';
import 'reassembly.dart';
import 'package:cleona/core/bulk/responsibility.dart';
import 'secure_mode.dart';
import 'delivery_api.dart';
import 'liveness.dart';
import 'lookup.dart';
import 'onion.dart';
import 'pair_registry.dart';
import 'package:cleona/core/sync/partition.dart';
import 'partner_policy.dart';
import 'readiness.dart';
import 'reply_block_resolver.dart';
import 'routing_table.dart';
import 'slot_driver.dart';
import 'speed_egress.dart';
import 'package:cleona/core/sync/delivery_params.dart' show kDeliveryFamilies;

/// The harvest order: first the pairs with fresh traffic, then the
/// cold ones in turn.
///
/// PURE FUNCTION, expressly pulled out. The property at stake
/// here — that the waiting time of a RUNNING conversation does not grow with the
/// contact count — is the only one this design promises,
/// and it deserves to be tested, not claimed. In the node itself it could
/// only be tested via a complete node with sockets; the
/// existing harvest suites therefore replicate the logic, and a
/// replica measures a copy that can drift.
///
/// [activePointer] and [coldPointer] move separately: the active set can
/// change between two runs, a shared pointer would then point to
/// the wrong position.
({List<String> active, List<String> cold, List<String> ordered}) harvestRank({
  required List<String> all,
  required Map<String, DateTime> lastTraffic,
  required DateTime current,
  required int activePointer,
  required int coldPointer,
  Duration activeWindow = V41Node.activeWindow,
  bool coldFirst = false,
}) {
  final active = <String>[];
  final cold = <String>[];
  for (final p in all) {
    final z = lastTraffic[p];
    if (z != null && current.difference(z) < activeWindow) {
      active.add(p);
    } else {
      cold.add(p);
    }
  }
  // Round-robin also WITHIN the active set: otherwise the second
  // running conversation starves behind the first.
  final activeRotated = <String>[
    if (active.isNotEmpty) ...[
      ...active.skip(activePointer % active.length),
      ...active.take(activePointer % active.length),
    ],
  ];
  final coldRotated = <String>[
    if (cold.isNotEmpty) ...[
      ...cold.skip(coldPointer % cold.length),
      ...cold.take(coldPointer % cold.length),
    ],
  ];
  // ── [kaltZuerst] — THE THROTTLED RUN ALTERNATES THE RANKS (S382) ──
  //
  // MEASURED ON 12.09.2026, two nodes, same build, same day, the
  // only difference was the control queue:
  //
  //   Node1  407 waiting control frames (above the throttle of 128),
  //          cap 1 instead of 3 — the throttle message is in the log
  //          -> 50 harvest runs, ALL to the same active pair,
  //             ZERO to an invitation line
  //   Node2  4 waiting frames (below the throttle), full cap 3
  //          -> 200 active, 5 x `invite:8`, 11 x device line, 30 x own
  //
  //   (The status line writes `Kontrollschlange wartend/Hoechststand` —
  //   the denominator is `maxControlDepth`, a high-water mark, NOT the
  //   cap. The cap is `kMaxControlBacklog` everywhere.)
  //
  // Node2 harvested its invitation line every 3:46 to 6:31 min, Node1
  // not at all.
  //
  // WHY THIS CANNOT STOP WITHOUT THIS SWITCH: an
  // invitation line by construction NEVER has traffic — it is created empty
  // and waits for the first stranger. It therefore always stands in the cold
  // rank. If the run is throttled, exactly ONE request goes out
  // (`kHarvestForcedRequests`), a pair needs three — the one is
  // used up before the cold rank even begins. So as long as
  // any conversation runs AND the queue stands, no
  // first contact arrives. Silence on both sides, without an error message.
  //
  // THE DOCUMENT REQUIRES THIS HARVEST, §15.2 step 2 verbatim: "Bob
  // harvests it, the user decides (§15.4)." The measured state is a
  // conformance violation, not design latitude. The ORDER, on the other hand,
  // is not in the document — §9.2 only regulates which RELAY is asked per pair
  // ("harvest samples the responsible set … advancing a
  // per-peer offset"), not which PAIR. That is why a
  // code change without a document change suffices here.
  //
  // NO NEW METADATA CLASS, and that is the reason why it is solved this way and
  // not via a priority for invitation lines: an
  // unthrottled node queries both ranks anyway (Node2 above), and
  // every resting contact is "cold" too. A relay cannot read from the
  // alternation that this node is waiting for a first contact.
  // A priority FOR invitation tags could do exactly that — it
  // would stand against §8/§6 and is therefore not built.
  //
  // WHAT IT COSTS: no additional egress — it stays at one
  // request per throttled run. Paid for in latency of the ACTIVE
  // conversation: its harvest only gets its turn every second throttled run.
  // That is the intended trade — a running conversation waits
  // one run longer, a first contact arrives at all.
  //
  // DEFAULT `false`: the unthrottled run keeps its order
  // unchanged (active first). `smoke_v41_harvest_rank.dart` checks
  // exactly that and stays valid.
  final ordered = <String>[
    if (coldFirst) ...[...coldRotated, ...activeRotated]
    else ...[...activeRotated, ...coldRotated],
  ];
  return (active: active, cold: cold, ordered: ordered);
}

/// A node that really operates the V4.1 delivery layer.
final class V41Node implements V41Delivery {
  final LinkHost host;
  final NodeKeys keys;
  final void Function(String) log;

  /// The level-D cookie table of this node (§17.4).
  ///
  /// ── WHY IT HANGS HERE AND NOT ON THE IDENTITY ──────────────
  ///
  /// Level D addresses a SESSION via a cookie that the demux looks up BEFORE
  /// any cryptography (`d_socket.dart`, three steps:
  /// length, cookie, AEAD). The demux belongs to the node, so the
  /// table belongs to the node. Two identities on one process share
  /// it; that is right and not merely cheap, because a D frame
  /// carries no identity identifier — it is "authentic via AEAD under the
  /// `call_key`" (§17.4), and whoever does not have it does not exist
  /// for the socket.
  ///
  /// ── WHAT IT WAS BEFORE S360: NOTHING ──────────────────────────────────
  ///
  /// `d_socket.dart` and `d_frame.dart` were built and measured
  /// (`smoke_d_frame`, `smoke_call_plane_d` drive two real nodes),
  /// and `LinkDemux.dAdmission` had **not a single
  /// setting site** in `lib/` — the only one in the whole tree stood in a test file.
  /// Thus no D frame ever reached a running node: the demux
  /// asked the branch, the branch was `null`, the datagram fell through
  /// (`link_demux.dart:454`). Calls could therefore carry no media,
  /// and `CallTransportV41.mediaUnavailableReason` named exactly that as
  /// the first reason.
  late final DSocket dSocket;

  /// The listening half of the escalation step `tcpOwnPort` (§26.6.5).
  ///
  /// ── WHY IT HANGS HERE, AND WHY IT DID NOT UNTIL S361 ──────
  ///
  /// It belongs to the NODE, for the same reason as [dSocket] a
  /// hand's breadth higher: one port, one process, one set of sessions. §26.6.5
  /// expressly puts **both** branches on **one** port number
  /// behind **one** four-byte switch — "protocol detection at the first
  /// byte of a TCP connection (`GET`/`HEAD` → HTTP …) and the shared port
  /// number for UDP and TCP". A second binder solely for HTTP would
  /// therefore not be the cheaper solution but the wrong one; S360
  /// rejected it for exactly this reason
  /// (`docs/v4-redesign/S360-update-verteilung-entwurf.md:283-289`).
  ///
  /// **Until S361 NOBODY in `lib/` constructed a `TcpLinkListener`**
  /// (measured 2026-09-01 with three search phrasings: `TcpLinkListener`,
  /// `tcp_listener.dart`, `httpSink` — the only hits in `lib/` were
  /// the class itself, its constructor, its callback field and two
  /// comment lines). Both halves of the step were built on 2026-08-20
  /// and covered by suites of their own; the call was missing. What hung on it:
  /// **every** incoming TCP link handshake, the delivery of
  /// binary files (§26.6.4) and the bootstrap web app of the
  /// invitation link (§26.6.5, step 3 of the distribution ladder §26.6.7).
  ///
  /// ── WHAT DOES NOT COME ALONG WITH IT ───────────────────────────────────────
  ///
  /// **CORRECTED ON 2026-09-03 — THIS PARAGRAPH WAS OUTDATED.** Here
  /// stood: "The OUTGOING half (`TcpLinkConnector`) remains
  /// untrodden: `LinkHost.connect` passes a fixed `udpOwnPort`, and
  /// `UdpLinkConnector.attempt` rejects every other step." Both have been
  /// wrong since 02.09.2026 (`56068bed`, E-119 option C, approved by the
  /// owner). Re-measured on 2026-09-03:
  ///
  ///   * `link_io/link_host.dart:473` constructs a
  ///     `TcpLinkConnector` — the only construction in `lib/`, measured via
  ///     `TcpLinkConnector` as a word, as `TcpLinkConnector(` and as a
  ///     type annotation; apart from it there are only declaration, field and smokes.
  ///   * It sits in the `StagedLinkConnector` (`link_host.dart:336-341`),
  ///     which passes `udpOwnPort` to `udp.attempt` and `tcpOwnPort` to
  ///     `tcp.attempt`; only `tcp443` and
  ///     `icmpKnock` are still rejected (`:352-355`).
  ///   * `LinkHost.connect` (`:518-522`) still passes `udpOwnPort` as the
  ///     **starting rung** — that is the part that is right. Escalation
  ///     happens via `nextStage`, and the second rung has had an
  ///     I/O since then (`link_host.dart:449-455`).
  ///   * Guards: `test/smoke/smoke_v41_tcp_listener_wired.dart` and
  ///     `test/smoke/smoke_v41_tcp_connector_wired.dart`.
  ///
  /// What REMAINS of the old reasoning: RL-15 (the TCP wire profile
  /// above the constant cell rate) is the declared price of the step
  /// and written down as such in `link_host.dart:434-438`. E-119
  /// (simultaneous open on `tcpOwnPort`) is no longer unregulated
  /// but decided with option C. The proposal
  /// `docs/v4-redesign/S361-VORLAGE-tcp-lauscher.md` is thus done.
  ///
  /// Its HTTP switch (`tcp.httpSink`) is filled in later by `attachV41`, because
  /// `BinaryHttpServer` arises at the SERVICE and the node comes before the services
  /// (E-118: "the node host inserts `BinaryHttpServer`"). Until
  /// then it is `null`, and the listener handles that explicitly —
  /// it does not tear down, but lets the sniffing period run out (E-83).
  /// No pass-through getter on the node: a second handle to the same
  /// thing would be one more place at which someone sets the wrong one.
  late final TcpLinkListener tcp;

  late final SpeedEgress egress;
  late final DeliveryNode delivery;
  late final SlotDriver driver;

  /// The sessions over which slots go — same order as
  /// `egress.partnerLinkKeys`.
  final List<CellTransport> _partners = <CellTransport>[];
  final List<LinkChannel> _channels = <LinkChannel>[];
  final List<StreamSubscription<Uint8List>> _subs =
      <StreamSubscription<Uint8List>>[];

  /// Who opened the session — `true` if the remote side dialled.
  ///
  /// FIFTH INDEX-ALIGNED LIST, and it has to be: §25.4 requires the
  /// partner counts SEPARATED by direction ("Verified sync partners,
  /// outbound … inbound"), and the direction cannot be read
  /// anywhere else. `LinkChannel` does not carry it — the link layer is
  /// symmetric after the handshake, and that is intentional: from outside an
  /// accepted link should look like an established one. It can only be derived
  /// here, at the exactly two places where a session arises:
  /// `host.accepted` (the remote side dialled) and [connect] (this
  /// node dialled).
  ///
  /// WHAT THE SEPARATION SERVES (§25.4). Outgoing carries the OWN
  /// delivery and feeds the readiness; incoming says how much
  /// this node contributes FOR OTHERS, and is a prerequisite for
  /// incoming calls (§17). A sum of both answers neither of the
  /// two questions.
  final List<bool> _inbound = <bool>[];

  /// Who may be responsible at all (E-B).
  final EligibilityRegistry eligibility = EligibilityRegistry();

  /// What the node knows of entry records (§11).
  ///
  /// This is the reading of the entry cascade in the node: here lands what
  /// comes back from requests, and here the connection setup fetches its
  /// material. As long as this supply is empty, the node can accept,
  /// but reach nobody on its own.
  final EntryCache entries = EntryCache();

  /// EARLIER a set of open requests stood here: records sent unsolicited
  /// were discarded. That was the emergency measure
  /// against a hole that is now properly closed — as long as `L_node`
  /// was random, a supplier could write arbitrary keys under a
  /// foreign position. Since the position is the hash of the keys
  /// and the issuer signs, a record CAN no longer
  /// lie; unsolicited then only means "unasked", not
  /// "untrustworthy". What remains is the flood — and that is limited by the
  /// quota per source in the supply, not by a request list.

  /// Called when a record newly came into the supply.
  ///
  /// The delivery layer itself writes nothing to disk — it knows
  /// no `dart:io`, and that is to stay so. Whoever wants to save the supply
  /// hooks in here.
  void Function()? onEntriesChanged;

  /// The own addresses, as the node names them to others.
  ///
  /// Several, because a dual-stack node must be recognisable as such —
  /// §17.3 looks for a volunteer with both families for `v4-only <-> v6-only` calls,
  /// and whoever names only one is not one.
  String advertiseHost = '127.0.0.1';
  int advertisePort = 0;
  List<EntryAddress> advertiseExtra = const <EntryAddress>[];

  /// The externally reachable address from a CONFIRMED
  /// port mapping (UPnP/IGD or NAT-PMP/PCP), or `null`.
  ///
  /// ── WHY A FIELD OF ITS OWN AND NOT [advertiseExtra] (S373) ──────
  ///
  /// [advertiseExtra] is set COMPLETELY anew at every network change
  /// (`setzeAnsageadressen`) and stems from the enumeration of the local
  /// interfaces. The mapped address has a different source (the
  /// gateway) and a different life cycle: it arises seconds to
  /// minutes AFTER start, is renewed hourly and goes away
  /// when the router withdraws the grant. In the same list
  /// the next address finder would silently delete it.
  ///
  /// ONLY FROM A CONFIRMED MAPPING. A merely OBSERVED
  /// external address does not belong in here — without a mapping it points
  /// to a closed port, and a neighbour that dials it
  /// sends into the void and afterwards considers this node dead. That was
  /// already in V3 the separation between `setPortMapping(...)` and
  /// `setExternalIpOnly(...)`.
  ///
  /// The field is written exclusively by `PortMapBinding`
  /// (`port_map_wiring.dart`) — the only place where the node and
  /// the coordinator are present at the same time.
  EntryAddress? advertiseMapped;
  /// Has the router CONFIRMED a port mapping for this node?
  /// (S373, second source of evidence)
  ///
  /// ── IT IS NOT WEAKER THAN AN INBOUND PROOF, BUT STRONGER
  ///
  /// A confirmed mapping is a PROMISE of the router to pass incoming
  /// packets on to exactly this port. An inbound proof
  /// ([externalInboundProven]) is the after-the-fact observation that it
  /// worked once. V3.2.2 for the same reason put the result of
  /// `NatTraversal.setPortMapping` directly into the announcement WITHOUT an additional probe
  /// — to be looked up on the branch `s330/ap1-naht-sanieren`;
  /// in THIS tree the file no longer exists, the whole V3 network tree
  /// fell with the CUT of 31.08.
  ///
  /// ── WITHOUT IT THERE WOULD BE A LOOP ───────────────────────────────
  ///
  /// A freshly mapped node has no inbound yet, therefore does not publish
  /// itself, is therefore not dialled and therefore never gets
  /// an inbound. The rule applies equally to EVERY node: a
  /// confirmed mapping OR an incoming session from outside. There is
  /// no operator special case — a bootstrap is a node like any
  /// other (owner, 07.09.2026).
  ///
  /// ── WHO SETS THIS FIELD ─────────────────────────────────────────
  ///
  /// **Today NOBODY on this branch, and that is intentional.** The
  /// port mapping lies in the package `s373-portmapping` (commit `47df9f24`,
  /// UPnP/NAT-PMP/PCP) and comes with its merge. On the merge
  /// exactly one line has to be added: **where `V41Node.advertiseMapped`
  /// is set, `portMappingConfirmed = true` belongs next to it** — and
  /// only if the router has confirmed the mapping, not already
  /// on the attempt.
  ///
  /// It nonetheless already stands here as a field, instead of as a dummy that silently
  /// returns `true`: `false` is the honest default ("not proven"), it
  /// lets the rule take effect and reports nothing false. A node without
  /// a mapping still gets in via the inbound proof.
  bool portMappingConfirmed = false;

  /// Has this node already had an INCOMING session from outside the
  /// own network? (S4/S373)
  ///
  /// This is V4.1's replacement for the V3 port probe (CPRB) and costs no
  /// additional traffic: only what comes in anyway is evaluated.
  /// An INCOMING session is the only proof there is — an
  /// outgoing one says nothing (it opens the NAT hole itself), and a
  /// global IPv6 on the interface likewise says nothing: most
  /// home routers block incoming IPv6 by default. Exactly three of these
  /// lay on the global board on 06.09.2026.
  ///
  /// IT IS SET BY `v41_attach.dart`, not here, and that is the
  /// layer boundary: judging which source address means "outside"
  /// is address classification, and the delivery layer knows no
  /// `dart:io` (see [onEntriesChanged]). The node only holds the
  /// RESULT — so that [onNetworkChanged] can drop it together with the sessions
  /// to which it owes its validity.
  bool externalInboundProven = false;

  /// What this node knows of the network.
  late final RoutingTable table;

  // ── THE RESPONSIBLE NODES OF THE NETWORK (S356, §9.1) ────────────────────────
  //
  // Up to here `responsibleRelays` computed responsibility against
  // THIS table — §9.1 itself calls that "Still an approximation". The
  // price showed in the field on 29.08.: placement and harvest side converted
  // the same tag onto their own respective tables and hit different
  // nodes. Network-wide not a single harvest hit.
  //
  // WHY A STORE AND NOT A CALL IN THE SEND PATH. A lookup
  // costs about seven requests, and each is a cell from the own
  // cover tick: ~7 slots ~ 56 s (§7.2). In the send path EVERY
  // message would cost a minute of lookup. §7.2 says the opposite — the cold start
  // pays for it FIRST, afterwards it holds for the epoch.
  //
  // WHY THE RESULT DOES NOT MOVE INTO THE TABLE. The R nearest to
  // a FOREIGN target almost all lie in ONE bucket, and that holds
  // k = 20 and rejects when full (`routing_table.dart`). A
  // lookup result structurally does not fit into a Kademlia table; it
  // must be kept per TARGET.
  final ResponsibleSetCache networkResponsible = ResponsibleSetCache();

  /// Open own lookup requests: identifier -> who is waiting for the answer.
  final Map<String, Completer<List<KnownNode>>> _lookupRequest =
      <String, Completer<List<KnownNode>>>{};

  /// Pointer for the round-robin over the targets — the same consideration as
  /// with `_ernteZeiger`: without it the first counterpart would always have
  /// priority and the second would starve.
  int _lookupPointer = 0;

  /// How many lookup runs have taken place. Stands in the
  /// status line so that it is VISIBLE in the field log whether lookups happen — the
  /// class of defect that has cost this migration three times was
  /// each time "built, never trodden".
  int lookupRuns = 0;

  /// How many lookup requests went out via an onion (E-L).
  int lookupsOnionWrapped = 0;

  /// How many lookup requests were OMITTED because no blind relay was
  /// available.
  ///
  /// COUNTED AND NOT SILENTLY DISCARDED. A node that knows nobody beyond the
  /// own sessions cannot onion — and
  /// it then does NOT fall back to the open request, but
  /// omits it. Without this counter this would look like a network in
  /// which nobody answers.
  int lookupsWithoutBlindRelay = 0;

  int _uninteresting = 0;

  /// How many incoming cells were nothing for this node —
  /// counted instead of logged.
  int get uninterestingCells => _uninteresting;

  // ── THE RECEIVE CHAIN (S349) ────────────────────────────────────────
  //
  // Until S349 every receive path of this layer ended in nothing. A cell
  // delivered to this node was counted as `CellRole.mine`
  // and dropped; `Aggregate.unpack`, `MessageOpener` and
  // `V41Host.accept` together had ZERO callers in `lib/`. Two nodes
  // exchanged cover traffic, and no message ever arrived at the top.
  //
  // The way in has four stations, and each is necessary:
  //
  //   cell -> aggregate apart -> pieces together -> seal open
  //
  // The order is not free: aggregation happens BEFORE splitting
  // (several short messages share one cell), so on
  // receiving first the aggregate must be opened and then the transmission
  // reassembled.

  /// Reassembles split payloads — one instance per session.
  ///
  /// ONE FOR THE WHOLE SPEED PATH — not one per session.
  ///
  /// Here stood `Map<CellTransport, PayloadReassembler>`, keyed
  /// by the session through which a cell came in. The intention was
  /// cleanup: an ended session was to take its half-finished
  /// transmissions with it.
  ///
  /// THAT TEARS A PAYLOAD APART. The pieces of a Speed payload
  /// do not necessarily reach the receiver via THE SAME session —
  /// and if the session changes between two pieces, they lie in two
  /// instances, none of which ever becomes complete. Measured in the field on 30.08.
  /// on both nodes: `zusammengesetzt 0`, `Stuecke verworfen
  /// 0`, but `offene Uebertragungen 3` — pieces arrived, nothing was
  /// ever finished, and nothing was lost. Alice's log shows in addition
  /// "Sitzung 3 in Betrieb" twice within 40 seconds.
  ///
  /// The split was moreover superfluous: `PayloadReassembler`
  /// has long indexed internally by transmission identifier (`_offen`) and
  /// limits itself via `maxOpenTransfers` and `maxBufferedBytes`. The
  /// cap now holds for the path instead of per session — tighter than before,
  /// and that is the right direction.
  /// THE LIMITS MERGED ALONG (30.08., second version). Before, there was
  /// one reassembler per session, so the cap of 4 open
  /// transmissions held PER SESSION — with three partners effectively 12.
  /// After the merge it held once, and in the field promptly
  /// transmissions tipped into discarding (`Stuecke verworfen 2`, order 0),
  /// although no piece was missing. Whoever merges instances must merge their
  /// limits along — otherwise he trades one error for a
  /// tighter one.
  final PayloadReassembler _speedAssembler = PayloadReassembler(
    maxOpenTransfers: 16,
    maxBufferedBytes: 256 * 1024,
  );

  /// For harvested cells (Secure) — one PER COUNTERPART.
  ///
  /// Not ONE shared one: the transmission identifier is chosen by the sender
  /// and is not unique across senders. With a shared
  /// buffer four incomplete transmissions of a single
  /// counterpart could jam the harvest of all others
  /// ([PayloadReassembler.maxOpenTransfers]) — the same isolation that
  /// `CellTransport` already provides for the link layer.
  final Map<String, PayloadReassembler> _harvestAssembler = {};

  /// Which harvest request belongs to which counterpart.
  ///
  /// CAPPED, because otherwise it grows as long as the node runs: with
  /// six requests every 32 s that is ~16 000 entries a day. The
  /// return path of an answer is needed within seconds or not at all
  /// — the same consideration for which `PendingRequests` has a deadline and
  /// a cap.
  final Map<String, String> _requestPeer = <String, String>{};

  /// Maximum number of remembered own requests.
  static const int kOwnRequestMemory = 256;

  /// The harvest book per counterpart (B-32).
  final Map<String, HarvestMemo> _harvestMemo = <String, HarvestMemo>{};

  HarvestMemo _memoFor(String peer) =>
      _harvestMemo.putIfAbsent(peer, HarvestMemo.new);

  /// How many harvested cells were dropped as repetition.
  ///
  /// A counter, not a log (E-83) — but a counter that one must be able to
  /// read: it is the measure for B-32, and a rise means
  /// that the have-list does not arrive at the counterpart.
  int duplicateHarvestCells = 0;

  /// A harvested cell whose counterpart is known.
  ///
  /// TWO STAGES (B-32, see `harvest_memo.dart`): a cell that this
  /// book already knows completely is dropped here — before the
  /// reassembler and thus before seal and signature check. It only goes into the book
  /// when ITS transmission is complete; noted earlier,
  /// a displaced first piece would be lost forever.
  void _harvestedFrom(String peer, Uint8List cell) {
    // Traffic in THIS direction keeps the pair in the active rank.
    _lastTraffic[peer] = DateTime.now().toUtc();
    final memo = _memoFor(peer);
    final epoch = nodeEpochNow();
    if (memo.offer(cell, epoch) == CellVerdict.duplicate) {
      duplicateHarvestCells++;
      return;
    }
    final zs = _harvestAssembler.putIfAbsent(peer, PayloadReassembler.new);
    final done = zs.offer(cell);
    if (done != null) {
      final id = splitTransferId(cell);
      if (id != null) memo.completed(id, epoch);
      _offer(peer, done);
    }
  }

  /// Who may open a reassembled, still sealed payload.
  ///
  /// One sink per identity. It returns `true` if IT has got it
  /// open — then the node stops asking. The node knows no
  /// keys and should know none; it passes bytes around and lets
  /// those who can assign them.
  ///
  /// The first parameter is the sender from the tag line (path A, S352):
  /// in the Secure path the pair identifier, known from `_geerntetVon`; the
  /// removed signature in the frame replaced exactly this information, which was
  /// already available here and only not passed through.
  final List<bool Function(String peer, Uint8List sealed)> _sinks =
      <bool Function(String peer, Uint8List sealed)>[];

  void addSink(bool Function(String peer, Uint8List sealed) sink) =>
      _sinks.add(sink);

  /// How many payloads were completely assembled.
  int payloadsAssembled = 0;

  /// How many of them a sink could open.
  int payloadsOpened = 0;

  void _offer(String peer, Uint8List assembled) {
    payloadsAssembled++;
    for (final sink in _sinks) {
      if (sink(peer, assembled)) {
        payloadsOpened++;
        return;
      }
    }
    // Nobody could open it. That is the NORMAL CASE: a dummy cell
    // of a partner looks exactly the same at this point as a real
    // message for someone else. Counted, not reported (E-83).
  }

  /// A cell that was addressed to this node.
  void _incoming(int fromPartner, Uint8List body) {
    if (fromPartner < 0 || fromPartner >= _partners.length) return;
    final zs = _speedAssembler;
    for (final entry in Aggregate.unpack(body)) {
      final done = zs.offer(entry);
      // SPEED path: here the onion addresses, there is no field tag
      // (§4.3, "in Speed-Mode there is no field tag") — so the sender is
      // not known. '' is a STATE here (no field tag in the
      // mode), not a missing value as in the Secure path before path A.
      if (done != null) _offer('', done);
    }
  }

  /// A cell that came back on an own harvest request (Secure).
  ///
  /// It is NOT aggregated: `placeSecure` puts the payload directly into
  /// the placement (`buildPlace`), without cover aggregate. It is however very much
  /// SPLIT — the first contact measures more than one cell.
  void _harvested(Uint8List requestId, Uint8List cell) {
    final key = base64.encode(requestId);
    // FIRST THE LIVENESS (S354). An answer to a liveness request
    // is NOT a piece of a transmission: it is `r2-Kennung ‖ Wegblock`
    // and has no business in the message reassembler — there it occupied
    // one of the open places and waited for continuations that
    // never come.
    final forLiveness = _livenessRequest[key];
    if (forLiveness != null) {
      // THE EPOCH COMES FROM THE REQUEST, not from the clock. Between
      // question and answer the pair epoch can move; then the
      // route would belong to the old one, but would be noted under the new one and at the
      // next `prepareSpeed` considered valid — the path block
      // would no longer be (`relay.dart`, binding to the epoch).
      _livenessAdopt(
          forLiveness.peer, forLiveness.epoch, cell);
      return;
    }
    // THEN THE TAG HARVEST (§13.3.1). For the same reason as the
    // liveness one line higher: a cell of the bundle line is not a
    // piece of a pair transmission and has no business in the reassembler.
    // The caller who made the request sorts
    // himself — he is the only one who knows the tags.
    final forMark = _marksRequest[key];
    if (forMark != null) {
      forMark(cell);
      return;
    }
    // Who asked stands in the request list. If the identifier is
    // unknown, a shared buffer remains — that is the fallback,
    // not the normal path.
    final peer = _requestPeer[key] ?? '';
    _harvestedFrom(peer, cell);
  }

  V41Node._(this.host, this.keys, this.log);

  // ── THE WIRE BOOKKEEPING, NOW AT THE NODE (§25.5, CUT 31.08.) ───────────
  //
  // Until the CUT the composition point (`main.dart`,
  // `service_daemon.dart`) passed in two callbacks that booked into
  // `CleonaNode.statsCollector`. This detour only existed
  // because V3 owned the socket and the network statistics hung there. Without
  // `CleonaNode` there is no collector any more — and then inventing the number
  // anew somewhere would be the dummy that this migration must not
  // produce.
  //
  // It belongs here because it ARISES here: `UdpSocketSet` counts
  // on sending and on receiving (`udp_sockets.dart:204/216`), the
  // chain runs via `LinkHost.start` to `V41Node.start`. The
  // display layer reads via the handle it holds anyway
  // (`CleonaService.v41Host` or the node itself).
  //
  // The passed-through callbacks remain possible and are called IN ADDITION:
  // the lab run (`bin/cleona_v41_node.dart`) and tests should
  // still be able to listen in, without a caller accidentally switching the bookkeeping
  // OFF by omitting the parameter.
  // READ SITES, NOT FIELDS — and that is no stylistic decision. The
  // first version of this rebuild copied the numbers accumulated in the start window
  // ONCE into two `int` fields. After that the
  // socket callbacks kept writing into their local counters, and the fields
  // stood at their start value forever: a display that looks
  // like a measurement and is none. Read via a function,
  // this error cannot arise — there is only ONE number.
  int Function() _wireSent = () => 0;
  int Function() _wireReceived = () => 0;

  /// Datagram bytes out, since the start of this node.
  int get wireBytesSent => _wireSent();

  /// Datagram bytes in, since the start of this node.
  int get wireBytesReceived => _wireReceived();

  // ── THE FORWARDING (§25.5) ─────────────────────────────────────
  //
  // Two numbers that the UI showed as zero since the CUT:
  // "forwarded messages" and "relay volume"
  // (`network_stats_screen.dart`, tiles `stats_messages_relayed` and
  // `stats_relay_volume`). The writer fell with the V3 transport, and
  // the replacement did not stand next to it: `DeliveryNode` forwards without
  // booking it anywhere.
  //
  // They belong here because they ARISE here — the same reasoning
  // as with the wire bytes a hand's breadth higher, and the same design:
  // fields in the node, read via getters, wired via bare
  // callbacks. The DISTINCTION from `wireBytesSent` is important and the
  // reason why there are two numbers and not one: `wireBytesSent`
  // counts EVERYTHING that leaves the socket, including the own post and the
  // cover traffic. `relayBytes` counts only what went on for SOMEONE ELSE.
  // The UI warns at the tile itself about the
  // double counting (`stats_relay_volume_note`).
  int _relayBytes = 0;
  int _relayCells = 0;

  /// Bytes this node has forwarded for others.
  int get relayBytes => _relayBytes;

  /// Cells this node has forwarded for others.
  int get relayCells => _relayCells;

  /// Send attempts that failed at the transport (D-3, S372) — see
  /// `DeliveryNode.onSendFailed`. `tick()` catches these cases itself since then
  /// and no longer throws; without this counter a
  /// closed partner would be invisible from here, although the payload
  /// is put back every time and retried in the next slot.
  int _sendFailures = 0;

  /// How often a send attempt failed at the transport.
  int get sendFailures => _sendFailures;

  static Future<V41Node> start({
    required int port,
    required NodeKeys keys,
    Duration slotInterval = kSlotInterval,
    void Function(String)? log,
    PeerLookup? peers,
    // ── THE WIRE BOOKKEEPING (§25.5) ──────────────────────────────────────
    //
    // Two bare callbacks, NO reference to `NetworkStatsCollector`.
    // Wiring happens at the composition point (`service_daemon.dart`,
    // `main.dart`), where both worlds lie side by side anyway.
    //
    // RE-MEASURED 2026-09-03 — THE REASONING WAS OUTDATED, THE
    // DECISION NOT. Here stood: "`smoke_link_io_milestone`
    // (section 5) forbids every module under `lib/core/link`,
    // `lib/core/link_io`, `lib/core/sync` and `lib/core/tagline` an
    // import edge to `lib/core/network/`." The guard today checks
    // five V4 roots against five V3 trees (`kV4Roots`, `kV3Trees`) —
    // and `NetworkStatsCollector` lies since the CUT (`9d91f801`) in
    // `lib/core/stats/network_stats.dart:378`. `stats` is NOT in
    // `kV3Trees`; the guard even lists
    // `import 'package:cleona/core/stats/network_stats.dart';` in
    // its `mustNotMatch` list. Section 5 would thus no longer catch such an edge.
    // The bare callbacks remain nonetheless:
    // this file is to stay testable without the statistics layer.
    //
    // WHY THEY ARE PASSED THROUGH HERE AND NOT SET LATER:
    // `LinkHost.start` starts the demux before it hands out the host.
    // A hook set afterwards would lose the first incoming
    // datagrams — exactly the class "number that is a little
    // off" that this package eliminates.
    //
    // UNTIL S357 V4.1 BOOKED NOTHING. Measured in the field: ~24.5 MB/day out,
    // ~24.9 MB/day in, without exception in 1200 B cells — and of that
    // not a single byte appeared in the user's network statistics.
    void Function(int bytes)? onWireBytesSent,
    void Function(int bytes)? onWireBytesReceived,
    // Forwarding (§25.5). Called exactly when a FOREIGN cell
    // leaves this node again — see `DeliveryNode.onRelay`.
    void Function(int bytes)? onRelayBytes,
    // The HTTP switch of the data port (§26.6.5). In the app it stays
    // `null` here and is filled in later by `attachV41` as soon as the service
    // has its `BinaryHttpServer`; the lab program and the guards
    // can already pass it at start.
    LinkHttpSink? httpSink,
    // Total byte cap of the delivery store (§21.3.3, option C). `-1` =
    // unlimited (desktop). `startV41Node` passes
    // `kMobileSecureStoreCapBytes` through here, after the platform derivation
    // `Platform.isAndroid || Platform.isIOS` — the same design as
    // `cleona_service_update.dart:218-222`. This file deliberately does not read `Platform.*`
    // itself (layer boundary `smoke_link_axis_guard`).
    int maxStoreBytes = -1,
    // The bulk quota of the holder (§9.3, §21.3.3 no. 3). Without an argument
    // a desktop quota; `startV41Node` passes a SWITCHED-OFF one through on
    // Android/iOS (E-53: "mobile nodes carry no bulk" — none,
    // not little). The same layer boundary as with [maxStoreBytes]:
    // this file does not read `Platform.*`.
    BulkCache? bulkCache,
  }) async {
    final sink = log ?? (String s) {};

    // TWO INTERMEDIATE HOLDERS INSTEAD OF DIRECT ACCESS TO `n`. The node is
    // `late final` and only assigned after `LinkHost.start` — but the host
    // starts the demux BEFORE it returns. A datagram that falls into
    // this window would, on an access to `n`, run into a
    // `LateInitializationError`, and that from within a socket callback,
    // i.e. uncaught. Exactly the class of error one only sees in the
    // field.
    var sent = 0;
    var receive = 0;
    // THE ENTRY CASCADE, at its effective place. On connection setup the host asks
    // for the material of the remote side; asked FIRST is
    // the own supply. Only when that stays silent does what was passed in from
    // outside take effect — today the lab crutch. The crutch has thus
    // turned from the main path into the fallback: it can go as soon as a
    // node fills its supply from the network, and until then one sees at
    // this one line what is still missing.
    late final V41Node n;
    final host = await LinkHost.start(
        port: port,
        keys: keys,
        log: (s) => sink(s),
        onWireBytesSent: (b) {
          sent += b;
          onWireBytesSent?.call(b);
        },
        onWireBytesReceived: (b) {
          receive += b;
          onWireBytesReceived?.call(b);
        },
        peers: (ep) =>
            n.entries.lookupEndpoint(ep.host, ep.port)?.toMaterial() ??
            peers?.call(ep),
        // Decision C: if this node already knows the caller, his
        // static key goes into the session key and the
        // session carries a VERIFIED position. Exactly that was missing in order
        // to be able to forward via incoming connections.
        lookupStatic: (pos) => n.entries.lookup(pos)?.x25519Public,
        // WAIT TWO TICKS, NOT SIX SECONDS. The proof of a session
        // is an arriving cell, and cells come on the cover tick — with
        // `kSlotInterval` = 8 s at the earliest after 8 s, because of the spread around
        // the mean also later. The link layer's default (one
        // cascade run, 4 x 1.5 s = 6 s) is thus SHORTER than the
        // earliest possible proof: every accepted session was
        // swept away before the partner was allowed to send. Two ticks allow
        // two opportunities and keep the purpose of the short deadline
        // intact — a slipped-in entry still ages out in seconds,
        // not in an hour.
        //
        // THE MAXIMUM, NOT THE MULTIPLE. The first version took a bare
        // `slotInterval * 2` — and was thus, with a short tick, SHORTER than
        // the 6 s it was to replace. `smoke_v41_node` immediately falls over on that
        // (the tick there runs in milliseconds): the session
        // died before the peer announcement arrived. The deadline must hold BOTH
        // lower bounds — the cascade run of the link layer and two
        // ticks of the delivery layer.
        sessionProofLifetime: slotInterval * 2 > LinkDemux.defaultPendingLifetime
            ? slotInterval * 2
            : LinkDemux.defaultPendingLifetime);
    n = V41Node._(host, keys, sink);
    // The intermediate holders ARE the counter; the node only gets the
    // read site for it. Thus the start window also counts, in which
    // the demux is already running and `n` is not yet assigned.
    n._wireSent = () => sent;
    n._wireReceived = () => receive;

    // ── REGISTER LEVEL D (§17.4) ──────────────────────────────────────
    //
    // AFTER `LinkHost.start`, and that is here — unlike with the
    // wire bookkeeping a hand's breadth further up — demonstrably harmless.
    // The demux is already running in this window, but the cookie table
    // is EMPTY, and `DSocket.claim` is totally
    // false on an empty table: step 2 fails for every datagram
    // (`d_socket.dart`, `_sessions[...] == null -> return false`). A
    // branch set earlier would thus have given exactly the same answer.
    // The booking of the wire bytes had to go in beforehand because it COUNTS
    // and a lost datagram would leave a wrong number; here
    // there is nothing to lose.
    //
    // The branch is SET and not added to: `dAdmission` is a
    // single field, not a callback register. Whoever sets it a second time
    // overwrites — that is why this line is the ONLY
    // setting site in `lib/`, and `smoke_v41_plane_d_registered` measures that.
    n.dSocket = DSocket(sockets: host.sockets);
    host.demux.dAdmission = n.dSocket.claim;

    n.table = RoutingTable(keys.lNode);
    // ── THE SLOT SEED COMES FROM THE CSPRNG (S376, finding 1) ───────────
    //
    // HERE STOOD `seed: 0`, unchanged since `98836b2a`. That was the
    // gravest finding of the S375 network audit: `Random(0)` is
    // deterministic in Dart and can be recomputed without knowledge of any secret.
    // Because this is the ONLY creation site of a
    // `SpeedEgress` in `lib/`, every shipped node
    // worldwide thus drew
    //
    //   * the same sequence of slot intervals (`CoverStream._rng`,
    //     `drawInterval`),
    //   * the same sequence of partner indices (`drawPartner`),
    //   * the same sequence of padding bytes (`_padRng`),
    //   * and via `seed ^ 0xa5a5a5` the same onion nonce seeds and
    //     the same dummy cell bytes (`SpeedEgress._seedRng`).
    //
    // An observer needs no access to the node for this: he
    // runs `Random(0)` himself. After a few observed
    // inter-arrivals he knows he has the right sequence in
    // hand, and from then on knows every future slot time of every
    // node. That makes §5.2 ("shared jitter") ineffective: the jitter
    // is to hide the moment of sending in a window (§7.3, "one
    // slot interval plus jitter"), but a predictable window is
    // none — the observer knows the position of every slot in advance and only measures
    // whether a cell carried payload.
    //
    // 8 bytes from `randombytes` (libsodium, CSPRNG of the operating system),
    // read as an integer. The top bit is cleared: Dart `int`
    // is signed, and a negative seed is admissible,
    // but `seed ^ 0xa5a5a5` and `seed ^ 0x5f5f5f` are harder to survey on
    // negative numbers than necessary. 63 bits
    // of seed are ample for this purpose.
    //
    // THERE IS DELIBERATELY NO PARAMETER for this. A `slotSeed` argument
    // would be exactly the way by which a fixed number would come back — and
    // it is not needed: every suite that needs a reproducible
    // plan builds its `SpeedEgress` itself and specifies its
    // seed there.
    final seedBytes = SodiumFFI().randomBytes(8);
    var slotSeed = 0;
    for (final b in seedBytes) {
      slotSeed = (slotSeed << 8) | b;
    }
    slotSeed &= 0x7fffffffffffffff;
    n.egress = SpeedEgress(
        partnerLinkKeys: <Uint8List>[],
        meanInterval: slotInterval,
        seed: slotSeed);
    // Without partners the tick runs anyway — the cells then fall to
    // the floor. That is right: a stream that only starts with the first
    // connection would reveal the time of the first connection.
    n.egress.syncPartnerCount();
    // -- THE LOSS GETS AN ADDRESSEE (S381, 11.09.2026) ------
    //
    // If a placement frame drops out of the control queue, a PIECE
    // of the message is gone — and until S381 nobody noticed: the queue
    // counted (`droppedControl`), the sender considered the message
    // placed. Measured on 11.09.2026 on Node1 during `1a.03`:
    // `Kontrollschlange 84/120, verworfen 168`, and Bob's answer arrived at
    // Alice as two of five pieces.
    //
    // The callback carries only bytes; which message hangs on it is known by
    // `_eigeneAblagen` — that is why the assignment stands here and not in
    // the queue.
    n.egress.stream.onControlDropped = n._depositDropped;
    n.delivery = DeliveryNode(
      egress: n.egress,
      partners: n._partners,
      partnerFor: n._partnerFor,
      epochNow: nodeEpochNow,
      onPeerLearned: n._learn,
      maxStoreBytes: maxStoreBytes,
      bulkCache: bulkCache,
    );
    n.driver = SlotDriver(n.delivery, log: n.log);

    n.advertisePort = port;
    n.pairs = PairRegistry.fromNodeSecret(keys.nX25519Secret);
    // The resolver sees the same list the egress keeps — if a
    // partner is added, it is included in the next pass.
    n.blockResolver = ReplyBlockResolver(linkKeys: n.egress.partnerLinkKeys);
    n.delivery.entryProvider = n._entryFor;
    n.delivery.onEntryLearned = n._learnEntry;
    // EVERY answer releases the lock — even an empty one (S376, P4-3).
    n.delivery.onEntryResponse = n.entrySetSettled;
    n.delivery.entrySetProvider = n._entrySet;
    n.delivery.onPlaceAck = n._placeAck;
    n.delivery.ownPosition = keys.lNode;
    n.delivery.ownX25519Secret = keys.nX25519Secret;
    n.delivery.nextHopToward = n._nextHopToward;
    // THE TWO RECEIVE PATHS. Without them the whole layer runs into a
    // dead end: Speed ends in `CellRole.mine`, Secure in a harvest answer
    // that nobody takes.
    n.delivery.onInbound = n._incoming;
    n.delivery.onHarvested = n._harvested;
    // §25.5 — the forwarding numbers. As with the wire bytes, an
    // intermediate store in the node plus an ADDITIONAL pass-through to
    // the outside: the lab run and tests should be able to listen in without
    // a caller accidentally switching off the bookkeeping by omitting the
    // parameter.
    n.delivery.onRelay = (bytes) {
      n._relayBytes += bytes;
      n._relayCells++;
      onRelayBytes?.call(bytes);
    };
    // D-3 (S372): `tick()` now catches a failed send attempt
    // itself, puts the payload back and no longer throws — without
    // this report the failure would be invisible from here. `n.log`
    // is the same channel that `SlotDriver` already uses for its own (second)
    // line of defence (`n.driver = SlotDriver(n.delivery,
    // log: n.log)` above) — no new reporting path, the same one.
    n.delivery.onSendFailed = (recipient, err) {
      n._sendFailures++;
      n.log('Send attempt failed '
          '${recipient != null ? "for $recipient" : "(control frame)"}: '
          '$err — payload put back, slot stays used.');
    };
    // ── AND THE TWO SIDES OF THE LOOKUP (S356) ───────────────────────
    //
    // Without `nearestKnown` this node answers no foreign lookup —
    // it would be a hole in the network, and the lookup of all others would
    // get worse without it being noticed here. Without `onNodesFound`
    // the own answer would arrive nowhere and every lookup would run into
    // the timeout. Both are the same class of defect as `onHarvested`
    // one line above: one half built, the other not
    // connected.
    n.delivery.nearestKnown = n._nearestKnown;
    n.delivery.onNodesFound = n._found;

    // ── SUPPLY AND TABLE MUST NOT DIVERGE (S351) ─────
    //
    // Every path that brings an entry record into the supply thereby
    // also brings a position — and that belongs in the routing table
    // from which `placeSecure` and `harvestTick` choose their relay. So far
    // only `_learnEntry` did that, i.e. the path via a partner; the
    // cold-start cascade writes directly into the supply and went
    // past it. The callback sits at the supply instead of at the cascade, so that
    // every FUTURE path takes it as well.
    //
    // A learned record does NOT make the node eligible (E-B) — it
    // is only just beginning to run in. That is decided by `_learn`; nothing
    // changes about it here.
    n.entries.ownPosition = keys.lNode;
    n.entries.onRemembered = (r) => n._learn(r.lNode);

    // `inbound: true` — what comes in via `host.accepted` was dialled
    // by the REMOTE SIDE. The direction can only be read here, at the
    // creation: looking at the same session later no longer lets it
    // be determined, because `LinkChannel` is symmetric after the handshake
    // (§25.4 separates outgoing/incoming, §22.9 grades only
    // the outgoing number). Hence no short form `listen(n.adopt)`.
    n.host.accepted.listen((ch) => n.adopt(ch, inbound: true, peer: ch.peer));

    // ── AND THE SECOND RECEIVE DIRECTION: TCP (§26.6.5, E-116(3)) ───────
    //
    // WHY DOWN HERE AND NOT ABOVE AT LEVEL D. `TcpLinkListener.start`
    // BINDS, and from the return point a foreign connection can
    // come in. The first complete handshake calls `n.adopt`, and
    // `adopt` accesses `egress`, `delivery`, `readiness` and `entries`
    // — all `late final`, all only assigned further up. Binding
    // therefore happens LAST, immediately next to the UDP side, which
    // has the same condition.
    //
    // THE REPLAY BUFFER IS THE DEMUX'S, not a second one. Both paths
    // accept the same `init` flight (§2.6); two buffers would mean
    // that a flight rejected over UDP would get through once more over TCP
    // — the ring buffer is the only place at which a
    // replay attack fails, and it only fails if it SEES the
    // repetition.
    //
    // THE ADMISSION IS SEPARATE, and that is the reverse direction of the same
    // consideration: `LinkAdmission` counts connections and descriptors,
    // and those only exist on a stream. On UDP it has no
    // object (`admission.dart`, header: `accept()` IS the
    // state creation). The values come from E-124 and are NOT
    // set here — the defaults of the class are the measured ones.
    n.tcp = TcpLinkListener(
      keys: keys,
      replay: host.demux.replay,
      admission: LinkAdmission(),
      // Fresh 32 B per handshake; `ElligatorFFI.keyPair` wipes the
      // buffer, a seed must never be reused.
      drawSeed: () => SodiumFFI().randomBytes(32),
      log: sink,
      // THE SAME PORT NUMBER AS UDP (§2.1a; E-60 gives the
      // entry record exactly one port for both protocols). UDP
      // (SOCK_DGRAM) and TCP (SOCK_STREAM) share it on the kernel side
      // without conflict.
      port: port,
      // NOT YET SET, and that is an order: `BinaryHttpServer`
      // arises in the SERVICE, the node comes before the services. `attachV41`
      // fills it in later (E-118). Until then a `GET` runs into the
      // sniffing period instead of an immediate teardown (E-83).
      httpSink: httpSink,
    );
    // Decision C, as on the UDP side: if this node already knows the caller,
    // his static key goes into the session key
    // and the session carries a VERIFIED position.
    n.tcp.lookupStatic = (pos) => n.entries.lookup(pos)?.x25519Public;
    // `inbound: true` for the same reason as two lines higher — via
    // a listener comes in whoever DIALLED.
    n.tcp.accepted.listen((ch) => n.adopt(ch, inbound: true, peer: ch.peer));

    // E-120: the listener is bound as soon as AT LEAST ONE family
    // stands, and the failure is silent and NOT fatal — a node with a
    // bound UDP listener is not deaf, it loses the incoming
    // side of a fallback step. E-71 requires one line PER missing
    // family, no collective line; `TcpLinkListener.start` already writes them
    // itself, here only the overall situation remains.
    // ── THE LAN SITUATION ONCE, AND THEN ONLY ON THE EDGE ─────────
    //
    // `refreshLanSegments` asks the operating system for the own
    // addresses; the answer does not change between two network changes.
    // It therefore stands here once and afterwards exclusively in
    // `onNetworkChanged` — no timer, no second rhythm.
    await n.refreshLanSegments();
    // And the checker on which the consented cover switch-off
    // hangs (S373). REGISTERED AND NOT SET: `CoverSaver` asks anew at
    // every draw, so every change of the situation — a
    // newly added remote partner, a revoked witness — takes effect in the
    // same slot, without anyone having to call a setter.
    CoverSaver.instance.bindLanConfinedProbe(n, n.lanConfined);
    final List<TcpBindReport> tcpReports = await n.tcp.start();
    final bound = tcpReports.where((TcpBindReport r) => r.bound).length;
    if (bound == 0) {
      sink('V4.1: TCP listener on port $port bound in NO family — '
          'this node accepts no inbound TCP links and serves '
          'no binaries (§26.6.5). UDP is unaffected by this.');
    } else {
      sink('V4.1: TCP listener on port $port — $bound of '
          '${tcpReports.length} address family(ies) bound');
    }
    return n;
  }

  /// Takes up an announced position. `true` if it was new.
  ///
  /// It goes into the routing table AND into the eligibility register — both
  /// are necessary: the table says where someone lies, the register whether he
  /// may be responsible at all (E-B). A freshly announced
  /// node is thus **not yet eligible**: it is only just beginning to
  /// run in, and exactly that is what the gate is to achieve.
  /// The own entry record.
  EntryRecord get ownEntry => EntryRecord.issue(
        keys: keys,
        // CAPPED, and that here and not only when setting. `advertiseExtra`
        // is a public field; whoever fills it need not know the format
        // limit. On 28.08. a phone with EIGHT address families
        // ("Ansageadresse 192.0.0.4 (+7 weitere)") made the
        // entry handler run into an exception exactly here —
        // `Invalid argument(s): hoechstens vier Adressen`, from within a
        // stream callback and thus uncaught. On the test nodes
        // with two addresses it never showed.
        addresses: [
          EntryAddress(advertiseHost, advertisePort),
          // IN SECOND PLACE, and the order is the selection: the
          // record carries at most [kMaxEntryAddresses] addresses, and
          // `take` cuts off at the back. The local address is needed by a
          // neighbour in the same segment, the mapped one by everyone else —
          // both therefore go before the remaining families (S373).
          ?advertiseMapped,
          ...advertiseExtra,
        ].take(kMaxEntryAddresses).toList(),
        now: DateTime.now(),
      );

  /// Nodes from the supply that are reachable on BOTH address families.
  ///
  /// These are the candidates for the media volunteer from §17.3: only
  /// whoever has both families can mediate between a v4-only and a
  /// v6-only counterpart. He cannot read anything in doing so — the
  /// media frames are under `call_key`, which he does not have (§17.4).
  List<EntryRecord> dualStackCandidates() =>
      entries.all().where((r) => r.isDualStack).toList();

  EntryRecord? _entryFor(Uint8List position) {
    if (_sameBytes(position, keys.lNode)) return ownEntry;
    return entries.lookup(position);
  }

  bool _learnEntry(EntryRecord r, int fromPartner) {
    // THE LOCK IS NO LONGER RELEASED HERE (S376, P4-3). It hung on
    // an answer WITH CONTENT; an empty answer, a discarded
    // frame or a broken-off partner left it standing until restart.
    // It is now released by `delivery.onEntryResponse` — on
    // every answer, including the empty one — and by the expiry in the slot driver.
    // One does not accept the OWN record. It comes back as soon as
    // a partner passes it on — harmless-looking, but it brought the
    // own position into the own routing table, and with that the
    // node would have considered itself a responsible relay.
    if (_sameBytes(r.lNode, keys.lNode)) return false;
    // Held twice: `decodeAt` lets nothing fake in, and here
    // it is checked once more. The supply is the place where an
    // error would be most expensive — it decides whom the node talks to.
    if (!r.isAuthentic) return false;
    final fresh = !entries.has(r.lNode);
    // The source goes in with it: at most a quarter of the supply may
    // stem from ONE partner. Without it the quota in the supply would be
    // built and ineffective.
    if (!entries.remember(r, source: 'partner/$fromPartner')) return false;
    // The acquisition is done — the marker frees the place
    // (S376, P4-1). Without that the position would run as "asked" until the
    // deadline expired, and the next need would wait for it.
    final key = _hex(r.lNode);
    _openEntryRequests.remove(key);
    _missedRecords.remove(key);
    if (fresh) {
      onEntriesChanged?.call();
      log('Entry record learned from partner $fromPartner: '
          '${r.host}:${r.port} '
          '${r.lNode.take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}…');
    }
    // A learned record is at the same time a learned position — but it
    // does NOT make the node eligible. It is only just beginning to run in
    // (E-B), and that does not change because someone names it.
    _learn(r.lNode);
    return fresh;
  }

  /// Short hash prefix — comparable without giving anything away.
  /// The readable part of a pair identifier: "own/counterpart" becomes
  /// the first digits of BOTH sides. Only shortening would mean always
  /// showing the same own identifier (B-31).
  static String _peerLabel(String peer) {
    final parts = peer.split('/');
    String short(String x) => x.length <= 8 ? x : x.substring(0, 8);
    if (parts.length == 2) return '${short(parts[0])}->${short(parts[1])}';
    return short(peer);
  }

  /// The first digits of a position — enough to compare two logs,
  /// too little to be a lasting trace.
  static String _posLabel(Uint8List p) =>
      p.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static String _fingerprint(Uint8List b) => SodiumFFI()
      .sha256(b)
      .take(4)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The book of the OWN placements.
  ///
  /// The key is the identifier from `placeRequestId`, the value is the relay
  /// at which the placement was made, together with the family. **Without this book a
  /// placement receipt cannot be interpreted**: since S357 it carries only the
  /// identifier, and that is intentional — the tag is the mailbox line of a
  /// pair and has no business on the return path (IP-1).
  ///
  /// WHAT HANGS ON THE ENTRY AND WHY. The FAMILY carries the m = 3
  /// redundancy (`DeliveryState.redundant`); the RELAY carries the
  /// independence on which `placed` rests (§22.5.1: "≥ 2 … from
  /// independent relais in different partitions") — the two systematically diverge in the
  /// small network, because `responsibleRelays` computes a target of its own per
  /// family, but draws from the same table.
  /// ATTEMPT and PIECE say to which sealing the receipt
  /// belongs: a message is not always one cell, and evidence from
  /// different attempts does not add up.
  final Map<
      String,
      ({
        Uint8List relay,
        int family,
        Uint8List ackKey,
        Uint8List? messageId,
        int transferId,
        int piece,
        DateTime since
      })> _ownDeposits = {};

  /// How many own placements can wait for a receipt at the same time.
  ///
  /// `placeSecure` enqueues `m x R` = 3 x 20 = 60 legs at once
  /// (`kMaxControlBacklog` is derived from the same number), and the
  /// drain needs 480 s for that. Having four such sends open at the same time
  /// is the normal case of an ongoing conversation;
  /// 1024 carries seventeen of them.
  static const int _maxOwnDeposits = 1024;

  /// How long an OWN placement waits for its receipt.
  ///
  /// **HERE — and only here — the backlog is the right quantity.**
  /// The cell stands in the egress queue of THIS node, and according to
  /// its own comment in `cover_stream.dart` that carries up to
  /// `kMaxControlBacklog` (120) frames at `kSlotInterval` (8 s), i.e.
  /// **960 s = 16 min** before departure. Plus the way there and the receipt
  /// back: `2 x 120 x 8 s` = 32 min.
  ///
  /// The return-path store of the INTERMEDIATE nodes (`DeliveryNode.pending`)
  /// expressly does NOT need this — its entry only arises when
  /// the frame arrives there, i.e. after this waiting time, and it is
  /// passed on immediately. The two deadlines look similar and
  /// belong to different things; a first version of S357
  /// confused them.
  static const Duration kOwnPlacementTtl = Duration(minutes: 32);

  /// Enters an own placement into the book.
  ///
  /// [frame] is the finished `buildPlace` frame — the identifier is
  /// computed from it, not kept alongside. If it were a second value,
  /// the two could diverge.
  void _rememberOwnDeposit(Uint8List frame, Uint8List ackKey,
      Uint8List relay, int family, DateTime current,
      {Uint8List? messageId, int transferId = 0, int piece = 0}) {
    if (_ownDeposits.length >= _maxOwnDeposits) {
      _ownDeposits
          .removeWhere((_, v) => current.difference(v.since) > kOwnPlacementTtl);
    }
    if (_ownDeposits.length >= _maxOwnDeposits) return;
    _ownDeposits[base64.encode(placeRequestId(frame))] = (
      relay: relay,
      family: family,
      ackKey: ackKey,
      messageId: messageId,
      transferId: transferId,
      piece: piece,
      since: current
    );
  }

  /// A control frame dropped out of the queue before it went out.
  ///
  /// If it belongs to an own placement, a PIECE of a
  /// message is thereby lost — not delayed. The entry is removed
  /// (otherwise someone waits until the deadline expires for a receipt for something
  /// that never went out), and the loss is named with the
  /// message instead of only counted.
  ///
  /// Frames that belong to no own placement — harvest requests,
  /// announcements, forwardings — are deliberately silent here: they
  /// repeat in the next tick, and §5.8 knows no state
  /// for them. They are still counted in `droppedControl`.
  void _depositDropped(Uint8List body) {
    final Uint8List identifier;
    try {
      identifier = placeRequestId(body);
    } catch (_) {
      return; // no placement frame
    }
    final record = _ownDeposits.remove(base64.encode(identifier));
    if (record == null) return;
    _discardedDeposits++;
    final mid = record.messageId;
    log('PLACEMENT DROPPED: the control queue was full, a piece did '
        'NOT go out — family ${record.family}, piece ${record.piece}'
        '${mid == null ? '' : ', message ${base64.encode(mid).substring(0, 8)}'}'
        ' (total $_discardedDeposits)');
  }

  /// How many OWN placements the full queue has swallowed.
  int _discardedDeposits = 0;

  /// For the status line and for probes.
  int get discardedDeposits => _discardedDeposits;

  /// A placement receipt for an OWN placement.
  ///
  /// ── WHAT WAS WRONG HERE UNTIL S357, AND TWOFOLD ──────────────
  ///
  /// (1) **The receipt mostly did not arrive at all.** `DeliveryNode`
  /// remembered no return path on placement (as the only
  /// multi-hop frame), the storing relay confirmed to its
  /// PREDECESSOR, and there it ended. Only a placement at a DIRECT
  /// neighbour reached the sender at all.
  ///
  /// (2) **And where it arrived, it was credited to the wrong one.** The
  /// predecessor hop called `onPlaceAck` unconditionally and let its
  /// own readiness rise from a foreign placement. §22.7 bases
  /// readiness expressly on "evidence, not acquaintance" —
  /// that was neither the one nor the other, but foreign evidence.
  ///
  /// ── TO WHOM IT IS NOW CREDITED ────────────────────────────
  ///
  /// To the RELAY that stored, not to the neighbour via which the
  /// receipt came in. That is the statement the evidence carries: "at
  /// this relay placement is possible."
  ///
  /// **DELIBERATELY NARROW: only relays that are also direct partners.**
  /// `ReadinessTracker` keeps its evidence per SESSION and drops it with
  /// it ("A relay that confirmed an hour ago and has
  /// been gone since is no evidence any more"). For a relay three hops
  /// further there is no session that could drop — the evidence would need
  /// a deadline of its own. That is a design question, not a bug fix,
  /// and it has been proposed as such. Until it is decided: the
  /// receipt is booked and counted, readiness does not
  /// touch it.
  ///
  /// **That is no deterioration compared with before.** Before, only
  /// the receipt of a direct neighbour reached the sender at all —
  /// exactly the set that also counts now. The only thing dropped is the wrong
  /// credit at the passing-through hop.
  int foreignRelayProofs = 0;
  int unknownReceipts = 0;

  /// Receipts whose MAC did not hold — someone on the way built them,
  /// not the target relay. A number > 0 is a finding, not noise.
  int forgedReceipts = 0;

  /// The sinks for confirmed OWN placements (see
  /// `V41Delivery.bindPlacementAcked`).
  ///
  /// ── A LIST, NOT A FIELD (S376, P5 finding 1) ─────────────────────
  ///
  /// Here stood a single field, and `bindPlacementAcked` set it —
  /// "a second call REPLACES the first; there is exactly one sink",
  /// so it stood in the contract. But `attachV41` calls it PER IDENTITY
  /// against THE SAME node (`service_daemon.dart`, `main.dart`,
  /// `ios_background_fetch.dart` each have a loop over their
  /// identities). With three identities only the LAST
  /// attached one got its placement receipts; for the other two
  /// `placed` never reached the display, and their local outbox (§21.2) never
  /// let go of their entries.
  ///
  /// The node is one, the services are N — that is no exception
  /// but the design of the whole seam (see the header of
  /// `V41Runtime`). A single slot is always wrong at this point.
  final List<void Function(PlacementAck ack)> _placementSinks =
      <void Function(PlacementAck ack)>[];

  @override
  void bindPlacementAcked(void Function(PlacementAck ack) sink) {
    // WITHOUT DUPLICATE ENTRY. `attachV41` can run a second time for the same identity
    // (re-creation at runtime after a failure);
    // two identical sinks would mean two pieces of evidence from one receipt, and
    // `DeliveryRecord.notePlaced` counts relays, not calls — the
    // damage would be a `placed` that stands on one hand.
    if (!_placementSinks.contains(sink)) _placementSinks.add(sink);
  }

  /// Removes a sink again. **Mandatory on `removeIdentity`** —
  /// otherwise the node keeps reporting to a stopped service.
  void unbindPlacementAcked(void Function(PlacementAck ack) sink) =>
      _placementSinks.remove(sink);

  /// How many identities listen to placement receipts. Metric of the
  /// guard — without it "distributor" could not be distinguished from "single slot
  /// in a new spelling".
  int get placementSinksNumber => _placementSinks.length;

  /// The sink for READINESS CHANGES (§22.7).
  ///
  /// ── WHAT FOR (§21.2, gap G-4) ──────────────────────────────────────
  ///
  /// The local outbox holds messages whose placement is not proven.
  /// For the most frequent kind — `SendRefusal.notReady`, i.e. "no
  /// confirmed relay" — there is exactly ONE moment at which
  /// the situation changes: when a relay confirms. That is this edge.
  ///
  /// IT IS NO CLOCK. §21.2 forbids "timer retry", and §5.1
  /// invariant 1 gives the reason: a rhythm of its own would be recognisable on the wire
  /// as such. This sink fires when EVIDENCE arrives,
  /// not when time passes — the V4.1 counterpart of the V3 edge
  /// `onNetworkChanged`.
  ///
  /// NOT on the interface [V41Delivery], but only here: the
  /// readiness is a state of the NODE, not part of the
  /// delivery contract, and `v41_attach.dart` holds the node
  /// concretely in hand anyway (as with [wireBytesSent] next to it).
  /// ── A LIST, NOT A FIELD (S376, P5 finding 1) ─────────────────────
  ///
  /// For the same reason as with [_placementSinks]: `attachV41` set
  /// this field per identity against the same node, and the second
  /// call threw away the first. For all identities except the
  /// last attached one BOTH thus failed: the drain of the local
  /// outbox at the readiness edge (§21.2 — the only edge at which
  /// a message left lying because of `SendRefusal.notReady` goes out again)
  /// and the display of the readiness state (§25.4).
  final List<void Function(Readiness before, Readiness after)>
      _readinessSinks =
      <void Function(Readiness before, Readiness after)>[];

  /// Registers for readiness changes. Admissible multiple times — one per
  /// identity.
  void addReadinessListener(
      void Function(Readiness before, Readiness after) cb) {
    if (!_readinessSinks.contains(cb)) _readinessSinks.add(cb);
  }

  /// Removes a sink again. **Mandatory on `removeIdentity`.**
  void removeReadinessListener(
          void Function(Readiness before, Readiness after) cb) =>
      _readinessSinks.remove(cb);

  /// How many identities listen to the readiness edge. Measurement quantity.
  int get readinessSinksNumber => _readinessSinks.length;

  /// The control queue has room again for a whole message.
  ///
  /// -- WHY THIS EDGE IS NEEDED (S381, 11.09.2026) --------------
  ///
  /// With [SendRefusal.egressFull] a message stays in the local
  /// outbox. Until S381 its drain hung on EXACTLY ONE edge:
  /// the rise of readiness (`onBereitschaftskante`). A
  /// message that only failed at the full queue would thus have
  /// waited for an event that has nothing to do with its reason —
  /// and that, for a node which is already `ready`, possibly never occurs.
  ///
  /// IT IS NO CLOCK (§21.2 forbids "timer retry", §5.1 invariant 1
  /// gives the reason): it hangs on the slot tick that the node keeps
  /// anyway, and fires only on the EDGE — when the depth falls from "too full"
  /// to "room again". A level would have fired at every slot.
  final List<void Function(String reason)> _egressFreeSinks =
      <void Function(String reason)>[];

  /// Registers for this edge. Admissible multiple times — one per identity,
  /// as with [addReadinessListener].
  void addEgressFreeListener(void Function(String reason) cb) {
    if (!_egressFreeSinks.contains(cb)) _egressFreeSinks.add(cb);
  }

  /// Removes a sink again. **Mandatory on `removeIdentity`.**
  void removeEgressFreeListener(void Function(String reason) cb) =>
      _egressFreeSinks.remove(cb);

  /// How many identities listen to this edge. Metric.
  int get egressFreeSinksNumber => _egressFreeSinks.length;

  /// Was the queue too full for a whole message at the last slot?
  /// Carries the EDGE — see [_egressFreeSinks].
  bool _egressWarFull = false;

  /// The room a Secure message needs at least for it to be
  /// worth waking the outbox: one piece (`m x R`).
  ///
  /// NOT the whole message: how many pieces it has, this
  /// layer does not know. One piece is the smallest amount with which the
  /// outbox can achieve anything at all; whether it suffices is decided once more
  /// by the host itself (`v41_host.dart`).
  static int get egressWakeThreshold =>
      kDeliveryFamilies * kResponsibleRelays;

  /// Checks the edge and reports it. Called from the slot tick.
  ///
  /// THE SAME QUANTITY IS MEASURED AT WHICH `V41Host` REJECTS — the
  /// free control queue. An edge that measures something other than the
  /// bolt wakes the outbox at a moment at which it is rejected
  /// again.
  void _egressPlaceCheck() {
    final free = controlBacklogLimit - pendingControlFrames;
    final fullNow = free < egressWakeThreshold;
    if (_egressWarFull && !fullNow) {
      for (final s in List<void Function(String reason)>.of(_egressFreeSinks)) {
        try {
          s('Control queue free again ($free frames)');
        } catch (e) {
          log('Egress edge: sink threw $e');
        }
      }
    }
    _egressWarFull = fullNow;
  }

  /// Reports a readiness transition — EXACTLY ONCE, from EXACTLY ONE
  /// hand, in BOTH directions.
  ///
  /// ── WHY THIS REPORTER EXISTS (S372) ─────────────────────────────
  ///
  /// `readiness.state` changes at TWO places of this node, not
  /// at one: in [_placeAck] (evidence is added, or a rejection
  /// deletes it) and in [_dropPartner] (the session drops,
  /// `ReadinessTracker.forgetPartner` takes the evidence along). Until S372 the second
  /// only wrote the transition to the log; the descent never reached the
  /// display.
  ///
  /// ONE REPORTER, NOT TWO. Two reporting sites would be two truths
  /// about the same transition — the reason for which the old comment
  /// excluded a second one. It was right about the rule and wrong about
  /// the fact; both are resolved here.
  ///
  /// CAUGHT, because the receiver is the application layer: a throw from
  /// there would run into the frame of the receive path or into the teardown of a
  /// session and would tear the slot along.
  ///
  /// NO TICK OF ITS OWN. The reporter fires on an EDGE — evidence
  /// arrives, a session drops —, not on a clock (§19 "no polling",
  /// §5.1 invariant 1).
  /// [reason] comes as a closure and not as a string: `_placeAck`
  /// runs per placement receipt, a transition is the exceptional case, and
  /// `ReadinessTracker.verifiedRelays` computes over all
  /// partners every time. Passed in ready-made, this text would have cost at EVERY receipt,
  /// instead of only at the ~3 transitions a day.
  /// The last REPORTED state — not the last one that occurred.
  ///
  /// ── WHY THE REPORTER KEEPS ITS "BEFORE" ITSELF (S376, finding 3) ──
  ///
  /// Until S375 every change site passed in its own `vorher` ("before"),
  /// remembered just before the change. That is right exactly when
  /// EVERY change runs through such a site — and one did
  /// not: the expiry of the foreign-evidence deadline. `_sweepRemote` throws
  /// expired evidence away on READING (`readiness.dart`), so
  /// `readiness.state` changes at the moment someone queries it,
  /// without any change site being involved. The transition
  /// `ready -> searching` took place and was never reported: no
  /// display, no IPC event, no drain of the local outbox.
  ///
  /// With a kept state that can no longer happen — the
  /// reporter compares against what the outside world last heard,
  /// and the slot callback asks it regularly. Thus the
  /// reporter still has exactly ONE hand, but it also knows the
  /// transitions that nobody triggered.
  Readiness _reportedReadiness = Readiness.searching;

  void _reportReadiness(String Function() reason) {
    final before = _reportedReadiness;
    final after = readiness.state;
    if (after == before) return;
    _reportedReadiness = after;
    log('Readiness: ${before.name} -> ${after.name} (${reason()})');
    // ONE CATCH PER SINK. A throwing receiver must not rob the
    // remaining identities of their edge — otherwise the
    // outbox drain of all others hangs on the weakest of them.
    // Via a COPY, because a receiver can unregister within its own
    // report (`removeIdentity` from an IPC command that
    // runs in the same round).
    for (final sink in List<
        void Function(Readiness before, Readiness after)>.of(
        _readinessSinks)) {
      try {
        sink(before, after);
      } catch (e) {
        log('Readiness edge: receiver threw $e');
      }
    }
  }

  /// How deep the control queue of the cover stream is right now.
  ///
  /// The drain of the outbox reads it before it enqueues: a
  /// Secure resubmission costs `m x R` frames at once, and
  /// `CoverStream` discards the OLDEST whole group on overflow —
  /// so possibly a message that is regularly in transit right now.
  int get pendingControlFrames => egress.stream.pendingControl;

  /// And the cap for it (`kMaxControlBacklog`).
  int get controlBacklogLimit => egress.stream.maxControlBacklog;

  /// To which SESSION does this relay position belong — or to none?
  ///
  /// A session without a verified position cannot IDENTIFY a relay.
  /// Counting it would mean hanging the evidence on a connection instead of on
  /// a node — exactly the confusion that §22.7 ("evidence, not
  /// acquaintance") excludes. Result `-1`: foreign relay.
  int _partnerIndexOf(Uint8List position) {
    for (var i = 0; i < _channels.length; i++) {
      final pp = _channels[i].peerPosition;
      if (pp != null && _sameBytes(pp, position)) return i;
    }
    return -1;
  }

  void _placeAck(
      Uint8List requestId, bool stored, int fromPartner, Uint8List rawAck) {
    final entry = _ownDeposits.remove(base64.encode(requestId));
    if (entry == null) {
      // No own placement. Either the entry has expired, or a
      // neighbour sends receipts at random. Neither changes anything:
      // without an entry there is nothing to prove.
      //
      // IT IS SAID NONETHELESS (S379). This branch is the silent
      // exit of the receipt, and silent it could not be distinguished in the field
      // from "none came at all": a node whose
      // return-path entry has expired at the PREDECESSOR gets the
      // foreign receipt delivered and discards it here — the same
      // log line `Ablage bestaetigt` then stands in the neighbour log as for
      // a genuine own placement.
      unknownReceipts++;
      log('Deposit receipt without own entry (identifier '
          '${tagLabel(requestId)}, via partner $fromPartner) — '
          'total $unknownReceipts, book ${_ownDeposits.length}');
      return;
    }
    // ── THE EVIDENCE IS CHECKED BEFORE IT COUNTS ──────────────────────
    //
    // The identifier alone proves nothing: it is computed from `ephPk`,
    // and every hop reads that in plaintext. Without this check
    // the first neighbour could throw away the frame and acknowledge it himself — and
    // the sender would credit the evidence to the relay that never saw
    // anything (counter-reading S357, point E). The MAC only holds under
    // `ss` from the placement seal, and that is held exclusively by sender
    // and target relay.
    if (!verifyPlaceAck(rawAck, entry.ackKey)) {
      forgedReceipts++;
      log('Deposit receipt for ${_posLabel(entry.relay)} DISCARDED — '
          'MAC does not hold (via partner $fromPartner)');
      return;
    }
    // ── THE REPORT UPWARDS ─────────────────────────────────────────
    //
    // Only here, behind the MAC check: a receipt that does not stem from the
    // target relay must not move `placed` — otherwise the
    // whole authentication effort above would be in vain. And only on
    // `stored`: a rejection says that the relay could NOT
    // place, it is the opposite of evidence.
    final relay = entry.relay;
    // ── AND IT COUNTS FOR THE ELIGIBILITY GATE (S376, P4-2) ──────────────────
    //
    // Behind the MAC check, i.e. behind the only proof that
    // EXACTLY THIS relay got the cell: the MAC only holds
    // under the `ss` from the placement seal. That is work in this
    // epoch, and work is the currency in which §10.3 reckons.
    //
    // Also on `stored == false`: a rejection ("my quota is full")
    // is an AUTHENTICATED answer of a running node. It is no good
    // as delivery evidence — `stored` further below stands for that —, but
    // it proves uptime, and only that counts for the gate.
    _proofsWork(relay);
    final rec = entries.lookup(relay);
    final parts = rec == null ? const <String>{} : Partition.ofRecord(rec);
    // ── THE REPORT UPWARDS ─────────────────────────────────────────
    //
    // Only here, behind the MAC check: a receipt that does not stem from the
    // target relay must not move `placed` — otherwise the
    // whole authentication effort above would be in vain. And only on `stored`:
    // a rejection says that the relay could NOT place, it is
    // the opposite of evidence.
    //
    // THE RELAY AND ITS NETWORK BLOCK ARE PASSED ALONG, not only the
    // family. §22.5.1 requires "≥ 2 … from independent relais in
    // different partitions"; the family is the m redundancy, not the
    // independence evidence. In the small network the same relay regularly
    // acknowledges two families — a counter over families would then tip
    // to `placed` with the evidence of a single hand.
    final mid = entry.messageId;
    if (stored && mid != null) {
      final proof = (
        messageId: mid,
        transferId: entry.transferId,
        piece: entry.piece,
        family: entry.family,
        relay: relay,
        partitions: parts,
      );
      // TO EVERY IDENTITY, via a copy and with a catch of its own per
      // sink (S376, P5 finding 1). Which identity sent the message
      // the NODE does not know — it only knows the
      // placement identifier. The assignment happens one level higher:
      // `CleonaService.noteV41Placement` looks up the identifier in its own
      // delivery register and turns back immediately on `null`. A
      // receipt that belongs to another identity costs one
      // map access there and moves nothing.
      for (final sink
          in List<void Function(PlacementAck)>.of(_placementSinks)) {
        try {
          sink(proof);
        } catch (e) {
          log('Placement receipt: receiver threw $e');
        }
      }
    }
    // Is the storing relay one of our direct partners? Then
    // its session has a number under which the evidence drops with it.
    final partnerIndex = _partnerIndexOf(relay);
    if (partnerIndex < 0) {
      // ── FOREIGN RELAY: COUNTS, BUT WITH A CLOCK ───────────────────────
      //
      // The evidence says "at this relay placement is possible", and that
      // holds regardless of whether we are connected to it (§22.7,
      // "evidence, not acquaintance"). What is missing is the session whose
      // dropping otherwise lets the evidence expire — for that the deadline stands
      // in `ReadinessTracker.remoteEvidenceTtl`.
      foreignRelayProofs++;
      readiness.observeRemotePlaceAck(
        relayPosition: relay,
        stored: stored,
        now: DateTime.now().toUtc(),
        partitions: parts,
      );
    } else {
      readiness.observePlaceAck(
        partner: partnerIndex,
        partnerPosition: relay,
        stored: stored,
        partitions: parts,
      );
    }
    // WHAT IT MOVED (S379). Up to here the field log only showed
    // `Ablage bestaetigt` from `DeliveryNode` — the statement "a receipt
    // arrived", without WHOSE relay it was and whether it moves
    // readiness. A node that stands at `connecting` for forty minutes
    // while ten such lines pass through thus cannot be
    // interpreted: ten receipts of the same relay look like ten
    // different ones.
    log('Placement receipt from ${_posLabel(relay)} '
        '(${partnerIndex < 0 ? 'foreign relay' : 'partner $partnerIndex'}, '
        '${stored ? 'accepted' : 'rejected'}, family ${entry.family})'
        ' — confirmed relays now ${readiness.verifiedRelays}');
    // ── THE EDGE, BOTH DIRECTIONS (§21.2 gap G-4, §25.4) ─────────
    //
    // UNTIL S372 HERE STOOD the claim that this was "the ONLY place in the
    // tree at which `readiness.state` can change". It was wrong,
    // and the reporting site therefore remained incomplete: a dropped
    // session also takes away evidence via `ReadinessTracker.forgetPartner`
    // (`_dropPartner`), and there the transition was until S372
    // only written to the log.
    //
    // The sentence that forbids a SECOND reporting site is nonetheless
    // right — that is why there is now exactly ONE reporter,
    // [_meldeBereitschaft], and both change sites call it.
    _reportReadiness(
        () => '${readiness.verifiedRelays} confirmed relays, of which '
            '${readiness.remotePositions.length} without an own session');
  }

  /// Should THIS node set up the connection to [peerPosition]?
  ///
  /// THE PROBLEM. If two nodes learn of each other at the same time — in the local network
  /// that is the normal case, both call and both listen —, then
  /// each dials the other and there are TWO connections between
  /// the same two nodes. That is not merely ugly: the cover stream
  /// runs per partner, so the traffic to this neighbour doubles,
  /// and the partner count from which the slot plan draws counts him twice.
  ///
  /// THE SOLUTION WITHOUT ARRANGEMENT. Whoever has the smaller position dials.
  /// Both sides know both positions as soon as they have the records,
  /// and the order is total — so each decides the same for itself,
  /// without exchanging a message about it. A simultaneous open
  /// thus does not arise in the first place; none has to be resolved either,
  /// and exactly on that hung the deadlock from S342.
  bool shouldDial(Uint8List peerPosition) {
    for (var i = 0; i < 32; i++) {
      if (keys.lNode[i] != peerPosition[i]) {
        return keys.lNode[i] < peerPosition[i];
      }
    }
    return false; // nobody dials himself
  }

  /// Resolves to which link a path block belongs. Tries and remembers
  /// — see `reply_block_resolver.dart`.
  late final ReplyBlockResolver blockResolver;

  /// The pair keys. Without them WP-2 (liveness) and WP-4 (Secure) are
  /// built and dead — both need `K_AB`.
  late final PairRegistry pairs;

  /// How many partners this node holds and in which mix.
  final PartnerPolicy policy = const PartnerPolicy();

  /// The address families of the existing partners.
  ///
  /// Only those that can be DETERMINED: the family comes from the
  /// entry record for the verified position. An anonymous session does not count
  /// here — it is neither credited nor charged for the diversity,
  /// because nothing is known about it.
  List<AddressFamily> get partnerFamilies {
    final out = <AddressFamily>[];
    for (final c in _channels) {
      final pos = c.peerPosition;
      if (pos == null) continue;
      final r = entries.lookup(pos);
      if (r == null) continue;
      out.addAll(familiesOfRecord(r));
    }
    return out;
  }

  /// Does this node want [r] as a partner?
  ///
  /// Only when that is answered with `true` is the question WHO dials worthwhile
  /// ([shouldDial]) — otherwise one would set up a connection only to treat it
  /// right away as surplus.
  bool wantsPartner(EntryRecord r) =>
      policy.wantsForDiversity(partnerFamilies, familyOfRecord(r));

  /// Makes room for a partner of the family [candidate] — or `null`
  /// if no room is needed or none can be given up.
  ///
  /// ── THE GAP, MEASURED ON 09.09.2026 (S378) ──────────────────────
  ///
  /// `PartnerPolicy.evictFor` and `weakerShare` were built and had
  /// **no caller**. Thus the countermeasure that §11 provides for
  /// the address families was missing ("below 25 % share of the weaker
  /// family, raise to two partners per family"): `wantsPartner` did say
  /// "yes" to a v6 candidate, even if all four places
  /// were occupied with v4 — only nobody made room. The candidate was
  /// wanted and never taken in.
  ///
  /// ── WHY NOT `evictFor` DIRECTLY ──────────────────────────────────
  ///
  /// `evictFor` returns an index into [partnerFamilies], and this
  /// list is NOT index-aligned with [_channels]: it skips
  /// channels without a position (`continue`) and takes in all
  /// families per record (`addAll`) — a dual-stack neighbour thus stands in it twice,
  /// a positionless channel not at all. The index thus pointed
  /// to the wrong partner. That is why work here is done CHANNEL BY CHANNEL
  /// and `evictFor` is only asked WHETHER eviction is allowed.
  ///
  /// ── CONSERVATIVE, AND DELIBERATELY SO ──────────────────────────────
  ///
  /// Eviction only happens if (a) there is no room left, (b) the alarm from
  /// §11 is present, (c) the candidate comes from the WEAKER family and
  /// (d) there is a channel whose families ALL belong to the over-
  /// represented one. A dual-stack neighbour is never sacrificed — he is
  /// exactly the translator between the families that this is about.
  LinkChannel? evictFor(AddressFamily candidate) {
    if (partnerCount < policy.target) return null;
    final families = partnerFamilies;
    if (!policy.diversityAlarm(families)) return null;
    // The candidate must strengthen the weaker side, not the strong one.
    final v4 = families.where((f) => f == AddressFamily.v4).length;
    final v6 = families.length - v4;
    final weaker = v4 < v6 ? AddressFamily.v4 : AddressFamily.v6;
    if (candidate != weaker) return null;
    if (policy.evictFor(families, candidate) == null) return null;
    // Channel by channel: only one whose families ALL belong to the strong one.
    for (final c in _channels) {
      final pos = c.peerPosition;
      if (pos == null) continue;
      final r = entries.lookup(pos);
      if (r == null) continue;
      final f = familiesOfRecord(r);
      if (f.isEmpty) continue;
      if (f.every((x) => x != candidate)) return c;
    }
    return null;
  }

  /// Disconnects [c] — the public path to [_dropPartner] for the
  /// family eviction. All five index-aligned lists collapse
  /// together, as described there.
  void separatePartner(LinkChannel c) => _dropPartner(c);

  /// The readiness state (§22.7) — the only statement about
  /// deliverability that this node may make.
  final ReadinessTracker readiness = ReadinessTracker();

  /// §22.7 to the outside. The tracker remains the bookkeeper, but the
  /// layer above should not have to take it apart — it
  /// gets the state, not the book.
  @override
  Readiness get readinessState => readiness.state;

  /// Publishes the own liveness for all known pairs.
  ///
  /// HOW IT GETS THERE. `livenessTarget(K_AB, e)` is a POSITION in the
  /// hash space, not a node. The node therefore looks up the positions known to it
  /// that lie nearest to it, and places at those whose
  /// entry record it has — it needs that in order to seal to them.
  /// The placement then finds its way itself (§11.2, greedy).
  ///
  /// WHY ONLY AT THOSE WITH A RECORD. Without the static X25519 part
  /// nothing can be sealed to them, and unsealed one would expose the
  /// tag to every intermediate node. Better fewer copies than a
  /// tag that can be read along.
  ///
  /// ── OVER THE WHOLE RESPONSIBILITY SET, AND ONLY ONCE PER EPOCH
  /// (S354) ────────────────────────────────────────────────────────────
  ///
  /// Until S354 `copies = 3` placements at the three nearest
  /// known relays stood here. §6 requires something else: "replicated over the R
  /// responsible relays". The difference is not redundancy cosmetics
  /// but the prerequisite for the other side finding the record
  /// AT ALL: the harvest samples the set (one relay per run,
  /// `kHarvestRelaysPerFamily`, S353), and this sampling is only
  /// admissible because the PLACEMENT covers the whole set. Three placements against
  /// a sample from up to twenty means: in four of five cases
  /// the sender asks a relay that never got the record.
  /// The same calculation that §9.2 makes for Secure applies here.
  ///
  /// IN RETURN ONLY ONCE PER EPOCH. So far, at EVERY new
  /// session, publishing happened anew for EVERY pair — with eight contacts thus
  /// 24 control frames per session setup, over the full set it would be
  /// 160. That is exactly the inflow that made the node deaf for minutes
  /// in the field on 29.08. (S353). But the record only changes
  /// at two events: the epoch moves (§6, 24 h), or the
  /// return-path partner r2 changes. Both stand in [_ownLiveness]; if
  /// neither has happened, the publication is a repetition
  /// without receiver and is omitted.
  ///
  /// The liveness thus costs `min(R, known relays)` cells per
  /// Speed contact and day — the quantity that §6 budgets as "the R=20 publish
  /// term is the fixed floor".
  ///
  /// Returns how many placements were enqueued.
  int publishLiveness({DateTime? now, bool force = false}) {
    final current = now ?? DateTime.now().toUtc();
    var enqueued = 0;
    // ── ONLY COUNTERPARTS FROM WHOM HARVESTING ALSO HAPPENS ─────────────────
    //
    // The liveness is the own RETURN PATH (§6) — it only makes sense
    // where someone can fetch and use it. A pure placement line
    // (`PairRegistry.isPlaceOnly`, today the device line of a
    // sister) has no counterpart that answers; a record
    // there would cost `min(R, known)` cells a day for a path that
    // nobody takes.
    for (final peer in pairs.harvestPeers) {
      // ONLY FOR SPEED-CAPABLE COUNTERPARTS (§6, M5). "Only Speed-capable
      // contacts need liveness — a Secure-only contact plants to a tag,
      // not to a live path. The per-chat Secure/Speed setting (§12)
      // therefore bounds this cost directly." Without this line
      // liveness scales with ALL contacts instead of with S: with a hundred
      // contacts and R = 20 that would be 2000 cells a day, i.e. about
      // a fifth of all slots — for chats that do not even use the fast path.
      //
      // THE DEFAULT IS TO PUBLISH. The mode is a one-sided
      // sender choice (§12); whoever has set nothing here counts as
      // Speed-capable, because Speed is the default. The price of the
      // asymmetry is openly stated: if A sets the chat to Secure, B finds
      // no return path to A and sends to A via Secure — slower,
      // not broken, and exactly the gradation that §7.2 provides for the
      // epoch cold start anyway.
      if (_secureOnly.contains(peer)) continue;
      final kAb = pairs.kAbFor(peer);
      if (kAb == null) continue;
      final epoch = livenessEpoch(kAb, current);
      // PUBLISHING HAPPENS UNDER THE OUTGOING DIRECTION, harvesting under
      // the opposite direction — the same order as with the Secure tag
      // (B-22). Without it both partners would place under the same tag
      // and harvest their own record back.
      final direction = pairs.outDirectionFor(peer);
      final target = livenessTarget(kAb, epoch, direction);
      final tag = livenessTag(kAb, epoch, direction);

      // THE RECORD IS THE RETURN PATH. §6: "encoded as an onion return
      // path (never a bare exit-relay)" — so `r2-Kennung ‖ Wegblock`,
      // exactly the pair that `SpeedRoute` needs. Until S348 the
      // own position stood here as a placeholder ("so that the form is right"), and
      // with that no sender could ever build a Speed route: `SpeedEgress`
      // threw `keine Speed-Route`, and the message did not go.
      //
      // WHO IS r2. A partner whose position is verified — only him
      // can A address, and only to him does B hold a link key
      // under which the path block lies post-quantum-securely (§7). Without such a
      // partner there is no return path, and then nothing is
      // published either: a record without a path would be worse than
      // none, because the sender would consider it valid.
      final r2 = _pickReturnRelay();
      if (r2 == null) continue;

      // REPETITION WITHOUT CHANGE IS OMITTED (see header). Compared
      // against ALL THREE quantities that determine the record: the
      // epoch, the return-path partner — and the LINK KEY to him.
      //
      // ── WHY THE THIRD WAS ADDED (S355) ─────────────────────────────
      //
      // Only epoch and position were compared, and that let exactly
      // the case fall through that makes Speed go dark: the session to r2
      // breaks off and is set up anew. Position and epoch are
      // unchanged, the link key is a different one — and a
      // path block under the old key no longer redeems at r2.
      // The publication was suppressed as a repetition,
      // the DEAD record stayed lying at the relays, and the sender
      // kept harvesting it until the end of the epoch.
      //
      // What is compared is a fingerprint, not the key itself: it should
      // not lie in memory longer than necessary.
      final keyFingerprint =
          Uint8List.sublistView(SodiumFFI().sha256(r2.linkKey), 0, 8);
      final already = _ownLiveness[peer];
      if (!force &&
          already != null &&
          already.epoch == epoch &&
          _sameBytes(already.r2, r2.position) &&
          _sameBytes(already.key, keyFingerprint)) {
        continue;
      }

      final routeBlock = buildReplyBlock(
        linkKeyToR2: r2.linkKey,
        handleOfB: keys.lNode,
        seed: SodiumFFI().randomBytes(kSeedBytes),
        epoch: epoch,
      );
      // THE PUBLICATION MARK (§6, S355): seconds since the beginning
      // of this pair epoch, big-endian. It decides at the harvester
      // which of several records under the same tag is the
      // live one — see `livenessMark` and `_livenessUebernehmen`.
      final mark = livenessMark(kAb, current);
      final content = Uint8List(kLivenessRecordBytes)
        ..setRange(0, kHopIdBytes, r2.position)
        ..setRange(kHopIdBytes, kHopIdBytes + kReplyBlockBytes, routeBlock);
      final mv = ByteData.sublistView(content, kHopIdBytes + kReplyBlockBytes);
      mv.setUint32(0, mark);

      // ── THE SET IS SMALLER THAN FOR A MESSAGE (S381) ──────
      //
      // [kLivenessRelays], not [kResponsibleRelays]. The read side
      // below (`_livenessAbfragen`) computes with THE SAME number from
      // THE SAME tag — only then does its sample hit. The price and
      // the measurement from which the number comes stand at the constant.
      final responsible = responsibleRelays(target, count: kLivenessRelays);
      for (final rec in responsible) {
        final built = buildPlace(rec.lNode, rec.x25519Public, tag, content);
        // Family 0: the liveness knows no families (§6, it lies
        // under ONE tag). The entry here serves readiness and
        // diagnosis, not `notePlaced`.
        _rememberOwnDeposit(built.frame, built.ackKey, rec.lNode, 0, current);
        egress.stream.enqueueControl(built.frame);
        enqueued++;
      }
      // ONE ALWAYS HOLDS THE OWN RETURN PATH ONESELF — not only when the
      // metric happens to count one among the responsible ones.
      //
      // On the Secure side self-placement is bound to `isSelfResponsible`
      // (B-34), and that is right there: a message lies
      // with the responsible ones, nowhere else. The liveness is something
      // different — it is the information about THIS node. If it is asked
      // for it, the answer is always available; refusing it
      // because the hash distance happens to be unfavourable would be the only
      // place in the system at which a node does not know its own reachability.
      //
      // IN THE SMALL NETWORK THIS IS THE DIFFERENCE BETWEEN WORKS AND DOES
      // NOT WORK: the sender samples the responsibility set (one relay
      // per attempt), and in a network of four nodes the counterpart
      // ITSELF is often the next candidate. Without this line it then answers
      // "nothing under the tag" — of all things about itself.
      // Costs no cell.
      delivery.store.place(tag, content, nodeEpochNow(current));

      // ONLY REMEMBER WHEN SOMETHING WENT OUT. If the note were
      // unconditional, a run without a single known relay would have
      // ticked off the epoch as "done", and the record would stay
      // unpublished until the next epoch change — 24 h invisible,
      // triggered by an empty table in the first minute.
      if (responsible.isNotEmpty) {
        _ownLiveness[peer] = (
          epoch: epoch,
          r2: r2.position,
          key: Uint8List.fromList(keyFingerprint)
        );
      }
    }
    return enqueued;
  }

  /// What this node last placed under its liveness tag.
  ///
  /// WHAT FOR: avoiding repetitions. §6 lets exactly THREE events
  /// trigger a new publication — the epoch moves, the
  /// return-path partner r2 changes, or the link key to r2 changes
  /// (i.e.: the session was set up anew). All three stand here.
  ///
  /// The content itself does NOT stand in it. It was there to recognise the own
  /// record when harvesting; since the tag carries a direction,
  /// it can no longer turn up there at all.
  final Map<String, ({int epoch, Uint8List r2, Uint8List key})>
      _ownLiveness = {};

  /// Chooses a partner as r2 for the own return path.
  ///
  /// ONLY A VERIFIED ONE. An anonymous session is no good: A must be able to
  /// name r2 in order to route at all (§7), and for that its
  /// position is needed. If this node knows no such partner, there is
  /// no return path — then the liveness stays silent instead of promising a path
  /// nobody can walk.
  ({Uint8List position, Uint8List linkKey})? _pickReturnRelay() {
    for (var i = 0; i < _channels.length && i < _partners.length; i++) {
      final pos = _channels[i].peerPosition;
      if (pos == null) continue;
      return (position: pos, linkKey: _channels[i].deliveryKey);
    }
    return null;
  }

  /// Whom the probe can ask, in the order in which it makes sense.
  ///
  /// ── FIRST THE OWN PARTNERS (S379) ──────────────────────────────
  ///
  /// MEASURED on 09.09.2026: `.201` placed six cells in two probes at
  /// a position that it only knew from an entry record
  /// — no partner, no session. From this position came
  /// **not a single** receipt, while EVERY placement at a direct
  /// partner was acknowledged. The way there ended at the only
  /// neighbour as a BLIND PLACEMENT (§11.2, "a relay that knows no nearer
  /// partner … stores rather than dropping"), and a blind placement
  /// expressly does NOT confirm — the blind keeper has no
  /// evidence that he can place for this day.
  ///
  /// A relay to which this node HAS a session is thus the
  /// only addressee at which a placement CAN be acknowledged without outside help.
  /// For the probe — whose only purpose is the evidence —
  /// that is the right first choice.
  ///
  /// THIS DOES NOT TURN ACQUAINTANCE INTO EVIDENCE. §22.7 ("evidence, not
  /// acquaintance") remains untouched: what counts is still only the
  /// receipt, and that carries a MAC under the `ss` from the
  /// placement seal, which only the TARGET relay can compute. A partner
  /// that does not place remains without evidence here like any other.
  ///
  /// AFTER THAT THE TABLE, unchanged. In a network large enough
  /// that there is a path between two nodes, a foreign
  /// relay is a perfectly valid addressee — and §22.7 expressly wants evidence
  /// from such ones as well (`observeRemotePlaceAck`). The
  /// order only says where to ask first.
  Iterable<Uint8List> _probeCandidates(Uint8List target) {
    final partner = <Uint8List>[
      for (final c in _channels)
        if (c.peerPosition != null) c.peerPosition!,
    ]..sort((a, b) => compareDistance(target, a, b));
    return <Uint8List>[
      ...partner,
      for (final k in table.closest(target, count: 8)) k.position,
    ];
  }

  /// Cold-start probe (§22.7.1): places a cover cell in order to gain
  /// evidence. Returns how many families were enqueued.
  ///
  /// WHY IT IS NEEDED. §22.7.1 counts as a "verified outbound relay"
  /// only one that has CONFIRMED placement capability. The confirmation
  /// arises from `observePlaceAck`, that from a placement — and until S348
  /// the placement lay behind exactly the gate it was supposed to open. A node
  /// with sessions but without contacts could never leave the circle:
  /// `placeSecure` needs `K_AB`, and without a counterpart there is none.
  ///
  /// WHY COVER AND NOT A PROBE OP OF ITS OWN. The control channel `0x04` is
  /// open, so a new op would be allowed — but it would be a type of its own,
  /// recognisable, and the partner would read from it: "this node is looking for
  /// relays", i.e. "it is cold". A placement cannot be distinguished from a real
  /// one; that is the purpose of the cover stream. The price lies
  /// with the relay: [families] cells of 1200 B that nobody harvests and that
  /// expire with the normal deadline.
  ///
  /// THE TAG IS NODE-LOCAL. It comes from a secret that only this
  /// node has, in the same form as a pair tag (`secureTag`).
  /// Nobody can recompute it, nobody harvests under it, and on the
  /// wire it looks like any other. It is EXPRESSLY not a
  /// pair tag: it must not coincide with any counterpart, otherwise filler
  /// material would lie under a real tag.
  ///
  /// IT RIDES THE TICK. `enqueueControl` fills a slot that goes out
  /// anyway — no additional traffic, no spike (invariant 1).
  int probePlacement({DateTime? now, int families = kDeliveryFamilies}) {
    if (partnerCount == 0) return 0;
    final current = now ?? DateTime.now().toUtc();
    // Node-local secret in pair-tag form. A label of its own, so that
    // it never overlaps with `secure/...` of a real pair.
    final probeSecret = SodiumFFI().hkdfSha256(
      keys.nX25519Secret,
      salt: SodiumFFI()
          .sha256(Uint8List.fromList(utf8.encode('cleona-v41-probe/salt/v1'))),
      info: Uint8List.fromList(utf8.encode('cleona-v41-probe/v1')),
      length: 32,
    );
    final epoch = secureEpoch(probeSecret, current);
    // Filler material the size of an ordinary placement — a
    // conspicuously short cell would itself be the signal that is avoided.
    final content = SodiumFFI().randomBytes(kMaxPlaceContentBytes);
    var enqueued = 0;
    // WHERE THE PROBE GOES — for the same reason for which `placeSecure`
    // writes down its target per family. The probe is the only
    // placement of a cold node; if readiness stays at
    // `connecting`, the first question is "did it ask three
    // DIFFERENT relays or the same one three times?" — and that
    // could not be answered in the field until S379, because only the NUMBER of
    // enqueued families stood in the log.
    final chosen = <String>[];
    // ── ONE RELAY CARRIES EXACTLY ONE PIECE OF EVIDENCE (S379) ────────────────────
    //
    // MEASURED on 09.09.2026 on all three test nodes, in the same run:
    //
    //   `Boot  Sonde -> 0->d1f88a49[P0], 1->d1f88a49[P0], 2->d1f88a49[P0]`
    //   `.201  Sonde -> 0->d1f88a49, 1->d1f88a49, 2->d1f88a49`
    //   `.202  Sonde -> 0->451e4dcc, 1->451e4dcc, 2->d1f88a49`
    //
    // All three families ran to ONE relay. The reason is in the
    // loop below: it takes the FIRST of the eight nearest
    // neighbours that has an entry record — and in a small
    // table that is the same node for every family target.
    //
    // WHY THAT MAKES THE PROBE WORTHLESS. §22.5.1 counts evidence from
    // "independent relais in different partitions"; three cells at
    // ONE relay are ONE piece of evidence. `ready` requires two. A cold
    // node could thus probe as often as it liked and stayed at
    // `connecting` — measured on 09.09. over 40 minutes and
    // twelve probes, without anything moving. The m = 3
    // redundancy of the families is the DELIVERY redundancy (`DeliveryState`),
    // not the independence evidence; the two have
    // diverged here.
    //
    // SO: ONE CELL PER RELAY. If a relay is already taken, the
    // family keeps searching; if it finds none left, it is NOT enqueued.
    // A fourth cell to the same relay costs a slot and brings
    // no evidence — and three cells under three tags in quick
    // succession at THE SAME neighbour are moreover more conspicuous
    // than one.
    final proven = <String>{};
    for (var f = 0; f < families; f++) {
      // Direction 0 fixed: the probe is node-local, there is no
      // counterpart and thus no order between two.
      final tag = secureTag(probeSecret, epoch, f, 0);
      final target = targetFor(tag, epoch);
      for (final k in _probeCandidates(target)) {
        if (!proven.add(base64.encode(k))) continue;
        final r = entries.lookup(k);
        if (r == null) {
          proven.remove(base64.encode(k));
          continue;
        }
        final built = buildPlace(r.lNode, r.x25519Public, tag, content);
        // THE PROBE IS THE REASON WHY THE BOOK MUST EXIST: it
        // expressly waits "for placement confirmation", and without an
        // entry the returning receipt could not be assigned
        // to it.
        _rememberOwnDeposit(built.frame, built.ackKey, r.lNode, f, current);
        egress.stream.enqueueControl(built.frame);
        final pi = _partnerIndexOf(r.lNode);
        chosen.add('$f->${_posLabel(r.lNode)}'
            '${pi < 0 ? '[fremd]' : '[P$pi]'}');
        enqueued++;
        break;
      }
    }
    if (enqueued > 0) {
      log('Readiness: probe enqueued ($enqueued family(ies)) — '
          'waiting for placement confirmation '
          '(relays ${chosen.join(', ')}, table ${table.length})');
    }
    if (enqueued < families) {
      // NOT SILENT. Fewer families than m means: this node knows
      // fewer relays than `ready` requires evidence — that is a
      // statement about the NETWORK, not about the probe, and it belongs
      // in the log. Without it a node that CANNOT know two
      // independent relays at all looks exactly like one to which
      // nobody answers.
      log('Readiness: only $enqueued of $families family(ies) — '
          'that is how many different relays with an entry record '
          'this node knows (table ${table.length}, partners $partnerCount)');
    }
    return enqueued;
  }

  @override
  void rememberPeer(String peer, Uint8List kAb,
          {int outDirection = 0, bool harvest = true}) =>
      pairs.remember(peer, kAb, outDirection: outDirection, harvest: harvest);

  @override
  void forgetPeer(String peer) {
    // EVERYTHING THAT HANGS ON THE PAIR, and that at ONE place. If one spreads
    // the forgetting over the callers, one is left lying at the next new
    // state — exactly so `SecureStore.expire` (B-32)
    // stayed without a caller unnoticed for years.
    pairs.forget(peer);
    egress.clearRoute(peer);
    _routesEpoch.remove(peer);
    _routesMark.remove(peer);
    _ownLiveness.remove(peer);
    _livenessAttempts.remove(peer);
    _livenessOffset.remove(peer);
    _secureOnly.remove(peer);
    _harvestMemo.remove(peer);
    _harvestOffset.remove(peer);
    _catchUpPointer.remove(peer);
    _harvestAssembler.remove(peer);
    // What already lies in the own store under the tags of this pair
    // stays lying and expires with the normal deadline: it is sealed against the
    // counterpart, this node cannot open it anyway,
    // and targeted deletion would be the information "this pair existed here".
  }

  @override
  int get maxPayloadBytes => kMaxPlaceContentBytes < kMaxOnionMessageBytes
      ? kMaxPlaceContentBytes
      : kMaxOnionMessageBytes;

  /// Submits a message (IP-2).
  ///
  /// The order of the checks is intentional: first what cannot work at all
  /// (no pair key, too large), then what does not work right now (no
  /// confirmed relay). The first two do not change by
  /// waiting — the third does.
  @override
  SendOutcome send({
    required String peer,
    required Uint8List payload,
    required SendMode mode,
    Uint8List? messageId,
    int transferId = 0,
    int piece = 0,
    // §22.5.1 standardises `TtlClass ttl = TtlClass.standard` on `sendToUser`
    // — not built in the code (`grep -rn TtlClass lib/` returns nothing).
    // [management] is the minimal, orthogonal counterpart for it, ONLY
    // for [SendMode.secure]: see reasoning at `placeSecure`.
    bool management = false,
  }) {
    if (pairs.kAbFor(peer) == null) {
      return const SendOutcome.refused(SendRefusal.noPairKey);
    }
    // Traffic in this direction keeps the pair in the active harvest rank. Whoever
    // writes gets an answer — and that wants to be harvested without waiting behind
    // all cold contacts.
    _lastTraffic[peer] = DateTime.now().toUtc();
    if (payload.length > maxPayloadBytes) {
      // No error of the delivery, but §5.3/B-13: media belong on
      // the two-stage path and do not ride along in the cover stream.
      return const SendOutcome.refused(SendRefusal.tooLarge);
    }
    // ── WITHOUT PARTNERS NOTHING GOES OUT (S376, finding 2) ─────────────
    //
    // Not the readiness gate, and not in its place: this is
    // a statement about the WIRE, not about evidence. Without a
    // running session there is nobody to whom a cell could go
    // — `DeliveryNode.tick` sends per slot to
    // `partners[p % partners.length]`, and this list is empty.
    //
    // WHAT HAPPENED WITHOUT THIS BOLT, measured at the queues:
    // `placeSecure` only checks `pairs.kAbFor(peer)` and enqueues its
    // `m x R` frames (§9.2, up to 60) even when `partnerCount`
    // is 0. It then returned `n > 0`, `send` answered
    // `SendOutcome.accepted`, and the application booked the message as
    // handed over. Not one of them ever appeared on the wire: until S375
    // `tick` threw away every frame it took without a partner; since the
    // finding-2 fix they stay in the control queue — but that holds
    // [kMaxControlBacklog] = 120 frames and on overflow discards the
    // oldest WHOLE group. Two messages fill it.
    //
    // THE HONEST ANSWER IS `notReady`. Then the message stays in
    // the local outbox (§21.2, "the outbox stays local until >= 2
    // placement acks"), and it goes out as soon as the
    // readiness edge rises — the path §21.2 provides for this,
    // and which without this bolt was never even entered.
    //
    // BEFORE THE BRANCHING, because it applies to ALL four modes: Secure and
    // Signal enqueue control frames, Speed and SpeedOnly enqueue at the
    // egress, whose slot likewise goes into the void.
    //
    // NO ADDITIONAL NETWORK TRAFFIC (working rule 5): the bolt reads
    // a list length.
    if (partnerCount == 0) {
      return const SendOutcome.refused(SendRefusal.notReady);
    }
    // THE READINESS GATE USED TO STAND HERE, BEFORE THE BRANCHING — and
    // was thus a circle: `readiness` only rises through a confirmed
    // PLACEMENT (`observePlaceAck`), the placement lay behind the gate, and no
    // node could break the circle from outside. Measured on 25.08.:
    // two connected nodes, `Sitzung 1 in Betrieb` on both sides,
    // `readiness = searching`, and EVERY message `notReady`.
    //
    // Secure does not need the gate: `placeSecure` itself reports how many
    // families it could place, and 0 is exactly the statement the
    // gate wanted to make. Speed needs it because it FORWARDS via a relay
    // and cannot go anywhere without a confirmed relay.
    switch (mode) {
      case SendMode.secure:
        final n = placeSecure(
            peer: peer,
            payload: payload,
            messageId: messageId,
            transferId: transferId,
            piece: piece,
            management: management);
        return n == 0
            ? const SendOutcome.refused(SendRefusal.notReady)
            : SendOutcome.accepted(n);
      case SendMode.signal:
        // THE SIGNAL LINE (§17.2). The same placement process as Secure, only
        // under `signalTag`, with `kSignalRelays` instead of
        // `kResponsibleRelays` and with `kRetentionSignal`.
        //
        // NO FALLBACK TO THE MESSAGE LINE if it does not work.
        // That would be the expensive path this branching just abolishes:
        // 60 placements = 480 s egress for a cell that expires after 120 s.
        // If no family could be placed, the honest
        // answer is `notReady` — the caller sees "reaching" and runs into
        // his deadline, instead of an INVITE consuming egress that
        // no longer reaches anyone.
        final s = placeSecure(
            peer: peer,
            payload: payload,
            messageId: messageId,
            transferId: transferId,
            piece: piece,
            signal: true);
        return s == 0
            ? const SendOutcome.refused(SendRefusal.notReady)
            : SendOutcome.accepted(s);
      case SendMode.speedOnly:
        // EPHEMERAL: without a route it is DISCARDED, not placed.
        //
        // The difference from [SendMode.speed] is exactly the fallback
        // below it. A typing indicator that goes via `m x R` placements and
        // arrives an hour later claims that someone is typing right now —
        // it is then not late but wrong. And it costs
        // the same as a text: in the field on 30.08. 18 control frames, at
        // a drain of one cell per 8 s.
        //
        // `prepareSpeed` is called nonetheless: the next indicator should
        // find a route. That costs no placement.
        if (!egress.hasRoute(peer)) {
          prepareSpeed(peer);
          return const SendOutcome.refused(SendRefusal.notReady);
        }
        if (readiness.state == Readiness.searching) {
          return const SendOutcome.refused(SendRefusal.notReady);
        }
        egress.send(peer, payload);
        return const SendOutcome.accepted(1);

      case SendMode.speed:
        // WITHOUT LIVENESS THERE IS NO SPEED PATH — and at
        // FIRST CONTACT that is the normal case, not a special case: `publishLiveness`
        // runs over `pairs.peers`, so before the first
        // contact no return path of the counterpart exists. A circle that Speed
        // cannot resolve.
        //
        // Until S349 this branch called `egress.send` blindly, and that THROWS
        // (`speed_egress.dart`: "keine Speed-Route"). The throw ran
        // uncaught up into `sendToUser` — the same class of
        // unhandled async error that killed the whole daemon in S348 as B-3.
        //
        // THE FALLBACK IS TO SECURE, not a rejection. That
        // makes nothing worse: Secure is the more anonymous and more robust
        // of the two paths (§8), it costs latency, not security. And
        // it is exactly what §15.2 provides for the first contact anyway
        // — the answer lies there on a tag line, not on
        // an onion. The user's wish "fast" is thus not
        // overridden but fulfilled as soon as it can be fulfilled.
        if (!egress.hasRoute(peer)) {
          // AND FETCH THE ROUTE FOR NEXT TIME (S354).
          //
          // §6/E-E fetches the liveness when the chat is opened — "not only on
          // first send". That is the regular path and remains so; here stands
          // the case in which there is no opening: a daemon without
          // UI (bootstrap, test node, background service) sends
          // without a chat ever having been opened. Without this line it would stay
          // permanently on the Secure path, although it constantly talks to
          // the same counterpart.
          //
          // THIS message does not get faster by it — the answer to
          // the request comes one slot later at the earliest. It goes out
          // via Secure, as it would anyway. The quota
          // (`kLivenessAttemptsPerEpoch`) limits what that costs.
          prepareSpeed(peer);
          final n = placeSecure(
              peer: peer,
              payload: payload,
              messageId: messageId,
              transferId: transferId,
              piece: piece);
          return n == 0
              ? const SendOutcome.refused(SendRefusal.notReady)
              : SendOutcome.accepted(n);
        }
        if (readiness.state == Readiness.searching) {
          return const SendOutcome.refused(SendRefusal.notReady);
        }
        // FOLLOW UP BEFORE SENDING (S355). `prepareSpeed`
        // limits itself: if the route stands and is younger than
        // [kSpeedRouteRefreshSeconds], it returns immediately. Otherwise
        // it asks for a younger record — for the NEXT
        // message. This one goes out via the existing route in any case;
        // it does not wait, and it does not get worse.
        //
        // The reason stands at `prepareSpeed`: a path block dies with
        // the session to r2, the failure is silent, and without this
        // line a node sends into a dead relay until the epoch change — 24 h.
        prepareSpeed(peer);
        // The Speed path enqueues at the egress; the slot plan draws the
        // partner (invariant 4), the sender does not choose it.
        egress.send(peer, payload);
        return const SendOutcome.accepted(1);
    }
  }

  /// The relays responsible for [target] — the up to R nearest that
  /// this node can also ADDRESS (§9.1).
  ///
  /// R IS `kResponsibleRelays` (20), not 1. The set is the only
  /// quantity on which placement and harvest side can agree without arrangement:
  /// both compute it from the same tag, each on its
  /// own table. If each side chooses only ONE node from it,
  /// two different tables must practically always choose differently — the
  /// field finding of 29.08. Over the whole set they necessarily overlap
  /// as soon as the tables share a node.
  ///
  /// LIMITED BY WHAT IS KNOWN, and twofold: by R and by the
  /// number of relays for which an entry record is available. Without
  /// its static X25519 part nothing can be sealed to the relay,
  /// and an unsealed tag would lie open to every hop — a
  /// node without a record is thus no reachable relay at all for this
  /// node, not merely an inconvenient one. With three known
  /// relays the set therefore means "all three".
  ///
  /// SORTED, nearest first — [isSelfResponsible] relies
  /// on the last entry being the farthest.
  ///
  /// AGAINST THE NETWORK, IF IT IS KNOWN (S356). The real
  /// responsibility set is the R nodes of the NETWORK, not the R
  /// nearest of the own table — §9.1 listed the difference until
  /// then as "Still an approximation". [networkResponsible] holds the
  /// result of the lookup per target; if something valid stands there, THAT
  /// is the candidate list.
  ///
  /// IF NOTHING STANDS THERE, the table still applies. That is no fallback
  /// out of convenience, but the promise to the send path: a lookup
  /// costs ~7 slots ~ 56 s (§7.2), and nobody waits for it here.
  /// Lookups happen on the tick (`_lookupTick`), sending happens immediately.
  /// [count] is the size of the set. Defaulted to
  /// [kResponsibleRelays]; the SIGNAL line passes in [kSignalRelays]
  /// (§17.2, S358) — the same metric, the same order, only cut off
  /// shorter. The reasoning for the smaller number stands at
  /// [kSignalRelays], not here: this function makes no
  /// policy decision, it executes one.
  List<EntryRecord> responsibleRelays(Uint8List target,
      {DateTime? now, int count = kResponsibleRelays}) {
    // ── THE ELIGIBILITY GATE (§9.1: "R ELIGIBLE relays", §10.3) ──────────
    //
    // Until S354 this set did NOT filter eligibility. `isEligible` was
    // built, `observe` wired — and nobody asked. Thus the
    // flash-Sybil gate that M6 prices was not present in the responsibility
    // computation: a freshly set-up fleet came into the
    // set immediately, instead of having to run in for ten epochs.
    //
    // THE COLD-START EXIT IS NORMATIVE, not my addition. §10.3 names
    // two conditions "without which the gate does harm rather than
    // good", and this is the second: "the gate must take effect only
    // once enough eligible positions are known (`eligibleCount >= R`);
    // below that threshold it waves everything through". Without it
    // the first node of a new network would find NO
    // responsible relay for ten days — a Sybil fix would have become
    // an availability outage.
    //
    // (The first condition — the age must survive a restart —
    // sits in `EligibilityRegistry.toJson`/`loadJson` and is saved by
    // `v41_attach.dart` next to the entry supply. Without it
    // every peer would be "fresh" after each start, and the same hole
    // would stand open, only less conspicuously.)
    final epoch = nodeEpochNow(now);
    final torActive = eligibility.eligibleCount(epoch) >= kResponsibleRelays;
    final currentSet = <EntryRecord>[];
    final candidates = networkResponsible.cached(target, now: now) ??
        table.closest(target, count: table.length);
    for (final k in candidates) {
      final r = entries.lookup(k.position);
      if (r == null) {
        // ── THE FILTER STAYS — BUT IT NO LONGER KEEPS SILENT (S376, P4-1)
        //
        // Without a record a position is NO relay: `buildPlace`
        // seals to `r.x25519Public`, and that stands exclusively
        // in the entry record. Taking this line out — as the
        // audit text at first suggested — would yield a set that
        // cannot be populated; the filter is structural, not
        // incidental.
        //
        // What was wrong is the SILENT dropping out: the lookup found
        // the R nearest of the NETWORK, here the set shrank, and
        // nobody fetched the missing record. §11.1 says "fetched on
        // demand". Exactly that happens now — remembered, and asked for
        // in a targeted way on the tick (`_entryFetchTick`).
        _miss(k.position);
        continue;
      }
      if (torActive && !eligibility.isEligible(k.position, epoch)) continue;
      currentSet.add(r);
      if (currentSet.length >= count) break;
    }
    return currentSet;
  }

  /// Does this node itself belong to those responsible for [target]?
  ///
  /// [currentSet] is the result of [responsibleRelays], i.e. sorted by distance.
  /// The own node stands in no routing table (§11.1) and
  /// must therefore be placed separately: it is included as long as the
  /// set is not yet full, or if it lies nearer than its farthest.
  ///
  /// [count] must be the same number with which [currentSet] was fetched —
  /// otherwise the node would count itself in on the SIGNAL line (5),
  /// although the set would already be full with 20, or vice versa.
  bool isSelfResponsible(Uint8List target, List<EntryRecord> currentSet,
          {int count = kResponsibleRelays}) =>
      currentSet.length < count ||
      compareDistance(target, keys.lNode, currentSet.last.lNode) < 0;

  // ══ THE LOOKUP (S356) ═══════════════════════════════════════════════
  //
  // Three parts, and none of them may be missing:
  //   * ANSWERING — [_nahesteKnown], called by `DeliveryNode` when
  //     a foreign lookup arrives here.
  //   * ASKING — [lookupQuery] as `LookupQuery`, plus [_found] as
  //     the return path of the answer.
  //   * TICKING — [lookupTick], once per [lookupEverySlots], never in the
  //     send path.

  /// How long to wait for the answer to a single lookup request.
  ///
  /// 60 s, and the number is calculated, not plucked from the air: the request itself waits
  /// one slot (`kSlotInterval` = 8 s, longer with a full queue),
  /// runs over up to three hops to the target and the same three back.
  /// If it expires, that is NO error — `iterativeLookup` expressly treats an
  /// empty answer as "did not answer" and does not abort
  /// on it. A node that is gone is the normal case.
  static const Duration kLookupTimeout = Duration(seconds: 60);

  /// Whether a lookup is running right now.
  ///
  /// ONE, NOT SEVERAL, and that is a budget question: a lookup occupies
  /// about seven slots. Two side by side would occupy fourteen, and the
  /// harvest — the only movement that FETCHES messages — would not get its
  /// turn during that time. The cache only merges lookups
  /// for the SAME target; this bolt covers the different ones.
  bool _lookupRuns = false;

  /// The positions this node knows near [searchPoint].
  ///
  /// The answering side. It does NOT check whether this node is responsible
  /// for the point — the same consideration as with placing: a
  /// rejection "not my area" would reveal where the own neighbourhood
  /// ends, and that is information about the own position that
  /// nobody needs.
  List<Uint8List> _nearestKnown(Uint8List searchPoint) => table
      .closest(searchPoint, count: kMaxFindNodePositions)
      .map((k) => k.position)
      .toList();

  /// A lookup answer to an OWN request has arrived.
  void _found(Uint8List requestId, List<Uint8List> positions) {
    final key = base64.encode(requestId);
    final waiting = _lookupRequest.remove(key);
    if (waiting == null || waiting.isCompleted) return;
    waiting.complete(<KnownNode>[
      for (final p in positions)
        if (p.length == kNodePositionBytes && !_sameBytes(p, keys.lNode))
          KnownNode(p)
    ]);
  }

  /// Asks ONE node for the nearest ones known to it — the
  /// `LookupQuery` from `lookup.dart`.
  ///
  /// Whoever has no entry record is not addressable: without the
  /// static X25519 part the search point cannot be sealed to him,
  /// and unsealed it would lie open to every hop. Such a
  /// node counts as "did not answer".
  /// Chooses the CHAIN of blind relays for a lookup onion (E-L).
  ///
  /// ── THE SELECTION IS THE PROPERTY, NOT THE SHELL ──────────────
  ///
  /// A blind relay that lies NEAR the search point reveals the search point
  /// just as the target relay did before S376 — the shell would then be
  /// decoration. That is why the draw is **uniform from the table**
  /// and not by distance: the value the first hop sees is thus
  /// stochastically independent of `H(T ‖ e)`. Exactly that is measured by
  /// `smoke_v41_lookup_onion.dart`.
  ///
  /// Three exclusions, each with a reason:
  ///
  ///   * **the target relay itself** — otherwise the onion would be a
  ///     wrapping around the same receiver and the gain zero;
  ///   * **the own partners** — the slot plan draws the first hop
  ///     (invariant 4, §5.1), and if it hit the same node that is also
  ///     a blind relay, that one would open the shell immediately and see
  ///     sender AND the next link;
  ///   * **whoever has no entry record** — without the static
  ///     X25519 part nothing can be sealed to him.
  ///
  /// ── A FOURTH EXCLUSION, SINCE S377: ITSELF ─────────────────
  ///
  /// [count] links are drawn **without replacement**, so they are
  /// pairwise different. The same node twice in the chain would be
  /// a silent fallback to one shell: this node would see both
  /// ends, and the arrangement would again need two accomplices instead of
  /// [kLookupOnionShells] `+ 1`. The receiver rejects the same case
  /// once more (`DeliveryNode`, "Suchzwiebel zeigt auf denselben
  /// Knoten"), because a stranger may build it.
  ///
  /// `null` means: this node knows fewer than [count] relays
  /// outside its own sessions. Then NO lookup happens (see
  /// [lookupQuery]) — the cold start gets stricter with every shell, and
  /// that stands at [kLookupOnionShells] as point (c) 3.
  List<EntryRecord>? _blindRelayChain(KnownNode target, int count) {
    final own = <String>{
      for (final ch in _channels)
        if (ch.peerPosition != null) _posKey(ch.peerPosition!)
    };
    final candidates = <EntryRecord>[];
    for (final k in table.closest(keys.lNode, count: table.length)) {
      if (_sameBytes(k.position, target.position)) continue;
      if (_sameBytes(k.position, keys.lNode)) continue;
      if (own.contains(_posKey(k.position))) continue;
      final r = entries.lookup(k.position);
      if (r != null) candidates.add(r);
    }
    if (candidates.length < count) return null;
    // UNIFORM AND WITHOUT REPLACEMENT, and the randomness comes from
    // libsodium — not from `Random()`. A predictable stream would make
    // the blind-relay sequence of a node recomputable; that is
    // the same finding that hit the slot plan in S376
    // (`CoverStream.seed`).
    final sodium = SodiumFFI();
    final chain = <EntryRecord>[];
    for (var i = 0; i < count; i++) {
      final w = sodium.randomBytes(4);
      final n = ((w[0] << 24) | (w[1] << 16) | (w[2] << 8) | w[3]) & 0x7fffffff;
      chain.add(candidates.removeAt(n % candidates.length));
    }
    return chain;
  }

  static String _posKey(Uint8List p) =>
      p.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Asks ONE node for the nearest ones known to it — the
  /// `LookupQuery` from `lookup.dart`.
  ///
  /// Whoever has no entry record is not addressable: without the
  /// static X25519 part the search point cannot be sealed to him,
  /// and unsealed it would lie open to every hop. Such a
  /// node counts as "did not answer".
  ///
  /// ── SINCE S376 THE REQUEST GOES VIA AN ONION (E-L) ────────────
  ///
  /// Until then the `findNode` frame went out unwrapped. What the
  /// first hop saw with it is measured (S376 report, section 1.4):
  /// the sender with certainty (`hops == kMaxPlaceHops` only exists
  /// at the producer) and a target relay that on average shares 6.7 leading bits
  /// with the search point. §9.1 lists exactly this linkage as
  /// closed — it was not.
  ///
  /// Now the frame lies in [kLookupOnionShells] shells, each for
  /// a different, randomly chosen BLIND RELAY. One identifier per leg
  /// — so `kLookupOnionShells + 1`; why is stated at
  /// [SecureOp.findNodeOnion]. The egress stays ONE cell per request,
  /// independent of the depth.
  ///
  /// NO FALLBACK TO THE OPEN REQUEST. If no blind relay is
  /// available, the request is omitted and counted. A
  /// fallback would be a silent mode change from "covert" to
  /// "open" — the same class that the working rule
  /// `kein_stiller_moduswechsel` forbids for delivery.
  /// (Was called `_fragen` until S376. Public, because the guard
  /// `smoke_v41_lookup_zwiebel.dart` measures the STATEMENT — "what leaves
  /// this node" — and not a proxy for it. A test
  /// against a replicated send site would stay green if exactly
  /// this line enqueued `buildFindNode` again.)
  Future<List<KnownNode>> lookupQuery(KnownNode peer, Uint8List target) {
    final r = entries.lookup(peer.position);
    if (r == null) return Future.value(const <KnownNode>[]);
    final chain = _blindRelayChain(peer, kLookupOnionShells);
    if (chain == null) {
      lookupsWithoutBlindRelay++;
      return Future.value(const <KnownNode>[]);
    }
    final sodium = SodiumFFI();
    // ONE IDENTIFIER PER LEG, so `kLookupOnionShells + 1`. `ids[0]` is
    // the outermost: it stands in the plaintext of the frame that goes out
    // here, and is the only one under which the answer arrives at this
    // node. Each further one lies one shell deeper.
    //
    // ALL DRAWN INDEPENDENTLY. Two adjacent legs with the same
    // identifier are rejected by the blind relay in between; the pairing
    // of NON-adjacent legs is seen by no node and is structurally
    // not checkable at the receiver — it is guaranteed here. Why that
    // counts at all is stated at `PendingRequests.remember`: the same
    // identifier via another neighbour overwrites the return path.
    final ids = [
      for (var i = 0; i <= kLookupOnionShells; i++)
        sodium.randomBytes(kRequestIdBytes)
    ];
    final outsideId = ids.first;
    final key = base64.encode(outsideId);
    final c = Completer<List<KnownNode>>();
    _lookupRequest[key] = c;
    _ownRequests.add(key);
    while (_lookupRequest.length > kOwnRequestMemory) {
      _lookupRequest.remove(_lookupRequest.keys.first);
    }
    while (_ownRequests.length > kOwnRequestMemory) {
      _ownRequests.remove(_ownRequests.first);
    }
    // BUILT FROM THE INSIDE OUT. The innermost frame is the
    // lookup request to the target relay with the last identifier; over it
    // each round lays a shell for one link of the chain, the
    // OUTERMOST last. `kette[0]` is thus the blind relay that
    // is reached first.
    var frame =
        buildFindNode(r.lNode, r.x25519Public, ids[kLookupOnionShells], target);
    for (var shell = kLookupOnionShells - 1; shell >= 0; shell--) {
      frame = buildFindNodeOnion(
        blindRelay: chain[shell].lNode,
        blindRelayX25519Public: chain[shell].x25519Public,
        outerRequestId: ids[shell],
        innerFrame: frame,
      );
    }
    // SACRIFICEABLE. A lookup is precaution, not delivery: if the
    // queue is full, it drops off the back instead of displacing a placement or a
    // harvest.
    //
    // ONE CELL, INDEPENDENT OF THE DEPTH: ONE `enqueueControl`, and
    // the frame measures `kFindNodeOnionBytes` (362 B) of 1169 B. §9.1
    // says "no additional egress cells", and THIS is the place where
    // it stands — if the number of enqueuings grows here, the build is
    // wrong. `smoke_v41_lookup_zwiebel.dart` measures exactly that on a
    // running node: after the take-out the queue must be empty.
    egress.stream.enqueueControl(frame, sacrificable: true);
    lookupsOnionWrapped++;
    return c.future.timeout(kLookupTimeout, onTimeout: () {
      _lookupRequest.remove(key);
      return const <KnownNode>[];
    });
  }

  /// The next target for which no valid network set is available.
  ///
  /// Per counterpart there are seven: three Secure families in the sending direction
  /// (placement happens there), three in the opposite direction (harvesting happens there) and
  /// the liveness tag. Round-robin over all, so that the first
  /// counterpart does not use up all lookups — the same consideration as with
  /// `_ernteZeiger`.
  Uint8List? _nextUncoveredTarget(DateTime current) {
    final targets = <Uint8List>[];
    for (final peer in pairs.peers) {
      final kAb = pairs.kAbFor(peer);
      if (kAb == null) continue;
      final epoch = secureEpoch(kAb, current);
      final out = pairs.outDirectionFor(peer);
      for (var f = 0; f < kDeliveryFamilies; f++) {
        targets.add(targetFor(secureTag(kAb, epoch, f, out), epoch));
      }
      // ── THE INBOUND SIDE ONLY WHERE THERE IS ONE ────────────────────
      //
      // A pure placement line is not harvested and publishes
      // no liveness (see `publishLiveness`). Searching its inbound and
      // liveness targets here would mean spending lookups on tags
      // that this node never queries — and the lookup is
      // capped and round-robin, every wasted lookup is missing for a real one.
      if (pairs.isPlaceOnly(peer)) continue;
      final incoming = pairs.inDirectionFor(peer);
      for (var f = 0; f < kDeliveryFamilies; f++) {
        targets.add(targetFor(secureTag(kAb, epoch, f, incoming), epoch));
      }
      targets.add(livenessTarget(kAb, epoch, incoming));
    }
    if (targets.isEmpty) return null;
    final from = _lookupPointer % targets.length;
    for (var i = 0; i < targets.length; i++) {
      final z = targets[(from + i) % targets.length];
      if (networkResponsible.cached(z, now: current) == null) {
        _lookupPointer = from + i + 1;
        return z;
      }
    }
    return null;
  }

  /// One lookup run: look up a target, then pull in its records.
  ///
  /// NEVER IN THE SEND PATH. This is called from `run()`, every
  /// [lookupEverySlots] slots; `send` sees nothing of it and only reads
  /// what was stored here.
  Future<void> lookupTick({DateTime? now}) async {
    if (_lookupRuns || _stopped) return;
    final current = (now ?? DateTime.now()).toUtc();
    networkResponsible.expire(now: current);
    final target = _nextUncoveredTarget(current);
    if (target == null) return;

    _lookupRuns = true;
    lookupRuns++;
    try {
      final before = networkResponsible.queriesSpent;
      final found = await networkResponsible.ensure(
        target: target,
        table: table,
        query: lookupQuery,
        now: current,
      );
      // WITHOUT A RECORD A FIND IS NO RELAY. `responsibleRelays`
      // throws out every position without an entry record — a perfectly
      // looked-up result would otherwise be completely unusable. Four
      // positions per frame (`kMaxEntryRequestPositions`), the rest in the
      // next run.
      final missing = found
          .map((k) => k.position)
          .where((p) => !entries.has(p) && !_sameBytes(p, keys.lNode))
          .toList();
      final requested = requestEntries(missing);
      log('Lookup ${_posLabel(target)}: ${found.length} responsible '
          'from the network, ${networkResponsible.queriesSpent - before} requests, '
          '$requested/${missing.length} records requested');
    } finally {
      _lookupRuns = false;
    }
  }
  /// Places a message for [peer] in Secure mode (WP-4).
  ///
  /// Over all m families, so that a censorship would have to hit all three
  /// (D1). Per family at the responsible relay that this node knows as
  /// nearest — the cell finds its way on from there itself (§11.2).
  ///
  /// WHAT DOES NOT HAPPEN HERE YET: the cell is not sealed end-to-end.
  /// That is the business of the layer above (per-message KEM); here
  /// goes in what is passed in. The sealing TO THE RELAY
  /// on the other hand very much happens — otherwise the tag would lie open en route.
  ///
  /// Returns how many families could be placed.
  /// [signal] places on the SIGNAL line instead of on the
  /// message line (§17.2, owner decision 2026-08-31): a tag of its own
  /// ([signalTag]), a smaller responsibility set ([kSignalRelays]) and
  /// short retention ([kRetentionSignal]). Meant for the
  /// call signalling — the path that `sendeModus` today recognises by `skipL3`.
  ///
  /// ── THE SEAM IS BUILT — S360, 01.09.2026 ───────────────────────
  ///
  /// Here stood: "This parameter has NO caller in `lib/` today",
  /// followed by three steps that would have to be built. The sentence was right —
  /// the signal line was built, measured (`smoke_v41_signal_line.dart`)
  /// and not trodden, the same situation as with the receiving side before
  /// S349. It stays as a correction instead of disappearing.
  ///
  /// Exactly these three steps were built:
  ///
  ///   1. `delivery_api.dart`: the fourth value `SendMode.signal`.
  ///      `sendeModus` returns it where until then it returned
  ///      `SendMode.secure` on `skipL3`.
  ///   2. `v41_node.dart` (here): `case SendMode.signal` in `send` calls
  ///      `placeSecure(..., signal: true)`.
  ///   3. Passing `skipL3` through was NOT necessary: `sendeModus`
  ///      already gets it (`cleona_service.dart`), and the chosen
  ///      mode travels up to here anyway. The third step of the old
  ///      list was a false assumption.
  ///
  /// What an INVITE costs with this: `m x kSignalRelays = 15` placements
  /// = 120 s egress, exactly the TTL of the class. Before it was `m x R`
  /// = 60 = 480 s against the same TTL.
  ///
  /// The guard for this is `smoke_v41_signal_line.dart` — since
  /// S360 it measures not only THAT the line works, but also that
  /// it is TRODDEN.
  int placeSecure({
    required String peer,
    required Uint8List payload,
    DateTime? now,
    Uint8List? messageId,
    int transferId = 0,
    int piece = 0,
    bool signal = false,
    // ── THE MANAGEMENT CLASS (S361, kRetentionManagement producer) ────
    //
    // So far this place only chose between `kRetentionSignal` and
    // `kRetentionNormal` — `kRetentionManagement` (31 d, built since S360,
    // `secure_frames.dart:241`/`secure_mode.dart:394`) had NO
    // setting site in `lib/` (measured,
    // `docs/v4-redesign/S361-aufbewahrung-entwurf.md` section 1.3/4).
    //
    // ONE message type that this tree really sends today is assigned
    // BY NAME to the 31-day class in the v4_1 document: the
    // EMERGENCY rotation (§4.5.4, document line 1007-1008 — "Distribution:
    // as a delivery of the 31-day TTL class, pairwise to contacts, via
    // twin sync to one's own devices"). It sets this parameter in
    // `CleonaService.rotateIdentityKeys`.
    //
    // THE SECOND named type — twin type 16 `DEVICE_SET_CHANGED`,
    // the key packet per device (§14.4 l. 3624, §14.7 l. 3862/3887)
    // — has NO producer on this branch: `proto/app_payloads.proto`
    // lists 14/15/16 as `reserved`, and `rotateIdentityKeys` aborts fail-closed on
    // `_devices.length > 1`, because the device-bound
    // line from §14.1 is not built. It gets its setting site when
    // it is sent — not before.
    //
    // WHAT EXPRESSLY DOES NOT BELONG HERE, so that nobody adds it out of
    // similarity: the ROUTINE KEM rotation (§4.5.4: "the
    // rotation is announced pairwise as an ORDINARY delivery") and the
    // pairwise device-set announcement to contacts (§14.5 path 2:
    // "Changes go out to contacts as an ORDINARY delivery"). Both even share
    // the wire type with the emergency rotation
    // (`MTV3_KEY_ROTATION_BROADCAST`) — exactly for that reason the class is a
    // parameter of the SEND SITE and not derivable from the message type.
    //
    // It is deliberately orthogonal to [signal]: a management
    // delivery does not change the relay path (still
    // `kResponsibleRelays`, not `kSignalRelays`), only the
    // retention period. Setting both at the same time makes no
    // sense and is not caught — no caller today does that.
    bool management = false,
  }) {
    final kAb = pairs.kAbFor(peer);
    if (kAb == null) return 0;
    if (payload.length > kMaxPlaceContentBytes) {
      throw ArgumentError('Payload ${payload.length} B, the limit is '
          '$kMaxPlaceContentBytes');
    }
    final current = now ?? DateTime.now().toUtc();
    // ── ONE EPOCH, AND THAT THE CURRENT ONE (re-measured S361) ────────
    //
    // Since S361 the harvest reaches back three epochs (§22.4.1, see
    // `ernteEpochenPlan`). THE PLACEMENT EXPRESSLY DOES NOT, and
    // that is checked against the document, not assumed: §1 describes the
    // Secure path as "planted to the R≈20 responsible relays under a tag
    // `HKDF(K_AB, "secure", epoch, salt)`" — ONE epoch —, and the
    // module line in §22.4.1 separates the two sides in one sentence:
    // "Inbox tag line … (**rotating per epoch**, §9); **epoch
    // subscription: current + 2 previous**". The line rotates; whoever
    // writes, writes to the current one, and whoever reads subscribes to
    // three.
    //
    // If it were otherwise, it would be expensive and wrong at the same time: a placement
    // costs `m x R` frames (§9.2, in the field 6 to 30), placing three times
    // would triple that — and the copies in the previous epochs would lie on
    // relays that the receiver no longer has to ask in exactly this epoch,
    // because he already has the fresh copy.
    final epoch = secureEpoch(kAb, current);
    var laid = 0;
    final direction = pairs.outDirectionFor(peer);
    // DIAGNOSIS, and it is necessary. Whether two sides find each other depends on
    // THREE quantities that both compute independently: `K_AB`, the epoch and
    // the direction. If one deviates, the one places under a tag
    // that the other never queries — and both sides only see "geerntet:
    // 0". On 28.08. 224 harvests without a single hit stood in the log
    // of the bootstrap, without it being possible to say which of the three
    // diverged. The fingerprint is a HASH prefix, not
    // key material; it makes the comparison between two devices
    // possible without revealing anything.
    final klass = signal
        ? kRetentionSignal
        : (management ? kRetentionManagement : kRetentionNormal);
    final rSize = signal ? kSignalRelays : kResponsibleRelays;
    log('${signal ? 'Signal' : (management ? 'Management' : 'Secure')} deposit '
        'to ${_peerLabel(peer)}: '
        'K_AB ${_fingerprint(kAb)}, epoch $epoch, direction $direction, '
        'R $rSize');

    // ── FIRST THE SETS, THEN THE ENQUEUING ──────────────────────────
    //
    // The separation is the prerequisite for the round-robin order
    // below: as long as tag, target and set were computed INSIDE the family loop,
    // the loop could not do otherwise than run
    // family-outermost.
    final tags = <Uint8List>[];
    final targets = <Uint8List>[];
    final sets = <List<EntryRecord>>[];
    for (var f = 0; f < kDeliveryFamilies; f++) {
      final tag = signal
          ? signalTag(kAb, epoch, f, direction)
          : secureTag(kAb, epoch, f, direction);
      final target = targetFor(tag, epoch);

      // ── THE WHOLE RESPONSIBILITY SET, NOT THE FIRST HIT ─────
      //
      // Until S353 here stood a `break` after the first relay: effectively
      // R = 1. §9.2 requires `m x R` placements per message, and that is
      // no redundancy extra, but the prerequisite of the M6 model
      // — `P1 = 1 - exp(-R*f)` presupposes the cell on the WHOLE
      // responsibility set. With one placement per family the
      // hit probability of a 25% fleet against one family falls
      // from 0.993 to 0.25, and m = 3 would no longer be a lever.
      //
      // BUT IT IS FATAL FOR A SECOND REASON, and that was measured on
      // 29.08.: placement and harvest side convert the same tag
      // onto their respective OWN routing table. With R = 1 each side chooses
      // exactly ONE node, and two nodes with different tables
      // practically never make the same choice:
      //
      //   `Bob legt ab:  Familie 0 -> Relais 49527e5b (Ziel 8a565454)`
      //   `Handy fragt:  Familie 0 -> frage  819c4d49 (Ziel 8a565454)`
      //
      // Same target, same `K_AB`, same epoch, same direction
      // — different nodes. Network-wide not a single harvest hit.
      // Over the full set both sides necessarily overlap
      // as soon as their tables share even ONE node.
      //
      // WHAT IT COSTS, in cells (§9.2): `m x R` = 3 x 20 = 60 placements per
      // Secure message at full network size. At `R_cover = 1/8 s`
      // that is 60 slots = 480 s = 8 minutes of egress and ~70 KiB, i.e.
      // 60 times a Speed message — exactly the number that §9.2
      // budgets. In the three-node lab it is 3 x 3 = 9 cells (72 s),
      // because the set is limited by the number of KNOWN relays.
      // Whoever takes the 9 for the field number underestimates the sender by
      // a factor of 6.7.
      tags.add(tag);
      targets.add(target);
      sets.add(responsibleRelays(target, count: rSize));
    }

    // ── WHICH TAGS EXACTLY (S382, measurement) ──────────────────────────
    //
    // The harvest path has always logged its tags ("Marken
    // N0,N1,N2,… -> frage X", and the answer lists them verbatim).
    // The PLACEMENT path does not. On 12.09.2026 exactly this
    // asymmetry blocked a narrowing down: Alice's placement was acknowledged by
    // the same relays that Bob asks, same `K_AB`,
    // same epoch, same direction — and Bob got no hit network-wide.
    // Whether both sides mean the same tag could NOT be decided from the logs,
    // because only one of the two names its.
    //
    // The same short form as on the harvest path (four bytes), so that
    // the two lists can be compared without conversion.
    // ONLY `tagLabel`, NO `_fingerprint` (S382, after two crashes):
    // `_fingerprint` is SHA-256 via FFI. In this line it stood
    // additionally per tag — i.e. three to six native calls per placement
    // AND per harvest instead of one. After that both test nodes died with
    // `Segmentation fault` (Node1 22:39, Node2 22:51), while the
    // builds before ran through for hours. Cause NOT proven, but
    // the connection is too close to leave it standing overnight —
    // and `tagLabel` suffices for the comparison.
    //
    // TWO SHORT FORMS, AND THAT IS NO LUXURY (S382): `_fingerprint` is
    // SHA-256(tag)[0..4), `tagLabel` (delivery_node.dart) are the
    // FIRST FOUR BYTES of the tag itself. Two different abbreviations
    // of the same quantity — whoever compares sender and relay log otherwise compares
    // apples with oranges and concludes from it that the tag never
    // arrived. Exactly that happened on 12.09.2026 and delayed a
    // narrowing down by one round.
    log('Placement marks ${_peerLabel(peer)}: epoch $epoch, direction $direction '
        '-> ${tags.map(tagLabel).join(" ")} '
        '(targets ${targets.map(tagLabel).join(" ")})');

    // ── ROUND-ROBIN OVER THE FAMILIES, NOT FAMILY-OUTERMOST (S358) ──────
    //
    // Here stood `for (Familie) { for (Relais) { … } }`, and that was
    // not merely an order but a delivery question. The
    // frames all go into ONE FIFO (`enqueueControl`), from which the
    // slot tick draws exactly one per `kSlotInterval` = 8 s. With
    // `m x R` = 3 x 20 = 60 placements, families 1 and 2 thus lie
    // completely BEHIND the twenty frames of family 0:
    //
    //   Family 0:  frames  1..20  ->    8 s .. 160 s
    //   Family 1:  frames 21..40  ->  168 s .. 320 s
    //   Family 2:  frames 41..60  ->  328 s .. 480 s
    //
    // For call signalling with its 120 s (§17.2) that means:
    // within the deadline **only family 0** goes out, the
    // m = 3 redundancy against censorship (D1) is not present at all in this time.
    // And for a text too it is the wrong order:
    // if the node fails after two minutes, one family lies
    // twentyfold and two do not lie at all — instead of each family
    // six- to sevenfold.
    //
    // Round-robin, after the k-th pass each family lies k-fold. With
    // `R_signal` = 5 there are only 15 frames anyway and the order
    // changes nothing about the result — but it should not DEPEND on
    // the time sufficing.
    // ── AND THE SIGNAL LINE JUMPS THE QUEUE (S358) ─────────────────
    //
    // WITHOUT THIS THE WHOLE CALCULATION FROM `kSignalRelays` IS WRONG. It
    // says: 15 placements at `kSlotInterval` = 8 s are 120 s, i.e. exactly
    // `kInteractiveDeliveryTtl`. But that only holds if the
    // control queue is EMPTY. It typically is not: a
    // single preceding text message enqueues `m x R` = 60 frames
    // (§9.2), and behind them the INVITE only leaves after `(60 + 15) x 8` =
    // **600 s** — five times its own deadline. The caller would have
    // long hung up (`CallManager.reachingTimeoutSec` = 120 s), and
    // the cells would lie there for a call that no longer exists.
    //
    // `enqueueFramesFirst` is there for that and is already used so
    // (`prepareSpeed`, S354/S355). The reasoning from there applies here
    // unchanged: "what it overtakes is the redundancy of a
    // message that is already in transit — being placed one slot later costs it
    // nothing that would be measurable." Nothing changes to the outside:
    // the slot tick still hands out exactly one byte-identical
    // cell per slot, only their order is swapped
    // (invariant 1 speaks about the RHYTHM).
    //
    // THE QUOTA that the caller must keep himself (there is
    // no cap there): `kFamilies x kSignalRelays` = 15 frames per
    // signalling. A signalling arises through a
    // user action — a call —, not through a tick; it is
    // thus just as rare as the session setup, for which the same
    // right of way already applies.
    final priority = <({int type, Uint8List body})>[];
    final longest =
        sets.fold<int>(0, (a, m) => m.length > a ? m.length : a);
    for (var i = 0; i < longest; i++) {
      for (var f = 0; f < kDeliveryFamilies; f++) {
        if (i >= sets[f].length) continue;
        final r = sets[f][i];
        final built = buildPlace(
            r.lNode, r.x25519Public, tags[f], payload,
            retention: klass);
        _rememberOwnDeposit(built.frame, built.ackKey, r.lNode, f, current,
            messageId: messageId, transferId: transferId, piece: piece);
        if (signal) {
          priority.add((type: LinkFrameType.control, body: built.frame));
        } else {
          egress.stream.enqueueControl(built.frame);
        }
        // WHERE — and that is not cosmetics. Placement and harvest side
        // convert the same tag onto their respective OWN routing table; whether
        // they come out at the same node is the whole question
        // (S351: 224 harvests, all `geerntet: 0`). Without the chosen target
        // in the log this cannot be decided in the field — one only sees
        // both sides keep silent.
        log('  Family $f -> relay ${_posLabel(r.lNode)} '
            '(target ${_posLabel(targets[f])}, table ${table.length})');
      }
    }
    // AS ONE GROUP, in the round-robin order built above.
    // Calling `enqueueControlFirst` individually would reverse it — every new
    // frame would land before the previous one, and 0,1,2,0,1,2 would become
    // 2,1,0,2,1,0. `enqueueFramesFirst` inserts the list at the front in its
    // order.
    if (priority.isNotEmpty) egress.stream.enqueueFramesFirst(priority);

    for (var f = 0; f < kDeliveryFamilies; f++) {
      final tag = tags[f];
      final target = targets[f];
      final responsible = sets[f];
      var placed = responsible.isNotEmpty;

      // ── WHOEVER IS HIMSELF THE RESPONSIBLE ONE PLACES WITH HIMSELF (B-34) ─────
      //
      // §9.1 defines the responsible ones purely metrically: the R relays whose
      // `L_node` lies nearest to `H(T ‖ e)`. This set knows no
      // exception for the sender. The routing table of this node
      // on the other hand NEVER contains it (§11.1, `EntryCache.remember` rejects the
      // own record, `_learnEntry` likewise) — right for a
      // table from which one FORWARDS, wrong for one from which one
      // computes RESPONSIBILITY.
      //
      // Measured in the field on 29.08. (four nodes):
      //   A: "Familie 2 -> Relais 49527e5b (Ziel 2dc0026a)"
      //   B: "Familie 2 -> frage  7c3c24b4 (Ziel 2dc0026a)"   <- that is A
      //
      // The counterpart on the receiver side has long existed: the
      // harvest run FIRST looks into the own store. Here the same
      // matter of course was missing on the placement side.
      //
      // COSTS NO CELL. The node holds the payload in hand
      // anyway; nothing additional goes out.
      //
      // AND IT DOES NOT HARVEST IT BACK ITSELF: placement happens under the
      // OUTGOING direction, harvesting under the opposite direction (B-22).
      if (isSelfResponsible(target, responsible, count: rSize)) {
        if (delivery.store.place(tag, payload, nodeEpochNow(current),
            retention: klass, bucket: retentionBucket(current))) {
          log('  Family $f -> deposited at myself '
              '(among the $rSize nearest to the target '
              '${_posLabel(target)})');
          placed = true;
        }
      }

      // FAMILIES ARE COUNTED, NOT CELLS. The return value goes up as
      // `SendOutcome.accepted(n)` and means there "this many
      // legs lie"; if it now counted the m x R cells, three
      // legs would suddenly become sixty, and every display above would lie.
      if (placed) laid++;
    }
    return laid;
  }

  // ═══════════════════════════════════════════════════════════════════
  // THE TAG-BASED PLACEMENT WITHOUT PAIR REFERENCE (S-2)
  // ═══════════════════════════════════════════════════════════════════
  //
  // ── WHICH GAP THIS CLOSES, MEASURED ─────────────────────────
  //
  // `placeSecure` begins with `pairs.kAbFor(peer)` and returns 0 without a
  // pair key; the harvest run forms its tags
  // exclusively in a loop over `pairs.harvestPeers`. Both
  // are right for pair traffic and useless for §13.3: the
  // bundle line `tag_R(i, e, j)` follows from the SEED alone
  // (`recovery_keys.dart`), it has no counterpart and cannot have one
  // — that is its purpose (§13.1.3: "The recovering user possesses
  // exclusively **self-referential** key material").
  //
  // The PRIMITIVE below was already tag-based: `buildPlace` has always
  // taken an arbitrary 32 B tag (`secure_frames.dart`). What
  // was missing was the entrance and exit above it. Exactly that stands
  // here, and WITHOUT any knowledge of the recovery: this
  // layer knows no contact list and no seeds and should know
  // none. Whoever looks for the bundle line finds it in
  // `lib/core/tagline/recovery_line.dart`.
  //
  // ── WHY NO PSEUDO COUNTERPART AS WITH INVITATION AND OWN LINE ──
  //
  // `invite_line.dart` and `own_line.dart` are carried by the tree as
  // PSEUDO COUNTERPARTS in the `PairRegistry` — with good reason: their
  // tags have the same form as `secureTag(K_AB, epoch, family,
  // direction)`, i.e. epoch, family and direction. The bundle tag does
  // NOT have that: §13.3.1 writes `HKDF(recovery_key(i), "recovery" ‖
  // epoch_e ‖ j)` with a BLOCK INDEX instead of a direction, its epoch
  // is the 14-day epoch of the recovery and not the
  // node epoch, and it has no opposite direction under which harvesting
  // would happen. Forcing it into a pair would mean inventing three quantities
  // that do not exist.

  /// Places [cell] under [tag] at exactly ONE relay.
  ///
  /// The caller chooses the relay himself — he gets the set via
  /// [responsibleRelays] and decides how fast he works through it.
  /// **That is the place where the pacing sits, and it sits there
  /// deliberately:** a renewal of the rescue bundle is thousands of
  /// placements (§13.3.2), and the control queue holds
  /// `kMaxControlBacklog` = 120 frames. Whoever enqueues them all at once
  /// silently loses the large remainder — `CoverStream._pushControl` throws away
  /// the oldest whole group on overflow. A loop here
  /// would therefore not be a convenience but a defect.
  ///
  /// Returns `true` if a frame was enqueued.
  bool placeUnderTag({
    required EntryRecord relay,
    required Uint8List tag,
    required Uint8List cell,
    required int retention,
    int family = 0,
    DateTime? now,
  }) {
    if (cell.length > kMaxPlaceContentBytes) {
      throw ArgumentError('Cell ${cell.length} B, what fits is '
          '$kMaxPlaceContentBytes');
    }
    final current = now ?? DateTime.now().toUtc();
    final built = buildPlace(relay.lNode, relay.x25519Public, tag, cell,
        retention: retention);
    // WITHOUT `messageId`, and that is measured and intended: the receipt
    // runs via `_placementAcked` into the delivery bookkeeping of the
    // application, and that looks it up under a message identifier
    // (`cleona_service_msgstate.dart`, `noteV41Placement`). A
    // bundle cell IS no message; it would invent a
    // delivery record there that nobody displays. The throw on the other hand is
    // excluded: the reporting site checks `mid != null`.
    _rememberOwnDeposit(built.frame, built.ackKey, relay.lNode, family, current);
    egress.stream.enqueueControl(built.frame);
    tagPlacements++;
    return true;
  }

  /// Places [cell] under [tag] in the OWN store.
  ///
  /// THE SELF-RESPONSIBILITY (B-34): the routing table of this node
  /// never contains it, the responsibility set from §9.1 on the other hand knows
  /// no exception for the sender. Without this step a
  /// cell for which this node itself is the nearest relay would lie
  /// nowhere. Costs no cell on the wire.
  bool storeUnderTag({
    required Uint8List tag,
    required Uint8List cell,
    required int retention,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now().toUtc();
    return delivery.store.place(tag, cell, nodeEpochNow(current),
        retention: retention, bucket: retentionBucket(current));
  }

  /// How many placements went out via [placeUnderTag].
  int tagPlacements = 0;

  /// How many harvest requests went out via [harvestUnderTags].
  int tagHarvestRequests = 0;

  /// Requests of a tag-based harvest and where their answer goes.
  ///
  /// Separate from `_anfragePeer` and `_livenessAnfrage` for the same
  /// reason for which those two are separate: an answer to THIS
  /// question is no piece of a pair transmission. If it ran into
  /// `_geerntetVon`, it would occupy a place in the reassembler there and
  /// wait for continuations that never come (the same error as with
  /// the liveness answer before S354).
  final Map<String, void Function(Uint8List cell)> _marksRequest =
      <String, void Function(Uint8List cell)>{};

  /// Queries an arbitrary tag line at its responsible relays.
  ///
  /// [tags] and [epochs] are of equal length; the epoch belongs PER TAG,
  /// because the target includes it in the computation (`targetFor(tag, epoche)`, §9.1
  /// `H(T ‖ e)`). Addressing a tag of the previous epoch against the current epoch
  /// would ask the wrong relays — the same class of error as
  /// R = 1 (S352), only one axis further.
  ///
  /// [sink] gets every cell that came back on one of these requests.
  /// It is NOT "the sought cell": under a tag there can lie
  /// what someone else has placed there, and the decoys bring
  /// foreign material along anyway. Sorting belongs to the caller.
  ///
  /// Returns how many requests were enqueued (at most
  /// [maxRequests]).
  int harvestUnderTags({
    required List<Uint8List> tags,
    required List<int> epochs,
    required void Function(Uint8List cell) sink,
    int relaysPerTag = kResponsibleRelays,
    int offset = 0,
    int maxRequests = 1,
    int decoys = kDecoyCount,
  }) {
    if (tags.length != epochs.length) {
      throw ArgumentError('${tags.length} marks, ${epochs.length} epochs');
    }
    if (tags.isEmpty || maxRequests <= 0) return 0;
    if (partnerCount == 0) return 0;

    final targets = <Uint8List>[
      for (var i = 0; i < tags.length; i++) targetFor(tags[i], epochs[i])
    ];
    final sets = <List<EntryRecord>>[
      for (final z in targets) responsibleRelays(z, count: relaysPerTag)
    ];

    // THE CANDIDATE LIST, DEDUPLICATED — as in the pair harvest run. The same
    // relay usually stands in several of these sets, because
    // `responsibleRelays` computes a target of its own per tag, but draws from
    // THE SAME routing table. Listing a relay twice
    // would mean asking it twice.
    final candidates = <EntryRecord>[];
    final candidateIndex = <String, int>{};
    final relayForMark = <List<int>>[];
    for (final m in sets) {
      final idx = <int>[];
      for (final r in m) {
        final k = base64.encode(r.lNode);
        final present = candidateIndex[k];
        if (present != null) {
          idx.add(present);
        } else {
          candidateIndex[k] = candidates.length;
          idx.add(candidates.length);
          candidates.add(r);
        }
      }
      relayForMark.add(idx);
    }
    if (candidates.isEmpty) return 0;

    final bundle = bundleHarvest(
      relayForMark: relayForMark,
      relayCount: candidates.length,
      offset: offset,
    );
    var placed = 0;
    for (final b in bundle) {
      if (placed >= maxRequests) break;
      final relay = candidates[b.relay];
      // PER REAL TAG [decoys] DECOYS, and they hang on the epoch
      // OF THE TAG, not on that of the run (S361): the same tag is asked in
      // two consecutive runs: if their decoys differed,
      // the intersection of two queries would be exactly the real
      // tag.
      final currentSet = <Uint8List>[];
      for (final mi in b.marks) {
        final tag = tags[mi];
        currentSet.add(tag);
        for (var i = 0; i < decoys; i++) {
          currentSet.add(SodiumFFI().hkdfSha256(pairs.deviceSecret,
              salt: tag,
              info: Uint8List.fromList(
                  utf8.encode('decoy/${epochs[mi]}/$i')),
              length: 32));
        }
      }
      currentSet.shuffle();
      final id = SodiumFFI().randomBytes(kRequestIdBytes);
      final key = base64.encode(id);
      _marksRequest[key] = sink;
      _ownRequests.add(key);
      while (_marksRequest.length > kOwnRequestMemory) {
        _marksRequest.remove(_marksRequest.keys.first);
      }
      while (_ownRequests.length > kOwnRequestMemory) {
        _ownRequests.remove(_ownRequests.first);
      }
      // SACRIFICEABLE: a harvest request that falls on overflow is
      // made anew in the next run. A placement in its place
      // would be the content itself.
      egress.stream
          .enqueueControl(buildHarvestRequest(
              relay.lNode, relay.x25519Public, id, currentSet),
              sacrificable: true);
      placed++;
      tagHarvestRequests++;
      log('Mark harvest: ${b.marks.length} mark(s) -> '
          'ask ${_posLabel(relay.lNode)} (table ${table.length})');
    }
    return placed;
  }

  /// Callbacks per slot, for work that this layer does not know.
  ///
  /// NO TIMER OF ITS OWN, and that is working rule 5 and §5.1
  /// invariant 1 at the same time: a second rhythm in the process would be
  /// recognisable from outside as such. The slot tick runs anyway. The
  /// callbacks run SYNCHRONOUSLY on the tick and must therefore do nothing long;
  /// whoever waits does so behind `unawaited` on his own side.
  ///
  /// ── A LIST AND NOT A SINGLE CALLBACK, AND THAT MEASURED ─────
  ///
  /// A single field would be a silent failure here with
  /// MULTI-IDENTITY. `attachV41` runs once per identity against
  /// THE SAME node (one process, one UDP port, several identities —
  /// see the header of `v41_attach.dart`), and §13.3.1 requires "**One
  /// bundle per identity**". With a field the second identity would have
  /// overwritten the first: its rescue bundle would never have been
  /// renewed again, and nothing would have reported it — the renewal
  /// runs every 14 days, its absence shows at the earliest after 31,
  /// and then the bundle is gone.
  final List<void Function(int slot)> _slotCallbacks =
      <void Function(int slot)>[];

  /// Hooks a consumer onto the slot tick.
  void addSlotTick(void Function(int slot) callback) =>
      _slotCallbacks.add(callback);

  /// Takes it off again. `true` if it was in.
  bool removeSlotTick(void Function(int slot) callback) =>
      _slotCallbacks.remove(callback);

  /// Fetches the own cells from the responsible relays (WP-4).
  ///
  /// ONE REQUEST PER RELAY, NOT PER TAG (S358). Until then "one request per
  /// real tag" applied; since a contact has six tags (three
  /// families message line, three signal line), that would be six
  /// frames with a cap of three — the contact would never get its full turn.
  /// `buendleErnte` instead puts all tags that the same relay
  /// can serve into ONE frame; in the small network that is exactly one.
  /// The decoys still lie in THE SAME request as their real
  /// tag — if they lay in separate ones, the real one would be recognisable by
  /// coming alone.
  ///
  /// CAPPED: at most [maxRequests] requests per call. Each costs
  /// one slot, and a node with many contacts would otherwise spend its
  /// whole tick harvesting.
  ///
  /// Returns how many requests were enqueued.
  ///
  /// THE CAP IS DERIVED, NOT CHOSEN (S353). The drain is
  /// fixed: `DeliveryNode.tick` takes EXACTLY ONE control frame per time slice,
  /// and between two harvest runs lie
  /// [harvestEverySlots] time slices. Whoever enqueues more per run than
  /// [harvestEverySlots] lets the queue grow with every run —
  /// and with it the waiting time of every new frame.
  ///
  /// `m x R` = 60 stood here from S352 to S353 and was exactly this
  /// error: 15.125 frames in per slot against 1.0 out. Measured in the field
  /// (.201, 29.08.): harvest tick 131 s instead of the designed 32 s,
  /// and after a single Secure send 5 min 22 s without any
  /// harvest run. `m x 1` = 3 lies below [harvestEverySlots] = 4 and is
  /// thus the largest number at which the queue is empty again between two runs.
  ///
  /// ── THE SAME THREE FRAMES BUY THREE CONTACTS SINCE S358 ─────────
  ///
  /// The number stays because its derivation stays: the drain is
  /// [harvestEverySlots] = 4 frames between two runs, three lies
  /// below. What has changed is what a frame CARRIES. Before
  /// S358 a counterpart cost three frames (`kDeliveryFamilies` tags
  /// at one relay each) — one run covered EXACTLY ONE contact, and
  /// with N contacts one waited up to `32 x N` seconds. With the
  /// bundling a counterpart in the small network costs ONE frame for
  /// BOTH lines; the same cap now covers three contacts per run.
  /// Measured: `smoke_v41_harvest_bundling.dart`, section 5.
  ///
  /// The expression deliberately stays `kDeliveryFamilies x
  /// kHarvestRelaysPerFamily`: it is still the right
  /// calculation for the WORST case, in which each family needs a
  /// relay of its own.
  static const int kHarvestRequestsPerRun =
      kDeliveryFamilies * kHarvestRelaysPerFamily;

  /// How many of the responsible relays a harvest asks PER FAMILY AND RUN.
  ///
  /// ONE, and that is no austerity, but the division of labour
  /// between the two sides. The placement covers the whole
  /// responsibility set (`m x R`, §9.2) — it MUST, because M6 computes the
  /// censorship cost over the whole set. Exactly for that reason a single node
  /// of this set suffices for the harvest: what lies on all R lies
  /// on the one that is asked too. Querying both sides fully
  /// would check `R x R` pairings where `R + 1` suffices.
  ///
  /// The offset moves on by one per run (`_ernteVersatz`), so that
  /// over `|set|` runs every responsible relay has been asked once —
  /// a failed attempt thus costs one run (32 s), not the delivery.
  static const int kHarvestRelaysPerFamily = 1;

  /// From how many waiting control frames on a harvest run pauses.
  ///
  /// ── WHY THIS THROTTLE IS NEEDED (S353) ─────────────────────────
  //
  /// The cover stream hands out EXACTLY ONE control frame per slot
  /// (`DeliveryNode.tick` calls `takeControl()` once), and a slot is
  /// on average `kSlotInterval` = 8 s. Between two harvest runs
  /// ([harvestEverySlots] = 4 slots) the queue thus empties by
  /// at most 4 frames.
  ///
  /// Since S353 the harvest itself is dimensioned so that it does not fill the queue
  /// ([kHarvestRequestsPerRun] = 3 against 4 draining
  /// frames). The throttle thus no longer regulates the harvest against itself,
  /// but the harvest against the PLACEMENT: a Secure send
  /// enqueues `m x R` frames at once (§9.2, measured in the field 30 with
  /// a table of 5), and as long as they drain, every
  /// additionally enqueued request would just be one that waits behind them.
  ///
  /// WHAT IT DOES NOT HEAL WITH THIS, and that belongs here rather than in a
  /// footnote: the sender stays without a harvest run for the duration of his own
  /// placement burst — measured on 29.08. **5 min 22 s**
  /// after a single text. That is the price from §9.2 ("the sender is
  /// occupied"), not an error of this throttle; it only does not shift it
  /// into a growing queue. Whoever wants to lower it must start at the
  /// PLACEMENT (R, or aggregation of several families per frame),
  /// not here.
  ///
  /// THE THROTTLE COSTS NO EGRESS. The slot tick sends exactly
  /// one cell per 8 s anyway, whether it carries harvest, placement or filler; what
  /// is limited here is solely the length of the queue.
  // UPDATED 18:10 (S381): the threshold was `harvestEverySlots` = 4
  // and thus derived against a cap of 120. With
  // `kMaxControlBacklog` = 1024 the queue stands practically always above
  // 4, the throttle is permanently on, and the RECEIVER no longer gets
  // at its pieces — measured on 11.09.: Alice `empfangen 2,
  // zusammengesetzt 0` with 85 paused harvest runs. The throttle
  // is to dampen a backlog, not switch off the harvest; it
  // therefore hangs on the cap it protects against, and no longer on
  // the run period.
  static const int kHarvestBacklogLimit = kMaxControlBacklog ~/ 8;

  /// After how many paused runs a harvest run takes place DESPITE a full
  /// queue.
  ///
  /// ── THE THROTTLE DID NOT THROTTLE, IT SWITCHED OFF (S355) ─────────────
  //
  /// [kHarvestBacklogLimit] is 4 frames. A single Secure send
  /// enqueues `m x R` — in the field 6 to 30. The queue thus stands permanently
  /// above the threshold after the first message, and the harvest run
  /// does not pause but stops.
  ///
  /// MEASURED on 30.08., window 20:00-20:15, twelve Secure messages:
  /// in fifteen minutes Alice made **3** own harvest requests, Bob
  /// **0**. The tick provides 3 per 32 s, i.e. about 84 per node. Of
  /// twelve messages 1 and 2 respectively arrived. Whoever sends stops
  /// receiving — and the more he sends, the longer.
  ///
  /// That is no error of the intention: the comment above names the price
  /// expressly ("the sender stays without a harvest run for the duration of his own
  /// placement burst … 5 min 22 s"). Measured, however, it is not limited to
  /// the duration of a burst, but to the
  /// duration of the TRAFFIC: as long as sending goes on, the queue never gets
  /// back below 4.
  ///
  /// THIS CAP LIMITS THE DARK TIME. After [kHarvestMaxSkips]
  /// paused runs one is let through, however full the
  /// queue stands.
  ///
  /// THREE, NOT FIFTEEN. A run falls every [harvestEverySlots] = 4
  /// slots at 8 s, i.e. every 32 s. Three skipped runs are thus
  /// at most 96 s without harvest; fifteen would be eight minutes, and eight
  /// minutes of silence are no longer load protection but the same state
  /// in slower.
  ///
  /// PRICE, calculated: [kHarvestRequestsPerRun] = 3 frames per four
  /// runs, i.e. 3 of 16 draining frames — **19 % of the
  /// control slots**, withdrawn from the placements. A placement burst
  /// of 30 frames thus needs 5 min instead of 4 min. That is the trade,
  /// and it is deliberately this way round: a placement that goes out four minutes later
  /// is delivered; a harvest that does not take place at all
  /// delivers nothing. The cap [kMaxControlBacklog] = 120 remains the
  /// hard limit.
  ///
  /// WHAT IT DOES NOT SOLVE, and that belongs here: the control channel is
  /// structurally overbooked. `kHarvestRequestsPerRun` = 3 frames per 4
  /// slots are alone already 75 % of the channel, and a Secure message
  /// needs 6 to 30 more. Whoever wants to resolve that must start at the PLACEMENT
  /// (aggregation of the m families per relay into ONE frame, R,
  /// or the cover rate) — and each of these adjusting screws touches
  /// traffic or anonymity, so belongs to the owner. This cap
  /// does only one thing: it prevents the harvest from stopping entirely.
  static const int kHarvestMaxSkips = 3;

  /// How many requests a FORCED harvest run makes at most
  /// (S374, link 2a).
  ///
  /// Forced means: `ernteLaufFaellig` only let it through
  /// because [kHarvestMaxSkips] was reached — so the
  /// control queue still stands above
  /// [kHarvestBacklogLimit]. Such a run is to PREVENT STARVATION,
  /// not produce throughput; ONE request suffices for that.
  ///
  /// ONE, calculated and not chosen. The drain is ONE
  /// control frame per slot, between two runs lie
  /// [harvestEverySlots] = 4 slots. With the full cap
  /// [kHarvestRequestsPerRun] = 3 the calculation holds per CALL (3 < 4) —
  /// but the drain belongs to the NODE, and with two identities
  /// two calls stand against the same cover stream. Measured in the field
  /// (07.09.2026, .201, two identities): 6 requests per ~31 s against 4
  /// draining, queue 120/120, discarded 180 and rising. With
  /// ONE request per forced run the calculation stays negative even
  /// when several identities force at the same time.
  ///
  /// WHAT IT COSTS: the harvest latency rises as long as the queue stands.
  /// That is no real loss — a request that stands behind 120 frames
  /// waits up to 16 minutes anyway.
  ///
  /// WHAT IT DOES NOT TOUCH: the slot tick. `kSlotInterval` = 8 s is
  /// E-C' (§5.3) and carries the 12.96 MB/day from §31.5.
  static const int kHarvestForcedRequests = 1;

  /// How many harvest runs the throttle has paused in a row.
  int _harvestSuspended = 0;

  int harvestTick(
      {DateTime? now,
      int maxRequests = kHarvestRequestsPerRun,
      int decoys = 3}) {
    final current = now ?? DateTime.now().toUtc();
    // THE CLOCK OF THE CATCH-UP HARVEST, AND THAT UP HERE. It does not measure whether
    // a run ACHIEVED anything, but whether this process ran
    // at all — exactly the quantity from which `nachholErnte` computes the
    // absence. If it stood at the end of the body, every
    // round paused by the backlog throttle (and every round without
    // pairs) would have faked an absence that did not exist.
    // ── THE COLD START, AND WHY IT HANGS HERE (E5, S363) ───────────
    //
    // [_letzterErnteLauf] is `null` as long as this process has not yet
    // harvested — after a restart thus exactly when an
    // absence occurred. `nachholErnte` therefore so far never found an
    // absence across a restart, and the comment at
    // [_letzterErnteLauf] reported that as an open limit.
    //
    // The STORED horizon closes it: it survives the restart and
    // says up to where things have been asked. The first run of this process is
    // the edge (not a tick, working rule 5) — it asks it once
    // and measures the absence against it.
    //
    // WITHOUT THESE LINES E5 WOULD BE A TRAP, not an improvement: the
    // horizon would advance to `jetzt` at the first run after the restart,
    // because no catch-up is open — and then all
    // old prekeys would fall after all, only one round later. The cold start MUST
    // set the catch-up before the first run touches the horizon.
    if (_lastHarvestRun == null) {
      // THE DEEPEST STATE ACROSS ALL IDENTITIES (V-1 = B, S376). A
      // catch-up is a quantity of the node; the deepest gap
      // contains all shallower ones, and thus ONE run covers every identity.
      // Bundling without additional traffic.
      final h = oldestHorizon;
      if (h != null) catchUpHarvest(now: current, since: h, reason: 'Kaltstart');
    }
    _lastHarvestRun = current;
    var placed = 0;

    // ── THE DEADLINE, AND WHY IT IS ENFORCED HERE (B-32, S350) ──────
    //
    // `SecureStore.expire()` had NO caller in `lib/` — only a
    // smoke test called it. A relay thus never forgot anything: the store
    // grew unboundedly, and every placed cell was delivered anew at EVERY
    // harvest run of the receiver until process end. The 21
    // deliveries of 28.08. were not the end, they were the first
    // three and a half minutes.
    //
    // The harvest run is the right place: it is the only
    // regular tick of this layer that does not hang on the slot plan
    // (a second timer would be a second rhythm in the egress and
    // recognisable from outside as such — invariant 1).
    final nodeEpoch = nodeEpochNow(current);
    // TWO CLOCKS SINCE S358: the node epoch for the ordinary
    // deadline, the 120 s bucket for the signal line (§17.2). Both come
    // from THE SAME time `jetzt` — two separately read clocks would disagree at
    // the epoch boundary.
    delivery.store.expire(nodeEpoch, retentionBucket(current));
    // AND THE ENTRY SUPPLY (B-33). Until S350 it knew no
    // expiry path at all except the incidental cleanup in `lookup` — what was never
    // looked up stayed lying until displacement at 512 and
    // was passed on to partners by `_entrySet`. §11.1: "Expired
    // records are not passed on."
    entries.expire(current);
    for (final m in _harvestMemo.values) {
      m.expire(nodeEpoch);
    }

    // FIRST LOOK IN ONE'S OWN STORE. The responsible relays are the
    // nodes nearest to the tag — this node can itself be one of them,
    // and then the cell lies here. Without this step it would ask
    // half the neighbourhood for something that lies in its own store.
    // (Noticed exactly so in the lab: A placed, B stored, and B did not find
    // it.)
    //
    // ── VIA A COPY, NOT VIA THE LIVE SET ──────────
    //
    // `pairs.peers` is `_kAb.keys` — a VIEW onto the registry, not a
    // snapshot. This body hands cells to the application
    // (`_geerntetVon` -> sink -> `CleonaService`), and the application may
    // change the pair set in doing so. It even MUST:
    //
    //   * an accepted contact request enters the new pair
    //     (`_saveContacts` -> `primeV41Pairs` -> `rememberPeer`),
    //   * and a redeemed one-time invitation withdraws its line
    //     (§15.4 -> `armV41InviteLines` -> `forgetPeer`).
    //
    // Run over the live view, the harvest run then ends with
    // `Concurrent modification during iteration` — in the middle of the tick, after
    // the delivery, but BEFORE the rest of the harvest. Measured on 01.09. in
    // `smoke_invite_single_use.dart`: the throw came with two pairs, directly
    // after the self-acceptance from §15.4 had withdrawn the consumed invitation line.
    //
    // The copy is the right place and not the rule "the
    // application must not touch anything here": this rule would stand nowhere,
    // could not be kept from the application's side, and the delivery
    // is exactly the purpose of this body. A counterpart that disappears during
    // the run falls through one line further via `kAb == null` and
    // is skipped — so no harvesting happens for a dead pair.
    //
    // FILTERED BY `harvestPeers`, since the device-bound line
    // (§14.7): a pure PLACEMENT line is supplied and never harvested.
    // The copy remains necessary nonetheless — `harvestPeers` is a
    // lazy `where` OVER `_kAb.keys` (`pair_registry.dart:78`), so
    // the same live view as before, only narrower. Whoever drops one of the two
    // changes when merging them gets
    // either the throw back or harvests on a placement line.
    for (final peer in pairs.harvestPeers.toList(growable: false)) {
      final kAb = pairs.kAbFor(peer);
      if (kAb == null) {
        pairEmptySkipped++;
        continue;
      }
      final epoch = secureEpoch(kAb, current);
      // THE OPPOSITE DIRECTION IS HARVESTED (B-22). Without it the
      // node fetches back its own placements — sealed against the
      // counterpart, so not openable for itself — and thereby displaces
      // the pieces it is waiting for.
      final inv = pairs.inDirectionFor(peer);
      // BOTH LINES (S358). The own store costs no frame,
      // and leaving out of all things the signal line there would be expensive:
      // in the small network the receiver is often itself one of the
      // `kSignalRelays` = 5 responsible ones, and then the INVITE lies here.
      //
      // ── HERE THE FULL EPOCH DEPTH, BECAUSE IT COSTS NOTHING (S361) ──
      //
      // The foreign harvest must sample the depth (`ernteEpochenPlan`),
      // because every tag costs a control frame there and the channel
      // is overbooked. HERE it costs nothing: the own store is
      // a map, and `harvest` is one lookup per tag. That is why
      // the function that §22.4.1 computes verbatim stands at this place
      // — `harvestQuerySet`.
      //
      // AND THAT UP TO [kManagementKeepEpochs] = 31, NOT UP TO
      // [kHarvestEpochs] = 3. The own store keeps a
      // management cell 31 epochs (`SecureStore.expire`, branch
      // [kRetentionManagement]); with a query of three epochs
      // 28 of them lay unreachable in the own process — the node was its
      // own mute relay. Exactly this case occurs frequently in the small network:
      // the receiver is himself one of the
      // [kResponsibleRelays] responsible ones.
      //
      // WHAT THE DEPTH COSTS HERE, calculated instead of estimated: the
      // number of tags per counterpart rises from `kFamilies x 3` = 9 to
      // `kFamilies x 31` = 93, plus the 3 signal tags. Every tag is
      // ONE HKDF-SHA256 (`secureTag`) and ONE map lookup; with 20
      // counterparts and one run every 32 s that is about 1920 instead of 240
      // derivations per run, i.e. **60 instead of 7.5 per second**. No
      // byte on the wire, no frame, no slot.
      //
      // WITHOUT DECOYS, and that is not thrift, but the matter itself:
      // decoys mask against a FOREIGN relay that sees the query
      // (§6). When looking into the own store nobody is watching — three
      // quarters of the tags would be pure compute time without an addressee.
      //
      // THE SIGNAL LINE STAYS ON THE CURRENT EPOCH, calculated:
      // a signal cell lives [kSignalKeepBuckets] = 2 buckets at
      // [kRetentionBucketSeconds] = 120 s, i.e. at most 240 s. A
      // previous epoch is at least 86 400 s old. Under a signal tag
      // of the previous epoch nothing can lie any more by construction.
      final own = <Uint8List>[
        ...harvestQuerySet(
            kAb: kAb,
            deviceSecret: pairs.deviceSecret,
            currentEpoch: epoch,
            direction: inv,
            epochs: kManagementKeepEpochs,
            decoysPerTag: 0),
        for (var f = 0; f < kDeliveryFamilies; f++)
          signalTag(kAb, epoch, f, inv),
      ];
      // HERE TOO THE HAVE-LIST (B-32) — without it the node fetches
      // everything it already has from its own store anew at every run,
      // and that m=3 times, because the three family tags
      // carry the same content. Filler tags are not needed: here
      // nobody is watching.
      final self = delivery.store
          .harvest(own, exclude: _memoFor(peer).knownDigests());
      // THE SELF-HARVEST HAD NO LINE, and that was the gap that made the
      // field finding of 29.08. undecidable. A node that as a
      // responsible relay accepts a cell FOR ITSELF logs it
      // as "placed" — then nothing more. Whether it afterwards finds it again in its
      // own store stood nowhere; what became visible was only
      // the absence of the message, minutes later and without a place.
      //
      // THE ZERO IS LOGGED TOO. "nothing under the own tags" is
      // the more frequent and the more important information: together with the
      // placement line of the same prefix on the other side it decides
      // whether the two calculations have yielded the same tag.
      log('Self-harvest ${_peerLabel(peer)}: ${self.length} '
          '[${own.map(tagLabel).join(' ')}] store '
          '${delivery.store.cellCount}');
      for (final s in self) {
        _harvestedFrom(peer, s.cell);
      }
    }

    // ── ROUND-ROBIN, NOT ALWAYS FROM THE START (B-30, S349) ────────────────────
    //
    // Per contact a harvest costs `kDeliveryFamilies` (3) requests, and
    // [maxRequests] caps at 4. The loop so far ALWAYS began at the
    // first counterpart — so exactly the first one and a half got their turn,
    // and all others NEVER. With eight contacts the ninth was as
    // unreachable as a switched-off node.
    //
    // Measured in the field on 28.08.: the phone had eight pair keys and
    // harvested round after round for the same TWO — Bob was never included.
    // His messages lay at the responsible relay the whole time;
    // both sides only saw "geerntet: 0" and considered the other
    // mute.
    //
    // The pointer moves, so every contact gets its turn after at most
    // `ceil(N * 3 / 4)` runs — with eight contacts and
    // one run every 32 s about three minutes.
    // ── PURE PLACEMENT LINES DO NOT STAND HERE ────────────────────────
    //
    // `harvestPeers` leaves out what is only supplied
    // (`PairRegistry.isPlaceOnly`). For the device line of a
    // sister (§14.7, `device_line.dart`) that is the whole effect
    // of the line: if this device harvested it too, it would get material
    // that another device is meant for — and it could even open it
    // (§14.2, shared user KEM key).
    final all = pairs.harvestPeers.toList();
    if (all.isEmpty) {
      // THIS EXIT TOO ADVANCES THE HORIZON (E5, S363), and that
      // is no oversight, but the difference from the exit at the
      // backlog throttle further below:
      //
      //   * HERE there is NOTHING to ask. The epoch axis is sampled in the
      //     sense that nobody is there with whom something could lie.
      //     If the horizon stood still, a node that is still
      //     learning its pairs would never get to expiry — the supply
      //     would grow up to the cap.
      //   * AT THE THROTTLE the run was paused, so there WAS no
      //     asking, although there was something to ask. There it must not
      //     advance, and that is why the line does not stand there.
      //
      // `nachholungOffen` applies nonetheless: if a catch-up is running and
      // no counterpart is there right now, the gap is not closed — one can
      // be added again at any moment.
      _horizonsAdvance(current: current, catchUpOpen: _catchUpUntil > 0);
      return placed;
    }

    // ── TWO RANKS, SO THAT THE LATENCY DOES NOT HANG ON THE CONTACT COUNT ──
    //
    // The round-robin pointer alone (B-30) distributes fairly, but the waiting time
    // grows LINEARLY with the contact count: three requests per run and three
    // families per pair mean EXACTLY ONE PAIR PER RUN, one run every 32 s.
    // Calculated: 20 contacts = 10.7 min, 100 = 53 min, 200 = 107 min, until
    // a particular pair is queried again. The hard limit
    // behind it is not `maxRequests`, but the drain of the
    // cover stream — one cell per 8 s; more requests per run only fill
    // the control queue (field 30.08.: 434 discarded control frames).
    //
    // And priming ALL contacts (30.08.) enlarges the set.
    //
    // Hence first the pairs with fresh traffic, then the cold ones
    // round-robin. With 200 contacts and three running conversations the
    // waiting time for the three falls from 107 min to 3 x 32 s — independent of
    // the total number. Cold ones keep the long rotation; their messages
    // lie in the placement for up to seven days and are not lost.
    //
    // WHAT THIS DOES NOT SOLVE: if a COLD contact writes for the first time,
    // he still waits up to 32*N seconds. Only putting several
    // tags into ONE control frame helps against that (frame 1169 B, tag 16 B)
    // — a wire change that is proposed and not built on the side.
    var considered = 0;
    // AT MOST ONE counterpart per run carries catch-up tags — the
    // reasoning stands below at [_nachholBis].
    var catchUpAssigned = false;

    // ── THROTTLE BEFORE THE QUEUE, NOT AFTER IT ──────────────────────
    //
    // From here on enqueuing happens, and it happens over the whole
    // responsibility set (`m x min(R, known)`). If the
    // control queue is still full from the last run, this one pauses:
    // otherwise it would grow unboundedly, because the slot tick only lets
    // [harvestEverySlots] frames drain per run. See
    // [kHarvestBacklogLimit] — the throttle costs no egress, it
    // only prevents a fresh request from waiting behind ten minutes of
    // old load.
    //
    // ONLY AFTER THE SELF-HARVEST. That costs no slot (it reads the
    // own store), and leaving out of all things that one because the
    // queue is full would be the wrong saving.
    // Pausing yes, stopping no — see [kHarvestMaxSkips]. The
    // decision lies next to it as a pure function, so that it can be tested
    // and is not only commented.
    if (!harvestRunDue(
        waitingFrame: egress.stream.pendingControl,
        limit: kHarvestBacklogLimit,
        suspended: _harvestSuspended,
        atMostSkips: kHarvestMaxSkips)) {
      _harvestSuspended++;
      return placed;
    }
    // ── THE FORCED RUN IS SMALL, NOT FULL (S374, link 2a) ────
    //
    // `harvestRunDue` lets a run through after [kHarvestMaxSkips] pauses,
    // EVEN if the queue still stands above the limit —
    // "pausing yes, stopping no". That was meant against a
    // TEMPORARY backlog. Against a STANDING one it achieves
    // the opposite: the run then goes in with the full cap and
    // pushes the queue further up instead of letting it sink.
    //
    // MEASURED IN THE FIELD on 07.09.2026 on .201 (two identities):
    //   harvest rounds every ~31 s, 6 requests each  ->  6 in
    //   drain one control frame per slot             ->  4 out in 32 s
    //   control queue 120/120, discarded 180 and rising
    // The cap [kHarvestRequestsPerRun] = 3 is derived against the
    // 4 draining frames between two runs and holds — per
    // CALL. But the drain belongs to the NODE, and with two
    // identities two calls stand against the same cover stream.
    //
    // The purpose of the forced run is that the harvest does not
    // starve. ONE request suffices for that; a full run is not
    // necessary for that and makes the cause worse. The latency of the harvest
    // rises through this as long as the queue stands — that is the intended
    // price, because a request that waits 16 minutes in the queue
    // is no faster one anyway.
    //
    // NOT TOUCHED: the slot tick. `kSlotInterval` = 8 s is E-C'
    // (§5.3, `R_cover` = 1/8 s) and carries the 12.96 MB/day of the
    // parameter table §31.5 — an architecture quantity, no adjusting screw.
    // The decision lies as a pure function next to `harvestRunDue`
    // (`secure_mode.dart`), so that it can be tested and is not only
    // commented — the same pattern, the same place.
    final cap = harvestCap(
      waitingFrame: egress.stream.pendingControl,
      limit: kHarvestBacklogLimit,
      fullCap: maxRequests,
      forcedCap: kHarvestForcedRequests,
    );
    if (_harvestSuspended > 0) {
      log('Harvest: $_harvestSuspended runs suspended '
          '(queue ${egress.stream.pendingControl}) — one goes anyway, '
          'capped at $cap instead of $maxRequests');
    }
    _harvestSuspended = 0;

    // ── THE ORDER IS DECIDED HERE, NOT FURTHER UP (S382) ─────────
    //
    // It needs `deckel`, and `deckel` needs the throttle. If the
    // rank stood further up, "is this run throttled" would have to be computed a second
    // time from `pendingControl` — a second truth
    // about the same thing, which diverges at the next rebuild.
    // `deckel < maxRequests` IS the throttle, without asking it
    // again.
    //
    // The counter stands at the NODE and not at the run: it is to
    // alternate across the runs, not begin anew at zero in every run.
    // The first throttled run serves the cold rank — whoever
    // just gets into the throttle has already served the active rank in the last
    // unthrottled run.
    final throttled = cap < maxRequests;
    if (throttled) _throttledRuns++;
    final rank = harvestRank(
      all: all,
      lastTraffic: _lastTraffic,
      current: current,
      activePointer: _harvestPointer,
      coldPointer: _coldPointer,
      coldFirst: throttled && _throttledRuns.isOdd,
    );
    final active = rank.active;
    final cold = rank.cold;
    final ordered = rank.ordered;

    for (final peer in ordered) {
      if (placed >= cap) break;
      considered++;
      final kAb = pairs.kAbFor(peer);
      if (kAb == null) {
        // NO LONGER MUTE (30.08.) — see `paarleerSkipped`.
        pairEmptySkipped++;
        continue;
      }
      final epoch = secureEpoch(kAb, current);
      final inv = pairs.inDirectionFor(peer);

      // ── THE PLACEMENT COVERS THE SET, THE HARVEST SAMPLES IT ──────────
      //
      // Until S352 a `break` stood here: exactly ONE relay per family,
      // i.e. R = 1 on both sides. Both sides compute the same
      // tag — but each on its own table, and two
      // different tables practically never choose the same
      // one node from it. On 29.08. in the field:
      //
      //   `Bob legt ab:  Familie 0 -> Relais 49527e5b (Ziel 8a565454)`
      //   `Handy fragt:  Familie 0 -> frage  819c4d49 (Ziel 8a565454)`
      //
      // S352 thereupon set BOTH sides to the full set.
      // That opened up delivery — and blew up the egress.
      //
      // ── WHY THE HARVEST DOES NOT NEED THE FULL SET (S353) ────────
      //
      // The redundancy sits on the PLACEMENT SIDE. §9.2 requires `m x R`
      // placements, because M6 (`P1 = 1 - exp(-R*f)`) presupposes the cell on the WHOLE
      // responsibility set. Exactly for that reason ONE relay of this set suffices
      // for the harvest: if the cell lies on all R, then it lies
      // on the one that is asked too. The full set on BOTH
      // sides queries `R x R` pairs where `R + 1` suffices — effort without
      // return. §9.2 budgets the placement; about the cardinality
      // of the harvest the spec says nothing, and it need not.
      //
      // WHAT THE FULL HARVEST COST, measured on 29.08. on .201:
      // a single text (124 B) filled the control queue with 30
      // frames; at one cell per 8 s the node was **deaf for 5 min 22 s**
      // (22:27:24 sent, 22:32:46 harvested again). After that
      // EVERY harvest run enqueued 15 more requests, which need 120 s to drain
      // — the harvest tick thus lay at a measured 131 s instead of the
      // designed 32 s (22:32:46 -> 22:34:57). The inflow was 15.125
      // frames per slot against an outflow of 1.0; that already stands so in the
      // comment of `_pushControl` and was noted there as a finding,
      // not as an intention.
      //
      // SAMPLING IS ROUND-ROBIN, NOT RANDOM. An offset per counterpart
      // moves on by one with every run; over `|set|` runs
      // every responsible relay is thus asked exactly once. Randomness
      // would hit the same on average, but could draw the same relay several times
      // in a row and leave out another for a long time — with a
      // cap of one relay per family that is the difference
      // between "at the latest after |set| runs" and "sometime".
      //
      // THE PRICE is openly stated: if the one asked node finds nothing,
      // it takes one run longer. With `harvestEverySlots` = 4 that is
      // 32 s per failed attempt against the 120 s that the full set cost EVERY
      // run. The trade is thus favourable for the latency too,
      // not only for the egress.
      // ── BOTH LINES IN ONE GO (S358) ────────────────────────────
      //
      // First the `kDeliveryFamilies` tags of the MESSAGE line, then
      // the same number of the SIGNAL line (§17.2). Six tags, and that is
      // exactly [kMaxRealHarvestTags] — the signal line thus costs
      // NO additional frame, as long as a common relay
      // is found. If none is found, it costs a second one;
      // both can be read below from `bundle.length` and are logged.
      //
      // WHY THE SIGNAL LINE ASKS ALONG IN EVERY RUN: an INVITE lives
      // 120 s (`kInteractiveDeliveryTtl`), a harvest run falls every
      // 32 s. Asking it only occasionally would mean missing it
      // most of the time.
      //
      // ── AND THE EPOCH DEPTH, SAMPLED (S361) ─────────────────────
      //
      // §22.4.1 requires "epoch subscription: current + 2 previous". Until
      // S361 only `epoch` stood here — the offline tolerance
      // was thus one epoch boundary (<= 24 h) instead of the three days that
      // the retention (`SecureStore.keepEpochs` = [kHarvestEpochs])
      // actually keeps. Whoever was away longer queried tags under
      // which nothing ever lay, while his cells lay at the relay.
      //
      // Three epochs x three families plus three signal tags would be TWELVE
      // real tags; a frame carries six ([kMaxRealHarvestTags]).
      // Two frames per counterpart against a cap of three means: one
      // counterpart per run instead of three. That is why the harvest samples the
      // epoch axis just as §6 lets it sample the relay axis
      // — the full derivation stands at [harvestEpochsPlan].
      //
      // ── AND SINCE S362 OVER TWO RANKS ──────────────────────────────
      //
      // The shallow rank covers [kHarvestEpochs] = 3 (the ordinary
      // deadline), the deep one up to [kManagementKeepEpochs] = 31 (the
      // management class, §21.1). Without the deep one 28 of the 31 days
      // that a relay keeps a management cell were unreachable: the
      // relay kept, nobody asked. The number of tags per run stays
      // the same — the choice between the ranks costs no frame,
      // it costs catch-up latency, and the calculation for that stands at
      // [harvestEpochsPlan].
      //
      // THE SIGNAL LINE STAYS ON THE CURRENT EPOCH: a
      // signal cell lives at most [kSignalKeepBuckets] x
      // [kRetentionBucketSeconds] = 240 s, a previous epoch is at least
      // 86 400 s old.
      final offset = _harvestOffset[peer] ?? 0;
      final plan = harvestEpochsPlan(currentEpoch: epoch, run: offset);

      // ── THE CATCH-UP HARVEST, IF ONE IS RUNNING (variant C, S362) ───────
      //
      // The rotation above needs about 3.5 h with 20 contacts until every
      // deep backlog has been asked once ([ernteEpochenPlan]). That is
      // right for continuous operation and wrong for the moment in which
      // a device comes back after days — exactly there hangs the
      // management class.
      //
      // HENCE AN EDGE, NOT A TIMER (working rule 5): `nachholErnte`
      // is called by `onNetworkChanged` and by the return to the foreground,
      // measures the absence in epochs and sets [_nachholBis].
      // As long as it is set, this run appends up to
      // [kNachholMarkenProLauf] additional tags to ONE counterpart.
      //
      // ONE FAMILY PER BACKLOG, not three — that is the reason why
      // the catch-up is affordable at all. The placement puts the same
      // content under ALL `m` family tags (§9.2); one found
      // family suffices. Six tags thus cover SIX backlogs
      // instead of two. The family moves with the backlog and with the
      // relay offset, so that two catch-ups do not choose the same one.
      //
      // WHAT IT COSTS, calculated with today's constants: with N = 20
      // counterparts and an absence of A epochs it is
      // `ceil(A / 6) x N` catch-up frames. A = 2 (the situation for which the
      // proposal named 20 frames and 224 s): 1 x 20 = **20 frames**, with
      // [kHarvestRequestsPerRun] = 3 and 32 s per run **224 s** — the
      // proposal's number, independently recalculated. A = 30 (the deepest
      // reachable situation): 5 x 20 = **100 frames**, about 53 min.
      //
      // AND IT IS NO ADDITIONAL EGRESS. The frames run within the
      // EXISTING cap [maxRequests]; the cover stream hands out one cell
      // per slot either way (§5.1, invariant 1). What the
      // catch-up really costs is one place per run that would otherwise have
      // gone to another counterpart — the round time of the
      // ordinary harvest grows by up to 50 % during the drain,
      // and afterwards falls back. AT MOST ONE counterpart per
      // run gets catch-up tags; without this throttle a run would have
      // put its whole cap into the catch-up and no longer asked the current
      // epoch at all.
      final catchUp = <int>[];
      if (_catchUpUntil > 0 && !catchUpAssigned) {
        var z = _catchUpPointer[peer] ?? 1;
        while (z <= _catchUpUntil && catchUp.length < kCatchUpMarksProRun) {
          catchUp.add(z);
          z++;
        }
        if (catchUp.isNotEmpty) {
          _catchUpPointer[peer] = z;
          catchUpAssigned = true;
        }
      }
      // PER TAG ITS OWN EPOCH, because the TARGET includes it in the computation:
      // `targetFor(tag, epoche)` mixes the epoch into the search point
      // (§9.1, `H(T ‖ e)`). Addressing a previous-epoch tag against the current
      // epoch would ask the wrong relays — the same
      // class of error as R=1 (S352), only one axis further.
      final marksEpoch = <int>[
        ...plan,
        for (var f = 0; f < kDeliveryFamilies; f++) epoch,
        for (final r in catchUp) epoch - r,
      ];
      final marks = <Uint8List>[
        for (var f = 0; f < kDeliveryFamilies; f++)
          secureTag(kAb, plan[f], f, inv),
        for (var f = 0; f < kDeliveryFamilies; f++)
          signalTag(kAb, epoch, f, inv),
        for (final r in catchUp)
          secureTag(kAb, epoch - r, (r + offset) % kDeliveryFamilies, inv),
      ];
      final targets = <Uint8List>[
        for (var i = 0; i < marks.length; i++)
          targetFor(marks[i], marksEpoch[i])
      ];
      // ONLY THE SIGNAL TAGS DRAW FROM THE SMALL SET. The catch-up
      // tags stand BEHIND them and are message tags — with the
      // earlier `i < kDeliveryFamilies ? R : R_signal` they would have drawn the
      // signal set and asked the wrong relays.
      final sets = <List<EntryRecord>>[
        for (var i = 0; i < marks.length; i++)
          responsibleRelays(targets[i],
              count: (i >= kDeliveryFamilies && i < 2 * kDeliveryFamilies)
                  ? kSignalRelays
                  : kResponsibleRelays)
      ];

      // ── THE CANDIDATE LIST, DEDUPLICATED ─────────────────────────────
      //
      // The same relay usually stands in SEVERAL of these sets:
      // `responsibleRelays` computes a target of its own per tag, but draws
      // from THE SAME routing table — with fewer than R known nodes
      // all six sets are even identical (only sorted differently).
      // Exactly on that the bundling rests, and exactly for that reason the
      // list must be deduplicated by position: listing a relay twice
      // would mean asking it twice.
      final candidates = <EntryRecord>[];
      final candidateIndex = <String, int>{};
      final relayForMark = <List<int>>[];
      for (final m in sets) {
        final idx = <int>[];
        for (final r in m) {
          final k = base64.encode(r.lNode);
          final present = candidateIndex[k];
          if (present != null) {
            idx.add(present);
          } else {
            candidateIndex[k] = candidates.length;
            idx.add(candidates.length);
            candidates.add(r);
          }
        }
        relayForMark.add(idx);
      }
      if (candidates.isEmpty) {
        log('Harvest for ${_peerLabel(peer)}: no relay known '
            '(table ${table.length})');
        continue;
      }
      final bundle = bundleHarvest(
        relayForMark: relayForMark,
        relayCount: candidates.length,
        offset: offset,
      );
      final cost = bundle.length;
      if (cost == 0) {
        log('Harvest for ${_peerLabel(peer)}: no relay known '
            '(table ${table.length})');
        continue;
      }
      // ── WHOLE CONTACTS, BUT NEVER ZERO (S358) ───────────────────
      //
      // S353 set "whole contacts, not halves" here: if a
      // counterpart no longer fits wholly into the run, it waits for the
      // next. That was right as long as `kosten` was FIXED at
      // `kDeliveryFamilies` = 3 and the cap was likewise 3 — then
      // the rule only took effect from the second contact.
      //
      // WITH THE BUNDLING `kosten` IS NO LONGER FIXED. With a
      // large routing table (measured on 31.08. with 25 known
      // relays) a single relay no longer covers all six tags
      // of a pair; `kosten` then fluctuates between 1 and 4. With
      // `kosten` = 4 and `gestellt` = 0 the old line said "does not
      // fit" and aborted the WHOLE run — the node made not a
      // single request, run after run. In the test that showed as
      // "0 Rahmen nach 5 Laeufen"; in the field it would have been the same
      // picture as on 30.08.: a node that sends and receives nothing.
      //
      // The rule stays, but it only applies once something has gone out.
      // If this counterpart is the FIRST of the run, as much goes as
      // possible — half a contact is still better than no
      // contact, and with the bundling already the first bundle covers
      // several tags. The rest comes in the next run: `versatz`
      // moves on, the rotation begins at a different relay.
      if (placed + cost > cap && placed > 0) {
        considered--;
        break;
      }
      final covered = bundle.fold<int>(0, (a, b) => a + b.marks.length);
      // ── WHICH TAGS EXACTLY (S382, measurement) ──────────────────────
      //
      // The line below names them only symbolically (N0,N1,…). The
      // placement side has named them verbatim since S382; without the same
      // short form here the two lists cannot be compared —
      // and exactly there the narrowing down got stuck on 12.09.2026:
      // Alice placed under `8ccba741 beb7ea07 145f0112`,
      // Bob harvested the same pair with the same `K_AB`, the same epoch
      // and the same direction, and none of these tags ever turned up in
      // his log. Whether both sides MEAN the same tag was
      // not decidable, because only one names it.
      // Both short forms, see the reasoning at `Ablage-Marken`.
      log('Harvest tags ${_peerLabel(peer)}: epoch $epoch, direction $inv, '
          'plan ${plan.map((e) => e - epoch).join(",")} '
          '-> ${marks.take(kDeliveryFamilies).map(tagLabel).join(" ")} '
          '(targets ${targets.take(kDeliveryFamilies).map(tagLabel).join(" ")})');
      log('Harvest for ${_peerLabel(peer)}: '
          'K_AB ${_fingerprint(kAb)}, epoch $epoch, direction $inv, '
          'epoch plan ${plan.map((e) => e - epoch).join(',')}, '
          '${catchUp.isEmpty ? '' : 'catch-up -${catchUp.join(',-')} '
              '(until -$_catchUpUntil), '}'
          '$cost request(s) for $covered of ${marks.length} tags '
          '(${candidates.length} candidates)');
      for (final b in bundle) {
        if (placed >= cap) break;
        final relay = candidates[b.relay];
        log('  marks ${b.marks.map((i) => i < kDeliveryFamilies ? 'N$i' : (i < 2 * kDeliveryFamilies ? 'S${i - kDeliveryFamilies}' : 'H-${catchUp[i - 2 * kDeliveryFamilies]}')).join(',')}'
            ' -> ask ${_posLabel(relay.lNode)} '
            '(table ${table.length})');

        // THE DECOYS ARE THE SAME PER TAG, and that is intentional: they
        // are derived from `(Geraetegeheimnis, Tag, Epoche)`, so that
        // two queries of the same epoch cannot be told apart by changing decoys
        // as "real versus invented" (§6). That
        // now also applies across the R responsible ones — they all see
        // the same set and learn nothing from it that one
        // alone would not already see. The ORDER is shuffled anew per request,
        // so that the position in the frame reveals nothing.
        //
        // PER REAL TAG [decoys] DECOYS, also in the bundle. A
        // shared decoy block for several real tags would be cheaper
        // and wrong: the ratio of real to invented is exactly the
        // quantity that §6/E-C′ fixes, and it must not depend on
        // how many tags happened to fall on the same relay.
        //
        // AND THEY HANG ON THE EPOCH OF THE TAG, NOT ON THAT OF THE
        // RUN (S361). As long as only the current epoch was asked,
        // that was the same. With the epoch depth no longer: the same
        // tag `N-1` is asked in epoch `N` and in epoch `N+1`
        // (there as `N-2`). If its decoys were derived from the CURRENT epoch,
        // the two queries would differ in all
        // decoys and agree in exactly one element — the
        // real one. The intersection of two queries is exactly the attack that
        // the deterministic derivation is meant to fend off (§6, see
        // `harvestQuerySet`). Anchored to the epoch of the TAG,
        // the intersection yields the tag WITH its three decoys, i.e.
        // again one of four.
        final currentSet = <Uint8List>[];
        for (final mi in b.marks) {
          final tag = marks[mi];
          currentSet.add(tag);
          for (var i = 0; i < decoys; i++) {
            currentSet.add(SodiumFFI().hkdfSha256(pairs.deviceSecret,
                salt: tag,
                info: Uint8List.fromList(
                    utf8.encode('decoy/${marksEpoch[mi]}/$i')),
                length: 32));
          }
        }
        currentSet.shuffle();

        final id = SodiumFFI().randomBytes(kRequestIdBytes);
        // WHO ASKED, so that the answer goes to the right reassembler.
        // Without that the harvest of all contacts would run through ONE
        // buffer, and four incomplete transmissions of a single
        // counterpart could jam the harvest of all others.
        //
        // AND EXACTLY THIS LINE IS THE LIMIT OF THE BUNDLING: one
        // entry, one counterpart. Putting tags of TWO contacts into one request
        // would turn the sender into a guess (path A, S352 /
        // B-20) — see `buendleErnte`.
        final key = base64.encode(id);
        _requestPeer[key] = peer;
        _ownRequests.add(key);
        while (_requestPeer.length > kOwnRequestMemory) {
          _requestPeer.remove(_requestPeer.keys.first);
        }
        while (_ownRequests.length > kOwnRequestMemory) {
          _ownRequests.remove(_ownRequests.first);
        }
        // WHAT I ALREADY HAVE, I SAY ALONG (B-32). Exactly
        // [kHarvestHaveSlots] tags, padded — a shorter list
        // would itself be the information "this much already lies with me".
        //
        // IT STAYS RIGHT PER COUNTERPART, because a bundle only carries tags
        // of ONE counterpart: the evidence stems from exactly his
        // book. If several contacts were in one frame, their books would have
        // to share the 32 places — one more reason why the
        // bundling ends there.
        //
        // SACRIFICEABLE (S355): a harvest request that falls on overflow
        // is made anew 32 s later. A placement that falls in
        // its place is the message itself.
        egress.stream.enqueueControl(
            buildHarvestRequest(
                relay.lNode, relay.x25519Public, id, currentSet,
                have: _memoFor(peer).declare(
                    deviceSecret: pairs.deviceSecret, epoch: epoch)),
            sacrificable: true);
        placed++;
      }
      // ONE STEP FURTHER IN THE SAMPLING — per counterpart, not globally.
      // Two counterparts have different responsibility sets; a
      // shared pointer would run through equally fast for both, although
      // they get their turn unequally often (`_ernteZeiger`, B-30).
      _harvestOffset[peer] = offset + 1;
    }
    // At the next run continue where this one stopped.
    // Both pointers move by what was looked at. Separate, because
    // the active set can change between two runs and a
    // shared pointer would then point to the wrong position.
    if (active.isNotEmpty) {
      _harvestPointer = (_harvestPointer + considered) % active.length;
    }
    if (cold.isNotEmpty) {
      _coldPointer = (_coldPointer + considered) % cold.length;
    }
    _catchUpComplete(pairs.harvestPeers);
    // ── THE HORIZON ADVANCES (E5, S363) ───────────────────────────
    //
    // AFTER [_nachholAbschliessen], not before: if this run completes the
    // catch-up, the gap is now closed and the horizon may jump to
    // `jetzt`. If the line stood before, every
    // completed catch-up would cost one round of delay.
    //
    // `nachholungOffen` is the whole decision — if it stands, an unasked
    // stretch yawns between the old horizon and now, and
    // a prekey whose cells lie there must not fall.
    _horizonsAdvance(current: current, catchUpOpen: _catchUpUntil > 0);
    return placed;
  }

  /// Completes a running catch-up as soon as EVERY counterpart to be harvested
  /// is past the deepest backlog.
  ///
  /// Without this completion [_catchUpUntil] would stay, and the run would
  /// append empty catch-up tags to every counterpart until process end
  /// — expensive and without return.
  void _catchUpComplete(Iterable<String> peers) {
    if (_catchUpUntil <= 0) return;
    for (final p in peers) {
      if ((_catchUpPointer[p] ?? 1) <= _catchUpUntil) return;
    }
    log('Catch-up harvest done: all peers asked up to backlog '
        '$_catchUpUntil');
    _catchUpUntil = 0;
    _catchUpPointer.clear();
  }

  /// Where the next harvest round begins (B-30).
  int _harvestPointer = 0;

  /// Second pointer, only for the cold pairs — see the two-stage
  /// order in the harvest. A shared pointer over both ranks would run
  /// into the wrong position at every change of the active set.
  int _coldPointer = 0;

  /// How many THROTTLED harvest runs this node has already done.
  ///
  /// Only there so that a throttled run alternates the ranks
  /// (full reasoning at [harvestRank], keyword `kaltZuerst`).
  /// Unthrottled runs do NOT count: they serve both ranks
  /// anyway, and counting them would make the alternation dependent on the question
  /// of how often the queue was empty in between.
  int _throttledRuns = 0;

  /// When traffic with this counterpart last ran — sent OR
  /// harvested. Carries the two-stage harvest order.
  final Map<String, DateTime> _lastTraffic = <String, DateTime>{};

  /// How often the harvest has skipped a pair for lack of `K_AB`.
  ///
  /// Until 30.08. the skip was MUTE. In the field that made a whole
  /// identity invisibly deaf: its contacts had no founding anchor at start,
  /// so no pair key stood in the
  /// registry, so it harvested for nobody — and nothing said so.
  int pairEmptySkipped = 0;

  /// How long a pair counts as "active" after the last traffic.
  ///
  /// NOT the Secure ceiling (~1 h): after that, in a normally
  /// used account, practically every contact would be active and the rank would carry
  /// nothing. Ten minutes cover a running conversation.
  static const Duration activeWindow = Duration(minutes: 10);

  /// How far the harvest has already sampled the responsibility set per counterpart.
  /// Grows monotonically; computation is modulo the
  /// set size, which may change with the table.
  final Map<String, int> _harvestOffset = <String, int>{};

  // ══ THE CATCH-UP HARVEST (variant C, S362) ═════════════════════════════
  //
  // ── THE FINDING THAT MAKES IT NECESSARY ────────────────────────────────
  //
  // The epoch rotation ([ernteEpochenPlan]) since this
  // change reaches all 30 backlogs under which a management cell
  // can lie — but it REACHES them slowly: a counterpart is visited at
  // N = 20 contacts every `ceil(20/3) x 32 s` = 224 s, and every
  // second visit carries a deep backlog. Until every deep
  // backlog has been asked once, 56 visits = **3.5 h** pass.
  //
  // For continuous operation that is right (it costs nothing). For the
  // moment in which it matters, it is too slow: a device that
  // comes back into the network after days should find its management cells NOW
  // and not in three and a half hours.
  //
  // ── EDGE, NOT TIMER (working rule 5) ──────────────────────────────
  //
  // Triggered via `onNetworkChanged` and the return to the
  // foreground — the same edge pattern as the one-time outbox, and both
  // hooks already exist (S360). NO tick of its own: a second
  // rhythm in the egress would be recognisable from outside as such
  // (invariant 1), and a timer retry is expressly forbidden.
  //
  // ── AND NO EDGE WITHOUT ABSENCE ────────────────────────────────
  //
  // The frequent trigger is a network change WHILE operation
  // runs (WLAN after mobile, several times a day). Then there is nothing
  // to catch up, and [nachholErnte] returns after one subtraction
  // — **zero tags, zero frames**. Paid is only after an absence
  // measurable in epochs.

  /// Up to which backlog a running catch-up asks; 0 = none.
  int _catchUpUntil = 0;

  /// The next backlog not yet caught up, per counterpart.
  final Map<String, int> _catchUpPointer = <String, int>{};

  /// When the last harvest run took place — the clock of the absence.
  ///
  /// ONLY IN MEMORY — after a restart `null` stands here.
  ///
  /// **THE RESULTING GAP HAS BEEN CLOSED SINCE S363** (E5), and not
  /// by persisting THIS field, but by [ernteHorizont]: it
  /// lies with the identity, travels along in the prekey store and is read in
  /// [harvestTick] and in [catchUpHarvest] as fallback. A
  /// cold start after a long absence thus triggers the catch-up immediately
  /// instead of only after the 3.5 h rotation.
  ///
  /// This field nonetheless stays in memory, and that is intentional: it
  /// measures something else (see [ernteHorizont]) and must advance at EVERY run,
  /// even in the middle of a catch-up.
  DateTime? _lastHarvestRun;

  /// Up to where the harvest has sampled the epoch axis (E5, S363).
  ///
  /// **Not the same as [_lastHarvestRun]**, and the difference is
  /// the whole point — the juxtaposition stands at [HarvestHorizon].
  /// In short: that field measures "when did this process last run" and advances
  /// at EVERY run (even in the middle of a catch-up, otherwise the
  /// catch-up would never finish); this one measures "up to where has been asked" and
  /// stays put as long as a catch-up is open.
  ///
  /// The carrier belongs to the IDENTITY (`V41Host`), because it is stored together with the
  /// one-time prekeys — it is only kept here.
  /// An empty list means: this node runs without an identity alongside
  /// (relay operation, `bin/cleona_v41_node.dart`), and then there is also
  /// nothing whose deadline hangs on it.
  ///
  /// ══════════════════════════════════════════════════════════════════
  /// A LIST, AND THAT IS AN OWNER DECISION (V-1 = B, 08.09.2026)
  /// ══════════════════════════════════════════════════════════════════
  ///
  /// Here stood a single field, set in `attachV41` with
  /// `runtime.node.ernteHorizont = host.ernteHorizont` — i.e. PER
  /// IDENTITY against the same node. With three identities the
  /// node kept the horizon of the LAST attached one; the other two
  /// never advance and never trigger a catch-up.
  ///
  /// The obvious repair would have been a horizon PER PROCESS.
  /// The owner expressly decided against it on 08.09.2026
  /// (variant B), and the reasoning is a statement about
  /// message loss, not about tidiness: **a shared
  /// horizon does not let a rarely used identity harvest back after the restart.**
  /// The horizon of the daily used identity
  /// would then stand at "yesterday", and the cells that have been lying for three weeks
  /// for the rarely used one would never be queried — silent
  /// message loss, exactly the class that §4.6 point 3 describes.
  ///
  /// ── THE PRICE, AND WHY IT IS SMALLER THAN IT LOOKS ───────────
  ///
  /// "Harvest traffic per identity" is the assumed price. MEASURED,
  /// it does NOT arise here, and that because of the bundling: the
  /// catch-up is a quantity of the NODE (`_nachholBis`,
  /// `_nachholZeiger`), not of the identity. [oldestHorizon] takes
  /// the DEEPEST state across all identities; a single catch-up
  /// thus covers each of them. Two identities with the same state
  /// cost exactly one catch-up, three with different states
  /// likewise — the deepest wins, and the shallower ones are contained
  /// in it. The cap [kHarvestRequestsPerRun] per run stays
  /// untouched.
  ///
  /// What REALLY arises per identity is the advancing
  /// ([laufAbgeschlossenAlle]) — an assignment in memory, not a frame
  /// on the wire.
  final List<HarvestHorizon> _harvestHorizons = <HarvestHorizon>[];

  /// Registers the horizon of an identity. Admissible multiple times.
  void addHarvestHorizon(HarvestHorizon h) {
    if (!_harvestHorizons.contains(h)) _harvestHorizons.add(h);
  }

  /// Removes it again. **Mandatory on `removeIdentity`** — otherwise
  /// a removed identity would hold the catch-up of all others at
  /// its frozen state.
  void removeHarvestHorizon(HarvestHorizon h) => _harvestHorizons.remove(h);

  /// How many identities keep their horizon here. Metric of the
  /// guard.
  int get harvestHorizonNumber => _harvestHorizons.length;

  /// The DEEPEST sampled state across all identities — `null` if
  /// none has one.
  ///
  /// THE DEEPEST AND NOT THE HIGHEST: the catch-up must close the largest
  /// gap, otherwise the rarely used identity would stay put exactly
  /// as it would under a shared horizon. A
  /// horizon WITHOUT a state (`null`, never run yet) does not count —
  /// it says nothing, and no absence can be computed from "nothing".
  DateTime? get oldestHorizon {
    DateTime? oldest;
    for (final h in _harvestHorizons) {
      final b = h.sampledUntil;
      if (b == null) continue;
      if (oldest == null || b.isBefore(oldest)) oldest = b;
    }
    return oldest;
  }

  /// Advances EVERY kept horizon.
  ///
  /// OVER ALL, not over the deepest: every horizon is saved in the
  /// store of ITS identity (§21.4), and a state that does not move along
  /// there makes the same stretch be caught up again at the next start.
  void _horizonsAdvance({
    required DateTime current,
    required bool catchUpOpen,
  }) {
    for (final h in _harvestHorizons) {
      h.runCompleted(now: current, catchUpOpen: catchUpOpen);
    }
  }

  /// How many catch-up tags a run appends at most.
  ///
  /// [kMaxRealHarvestTags] = 6, i.e. EXACTLY ONE additional frame in the
  /// small network. More would be several frames for ONE counterpart and
  /// thus the whole cap [kHarvestRequestsPerRun] = 3 for a
  /// single contact — the current epoch of all others would drop out for the
  /// duration of the drain.
  static const int kCatchUpMarksProRun = kMaxRealHarvestTags;

  /// Triggers a one-off catch-up harvest if this node was away measurably
  /// in epochs (variant C).
  ///
  /// Returns the deepest backlog that is caught up — 0 if
  /// there is nothing to catch up. The return value is the metric of the
  /// guard; without it "cost nothing" could not be distinguished from
  /// "did nothing".
  ///
  /// [since] overrides the internal clock — meant for a future
  /// caller that has a PERSISTED timestamp (see
  /// [_lastHarvestRun]), and for the guard.
  int catchUpHarvest({DateTime? now, DateTime? since, String reason = 'Kante'}) {
    final current = now ?? DateTime.now().toUtc();
    // THE STORED HORIZON AS THIRD SOURCE (E5, S363). Without it
    // a network change BEFORE the first harvest run would have set the clock to `jetzt`
    // (the `letzter == null` branch below) — and thereby devalued the
    // cold-start edge in [harvestTick] before it could take effect:
    // it checks `_letzterErnteLauf == null`.
    final last = since ?? _lastHarvestRun ?? oldestHorizon;
    if (last == null) {
      // Cold start: there is no measured absence, so none
      // is claimed either. The clock starts to run.
      _lastHarvestRun = current;
      return 0;
    }
    final absentEpochs =
        current.difference(last).inSeconds ~/ kEpochSeconds;
    if (absentEpochs < 1) {
      log('Catch-up harvest ($reason): nothing to catch up — '
          '${current.difference(last).inSeconds} s since the last '
          'harvest run, that is less than one epoch ($kEpochSeconds s)');
      return 0;
    }
    // ASKING DEEPER THAN THE MANAGEMENT DEADLINE WOULD BE WASTE AND
    // BETRAYAL AT THE SAME TIME: `SecureStore.expire` throws away a management cell
    // at backlog [kManagementKeepEpochs], and a tag under
    // which provably nothing can lie only tells the asked relay
    // how long this node was away.
    final until = absentEpochs > kManagementKeepEpochs - 1
        ? kManagementKeepEpochs - 1
        : absentEpochs;
    _catchUpUntil = until;
    // FROM THE START, even if a catch-up was already running. The alternative
    // — leaving the pointer where it is — would be cheaper and wrong: after a
    // COMPLETED catch-up it would stand behind the old backlog,
    // and a new, shallower absence would no longer ask anything.
    _catchUpPointer.clear();
    log('Catch-up harvest ($reason): $absentEpochs epoch(s) away, '
        'fetching backlogs 1..$until — per peer '
        '${(until + kCatchUpMarksProRun - 1) ~/ kCatchUpMarksProRun} '
        'additional frame(s), within the existing cap '
        '$kHarvestRequestsPerRun per run');
    return until;
  }


  /// Takes [howMuch] relays from [currentSet], starting at [offset], cyclically.
  ///
  /// An empty set stays empty — the caller reports that as "no relay
  /// known", and that is a different situation from "nothing found".
  static List<EntryRecord> _sample(List<EntryRecord> currentSet, int offset,
      {int howMuch = kHarvestRelaysPerFamily}) {
    if (currentSet.isEmpty) return const <EntryRecord>[];
    final n = howMuch < currentSet.length ? howMuch : currentSet.length;
    return <EntryRecord>[
      for (var i = 0; i < n; i++) currentSet[(offset + i) % currentSet.length]
    ];
  }

  // ══ THE READ SIDE OF THE SPEED MODE (S354) ═══════════════════════════
  //
  // WHAT WAS MISSING HERE. `SpeedEgress.setRoute` and
  // `SpeedRoute.fromLiveness` together had ZERO callers in `lib/` and `bin/`;
  // `livenessTag` occurred productively exactly once, in
  // `publishLiveness` — the WRITE side. Thus `hasRoute` always returned
  // `false`, `egress.send` was dead code, and EVERY message took the
  // fallback to Secure (`send`, branch `SendMode.speed`) at `m x R`
  // cells. The log said "(124 B, speed)" and placed a
  // Secure placement next to it.
  //
  // WHAT THAT COST IN THE FIELD (29.08., measured): a delivery receipt —
  // 124 B, the cheapest thing this layer knows — cost 30
  // control frames and four minutes of egress. The V3 layer meanwhile repeats
  // its message every second (16x `L1 direct retry`), the
  // receiver acknowledges every duplicate, and each of these receipts
  // again booked 30 cells: a feedback loop across the layer boundary,
  // queue permanently at ~110/120, **441 discarded control frames**,
  // among them real placements. With a Speed route the same
  // receipt costs ONE cell.
  //
  // WHEN IT IS FETCHED (§6, E-E): "lazily when a chat is opened, not at
  // contact-add and not only on first send". It is wired exactly so —
  // [prepareSpeed] is called by the service when a chat comes into the
  // foreground, and additionally when a frame arrives from a counterpart:
  // then an answer (receipt, read confirmation) is
  // imminent, and exactly that is not to cost 30 cells again.
  // For contacts that nobody opens and from whom nothing comes,
  // nothing is fetched — that is the point of the place.

  /// For which epoch a Speed route stands (per counterpart).
  final Map<String, int> _routesEpoch = <String, int>{};

  /// The publication mark of the record from which the standing
  /// route was built (§6). Only valid together with [_routesEpoch].
  final Map<String, int> _routesMark = <String, int>{};

  /// When a younger record was last asked for, although
  /// a route already stood — as publication mark.
  final Map<String, int> _routesRefreshed = <String, int>{};

  /// How old a standing Speed route may get before at the next
  /// send a younger record is asked for (§6, S355).
  ///
  /// CALCULATED: one control cell per counterpart and window, and only
  /// while sending. Ten minutes means in a continuous conversation
  /// at most 144 cells a day per Speed contact — next to the 8100 that
  /// the harvest tick (3 per 32 s) makes anyway, that is small. The
  /// return is the upper bound for the dark time after a
  /// restart of the counterpart or of r2: before, one epoch (24 h),
  /// now this window.
  static const int kSpeedRouteRefreshSeconds = 600;

  /// Counterparts whose chat is set to Secure (§12).
  ///
  /// Only a SET, no map: the default is Speed, and a
  /// counterpart that does not stand here is Speed-capable. Thus a
  /// node that never learns the setting — lab, first contact —
  /// costs nothing but the expected behaviour.
  final Set<String> _secureOnly = <String>{};

  @override
  void setChatMode(String peer, {required bool secure}) {
    if (secure) {
      _secureOnly.add(peer);
    } else {
      _secureOnly.remove(peer);
    }
  }

  /// Which harvest request is meant for a LIVENESS instead of a message.
  ///
  /// Without this separation the answer would run into `_geerntetVon` and thus into
  /// the reassembler for messages: 96 B that are no piece of a
  /// transmission would be interpreted as such there and would occupy
  /// one of the open places.
  final Map<String, ({String peer, int epoch})> _livenessRequest =
      <String, ({String peer, int epoch})>{};

  /// How often in THIS epoch the liveness of a counterpart has already
  /// been asked for.
  ///
  /// COUNTED, NOT TICKED, and that is a decision against the
  /// more obvious variant. A throttle "at most every n slots" would have
  /// two errors: it would hang on a clock that the delivery layer does not
  /// need at all at this point (invariant 1 speaks of exactly one
  /// rhythm), and in the lab it would be ineffective or blocking, depending
  /// on whether the slot counter runs.
  ///
  /// The number is derived: the placement covers the whole
  /// responsibility set (§6, R relays), so ONE asked relay
  /// suffices. More than one is only needed if the placement was still
  /// in transit at exactly the one asked — [kLivenessAttemptsPerEpoch]
  /// attempts with moving offset cover that. Whoever asks more often
  /// pays for a counterpart that keeps silent: with twenty
  /// Speed contacts three attempts are 60 cells a day, twenty would be
  /// 400 — almost an hour of egress for nothing.
  final Map<String, ({int epoch, int attempts})> _livenessAttempts =
      <String, ({int epoch, int attempts})>{};

  /// How often per epoch and counterpart the liveness is asked for.
  ///
  /// SIX, and the number has two sides. Downwards: three were too few,
  /// re-measured in the lab — if the counterpart is only just placing its liveness
  /// (one control frame per slot), the first requests can
  /// arrive before the placement is at the asked relay. Whoever has then
  /// used up his quota gets no Speed route until the epoch change
  /// — up to 24 h on the slow path, triggered by
  /// one second of ordering.
  ///
  /// Upwards: every attempt costs a slot. With twenty
  /// Speed contacts six attempts are 120 cells a day, i.e. a good
  /// percent of all slots — the same order of magnitude as the
  /// publication itself and justifiable even when a
  /// counterpart keeps permanently silent.
  ///
  /// The quota is moreover reset at every NEW SESSION
  /// (`adopt`): a new session changes the responsibility set that
  /// this node can reach, and thereby makes an attempt sensible again
  /// that was hopeless before.
  static const int kLivenessAttemptsPerEpoch = 6;

  /// How far the liveness query has sampled the responsibility set per counterpart
  /// — the same rotation as with the harvest (S353), so that
  /// a failed attempt costs one run and not the delivery.
  final Map<String, int> _livenessOffset = <String, int>{};

  /// Fetches the liveness of [peer] if there is occasion for it.
  ///
  /// Returns `true` if afterwards a valid Speed route stands.
  ///
  /// THREE STAGES, in this order, and each saves the next:
  /// if the route for the current epoch already stands, there is nothing to do;
  /// if the record lies in the OWN placement store (this node is
  /// itself one of the responsible ones), it costs no cell; only then
  /// is asking done.
  @override
  bool prepareSpeed(String peer, {DateTime? now}) {
    final kAb = pairs.kAbFor(peer);
    if (kAb == null) return false;
    final current = now ?? DateTime.now().toUtc();
    final epoch = livenessEpoch(kAb, current);
    final markNow = livenessMark(kAb, current);

    // ── A STANDING ROUTE IS FOLLOWED UP, NOT BELIEVED (S355) ───
    //
    // Here stood `if (_routenEpoche[peer] == epoche) return true;` — whoever
    // once had a route did not ask again for the whole epoch.
    // 24 h. That would be right if a path block lived as long as its
    // epoch; it does not. It is sealed under the link key `B<->r2`,
    // and that is SESSION-BOUND (§6). If the
    // counterpart or r2 restarts, the route is dead — and the failure is
    // SILENT by design (E-83). The sender cannot notice it.
    //
    // In the field on 30.08. both directions of the same pair at the same time:
    // Bob had NO route, asked, got the fresh record —
    // four of four messages delivered, 25 to 34 s. Alice had a
    // route from 18:41, the relay restarted at 18:52 — six of six
    // messages disappeared, without a single report on her side.
    //
    // FOLLOW-UP HAPPENS ONLY WHEN SENDING and at most every
    // [kSpeedRouteRefreshSeconds]. Whoever does not send needs no route.
    // The CURRENT message does not wait for it — the route stays
    // standing and is used; the refresh is for the next one. And
    // it can make nothing worse: whether a harvested record replaces the
    // standing route is decided by the mark
    // (`livenessIstJuenger`), not by the arrival.
    final standsAlready = _routesEpoch[peer] == epoch;
    if (standsAlready) {
      final last = (_routesMark[peer] ?? 0) > (_routesRefreshed[peer] ?? 0)
          ? (_routesMark[peer] ?? 0)
          : (_routesRefreshed[peer] ?? 0);
      if (markNow - last < kSpeedRouteRefreshSeconds) return true;
      // What is noted is the ASKING, not the success: otherwise a
      // counterpart that has published nothing new would ask again at every
      // further send.
      _routesRefreshed[peer] = markNow;
    } else if (_routesEpoch.containsKey(peer)) {
      // A route from a past epoch is worse than none
      // (see `SpeedEgress.clearRoute`) — it goes before anything
      // else happens.
      egress.clearRoute(peer);
      _routesEpoch.remove(peer);
      _routesMark.remove(peer);
      _routesRefreshed.remove(peer);
    }

    // THE OPPOSITE DIRECTION IS HARVESTED (§6, like B-22 for Secure): the
    // record of the COUNTERPART lies under its outgoing direction, and
    // that is the incoming direction from here.
    final inv = pairs.inDirectionFor(peer);
    final tag = livenessTag(kAb, epoch, inv);
    for (final s in delivery.store.harvest(<Uint8List>[tag])) {
      if (_livenessAdopt(peer, epoch, s.cell)) return true;
    }

    // ── NOT THROTTLED LIKE THE HARVEST, AND THAT IS MEASURED (S354) ─────
    //
    // Here stood the same throttle as before the harvest run ("if the
    // queue is full, pause"). In the field on 30.08. it achieved exactly the
    // opposite of its purpose: the send attempt enqueues `m x R` = 60
    // placements, the queue then stood at 76, and the request for
    // the liveness — the ONE cell that ends this state — was
    // therefore never even made. In the log of `.201`: not a single
    // `Liveness` entry after sending, queue 76/86.
    //
    // The difference from the harvest is the return. A harvest request that
    // waits behind ten minutes of old load fetches a message ten minutes
    // later — it costs what it brings in. The liveness request
    // ends the cause: one cell now saves 60 per message afterwards.
    // It is therefore not paused but PULLED FORWARD
    // (`enqueueControlFirst`).
    //
    // The cap stays: `kLivenessAttemptsPerEpoch` attempts per epoch
    // and counterpart. Without it the pulling forward would be an open gate.
    //
    // COUNTED SEPARATELY (S355): the quota caps the SEARCH
    // when nothing stands at all yet. It does not fit the follow-up of a standing
    // route — it would be used up after a scant hour of
    // conversation, and after that the node would again run into the
    // silent darkness that the follow-up just ends. The follow-up
    // is instead limited by its window
    // ([kSpeedRouteRefreshSeconds]), and that above: ONE note per
    // counterpart and window, independent of the result.
    final soFar = _livenessAttempts[peer];
    final alreadyTried =
        (soFar != null && soFar.epoch == epoch) ? soFar.attempts : 0;
    if (!standsAlready && alreadyTried >= kLivenessAttemptsPerEpoch) {
      return false;
    }

    final target = livenessTarget(kAb, epoch, inv);
    final offset = _livenessOffset[peer] ?? 0;
    // THE SAME NUMBER AS THE WRITE SIDE (S381) — otherwise this
    // sample samples a set in which nothing lies. `smoke_liveness_
    // menge_symmetrisch` holds the two places against each other.
    final currentSet =
        _sample(responsibleRelays(target, count: kLivenessRelays), offset);
    if (currentSet.isEmpty) {
      log('Liveness ${_peerLabel(peer)}: no relay known '
          '(target ${_posLabel(target)}, table ${table.length})');
      return standsAlready;
    }
    _livenessOffset[peer] = offset + 1;
    if (!standsAlready) {
      _livenessAttempts[peer] = (epoch: epoch, attempts: alreadyTried + 1);
    }

    for (final relay in currentSet) {
      // DECOYS AS WITH THE HARVEST (§6, d = 3): a query that comes
      // alone names its tag. They are derived from `(Geraetegeheimnis, Tag,
      // Epoche)`, so that two queries of the same epoch cannot be told apart
      // by the change of the decoys.
      final set2 = <Uint8List>[tag];
      for (var i = 0; i < kDecoyCount; i++) {
        set2.add(SodiumFFI().hkdfSha256(pairs.deviceSecret,
            salt: tag,
            info: Uint8List.fromList(utf8.encode('liveness-decoy/$epoch/$i')),
            length: 32));
      }
      set2.shuffle();
      final id = SodiumFFI().randomBytes(kRequestIdBytes);
      final key = base64.encode(id);
      _livenessRequest[key] = (peer: peer, epoch: epoch);
      _ownRequests.add(key);
      while (_livenessRequest.length > kOwnRequestMemory) {
        _livenessRequest.remove(_livenessRequest.keys.first);
      }
      while (_ownRequests.length > kOwnRequestMemory) {
        _ownRequests.remove(_ownRequests.first);
      }
      // ONLY THE FIRST ATTEMPT JUMPS THE QUEUE.
      //
      // The priority is justified by the return: the one cell that
      // ends the Secure compulsion. This argument holds exactly once per
      // counterpart and epoch. Repetitions are follow-ups, and
      // follow-ups must not overtake — re-measured in the lab on 30.08.:
      // if EVERY attempt jumps the queue, it pushes the cold-start probe
      // behind itself, whose placement confirmation sets readiness. The
      // node thus got a route and was not allowed to use it
      // ("abgelehnt (notReady)").
      final frame = buildHarvestRequest(
          relay.lNode, relay.x25519Public, id, set2);
      // Follow-up NEVER jumps the queue: a route does stand, there is
      // nothing blocked, and the priority is justified solely by the end of the
      // Secure compulsion.
      if (alreadyTried == 0 && !standsAlready) {
        egress.stream.enqueueControlFirst(frame);
      } else {
        // Follow-up is sacrificeable: it comes again at the next send,
        // as soon as the window has expired again.
        egress.stream.enqueueControl(frame, sacrificable: true);
      }
      log('Liveness ${_peerLabel(peer)}: ask ${_posLabel(relay.lNode)} '
          '(mark ${tagLabel(tag)}, epoch $epoch, target ${_posLabel(target)})');
    }
    return false;
  }

  /// Accepts a harvested liveness record. `true` if a route
  /// resulted from it.
  bool _livenessAdopt(String peer, int epoch, Uint8List cell) {
    if (cell.length != kLivenessRecordBytes) {
      // No liveness record. No error: under the same tag
      // filler material can lie, and a relay is not obliged to deliver only
      // what is wanted.
      //
      // BUT LOGGED, and that is the difference between knowing and
      // guessing (30.08. in the field): the relay REPORTED `geerntet: 2` under
      // exactly the tag this node had asked for — and here
      // afterwards stood no line. Whether the answer never arrived, whether it had the wrong
      // size or whether the path block was no good could not be
      // decided from the logs. A silent return value at this place
      // makes exactly the question unanswerable that this is about.
      log('Liveness ${_peerLabel(peer)}: answer does not fit '
          '(${cell.length} B instead of $kLivenessRecordBytes)');
      return false;
    }
    // HERE STOOD A BYTE COMPARISON AGAINST THE OWN RECORD, and it
    // has become moot with the direction in the tag (§6, decision 2026-08-30):
    // the own one now lies under the
    // outgoing, the foreign one under the incoming direction, and only
    // the incoming direction is harvested. It does not stay "for safety" —
    // a comparison that never applies obscures, at the next reading, the
    // question of which of the two precautions actually holds.
    final r2 = Uint8List.sublistView(cell, 0, kHopIdBytes);
    // LIMIT WRITTEN OUT. Until S355 the path block ran "to the end";
    // since the record carries a mark behind it, that would be four
    // bytes too many — and `SpeedRoute` throws on a wrong length.
    final block = Uint8List.sublistView(
        cell, kHopIdBytes, kHopIdBytes + kReplyBlockBytes);
    final mark = ByteData.sublistView(
            cell, kHopIdBytes + kReplyBlockBytes)
        .getUint32(0);
    if (_sameBytes(r2, keys.lNode)) {
      // r2 would be this node itself. Then the "route" would lead in a circle:
      // the slot plan hands the cell to a partner that would pass it back
      // to us. Do not adopt — the next run finds the
      // record of a different return path.
      return false;
    }
    // ── THE YOUNGEST RECORD WINS (§6, S355) ────────────────────
    //
    // A relay APPENDS under a tag instead of replacing
    // (`SecureStore.place`), and a path block dies with the session in
    // which it was sealed. A harvest therefore delivers, after every
    // connection loss of the counterpart, the dead record NEXT TO the
    // live one, and until S355 this branch adopted unconditionally —
    // which one won was decided by the order in the answer.
    //
    // The mark is monotonic within the epoch (seconds since
    // epoch start, read from the clock). A younger record can
    // thus never carry a smaller mark than an older one, and the
    // comparison needs no state beyond the epoch.
    //
    // A TIE ADOPTS: two publications in the same
    // second are practically only the same run, and the record is then
    // the same.
    if (!livenessIsNewer(
        newMark: mark,
        newEpoch: epoch,
        previousMark: _routesMark[peer],
        previousEpoch: _routesEpoch[peer])) {
      log('Liveness ${_peerLabel(peer)}: older record discarded '
          '(mark $mark < ${_routesMark[peer]}, epoch $epoch)');
      return false;
    }
    egress.setRoute(
        peer, SpeedRoute(idOfR2: Uint8List.fromList(r2),
            replyBlock: Uint8List.fromList(block)));
    _routesEpoch[peer] = epoch;
    _routesMark[peer] = mark;
    log('Liveness ${_peerLabel(peer)}: route stands via '
        '${_posLabel(r2)} (epoch $epoch, mark $mark) — speed is open');
    return true;
  }

  /// Throws away routes whose epoch has moved on.
  ///
  /// A PATH BLOCK IS BOUND TO ITS EPOCH (`relay.dart`), and the
  /// failure is silent: r2 discards, the sender sees an accepted
  /// message. That is why the route is thrown away as soon as the epoch of the
  /// pair moves, instead of using it until the first failure —
  /// which is not there to be seen.
  void _routesMaintain(DateTime current) {
    if (_routesEpoch.isEmpty) return;
    for (final peer in _routesEpoch.keys.toList()) {
      final kAb = pairs.kAbFor(peer);
      final valid =
          kAb != null && livenessEpoch(kAb, current) == _routesEpoch[peer];
      if (valid) continue;
      egress.clearRoute(peer);
      _routesEpoch.remove(peer);
      _routesMark.remove(peer);
      log('Liveness ${_peerLabel(peer)}: route expired (epoch change) '
          '— next message goes via secure until it is renewed');
    }
  }

  /// Identifiers of the requests that this node made ITSELF.
  final Set<String> _ownRequests = <String>{};

  /// Was this answer given to our own request?
  bool isOwnRequest(Uint8List requestId) =>
      _ownRequests.contains(base64.encode(requestId));

  /// The partner that is nearer to [target] than this node.
  ///
  /// Greedy: all that counts is whether a partner lies NEARER. If none lies
  /// nearer, this node is the local minimum and the placement ends
  /// here — that is the termination condition that makes the path finite, without
  /// anyone planning a route.
  int? _nextHopToward(Uint8List target) => closerPartner(
        target,
        keys.lNode,
        [for (final c in _channels) c.peerPosition],
      );


  /// Where the remote sides of the running sessions sit (S373).
  ///
  /// ── A MAP AND NOT A SIXTH INDEX-ALIGNED LIST ──────────────────
  ///
  /// `_dropPartner` today keeps five lists that must lie index-aligned,
  /// and the comment there names exactly the error class that
  /// a sixth would have created: "Whoever removes from only one trades the
  /// crash for wrong forwarding — a quieter error class."
  /// A lookup via the channel cannot slip; with single-digit partner counts
  /// it costs nothing.
  ///
  /// CAN HAVE GAPS, and that co-decides below: a session that
  /// was taken up without an endpoint is one of which this node
  /// does not know where it sits. [lanConfined] treats that as NO.
  final Map<LinkChannel, LinkEndpoint> _partnerEndpoints =
      <LinkChannel, LinkEndpoint>{};

  /// The granted consents to suspend cover per segment
  /// (S373, §5.1 exception). The service loads and writes them; here they are
  /// only read.
  final SegmentConsentStore lanConsent = SegmentConsentStore();

  /// The segments in which this node currently sits.
  ///
  /// REFRESHED EDGE-DRIVEN, no timer (working rule #5):
  /// once at start and after that exclusively on
  /// [onNetworkChanged] — the network situation changes exactly then, and
  /// a periodic query of `NetworkInterface.list` would be a
  /// second rhythm for an answer that does not change between two
  /// network changes.
  List<LanSegment> _lanSegments = const <LanSegment>[];

  List<LanSegment> get lanSegments => _lanSegments;

  /// From where the LAN call learns which neighbours claim an internet leg.
  /// Set by `startLanEntry`; `null` means "no call
  /// active", not "no neighbours".
  Set<String> Function()? uplinkHints;

  /// How many sessions are open.
  int get partnerCount => _partners.length;

  /// What this node claims about itself in the LAN call (S373).
  ///
  /// Both bits are MEASURED statements and no configuration: the
  /// internet leg comes from the outcome of the external rendezvous
  /// (`UplinkState`, edge-driven), the passing-on from the fact that
  /// at least one session exists over which a cell can run.
  /// A node without partners claims nothing — it also can do nothing.
  int ownLanCaps() =>
      (UplinkState.instance.hasUplink() ? LanEntryService.capUplink : 0) |
      (_partners.isNotEmpty ? LanEntryService.capForwards : 0);

  /// Refreshes [lanSegments]. Called at start and on
  /// [onNetworkChanged] — nowhere periodically.
  Future<void> refreshLanSegments() async {
    _lanSegments = await currentLanSegments();
  }

  /// Does this node stand EXCLUSIVELY in a consented segment?
  ///
  /// The predicate on which the cover switch-off hangs
  /// (`CoverSaver.bindLanConfinedProbe`). Four conditions, each
  /// necessary by itself, and each falls to NO when in doubt:
  ///
  ///  1. **There are partners at all.** Without them there would be nothing
  ///     to switch off, and a `true` would be a statement about an
  ///     empty set.
  ///  2. **The endpoint of EVERY partner is known.** A partner
  ///     without an endpoint is one of which this node does not know whether
  ///     it lies in the segment — and ignorance means no here. Without
  ///     this bolt the loop below would run over an
  ///     incomplete set and find it closed.
  ///  3. **All endpoints lie in the same consented segment.**
  ///     A single remote partner keeps the full cover — it
  ///     is the path by which a cell would leave the segment, and
  ///     exactly there the §5.1 invariants would apply again.
  ///  4. **A witness of the consent is present** (`appliesTo`).
  ///     Without that everything hangs on a string that in a hotel
  ///     can be the same as at home — see `lan_segment.dart`.
  bool lanConfined() {
    if (_partners.isEmpty) return false;
    if (_partnerEndpoints.length != _channels.length) return false;
    final present = <String>[
      for (final c in _channels)
        if (c.peerPosition != null) _hexPos(c.peerPosition!)
    ];
    if (present.isEmpty) return false;
    for (final s in _lanSegments) {
      var all = true;
      for (final ep in _partnerEndpoints.values) {
        if (!addressInSegment(ep.host, s)) {
          all = false;
          break;
        }
      }
      if (!all) continue;
      if (lanConsent.appliesTo(s, present)) return true;
    }
    return false;
  }

  static String _hexPos(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// The partners of ONE direction, deduplicated (§25.4, §25.7).
  ///
  /// WHY DEDUPLICATED AND NOT SIMPLY `_channels.length`. §25.7 counts
  /// PARTNERS, not sessions: "two connections to the same node are one
  /// relay, not a redundancy pair" — the same rule by which
  /// `ReadinessTracker.verifiedRelays` computes. Two sessions to
  /// the same position are one partner; a display that counted them
  /// twice would promise redundancy that does not exist.
  ///
  /// AN ANONYMOUS SESSION COUNTS INDIVIDUALLY. If the remote side stayed anonymous
  /// (decision C, `LinkChannel.peerPosition == null`), it cannot be
  /// shown that it coincides with another — but neither
  /// that it does not. It therefore gets a session-bound
  /// identifier and counts as a partner of its own; that is the same treatment
  /// as in `ReadinessTracker.observePlaceAck`, and it is the direction
  /// that invents nothing: a session that is there is counted.
  Set<String> _partnerKeys({required bool inbound}) {
    final out = <String>{};
    for (var i = 0; i < _channels.length && i < _inbound.length; i++) {
      if (_inbound[i] != inbound) continue;
      final pos = _channels[i].peerPosition;
      out.add(pos == null ? 'session/$i' : base64.encode(pos));
    }
    return out;
  }

  /// §25.4 — partners that this node reaches ITSELF.
  ///
  /// "Carries the node's own delivery and feeds readiness." A partner
  /// to which there is a session in both directions counts in both
  /// numbers; §25.7 names the row value `both` for exactly that.
  @override
  int get syncPartnersOutbound => _partnerKeys(inbound: false).length;

  /// §25.4 — partners that reach THIS node.
  ///
  /// "States how much the node contributes for others; a precondition for
  /// inbound calls (§17)." This number does NOT feed readiness: what
  /// comes in says nothing about whether this node can place.
  @override
  int get syncPartnersInbound => _partnerKeys(inbound: true).length;

  /// §25.4 — "of which independent": the number on which `ready` hangs.
  ///
  /// Not the gross number of outgoing partners, but that of the
  /// confirmed and mutually independent relays — the same quantity
  /// from which [readinessState] arises. It stands separately alongside because
  /// §25.4 requires it separately: "This is the number `ready` hinges on
  /// (>= 2) — not the gross count."
  @override
  int get independentSyncPartners => readiness.verifiedRelays;

  /// §9.2 — how many responsible relays a Secure placement reaches TODAY.
  ///
  /// ── IT ASKS THE PLACEMENT ITSELF, NOT A SIDE QUANTITY ───────────
  ///
  /// The value falls out of [responsibleRelays] — exactly the function that
  /// [placeSecure] calls for every family (v41_node.dart, "mengen.add").
  /// It thus shares EVERYTHING that trims the set: the eligibility gate
  /// (§10.3), the requirement of a record (`entries.lookup`), the
  /// cold-start exception. A count of its own over `table.length` or
  /// `eligibility.eligibleCount` would be a PROXY — it coincides
  /// with the placement today and would diverge at the next filter,
  /// without anyone noticing.
  ///
  /// ── WHICH TARGET, AND WHY THAT WORKS ───────────────────────────────
  ///
  /// [responsibleRelays] returns `min(count, candidates that pass record and
  /// eligibility gate)`. The NUMBER thus depends on the target only via the
  /// candidate list, and without a lookup hit that is the whole
  /// table — so target-independent. The question is therefore asked with the own
  /// position: it always exists and stands in no foreign
  /// lookup cache (§11.1: the own node stands in no
  /// routing table).
  ///
  /// **WHERE IT CAN DEVIATE, openly stated:** if for a
  /// concrete tag a lookup result is available that is SHORTER than the
  /// table, the placement there places less than this number promises.
  /// The deviation thus goes in the safe direction — the estimate
  /// in the consent dialog would be too HIGH, the send thus faster than
  /// announced.
  @override
  int get reachableResponsibleRelays => responsibleRelays(keys.lNode).length;

  @override
  List<String> get lanSegmentIds =>
      <String>[for (final s in _lanSegments) s.id];

  @override
  bool lanSegmentConsented(String segmentId) =>
      lanConsent.consentFor(segmentId) != null;

  /// The positions of the neighbours that sit in [segment] NOW — the
  /// possible witnesses of a consent.
  List<String> _witnessesIn(LanSegment segment) {
    final out = <String>[];
    for (final c in _channels) {
      final pos = c.peerPosition;
      final ep = _partnerEndpoints[c];
      if (pos == null || ep == null) continue;
      if (!addressInSegment(ep.host, segment)) continue;
      out.add(_hexPos(pos));
    }
    return out;
  }

  @override
  List<String> get lanSegmentsGrantable => <String>[
        for (final s in _lanSegments)
          if (_witnessesIn(s).isNotEmpty) s.id
      ];

  @override
  bool grantLanShaping(String segmentId) {
    // ── THE WITNESSES ARE THE NEIGHBOURS PRESENT NOW ─────────────────
    //
    // What is taken is the VERIFIED position from the handshake, not the
    // address: an address is someone else in the next network, a
    // position is the hash over the static keys and implicitly authenticated in the
    // handshake. And only neighbours that REALLY sit in
    // this segment — a remote partner may not witness a
    // consent for the home network.
    final segment = _lanSegments.where((s) => s.id == segmentId).firstOrNull;
    if (segment == null) return false;
    final witnesses = _witnessesIn(segment);
    final ok = lanConsent.grant(segmentId, witnesses);
    if (ok) {
      log('LAN: cover for $segmentId suspended — consent of the '
          'user, bound to ${witnesses.length} witness(es)');
    }
    return ok;
  }

  @override
  bool revokeLanShaping(String segmentId) {
    final route = lanConsent.revoke(segmentId);
    if (route) log('LAN: consent for $segmentId revoked — full cover');
    return route;
  }

  /// WRAPPED IN A MAP, because the store keeps maps per area
  /// (`store.replaceArea` takes `Map<String, Map<String, dynamic>>`). The
  /// list itself would not be assignable there — and an area that sometimes
  /// carries a list and sometimes a map is the sort of inconsistency
  /// at which a reader later guesses.
  @override
  Map<String, dynamic> lanConsentToJson() =>
      <String, dynamic>{'segments': lanConsent.toJson()};

  @override
  void lanConsentLoadJson(Object? raw) =>
      lanConsent.loadJson(raw is Map ? raw['segments'] : null);

  @override
  set onLanConsentChanged(void Function()? cb) => lanConsent.onChanged = cb;

  /// Is a session to this position already open?
  ///
  /// One answer, one place: the same search is done by [_sessionIndexFor],
  /// from which the deduplication in [adopt] takes its index (E-119). Two
  /// loops of their own over `_channels` would be two answers to one
  /// question in neighbouring code — and the one that is later changed
  /// is then the wrong one.
  bool hasSessionWith(Uint8List position) =>
      _sessionIndexFor(position) != null;

  /// Does this node hand out its own record?
  ///
  /// E-63, "private door": being reachable and publishing oneself are
  /// two decisions. Whoever sets `false` here keeps accepting connections,
  /// but turns up in no entry set — his address then only travels
  /// in a ContactSeed. Publishing remains the normal case: a
  /// network in which holding back were the normal case could not
  /// cold-start.
  bool publishEntry = true;

  /// Whether a set request is running right now. Nobody would need two at the same time,
  /// and they cost one slot each.
  ///
  /// A CLASS AND NOT A `bool` (S376, P4-3): a lock without expiry
  /// is a bolt. Reasoning and the three situations in which the answer
  /// fails to come, in the header of `entry_set_latch.dart`.
  final EntrySetLatch setLatch =
      EntrySetLatch(timeoutSlots: entrySetTimeoutSlots);

  /// Returns up to [count] records for passing on.
  ///
  /// Drawn randomly, not the nearest: if it were always the nearest,
  /// every answer would reveal the own neighbourhood and all nodes
  /// would be pulled into the same corner.
  ///
  /// Expired ones are NOT passed on (doc Z-22) — a record that
  /// one would no longer use oneself does not belong in circulation.
  List<EntryRecord> _entrySet(int count) {
    final current = DateTime.now();
    final all = entries.all().where((r) => r.isFresh(current)).toList();
    if (publishEntry && advertisePort > 0) all.add(ownEntry);
    if (all.isEmpty) return const <EntryRecord>[];
    all.shuffle();
    final n = count < all.length ? count : all.length;
    return all.take(n).toList();
  }

  /// Asks a partner for arbitrary entry records.
  ///
  /// Self-initiated, hence via a slot.
  void requestEntrySet({int count = kMaxEntryRequestPositions}) {
    if (!setLatch.tryOpen(_slotCounter)) return;
    // SACRIFICEABLE. A set request is a repeated query: it
    // comes back by itself [entrySetEverySlots] slots later, whereas
    // a placement is the message ITSELF and is lost with it
    // (`enqueueControl`, doc). Until S376 it stood unmarked in the
    // queue and made a placement give way on overflow — measured in the field on
    // 07.09.2026 on `.201`: 120/120 frames, 180 discarded.
    egress.stream.enqueueControl(buildEntrySetRequest(count), sacrificable: true);
  }

  /// The answer is there (or failed to come) — the next one may go.
  ///
  /// CALLERS, since S376 (P4-3, before none): `delivery.onEntryResponse`
  /// on EVERY incoming answer — including an empty one, because "I have
  /// nothing" is an answer — and the expiry run in the slot driver.
  void entrySetSettled() => setLatch.settle();

  /// Tells the freshly connected partner the OWN record.
  ///
  /// Without that a partner only knows the POSITION of the remote side (from the
  /// handshake), not its address — so it could name it to nobody
  /// further, and the entry set would never grow beyond what
  /// each has found himself. Via slots, because self-initiated.
  void announceOwnEntry({bool priority = false}) {
    if (!publishEntry || advertisePort <= 0) return;
    final frame =
        fragmentFrame(LinkFrameType.control, buildEntryResponse([ownEntry]));
    // PRIORITY AT SESSION SETUP (S355). Without the own record at the
    // counterpart this node is invisible to its `responsibleRelays`
    // — there stands `entries.lookup(...) == null -> continue`,
    // and a session only delivers the position. With a full queue
    // the announcement otherwise waits a quarter of an hour, and for exactly as
    // long a LIVE partner stays out of the responsibility set,
    // while phantoms stand in it. Two frames, once per
    // session — see `enqueueFramesFirst`.
    if (priority) {
      egress.stream.enqueueFramesFirst(frame);
    } else {
      egress.stream.enqueueFrames(frame);
    }
  }

  /// Requests the entry records for known positions.
  ///
  /// SELF-INITIATED, hence via a slot — not immediately. A request
  /// is no forwarding traffic; if it went past the tick, it would be a
  /// spike (invariant 1).
  int requestEntries(List<Uint8List> positions) {
    final seen = <String>{};
    final open = <Uint8List>[];
    for (final p in positions) {
      if (entries.has(p) || _sameBytes(p, keys.lNode)) continue;
      final k = _hex(p);
      if (!seen.add(k)) continue;
      // ── ONE REQUEST PER POSITION, NOT PER ROUND (S376, P4-1) ──────
      //
      // The frame is directed and runs several hops; its answer
      // needs longer than one slot. Without this memory the
      // node would ask the same position anew every round and fill
      // its own egress with repetitions — working rule 5.
      final since = _openEntryRequests[k];
      if (since != null && _slotCounter - since < entrySetTimeoutSlots) {
        continue;
      }
      open.add(p);
      if (open.length >= kEntryRequestsPerRound) break;
    }
    if (open.isEmpty) return 0;
    final sodium = SodiumFFI();
    for (final p in open) {
      _openEntryRequests[_hex(p)] = _slotCounter;
      // SACRIFICEABLE: an acquisition request comes back by itself
      // (`_entryFetchTick`), whereas a placement is the message ITSELF
      // and is lost with it.
      egress.stream.enqueueControl(
          buildEntryRequest(p, sodium.randomBytes(kRequestIdBytes)),
          sacrificable: true);
    }
    _expireEntryRequests();
    return open.length;
  }

  /// Positions whose record is currently asked for — slot of the question.
  final Map<String, int> _openEntryRequests = <String, int>{};

  /// Positions that the responsibility computation missed.
  ///
  /// ── WHY REMEMBERED AND NOT ASKED IMMEDIATELY (S376, P4-1) ────────────
  ///
  /// [responsibleRelays] runs per family and per tag, i.e. in the
  /// send path several times per message. Enqueuing a frame from there
  /// would mean flooding the egress with acquisition requests
  /// (working rule 5). So it is only remembered, and the slot driver
  /// asks on the tick — [entryFetchEverySlots].
  ///
  /// CAPPED, because a foreign lookup answer can fill the set.
  ///
  /// ONE structure, not two: the key is the hex position, the
  /// value the position itself. An additional `Set` next to it would be
  /// the same statement in two places, and the one that is later changed
  /// is then the wrong one.
  final Map<String, Uint8List> _missedRecords = <String, Uint8List>{};

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// Remembers that the record for this position is missing.
  void _miss(Uint8List position) {
    if (_missedRecords.length >= kMaxMissingEntries) return;
    _missedRecords[_hex(position)] = Uint8List.fromList(position);
  }

  void _expireEntryRequests() {
    _openEntryRequests.removeWhere(
        (_, since) => _slotCounter - since >= entrySetTimeoutSlots);
  }

  /// Asks on the tick for the records that the responsibility is missing.
  ///
  /// CALLER of [requestMissingEntries], which had none until S376.
  ///
  /// ── WHAT THIS COSTS IN THE STEADY STATE (working rule 5) ────────────────
  ///
  /// As long as something is missing, this keeps running: [responsibleRelays] enters
  /// the same position again as soon as it is needed again. The
  /// upper limit is therefore not "until it works", but the calculation
  /// [kEntryRequestsPerRound] = 2 frames per [entryFetchEverySlots] = 8
  /// slots, i.e. **0.25 frames per slot** — at `kSlotInterval` = 8 s one
  /// request every 32 s, in the same order of magnitude as the harvest. The
  /// lock [_openEntryRequests] pushes it down further: the same position
  /// is only asked again after [entrySetTimeoutSlots] = 16 slots.
  /// All requests are `opferbar` and give way first on overflow.
  ///
  /// A give-up rule ("stop asking after N failed attempts") would be
  /// ineffective here and therefore does not stand here: [_miss] enters the
  /// position again immediately at the next need. Whoever wants to be rid of it
  /// must take it out of the routing table, not out of this
  /// marker.
  int _entryFetchTick() {
    if (partnerCount == 0) return 0;
    return requestMissingEntries();
  }

  /// Asks for what the responsibility misses and the supply does not have.
  ///
  /// ── IT HAD NO CALLER UNTIL S376 (P4-1) ──────────────────────
  ///
  /// Built, measured, untrodden — the same class that has hit this migration
  /// several times. Now [_entryFetchTick] calls it on the tick.
  ///
  /// ON DEMAND, NOT AS A PRECAUTION — and that is a cost calculation.
  ///
  /// Only [_missedRecords] are asked for, i.e. what
  /// [responsibleRelays] just had to throw out because no record
  /// was available. §11.1 says exactly that: "fetched on demand".
  ///
  /// The obvious second source — "the nearest of the routing table
  /// without a record", as a precaution — is DELIBERATELY NOT in. It would be
  /// not rare but the steady state: `peerAnnounce` brings
  /// POSITIONS, not records, so every node always has some
  /// without. The acquisition run would thus fire on every tick, i.e.
  /// [kEntryRequestsPerRound] frames every [entryFetchEverySlots] slots
  /// without occasion — a quarter of the egress for stockpiling (working rule 5).
  /// Measured: `smoke_v41_node` turned red from it, because the
  /// control queue never became empty again.
  ///
  /// The precautionary part does not go away with this, it only gets an
  /// occasion: the status line calls `reachableResponsibleRelays`, i.e.
  /// [responsibleRelays] on the OWN position — and what is missing there
  /// is missed and fetched.
  int requestMissingEntries() {
    final n = requestEntries(_missedRecords.values.toList());
    // What the supply has meanwhile no longer needs to be missed.
    _missedRecords.removeWhere((_, p) => entries.has(p));
    return n;
  }

  bool _learn(Uint8List position) {
    final before = eligibility.ageOf(position) != null;
    // ONLY A SIGHTING, NO EVIDENCE (S376, P4-2). Pure
    // BOARD KNOWLEDGE also lands here: `entries.onRemembered` hangs on the supply, and the
    // entry cascade writes into it what stood on a public
    // rendezvous board. Whoever computes age from that can be fooled with
    // two board placements ten days apart into a "standing fleet"
    // that has not run for a second. The evidence comes from
    // [_belegeArbeit], and only from there.
    eligibility.note(position, nodeEpochNow());
    if (!before) {
      table.insert(KnownNode(position));
      return true;
    }
    return false;
  }

  /// "This position has provably worked in this epoch."
  ///
  /// §22.7 "evidence, not acquaintance", §10.3 "continuously paid-for
  /// fleet". There are exactly two pieces of evidence, and both cost the counterpart
  /// uptime:
  ///
  ///   * a session that CAME ABOUT ([adopt]) — the handshake
  ///     proves the static key for exactly this `L_node`, and
  ///     that now;
  ///   * an AUTHENTICATED placement receipt ([_placeAck], behind
  ///     `verifyPlaceAck`) — the MAC only holds under the `ss` from the
  ///     placement seal, which only sender and target relay have.
  ///
  /// An unauthenticated receipt is expressly NO evidence; exactly that
  /// already once fraudulently obtained `ready` in S357.
  void _proofsWork(Uint8List position) =>
      eligibility.credit(position, nodeEpochNow());

  /// Announces a LIMITED, random selection of known nodes.
  ///
  /// Via the slot, not immediately: this is self-initiated traffic
  /// (see `CellTransport.emitControl`).
  void announcePeers({int sample = 8}) {
    final all = table.closest(keys.lNode, count: sample * 4);
    if (all.isEmpty) return;
    all.shuffle();
    final selection = all.take(sample).map((n) => n.position).toList();
    egress.stream.enqueueControl(buildPeerAnnounce(selection));
  }

  int? _partnerFor(Uint8List hopId) {
    // The assignment hop identifier -> partner now comes from the session
    // itself: whoever identified himself in the handshake and was known
    // carries a verified position (decision C). Before, this was a
    // stub, because `LinkChannel` yielded no identity at all — forwarding
    // was only possible over connections that this node had set up
    // itself.
    //
    // It is NOT unverified: had the remote side lied, it would have
    // a different key and could open nothing that we
    // send it. Forwarded to an impostor means discarded.
    for (var i = 0; i < _channels.length && i < _partners.length; i++) {
      final pos = _channels[i].peerPosition;
      if (pos != null && _sameBytes(pos, hopId)) return i;
    }
    return null;
  }


  /// Drops an ended session.
  ///
  /// WHY THIS MUST EXIST. Until S348 `adopt` inserted into four lists
  /// and there was NO way back — `grep '_partners.remove'` found nothing.
  /// A closed channel remained a partner, the next slot drew it, and
  /// `UdpLinkChannel.send` deliberately throws on a closed channel
  /// (`link_demux.dart:112-123`: swallowing such a call
  /// "conceals exactly the error class one wants to see" — right).
  /// The throw ran from a timer callback up into the zone handler of the
  /// daemon, and that does not classify it as survivable
  /// (`service_daemon.dart`) — so `exit(99)`. With a cover tick of
  /// 1/8 s that meant: EVERY connection loss killed the node within
  /// eight seconds. In the field on 25.08. several times on node 2 and relay 2.
  ///
  /// WHERE THE REPORT COMES FROM. The channel closes its input stream at the end
  /// (`link_demux.dart:150`). `onDone` is thus the
  /// notification that existed all along and that nobody took —
  /// it needs no second callback and no change to the demux.
  ///
  /// ALL FIVE LISTS TOGETHER. `_channels`, `_partners`, `_inbound`,
  /// `egress.partnerLinkKeys` and `_subs` lie index-aligned, and
  /// `DeliveryNode` checks in the constructor `partners.length ==
  /// partnerLinkKeys.length`. Whoever removes from only one trades the
  /// crash for wrong forwarding — a quieter error class.
  /// The line of the caller of [_dropPartner], shortened to `file:line`
  /// — see the reasoning there.
  static String _dropCaller() {
    final lines = StackTrace.current.toString().split('\n');
    // 0 = _dropAufrufer, 1 = _dropPartner, 2 = the caller
    for (var i = 2; i < lines.length && i < 7; i++) {
      final m = RegExp(r'\(([^)]*\.dart):(\d+)').firstMatch(lines[i]);
      if (m == null) continue;
      return '${m.group(1)!.split('/').last}:${m.group(2)}';
    }
    return 'unbekannt';
  }

  void _dropPartner(LinkChannel channel) {
    final i = _channels.indexOf(channel);
    if (i < 0) return;
    // FIRST, and that before the `return`-less rest: as long as the endpoint
    // of a dropped partner stayed,
    // `_partnerEndpoints.length != _channels.length` would be permanently violated
    // and `lanConfined()` permanently `false` — the switch-off would be dead after
    // the first connection loss, without anyone noticing.
    _partnerEndpoints.remove(channel);
    _channels.removeAt(i);
    // NO reassembler per session any more — see `_speedZusammensetzer`.
    // Half-finished transmissions deliberately stay: the second piece
    // can arrive via a DIFFERENT session, and throwing exactly that away with the
    // session was the error.
    _partners.removeAt(i);
    _inbound.removeAt(i);
    egress.partnerLinkKeys.removeAt(i);
    unawaited(_subs.removeAt(i).cancel());
    // THE EVIDENCE FALLS WITH THE SESSION (§22.7). Until S357 nobody called this
    // line: `forgetPartner` had no caller in the whole tree,
    // and a node whose relays vanished without a word
    // reported `ready` for all eternity.
    readiness.forgetPartner(i);
    // AND THE REMEMBERED RETURN PATHS. They hang on the same
    // partner number, and those move up when removed from the list —
    // without this they would afterwards point to a foreign neighbour, and the
    // dropped one would have kept its share of the cap occupied until the deadline
    // expired.
    delivery.pending.forgetPartner(i);
    // AND THE REPORT TO THE OUTSIDE. Until S372 ONLY the line to the log stood
    // here: the descent `ready` -> `connecting` never reached
    // `onReadinessChanged` and thus no display surface (§25.4:
    // "The badge mirrors the readiness state 1:1"). Measured in the field —
    // the node fell at 10:21:58, the UI still showed "Bereit" 11.5 minutes
    // later.
    _reportReadiness(() => 'Session dropped');
    egress.syncPartnerCount();
    // -- WHO DROPS THE SESSION (S381, 11.09.2026) --------------
    //
    // The line so far only named THAT a session fell. On 11.09.2026
    // measured on an EMPTY node: 50 aborts in ten minutes,
    // two partners alternate. Every abort changes the
    // link key to the return-path partner, and with it
    // `publishLiveness` rightly places anew — measured 32 placements each time,
    // i.e. about 32 frames per minute against an outflow of 7.5. The
    // control queue then stood at 119/122, the harvest was
    // paused, no Speed route came about, and the
    // contact answer (`1a.04`) stayed stuck at two of five pieces.
    //
    // The path there could NOT be read from the logs: `onDone`,
    // `onNetworkChanged`, E-119 and `trennePartner` all end in
    // the same line. That is why the caller now stands alongside — the same
    // technique that a day earlier answered the question of who fills the
    // control queue (`cover_stream.dart`).
    log('Session ended — partner removed (${_partners.length} '
        'remaining, by ${_dropCaller()})');
  }

  /// The network has changed — WLAN to mobile, cable pulled, new
  /// address from the router.
  ///
  /// ── WHY THIS NEEDS AN ACTION AND DOES NOT HEAL BY ITSELF ─────
  ///
  /// Until S360 the delivery layer learned NOTHING of a network change.
  /// `CleonaService.onNetworkChanged` refreshed a local address list,
  /// reported it to the rendezvous and shortened a backoff — and the
  /// V4.1 node ran on unchanged. Three things stayed wrong in the process,
  /// each by itself sufficient to make the node mute:
  ///
  ///  1. **The sessions.** They point to addresses in the old network. The
  ///     link layer clears a session after one hour of silence —
  ///     but only when a datagram arrives (`LinkDemux._expire` runs
  ///     `afterMacCheck`). On a dead network none arrives. The
  ///     sessions would thus stand indefinitely, `partnerCount` would stay full,
  ///     and the partner policy would see no reason to dial anew: the
  ///     node holds four partners, none of which exists any more.
  ///  2. **The observed addresses.** See
  ///     `ObservedAddressBook.clearAll` — a unanimously wrong
  ///     §17.3 candidate.
  ///  3. **The own announcement.** The entry record carries the address
  ///     of the old network; whoever harvests it dials into the void. That is
  ///     the same error class as the loopback announcement of 25.08.
  ///     (S349) — the record was formally fine and pointed to
  ///     nothing. This third part is done by the caller, because only he
  ///     knows the dialable addresses (`v41_attach.dart`); here goes
  ///     what the node itself holds.
  ///
  /// WHAT DELIBERATELY STAYS: the entry supply ([entries]). It is
  /// step 1 of the cascade, and a record from the network remains valid —
  /// a node in the internet is the same from both networks. Throwing it
  /// away would mean starting at step 2 after every change.
  ///
  /// WHAT IT COSTS: re-dialling the partners is traffic, and it
  /// arises bundled. That is unavoidable — the old paths are
  /// gone — and it is the same traffic as at the start of the node, so
  /// no new pattern for an observer.
  void onNetworkChanged({String reason = 'Netzwechsel'}) {
    final before = _channels.length;
    // FIRST THE COPY, then drop: `_dropPartner` shrinks the
    // list that is being iterated here.
    for (final c in List<LinkChannel>.of(_channels)) {
      // Order: first take out of the five index-aligned lists
      // (`_dropPartner` cancels the subscription in doing so), then close the
      // channel. The other way round `close()` would run into the `onDone` branch, and
      // `_dropPartner` would run twice — the second time on an index
      // that meanwhile belongs to another partner.
      _dropPartner(c);
      unawaited(c.close());
    }
    host.observed.clearAll();
    // ── AND THE MEMORY OF THE DIAL LADDER (E-89, S376) ────────────
    //
    // `host.connectState` remembers per target the last successful rung.
    // Whether a rung holds is decided by the LOCAL network — a network that
    // blocks UDP is the reason for a `tcpOwnPort` hint, not the
    // target. Behind the change it no longer applies, just like the
    // observed addresses one line higher. A hint left standing
    // would not be dangerous (the cascade continues after the
    // remembered rung, it costs at most one attempt), but
    // it would be a statement about a location that no longer exists.
    host.connectState.clear();
    // ── AND THE FOREIGN EVIDENCE (S376, finding 3) ─────────────────────────
    //
    // The session evidence fell one line higher with the sessions
    // (`_dropPartner` -> `ReadinessTracker.forgetPartner`). The
    // evidence of relays WITHOUT a session of their own was the only one to stay —
    // with a deadline of one hour. A node then stood at zero
    // partners for up to 60 minutes on `ready`: display green, Speed path
    // open, and the readiness edge did not fire, so neither did
    // the drain of the local outbox run (§21.2, gap G-4). The
    // fall back then came silently on mere reading.
    //
    // They say "at THIS relay placement is possible" — a statement
    // about the old network, because the path there led via partners
    // that no longer exist. The same reasoning as for the
    // observed addresses (point 2) and the inbound proof below;
    // §22.7.2 "live state governs".
    readiness.forgetRemote();
    // ── AND THE INBOUND PROOF (S4/S373) ──────────────────────────────
    //
    // It is a statement about THIS network: "from outside someone arrives
    // here". Behind a network change it no longer applies — the same
    // reasoning as for the observed addresses one line higher
    // (point 2 in the header) and as for the own announcement (point 3). A
    // node that kept it across the change would keep placing on the global board
    // in the new network and point to nothing there.
    //
    // [portMappingConfirmed] falls ALONG for the same reason: a promise
    // of the old router does not apply in the new network. Whoever sets the mapping
    // (package `s373-portmapping`) creates it anew in the new network; until
    // then the inbound proof carries.
    final proofBefore = externalInboundProven || portMappingConfirmed;
    portMappingConfirmed = false;
    externalInboundProven = false;
    // ── AND THE LAN SITUATION (S373) ──────────────────────────────────────
    //
    // The network change IS the edge at which the segments change —
    // the only one. Until the refresh is through, the old prefixes stand in
    // `_lanSegmente`; that is harmless, because
    // `lanConfined()` already returns `false` anyway (all sessions
    // fell one line further up, `_partners` is empty). The
    // cover is thus full during the change, and that is the
    // right direction.
    unawaited(refreshLanSegments());
    log('$reason: $before session(s) dropped, observed addresses '
        'forgotten${proofBefore ? ', entry proof expired' : ''} — '
        'the partner choice dials anew');
    // AFTER dropping and AFTER `forgetRemote`, otherwise the
    // reporter would report a state that no longer applies one line later.
    // `_dropPartner` has already reported per session above; the call here
    // catches the rest — above all the case in which no session at all
    // stood and the foreign evidence alone carried readiness.
    _reportReadiness(() => 'Network change: foreign proofs discarded');
    // ── AND THE CATCH-UP HARVEST (variant C, S362) ──────────────────────
    //
    // A network change is the edge behind which a device was often away
    // longer than an epoch lasts — flight mode, dead zone, switched off
    // overnight. The rotation would find the management cells left lying
    // meanwhile only after hours.
    //
    // FREE OF CHARGE IN THE FREQUENT CASE: if the node was away less than one
    // epoch — the ordinary WLAN/mobile change during operation —
    // the call returns without a single tag.
    catchUpHarvest(reason: reason);
  }

  /// To which running session does [position] belong? `null` if none.
  ///
  /// Searches via the VERIFIED position, not via the endpoint: the same
  /// node can be reachable under two addresses (dual-stack, §17.3),
  /// and two endpoints are then nonetheless one partner (§25.7: "two
  /// connections to the same node are one relay, not a redundancy pair").
  int? _sessionIndexFor(Uint8List position) {
    for (var i = 0; i < _channels.length; i++) {
      final p = _channels[i].peerPosition;
      if (p != null && _sameBytes(p, position)) return i;
    }
    return null;
  }

  /// Puts a session into operation.
  ///
  /// [peer] is the endpoint of the remote side (S373). It is
  /// PASSED IN and not taken from [channel]: `LinkChannel` deliberately
  /// does not keep it — the interface passes inner frames through
  /// and knows no target. Both real channels (`UdpLinkChannel`,
  /// `TcpLinkChannel`) carry it as `peer`, and the three callers
  /// of this method know it anyway; adding it to the interface
  /// would have extended thirteen test dummies without
  /// any of them being able to answer it.
  ///
  /// `null` is admissible and means "endpoint unknown" — [lanConfined]
  /// evaluates that as NO and leaves the cover standing.
  void adopt(LinkChannel channel, {required bool inbound, LinkEndpoint? peer}) {
    // A verified remote side goes into the routing table — it is
    // reachable, and that is exactly what the table records. It does not
    // make it eligible (E-B), it only starts to run in.
    final pos = channel.peerPosition;

    // ── E-119: SIMULTANEOUS OPEN ─────────────────────────────────
    //
    // WHAT CAN HAPPEN. If two nodes dial each other at the same time,
    // TWO sessions stand between the same pair. On UDP that is prevented by
    // E-113 (the waiting mark of the demux), and on the LAN it is prevented by
    // [shouldDial], by not letting both dial in the first place. Both take effect
    // however only on DIALLING. They do NOT take effect when two paths
    // meet — a LAN call and a supply call at the same time
    // —, and on `tcpOwnPort` E-113 fundamentally does not take effect: the
    // lookup of the mark runs via the source endpoint
    // (`link_demux.dart`, `origin.key`), and an incoming
    // TCP connection carries an EPHEMERAL source port, never the data port
    // that the initiator dialled. The mark stands under
    // `A:Datenport`, the event comes under `A:ephemer`.
    //
    // WHAT IT COSTS, CALCULATED. No extra bandwidth: the cover stream
    // carries one cell per time slice for the WHOLE node, and
    // `CoverStream.drawInterval()` draws without partner count
    // (`cover_stream.dart`). It costs a REDISTRIBUTION: the plan draws
    // uniformly over the ENTRIES (`drawPartner()` -> `_partners`,
    // not over deduplicated neighbours), so the doubled neighbour gets at
    // P = 4 2/5 = 40 % instead of 25 % and every other 1/5 = 20 % —
    // **minus 20 % to every other neighbour**. READINESS is
    // not affected, it hangs on `Partition.independentCount`
    // (§22.5.1), not on this number. And the state does not heal by
    // itself: both sessions see traffic and keep each other
    // above the idle period of one hour
    // (`LinkDemux.sessionIdleLifetime`).
    //
    // THE RULE, WITHOUT ARRANGEMENT. The session that CARRIES is the one that the node
    // with the smaller position dialled — the same order by
    // which [shouldDial] decides on the LAN, and the same axis as
    // E-113 on UDP. Both sides know both positions and compute for
    // themselves the same result, without exchanging a message about it:
    //
    //   * `shouldDial(pos) == true`  -> my position is smaller, so
    //     MY outgoing session carries; the incoming one falls.
    //   * `shouldDial(pos) == false` -> the remote side is smaller, so
    //     its one carries — for me the INCOMING one; my outgoing one falls.
    //
    // The remote side computes the same line with swapped roles and
    // closes THE SAME connection.
    //
    // WHAT IT NEVER DOES. It does not touch a SINGLE session — without a
    // hit in [_sessionIndexFor] nothing runs from here. And it does not touch
    // ANONYMOUS sessions (`peerPosition == null`): that two
    // of them coincide cannot be shown, and what cannot be
    // shown is not closed (the same direction as
    // [_partnerKeys], which counts them individually).
    //
    // SAME DIRECTION means: the older one carries. That is no case from
    // E-119 (there both sides dial, so the directions are
    // different), but the remainder — twice outgoing to the same
    // position can only arise if a caller dialled past
    // [hasSessionWith]. Keeping the older one is
    // the choice that does not touch operation.
    if (pos != null) {
      final old = _sessionIndexFor(pos);
      if (old != null) {
        final keepIncoming = !shouldDial(pos);
        final newCarries =
            _inbound[old] != inbound && inbound == keepIncoming;
        final who = pos
            .take(6)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        if (newCarries) {
          // FIRST OUT OF THE FIVE LISTS, THEN CLOSE — the same
          // order as in [onNetworkChanged]. The other way round
          // `close()` would run into the `onDone` branch and `_dropPartner` a
          // second time, the second time on an index that
          // meanwhile belongs to another partner.
          final route = _channels[old];
          log('E-119: second session to $who… — the '
              '${_inbound[old] ? 'inbound' : 'outbound'} one drops, '
              'the ${inbound ? 'inbound' : 'outbound'} one carries');
          _dropPartner(route);
          unawaited(route.close());
        } else {
          log('E-119: second session to $who… — the existing '
              '${_inbound[old] ? 'inbound' : 'outbound'} one carries, '
              'the new one drops');
          unawaited(channel.close());
          // NO `announceOwnEntry` and no `probePlacement` from here:
          // this session does not go into operation, and both would cost
          // slots for nothing (working rule 5).
          return;
        }
      }
    }

    if (pos != null) {
      _learn(pos);
      // A SESSION IS EVIDENCE (S376, P4-2). It stands behind the
      // handshake, i.e. behind the static key for exactly this
      // position — unlike everything that merely comes in via a record.
      _proofsWork(pos);
    }
    announceOwnEntry(priority: true);
    if (peer != null) _partnerEndpoints[channel] = peer;
    _channels.add(channel);
    _inbound.add(inbound);
    egress.partnerLinkKeys.add(channel.deliveryKey);
    final transport = CellTransport(
      channel: channel,
      linkKey: channel.deliveryKey,
      blockLookup: _blockLookup,
    );
    _partners.add(transport);
    egress.syncPartnerCount();
    _subs.add(channel.inbound.listen((inner) {
      // DETERMINE THE INDEX ONLY NOW. Earlier it was captured at creation
      // — after the first `_dropPartner` this number pointed
      // to a foreign partner, and incoming cells would have been attributed to the
      // wrong session. The list is short (partners
      // in the single digits), the lookup costs nothing.
      final idx = _partners.indexOf(transport);
      if (idx < 0) return; // already dropped
      for (final a in delivery.receive(idx, inner)) {
        // DO NOT log every cell. The cover stream delivers at
        // R_cover = 1/8 s about 10 800 cells a day PER PARTNER, and
        // the vast majority are dummies — one entry per cell would be a
        // log file that grows faster than anything else on the node, and
        // on top of that it would reveal in the file exactly the timing pattern that
        // is hidden on the wire.
        if (a.what == 'for me or unknown') {
          _uninteresting++;
          continue;
        }
        log('Partner $idx: $a');
      }
    }, onDone: () => _dropPartner(channel)));
    // Whether the remote side was recognised belongs in the log — it decides
    // whether forwarding over this session is possible. Only the first
    // bytes: the whole position would be an unnecessarily lasting trace.
    final who = pos == null
        ? 'anonym'
        : 'recognised ${pos.take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}…';
    log('Session ${_partners.length} in operation — counterpart $who');

    // COLD START: as long as the evidence is not COMPLETE, every
    // new session becomes the occasion for a probe. Not periodically — there is
    // nothing to repeat as long as nothing has changed; a new
    // session IS the change.
    //
    // ── HERE STOOD `== Readiness.searching` (S373, measured) ──────────
    //
    // With the reasoning "from `connecting` on the evidence is available". It was
    // not available: `connecting` is ONE confirmed relay, `ready`
    // requires two (`readiness.dart`, `state`). The probe is the
    // only way to actively produce a confirmation — `probePlacement`
    // has exactly one caller in `lib/`, this one —, and it was switched off exactly
    // when one was still missing. `connecting` thus had
    // no drive of its own and waited passively for foreign traffic.
    //
    // Measured on 07.09.2026 in the lab network, Node1: `ready -> connecting`
    // at 10:21:58 (session fell), after that for 52 minutes not a
    // single placement confirmation. The node only got free when it had
    // dropped to ZERO relays and the old condition took effect again
    // (`searching -> connecting` 11:14:16) — from there it was `ready` in 24
    // seconds. Node2 hung for the same reason 1 h 38 min in
    // `connecting` and only got out through a random foreign receipt.
    // From the WORSE state the node recovered in
    // half a minute, from the better one it needed an hour; that
    // is the signature of this error.
    //
    // `ready` stays the exception, and there it is factually right:
    // two relays are confirmed, further filler cells buy nothing.
    // The trigger stays the new session, so still
    // edge-driven — no timer, no polling (working rule #5).
    //
    // COSTS, calculated: `probePlacement` passes at most
    // [kDeliveryFamilies] cells via `enqueueControl` into the
    // control queue. The slot tick hands out unchanged exactly one
    // byte-identical cell per slot — NO additional
    // traffic arises, only queue occupancy (invariant 1 untouched). For
    // comparison: a single text message without a Speed route enqueues 60
    // placements (`cover_stream.dart`).
    if (readiness.state != Readiness.ready) {
      probePlacement();
    }

    // LIVENESS NEEDS A PARTNER — before that there is no r2 and thus
    // no return path. A new session is therefore exactly the moment in
    // which the record can change. `publishLiveness` had no caller at all
    // in `lib/` until S348; it only ran in the
    // lab program.
    //
    // STILL OPEN, and that belongs here instead of in a footnote: the
    // epoch refresh. §6 binds the tag to the epoch, so a
    // record ages with it. Here publishing only happens on a session change
    // — whoever runs longer than an epoch without a new session
    // becomes invisible to new senders.
    final laid = publishLiveness();
    if (laid > 0) {
      log('Liveness: $laid placement(s) queued — return path published');
    }

    // AND THE ASKING QUOTA IS FREED. A new session changes which
    // responsible relays this node can reach at all; an
    // attempt that previously ran into the void can hit now. Without this
    // line a node that has used up its quota in the cold start
    // would stay on the Secure path until the epoch change — see
    // [kLivenessAttemptsPerEpoch].
    _livenessAttempts.clear();
  }

  /// To which link does this path block belong? As long as this node keeps no
  /// assignment, it tries nothing — it is then simply not r2.
  /// Resolves the path block by trying (decision (a)).
  Uint8List? _blockLookup(Uint8List block, int epoch) =>
      blockResolver.resolve(block, epoch);

  /// Dials from the SUPPLY until enough partners stand (§11.3).
  ///
  /// ── WHY THIS MUST STAND ON ITS OWN (B-28, S349) ────────────────────────
  ///
  /// The cold-start cascade FILLS the supply — it dials nobody.
  /// On 28.08. in the field: the phone fetched **18 entry records** from
  /// the external rendezvous and nonetheless set up **zero** sessions.
  /// Dialling lay solely in the LAN path (`lan_entry_wiring`), and that
  /// got to see not a single call in the guest WLAN.
  ///
  /// **`shouldDial` does NOT apply here**, and that is the difference from the
  /// LAN. There both sides hear each other at the same time and must agree
  /// on who dials — otherwise two connections stand. On
  /// entry via a supply the other side has **never seen** us;
  /// whoever waits for the other here waits forever. The one entering
  /// dials, full stop.
  ///
  /// Capped by [PartnerPolicy]: dialling only happens as long as
  /// partners are missing. Every call costs packets (working rule 5).
  ///
  /// Returns how many calls were triggered.
  ///
  /// ── FROM WHICH HEAP THE CHOICE IS MADE (B-33, S350) ───────────────────
  ///
  /// Until here the loop ran over `entries.all()`, i.e. over the
  /// INSERTION ORDER of the supply — after a cold start that is the
  /// order in which four Nostr relays answered. On 29.08.
  /// at 12:26:48 the phone thus fetched **86 records** and dialled the
  /// first of them. The cap took effect, the SELECTION did not: if of 86
  /// only the three youngest were alive, four attempts would hit a live node
  /// at all with about 13.5 %.
  ///
  /// Now [EntryCache.dialCandidates] draws: never-failed ones first,
  /// within those the younger publication, within that randomness (RL-1). And every
  /// attempt is BOOKED — three failed attempts throw the record out of
  /// the supply.
  /// Puts neighbours that claim an internet leg at the FRONT (S373).
  ///
  /// ── HOW A LAN CLIENT FINDS ITS RELAY INSTEAD OF GUESSING IT ───────
  ///
  /// A node without an internet leg of its own — the tablet in the WLAN behind
  /// a router that only one device passes — only gets out via a
  /// neighbour. Until S373 the dialling order was that of the
  /// supply, i.e. effectively random: it took whomever it found first, and
  /// never noticed that another neighbour would have been the better path.
  ///
  /// ── IT IS AN ORDER, NOT A SELECTION ─────────────────────────
  ///
  /// And that is its whole scope. No candidate drops out, none is
  /// added, the number of dial attempts (`max`) and the
  /// partner upper limit (`policy.target`) are untouched, and not a
  /// single additional packet goes out (working rule #5).
  /// In particular this creates NO "designated relay" in the sense of
  /// §11.3: who carries the delivery is still decided solely by the
  /// responsibility computation (§9.1), and that does not know this hint.
  /// A neighbour that lies here draws one dial attempt onto itself —
  /// it cannot gain more.
  ///
  /// ── ONLY IF THIS NODE ITSELF HAS NONE ───────────────────────
  ///
  /// Whoever already gets out needs no relay, and a pre-sorting
  /// would push him without return onto the same neighbours as everyone else
  /// — a concentration that benefits nobody.
  List<EntryRecord> _withRelayPriority(List<EntryRecord> candidates) {
    if (UplinkState.instance.hasUplink()) return candidates;
    final hints = uplinkHints?.call();
    if (hints == null || hints.isEmpty) return candidates;
    // Split STABLY, not sorted: within both halves the
    // order of the supply is preserved. A `sort` with a
    // bool key would be allowed to rearrange it, and then the
    // dialling order would hang on the implementation instead of on the intention.
    final front = <EntryRecord>[];
    final rest = <EntryRecord>[];
    for (final r in candidates) {
      (hints.contains(r.host) ? front : rest).add(r);
    }
    if (front.isEmpty) return candidates;
    log('Entry: ${front.length} neighbour(s) with internet leg first — '
        'this node has none itself');
    return <EntryRecord>[...front, ...rest];
  }

  Future<int> dialFromEntries({int max = 4}) async {
    var chosen = 0;
    final current = DateTime.now();
    // First clean up, then choose: what has expired should not even
    // come into the candidate list.
    final expired = entries.expire(current);
    if (expired > 0) {
      log('Entry: $expired expired record(s) discarded');
    }
    final candidates = _withRelayPriority(entries.dialCandidates(now: current));
    log('Entry: ${candidates.length} of ${entries.size} records '
        'dialable (rest expired or in rest period)');
    // AND WHICH, AND WHY (S380). The line above says "or" and
    // leaves open which of the two reasons applies — on 10.09.2026
    // exactly that was the question on which an hour hung: the bootstrap lay
    // with a public IPv4 on the board AND in the supply and was
    // nonetheless not dialled. Only if something is really missing, and
    // capped.
    if (candidates.length < entries.size) {
      for (final z in entries.heldBack(now: current)) {
        log('Entry: held back — $z');
      }
    }
    for (final r in candidates) {
      if (chosen >= max) break;
      if (partnerCount >= policy.target) break;
      if (_sameBytes(r.lNode, keys.lNode)) continue; // not itself
      if (hasSessionWith(r.lNode)) continue;
      if (!r.isAuthentic) continue;
      // ── VIA THE RECORD, NOT VIA ITS FIRST ADDRESS (S373) ─
      //
      // Here stood `await connect(r.host, r.port)`, and `r.host`/`r.port`
      // are `addresses.first`. A record with four addresses thus got
      // one attempt on one of them; if that failed,
      // `connect` booked a failed attempt on the POSITION and after three rounds
      // the whole record fell out of the supply — including the addresses that
      // had never seen a packet. Reasoning and field measurement at
      // [dialAddressOrder].
      //
      // THE CAP STAYS ON THE RECORD, not on the attempt: `gewaehlt`
      // still counts records, [max] still caps
      // records. What changes is the number of attempts PER
      // record — at most [kDialAddressesPerRecord], at most
      // one per address family.
      await dialRecord(r);
      chosen++;
    }
    return chosen;
  }

  /// The own dialable addresses — the basis for "does this
  /// address lie in MY segment".
  ///
  /// THEY COME FROM THE ANNOUNCEMENT and not from a second determination.
  /// `setzeAnsageadressen` determined them at start from
  /// `dialableLocalAddresses()` and in doing so already filtered against
  /// DS-Lite/CGNAT/link-local; a second determiner would be a
  /// second truth (reasoning in the header of `local_addresses.dart`) and
  /// it would be `async`, which does not work in the dial path.
  ///
  /// REPORTED LIMIT, not fixed here: the announcement is set
  /// ONCE at start; an address change during operation leaves it standing
  /// (`service_daemon.dart:1700`: "An address change makes the own
  /// entry record silently wrong — reported gap"). As long as that is
  /// so, this list ages with it. The consequence here would be mild: an
  /// address of the own segment would lose rank 0 and slip to rank 4,
  /// but it would not drop out.
  List<String> get _ownIps => <String>[
        advertiseHost,
        for (final a in advertiseExtra) a.host,
      ];

  /// The address families in which this node can really DIAL.
  ///
  /// ── A BOUND SOCKET IS NO REACHABILITY (S379) ──────────
  ///
  /// `LinkHost.families` says which wildcard sockets came up. On
  /// Linux `::` binds even on a node that has no IPv6 except `::1` and a
  /// link-local address — the family then counts as
  /// present, and every send attempt ends in the kernel.
  ///
  /// MEASURED IN THE FIELD on 09.09.2026 on `.202` (`ip -6 addr`: only `::1`
  /// and `fe80:`), three times on that day:
  ///
  ///     "Eintritt: waehle [<ip6-pub#530ab672>]:39382 an (1 von 2)"
  ///     "link socket v6: Fehler — Send failed (Network is unreachable,
  ///                     errno = 101), address = ::"
  ///     "Verbindung kam nicht zustande (udpOwnPort:silent, tcpOwnPort:
  ///                     refused, tcp443:refused, icmpKnock:refused)"
  ///
  /// The price is not only the lost second: the failed attempt
  /// books on the RECORD (`noteUnreachable` keys per position),
  /// and after `kDialFailureLimit` rounds it falls out of the supply —
  /// together with its usable IPv4.
  ///
  /// THE SAME REASONING AS BEFORE, ONLY CARRIED TO THE END. The comment
  /// at `dialAddressOrder` rejects an address of a NON-BOUND
  /// family, because the attempt under Windows tears down the VM (§27.3: IOCP
  /// `send()` to an IPv6 without a route, below every try/catch). Exactly
  /// this case is "bound, but without a route" — it was not covered by the old
  /// condition.
  ///
  /// AND IT DECIDES WHO CAN BROKER. §11/§25 let a
  /// dual-stack node mediate between `v4-only` and `v6-only`; whoever
  /// considers himself dual-stack on the basis of a bound socket registers
  /// a mediation he cannot perform.
  ///
  /// IF NOTHING IS ANNOUNCED, THE SOCKET APPLIES. At start and in tests
  /// no announcement address stands yet; then the old behaviour remains,
  /// instead of muting the node.
  ///
  /// LOOPBACK COUNTS AS "NOTHING ANNOUNCED" HERE, and that is the
  /// decisive part: [advertiseHost] stands at `127.0.0.1` until the first announcement
  /// (:302), and `setAnnounceAddresses` returns without any
  /// change if it finds no non-local IPv4 — on
  /// a node WITHOUT IPv4 thus always. Whoever counted loopback would have
  /// read "only v4" exactly there and taken a v6-only node's only
  /// family away.
  Set<LinkAddressFamily> get usableFamilies {
    final bound = host.families;
    final outAddresses = <LinkAddressFamily>{
      for (final h in _ownIps)
        if (h.isNotEmpty && !h.startsWith('127.') && h != '::1')
          h.contains(':') ? LinkAddressFamily.v6 : LinkAddressFamily.v4,
    };
    if (outAddresses.isEmpty) return bound;
    return bound.intersection(outAddresses);
  }

  /// Dials ONE record — over its addresses in turn.
  ///
  /// ── WHY THIS CANNOT BE `connect` (S373) ──────────────────────
  ///
  /// [connect] takes host and port, i.e. EXACTLY ONE address. There was
  /// no function in `lib/` that dials a record as a whole —
  /// that is why both dial points (here and `lan_entry_wiring`) ran on
  /// `addresses.first`. But the failed-attempt memory lies one level
  /// HIGHER than the evidence that produces it: [EntryCache.noteUnreachable]
  /// keys per position, but what failed is an address. Exactly
  /// this imbalance burned whole records.
  ///
  /// ── THE MEMORY IS ONLY BOOKED AT THE END ───────────────────────
  ///
  /// [EntryCache.noteUnreachable] falls exactly ONCE per round, and only
  /// when ALL tried addresses have failed. That is the small
  /// solution, and it is preferred over the large one: bookkeeping per address
  /// would have cost up to four times as many memo entries (cap
  /// `capacity` 512 → up to 2048, about 300 kB instead of 50 kB), but more expensive than
  /// the memory would have been the second rule: quarantine and
  /// displacement are today defined per RECORD (`_forget(k)`
  /// removes the record), an address bookkeeping would need its
  /// own answer to when the record dies. Instead
  /// `rundenversatz` moves the choice within a family on per round —
  /// see [dialAddressOrder].
  ///
  /// Returns whether a session came about.
  Future<bool> dialRecord(EntryRecord r) async {
    // Held twice: `dialCandidates` already sifts out rest periods,
    // but the LAN path does not go via it.
    if (entries.isBackedOff(r.lNode)) {
      log('Entry: ${r.host}:${r.port} skipped — rest period after '
          '${entries.failuresFor(r.lNode)} failed attempt(s)');
      return false;
    }
    // HOISTED, because the diagnosis below needs the same set as the
    // decision here (S377). Two calls would be two truths as soon as
    // a port mapping gets confirmed between them.
    final ownHosts = ownDialHosts(
      advertiseHost: advertiseHost,
      advertiseMapped: advertiseMapped,
      advertiseExtra: advertiseExtra,
    );
    final usable = usableFamilies;
    final targets = dialAddressOrder(
      r.addresses,
      v4Available: usable.contains(LinkAddressFamily.v4),
      v6Available: usable.contains(LinkAddressFamily.v6),
      localIps: _ownIps,
      // The own addresses are no target (S374, B-1). Both sets
      // stay separate: `localIps` ranks the own segment,
      // `eigeneHosts` excludes.
      //
      // ── THE S374 FIX WAS INCOMPLETE (S376, P4-4) ────────────────
      //
      // Here stood `{..._eigeneIps, if (advertiseHost.isNotEmpty)
      // advertiseHost}` with the reasoning that `advertiseHost` covers "a
      // public address mapped via UPnP". That is wrong twice:
      // `_eigeneIps` has `advertiseHost` as its FIRST element
      // (:5320), so the addition was ineffective — and the mapped
      // address does not stand in `advertiseHost` at all, but in
      // [advertiseMapped], a field of its own with a source of its own (the
      // gateway) and a life cycle of its own. Exactly the address that the
      // comment wanted to exclude was the only one it did not
      // cover.
      //
      // It stands in the OWN record in second place (`ownEntry`,
      // :1037) and thus comes back via every partner. With
      // hairpin NAT `wan-ip:port` is dialable from inside — the node
      // sets up a session to itself; without hairpin the dial fails
      // and `noteUnreachable` falls on the OWN position.
      //
      // What is compared is the HOST, not host+port. A neighbour behind
      // the same NAT names the same `wan-ip` and thus drops out for the
      // outside path — he stays reachable via his LAN address, which
      // stands in FIRST place in his record. That is the right
      // path for him: a neighbour in the own segment is not dialled via the
      // router.
      ownHosts: ownHosts,
      roundOffset: entries.failuresFor(r.lNode),
    );
    if (targets.isEmpty) {
      // NO PACKET, BUT A FINDING. This node demonstrably cannot reach the record
      // — none of its addresses lies on
      // a family that is bound here. That is booked like a
      // failed attempt, because it is one; it heals by itself, because after
      // the quarantine the counting starts anew and a family that comes up later
      // is then seen.
      // ── THE REASON IS DISTINGUISHED (S377) ────────────────────────
      //
      // Here stood exactly one line for three different findings:
      // "keine anwaehlbare Adresse … eigene Familien: v4,v6". It names
      // the address families and thereby suggests one is missing — the
      // most frequent case, however, is a different one: the address IS one of the
      // own hosts and is excluded by `dialAddressOrder`
      // (S374 B-1). The line thus expressly excluded the applicable
      // cause.
      //
      // MEASURED: `smoke_v41_redial` ran on `4 passed, 2
      // failed` since S354, because both test nodes announced `127.0.0.1` and the
      // record of the one thus lay on the own host of the other.
      // The S376 report closed the investigation with "other cause"
      // — the cause stood in the log, under a wrong name. The same
      // class as the reason for which `_versuchAdresse` has written down the
      // `LinkAttemptOutcome` since S374.
      final own = ownHostsAmong(r.addresses, ownHosts);
      final reason = own.length == r.addresses.length
          ? 'all addresses are own hosts '
              '(${ownHosts.join(", ")}) — §11.1: the own host is '
              'not a target'
          // WHAT IS REPORTED IS WHAT DECIDED. Here stood `host.families`
          // — the bound sockets. Since S379
          // [brauchbareFamilien] selects (socket AND own source address);
          // the old line would, in exactly the case the fix
          // concerns, have reported "v4,v6" while v6 was rejected.
          : 'own families: '
              '${usable.map((f) => f.name).join(",")}'
              '${usable.length == host.families.length ? '' : ' (bound: '
                  '${host.families.map((f) => f.name).join(",")}, discarded '
                  'without own source address)'}'
              '${own.isEmpty ? '' : ', of which ${own.length} excluded '
                  'as own host'}';
      log('Entry: no dialable address in '
          '${r.addresses.join(", ")} — $reason');
      if (entries.noteUnreachable(r.lNode)) {
        log('Entry: record discarded — no reachable '
            'address family, $kDialFailureLimit rounds in a row');
      }
      return false;
    }
    for (var i = 0; i < targets.length; i++) {
      final a = targets[i];
      log('Entry: dialling $a (${i + 1} of ${targets.length})');
      if (await _attemptAddress(a.host, a.port, r)) return true;
    }
    if (entries.noteUnreachable(r.lNode)) {
      log('Entry: record ${r.host}:${r.port} discarded — '
          '$kDialFailureLimit rounds without success on all addresses');
    }
    return false;
  }

  /// Sets up ONE connection and books how it turned out.
  ///
  /// ── WHY THE REST PERIOD SITS HERE AND NOT AT THE CALLER (B-33) ──
  ///
  /// This is the only place at which this node on its own opens a
  /// session — the entry from the supply and the LAN entry
  /// both run through here. The LAN call goes out every 30 s, and the
  /// caller issues a fresh record every time; without a
  /// deadline this node would dial a remote side that it does not reach
  /// again every 30 s. Exactly that stands as "22-36 session setups per
  /// node in one afternoon" in the finding. A deadline at the caller
  /// would have applied it on only one of the two paths.
  ///
  /// Returns whether a session came about.
  Future<bool> connect(String hostName, int port) async {
    // Who sits there the supply knows via the endpoint index — the
    // caller does not know the position itself.
    final known = entries.lookupEndpoint(hostName, port);
    if (known != null && entries.isBackedOff(known.lNode)) {
      log('Entry: $hostName:$port skipped — rest period after '
          '${entries.failuresFor(known.lNode)} failed attempt(s)');
      return false;
    }
    if (await _attemptAddress(hostName, port, known)) return true;
    if (known != null && entries.noteUnreachable(known.lNode)) {
      log('Entry: record $hostName:$port discarded — '
          '$kDialFailureLimit failed attempts in a row');
    }
    return false;
  }

  /// ONE connection attempt to ONE address — without booking.
  ///
  /// ── WHY THE BOOKING IS PULLED OUT (S373) ───────────────────────
  ///
  /// [dialRecord] tries several addresses of the same record. If it
  /// called [connect] for that, every failed address would book a failed attempt
  /// of its own — a two-address record would be burned after one and a half
  /// instead of after three rounds, i.e. FASTER than before. The
  /// attempt and its booking are two things, and since two
  /// callers with different booking rules stand here, they must
  /// also be two functions.
  ///
  /// Success is indeed booked immediately: a standing session is
  /// indisputable, no matter via which address it came.
  Future<bool> _attemptAddress(
      String hostName, int port, EntryRecord? known) async {
    final r = await host.connect(LinkEndpoint(hostName, port));
    final ch = r.channel;
    if (ch != null) {
      // This node dialled — OUTGOING (§25.4).
      adopt(ch, inbound: false, peer: LinkEndpoint(hostName, port));
      // First the verified position from the handshake, otherwise the one from the
      // record: an anonymous session says nothing about WHOM one
      // has reached, but the endpoint has answered.
      final pos = ch.peerPosition ?? known?.lNode;
      if (pos != null) entries.noteReachable(pos);
      return true;
    }
    // ── THE REASON IS WRITTEN DOWN TOO (S374, B-1) ────────────────────
    //
    // Here stood only "did not come about". Exactly this one line prevented the
    // traffic measurement of 07.09.2026 from clearing up its own
    // finding: 272 dials on the emulator, 247 of them
    // failed (91 %), and the reason stood nowhere. It is there —
    // `Link.connect` returns `attempts` with `LinkAttemptOutcome` per
    // step, and the enum distinguishes exactly what matters:
    //
    //   refused  the operating system rejects -> nobody listens on the
    //            port. The record points to a dead port.
    //   silent   no answer within `stageTimeout` -> filtered or
    //            not reachable. The record points to an address
    //            that does not work from here.
    //
    // These are two completely different findings with two different
    // answers, and until here they were indistinguishable. The effort
    // is one string; the alternative was a session of measuring work.
    log('Connection to $hostName:$port did not come about '
        '(${r.attempts.map((a) => '${a.stage.name}:${a.outcome.name}').join(', ')})');
    return false;
  }

  /// How many slots lie between two harvest runs.
  ///
  /// NOT EVERY SLOT. A harvest enqueues control frames, and each
  /// of them consumes a slot — harvesting on every tick would mean filling the
  /// whole egress with harvests and leaving no slot over for messages.
  /// At `kSlotInterval` = 8 s, 4 yields one
  /// harvest run roughly every 32 s.
  static const int harvestEverySlots = 4;

  /// How many slots lie between two set requests.
  ///
  /// RARER THAN THE HARVEST, and for a different reason than there.
  /// The harvest fetches messages — it is the operation. The set request
  /// extends the NEIGHBOURHOOD, and that changes in minutes, not
  /// in seconds. At `kSlotInterval` = 8 s, 8 yields one request roughly
  /// every 64 s.
  ///
  /// The cap lies additionally in [requestEntrySet] itself: as long as
  /// [setLatch] stands, every further request silently drops. A
  /// partner that does not answer thus costs no repetition —
  /// but it does not block it permanently either; that is ensured by
  /// [entrySetTimeoutSlots].
  static const int entrySetEverySlots = 8;

  /// After how many slots without an answer the set lock falls by itself.
  ///
  /// TWO REQUEST INTERVALS, and the number is a calculation, not a choice:
  /// a request stands in the control queue, goes out with one slot,
  /// the answer stands in the partner's queue and comes back with
  /// one of his slots. One interval would thus be tight; three
  /// or more would leave a node whose partner has broken off
  /// unnecessarily long without neighbourhood extension.
  ///
  /// The expiry does NOT replace the answer — it only ends the waiting.
  /// The next request comes at the usual tick and costs no
  /// additional frame (working rule 5).
  static const int entrySetTimeoutSlots = entrySetEverySlots * 2;

  /// How many slots lie between two targeted acquisition runs.
  ///
  /// THE SAME TICK AS THE SET REQUEST, but offset. Both fetch
  /// entry records; the one arbitrary ones, the other exactly those
  /// that the delivery is missing. Letting them run in the same slot
  /// would mean letting two frames compete for one place, without
  /// either of the two being faster.
  static const int entryFetchEverySlots = entrySetEverySlots;

  /// How many slots lie between two re-dial attempts.
  ///
  /// RARER THAN THE HARVEST, more frequent than the set request. A node
  /// without partners is completely deaf — hence not too rare; a
  /// dial however costs a handshake at a remote side that
  /// is perhaps not there right now, hence not too often. At
  /// `kSlotInterval` = 8 s, 6 yields one attempt roughly every 48 s.
  static const int dialEverySlots = 6;

  /// How many slots lie between two lookup runs.
  ///
  /// RARER THAN ANYTHING ELSE, and that follows from what a lookup
  /// brings in and what it costs. It costs about seven slots; in return it holds
  /// for a whole epoch (§7.2, `ResponsibleSetCache`). Nobody would need to look up
  /// more often — it would only displace the harvest, and that is
  /// the only movement that FETCHES messages. At `kSlotInterval` = 8 s,
  /// 12 yields one run roughly every 96 s; a counterpart with its seven
  /// targets is thus covered in a good eleven minutes.
  static const int lookupEverySlots = 12;

  /// How many slots lie between two status lines.
  ///
  /// No egress, no wire — one line into the own log. It nonetheless
  /// stands on the slot and not on a clock, so that in this class there is
  /// exactly ONE clock and nobody later takes a second one for
  /// granted.
  static const int statusEverySlots = 15;

  /// Interval between two readiness probes while the node is NOT
  /// `ready` — in slots, not in seconds (invariant 1: no
  /// second rhythm in the egress).
  ///
  /// THIRTY, derived and not chosen. A probe passes in
  /// at most [kDeliveryFamilies] = 3 frames, the drain is ONE
  /// control frame per slot. 30 slots x `kSlotInterval` = 8 s are four
  /// minutes, i.e. 3 frames per 30 draining — 10 % of the egress. At
  /// [statusEverySlots] = 15 (two minutes) it would be 20 %, and the
  /// control queue currently does not bear that (S374, link 2).
  ///
  /// The value is an UPPER LIMIT of the repetition, not a frequency: the
  /// fast path remains the new session, which probes immediately. This
  /// number only takes effect when no session arises any more — and it ends
  /// with `ready`.
  static const int probeEverySlots = 30;

  int _slotCounter = 0;

  /// How often harvesting happened since the node has been running.
  int harvestRuns = 0;

  /// Called after EVERY harvest run that enqueued requests.
  ///
  /// ── WHAT FOR (§4.5.4, S363) ────────────────────────────────────────────
  ///
  /// The layer above must know WHEN harvesting happened for the first time:
  /// `CleonaService` postpones its cold-start rotation until then,
  /// because an announcement that is sealed before the first harvest
  /// goes against the not-updated contact keys
  /// (`kaltstart_rotationstor.dart`).
  ///
  /// WHAT IS REPORTED IS THE RUN, NOT THE ANSWER. The answer hangs on the
  /// remote side; expecting it would turn the gate into a bet that a
  /// node without a counterpart never wins. The run is what this
  /// node itself can do.
  ///
  /// A callback that throws must not tear the slot tick — hence
  /// caught and logged.
  ///
  /// ── A LIST, NOT A FIELD (S376, P5 finding 1) ─────────────────────
  ///
  /// As with [_placementSinks] and [_readinessSinks]: `attachV41`
  /// set this field per identity against the same node. For all
  /// except the last attached one the cold-start gate of the
  /// key rotation (§4.5.4) thus stayed closed forever — it only opened
  /// via the fallback deadline of one hour.
  final List<void Function()> _harvestRunSinks = <void Function()>[];

  /// Registers for "a harvest run has enqueued requests".
  /// Admissible multiple times — one per identity.
  void addHarvestRunListener(void Function() cb) {
    if (!_harvestRunSinks.contains(cb)) _harvestRunSinks.add(cb);
  }

  /// Removes a sink again. **Mandatory on `removeIdentity`.**
  void removeHarvestRunListener(void Function() cb) =>
      _harvestRunSinks.remove(cb);

  /// How many identities listen to the harvest run. Metric.
  int get harvestRunSinksNumber => _harvestRunSinks.length;

  void run() {
    // THE HARVEST NEEDS A CLOCK. `harvestTick` had no caller at all
    // in `lib/` until S349 — only the lab program called
    // it. Thus every Secure message lay at the responsible relay and
    // was never collected: the send path was finished, the collection path
    // did not exist.
    //
    // IT HANGS ON THE SLOT PLAN, not on a timer of its own. A second
    // timer would be a second rhythm in the egress, and that would be
    // recognisable from outside as such (invariant 1).
    driver.onSlotDone = () {
      // THE PASS BUDGET OF THE PATH-BLOCK RESOLVER IS RELEASED HERE.
      //
      // `ReplyBlockResolver.resetScanBudget` had NO caller in `lib/`,
      // although its own comment promised "the caller calls this every
      // second". Without release the cap is no
      // cap but an end point: after `scanBudget` (500) full
      // passes — cache misses, i.e. foreign or new pairs —
      // `resolve` returns `null` forever, and the node stops
      // forwarding as r2. Silently, because an unresolved
      // path block looks like a foreign one. The same class as B-32.
      //
      // ON THE SLOT, NOT ON A CLOCK OF ITS OWN. A per-second timer would be a
      // second rhythm (invariant 1); the slot tick runs anyway.
      // Price: instead of 500 passes per second it is 500 per slot,
      // at `kSlotInterval` = 8 s thus on average a good 62/s. That is
      // TIGHTER than the comment promised, not wider — and with four
      // partners 500 passes are about 21 ms, i.e. 0.26 % of a
      // core per slot.
      blockResolver.resetScanBudget();

      // -- THE EGRESS EDGE (S381) --------------------------------------
      //
      // Before the harvest gate, because it has nothing to do with the harvest
      // tick: a message that was only held up at the full queue should
      // go out as soon as there is room — not only at the next
      // harvest run. Reasoning at [_egressFreiSenken].
      _egressPlaceCheck();

      _slotCounter++;

      // ── WORK THAT THIS LAYER DOES NOT KNOW (§13.3.4) ──────────────
      //
      // "it hangs off a tick the node keeps anyway (§19: no polling)" —
      // §13.3.4 about the renewal cadence of the rescue bundle, and the
      // sentence applies to every consumer here. The callback stands BEFORE the
      // harvest gate `_slotZaehler % harvestEverySlots != 0`, because its
      // use lies precisely in the slots in which nothing else is pending.
      //
      // PROTECTED, because a throw here would tear the slot tick and with it
      // the cover stream. A consumer that throws loses its
      // slot, not the node its rhythm.
      //
      // VIA A COPY: a consumer may unregister in the callback
      // (`removeSlotTick`), and run over the live list
      // that would be `Concurrent modification during iteration` — in the middle of the
      // tick, i.e. in the cover stream. The same class of defect that cost S361 the
      // harvest run.
      for (final tick in _slotCallbacks.toList(growable: false)) {
        try {
          tick(_slotCounter);
        } catch (e) {
          log('Slot callback threw: $e');
        }
      }

      // ── THE EXPIRY EDGE OF THE FOREIGN EVIDENCE (S376, finding 3) ────────────
      //
      // A piece of foreign evidence expires after [ReadinessTracker.remoteEvidenceTtl]
      // = 1 h, and `_sweepRemote` throws it away on READING. Thus
      // `readiness.state` changes without any change site — the transition
      // `ready -> connecting -> searching` took place and was never
      // reported. No display, no IPC event, no drain of the
      // local outbox at the later re-rise, because its edge
      // compared against a `vorher` that the outside world had never
      // seen.
      //
      // Since S376 the reporter keeps its comparison state itself
      // ([_gemeldeteBereitschaft]); here it is only asked
      // regularly. The call is moreover the only one that still triggers `_sweepRemote`
      // at all on a silent node.
      //
      // ON THE SLOT, NOT ON A CLOCK OF ITS OWN (invariant 1) — like status,
      // probe, lookup and harvest alongside. NO NETWORK TRAFFIC: the call
      // computes over two maps in memory.
      _reportReadiness(() => 'Foreign proofs expired or sessions gone');

      // ── THE STATUS LINE HAS A READER IN THE APPLICATION (S353) ──────
      //
      // `status` was built, tested and had EXACTLY ONE caller:
      // `bin/cleona_v41_node.dart`, the lab program. In the daemon and in
      // the app nobody read it. Thus of all things the four
      // numbers stood in no field log that alone reveal that
      // control frames fall under the table (`droppedControl`) or that
      // the queue depth measures the waiting time of a harvest request in minutes
      // (`pendingControl`).
      //
      // On 29.08. exactly this gap cost time: it was measured
      // that a node after ONE Secure send did not harvest for six and a half minutes
      // — why could not be told from the log,
      // because the queue depth did not appear in it. The same
      // class as B-32 (`SecureStore.expire` without a caller), only one
      // step more harmless: here nothing fails, one only does not SEE
      // when something fails.
      //
      // ON THE SLOT, NOT ON A CLOCK (invariant 1). [statusEverySlots]
      // = 15 yields about two minutes at `kSlotInterval` = 8 s.
      if (_slotCounter % statusEverySlots == 0) log(status);

      // ── THE READINESS PROBE NEEDS A SECOND TRIGGER ──────
      //
      // Until S374 `probePlacement` had EXACTLY ONE caller: the new
      // session (`_sitzungInBetrieb`). The comment there justifies that
      // with "there is nothing to repeat as long as nothing has changed;
      // a new session IS the change". That only holds
      // as long as sessions still arise.
      //
      // MEASURED IN THE FIELD on 07.09.2026, both lab nodes, correlation 1:1:
      //   Node A  7 sessions, 7 probes, last both 20:21:07
      //   Node B  8 sessions, 7 probes, last probe   20:26:06
      // At 20:50 both stood unchanged — 29 and 24 minutes respectively without a
      // single probe, while both nodes stood at `connecting` with ONE
      // confirmed relay and `ready` requires two.
      //
      // THIS IS A DEAD END WITHOUT EXIT. As soon as the partner set
      // stands ("Partner 4 von 4"), no edge comes any more; without an edge
      // no probe, without a probe no placement confirmation, without
      // confirmation never `ready`. Visibly everything hangs on `ready`:
      // `ContactSeedBuilder.isReady` is literally
      // `readinessState == kReadinessReady` (`contact_seed.dart`), so
      // `getContactSeedFor` returns `null` — the QR code stayed at 95 %,
      // on desktop as on Android, and `gui-00a 0a.08`,
      // `gui-01e` and `WIN 11.02` fell at the same root.
      //
      // WHY THIS IS NO POLLING (working rule #5). The condition ends
      // by itself: with `ready` it stops, and it is the only
      // way to reach `ready` at all. It hangs on the slot tick and
      // not on a clock of its own — no second rhythm in the egress
      // (invariant 1), just like status, harvest and re-dial alongside.
      //
      // PRICE, CALCULATED: a probe passes in at most
      // [kDeliveryFamilies] = 3 frames. [probeEverySlots] = 30 yields
      // four minutes at `kSlotInterval` = 8 s, i.e. 0.75 frames/min
      // against a drain of 7.5/min — 10 % of the egress, and only
      // as long as the node is not ready. The edge remains the
      // fast path; this here is the exit from the standstill.
      if (readiness.state != Readiness.ready &&
          _slotCounter % probeEverySlots == 0) {
        // The return value is evaluated, not thrown away: if the
        // probe returns 0, it has enqueued NOTHING (no
        // entry record for the eight nearest positions) and
        // otherwise keeps silent. Exactly this silence cost time in S374
        // — a node that waits for the receipt of a never
        // sent probe looks in the log like one to whom only
        // nobody answers.
        if (probePlacement() == 0) {
          log('Readiness: probe NOT enqueued — none of the eight '
              'nearest positions has an entry record '
              '(table ${table.length}, partners $partnerCount)');
        }
      }

      // ── THE LOOKUP (S356) ─────────────────────────────────────────────
      //
      // ON THE SLOT, NOT ON A CLOCK OF ITS OWN (invariant 1) — like harvest,
      // set request and re-dial alongside. `unawaited`, because a run can take up
      // to three rounds of 60 s each and the slot tick must not wait
      // for it; the bolt `_lookupLaeuft` prevents
      // two runs from overlapping.
      //
      // NO `try` AROUND THE CALL, but `catchError` ON THE FUTURE: an
      // `unawaited()` behind a SYNCHRONOUS `try/catch` catches
      // nothing at all in Dart — the throw arrives later, when the block has long
      // been left. Exactly there a crash slipped past in S351
      // that was looked for in the call path and was never there. Here the
      // call runs from a timer callback: an unhandled throw would go into
      // the zone handler of the daemon, and that does not classify it as
      // survivable (`exit(99)`).
      if (_slotCounter % lookupEverySlots == 0) {
        unawaited(lookupTick().catchError((Object e) {
          log('Lookup run threw: $e');
        }));
      }

      // THE SET REQUEST — the second half-clause of the cascade.
      //
      // `requestEntrySet` was built and had NO caller in `lib/`;
      // only `bin/cleona_v41_node.dart` asked, in the lab, via its own
      // timer. The application did name itself (`announceOwnEntry`
      // runs), but never asked back — the exchange ran in ONE
      // direction, and the supply only grew via the external rendezvous
      // and via unsolicited material. Whoever stands in the guest WLAN whose
      // rendezvous is blocked thus got no further, although next to
      // him stands a partner that knows twenty paths.
      //
      // Two caps lie on it: this slot counter and [mengeLatch]
      // in the method itself. The second is the more important one — it
      // prevents a mute partner from costing repetitions.
      //
      // ONLY WITH A PARTNER — otherwise the door closes forever.
      // `_mengeOffen` stands at `true` after enqueuing and is only
      // released by an ANSWER; without a partner none comes. A node
      // that once asked without a partner would thus never have
      // asked again, of all things on the cold-start path that this is
      // meant to help. `harvestTick` has carried the same bolt all along
      // (`if (partnerCount == 0) return 0;`).
      //
      // UNTIL S375 A SECOND REASON WAS ADDED, and it has gone:
      // `tick()` took the control frame out of the queue
      // (`takeControl`) AND then dropped it if
      // `partners.isEmpty` — the request was gone without ever having
      // seen a wire. Since finding 2 (S376) `tick` takes nothing any more without a
      // partner; the frame would thus stay lying. The bolt
      // here stays nonetheless, because the lock via `_mengeOffen`
      // alone already suffices to justify it.
      // ── AND IT EXPIRES (S376, P4-3) ─────────────────────────────
      //
      // Without these four lines the lock is not a cap but a
      // bolt: the paragraph above itself names the situation — `_mengeOffen`
      // is only released by an ANSWER — and closed it only for
      // the partnerless case. There are three more: a partner without
      // entries did not answer at all, an overflow of the
      // control queue discards the group, a partner breaks off.
      // `entrySetSettled` was the built way out and had
      // NO caller in `lib/`.
      if (setLatch.expire(_slotCounter)) {
        log('V4.1: set request without answer for $entrySetTimeoutSlots slots '
            '— latch drops (${setLatch.expired}. time)');
      }
      if (partnerCount > 0 && _slotCounter % entrySetEverySlots == 0) {
        requestEntrySet();
      }

      // ── AND THE TARGETED ACQUISITION (S376, P4-1) ──────────────────
      //
      // The set request above fetches ANY records; here
      // those are fetched that the responsibility computation is currently
      // missing. `requestMissingEntries` was built and had
      // NO caller in `lib/` — this is it.
      //
      // Offset against the set request (`% == 4` with a tick of 8),
      // so that the two acquisition paths do not seek the same slot.
      if (_slotCounter % entryFetchEverySlots ==
          entryFetchEverySlots ~/ 2) {
        final n = _entryFetchTick();
        if (n > 0) {
          log('V4.1: $n entry record(s) requested specifically '
              '(${_missedRecords.length} missing)');
        }
      }

      // ── AND WHOEVER HAS NO PARTNER LEFT DIALS AGAIN (S354) ────
      //
      // `dialFromEntries` ran EXACTLY ONCE: in the cold-start block of
      // `v41_attach.dart`, on the side at start. If a node afterwards lost
      // its sessions, it stayed alone — with a full supply, without a
      // single dial attempt.
      //
      // Measured in the field on 30.08. (`.201`): after the restart of its
      // two remote sides the node stood at `Partner 0` and stayed
      // there. Four minutes, five entry records in the supply, no
      // dial. Everything above — harvest, placement, liveness — kept running
      // and fell to the floor, because `DeliveryNode.tick` discarded the cell without a
      // partner. The second part no longer applies since S376
      // (finding 2: without a partner nothing is taken any more); the first —
      // a node without partners dials again by itself — is the
      // reason for which these lines stand here, and stays.
      //
      // ONLY IF THERE ARE TOO FEW. `policy.target` is the desired
      // partner count; above it no dialling happens. And only every
      // [dialEverySlots] slots, so that a node in a network that
      // is not reachable right now does not knock every second — the
      // rest period per record (`connect`, B-33) lies additionally
      // below it.
      //
      // NO COVER CELL. A dial is a handshake of the link layer,
      // no egress from the stream; it does not fall under invariant 1 —
      // just as the LAN call and the cold-start call do not either.
      if (partnerCount < policy.target &&
          _slotCounter % dialEverySlots == 0) {
        unawaited(() async {
          try {
            final n = await dialFromEntries();
            if (n > 0) {
              log('Entry: $n node(s) redialled (partners $partnerCount '
                  'of ${policy.target})');
            }
          } catch (e) {
            // A failed dial attempt is the normal case, no
            // error — and it must not tear the slot tick.
            log('Entry: redial failed ($e)');
          }
        }());
      }

      if (_slotCounter % harvestEverySlots != 0) return;

      // ── THE EPOCH MOVES EVEN WITHOUT A NEW SESSION (S354) ────────────
      //
      // `publishLiveness` so far hung solely on `adopt` — on a new
      // session. The own comment there already named the gap: "whoever
      // runs longer than an epoch without a new session becomes invisible to new
      // senders". An epoch is 24 h (§6, E-J); a node
      // that runs through a day is exactly that.
      //
      // IT COSTS NOTHING IF NOTHING HAS HAPPENED: the note in
      // `_eigeneLiveness` lets the call run through empty as long as
      // epoch and return-path partner stand. Only the change places anew.
      //
      // And the opposite direction right along with it: a route whose epoch
      // has moved on is thrown away before anyone uses it.
      final current = DateTime.now().toUtc();
      _routesMaintain(current);
      final newPlaced = publishLiveness(now: current);
      if (newPlaced > 0) {
        log('Liveness: $newPlaced placement(s) queued (epoch change)');
      }

      final n = harvestTick();
      if (n > 0) {
        harvestRuns++;
        log('Harvest: $n request(s) enqueued');
        // ONE CATCH PER SINK, via a copy — the same
        // reasoning as with the readiness edge.
        for (final sink in List<void Function()>.of(_harvestRunSinks)) {
          try {
            sink();
          } catch (e) {
            log('Harvest: callback onHarvestRun threw ($e)');
          }
        }
      }
    };
    driver.start();
  }

  /// Whether this node has been torn down.
  ///
  /// WHY A FLAG WHEN THERE IS `stop()`. Concurrent loops that
  /// live longer than one slot — the upkeep of the external rendezvous in
  /// `v41_attach`, for example — need a termination criterion that they can read
  /// themselves. Without it every such loop would have needed a timer
  /// of its own, and a `Timer.periodic` keeps the Dart VM alive:
  /// exactly the trap because of which `V41Runtime.entryPersist` stands in the
  /// return value at all and every standalone suite would otherwise hang at the end.
  bool get stopped => _stopped;
  bool _stopped = false;

  Future<void> stop() async {
    _stopped = true;
    // UNREGISTER FIRST. A checker that points to a torn-down node
    // answers from a partner list that nobody maintains any more —
    // and `CoverSaver` is process-wide, a second node in the same
    // process would inherit the answer. The same consideration as with
    // `demux.dAdmission` further below.
    CoverSaver.instance.unbindLanConfinedProbe(this);
    driver.stop();
    for (final s in _subs) {
      await s.cancel();
    }
    // BEFORE `host.stop()`. `DSession` holds one
    // `StreamController` per session for the incoming frames; an open
    // controller keeps the Dart event loop alive, and the node
    // would then not tear down. The branch in the demux is expressly
    // withdrawn, so that a datagram that arrives between this call and
    // `demux.close()` does not reach into a just emptied table.
    host.demux.dAdmission = null;
    await dSocket.close();
    // BEFORE `host.stop()` and for the same reason as the D socket: a
    // `ServerSocket` with a running `listen` keeps the Dart event loop
    // alive. A node that does not tear it down lets every
    // standalone test that starts it hang — the same trap that
    // `entryPersist` forces in the return value of `startV41Node`.
    await tcp.close();
    await host.stop();
  }

  /// The status line — and since S352 it also shows the control queue.
  ///
  /// `droppedControl`, `maxControlDepth`, `controlFailures` and
  /// `droppedEphemeral` were built, tested and had NO reader in `lib/` or in
  /// `bin/`. That is the same class as B-32
  /// (`SecureStore.expire` without a caller) and `resetScanBudget`, only one
  /// step more harmless: here nothing fails, one only does not SEE when
  /// something fails.
  ///
  /// And that is exactly what matters with these four. The cap on the
  /// control queue discards nothing in regular operation (measured: peak 63
  /// with pure harvest, 0 discards); if `verworfen` rises in the field, that is
  /// the only place at which one learns that requests fall under the
  /// table — and without a display it would again be a silent loss
  /// that one would only learn of through missing messages.
  /// What the reassemblers have thrown away — both paths together.
  ///
  /// `PayloadReassembler` discards silently (E-83) and only counts; until 30.08.
  /// `discarded` had NO reader in `lib/`, and neither had
  /// `payloadsAssembled`/`payloadsOpened`. Thus three completely
  /// different findings looked the same in the log: "nothing arrived at all",
  /// "pieces arrived, the payload was never finished" and "the payload
  /// was finished but could not be opened". The proof of which of
  /// them applied on 30.08. therefore needed archaeology on the
  /// exclusion list of the placement store. That is not necessary a second time.
  /// PUBLIC SINCE S360: the network statistics show this number as a tile of its own.
  /// Until then it stood only in [status] — a log line that
  /// no user sees.
  int get discardedPieces => _viaAssembler((z) => z.discarded);

  /// Of those due to overlap — the rest are format errors, memory pressure
  /// and length conflicts.
  int get _droppedOrder =>
      _viaAssembler((z) => z.discardedOutOfOrder);

  /// Transmissions that are waiting for missing pieces.
  ///
  /// BELONGS NEXT TO THE DISCARDS, since the reassembler keeps gaps open
  /// (30.08.). Before, "nothing gets finished" necessarily meant
  /// "something was discarded"; now it can also mean "something is still waiting",
  /// and the two cases require opposite
  /// conclusions. Without this number the finding of 30.08. would be invisible again after its
  /// own fix.
  /// PUBLIC SINCE S360 — the same reasoning as with
  /// [verworfeneStuecke]: the tile "wartet auf Stuecke" reads it.
  int get openTransfers =>
      _viaAssembler((z) => z.openTransfers);

  int _viaAssembler(int Function(PayloadReassembler) f) {
    var n = 0;
    n += f(_speedAssembler);
    for (final z in _harvestAssembler.values) {
      n += f(z);
    }
    return n;
  }

  String get status => 'Slots ${driver.slotsEmitted}, verpasst '
      '${driver.slotsSkipped}, Partner ${_partners.length} '
      '(aus $syncPartnersOutbound, ein $syncPartnersInbound, '
      'unabhaengig $independentSyncPartners), '
      'empfangen $_uninteresting, zusammengesetzt $payloadsAssembled, '
      'ohne Paarschluessel $pairEmptySkipped, '
      'geoeffnet $payloadsOpened, Stuecke verworfen $discardedPieces '
      '(Reihenfolge $_droppedOrder, Form '
      '${_viaAssembler((z) => z.discardedMalformed)}, Druck '
      '${_viaAssembler((z) => z.discardedPressure)}, Laenge '
      '${_viaAssembler((z) => z.discardedLengthConflict)}), '
      'offene Uebertragungen $openTransfers, '
      'Speed-Routen ${_routesEpoch.length}, Epoche ${nodeEpochNow()}, '
      'Nutzlast wartet ${egress.stream.pendingReal}, '
      'Kontrollschlange ${egress.stream.pendingControl}'
      '/${egress.stream.maxControlDepth}, verworfen '
      '${egress.stream.droppedControl}+${egress.stream.droppedEphemeral}, '
      'Kontrollfehler ${delivery.controlFailures}, '
      // THE LOOKUP BELONGS IN THE STATUS LINE (S356). The recurring
      // defect of this migration is "built, never trodden" — counted three times
      // (attachV41, Nostr provider, LanEntryService). If the
      // number stands in the field log, the question "does the lookup run at all?"
      // is a measurement instead of a guess.
      'Lookups $lookupRuns/${networkResponsible.queriesSpent} Anfragen, '
      // THE ONION FOR THE SAME REASON (S376, E-L). Two numbers, because
      // TWO questions would be open: does the onion wrapping run at all
      // (`verzwiebelt`), and is a lookup omitted for lack of a blind relay
      // (`ohne Blindrelais`)? The second number is the one by which a node
      // without a foreign inventory is recognisable — otherwise that would look like a
      // network in which nobody answers.
      'davon verzwiebelt $lookupsOnionWrapped, '
      'ohne Blindrelais $lookupsWithoutBlindRelay, '
      'Blindrelais-Dienst ${delivery.blindRelayHandovers}/'
      '${delivery.blindRelayAnswer}, '
      'Netzmengen ${networkResponsible.size}, '
      // AND THE TAG LINES — for the same reason as the lookup one
      // line higher. The rescue bundle renews every 14 days
      // (§13.3.4); without these two numbers in the field log "does it
      // place at all?" would be a guess, and its absence would otherwise show
      // at the earliest after 31 days — when the bundle is gone.
      'Markenablagen $tagPlacements, Markenernten $tagHarvestRequests, '
      // THE RECEIPT SIDE OF THE PLACEMENT (S379). Readiness rests on
      // confirmed placements (§22.7); if it stands still, exactly four
      // numbers are the question: how many own placements are still waiting for a
      // receipt (`offen`), how many receipts found no book
      // (`ohne Buch` — the return path of a PREDECESSOR has expired and
      // the foreign receipt landed here), how many carried the wrong
      // MAC (`gefaelscht`), and how many pieces of evidence stem from relays without
      // a session of their own (`fremde Belege`). Without them "no receipt
      // comes" cannot be distinguished in the field from "one comes, it just does not count".
      'Ablage-Quittungen offen ${_ownDeposits.length}, ohne Buch '
      '$unknownReceipts, gefaelscht $forgedReceipts, '
      'fremde Belege $foreignRelayProofs, bestaetigte Relais '
      '${readiness.verifiedRelays}, '
      // AND THE OTHER HALF OF THE SAME PATH: the return-path store of the
      // INTERMEDIATE nodes. A receipt whose identifier has expired there
      // (`verfallen`) or never found room (`verdraengt`) never reaches the
      // sender — he then sees the same as with a relay that
      // keeps silent. The two numbers separate the two cases.
      'Rueckwege ${delivery.pending.length} offen, '
      '${delivery.pending.expired} verfallen, '
      '${delivery.pending.dropped}+${delivery.pending.droppedPerPartner} '
      'verdraengt, '
      // AND THE BULK LANE (§9.3) — for the same reason as the two
      // lines above. A media object is thousands of blocks over
      // a SECOND drain; without these numbers in the field log "does it
      // place, does someone hold, does something come back?" would be three times a
      // guess. `Bulk-Vorrat` is the depth of the second drain and
      // the number of frames it has discarded for lack of room — the
      // counterpart to `Kontrollschlange` for the lane that does NOT run on
      // the slot tick.
      'Bulk gehalten ${delivery.bulk.blockCount} Bloecke/'
      '${delivery.bulk.tagLineCount} Linien, ausgeliefert '
      '${delivery.bulkBlocksServed}, weitergereicht '
      '${delivery.bulkForwarded}, verdraengt ${delivery.bulk.evicted}, '
      'verfallen ${delivery.bulk.expiredBlocks}'
      '${bulkEgress == null ? '' : ', Bulk-Vorrat ${bulkEgress!.pending}'
          '/${bulkEgress!.dropped} verworfen'}'
      '${bulkSenderStatus == null ? '' : ', ${bulkSenderStatus!()}'}, '
      'Slot-Verbraucher ${_slotCallbacks.length}, '
      // S381: a discarded placement frame is a lost piece.
      'Ablagen verworfen $_discardedDeposits'
      // WHO FILLS THE CONTROL QUEUE (S381) — the five largest
      // enqueuers. B-2 had stood with the open question since 07.09.,
      // and about nine of ten enqueuings had no log line.
      ', Einreiher ${(egress.stream.controlReasons.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5)
          .map((e) => '${e.key}=${e.value}')
          .join(' ')}';

  /// The numbers of the SENDING SIDE of the bulk lane, if one is hooked in.
  ///
  /// A callback and not a field on the transport: that belongs to the
  /// IDENTITY, this node to the process (§9.3 — the holder role is
  /// node-wide, the transmissions are not). A pointer to the
  /// transport would pull the service layer into the delivery layer; a
  /// callback that returns a string does not.
  ///
  /// WHY IN THE STATUS LINE AT ALL: because the recurring defect
  /// of this migration is called "built, never trodden" and the counter-check
  /// is a number in the field log. Without it "does it place, does it sample,
  /// does a round run?" would be three times a guess.
  String Function()? bulkSenderStatus;

  /// The second drain of this identity, if one is hooked in.
  ///
  /// **The node does NOT OWN it** — it belongs to the
  /// `V41MediaBulkTransport`, and that belongs to the identity (§9.3: the
  /// holder role is node-wide, the transmissions are not). Here
  /// stands only a pointer for the status line, so that the depth of the
  /// second drain is visible in the field log like that of the
  /// control queue. Set in `attachV41`.
  BulkEgress? bulkEgress;
}
