/// The media side of the host — lane 3 of §9.4 wired to the node: holder,
/// sender and recipient on the node's socket, the collection edges, and the
/// order in which holders are asked (D-30).
///
/// A separate file because `host.dart` is at its line budget. The host
/// creates ONE [HostMedia] at start; the mailbox reaches it through
/// `mailbox_bulk.dart`. Lanes 1 and 2 are not here: lane 1 is one ordinary
/// message (§9.4), lane 2 goes through a volunteer (§17.6).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/bulk_collect.dart';
import 'package:mycelium/bulk_disk.dart';
import 'package:mycelium/bulk_hold.dart';
import 'package:mycelium/bulk_piece.dart';
import 'package:mycelium/bulk_place.dart';
import 'package:mycelium/board_node.dart' show NodeAnswer;
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/host_network.dart' show HostNetwork;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/neighbourhood_seat.dart' show reachableNeighbour;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_collect_edge.dart';
import 'package:mycelium/node_helpers.dart' show interfaces;
import 'package:mycelium/host_stream.dart' show streamDispatch;

class HostMedia {
  final Node node;

  /// `R_bulk` for everything this node sends on lane 3 — placed pieces and
  /// pieces handed out alike.
  final BulkPace pace = BulkPace();
  late final BulkHolder holder;
  late final BulkPlacer placer;

  /// The recipient's side: ONE collector per registered identity, keyed by
  /// its identifier (S401). A transfer belongs to one identity — its
  /// callbacks, and its opened blocks in that identity's folder under its
  /// key (§4.5.3, §21.4.1); the host holds none of it.
  final Map<String, BulkCollector> _collectors = {};
  late final void Function(Uint8List packet, CardAddress to) _send;
  final void Function(String)? _report;

  /// Every edge of §8.2, after the collections asked: the layer above
  /// resumes its own lane 3 work at the same moments (S398-W1). No clock.
  void Function()? onEdge;

  /// [bulkCacheBytes]: the bulk cache (§21.3.3, D-32: desktop 1 GB, phone
  /// 100 MB). 0 — the default — keeps no bulk and refuses every open.
  /// [cls] is stated in every `0x53`; [open] says whether a family is open
  /// from outside (§8.1) — for a phone per family, for a desktop as part
  /// of [reachableEvidenced] —, and [serveAllowed] whether a phone may hold
  /// now (data-saving mode on a metered link, D-32) — see `bulk_hold.dart`.
  HostMedia(this.node, Directory directory, Uint8List key,
      {int bulkCacheBytes = 0,
      BulkClass cls = BulkClass.desktop,
      bool Function(InternetAddressType family)? open,
      bool Function()? serveAllowed,
      void Function(String)? report})
      : _report = report {
    // The host's folder holds the holder's side only; what an earlier build
    // left there of an identity goes (S401).
    final disk = BulkDisk.open(directory, key, report: report)
      ..identityStockDrop();
    // A packet to one of the node's OWN addresses never reaches the wire:
    // a recipient that is itself one of the holders (a group member, a
    // desktop contact) asks its own cache, and a shell to oneself does not
    // come about. It goes to the dispatch in the next microtask instead —
    // the same path, the address it was sent to as the sender.
    // The port first: the list is built only for a packet that may be one.
    bool own(CardAddress to) =>
        (to.port == node.port || to.port == node.publicAddress?.port) &&
        bulkOwnAddresses(node).any((a) => a.equal(to));
    void send(Uint8List p, CardAddress to) {
      if (!own(to)) return node.rawSend(p, to);
      scheduleMicrotask(() => _dispatch(p, to));
    }

    bool familyOpen(InternetAddressType f) => open?.call(f) ?? false;
    holder = BulkHolder(
        budget: bulkCacheBytes,
        send: send,
        own: () => bulkOwnAddresses(node),
        cls: cls,
        reachable: (a) => familyOpen(a.address.length == 4
            ? InternetAddressType.IPv4
            : InternetAddressType.IPv6),
        proven: () => reachableEvidenced(node, familyOpen),
        serveAllowed: serveAllowed,
        disk: disk,
        pace: pace,
        report: report);
    placer = BulkPlacer(send: send, pace: pace, report: report);
    _send = send;
    node.mediaReception = receive;
    node.addCollectEdge((_, __) {
      for (final c in List.of(_collectors.values)) {
        c.ask();
      }
      onEdge?.call();
    });
  }

  /// A mailbox was admitted (`Host`): its identity [owner] gets its
  /// collector, with the opened blocks in ITS [directory] under ITS [key].
  /// Nothing is open yet — the layer above hands its collections over.
  void admit(String owner, Directory directory, Uint8List key) {
    _collectors.remove(owner)?.close();
    _collectors[owner] = BulkCollector(
        send: _send,
        disk: BulkDisk.open(directory, key, report: _report),
        // The bound of 256 MiB on disk holds for the device (§9.4).
        othersOnDisk: () => _collectors.entries
            .where((e) => e.key != owner)
            .fold(0, (n, e) => n + e.value.openedOnDisk),
        report: _report);
  }

  /// The identity [owner] left the host (deregistered, or its service was
  /// detached): nothing is asked or taken for it any more, and nothing is
  /// written into its folder — which may be removed next (§21.4.1).
  void release(String owner) => _collectors.remove(owner)?.close();

  /// The collector of the registered identity [owner].
  BulkCollector collectorOf(String owner) =>
      _collectors[owner] ??
      (throw StateError('no collector — the identity is not registered'));

  /// The media range of the kind dispatch (`node_helpers.dart`). The old
  /// unsealed announcement 0x50 has no receiver any more: lane 1 is an
  /// ordinary message, and a raw 0x51 is now always a sealed bulk piece.
  void receive(Uint8List p, InternetAddress from, int fromPort) =>
      _dispatch(p, CardAddress(Uint8List.fromList(from.rawAddress), fromPort));

  void _dispatch(Uint8List p, CardAddress a) {
    if (p.isEmpty) return;
    final k = p[0];
    if (kinds.isStream(k)) return streamDispatch(node, p, a); // lane 2, §17.6
    if (k == kinds.kBulkHold || k == kinds.kBulkCollect) {
      holder.receive(p, a);
    } else if (k == kinds.kBulkHeld) {
      placer.receive(p, a);
    } else if (k == kinds.kMediaPiece || k == kinds.kBulkNothingHere) {
      // A packet names its transfer, not an identity: every collector that
      // has this transfer open takes it, the others ignore it.
      for (final c in List.of(_collectors.values)) {
        c.receive(p, a);
      }
    } else {
      node.report('media kind 0x${k.toRadixString(16)} without receiver');
    }
  }

  /// Holder candidates for a transfer (§9.4, D-30), in the order they are
  /// asked; see [bulkHolderOrder].
  List<CardAddress> holderOrder(List<CardAddress> recipientFixed) =>
      bulkHolderOrder(node.neighbourhood, recipientFixed,
          classOf: placer.classOf);

  void stop() => holder.stop();
}

/// The order of §9.4 (lane 3, who holds), in three ranks: (1) the
/// recipient's fixed neighbours as it last told them (§9.2), (2) this
/// node's own fixed neighbours (§5.2), (3) every other neighbour — ranks 2
/// and 3 only with evidenced reachability: an address confirmed and
/// reachable from the open network ([reachableNeighbour], §11.8a), and that
/// address is the one used. The recipient's list is taken as told: its
/// fixed seats go to reachable neighbours (V6), and this node has no
/// evidence of its own about them. An address appears once, in its
/// highest rank.
///
/// Within a rank desktops go first (D-30), then candidates of unknown
/// class, then phones — [classOf] is what earlier `0x53` answers stated
/// (`BulkPlacer.classOf`); otherwise the order within a rank is kept.
/// Whether a candidate holds at all is learned from its answer — a node
/// without a cache, or a phone that may not hold now, refuses with count 0
/// and the sender moves on.
List<CardAddress> bulkHolderOrder(
    Neighbourhood hood, List<CardAddress> recipientFixed,
    {BulkClass Function(CardAddress holder)? classOf}) {
  bool public(NeighbourAddress a) => hood.openNetwork(a.address);
  final ranks = [<CardAddress>[], <CardAddress>[], <CardAddress>[]];
  void add(int rank, CardAddress c) {
    if (!ranks.any((r) => r.any((x) => x.equal(c)))) ranks[rank].add(c);
  }

  for (final c in recipientFixed) {
    add(0, c);
  }
  for (final (rank, list) in [(1, hood.fixedNeighbours), (2, hood.all)]) {
    for (final n in list) {
      if (!reachableNeighbour(n, public)) continue;
      add(rank, n.addresses
          .firstWhere((a) => a.confirmedEver && public(a))
          .asCardAddress);
    }
  }
  final order = classOf ?? (_) => BulkClass.unknown;
  final out = <CardAddress>[];
  for (final r in ranks) {
    final at = [for (var i = 0; i < r.length; i++) (i, r[i])];
    // Stable: candidates of equal class keep the order of their rank.
    at.sort((a, b) {
      final c = order(a.$2).order.compareTo(order(b.$2).order);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    out.addAll(at.map((e) => e.$2));
  }
  return out;
}

/// Whether [family] of this node is open from outside (§8.1): the open
/// check found it open (`open_check.dart`), or the router granted an IPv4
/// mapping or an IPv6 pinhole (§7.3, set by the app seam at
/// `KeepAlive.ipv4Mapped`/`ipv6Mapped`). Lane 3 asks it before a phone
/// holds (§9.4, D-30). Read only here — `host_network.dart` owns the values.
bool bulkFamilyOpen(HostNetwork n, InternetAddressType family) =>
    n.openCheck.isOpen(family) ||
    (family == InternetAddressType.IPv4
        ? n.keepAlive.ipv4Mapped()
        : n.keepAlive.ipv6Mapped());

/// Whether [k]'s reachability is evidenced (§11.8a) — what makes a desktop
/// a holder (§9.4, D-30) and a volunteer (§17.6, D-31): a family open from
/// outside ([open]: the open check of §8.1, or a mapping or pinhole the
/// router granted — [bulkFamilyOpen]), or the board's proof (mapping
/// proven OR an unsolicited packet from a node never sent to,
/// `Board.reachableProven`). An address confirmed from outside is not
/// evidence: behind a translator it answers only whom it asked.
bool reachableEvidenced(Node k, bool Function(InternetAddressType) open) =>
    open(InternetAddressType.IPv4) ||
    open(InternetAddressType.IPv6) ||
    (k.board?.reachableProven ?? false);

/// The addresses under which [k] knows itself, each with its data port:
/// the loopback and every interface address of a family it holds a socket
/// for, and the public address confirmed from outside or granted by the
/// router (`Node.publicAddress`; the app seam sets a granted IPv4 mapping
/// there, `mycelium_seam.dart`). A sender binds its proof to the address it
/// writes to (D-30); the holder accepts it only under one of these.
///
/// LIMIT, named: a translator that gives this node a different outside
/// port per destination is not covered — the sender then writes to an
/// address this list does not name, and the holder stays silent; the
/// sender moves on to the next candidate after `kOpenWait`.
List<CardAddress> bulkOwnAddresses(Node k) {
  final out = <CardAddress>[];
  void add(InternetAddress a, int port) {
    if (!k.speaks(a)) return;
    final c = CardAddress(Uint8List.fromList(a.rawAddress), port);
    if (!out.any((x) => x.equal(c))) out.add(c);
  }

  add(InternetAddress.loopbackIPv4, k.port);
  add(InternetAddress.loopbackIPv6, k.port);
  for (final s in interfaces) {
    for (final a in s.addresses) {
      add(a, k.port);
    }
  }
  final p = k.publicAddress;
  if (p != null) add(InternetAddress.fromRawAddress(p.address), p.port);
  return out;
}
