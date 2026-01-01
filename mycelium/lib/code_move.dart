/// The fixed neighbour moves a device's code-table entry (V4.2 §8.1
/// "Safety net: the neighbour reports a move", §11.8.9; S407 C-13).
///
/// A keep-alive or a registration of a registered device that arrives from
/// another address than the device's entry IN THAT FAMILY holds
/// ([CodeTable.holds]) is treated as §11.8.6 says: ONE request to that
/// address — the address question `0x40`, repeated as §11.3a says, shared
/// with the return-and-move rule of `node_roam.dart` — and only on its answer
/// does the entry move ([CodeTable.moveConfirmed]). Until then step 3 keeps
/// forwarding to the old entry. A keep-alive or registration replayed from a
/// third address brings no answer there and moves nothing — path validation
/// as QUIC does it (RFC 9000 §8.2).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/node.dart';
import 'package:mycelium/node_roam.dart';

/// [device] showed up at [a]:[p] (keep-alive or registration). If that is
/// not its entry in that family, one path request goes out; [answered] runs
/// only once [a]:[p] answered it — without one, the entry follows as after
/// a registration (`node_codes.dart`).
void codeMoveAsk(Node k, Uint8List device, InternetAddress a, int p,
    {void Function()? answered}) {
  final table = k.codeRoute.table;
  if (table.holds(device, a, p)) return;
  answered ??= () => table.moveConfirmed(device, a, p, registration: true);
  final who = device
      .take(4)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();
  k.report('Device $who seen at ${a.address}:$p, not its entry in that family '
      '— path request before the entry moves (§11.8.9)');
  unawaited(nodePathAnswered(k, a, p).then((ok) {
    if (ok) answered!();
  }));
}
