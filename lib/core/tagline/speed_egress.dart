// The Speed egress — here WP-1, WP-2 and WP-3 come together.
//
// THE LAYERING, AND WHY IT IS THIS WAY ROUND.
//
// Aggregation happens BEFORE the onion, not after it. The onion delivers a
// finished cell of fixed size; what can be aggregated is its
// message area (822 B, WP-3). The other way round there would be nothing left to
// bundle, and the four short messages per cell from E-K would be lost.
//
//   messages -> cover stream aggregates (822 B) -> onion (1169 B) -> slot
//
// UNTIL S368 THIS SAID „onion (950 B)", and below „An empty slot
// delivers 950 B of randomness". Both numbers were wrong, and known since
// `VORLAGE-cover-fill-update-blocks.md` section 7 (no. 2): the
// code takes `kOnionCellBytes` = `kMaxFrameBodySize` = **1169**
// (`link/cell.dart:60`). S365 corrected the number at the site in
// `_buildCell` and explicitly noted there that the
// layer picture up here was „outdated too" — **without
// changing it**. Two lines away from the correction the
// wrong number thus still stood, and the module header is the place a
// builder reads first for §5.5.
//
// The onion is thus only built IN THE SLOT, not when enqueuing. That is
// no detail: if one built it when enqueuing, it would be fixed which
// messages travel together before the slot is due — and a
// message arriving later could no longer ride along, although there would still be
// room in the cell.
//
// DUMMY CELLS. An empty slot delivers 1169 B of randomness. That is no
// makeshift: a real cell is ciphertext throughout, so
// uniformly distributed randomness is exactly the right padding (§5.1 invariant 3).
// Whoever inserts zeros here makes every dummy recognisable at a glance.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/sync/cover_stream.dart';

import 'liveness.dart';
import 'onion.dart';

/// What a sender needs to reach a contact in Speed mode.
///
/// **No r1 in it any more.** The first hop is not chosen but supplied by the
/// slot plan (invariant 4, §5.1): if the sender chose it by
/// need, the target of the cell would hang on its content. The sender thus builds
/// for the partner it gets.
final class SpeedRoute {
  /// Whom r1 is to address next. **A knows this value** — it
  /// must know it to be able to route at all (see onion.dart).
  final Uint8List idOfR2;

  /// The path block from the receiver's liveness. Opaque to A.
  final Uint8List replyBlock;

  SpeedRoute({
    required this.idOfR2,
    required this.replyBlock,
  }) {
    if (replyBlock.length != kReplyBlockBytes) {
      throw ArgumentError('Route block must be $kReplyBlockBytes B');
    }
  }

  /// Builds the route from a liveness record.
  ///
  /// `returnPath` of the liveness IS the path block — the liveness carries it
  /// as opaque bytes, that is exactly what the field is for (§6).
  factory SpeedRoute.fromLiveness(
    LivenessRecord liveness, {
    required Uint8List idOfR2,
  }) =>
      SpeedRoute(idOfR2: idOfR2, replyBlock: liveness.returnPath);
}

final class SpeedEgress {
  /// The egress OWNS its stream.
  ///
  /// Otherwise a circularity arises: the stream needs the cell builder,
  /// the cell builder the routes of the egress. Whoever builds both separately
  /// ends up holding two objects with different route tables — the
  /// first test setup failed exactly on that, with „route lost during the
  /// slot".
  late final CoverStream stream;

  final Map<String, SpeedRoute> _routes = <String, SpeedRoute>{};

  /// Own random stream for the nonce seeds — it must not touch the slot plan,
  /// otherwise that hangs on demand again.
  final Random _seedRng;

  /// The link keys of the partners over which slots go. The slot plan
  /// chooses the index; this node supplies the key for it.
  ///
  /// Mutable: connections come and go. Whoever changes them must
  /// call [syncPartnerCount].
  final List<Uint8List> partnerLinkKeys;

  /// Reports to the slot plan how many partners there are now.
  void syncPartnerCount() =>
      stream.partnerCount = partnerLinkKeys.isEmpty ? 1 : partnerLinkKeys.length;

  SpeedEgress({
    required this.partnerLinkKeys,
    Duration meanInterval = kSlotInterval,
    int maxControlBacklog = kMaxControlBacklog,
    // NO DEFAULT VALUE (S376). Until then `int seed = 0` stood here, and
    // the only creator in `lib/` accepted the default — every
    // shipped node drew the same, publicly recomputable
    // slot and partner sequence, and from the same seed also the
    // onion nonces and the padding bytes of the dummy cells. Reasoning
    // in detail at `CoverStream.seed`.
    required int seed,
  }) : _seedRng = Random(seed ^ 0xa5a5a5) {
    // NO throw with an empty partner list: a node without a connection must
    // still keep the cycle. A stream that only starts with the first connection
    // would reveal the time of the first connection — and that
    // is exactly the kind of event the cover stream is meant to hide.
    // The slot then runs EMPTY: since S376 `DeliveryNode.tick` takes
    // nothing at all with an empty partner list and only finishes building the
    // dummy cell (`CoverStream.takeSlot(leerlauf: true)`). Until
    // then this said „the cell falls on the floor" — it did
    // actually fall, and with it the payload and the control frames that
    // had been taken beforehand.
    stream = CoverStream(
        meanInterval: meanInterval,
        seed: seed,
        partnerCount: partnerLinkKeys.length,
        maxControlBacklog: maxControlBacklog,
        cellBuilder: _buildCell);
  }

  void setRoute(String recipient, SpeedRoute route) =>
      _routes[recipient] = route;

  /// Withdraws a route.
  ///
  /// IT MUST BE WITHDRAWABLE, and for a reason that has nothing
  /// to do with tidying up: the path block is bound to ITS epoch
  /// (`relay.dart`, „a block for epoch e can no longer be opened
  /// in e+1"). A route that outlives the epoch is not
  /// noticed — it causes `hasRoute` to keep saying `true`, the cell
  /// to be built and sent and r2 to silently discard it. The sender would see
  /// an accepted message, the receiver never one. That is why
  /// the node throws it away at the epoch change (`V41Node._routenPflegen`)
  /// instead of hoping that it still holds.
  void clearRoute(String recipient) => _routes.remove(recipient);

  bool hasRoute(String recipient) => _routes.containsKey(recipient);

  /// Enqueues a message. Building happens only in the slot.
  void send(String recipient, Uint8List message, {bool ephemeral = false}) {
    if (!_routes.containsKey(recipient)) {
      throw StateError('no speed route for $recipient — the liveness '
          'of the contact is missing (§6, lazy on chat open, E-E)');
    }
    stream.enqueue(Outgoing(recipient, message, ephemeral: ephemeral));
  }

  Uint8List _seed() {
    final s = Uint8List(kSeedBytes);
    for (var i = 0; i < kSeedBytes; i++) {
      s[i] = _seedRng.nextInt(256);
    }
    return s;
  }

  Uint8List _buildCell(String? recipient, Uint8List payload, int partner) {
    if (recipient == null) {
      // Dummy: `kOnionCellBytes` = 1169 B of randomness, indistinguishable from
      // ciphertext.
      //
      // UNTIL S365 THIS SAID „950 B", and the number was wrong: the code
      // takes `kOnionCellBytes` = `kMaxFrameBodySize` = 1169
      // (`link/cell.dart:60`). The 950 came from the layer picture in the
      // module header — **which S365 left standing although it noted here
      // that it was outdated.** Since S368 the header also carries 1169.
      // The defect had stood open since `VORLAGE-cover-fill-update-blocks.md`
      // section 7 (no. 2) and is exactly the place a
      // builder opens first for paragraph 5.5.
      //
      // WHOEVER WANTS TO FILL THIS CELL DOES NOT DO IT HERE. Paragraph 5.5
      // („Cover fill carries fountain blocks") starts at exactly ONE
      // other place: `DeliveryNode.tick`, after `takeSlot` has delivered a
      // dummy. The reason is rule 3 of the section — the
      // block goes out as a `0x05` frame and not as a spore frame,
      // and which frame type a cell carries is decided by the node
      // and not by the cell builder. Whoever inserted the block here would deliver
      // it in a spore frame; the receiver would peel it as an
      // onion, fail at the AEAD and silently drop it.
      final d = Uint8List(kOnionCellBytes);
      for (var i = 0; i < d.length; i++) {
        d[i] = _seedRng.nextInt(256);
      }
      return d;
    }
    final route = _routes[recipient];
    if (route == null) {
      throw StateError('Route for $recipient lost during the slot');
    }
    return buildOnion(
      message: payload,
      // The first hop comes from the slot plan, not from the route.
      linkKeyToR1: partnerLinkKeys.isEmpty
          ? Uint8List(32)
          : partnerLinkKeys[partner % partnerLinkKeys.length],
      idOfR2: route.idOfR2,
      replyBlock: route.replyBlock,
      seed: _seed(),
    );
  }
}
