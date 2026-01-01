import 'package:cleona/core/tagline/partner_policy.dart';
import 'package:cleona/core/config/network_channel.dart';
import 'dart:async';
import 'dart:io';

import '../link/node_keys.dart';
import 'entry_portal.dart';
import 'package:cleona/core/sync/entry_record.dart';
import 'entry_sources.dart';
import 'lan_entry.dart';
import 'v41_node.dart';

/// Step 2 of the entry cascade (§11.1), wired.
///
/// WHY THIS FILE EXISTS. For forty lines the wiring stood
/// exclusively in the lab program `bin/cleona_v41_node.dart`. The app called
/// `attachV41`, which started the node — but not its entry.
/// Result in the field (measured on the phone, 2026-08-22): port 41340 does not
/// appear in the log, the node neither calls nor listens, and so never finds
/// a partner. Without a partner `verifiedRelays == 0`, so
/// `readiness.state` is `searching`, and `V41Node.send` aborts BEFORE it
/// looks at the mode — Speed just like Secure. The device could not send a
/// single small message.
///
/// That is the same type of defect as `attachV41`, which at first no one called,
/// and as the Nostr provider that the clean-up disconnected. It arises
/// the same way every time: something is built in the lab, used there, and the app
/// never gets it. That is why the wiring now lives HERE and is called from
/// both sides — copying would only have moved the drift.
///
/// What does NOT happen here: step 1 (storage from the last run) and
/// step 3 (people, doors, external). Those have their own sources (§11.3).
/// Addresses that are called by unicast IN ADDITION to the broadcast.
///
/// Handed in, not determined here: where a node knows addresses
/// from (bootstrap configuration, learned V3 peers, a supply across
/// the restart) is the business of the layer above. See `rufen()`.
typedef EntryHintSource = List<EntryHint> Function();

Future<LanEntryHandle> startLanEntry({
  required V41Node node,
  required NodeKeys keys,
  required int dataPort,
  int intervalSeconds = 30,
  void Function(String)? log,
  EntryHintSource? hints,
}) async {
  // ── ONE SENDER, TWO LISTENERS, NO WILDCARD (S372) ─────────────────
  //
  // UNTIL S372 THIS SAID: a call socket bound to `InternetAddress.anyIPv4`,
  // thus reachable on UDP/41340 from the whole internet, and
  // an ephemeral entry socket next to it. The wildcard bind was what
  // made the directed entry from afar work at all —
  // and exactly for that reason it was the hole: a block rule on 41340 kills
  // step 3 network-wide, and whoever answers there is recognised
  // as a Cleona node.
  //
  // MEASURED what Dart offers here (Linux, 06.09.2026, three bindings
  // against four delivery kinds):
  //
  //     Binding to 192.168.10.92  -> [UNICAST]
  //     Binding to 239.192.67.76  -> [MCAST]
  //     Binding to 192.168.10.255 -> [SUBNET]
  //     Binding to 255.255.255.255-> [LIMITED]
  //     Binding to 0.0.0.0        -> [LIMITED, MCAST, SUBNET, UNICAST]
  //
  // Binding to an interface address thus loses broadcast AND
  // multicast and is therefore not a way. Binding to the GROUP and to
  // the LIMITED BROADCAST together covers exactly the two channels
  // on which the call is sent — and does not accept UNICAST.
  // A datagram from the internet to `our-ip:41340` thus finds
  // no receiver.
  //
  // SENDING happens over the ephemeral socket. The call carries the
  // entry port in the frame (`buildAnnounce`), so the receiver does
  // not answer to the source port of the call — the separation from S349 („two
  // nodes on one machine, SO_REUSEPORT distributes by hash")
  // is preserved without a second sender being needed.
  final entrySock =
      await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  entrySock.broadcastEnabled = true;
  try {
    entrySock.multicastHops = kLanEntryMulticastHops;
  } catch (e) {
    log?.call('LAN: multicast range not set ($e)');
  }

  final listener = <RawDatagramSocket>[];
  var wildcardFallback = false;

  // (a) The multicast group. Join PER INTERFACE — on a
  // machine with WLAN, bridge and virtual network, a join
  // without specification hits exactly one of them, and which one is decided by the
  // routing table.
  try {
    final m = await RawDatagramSocket.bind(
        InternetAddress(kLanEntryMulticastV4), kLanEntryPort,
        reuseAddress: true, reusePort: true);
    var joined = 0;
    try {
      for (final iface in await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4)) {
        try {
          m.joinMulticast(InternetAddress(kLanEntryMulticastV4), iface);
          joined++;
        } catch (_) {
          // One interface fewer is no disaster.
        }
      }
    } catch (_) {
      // Enumeration during an interface change — silent (E-83).
    }
    if (joined == 0) {
      try {
        m.joinMulticast(InternetAddress(kLanEntryMulticastV4));
        joined = 1;
      } catch (e) {
        log?.call('LAN: multicast group not joined ($e) — the call '
            'reaches only the own segment');
      }
    }
    listener.add(m);
  } catch (e) {
    log?.call('LAN: group address not bindable ($e)');
  }

  // (b) The limited broadcast. Measured on Linux; on platforms that
  // reject a binding to `255.255.255.255`, exactly this channel
  // drops out and multicast carries alone.
  try {
    listener.add(await RawDatagramSocket.bind(
        InternetAddress('255.255.255.255'), kLanEntryPort,
        reuseAddress: true, reusePort: true));
  } catch (e) {
    log?.call('LAN: limited broadcast not bindable ($e) — '
        'the call runs via the multicast group');
  }

  // (c) THE FALLBACK, and it is named instead of concealed. If on
  // a platform NEITHER of the two bindings comes about, the node would be
  // deaf in its own segment — worse than the hole being
  // closed here. Then it does bind the wildcard. The second
  // gate applies even then: `LanEntryService.sourceAllowed` discards
  // every publicly routable source BEFORE any interpretation, so
  // still no answer goes outside. What remains in this case is
  // only that a scanner from outside can distinguish „port bound" from „port closed"
  // (no ICMP port-unreachable).
  if (listener.isEmpty) {
    wildcardFallback = true;
    listener.add(await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, kLanEntryPort,
        reuseAddress: true, reusePort: true));
    log?.call('LAN: neither group nor broadcast bindable — fallback to '
        'the wildcard. Foreign sources are still discarded '
        '(sourceAllowed), but the port is visible from outside.');
  }

  // AN UNREACHABLE TARGET MUST NOT KILL THE PROCESS.
  //
  // Both senders run from `rufen()`, and that hangs on a
  // `Timer.periodic` (below). What throws here throws in a
  // timer callback — there is no caller that could catch it, so
  // it lands at the `PlatformDispatcher` and ends the application.
  //
  // In the field on 2026-08-29 it happened exactly like this twice (`errno 97`,
  // address family), and once on the same day with `errno 101` („Network is
  // unreachable") from the same call. The address family is fixed with the filter
  // in `vorratUnicastTargets` — but it was only the occasion. The
  // bug is that ONE unreachable target among several takes the
  // whole node down: a machine changes network, an address
  // from the supply is not routable from here, an interface goes
  // away — all normal situations, all with the same outcome.
  //
  // COUNTED, NOT CONCEALED: the first failure per run is in the
  // log. Discarding silently would be the other half of the same
  // bug — then no one would find out why the call achieves nothing.
  var stillFailed = 0;
  int safeSend(
      RawDatagramSocket sock, List<int> data, String host, int p) {
    try {
      return sock.send(data, InternetAddress(host), p);
    } on SocketException catch (e) {
      if (stillFailed == 0) {
        log?.call('LAN: call to $host:$p not possible ($e) — '
            'skipped, the tick continues');
      }
      stillFailed++;
      return 0;
    } on ArgumentError catch (e) {
      // `InternetAddress(host)` throws on an unusable string.
      // That too is one target fewer, no reason to stop.
      if (stillFailed == 0) {
        log?.call('LAN: target "$host" unusable ($e) — skipped');
      }
      stillFailed++;
      return 0;
    }
  }

  // ── ONE ACCEPTANCE POINT FOR BOTH PATHS ───────────────────────────
  //
  // Call (step 2) and portal (step 3) bring the same object:
  // a checked `EntryRecord`. What happens with it — discarding the self-echo,
  // putting it into the supply, dialling if applicable — may exist
  // only ONCE; two versions would be two answers to one
  // question and would drift apart.
  // The portal is only built further below (it needs `nimmDatensatz`
  // as callback), and `nimmDatensatz` needs it. NULLABLE instead of `late
  // final`: a `LateInitializationError` would hit here from a
  // socket callback and take the process with it — the same class of bug
  // the block at `sicherSenden` warns about. `null` simply means
  // „no portal yet", and then there is no hint to resolve either.
  EntryPortal? portalRef;

  void takeRecord(EntryRecord r, String origin) {
    // One hears one's own call too — normal with broadcast.
    var self = true;
    for (var i = 0; i < 32; i++) {
      if (r.lNode[i] != keys.lNode[i]) {
        self = false;
        break;
      }
    }
    if (self) return;
    // ── A RESOLVED HINT COSTS NO SECOND REQUEST (S377) ──
    //
    // The second portal attempt exists so that a LOST
    // datagram does not kill the hint — not to ask a node
    // one has just obtained by another path. If
    // the same host came in via the LAN call, the hint is done,
    // and the 1200 B of the second attempt would be traffic without benefit
    // (work rule #5). BEFORE `remember`, because the supply can also reject the
    // record (full, expired) — the hint is resolved
    // anyway, we have its checked record in hand right
    // now.
    for (final a in r.addresses) {
      portalRef?.markResolved(EntryPortal.hintKey(a.host, a.port));
    }
    if (!node.entries.remember(r, source: origin)) return;
    node.onEntriesChanged?.call();
    log?.call('$origin: node found ${r.host}:${r.port} — '
        'record checked');
    if (node.hasSessionWith(r.lNode)) return;
    if (!node.wantsPartner(r)) {
      log?.call('$origin: enough partners (${node.partnerCount}/'
          '${node.policy.target}) — not dialled');
      return;
    }
    // ── MAKING ROOM FOR THE WEAKER ADDRESS FAMILY (§11, S378) ────
    //
    // `wantsPartner` says „yes" to a v6 candidate even if all
    // four places are taken by v4 — only until today NO ONE made
    // room. The candidate was wanted and never admitted, and the
    // share of the weaker family kept sinking. Exactly against that
    // §11 provides the countermeasure; `PartnerPolicy.evictFor` and
    // `weakerShare` were built for it and had no caller.
    //
    // Eviction happens only under the four conditions in
    // `V41Node.verdraengeFuer` — in particular never a dual-stack neighbour,
    // which is precisely the translator between the families.
    if (node.partnerCount >= node.policy.target) {
      final victim = node.evictFor(familyOfRecord(r));
      if (victim == null) {
        log?.call('$origin: no slot and none to give up — '
            '${r.host}:${r.port} not dialled');
        return;
      }
      log?.call('$origin: made room for the weaker address family '
          '(${familyOfRecord(r).name}) — one partner of the strong family '
          'disconnected (§11)');
      node.separatePartner(victim);
    }
    if (!node.shouldDial(r.lNode)) {
      log?.call('$origin: the other side dials (smaller position there)');
      return;
    }
    // VIA THE RECORD, NOT VIA ITS FIRST ADDRESS (S373). Here
    // stood `knoten.connect(r.host, r.port)` — and `r.host`/`r.port` are
    // `addresses.first`. The LAN call regularly brings dual-stack
    // records (a device in the segment usually has both families); of
    // those, exactly one address was tried so far. Reasoning and
    // field measurement at `dialAddressOrder`.
    unawaited(node.dialRecord(r));
  }

  final service = LanEntryService(
    // BOTH over the ephemeral socket — the listening sockets are bound to
    // group or broadcast addresses and are unfit as
    // sender (the source address would not be a unicast address).
    sendBroadcast: (data, host, p) =>
        safeSend(entrySock, data, host, p),
    sendUnicast: (data, host, p) =>
        safeSend(entrySock, data, host, p),
    ownRecord: () => node.ownEntry,
    ownDataPort: dataPort,
    ownEntryPort: entrySock.port,
    onRecord: (r) => takeRecord(r, 'lan'),
    // ── DIAGNOSTICS: LOUD IN THE BETA CHANNEL, SILENT IN LIVE (owner, 09.09.2026)
    //
    // The LAN entry was completely silent until today. For the
    // layer that is supposed to carry the cold start WITHOUT a boost, that is too
    // little: on 09.09. it took socket, multicast and
    // probe measurements just to see that it runs.
    //
    // Only `cleona-beta`. The calls come every 30 s and name
    // neighbour addresses; in the shipped version that would be noise
    // with personal reference and no benefit. The owner on 09.09.:
    // „especially in the beta version, that can then be dropped in the live version
    // later".
    diag: activeNetworkChannel == NetworkChannel.beta
        ? (line) => log?.call(line)
        : null,
    // ── THE CAPABILITY BYTE (S373) ────────────────────────────────
    //
    // A callback and not a value: the claim must be true at the time of
    // EVERY call. A value set once would still stand there
    // when the internet leg is long gone — and then this
    // node would draw neighbours onto a path that no longer exists.
    ownCaps: () => node.ownLanCaps(),
  );

  // And the opposite direction: what the neighbours claim co-decides
  // whom this node dials first when it cannot get out itself
  // (`V41Node._mitRelaisVorrang`). Handed in as a callback so that the
  // node does not have to know the call service.
  node.uplinkHints = () => service.uplinkNeighbours.toSet();

  // ── STEP 3 ON THE DATA PORT (§11.3 row C, S372) ───────────────
  //
  // The directed entry no longer runs over the fixed call port,
  // but over the port that the hint names — and that is the
  // DATA port of the other side. It is therefore received there, behind the
  // demux of the link layer, in the `unclaimed` branch: a datagram that is neither
  // flight 1 nor flight 2 nor the cell of an existing session.
  //
  // SENDING happens over the node's sockets, not over the
  // entry socket. The other side answers to the source address, and
  // that must be the data port: only it is announced in the record and
  // only it survives a NAT mapping that the handshake uses right
  // afterwards.
  final portal = EntryPortal(
    sendUnit: (unit, host, p) {
      try {
        node.host.sockets.send(unit, InternetAddress(host), p);
      } on SocketException catch (e) {
        if (stillFailed == 0) {
          log?.call('Portal: request to $host:$p not possible ($e)');
        }
        stillFailed++;
      } on ArgumentError catch (e) {
        if (stillFailed == 0) {
          log?.call('Portal: target "$host" unusable ($e)');
        }
        stillFailed++;
      } on StateError catch (e) {
        // `UdpSocketSet.send` throws if the address family is not
        // bound (IPv6 hint on an IPv4-only node).
        if (stillFailed == 0) {
          log?.call('Portal: no socket family for $host ($e)');
        }
        stillFailed++;
      }
    },
    ownRecord: () => node.ownEntry,
    onRecord: (r) => takeRecord(r, 'person'),
  );
  portalRef = portal;
  node.host.demux.onUnclaimed = (dg) =>
      portal.receive(dg.data, dg.source.address, dg.sourcePort);

  void listen(RawDatagramSocket sock) {
    sock.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;
      service.receive(dg.data, dg.address.address, dg.port);
    });
  }

  for (final h in listener) {
    listen(h);
  }
  listen(entrySock);

  void call() {
    // THE CALL CYCLE IS THE CLOCK OF THE SECOND ATTEMPT (S377). The portal
    // has no timer and is not to get one — it counts what
    // this line tells it. At the very top so that every path through `rufen()`
    // advances the cycle equally.
    portal.tick();

    // ── THE RATE LIMIT REPORTS BEFORE IT FORGETS (S376) ───
    //
    // The overall cap of the portal turns a flood into a BOUNDED
    // load instead of a memory leak — but a bounded load that
    // no one sees cannot be told apart from a broken portal:
    // in both cases an honest asker gets
    // no answer. That is why a line goes into the log here as soon as anything at all
    // was rejected in the elapsed window.
    //
    // ONLY THEN. In the normal case — and that is every run without a flood —
    // this place is silent; a timer that writes a line every 30 s
    // would be noise without statement.
    //
    // No network traffic (work rule #5): this is a log line, not a
    // datagram. And it stands BEFORE `resetRateLimit`, because the counters
    // are at zero afterwards.
    final perSource = portal.rejectedSource;
    final inWindow = portal.rejectedWindow;
    if (perSource > 0 || inWindow > 0) {
      log?.call('Portal: rate limiting rejected in the last window '
          '$perSource request(s) at the per-source cap and $inWindow at the '
          'total cap; ${portal.trackedSources} source address(es) '
          'tracked (maximum ${EntryPortal.maxAnswersPerWindow}). '
          '${inWindow > 0 ? "The total cap applies — honest "
              "first contacts can fail along with it in this time." : ""}');
    }
    portal.rejectedSource = 0;
    portal.rejectedWindow = 0;

    // ── WHAT ARRIVED ON THE RECEIVING SIDE (S382) ────────────────────────
    //
    // The line above says what the RATE LIMIT rejected.
    // It says nothing about whether anything arrived at all — and exactly that
    // was the question on 12.09.2026 that cost an hour: Alice
    // and the Windows VM asked each other directly for their
    // entry record, both got no answer, and from the logs
    // it could not be decided whether the packets never arrived or were silently
    // discarded.
    //
    // THREE NUMBERS THAT SEPARATE THIS:
    //   received         anything arrived at all?
    //   not opened       arrived, but readable under no hour key
    //                    — wrong channel, wrong hour, or
    //                    simply a foreign datagram on the data port
    //   answered         arrived, read, record handed out
    //
    // ONLY IF SOMETHING ARRIVED. A node that no one asks writes
    // nothing here — the same rule as one line above, for the same reason.
    if (portal.receiveIncoming > 0) {
      log?.call('Portal received: ${portal.receiveIncoming} unit(s), '
          'of which ${portal.notOpened} could not be opened, '
          '${portal.answered} answered, ${portal.dropped} '
          'discarded');
    }
    portal.receiveIncoming = 0;
    portal.notOpened = 0;
    portal.answered = 0;
    portal.dropped = 0;

    service.resetRateLimit();
    portal.resetRateLimit();
    // ── THE CALL IS BROADCAST AND MULTICAST, NOTHING ELSE (S372) ─────
    //
    // UNTIL S372 unicast calls additionally went to every address from the
    // supply and to every ContactSeed hint — on `kLanEntryPort`, every
    // 30 s, also to public addresses. That was the second path by
    // which the fixed port left the LAN, and it is gone without replacement:
    //
    //  * An address FROM THE SUPPLY we have together with its record. One does not
    //    have to call to it, one dials it (`dialFromEntries`) — the
    //    unicast call to it was redundant.
    //  * A HINT from a person gets, since S372, a directed
    //    portal request on ITS port, exactly once per hint
    //    instead of every 30 s. B-27 (guest WLAN without broadcast forwarding)
    //    thus remains served and is even served better: the portal
    //    fetches the record of the other side, whereas the call only made us
    //    known.
    //
    // The number of messages drops as a result (work rule #5): „per
    // target one datagram every 30 seconds, indefinitely" becomes „per hint
    // one request, once".
    service.announce(const ['255.255.255.255', kLanEntryMulticastV4]);

    // And the hints. `EntryPortal.ask` decides by itself whether a
    // datagram results: the first attempt, after
    // `EntryPortal.retryAfterTicks` ticks without an answer exactly ONE
    // second, then silence. This tick is the trigger, not a
    // retry cycle — the cap lies at
    // `EntryPortal.maxAttemptsPerHint` = 2 requests (2400 B) per hint
    // over its whole lifetime.
    final beforeRepeated = portal.repeated;
    final beforeRejected = portal.rejectedTable;
    for (final h in hints?.call() ?? const <EntryHint>[]) {
      if (portal.ask(h)) {
        log?.call('Portal: record requested from ${h.key} '
            '(hint, §11.3 step „human")');
      }
    }
    final newRepeated = portal.repeated - beforeRepeated;
    if (newRepeated > 0) {
      log?.call('Portal: $newRepeated hint(s) asked a second and last time after '
          '${EntryPortal.retryAfterTicks} ticks without answer '
          '(${portal.wentSilent} gone silent)');
    }

    // ── THE SECOND CAP REPORTS THE SAME WAY (S377, proposal S-1) ────
    //
    // The counterpart of the line above at the rate limit, with
    // the same reasoning and for the same case: `maxTrackedHints`
    // turns a flood of hints into a BOUNDED load instead of a
    // growing table — but a bounded load that no one sees
    // cannot be told apart from a broken portal. If more
    // than `EntryPortal.maxTrackedHints` hints pile up, some remain
    // WITHOUT a request: a first contact fails, and without this line
    // nothing about it would be in the log. `abgewiesenTabelle` carried the
    // promise „Counted and not concealed" and until here had
    // no reader apart from its own incrementer.
    //
    // AS A DELTA OVER THE ROUND, not as an absolute value: unlike the
    // two window counters of the rate limit, `abgewiesenTabelle` is
    // reset nowhere (the cap has no window, it applies
    // always). A `> 0` on the absolute value would repeat the line from the
    // first rejection on in EVERY round — exactly the noise that
    // the line above explicitly avoids. The same pattern as two
    // lines above at `wiederholt`.
    //
    // ONLY ON REAL REJECTION. In regular operation this place is silent:
    // the only source in `lib/` is `personEntryHints` with
    // `EntryHintStore.max = 16`, a quarter of the cap.
    //
    // No network traffic (work rule #5): a log line, no
    // datagram, no cycle of its own — it hangs on the existing call.
    final newRejected = portal.rejectedTable - beforeRejected;
    if (newRejected > 0) {
      log?.call('Portal: $newRejected hint(s) NOT asked — the '
          'hint table is full (${portal.trackedHints} of '
          '${EntryPortal.maxTrackedHints} tracked). An honest '
          'first contact may fail in this round as well.');
    }
  }

  call();
  final tick =
      Timer.periodic(Duration(seconds: intervalSeconds), (_) => call());
  log?.call('LAN search active: call on $kLanEntryPort '
      '(${listener.length} listening socket(s)'
      '${wildcardFallback ? ", WILDCARD FALLBACK" : ""}), '
      'entry on ${entrySock.port}, every ${intervalSeconds}s');

  return LanEntryHandle._(
      service, portal, listener, entrySock, tick, call,
      // DETACH ON SHUTDOWN, as `V41Node.stop` does with
      // `demux.dAdmission`. A portal that still hangs on the demux after the
      // service has been shut down answers requests with the
      // record of a node that is just being torn down.
      () {
        node.host.demux.onUnclaimed = null;
        // AND THE RELAY HINT (S373). It points to the call service that
        // is being shut down here; if it stayed, dialling would sort
        // by neighbours no one hears from any more.
        node.uplinkHints = null;
      });
}

/// The running parts, so that a caller can stop them again. The daemon
/// runs until process end and does not need this; the app on Android
/// does, when the service is shut down.
final class LanEntryHandle {
  LanEntryHandle._(this.service, this.portal, this._listener, this._entry,
      this._tick, this._call, this._depend);

  final LanEntryService service;

  /// Step 3: the directed entry over the data port (S372).
  final EntryPortal portal;

  final List<RawDatagramSocket> _listener;
  final RawDatagramSocket _entry;
  final Timer _tick;
  final void Function() _call;
  final void Function() _depend;

  /// The ephemeral port on which directed entry answers of the
  /// LAN call arrive.
  int get entryPort => _entry.port;

  /// Calls IMMEDIATELY, outside the cycle.
  ///
  /// ── WHAT FOR, WHEN THE CYCLE IS RUNNING ANYWAY (S360) ───────────────
  ///
  /// For the network change. The cycle calls every 30 s; after a change from
  /// WLAN to mobile that is up to 30 s in which the node exists for no one
  /// in the new segment — and at the same time the 30 s in which
  /// its mail can go nowhere, because all sessions were in the old network.
  /// That is exactly the window in which a user says „it doesn't
  /// work".
  ///
  /// NO ADDITIONAL PATTERN ON THE WIRE: the call is the same as that of the
  /// cycle, with the same targets, and it replaces none — it is added once,
  /// at a point where an observer sees the network change anyway
  /// (the address has changed).
  ///
  /// ── AND IT FORGETS WHOM IT HAS ALREADY ASKED (S372) ───────────────
  ///
  /// Both memo lists — that of the call and that of the portal — record
  /// which endpoint has already been asked, so that a repeated
  /// cycle does not trigger a repeated request. After a NETWORK CHANGE
  /// this memory is wrong: the same address may belong to someone else,
  /// and above all the other side has never seen our new source address.
  /// `LanEntryService.forgetAsked` had been ready for this since S349
  /// and had in `lib/` **not a single caller** — measured
  /// 06.09.2026; a node that changed WLAN asked no one in its
  /// new segment whom it had already asked once in the old
  /// one.
  void announceNow() {
    service.forgetAsked();
    portal.forgetAsked();
    _call();
  }

  /// Asks the named hints for their entry record — each
  /// exactly once, over the port that the hint names.
  ///
  /// ── WHAT FOR, WHEN THE CALL EXISTS ANYWAY (§11.3 row C) ──────────────
  ///
  /// The call (`announce`) only says „here is a node". The other side
  /// hears it, asks BACK and thereby learns US — so the record travels
  /// in the wrong direction. For a neighbour in the segment that is
  /// equivalent: it calls itself, and its call arrives. For an
  /// entry hint from a ContactSeed it is NOT — the host
  /// stands somewhere in the network, its broadcast never reaches us, and whoever
  /// sits behind NAT is not dialled back by it either.
  ///
  /// ── AND WHY NO LONGER ON 41340 (S372) ──────────────────────────
  ///
  /// Until S372 this request went to the host's fixed `kLanEntryPort`,
  /// and the host had to bind the wildcard for it. That was a second
  /// fixed point next to the one that B-24 knowingly accepts:
  /// switchable off network-wide with one block rule, and every responder
  /// recognisable as a Cleona node. The port is in the hint; it is now
  /// used.
  int askHints(Iterable<EntryHint> hints) {
    var n = 0;
    for (final h in hints) {
      if (portal.ask(h)) n++;
    }
    return n;
  }

  void stop() {
    _tick.cancel();
    _depend();
    for (final h in _listener) {
      h.close();
    }
    _entry.close();
  }
}
