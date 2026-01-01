/// The node's [Silence] (V4.2 §11.3a): one instance per node, wired to the
/// neighbourhood (which addresses belong to the same node, §11.8) and to the
/// readiness (whether a failed address counts, §22.7.1).
///
/// Next to the node in an [Expando]: `node.dart` is at its line budget
/// (mycelium/README.md rule 2).
library;

import 'dart:io';

import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/silence.dart';

final Expando<Silence> _silence = Expando<Silence>('silence');

extension NodeSilence on Node {
  /// The one place a packet that expects an answer is repeated and given up.
  Silence get silence => _silence[this] ??= Silence(
        addressesOf: (a, p) => sameNode(neighbourhood, a, p, speaks),
        failed: readiness.addressFailed,
        report: report,
      );
}

/// [a]:[port] first, then the other addresses the neighbourhood holds for the
/// same node in a family this node speaks (§11.1, §11.8). An address the
/// list does not hold stands alone.
List<Address> sameNode(Neighbourhood n, InternetAddress a, int port,
    bool Function(InternetAddress) speaks) {
  final x = n.holding(a, port);
  return [
    (a, port),
    if (x != null)
      for (final y in x.addresses)
        if (!y.isAt(a, port) && speaks(y.address)) (y.address, y.port),
  ];
}
