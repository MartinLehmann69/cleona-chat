/// The durable-object class at the node — the transport of the system
/// channels (v4_2 §16.0, §16.7, §5.5, D-54). S407 SK-1.
///
/// Implements [DurableTransport] for the application and wires the parts:
/// naming in the cover stream (`0x05`), fetching what a neighbour named
/// (`durable_fetch.dart`), answering as a holder (`durable_serve.dart`),
/// depositing (`durable_deposit.dart`) and the questions at the edges
/// (`durable_questions.dart`). Next to the node in an [Expando], like
/// `host_stream.dart`: `node.dart` is at its line budget.
///
/// **Without a stock nothing happens.** A node to which no [DurableStock]
/// was attached ([DurableNode.attach]) names nothing, fetches nothing,
/// answers nothing — the kinds `0x90`–`0x9F` are dropped in the dispatch
/// as a 4.2.3 node drops them. A stock whose [DurableStock.heldChannels]
/// is empty (a 4.2 phone before S426 V1) names nothing and holds nothing,
/// but deposits, asks about fingerprints and fetches what it lacks when the
/// user opens a channel; since D-126 every device holds (§16.7).
///
/// **No clock.** Fetching happens when an identifier is named, the stock
/// is asked at the edges of §16.0, and a deposit when the application calls.
/// The only waits are the answer waits of single requests ([DurableAsk]) and
/// the quiet gap that ends a fetch answer (§11.3, `update_run.dart`).
///
/// **Limits** (§16.0, §16.7): a namer whose identifiers cannot be fetched
/// is written off for the day; at most [kNewObjectsPerNamerDay] new objects
/// a day are fetched from one neighbour.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/durable_deposit.dart';
import 'package:mycelium/durable_fetch.dart';
import 'package:mycelium/durable_id.dart';
import 'package:mycelium/durable_questions.dart';
import 'package:mycelium/durable_serve.dart';
import 'package:mycelium/durable_stock.dart';
import 'package:mycelium/durable_trace.dart' show durableTraceDepositStart;
import 'package:mycelium/host.dart';
import 'package:mycelium/durable_candidates.dart' show durableCandidates;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/node.dart';
import 'package:mycelium/shell_counterpart.dart' show askedCard;

/// §16.7 "Per neighbour that hands out new objects: at most 250 a day".
const int kNewObjectsPerNamerDay = 250;

/// Capable nodes kept across a restart — the most recent ones; the start
/// edge asks the newest first and goes on to the next when one fails.
const int kCapableRemembered = 16;

final Expando<DurableNode> _durable = Expando<DurableNode>('durable');

int _today() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;

class DurableNode implements DurableTransport {
  final Node node;
  final DurableStock stock;
  final void Function(String) report;

  /// Where every packet of this class leaves — replaceable for probes.
  DurableSend send;

  /// This device is a phone: it holds and names like every device, but on a
  /// metered link it fetches only at edges (§16.0, S426 V1).
  bool phone = false;

  /// Holder candidates in the order of §16.7 (`durable_candidates.dart`,
  /// S426 V2) — the host sets the one with the classes stated in `0x53`.
  List<CardAddress> Function() holderOrder;

  late final DurableFetcher fetcher;
  late final DurableServe serve;
  late final DurableQuestions questions;
  final List<DurableDeposit> _deposits = [];

  /// Nodes that showed the capability (named, or answered a request of this
  /// class), the most recent last. Memory only.
  final LinkedHashMap<String, CardAddress> _capable = LinkedHashMap();

  /// Nodes that never showed the capability and failed a request of this
  /// class — not asked again this run unless they show it after all (§16.0
  /// "never asked twice, because it never shows the capability"). A capable
  /// node that stays silent is never entered here ([failed], S424 F-9).
  final Set<String> _failed = {};
  final Map<String, int> _writtenOff = {};
  final Map<String, (int, int)> _perNamer = {};

  DurableNode._(this.node, this.stock, this.report)
      : send = node.rawSend,
        holderOrder = (() => durableCandidates(node.neighbourhood,
            evidence: node.neighbourhood.reachabilitySaid)) {
    fetcher = DurableFetcher(
        send: (p, to) => send(p, to),
        report: report,
        onObject: _fetched,
        onFailed: (namer, _) => _writeOff(namer));
    serve = DurableServe(stock, (p, to) => send(p, to), report);
    questions = DurableQuestions(this);
  }

  /// Attaches [stock] to [node]: the cover stream names and hears
  /// identifiers, the edges ask the stock. Once per node.
  static DurableNode attach(Node node, DurableStock stock,
      {void Function(String)? report}) {
    final present = _durable[node];
    if (present != null) return present;
    final d = DurableNode._(node, stock, report ?? node.report);
    _durable[node] = d;
    node.coverStream
      ..nextIdentifiers = d.names
      ..onIdentifiers = (ids, from, port) => d.heard(ids, _card(from, port));
    // The edges are called by the application (`edge`, `channelOpened`):
    // the collection edge of the node also fires when the application
    // collects for its own reasons, and those are no edges of §16.0.
    for (final k in stock.rememberedCapable()) {
      final a = _parseKey(k);
      if (a != null) d._capable[k] = a;
    }
    return d;
  }

  static DurableNode? of(Node node) => _durable[node];

  // ── Naming (§5.5 rule 2) ───────────────────────────────────────────────

  /// The young identifiers of every held channel, or `null`: the
  /// identifiers count as one object only while there are any. More than
  /// one packet holds are named in turn, the youngest first in each round
  /// (§5.5 rule 2, S426 V4): with only the youngest 57, older ones of the
  /// same day were never named.
  List<DurableId>? names() {
    final all = <DurableId>[
      for (final c in stock.heldChannels())
        ...stock.held(c, sinceHours: kCoverAgeHours - 1)
            .where((i) => i.ageHours < kCoverAgeHours),
    ]..sort((a, b) => a.ageHours.compareTo(b.ageHours));
    if (all.isEmpty) return null;
    if (all.length <= kIdentifiersPerCover) return all;
    final start = _nameAt >= all.length ? 0 : _nameAt; // a new round: youngest
    final end = start + kIdentifiersPerCover > all.length
        ? all.length
        : start + kIdentifiersPerCover;
    _nameAt = end;
    return all.sublist(start, end);
  }

  int _nameAt = 0; // where the next round of naming starts (S426 V4)

  // ── Hearing and fetching (§16.0) ───────────────────────────────────────

  /// Identifiers named by [from] in a cover packet: a holder fetches the
  /// ones it neither holds nor has rejected.
  void heard(List<DurableId> ids, CardAddress from) {
    capable(from);
    // §16.0 (S426 V1): a phone fetches a named identifier at once only on an
    // unmetered link; on a metered one the next edge or opening fetches it.
    if (phone && node.coverStream.metered) return;
    final held = stock.heldChannels();
    for (final id in ids) {
      if (held.contains(id.channel)) want(id, from);
    }
  }

  /// Fetch [id] from [namer] unless it is held, rejected, being fetched,
  /// the namer is written off today, or its daily bound is reached.
  void want(DurableId id, CardAddress namer) {
    if (stock.isHeldOrRejected(id) || fetcher.wanted(id)) return;
    final k = nodeKey(namer);
    final day = _today();
    if (_writtenOff[k] == day) return;
    final n = _perNamer[k];
    final count = n != null && n.$1 == day ? n.$2 : 0;
    if (count >= kNewObjectsPerNamerDay) return;
    _perNamer[k] = (day, count + 1);
    fetcher.want(id, namer);
  }

  /// New objects taken from [namer] today (§16.7 bound).
  int fetchesToday(CardAddress namer) {
    final n = _perNamer[nodeKey(namer)];
    return n != null && n.$1 == _today() ? n.$2 : 0;
  }

  /// Whether [namer] is written off today (§16.0).
  bool writtenOff(CardAddress namer) => _writtenOff[nodeKey(namer)] == _today();

  void _fetched(DurableId id, Uint8List object, CardAddress namer) {
    capable(namer);
    final v = stock.offer(id.channel, object, fromNode: nodeKey(namer));
    if (v == DurableVerdict.rejected) {
      report('Durable: $id from ${nodeKey(namer)} rejected by the application');
    }
  }

  void _writeOff(CardAddress namer) {
    final k = nodeKey(namer);
    _writtenOff[k] = _today();
    failed(namer);
  }

  // ── Capability memory ──────────────────────────────────────────────────

  /// [a] showed the capability. The first one known releases an edge that
  /// found nobody to ask.
  void capable(CardAddress a) {
    final k = nodeKey(a);
    _failed.remove(k);
    final first = _capable.isEmpty;
    final known = _capable.remove(k) != null;
    _capable[k] = a;
    if (!known) _remember();
    if (first) questions.capableKnown(a);
  }

  /// [a] was reached and stayed silent. Locked out for this run only when
  /// it never showed the capability (§16.0 "Older 4.2 versions … never
  /// asked twice, because it never shows the capability"); a node that did
  /// show it is no older version, its silence is a lost request (§11.3a,
  /// e.g. a network change) and it stays capable (S424 F-9). Returns
  /// whether [a] is now locked out.
  bool failed(CardAddress a) {
    final k = nodeKey(a);
    if (_capable.containsKey(k)) return false;
    _failed.add(k);
    return true;
  }

  /// Hands the membership to the application's device data — only when it
  /// changed, never per packet (a capable node names in every cover packet).
  void _remember() {
    while (_capable.length > kCapableRemembered) {
      _capable.remove(_capable.keys.first);
    }
    stock.rememberCapable(_capable.keys.toList());
  }

  bool isCapable(String k) => _capable.containsKey(k);
  bool isFailed(String k) => _failed.contains(k);

  /// Capable nodes, the most recent first, without the failed ones.
  List<CardAddress> get capableNodes => _capable.values.toList().reversed.toList();

  /// Every address of every open neighbour (§11.8.8) as [nodeKey] — the
  /// further stock questions of an edge go only there (S426 V3).
  Set<String> openNodeKeys() => {
        for (final n in node.neighbourhood.openSet())
          for (final a in n.addresses) nodeKey(a.asCardAddress),
      };

  /// S425 N3-3 measurement for `deposit-start`: when [c] was last confirmed
  /// and whether it answered in this run (an `earlier run` stamp is the case
  /// that stays unexplained in 73.W2).
  String _confirmNote(CardAddress c) {
    final a = InternetAddress.fromRawAddress(c.address);
    final n = node.neighbourhood.holding(a, c.port);
    for (final x in n?.addresses ?? const []) {
      if (x.port != c.port || x.address != a) continue;
      return x.confirmedEver
          ? 'confirmed ${x.last.toUtc().toIso8601String()}, ${x.answering ? "this run" : "earlier run"}'
          : 'never confirmed';
    }
    return 'not in the list';
  }

  /// Candidates for a deposit or a fingerprint question (§16.7).
  List<CardAddress> holders() => durableHolderOrder(holderOrder(),
      isContact: stock.isContactNode, capable: isCapable, failed: isFailed);

  // ── DurableTransport ───────────────────────────────────────────────────

  @override
  Stream<DepositEvent> deposit(int channel, Uint8List object) {
    final candidates = holders();
    final d = DurableDeposit(channel, object, candidates,
        isContact: stock.isContactNode,
        send: (p, to) => send(p, to),
        onHolder: (h, answered) => answered ? capable(h) : failed(h),
        report: report);
    // S424 M-4: which holders this deposit asks, and which it leaves out.
    durableTraceDepositStart(report, d.hash, channel, candidates,
        [for (final c in holderOrder()) if (isFailed(nodeKey(c))) c],
        noteOf: _confirmNote);
    _deposits
      ..removeWhere((x) => x.over)
      ..add(d);
    unawaited(d.start());
    return d.events;
  }

  @override
  Future<FingerprintAnswer> askFingerprint(int channel, Uint8List fingerprint) =>
      questions.fingerprint(channel, fingerprint);

  @override
  void channelOpened(int channel) => questions.opened(channel);

  @override
  void edge() => questions.edge();

  @override
  List<String> depositHolders() =>
      [for (final h in holders().take(kDepositHolders)) nodeKey(h)];

  // ── Dispatch (`node_helpers.dart`) ─────────────────────────────────────

  /// D73B-2 (§11.8.4): the asked node an answer from [from] belongs to
  /// (`askedCard`, the shell's link test on the outside route).
  CardAddress _asked(CardAddress from) => askedCard(
      node.outsideRoute.sameCounterpart,
      [...questions.askedAt, for (final d in _deposits) ...d.candidates],
      from);

  void receive(Uint8List p, CardAddress at) {
    final k = p[0];
    final from = switch (k) {
      kinds.kDurableStockAnswer ||
      kinds.kDurableFingerprintAnswer ||
      kinds.kDurableDeposited ||
      kinds.kDurableNotHeld =>
        _asked(at),
      _ => at,
    };
    if (k == kinds.kDurableDeposit) {
      serve.deposit(p, from);
    } else if (k == kinds.kDurableFetch) {
      unawaited(serve.fetch(p, from));
    } else if (k == kinds.kDurableStockAsk) {
      serve.stockAsk(p, from);
    } else if (k == kinds.kDurableFingerprintAsk) {
      serve.fingerprint(p, from);
    } else if (k == kinds.kDurableStockAnswer ||
        k == kinds.kDurableFingerprintAnswer) {
      questions.receive(p, from);
    } else if (k == kinds.kDurableDeposited) {
      for (final d in List.of(_deposits)) {
        d.receive(p, from);
      }
    } else if (k == kinds.kDurablePiece || k == kinds.kDurableNotHeld) {
      fetcher.receive(p, at); // a fetch run is keyed by the namer it went to
      if (k == kinds.kDurableNotHeld) {
        for (final d in List.of(_deposits)) {
          d.receive(p, from);
        }
      }
    }
  }

  void stop() {
    fetcher.stop();
    questions.stop();
    for (final d in _deposits) {
      d.stop();
    }
    _deposits.clear();
  }
}

CardAddress _card(InternetAddress a, int port) =>
    CardAddress(Uint8List.fromList(a.rawAddress), port);

/// `address:port` (the seam's node form, [nodeKey]) back to an address, or
/// `null` for a malformed entry.
CardAddress? _parseKey(String k) {
  final i = k.lastIndexOf(':');
  final ip = i <= 0 ? null : InternetAddress.tryParse(k.substring(0, i));
  final port = i <= 0 ? null : int.tryParse(k.substring(i + 1));
  if (ip == null || port == null || port < 1 || port > 0xFFFF) return null;
  return _card(ip, port);
}

/// The one line of the kind dispatch (`node_helpers.dart`): a node without
/// an attached stock drops the packet silently, as 4.2.3 does (D-21).
void durableDispatch(Node node, Uint8List p, InternetAddress from, int port) =>
    _durable[node]?.receive(p, _card(from, port));

/// The one place where the application hands its [DurableStock] to the
/// transport. The seam (`lib/core/service/`, SK-4) calls [durableAttach]
/// once after the host started; every device holds and names both system
/// channels (§16.7, S426 V1). A host that never attaches a stock behaves
/// as 4.2.3 does. The holder order is §16.7's (`durable_candidates.dart`,
/// S426 V2) with the classes stated in `0x53`, desktops first; the contact
/// rule of §16.7 lies over it (`durable_deposit.dart`).
extension HostDurable on Host {
  /// Attaches [stock]; a second call returns the first attachment. [phone]:
  /// this device is a phone (S426 V1, fetching on a metered link).
  DurableTransport durableAttach(DurableStock stock, {bool phone = false}) =>
      DurableNode.of(node) ??
      (DurableNode.attach(node, stock, report: report)
        ..phone = phone
        ..holderOrder = () => durableCandidates(node.neighbourhood,
            classOf: bulk.placer.classOf,
            evidence: node.neighbourhood.reachabilitySaid));

  /// The attached transport, or `null`.
  DurableTransport? get durable => DurableNode.of(node);
}
