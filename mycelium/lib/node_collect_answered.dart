/// "A collection ended with an answer from at least one holder" (v4_2 §8.2
/// "After more than 7 days", D-48).
///
/// A device keeps the moment its last collection ended WITH AN ANSWER; when
/// that moment lies more than 7 days back at the end of a collection, it asks
/// its parties for what it missed (§9.5). The delivery layer says only WHEN
/// such a collection ended, and for which identity — the moment, where it is
/// kept and what follows from it are the application's.
///
/// A collection nobody answered is not reported: it proves nothing about the
/// post box, and taking its end as the last stand would hide exactly the
/// absence the catching up is made for.
///
/// Next to the node, in an [Expando]: `node.dart` is at its line budget. No
/// clock: the function runs only where a collection round ends
/// (`NodePostBox`, §5.4, D-9).
library;

import 'package:mycelium/identity.dart' show Identity;
import 'package:mycelium/node.dart';

/// A collection of [identity] under its own day values has ended, and at
/// least one holder it asked answered that question to the end — handed out
/// what it announced, or said "nothing here" (`TalkEnd.answered`).
typedef CollectionAnswered = void Function(Identity identity);

final Expando<CollectionAnswered> _answered =
    Expando<CollectionAnswered>('collectionAnswered');

extension NodeCollectAnswered on Node {
  /// Who learns of every answered collection. One receiver; whoever needs
  /// several distributes (the app seam does, per identity).
  set onCollectionAnswered(CollectionAnswered? f) => _answered[this] = f;

  /// Called by `NodePostBox` where a round ends. A failing receiver is
  /// reported and does not disturb the round.
  void fireCollectionAnswered(Identity identity) {
    final f = _answered[this];
    if (f == null) return;
    try {
      f(identity);
    } on Object catch (e) {
      report('Collection answered: the receiver failed: $e');
    }
  }
}
