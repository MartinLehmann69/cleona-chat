/// The system channels at the mycelium host (v4_2 §16.0, §16.7; S407 SK-4):
/// the device's [SystemChannelHub] gets the host's transport
/// (`HostDurable.durableAttach`), and the edges of §16.0 reach it here.
///
/// The edges, and ONLY these (SK-1 finding B2):
/// * start — [systemChannelsAttach], called by `hostStart`;
/// * network change — [hostNetworkChanged], run by the one entry
///   `networkChangeEdge` (`mycelium_seam.dart`) every source goes through;
/// * a new neighbour — `Host.onNewNeighbours`, set in `hostStart`;
/// * the user opened a channel — `SystemChannelApi.channelOpened`.
/// A collection the application runs for its own reasons (enrolment,
/// recovery, the app opened) is no edge of this class.
///
/// A desktop holds both channels (25 MB each), a phone none and reads into
/// its 5 MB cache (D-55): the hub's store decides, `!Android && !iOS`.
library;

import 'package:cleona/core/channels/system_channel_hub.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:mycelium/durable_fetch.dart' show nodeKey;
import 'package:mycelium/durable_node.dart' show HostDurable;
import 'package:mycelium/host.dart';

final Expando<SystemChannelHub> _hubOfHost = Expando('system-channel-hub');

/// Attaches the device's system channels to [host] — the edge "start".
/// [service] names the device (its device database); every identity on
/// the host shares the hub.
void systemChannelsAttach(Host host, CleonaService service,
    {void Function(String)? report}) {
  if (_hubOfHost[host] != null) return;
  final hub = service.systemChannelHub;
  _hubOfHost[host] = hub;
  hub.isContact = (node) => isContactDevice(host, node);
  hub.attach(host.durableAttach(hub.stock));
  report?.call('mycelium:system channels attached '
      '(${hub.store.holds ? 'holder' : 'reader'})');
}

/// The edge "network change" or "a new neighbour" for the system channels.
void systemChannelsEdge(Host host) => _hubOfHost[host]?.edge();

/// The network changed: the host reads it anew, then the system channels
/// take the edge — the host part of the one entry `networkChangeEdge`
/// (`mycelium_seam.dart`, S407-LB-P12), its only caller, so the edge cannot
/// be forgotten at one of the sources.
Future<void> hostNetworkChanged(Host host) async {
  await host.networkChanged();
  systemChannelsEdge(host);
}

/// Whether [node] (`address:port`) is a device of a contact of any
/// identity on [host]: where the contact was last seen or what its card
/// names (§16.7: devices of non-contacts first).
bool isContactDevice(Host host, String node) {
  for (final p in host.mailboxes) {
    for (final k in p.contacts) {
      final seen = k.lastSeen;
      if (seen != null && nodeKey(seen) == node) return true;
      for (final a in k.cardsAddresses) {
        if (nodeKey(a) == node) return true;
      }
    }
  }
  return false;
}
