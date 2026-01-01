import 'dart:typed_data';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/service/multi_interface_mode.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/stats/network_stats.dart';
import 'package:cleona/core/contact/contact_seed.dart' show ContactSeedBuilder;
import 'package:cleona/core/contact/invite_issue_refusal.dart';
// Re-export COMPLETELY, not `show InviteIssueRefusal`: the
// mapping reason → wire identifier → message lives in an EXTENSION, and
// an extension does not travel via a `show` list of the type. With the
// narrow version `refusal.messageKey` did not translate in the UI.
export 'package:cleona/core/contact/invite_issue_refusal.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/media/link_preview_fetcher.dart';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/polls/poll_manager.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/crypto/hd_wallet.dart' show HdWallet;
import 'package:cleona/core/service/readiness_names.dart';
export 'package:cleona/core/service/readiness_names.dart';
import 'package:cleona/core/service/invitation_card_types.dart';
export 'package:cleona/core/service/invitation_card_types.dart';

/// §7.5: what a `ROTATION_APPROVAL_REQUEST` is actually asking the user for.
///
/// Both occasions travel the same wire channel (`TwinSyncType`
/// `ROTATION_APPROVAL_REQUEST`/`_RESPONSE`) and produce the same
/// countersignature format, but they are two different questions to the human:
/// "your identity keys are being replaced" versus "a device is being removed
/// from your identity". Without this discriminator a Linked Device announces
/// every request as an Emergency Key Rotation, so a device-set change would be
/// confirmed under a false description — a genuine signature for something the
/// user was never asked about. Mirrors `proto.ApprovalKindV3`.
enum RotationApprovalKind {
  /// Emergency Key Rotation. The hash is `computeRotationHash(...)` over the
  /// new User pubkeys.
  keyRotation('key_rotation'),

  /// Device-set change (the §7.5 shrink proof). The hash is
  /// `computeDeviceSetChangeHash(...)` over the REMAINING device node ids and
  /// the sequence number of the manifest that will carry the proof.
  deviceSetChange('device_set_change');

  const RotationApprovalKind(this.wireName);

  /// Stable identifier on the IPC boundary. Deliberately a string and not the
  /// enum index: the IPC payload is JSON and must not silently re-map when a
  /// value is inserted into this enum.
  final String wireName;

  /// Unknown/absent names map to [keyRotation] — the same fallback the proto
  /// default (`APPROVAL_KIND_KEY_ROTATION = 0`) gives for senders that predate
  /// the field, so old and new peers read an unmarked request identically.
  static RotationApprovalKind fromWireName(String? name) =>
      RotationApprovalKind.values.firstWhere(
        (k) => k.wireName == name,
        orElse: () => RotationApprovalKind.keyRotation,
      );
}

/// Abstract interface for the Cleona service.
/// Both CleonaService (direct) and IpcClient (remote) implement this.
/// Whether the daemon on the other end of the IPC boundary mints identities
/// the same way this build does.
///
/// The two halves of the app are separate binaries deployed separately, so
/// they can disagree about the one formula that decides who everybody is
/// (`userId = SHA-256(kIdentityDomain ‖ ed25519_pk ‖ mldsa65_pk)`, v4.2
/// §4.1). When they do, every
/// UserID the daemon reports is a value the GUI cannot reproduce: the GUI
/// then cannot honestly hand out a ContactSeed, because the self-check that
/// makes a seed self-certifying (`ContactSeed.verifyIntegrity`) must fail.
/// Measured 2026-08-30 — see [HdWallet.identityDerivationFingerprint].
enum IdentityDerivationSkew {
  /// Measured equal — the GUI can vouch for what the daemon reports.
  ok,

  /// Not measurable: no snapshot yet, or a daemon older than the fingerprint.
  /// Says nothing about agreement; must not be reported as a defect.
  unknown,

  /// Measured different. Fail closed and say so.
  mismatch;

  /// Classify a fingerprint reported by the other half of the app against the
  /// one this build computes.
  ///
  /// A missing or empty value is [unknown], never [mismatch]: a daemon older
  /// than this field reports nothing, and calling that a defect would raise a
  /// false alarm on every rollout where one half lags by a build. Only a
  /// value that is present AND different is a measured disagreement.
  static IdentityDerivationSkew classify(String? reportedFingerprint) {
    if (reportedFingerprint == null || reportedFingerprint.isEmpty) {
      return IdentityDerivationSkew.unknown;
    }
    return reportedFingerprint == HdWallet.identityDerivationFingerprint
        ? IdentityDerivationSkew.ok
        : IdentityDerivationSkew.mismatch;
  }
}

/// What of an issued invitation goes into the ContactSeed
/// (§15.3, §15.5).
///
/// NOT `InviteRecord`: that is the entry in the issuer's book and
/// carries counter, revocation and label. Only what the seed needs
/// goes over the interface — class, deadline, key. A book record that
/// wandered over IPC would be a second truth next to the book.
///
/// [inviteClassCode] is the ONE-character code from `InviteClass` (`c`, `p`,
/// …) and not the enum value: `service_interface.dart` lives below the
/// UI and is not to pull in `core/contact/`, and over IPC
/// the value has to go through JSON anyway.
class IssuedInvite {
  const IssuedInvite({
    required this.inviteClassCode,
    required this.index,
    required this.inviteKey,
    this.expiresAtMs,
  });

  /// `InviteClass.code` — one character.
  final String inviteClassCode;

  /// Running number in the issuer's book (§15.3.1 `i` in `K_inv(i)`).
  final int index;

  /// `K_inv(i)` — the CARRIER of the contact request (§15.3.2). Without it
  /// the request has no tagline on which the issuer would ever harvest it.
  final Uint8List inviteKey;

  /// Expiry in ms since epoch, `null` for an unlimited invitation.
  final int? expiresAtMs;
}

/// The result of [ICleonaService.issueInviteForSharing]: either the
/// invitation or the REASON why there is none.
///
/// Until S381 the call returned `null` and the reason stayed in the
/// issuer's log — the UI then guessed the most frequent one. Why
/// that is worse than no reason at all is in the header of
/// `invite_issue_refusal.dart`.
typedef InviteIssueResult = InviteIssueOutcome<IssuedInvite>;

/// An open invitation, as the UI has to list it
/// (§15.3.2 cap, §15.3.3 single revocation).
///
/// Deliberately WITHOUT `K_inv(i)`: listing and revoking do not need
/// the key, and what is not needed does not travel
/// across the process boundary either.
class OpenInvitation {
  const OpenInvitation({
    required this.index,
    required this.inviteClassCode,
    required this.expiresAtMs,
    required this.label,
    required this.singleUse,
  });

  /// `i` from `K_inv(i)` (§15.3.1) — the identifier for revocation.
  final int index;

  /// `InviteClass.wireChar` — one character.
  final String inviteClassCode;

  /// Expiry in ms since epoch, `null` for an unlimited invitation.
  final int? expiresAtMs;

  /// Label under which it was issued (e.g. `qr-card`).
  final String label;

  /// §15.4: single-use invitation of the self-acceptance class.
  final bool singleUse;

  Map<String, dynamic> toJson() => {
        'index': index,
        'class': inviteClassCode,
        'expiresAtMs': expiresAtMs,
        'label': label,
        'singleUse': singleUse,
      };

  static OpenInvitation fromJson(Map<String, dynamic> j) => OpenInvitation(
        index: j['index'] as int? ?? 0,
        inviteClassCode: j['class'] as String? ?? '',
        expiresAtMs: j['expiresAtMs'] as int?,
        label: j['label'] as String? ?? '',
        singleUse: j['singleUse'] == true,
      );
}

abstract class ICleonaService {
  // State
  Map<String, Conversation> get conversations;

  // Callbacks for GUI
  void Function()? onStateChanged;
  void Function(String conversationId, UiMessage message)? onNewMessage;
  void Function(String nodeIdHex, String displayName)? onContactRequestReceived;
  void Function(String nodeIdHex)? onContactAccepted;

  // Getters
  String get nodeIdHex;
  /// Profile directory of the ACTIVE identity — in `CleonaService` from the
  /// `ServiceContext` (= `identity.profileDir`), in `IpcClient` from the
  /// daemon's `get_state` snapshot. **Not** `AppPaths.dataDir`:
  /// that is the process sink for lines that belong to no identity.
  ///
  /// Used by GUI-side bridges (e.g. [AndroidCalendarBridge]) that
  /// build their own [CLogger] and whose lines belong in the log of the SAME
  /// identity the daemon also writes to.
  String get profileDir;
  /// Welle 5/6: Device-Node-ID (≠ User-ID) for direct InfraFrame addressing
  /// before the Auth-Manifest is published. Used by ContactSeed-URI.
  String get deviceNodeIdHex;
  /// Welle 5: Device-X25519-PK (32 bytes) — KEM subject for First-CR.
  /// Embedded in ContactSeed-URI so the receiver skips the 2D-DHT lookup.
  Uint8List get deviceX25519Pk;
  /// Welle 5: Device-ML-KEM-768-PK (1184 bytes) — see [deviceX25519Pk].
  Uint8List get deviceMlKemPk;
  /// rev3: User-Ed25519-PK (32 bytes) — trust-anchor for ContactSeed v2.
  Uint8List get userEd25519Pk;
  /// SR-2 (§8.1.1): founding User-Ed25519-PK — the key whose hash IS the
  /// userId. Equals [userEd25519Pk] for never-rotated identities; the
  /// ContactSeed emits the `fp` field only when the two differ.
  Uint8List get foundingEd25519Pk;
  /// The readiness state (§22.7): `searching` | `connecting` | `ready`.
  ///
  /// **The only quantity that speaks about DELIVERABILITY.** The three
  /// peer counters below count acquaintances; this state counts
  /// evidence — confirmed outbound relays that have accepted a placement.
  /// §22.7: "gates hang off the readiness state `ready`, never off a raw
  /// acquaintance count."
  ///
  /// **§22.7.2, normative for the transfer:** both implementations
  /// of this interface — the in-process service and the IPC client —
  /// deliver the value identically. A field that the daemon keeps and that the
  /// IPC client answers with a constant or a hard-wired `null`
  /// is a defect: the GUI would then show an immovable
  /// readiness, and the observable transition would be lost exactly in the
  /// layer meant to make it visible. The guard
  /// `smoke_ipc_interface_completeness.dart` checks this mechanically.
  ///
  /// As a string, not as an enumeration: the value crosses a
  /// JSON boundary, and `Readiness` lives in `lib/core/tagline/` — the
  /// service interface should not have to import the delivery layer
  /// just to name a state.
  String get readinessState;

  /// §25.4 — confirmed sync partners, separated by direction.
  ///
  /// **Outbound** are the partners this node itself reaches;
  /// they carry the OWN delivery and feed the readiness.
  /// **Inbound** are those that reach it; they say how much this
  /// node contributes for others, and are a precondition for inbound
  /// calls (§17). §28.7 rule 3 demands the separate numbers for displays
  /// — until AP-5 they did not cross the IPC boundary, and every display
  /// above it had to take one of the three V3 peer numbers as a substitute.
  ///
  /// They are EXPLICITLY no statement of deliverability: that is
  /// [readinessState] and only it (§22.7.3 "no display element derives
  /// deliverability from a partner count").
  int get syncPartnersOutbound;
  int get syncPartnersInbound;

  /// §25.4 "of which independent" — the number `ready` hangs on (>= 2).
  ///
  /// Not the gross number: two partners in the same network block are one
  /// (§22.7.1, `ReadinessTracker.verifiedRelays`).
  int get independentSyncPartners;

  /// §9.2 — how many responsible relays a Secure placement reaches TODAY.
  ///
  /// The number from which the consent dialog computes its TIME SPAN
  /// (`media_send_estimate.dart`). It must go over this interface
  /// and not be estimated from [syncPartnersOutbound] as a substitute:
  /// those are two different sets (session partners versus
  /// the responsible ones of a tag), and the full reasoning is at
  /// `V41Delivery.reachableResponsibleRelays`.
  ///
  /// `0` means "none known" — then no estimate is possible, and
  /// the dialog says so instead of showing a number from an empty
  /// set.
  int get reachableResponsibleRelays;

  /// §24.4.2 — DATA SAVER MODE: whether it is IN EFFECT.
  ///
  /// Not the same as "the user has chosen it": a Secure chat
  /// overrides the choice (see [dataSaverLockedBySecure]). The display
  /// must show the EFFECT, not the wish — §24.4.2 demands "a
  /// visible state, not a setting buried in a submenu", and a state
  /// that claims something other than what the stream does is no state.
  bool get dataSaverActive;

  /// §24.4.2 — whether the switch is locked because on this node a
  /// chat is set to High-Secure.
  ///
  /// "**Secure-Mode is exempt, without exception** (owner, 2026-08-30) …
  /// The cover stream is a node-wide stream, not per chat — so a node
  /// holding even one Secure chat keeps it in full, and the switch is
  /// then locked with its reason named."
  bool get dataSaverLockedBySecure;

  /// §24.4.2 — the setter. **Only a user action calls it**
  /// ("the app may suggest but must never activate it itself").
  ///
  /// Returns [kDataSaverOk] or [kDataSaverLockedBySecure]. The reason
  /// is REPORTED BACK and not merely swallowed: a setter that
  /// silently does nothing cannot be told apart from a broken one.
  String setDataSaver(bool on);

  /// V4.2 §11.9 — whether the fourth neighbour source (external address entries on
  /// public relays) is switched on. A DEVICE value: it applies to
  /// the one node of the device. "The source can be switched off by the
  /// user. A node with it switched off neither reads nor publishes."
  bool get externalRecordsEnabled;

  /// V4.2 §11.9 — the setter, ONLY from a user action. `false` if
  /// no node is attached and therefore nothing was set.
  bool setExternalRecordsEnabled(bool on);

  // ── S373: COVER IN THE OWN NETWORK ──────────────────────────────────
  //
  // The same constraints as for saver mode (§24.4.2), only stricter:
  // here the cover is not thinned but SUSPENDED. Therefore
  // there is no "on/off" switch, only a consent PER
  // SEGMENT — whether it takes effect is decided by the situation (all partners in the
  // segment, no Secure chat), not by the user and certainly not
  // by the app.

  /// Whether the switch-off is currently IN EFFECT.
  ///
  /// Not the same as "a consent exists": a Secure chat
  /// or a single outside partner overrides it. The display
  /// must show the EFFECT — a state that claims something other
  /// than what the stream does is no state.
  bool get lanShapingActive;

  /// The segments this node sits in (identifiers as they appear in
  /// the UI). Empty means "no own network recognised".
  List<String> get lanSegmentIds;

  /// The segments for which a consent CAN be given — at least one
  /// known neighbour currently sits there to which it could
  /// bind. Without that there is no button, but the
  /// reason.
  List<String> get lanSegmentsGrantable;

  /// Whether a consent is stored for this segment.
  bool lanSegmentConsented(String segmentId);

  /// The setter. **Only a user action calls it.** `false` if
  /// no neighbour is there to which the consent could bind —
  /// the reason is shown, not swallowed.
  bool grantLanShaping(String segmentId);

  /// The revocation. Always works.
  bool revokeLanShaping(String segmentId);

  // ── THREE GETTERS, ONE NUMBER — AND NO RECONCILIATION WITH THE STATS ──
  //
  // Until 01.09.2026 (S360) the constraint "Must match
  // `NetworkStats.activePeerCount` and the Connection Sheet list" stood here.
  // It had been VIOLATED since the CUT of 31.08., and not a
  // little: `peerCount` delivered the V4.1 session partners (a real
  // number different from 0), `NetworkStats.activePeerCount` delivered
  // constantly 0 because its writer had fallen with the routing table.
  // The home screen showed N, the network statistics 0 — the same question,
  // two answers.
  //
  // Resolved by making the RECONCILIATION PARTNER disappear:
  // `activePeerCount` was dropped when the network statistics were cut down to
  // V4.1 quantities. The network statistics now show the
  // direction-separated partner numbers (§25.4) and read them via
  // [syncPartnersOutbound]/[syncPartnersInbound] from THIS
  // interface — i.e. from the same source as everything here. A
  // divergence is thereby no longer possible, instead of merely
  // forbidden.
  //
  // ALL THREE GETTERS DELIVER THE SAME NUMBER, and that is no oversight:
  // V3 distinguished routing table / bidirectionally confirmed / reachable via a
  // live relay. This distinction presupposes a
  // routing table, and that no longer exists (reasoning at
  // `CleonaService._v41SessionPartner`). Inventing three different numbers
  // would be the worse answer.
  //
  // WHAT IT STANDS FOR IN THE UI: home badge, settings,
  // contacts, connection status, Android foreground notification.
  int get peerCount;
  int get confirmedPeerCount;
  int get reachablePeerCount;
  /// Whether an inbound port mapping is open (§25.9).
  ///
  /// SINCE S373 (07.09.2026) with a producer again: `CleonaService` reads
  /// `PortMapper.hasMapping` (UPnP/IGD + NAT-PMP/PCP,
  /// `lib/core/link_io/`), the IPC path passes the value through
  /// unchanged. Between the CUT (31.08.) and today it was a constant
  /// `false` — the four display sites (chip "UPnP", two
  /// system channel reports, crash and contact report) permanently showed
  /// "no".
  bool get hasPortMapping;
  /// True once at least one peer has been confirmed by a direct packet in
  /// the current daemon session. Used by the QR convergence gate (§8.1.1).
  bool get hasSessionConfirmedPeers;
  /// When the node started — used by the QR convergence indicator.
  DateTime? get nodeStartedAt;
  /// User-initiated NAT-Wizard trigger (e.g. icon-tap). Same effect as the
  /// automatic trigger but bypasses the dismiss-until flag so the user can
  /// always re-open it. GUI's `_natWizardShown` latch is also reset.
  void requestNatWizard();
  int get port;
  Future<bool> setPort(int newPort);
  List<String> get localIps;
  String? get publicIp;
  int? get publicPort;
  int get fragmentCount;
  bool get isRunning;
  String get displayName;
  /// True when the user clicked "Open anyway (limited)" on the
  /// [UpdateRequiredScreen] splash. While active, all user-message send/edit/
  /// delete paths short-circuit and incoming user messages are silently
  /// dropped. Per-session, not persisted; every restart re-shows the splash.
  /// IpcClient defaults to false (the daemon manages reducedMode locally and
  /// the GUI sets it before IPC handshake — sec-h5 §8.2 / T11).
  bool get reducedMode;

  List<ContactInfo> get acceptedContacts;
  List<ContactInfo> get pendingContacts;
  List<ContactInfo> get pendingOutgoingContacts;

  /// §5.5b / §8.1.1 step 3: outgoing CRs a seed peer has confirmed storing
  /// (`FIRST_CR_STORE_ACK`). Arch:3665 requires the sender to show these as
  /// "zugestellt (gespeichert)". Before S299 the status existed but had no
  /// getter, so the contact vanished from the UI the moment the store
  /// succeeded — success looked exactly like losing the request.
  List<ContactInfo> get storedForDeliveryContacts;
  ContactInfo? getContact(String nodeIdHex);
  List<Conversation> get sortedConversations;
  List<PeerSummary> get peerSummaries;

  /// Central, stable CR generator. Network data is computed once when
  /// the mesh converges (peers confirmed + public IP discovered) and
  /// cached. UI screens call [ContactSeedBuilder.getContactSeedFor]
  /// instead of assembling ContactSeeds themselves.
  ContactSeedBuilder get contactSeedBuilder;

  /// Whether this build and the service it talks to derive identities alike.
  /// In-process implementations are the same binary and answer [
  /// IdentityDerivationSkew.ok]; the IPC client measures it.
  IdentityDerivationSkew get identityDerivationSkew;

  // Groups
  Map<String, GroupInfo> get groups;
  Future<String?> createGroup(String name, List<String> memberNodeIdHexList);
  Future<UiMessage?> sendGroupTextMessage(String groupIdHex, String text, {String? replyToMessageId, String? replyToText, String? replyToSender});
  Future<bool> leaveGroup(String groupIdHex);
  Future<bool> inviteToGroup(String groupIdHex, String memberNodeIdHex);
  Future<bool> removeMemberFromGroup(String groupIdHex, String memberNodeIdHex);
  Future<bool> setMemberRole(String groupIdHex, String memberNodeIdHex, String role);
  void Function(String groupIdHex, String groupName)? onGroupInviteReceived;

  // Channels
  Map<String, ChannelInfo> get channels;
  Future<String?> createChannel(String name, List<String> subscriberNodeIdHexList, {
    bool isPublic = false,
    bool isAdult = true,
    String language = 'de',
    String category = 'general',
    String? description,
    String? pictureBase64,
  });
  Future<UiMessage?> sendChannelPost(String channelIdHex, String text);

  /// §9.5.3 D3 (S119): Feature-Request submission — SystemChannelRecord
  /// with embedded auto-poll + implicit "Ja" vote of the submitter.
  Future<UiMessage?> submitFeatureRequest(String title, String body);

  /// §9.5.3 D3: open vote record on an FR post (0="Ja" (yes), 1="Nein" (no), 2="Egal" (don't care)).
  /// LWW per author — voting again changes the vote.
  Future<bool> voteFeatureRequest(String recordIdHex, int option);

  /// §9.5.3 D3: local tally over the open vote records. Keys: `ja`,
  /// `nein`, `egal`, `net`, `own` (-1 when the caller has not voted).
  Future<Map<String, int>> featureRequestTally(String recordIdHex);

  Future<bool> leaveChannel(String channelIdHex);
  Future<bool> inviteToChannel(String channelIdHex, String memberNodeIdHex);
  Future<bool> removeFromChannel(String channelIdHex, String memberNodeIdHex);
  Future<bool> setChannelRole(String channelIdHex, String memberNodeIdHex, String role);
  void Function(String channelIdHex, String channelName)? onChannelInviteReceived;

  // Public channel search & moderation
  Future<List<ChannelIndexEntry>> searchPublicChannels({String? query, String? language, bool? includeAdult});
  Future<bool> publishChannelToIndex(String channelIdHex);
  Future<bool> joinPublicChannel(String channelIdHex);
  Future<bool> reportChannel(String channelIdHex, int category, List<String> evidencePostIds, {String? description});
  Future<bool> reportPost(String channelIdHex, String postId, int category, {String? description});
  Future<bool> submitJuryVote(String juryId, String reportId, int vote, {String? reason});
  List<JuryRequest> get pendingJuryRequests;
  /// AP-5a: async because on daemon platforms this crosses the IPC boundary.
  /// A synchronous signature forced `IpcClient` to answer `{}` forever.
  Future<Map<String, dynamic>> getChannelModerationInfo(String channelIdHex);
  Future<bool> dismissPostReport(String channelIdHex, String reportId);
  Future<bool> submitBadgeCorrection(String channelIdHex, {String? newName, String? newDescription});
  Future<bool> contestCsamHide(String channelIdHex);
  void Function(JuryRequest request)? onJuryRequestReceived;

  // Call state
  CallInfo? get currentCall;
  void Function(CallInfo call)? onIncomingCall;
  void Function(CallInfo call)? onCallAccepted;
  void Function(CallInfo call, String reason)? onCallRejected;
  void Function(CallInfo call)? onCallEnded;

  // Actions
  Future<UiMessage?> sendTextMessage(String recipientUserIdHex, String text, {String? replyToMessageId, String? replyToText, String? replyToSender});
  /// Submits a file into a chat.
  ///
  /// NO `secureChoice` ANYMORE (S389). The parameter carried the answer of the
  /// consent dialog — "send in Secure mode" or "switch to Speed for this
  /// file". That is a choice of the send path per transfer,
  /// and §12.1 allows none: "The interface offers no delivery-mode
  /// control." Its only producer was moreover the switch that
  /// fell with the same change.
  ///
  /// What §24.4.5 still demands at this place — a consent
  /// per transfer that does NOT choose between two paths but names the
  /// consequences of ONE — is recorded as finding B-M2 in
  /// `mycelium/berichte/S389-BAU-MODUS.md`.
  Future<UiMessage?> sendMediaMessage(String conversationId, String filePath);
  Future<bool> acceptMediaDownload(String conversationId, String messageId);
  Future<bool> editMessage(String conversationId, String messageId, String newText);
  Future<bool> deleteMessage(String conversationId, String messageId);

  // `checkExpiredMessages` stood here. Fell with S390: §9.3 —
  // "There is no timer that expires messages and no background retry
  // loop." A message stays `inTransit` until a receipt arrives
  // or the user gives up.

  /// §9.3: resend a given-up message ([MessageStatus.failed])
  /// — the one user action §12.2 offers at all.
  ///
  /// The retry gets a new identifier; the old entry
  /// stays `failed` and is removed from the conversation.
  Future<UiMessage?> resendFailedMessage(String conversationId, String messageId);
  Future<void> sendReaction({required String conversationId, required String messageId, required String emoji, required bool remove});
  Future<bool> updateChatConfig(String conversationId, ChatConfig config);
  void updateConversationNotifications(String conversationId, {bool? enabled, String? soundName});
  Future<bool> acceptConfigProposal(String conversationId);
  Future<bool> rejectConfigProposal(String conversationId);
  Future<UiMessage?> forwardMessage(String sourceConversationId, String messageId, String targetConversationId);
  void markConversationRead(String conversationId);

  /// Loads the history of a conversation lazily (S366, stage B).
  ///
  /// After start a conversation carries only its YOUNGEST message —
  /// it is the preview in the list. Whoever displays or
  /// searches the history calls this first; the second call does nothing.
  ///
  /// **In the service the call takes effect immediately** (the store is right beside it),
  /// **in the GUI client it only triggers** — there the history lives at the
  /// other end of a socket, and the UI redraws as soon as
  /// it is there. Whoever definitely needs it takes
  /// `IpcClient.ensureLoadedAsync` on the client.
  void ensureLoaded(String conversationId);

  /// Loads the history of ALL conversations.
  ///
  /// Only for the few operations that really need the whole stock
  /// — the archive run searches by age, the
  /// restore answer carries the history. **Not as a convenient
  /// substitute for [ensureLoaded]:** here the memory peak comes back
  /// against which stage B was built.
  void ensureAllLoaded();
  /// Track which conversation the user is currently viewing in the foreground.
  /// Used to suppress in-app notifications for messages in the active chat.
  /// Pass null when no chat is open.
  void setActiveConversationId(String? conversationId);
  /// Track whether the app is in the foreground (AppLifecycleState.resumed).
  /// Combined with setActiveConversationId to gate notification suppression.
  /// [triggerNodeHarvest] (default `true`): on the edge
  /// "was in the background, is now in front" additionally triggers the catch-up harvest of the
  /// NODE (§22.6, variant C). A caller that calls this method in
  /// a loop over several identities passes `false` and
  /// runs the node part itself exactly once — otherwise the one
  /// node harvests N times for a single event (S376, P5 finding 5).
  /// The same separation as [triggerNodeReset] in [onNetworkChanged].
  void setAppResumed(bool isResumed, {bool triggerNodeHarvest = true});
  void sendTypingIndicator(String conversationId);
  void toggleFavorite(String conversationId);
  Future<bool> setProfilePicture(String? base64Jpeg);
  String? get profilePictureBase64;
  void updateDisplayName(String newName);
  // `sendContactRequest` was dropped (S388-BAU-KONTAKT): on V4.2 the
  // contact request is packet (2) of the first contact in mycelium and is created when
  // redeeming a card ([redeemInvitationText],
  // [redeemInvitationCardBytes], §15.5).

  /// Issues an invitation and returns what a ContactSeed
  /// needs of it: class, deadline and `K_inv(i)` (§15.3, §15.5).
  ///
  /// ── WHY THIS IS ON THE INTERFACE AND NOT ONLY ON THE SERVICE ──
  ///
  /// Until S380 `contact_share_card` called `svc.issueInvitation(...)` on
  /// an `is CleonaService` downcast. That only works **in-process**
  /// (Android/iOS). On every daemon platform — Linux, Windows, macOS —
  /// the UI talks via IPC, the downcast yielded `null`, and
  /// instead of the selection the card showed the sentence "this view is
  /// connected to a background service and shows the code without
  /// invitation".
  ///
  /// **Consequence, measured in the field on 10.09.2026:** the ContactSeed of these
  /// platforms never carried `ki`, and the then `sendContactRequest` rejected
  /// every first request after 9 ms — "the ContactSeed carries no
  /// invitation key `ki` (§15.5) … ki=false". **On the desktop
  /// no first contact was thus possible**, on any path. (S389: the path has been
  /// dropped since S388-BAU-KONTAKT; the first request today comes from
  /// the invitation card, §15.5.)
  ///
  /// ── WHO MAY ISSUE STAYS UNCHANGED (§15.3) ──────────────────────────
  ///
  /// "Invitations can only be issued by the device that holds the
  /// identity." Exactly that still happens: the call is executed IN THE DAEMON.
  /// It holds the master seed (`service_daemon.dart:671`),
  /// it keeps the invitation book, and it is the one that harvests the invitation line
  /// (§15.3.2) — an invitation created in the UI would have
  /// no harvester. The UI is the front part of the same device;
  /// the path there is the same 0600 Unix socket (Windows: TCP +
  /// token) over which seed dialog, messages and contact data already
  /// run. The trust boundary does not move as a result.
  ///
  /// ── THE REASON TRAVELS ALONG (S381, 11.09.2026) ────────────────────
  ///
  /// Until S381 this said: "`null` means: not issued — cap
  /// reached (§15.3.4), book unreadable (§21.4) or no master seed for
  /// this identity (§15.3.1). **The reason is in the issuer's
  /// log.**" Exactly this last sentence was the defect: the
  /// UI cannot read a log, so it GUESSED the most frequent
  /// reason. But §15.3.1 demands that the UI NAMES the consequence.
  ///
  /// The result therefore carries the reason as a value. Reasoning and the
  /// four branches: `invite_issue_refusal.dart`.
  Future<InviteIssueResult> issueInviteForSharing({
    required String inviteClassCode,
    Duration? validity,
    bool singleUse = false,
    String label = 'qr-card',
  });

  /// The open invitations of this identity (§15.3.2).
  ///
  /// Needed because the cap was a dead end: the message
  /// "Revoke one before you create a new one" pointed to a path
  /// that did not exist. Throws if the book is there and unreadable
  /// (§21.4) — an empty list would there be the false statement "you have
  /// no open invitations".
  Future<List<OpenInvitation>> listOpenInvitations({DateTime? now});

  /// §15.3.3: revoke an open invitation. `false` if it does
  /// not exist or was already revoked.
  Future<bool> revokeInvitation(int index, {DateTime? now});

  // ── V4.2 invitation card (§15.2, §15.3, §15.6) — S387 ────────────────
  //
  // Contract with the seam: `mycelium/berichte/S387-API-KARTE.md`. The
  // UI calls only these six; the V4.1 invitation methods above
  // stay until the seam replaces them.

  /// Issues a card for the ACTIVE identity (§15.2, §15.3).
  /// [validity] `null` = default of the kind ([InvitationValidity.defaultFor]).
  /// The card needs no network (§12.4) — a refusal names its reason.
  /// [faceToFace]: for personal handover (QR shown, NFC) —
  /// a request on it is accepted without a second question (§15.5); only for
  /// [InvitationKind.single], and the card then carries no text line.
  Future<InvitationIssueResult> issueInvitationCard({
    InvitationKind kind = InvitationKind.single,
    InvitationValidity? validity,
    String label = '',
    bool faceToFace = false,
  });

  /// Redeems a pasted or shared invitation text (§15.6)
  /// and sends the contact request. Read error, foreign channel and
  /// expiry come back as [InvitationRedeemOutcome.readError] before
  /// a packet goes out (§15.2, §15.3).
  Future<InvitationRedeemResult> redeemInvitationText(String text);

  /// Like [redeemInvitationText], for the packed card from a
  /// QR code (binary form) or NFC record (§15.2).
  Future<InvitationRedeemResult> redeemInvitationCardBytes(Uint8List packed);

  /// The standing invitations of this identity (§15.3). `items == null`
  /// means unreadable, not empty.
  Future<StandingInvitationsResult> standingInvitations();

  /// §15.3: revoke a standing invitation.
  Future<InvitationRevokeOutcome> revokeInvitationCard(String invitationId);

  /// §15.3 "Bulk revocation": all standing invitations at once.
  Future<InvitationRevokeAllResult> revokeAllInvitationCards();

  /// §8.1.1 rev3: pass [targetDeviceIdHex] + Device-KEM-PKs (v1 legacy) or
  /// [targetEpB64] (v2 trust-anchor) from a ContactSeed so the seeded peer
  /// is keyed by Device-Node-ID and a direct DV-route is registered.
  /// [targetRendezvousNonceB64] (§4.11.10): the URI's `r` nonce — since S388
  /// without effect (first-contact rendezvous removed); falls with the
  /// V3 ContactSeed reader.
  void addPeersFromContactSeed(
    String targetNodeIdHex,
    List<String> targetAddresses,
    List<({String nodeIdHex, List<String> addresses})> seedPeers, {
    String? targetDeviceIdHex,
    String? targetDxkB64,
    String? targetDmkB64,
    String? targetEpB64,
    String? targetRendezvousNonceB64,
  });
  bool addManualPeer(String ip, int port);
  Future<bool> acceptContactRequest(String nodeIdHex);
  void deleteContact(String nodeIdHex, {required String source});
  void renameContact(String nodeIdHex, String? localAlias);

  /// §14.7.4: withhold this node's delivery status from a contact or group.
  /// Returns false when [entityIdHex] is neither (e.g. a channel).
  bool setWithholdDeliveryStatus(String entityIdHex, bool withhold);

  // NO SETTER FOR A SEND MODE. Until S389 this held
  // `setSecureMode` — the write side of the switch from the
  // chat settings dialog. §12.1: "The interface offers no
  // delivery-mode control … No per-chat setting, no explanatory dialog,
  // no switch." There is ONE way to send (§3.3); a verb with which the
  // UI chooses a second one therefore cannot exist.

  /// Set/clear a contact's birthday (local metadata only, never broadcast).
  /// Pass null for all three to clear. Triggers calendar birthday re-sync.
  bool setContactBirthday(String nodeIdHex, {int? month, int? day, int? year});

  /// §15.10 (D2 = a): mark a contact so that it never takes a fixed
  /// neighbour seat (§5.2). A property of the contact, not a send mode
  /// (§3.3); local, never distributed. Returns false for an unknown contact.
  bool setContactNeverFixedNeighbour(String nodeIdHex, bool never);
  void acceptContactNameChange(String nodeIdHex, bool accept);

  // Group Call state
  GroupCallInfo? get currentGroupCall;
  void Function(GroupCallInfo info)? onIncomingGroupCall;
  void Function(GroupCallInfo info)? onGroupCallStarted;
  void Function(GroupCallInfo info)? onGroupCallEnded;

  // Group Call actions
  Future<GroupCallInfo?> startGroupCall(String groupIdHex);
  Future<void> acceptGroupCall();
  Future<void> rejectGroupCall({String reason = 'busy'});
  Future<void> leaveGroupCall();

  // Call actions
  Future<CallInfo?> startCall(String peerNodeIdHex, {bool video = false});
  Future<void> acceptCall();
  Future<void> rejectCall({String reason = 'busy'});
  Future<void> hangup();
  bool get isMuted;
  void toggleMute();
  bool get isSpeakerEnabled;
  void toggleSpeaker();

  // 1:1 video call actions (§ F-B). Pause/resume is functional wherever a
  // video engine is running (including Linux's gray-frame isolate capture);
  // switchCamera is Android-only today and returns false elsewhere.
  bool get isVideoMuted;
  void toggleVideoMute();
  Future<bool> switchCamera();

  // Recovery
  void Function(int phase, int contactsRestored, int messagesRestored)? onRestoreProgress;
  Future<bool> sendRestoreBroadcast({
    required Uint8List oldEd25519Sk,
    required Uint8List oldEd25519Pk,
    required Uint8List oldNodeId,
    required List<ContactInfo> oldContacts,
  });

  // Network statistics
  NetworkStats getNetworkStats();

  // Contact issue reporting
  Future<ContactIssueReport?> buildContactIssueReport(String contactNodeIdHex);
  Future<bool> publishContactIssueReport(String contactNodeIdHex);

  // Manual log report (Bug Log)
  //
  // S368: WAS SYNCHRONOUS, and exactly that broke the user's
  // consent. On desktop the implementation of this interface is the
  // IPC bridge; it cannot fetch anything synchronously over the socket and therefore
  // delivered an EMPTY report (version '', log excerpt '', 0 peers). The
  // preview dialog showed this empty report, but what was published was
  // the REAL one from the daemon. The user consented to something other than
  // what was sent. A Future forces every implementation to obtain the real
  // report — or to throw.
  Future<LogReport> buildLogReport();
  Future<bool> publishLogReport();

  // ── NAT-Troubleshooting-Wizard (§27.9) ─────────────────────────────
  /// Fired when the 10-min trigger (0 direct + UPnP fail + PCP fail +
  /// no CGNAT + not dismissed) has been satisfied and the dialog should
  /// be shown. Fires at most once per daemon run per identity.
  void Function()? onNatWizardTriggered;
  /// Fired when the user explicitly requested the wizard via the
  /// connection-status icon tap. Distinct from [onNatWizardTriggered] so
  /// the GUI can bypass the auto-trigger one-shot latch — a deliberate
  /// user tap is always allowed to re-open the dialog, regardless of how
  /// many times the wizard has already shown this session.
  void Function()? onNatWizardUserRequested;
  /// Dismiss the wizard. [durationSeconds] = 0 means forever (never again),
  /// any positive value delays re-trigger by that many seconds (typically
  /// 7 days = 604800).
  Future<void> dismissNatWizard({required int durationSeconds});
  /// Searches the port mapping anew (UPnP/IGD + NAT-PMP/PCP) and observes
  /// for 30 s whether an INBOUND sync partner comes about. §27.9.2
  /// step 3, the button "Check now".
  ///
  /// The return value is the observation, not the mapping: §25.4
  /// lists inbound sync partners as "a precondition for inbound calls
  /// (§17)" — i.e. exactly "does someone reach me from outside", and that is
  /// the question a port forwarding answers. The new search runs
  /// alongside; it can take longer than the observation window.
  ///
  /// UNTIL S373 THIS SAID "Re-run UPnP discovery + hole-punch round". The
  /// sentence was outdated between the CUT (31.08.2026) and 07.09.: the
  /// implementation only observed. Both are back now.
  Future<bool> recheckNatWizard();
  /// Test-only (E2E gui-53): fire [onNatWizardTriggered] directly, bypassing
  /// the 10-min uptime gate, network-condition checks, and the dismissed-flag
  /// in §27.9.1. DOES NOT clear the dismissed flag — the GUI-side latch is
  /// still expected to suppress repeated shows. Use
  /// [testResetNatWizardDismissed] to reset the persistent dismiss window.
  void testForceNatWizardTrigger();
  /// Test-only (E2E gui-53): clear the persistent `nat_wizard_dismissed_until`
  /// flag so the next trigger can re-fire. Pairs with the GUI-level reset
  /// `gui_action('reset_nat_wizard_latch')` invoked from the test harness.
  void testResetNatWizardDismissed();

  // §7.1 Linked-Device Pairing
  void Function(String requestingDeviceIdHex)? onDevicePairRequest;
  bool get isLinkedDevice;
  LinkedDeviceStatus get linkedDeviceStatus;
  Future<bool> sendDevicePairRequest();
  Future<bool> requestDelegationRenewal();

  /// §7.1 LD-2: the user (on this, the Primary, device) approved a pending
  /// pairing request. Derives delegation keys and sends
  /// `MTV3_DEVICE_PAIR_APPROVE` to the requester. False if `deviceIdHex` is
  /// not (or no longer) a pending request.
  ///
  /// The caller MUST have shown `deviceIdHex` to the user in plain text and
  /// obtained an explicit approval first (§7.1 step 2) — there is no
  /// reject counterpart: declining is simply not calling this, and the
  /// request either sits in [getPendingPairRequests] until the requester
  /// retries, or ages out of that catch-up view (see its doc).
  Future<bool> approvePairRequest(String requestingDeviceIdHex);

  /// §7.1 LD-2: the pairing requests currently awaiting a decision on this
  /// (Primary) device, oldest first.
  ///
  /// Analogous to [getPendingRotationApprovals] (§7.5): [onDevicePairRequest]
  /// is a fire-and-forget event, so a GUI that is not running (or not yet
  /// connected) when the request arrives never sees it. Unlike §7.5,
  /// nothing here is a security-authoritative deadline —
  /// [approvePairRequest] keeps working on an entry after it drops out of
  /// this list, and the requesting device can simply ask again (§7.1 LD-9
  /// already overwrites the pending entry on retry, resetting the clock
  /// below). The cutoff exists only to stop the GUI from presenting a
  /// long-forgotten request as if it just arrived — which is exactly the
  /// condition under which a user approves without actually performing the
  /// device-ID comparison §7.1 step 2 depends on.
  ///
  /// Each entry is a plain JSON-serializable map with these keys:
  ///   * `deviceIdHex`   (String) — pass this to [approvePairRequest]; it is
  ///                     also the value the user must compare in plain text
  ///                     against the requesting device before approving.
  ///   * `receivedAtMs`  (int)    — arrival time, epoch milliseconds.
  ///   * `expiresAtMs`   (int)    — epoch milliseconds after which the entry
  ///                     stops being returned here (display cutoff, not a
  ///                     security boundary — see above).
  Future<List<Map<String, dynamic>>> getPendingPairRequests();

  // Guardian Recovery (Shamir SSS)
  Future<bool> setupGuardians(List<String> guardianNodeIds);
  Future<Map<String, dynamic>?> triggerGuardianRestore(String contactNodeIdHex);
  bool get isGuardianSetUp;
  void Function(String ownerName, String triggeringGuardianName, String ownerNodeIdHex, String recoveryMailboxIdHex)? onGuardianRestoreRequest;
  Future<bool> confirmGuardianRestore(String ownerNodeIdHex, String recoveryMailboxIdHex);

  // Profile description
  String? get profileDescription;
  Future<bool> setProfileDescription(String? description);

  // Media settings
  MediaSettings get mediaSettings;
  void updateMediaSettings(MediaSettings settings);

  // Link preview settings
  LinkPreviewSettings get linkPreviewSettings;
  void updateLinkPreviewSettings(LinkPreviewSettings settings);

  // Multi-interface send (Architecture §23.2)
  MultiInterfaceMode get multiInterfaceMode;
  Future<void> setMultiInterfaceMode(MultiInterfaceMode mode);

  bool get serveBinaryUpdates => true;

  /// Generate an invite link URL for sharing the app (§19.6.4).
  /// Returns the full `http://<public-ip>:<port>/cleona#...` URL with
  /// per-platform hashes and maintainer signatures from the UpdateManifest,
  /// or null if no public IP or no manifest is available yet.
  /// AP-5a: async because on daemon platforms this crosses the IPC boundary.
  /// A synchronous signature forced `IpcClient` to answer `null` forever,
  /// which hid the whole invite block in `share_cleona_dialog.dart`.
  Future<String?> generateInviteLinkUrl();

  // NFC Contact Exchange: crypto keys + sign/verify
  Uint8List? get ed25519PublicKey;
  Uint8List? get mlDsaPublicKey;
  Uint8List? get x25519PublicKey;
  Uint8List? get mlKemPublicKey;
  Uint8List? get profilePicture;
  Uint8List signEd25519(Uint8List message);
  bool verifyEd25519(Uint8List message, Uint8List signature, Uint8List publicKey);
  // `addNfcContact` was dropped (S388-BAU-KONTAKT): the NFC screen exchanges
  // invitation cards and redeems them (§15.5, §15.10) instead of creating a contact
  // without a request.

  // Notification sounds
  NotificationSoundService get notificationSound;

  // Multi-Device (§26)
  List<DeviceRecord> get devices;
  String get localDeviceId;

  /// §24.4.3 — the transition state of a device lock, for the display.
  ///
  /// A lock does not take effect immediately, but per contact — namely as soon as
  /// this contact has harvested the announcement (§14.6). §24.4.3 demands
  /// for this the parameterised sentence "Device locked — fully in effect once all
  /// contacts are informed (3 of 47 still open)" and adds that the
  /// transition "belongs in the UI, not in a footnote". Until here there was
  /// only the data side (`DeviceLockoutOps.deviceLockoutStates()`,
  /// cleona_service_lockout.dart:464) — tree-wide without a single
  /// consumer. The numbers were kept, the UI never saw them.
  ///
  /// **Abstract, not an extension getter.** [isReady] may be an extension
  /// on [ICleonaService] because there is nothing to transfer there: the
  /// value is derived from `readinessState`, and a second derivation
  /// would be the same calculation twice. Here it is the other way round — there are TWO
  /// real sources: the daemon computes from `_lockouts`, the GUI only has the
  /// snapshot. An extension could serve only one of the two
  /// and would have to guess the other.
  ///
  /// **The name is deliberately not `deviceLockoutStates`.** A class member
  /// of this name would shadow the extension method of the same name on
  /// `CleonaService` (class members take precedence over
  /// extension members), and `service.deviceLockoutStates()` in
  /// `test/smoke/smoke_device_lockout_transition.dart` would then be read as a call
  /// of the getter's result. The getter is therefore called
  /// `deviceLockouts` and forwards to the extension.
  ///
  /// As `List<Map<String, dynamic>>` and not as a type: the value crosses a
  /// JSON boundary, and `LockoutTransition` lives in a `part` of
  /// `cleona_service.dart` — the IPC client would have to import the service
  /// to name it, and that is the dependency direction the wrong way round.
  ///
  /// Keys per entry: `deviceId`, `deviceName`, `startedAtMs`,
  /// `deadlineMs`, `total`, `stillOpen`, `notSent`, `closed`; plus
  /// `closedAtMs` and `closeReason` (`allInformed` or `deadline`) as soon as
  /// the transition is closed.
  List<Map<String, dynamic>> get deviceLockouts;
  void renameDevice(String deviceId, String newName);
  Future<bool> revokeDevice(String deviceId);
  Future<void> rotateIdentityKeys();
  void injectTestDevice(String deviceId, String name, String platform);
  /// Test-only (E2E gui-52): snapshot of §26.6.2 package C retry-manager state.
  Map<String, dynamic> testGetKeyRotationRetryState();
  /// Test-only (E2E gui-52): bypass the 24h retry-interval and force a retry
  /// of all pending contacts now.
  void testForceKeyRotationRetry();

  // Calendar (§23)
  CalendarManager get calendarManager;
  IdentityContext get identity;
  /// Create a calendar event (local CRUD + group invite if applicable).
  Future<String> createCalendarEvent(CalendarEvent event);
  /// Update a calendar event (local CRUD + group update if applicable).
  Future<bool> updateCalendarEvent(String eventIdHex, {
    String? title, String? description, String? location,
    int? startTime, int? endTime, bool? allDay, bool? hasCall,
    List<int>? reminders, String? recurrenceRule,
    bool? taskCompleted, int? taskPriority, bool? cancelled,
    List<String>? attendeeNodeIds,
  });
  /// Delete a calendar event (local CRUD + group delete if applicable).
  Future<bool> deleteCalendarEvent(String eventIdHex);
  Future<void> sendCalendarInvite(CalendarEvent event);
  Future<void> sendCalendarRsvp(String eventIdHex, RsvpStatus status, {int? proposedStart, int? proposedEnd, String? comment});
  Future<void> sendCalendarUpdate(String eventIdHex);
  Future<void> sendCalendarDelete(String eventIdHex);
  Future<String> sendFreeBusyRequest(String contactNodeIdHex, int queryStart, int queryEnd);

  // Polls (§24)
  PollManager get pollManager;
  /// Poll received by a member/subscriber.
  void Function(String pollId, String groupId, String question)? onPollCreated;
  /// Vote tally changed (incoming vote, snapshot, or close).
  void Function(String pollId)? onPollTallyUpdated;
  /// Poll closed/reopened/deleted/updated.
  void Function(String pollId)? onPollStateChanged;
  /// Create a poll locally and fan it out to the group/channel.
  Future<String> createPoll({
    required String question,
    String description,
    required PollType pollType,
    required List<PollOption> options,
    required PollSettings settings,
    required String groupIdHex,
  });
  /// Submit the caller's vote (non-anonymous).
  Future<bool> submitPollVote({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  });
  /// Submit an anonymous vote via linkable ring signature (§24.4).
  Future<bool> submitPollVoteAnonymous({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  });
  /// Revoke the caller's anonymous vote so a new anonymous vote can be cast.
  Future<bool> revokePollVoteAnonymous(String pollId);
  /// Close, reopen, add/remove options, extend deadline, or delete a poll.
  Future<bool> updatePoll(String pollId, {
    bool? close,
    bool? reopen,
    List<PollOption>? addOptions,
    List<int>? removeOptions,
    int? newDeadline,
    bool delete,
  });
  /// Convert the winning slot of a DATE poll to a calendar event (§24.5).
  Future<String?> convertDatePollToEvent(String pollId, int winningOptionId);

  /// §26.6.2 package C: fired when an emergency-key-rotation retry gives up on
  /// a contact (either max attempts reached or the 90d window expired). The
  /// contact is flagged, not removed — the UI should warn the user.
  /// Second argument is the remaining pending count.
  void Function(String contactNodeIdHex, int pendingCount)?
      onKeyRotationPendingExpired;

  /// SR-1 (§7.4b step 6 / §8.3): fired when an accepted emergency key
  /// rotation from a contact reset that contact's verification level —
  /// the UI must surface the key-change warning so a soft re-key is never
  /// followed silently (a valid rotation chain does not prove the rotation
  /// was authorized by the legitimate owner vs. a seed-holding thief).
  /// Args: contact userId hex, display name, whether the level was reset
  /// from a previously verified/trusted state.
  void Function(
          String contactNodeIdHex, String displayName, bool wasVerified)?
      onContactIdentityRotated;

  /// §7.5: fired when a KEY_ROTATION_BROADCAST is received from a multi-device
  /// contact but the Device-Sig countersig quorum is NOT met. This is the
  /// elevated "possible Primary theft" warning — the standard key-change
  /// warning fires regardless via [onContactIdentityRotated].
  void Function(String contactNodeIdHex, String displayName,
      int tokensPresent, int tokensRequired)? onRotationCoAuthWarning;

  /// §7.5: fired when a Linked Device actively rejects a rotation via
  /// MTV3_ROTATION_REJECTION_ALERT. Strongest possible theft signal.
  void Function(String contactNodeIdHex, String displayName)?
      onRotationRejectionAlert;

  /// §7.5: fired on a Linked Device when the Primary requests a Device-Sig
  /// countersignature. The UI MUST ask the user and then call
  /// [approveRotation] or [rejectRotation] with the same `rotationHashHex`.
  /// Without a decision the daemon sends NOTHING — a timeout is neither
  /// approval nor rejection (silence is not consent).
  ///
  /// [kind] says what is actually being asked and MUST be reflected in the
  /// dialog text — see [RotationApprovalKind]. For
  /// [RotationApprovalKind.deviceSetChange] the last argument lists the
  /// device node ids (hex) that remain after the change, so the dialog can
  /// name what disappears; it is empty for a key rotation.
  ///
  /// Args: hash hex, requesting device-id hex, occasion, remaining device
  /// node ids (hex).
  void Function(String rotationHashHex, String requestingDeviceIdHex,
          RotationApprovalKind kind, List<String> newDeviceNodeIdHexes)?
      onRotationApprovalRequest;

  /// §7.5: user approved the pending rotation — creates and sends the
  /// Device-Sig countersignature. False if the hash is unknown or expired.
  Future<bool> approveRotation(String rotationHashHex);

  /// §7.5 point 5: user rejected the pending rotation — answers
  /// `rejected=true` and alerts the contacts directly (bypassing the possibly
  /// compromised Primary). False if the hash is unknown or expired.
  Future<bool> rejectRotation(String rotationHashHex);

  /// §7.5: the rotation-approval requests currently awaiting a user decision
  /// on this device, newest last.
  ///
  /// [onRotationApprovalRequest] is a fire-and-forget event: a GUI that is not
  /// running (or not yet connected) when the request arrives never sees it,
  /// and the request then expires unanswered without the user ever being
  /// asked. This getter is the catch-up path — call it once after connecting
  /// and render the result exactly like a live event.
  ///
  /// Entries whose TTL has already elapsed are never returned. Each entry is a
  /// plain JSON-serializable map with these keys:
  ///   * `rotationHashHex`       (String) — pass this to [approveRotation] /
  ///                             [rejectRotation]; it is also the identity of
  ///                             the request, so a live event and a catch-up
  ///                             entry for the same rotation de-duplicate on it.
  ///   * `requestingDeviceIdHex` (String) — device-node-id of the Primary that
  ///                             asked, same value the event carries.
  ///   * `approvalKind`          (String) — [RotationApprovalKind.wireName].
  ///                             The dialog MUST branch on this: a catch-up
  ///                             entry that renders every request as "approve
  ///                             key rotation?" asks for consent under a
  ///                             false description, which is exactly what the
  ///                             discriminator exists to prevent.
  ///   * `newDeviceNodeIdHexes`  (`List<String>`) — devices remaining after
  ///                             the change; only populated for
  ///                             `device_set_change`, empty otherwise.
  ///   * `receivedAtMs`          (int)    — arrival time, epoch milliseconds.
  ///   * `expiresAtMs`           (int)    — epoch milliseconds at which the
  ///                             entry is dropped. Nothing is sent on expiry —
  ///                             a countdown may be shown, but running out is
  ///                             not a rejection.
  Future<List<Map<String, dynamic>>> getPendingRotationApprovals();

  /// H-2 (§6.3.5): fired for every accepted Restore Broadcast — the
  /// "[Name] has set up a new device" notification. `identityKeyChanged`
  /// is true when the restore actually changed the contact's identity key
  /// (new-seed re-identity / forge attempt → verification was reset, §8.3),
  /// false for a deterministic same-seed recovery (keys unchanged).
  /// Args: contact userId hex (new), display name, identityKeyChanged.
  void Function(
          String contactNodeIdHex, String displayName, bool identityKeyChanged)?
      onContactRestoreDetected;

  /// [triggerNodeReset] (default `true`): forwards to `node.onNetworkChanged()`
  /// before running service-side cleanup (mailbox poll, identity-publisher
  /// re-publish). Daemon-style callers that already invoke `node.onNetworkChanged()`
  /// once for all identities should pass `false` to avoid the N+1 multiplication
  /// (one node-reset per identity on top of the direct one).
  // Media archive — share identity and narrowing (§21.6, S394). The
  // status map carries no secret: identity state, the pin SHORTENED, the
  // captured networks, and whether this platform reads the SSID for free.
  Future<Map<String, dynamic>?> getArchiveShareStatus();

  /// Forgets the share pin; the next run pins anew. Deletes nothing.
  Future<bool> rebindArchiveShare();

  /// Adds the network this device is in now to "only in this network";
  /// returns the captured entry or `null`.
  Future<Map<String, dynamic>?> captureArchiveNetwork();

  /// Removes the network narrowing.
  Future<bool> clearArchiveNetworks();

  // Peer Rescue Bundle (§8.1.2)
  Future<Map<String, dynamic>?> exportPeerBundle();
  Future<Map<String, dynamic>> importPeerBundle({String? uri, String? bundleBase64});

  Future<void> onNetworkChanged({bool triggerNodeReset = true});
  Future<void> stop();
}

/// §22.7.2 — the ONE predicate on which the functional gates hang.
///
/// **Why an extension and not a getter on the interface.**
/// §22.7.2 demands literally: "UI and service layer query the **same**
/// getter; two independent copies of the same gate are impermissible."
/// Exactly two copies existed until AP-5 — `contact_issue_reporter.dart:98`
/// (`_service.peerCount > 0`) and `contact_issue_dialog.dart:23`
/// (`service.peerCount > 0`): the same question, answered twice, and
/// both answers from an acquaintance count instead of from a
/// placement proof.
///
/// An abstract getter on [ICleonaService] would have brought the second copy
/// back, only one level deeper: `CleonaService` and `IpcClient`
/// implement the interface with `implements`, so they inherit
/// no body and would each have to write one. An extension
/// CANNOT be overridden — it is the only definition tree-wide,
/// and that is not convenience here, but the
/// assurance itself.
///
/// The comparison is deliberately against [kReadinessReady] and not against
/// a literal; the name equality with `Readiness.ready` is held by
/// `test/smoke/smoke_delivery_api.dart`.
extension ReadinessGate on ICleonaService {
  /// Whether placing with redundancy is possible (§22.7.1).
  bool get isReady => readinessState == kReadinessReady;
}

/// §24.4.2 — responses of [ICleonaService.setDataSaver].
///
/// As strings because the value crosses the JSON boundary of the IPC: an
/// enumeration would have to be mapped to a name there anyway,
/// and two mappings are one more than necessary.
const String kDataSaverOk = 'ok';

/// The latch has engaged: at least one chat is set to High-Secure.
const String kDataSaverLockedBySecure = 'locked_secure';
