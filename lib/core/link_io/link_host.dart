/// The V4 node host: sockets, bind side, connect side, demux — one process,
/// no V3 module.
///
/// **Why this exists at all.** Measured on 2026-08-19, V4 was a library
/// without a caller: of the twelve modules under `lib/core/link/` exactly
/// one was imported from outside, and `lib/core/field/` had no importer at
/// all. The question was never how to wire the link layer to
/// `lib/core/network/transport.dart` — it was that there was no V4 node.
/// This file is that node (way D). `transport.dart` stayed untouched and
/// was **deleted** at the lab gate, not rebuilt — that happened on
/// 2026-08-31 (CUT); `lib/core/network/` holds zero files, measured
/// 2026-09-03.
///
/// **Scope of the first milestone (E-102).** `udpOwnPort`, one address, two
/// processes on one machine, handshake plus one cell in each direction.
/// Deliberately absent: `tcpOwnPort`, `tcp443`, `icmpKnock`, the disguise,
/// the `cold`/`planting`/`ready` state machine, the entry record, and the
/// tick. Each omission has a reason recorded there; none of them is an
/// oversight.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/link/connect.dart';
import 'package:cleona/core/link/connect_state.dart';
import 'package:cleona/core/link/handshake.dart';
import 'package:cleona/core/link/node_keys.dart';
import 'package:cleona/core/link/replay_buffer.dart';
import 'package:cleona/core/link/transport_selector.dart';
import 'package:cleona/core/link_io/link_demux.dart';
import 'package:cleona/core/link_io/tcp_connector.dart';
// Re-exports LinkAddressFamily, LinkDatagram, LinkNoFamilyBound and
// UdpSocketSet — that is why there is no second import of udp_sockets.dart here.
import 'package:cleona/core/link_io/udp_binder.dart';

/// The public node material an initiator needs to open a link.
///
/// **This is the entry record's payload, and the entry record does not
/// exist.** Measured 2026-08-19 and unchanged: it has no declaration site
/// anywhere in the tree — no type, no protobuf message, no serialisation,
/// no constant list; `lib/core/sync/`, to which V4 §20.4 assigns it, was
/// never created. Guard 6 cannot be built for the same reason, and both
/// belong to AP-3b.
///
/// Until then the material reaches the connect side **out of band**. That
/// is honest for a lab milestone and dishonest to hide: a node cannot cold
/// start with this, it can only talk to a peer someone told it about.
final class PeerNodeMaterial {
  /// The peer's `L_node` — the MAC key of the `init` flight (§2.6).
  final Uint8List lNode;

  /// The peer's static X25519 node key; `k_prov` of flight 1 (E-82).
  final Uint8List x25519Public;

  /// The peer's static ML-KEM-768 node key (E-82).
  final Uint8List mlKemPublic;

  const PeerNodeMaterial({
    required this.lNode,
    required this.x25519Public,
    required this.mlKemPublic,
  });
}

/// Where the connect side gets a peer's node material from.
typedef PeerLookup = PeerNodeMaterial? Function(LinkEndpoint peer);

/// What several partners have said about the own outer address
/// (§17.3 "observed address" instead of STUN).
///
/// **Why this is a book and not a variable.** An observation is the
/// statement of ONE partner, and a node has many. Whoever writes them into a field
/// has lost the first after the second handshake and does not know
/// that he has lost it. If two statements contradict each other, that is
/// the textbook finding of a **symmetric NAT** (§17.3: every
/// peer gets its own port assignment) — and §17.3 builds on
/// exactly this finding, both with the port prediction
/// ("±10 ports around the last observed") and with the honest
/// refusal ("no call possible"). A construction that averages away the contradiction
/// takes away from the layer above the decision that belongs
/// to it.
///
/// **The families stay separate**, because §17.3 demands it ("both
/// families kept separate"): an IPv4 and an IPv6 observation are not a
/// contradiction but two candidates.
///
/// **Trust.** The mirror lies in the AEAD of flight 2, so a third party
/// cannot bend it — the partner himself very well can. That is why
/// [agreed] is deliberately strict: it only answers if ALL partners of this
/// family say the same. A single lying partner thus produces
/// no false candidate but a visible contradiction.
final class ObservedAddressBook {
  /// Upper limit of held partners — the same number as the
  /// session table of the demux ([LinkDemux.maxSessions], from there E-89).
  /// It stands here for the same reason: the key is a FOREIGN
  /// address, and what grows by foreign address grows without limit
  /// if nobody sets a cap.
  final int maxPartners;

  /// Statement per partner, in insertion order (Dart `Map` promise). The
  /// youngest statement of a partner replaces his older one — it is the newer
  /// state on the same question, not a second opinion.
  final _byPartner = <String, _Observation>{};

  ObservedAddressBook({this.maxPartners = LinkDemux.maxSessions});

  /// The EDGE: called when the UNANIMOUS statement of a family
  /// changes — not on every observation (S373).
  ///
  /// **Why it exists.** The book only fills up AFTER the start, with
  /// every handshake this node opens itself. The announce address
  /// however is set at start (`setAnnounceAddresses`, two callers:
  /// start and network change). Without this edge the
  /// entry record does not carry an outer address learned later until the
  /// next network change — and on a
  /// desktop there is no network change for days.
  ///
  /// **Why an edge and not a timer.** A timer polling the book
  /// would run even if nothing ever changes, and that is the
  /// normal case (working rule #5).
  ///
  /// **What does NOT report.** A second, identical statement — of the same
  /// or a further partner — does not change the unanimous address.
  /// If it reported, EVERY handshake would cost an entry record
  /// on the wire. The transition "unanimous -> contradictory" on the other hand
  /// very much reports: [agreed] then returns `null`, the address must disappear from the
  /// announcement, and exactly that the caller must learn.
  ///
  /// **[clearAll] expressly does NOT report.** It has exactly one
  /// caller, the network change (`V41Node.onNetworkChanged`), and this
  /// path resets the announcement itself anyway and announces it with priority.
  /// A second report from the same edge would be a second
  /// entry record on the wire for the same change.
  void Function()? onAgreedChanged;

  /// Records what [partner] has observed.
  void record(LinkEndpoint partner, ObservedAddress observed) {
    final before = _state;
    // First remove, then set: this way a repeating partner moves
    // to the end of the insertion order and the eviction really hits
    // the oldest entry.
    _byPartner.remove(partner.key);
    _byPartner[partner.key] = _Observation(partner, observed);
    while (_byPartner.length > maxPartners) {
      _byPartner.remove(_byPartner.keys.first);
    }
    final now = _state;
    if (now.v4 != before.v4 || now.v6 != before.v6) {
      onAgreedChanged?.call();
    }
  }

  /// The unanimous statement of BOTH families in one grab — exactly the
  /// quantity [onAgreedChanged] hangs on. Kept separate because
  /// §17.3 keeps the families separate: a new IPv6 observation must not
  /// touch a standing IPv4 announcement.
  ({ObservedAddress? v4, ObservedAddress? v6}) get _state =>
      (v4: agreed(ipv6: false), v6: agreed(ipv6: true));

  /// Forgets what [partner] has said.
  void forget(LinkEndpoint partner) => _byPartner.remove(partner.key);

  /// Forgets EVERYTHING — after a network change.
  ///
  /// **An old observation is worse than none after a network
  /// change.** What a partner in the WLAN said about the outer address of this
  /// node no longer applies on mobile data; [agreed] would
  /// however continue to output exactly this address — and indeed as
  /// free of contradiction, because all statements stem from the same, now dead
  /// network. §17.3 builds the punch window on these candidates;
  /// a unanimously wrong candidate is the most expensive form of
  /// wrong.
  void clearAll() => _byPartner.clear();

  int get partnerCount => _byPartner.length;

  /// Who said what — the raw form, for log and diagnostics.
  Map<LinkEndpoint, ObservedAddress> get observations => Map.unmodifiable({
        for (final o in _byPartner.values) o.partner: o.observed,
      });

  /// The different addresses named for this family.
  ///
  /// More than one is the NAT finding, not an error. The order is
  /// that of first naming.
  List<ObservedAddress> candidates({required bool ipv6}) {
    final out = <ObservedAddress>[];
    for (final o in _byPartner.values) {
      if (o.observed.isIpv6 != ipv6) continue;
      if (!out.contains(o.observed)) out.add(o.observed);
    }
    return out;
  }

  /// All candidates of both families, IPv4 first — the order that
  /// `dialableLocalAddresses()` keeps on the local half.
  List<ObservedAddress> get allCandidates =>
      <ObservedAddress>[...candidates(ipv6: false), ...candidates(ipv6: true)];

  /// The address of this family, **if all partners see it the same**.
  ///
  /// `null` with zero observations AND on contradiction. The caller who
  /// must distinguish both asks [candidates].
  ObservedAddress? agreed({required bool ipv6}) {
    final c = candidates(ipv6: ipv6);
    return c.length == 1 ? c.first : null;
  }

  /// Do two partners say different things about this family? (§17.3
  /// symmetric NAT)
  bool disagrees({required bool ipv6}) => candidates(ipv6: ipv6).length > 1;

  @override
  String toString() => 'ObservedAddressBook(${_byPartner.length} Partner, '
      'v4=${candidates(ipv6: false)}, v6=${candidates(ipv6: true)})';
}

final class _Observation {
  final LinkEndpoint partner;
  final ObservedAddress observed;
  const _Observation(this.partner, this.observed);
}

/// The injected outbound boundary of `Link.connect`, over UDP.
///
/// **It imposes no timeout of its own.** `Link.connect` owns the stage
/// timeout (§4.8, E-98); a second one here would silently take that
/// decision away from the layer that holds it.
///
/// **The sentence that used to follow was wrong, and it mattered (B-1).** It
/// read: "when the stage gives up, the pending slot in the demux ages out on
/// its own — that is why [LinkDemux.pendingLifetime] is the stage timeout".
/// Neither half held. `Link.connect` gives a stage up by discarding the
/// future without a signal, so nothing here ever learns of it; and the
/// demux's own ageing ran only when a datagram arrived, so on a quiet socket
/// the slot never aged at all — measured, 30 slots still standing after
/// their lifetime had passed twice over. The slot now carries a one-shot
/// timer of its own, which removes it **without touching the completer**:
/// it decides nothing about the attempt, so the timeout stays where §4.8
/// puts it. And the lifetime is a full cascade run, not a stage (V-C).
final class UdpLinkConnector implements LinkConnector {
  final UdpSocketSet sockets;
  final LinkDemux demux;
  final PeerLookup peers;
  final LinkLogSink log;

  /// The own node keys — only needed so that the caller can identify himself
  /// to the callee (decision C). If they are missing, this
  /// node calls anonymously.
  final NodeKeys? ownKeys;

  UdpLinkConnector({
    required this.sockets,
    required this.demux,
    required this.peers,
    required this.log,
    this.ownKeys,
  });

  @override
  Future<LinkAttempt> attempt(
      LinkEndpoint target, LinkTransport transport) async {
    if (transport.stage != TransportStage.udpOwnPort) {
      // A stage with no I/O is refused rather than left silent: silence
      // means "the network discarded it" and would cost the cascade a full
      // stage timeout for something this process knows immediately.
      return LinkRefused(
          'stage ${transport.stage.name} has no I/O in this build (E-102)');
    }
    if (transport.disguise != Disguise.bare) {
      return LinkRefused('disguise ${transport.disguise.name} is unspecified');
    }

    final material = peers(target);
    if (material == null) {
      return LinkRefused('no node material for ${target.key} — the entry '
          'record has no declaration site (AP-3b)');
    }

    final InternetAddress address;
    try {
      address = InternetAddress(target.host);
    } catch (e) {
      return LinkRefused('unparsable address ${target.host}: $e');
    }

    final pending = LinkHandshake.buildFlight1(
      lNode: material.lNode,
      nX25519Pub: material.x25519Public,
      nMlKemPub: material.mlKemPublic,
      // Fresh 32 B per handshake; `ElligatorFFI.keyPair` wipes the
      // buffer, so it must not be reused.
      seed: SodiumFFI().randomBytes(32),
      // We name our position. If the callee knows it, it goes into
      // the key and we are authenticated towards him;
      // if he does not know it, the call stays anonymous and still comes
      // about. The statement lies in the AEAD, an eavesdropper does not see it.
      claimPosition: ownKeys?.lNode,
      ownStaticX25519Secret: ownKeys?.nX25519Secret,
    );

    final future = demux.awaitFlight2(
      target: target,
      pending: pending,
      transport: transport,
      address: address,
      port: target.port,
      peerStatic: material.x25519Public,
    );

    try {
      sockets.send(pending.flight1, address, target.port);
    } catch (e) {
      demux.cancelPending(target);
      return LinkRefused('send failed: $e');
    }

    // No timeout here — see the class comment.
    try {
      final channel = await future;
      return LinkEstablished(channel);
    } on LinkPendingAbandoned catch (e) {
      // The marker was cleared before flight 2 came. `Link.connect` catches
      // only `TimeoutException`; anything else would tear down the whole cascade run.
      // Reported as a refusal the run escalates immediately — correct, because
      // no response will come to this attempt any more.
      return LinkRefused('handshake abandoned: ${e.reason}');
    }
  }
}

/// The composite connector of the escalation ladder (§11/§4.8, E-116; option B
/// of the proposal `docs/v4-redesign/S361-VORLAGE-tcp-lauscher.md`).
///
/// ── WHAT IT IS, AND WHY IT IS NOT A THIRD CONNECTOR ─────────────
///
/// It performs no I/O of its own. It forwards by STAGE: `udpOwnPort`
/// to the [UdpLinkConnector], `tcpOwnPort` to the [TcpLinkConnector].
/// Which rung comes next is still decided solely by
/// `Link.connect` via `nextStage` — there is no second answer here to
/// the same question (E-89).
///
/// ── WHAT IT CLOSES ────────────────────────────────────────────────
///
/// Of four rungs, until now exactly ONE was passable. `LinkHost.start`
/// built only `UdpLinkConnector`, and its `attempt` rejected every other
/// stage with `LinkRefused('… has no I/O in this build (E-102)')`
/// (:222). A node in a network that blocks outgoing UDP thus had
/// **zero** rungs — RL-15 verbatim: "no path at all". It was
/// not slow but not in the network: `readiness` stayed at
/// `searching`, and `V41Node.send` rejects before the mode branch.
///
/// ── THE TWO UPPER RUNGS REMAIN REFUSALS, AND IMMEDIATE ONES ──
///
/// `tcp443` and `icmpKnock` need build stage 5 (installer rule A-1,
/// `CAP_NET_RAW` **and** `CAP_NET_ADMIN`, §4d.8 finding 2). They are
/// **refused, not concealed** — for the same reason for which
/// `UdpLinkConnector.attempt` does it: silence would mean "the network has
/// discarded it" and would cost the run a full stage timeout for
/// something this process knows immediately. A refusal escalates "at
/// once — no wait" (§4.8).
///
/// A full failed run thus costs **2 × 1.5 s** (the two silent
/// lower rungs) plus two immediate refusals, not 4 × 1.5 s.
///
/// ── WHAT IT BRINGS ALONG, AND IT IS DECLARED ─────────────────────────
///
/// RL-15: where `tcpOwnPort` applies, a TCP wire profile lies over the
/// constant cell rate (§5) — connection setup, ACK cadence,
/// window development, retransmissions. That is the **declared price
/// of the stage**, not a regression: it is a fallback, not a normal path,
/// and it only applies where the alternative is no connection instead of
/// an inconspicuous one.
final class StagedLinkConnector implements LinkConnector {
  final UdpLinkConnector udp;
  final TcpLinkConnector tcp;

  const StagedLinkConnector({required this.udp, required this.tcp});

  @override
  Future<LinkAttempt> attempt(
      LinkEndpoint target, LinkTransport transport) async {
    switch (transport.stage) {
      case TransportStage.udpOwnPort:
        return udp.attempt(target, transport);
      case TransportStage.tcpOwnPort:
        return tcp.attempt(target, transport);
      case TransportStage.tcp443:
      case TransportStage.icmpKnock:
        return LinkRefused('stage ${transport.stage.name} has no I/O in '
            'this build (build stage 5, installer rule A-1)');
    }
  }
}

/// One V4 node: one socket set, one demux, one bind side, one connect side.
final class LinkHost {
  final UdpSocketSet sockets;
  final NodeKeys keys;
  final LinkDemux demux;
  final UdpLinkBinder binder;

  /// The outgoing side of the cascade — since the composite connector no
  /// longer the UDP rung alone but the switch over both
  /// built rungs ([StagedLinkConnector]).
  final LinkConnector connector;
  final LinkLogSink log;

  /// What partners have said about the outer address of this node
  /// (§17.3). Filled from every handshake this node opens **itself**
  /// — see [LinkSession.observedSelf] for the direction.
  final ObservedAddressBook observed;

  LinkHost._({
    required this.sockets,
    required this.keys,
    required this.demux,
    required this.binder,
    required this.connector,
    required this.log,
    required this.observed,
  });

  /// Brings the node up: binds `bare`, starts the demux.
  ///
  /// `bare` is bound through `Link.bind`, so the invariants of E-96, E-99
  /// and E-101 apply as written — a disguise that cannot bind falls away
  /// silently and logged, `bare` that binds in no family ends the start,
  /// and one family is enough.
  /// [sessionProofLifetime] is the deadline within which a freshly accepted
  /// session must show an opening cell (`LinkDemux.pendingLifetime`).
  ///
  /// WHY IT IS PASSED IN AND DOES NOT STAND HERE. The deadline measures
  /// how long one waits for a PROOF — and how fast a proof
  /// can come is known only to the layer above, which keeps the send
  /// timing. The default of the link layer is a full cascade run
  /// (4 x 1.5 s = 6 s); the cover timing however sends a cell only every 8 s
  /// (`kSlotInterval`). The deadline was thus shorter than the earliest possible
  /// proof, and EVERY accepted session was swept away before the partner
  /// was even allowed to send — measured on 25.08.: the passive side
  /// lost the session reproducibly after ~9 s, found the partner again,
  /// lost it again. Two constants, each correct on its own, never
  /// calculated against each other.
  static Future<LinkHost> start({
    required int port,
    required NodeKeys keys,
    required LinkLogSink log,
    PeerLookup? peers,
    StaticKeyLookup? lookupStatic,
    DateTime Function()? now,
    Duration? sessionProofLifetime,
    void Function(int bytes)? onWireBytesSent,
    void Function(int bytes)? onWireBytesReceived,
  }) async {
    // Handed to the constructor, NOT set on the returned set: `demux.start()`
    // below runs before this method returns, so a hook installed afterwards
    // would already have missed the first inbound datagrams. Bare function
    // references — see the field comment on [UdpSocketSet.onWireBytesSent],
    // which records why they stay bare now that section 5 of
    // `smoke_link_io_milestone` no longer covers the case (the stats
    // collector moved out of the V3 trees with the CUT of 2026-08-31).
    final sockets = UdpSocketSet(
      port: port,
      log: log,
      onWireBytesSent: onWireBytesSent,
      onWireBytesReceived: onWireBytesReceived,
    );
    final binder = UdpLinkBinder(sockets: sockets, log: log);
    final demux = LinkDemux(
      sockets: sockets,
      keys: keys,
      replay: LinkReplayBuffer(),
      log: log,
      now: now,
      pendingLifetime:
          sessionProofLifetime ?? LinkDemux.defaultPendingLifetime,
    )..lookupStatic = lookupStatic;

    // §17.3: the book hangs on the host, not on the demux. The demux sees ONE
    // statement per handshake and should not decide what several of them
    // mean; the host is the place where all links of this node
    // converge. Wired BEFORE `demux.start()`, for the same reason
    // for which the byte counters go into the socket set's constructor:
    // afterwards the first datagrams would already be through.
    final observed = ObservedAddressBook();
    demux.onObservedSelf = observed.record;

    // ── BOTH BUILT RUNGS, ONE SWITCH ──────────────────────────
    //
    // The host still gives `Link.connect` `udpOwnPort` as the START rung
    // (see [connect]); escalation happens via `nextStage`. The
    // composite connector is the place where the second rung
    // gets any I/O at all — previously `UdpLinkConnector.attempt` rejected
    // it, and the cascade had one of four rungs.
    //
    // THE SAME STORE, THE SAME KEYS. Both rungs look up the
    // peer's material via THE SAME function; two sources
    // would be two answers to one question. And both name the own
    // position (decision C), so that a session established over TCP
    // carries the same VERIFIED position as one over UDP — without it
    // nothing could be forwarded over it, and the deduplication
    // from E-119 (`V41Node.adopt`) would not see it.
    final lookup = peers ?? ((LinkEndpoint _) => null);
    final connector = StagedLinkConnector(
      udp: UdpLinkConnector(
        sockets: sockets,
        demux: demux,
        peers: lookup,
        log: log,
        ownKeys: keys,
      ),
      tcp: TcpLinkConnector(
        lookup: lookup,
        ownKeys: keys,
        // Fresh 32 B per handshake; `ElligatorFFI.keyPair` wipes the
        // buffer, a seed must never be reused. The same
        // line stands at the listener (`V41Node.start`) — the two halves
        // draw independently of each other.
        drawSeed: () => SodiumFFI().randomBytes(32),
        log: log,
        now: now,
      ),
    );

    await Link.bind(const <Disguise>{}, binder: binder, log: log);
    demux.start();

    return LinkHost._(
      sockets: sockets,
      keys: keys,
      demux: demux,
      binder: binder,
      connector: connector,
      log: log,
      observed: observed,
    );
  }

  /// This node's own material, as a peer would need it.
  ///
  /// Stands in for the entry record until that has a type (AP-3b).
  PeerNodeMaterial get ownMaterial => PeerNodeMaterial(
        lNode: keys.lNode,
        x25519Public: keys.nX25519Public,
        mlKemPublic: keys.nMlKemPublic,
      );

  LinkEndpoint endpointOn(String host) => LinkEndpoint(host, sockets.port);

  /// The families that came up. Never collapsed into one answer (E-101).
  Set<LinkAddressFamily> get families => sockets.families;

  /// Links a peer opened towards this node.
  Stream<UdpLinkChannel> get accepted => demux.accepted;

  /// The memory of the dial ladder (E-89) — per target the last
  /// SUCCESSFUL rung.
  ///
  /// ── WHY IT LIVES HERE AND NOT WITH THE CALLER (S376) ────────────
  ///
  /// `ConnectState` had been built since AP-3a step 3, documented and
  /// evaluated by `Link.connect` — and in `lib/` **never created**: measured
  /// on 08.09.2026 `grep -rn 'ConnectState(' lib/` found exactly the
  /// constructor itself, not a single `new`; in the test tree nine hits.
  /// The only caller of [connect] in `lib/`
  /// (`V41Node._versuchAdresse`, `v41_node.dart:5452`) passed no
  /// `state`. Every dial thus started again at `udpOwnPort`.
  ///
  /// MEASURED, WHAT THAT COSTS: in a network that blocks outgoing UDP,
  /// the first rung is SILENT — it costs the full stage timeout
  /// `kLinkStageTimeout` = 1.5 s, namely on EVERY attempt to EVERY
  /// target, even to a target that was reached a minute earlier via `tcpOwnPort`.
  /// A redial round (`dialFromEntries`, up to four
  /// records with up to two addresses each) thus burns up to 12 s
  /// waiting for a rung of which this node already knows
  /// that it does not carry here.
  ///
  /// ── PER TARGET, NOT PER NETWORK — AND WHY (E-89) ─────────────────────
  ///
  /// The entry key is the TARGET ADDRESS; E-89 fixes it that way
  /// (`connect_state.dart`, "Entry key: the target address"), and
  /// `Link.connect` looks up under `target.key`. That stays
  /// unchanged. A remembered stage PER NETWORK ("UDP does not work here at all")
  /// would be the greater saving — it also helps on the FIRST attempt
  /// to a new target — but it is a different statement from the one
  /// E-89 describes, and it is not silently introduced here.
  ///
  /// ── BUT IT FALLS WITH THE NETWORK ──────────────────────────────────
  ///
  /// Whether `tcpOwnPort` carries depends on the LOCAL network, not on the target: the
  /// block sits in the network in which this node currently is. Behind
  /// a network change the hint therefore no longer applies — the same
  /// justification for which [ObservedAddressBook.clearAll],
  /// `portMappingConfirmed` and `externalInboundProven` fall there
  /// (`V41Node.onNetworkChanged`). It is not a statement about the world,
  /// but about this location.
  ///
  /// A WRONG hint would be cheap anyway — `Link.connect` continues
  /// after the remembered rung with the others in cascade order
  /// (`_runOrder`), so it costs at most one attempt. That
  /// is the reason why it is cleared here and not tracked:
  /// the cost of an error is small, that of a bookkeeping error
  /// would not be.
  final ConnectState connectState = ConnectState();

  /// One cascade run against [target] (§4.8).
  ///
  /// [state] overrides the memory of this host — guards pass
  /// their own instance here to measure without a wall clock. `null`
  /// means: the host's memory, and that is the normal case.
  Future<LinkConnectResult> connect(LinkEndpoint target,
          {ConnectState? state}) =>
      Link.connect(
        target: target,
        transport: const LinkTransport(TransportStage.udpOwnPort, Disguise.bare),
        connector: connector,
        state: state ?? connectState,
      );

  Future<void> stop() async {
    await demux.close();
    await sockets.close();
  }
}
