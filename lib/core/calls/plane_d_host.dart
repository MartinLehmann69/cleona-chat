// Plane D on the 4.2 host — the attachment `attachV41` did until the
// delivery layer became `mycelium/` (S398-W2).
//
// ══ THE FINDING ═════════════════════════════════════════════════════════
//
// `CleonaService.attachCallPlaneD` had exactly one caller,
// `lib/core/tagline/v41_attach.dart`, inside `attachV41` — and `attachV41`
// has had no caller since the replacement. So no service ever got a
// [CallPlaneD], `CallTransportV41.mediaUnavailableReason` always named a
// reason, and `CallService._mediaCarrierReady` rejected every 1:1 call,
// every acceptance and every group call (S398-LUECKEN-NAHT.md, B-2).
//
// ══ WHERE THE FRAMES RUN, BY THE NORM ═══════════════════════════════════
//
//  * §11.1: "A node opens exactly one UDP socket and uses it for
//    everything: real packets, cover, calls." — so no socket of its own;
//    the frames use the host's data port.
//  * §17.1: "Media does **not** run in delivery cells" and §22.4
//    ("Plane D sits beside, not beneath, this stack … do not use Layer
//    2") — so NOT through the shell, the splitter or any mailbox; the
//    sealed D-frame goes onto the wire as it is, and an arriving one is
//    taken off below the shell.
//  * §22.5.2: "live-call frames are the only direct, address-bearing
//    traffic." — the send path takes an explicit address; nothing of the
//    delivery layer's routing is asked.
//
// The one point between wire and shell is `ReachabilityProof`
// (`mycelium/lib/board_proof.dart`, built in `socketBuild`). Sending goes
// through it — so a punch towards the peer counts as "contacted" and the
// peer's answer is never mistaken for proof of inbound reachability — and
// receiving is its branch [ReachabilityProof.beside], asked before the
// shell. [DSocket.claimFrom] takes a datagram only if its first eight
// bytes name a live session of this host.
//
// ══ ONE TABLE PER HOST, THE TRANSPORT PER IDENTITY ═════════════════════
//
// The same split `attachV41` made and for the same reason: the socket
// belongs to the node, the call to the identity. A D-frame carries no
// identity (§17.4: authentic "via AEAD under `call_key`", found by
// cookie), so all identities of the process share the one cookie table.
//
// ══ THE ADDRESS CANDIDATES (§17.3) ══════════════════════════════════════
//
//  * local: `dialableLocalAddresses` inside `ownCallCandidates`, with the
//    host's port;
//  * mapped: the port mapping of the app seam (`portMappingFrom`, §25.9);
//  * mirrored: `Node.publicAddress`, which the host learns from a
//    neighbour outside the own segment ("how do I look from there",
//    `mycelium/lib/node_outside.dart`) — the §17.3 mirror of the 4.2
//    carrier. It is also where the seam writes a granted IPv4 mapping;
//    then it equals the mapped candidate and counts once, as mapped.
library;

import 'dart:typed_data';

import 'package:cleona/core/calls/address_candidates.dart';
import 'package:cleona/core/calls/call_transport_v41.dart' show CallPlaneD;
import 'package:cleona/core/link_io/d_socket.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/service/mycelium_seam.dart' show portMappingFrom;
import 'package:cleona/core/sync/entry_record.dart' show EntryAddress;
import 'package:mycelium/board_node.dart' show NodeAnswer;
import 'package:mycelium/host.dart';

/// Plane D per host — an `Expando` for the same reason as the port mapping
/// in `mycelium_seam.dart`: it is a property of the app, not of the
/// delivery layer, and `Host` gets no field for it.
final Expando<CallPlaneD> _planeDPerHost = Expando('plane-d');

/// The Plane D of [host], or `null` before [planeDAttach].
CallPlaneD? planeDFrom(Host host) => _planeDPerHost[host];

/// Builds the Plane D of [host] (once) and hangs it on every service in
/// [services]. Called at the host start for all identities and at runtime
/// for a new one ([planeDRegister]); a second call for the same host
/// reuses the same table, so running sessions survive it.
CallPlaneD planeDAttach(Host host, Iterable<CleonaService> services,
    {void Function(String)? report}) {
  final d = _planeDPerHost[host] ??= _build(host, report);
  for (final service in services) {
    service.attachCallPlaneD(d);
  }
  return d;
}

/// A service registered on a running host — the same attachment.
CallPlaneD planeDRegister(Host host, CleonaService service,
        {void Function(String)? report}) =>
    planeDAttach(host, [service], report: report);

/// Takes Plane D off [host] before it stops: every service loses it (its
/// calls end with the loss rule, §17.4), the branch beside the shell is
/// removed and the sessions are closed.
Future<void> planeDDetach(Host host, Iterable<CleonaService> services) async {
  final d = _planeDPerHost[host];
  if (d == null) return;
  for (final service in services) {
    service.attachCallPlaneD(null);
  }
  host.node.passiveProof?.beside = null;
  _planeDPerHost[host] = null;
  await d.socket.close();
}

CallPlaneD _build(Host host, void Function(String)? report) {
  final route = host.node.passiveProof;
  if (route == null) {
    // `socketBuild` always hangs the proof on the node; without it there is
    // no point between wire and shell, and a Plane D that could not receive
    // must not pretend to exist.
    throw StateError('Plane D: the host has no route between wire and '
        'shell (ReachabilityProof missing) — no call frame could arrive');
  }
  final socket = DSocket.onRoute(send: (datagram, target, targetPort) {
    route.send(datagram, target, targetPort);
  });
  route.beside = socket.claimFrom;
  report?.call('Plane D: attached to the data port ${host.port} '
      '(§11.1 one socket, §17.1 beside the shell)');
  return CallPlaneD(
    socket: socket,
    ownPort: host.port,
    mapped: () {
      final m = portMappingFrom(host)?.mapper;
      if (m == null || !m.hasMapping) return null;
      final ip = m.externalIp;
      final port = m.externalPort;
      if (ip == null || port == null) return null;
      return EntryAddress(ip, port);
    },
    mirrored: () {
      final p = host.node.publicAddress;
      if (p == null) return const <CallCandidate>[];
      final c = CallCandidate.of(Uint8List.fromList(p.address), p.port,
          fromMirror: true);
      return c == null ? const <CallCandidate>[] : [c];
    },
  );
}

