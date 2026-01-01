import 'dart:typed_data';

import 'readiness.dart';

// Whoever implements this interface must be able to name [Readiness].
export 'readiness.dart' show Readiness;
import 'package:cleona/core/sync/delivery_params.dart' show kInteractiveDeliveryTtl;

/// In which mode a message goes out.
///
/// The sender decides, one-sidedly and per chat (§7, WP-7). There is no
/// field on the wire that names the mode — it is an egress choice.
enum SendMode {
  /// Two-hop onion, seconds, linkable (§7).
  speed,

  /// Placement with the responsible relays, hidden in the cover, ~1 h (§8).
  secure,

  /// Like [speed], but WITHOUT fallback to the placement: if no route exists,
  /// it is discarded instead of placed.
  ///
  /// FOR TRANSIENT INDICATORS that only make sense now. A
  /// typing indicator that lies in a placement for an hour and then
  /// arrives is no longer information, but misdirection — it
  /// claims someone is typing right now.
  ///
  /// WHAT IT COSTS TODAY, measured on 30.08.: [speed] falls back without a route
  /// to Secure (`V41Node.send`), and a Secure placement costs
  /// `m x R` control frames — in the field 18 per message, with an outflow
  /// of one cell per 8 s. Of 108 control frames from six transmissions
  /// only 36 belonged to the two texts; the rest were typing indicators,
  /// receipts and a configuration message. The queue then stood
  /// at 115/120, and because a harvest run silently turns back from
  /// `pendingControl >= kHarvestBacklogLimit`, every
  /// sender thus switched off its own harvest.
  ///
  /// NOT for receipts: they must arrive, they flip the
  /// delivery status and the capsule proof. Only for what
  /// expires without value.
  speedOnly,

  /// Placement on the SIGNAL line (§17.2) — the call signalling.
  ///
  /// Like [secure] a placement with responsible relays, but on an
  /// OWN tagline and with an own retention class:
  /// `signalTag` instead of `secureTag`, `kSignalRelays` (5) instead of
  /// `kResponsibleRelays` (~20), `kRetentionSignal` instead of
  /// `kRetentionNormal`.
  ///
  /// ── WHY THIS MUST BE A PATH OF ITS OWN AND NOT SECURE ──────────────
  ///
  /// §17.2 gives the signal cell a TTL of 120 s. On the
  /// MESSAGE line a placement costs `m x R = 3 x 20 = 60`
  /// placements; at one cell per 8 s that is **480 s egress against
  /// a TTL of 120 s** — the INVITE has expired before it
  /// lies completely, and a family-wise order would leave two of three families empty
  /// when the deadline expires (measured 31.08.2026).
  /// The signal line places `m x kSignalRelays = 15` and thus fits into
  /// exactly one cover budget of 120 s: the INVITE lies completely
  /// within its own TTL.
  ///
  /// **The traded-away redundancy is an owner decision**
  /// (2026-08-31), not an oversight: a real-time signal is by its nature
  /// censorable, and `m = 3` buys far less for it than for a
  /// message that has seven days. A 25 % fleet hits a
  /// 5-relay set with 76 % against 99.7 % at 20.
  ///
  /// **The fallback goes to [secure], never to [speed].** A device in the
  /// background cannot be reached via the onion; the placement is
  /// the only path on which a call rings at all (§17.2).
  signal,
}

/// Which path a message takes — the ONE place where this is
/// decided.
///
/// `null` means: do not send at all.
///
/// ── THE INVARIANT (owner, 30.08.) ─────────────────────────────────────
///
/// **A fallback from Speed to Secure is defensible. The opposite
/// direction never, without the user noticing.**
///
/// Speed is linkable (§7); Secure is the user's explicit choice
/// against exactly that (§12, one-sided and local per sender). Latency
/// may be imposed on him without asking, the loss of anonymity
/// not. As long as work is done with mycelium and these two modes, that applies
/// without exception.
///
/// That is why this function is pulled out and did not remain an expression in the
/// send path: the invariant is thus exhaustively checkable
/// (`smoke_v41_mode_invariant.dart` runs all eight combinations), instead of
/// depending on the shape of a `?:` expression.
///
/// [ephemeral] are kinds that only make sense NOW — today
/// only the typing indicator. In a Speed chat they go via
/// [SendMode.speedOnly] and are discarded without a route; in a
/// Secure chat they do NOT go AT ALL. Sending them via the placement
/// would cost `m x R` control frames for an indicator that lies an hour
/// later anyway — and sending them via Speed would be the
/// forbidden downgrade.
///
/// ── [skipL3] IS THE CALL SIGNALLING, AND IT GOES ONTO THE
///    HARVEST PATH (§17.2, corrected S357) ────────────────────────────
///
/// **The name is a V3 remnant** — "Layer 3" there meant store-and-forward,
/// and the reasoning was: a signalling must not lie in a placement
/// for days. On the V4.1 line the reasoning is
/// REVERSED. §17.2 ("Why signaling rides harvest, not Speed
/// forwarding"), literally:
///
///     "Speed-Mode (§7) forwards along a 2-hop onion to a device that is
///      reachable by the relay path *right now*; a device in the
///      background is not. The harvest path (§8) is the mechanism that
///      reaches a device regardless of foreground state […] there is no
///      cached Speed path to a device whose reachability is uncertain."
///
/// A call that only a device in the foreground can take is
/// no call. Therefore the signalling goes via the PLACEMENT — and
/// it is bounded not by the mode, but by the
/// TTL class [kInteractiveDeliveryTtl] (§17.2: "Short ,interactive'
/// delivery TTL (120 s) […] It buys **freshness** (an INVITE cannot ring
/// days later)").
///
/// NO VIOLATION OF THE INVARIANT, but its defusing. The
/// old branch delivered `SendMode.speed` in a Secure chat — the
/// only place in the whole design where a Secure wish became a
/// linkable path. It was listed as a named exception; now
/// the exception no longer exists, and the invariant applies
/// without exception. The direction of this change is Speed -> Secure, i.e.
/// the explicitly defensible one.
///
/// [ephemeral] plays no role here anymore: no signalling type
/// is transient (the set in `cleona_service.dart` contains only
/// the typing indicator), and what limits a signalling in time is
/// the TTL class and not the dropping of the fallback.
SendMode? sendMode({
  required bool secureDesired,
  required bool skipL3,
  required bool ephemeral,
}) {
  // Call signalling: HARVEST path, always. It must reach a device in the
  // background, and only the placement can do that (§17.2).
  //
  // ON THE SIGNAL LINE, NOT ON THE MESSAGE LINE — since S360.
  // Until then this said `SendMode.secure`, and thus the information
  // "this is a signalling" was used up before it
  // reached `V41Node.send`: `placeSecure(signal: true)` was built, measured
  // (`smoke_v41_signal_line.dart`) and had NO caller in `lib/`.
  // An INVITE lay on the message line and cost 60 placements
  // = 480 s egress against its own TTL of 120 s. The reasoning
  // in full at [SendMode.signal].
  if (skipL3) return SendMode.signal;
  if (secureDesired) {
    // No path from here to Speed. Transient content is discarded.
    return ephemeral ? null : SendMode.secure;
  }
  return ephemeral ? SendMode.speedOnly : SendMode.speed;
}

/// The short delivery TTL class "interactive" from §17.2, literally:
///
///     "**Short ,interactive' delivery TTL (120 s).** Signaling cells
///      carry a third, short TTL class. It buys **freshness** (an INVITE
///      cannot ring days later) and keeps dead ring signals off the
///      relays. […] An INVITE is **placed once**; there is **no
///      retransmission** — which is why its survival on the recipient's
///      tag line is a delivery property, not a detail: the 120 s TTL must
///      exceed the recipient's harvest interval, and the R≈20 redundancy
///      with m=3 (§9) ensures the INVITE is placed even across
///      partly-hostile relays."
///
/// ── WHAT THIS CONSTANT BINDS TODAY, AND WHAT NOT ─────────────────────
///
/// **It binds the CALLER SIDE.** `CallManager.reachingTimeoutSec` is
/// derived from it: waiting longer for a RING_ACK than the
/// signal cell may live at all would mean waiting for an answer to something
/// that no longer exists. The two numbers must not
/// diverge; `smoke_v41_signaling_ttl.dart` checks that.
///
/// **IT BINDS THE RELAY SIDE — since S358, and this paragraph said the opposite
/// until S361.** Here stood, measured on 31.08.: "`SecureStore`
/// knows only ONE deadline for all cells … A cell carries on the
/// wire no field at all in which a class could stand …
/// `DeliveryNode` stamps `epochNow()` on placement and nothing else."
/// **All three claims are false**, re-measured on 01.09. against
/// `ca263694`:
///
///   * the class is on the wire — `buildPlace(..., retention:)`
///     writes it (`secure_frames.dart:299,342`), `openPlace` returns
///     it (`:362,393`), `isKnownAufbewahrung` (`:251`)
///     rejects an unknown one;
///   * `DeliveryNode` stamps it together with the bucket
///     (`delivery_node.dart:547-548`);
///   * `SecureStore.expire` is a three-way switch over
///     [kRetentionSignal] / [kRetentionManagement] / normal class
///     (`secure_mode.dart:570-579`, the switch in l. 574-579).
///
/// The signal cell thus lives guaranteed longer than 120 s and at most
/// 240 s ([kSignalKeepBuckets] = 2, re-measured there: min 121 s, mean
/// 180.5 s, max 240 s) — against three days before S358. **The sentence "an INVITE
/// cannot ring days later" holds.**
///
/// ── WHAT IS OPEN INSTEAD ────────────────────────────────────────────
///
/// The class is chosen at exactly ONE place, and that place knows
/// only two of the three: `v41_node.dart:1966` computes
/// `signal ? kRetentionSignal : kRetentionNormal`. **[kRetentionManagement]
/// thus has no setting site in the whole tree** — the management class
/// is defined, validated, expires correctly and is never assigned.
/// What the application still cannot do is pass a class down from above:
/// `V41Host.sendFrame` and `CleonaService.sendToUser`
/// carry no field for it, the mode decides it.
///
/// **That is the reason why the paragraph above could stand wrong
/// for so long** — it described a real deficiency, only the
/// wrong one. The correction does not belong here, but to the
/// retention package; the owner's commitment of 01.09. ("the
/// recovery phrase must survive at least 31 days offline") depends on it.

/// Why a message was not accepted.
///
/// Every refusal has a NAME. A `false` without a reason forces the
/// layer above to guess, and then it guesses wrong.
enum SendRefusal {
  /// No pair key for this counterpart — the delivery layer knows
  /// only pairs, not contacts (§11.1).
  noPairKey,

  /// Larger than a cell carries. **No error of the delivery, but
  /// the declared limit from §5.3/B-13:** media belong on the
  /// two-stage path and do not ride along in the cover stream.
  tooLarge,

  /// No confirmed relay yet — nothing can be placed
  /// (§22.7, `searching`).
  notReady,
}

/// What became of a send attempt.
///
/// WHY NOT `bool`. The V3 contract returned `true` if at least
/// one direct device leg had left the node — and `false` otherwise,
/// where `false` was explicitly NOT an error (the message may be resting in the network).
/// This ambiguity was carried by the layer above for years.
/// Here instead stands what really happened.
final class SendOutcome {
  /// Accepted and queued into the stream.
  final bool accepted;

  /// Only set if not accepted.
  final SendRefusal? refusal;

  /// How many legs went out — for Secure the families (m), for
  /// Speed one. With several pieces the SUM over all.
  final int legs;

  /// Into how many pieces the sealed message fell apart.
  ///
  /// ── WHY THIS NUMBER MUST TAKE THE PATH UPWARD ─────────────────────
  ///
  /// A message is not always ONE cell on the wire. `V41Host`
  /// seals first and splits afterwards (`_sendSealed`), and with the
  /// FIRST frame of a day the day capsule travels along (§4.3, 1088 B) —
  /// the sealed frame then no longer fits into any cell, no matter how
  /// small one makes the piece. The split is not a special case there,
  /// but the rule.
  ///
  /// The delivery record above (`DeliveryRecord`) needs the number because it
  /// otherwise CANNOT say whether a message rests completely. Without
  /// it "two families rest" would be a statement about some
  /// piece; with it, it is a statement about the message. And the
  /// recipient cannot check a single piece — the AEAD only holds
  /// over the whole (see "ALL OR NOTHING" in `v41_host.dart`).
  ///
  /// `0` means "unknown": a refused attempt has no pieces.
  final int pieces;

  /// The identifier of this send attempt (see `V41Delivery.send`).
  final int transferId;

  const SendOutcome.accepted(this.legs, {this.pieces = 1, this.transferId = 0})
      : accepted = true,
        refusal = null;

  const SendOutcome.refused(this.refusal)
      : accepted = false,
        legs = 0,
        pieces = 0,
        transferId = 0;

  @override
  String toString() => accepted
      ? 'accepted ($legs legs, $pieces pieces, attempt $transferId)'
      : 'refused (${refusal!.name})';
}

/// The entry point into the V4.1 delivery (IP-2).
///
/// WHAT IT EXISTS FOR. `sendToUser` (`service_context.dart`) is the
/// contract on which 62 callers hang, and its body today is the
/// complete V3 cascade. The seam (IP-3) rewires this body; for that it
/// needs something to point to. This is it.
///
/// WHAT DOES NOT BELONG IN HERE — and that is the reason why the
/// interface is so narrow: the delivery layer knows no contacts,
/// no groups, no message types and no protobuf frames. It
/// knows pairs and bytes. Everything the V3 contract carries beyond that
/// — group identifier, roster epoch, edit and expiry metadata, the
/// KEM overrides —, belongs in the frame that the layer
/// above builds, and passes through here as `payload`. Whoever mixes that
/// pulls half the application into delivery.
/// A confirmed own placement — the proof on which `placed` rests.
///
/// ── WHY RELAY AND NETWORK BLOCK TRAVEL ALONG, NOT ONLY THE FAMILY ────
///
/// §22.5.1 says literally: `placed` is set "**exclusively** by ≥ 2
/// placement acknowledgments **from independent relays in different
/// partitions** — partition = address block, `/24` v4 / `/48` v6". The
/// family is something else: it is the m = 3 redundancy, i.e. AGAINST
/// HOW MANY censorships the cell rests, not FROM HOW MANY HANDS the
/// proof comes.
///
/// The two do not coincide, and in a small network they diverge
/// systematically: `responsibleRelays` computes a separate target per family,
/// but it draws from the same routing table. With four
/// known nodes all three families deliver the same four relays —
/// **the same relay then acknowledges family 0 AND family 1**, and a
/// counter over families would flip to `placed` with the proof of a
/// single hand. Exactly the state that claims more than its proof
/// carries.
///
/// `delivery_state.dart` itself registered this debt as long as there was
/// no producer ("family and partition are not the same … the
/// partition check belongs at the place that will one day call `notePlaced`").
/// With the producer it becomes due.
///
/// [partitions] is empty if no interpretable
/// entry record exists for the relay. That is no error: the proof then counts
/// as ONE, but lends independence to no second one
/// (`Partition.independentCount`).
typedef PlacementAck = ({
  /// The application's recognition value, as passed in with `send`.
  Uint8List messageId,

  /// The send attempt to which this piece belongs.
  int transferId,

  /// The running number of the piece in this attempt.
  int piece,

  /// The family under which the cell rested — for the m redundancy.
  int family,

  /// The position of the storing relay.
  Uint8List relay,

  /// The network blocks of this relay.
  Set<String> partitions,
});

abstract interface class V41Delivery {
  /// The largest payload that fits through this path.
  ///
  /// It is small, and that is no oversight: a cell carries 1200 B,
  /// and the cover clock is at the same time the send limit (B-13). Whoever wants to
  /// send more takes the two-stage path.
  int get maxPayloadBytes;

  /// Remembers the pair key for a counterpart.
  ///
  /// Without it liveness and Secure tags cannot be computed. It is
  /// passed in from above because the delivery layer knows no contact list
  /// and is not supposed to know one.
  ///
  /// [outDirection] is the canonical outbound direction of the pair
  /// (`pair_registry.dart`, `outboundDirection`). It decides under
  /// which tagline placement happens and under which harvesting — without it
  /// each side harvests back its own placements (B-22, §15.2
  /// "`tag(K_AB, B→A)`").
  ///
  /// [harvest] `false` registers the counterpart as a pure PLACEMENT target:
  /// it is supplied, but never harvested and publishes no
  /// liveness. The only case for that is the DEVICE LINE of a
  /// sibling (§14.7, `device_line.dart`) — there it is not the
  /// sealing that separates (§14.2: all own devices can open the same cell),
  /// but exactly the question of who harvests the line.
  void rememberPeer(String peer, Uint8List kAb,
      {int outDirection = 0, bool harvest = true});

  /// Forgets the pair key and everything hanging on it.
  ///
  /// THE COUNTERPART OF [rememberPeer], and it was missing until S354:
  /// `PairRegistry.forget` was built and had no caller in `lib/`.
  /// A deleted contact thus stayed in the delivery layer —
  /// the node kept publishing liveness for it (§6, cost per
  /// Speed contact), kept harvesting under its tags, and the
  /// pair key survived the deletion in memory. §21.5.1 says
  /// what has to disappear on deletion.
  void forgetPeer(String peer);

  /// Makes sure that a Speed route exists for [peer] — i.e. fetches
  /// its liveness if necessary (§6).
  ///
  /// WHY THIS IS AN ACTION OF ITS OWN AND NOT INSIDE [send]. §6,
  /// E-E: the liveness is fetched "lazily when a chat is opened, not at
  /// contact-add and not only on first send" — when the chat is opened,
  /// so that the first typed message is already fast. If the
  /// fetch were inside `send`, the first message of every conversation would
  /// necessarily be the slow one; and bound to contact-add, one would pay
  /// for it for every contact that nobody ever addresses.
  ///
  /// Returns `true` if a valid route exists afterwards. `false` means
  /// "not yet" and is no error: the request then runs, and until
  /// the answer is there, [send] takes the Secure path (§7.2, the
  /// epoch cold start falls into the same cadence).
  bool prepareSpeed(String peer);

  /// Tells the delivery layer whether the chat with [peer] is set to Secure
  /// (§12).
  ///
  /// WHY THE LAYER MUST KNOW THIS, although the mode is passed along per message:
  /// the own liveness is published not per message, but
  /// per epoch, and §6 explicitly binds its cost to
  /// this setting — "only Speed-capable contacts need liveness …  the
  /// per-chat Secure/Speed setting (§12) therefore bounds this cost
  /// directly". Without the information the effort scales with all
  /// contacts instead of with the speed-capable ones.
  ///
  /// Not set means speed-capable — Speed is the default (§12).
  void setChatMode(String peer, {required bool secure});

  /// The readiness state (§22.7).
  ///
  /// WHY THIS IS ON THIS INTERFACE and not only in the node.
  /// §22.7 makes readiness the ONLY quantity that speaks about
  /// deliverability — display gates, function gates and the
  /// E2E gates (§28.7) hang on it. Until S356 the
  /// `ReadinessTracker` held the state node-internally; above this layer
  /// it did not exist, and every gate above had to query a
  /// peer NUMBER as a substitute. Exactly that is forbidden by §22.7: "gates hang off the
  /// readiness state `ready`, never off a raw acquaintance count."
  ///
  /// The state is LIVE, not a latch: if the session falls, the
  /// proof falls (`ReadinessTracker.forgetPartner`). §22.7.2 says
  /// explicitly that a latch and a live comparison are not
  /// the same predicate.
  Readiness get readinessState;

  /// Confirmed sync partners that this node ITSELF reaches (§25.4).
  ///
  /// WHY THE NUMBERS GO SEPARATELY OVER THIS INTERFACE. §25.4
  /// lists them as two metrics with two different statements:
  /// outbound "carries the node's own delivery and feeds readiness",
  /// inbound "states how much the node contributes for others; a
  /// precondition for inbound calls (§17)". A sum answers neither
  /// of the two questions — and the display layer cannot produce the separation
  /// itself: which side opened a session is known
  /// only to the node (`V41Node._inbound`).
  ///
  /// What is counted is PARTNERS, not sessions (§25.7).
  int get syncPartnersOutbound;

  /// Confirmed sync partners that reach THIS node (§25.4).
  int get syncPartnersInbound;

  /// Of which independent (§25.4, §22.7) — the number `ready` hangs on.
  ///
  /// Separate from [syncPartnersOutbound] because §25.4 demands it
  /// separately: "not the gross count". Two partners behind the same
  /// network block are ONE, and a display that conceals that reports
  /// a redundancy that is not there when it counts.
  int get independentSyncPartners;

  /// How many responsible relays a Secure placement reaches TODAY.
  ///
  /// ── WHAT THE DISPLAY NEEDS THIS NUMBER FOR (02.09.2026) ────────────
  ///
  /// A Secure placement costs `m x R` frames (§9.2), and `R` is NOT
  /// `kResponsibleRelays`, but `min(kResponsibleRelays, as many as
  /// the node knows)` — `responsibleRelays` stops when the
  /// candidate list is exhausted. In the field that is 3 x 20 = 60 frames
  /// = 480 s egress, in the three-node lab 3 x 3 = 9 frames = 72 s. The
  /// factor between the two is 6.7, and a display that takes the nominal quantity
  /// for reality is off by exactly that.
  ///
  /// **Do NOT take [syncPartnersOutbound] as a substitute.** That is a
  /// different quantity: session partners are those with which a LINK LAYER
  /// is up; responsible relays are those that are responsible for a TAG
  /// (§9.1, distance in the metric space plus suitability gate). The two
  /// sets overlap, but are neither contained in each other
  /// nor equally large.
  int get reachableResponsibleRelays;

  // ── S373: THE CONSENTED COVER SWITCH-OFF IN THE OWN NETWORK ─────────
  //
  // Only what the UI needs, and explicitly NO setter for
  // the switch-off itself: nobody switches it, it results from
  // consent AND situation (`V41Node.lanConfined`). A setter would be the
  // door through which it could be switched on by hand after all.

  /// The identifiers of the segments this node currently sits in.
  /// Empty means "no own network recognised" — then the cover stays on.
  List<String> get lanSegmentIds;

  /// The segments for which a consent CAN be given at all
  /// — i.e. those in which currently at least one neighbour with a
  /// verified position sits.
  ///
  /// It stands separately next to [lanSegmentIds] because the UI must show the
  /// difference BEFORE anyone presses: a segment without
  /// witnesses gets no button, but the reason
  /// ('lan_shaping_no_witness'). And because the desktop UI sits behind
  /// the IPC boundary and would otherwise have to apply the same rule there a second time
  /// instead of guessing it (the same pattern as
  /// `dataSaverLockedBySecure`).
  List<String> get lanSegmentsGrantable;

  /// Whether a consent exists for [segmentId]. **Not** the same
  /// as "it is in effect": a Secure chat or an outside partner
  /// overrides it without revoking it.
  bool lanSegmentConsented(String segmentId);

  /// Grants the consent for [segmentId]. **Only a
  /// user action calls this** — the same constraint as for
  /// `setDataSaver` (§24.4.2: "the app may suggest but must never
  /// activate it itself"), and here breaking it would be more expensive.
  ///
  /// `false` if there is no witness to which the consent could
  /// bind (no neighbour with a verified position in the segment).
  /// The reason is REPORTED BACK and not swallowed: a setter
  /// that silently does nothing cannot be told apart from a broken one.
  bool grantLanShaping(String segmentId);

  /// Takes it back. ALWAYS works — a revocation leads to MORE cover.
  bool revokeLanShaping(String segmentId);

  /// The consents as a JSON-capable structure, for the store.
  ///
  /// OVER THIS INTERFACE AND NOT OVER THE CLASS: the service would
  /// otherwise have an import edge onto `tagline/v41_node.dart`, i.e. onto
  /// the 5000-line composition of the delivery layer, for a list of
  /// strings. What it needs is one write point and one read point.
  Map<String, dynamic> lanConsentToJson();

  /// Loads them from the store. An unusable record is DISCARDED
  /// and not repaired (see `SegmentConsent.fromJson`) — a
  /// half-baked consent would be none.
  void lanConsentLoadJson(Object? raw);

  /// Is called when a consent has changed; the service
  /// then writes it away.
  set onLanConsentChanged(void Function()? cb);

  /// Submits a message.
  ///
  /// It does NOT go out immediately — it waits for a slot. That is
  /// invariant 1: the clock does not depend on demand.
  SendOutcome send({
    required String peer,
    required Uint8List payload,
    required SendMode mode,
    // ── WHY THE DELIVERY LAYER GETS A MESSAGE IDENTIFIER ─────────────
    //
    // It knows no messages, only pairs and bytes — and that stays
    // so. [messageId] is NOT read, not derived and not put on
    // the wire; it is an opaque recognition value
    // that the layer above passes in and gets back in the placement receipt.
    // Without it `placed` can have no producer: the
    // receipt names a leg, and which MESSAGE this leg carried
    // is known only to the sender.
    //
    // [piece] is the running number of the piece of the same message.
    // It must go along because `placed` is a statement about the WHOLE message:
    // if two families of the first piece rest and none of the second,
    // nothing is delivered — the recipient cannot even check a single piece
    // (the AEAD only holds over the whole).
    // [transferId] is the identifier of THIS send attempt. It must go along
    // because `V41Host.sendFrame` seals ANEW on every attempt (new
    // ephemeral key, new split, possibly a different
    // piece count if the capsule status changed in the meantime). Without it
    // "piece 0 from attempt 1" and "piece 1 from attempt 2" could be
    // added up to a `placed`, although NO complete sealing
    // rests anywhere — the recipient reassembles by `(transferId, total)`,
    // not by message.
    Uint8List? messageId,
    int transferId = 0,
    int piece = 0,
    // §22.5.1 specifies `TtlClass ttl` on `sendToUser` — not
    // built in the code (`TtlClass` exists nowhere, S361 finding). [management]
    // is the minimal equivalent: only effective for [SendMode.secure],
    // chooses `kRetentionManagement` (31 d) instead of `kRetentionNormal`
    // (`kNormalKeepEpochs` = 14 d since S363/D2; here stood "3 d" as long as
    // the deadline hung on the subscription depth `kHarvestEpochs`) at the
    // only setting site (`V41Node.placeSecure`). For
    // every other mode without effect — there is no caller today
    // that sets both at the same time.
    bool management = false,
  });

  /// Reports confirmed placements to the layer above.
  ///
  /// It is called ONLY for own placements whose receipt verified under the
  /// ack key of the target relay (`verifyPlaceAck`) — an
  /// unauthenticated or foreign receipt does not reach this path. The
  /// values are those the caller passed in with [send],
  /// plus the family under which the placement rested.
  ///
  /// ── A SECOND CALL APPENDS (S376, P5 finding 1) ────────────────────
  ///
  /// HERE STOOD: "A second call REPLACES the first; there is exactly
  /// one sink."
  ///
  /// The sentence was the reason why the single slot in the node was considered
  /// right — and it is incompatible with multi-identity: `attachV41` runs
  /// PER IDENTITY against THE SAME node (all three entry points
  /// have a loop over their identities). With three identities
  /// only the last attached one got its placement receipts; for the
  /// two others `placed` never reached the display, and their local
  /// outbox (§21.2) never released their entries.
  ///
  /// Since then: **every sink stays until it is removed.**
  /// Registering the same sink twice stays once — two identical
  /// sinks would mean two proofs from one receipt, and
  /// `DeliveryRecord.notePlaced` counts relays, not calls.
  ///
  /// **Whoever registers also deregisters.** The implementation in the node is called
  /// `V41Node.unbindPlacementAcked`; `attachV41` puts the deregistration into
  /// `V41Host.deregistrations`, and `V41Host.dispose` executes it. Without
  /// that the node would report to a stopped service after `removeIdentity`.
  void bindPlacementAcked(void Function(PlacementAck ack) sink);
}
