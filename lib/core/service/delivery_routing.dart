import 'package:cleona/generated/proto/transport.pbenum.dart' as pe;

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
const Set<pe.MessageType> kOffDeliveryTypes = {
  // ── Erasure-Fragmente ──────────────────────────────────────────────
  pe.MessageType.MT_FRAGMENT_STORE,
  pe.MessageType.MT_FRAGMENT_STORE_ACK,
  pe.MessageType.MT_FRAGMENT_RETRIEVE,
  pe.MessageType.MT_FRAGMENT_RETRIEVE_RESPONSE,
  pe.MessageType.MT_FRAGMENT_DELETE,

  // ── Live-Anrufrahmen (Ebene D) ─────────────────────────────────────
  pe.MessageType.MT_CALL_AUDIO,
  pe.MessageType.MT_CALL_VIDEO,
  pe.MessageType.MT_CALL_GROUP_AUDIO,
  pe.MessageType.MT_CALL_GROUP_VIDEO,

  // ── DHT ────────────────────────────────────────────────────────────
  pe.MessageType.MT_DHT_PING,
  pe.MessageType.MT_DHT_PONG, // ~1.4 KB with kem_record
  pe.MessageType.MT_DHT_STORE,
  pe.MessageType.MT_DHT_STORE_RESPONSE,
  pe.MessageType.MT_DHT_FIND_NODE,
  pe.MessageType.MT_DHT_FIND_NODE_RESPONSE,
  pe.MessageType.MT_DHT_FIND_VALUE,
  pe.MessageType.MT_DHT_FIND_VALUE_RESPONSE,
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
/// That was `AckTracker.isAckWorthy` and thus lived in
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
/// `MessageType` — the same reasoning from which
/// `kOffDeliveryTypes` above is so named.
bool isAckWorthy(pe.MessageType type) {
  switch (type) {
    // Content
    case pe.MessageType.MT_TEXT:
    case pe.MessageType.MT_MEDIA_INLINE:
    // NOT `MT_MEDIA_ANNOUNCE` (S398 P2b, Q1): its receipt goes only once
    // the object decodes (§9.4, D-29) — `cleona_service_bulk.dart` sends it.
    case pe.MessageType.MT_MEDIA_REQUEST:
    case pe.MessageType.MT_EDIT:
    case pe.MessageType.MT_DELETE:
    case pe.MessageType.MT_REACTION:
    // §17.2: the missed-call message is "acknowledged … like any message".
    case pe.MessageType.MT_CALL_MISSED:
    // Group lifecycle
    case pe.MessageType.MT_GROUP_CREATE:
    case pe.MessageType.MT_GROUP_INVITE:
    case pe.MessageType.MT_GROUP_LEAVE:
    case pe.MessageType.MT_GROUP_JOIN: // B-3: the explicit join (§16.2.2)
    // Channel lifecycle
    case pe.MessageType.MT_CHANNEL_INVITE:
    case pe.MessageType.MT_CHANNEL_LEAVE:
    case pe.MessageType.MT_CHANNEL_ROLE_UPDATE:
    // Contact establishment
    case pe.MessageType.MT_CONTACT_REQUEST:
    case pe.MessageType.MT_CONTACT_REQUEST_RESPONSE:
    // Calendar
    case pe.MessageType.MT_CALENDAR_INVITE:
    case pe.MessageType.MT_CALENDAR_RSVP:
    case pe.MessageType.MT_CALENDAR_UPDATE:
    case pe.MessageType.MT_CALENDAR_DELETE:
    // Polls
    case pe.MessageType.MT_POLL_CREATE:
    case pe.MessageType.MT_POLL_VOTE:
    case pe.MessageType.MT_POLL_UPDATE:
    case pe.MessageType.MT_POLL_VOTE_ANONYMOUS:
    // Identity-layer infra warranting confirmation
    case pe.MessageType.MT_PROFILE_UPDATE:
    case pe.MessageType.MT_KEY_ROTATION_BROADCAST:
    case pe.MessageType.MT_CHAT_CONFIG_UPDATE:
    case pe.MessageType.MT_IDENTITY_DELETED:
      return true;
    default:
      return false;
  }
}
