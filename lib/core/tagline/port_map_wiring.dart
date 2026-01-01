/// The seam between the port mapping and the node (S373).
///
/// ── WHY THIS IS A FILE OF ITS OWN ─────────────────────────────────
///
/// The same reasoning as for `lan_entry_wiring.dart` next to it: the
/// port mapping (`lib/core/link_io/port_mapper.dart`) knows no
/// node, and the node knows no gateway. The place where both
/// are available is `startV41Node` — and a block IN the body of
/// `startV41Node` would be exactly the construction that S360 resolved at
/// `setzeAnsageadressen`: computed once per process,
/// not individually testable, and not reusable at the next occasion (network change).
///
/// As a component of its own the seam has three occasions — start, network change,
/// shutdown — and **one** implementation. And it can be measured
/// against a real node with an inserted coordinator
/// (`smoke_port_mapping_wired.dart`, section 2), instead of only being claimed in the source
/// of `v41_attach.dart`.
///
/// ── WHAT IT DOES, AND WHAT IT EXPLICITLY DOES NOT DO ────────────────
///
/// It writes exactly ONE field: [V41Node.advertiseMapped]. It does NOT touch
/// `advertiseHost`, `advertisePort` and `advertiseExtra` — those
/// belong to `setzeAnsageadressen` and come from a different source (the
/// local interfaces). Two writers on one list would be the
/// drift in which one silently overwrites what the other just
/// set.
///
/// ONLY CONFIRMED MAPPINGS. The event `externalIpDiscovered` without
/// mapping is logged and otherwise discarded: an external address
/// without an open port is an address at which no one listens. A neighbour
/// that takes it from the entry record sends into the void and then considers the
/// node dead.
library;

import 'dart:async';

import 'package:cleona/core/link_io/port_mapper.dart';
import 'package:cleona/core/sync/entry_record.dart' show EntryAddress;
import 'package:cleona/core/tagline/v41_node.dart';

export 'package:cleona/core/link_io/port_mapper.dart'
    show PortMapper, PortMapperEvent, PortMapperEventType, PortMapperState;

/// The running port mapping of a process, bound to the node.
///
/// Built by `startV41Node` and handed outward in `V41Runtime`
/// — for the same reason as `entryPersist`: the renewal timer of the
/// coordinator keeps the Dart VM alive, and [dispose] is the only
/// way to get rid of it again.
final class PortMapBinding {
  final V41Node _node;
  final void Function(String)? _log;

  /// The coordinator itself. The service reads it for
  /// `CleonaService.hasPortMapping` and for the NAT assistant (§27.9).
  final PortMapper mapper;

  late final StreamSubscription<PortMapperEvent> _sub;

  PortMapBinding._(this._node, this.mapper, this._log);

  /// Builds the seam and starts listening. Does NOT start the coordinator
  /// — the caller does that, so that the node start does not wait for a gateway
  /// that may never answer.
  factory PortMapBinding.bind({
    required V41Node node,
    required int port,
    void Function(String)? log,
    PortMapper? mapper,
  }) {
    final m = mapper ??
        PortMapper(
          internalPort: port,
          // THE SAME PORT OUTSIDE AS INSIDE, if the router plays along.
          // §11/E-60 gives the entry record ONE port for UDP and
          // TCP; a differing external port number would be right for UDP
          // and wrong for the TCP fallback, and the record
          // cannot tell the two apart. If the router rejects the
          // request and assigns a different number, it is taken anyway
          // — then at least the UDP side is right, and the
          // TCP fallback is no worse off than without a mapping.
          requestedExternalPort: port,
          log: log,
        );
    final b = PortMapBinding._(node, m, log);
    b._sub = m.events.listen(b._onEvent);
    return b;
  }

  void _onEvent(PortMapperEvent e) {
    switch (e.type) {
      case PortMapperEventType.mappingAcquired:
      case PortMapperEventType.mappingRenewed:
        final m = e.mapping;
        if (m == null) return;
        // '0.0.0.0' means „mapping yes, external address unknown".
        // That happens with NAT-PMP when the address query stayed silent.
        // An announcement on 0.0.0.0 would be worse than none.
        if (m.externalIp.isEmpty || m.externalIp == '0.0.0.0') {
          _log?.call('V4.1: port mapping open, but without external '
              'address — nothing is announced');
          return;
        }
        final fresh = EntryAddress(m.externalIp, m.externalPort);
        // FIRST THE PROOF, THEN THE ADDRESS (S373, added during
        // merging). `portMappingConfirmed` is the second proof source
        // of `brettEntscheid` next to the inbound proof — without it there would be
        // the loop: a freshly mapped node has no inbound,
        // does not publish, is not dialled, never gets one.
        // It stands BEFORE the early return so that an UNCHANGED
        // renewal sets it TOO: after a network change the
        // proof falls (`onNetworkChanged`), and the first renewal afterwards can
        // deliver the same address as before. If it stood behind it,
        // the node would stay unpublished after every network change until the next
        // ADDRESS CHANGE — i.e. possibly forever.
        _node.portMappingConfirmed = true;
        if (_node.advertiseMapped == fresh) return; // renewal, unchanged
        _node.advertiseMapped = fresh;
        _log?.call('V4.1: announce address from port mapping $fresh '
            '(${e.source})');
        // WITH PRIORITY, for the same reason as at the network change: the
        // record is the only thing that tells a neighbour where this
        // node can be reached from outside.
        _node.announceOwnEntry(priority: true);

      case PortMapperEventType.mappingLost:
        if (_node.advertiseMapped == null) return;
        _log?.call('V4.1: port mapping lost — the outer '
            'announce address is dropped');
        _node.portMappingConfirmed = false;
        _node.advertiseMapped = null;
        _node.announceOwnEntry(priority: true);

      case PortMapperEventType.externalIpDiscovered:
        // LOG ONLY. Reasoning in the file header: without a confirmed
        // mapping this address points to a closed port.
        _log?.call('V4.1: external address seen (${e.externalIp}) — '
            'without port mapping it is NOT announced');
    }
  }

  /// Network change (§22.6): the old mapping points into the old network.
  ///
  /// ORDER, and it is not arbitrary: first clear the announcement,
  /// then reset the coordinator, then search anew. The other way round
  /// the dead external address would still stand in the record in the window in between
  /// — and exactly that would be harvested by the neighbours the
  /// node is just dialling anew. The same reasoning as for
  /// `setzeAnsageadressen` in `v41_attach.dart`.
  ///
  /// The new search is NOT awaited: in the worst case it can
  /// take minutes (RFC 6886 backoff), and the network change must not
  /// hang on it.
  Future<void> onNetworkChanged() async {
    _node.portMappingConfirmed = false;
    _node.advertiseMapped = null;
    await mapper.reset();
    unawaited(mapper.start());
  }

  /// MANDATORY on shutdown. Without this call the
  /// renewal timer of the coordinator keeps the Dart VM alive for up to an hour
  /// — the same trap because of which `V41Runtime.entryPersist` is in the
  /// return value of `startV41Node`.
  Future<void> dispose() async {
    await _sub.cancel();
    _node.portMappingConfirmed = false;
    _node.advertiseMapped = null;
    await mapper.dispose();
  }
}
