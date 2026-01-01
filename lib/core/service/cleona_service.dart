import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/pq_isolate.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/seed_phrase.dart';
import 'package:cleona/core/dht/channel_index.dart';
import 'package:cleona/core/dht/kbucket.dart' show RoutingTable;
import 'package:cleona/core/dht/mailbox_store.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/identity_resolution/device_delegation.dart';
import 'package:cleona/core/identity_resolution/rotation_co_auth.dart';
import 'package:cleona/core/identity_resolution/linked_device_keys.dart';
import 'package:cleona/core/identity_resolution/linked_device_keys_store.dart';
import 'package:cleona/core/identity_resolution/identity_publisher.dart';
import 'package:cleona/core/identity_resolution/identity_resolver.dart' show ResolvedDevice;
import 'package:cleona/core/identity_resolution/device_kem_record.dart';
import 'package:cleona/core/service/device_pairing_service.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/network/ack_tracker.dart';
import 'package:cleona/core/network/contact_seed.dart' show ContactSeedBuilder, ContactSeedDataSource;
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/lan_discovery.dart' show LocalDiscovery;
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/peer_message_store.dart';
import 'package:cleona/core/network/peer_rescue_bundle.dart';
import 'package:cleona/core/network/v3_frame_codec.dart';
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/erasure/erasure_placement.dart';
import 'package:cleona/core/erasure/reed_solomon.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/service_context.dart';
import 'package:cleona/core/service/channel_moderation_service.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/network/network_stats.dart';
import 'package:cleona/core/calls/call_manager.dart';
import 'package:cleona/core/calls/group_call_manager.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/service/guardian_service.dart';
import 'package:cleona/core/service/key_rotation_retry_manager.dart';
import 'package:cleona/core/service/nat_wizard_trigger.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/archive/voice_transcription_service.dart';
import 'package:cleona/core/archive/voice_transcription_config.dart';
import 'package:cleona/core/archive/voice_transcription_types.dart';
import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_manager.dart';
import 'package:cleona/core/archive/archive_transport.dart';
import 'package:cleona/core/update/update_manifest.dart';
import 'package:cleona/core/update/binary_fetch_client.dart';
import 'package:cleona/core/update/binary_fragment_store.dart';
import 'package:cleona/core/update/binary_http_server.dart';
import 'package:cleona/core/update/binary_update_manager.dart';
import 'package:cleona/core/update/bootstrap_web_app.dart';
import 'package:cleona/core/update/delta_update_manager.dart';
import 'package:cleona/core/update/invite_link_service.dart';
import 'package:cleona/core/update/physical_transfer_helper.dart';
import 'package:cleona/core/update/install_source.dart';
import 'package:cleona/core/update/binary_seeder.dart';
import 'package:cleona/core/network/rendezvous/binary_rendezvous_manager.dart';
import 'package:cleona/core/media/link_preview_fetcher.dart';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/sync/calendar_sync_service.dart';
import 'package:cleona/core/polls/poll_manager.dart';
import 'package:cleona/core/service/calendar_protocol_service.dart';
import 'package:cleona/core/service/poll_service.dart';
import 'package:cleona/core/service/call_service.dart';
import 'package:cleona/core/services/contact_manager.dart' show Contact;
import 'package:cleona/core/services/key_change_policy.dart';
import 'package:cleona/core/identity/identity_dht_registry.dart';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/channels/system_channel_records.dart';
import 'package:cleona/core/channels/contact_issue_reporter.dart';
import 'package:cleona/core/channels/crash_reporter.dart';
import 'package:cleona/core/network/rendezvous/first_contact_rendezvous_manager.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_manager.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart'
    show EndpointAddress;
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

// Re-export types so existing imports still work
export 'package:cleona/core/service/service_types.dart';

/// Outcome of [CleonaService.handleIncomingApplicationPacket]. Drives the
/// multi-identity dispatch loop in `service_daemon.onApplicationFramePayload`
/// (§2.4 step [9] try-loop, §3.1 daemon-global deviceID).
enum AppFrameDispatchOutcome {
  /// KEM-decap + sig-verify + handle all succeeded — no retry needed.
  delivered,

  /// KEM-decap with this identity's User-KEM-SK failed. The frame may be
  /// addressed to another hosted identity on this daemon — caller MUST try
  /// the remaining services.
  notForThisIdentity,

  /// KEM-decap succeeded (frame WAS for this identity) but a later step
  /// failed (sig invalid, sender pubkey miss, recipientUserId mismatch,
  /// parse error). No retry — drop is final.
  droppedAfterDecap,
}

/// MessageTypes eligible for the live-media receive fast path (Architecture
/// §10.3 / Appendix B.2, F-C amendment) — the strict allow-list a plaintext
/// ApplicationFrameV3 inner must fall into before
/// [CleonaService._tryLiveMediaFastPath] will dispatch it. Everything else
/// MUST go through the normal per-recipient-KEM + user-sig inner path.
const Set<proto.MessageTypeV3> _liveMediaFastPathTypes = {
  proto.MessageTypeV3.MTV3_CALL_AUDIO,
  proto.MessageTypeV3.MTV3_CALL_VIDEO,
  proto.MessageTypeV3.MTV3_CALL_GROUP_AUDIO,
  proto.MessageTypeV3.MTV3_CALL_GROUP_VIDEO,
};

/// Central orchestrator: wires node, contacts, messaging, and manages state.
/// Now takes a shared CleonaNode + IdentityContext instead of creating its own node.
class CleonaService implements ICleonaService, ContactSeedDataSource, ServiceContext {
  @override
  final String profileDir;
  @override
  String displayName;
  @override
  int port;
  final String networkChannel;
  final CLogger _log;

  late final ContactSeedBuilder _contactSeedBuilder = ContactSeedBuilder(this);
  @override
  ContactSeedBuilder get contactSeedBuilder => _contactSeedBuilder;

  /// The identity this service operates on behalf of.
  @override
  final IdentityContext identity;

  /// The shared network node (transport, routing, DHT).
  @override
  final CleonaNode node;

  late MailboxStore mailboxStore;
  late final CallService _calls;
  /// True once [_calls] has been assigned in [startService]. Guards the
  /// buffered call-video accessors below, which must be settable before
  /// startService runs (main.dart's `_wireServiceCallbacks` wires them
  /// ahead of `await service.startService()`).
  bool _callsReady = false;
  CallManager get callManager => _calls.callManager;
  GroupCallManager get groupCallManager => _calls.groupCallManager;
  // §2.2.4: per-identity Auth+Liveness Publisher. Eine pro CleonaService-Instanz
  // (Multi-Identity-Daemon hat N Services, sharing one CleonaNode).
  IdentityPublisher? _identityPublisher;
  /// Registered listener on the shared RoutingTable; wakes our publisher's
  /// parked cold-start retry as soon as a new peer joins.
  void Function(PeerInfo)? _publisherPeerAddedListener;
  @override
  final NotificationSoundService notificationSound = NotificationSoundService();

  /// Conversation the user is currently looking at (set by ChatScreen.initState,
  /// cleared on dispose). Used together with [_isAppResumed] to suppress
  /// in-app notifications for the active chat.
  String? _activeConversationId;
  /// Mirrors AppLifecycleState.resumed (set by main.dart's lifecycle observer).
  /// Defaults to true so the app behaves like „foreground" before the first
  /// lifecycle event arrives.
  bool _isAppResumed = true;

  /// True when the user has skipped the UpdateRequiredScreen into limited mode
  /// (sec-h5 §8.2 / T13). Per-session only — NOT persisted; every restart
  /// re-shows the splash.
  ///
  /// While active, [handleMessage] drops incoming user-message types and the
  /// public send-methods short-circuit before encrypting/transmitting any user
  /// payload. DHT participation, peer-list-push, presence, ACKs, contact
  /// establishment and call signaling are unaffected.
  bool _reducedMode = false;
  @override
  bool get reducedMode => _reducedMode;
  set reducedMode(bool v) {
    if (_reducedMode == v) return;
    _reducedMode = v;
    _log.warn('reducedMode = $v');
  }
  /// Wall-clock of the most recent fired notification per conversation.
  /// Used for the per-conv 2s debounce that protects against group-chat bursts.
  final Map<String, DateTime> _lastNotifiedAt = {};
  /// Maximum age (ms) of an incoming message that still triggers a notification.
  /// Older messages are treated as backlog (startup re-poll, daemon restart,
  /// store-and-forward catch-up) and only update the badge silently.
  static const int _notificationStaleThresholdMs = 30000;
  /// Minimum spacing (ms) between two notifications for the same conversation.
  static const int _notificationDebounceMs = 2000;

  /// Extracted moderation sub-service (§9.3 jury, §9.4 reports, channel index gossip).
  late final ChannelModerationService _moderation;
  @override
  ModerationConfig get moderationConfig => _moderation.moderationConfig;
  set moderationConfig(ModerationConfig value) {
    _moderation.moderationConfig = value;
  }

  /// Voice transcription service (whisper.cpp).
  VoiceTranscriptionService? _voiceTranscription;

  /// Public accessor for transcription service (used by settings UI).
  VoiceTranscriptionService? get voiceTranscriptionService => _voiceTranscription;

  /// Media auto-archive manager.
  ArchiveManager? _archiveManager;

  /// Public accessor for archive manager (used by settings UI + IPC).
  ArchiveManager? get archiveManager => _archiveManager;

  /// Inject platform-specific audio decoder (Android: MediaCodec).
  void setPlatformAudioDecoder(AudioDecoderCallback decoder) {
    _voiceTranscription?.platformAudioDecoder = decoder;
    _platformAudioDecoder = decoder;
  }
  AudioDecoderCallback? _platformAudioDecoder;

  // State
  @override
  final Map<String, Conversation> conversations = {};

  /// Receive-side dedup for V3 ApplicationFrame: bounded LRU keyed on
  /// inner.messageId-hex. Catches the same logical message arriving via
  /// multiple paths (Direct + Reed-Solomon reassembly + S&F mutual peer)
  /// and prevents double-dispatch / double-DELIVERY_RECEIPT-emit.
  /// Insertion order is preserved by `LinkedHashSet`; eviction is FIFO
  /// when the cap is reached.
  static const int _processedMessageIdsCap = 4096;
  final LinkedHashSet<String> _processedMessageIds = LinkedHashSet<String>();

  // Callbacks for GUI
  @override
  void Function()? onStateChanged;
  @override
  void Function(String conversationId, UiMessage message)? onNewMessage;
  @override
  void Function(String nodeIdHex, String displayName)? onContactRequestReceived;
  @override
  void Function(String nodeIdHex)? onContactAccepted;
  @override
  void Function(CallInfo call)? onIncomingCall;
  @override
  void Function(CallInfo call)? onCallAccepted;
  @override
  void Function(CallInfo call, String reason)? onCallRejected;
  @override
  void Function(CallInfo call)? onCallEnded;

  /// IPC push: immediate read-receipt notification (bypasses state_changed debounce).
  void Function(String conversationId, String messageId)? onReadReceiptReceived;

  /// Android: post a system notification for incoming messages (set by Flutter app).
  Future<void> Function(String title, String body, String conversationId)? onPostNotificationAndroid;

  /// Android: cancel notification when conversation is read (set by Flutter app).
  void Function(String conversationId)? onCancelNotificationAndroid;

  /// Badge count changed — update launcher badge / tray icon (set by Flutter app or daemon).
  void Function(int totalUnread)? onBadgeCountChanged;

  /// Android: post/cancel incoming call notification with fullScreenIntent.
  void Function(String callerName, String callId)? onPostCallNotificationAndroid;
  void Function()? onCancelCallNotificationAndroid;

  // Contact storage
  final Map<String, ContactInfo> _contacts = {};
  // Persistent deletion flag: prevents re-import of deleted contacts
  final Set<String> _deletedContacts = {};

  // Calendar (§23) — protocol layer delegated to CalendarProtocolService
  late final CalendarProtocolService _calendarProto;
  @override
  CalendarManager get calendarManager => _calendarProto.calendarManager;
  late CalendarSyncService calendarSyncService;

  void Function(String senderNodeIdHex, String eventId, String title)? onCalendarInviteReceived;
  void Function(String eventId, String responderNodeIdHex, RsvpStatus status)? onCalendarRsvpReceived;
  void Function(String eventId)? onCalendarEventUpdated;
  void Function(String eventId, String title, int minutesBefore)? onCalendarReminderDue;

  // Polls (§24) — delegated to PollService
  late final PollService _polls;

  // §4.11 External Rendezvous (Nostr cold-start address resolution)
  RendezvousManager? _rendezvousManager;

  // §4.11.10 First-Contact Rendezvous (URI-scoped, nonce from ContactSeed `r`)
  FirstContactRendezvousManager? _fcRendezvous;

  // §19.6 Censorship-Resistant Distribution: in-network binary updates.
  // Node-wide singletons — only the first identity's service on a daemon
  // wires these onto the shared node (same first-wins pattern as
  // node.rendezvousManager above).
  BinaryFragmentStore? _binaryFragmentStore;
  BinaryUpdateManager? _binaryUpdateManager;
  BinaryHttpServer? _binaryHttpServer;
  BinaryRendezvousManager? _binaryRendezvousManager;
  DeltaUpdateManager? _deltaUpdateManager;
  InviteLinkService? _inviteLinkService;
  PhysicalTransferHelper? _physicalTransferHelper;
  BinarySeeder? _binarySeeder;
  // §19.6.2 — periodic housekeeping on the fragment store (prunes
  // superseded versions + enforces the platform storage budget).
  Timer? _binaryGcTimer;
  // Fetches fragments/binaries from other nodes' embedded HTTP servers
  // (§19.6.6) — the `fetchFragment` callback for BinaryUpdateManager /
  // DeltaUpdateManager downloads.
  BinaryFetchClient? _binaryFetchClient;
  InviteLinkService? get inviteLinkService => _inviteLinkService;
  PhysicalTransferHelper? get physicalTransferHelper => _physicalTransferHelper;
  @override
  PollManager get pollManager => _polls.pollManager;
  @override
  void Function(String pollId, String groupId, String question)? onPollCreated;
  @override
  void Function(String pollId)? onPollTallyUpdated;
  @override
  void Function(String pollId)? onPollStateChanged;

  // §26.6.2 Paket C
  @override
  void Function(String contactNodeIdHex, int pendingCount)?
      onKeyRotationPendingExpired;

  // SR-1 (§7.4b step 6 / §8.3)
  @override
  void Function(
          String contactNodeIdHex, String displayName, bool wasVerified)?
      onContactIdentityRotated;

  // §7.5 Co-Auth warning callbacks
  @override
  void Function(String contactNodeIdHex, String displayName,
      int tokensPresent, int tokensRequired)? onRotationCoAuthWarning;
  @override
  void Function(String contactNodeIdHex, String displayName)?
      onRotationRejectionAlert;

  // H-2 (§6.3.5)
  @override
  void Function(
          String contactNodeIdHex, String displayName, bool identityKeyChanged)?
      onContactRestoreDetected;

  /// §26: fires whenever the twin-device list changes (add/remove/rename).
  /// GUI listens via IPC to refresh the Device Management screen.
  void Function()? onDevicesUpdated;

  /// §7.1 LD-2: fires when a new Linked-Device pairing request arrives.
  /// The GUI shows a confirmation dialog; on approval, call approvePairRequest().
  @override
  void Function(String requestingDeviceIdHex)? onDevicePairRequest;

  // Multi-Device (§26): twin device list + deduplication
  final Map<String, DeviceRecord> _devices = {};
  bool _devicesLoaded = false;
  late final String _localDeviceId; // UUID, generated once on first launch
  /// Rolling dedup window for TWIN_SYNC syncIds. Maps syncIdHex → firstSeen
  /// epoch-ms. Entries older than 7 days are garbage-collected on every save.
  final Map<String, int> _processedSyncIds = {};
  /// 7-day TTL for TWIN_SYNC dedup entries (matches S&F TTL per architecture).
  static const int _syncDedupTtlMs = 7 * 24 * 60 * 60 * 1000;
  // Key Rotation ACK tracking (§26.6.2, Paket C): per-contact retry state,
  // persisted, re-sends broadcast on 24h-tick until ACK or expiry.
  late final KeyRotationRetryManager _keyRotationRetry;
  // Guard: tracks whether each data type was successfully loaded from disk.
  // Prevents _save*() from overwriting existing data with empty maps
  // if _load*() failed (e.g. decryption error, missing key).
  bool _contactsLoaded = false;
  bool _conversationsLoaded = false;
  bool _groupsLoaded = false;
  bool _channelsLoaded = false;
  // Rate limiter: last CR retry time per contact (nodeIdHex -> timestamp)
  final Map<String, DateTime> _lastCrRetryPerContact = {};
  // Exponential backoff counter for CR retries to unreachable contacts.
  // Backoff: 10s, 20s, 40s, 80s, 160s, 320s, then capped at 600s (10min).
  // Keeps retrying forever so eventually-online contacts still get through,
  // but at low frequency after the initial burst (~10 attempts in 20min).
  final Map<String, int> _crRetryCountPerContact = {};
  // §8.1.1 rev3 step 1b: pending DEVICE_KEM_OFFER completers.
  // Per-contact last end-to-end-confirmed ACK (any message type).
  // Proves reachability to the contact — stops CR-Response retry flooding
  // on CGNAT peers where DELIVERY_RECEIPTs arrive only via relay and thus
  // never flip dvRouting's direct-only ackConfirmed flag.
  final Map<String, DateTime> _contactLastAckedAt = {};
  // Contacts for which the sender-side stale warning has already been written
  // into the conversation. Prevents duplicate warnings; cleared on the next
  // ACK (contact is alive) or re-acceptance.
  final Set<String> _staleWarningWrittenFor = {};
  // GM-2 (§9.1.4): track per-group last epoch for which a RESYNC_REQUEST was sent
  // to avoid flooding the owner. Key = groupIdHex, value = epoch that triggered it.
  final Map<String, int> _resyncRequestedAtEpoch = {};
  Timer? _keyRotationTimer;
  // §26.6.2 Paket C: drives _keyRotationRetry re-sends every 24h.
  Timer? _keyRotationRetryTimer;
  Timer? _expiryTimer;
  int _processedMsgIdsSaveCounter = 0;
  // §27.9 NAT-Troubleshooting-Wizard trigger + dismissal timestamp.
  NatWizardTrigger? _natWizardTrigger;
  // Unix-ms until which the NAT wizard is suppressed. 0 = never dismissed.
  // Persisted in nat_wizard_settings.json alongside the profile.
  int _natWizardDismissedUntilMs = 0;
  // Own profile picture (base64 JPEG, max 64KB)
  String? _profilePictureBase64;
  // Own profile description (max 500 chars)
  String? _profileDescription;
  // Media download settings (auto-download thresholds + download dir)
  MediaSettings _mediaSettings = MediaSettings();
  // Link preview settings + fetcher (sender-side)
  LinkPreviewSettings _linkPreviewSettings = LinkPreviewSettings();
  late LinkPreviewFetcher _linkPreviewFetcher;
  // Guardian service (Shamir SSS)
  late GuardianService guardianService;
  // Groups
  final Map<String, GroupInfo> _groups = {};
  /// Pending config updates for groups not yet known (arrive before GROUP_INVITE).
  final Map<String, ({ChatConfig config, String senderHex})> _pendingGroupConfigs = {};
  @override
  void Function(String groupIdHex, String groupName)? onGroupInviteReceived;

  // Channels
  final Map<String, ChannelInfo> _channels = {};
  @override
  void Function(String channelIdHex, String channelName)? onChannelInviteReceived;
  @override
  void Function(JuryRequest request)? onJuryRequestReceived;

  // Channel index (public channel discovery)
  late ChannelIndex _channelIndex;

  // System channels (§9.5)
  CrashReporter? _crashReporter;
  ContactIssueReporter? _contactIssueReporter;
  Timer? _systemChannelEvictionTimer;

  CrashReporter get crashReporter => _crashReporter ??= CrashReporter(this);
  ContactIssueReporter get contactIssueReporter =>
      _contactIssueReporter ??= ContactIssueReporter(this);

  // Guardian restore callback
  @override
  void Function(String ownerName, String triggeringGuardianName, String ownerNodeIdHex, String recoveryMailboxIdHex)? onGuardianRestoreRequest;

  // Update checking (Architecture Section 17.5.5)
  Timer? _updateCheckTimer;
  UpdateManifest? _latestManifest;
  /// Callback when a new version is available. UI should show banner/prompt.
  /// [inNetworkAvailable] is true when the update can additionally be
  /// fetched via §19.6 in-network binary distribution (not just the
  /// external `manifest.downloadUrl`).
  void Function(UpdateManifest manifest, bool inNetworkAvailable)? onUpdateAvailable;

  /// The current app version string. Single source of truth, also consumed
  /// by `lib/main.dart` for the Sec H-5 hard-block startup check (T13).
  static const String kCurrentAppVersion = '3.1.126';

  /// Backwards-compatible instance accessor.
  String get currentAppVersion => kCurrentAppVersion;

  // Recovery state
  @override
  void Function(int phase, int contactsRestored, int messagesRestored)? onRestoreProgress;
  DateTime? _lastRestoreBroadcast;
  Timer? _restoreRetryTimer;
  Timer? _restorePollingTimer;
  int _restorePollCount = 0;

  Timer? _postDiscoverySecondSweep;
  Timer? _delegationRenewalTimer;
  Timer? _crRetryTimer;
  final Set<String> _postDiscoveryPolledPeers = {};

  // §8.1 per-sender CR rate limit: max 5 CRs per hour per sender.
  // Key: senderUserIdHex, Value: list of timestamps (kept ≤ 5, pruned on check).
  final Map<String, List<DateTime>> _crRateTracker = {};

  // §5.6 Key-rotation transition: previous primary mailbox ID, polled for 7
  // days after key rotation so messages stored under the old pubkey are found.
  Uint8List? _previousMailboxPrimary;
  DateTime? _previousMailboxPrimarySetAt;
  static const _mailboxTransitionDays = 7;

  // ── §5.8 One-Shot-Outbox ─────────────────────────────────────────────
  // Messages that could NOT be placed into L3 (Erasure + S&F) because the
  // sender had 0 connectivity at send time.  Each entry holds the serialized
  // canonical NetworkPacketV3 bytes plus routing metadata so the edge-triggered
  // flush (_flushOutbox) can retry the single L3 placement attempt exactly once.
  //
  // IMPORTANT: This is NOT a retry queue. There is NO timer, NO periodic flush.
  // The flush fires exactly once, edge-triggered by onNetworkChanged (= the
  // first time the sender gets a network interface back after being offline).
  // If the flush itself still finds 0 DHT peers (which is possible in the
  // split-second before Kademlia finds neighbours), the entry stays until the
  // NEXT onNetworkChanged edge — guaranteeing liveness without polling.
  //
  // Structure: messageIdHex → _OutboxEntry
  final Map<String, _OutboxEntry> _outbox = {};
  bool _outboxLoaded = false;

  // §5.1 F3′ (fourth outbox edge): last user-scoped flush attempt per sender.
  // Gates the verified-inbound edge so a chatty sender cannot re-trigger a
  // still-failing flush on every frame. NOT a timer — consulted only when an
  // inbound frame arrives while entries for that sender are parked.
  final Map<String, DateTime> _outboxInboundFlushAt = {};
  static const Duration _outboxInboundFlushGate = Duration(seconds: 60);

  // §5.8 extension: pending membership update resends.
  // When _broadcastGroupUpdate / _broadcastChannelUpdate fails for a member
  // (sendToUser returned false), the (entityId, recipientHex) pair is parked
  // here. On the next onNetworkChanged edge, the CURRENT group/channel state
  // is re-sent to pending recipients only (not all members). Successful
  // re-sends are removed; stale entries (member removed, entity deleted) are
  // cleaned up during flush.
  // Structure: entityIdHex (group or channel) → Set<recipientUserIdHex>
  final Map<String, Set<String>> _pendingMembershipResends = {};

  CleonaService({
    required this.identity,
    required this.node,
    required this.displayName,
    this.networkChannel = 'beta',
  })  : profileDir = identity.profileDir,
        port = node.port,
        _log = CLogger.get('service', profileDir: identity.profileDir);

  /// Start service-level components (contacts, conversations, mailbox).
  /// The node must already be started externally.
  Future<void> startService() async {
    _log.info('Starting CleonaService "$displayName"...');

    // Ensure profile dir exists
    Directory(profileDir).createSync(recursive: true);

    // Init mailbox store
    mailboxStore = MailboxStore(profileDir: profileDir);
    await mailboxStore.load();

    // Init channel index (public channel discovery cache)
    _channelIndex = ChannelIndex(dataDir: profileDir);
    _channelIndex.load();

    // Init moderation sub-service
    _moderation = ChannelModerationService(this);
    _moderation.onJuryRequestReceived = (req) => onJuryRequestReceived?.call(req);

    // Init call service (call/group-call managers, audio/video engine)
    _calls = CallService(this, notificationSound: notificationSound, log: _log);
    _callsReady = true;
    _calls.onIncomingCall = (info) => onIncomingCall?.call(info);
    _calls.onCallAccepted = (info) => onCallAccepted?.call(info);
    _calls.onCallRejected = (info, reason) => onCallRejected?.call(info, reason);
    _calls.onCallEnded = (info) => onCallEnded?.call(info);
    _calls.onIncomingGroupCall = (info) => onIncomingGroupCall?.call(info);
    _calls.onGroupCallStarted = (info) => onGroupCallStarted?.call(info);
    _calls.onGroupCallEnded = (info) => onGroupCallEnded?.call(info);
    _calls.onStateChanged = () => onStateChanged?.call();
    _calls.onPostCallNotificationAndroid = (name, id) => onPostCallNotificationAndroid?.call(name, id);
    _calls.onCancelCallNotificationAndroid = () => onCancelCallNotificationAndroid?.call();
    // Forward whatever was buffered on the plain fields below (set by
    // callers that ran before startService, e.g. main.dart's
    // _wireServiceCallbacks) to the now-constructed CallService.
    _calls.onGroupVideoI420Frame = _bufferedOnGroupVideoI420Frame;
    _calls.createVideoEngine = _bufferedCreateVideoEngine;
    _calls.onVideoFrameReceived = _bufferedOnVideoFrameReceived;
    _calls.onKeyframeRequested = _bufferedOnKeyframeRequested;
    _calls.init();

    // §5.5b: FIRST_CR_STORE_ACK callback — update contact status to
    // storedForDelivery when a seed peer confirms it stored our CR.
    node.onFirstCrStoreAck = (senderDeviceId, accepted) {
      if (!accepted) return;
      final senderHex = bytesToHex(senderDeviceId);
      for (final entry in _contacts.entries) {
        if (entry.value.status != 'pending_outgoing') continue;
        // The ACK comes from the seed peer, not the target. Check if
        // this seed peer is in the routing table as a protected seed.
        final seedPeer = node.routingTable.getPeer(senderDeviceId);
        if (seedPeer != null && seedPeer.isProtectedSeed) {
          entry.value.status = 'storedForDelivery';
          _saveContacts();
          onStateChanged?.call();
          _log.info('§5.5b CR storedForDelivery for '
              '${entry.key.substring(0, 8)} via seed ${senderHex.substring(0, 8)}');
          break;
        }
      }
    };

    // Init guardian service
    guardianService = GuardianService(
      identity: identity,
      node: node,
      profileDir: profileDir,
    );
    guardianService.onGuardianRestoreRequest = (ownerName, triggerName, ownerHex, mailboxHex) {
      onGuardianRestoreRequest?.call(ownerName, triggerName, ownerHex, mailboxHex);
    };
    guardianService.sendFragmentStoreWithAck = (fragStoreBytes, messageId, fragmentIndex, recipientDeviceId) async {
      final msgIdHex = bytesToHex(messageId);
      final key = '$msgIdHex:$fragmentIndex';
      final completer =
          _pendingFragmentStoreAcks.putIfAbsent(key, () => Completer<void>());
      unawaited(node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_FRAGMENT_STORE,
        innerPayload: fragStoreBytes,
        recipientDeviceId: recipientDeviceId,
      ));
      try {
        await completer.future.timeout(_peerStoreAckTimeout);
        _pendingFragmentStoreAcks.remove(key);
        return true;
      } on TimeoutException {
        _pendingFragmentStoreAcks.remove(key);
        return false;
      }
    };

    // Load contacts
    _loadContacts();

    // Init local device (§26 Multi-Device)
    _initLocalDevice();

    // §7.1: Restore linked-device delegation keys (if this is a Linked Device)
    final restoredLinkedKeys = LinkedDeviceKeysStore.load(
      profileDir: profileDir,
      fileEnc: _fileEnc,
    );
    if (restoredLinkedKeys != null) {
      applyLinkedDeviceKeys(restoredLinkedKeys);
      _log.info('Restored linked-device keys from disk');
    }

    // Load own profile picture
    _loadProfilePicture();

    // Load own profile description
    _loadProfileDescription();

    // Load groups
    _loadGroups();

    // Load channels
    _loadChannels();

    // NOTE: _seedSystemChannels() is intentionally NOT called here. It seeds
    // entries into `conversations`, which is not loaded until _loadConversations()
    // further down. Seeding before the load made _seedSystemChannels' own
    // _saveConversations() write a conversations.json containing ONLY the two
    // system channels — overwriting all real chats before they were ever read
    // back (catastrophic data loss on every restart). It now runs right after
    // _loadConversations(), mirroring _loadGroups/_loadChannels above.

    // Load moderation state
    _moderation.loadModeration();

    // Load calendar (§23)
    final calMgr = CalendarManager(
      profileDir: profileDir,
      identityId: identity.userIdHex,
      fileEnc: _fileEnc,
    );
    calMgr.load();
    _calendarProto = CalendarProtocolService(this, calMgr);
    _calendarProto.onCalendarInviteReceived = (s, e, t) => onCalendarInviteReceived?.call(s, e, t);
    _calendarProto.onCalendarRsvpReceived = (e, s, st) => onCalendarRsvpReceived?.call(e, s, st);
    _calendarProto.onCalendarEventUpdated = (e) => onCalendarEventUpdated?.call(e);
    _calendarProto.init();

    // Load external calendar sync (§23.8 — CalDAV + Google)
    calendarSyncService = CalendarSyncService(
      profileDir: profileDir,
      identityId: identity.userIdHex,
      calendar: calMgr,
      fileEnc: _fileEnc,
    );
    calendarSyncService.load();

    // Polls (§24)
    _polls = PollService(this);
    _polls.onPollCreated = (id, gid, q) => onPollCreated?.call(id, gid, q);
    _polls.onPollTallyUpdated = (id) => onPollTallyUpdated?.call(id);
    _polls.onPollStateChanged = (id) => onPollStateChanged?.call(id);
    _polls.init();

    // Key rotation retry manager (§26.6.2 Paket C): persisted per-contact
    // retry state so offline contacts still receive KEY_ROTATION_BROADCAST
    // after S&F TTL expiry.
    _keyRotationRetry = KeyRotationRetryManager(
      profileDir: profileDir,
      identityId: identity.userIdHex,
      fileEnc: _fileEnc,
    );
    _keyRotationRetry.load();

    // Birthday auto-sync (§23.4): derive yearly birthday events from
    // contacts that carry birthday metadata. Runs once at startup and is
    // refreshed from acceptContactRequest / setContactBirthday.
    _syncCalendarBirthdays();

    // Load media settings
    _loadMediaSettings();

    // Load link preview settings
    _loadLinkPreviewSettings();
    _linkPreviewFetcher = LinkPreviewFetcher(
      settings: _linkPreviewSettings,
      log: (msg) => _log.debug(msg),
    );

    // Sync contact/channel tier registration to DV routing table
    _syncTierRegistration();

    // §4.11 External Rendezvous: Nostr cold-start address resolution.
    // Each identity/device inits its own RendezvousManager (§4.11.7
    // per-device independence — no "first service wins" gate).
    _rendezvousManager = RendezvousManager(profileDir: profileDir);
    _rendezvousManager!.init(
      ownFoundingSk: identity.ed25519SecretKey,
      ownUserIdHex: identity.userIdHex,
      // §4.11.7: device-scoped rendezvous MUST use the daemon-global
      // deviceNodeId, not the userId. identity.nodeId is a legacy alias
      // for userId and must not be used for routing/device tags.
      deviceId: identity.deviceNodeId,
      contacts: _buildRendezvousContacts(),
      addressProvider: () => node.currentSelfAddresses()
          .map((a) => RendezvousAddress(a.ip, a.port))
          .toList(),
    );
    // Primary identity's manager is used for Tier 3b contact-resolve in the
    // discovery cascade. All managers publish independently.
    node.rendezvousManager ??= _rendezvousManager;

    // §4.11.10 First-Contact Rendezvous: URI-scoped Nostr rendezvous for the
    // very first CR over asynchronous ContactSeed-URIs (clipboard/e-mail).
    // Sessions are persisted in the profileDir and resumed in
    // _onPostDiscoveryRetrieve (network is up by then).
    _fcRendezvous = FirstContactRendezvousManager(profileDir: profileDir);
    _fcRendezvous!.init(
      deviceId: identity.deviceNodeId,
      addressProvider: () => node.currentSelfAddresses()
          .map((a) => RendezvousAddress(a.ip, a.port))
          .toList(),
    );
    _fcRendezvous!.onEndpointResolved = _onFcEndpointResolved;

    // §19.6 Censorship-Resistant Distribution: in-network binary updates.
    // Node-wide subsystem (fragment store on disk, one embedded HTTP server
    // on the shared transport, one Nostr rendezvous manager) — only the
    // first identity's service on this daemon wires it up, mirroring the
    // node.rendezvousManager ??= _rendezvousManager first-wins pattern above.
    if (node.binaryRendezvousManager == null) {
      await InstallSourceDetector.detect();

      _binaryFragmentStore = BinaryFragmentStore(profileDir);
      await _binaryFragmentStore!.init();

      _binaryUpdateManager = BinaryUpdateManager(
        store: _binaryFragmentStore!,
        checker: UpdateChecker(log: _log),
        profileDir: profileDir,
      );
      _deltaUpdateManager = DeltaUpdateManager(
        store: _binaryFragmentStore!,
        log: _log,
      );
      _inviteLinkService = InviteLinkService(profileDir: profileDir);
      _physicalTransferHelper = PhysicalTransferHelper(
        store: _binaryFragmentStore!,
        profileDir: profileDir,
      );
      _binarySeeder = BinarySeeder(store: _binaryFragmentStore!, profileDir: profileDir);
      _binaryFetchClient = BinaryFetchClient(profileDir: profileDir);
      // Once a download is verified and ready, this device becomes a
      // legitimate distribution source — (re)publish availability so
      // other cold-starting nodes can find it.
      _binaryUpdateManager!.onUpdateReady = (version, path) {
        node.binaryHasContentToShare = true;
        _binaryRendezvousManager?.startPeriodicRefresh(_buildBinaryAvailabilityRecord);
        _binaryRendezvousManager?.publish(_buildBinaryAvailabilityRecord());
      };

      _binaryHttpServer = BinaryHttpServer(profileDir: profileDir);
      _binaryHttpServer!.bootstrapWebApp = Uint8List.fromList(
          utf8.encode(BootstrapWebApp.html(
              maintainerPublicKeyHex: UpdateChecker.maintainerPublicKeyHex)));
      _binaryHttpServer!.binaryProvider = (platform) {
        final versions = _binaryFragmentStore!.storedVersionsSync(platform);
        if (versions.isEmpty) return null;
        return _binaryFragmentStore!.getCompleteSync(platform, versions.last);
      };
      _binaryHttpServer!.fragmentProvider = (platform, index) {
        final versions = _binaryFragmentStore!.storedVersionsSync(platform);
        if (versions.isEmpty) return null;
        return _binaryFragmentStore!.getFragmentSync(platform, versions.last, index);
      };
      node.transport.httpServer = _binaryHttpServer;

      _binaryRendezvousManager = BinaryRendezvousManager(profileDir: profileDir);
      _binaryRendezvousManager!.init(
        networkSecret: NetworkSecret.secret,
        deviceId: identity.deviceNodeId,
        addressProvider: () => node.currentSelfAddresses()
            .map((a) => RendezvousAddress(a.ip, a.port))
            .toList(),
        platformProvider: () => Platform.operatingSystem,
      );
      node.binaryRendezvousManager = _binaryRendezvousManager;
      node.binaryRecordProvider = _buildBinaryAvailabilityRecord;

      // Arbeitsregel #5 (kein unnötiger Netzwerkverkehr): only start the
      // periodic Nostr republish if this device already holds binary/
      // fragment data worth advertising. Devices with an empty store stay
      // silent until BinaryUpdateManager.onUpdateReady flips the flag above.
      node.binaryHasContentToShare = _binaryFragmentStore!
              .storedVersionsSync(Platform.operatingSystem)
              .isNotEmpty;
      if (node.binaryHasContentToShare) {
        _binaryRendezvousManager!.startPeriodicRefresh(_buildBinaryAvailabilityRecord);
      }

      // Self-seed: encode the running binary into RS fragments so this node
      // can serve updates immediately (§19.6.2).
      if (InstallSourceDetector.cached == InstallSource.sideload) {
        _selfSeedCurrentBinary();
      }

      _selfPublishManifest();

      // §19.6 fragment GC — prune old/excess fragment data once per hour,
      // and once immediately at startup to clean up stale data from
      // previous runs.
      _runBinaryFragmentGc();
      _binaryGcTimer = Timer.periodic(const Duration(hours: 1), (_) {
        _runBinaryFragmentGc();
      });
    }

    // Load conversations
    _loadConversations();
    _recoverStuckMedia();
    _loadPendingMediaSends();

    // Seed system channels (§9.5) — MUST run after _loadConversations() so the
    // real chats are already in `conversations`; seeding then only adds the two
    // system-channel entries if missing and the subsequent save persists the
    // FULL set. (Running this before the load destroyed all chats — see note
    // next to _loadChannels above.)
    _seedSystemChannels();
    // §9.5.7 (S119 D1): load the gossip record set for the system channels.
    _loadSysChanRecords();

    // After load: surface the persisted unreadCount to the system badge so
    // the Launcher-Badge matches the on-disk truth right after daemon-start.
    _updateBadgeCount();

    // Load persisted message-ID dedup set (H12 replay-window fix).
    _loadProcessedMessageIds();

    // §5.8: Load persisted outbox (messages that failed L3 placement when the
    // sender had 0 connectivity). Flush is edge-triggered by onNetworkChanged —
    // NOT by any startup timer.
    _loadOutbox();
    _loadMailboxTransition();
    _loadPendingMembershipResends();

    // V3.1.44: Migrate self-entries from deviceNodeId to userIdHex in groups/channels/messages.
    // §26 Phase 2 temporarily stored deviceNodeId as member keys, but service-level
    // identification must use the stable userId (same across all devices).
    _migrateDeviceNodeIdToUserId();

    // Clean up stale group/channel conversations
    final staleConvs = conversations.keys
        .where((id) {
          final c = conversations[id]!;
          if (c.isGroup && !_groups.containsKey(id)) return true;
          if (c.isChannel && !_channels.containsKey(id)) return true;
          return false;
        })
        .toList();
    for (final id in staleConvs) {
      conversations.remove(id);
      _log.info('Removed stale conversation: $id');
    }
    if (staleConvs.isNotEmpty) _saveConversations();

    // #U1 fix: edge-triggered offline-message retrieval.
    // S&F poll, DHT-fragment pull, and CR rebroadcast are all triggered by
    // node.onDiscoveryComplete (fires once after §4.5 cascade + jitter).
    // A second sweep 15s later catches peers that joined the routing table
    // after Kademlia bootstrap. No periodic polling (Arbeitsregel #5).
    node.onDiscoveryComplete = _onPostDiscoveryRetrieve;

    // §26: TWIN_ANNOUNCE at startup so existing twins learn about this device.
    // 6 seconds lets the first peers come up first. Fire-and-forget; a no-op
    // when we have no known twins yet (first twin learns us when its own
    // announce arrives here — our handler echoes _sendTwinAnnounce back).
    Timer(const Duration(seconds: 6), _sendTwinAnnounce);

    // Key rotation: check on startup and schedule daily check
    identity.discardPreviousKeysIfExpired();
    if (identity.needsRotation()) {
      _performKeyRotation();
    }
    _keyRotationTimer = Timer.periodic(const Duration(hours: 6), (_) {
      identity.discardPreviousKeysIfExpired();
      if (identity.needsRotation()) _performKeyRotation();
    });

    // §26.6.2 Paket C: re-sends pending KEY_ROTATION_BROADCAST every 24h
    // until every contact either ACKs or expires (default 90d / 3 attempts).
    // Fire once on startup so a long-offline sender resumes retries at boot.
    _retryPendingKeyRotations();
    _keyRotationRetryTimer = Timer.periodic(
        const Duration(hours: 24), (_) => _retryPendingKeyRotations());

    // Message expiry: check every 30 seconds for expired messages
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkMessageExpiry();
      _processedMsgIdsSaveCounter++;
      if (_processedMsgIdsSaveCounter >= 2) {
        _processedMsgIdsSaveCounter = 0;
        _saveProcessedMessageIds();
      }
    });

    // Channel index gossip + moderation timers (delegated to sub-service)
    // §9.5.7: system-channel record digests piggyback on the same slot.
    _moderation.onGossipTargets = sendSysChanDigests;
    _moderation.startChannelIndexGossip(const Duration(minutes: 5));
    _channelIndex.prune();
    _moderation.startModerationTimer();

    // System channel eviction (§9.5.5)
    _systemChannelEvictionTimer = Timer.periodic(
        const Duration(minutes: 30), (_) => _evictSystemChannels());

    // §7.1 LD-9: delegation cert renewal check (hourly)
    _delegationRenewalTimer = Timer.periodic(
        const Duration(hours: 1), (_) => _checkDelegationRenewal());

    // Stats wiring lives on CleonaNode now (single shared collector across
    // all identities). #U5: previous per-Service `??=` only let the first
    // service to start win the transport callbacks; all later services saw
    // 0 receive bytes.

    // RUDP Light: downgrade message status on ACK timeout.
    node.ackTracker.onAckTimeout = _handleAckTimeout;
    // FRAGMENT_STORE_ACK observation (proactive-push retry-cancel +
    // Erasure-F1 placement ACKs) is wired via the InfraFrame dispatcher →
    // handleIncomingFragmentStoreAckInfra (S123 Erasure-F1); the previous
    // CleonaNode.onFragmentStoreAck hook was dead code (never invoked,
    // since the DhtRpc bridge swallowed the frame before it could fire).

    // §5.1 L1 direct retry on first AckTracker timeout (transient loss).
    node.onMessageRetryNeeded = _handleRetryNeeded;
    // §5.1 Layer 3: offline cascade when all DV routes are exhausted.
    node.onMessageRetryExhausted = _handleRetryExhausted;

    // §4.11.11 / §5.1: contact-endpoint-confirmed is the third outbox edge
    // (besides onNetworkChanged and first-peer-confirmed). A rendezvous-
    // resolved contact device just answered — parked messages toward it can
    // now complete the cascade. Chained (multi-identity: one node, N
    // services — every service must flush its own outbox).
    final prevEndpointConfirmed = node.onContactEndpointConfirmed;
    node.onContactEndpointConfirmed = (contactUserIdHex) {
      prevEndpointConfirmed?.call(contactUserIdHex);
      unawaited(_flushOutbox());
    };

    // Track end-to-end reachability per contact (used to stop CR-Response retry).
    // AckTracker callback provides the deviceNodeId of the recipient (Phase 2
    // routing). Contacts are keyed by userId with deviceNodeIds as aliases —
    // resolve deviceNodeId → userId so the retry loop (which iterates userId
    // keys) finds the ACK.
    //
    // §3.4: cleona_node has already wired its DV-bridge handler in start().
    // Preserve it and chain — both layers need the same event but for
    // different state (DV-routing vs. contact reachability).
    final prevAckReceived = node.ackTracker.onAckReceived;
    node.ackTracker.onAckReceived = (msgIdHex, recipientHex, wasDirect) {
      prevAckReceived?.call(msgIdHex, recipientHex, wasDirect);

      final now = DateTime.now();
      _contactLastAckedAt[recipientHex] = now;
      _staleWarningWrittenFor.remove(recipientHex);
      for (final entry in _contacts.entries) {
        if (entry.key == recipientHex ||
            entry.value.deviceNodeIds.contains(recipientHex)) {
          _contactLastAckedAt[entry.key] = now;
          _staleWarningWrittenFor.remove(entry.key);
          // §4.11.10 scanner-side session end: a DELIVERY_RECEIPT from this
          // contact proves end-to-end reachability — the First-Contact
          // rendezvous session (if any) is complete. Cheap no-op otherwise.
          _fcRendezvous?.onCrConfirmed(entry.key);
          return;
        }
      }
      _fcRendezvous?.onCrConfirmed(recipientHex);
    };

    // Mutual Peer Selection for S&F (Architecture Section 3.3.7).
    node.getMutualPeerIds = _computeMutualPeerIds;

    // D1 (§4.3 Trust anchor): Contact-Pubkey-Lookup fuer den Contact-Match/
    // Continuity-Pfad des Resolvers. Multi-Identity: Services teilen einen
    // Node — chainen statt ueberschreiben, damit Kontakte aller gehosteten
    // Identitaeten gefunden werden (Pattern wie onAckReceived oben).
    final prevContactPkLookup = node.identityResolver.contactEd25519PkLookup;
    node.identityResolver.contactEd25519PkLookup = (userId) {
      final pk = _contacts[bytesToHex(userId)]?.ed25519Pk;
      if (pk != null && pk.isNotEmpty) return pk;
      return prevContactPkLookup?.call(userId);
    };
    node.identityResolver.onContactKeyMismatch ??= (userId, embeddedPk) {
      _log.warn('D1 trust anchor: AuthManifest fuer Kontakt '
          '${bytesToHex(userId).substring(0, 16)}... traegt einen User-Key, '
          'der dem gespeicherten Kontakt-Key widerspricht (keine brueckende '
          'Rotationskette) — Record verworfen (§4.3 contact continuity)');
    };

    // markStarted lives on node._startBase now — Multi-Identity-Daemon shouldn't
    // reset uptime every time a second/third identity comes up.
    await notificationSound.init(identity.profileDir);

    // §2.2.4: 2D-DHT Identity Publisher pro Identität. The publisher needs
    // access to the local IdentityDhtHandler so it can self-store every
    // record it publishes — without that self-store, a 2-node setup stalls
    // because the publisher itself ranks among the k-closest replicators
    // for its own dht-keys (and Kademlia retrieve probes us first), but we
    // would have nothing to answer with.
    _identityPublisher = IdentityPublisher(
      identity: identity,
      routingTable: node.routingTable,
      sender: _IdentityPublisherSender(node),
      dhtHandler: node.identityDhtHandler,
      // D4 (§4.3 Publisher self-verify): post-publish self-lookup channel.
      dhtRpc: node.dhtRpc,
    );
    // D4 observability: feed the idSelfVerifyOk/Miss network-stats counters.
    _identityPublisher!.onSelfVerifyResult =
        (ok) => node.statsCollector.recordIdSelfVerify(ok);
    _identityPublisher!.setForeground(_isAppResumed);
    _identityPublisher!.setAddressProvider(() => node.currentSelfAddresses());
    // Welle 5 (§3.5b + §4.3): publisher braucht die Device-KEM-Pubkeys, um
    // den DeviceKemRecord zu signen und ueber `kem-key = SHA-256("kem" ||
    // userId || deviceId)` ins 2D-DHT zu replizieren. Quelle ist das
    // node-eigene Device-KEM-Keypair (locally generated, NICHT seed-derived
    // per §3.6 #5).
    _identityPublisher!.setDeviceKemPkProvider(() => (
          x25519Pk: node.deviceKem.x25519PublicKey,
          mlKemPk: node.deviceKem.mlKemPublicKey,
        ));
    // §7.5: Device-Sig-Pubkeys fuer Co-Authorization im AuthManifest.
    _identityPublisher!.setDeviceSigPkProvider(() => (
          ed25519Pk: node.deviceKeyPair.ed25519PublicKey,
          mlDsaPk: node.deviceKeyPair.mlDsaPublicKey,
        ));
    // §7.5: detect device-set shrink without co-auth proof in incoming manifests.
    node.identityDhtHandler.onDeviceSetShrinkWithoutProof =
        (userId, oldCount, newCount) {
      final userHex = bytesToHex(userId);
      final contact = _contacts[userHex];
      if (contact == null) return;
      _log.warn('§7.5 Device-set shrink for ${contact.displayName}: '
          '$oldCount→$newCount without valid proof');
      onRotationCoAuthWarning?.call(
          userHex, contact.displayName, 0, rotationQuorum(oldCount));
    };
    // Wake parked cold-start retry as soon as new peers join the routing table.
    // Without this hook the publisher only ever re-checks every 60s after
    // initial timeout — meaning a daemon that started before any peer was
    // known (Bootstrap-Restart, Cold-Start) would not republish until the
    // 20h auth-refresh tick.
    void onPeerAdded(PeerInfo peer) {
      _identityPublisher?.onPeerJoined();
      // Architecture §3.5 (V3.1.75): no re-push on reachability events. The
      // 3-attempt push budget per (fragment, owner) is consumed in one
      // contiguous retry window starting at the initial store-with-known-owner
      // trigger. Recovery for owners that come online later happens via the
      // owner's FRAGMENT_RETRIEVE startup poll (§3.3.6), not via sender-side
      // re-pushes.

      // §8.1.1: retry pending CRs when a new peer appears — the CR target
      // may now be reachable. Backoff gates inside the method prevent flooding.
      if (_contacts.values.any((c) => c.status == 'pending_outgoing')) {
        _retryPendingContactRequests();
      }
    }
    node.routingTable.addOnPeerAddedListener(onPeerAdded);
    _publisherPeerAddedListener = onPeerAdded;
    // Fire-and-forget: Publisher startet eigene cold-start-wait + scheduling
    unawaited(_identityPublisher!.start());

    // Init voice transcription service (whisper.cpp)
    // Load saved config from transcription_config.json (user may have changed language).
    var vtConfig = VoiceTranscriptionConfig.production();
    final vtConfigFile = File('$profileDir/transcription_config.json');
    if (vtConfigFile.existsSync()) {
      try {
        final j = json.decode(vtConfigFile.readAsStringSync()) as Map<String, dynamic>;
        vtConfig = VoiceTranscriptionConfig(
          defaultLanguage: j['defaultLanguage'] as String? ?? 'auto',
          audioRetentionDays: j['audioRetentionDays'] as int? ?? 30,
          modelSize: _parseModelSize(j['modelSize'] as String? ?? 'base'),
        );
        _log.info('Voice transcription config loaded: lang=${vtConfig.defaultLanguage}');
      } catch (e) {
        _log.warn('Failed to load transcription config: $e');
      }
    }
    _voiceTranscription = VoiceTranscriptionService(
      config: vtConfig,
      profileDir: profileDir,
    );
    _voiceTranscription!.onTranscriptionComplete = _onLocalTranscriptionComplete;
    if (_platformAudioDecoder != null) {
      _voiceTranscription!.platformAudioDecoder = _platformAudioDecoder;
    }
    await _voiceTranscription!.start();

    // Init media auto-archive manager (if configured)
    await _initArchive();

    // Update checking: check DHT for signed update manifest (every 6 hours)
    Timer(const Duration(seconds: 30), _checkForUpdates); // Initial check after 30s
    _updateCheckTimer = Timer.periodic(const Duration(hours: 6), (_) => _checkForUpdates());

    // §27.9 NAT-Troubleshooting-Wizard trigger (10-min hold, 1-min tick).
    _loadNatWizardSettings();
    _natWizardTrigger = NatWizardTrigger(
      getSignals: () => NatWizardSignals(
        stats: getNetworkStats(),
        externalIpv4: publicIp,
        dismissedUntilMs: _natWizardDismissedUntilMs,
        uptimeSeconds: node.statsCollector.uptime.inSeconds,
      ),
      onTrigger: () {
        _log.info('NAT-Wizard trigger fired (§27.9.1)');
        onNatWizardTriggered?.call();
      },
    );
    _natWizardTrigger!.start();

    _log.info('CleonaService started. User-ID: ${identity.userIdHex.substring(0, 16)}... '
        'Device-Node-ID: ${identity.deviceNodeIdHex.substring(0, 16)}...');
  }

  /// Initialize media auto-archive if configured.
  Future<void> _initArchive() async {
    try {
      final configFile = File('$profileDir/archive_config.json');
      if (!configFile.existsSync()) return;
      final config = ArchiveConfig.fromJson(
          json.decode(configFile.readAsStringSync()) as Map<String, dynamic>);
      if (!config.enabledByDefault || config.archiveHost.isEmpty) return;

      final transport = ArchiveTransport.forProtocol(config.defaultProtocol);
      await transport.connect(
        host: config.archiveHost,
        path: config.archivePath,
        username: config.archiveUsername,
        password: config.archivePassword,
        port: config.archivePort,
      );

      _archiveManager = ArchiveManager(
        config: config,
        transport: transport,
        profileDir: profileDir,
      );
      await _archiveManager!.startScheduler();
      _log.info('ArchiveManager started (${config.defaultProtocol.name}://${config.archiveHost})');
    } catch (e) {
      _log.warn('ArchiveManager init failed: $e');
      _archiveManager = null;
    }
  }

  /// Legacy: Full start creating its own node. Used by headless mode / in-process fallback.
  Future<void> start() async {
    await startService();
  }

  /// Legacy alias.
  Future<void> startQuick() async {
    await startService();
  }

  // ── Message Handling ───────────────────────────────────────────────
  //
  // V3 receive routes via `handleApplicationFrame` (User-KEM-decap) and
  // `handleIncoming*Infra` (Device-KEM-decap), both wired in
  // `service_daemon.dart`.

  /// Tracks when each contact last sent a typing indicator.
  final Map<String, DateTime> _typingTimestamps = {};

  /// Returns true if the given contact is currently typing (within last 5 seconds).
  bool isTyping(String nodeIdHex) {
    final ts = _typingTimestamps[nodeIdHex];
    if (ts == null) return false;
    return DateTime.now().difference(ts).inSeconds < 5;
  }

  /// RUDP Light: ACK timeout — downgrade message status from "sent" to "queued".
  void _handleAckTimeout(String messageIdHex, String recipientUserIdHex) {
    for (final conv in conversations.values) {
      for (final msg in conv.messages) {
        if (msg.id == messageIdHex && msg.isOutgoing && msg.status == MessageStatus.sent) {
          msg.status = MessageStatus.queued;
          _log.info('ACK timeout for ${messageIdHex.substring(0, 8)} to '
              '${recipientUserIdHex.substring(0, 8)} — status downgraded to queued');
          onStateChanged?.call();
          return;
        }
      }
    }
  }

  /// Check for expired messages and delete them.
  void _checkMessageExpiry() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;

    for (final conv in conversations.values) {
      final expiryMs = conv.config.expiryDurationMs;
      if (expiryMs == null || expiryMs <= 0) continue;

      for (final msg in conv.messages) {
        if (msg.isDeleted) continue;
        if (msg.readAt == null) continue;
        final elapsed = now - msg.readAt!.millisecondsSinceEpoch;
        if (elapsed >= expiryMs) {
          msg.text = '';
          msg.isDeleted = true;
          changed = true;
          _log.debug('Message ${msg.id.substring(0, 8)} expired after ${elapsed}ms');
        }
      }
    }

    if (changed) {
      _saveConversations();
      onStateChanged?.call();
    }

    // Prune service-level cooldown maps to prevent unbounded growth.
    final nowDt = DateTime.now();
    _lastNotifiedAt.removeWhere((_, ts) => nowDt.difference(ts).inHours > 1);
    _lastCrRetryPerContact.removeWhere((_, ts) => nowDt.difference(ts).inHours > 2);
    _contactLastAckedAt.removeWhere((_, ts) => nowDt.difference(ts).inDays > 1);
    _resyncRequestedAtEpoch.removeWhere((_, epoch) => epoch > 0 &&
        nowDt.millisecondsSinceEpoch ~/ 1000 - epoch > 86400);
  }

  /// FRAGMENT_STORE handler (Architecture §5.4 + §23.3 InfraFrame). Stores
  /// the fragment in the local mailbox; if storage succeeds, sends a
  /// FRAGMENT_STORE_ACK back to the sender's device. If the fragment
  /// targets our own mailbox, triggers reassembly; otherwise, if we know
  /// the mailbox owner, kicks off a proactive push (§3.5).
  void _handleFragmentStore(Uint8List payload, Uint8List senderDeviceId) {
    // D3 Phase 2 (§13.1.2): reject fragment stores from non-admitted senders
    // (unless the sender is a local identity — self-store for own mailbox).
    if (senderDeviceId.isNotEmpty &&
        !node.routingTable.isLocalNode(senderDeviceId)) {
      final senderPeer = node.routingTable.getPeer(senderDeviceId);
      if (senderPeer != null &&
          !senderPeer.idPowVerified &&
          !senderPeer.isProtectedSeed) {
        _log.debug('D3: FRAGMENT_STORE from non-admitted '
            '${bytesToHex(senderDeviceId).substring(0, 8)} — rejected');
        return;
      }
    }
    try {
      final frag = proto.FragmentStore.fromBuffer(payload);
      final stored = mailboxStore.storeFragment(StoredFragment(
        mailboxId: Uint8List.fromList(frag.mailboxId),
        messageId: Uint8List.fromList(frag.messageId),
        fragmentIndex: frag.fragmentIndex,
        totalFragments: frag.totalFragments,
        requiredFragments: frag.requiredFragments,
        data: Uint8List.fromList(frag.fragmentData),
        originalSize: frag.originalSize,
      ));

      if (stored) {
        final ackPayload = (proto.FragmentStoreAck()
              ..messageId = frag.messageId
              ..fragmentIndex = frag.fragmentIndex)
            .writeToBuffer();
        node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_FRAGMENT_STORE_ACK,
          innerPayload: Uint8List.fromList(ackPayload),
          recipientDeviceId: senderDeviceId,
        );
      }

      final mailboxId = Uint8List.fromList(frag.mailboxId);
      if (_isOurMailbox(mailboxId)) {
        _tryReassemble(Uint8List.fromList(frag.messageId));
      } else if (stored) {
        _proactivePush(frag, mailboxId);
      }
    } catch (e) {
      _log.debug('Fragment store error: $e');
    }
  }

  /// Proactive fragment push: forward a stored fragment to the mailbox owner
  /// if we know their address. Push-based delivery (< 1s latency) replaces
  /// polling for online recipients. Per Architecture Section 3.5.
  /// Checks both contacts AND routing table peers (PeerExchange provides PKs).
  void _proactivePush(proto.FragmentStore frag, Uint8List mailboxId) {
    final ownerNodeId = _findMailboxOwner(mailboxId);
    if (ownerNodeId == null) return;
    _attemptPush(frag, mailboxId, ownerNodeId);
  }

  /// Resolve mailboxId to ownerNodeId via contacts + routing table.
  Uint8List? _findMailboxOwner(Uint8List mailboxId) {
    final sodium = SodiumFFI();
    final seen = <String>{};

    bool tryCandidate(Uint8List nodeId, Uint8List ed25519Pk) {
      final candidateMailbox = sodium.sha256(Uint8List.fromList(
        [...utf8.encode('mailbox'), ...ed25519Pk],
      ));
      return _bytesEqual(mailboxId, candidateMailbox);
    }

    for (final contact in _contacts.values) {
      if (contact.ed25519Pk == null) continue;
      final hex = bytesToHex(contact.nodeId);
      if (!seen.add(hex)) continue;
      if (tryCandidate(contact.nodeId, contact.ed25519Pk!)) {
        return contact.nodeId;
      }
    }
    for (final peer in node.routingTable.allPeers) {
      if (peer.ed25519PublicKey == null || peer.ed25519PublicKey!.isEmpty) continue;
      final hex = bytesToHex(peer.nodeId);
      if (!seen.add(hex)) continue;
      if (tryCandidate(peer.nodeId, peer.ed25519PublicKey!)) {
        return peer.nodeId;
      }
    }
    return null;
  }

  /// Single push attempt with retry-on-no-ACK.
  /// Idempotent per (mailboxId, messageId, fragmentIndex, ownerNodeId):
  /// reuses the FragmentPushState retryTimer to avoid concurrent chains.
  /// Architecture §3.5 Push reliability: up to 3 attempts (initial + 2 retries),
  /// backoffs 500 ms / 2 s. Cancelled on FRAGMENT_STORE_ACK.
  void _attemptPush(proto.FragmentStore frag, Uint8List mailboxId, Uint8List ownerNodeId) {
    final storeKey = '${bytesToHex(mailboxId)}:'
        '${bytesToHex(Uint8List.fromList(frag.messageId))}:'
        '${frag.fragmentIndex}';

    final state = mailboxStore.pushStateFor(storeKey, ownerNodeId);
    if (state == null) return;        // fragment already evicted
    if (state.pushAcked) return;      // owner already received
    if (state.attempts >= MailboxStore.maxPushAttempts) return;

    final peer = node.routingTable.getPeer(ownerNodeId);
    if (peer == null) {
      // Owner not currently in routing table; skip this attempt.
      // Architecture §3.5: no re-push on reachability — the budget is
      // consumed in one contiguous window. If the owner reappears later,
      // recovery is via their FRAGMENT_RETRIEVE startup poll (§3.3.6).
      return;
    }

    state.cancelRetry();
    mailboxStore.recordPushAttempt(storeKey, ownerNodeId);
    final attemptNum = state.attempts;

    // V3 proactive push: notify owner via InfrastructureFrame
    // (MTV3_FRAGMENT_STORE) targeted at their deviceId. Fire-and-forget;
    // ACK arrives via FRAGMENT_STORE_ACK → onProactivePushAcked() which
    // cancels the retry timer. Architecture §3.5 push-pacing.
    final fragBytes = Uint8List.fromList(frag.writeToBuffer());
    unawaited(node.sendInfraTo(
      messageType: proto.MessageTypeV3.MTV3_FRAGMENT_STORE,
      innerPayload: fragBytes,
      recipientDeviceId: ownerNodeId,
    ).then((sent) {
      if (sent) {
        _log.debug('Proactive push sent: attempt $attemptNum/'
            '${MailboxStore.maxPushAttempts} frag=${frag.fragmentIndex} '
            'owner=${bytesToHex(ownerNodeId).substring(0, 8)} '
            'targets=${peer.allConnectionTargets().length}');
      } else {
        _log.debug('Proactive push send failed (no DV-route or KEM-PK): '
            'attempt $attemptNum frag=${frag.fragmentIndex} '
            'owner=${bytesToHex(ownerNodeId).substring(0, 8)}');
      }
    }, onError: (Object e, StackTrace st) {
      _log.warn('Proactive push exception: attempt $attemptNum '
          'frag=${frag.fragmentIndex} '
          'owner=${bytesToHex(ownerNodeId).substring(0, 8)} err=$e');
    }));

    if (attemptNum >= MailboxStore.maxPushAttempts) return;

    // Backoff after attempt 1 → 500ms; after attempt 2 → 2s.
    final backoff = attemptNum == 1
        ? const Duration(milliseconds: 500)
        : const Duration(seconds: 2);
    state.retryTimer = Timer(backoff, () {
      _attemptPush(frag, mailboxId, ownerNodeId);
    });
  }

  /// Called by Node when a FRAGMENT_STORE_ACK is observed for a push we issued.
  /// Marks the corresponding push as completed and cancels its retry timer.
  void onProactivePushAcked(Uint8List messageId, int fragmentIndex) {
    final storeKey = mailboxStore.markPushAcked(messageId, fragmentIndex);
    if (storeKey != null) {
      _log.debug('Proactive push ACKed: frag=$fragmentIndex msg=${bytesToHex(messageId).substring(0, 8)}');
    }
  }

  /// FRAGMENT_RETRIEVE handler (Architecture §5.4 + §23.3 InfraFrame).
  /// Looks up fragments stored for [req.mailboxId] in the local mailbox
  /// and forwards each one back to [senderDeviceId] as a fresh
  /// FRAGMENT_STORE via the DV cascade.
  void _handleFragmentRetrieve(Uint8List payload, Uint8List senderDeviceId) {
    try {
      final req = proto.FragmentRetrieve.fromBuffer(payload);
      final mailboxId = Uint8List.fromList(req.mailboxId);
      final fragments = mailboxStore.retrieveFragments(mailboxId);

      for (final frag in fragments) {
        final fragStore = proto.FragmentStore()
          ..mailboxId = frag.mailboxId
          ..messageId = frag.messageId
          ..fragmentIndex = frag.fragmentIndex
          ..totalFragments = frag.totalFragments
          ..requiredFragments = frag.requiredFragments
          ..fragmentData = frag.data
          ..originalSize = frag.originalSize;
        node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_FRAGMENT_STORE,
          innerPayload: Uint8List.fromList(fragStore.writeToBuffer()),
          recipientDeviceId: senderDeviceId,
        );
      }
      final resp = proto.FragmentRetrieveResponse()
        ..mailboxId = req.mailboxId
        ..fragmentCount = fragments.length;
      node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE_RESPONSE,
        innerPayload: Uint8List.fromList(resp.writeToBuffer()),
        recipientDeviceId: senderDeviceId,
      );
      _log.info('FRAGMENT_RETRIEVE: sent ${fragments.length} fragments + response '
          'to ${bytesToHex(senderDeviceId).substring(0, 8)}');
    } catch (e) {
      _log.debug('Fragment retrieve error: $e');
    }
  }

  void handleIncomingFragmentRetrieveResponseInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
  ) {
    try {
      final resp = proto.FragmentRetrieveResponse.fromBuffer(frame.payload);
      _log.info('FRAGMENT_RETRIEVE_RESPONSE from '
          '${bytesToHex(senderDeviceId).substring(0, 8)}: '
          '${resp.fragmentCount} fragments');
    } catch (e) {
      _log.debug('Fragment retrieve response error: $e');
    }
  }

  /// FRAGMENT_DELETE handler (Architecture §5.4 + §23.3 InfraFrame).
  /// Mailbox-owner explicitly evicts a reassembled fragment-bundle; no
  /// reply, no ACK.
  void _handleFragmentDelete(Uint8List payload) {
    try {
      final del = proto.FragmentDelete.fromBuffer(payload);
      mailboxStore.deleteFragments(
        Uint8List.fromList(del.mailboxId),
        Uint8List.fromList(del.messageId),
      );
    } catch (_) {}
  }

  // Pending media: maps messageIdHex -> local file path (sender keeps file until accepted).
  // Persisted to $profileDir/pending_media_sends.json so Two-Stage transfers
  // survive app restarts (the receiver's MEDIA_REQUEST may arrive hours later
  // via S&F, and the in-memory map would be empty after a restart).
  final Map<String, String> _pendingMediaSends = {};

  // Receiver-side Stage-2 reassembly buffer. Keyed by mediaIdHex (the original
  // MEDIA_ANNOUNCE messageId). Holds the partial chunk-array; finalised by
  // MEDIA_COMPLETE → file write + UiMessage state-bump to completed.
  final Map<String, _MediaChunkBuffer> _mediaChunkBuffers = {};

  /// Send a media file (image, file, etc.) to a contact or group.
  /// Two-Stage: sends MEDIA_ANNOUNCEMENT first, actual content on MEDIA_ACCEPT.
  @override
  Future<UiMessage?> sendMediaMessage(String conversationId, String filePath) async {
    _log.info('sendMediaMessage: convId=$conversationId path=$filePath');
    if (_reducedMode) {
      _log.warn('sendMediaMessage blocked: reducedMode active');
      return null;
    }
    final file = File(filePath);
    if (!file.existsSync()) {
      _log.warn('sendMediaMessage: file does not exist at $filePath');
      return null;
    }

    final audioBytes = await file.readAsBytes();
    final filename = filePath.split('/').last;
    final mimeType = _guessMimeType(filename);
    final fileSize = audioBytes.length;
    final isVoice = _isVoiceFromMime(mimeType);
    final isGroup = _groups.containsKey(conversationId);

    if (!isGroup) _maybeWriteStaleContactWarning(conversationId);

    // Copy file to media directory so sent media survives source deletion
    final mediaDir = Directory('$profileDir/media');
    if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
    var persistentPath = '${mediaDir.path}/$filename';
    if (filePath != persistentPath) {
      // Avoid overwriting a different file with the same name
      final existing = File(persistentPath);
      if (existing.existsSync() && existing.lengthSync() != fileSize) {
        final dot = filename.lastIndexOf('.');
        final base = dot > 0 ? filename.substring(0, dot) : filename;
        final ext = dot > 0 ? filename.substring(dot) : '';
        persistentPath = '${mediaDir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
      }
      file.copySync(persistentPath);
    }

    // ── Show message in UI IMMEDIATELY (optimistic update) ──
    // Optimistic UI msg.id is the wire messageId so DELIVERY_RECEIPT
    // (which carries inner.messageId) can match this local message and
    // upgrade `sent → delivered` in `_handleDeliveryReceiptV3`. Mirrors
    // the alignment pattern from `sendTextMessage` (commit 145e24d).
    final messageIdBytes = SodiumFFI().randomBytes(16);
    final tempId = bytesToHex(messageIdBytes);
    final msg = UiMessage(
      id: tempId,
      conversationId: conversationId,
      senderNodeIdHex: identity.userIdHex,
      text: filename,
      timestamp: DateTime.now(),
      type: _msgTypeFromMime(mimeType),
      status: MessageStatus.sending,
      isOutgoing: true,
      filePath: persistentPath,
      mimeType: mimeType,
      fileSize: fileSize,
      filename: filename,
      mediaState: MediaDownloadState.completed,
    );
    _addMessageToConversation(conversationId, msg, isGroup: isGroup);

    // Yield to let UI repaint before heavy crypto/transcription work
    await Future.delayed(Duration.zero);

    // ── Voice transcription (source-side, non-blocking for UI) ──
    VoiceTranscription? senderTranscript;
    if (isVoice) {
      senderTranscript = await _voiceTranscription?.transcribeNow(filePath);
      if (senderTranscript != null) {
        msg.transcriptText = senderTranscript.text;
        msg.transcriptLanguage = senderTranscript.language;
        msg.transcriptConfidence = senderTranscript.confidence;
        onStateChanged?.call(); // Update UI with transcript
        _log.info('Voice transcribed: "${senderTranscript.text.length > 40 ? '${senderTranscript.text.substring(0, 40)}...' : senderTranscript.text}"');
      }
    }

    // ── Build payload ──
    Uint8List bytes;
    if (isVoice) {
      final voicePayload = proto.VoicePayload()..audioData = audioBytes;
      if (senderTranscript != null) {
        voicePayload.transcriptText = senderTranscript.text;
        voicePayload.transcriptLanguage = senderTranscript.language;
        voicePayload.transcriptConfidence = senderTranscript.confidence;
      }
      bytes = Uint8List.fromList(voicePayload.writeToBuffer());
    } else {
      bytes = audioBytes;
    }

    // Compute content hash
    final sodium = SodiumFFI();
    final contentHash = sodium.sha256(audioBytes);

    // Generate thumbnail for images. Architecture §3.4.1: "compressed thumbnail
    // (max 100 KB)". Earlier versions used `bytes.sublist(0, 100*1024)` which
    // produced TRUNCATED image bytes (header + partial data) — receiver's
    // Image.memory then crashed with "Codec failed to produce an image" on every
    // image > 100KB. Now: real decode → resize to 320×320 max → JPEG-encode at
    // q=70. Falls back to original bytes if decode fails or already small enough.
    Uint8List? thumbnail;
    if (mimeType.startsWith('image/') && bytes.isNotEmpty) {
      if (bytes.length <= 100 * 1024) {
        // Already small — use original bytes (likely valid as-is).
        thumbnail = bytes;
      } else {
        try {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            // Maintain aspect ratio, fit into 320×320.
            final resized = img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? 320 : null,
              height: decoded.height > decoded.width ? 320 : null,
              interpolation: img.Interpolation.linear,
            );
            final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
            // Cap final at 100KB for §3.4.1 compliance — drop quality if needed.
            thumbnail = encoded.length <= 100 * 1024
                ? encoded
                : Uint8List.fromList(img.encodeJpg(resized, quality: 50));
            // If even q=50 is over 100KB (very rare), drop thumbnail entirely
            // rather than ship invalid bytes.
            if (thumbnail.length > 100 * 1024) thumbnail = null;
          }
        } catch (e) {
          _log.warn('Thumbnail generation failed for $filename: $e — '
              'shipping no thumbnail rather than truncated bytes');
          thumbnail = null;
        }
      }
    }

    // Build MEDIA_ANNOUNCEMENT metadata
    final metadata = proto.ContentMetadata()
      ..mimeType = mimeType
      ..fileSize = Int64(fileSize)
      ..filename = filename
      ..contentHash = contentHash;
    if (thumbnail != null) metadata.thumbnail = thumbnail;

    final announcementBytes = metadata.writeToBuffer();

    // Determine recipients
    List<ContactInfo> recipients;
    if (isGroup) {
      final group = _groups[conversationId];
      if (group == null) return null;
      recipients = group.members.values
          .where((m) => m.nodeIdHex != identity.userIdHex && m.x25519Pk != null && m.mlKemPk != null)
          .map((m) => ContactInfo(
                nodeId: hexToBytes(m.nodeIdHex),
                displayName: m.displayName,
                x25519Pk: m.x25519Pk,
                mlKemPk: m.mlKemPk,
                status: 'accepted',
              ))
          .toList();
    } else {
      final contact = _contacts[conversationId];
      if (contact == null || contact.status != 'accepted') {
        _log.warn('sendMediaMessage: cannot send to non-accepted contact convId=$conversationId '
            'contact=${contact != null ? "exists status=${contact.status}" : "MISSING"} '
            '(contacts loaded: ${_contacts.length})');
        return null;
      }
      recipients = [contact];
    }

    // V3 send path. Inline (≤256KB) → MTV3_MEDIA_INLINE with the raw
    // content as payload + ContentMetadata on the frame. Two-Stage (>256KB)
    // → MTV3_MEDIA_ANNOUNCE with empty payload (metadata in frame), Stage-2
    // (MEDIA_REQUEST/CHUNK/COMPLETE) is wired in C4 (bulk + S&F + mailbox).
    final twoStage = fileSize > 256 * 1024;
    _log.info('[E2E media-send-path-v3] mode=${twoStage ? "two-stage-announce-only" : "inline"} '
        'fileSize=$fileSize recipients=${recipients.length} convId=${conversationId.substring(0, 8)}');
    // GM-1 (§9.1.4): group media must carry groupId + membership tag
    final groupForMedia = isGroup ? _groups[conversationId] : null;
    final mediaGroupId = isGroup ? hexToBytes(conversationId) : null;
    final mediaGmEpoch = groupForMedia?.membershipEpoch;
    final mediaGmHash = groupForMedia != null
        ? _computeMembershipHash(groupForMedia.membershipEpoch, conversationId, groupForMedia.members)
        : null;
    String? firstMsgId;
    if (!twoStage) {
      for (final recipient in recipients) {
        if (recipient.x25519Pk == null || recipient.mlKemPk == null) continue;
        final ok = await sendToUser(
          recipientUserId: recipient.nodeId,
          messageType: proto.MessageTypeV3.MTV3_MEDIA_INLINE,
          payload: bytes,
          contentMetadata: metadata,
          messageId: messageIdBytes,
          groupId: mediaGroupId,
          groupMembershipEpoch: mediaGmEpoch,
          groupMembershipHash: mediaGmHash,
        );
        if (ok) node.statsCollector.addMessageSent();
      }
      firstMsgId = tempId;
    } else {
      // Two-Stage Stage 1: announce only — content stays pending until
      // receiver triggers MEDIA_REQUEST. V3 trägt die Metadata strukturiert
      // im frame.contentMetadata, der Payload bleibt leer.
      for (final recipient in recipients) {
        if (recipient.x25519Pk == null || recipient.mlKemPk == null) continue;
        await sendToUser(
          recipientUserId: recipient.nodeId,
          messageType: proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE,
          payload: Uint8List(0),
          contentMetadata: metadata,
          messageId: messageIdBytes,
          groupId: mediaGroupId,
          groupMembershipEpoch: mediaGmEpoch,
          groupMembershipHash: mediaGmHash,
        );
      }
      firstMsgId = tempId;
      // Touch announcementBytes so the unused-local lint stays quiet —
      // keeps the helper available for the C4 fallback path.
      // ignore: unnecessary_statements
      announcementBytes;
    }

    // Store pending media for two-stage delivery (C4 will look this up
    // when the receiver sends MEDIA_REQUEST).
    if (twoStage) {
      _pendingMediaSends[firstMsgId] = persistentPath;
      _savePendingMediaSends();
    }

    // Update message with final ID and status
    msg.id = firstMsgId;
    final thumbnailB64 = thumbnail != null ? base64Encode(thumbnail) : null;
    msg.thumbnailBase64 = thumbnailB64;
    msg.status = MessageStatus.sent;
    _saveConversations();
    onStateChanged?.call();

    _log.info('[E2E media-send-done] msgId=${msg.id.substring(0, 8)} '
        'filename=$filename size=$fileSize recipient=${conversationId.substring(0, 8)} '
        'mode=${twoStage ? "two-stage (announcement only)" : "inline (full content)"}');
    return msg;
  }

  /// Accept a media download (Two-Stage: send MEDIA_ACCEPT).
  @override
  Future<bool> acceptMediaDownload(String conversationId, String messageId) async {
    _log.info('[E2E media-accept-send] msgId=${messageId.substring(0, 8)} convId=${conversationId.substring(0, 8)}');
    final conv = conversations[conversationId];
    if (conv == null) {
      _log.warn('[E2E media-accept-send] ABORT: conversation not found');
      return false;
    }

    // Enforce allowDownloads policy
    if (!conv.config.allowDownloads) {
      _log.warn('[E2E media-accept-send] BLOCKED: allowDownloads=false for $conversationId');
      return false;
    }

    final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null || msg.mediaState != MediaDownloadState.announced) {
      _log.warn('[E2E media-accept-send] ABORT: msg=${msg != null ? "exists state=${msg.mediaState.name}" : "MISSING"} '
          '(expected mediaState=announced)');
      return false;
    }

    // For now, just mark as downloading (the actual content delivery is handled
    // when we receive the IMAGE/FILE response from sender)
    msg.mediaState = MediaDownloadState.downloading;
    onStateChanged?.call();
    _saveConversations();

    // Send V3 MEDIA_REQUEST to the original sender. Payload = original
    // messageId bytes (16 bytes). Sender (C4 — see _handleMediaRequestV3)
    // looks up _pendingMediaSends[msgIdHex] and starts the bulk push.
    final contact = _contacts[msg.senderNodeIdHex];
    if (contact == null ||
        contact.x25519Pk == null ||
        contact.mlKemPk == null) {
      _log.warn('[E2E media-accept-send-v3] ABORT: contact=${contact != null ? "exists" : "MISSING"}');
      return false;
    }
    final ok = await sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageTypeV3.MTV3_MEDIA_REQUEST,
      payload: Uint8List.fromList(hexToBytes(messageId)),
    );
    _log.info('[E2E media-accept-send-v3] msgId=${messageId.substring(0, 8)} '
        'sender=${msg.senderNodeIdHex.substring(0, 8)} → MEDIA_REQUEST sendToUser ok=$ok');
    return ok;
  }

  static String _uniqueMediaPath(String dirPath, String filename) {
    var path = '$dirPath/$filename';
    if (!File(path).existsSync()) return path;
    final dot = filename.lastIndexOf('.');
    final base = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      path = '$dirPath/${base}_$i$ext';
      if (!File(path).existsSync()) return path;
    }
    return '$dirPath/${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  String _guessMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'mp4': return 'video/mp4';
      case 'webm': return 'video/webm';
      case 'mov': return 'video/quicktime';
      case 'mkv': return 'video/x-matroska';
      case 'mpeg': case 'mpg': return 'video/mpeg';
      case 'mp3': return 'audio/mpeg';
      case 'ogg': case 'oga': return 'audio/ogg';
      case 'wav': return 'audio/wav';
      case 'm4a': case 'aac': return 'audio/aac';
      case 'flac': return 'audio/flac';
      case 'opus': return 'audio/opus';
      case 'pdf': return 'application/pdf';
      case 'txt': return 'text/plain';
      case 'zip': return 'application/zip';
      default: return 'application/octet-stream';
    }
  }

  /// Maps MIME type to the correct MessageType.
  ///
  /// V3 has no media-subtype enum — `MTV3_MEDIA_INLINE` covers
  /// image/video/audio/file uniformly. This helper produces the
  /// UI-side [UiMessageType] tag for the chat-card row only; the wire
  /// layer always emits `MTV3_MEDIA_INLINE`.
  /// For voice-vs-non-voice branching see [_isVoiceFromMime].
  UiMessageType _msgTypeFromMime(String mimeType) {
    if (mimeType.startsWith('image/')) return UiMessageType.image;
    if (mimeType.startsWith('audio/')) return UiMessageType.voiceMessage;
    if (mimeType.startsWith('video/')) return UiMessageType.video;
    return UiMessageType.file;
  }

  /// True iff [mimeType] denotes a voice/audio recording (audio/*).
  /// V3 send-paths use this for transcription/voice-payload branching.
  bool _isVoiceFromMime(String mimeType) => mimeType.startsWith('audio/');

  /// Whether this V3 message type carries user-authored content that must
  /// be dropped while reduced-mode (sec-h5 §8.2 / T11) is active. Returning
  /// false means the type is infrastructure / DHT / signaling and should
  /// keep flowing even when the local user has skipped a hard-block update.
  ///
  /// Mirrors the user-initiated send-paths gated in T11. V3 collapses
  /// IMAGE/VIDEO/GIF/FILE into `MTV3_MEDIA_INLINE`; voice has its own
  /// `MTV3_VOICE_MESSAGE`. `MTV3_MEDIA_REQUEST` carries
  /// request-the-upload semantics. `MTV3_REPLY` is classified as
  /// user-content.
  static bool _isUserMessage(proto.MessageTypeV3 type) {
    switch (type) {
      case proto.MessageTypeV3.MTV3_TEXT:
      case proto.MessageTypeV3.MTV3_MEDIA_INLINE:
      case proto.MessageTypeV3.MTV3_VOICE_MESSAGE:
      case proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE:
      case proto.MessageTypeV3.MTV3_MEDIA_REQUEST:
      case proto.MessageTypeV3.MTV3_MEDIA_REJECT:
      case proto.MessageTypeV3.MTV3_MEDIA_CHUNK:
      case proto.MessageTypeV3.MTV3_REACTION:
      case proto.MessageTypeV3.MTV3_REPLY:
      case proto.MessageTypeV3.MTV3_EDIT:
      case proto.MessageTypeV3.MTV3_DELETE:
      case proto.MessageTypeV3.MTV3_CHANNEL_POST:
      case proto.MessageTypeV3.MTV3_CALENDAR_INVITE:
      case proto.MessageTypeV3.MTV3_CALENDAR_RSVP:
      case proto.MessageTypeV3.MTV3_CALENDAR_UPDATE:
      case proto.MessageTypeV3.MTV3_CALENDAR_DELETE:
      case proto.MessageTypeV3.MTV3_FREE_BUSY_REQUEST:
      case proto.MessageTypeV3.MTV3_FREE_BUSY_RESPONSE:
      case proto.MessageTypeV3.MTV3_POLL_CREATE:
      case proto.MessageTypeV3.MTV3_POLL_VOTE:
      case proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS:
      case proto.MessageTypeV3.MTV3_POLL_REVOKE:
      case proto.MessageTypeV3.MTV3_POLL_UPDATE:
      case proto.MessageTypeV3.MTV3_POLL_SNAPSHOT:
        return true;
      default:
        return false;
    }
  }

  /// Test-only accessor for the private user-message classifier.
  /// Used by `test/smoke/smoke_reduced_mode.dart`. Not for production callers —
  /// the gate is enforced inside [handleMessage], not at call sites.
  static bool isUserMessageForTest(proto.MessageTypeV3 type) => _isUserMessage(type);


  /// Sender-side edit window: 15 minutes (UI hides edit button after this).
  static const int _defaultEditWindowMs = 15 * 60 * 1000;

  /// Receiver-side tolerance: accept edits up to 60 min to avoid rejecting
  /// edits from older nodes that still use the previous 60-min default.
  static const int _receiverEditToleranceMs = 60 * 60 * 1000;

  // ── Emoji Reactions (Architecture Section 14.3) ──────────────────────

  /// Send an emoji reaction to a message.
  @override
  Future<void> sendReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
    required bool remove,
  }) async {
    if (_reducedMode) {
      _log.warn('sendReaction blocked: reducedMode active');
      return;
    }
    final conv = conversations[conversationId];
    if (conv == null) return;

    // Apply locally
    final msgIndex = conv.messages.indexWhere((m) => m.id == messageId);
    if (msgIndex >= 0) {
      final msg = conv.messages[msgIndex];
      if (remove) {
        msg.reactions[emoji]?.remove(identity.userIdHex);
        if (msg.reactions[emoji]?.isEmpty ?? false) msg.reactions.remove(emoji);
      } else {
        msg.reactions.putIfAbsent(emoji, () => {});
        msg.reactions[emoji]!.add(identity.userIdHex);
      }
    }

    // Build reaction payload
    final reaction = proto.EmojiReaction()
      ..messageId = hexToBytes(messageId)
      ..emoji = emoji
      ..remove = remove;
    final basePayload = Uint8List.fromList(reaction.writeToBuffer());

    // V3: pairwise fan-out via sendToUser. Group-Conversation-ID auf der
    // Wire-Side wandert mit C4-Groups; bis dahin landet die Reaction beim
    // Empfänger als DM-Reaction auf seinem Sender-Tab.
    final group = _groups[conversationId];
    if (group != null) {
      final groupIdBytes = hexToBytes(conversationId);
      final gmEpoch = group.membershipEpoch;
      final gmHash = _computeMembershipHash(gmEpoch, conversationId, group.members);
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageTypeV3.MTV3_REACTION,
          payload: basePayload,
          groupId: groupIdBytes,
          groupMembershipEpoch: gmEpoch,
          groupMembershipHash: gmHash,
        );
      }
    } else {
      final contact = _contacts[conversationId];
      if (contact == null ||
          contact.x25519Pk == null ||
          contact.mlKemPk == null) {
        return;
      }
      await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_REACTION,
        payload: basePayload,
      );
    }

    if (msgIndex >= 0) {
      onStateChanged?.call();
      _saveConversations();
      _log.info('Reaction ${remove ? "removed" : "added"}: $emoji on ${messageId.substring(0, 8)}');
    } else {
      _log.warn('sendReaction: message ${messageId.substring(0, 8)} not found locally, sent to network only');
    }
  }

  /// Broadcast IDENTITY_DELETED to all accepted contacts before deletion.
  /// V3: per-contact sendToUser fan-out; KEM/Sig handled inside sendToUser.
  /// §7.1 LD-5: only the Primary may delete an identity.
  Future<void> broadcastIdentityDeleted() async {
    if (identity.isLinkedDevice) {
      _log.warn('broadcastIdentityDeleted: blocked — Linked Device cannot delete identity');
      return;
    }
    final notification = proto.IdentityDeletedNotification()
      ..identityEd25519Pk = identity.ed25519PublicKey
      ..deletedAtMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..displayName = displayName;
    final payload = Uint8List.fromList(notification.writeToBuffer());
    var sent = 0;
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      try {
        final ok = await sendToUser(
          recipientUserId: contact.nodeId,
          messageType: proto.MessageTypeV3.MTV3_IDENTITY_DELETED,
          payload: payload,
        );
        if (ok) sent++;
      } catch (e) {
        _log.debug('IDENTITY_DELETED send to ${contact.displayName} failed: $e');
      }
    }
    _log.info('IDENTITY_DELETED broadcast sent to $sent contacts');
  }

  // ── Fragment Ownership Check ────────────────────────────────────────

  /// Check if a mailbox ID belongs to this identity.
  bool _isOurMailbox(Uint8List mailboxId) {
    final sodium = SodiumFFI();
    // Primary mailbox: SHA-256("mailbox" + ed25519Pk)
    final primaryInput = Uint8List.fromList(
      [...utf8.encode('mailbox'), ...identity.ed25519PublicKey],
    );
    if (_bytesEqual(mailboxId, sodium.sha256(primaryInput))) return true;

    // Fallback mailbox: SHA-256("mailbox-nid" + nodeId)
    final fallbackInput = Uint8List.fromList(
      [...utf8.encode('mailbox-nid'), ...identity.nodeId],
    );
    if (_bytesEqual(mailboxId, sodium.sha256(fallbackInput))) return true;

    // §5.6: accept fragments for previous primary during key-rotation transition
    if (_previousMailboxPrimary != null &&
        _bytesEqual(mailboxId, _previousMailboxPrimary!)) {
      return true;
    }

    return false;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// First-CR §8.1.1 backward-compat picker. Filters `resolved` to devices
  /// that carry a complete Device-KEM (X25519 + ML-KEM) and returns the
  /// candidate with the freshest `deviceKemPublishedAtMs`. When `preferred`
  /// is supplied (legacy ContactSeed `did`), candidates matching that
  /// deviceNodeId win over fresher non-matching ones — but only if at least
  /// one match has KEM material; otherwise the filter falls back to "any
  /// device with KEM". Returns `null` when no resolved device carries
  /// KEM material at all.
  static ResolvedDevice? firstCrPickDeviceKem(
      List<ResolvedDevice> resolved, Uint8List? preferred) {
    var withKem = resolved
        .where((d) => d.deviceX25519Pk != null && d.deviceMlKemPk != null)
        .toList();
    if (withKem.isEmpty) return null;
    if (preferred != null) {
      final byId = withKem
          .where((d) =>
              _bytesEqual(Uint8List.fromList(d.deviceNodeId), preferred))
          .toList();
      if (byId.isNotEmpty) withKem = byId;
    }
    withKem.sort((a, b) =>
        (b.deviceKemPublishedAtMs ?? 0).compareTo(a.deviceKemPublishedAtMs ?? 0));
    return withKem.first;
  }

  // ── Fragment Reassembly ────────────────────────────────────────────

  /// Reed-Solomon reassembly (Architecture §5.4). Once K=7 of N=10 fragments
  /// for a given `messageId` are present in the mailbox store, decode the
  /// canonical `NetworkPacketV3` wire bytes and re-inject them through the
  /// node's reassembly entrypoint. Outer-Sig-Verify, KEM-Decap and
  /// Inner-Sig-Verify run there identically to a UDP-received packet.
  ///
  /// Multi-device: fragments are *not* deleted after a successful local
  /// reassembly. Sibling devices of the same user polling the same mailbox
  /// need them too; expiry is via the 7-day DHT TTL.
  void _tryReassemble(Uint8List messageId) {
    final fragments = mailboxStore.getFragmentsForMessage(messageId);
    if (fragments.isEmpty) return;

    final first = fragments.first;
    if (fragments.length < first.requiredFragments) return;

    final fragMap = <int, Uint8List>{};
    for (final f in fragments) {
      fragMap[f.fragmentIndex] = f.data;
    }

    try {
      final rs = ReedSolomon();
      final data = rs.decode(fragMap, first.originalSize);
      node.dispatchReassembledPacket(data);
      _log.info('Reassembled message ${bytesToHex(messageId).substring(0, 8)}');
    } catch (e) {
      _log.debug('Reassembly failed for ${bytesToHex(messageId).substring(0, 8)}: $e');
    }
  }

  // ── Mailbox Polling ────────────────────────────────────────────────

  void _pollMailbox() {
    final sodium = SodiumFFI();

    // Primary mailbox: SHA-256("mailbox" + ed25519Pk)
    final primaryInput = Uint8List.fromList(
      [...utf8.encode('mailbox'), ...identity.ed25519PublicKey],
    );
    final primaryMailboxId = sodium.sha256(primaryInput);

    // Fallback mailbox: SHA-256("mailbox-nid" + nodeId)
    final fallbackInput = Uint8List.fromList(
      [...utf8.encode('mailbox-nid'), ...identity.nodeId],
    );
    final fallbackMailboxId = sodium.sha256(fallbackInput);

    // §5.6 Key-rotation transition: expire old primary after 7 days.
    if (_previousMailboxPrimary != null && _previousMailboxPrimarySetAt != null) {
      final age = DateTime.now().difference(_previousMailboxPrimarySetAt!);
      if (age.inDays >= _mailboxTransitionDays) {
        _log.info('Mailbox transition: dropping old primary after $age');
        _previousMailboxPrimary = null;
        _previousMailboxPrimarySetAt = null;
        _saveMailboxTransition();
      }
    }

    // Request fragments from confirmed peers only (§4.4).
    final peers = node.routingTable.allPeers
        .where((p) => node.isPeerConfirmed(p.nodeIdHex))
        .toList();
    for (final peer in peers) {
      _requestFragments(peer, primaryMailboxId);
      _requestFragments(peer, fallbackMailboxId);
      // §5.6: poll old primary mailbox during key-rotation transition
      if (_previousMailboxPrimary != null) {
        _requestFragments(peer, _previousMailboxPrimary!);
      }
    }

    _log.info('Mailbox poll sent to ${peers.length} peers'
        '${_previousMailboxPrimary != null ? ' (+ transition primary)' : ''}');
  }

  void _requestFragments(PeerInfo peer, Uint8List mailboxId) {
    // V3 (Architecture §23.3): FRAGMENT_RETRIEVE is an infrastructure
    // message — route via DV cascade as InfrastructureFrame.
    final req = proto.FragmentRetrieve()..mailboxId = mailboxId;
    node.sendInfraTo(
      messageType: proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE,
      innerPayload: Uint8List.fromList(req.writeToBuffer()),
      recipientDeviceId: Uint8List.fromList(peer.nodeId),
    );
  }

  /// Send a single PEER_RETRIEVE to one peer.
  void _requestStoredMessages(PeerInfo peer) {
    // V3 (Architecture §23.3): PEER_RETRIEVE is an infrastructure message —
    // route via DV cascade as InfrastructureFrame.
    final retrieve = proto.PeerRetrieve()..requesterNodeId = identity.nodeId;
    node.sendInfraTo(
      messageType: proto.MessageTypeV3.MTV3_PEER_RETRIEVE,
      innerPayload: Uint8List.fromList(retrieve.writeToBuffer()),
      recipientDeviceId: Uint8List.fromList(peer.nodeId),
    );
  }

  /// §4.11: build RendezvousContact list from accepted contacts.
  List<RendezvousContact> _buildRendezvousContacts() {
    return _contacts.entries
        .where((e) => e.value.status == 'accepted' && e.value.ed25519Pk != null)
        .map((e) => RendezvousContact(
              userIdHex: e.key,
              foundingEd25519Pk: e.value.ed25519Pk!,
            ))
        .toList();
  }

  /// §4.11: notify rendezvous manager about contact list changes.
  void _updateRendezvousContacts() {
    _rendezvousManager?.updateContacts(_buildRendezvousContacts());
  }

  /// Edge-triggered offline-message retrieval. Fires once from
  /// [node.onDiscoveryComplete] after the §4.5 discovery cascade completes.
  void _onPostDiscoveryRetrieve() {
    _log.info('#U1 discovery-complete: starting one-shot offline retrieval');
    _postDiscoveryPolledPeers.clear();
    _pollConfirmedPeersOnce();
    _retryPendingContactRequests();
    _startCrRetryTimer();

    // §4.11: initial rendezvous publish + start periodic refresh (4h).
    _rendezvousManager?.publishForAllContacts();
    _rendezvousManager?.startPeriodicRefresh();

    // §4.11.10: resume persisted First-Contact rendezvous sessions
    // (republish records + re-arm owner polls). No-op without sessions.
    _fcRendezvous?.resumeSessions();

    // §9.5.7 (S119 D1): edge-triggered initial anti-entropy sync — a fresh
    // or long-offline node pulls the system-channel record sets once; the
    // hourly digest piggyback keeps it converged afterwards.
    final syncPeers = List<PeerInfo>.from(node.routingTable.allPeers)
      ..shuffle();
    sendSysChanDigests(syncPeers.take(_sysChanFanout));

    _postDiscoverySecondSweep?.cancel();
    _postDiscoverySecondSweep = Timer(const Duration(seconds: 15), () {
      _postDiscoverySecondSweep = null;
      final count = _pollConfirmedPeersOnce();
      if (count > 0) {
        _retryPendingContactRequests();
      }
      _log.info('#U1 second sweep complete '
          '(${_postDiscoveryPolledPeers.length} total peers polled)');
    });
  }

  /// Send FRAGMENT_RETRIEVE + PEER_RETRIEVE to all confirmed peers not
  /// yet polled (dedup via [_postDiscoveryPolledPeers]).
  int _pollConfirmedPeersOnce() {
    final sodium = SodiumFFI();
    final primaryMailboxId = sodium.sha256(Uint8List.fromList(
      [...utf8.encode('mailbox'), ...identity.ed25519PublicKey],
    ));
    final fallbackMailboxId = sodium.sha256(Uint8List.fromList(
      [...utf8.encode('mailbox-nid'), ...identity.nodeId],
    ));
    final newPeers = node.routingTable.allPeers
        .where((p) => node.isPeerConfirmed(p.nodeIdHex) &&
            _postDiscoveryPolledPeers.add(p.nodeIdHex))
        .toList();
    if (newPeers.isEmpty) return 0;
    for (final peer in newPeers) {
      _requestFragments(peer, primaryMailboxId);
      _requestFragments(peer, fallbackMailboxId);
      _requestStoredMessages(peer);
    }
    _log.info('#U1 polled ${newPeers.length} new peers '
        '(total ${_postDiscoveryPolledPeers.length})');
    return newPeers.length;
  }

  // ── Sending ────────────────────────────────────────────────────────

  /// Send a text message to a contact.
  @override
  Future<UiMessage?> sendTextMessage(String recipientUserIdHex, String text, {String? forwardedFrom, String? replyToMessageId, String? replyToText, String? replyToSender}) async {
    if (_reducedMode) {
      _log.warn('sendTextMessage blocked: reducedMode active');
      return null;
    }
    final contact = _contacts[recipientUserIdHex];
    if (contact == null || contact.status != 'accepted') {
      _log.warn('Cannot send to non-accepted contact: $recipientUserIdHex (contact=${contact != null}, status=${contact?.status})');
      return null;
    }

    _maybeWriteStaleContactWarning(recipientUserIdHex);

    // Optimistic UI msg.id is the wire messageId so DELIVERY_RECEIPT
    // (which carries inner.messageId) can match this local message and
    // upgrade `sent → delivered` in `_handleDeliveryReceiptV3`.
    final messageIdBytes = SodiumFFI().randomBytes(16);
    final messageIdHex = bytesToHex(messageIdBytes);
    final msg = UiMessage(
      id: messageIdHex,
      conversationId: recipientUserIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: UiMessageType.text,
      status: MessageStatus.sending,
      isOutgoing: true,
      forwardedFrom: forwardedFrom,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSender: replyToSender,
    );
    _addMessageToConversation(recipientUserIdHex, msg);

    // Yield to let UI repaint before heavy crypto work
    await Future.delayed(Duration.zero);

    // V3 sender path: build TextMessageV3 sub-message, hand to sendToUser
    // which does Inner-build/User-Sign/zstd/KEM-encrypt + Outer-build/
    // Device-Sign + per-device fan-out. Reply-fields and the sender-side
    // link-preview are wire-tagged on TextMessageV3 itself.

    // Sender-side link preview: fetched AFTER the message is sent, then
    // delivered as an edit/update so the send path is never blocked by DNS
    // or HTTP timeouts. The receiver-MUST-NOT-fetch invariant (CLAUDE.md)
    // is preserved — the preview still comes from the sender, just async.
    final hasUrl = _linkPreviewSettings.enabled && extractFirstUrl(text) != null;

    final tm = proto.TextMessageV3()
      ..text = text
      ..formatHint = 'plain';
    if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
      try {
        tm.replyToMessageId = hexToBytes(replyToMessageId);
      } catch (_) {
        // Non-hex (legacy) replyToMessageId — log + skip wire-tag, local-only.
        _log.debug(
            'sendTextMessage: replyToMessageId not hex — wire-tag dropped');
      }
      if (replyToText != null && replyToText.isNotEmpty) {
        // Bound the snippet so we don't bloat the frame.
        tm.replyToSnippet = replyToText.length > 120
            ? '${replyToText.substring(0, 120)}…'
            : replyToText;
      }
    }
    // §5.8: track L3 placement result via optional output parameter.
    final l3Out = [false];
    final sent = await sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageTypeV3.MTV3_TEXT,
      payload: tm.writeToBuffer(),
      messageId: messageIdBytes,
      l3Result: l3Out,
    );
    node.statsCollector.addMessageSent();

    // §5.8 status assignment:
    //   sent=true  → direct UDP dispatch succeeded → MessageStatus.sent
    //   sent=false + l3Out[0]=true  → L3 artefacts placed → queuedOffline
    //   sent=false + l3Out[0]=false → 0 connectivity, parked in outbox → failed
    msg.status = sent
        ? MessageStatus.sent
        : (l3Out[0] ? MessageStatus.queuedOffline : MessageStatus.failed);
    onStateChanged?.call();

    // Twin-Sync: notify other devices about sent message (§26)
    _sendTwinSync(proto.TwinSyncType.MESSAGE_SENT, Uint8List.fromList(utf8.encode(jsonEncode({
      'conversationId': recipientUserIdHex,
      'text': text,
      // V3: per-device fan-out generates messageIds inside sendToUser; for
      // twin-sync we use the optimistic temp-ID — twin receivers just dedup
      // on (conversationId, text, timestamp) anyway.
      'messageId': msg.id,
      'timestamp': msg.timestamp.millisecondsSinceEpoch,
    }))));

    // Async link-preview fetch: runs AFTER the message is sent so the
    // send path is never blocked by DNS/HTTP timeouts. On success, the
    // local UiMessage is updated and an EDIT envelope patches the preview
    // onto the already-delivered message at the receiver.
    if (hasUrl) {
      unawaited(_fetchAndDeliverLinkPreview(
        recipientUserIdHex, contact, msg, messageIdBytes, text,
      ));
    }

    return msg;
  }

  Future<void> _fetchAndDeliverLinkPreview(
    String recipientUserIdHex,
    ContactInfo contact,
    UiMessage msg,
    Uint8List messageIdBytes,
    String text,
  ) async {
    try {
      final preview = await _linkPreviewFetcher.fetchPreview(text);
      if (preview == null) return;
      msg.linkPreviewUrl = preview.url;
      msg.linkPreviewTitle = preview.title;
      msg.linkPreviewDescription = preview.description;
      msg.linkPreviewSiteName = preview.siteName;
      if (preview.thumbnail != null) {
        msg.linkPreviewThumbnailBase64 = base64Encode(preview.thumbnail!);
      }
      onStateChanged?.call();
      _saveConversations();
    } catch (e) {
      _log.debug('Async link preview fetch failed: $e');
    }
  }

  /// §5.8: Check if any queuedOffline messages in [conversationId] have
  /// exceeded the 7-day TTL and mark them [MessageStatus.expired].
  /// Pure local timestamp comparison — zero network traffic.
  @override
  void checkExpiredMessages(String conversationId) {
    _checkAndMarkExpired(conversationId);
  }

  /// §5.8: Re-send a message that has [MessageStatus.expired].
  ///
  /// Looks up the original message text, removes the old expired message,
  /// and queues a fresh send through [sendTextMessage]. The old message is
  /// replaced by the new one so the conversation stays coherent.
  @override
  Future<UiMessage?> resendExpiredMessage(
      String conversationId, String messageId) async {
    if (_reducedMode) {
      _log.warn('resendExpiredMessage blocked: reducedMode active');
      return null;
    }
    final conv = conversations[conversationId];
    if (conv == null) return null;
    final idx = conv.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return null;
    final original = conv.messages[idx];
    if (original.status != MessageStatus.expired) return null;
    if (!original.isOutgoing) return null;
    // Remove the expired entry from the outbox (if still there) and
    // the conversation, then re-send via the normal path.
    _outbox.remove(messageId);
    _saveOutbox();
    conv.messages.removeAt(idx);
    _saveConversations();
    return sendTextMessage(
      conversationId,
      original.text,
      replyToMessageId: original.replyToMessageId,
      replyToText: original.replyToText,
      replyToSender: original.replyToSender,
    );
  }

  /// Edit a previously sent message.
  @override
  Future<bool> editMessage(String conversationId, String messageId, String newText) async {
    if (_reducedMode) {
      _log.warn('editMessage blocked: reducedMode active');
      return false;
    }
    final conv = conversations[conversationId];
    if (conv == null) return false;

    final msgIndex = conv.messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return false;

    final original = conv.messages[msgIndex];

    // Only own messages
    if (!original.isOutgoing) return false;

    // Check edit window (per-chat config or default)
    final editWindowMs = conv.config.editWindowMs ?? _defaultEditWindowMs;
    final ageMs = DateTime.now().millisecondsSinceEpoch - original.timestamp.millisecondsSinceEpoch;
    if (ageMs > editWindowMs) {
      _log.warn('Edit rejected: message too old');
      return false;
    }

    // Cannot edit deleted messages
    if (original.isDeleted) return false;

    // Build edit payload (V3: identical sub-message; only the wrapping
    // changes — sendToUser handles compress/KEM/sign per device).
    final editMsg = proto.MessageEdit()
      ..originalMessageId = hexToBytes(messageId)
      ..newText = newText
      ..editTimestamp = Int64(DateTime.now().millisecondsSinceEpoch);
    final basePayload = Uint8List.fromList(editMsg.writeToBuffer());

    // Wire messageId == originalMessageId. Receiver-side dedup is then
    // idempotent (re-applying the same edit is a no-op), and the sender's
    // `_handleDeliveryReceiptV3` lookup can locate the original UiMessage
    // by the receipt's messageId. Status stays at delivered/read (edits
    // mutate an existing bubble; no `sent → delivered` transition required).
    final wireMessageId = hexToBytes(messageId);

    // Group or DM? V3 keeps pairwise fan-out (one sendToUser per member).
    // ApplicationFrameV3.group_id (Field 17) carries the conversation tag so
    // receivers dispatch the EDIT to the matching group/channel tab.
    final group = _groups[conversationId];
    bool anySent = false;

    if (group != null) {
      final groupIdBytes = hexToBytes(conversationId);
      final gmEpoch = group.membershipEpoch;
      final gmHash = _computeMembershipHash(gmEpoch, conversationId, group.members);
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final ok = await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageTypeV3.MTV3_EDIT,
          payload: basePayload,
          groupId: groupIdBytes,
          messageId: wireMessageId,
          groupMembershipEpoch: gmEpoch,
          groupMembershipHash: gmHash,
        );
        if (ok) anySent = true;
      }
    } else {
      final contact = _contacts[conversationId];
      if (contact == null || contact.status != 'accepted') return false;
      final sent = await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_EDIT,
        payload: basePayload,
        messageId: wireMessageId,
      );
      if (sent) anySent = true;
    }

    if (anySent) {
      // Apply locally
      original.text = newText;
      original.editedAt = DateTime.now();
      onStateChanged?.call();
      _saveConversations();
      _log.info('Message edited: $messageId');

      // Twin-Sync (§26)
      _sendTwinSync(proto.TwinSyncType.MESSAGE_EDITED, Uint8List.fromList(utf8.encode(jsonEncode({
        'conversationId': conversationId,
        'messageId': messageId,
        'text': newText,
      }))));
    }

    return anySent;
  }

  /// Delete a previously sent message.
  @override
  Future<bool> deleteMessage(String conversationId, String messageId) async {
    if (_reducedMode) {
      _log.warn('deleteMessage blocked: reducedMode active');
      return false;
    }
    final conv = conversations[conversationId];
    if (conv == null) return false;

    final msgIndex = conv.messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return false;

    final original = conv.messages[msgIndex];

    // Only own messages
    if (!original.isOutgoing) return false;

    // Already deleted
    if (original.isDeleted) return false;

    // §9.5.7 D2 (S119): system-channel posts are deleted via an author-
    // signed RETRACT tombstone that gossips with the record set (a plain
    // MTV3_DELETE could never reach "all subscribers" — there is no
    // member list). Deletion is unbounded (§14.6 — no time window).
    if (SystemChannels.isSystemChannel(conversationId)) {
      final stored = await _publishSystemChannelRecord(
        channelIdHex: conversationId,
        kind: SysChanKind.retract,
        targetRecordId: Uint8List.fromList(hexToBytes(messageId)),
      );
      if (stored == null) return false;
      // _applySysChanRetract (inside publish) marked the bridged message;
      // legacy pre-D1 local posts share the id and are covered too.
      if (!original.isDeleted) {
        original.text = '';
        original.isDeleted = true;
        _saveConversations();
      }
      onStateChanged?.call();
      _log.info('System-channel post retracted: $messageId');
      return true;
    }

    // Build delete payload (V3 wraps via sendToUser).
    final deleteMsg = proto.MessageDelete()
      ..messageId = hexToBytes(messageId)
      ..deletedAt = Int64(DateTime.now().millisecondsSinceEpoch);
    final basePayload = Uint8List.fromList(deleteMsg.writeToBuffer());

    // Wire messageId == target messageId. Same rationale as `editMessage`:
    // receiver dedup stays idempotent, and the sender's DELIVERY_RECEIPT
    // handler can find the local UiMessage via the receipt's messageId.
    final wireMessageId = hexToBytes(messageId);

    final group = _groups[conversationId];
    bool anySent = false;

    if (group != null) {
      // Pairwise fan-out per member (V3 keeps the same model).
      final groupIdBytes = hexToBytes(conversationId);
      final gmEpoch = group.membershipEpoch;
      final gmHash = _computeMembershipHash(gmEpoch, conversationId, group.members);
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final ok = await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageTypeV3.MTV3_DELETE,
          payload: basePayload,
          groupId: groupIdBytes,
          messageId: wireMessageId,
          groupMembershipEpoch: gmEpoch,
          groupMembershipHash: gmHash,
        );
        if (ok) anySent = true;
      }
    } else {
      final contact = _contacts[conversationId];
      if (contact == null || contact.status != 'accepted') return false;
      final sent = await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_DELETE,
        payload: basePayload,
        messageId: wireMessageId,
      );
      if (sent) anySent = true;
    }

    if (anySent) {
      // Apply locally
      original.text = '';
      original.isDeleted = true;
      onStateChanged?.call();
      _saveConversations();
      _log.info('Message deleted: $messageId');

      // Twin-Sync (§26)
      _sendTwinSync(proto.TwinSyncType.MESSAGE_DELETED, Uint8List.fromList(utf8.encode(jsonEncode({
        'conversationId': conversationId,
        'messageId': messageId,
      }))));
    }

    return anySent;
  }

  @override
  Future<bool> updateChatConfig(String conversationId, ChatConfig config) async {
    final conv = conversations[conversationId];
    if (conv == null) return false;

    // For groups: owner or admin can set directly
    final group = _groups[conversationId];
    if (group != null) {
      if (!_hasGroupPermission(group, 'config')) return false;
      conv.config = config;
      _saveConversations();
      // Broadcast config to all group members
      _broadcastGroupConfigUpdate(group, config);
      onStateChanged?.call();
      _log.info('Group chat config updated for "${group.name}"');
      return true;
    }

    // For channels: owner or admin can set directly
    final channel = _channels[conversationId];
    if (channel != null) {
      if (!_hasChannelPermission(channel, 'config')) return false;
      conv.config = config;
      _saveConversations();
      _broadcastChannelConfigUpdate(channel, config);
      onStateChanged?.call();
      _log.info('Channel chat config updated for "${channel.name}"');
      return true;
    }

    // For DMs: send config update proposal to peer — NOT active until accepted
    final contact = _contacts[conversationId];
    if (contact == null || contact.status != 'accepted') return false;

    // Store as pending on our side too (active only after peer accepts)
    conv.pendingConfigProposal = config;
    conv.pendingConfigProposer = identity.userIdHex;
    _saveConversations();

    _sendChatConfigUpdate(contact, conversationId, config, isRequest: true);
    onStateChanged?.call();
    _log.info('Chat config proposal sent to ${contact.displayName}');
    return true;
  }

  /// Accept a pending DM config proposal.
  @override
  Future<bool> acceptConfigProposal(String conversationId) async {
    final conv = conversations[conversationId];
    if (conv == null || conv.pendingConfigProposal == null) return false;
    if (conv.isGroup || conv.isChannel) return false; // Groups/Channels don't use proposals

    final proposedConfig = conv.pendingConfigProposal!;

    // Apply the config locally
    conv.config = proposedConfig;
    conv.pendingConfigProposal = null;
    conv.pendingConfigProposer = null;
    _saveConversations();

    // Send acceptance to the proposer
    final contact = _contacts[conversationId];
    if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
      _sendChatConfigUpdate(contact, conversationId, proposedConfig, isRequest: false, accepted: true);
    }

    onStateChanged?.call();
    _log.info('DM config proposal accepted for ${contact?.displayName ?? conversationId.substring(0, 8)}');
    return true;
  }

  /// Reject a pending DM config proposal.
  @override
  Future<bool> rejectConfigProposal(String conversationId) async {
    final conv = conversations[conversationId];
    if (conv == null || conv.pendingConfigProposal == null) return false;
    if (conv.isGroup || conv.isChannel) return false;

    final rejectedConfig = conv.pendingConfigProposal!;

    // Clear the pending proposal
    conv.pendingConfigProposal = null;
    conv.pendingConfigProposer = null;
    _saveConversations();

    // Send rejection to the proposer
    final contact = _contacts[conversationId];
    if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
      _sendChatConfigUpdate(contact, conversationId, rejectedConfig, isRequest: false, accepted: false);
    }

    onStateChanged?.call();
    _log.info('DM config proposal rejected for ${contact?.displayName ?? conversationId.substring(0, 8)}');
    return true;
  }

  /// Forward a message to another conversation.
  @override
  Future<UiMessage?> forwardMessage(String sourceConversationId, String messageId, String targetConversationId) async {
    if (_reducedMode) {
      _log.warn('forwardMessage blocked: reducedMode active');
      return null;
    }
    // Check allowForwarding on source conversation
    final sourceConv = conversations[sourceConversationId];
    if (sourceConv != null && !sourceConv.config.allowForwarding) {
      _log.warn('Forward blocked: allowForwarding=false for $sourceConversationId');
      return null;
    }

    // Find the original message
    final msg = sourceConv?.messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null || msg.isDeleted) return null;

    // Determine original sender name for attribution
    final originalSenderName = msg.isOutgoing
        ? displayName
        : (_contacts[msg.senderNodeIdHex]?.effectiveName ?? msg.senderNodeIdHex.substring(0, 8));

    // Check if this is a media message with a local file
    if (msg.isMedia && msg.filePath != null && File(msg.filePath!).existsSync()) {
      // Forward media: re-send the file to the target
      final result = await sendMediaMessage(targetConversationId, msg.filePath!);
      if (result != null) {
        result.forwardedFrom = originalSenderName;
        _saveConversations();
      }
      return result;
    }

    // Text-only forward
    final forwardText = msg.text;

    // Send to target with forwardedFrom attribution
    final isGroupTarget = _groups.containsKey(targetConversationId);
    final isChannelTarget = _channels.containsKey(targetConversationId);
    UiMessage? result;
    if (isChannelTarget) {
      result = await sendChannelPost(targetConversationId, forwardText);
      if (result != null) {
        result.forwardedFrom = originalSenderName;
        _saveConversations();
      }
    } else if (isGroupTarget) {
      result = await sendGroupTextMessage(targetConversationId, forwardText);
      if (result != null) {
        result.forwardedFrom = originalSenderName;
        _saveConversations();
      }
    } else {
      result = await sendTextMessage(targetConversationId, forwardText, forwardedFrom: originalSenderName);
    }

    return result;
  }

  /// Send a CHAT_CONFIG_UPDATE message to a contact (V3).
  void _sendChatConfigUpdate(ContactInfo contact, String conversationId,
      ChatConfig config,
      {required bool isRequest, bool accepted = false, String? groupIdHex}) {
    final configMsg = proto.ChatConfigUpdate()
      ..conversationId = conversationId
      ..allowDownloads = config.allowDownloads
      ..allowForwarding = config.allowForwarding
      ..readReceipts = config.readReceipts
      ..typingIndicators = config.typingIndicators
      ..isRequest = isRequest
      ..accepted = accepted;
    if (config.editWindowMs != null) {
      configMsg.editWindowMs = Int64(config.editWindowMs!);
    }
    if (config.expiryDurationMs != null) {
      configMsg.expiryDurationMs = Int64(config.expiryDurationMs!);
    }
    sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageTypeV3.MTV3_CHAT_CONFIG_UPDATE,
      payload: Uint8List.fromList(configMsg.writeToBuffer()),
      groupId: groupIdHex != null ? hexToBytes(groupIdHex) : null,
    );
  }

  /// Resolve best available encryption keys for a group/channel member.
  /// Prefers contact keys (most up-to-date), falls back to member keys.
  (Uint8List?, Uint8List?) _resolveMemberKeys(String nodeIdHex, {Uint8List? memberX25519Pk, Uint8List? memberMlKemPk}) {
    final contact = _contacts[nodeIdHex];
    if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
      return (contact.x25519Pk!, contact.mlKemPk!);
    }
    if (memberX25519Pk != null && memberX25519Pk.isNotEmpty &&
        memberMlKemPk != null && memberMlKemPk.isNotEmpty) {
      return (memberX25519Pk, memberMlKemPk);
    }
    return (null, null);
  }

  /// Broadcast a config update to all group members (pairwise KEM).
  void _broadcastGroupConfigUpdate(GroupInfo group, ChatConfig config) {
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;

      final contact = _contacts[member.nodeIdHex];
      if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
        _sendChatConfigUpdate(contact, group.groupIdHex, config, isRequest: false, groupIdHex: group.groupIdHex);
      }
    }
    _log.info('Broadcast config update for "${group.name}" to ${group.members.length - 1} members');
  }

  /// Broadcast a config update to all channel members (pairwise KEM).
  void _broadcastChannelConfigUpdate(ChannelInfo channel, ChatConfig config) {
    for (final member in channel.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;

      final contact = _contacts[member.nodeIdHex];
      if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
        _sendChatConfigUpdate(contact, channel.channelIdHex, config, isRequest: false, groupIdHex: channel.channelIdHex);
      }
    }
    _log.info('Broadcast config update for channel "${channel.name}" to ${channel.members.length - 1} members');
  }

  /// Store erasure-coded backup of an envelope on DHT peers near the recipient's mailbox.
  /// Works with ContactInfo (uses ed25519Pk for mailbox) or plain nodeId (fallback).
  /// Reed-Solomon offline-delivery (Architecture §5.4): split the canonical
  /// `NetworkPacketV3` wire bytes [packetBytes] into N=10 fragments (K=7
  /// reassemble threshold) and FRAGMENT_STORE them onto the K=10 closest
  /// DHT replicators of the recipient's mailbox.
  ///
  /// The recipient mailbox is keyed by the user's Ed25519 pubkey for
  /// AppFrame payloads (`recipientUserEd25519Pk` non-null); for InfraFrame
  /// payloads where the recipient is a specific device (RESTORE_BROADCAST,
  /// Emergency KEY_ROTATION_BROADCAST), the mailbox derives from the
  /// recipient's user node-ID via the `mailbox-nid` salt, since the
  /// recipient may not have published its Device-KEM-PK yet at offline-time.
  /// [messageId] is the packet's end-to-end identifier (16-byte UUID v4),
  /// used by the receiver's reassembly buffer to gather all 10 fragments
  /// of the same logical send.
  ///
  /// ACK-verified placement (S123 Erasure-F1): wave 1 sends N=10 fragments
  /// x min(3, P) replicas to the P closest DHT replicators exactly like the
  /// pre-F1 fire-and-forget placement, then waits (Completer + 8s timeout,
  /// [_peerStoreAckTimeout], reused from the S&F F1 pattern) for
  /// FRAGMENT_STORE_ACKs. Up to 2 retry waves target only the fragment
  /// indices still unconfirmed, drawing fresh candidates from a deeper pool
  /// (count:30) — see [ErasurePlacementCoordinator]. Success = at least
  /// K=[ReedSolomon.defaultK] distinct fragment indices confirmed.
  /// Returns true iff K-of-N placement was ACK-confirmed within the wave
  /// budget. Returns false when no DHT replicators are reachable at all, or
  /// when fewer than K indices could be confirmed (truly offline / eclipse).
  Future<bool> _distributeErasureFragments({
    required Uint8List packetBytes,
    required Uint8List messageId,
    Uint8List? recipientUserEd25519Pk,
    Uint8List? recipientUserNodeId,
  }) async {
    try {
      final sodium = SodiumFFI();
      final Uint8List mailboxId;
      if (recipientUserEd25519Pk != null && recipientUserEd25519Pk.isNotEmpty) {
        mailboxId = sodium.sha256(Uint8List.fromList(
            [...utf8.encode('mailbox'), ...recipientUserEd25519Pk]));
      } else if (recipientUserNodeId != null && recipientUserNodeId.isNotEmpty) {
        mailboxId = sodium.sha256(Uint8List.fromList(
            [...utf8.encode('mailbox-nid'), ...recipientUserNodeId]));
      } else {
        _log.debug('Erasure offline-delivery skipped: no recipient pk/node-id');
        return false;
      }

      final rs = ReedSolomon();
      final fragments = rs.encode(packetBytes);
      // D4 (§4.3): subnet-diverse replicator selection (same store/retrieve
      // pattern as the identity records — eclipse cost binding).
      final initialPeers = node.routingTable.findClosestPeers(mailboxId,
          count: 10, maxPerIpGroup: RoutingTable.diversityMaxPerIpGroup);
      if (initialPeers.isEmpty) {
        _log.debug('Erasure offline-delivery skipped: no DHT replicators known');
        return false;
      }

      final msgIdHex = bytesToHex(messageId);

      Future<bool> sendAndWait(int fragmentIndex, PeerInfo peer) async {
        final fragStore = proto.FragmentStore()
          ..mailboxId = mailboxId
          ..messageId = messageId
          ..fragmentIndex = fragmentIndex
          ..totalFragments = fragments.length
          ..requiredFragments = ReedSolomon.defaultK
          ..fragmentData = fragments[fragmentIndex]
          ..originalSize = packetBytes.length;
        final key = '$msgIdHex:$fragmentIndex';
        // Multiple replicas of the SAME fragment index (within or across
        // waves) share one Completer: FragmentStoreAck carries only
        // (messageId, fragmentIndex) — no per-send correlation id — so any
        // one ACK for this index resolves every in-flight wait for it.
        final completer =
            _pendingFragmentStoreAcks.putIfAbsent(key, () => Completer<void>());
        unawaited(node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_FRAGMENT_STORE,
          innerPayload: Uint8List.fromList(fragStore.writeToBuffer()),
          recipientDeviceId: Uint8List.fromList(peer.nodeId),
        ));
        try {
          await completer.future.timeout(_peerStoreAckTimeout);
          return true;
        } on TimeoutException {
          return false;
        }
      }

      final coordinator = ErasurePlacementCoordinator<PeerInfo>(
        totalFragments: fragments.length,
        requiredFragments: ReedSolomon.defaultK,
        peerId: (p) => p.nodeIdHex,
        isPeerConfirmed: (p) => node.isPeerConfirmed(p.nodeIdHex),
      );
      final result = await coordinator.run(
        initialPool: initialPeers,
        deeperPool: () => node.routingTable.findClosestPeers(mailboxId,
            count: 30, maxPerIpGroup: RoutingTable.diversityMaxPerIpGroup),
        sendAndWait: sendAndWait,
      );

      // Aufraeumen nach Abschluss (kein Leak): every wait for this
      // messageId's Completers has already resolved by the time
      // `coordinator.run()` returns (each wave `await`s Future.wait before
      // the next starts), so it's safe to drop any remaining entries —
      // a late/duplicate ACK arriving afterwards is a harmless no-op in
      // `handleIncomingFragmentStoreAckInfra`.
      for (var i = 0; i < fragments.length; i++) {
        _pendingFragmentStoreAcks.remove('$msgIdHex:$i');
      }

      if (result.success) {
        if (result.fragile) {
          _log.warn('Erasure placement fragile '
              '(${result.confirmedCount}/${result.totalFragments} indices confirmed)');
        } else {
          _log.info('Erasure: ${result.confirmedCount}/${result.totalFragments} '
              'indices confirmed');
        }
        return true;
      }
      _log.info('Erasure placement FAILED: '
          '${result.confirmedCount}/${result.totalFragments} indices confirmed');
      return false;
    } catch (e) {
      _log.debug('Erasure offline-delivery failed: $e');
      return false;
    }
  }

  /// §5.4 (S123 Erasure-F1): pending FRAGMENT_STORE ACKs keyed by
  /// `'<messageIdHex>:<fragmentIndex>'`. Distinct from
  /// [_pendingPeerStoreAcks] (S&F path, keyed by a random per-send storeId)
  /// because `FragmentStoreAck` carries no correlation id beyond
  /// (messageId, fragmentIndex) — replicas of the same index share one
  /// Completer.
  final Map<String, Completer<void>> _pendingFragmentStoreAcks = {};

  /// Routed from the InfraFrame dispatchers. Resolves the sender-side
  /// per-fragment-index ACK wait started by `_distributeErasureFragments`
  /// AND drives the proactive-push retry-cancel path (`onProactivePushAcked`)
  /// — both concerns share this one FRAGMENT_STORE_ACK observation point
  /// since S123 Erasure-F1 (previously `onProactivePushAcked` was wired via
  /// the now-removed `CleonaNode.onFragmentStoreAck` hook, which was never
  /// invoked because the type was swallowed by the DhtRpc bridge before
  /// S123).
  void handleIncomingFragmentStoreAckInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final ack = proto.FragmentStoreAck.fromBuffer(frame.payload);
      final messageId = Uint8List.fromList(ack.messageId);
      final msgIdHex = bytesToHex(messageId);
      final key = '$msgIdHex:${ack.fragmentIndex}';
      final pending = _pendingFragmentStoreAcks.remove(key);
      if (pending != null && !pending.isCompleted) {
        pending.complete();
      }
      onProactivePushAcked(messageId, ack.fragmentIndex);
    } catch (_) {/* malformed ACK — ignore */}
  }

  // ── §5.1 L1 Direct Retry (AckTracker timeout) ─────────────────────

  Future<void> _handleRetryNeeded(
      String messageIdHex, Uint8List serializedPacket, Uint8List recipientUserId) async {
    final recipientHex = bytesToHex(recipientUserId);
    _log.info('L1 direct retry for ${messageIdHex.substring(0, 8)} '
        '→ ${recipientHex.substring(0, 8)}');

    final devices = await node.identityResolver.resolve(recipientUserId);
    if (devices.isEmpty) {
      _log.debug('L1 retry: no devices resolved for ${recipientHex.substring(0, 8)}');
      return;
    }

    for (final dev in devices) {
      if (dev.addresses.isNotEmpty) {
        var peer = node.routingTable.getPeer(dev.deviceNodeId);
        if (peer == null) {
          peer = PeerInfo(nodeId: dev.deviceNodeId, userId: recipientUserId);
          for (final addr in dev.addresses) {
            peer.addresses.add(addr);
          }
          node.routingTable.addPeer(peer);
        } else {
          for (final addr in dev.addresses) {
            final key = '${addr.ip}:${addr.port}';
            if (!peer.addresses.any((a) => '${a.ip}:${a.port}' == key)) {
              peer.addresses.add(addr);
            }
          }
          node.routingTable.addPeer(peer);
        }
      }
    }

    final packet = proto.NetworkPacketV3.fromBuffer(serializedPacket);
    for (final dev in devices) {
      final ok = await node.sendToDevice(packet, dev.deviceNodeId);
      if (ok) {
        _log.info('L1 retry: direct delivery OK for '
            '${messageIdHex.substring(0, 8)} → re-tracking ACK');
        unawaited(node.ackTracker.trackSend(
          messageIdHex,
          recipientHex,
          const <PeerAddress>[],
          AckTracker.computeTimeout(node.dhtRpc.getRtt(recipientUserId)),
          serializedPacket: serializedPacket,
          recipientUserId: recipientUserId,
        ));
        return;
      }
    }
    _log.debug('L1 retry: all devices unreachable for ${recipientHex.substring(0, 8)}');
  }

  // ── §5.1 Layer 3: Offline Cascade ──────────────────────────────────

  Future<void> _handleRetryExhausted(
      String messageIdHex, Uint8List serializedPacket, Uint8List recipientUserId) async {
    _log.info('Offline cascade for message $messageIdHex '
        '→ ${_hexShort(recipientUserId)}');
    final recipientHex = bytesToHex(recipientUserId);
    final contact = _contacts[recipientHex];

    // §5.4: Erasure-coded backup on DHT
    final fragmentBundleId =
        SodiumFFI().sha256(serializedPacket).sublist(0, 16);
    final erasureOk = await _distributeErasureFragments(
      packetBytes: serializedPacket,
      messageId: fragmentBundleId,
      recipientUserEd25519Pk: contact?.ed25519Pk,
      recipientUserNodeId: recipientUserId,
    );

    // §5.5: S&F copy on mutual peers (S121 F1: ACK-verified placement)
    final safOk = await _storeSafOnContactPeers(
      recipientUserId: recipientUserId,
      wrappedEnvelope: serializedPacket,
    );

    if (erasureOk || safOk) {
      _updateMessageStatusById(
          messageIdHex, recipientHex, MessageStatus.queuedOffline);
    } else {
      // Neither erasure nor S&F succeeded — park in outbox for retry on
      // next network-change edge (the outbox flush runs L1→L2→L3).
      _addToOutbox(
        messageIdHex: messageIdHex,
        recipientUserIdHex: recipientHex,
        recipientEd25519PkHex:
            contact?.ed25519Pk != null ? bytesToHex(contact!.ed25519Pk!) : null,
        canonicalPacket: serializedPacket,
      );
      _log.warn('Offline cascade failed (erasure=$erasureOk, saf=$safOk) '
          '— $messageIdHex parked in outbox');
    }
  }

  /// §5.5 F4(a) (S121): infrastructure-node S&F policy — when true, this
  /// node stores PEER_STORE messages for ANY recipient (within budgets),
  /// not only for its own accepted contacts. Set by headless/bootstrap
  /// runners; GUI daemons and mobile devices keep contact-only storage.
  bool acceptAnyPeerStore = false;

  /// §5.5 (S121 F1): pending PEER_STORE ACKs keyed by storeIdHex. The
  /// storage peer answers every store with `PEER_STORE_ACK{accepted}` —
  /// accepted=false when the recipient is not ITS accepted contact
  /// (receiver-enforced mutuality, §5.5 criterion 3).
  final Map<String, Completer<bool>> _pendingPeerStoreAcks = {};

  /// Per-store ACK wait. 8 s covers relay paths (min relay ACK budget §2).
  static const Duration _peerStoreAckTimeout = Duration(seconds: 8);

  /// §5.5 target redundancy: confirmed copies we aim for per message.
  static const int _safTargetCopies = 3;

  /// Routed from the InfraFrame dispatchers (was silently dropped before
  /// S121 F1 — the sender could never distinguish accepted from rejected
  /// or lost stores).
  void handleIncomingPeerStoreAckInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final ack = proto.PeerStoreAck.fromBuffer(frame.payload);
      final storeIdHex = bytesToHex(Uint8List.fromList(ack.storeId));
      final pending = _pendingPeerStoreAcks.remove(storeIdHex);
      if (pending != null && !pending.isCompleted) {
        pending.complete(ack.accepted);
      }
    } catch (_) {/* malformed ACK — ignore */}
  }

  /// §5.5: Store a complete message copy on mutual peers with ACK-verified
  /// placement (S121 F1). Spec: "the sender detects [a rejected store] via
  /// a missing PEER_STORE_ACK and can try the next candidate."
  ///
  /// Sends in waves toward [_safTargetCopies] confirmed copies, drawing
  /// fresh candidates per wave until the pool is dry. Success = at least
  /// one storage peer ACCEPTED. Pre-F1 this was fire-and-forget and
  /// returned true for merely attempting — the cascade then reported
  /// queuedOffline although every store had been rejected or lost
  /// (field evidence 2026-07-03, Martin→Eierphone).
  Future<bool> _storeSafOnContactPeers({
    required Uint8List recipientUserId,
    required Uint8List wrappedEnvelope,
  }) async {
    // Draw a deep candidate pool (3 waves worth) so rejected stores can
    // fall through to the next candidates per spec.
    final pool = _findContactPeerDeviceIds(recipientUserId,
        limit: _safTargetCopies * 3);
    if (pool.isEmpty) {
      _log.debug('S&F: no mutual peers for ${_hexShort(recipientUserId)}');
      return false;
    }

    var accepted = 0;
    var attempted = 0;
    var cursor = 0;
    while (accepted < _safTargetCopies && cursor < pool.length) {
      final need = _safTargetCopies - accepted;
      final wave = pool.skip(cursor).take(need).toList();
      cursor += wave.length;

      final waits = <Future<bool>>[];
      for (final deviceId in wave) {
        final sid = SodiumFFI().randomBytes(16);
        final sidHex = bytesToHex(sid);
        final peerStore = proto.PeerStore()
          ..recipientNodeId = recipientUserId
          ..wrappedEnvelope = wrappedEnvelope
          ..storeId = sid
          ..ttlMs = Int64(PeerMessageStore.defaultTtlMs);
        final completer = Completer<bool>();
        _pendingPeerStoreAcks[sidHex] = completer;
        attempted++;
        unawaited(node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_PEER_STORE,
          innerPayload: Uint8List.fromList(peerStore.writeToBuffer()),
          recipientDeviceId: deviceId,
        ));
        waits.add(completer.future.timeout(_peerStoreAckTimeout,
            onTimeout: () {
          _pendingPeerStoreAcks.remove(sidHex);
          return false;
        }));
      }
      final results = await Future.wait(waits);
      accepted += results.where((ok) => ok).length;
    }

    if (accepted == 0) {
      _log.warn('S&F: 0/$attempted stores ACCEPTED for '
          '${_hexShort(recipientUserId)} — placement failed');
      return false;
    }
    if (accepted < _safTargetCopies) {
      _log.warn('S&F: only $accepted/$_safTargetCopies confirmed stores for '
          '${_hexShort(recipientUserId)} ($attempted attempted) — '
          'offline delivery fragile');
    } else {
      _log.info('S&F: $accepted confirmed stores for '
          '${_hexShort(recipientUserId)} ($attempted attempted)');
    }
    return true;
  }

  /// §5.5: Find contacts that are likely mutual peers (both sender and
  /// recipient know them). Heuristic: accepted contacts with a known
  /// deviceNodeId in the routing table (i.e. online and reachable).
  /// Excludes the recipient itself.
  List<Uint8List> _findContactPeerDeviceIds(Uint8List recipientUserId, {int limit = 3}) {
    final recipientHex = bytesToHex(recipientUserId);
    final selfDeviceHex = bytesToHex(identity.nodeId);
    final candidates = <(Uint8List, int)>[];
    final seen = <String>{};

    // Phase 1: accepted contacts (high confidence mutual). S121 F2: rank
    // confirmed peers (bidirectional UDP within TTL) far above merely
    // alive-routed ones — stale relay routes are never pruned without
    // traffic, so `isAlive` alone selected devices that had been offline
    // for days (field evidence 2026-07-03: S&F copy on a 6-days-dead
    // device; the §5.5 receiver-pull then never finds the message).
    for (final entry in _contacts.entries) {
      if (entry.key == recipientHex) continue;
      final c = entry.value;
      if (c.status != 'accepted') continue;
      if (c.deviceNodeIds.isEmpty) continue;
      for (final devHex in c.deviceNodeIds) {
        final devBytes = hexToBytes(devHex);
        final peer = node.routingTable.getPeer(devBytes);
        if (peer == null) continue;
        final confirmed = node.isPeerConfirmed(devHex);
        final routes = node.dvRouting.routesTo(devHex);
        final aliveCount = routes.where((r) => r.isAlive).length;
        if (confirmed || aliveCount > 0) {
          candidates.add((devBytes, (confirmed ? 1000 : 0) + aliveCount));
          seen.add(devHex);
          break;
        }
      }
    }

    // Phase 2: routing table peers (e.g. Bootstrap) as fallback candidates.
    // Always appended — Phase 1 contacts may all reject the store (recipient
    // is not THEIR contact), so infra nodes with acceptAnyPeerStore must be
    // in the pool for wave-retry to reach them (S142 RCA: Bootstrap was never
    // tried because isEmpty guard blocked Phase 2 when Phase 1 had contacts).
    {
      final rtFallback = <(Uint8List, int)>[];
      for (final peer in node.routingTable.allPeers) {
        final peerHex = peer.nodeIdHex;
        if (peerHex == recipientHex || peerHex == selfDeviceHex) continue;
        if (seen.contains(peerHex)) continue;
        if (!node.isPeerConfirmed(peerHex)) continue;
        final routes = node.dvRouting.routesTo(peerHex);
        final aliveCount = routes.where((r) => r.isAlive).length;
        if (aliveCount > 0) {
          rtFallback.add((Uint8List.fromList(peer.nodeId), aliveCount));
        }
      }
      rtFallback.sort((a, b) => b.$2.compareTo(a.$2));
      candidates.addAll(rtFallback.take(limit));
    }

    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    return candidates.take(limit).map((c) => c.$1).toList();
  }

  /// Add peers from a scanned ContactSeed QR code to the routing table.
  /// This ensures the target node and its seed peers are reachable before sending a CR.
  ///
  /// Welle 5/6 (§8.1.1): when [targetDeviceIdHex] + Device-KEM keys are
  /// supplied (newer ContactSeed-URIs include them), the target peer is
  /// indexed by its Device-Node-ID instead of User-ID, and a direct
  /// DV-route is registered. This is what unblocks `sendToDevice` for the
  /// First-CR InfraFrame — without it, `cascade exhausted (routes=0)`
  /// because DV-routing keys on Device-IDs while legacy seeds added the
  /// peer under the User-ID. [targetDxkB64] / [targetDmkB64] (v1 legacy)
  /// or [targetEpB64] (v2 rev3 trust-anchor) from ContactSeed.
  @override
  void addPeersFromContactSeed(
    String targetNodeIdHex,
    List<String> targetAddresses,
    List<({String nodeIdHex, List<String> addresses})> seedPeers, {
    String? targetDeviceIdHex,
    String? targetDxkB64,
    String? targetDmkB64,
    String? targetEpB64,
    String? targetRendezvousNonceB64,
  }) {
    // Add the target node itself — always, even without addresses.
    // Without addresses the Three-Layer Cascade will relay via seed peers.
    final targetUserId = hexToBytes(targetNodeIdHex);
    final hasDeviceId = targetDeviceIdHex != null && targetDeviceIdHex.isNotEmpty;
    final routingNodeId = hasDeviceId ? hexToBytes(targetDeviceIdHex) : targetUserId;
    final addresses = <PeerAddress>[];
    for (final addr in targetAddresses) {
      final parsed = _parseAddrString(addr);
      if (parsed != null) {
        addresses.add(PeerAddress(ip: parsed.$1, port: parsed.$2));
      }
    }
    final targetPeer = PeerInfo(nodeId: routingNodeId, addresses: addresses)
      ..userId = hasDeviceId ? targetUserId : null
      ..isProtectedSeed = true; // Survive Doze pruning (§27)
    node.routingTable.addPeer(targetPeer);
    if (hasDeviceId) {
      // Do NOT add the target as a DV direct-neighbor here. If the target
      // is reachable (same LAN), the PING below will get a PONG which
      // establishes the direct route naturally. If the target is NOT
      // reachable (cross-network/CGNAT), a premature direct-neighbor entry
      // causes sendToDevice to fire-and-forget via UDP to the unreachable
      // private IP — which "succeeds" locally and prevents the relay
      // cascade from ever trying Bootstrap as relay.
      //
      // Welle 5/6 (§4.3 / §3.5b): prime the DeviceKemRecord cache so
      // `_buildInfraPacket → _lookupDeviceKemPk` hits the canonical path [1]
      // for this device. The seed-derived record carries no User-Sig (we
      // don't hold the contact's user-Ed25519-Sk yet), but handleKemPublish
      // does not verify — the wire-layer does that on a real
      // IDENTITY_KEM_PUBLISH. sequenceNumber=0 means a real publish will
      // strictly supersede this seed.
      if (targetDxkB64 != null && targetDmkB64 != null) {
        try {
          final dxk = base64Decode(targetDxkB64);
          final dmk = base64Decode(targetDmkB64);
          final primed = DeviceKemRecord(
            userId: targetUserId,
            deviceId: routingNodeId,
            deviceX25519Pk: dxk,
            deviceMlKemPk: dmk,
            ttlSeconds: 24 * 3600,
            sequenceNumber: 0,
            publishedAtMs: DateTime.now().millisecondsSinceEpoch,
            userEd25519Pk: Uint8List(0),
            ed25519Sig: Uint8List(0),
          );
          node.identityDhtHandler.handleKemPublish(primed);
        } catch (e) {
          _log.warn('QR seed: malformed dxk/dmk — DKR cache not primed: $e');
        }
      }
      final hasDkr = targetDxkB64 != null && targetDmkB64 != null;
      final hasEp = targetEpB64 != null;
      _log.info('QR seed: added target user=${targetNodeIdHex.substring(0, 8)} '
          'device=${targetDeviceIdHex.substring(0, 8)} '
          'with ${addresses.length} addresses'
          '${hasDkr ? " + DKR cache" : hasEp ? " + ep trust-anchor" : " (no keys)"}'
          ' (protected, no DV-neighbor)');
    } else {
      _log.info('QR seed: added target ${targetNodeIdHex.substring(0, 8)} '
          'with ${addresses.length} addresses (protected, legacy URI)');
    }

    // Ping the target's own addresses — the target was added to the routing
    // table above but no PONG cycle was kicked off (unlike seed peers below).
    for (final addr in addresses) {
      node.sendPing(addr.ip, addr.port);
    }

    // Add seed peers (bootstrap, mutual contacts, etc.)
    for (final sp in seedPeers) {
      final peerNodeId = hexToBytes(sp.nodeIdHex);
      final spAddresses = <PeerAddress>[];
      for (final addr in sp.addresses) {
        final parsed = _parseAddrString(addr);
        if (parsed != null) {
          spAddresses.add(PeerAddress(ip: parsed.$1, port: parsed.$2)..score = 0.95);
        }
      }
      if (spAddresses.isNotEmpty) {
        final seedPeer = PeerInfo(nodeId: peerNodeId, addresses: spAddresses)
          ..isProtectedSeed = true; // Survive Doze pruning (§27)
        node.routingTable.addPeer(seedPeer);
        // Seed peers must be DV neighbors so they can serve as default gateway
        // for the First-CR when no direct route to the target exists yet.
        node.dvRouting.addDirectNeighbor(peerNodeId, ConnectionType.publicUdp);
        _log.info('QR seed: added peer ${sp.nodeIdHex.substring(0, 8)} with ${spAddresses.length} addresses + DV neighbor (protected)');
        // Ping seed peer to establish connection
        for (final addr in spAddresses) {
          node.sendPing(addr.ip, addr.port);
        }
      }
    }

    // Elect default gateway now that seed peers are DV neighbors — ensures
    // sendToDevice has a last-resort relay path for the First-CR even if
    // no PONG has arrived yet.
    node.dvRouting.updateDefaultGateway();

    // §4.11.10 First-Contact Rendezvous, scanner side: a pasted URI carries
    // the `r` nonce → resolve the owner-tag (fresher addresses than `a=`),
    // publish our own EndpointRecord under the scanner-tag, and let the
    // existing CR retry re-resolve before each attempt.
    if (targetRendezvousNonceB64 != null && hasDeviceId) {
      try {
        final nonce = Uint8List.fromList(
            base64Url.decode(base64Url.normalize(targetRendezvousNonceB64)));
        _fcRendezvous?.startScannerSession(
            nonce, targetNodeIdHex.toLowerCase(), targetDeviceIdHex);
      } catch (e) {
        _log.warn('FC-RV: malformed rendezvous nonce in ContactSeed — '
            'scanner session not started: $e');
      }
    }
  }

  /// §4.11.10 First-Contact Rendezvous, owner side: the UI copied/shared a
  /// ContactSeed-URI carrying the given `r` nonce (base64url). Starts (or
  /// resumes — idempotent per nonce) the owner session: publish own
  /// EndpointRecord under the owner-tag + poll the scanner-tag.
  @override
  void notifyContactSeedUriShared(String rendezvousNonceB64) {
    try {
      final nonce = Uint8List.fromList(
          base64Url.decode(base64Url.normalize(rendezvousNonceB64)));
      _fcRendezvous?.startOwnerSession(nonce);
    } catch (e) {
      _log.warn('FC-RV: malformed rendezvous nonce from UI — '
          'owner session not started: $e');
    }
  }

  /// §4.11.10: the other side's EndpointRecord was resolved via the
  /// First-Contact rendezvous. Merge the addresses into the routing table
  /// and PING all of them (simultaneous-open: both sides send → carrier
  /// firewalls/NATs open bidirectionally). Fired on every poll hit while
  /// the session is active, so the PINGs are repeated.
  void _onFcEndpointResolved(
      FcSession session, String deviceIdHex, List<EndpointAddress> addresses) {
    if (deviceIdHex == bytesToHex(identity.deviceNodeId)) return; // self-echo
    final deviceId = hexToBytes(deviceIdHex);
    final existing = node.routingTable.getPeer(deviceId);
    if (existing == null) {
      final peer = PeerInfo(
        nodeId: deviceId,
        addresses:
            addresses.map((a) => PeerAddress(ip: a.ip, port: a.port)).toList(),
      )..isProtectedSeed = true; // survive Doze pruning, like ContactSeed peers
      if (session.role == kFcRoleScanner && session.targetUserIdHex != null) {
        peer.userId = hexToBytes(session.targetUserIdHex!);
      }
      node.routingTable.addPeer(peer);
      _log.info('FC-RV: added peer ${deviceIdHex.substring(0, 8)} with '
          '${addresses.length} rendezvous address(es)');
    } else {
      var merged = 0;
      for (final a in addresses) {
        final known = existing.addresses
            .any((pa) => pa.ip == a.ip && pa.port == a.port);
        if (!known) {
          existing.addresses.add(PeerAddress(ip: a.ip, port: a.port));
          merged++;
        }
      }
      if (merged > 0) {
        _log.info('FC-RV: merged $merged fresh rendezvous address(es) into '
            'peer ${deviceIdHex.substring(0, 8)}');
      }
    }
    for (final a in addresses) {
      node.sendPing(a.ip, a.port);
    }
  }

  /// Parse address string: "1.2.3.4:5678" (IPv4) or "[2001:db8::1]:5678" (IPv6).
  static (String, int)? _parseAddrString(String addr) {
    if (addr.startsWith('[')) {
      // IPv6: [2001:db8::1]:port
      final closeBracket = addr.indexOf(']');
      if (closeBracket < 0) return null;
      final ip = addr.substring(1, closeBracket);
      if (closeBracket + 2 >= addr.length || addr[closeBracket + 1] != ':') return null;
      final port = int.tryParse(addr.substring(closeBracket + 2));
      if (port == null || ip.isEmpty || ip == '::') return null;
      return (ip, port);
    }
    // IPv4: ip:port
    final parts = addr.split(':');
    if (parts.length != 2) return null;
    final ip = parts[0];
    final port = int.tryParse(parts[1]);
    if (port == null || ip.isEmpty || ip == '0.0.0.0') return null;
    return (ip, port);
  }

  // ── Manual Peer Entry (Architecture Section 2.3.4) ──────────────────

  /// Add a peer by IP:port. Sends a PING to verify reachability.
  ///
  /// This is the "Manual Peer Entry" fallback for advanced users and debugging
  /// as described in the architecture. The peer is added to the routing table
  /// and pinged. If the PONG arrives, the peer is confirmed and becomes part
  /// of the normal DV routing.
  ///
  /// Returns true if the PING was sent (does not wait for PONG).
  @override
  bool addManualPeer(String ip, int port) {
    if (ip.isEmpty || port <= 0 || port > 65535) {
      _log.warn('addManualPeer: invalid address $ip:$port');
      return false;
    }

    // V3 path (post-Welle 3): the InfrastructureFrame BOOT-pipeline (§2.4.1a)
    // requires the recipient's deviceId — without it `_sendPing` silently
    // drops because no addressee can be encoded in the frame header. Manual
    // peer entry by definition supplies only an (ip, port) pair, so we use
    // the LAN-Discovery wire format instead: a 38-byte unicast probe to the
    // recipient's discovery socket. The receiver's `LocalDiscovery._onEvent`
    // registers us via the standard discovery callback, after which V3
    // BOOT-bonding can proceed in both directions.
    //
    // The discovery port (41338) is well-known protocol-wide. The user-
    // supplied `port` is usually the daemon's *data* port — we send the
    // probe to discoveryPort regardless. If the user knows the recipient
    // binds discovery on a non-standard port, they can override by sending
    // a SECOND probe to the supplied port; we cover that fallback so manual
    // entry remains operator-friendly across uncommon topologies.
    node.localDiscovery.sendUnicastDiscovery(ip);
    if (port != LocalDiscovery.discoveryPort) {
      node.localDiscovery.sendUnicastDiscovery(ip, port);
    }
    // Cross-NAT: LAN-Discovery probes fail across CGNAT (no pinhole on
    // discovery port 41338). Also send a V3 DHT_PING to the data port —
    // works if the target is a KNOWN peer whose addresses include ip:port.
    node.sendPing(ip, port);
    _log.info('Manual peer entry: LAN-Discovery probe + V3 PING sent to $ip:$port '
        '(discoveryPort=${LocalDiscovery.discoveryPort})');
    return true;
  }

  // ── Peer Rescue Bundle (§8.1.2) ──────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> exportPeerBundle() async {
    final summaries = peerSummaries;
    final inbound = summaries.where((p) => p.allAddresses.any(_isPublicAddress)).toList();
    final others = summaries.where((p) => !p.allAddresses.any(_isPublicAddress)).toList();
    final selected = <RescuePeer>[];
    for (final p in [...inbound, ...others].take(PeerRescueBundle.maxPeers)) {
      final nodeId = _hexToBytes32(p.nodeIdHex);
      if (nodeId == null) continue;
      selected.add(RescuePeer(nodeId: nodeId, addresses: p.allAddresses));
    }

    final bundle = PeerRescueBundle.build(
      exporterDeviceId: identity.deviceNodeId,
      exporterEd25519Sk: identity.ed25519SecretKey,
      peers: selected,
    );

    final bytes = bundle.toBytes();
    final uri = bundle.toUri();

    return {
      'bundleBase64': base64.encode(bytes),
      'uri': uri,
      'peerCount': selected.length,
      'createdAtMs': bundle.createdAt.millisecondsSinceEpoch,
    };
  }

  @override
  Future<Map<String, dynamic>> importPeerBundle({String? uri, String? bundleBase64}) async {
    assert(uri != null || bundleBase64 != null);

    PeerRescueBundleParseResult result;
    if (uri != null) {
      result = PeerRescueBundle.parseUriAndValidate(uri);
    } else {
      final bytes = base64.decode(bundleBase64!);
      result = PeerRescueBundle.parseAndValidate(bytes);
    }

    if (!result.networkTagValid) {
      return {
        'networkTagValid': false,
        'error': result.errorMessage ?? 'Network tag mismatch',
      };
    }

    final bundle = result.bundle!;
    var contacted = 0;
    for (final peer in bundle.peers) {
      for (final addr in peer.addresses) {
        final parts = _splitHostPort(addr);
        if (parts != null) {
          addManualPeer(parts.$1, parts.$2);
          contacted++;
        }
      }
    }

    unawaited(node.onNetworkChanged(force: true));

    return {
      'networkTagValid': true,
      'sigValid': result.sigValid,
      'sigUnknownExporter': result.sigUnknownExporter,
      'ageHours': result.ageHours,
      'peerCount': bundle.peers.length,
      'peersContacted': contacted,
      'exporterDeviceIdHex': bytesToHex(bundle.exporterDeviceId),
      'createdAtMs': bundle.createdAt.millisecondsSinceEpoch,
    };
  }

  static bool _isPublicAddress(String addr) {
    final h = _splitHostPort(addr);
    if (h == null) return false;
    final ip = h.$1;
    if (ip == '127.0.0.1' || ip == '::1') return false;
    if (ip.startsWith('10.')) return false;
    if (ip.startsWith('192.168.')) return false;
    final parts = ip.split('.');
    if (parts.length == 4) {
      final b1 = int.tryParse(parts[0]) ?? 0;
      final b2 = int.tryParse(parts[1]) ?? 0;
      if (b1 == 172 && b2 >= 16 && b2 <= 31) return false;
      if (b1 == 169 && b2 == 254) return false;
    }
    if (ip.startsWith('fe80:') || ip.startsWith('fc') || ip.startsWith('fd')) return false;
    return true;
  }

  static (String, int)? _splitHostPort(String addr) {
    try {
      if (addr.startsWith('[')) {
        final closeBracket = addr.indexOf(']');
        if (closeBracket < 0) return null;
        final ip = addr.substring(1, closeBracket);
        final rest = addr.substring(closeBracket + 1);
        if (!rest.startsWith(':')) return null;
        final port = int.tryParse(rest.substring(1));
        if (port == null || port <= 0 || port > 65535) return null;
        return (ip, port);
      } else {
        final lastColon = addr.lastIndexOf(':');
        if (lastColon < 0) return null;
        final ip = addr.substring(0, lastColon);
        final port = int.tryParse(addr.substring(lastColon + 1));
        if (port == null || port <= 0 || port > 65535) return null;
        return (ip, port);
      }
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _hexToBytes32(String hex) {
    if (hex.length != 64) return null;
    try {
      return hexToBytes(hex);
    } catch (_) {
      return null;
    }
  }

  /// Send a contact request.
  /// If the contact already exists as "accepted", re-sends CR with fresh keys
  /// so the remote side can re-establish the relationship (e.g. after data loss).
  @override
  Future<bool> sendContactRequest(String recipientUserIdHex,
      {String message = '',
      String? seedDeviceIdHex,
      String? seedDxkB64,
      String? seedDmkB64,
      String? seedEpB64}) async {
    final existing = _contacts[recipientUserIdHex];
    final isReContact = existing != null && existing.status == 'accepted';

    final recipientUserId = hexToBytes(recipientUserIdHex);

    final cr = proto.ContactRequestMsg()
      ..displayName = displayName
      ..ed25519PublicKey = identity.ed25519PublicKey
      ..mlDsaPublicKey = identity.mlDsaPublicKey
      ..x25519PublicKey = identity.x25519PublicKey
      ..mlKemPublicKey = identity.mlKemPublicKey
      ..message = message;
    if (_profilePictureBase64 != null) {
      cr.profilePicture = base64Decode(_profilePictureBase64!);
    }
    final crBytes = Uint8List.fromList(cr.writeToBuffer());

    if (!isReContact) {
      _contacts[recipientUserIdHex] = ContactInfo(
        nodeId: recipientUserId,
        displayName: 'Pending...',
        status: 'pending_outgoing',
        message: message.isEmpty ? null : message,
        seedDeviceIdHex: seedDeviceIdHex,
        seedDxkB64: seedDxkB64,
        seedDmkB64: seedDmkB64,
        seedEpB64: seedEpB64,
      );
      _saveContacts();
    } else {
      _log.info(
          'Re-contact to accepted ${existing.displayName} — sending CR with fresh keys');
    }

    // V3 path: re-contact (recipient KEM pubkeys already known) — sendToUser.
    if (isReContact &&
        existing.x25519Pk != null &&
        existing.mlKemPk != null) {
      final ok = await sendToUser(
        recipientUserId: recipientUserId,
        messageType: proto.MessageTypeV3.MTV3_CONTACT_REQUEST,
        payload: crBytes,
      );
      _log.info('CONTACT_REQUEST (re-contact V3) sendToUser ok=$ok');
      return true;
    }

    // First-contact CR (Welle 5 §8.1.1 First-CR-Bootstrap): wrap a
    // User-signed ApplicationFrameV3 (recipientUserId=recipient, payload=CR)
    // into an InfrastructureFrame whose KEM-encap subject is the recipient's
    // *Device*-KEM-PK (NOT User-KEM-PK — the sender doesn't have that yet, the
    // CR is what bootstraps the User-KEM exchange). The Device-KEM-PK pair
    // is delivered out-of-band via the ContactSeed `dxk`/`dmk` parameters.
    //
    // §8.1.1 Backward-compat: legacy ContactSeed-URIs predate Welle 5 and
    // carry only `did` (or nothing). When `dxk`/`dmk` are missing the sender
    // falls back to a synchronous 2D-DHT lookup of the recipient's
    // DeviceKemRecord (§4.3 step 4b) via `IdentityResolver.resolve(userId)`.
    // If a specific `did` was supplied, the resolver result is filtered to
    // that device; otherwise the freshest published Device-KEM is picked.
    Uint8List dxk;
    Uint8List dmk;
    Uint8List recipientDeviceId;
    final hasFullSeed = seedDeviceIdHex != null &&
        seedDeviceIdHex.isNotEmpty &&
        seedDxkB64 != null &&
        seedDmkB64 != null;
    if (hasFullSeed) {
      try {
        dxk = base64Decode(seedDxkB64);
        dmk = base64Decode(seedDmkB64);
        recipientDeviceId = hexToBytes(seedDeviceIdHex);
      } catch (e) {
        _log.warn('CONTACT_REQUEST drop: malformed seed parameters: $e');
        return false;
      }
    } else {
      // §8.1.1 rev3 Deferred Key Exchange step 1a: resolve Device-KEM-PK
      // from DHT (primary path for v2 ContactSeeds with ep trust-anchor).
      _log.info('CONTACT_REQUEST First-CR: Deferred Key Exchange — '
          'DHT lookup for ${recipientUserIdHex.substring(0, 8)}'
          '${seedEpB64 != null ? " (v2 seed with ep)" : " (legacy seed)"}');
      final resolved = await node.identityResolver.resolve(recipientUserId);
      Uint8List? preferred;
      if (seedDeviceIdHex != null && seedDeviceIdHex.isNotEmpty) {
        try {
          preferred = hexToBytes(seedDeviceIdHex);
        } catch (_) {}
      }
      final picked = firstCrPickDeviceKem(resolved, preferred);
      if (picked != null) {
        dxk = Uint8List.fromList(picked.deviceX25519Pk!);
        dmk = Uint8List.fromList(picked.deviceMlKemPk!);
        recipientDeviceId = Uint8List.fromList(picked.deviceNodeId);
        _log.info('CONTACT_REQUEST First-CR: DHT resolved device '
            '${bytesToHex(recipientDeviceId).substring(0, 8)} for '
            '${recipientUserIdHex.substring(0, 8)} '
            '(publishedAtMs=${picked.deviceKemPublishedAtMs})');
      } else if (seedEpB64 != null &&
          seedDeviceIdHex != null &&
          seedDeviceIdHex.isNotEmpty) {
        // §8.1.1 rev3 Deferred Key Exchange step 1b: the DHT had no
        // DeviceKemRecord (the common case for a fresh QR-scan between two
        // isolated networks — AP-isolation + CGNAT — where neither side's
        // 2D-DHT has converged). v2 ContactSeeds carry no inline dxk/dmk, so
        // we ask the recipient directly: a plaintext BOOT DEVICE_KEM_REQUEST
        // is routed to the target device (relayed through the ContactSeed's
        // seed peers via the DV cascade — the same path the CR itself uses).
        // The recipient answers with a DEVICE_KEM_OFFER signed by its user
        // Ed25519 key; handleIncomingDeviceKemOffer verifies that against the
        // `ep` trust-anchor, persists dxk/dmk onto this contact, and
        // re-triggers the CR. This is self-healing: we do NOT block on a
        // single timeout window — the CR stays pending_outgoing and the retry
        // timer re-issues the request until an OFFER arrives (or the user
        // gives up). See §8.1.1 step 1b.
        final targetDeviceId = hexToBytes(seedDeviceIdHex);
        _requestDeviceKem(recipientUserId, targetDeviceId, seedEpB64);
        _log.info('CONTACT_REQUEST First-CR: DHT miss for '
            '${recipientUserIdHex.substring(0, 8)} — sent DEVICE_KEM_REQUEST '
            '(step 1b); waiting up to 15s for DEVICE_KEM_OFFER...');
        final completer = _dkeCompleters.putIfAbsent(
            recipientUserIdHex, () => Completer<void>());
        // §4.5 DKE retry: resend after DV routing converges. The first
        // attempt often hits an incomplete routing table (discovery cascade
        // not finished, Bootstrap routes not yet accepted via D3 PoW
        // verification). A retry at 8s (matching the per-device rate-limit
        // cooldown) gives the mesh time to converge and picks up the newly
        // elected default-GW (typically Bootstrap with 50+ routes).
        final retryTimer = Timer(const Duration(seconds: 8), () {
          if (!completer.isCompleted) {
            _requestDeviceKem(recipientUserId, targetDeviceId, seedEpB64);
          }
        });
        try {
          await completer.future.timeout(const Duration(seconds: 15));
          retryTimer.cancel();
          _dkeCompleters.remove(recipientUserIdHex);
          _log.info('CONTACT_REQUEST First-CR: DEVICE_KEM_OFFER received for '
              '${recipientUserIdHex.substring(0, 8)} — CR sent by offer handler');
          return true;
        } on TimeoutException {
          retryTimer.cancel();
          _dkeCompleters.remove(recipientUserIdHex);
          _log.warn('CONTACT_REQUEST First-CR: DEVICE_KEM_OFFER timeout for '
              '${recipientUserIdHex.substring(0, 8)} — no RUDP-Light confirmation '
              'received. CR stays pending_outgoing for background retry '
              '(exponential backoff).');
          return false;
        }
      } else {
        _log.warn('CONTACT_REQUEST: Deferred Key Exchange failed — '
            'no DeviceKemRecord in DHT for '
            '${recipientUserIdHex.substring(0, 8)} and no ep+seedDeviceId for '
            'the step-1b fallback. CR queued for retry (exponential backoff).');
        return false;
      }
    }

    // Build inner ApplicationFrameV3, User-signed. Sender pubkeys are
    // carried in the CR payload itself so the receiver can verify even
    // before any contact-registry entry exists (§8.1.1 trust-bootstrap).
    final innerFrame = proto.ApplicationFrameV3()
      ..version = 1
      ..senderUserId = identity.userId
      ..recipientUserId = recipientUserId
      ..messageType = proto.MessageTypeV3.MTV3_CONTACT_REQUEST
      ..messageId = SodiumFFI().randomBytes(16)
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..payload = crBytes;
    final signedInnerBytes = V3FrameCodec.signApplicationFrameInner(
      inner: innerFrame,
      senderUserEd25519Sk: identity.signingEd25519Sk,
      senderUserMlDsaSk: identity.signingMlDsaSk,
    );

    // Build InfrastructureFrame with §8.1.1-relaxed selector
    // (MTV3_CONTACT_REQUEST), KEM-encapped under the recipient's
    // Device-KEM-PK pair from the seed.
    final packet = V3FrameCodec.buildInfrastructureFrame(
      recipientDeviceId: recipientDeviceId,
      senderDeviceId: node.primaryIdentity.deviceNodeId,
      senderDeviceKeys: node.deviceKeyPair,
      messageType: proto.MessageTypeV3.MTV3_CONTACT_REQUEST,
      payload: signedInnerBytes,
      recipientDeviceX25519Pk: dxk,
      recipientDeviceMlKemPk: dmk,
    );
    final ok = await node.sendToDevice(packet, recipientDeviceId);
    _log.info('CONTACT_REQUEST V3 First-CR-Bootstrap to '
        '${recipientUserIdHex.substring(0, 8)} (device='
        '${bytesToHex(recipientDeviceId).substring(0, 8)}) sendToDevice ok=$ok');

    // §5.5b FIRST_CR_STORE: also deposit the CR on seed peers so the
    // target can retrieve it even if currently offline (async CR via
    // email/copy-paste). The blob is the serialized KEM-encrypted packet
    // — opaque to the seed peer. Direct send bypasses DV cascade.
    unawaited(_sendFirstCrStoreToSeedPeers(
      recipientUserId: recipientUserId,
      recipientDeviceId: recipientDeviceId,
      encryptedCrBlob: Uint8List.fromList(packet.writeToBuffer()),
    ));

    // First-contact CRs are persisted as pending_outgoing and retried by
    // _retryPendingContactRequests regardless of the initial send result.
    // Return true so the UI shows "sent" rather than "failed" — the retry
    // timer handles delivery even when the routing table isn't warm yet.
    return true;
  }

  // ── §5.5b First-CR-Store on seed peers ───────────────────────────────────

  Future<void> _sendFirstCrStoreToSeedPeers({
    required Uint8List recipientUserId,
    required Uint8List recipientDeviceId,
    required Uint8List encryptedCrBlob,
  }) async {
    final recipDevHex = bytesToHex(recipientDeviceId);
    final storeMsg = proto.FirstCrStoreV3()
      ..recipientUserId = recipientUserId
      ..recipientDeviceId = recipientDeviceId
      ..encryptedCrBlob = encryptedCrBlob
      ..senderDeviceId = node.primaryIdentity.deviceNodeId
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..ttlMs = Int64(const Duration(days: 7).inMilliseconds);
    final storeBytes = Uint8List.fromList(storeMsg.writeToBuffer());

    // Find seed peers: protected DV neighbors that are NOT the target.
    // Route via sendInfraViaDeviceRoute (DV relay cascade) instead of
    // sendInfraDirect — from CGNAT/mobile, direct UDP to seed-peer
    // addresses is unreachable (private IPs not routable, public IPs
    // lack NAT pinholes). The relay cascade falls through to Bootstrap
    // which has an established connection.
    var sent = 0;
    for (final nhHex in node.dvRouting.neighborIds) {
      if (nhHex == recipDevHex) continue;
      final peer = node.routingTable.getPeer(hexToBytes(nhHex));
      if (peer == null || !peer.isProtectedSeed) continue;
      try {
        final ok = await node.sendInfraViaDeviceRoute(
          messageType: proto.MessageTypeV3.MTV3_FIRST_CR_STORE,
          innerPayload: storeBytes,
          recipientDeviceId: hexToBytes(nhHex),
        );
        if (ok) sent++;
        _log.info('§5.5b FIRST_CR_STORE → ${nhHex.substring(0, 8)} '
            'via DV cascade ok=$ok');
      } catch (e) {
        _log.debug('§5.5b FIRST_CR_STORE to ${nhHex.substring(0, 8)} '
            'error: $e');
      }
    }
    if (sent > 0) {
      _log.info('§5.5b FIRST_CR_STORE: deposited CR on $sent seed peers '
          'for ${recipDevHex.substring(0, 8)}');
    } else {
      // Clean no-op: seeds with a public own address may legitimately carry
      // an empty seed-peer list (relaxed §8.1.1 readiness gate) — the CR
      // then relies on Direct + Relay + rendezvous instead of FIRST_CR_STORE.
      _log.info('§5.5b FIRST_CR_STORE: no protected seed peers available '
          'for ${recipDevHex.substring(0, 8)} — skipped (no-op)');
    }
  }

  // ── §8.1.1 rev3 Deferred Key Exchange (step 1b) ─────────────────────────
  //
  // v2 ContactSeeds carry only the 32-byte `ep` (userEd25519Pk) trust-anchor,
  // not the 1216-byte Device-KEM-PK pair. When the primary DHT resolution
  // (step 1a) misses — which it always does for a fresh first contact between
  // two isolated networks whose 2D-DHT has not converged — the sender asks the
  // recipient directly for its Device-KEM-PK via a plaintext BOOT
  // DEVICE_KEM_REQUEST. The recipient answers with a DEVICE_KEM_OFFER signed by
  // its user Ed25519 key, which the sender verifies against `ep`. Closed-Network
  // HMAC + Outer Device-Sig (BOOT path) and this `ep`-anchored inner signature
  // carry the security properties; the request/offer themselves cannot be
  // KEM-encrypted because the KEM-PK is precisely what they are discovering.

  /// In-flight throttle for outbound DEVICE_KEM_REQUEST, keyed by target
  /// deviceHex → last-sent time. The CR retry timer replays sendContactRequest
  /// every backoff tick; without this guard a deferred v2 first-CR would emit a
  /// fresh request on every tick. Throttled to the OFFER round-trip budget (8s).
  final Map<String, DateTime> _lastKemRequestSent = {};

  /// Completers for DKE step 1b synchronous wait. sendContactRequest() awaits
  /// these (15s timeout) so the UI gets a real success/failure. Completed by
  /// handleIncomingDeviceKemOffer() when the OFFER arrives.
  final Map<String, Completer<void>> _dkeCompleters = {};

  /// Per-sender anti-flood for inbound DEVICE_KEM_REQUEST (§8.2 Layer-3 rate
  /// limit). senderDeviceHex → recent request timestamps (sliding 60s window).
  final Map<String, List<DateTime>> _kemRequestTimes = {};

  /// §8.1.1 rev3 step 1b sender: ask [deviceId] (owned by [userId]) for its
  /// Device-KEM-PK pair. Fire-and-forget — the reply is handled asynchronously
  /// by [handleIncomingDeviceKemOffer]. [epB64] is already persisted on the
  /// contact (used there to verify the OFFER); passed here only for logging.
  void _requestDeviceKem(Uint8List userId, Uint8List deviceId, String epB64) {
    final devHex = bytesToHex(deviceId);
    final now = DateTime.now();
    final last = _lastKemRequestSent[devHex];
    if (last != null && now.difference(last).inSeconds < 8) return;
    _lastKemRequestSent[devHex] = now;

    final request = proto.DeviceKemRequestV3()
      ..targetUserId = userId
      ..targetDeviceId = deviceId
      ..nonce = SodiumFFI().randomBytes(16)
      ..timestampMs = Int64(now.millisecondsSinceEpoch);
    final payload = Uint8List.fromList(request.writeToBuffer());
    unawaited(node.sendInfraTo(
      messageType: proto.MessageTypeV3.MTV3_DEVICE_KEM_REQUEST,
      innerPayload: payload,
      recipientDeviceId: deviceId,
    ));
    // §8.1.1 step 1b direct-path: also send directly to the target's known
    // addresses (from ContactSeed). If the target is on the same LAN, this
    // arrives immediately — the DV cascade above handles cross-network relay.
    final targetPeer = node.routingTable.getPeer(deviceId);
    if (targetPeer != null) {
      var directCount = 0;
      for (final addr in targetPeer.allConnectionTargets()) {
        if (addr.ip.isEmpty || addr.port <= 0) continue;
        if (!addr.isReachableFromCurrentNetwork) continue;
        unawaited(node.sendInfraDirect(
          messageType: proto.MessageTypeV3.MTV3_DEVICE_KEM_REQUEST,
          innerPayload: payload,
          recipientDeviceId: deviceId,
          addr: InternetAddress(addr.ip),
          port: addr.port,
        ));
        directCount++;
      }
      if (directCount > 0) {
        _log.info('DEVICE_KEM_REQUEST → ${devHex.substring(0, 8)} '
            'also sent direct to $directCount address(es)');
      }
    }
    _log.info('DEVICE_KEM_REQUEST → ${devHex.substring(0, 8)} '
        '(user ${bytesToHex(userId).substring(0, 8)}, §8.1.1 step 1b)');
  }

  /// §8.1.1 rev3 step 1b receiver (recipient side): a DEVICE_KEM_REQUEST
  /// addressed to this identity+device arrived. Answer with a DEVICE_KEM_OFFER
  /// carrying our Device-KEM-PK pair, signed with our user Ed25519 SK so the
  /// requester can verify it against the `ep` trust-anchor from our ContactSeed.
  void handleIncomingDeviceKemRequest(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
  ) {
    try {
      final req = proto.DeviceKemRequestV3.fromBuffer(frame.payload);
      // Multi-identity fan-out: only the addressed identity + device answers.
      if (bytesToHex(Uint8List.fromList(req.targetUserId)) !=
          identity.userIdHex) {
        return;
      }
      if (bytesToHex(Uint8List.fromList(req.targetDeviceId)) !=
          identity.deviceNodeIdHex) {
        return;
      }
      // §8.2 Layer-3 anti-flood: max 5 requests / minute per sender device.
      final senderHex = bytesToHex(senderDeviceId);
      final now = DateTime.now();
      final times = _kemRequestTimes.putIfAbsent(senderHex, () => <DateTime>[]);
      times.removeWhere((t) => now.difference(t).inSeconds > 60);
      if (times.length >= 5) {
        _log.debug('DEVICE_KEM_REQUEST from ${senderHex.substring(0, 8)} '
            'rate-limited (>5/min)');
        return;
      }
      times.add(now);

      final dxk = node.deviceKem.x25519PublicKey;
      final dmk = node.deviceKem.mlKemPublicKey;
      final nonce = Uint8List.fromList(req.nonce);
      final sig =
          SodiumFFI().signEd25519(_kemOfferSigInput(dxk, dmk, nonce),
              identity.ed25519SecretKey);

      final offer = proto.DeviceKemOfferV3()
        ..deviceX25519Pk = dxk
        ..deviceMlKemPk = dmk
        ..nonce = nonce
        ..userEd25519Sig = sig
        ..timestampMs = Int64(now.millisecondsSinceEpoch);
      unawaited(node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_DEVICE_KEM_OFFER,
        innerPayload: Uint8List.fromList(offer.writeToBuffer()),
        recipientDeviceId: senderDeviceId,
      ));
      _log.info('DEVICE_KEM_REQUEST from ${senderHex.substring(0, 8)} '
          '→ replied DEVICE_KEM_OFFER (§8.1.1 step 1b)');
    } catch (e) {
      _log.warn('DEVICE_KEM_REQUEST handle error: $e');
    }
  }

  /// §8.1.1 rev3 step 1b requester side: a DEVICE_KEM_OFFER arrived. Verify it
  /// against the `ep` trust-anchor of the matching pending contact, persist the
  /// resolved Device-KEM-PK pair onto the contact (so the CR + retries take the
  /// hasFullSeed fast path), prime the local DKR cache, and re-trigger the
  /// deferred first-CR immediately (self-healing).
  void handleIncomingDeviceKemOffer(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
  ) {
    try {
      final offer = proto.DeviceKemOfferV3.fromBuffer(frame.payload);
      final senderHex = bytesToHex(senderDeviceId);

      // Find the pending contact whose scanned ContactSeed names this device.
      ContactInfo? contact;
      String? contactUserHex;
      for (final e in _contacts.entries) {
        if (e.value.seedDeviceIdHex == senderHex &&
            e.value.seedEpB64 != null &&
            (e.value.status == 'pending_outgoing' ||
             e.value.status == 'storedForDelivery')) {
          contact = e.value;
          contactUserHex = e.key;
          break;
        }
      }
      if (contact == null || contactUserHex == null) {
        _log.debug('DEVICE_KEM_OFFER from ${senderHex.substring(0, 8)} — '
            'no matching pending contact, ignoring');
        return;
      }

      final dxk = Uint8List.fromList(offer.deviceX25519Pk);
      final dmk = Uint8List.fromList(offer.deviceMlKemPk);
      final nonce = Uint8List.fromList(offer.nonce);
      final sig = Uint8List.fromList(offer.userEd25519Sig);
      final ep = base64Url.decode(base64Url.normalize(contact.seedEpB64!));

      // Trust-anchor verify: the signature (by the recipient's user Ed25519
      // key) over (dxk + dmk + nonce) must validate against `ep`. This binds
      // the resolved Device-KEM-PK to the identity the user actually scanned —
      // a malicious relay cannot substitute its own keys.
      if (!SodiumFFI().verifyEd25519(_kemOfferSigInput(dxk, dmk, nonce), sig, ep)) {
        _log.warn('DEVICE_KEM_OFFER from ${senderHex.substring(0, 8)} — '
            'Ed25519 sig verify FAILED against ep trust-anchor, dropping');
        return;
      }
      // Length sanity before KEM-encap (X25519=32, ML-KEM-768=1184).
      if (dxk.length != 32 || dmk.length != 1184) {
        _log.warn('DEVICE_KEM_OFFER from ${senderHex.substring(0, 8)} — '
            'bad key lengths (dxk=${dxk.length}, dmk=${dmk.length}), dropping');
        return;
      }

      // Persist resolved keys onto the contact (CR fast path) + prime DKR cache.
      contact.seedDxkB64 = base64Encode(dxk);
      contact.seedDmkB64 = base64Encode(dmk);
      _saveContacts();
      node.identityDhtHandler.handleKemPublish(DeviceKemRecord(
        userId: contact.nodeId,
        deviceId: senderDeviceId,
        deviceX25519Pk: dxk,
        deviceMlKemPk: dmk,
        ttlSeconds: 24 * 3600,
        sequenceNumber: 0,
        publishedAtMs: DateTime.now().millisecondsSinceEpoch,
        userEd25519Pk: ep,
        ed25519Sig: Uint8List(0),
      ));

      _log.info('DEVICE_KEM_OFFER from ${senderHex.substring(0, 8)} verified '
          'against ep — Device-KEM-PK resolved, re-triggering first-CR');

      // Wake up the synchronous DKE waiter if still active (step 1b path).
      final dkeCompleter = _dkeCompleters.remove(contactUserHex);
      if (dkeCompleter != null && !dkeCompleter.isCompleted) {
        dkeCompleter.complete();
      }

      // Self-healing: send the CR right now via the hasFullSeed fast path.
      unawaited(sendContactRequest(
        contactUserHex,
        message: contact.message ?? '',
        seedDeviceIdHex: contact.seedDeviceIdHex,
        seedDxkB64: contact.seedDxkB64,
        seedDmkB64: contact.seedDmkB64,
        seedEpB64: contact.seedEpB64,
      ));
    } catch (e) {
      _log.warn('DEVICE_KEM_OFFER handle error: $e');
    }
  }

  /// Canonical bytes signed/verified for a DEVICE_KEM_OFFER: dxk ++ dmk ++
  /// nonce. Signer (recipient) and verifier (requester) MUST build this
  /// identically, else the Ed25519 check fails.
  static Uint8List _kemOfferSigInput(
      Uint8List dxk, Uint8List dmk, Uint8List nonce) {
    final out = Uint8List(dxk.length + dmk.length + nonce.length);
    out.setRange(0, dxk.length, dxk);
    out.setRange(dxk.length, dxk.length + dmk.length, dmk);
    out.setRange(dxk.length + dmk.length, out.length, nonce);
    return out;
  }

  /// Accept a pending (or re-) contact request.
  @override
  Future<bool> acceptContactRequest(String nodeIdHex) async {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return false;
    // Allow 'pending' (normal accept), 'accepted' (re-contact response),
    // 'pending_outgoing' and 'storedForDelivery' (bidirectional CR auto-accept).
    if (contact.status != 'pending' && contact.status != 'accepted' &&
        contact.status != 'pending_outgoing' && contact.status != 'storedForDelivery') {
      return false;
    }

    contact.status = 'accepted';
    contact.acceptedAt ??= DateTime.now();
    _crRetryCountPerContact.remove(nodeIdHex);
    _staleWarningWrittenFor.remove(nodeIdHex);
    _saveContacts();
    // A newly-accepted contact may carry a birthday set locally; refresh.
    _syncCalendarBirthdays();

    // Create conversation with system message so the contact appears
    // immediately in the "Aktuell" tab after acceptance.
    if (!conversations.containsKey(nodeIdHex)) {
      final systemMsg = UiMessage(
        id: bytesToHex(SodiumFFI().randomBytes(16)),
        conversationId: nodeIdHex,
        senderNodeIdHex: '',
        text: 'Contact request from ${contact.displayName} accepted.',
        isOutgoing: false,
        timestamp: DateTime.now(),
        type: UiMessageType.identityDeleted, // system message type
        status: MessageStatus.delivered,
      );
      _addMessageToConversation(nodeIdHex, systemMsg);
      _saveConversations();
    }

    final resp = proto.ContactRequestResponse()
      ..accepted = true
      ..ed25519PublicKey = identity.ed25519PublicKey
      ..mlDsaPublicKey = identity.mlDsaPublicKey
      ..x25519PublicKey = identity.x25519PublicKey
      ..mlKemPublicKey = identity.mlKemPublicKey
      ..displayName = displayName;
    if (_profilePictureBase64 != null) {
      resp.profilePicture = base64Decode(_profilePictureBase64!);
    }

    onContactAccepted?.call(nodeIdHex);
    onStateChanged?.call();

    // V3 (Architecture §23.3): at this point we know the recipient's KEM
    // pubkeys (received with the incoming CR and stored on the contact
    // record), so the response goes through sendToUser. A CR_RESPONSE
    // without KEM pubkeys cannot reach a V3 receiver, so we drop with a
    // warning rather than emit something the receiver cannot decap.
    bool sent;
    if (contact.x25519Pk != null && contact.mlKemPk != null) {
      sent = await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_CONTACT_REQUEST_RESPONSE,
        payload: Uint8List.fromList(resp.writeToBuffer()),
      );
      _log.info('CONTACT_REQUEST_RESPONSE V3 sendToUser ok=$sent');
    } else {
      sent = false;
      _log.warn('CONTACT_REQUEST_RESPONSE drop: contact ${nodeIdHex.substring(0, 8)} '
          'has no KEM pubkeys — CR-handshake incomplete');
    }

    // Twin-Sync: notify other devices about accepted contact (§26)
    _sendTwinSync(proto.TwinSyncType.CONTACT_ADDED, Uint8List.fromList(utf8.encode(jsonEncode({
      'nodeId': nodeIdHex,
      'displayName': contact.displayName,
      if (contact.ed25519Pk != null) 'ed25519Pk': bytesToHex(contact.ed25519Pk!),
      if (contact.x25519Pk != null) 'x25519Pk': bytesToHex(contact.x25519Pk!),
      if (contact.mlKemPk != null) 'mlKemPk': bytesToHex(contact.mlKemPk!),
      if (contact.mlDsaPk != null) 'mlDsaPk': bytesToHex(contact.mlDsaPk!),
      if (contact.deviceNodeIds.isNotEmpty) 'deviceNodeIds': contact.deviceNodeIds.toList(),
    }))));

    return sent;
  }

  /// Delete a contact and its conversation.
  @override
  void deleteContact(String nodeIdHex) {
    _contacts.remove(nodeIdHex);
    _deletedContacts.add(nodeIdHex);
    conversations.remove(nodeIdHex);
    _saveContacts();
    _saveConversations();
    onStateChanged?.call();
    _log.info('Contact deleted: ${nodeIdHex.substring(0, 8)}');

    // Twin-Sync (§26)
    _sendTwinSync(proto.TwinSyncType.CONTACT_DELETED, Uint8List.fromList(utf8.encode(nodeIdHex)));
  }

  /// Set or clear a local alias for a contact.
  @override
  void renameContact(String nodeIdHex, String? localAlias) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return;
    contact.localAlias = (localAlias != null && localAlias.trim().isEmpty) ? null : localAlias?.trim();
    // Also update conversation displayName
    final conv = conversations[nodeIdHex];
    if (conv != null) {
      conv.displayName = contact.effectiveName;
    }
    _saveContacts();
    onStateChanged?.call();
    _log.info('Contact renamed: ${nodeIdHex.substring(0, 8)} → "${contact.effectiveName}"');
  }

  /// Accept or reject a pending contact name change.
  @override
  void acceptContactNameChange(String nodeIdHex, bool accept) {
    final contact = _contacts[nodeIdHex];
    if (contact == null || contact.pendingNameChange == null) return;
    if (accept) {
      contact.displayName = contact.pendingNameChange!;
      // If no local alias, update conversation too
      if (contact.localAlias == null) {
        final conv = conversations[nodeIdHex];
        if (conv != null) {
          conv.displayName = contact.displayName;
        }
      }
    }
    contact.pendingNameChange = null;
    _saveContacts();
    onStateChanged?.call();
  }

  // ── Stale contact sender-side warning ──────────────────────────────
  //
  // V3.1.50 added receiver-side detection: when a reinstalled contact sends
  // a fresh CR, the old conversation gets a "new identity" system message.
  // That only helps if the new identity initiates contact. If the sender
  // (us) has the old userId and keeps writing to it, the receiver-side
  // path never fires and the user sees no warning — messages just silently
  // fail to deliver.
  //
  // This helper writes a one-time warning into the conversation when we're
  // sending to an accepted contact that hasn't ACKed anything for 7 days
  // (or ever, if accepted > 7d ago). Cleared on next ACK or re-accept.
  void _maybeWriteStaleContactWarning(String userIdHex) {
    if (_staleWarningWrittenFor.contains(userIdHex)) return;
    final contact = _contacts[userIdHex];
    if (contact == null || contact.status != 'accepted') return;
    final acceptedAt = contact.acceptedAt;
    if (acceptedAt == null) return;

    const staleThreshold = Duration(days: 7);
    final now = DateTime.now();
    if (now.difference(acceptedAt) < staleThreshold) return;

    final lastAck = _contactLastAckedAt[userIdHex];
    if (lastAck != null && now.difference(lastAck) < staleThreshold) return;

    final conv = conversations[userIdHex];
    if (conv == null) return;

    _staleWarningWrittenFor.add(userIdHex);
    final systemMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: userIdHex,
      senderNodeIdHex: '',
      text: 'No delivery confirmation from ${contact.displayName} in over 7 days. '
          'The contact may have reinstalled the app. '
          'Ask them to send you a new contact request.',
      isOutgoing: false,
      timestamp: now,
      type: UiMessageType.identityDeleted,
      status: MessageStatus.delivered,
    );
    // Route through _addMessageToConversation so badge + Launcher counter
    // pick up the warning (#U15 — direct conv.messages.add bypassed both).
    _addMessageToConversation(userIdHex, systemMsg);
    _log.info('Stale sender-side warning for ${userIdHex.substring(0, 8)} (${contact.displayName})');
  }

  // ── CR Retry ───────────────────────────────────────────────────────

  void _retryPendingContactRequests() {
    final now = DateTime.now();
    final pending = _contacts.entries
        .where((e) => e.value.status == 'pending_outgoing')
        .where((e) => !_deletedContacts.contains(e.key))
        .toList();

    for (final entry in pending) {
      final recipientUserId = entry.value.nodeId;
      // Exponential backoff: 10s, 20s, 40s, 80s, 160s, 320s, capped at 600s.
      // ML-DSA signing + erasure-coded backup per retry is expensive — without
      // backoff we'd flood unreachable contacts with CR + erasure writes every 10s
      // indefinitely.
      final count = _crRetryCountPerContact[entry.key] ?? 0;
      final shift = count > 6 ? 6 : count;
      final backoffSec = 10 * (1 << shift) > 600 ? 600 : 10 * (1 << shift);
      final lastRetry = _lastCrRetryPerContact[entry.key];
      if (lastRetry != null && now.difference(lastRetry).inSeconds < backoffSec) continue;

      // Only retry if peer is in routing table (known peer).
      // DV routing only carries deviceNodeIds — the userId secondary index
      // is often empty for first-CR contacts. Fall back to the persisted
      // seedDeviceIdHex from the QR/ContactSeed.
      final seedDevId = entry.value.seedDeviceIdHex;
      if (node.routingTable.getPeer(recipientUserId) == null &&
          node.routingTable.getPeerByUserId(recipientUserId) == null &&
          (seedDevId == null || node.routingTable.getPeer(hexToBytes(seedDevId)) == null)) {
        continue;
      }

      // Welle 5 Teil 4 Wave 2: First-CR retry replays sendContactRequest with
      // the persisted ContactSeed bundle (§8.1.1). Without seed (legacy
      // pre-Wave-2 contacts) the retry stays a no-op and the user has to
      // re-scan the QR.
      final ci = entry.value;
      _lastCrRetryPerContact[entry.key] = now;
      _crRetryCountPerContact[entry.key] = count + 1;
      // v2 seeds have ep but no dxk/dmk — Deferred Key Exchange via DHT.
      // v1 seeds have dxk+dmk. Both need seedDeviceIdHex.
      final hasV1Seed = ci.seedDxkB64 != null && ci.seedDmkB64 != null;
      final hasV2Seed = ci.seedEpB64 != null;
      if (ci.seedDeviceIdHex == null || (!hasV1Seed && !hasV2Seed)) {
        _log.debug(
            'CR retry skipped for ${entry.key.substring(0, 8)} (attempt '
            '${count + 1}): no persisted ContactSeed — re-scan QR to resend');
        continue;
      }
      // §4.11.10: before each CR retry, re-resolve the owner-tag of an
      // active First-Contact rendezvous session (fresher owner addresses
      // than the URI's `a=`). Fire-and-forget + rate-limited inside the
      // manager (min 60s) — no own timer, docks onto this existing retry.
      final fcResolve = _fcRendezvous?.resolveOwnerForContact(entry.key);
      if (fcResolve != null) unawaited(fcResolve);
      unawaited(sendContactRequest(
        entry.key,
        message: ci.message ?? '',
        seedDeviceIdHex: ci.seedDeviceIdHex,
        seedDxkB64: ci.seedDxkB64,
        seedDmkB64: ci.seedDmkB64,
        seedEpB64: ci.seedEpB64,
      ));
      _log.info(
          'CR retry replayed for ${entry.key.substring(0, 8)} (attempt '
          '${count + 1}, backoff ${backoffSec}s)');
    }

    // V3.1: Also retry CR-Response for recently accepted contacts.
    // If the first Response was sent via a DV route that silently drops packets
    // (e.g. AP isolation), it was lost. After ACK-based Route-DOWN, the retry
    // goes through the full cascade again and finds the working relay path.
    final recentlyAccepted = _contacts.entries
        .where((e) => e.value.status == 'accepted')
        .where((e) => e.value.acceptedAt != null)
        .where((e) => now.difference(e.value.acceptedAt!).inMinutes < 5)
        .where((e) => !_deletedContacts.contains(e.key))
        .toList();

    for (final entry in recentlyAccepted) {
      final contact = entry.value;
      // Rate limit: skip contacts retried less than 10s ago
      final lastRetry = _lastCrRetryPerContact[entry.key];
      if (lastRetry != null && now.difference(lastRetry).inSeconds < 10) continue;

      // Only retry if we have their keys (received their CR)
      if (contact.ed25519Pk == null) continue;
      // contact.nodeId is the USER nodeId; peer may be indexed under DEVICE nodeId
      if (node.routingTable.getPeer(contact.nodeId) == null &&
          node.routingTable.getPeerByUserId(contact.nodeId) == null) {
        continue;
      }

      // Stop retrying once delivery to this contact is ACK-confirmed.
      // Primary check: any DELIVERY_RECEIPT from this contact since acceptance
      // proves end-to-end reachability (works for direct AND relay receipts —
      // critical for CGNAT peers where receipts only arrive via relay and
      // dvRouting.confirmRoute is never called).
      final lastAck = _contactLastAckedAt[entry.key];
      if (lastAck != null &&
          contact.acceptedAt != null &&
          lastAck.isAfter(contact.acceptedAt!)) {
        continue;
      }
      // Fallback: dvRouting direct-route confirmation.
      final route = node.dvRouting.bestRouteTo(entry.key);
      if (route != null && route.ackConfirmed) continue;

      final resp = proto.ContactRequestResponse()
        ..accepted = true
        ..ed25519PublicKey = identity.ed25519PublicKey
        ..mlDsaPublicKey = identity.mlDsaPublicKey
        ..x25519PublicKey = identity.x25519PublicKey
        ..mlKemPublicKey = identity.mlKemPublicKey
        ..displayName = displayName;

      // V3: by retry time we have the contact's KEM pubkeys (CR was already
      // received and accepted) — sendToUser handles the rest.
      if (contact.x25519Pk != null && contact.mlKemPk != null) {
        sendToUser(
          recipientUserId: contact.nodeId,
          messageType: proto.MessageTypeV3.MTV3_CONTACT_REQUEST_RESPONSE,
          payload: Uint8List.fromList(resp.writeToBuffer()),
        );
      } else {
        // Defensive: should be unreachable — accepted contacts always have
        // KEM pubkeys (CR carried them). A missing-pks contact at retry
        // time is a data-integrity issue.
        _log.warn('CR-Response retry skipped for ${entry.key.substring(0, 8)}: '
            'accepted contact lacks KEM pubkeys (data corruption?)');
      }
      _lastCrRetryPerContact[entry.key] = now;
      _log.debug('CR-Response retry to ${entry.key.substring(0, 8)}');
    }
  }

  void _startCrRetryTimer() {
    _crRetryTimer?.cancel();
    if (_contacts.values.any((c) => c.status == 'pending_outgoing') ||
        _contacts.values.any((c) =>
            c.status == 'accepted' &&
            c.acceptedAt != null &&
            DateTime.now().difference(c.acceptedAt!).inMinutes < 5)) {
      _crRetryTimer = Timer(const Duration(seconds: 30), () {
        _crRetryTimer = null;
        _retryPendingContactRequests();
        _startCrRetryTimer();
      });
    }
  }

  // ── Conversation Management ────────────────────────────────────────

  bool _addMessageToConversation(String conversationId, UiMessage msg, {bool isGroup = false, bool isChannel = false}) {
    final contact = _contacts[conversationId];
    final group = _groups[conversationId];
    final channel = _channels[conversationId];
    final conv = conversations.putIfAbsent(conversationId, () {
      if (isChannel && channel != null) {
        return Conversation(
          id: conversationId,
          displayName: channel.name,
          profilePictureBase64: channel.pictureBase64,
          isChannel: true,
        );
      }
      if (isGroup && group != null) {
        return Conversation(
          id: conversationId,
          displayName: group.name,
          profilePictureBase64: group.pictureBase64,
          isGroup: true,
        );
      }
      return Conversation(
        id: conversationId,
        displayName: contact?.displayName ?? conversationId.substring(0, 8),
        profilePictureBase64: contact?.profilePictureBase64,
      );
    });
    // Keep profile picture in sync
    if (!isGroup && contact?.profilePictureBase64 != null && conv.profilePictureBase64 == null) {
      conv.profilePictureBase64 = contact!.profilePictureBase64;
    }

    // Set readAt for expiry timer: outgoing = read immediately, incoming = read on receipt
    msg.readAt ??= DateTime.now();

    // Dedup by msg.id: Node-level _seenMessageIds is in-memory and resets on
    // every daemon restart, but Store-and-Forward + Erasure replays the same
    // envelope to us whenever we come back online. Without this check, each
    // replay of a MEDIA_ANNOUNCEMENT (or any message) creates a new duplicate
    // row in the conversation with the same msg.id. User-visible symptom:
    // "4× screen_now.png with placeholder" (Bug #R2, 2026-04-18).
    if (msg.id.isNotEmpty) {
      final existingIdx = conv.messages.indexWhere((m) => m.id == msg.id);
      if (existingIdx >= 0) {
        final existing = conv.messages[existingIdx];
        // Upgrade fields conservatively: prefer the newer/stronger state.
        if (msg.mediaState.index > existing.mediaState.index) {
          existing.mediaState = msg.mediaState;
        }
        if (msg.filePath != null && existing.filePath == null) {
          existing.filePath = msg.filePath;
        }
        if (msg.thumbnailBase64 != null && existing.thumbnailBase64 == null) {
          existing.thumbnailBase64 = msg.thumbnailBase64;
        }
        if (msg.status.index > existing.status.index) {
          existing.status = msg.status;
        }
        if (msg.readAt != null && existing.readAt == null) {
          existing.readAt = msg.readAt;
        }
        onStateChanged?.call();
        _saveConversations();
        return false;
      }
    }

    conv.messages.add(msg);
    conv.lastActivity = msg.timestamp;
    if (!msg.isOutgoing &&
        !(_isAppResumed && _activeConversationId == conversationId)) {
      conv.unreadCount++;
      _updateBadgeCount();
    }

    onNewMessage?.call(conversationId, msg);
    onStateChanged?.call();
    _saveConversations();
    return true;
  }

  /// Mark a conversation as read — sends READ_RECEIPTs if enabled.
  @override
  void markConversationRead(String conversationId) {
    final conv = conversations[conversationId];
    if (conv == null) return;

    final hadUnread = conv.unreadCount > 0;
    if (hadUnread) {
      conv.unreadCount = 0;
      onCancelNotificationAndroid?.call(conversationId);
      _updateBadgeCount();
    }

    // Send READ_RECEIPTs for unread incoming messages (if readReceipts enabled).
    // Runs regardless of unreadCount — messages may have status != read even
    // when the badge counter was already cleared.
    if (!conv.config.readReceipts) {
      if (hadUnread) {
        _saveConversations();
        onStateChanged?.call();
      }
      return;
    }

    var sentReceipts = false;
    for (final msg in conv.messages) {
      if (!msg.isOutgoing && msg.status != MessageStatus.read) {
        msg.status = MessageStatus.read;
        sentReceipts = true;
        if (msg.senderNodeIdHex.isEmpty) continue;
        final senderUserId = hexToBytes(msg.senderNodeIdHex);
        final receipt = proto.ReadReceipt()
          ..messageId = hexToBytes(msg.id)
          ..readAt = Int64(DateTime.now().millisecondsSinceEpoch);
        sendToUser(
          recipientUserId: senderUserId,
          messageType: proto.MessageTypeV3.MTV3_READ_RECEIPT,
          payload: receipt.writeToBuffer(),
        );
      }
    }

    if (hadUnread || sentReceipts) {
      _saveConversations();
      onStateChanged?.call();
    }

    if (sentReceipts) {
      _sendTwinSync(proto.TwinSyncType.TWIN_READ_RECEIPT, Uint8List.fromList(utf8.encode(jsonEncode({
        'conversationId': conversationId,
      }))));
    }
  }

  @override
  void setActiveConversationId(String? conversationId) {
    _activeConversationId = conversationId;
  }

  @override
  void setAppResumed(bool isResumed) {
    _isAppResumed = isResumed;
    // §2.2.4: adaptive Liveness-TTL — Foreground 15min, Background 1h.
    _identityPublisher?.setForeground(isResumed);
  }

  /// Decide whether the in-app notification (sound + vibrate + Android banner)
  /// for an incoming message should be suppressed. Three independent layers:
  ///
  ///   L1 — Foreground active conversation: chat is already on screen.
  ///   L2 — Stale backlog: message timestamp older than [_notificationStaleThresholdMs].
  ///        Covers startup re-poll, daemon restart, S&F catch-up — the user
  ///        either already saw these elsewhere or there is no point in beeping
  ///        about old news.
  ///   L3 — Per-conversation debounce: at most one notification every
  ///        [_notificationDebounceMs] ms per conversation, against group-chat
  ///        spam-bursts.
  ///
  /// Badge updates run in a different code path and are NOT gated by this.
  bool _shouldSuppressNotification(String conversationId, int messageTimestampMs) {
    if (_isAppResumed && _activeConversationId == conversationId) return true;
    final ageMs = DateTime.now().millisecondsSinceEpoch - messageTimestampMs;
    if (ageMs > _notificationStaleThresholdMs) return true;
    final last = _lastNotifiedAt[conversationId];
    if (last != null &&
        DateTime.now().difference(last).inMilliseconds < _notificationDebounceMs) {
      return true;
    }
    return false;
  }

  /// Toggle favorite status of a conversation.
  @override
  void toggleFavorite(String conversationId) {
    final conv = conversations[conversationId];
    if (conv == null) return;
    conv.isFavorite = !conv.isFavorite;
    _saveConversations();
    onStateChanged?.call();
  }

  /// Send a typing indicator to a DM conversation partner.
  @override
  void sendTypingIndicator(String conversationId) {
    final conv = conversations[conversationId];
    if (conv == null || conv.isGroup) return;
    if (!conv.config.typingIndicators) return;

    final contact = _contacts[conversationId];
    if (contact == null || contact.status != 'accepted') return;

    final indicator = proto.TypingIndicator()
      ..conversationId = conversationId
      ..isTyping = true;
    sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageTypeV3.MTV3_TYPING_INDICATOR,
      payload: indicator.writeToBuffer(),
    );
  }

  // ── Mutual Peer Selection (Architecture Section 3.3.7) ─────────

  /// Compute set of nodeIdHex that the recipient is likely to know.
  /// Sources: shared contacts (bidirectional) + shared group members.
  Set<String> _computeMutualPeerIds(Uint8List recipientUserId) {
    final recipientHex = bytesToHex(recipientUserId);
    final mutual = <String>{};

    // Source 1: Our accepted contacts — the recipient likely knows them too
    // (contacts are bidirectional: if we accepted them, they accepted us).
    for (final contact in _contacts.values) {
      if (contact.status == 'accepted' && contact.nodeIdHex != recipientHex) {
        mutual.add(contact.nodeIdHex);
      }
    }

    // Source 2: Shared group members — groups where recipient is a member.
    for (final group in _groups.values) {
      if (group.members.containsKey(recipientHex)) {
        for (final memberHex in group.members.keys) {
          if (memberHex != recipientHex && memberHex != identity.userIdHex) {
            mutual.add(memberHex);
          }
        }
      }
    }

    return mutual;
  }

  // ── ServiceContext implementation ───────────────────────────────

  @override
  Map<String, ContactInfo> get contacts => _contacts;
  @override
  ChannelIndex get channelIndex => _channelIndex;
  @override
  void saveChannels() => _saveChannels();
  @override
  void saveConversations() => _saveConversations();
  @override
  void notifyStateChanged() => onStateChanged?.call();
  @override
  bool hasChannelPermission(ChannelInfo channel, String action) =>
      _hasChannelPermission(channel, action);
  @override
  FileEncryption get fileEnc => _fileEnc;
  @override
  Future<void> sendEncryptedPayload(
    Uint8List recipientUserId,
    proto.MessageTypeV3 messageType,
    Uint8List payload, {
    Uint8List? groupId,
  }) => _sendEncryptedPayload(recipientUserId, messageType, payload, groupId: groupId);
  @override
  void addMessageToConversation(String conversationId, UiMessage msg,
      {bool isGroup = false, bool isChannel = false}) =>
      _addMessageToConversation(conversationId, msg, isGroup: isGroup, isChannel: isChannel);

  // ── Groups ──────────────────────────────────────────────────────

  @override
  Map<String, GroupInfo> get groups => Map.unmodifiable(_groups);

  @override
  Future<String?> createGroup(String name, List<String> memberNodeIdHexList) async {
    final sodium = SodiumFFI();
    final groupId = sodium.randomBytes(32);
    final groupIdHex = bytesToHex(groupId);

    // Build member list (self + selected contacts)
    final members = <String, GroupMemberInfo>{};

    // Add self as owner
    members[identity.userIdHex] = GroupMemberInfo(
      nodeIdHex: identity.userIdHex,
      displayName: displayName,
      role: 'owner',
      ed25519Pk: identity.ed25519PublicKey,
      x25519Pk: identity.x25519PublicKey,
      mlKemPk: identity.mlKemPublicKey,
    );

    // Add selected contacts
    for (final nodeIdHex in memberNodeIdHexList) {
      final contact = _contacts[nodeIdHex];
      if (contact == null || contact.status != 'accepted') continue;
      members[nodeIdHex] = GroupMemberInfo(
        nodeIdHex: nodeIdHex,
        displayName: contact.displayName,
        role: 'member',
        ed25519Pk: contact.ed25519Pk,
        x25519Pk: contact.x25519Pk,
        mlKemPk: contact.mlKemPk,
      );
    }

    if (members.length < 2) {
      _log.warn('Group needs at least 2 members');
      return null;
    }

    final group = GroupInfo(
      groupIdHex: groupIdHex,
      name: name,
      ownerNodeIdHex: identity.userIdHex,
      members: members,
      membershipEpoch: 1,
    );
    _groups[groupIdHex] = group;
    _saveGroups();

    // Create conversation
    conversations[groupIdHex] = Conversation(
      id: groupIdHex,
      displayName: name,
      isGroup: true,
    );
    _saveConversations();

    // Send GROUP_INVITE to each member (pairwise encrypted)
    final invite = proto.GroupInviteV3()
      ..groupId = groupId
      ..groupName = name
      ..inviterId = identity.nodeId;
    for (final m in members.values) {
      invite.members.add(proto.GroupMemberV3()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role
        ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
        ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
        ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0));
    }

    // GM-1 (§9.1.4): attach epoch, hash, and hybrid sig
    invite.membershipEpoch = Int64(group.membershipEpoch);
    final createHash = _computeMembershipHash(group.membershipEpoch, groupIdHex, members);
    invite.membershipHash = createHash;
    invite.membershipSigEd25519 = SodiumFFI().signEd25519(createHash, identity.ed25519SecretKey);
    invite.membershipSigMlDsa = OqsFFI().mlDsaSign(createHash, identity.mlDsaSecretKey);

    final inviteBytes = Uint8List.fromList(invite.writeToBuffer());
    // V3: pairwise sendToUser with groupId for receiver-side conversation routing.
    for (final m in members.values) {
      if (m.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(m.nodeIdHex,
          memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;
      final ok = await sendToUser(
        recipientUserId: hexToBytes(m.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_GROUP_INVITE,
        payload: inviteBytes,
        groupId: groupId,
      );
      if (!ok) {
        _log.warn('GROUP_INVITE: no route to ${m.nodeIdHex.substring(0, 8)} (${m.displayName}) — S&F path not yet implemented');
      }
    }

    onStateChanged?.call();
    _log.info('Group "$name" created with ${members.length} members: $groupIdHex');
    return groupIdHex;
  }

  @override
  Future<UiMessage?> sendGroupTextMessage(String groupIdHex, String text, {String? replyToMessageId, String? replyToText, String? replyToSender}) async {
    if (_reducedMode) {
      _log.warn('sendGroupTextMessage blocked: reducedMode active');
      return null;
    }
    final group = _groups[groupIdHex];
    if (group == null) return null;

    // V3 group fan-out: TextMessageV3 sub-message + sendToUser per member.
    // ApplicationFrameV3.group_id (Field 17) carries the conversation tag so
    // receivers dispatch into the matching group tab.
    final tm = proto.TextMessageV3()
      ..text = text
      ..formatHint = 'plain';
    proto.LinkPreview? wirePreview;
    String? previewUrl, previewTitle, previewDescription, previewSiteName, previewThumbnailBase64;
    if (_linkPreviewSettings.enabled && extractFirstUrl(text) != null) {
      try {
        final preview = await _linkPreviewFetcher.fetchPreview(text);
        if (preview != null) {
          wirePreview = preview.toProto();
          previewUrl = preview.url;
          previewTitle = preview.title;
          previewDescription = preview.description;
          previewSiteName = preview.siteName;
          if (preview.thumbnail != null) previewThumbnailBase64 = base64Encode(preview.thumbnail!);
        }
      } catch (e) {
        _log.debug('Link preview fetch failed: $e');
      }
    }
    if (wirePreview != null) tm.linkPreview = wirePreview;
    if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
      try {
        tm.replyToMessageId = hexToBytes(replyToMessageId);
      } catch (_) {
        _log.debug(
            'sendGroupTextMessage: replyToMessageId not hex — wire-tag dropped');
      }
      if (replyToText != null && replyToText.isNotEmpty) {
        tm.replyToSnippet = replyToText.length > 120
            ? '${replyToText.substring(0, 120)}…'
            : replyToText;
      }
    }
    final basePayload = tm.writeToBuffer();
    final groupIdBytes = hexToBytes(groupIdHex);
    // GM-1 (§9.1.4): post-tag with sender's local membership state
    final gmEpoch = group.membershipEpoch;
    final gmHash = _computeMembershipHash(gmEpoch, groupIdHex, group.members);

    final localId = bytesToHex(SodiumFFI().randomBytes(16));
    final msg = UiMessage(
      id: localId,
      conversationId: groupIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: UiMessageType.text,
      status: MessageStatus.sending,
      isOutgoing: true,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSender: replyToSender,
    );
    if (previewUrl != null) {
      msg.linkPreviewUrl = previewUrl;
      msg.linkPreviewTitle = previewTitle;
      msg.linkPreviewDescription = previewDescription;
      msg.linkPreviewSiteName = previewSiteName;
      msg.linkPreviewThumbnailBase64 = previewThumbnailBase64;
    }

    _addMessageToConversation(groupIdHex, msg, isGroup: true);

    await Future.delayed(Duration.zero);

    bool anySent = false;
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      final ok = await sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_TEXT,
        payload: basePayload,
        groupId: groupIdBytes,
        groupMembershipEpoch: gmEpoch,
        groupMembershipHash: gmHash,
      );
      if (ok) anySent = true;
    }

    msg.status = anySent ? MessageStatus.sent : MessageStatus.failed;
    if (anySent) node.statsCollector.addMessageSent();
    onStateChanged?.call();
    _saveConversations();
    return msg;
  }

  @override
  Future<bool> leaveGroup(String groupIdHex) async {
    final group = _groups[groupIdHex];
    if (group == null) return false;

    // If owner leaving, transfer ownership to first admin (or first member)
    if (group.ownerNodeIdHex == identity.userIdHex && group.members.length > 1) {
      final otherMembers = group.members.values.where((m) => m.nodeIdHex != identity.userIdHex);
      final newOwner = otherMembers.where((m) => m.role == 'admin').firstOrNull
          ?? otherMembers.first;
      newOwner.role = 'owner';
      group.ownerNodeIdHex = newOwner.nodeIdHex;
      _log.info('Ownership transferred to ${newOwner.displayName} before leaving');
    }

    // Remove self from member list before broadcasting
    group.members.remove(identity.userIdHex);
    group.membershipEpoch++;

    // Broadcast updated group (without us) to remaining members
    if (group.members.isNotEmpty) {
      await _broadcastGroupUpdate(group);
    }

    // V3 GROUP_LEAVE fan-out
    final leaveMsg = proto.GroupLeave()..groupId = hexToBytes(groupIdHex);
    final leaveBytes = Uint8List.fromList(leaveMsg.writeToBuffer());
    final groupIdBytes = hexToBytes(groupIdHex);
    for (final member in group.members.values) {
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(member.nodeIdHex,
          memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;
      sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_GROUP_LEAVE,
        payload: leaveBytes,
        groupId: groupIdBytes,
      );
    }

    _groups.remove(groupIdHex);
    // Remove the conversation too — we're no longer in this group
    conversations.remove(groupIdHex);
    _saveGroups();
    _saveConversations();
    onStateChanged?.call();
    _log.info('Left group $groupIdHex');
    return true;
  }

  @override
  Future<bool> inviteToGroup(String groupIdHex, String memberNodeIdHex) async {
    final group = _groups[groupIdHex];
    if (group == null) return false;

    // Owner or Admin can invite
    if (!_hasGroupPermission(group, 'invite')) return false;

    final contact = _contacts[memberNodeIdHex];
    if (contact == null || contact.status != 'accepted') return false;
    if (contact.x25519Pk == null || contact.mlKemPk == null) return false;

    // Add member to group
    group.members[memberNodeIdHex] = GroupMemberInfo(
      nodeIdHex: memberNodeIdHex,
      displayName: contact.displayName,
      role: 'member',
      ed25519Pk: contact.ed25519Pk,
      x25519Pk: contact.x25519Pk,
      mlKemPk: contact.mlKemPk,
    );
    group.membershipEpoch++;
    _saveGroups();

    // Send GROUP_INVITE to new member AND broadcast updated member list to
    // existing members — otherwise their local state stays stale and they
    // can't target the new member for role changes, messages, etc.
    await _broadcastGroupUpdate(group);

    // System message
    final sysMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: groupIdHex,
      senderNodeIdHex: '',
      text: '${contact.displayName} wurde eingeladen',
      timestamp: DateTime.now(),
      type: UiMessageType.groupInvite,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    _addMessageToConversation(groupIdHex, sysMsg, isGroup: true);

    _log.info('Invited ${contact.displayName} to group "${group.name}"');
    return true;
  }

  @override
  Future<bool> removeMemberFromGroup(String groupIdHex, String memberNodeIdHex) async {
    final group = _groups[groupIdHex];
    if (group == null) return false;

    // Owner or Admin can remove
    if (!_hasGroupPermission(group, 'remove')) return false;
    // Can't remove self (use leaveGroup)
    if (memberNodeIdHex == identity.userIdHex) return false;

    final memberName = group.members[memberNodeIdHex]?.displayName ?? memberNodeIdHex.substring(0, 8);
    group.members.remove(memberNodeIdHex);
    group.membershipEpoch++;
    _saveGroups();

    // Broadcast updated member list to all remaining members
    await _broadcastGroupUpdate(group);

    // System message
    final sysMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: groupIdHex,
      senderNodeIdHex: '',
      text: '$memberName wurde entfernt',
      timestamp: DateTime.now(),
      type: UiMessageType.groupLeave,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    _addMessageToConversation(groupIdHex, sysMsg, isGroup: true);

    onStateChanged?.call();
    _log.info('Removed $memberName from group "${group.name}"');
    return true;
  }

  @override
  Future<bool> setMemberRole(String entityIdHex, String memberNodeIdHex, String role) async {
    // Dual-mode: works for both groups and channels (Architecture v3.0 Section 10.2)
    final group = _groups[entityIdHex];
    final channel = _channels[entityIdHex];
    if (group == null && channel == null) return false;

    final validRoles = group != null
        ? ['owner', 'admin', 'member']
        : ['owner', 'admin', 'subscriber'];
    if (!validRoles.contains(role)) return false;

    // Can't change own role
    if (memberNodeIdHex == identity.userIdHex) return false;

    if (group != null) {
      // Permission: Owner only. Architecture §10.2: "Owner … appoints Admins".
      // Admins can invite/remove members + moderate content, but cannot change roles.
      final myMember = group.members[identity.userIdHex];
      if (myMember == null || myMember.role != 'owner') return false;

      final member = group.members[memberNodeIdHex];
      if (member == null) return false;

      final oldRole = member.role;
      member.role = role;

      if (role == 'owner') {
        group.members[identity.userIdHex]?.role = 'admin';
        group.ownerNodeIdHex = memberNodeIdHex;
      }

      group.membershipEpoch++;
      _saveGroups();
      await _broadcastGroupUpdate(group);
      _broadcastRoleUpdate(entityIdHex, memberNodeIdHex, role, group.members);

      final sysMsg = UiMessage(
        id: bytesToHex(SodiumFFI().randomBytes(16)),
        conversationId: entityIdHex,
        senderNodeIdHex: '',
        text: '${member.displayName}: $oldRole → $role',
        timestamp: DateTime.now(),
        type: UiMessageType.channelRoleUpdate,
        status: MessageStatus.delivered,
        isOutgoing: false,
      );
      _addMessageToConversation(entityIdHex, sysMsg, isGroup: true);
      _log.info('Role changed: ${member.displayName} $oldRole -> $role in group "${group.name}"');

    } else {
      // Channel — same rule as groups: Owner only can change roles (§10.2).
      final myMember = channel!.members[identity.userIdHex];
      if (myMember == null || myMember.role != 'owner') return false;

      final member = channel.members[memberNodeIdHex];
      if (member == null) return false;

      final oldRole = member.role;
      member.role = role;

      if (role == 'owner') {
        channel.members[identity.userIdHex]?.role = 'admin';
        channel.ownerNodeIdHex = memberNodeIdHex;
      }

      channel.membershipEpoch++;
      _saveChannels();
      _broadcastRoleUpdate(entityIdHex, memberNodeIdHex, role, channel.members);

      final sysMsg = UiMessage(
        id: bytesToHex(SodiumFFI().randomBytes(16)),
        conversationId: entityIdHex,
        senderNodeIdHex: '',
        text: '${member.displayName}: $oldRole → $role',
        timestamp: DateTime.now(),
        type: UiMessageType.channelRoleUpdate,
        status: MessageStatus.delivered,
        isOutgoing: false,
      );
      _addMessageToConversation(entityIdHex, sysMsg, isChannel: true);
      _log.info('Role changed: ${member.displayName} $oldRole -> $role in channel "${channel.name}"');
    }

    onStateChanged?.call();
    return true;
  }

  /// Broadcast CHANNEL_ROLE_UPDATE to all members of a group or channel.
  /// Architecture v3.0: "must be sent to ALL members, not just the affected member"
  void _broadcastRoleUpdate(String entityIdHex, String targetIdHex, String newRole,
      Map<String, dynamic> members) {
    final roleUpdate = proto.ChannelRoleUpdate()
      ..channelId = hexToBytes(entityIdHex)
      ..targetId = hexToBytes(targetIdHex)
      ..newRole = newRole;

    final roleBytes = Uint8List.fromList(roleUpdate.writeToBuffer());
    final entityIdBytes = hexToBytes(entityIdHex);
    for (final entry in members.entries) {
      final mHex = entry.key;
      if (mHex == identity.userIdHex) continue;
      final m = entry.value;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(mHex,
          memberX25519Pk: m.x25519Pk as Uint8List?,
          memberMlKemPk: m.mlKemPk as Uint8List?);
      if (x25519Pk == null || mlKemPk == null) continue;
      sendToUser(
        recipientUserId: hexToBytes(mHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_ROLE_UPDATE,
        payload: roleBytes,
        groupId: entityIdBytes,
      );
    }
  }

  /// GM-1 (§9.1.4): canonical membership hash.
  /// SHA-256(epoch_le64 || groupId_bytes || Σ sorted(nodeId || role_utf8))
  Uint8List _computeMembershipHash(int epoch, String groupIdHex, Map<String, GroupMemberInfo> members) {
    final sorted = members.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final parts = <int>[];
    final epochBytes = ByteData(8)..setUint64(0, epoch, Endian.little);
    parts.addAll(epochBytes.buffer.asUint8List());
    parts.addAll(hexToBytes(groupIdHex));
    for (final e in sorted) {
      parts.addAll(hexToBytes(e.key));
      parts.addAll(utf8.encode(e.value.role));
    }
    return SodiumFFI().sha256(Uint8List.fromList(parts));
  }

  /// Build a signed GROUP_INVITE payload from current group state.
  Uint8List _buildSignedGroupInviteBytes(GroupInfo group) {
    final invite = proto.GroupInviteV3()
      ..groupId = hexToBytes(group.groupIdHex)
      ..groupName = group.name
      ..inviterId = identity.nodeId;
    for (final m in group.members.values) {
      invite.members.add(proto.GroupMemberV3()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role
        ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
        ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
        ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0));
    }
    invite.membershipEpoch = Int64(group.membershipEpoch);
    final hash = _computeMembershipHash(group.membershipEpoch, group.groupIdHex, group.members);
    invite.membershipHash = hash;
    invite.membershipSigEd25519 = SodiumFFI().signEd25519(hash, identity.ed25519SecretKey);
    invite.membershipSigMlDsa = OqsFFI().mlDsaSign(hash, identity.mlDsaSecretKey);
    return Uint8List.fromList(invite.writeToBuffer());
  }

  /// Broadcast updated group member list to all members via GROUP_INVITE.
  Future<void> _broadcastGroupUpdate(GroupInfo group) async {
    final groupId = hexToBytes(group.groupIdHex);
    final inviteBytes = _buildSignedGroupInviteBytes(group);
    bool anyFailed = false;
    for (final m in group.members.values) {
      if (m.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(m.nodeIdHex,
          memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;
      final ok = await sendToUser(
        recipientUserId: hexToBytes(m.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_GROUP_INVITE,
        payload: inviteBytes,
        groupId: groupId,
      );
      if (!ok) {
        _log.warn('GROUP_UPDATE broadcast: no route to ${m.nodeIdHex.substring(0, 8)} (${m.displayName})');
        _pendingMembershipResends
            .putIfAbsent(group.groupIdHex, () => {})
            .add(m.nodeIdHex);
        anyFailed = true;
      }
    }
    if (anyFailed) _savePendingMembershipResends();
    _log.info('Broadcast group update for "${group.name}" to ${group.members.length - 1} members');
  }

  /// Check if caller has permission for group action.
  bool _hasGroupPermission(GroupInfo group, String action) {
    final myMember = group.members[identity.userIdHex];
    if (myMember == null) return false;

    switch (action) {
      case 'invite':
        return myMember.role == 'owner' || myMember.role == 'admin';
      case 'remove':
        return myMember.role == 'owner' || myMember.role == 'admin';
      case 'change_role':
        return myMember.role == 'owner';
      case 'config':
        return myMember.role == 'owner' || myMember.role == 'admin';
      default:
        return false;
    }
  }

  // ── Channels ────────────────────────────────────────────────────

  @override
  Map<String, ChannelInfo> get channels => Map.unmodifiable(_channels);

  @override
  Future<String?> createChannel(String name, List<String> subscriberNodeIdHexList, {
    bool isPublic = false,
    bool isAdult = true,
    String language = 'de',
    String? description,
    String? pictureBase64,
  }) async {
    final sodium = SodiumFFI();
    final channelId = sodium.randomBytes(32);
    final channelIdHex = bytesToHex(channelId);

    // Build member list (self as owner + selected contacts as subscribers)
    final members = <String, ChannelMemberInfo>{};

    // Add self as owner
    members[identity.userIdHex] = ChannelMemberInfo(
      nodeIdHex: identity.userIdHex,
      displayName: displayName,
      role: 'owner',
      ed25519Pk: identity.ed25519PublicKey,
      x25519Pk: identity.x25519PublicKey,
      mlKemPk: identity.mlKemPublicKey,
    );

    // For private channels, require at least 1 subscriber
    // For public channels, subscribers are optional (people join via search)
    if (!isPublic) {
      for (final nodeIdHex in subscriberNodeIdHexList) {
        final contact = _contacts[nodeIdHex];
        if (contact == null || contact.status != 'accepted') continue;
        members[nodeIdHex] = ChannelMemberInfo(
          nodeIdHex: nodeIdHex,
          displayName: contact.displayName,
          role: 'subscriber',
          ed25519Pk: contact.ed25519Pk,
          x25519Pk: contact.x25519Pk,
          mlKemPk: contact.mlKemPk,
        );
      }

      if (members.length < 2) {
        _log.warn('Private channel needs at least 1 subscriber');
        return null;
      }
    } else {
      // Public channels can also pre-invite contacts
      for (final nodeIdHex in subscriberNodeIdHexList) {
        final contact = _contacts[nodeIdHex];
        if (contact == null || contact.status != 'accepted') continue;
        members[nodeIdHex] = ChannelMemberInfo(
          nodeIdHex: nodeIdHex,
          displayName: contact.displayName,
          role: 'subscriber',
          ed25519Pk: contact.ed25519Pk,
          x25519Pk: contact.x25519Pk,
          mlKemPk: contact.mlKemPk,
        );
      }
    }

    final channel = ChannelInfo(
      channelIdHex: channelIdHex,
      name: name,
      description: description,
      pictureBase64: pictureBase64,
      ownerNodeIdHex: identity.userIdHex,
      members: members,
      isPublic: isPublic,
      isAdult: isAdult,
      language: language,
      membershipEpoch: 1,
    );
    _channels[channelIdHex] = channel;
    _saveChannels();

    // Create conversation
    conversations[channelIdHex] = Conversation(
      id: channelIdHex,
      displayName: name,
      isChannel: true,
    );
    _saveConversations();

    // Send CHANNEL_INVITE to each subscriber (pairwise encrypted)
    if (members.length > 1) {
      await _broadcastChannelUpdate(channel);
    }

    // Publish to DHT channel index if public
    if (isPublic) {
      _channelIndex.upsert(ChannelIndexEntry(
        channelIdHex: channelIdHex,
        name: name,
        language: language,
        isAdult: isAdult,
        description: description,
        subscriberCount: members.length,
        ownerNodeIdHex: identity.userIdHex,
        createdAt: channel.createdAt,
      ));
      _channelIndex.save();
    }

    onStateChanged?.call();
    _log.info('Channel "$name" created (public=$isPublic, adult=$isAdult, lang=$language) with ${members.length} members: $channelIdHex');
    return channelIdHex;
  }

  @override
  Future<UiMessage?> sendChannelPost(String channelIdHex, String text) async {
    if (_reducedMode) {
      _log.warn('sendChannelPost blocked: reducedMode active');
      return null;
    }
    final channel = _channels[channelIdHex];
    if (channel == null) return null;

    // §9.5.7 (S119 D1): system channels are ownerless and have no member
    // fan-out — posts travel as self-signed SystemChannelRecords via the
    // SYSCHAN gossip. The old CHANNEL_POST path fanned out over the always-
    // empty members map (Problem 4/6: posts never left the local node).
    if (SystemChannels.isSystemChannel(channelIdHex)) {
      final stored = await _publishSystemChannelRecord(
          channelIdHex: channelIdHex, kind: SysChanKind.post, text: text);
      if (stored == null) return null;
      node.statsCollector.addMessageSent();
      final conv = conversations[channelIdHex];
      final recordIdHex =
          bytesToHex(Uint8List.fromList(stored.record.recordId));
      for (final m in conv?.messages ?? const <UiMessage>[]) {
        if (m.id == recordIdHex) return m;
      }
      return null;
    }

    // Only owner/admin can post
    if (!_hasChannelPermission(channel, 'post')) {
      _log.warn('No permission to post in channel');
      return null;
    }

    // V3 CHANNEL_POST: TextMessageV3 sub-message + sendToUser per member with
    // groupId so receivers route to the channel tab.
    final tm = proto.TextMessageV3()
      ..text = text
      ..formatHint = 'plain';
    proto.LinkPreview? wirePreview;
    String? previewUrl, previewTitle, previewDescription, previewSiteName, previewThumbnailBase64;
    if (_linkPreviewSettings.enabled && extractFirstUrl(text) != null) {
      try {
        final preview = await _linkPreviewFetcher.fetchPreview(text);
        if (preview != null) {
          wirePreview = preview.toProto();
          previewUrl = preview.url;
          previewTitle = preview.title;
          previewDescription = preview.description;
          previewSiteName = preview.siteName;
          if (preview.thumbnail != null) previewThumbnailBase64 = base64Encode(preview.thumbnail!);
        }
      } catch (e) {
        _log.debug('Link preview fetch failed: $e');
      }
    }
    if (wirePreview != null) tm.linkPreview = wirePreview;
    final basePayload = Uint8List.fromList(tm.writeToBuffer());
    final channelIdBytes = hexToBytes(channelIdHex);

    // GM-4 (§9.1.4): tag channel posts with membership epoch+hash
    final chEpoch = channel.membershipEpoch;
    final chHash = _computeChannelMembershipHash(chEpoch, channelIdHex, channel.members);

    String? firstMsgId;

    for (final member in channel.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(member.nodeIdHex,
          memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;
      sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_POST,
        payload: basePayload,
        groupId: channelIdBytes,
        groupMembershipEpoch: chEpoch,
        groupMembershipHash: chHash,
      );
    }

    // If no other members received the post, generate a local message ID
    // (e.g. owner-only public channel — post is stored locally for future subscribers)
    firstMsgId ??= bytesToHex(SodiumFFI().randomBytes(16));
    node.statsCollector.addMessageSent();

    // Create single UI message
    final msg = UiMessage(
      id: firstMsgId,
      conversationId: channelIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: UiMessageType.channelPost,
      status: MessageStatus.sent,
      isOutgoing: true,
    );
    if (previewUrl != null) {
      msg.linkPreviewUrl = previewUrl;
      msg.linkPreviewTitle = previewTitle;
      msg.linkPreviewDescription = previewDescription;
      msg.linkPreviewSiteName = previewSiteName;
      msg.linkPreviewThumbnailBase64 = previewThumbnailBase64;
    }

    _addMessageToConversation(channelIdHex, msg, isChannel: true);

    return msg;
  }

  @override
  Future<bool> leaveChannel(String channelIdHex) async {
    final channel = _channels[channelIdHex];
    if (channel == null) return false;

    // If owner leaving, transfer ownership to first admin (or first member)
    if (channel.ownerNodeIdHex == identity.userIdHex && channel.members.length > 1) {
      final otherMembers = channel.members.values.where((m) => m.nodeIdHex != identity.userIdHex);
      final newOwner = otherMembers.where((m) => m.role == 'admin').firstOrNull
          ?? otherMembers.first;
      newOwner.role = 'owner';
      channel.ownerNodeIdHex = newOwner.nodeIdHex;
      _log.info('Channel ownership transferred to ${newOwner.displayName} before leaving');
    }

    // Remove self from member list before broadcasting
    channel.members.remove(identity.userIdHex);
    channel.membershipEpoch++;

    // Broadcast updated channel (without us) to remaining members
    if (channel.members.isNotEmpty) {
      await _broadcastChannelUpdate(channel);
    }

    // V3 CHANNEL_LEAVE fan-out
    final leaveMsg = proto.ChannelLeave()..channelId = hexToBytes(channelIdHex);
    final leaveBytes = Uint8List.fromList(leaveMsg.writeToBuffer());
    final channelIdBytes = hexToBytes(channelIdHex);
    for (final member in channel.members.values) {
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(member.nodeIdHex,
          memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;
      sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_LEAVE,
        payload: leaveBytes,
        groupId: channelIdBytes,
      );
    }

    _channels.remove(channelIdHex);
    conversations.remove(channelIdHex);
    _saveChannels();
    _saveConversations();
    onStateChanged?.call();
    _log.info('Left channel $channelIdHex');
    return true;
  }

  @override
  Future<bool> inviteToChannel(String channelIdHex, String memberNodeIdHex) async {
    final channel = _channels[channelIdHex];
    if (channel == null) return false;

    // Owner or Admin can invite
    if (!_hasChannelPermission(channel, 'invite')) return false;

    final contact = _contacts[memberNodeIdHex];
    if (contact == null || contact.status != 'accepted') return false;
    if (contact.x25519Pk == null || contact.mlKemPk == null) return false;

    // Add as subscriber
    channel.members[memberNodeIdHex] = ChannelMemberInfo(
      nodeIdHex: memberNodeIdHex,
      displayName: contact.displayName,
      role: 'subscriber',
      ed25519Pk: contact.ed25519Pk,
      x25519Pk: contact.x25519Pk,
      mlKemPk: contact.mlKemPk,
    );
    channel.membershipEpoch++;
    _saveChannels();

    // Broadcast updated member list to all members
    await _broadcastChannelUpdate(channel);

    // System message
    final sysMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: channelIdHex,
      senderNodeIdHex: '',
      text: '${contact.displayName} wurde eingeladen',
      timestamp: DateTime.now(),
      type: UiMessageType.channelInvite,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    _addMessageToConversation(channelIdHex, sysMsg, isChannel: true);

    _log.info('Invited ${contact.displayName} to channel "${channel.name}"');
    return true;
  }

  @override
  Future<bool> removeFromChannel(String channelIdHex, String memberNodeIdHex) async {
    final channel = _channels[channelIdHex];
    if (channel == null) return false;

    // Owner or Admin can remove
    if (!_hasChannelPermission(channel, 'remove')) return false;
    if (memberNodeIdHex == identity.userIdHex) return false;

    final memberName = channel.members[memberNodeIdHex]?.displayName ?? memberNodeIdHex.substring(0, 8);
    channel.members.remove(memberNodeIdHex);
    channel.membershipEpoch++;
    _saveChannels();

    // Broadcast updated member list
    await _broadcastChannelUpdate(channel);

    // System message
    final sysMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: channelIdHex,
      senderNodeIdHex: '',
      text: '$memberName wurde entfernt',
      timestamp: DateTime.now(),
      type: UiMessageType.channelLeave,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    _addMessageToConversation(channelIdHex, sysMsg, isChannel: true);

    onStateChanged?.call();
    _log.info('Removed $memberName from channel "${channel.name}"');
    return true;
  }

  @override
  Future<bool> setChannelRole(String channelIdHex, String memberNodeIdHex, String role) async {
    // B-31: delegate to the dual-mode setMemberRole. It broadcasts the atomic
    // MTV3_CHANNEL_ROLE_UPDATE — the receiver patches only the one member's role +
    // ownerNodeIdHex (_handleChannelRoleUpdateV3). The previous body broadcast a
    // CHANNEL_INVITE (full member-list rebuild via _broadcastChannelUpdate), which
    // races on the receiver: after an ownership transfer the freshly-promoted
    // owner's node could fire its first role change before the INVITE rebuilt its
    // local channel, so its owner-guard rejected the change (gui-40 40b.17).
    // Both GUI in-process callers (home_screen, chat_screen) and the IPC path now
    // share this atomic route.
    return setMemberRole(channelIdHex, memberNodeIdHex, role);
  }

  Uint8List _computeChannelMembershipHash(
      int epoch, String channelIdHex, Map<String, ChannelMemberInfo> members) {
    final sorted = members.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final parts = <int>[];
    final epochBytes = ByteData(8)..setUint64(0, epoch, Endian.little);
    parts.addAll(epochBytes.buffer.asUint8List());
    parts.addAll(hexToBytes(channelIdHex));
    for (final e in sorted) {
      parts.addAll(hexToBytes(e.key));
      parts.addAll(utf8.encode(e.value.role));
    }
    return SodiumFFI().sha256(Uint8List.fromList(parts));
  }

  /// Build a signed CHANNEL_INVITE payload from current channel state.
  Uint8List _buildSignedChannelInviteBytes(ChannelInfo channel) {
    final invite = proto.ChannelInvite()
      ..channelId = hexToBytes(channel.channelIdHex)
      ..channelName = channel.name
      ..inviterId = identity.nodeId
      ..isPublic = channel.isPublic
      ..isAdult = channel.isAdult
      ..language = channel.language;
    if (channel.description != null) invite.channelDescription = channel.description!;
    for (final m in channel.members.values) {
      invite.members.add(proto.GroupMemberV3()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role
        ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
        ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
        ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0));
    }
    invite.membershipEpoch = Int64(channel.membershipEpoch);
    final hash = _computeChannelMembershipHash(
        channel.membershipEpoch, channel.channelIdHex, channel.members);
    invite.membershipHash = hash;
    invite.membershipSigEd25519 =
        SodiumFFI().signEd25519(hash, identity.ed25519SecretKey);
    invite.membershipSigMlDsa =
        OqsFFI().mlDsaSign(hash, identity.mlDsaSecretKey);
    return Uint8List.fromList(invite.writeToBuffer());
  }

  /// Broadcast updated channel member list to all members via CHANNEL_INVITE.
  Future<void> _broadcastChannelUpdate(ChannelInfo channel) async {
    final channelId = hexToBytes(channel.channelIdHex);
    final inviteBytes = _buildSignedChannelInviteBytes(channel);
    bool anyFailed = false;
    for (final m in channel.members.values) {
      if (m.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(m.nodeIdHex,
          memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;
      final ok = await sendToUser(
        recipientUserId: hexToBytes(m.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_INVITE,
        payload: inviteBytes,
        groupId: channelId,
      );
      if (!ok) {
        _log.warn('CHANNEL_UPDATE broadcast: no route to ${m.nodeIdHex.substring(0, 8)} (${m.displayName})');
        _pendingMembershipResends
            .putIfAbsent(channel.channelIdHex, () => {})
            .add(m.nodeIdHex);
        anyFailed = true;
      }
    }
    if (anyFailed) _savePendingMembershipResends();
    _log.info('Broadcast channel update for "${channel.name}" to ${channel.members.length - 1} members');
  }

  // ── Public Channel Operations (delegated to ChannelModerationService) ──

  @override
  Future<List<ChannelIndexEntry>> searchPublicChannels({
    String? query,
    String? language,
    bool? includeAdult,
  }) => _moderation.searchPublicChannels(query: query, language: language, includeAdult: includeAdult);

  @override
  Future<bool> publishChannelToIndex(String channelIdHex) async {
    final channel = _channels[channelIdHex];
    if (channel == null || !channel.isPublic) return false;
    if (channel.ownerNodeIdHex != identity.userIdHex) return false;

    _channelIndex.upsert(ChannelIndexEntry(
      channelIdHex: channelIdHex,
      name: channel.name,
      language: channel.language,
      isAdult: channel.isAdult,
      description: channel.description,
      subscriberCount: channel.members.length,
      badBadgeLevel: channel.badBadgeLevel,
      badBadgeSince: channel.badBadgeSince,
      correctionSubmitted: channel.correctionSubmitted,
      ownerNodeIdHex: channel.ownerNodeIdHex,
      createdAt: channel.createdAt,
    ));
    _channelIndex.save();
    _log.info('Published channel "${channel.name}" to index');
    return true;
  }

  // ── Moderation (delegated to ChannelModerationService) ─────────

  @override
  Future<bool> reportChannel(String channelIdHex, int category, List<String> evidencePostIds, {String? description}) =>
      _moderation.reportChannel(channelIdHex, category, evidencePostIds, description: description);
  @override
  Future<bool> reportPost(String channelIdHex, String postId, int category, {String? description}) =>
      _moderation.reportPost(channelIdHex, postId, category, description: description);
  @override
  List<JuryRequest> get pendingJuryRequests => _moderation.pendingJuryRequestsList;
  @override
  Map<String, dynamic> getChannelModerationInfo(String channelIdHex) =>
      _moderation.getChannelModerationInfo(channelIdHex);
  @override
  Future<bool> dismissPostReport(String channelIdHex, String reportId) =>
      _moderation.dismissPostReport(channelIdHex, reportId);
  @override
  Future<bool> submitBadgeCorrection(String channelIdHex, {String? newName, String? newDescription}) =>
      _moderation.submitBadgeCorrection(channelIdHex, newName: newName, newDescription: newDescription);
  @override
  Future<bool> contestCsamHide(String channelIdHex) =>
      _moderation.contestCsamHide(channelIdHex);
  @override
  Future<bool> submitJuryVote(String juryId, String reportId, int vote, {String? reason}) =>
      _moderation.submitJuryVote(juryId, reportId, vote, reason: reason);
  @override
  Future<bool> joinPublicChannel(String channelIdHex) =>
      _moderation.joinPublicChannel(channelIdHex);

  // ── End moderation delegation ─────────────────────────────────
  /// Check if caller has permission for channel action.
  bool _hasChannelPermission(ChannelInfo channel, String action) {
    // System channels (§9.5): zero-owner, any member can post
    if (SystemChannels.isSystemChannel(channel.channelIdHex)) {
      if (action == 'post') return true;
      return false;
    }

    final myMember = channel.members[identity.userIdHex];
    if (myMember == null) return false;

    switch (action) {
      case 'post':
        return myMember.role == 'owner' || myMember.role == 'admin';
      case 'invite':
        return myMember.role == 'owner' || myMember.role == 'admin';
      case 'remove':
        return myMember.role == 'owner' || myMember.role == 'admin';
      case 'change_role':
        return myMember.role == 'owner';
      case 'config':
        return myMember.role == 'owner' || myMember.role == 'admin';
      default:
        return false;
    }
  }

  // ── Profile Picture ─────────────────────────────────────────────

  @override
  String? get profilePictureBase64 => _profilePictureBase64;

  @override
  Future<bool> setProfilePicture(String? base64Jpeg) async {
    // Validate size (max 64KB decoded)
    if (base64Jpeg != null) {
      final bytes = base64Decode(base64Jpeg);
      if (bytes.length > 64 * 1024) {
        _log.warn('Profile picture too large: ${bytes.length} bytes (max 64KB)');
        return false;
      }
    }

    _profilePictureBase64 = base64Jpeg;
    _saveProfilePicture();

    // Broadcast PROFILE_UPDATE (picture + description) to all accepted contacts
    _broadcastProfileUpdate();

    onStateChanged?.call();
    _log.info('Profile picture ${base64Jpeg != null ? "set" : "removed"}, broadcast to ${acceptedContacts.length} contacts');
    return true;
  }

  void _loadProfilePicture() {
    try {
      final file = File('$profileDir/profile_picture.b64');
      if (file.existsSync()) {
        _profilePictureBase64 = file.readAsStringSync().trim();
        if (_profilePictureBase64!.isEmpty) _profilePictureBase64 = null;
      }
    } catch (e) {
      _log.debug('Failed to load profile picture: $e');
    }
  }

  void _saveProfilePicture() {
    try {
      final file = File('$profileDir/profile_picture.b64');
      if (_profilePictureBase64 != null) {
        file.writeAsStringSync(_profilePictureBase64!);
      } else if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      _log.debug('Failed to save profile picture: $e');
    }
  }

  // ── Profile Description ─────────────────────────────────────────────

  @override
  String? get profileDescription => _profileDescription;

  @override
  Future<bool> setProfileDescription(String? description) async {
    if (description != null && description.length > 500) {
      _log.warn('Profile description too long: ${description.length} chars (max 500)');
      return false;
    }

    _profileDescription = (description != null && description.isEmpty) ? null : description;
    _saveProfileDescription();

    // Broadcast PROFILE_UPDATE with description to all accepted contacts
    _broadcastProfileUpdate();

    onStateChanged?.call();
    _log.info('Profile description ${_profileDescription != null ? "set" : "removed"}');
    return true;
  }

  void _loadProfileDescription() {
    try {
      final file = File('$profileDir/profile_description.txt');
      if (file.existsSync()) {
        final text = file.readAsStringSync().trim();
        _profileDescription = text.isNotEmpty ? text : null;
      }
    } catch (e) {
      _log.debug('Failed to load profile description: $e');
    }
  }

  void _saveProfileDescription() {
    try {
      final file = File('$profileDir/profile_description.txt');
      if (_profileDescription != null) {
        file.writeAsStringSync(_profileDescription!);
      } else if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      _log.debug('Failed to save profile description: $e');
    }
  }

  // ── Media Settings ──────────────────────────────────────────────────

  @override
  MediaSettings get mediaSettings => _mediaSettings;

  @override
  Future<bool> setPort(int newPort) async {
    try {
      await node.changePort(newPort);
      port = newPort;
      IdentityManager().updatePort(newPort);
      onStateChanged?.call();
      return true;
    } on SocketException {
      return false;
    }
  }

  @override
  void updateMediaSettings(MediaSettings settings) {
    _mediaSettings = settings;
    _saveMediaSettings();
    onStateChanged?.call();
    _log.info('Media settings updated');
  }

  void _loadMediaSettings() {
    try {
      final file = File('$profileDir/media_settings.json');
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        _mediaSettings = MediaSettings.fromJson(json);
      }
    } catch (e) {
      _log.debug('Failed to load media settings: $e');
    }
  }

  void _saveMediaSettings() {
    try {
      final file = File('$profileDir/media_settings.json');
      file.writeAsStringSync(jsonEncode(_mediaSettings.toJson()));
    } catch (e) {
      _log.debug('Failed to save media settings: $e');
    }
  }

  @override
  bool get serveBinaryUpdates => true;

  // ── Link Preview Settings ────────────────────────────────────────────

  @override
  LinkPreviewSettings get linkPreviewSettings => _linkPreviewSettings;

  @override
  void updateLinkPreviewSettings(LinkPreviewSettings settings) {
    _linkPreviewSettings = settings;
    _linkPreviewFetcher = LinkPreviewFetcher(
      settings: _linkPreviewSettings,
      log: (msg) => _log.debug(msg),
    );
    _saveLinkPreviewSettings();
    onStateChanged?.call();
    _log.info('Link preview settings updated');
  }

  void _loadLinkPreviewSettings() {
    try {
      final file = File('$profileDir/link_preview_settings.json');
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        _linkPreviewSettings = LinkPreviewSettings.fromJson(json);
      }
    } catch (e) {
      _log.debug('Failed to load link preview settings: $e');
    }
  }

  void _saveLinkPreviewSettings() {
    try {
      final file = File('$profileDir/link_preview_settings.json');
      file.writeAsStringSync(jsonEncode(_linkPreviewSettings.toJson()));
    } catch (e) {
      _log.debug('Failed to save link preview settings: $e');
    }
  }

  // ── NFC Contact Exchange ─────────────────────────────────────────────

  @override
  Uint8List? get ed25519PublicKey => identity.ed25519PublicKey;

  @override
  Uint8List? get mlDsaPublicKey => identity.mlDsaPublicKey;

  @override
  Uint8List? get x25519PublicKey => identity.x25519PublicKey;

  @override
  Uint8List? get mlKemPublicKey => identity.mlKemPublicKey;

  @override
  Uint8List? get profilePicture =>
      _profilePictureBase64 != null ? base64Decode(_profilePictureBase64!) : null;

  @override
  Uint8List signEd25519(Uint8List message) =>
      SodiumFFI().signEd25519(message, identity.ed25519SecretKey);

  @override
  bool verifyEd25519(Uint8List message, Uint8List signature, Uint8List publicKey) =>
      SodiumFFI().verifyEd25519(message, signature, publicKey);

  @override
  void addNfcContact(Contact contact) {
    final hex = bytesToHex(contact.nodeId);
    final info = ContactInfo(
      nodeId: Uint8List.fromList(contact.nodeId),
      displayName: contact.displayName,
      ed25519Pk: contact.ed25519Pk,
      mlDsaPk: contact.mlDsaPk,
      x25519Pk: contact.x25519Pk,
      mlKemPk: contact.mlKemPk,
      status: 'accepted',
      verificationLevel: 'verified',
      acceptedAt: DateTime.now(),
      profilePictureBase64: contact.profilePicture != null
          ? base64Encode(contact.profilePicture!)
          : null,
    );
    _contacts[hex] = info;
    _saveContacts();
    onContactAccepted?.call(hex);
    onStateChanged?.call();
    _log.info('NFC contact added: ${contact.displayName} (verified)');
  }

  /// Update own display name and broadcast to all contacts.
  ///
  /// Persists the new name to `identities.json` via [IdentityManager] so it
  /// survives daemon restarts. Matches the Identity record by `profileDir`
  /// (stable, unique per identity). If no matching record is found, the
  /// in-memory + broadcast path still runs so that at least contacts learn
  /// the new name in the current session.
  @override
  void updateDisplayName(String newName) {
    final mgr = IdentityManager();
    final match = mgr.loadIdentities().firstWhere(
          (i) => i.profileDir == identity.profileDir,
          orElse: () => Identity(
            id: '',
            displayName: '',
            profileDir: '',
            port: 0,
            createdAt: DateTime.now(),
          ),
        );
    if (match.id.isNotEmpty) {
      mgr.renameIdentity(match.id, newName);
    } else {
      _log.warn('updateDisplayName: no Identity record for profileDir=${identity.profileDir}; skipping persist');
    }
    displayName = newName;
    _broadcastProfileUpdate();
    onStateChanged?.call();
    _log.info('Display name updated to "$newName", broadcast sent');
  }

  /// Broadcast profile update (picture + description + name) to all accepted contacts.
  void _broadcastProfileUpdate() {
    final profileData = proto.ProfileData()
      ..updatedAtMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..displayName = displayName;
    if (_profilePictureBase64 != null) {
      profileData.profilePicture = base64Decode(_profilePictureBase64!);
    }
    if (_profileDescription != null) {
      profileData.description = _profileDescription!;
    }

    final payload = Uint8List.fromList(profileData.writeToBuffer());

    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_PROFILE_UPDATE,
        payload: payload,
      );
    }
  }

  // ── Guardian Recovery ─────────────────────────────────────────────

  @override
  bool get isGuardianSetUp => guardianService.isSetUp;

  @override
  Future<bool> setupGuardians(List<String> guardianNodeIds) async {
    if (identity.isLinkedDevice) {
      _log.warn('setupGuardians: blocked — Linked Device cannot set up guardians');
      return false;
    }
    if (guardianNodeIds.length != 5) return false;

    // Resolve contacts
    final guardians = <ContactInfo>[];
    for (final nodeIdHex in guardianNodeIds) {
      final contact = _contacts[nodeIdHex];
      if (contact == null || contact.status != 'accepted') {
        _log.error('Guardian $nodeIdHex is not an accepted contact');
        return false;
      }
      guardians.add(contact);
    }

    // Get master seed from identity
    final masterSeed = identity.masterSeed;
    if (masterSeed == null) {
      _log.error('No master seed available for guardian setup');
      return false;
    }

    return guardianService.setupGuardians(masterSeed, guardians);
  }

  @override
  Future<Map<String, dynamic>?> triggerGuardianRestore(String contactNodeIdHex) async {
    final contact = _contacts[contactNodeIdHex];
    if (contact == null) return null;

    return guardianService.triggerGuardianRestore(
      contactNodeIdHex,
      contact.displayName,
      _contacts.values.toList(),
    );
  }

  @override
  Future<bool> confirmGuardianRestore(String ownerNodeIdHex, String recoveryMailboxIdHex) async {
    return guardianService.confirmRestore(ownerNodeIdHex, recoveryMailboxIdHex);
  }

  // ── Calls (delegated to CallService) ──────────────────────────────

  @override
  CallInfo? get currentCall => _calls.currentCall;
  @override
  Future<CallInfo?> startCall(String peerNodeIdHex, {bool video = false}) =>
      _calls.startCall(peerNodeIdHex, video: video);
  @override
  Future<void> acceptCall() => _calls.acceptCall();
  @override
  Future<void> rejectCall({String reason = 'busy'}) =>
      _calls.rejectCall(reason: reason);
  @override
  Future<void> hangup() => _calls.hangup();
  @override
  bool get isMuted => _calls.isMuted;
  @override
  void toggleMute() => _calls.toggleMute();
  @override
  bool get isSpeakerEnabled => _calls.isSpeakerEnabled;
  @override
  void toggleSpeaker() => _calls.toggleSpeaker();
  @override
  bool get isVideoMuted => _calls.isVideoMuted;
  @override
  void toggleVideoMute() => _calls.toggleVideoMute();
  @override
  Future<bool> switchCamera() => _calls.switchCamera();

  @override
  void Function(GroupCallInfo info)? onIncomingGroupCall;
  @override
  void Function(GroupCallInfo info)? onGroupCallStarted;
  @override
  void Function(GroupCallInfo info)? onGroupCallEnded;

  @override
  GroupCallInfo? get currentGroupCall => _calls.currentGroupCall;
  @override
  Future<GroupCallInfo?> startGroupCall(String groupIdHex) =>
      _calls.startGroupCall(groupIdHex);
  @override
  Future<void> acceptGroupCall() => _calls.acceptGroupCall();
  @override
  Future<void> rejectGroupCall({String reason = 'busy'}) =>
      _calls.rejectGroupCall(reason: reason);
  @override
  Future<void> leaveGroupCall() => _calls.leaveGroupCall();

  // The four accessors below buffer on a plain field instead of delegating
  // straight to `_calls` because `_calls` is `late` and only assigned inside
  // startService(): main.dart's `_wireServiceCallbacks` sets these (at least
  // `createVideoEngine`) before `await service.startService()` runs, which
  // would otherwise throw LateInitializationError. The buffered value is
  // handed to `_calls` in startService (see there) once it exists.
  void Function(String senderHex, Uint8List i420, int width, int height)?
      _bufferedOnGroupVideoI420Frame;
  void Function(String senderHex, Uint8List i420, int width, int height)?
      get onGroupVideoI420Frame => _bufferedOnGroupVideoI420Frame;
  set onGroupVideoI420Frame(
      void Function(String, Uint8List, int, int)? v) {
    _bufferedOnGroupVideoI420Frame = v;
    if (_callsReady) _calls.onGroupVideoI420Frame = v;
  }

  dynamic Function(Uint8List callKey, void Function(Uint8List) onVideoFrame)?
      _bufferedCreateVideoEngine;
  dynamic Function(Uint8List callKey, void Function(Uint8List) onVideoFrame)?
      get createVideoEngine => _bufferedCreateVideoEngine;
  set createVideoEngine(
      dynamic Function(Uint8List, void Function(Uint8List))? v) {
    _bufferedCreateVideoEngine = v;
    if (_callsReady) _calls.createVideoEngine = v;
  }

  void Function(Uint8List serializedVideoFrame)?
      _bufferedOnVideoFrameReceived;
  void Function(Uint8List serializedVideoFrame)? get onVideoFrameReceived =>
      _bufferedOnVideoFrameReceived;
  set onVideoFrameReceived(void Function(Uint8List)? v) {
    _bufferedOnVideoFrameReceived = v;
    if (_callsReady) _calls.onVideoFrameReceived = v;
  }

  void Function()? _bufferedOnKeyframeRequested;
  void Function()? get onKeyframeRequested => _bufferedOnKeyframeRequested;
  set onKeyframeRequested(void Function()? v) {
    _bufferedOnKeyframeRequested = v;
    if (_callsReady) _calls.onKeyframeRequested = v;
  }

  void sendKeyframeRequest() => _calls.sendKeyframeRequest();

  // ── Network Change ─────────────────────────────────────────────────

  @override
  Future<void> onNetworkChanged({bool triggerNodeReset = true}) async {
    // The node-side reset is global (transport, NAT, DV, discovery) — running
    // it once per identity on a multi-identity daemon multiplies the work and
    // floods the log with N+1 "ignored" lines per polling tick. Daemon-style
    // callers already trigger `node.onNetworkChanged()` directly and pass
    // `false` here; single-service callers (legacy in-process path) keep the
    // default and rely on this forward.
    if (triggerNodeReset) await node.onNetworkChanged();
    // §2.2.4: Liveness-Republish bei Adress-Wechsel (debounced 5s im Publisher)
    _identityPublisher?.onAddressesChanged();
    // §4.11.10: debounced First-Contact rendezvous republish (10s) so the
    // other side resolves our new address. No-op without active sessions.
    _fcRendezvous?.onNetworkChanged();
    // §5.8: Edge-triggered one-shot outbox flush.
    // Fire-and-forget — errors are logged inside _flushOutbox; the flush does
    // not block the network-change recovery path.
    // IMPORTANT: NO timer is involved here.  The flush happens exactly once per
    // onNetworkChanged event (= a real network interface transition), NOT
    // periodically.
    unawaited(_flushOutbox());
    unawaited(_flushPendingMembershipResends());
  }

  // ── Persistence ────────────────────────────────────────────────────

  // Cached FileEncryption instance — uses seed-derived key per §3.7 step 5.
  FileEncryption? _fileEncCached;
  FileEncryption get _fileEnc {
    if (_fileEncCached != null) return _fileEncCached!;
    final baseDir = '${AppPaths.home}/.cleona';
    // §3.7: derive per-identity FileEncryption key from master seed
    final seed = identity.masterSeed;
    final idx = identity.hdIndex;
    final Uint8List? key = (seed != null && idx != null)
        ? HdWallet.deriveFileEncKey(seed, idx)
        : null;
    _fileEncCached = FileEncryption(baseDir: baseDir, key: key);
    return _fileEncCached!;
  }

  void _loadContacts() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/contacts.json');
      if (json == null) {
        final encFile = File('$profileDir/contacts.json.enc');
        if (encFile.existsSync()) {
          _log.warn('contacts.json.enc exists (${encFile.lengthSync()} bytes) '
              'but could not be decrypted — preserving file, saves '
              'refused until a clean load succeeds');
          return;
        }
        _log.info('No contacts file found (fresh profile)');
        _contactsLoaded = true;
        return;
      }
      // Load deleted contacts set
      final deleted = json['_deleted'] as List<dynamic>?;
      if (deleted != null) {
        _deletedContacts.addAll(deleted.cast<String>());
      }
      for (final entry in json.entries) {
        if (entry.key.startsWith('_')) continue; // Skip metadata keys
        _contacts[entry.key] = ContactInfo.fromJson(entry.value as Map<String, dynamic>);
      }
      _contactsLoaded = true;
      _log.info('Loaded ${_contacts.length} contacts, ${_deletedContacts.length} deleted');
    } catch (e) {
      _log.warn('Failed to load contacts: $e');
    }
  }

  void _saveContacts() {
    // Guard: don't overwrite existing contacts file with empty data
    // if loading failed (decryption error, wrong key, etc.)
    if (!_contactsLoaded && _contacts.isEmpty && _deletedContacts.isEmpty) {
      final encFile = File('$profileDir/contacts.json.enc');
      if (encFile.existsSync()) {
        _log.warn('REFUSED to save empty contacts — load failed but file exists '
            '(${encFile.lengthSync()} bytes). Would cause data loss!');
        return;
      }
    }
    try {
      final json = <String, dynamic>{};
      for (final entry in _contacts.entries) {
        json[entry.key] = entry.value.toJson();
      }
      if (_deletedContacts.isNotEmpty) {
        json['_deleted'] = _deletedContacts.toList();
      }
      _fileEnc.writeJsonFile('$profileDir/contacts.json', json);
      _syncTierRegistration();
      _updateRendezvousContacts();
    } catch (e) {
      _log.warn('Failed to save contacts: $e');
    }
  }

  // ── §5.8 Outbox persistence ─────────────────────────────────────────

  void _loadOutbox() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/outbox.json');
      if (json == null) {
        _outboxLoaded = true;
        return;
      }
      for (final entry in json.entries) {
        try {
          _outbox[entry.key] =
              _OutboxEntry.fromJson(entry.value as Map<String, dynamic>);
        } catch (e) {
          _log.debug('Outbox: skipped corrupt entry ${entry.key}: $e');
        }
      }
      _outboxLoaded = true;
      if (_outbox.isNotEmpty) {
        _log.info('Outbox: loaded ${_outbox.length} pending entries');
      }
    } catch (e) {
      _log.warn('Outbox: load failed: $e');
    }
  }

  void _saveOutbox() {
    if (!_outboxLoaded && _outbox.isEmpty) return;
    try {
      if (_outbox.isEmpty) {
        // Remove the file when the outbox is empty — no stale entry leak.
        final f = File('$profileDir/outbox.json.enc');
        if (f.existsSync()) f.deleteSync();
        return;
      }
      _fileEnc.writeJsonFile('$profileDir/outbox.json',
          {for (final e in _outbox.entries) e.key: e.value.toJson()});
    } catch (e) {
      _log.warn('Outbox: save failed: $e');
    }
  }

  void _loadMailboxTransition() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/mailbox_transition.json');
      if (json == null) return;
      final hexId = json['previousMailboxPrimary'] as String?;
      final setAtMs = json['setAtMs'] as int?;
      if (hexId != null && setAtMs != null) {
        final setAt = DateTime.fromMillisecondsSinceEpoch(setAtMs);
        if (DateTime.now().difference(setAt).inDays < _mailboxTransitionDays) {
          _previousMailboxPrimary = hexToBytes(hexId);
          _previousMailboxPrimarySetAt = setAt;
          _log.info('Mailbox transition: loaded previous primary (age: ${DateTime.now().difference(setAt)})');
        } else {
          final f = File('$profileDir/mailbox_transition.json.enc');
          if (f.existsSync()) f.deleteSync();
        }
      }
    } catch (e) {
      _log.debug('Mailbox transition: load failed: $e');
    }
  }

  void _saveMailboxTransition() {
    try {
      if (_previousMailboxPrimary == null) {
        final f = File('$profileDir/mailbox_transition.json.enc');
        if (f.existsSync()) f.deleteSync();
        return;
      }
      _fileEnc.writeJsonFile('$profileDir/mailbox_transition.json', {
        'previousMailboxPrimary': bytesToHex(_previousMailboxPrimary!),
        'setAtMs': _previousMailboxPrimarySetAt!.millisecondsSinceEpoch,
      });
    } catch (e) {
      _log.warn('Mailbox transition: save failed: $e');
    }
  }

  /// §5.8: Add a message to the one-shot outbox.
  void _addToOutbox({
    required String messageIdHex,
    required String recipientUserIdHex,
    String? recipientEd25519PkHex,
    required Uint8List canonicalPacket,
  }) {
    _outbox[messageIdHex] = _OutboxEntry(
      messageIdHex: messageIdHex,
      recipientUserIdHex: recipientUserIdHex,
      recipientEd25519PkHex: recipientEd25519PkHex,
      canonicalPacketB64: base64Encode(canonicalPacket),
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _saveOutbox();
    _log.info('Outbox: parked $messageIdHex → ${recipientUserIdHex.substring(0, 8)} '
        '(total: ${_outbox.length})');
  }

  /// §5.1 F3′ (fourth outbox edge): verified inbound from [senderUserHex]
  /// while entries for that user are parked → user-scoped flush. Gated per
  /// sender (60 s) so a still-failing flush is not re-triggered per frame;
  /// after a successful flush the entries are gone and this is a no-op.
  void _maybeFlushOutboxForSender(String senderUserHex) {
    if (!_outbox.values.any((e) => e.recipientUserIdHex == senderUserHex)) {
      return;
    }
    final last = _outboxInboundFlushAt[senderUserHex];
    if (last != null &&
        DateTime.now().difference(last) < _outboxInboundFlushGate) {
      return;
    }
    _outboxInboundFlushAt[senderUserHex] = DateTime.now();
    _log.info('Outbox: F3-edge — verified inbound from '
        '${senderUserHex.substring(0, 8)} with parked entries → flush');
    unawaited(_flushOutbox(onlyUserIdHex: senderUserHex));
  }

  /// §5.1 One-shot outbox flush (full cascade: L1→L2→L3).
  ///
  /// Called ONLY from the §5.1 edges (network-change, first-peer,
  /// contact-endpoint-confirmed, F3′ verified-inbound) — NOT from any timer.
  /// For each parked entry we first attempt direct delivery (L1
  /// identity-resolve + L2 sendToDevice — the recipient may now be online),
  /// then fall back to L3 (Erasure + S&F) on L2 failure.  On success the
  /// entry is removed and the message status is upgraded.  On continued
  /// failure (still zero peers) the entry is retained for the next edge.
  /// With [onlyUserIdHex] (F3′) the flush is scoped to that recipient.
  Future<void> _flushOutbox({String? onlyUserIdHex}) async {
    if (_outbox.isEmpty) return;
    _log.info('Outbox flush: ${_outbox.length} entries on '
        '${onlyUserIdHex == null ? "network-change edge" : "F3-edge for ${onlyUserIdHex.substring(0, 8)}"}');
    final toRemove = <String>[];
    // Snapshot: a DELIVERY_RECEIPT for a just-flushed entry mutates _outbox
    // (_handleDeliveryReceiptV3 → remove) while this loop is suspended at an
    // await — iterating the live map throws ConcurrentModificationError
    // (killed the daemon in the S122 gui-11 run: receipt for entry 1 arrived
    // before entry 2 was processed).
    for (final entry in _outbox.values.toList()) {
      if (onlyUserIdHex != null &&
          entry.recipientUserIdHex != onlyUserIdHex) {
        continue;
      }
      // Removed meanwhile (receipt arrived) → already delivered, skip.
      if (!_outbox.containsKey(entry.messageIdHex)) continue;
      // Skip entries younger than 10s — AckTracker L1 retry handles those.
      // Without this gate, every crash-safety-parked message gets re-sent
      // on the first F3-edge inbound (double-send on every message).
      final ageMs = DateTime.now().millisecondsSinceEpoch - entry.sentAtMs;
      if (ageMs < 10000) continue;
      try {
        final recipientUserId = hexToBytes(entry.recipientUserIdHex);
        final canonicalBytes = base64Decode(entry.canonicalPacketB64);

        // ── Layer 1+2: Try direct delivery first ──
        var directOk = false;
        final devices = await node.identityResolver
            .resolve(recipientUserId);
        if (devices.isNotEmpty) {
          final packet = proto.NetworkPacketV3.fromBuffer(canonicalBytes);
          for (final dev in devices) {
            final ok = await node.sendToDevice(
              packet, dev.deviceNodeId);
            if (ok) {
              directOk = true;
              break;
            }
          }
        }

        if (directOk) {
          toRemove.add(entry.messageIdHex);
          _updateMessageStatusById(
              entry.messageIdHex,
              entry.recipientUserIdHex,
              MessageStatus.delivered);
          _log.info('Outbox flush: direct delivery OK for '
              '${entry.messageIdHex.substring(0, 8)} → delivered');
          continue;
        }

        // ── Layer 3: Erasure + S&F fallback ──
        final fragmentBundleId =
            SodiumFFI().sha256(canonicalBytes).sublist(0, 16);
        final recipientEd25519Pk = entry.recipientEd25519PkHex != null
            ? hexToBytes(entry.recipientEd25519PkHex!)
            : null;

        final erasureOk = await _distributeErasureFragments(
          packetBytes: canonicalBytes,
          messageId: Uint8List.fromList(fragmentBundleId),
          recipientUserEd25519Pk: recipientEd25519Pk,
          recipientUserNodeId: recipientUserId,
        );
        final safOk = await _storeSafOnContactPeers(
          recipientUserId: recipientUserId,
          wrappedEnvelope: canonicalBytes,
        );

        if (erasureOk || safOk) {
          toRemove.add(entry.messageIdHex);
          _updateMessageStatusById(
              entry.messageIdHex,
              entry.recipientUserIdHex,
              MessageStatus.queuedOffline);
          _log.info('Outbox flush: placed ${entry.messageIdHex.substring(0, 8)}'
              ' (erasure=$erasureOk, saf=$safOk) → queuedOffline');
        } else {
          _log.debug('Outbox flush: still no peers for '
              '${entry.messageIdHex.substring(0, 8)} — retaining');
        }
      } catch (e) {
        _log.warn('Outbox flush: error on ${entry.messageIdHex}: $e');
      }
    }
    for (final id in toRemove) {
      _outbox.remove(id);
    }
    if (toRemove.isNotEmpty) {
      _saveOutbox();
      // F3′ gate cleanup: drop per-sender timestamps for users that no
      // longer have parked entries (keeps the gate map bounded).
      _outboxInboundFlushAt.removeWhere((user, _) =>
          !_outbox.values.any((e) => e.recipientUserIdHex == user));
    }
  }

  // ── §5.8 extension: pending membership update resends ────────────

  void _loadPendingMembershipResends() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/membership_resend.json');
      if (json == null) return;
      for (final entry in json.entries) {
        final list = entry.value as List<dynamic>;
        _pendingMembershipResends[entry.key] =
            list.map((e) => e as String).toSet();
      }
      if (_pendingMembershipResends.isNotEmpty) {
        _log.info('Membership resend: loaded ${_pendingMembershipResends.length} entities');
      }
    } catch (e) {
      _log.warn('Membership resend: load failed: $e');
    }
  }

  void _savePendingMembershipResends() {
    try {
      if (_pendingMembershipResends.isEmpty) {
        final f = File('$profileDir/membership_resend.json.enc');
        if (f.existsSync()) f.deleteSync();
        return;
      }
      _fileEnc.writeJsonFile('$profileDir/membership_resend.json', {
        for (final e in _pendingMembershipResends.entries)
          e.key: e.value.toList()
      });
    } catch (e) {
      _log.warn('Membership resend: save failed: $e');
    }
  }

  Future<void> _flushPendingMembershipResends() async {
    if (_pendingMembershipResends.isEmpty) return;
    _log.info('Membership resend flush: ${_pendingMembershipResends.length} entities');
    final toRemoveEntities = <String>[];
    for (final entry in _pendingMembershipResends.entries.toList()) {
      final entityId = entry.key;
      final recipients = entry.value;
      final group = _groups[entityId];
      final channel = _channels[entityId];
      if (group == null && channel == null) {
        toRemoveEntities.add(entityId);
        continue;
      }
      final succeeded = <String>{};
      final stale = <String>{};
      final Uint8List inviteBytes;
      final proto.MessageTypeV3 msgType;
      final bool Function(String) isMember;
      final Uint8List? Function(String) memberX25519;
      final Uint8List? Function(String) memberMlKem;
      if (group != null) {
        inviteBytes = _buildSignedGroupInviteBytes(group);
        msgType = proto.MessageTypeV3.MTV3_GROUP_INVITE;
        isMember = group.members.containsKey;
        memberX25519 = (h) => group.members[h]?.x25519Pk;
        memberMlKem = (h) => group.members[h]?.mlKemPk;
      } else {
        inviteBytes = _buildSignedChannelInviteBytes(channel!);
        msgType = proto.MessageTypeV3.MTV3_CHANNEL_INVITE;
        isMember = channel.members.containsKey;
        memberX25519 = (h) => channel.members[h]?.x25519Pk;
        memberMlKem = (h) => channel.members[h]?.mlKemPk;
      }
      final entityIdBytes = hexToBytes(entityId);
      for (final recipientHex in recipients) {
        if (!isMember(recipientHex)) {
          stale.add(recipientHex);
          continue;
        }
        final (x25519Pk, mlKemPk) = _resolveMemberKeys(recipientHex,
            memberX25519Pk: memberX25519(recipientHex),
            memberMlKemPk: memberMlKem(recipientHex));
        if (x25519Pk == null || mlKemPk == null) continue;
        try {
          final ok = await sendToUser(
            recipientUserId: hexToBytes(recipientHex),
            messageType: msgType,
            payload: inviteBytes,
            groupId: entityIdBytes,
          );
          if (ok) {
            succeeded.add(recipientHex);
            _log.info('Membership resend: sent to ${recipientHex.substring(0, 8)}');
          }
        } catch (e) {
          _log.warn('Membership resend: error for ${recipientHex.substring(0, 8)}: $e');
        }
      }
      recipients.removeAll(succeeded);
      recipients.removeAll(stale);
      if (recipients.isEmpty) toRemoveEntities.add(entityId);
    }
    for (final id in toRemoveEntities) {
      _pendingMembershipResends.remove(id);
    }
    if (toRemoveEntities.isNotEmpty || _pendingMembershipResends.isEmpty) {
      _savePendingMembershipResends();
    }
  }

  /// §5.8: Update a message status by its wire message-ID hex.
  ///
  /// Scans all conversations — this is acceptable because outbox entries are
  /// rare and the status update is triggered only by onNetworkChanged (not
  /// per-message). Fires onStateChanged when a match is found.
  void _updateMessageStatusById(
      String messageIdHex, String recipientHex, MessageStatus newStatus) {
    // Search own conversations first — recipient hex may be a userId or deviceId
    for (final conv in conversations.values) {
      for (final msg in conv.messages) {
        if (msg.id == messageIdHex && msg.isOutgoing) {
          if (msg.status == newStatus) return; // already correct
          msg.status = newStatus;
          _log.debug('Status update: $messageIdHex → $newStatus');
          onStateChanged?.call();
          _saveConversations();
          return;
        }
      }
    }
  }

  /// §5.8: Check all queuedOffline messages in a conversation for TTL expiry.
  ///
  /// Called lazily at conversation-open time (chat screen load).
  /// Zero network traffic — purely local timestamp comparison.
  ///
  /// The 7-day TTL matches the S&F / Reed-Solomon fragment lifetime
  /// (Architecture §5.4, §5.5).
  static const int _offlineTtlMs = 7 * 24 * 60 * 60 * 1000; // 7 days

  bool _checkAndMarkExpired(String conversationId) {
    final conv = conversations[conversationId];
    if (conv == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final msg in conv.messages) {
      if (msg.status == MessageStatus.queuedOffline && msg.isOutgoing) {
        final age = now - msg.timestamp.millisecondsSinceEpoch;
        if (age > _offlineTtlMs) {
          msg.status = MessageStatus.expired;
          changed = true;
        }
      }
    }
    if (changed) {
      _saveConversations();
      onStateChanged?.call();
    }
    return changed;
  }

  /// Sync contact + channel member IDs to the DV routing table's tier registry.
  /// Called after loading contacts/channels and after any membership change.
  /// §3.1: registers deviceIds (not userIds) — routing operates on devices.
  void _syncTierRegistration() {
    final dv = node.dvRouting;
    final contactDeviceIds = <String>{};
    for (final entry in _contacts.entries) {
      if (entry.value.status == 'accepted') {
        contactDeviceIds.addAll(entry.value.deviceNodeIds);
      }
    }
    dv.replaceContactIds(contactDeviceIds);

    final channelDeviceIds = <String>{};
    for (final channel in _channels.values) {
      for (final memberHex in channel.members.keys) {
        final contact = _contacts[memberHex];
        if (contact != null) {
          channelDeviceIds.addAll(contact.deviceNodeIds);
        }
      }
    }
    dv.replaceChannelMemberIds(channelDeviceIds);
  }

  void _loadConversations() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/conversations.json');
      if (json == null) {
        final encFile = File('$profileDir/conversations.json.enc');
        if (encFile.existsSync()) {
          // The file is present but could not be decrypted (transient FFI/key
          // hiccup, partial write the sidecar-recovery didn't catch, etc.).
          // Do NOT mark _conversationsLoaded — leaving it false makes
          // _saveConversations REFUSE to overwrite, so the on-disk data is
          // preserved for the next start instead of being clobbered with an
          // empty set. (Closes the second data-loss vector alongside the
          // seed-before-load fix.)
          _log.warn('conversations.json.enc exists (${encFile.lengthSync()} '
              'bytes) but could not be decrypted — preserving file, saves '
              'refused until a clean load succeeds');
          return;
        }
        // Genuine first run: no file yet → loading is "done" (empty is correct).
        _conversationsLoaded = true;
        return;
      }
      for (final entry in json.entries) {
        final convData = entry.value as Map<String, dynamic>;
        final msgs = (convData['messages'] as List<dynamic>?)?.map((m) {
          final mm = m as Map<String, dynamic>;
          // Use UiMessage.fromJson for complete deserialization (media, transcripts, reactions, etc.)
          return UiMessage.fromJson(mm);
        }).toList() ?? [];

        conversations[entry.key] = Conversation(
          id: entry.key,
          displayName: convData['displayName'] as String? ?? entry.key.substring(0, 8),
          messages: msgs,
          lastActivity: DateTime.fromMillisecondsSinceEpoch(convData['lastActivity'] as int? ?? 0),
          isGroup: convData['isGroup'] as bool? ?? false,
          isChannel: convData['isChannel'] as bool? ?? false,
          profilePictureBase64: convData['profilePicture'] as String?,
          isFavorite: convData['isFavorite'] as bool? ?? false,
          unreadCount: convData['unreadCount'] as int? ?? 0,
        );
      }
      _conversationsLoaded = true;
      _log.info('Loaded ${conversations.length} conversations');
    } catch (e) {
      _log.warn('Failed to load conversations: $e');
    }
  }

  void _recoverStuckMedia() {
    var resetCount = 0;
    for (final conv in conversations.values) {
      for (final msg in conv.messages) {
        if (msg.mediaState == MediaDownloadState.downloading) {
          msg.mediaState = MediaDownloadState.announced;
          msg.filePath = null;
          resetCount++;
        } else if (msg.mediaState == MediaDownloadState.completed &&
            msg.filePath != null &&
            !File(msg.filePath!).existsSync()) {
          msg.mediaState = MediaDownloadState.announced;
          msg.filePath = null;
          resetCount++;
        }
      }
    }
    if (resetCount > 0) {
      _log.info('Media recovery: reset $resetCount stuck downloads to announced');
      _saveConversations();
    }
  }

  void _loadPendingMediaSends() {
    final path = '$profileDir/pending_media_sends.json';
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final entry in json.entries) {
        final filePath = entry.value as String;
        if (File(filePath).existsSync()) {
          _pendingMediaSends[entry.key] = filePath;
        }
      }
      if (_pendingMediaSends.isNotEmpty) {
        _log.info('Loaded ${_pendingMediaSends.length} pending media sends');
      }
    } catch (e) {
      _log.warn('Failed to load pending media sends: $e');
    }
  }

  String? _recoverPendingMediaPath(String messageId) {
    for (final conv in conversations.values) {
      for (final msg in conv.messages) {
        if (msg.id == messageId && msg.filePath != null && File(msg.filePath!).existsSync()) {
          return msg.filePath;
        }
      }
    }
    return null;
  }

  void _savePendingMediaSends() {
    final path = '$profileDir/pending_media_sends.json';
    try {
      if (_pendingMediaSends.isEmpty) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
        return;
      }
      File(path).writeAsStringSync(jsonEncode(_pendingMediaSends));
    } catch (e) {
      _log.warn('Failed to save pending media sends: $e');
    }
  }

  /// Post an Android system notification for an incoming message.
  void _postAndroidNotification(String senderName, String text, String conversationId) {
    if (onPostNotificationAndroid == null) return;
    if (_isAppResumed) return;
    onPostNotificationAndroid!(senderName, text, conversationId);
  }

  /// Feed `CalendarManager.syncBirthdaysFromContacts()` from the local
  /// contact book. Produces yearly all-day events for every contact with
  /// birthdayMonth + birthdayDay set. Idempotent — existing birthday events
  /// are updated in place keyed by contactId. §23.4.
  void _syncCalendarBirthdays() {
    final map = <String, Map<String, dynamic>>{};
    for (final entry in _contacts.entries) {
      final c = entry.value;
      if (c.status != 'accepted') continue;
      if (c.birthdayMonth == null || c.birthdayDay == null) continue;
      map[entry.key] = {
        'displayName': c.effectiveName,
        'birthdayMonth': c.birthdayMonth,
        'birthdayDay': c.birthdayDay,
        'birthdayYear': c.birthdayYear,
      };
    }
    if (map.isEmpty) return;
    try {
      calendarManager.syncBirthdaysFromContacts(map);
      _log.info('Birthday calendar sync: ${map.length} contact birthday(s)');
    } catch (e) {
      _log.warn('Birthday calendar sync failed: $e');
    }
  }

  /// Set or clear the birthday metadata on a contact. Triggers an immediate
  /// re-sync of the calendar birthday events.
  @override
  bool setContactBirthday(String nodeIdHex,
      {int? month, int? day, int? year}) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return false;
    contact.birthdayMonth = month;
    contact.birthdayDay = day;
    contact.birthdayYear = year;
    _saveContacts();
    _syncCalendarBirthdays();
    return true;
  }

  /// Recalculate total unread count and notify badge listeners.
  void _updateBadgeCount() {
    if (onBadgeCountChanged == null) return;
    final total = conversations.values.fold<int>(0, (sum, c) => sum + c.unreadCount);
    onBadgeCountChanged!(total);
  }

  /// Save all persistent state (conversations, contacts, groups, channels).
  /// Called by the app lifecycle observer when going to background on Android.
  void saveState() {
    _saveConversations();
    _saveContacts();
    _saveGroups();
    _saveChannels();
  }

  void _saveProcessedMessageIds() {
    if (_processedMessageIds.isEmpty) return;
    try {
      _fileEnc.writeJsonFile('$profileDir/processed_msg_ids.json', {
        'ids': _processedMessageIds.toList(),
      });
    } catch (e) {
      _log.warn('Failed to save processed message IDs: $e');
    }
  }

  void _loadProcessedMessageIds() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/processed_msg_ids.json');
      if (json == null) return;
      final ids = json['ids'] as List<dynamic>?;
      if (ids == null) return;
      for (final id in ids) {
        _processedMessageIds.add(id as String);
      }
      while (_processedMessageIds.length > _processedMessageIdsCap) {
        _processedMessageIds.remove(_processedMessageIds.first);
      }
      _log.info('Loaded ${_processedMessageIds.length} processed message IDs '
          '(replay protection)');
    } catch (e) {
      _log.warn('Failed to load processed message IDs: $e');
    }
  }

  Timer? _saveConversationsTimer;
  bool _saveConversationsPending = false;

  void _saveConversations() {
    _saveConversationsPending = true;
    _saveConversationsTimer ??= Timer(const Duration(seconds: 2), () {
      _saveConversationsTimer = null;
      if (_saveConversationsPending) {
        _saveConversationsPending = false;
        _saveConversationsNow();
      }
    });
  }

  void _saveConversationsNow() {
    // Safety net: never overwrite an existing conversations file before the
    // load has completed. Before _conversationsLoaded, `conversations` can only
    // ever be a partial/seeded set (e.g. the §9.5 system channels), so
    // persisting it would clobber the real chats still on disk. This is the
    // data-loss root cause (seed-before-load); the ordering is also fixed in
    // start(), and this guard makes any future pre-load save harmless too.
    // NOTE: the guard deliberately does NOT also require `conversations.isEmpty`
    // — the original bug was a pre-load save with a NON-empty (seeded) map.
    if (!_conversationsLoaded) {
      final encFile = File('$profileDir/conversations.json.enc');
      if (encFile.existsSync()) {
        _log.warn('REFUSED to save conversations before load completed — '
            'on-disk file exists (prevents pre-load overwrite)');
        return;
      }
    }
    try {
      final json = <String, dynamic>{};
      for (final entry in conversations.entries) {
        json[entry.key] = {
          'displayName': entry.value.displayName,
          'lastActivity': entry.value.lastActivity.millisecondsSinceEpoch,
          if (entry.value.isGroup) 'isGroup': true,
          if (entry.value.isChannel) 'isChannel': true,
          if (entry.value.isFavorite) 'isFavorite': true,
          if (entry.value.profilePictureBase64 != null) 'profilePicture': entry.value.profilePictureBase64,
          if (entry.value.unreadCount > 0) 'unreadCount': entry.value.unreadCount,
          'messages': entry.value.messages.map((m) => m.toJson()).toList(),
        };
      }
      _fileEnc.writeJsonFile('$profileDir/conversations.json', json);
    } catch (e) {
      _log.warn('Failed to save conversations: $e');
    }
  }

  // ── Group Persistence ─────────────────────────────────────────

  void _loadGroups() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/groups.json');
      if (json == null) {
        final encFile = File('$profileDir/groups.json.enc');
        if (encFile.existsSync()) {
          _log.warn('groups.json.enc exists (${encFile.lengthSync()} bytes) '
              'but could not be decrypted — preserving file, saves '
              'refused until a clean load succeeds');
          return;
        }
        _groupsLoaded = true;
        return;
      }
      for (final entry in json.entries) {
        _groups[entry.key] = GroupInfo.fromJson(entry.value as Map<String, dynamic>);
      }
      _groupsLoaded = true;
      _log.info('Loaded ${_groups.length} groups');
    } catch (e) {
      _log.warn('Failed to load groups: $e');
    }
  }

  void _saveGroups() {
    if (!_groupsLoaded && _groups.isEmpty) {
      final encFile = File('$profileDir/groups.json.enc');
      if (encFile.existsSync()) {
        _log.warn('REFUSED to save empty groups — load failed but file exists');
        return;
      }
    }
    try {
      final json = <String, dynamic>{};
      for (final entry in _groups.entries) {
        json[entry.key] = entry.value.toJson();
      }
      _fileEnc.writeJsonFile('$profileDir/groups.json', json);
    } catch (e) {
      _log.warn('Failed to save groups: $e');
    }
  }

  // ── Channel Persistence ──────────────────────────────────────

  void _loadChannels() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/channels.json');
      if (json == null) {
        final encFile = File('$profileDir/channels.json.enc');
        if (encFile.existsSync()) {
          _log.warn('channels.json.enc exists (${encFile.lengthSync()} bytes) '
              'but could not be decrypted — preserving file, saves '
              'refused until a clean load succeeds');
          return;
        }
        _channelsLoaded = true;
        return;
      }
      for (final entry in json.entries) {
        _channels[entry.key] = ChannelInfo.fromJson(entry.value as Map<String, dynamic>);
      }
      _channelsLoaded = true;
      _log.info('Loaded ${_channels.length} channels');
    } catch (e) {
      _log.warn('Failed to load channels: $e');
    }
  }

  void _saveChannels() {
    if (!_channelsLoaded && _channels.isEmpty) {
      final encFile = File('$profileDir/channels.json.enc');
      if (encFile.existsSync()) {
        _log.warn('REFUSED to save empty channels — load failed but file exists');
        return;
      }
    }
    try {
      final json = <String, dynamic>{};
      for (final entry in _channels.entries) {
        json[entry.key] = entry.value.toJson();
      }
      _fileEnc.writeJsonFile('$profileDir/channels.json', json);
      _syncTierRegistration();
    } catch (e) {
      _log.warn('Failed to save channels: $e');
    }
  }

  // ── System Channels (§9.5) ────────────────────────────────────────

  void _seedSystemChannels() {
    bool changed = false;

    for (final entry in [
      (SystemChannels.bugLogChannelIdHex, 'Cleona Bug Log'),
      (SystemChannels.featureReqChannelIdHex, 'Feature Requests'),
    ]) {
      final (idHex, name) = entry;
      if (!_channels.containsKey(idHex)) {
        _channels[idHex] = ChannelInfo(
          channelIdHex: idHex,
          name: name,
          ownerNodeIdHex: SystemChannels.zeroOwnerHex,
          isPublic: true,
          isAdult: false,
          language: 'multi',
        );
        changed = true;
        _log.info('Seeded system channel: $name');
      }
      if (!conversations.containsKey(idHex)) {
        conversations[idHex] = Conversation(
          id: idHex,
          displayName: name,
          isChannel: true,
        );
        changed = true;
      }
    }

    if (changed) {
      _saveChannels();
      _saveConversations();
    }
  }

  void _evictSystemChannels() {
    _evictChannel(
      SystemChannels.bugLogChannelIdHex,
      SystemChannels.maxChannelStorageBytes,
      oldestFirst: true,
    );
    _evictChannel(
      SystemChannels.featureReqChannelIdHex,
      SystemChannels.maxChannelStorageBytes,
      oldestFirst: false,
    );
    // §9.5.7: keep the gossip record store under the same 25 MB cap
    // (strategies match §9.5.5: bug log oldest-first, FR fewest-net-votes).
    var evicted = 0;
    evicted += _sysChanStore.evictToLimit(SystemChannels.bugLogChannelIdHex);
    evicted +=
        _sysChanStore.evictToLimit(SystemChannels.featureReqChannelIdHex);
    if (evicted > 0) _saveSysChanRecords();
  }

  void _evictChannel(String channelIdHex, int maxBytes,
      {required bool oldestFirst}) {
    final conv = conversations[channelIdHex];
    if (conv == null || conv.messages.isEmpty) return;

    int totalBytes = 0;
    for (final msg in conv.messages) {
      totalBytes += msg.text.length;
    }
    if (totalBytes <= maxBytes) return;

    final sorted = List<UiMessage>.from(conv.messages);
    if (oldestFirst) {
      sorted.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } else {
      // Feature requests: fewest-votes first, then oldest
      sorted.sort((a, b) {
        final aVotes = _featureVoteScore(a);
        final bVotes = _featureVoteScore(b);
        if (aVotes != bVotes) return aVotes.compareTo(bVotes);
        return a.timestamp.compareTo(b.timestamp);
      });
    }

    int removed = 0;
    while (totalBytes > maxBytes && sorted.isNotEmpty) {
      final victim = sorted.removeAt(0);
      totalBytes -= victim.text.length;
      conv.messages.remove(victim);
      removed++;
    }
    if (removed > 0) {
      _saveConversations();
      _log.info('Evicted $removed messages from $channelIdHex (${totalBytes ~/ 1024}KB remaining)');
    }
  }

  int _featureVoteScore(UiMessage msg) {
    try {
      final json = jsonDecode(msg.text);
      if (json is Map && json['pollId'] != null) {
        final poll = pollManager.polls[json['pollId']];
        if (poll != null) {
          int yes = 0, no = 0;
          for (final v in poll.votes.values) {
            if (v.selectedOptions.contains(0)) yes++;
            if (v.selectedOptions.contains(1)) no++;
          }
          return yes - no;
        }
      }
    } catch (_) {}
    return 0;
  }

  // ── §9.5.7 System-Channel Records & Gossip (S119 D1/D2/D3) ─────────

  /// Local record set for the ownerless system channels. Gossip-converged
  /// (SYSCHAN_DIGEST/SUMMARY/WANT/PUSH, BOOT-path InfrastructureFrames).
  late final SystemChannelRecordStore _sysChanStore =
      SystemChannelRecordStore(profileDir: profileDir);
  Timer? _sysChanSaveDebounce;
  bool _sysChanLoaded = false;

  /// §9.5.7 push budget: eager-flood TTL for freshly created/learned records.
  static const int _sysChanPushTtl = 5;

  /// k adaptive: eager pushes and anti-entropy digests go to at most this
  /// many random peers per event.
  static const int _sysChanFanout = 3;

  /// SUMMARY cap: beyond this the newest fingerprints win; the tail
  /// converges over subsequent hourly rounds (bounded message size).
  static const int _sysChanSummaryCap = 4000;

  /// PUSH batching: keep each SysChanPush under this many payload bytes so
  /// the app-level UDP fragmenter (§2.4) never sees an oversized frame.
  static const int _sysChanPushBatchBytes = 100 * 1024;

  void _loadSysChanRecords() {
    if (_sysChanLoaded) return;
    _sysChanLoaded = true;
    try {
      final json = _fileEnc.readJsonFile('$profileDir/syschan_records.json');
      if (json != null) {
        _sysChanStore.loadFromJson(json);
        // Re-bridge stored POSTs into the conversation (idempotent) so the
        // UI list survives a conversations/records divergence.
        for (final chHex in [
          SystemChannels.bugLogChannelIdHex,
          SystemChannels.featureReqChannelIdHex,
        ]) {
          for (final r in _sysChanStore.allRecords(chHex)) {
            if (r.record.kind == SysChanKind.post) _bridgeSysChanPost(r);
          }
        }
      }
    } catch (e) {
      _log.warn('syschan: load failed: $e');
    }
  }

  void _saveSysChanRecords() {
    _sysChanSaveDebounce?.cancel();
    _sysChanSaveDebounce = Timer(const Duration(seconds: 2), () {
      try {
        _fileEnc.writeJsonFile(
            '$profileDir/syschan_records.json', _sysChanStore.toJson());
      } catch (e) {
        _log.warn('syschan: save failed: $e');
      }
    });
  }

  /// Create, sign, store, UI-bridge and eager-push a system-channel record.
  /// Returns null when the store's own admission rejected it (e.g. foreign
  /// retract target).
  Future<StoredSysChanRecord?> _publishSystemChannelRecord({
    required String channelIdHex,
    required int kind,
    String text = '',
    Uint8List? targetRecordId,
    int voteOption = 0,
  }) async {
    if (!SystemChannels.isSystemChannel(channelIdHex)) return null;
    final record = SystemChannelRecordStore.buildSigned(
      channelId: Uint8List.fromList(hexToBytes(channelIdHex)),
      kind: kind,
      // Founding binding (§9.5.7): computeUserId(inline pk) == userId. On
      // linked devices the delegated sub-key would break the binding —
      // records are signed with the identity's user keys.
      authorUserId: identity.userId,
      ed25519Pk: identity.ed25519PublicKey,
      ed25519Sk: identity.ed25519SecretKey,
      mlDsaPk: identity.mlDsaPublicKey,
      mlDsaSk: identity.mlDsaSecretKey,
      text: text,
      targetRecordId: targetRecordId,
      voteOption: voteOption,
    );
    final bytes = record.writeToBuffer();
    final admission = _sysChanStore.tryAdmit(bytes, parsed: record);
    if (admission == SysChanAdmission.rejected) return null;
    final stored = StoredSysChanRecord(
        record: record,
        bytes: bytes,
        fingerprintHex: SystemChannelRecordStore.fingerprintHexOf(bytes));

    switch (kind) {
      case SysChanKind.post:
        _bridgeSysChanPost(stored);
      case SysChanKind.retract:
        _applySysChanRetract(
            channelIdHex, bytesToHex(Uint8List.fromList(record.targetRecordId)));
    }
    _saveSysChanRecords();
    _sysChanEagerPush(channelIdHex, [stored], ttl: _sysChanPushTtl);
    onStateChanged?.call();
    return stored;
  }

  /// Materializes an admitted POST record as a conversation message so the
  /// existing channel UI (SystemChannelPost cards, eviction, dedup scans)
  /// keeps working. Idempotent per record id.
  UiMessage? _bridgeSysChanPost(StoredSysChanRecord stored) {
    final channelIdHex = bytesToHex(Uint8List.fromList(stored.record.channelId));
    final conv = conversations[channelIdHex];
    if (conv == null) return null;
    final recordIdHex = bytesToHex(Uint8List.fromList(stored.record.recordId));
    for (final m in conv.messages) {
      if (m.id == recordIdHex) return m;
    }
    final authorHex = bytesToHex(Uint8List.fromList(stored.record.authorUserId));
    final isOwn = authorHex == identity.userIdHex;
    final msg = UiMessage(
      id: recordIdHex,
      conversationId: channelIdHex,
      senderNodeIdHex: authorHex,
      text: stored.record.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          stored.record.timestampMs.toInt()),
      type: UiMessageType.channelPost,
      status: isOwn ? MessageStatus.sent : MessageStatus.delivered,
      isOutgoing: isOwn,
    );
    _addMessageToConversation(channelIdHex, msg, isChannel: true);
    return msg;
  }

  /// D2: marks the bridged conversation message of a retracted record as
  /// deleted (tombstone effect in the UI).
  void _applySysChanRetract(String channelIdHex, String targetRecordIdHex) {
    final conv = conversations[channelIdHex];
    if (conv == null) return;
    for (final m in conv.messages) {
      if (m.id == targetRecordIdHex && !m.isDeleted) {
        m.text = '';
        m.isDeleted = true;
        _saveConversations();
        break;
      }
    }
  }

  void _sysChanPushTo(Uint8List recipientDeviceId, String channelIdHex,
      List<StoredSysChanRecord> records, {required int ttl}) {
    if (records.isEmpty) return;
    var batch = proto.SysChanPush()
      ..channelId = hexToBytes(channelIdHex)
      ..ttl = ttl;
    var batchBytes = 0;
    void flush() {
      if (batch.records.isEmpty) return;
      unawaited(node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_SYSCHAN_PUSH,
        innerPayload: Uint8List.fromList(batch.writeToBuffer()),
        recipientDeviceId: recipientDeviceId,
      ));
      batch = proto.SysChanPush()
        ..channelId = hexToBytes(channelIdHex)
        ..ttl = ttl;
      batchBytes = 0;
    }

    for (final r in records) {
      if (batchBytes + r.bytes.length > _sysChanPushBatchBytes &&
          batch.records.isNotEmpty) {
        flush();
      }
      batch.records.add(r.bytes);
      batchBytes += r.bytes.length;
    }
    flush();
  }

  /// Eager new-record flood (§9.5.7 push budget): k random peers, TTL
  /// decremented per hop, fingerprint dedup at every receiver.
  void _sysChanEagerPush(
      String channelIdHex, List<StoredSysChanRecord> records,
      {required int ttl, String? excludeDeviceHex}) {
    if (records.isEmpty || ttl <= 0) return;
    final peers = List<PeerInfo>.from(node.routingTable.allPeers)
      ..removeWhere((p) =>
          p.nodeIdHex == excludeDeviceHex ||
          p.nodeIdHex == identity.nodeIdHex)
      ..shuffle();
    for (final peer in peers.take(_sysChanFanout)) {
      _sysChanPushTo(Uint8List.fromList(peer.nodeId), channelIdHex, records,
          ttl: ttl);
    }
  }

  /// Hourly anti-entropy digest (piggy-backed on the channel-index gossip
  /// slot) + edge-triggered initial sync after discovery-complete.
  void sendSysChanDigests(Iterable<PeerInfo> targets) {
    final targetList = targets.toList();
    if (targetList.isEmpty) return;
    for (final chHex in [
      SystemChannels.bugLogChannelIdHex,
      SystemChannels.featureReqChannelIdHex,
    ]) {
      final digest = proto.SysChanDigest()
        ..channelId = hexToBytes(chHex)
        ..recordCount = _sysChanStore.recordCount(chHex)
        ..setHash = _sysChanStore.setHash(chHex);
      final payload = Uint8List.fromList(digest.writeToBuffer());
      for (final peer in targetList) {
        unawaited(node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_SYSCHAN_DIGEST,
          innerPayload: payload,
          recipientDeviceId: Uint8List.fromList(peer.nodeId),
        ));
      }
    }
  }

  /// DIGEST: peer advertises its record set. On mismatch, reply with our
  /// fingerprint SUMMARY so the peer can WANT/PUSH the difference.
  void handleIncomingSysChanDigestInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final digest = proto.SysChanDigest.fromBuffer(frame.payload);
      final chHex = bytesToHex(Uint8List.fromList(digest.channelId));
      if (!SystemChannels.isSystemChannel(chHex)) return;
      final localHash = bytesToHex(_sysChanStore.setHash(chHex));
      final remoteHash =
          bytesToHex(Uint8List.fromList(digest.setHash));
      if (localHash == remoteHash) return; // converged
      final summary = proto.SysChanSummary()..channelId = digest.channelId;
      final fps = _sysChanStore.storedFingerprints(chHex);
      for (final fp in fps.take(_sysChanSummaryCap)) {
        summary.fingerprints.add(hexToBytes(fp));
      }
      unawaited(node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_SYSCHAN_SUMMARY,
        innerPayload: Uint8List.fromList(summary.writeToBuffer()),
        recipientDeviceId: senderDeviceId,
      ));
    } catch (e) {
      _log.debug('syschan: digest handling failed: $e');
    }
  }

  /// SUMMARY: peer's fingerprint set. WANT what we lack, PUSH what it
  /// lacks (ttl 0 — anti-entropy transfers do not re-flood).
  void handleIncomingSysChanSummaryInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final summary = proto.SysChanSummary.fromBuffer(frame.payload);
      final chHex = bytesToHex(Uint8List.fromList(summary.channelId));
      if (!SystemChannels.isSystemChannel(chHex)) return;
      final theirs = summary.fingerprints
          .map((f) => Uint8List.fromList(f))
          .toList();

      final missing = _sysChanStore.missingFingerprints(chHex, theirs);
      if (missing.isNotEmpty) {
        final want = proto.SysChanWant()..channelId = summary.channelId;
        want.fingerprints.addAll(missing);
        unawaited(node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_SYSCHAN_WANT,
          innerPayload: Uint8List.fromList(want.writeToBuffer()),
          recipientDeviceId: senderDeviceId,
        ));
      }

      final extra = _sysChanStore.extraRecords(chHex, theirs);
      if (extra.isNotEmpty) {
        _sysChanPushTo(senderDeviceId, chHex, extra, ttl: 0);
      }
    } catch (e) {
      _log.debug('syschan: summary handling failed: $e');
    }
  }

  void handleIncomingSysChanWantInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final want = proto.SysChanWant.fromBuffer(frame.payload);
      final chHex = bytesToHex(Uint8List.fromList(want.channelId));
      if (!SystemChannels.isSystemChannel(chHex)) return;
      final records = _sysChanStore.recordsForFingerprints(
          chHex, want.fingerprints.map((f) => Uint8List.fromList(f)).toList());
      if (records.isNotEmpty) {
        _sysChanPushTo(senderDeviceId, chHex, records, ttl: 0);
      }
    } catch (e) {
      _log.debug('syschan: want handling failed: $e');
    }
  }

  /// PUSH: admit each record (§8.2 context-proof happens inside tryAdmit:
  /// hybrid self-signature + founding binding + known channel_id), bridge
  /// UI effects, forward fresh records while TTL remains.
  void handleIncomingSysChanPushInfra(
      proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId) {
    try {
      final push = proto.SysChanPush.fromBuffer(frame.payload);
      final chHex = bytesToHex(Uint8List.fromList(push.channelId));
      if (!SystemChannels.isSystemChannel(chHex)) return;

      final fresh = <StoredSysChanRecord>[];
      var votesChanged = false;
      for (final blob in push.records.take(500)) {
        final bytes = Uint8List.fromList(blob);
        if (bytes.length > SystemChannels.maxManualPostBytes) continue;
        proto.SystemChannelRecord record;
        try {
          record = proto.SystemChannelRecord.fromBuffer(bytes);
        } catch (_) {
          continue;
        }
        final admission = _sysChanStore.tryAdmit(bytes, parsed: record);
        if (admission == SysChanAdmission.duplicate ||
            admission == SysChanAdmission.rejected) {
          continue;
        }
        final stored = StoredSysChanRecord(
            record: record,
            bytes: bytes,
            fingerprintHex: SystemChannelRecordStore.fingerprintHexOf(bytes));
        fresh.add(stored);
        switch (admission) {
          case SysChanAdmission.postAdmitted:
            _bridgeSysChanPost(stored);
          case SysChanAdmission.retractAdmitted:
            _applySysChanRetract(chHex,
                bytesToHex(Uint8List.fromList(record.targetRecordId)));
          case SysChanAdmission.voteAdmitted:
            votesChanged = true;
          default:
            break;
        }
      }

      if (fresh.isEmpty) return;
      _sysChanStore.evictToLimit(chHex);
      _saveSysChanRecords();
      if (votesChanged) onStateChanged?.call();
      final ttl = push.ttl;
      if (ttl > 1) {
        _sysChanEagerPush(chHex, fresh,
            ttl: ttl - 1, excludeDeviceHex: bytesToHex(senderDeviceId));
      }
    } catch (e) {
      _log.debug('syschan: push handling failed: $e');
    }
  }

  /// D3 (§9.5.3): programmatic Feature-Request submission. Posts a
  /// SystemChannelRecord with an embedded auto-poll (the FR JSON) and the
  /// submitter's implicit "Ja" vote (Auto-Ja embedded).
  @override
  Future<UiMessage?> submitFeatureRequest(String title, String body) async {
    if (_reducedMode) {
      _log.warn('submitFeatureRequest blocked: reducedMode active');
      return null;
    }
    if (title.trim().isEmpty) return null;
    final text = jsonEncode({
      'type': 'feature_request',
      'title': title.trim(),
      'body': body.trim(),
    });
    final stored = await _publishSystemChannelRecord(
      channelIdHex: SystemChannels.featureReqChannelIdHex,
      kind: SysChanKind.post,
      text: text,
    );
    if (stored == null) return null;
    final recordIdHex = bytesToHex(Uint8List.fromList(stored.record.recordId));
    // Auto-Ja embedded: the submitter implicitly supports their request.
    await voteFeatureRequest(recordIdHex, SysChanVote.ja);
    final conv = conversations[SystemChannels.featureReqChannelIdHex];
    for (final m in conv?.messages ?? const <UiMessage>[]) {
      if (m.id == recordIdHex) return m;
    }
    return null;
  }

  /// D3 (§9.5.3): open vote record on a Feature-Request post. LWW per
  /// author — voting again changes the vote.
  @override
  Future<bool> voteFeatureRequest(String recordIdHex, int option) async {
    if (_reducedMode) return false;
    if (option < SysChanVote.ja || option > SysChanVote.egal) return false;
    final stored = await _publishSystemChannelRecord(
      channelIdHex: SystemChannels.featureReqChannelIdHex,
      kind: SysChanKind.vote,
      targetRecordId: Uint8List.fromList(hexToBytes(recordIdHex)),
      voteOption: option,
    );
    return stored != null;
  }

  /// D3 (§9.5.3): local tally over the open vote records. Keys: `ja`,
  /// `nein`, `egal`, `net`, `own` (-1 when the caller has not voted).
  @override
  Future<Map<String, int>> featureRequestTally(String recordIdHex) async {
    final chHex = SystemChannels.featureReqChannelIdHex;
    final tally = _sysChanStore.tallyFor(chHex, recordIdHex);
    final own =
        _sysChanStore.ownVote(chHex, recordIdHex, identity.userIdHex) ?? -1;
    return {
      'ja': tally.ja,
      'nein': tally.nein,
      'egal': tally.egal,
      'net': tally.net,
      'own': own,
    };
  }

  // ── Migration: deviceNodeId → userIdHex (V3.1.44) ─────────────────

  /// One-time migration: §26 Phase 2 temporarily used deviceNodeId as member key
  /// in groups/channels and as senderNodeIdHex in messages. Service-level
  /// identification must use the stable userId. This migrates stored data.
  void _migrateDeviceNodeIdToUserId() {
    final deviceHex = identity.nodeIdHex; // = deviceNodeIdHex
    final userHex = identity.userIdHex;
    if (deviceHex == userHex) return; // No-op if IDs happen to match (shouldn't, but safe)

    var migrated = false;

    // ── Groups ──
    for (final group in _groups.values) {
      // Re-key self in members map
      if (group.members.containsKey(deviceHex) && !group.members.containsKey(userHex)) {
        final self = group.members.remove(deviceHex)!;
        group.members[userHex] = GroupMemberInfo(
          nodeIdHex: userHex,
          displayName: self.displayName,
          role: self.role,
          ed25519Pk: self.ed25519Pk,
          x25519Pk: self.x25519Pk,
          mlKemPk: self.mlKemPk,
        );
        migrated = true;
        _log.info('Migrated self in group "${group.name}": deviceNodeId → userId');
      }
      // Fix ownerNodeIdHex
      if (group.ownerNodeIdHex == deviceHex) {
        group.ownerNodeIdHex = userHex;
        migrated = true;
      }
    }

    // ── Channels ──
    for (final channel in _channels.values) {
      if (channel.members.containsKey(deviceHex) && !channel.members.containsKey(userHex)) {
        final self = channel.members.remove(deviceHex)!;
        channel.members[userHex] = ChannelMemberInfo(
          nodeIdHex: userHex,
          displayName: self.displayName,
          role: self.role,
          ed25519Pk: self.ed25519Pk,
          x25519Pk: self.x25519Pk,
          mlKemPk: self.mlKemPk,
        );
        migrated = true;
        _log.info('Migrated self in channel "${channel.name}": deviceNodeId → userId');
      }
      if (channel.ownerNodeIdHex == deviceHex) {
        channel.ownerNodeIdHex = userHex;
        migrated = true;
      }
    }

    // ── Conversations: senderNodeIdHex + reactions + pendingConfigProposer ──
    for (final conv in conversations.values) {
      if (conv.pendingConfigProposer == deviceHex) {
        conv.pendingConfigProposer = userHex;
        migrated = true;
      }
      for (final msg in conv.messages) {
        if (msg.senderNodeIdHex == deviceHex) {
          msg.senderNodeIdHex = userHex;
          migrated = true;
        }
        // Reactions: replace deviceHex with userHex in all reaction sets
        for (final reactionSet in msg.reactions.values) {
          if (reactionSet.remove(deviceHex)) {
            reactionSet.add(userHex);
            migrated = true;
          }
        }
      }
    }

    if (migrated) {
      _saveGroups();
      _saveChannels();
      _saveConversations();
      _log.info('Migration deviceNodeId→userId complete');
    }
  }

  // ── Multi-Device Persistence (§26) ─────────────────────────────────

  /// Initialize local device ID (generated once, persisted in devices.json).
  void _initLocalDevice() {
    _loadDevices();

    // Check if we already have a local device ID on disk
    final existing = _devices.values.where((d) => d.isThisDevice).toList();
    if (existing.isNotEmpty) {
      _localDeviceId = existing.first.deviceId;
      existing.first.lastSeen = DateTime.now();
      // §26 Phase 4: ensure deviceNodeIdHex is set (migration from pre-Phase-4)
      existing.first.deviceNodeIdHex ??= bytesToHex(identity.deviceNodeId);
      _saveDevices();
      return;
    }

    // Generate new device ID (UUID v4 as hex)
    final uuid = SodiumFFI().randomBytes(16);
    _localDeviceId = bytesToHex(uuid);

    final now = DateTime.now();
    _devices[_localDeviceId] = DeviceRecord(
      deviceId: _localDeviceId,
      deviceName: Platform.localHostname,
      platform: _detectPlatform(),
      firstSeen: now,
      lastSeen: now,
      isThisDevice: true,
      deviceNodeIdHex: bytesToHex(identity.deviceNodeId),
    );
    _saveDevices();
    _log.info('Local device registered: $_localDeviceId (${Platform.localHostname})');
  }

  static String _detectPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }

  void _loadDevices() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/devices.json');
      if (json == null) {
        _devicesLoaded = true;
        return;
      }
      for (final entry in json.entries) {
        if (entry.key.startsWith('_')) continue;
        _devices[entry.key] = DeviceRecord.fromJson(entry.value as Map<String, dynamic>);
      }
      // Load sync dedup window.
      // New format: map of syncIdHex → firstSeen epoch-ms.
      // Legacy format: list of syncIdHex (seed with current timestamp so 7d TTL
      // applies from now on — safer than dropping all entries).
      final syncIdsMap = json['_syncIdTs'] as Map<String, dynamic>?;
      if (syncIdsMap != null) {
        for (final e in syncIdsMap.entries) {
          _processedSyncIds[e.key] = (e.value as num).toInt();
        }
      } else {
        final legacy = json['_syncIds'] as List<dynamic>?;
        if (legacy != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          for (final id in legacy.cast<String>()) {
            _processedSyncIds[id] = now;
          }
        }
      }
      // Prune expired entries (>7 days) on load
      _pruneSyncDedup();
      _devicesLoaded = true;
      _log.info('Loaded ${_devices.length} devices, ${_processedSyncIds.length} sync IDs');
    } catch (e) {
      _log.warn('Failed to load devices: $e');
    }
  }

  void _saveDevices() {
    if (!_devicesLoaded && _devices.isEmpty) {
      final encFile = File('$profileDir/devices.json.enc');
      if (encFile.existsSync()) {
        _log.warn('REFUSED to save empty devices — load failed but file exists');
        return;
      }
    }
    try {
      final json = <String, dynamic>{};
      for (final entry in _devices.entries) {
        json[entry.key] = entry.value.toJson();
      }
      // Persist sync dedup IDs with 7-day TTL (matches S&F window, §26 Dedup).
      _pruneSyncDedup();
      // Hard cap on the map size to bound memory (evict oldest first) even if
      // the 7-day window gets flooded. 10k ≈ ~60 entries/hour for a week.
      if (_processedSyncIds.length > 10000) {
        final sorted = _processedSyncIds.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        final evict = sorted.take(_processedSyncIds.length - 10000).map((e) => e.key).toList();
        for (final id in evict) {
          _processedSyncIds.remove(id);
        }
      }
      json['_syncIdTs'] = Map<String, int>.from(_processedSyncIds);
      _fileEnc.writeJsonFile('$profileDir/devices.json', json);
    } catch (e) {
      _log.warn('Failed to save devices: $e');
    }
  }

  /// Drop TWIN_SYNC dedup entries older than 7 days (§26 Dedup TTL).
  void _pruneSyncDedup() {
    final cutoff = DateTime.now().millisecondsSinceEpoch - _syncDedupTtlMs;
    _processedSyncIds.removeWhere((_, ts) => ts < cutoff);
  }

  /// Fire devices-updated + state-changed callbacks. Wrapper so every
  /// device mutation goes through a single place and emits the IPC event.
  void _notifyDevicesChanged() {
    try {
      onDevicesUpdated?.call();
    } catch (e) {
      _log.warn('onDevicesUpdated callback failed: $e');
    }
    onStateChanged?.call();
  }

  /// Public accessor: list of registered twin devices (for IPC/GUI).
  @override
  List<DeviceRecord> get devices => _devices.values.toList();

  /// Local device ID (UUID hex).
  @override
  String get localDeviceId => _localDeviceId;

  /// Rename a twin device and broadcast via TWIN_SYNC.
  @override
  void renameDevice(String deviceId, String newName) {
    final device = _devices[deviceId];
    if (device == null) return;
    device.deviceName = newName;
    _saveDevices();
    _log.info('Device renamed: $deviceId → $newName');

    // Broadcast to twins
    final payload = utf8.encode(jsonEncode({
      'deviceId': deviceId,
      'deviceName': newName,
    }));
    _sendTwinSync(proto.TwinSyncType.DEVICE_RENAMED, Uint8List.fromList(payload));
    _notifyDevicesChanged();
  }

  /// Revoke a twin device: remove from list, notify twins + contacts.
  /// Returns true if the device was found and revoked.
  @override
  Future<bool> revokeDevice(String deviceId) async {
    if (deviceId == _localDeviceId) return false; // Can't revoke self
    final device = _devices[deviceId];
    if (device == null) return false;

    _log.info('Revoking twin device: $deviceId (${device.deviceName})');

    // Notify twins: device has been revoked
    final payload = Uint8List.fromList(utf8.encode(deviceId));
    _sendTwinSync(proto.TwinSyncType.TWIN_DEVICE_REVOKED, payload);

    // Broadcast DEVICE_REVOKED to contacts with DeviceRecord proto (§26.6.1).
    // §26 Phase 4: include deviceNodeId so contacts can remove the specific
    // routing entry from their routing table.
    final revokedRecord = proto.DeviceRecord()
      ..deviceId = hexToBytes(deviceId)
      ..deviceName = device.deviceName;
    if (device.deviceNodeIdHex != null) {
      revokedRecord.deviceNodeId = hexToBytes(device.deviceNodeIdHex!);
    }
    final revokePayload = Uint8List.fromList(revokedRecord.writeToBuffer());
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      try {
        sendToUser(
          recipientUserId: contact.nodeId,
          messageType: proto.MessageTypeV3.MTV3_DEVICE_REVOCATION,
          payload: revokePayload,
        );
      } catch (e) {
        _log.warn('Failed to send DEVICE_REVOCATION to ${contact.displayName}: $e');
      }
    }

    _devices.remove(deviceId);
    _saveDevices();
    _notifyDevicesChanged();
    return true;
  }

  /// Inject a fake twin device for E2E testing (test-only).
  @override
  void injectTestDevice(String deviceId, String name, String platform) {
    final now = DateTime.now();
    _devices[deviceId] = DeviceRecord(
      deviceId: deviceId,
      deviceName: name,
      platform: platform,
      firstSeen: now,
      lastSeen: now,
    );
    _saveDevices();
    _notifyDevicesChanged();
    _log.info('Test device injected: $deviceId ($name)');
  }

  /// Test-only: read-only snapshot of the key-rotation retry state. Used by
  /// E2E harness (gui-52-key-rotation-retry) to assert pending/acked counts
  /// after an offline→online contact resurface.
  @override
  Map<String, dynamic> testGetKeyRotationRetryState() {
    final s = _keyRotationRetry.state;
    return {
      'hasActiveRotation': _keyRotationRetry.hasActiveRotation,
      'pendingCount': _keyRotationRetry.pendingCount,
      'ackedCount': _keyRotationRetry.ackedCount,
      'expiredCount': _keyRotationRetry.expiredCount,
      'rotationId': s?.rotationId,
      'pendingHexes': s?.pending.keys.toList() ?? const <String>[],
      'ackedHexes': s?.acked.toList() ?? const <String>[],
      'expiredHexes': s?.expired.toList() ?? const <String>[],
    };
  }

  /// Test-only: ignore the 24h retry interval and trigger the retry loop
  /// immediately for every pending contact. The production code path
  /// (`_retryPendingKeyRotations`) is reused unchanged — we only reset the
  /// per-contact attempt clocks so `duePending` reports them as due.
  @override
  void testForceKeyRotationRetry() {
    _keyRotationRetry.resetAttemptClocksForTesting();
    _retryPendingKeyRotations();
  }

  // ── Getters ────────────────────────────────────────────────────────

  @override
  String get nodeIdHex => identity.userIdHex;
  @override
  String get deviceNodeIdHex => identity.deviceNodeIdHex;
  @override
  Uint8List get deviceX25519Pk => node.deviceKem.x25519PublicKey;
  @override
  Uint8List get deviceMlKemPk => node.deviceKem.mlKemPublicKey;
  @override
  Uint8List get userEd25519Pk => identity.ed25519PublicKey;

  /// SR-2 (§8.1.1): founding anchor for the ContactSeed `fp` field.
  @override
  Uint8List get foundingEd25519Pk => identity.foundingEd25519Pk;
  @override
  int get peerCount => node.routingTable.peerCount;
  @override
  int get confirmedPeerCount => node.confirmedPeerIds.length;
  @override
  bool get hasPortMapping => node.natTraversal.hasPortMapping;

  @override
  bool get hasSessionConfirmedPeers => node.hasSessionConfirmedPeers;

  @override
  DateTime? get nodeStartedAt => node.nodeStartedAt;
  @override
  List<String> get localIps => node.localIps.isNotEmpty ? node.localIps : ['127.0.0.1'];
  @override
  String? get publicIp => node.natTraversal.publicIp;
  @override
  int? get publicPort => node.natTraversal.publicPort;
  @override
  int get fragmentCount => mailboxStore.fragmentCount;
  @override
  bool get isRunning => node.isRunning;
  @override
  bool get isLinkedDevice => identity.isLinkedDevice;

  @override
  LinkedDeviceStatus get linkedDeviceStatus {
    final ldKeys = identity.linkedDeviceKeys;
    if (!identity.isLinkedDevice || ldKeys == null) {
      return LinkedDeviceStatus(isLinkedDevice: false);
    }
    final cert = ldKeys.delegationCert;
    return LinkedDeviceStatus(
      isLinkedDevice: true,
      capabilities: cert.capabilities,
      issuedAtMs: cert.issuedAtMs,
      maxValidUntilMs: cert.maxValidUntilMs,
      isExpired: cert.isExpired(),
    );
  }

  @override
  Future<bool> requestDelegationRenewal() async {
    if (!identity.isLinkedDevice) {
      _log.warn('requestDelegationRenewal: not a linked device');
      return false;
    }
    _log.info('LD-9: requesting delegation renewal from Primary');
    return sendDevicePairRequest();
  }

  @override
  List<ContactInfo> get acceptedContacts =>
      _contacts.values.where((c) => c.status == 'accepted').toList();

  @override
  List<ContactInfo> get pendingContacts =>
      _contacts.values.where((c) => c.status == 'pending').toList();

  @override
  List<ContactInfo> get pendingOutgoingContacts =>
      _contacts.values.where((c) => c.status == 'pending_outgoing').toList();

  @override
  ContactInfo? getContact(String nodeIdHex) => _contacts[nodeIdHex];

  @override
  List<PeerSummary> get peerSummaries {
    // S119 B: reachable = confirmed ∪ alive DV route (NOT allDestinations —
    // that set contains dead routes and inflated the list, Problem 2).
    final confirmed = node.confirmedPeerIds;
    final reachable = node.reachablePeerIds;
    return node.routingTable.allPeers
        .where((p) => reachable.contains(p.nodeIdHex))
        .where((p) => p.publicIp.isNotEmpty || p.localIp.isNotEmpty || p.addresses.isNotEmpty)
        .map((p) {
      // Collect addresses: local + public IPv4 + IPv6 global (§27)
      final addrs = <String>[];
      final seen = <String>{};
      if (p.localIp.isNotEmpty && p.localPort > 0) {
        final key = '${p.localIp}:${p.localPort}';
        addrs.add(key);
        seen.add(key);
      }
      if (p.publicIp.isNotEmpty && p.publicPort > 0) {
        final key = '${p.publicIp}:${p.publicPort}';
        if (seen.add(key)) addrs.add(key);
      }
      // Include ALL addresses from the multi-address list: private IPv4,
      // public IPv4, IPv6 global. §8.1.1 seed-peer selection needs all
      // addresses so the scanner can choose the optimal one for its network
      // position (private when on same LAN, public when external).
      for (final addr in p.addresses) {
        if (addr.type == PeerAddressType.ipv6LinkLocal) continue;
        final key = addr.ip.contains(':')
            ? '[${addr.ip}]:${addr.port}'
            : '${addr.ip}:${addr.port}';
        if (seen.add(key)) addrs.add(key);
      }
      // Primary address: prefer IPv6 global > public IPv4 > local IPv4
      // Check both legacy publicIp field AND multi-address list for public IPv4
      final ipv6Addr = p.addresses.where((a) => a.type == PeerAddressType.ipv6Global).toList();
      final pubV4Addr = p.addresses.where((a) => a.type == PeerAddressType.ipv4Public).toList();
      final effectivePublicIp = p.publicIp.isNotEmpty ? p.publicIp
          : pubV4Addr.isNotEmpty ? pubV4Addr.first.ip : '';
      final effectivePublicPort = p.publicPort > 0 ? p.publicPort
          : pubV4Addr.isNotEmpty ? pubV4Addr.first.port : 0;
      final primaryIp = ipv6Addr.isNotEmpty ? ipv6Addr.first.ip
          : effectivePublicIp.isNotEmpty ? effectivePublicIp : p.localIp;
      final primaryPort = ipv6Addr.isNotEmpty ? ipv6Addr.first.port
          : effectivePublicPort > 0 ? effectivePublicPort : p.localPort;
      return PeerSummary(
        nodeIdHex: p.nodeIdHex,
        address: primaryIp,
        port: primaryPort,
        lastSeen: p.lastSeen,
        allAddresses: addrs,
        stabilityTierIndex: p.stabilityTier.index,
        // S119 B: direct = confirmed bidirectional UDP; otherwise the peer
        // is only reachable via an alive relay route (amber in the sheet).
        isDirect: confirmed.contains(p.nodeIdHex),
      );
    }).toList();
  }

  @override
  List<Conversation> get sortedConversations {
    final list = conversations.values.toList();
    list.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return list;
  }

  /// Get full state snapshot for IPC.
  Map<String, dynamic> getStateSnapshot() {
    // Sync profile pictures from contacts into conversations
    for (final conv in conversations.values) {
      if (!conv.isGroup && !conv.isChannel) {
        final contact = _contacts[conv.id];
        if (contact?.profilePictureBase64 != null) {
          conv.profilePictureBase64 = contact!.profilePictureBase64;
        }
      }
    }
    return {
      'nodeIdHex': nodeIdHex,
      'displayName': displayName,
      'port': port,
      'publicIp': publicIp,
      'publicPort': publicPort,
      'localIps': localIps,
      'peerCount': peerCount,
      'confirmedPeerCount': confirmedPeerCount,
      'hasPortMapping': hasPortMapping,
      'mobileFallbackActive': node.transport.isMobileFallbackActive,
      'fragmentCount': fragmentCount,
      'isRunning': isRunning,
      'isLinkedDevice': isLinkedDevice,
      'linkedDeviceStatus': linkedDeviceStatus.toJson(),
      'profilePicture': _profilePictureBase64,
      'profileDescription': _profileDescription,
      'isGuardianSetUp': isGuardianSetUp,
      'groups': _groups.map((k, v) => MapEntry(k, v.toJson())),
      'channels': _channels.map((k, v) => MapEntry(k, v.toJson())),
      'conversations': conversations.map((k, v) => MapEntry(k, v.toJson())),
      'acceptedContacts': acceptedContacts.map((c) => c.toJson()).toList(),
      'pendingContacts': pendingContacts.map((c) => c.toJson()).toList(),
      'pendingOutgoingContacts': pendingOutgoingContacts.map((c) => c.toJson()).toList(),
      'currentCall': currentCall?.toJson(),
      'isMuted': isMuted,
      'isSpeakerEnabled': isSpeakerEnabled,
      'peerSummaries': peerSummaries.map((p) => p.toJson()).toList(),
      'typingContacts': _typingTimestamps.entries
          .where((e) => DateTime.now().difference(e.value).inSeconds < 5)
          .map((e) => e.key)
          .toList(),
      'mediaSettings': _mediaSettings.toJson(),
      'notificationSettings': notificationSound.settings.toJson(),
      'devices': _devices.values.map((d) => d.toJson()).toList(),
      'localDeviceId': _localDeviceId,
      'deviceNodeIdHex': deviceNodeIdHex,
      'deviceX25519PkB64': base64Encode(deviceX25519Pk),
      'deviceMlKemPkB64': base64Encode(deviceMlKemPk),
      'userEd25519PkB64': base64Encode(userEd25519Pk),
      // SR-2: founding anchor (== userEd25519Pk for never-rotated identities).
      'foundingEd25519PkB64': base64Encode(foundingEd25519Pk),
    };
  }

  // ── Network Statistics ──────────────────────────────────────────

  /// Collect a full network statistics snapshot.
  @override
  NetworkStats getNetworkStats() {
    return node.statsCollector.collect(
      routingTable: node.routingTable,
      mailboxStore: mailboxStore,
      natTraversal: node.natTraversal,
      rttMap: node.dhtRpc.rttMap,
      isRunning: isRunning,
      profileDir: profileDir,
      // S119 B (Problem 2): "Aktive Peers" counter must equal the
      // connection-sheet list — both come from peerSummaries now.
      reachablePeerCount: peerSummaries.length,
      // D5 (§13.1.3): collective-quota observability.
      poolDropsRate: node.rateLimiter.poolDroppedPackets,
      poolDropsRelay: node.relayPoolDrops,
    );
  }

  // ── Contact issue reporting ────────────────────────────────────────
  @override
  Future<ContactIssueReport?> buildContactIssueReport(String contactNodeIdHex) async {
    final contact = _contacts[contactNodeIdHex];
    if (contact == null) return null;
    return contactIssueReporter.buildReport(contact);
  }

  @override
  Future<bool> publishContactIssueReport(String contactNodeIdHex) async {
    final report = await buildContactIssueReport(contactNodeIdHex);
    if (report == null) return false;
    return contactIssueReporter.publishReport(report);
  }

  @override
  LogReport buildLogReport() => crashReporter.buildLogReport();

  @override
  Future<bool> publishLogReport() async {
    final report = buildLogReport();
    return crashReporter.publishLogReport(report);
  }

  // ── NAT-Troubleshooting-Wizard (§27.9) ───────────────────────────────
  @override
  void Function()? onNatWizardTriggered;
  @override
  void Function()? onNatWizardUserRequested;

  @override
  Future<void> dismissNatWizard({required int durationSeconds}) async {
    if (durationSeconds <= 0) {
      // 0 = forever. JavaScript-style "far future" using Dart's int max-safe
      // constant. Practically never revisited.
      _natWizardDismissedUntilMs = 0x7FFFFFFFFFFFFFFF;
    } else {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _natWizardDismissedUntilMs = nowMs + durationSeconds * 1000;
    }
    _saveNatWizardSettings();
    _log.info('NAT-Wizard dismissed until $_natWizardDismissedUntilMs '
        '(durationSeconds=$durationSeconds)');
  }

  /// Test-only (E2E gui-53): fire [onNatWizardTriggered] directly, bypassing
  /// the 10-min uptime gate, network checks and dismissed-flag from §27.9.1.
  /// The GUI-side `_natWizardShown` latch in `home_screen.dart` still applies,
  /// so a second force-trigger after the dialog has been shown (and not reset)
  /// is a no-op — tests rely on that to verify the dismiss path.
  @override
  void testForceNatWizardTrigger() {
    _log.info('NAT-Wizard: test-force trigger (E2E gui-53)');
    onNatWizardTriggered?.call();
  }

  /// User-initiated trigger via icon-tap in home_screen. Differs from the
  /// auto-trigger in that we also reset the dismiss-until flag (the user
  /// explicitly asked for it, overriding any earlier "Spaeter" click).
  ///
  /// Fires [onNatWizardUserRequested], NOT [onNatWizardTriggered] — the
  /// GUI-side auto-trigger latch must not apply here, otherwise a user who
  /// already saw the auto-dialog once this session could not manually
  /// re-open it via the icon. See home_screen.dart wiring.
  @override
  void requestNatWizard() {
    _natWizardDismissedUntilMs = 0;
    _saveNatWizardSettings();
    _log.info('NAT-Wizard: user-requested trigger (icon tap)');
    onNatWizardUserRequested?.call();
  }

  /// Test-only (E2E gui-53): clear the persistent dismissed-until flag so the
  /// next real trigger can fire again. Pairs with the GUI-level latch reset
  /// via `gui_action('reset_nat_wizard_latch')`.
  @override
  void testResetNatWizardDismissed() {
    _natWizardDismissedUntilMs = 0;
    _saveNatWizardSettings();
    _log.info('NAT-Wizard: test-reset dismissed flag (E2E gui-53)');
  }

  @override
  Future<bool> recheckNatWizard() async {
    // §27.9.2 Step 3: re-run UPnP discovery + hole-punch round + 30s
    // observation of directConnections > 0. No implicit retry — user must
    // have already edited the router rule before clicking "Jetzt pruefen".
    _log.info('NAT-Wizard recheck: resetting port mapper + punch round');
    try {
      await node.portMapper.reset();
      // Start port mapping in background — don't await (completes async).
      node.portMapper.start();
    } catch (e) {
      _log.debug('NAT-Wizard recheck: portMapper reset failed — $e');
      // Continue anyway; the direct-connection observation below is the
      // real success signal.
    }

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final snap = getNetworkStats();
      if (snap.directConnections > 0) {
        _log.info('NAT-Wizard recheck: direct connection observed '
            '(${snap.directConnections})');
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _log.info('NAT-Wizard recheck: no direct connections after 30s');
    return false;
  }

  void _loadNatWizardSettings() {
    try {
      final file = File('$profileDir/nat_wizard_settings.json');
      if (file.existsSync()) {
        final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        _natWizardDismissedUntilMs =
            (j['nat_wizard_dismissed_until'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      _log.debug('Failed to load nat wizard settings: $e');
    }
  }

  void _saveNatWizardSettings() {
    try {
      final file = File('$profileDir/nat_wizard_settings.json');
      file.writeAsStringSync(jsonEncode({
        'nat_wizard_dismissed_until': _natWizardDismissedUntilMs,
      }));
    } catch (e) {
      _log.debug('Failed to save nat wizard settings: $e');
    }
  }

  // ── Key Rotation ──────────────────────────────────────────────────

  /// Rotate KEM keys and broadcast to all contacts.
  /// Async: ML-KEM keygen runs in background isolate (ANR fix).
  Future<void> _performKeyRotation() async {
    await identity.rotateKemKeys();
    // §5.11 — periodic 120 s peer-exchange tick is gone; rotations are an
    // event the mesh learns about explicitly. Push our refreshed PeerInfo
    // (carries new KEM PK) to every known peer once.
    node.broadcastAddressUpdate();

    // Build KEY_ROTATION message
    final rotationMsg = proto.KeyRotation()
      ..newX25519Pk = identity.x25519PublicKey
      ..newMlKemPk = identity.mlKemPublicKey
      ..rotationTimestamp = Int64(DateTime.now().millisecondsSinceEpoch);

    // Sign the rotation data with our identity key
    final dataToSign = rotationMsg.writeToBuffer();
    rotationMsg.signature = SodiumFFI().signEd25519(dataToSign, identity.ed25519SecretKey);

    // Broadcast to all accepted contacts
    final payload = Uint8List.fromList(rotationMsg.writeToBuffer());
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST,
        payload: payload,
      );
    }

    _log.info('Key rotation complete, broadcast to ${acceptedContacts.length} contacts');
  }

  /// Emergency full identity rotation (§26.6.2): new seed, new keys, broadcast to all.
  /// Called from GUI "Identität neu schlüsseln" button.
  /// Generates new master seed, derives all new keys, sends dual-signed
  /// KEY_ROTATION_BROADCAST to all contacts, syncs new seed to twin devices.
  @override
  Future<void> rotateIdentityKeys() async {
    // §7.1 LD-5: only the Primary device (with master seed) may rotate keys.
    if (identity.isLinkedDevice) {
      _log.warn('rotateIdentityKeys: blocked — this is a Linked Device '
          '(no master seed). Rotation must be initiated on the Primary.');
      return;
    }

    final sodium = SodiumFFI();

    // §5.6: save current primary mailbox ID before Ed25519 changes
    final preRotInput = Uint8List.fromList(
      [...utf8.encode('mailbox'), ...identity.ed25519PublicKey],
    );
    _previousMailboxPrimary = sodium.sha256(preRotInput);
    _previousMailboxPrimarySetAt = DateTime.now();
    _saveMailboxTransition();

    // 1. Generate new seed → new keys (BEFORE sending, so we can dual-sign)
    final newEntropy = sodium.randomBytes(32);
    final newMasterSeed = SeedPhrase.entropyToSeed(newEntropy);
    final hdIndex = identity.hdIndex ?? 0;

    final newEd25519 = HdWallet.deriveEd25519(newMasterSeed, hdIndex);
    final newX25519Pk = sodium.ed25519PkToX25519(newEd25519.publicKey);
    final newX25519Sk = sodium.ed25519SkToX25519(newEd25519.secretKey);

    // PQ keygen: deterministic from new seed (recovery must reproduce same keys)
    final pqKeys = await generatePqKeysDeterministicIsolated(newMasterSeed, hdIndex);
    final newMlDsa = (publicKey: pqKeys.mlDsaPk, secretKey: pqKeys.mlDsaSk);
    final newMlKem = (publicKey: pqKeys.mlKemPk, secretKey: pqKeys.mlKemSk);

    // 2. Build KeyRotationBroadcast with dual signatures
    final broadcast = proto.KeyRotationBroadcast()
      ..newEd25519Pk = newEd25519.publicKey
      ..newMlDsaPk = newMlDsa.publicKey
      ..newX25519Pk = newX25519Pk
      ..newMlKemPk = newMlKem.publicKey;

    // Sign the data payload (without signature fields) with BOTH keys
    final dataToSign = broadcast.writeToBuffer();
    broadcast.oldSignatureEd25519 =
        sodium.signEd25519(dataToSign, identity.ed25519SecretKey); // OLD key
    broadcast.newSignatureEd25519 =
        sodium.signEd25519(dataToSign, newEd25519.secretKey); // NEW key

    // §7.5 Co-Auth: collect Device-Sig countersigs from Linked Devices
    final pub0 = _identityPublisher;
    final linkedDelegations = pub0?.delegations ?? <DeviceDelegation>[];
    final totalDevices = linkedDelegations.length + 1; // +1 for Primary
    final approvalTokens = <RotationApprovalToken>[];

    if (totalDevices >= 2) {
      final rotHash = computeRotationHash(
        newEd25519Pk: newEd25519.publicKey,
        newMlDsaPk: newMlDsa.publicKey,
        newX25519Pk: newX25519Pk,
        newMlKemPk: newMlKem.publicKey,
        userId: identity.userId,
      );

      // Primary's own approval token
      final deviceKp = node.deviceKeyPair;
      approvalTokens.add(RotationApprovalToken(
        deviceNodeId: identity.deviceNodeId,
        rotationHash: rotHash,
        deviceEd25519Sig: SodiumFFI().signEd25519(rotHash, deviceKp.ed25519PrivateKey),
        deviceMlDsaSig: OqsFFI().mlDsaSign(rotHash, deviceKp.mlDsaPrivateKey),
      ));

      // Request approval from Linked Devices (5min timeout)
      _pendingRotationHash = rotHash;
      _collectedApprovalTokens.clear();
      _rotationApprovalCompleter = Completer<void>();

      final reqPayload = proto.RotationApprovalRequestPayload()
        ..rotationHash = rotHash;
      _sendTwinSync(proto.TwinSyncType.ROTATION_APPROVAL_REQUEST,
          Uint8List.fromList(reqPayload.writeToBuffer()));
      _log.info('§7.5 ROTATION_APPROVAL_REQUEST sent to ${linkedDelegations.length} '
          'linked device(s), waiting up to 5min');

      await _rotationApprovalCompleter!.future
          .timeout(const Duration(minutes: 5), onTimeout: () {
        _log.warn('§7.5 Approval timeout — proceeding with '
            '${_collectedApprovalTokens.length + 1}/$totalDevices tokens');
      });

      approvalTokens.addAll(_collectedApprovalTokens);
      _pendingRotationHash = null;
      _collectedApprovalTokens.clear();
      _rotationApprovalCompleter = null;

      _log.info('§7.5 Co-Auth complete: ${approvalTokens.length}/$totalDevices '
          'tokens (quorum=${rotationQuorum(totalDevices)})');
    }

    // Embed approval tokens in broadcast
    broadcast.approvalTokens.addAll(approvalTokens.map((t) => t.toProto()));
    broadcast.preRotationDeviceCount = totalDevices;

    // 3. Send KEY_ROTATION_BROADCAST to all contacts (signed with OLD identity).
    //    Welle 6 §7.4 Variant (b) — Emergency-flavor MUST go on the
    //    InfrastructureFrame path: KEM-encap under each contact's
    //    Device-KEM-PK, Outer Device-Sig under the unchanged Device-Sig keys
    //    (rotation-stable per §3.5b). The dual-sig in the body is the inner
    //    authentication subject. Every recipient device gets its own frame
    //    (per-device fan-out via 2D-DHT auth-manifest).
    final payloadBytes = Uint8List.fromList(broadcast.writeToBuffer());
    // Paket C: pre-rotation hex for the persisted retry state. SR-2: the
    // userId is a stable anchor (§3.1) and no longer changes on rotation —
    // this now always equals the post-rotation hex; kept for the persisted
    // retry-state format.
    final oldUserIdHex = identity.userIdHex;
    final sentToHex = <String>[];
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      try {
        final resolved = await node.identityResolver.resolve(contact.nodeId);
        if (resolved.isEmpty) {
          _log.warn('KEY_ROTATION_BROADCAST: no devices resolved for '
              '${contact.displayName} '
              '(${bytesToHex(contact.nodeId).substring(0, 8)}) — skipped, '
              'retry timer will pick this up');
          // Still register for retry so an offline contact eventually receives
          // the rotation when their AuthManifest becomes reachable again.
          sentToHex.add(bytesToHex(contact.nodeId));
          continue;
        }
        var anyOk = false;
        for (final dev in resolved) {
          final ok = await node.sendInfraTo(
            messageType: proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST,
            innerPayload: payloadBytes,
            recipientDeviceId: dev.deviceNodeId,
          );
          anyOk = anyOk || ok;
        }
        if (anyOk) {
          _log.info('KEY_ROTATION_BROADCAST (Emergency, InfraFrame) sent to '
              '${contact.displayName} '
              '(${bytesToHex(contact.nodeId).substring(0, 8)}) — '
              '${resolved.length} device(s)');
        } else {
          _log.warn('KEY_ROTATION_BROADCAST: all ${resolved.length} device(s) '
              'sends failed for ${contact.displayName} — registering for '
              'retry');
        }
        sentToHex.add(bytesToHex(contact.nodeId));
      } catch (e) {
        _log.warn('Failed to send KEY_ROTATION_BROADCAST to '
            '${contact.displayName}: $e');
      }
    }
    final sentCount = sentToHex.length;

    // 4. Send rotation material to twin devices (encrypted with OLD key).
    //    §7.1 LD-8: Linked Devices get per-device delegation keys (no seed!).
    //    Legacy twins (seed-on-every-device) get entropy as before.
    if (_devices.length > 1) {
      final pub = _identityPublisher;
      final linkedDeviceIds = pub != null
          ? pub.delegations.map((d) => bytesToHex(d.deviceId)).toSet()
          : <String>{};

      // 4a. Linked devices: per-device delegation rotation
      for (final delegation in pub?.delegations ?? <DeviceDelegation>[]) {
        _sendDelegationRotation(
          targetDeviceId: delegation.deviceId,
          capabilities: delegation.capabilities,
          maxValidUntilMs: delegation.maxValidUntilMs,
          newMasterSeed: newMasterSeed,
          newEd25519Pk: newEd25519.publicKey,
          newMlDsaPk: newMlDsa.publicKey,
          newX25519Pk: newX25519Pk,
          newMlKemPk: newMlKem.publicKey,
          newX25519Sk: newX25519Sk,
          newMlKemSk: newMlKem.secretKey,
        );
      }

      // 4b. Legacy twins only: entropy (they already hold the seed)
      final hasLegacyTwins = _devices.keys.any((devHex) =>
          devHex != _localDeviceId && !linkedDeviceIds.contains(devHex));
      if (hasLegacyTwins) {
        final seedPayload = utf8.encode(jsonEncode({
          'emergencyRotation': true,
          'newEntropy': bytesToHex(newEntropy),
          'hdIndex': hdIndex,
        }));
        _sendTwinSync(
            proto.TwinSyncType.SETTINGS_CHANGED, Uint8List.fromList(seedPayload));
      }
    }

    // 5. NOW apply new keys locally (after all messages sent with OLD key)
    identity.rotateIdentityFull(
      newEd25519Pk: newEd25519.publicKey,
      newEd25519Sk: newEd25519.secretKey,
      newMlDsaPk: newMlDsa.publicKey,
      newMlDsaSk: newMlDsa.secretKey,
      newX25519Pk: newX25519Pk,
      newX25519Sk: newX25519Sk,
      newMlKemPk: newMlKem.publicKey,
      newMlKemSk: newMlKem.secretKey,
    );

    // §5.11 — periodic peer-exchange tick is gone. After full identity
    // rotation, push refreshed PeerInfo (carries new Ed25519/ML-DSA + KEM
    // PKs) to every known peer once so transit/non-contact peers can heal
    // their stale-PK caches without waiting for the §5.12 cold-path 1 h tick.
    node.broadcastAddressUpdate();

    // SR-2: republish the Auth-Manifest promptly so the DHT carries the
    // chained manifest (new embedded keys + rotation chain, §4.3 path 2)
    // instead of waiting for the 20h refresh tick. The 7-day old-KEM
    // retention covers senders still resolving the pre-rotation manifest.
    final pub = _identityPublisher;
    if (pub != null) {
      pub.stop();
      unawaited(pub.start());
    }

    // 6. Initialize ACK tracking + persisted retry state (§26.6.2 Paket C).
    // The retry manager stores `payloadBytes` (the dual-signed inner
    // broadcast) so we can re-send to contacts that have not ACKed without
    // needing the OLD signing key (which is already wiped).
    _keyRotationRetry.startNewRotation(
      broadcastBytes: payloadBytes,
      contactNodeIdsHex: sentToHex,
      oldUserIdHex: oldUserIdHex,
      now: DateTime.now().millisecondsSinceEpoch,
    );

    _log.info('Emergency key rotation complete. '
        'Broadcast to $sentCount contacts. '
        'UserID ${identity.userIdHex.substring(0, 16)}... unchanged '
        '(stable anchor, chain ${identity.rotationChain.length} link(s))');
    onStateChanged?.call();
  }

  /// Handle incoming KEY_ROTATION from a contact.
  /// Periodic KEM-only key rotation (§7.4 Variant a). [payload] is the
  /// already-decrypted+authenticated `KeyRotation` proto bytes (V3 inner
  /// User-Sig + outer Device-Sig + KEM-decap chain verified upstream).
  /// [senderUserId] is the rotating peer's user-id (frame.senderUserId).
  void _handleKeyRotation(Uint8List payload, Uint8List senderUserId) {
    final senderHex = bytesToHex(senderUserId);
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') return;

    try {
      final rotation = proto.KeyRotation.fromBuffer(payload);

      // Verify signature (signed with sender's ed25519 key)
      if (contact.ed25519Pk != null) {
        final dataToVerify = (proto.KeyRotation()
              ..newX25519Pk = rotation.newX25519Pk
              ..newMlKemPk = rotation.newMlKemPk
              ..rotationTimestamp = rotation.rotationTimestamp)
            .writeToBuffer();
        final valid = SodiumFFI().verifyEd25519(
          dataToVerify,
          Uint8List.fromList(rotation.signature),
          contact.ed25519Pk!,
        );
        if (!valid) {
          _log.warn('KEY_ROTATION signature invalid from ${senderHex.substring(0, 8)}');
          return;
        }
      }

      // Update contact's KEM keys
      contact.x25519Pk = Uint8List.fromList(rotation.newX25519Pk);
      contact.mlKemPk = Uint8List.fromList(rotation.newMlKemPk);
      _saveContacts();

      // Update keys in group member entries
      for (final group in _groups.values) {
        final member = group.members[senderHex];
        if (member != null) {
          member.x25519Pk = contact.x25519Pk;
          member.mlKemPk = contact.mlKemPk;
        }
      }
      _saveGroups();

      // Update keys in channel member entries
      for (final channel in _channels.values) {
        final member = channel.members[senderHex];
        if (member != null) {
          member.x25519Pk = contact.x25519Pk;
          member.mlKemPk = contact.mlKemPk;
        }
      }
      _saveChannels();

      // Update routing table
      final peer = node.routingTable.getPeer(senderUserId);
      if (peer != null) {
        peer.x25519PublicKey = contact.x25519Pk!;
        peer.mlKemPublicKey = contact.mlKemPk!;
      }

      _log.info('Key rotation received from ${contact.displayName}');
    } on KemVersionRejectedException catch (e) {
      _warnKemVersionRejected('KEY_ROTATION', e);
    } catch (e) {
      _log.error('KEY_ROTATION processing failed: $e');
    }
  }

  // ── Multi-Device Twin-Sync (§26) ───────────────────────────────────

  /// Send a TWIN_SYNC message to all known twin devices.
  /// Encrypted with own pubkey (Per-Message KEM to self).
  void _sendTwinSync(proto.TwinSyncType syncType, Uint8List payload) {
    if (_devices.length <= 1) return; // No twins to sync to

    final syncId = SodiumFFI().randomBytes(16);
    final syncIdHex = bytesToHex(syncId);
    // Pre-mark with current timestamp to avoid processing our own sync + 7d TTL
    _processedSyncIds[syncIdHex] = DateTime.now().millisecondsSinceEpoch;

    final syncEnvelope = proto.TwinSyncEnvelope()
      ..syncId = syncId
      ..deviceId = hexToBytes(_localDeviceId)
      ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch)
      ..syncType = syncType
      ..payload = payload;

    final syncBytes = Uint8List.fromList(syncEnvelope.writeToBuffer());

    // V3: TWIN_SYNC fan-out to our own user-id resolves all our authorized
    // device-ids — kanonischer Multi-Device-Use-Case for sendToUser.
    try {
      sendToUser(
        recipientUserId: identity.nodeId,
        messageType: proto.MessageTypeV3.MTV3_TWIN_SYNC,
        payload: syncBytes,
      );
      _log.debug('TWIN_SYNC($syncType) sent to ${_devices.length - 1} twins');
    } catch (e) {
      _log.warn('Failed to send TWIN_SYNC: $e');
    }
  }

  /// Send TWIN_ANNOUNCE to register this device with existing twins.
  void _sendTwinAnnounce() {
    if (_devices.length <= 1) return;

    final record = proto.DeviceRecord()
      ..deviceId = hexToBytes(_localDeviceId)
      ..deviceName = _devices[_localDeviceId]?.deviceName ?? Platform.localHostname
      ..platform = _platformToProto(_detectPlatform())
      ..firstSeen = Int64(_devices[_localDeviceId]?.firstSeen.millisecondsSinceEpoch ?? 0)
      ..lastSeen = Int64(DateTime.now().millisecondsSinceEpoch)
      ..deviceNodeId = identity.deviceNodeId;

    final payload = Uint8List.fromList(record.writeToBuffer());

    // V3: no MTV3_TWIN_ANNOUNCE — wrapped as TWIN_SYNC sub-type DEVICE_ANNOUNCE.
    try {
      final wrapper = proto.TwinSyncEnvelope()
        ..syncId = SodiumFFI().randomBytes(16)
        ..deviceId = hexToBytes(_localDeviceId)
        ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch)
        ..syncType = proto.TwinSyncType.DEVICE_ANNOUNCE
        ..payload = payload;
      sendToUser(
        recipientUserId: identity.nodeId,
        messageType: proto.MessageTypeV3.MTV3_TWIN_SYNC,
        payload: Uint8List.fromList(wrapper.writeToBuffer()),
      );
      _log.info('TWIN_ANNOUNCE (V3 TWIN_SYNC/DEVICE_ANNOUNCE) sent for $_localDeviceId');
    } catch (e) {
      _log.warn('Failed to send TWIN_ANNOUNCE: $e');
    }
  }

  static proto.DevicePlatform _platformToProto(String platform) {
    switch (platform) {
      case 'android': return proto.DevicePlatform.PLATFORM_ANDROID;
      case 'ios': return proto.DevicePlatform.PLATFORM_IOS;
      case 'linux': return proto.DevicePlatform.PLATFORM_LINUX;
      case 'windows': return proto.DevicePlatform.PLATFORM_WINDOWS;
      case 'macos': return proto.DevicePlatform.PLATFORM_MACOS;
      default: return proto.DevicePlatform.PLATFORM_UNKNOWN;
    }
  }

  static String _detectPlatformFromProto(proto.DevicePlatform p) {
    switch (p) {
      case proto.DevicePlatform.PLATFORM_ANDROID: return 'android';
      case proto.DevicePlatform.PLATFORM_IOS: return 'ios';
      case proto.DevicePlatform.PLATFORM_LINUX: return 'linux';
      case proto.DevicePlatform.PLATFORM_WINDOWS: return 'windows';
      case proto.DevicePlatform.PLATFORM_MACOS: return 'macos';
      default: return 'unknown';
    }
  }

  // ── Twin-Sync sub-handlers ─────────────────────────────────────────

  void _handleTwinContactAdded(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final nodeIdHex = json['nodeId'] as String;
      if (_contacts.containsKey(nodeIdHex)) return; // Already known

      final contact = ContactInfo(
        nodeId: hexToBytes(nodeIdHex),
        displayName: json['displayName'] as String? ?? '',
        ed25519Pk: json['ed25519Pk'] != null ? hexToBytes(json['ed25519Pk'] as String) : null,
        x25519Pk: json['x25519Pk'] != null ? hexToBytes(json['x25519Pk'] as String) : null,
        mlKemPk: json['mlKemPk'] != null ? hexToBytes(json['mlKemPk'] as String) : null,
        mlDsaPk: json['mlDsaPk'] != null ? hexToBytes(json['mlDsaPk'] as String) : null,
        status: 'accepted',
        acceptedAt: DateTime.now(),
      );
      final twinDeviceIds = json['deviceNodeIds'];
      if (twinDeviceIds is List) {
        contact.deviceNodeIds.addAll(twinDeviceIds.cast<String>());
      }
      _contacts[nodeIdHex] = contact;
      _saveContacts();
      _log.info('Twin-synced contact added: ${json['displayName']}');
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Twin CONTACT_ADDED failed: $e');
    }
  }

  void _handleTwinContactDeleted(List<int> payload) {
    try {
      final nodeIdHex = utf8.decode(payload);
      if (_contacts.containsKey(nodeIdHex)) {
        final name = _contacts[nodeIdHex]!.displayName;
        _contacts.remove(nodeIdHex);
        _deletedContacts.add(nodeIdHex);
        _saveContacts();
        _log.info('Twin-synced contact deleted: $name');
        onStateChanged?.call();
      }
    } catch (e) {
      _log.warn('Twin CONTACT_DELETED failed: $e');
    }
  }

  void _handleTwinMessageSent(List<int> payload) {
    try {
      // Payload is a JSON-encoded map: {conversationId, text, messageId, timestamp}
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final conversationId = json['conversationId'] as String;
      final text = json['text'] as String;
      final messageId = json['messageId'] as String;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int);

      // Avoid duplicate if we already have this message
      final conv = conversations[conversationId];
      if (conv != null && conv.messages.any((m) => m.id == messageId)) return;

      final msg = UiMessage(
        id: messageId,
        conversationId: conversationId,
        senderNodeIdHex: identity.userIdHex,
        text: text,
        timestamp: timestamp,
        type: UiMessageType.text,
        status: MessageStatus.sent,
        isOutgoing: true,
      );

      if (conv != null) {
        conv.messages.add(msg);
        conv.lastActivity = timestamp;
        _saveConversations();
        onStateChanged?.call();
      }
      _log.debug('Twin-synced outgoing message to $conversationId');
    } catch (e) {
      _log.warn('Twin MESSAGE_SENT failed: $e');
    }
  }

  void _handleTwinMessageEdited(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final conversationId = json['conversationId'] as String;
      final messageId = json['messageId'] as String;
      final newText = json['text'] as String;

      final conv = conversations[conversationId];
      if (conv == null) return;
      final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
      if (msg == null) return;

      msg.text = newText;
      msg.editedAt = DateTime.now();
      _saveConversations();
      onStateChanged?.call();
      _log.debug('Twin-synced message edit in $conversationId');
    } catch (e) {
      _log.warn('Twin MESSAGE_EDITED failed: $e');
    }
  }

  void _handleTwinMessageDeleted(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final conversationId = json['conversationId'] as String;
      final messageId = json['messageId'] as String;

      final conv = conversations[conversationId];
      if (conv == null) return;
      final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
      if (msg == null) return;

      msg.isDeleted = true;
      msg.text = '';
      _saveConversations();
      onStateChanged?.call();
      _log.debug('Twin-synced message delete in $conversationId');
    } catch (e) {
      _log.warn('Twin MESSAGE_DELETED failed: $e');
    }
  }

  void _handleTwinReadReceipt(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final conversationId = json['conversationId'] as String;

      final conv = conversations[conversationId];
      if (conv == null) return;
      if (conv.unreadCount == 0) return;
      conv.unreadCount = 0;
      // Bug #U3+#U15: Twin-Device-Read muss auch Android-Launcher-Badge
      // aktualisieren — sonst bleibt Badge auf Primary hängen, obwohl der
      // User auf dem Zweitgerät gelesen hat.
      onCancelNotificationAndroid?.call(conversationId);
      _updateBadgeCount();
      _saveConversations();
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Twin READ_RECEIPT failed: $e');
    }
  }

  void _handleTwinGroupCreated(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final groupInfo = GroupInfo.fromJson(json);
      if (_groups.containsKey(groupInfo.groupIdHex)) return;
      _groups[groupInfo.groupIdHex] = groupInfo;
      _saveGroups();
      _log.info('Twin-synced group created: ${groupInfo.name}');
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Twin GROUP_CREATED failed: $e');
    }
  }

  void _handleTwinProfileChanged(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      if (json.containsKey('displayName')) {
        displayName = json['displayName'] as String;
      }
      if (json.containsKey('profilePicture')) {
        _profilePictureBase64 = json['profilePicture'] as String?;
        _saveProfilePicture();
      }
      onStateChanged?.call();
      _log.info('Twin-synced profile change');
    } catch (e) {
      _log.warn('Twin PROFILE_CHANGED failed: $e');
    }
  }

  /// Handle SETTINGS_CHANGED from twin: includes emergency key rotation (§26.6.2)
  /// and §7.1 LD-8 delegation rotation.
  /// Async: PQ keygen runs in background isolate (ANR fix).
  Future<void> _handleTwinSettingsChanged(List<int> payload) async {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;

      // §7.1 LD-8: delegation rotation for Linked Devices (no seed transfer)
      if (json['delegationRotation'] == true) {
        await _handleDelegationRotation(json);
        return;
      }

      if (json['emergencyRotation'] == true) {
        // §7.1 LD-5: Linked Devices must NOT process seed entropy —
        // they receive delegation rotation via the path above.
        if (identity.isLinkedDevice) {
          _log.warn('Ignoring emergency rotation entropy — '
              'this is a Linked Device (LD-5 guard)');
          return;
        }
        final newEntropyHex = json['newEntropy'] as String;
        final hdIndex = json['hdIndex'] as int? ?? identity.hdIndex ?? 0;
        final newEntropy = hexToBytes(newEntropyHex);
        final newMasterSeed = SeedPhrase.entropyToSeed(newEntropy);

        final sodium = SodiumFFI();
        final newEd25519 = HdWallet.deriveEd25519(newMasterSeed, hdIndex);
        final newX25519Pk = sodium.ed25519PkToX25519(newEd25519.publicKey);
        final newX25519Sk = sodium.ed25519SkToX25519(newEd25519.secretKey);

        // PQ keygen: deterministic from new seed
        final pqKeys = await generatePqKeysDeterministicIsolated(newMasterSeed, hdIndex);

        identity.rotateIdentityFull(
          newEd25519Pk: newEd25519.publicKey,
          newEd25519Sk: newEd25519.secretKey,
          newMlDsaPk: pqKeys.mlDsaPk,
          newMlDsaSk: pqKeys.mlDsaSk,
          newX25519Pk: newX25519Pk,
          newX25519Sk: newX25519Sk,
          newMlKemPk: pqKeys.mlKemPk,
          newMlKemSk: pqKeys.mlKemSk,
        );
        // §5.11 — same as the originating-device path: push refreshed
        // PeerInfo to all known peers so the mesh heals stale-PK caches
        // without waiting for the §5.12 cold-path 1 h tick.
        node.broadcastAddressUpdate();
        // SR-2: prompt chained-manifest republish (see originating path).
        final pub = _identityPublisher;
        if (pub != null) {
          pub.stop();
          unawaited(pub.start());
        }
        _log.info('Emergency key rotation applied from twin. '
            'UserID ${identity.userIdHex.substring(0, 16)}... unchanged '
            '(stable anchor)');
        onStateChanged?.call();
      }
    } catch (e) {
      _log.warn('Twin SETTINGS_CHANGED failed: $e');
    }
  }

  void _handleTwinDeviceRenamed(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final deviceId = json['deviceId'] as String;
      final newName = json['deviceName'] as String;
      if (_devices.containsKey(deviceId)) {
        _devices[deviceId]!.deviceName = newName;
        _saveDevices();
        _log.info('Twin device renamed: $deviceId → $newName');
        _notifyDevicesChanged();
      }
    } catch (e) {
      _log.warn('Twin DEVICE_RENAMED failed: $e');
    }
  }

  void _handleTwinDeviceRevoked(List<int> payload) {
    try {
      final deviceIdHex = utf8.decode(payload);
      if (deviceIdHex == _localDeviceId) {
        // This device has been revoked — wipe and return to welcome
        _log.warn('THIS DEVICE has been revoked by another twin!');
        // Wipe will be handled by the GUI layer via callback
        _notifyDevicesChanged();
        return;
      }
      _devices.remove(deviceIdHex);
      _saveDevices();
      _log.info('Twin device revoked: $deviceIdHex');
      _notifyDevicesChanged();
    } catch (e) {
      _log.warn('Twin DEVICE_REVOKED failed: $e');
    }
  }

  /// Handle KEY_ROTATION_BROADCAST from a contact.
  /// Dispatches between periodic KEM rotation (legacy KeyRotation format)
  /// and emergency full rotation (KeyRotationBroadcast with dual-signature).
  /// KEY_ROTATION_BROADCAST handler (§7.4). [payload] is the already-
  /// decrypted+authenticated `KeyRotationBroadcast` proto bytes (V3 inner
  /// User-Sig + outer Device-Sig + KEM-decap chain verified upstream;
  /// for the Emergency variant on InfraFrame the inner dual-sig in the
  /// body is the canonical authenticator). [senderUserId] is the
  /// rotating peer's user-id (frame.senderUserId on AppFrame, or the
  /// inferred old-userId via `_findSenderUserIdForKeyRotation` on
  /// InfraFrame).
  ///
  /// Discriminator (defence in depth — wire-path bridges already enforce
  /// it upstream): dual-sig populated → Emergency, single-sig → Periodic.
  void _handleKeyRotationBroadcast(Uint8List payload, Uint8List senderUserId) {
    final senderHex = bytesToHex(senderUserId);
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') return;

    try {
      final broadcast = proto.KeyRotationBroadcast.fromBuffer(payload);
      if (broadcast.oldSignatureEd25519.isNotEmpty &&
          broadcast.newSignatureEd25519.isNotEmpty) {
        _handleEmergencyKeyRotation(senderUserId, contact, senderHex, broadcast);
      } else {
        // Periodic KEM rotation — delegate to legacy handler. Re-serialize
        // the parsed body so the periodic handler parses a clean
        // KeyRotation proto (the body is wire-compatible since the dual-
        // sig fields are absent).
        _handleKeyRotation(payload, senderUserId);
      }
    } on KemVersionRejectedException catch (e) {
      _warnKemVersionRejected('KEY_ROTATION_BROADCAST', e);
    } catch (e) {
      _log.error('KEY_ROTATION_BROADCAST processing failed: $e');
    }
  }

  /// Emergency full key rotation (§26.6.2): dual-signature verification,
  /// ALL keys updated, Node-ID re-keyed across contacts/groups/channels.
  void _handleEmergencyKeyRotation(
    Uint8List senderUserId,
    ContactInfo contact,
    String senderHex,
    proto.KeyRotationBroadcast broadcast,
  ) {
    final sodium = SodiumFFI();

    // The data that was signed = broadcast without signature fields
    final dataToVerify = (proto.KeyRotationBroadcast()
          ..newEd25519Pk = broadcast.newEd25519Pk
          ..newMlDsaPk = broadcast.newMlDsaPk
          ..newX25519Pk = broadcast.newX25519Pk
          ..newMlKemPk = broadcast.newMlKemPk)
        .writeToBuffer();

    // 1. Verify old signature: proves sender IS our known contact
    if (contact.ed25519Pk == null) {
      _log.warn('KEY_ROTATION_BROADCAST: no Ed25519 key for ${senderHex.substring(0, 8)}');
      return;
    }
    if (!sodium.verifyEd25519(
      dataToVerify,
      Uint8List.fromList(broadcast.oldSignatureEd25519),
      contact.ed25519Pk!,
    )) {
      _log.warn('KEY_ROTATION_BROADCAST: old signature INVALID from ${senderHex.substring(0, 8)}');
      return;
    }

    // 2. Verify new signature: proves sender controls new key
    final newEd25519Pk = Uint8List.fromList(broadcast.newEd25519Pk);
    if (!sodium.verifyEd25519(
      dataToVerify,
      Uint8List.fromList(broadcast.newSignatureEd25519),
      newEd25519Pk,
    )) {
      _log.warn('KEY_ROTATION_BROADCAST: new signature INVALID from ${senderHex.substring(0, 8)}');
      return;
    }

    // Both signatures valid — update ALL contact keys
    final newMlDsaPk = Uint8List.fromList(broadcast.newMlDsaPk);
    final newX25519Pk = Uint8List.fromList(broadcast.newX25519Pk);
    final newMlKemPk = Uint8List.fromList(broadcast.newMlKemPk);

    // §7.5 Co-Auth verification: check Device-Sig countersigs against
    // cached AuthManifest device_sig_keys before applying new keys.
    final cachedManifest = node.identityDhtHandler.getAuthManifest(senderUserId);
    final cachedDeviceSigKeys = cachedManifest?.deviceSigKeys ?? <DeviceSigInfo>[];
    RotationCoAuthResult coAuthResult;

    if (cachedDeviceSigKeys.isEmpty) {
      coAuthResult = RotationCoAuthResult.legacy;
    } else {
      final rotHash = computeRotationHash(
        newEd25519Pk: newEd25519Pk,
        newMlDsaPk: newMlDsaPk,
        newX25519Pk: newX25519Pk,
        newMlKemPk: newMlKemPk,
        userId: senderUserId,
      );
      final tokens = broadcast.approvalTokens
          .map(RotationApprovalToken.fromProto)
          .toList();
      coAuthResult = verifyRotationCoAuth(
        tokens: tokens,
        cachedDeviceSigKeys: cachedDeviceSigKeys,
        rotationHash: rotHash,
        preRotationDeviceCount: broadcast.preRotationDeviceCount,
      );
      _log.info('§7.5 Co-Auth result for ${senderHex.substring(0, 8)}: '
          '$coAuthResult (${tokens.length} tokens, '
          '${cachedDeviceSigKeys.length} cached devices, '
          'quorum=${rotationQuorum(cachedDeviceSigKeys.length)})');
    }

    // Keys are always applied (SR-1: visibility, not prevention).
    contact.ed25519Pk = newEd25519Pk;
    contact.mlDsaPk = newMlDsaPk;
    contact.x25519Pk = newX25519Pk;
    contact.mlKemPk = newMlKemPk;

    // SR-1 (§7.4b step 6 / §8.3): route the rotation through Key-Change-
    // Detection (policy in key_change_policy.dart). The dual-sig + chain make
    // the rotation cryptographically valid, so we DO apply the new keys
    // (comms keep working, a legitimate rotation is not blocked) — but a
    // valid chain does NOT prove the rotation was authorized by the
    // legitimate owner vs. a seed-holding thief, so we never follow it
    // silently at full trust. Reset the verification level and surface a
    // key-change warning, exactly like any other identity-key change.
    final prevLevel = contact.verificationLevel;
    final keyChange = onIdentityRotation(prevLevel);
    final wasVerified = keyChange.wasVerified;
    contact.verificationLevel = keyChange.newLevel;

    // SR-2 (§7.4b step 5, stable anchor): the contact's UserID does NOT
    // change — it is pinned to the founding key (§3.1); the rotating side
    // proves continuity via the rotation chain in its Auth-Manifests
    // (§4.3 path 2). Keys are updated IN PLACE; contact entry, groups,
    // channels and conversations are untouched (verification level is reset
    // above per SR-1).
    // (The pre-SR-2 implementation recomputed the UserID here and migrated
    // contact/groups/channels/conversations to the new hex — that
    // contradicted §3.1 and wiped per-identity continuity.)
    final peer = node.routingTable.getPeer(contact.nodeId);
    if (peer != null) {
      // firstParty per §17.3: the broadcast is authenticated with the old
      // key (verified above), so the new key is first-party provenance.
      peer.ed25519PublicKey = newEd25519Pk;
      peer.x25519PublicKey = newX25519Pk;
      peer.mlKemPublicKey = newMlKemPk;
      peer.pkSource = PkSource.firstParty;
    }
    for (final group in _groups.values) {
      final member = group.members[senderHex];
      if (member != null) {
        member.ed25519Pk = newEd25519Pk;
        member.x25519Pk = newX25519Pk;
        member.mlKemPk = newMlKemPk;
      }
    }
    _saveGroups();
    for (final channel in _channels.values) {
      final member = channel.members[senderHex];
      if (member != null) {
        member.ed25519Pk = newEd25519Pk;
        member.x25519Pk = newX25519Pk;
        member.mlKemPk = newMlKemPk;
      }
    }
    _saveChannels();

    _saveContacts();

    // §26.6.2 Send KEY_ROTATION_ACK back to the rotator — same UserID as
    // before (stable anchor). Pure ACK — empty payload. V3 inner User-Sig +
    // outer Device-Sig + KEM-decap chain provides Paket-C-F2 forge defence.
    unawaited(sendToUser(
      recipientUserId: senderUserId,
      messageType: proto.MessageTypeV3.MTV3_KEY_ROTATION_ACK,
      payload: Uint8List(0),
    ));

    _log.info('Emergency key rotation from ${contact.displayName}: '
        'all keys updated in place, UserID ${senderHex.substring(0, 8)} '
        'unchanged (stable anchor); verification reset '
        '$prevLevel→${contact.verificationLevel} (SR-1 visibility), '
        'coAuth=$coAuthResult');
    // SR-1: surface the key-change warning to the UI so a soft re-key is
    // never followed silently. Fired for every accepted rotation; the UI
    // decides how loudly to warn based on `wasVerified`.
    try {
      onContactIdentityRotated?.call(
          senderHex, contact.displayName, wasVerified);
    } catch (e) {
      _log.warn('onContactIdentityRotated listener threw: $e');
    }
    // §7.5: escalated warning when co-auth quorum is NOT met on a
    // multi-device identity (possible Primary theft).
    if (coAuthResult == RotationCoAuthResult.quorumNotMet) {
      final tokens = broadcast.approvalTokens.length;
      final required = rotationQuorum(cachedDeviceSigKeys.length);
      try {
        onRotationCoAuthWarning?.call(
            senderHex, contact.displayName, tokens, required);
      } catch (e) {
        _log.warn('onRotationCoAuthWarning listener threw: $e');
      }
    }
    onStateChanged?.call();
  }

  /// V3 handler for MTV3_KEY_ROTATION_ACK (§26.6.2). Pure ACK — frame.payload
  /// is empty. Auth is the §23.3 inner User-Sig + outer Device-Sig + KEM-
  /// decap chain (verified upstream by the V3 receive pipeline), providing
  /// Paket-C-F2 forge defence.
  void _handleKeyRotationAckV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    if (!_contacts.containsKey(senderHex)) {
      _log.warn('KEY_ROTATION_ACK V3 from unknown sender ${senderHex.substring(0, 8)} — dropped');
      return;
    }
    _keyRotationRetry.markAcked(senderHex);
    final acked = _keyRotationRetry.ackedCount;
    final pending = _keyRotationRetry.pendingCount;
    final expired = _keyRotationRetry.expiredCount;
    _log.info('KEY_ROTATION_ACK V3 from ${senderHex.substring(0, 8)} '
        '(acked=$acked pending=$pending expired=$expired)');
    if (pending == 0 && acked > 0) {
      _log.info('All still-reachable contacts acknowledged key rotation');
    }
    _emitKeyRotationRetryEvents();
  }

  /// §7.5: handle ROTATION_REJECTION_ALERT from a Linked Device of a contact.
  void _handleRotationRejectionAlertV3(proto.ApplicationFrameV3 frame,
      Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final alert = proto.RotationRejectionAlertPayload.fromBuffer(frame.payload);
      final userIdHex = bytesToHex(Uint8List.fromList(alert.userId));
      final contact = _contacts[userIdHex];
      if (contact == null) {
        _log.warn('ROTATION_REJECTION_ALERT for unknown user $userIdHex — dropped');
        return;
      }
      _log.warn('§7.5 ROTATION_REJECTION_ALERT: a linked device of '
          '${contact.displayName} actively rejected a key rotation — '
          'possible Primary theft!');
      try {
        onRotationRejectionAlert?.call(userIdHex, contact.displayName);
      } catch (e) {
        _log.warn('onRotationRejectionAlert listener threw: $e');
      }
    } catch (e) {
      _log.error('ROTATION_REJECTION_ALERT processing failed: $e');
    }
  }

  /// §26.6.2 Paket C: called from the 24h retry timer (and once at daemon
  /// start). Re-sends the stored dual-signed broadcast to every pending
  /// contact whose last attempt is older than the retry interval. Expired
  /// contacts (too many attempts or past the 90d window) are surfaced via
  /// `key_rotation_pending_contact` IPC events so the UI can warn.
  void _retryPendingKeyRotations() {
    if (!_keyRotationRetry.hasActiveRotation) {
      // Still drain notifications — contacts may have expired on a prior tick
      // before the UI had a chance to listen.
      _emitKeyRotationRetryEvents();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = _keyRotationRetry.duePending(now: now);
    // Welle 6 §7.4: Emergency KEY_ROTATION_BROADCAST migrates to the
    // InfrastructureFrame path. Per-device fan-out via the IdentityResolver
    // — the Outer Device-Sig signs under the post-rotation Device-Sig-Keys
    // (rotation-stable per §3.5b), and the dual-sig in the inner body is
    // the only authentication subject the receiver checks against.
    // Note: the legacy `oldUserIdHex` from `due` is no longer wired into the
    // wire (the InfraFrame envelope has no senderUserId field), but the
    // receiver looks up the contact-record by ed25519Pk-derived old keys
    // already cached locally — so the F1 correlation still works.

    for (final hex in due.contacts) {
      final contact = _contacts[hex];
      if (contact == null || contact.status != 'accepted') {
        // Contact removed / invalid — just count it as an attempt so it will
        // eventually expire instead of being retried every tick forever.
        _keyRotationRetry.markAttempt(hex, now: now);
        continue;
      }
      // Resolve the recipient's authorized device-set on each retry. The
      // 2D-DHT may have grown new devices since the last attempt, and the
      // local DeviceKemRecord cache may have warmed up — both are normal
      // catch-up patterns for an offline contact coming back online.
      unawaited(_retryKeyRotationToContact(hex, contact, due.broadcastBytes,
          now: now));
    }

    _emitKeyRotationRetryEvents();
  }

  Future<void> _retryKeyRotationToContact(
    String hex,
    ContactInfo contact,
    Uint8List broadcastBytes, {
    required int now,
  }) async {
    try {
      final resolved = await node.identityResolver.resolve(contact.nodeId);
      if (resolved.isEmpty) {
        _log.debug('KEY_ROTATION_BROADCAST retry: no devices resolved for '
            '${hex.substring(0, 8)} (${contact.displayName}) — '
            'will retry on next tick');
        _keyRotationRetry.markAttempt(hex, now: now);
        return;
      }
      var anyOk = false;
      for (final dev in resolved) {
        final ok = await node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST,
          innerPayload: broadcastBytes,
          recipientDeviceId: dev.deviceNodeId,
        );
        anyOk = anyOk || ok;
      }
      _keyRotationRetry.markAttempt(hex, now: now);
      if (anyOk) {
        _log.info('KEY_ROTATION_BROADCAST retry (InfraFrame) to '
            '${hex.substring(0, 8)} (${contact.displayName}) — '
            '${resolved.length} device(s)');
      } else {
        _log.debug('KEY_ROTATION_BROADCAST retry: all ${resolved.length} '
            'device(s) sends failed for ${hex.substring(0, 8)} — '
            'will retry on next tick');
      }
    } catch (e) {
      _log.warn('Retry KEY_ROTATION_BROADCAST to '
          '${hex.substring(0, 8)} failed: $e');
      // Still count attempt so we do not loop forever on permanent failure.
      _keyRotationRetry.markAttempt(hex, now: now);
    }
  }

  /// Drain new `expired` transitions into IPC events. Idempotent — if there
  /// is nothing to report this is a no-op.
  void _emitKeyRotationRetryEvents() {
    final newlyExpired = _keyRotationRetry.drainNewlyExpired();
    if (newlyExpired.isEmpty) return;
    final listener = onKeyRotationPendingExpired;
    if (listener == null) return;
    for (final hex in newlyExpired) {
      try {
        listener(hex, _keyRotationRetry.pendingCount);
      } catch (e) {
        _log.warn('onKeyRotationPendingExpired listener threw: $e');
      }
    }
  }

  // ── Calendar (§23) ──────────────────────────────────────────────────

  /// Send an encrypted payload to a single contact (V3 sendToUser path).
  /// `messageType` is already a V3 `MessageTypeV3` — KEM/Sig/zstd are
  /// handled inside `sendToUser`. Used by the Calendar/Polls/Free-Busy
  /// cluster.
  Future<void> _sendEncryptedPayload(
    Uint8List recipientUserId,
    proto.MessageTypeV3 messageType,
    Uint8List payload, {
    Uint8List? groupId,
  }) async {
    final recipientHex = bytesToHex(recipientUserId);
    final contact = _contacts[recipientHex];
    if (contact == null || contact.x25519Pk == null || contact.mlKemPk == null) {
      _log.warn('Cannot send $messageType to $recipientHex: missing keys');
      return;
    }
    await sendToUser(
      recipientUserId: recipientUserId,
      messageType: messageType,
      payload: payload,
      groupId: groupId,
    );
    node.statsCollector.addMessageSent();
  }

  // ── Calendar (§23) — forwarded to CalendarProtocolService ─────────

  @override
  Future<String> createCalendarEvent(CalendarEvent event) =>
      _calendarProto.createCalendarEvent(event);
  @override
  Future<bool> updateCalendarEvent(String eventIdHex, {
    String? title, String? description, String? location,
    int? startTime, int? endTime, bool? allDay, bool? hasCall,
    List<int>? reminders, String? recurrenceRule,
    bool? taskCompleted, int? taskPriority, bool? cancelled,
  }) => _calendarProto.updateCalendarEvent(eventIdHex,
    title: title, description: description, location: location,
    startTime: startTime, endTime: endTime, allDay: allDay,
    hasCall: hasCall, reminders: reminders, recurrenceRule: recurrenceRule,
    taskCompleted: taskCompleted, taskPriority: taskPriority, cancelled: cancelled);
  @override
  Future<bool> deleteCalendarEvent(String eventIdHex) =>
      _calendarProto.deleteCalendarEvent(eventIdHex);
  @override
  Future<void> sendCalendarInvite(CalendarEvent event) =>
      _calendarProto.sendCalendarInvite(event);
  @override
  Future<void> sendCalendarRsvp(String eventIdHex, RsvpStatus status, {
    int? proposedStart, int? proposedEnd, String? comment,
  }) => _calendarProto.sendCalendarRsvp(eventIdHex, status,
    proposedStart: proposedStart, proposedEnd: proposedEnd, comment: comment);
  @override
  Future<void> sendCalendarUpdate(String eventIdHex) =>
      _calendarProto.sendCalendarUpdate(eventIdHex);
  @override
  Future<void> sendCalendarDelete(String eventIdHex) =>
      _calendarProto.sendCalendarDelete(eventIdHex);
  @override
  Future<String> sendFreeBusyRequest(String contactNodeIdHex, int queryStart, int queryEnd) =>
      _calendarProto.sendFreeBusyRequest(contactNodeIdHex, queryStart, queryEnd);

  // ── Polls (§24) — forwarded to PollService ────────────────────────

  @override
  Future<String> createPoll({
    required String question,
    String description = '',
    required PollType pollType,
    required List<PollOption> options,
    required PollSettings settings,
    required String groupIdHex,
  }) => _polls.createPoll(
    question: question, description: description, pollType: pollType,
    options: options, settings: settings, groupIdHex: groupIdHex);

  @override
  Future<bool> submitPollVote({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  }) => _polls.submitPollVote(
    pollId: pollId, selectedOptions: selectedOptions,
    dateResponses: dateResponses, scaleValue: scaleValue, freeText: freeText);

  @override
  Future<bool> submitPollVoteAnonymous({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  }) => _polls.submitPollVoteAnonymous(
    pollId: pollId, selectedOptions: selectedOptions,
    dateResponses: dateResponses, scaleValue: scaleValue, freeText: freeText);

  @override
  Future<bool> revokePollVoteAnonymous(String pollId) =>
      _polls.revokePollVoteAnonymous(pollId);

  void handleIncomingPollAnonSubmit(
    proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId,
    InternetAddress from, int port, SenderIdentitySnapshot snapshot,
  ) => _polls.handleIncomingPollAnonSubmit(frame, senderDeviceId, from, port, snapshot);

  void handleIncomingPollAnonSubmitAck(
    proto.InfrastructureFrameV3 frame, Uint8List senderDeviceId,
  ) => _polls.handleIncomingPollAnonSubmitAck(frame, senderDeviceId);

  @override
  Future<bool> updatePoll(String pollId, {
    bool? close,
    bool? reopen,
    List<PollOption>? addOptions,
    List<int>? removeOptions,
    int? newDeadline,
    bool delete = false,
  }) => _polls.updatePoll(pollId,
    close: close, reopen: reopen, addOptions: addOptions,
    removeOptions: removeOptions, newDeadline: newDeadline, delete: delete);

  @override
  Future<String?> convertDatePollToEvent(String pollId, int winningOptionId) async {
    if (_reducedMode) {
      _log.warn('convertDatePollToEvent blocked: reducedMode active');
      return null;
    }
    final poll = pollManager.polls[pollId];
    if (poll == null || poll.pollType != PollType.datePoll) return null;
    final option = poll.options.firstWhere(
      (o) => o.optionId == winningOptionId,
      orElse: () => PollOption(optionId: -1, label: ''),
    );
    if (option.optionId == -1 || option.dateStart == null || option.dateEnd == null) {
      return null;
    }
    final event = CalendarEvent(
      eventId: PollManager.generateUuid(),
      identityId: identity.userIdHex,
      title: poll.question,
      startTime: option.dateStart!,
      endTime: option.dateEnd!,
      category: EventCategory.meeting,
      groupId: _groups.containsKey(poll.groupId) ? poll.groupId : null,
      createdBy: identity.userIdHex,
    );
    await createCalendarEvent(event);
    return event.eventId;
  }

  // ── Recovery / Restore ──────────────────────────────────────────────

  /// Handle incoming RESTORE_BROADCAST from a former contact trying to recover.
  /// We check if the sender's old_node_id matches one of our contacts,
  /// verify the signature with the old key, then send back our contact list
  /// and recent messages progressively.
  /// RESTORE_BROADCAST handler (Architecture §6.3 + §23.3 InfraFrame).
  /// [payload] is the plain `RestoreBroadcast` proto (NOT KEM-encrypted —
  /// the recovering peer's user-keys just changed, so the recipient cannot
  /// run the standard inner User-Sig path; the inner old-Ed25519 sig in
  /// the body is the canonical authenticity check). Sender lookup keys
  /// off `rb.oldNodeId` so no separate sender argument is needed.
  void _handleRestoreBroadcast(Uint8List payload) {
    try {
      // RestoreBroadcast is NOT encrypted (sender has new keys, we don't know them yet)
      // but it IS signed with the OLD key to prove ownership
      final rb = proto.RestoreBroadcast.fromBuffer(payload);
      final oldNodeIdHex = bytesToHex(Uint8List.fromList(rb.oldNodeId));
      final newNodeIdHex = bytesToHex(Uint8List.fromList(rb.newNodeId));

      // Check: is old_node_id one of our accepted contacts?
      final contact = _contacts[oldNodeIdHex];
      if (contact == null || contact.status != 'accepted') {
        _log.debug('RESTORE_BROADCAST from unknown node ${oldNodeIdHex.substring(0, 8)}, ignoring');
        return;
      }

      // H-2: verify the inner restore proof against the contact's STORED
      // keys (before we apply the broadcast's new keys). The canonical
      // bytes are the body with both signature fields empty.
      if (contact.ed25519Pk != null) {
        final dataToVerify = (proto.RestoreBroadcast()
              ..oldNodeId = rb.oldNodeId
              ..newNodeId = rb.newNodeId
              ..newEd25519Pk = rb.newEd25519Pk
              ..newX25519Pk = rb.newX25519Pk
              ..newMlKemPk = rb.newMlKemPk
              ..newMlDsaPk = rb.newMlDsaPk
              ..displayName = rb.displayName
              ..timestamp = rb.timestamp)
            .writeToBuffer();
        final edValid = SodiumFFI().verifyEd25519(
          dataToVerify,
          Uint8List.fromList(rb.signature),
          contact.ed25519Pk!,
        );
        if (!edValid) {
          _log.warn('RESTORE_BROADCAST Ed25519 signature invalid from ${oldNodeIdHex.substring(0, 8)}');
          return;
        }
        // H-2 hybrid: when the sender supplied an ML-DSA signature AND we
        // hold the contact's ML-DSA key, the PQ proof MUST verify too — a
        // classical-only forge is rejected. A missing `signature_ml_dsa`
        // (pre-H-2 sender) is accepted as legacy-classical during the
        // transition; a present-but-invalid one is a forge and rejected.
        if (rb.signatureMlDsa.isNotEmpty) {
          if (contact.mlDsaPk == null) {
            _log.warn('RESTORE_BROADCAST carries ML-DSA sig but no stored '
                'mlDsaPk for ${oldNodeIdHex.substring(0, 8)} — accepting '
                'classical proof (legacy transition)');
          } else {
            final pqValid = OqsFFI().mlDsaVerify(
              dataToVerify,
              Uint8List.fromList(rb.signatureMlDsa),
              contact.mlDsaPk!,
            );
            if (!pqValid) {
              _log.warn('RESTORE_BROADCAST ML-DSA signature INVALID from '
                  '${oldNodeIdHex.substring(0, 8)} — rejected (H-2 forge defence)');
              return;
            }
          }
        } else {
          _log.info('RESTORE_BROADCAST from ${oldNodeIdHex.substring(0, 8)} '
              'is Ed25519-only (legacy-classical, pre-H-2 sender)');
        }
      }

      _log.info('Valid RESTORE_BROADCAST from ${contact.displayName} (old: ${oldNodeIdHex.substring(0, 8)}, new: ${newNodeIdHex.substring(0, 8)})');

      // H-2 Part B: detect whether this restore actually CHANGES the
      // contact's identity key (new-seed re-identity or forge attempt) vs.
      // a deterministic same-seed recovery where the keys are unchanged.
      // Captured before the overwrite below.
      final identityKeyChanged = contact.ed25519Pk == null ||
          !_bytesEqual(contact.ed25519Pk!,
              Uint8List.fromList(rb.newEd25519Pk));
      final prevVerification = contact.verificationLevel;

      // Update contact with new keys and node ID
      _contacts.remove(oldNodeIdHex);
      contact.nodeId = Uint8List.fromList(rb.newNodeId);
      contact.ed25519Pk = Uint8List.fromList(rb.newEd25519Pk);
      contact.x25519Pk = Uint8List.fromList(rb.newX25519Pk);
      contact.mlKemPk = Uint8List.fromList(rb.newMlKemPk);
      contact.mlDsaPk = Uint8List.fromList(rb.newMlDsaPk);
      if (rb.displayName.isNotEmpty) contact.displayName = rb.displayName;
      // H-2 Part B (§8.3, SR-1-consistent): if the restore changed the
      // contact's identity key, run Key-Change-Detection — reset the
      // verification level so a re-identity / forge is never followed
      // silently at full trust. A deterministic same-seed recovery leaves
      // the key unchanged and keeps the verification level.
      if (identityKeyChanged) {
        contact.verificationLevel =
            onIdentityRotation(contact.verificationLevel).newLevel;
      }
      _contacts[newNodeIdHex] = contact;
      _saveContacts();

      // Update group/channel memberships
      for (final group in _groups.values) {
        final member = group.members.remove(oldNodeIdHex);
        if (member != null) {
          group.members[newNodeIdHex] = GroupMemberInfo(
            nodeIdHex: newNodeIdHex,
            displayName: contact.displayName,
            role: member.role,
            ed25519Pk: contact.ed25519Pk,
            x25519Pk: contact.x25519Pk,
            mlKemPk: contact.mlKemPk,
          );
        }
        if (group.ownerNodeIdHex == oldNodeIdHex) {
          group.ownerNodeIdHex = newNodeIdHex;
        }
      }
      _saveGroups();

      for (final channel in _channels.values) {
        final member = channel.members.remove(oldNodeIdHex);
        if (member != null) {
          channel.members[newNodeIdHex] = ChannelMemberInfo(
            nodeIdHex: newNodeIdHex,
            displayName: contact.displayName,
            role: member.role,
            ed25519Pk: contact.ed25519Pk,
            x25519Pk: contact.x25519Pk,
            mlKemPk: contact.mlKemPk,
          );
        }
        if (channel.ownerNodeIdHex == oldNodeIdHex) {
          channel.ownerNodeIdHex = newNodeIdHex;
        }
      }
      _saveChannels();

      // Migrate conversation from old to new node ID
      final oldConv = conversations.remove(oldNodeIdHex);
      if (oldConv != null) {
        conversations[newNodeIdHex] = Conversation(
          id: newNodeIdHex,
          displayName: contact.displayName,
          messages: oldConv.messages,
          unreadCount: oldConv.unreadCount,
          lastActivity: oldConv.lastActivity,
          profilePictureBase64: oldConv.profilePictureBase64,
          config: oldConv.config,
          isFavorite: oldConv.isFavorite,
        );
        _saveConversations();
      }

      // Send RestoreResponse Phase 1: contact list
      _sendRestoreResponse(contact, 1);

      // Phase 2: recent messages (after short delay)
      Timer(const Duration(seconds: 2), () {
        _sendRestoreResponse(contact, 2);
      });

      // Phase 3: full history (after longer delay, in background)
      Timer(const Duration(seconds: 10), () {
        _sendRestoreResponse(contact, 3);
      });

      // H-2 Part B (§6.3.5): surface the restore to the UI. Fired for EVERY
      // accepted restore (the §6.3.5 "[Name] has set up a new device"
      // notification, now real). `identityKeyChanged` tells the UI whether
      // to escalate to a key-change warning (verification was reset above).
      _log.info('RESTORE_BROADCAST visibility: ${contact.displayName} '
          'keyChanged=$identityKeyChanged verification '
          '$prevVerification→${contact.verificationLevel}');
      try {
        onContactRestoreDetected?.call(
            newNodeIdHex, contact.displayName, identityKeyChanged);
      } catch (e) {
        _log.warn('onContactRestoreDetected listener threw: $e');
      }

      onStateChanged?.call();
    } catch (e) {
      _log.error('RESTORE_BROADCAST processing failed: $e');
    }
  }

  /// Send RestoreResponse to a recovering contact.
  Future<void> _sendRestoreResponse(ContactInfo recipient, int phase) async {
    if (recipient.x25519Pk == null || recipient.mlKemPk == null) return;

    final response = proto.RestoreResponse()..phase = phase;

    if (phase == 1) {
      // Phase 1: Send our contact list (contacts the recovering node might want to re-add)
      for (final c in _contacts.values) {
        if (c.status != 'accepted') continue;
        final entry = proto.ContactEntry()
          ..nodeId = c.nodeId
          ..displayName = c.displayName;
        if (c.ed25519Pk != null) entry.ed25519Pk = c.ed25519Pk!;
        if (c.x25519Pk != null) entry.x25519Pk = c.x25519Pk!;
        if (c.mlKemPk != null) entry.mlKemPk = c.mlKemPk!;
        if (c.mlDsaPk != null) entry.mlDsaPk = c.mlDsaPk!;
        if (c.profilePictureBase64 != null) {
          entry.profilePicture = base64Decode(c.profilePictureBase64!);
        }
        response.contacts.add(entry);
      }

      // Also add ourselves as a contact entry
      final selfEntry = proto.ContactEntry()
        ..nodeId = identity.nodeId
        ..displayName = displayName
        ..ed25519Pk = identity.ed25519PublicKey
        ..x25519Pk = identity.x25519PublicKey
        ..mlKemPk = identity.mlKemPublicKey
        ..mlDsaPk = identity.mlDsaPublicKey;
      if (_profilePictureBase64 != null) {
        selfEntry.profilePicture = base64Decode(_profilePictureBase64!);
      }
      response.contacts.add(selfEntry);

      // Add group structures + member contacts
      for (final group in _groups.values) {
        if (!group.members.containsKey(recipient.nodeIdHex)) continue;

        // Add group structure
        final groupInfo = proto.RestoreGroupInfo()
          ..groupId = hexToBytes(group.groupIdHex)
          ..name = group.name
          ..ownerNodeIdHex = group.ownerNodeIdHex;
        if (group.description != null) groupInfo.description = group.description!;

        for (final member in group.members.values) {
          final gm = proto.RestoreGroupMember()
            ..nodeIdHex = member.nodeIdHex
            ..displayName = member.displayName
            ..role = member.role;
          if (member.ed25519Pk != null) gm.ed25519Pk = member.ed25519Pk!;
          if (member.x25519Pk != null) gm.x25519Pk = member.x25519Pk!;
          if (member.mlKemPk != null) gm.mlKemPk = member.mlKemPk!;
          groupInfo.members.add(gm);

          // Also add member as contact (dedup)
          if (!response.contacts.any((c) => bytesToHex(Uint8List.fromList(c.nodeId)) == member.nodeIdHex)) {
            final entry = proto.ContactEntry()
              ..nodeId = hexToBytes(member.nodeIdHex)
              ..displayName = member.displayName;
            if (member.ed25519Pk != null) entry.ed25519Pk = member.ed25519Pk!;
            if (member.x25519Pk != null) entry.x25519Pk = member.x25519Pk!;
            if (member.mlKemPk != null) entry.mlKemPk = member.mlKemPk!;
            response.contacts.add(entry);
          }
        }
        response.groups.add(groupInfo);
      }

      // Add channel structures + subscriber contacts
      for (final channel in _channels.values) {
        if (!channel.members.containsKey(recipient.nodeIdHex)) continue;

        final channelInfo = proto.RestoreChannelInfo()
          ..channelId = hexToBytes(channel.channelIdHex)
          ..name = channel.name
          ..ownerNodeIdHex = channel.ownerNodeIdHex;
        if (channel.description != null) channelInfo.description = channel.description!;

        for (final member in channel.members.values) {
          final cm = proto.RestoreChannelMember()
            ..nodeIdHex = member.nodeIdHex
            ..displayName = member.displayName
            ..role = member.role;
          if (member.ed25519Pk != null) cm.ed25519Pk = member.ed25519Pk!;
          if (member.x25519Pk != null) cm.x25519Pk = member.x25519Pk!;
          if (member.mlKemPk != null) cm.mlKemPk = member.mlKemPk!;
          channelInfo.members.add(cm);

          if (!response.contacts.any((c) => bytesToHex(Uint8List.fromList(c.nodeId)) == member.nodeIdHex)) {
            final entry = proto.ContactEntry()
              ..nodeId = hexToBytes(member.nodeIdHex)
              ..displayName = member.displayName;
            if (member.ed25519Pk != null) entry.ed25519Pk = member.ed25519Pk!;
            if (member.x25519Pk != null) entry.x25519Pk = member.x25519Pk!;
            if (member.mlKemPk != null) entry.mlKemPk = member.mlKemPk!;
            response.contacts.add(entry);
          }
        }
        response.channels.add(channelInfo);
      }
    } else if (phase == 2 || phase == 3) {
      // Phase 2: Last 50 messages from our DM conversation
      // Phase 3: ALL messages from ALL conversations (full history)
      final convIds = phase == 3
          ? conversations.keys.toList()
          : [recipient.nodeIdHex];
      final maxMessages = phase == 3 ? null : 50;

      for (final convId in convIds) {
        final conv = conversations[convId];
        if (conv == null) continue;

        final msgs = (maxMessages != null && conv.messages.length > maxMessages)
            ? conv.messages.sublist(conv.messages.length - maxMessages)
            : conv.messages;

        for (final msg in msgs) {
          if (msg.isDeleted) continue;
          response.messages.add(proto.StoredMessage()
            ..messageId = hexToBytes(msg.id)
            ..senderId = hexToBytes(msg.senderNodeIdHex)
            ..recipientId = identity.nodeId
            ..conversationId = convId
            ..timestamp = Int64(msg.timestamp.millisecondsSinceEpoch)
            ..uiMessageType = msg.type.wireValue
            ..payload = utf8.encode(msg.text));
        }
      }
    }

    // V3 (Architecture §23.3 + §6.3): RESTORE_RESPONSE rides as an
    // ApplicationFrameV3 via sendToUser. The codec handles per-message KEM
    // (X25519 + ML-KEM-768) on the inner frame, so we hand it the raw
    // RestoreResponse protobuf as payload (no pre-encryption). Receiver-
    // side `_handleRestoreResponseV3` is wired by Cluster C4.
    //
    // Spec-note: RESTORE flow uses recipient.nodeId from the old contact
    // list and `recipient.x25519Pk`/`mlKemPk` are pre-rotation. sendToUser
    // resolves recipient → devices via 2D-DHT and uses the KEM pubkeys on
    // the contact record — best-effort. If the recipient already rotated,
    // the resolve may return new device-IDs whose decap-SK doesn't match
    // the contact-cached User-KEM-PK, and the receiver silently drops.
    // That matches §2.4.1 [10'] semantics; the broadcaster's retry on
    // RESTORE_BROADCAST will eventually reach a freshly-keyed device.
    final ok = await sendToUser(
      recipientUserId: recipient.nodeId,
      messageType: proto.MessageTypeV3.MTV3_RESTORE_RESPONSE,
      payload: Uint8List.fromList(response.writeToBuffer()),
    );

    _log.info('Sent RestoreResponse phase $phase to ${recipient.displayName} '
        '(${phase == 1 ? '${response.contacts.length} contacts' : '${response.messages.length} messages'}) ok=$ok');
  }

  /// Handle incoming RESTORE_RESPONSE: restore contacts and messages.
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// RestoreResponse proto bytes (KEM-decap + inner User-Sig + outer
  /// Device-Sig already verified by the V3 receive pipeline).
  /// [senderUserId] is the recovering peer's user-id from the inbound
  /// ApplicationFrame.
  void _handleRestoreResponse(Uint8List payload, Uint8List senderUserId, Uint8List senderDeviceId) {
    try {
      final response = proto.RestoreResponse.fromBuffer(payload);
      final senderHex = bytesToHex(senderUserId);
      var contactsRestored = 0;
      var messagesRestored = 0;

      if (response.phase == 1) {
        // Phase 1: Restore contacts
        for (final entry in response.contacts) {
          final nodeIdHex = bytesToHex(Uint8List.fromList(entry.nodeId));
          if (nodeIdHex == identity.userIdHex) continue; // Skip self
          if (_contacts.containsKey(nodeIdHex)) continue; // Already known
          if (_deletedContacts.contains(nodeIdHex)) continue; // Explicitly deleted

          _contacts[nodeIdHex] = ContactInfo(
            nodeId: Uint8List.fromList(entry.nodeId),
            displayName: entry.displayName,
            ed25519Pk: entry.ed25519Pk.isNotEmpty ? Uint8List.fromList(entry.ed25519Pk) : null,
            x25519Pk: entry.x25519Pk.isNotEmpty ? Uint8List.fromList(entry.x25519Pk) : null,
            mlKemPk: entry.mlKemPk.isNotEmpty ? Uint8List.fromList(entry.mlKemPk) : null,
            mlDsaPk: entry.mlDsaPk.isNotEmpty ? Uint8List.fromList(entry.mlDsaPk) : null,
            status: 'accepted',
            profilePictureBase64: entry.profilePicture.isNotEmpty
                ? base64Encode(entry.profilePicture)
                : null,
            acceptedAt: DateTime.now(),
          );
          contactsRestored++;
        }
        // §3.1 A-5: the A-2 central fix ran before this handler but
        // _contacts was still empty at that point. Now that contacts are
        // restored, record the sender's deviceNodeId.
        final senderContact = _contacts[senderHex];
        if (senderContact != null) {
          senderContact.deviceNodeIds.add(bytesToHex(senderDeviceId));
        }
        if (contactsRestored > 0) _saveContacts();

        // Restore groups
        var groupsRestored = 0;
        for (final gi in response.groups) {
          final groupIdHex = bytesToHex(Uint8List.fromList(gi.groupId));
          if (_groups.containsKey(groupIdHex)) continue;

          final members = <String, GroupMemberInfo>{};
          for (final gm in gi.members) {
            members[gm.nodeIdHex] = GroupMemberInfo(
              nodeIdHex: gm.nodeIdHex,
              displayName: gm.displayName,
              role: gm.role,
              ed25519Pk: gm.ed25519Pk.isNotEmpty ? Uint8List.fromList(gm.ed25519Pk) : null,
              x25519Pk: gm.x25519Pk.isNotEmpty ? Uint8List.fromList(gm.x25519Pk) : null,
              mlKemPk: gm.mlKemPk.isNotEmpty ? Uint8List.fromList(gm.mlKemPk) : null,
            );
          }

          _groups[groupIdHex] = GroupInfo(
            groupIdHex: groupIdHex,
            name: gi.name,
            description: gi.description.isNotEmpty ? gi.description : null,
            ownerNodeIdHex: gi.ownerNodeIdHex,
            members: members,
          );
          groupsRestored++;
        }
        if (groupsRestored > 0) _saveGroups();

        // Restore channels
        var channelsRestored = 0;
        for (final ci in response.channels) {
          final channelIdHex = bytesToHex(Uint8List.fromList(ci.channelId));
          if (_channels.containsKey(channelIdHex)) continue;

          final members = <String, ChannelMemberInfo>{};
          for (final cm in ci.members) {
            members[cm.nodeIdHex] = ChannelMemberInfo(
              nodeIdHex: cm.nodeIdHex,
              displayName: cm.displayName,
              role: cm.role,
              ed25519Pk: cm.ed25519Pk.isNotEmpty ? Uint8List.fromList(cm.ed25519Pk) : null,
              x25519Pk: cm.x25519Pk.isNotEmpty ? Uint8List.fromList(cm.x25519Pk) : null,
              mlKemPk: cm.mlKemPk.isNotEmpty ? Uint8List.fromList(cm.mlKemPk) : null,
            );
          }

          _channels[channelIdHex] = ChannelInfo(
            channelIdHex: channelIdHex,
            name: ci.name,
            description: ci.description.isNotEmpty ? ci.description : null,
            ownerNodeIdHex: ci.ownerNodeIdHex,
            members: members,
          );
          channelsRestored++;
        }
        if (channelsRestored > 0) _saveChannels();

        _log.info('Restore Phase 1: $contactsRestored contacts, $groupsRestored groups, $channelsRestored channels from ${senderHex.substring(0, 8)}');
      } else if (response.phase == 2) {
        // Phase 2: Restore recent messages
        for (final stored in response.messages) {
          final msgId = bytesToHex(Uint8List.fromList(stored.messageId));
          final convId = stored.conversationId;
          final senderIdHex = bytesToHex(Uint8List.fromList(stored.senderId));

          // Skip if already have this message
          final conv = conversations[convId];
          if (conv != null && conv.messages.any((m) => m.id == msgId)) continue;

          final isOutgoing = senderIdHex == identity.userIdHex;
          final text = utf8.decode(stored.payload, allowMalformed: true);
          if (text.isEmpty) continue;

          final msg = UiMessage(
            id: msgId,
            conversationId: convId,
            senderNodeIdHex: senderIdHex,
            text: text,
            timestamp: DateTime.fromMillisecondsSinceEpoch(stored.timestamp.toInt()),
            type: UiMessageType.text,
            status: MessageStatus.delivered,
            isOutgoing: isOutgoing,
          );

          _addMessageToConversation(convId, msg);
          messagesRestored++;
        }
        if (messagesRestored > 0) _saveConversations();
        _log.info('Restore Phase 2: $messagesRestored messages from ${senderHex.substring(0, 8)}');
      }

      onRestoreProgress?.call(response.phase, contactsRestored, messagesRestored);
      onStateChanged?.call();
    } on KemVersionRejectedException catch (e) {
      _warnKemVersionRejected('RESTORE_RESPONSE', e);
    } catch (e) {
      _log.error('RESTORE_RESPONSE processing failed: $e');
    }
  }

  /// Send a Restore Broadcast to all known contacts, requesting they re-send
  /// our contact list and recent messages.
  /// [oldEd25519Sk] is the old secret key (derived from seed) to prove ownership.
  /// [oldNodeId] is our previous node ID.
  @override
  Future<bool> sendRestoreBroadcast({
    required Uint8List oldEd25519Sk,
    required Uint8List oldEd25519Pk,
    required Uint8List oldNodeId,
    required List<ContactInfo> oldContacts,
    // H-2: old ML-DSA-65 secret key for the hybrid inner signature. In the
    // dominant deterministic same-seed recovery the re-derived key is
    // identical to the old one (§6.3.5 PQ-handling), so the caller passes
    // `identity.mlDsaSecretKey`. Null → classical-only broadcast (legacy
    // transition; receivers accept it until the Phase-2 gate).
    Uint8List? oldMlDsaSk,
  }) async {
    // Rate limiting: max 1 per 5 minutes
    if (_lastRestoreBroadcast != null &&
        DateTime.now().difference(_lastRestoreBroadcast!).inMinutes < 5) {
      _log.warn('Restore broadcast rate limited');
      return false;
    }
    _lastRestoreBroadcast = DateTime.now();

    final rb = proto.RestoreBroadcast()
      ..oldNodeId = oldNodeId
      ..newNodeId = identity.nodeId
      ..newEd25519Pk = identity.ed25519PublicKey
      ..newX25519Pk = identity.x25519PublicKey
      ..newMlKemPk = identity.mlKemPublicKey
      ..newMlDsaPk = identity.mlDsaPublicKey
      ..displayName = displayName
      ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch);

    // H-2: hybrid inner signature — sign the canonical body with BOTH the
    // old Ed25519 key (classical ownership) AND the old ML-DSA-65 key (PQ
    // ownership). A classical-only forge of the contact's Ed25519 key no
    // longer suffices to forge a restore takeover. Both signature fields are
    // empty while signing so they cover identical canonical bytes.
    final dataToSign = rb.writeToBuffer();
    rb.signature = SodiumFFI().signEd25519(dataToSign, oldEd25519Sk);
    if (oldMlDsaSk != null) {
      rb.signatureMlDsa = OqsFFI().mlDsaSign(dataToSign, oldMlDsaSk);
    }

    final broadcastBytes = rb.writeToBuffer();
    var sent = 0;

    // V3.0 Welle 6 §6.3: per-recipient-DEVICE fanout via InfrastructureFrame
    // path. The recovering peer's User-Sig-Keys just changed, so we cannot
    // sign an ApplicationFrame; the InfrastructureFrame Outer-Sig under the
    // (rotation-stable) Device-Sig-Keys carries routing-authenticity, and
    // the inner old-Ed25519-sig in the RestoreBroadcast body proves we
    // controlled the previous User-Identity. KEM-encrypt under each
    // recipient's Device-KEM-PK (§3.5b) — looked up via 2D-DHT
    // (IdentityResolver). One RestoreBroadcast InfrastructureFrame per
    // *device* of each accepted contact.
    //
    // Erasure-coded offline-delivery (§5.4 + §6.3.1 step 4): the canonical
    // NetworkPacket built for the contact's first-resolved device is
    // fragmented onto the K=10 closest DHT replicators of the contact's
    // user-mailbox. Per §5.4 InfraFrame KEM is device-PK-keyed, so the
    // encoded blob can only reach that one device; sibling devices of the
    // same contact recover via subsequent Direct-Send retries or via S&F
    // (§5.5).
    for (final contact in oldContacts) {
      if (contact.status != 'accepted') continue;

      final resolved =
          await node.identityResolver.resolve(contact.nodeId);
      if (resolved.isEmpty) {
        _log.debug('Restore broadcast: no devices resolved for '
            '${contact.nodeIdHex.substring(0, 8)} — skipping (no canonical '
            'packet possible without device-set)');
        continue;
      }

      var anyDeviceSent = false;
      proto.NetworkPacketV3? canonicalPacket;
      for (var i = 0; i < resolved.length; i++) {
        final device = resolved[i];
        final deviceId = Uint8List.fromList(device.deviceNodeId);
        if (i == 0) {
          canonicalPacket = node.buildInfraPacket(
            messageType: proto.MessageTypeV3.MTV3_RESTORE_BROADCAST,
            innerPayload: broadcastBytes,
            recipientDeviceId: deviceId,
          );
          if (canonicalPacket != null) {
            final ok = await node.sendToDevice(canonicalPacket, deviceId);
            if (ok) anyDeviceSent = true;
            _log.debug('Restore broadcast → ${contact.nodeIdHex.substring(0, 8)} '
                'device=${bytesToHex(deviceId).substring(0, 8)} ok=$ok '
                '(canonical)');
          }
        } else {
          final ok = await node.sendInfraTo(
            messageType: proto.MessageTypeV3.MTV3_RESTORE_BROADCAST,
            innerPayload: broadcastBytes,
            recipientDeviceId: deviceId,
          );
          if (ok) anyDeviceSent = true;
          _log.debug('Restore broadcast → ${contact.nodeIdHex.substring(0, 8)} '
              'device=${bytesToHex(deviceId).substring(0, 8)} ok=$ok');
        }
      }

      if (canonicalPacket != null) {
        final canonicalBytes =
            node.serializePacketForOfflineDelivery(canonicalPacket);
        final fragmentBundleId =
            SodiumFFI().sha256(canonicalBytes).sublist(0, 16);
        await _distributeErasureFragments(
          packetBytes: canonicalBytes,
          messageId: Uint8List.fromList(fragmentBundleId),
          recipientUserNodeId: contact.nodeId,
        );
      }

      if (anyDeviceSent) sent++;
    }

    _log.info('Restore broadcast sent to $sent contacts (V3 InfrastructureFrame)');

    // Aggressive mailbox polling: 10 polls à 3s to catch RestoreResponses quickly
    _startAggressivePolling();

    // Schedule retry after 30 seconds
    _restoreRetryTimer?.cancel();
    _restoreRetryTimer = Timer(const Duration(seconds: 30), () {
      _log.info('Retrying restore broadcast...');
      sendRestoreBroadcast(
        oldEd25519Sk: oldEd25519Sk,
        oldEd25519Pk: oldEd25519Pk,
        oldNodeId: oldNodeId,
        oldContacts: oldContacts,
        oldMlDsaSk: oldMlDsaSk,
      );
    });

    return sent > 0;
  }

  /// Aggressive mailbox polling after restore: 10 polls à 3 seconds.
  /// Kademlia bootstrap takes ~15-20s, so first meaningful responses
  /// arrive after ~20s. Polling aggressively ensures we catch them fast.
  void _startAggressivePolling() {
    _restorePollingTimer?.cancel();
    _restorePollCount = 0;
    _restorePollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _restorePollCount++;
      _pollMailbox();
      _log.info('Aggressive restore poll $_restorePollCount/10');
      if (_restorePollCount >= 10) {
        timer.cancel();
        _restorePollingTimer = null;
        _log.info('Aggressive restore polling complete');
      }
    });
  }

  // ── Voice Transcription ─────────────────────────────────────────────

  static WhisperModelSize _parseModelSize(String s) {
    switch (s) {
      case 'tiny':  return WhisperModelSize.tiny;
      case 'small': return WhisperModelSize.small;
      default:      return WhisperModelSize.base;
    }
  }

  void _onLocalTranscriptionComplete(String messageId, VoiceTranscription transcription) {
    // Find the message and update its transcript fields.
    for (final conv in conversations.values) {
      final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
      if (msg != null) {
        msg.transcriptText = transcription.text;
        msg.transcriptLanguage = transcription.language;
        msg.transcriptConfidence = transcription.confidence;
        onStateChanged?.call();
        _saveConversations();
        _log.info('Local transcription complete for $messageId: "${transcription.text.length > 40 ? '${transcription.text.substring(0, 40)}...' : transcription.text}"');
        return;
      }
    }
  }

  // ── Shutdown ───────────────────────────────────────────────────────

  @override
  Future<void> stop() async {
    _saveConversationsTimer?.cancel();
    _saveConversationsTimer = null;
    if (_saveConversationsPending) {
      _saveConversationsPending = false;
      _saveConversationsNow();
    }
    _calls.dispose();
    _postDiscoverySecondSweep?.cancel();
    _postDiscoverySecondSweep = null;
    _crRetryTimer?.cancel();
    _crRetryTimer = null;
    _keyRotationTimer?.cancel();
    _keyRotationTimer = null;
    _keyRotationRetryTimer?.cancel();
    _keyRotationRetryTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _restoreRetryTimer?.cancel();
    _restoreRetryTimer = null;
    _restorePollingTimer?.cancel();
    _restorePollingTimer = null;
    _moderation.dispose();
    _polls.dispose();
    _systemChannelEvictionTimer?.cancel();
    _systemChannelEvictionTimer = null;
    _sysChanSaveDebounce?.cancel();
    _sysChanSaveDebounce = null;
    _updateCheckTimer?.cancel();
    _updateCheckTimer = null;
    _delegationRenewalTimer?.cancel();
    _delegationRenewalTimer = null;
    _natWizardTrigger?.stop();
    _natWizardTrigger = null;
    if (node.rendezvousManager == _rendezvousManager) {
      node.rendezvousManager = null;
    }
    _rendezvousManager?.dispose();
    _rendezvousManager = null;
    _fcRendezvous?.dispose();
    _fcRendezvous = null;
    // §19.6: tear down the binary-distribution subsystem — only the
    // identity that originally wired it onto the shared node clears it.
    if (node.transport.httpServer == _binaryHttpServer) {
      node.transport.httpServer = null;
    }
    _binaryHttpServer?.dispose();
    _binaryHttpServer = null;
    _binaryGcTimer?.cancel();
    _binaryGcTimer = null;
    _binaryUpdateManager?.dispose();
    _binaryUpdateManager = null;
    if (node.binaryRendezvousManager == _binaryRendezvousManager) {
      node.binaryRendezvousManager = null;
      node.binaryRecordProvider = null;
      node.binaryHasContentToShare = false;
    }
    _binaryRendezvousManager?.dispose();
    _binaryRendezvousManager = null;
    _deltaUpdateManager?.dispose();
    _deltaUpdateManager = null;
    _inviteLinkService?.dispose();
    _inviteLinkService = null;
    _physicalTransferHelper?.dispose();
    _physicalTransferHelper = null;
    _binarySeeder = null;
    _binaryFetchClient?.dispose();
    _binaryFetchClient = null;
    _binaryFragmentStore = null;
    // §2.2.4: stop Identity Publisher (Auth/Liveness-Refresh-Loops)
    if (_publisherPeerAddedListener != null) {
      node.routingTable.removeOnPeerAddedListener(_publisherPeerAddedListener!);
      _publisherPeerAddedListener = null;
    }
    _identityPublisher?.stop();
    _identityPublisher = null;
    _saveContacts();
    _saveGroups();
    _saveConversations();
    _saveProcessedMessageIds();
    mailboxStore.dispose();
    await _voiceTranscription?.stop();
    await _archiveManager?.stopScheduler();
    // Do NOT stop the shared node here — the daemon manages its lifecycle
    await CLogger.flushAll();
    _log.info('CleonaService stopped');
  }

  // ── Update Checking (Architecture Section 17.5.5) ──────────────────

  /// Check the DHT for a signed update manifest.
  ///
  /// Uses FRAGMENT_RETRIEVE on the update manifest's DHT key, then
  /// verifies the Ed25519 signature before presenting to the UI.
  void _checkForUpdates() {
    final checker = UpdateChecker(log: _log);
    final dhtKey = UpdateManifest.dhtKey();

    // Poll for update manifest fragments from all known peers
    final peers = node.routingTable.allPeers;
    for (final peer in peers) {
      _requestFragments(peer, dhtKey);
    }

    // Check collected fragments after a delay
    Timer(const Duration(seconds: 8), () async {
      final fragments = mailboxStore.retrieveFragments(dhtKey);
      if (fragments.isEmpty) return;

      // The manifest is small enough to be stored as a single fragment
      // (or the first fragment contains the complete JSON).
      try {
        final data = fragments.first.data;
        final jsonData = utf8.decode(data);
        final manifest = checker.verifyManifest(jsonData);
        if (manifest == null) return;

        _latestManifest = manifest;
        // Sec H-5 (V3.1.72) / T13: persist verified manifest so that the next
        // startup of `lib/main.dart` can apply the hard-block check before
        // services initialize. Best-effort — IO errors must not break the poll.
        try {
          final cacheFile = File('${AppPaths.dataDir}${Platform.pathSeparator}update_manifest_cache.json');
          cacheFile.parent.createSync(recursive: true);
          cacheFile.writeAsStringSync(jsonData, flush: true);
        } catch (e) {
          _log.debug('Failed to cache update manifest: $e');
        }
        final isNewer = checker.isNewer(manifest.version, currentAppVersion);

        if (isNewer) {
          _log.info('Update available: v${manifest.version} (current: v$currentAppVersion)');

          // §19.6: if the manifest carries a DHT binary tag, also check
          // whether this platform's update is reachable via in-network
          // binary distribution (peer-fetched fragments/binary) rather than
          // only the external manifest.downloadUrl.
          var inNetworkAvailable = false;
          if (manifest.dhtBinaryTag != null && _binaryUpdateManager != null) {
            try {
              inNetworkAvailable = await _binaryUpdateManager!
                  .checkForUpdate(manifest, currentAppVersion, Platform.operatingSystem);
              if (inNetworkAvailable) {
                _log.info('In-network update available for '
                    '${Platform.operatingSystem}: v${manifest.version}');
              }
            } catch (e) {
              _log.debug('In-network update check failed: $e');
            }
          }

          onUpdateAvailable?.call(manifest, inNetworkAvailable);
        } else {
          _log.debug('No update available (manifest: v${manifest.version}, current: v$currentAppVersion)');
        }
      } catch (e) {
        _log.debug('Update manifest check failed: $e');
      }
    });
  }

  /// Get the latest known update manifest (null if never checked or no update).
  UpdateManifest? get latestUpdateManifest => _latestManifest;

  /// Builds the current [BinaryAvailabilityRecord] for this device (§19.6.5)
  /// — a snapshot of what this node currently holds in its
  /// [BinaryFragmentStore] for the running platform/version. `addresses` and
  /// `seq` are placeholders overwritten by [BinaryRendezvousManager.publish].
  /// Synchronous because [RendezvousManager]-style record providers are
  /// invoked from debounce/periodic timers, not awaited call sites.
  BinaryAvailabilityRecord _buildBinaryAvailabilityRecord() {
    final platform = Platform.operatingSystem;
    final version = currentAppVersion;
    final store = _binaryFragmentStore;
    return BinaryAvailabilityRecord(
      deviceId: identity.deviceNodeId,
      platform: platform,
      version: version,
      addresses: const [],
      binaryHash: '',
      hasFullBinary: store?.hasCompleteSync(platform, version) ?? false,
      fragmentIndices: store?.availableFragmentsSync(platform, version) ?? const [],
      seq: 0,
    );
  }

  /// §19.6.2 fragment-store housekeeping: drops fragments/complete binaries
  /// for versions superseded by [kCurrentAppVersion] and enforces a
  /// platform-dependent storage budget on what's left. Invoked once at
  /// startup and then hourly via [_binaryGcTimer].
  void _runBinaryFragmentGc() {
    final updater = _binaryUpdateManager;
    final store = _binaryFragmentStore;
    if (updater == null || store == null) return;

    final budgetBytes = (Platform.isAndroid || Platform.isIOS)
        ? BinaryFragmentStore.kMobileBudgetBytes
        : BinaryFragmentStore.kDesktopBudgetBytes;

    try {
      updater.gc(kCurrentAppVersion, budgetBytes);
    } catch (e) {
      _log.debug('[update] Fragment GC failed: $e');
    }
  }

  /// The §19.6 binary seeder for this device, if wired (null on the
  /// non-first identity of a multi-identity daemon, or before startup).
  BinarySeeder? get binarySeeder => _binarySeeder;

  /// Self-seed: encode the currently-running binary into Reed-Solomon
  /// fragments so this node becomes a distribution source for its own
  /// platform/version immediately at startup, without waiting for an
  /// update download (§19.6.2). Only meaningful for sideloaded installs —
  /// Play Store builds never self-update, so seeding their own binary
  /// serves no purpose.
  void _selfSeedCurrentBinary() {
    final platform = Platform.operatingSystem;
    final version = kCurrentAppVersion;
    // Check if already seeded (idempotent).
    final existing = _binaryFragmentStore!.storedVersionsSync(platform);
    if (existing.contains(version)) {
      _log.debug('[update] Already seeded $platform/$version');
      return;
    }
    final binaryPath = _resolveCurrentBinaryPath();
    if (binaryPath == null) return;
    final file = File(binaryPath);
    if (!file.existsSync()) {
      _log.debug('[update] Binary not found at $binaryPath — skip self-seed');
      return;
    }
    // Read + seed async (don't block startup).
    file.readAsBytes().then((data) async {
      final count = await _binarySeeder!.seed(
        binary: data,
        platform: platform,
        version: version,
        maxFragments: Platform.isAndroid ? 2 : 8,
      );
      if (count > 0) {
        _log.info('[update] Self-seeded $count fragments for $platform/$version');
        node.binaryHasContentToShare = true;
        _binaryRendezvousManager?.startPeriodicRefresh(_buildBinaryAvailabilityRecord);
        _binaryRendezvousManager?.publish(_buildBinaryAvailabilityRecord());
      }
    }).catchError((e) {
      _log.warn('[update] Self-seed failed: $e');
    });
  }

  /// Resolves the on-disk path of the currently-running binary, for
  /// [_selfSeedCurrentBinary]. Platform-dependent — desktop builds run the
  /// executable directly, so [Platform.resolvedExecutable] is correct.
  /// Android's running code is the APK itself, not a standalone
  /// executable, and locating it requires the PackageManager (not yet
  /// wired) — self-seeding is skipped there until that lands.
  String? _resolveCurrentBinaryPath() {
    if (Platform.isAndroid) {
      // Android APK path — resolved via app info, placeholder for now.
      return null; // TODO: resolve via PackageManager
    }
    return Platform.resolvedExecutable;
  }

  void _selfPublishManifest() {
    try {
      final manifestPath = '${AppPaths.dataDir}${Platform.pathSeparator}update_manifest.json';
      final file = File(manifestPath);
      if (!file.existsSync()) return;
      final jsonData = file.readAsStringSync();
      final checker = UpdateChecker(log: _log);
      final manifest = checker.verifyManifest(jsonData);
      if (manifest == null) {
        _log.warn('[update] update_manifest.json has invalid signature — ignoring');
        return;
      }
      final dhtKey = UpdateManifest.dhtKey();
      final data = Uint8List.fromList(utf8.encode(jsonData));
      final messageId = SodiumFFI().sha256(data);
      final stored = mailboxStore.storeFragment(StoredFragment(
        mailboxId: dhtKey,
        messageId: messageId,
        fragmentIndex: 0,
        totalFragments: 1,
        requiredFragments: 1,
        data: data,
        originalSize: data.length,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      ));
      if (stored) {
        _log.info('[update] Published manifest v${manifest.version} to local DHT store');
        _latestManifest = manifest;
      }
    } catch (e) {
      _log.debug('[update] Self-publish manifest failed: $e');
    }
  }

  /// §19.6.2 — trigger an in-network binary update download. Public entry
  /// point for the UI layer: once [onUpdateAvailable] has fired with
  /// `inNetworkAvailable == true` and the user has consented to installing
  /// (no auto-install — §19.6.1 principle 6 / architecture §19.6.2 step 6),
  /// the UI calls this to actually fetch, verify and seed the binary via
  /// peers instead of falling back to `manifest.downloadUrl`.
  Future<void> startInNetworkUpdate(UpdateManifest manifest) =>
      _startInNetworkUpdate(manifest);

  /// Orchestrates the full in-network update flow (§19.6.2): resolve
  /// binary sources via [BinaryRendezvousManager], download erasure-coded
  /// fragments (or the full binary in one shot when a peer has it) from
  /// those sources, assemble + verify the result against the
  /// maintainer-signed hash carried in [manifest], and seed the verified
  /// binary back into this node's fragment store so it becomes a
  /// distribution source for other nodes too.
  Future<void> _startInNetworkUpdate(UpdateManifest manifest) async {
    final platform = Platform.operatingSystem;
    final store = _binaryFragmentStore;
    final updater = _binaryUpdateManager;
    final fetchClient = _binaryFetchClient;
    final seeder = _binarySeeder;
    if (store == null || updater == null || fetchClient == null || seeder == null) {
      _log.warn('startInNetworkUpdate: binary-update subsystem not initialized');
      return;
    }

    // The manifest's per-platform hash/signature/size is the trust anchor —
    // without it there is nothing to verify the downloaded binary against,
    // so refuse rather than install an unverified download.
    final expectedHash = manifest.binaryHashes?[platform];
    final signatureB64 = manifest.binarySignatures?[platform];
    final originalSize = manifest.binarySizes?[platform];
    if (expectedHash == null || signatureB64 == null || originalSize == null) {
      _log.warn('startInNetworkUpdate: manifest v${manifest.version} has no '
          'binaryHash/signature/size for platform=$platform — cannot verify, aborting');
      return;
    }
    final Uint8List signatureBytes;
    try {
      signatureBytes = base64Decode(signatureB64);
    } catch (e) {
      _log.warn('startInNetworkUpdate: malformed binarySignature for platform=$platform: $e');
      return;
    }

    // 1. Resolve binary sources via BinaryRendezvousManager (§19.6.5).
    final resolved = await node.binaryRendezvousManager?.resolve(platform);
    if (resolved == null || resolved.isEmpty) {
      _log.warn('startInNetworkUpdate: no binary sources found for platform=$platform');
      return;
    }

    // 2. Convert ResolvedBinaryEndpoint -> FragmentSource.
    final fragmentSources = resolved
        .where((ep) => ep.addresses.isNotEmpty)
        .map((ep) => FragmentSource(
              address: ep.addresses.first,
              fragmentIndices: ep.fragmentIndices,
              hasFullBinary: ep.hasFullBinary,
            ))
        .toList();
    if (fragmentSources.isEmpty) {
      _log.warn('startInNetworkUpdate: resolved sources carry no usable addresses');
      return;
    }

    // 3. Reed-Solomon parameters for this platform (§19.6.2).
    final params = BinarySeeder.paramsFor(platform);

    // 4./5. Delta path (§19.6.3): findDeltaPath() is a free, side-effect-free
    // check — only logged here. Actually applying a delta requires
    // libcleona_bsdiff, which DeltaUpdateManager.applyDelta() documents as
    // not yet implemented (always returns null), and the manifest carries no
    // delta-hash trust anchor yet either. So this stays a guarded no-op
    // until both land — full-binary download below is the functioning path.
    final deltaFromVersion = _deltaUpdateManager?.findDeltaPath(
      manifest: manifest,
      currentVersion: currentAppVersion,
      platform: platform,
    );
    if (deltaFromVersion != null) {
      _log.debug('startInNetworkUpdate: delta path $deltaFromVersion -> '
          '${manifest.version} advertised, but bsdiff is not yet wired — '
          'falling back to full binary');
    }

    // 6. Download (full binary in one shot if a source has it, else
    // K-of-N fragments assembled below).
    await updater.startDownload(
      platform: platform,
      version: manifest.version,
      n: params.n,
      k: params.k,
      expectedHash: expectedHash,
      sources: fragmentSources,
      fetchFragment: fetchClient.fetch,
    );
    if (updater.state == BinaryUpdateState.failed) {
      _log.warn('startInNetworkUpdate: download failed: ${updater.errorMessage}');
      return;
    }

    // 7. Assemble the binary from downloaded fragments (or reuse the
    // complete binary if a full-binary fetch already stored it).
    final binary = await updater.assemble(
        platform, manifest.version, params.n, params.k, originalSize);
    if (binary == null) {
      _log.warn('startInNetworkUpdate: assemble failed: ${updater.errorMessage}');
      return;
    }

    // 8. Verify SHA-256 hash + Ed25519 maintainer signature over that hash.
    // On success this also fires BinaryUpdateManager.onUpdateReady, which
    // republishes this node's binary-availability record.
    final verified = updater.verify(binary, expectedHash, signatureBytes);
    if (!verified) {
      _log.error('startInNetworkUpdate: verification FAILED for v${manifest.version} '
          '($platform) — refusing to seed or offer for install');
      return;
    }

    // 9. Seed — encode into RS fragments so this node also becomes a
    // fragment-serving distribution source, not just a full-binary source.
    final maxFragments = Platform.isAndroid || Platform.isIOS ? 2 : 8;
    final seededCount = await seeder.seed(
      binary: binary,
      platform: platform,
      version: manifest.version,
      maxFragments: maxFragments,
    );
    node.binaryHasContentToShare = true;
    _log.info('startInNetworkUpdate: v${manifest.version} verified and ready '
        '(${binary.length}B), seeded $seededCount fragment(s)');
  }

  // ── DHT Identity Registry Recovery (Architecture Section 6.4.3) ────

  /// Poll the DHT for identity registry fragments after seed recovery.
  ///
  /// [masterSeed] is the recovered master seed (from 24-word phrase).
  /// [onRecovered] is called with the list of identity entries if recovery succeeds.
  void pollRegistryFromDht(
    Uint8List masterSeed, {
    void Function(List<Map<String, dynamic>> identities, int nextIndex)? onRecovered,
  }) {
    final registry = IdentityDhtRegistry(masterSeed: masterSeed, profileDir: profileDir);
    final registryMailboxId = registry.registryDhtKey;

    _log.info('Registry recovery: polling DHT for registry fragments (key: ${registry.registryDhtKeyHex.substring(0, 16)}...)');

    // Use the same FRAGMENT_RETRIEVE mechanism as mailbox polling
    final peers = node.routingTable.allPeers;
    for (final peer in peers) {
      _requestFragments(peer, registryMailboxId);
    }

    // Collect fragments over time — check local mailbox store after delay
    // (fragments arrive asynchronously from responding peers)
    Timer(const Duration(seconds: 10), () {
      final fragments = mailboxStore.retrieveFragments(registryMailboxId);
      if (fragments.isEmpty) {
        _log.info('Registry recovery: no fragments found in DHT');
        return;
      }

      // Build fragment map (index -> data)
      final fragmentMap = <int, Uint8List>{};
      int maxSize = 0;
      for (final frag in fragments) {
        fragmentMap[frag.fragmentIndex] = Uint8List.fromList(frag.data);
        if (frag.data.length > maxSize) maxSize = frag.data.length;
      }

      _log.info('Registry recovery: collected ${fragmentMap.length} fragments');

      // Try reassembly with estimated original size
      // The original size is not stored explicitly — try with fragment count * fragment size
      final estimatedSize = maxSize * ReedSolomon.defaultK;
      final payload = registry.recoverFromFragments(fragmentMap, estimatedSize);
      if (payload == null) return;

      final identities = IdentityDhtRegistry.extractIdentities(payload);
      final nextIndex = IdentityDhtRegistry.extractNextIndex(payload);

      _log.info('Registry recovery: found ${identities.length} identities, next_index=$nextIndex');
      onRecovered?.call(identities, nextIndex);
    });
  }

  /// Store the current identity registry in the DHT with ACK-verified placement.
  /// Called after identity creation/deletion to keep the registry up-to-date.
  Future<bool> storeRegistryInDht(Uint8List masterSeed, List<({int? hdIndex, String name})> identities, int nextIndex) async {
    final registry = IdentityDhtRegistry(masterSeed: masterSeed, profileDir: profileDir);
    final entries = IdentityDhtRegistry.buildIdentityEntries(identities);
    final prepared = registry.prepareForDht(entries, nextIndex);

    final initialPeers = node.routingTable.findClosestPeers(prepared.mailboxId,
        count: 10, maxPerIpGroup: RoutingTable.diversityMaxPerIpGroup);
    if (initialPeers.isEmpty) {
      _log.debug('Registry DHT store skipped: no replicators known');
      return false;
    }

    final msgIdHex = bytesToHex(prepared.mailboxId);

    Future<bool> sendAndWait(int fragmentIndex, PeerInfo peer) async {
      final frag = prepared.fragments[fragmentIndex];
      final store = proto.FragmentStore()
        ..mailboxId = prepared.mailboxId
        ..messageId = prepared.mailboxId
        ..fragmentIndex = frag.index
        ..totalFragments = prepared.fragments.length
        ..requiredFragments = ReedSolomon.defaultK
        ..fragmentData = frag.data
        ..originalSize = prepared.payloadSize;
      final key = '$msgIdHex:$fragmentIndex';
      final completer =
          _pendingFragmentStoreAcks.putIfAbsent(key, () => Completer<void>());
      unawaited(node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_FRAGMENT_STORE,
        innerPayload: Uint8List.fromList(store.writeToBuffer()),
        recipientDeviceId: Uint8List.fromList(peer.nodeId),
      ));
      try {
        await completer.future.timeout(_peerStoreAckTimeout);
        return true;
      } on TimeoutException {
        return false;
      }
    }

    final coordinator = ErasurePlacementCoordinator<PeerInfo>(
      totalFragments: prepared.fragments.length,
      requiredFragments: ReedSolomon.defaultK,
      peerId: (p) => p.nodeIdHex,
      isPeerConfirmed: (p) => node.isPeerConfirmed(p.nodeIdHex),
    );
    final result = await coordinator.run(
      initialPool: initialPeers,
      deeperPool: () => node.routingTable.findClosestPeers(prepared.mailboxId,
          count: 30, maxPerIpGroup: RoutingTable.diversityMaxPerIpGroup),
      sendAndWait: sendAndWait,
    );

    for (var i = 0; i < prepared.fragments.length; i++) {
      _pendingFragmentStoreAcks.remove('$msgIdHex:$i');
    }

    if (result.success) {
      _log.info('Registry DHT store: ${result.confirmedCount}/${result.totalFragments} indices confirmed');
    } else {
      _log.warn('Registry DHT store FAILED: ${result.confirmedCount}/${result.totalFragments} indices confirmed');
    }
    return result.success;
  }

  /// Single-source-of-truth log message for KEM version rejections (Sec H-5
  /// silent-drop contract). Use from [PerMessageKem.decrypt] catch sites.
  void _warnKemVersionRejected(String context, KemVersionRejectedException e) {
    _log.warn('KEM version rejected for $context (version=${e.receivedVersion}, drop)');
  }

  // ──────────────────────────── V3 Send/Receive (§2.6 + §5) ────────────────────────────
  //
  // V3.0 layered-frames pipeline entry points.

  /// High-level V3 send API (Architecture v3.0 §2.6, sender steps 1-12):
  ///   resolve user → fan-out to devices → build inner → user-sign → zstd →
  ///   KEM-encrypt → wrap KEM → build outer → device-sign → PoW → tag → wire
  ///
  /// Returns true iff at least one device-leg of the recipient fan-out was
  /// dispatched successfully via the node. The codec produces the inner KEM
  /// bytes here; the outer wrap (Device-Sig + PoW + network_tag + send) lives
  /// in [CleonaNode.sendToDevice].
  ///
  /// Offline fallback (S&F + Mailbox) is a TODO — `false` is returned so
  /// callers can decide their queue-vs-drop policy explicitly.
  /// Sends a message to a recipient user.
  ///
  /// Returns true when at least one device received the direct UDP dispatch.
  /// Returns false in two distinct situations (callers that need to
  /// distinguish them can pass [l3Result]):
  ///   • No direct route — L3 placement attempted (Erasure + S&F).
  ///     [l3Result] is set to true if any L3 peer was reachable.
  ///   • No connectivity at all — L3 placement failed.
  ///     [l3Result] is set to false; caller should park the message in the
  ///     one-shot outbox ([_addToOutbox]) with status [MessageStatus.failed].
  ///
  /// [l3Result] is a single-element list used as an optional output parameter
  /// (Dart has no ref/out params).  Pass `[false]` and read index 0 after the
  /// call.  Existing callers that ignore L3 outcome can omit this parameter.
  @override
  Future<bool> sendToUser({
    required Uint8List recipientUserId,
    required proto.MessageTypeV3 messageType,
    required Uint8List payload,
    Uint8List? senderUserId,
    Uint8List? groupId,
    Uint8List? messageId,
    proto.ContentMetadata? contentMetadata,
    proto.EditMetadata? editMetadata,
    proto.ExpiryMetadata? expiryMetadata,
    proto.ErasureCodingMetadata? erasureMetadata,
    List<bool>? l3Result,
    int? groupMembershipEpoch,
    Uint8List? groupMembershipHash,
    Uint8List? targetDeviceId,
  }) async {
    // 1. Sender identity: this CleonaService is bound to a single
    //    IdentityContext (see ipc_server `_resolveService` per-request
    //    routing). Cross-identity sends therefore go through the matching
    //    service instance, not via a `senderUserId` override on a foreign
    //    service. The legacy override parameter is kept for callers that
    //    still pass it explicitly, but it MUST equal `identity.userId` —
    //    a mismatch indicates a router-bug at the call-site.
    final effectiveSenderUserId = senderUserId ?? identity.userId;
    assert(_constantTimeEq(effectiveSenderUserId, identity.userId),
        'sendToUser: senderUserId mismatch for service-bound identity '
        '${identity.userIdHex.substring(0, 8)} — fix the call-site');

    // 2. Resolve KEM-pubkeys for the recipient user from the contact store.
    //    The Inner ApplicationFrame is KEM-encrypted under the recipient User
    //    keypair (X25519 + ML-KEM-768). Both keys live on the contact record;
    //    callers that haven't completed the CR exchange cannot reach this
    //    user yet — drop with a TODO log.
    final recipientHex = bytesToHex(recipientUserId);
    final contact = _contacts[recipientHex];
    if (contact == null ||
        contact.x25519Pk == null ||
        contact.mlKemPk == null) {
      _log.warn('sendToUser: no KEM pubkeys for ${recipientHex.length >= 8 ? recipientHex.substring(0, 8) : recipientHex} '
          '(contact=${contact != null}, x25519=${contact?.x25519Pk != null}, mlKem=${contact?.mlKemPk != null})');
      return false;
    }

    // 3. Resolve recipient → list of authorized device-IDs (§2.6.2).
    //    Fast path: use locally-cached device IDs from received packets /
    //    CR handshake. These are always fresh (populated on every incoming
    //    ApplicationFrame at handleApplicationFrame:10335) and avoid the
    //    2s+ DHT timeout on cold networks where auth-manifests haven't
    //    been published yet. DHT resolution runs in the background to warm
    //    the cache for future sends and to discover additional devices.
    List<Uint8List> deviceIds;
    if (targetDeviceId != null && targetDeviceId.isNotEmpty) {
      // Caller already knows the exact device this frame must reach (e.g. a
      // DELIVERY_RECEIPT addressed back to the device that sent the original
      // message) — skip the multi-device cache/DHT resolution below, which
      // may hold a *different*, stale device of the same recipient user.
      deviceIds = [targetDeviceId];
      _log.debug('sendToUser: targeted send to device '
          '${_hexShort(targetDeviceId)} for ${_hexShort(recipientUserId)}');
    } else if (contact.deviceNodeIds.isNotEmpty) {
      deviceIds = contact.deviceNodeIds.map(hexToBytes).toList(growable: false);
      _log.debug('sendToUser: fast-path ${deviceIds.length} cached deviceNodeIds '
          'for ${_hexShort(recipientUserId)}');
      unawaited(node.resolveUserToDevices(recipientUserId).catchError((_) => <Uint8List>[]));
    } else {
      try {
        deviceIds = await node.resolveUserToDevices(recipientUserId);
      } catch (e) {
        _log.warn('sendToUser: resolveUserToDevices threw $e — drop');
        return false;
      }
    }
    if (deviceIds.isEmpty) {
      // §5.1 Layer 1 empty → skip Layer 2, go directly to Layer 3.
      _log.info('sendToUser: no devices for ${_hexShort(recipientUserId)}'
          ' — triggering offline cascade (S&F + Erasure)');
      final effectiveMessageId = (messageId != null && messageId.isNotEmpty)
          ? messageId
          : SodiumFFI().randomBytes(16);
      final inner = proto.ApplicationFrameV3()
        ..recipientUserId = recipientUserId
        ..senderUserId = effectiveSenderUserId
        ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
        ..messageId = effectiveMessageId
        ..messageType = messageType
        ..payload = payload;
      if (groupId != null && groupId.isNotEmpty) inner.groupId = groupId;
      if (contentMetadata != null) inner.contentMetadata = contentMetadata;
      if (editMetadata != null) inner.editMetadata = editMetadata;
      if (expiryMetadata != null) inner.expiryMetadata = expiryMetadata;
      if (erasureMetadata != null) inner.erasureMetadata = erasureMetadata;
      if (groupMembershipEpoch != null && groupMembershipEpoch > 0) {
        inner.groupMembershipEpoch = Int64(groupMembershipEpoch);
      }
      if (groupMembershipHash != null) {
        inner.groupMembershipHash = groupMembershipHash;
      }
      final l3PowStart = DateTime.now();
      final (kemBytes, l3Pow) =
          await V3FrameCodec.buildAndEncryptInnerWithPowAsync(
        innerFrameBytes: inner.writeToBuffer(),
        senderUserEd25519Sk: identity.signingEd25519Sk,
        senderUserMlDsaSk: identity.signingMlDsaSk,
        recipientUserX25519Pk: contact.x25519Pk!,
        recipientUserMlKemPk: contact.mlKemPk!,
      );
      final l3PowMs = DateTime.now().difference(l3PowStart).inMilliseconds;
      _log.info('offlineDelivery: PoW done kemSize=${kemBytes.length} powMs=$l3PowMs');
      final outer = V3FrameCodec.buildOuter(
        nextHopDeviceId: recipientUserId,
        senderDeviceId: node.primaryIdentity.deviceNodeId,
        deviceKeys: node.deviceKeyPair,
        innerPayload: kemBytes,
        payloadType: proto.PayloadTypeV3.PAYLOAD_APPLICATION_FRAME,
        applicationFlavor: true,
        precomputedPow: l3Pow,
      );
      final canonicalBytes = node.serializePacketForOfflineDelivery(outer);
      final fragmentBundleId =
          SodiumFFI().sha256(canonicalBytes).sublist(0, 16);
      final erasureOk = await _distributeErasureFragments(
        packetBytes: canonicalBytes,
        messageId: fragmentBundleId,
        recipientUserEd25519Pk: contact.ed25519Pk,
        recipientUserNodeId: recipientUserId,
      );
      final safOk = await _storeSafOnContactPeers(
        recipientUserId: recipientUserId,
        wrappedEnvelope: canonicalBytes,
      );
      // §5.8: report L3 placement outcome to caller via optional output param.
      final l3Placed = erasureOk || safOk;
      if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = l3Placed;
      if (!l3Placed) {
        // §5.8: 0 connectivity — park canonical bytes in outbox so the next
        // onNetworkChanged edge can retry placement exactly once.
        _addToOutbox(
          messageIdHex: bytesToHex(effectiveMessageId),
          recipientUserIdHex: bytesToHex(recipientUserId),
          recipientEd25519PkHex:
              contact.ed25519Pk != null ? bytesToHex(contact.ed25519Pk!) : null,
          canonicalPacket: canonicalBytes,
        );
        _log.info('sendToUser: 0 peers — message ${bytesToHex(effectiveMessageId).substring(0, 8)} parked in outbox');
      }
      return false;
    }

    // 4. Per-device fan-out. The Inner ApplicationFrameV3 is identical for
    //    every device of a given recipient user (recipient pubkeys are the
    //    User-Keypair, not the Device-Keypair). The Outer NetworkPacketV3
    //    differs per device (nextHopDeviceId + Device-Sig binding to that
    //    routing target). Re-encrypt the Inner per device because the codec
    //    mutates sig fields and KEM nonces, then re-build+sign the Outer.
    //
    //    The first successfully built outer is captured as the canonical
    //    erasure-source for §5.4 Reed-Solomon offline-delivery: AppFrame
    //    KEM is User-PK-keyed, so any per-device packet decapsulates with
    //    the same User-KEM-SK — one fragment-bundle suffices for all of
    //    the recipient's devices polling the same user-mailbox.
    int dispatched = 0;
    final senderDeviceId = node.deviceKeyPair.ed25519PublicKey;
    // Note: senderDeviceId on the wire is sha256(secret + ed25519_pk). For now
    // the routing layer keys peers by deviceNodeId from primaryIdentity, so
    // reuse that — multi-tab unification is a Welle-3 follow-up.
    final myDeviceNodeId = node.primaryIdentity.deviceNodeId;
    // Inner messageId (16-byte UUID v4): identifies the logical message
    // end-to-end, identical across all devices of the same recipient (the
    // KEM-ciphertext varies per device, the inner frame including this ID
    // does not). Receiver-side dedup, DELIVERY_RECEIPT correlation and
    // edit/delete-by-ID all key on this. Caller may pre-supply for UI-id
    // alignment (e.g. sender's optimistic msg.id == wire messageId hex).
    final effectiveMessageId = (messageId != null && messageId.isNotEmpty)
        ? messageId
        : SodiumFFI().randomBytes(16);
    proto.NetworkPacketV3? canonicalPacket;
    for (final deviceId in deviceIds) {
      try {
        final inner = proto.ApplicationFrameV3()
          ..recipientUserId = recipientUserId
          ..senderUserId = effectiveSenderUserId
          ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
          ..messageId = effectiveMessageId
          ..messageType = messageType
          ..payload = payload;
        if (groupId != null && groupId.isNotEmpty) inner.groupId = groupId;
        if (contentMetadata != null) inner.contentMetadata = contentMetadata;
        if (editMetadata != null) inner.editMetadata = editMetadata;
        if (expiryMetadata != null) inner.expiryMetadata = expiryMetadata;
        if (erasureMetadata != null) inner.erasureMetadata = erasureMetadata;
        if (groupMembershipEpoch != null && groupMembershipEpoch > 0) {
          inner.groupMembershipEpoch = Int64(groupMembershipEpoch);
        }
        if (groupMembershipHash != null) {
          inner.groupMembershipHash = groupMembershipHash;
        }

        // Inner crypto + PoW in one background isolate (main isolate free).
        final powStart = DateTime.now();
        final (kemBytes, pow) =
            await V3FrameCodec.buildAndEncryptInnerWithPowAsync(
          innerFrameBytes: inner.writeToBuffer(),
          senderUserEd25519Sk: identity.signingEd25519Sk,
          senderUserMlDsaSk: identity.signingMlDsaSk,
          recipientUserX25519Pk: contact.x25519Pk!,
          recipientUserMlKemPk: contact.mlKemPk!,
        );
        final powMs = DateTime.now().difference(powStart).inMilliseconds;
        _log.info('sendToUser: PoW done for ${_hexShort(deviceId)} '
            'kemSize=${kemBytes.length} powMs=$powMs nonce=${pow.nonce}');
        final outer = V3FrameCodec.buildOuter(
          nextHopDeviceId: deviceId,
          senderDeviceId: myDeviceNodeId,
          deviceKeys: node.deviceKeyPair,
          innerPayload: kemBytes,
          payloadType: proto.PayloadTypeV3.PAYLOAD_APPLICATION_FRAME,
          applicationFlavor: true,
          precomputedPow: pow,
        );

        canonicalPacket ??= outer;

        final ok = await node.sendToDevice(outer, deviceId);
        if (ok) dispatched++;
      } catch (e) {
        _log.warn('sendToUser: per-device fan-out failed for '
            '${_hexShort(deviceId)}: $e (continuing)');
      }
    }
    // Suppress the unused-warning when senderDeviceId becomes load-bearing
    // post-Welle-3; leaving the binding so Welle-3 wiring is a one-line edit.
    // ignore: unnecessary_statements
    senderDeviceId;

    // RUDP-Light (Architecture §2.4.5): register the pending ACK with the
    // tracker once at least one device-leg of the fan-out was dispatched.
    // The tracker keys on `(messageIdHex, recipientUserHex)` and times out
    // after `computeTimeout(baseRtt)` — on receipt it fires `onAckReceived`
    // (DV-bridge → confirmRoute), on 3× consecutive timeout per route it
    // fires `onRouteDown` (markRouteDown + Poison Reverse). `wasDirect` is
    // computed at receipt time from the source address.
    if (dispatched > 0 &&
        AckTracker.isAckWorthyV3(messageType) &&
        !_constantTimeEq(recipientUserId, identity.userId)) {
      final messageIdHex = bytesToHex(effectiveMessageId);
      final recipientHex = bytesToHex(recipientUserId);
      final baseRtt = node.dhtRpc.getRtt(recipientUserId);
      final timeout = AckTracker.computeTimeout(baseRtt);
      final canonicalBytes = canonicalPacket != null
          ? node.serializePacketForOfflineDelivery(canonicalPacket)
          : null;
      unawaited(node.ackTracker.trackSend(
        messageIdHex,
        recipientHex,
        const <PeerAddress>[],
        timeout,
        serializedPacket: canonicalBytes,
        recipientUserId: recipientUserId,
      ));

      // §5.8 Crash-safety: park sent-but-unACK'd messages in outbox so an
      // app kill between send and DELIVERY_RECEIPT does not lose the message.
      // The entry is removed on ACK receipt (_handleDeliveryReceiptV3) or
      // flushed with full L1→L2→L3 cascade on next restart.
      if (canonicalBytes != null) {
        _addToOutbox(
          messageIdHex: messageIdHex,
          recipientUserIdHex: recipientHex,
          recipientEd25519PkHex:
              contact.ed25519Pk != null ? bytesToHex(contact.ed25519Pk!) : null,
          canonicalPacket: canonicalBytes,
        );
      }
    }

    // §5.4 Erasure-coded offline-delivery: the sender places fragments
    // push-based on send-failure, not on every send (storage efficiency
    // stays bounded). When at least one device accepted the direct send,
    // the message is considered delivered and erasure-distribution is
    // skipped — the recipient will receive the inner ApplicationFrame
    // through the standard receive pipeline.
    if (dispatched == 0 && canonicalPacket != null) {
      final canonicalBytes =
          node.serializePacketForOfflineDelivery(canonicalPacket);
      final fragmentBundleId =
          SodiumFFI().sha256(canonicalBytes).sublist(0, 16);
      await _distributeErasureFragments(
        packetBytes: canonicalBytes,
        messageId: Uint8List.fromList(fragmentBundleId),
        recipientUserEd25519Pk: contact.ed25519Pk,
        recipientUserNodeId: recipientUserId,
      );
      unawaited(_storeSafOnContactPeers(
        recipientUserId: recipientUserId,
        wrappedEnvelope: canonicalBytes,
      ));
    }

    return dispatched > 0;
  }

  /// Welle 5 Teil 4 §8.1.1 First-CR-Bootstrap receive-side. Called by the
  /// daemon when an `InfrastructureFrameV3` with `messageType=
  /// MTV3_CONTACT_REQUEST` was decapped against this device's
  /// Device-KEM-SK and routed (by recipientDeviceId) to the identity that
  /// owns this device-id. The InfrastructureFrame's payload is a
  /// User-signed `ApplicationFrameV3` whose `senderUserId` corresponds to
  /// pubkeys carried *in plaintext inside the CR payload* — that is the
  /// §8.1.1 trust-bootstrap (the recipient cannot do contact-registry
  /// lookup because the CR is what creates the contact).

  /// Verify path: parse inner ApplicationFrameV3, parse its
  /// ContactRequestMsg payload, extract `(ed25519_pk, ml_dsa_pk)`, run the
  /// User-Sig verify against those — then dispatch through the normal
  /// [handleApplicationFrame] flow (identity-resolution + state mutation
  /// downstream are unchanged).
  Future<void> handleIncomingFirstContactRequest(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) async {
    proto.ApplicationFrameV3 inner;
    try {
      inner = proto.ApplicationFrameV3.fromBuffer(frame.payload);
    } catch (e) {
      _log.debug('First-CR drop: ApplicationFrameV3 parse failed: $e');
      return;
    }
    if (inner.messageType != proto.MessageTypeV3.MTV3_CONTACT_REQUEST) {
      _log.debug('First-CR drop: inner messageType is ${inner.messageType.name}, '
          'expected MTV3_CONTACT_REQUEST');
      return;
    }
    if (Uint8List.fromList(inner.recipientUserId).length != identity.userId.length ||
        !_constantTimeEq(Uint8List.fromList(inner.recipientUserId), identity.userId)) {
      _log.debug('First-CR drop: recipientUserId mismatch '
          '(packet=${bytesToHex(Uint8List.fromList(inner.recipientUserId)).substring(0, 8)}, '
          'us=${identity.userIdHex.substring(0, 8)})');
      return;
    }
    proto.ContactRequestMsg cr;
    try {
      cr = proto.ContactRequestMsg.fromBuffer(inner.payload);
    } catch (e) {
      _log.debug('First-CR drop: ContactRequestMsg parse failed: $e');
      return;
    }
    if (cr.ed25519PublicKey.isEmpty || cr.mlDsaPublicKey.isEmpty) {
      _log.debug('First-CR drop: CR payload missing sender pubkeys');
      return;
    }

    // §8.1 per-sender CR rate limit (5/hour) — applies to First-CR path too.
    final senderHex = bytesToHex(Uint8List.fromList(inner.senderUserId));
    if (_isCrRateLimited(senderHex)) {
      _log.debug('First-CR drop: rate limited for ${senderHex.substring(0, 8)}');
      return;
    }

    // User-Sig-verify against the pubkeys carried in the CR (§8.1.1
    // trust-bootstrap). Mirrors V3FrameCodec.decryptAndVerifyInner step 5.
    final edSig = Uint8List.fromList(inner.userEd25519Sig);
    final mlSig = Uint8List.fromList(inner.userMlDsaSig);
    inner.clearUserEd25519Sig();
    inner.clearUserMlDsaSig();
    final signedBytes = inner.writeToBuffer();
    inner.userEd25519Sig = edSig;
    inner.userMlDsaSig = mlSig;
    if (!SodiumFFI().verifyEd25519(
        signedBytes, edSig, Uint8List.fromList(cr.ed25519PublicKey))) {
      _log.debug('First-CR drop: Ed25519 user-sig invalid');
      return;
    }
    if (!OqsFFI().mlDsaVerify(
        signedBytes, mlSig, Uint8List.fromList(cr.mlDsaPublicKey))) {
      _log.debug('First-CR drop: ML-DSA user-sig invalid');
      return;
    }

    await handleApplicationFrame(
      frame: inner,
      senderDeviceId: senderDeviceId,
      sourceAddr: sourceAddr,
      sourcePort: sourcePort,
      // §2.4.0: attach the inner-claimed senderUserId to the snapshot so
      // bridge-layer F4-Gate (§8.1) can compare against the contact-store
      // entry. Outer-Sig in First-CR is verified-or-bootstrap depending on
      // whether we have prior infra exchange with the sender device.
      snapshot: snapshot.withSenderUserId(
          Uint8List.fromList(inner.senderUserId)),
    );
  }

  /// Welle 6 §6.3 receive-side. Called by the daemon when an
  /// `InfrastructureFrameV3` with `messageType=MTV3_RESTORE_BROADCAST` was
  /// decapped against this device's Device-KEM-SK and routed (by
  /// recipientDeviceId) to the identity that owns this device-id.
  ///
  /// The InfrastructureFrame's payload is a plain `RestoreBroadcast` proto
  /// (NOT an ApplicationFrame wrap) carrying an old-Ed25519 inner signature
  /// over the body — that is the §6.3 trust-bootstrap (the recipient cannot
  /// run the standard User-Sig path because the recovering peer's user-keys
  /// just changed). Forwards the raw body bytes to `_handleRestoreBroadcast`
  /// which keys off `rb.oldNodeId` for the contact lookup and verifies the
  /// inner old-Ed25519 sig against the contact's stored pubkey.
  Future<void> handleIncomingRestoreBroadcastInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) async {
    // §2.4.0 / §8.1 — log the outer-sig status so live-debug can correlate
    // bootstrap-pass cases. Restore is a special case: the inner old-Ed25519
    // sig (verified in `_handleRestoreBroadcast` against the OLD
    // contact.ed25519Pk) is the canonical authenticity check, so a
    // bootstrap-skipped Outer-Sig is plausible (the recovering peer is on a
    // fresh device). Don't drop on `skippedBootstrap`.
    if (snapshot.outerSigStatus != OuterSigStatus.verified) {
      _log.warn('RESTORE_BROADCAST V3 Infra: outerSig='
          '${snapshot.outerSigStatus.name} from device='
          '${bytesToHex(senderDeviceId).substring(0, 8)} — '
          'inner old-Ed25519 sig is the trust anchor (§6.3)');
    }
    _handleRestoreBroadcast(Uint8List.fromList(frame.payload));
  }

  /// Welle 6 §7.4 receive-side. Called by the daemon when an
  /// `InfrastructureFrameV3` with `messageType=MTV3_KEY_ROTATION_BROADCAST`
  /// was decapped against this device's Device-KEM-SK.
  ///
  /// The InfrastructureFrame path is reserved for the **Emergency variant**
  /// (dual-sig in body — `oldSignatureEd25519` AND `newSignatureEd25519`).
  /// Periodic KEM-only rotation continues on the ApplicationFrame path
  /// because no signature key changes there.
  ///
  /// Receiver enforces the Emergency-discriminator by parsing the inner
  /// `KeyRotationBroadcast` body and asserting both sig fields are
  /// populated. Frames missing either sig are dropped — they belong on the
  /// ApplicationFrame path, not here.
  ///
  /// Body filled in Welle 6 (Subagent C).
  ///
  /// Wire-layer: parses [frame.payload] as a `KeyRotationBroadcast` proto
  /// (NOT an ApplicationFrame wrap — the InfrastructureFrame.payload IS the
  /// signed broadcast body, per §2.3.5 + §7.4). Enforces the
  /// Emergency-discriminator: both `oldSignatureEd25519` AND
  /// `newSignatureEd25519` must be populated. Single-sig (Periodic) rotations
  /// belong on the ApplicationFrame path and are dropped here as a
  /// cross-layer-abuse defence.
  ///
  /// Inner-auth is the dual-sig itself. Outer-Sig status (`verified` vs.
  /// `skippedBootstrap`) is informational only — the receiver MUST NOT
  /// accept a rotation without dual-sig verification regardless of the
  /// outer status, and the inner dual-sig dispatcher below enforces that.
  /// We therefore proceed even on `skippedBootstrap`, matching the spec
  /// note in §2.4.0 + §7.4.
  Future<void> handleIncomingKeyRotationBroadcastInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) async {
    proto.KeyRotationBroadcast broadcast;
    try {
      broadcast = proto.KeyRotationBroadcast.fromBuffer(frame.payload);
    } catch (e) {
      _log.debug('handleIncomingKeyRotationBroadcastInfra drop: '
          'KeyRotationBroadcast parse failed: $e '
          '(sender=${bytesToHex(senderDeviceId).substring(0, 8)})');
      return;
    }

    // Discriminator: InfrastructureFrame path is reserved for the
    // Emergency variant. A frame missing either sig was either a Periodic
    // rotation that picked the wrong wire path (sender bug), or an
    // attacker trying to launder a single-sig past the dual-sig gate.
    if (broadcast.oldSignatureEd25519.isEmpty ||
        broadcast.newSignatureEd25519.isEmpty) {
      _log.warn('handleIncomingKeyRotationBroadcastInfra drop: missing '
          'dual-sig (oldSig=${broadcast.oldSignatureEd25519.length}b '
          'newSig=${broadcast.newSignatureEd25519.length}b) — the '
          'InfrastructureFrame path is reserved for the Emergency variant; '
          'periodic single-sig rotation belongs on the ApplicationFrame '
          'path '
          '(sender=${bytesToHex(senderDeviceId).substring(0, 8)})');
      return;
    }

    if (snapshot.outerSigStatus != OuterSigStatus.verified) {
      // Inform-and-proceed: the dual-sig in the body is cryptographically
      // sufficient. The dispatcher below will refuse if either sig fails
      // to verify — that is the only authentication subject for this
      // messageType (§7.4 Variant b).
      _log.info('handleIncomingKeyRotationBroadcastInfra: outer-sig '
          '${snapshot.outerSigStatus.name} (proceeding — dual-sig in body '
          'is the authoritative inner-auth per §7.4)');
    }

    // §2.3.5 InfrastructureFrame has no senderUserId field — the handler
    // keys `_contacts` by senderHex. Locate the matching contact by
    // scanning whose stored ed25519Pk verifies the inner old-sig in the
    // broadcast body.
    final inferredSenderUserId = _findSenderUserIdForKeyRotation(broadcast);
    if (inferredSenderUserId.isEmpty) {
      _log.warn('handleIncomingKeyRotationBroadcastInfra drop: cannot '
          'locate matching contact via old-sig verification '
          '(sender=${bytesToHex(senderDeviceId).substring(0, 8)})');
      return;
    }
    _handleKeyRotationBroadcast(
        Uint8List.fromList(frame.payload), inferredSenderUserId);
  }

  /// §6.2 receive-side. Called by the daemon when an `InfrastructureFrameV3`
  /// with `messageType=MTV3_GUARDIAN_SHARE_STORE` was decapped against this
  /// device's Device-KEM-SK and routed to the identity owning this device.
  ///
  /// The InfrastructureFrame's payload is the plain `GuardianShareStore`
  /// proto (no inner KEM wrap — the frame-level Device-KEM encap is the
  /// only confidentiality layer). Forward the raw body bytes directly to
  /// `guardianService.handleShareStore`.
  Future<void> handleIncomingGuardianShareStoreInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) async {
    if (snapshot.outerSigStatus != OuterSigStatus.verified) {
      _log.info('GUARDIAN_SHARE_STORE V3 Infra: outer-sig '
          '${snapshot.outerSigStatus.name} from device='
          '${bytesToHex(senderDeviceId).substring(0, 8)} — proceeding '
          '(payload is the §6.2 share, recipient validates by storing)');
    }
    guardianService.handleShareStore(Uint8List.fromList(frame.payload));
  }

  /// §6.2 receive-side. Called by the daemon when an `InfrastructureFrameV3`
  /// with `messageType=MTV3_GUARDIAN_RESTORE_REQUEST` was decapped.
  /// `guardianService.handleRestoreRequest` silently ignores the request if
  /// we don't hold a share for the named owner — so a broadcast fan-out
  /// from a triggering guardian arriving at non-guardian contacts is
  /// correctly absorbed.
  Future<void> handleIncomingGuardianRestoreRequestInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) async {
    if (snapshot.outerSigStatus != OuterSigStatus.verified) {
      _log.info('GUARDIAN_RESTORE_REQUEST V3 Infra: outer-sig '
          '${snapshot.outerSigStatus.name} from device='
          '${bytesToHex(senderDeviceId).substring(0, 8)} — proceeding '
          '(non-share holders ignore in handleRestoreRequest)');
    }
    guardianService.handleRestoreRequest(Uint8List.fromList(frame.payload));
  }

  /// §6.2 receive-side. Called by the daemon when an `InfrastructureFrameV3`
  /// with `messageType=MTV3_GUARDIAN_RESTORE_RESPONSE` arrives directly
  /// (NOT via DHT-fragment-retrieve — that path stores raw
  /// GuardianRestoreResponse bytes inside FragmentStore.fragmentData and is
  /// fetched separately). This direct path covers the future case where a
  /// confirming guardian sends the response point-to-point to the
  /// recovering owner once they come online.
  Future<void> handleIncomingGuardianRestoreResponseInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) async {
    guardianService.handleRestoreResponse(Uint8List.fromList(frame.payload));
  }

  /// V3 InfraFrame route for FRAGMENT_STORE — Reed-Solomon erasure-coded
  /// fragment delivery + S&F mailbox push (Architecture §5.4 + §23.3).
  void handleIncomingFragmentStoreInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) {
    _handleFragmentStore(Uint8List.fromList(frame.payload), senderDeviceId);
  }

  /// V3 InfraFrame route for FRAGMENT_RETRIEVE — request a mailbox dump
  /// from a peer holding our fragments. The peer responds with a series
  /// of FRAGMENT_STORE InfraFrames targeted at [senderDeviceId].
  void handleIncomingFragmentRetrieveInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) {
    _handleFragmentRetrieve(Uint8List.fromList(frame.payload), senderDeviceId);
  }

  /// V3 InfraFrame route for FRAGMENT_DELETE — explicit fragment-eviction
  /// signal from the mailbox owner once they've pulled and reassembled.
  void handleIncomingFragmentDeleteInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) {
    _handleFragmentDelete(Uint8List.fromList(frame.payload));
  }

  // ── §5.5 Store-and-Forward InfraFrame Handlers ──────────────────────

  void handleIncomingPeerStoreInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) {
    try {
      final store = proto.PeerStore.fromBuffer(frame.payload);
      final recipientUserId = Uint8List.fromList(store.recipientNodeId);

      // §5.5 receiver-side validation: only store for recipients that are
      // our accepted contacts.  This enforces "contact peer" at the storage
      // node rather than relying on sender-side heuristics.
      // S121 F4(a): infrastructure nodes (headless/bootstrap) accept stores
      // for ANY recipient within the existing budgets (30/recipient,
      // sender rate limit) — they have no contacts by design, and they are
      // the peers every device confirms and polls at coming-online. This
      // makes the §5.5 Phase-2 fallback actually deliverable (pre-F4 a
      // spec-compliant bootstrap rejected every Phase-2 store) and mirrors
      // the §5.5b First-CR-Mailbox precedent.
      final recipientHex = bytesToHex(recipientUserId);
      final isOurContact = _contacts.values.any((c) =>
          bytesToHex(c.nodeId) == recipientHex && c.status == 'accepted');
      if (!isOurContact && !acceptAnyPeerStore) {
        final ack = proto.PeerStoreAck()
          ..storeId = store.storeId
          ..accepted = false;
        node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_PEER_STORE_ACK,
          innerPayload: Uint8List.fromList(ack.writeToBuffer()),
          recipientDeviceId: senderDeviceId,
        );
        return;
      }

      final storeIdHex = bytesToHex(Uint8List.fromList(store.storeId));
      final ttlMs = store.ttlMs.toInt();
      final stored = node.peerMessageStore.storeMessage(
        recipientUserId: recipientUserId,
        wrappedEnvelope: Uint8List.fromList(store.wrappedEnvelope),
        storeIdHex: storeIdHex,
        ttlMs: ttlMs > 0 ? ttlMs : PeerMessageStore.defaultTtlMs,
      );
      final ack = proto.PeerStoreAck()
        ..storeId = store.storeId
        ..accepted = stored;
      node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_PEER_STORE_ACK,
        innerPayload: Uint8List.fromList(ack.writeToBuffer()),
        recipientDeviceId: senderDeviceId,
      );
    } catch (e) {
      _log.debug('PEER_STORE error: $e');
    }
  }

  void handleIncomingPeerRetrieveInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) {
    try {
      final retrieve = proto.PeerRetrieve.fromBuffer(frame.payload);
      final requesterUserId = Uint8List.fromList(retrieve.requesterNodeId);
      final envelopes = node.peerMessageStore.retrieveMessages(requesterUserId);
      final response = proto.PeerRetrieveResponse()
        ..storedEnvelopes.addAll(envelopes)
        ..remaining = 0;
      node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_PEER_RETRIEVE_RESPONSE,
        innerPayload: Uint8List.fromList(response.writeToBuffer()),
        recipientDeviceId: senderDeviceId,
      );
      _log.info('PEER_RETRIEVE: sent ${envelopes.length} stored messages '
          'to ${bytesToHex(senderDeviceId).substring(0, 8)}');
    } catch (e) {
      _log.debug('PEER_RETRIEVE error: $e');
    }
  }

  void handleIncomingPeerRetrieveResponseInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) {
    try {
      final response = proto.PeerRetrieveResponse.fromBuffer(frame.payload);
      var injected = 0;
      for (final envelope in response.storedEnvelopes) {
        try {
          node.dispatchReassembledPacket(Uint8List.fromList(envelope));
          injected++;
        } catch (e) {
          _log.debug('S&F re-inject failed: $e');
        }
      }
      if (injected > 0) {
        _log.info('S&F pull: re-injected $injected messages from '
            '${bytesToHex(senderDeviceId).substring(0, 8)}');
      }
    } catch (e) {
      _log.debug('PEER_RETRIEVE_RESPONSE error: $e');
    }
  }

  /// Welle 6 §7.4 path-discriminator. Returns true iff [broadcast] carries
  /// the Emergency-variant dual-sig (both `oldSignatureEd25519` and
  /// `newSignatureEd25519` populated). Receivers use this to enforce the
  /// path constraint: Emergency belongs on the InfrastructureFrame path,
  /// Periodic on the ApplicationFrame path. Public so smoke tests can
  /// assert the discriminator behaviour without spinning up a full service.
  static bool isEmergencyKeyRotationBody(
      proto.KeyRotationBroadcast broadcast) {
    return broadcast.oldSignatureEd25519.isNotEmpty &&
        broadcast.newSignatureEd25519.isNotEmpty;
  }

  /// Welle 6 §7.4: locate the contact whose stored `ed25519Pk` verifies the
  /// `oldSignatureEd25519` field on a KeyRotationBroadcast. The
  /// InfrastructureFrame carries no senderUserId, so we cannot trust any
  /// claimed identity — the only sound lookup is "which of my known
  /// contacts could have signed this?". Returns the contact's userId
  /// (= nodeId) on hit, or empty bytes on miss.
  Uint8List _findSenderUserIdForKeyRotation(
      proto.KeyRotationBroadcast broadcast) {
    final dataToVerify = (proto.KeyRotationBroadcast()
          ..newEd25519Pk = broadcast.newEd25519Pk
          ..newMlDsaPk = broadcast.newMlDsaPk
          ..newX25519Pk = broadcast.newX25519Pk
          ..newMlKemPk = broadcast.newMlKemPk)
        .writeToBuffer();
    final oldSig = Uint8List.fromList(broadcast.oldSignatureEd25519);
    final sodium = SodiumFFI();
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      final pk = contact.ed25519Pk;
      if (pk == null) continue;
      try {
        if (sodium.verifyEd25519(dataToVerify, oldSig, pk)) {
          return Uint8List.fromList(contact.nodeId);
        }
      } catch (_) {/* keep scanning */}
    }
    return Uint8List(0);
  }

  /// Welle 5 Teil 4 (§2.4 receiver): entry point for raw V3 application
  /// packets routed to *this* identity by the daemon dispatcher
  /// (`service_daemon._onAppPacketDispatch`). Performs inner KEM-decap with
  /// this identity's User-KEM-private-keys, User-Sig-verify against the
  /// sender's contact-registry pubkeys, and forwards to
  /// [handleApplicationFrame] on success.
  ///
  /// Drop policy follows §2.4 [9-13]: silent drop on every Inner-verify
  /// failure. Sender-pubkey-miss = "unknown contact" → KEX-Gate (§8.2).
  /// Logged at debug; no error response on the wire.
  ///
  /// Returns an [AppFrameDispatchOutcome] so the multi-identity dispatcher
  /// (§2.4 step [9] try-loop, §3.1 daemon-global deviceID) can decide
  /// whether to try the next hosted identity. KEM-decap-failure means the
  /// frame was not addressed to this identity's User-KEM keypair — the
  /// caller MUST try other hosted identities. Any failure after a successful
  /// KEM-decap is final (the frame WAS for this identity but failed verify).
  Future<AppFrameDispatchOutcome> handleIncomingApplicationPacket(
    proto.NetworkPacketV3 packet,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) async {
    // Live-media receive fast path (Architecture §10.3 / Appendix B.2,
    // F-C amendment): CALL_AUDIO/VIDEO/GROUP_AUDIO/GROUP_VIDEO frames sent
    // by a device this identity already trusts as an active call's peer
    // (or a group-call participant) carry a PLAIN inner — no per-recipient
    // KEM, no user-sig — because the payload is already AES-GCM-
    // authenticated under the call/send key. Try that cheap path first;
    // ANY parse/validation failure falls through silently to the normal
    // KEM-decap path below (rolling-upgrade compat: older builds still
    // send KEM-wrapped live-media frames, and this identity may simply
    // not be the one hosting the call).
    final senderDeviceId = Uint8List.fromList(packet.senderDeviceId);
    if (_calls.isLiveMediaSender(senderDeviceId)) {
      final fastOutcome = await _tryLiveMediaFastPath(
        packet: packet,
        senderDeviceId: senderDeviceId,
        sourceAddr: sourceAddr,
        sourcePort: sourcePort,
        snapshot: snapshot,
      );
      if (fastOutcome != null) return fastOutcome;
    }

    final result = V3FrameCodec.decryptAndVerifyInner(
      innerPayload: Uint8List.fromList(packet.payload),
      ourUserX25519Sk: identity.x25519SecretKey,
      ourUserMlKemSk: identity.mlKemSecretKey,
      lookupUserEd25519Pk: (senderUserId) {
        final c = _contacts[bytesToHex(senderUserId)];
        return c?.ed25519Pk ?? Uint8List(0);
      },
      lookupUserMlDsaPk: (senderUserId) {
        final c = _contacts[bytesToHex(senderUserId)];
        return c?.mlDsaPk ?? Uint8List(0);
      },
      // §8.1.1 Trust-Bootstrap: when the sender is not yet in `_contacts`
      // (first CR / response to our CR before the contact transitioned to
      // `accepted`), the body carries the sender's User-Pubkeys inline.
      // Without this fallback the verify drops with `userSigInvalid` and
      // mutual contact-setup deadlocks (§8.1.1 explicitly allows the
      // pubkeys-from-body trust-bootstrap for these two message types).
      trustBootstrapPubkeys: (frame) {
        try {
          if (frame.messageType == proto.MessageTypeV3.MTV3_CONTACT_REQUEST) {
            final cr = proto.ContactRequestMsg.fromBuffer(frame.payload);
            if (cr.ed25519PublicKey.isNotEmpty && cr.mlDsaPublicKey.isNotEmpty) {
              return (
                edPk: Uint8List.fromList(cr.ed25519PublicKey),
                mlDsaPk: Uint8List.fromList(cr.mlDsaPublicKey),
              );
            }
          } else if (frame.messageType ==
              proto.MessageTypeV3.MTV3_CONTACT_REQUEST_RESPONSE) {
            final crr = proto.ContactRequestResponse.fromBuffer(frame.payload);
            if (crr.ed25519PublicKey.isNotEmpty && crr.mlDsaPublicKey.isNotEmpty) {
              return (
                edPk: Uint8List.fromList(crr.ed25519PublicKey),
                mlDsaPk: Uint8List.fromList(crr.mlDsaPublicKey),
              );
            }
          }
        } catch (_) {/* malformed body — keep silent drop */}
        return null;
      },
      lookupDelegatedKeys: (senderUserId) =>
          node.identityDhtHandler.getDelegatedKeys(senderUserId),
    );
    final frame = result.frame;
    if (frame == null) {
      // Distinguish "frame not for this identity" (KEM-decap failed → try
      // next hosted identity) from "decap succeeded but verify failed"
      // (final drop, no retry). Per §2.4 step [9] + Edit 2.
      final isKemMiss = result.error == InnerVerifyError.kemDecapFailed ||
          result.error == InnerVerifyError.kemVersionRejected;
      if (isKemMiss) {
        return AppFrameDispatchOutcome.notForThisIdentity;
      }
      _log.debug('V3 APP drop: ${result.error?.name ?? "unknown"} '
          'from device=${bytesToHex(Uint8List.fromList(packet.senderDeviceId)).substring(0, 8)}');
      return AppFrameDispatchOutcome.droppedAfterDecap;
    }

    // §2.4 step [14] (Edit 3): cross-validate Inner.recipientUserId against
    // the identity that successfully decapped. Defence-in-depth — should
    // never trigger for legitimate frames since both PKs derive from the
    // same User-Master-Seed.
    final inboundRecipient = Uint8List.fromList(frame.recipientUserId);
    if (!_constantTimeEq(inboundRecipient, identity.userId)) {
      _log.warn('V3 APP drop: KEM-decap succeeded under '
          '${identity.userIdHex.substring(0, 8)} but Inner.recipientUserId '
          '= ${bytesToHex(inboundRecipient).substring(0, 8)} (identity mismatch)');
      return AppFrameDispatchOutcome.droppedAfterDecap;
    }

    await handleApplicationFrame(
      frame: frame,
      senderDeviceId: senderDeviceId,
      sourceAddr: sourceAddr,
      sourcePort: sourcePort,
      snapshot: snapshot.withSenderUserId(
          Uint8List.fromList(frame.senderUserId)),
    );
    return AppFrameDispatchOutcome.delivered;
  }

  /// Live-media fast-path admission check (Architecture §10.3 / Appendix
  /// B.2, F-C amendment). Called from [handleIncomingApplicationPacket]
  /// only after [CallService.isLiveMediaSender] has cheaply confirmed
  /// `senderDeviceId` belongs to an active call's peer / participant.
  ///
  /// Tries to parse [packet]'s payload directly as a PLAIN
  /// [proto.ApplicationFrameV3] (no KEM, no zstd — the live-media sender
  /// side skips both, see [CallService.sendLiveMediaFrame]). Returns the
  /// dispatch outcome on acceptance, or `null` on ANY validation failure
  /// so the caller falls through to the normal KEM-decap path unchanged
  /// (rolling-upgrade compatibility with builds that still send
  /// KEM-wrapped live-media frames).
  Future<AppFrameDispatchOutcome?> _tryLiveMediaFastPath({
    required proto.NetworkPacketV3 packet,
    required Uint8List senderDeviceId,
    required InternetAddress sourceAddr,
    required int sourcePort,
    required SenderIdentitySnapshot snapshot,
  }) async {
    final proto.ApplicationFrameV3 frame;
    try {
      frame = proto.ApplicationFrameV3.fromBuffer(packet.payload);
    } catch (_) {
      return null;
    }

    if (!_liveMediaFastPathTypes.contains(frame.messageType)) return null;

    final recipient = Uint8List.fromList(frame.recipientUserId);
    if (!_constantTimeEq(recipient, identity.userId)) return null;

    final senderUserId = Uint8List.fromList(frame.senderUserId);
    if (!_calls.isKnownCallPeerUserId(senderUserId)) return null;

    _calls.logLiveMediaFastPathOnce(senderDeviceId);
    await handleApplicationFrame(
      frame: frame,
      senderDeviceId: senderDeviceId,
      sourceAddr: sourceAddr,
      sourcePort: sourcePort,
      snapshot: snapshot.withSenderUserId(senderUserId),
    );
    return AppFrameDispatchOutcome.delivered;
  }

  /// V3 receive-side dispatcher (Architecture v3.0 §2.6, receiver step 13).
  /// Called by the node after the outer Device-Sig has been verified, the
  /// inner KEM has been decrypted, and the User-Sig has been verified. The
  /// frame is trusted at this point — this method only routes to subsystem-
  /// specific handlers.
  ///
  /// Each handler dispatches to the subsystem-specific business logic.
  Future<void> handleApplicationFrame({
    required proto.ApplicationFrameV3 frame,
    required Uint8List senderDeviceId,
    required InternetAddress sourceAddr,
    required int sourcePort,
    required SenderIdentitySnapshot snapshot,
  }) async {
    // Receive-side dedup (Architecture §5.8 RUDP-Light): drop duplicate
    // frames silently. The same logical message can arrive via Direct +
    // Reed-Solomon reassembly + S&F mutual peer; without dedup the user
    // sees the message thrice and the sender gets three DELIVERY_RECEIPTs.
    // Inner.messageId is set by `sendToUser` (16-byte UUID v4); empty
    // messageIds fall through (transitional path until all senders are
    // wired — receipt-emit just won't happen for those).
    if (frame.messageId.isNotEmpty) {
      final msgIdHex = bytesToHex(Uint8List.fromList(frame.messageId));
      if (_processedMessageIds.contains(msgIdHex)) {
        _log.debug('handleApplicationFrame: duplicate ${frame.messageType.name} '
            'msgId=${msgIdHex.substring(0, 8)} — dropped');
        return;
      }
      _processedMessageIds.add(msgIdHex);
      while (_processedMessageIds.length > _processedMessageIdsCap) {
        _processedMessageIds.remove(_processedMessageIds.first);
      }
    }

    // §3.1 A-2: refresh sender's known deviceNodeId on every incoming
    // ApplicationFrame so sendToUser's contact.deviceNodeIds fallback
    // stays warm without relying on DHT resolution.
    final senderUserHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    final senderContact = _contacts[senderUserHex];
    if (senderContact != null) {
      final senderDeviceHex = bytesToHex(senderDeviceId);
      if (!senderContact.deviceNodeIds.contains(senderDeviceHex)) {
        senderContact.deviceNodeIds.add(senderDeviceHex);
        _saveContacts();
      }
    }

    // §5.1 F3′ (fourth outbox edge): this frame is fully verified, so the
    // sender is provably back online. If we hold parked outbox entries FOR
    // this user, flush them user-scoped now — the recipient reappearing is
    // the one case the sender-side edges (network-change, first-peer,
    // endpoint-confirmed) cannot see.
    _maybeFlushOutboxForSender(senderUserHex);

    switch (frame.messageType) {
      // Messaging — Cluster C2
      case proto.MessageTypeV3.MTV3_TEXT:
        _handleTextV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_INLINE:
        _handleMediaInlineV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE:
        _handleMediaAnnounceV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_REQUEST:
        // Fire-and-forget: chunk-stream may take a while; the dispatch loop
        // mustn't block on it.
        unawaited(_handleMediaRequestV3(frame, senderDeviceId, snapshot));
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_CHUNK:
        _handleMediaChunkV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_COMPLETE:
        _handleMediaCompleteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_MEDIA_REJECT:
        _handleMediaRejectV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_REACTION:
        _handleReactionV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_REPLY:
        _handleReplyV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_EDIT:
        _handleEditV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_DELETE:
        _handleDeleteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_VOICE_MESSAGE:
        _handleVoiceMessageV3(frame, senderDeviceId, snapshot);
        break;

      // Layer-Replies (ephemeral, ACK) — Cluster C1
      case proto.MessageTypeV3.MTV3_TYPING_INDICATOR:
        _handleTypingIndicatorV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_READ_RECEIPT:
        _handleReadReceiptV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_DELIVERY_RECEIPT:
        _handleDeliveryReceiptV3(frame, senderDeviceId, snapshot,
            sourceAddr: sourceAddr);
        break;

      // Recovery / Identity / Profile — Cluster C4
      case proto.MessageTypeV3.MTV3_RESTORE_BROADCAST:
        _handleRestoreBroadcastV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_RESTORE_RESPONSE:
        _handleRestoreResponseV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_IDENTITY_DELETED:
        _handleIdentityDeletedV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_PROFILE_UPDATE:
        _handleProfileUpdateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST:
        _handleKeyRotationBroadcastV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_KEY_ROTATION_ACK:
        _handleKeyRotationAckV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_ROTATION_REJECTION_ALERT:
        _handleRotationRejectionAlertV3(frame, senderDeviceId, snapshot);
        break;

      // Contact-Request — Cluster C4
      case proto.MessageTypeV3.MTV3_CONTACT_REQUEST:
        _handleContactRequestV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CONTACT_REQUEST_RESPONSE:
        _handleContactRequestResponseV3(frame, senderDeviceId, snapshot);
        break;

      // Groups — Cluster C4
      case proto.MessageTypeV3.MTV3_GROUP_CREATE:
        _handleGroupCreateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_GROUP_INVITE:
        _handleGroupInviteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_GROUP_LEAVE:
        _handleGroupLeaveV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_GROUP_KEY_UPDATE:
        _handleGroupKeyUpdateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST:
        _handleGroupMembershipResyncRequest(frame, senderDeviceId, snapshot);
        break;

      // Channels — Cluster C4
      case proto.MessageTypeV3.MTV3_CHANNEL_CREATE:
        _handleChannelCreateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_POST:
        _handleChannelPostV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_INVITE:
        _handleChannelInviteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_LEAVE:
        _handleChannelLeaveV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_ROLE_UPDATE:
        _handleChannelRoleUpdateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_BAD_BADGE_REPORT:
        _moderation.handleChannelBadBadgeReportV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_JURY_VOTE:
        _moderation.handleChannelJuryVoteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_MOD_DECISION:
        _moderation.handleChannelModDecisionV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_SUBSCRIBE_PROBE:
        _moderation.handleChannelSubscribeProbeV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_JOIN_REQUEST:
        _moderation.handleChannelJoinRequestV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_REPORT:
        _moderation.handleChannelReportV3(frame, senderDeviceId, snapshot);
        break;

      // Calls — Cluster C3 (delegated to CallService)
      case proto.MessageTypeV3.MTV3_CALL_INVITE:
        _calls.handleCallInviteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_ANSWER:
        _calls.handleCallAnswerV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_REJECT:
        _calls.handleCallRejectV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_HANGUP:
        _calls.handleCallHangupV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_ICE_CANDIDATE:
        _calls.handleIceCandidateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_REJOIN:
        _calls.handleCallRejoinV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_AUDIO:
        _calls.handleCallAudioV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_VIDEO:
        _calls.handleCallVideoV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_KEYFRAME_REQUEST:
        _calls.onKeyframeRequested?.call();
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_AUDIO:
        _calls.handleCallGroupAudioV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_VIDEO:
        _calls.handleCallGroupVideoV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_LEAVE:
        _calls.handleCallGroupLeaveV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_KEY_ROTATE:
        _calls.handleCallGroupKeyRotateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_SENDER_KEY:
        _calls.groupCallManager.handleGroupCallSenderKeyV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_RTT_PING:
        _calls.handleCallRttPingV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_RTT_PONG:
        _calls.handleCallRttPongV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_TREE_UPDATE:
        _calls.handleCallTreeUpdateV3(frame, senderDeviceId, snapshot);
        break;

      // Wave 2B.3: PEER_LIST_*, DHT_*, ROUTE_UPDATE, REACHABILITY_*, HOLE_PUNCH_*
      // are §2.3.5 InfrastructureFrames handled in cleona_node.dart's
      // `_dispatchInfrastructureFrameLocal`. They never arrive as
      // ApplicationFrames on the wire — the V3 hard-cut routes them as
      // InfrastructureFrames — so cases here would be unreachable.
      //
      // FRAGMENT_* and PEER_STORE_* carry encrypted user-content and are
      // handled by service-layer Infra-hooks in service_daemon.dart
      // (handleIncomingFragmentStoreInfra etc.). They are not dispatched
      // through this ApplicationFrame switch either.

      // Chat-Config — Cluster C4
      case proto.MessageTypeV3.MTV3_CHAT_CONFIG_UPDATE:
        _handleChatConfigUpdateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHAT_CONFIG_RESPONSE:
        _handleChatConfigResponseV3(frame, senderDeviceId, snapshot);
        break;

      // (ROUTE_UPDATE, REACHABILITY_*, RELAY_*, HOLE_PUNCH_* — see comment
      //  on Wave 2B.3 above; all dispatched in cleona_node.dart.)

      // Identity-Resolution (§2.2.4) — Cluster C4
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_PUBLISH:
        _handleIdentityAuthPublishV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RETRIEVE:
        _handleIdentityAuthRetrieveV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_IDENTITY_AUTH_RESPONSE:
        _handleIdentityAuthResponseV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_PUBLISH:
        _handleIdentityLivePublishV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RETRIEVE:
        _handleIdentityLiveRetrieveV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_IDENTITY_LIVE_RESPONSE:
        _handleIdentityLiveResponseV3(frame, senderDeviceId, snapshot);
        break;

      // Multi-Device — Cluster C4
      case proto.MessageTypeV3.MTV3_TWIN_SYNC:
        _handleTwinSyncV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_DEVICE_PAIR_REQUEST:
        _handleDevicePairRequestV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_DEVICE_PAIR_APPROVE:
        _handleDevicePairApproveV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_DEVICE_REVOCATION:
        _handleDeviceRevocationV3(frame, senderDeviceId, snapshot);
        break;

      // Calendar — Cluster C4
      case proto.MessageTypeV3.MTV3_CALENDAR_INVITE:
        _calendarProto.handleCalendarInviteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALENDAR_RSVP:
        _calendarProto.handleCalendarRsvpV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALENDAR_UPDATE:
        _calendarProto.handleCalendarUpdateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALENDAR_DELETE:
        _calendarProto.handleCalendarDeleteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_FREE_BUSY_REQUEST:
        _calendarProto.handleFreeBusyRequestV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_FREE_BUSY_RESPONSE:
        _calendarProto.handleFreeBusyResponseV3(frame, senderDeviceId, snapshot);
        break;

      // Polls — Cluster C4
      case proto.MessageTypeV3.MTV3_POLL_CREATE:
        _polls.handlePollCreateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_POLL_VOTE:
        _polls.handlePollVoteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS:
        _polls.handlePollVoteAnonymousV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_POLL_UPDATE:
        _polls.handlePollUpdateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_POLL_SNAPSHOT:
        _polls.handlePollSnapshotV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_POLL_REVOKE:
        _polls.handlePollRevokeV3(frame, senderDeviceId, snapshot);
        break;

      // In-Call Collaboration (§25, geplant) — Cluster C3 (delegated to CallService)
      case proto.MessageTypeV3.MTV3_WHITEBOARD_STROKE:
        _calls.handleWhiteboardStrokeV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_WHITEBOARD_PAGE:
        _calls.handleWhiteboardPageV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_FILE_EXCHANGE:
        _calls.handleFileExchangeV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CLIPBOARD_EXCHANGE:
        _calls.handleClipboardExchangeV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_SCREEN_SHARE_FRAME:
        _calls.handleScreenShareFrameV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_CHAT:
        _calls.handleCallChatV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_REMOTE_CONTROL_INPUT:
        _calls.handleRemoteControlInputV3(frame, senderDeviceId, snapshot);
        break;

      default:
        _log.warn('handleApplicationFrame: unhandled type ${frame.messageType}');
    }

    if (_isUserMessage(frame.messageType)) {
      node.statsCollector.addMessageReceived();
    }

    // Auto-DELIVERY_RECEIPT (Architecture §5.8 RUDP-Light): for ack-worthy
    // ApplicationFrame types, emit a receipt back to the sender's UserID
    // with the inner messageId. The sender's `_handleDeliveryReceiptV3`
    // upgrades the matching outgoing UiMessage from `sent` to `delivered`.
    // Skipped when:
    //   - messageId empty (sender hasn't been migrated to set inner.messageId),
    //   - senderUserId empty,
    //   - sender is ourselves (loopback / self-send won't have a contact).
    if (AckTracker.isAckWorthyV3(frame.messageType) &&
        frame.messageId.isNotEmpty &&
        frame.senderUserId.isNotEmpty) {
      final senderUserId = Uint8List.fromList(frame.senderUserId);
      if (!_constantTimeEq(senderUserId, identity.userId)) {
        _sendDeliveryReceiptV3(
          recipientUserId: senderUserId,
          messageId: Uint8List.fromList(frame.messageId),
          senderDeviceId: senderDeviceId,
        );
      }
    }
  }

  /// Emit a V3 DELIVERY_RECEIPT (Architecture §5.8 RUDP-Light) for a
  /// successfully received ApplicationFrame. Fire-and-forget — receipt
  /// loss is tolerable (sender's AckTracker times out and triggers its
  /// own retry / route-down logic).
  ///
  /// [senderDeviceId] is the concrete device that sent the frame being
  /// acknowledged (from `handleApplicationFrame`'s outer packet). On a
  /// multi-device account, `sendToUser`'s user-level fan-out may otherwise
  /// pick a *different*, stale cached device of the same user — the receipt
  /// would then never reach the device whose AckTracker is actually waiting.
  /// Targeting the exact device closes that gap without any extra traffic
  /// (still exactly one receipt).
  void _sendDeliveryReceiptV3({
    required Uint8List recipientUserId,
    required Uint8List messageId,
    Uint8List? senderDeviceId,
  }) {
    final receipt = proto.DeliveryReceipt()
      ..messageId = messageId
      ..deliveredAt = Int64(DateTime.now().millisecondsSinceEpoch);
    sendToUser(
      recipientUserId: recipientUserId,
      messageType: proto.MessageTypeV3.MTV3_DELIVERY_RECEIPT,
      payload: receipt.writeToBuffer(),
      targetDeviceId:
          (senderDeviceId != null && senderDeviceId.isNotEmpty)
              ? senderDeviceId
              : null,
    );
  }

  // ──────────────────────────── V3 Handler Stubs ────────────────────────────
  // Planned/deferred message types with empty handlers (silent no-op).
  // Categories: §10.5 (in-call collaboration), moderation Phase 2,
  // infra-dispatched types (switch exhaustiveness only), dead proto types.

  // C1 — Layer-Replies (V3 migration of _handleDeliveryReceipt /
  // _handleReadReceipt / _handleEphemeral-typing). The V3 frame has no
  // groupId field — group fan-out for these ephemeral types lands with
  // C4-Groups; here the conversation lookup is DM-style on
  // bytesToHex(senderUserId), with the TypingIndicator carrying a
  // conversationId field for forward-compat.
  //
  // The V3-Neuerung: senderDeviceId is now available for per-device ACK
  // bookkeeping. The C1 cluster does not yet track per-device ACKs
  // (AckTracker is keyed by recipient nodeId / route, not by device); the
  // parameter is accepted and logged for traceability so future Welle-3
  // wiring is a one-line edit.

  /// V3 DELIVERY_RECEIPT: sender side marks the outgoing message as
  /// `delivered`. Conversation lookup is on senderUserId-hex (DM); group
  /// receipts are deferred to C4-Groups.
  void _handleDeliveryReceiptV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot,
      {InternetAddress? sourceAddr}) {
    try {
      final receipt = proto.DeliveryReceipt.fromBuffer(frame.payload);
      if (receipt.messageId.isEmpty) return;
      final msgIdHex = bytesToHex(Uint8List.fromList(receipt.messageId));
      final conversationId =
          bytesToHex(Uint8List.fromList(frame.senderUserId));

      // Bridge to AckTracker (RUDP-Light §2.4.5): consume the pending entry
      // registered by `sendToUser` so the route-failure / route-down logic
      // (3× consecutive timeout → markRouteDown + Poison Reverse) and the
      // address-success bookkeeping can fire. `wasDirect` heuristic:
      // relay-delivered receipts arrive with from=0.0.0.0
      // (no source address known), direct UDP receipts carry the recipient's
      // real address. confirmRoute (DV) only fires for direct receipts.
      final wasDirect =
          sourceAddr != null && sourceAddr.address != '0.0.0.0';
      // §3.1 B-1: pass senderDeviceId (deviceId) so the ACK→DV bridge
      // operates on routing-layer IDs, not identity-layer IDs.
      node.ackTracker.handleAck(
          msgIdHex, bytesToHex(senderDeviceId), wasDirect: wasDirect);

      // §5.8 Crash-safety: remove outbox entry for delivered message.
      if (_outbox.containsKey(msgIdHex)) {
        _outbox.remove(msgIdHex);
        _saveOutbox();
      }

      final conv = conversations[conversationId];
      if (conv == null) return;
      for (final msg in conv.messages) {
        if (msg.id == msgIdHex &&
            msg.isOutgoing &&
            (msg.status == MessageStatus.sent || msg.status == MessageStatus.queuedOffline)) {
          msg.status = MessageStatus.delivered;
          _saveConversations();
          onStateChanged?.call();
          break;
        }
      }
    } catch (e) {
      _log.warn('handleDeliveryReceiptV3: parse fail: $e '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} '
          'device=${_hexShort(senderDeviceId)})');
    }
  }

  /// V3 READ_RECEIPT: mark outgoing as `read` and stamp readAt for expiry.
  /// Conversation lookup is DM-style (senderUserId-hex). Backward-compat
  /// with raw-message-ID payloads is dropped in V3 — V3 senders always
  /// emit a structured ReadReceipt protobuf.
  void _handleReadReceiptV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final receipt = proto.ReadReceipt.fromBuffer(frame.payload);
      if (receipt.messageId.isEmpty) return;
      final msgIdHex = bytesToHex(Uint8List.fromList(receipt.messageId));
      final readAt = receipt.readAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(receipt.readAt.toInt())
          : DateTime.now();
      final conversationId =
          bytesToHex(Uint8List.fromList(frame.senderUserId));
      final conv = conversations[conversationId];
      if (conv == null) return;
      for (final msg in conv.messages) {
        if (msg.id == msgIdHex && msg.isOutgoing) {
          msg.status = MessageStatus.read;
          msg.readAt ??= readAt;
          _saveConversations();
          onReadReceiptReceived?.call(conversationId, msgIdHex);
          break;
        }
      }
      onStateChanged?.call();
    } catch (e) {
      _log.warn('handleReadReceiptV3: parse fail: $e '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} '
          'device=${_hexShort(senderDeviceId)})');
    }
  }

  /// V3 TYPING_INDICATOR: animate typing dots in UI. Per-chat config
  /// (`typingIndicators`) gates the indicator on the receiver side.
  /// V3-Neuerung: empty/unparseable payload no longer treated as
  /// is_typing=true — V3 senders always send a structured TypingIndicator.
  void _handleTypingIndicatorV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      // Parse first so that the convId-from-payload (group support) lands
      // even when the per-DM conversation hasn't materialised yet.
      bool isTyping = true;
      String convIdFromPayload = '';
      if (frame.payload.isNotEmpty) {
        final indicator = proto.TypingIndicator.fromBuffer(frame.payload);
        isTyping = indicator.isTyping;
        convIdFromPayload = indicator.conversationId;
      }
      final conversationId =
          convIdFromPayload.isNotEmpty ? convIdFromPayload : senderHex;
      final conv = conversations[conversationId];
      // Per-chat opt-out: receiver suppresses indicator if disabled.
      if (conv != null && !conv.config.typingIndicators) return;

      if (isTyping) {
        _typingTimestamps[senderHex] = DateTime.now();
      } else {
        _typingTimestamps.remove(senderHex);
      }
      onStateChanged?.call();
    } catch (e) {
      _log.warn('handleTypingIndicatorV3: parse fail: $e '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} '
          'device=${_hexShort(senderDeviceId)})');
    }
  }

  // C2 — Messaging
  //
  // Pattern (parallel zur C1-Migration in _handleDeliveryReceiptV3 etc.):
  //   - Inner-KEM-Decrypt + User-Sig-Verify hat das Frame VOR Aufruf bereits
  //     bestanden (cleona_node.dart). Hier nur frame.payload parsen +
  //     UI-State updaten + Notifications.
  //   - Multi-Identity / Group-Fanout: ApplicationFrameV3.group_id (Field 17)
  //     trägt die Group/Channel-Conversation-ID für Pairwise-Fan-out (jeder
  //     Member kriegt seinen eigenen sendToUser-Call mit identischem
  //     group_id). Receiver liest frame.groupId und dispatcht in den passenden
  //     Group/Channel-Tab; leer = DM auf Sender-Hex.

  /// GM-2 (§9.1.4): centralized group-post gatekeeper. Returns null if the
  /// post should be dropped (non-member). Returns true if a split-view
  /// anomaly was detected (same/lower epoch, different hash).
  bool? _checkGroupPostMembership(proto.ApplicationFrameV3 frame, String senderHex) {
    if (frame.groupId.isEmpty) return false;
    final groupIdHex = bytesToHex(Uint8List.fromList(frame.groupId));
    final group = _groups[groupIdHex];
    if (group == null) return false;

    if (!group.members.containsKey(senderHex)) {
      _log.warn('GM-2: group post from non-member ${senderHex.substring(0, 8)} '
          'in "${group.name}" — dropped');
      return null;
    }

    final wireEpoch = frame.groupMembershipEpoch.toInt();
    if (wireEpoch <= 0) return false; // legacy sender, no tag

    final wireHash = frame.groupMembershipHash;
    if (wireHash.isEmpty) return false;

    final localEpoch = group.membershipEpoch;
    final localHash = _computeMembershipHash(localEpoch, groupIdHex, group.members);

    if (wireEpoch == localEpoch && _bytesEqual(Uint8List.fromList(wireHash), localHash)) {
      return false; // match
    }

    if (wireEpoch > localEpoch) {
      // sender has newer membership — edge-triggered resync to owner
      final prevRequested = _resyncRequestedAtEpoch[groupIdHex] ?? 0;
      if (wireEpoch > prevRequested) {
        _resyncRequestedAtEpoch[groupIdHex] = wireEpoch;
        _sendResyncRequest(group);
      }
      return false; // not a split-view, just stale local state
    }

    // same or lower epoch, different hash → split-view anomaly
    _log.warn('GM-2: SPLIT-VIEW in "${group.name}" — '
        'local epoch=$localEpoch hash=${bytesToHex(localHash).substring(0, 16)}, '
        'wire epoch=$wireEpoch hash=${bytesToHex(Uint8List.fromList(wireHash)).substring(0, 16)} '
        'from ${senderHex.substring(0, 8)}');
    return true;
  }

  void _sendResyncRequest(GroupInfo group) {
    final ownerHex = group.ownerNodeIdHex;
    if (ownerHex == identity.userIdHex) return; // we are owner, no need
    final req = proto.GroupMembershipResyncRequest()
      ..groupId = hexToBytes(group.groupIdHex)
      ..localEpoch = Int64(group.membershipEpoch);
    sendToUser(
      recipientUserId: hexToBytes(ownerHex),
      messageType: proto.MessageTypeV3.MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST,
      payload: req.writeToBuffer(),
      groupId: hexToBytes(group.groupIdHex),
    );
    _log.info('GM-2: RESYNC_REQUEST sent to owner ${ownerHex.substring(0, 8)} '
        'for group "${group.name}" (local epoch=${group.membershipEpoch})');
  }

  void _sendChannelResyncRequest(ChannelInfo channel) {
    final ownerHex = channel.ownerNodeIdHex;
    if (ownerHex == identity.userIdHex) return;
    final req = proto.GroupMembershipResyncRequest()
      ..groupId = hexToBytes(channel.channelIdHex)
      ..localEpoch = Int64(channel.membershipEpoch);
    sendToUser(
      recipientUserId: hexToBytes(ownerHex),
      messageType: proto.MessageTypeV3.MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST,
      payload: req.writeToBuffer(),
      groupId: hexToBytes(channel.channelIdHex),
    );
    _log.info('GM-4: RESYNC_REQUEST sent to channel owner ${ownerHex.substring(0, 8)} '
        'for "${channel.name}" (local epoch=${channel.membershipEpoch})');
  }

  void _handleGroupMembershipResyncRequest(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final req = proto.GroupMembershipResyncRequest.fromBuffer(frame.payload);
      final entityIdHex = bytesToHex(Uint8List.fromList(req.groupId));
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

      // GM-4: dual-mode — handle both groups and channels
      final group = _groups[entityIdHex];
      final channel = _channels[entityIdHex];
      if (group == null && channel == null) return;

      if (group != null) {
        if (group.ownerNodeIdHex != identity.userIdHex) {
          _log.debug('GM-2: RESYNC_REQUEST for "$entityIdHex" but we are not owner — ignoring');
          return;
        }
        if (!group.members.containsKey(senderHex)) {
          _log.warn('GM-2: RESYNC_REQUEST from non-member ${senderHex.substring(0, 8)} — dropped');
          return;
        }
        final reqEpoch = req.localEpoch.toInt();
        if (reqEpoch >= group.membershipEpoch) {
          _log.debug('GM-2: RESYNC_REQUEST from ${senderHex.substring(0, 8)} '
              'already at epoch $reqEpoch (ours=${group.membershipEpoch}) — no resync needed');
          return;
        }
        _log.info('GM-2: RESYNC_REQUEST from ${senderHex.substring(0, 8)} '
            'epoch $reqEpoch < ${group.membershipEpoch} — sending GROUP_INVITE');
        unawaited(_broadcastGroupUpdate(group));
      } else {
        if (channel!.ownerNodeIdHex != identity.userIdHex) {
          _log.debug('GM-4: channel RESYNC_REQUEST for "$entityIdHex" but we are not owner — ignoring');
          return;
        }
        if (!channel.members.containsKey(senderHex)) {
          _log.warn('GM-4: channel RESYNC_REQUEST from non-member ${senderHex.substring(0, 8)} — dropped');
          return;
        }
        final reqEpoch = req.localEpoch.toInt();
        if (reqEpoch >= channel.membershipEpoch) {
          _log.debug('GM-4: channel RESYNC_REQUEST from ${senderHex.substring(0, 8)} '
              'already at epoch $reqEpoch (ours=${channel.membershipEpoch}) — no resync needed');
          return;
        }
        _log.info('GM-4: channel RESYNC_REQUEST from ${senderHex.substring(0, 8)} '
            'epoch $reqEpoch < ${channel.membershipEpoch} — sending CHANNEL_INVITE');
        unawaited(_broadcastChannelUpdate(channel));
      }
    } catch (e) {
      _log.warn('GM-2/4: RESYNC_REQUEST parse fail: $e');
    }
  }

  /// V3 TEXT: TextMessageV3-payload. Reply-fields (replyToMessageId +
  /// replyToSnippet) live on the proto sub-message. Link-Preview travels
  /// in `tm.linkPreview` (sender-side only — the receiver renders the card
  /// from the embedded data and MUST NOT issue a network request).
  void _handleTextV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final tm = proto.TextMessageV3.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final msgId = bytesToHex(Uint8List.fromList(frame.messageId));
      // V3: ApplicationFrameV3.group_id (Field 17) trägt die Group/Channel-
      // Conversation-ID für Pairwise-Fan-out. Leer = DM auf Sender-Hex.
      final conversationId = frame.groupId.isNotEmpty
          ? bytesToHex(Uint8List.fromList(frame.groupId))
          : senderHex;

      // GM-2 (§9.1.4): centralized membership gatekeeper
      final mismatchResult = _checkGroupPostMembership(frame, senderHex);
      if (mismatchResult == null) return; // non-member, dropped
      final isMembershipMismatch = mismatchResult;

      // Reply metadata: hex-encode the wire bytes; resolve sender display-
      // name from the local conversation (best-effort; UI falls back to the
      // snippet text if the original bubble is no longer retained).
      String? replyToMessageId;
      String? replyToText;
      String? replyToSender;
      if (tm.replyToMessageId.isNotEmpty) {
        replyToMessageId =
            bytesToHex(Uint8List.fromList(tm.replyToMessageId));
        if (tm.replyToSnippet.isNotEmpty) replyToText = tm.replyToSnippet;
        final origConv = conversations[conversationId];
        if (origConv != null) {
          final orig = origConv.messages
              .where((m) => m.id == replyToMessageId)
              .firstOrNull;
          if (orig != null) {
            replyToSender = _contacts[orig.senderNodeIdHex]?.displayName ??
                orig.senderNodeIdHex.substring(0, 8);
            // If the snippet on the wire was empty (older sender or trimmed),
            // fall back to the text we still have locally.
            replyToText ??= orig.text.length > 200
                ? orig.text.substring(0, 200)
                : orig.text;
          }
        }
      }

      final msg = UiMessage(
        id: msgId,
        conversationId: conversationId,
        senderNodeIdHex: senderHex,
        text: tm.text,
        timestamp: DateTime.fromMillisecondsSinceEpoch(frame.timestampMs.toInt()),
        type: UiMessageType.text,
        status: MessageStatus.delivered,
        isOutgoing: false,
        readAt: DateTime.now(),
        replyToMessageId: replyToMessageId,
        replyToText: replyToText,
        replyToSender: replyToSender,
        membershipMismatch: isMembershipMismatch,
      );

      // Link preview from sender (Architecture §2.3.4). We trust the
      // sender-supplied data and DO NOT fetch — empty url means no preview.
      if (tm.hasLinkPreview() && tm.linkPreview.url.isNotEmpty) {
        final lp = tm.linkPreview;
        msg.linkPreviewUrl = lp.url;
        msg.linkPreviewTitle = lp.title.isNotEmpty ? lp.title : null;
        msg.linkPreviewDescription =
            lp.description.isNotEmpty ? lp.description : null;
        msg.linkPreviewSiteName =
            lp.siteName.isNotEmpty ? lp.siteName : null;
        if (lp.thumbnail.isNotEmpty) {
          msg.linkPreviewThumbnailBase64 = base64Encode(lp.thumbnail);
        }
      }

      final isChannel = _channels.containsKey(conversationId);
      final isGroup = _groups.containsKey(conversationId);
      final isNew = _addMessageToConversation(conversationId, msg,
          isGroup: isGroup, isChannel: isChannel);
      if (isNew && !_shouldSuppressNotification(
          conversationId, msg.timestamp.millisecondsSinceEpoch)) {
        notificationSound.playMessageSound();
        notificationSound.vibrate(VibrationType.message);
        final senderName =
            _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        _postAndroidNotification(
            senderName,
            tm.text.length > 100 ? '${tm.text.substring(0, 100)}...' : tm.text,
            conversationId);
        _lastNotifiedAt[conversationId] = DateTime.now();
      }
      _log.info(
          'TEXT-V3 from ${senderHex.substring(0, 8)} (device=${_hexShort(senderDeviceId)}): '
          '${tm.text.length > 50 ? tm.text.substring(0, 50) : tm.text}');
    } catch (e) {
      _log.warn('handleTextV3: parse fail: $e '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))})');
    }
  }

  /// V3 MEDIA_INLINE: ≤256KB inline payload (raw bytes oder VoicePayload-
  /// proto je nach MIME). frame.contentMetadata trägt MIME, filename, size.
  void _handleMediaInlineV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final mismatchResult = _checkGroupPostMembership(frame, senderHex);
      if (mismatchResult == null) return;
      final isMembershipMismatch = mismatchResult;
      final msgId = bytesToHex(Uint8List.fromList(frame.messageId));
      final conversationId = frame.groupId.isNotEmpty
          ? bytesToHex(Uint8List.fromList(frame.groupId))
          : senderHex;
      final metadata = frame.contentMetadata;

      // Voice: VoicePayload-Wrapper.
      Uint8List actualFileData = Uint8List.fromList(frame.payload);
      String? transcriptText;
      String? transcriptLanguage;
      double? transcriptConfidence;
      final isVoice = metadata.mimeType.startsWith('audio/');
      if (isVoice) {
        try {
          final voicePayload = proto.VoicePayload.fromBuffer(frame.payload);
          if (voicePayload.audioData.isNotEmpty) {
            actualFileData = Uint8List.fromList(voicePayload.audioData);
            if (voicePayload.transcriptText.isNotEmpty) {
              transcriptText = voicePayload.transcriptText;
              transcriptLanguage = voicePayload.transcriptLanguage;
              transcriptConfidence = voicePayload.transcriptConfidence.toDouble();
            }
          }
        } catch (_) {/* raw audio bytes */}
      }

      final mediaDir = Directory('$profileDir/media');
      if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
      final filename =
          metadata.filename.isNotEmpty ? metadata.filename : 'file_$msgId';
      final savePath = _uniqueMediaPath(mediaDir.path, filename);
      File(savePath).writeAsBytesSync(actualFileData);

      final thumbnailB64 =
          metadata.thumbnail.isNotEmpty ? base64Encode(metadata.thumbnail) : null;
      final effectiveThumbnail = thumbnailB64 ??
          (metadata.mimeType.startsWith('image/') &&
                  actualFileData.length <= 100 * 1024
              ? base64Encode(actualFileData)
              : null);

      final msg = UiMessage(
        id: msgId,
        conversationId: conversationId,
        senderNodeIdHex: senderHex,
        text: filename,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(frame.timestampMs.toInt()),
        type: _msgTypeFromMime(metadata.mimeType),
        status: MessageStatus.delivered,
        isOutgoing: false,
        filePath: savePath,
        mimeType: metadata.mimeType,
        fileSize: actualFileData.length,
        filename: filename,
        thumbnailBase64: effectiveThumbnail,
        mediaState: MediaDownloadState.completed,
        transcriptText: transcriptText,
        transcriptLanguage: transcriptLanguage,
        transcriptConfidence: transcriptConfidence,
        membershipMismatch: isMembershipMismatch,
      );

      final isGroup = _groups.containsKey(conversationId);
      final isNew = _addMessageToConversation(conversationId, msg, isGroup: isGroup);
      if (isNew && !_shouldSuppressNotification(
          conversationId, msg.timestamp.millisecondsSinceEpoch)) {
        notificationSound.playMessageSound();
        notificationSound.vibrate(VibrationType.message);
        final senderName =
            _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        final label = metadata.mimeType.startsWith('image/')
            ? '📷 Bild'
            : metadata.mimeType.startsWith('video/')
                ? '🎬 Video'
                : metadata.mimeType.startsWith('audio/')
                    ? '🎵 Audio'
                    : '📎 Datei';
        _postAndroidNotification(senderName, label, conversationId);
        _lastNotifiedAt[conversationId] = DateTime.now();
      }
      _log.info(
          '[E2E media-inline-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${_hexShort(senderDeviceId)} msgId=${msgId.substring(0, 8)} '
          'filename=$filename size=${actualFileData.length} mime=${metadata.mimeType}');

      // Local transcription fallback for voice without source-side transcript.
      if (isVoice && transcriptText == null) {
        _voiceTranscription?.enqueueTranscription(
          messageId: msgId,
          audioFilePath: savePath,
        );
      }
    } catch (e) {
      _log.warn('handleMediaInlineV3: failed: $e '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))})');
    }
  }

  /// V3 MEDIA_ANNOUNCE: Stage-1 announcement of >256KB media. Receiver
  /// either auto-accepts (size+mime policy) or shows a placeholder for
  /// manual click. payload is empty (metadata lives in frame.contentMetadata).
  void _handleMediaAnnounceV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final mismatchResult = _checkGroupPostMembership(frame, senderHex);
      if (mismatchResult == null) return;
      final isMembershipMismatch = mismatchResult;
      final msgId = bytesToHex(Uint8List.fromList(frame.messageId));
      final conversationId = frame.groupId.isNotEmpty
          ? bytesToHex(Uint8List.fromList(frame.groupId))
          : senderHex;
      final metadata = frame.contentMetadata;

      final thumbnailB64 = metadata.thumbnail.isNotEmpty
          ? base64Encode(metadata.thumbnail)
          : null;

      final msg = UiMessage(
        id: msgId,
        conversationId: conversationId,
        senderNodeIdHex: senderHex,
        text: metadata.filename,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(frame.timestampMs.toInt()),
        type: _msgTypeFromMime(metadata.mimeType),
        status: MessageStatus.delivered,
        isOutgoing: false,
        mimeType: metadata.mimeType,
        fileSize: metadata.fileSize.toInt(),
        filename: metadata.filename,
        thumbnailBase64: thumbnailB64,
        mediaState: MediaDownloadState.announced,
        membershipMismatch: isMembershipMismatch,
      );

      final isGroup = _groups.containsKey(conversationId);
      _addMessageToConversation(conversationId, msg, isGroup: isGroup);
      _log.info(
          '[E2E media-announce-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${_hexShort(senderDeviceId)} msgId=${msgId.substring(0, 8)} '
          'filename=${metadata.filename} size=${metadata.fileSize} '
          'mime=${metadata.mimeType}');

      // Auto-accept policy per Architecture §3.4.3. Fires the same V3
      // MEDIA_REQUEST path the manual UI click uses.
      final autoOk = _mediaSettings.shouldAutoDownload(
          metadata.mimeType, metadata.fileSize.toInt());
      if (autoOk) {
        _log.info(
            'media-announce-v3 auto-accept: triggering MEDIA_REQUEST for '
            'msgId=${msgId.substring(0, 8)}');
        unawaited(acceptMediaDownload(conversationId, msgId));
      }
    } catch (e) {
      _log.warn('handleMediaAnnounceV3: failed: $e '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))})');
    }
  }

  /// V3 MEDIA_REQUEST: Stage-2 trigger — receiver asks the sender to push
  /// the actual content. payload carries the original message_id (16 bytes)
  /// the requester wants. Sender looks up the pending file and emits a
  /// MediaChunkV3 stream (≤32KB per chunk) + a final MediaCompleteV3 with
  /// SHA-256 of the assembled bytes.
  Future<void> _handleMediaRequestV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) async {
    try {
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      // V3-payload: opaque bytes = original message_id we should ship.
      final originalMsgIdBytes = Uint8List.fromList(frame.payload);
      final originalMsgId = bytesToHex(originalMsgIdBytes);
      final filePath = _pendingMediaSends[originalMsgId];
      _log.info(
          '[E2E media-request-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${_hexShort(senderDeviceId)} '
          'wantsMsgId=${originalMsgId.length >= 8 ? originalMsgId.substring(0, 8) : originalMsgId} '
          'pending=${filePath != null}');
      if (filePath == null) {
        final recovered = _recoverPendingMediaPath(originalMsgId);
        if (recovered == null) {
          _log.warn(
              'media-request-v3: no pending media for ${originalMsgId.length >= 8 ? originalMsgId.substring(0, 8) : originalMsgId}');
          return;
        }
        _pendingMediaSends[originalMsgId] = recovered;
        _savePendingMediaSends();
        _log.info('media-request-v3: recovered pending path from conversation history');
      }
      final resolvedPath = _pendingMediaSends[originalMsgId]!;
      final file = File(resolvedPath);
      if (!file.existsSync()) {
        _log.warn('media-request-v3: pending file vanished: $resolvedPath');
        _pendingMediaSends.remove(originalMsgId);
        _savePendingMediaSends();
        return;
      }

      final fileBytes = file.readAsBytesSync();
      final contentHash = SodiumFFI().sha256(fileBytes);

      // Chunk into ≤32KB pieces. Each chunk is its own ApplicationFrameV3
      // shipped via sendToUser → per-chunk KEM-encrypted (Spec §5.7 Stage 2).
      const chunkSize = 32 * 1024;
      final totalChunks = (fileBytes.length + chunkSize - 1) ~/ chunkSize;
      final recipientUserId = Uint8List.fromList(frame.senderUserId);

      _log.info(
          '[E2E media-stage2-send-v3] msgId=${originalMsgId.substring(0, 8)} '
          'recipient=${senderHex.substring(0, 8)} size=${fileBytes.length} '
          'chunks=$totalChunks');

      for (var idx = 0; idx < totalChunks; idx++) {
        final start = idx * chunkSize;
        final end = (start + chunkSize > fileBytes.length)
            ? fileBytes.length
            : start + chunkSize;
        final chunkData = fileBytes.sublist(start, end);
        final chunk = proto.MediaChunkV3()
          ..mediaId = originalMsgIdBytes
          ..chunkIndex = idx
          ..totalChunks = totalChunks
          ..data = chunkData;
        final ok = await sendToUser(
          recipientUserId: recipientUserId,
          messageType: proto.MessageTypeV3.MTV3_MEDIA_CHUNK,
          payload: Uint8List.fromList(chunk.writeToBuffer()),
        );
        if (!ok) {
          _log.warn(
              'media-request-v3: chunk $idx/$totalChunks send FAILED — abort');
          return;
        }
      }

      final complete = proto.MediaCompleteV3()
        ..mediaId = originalMsgIdBytes
        ..contentHash = contentHash
        ..totalSize = Int64(fileBytes.length);
      final okComplete = await sendToUser(
        recipientUserId: recipientUserId,
        messageType: proto.MessageTypeV3.MTV3_MEDIA_COMPLETE,
        payload: Uint8List.fromList(complete.writeToBuffer()),
      );
      _log.info(
          '[E2E media-stage2-send-done-v3] msgId=${originalMsgId.substring(0, 8)} '
          'complete-ok=$okComplete');

      // Sender finished — clear pending entry. (Receiver-side hash-check
      // protects against truncation; we don't keep retries here.)
      if (okComplete) {
        _pendingMediaSends.remove(originalMsgId);
        _savePendingMediaSends();
      }
    } catch (e, st) {
      _log.warn('handleMediaRequestV3: failed: $e\n$st '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))})');
    }
  }

  /// V3 MEDIA_CHUNK: receiver buffers the chunk in `_mediaChunkBuffers`
  /// keyed by mediaIdHex. Reassembly + file-write happens in the matching
  /// MEDIA_COMPLETE handler.
  void _handleMediaChunkV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final chunk = proto.MediaChunkV3.fromBuffer(frame.payload);
      final mediaIdHex = bytesToHex(Uint8List.fromList(chunk.mediaId));
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

      final buf = _mediaChunkBuffers.putIfAbsent(
          mediaIdHex, () => _MediaChunkBuffer(chunk.totalChunks));
      if (buf.totalChunks != chunk.totalChunks) {
        _log.warn(
            'media-chunk-v3: totalChunks mismatch for $mediaIdHex '
            '(buf=${buf.totalChunks} chunk=${chunk.totalChunks}) — '
            'dropping chunk');
        return;
      }
      if (chunk.chunkIndex >= buf.totalChunks) {
        _log.warn(
            'media-chunk-v3: out-of-bounds index ${chunk.chunkIndex}/${buf.totalChunks} '
            'for $mediaIdHex — drop');
        return;
      }
      buf.chunks[chunk.chunkIndex] = Uint8List.fromList(chunk.data);
      _log.debug(
          '[E2E media-chunk-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${_hexShort(senderDeviceId)} mediaId=${mediaIdHex.substring(0, 8)} '
          'idx=${chunk.chunkIndex}/${buf.totalChunks} bytes=${chunk.data.length}');
    } catch (e) {
      _log.warn('handleMediaChunkV3: parse fail: $e '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))})');
    }
  }

  /// V3 MEDIA_COMPLETE: assemble buffered chunks, hash-check, write file,
  /// bump the matching UiMessage to MediaDownloadState.completed.
  void _handleMediaCompleteV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final complete = proto.MediaCompleteV3.fromBuffer(frame.payload);
      final mediaIdHex = bytesToHex(Uint8List.fromList(complete.mediaId));
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final conversationId = frame.groupId.isNotEmpty
          ? bytesToHex(Uint8List.fromList(frame.groupId))
          : senderHex;

      final buf = _mediaChunkBuffers.remove(mediaIdHex);
      if (buf == null) {
        _log.warn(
            'media-complete-v3: no chunk-buffer for ${mediaIdHex.substring(0, 8)} — drop');
        return;
      }
      if (!buf.isComplete) {
        final missing = <int>[];
        for (var i = 0; i < buf.chunks.length; i++) {
          if (buf.chunks[i] == null) missing.add(i);
        }
        _log.warn(
            'media-complete-v3: incomplete buffer for ${mediaIdHex.substring(0, 8)} '
            '— missing=${missing.length}/${buf.totalChunks}');
        return;
      }
      final assembled = buf.assemble();
      if (complete.totalSize.toInt() != 0 &&
          complete.totalSize.toInt() != assembled.length) {
        _log.warn(
            'media-complete-v3: size mismatch for ${mediaIdHex.substring(0, 8)} '
            '(expected=${complete.totalSize} got=${assembled.length})');
        return;
      }
      final localHash = SodiumFFI().sha256(assembled);
      final wantHash = Uint8List.fromList(complete.contentHash);
      if (wantHash.isNotEmpty && !_bytesEqual(localHash, wantHash)) {
        _log.warn(
            'media-complete-v3: hash mismatch for ${mediaIdHex.substring(0, 8)}'
            ' — drop reassembled bytes');
        return;
      }

      // Locate the announced UiMessage so we can read filename/mime and bump
      // the mediaState. The MEDIA_ANNOUNCE handler stored the bubble keyed
      // by msgId (= mediaId) in the same conversation.
      final conv = conversations[conversationId];
      UiMessage? msg;
      if (conv != null) {
        final idx = conv.messages.indexWhere((m) => m.id == mediaIdHex);
        if (idx >= 0) msg = conv.messages[idx];
      }
      final filename =
          msg?.filename ?? 'file_$mediaIdHex';
      final mediaDir = Directory('$profileDir/media');
      if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
      final savePath = _uniqueMediaPath(mediaDir.path, filename);
      File(savePath).writeAsBytesSync(assembled);

      if (msg != null) {
        msg.filePath = savePath;
        msg.fileSize = assembled.length;
        msg.mediaState = MediaDownloadState.completed;
        if (msg.mimeType?.startsWith('image/') == true &&
            msg.thumbnailBase64 == null &&
            assembled.length <= 100 * 1024) {
          msg.thumbnailBase64 = base64Encode(assembled);
        }
        onStateChanged?.call();
        _saveConversations();
      }

      _log.info(
          '[E2E media-stage2-recv-done-v3] from=${senderHex.substring(0, 8)} '
          'device=${_hexShort(senderDeviceId)} mediaId=${mediaIdHex.substring(0, 8)} '
          'bytes=${assembled.length} path=$savePath');
    } catch (e, st) {
      _log.warn('handleMediaCompleteV3: failed: $e\n$st '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))})');
    }
  }

  /// V3 MEDIA_REJECT: receiver declined the announce; sender clears pending.
  void _handleMediaRejectV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final originalMsgId = bytesToHex(Uint8List.fromList(frame.payload));
      final removed = _pendingMediaSends.remove(originalMsgId) != null;
      _log.info(
          '[E2E media-reject-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${_hexShort(senderDeviceId)} '
          'msgId=${originalMsgId.length >= 8 ? originalMsgId.substring(0, 8) : originalMsgId} '
          'pending-cleared=$removed');
    } catch (e) {
      _log.warn('handleMediaRejectV3: failed: $e');
    }
  }

  /// V3 REACTION: EmojiReaction proto in frame.payload. Add/remove emoji
  /// on the target message. Conversation-Lookup ist DM-style auf Sender-Hex
  /// (Group-Fanout siehe Klassen-Header-TODO).
  void _handleReactionV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      if (_checkGroupPostMembership(frame, senderHex) == null) return;
      final reaction = proto.EmojiReaction.fromBuffer(frame.payload);
      final targetMsgId =
          bytesToHex(Uint8List.fromList(reaction.messageId));
      final emoji = reaction.emoji;
      if (emoji.isEmpty) return;

      final conversationId = frame.groupId.isNotEmpty
          ? bytesToHex(Uint8List.fromList(frame.groupId))
          : senderHex;
      final conv = conversations[conversationId];
      if (conv == null) return;
      _log.debug('_handleReactionV3: emoji=$emoji targetMsgId=${targetMsgId.substring(0, 8)} conv.messages.length=${conv.messages.length}');
      final msgIndex = conv.messages.indexWhere((m) => m.id == targetMsgId);
      if (msgIndex < 0) return;
      final msg = conv.messages[msgIndex];

      if (reaction.remove) {
        msg.reactions[emoji]?.remove(senderHex);
        if (msg.reactions[emoji]?.isEmpty ?? false) {
          msg.reactions.remove(emoji);
        }
      } else {
        msg.reactions.putIfAbsent(emoji, () => {});
        msg.reactions[emoji]!.add(senderHex);
      }
      onStateChanged?.call();
      _saveConversations();
      _log.debug(
          'REACTION-V3 ${reaction.remove ? "removed" : "added"}: $emoji on '
          '${targetMsgId.substring(0, 8)} by ${senderHex.substring(0, 8)} '
          'device=${_hexShort(senderDeviceId)}');
    } catch (e) {
      _log.warn('handleReactionV3: parse fail: $e');
    }
  }

  /// V3 REPLY: bisher gibt es kein eigenes ReplyMessageV3-Sub-Schema. Reply
  /// reist als TEXT mit reply_to_* in ContentMetadata. Bis Spec §5 ein
  /// ReplyMessageV3 definiert ist behandeln wir REPLY identisch zu TEXT —
  /// die reply-Felder werden aus ContentMetadata herausgezogen wenn vorhanden.
  void _handleReplyV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final mismatchResult = _checkGroupPostMembership(frame, senderHex);
      if (mismatchResult == null) return;
      final isMembershipMismatch = mismatchResult;
      final tm = proto.TextMessageV3.fromBuffer(frame.payload);
      final msgId = bytesToHex(Uint8List.fromList(frame.messageId));
      final conversationId = frame.groupId.isNotEmpty
          ? bytesToHex(Uint8List.fromList(frame.groupId))
          : senderHex;

      // TODO C4: reply_to_message_id / reply_to_text / reply_to_sender
      // brauchen ein ReplyMetadataV3-Feld. ContentMetadata hat heute keinen
      // Reply-Slot — bis die Spec klärt landet REPLY ohne Reply-Banner.
      final msg = UiMessage(
        id: msgId,
        conversationId: conversationId,
        senderNodeIdHex: senderHex,
        text: tm.text,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(frame.timestampMs.toInt()),
        type: UiMessageType.text,
        status: MessageStatus.delivered,
        isOutgoing: false,
        readAt: DateTime.now(),
        membershipMismatch: isMembershipMismatch,
      );
      final isChannel = _channels.containsKey(conversationId);
      final isGroup = _groups.containsKey(conversationId);
      _addMessageToConversation(conversationId, msg,
          isGroup: isGroup, isChannel: isChannel);
      _log.info(
          'REPLY-V3 (treated as TEXT — Reply-Schema TODO C4) '
          'from ${senderHex.substring(0, 8)} device=${_hexShort(senderDeviceId)}');
    } catch (e) {
      _log.warn('handleReplyV3: parse fail: $e');
    }
  }

  /// V3 EDIT: MessageEdit proto in payload + EditMetadata as standard frame
  /// field. Dual-Enforcement (sender == author + edit-window).
  void _handleEditV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      if (_checkGroupPostMembership(frame, senderHex) == null) return;
      final editMsg = proto.MessageEdit.fromBuffer(frame.payload);
      final originalMsgId =
          bytesToHex(Uint8List.fromList(editMsg.originalMessageId));
      final conversationId = frame.groupId.isNotEmpty
          ? bytesToHex(Uint8List.fromList(frame.groupId))
          : senderHex;
      final conv = conversations[conversationId];
      if (conv == null) return;
      final msgIndex =
          conv.messages.indexWhere((m) => m.id == originalMsgId);
      if (msgIndex < 0) return;
      final original = conv.messages[msgIndex];

      // Dual-Enforcement: only original author can edit.
      if (original.senderNodeIdHex != senderHex) {
        _log.warn(
            'EDIT-V3 rejected: sender ${senderHex.substring(0, 8)} != author '
            '(device=${_hexShort(senderDeviceId)})');
        return;
      }

      // Edit-Window check — receiver uses the wider tolerance to avoid
      // rejecting edits from older nodes that still use the 60-min default.
      final chatEditWindowMs =
          conv.config.editWindowMs ?? _receiverEditToleranceMs;
      if (chatEditWindowMs == 0) {
        _log.warn('EDIT-V3 rejected: editing disabled for $conversationId');
        return;
      }
      if (chatEditWindowMs > 0) {
        final ageMs = DateTime.now().millisecondsSinceEpoch -
            original.timestamp.millisecondsSinceEpoch;
        if (ageMs > chatEditWindowMs) {
          _log.warn('EDIT-V3 rejected: too old (${ageMs}ms > ${chatEditWindowMs}ms)');
          return;
        }
      }

      original.text = editMsg.newText;
      original.editedAt = DateTime.fromMillisecondsSinceEpoch(
          editMsg.editTimestamp.toInt());
      onStateChanged?.call();
      _saveConversations();
      _log.info(
          'EDIT-V3 by ${senderHex.substring(0, 8)} on $originalMsgId');
    } catch (e) {
      _log.warn('handleEditV3: parse fail: $e');
    }
  }

  /// V3 DELETE: MessageDelete proto in payload. Soft-delete (clear text +
  /// mark isDeleted).
  void _handleDeleteV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      if (_checkGroupPostMembership(frame, senderHex) == null) return;
      final deleteMsg = proto.MessageDelete.fromBuffer(frame.payload);
      final targetMsgId =
          bytesToHex(Uint8List.fromList(deleteMsg.messageId));
      final conversationId = frame.groupId.isNotEmpty
          ? bytesToHex(Uint8List.fromList(frame.groupId))
          : senderHex;
      final conv = conversations[conversationId];
      if (conv == null) return;
      final msgIndex = conv.messages.indexWhere((m) => m.id == targetMsgId);
      if (msgIndex < 0) return;
      final original = conv.messages[msgIndex];

      if (original.senderNodeIdHex != senderHex) {
        _log.warn(
            'DELETE-V3 rejected: sender ${senderHex.substring(0, 8)} != author '
            '(device=${_hexShort(senderDeviceId)})');
        return;
      }
      original.text = '';
      original.isDeleted = true;
      onStateChanged?.call();
      _saveConversations();
      _log.info('DELETE-V3 by ${senderHex.substring(0, 8)} on $targetMsgId');
    } catch (e) {
      _log.warn('handleDeleteV3: parse fail: $e');
    }
  }

  /// V3 VOICE_MESSAGE: alias for MEDIA_INLINE with audio MIME — share the
  /// same code path. The dedicated message type exists so receivers can
  /// route voice through transcription pipelines without sniffing MIME.
  void _handleVoiceMessageV3(
      proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    // Sender muss sicherstellen dass contentMetadata.mimeType audio/* ist.
    // Falls leer: Default audio/aac (Architecture §5).
    if (frame.contentMetadata.mimeType.isEmpty) {
      frame.contentMetadata.mimeType = 'audio/aac';
    }
    _handleMediaInlineV3(frame, senderDeviceId, snapshot);
  }


  // C4 — Recovery / Identity / Profile / CR / Groups / Channels / DHT /
  //       Fragments / Peer-Store / Chat-Config / Routing / Hole-Punch /
  //       Identity-Resolution / Multi-Device / Calendar / Polls
  void _handleRestoreBroadcastV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      // V3.0 Welle 6: RESTORE_BROADCAST migrated to InfrastructureFrame
      // (§2.3.5 selector + §6.3). An inbound ApplicationFrame with this
      // messageType is a protocol violation — drop.
      _log.warn('RESTORE_BROADCAST on ApplicationFrame path is invalid '
          'since V3.0 Welle 6 (§2.3.5) — dropping. sender='
          '${bytesToHex(sd).substring(0, 8)}');
  void _handleRestoreResponseV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    _handleRestoreResponse(
      Uint8List.fromList(frame.payload),
      Uint8List.fromList(frame.senderUserId),
      senderDeviceId,
    );
  }
  void _handleIdentityDeletedV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    // The inner payload is the IdentityDeletedNotification protobuf,
    // already decrypted + authenticated by the V3 pipeline (outer-sig +
    // inner user-sig + KEM-decap).
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    proto.IdentityDeletedNotification notification;
    try {
      notification = proto.IdentityDeletedNotification.fromBuffer(frame.payload);
    } catch (e) {
      _log.error('IDENTITY_DELETED parse failed: $e');
      return;
    }

    final contact = _contacts[senderHex];
    if (contact == null) {
      _log.debug('IDENTITY_DELETED from unknown sender ${senderHex.substring(0, 8)}');
      return;
    }

    final displayName = notification.displayName.isNotEmpty
        ? notification.displayName
        : contact.displayName;
    _log.info('Identity deleted: "$displayName" (${senderHex.substring(0, 8)})');

    // Add system message to conversation. Routed through
    // _addMessageToConversation so the badge counter and the system Launcher-
    // Badge stay in sync (#U15 — direct conv.messages.add bypassed both).
    if (conversations.containsKey(senderHex)) {
      final systemMsg = UiMessage(
        id: bytesToHex(Uint8List.fromList(frame.messageId)),
        conversationId: senderHex,
        senderNodeIdHex: '',
        text: '$displayName has deleted their identity.',
        isOutgoing: false,
        timestamp: DateTime.now(),
        type: UiMessageType.identityDeleted,
        status: MessageStatus.delivered,
      );
      _addMessageToConversation(senderHex, systemMsg);
    }

    // Mark contact as deleted (prevents re-import)
    _deletedContacts.add(senderHex);

    // Remove from groups/channels
    for (final group in _groups.values) {
      group.members.remove(senderHex);
    }
    for (final channel in _channels.values) {
      channel.members.remove(senderHex);
    }

    // Remove contact
    _contacts.remove(senderHex);
    _saveContacts();
    _saveGroups();
    _saveChannels();

    onStateChanged?.call();
  }
  void _handleProfileUpdateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    // Inner payload is the ProfileData protobuf, already decrypted +
    // authenticated by the V3 pipeline.
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    try {
      final profile = proto.ProfileData.fromBuffer(frame.payload);
      final contact = _contacts[senderHex];
      if (contact == null) return;

      if (profile.profilePicture.isNotEmpty) {
        contact.profilePictureBase64 = base64Encode(profile.profilePicture);
      } else {
        contact.profilePictureBase64 = null; // Picture removed
      }

      // Update description if present
      if (profile.description.isNotEmpty) {
        contact.message = profile.description;
      } else {
        contact.message = null;
      }

      // Handle display name change
      if (profile.displayName.isNotEmpty && profile.displayName != contact.displayName) {
        if (contact.localAlias != null) {
          // User has a local alias → store as pending, don't auto-override
          contact.pendingNameChange = profile.displayName;
          _log.info('Contact ${contact.effectiveName} changed name to "${profile.displayName}" (pending, local alias active)');
        } else {
          // No local alias → update directly
          final oldName = contact.displayName;
          contact.displayName = profile.displayName;
          // Update conversation displayName
          final conv = conversations[senderHex];
          if (conv != null) {
            conv.displayName = profile.displayName;
          }
          _log.info('Contact renamed: "$oldName" → "${profile.displayName}"');
        }
      }

      // Update conversation profile picture
      final conv = conversations[senderHex];
      if (conv != null) {
        conv.profilePictureBase64 = contact.profilePictureBase64;
      }

      _saveContacts();
      onStateChanged?.call();
      _log.info('Profile update from ${contact.effectiveName}');
    } catch (e) {
      _log.error('PROFILE_UPDATE parse error: $e');
    }
  }
  void _handleKeyRotationBroadcastV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    // V3-direct: inner payload is the KeyRotationBroadcast (Periodic
    // variant) protobuf, already decrypted + authenticated by the V3
    // pipeline.
    //
    // Welle 6 §7.4 path-discriminator: the ApplicationFrame path is
    // reserved for the **Periodic** flavor (KEM-only, single sig in body
    // — Ed25519/ML-DSA do not change). The **Emergency** flavor (dual-sig
    // in body) belongs on the InfrastructureFrame path. Early-detect
    // dual-sig here and drop — emitting a warn so a sender bug becomes
    // observable rather than silently bypassing the §7.4 wire-path
    // constraint.
    proto.KeyRotationBroadcast? earlyParse;
    try {
      earlyParse = proto.KeyRotationBroadcast.fromBuffer(frame.payload);
    } catch (_) {
      // If the body does not parse the downstream handler will fail in
      // the same way — let it produce its own error log.
    }
    if (earlyParse != null &&
        earlyParse.oldSignatureEd25519.isNotEmpty &&
        earlyParse.newSignatureEd25519.isNotEmpty) {
      _log.warn('_handleKeyRotationBroadcastV3 drop: dual-sig present on '
          'ApplicationFrame path — Emergency variant must arrive via '
          'InfrastructureFrame (§7.4 / Welle 6) '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} '
          'device=${_hexShort(senderDeviceId)})');
      return;
    }
    _handleKeyRotationBroadcast(
      Uint8List.fromList(frame.payload),
      Uint8List.fromList(frame.senderUserId),
    );
  }
  /// §8.1 per-sender CR rate limit: max 5 CRs per hour.
  bool _isCrRateLimited(String senderHex) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 1));
    final timestamps = _crRateTracker[senderHex];
    if (timestamps == null) {
      _crRateTracker[senderHex] = [now];
      return false;
    }
    timestamps.removeWhere((t) => t.isBefore(cutoff));
    if (timestamps.length >= 5) {
      _log.warn('CR rate limit: sender ${senderHex.substring(0, 8)} exceeded 5 CRs/hour');
      return true;
    }
    timestamps.add(now);
    return false;
  }

  void _handleContactRequestV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    _log.debug('_handleContactRequestV3 from device ${bytesToHex(senderDeviceId).substring(0, 8)}');
    _log.info('_handleContactRequestV3 ENTER for ${identity.userIdHex.substring(0, 8)}');
    try {
      final cr = proto.ContactRequestMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

      // §8.1 per-sender CR rate limit (5/hour).
      if (_isCrRateLimited(senderHex)) return;

      // §4.11.10 owner-side session end: an inbound First-CR from a scanner
      // device we resolved via the First-Contact rendezvous completes the
      // owner session (stop polling/publishing). No-op without sessions.
      _fcRendezvous?.onFirstCrReceived(bytesToHex(senderDeviceId));

      // Multi-Identity guard: only process CRs addressed to THIS identity.
      // Without this, a CR to identity B could be processed by identity A's
      // service on the same node, resulting in A responding instead of B.
      // Accept both userId and deviceNodeId: senders with pre-V3.1.44 contacts
      // may have stored our deviceNodeId instead of userId.
      if (frame.recipientUserId.isNotEmpty) {
        final recipientHex = bytesToHex(Uint8List.fromList(frame.recipientUserId));
        if (recipientHex != identity.userIdHex &&
            recipientHex != identity.nodeIdHex) {
          return; // Not for this identity
        }
      }

      // Previously deleted contact sends new CR: allow re-contact (delete ≠ block).
      if (_deletedContacts.contains(senderHex)) {
        _deletedContacts.remove(senderHex);
        _saveContacts();
        _log.info('Previously deleted contact ${senderHex.substring(0, 8)} re-requesting — allowed');
      }

      // Already accepted contact sends new CR: update keys and re-send acceptance.
      // This handles the case where the remote side deleted us and re-added.
      //
      // F4-Gate (§8.1, V3.0 Welle 6): the auto-overwrite of stored pubkeys
      // requires a verified outer Device-Sig (`snapshot.isOuterVerified`).
      // On V3 paths where the snapshot reports `skippedBootstrap`, we DO NOT
      // auto-replace keys — the CR falls through to the standard inbound CR
      // path (Inbox tab) so the user explicitly confirms the new keys.
      final existing = _contacts[senderHex];
      final allowAutoOverwrite = snapshot.isOuterVerified;
      if (existing != null && existing.status == 'accepted' && allowAutoOverwrite) {
        // RC-1 (§8.1+§8.3): detect identity key change before overwrite
        final storedEd25519 = existing.ed25519Pk;
        final incomingEd25519 = Uint8List.fromList(cr.ed25519PublicKey);

        // Restlücke A: accepted contact with empty stored key — treat as fresh CR
        if (storedEd25519 == null || storedEd25519.isEmpty) {
          _log.warn('RC-1: accepted contact ${senderHex.substring(0, 8)} has no stored ed25519Pk — routing to Inbox');
        }
        // Same-Seed-Reinstall: keys unchanged — silent refresh
        else if (_bytesEqual(storedEd25519, incomingEd25519)) {
          existing.displayName = cr.displayName;
          existing.ed25519Pk = incomingEd25519;
          existing.x25519Pk = Uint8List.fromList(cr.x25519PublicKey);
          existing.mlKemPk = Uint8List.fromList(cr.mlKemPublicKey);
          existing.mlDsaPk = Uint8List.fromList(cr.mlDsaPublicKey);
          if (cr.profilePicture.isNotEmpty) {
            existing.profilePictureBase64 = base64Encode(cr.profilePicture);
          }
          if (!existing.deviceNodeIds.contains(bytesToHex(senderDeviceId))) {
            existing.deviceNodeIds.add(bytesToHex(senderDeviceId));
          }
          _saveContacts();
          _log.info('Re-contact from accepted ${cr.displayName} (same keys) — sending acceptance');
          acceptContactRequest(senderHex);
          return;
        }
        // Key changed — fire §8.3 Key-Change-Detection, overwrite with verification reset
        else {
          final prevLevel = existing.verificationLevel;
          final keyChange = onIdentityRotation(prevLevel);
          existing.displayName = cr.displayName;
          existing.ed25519Pk = incomingEd25519;
          existing.x25519Pk = Uint8List.fromList(cr.x25519PublicKey);
          existing.mlKemPk = Uint8List.fromList(cr.mlKemPublicKey);
          existing.mlDsaPk = Uint8List.fromList(cr.mlDsaPublicKey);
          if (cr.profilePicture.isNotEmpty) {
            existing.profilePictureBase64 = base64Encode(cr.profilePicture);
          }
          if (!existing.deviceNodeIds.contains(bytesToHex(senderDeviceId))) {
            existing.deviceNodeIds.add(bytesToHex(senderDeviceId));
          }
          existing.verificationLevel = keyChange.newLevel;
          _saveContacts();
          _log.info('RC-1: Re-contact from ${cr.displayName} with CHANGED keys — '
              'overwrite + §8.3 reset $prevLevel→${keyChange.newLevel}');
          try {
            onContactIdentityRotated?.call(senderHex, existing.displayName, keyChange.wasVerified);
          } catch (e) {
            _log.warn('onContactIdentityRotated listener threw: $e');
          }
          acceptContactRequest(senderHex);
          onStateChanged?.call();
          return;
        }
      }
      if (existing != null && existing.status == 'accepted' && !allowAutoOverwrite) {
        // F4-Gate triggered: status==accepted, but outer-sig was not verified.
        // Do not auto-overwrite. Treat as fresh inbound CR — fall through to
        // the regular pending-CR creation below, which surfaces it in the
        // Inbox tab for explicit user confirmation.
        _log.warn('F4-Gate: skipping auto-overwrite for ${cr.displayName} '
            '(${senderHex.substring(0, 8)}) — outerSigStatus='
            '${snapshot.outerSigStatus.name}, requires explicit user accept');
      }
      if (existing != null && existing.status == 'pending_outgoing') {
        // Bidirectional CR: we sent them a CR AND they sent us one.
        // Auto-accept: both sides want to connect.
        existing.displayName = cr.displayName;
        existing.ed25519Pk = Uint8List.fromList(cr.ed25519PublicKey);
        existing.x25519Pk = Uint8List.fromList(cr.x25519PublicKey);
        existing.mlKemPk = Uint8List.fromList(cr.mlKemPublicKey);
        existing.mlDsaPk = Uint8List.fromList(cr.mlDsaPublicKey);
        if (cr.profilePicture.isNotEmpty) {
          existing.profilePictureBase64 = base64Encode(cr.profilePicture);
        }
        // Store device ID so sendToUser → deviceNodeIds fallback works on accept.
        if (!existing.deviceNodeIds.contains(bytesToHex(senderDeviceId))) {
          existing.deviceNodeIds.add(bytesToHex(senderDeviceId));
        }
        _saveContacts();
        _log.info('Bidirectional CR from ${cr.displayName} — auto-accepting');
        acceptContactRequest(senderHex);
        return;
      }

      final contact = ContactInfo(
        nodeId: Uint8List.fromList(frame.senderUserId),
        displayName: cr.displayName,
        ed25519Pk: Uint8List.fromList(cr.ed25519PublicKey),
        x25519Pk: Uint8List.fromList(cr.x25519PublicKey),
        mlKemPk: Uint8List.fromList(cr.mlKemPublicKey),
        mlDsaPk: Uint8List.fromList(cr.mlDsaPublicKey),
        status: 'pending',
        message: cr.message,
        profilePictureBase64: cr.profilePicture.isNotEmpty
            ? base64Encode(cr.profilePicture)
            : null,
      );

      // Detect stale contact: if an existing accepted contact has the same
      // display name but different nodeId, the sender likely reinstalled.
      // Mark the old conversation with a system message so the user knows
      // to use the new contact (old ID is unreachable).
      for (final entry in _contacts.entries) {
        if (entry.key == senderHex) continue; // Same contact — skip
        final old = entry.value;
        if (old.status != 'accepted') continue;
        if (old.displayName != cr.displayName) continue;
        // Same name, different identity → probable reinstall
        final oldConv = conversations[entry.key];
        if (oldConv != null) {
          final systemMsg = UiMessage(
            id: bytesToHex(SodiumFFI().randomBytes(16)),
            conversationId: entry.key,
            senderNodeIdHex: '',
            text: '${cr.displayName} appears to have a new identity. '
                'Messages in this conversation may not be delivered. '
                'Please use the new contact request instead.',
            isOutgoing: false,
            timestamp: DateTime.now(),
            type: UiMessageType.identityDeleted,
            status: MessageStatus.delivered,
          );
          oldConv.messages.add(systemMsg);
          _log.info('Stale contact detected: ${cr.displayName} has new identity '
              '${senderHex.substring(0, 8)}, old was ${entry.key.substring(0, 8)}');
        }
      }

      // Store sender's device ID so acceptContactRequest → sendToUser can reach
      // them immediately even before the DHT auth-manifest is warm (§2.6.2).
      contact.deviceNodeIds.add(bytesToHex(senderDeviceId));
      _contacts[senderHex] = contact;
      _saveContacts();
      _saveConversations();
      _log.info('CR from ${cr.displayName} (${senderHex.substring(0, 8)}) → pending');

      onContactRequestReceived?.call(senderHex, cr.displayName);
      onStateChanged?.call();
      _log.info('Contact request from ${cr.displayName} (${senderHex.substring(0, 8)})');
    } catch (e) {
      _log.error('Contact request parse error: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }
  void _handleContactRequestResponseV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final resp = proto.ContactRequestResponse.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

      // Multi-Identity guard: only accept responses addressed to THIS identity.
      // Accept both userId and deviceNodeId (backward compat with pre-V3.1.44 contacts).
      if (frame.recipientUserId.isNotEmpty) {
        final recipientHex = bytesToHex(Uint8List.fromList(frame.recipientUserId));
        if (recipientHex != identity.userIdHex &&
            recipientHex != identity.nodeIdHex) {
          return; // Not for this identity
        }
      }

      // Previously deleted contact responds: allow re-contact (delete ≠ block).
      if (_deletedContacts.contains(senderHex)) {
        _deletedContacts.remove(senderHex);
        _saveContacts();
        _log.info('Previously deleted contact ${senderHex.substring(0, 8)} responding — allowed');
      }

      if (resp.accepted) {
        // Validate: we must have a pending outgoing CR to this sender.
        // Without this check, a response from a wrong identity (e.g. identity A
        // responding to a CR addressed to identity B) would create a ghost contact.
        final existing = _contacts[senderHex];
        if (existing == null || (existing.status != 'pending_outgoing' && existing.status != 'accepted')) {
          _log.warn('CR-Response from ${senderHex.substring(0, 8)} but no pending CR — ignoring');
          return;
        }

        // Dedup on status transition: if the contact was already 'accepted',
        // this is a sender-side retry (e.g. sender restarted, lost in-memory
        // ACK-state, retried CR-Response). Don't flood the chat with duplicate
        // "accepted your CR" system messages or re-fire the onContactAccepted
        // callback — just refresh the keys in case they changed.
        final wasAlreadyAccepted = existing.status == 'accepted';

        // §4.11.10 scanner-side session end: the contact accepted our CR —
        // the First-Contact rendezvous session for this target is complete.
        _fcRendezvous?.onCrConfirmed(senderHex);

        // RC-1 (§8.1+§8.3): snapshot old key before overwrite
        final oldEd25519 = existing.ed25519Pk;

        final picBase64 = resp.profilePicture.isNotEmpty
            ? base64Encode(resp.profilePicture)
            : null;
        existing.status = 'accepted';
        existing.acceptedAt ??= DateTime.now();
        _crRetryCountPerContact.remove(senderHex);
        _staleWarningWrittenFor.remove(senderHex);
        // First-CR ContactSeed bootstrap is over once we have the recipient's
        // User-KEM pubkeys (filled below). Clear the seed bundle so re-contact
        // uses the User-KEM pair directly and stale Device-KEM pubkeys don't
        // outlive their TTL on disk.
        existing.seedDeviceIdHex = null;
        existing.seedDxkB64 = null;
        existing.seedDmkB64 = null;
        existing.seedEpB64 = null;

        // RC-1 (§8.1+§8.3): if already accepted AND keys changed, fire §8.3
        if (wasAlreadyAccepted) {
          final incomingEd25519 = Uint8List.fromList(resp.ed25519PublicKey);
          final identityKeyChanged = oldEd25519 == null || oldEd25519.isEmpty ||
              !_bytesEqual(oldEd25519, incomingEd25519);

          existing.ed25519Pk = incomingEd25519;
          existing.x25519Pk = Uint8List.fromList(resp.x25519PublicKey);
          existing.mlKemPk = Uint8List.fromList(resp.mlKemPublicKey);
          existing.mlDsaPk = Uint8List.fromList(resp.mlDsaPublicKey);
          existing.displayName = resp.displayName;
          if (picBase64 != null) existing.profilePictureBase64 = picBase64;
          existing.deviceNodeIds.add(bytesToHex(senderDeviceId));

          final conv = conversations[senderHex];
          if (conv != null && resp.displayName.isNotEmpty) {
            conv.displayName = resp.displayName;
            if (picBase64 != null) conv.profilePictureBase64 = picBase64;
          }

          if (identityKeyChanged) {
            final prevLevel = existing.verificationLevel;
            final keyChange = onIdentityRotation(prevLevel);
            existing.verificationLevel = keyChange.newLevel;
            _saveContacts();
            _saveConversations();
            _log.info('RC-1: CRR retry from ${senderHex.substring(0, 8)} with CHANGED keys — '
                '§8.3 reset $prevLevel→${keyChange.newLevel}');
            try {
              onContactIdentityRotated?.call(senderHex, existing.displayName, keyChange.wasVerified);
            } catch (e) {
              _log.warn('onContactIdentityRotated listener threw: $e');
            }
            onStateChanged?.call();
            return;
          }

          _saveContacts();
          _saveConversations();
          _log.debug('CR-Response retry from ${senderHex.substring(0, 8)} — keys refreshed, no system msg');
          onStateChanged?.call();
          return;
        }

        // First acceptance path
        existing.ed25519Pk = Uint8List.fromList(resp.ed25519PublicKey);
        existing.x25519Pk = Uint8List.fromList(resp.x25519PublicKey);
        existing.mlKemPk = Uint8List.fromList(resp.mlKemPublicKey);
        existing.mlDsaPk = Uint8List.fromList(resp.mlDsaPublicKey);
        existing.displayName = resp.displayName;
        if (picBase64 != null) existing.profilePictureBase64 = picBase64;
        // Store sender's device ID so sendToUser can reach them immediately
        // even before the DHT auth-manifest is warm (§2.6.2 bootstrapping).
        existing.deviceNodeIds.add(bytesToHex(senderDeviceId));

        // RC-1: first CRR acceptance — check if keys differ from pending_outgoing entry
        final identityKeyChanged = oldEd25519 != null && oldEd25519.isNotEmpty &&
            !_bytesEqual(oldEd25519, Uint8List.fromList(resp.ed25519PublicKey));
        if (identityKeyChanged) {
          final keyChange = onIdentityRotation(existing.verificationLevel);
          existing.verificationLevel = keyChange.newLevel;
          _log.info('RC-1: CRR first-accept from ${senderHex.substring(0, 8)} with '
              'changed keys — §8.3 reset');
          try {
            onContactIdentityRotated?.call(senderHex, existing.displayName, keyChange.wasVerified);
          } catch (e) {
            _log.warn('onContactIdentityRotated listener threw: $e');
          }
        }

        _saveContacts();

        // Sync conversation displayName — the conversation may already exist
        // (e.g. text arrived before CRR) with a truncated-hash placeholder.
        final conv = conversations[senderHex];
        if (conv != null && resp.displayName.isNotEmpty) {
          conv.displayName = resp.displayName;
          if (picBase64 != null) conv.profilePictureBase64 = picBase64;
        }

        // Create conversation with system message so the contact appears
        // immediately in the "Aktuell" tab (not only in "Kontakte" tab).
        final systemMsg = UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: senderHex,
          senderNodeIdHex: '',
          text: '${resp.displayName} accepted your contact request.',
          isOutgoing: false,
          timestamp: DateTime.now(),
          type: UiMessageType.identityDeleted, // system message type
          status: MessageStatus.delivered,
        );
        _addMessageToConversation(senderHex, systemMsg);
        _saveConversations();

        onContactAccepted?.call(senderHex);
        _log.info('Contact accepted by ${resp.displayName}');
      } else {
        _log.info('Contact rejected by ${senderHex.substring(0, 8)}: ${resp.rejectionReason}');
      }
      onStateChanged?.call();
    } catch (e) {
      _log.error('Contact response parse error: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }
  void _handleGroupCreateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    // GROUP_CREATE shares the GROUP_INVITE payload schema and processing path.
    _handleGroupInviteV3(frame, senderDeviceId, snapshot);
  }
  void _handleGroupInviteV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.GroupInviteV3 invite;
    try {
      invite = proto.GroupInviteV3.fromBuffer(frame.payload);
    } catch (e) {
      _log.error('GROUP_INVITE parse failed: $e');
      return;
    }

    final groupIdHex = bytesToHex(Uint8List.fromList(invite.groupId));

    // Build members map
    final members = <String, GroupMemberInfo>{};
    for (final m in invite.members) {
      final nid = bytesToHex(Uint8List.fromList(m.nodeId));
      members[nid] = GroupMemberInfo(
        nodeIdHex: nid,
        displayName: m.displayName,
        role: m.role,
        ed25519Pk: m.ed25519PublicKey.isEmpty ? null : Uint8List.fromList(m.ed25519PublicKey),
        x25519Pk: m.x25519PublicKey.isEmpty ? null : Uint8List.fromList(m.x25519PublicKey),
        mlKemPk: m.mlKemPublicKey.isEmpty ? null : Uint8List.fromList(m.mlKemPublicKey),
      );
    }

    // Determine owner
    final inviterHex = bytesToHex(Uint8List.fromList(invite.inviterId));
    final ownerHex = members.values.where((m) => m.role == 'owner').firstOrNull?.nodeIdHex ?? inviterHex;

    final isUpdate = _groups.containsKey(groupIdHex);

    // GM-1 (§9.1.4): authority check for group updates
    int newEpoch;
    if (isUpdate) {
      final oldGroup = _groups[groupIdHex]!;
      final senderMember = oldGroup.members[senderHex];

      if (senderMember == null || (senderMember.role != 'owner' && senderMember.role != 'admin')) {
        _log.warn('GM-1: GROUP_INVITE update from non-admin ${senderHex.substring(0, 8)} '
            'for "${oldGroup.name}" — rejected');
        return;
      }

      final wireEpoch = invite.membershipEpoch.toInt();

      if (wireEpoch > 0 && wireEpoch <= oldGroup.membershipEpoch) {
        _log.warn('GM-1: GROUP_INVITE epoch $wireEpoch <= ${oldGroup.membershipEpoch} '
            'from ${senderHex.substring(0, 8)} — rejected (replay/downgrade)');
        return;
      }

      if (invite.membershipHash.isNotEmpty && invite.membershipSigEd25519.isNotEmpty) {
        final senderEd25519Pk = senderMember.ed25519Pk;
        if (senderEd25519Pk != null && senderEd25519Pk.isNotEmpty) {
          final sigOk = SodiumFFI().verifyEd25519(
              Uint8List.fromList(invite.membershipHash),
              Uint8List.fromList(invite.membershipSigEd25519),
              senderEd25519Pk);
          if (!sigOk) {
            _log.warn('GM-1: GROUP_INVITE Ed25519 sig INVALID from ${senderHex.substring(0, 8)} — rejected');
            return;
          }
        }
        if (invite.membershipSigMlDsa.isNotEmpty) {
          final senderMlDsaPk = _contacts[senderHex]?.mlDsaPk;
          if (senderMlDsaPk != null && senderMlDsaPk.isNotEmpty) {
            final mlDsaOk = OqsFFI().mlDsaVerify(
                Uint8List.fromList(invite.membershipHash),
                Uint8List.fromList(invite.membershipSigMlDsa),
                senderMlDsaPk);
            if (!mlDsaOk) {
              _log.warn('GM-1: GROUP_INVITE ML-DSA sig INVALID from ${senderHex.substring(0, 8)} — rejected');
              return;
            }
          }
        }
        final expectedHash = _computeMembershipHash(wireEpoch, groupIdHex, members);
        if (!_bytesEqual(Uint8List.fromList(invite.membershipHash), expectedHash)) {
          _log.warn('GM-1: GROUP_INVITE hash mismatch from ${senderHex.substring(0, 8)} — rejected');
          return;
        }
      } else if (wireEpoch == 0) {
        _log.debug('GM-1: GROUP_INVITE without epoch/sig from ${senderHex.substring(0, 8)} — legacy-unverified');
      }

      newEpoch = wireEpoch > 0 ? wireEpoch : oldGroup.membershipEpoch;
    } else {
      newEpoch = invite.membershipEpoch.toInt() > 0
          ? invite.membershipEpoch.toInt()
          : 1;
    }

    final group = GroupInfo(
      groupIdHex: groupIdHex,
      name: invite.groupName,
      description: invite.groupDescription,
      pictureBase64: invite.groupPicture.isNotEmpty ? base64Encode(invite.groupPicture) : null,
      ownerNodeIdHex: ownerHex,
      members: members,
      membershipEpoch: newEpoch,
    );

    _groups[groupIdHex] = group;
    _saveGroups();

    // Create conversation (or update existing)
    final conv = conversations.putIfAbsent(groupIdHex, () => Conversation(
      id: groupIdHex,
      displayName: invite.groupName,
      isGroup: true,
      profilePictureBase64: group.pictureBase64,
    ));
    conv.displayName = invite.groupName;
    _saveConversations();

    if (!isUpdate) {
      onGroupInviteReceived?.call(groupIdHex, invite.groupName);
      _log.info('Group invite received: "${invite.groupName}" from ${senderHex.substring(0, 8)}');
    } else {
      _log.info('Group updated: "${invite.groupName}" from ${senderHex.substring(0, 8)}');
    }

    // Apply any pending config that arrived before the GROUP_INVITE
    final pendingConfig = _pendingGroupConfigs.remove(groupIdHex);
    if (pendingConfig != null) {
      final senderMember = group.members[pendingConfig.senderHex];
      if (senderMember != null && (senderMember.role == 'owner' || senderMember.role == 'admin')) {
        conv.config = pendingConfig.config;
        _saveConversations();
        _log.info('Applied buffered config for "${invite.groupName}" from ${pendingConfig.senderHex.substring(0, 8)}');
      }
    }

    onStateChanged?.call();
  }

  void _handleGroupLeaveV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.GroupLeave leaveMsg;
    try {
      leaveMsg = proto.GroupLeave.fromBuffer(frame.payload);
    } catch (e) {
      _log.error('GROUP_LEAVE parse failed: $e');
      return;
    }

    final groupIdHex = bytesToHex(Uint8List.fromList(leaveMsg.groupId));
    final group = _groups[groupIdHex];
    if (group == null) return;

    final memberName = group.members[senderHex]?.displayName ?? senderHex.substring(0, 8);
    final wasOwner = group.ownerNodeIdHex == senderHex;
    group.members.remove(senderHex);

    // If the owner left, transfer ownership to first admin or first member
    if (wasOwner && group.members.isNotEmpty) {
      final newOwner = group.members.values.where((m) => m.role == 'admin').firstOrNull
          ?? group.members.values.first;
      newOwner.role = 'owner';
      group.ownerNodeIdHex = newOwner.nodeIdHex;
      _log.info('Owner left, transferred to ${newOwner.displayName}');
    }
    _saveGroups();

    // Add system message
    final sysMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: groupIdHex,
      senderNodeIdHex: '',
      text: '$memberName hat die Gruppe verlassen',
      timestamp: DateTime.now(),
      type: UiMessageType.groupLeave,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    _addMessageToConversation(groupIdHex, sysMsg, isGroup: true);
    _log.info('$memberName left group "${group.name}"');
  }
  // GROUP_KEY_UPDATE: no shared group key in pairwise-KEM model (§9.1).
  void _handleGroupKeyUpdateV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {}
  void _handleChannelCreateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    // CHANNEL_CREATE shares the CHANNEL_INVITE payload schema and processing path.
    _handleChannelInviteV3(frame, senderDeviceId, snapshot);
  }
  void _handleChannelPostV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    // Route to channel via groupId field
    final channelIdHex = frame.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(frame.groupId))
        : '';
    if (channelIdHex.isEmpty) return;

    final channel = _channels[channelIdHex];
    if (channel == null) {
      _log.warn('CHANNEL_POST for unknown channel $channelIdHex');
      return;
    }

    // Verify sender is owner or admin (post permission)
    final senderMember = channel.members[senderHex];
    if (senderMember == null || (senderMember.role != 'owner' && senderMember.role != 'admin')) {
      _log.warn('CHANNEL_POST from unauthorized sender $senderHex');
      return;
    }

    // GM-4 (§9.1.4): split-view detection on channel posts
    bool isMembershipMismatch = false;
    final wireEpoch = frame.groupMembershipEpoch.toInt();
    if (wireEpoch > 0 && frame.groupMembershipHash.isNotEmpty) {
      final wireHash = Uint8List.fromList(frame.groupMembershipHash);
      final localEpoch = channel.membershipEpoch;
      final localHash = _computeChannelMembershipHash(
          localEpoch, channelIdHex, channel.members);
      if (wireEpoch == localEpoch && !_bytesEqual(wireHash, localHash)) {
        // Same epoch, different hash → split-view anomaly
        _log.warn('GM-4: CHANNEL SPLIT-VIEW in "${channel.name}" — '
            'local epoch=$localEpoch, wire epoch=$wireEpoch, hash mismatch '
            'from ${senderHex.substring(0, 8)}');
        isMembershipMismatch = true;
      } else if (wireEpoch > localEpoch) {
        // Sender has newer membership — edge-triggered resync to owner
        final prevRequested = _resyncRequestedAtEpoch[channelIdHex] ?? 0;
        if (wireEpoch > prevRequested) {
          _resyncRequestedAtEpoch[channelIdHex] = wireEpoch;
          _sendChannelResyncRequest(channel);
        }
      } else if (wireEpoch < localEpoch &&
          !_bytesEqual(wireHash, _computeChannelMembershipHash(
              wireEpoch, channelIdHex, channel.members))) {
        isMembershipMismatch = true;
      }
    }

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    final text = utf8.decode(frame.payload, allowMalformed: true);
    final msgId = bytesToHex(Uint8List.fromList(frame.messageId));

    final msg = UiMessage(
      id: msgId,
      conversationId: channelIdHex,
      senderNodeIdHex: senderHex,
      text: text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(frame.timestampMs.toInt()),
      type: UiMessageType.channelPost,
      status: MessageStatus.delivered,
      isOutgoing: false,
      membershipMismatch: isMembershipMismatch,
    );

    _addMessageToConversation(channelIdHex, msg, isChannel: true);
    _log.debug('Channel post received in "${channel.name}" from ${senderMember.displayName}');
  }

  void _handleChannelInviteV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.ChannelInvite invite;
    try {
      invite = proto.ChannelInvite.fromBuffer(frame.payload);
    } catch (e) {
      _log.error('CHANNEL_INVITE parse failed: $e');
      return;
    }

    final channelIdHex = bytesToHex(Uint8List.fromList(invite.channelId));

    // Build members map from the repeated GroupMemberV3 field
    final members = <String, ChannelMemberInfo>{};
    for (final m in invite.members) {
      final nid = bytesToHex(Uint8List.fromList(m.nodeId));
      members[nid] = ChannelMemberInfo(
        nodeIdHex: nid,
        displayName: m.displayName,
        role: m.role,
        ed25519Pk: m.ed25519PublicKey.isEmpty ? null : Uint8List.fromList(m.ed25519PublicKey),
        x25519Pk: m.x25519PublicKey.isEmpty ? null : Uint8List.fromList(m.x25519PublicKey),
        mlKemPk: m.mlKemPublicKey.isEmpty ? null : Uint8List.fromList(m.mlKemPublicKey),
      );
    }

    // Determine owner
    final inviterHex = bytesToHex(Uint8List.fromList(invite.inviterId));
    final ownerHex = members.values.where((m) => m.role == 'owner').firstOrNull?.nodeIdHex ?? inviterHex;

    // GM-4 (§9.1.4): Authority gate for existing channels
    final oldChannel = _channels[channelIdHex];
    final isUpdate = oldChannel != null;
    int newEpoch = 0;

    if (isUpdate) {
      final wireEpoch = invite.membershipEpoch.toInt();

      if (wireEpoch > 0) {
        // Sender must be owner or admin in the OLD state
        final senderOldMember = oldChannel.members[senderHex];
        if (senderOldMember == null ||
            (senderOldMember.role != 'owner' && senderOldMember.role != 'admin')) {
          _log.warn('GM-4: CHANNEL_INVITE from non-admin ${senderHex.substring(0, 8)} '
              'in "${oldChannel.name}" — rejected');
          return;
        }

        // Epoch must be strictly increasing
        if (wireEpoch <= oldChannel.membershipEpoch) {
          _log.warn('GM-4: CHANNEL_INVITE epoch $wireEpoch <= ${oldChannel.membershipEpoch} '
              'in "${oldChannel.name}" — rejected (replay/downgrade)');
          return;
        }

        // Verify hybrid signature over membership hash
        final wireHash = Uint8List.fromList(invite.membershipHash);
        final sigEd = Uint8List.fromList(invite.membershipSigEd25519);
        final sigMl = Uint8List.fromList(invite.membershipSigMlDsa);
        if (wireHash.isNotEmpty && sigEd.isNotEmpty) {
          final senderEd25519Pk = senderOldMember.ed25519Pk;
          if (senderEd25519Pk != null && senderEd25519Pk.isNotEmpty) {
            if (!SodiumFFI().verifyEd25519(wireHash, sigEd, senderEd25519Pk)) {
              _log.warn('GM-4: CHANNEL_INVITE Ed25519 sig invalid from ${senderHex.substring(0, 8)} — rejected');
              return;
            }
          }
          if (sigMl.isNotEmpty) {
            final senderMlDsaPk = _contacts[senderHex]?.mlDsaPk;
            if (senderMlDsaPk != null && senderMlDsaPk.isNotEmpty) {
              if (!OqsFFI().mlDsaVerify(wireHash, sigMl, senderMlDsaPk)) {
                _log.warn('GM-4: CHANNEL_INVITE ML-DSA sig invalid from ${senderHex.substring(0, 8)} — rejected');
                return;
              }
            }
          }
          // Verify hash matches the member list
          final expectedHash = _computeChannelMembershipHash(wireEpoch, channelIdHex, members);
          if (!_bytesEqual(wireHash, expectedHash)) {
            _log.warn('GM-4: CHANNEL_INVITE hash mismatch — tampered member list? Rejected.');
            return;
          }
        }
        newEpoch = wireEpoch;
      } else {
        // Legacy sender (no epoch) — accept as legacy-unverified
        newEpoch = oldChannel.membershipEpoch;
      }
    } else {
      // New channel — accept with wire epoch
      newEpoch = invite.membershipEpoch.toInt();
      if (newEpoch <= 0) newEpoch = 1;
    }

    final channel = ChannelInfo(
      channelIdHex: channelIdHex,
      name: invite.channelName,
      description: invite.channelDescription.isNotEmpty ? invite.channelDescription : null,
      pictureBase64: invite.channelPicture.isNotEmpty ? base64Encode(invite.channelPicture) : null,
      ownerNodeIdHex: ownerHex,
      members: members,
      isPublic: invite.isPublic,
      isAdult: invite.isAdult,
      language: invite.language.isNotEmpty ? invite.language : 'de',
      membershipEpoch: newEpoch,
    );

    _channels[channelIdHex] = channel;
    _saveChannels();

    // Create conversation (or update existing)
    final conv = conversations.putIfAbsent(channelIdHex, () => Conversation(
      id: channelIdHex,
      displayName: invite.channelName,
      isChannel: true,
      profilePictureBase64: channel.pictureBase64,
    ));
    conv.displayName = invite.channelName;
    _saveConversations();

    if (!isUpdate) {
      onChannelInviteReceived?.call(channelIdHex, invite.channelName);
      _log.info('Channel invite received: "${invite.channelName}" from ${senderHex.substring(0, 8)}');
    } else {
      _log.info('Channel updated: "${invite.channelName}" from ${senderHex.substring(0, 8)}');
    }

    // Apply any pending config that arrived before the CHANNEL_INVITE
    final pendingConfig = _pendingGroupConfigs.remove(channelIdHex);
    if (pendingConfig != null) {
      final senderMember = channel.members[pendingConfig.senderHex];
      if (senderMember != null && (senderMember.role == 'owner' || senderMember.role == 'admin')) {
        conv.config = pendingConfig.config;
        _saveConversations();
        _log.info('Applied buffered config for channel "${invite.channelName}" from ${pendingConfig.senderHex.substring(0, 8)}');
      }
    }

    onStateChanged?.call();
  }

  void _handleChannelLeaveV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.ChannelLeave leaveMsg;
    try {
      leaveMsg = proto.ChannelLeave.fromBuffer(frame.payload);
    } catch (e) {
      _log.error('CHANNEL_LEAVE parse failed: $e');
      return;
    }

    final channelIdHex = bytesToHex(Uint8List.fromList(leaveMsg.channelId));
    final channel = _channels[channelIdHex];
    if (channel == null) return;

    final memberName = channel.members[senderHex]?.displayName ?? senderHex.substring(0, 8);
    final wasOwner = channel.ownerNodeIdHex == senderHex;
    channel.members.remove(senderHex);

    // If the owner left, transfer ownership
    if (wasOwner && channel.members.isNotEmpty) {
      final newOwner = channel.members.values.where((m) => m.role == 'admin').firstOrNull
          ?? channel.members.values.first;
      newOwner.role = 'owner';
      channel.ownerNodeIdHex = newOwner.nodeIdHex;
      _log.info('Channel owner left, transferred to ${newOwner.displayName}');
    }
    _saveChannels();

    // Add system message
    final sysMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: channelIdHex,
      senderNodeIdHex: '',
      text: '$memberName hat den Channel verlassen',
      timestamp: DateTime.now(),
      type: UiMessageType.channelLeave,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    _addMessageToConversation(channelIdHex, sysMsg, isChannel: true);
    _log.info('$memberName left channel "${channel.name}"');
  }

  /// Handle CHANNEL_ROLE_UPDATE (type 73): update member role in channel or group.
  /// Architecture v3.0 Section 10.2: sent to ALL members, handler checks both
  /// channelManager and groupManager. Only owner/admin may change roles.
  void _handleChannelRoleUpdateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.ChannelRoleUpdate roleMsg;
    try {
      roleMsg = proto.ChannelRoleUpdate.fromBuffer(frame.payload);
    } catch (e) {
      _log.error('CHANNEL_ROLE_UPDATE parse failed: $e');
      return;
    }

    final entityIdHex = bytesToHex(Uint8List.fromList(roleMsg.channelId));
    final targetIdHex = bytesToHex(Uint8List.fromList(roleMsg.targetId));
    final newRole = roleMsg.newRole;

    // Check both channels and groups (Architecture v3.0: dual-mode handler)
    final channel = _channels[entityIdHex];
    final group = _groups[entityIdHex];

    if (channel != null) {
      // Verify sender is owner — only Owner can change roles (Architecture §10.2).
      final senderMember = channel.members[senderHex];
      if (senderMember == null || senderMember.role != 'owner') {
        _log.warn('CHANNEL_ROLE_UPDATE rejected: $senderHex is not owner in channel $entityIdHex');
        return;
      }

      final target = channel.members[targetIdHex];
      if (target == null) {
        _log.warn('CHANNEL_ROLE_UPDATE: target $targetIdHex not a member of channel $entityIdHex');
        return;
      }

      final oldRole = target.role;
      target.role = newRole;

      // Handle ownership transfer
      if (newRole == 'owner') {
        // Demote previous owner to admin
        final prevOwner = channel.members[channel.ownerNodeIdHex];
        if (prevOwner != null) prevOwner.role = 'admin';
        channel.ownerNodeIdHex = targetIdHex;
      }

      channel.membershipEpoch++;
      _saveChannels();

      final sysMsg = UiMessage(
        id: bytesToHex(SodiumFFI().randomBytes(16)),
        conversationId: entityIdHex,
        senderNodeIdHex: '',
        text: '${target.displayName}: $oldRole → $newRole',
        timestamp: DateTime.now(),
        type: UiMessageType.channelRoleUpdate,
        status: MessageStatus.delivered,
        isOutgoing: false,
      );
      _addMessageToConversation(entityIdHex, sysMsg, isChannel: true);
      _log.info('Channel role update: ${target.displayName} $oldRole → $newRole in "${channel.name}"');

    } else if (group != null) {
      // Verify sender is owner — only Owner can change roles (Architecture §10.2).
      final senderMember = group.members[senderHex];
      if (senderMember == null || senderMember.role != 'owner') {
        _log.warn('CHANNEL_ROLE_UPDATE rejected: $senderHex is not owner in group $entityIdHex');
        return;
      }

      final target = group.members[targetIdHex];
      if (target == null) {
        _log.warn('CHANNEL_ROLE_UPDATE: target $targetIdHex not a member of group $entityIdHex');
        return;
      }

      final oldRole = target.role;
      target.role = newRole;

      if (newRole == 'owner') {
        final prevOwner = group.members[group.ownerNodeIdHex];
        if (prevOwner != null) prevOwner.role = 'admin';
        group.ownerNodeIdHex = targetIdHex;
      }

      group.membershipEpoch++;
      _saveGroups();

      final sysMsg = UiMessage(
        id: bytesToHex(SodiumFFI().randomBytes(16)),
        conversationId: entityIdHex,
        senderNodeIdHex: '',
        text: '${target.displayName}: $oldRole → $newRole',
        timestamp: DateTime.now(),
        type: UiMessageType.channelRoleUpdate,
        status: MessageStatus.delivered,
        isOutgoing: false,
      );
      _addMessageToConversation(entityIdHex, sysMsg);
      _log.info('Group role update: ${target.displayName} $oldRole → $newRole in "${group.name}"');

    } else {
      _log.debug('CHANNEL_ROLE_UPDATE: entity $entityIdHex not found (not a member)');
    }

    onStateChanged?.call();
  }
  // Moderation V3 handlers — delegated to ChannelModerationService.
  void handleIncomingChannelIndexExchangeInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) => _moderation.handleChannelIndexExchangeInfra(frame, senderDeviceId, sourceAddr, sourcePort, snapshot);
  // Wave 2B.3: PEER_LIST_*, DHT_*, FRAGMENT_*, PEER_STORE_* dead-stub
  // declarations removed. PEER_LIST_*/DHT_* are §2.3.5 Infrastructure types
  // dispatched in cleona_node.dart's `_dispatchInfrastructureFrameLocal`.
  // FRAGMENT_*/PEER_STORE_* are dispatched via the service-layer Infra hook
  // (service_daemon.dart `node.onInfrastructureFramePayload`) into
  // `handleIncomingFragmentStoreInfra` etc.
  void _handleChatConfigUpdateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    // V3 direct: the inner payload is the ChatConfigUpdate protobuf,
    // already decrypted + authenticated by the V3 pipeline.
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

    proto.ChatConfigUpdate configMsg;
    try {
      configMsg = proto.ChatConfigUpdate.fromBuffer(frame.payload);
    } catch (e) {
      _log.error('CHAT_CONFIG_UPDATE parse failed: $e');
      return;
    }

    final newConfig = ChatConfig(
      allowDownloads: configMsg.allowDownloads,
      allowForwarding: configMsg.allowForwarding,
      editWindowMs: configMsg.hasEditWindowMs() ? configMsg.editWindowMs.toInt() : null,
      expiryDurationMs: configMsg.hasExpiryDurationMs() ? configMsg.expiryDurationMs.toInt() : null,
      readReceipts: configMsg.readReceipts,
      typingIndicators: configMsg.typingIndicators,
    );

    // Check if this is a group config update
    final groupIdHex = frame.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(frame.groupId))
        : null;

    if (groupIdHex != null) {
      // Group or channel config: apply directly (sender must be owner or admin)
      final group = _groups[groupIdHex];
      final channel = _channels[groupIdHex];
      if (group != null) {
        final senderMember = group.members[senderHex];
        if (senderMember == null) return;
        if (senderMember.role != 'owner' && senderMember.role != 'admin') {
          _log.warn('Group config rejected: ${senderHex.substring(0, 8)} is ${senderMember.role}');
          return;
        }
        final conv = conversations[groupIdHex];
        if (conv != null) {
          conv.config = newConfig;
          _saveConversations();
        }
        onStateChanged?.call();
        _log.info('Group config updated by ${senderMember.displayName} for "${group.name}"');
        return;
      }
      if (channel != null) {
        final senderMember = channel.members[senderHex];
        if (senderMember == null) return;
        if (senderMember.role != 'owner' && senderMember.role != 'admin') {
          _log.warn('Channel config rejected: ${senderHex.substring(0, 8)} is ${senderMember.role}');
          return;
        }
        final conv = conversations[groupIdHex];
        if (conv != null) {
          conv.config = newConfig;
          _saveConversations();
        }
        onStateChanged?.call();
        _log.info('Channel config updated by ${senderMember.displayName} for "${channel.name}"');
        return;
      }
      // Unknown group/channel — buffer config for when GROUP_INVITE arrives
      _pendingGroupConfigs[groupIdHex] = (config: newConfig, senderHex: senderHex);
      _log.info('Buffered config for unknown group/channel ${groupIdHex.substring(0, 8)} from ${senderHex.substring(0, 8)}');
      return;
    }

    // DM config: handle proposal/response
    if (configMsg.isRequest) {
      // Peer proposes new config — store as pending, do NOT apply yet
      final conv = conversations[senderHex] ?? conversations.putIfAbsent(
        senderHex,
        () => Conversation(id: senderHex, displayName: _contacts[senderHex]?.displayName ?? ''),
      );
      conv.pendingConfigProposal = newConfig;
      conv.pendingConfigProposer = senderHex;
      conv.unreadCount++;
      _updateBadgeCount();
      _saveConversations();
      onStateChanged?.call();
      _log.info('DM config proposal received from ${_contacts[senderHex]?.displayName ?? senderHex.substring(0, 8)} — awaiting accept/reject');
    } else if (configMsg.accepted) {
      // Peer accepted our proposal — NOW apply the config on our side
      final conv = conversations[senderHex];
      if (conv != null && conv.pendingConfigProposal != null) {
        conv.config = conv.pendingConfigProposal!;
        conv.pendingConfigProposal = null;
        conv.pendingConfigProposer = null;
        _saveConversations();
      }
      onStateChanged?.call();
      _log.info('DM config accepted by ${senderHex.substring(0, 8)}');
    } else {
      // Peer rejected our proposal — clear pending
      final conv = conversations[senderHex];
      if (conv != null) {
        conv.pendingConfigProposal = null;
        conv.pendingConfigProposer = null;
        _saveConversations();
      }
      onStateChanged?.call();
      _log.info('DM config rejected by ${senderHex.substring(0, 8)}');
    }
  }
  // CHAT_CONFIG_RESPONSE (type 141): dead code — the protocol uses
  // CHAT_CONFIG_UPDATE (type 140) with `accepted` flag for both request
  // and response directions. Type 141 is never sent.
  void _handleChatConfigResponseV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {}

  // Wave 2B.3: ROUTE_UPDATE, REACHABILITY_*, RELAY_*, HOLE_PUNCH_*
  // dead-stub declarations removed — all dispatched in cleona_node.dart
  // (`_dispatchInfrastructureFrameLocal`, see Wave 2B.3 section). RELAY_*
  // remains on the KEM-path with §5.5 logic (out of Wave 2B.3 scope).

  // IDENTITY_AUTH/LIVE_* (types 170-175): dispatched as InfrastructureFrames
  // in cleona_node.dart (lines 1722-1850). These ApplicationFrame stubs are
  // unreachable — kept only for switch-case exhaustiveness.
  void _handleIdentityAuthPublishV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {}
  void _handleIdentityAuthRetrieveV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {}
  void _handleIdentityAuthResponseV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {}
  void _handleIdentityLivePublishV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {}
  void _handleIdentityLiveRetrieveV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {}
  void _handleIdentityLiveResponseV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {}
  void _handleTwinSyncV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    // The inner payload is the TwinSyncEnvelope protobuf, already
    // decrypted + authenticated by the V3 pipeline. Sub-handlers operate
    // on raw payload bytes.
    try {
      final sync = proto.TwinSyncEnvelope.fromBuffer(frame.payload);
      final syncIdHex = bytesToHex(Uint8List.fromList(sync.syncId));
      final deviceIdHex = bytesToHex(Uint8List.fromList(sync.deviceId));

      // Deduplication: syncId seen within 7-day TTL window → silent drop.
      if (_processedSyncIds.containsKey(syncIdHex)) return;
      _processedSyncIds[syncIdHex] = DateTime.now().millisecondsSinceEpoch;

      // Update device lastSeen
      if (_devices.containsKey(deviceIdHex)) {
        _devices[deviceIdHex]!.lastSeen = DateTime.now();
      }

      _log.debug('TWIN_SYNC(${sync.syncType}) from device ${deviceIdHex.substring(0, 8)}');

      switch (sync.syncType) {
        case proto.TwinSyncType.CONTACT_ADDED:
          _handleTwinContactAdded(sync.payload);
          break;
        case proto.TwinSyncType.CONTACT_DELETED:
          _handleTwinContactDeleted(sync.payload);
          break;
        case proto.TwinSyncType.MESSAGE_SENT:
          _handleTwinMessageSent(sync.payload);
          break;
        case proto.TwinSyncType.MESSAGE_EDITED:
          _handleTwinMessageEdited(sync.payload);
          break;
        case proto.TwinSyncType.MESSAGE_DELETED:
          _handleTwinMessageDeleted(sync.payload);
          break;
        case proto.TwinSyncType.TWIN_READ_RECEIPT:
          _handleTwinReadReceipt(sync.payload);
          break;
        case proto.TwinSyncType.GROUP_CREATED:
          _handleTwinGroupCreated(sync.payload);
          break;
        case proto.TwinSyncType.PROFILE_CHANGED:
          _handleTwinProfileChanged(sync.payload);
          break;
        case proto.TwinSyncType.SETTINGS_CHANGED:
          _handleTwinSettingsChanged(sync.payload);
          break;
        case proto.TwinSyncType.DEVICE_RENAMED:
          _handleTwinDeviceRenamed(sync.payload);
          break;
        case proto.TwinSyncType.TWIN_DEVICE_REVOKED:
          _handleTwinDeviceRevoked(sync.payload);
          break;
        case proto.TwinSyncType.DEVICE_ANNOUNCE:
          // §26 Multi-Device: V3 carries TWIN_ANNOUNCE as TWIN_SYNC sub-type.
          // sync.payload is the inner DeviceRecord proto.
          //
          // Reciprocal-announce only on the new-device branch — sending it on
          // every announce creates an A→B→A→B amplification loop because
          // each side keeps updating lastSeen and re-announcing.
          // Convergence in two rounds: A announces, B registers + reciprocates,
          // A receives B's announce, A registers (new for A), A reciprocates
          // once more, B updates lastSeen and stops.
          try {
            final record = proto.DeviceRecord.fromBuffer(sync.payload);
            final announcedHex = bytesToHex(Uint8List.fromList(record.deviceId));
            if (announcedHex == _localDeviceId) break; // ignore self-loop

            final devNodeIdHex = record.deviceNodeId.isNotEmpty
                ? bytesToHex(Uint8List.fromList(record.deviceNodeId))
                : null;

            final now = DateTime.now();
            final isNew = !_devices.containsKey(announcedHex);
            if (isNew) {
              _devices[announcedHex] = DeviceRecord(
                deviceId: announcedHex,
                deviceName: record.deviceName,
                platform: _detectPlatformFromProto(record.platform),
                firstSeen: now,
                lastSeen: now,
                deviceNodeIdHex: devNodeIdHex,
              );
              _log.info('New twin device registered: $announcedHex (${record.deviceName})');
            } else {
              _devices[announcedHex]!.lastSeen = now;
              _devices[announcedHex]!.deviceName = record.deviceName;
              if (devNodeIdHex != null) {
                _devices[announcedHex]!.deviceNodeIdHex = devNodeIdHex;
              }
            }
            _notifyDevicesChanged();
            if (isNew) _sendTwinAnnounce();
          } catch (e) {
            _log.error('DEVICE_ANNOUNCE processing failed: $e');
          }
          break;
        case proto.TwinSyncType.ROTATION_APPROVAL_REQUEST:
          _handleRotationApprovalRequest(sync.payload, senderDeviceId);
          break;
        case proto.TwinSyncType.ROTATION_APPROVAL_RESPONSE:
          _handleRotationApprovalResponse(sync.payload, senderDeviceId);
          break;
        default:
          _log.debug('Unhandled TWIN_SYNC type: ${sync.syncType}');
      }
      _saveDevices(); // Persist dedup IDs
    } catch (e) {
      _log.error('TWIN_SYNC processing failed: $e');
    }
  }

  // §7.5: Co-Auth — collect approval tokens from linked devices during rotation.
  Completer<void>? _rotationApprovalCompleter;
  final List<RotationApprovalToken> _collectedApprovalTokens = [];
  Uint8List? _pendingRotationHash;

  /// §7.5: Linked Device receives ROTATION_APPROVAL_REQUEST from Primary.
  /// Signs the rotation hash with Device-Sig keys and sends back.
  void _handleRotationApprovalRequest(List<int> payload, Uint8List senderDeviceId) {
    try {
      final req = proto.RotationApprovalRequestPayload.fromBuffer(payload);
      final rotationHash = Uint8List.fromList(req.rotationHash);
      _log.info('§7.5 ROTATION_APPROVAL_REQUEST received — signing with Device-Sig keys');

      final deviceKp = node.deviceKeyPair;
      final ed25519Sig = SodiumFFI().signEd25519(rotationHash, deviceKp.ed25519PrivateKey);
      final mlDsaSig = OqsFFI().mlDsaSign(rotationHash, deviceKp.mlDsaPrivateKey);

      final token = proto.RotationApprovalToken()
        ..deviceNodeId = identity.deviceNodeId
        ..rotationHash = rotationHash
        ..deviceEd25519Sig = ed25519Sig
        ..deviceMlDsaSig = mlDsaSig;
      final response = proto.RotationApprovalResponsePayload()
        ..token = token
        ..rejected = false;

      _sendTwinSync(proto.TwinSyncType.ROTATION_APPROVAL_RESPONSE,
          Uint8List.fromList(response.writeToBuffer()));
      _log.info('§7.5 ROTATION_APPROVAL_RESPONSE sent (approved)');
    } catch (e) {
      _log.error('§7.5 ROTATION_APPROVAL_REQUEST handling failed: $e');
    }
  }

  /// §7.5: Primary receives ROTATION_APPROVAL_RESPONSE from a Linked Device.
  void _handleRotationApprovalResponse(List<int> payload, Uint8List senderDeviceId) {
    try {
      final resp = proto.RotationApprovalResponsePayload.fromBuffer(payload);
      if (_pendingRotationHash == null) {
        _log.warn('§7.5 ROTATION_APPROVAL_RESPONSE received but no rotation pending');
        return;
      }
      final senderHex = bytesToHex(senderDeviceId);
      if (resp.rejected) {
        _log.warn('§7.5 Device ${senderHex.substring(0, 8)} REJECTED rotation — '
            'sending ROTATION_REJECTION_ALERT to contacts');
        _sendRotationRejectionAlert(senderDeviceId);
        return;
      }
      if (!resp.hasToken()) {
        _log.warn('§7.5 ROTATION_APPROVAL_RESPONSE without token from '
            '${senderHex.substring(0, 8)} — skipped');
        return;
      }
      _collectedApprovalTokens.add(RotationApprovalToken.fromProto(resp.token));
      _log.info('§7.5 Collected approval ${_collectedApprovalTokens.length} '
          'from ${senderHex.substring(0, 8)}');

      final pub = _identityPublisher;
      final totalDevices = (pub?.delegations.length ?? 0) + 1;
      final required = rotationQuorum(totalDevices);
      if (_collectedApprovalTokens.length + 1 >= required) {
        _rotationApprovalCompleter?.complete();
      }
    } catch (e) {
      _log.error('§7.5 ROTATION_APPROVAL_RESPONSE handling failed: $e');
    }
  }

  /// §7.5: A Linked Device actively rejects the rotation — sends alert
  /// DIRECTLY to all contacts (bypassing Primary, which may be compromised).
  void _sendRotationRejectionAlert(Uint8List rejectingDeviceId) {
    final rotHash = _pendingRotationHash ?? Uint8List(0);
    final deviceKp = node.deviceKeyPair;
    final alert = proto.RotationRejectionAlertPayload()
      ..userId = identity.userId
      ..deviceNodeId = rejectingDeviceId
      ..rotationHash = rotHash
      ..deviceEd25519Sig = SodiumFFI().signEd25519(rotHash, deviceKp.ed25519PrivateKey)
      ..deviceMlDsaSig = OqsFFI().mlDsaSign(rotHash, deviceKp.mlDsaPrivateKey);

    final payloadBytes = Uint8List.fromList(alert.writeToBuffer());
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      try {
        sendToUser(
          recipientUserId: contact.nodeId,
          messageType: proto.MessageTypeV3.MTV3_ROTATION_REJECTION_ALERT,
          payload: payloadBytes,
        );
      } catch (e) {
        _log.warn('§7.5 Failed to send ROTATION_REJECTION_ALERT to '
            '${contact.displayName}: $e');
      }
    }
  }

  // §7.1 LD-2: Pending pair requests awaiting user approval on this (Primary) device.
  final Map<String, proto.DevicePairRequestV3> _pendingPairRequests = {};

  void _handleDevicePairRequestV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    try {
      final request = proto.DevicePairRequestV3.fromBuffer(f.payload);
      final deviceIdHex = bytesToHex(sd);
      _log.info('DEVICE_PAIR_REQUEST from device $deviceIdHex');

      if (identity.masterSeed == null) {
        _log.warn('Ignoring pair request: this device is not the Primary (no seed)');
        return;
      }

      // §7.1 LD-9: auto-approve renewal from known linked devices
      final pub = _identityPublisher;
      if (pub != null) {
        final isKnownLinked = pub.delegations
            .any((d) => bytesToHex(d.deviceId) == deviceIdHex);
        if (isKnownLinked) {
          _log.info('LD-9: auto-approving renewal for known linked device '
              '${deviceIdHex.substring(0, 8)}');
          _pendingPairRequests[deviceIdHex] = request;
          approvePairRequest(deviceIdHex);
          return;
        }
      }

      _pendingPairRequests[deviceIdHex] = request;
      onDevicePairRequest?.call(deviceIdHex);
    } catch (e) {
      _log.error('Failed to parse DEVICE_PAIR_REQUEST: $e');
    }
  }

  /// §7.1 LD-11: Initiate pairing from this device (wants to become Linked).
  /// Sends DEVICE_PAIR_REQUEST to our own userId — the Primary picks it up.
  /// Also used for renewal (LD-9): already-linked devices can re-request to
  /// get a fresh cert with a new 30-day window.
  @override
  Future<bool> sendDevicePairRequest() async {
    final request = proto.DevicePairRequestV3()
      ..deviceEd25519Pk = node.deviceKeyPair.ed25519PublicKey
      ..deviceMlDsaPk = node.deviceKeyPair.mlDsaPublicKey
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch);

    final sent = await sendToUser(
      recipientUserId: identity.userId,
      messageType: proto.MessageTypeV3.MTV3_DEVICE_PAIR_REQUEST,
      payload: request.writeToBuffer(),
    );

    if (sent) {
      _log.info('DEVICE_PAIR_REQUEST sent to own userId '
          '(${identity.isLinkedDevice ? "renewal" : "initial pairing"})');
    } else {
      _log.warn('DEVICE_PAIR_REQUEST send failed — no route to Primary');
    }
    return sent;
  }

  void _handleDevicePairApproveV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    try {
      final approve = proto.DevicePairApproveV3.fromBuffer(f.payload);
      final senderHex = bytesToHex(sd);
      _log.info('DEVICE_PAIR_APPROVE from $senderHex — storing linked-device keys');

      final parsed = DevicePairingService().parseApproval(approve);

      if (!parsed.delegationCert.verify(
          identity.ed25519PublicKey, identity.mlDsaPublicKey)) {
        _log.error('DEVICE_PAIR_APPROVE: delegation cert signature INVALID — rejecting');
        return;
      }

      LinkedDeviceKeysStore.save(
        profileDir: profileDir,
        fileEnc: _fileEnc,
        keys: parsed,
      );
      applyLinkedDeviceKeys(parsed);
      _log.info('DEVICE_PAIR_APPROVE accepted — persisted + applied, '
          'caps=${parsed.delegationCert.capabilities}, '
          'expiry=${parsed.delegationCert.maxValidUntilMs > 0 ? "${((parsed.delegationCert.maxValidUntilMs - DateTime.now().millisecondsSinceEpoch) / 86400000).toStringAsFixed(0)}d" : "none"}');
    } catch (e) {
      _log.error('Failed to process DEVICE_PAIR_APPROVE: $e');
    }
  }

  /// §7.1 LD-2: Called from IPC when the user approves a pending pair request.
  /// Builds the delegation material and sends DEVICE_PAIR_APPROVE to the requester.
  Future<bool> approvePairRequest(String requestingDeviceIdHex) async {
    final request = _pendingPairRequests.remove(requestingDeviceIdHex);
    if (request == null) {
      _log.warn('approvePairRequest: no pending request for $requestingDeviceIdHex');
      return false;
    }

    final newDeviceId = hexToBytes(requestingDeviceIdHex);
    final result = DevicePairingService().buildApproval(
      identity: identity,
      newDeviceId: newDeviceId,
    );

    // Send the approval (KEM-encrypted to the requesting device)
    final sent = await sendToUser(
      recipientUserId: identity.userId,
      messageType: proto.MessageTypeV3.MTV3_DEVICE_PAIR_APPROVE,
      payload: result.approvePayload.writeToBuffer(),
    );

    if (sent) {
      _log.info('DEVICE_PAIR_APPROVE sent to $requestingDeviceIdHex');
      // Update AuthManifest with the new delegation
      _addDeviceDelegation(newDeviceId, result.delegationCert);
      // §7.5: register linked device's Device-Sig pubkeys for Co-Auth
      _identityPublisher?.addLinkedDeviceSigKeys(DeviceSigInfo(
        deviceNodeId: newDeviceId,
        deviceEd25519Pk: Uint8List.fromList(request.deviceEd25519Pk),
        deviceMlDsaPk: Uint8List.fromList(request.deviceMlDsaPk),
        isPrimary: false,
      ));
    }
    return sent;
  }

  void _addDeviceDelegation(Uint8List deviceId, DeviceDelegation cert) {
    // Add to authorized devices list (backward compat for old builds)
    final deviceIdHex = bytesToHex(deviceId);
    if (!_devices.containsKey(deviceIdHex)) {
      final now = DateTime.now();
      _devices[deviceIdHex] = DeviceRecord(
        deviceId: deviceIdHex,
        deviceName: 'Linked-${deviceIdHex.substring(0, 6)}',
        platform: 'unknown',
        firstSeen: now,
        lastSeen: now,
        deviceNodeIdHex: deviceIdHex,
      );
      _saveDevices();
    }

    // Republish AuthManifest with the new delegation cert
    _identityPublisher?.addDelegation(cert);
    _log.info('Added device delegation for ${deviceIdHex.substring(0, 8)}, '
        'republishing AuthManifest');
  }

  /// §7.1 LD-7: Soft migration — apply LinkedDeviceKeys received via pairing
  /// to this IdentityContext. Called when the user opts to convert a legacy
  /// twin-device (seed-on-every-device) to the delegation model.
  ///
  /// After this call, [identity.isLinkedDevice] becomes true and all
  /// Inner-Sigs use the delegated keys. The master seed is NOT wiped here
  /// (that's a destructive operation requiring explicit user confirmation
  /// in the GUI); it simply becomes unused for signing.
  void applyLinkedDeviceKeys(LinkedDeviceKeys keys) {
    identity.linkedDeviceKeys = keys;
    _log.info('Applied linked-device delegation keys — '
        'isLinkedDevice=${identity.isLinkedDevice}, '
        'caps=${keys.delegationCert.capabilities}');
  }

  /// §7.1 LD-9: Periodic check — request renewal when cert expires within 7 days.
  void _checkDelegationRenewal() {
    if (!identity.isLinkedDevice) return;
    final ldKeys = identity.linkedDeviceKeys;
    if (ldKeys == null) return;
    final cert = ldKeys.delegationCert;
    if (cert.maxValidUntilMs == 0) return;
    final remainingMs =
        cert.maxValidUntilMs - DateTime.now().millisecondsSinceEpoch;
    final remainingDays = remainingMs / (24 * 60 * 60 * 1000);
    if (remainingDays <= 7 && remainingDays > 0) {
      _log.info('LD-9: delegation cert expires in ${remainingDays.toStringAsFixed(1)} days — requesting renewal');
      requestDelegationRenewal();
    } else if (remainingDays <= 0) {
      _log.warn('LD-9: delegation cert EXPIRED — requesting renewal');
      requestDelegationRenewal();
    }
  }

  /// §7.1 LD-8: Send per-device delegation rotation to a Linked Device.
  /// Called from rotateIdentityKeys() BEFORE applying new keys locally,
  /// so the TWIN_SYNC envelope is signed with the OLD User-Keys.
  void _sendDelegationRotation({
    required Uint8List targetDeviceId,
    required int capabilities,
    required int maxValidUntilMs,
    required Uint8List newMasterSeed,
    required Uint8List newEd25519Pk,
    required Uint8List newMlDsaPk,
    required Uint8List newX25519Pk,
    required Uint8List newMlKemPk,
    required Uint8List newX25519Sk,
    required Uint8List newMlKemSk,
  }) {
    final delegEd = HdWallet.deriveDelegatedEd25519(newMasterSeed, targetDeviceId);
    final mlDsaSeed = HdWallet.deriveDelegatedMlDsaSeed(newMasterSeed, targetDeviceId);
    final delegMlDsa = OqsFFI().mlDsaKeypairDerand(mlDsaSeed);

    // Cert signed with OLD User-Keys (Linked Device can verify)
    final cert = DeviceDelegation.sign(
      deviceId: targetDeviceId,
      delegatedEd25519Pk: delegEd.publicKey,
      delegatedMlDsaPk: delegMlDsa.publicKey,
      capabilities: capabilities,
      maxValidUntilMs: maxValidUntilMs,
      userEd25519Sk: identity.ed25519SecretKey,
      userMlDsaSk: identity.mlDsaSecretKey,
    );

    final payload = utf8.encode(jsonEncode({
      'delegationRotation': true,
      'targetDeviceId': bytesToHex(targetDeviceId),
      'delegatedEd25519Pk': bytesToHex(delegEd.publicKey),
      'delegatedEd25519Sk': bytesToHex(delegEd.secretKey),
      'delegatedMlDsaPk': bytesToHex(delegMlDsa.publicKey),
      'delegatedMlDsaSk': bytesToHex(delegMlDsa.secretKey),
      'newUserEd25519Pk': bytesToHex(newEd25519Pk),
      'newUserMlDsaPk': bytesToHex(newMlDsaPk),
      'newUserX25519Pk': bytesToHex(newX25519Pk),
      'newUserMlKemPk': bytesToHex(newMlKemPk),
      'newUserX25519Sk': bytesToHex(newX25519Sk),
      'newUserMlKemSk': bytesToHex(newMlKemSk),
      'delegationCertProto': bytesToHex(cert.toProtoBytes()),
    }));

    _sendTwinSync(
        proto.TwinSyncType.SETTINGS_CHANGED, Uint8List.fromList(payload));
    _log.info('LD-8: delegation rotation sent to '
        '${bytesToHex(targetDeviceId).substring(0, 8)}');
  }

  /// §7.1 LD-8: Handle delegation rotation on a Linked Device.
  Future<void> _handleDelegationRotation(Map<String, dynamic> json) async {
    final targetHex = json['targetDeviceId'] as String;
    if (targetHex != bytesToHex(identity.deviceNodeId)) return;

    if (!identity.isLinkedDevice) {
      _log.warn('LD-8: received delegation rotation but not a Linked Device');
      return;
    }

    final certBytes = hexToBytes(json['delegationCertProto'] as String);
    final cert = DeviceDelegation.fromProtoBytes(certBytes);

    if (!cert.verify(identity.ed25519PublicKey, identity.mlDsaPublicKey)) {
      _log.error('LD-8: delegation rotation cert INVALID — rejecting');
      return;
    }

    final newUserEd25519Pk = hexToBytes(json['newUserEd25519Pk'] as String);
    final newUserMlDsaPk = hexToBytes(json['newUserMlDsaPk'] as String);
    final newUserX25519Pk = hexToBytes(json['newUserX25519Pk'] as String);
    final newUserMlKemPk = hexToBytes(json['newUserMlKemPk'] as String);
    final newUserX25519Sk = hexToBytes(json['newUserX25519Sk'] as String);
    final newUserMlKemSk = hexToBytes(json['newUserMlKemSk'] as String);

    final newLinkedKeys = LinkedDeviceKeys(
      delegatedEd25519Pk: hexToBytes(json['delegatedEd25519Pk'] as String),
      delegatedEd25519Sk: hexToBytes(json['delegatedEd25519Sk'] as String),
      delegatedMlDsaPk: hexToBytes(json['delegatedMlDsaPk'] as String),
      delegatedMlDsaSk: hexToBytes(json['delegatedMlDsaSk'] as String),
      userX25519Sk: newUserX25519Sk,
      userMlKemSk: newUserMlKemSk,
      delegationCert: cert,
      userId: identity.userId,
      displayName: identity.displayName,
    );

    LinkedDeviceKeysStore.save(
      profileDir: profileDir,
      fileEnc: _fileEnc,
      keys: newLinkedKeys,
    );

    identity.rotateDelegation(
      newUserEd25519Pk: newUserEd25519Pk,
      newUserMlDsaPk: newUserMlDsaPk,
      newUserX25519Pk: newUserX25519Pk,
      newUserMlKemPk: newUserMlKemPk,
      newUserX25519Sk: newUserX25519Sk,
      newUserMlKemSk: newUserMlKemSk,
      newLinkedKeys: newLinkedKeys,
    );

    node.broadcastAddressUpdate();
    final pub = _identityPublisher;
    if (pub != null) {
      pub.stop();
      unawaited(pub.start());
    }
    onStateChanged?.call();
    _log.info('LD-8: delegation rotation applied from Primary — '
        'chain length ${identity.rotationChain.length}');
  }

  void _handleDeviceRevocationV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    // V3 direct: inner payload is the DeviceRecord protobuf, already
    // decrypted + authenticated by the V3 pipeline. §26 authorization check
    // preserved: only accepted contacts may revoke their own devices for us.
    final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') return;

    try {
      final revokedDevice = proto.DeviceRecord.fromBuffer(frame.payload);
      final deviceIdShort = bytesToHex(Uint8List.fromList(revokedDevice.deviceId)).substring(0, 8);

      // §26 Phase 4: remove by deviceNodeId (preferred, precise)
      if (revokedDevice.deviceNodeId.isNotEmpty) {
        final revokedNodeId = Uint8List.fromList(revokedDevice.deviceNodeId);
        final revokedNodeIdHex = bytesToHex(revokedNodeId);
        final removed = node.routingTable.removePeerByNodeId(revokedNodeId);
        contact.deviceNodeIds.remove(revokedNodeIdHex);
        _saveContacts();
        _log.info('DEVICE_REVOKED from ${contact.displayName}: '
            'device $deviceIdShort, routing entry ${removed ? "removed" : "not found"} '
            '(deviceNodeId ${revokedNodeIdHex.substring(0, 8)})');
        return;
      }

      // Fallback: remove by addresses (pre-Phase-4 peers without deviceNodeId)
      final revokedAddresses = revokedDevice.addresses
          .map((a) => '${a.ip}:${a.port}')
          .toSet();

      if (revokedAddresses.isEmpty) {
        _log.info('DEVICE_REVOKED from ${contact.displayName}: '
            'device $deviceIdShort revoked (no deviceNodeId or addresses to prune)');
        return;
      }

      final peer = node.routingTable.getPeerByUserId(contact.nodeId);
      if (peer != null) {
        final beforeCount = peer.addresses.length;
        peer.addresses.removeWhere(
            (a) => revokedAddresses.contains('${a.ip}:${a.port}'));
        final removed = beforeCount - peer.addresses.length;
        _log.info('DEVICE_REVOKED from ${contact.displayName}: '
            'removed $removed/${revokedAddresses.length} addresses (fallback)');
      } else {
        _log.debug('DEVICE_REVOKED from ${contact.displayName}: '
            'no PeerInfo in routing table');
      }
    } catch (e) {
      _log.error('DEVICE_REVOKED processing failed: $e');
    }
  }
  // ──────────────────────────── V3 Helpers ────────────────────────────

  /// Constant-time byte equality (for userId compare in sender-override path).
  static bool _constantTimeEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Short hex prefix for log lines (8 chars / 4 bytes).
  static String _hexShort(Uint8List bytes) {
    final n = bytes.length < 4 ? bytes.length : 4;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

/// §2.2.4: V3-direct adapter (Welle 2A). IdentityPublisher hands us a
/// `(MessageTypeV3, payload, peer)` triple; we forward straight to
/// `CleonaNode.sendInfraTo`, which wraps in InfrastructureFrameV3 with the
/// proper Outer Device-Sig + KEM-AEAD per §2.3.5. Fire-and-forget — the
/// publisher broadcasts to K closest replicators and tolerates per-peer
/// failure (replication factor covers it).
class _IdentityPublisherSender implements IdentityPublisherSender {
  final CleonaNode _node;
  _IdentityPublisherSender(this._node);

  @override
  Future<void> send(proto.MessageTypeV3 messageType, Uint8List payload,
      PeerInfo peer) async {
    await _node.sendInfraTo(
      messageType: messageType,
      innerPayload: payload,
      recipientDeviceId: Uint8List.fromList(peer.nodeId),
    );
  }
}

/// Stage-2 reassembly buffer for incoming MEDIA_CHUNK frames.
/// Holds chunks indexed by chunk_index until MEDIA_COMPLETE arrives,
/// at which point the receiver concatenates them, hash-checks against
/// the COMPLETE-payload, writes the file, and bumps the UiMessage's
/// mediaState to completed.
class _MediaChunkBuffer {
  final int totalChunks;
  final List<Uint8List?> chunks;
  final DateTime createdAt;
  _MediaChunkBuffer(this.totalChunks)
      : chunks = List<Uint8List?>.filled(totalChunks, null),
        createdAt = DateTime.now();

  bool get isComplete => chunks.every((c) => c != null);

  Uint8List assemble() {
    final total = chunks.fold<int>(0, (a, c) => a + (c?.length ?? 0));
    final out = Uint8List(total);
    var off = 0;
    for (final c in chunks) {
      if (c == null) continue;
      out.setRange(off, off + c.length, c);
      off += c.length;
    }
    return out;
  }
}

/// §5.8 One-Shot-Outbox entry.
///
/// Holds a canonical serialized [NetworkPacketV3] and the metadata required to
/// retry the single L3 placement attempt once the sender regains connectivity.
/// This is NOT a retry queue — the entry is flushed exactly once per
/// onNetworkChanged edge-trigger and then either removed (L3 placed) or kept
/// for the next edge (still 0 peers).
class _OutboxEntry {
  /// Wire message ID (hex string), correlates to UiMessage.id.
  final String messageIdHex;
  /// Recipient user ID (hex string) for erasure distribution routing.
  final String recipientUserIdHex;
  /// Ed25519 pubkey of the recipient (hex) — used for mailbox-id derivation.
  final String? recipientEd25519PkHex;
  /// Serialized NetworkPacketV3 bytes (base64-encoded for JSON storage).
  final String canonicalPacketB64;
  /// When the original send was attempted (for TTL / expired-status check).
  final int sentAtMs;

  _OutboxEntry({
    required this.messageIdHex,
    required this.recipientUserIdHex,
    this.recipientEd25519PkHex,
    required this.canonicalPacketB64,
    required this.sentAtMs,
  });

  Map<String, dynamic> toJson() => {
        'messageIdHex': messageIdHex,
        'recipientUserIdHex': recipientUserIdHex,
        if (recipientEd25519PkHex != null) 'recipientEd25519PkHex': recipientEd25519PkHex,
        'canonicalPacketB64': canonicalPacketB64,
        'sentAtMs': sentAtMs,
      };

  static _OutboxEntry fromJson(Map<String, dynamic> json) => _OutboxEntry(
        messageIdHex: json['messageIdHex'] as String,
        recipientUserIdHex: json['recipientUserIdHex'] as String,
        recipientEd25519PkHex: json['recipientEd25519PkHex'] as String?,
        canonicalPacketB64: json['canonicalPacketB64'] as String,
        sentAtMs: json['sentAtMs'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
}
