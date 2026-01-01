/// Lane 2 of §9.4 wired to the node: volunteer, sender and recipient of the
/// relayed media stream (§17.6) on the node's socket.
///
/// Next to the node in an [Expando] (like `node_collect_edge.dart`):
/// `host.dart` and `host_media.dart` are at their line budget and belong to
/// lane 3. The media dispatch hands every kind of `0x56`–`0x5A` here with
/// ONE line ([streamDispatch]); the parts are asked in turn, each takes
/// only what carries one of its cookies (or, for the volunteer, an ask).
///
/// Whether this node volunteers (D-31: every inbound-reachable always-on
/// node, no switch): [HostStream.volunteer] says "always-on class" — the
/// app sets it on a desktop, as it sets the bulk cache (§21.3.3) —, and
/// [HostStream.reachable] says "reachability evidenced" (§11.8a), the same
/// test as for a desktop holder of lane 3 (`reachableEvidenced`,
/// `host_media.dart`): a family open from outside (open check of §8.1,
/// granted mapping or pinhole) or the board's proof. Without it the
/// volunteer refuses every ask (verdict "no volunteer").
library;

import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/host.dart';
import 'package:mycelium/host_media.dart'
    show bulkFamilyOpen, reachableEvidenced;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/node.dart';
import 'package:mycelium/stream_receive.dart';
import 'package:mycelium/stream_send.dart';
import 'package:mycelium/stream_volunteer.dart';

final Expando<HostStream> _streams = Expando<HostStream>('stream');

class HostStream {
  final Node node;

  /// Where every lane-2 packet of this node leaves — replaceable for probes
  /// (a packet log, artificial loss).
  late void Function(Uint8List packet, CardAddress to) send = node.rawSend;

  /// Always-on class (desktop). Default false: a phone never volunteers.
  bool volunteer = false;

  /// Reachability evidenced; see the library comment. Before [HostStreamOn]
  /// wires the host's network side: the board's proof alone.
  late bool Function() reachable =
      () => reachableEvidenced(node, (_) => false);

  late final StreamVolunteer volunteerSide = StreamVolunteer(
      send: _out, allowed: () => volunteer && reachable(), report: node.report);
  late final StreamSender sender = StreamSender(send: _out, report: node.report);
  late final StreamReceiver receiver =
      StreamReceiver(send: _out, report: node.report);

  HostStream._(this.node);

  static HostStream of(Node node) => _streams[node] ??= HostStream._(node);

  void _out(Uint8List p, CardAddress to) => send(p, to);

  void receive(Uint8List p, CardAddress from) {
    if (p.isEmpty || !kinds.isStream(p[0])) return;
    if (volunteerSide.receive(p, from) || sender.receive(p, from) ||
        receiver.receive(p, from)) {
      return;
    }
    // Silence: no cookie of ours — no answer (§17.4, §11.6).
  }

  /// Ends every session clock; called when the host stops.
  void stop() {
    volunteerSide.stop();
    receiver.stop();
  }
}

/// The one line of the media dispatch (`host_media.dart`).
void streamDispatch(Node node, Uint8List p, CardAddress from) =>
    HostStream.of(node).receive(p, from);

extension HostStreamOn on Host {
  /// Lane 2 of this host. The first access sets the reachability test from
  /// the host's network side (open check, mapping) — see [HostStream].
  HostStream get stream {
    final s = HostStream.of(node);
    if (_wired[s] != true) {
      _wired[s] = true;
      s.reachable =
          () => reachableEvidenced(node, (f) => bulkFamilyOpen(network, f));
    }
    return s;
  }
}

final Expando<bool> _wired = Expando<bool>('streamWired');
