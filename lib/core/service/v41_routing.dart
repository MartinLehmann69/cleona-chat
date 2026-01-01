import 'package:cleona/core/bulk/bulk_params.dart' show kFountainWorthwhileBytes;
import 'package:cleona/generated/proto/transport_v3.pbenum.dart' as pe;

/// Which path a message takes (IP-3).
enum DeliveryRoute {
  /// Via the V4.1 delivery layer — cell in the cover stream.
  v41,

  /// Via the bulk lane (§9.3): the object is rateless-coded, every
  /// block placed EXACTLY ONCE with a responsible always-on holder,
  /// the recipient samples. No `m x R` (that cost a factor of 60), no
  /// block numbers, no index.
  ///
  /// SINCE THE CUT (31.08.2026) THE ONLY PATH FOR LARGE MEDIA. Before,
  /// this function returned `twoStage` for everything in [kMediaTypes] —
  /// the V3 path.
  bulkLane,

  /// Via the two-stage path that remains from V3.
  ///
  /// AFTER THE CUT ONLY FOR TWO THINGS: first contact
  /// ([kBootstrapTypes], B-25) and the V3 infrastructure that has no
  /// counterpart in V4.1 ([kV3InfraTypes]). **Media no longer** —
  /// that is step 1 of the CUT.
  twoStage,

  /// Via the INVITATION LINE of first contact (§15.3.2, §15.4).
  ///
  /// The only type that takes it is `MTV3_CONTACT_REQUEST` — §15.3.2
  /// binds the line normatively to exactly this one: "A cell harvested under
  /// `tag_I(i,e)` **MUST** be interpreted as a contact request. Every
  /// other inner message type is **discarded**."
  ///
  /// The delivery is the same Secure placement as [v41]; what differs is
  /// only the secret from which the tag derives (`K_inv(i)` instead of
  /// `K_AB`) and the path to sealing (`V41Host.sendInviteRequest`
  /// instead of `sendFrame`). That is why it is a ROUTE and not a second
  /// transport.
  inviteLine,

  /// Fits nowhere: a type classified as small that itself breaks the
  /// split limit. Is refused, not redirected.
  refuseTooLarge,
}

/// The switch in the body of `sendToUser`.
///
/// FOUR CLASSES. Until the cut there were three; the fourth is the bulk lane.
///
///   * **Content types** (TEXT, EDIT, poll free text, calendar
///     description): unbounded only because a string has no limit, in
///     practice small — a whole paragraph measures 190 B as measured. They
///     go via V4.1, and the size is their gate.
///   * **Media control flow** ([kMediaControlTypes]): ordinary
///     messages in the chat's mode, any size (§9.3).
///   * **Media payload** ([kMediaPayloadTypes]): >= 32 KB onto the
///     bulk lane, below onto the cell path (§9.3, lower bound —
///     lowered on 31.08.2026, see below).
///   * **V3 infrastructure and level D** ([kV3InfraTypes]): fragments,
///     DHT, live call frames. They continue to go the other way — not
///     because they are "large", but because they have no counterpart in V4.1
///     or belong on level D.
///
/// **SIZE DECIDES ONLY WITHIN THE MEDIA PAYLOAD.** Until the
/// cut this said: "they ALWAYS go the other way, even if the
/// single message is small — otherwise the behaviour would depend on the content".
/// That was right for the two-stage path and is wrong for the media lanes:
/// §9.3 explicitly makes size the criterion because the
/// rateless overhead is a FUNCTION OF SIZE. The old concern remains
/// answered, only differently — the same FILE always takes the same path,
/// because its size does not change.
///
/// **WHAT IS MEASURED IS THE WHOLE FRAME, not the payload.** `MEDIA_ANNOUNCE`
/// has an empty payload and nevertheless carries a preview image of up to
/// 100 KB — in `contentMetadata`, outside the payload. Whoever measures only the
/// payload lets it through.
///
/// **No fallback.** If the V4.1 layer refuses (no pair key,
/// not ready), the message does NOT go via V3 as a substitute. This
/// rule binds the caller, not this function — it is here
/// so that it is read at the same place.
///
/// **THE LIMIT IS NO LONGER THE CELL (S349).** Until S349 this
/// function refused every frame larger than a cell carries —
/// and that was the latch before every first contact: the answer to a
/// contact request measures ~3.4 KB against ~1041 B cell content, so
/// it was rejected with `refuseTooLarge` and the relationship never came
/// about. §15.4 itself computes first contact at "~11-14 cells";
/// a limit of one cell thus contradicted the own architecture.
///
/// Since the delivery layer splits (`frame_split.dart`), [cellLimit] is
/// the SPLIT limit (`kMaxSplitPayloadBytes`, measured 32768 B).
///
/// **THE GAP BETWEEN 32 KB AND 256 KB IS CLOSED** (31.08.2026). §9.3
/// set the lower bound of the media lanes at ~256 KB and said
/// at the same time that the offline promise is kept "by the tag line (**<= 32 KB** via
/// frame splitting) and the bulk lane". In between the
/// document named no path, and this function invented none: it returned
/// [DeliveryRoute.refuseTooLarge]. That hit the
/// normal case photo — an image of 200 KB did not go out.
///
/// The owner lowered the lower bound to **32 KB**
/// ([kFountainWorthwhileBytes]). Thus the two limits
/// meet: what breaks the split limit is large enough for the
/// bulk lane, and there is no longer a size for which both refuse.
/// `test/smoke/smoke_v41_routing.dart` measures exactly that over the whole
/// band, not on one example.
///
/// The price of lowering was stated in `bulk_params.dart` and was
/// paid there: the rateless overhead is large and long-tailed for small objects,
/// therefore `BulkSender.plannedBlocks`
/// no longer plans with the mean curve there, but counts on the graph
/// how many consecutive seeds REALLY suffice
/// (`bulk_prefix.dart`).
///
/// ── STEP 1 OF THE CUT (31.08.2026): MEDIA LEAVE V3 ──────────────────
///
/// Until today a line stood here that sent EVERYTHING from [kBulkTypes] to
/// `twoStage` — the V3 path. The fountain codec
/// (`lib/core/fountain/`) and the bulk lane (`lib/core/bulk/`) were
/// built and had not a single consumer in `lib/`: built, not
/// routed, the most frequent error class of this project (S347, S349).
///
/// §9.3 prescribes three size ranges, and this function hits them:
///
/// | Frame | Path | Spec |
/// |---|---|---|
/// | < [mediaLaneFloorBytes] | [DeliveryRoute.v41] — cell path like every message | "below the floor **neither lane is used**" |
/// | >= [mediaLaneFloorBytes] | [DeliveryRoute.bulkLane] | "the same fountain blocks are placed once each on always-on bulk holders" |
/// | control flow, any size | [DeliveryRoute.v41] | "announce …, request, refill, DECODED receipt — rides the delivery layer in the chat's mode" |
///
/// **THE LOWER BOUND IS A NUMBER WITH A PRICE, AND THE PRICE IS
/// PAID.** §9.3 justified the 256 KB by measurement: the rateless
/// overhead is 1.021 at 200 MiB, but 1.367 at 64 KiB, and at
/// 16 KiB two of four thousand runs did not reconstruct even at 3k.
/// The argument was never "more expensive", but
/// **"less predictable"** — Reed-Solomon cost a fixed 1.43 without a tail.
///
/// The tail is gone with the exact prefix, not with a
/// larger surcharge: `bulk_prefix.dart:exactSequentialPrefix` counts
/// on the graph, for objects up to 4 MiB, how many consecutive seeds
/// suffice (measured 0..50 ms). It turned out that the old planning
/// in the band 32..256 KiB provided too few blocks in **56 of 225** sizes ALREADY AT ZERO LOSS
/// — so the error was not the lowering,
/// but was there before and merely hidden by the lower bound.
///
/// **HERE THE FRAME IS MEASURED, THERE THE OBJECT.** This function
/// sees only the frame (§B-27: `MEDIA_ANNOUNCE` carries its preview in
/// `contentMetadata`, not in the payload — whoever measures only the payload
/// lets it through). The decision PER TRANSFER — stream or bulk,
/// and whether a Secure chat consents at all — is made one level
/// higher in `chooseMediaLane` (`lib/core/bulk/bulk_lane.dart`), which knows the
/// object size. Both gates carry the same number
/// ([kFountainWorthwhileBytes]); measuring twice is intentional here, because
/// the two places see different sizes and neither of the two
/// can replace the other.
///
/// **THE STREAM LANE (§17.6) IS NOT IN THIS ENUMERATION.** It
/// needs level D. It will later come NEXT TO [DeliveryRoute.bulkLane],
/// not in its place: §9.3 "Blocks are lane-neutral … a transfer
/// interrupted on one lane finishes on the other with no byte of received
/// progress lost". This switch need not change for that — the
/// lane choice lives in `chooseMediaLane`.
DeliveryRoute routeFor({
  required pe.MessageTypeV3 type,
  required int frameBytes,
  required int cellLimit,

  /// Overrides [kV3InfraTypes] — the set that may still go onto the
  /// two-stage path AFTER the cut. Was called `bulk` until the cut and meant
  /// [kBulkTypes]; the rename is intended because the MEANING
  /// has changed: media are no longer in it.
  Set<pe.MessageTypeV3>? infra,

  /// The lower bound of the media lanes from §9.3.
  int mediaLaneFloorBytes = kFountainWorthwhileBytes,
}) {
  // ── FIRST CONTACT FIRST (§15.2, §15.3.2) ───────────────────────────
  //
  // The REQUEST takes the invitation line. It must, because the
  // issuer cannot form `K_AB` before receiving the request — he
  // does not know that the requester exists. §15.3.2 gives it for this
  // a tagline of its own per invitation.
  //
  // THE ANSWER DOES NOT. Until S360 it was in the same set and thus went
  // onto the two-stage path — which fell with the CUT, so that
  // `acceptContactRequest` ended with `false` and B could not answer
  // at all. §15.2 explicitly says the opposite: "Even the reply
  // already runs under `K_AB`. Only the very first message of the pair —
  // the request itself — needs the invite family. Everything after that
  // (reply, delivery receipts, messages, prekey refills) is ordinary §4.3
  // traffic."
  //
  // The circle that the old comment below describes is thus not
  // glossed over, but resolved: it arose when the ContactSeed
  // carried no `ep`. But a seed without `ep` also carries no `ki` and
  // since S360 could not trigger a request at all — the then
  // `sendContactRequest` rejected it with a named reason instead of letting it
  // run into a delivery whose answer nobody can harvest.
  // S389: the path no longer exists (S388-BAU-KONTAKT), and neither does a
  // seed READER (package 17 = A) — the first request on
  // V4.2 comes from the invitation card (§15.5).
  if (kBootstrapTypes.contains(type)) return DeliveryRoute.inviteLine;

  // ── MEDIA (§9.3) ───────────────────────────────────────────────────
  //
  // The control flow FIRST, and separate from the payload. It is
  // ordinary message traffic — "rides the delivery layer in the
  // chat's mode" — and must NEVER get onto the bulk lane, not even
  // if its frame is large. An offer with a 100 KB preview
  // (the V3 cut) is not a bulk object, but an offer that
  // is too large against §9.3: the micro-preview measures <= 979 B, "(one
  // cell)". Therefore `refuseTooLarge` here instead of a silent redirect.
  if (kMediaControlTypes.contains(type)) {
    return frameBytes > cellLimit
        ? DeliveryRoute.refuseTooLarge
        : DeliveryRoute.v41;
  }
  if (kMediaPayloadTypes.contains(type)) {
    if (frameBytes >= mediaLaneFloorBytes) return DeliveryRoute.bulkLane;
    // Below the lower bound: the cell path, like every message — and
    // thus also its split limit. What breaks it is REFUSED
    // and not lifted onto the bulk lane as a substitute; that would be exactly the
    // lowering of the lower bound that §9.3 excludes.
    return frameBytes > cellLimit
        ? DeliveryRoute.refuseTooLarge
        : DeliveryRoute.v41;
  }

  // ── WHAT STAYS V3 AFTER THE CUT ────────────────────────────────────
  //
  // Erasure fragments and DHT are V3 INFRASTRUCTURE without a V4.1 counterpart;
  // the live call frames belong on level D (§17), not in the
  // delivery layer. Both are NOT the subject of step 1 and stand
  // here unchanged — visible in a set of their own, so that the next
  // cut stage finds them instead of searching for them in [kBulkTypes].
  if ((infra ?? kV3InfraTypes).contains(type)) return DeliveryRoute.twoStage;

  if (frameBytes > cellLimit) return DeliveryRoute.refuseTooLarge;
  return DeliveryRoute.v41;
}

/// Types that may NOT take the V4.1 path because the recipient at
/// this point cannot yet form a pair key.
///
/// ── THE FIRST-CONTACT CIRCLE (B-25, S349) ───────────────────────────
///
/// Measured in the field on 28.08.: the phone sent a contact request to
/// Charly, Charly accepted and answered — and on the phone appeared
/// **no contact**. The reason was in the phone's log:
///
///     "V4.1: kein Paarschluessel fuer 5d032d7a — weder ContactSeed-ep
///     noch Ed25519 des Kontakts liegen vor (§15.2)"
///
/// `K_AB` comes from the founding keys of both sides. The
/// ANSWERING side has both (its own plus the one from the request), the
/// REQUESTING side only if its ContactSeed carried `ep`. If it does not,
/// a circle arises: the answer carries the missing key, but lies
/// on a tagline that nobody harvests without exactly this key.
///
/// ── HOW S360 RESOLVES IT ────────────────────────────────────────────
///
/// The circle has a condition: "only if its ContactSeed carried `ep`".
/// Exactly there the resolution starts, instead of sending the answer onto a
/// third path.
///
///   * The REQUEST goes onto the invitation line `σ(i,e)` from `K_inv(i)`
///     (§15.3.2). It is the only type of this set.
///   * A seed without `ep` also has no `ki` — both are in the same
///     field schema (§15.5) and are written by the same output.
///     Without `ki` there is no invitation line, so the then
///     `sendContactRequest` refused with a named reason. The case "request
///     in transit, answer not harvestable" can thus no longer arise.
///     (S389: `sendContactRequest` has been dropped since S388-BAU-KONTAKT;
///     the first request comes from the invitation card, §15.5.)
///   * The ANSWER is ordinary `K_AB` traffic (§15.2). It USED TO BE
///     here and therefore went onto the two-stage path; after the CUT that meant:
///     `acceptContactRequest` could not answer.
///
/// From the first regular message on, the requester has the keys
/// from the answer and computes `K_AB` itself; everything further runs via
/// V4.1.
const Set<pe.MessageTypeV3> kBootstrapTypes = {
  pe.MessageTypeV3.MTV3_CONTACT_REQUEST,
};

/// The CONTROL FLOW of the media lanes (§9.3).
///
/// §9.3 enumerates it exhaustively: "Control flow — **announce** with a
/// one-cell micro-preview, **request**, **refill**, **DECODED receipt** —
/// rides the delivery layer in the chat's mode." That is the point: they
/// are ORDINARY messages, they have no transport of their own and
/// no clock of their own.
///
/// The four V3 types carry the four V4.1 roles; the encoding behind it
/// is in `lib/core/bulk/bulk_control.dart` and carries a marker
/// byte of its own per role (`0xB1`..`0xB4`), so that request and
/// re-request can share the same type.
///
/// **`MEDIA_CHUNK` IS DELIBERATELY NOT HERE.** It is not a
/// control frame, but the payload carrier of the V3 two-stage path
/// (<= 32 KB per piece). In V4.1 there is no counterpart to it: blocks
/// are CELLS of entry type `0x05`, not application messages. It
/// is therefore with the payload, where the size rule hits it.
const Set<pe.MessageTypeV3> kMediaControlTypes = {
  pe.MessageTypeV3.MTV3_MEDIA_ANNOUNCE, // §9.3 „announce"
  pe.MessageTypeV3.MTV3_MEDIA_REQUEST, // §9.3 „request" + „refill"
  pe.MessageTypeV3.MTV3_MEDIA_COMPLETE, // §9.3 „DECODED receipt"
  pe.MessageTypeV3.MTV3_MEDIA_REJECT,
};

/// Media PAYLOAD — the types over which the bytes of an object travel.
///
/// Their path depends on the size, and that is the ONLY place in this
/// file where size decides over the class. §9.3:
/// "**A lower bound, and it is normative: below ~256 KB neither lane is
/// used.**" — the number has been 32 KB since 31.08.2026
/// ([kFountainWorthwhileBytes]); the reasoning why that is no
/// softening of the spec is there.
const Set<pe.MessageTypeV3> kMediaPayloadTypes = {
  pe.MessageTypeV3.MTV3_MEDIA_INLINE,
  pe.MessageTypeV3.MTV3_VOICE_MESSAGE, // Alias von MEDIA_INLINE
  pe.MessageTypeV3.MTV3_FILE_EXCHANGE,
  pe.MessageTypeV3.MTV3_MEDIA_CHUNK, // V3 carrier, without V4.1 counterpart
};

/// Everything that is media — control flow and payload.
///
/// **NONE OF THESE TYPES MAY STILL YIELD `twoStage`.** That is step 1
/// of the CUT, and `test/smoke/smoke_media_lane_guard.dart` measures it.
const Set<pe.MessageTypeV3> kMediaTypes = {
  ...kMediaControlTypes,
  ...kMediaPayloadTypes,
};

/// V3 infrastructure and level D — what still goes onto the
/// two-stage path AFTER the cut.
///
/// Two different reasons, deliberately in one set, because for this
/// switch they have the same result:
///
///   * **Erasure fragments and DHT** are V3 INFRASTRUCTURE and not
///     message traffic. V4.1 has no DHT of this kind and no
///     Reed-Solomon on the delivery path (§9.3: "Reed-Solomon survives
///     solely as the recovery bundle's cell-level coding"). They die
///     with the V3 line, not via a redirect.
///   * **Live call frames** belong on level D (§17, §22.5.2) and have
///     no business in the delivery layer. `CALL_AUDIO` breaks the cell limit
///     at full Opus bitrate anyway.
///
/// They are in a set of their OWN and no longer in one pot with the
/// media, so that the next cut stage finds them.
const Set<pe.MessageTypeV3> kV3InfraTypes = {
  // ── Erasure-Fragmente ──────────────────────────────────────────────
  pe.MessageTypeV3.MTV3_FRAGMENT_STORE,
  pe.MessageTypeV3.MTV3_FRAGMENT_STORE_ACK,
  pe.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE,
  pe.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE_RESPONSE,
  pe.MessageTypeV3.MTV3_FRAGMENT_DELETE,

  // ── Live-Anrufrahmen (Ebene D) ─────────────────────────────────────
  pe.MessageTypeV3.MTV3_CALL_AUDIO,
  pe.MessageTypeV3.MTV3_CALL_VIDEO,
  pe.MessageTypeV3.MTV3_CALL_GROUP_AUDIO,
  pe.MessageTypeV3.MTV3_CALL_GROUP_VIDEO,

  // ── DHT ────────────────────────────────────────────────────────────
  pe.MessageTypeV3.MTV3_DHT_PING,
  pe.MessageTypeV3.MTV3_DHT_PONG, // ~1.4 KB with kem_record
  pe.MessageTypeV3.MTV3_DHT_STORE,
  pe.MessageTypeV3.MTV3_DHT_STORE_RESPONSE,
  pe.MessageTypeV3.MTV3_DHT_FIND_NODE,
  pe.MessageTypeV3.MTV3_DHT_FIND_NODE_RESPONSE,
  pe.MessageTypeV3.MTV3_DHT_FIND_VALUE,
  pe.MessageTypeV3.MTV3_DHT_FIND_VALUE_RESPONSE,
};

/// Types that by their NATURE carry bulk — media AND V3 infrastructure.
///
/// ── SINCE THE CUT IT HAS NO CODE READER IN `lib/`, RE-MEASURED ───────
///
/// `grep -rn kBulkTypes lib/` on **2026-09-03** (the count of
/// 31.08.2026 named four hits at four lines that have since moved
/// and was thus outdated): **three** hits outside this file,
/// all three in COMMENTS — `cleona_service_msgstate.dart:447`, `:705`
/// and `cleona_service.dart:11123`. [routeFor] no longer reads it
/// — it reads [kMediaControlTypes], [kMediaPayloadTypes] and
/// [kV3InfraTypes] separately, because they yield three different paths.
/// It has no CODE reader in `lib/`; in `test/` it does —
/// `smoke_media_lane_guard.dart:154` measures the union.
///
/// It stays nevertheless, and for a reason, not out of
/// convenience: the three comment sites explain why a
/// DELIVERY_RECEIPT comes back via V4.1 ("is neither in
/// `kBootstrapTypes` nor in `kBulkTypes`"). If one deleted the name,
/// four justifications would point into the void — the same kind of dangling reference that
/// had to be cleaned up at §9. Written as a UNION it cannot
/// drift from the two live sets;
/// `test/smoke/smoke_media_lane_guard.dart` checks the equality.
const Set<pe.MessageTypeV3> kBulkTypes = {
  ...kMediaTypes,
  ...kV3InfraTypes,
};

/// The readable part of a pair designator for the log.
///
/// ── WHY THIS IS A FUNCTION OF ITS OWN (S350) ────────────────────────
///
/// The designator of a pair is `own/other` (`_v41PeerKey`,
/// B-31): 64 digits own identity, a slash, 64 digits
/// other side. Whoever takes `substring(0, 8)` of it shows **always the same
/// eight digits of the OWN identity** — in every line, for every
/// other side. Exactly that stood in the send line until S350
/// (`cleona_service.dart`: "V4.1 SENDEN … an ${peer.substring(0, 8)}"),
/// and a log that writes the same for every recipient cannot
/// answer the question "did it go to the right one?".
///
/// `V41Node._peerLabel` has done it right since S349; this function is
/// the same procedure at the place where the service layer needs it.
/// It is here and not a private method because a private
/// method of `CleonaService` would not be checkable — and this line was
/// wrong because nobody checked it.
String shortPairLabel(String peer) {
  String short(String x) => x.length <= 8 ? x : x.substring(0, 8);
  final parts = peer.split('/');
  if (parts.length == 2) return '${short(parts[0])}->${short(parts[1])}';
  return short(peer);
}


/// Which message kind deserves a delivery confirmation.
///
/// ── RETRIEVED FROM `AckTracker` (CUT, 31.08.2026) ───────────────────
///
/// That was `AckTracker.isAckWorthyV3` and thus lived in
/// `lib/core/network/` — in the middle of the V3 transport, although the body is a
/// `switch` over message kinds and contains not a single network line.
/// The `AckTracker` itself fell without replacement (RUDP-Light,
/// timer, address rating, route failure); this statement did
/// not: it answers "should the recipient acknowledge?", and the
/// question arises in V4.1 just the same.
///
/// The DELIVERY_RECEIPT is explicitly a transport primitive and
/// is ALWAYS sent, even if the §14.7.4 display lock withholds the
/// STATUS (see `_withholdsDeliveryStatusTo`).
///
/// It is here and not a private method in the service because it is read at
/// two places of the receive path and must stay
/// checkable. The name keeps the `V3` because the enumeration runs over
/// `MessageTypeV3` — the same reasoning from which
/// `kV3InfraTypes` above is so named.
bool isAckWorthyV3(pe.MessageTypeV3 type) {
  switch (type) {
    // Content
    case pe.MessageTypeV3.MTV3_TEXT:
    case pe.MessageTypeV3.MTV3_MEDIA_INLINE:
    case pe.MessageTypeV3.MTV3_MEDIA_ANNOUNCE:
    case pe.MessageTypeV3.MTV3_MEDIA_REQUEST:
    case pe.MessageTypeV3.MTV3_EDIT:
    case pe.MessageTypeV3.MTV3_DELETE:
    case pe.MessageTypeV3.MTV3_REACTION:
    // Group lifecycle
    case pe.MessageTypeV3.MTV3_GROUP_CREATE:
    case pe.MessageTypeV3.MTV3_GROUP_INVITE:
    case pe.MessageTypeV3.MTV3_GROUP_LEAVE:
    // Channel lifecycle
    case pe.MessageTypeV3.MTV3_CHANNEL_INVITE:
    case pe.MessageTypeV3.MTV3_CHANNEL_LEAVE:
    case pe.MessageTypeV3.MTV3_CHANNEL_ROLE_UPDATE:
    // Contact establishment
    case pe.MessageTypeV3.MTV3_CONTACT_REQUEST:
    case pe.MessageTypeV3.MTV3_CONTACT_REQUEST_RESPONSE:
    // Calendar
    case pe.MessageTypeV3.MTV3_CALENDAR_INVITE:
    case pe.MessageTypeV3.MTV3_CALENDAR_RSVP:
    case pe.MessageTypeV3.MTV3_CALENDAR_UPDATE:
    case pe.MessageTypeV3.MTV3_CALENDAR_DELETE:
    // Polls
    case pe.MessageTypeV3.MTV3_POLL_CREATE:
    case pe.MessageTypeV3.MTV3_POLL_VOTE:
    case pe.MessageTypeV3.MTV3_POLL_UPDATE:
    case pe.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS:
    // Identity-layer infra warranting confirmation
    case pe.MessageTypeV3.MTV3_PROFILE_UPDATE:
    case pe.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST:
    case pe.MessageTypeV3.MTV3_RESTORE_BROADCAST:
    case pe.MessageTypeV3.MTV3_CHAT_CONFIG_UPDATE:
    case pe.MessageTypeV3.MTV3_IDENTITY_DELETED:
      return true;
    default:
      return false;
  }
}
