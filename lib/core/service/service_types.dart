import 'dart:convert';
import 'dart:typed_data';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/log/log_redaction.dart';
import 'package:cleona/core/moderation/moderation_config.dart' show ReportCategory;
import 'package:cleona/generated/proto/transport_v3.pb.dart' as proto;

/// One built fan-out leg of a [ServiceContext.sendToUser] call: the outer
/// packet as it was signed for exactly one recipient device.
///
/// Exported so ephemeral signaling with its own retry schedule (CALL_INVITE,
/// §10.1) can re-dispatch the *identical* packet instead of re-running the
/// full inner pipeline (KEM + Ed25519 + ML-DSA + PoW) per retry. Re-sending
/// identical bytes is a plain retransmission: the receiver's §2.4 step [3b]
/// duplicate-frame cache drops copies that actually arrive twice, and a copy
/// whose predecessor was lost passes through normally. Callers MUST respect
/// the ±60 s outer-timestamp replay window (§2.4 step [3]) and rebuild once
/// [builtAt] is older than that — see [isReusable].
class SendLeg {
  final Uint8List deviceId;
  final proto.NetworkPacketV3 packet;
  final DateTime builtAt;

  SendLeg(this.deviceId, this.packet) : builtAt = DateTime.now();

  /// Safety margin against the receiver's ±60 s timestamp window: a leg is
  /// only reused for the first 30 s so that in-flight time plus clock skew
  /// cannot push an otherwise valid retransmission out of the window.
  static const Duration reuseWindow = Duration(seconds: 30);

  bool get isReusable => DateTime.now().difference(builtAt) < reuseWindow;
}

/// UI tag enum, decoupled from the wire layer; persisted by ordinal
/// [wireValue]. V3 wire frames use `MessageTypeV3` exclusively — this enum
/// is purely UI/persistence-internal.
enum UiMessageType {
  // Content payloads
  text(0),
  image(1),
  video(2),
  gif(3),
  voiceMessage(4),
  file(5),
  // Group lifecycle
  groupInvite(6),
  groupLeave(7),
  // Channels
  channelPost(8),
  channelInvite(9),
  channelLeave(10),
  channelRoleUpdate(11),
  // Identity
  identityDeleted(12),
  // Calendar
  calendarInvite(13),
  calendarRsvp(14),
  calendarUpdate(15),
  calendarDelete(16),
  // Polls
  pollCreate(17),
  ;

  final int wireValue;
  const UiMessageType(this.wireValue);

  /// Decode from persisted int. Falls back to [UiMessageType.text] for unknown
  /// values (forward-compatible: a future wire-only type accidentally landing
  /// in a UiMessage blob shouldn't crash UI).
  static UiMessageType fromInt(int v) {
    for (final t in UiMessageType.values) {
      if (t.wireValue == v) return t;
    }
    return UiMessageType.text;
  }
}

/// Message delivery status — **the four states of §9.1, and no fifth.**
///
/// ── THE SET IS THE STATEMENT ────────────────────────────────────────
///
/// v4_2 §9.1 lists exactly four states and says about them: "That is the
/// complete set, and an implementation must not extend it. Every
/// additional state is a transition that can be wrong, and a state with
/// no consumer is a defect waiting to happen."
///
///   `resting`    created, not yet gone out        — waiting mark
///   `inTransit`  gone out, no receipt             — ONE tick
///   `delivered`  the recipient has acknowledged (§9.2) — TWO ticks
///   `failed`     given up; no rung has carried    — warning mark
///
/// §12.2 maps them one to one onto the four marks, and only
/// `failed` carries a user action ("retry").
///
/// **`inTransit` also covers "resting in the post box"** (§9.1). The
/// sender does not learn which rung of the ladder carried, and
/// does not need to learn it — therefore there is no further step between "gone out"
/// and "acknowledged".
///
/// **A recipient who is offline is NOT an error** (§9.1). The
/// message stays `inTransit` as long as it rests in the post box;
/// `failed` is reserved for the case that no rung has carried it.
///
/// ── WHAT FELL ON 16.09.2026, AND WHY (S390, finding B-4) ────────────
///
/// Until here SIX values stood here, and the reasoning in the header
/// cited the V4.1 line. Since 15.09.2026 `CLAUDE.md` names
/// `Cleona_Chat_Architecture_v4_2.md` as the spec, and §9.1 lists four.
///
///   `placed`    was the placement proof of the V4.1 layer (">= 2
///               placement acknowledgments from independent relays").
///               §9.1 does not know it: it tells the sender which
///               rung has carried. It falls into `inTransit`.
///               **The one tick hung on it** — and because mycelium never
///               produced it, `in transit` could not be displayed in the UI
///               at all (finding B-4).
///   `expired`   was a fifth, TERMINAL state that a clock set after
///               14 days. §9.3 forbids it literally: "There is
///               no timer that expires messages and no background retry
///               loop." It falls WITHOUT REPLACEMENT (owner decision
///               16.09.2026). The action "retry" now hangs where
///               §12.2 lists it: on `failed`.
///   `read`      is not a DELIVERY state. A read mark is a
///               mark — it does not disappear, it changes its
///               carrier: [UiMessage.readByRecipient] (outgoing, from
///               the recipient's read receipt) and
///               [UiMessage.readReceiptSent] (incoming, the flag that
///               the own read receipt has already gone out).
///
/// The words are those of §9.1 and no longer those of the seam: the
/// delivery layer `mycelium/lib/message.dart` keeps the same four under
/// `resting`/`inTransit`/`delivered`/`failed`, and
/// `cleona_service_mycelium.dart::_myceliumStatusFor` maps them one to one.
/// Two vocabularies for four states are enough; a third
/// (`SendOutcome`) no longer exists.
enum MessageStatus {
  /// §9.1: created, not yet gone out. Waiting mark (§12.2).
  ///
  /// The only INITIAL state — a message comes here when it is
  /// created, and never back again (see [MessageStatusGuard]).
  resting('resting'),

  /// §9.1: gone out, no receipt yet. ONE tick (§12.2).
  ///
  /// **Post box INCLUDED.** A message that rests with three neighbours
  /// and waits for a recipient who is away for a week stays on this value
  /// for a week — that is §9.1 and not an error.
  inTransit('inTransit'),

  /// §9.1/§9.2: the recipient has acknowledged — sealed and signed in the
  /// seal. TWO ticks (§12.2).
  delivered('delivered'),

  /// §9.1: given up, no rung has carried. Warning mark (§12.2),
  /// and the ONLY state with a user action ("retry").
  ///
  /// **Never for a recipient who is merely offline.**
  failed('failed');

  const MessageStatus(this.wireName);

  /// Stable identifier on the IPC boundary AND inside `conversations.json(.enc)`.
  ///
  /// Deliberately a string and not the enum index: both payloads are JSON, and
  /// the member set has changed twice (nine V3 values -> six V4.1 values ->
  /// four V4.2 values). Without a stable name the meaning of every
  /// transmitted and every persisted status value would have shifted silently
  /// at exactly those moments. Mirrors [RotationApprovalKind.wireName].
  final String wireName;

  /// Decode from a wire or persistence value.
  ///
  /// Accepts a [wireName] string. **Only that.**
  ///
  /// ── THE FALLBACK DEPENDS ON THE SIDE, AND MUST (§9.1) ───────────────
  ///
  /// A status name that THIS version does not know — a state that still
  /// carries `placing`/`placed`/`read`/`expired`, a corrupted store,
  /// a hand-edited record — may neither throw nor
  /// silently claim a delivery. A profile that no longer loads after
  /// an update is a total loss; therefore nothing throws
  /// here.
  ///
  /// **Outgoing -> [failed].** That is the only one of the four values that
  /// can be right for a record read from disk:
  ///
  ///   * [resting] and [inTransit] are LIVE states. They are
  ///     updated by `_myceliumStatusFor` or `_v41StatusFor` from an outgoing entry,
  ///     and that outgoing entry lives in working memory
  ///     (`_myceliumOutbounds`, capped). Behind a loaded record
  ///     there is none — the message would rest on a promise that
  ///     nobody can redeem anymore.
  ///   * [delivered] would be a claim about the recipient that no
  ///     proof covers (§9.2: only the sealed receipt leads there).
  ///   * [failed] claims nothing about the network, is the honest
  ///     statement ("nobody carries this anymore") and carries, per §12.2, the
  ///     gesture the user needs here: "retry".
  ///
  /// **Incoming -> [delivered].** For a record on the own
  /// disk this is an observation, not a claim: it is there.
  ///
  /// An `int` takes the same path. The frozen V3.2 index table
  /// fell with S368 and does not return — there are no old profiles on
  /// this line (`FirstStartWipe`, owner 05.09.2026).
  static MessageStatus fromWire(Object? value, {required bool isOutgoing}) {
    final fallback =
        isOutgoing ? MessageStatus.failed : MessageStatus.delivered;
    if (value is String) {
      return _byWireName(value) ?? fallback;
    }
    return fallback;
  }

  static MessageStatus? _byWireName(String name) {
    for (final s in MessageStatus.values) {
      if (s.wireName == name) return s;
    }
    return null;
  }
}

extension MessageStatusGuard on MessageStatus {
  /// The transition gate of the four states (§9.1, §9.2, §9.3).
  ///
  /// Four rules carry it, and each one is in the spec:
  ///
  /// 1. **A state never goes to itself.** That is no transition,
  ///    and the caller depends on whether `onStateChanged` fires.
  /// 2. **[MessageStatus.resting] is a pure START.** "created, not
  ///    yet sent" (§9.1) — what has gone out cannot become
  ///    unsent again. Nothing leads back.
  /// 3. **[MessageStatus.delivered] is TERMINAL.** The receipt of §9.2
  ///    is sealed and signed in the seal; it is a proof, and a
  ///    proof is not overtaken. A duplicate receipt is ignored per §9.2
  ///    anyway.
  /// 4. **[MessageStatus.failed] is NOT terminal.** §9.2 lists "an
  ///    acknowledgement for an unknown identifier is the expected
  ///    consequence of a retry crossing a late answer": a receipt
  ///    can arrive after giving up, and it is the same proof as
  ///    before. Pinning a message that the recipient demonstrably has to
  ///    a warning mark would be the untruth. And the
  ///    caller may put it out again at an edge
  ///    (`failed -> inTransit`).
  ///
  /// **`expired` no longer exists, and with it no terminal
  /// state that a clock produces** (§9.3: "There is no timer that
  /// expires messages and no background retry loop.").
  bool canTransitionTo(MessageStatus next) {
    if (this == next) return false;
    // (3) Proof beats everything, and nothing beats the proof.
    if (this == MessageStatus.delivered) return false;
    // (2) No path leads back to the start.
    if (next == MessageStatus.resting) return false;
    // resting, inTransit and failed may do everything that (2) and (3) allow.
    return true;
  }
}

/// Media download state for two-stage media delivery.
enum MediaDownloadState {
  none('none', 0),
  announced('announced', 1),
  downloading('downloading', 2),
  completed('completed', 3),
  failed('failed', 4);

  const MediaDownloadState(this.wireName, this.mergeRank);

  /// Stable identifier on the IPC boundary AND inside `conversations.json(.enc)`.
  ///
  /// Same reasoning as [MessageStatus.wireName] (MIGRATION §5.1, package
  /// AP-4a): both payloads are JSON, and V4 replaces two-stage media delivery
  /// with the four stages of V4 §5.5 — the members of this enum, and hence
  /// their index order, change for certain. AP-4b (MIGRATION §5.1d) pulls this
  /// sibling of the AP-4a trap forward, because it rides in the very same
  /// `UiMessage.toJson`.
  final String wireName;

  /// Merge order for the deduplication path in
  /// `cleona_service.dart::_addMessageToConversation` ("prefer the newer/stronger
  /// state" when Store-and-Forward replays an envelope).
  ///
  /// Frozen as an explicit literal because it used to be `index`: the merge
  /// rule silently depended on the declaration order, and that order is about
  /// to change. The values reproduce the V3.2 order exactly — including
  /// `failed` outranking `completed`, which is the behaviour as measured, not
  /// a judgement about it (MIGRATION §5.1d).
  final int mergeRank;

  /// Decode from a wire or persistence value.
  ///
  /// Accepts a [wireName] string. Absent, unknown or wrongly typed values map
  /// to [none] — the value an absent field already produced, and never a
  /// throw: `MediaDownloadState.values[...]` used to raise a RangeError,
  /// which aborted the whole conversation load.
  ///
  /// ── S368: THE INDEX PATH IS GONE ────────────────────────────────────
  ///
  /// As in [MessageStatus.fromWire] an `int` branch with a
  /// frozen V3.2 order for "profiles written before AP-4b" stood here.
  /// Such profiles do not exist on this line (owner, 05.09.2026:
  /// "There are no old profiles!!"), and `FirstStartWipe` lets none
  /// through to here. An `int` is thus an unreadable value like any
  /// other and lands on [none].
  static MediaDownloadState fromWire(Object? value) {
    if (value is String) {
      return _byWireName(value) ?? MediaDownloadState.none;
    }
    return MediaDownloadState.none;
  }

  static MediaDownloadState? _byWireName(String name) {
    for (final s in MediaDownloadState.values) {
      if (s.wireName == name) return s;
    }
    return null;
  }
}

/// Call state visible to UI.
enum CallState { idle, ringing, inCall, ended }

/// Call direction.
enum CallDirection { outgoing, incoming }

/// Group call state visible to UI.
enum GroupCallState { idle, inviting, ringing, inCall, ended }

/// Participant state in a group call.
enum ParticipantState { invited, ringing, joined, left, crashed }

/// Call information for IPC/UI.
class CallInfo {
  final String callId;
  final String peerNodeIdHex;
  final CallDirection direction;
  final bool isVideo;
  CallState state;
  final DateTime startedAt;
  int framesSent;
  int framesReceived;
  int videoFramesSent;
  int videoFramesReceived;

  CallInfo({
    required this.callId,
    required this.peerNodeIdHex,
    required this.direction,
    this.isVideo = false,
    this.state = CallState.idle,
    DateTime? startedAt,
    this.framesSent = 0,
    this.framesReceived = 0,
    this.videoFramesSent = 0,
    this.videoFramesReceived = 0,
  }) : startedAt = startedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'peerNodeIdHex': peerNodeIdHex,
        'direction': direction.index,
        'isVideo': isVideo,
        'state': state.index,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'framesSent': framesSent,
        'framesReceived': framesReceived,
        'videoFramesSent': videoFramesSent,
        'videoFramesReceived': videoFramesReceived,
      };

  static CallInfo fromJson(Map<String, dynamic> json) => CallInfo(
        callId: json['callId'] as String,
        peerNodeIdHex: json['peerNodeIdHex'] as String,
        direction: CallDirection.values[json['direction'] as int],
        isVideo: json['isVideo'] as bool? ?? false,
        state: CallState.values[json['state'] as int? ?? 0],
        startedAt: DateTime.fromMillisecondsSinceEpoch(
            json['startedAt'] as int? ?? 0),
        framesSent: json['framesSent'] as int? ?? 0,
        framesReceived: json['framesReceived'] as int? ?? 0,
        videoFramesSent: json['videoFramesSent'] as int? ?? 0,
        videoFramesReceived: json['videoFramesReceived'] as int? ?? 0,
      );
}

/// Group call participant info for IPC/UI.
class GroupCallParticipantInfo {
  final String nodeIdHex;
  final String displayName;
  final ParticipantState state;
  final bool isMuted;
  final double audioLevel;

  GroupCallParticipantInfo({
    required this.nodeIdHex,
    required this.displayName,
    required this.state,
    this.isMuted = false,
    this.audioLevel = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'nodeIdHex': nodeIdHex,
        'displayName': displayName,
        'state': state.index,
        'isMuted': isMuted,
        'audioLevel': audioLevel,
      };

  static GroupCallParticipantInfo fromJson(Map<String, dynamic> json) =>
      GroupCallParticipantInfo(
        nodeIdHex: json['nodeIdHex'] as String,
        displayName: json['displayName'] as String? ?? '',
        state: ParticipantState.values[json['state'] as int? ?? 0],
        isMuted: json['isMuted'] as bool? ?? false,
        audioLevel: (json['audioLevel'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Group call information for IPC/UI.
class GroupCallInfo {
  final String callId;
  final String groupIdHex;
  final String groupName;
  final String initiatorHex;
  final GroupCallState state;
  final DateTime startedAt;
  final List<GroupCallParticipantInfo> participants;
  final int totalFramesSent;
  final int totalFramesReceived;
  final int videoFramesSent;
  final int videoFramesReceived;

  GroupCallInfo({
    required this.callId,
    required this.groupIdHex,
    required this.groupName,
    required this.initiatorHex,
    required this.state,
    DateTime? startedAt,
    this.participants = const [],
    this.totalFramesSent = 0,
    this.totalFramesReceived = 0,
    this.videoFramesSent = 0,
    this.videoFramesReceived = 0,
  }) : startedAt = startedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'groupIdHex': groupIdHex,
        'groupName': groupName,
        'initiatorHex': initiatorHex,
        'state': state.index,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'participants': participants.map((p) => p.toJson()).toList(),
        'totalFramesSent': totalFramesSent,
        'totalFramesReceived': totalFramesReceived,
        'videoFramesSent': videoFramesSent,
        'videoFramesReceived': videoFramesReceived,
      };

  static GroupCallInfo fromJson(Map<String, dynamic> json) => GroupCallInfo(
        callId: json['callId'] as String,
        groupIdHex: json['groupIdHex'] as String,
        groupName: json['groupName'] as String? ?? '',
        initiatorHex: json['initiatorHex'] as String? ?? '',
        state: GroupCallState.values[json['state'] as int? ?? 0],
        startedAt: DateTime.fromMillisecondsSinceEpoch(
            json['startedAt'] as int? ?? 0),
        participants: (json['participants'] as List<dynamic>?)
                ?.map((p) => GroupCallParticipantInfo.fromJson(
                    p as Map<String, dynamic>))
                .toList() ??
            [],
        totalFramesSent: json['totalFramesSent'] as int? ?? 0,
        totalFramesReceived: json['totalFramesReceived'] as int? ?? 0,
        videoFramesSent: json['videoFramesSent'] as int? ?? 0,
        videoFramesReceived: json['videoFramesReceived'] as int? ?? 0,
      );
}

/// UI-facing message representation.
class UiMessage {
  String id;
  final String conversationId;
  String senderNodeIdHex;
  String text;
  final DateTime timestamp;
  final UiMessageType type;
  MessageStatus status;
  final bool isOutgoing;
  String? filePath;
  DateTime? editedAt;
  bool isDeleted;
  // Media fields
  String? mimeType;
  int? fileSize;
  String? filename;
  String? thumbnailBase64;
  MediaDownloadState mediaState;
  /// When this message was taken note of LOCALLY — the
  /// anchor of the per-chat expiry deadline (§21.5.3), not the read mark.
  ///
  /// Set when inserting into the conversation, for incoming
  /// AND outgoing (`cleona_service.dart::addMessage`). It therefore says
  /// NOTHING about whether the other side has read — for that there is
  /// [readByRecipient].
  DateTime? readAt;

  /// OUTGOING: the recipient's read receipt has arrived
  /// (`_handleReadReceiptV3`). Colours the two ticks, does not change the
  /// delivery state.
  ///
  /// **Why a field and not a state (S390, finding B-4).** §9.1 lists
  /// four DELIVERY states; a read mark is a different fact
  /// (§21.5.4, switchable per chat) and does not belong in the same
  /// enumeration. As a fifth enum value it was moreover TERMINAL and
  /// overwrote `delivered` — the proof of §9.2 was lost in the
  /// process.
  bool readByRecipient;

  /// INCOMING: the own read receipt for this message has already
  /// gone out (`markConversationRead`).
  ///
  /// Pure flag against double sending — it spares exactly what §1.2
  /// forbids: the same packet a second time without cause. Until S390
  /// it stood as `MessageStatus.read` in the state scale of an
  /// INCOMING message whose state is never displayed
  /// (`chat_screen.dart`: marks only for `isOutgoing`).
  bool readReceiptSent;
  // ── Archive state (§21.6) ───────────────────────────────────────────
  //
  // S392/B3. Four fields, and they are a PROJECTION, not a state: the
  // leading stock is the archive index in `ArchiveManager`
  // (`archive_manager.dart`, area `archive_entries` of the store). They are
  // filled immediately before the message reaches the UI process
  // (`ArchiveManager.applyArchiveView`), and `messageExtraForStore`
  // strips them out again — a second, ageing copy of the same
  // fact in the message store would be exactly the contradiction that a
  // user experienced as "placeholder for a file that is still there".
  //
  // Why they have to cross the boundary at all: on Linux, Windows and
  // macOS service and UI run in two processes (§22.6). The
  // drawing path in the conversation cannot ask `ArchiveManager`; without
  // these four fields it sees only a message whose file is missing, and
  // shows "not yet downloaded" — a false statement.

  /// The tier as wire value: `original` · `thumbnail` · `mini` ·
  /// `metadataOnly` (the names of `ArchiveTier`, to be read back with
  /// `archiveTierFromWire` in `archive_config.dart`).
  ///
  /// `null` means "there is no archive entry for this message" and
  /// is NOT the same as `original`: `original` means offloaded and
  /// still on the device (pinned, or the first deadline has not yet
  /// expired).
  ///
  /// A `String` and not an enum, so that `service_types.dart` need not point to
  /// `archive_config.dart` — that already points here
  /// (`show Conversation`), and an import cycle would be the price for nothing.
  String? archiveTier;

  /// Where the original lies on the share (`smb:///Chat/2026-09/<hash>.jpg`).
  /// Carries the retrieval path for B4 and the hint text "is in the archive".
  String? archiveShareUrl;

  /// When it was offloaded. §21.6 explicitly names the date as part
  /// of what tier 4 still shows ("a metadata reference (date, size,
  /// type icon)").
  DateTime? archivedAt;

  /// The mini image of tier 3 (~2–5 KB, 64 px) as base64.
  ///
  /// **May stay empty and today always does.** The downscaler is built by
  /// S392/B1 (`lib/core/archive/archive_thumbnail.dart`); until it exists,
  /// `applyArchiveView` does not fill this field. No consumer may conclude
  /// "no archive" from `null` — that is what [archiveTier] is for.
  String? archiveMiniBase64;

  /// Display name of original sender if this message was forwarded.
  String? forwardedFrom;
  // Voice transcription (source-side or local fallback)
  String? transcriptText;
  String? transcriptLanguage;
  double? transcriptConfidence;
  // Reply/Quote
  String? replyToMessageId;
  String? replyToText;
  String? replyToSender;
  // Link Preview (Sender-Side)
  String? linkPreviewUrl;
  String? linkPreviewTitle;
  String? linkPreviewDescription;
  String? linkPreviewSiteName;
  String? linkPreviewThumbnailBase64; // JPEG base64, max 64KB
  // Poll (§24): pollId set on chat cards rendered from POLL_CREATE.
  String? pollId;
  // Calendar (§18.1/§18.2, S367 3.6): eventId set on chat cards rendered
  // from CALENDAR_INVITE/CALENDAR_UPDATE, mirroring pollId above.
  String? calendarEventId;
  // GM-2 (§9.1.4): true when sender's membership hash differs at same/lower epoch
  bool membershipMismatch;

  /// Emoji reactions: emoji → set of senderNodeIdHex.
  /// Example: {"👍": {"aabb...", "ccdd..."}, "❤️": {"aabb..."}}
  Map<String, Set<String>> reactions = {};

  /// §5.8/§14.7.4 fan-out delivery tracking: recipientUserIdHex → the wire
  /// messageId that carried this message to that recipient.
  ///
  /// A 1:1 message reuses `id` as its wire messageId, so the receipt matches
  /// on `id` alone and this map stays empty. A group message has one leg per
  /// member, and each leg needs its OWN wire id: `AckTracker._pending` is
  /// keyed by messageId alone, so reusing one id across N members would make
  /// each `trackSend` evict the previous member's pending entry (timer +
  /// completer) and break RUDP-Light route-failure detection for everyone
  /// but the last member. Empty for non-fan-out messages.
  Map<String, String> fanoutLegs = {};

  /// Recipients whose DELIVERY_RECEIPT arrived (subset of `fanoutLegs` keys).
  Set<String> deliveredBy = {};

  /// Recipients whose receipt carried `withholdDeliveryStatus` (§14.7.4).
  /// Their leg must never contribute to a visible `delivered`, otherwise the
  /// aggregate symbol would reveal exactly what they chose to withhold.
  Set<String> withheldBy = {};

  /// §14.7.4: aggregate over all fan-out legs — `true` only when every leg is
  /// confirmed AND every recipient discloses. Callers must not upgrade the
  /// status to `delivered` unless this holds.
  bool get isFullyDelivered =>
      fanoutLegs.isNotEmpty &&
      withheldBy.isEmpty &&
      deliveredBy.length >= fanoutLegs.length;

  UiMessage({
    required this.id,
    required this.conversationId,
    required this.senderNodeIdHex,
    required this.text,
    required this.timestamp,
    required this.type,
    this.status = MessageStatus.resting,
    required this.isOutgoing,
    this.filePath,
    this.editedAt,
    this.isDeleted = false,
    this.mimeType,
    this.fileSize,
    this.filename,
    this.thumbnailBase64,
    this.mediaState = MediaDownloadState.none,
    this.readAt,
    this.readByRecipient = false,
    this.readReceiptSent = false,
    this.archiveTier,
    this.archiveShareUrl,
    this.archivedAt,
    this.archiveMiniBase64,
    this.forwardedFrom,
    this.transcriptText,
    this.transcriptLanguage,
    this.transcriptConfidence,
    this.replyToMessageId,
    this.replyToText,
    this.replyToSender,
    this.linkPreviewUrl,
    this.linkPreviewTitle,
    this.linkPreviewDescription,
    this.linkPreviewSiteName,
    this.linkPreviewThumbnailBase64,
    this.pollId,
    this.calendarEventId,
    this.membershipMismatch = false,
    Map<String, Set<String>>? reactions,
    Map<String, String>? fanoutLegs,
    Set<String>? deliveredBy,
    Set<String>? withheldBy,
  })  : reactions = reactions ?? {},
        fanoutLegs = fanoutLegs ?? {},
        deliveredBy = deliveredBy ?? {},
        withheldBy = withheldBy ?? {};

  bool get hasLinkPreview =>
      linkPreviewUrl != null && linkPreviewUrl!.isNotEmpty;

  bool get isMedia => mimeType != null && mimeType!.isNotEmpty;
  bool get isImage => mimeType?.startsWith('image/') ?? false;
  bool get isVideo => mimeType?.startsWith('video/') ?? false;
  bool get isAudio => mimeType?.startsWith('audio/') ?? false;
  bool get isVoiceMessage => mimeType == 'audio/opus' || mimeType == 'audio/ogg' || (filename?.startsWith('voice_') ?? false);

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'sender': senderNodeIdHex,
        'text': text,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'type': type.wireValue,
        'status': status.wireName,
        'isOutgoing': isOutgoing,
        'filePath': filePath,
        if (editedAt != null) 'editedAt': editedAt!.millisecondsSinceEpoch,
        if (readAt != null) 'readAt': readAt!.millisecondsSinceEpoch,
        if (readByRecipient) 'readByRecipient': true,
        if (readReceiptSent) 'readReceiptSent': true,
        if (isDeleted) 'isDeleted': true,
        if (mimeType != null) 'mimeType': mimeType,
        if (fileSize != null) 'fileSize': fileSize,
        if (filename != null) 'filename': filename,
        if (thumbnailBase64 != null) 'thumbnailBase64': thumbnailBase64,
        if (mediaState != MediaDownloadState.none) 'mediaState': mediaState.wireName,
        // §21.6/S392-B3 — projection, see field comment. It travels over
        // IPC and is stripped again by `messageExtraForStore` before
        // the message goes into the store.
        if (archiveTier != null) 'archiveTier': archiveTier,
        if (archiveShareUrl != null) 'archiveShareUrl': archiveShareUrl,
        if (archivedAt != null) 'archivedAt': archivedAt!.millisecondsSinceEpoch,
        if (archiveMiniBase64 != null) 'archiveMiniBase64': archiveMiniBase64,
        if (forwardedFrom != null) 'forwardedFrom': forwardedFrom,
        if (transcriptText != null) 'transcriptText': transcriptText,
        if (transcriptLanguage != null) 'transcriptLanguage': transcriptLanguage,
        if (transcriptConfidence != null) 'transcriptConfidence': transcriptConfidence,
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        if (replyToText != null) 'replyToText': replyToText,
        if (replyToSender != null) 'replyToSender': replyToSender,
        if (linkPreviewUrl != null) 'linkPreviewUrl': linkPreviewUrl,
        if (linkPreviewTitle != null) 'linkPreviewTitle': linkPreviewTitle,
        if (linkPreviewDescription != null) 'linkPreviewDescription': linkPreviewDescription,
        if (linkPreviewSiteName != null) 'linkPreviewSiteName': linkPreviewSiteName,
        if (linkPreviewThumbnailBase64 != null) 'linkPreviewThumbnailBase64': linkPreviewThumbnailBase64,
        if (pollId != null) 'pollId': pollId,
        if (calendarEventId != null) 'calendarEventId': calendarEventId,
        if (reactions.isNotEmpty)
          'reactions': reactions.map((emoji, senders) => MapEntry(emoji, senders.toList())),
        // GM-2 (§9.1.4). Missing here AND in `fromJson` since the field
        // exists — the warning on a group message with a
        // deviating membership hash silently vanished on every restart,
        // and the message afterwards looked unsuspicious.
        // The loss is OLDER than the store (the JSON form used
        // the same method); it was noticed during the round-trip comparison for S366.
        if (membershipMismatch) 'membershipMismatch': true,
        if (fanoutLegs.isNotEmpty) 'fanoutLegs': fanoutLegs,
        if (deliveredBy.isNotEmpty) 'deliveredBy': deliveredBy.toList(),
        if (withheldBy.isNotEmpty) 'withheldBy': withheldBy.toList(),
      };

  static UiMessage fromJson(Map<String, dynamic> json) => UiMessage(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        senderNodeIdHex: json['sender'] as String? ?? '',
        text: json['text'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        type: UiMessageType.fromInt(json['type'] as int),
        // AP-4: the fallback depends on the side (§5.1b point 1). `isOutgoing`
        // is available right next to it and is therefore read here
        // instead of being pulled from the map twice.
        status: MessageStatus.fromWire(json['status'],
            isOutgoing: json['isOutgoing'] as bool),
        isOutgoing: json['isOutgoing'] as bool,
        membershipMismatch: json['membershipMismatch'] as bool? ?? false,
        filePath: json['filePath'] as String?,
        editedAt: json['editedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['editedAt'] as int)
            : null,
        readAt: json['readAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['readAt'] as int)
            : null,
        // S390: the read mark has changed its carrier (finding B-4).
        // A record that THIS store formerly wrote with `status: 'read'`
        // still carries it there — and it is read,
        // otherwise it costs network traffic: `markConversationRead` sends
        // a read receipt for every incoming message without the flag,
        // i.e. on the next opening again for the WHOLE history
        // (work rule #5, §1.2). Side-dependent, because the same value
        // denoted two different facts on the two sides.
        readByRecipient: json['readByRecipient'] as bool? ??
            ((json['isOutgoing'] as bool) && json['status'] == 'read'),
        readReceiptSent: json['readReceiptSent'] as bool? ??
            (!(json['isOutgoing'] as bool) && json['status'] == 'read'),
        isDeleted: json['isDeleted'] as bool? ?? false,
        mimeType: json['mimeType'] as String?,
        fileSize: json['fileSize'] as int?,
        filename: json['filename'] as String?,
        thumbnailBase64: json['thumbnailBase64'] as String?,
        mediaState: MediaDownloadState.fromWire(json['mediaState']),
        archiveTier: json['archiveTier'] as String?,
        archiveShareUrl: json['archiveShareUrl'] as String?,
        archivedAt: json['archivedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['archivedAt'] as int)
            : null,
        archiveMiniBase64: json['archiveMiniBase64'] as String?,
        forwardedFrom: json['forwardedFrom'] as String?,
        transcriptText: json['transcriptText'] as String?,
        transcriptLanguage: json['transcriptLanguage'] as String?,
        transcriptConfidence: (json['transcriptConfidence'] as num?)?.toDouble(),
        replyToMessageId: json['replyToMessageId'] as String?,
        replyToText: json['replyToText'] as String?,
        replyToSender: json['replyToSender'] as String?,
        linkPreviewUrl: json['linkPreviewUrl'] as String?,
        linkPreviewTitle: json['linkPreviewTitle'] as String?,
        linkPreviewDescription: json['linkPreviewDescription'] as String?,
        linkPreviewSiteName: json['linkPreviewSiteName'] as String?,
        linkPreviewThumbnailBase64: json['linkPreviewThumbnailBase64'] as String?,
        pollId: json['pollId'] as String?,
        calendarEventId: json['calendarEventId'] as String?,
        reactions: _parseReactions(json['reactions']),
        fanoutLegs: (json['fanoutLegs'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        deliveredBy: _parseHexSet(json['deliveredBy']),
        withheldBy: _parseHexSet(json['withheldBy']),
      );

  static Set<String>? _parseHexSet(dynamic raw) =>
      raw == null ? null : (raw as List<dynamic>).map((e) => e as String).toSet();

  static Map<String, Set<String>> _parseReactions(dynamic raw) {
    if (raw == null) return {};
    final map = raw as Map<String, dynamic>;
    return map.map((emoji, senders) =>
        MapEntry(emoji, (senders as List<dynamic>).map((s) => s as String).toSet()));
  }
}

/// Global media download settings (auto-download thresholds + download directory).
class MediaSettings {
  /// Max auto-download size per media type (bytes). 0 = never auto-download.
  int maxAutoDownloadImage;
  int maxAutoDownloadVideo;
  int maxAutoDownloadFile;
  int maxAutoDownloadVoice;

  /// Whether to auto-download on mobile data (default: false = WiFi only).
  bool autoDownloadOnMobile;

  /// Custom download directory (null = platform default: ~/Downloads).
  String? downloadDirectory;

  MediaSettings({
    this.maxAutoDownloadImage = 10 * 1024 * 1024,   // 10 MB
    this.maxAutoDownloadVideo = 50 * 1024 * 1024,   // 50 MB
    this.maxAutoDownloadFile = 25 * 1024 * 1024,    // 25 MB
    this.maxAutoDownloadVoice = 5 * 1024 * 1024,    // 5 MB
    this.autoDownloadOnMobile = false,
    this.downloadDirectory,
  });

  /// Check if a media file should be auto-downloaded based on type and size.
  bool shouldAutoDownload(String? mimeType, int fileSize) {
    final threshold = _thresholdForMime(mimeType);
    return threshold > 0 && fileSize <= threshold;
  }

  int _thresholdForMime(String? mimeType) {
    if (mimeType == null) return maxAutoDownloadFile;
    if (mimeType.startsWith('image/')) return maxAutoDownloadImage;
    if (mimeType.startsWith('video/')) return maxAutoDownloadVideo;
    if (mimeType.startsWith('audio/')) return maxAutoDownloadVoice;
    return maxAutoDownloadFile;
  }

  Map<String, dynamic> toJson() => {
        'maxAutoDownloadImage': maxAutoDownloadImage,
        'maxAutoDownloadVideo': maxAutoDownloadVideo,
        'maxAutoDownloadFile': maxAutoDownloadFile,
        'maxAutoDownloadVoice': maxAutoDownloadVoice,
        'autoDownloadOnMobile': autoDownloadOnMobile,
        if (downloadDirectory != null) 'downloadDirectory': downloadDirectory,
      };

  static MediaSettings fromJson(Map<String, dynamic> json) => MediaSettings(
        maxAutoDownloadImage: json['maxAutoDownloadImage'] as int? ?? 10 * 1024 * 1024,
        maxAutoDownloadVideo: json['maxAutoDownloadVideo'] as int? ?? 50 * 1024 * 1024,
        maxAutoDownloadFile: json['maxAutoDownloadFile'] as int? ?? 25 * 1024 * 1024,
        maxAutoDownloadVoice: json['maxAutoDownloadVoice'] as int? ?? 5 * 1024 * 1024,
        autoDownloadOnMobile: json['autoDownloadOnMobile'] as bool? ?? false,
        downloadDirectory: json['downloadDirectory'] as String?,
      );
}

/// Per-chat configuration (policies).
class ChatConfig {
  bool allowDownloads;
  bool allowForwarding;
  int? expiryDurationMs; // null = no expiry
  int? editWindowMs; // null = default (1h), 0 = disabled
  bool readReceipts;
  bool typingIndicators;

  ChatConfig({
    this.allowDownloads = true,
    this.allowForwarding = true,
    this.expiryDurationMs,
    this.editWindowMs,
    this.readReceipts = true,
    this.typingIndicators = true,
  });

  Map<String, dynamic> toJson() => {
        'allowDownloads': allowDownloads,
        'allowForwarding': allowForwarding,
        if (expiryDurationMs != null) 'expiryDurationMs': expiryDurationMs,
        if (editWindowMs != null) 'editWindowMs': editWindowMs,
        'readReceipts': readReceipts,
        'typingIndicators': typingIndicators,
      };

  static ChatConfig fromJson(Map<String, dynamic> json) => ChatConfig(
        allowDownloads: json['allowDownloads'] as bool? ?? true,
        allowForwarding: json['allowForwarding'] as bool? ?? true,
        expiryDurationMs: json['expiryDurationMs'] as int?,
        editWindowMs: json['editWindowMs'] as int?,
        readReceipts: json['readReceipts'] as bool? ?? true,
        typingIndicators: json['typingIndicators'] as bool? ?? true,
      );

  /// Value equality — so that "has something changed?" can be answered.
  ///
  /// WHY IT WAS MISSING AND WHAT IT COST (30.08.). For direct chats
  /// a configuration change is a PROPOSAL to the other side
  /// (`CleonaService.updateChatConfig`) that appears there as a banner with
  /// "Accept / Reject". The settings dialog called it on
  /// save UNCONDITIONALLY. Without value equality one could not even
  /// check whether something had changed — `!=` would have compared identity
  /// and always delivered `true`.
  ///
  /// Consequence in the field: the Secure/Speed switch lies in the same dialog, but is
  /// a ONE-SIDED, LOCAL choice of the sender (§12) and is not
  /// in this class at all. Whoever flipped it nevertheless sent the other side
  /// a negotiation proposal — the owner repeatedly received
  /// requests for changes he had never made. Each also cost
  /// a full Secure placement (`m x R`, in the field 18
  /// control frames).
  @override
  bool operator ==(Object other) =>
      other is ChatConfig &&
      other.allowDownloads == allowDownloads &&
      other.allowForwarding == allowForwarding &&
      other.expiryDurationMs == expiryDurationMs &&
      other.editWindowMs == editWindowMs &&
      other.readReceipts == readReceipts &&
      other.typingIndicators == typingIndicators;

  @override
  int get hashCode => Object.hash(allowDownloads, allowForwarding,
      expiryDurationMs, editWindowMs, readReceipts, typingIndicators);
}

/// Conversation state.
class Conversation {
  final String id; // nodeIdHex for DMs, groupIdHex for groups, channelIdHex for channels
  String displayName;

  /// The messages of this conversation — **complete only after `ensureLoaded`**
  /// (S366, stage B).
  ///
  /// At start the service loads only the conversation data and the YOUNGEST
  /// message (for the preview in the list). The history comes from
  /// the store as soon as somebody needs it. The reason was measured: with
  /// the full stock the start cost 3 497 ms at 150 000 messages
  /// and a **1 005 MB** memory peak, and the app does not use
  /// `largeHeap` — at around 50 000 messages the profile no longer loads.
  ///
  /// **Whoever looks in here without `ensureLoaded` possibly sees only
  /// the last message** and takes it for the whole history. Exactly
  /// against that `test/smoke/smoke_lazy_load_deckung.dart` holds.
  final List<UiMessage> messages;

  /// `true` as soon as [messages] carries the complete history.
  /// A freshly created conversation is complete by construction —
  /// it has nothing yet that could be missing.
  bool messagesLoaded = true;

  /// How many messages this conversation has in total — **including the
  /// ones not loaded**.
  ///
  /// Without this field every count would have to load the whole history and
  /// would thereby bring back exactly the memory peak against which stage B
  /// is built. The value comes from the store at start
  /// (`countMessagesOf`) and is updated on every insertion;
  /// `ensureLoaded` sets it to `messages.length` and thereby heals any
  /// deviation.
  int totalMessages = 0;
  int unreadCount;
  DateTime lastActivity;
  String? profilePictureBase64;
  final bool isGroup;
  final bool isChannel;
  ChatConfig config;
  /// Pending config proposal from DM partner (null = no pending proposal).
  ChatConfig? pendingConfigProposal;
  /// Who proposed the pending config (nodeIdHex of proposer).
  String? pendingConfigProposer;
  /// Marked as favorite.
  bool isFavorite;
  /// Per-conversation notification toggle (null = use identity default).
  bool? notificationsEnabled;
  /// Per-conversation notification sound (null = use identity default).
  String? notificationSoundName;

  Conversation({
    required this.id,
    required this.displayName,
    List<UiMessage>? messages,
    this.unreadCount = 0,
    DateTime? lastActivity,
    this.profilePictureBase64,
    this.isGroup = false,
    this.isChannel = false,
    ChatConfig? config,
    this.pendingConfigProposal,
    this.pendingConfigProposer,
    this.isFavorite = false,
    this.notificationsEnabled,
    this.notificationSoundName,
  })  : messages = messages ?? [],
        lastActivity = lastActivity ?? DateTime.now(),
        config = config ?? ChatConfig();

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'unreadCount': unreadCount,
        'lastActivity': lastActivity.millisecondsSinceEpoch,
        if (isGroup) 'isGroup': true,
        if (isChannel) 'isChannel': true,
        if (profilePictureBase64 != null) 'profilePicture': profilePictureBase64,
        'config': config.toJson(),
        if (pendingConfigProposal != null) 'pendingConfigProposal': pendingConfigProposal!.toJson(),
        if (pendingConfigProposer != null) 'pendingConfigProposer': pendingConfigProposer,
        if (isFavorite) 'isFavorite': true,
        if (notificationsEnabled != null) 'notificationsEnabled': notificationsEnabled,
        if (notificationSoundName != null) 'notificationSoundName': notificationSoundName,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  static Conversation fromJson(Map<String, dynamic> json) {
    final msgs = (json['messages'] as List<dynamic>?)
            ?.map((m) => UiMessage.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [];
    return Conversation(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      messages: msgs,
      unreadCount: json['unreadCount'] as int? ?? 0,
      lastActivity: DateTime.fromMillisecondsSinceEpoch(
          json['lastActivity'] as int? ?? 0),
      isGroup: json['isGroup'] as bool? ?? false,
      isChannel: json['isChannel'] as bool? ?? false,
      profilePictureBase64: json['profilePicture'] as String?,
      config: json['config'] != null
          ? ChatConfig.fromJson(json['config'] as Map<String, dynamic>)
          : null,
      pendingConfigProposal: json['pendingConfigProposal'] != null
          ? ChatConfig.fromJson(json['pendingConfigProposal'] as Map<String, dynamic>)
          : null,
      pendingConfigProposer: json['pendingConfigProposer'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool?,
      notificationSoundName: json['notificationSoundName'] as String?,
    );
  }
}

/// Group member info.
class GroupMemberInfo {
  final String nodeIdHex;
  String displayName;
  String role; // "owner", "admin", "member"
  Uint8List? ed25519Pk;
  Uint8List? x25519Pk;
  Uint8List? mlKemPk;

  GroupMemberInfo({
    required this.nodeIdHex,
    required this.displayName,
    this.role = 'member',
    this.ed25519Pk,
    this.x25519Pk,
    this.mlKemPk,
  });

  Map<String, dynamic> toJson() => {
        'nodeIdHex': nodeIdHex,
        'displayName': displayName,
        'role': role,
        if (ed25519Pk != null) 'ed25519Pk': bytesToHex(ed25519Pk!),
        if (x25519Pk != null) 'x25519Pk': bytesToHex(x25519Pk!),
        if (mlKemPk != null) 'mlKemPk': bytesToHex(mlKemPk!),
      };

  static GroupMemberInfo fromJson(Map<String, dynamic> json) => GroupMemberInfo(
        nodeIdHex: json['nodeIdHex'] as String,
        displayName: json['displayName'] as String? ?? '',
        role: json['role'] as String? ?? 'member',
        ed25519Pk: json['ed25519Pk'] != null ? hexToBytes(json['ed25519Pk'] as String) : null,
        x25519Pk: json['x25519Pk'] != null ? hexToBytes(json['x25519Pk'] as String) : null,
        mlKemPk: json['mlKemPk'] != null ? hexToBytes(json['mlKemPk'] as String) : null,
      );
}

/// Group info.
class GroupInfo {
  final String groupIdHex;

  /// The group name is USER CONTENT — on 06.09.2026 it stood in plain text at 20
  /// log sites (`channel_moderation_service.dart`,
  /// `cleona_service_pure.dart:676`, `group_call_manager.dart:165`).
  /// Every set registers it with [LogRedaction]; the replacement
  /// then happens at the sink point in `CLogger`, not at the
  /// log sites. Constructor AND setter, because a field that is registered only in the
  /// constructor would be in plain text again after a rename.
  String _name;
  String get name => _name;
  set name(String v) {
    _name = v;
    LogRedaction.registerName(v, kind: 'group');
  }

  String? description;
  String? pictureBase64;
  final Map<String, GroupMemberInfo> members; // nodeIdHex -> member
  String ownerNodeIdHex;
  DateTime createdAt;
  int membershipEpoch;

  /// §14.7.4: withhold this node's delivery status from the other members'
  /// UI. Purely local and unilateral — never negotiated, never distributed as
  /// configuration; it rides as a bit on each outgoing DELIVERY_RECEIPT.
  /// Default false = disclose.
  bool withholdDeliveryStatus;

  GroupInfo({
    required this.groupIdHex,
    required String name,
    this.description,
    this.pictureBase64,
    Map<String, GroupMemberInfo>? members,
    required this.ownerNodeIdHex,
    DateTime? createdAt,
    this.membershipEpoch = 0,
    this.withholdDeliveryStatus = false,
  })  : _name = name,
        members = members ?? {},
        createdAt = createdAt ?? DateTime.now() {
    LogRedaction.registerName(name, kind: 'group');
  }

  Map<String, dynamic> toJson() => {
        'groupIdHex': groupIdHex,
        'name': name,
        'description': description,
        'pictureBase64': pictureBase64,
        'ownerNodeIdHex': ownerNodeIdHex,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'members': members.map((k, v) => MapEntry(k, v.toJson())),
        'membershipEpoch': membershipEpoch,
        'withholdDeliveryStatus': withholdDeliveryStatus,
      };

  static GroupInfo fromJson(Map<String, dynamic> json) {
    final membersMap = <String, GroupMemberInfo>{};
    final m = json['members'] as Map<String, dynamic>?;
    if (m != null) {
      for (final e in m.entries) {
        membersMap[e.key] = GroupMemberInfo.fromJson(e.value as Map<String, dynamic>);
      }
    }
    return GroupInfo(
      groupIdHex: json['groupIdHex'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      pictureBase64: json['pictureBase64'] as String?,
      ownerNodeIdHex: json['ownerNodeIdHex'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int? ?? 0),
      members: membersMap,
      membershipEpoch: json['membershipEpoch'] as int? ?? 0,
      withholdDeliveryStatus: json['withholdDeliveryStatus'] as bool? ?? false,
    );
  }
}

/// Channel member info.
class ChannelMemberInfo {
  final String nodeIdHex;
  String displayName;
  String role; // "owner", "admin", "subscriber"
  Uint8List? ed25519Pk;
  Uint8List? x25519Pk;
  Uint8List? mlKemPk;

  ChannelMemberInfo({
    required this.nodeIdHex,
    required this.displayName,
    this.role = 'subscriber',
    this.ed25519Pk,
    this.x25519Pk,
    this.mlKemPk,
  });

  Map<String, dynamic> toJson() => {
        'nodeIdHex': nodeIdHex,
        'displayName': displayName,
        'role': role,
        if (ed25519Pk != null) 'ed25519Pk': bytesToHex(ed25519Pk!),
        if (x25519Pk != null) 'x25519Pk': bytesToHex(x25519Pk!),
        if (mlKemPk != null) 'mlKemPk': bytesToHex(mlKemPk!),
      };

  static ChannelMemberInfo fromJson(Map<String, dynamic> json) => ChannelMemberInfo(
        nodeIdHex: json['nodeIdHex'] as String,
        displayName: json['displayName'] as String? ?? '',
        role: json['role'] as String? ?? 'subscriber',
        ed25519Pk: json['ed25519Pk'] != null ? hexToBytes(json['ed25519Pk'] as String) : null,
        x25519Pk: json['x25519Pk'] != null ? hexToBytes(json['x25519Pk'] as String) : null,
        mlKemPk: json['mlKemPk'] != null ? hexToBytes(json['mlKemPk'] as String) : null,
      );
}

/// Channel info.
class ChannelInfo {
  final String channelIdHex;

  /// Like [GroupInfo.name]. A PUBLIC channel carries its name
  /// in the DHT index anyway — but `isPublic` is switchable, and a
  /// private channel name is user content like any other. An exception
  /// "only if public" would thus have queried a state that
  /// changes, and diagnosis loses nothing: the log lines that
  /// carry the name almost all additionally carry `channelIdHex`.
  String _name;
  String get name => _name;
  set name(String v) {
    _name = v;
    LogRedaction.registerName(v, kind: 'channel');
  }

  String? description;
  String? pictureBase64;
  final Map<String, ChannelMemberInfo> members; // nodeIdHex -> member
  String ownerNodeIdHex;
  DateTime createdAt;
  /// Public channel (discoverable via DHT search) vs private (invite-only).
  bool isPublic;
  /// Content-Rating: true = NSFW (requires isAdult to view).
  bool isAdult;
  /// Primary language (de/en/es/hu/sv/multi).
  String language;
  /// Channel category (e.g. 'general', 'tech', 'news', 'music', 'gaming').
  String category;
  /// Bad Badge level (0=none, 1=questionable, 2=repeatedlyMisleading, 3=permanent).
  int badBadgeLevel;
  /// Timestamp when bad badge was assigned (for probation tracking).
  DateTime? badBadgeSince;
  /// Whether admin submitted a correction after bad badge.
  bool correctionSubmitted;
  /// Temporarily hidden due to CSAM reports (Stage 2).
  bool isCsamHidden;
  /// When CSAM hiding started.
  DateTime? csamHiddenSince;
  /// CSAM Stage 3: extended-hidden, objection window active.
  bool csamStage3Active;
  /// CSAM Stage 3: when the objection window ends (14d after threshold).
  DateTime? csamObjectionWindowEnd;
  /// CSAM Stage 3: jury ID of the plausibility jury (if active).
  String? csamObjectionJuryId;
  /// Permanently tombstoned (jury verdict: deleteChannel).
  bool tombstoned;

  /// GM-4 (§9.1.4): monotonic membership epoch for consistency detection.
  int membershipEpoch;

  ChannelInfo({
    required this.channelIdHex,
    required String name,
    this.description,
    this.pictureBase64,
    Map<String, ChannelMemberInfo>? members,
    required this.ownerNodeIdHex,
    DateTime? createdAt,
    this.isPublic = false,
    // false, matching fromJson and the compact wire format: toJson writes
    // 'isAdult' ONLY when true, so absence means "not adult" by definition.
    // The default of true was not merely a trap — it fired: the Restore
    // Broadcast channel restore (cleona_service.dart:11221) omits the argument,
    // because RestoreChannelInfo carries no is_adult field at all
    // (proto/app_payloads.proto::RestoreChannelInfo). Every channel recovered through the canonical
    // recovery path was therefore flagged 18+, persisted that way by
    // _saveChannels(), shown with the red 18+ badge (chat_screen.dart:1777),
    // filtered out of every default channel search for all other users
    // (channel_index.dart:119) and propagated into signed CHANNEL_INVITEs
    // (cleona_service.dart:6626). Verified 2026-07-28.
    //
    // Restoring a genuinely adult channel still loses the flag — that needs the
    // proto field and is a separate, protocol-level decision.
    this.isAdult = false,
    this.language = 'de',
    this.category = 'general',
    this.badBadgeLevel = 0,
    this.badBadgeSince,
    this.correctionSubmitted = false,
    this.isCsamHidden = false,
    this.csamHiddenSince,
    this.csamStage3Active = false,
    this.csamObjectionWindowEnd,
    this.csamObjectionJuryId,
    this.tombstoned = false,
    this.membershipEpoch = 0,
  })  : _name = name,
        members = members ?? {},
        createdAt = createdAt ?? DateTime.now() {
    LogRedaction.registerName(name, kind: 'channel');
  }

  Map<String, dynamic> toJson() => {
        'channelIdHex': channelIdHex,
        'name': name,
        'description': description,
        'pictureBase64': pictureBase64,
        'ownerNodeIdHex': ownerNodeIdHex,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'members': members.map((k, v) => MapEntry(k, v.toJson())),
        if (isPublic) 'isPublic': true,
        if (isAdult) 'isAdult': true,
        'language': language,
        if (category != 'general') 'category': category,
        if (badBadgeLevel > 0) 'badBadgeLevel': badBadgeLevel,
        if (badBadgeSince != null) 'badBadgeSince': badBadgeSince!.millisecondsSinceEpoch,
        if (correctionSubmitted) 'correctionSubmitted': true,
        if (isCsamHidden) 'isCsamHidden': true,
        if (csamHiddenSince != null) 'csamHiddenSince': csamHiddenSince!.millisecondsSinceEpoch,
        if (csamStage3Active) 'csamStage3Active': true,
        if (csamObjectionWindowEnd != null) 'csamObjectionWindowEnd': csamObjectionWindowEnd!.millisecondsSinceEpoch,
        if (csamObjectionJuryId != null) 'csamObjectionJuryId': csamObjectionJuryId,
        if (tombstoned) 'tombstoned': true,
        if (membershipEpoch > 0) 'membershipEpoch': membershipEpoch,
      };

  static ChannelInfo fromJson(Map<String, dynamic> json) {
    final membersMap = <String, ChannelMemberInfo>{};
    final m = json['members'] as Map<String, dynamic>?;
    if (m != null) {
      for (final e in m.entries) {
        membersMap[e.key] = ChannelMemberInfo.fromJson(e.value as Map<String, dynamic>);
      }
    }
    return ChannelInfo(
      channelIdHex: json['channelIdHex'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      pictureBase64: json['pictureBase64'] as String?,
      ownerNodeIdHex: json['ownerNodeIdHex'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int? ?? 0),
      members: membersMap,
      isPublic: json['isPublic'] as bool? ?? false,
      isAdult: json['isAdult'] as bool? ?? false,
      language: json['language'] as String? ?? 'de',
      category: json['category'] as String? ?? 'general',
      badBadgeLevel: json['badBadgeLevel'] as int? ?? 0,
      badBadgeSince: json['badBadgeSince'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['badBadgeSince'] as int)
          : null,
      correctionSubmitted: json['correctionSubmitted'] as bool? ?? false,
      isCsamHidden: json['isCsamHidden'] as bool? ?? false,
      csamHiddenSince: json['csamHiddenSince'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['csamHiddenSince'] as int)
          : null,
      csamStage3Active: json['csamStage3Active'] as bool? ?? false,
      csamObjectionWindowEnd: json['csamObjectionWindowEnd'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['csamObjectionWindowEnd'] as int)
          : null,
      csamObjectionJuryId: json['csamObjectionJuryId'] as String?,
      tombstoned: json['tombstoned'] as bool? ?? false,
      membershipEpoch: json['membershipEpoch'] as int? ?? 0,
    );
  }
}

/// DHT Channel Index entry — compact public metadata for search/discovery.
class ChannelIndexEntry {
  final String channelIdHex;
  final String name;
  final String language;
  final String category;
  final bool isAdult;
  final String? description;
  final int subscriberCount;
  final int badBadgeLevel;
  final DateTime? badBadgeSince;
  final bool correctionSubmitted;
  final String ownerNodeIdHex;
  final DateTime createdAt;

  ChannelIndexEntry({
    required this.channelIdHex,
    required this.name,
    required this.language,
    this.category = 'general',
    // false, matching fromJson and the compact wire format: toJson writes 'a'
    // ONLY when isAdult is true, so absence means "not adult" by definition.
    // A constructor default of true contradicted that contract — the same
    // logical entry was classified differently depending on whether it was
    // built in code or read from JSON, and a code-built entry silently
    // disappeared from search(), which filters !isAdult unless includeAdult is
    // set (channel_index.dart:119-121). Verified 2026-07-28: all four
    // production call sites pass the flag explicitly, so this is a no-op for
    // them and closes the trap for the next one.
    this.isAdult = false,
    this.description,
    this.subscriberCount = 0,
    this.badBadgeLevel = 0,
    this.badBadgeSince,
    this.correctionSubmitted = false,
    required this.ownerNodeIdHex,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': channelIdHex,
        'n': name,
        'l': language,
        if (category != 'general') 'cat': category,
        if (isAdult) 'a': true,
        if (description != null && description!.isNotEmpty) 'd': description,
        's': subscriberCount,
        if (badBadgeLevel > 0) 'b': badBadgeLevel,
        if (badBadgeSince != null) 'bs': badBadgeSince!.millisecondsSinceEpoch,
        if (correctionSubmitted) 'cs': true,
        'o': ownerNodeIdHex,
        'c': createdAt.millisecondsSinceEpoch,
      };

  static ChannelIndexEntry fromJson(Map<String, dynamic> json) => ChannelIndexEntry(
        channelIdHex: json['id'] as String? ?? '',
        name: json['n'] as String? ?? '',
        language: json['l'] as String? ?? 'de',
        category: json['cat'] as String? ?? 'general',
        isAdult: json['a'] as bool? ?? false,
        description: json['d'] as String?,
        subscriberCount: json['s'] as int? ?? 0,
        badBadgeLevel: json['b'] as int? ?? 0,
        badBadgeSince: json['bs'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['bs'] as int)
            : null,
        correctionSubmitted: json['cs'] as bool? ?? false,
        ownerNodeIdHex: json['o'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['c'] as int? ?? 0),
      );
}

/// A content report for moderation.
class ChannelReport {
  final String reportId;
  final String channelIdHex;
  final String reporterNodeIdHex;
  final ReportCategory category;
  final List<String> evidencePostIds;
  final String? description;
  final DateTime createdAt;
  /// Current state of this report.
  ReportState state;

  ChannelReport({
    required this.reportId,
    required this.channelIdHex,
    required this.reporterNodeIdHex,
    required this.category,
    this.evidencePostIds = const [],
    this.description,
    DateTime? createdAt,
    this.state = ReportState.pending,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'reportId': reportId,
        'channelIdHex': channelIdHex,
        'reporterNodeIdHex': reporterNodeIdHex,
        'category': category.index,
        'evidencePostIds': evidencePostIds,
        if (description != null) 'description': description,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'state': state.index,
      };

  static ChannelReport fromJson(Map<String, dynamic> json) => ChannelReport(
        reportId: json['reportId'] as String,
        channelIdHex: json['channelIdHex'] as String,
        reporterNodeIdHex: json['reporterNodeIdHex'] as String,
        category: ReportCategory.values[json['category'] as int? ?? 0],
        evidencePostIds: (json['evidencePostIds'] as List<dynamic>?)
                ?.cast<String>() ??
            [],
        description: json['description'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int? ?? 0),
        state: ReportState.values[json['state'] as int? ?? 0],
      );
}

/// Report state.
enum ReportState { pending, juryActive, resolved, dismissed }

/// A single-post report.
class PostReport {
  final String reportId;
  final String channelIdHex;
  final String postId;
  final String reporterNodeIdHex;
  final ReportCategory category;
  final String? description;
  final DateTime createdAt;
  PostReportState state;

  PostReport({
    required this.reportId,
    required this.channelIdHex,
    required this.postId,
    required this.reporterNodeIdHex,
    required this.category,
    this.description,
    DateTime? createdAt,
    this.state = PostReportState.pending,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'reportId': reportId,
        'channelIdHex': channelIdHex,
        'postId': postId,
        'reporterNodeIdHex': reporterNodeIdHex,
        'category': category.index,
        if (description != null) 'description': description,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'state': state.index,
      };

  static PostReport fromJson(Map<String, dynamic> json) => PostReport(
        reportId: json['reportId'] as String,
        channelIdHex: json['channelIdHex'] as String,
        postId: json['postId'] as String,
        reporterNodeIdHex: json['reporterNodeIdHex'] as String,
        category: ReportCategory.values[json['category'] as int? ?? 0],
        description: json['description'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int? ?? 0),
        state: PostReportState.values[json['state'] as int? ?? 0],
      );
}

/// Post report state.
enum PostReportState { pending, adminNotified, escalated, resolved }

/// Jury request sent to a juror.
class JuryRequest {
  final String juryId;
  final String channelIdHex;
  final String reportId;
  final ReportCategory category;
  final List<String> evidencePostIds;
  final String? reportDescription;
  final String? channelName;
  final String? channelLanguage;
  final String? requesterNodeIdHex;
  final DateTime sentAt;
  final int epochDay;
  final int juryRound;
  JuryVoteResult? vote;
  DateTime? votedAt;

  JuryRequest({
    required this.juryId,
    required this.channelIdHex,
    required this.reportId,
    required this.category,
    this.evidencePostIds = const [],
    this.reportDescription,
    this.channelName,
    this.channelLanguage,
    this.requesterNodeIdHex,
    DateTime? sentAt,
    this.epochDay = 0,
    this.juryRound = 0,
    this.vote,
    this.votedAt,
  }) : sentAt = sentAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'juryId': juryId,
        'channelIdHex': channelIdHex,
        'reportId': reportId,
        'category': category.index,
        'evidencePostIds': evidencePostIds,
        if (reportDescription != null) 'reportDescription': reportDescription,
        if (channelName != null) 'channelName': channelName,
        if (channelLanguage != null) 'channelLanguage': channelLanguage,
        if (requesterNodeIdHex != null) 'requesterNodeIdHex': requesterNodeIdHex,
        'sentAt': sentAt.millisecondsSinceEpoch,
        'epochDay': epochDay,
        'juryRound': juryRound,
        // Wire field consumed by `JuryRequest.hasVoted` in
        // test/e2e/lib/ipc-client.ts (moderation.spec.ts,
        // moderation-lab.ts) — derived, not stored separately, so it can
        // never drift from `vote`. Always present (not `if`-guarded like
        // `vote`/`votedAt` above) because readers filter on the boolean
        // itself, not on its absence.
        'hasVoted': vote != null,
        if (vote != null) 'vote': vote!.index,
        if (votedAt != null) 'votedAt': votedAt!.millisecondsSinceEpoch,
      };

  static JuryRequest fromJson(Map<String, dynamic> json) => JuryRequest(
        juryId: json['juryId'] as String,
        channelIdHex: json['channelIdHex'] as String,
        reportId: json['reportId'] as String,
        category: ReportCategory.values[json['category'] as int? ?? 0],
        evidencePostIds: (json['evidencePostIds'] as List<dynamic>?)
                ?.cast<String>() ??
            [],
        reportDescription: json['reportDescription'] as String?,
        channelName: json['channelName'] as String?,
        channelLanguage: json['channelLanguage'] as String?,
        requesterNodeIdHex: json['requesterNodeIdHex'] as String?,
        sentAt: DateTime.fromMillisecondsSinceEpoch(json['sentAt'] as int? ?? 0),
        epochDay: json['epochDay'] as int? ?? 0,
        juryRound: json['juryRound'] as int? ?? 0,
        vote: json['vote'] != null ? JuryVoteResult.values[json['vote'] as int] : null,
        votedAt: json['votedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['votedAt'] as int)
            : null,
      );
}

/// Jury vote result (matches JuryVote in moderation_config).
enum JuryVoteResult { approve, reject, abstain }

/// Peer information for UI/daemon display.
class PeerSummary {
  final String nodeIdHex;
  final String address;
  final int port;
  final DateTime lastSeen;
  /// All known addresses as "ip:port" strings (max 2: local + public).
  final List<String> allAddresses;
  /// Long-term address stability — drives ContactSeed peer selection.
  final int stabilityTierIndex;
  /// S119 B: true = confirmed bidirectional UDP contact (green dot);
  /// false = reachable only via an alive relay route (amber dot).
  final bool isDirect;

  PeerSummary({
    required this.nodeIdHex,
    required this.address,
    required this.port,
    required this.lastSeen,
    this.allAddresses = const [],
    this.stabilityTierIndex = 2,
    this.isDirect = true,
  });

  Map<String, dynamic> toJson() => {
        'nodeIdHex': nodeIdHex,
        'address': address,
        'port': port,
        'lastSeen': lastSeen.millisecondsSinceEpoch,
        'allAddresses': allAddresses,
        if (stabilityTierIndex != 2) 'stabilityTierIndex': stabilityTierIndex,
        'isDirect': isDirect,
      };

  static PeerSummary fromJson(Map<String, dynamic> json) => PeerSummary(
        nodeIdHex: json['nodeIdHex'] as String,
        address: json['address'] as String? ?? '',
        port: json['port'] as int? ?? 0,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(
            json['lastSeen'] as int? ?? 0),
        allAddresses: (json['allAddresses'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        stabilityTierIndex: json['stabilityTierIndex'] as int? ?? 2,
        isDirect: json['isDirect'] as bool? ?? true,
      );
}

/// Contact information (public, used across IPC boundary).
/// One authorized device of a CONTACT, as carried by the §14.5 path-2
/// device-set announcement.
///
/// Deliberately a plain storage record rather than
/// `DeviceSigInfo` (`lib/core/identity/rotation_co_auth.dart`): that type is
/// the crypto layer's view and lives on `Uint8List`, while everything in
/// this file round-trips through hex JSON. `toSigInfo()` bridges the two at
/// the one place the quorum check needs it, so neither layer has to know the
/// other's encoding.
class ContactDeviceSigKey {
  final String deviceNodeIdHex;
  final String ed25519PkHex;
  final String mlDsaPkHex;
  final bool isPrimary;

  const ContactDeviceSigKey({
    required this.deviceNodeIdHex,
    required this.ed25519PkHex,
    required this.mlDsaPkHex,
    this.isPrimary = false,
  });

  Map<String, dynamic> toJson() => {
        'deviceNodeId': deviceNodeIdHex,
        'ed25519Pk': ed25519PkHex,
        'mlDsaPk': mlDsaPkHex,
        if (isPrimary) 'isPrimary': true,
      };

  static ContactDeviceSigKey fromJson(Map<String, dynamic> json) =>
      ContactDeviceSigKey(
        deviceNodeIdHex: json['deviceNodeId'] as String? ?? '',
        ed25519PkHex: json['ed25519Pk'] as String? ?? '',
        mlDsaPkHex: json['mlDsaPk'] as String? ?? '',
        isPrimary: json['isPrimary'] as bool? ?? false,
      );
}

/// The name a contact carries until its own introduction arrives (S394-11).
///
/// A MARK in the data, not a text for the screen: the data model knows no
/// language. The surface translates it (`contact_name_pending`) through
/// `shownContactName` in `lib/ui/components/contact_name.dart` (S395).
const String kPendingContactName = 'Pending...';

class ContactInfo {
  Uint8List nodeId;
  String displayName;
  String? localAlias; // Local override for display name
  Uint8List? ed25519Pk;
  Uint8List? mlDsaPk;
  Uint8List? x25519Pk;
  Uint8List? mlKemPk;
  String status; // pending, accepted, rejected, pending_outgoing, storedForDelivery
  String? message;
  String? profilePictureBase64;
  String? pendingNameChange; // Remote name change waiting for user decision
  /// When this contact was accepted (for long-term contact checks).
  DateTime? acceptedAt;
  /// Verification level (Architecture Section 5.5): unverified, seen, verified, trusted.
  String verificationLevel;
  /// §26 Multi-Device: known device-node-IDs for this contact (learned from senderDeviceNodeId).
  Set<String> deviceNodeIds;

  /// §14.5 path 2 — the contact's DEVICE SET as last announced pairwise.
  ///
  /// This is the store §7.5 always needed and never had. Until S360 the
  /// receiver fed `verifyRotationCoAuth` a compile-time
  /// `const cachedDeviceSigKeys = <DeviceSigInfo>[]`, so every incoming
  /// emergency rotation came out as `RotationCoAuthResult.legacy` and was
  /// applied unchecked. §14.5 does prescribe that branch — but as the
  /// exception for a brand-new or long-absent contact ("A brand-new contact
  /// does not know `N`, a long-absent one has a stale state"), not as the
  /// rule for everyone forever.
  ///
  /// Held per contact and NEVER derivable from anything public: §14.5
  /// rejected the public durable object because it "would make the device
  /// set of every identity enumerable network-wide".
  ///
  /// Serialised as hex triples so the record survives a restart — a device
  /// set that lived only in RAM would be empty again after every daemon
  /// start, i.e. the same universal `legacy` as before, just later.
  List<ContactDeviceSigKey> deviceSigKeys;

  /// Highest `seq` accepted from this contact's device-set announcements.
  ///
  /// Replay defence, and it is load-bearing rather than hygiene: a captured
  /// OLDER announcement carries a LARGER device set, and replaying it would
  /// reinstate a locked-out device as a valid countersigner — which is
  /// exactly the quorum §14.4 is meant to protect. `-1` = never received
  /// one (distinct from seq 0, which is a real first announcement).
  int deviceSetSeq;
  /// Birthday month (1-12), day (1-31), optional year. Feeds the calendar
  /// birthday auto-sync (§23.4). Purely local — never broadcast to other contacts.
  int? birthdayMonth;
  int? birthdayDay;
  int? birthdayYear;

  /// §4.5.4 — when the KEM copy stored here DEMONSTRABLY applied.
  ///
  /// ── WHY THE FIELD WAS MISSING AND WHAT IT COST (S363) ──────────────
  ///
  /// [x25519Pk] and [mlKemPk] had no age. The sealing
  /// (`CleonaService.sendToUser`, step 2) therefore only checks them for
  /// `null` — a sender seals against a generation of which it does
  /// not know whether the other side still holds it at all. §4.5.4
  /// keeps EXACTLY ONE previous generation ("Exactly **one** previous
  /// generation is retained"); two rotation steps old is provably
  /// too old, and the failure is silent on both sides.
  ///
  /// It is filled from the `rotationTimestamp` of the ANNOUNCEMENT
  /// (`proto.KeyRotation.rotationTimestamp`) — i.e. from the time of the
  /// other side, not from the own one. Until S363 this value only went
  /// into the signature buffer and was discarded afterwards.
  ///
  /// ── AND IT IS AT THE SAME TIME THE ORDER ───────────────────────────
  ///
  /// Since S361 this node harvests up to 30 epochs back
  /// (`harvestEpochsPlan`, `depth = kManagementKeepEpochs`). Thus
  /// an OLD announcement can arrive after a newer one. Without a
  /// comparison it would overwrite the fresher keys — a
  /// reset to a generation that the other side no longer
  /// keeps, and at the same time a replay path. `_handleKeyRotation`
  /// therefore compares against this field and discards what is not newer.
  ///
  /// `null` = never applied an announcement. Then [acceptedAt] counts as the
  /// lower bound — the keys were at least that fresh when the contact
  /// was accepted.
  DateTime? kemRotationAt;

  /// The point in time against which the freshness of the KEM copy is measured.
  ///
  /// [kemRotationAt], else [acceptedAt], else `null` (= no measurement
  /// possible, `KemCopyFreshness.unknown`).
  DateTime? get kemSeenAt => kemRotationAt ?? acceptedAt;

  /// A5/A6: Last verified liveness proof from this contact (DELIVERY_RECEIPT
  /// or ApplicationFrame). Device-local — excluded from twin-sync.
  DateTime? lastAckedAt;
  /// A6: Guard for AUTO-REPAIR — only cleared by liveness proof
  /// (DELIVERY_RECEIPT / ApplicationFrame), never by acceptContactRequest.
  /// Device-local — excluded from twin-sync.
  bool autoRepairAttempted;

  /// First-CR-Bootstrap seed (§8.1.1, persisted from QR/NFC scan).
  /// Required for retrying a `pending_outgoing` first-contact CR — the
  /// recipient's User-KEM-PK is unknown until CR-Response arrives, so the
  /// retry must re-encap under the recipient's Device-KEM-PK from the seed.
  /// Cleared once the contact transitions to `accepted` is unnecessary —
  /// these are tiny static fields and survive across re-installs.
  String? seedDeviceIdHex;
  String? seedDxkB64;
  String? seedDmkB64;
  /// rev3: userEd25519Pk trust-anchor from v2 ContactSeed (base64url, no padding).
  String? seedEpB64;

  /// §15.2 — the FOUNDING pubkey of the OTHER SIDE. Set ONCE, NEVER
  /// changed again.
  ///
  /// ── WHY THIS FIELD IS NEEDED ALTHOUGH [ed25519Pk] IS THERE ──────────
  ///
  /// [ed25519Pk] carries the CURRENT signing key of the
  /// other side at any time: every accepted `KEY_ROTATION_BROADCAST` overwrites
  /// it (`CleonaService._setContactTrustAnchor`). For a contact that
  /// has rotated once, the value there is therefore NO LONGER the
  /// founding key — it is the latest one. Whoever forms `K_AB` or the
  /// outbound direction from it computes, after the other side's rotation,
  /// under a different tag than the other side, and the delivery
  /// fails silently (§15.2: "K_AB has exactly one source: the founding
  /// keys of both sides").
  ///
  /// The founding value itself is lost without replacement — there is
  /// no second source from which it could be retrieved. Therefore
  /// it is recorded here BEFORE the first overwriter runs.
  ///
  /// ── ONCE, AND THAT IS ENFORCED HERE, NOT AT THE CALLER ──────────────
  ///
  /// The field is private and has NO setter; the only way in is
  /// [rememberFoundingAnchor], which does not touch an anchor already
  /// set. A caller who forgets the rule thus cannot break it at all
  /// — were it a public field, the seven
  /// callers of `_setContactTrustAnchor` would each have their own chance to.
  Uint8List? _peerFoundingEd25519Pk;

  /// The founding pubkey of the other side, or `null` as long as none
  /// has been recorded. See [rememberFoundingAnchor].
  Uint8List? get peerFoundingEd25519Pk => _peerFoundingEd25519Pk;

  /// Records the founding pubkey of the other side ONCE.
  ///
  /// Return: whether THIS call set it. `false` means either
  /// "already set" (the normal case on every later call) or "no
  /// usable value" — neither is an error, but the reason why
  /// the method exists.
  bool rememberFoundingAnchor(Uint8List? pk) {
    if (_peerFoundingEd25519Pk != null) return false;
    if (pk == null || pk.length != 32) return false;
    _peerFoundingEd25519Pk = Uint8List.fromList(pk);
    return true;
  }

  /// [seedEpB64] as bytes, or `null` if the field is empty or not
  /// decodable.
  ///
  /// ONE decoder for this field, not several: all three writers
  /// (`qr_contact_screen.dart`, `deep_link_receiver.dart`,
  /// `home_screen.dart`) store URL-safe base64 WITHOUT padding.
  /// Raw `base64Decode` throws on it `Invalid length, must be multiple of
  /// four` — that was until S360 the silent total failure of first contact.
  /// `base64.normalize` pads and translates `-_` to `+/`.
  Uint8List? get seedEpBytes {
    final ep = seedEpB64;
    if (ep == null || ep.isEmpty) return null;
    try {
      final b = base64Decode(base64.normalize(ep));
      return b.length == 32 ? b : null;
    } catch (_) {
      return null;
    }
  }

  /// §15.5 field `ki` — `K_inv(i)` from the read-in ContactSeed
  /// (base64url without padding, 32 B).
  ///
  /// ── WHY IT HANGS ON THE CONTACT AND NOT ONLY IN THE CALL ────────────
  ///
  /// Without it there is no invitation line and thus no carrier for
  /// the contact request (§15.3.2). If it is only in the call, it is gone after
  /// a restart — and a `pending_outgoing` contact whose
  /// request never arrived could never be retried. The same
  /// reasoning as for [seedEpB64] next to it, out of the same necessity.
  ///
  /// `null` means "the seed carried no invitation": every seed of the
  /// 3.x line is like that, and the then `sendContactRequest` refused
  /// with a named reason instead of putting a request into the void. S389:
  /// the path no longer exists (S388-BAU-KONTAKT); on V4.2 the
  /// invitation card carries the code itself (§15.2, field `code`), and a record
  /// without it does not come about at all.
  String? seedKiB64;

  /// [seedKiB64] as bytes, or `null` if the field is empty, not
  /// decodable or not 32 B long.
  ///
  /// The same reasoning as for [seedEpBytes] next to it, and for the same
  /// reason in ONE place: the writers store URL-safe base64 WITHOUT
  /// padding, on which raw `base64Decode` throws with `Invalid length`.
  /// The length check is not cosmetic — §15.5: a
  /// `K_inv(i)` of wrong length would yield a different tag line than
  /// the issuer's, and the request would lie under a tag that nobody
  /// listens to.
  Uint8List? get seedKiBytes {
    final ki = seedKiB64;
    if (ki == null || ki.isEmpty) return null;
    try {
      final b = base64Decode(base64.normalize(ki));
      return b.length == 32 ? Uint8List.fromList(b) : null;
    } catch (_) {
      return null;
    }
  }

  /// §15.3.3 — under WHICH own invitation this request arrived.
  ///
  /// ── WHY THIS ATTRIBUTION EXISTS AT ALL ──────────────────────────────
  ///
  /// §15.3.3 demands it literally: "Every incoming request is shown
  /// attributed to the invitation (‚via invitation ‚conference' from
  /// Aug 3') — the tag family delivers the attribution for free. If a URI
  /// leaks, the issuer sees *which* invitation is flooding, and revokes
  /// exactly that one."
  ///
  /// ── AND WHY IT MUST BE PERSISTENT ───────────────────────────────────
  ///
  /// §15.4 lets the single-use invitation be revoked "after the first acceptance".
  /// Acceptance and arrival are, on the non-self-accepting
  /// paths, TWO points in time between which a restart may lie. An
  /// attribution kept only in memory would be gone afterwards, and the
  /// invitation would stay live although it was redeemed.
  ///
  /// ── WHAT IT EXPLICITLY IS NOT ───────────────────────────────────────
  ///
  /// **No proof of sender.** The tag derives from `K_inv(i)`, and in the
  /// class "published" everybody holds it (§15.3.1). It says "someone with
  /// this invitation", not "this person". Therefore it is never used in a
  /// trust decision; the pair designator stays empty on the
  /// invitation path (`v41_attach.dart`), and the verdict on the
  /// sender stays `skippedBootstrap`.
  ///
  /// `null` = the request did not come via an own invitation line
  /// (Speed receive, V3 legacy path, twin-sync takeover).
  int? viaInviteIndex;

  /// The generation `g_inv` for [viaInviteIndex] (§15.3.1).
  ///
  /// Without it the index is ambiguous after a bulk revocation: the
  /// counter keeps running across generations, but the harvest window
  /// keeps old generations open for the maximum TTL
  /// (`kInviteGenerationRetention`). A request from the previous
  /// generation must hit exactly ITS record on acceptance.
  int? viaInviteGeneration;

  /// §5.5b: node-IDs (hex, lowercase) of the seed peers imported from THIS
  /// contact's scanned ContactSeed. The First-CR-Mailbox fanout must deposit
  /// only on these — Arch §5.5b flow step 3: "The seed peers are those
  /// imported from the scanned ContactSeed ..., and protected seeds from
  /// unrelated older ContactSeeds must not [be used]." Without this list the
  /// fanout can only see the global `isProtectedSeed` flag, which is the
  /// union over every ContactSeed ever scanned.
  ///
  /// Empty for contacts created before this field existed (and for contacts
  /// that never came from a ContactSeed) — see the legacy fallback in
  /// `_seedPeerIdsForTarget`.
  List<String> seedPeerIdsHex;

  /// §8.3 — the stored trust anchor violated an invariant and must not be
  /// used. Set by the central anchor setter and by the load-time audit;
  /// cleared only by an explicitly confirmed re-anchor.
  ///
  /// Quarantine rather than deletion: an empty anchor is silently re-filled
  /// by the §8.1.1 "Restluecke A" branch from any incoming CR whose outer
  /// device signature verifies — and that signature is the sender's own.
  /// Deleting a corrupt anchor would therefore hand the next CR a free
  /// overwrite. A quarantined record blocks verification AND the silent
  /// re-fill until a human confirms.
  ///
  /// Background: in S280 a DhtRpc response mix-up wrote a node's OWN
  /// Ed25519 pubkey into a contact record. Every message from that contact
  /// then decrypted and died at the user-signature check, DELIVERY_RECEIPTs
  /// included — silently, for days.
  bool trustAnchorQuarantined;

  /// Human-readable reason for [trustAnchorQuarantined] (log + UI).
  String? trustAnchorQuarantineReason;

  /// §14.7.4: withhold this node's delivery status from this contact's UI.
  /// Purely local and unilateral — never negotiated (unlike everything in
  /// `ChatConfig`), never distributed as configuration; it rides as a bit on
  /// each outgoing DELIVERY_RECEIPT. Default false = disclose.
  bool withholdDeliveryStatus;

  /// §15.10 (proposal "contacts as fixed neighbours", D2 = a): this contact
  /// never takes a fixed neighbour seat (§5.2) — it forwards nothing for
  /// this node and does not learn when it sends or receives. A property of
  /// the contact, not a send mode (§3.3). Purely local: the mark travels
  /// nowhere; the service hands it to the delivery layer
  /// (`Contact.neverFixedNeighbour` in `mycelium/lib/memory_contact.dart`).
  /// Default false.
  bool neverFixedNeighbour;

  /// Returns localAlias if set, otherwise the contact's own displayName.
  String get effectiveName => localAlias ?? displayName;

  /// §15.7: this contact deleted their OWN identity — an `IDENTITY_DELETED`
  /// notice arrived under their key. The contact record is kept on purpose
  /// (name, picture, `effectiveName` all stay valid) so the conversation can
  /// keep showing who it was with; the UI layer is the one that must turn
  /// the conversation read-only and append the "(deleted)" suffix wherever
  /// this name or picture is rendered — this getter only names the state.
  ///
  /// Not to be confused with the user's OWN "delete contact" action
  /// (§15.9): that path removes the `ContactInfo` from the map entirely
  /// (`CleonaService.deleteContact`), so a record with `isDeleted == true`
  /// can only ever originate from the counterpart's own identity deletion.
  bool get isDeleted => status == 'deleted';

  ContactInfo({
    required this.nodeId,
    required this.displayName,
    this.localAlias,
    this.ed25519Pk,
    this.mlDsaPk,
    this.x25519Pk,
    this.mlKemPk,
    required this.status,
    this.message,
    this.profilePictureBase64,
    this.pendingNameChange,
    this.acceptedAt,
    this.verificationLevel = 'unverified',
    Set<String>? deviceNodeIds,
    List<ContactDeviceSigKey>? deviceSigKeys,
    this.deviceSetSeq = -1,
    this.birthdayMonth,
    this.birthdayDay,
    this.birthdayYear,
    this.kemRotationAt,
    this.lastAckedAt,
    this.autoRepairAttempted = false,
    this.seedDeviceIdHex,
    this.seedDxkB64,
    this.seedDmkB64,
    this.seedEpB64,
    Uint8List? peerFoundingEd25519Pk,
    this.seedKiB64,
    this.viaInviteIndex,
    this.viaInviteGeneration,
    List<String>? seedPeerIdsHex,
    this.trustAnchorQuarantined = false,
    this.trustAnchorQuarantineReason,
    this.withholdDeliveryStatus = false,
    this.neverFixedNeighbour = false,
  })  : deviceNodeIds = deviceNodeIds ?? {},
        deviceSigKeys = deviceSigKeys ?? [],
        // §15.2: the anchor comes in only via this one path and
        // is afterwards touched exclusively by [rememberFoundingAnchor]
        // — therefore directly onto the private field here, instead of making it
        // public.
        _peerFoundingEd25519Pk = (peerFoundingEd25519Pk != null &&
                peerFoundingEd25519Pk.length == 32)
            ? Uint8List.fromList(peerFoundingEd25519Pk)
            : null,
        seedPeerIdsHex = seedPeerIdsHex ?? [];

  String get nodeIdHex => bytesToHex(nodeId);

  Map<String, dynamic> toJson() => {
        'nodeId': bytesToHex(nodeId),
        'displayName': displayName,
        if (localAlias != null) 'localAlias': localAlias,
        'ed25519Pk': ed25519Pk != null ? bytesToHex(ed25519Pk!) : null,
        'mlDsaPk': mlDsaPk != null ? bytesToHex(mlDsaPk!) : null,
        'x25519Pk': x25519Pk != null ? bytesToHex(x25519Pk!) : null,
        'mlKemPk': mlKemPk != null ? bytesToHex(mlKemPk!) : null,
        'status': status,
        'message': message,
        if (profilePictureBase64 != null) 'profilePicture': profilePictureBase64,
        if (pendingNameChange != null) 'pendingNameChange': pendingNameChange,
        if (acceptedAt != null) 'acceptedAt': acceptedAt!.millisecondsSinceEpoch,
        'verificationLevel': verificationLevel,
        if (deviceNodeIds.isNotEmpty) 'deviceNodeIds': deviceNodeIds.toList(),
        if (deviceSigKeys.isNotEmpty)
          'deviceSigKeys': deviceSigKeys.map((d) => d.toJson()).toList(),
        if (deviceSetSeq >= 0) 'deviceSetSeq': deviceSetSeq,
        if (birthdayMonth != null) 'birthdayMonth': birthdayMonth,
        if (birthdayDay != null) 'birthdayDay': birthdayDay,
        if (birthdayYear != null) 'birthdayYear': birthdayYear,
        if (kemRotationAt != null)
          'kemRotationAt': kemRotationAt!.millisecondsSinceEpoch,
        if (lastAckedAt != null) 'lastAckedAt': lastAckedAt!.millisecondsSinceEpoch,
        if (autoRepairAttempted) 'autoRepairAttempted': autoRepairAttempted,
        if (seedDeviceIdHex != null) 'seedDeviceIdHex': seedDeviceIdHex,
        if (seedDxkB64 != null) 'seedDxkB64': seedDxkB64,
        if (seedDmkB64 != null) 'seedDmkB64': seedDmkB64,
        if (seedEpB64 != null) 'seedEpB64': seedEpB64,
        // §15.2: the founding anchor MUST survive the restart. Kept only in
        // memory it would have to be guessed again after every start from
        // `ed25519Pk` — i.e. from the field that rotation
        // overwrites, and thus exactly the error it fixes.
        if (_peerFoundingEd25519Pk != null)
          'peerFoundingEd25519Pk': bytesToHex(_peerFoundingEd25519Pk!),
        if (seedKiB64 != null) 'seedKiB64': seedKiB64,
        if (viaInviteIndex != null) 'viaInviteIndex': viaInviteIndex,
        if (viaInviteGeneration != null)
          'viaInviteGeneration': viaInviteGeneration,
        if (seedPeerIdsHex.isNotEmpty) 'seedPeerIdsHex': seedPeerIdsHex,
        if (trustAnchorQuarantined) 'trustAnchorQuarantined': true,
        if (trustAnchorQuarantineReason != null)
          'trustAnchorQuarantineReason': trustAnchorQuarantineReason,
        if (withholdDeliveryStatus) 'withholdDeliveryStatus': true,
        if (neverFixedNeighbour) 'neverFixedNeighbour': true,
      };

  static ContactInfo fromJson(Map<String, dynamic> json) => ContactInfo(
        nodeId: hexToBytes(json['nodeId'] as String),
        displayName: json['displayName'] as String? ?? '',
        localAlias: json['localAlias'] as String?,
        ed25519Pk: json['ed25519Pk'] != null
            ? hexToBytes(json['ed25519Pk'] as String)
            : null,
        mlDsaPk: json['mlDsaPk'] != null
            ? hexToBytes(json['mlDsaPk'] as String)
            : null,
        x25519Pk: json['x25519Pk'] != null
            ? hexToBytes(json['x25519Pk'] as String)
            : null,
        mlKemPk: json['mlKemPk'] != null
            ? hexToBytes(json['mlKemPk'] as String)
            : null,
        status: json['status'] as String? ?? 'pending',
        message: json['message'] as String?,
        profilePictureBase64: json['profilePicture'] as String?,
        pendingNameChange: json['pendingNameChange'] as String?,
        acceptedAt: json['acceptedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['acceptedAt'] as int)
            : null,
        verificationLevel: json['verificationLevel'] as String? ?? 'unverified',
        deviceNodeIds: json['deviceNodeIds'] != null
            ? (json['deviceNodeIds'] as List).cast<String>().toSet()
            : null,
        deviceSigKeys: json['deviceSigKeys'] != null
            ? (json['deviceSigKeys'] as List)
                .map((e) =>
                    ContactDeviceSigKey.fromJson(e as Map<String, dynamic>))
                .toList()
            : null,
        deviceSetSeq: json['deviceSetSeq'] as int? ?? -1,
        birthdayMonth: json['birthdayMonth'] as int?,
        birthdayDay: json['birthdayDay'] as int?,
        birthdayYear: json['birthdayYear'] as int?,
        kemRotationAt: json['kemRotationAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['kemRotationAt'] as int)
            : null,
        lastAckedAt: json['lastAckedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['lastAckedAt'] as int)
            : null,
        autoRepairAttempted: (json['autoRepairAttempted'] as bool?) ?? false,
        seedDeviceIdHex: json['seedDeviceIdHex'] as String?,
        seedDxkB64: json['seedDxkB64'] as String?,
        seedDmkB64: json['seedDmkB64'] as String?,
        seedEpB64: json['seedEpB64'] as String?,
        peerFoundingEd25519Pk: json['peerFoundingEd25519Pk'] != null
            ? hexToBytes(json['peerFoundingEd25519Pk'] as String)
            : null,
        seedKiB64: json['seedKiB64'] as String?,
        viaInviteIndex: json['viaInviteIndex'] as int?,
        viaInviteGeneration: json['viaInviteGeneration'] as int?,
        seedPeerIdsHex: json['seedPeerIdsHex'] != null
            ? (json['seedPeerIdsHex'] as List).cast<String>().toList()
            : null,
        trustAnchorQuarantined:
            json['trustAnchorQuarantined'] as bool? ?? false,
        trustAnchorQuarantineReason:
            json['trustAnchorQuarantineReason'] as String?,
        withholdDeliveryStatus:
            json['withholdDeliveryStatus'] as bool? ?? false,
        neverFixedNeighbour: json['neverFixedNeighbour'] as bool? ?? false,
      );
}

/// §7.1 LD-9/LD-11: Delegation status for the local device.
class LinkedDeviceStatus {
  final bool isLinkedDevice;
  final int capabilities;
  final int issuedAtMs;
  final int maxValidUntilMs;
  final bool isExpired;

  LinkedDeviceStatus({
    required this.isLinkedDevice,
    this.capabilities = 0,
    this.issuedAtMs = 0,
    this.maxValidUntilMs = 0,
    this.isExpired = false,
  });

  bool get hasCert => isLinkedDevice && issuedAtMs > 0;

  int get daysRemaining {
    if (maxValidUntilMs == 0) return -1;
    final remaining = maxValidUntilMs - DateTime.now().millisecondsSinceEpoch;
    return (remaining / (24 * 60 * 60 * 1000)).ceil();
  }

  bool get expiresWithin7Days {
    final d = daysRemaining;
    return d >= 0 && d <= 7;
  }

  String get expiryDate {
    if (maxValidUntilMs == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(maxValidUntilMs);
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  List<String> get capabilityNames {
    final names = <String>[];
    if (capabilities & 1 != 0) names.add('send');
    if (capabilities & 2 != 0) names.add('contacts');
    if (capabilities & 4 != 0) names.add('groups');
    if (capabilities & 8 != 0) names.add('channels');
    return names;
  }

  Map<String, dynamic> toJson() => {
        'isLinkedDevice': isLinkedDevice,
        'capabilities': capabilities,
        'issuedAtMs': issuedAtMs,
        'maxValidUntilMs': maxValidUntilMs,
        'isExpired': isExpired,
      };

  static LinkedDeviceStatus fromJson(Map<String, dynamic> json) =>
      LinkedDeviceStatus(
        isLinkedDevice: json['isLinkedDevice'] as bool? ?? false,
        capabilities: json['capabilities'] as int? ?? 0,
        issuedAtMs: json['issuedAtMs'] as int? ?? 0,
        maxValidUntilMs: json['maxValidUntilMs'] as int? ?? 0,
        isExpired: json['isExpired'] as bool? ?? false,
      );
}

/// Multi-Device (§26): represents a twin device running the same identity.
class DeviceRecord {
  final String deviceId; // UUID hex string, generated once on first launch
  String deviceName;     // OS hostname by default, user-editable
  String platform;       // android, ios, linux, windows, macos
  final DateTime firstSeen;
  DateTime lastSeen;
  bool isThisDevice;
  /// §26 Phase 4: routing-level node ID for this device (from IdentityContext.deviceNodeId).
  String? deviceNodeIdHex;

  DeviceRecord({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.firstSeen,
    required this.lastSeen,
    this.isThisDevice = false,
    this.deviceNodeIdHex,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'firstSeen': firstSeen.millisecondsSinceEpoch,
        'lastSeen': lastSeen.millisecondsSinceEpoch,
        'isThisDevice': isThisDevice,
        if (deviceNodeIdHex != null) 'deviceNodeIdHex': deviceNodeIdHex,
      };

  static DeviceRecord fromJson(Map<String, dynamic> json) => DeviceRecord(
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String? ?? 'Unknown',
        platform: json['platform'] as String? ?? 'unknown',
        firstSeen: DateTime.fromMillisecondsSinceEpoch(json['firstSeen'] as int? ?? 0),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int? ?? 0),
        isThisDevice: json['isThisDevice'] as bool? ?? false,
        deviceNodeIdHex: json['deviceNodeIdHex'] as String?,
      );
}

// ── Calendar (§23) ─────────────────────────────────────────────────────

/// Event category for calendar events.
enum EventCategory { appointment, task, birthday, reminder, meeting }

/// Free/Busy visibility level (per-contact configurable).
enum FreeBusyLevel { full, timeOnly, hidden }

/// RSVP response status.
enum RsvpStatus { accepted, declined, tentative, proposeNewTime }

/// A calendar event (§23.2.1).
class CalendarEvent {
  final String eventId;          // UUID hex
  final String identityId;       // Which identity owns this event
  String title;
  String? description;
  String? location;
  int startTime;                 // Unix milliseconds
  int endTime;                   // Unix milliseconds
  bool allDay;
  String timeZone;               // IANA timezone

  // Recurrence (RRULE-compatible)
  String? recurrenceRule;        // RFC 5545 RRULE format
  List<int> recurrenceExceptions; // Excluded dates as Unix ms

  // Categorization
  EventCategory category;
  int? color;                    // ARGB for visual grouping
  List<String> tags;

  // Task-specific fields
  bool taskCompleted;
  int? taskDueDate;              // Unix ms deadline
  int taskPriority;              // 0=none, 1=low, 2=medium, 3=high

  // Birthday-specific fields
  String? birthdayContactId;     // Linked contact's node ID hex
  int? birthdayYear;             // Birth year for age calculation

  // Participants: either individual contacts OR a group (not both)
  List<String> attendeeNodeIds;  // Individual contact node IDs (hex)
  String? groupId;               // Linked group/channel ID hex
  bool hasCall;

  // Reminders (minutes before event)
  List<int> reminders;

  // Free/Busy visibility control
  FreeBusyLevel freeBusyVisibility;
  Map<String, FreeBusyLevel> visibilityOverrides; // nodeIdHex → level

  // RSVP state (for received invites)
  Map<String, RsvpStatus> rsvpResponses; // nodeIdHex → status

  // Metadata
  int createdAt;                 // Unix ms
  int updatedAt;                 // Unix ms
  String createdBy;              // Node ID hex of creator
  bool cancelled;

  CalendarEvent({
    required this.eventId,
    required this.identityId,
    required this.title,
    this.description,
    this.location,
    required this.startTime,
    required this.endTime,
    this.allDay = false,
    this.timeZone = 'UTC',
    this.recurrenceRule,
    List<int>? recurrenceExceptions,
    this.category = EventCategory.appointment,
    this.color,
    List<String>? tags,
    this.taskCompleted = false,
    this.taskDueDate,
    this.taskPriority = 0,
    this.birthdayContactId,
    this.birthdayYear,
    List<String>? attendeeNodeIds,
    this.groupId,
    this.hasCall = false,
    List<int>? reminders,
    this.freeBusyVisibility = FreeBusyLevel.timeOnly,
    Map<String, FreeBusyLevel>? visibilityOverrides,
    Map<String, RsvpStatus>? rsvpResponses,
    int? createdAt,
    int? updatedAt,
    required this.createdBy,
    this.cancelled = false,
  })  : attendeeNodeIds = attendeeNodeIds ?? [],
        recurrenceExceptions = recurrenceExceptions ?? [],
        tags = tags ?? [],
        reminders = reminders ?? [15],
        visibilityOverrides = visibilityOverrides ?? {},
        rsvpResponses = rsvpResponses ?? {},
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'identityId': identityId,
        'title': title,
        if (description != null) 'description': description,
        if (location != null) 'location': location,
        'startTime': startTime,
        'endTime': endTime,
        'allDay': allDay,
        'timeZone': timeZone,
        if (recurrenceRule != null) 'recurrenceRule': recurrenceRule,
        if (recurrenceExceptions.isNotEmpty) 'recurrenceExceptions': recurrenceExceptions,
        'category': category.index,
        if (color != null) 'color': color,
        if (tags.isNotEmpty) 'tags': tags,
        'taskCompleted': taskCompleted,
        if (taskDueDate != null) 'taskDueDate': taskDueDate,
        'taskPriority': taskPriority,
        if (birthdayContactId != null) 'birthdayContactId': birthdayContactId,
        if (birthdayYear != null) 'birthdayYear': birthdayYear,
        if (attendeeNodeIds.isNotEmpty) 'attendeeNodeIds': attendeeNodeIds,
        if (groupId != null) 'groupId': groupId,
        'hasCall': hasCall,
        'reminders': reminders,
        'freeBusyVisibility': freeBusyVisibility.index,
        if (visibilityOverrides.isNotEmpty)
          'visibilityOverrides': visibilityOverrides.map((k, v) => MapEntry(k, v.index)),
        if (rsvpResponses.isNotEmpty)
          'rsvpResponses': rsvpResponses.map((k, v) => MapEntry(k, v.index)),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
        'cancelled': cancelled,
      };

  static CalendarEvent fromJson(Map<String, dynamic> json) => CalendarEvent(
        eventId: json['eventId'] as String,
        identityId: json['identityId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        location: json['location'] as String?,
        startTime: json['startTime'] as int? ?? 0,
        endTime: json['endTime'] as int? ?? 0,
        allDay: json['allDay'] as bool? ?? false,
        timeZone: json['timeZone'] as String? ?? 'UTC',
        recurrenceRule: json['recurrenceRule'] as String?,
        recurrenceExceptions: (json['recurrenceExceptions'] as List?)?.cast<int>(),
        category: EventCategory.values[json['category'] as int? ?? 0],
        color: json['color'] as int?,
        tags: (json['tags'] as List?)?.cast<String>(),
        taskCompleted: json['taskCompleted'] as bool? ?? false,
        taskDueDate: json['taskDueDate'] as int?,
        taskPriority: json['taskPriority'] as int? ?? 0,
        birthdayContactId: json['birthdayContactId'] as String?,
        birthdayYear: json['birthdayYear'] as int?,
        attendeeNodeIds: (json['attendeeNodeIds'] as List?)?.cast<String>(),
        groupId: json['groupId'] as String?,
        hasCall: json['hasCall'] as bool? ?? false,
        reminders: (json['reminders'] as List?)?.cast<int>(),
        freeBusyVisibility: FreeBusyLevel.values[json['freeBusyVisibility'] as int? ?? 1],
        visibilityOverrides: (json['visibilityOverrides'] as Map?)?.map(
            (k, v) => MapEntry(k as String, FreeBusyLevel.values[v as int])),
        rsvpResponses: (json['rsvpResponses'] as Map?)?.map(
            (k, v) => MapEntry(k as String, RsvpStatus.values[v as int])),
        createdAt: json['createdAt'] as int?,
        updatedAt: json['updatedAt'] as int?,
        createdBy: json['createdBy'] as String? ?? '',
        cancelled: json['cancelled'] as bool? ?? false,
      );
}

/// Free/Busy settings for a single identity.
class FreeBusySettings {
  FreeBusyLevel defaultLevel;
  Map<String, FreeBusyLevel> contactOverrides; // nodeIdHex → level

  FreeBusySettings({
    this.defaultLevel = FreeBusyLevel.timeOnly,
    Map<String, FreeBusyLevel>? contactOverrides,
  }) : contactOverrides = contactOverrides ?? {};

  Map<String, dynamic> toJson() => {
        'defaultLevel': defaultLevel.index,
        if (contactOverrides.isNotEmpty)
          'contactOverrides': contactOverrides.map((k, v) => MapEntry(k, v.index)),
      };

  static FreeBusySettings fromJson(Map<String, dynamic> json) => FreeBusySettings(
        defaultLevel: FreeBusyLevel.values[json['defaultLevel'] as int? ?? 1],
        contactOverrides: (json['contactOverrides'] as Map?)?.map(
            (k, v) => MapEntry(k as String, FreeBusyLevel.values[v as int])),
      );
}

// ── Polls & Voting (§24) ────────────────────────────────────────────────

enum PollType { singleChoice, multipleChoice, datePoll, scale, freeText }

enum DateAvailability { yes, no, maybe }

/// A single option within a poll.
class PollOption {
  final int optionId;
  final String label;
  final int? dateStart; // Unix ms, DATE_POLL only
  final int? dateEnd;   // Unix ms, DATE_POLL only

  PollOption({
    required this.optionId,
    required this.label,
    this.dateStart,
    this.dateEnd,
  });

  Map<String, dynamic> toJson() => {
        'optionId': optionId,
        'label': label,
        if (dateStart != null) 'dateStart': dateStart,
        if (dateEnd != null) 'dateEnd': dateEnd,
      };

  static PollOption fromJson(Map<String, dynamic> json) => PollOption(
        optionId: json['optionId'] as int,
        label: json['label'] as String? ?? '',
        dateStart: json['dateStart'] as int?,
        dateEnd: json['dateEnd'] as int?,
      );
}

/// Poll configuration (§24.2.1 PollSettings).
class PollSettings {
  bool anonymous;
  int deadline; // 0 = no deadline
  bool allowVoteChange;
  bool showResultsBeforeClose;
  int maxChoices; // 0 = unlimited
  int scaleMin;
  int scaleMax;
  bool onlyMembersCanVote;

  PollSettings({
    this.anonymous = false,
    this.deadline = 0,
    this.allowVoteChange = true,
    this.showResultsBeforeClose = true,
    this.maxChoices = 0,
    this.scaleMin = 1,
    this.scaleMax = 5,
    this.onlyMembersCanVote = false,
  });

  Map<String, dynamic> toJson() => {
        'anonymous': anonymous,
        'deadline': deadline,
        'allowVoteChange': allowVoteChange,
        'showResultsBeforeClose': showResultsBeforeClose,
        'maxChoices': maxChoices,
        'scaleMin': scaleMin,
        'scaleMax': scaleMax,
        'onlyMembersCanVote': onlyMembersCanVote,
      };

  static PollSettings fromJson(Map<String, dynamic> json) => PollSettings(
        anonymous: json['anonymous'] as bool? ?? false,
        deadline: json['deadline'] as int? ?? 0,
        allowVoteChange: json['allowVoteChange'] as bool? ?? true,
        showResultsBeforeClose:
            json['showResultsBeforeClose'] as bool? ?? true,
        maxChoices: json['maxChoices'] as int? ?? 0,
        scaleMin: json['scaleMin'] as int? ?? 1,
        scaleMax: json['scaleMax'] as int? ?? 5,
        onlyMembersCanVote: json['onlyMembersCanVote'] as bool? ?? false,
      );
}

/// A recorded individual vote (non-anonymous).
class PollVoteRecord {
  final String pollId;
  final String voterIdHex; // For anonymous polls: hex of key image
  String voterName;
  List<int> selectedOptions;
  Map<int, DateAvailability> dateResponses;
  int scaleValue;
  String freeText;
  int votedAt;
  final bool anonymous;

  PollVoteRecord({
    required this.pollId,
    required this.voterIdHex,
    this.voterName = '',
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    this.scaleValue = 0,
    this.freeText = '',
    required this.votedAt,
    this.anonymous = false,
  })  : selectedOptions = selectedOptions ?? [],
        dateResponses = dateResponses ?? {};

  Map<String, dynamic> toJson() => {
        'pollId': pollId,
        'voterIdHex': voterIdHex,
        'voterName': voterName,
        if (selectedOptions.isNotEmpty) 'selectedOptions': selectedOptions,
        if (dateResponses.isNotEmpty)
          'dateResponses':
              dateResponses.map((k, v) => MapEntry(k.toString(), v.index)),
        'scaleValue': scaleValue,
        if (freeText.isNotEmpty) 'freeText': freeText,
        'votedAt': votedAt,
        'anonymous': anonymous,
      };

  static PollVoteRecord fromJson(Map<String, dynamic> json) => PollVoteRecord(
        pollId: json['pollId'] as String,
        voterIdHex: json['voterIdHex'] as String,
        voterName: json['voterName'] as String? ?? '',
        selectedOptions: (json['selectedOptions'] as List?)?.cast<int>(),
        dateResponses: (json['dateResponses'] as Map?)?.map(
            (k, v) => MapEntry(int.parse(k as String),
                DateAvailability.values[v as int])),
        scaleValue: json['scaleValue'] as int? ?? 0,
        freeText: json['freeText'] as String? ?? '',
        votedAt: json['votedAt'] as int,
        anonymous: json['anonymous'] as bool? ?? false,
      );
}

/// A poll (§24.2.1 + aggregated votes).
class Poll {
  final String pollId;         // UUID hex
  final String identityId;     // Owning identity
  String question;
  String description;
  PollType pollType;
  List<PollOption> options;
  PollSettings settings;
  final String groupId;        // Group or channel this poll belongs to
  final String createdByHex;   // Creator's node ID hex
  String createdByName;
  final int createdAt;
  int updatedAt;
  bool closed;

  /// Votes keyed by voterIdHex (non-anonymous) or by key-image hex (anonymous).
  Map<String, PollVoteRecord> votes;

  /// For channel mode: cached snapshot from the creator.
  PollSnapshotCache? cachedSnapshot;

  Poll({
    required this.pollId,
    required this.identityId,
    required this.question,
    this.description = '',
    required this.pollType,
    required this.options,
    required this.settings,
    required this.groupId,
    required this.createdByHex,
    this.createdByName = '',
    required this.createdAt,
    int? updatedAt,
    this.closed = false,
    Map<String, PollVoteRecord>? votes,
    this.cachedSnapshot,
  })  : updatedAt = updatedAt ?? createdAt,
        votes = votes ?? {};

  Map<String, dynamic> toJson() => {
        'pollId': pollId,
        'identityId': identityId,
        'question': question,
        if (description.isNotEmpty) 'description': description,
        'pollType': pollType.index,
        'options': options.map((o) => o.toJson()).toList(),
        'settings': settings.toJson(),
        'groupId': groupId,
        'createdByHex': createdByHex,
        'createdByName': createdByName,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'closed': closed,
        if (votes.isNotEmpty)
          'votes': votes.map((k, v) => MapEntry(k, v.toJson())),
        if (cachedSnapshot != null) 'cachedSnapshot': cachedSnapshot!.toJson(),
      };

  static Poll fromJson(Map<String, dynamic> json) => Poll(
        pollId: json['pollId'] as String,
        identityId: json['identityId'] as String? ?? '',
        question: json['question'] as String? ?? '',
        description: json['description'] as String? ?? '',
        pollType: PollType.values[json['pollType'] as int? ?? 0],
        options: (json['options'] as List? ?? [])
            .map((e) => PollOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        settings: PollSettings.fromJson(
            (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {}),
        groupId: json['groupId'] as String? ?? '',
        createdByHex: json['createdByHex'] as String? ?? '',
        createdByName: json['createdByName'] as String? ?? '',
        createdAt: json['createdAt'] as int? ?? 0,
        updatedAt: json['updatedAt'] as int?,
        closed: json['closed'] as bool? ?? false,
        votes: (json['votes'] as Map?)?.map((k, v) => MapEntry(
            k as String,
            PollVoteRecord.fromJson((v as Map).cast<String, dynamic>()))),
        cachedSnapshot: json['cachedSnapshot'] == null
            ? null
            : PollSnapshotCache.fromJson(
                (json['cachedSnapshot'] as Map).cast<String, dynamic>()),
      );
}

/// A PollSnapshot as received by a channel subscriber (§24.3.2).
class PollSnapshotCache {
  final String pollId;
  final int totalVotes;
  final Map<int, int> optionCounts;            // SINGLE/MULTIPLE
  final Map<int, Map<DateAvailability, int>> dateCounts; // DATE
  final double scaleAverage;
  final int scaleCount;
  final bool closed;
  final int snapshotAt;

  PollSnapshotCache({
    required this.pollId,
    required this.totalVotes,
    Map<int, int>? optionCounts,
    Map<int, Map<DateAvailability, int>>? dateCounts,
    this.scaleAverage = 0.0,
    this.scaleCount = 0,
    this.closed = false,
    required this.snapshotAt,
  })  : optionCounts = optionCounts ?? {},
        dateCounts = dateCounts ?? {};

  Map<String, dynamic> toJson() => {
        'pollId': pollId,
        'totalVotes': totalVotes,
        if (optionCounts.isNotEmpty)
          'optionCounts':
              optionCounts.map((k, v) => MapEntry(k.toString(), v)),
        if (dateCounts.isNotEmpty)
          'dateCounts': dateCounts.map((k, v) => MapEntry(
              k.toString(),
              v.map((k2, v2) => MapEntry(k2.index.toString(), v2)))),
        'scaleAverage': scaleAverage,
        'scaleCount': scaleCount,
        'closed': closed,
        'snapshotAt': snapshotAt,
      };

  static PollSnapshotCache fromJson(Map<String, dynamic> json) =>
      PollSnapshotCache(
        pollId: json['pollId'] as String,
        totalVotes: json['totalVotes'] as int? ?? 0,
        optionCounts: (json['optionCounts'] as Map?)?.map(
            (k, v) => MapEntry(int.parse(k as String), v as int)),
        dateCounts: (json['dateCounts'] as Map?)?.map((k, v) => MapEntry(
            int.parse(k as String),
            (v as Map).map((k2, v2) => MapEntry(
                DateAvailability.values[int.parse(k2 as String)],
                v2 as int)))),
        scaleAverage: (json['scaleAverage'] as num?)?.toDouble() ?? 0.0,
        scaleCount: json['scaleCount'] as int? ?? 0,
        closed: json['closed'] as bool? ?? false,
        snapshotAt: json['snapshotAt'] as int? ?? 0,
      );
}

/// Aggregated tally computed locally from [Poll.votes] (groups) or the cached
/// snapshot (channels).
class PollTally {
  final int totalVotes;
  final Map<int, int> optionCounts; // SINGLE/MULTIPLE
  final Map<int, Map<DateAvailability, int>> dateCounts;
  final double scaleAverage;
  final int scaleCount;
  final List<String> freeTextResponses; // Only for FREE_TEXT

  PollTally({
    required this.totalVotes,
    Map<int, int>? optionCounts,
    Map<int, Map<DateAvailability, int>>? dateCounts,
    this.scaleAverage = 0.0,
    this.scaleCount = 0,
    List<String>? freeTextResponses,
  })  : optionCounts = optionCounts ?? {},
        dateCounts = dateCounts ?? {},
        freeTextResponses = freeTextResponses ?? [];

  Map<String, dynamic> toJson() => {
        'totalVotes': totalVotes,
        if (optionCounts.isNotEmpty)
          'optionCounts':
              optionCounts.map((k, v) => MapEntry(k.toString(), v)),
        if (dateCounts.isNotEmpty)
          'dateCounts': dateCounts.map((k, v) => MapEntry(
              k.toString(),
              v.map((k2, v2) => MapEntry(k2.index.toString(), v2)))),
        'scaleAverage': scaleAverage,
        'scaleCount': scaleCount,
        if (freeTextResponses.isNotEmpty) 'freeTextResponses': freeTextResponses,
      };
}
