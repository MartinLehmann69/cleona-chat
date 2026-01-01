/// The cover stream at the node — network kind and start (S391, §5.1, §5.3; W1, W3).
///
/// Its own file, because `node.dart` is at the line budget. Here is HOW
/// the node learns whether its network is metered; the cover stream itself
/// (`cover_stream.dart`) asks nobody, it gets the value set.
///
/// **The question is asked by the app, not by mycelium.** Whether a connection is metered
/// is known by the operating system (W1), and the routes there (plugin,
/// method channel, `nmcli`, PowerShell) belong to the app
/// (`lib/core/util/network_metered.dart`). The seam sets [networkKindRead];
/// without it the stream stays at the W/LAN mean.
///
/// **Read only at edges**: at start ([coverAttach]) and at
/// every network change (`Node.networkEnvironmentNewRead`). No clock, no packet.
library;

import 'dart:async';

import 'package:mycelium/node.dart';

final Expando<Future<bool> Function()> _networkKind =
    Expando<Future<bool> Function()>('netzartLesen');

extension NodeCover on Node {
  /// Who reads the network kind — `true` means metered.
  set networkKindRead(Future<bool> Function()? read) => _networkKind[this] = read;

  /// Reads the network kind and sets it at the cover stream. An error while reading
  /// leaves the last value standing: the rate is an accessory, no reason to let a
  /// network edge fail.
  Future<void> networkKindNewRead() async {
    final read = _networkKind[this];
    if (read == null) return;
    try {
      coverStream.metered = await read();
    } on Object catch (e) {
      report('Cover stream: network type not readable ($e) — rate stays');
    }
  }

  /// Sets the reader and reads once — the edge „start" for the network kind.
  /// The stream itself is already running by then (`Node.start`).
  void coverAttach(Future<bool> Function() read) {
    networkKindRead = read;
    unawaited(networkKindNewRead());
  }
}
