// Delivery state — what "delivered" means, and who may say it.
//
// TWO RECEIPTS THAT ARE NOT THE SAME (D2, E-F).
//
//   Transport ack: a relay confirms having accepted the cell.
//     Fast, useful, and **not trustworthy** — the relay can
//     lie, and it does not know anyway whether the recipient ever harvests.
//     It does NOT flip "delivered".
//   E2E receipt: only the recipient can produce it, because it stands under
//     `K_AB`. IT alone flips "delivered".
//
// That is the protection against silent deletion: an attacker who
// swallows the cell cannot forge a receipt, and the sender never sees the
// delivery as done.
//
// M FAMILIES (D1). A delivery goes over m=3 families. "Placed"
// means: at least one family rests. It is censorship-resistant only when
// all three rest — therefore both numbers are kept and not merged
// into one. Whoever shows only "placed" hides that two
// families are missing.
//
// OFFLINE IS NO ERROR. A recipient who does not harvest is the
// normal case (§9.2, work rule: "An offline recipient is NOT an
// error"). `failed` is reserved solely for what could be placed
// NOWHERE.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

import 'package:cleona/core/sync/partition.dart';
import 'package:cleona/core/sync/delivery_params.dart' show kDeliveryFamilies;

/// From how many placements a delivery counts as `placed`.
///
/// **TWO, not one** (§22.5.1: "`placed` hinges on the placement
/// acknowledgment — >= 2 from independent relays"; §21.2 lets the cell
/// out of the local outbox only at two receipts for the same reason).
/// A single placement is no proof: "independent" is a statement at all
/// only from two onwards, and a placement at exactly one relay
/// can be claimed by that relay alone.
///
/// Until S356 this said `isNotEmpty`, i.e. one. That was the same weakness
/// that AP-4 just removed from `MessageStatus.sent`: a state that
/// claims more than its proof carries.
///
/// **SINCE S357 IT IS THE NUMBER OF INDEPENDENT RELAYS, NOT OF FAMILIES.**
/// Until then the debt itself was registered here: "family and
/// partition are not the same … the partition check belongs at the
/// place that will one day call `notePlaced` — today it does not exist (no
/// producer)." With the producer it became due, and the cross-reading
/// showed that it was not merely imprecise, but wrong:
/// `responsibleRelays` computes a separate target per family, but draws from
/// THE SAME routing table. With four known nodes all three
/// families deliver the same four relays — the same relay then acknowledges family
/// 0 AND family 1, and a counter over families would flip to `placed` with
/// the proof of a single hand.
///
/// Counting therefore uses `Partition.independentCount`, the same
/// calculation that readiness uses too.
const int kPlacedMinIndependentRelays = 2;

enum DeliveryState {
  /// Nothing is resting yet.
  placing,

  /// At least [kPlacedMinIndependentRelays] independent relays have
  /// confirmed EVERY piece — the first state
  /// with a proof that does not come from a single relay.
  placed,

  /// All families rest — only here is the delivery censorship-resistant.
  redundant,

  /// The recipient has acknowledged. Only an E2E receipt leads here.
  delivered,

  /// Placeable nowhere. NOT for offline recipients.
  failed,
}

/// The receipt that only the recipient can produce.
///
/// A MAC under `K_AB` over the message identifier. Cannot be produced without `K_AB`
/// — and only the pair has `K_AB` (§9.2).
Uint8List makeReceipt(Uint8List kAb, Uint8List messageId) =>
    SodiumFFI().hkdfSha256(kAb,
        salt: messageId,
        info: Uint8List.fromList(utf8.encode('cleona-receipt')),
        length: 32);

bool verifyReceipt(Uint8List kAb, Uint8List messageId, Uint8List receipt) {
  final expected = makeReceipt(kAb, messageId);
  if (expected.length != receipt.length) return false;
  // Constant time: an early exit would be measurable.
  var diff = 0;
  for (var i = 0; i < expected.length; i++) {
    diff |= expected[i] ^ receipt[i];
  }
  return diff == 0;
}

/// The state of a delivery.
///
/// ── A MESSAGE IS NOT ALWAYS ONE CELL (S357) ─────────────────────────
///
/// `V41Host` seals first and splits afterwards; with the first frame of a
/// day the day capsule travels along (§4.3, 1088 B), and the sealed
/// frame then fits into NO cell anymore — recomputed: a piece
/// carries 1026 B payload, the capsule alone brings the frame to
/// at least 1185 B. The document says it itself (§4.3): "until the first
/// reply, each message carries 1,088 B extra and **splits into two cells
/// rather than one**."
///
/// From this follows the aggregation rule, and it is the conservative one:
/// **`placed` applies only when EVERY piece has its proof.** If two
/// relays of the first piece rest and none of the second, nothing is
/// delivered: the recipient cannot even CHECK a single piece,
/// because the AEAD only holds over the whole (`v41_host.dart`:
/// "ALL OR NOTHING"; `frame_split.dart`: "not authenticatable
/// individually"). §21.2 phrases the outbox rule accordingly in the
/// plural — "a node's own **cells** stay local until **their** placement
/// is substantiated".
///
/// **And proofs of different send attempts do NOT add up.** The
/// outbound re-offer (§5.1) submits the same message identifier again,
/// but `V41Host.sendFrame` seals afresh in the process: new
/// ephemeral key, new split, possibly a different
/// piece count. "Piece 0 from attempt 1" plus "piece 1 from attempt 2"
/// would otherwise yield `placed`, although no complete sealing
/// rests anywhere — the recipient reassembles by `(transferId, total)`,
/// not by message.
final class DeliveryRecord {
  final Uint8List messageId;

  /// The current send attempt, or `null` as long as none is reported.
  int? _attempt;

  /// How many pieces this attempt has.
  int _pieces = 0;

  /// Per piece: the families, and per relay its network blocks.
  final Map<int, _PieceState> _proPiece = <int, _PieceState>{};

  /// Transport acks are COUNTED, but they flip nothing.
  int transportAcks = 0;

  bool _receipted = false;
  bool _failed = false;

  DeliveryRecord(this.messageId);

  /// Registers a send attempt: [pieces] pieces under [transferId].
  ///
  /// A NEW attempt resets the proofs. That is no loss,
  /// but the truth: the cells of the previous attempt carry a
  /// different seal and cannot be assembled with those of this attempt.
  void noteAttempt(int transferId, int pieces) {
    if (pieces <= 0) return;
    if (_attempt == transferId && _pieces == pieces) return;
    _attempt = transferId;
    _pieces = pieces;
    _proPiece.clear();
    // ── AND `failed` FALLS (S360) ────────────────────────────────────
    //
    // Per §22.5.1 `failed` means EXACTLY ONE thing: "no relay reachable,
    // placement impossible". An ACCEPTED new send attempt
    // refutes that — something just went out. Without this line
    // the record would stay at `failed` after a successful re-offer from the
    // local outbox (§21.2), because [state] checks
    // `_failed && independentRelays == 0` and the proofs of the
    // new attempt take a harvest to arrive.
    //
    // MEASURED in `test/smoke/smoke_v41_outbox.dart` section 6: a
    // send refused with `notReady`, then an accepted
    // re-offer — the record kept reporting `failed`, and the display
    // would have shown the user a failure while the cells
    // were in transit.
    //
    // `MessageStatusGuard` above already reckons with this: "`failed` is
    // deliberately NOT terminal. It is an observation of one moment …
    // and the next moment may overturn it — the one-shot outbox
    // re-offers the cell on the next connectivity edge."
    //
    // ONLY HERE, and only via this path: [markFailed] sets the mark,
    // an ACCEPTED attempt takes it back. A renewed refusal
    // does not call `noteAttempt` at all — `_v41NoteSend` calls on
    // `!outcome.accepted` exclusively `markFailed`.
    _failed = false;
  }

  /// Takes in a confirmed placement.
  ///
  /// Proofs of a FOREIGN attempt are discarded — see the header.
  void notePlaced({
    required int transferId,
    required int piece,
    required int family,
    required Uint8List relay,
    Set<String> partitions = const <String>{},
  }) {
    if (family < 0 || family >= kDeliveryFamilies) {
      throw ArgumentError('family 0..${kDeliveryFamilies - 1}');
    }
    if (_attempt == null || transferId != _attempt) return;
    if (piece < 0 || piece >= _pieces) return;
    (_proPiece[piece] ??= _PieceState())
      ..families.add(family)
      ..blocksProRelay[base64.encode(relay)] = partitions;
  }

  void noteTransportAck() => transportAcks++;

  /// Accepts a receipt — only if it verifies under `K_AB`.
  bool noteReceipt(Uint8List kAb, Uint8List receipt) {
    if (!verifyReceipt(kAb, messageId, receipt)) return false;
    _receipted = true;
    return true;
  }

  /// Accepts the delivery as acknowledged because the RECEIPT FRAME was
  /// authenticated under `K_AB` — not because an own receipt MAC lay on the
  /// wire.
  ///
  /// ── WHY THIS SECOND DOOR EXISTS, and why it is no hole ──────────────
  ///
  /// §9.2 demands exactly one property: "Only the recipient, holding
  /// `K_AB`, can produce a receipt that flips the sender's 'delivered'
  /// state. … A receipt cannot be forged without `K_AB`." It does
  /// NOT demand that the proof stands as a field of its own next to the message identifier
  /// — it demands that no receipt arises without `K_AB`.
  ///
  /// On today's wire this property is delivered by the
  /// FRAME authentication: §4.4.3 lists the 1:1 message with signature
  /// **none** and justifies that with "the tag `HKDF(K_AB, …)`
  /// authenticates the sender symmetrically". The receipt frame therefore
  /// carries `v41SenderMac(K_AB, frame)`, and `verifyV41Sender`
  /// (`v41_host.dart`) checks it BEFORE the frame is unpacked at all.
  /// Whoever wants to forge the receipt must forge this MAC —
  /// i.e. have `K_AB`. That is the same gate that [noteReceipt]
  /// applies, only one layer deeper and once instead of twice.
  ///
  /// A SECOND MAC WOULD NO LONGER BE SECURITY, BUT MORE BYTES:
  /// 32 B per receipt, and a receipt in Speed mode is worth a whole
  /// cell (§9.2 computes the egress in cells, not in bytes).
  ///
  /// WHAT THE CALLER OWES, explicitly named because the name of the
  /// method no longer contains the check: it may call it ONLY
  /// if `verifyV41Sender` has returned `verified` for exactly this frame.
  /// `unverifiable`/`skippedBootstrap` does NOT suffice — there
  /// `K_AB` could not be formed at all, so the MAC was unchecked.
  /// [noteReceipt] stays for the day on which the proof stands as a field of its own
  /// on the wire; then THIS door is to be closed.
  void noteReceiptAuthenticatedByFrame() => _receipted = true;

  void markFailed() => _failed = true;

  /// How many independent relays have proven the weakest piece.
  ///
  /// `0` as long as no attempt is reported — without the piece count
  /// nothing can be said about the MESSAGE, only about individual pieces.
  int get independentRelays {
    if (_attempt == null || _pieces == 0) return 0;
    var smallest = 1 << 30;
    for (var i = 0; i < _pieces; i++) {
      final st = _proPiece[i];
      final n = st == null
          ? 0
          : Partition.independentCount(st.blocksProRelay.values);
      if (n < smallest) smallest = n;
    }
    return smallest;
  }

  /// The families that EVERY piece has reached — the intersection.
  Set<int> get placedFamilies {
    if (_attempt == null || _pieces == 0) return const <int>{};
    Set<int>? cut;
    for (var i = 0; i < _pieces; i++) {
      final f = _proPiece[i]?.families ?? const <int>{};
      cut = cut == null ? {...f} : cut.intersection(f);
      if (cut.isEmpty) return const <int>{};
    }
    return cut ?? const <int>{};
  }

  DeliveryState get state {
    if (_receipted) return DeliveryState.delivered;
    if (_failed && independentRelays == 0) return DeliveryState.failed;
    if (placedFamilies.length >= kDeliveryFamilies &&
        independentRelays >= kPlacedMinIndependentRelays) {
      return DeliveryState.redundant;
    }
    if (independentRelays >= kPlacedMinIndependentRelays) {
      return DeliveryState.placed;
    }
    return DeliveryState.placing;
  }

  /// How many families the weakest piece lacks for censorship
  /// resistance.
  int get missingFamilies => kDeliveryFamilies - placedFamilies.length;
}

/// The evidence state of ONE piece.
final class _PieceState {
  final Set<int> families = <int>{};

  /// Relay (base64 of the position) -> its network blocks.
  final Map<String, Set<String>> blocksProRelay = <String, Set<String>>{};
}

/// The delivery register of the node — ONE record per message sent
/// via V4.1.
///
/// ── WHAT IT EXISTS FOR ──────────────────────────────────────────────
///
/// [DeliveryRecord] describes the state of ONE delivery; nobody
/// held them. The application instead kept its delivery status
/// completely via the V3 path (`cleona_service_msgstate.dart`,
/// `MessageStatus`) — i.e. via a source that knows nothing of the rule of §9.2:
/// there EVERY incoming receipt frame flipped the display
/// to "delivered", regardless of whether it was authenticated under `K_AB`.
/// Exactly that is the case D2 wants to exclude (silent deletion with
/// a forged receipt).
///
/// This register is the one source for V4.1 messages. It does NOT REPLACE
/// `MessageStatus` — it decides whether the transition to
/// `delivered` may happen at all. Two state machines each with
/// its own verdict would be the double bookkeeping that is just
/// avoided here.
///
/// ── WHY IT IS CAPPED ────────────────────────────────────────────────
///
/// A daemon runs for weeks, and every sent message creates a
/// record. Without a cap the map grows without limit — the same
/// class of leak as the cool-down maps that
/// `_checkMessageExpiry` prunes hourly. Displacement is in
/// INSERTION ORDER (Dart map literals are insertion-ordered), i.e.
/// the oldest record first: a receipt that still arrives after [maxRecords]
/// further messages would anyway be beyond every
/// deadline that §9.2 names for Speed (~8.5 s) or Secure (~1 h).
///
/// DISPLACED DOES NOT MEAN REFUSED: if the register does not (or no longer) know an identifier,
/// the caller falls back to its previous behaviour.
/// A cap must not pin a message permanently to "not
/// delivered".
final class V41DeliveryRegister {
  /// How many deliveries are kept at the same time.
  ///
  /// 2048 is deliberately generous compared to everything that can be open within a
  /// deadline, and still small: a record holds an identifier
  /// (16 B), three family numbers and two booleans.
  static const int maxRecords = 2048;

  final Map<String, DeliveryRecord> _records = <String, DeliveryRecord>{};

  /// Creates the record for [messageIdHex] — or returns the existing one.
  ///
  /// IDEMPOTENT because it is the send side that calls it, and that can
  /// see an identifier again: the outbound re-offer (§5.1) submits
  /// a never placed message with THE SAME identifier again. A
  /// new record would thereby reset an already reached `delivered`.
  DeliveryRecord open(String messageIdHex, Uint8List messageId) {
    final present = _records[messageIdHex];
    if (present != null) return present;
    if (_records.length >= maxRecords) {
      _records.remove(_records.keys.first);
    }
    return _records[messageIdHex] = DeliveryRecord(messageId);
  }

  /// The record for [messageIdHex], or `null` — "do not know it".
  DeliveryRecord? lookup(String messageIdHex) => _records[messageIdHex];

  /// How many deliveries are kept. For diagnosis and tests.
  int get length => _records.length;
}
