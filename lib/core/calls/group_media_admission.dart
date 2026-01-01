/// Over which edge a group-call receiver takes a sender's media (§17.5).
///
/// ══ THE RULE ═══════════════════════════════════════════════════════
///
/// §17.5: "For groups, a separate `send_key` per sender, handed to every
/// participant end to end […] It does not prove the sender to a fellow
/// participant, who holds the same key; a receiver therefore takes a
/// sender's frames only over its media pair with that sender, from that
/// pair's broker, or over its tree link towards that sender (§17.7)."
///
/// The sender of a group frame is named by one byte, its slot in the
/// sorted participant list (`group_media_frame.dart`). Every participant
/// holds every sender's `send_key`, so any participant can seal a frame
/// under any slot (B-5 in `mycelium/berichte/S407-GRUPPENANRUF.md`). What
/// a forger cannot choose is the EDGE its frame arrives over — the Plane D
/// session it came by is authenticated pairwise (`call_key` per hop). The
/// binding to the edge therefore narrows forging to the one forwarder the
/// receiver itself depends on for that sender, without a byte more per
/// frame.
///
/// ══ THREE EDGES, AND WHO FILLS THEM ═══════════════════════════════════
///
/// 1. **The media pair with the sender**: the frame came straight from
///    the sender's own session. Always known.
/// 2. **The pair's broker** (§17.7, "a broker only where there is none"):
///    filled by the broker binding through [bindBroker] / [unbindBroker].
///    The binding itself (`relayAsk/Have/Bind/Bound`) is package P5 of
///    S407-GRUPPENANRUF; until it is built nobody calls [bindBroker], and
///    a frame relayed by a third participant in the mesh is refused —
///    which is right, because nobody has bound that third participant.
/// 3. **The tree link towards the sender**: read from the view of the
///    tree this participant holds ([OverlayTree.linkTowards]). A view is
///    either the whole tree (the participant that built it) or the own
///    place plus, per down-link, which participants lie behind it
///    ([ControlRecordType.treeSubtree]). Only a COMPLETE view may answer
///    "not behind any down-link, hence over the up-link"; an incomplete
///    one refuses what it cannot place.
library;

import 'package:cleona/core/calls/overlay_tree.dart';

/// Why a frame was taken — or that it was not.
enum EdgeVerdict {
  /// Straight from the sender (its media pair with us).
  mediaPair,

  /// From the broker bound for this sender.
  broker,

  /// Over our tree link towards the sender.
  treeLink,

  /// Over any other edge — dropped, not played, not passed on.
  refused,
}

/// The admission state of one group call, held by its session.
class GroupMediaAdmission {
  /// sender → the participant bound as broker for our pair with it.
  final Map<String, String> _brokerOf = <String, String>{};

  /// Whether the tree view answers "unknown, hence over the up-link".
  ///
  /// `true` for the participant that built the whole tree, for a
  /// participant without down-links (everything comes over the up-link),
  /// and after the subtree record of the current tree version has been
  /// applied. Reset with every new tree assignment.
  bool treeViewComplete = false;

  /// Frames refused so far — a counter for the log and the guards.
  int refused = 0;

  /// Bind [brokerHex] as the broker for our pair with [senderHex] (P5).
  void bindBroker(String senderHex, String brokerHex) =>
      _brokerOf[senderHex] = brokerHex;

  /// Release the broker binding for [senderHex] (P5: the pair gained a
  /// media pair of its own, the broker left, or it reached its limit).
  void unbindBroker(String senderHex) => _brokerOf.remove(senderHex);

  /// The broker bound for [senderHex], or `null`.
  String? brokerFor(String senderHex) => _brokerOf[senderHex];

  /// Decide on a frame that names [senderHex] and arrived over the
  /// Plane D session with [linkHex]. [tree] is `null` while this
  /// participant has no tree (mesh).
  EdgeVerdict judge({
    required String ownHex,
    required String linkHex,
    required String senderHex,
    required OverlayTree? tree,
  }) {
    if (senderHex == ownHex) return EdgeVerdict.refused;
    if (linkHex == senderHex) return EdgeVerdict.mediaPair;
    if (_brokerOf[senderHex] == linkHex) return EdgeVerdict.broker;
    if (tree != null) {
      final towards = tree.linkTowards(ownHex, senderHex) ??
          (treeViewComplete ? tree.upLinkOf(ownHex) : null);
      if (towards == linkHex) return EdgeVerdict.treeLink;
    }
    return EdgeVerdict.refused;
  }

  /// Forget everything — the call ended.
  void clear() {
    _brokerOf.clear();
    treeViewComplete = false;
    refused = 0;
  }
}
