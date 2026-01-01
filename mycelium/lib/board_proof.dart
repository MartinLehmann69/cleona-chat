/// The passive proof of reachability (build spec W6, S391).
///
/// A node is reachable from outside if a packet reaches it that it
/// did not ask for: from an address from the open network to which it
/// has itself NEVER sent. An address translation or a
/// stateful firewall does not let such a packet through; if it arrives,
/// the node accepts unsolicited traffic.
///
/// Measurement happens UNDER the shell: [ReachabilityProof] is a [PacketRoute]
/// between wire and shell (`node_helpers.dart`, `socketBuild`). Only there
/// is a stranger's first packet visible BEFORE the node answers its
/// handshake — above it, it has already sent to it. `wire.dart`
/// and `shell.dart` stay untouched.
///
/// Comparison is by address, not by address and port: an
/// address-restricted translation lets through packets from every port of an address
/// to which the node has once sent — that would be no proof.
///
/// Limit, named: a packet with a forged sender address from the
/// own segment can set the proof. The only consequence is that the node
/// gives boards — each no larger than the question (§11.8a).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/outside_address.dart' show fromOutsideReachable;
import 'package:mycelium/wire.dart' show PacketRoute;

/// Upper limit of remembered target addresses. Beyond it nothing more is proven —
/// a forgotten target could otherwise yield a false proof.
const int kContactedAtMost = 1 << 16;

/// Upper limit of counted inbound partners (§25.4) — a display figure, far
/// above the neighbour optimum of 32 (§11.8).
const int kInboundAtMost = 256;

class ReachabilityProof implements PacketRoute {
  final PacketRoute _bottom;
  final Set<String> _contacted = {};
  bool _full = false;

  /// Addresses that reached this node unasked — bounded like the neighbour
  /// list's own bound would never need more (§11.8: 32), with room to spare.
  final Set<String> _inbound = {};

  /// When and from whom the proof came — `null` as long as there is none.
  DateTime? provenAt;
  String? provenFrom;

  ReachabilityProof(this._bottom);

  /// The branch BESIDE the shell: gets every arriving packet before the
  /// shell and answers `true` for one that is not a shell packet but
  /// belongs to it — then the shell never sees it.
  ///
  /// It exists for Plane D (§17): §11.1 gives a node ONE socket "for
  /// everything: real packets, cover, calls", and §17.1 keeps call frames
  /// out of delivery cells ("Media does **not** run in delivery cells").
  /// So a call frame shares this socket with the shell and must be sorted
  /// out below it. It hangs here because this is the one [PacketRoute]
  /// between wire and shell (`socketBuild`), and a second insertion point
  /// would be a second copy of the chain. The app sets it
  /// (`lib/core/calls/plane_d_host.dart`); unset, every packet goes to the
  /// shell as before.
  ///
  /// The sorting costs the shell nothing it could lose: the caller claims
  /// only a packet whose first eight bytes name one of ITS live sessions —
  /// the chance that a shell packet does is 2^-64.
  bool Function(Uint8List packet, InternetAddress from, int fromPort)? beside;

  bool get proven => provenAt != null;

  /// Inbound partners (§25.4, E-41): distinct addresses from the open network
  /// that reached this node unasked since start or the last network change.
  /// The norm keeps partner counts separately by inbound and outbound; until
  /// S405 the app showed the replaced V4.1 layer's 0 here (S405 A-2).
  int get inbound => _inbound.length;

  /// The same evidence, asked for at an edge (§8.1, `open_check.dart`): a
  /// packet from a node this node never sent to reached an untouched port.
  void evidenced(String from) {
    if (provenAt != null) return;
    provenAt = DateTime.now();
    provenFrom = from;
  }

  /// Network change: new address, new mappings — nothing applies any more.
  void forget() {
    provenAt = null;
    provenFrom = null;
    _contacted.clear();
    _inbound.clear();
    _full = false;
  }

  @override
  bool send(Uint8List packet, InternetAddress target, int targetPort) {
    if (_contacted.length < kContactedAtMost) {
      _contacted.add(target.address);
    } else if (!_contacted.contains(target.address)) {
      _full = true;
    }
    return _bottom.send(packet, target, targetPort);
  }

  @override
  void listen(
      void Function(Uint8List packet, InternetAddress from, int fromPort) onPacket) {
    _bottom.listen((packet, from, fromPort) {
      _check(from, fromPort);
      if (beside?.call(packet, from, fromPort) ?? false) return;
      onPacket(packet, from, fromPort);
    });
  }

  void _check(InternetAddress from, int fromPort) {
    if (_full) return;
    if (!fromOutsideReachable(from)) return;
    if (_contacted.contains(from.address)) return;
    if (_inbound.length < kInboundAtMost) _inbound.add(from.address);
    if (provenAt != null) return;
    provenAt = DateTime.now();
    provenFrom = '${from.address}:$fromPort';
  }
}

final Expando<ReachabilityProof> _proofs = Expando('reachabilityProof');

/// Hangs the proof on [anchor] — the node's cover stream, the only
/// public piece that arises together with wire and shell
/// (`socketBuild`). A field on the node would exist only in `node.dart`.
void proofAttach(Object anchor, ReachabilityProof proof) =>
    _proofs[anchor] = proof;

ReachabilityProof? proofTo(Object anchor) => _proofs[anchor];
