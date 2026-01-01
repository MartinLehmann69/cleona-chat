/// The steps of the cold-start cascade that had NO source until S356.
///
/// ── WHAT IS FIXED HERE ────────────────────────────────────────────────
///
/// `ColdStart.order` names five steps (supply, LAN, human, doors,
/// external). Exactly ONE was wired: `v41_attach.dart` built the cascade
/// with `ColdStart(sources: [extern])`. Supply and LAN ran alongside and
/// outside the cascade, "human" and "doors" did not exist
/// at all.
///
/// That has three measurable consequences, and all three are silent:
///
/// 1. **The report does not lie, but it says nothing.** `ColdStartResult`
///    always reported "one step, zero skipped" — impossible to
///    distinguish from a complete cascade in which four steps
///    found nothing. Exactly that is what `UnbuiltSource` warns against in its own
///    class comment ("That is the difference between ‚nobody there' and
///    ‚not built'"), and exactly this class had zero
///    callers in `lib/`.
/// 2. **The external rendezvous ALWAYS ran.** §11.3 and the header of
///    `ColdStart` say "it stops at the first hit — every further
///    source costs and reveals something". With a single-element cascade
///    there is no first hit one could have made beforehand:
///    every start registered with foreign relays, even when the supply
///    was full and the neighbour in the segment answered. The price for that
///    is listed as B-24/RL-13 in the declared limits — it is to be paid
///    when it is necessary, not on every start.
/// 3. **The path the architecture calls "the normal one" did nothing.**
///    §11.3 row C: "A person — ContactSeed by QR, NFC or link — always,
///    and it is the normal way in". §15: "the peer list handed over in the
///    process becomes **entry hints** and serves exclusively the network
///    entry." Measured: `addPeersFromContactSeed` writes exclusively
///    to `node.routingTable` (V3) and does not touch `v41.entries` a
///    single time.
library;

import 'dart:async';

import 'package:cleona/core/sync/cold_start.dart';
import 'package:cleona/core/sync/entry_record.dart';

/// Step 1: what was already there.
///
/// The supply is loaded from disk in `startV41Node` BEFORE the
/// cascade runs. This source only reads it — it loads nothing more and
/// touches no network. That is why it is also the cheapest and comes first.
final class StoreEntrySource implements EntrySource {
  /// The dialable records of the supply.
  ///
  /// Deliberately a function and not the `EntryCache` itself: the caller
  /// decides whether it hands in `dialCandidates()` (fresh before expired,
  /// unfailed before deferred) or `all()`. The
  /// cascade should not know how a supply sorts.
  final List<EntryRecord> Function() candidates;

  const StoreEntrySource(this.candidates);

  @override
  EntrySourceKind get kind => EntrySourceKind.store;

  /// An empty supply is NOT "not available".
  ///
  /// The difference matters: `available == false` means "this step does not
  /// exist here" and is counted as skipped; an empty supply
  /// is a step that was asked and had nothing. Those are two
  /// different findings, and the report should be able to distinguish them.
  @override
  bool get available => true;

  @override
  Future<List<EntryRecord>> fetch() async => candidates();
}

/// Steps 2 and 3: what comes in via the directed entry call.
///
/// ── WHY THIS SOURCE WAITS INSTEAD OF FETCHING ─────────────────────────
///
/// The LAN entry is not a fetch, but a conversation: this node
/// calls (broadcast, multicast, unicast to known addresses), the
/// counterpart asks back, and only its answer carries the signed
/// record. That takes one round trip and runs via sockets that already
/// belong to someone else (`startLanEntry`).
///
/// A source that rebuilt that would have needed a second socket on the same
/// port — and exactly that is what `lan_entry_wiring.dart` warns against ("if
/// two nodes run on one computer, the kernel decides by hash value").
/// Therefore this source calls the running entry ([nudge]) and
/// then WATCHES the supply it writes into.
///
/// It delivers only what was added in ITS window. What was already in the
/// supply before belongs to step 1 — otherwise the same record would count twice
/// and the cascade would have "enough" without knowing a single new path.
final class DirectedEntrySource implements EntrySource {
  @override
  final EntrySourceKind kind;

  /// What the supply holds RIGHT NOW.
  final List<EntryRecord> Function() snapshot;

  /// What this step triggers before it waits. For `lan` the
  /// broadcast call, for `person` the directed requests to the
  /// entry hints of a ContactSeed.
  final FutureOr<void> Function() nudge;

  /// Whether the step has anything to trigger at all. A node without
  /// a running LAN entry or without a single hint reports itself
  /// as not available — and is counted, not concealed.
  final bool Function() usable;

  /// How long to wait for the FIRST answer.
  final Duration window;

  /// How long collecting continues after the first answer.
  ///
  /// ── WHY THIS SECOND WINDOW IS NEEDED (measured in the lab) ──────────
  ///
  /// The first version returned as soon as ONE record was there. In the
  /// lab run on 30.08. (four nodes in the same segment, plus two real
  /// test nodes) every report therefore said `lan:1/1` — the step
  /// reported exactly one path, the cascade thus never had "enough" (three
  /// different nodes) and asked the external rendezvous anyway:
  ///
  ///     `V4.1 Kaskade: store:0/0 lan:1/1 external:469/469`
  ///     `davon OHNE externe Stufe: 0`
  ///
  /// The answers were there — they only came in spread over several seconds,
  /// as the log immediately afterwards shows (five more
  /// "LAN: Knoten gefunden" within 10 s). Whoever stops at the first one
  /// measures the latency of the fastest neighbour and calls it the result
  /// of the step.
  ///
  /// The same pattern is used by `nostr_provider.dart` under the same name
  /// and for the same reason (`kResolveCollectWindow`, §4.11.11): "first
  /// hit opens the collect window; later hits from slower relays can still
  /// replace `best`".
  final Duration collectWindow;

  /// How often to check.
  final Duration pollEvery;

  DirectedEntrySource({
    required this.kind,
    required this.snapshot,
    required this.nudge,
    required this.usable,
    this.window = const Duration(seconds: 6),
    this.collectWindow = const Duration(milliseconds: 2500),
    this.pollEvery = const Duration(milliseconds: 250),
  });

  @override
  bool get available => usable();

  @override
  Future<List<EntryRecord>> fetch() async {
    final before = <String>{
      for (final r in snapshot()) _key(r),
    };
    await nudge();

    // Until the first answer the whole window; after that only the
    // collect window. A segment in which nobody is thus still costs
    // at most [window] — and one in which someone is
    // delivers not only the fastest.
    var end = DateTime.now().add(window);
    var fresh = <EntryRecord>[];
    var collects = false;
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(pollEvery);
      fresh = [
        for (final r in snapshot())
          if (!before.contains(_key(r))) r,
      ];
      if (fresh.isNotEmpty && !collects) {
        collects = true;
        final collectEnd = DateTime.now().add(collectWindow);
        // NEVER EXTEND, only shorten: if the first answer came shortly
        // before the window end, the collecting must not pull the start beyond the
        // promised upper bound.
        if (collectEnd.isBefore(end)) end = collectEnd;
      }
    }
    return fresh;
  }

  static String _key(EntryRecord r) =>
      r.lNode.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// ONE entry hint: host AND port.
///
/// ── WHY THE PORT COMES ALONG (S372, owner decision) ───────────────────
///
/// Until S372 [EntryHintStore.add] threw away the port and justified that
/// by saying the directed entry always runs "on the fixed
/// `kLanEntryPort`". Exactly that was the error: a second fixed port
/// that applies to EVERY node can be killed network-wide with ONE blocking rule
/// and makes every node recognisable from afar. RL-14 names
/// the property that contradicts this — "no well-known port, no
/// designated relay"; B-24 declares EXACTLY ONE fixed point
/// bearable, and that is the external cold-start source, not this one.
///
/// The right port lay in the data all the time: a ContactSeed
/// names its addresses as `ip:port`, and this port is the
/// V4.1 data port of the counterpart (`link/data_port.dart`, 10000-64999 drawn per
/// node). A node that MUST have a fixed port so that
/// it is reachable through a firewall — the bootstrap — thus gets it
/// without any special case in the program: it is in its seed.
/// A fixed port as a property of ONE host, announced in its
/// data, is bearable; a fixed port as a constant in the program is
/// not.
final class EntryHint {
  final String host;
  final int port;

  const EntryHint(this.host, this.port);

  /// How a hint is written — and how it is compared.
  String get key => host.contains(':') ? '[$host]:$port' : '$host:$port';

  @override
  String toString() => key;
}

/// The entry hints a human has brought along (§11.3 row C,
/// §15 "the peer list … becomes entry hints").
///
/// ── WHY THIS IS A STORE OF ITS OWN, NODE-WIDE ─────────────────────────
///
/// A ContactSeed arrives at an IDENTITY (QR scan, deep link,
/// NFC) — but the V4.1 node is NODE-bound and runs once per
/// process, started BEFORE the services are up (`startV41Node` before
/// `attachV41`). A hint that stayed attached to the identity
/// would never reach the node.
///
/// They are ADDRESSES, not records, and that is no sloppiness: an
/// `EntryRecord` is signed and carries the static node keys —
/// it cannot be built from an `ip:port`, and it is not supposed to be.
/// The hint only says WHERE one can ask; the record is issued by
/// the counterpart itself, and it checks itself on arrival
/// (`EntryRecord.isAuthentic`). A planted hint therefore costs
/// at most one request into the void.
///
/// CAPPED, and hard: a seed carries up to five seed peers, and
/// whoever reads in many seeds would otherwise have turned the entry call into a
/// circular to everything he has ever seen. The cap throws
/// the oldest out first.
final class EntryHintStore {
  final List<EntryHint> _hints = <EntryHint>[];

  /// Maximum number of hints held.
  final int max;

  /// How many addresses were discarded BECAUSE they named no port.
  ///
  /// Counted and not concealed (E-83): a seed from an older
  /// version that names only hosts is ineffective after S372 — and that
  /// should be visible instead of appearing as "nobody answered".
  int droppedWithoutPort = 0;

  EntryHintStore({this.max = 16});

  /// Accepts addresses in the form `ip:port` or `[v6]:port`.
  ///
  /// ── AN ADDRESS WITHOUT A PORT IS DISCARDED (S372) ───────────────────
  ///
  /// No fallback to `kLanEntryPort`. A fallback would have reopened the gap
  /// via exactly this fallback: the same fixed port
  /// for every node, only with a condition in front. And there is no
  /// viable substitute port to guess — the data port is drawn per node
  /// randomly from 10000-64999.
  ///
  /// An exception for "lies in the own segment" was examined and NOT
  /// built: since S372 this store feeds exclusively the
  /// directed entry via the DATA PORT, and that needs the port
  /// even for a neighbour in the segment. The own segment is served by the call
  /// (broadcast/multicast, `lan_entry.dart`), which needs no hint.
  int add(Iterable<String> addresses) {
    var fresh = 0;
    for (final a in addresses) {
      final h = parse(a);
      if (h == null) continue;
      if (_hints.any((x) => x.key == h.key)) continue;
      _hints.add(h);
      fresh++;
      while (_hints.length > max) {
        _hints.removeAt(0);
      }
    }
    return fresh;
  }

  List<EntryHint> get hints => List<EntryHint>.unmodifiable(_hints);

  bool get isEmpty => _hints.isEmpty;

  void clear() {
    _hints.clear();
    droppedWithoutPort = 0;
  }

  /// Splits `ip:port` / `[v6]:port` into host and port.
  ///
  /// `null` for everything that is no usable target: empty, loopback,
  /// unspecified, **or without a port**. A hint to oneself is
  /// no way out, and it has already once made a node dial
  /// itself (`v41_attach`, announce address 127.0.0.1).
  ///
  /// Without a port [droppedWithoutPort] is additionally incremented — that is
  /// the only difference to the static [split], which is the pure
  /// split without a counter.
  EntryHint? parse(String addrPort) {
    final h = split(addrPort);
    if (h == null && _nameNoPort(addrPort)) droppedWithoutPort++;
    return h;
  }

  static bool _nameNoPort(String addrPort) {
    final s = addrPort.trim();
    if (s.isEmpty) return false;
    if (s.startsWith('[')) return !s.contains(']:');
    final c = s.lastIndexOf(':');
    return !(c > 0 && s.indexOf(':') == c);
  }

  /// The pure split, without a counter. `null` if no usable
  /// target WITH a port comes out.
  static EntryHint? split(String addrPort) {
    var s = addrPort.trim();
    if (s.isEmpty) return null;
    String host;
    String portPart;
    if (s.startsWith('[')) {
      final end = s.indexOf(']');
      if (end <= 0) return null;
      host = s.substring(1, end);
      final rest = s.substring(end + 1);
      if (!rest.startsWith(':')) return null;
      portPart = rest.substring(1);
    } else {
      final colon = s.lastIndexOf(':');
      // Exactly ONE colon means `ip:port`; several mean bare
      // IPv6 without brackets — and that carries no port.
      if (colon <= 0 || s.indexOf(':') != colon) return null;
      host = s.substring(0, colon);
      portPart = s.substring(colon + 1);
    }
    if (host.isEmpty) return null;
    if (host == '0.0.0.0' || host == '::') return null;
    if (host.startsWith('127.') || host == '::1') return null;
    final port = int.tryParse(portPart);
    if (port == null || port < 1 || port > 65535) return null;
    return EntryHint(host, port);
  }
}

/// The node-wide hint store of this process.
///
/// ONE instance, as the V4.1 node itself is one. The alternative would have
/// been to pass it through `CleonaService` -> `startV41Node` —
/// but the node starts BEFORE there is a service, and the hints
/// arrive AFTER both are running. A passed-through store would
/// therefore have existed either too early or not at all.
final EntryHintStore personEntryHints = EntryHintStore();
