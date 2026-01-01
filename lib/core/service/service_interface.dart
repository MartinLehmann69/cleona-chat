import 'dart:typed_data';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/network/network_stats.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/media/link_preview_fetcher.dart';
import 'package:cleona/core/services/contact_manager.dart' show Contact;
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/polls/poll_manager.dart';
import 'package:cleona/core/node/identity_context.dart';

/// Abstract interface for the Cleona service.
/// Both CleonaService (direct) and IpcClient (remote) implement this.
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
  int get peerCount;
  /// Peers with confirmed bidirectional UDP contact this session.
  /// Used for P2P-aware connection status icon.
  int get confirmedPeerCount;
  /// True if UPnP/PCP successfully opened an inbound port mapping OR an
  /// observed public address matches our port. Distinguishes "fully
  /// reachable (green Hulk)" from "behind-NAT outbound-only (yellow Hulk)".
  bool get hasPortMapping;
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

  List<ContactInfo> get acceptedContacts;
  List<ContactInfo> get pendingContacts;
  ContactInfo? getContact(String nodeIdHex);
  List<Conversation> get sortedConversations;
  List<PeerSummary> get peerSummaries;

  // Groups
  Map<String, GroupInfo> get groups;
  Future<String?> createGroup(String name, List<String> memberNodeIdHexList);
  Future<UiMessage?> sendGroupTextMessage(String groupIdHex, String text);
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
    String? description,
    String? pictureBase64,
  });
  Future<UiMessage?> sendChannelPost(String channelIdHex, String text);
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
  Map<String, dynamic> getChannelModerationInfo(String channelIdHex);
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
  Future<UiMessage?> sendTextMessage(String recipientNodeIdHex, String text, {String? replyToMessageId, String? replyToText, String? replyToSender});
  Future<UiMessage?> sendMediaMessage(String conversationId, String filePath);
  Future<bool> acceptMediaDownload(String conversationId, String messageId);
  Future<bool> editMessage(String conversationId, String messageId, String newText);
  Future<bool> deleteMessage(String conversationId, String messageId);
  Future<void> sendReaction({required String conversationId, required String messageId, required String emoji, required bool remove});
  Future<bool> updateChatConfig(String conversationId, ChatConfig config);
  Future<bool> acceptConfigProposal(String conversationId);
  Future<bool> rejectConfigProposal(String conversationId);
  Future<UiMessage?> forwardMessage(String sourceConversationId, String messageId, String targetConversationId);
  void markConversationRead(String conversationId);
  void sendTypingIndicator(String conversationId);
  void toggleFavorite(String conversationId);
  Future<bool> setProfilePicture(String? base64Jpeg);
  String? get profilePictureBase64;
  void updateDisplayName(String newName);
  Future<bool> sendContactRequest(String recipientNodeIdHex, {String message = ''});
  void addPeersFromContactSeed(String targetNodeIdHex, List<String> targetAddresses, List<({String nodeIdHex, List<String> addresses})> seedPeers);
  bool addManualPeer(String ip, int port);
  Future<bool> acceptContactRequest(String nodeIdHex);
  void deleteContact(String nodeIdHex);
  void renameContact(String nodeIdHex, String? localAlias);
  /// Set/clear a contact's birthday (local metadata only, never broadcast).
  /// Pass null for all three to clear. Triggers calendar birthday re-sync.
  bool setContactBirthday(String nodeIdHex, {int? month, int? day, int? year});
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
  /// Re-run UPnP discovery + hole-punch round + 30s direct-connection
  /// observation. Returns true when at least one direct connection was
  /// observed during the window (Step 3 "Jetzt pruefen" button). §27.9.2.
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

  // NFC Contact Exchange: crypto keys + sign/verify
  Uint8List? get ed25519PublicKey;
  Uint8List? get mlDsaPublicKey;
  Uint8List? get x25519PublicKey;
  Uint8List? get mlKemPublicKey;
  Uint8List? get profilePicture;
  Uint8List signEd25519(Uint8List message);
  bool verifyEd25519(Uint8List message, Uint8List signature, Uint8List publicKey);
  void addNfcContact(Contact contact);

  // Notification sounds
  NotificationSoundService get notificationSound;

  // Multi-Device (§26)
  List<DeviceRecord> get devices;
  String get localDeviceId;
  void renameDevice(String deviceId, String newName);
  Future<bool> revokeDevice(String deviceId);
  Future<void> rotateIdentityKeys();
  void injectTestDevice(String deviceId, String name, String platform);
  /// Test-only (E2E gui-52): snapshot of §26.6.2 Paket C retry-manager state.
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
    bool? taskCompleted, int? taskPriority,
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

  /// §26.6.2 Paket C: fired when an emergency-key-rotation retry gives up on
  /// a contact (either max attempts reached or the 90d window expired). The
  /// contact is flagged, not removed — the UI should warn the user.
  /// Second argument is the remaining pending count.
  void Function(String contactNodeIdHex, int pendingCount)?
      onKeyRotationPendingExpired;

  Future<void> onNetworkChanged();
  Future<void> stop();
}
