/// Link I/O — the UDP bind side of AP-3a build stage 4.
///
/// **Why this directory exists (E-100).** `lib/core/link/` opens no socket:
/// its twelve modules are checkable without a network, and the connect
/// surface writes that line down for itself (`connect.dart:14-24`). Build
/// stage 4 needs real socket work, so it lives here — not in the link layer,
/// whose testability it would break, and not in `lib/core/network/`, the V3
/// tree that was deleted rather than rebuilt when the lab gate passed
/// (CUT, 2026-08-31; zero files there, measured 2026-09-03). The
/// search sets of guards 4, 9 and 10c extend to this directory; guard 4 came
/// with the commit that created it (E-100), guards 9 and 10c followed with
/// D-3, each with an anti-vacuum check per root — a search root that holds
/// no file is vacuously green.
///
/// **What this file is.** The injected [LinkBinder] of
/// `lib/core/link/connect.dart`. It does **not** own the sockets any more:
/// since D-1 those belong to [UdpSocketSet], which the node host holds and
/// hands to both directions. What stays here is the bind-side bookkeeping —
/// which families came up, why the others did not, and the one decision
/// E-101 turns on: a bind counts when **at least one** family is listening,
/// and fails only when none is.
///
/// It interprets no byte of what arrives. Telling a handshake flight from a
/// data cell is the demux of E-95 and lives beside this file, not in it.
library;

import 'dart:async';

import 'package:cleona/core/link/connect.dart';
import 'package:cleona/core/link/transport_selector.dart';
import 'package:cleona/core/link_io/udp_sockets.dart';

export 'package:cleona/core/link_io/udp_sockets.dart'
    show LinkAddressFamily, LinkDatagram, LinkNoFamilyBound, UdpSocketSet;

/// A bound listener for one disguise, over the families that came up.
final class UdpLinkBinding implements LinkBinding {
  @override
  final Disguise disguise;

  /// The families that are listening. Never empty — an empty set is
  /// [LinkNoFamilyBound] instead, thrown before this object exists.
  final Set<LinkAddressFamily> families;

  /// Why the missing families are missing, one entry each.
  ///
  /// Kept because §4.6 rule 5 (E-71) requires two causes to stay apart: a
  /// family absent because this node has none, against a family absent
  /// because no partner offers one. Without this map the diversity
  /// indicator "reports drift and the operator looks in the wrong place".
  final Map<LinkAddressFamily, Object> familyFailures;

  final Future<void> Function() _release;

  const UdpLinkBinding._({
    required this.disguise,
    required this.families,
    required this.familyFailures,
    required this._release,
  });

  /// True when only one family came up — a single-stack node.
  bool get isSingleStack => families.length == 1;

  @override
  Future<void> close() => _release();

  @override
  String toString() => 'UdpLinkBinding(${disguise.name}, '
      '${families.map((f) => f.name).join("+")})';
}

/// The injected inbound boundary of `Link.bind`, over the node's sockets.
///
/// **One socket set for the node, not one per disguise (E-95).** The first
/// [bindDisguise] brings the set up; every later disguise is a demux
/// registration on the set that already exists. A second port is foreclosed
/// by E-64, and a second `SO_REUSEADDR` socket on the same port is
/// documented broken — so sharing is not a shortcut here, it is the only
/// shape available.
///
/// **This class holds no counter and no failure flag.** Failures are kept as
/// records ([UdpLinkBinding.familyFailures]), never as a tally, and nothing
/// here feeds either the escalation axis or the disguise choice — the
/// separation guard 4 watches (§4d.4 point 4).
final class UdpLinkBinder implements LinkBinder {
  /// The node's sockets. Held by the host, shared with the connect side
  /// (D-1); this class neither opens nor closes them on its own account.
  final UdpSocketSet sockets;

  final LinkLogSink log;

  final _registered = <Disguise>{};

  UdpLinkBinder({required this.sockets, required this.log});

  /// The node's data port.
  int get port => sockets.port;

  /// Every datagram that arrives on any bound family, undisturbed.
  ///
  /// The demux of E-95 subscribes here. Nothing in this class looks at the
  /// bytes: at 1200 B a handshake flight and a data cell are the same shape,
  /// so there is nothing to decide at this layer.
  Stream<LinkDatagram> get inbound => sockets.inbound;

  /// The families currently listening.
  Set<LinkAddressFamily> get families => sockets.families;

  @override
  Future<LinkBinding> bindDisguise(Disguise disguise) async {
    await sockets.open();

    if (sockets.families.isEmpty) {
      // No family came up. Every cause is in the map; the caller decides
      // what that means for this disguise (E-99 for `bare`, E-96 otherwise).
      throw LinkNoFamilyBound(sockets.failures);
    }

    _registered.add(disguise);

    return UdpLinkBinding._(
      disguise: disguise,
      families: sockets.families,
      familyFailures: sockets.failures,
      release: () async => _unregister(disguise),
    );
  }

  Future<void> _unregister(Disguise disguise) async {
    _registered.remove(disguise);
    if (_registered.isEmpty) {
      await close();
    }
  }

  /// Closes the socket set.
  ///
  /// Kept as a method of the binder because the guard and the callers of
  /// stage 4 reach it here; the sockets themselves belong to the host.
  Future<void> close() => sockets.close();
}
