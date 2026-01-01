/// The admission of learned addresses (V4.2 §11.8.3): what a card, an external
/// record, a board or a cover entry names becomes a HINT here, and a new one is
/// the host's edge "new neighbour". `neighbourAdd` holds the rules per address;
/// this file holds who asks and what follows.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/address_entries.dart';
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/host.dart';
import 'package:mycelium/mailbox_edge.dart';
import 'package:mycelium/neighbour_found_by.dart';
import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_call.dart' show neighbourAdd;
import 'package:mycelium/node_post_box.dart';

/// An entry whose confirmation lies further back is stale
/// (§11.8) and is not adopted from foreign lists.
final int _staleMinutes = Neighbourhood.staleAfter.inMinutes;

class NeighbourHints {
  final Node _k;

  /// The host's edge "new neighbour" ([HostNewNeighbour.newNeighbour]).
  final void Function(List<(InternetAddress, int)> fresh) _newNeighbour;
  final void Function(String)? _report;

  /// Source 3 (§11.8.3): the addresses carried in the invitation data this
  /// node has read — kept in its contacts' records (the card's own addresses
  /// and the fixed neighbours it named) — set by the host.
  List<CardAddress> Function() invitationAddresses = () => const [];

  NeighbourHints(this._k, this._newNeighbour, this._report);

  /// One address from outside the call: a card, an external record.
  void remember(List<int> ip, int port,
      {DateTime? confirmedAt, required NeighbourSource source}) {
    final a = InternetAddress.fromRawAddress(Uint8List.fromList(ip));
    if (neighbourAdd(_k, ip, port, confirmedAt: confirmedAt, source: source)) {
      _newNeighbour([(a, port)]);
    }
  }

  /// A received address list (cover §5.5, board §11.8a) from [from]:[port]:
  /// its own addresses are joined into ONE neighbour if the packet came
  /// from one of them (§11.8, V4) — otherwise they are hints like the rest.
  /// A loopback entry is taken only from a sender on loopback ([entryFor]).
  void addressList(AddressList l, InternetAddress from, int port,
      {NeighbourSource? source}) {
    final own = [for (final e in l.own) e.address];
    final n = _k.neighbourhood;
    final r = n.ownAddresses(from, port, own);
    if (r.fresh && source != null) n.noteFoundBy(n.holding(from, port)!, source);
    if (own.isNotEmpty) {
      _report?.call('Own addresses of ${from.address}:$port: ${own.join(', ')}'
          ' — ${r.bound ? 'one neighbour${r.fresh ? ' (new)' : ''}' : 'not bound '
              '(not sent from one of them) — taken as hints'}');
    }
    candidates([
      for (final e in [if (!r.bound) ...l.own, ...l.neighbours])
        if (entryFor(e.address, from)) e,
    ], fresh: [if (r.fresh) (from, port)], source: source);
  }

  /// Learned addresses (cover stream, board) — HINTS, not neighbours.
  /// Admission happens only as long as the list lies below the optimum: a
  /// hint never displaces an entry. Stale entries stay outside.
  /// One edge, no matter how many are new; [fresh]: new ones the caller
  /// already entered.
  void candidates(List<AddressEntry> entries,
      {List<(InternetAddress, int)> fresh = const [],
      NeighbourSource? source}) {
    final n = _k.neighbourhood;
    final added = [...fresh];
    final now = DateTime.now();
    for (final e in entries) {
      if (n.count >= Neighbourhood.atMost) break;
      if (e.ageMinutes >= _staleMinutes) continue;
      final a = e.address;
      // S406: the entry's age says when its sender last confirmed it; a
      // removed address returns only with a confirmation after the removal.
      if (neighbourAdd(_k, a.address, a.port,
          confirmedAt: now.subtract(Duration(minutes: e.ageMinutes)),
          source: source)) {
        added.add((InternetAddress.fromRawAddress(a.address), a.port));
      }
    }
    if (added.isNotEmpty) _newNeighbour(added);
  }

  /// Source 3 in a round (§11.8.3): every invitation address the list does
  /// not hold becomes a hint while the list is below 32, and a new one is
  /// the edge "new neighbour" — which uses it. An address removed since the
  /// last network change stays out: an invitation carries no time, so it says
  /// nothing newer than the removal (§11.8.6); without that, a dead card
  /// address would come back with every round its removal starts (D-9).
  /// The one admission `neighbourAdd` holds that rule for every source
  /// (S407-LB-P7, C-8); no second filter here.
  void invitationTry() {
    final n = _k.neighbourhood;
    final added = <(InternetAddress, int)>[];
    for (final c in invitationAddresses()) {
      if (n.count >= Neighbourhood.atMost) break;
      final a = InternetAddress.fromRawAddress(c.address);
      if (n.holding(a, c.port) != null) continue;
      if (neighbourAdd(_k, c.address, c.port,
          source: NeighbourSource.invitation)) {
        added.add((a, c.port));
      }
    }
    if (added.isNotEmpty) _newNeighbour(added);
  }
}

extension HostNewNeighbour on Host {
  /// The edge "new neighbour" of the host.
  void newNeighbour(List<(InternetAddress, int)> fresh) {
    // Remembering happens IMMEDIATELY, not only on stopping: a crash in between
    // would otherwise cost exactly the source that makes the next start fast.
    network.save();
    for (final p in List.of(mailboxes)) {
      p.atEdge(); // §9.3, §8.2 edge new neighbour (W-2)
    }
    unawaited(node.collectFrom(fresh)); // §8.2: the new neighbour alone
    // Triggered AFTER the own questions: whoever asks here (the manifest
    // compartment, S388) follows them at a holder both ask.
    onNewNeighbours?.call();
  }
}
