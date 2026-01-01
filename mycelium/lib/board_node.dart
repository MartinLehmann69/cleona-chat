/// The board at the node (§11.8a) — attach and find.
///
/// A separate file for the same reason as `node_outside.dart`: `node.dart`
/// has no line budget left. The board therefore does not hang as a field on the
/// node, but via an [Expando]; the kind dispatch
/// (`node_helpers.dart`) asks [NodeAnswer.board].
///
/// Sending goes via [Node.rawSend] — splitter and shell, like every
/// packet. Without an attached board 0x43/0x44 are silently discarded: a
/// node without a board gives none (W6).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/address_entries.dart' show AddressList;
import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/node.dart';
import 'package:mycelium/board.dart';
import 'package:mycelium/board_proof.dart';
import 'package:mycelium/neighbourhood.dart' show Neighbour;
import 'package:mycelium/own_entries.dart';

final Expando<Board> _answers = Expando('neighbourAnswer');

extension NodeAnswer on Node {
  Board? get board => _answers[this];

  /// The passive proof under the shell of this node (`socketBuild`).
  ReachabilityProof? get passiveProof => proofTo(coverStream);

  /// Attaches the board. [confirmed] and [mappingProven] deliver the
  /// neighbourhood and the port mapping respectively (§7.3); [onBoardAnswer] gets the
  /// answering node's own addresses and the learned candidates.
  Board answerAttach({
    required List<Neighbour> Function(DateTime now) confirmed,
    required bool Function() mappingProven,
    void Function(AddressList l, InternetAddress from, int fromPort)?
        onBoardAnswer,
    Duration deadline = kBoardAnswerDeadline,
  }) =>
      _answers[this] = Board(
        send: (p, target, port) => rawSend(
            p, CardAddress(Uint8List.fromList(target.rawAddress), port)),
        confirmed: confirmed,
        mappingProven: mappingProven,
        own: (asker) => ownEntriesFor(this, asker), // S394 V3
        passive: passiveProof,
        onBoardAnswer: onBoardAnswer,
        deadline: deadline,
        report: report,
      );
}
