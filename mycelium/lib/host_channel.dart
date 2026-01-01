/// Groups and channels on the shared key at the host (V4.2 §16.2.5): the
/// keeper, the author's deposit, the member's collection and the nudge,
/// wired to the node's socket and to the mailboxes.
///
/// Next to the node in an [Expando] (like `host_stream.dart`): `host.dart`
/// and `node.dart` are at their line budget. The kind dispatch hands every
/// packet of `0x60`–`0x6F` here ([HostChannelWire.channelWireUp]).
///
/// Who keeps (§16.2.5 "Keepers"): an always-on desktop installation with
/// evidenced reachability (§11.8a) — the same test as the lane-2 volunteer
/// (`host_stream.dart`, D-31) and the desktop holder of lane 3; a
/// retention-bounded node never keeps.
///
/// A nudge names no identity, only a pair code: it is offered to every
/// mailbox until one opens it, and that mailbox's application gets it
/// ([HostChannel.onNudge]).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/channel_collect.dart';
import 'package:mycelium/channel_deposit.dart';
import 'package:mycelium/channel_keeper.dart';
import 'package:mycelium/device_records.dart';
import 'package:mycelium/host.dart';
import 'package:mycelium/host_media.dart' show bulkOwnAddresses;
import 'package:mycelium/node_helpers.dart' show ownTarget;
import 'package:mycelium/split_flow.dart' show SendEnd;
import 'package:mycelium/host_stream.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_channel.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_silence.dart';
import 'package:mycelium/silence.dart';

final Expando<HostChannel> _channels = Expando<HostChannel>('channel');

/// What the application does with a nudge that a mailbox opened: the
/// sender (identifier hex) and the entry.
typedef NudgeSink = void Function(String fromHex, Uint8List entry);

class HostChannel {
  final Node node;

  /// What this node holds for others survives a restart — set by the host
  /// before the first packet (`Host.start`); without it, in memory.
  DeviceRecords? records;

  /// Where every packet of this file leaves for another node — replaceable
  /// for probes.
  late Object? Function(Uint8List packet, CardAddress to) send = node.rawSend;

  /// Whether this node keeps; see the library comment. Replaceable for
  /// probes.
  late bool Function() keeps = () {
    final s = HostStream.of(node);
    return s.volunteer && s.reachable();
  };

  /// The one way out of keeper, deposit and collection. The owner and the
  /// admins come first on the keeper list (§16.2.5 "Keepers"), so an author
  /// or a member may name its own node: such a packet never reaches the
  /// wire ([ownTarget] — the shell cannot carry it) and goes to [receive]
  /// in the next microtask, with the address it was sent to as the sender,
  /// as on lane 3 (`host_media.dart`). Packets, kinds and answers stay
  /// those of the wire (S407-B19).
  Object? _out(Uint8List p, CardAddress to) {
    if (!ownTarget(node, to)) return send(p, to);
    scheduleMicrotask(() => receive(
        p, InternetAddress.fromRawAddress(to.address), to.port, false, const []));
    return SendEnd.sent;
  }

  late final ChannelKeeper keeper = ChannelKeeper(
      send: _out,
      allowed: () => keeps(),
      ownAddresses: () => bulkOwnAddresses(node),
      records: records,
      report: node.report);
  /// The deposit asks through the silence building block like every request
  /// (§11.3a); its own instance only so that it learns WHICH keeper address
  /// the readiness declared failed — the one the owner's next list leaves
  /// out (§16.2.5 "Keepers").
  late final ChannelDepositor depositor = ChannelDepositor(
      send: _out,
      silence: Silence(
        addressesOf: (a, p) => sameNode(node.neighbourhood, a, p, node.speaks),
        failed: (a, p, {silentNow = const {}}) {
          final counted = node.readiness.addressFailed(a, p, silentNow: silentNow);
          if (counted) depositor.declared.add('${a.address}:$p');
          return counted;
        },
        report: node.report,
        // Its answers stamp at the node's one place (§11.8.4, O-3).
        onAnswered: (a, p) => node.silence.answeredBy(a, p),
      ),
      report: node.report);
  late final ChannelCollector collector = ChannelCollector(
      send: _out, silence: node.silence, report: node.report);

  /// The application of each identity, by its mailbox.
  final Expando<NudgeSink> onNudge = Expando<NudgeSink>('nudge');

  /// Nudges opened and handed on — for probes and the statistics (§25).
  int nudgesIn = 0;

  HostChannel._(this.node);

  static HostChannel of(Node node) => _channels[node] ??= HostChannel._(node);

  /// One packet of `0x60`–`0x6F`. [forwarded]: it came over a forwarder or
  /// out of a post box — only a nudge is taken so.
  void receive(Uint8List p, InternetAddress from, int port, bool forwarded,
      List<Mailbox> mailboxes) {
    if (p.isEmpty) return;
    if (p[0] == kinds.kChannelNudge) {
      for (final m in mailboxes) {
        final opened = m.nudgeOpen(p);
        if (opened == null) continue;
        nudgesIn++;
        onNudge[m]?.call(opened.$1, opened.$2);
        return;
      }
      return; // no pair of this device sends under its code: silence (§11.6)
    }
    if (forwarded) return;
    final at = CardAddress(Uint8List.fromList(from.rawAddress), port);
    switch (p[0]) {
      case kinds.kChannelHold:
        keeper.onHold(p, at);
      case kinds.kChannelQuestion:
        keeper.onQuestion(p, at);
      case kinds.kChannelFetch:
        keeper.onFetch(p, at);
      case kinds.kChannelHeld:
        depositor.onHeld(p);
      case kinds.kChannelSame || kinds.kChannelList || kinds.kChannelEntry ||
            kinds.kChannelEnd:
        collector.onAnswer(p);
    }
  }
}

extension HostChannelWire on Host {
  /// Called once from `Host._wireUp`. The closure reads [mailboxes] on call.
  void channelWireUp() {
    final c = HostChannel.of(node);
    node.groupsReception =
        (p, from, port, forwarded) => c.receive(p, from, port, forwarded, mailboxes);
  }

  HostChannel get channel => HostChannel.of(node);
}
