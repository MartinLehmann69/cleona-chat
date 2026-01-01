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

class ReachabilityProof implements PacketRoute {
  final PacketRoute _bottom;
  final Set<String> _contacted = {};
  bool _full = false;

  /// When and from whom the proof came — `null` as long as there is none.
  DateTime? provenAt;
  String? provenFrom;

  ReachabilityProof(this._bottom);

  bool get proven => provenAt != null;

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
      onPacket(packet, from, fromPort);
    });
  }

  void _check(InternetAddress from, int fromPort) {
    if (provenAt != null || _full) return;
    if (!fromOutsideReachable(from)) return;
    if (_contacted.contains(from.address)) return;
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
