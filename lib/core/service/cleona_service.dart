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
import 'package:cleona/core/dht/mailbox_store.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/identity_resolution/identity_publisher.dart';
import 'package:cleona/core/identity_resolution/identity_resolver.dart' show ResolvedDevice;
import 'package:cleona/core/identity_resolution/device_kem_record.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/network/ack_tracker.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/lan_discovery.dart' show LocalDiscovery;
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/peer_message_store.dart';
import 'package:cleona/core/network/v3_frame_codec.dart';
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/erasure/reed_solomon.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/network/network_stats.dart';
import 'package:cleona/core/calls/call_manager.dart';
import 'package:cleona/core/calls/audio_engine.dart';
import 'package:cleona/core/calls/audio_permissions.dart';
import 'package:cleona/core/calls/foreground_service.dart';
import 'package:cleona/core/calls/group_call_manager.dart';
import 'package:cleona/core/calls/audio_mixer.dart';
import 'package:cleona/core/calls/group_call_session.dart';
import 'package:cleona/core/calls/group_video_receiver.dart';
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
import 'package:cleona/core/media/link_preview_fetcher.dart';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/sync/calendar_sync_service.dart';
import 'package:cleona/core/polls/poll_manager.dart';
import 'package:cleona/core/crypto/linkable_ring_signature.dart';
import 'package:cleona/core/services/contact_manager.dart' show Contact;
import 'package:cleona/core/identity/identity_dht_registry.dart';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/channels/contact_issue_reporter.dart';
import 'package:cleona/core/channels/crash_reporter.dart';
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

/// Central orchestrator: wires node, contacts, messaging, and manages state.
/// Now takes a shared CleonaNode + IdentityContext instead of creating its own node.
class CleonaService implements ICleonaService {
  final String profileDir;
  @override
  String displayName;
  @override
  int port;
  final String networkChannel;
  final CLogger _log;

  /// The identity this service operates on behalf of.
  @override
  final IdentityContext identity;

  /// The shared network node (transport, routing, DHT).
  final CleonaNode node;

  late MailboxStore mailboxStore;
  late CallManager callManager;
  // §2.2.4: per-identity Auth+Liveness Publisher. Eine pro CleonaService-Instanz
  // (Multi-Identity-Daemon hat N Services, sharing one CleonaNode).
  IdentityPublisher? _identityPublisher;
  /// Registered listener on the shared RoutingTable; wakes our publisher's
  /// parked cold-start retry as soon as a new peer joins.
  void Function(PeerInfo)? _publisherPeerAddedListener;
  @override
  final NotificationSoundService notificationSound = NotificationSoundService();
  AudioEngine? _audioEngine;
  late GroupCallManager groupCallManager;
  AudioMixer? _audioMixer;
  dynamic _groupVideoEngine; // VideoEngine (loaded by GUI, avoids dart:ui in daemon)
  GroupVideoReceiver? _groupVideoReceiver;

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

  /// Active moderation config (can be switched between production/test via IPC).
  /// Setting this restarts the moderation timer with the appropriate interval.
  ModerationConfig _moderationConfig = ModerationConfig.production();
  ModerationConfig get moderationConfig => _moderationConfig;
  set moderationConfig(ModerationConfig value) {
    _moderationConfig = value;
    _startModerationTimer(); // restart with new interval
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

  // Contact storage
  final Map<String, ContactInfo> _contacts = {};
  // Persistent deletion flag: prevents re-import of deleted contacts
  final Set<String> _deletedContacts = {};

  // Calendar (§23)
  @override
  late CalendarManager calendarManager;
  /// External calendar sync (§23.8 — CalDAV + Google). Daemon-only, not
  /// part of the ICleonaService interface: the GUI interacts via IPC commands.
  late CalendarSyncService calendarSyncService;

  /// Callback: calendar invite received from a contact.
  void Function(String senderNodeIdHex, String eventId, String title)? onCalendarInviteReceived;
  /// Callback: RSVP response received for a group event.
  void Function(String eventId, String responderNodeIdHex, RsvpStatus status)? onCalendarRsvpReceived;
  /// Callback: calendar event updated by creator.
  void Function(String eventId)? onCalendarEventUpdated;
  /// Callback: reminder is due.
  void Function(String eventId, String title, int minutesBefore)? onCalendarReminderDue;

  // Polls (§24)
  @override
  late PollManager pollManager;
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
  /// Closed key-image hex values keyed by pollId (§24.4). In-memory only —
  /// after a restart every stored vote is re-indexed from poll.votes.
  final Map<String, Set<String>> _anonymousKeyImages = {};
  Timer? _pollDeadlineTimer;

  /// §26: fires whenever the twin-device list changes (add/remove/rename).
  /// GUI listens via IPC to refresh the Device Management screen.
  void Function()? onDevicesUpdated;

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
  // CR retry timer
  Timer? _crRetryTimer;
  // Rate limiter: last CR retry time per contact (nodeIdHex -> timestamp)
  final Map<String, DateTime> _lastCrRetryPerContact = {};
  // Exponential backoff counter for CR retries to unreachable contacts.
  // Backoff: 10s, 20s, 40s, 80s, 160s, 320s, then capped at 600s (10min).
  // Keeps retrying forever so eventually-online contacts still get through,
  // but at low frequency after the initial burst (~10 attempts in 20min).
  final Map<String, int> _crRetryCountPerContact = {};
  // §8.1.1 rev3 step 1b: pending DEVICE_KEM_OFFER completers.
  // Key = hex(targetDeviceId), value = completer resolved by the
  // incoming DEVICE_KEM_OFFER handler. Timeout in sendContactRequest.
  final Map<String, Completer<({Uint8List dxk, Uint8List dmk})>>
      _pendingKemOfferCompleters = {};
  // Per-contact last end-to-end-confirmed ACK (any message type).
  // Proves reachability to the contact — stops CR-Response retry flooding
  // on CGNAT peers where DELIVERY_RECEIPTs arrive only via relay and thus
  // never flip dvRouting's direct-only ackConfirmed flag.
  final Map<String, DateTime> _contactLastAckedAt = {};
  // Contacts for which the sender-side stale warning has already been written
  // into the conversation. Prevents duplicate warnings; cleared on the next
  // ACK (contact is alive) or re-acceptance.
  final Set<String> _staleWarningWrittenFor = {};
  Timer? _keyRotationTimer;
  // §26.6.2 Paket C: drives _keyRotationRetry re-sends every 24h.
  Timer? _keyRotationRetryTimer;
  Timer? _expiryTimer;
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
  Timer? _channelIndexGossipTimer;
  Timer? _moderationTimer;
  // Moderation state
  final Map<String, ChannelReport> _channelReports = {};
  final Map<String, PostReport> _postReports = {};
  final Map<String, JuryRequest> _pendingJuryRequests = {};
  /// Active jury sessions we initiated (juryId -> jury state).
  final Map<String, _JurySession> _activeSessions = {};
  /// Reports filed per identity per day (rate-limiting).
  final Map<String, int> _dailyReportCounts = {};
  DateTime _lastReportCountReset = DateTime.now();
  /// CSAM reporter cooldowns: nodeIdHex -> last CSAM report time.
  final Map<String, DateTime> _csamCooldowns = {};
  /// CSAM reporter strikes: nodeIdHex -> strike count.
  final Map<String, int> _csamStrikes = {};

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
  void Function(UpdateManifest manifest, bool isCurrent)? onUpdateAvailable;

  /// The current app version string. Single source of truth, also consumed
  /// by `lib/main.dart` for the Sec H-5 hard-block startup check (T13).
  static const String kCurrentAppVersion = '3.1.82';

  /// Backwards-compatible instance accessor.
  String get currentAppVersion => kCurrentAppVersion;

  // Recovery state
  @override
  void Function(int phase, int contactsRestored, int messagesRestored)? onRestoreProgress;
  DateTime? _lastRestoreBroadcast;
  Timer? _restoreRetryTimer;
  Timer? _restorePollingTimer;
  int _restorePollCount = 0;

  // #U1 startup-poll state: Kademlia bootstrap takes ~15-20s after restart, so
  // peers responsible for our DHT-fragment storage and S&F-stored messages may
  // not yet be in the routing table when a single-shot poll fires at T+5/8s.
  // The startup polling timer fires every 3s for ~30s and polls only newly
  // observed peers, catching late arrivals without re-flooding known peers.
  Timer? _startupPollingTimer;
  int _startupPollCount = 0;
  final Set<String> _startupPolledPeers = {};

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

    // Init call manager
    callManager = CallManager(identity: identity, node: node, contacts: _contacts, profileDir: profileDir);
    callManager.sendViaUser = (recipientUserId, type, payload) =>
        sendToUser(recipientUserId: recipientUserId, messageType: type, payload: payload);
    callManager.onIncomingCall = (session) {
      onIncomingCall?.call(session.toCallInfo());
      onStateChanged?.call();
    };
    callManager.onCallAccepted = (session) {
      _startAudioEngine(session);
      onCallAccepted?.call(session.toCallInfo());
      onStateChanged?.call();
    };
    callManager.onCallRejected = (session, reason) {
      _stopAudioEngine();
      onCallRejected?.call(session.toCallInfo(), reason);
      onStateChanged?.call();
    };
    callManager.onCallEnded = (session) {
      _stopAudioEngine();
      onCallEnded?.call(session.toCallInfo());
      onStateChanged?.call();
    };

    // Plan §D2: hook DV-Routing route-down → drop cached route on the active
    // CallSession so the next audio frame re-resolves via routingTable.
    // peerHex may arrive as deviceNodeId OR userId (V3.1.65 multi-device);
    // we match against the session's stable peerNodeIdHex, plus the live
    // deviceNodeId of the cached PeerInfo if present.
    node.onRouteDownForCalls = (peerHex) {
      final session = callManager.currentCall;
      if (session == null) return;
      final cachedDevHex = session.cachedRoute?.nodeIdHex;
      if (session.peerNodeIdHex == peerHex || cachedDevHex == peerHex) {
        session.invalidateCachedRoute();
      }
    };

    // Init group call manager
    groupCallManager = GroupCallManager(
      identity: identity,
      node: node,
      contacts: _contacts,
      groups: _groups,
      profileDir: profileDir,
    );
    groupCallManager.sendViaUser = (recipientUserId, type, payload) =>
        sendToUser(recipientUserId: recipientUserId, messageType: type, payload: payload);
    groupCallManager.onIncomingGroupCall = (info) {
      onIncomingGroupCall?.call(info);
      onStateChanged?.call();
    };
    groupCallManager.onGroupCallStarted = (info) {
      _startAudioMixer(groupCallManager.currentGroupCall!);
      _startGroupVideo(groupCallManager.currentGroupCall!);
      onGroupCallStarted?.call(info);
      onStateChanged?.call();
    };
    groupCallManager.onGroupCallEnded = (info) {
      _stopAudioMixer();
      _stopGroupVideo();
      onGroupCallEnded?.call(info);
      onStateChanged?.call();
    };
    groupCallManager.onParticipantChanged = (hex, state) {
      if (state == ParticipantState.left || state == ParticipantState.crashed) {
        _audioMixer?.removePeer(hex);
        _groupVideoReceiver?.removePeer(hex);
      }
      onStateChanged?.call();
    };
    groupCallManager.onKeyRotated = (newKey, version) {
      _audioMixer?.updateCallKey(newKey, version);
      _groupVideoReceiver?.updateCallKey(newKey, version);
      // VideoEngine capture key update: stop and restart with new key
      // (capture isolate uses immutable key — simpler to restart)
      if (_groupVideoEngine != null) {
        try { (_groupVideoEngine as dynamic).stop(); } catch (_) {}
        _groupVideoEngine = null;
        _startGroupVideoCapture(groupCallManager.currentGroupCall!);
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

    // Load contacts
    _loadContacts();

    // Init local device (§26 Multi-Device)
    _initLocalDevice();

    // Load own profile picture
    _loadProfilePicture();

    // Load own profile description
    _loadProfileDescription();

    // Load groups
    _loadGroups();

    // Load channels
    _loadChannels();

    // Seed system channels (§9.5)
    _seedSystemChannels();

    // Load moderation state
    _loadModeration();

    // Load calendar (§23)
    calendarManager = CalendarManager(
      profileDir: profileDir,
      identityId: identity.userIdHex,
      fileEnc: _fileEnc,
    );
    calendarManager.load();

    // Load external calendar sync (§23.8 — CalDAV + Google)
    calendarSyncService = CalendarSyncService(
      profileDir: profileDir,
      identityId: identity.userIdHex,
      calendar: calendarManager,
      fileEnc: _fileEnc,
    );
    calendarSyncService.load();

    // Polls (§24)
    pollManager = PollManager(
      profileDir: profileDir,
      identityId: identity.userIdHex,
      fileEnc: _fileEnc,
    );
    pollManager.load();

    // Key rotation retry manager (§26.6.2 Paket C): persisted per-contact
    // retry state so offline contacts still receive KEY_ROTATION_BROADCAST
    // after S&F TTL expiry.
    _keyRotationRetry = KeyRotationRetryManager(
      profileDir: profileDir,
      identityId: identity.userIdHex,
      fileEnc: _fileEnc,
    );
    _keyRotationRetry.load();

    // Rebuild the key-image index from persisted anonymous votes so
    // double-vote detection survives restarts.
    for (final poll in pollManager.polls.values) {
      for (final v in poll.votes.values) {
        if (v.anonymous) {
          _anonymousKeyImages
              .putIfAbsent(poll.pollId, () => {})
              .add(v.voterIdHex);
        }
      }
    }
    _startPollDeadlineTimer();

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

    // Load conversations
    _loadConversations();
    // After load: surface the persisted unreadCount to the system badge so
    // the Launcher-Badge matches the on-disk truth right after daemon-start.
    _updateBadgeCount();

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

    // #U1 fix: aggressive startup polling for DHT-fragment + S&F retrieval.
    // Single-shot polls at T+5/8s missed peers that joined the routing table
    // after Kademlia bootstrap (~15-20s), leaving stored CRs and away-period
    // messages permanently unretrieved. The 30-second window with per-peer
    // dedup catches late arrivals without re-flooding peers that already
    // responded with 0 messages.
    _startupPollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _startupPollCount++;
      _pollNewPeersForStoredMessages();
      if (_startupPollCount >= 10) {
        timer.cancel();
        _startupPollingTimer = null;
        _log.info('Startup polling complete (${_startupPolledPeers.length} peers polled)');
      }
    });

    // §26: TWIN_ANNOUNCE at startup so existing twins learn about this device.
    // 6 seconds lets the first peers come up first. Fire-and-forget; a no-op
    // when we have no known twins yet (first twin learns us when its own
    // announce arrives here — our handler echoes _sendTwinAnnounce back).
    Timer(const Duration(seconds: 6), _sendTwinAnnounce);

    // Retry pending outgoing contact requests (every 10 seconds)
    _crRetryTimer = Timer.periodic(const Duration(seconds: 10), (_) => _retryPendingContactRequests());

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
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkMessageExpiry());

    // Channel index gossip: share index with peers every 5 minutes
    _channelIndexGossipTimer = Timer.periodic(const Duration(minutes: 5), (_) => _doChannelIndexGossip());
    // Prune stale index entries on startup
    _channelIndex.prune();

    // Moderation timer: periodic check of all time-based moderation limits
    _startModerationTimer();

    // System channel eviction (§9.5.5)
    _systemChannelEvictionTimer = Timer.periodic(
        const Duration(minutes: 30), (_) => _evictSystemChannels());

    // Stats wiring lives on CleonaNode now (single shared collector across
    // all identities). #U5: previous per-Service `??=` only let the first
    // service to start win the transport callbacks; all later services saw
    // 0 receive bytes.

    // RUDP Light: downgrade message status on ACK timeout.
    node.ackTracker.onAckTimeout = _handleAckTimeout;
    // Wire FRAGMENT_STORE_ACK observer for proactive-push reliability tracking
    // (Architecture §3.5).
    node.onFragmentStoreAck = onProactivePushAcked;

    // §5.1 Layer 3: offline cascade when all DV routes are exhausted.
    node.onMessageRetryExhausted = _handleRetryExhausted;

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
          return;
        }
      }
    };

    // Mutual Peer Selection for S&F (Architecture Section 3.3.7).
    node.getMutualPeerIds = _computeMutualPeerIds;

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
    );
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
  }

  /// FRAGMENT_STORE handler (Architecture §5.4 + §23.3 InfraFrame). Stores
  /// the fragment in the local mailbox; if storage succeeds, sends a
  /// FRAGMENT_STORE_ACK back to the sender's device. If the fragment
  /// targets our own mailbox, triggers reassembly; otherwise, if we know
  /// the mailbox owner, kicks off a proactive push (§3.5).
  void _handleFragmentStore(Uint8List payload, Uint8List senderDeviceId) {
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

  // Pending media: maps messageIdHex -> local file path (sender keeps file until accepted)
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


  /// Default edit window: 15 minutes.
  static const int _defaultEditWindowMs = 60 * 60 * 1000; // 1 hour

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
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageTypeV3.MTV3_REACTION,
          payload: basePayload,
          groupId: groupIdBytes,
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

    onStateChanged?.call();
    _saveConversations();
    _log.info('Reaction ${remove ? "removed" : "added"}: $emoji on ${messageId.substring(0, 8)}');
  }

  /// Broadcast IDENTITY_DELETED to all accepted contacts before deletion.
  /// V3: per-contact sendToUser fan-out; KEM/Sig handled inside sendToUser.
  Future<void> broadcastIdentityDeleted() async {
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
    return _bytesEqual(mailboxId, sodium.sha256(fallbackInput));
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

    // Request fragments from confirmed peers only (§4.4).
    final peers = node.routingTable.allPeers
        .where((p) => node.isPeerConfirmed(p.nodeIdHex))
        .toList();
    for (final peer in peers) {
      // Primary mailbox
      _requestFragments(peer, primaryMailboxId);
      // Fallback mailbox
      _requestFragments(peer, fallbackMailboxId);
    }

    _log.info('Mailbox poll sent to ${peers.length} peers');
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

  /// #U1 fix: poll only peers that joined the routing table since the last
  /// startup-poll iteration. Each new peer receives both a FRAGMENT_RETRIEVE
  /// (for DHT-erasure-coded mailbox fragments — primary + fallback mailbox IDs)
  /// and a PEER_RETRIEVE (for Store-and-Forward stored envelopes). Already-
  /// polled peers are skipped to avoid re-flooding known-empty mailboxes.
  void _pollNewPeersForStoredMessages() {
    final sodium = SodiumFFI();
    final primaryMailboxId = sodium.sha256(Uint8List.fromList(
      [...utf8.encode('mailbox'), ...identity.ed25519PublicKey],
    ));
    final fallbackMailboxId = sodium.sha256(Uint8List.fromList(
      [...utf8.encode('mailbox-nid'), ...identity.nodeId],
    ));
    final newPeers = node.routingTable.allPeers
        .where((p) => node.isPeerConfirmed(p.nodeIdHex) &&
            _startupPolledPeers.add(p.nodeIdHex))
        .toList();
    if (newPeers.isEmpty) return;
    for (final peer in newPeers) {
      _requestFragments(peer, primaryMailboxId);
      _requestFragments(peer, fallbackMailboxId);
      _requestStoredMessages(peer);
    }
    _log.info('Startup poll iter $_startupPollCount/10: '
        '${newPeers.length} new peers polled '
        '(total ${_startupPolledPeers.length})');
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

    // Sender-side link preview. We fetch up-front (HTTPS-only, SSRF-guarded
    // by LinkPreviewFetcher) and embed the result in TextMessageV3 so the
    // receiver can render the card WITHOUT making any network request —
    // this is the privacy-safe receiver-MUST-NOT-fetch invariant from the
    // architecture (Messaging feature-list in CLAUDE.md).
    proto.LinkPreview? wirePreview;
    if (_linkPreviewSettings.enabled && extractFirstUrl(text) != null) {
      try {
        final preview = await _linkPreviewFetcher.fetchPreview(text);
        if (preview != null) {
          msg.linkPreviewUrl = preview.url;
          msg.linkPreviewTitle = preview.title;
          msg.linkPreviewDescription = preview.description;
          msg.linkPreviewSiteName = preview.siteName;
          if (preview.thumbnail != null) {
            msg.linkPreviewThumbnailBase64 = base64Encode(preview.thumbnail!);
          }
          wirePreview = preview.toProto();
          onStateChanged?.call();
        }
      } catch (e) {
        _log.debug('Link preview fetch failed: $e');
      }
    }

    final tm = proto.TextMessageV3()
      ..text = text
      ..formatHint = 'plain';
    if (wirePreview != null) {
      tm.linkPreview = wirePreview;
    }
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
    final sent = await sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageTypeV3.MTV3_TEXT,
      payload: tm.writeToBuffer(),
      messageId: messageIdBytes,
    );
    node.statsCollector.addMessageSent();

    msg.status = sent ? MessageStatus.sent : MessageStatus.queued;
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

    return msg;
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
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final ok = await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageTypeV3.MTV3_EDIT,
          payload: basePayload,
          groupId: groupIdBytes,
          messageId: wireMessageId,
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
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final ok = await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageTypeV3.MTV3_DELETE,
          payload: basePayload,
          groupId: groupIdBytes,
          messageId: wireMessageId,
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
  /// Fire-and-forget: errors are logged at debug, callers don't await
  /// individual FRAGMENT_STORE ACKs (they will arrive asynchronously via
  /// the standard InfraFrame receive path).
  Future<void> _distributeErasureFragments({
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
        return;
      }

      final rs = ReedSolomon();
      final fragments = rs.encode(packetBytes);
      final peers = node.routingTable.findClosestPeers(mailboxId, count: 10);
      if (peers.isEmpty) {
        _log.debug('Erasure offline-delivery skipped: no DHT replicators known');
        return;
      }

      for (var i = 0; i < fragments.length; i++) {
        final fragStore = proto.FragmentStore()
          ..mailboxId = mailboxId
          ..messageId = messageId
          ..fragmentIndex = i
          ..totalFragments = fragments.length
          ..requiredFragments = ReedSolomon.defaultK
          ..fragmentData = fragments[i]
          ..originalSize = packetBytes.length;
        final targetPeer = peers[i % peers.length];
        node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_FRAGMENT_STORE,
          innerPayload: Uint8List.fromList(fragStore.writeToBuffer()),
          recipientDeviceId: Uint8List.fromList(targetPeer.nodeId),
        );
      }
    } catch (e) {
      _log.debug('Erasure offline-delivery failed: $e');
    }
  }

  // ── §5.1 Layer 3: Offline Cascade ──────────────────────────────────

  void _handleRetryExhausted(
      String messageIdHex, Uint8List serializedPacket, Uint8List recipientUserId) {
    _log.info('Offline cascade for message $messageIdHex '
        '→ ${_hexShort(recipientUserId)}');
    final recipientHex = bytesToHex(recipientUserId);
    final contact = _contacts[recipientHex];

    // §5.4: Erasure-coded backup on DHT
    final fragmentBundleId =
        SodiumFFI().sha256(serializedPacket).sublist(0, 16);
    _distributeErasureFragments(
      packetBytes: serializedPacket,
      messageId: fragmentBundleId,
      recipientUserEd25519Pk: contact?.ed25519Pk,
      recipientUserNodeId: recipientUserId,
    );

    // §5.5: S&F copy on mutual peers
    _storeSafOnMutualPeers(
      recipientUserId: recipientUserId,
      wrappedEnvelope: serializedPacket,
      storeId: SodiumFFI().randomBytes(16),
    );
  }

  /// §5.5: Store a complete message copy on up to 3 mutual peers.
  void _storeSafOnMutualPeers({
    required Uint8List recipientUserId,
    required Uint8List wrappedEnvelope,
    required Uint8List storeId,
  }) {
    final mutuals = _findMutualPeerDeviceIds(recipientUserId, limit: 3);
    if (mutuals.isEmpty) {
      _log.debug('S&F: no mutual peers for ${_hexShort(recipientUserId)}');
      return;
    }
    final peerStore = proto.PeerStore()
      ..recipientNodeId = recipientUserId
      ..wrappedEnvelope = wrappedEnvelope
      ..storeId = storeId
      ..ttlMs = Int64(PeerMessageStore.defaultTtlMs);
    final payload = Uint8List.fromList(peerStore.writeToBuffer());
    for (final mutualDeviceId in mutuals) {
      node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_PEER_STORE,
        innerPayload: payload,
        recipientDeviceId: mutualDeviceId,
      );
    }
    _log.info('S&F: stored on ${mutuals.length} mutual peers '
        'for ${_hexShort(recipientUserId)}');
  }

  /// §5.5: Find contacts that are likely mutual peers (both sender and
  /// recipient know them). Heuristic: accepted contacts with a known
  /// deviceNodeId in the routing table (i.e. online and reachable).
  /// Excludes the recipient itself.
  List<Uint8List> _findMutualPeerDeviceIds(Uint8List recipientUserId, {int limit = 3}) {
    final recipientHex = bytesToHex(recipientUserId);
    final candidates = <(Uint8List, int)>[];
    for (final entry in _contacts.entries) {
      if (entry.key == recipientHex) continue;
      final c = entry.value;
      if (c.status != 'accepted') continue;
      if (c.deviceNodeIds.isEmpty) continue;
      for (final devHex in c.deviceNodeIds) {
        final devBytes = hexToBytes(devHex);
        final peer = node.routingTable.getPeer(devBytes);
        if (peer == null) continue;
        final routes = node.dvRouting.routesTo(devHex);
        final aliveCount = routes.where((r) => r.isAlive).length;
        if (aliveCount > 0) {
          candidates.add((devBytes, aliveCount));
          break;
        }
      }
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
    _log.info('Manual peer entry: LAN-Discovery probe sent to $ip '
        '(discoveryPort=${LocalDiscovery.discoveryPort}'
        '${port != LocalDiscovery.discoveryPort ? ", fallback=$port" : ""})');
    return true;
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
      } else if (seedDeviceIdHex != null && seedDeviceIdHex.isNotEmpty) {
        // §8.1.1 rev3 step 1b: DHT miss — fallback to DEVICE_KEM_REQUEST.
        // Send a plaintext BOOT-frame request to the target device (no KEM
        // needed). The target responds with a signed DEVICE_KEM_OFFER
        // containing its Device-KEM-PK pair. We verify the OFFER signature
        // against the ep trust-anchor from the ContactSeed.
        final targetDevId = hexToBytes(seedDeviceIdHex);
        _log.info('CONTACT_REQUEST First-CR: DHT miss — '
            'sending DEVICE_KEM_REQUEST to '
            '${seedDeviceIdHex.substring(0, 8)}');
        final nonce = SodiumFFI().randomBytes(16);
        final request = proto.DeviceKemRequestV3()
          ..targetUserId = recipientUserId
          ..targetDeviceId = targetDevId
          ..nonce = nonce
          ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch);
        final requestBytes =
            Uint8List.fromList(request.writeToBuffer());

        final completer = Completer<({Uint8List dxk, Uint8List dmk})>();
        final targetDevHex = seedDeviceIdHex;
        _pendingKemOfferCompleters[targetDevHex] = completer;

        // Send to target directly (BOOT-path, no KEM) + via seed peers.
        unawaited(node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_DEVICE_KEM_REQUEST,
          innerPayload: requestBytes,
          recipientDeviceId: targetDevId,
        ));

        try {
          final offer = await completer.future
              .timeout(const Duration(seconds: 8));
          dxk = offer.dxk;
          dmk = offer.dmk;
          recipientDeviceId = targetDevId;
          // Prime the DKR cache so retries skip DHT+handshake.
          final primed = DeviceKemRecord(
            userId: recipientUserId,
            deviceId: targetDevId,
            deviceX25519Pk: dxk,
            deviceMlKemPk: dmk,
            ttlSeconds: 24 * 3600,
            sequenceNumber: 0,
            publishedAtMs: DateTime.now().millisecondsSinceEpoch,
            userEd25519Pk: Uint8List(0),
            ed25519Sig: Uint8List(0),
          );
          node.identityDhtHandler.handleKemPublish(primed);
          _log.info('CONTACT_REQUEST First-CR: DEVICE_KEM_OFFER received '
              'for ${seedDeviceIdHex.substring(0, 8)} — proceeding');
        } on TimeoutException {
          _pendingKemOfferCompleters.remove(targetDevHex);
          _log.warn('CONTACT_REQUEST: Deferred Key Exchange timeout — '
              'no DEVICE_KEM_OFFER from '
              '${seedDeviceIdHex.substring(0, 8)} within 8s. '
              'CR queued for retry.');
          return false;
        } finally {
          _pendingKemOfferCompleters.remove(targetDevHex);
        }
      } else {
        _log.warn('CONTACT_REQUEST: Deferred Key Exchange failed — '
            'no DeviceKemRecord in DHT for '
            '${recipientUserIdHex.substring(0, 8)} '
            'and no seedDeviceIdHex for fallback. '
            'CR queued for retry (exponential backoff).');
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
      senderUserEd25519Sk: identity.ed25519SecretKey,
      senderUserMlDsaSk: identity.mlDsaSecretKey,
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
    // First-contact CRs are persisted as pending_outgoing and retried by
    // _retryPendingContactRequests regardless of the initial send result.
    // Return true so the UI shows "sent" rather than "failed" — the retry
    // timer handles delivery even when the routing table isn't warm yet.
    return true;
  }

  /// Accept a pending (or re-) contact request.
  @override
  Future<bool> acceptContactRequest(String nodeIdHex) async {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return false;
    // Allow 'pending' (normal accept), 'accepted' (re-contact response),
    // and 'pending_outgoing' (bidirectional CR auto-accept).
    if (contact.status != 'pending' && contact.status != 'accepted' && contact.status != 'pending_outgoing') return false;

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

  // ── Conversation Management ────────────────────────────────────────

  void _addMessageToConversation(String conversationId, UiMessage msg, {bool isGroup = false, bool isChannel = false}) {
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
        return;
      }
    }

    conv.messages.add(msg);
    conv.lastActivity = msg.timestamp;
    if (!msg.isOutgoing) {
      conv.unreadCount++;
      // Bug #U3+#U15: Launcher-Badge muss bei JEDEM eingehenden Increment
      // aktualisiert werden — nicht nur bei Text/Media. Vorher fehlte es
      // auf Channel-Posts und Config-Proposals, was zu Badge-Drift führte.
      // Zentralisiert, damit neue Handler nichts vergessen können.
      _updateBadgeCount();
    }

    onNewMessage?.call(conversationId, msg);
    onStateChanged?.call();
    _saveConversations();
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
  Future<UiMessage?> sendGroupTextMessage(String groupIdHex, String text) async {
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
    final basePayload = tm.writeToBuffer();
    final groupIdBytes = hexToBytes(groupIdHex);
    bool anySent = false;

    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      final ok = await sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_TEXT,
        payload: basePayload,
        groupId: groupIdBytes,
      );
      if (ok) anySent = true;
    }

    if (!anySent) return null;
    node.statsCollector.addMessageSent();

    // Optimistic UI message — V3 generates per-device messageIds inside
    // sendToUser; for the local single UI bubble we use a fresh random id
    // (DELIVERY_RECEIPT keys on per-user msgId so the local bubble cannot
    // be matched 1:1 — that's the C4-Groups follow-up).
    final localId = bytesToHex(SodiumFFI().randomBytes(16));
    final msg = UiMessage(
      id: localId,
      conversationId: groupIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: UiMessageType.text,
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

    _addMessageToConversation(groupIdHex, msg, isGroup: true);
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

  /// Broadcast updated group member list to all members via GROUP_INVITE.
  Future<void> _broadcastGroupUpdate(GroupInfo group) async {
    final groupId = hexToBytes(group.groupIdHex);
    final invite = proto.GroupInviteV3()
      ..groupId = groupId
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

    final inviteBytes = Uint8List.fromList(invite.writeToBuffer());
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
      }
    }
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
      _broadcastChannelUpdate(channel);
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

    // Broadcast updated channel (without us) to remaining members
    if (channel.members.isNotEmpty) {
      _broadcastChannelUpdate(channel);
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
    _saveChannels();

    // Broadcast updated member list to all members
    _broadcastChannelUpdate(channel);

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
    _saveChannels();

    // Broadcast updated member list
    _broadcastChannelUpdate(channel);

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

  /// Broadcast updated channel member list to all members via CHANNEL_INVITE.
  void _broadcastChannelUpdate(ChannelInfo channel) {
    final channelId = hexToBytes(channel.channelIdHex);
    final invite = proto.ChannelInvite()
      ..channelId = channelId
      ..channelName = channel.name
      ..inviterId = identity.nodeId
      ..isPublic = channel.isPublic
      ..isAdult = channel.isAdult
      ..language = channel.language;
    if (channel.description != null) invite.channelDescription = channel.description!;
    for (final m in channel.members.values) {
      invite.members.add(proto.GroupMemberV3() // reuse GroupMemberV3 proto
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role
        ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
        ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
        ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0));
    }

    final inviteBytes = Uint8List.fromList(invite.writeToBuffer());
    for (final m in channel.members.values) {
      if (m.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(m.nodeIdHex,
          memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;
      sendToUser(
        recipientUserId: hexToBytes(m.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_INVITE,
        payload: inviteBytes,
        groupId: channelId,
      );
    }
    _log.info('Broadcast channel update for "${channel.name}" to ${channel.members.length - 1} members');
  }

  /// Check if caller has permission for channel action.
  // ── Public Channel Operations ────────────────────────────────────

  @override
  Future<List<ChannelIndexEntry>> searchPublicChannels({
    String? query,
    String? language,
    bool? includeAdult,
  }) async {
    return _channelIndex.search(
      query: query,
      language: language,
      includeAdult: includeAdult ?? false,
    );
  }

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

  // joinPublicChannel is implemented in the Channel Join Request section below

  // ── Moderation: Reports ────────────────────────────────────────

  void _resetDailyReportCountsIfNeeded() {
    final now = DateTime.now();
    if (now.difference(_lastReportCountReset).inHours >= 24) {
      _dailyReportCounts.clear();
      _lastReportCountReset = now;
    }
  }

  /// Check if the current identity meets reporter qualification requirements.
  /// Returns null if qualified, or an error message if not.
  String? _checkReporterQualification(ReportCategory category) {
    final config = moderationConfig;

    // Check identity age
    final identityAge = DateTime.now().difference(identity.createdAt);
    if (category == ReportCategory.illegalCSAM) {
      if (identityAge < config.identityMinAgeCSAM) {
        return 'Identity too young for CSAM reports (need ${config.identityMinAgeCSAM.inDays} days)';
      }
      // CSAM requires isAdult
      if (config.csamRequiresAdult && !identity.isAdult) {
        return 'CSAM reports require adult verification';
      }
      // CSAM: min bidirectional partners
      final bidirectional = _contacts.values.where((c) => c.status == 'accepted').length;
      if (bidirectional < config.csamMinBidirectionalPartners) {
        return 'Not enough contacts for CSAM reports (need ${config.csamMinBidirectionalPartners})';
      }
      // CSAM: min long-term contacts
      final longterm = _contacts.values.where((c) {
        if (c.status != 'accepted' || c.acceptedAt == null) return false;
        return DateTime.now().difference(c.acceptedAt!) >= config.csamLongtermContactAge;
      }).length;
      if (longterm < config.csamMinLongtermContacts) {
        return 'Not enough long-term contacts for CSAM reports (need ${config.csamMinLongtermContacts})';
      }
      // CSAM cooldown check
      final lastCsam = _csamCooldowns[identity.userIdHex];
      if (lastCsam != null && DateTime.now().difference(lastCsam) < config.csamReporterCooldown) {
        return 'CSAM reporter cooldown active';
      }
      // CSAM strike check
      final strikes = _csamStrikes[identity.userIdHex] ?? 0;
      if (strikes >= config.csamMaxStrikes) {
        return 'CSAM reporting permanently banned (${config.csamMaxStrikes} strikes)';
      }
    } else {
      if (identityAge < config.identityMinAge) {
        return 'Identity too young for reports (need ${config.identityMinAge.inDays} days)';
      }
    }
    return null;
  }

  @override
  Future<bool> reportChannel(String channelIdHex, int category, List<String> evidencePostIds, {String? description}) async {
    _resetDailyReportCountsIfNeeded();

    // Rate limit
    final dailyCount = _dailyReportCounts[identity.userIdHex] ?? 0;
    if (dailyCount >= 5) {
      _log.warn('Daily report limit reached');
      return false;
    }

    // Reporter qualification
    final cat = ReportCategory.values[category];
    final qualError = _checkReporterQualification(cat);
    if (qualError != null) {
      _log.warn('Reporter not qualified: $qualError');
      return false;
    }

    // Validate evidence (3-10 posts for channel reports)
    if (evidencePostIds.isEmpty || evidencePostIds.length > 10) {
      _log.warn('Channel report needs 1-10 evidence posts');
      return false;
    }

    final reportId = bytesToHex(SodiumFFI().randomBytes(16));

    final report = ChannelReport(
      reportId: reportId,
      channelIdHex: channelIdHex,
      reporterNodeIdHex: identity.userIdHex,
      category: cat,
      evidencePostIds: evidencePostIds,
      description: description,
    );

    _channelReports[reportId] = report;
    _dailyReportCounts[identity.userIdHex] = dailyCount + 1;
    if (cat == ReportCategory.illegalCSAM) {
      _csamCooldowns[identity.userIdHex] = DateTime.now();
    }
    _saveModeration();

    _log.info('Channel report $reportId filed for $channelIdHex (category: ${cat.name})');

    // Check if jury threshold reached
    _checkJuryThreshold(channelIdHex);

    return true;
  }

  @override
  Future<bool> reportPost(String channelIdHex, String postId, int category, {String? description}) async {
    _resetDailyReportCountsIfNeeded();

    final dailyCount = _dailyReportCounts[identity.userIdHex] ?? 0;
    if (dailyCount >= 5) {
      _log.warn('Daily report limit reached');
      return false;
    }

    // Reporter qualification
    final cat = ReportCategory.values[category];
    final qualError = _checkReporterQualification(cat);
    if (qualError != null) {
      _log.warn('Reporter not qualified: $qualError');
      return false;
    }

    final reportId = bytesToHex(SodiumFFI().randomBytes(16));

    final report = PostReport(
      reportId: reportId,
      channelIdHex: channelIdHex,
      postId: postId,
      reporterNodeIdHex: identity.userIdHex,
      category: cat,
      description: description,
    );

    _postReports[reportId] = report;
    _dailyReportCounts[identity.userIdHex] = dailyCount + 1;
    if (cat == ReportCategory.illegalCSAM) {
      _csamCooldowns[identity.userIdHex] = DateTime.now();
    }
    _saveModeration();

    _log.info('Post report $reportId filed for $postId in $channelIdHex (category: ${cat.name})');
    return true;
  }

  // submitJuryVote is implemented in the Jury section below (with network send)

  void _saveModeration() {
    try {
      final file = File('$profileDir/moderation.json');
      file.writeAsStringSync(jsonEncode({
        'channelReports': _channelReports.map((k, v) => MapEntry(k, v.toJson())),
        'postReports': _postReports.map((k, v) => MapEntry(k, v.toJson())),
        'juryRequests': _pendingJuryRequests.map((k, v) => MapEntry(k, v.toJson())),
        'csamCooldowns': _csamCooldowns.map((k, v) => MapEntry(k, v.millisecondsSinceEpoch)),
        'csamStrikes': _csamStrikes,
      }));
    } catch (e) {
      _log.warn('Failed to save moderation state: $e');
    }
  }

  void _loadModeration() {
    try {
      final file = File('$profileDir/moderation.json');
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      final reports = json['channelReports'] as Map<String, dynamic>? ?? {};
      for (final e in reports.entries) {
        _channelReports[e.key] = ChannelReport.fromJson(e.value as Map<String, dynamic>);
      }

      final postReports = json['postReports'] as Map<String, dynamic>? ?? {};
      for (final e in postReports.entries) {
        _postReports[e.key] = PostReport.fromJson(e.value as Map<String, dynamic>);
      }

      final jury = json['juryRequests'] as Map<String, dynamic>? ?? {};
      for (final e in jury.entries) {
        _pendingJuryRequests[e.key] = JuryRequest.fromJson(e.value as Map<String, dynamic>);
      }

      final cooldowns = json['csamCooldowns'] as Map<String, dynamic>? ?? {};
      for (final e in cooldowns.entries) {
        _csamCooldowns[e.key] = DateTime.fromMillisecondsSinceEpoch(e.value as int);
      }
      final strikes = json['csamStrikes'] as Map<String, dynamic>? ?? {};
      for (final e in strikes.entries) {
        _csamStrikes[e.key] = e.value as int;
      }
    } catch (e) {
      _log.warn('Failed to load moderation state: $e');
    }
  }

  @override
  List<JuryRequest> get pendingJuryRequests => _pendingJuryRequests.values.toList();

  @override
  Map<String, dynamic> getChannelModerationInfo(String channelIdHex) {
    final channel = _channels[channelIdHex];
    final reports = _channelReports.values
        .where((r) => r.channelIdHex == channelIdHex)
        .map((r) => <String, dynamic>{
          'reportId': r.reportId,
          'channelId': r.channelIdHex,
          'category': _categoryToString(r.category),
          'reporterCount': 1,
          'status': r.state.name,
          'juryResult': null,
        }).toList();

    return {
      'channelId': channelIdHex,
      'isPublic': channel?.isPublic ?? false,
      'isAdultContent': channel?.isAdult ?? false,
      'badBadgeLevel': _badgeLevelToString(channel?.badBadgeLevel ?? 0),
      if (channel?.badBadgeSince != null) 'badBadgeSince': channel!.badBadgeSince!.millisecondsSinceEpoch,
      if (channel?.correctionSubmitted == true) 'correctionSubmitted': channel!.correctionSubmitted,
      'pendingReports': reports,
      'isTempHidden': channel?.isCsamHidden ?? false,
      if (channel?.csamHiddenSince != null) 'tempHiddenSince': channel!.csamHiddenSince!.millisecondsSinceEpoch,
      'tombstoned': channel?.tombstoned ?? false,
    };
  }

  String _categoryToString(ReportCategory cat) {
    switch (cat) {
      case ReportCategory.notSafeForWork: return 'not_safe_for_work';
      case ReportCategory.falseContent: return 'false_content';
      case ReportCategory.illegalDrugs: return 'illegal_drugs';
      case ReportCategory.illegalWeapons: return 'illegal_weapons';
      case ReportCategory.illegalCSAM: return 'illegal_csam';
      case ReportCategory.illegalOther: return 'illegal_other';
    }
  }

  String _badgeLevelToString(int level) {
    switch (level) {
      case 1: return 'questionable';
      case 2: return 'repeatedly_misleading';
      case 3: return 'permanent';
      default: return 'none';
    }
  }

  @override
  Future<bool> dismissPostReport(String channelIdHex, String reportId) async {
    final report = _postReports[reportId];
    if (report == null || report.channelIdHex != channelIdHex) return false;

    final channel = _channels[channelIdHex];
    if (channel == null || !_hasChannelPermission(channel, 'config')) return false;

    _postReports.remove(reportId);
    _saveModeration();
    _log.info('Post report $reportId dismissed');
    return true;
  }

  @override
  Future<bool> submitBadgeCorrection(String channelIdHex, {String? newName, String? newDescription}) async {
    final channel = _channels[channelIdHex];
    if (channel == null) return false;
    if (channel.ownerNodeIdHex != identity.userIdHex) return false;
    if (channel.badBadgeLevel <= 0 || channel.badBadgeLevel >= 3) return false; // no correction for permanent

    if (newName != null && newName.isNotEmpty) channel.name = newName;
    if (newDescription != null) channel.description = newDescription;
    channel.correctionSubmitted = true;
    _saveChannels();

    // Update index
    if (channel.isPublic) {
      _channelIndex.upsert(ChannelIndexEntry(
        channelIdHex: channelIdHex,
        name: channel.name,
        language: channel.language,
        isAdult: channel.isAdult,
        description: channel.description,
        subscriberCount: channel.members.length,
        badBadgeLevel: channel.badBadgeLevel,
        badBadgeSince: channel.badBadgeSince,
        correctionSubmitted: true,
        ownerNodeIdHex: channel.ownerNodeIdHex,
        createdAt: channel.createdAt,
      ));
      _channelIndex.save();
    }

    _log.info('Badge correction submitted for channel "${channel.name}"');
    return true;
  }

  @override
  Future<bool> contestCsamHide(String channelIdHex) async {
    final channel = _channels[channelIdHex];
    if (channel == null) return false;
    if (channel.ownerNodeIdHex != identity.userIdHex) return false;
    if (!channel.isCsamHidden) return false;

    // Create a plausibility jury (jurors see only metadata, not content)
    final report = _channelReports.values
        .where((r) => r.channelIdHex == channelIdHex && r.category == ReportCategory.illegalCSAM)
        .firstOrNull;
    if (report == null) return false;

    final juryId = bytesToHex(SodiumFFI().randomBytes(16));
    final session = _createJurySession(
      juryId: juryId,
      reportId: report.reportId,
      channelIdHex: channelIdHex,
      category: ReportCategory.illegalCSAM,
      isPlausibilityJury: true,
    );
    if (session == null) {
      _log.warn('Cannot form plausibility jury — not enough eligible jurors');
      return false;
    }

    _log.info('CSAM plausibility jury $juryId formed for channel "${channel.name}" — ${session.jurorNodeIds.length} jurors');
    return true;
  }

  // ── Channel Index Gossip ──────────────────────────────────────

  /// Send channel index to up to 3 random connected peers.
  void _doChannelIndexGossip() {
    final entries = _channelIndex.allEntries;
    if (entries.isEmpty) return;

    // Pick up to 3 random peers from routing table
    final allPeers = node.routingTable.allPeers;
    if (allPeers.isEmpty) return;

    final shuffled = List<PeerInfo>.from(allPeers)..shuffle();
    final targets = shuffled.take(3);

    final exchangeMsg = proto.ChannelIndexExchange();
    for (final entry in entries) {
      exchangeMsg.entries.add(proto.ChannelIndexEntryProto()
        ..channelId = hexToBytes(entry.channelIdHex)
        ..name = entry.name
        ..language = entry.language
        ..isAdult = entry.isAdult
        ..description = entry.description ?? ''
        ..subscriberCount = entry.subscriberCount
        ..badBadgeLevel = entry.badBadgeLevel
        ..correctionSubmitted = entry.correctionSubmitted
        ..ownerNodeId = hexToBytes(entry.ownerNodeIdHex)
        ..createdAtMs = Int64(entry.createdAt.millisecondsSinceEpoch));
      if (entry.badBadgeSince != null) {
        exchangeMsg.entries.last.badBadgeSinceMs = Int64(entry.badBadgeSince!.millisecondsSinceEpoch);
      }
    }

    // V3 channel-index gossip rides InfrastructureFrame: recipients are
    // arbitrary routing-table peers (NOT necessarily contacts), and there
    // is no inner User-Sig requirement — receivers treat the entries as
    // gossip and trust nothing. Device-KEM-Decap at the recipient gates
    // delivery to addressed devices; HMAC + Outer-Device-Sig per §3.5
    // protect the wire. Architecture §10.2 + §2.3.5.
    final payload = Uint8List.fromList(exchangeMsg.writeToBuffer());
    for (final peer in targets) {
      unawaited(node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_INDEX_EXCHANGE,
        innerPayload: payload,
        recipientDeviceId: peer.nodeId,
      ));
    }
  }

  /// Handle incoming channel index exchange from a peer.
  ///
  /// V3-direct: [payload] is the raw `ChannelIndexExchange` proto bytes
  /// from the InfrastructureFrame body (gossip-style, untrusted by design
  /// — handler only merges entries into `_channelIndex`). No sender
  /// argument needed — the entry payload is self-describing per channel.
  void _handleChannelIndexExchange(Uint8List payload) {
    try {
      final exchange = proto.ChannelIndexExchange.fromBuffer(payload);
      var added = 0;
      for (final e in exchange.entries) {
        final entry = ChannelIndexEntry(
          channelIdHex: bytesToHex(Uint8List.fromList(e.channelId)),
          name: e.name,
          language: e.language,
          isAdult: e.isAdult,
          description: e.description.isEmpty ? null : e.description,
          subscriberCount: e.subscriberCount,
          badBadgeLevel: e.badBadgeLevel,
          badBadgeSince: e.badBadgeSinceMs.toInt() > 0
              ? DateTime.fromMillisecondsSinceEpoch(e.badBadgeSinceMs.toInt())
              : null,
          correctionSubmitted: e.correctionSubmitted,
          ownerNodeIdHex: bytesToHex(Uint8List.fromList(e.ownerNodeId)),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
              e.createdAtMs.toInt() > 0 ? e.createdAtMs.toInt() : 0),
        );
        final existing = _channelIndex.get(entry.channelIdHex);
        if (existing == null || existing.subscriberCount < entry.subscriberCount ||
            existing.badBadgeLevel != entry.badBadgeLevel) {
          _channelIndex.upsert(entry);
          added++;
        }
      }
      if (added > 0) {
        _channelIndex.save();
        _log.info('Channel index gossip: merged $added entries from peer');
      }
    } catch (e) {
      _log.debug('Channel index exchange error: $e');
    }
  }

  // ── Channel Join Request (Owner-Seite) ────────────────────────

  /// Handle incoming join request for a public channel we own.
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// `ChannelJoinRequest` proto bytes (V3 inner User-Sig + outer
  /// Device-Sig + KEM-decap chain verified upstream). [senderUserId] is
  /// the requesting peer's user-id (`frame.senderUserId`).
  void _handleChannelJoinRequest(Uint8List payload, Uint8List senderUserId) {
    try {
      final joinReq = proto.ChannelJoinRequest.fromBuffer(payload);
      final channelIdHex = bytesToHex(Uint8List.fromList(joinReq.channelId));
      final channel = _channels[channelIdHex];
      if (channel == null || !channel.isPublic) {
        _log.debug('Join request for unknown/private channel $channelIdHex');
        return;
      }

      // Only owner processes join requests
      if (channel.ownerNodeIdHex != identity.userIdHex) return;

      final requesterNodeIdHex = bytesToHex(senderUserId);

      // Already a member?
      if (channel.members.containsKey(requesterNodeIdHex)) {
        _log.debug('$requesterNodeIdHex already member of channel $channelIdHex');
        return;
      }

      // Add as subscriber
      channel.members[requesterNodeIdHex] = ChannelMemberInfo(
        nodeIdHex: requesterNodeIdHex,
        displayName: joinReq.displayName,
        role: 'subscriber',
        ed25519Pk: Uint8List.fromList(joinReq.ed25519Pk),
        x25519Pk: Uint8List.fromList(joinReq.x25519Pk),
        mlKemPk: Uint8List.fromList(joinReq.mlKemPk),
      );
      _saveChannels();

      // Send CHANNEL_INVITE back with full member list
      _sendChannelInviteToMember(channel, requesterNodeIdHex);

      // Update index subscriber count
      if (channel.isPublic) {
        publishChannelToIndex(channelIdHex);
      }

      _log.info('Auto-accepted join request from ${joinReq.displayName} for channel "${channel.name}"');
      onStateChanged?.call();
    } catch (e) {
      _log.debug('Channel join request error: $e');
    }
  }

  /// Send a CHANNEL_INVITE to a specific member (used for join request responses).
  Future<void> _sendChannelInviteToMember(ChannelInfo channel, String memberNodeIdHex) async {
    final memberInfo = channel.members[memberNodeIdHex];
    if (memberInfo == null) return;

    // Build invite protobuf
    final invite = proto.ChannelInvite()
      ..channelId = hexToBytes(channel.channelIdHex)
      ..channelName = channel.name
      ..role = memberInfo.role
      ..isPublic = channel.isPublic
      ..isAdult = channel.isAdult
      ..language = channel.language;
    if (channel.description != null) invite.channelDescription = channel.description!;

    // Include full member list
    for (final m in channel.members.values) {
      final gm = proto.GroupMemberV3()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role;
      if (m.ed25519Pk != null) gm.ed25519PublicKey = m.ed25519Pk!;
      if (m.x25519Pk != null) gm.x25519PublicKey = m.x25519Pk!;
      if (m.mlKemPk != null) gm.mlKemPublicKey = m.mlKemPk!;
      invite.members.add(gm);
    }

    // V3: sendToUser handles KEM/Sig + per-device fan-out.
    final (x25519Pk, mlKemPk) = _resolveMemberKeys(memberNodeIdHex,
        memberX25519Pk: memberInfo.x25519Pk, memberMlKemPk: memberInfo.mlKemPk);
    if (x25519Pk == null || mlKemPk == null) return;
    await sendToUser(
      recipientUserId: hexToBytes(memberNodeIdHex),
      messageType: proto.MessageTypeV3.MTV3_CHANNEL_INVITE,
      payload: Uint8List.fromList(invite.writeToBuffer()),
      groupId: hexToBytes(channel.channelIdHex),
    );
  }

  @override
  Future<bool> joinPublicChannel(String channelIdHex) async {
    final entry = _channelIndex.get(channelIdHex);
    if (entry == null) return false;

    // Create local channel + conversation
    if (!_channels.containsKey(channelIdHex)) {
      final channel = ChannelInfo(
        channelIdHex: channelIdHex,
        name: entry.name,
        description: entry.description,
        ownerNodeIdHex: entry.ownerNodeIdHex,
        isPublic: true,
        isAdult: entry.isAdult,
        language: entry.language,
      );
      channel.members[identity.userIdHex] = ChannelMemberInfo(
        nodeIdHex: identity.userIdHex,
        displayName: displayName,
        role: 'subscriber',
        ed25519Pk: identity.ed25519PublicKey,
        x25519Pk: identity.x25519PublicKey,
        mlKemPk: identity.mlKemPublicKey,
      );
      _channels[channelIdHex] = channel;
      _saveChannels();

      conversations[channelIdHex] = Conversation(
        id: channelIdHex,
        displayName: entry.name,
        isChannel: true,
      );
      _saveConversations();
      onStateChanged?.call();
    }

    // Send join request to channel owner via V3 sendToUser. Owner is
    // (per §10.2) a contact for any public channel we discovered, so
    // sendToUser handles per-device fan-out + KEM/Sig.
    final ownerContact = _contacts[entry.ownerNodeIdHex];
    if (ownerContact?.x25519Pk != null && ownerContact?.mlKemPk != null) {
      final joinReq = proto.ChannelJoinRequest()
        ..channelId = hexToBytes(entry.channelIdHex)
        ..displayName = displayName
        ..ed25519Pk = identity.ed25519PublicKey
        ..x25519Pk = identity.x25519PublicKey
        ..mlKemPk = identity.mlKemPublicKey;
      unawaited(sendToUser(
        recipientUserId: hexToBytes(entry.ownerNodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_JOIN_REQUEST,
        payload: Uint8List.fromList(joinReq.writeToBuffer()),
      ));
      _log.info('CHANNEL_JOIN_REQUEST sent for "${entry.name}" to owner '
          '${entry.ownerNodeIdHex.substring(0, 8)}');
    } else {
      _log.info('Joined public channel "${entry.name}" locally — owner keys not yet known');
    }
    return true;
  }

  // ── Moderation Timer ─────────────────────────────────────────

  /// Start (or restart) the periodic moderation timer.
  /// Interval adapts to config: ~1/6 of the shortest timeout, clamped to [5s, 5min].
  void _startModerationTimer() {
    _moderationTimer?.cancel();
    final shortest = [
      moderationConfig.juryVoteTimeout,
      moderationConfig.badgeProbationLevel1,
      moderationConfig.csamTempHideDuration,
      moderationConfig.singlePostEscalationTimeout,
    ].reduce((a, b) => a < b ? a : b);
    var intervalMs = (shortest.inMilliseconds ~/ 6).clamp(5000, 300000);
    // For very short test timeouts (<5s), tick every second
    if (shortest.inSeconds < 5) intervalMs = 1000;
    _moderationTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) => _runModerationChecks());
    _log.debug('Moderation timer started: interval=${intervalMs}ms (shortest timeout=${shortest.inSeconds}s)');
  }

  /// Periodic check of all time-based moderation limits.
  Future<void> _runModerationChecks() async {
    final now = DateTime.now();
    final config = moderationConfig;
    var changed = false;

    // 1. Jury vote timeouts — resolve timed-out jury sessions
    for (final session in _activeSessions.values.toList()) {
      if (session.isComplete) continue;
      if (now.difference(session.createdAt) > config.juryVoteTimeout) {
        _log.info('Moderation timer: jury ${session.juryId} timed out');
        _resolveJury(session);
        changed = true;
      }
    }

    // 2. Badge probation — remove badge after successful probation
    for (final channel in _channels.values) {
      if (channel.badBadgeLevel <= 0 || channel.badBadgeLevel >= 3) continue;
      if (!channel.correctionSubmitted) continue;
      if (channel.badBadgeSince == null) continue;

      final probation = channel.badBadgeLevel == 1
          ? config.badgeProbationLevel1
          : config.badgeProbationLevel2;
      if (now.difference(channel.badBadgeSince!) >= probation) {
        final oldLevel = channel.badBadgeLevel;
        channel.badBadgeLevel = (channel.badBadgeLevel - 1).clamp(0, 3);
        channel.correctionSubmitted = false;
        if (channel.badBadgeLevel == 0) {
          channel.badBadgeSince = null;
        }
        _log.info('Moderation timer: badge probation complete for "${channel.name}" ($oldLevel → ${channel.badBadgeLevel})');
        if (channel.isPublic) await publishChannelToIndex(channel.channelIdHex);
        changed = true;
      }
    }

    // 3. CSAM temp-hide — lift hide after duration expires
    for (final channel in _channels.values) {
      if (!channel.isCsamHidden) continue;
      if (channel.csamHiddenSince == null) continue;
      if (now.difference(channel.csamHiddenSince!) >= config.csamTempHideDuration) {
        channel.isCsamHidden = false;
        channel.csamHiddenSince = null;
        _log.info('Moderation timer: CSAM temp-hide lifted for "${channel.name}"');
        if (channel.isPublic) await publishChannelToIndex(channel.channelIdHex);
        changed = true;
      }
    }

    // 4. Single-post escalation — pending post reports escalate to channel reports
    for (final report in _postReports.values.toList()) {
      if (report.state != PostReportState.pending) continue;
      if (now.difference(report.createdAt) >= config.singlePostEscalationTimeout) {
        report.state = PostReportState.escalated;
        // Create a channel-level report from the post report
        final channelReport = ChannelReport(
          reportId: report.reportId,
          channelIdHex: report.channelIdHex,
          reporterNodeIdHex: report.reporterNodeIdHex,
          category: report.category,
          evidencePostIds: [report.postId],
          description: report.description,
        );
        _channelReports[report.reportId] = channelReport;
        _checkJuryThreshold(report.channelIdHex);
        _log.info('Moderation timer: post report ${report.reportId} escalated to channel report');
        changed = true;
      }
    }

    // Clean up completed jury sessions (keep for 1 hour, then discard)
    _activeSessions.removeWhere((id, s) =>
        s.isComplete && now.difference(s.createdAt) > const Duration(hours: 1));

    if (changed) {
      _saveChannels();
      _saveModeration();
      onStateChanged?.call();
    }
  }

  // ── Jury-Auswahl + Verteilung ─────────────────────────────────

  /// Check if reports for a channel have reached the jury threshold.
  void _checkJuryThreshold(String channelIdHex) {
    final config = moderationConfig;
    // Count unique reporters per category for this channel
    final reportsByCategory = <ReportCategory, Set<String>>{};
    for (final r in _channelReports.values) {
      if (r.channelIdHex != channelIdHex || r.state != ReportState.pending) continue;
      reportsByCategory.putIfAbsent(r.category, () => {}).add(r.reporterNodeIdHex);
    }

    for (final entry in reportsByCategory.entries) {
      if (entry.value.length >= config.reportThresholdForJury) {
        // Check if jury already active for this channel+category
        final alreadyActive = _activeSessions.values.any((s) =>
            s.channelIdHex == channelIdHex && s.category == entry.key && !s.isComplete);
        if (alreadyActive) continue;

        _initiateJury(channelIdHex, entry.key);
      }
    }
  }

  /// Start a jury process for a channel+category.
  void _initiateJury(String channelIdHex, ReportCategory category) {
    final report = _channelReports.values
        .where((r) => r.channelIdHex == channelIdHex && r.category == category)
        .firstOrNull;
    if (report == null) return;

    final juryId = bytesToHex(SodiumFFI().randomBytes(16));
    final session = _createJurySession(
      juryId: juryId,
      reportId: report.reportId,
      channelIdHex: channelIdHex,
      category: category,
    );
    if (session == null) {
      _log.warn('Cannot form jury for $channelIdHex — not enough eligible jurors');
      return;
    }

    // Mark all pending reports as jury-active
    for (final r in _channelReports.values) {
      if (r.channelIdHex == channelIdHex && r.category == category && r.state == ReportState.pending) {
        r.state = ReportState.juryActive;
      }
    }
    _saveModeration();
    _log.info('Jury $juryId initiated for $channelIdHex (${category.name}) — ${session.jurorNodeIds.length} jurors');
  }

  /// Create a jury session, select jurors, and send JuryRequests.
  _JurySession? _createJurySession({
    required String juryId,
    required String reportId,
    required String channelIdHex,
    required ReportCategory category,
    bool isPlausibilityJury = false,
  }) {
    final config = moderationConfig;
    final channel = _channels[channelIdHex];

    // Select eligible jurors from accepted contacts
    final eligible = <ContactInfo>[];
    for (final c in _contacts.values) {
      if (c.status != 'accepted') continue;
      if (c.nodeIdHex == identity.userIdHex) continue;
      // Skip channel members (independence)
      if (channel != null && channel.members.containsKey(c.nodeIdHex)) continue;
      // Skip reporters for this channel
      if (_channelReports.values.any((r) => r.channelIdHex == channelIdHex && r.reporterNodeIdHex == c.nodeIdHex)) continue;
      eligible.add(c);
    }

    final jurySize = config.effectiveJurySize(eligible.length);
    if (eligible.length < config.juryMinSize) return null;

    // Random selection
    eligible.shuffle();
    final selected = eligible.take(jurySize).toList();

    final session = _JurySession(
      juryId: juryId,
      reportId: reportId,
      channelIdHex: channelIdHex,
      category: category,
      jurorNodeIds: selected.map((c) => c.nodeIdHex).toList(),
      isPlausibilityJury: isPlausibilityJury,
      createdAt: DateTime.now(),
    );
    _activeSessions[juryId] = session;

    // Send JuryRequest to each selected juror
    for (final juror in selected) {
      _sendJuryRequest(session, juror);
    }

    return session;
  }

  /// Send an encrypted JuryRequest to a juror.
  void _sendJuryRequest(_JurySession session, ContactInfo juror) {
    final channel = _channels[session.channelIdHex];
    final juryReq = proto.JuryRequestMsg()
      ..juryId = hexToBytes(session.juryId)
      ..channelId = hexToBytes(session.channelIdHex)
      ..reportId = hexToBytes(session.reportId)
      ..category = session.category.index
      ..channelName = channel?.name ?? 'Unknown'
      ..channelLanguage = channel?.language ?? '';

    final report = _channelReports[session.reportId];
    if (report != null) {
      juryReq.reportDescription = report.description ?? '';
      for (final eid in report.evidencePostIds) {
        juryReq.evidencePostIds.add(hexToBytes(eid));
      }
    }

    if (juror.x25519Pk == null || juror.mlKemPk == null) return;
    // V3: JURY_REQUEST routes via CHANNEL_JURY_VOTE (V3 enum has no
    // JURY_REQUEST — same Sub-Message-Bump TODO as Channel-Join).
    sendToUser(
      recipientUserId: hexToBytes(juror.nodeIdHex),
      messageType: proto.MessageTypeV3.MTV3_CHANNEL_JURY_VOTE,
      payload: Uint8List.fromList(juryReq.writeToBuffer()),
      groupId: hexToBytes(session.channelIdHex),
    );
  }

  /// Handle incoming JuryRequest (we've been selected as juror).
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// `JuryRequestMsg` proto bytes (V3 receive pipeline). [senderUserId]
  /// is the jury initiator's user-id (`frame.senderUserId`) — recorded
  /// as `requesterNodeIdHex` for the vote-back routing.
  void _handleIncomingJuryRequest(Uint8List payload, Uint8List senderUserId) {
    try {
      final msg = proto.JuryRequestMsg.fromBuffer(payload);
      final juryId = bytesToHex(Uint8List.fromList(msg.juryId));
      final reportId = bytesToHex(Uint8List.fromList(msg.reportId));
      final channelIdHex = bytesToHex(Uint8List.fromList(msg.channelId));
      final senderHex = bytesToHex(senderUserId);

      final request = JuryRequest(
        juryId: juryId,
        reportId: reportId,
        channelIdHex: channelIdHex,
        category: ReportCategory.values[msg.category],
        channelName: msg.channelName,
        channelLanguage: msg.channelLanguage,
        reportDescription: msg.reportDescription.isNotEmpty ? msg.reportDescription : null,
        requesterNodeIdHex: senderHex,
      );

      _pendingJuryRequests[juryId] = request;
      _saveModeration();
      onJuryRequestReceived?.call(request);
      onStateChanged?.call();
      _log.info('Received jury request $juryId for channel "${msg.channelName}"');
    } catch (e) {
      _log.debug('Jury request error: $e');
    }
  }

  /// Handle vote submission — also sends vote back to requester.
  @override
  Future<bool> submitJuryVote(String juryId, String reportId, int vote, {String? reason}) async {
    final request = _pendingJuryRequests[juryId];
    if (request == null) return false;

    request.vote = JuryVoteResult.values[vote];
    request.votedAt = DateTime.now();
    _saveModeration();

    // Send vote back to the jury initiator
    if (request.requesterNodeIdHex != null) {
      final contact = _contacts[request.requesterNodeIdHex!];
      if (contact?.x25519Pk != null && contact?.mlKemPk != null) {
        final voteMsg = proto.JuryVoteMsg()
          ..juryId = hexToBytes(juryId)
          ..reportId = hexToBytes(reportId)
          ..vote = vote
          ..reason = reason ?? '';
        await sendToUser(
          recipientUserId: hexToBytes(request.requesterNodeIdHex!),
          messageType: proto.MessageTypeV3.MTV3_CHANNEL_JURY_VOTE,
          payload: Uint8List.fromList(voteMsg.writeToBuffer()),
          groupId: hexToBytes(request.channelIdHex),
        );
      }
    }

    _log.info('Jury vote submitted for $juryId: ${JuryVoteResult.values[vote].name}');
    return true;
  }

  /// Handle incoming jury vote (we initiated this jury).
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// `JuryVoteMsg` proto bytes (V3 receive pipeline). [senderUserId] is
  /// the voter's user-id (`frame.senderUserId`) — recorded in the
  /// session's vote map.
  void _handleIncomingJuryVote(Uint8List payload, Uint8List senderUserId) {
    try {
      final msg = proto.JuryVoteMsg.fromBuffer(payload);
      final juryId = bytesToHex(Uint8List.fromList(msg.juryId));
      final voterHex = bytesToHex(senderUserId);

      final session = _activeSessions[juryId];
      if (session == null) return;

      session.votes[voterHex] = JuryVoteResult.values[msg.vote];
      _log.info('Jury $juryId: vote from $voterHex = ${JuryVoteResult.values[msg.vote].name}');

      // Check if all votes are in
      _checkJuryCompletion(session);
    } catch (e) {
      _log.debug('Jury vote error: $e');
    }
  }

  /// Check if a jury has enough votes to reach a decision.
  void _checkJuryCompletion(_JurySession session) {
    final config = moderationConfig;
    final totalJurors = session.jurorNodeIds.length;
    final voteCount = session.votes.length;

    if (voteCount < totalJurors) {
      // Check for timeout
      if (DateTime.now().difference(session.createdAt) > config.juryVoteTimeout) {
        _log.info('Jury ${session.juryId} timed out with $voteCount/$totalJurors votes');
        _resolveJury(session);
      }
      return;
    }

    _resolveJury(session);
  }

  /// Resolve a jury — compute result and apply consequences.
  void _resolveJury(_JurySession session) {
    final config = moderationConfig;
    var approve = 0;
    var reject = 0;
    var abstain = 0;

    for (final v in session.votes.values) {
      switch (v) {
        case JuryVoteResult.approve: approve++;
        case JuryVoteResult.reject: reject++;
        case JuryVoteResult.abstain: abstain++;
      }
    }

    final totalVotes = approve + reject;
    final approved = totalVotes > 0 && (approve / totalVotes) >= config.juryMajority;
    session.isComplete = true;

    _log.info('Jury ${session.juryId} resolved: approve=$approve reject=$reject abstain=$abstain → ${approved ? "APPROVED" : "REJECTED"}');

    if (approved) {
      _applyJuryConsequence(session);
    } else if (session.isPlausibilityJury) {
      // Plausibility jury rejected = CSAM hide was unjustified → lift hide
      final channel = _channels[session.channelIdHex];
      if (channel != null && channel.isCsamHidden) {
        channel.isCsamHidden = false;
        channel.csamHiddenSince = null;
        if (channel.badBadgeLevel > 0) channel.badBadgeLevel--;
        _saveChannels();
        _log.info('CSAM hide lifted for "${channel.name}" after plausibility jury rejection');
      }
    }

    // Mark reports as resolved
    for (final r in _channelReports.values) {
      if (r.channelIdHex == session.channelIdHex && r.state == ReportState.juryActive) {
        r.state = ReportState.resolved;
      }
    }
    _saveModeration();

    // Send result to all jurors
    _broadcastJuryResult(session, approve, reject, abstain);
  }

  /// Apply the consequence of an approved jury verdict.
  void _applyJuryConsequence(_JurySession session) {
    final channel = _channels[session.channelIdHex];
    if (channel == null) return;

    final consequence = consequenceForCategory(session.category);

    switch (consequence) {
      case JuryConsequence.reclassifyNsfw:
        channel.isAdult = true;
        channel.badBadgeLevel = (channel.badBadgeLevel + 1).clamp(0, 3);
        channel.badBadgeSince = DateTime.now();
        _log.info('Channel "${channel.name}" relabeled as NSFW, badge level ${channel.badBadgeLevel}');
        break;
      case JuryConsequence.addBadBadge:
        channel.badBadgeLevel = (channel.badBadgeLevel + 1).clamp(0, 3);
        channel.badBadgeSince = DateTime.now();
        _log.info('Channel "${channel.name}" badge escalated to level ${channel.badBadgeLevel}');
        break;
      case JuryConsequence.deleteChannel:
        channel.badBadgeLevel = 3;
        channel.badBadgeSince = DateTime.now();
        channel.tombstoned = true;
        _channelIndex.remove(session.channelIdHex);
        _channelIndex.save();
        _log.info('Channel "${channel.name}" tombstoned (permanent badge)');
        break;
      case JuryConsequence.noAction:
        _log.info('Channel "${channel.name}" no action (CSAM has special procedure)');
        break;
    }

    _saveChannels();
    // Update index
    if (channel.isPublic) {
      publishChannelToIndex(channel.channelIdHex);
    }
  }

  /// Send jury result to all jurors.
  void _broadcastJuryResult(_JurySession session, int approve, int reject, int abstain) {
    final channel = _channels[session.channelIdHex];

    final resultMsg = proto.JuryResultMsg()
      ..juryId = hexToBytes(session.juryId)
      ..reportId = hexToBytes(session.reportId)
      ..channelId = hexToBytes(session.channelIdHex)
      ..consequence = consequenceForCategory(session.category).index
      ..votesApprove = approve
      ..votesReject = reject
      ..votesAbstain = abstain
      ..newBadBadgeLevel = channel?.badBadgeLevel ?? 0;

    final payload = Uint8List.fromList(resultMsg.writeToBuffer());
    final channelIdBytes = hexToBytes(session.channelIdHex);

    for (final jurorId in session.jurorNodeIds) {
      final contact = _contacts[jurorId];
      if (contact?.x25519Pk == null || contact?.mlKemPk == null) continue;
      sendToUser(
        recipientUserId: hexToBytes(jurorId),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_MOD_DECISION,
        payload: payload,
        groupId: channelIdBytes,
      );
    }
  }

  /// Handle incoming jury result (we were a juror).
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// `JuryResultMsg` proto bytes (V3 receive pipeline). The handler only
  /// removes the local pending entry and logs the tally — no sender
  /// argument is needed (sender authenticity is already enforced by the
  /// V3 outer Device-Sig + inner User-Sig chain).
  void _handleIncomingJuryResult(Uint8List payload) {
    try {
      final msg = proto.JuryResultMsg.fromBuffer(payload);
      final juryId = bytesToHex(Uint8List.fromList(msg.juryId));

      // Remove from pending requests
      _pendingJuryRequests.remove(juryId);
      _saveModeration();
      onStateChanged?.call();

      _log.info('Jury result for $juryId: approve=${msg.votesApprove} reject=${msg.votesReject} abstain=${msg.votesAbstain}');
    } catch (e) {
      _log.debug('Jury result error: $e');
    }
  }

  /// Handle incoming channel report (forwarded from reporter).
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// `ChannelReportMsg` proto bytes (V3 receive pipeline). [senderUserId]
  /// is the reporter's user-id (`frame.senderUserId`) — recorded as
  /// `reporterNodeIdHex` on the stored `ChannelReport`.
  void _handleIncomingChannelReport(Uint8List payload, Uint8List senderUserId) {
    try {
      final msg = proto.ChannelReportMsg.fromBuffer(payload);
      final channelIdHex = bytesToHex(Uint8List.fromList(msg.channelId));
      final reportId = bytesToHex(Uint8List.fromList(msg.reportId));
      final reporterHex = bytesToHex(senderUserId);

      // Store the report
      final report = ChannelReport(
        reportId: reportId,
        channelIdHex: channelIdHex,
        reporterNodeIdHex: reporterHex,
        category: ReportCategory.values[msg.category],
        evidencePostIds: msg.evidencePostIds.map((e) => bytesToHex(Uint8List.fromList(e))).toList(),
        description: msg.description.isNotEmpty ? msg.description : null,
      );
      _channelReports[reportId] = report;
      _saveModeration();

      // Check if jury threshold is now reached
      _checkJuryThreshold(channelIdHex);

      _log.info('Received channel report $reportId for $channelIdHex from $reporterHex');
    } catch (e) {
      _log.debug('Channel report error: $e');
    }
  }

  // ── End moderation ─────────────────────────────────────────────

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

  // ── Calls ──────────────────────────────────────────────────────────

  @override
  CallInfo? get currentCall => callManager.currentCall?.toCallInfo();

  @override
  Future<CallInfo?> startCall(String peerNodeIdHex, {bool video = false}) async {
    // Mutual exclusion with group calls
    if (groupCallManager.currentGroupCall != null) return null;
    final session = await callManager.startCall(peerNodeIdHex, video: video);
    if (session != null) notificationSound.playRingback();
    return session?.toCallInfo();
  }

  @override
  Future<void> acceptCall() async {
    await notificationSound.stopRingtone();
    await callManager.acceptCall();
  }

  @override
  Future<void> rejectCall({String reason = 'busy'}) async {
    await notificationSound.stopRingtone();
    await callManager.rejectCall(reason: reason);
  }

  @override
  Future<void> hangup() async {
    await notificationSound.stopAll();
    // Audio-Engine wird via callManager.onCallEnded gestoppt — direkter Aufruf hier wäre doppelt.
    await callManager.hangup();
  }

  @override
  bool get isMuted {
    if (_audioMixer != null) return _audioMixer!.isMuted;
    return _audioEngine?.isMuted ?? false;
  }

  @override
  void toggleMute() {
    if (_audioMixer != null) {
      _audioMixer!.muted = !_audioMixer!.isMuted;
    } else if (_audioEngine != null) {
      _audioEngine!.muted = !_audioEngine!.isMuted;
    }
  }

  @override
  bool get isSpeakerEnabled {
    if (_audioMixer != null) return _audioMixer!.isSpeakerEnabled;
    return _audioEngine?.isSpeakerEnabled ?? true;
  }

  @override
  void toggleSpeaker() {
    if (_audioMixer != null) {
      _audioMixer!.speakerEnabled = !_audioMixer!.isSpeakerEnabled;
    } else if (_audioEngine != null) {
      _audioEngine!.speakerEnabled = !_audioEngine!.isSpeakerEnabled;
    }
  }

  // ── Group Calls ─────────────────────────────────────────────────

  // Callbacks for group call events (wired by GUI)
  @override
  void Function(GroupCallInfo info)? onIncomingGroupCall;
  @override
  void Function(GroupCallInfo info)? onGroupCallStarted;
  @override
  void Function(GroupCallInfo info)? onGroupCallEnded;

  @override
  GroupCallInfo? get currentGroupCall =>
      groupCallManager.currentGroupCall?.toGroupCallInfo();

  @override
  Future<GroupCallInfo?> startGroupCall(String groupIdHex) async {
    // Mutual exclusion with 1:1 calls
    if (callManager.currentCall != null) return null;
    final session = await groupCallManager.startGroupCall(groupIdHex);
    return session?.toGroupCallInfo();
  }

  @override
  Future<void> acceptGroupCall() => groupCallManager.acceptGroupCall();

  @override
  Future<void> rejectGroupCall({String reason = 'busy'}) =>
      groupCallManager.rejectGroupCall(reason: reason);

  @override
  Future<void> leaveGroupCall() async {
    _stopAudioMixer();
    _stopGroupVideo();
    await groupCallManager.leaveGroupCall();
  }

  Future<void> _startAudioMixer(GroupCallSession session) async {
    // Plan §E4 — same RECORD_AUDIO gate as 1:1 calls (see _startAudioEngine).
    // Group calls share the same capture path; without the permission we'd
    // promote the FGS to mic-type but never actually capture anything.
    if (Platform.isAndroid) {
      final granted = await AudioPermissions.requestRecordAudio();
      if (!granted) {
        _log.warn('RECORD_AUDIO permission denied — group call audio disabled');
        return;
      }
    }

    // Bug #U10b — same mic-type promotion as 1:1 calls (see _startAudioEngine).
    if (Platform.isAndroid) {
      await ForegroundServiceControl.promoteForCall();
    }

    if (session.callKey == null) return;
    try {
      _audioMixer = AudioMixer(
        callKey: session.callKey!,
        profileDir: profileDir,
        callKeyVersion: session.callKeyVersion,
      );
      _audioMixer!.onAudioFrame = (encryptedFrame) {
        groupCallManager.sendGroupAudioFrame(encryptedFrame);
      };
      await _audioMixer!.start();
    } catch (e) {
      _log.error('Audio mixer start failed: $e');
    }
  }

  void _stopAudioMixer() {
    _audioMixer?.stop();
    _audioMixer = null;
    if (Platform.isAndroid) {
      ForegroundServiceControl.demoteAfterCall();
    }
  }

  Future<void> _startGroupVideo(GroupCallSession session) async {
    // Desktop only — vpx_ffi has Linux/macOS/Windows .so/.dylib/.dll paths.
    // Android-Group-Video braucht eigenen Codec-Pfad (geplant, separate Spec).
    // iOS analog (AVFoundation-Port pending).
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows) ||
        session.callKey == null) {
      return;
    }
    _startGroupVideoCapture(session);
    _startGroupVideoReceiver(session);
  }

  /// Factory callback: GUI sets this to create a VideoEngine instance.
  /// Avoids importing dart:ui in the daemon.
  /// Signature: (Uint8List callKey, void Function(Uint8List) onVideoFrame) -> dynamic
  dynamic Function(Uint8List callKey, void Function(Uint8List) onVideoFrame)? createVideoEngine;

  void _startGroupVideoCapture(GroupCallSession session) {
    if (session.callKey == null || createVideoEngine == null) return;
    try {
      _groupVideoEngine = createVideoEngine!(
        session.callKey!,
        (serializedFrame) => groupCallManager.sendGroupVideoFrame(serializedFrame),
      );
    } catch (e) {
      _log.error('Group video engine start failed: $e');
      _groupVideoEngine = null;
    }
  }

  void _startGroupVideoReceiver(GroupCallSession session) {
    if (session.callKey == null) return;
    _groupVideoReceiver = GroupVideoReceiver(
      callKey: session.callKey!,
      profileDir: profileDir,
      callKeyVersion: session.callKeyVersion,
    );
    _groupVideoReceiver!.onDecodedI420 = (senderHex, i420, w, h) {
      onGroupVideoI420Frame?.call(senderHex, i420, w, h);
    };
  }

  void _stopGroupVideo() {
    try { (_groupVideoEngine as dynamic)?.stop(); } catch (_) {}
    _groupVideoEngine = null;
    _groupVideoReceiver?.dispose();
    _groupVideoReceiver = null;
  }

  /// Callback: group video I420 frame decoded (UI converts to RGBA).
  void Function(String senderHex, Uint8List i420, int width, int height)? onGroupVideoI420Frame;

  // ── Audio Engine ──────────────────────────────────────────────────

  Future<void> _startAudioEngine(CallSession session) async {
    // Plan §E4 — RECORD_AUDIO runtime permission must be granted before we
    // promote the foreground service to mic-type. Asking earlier (e.g. at
    // app start) would surprise users; asking after promote leaves the FGS
    // in MICROPHONE mode with no actual capture, which Android logs as a
    // misuse. The helper is a no-op on non-Android (returns true).
    if (Platform.isAndroid) {
      final granted = await AudioPermissions.requestRecordAudio();
      if (!granted) {
        _log.warn('RECORD_AUDIO permission denied — call audio disabled');
        return;
      }
    }

    // Bug #U10b — promote the foreground service to MICROPHONE type
    // BEFORE the engine opens AudioRecord (API 34+ enforces this at the
    // moment of capture). The helper is a no-op on non-Android. We do
    // this even though the engine itself is currently Linux-only so the
    // wiring is already in place for the upcoming C2/C3 cross-platform
    // refactor.
    if (Platform.isAndroid) {
      await ForegroundServiceControl.promoteForCall();
    }

    if (session.sharedSecret == null) return;

    try {
      _audioEngine = AudioEngine(
        sharedSecret: session.sharedSecret!,
        profileDir: profileDir,
      );
      _audioEngine!.onAudioFrame = (encryptedFrame) {
        _sendAudioFrame(session, encryptedFrame);
      };
      await _audioEngine!.start();
    } catch (e) {
      _log.error('Audio engine start failed: $e');
    }
  }

  void _stopAudioEngine() {
    _audioEngine?.stop();
    _audioEngine = null;
    // Bug #U10b — demote back to plain DATA_SYNC so the persistent
    // "microphone in use" indicator goes away. Fire-and-forget; failures
    // are non-fatal and swallowed inside the helper.
    if (Platform.isAndroid) {
      ForegroundServiceControl.demoteAfterCall();
    }
  }

  void _sendAudioFrame(CallSession session, Uint8List encryptedFrame) {
    session.framesSent++;
    final peerNodeId = hexToBytes(session.peerNodeIdHex);

    // Per-call route cache: keep the resolved PeerInfo on the session so the
    // routing-table XOR+bucket lookup runs at most once per call. The
    // DV-Routing onRouteDown handler invalidates this cache. The cache lives
    // on as a structural optimization; the V3 send-path itself runs through
    // sendToUser which orchestrates resolveUserToDevices + per-device
    // dispatch (the inner KEM is unavoidable today; §4.4.5 fast-path
    // skip-KEM/skip-zstd/skip-ML-DSA optimisation lands later).
    if (session.cachedRoute == null) {
      final peer = node.routingTable.getPeer(peerNodeId) ??
          node.routingTable.getPeerByUserId(peerNodeId);
      if (peer != null) {
        session.cachedRoute = peer;
        session.cachedRouteAt = DateTime.now();
      }
    }

    // Fire-and-forget; live audio tolerates frame loss.
    unawaited(sendToUser(
      recipientUserId: peerNodeId,
      messageType: proto.MessageTypeV3.MTV3_CALL_AUDIO,
      payload: encryptedFrame,
    ));
  }

  /// Ask the remote video sender to emit a keyframe on the next encode.
  /// Signal-only message (empty payload) on the V3 ApplicationFrame path —
  /// ack-less by design (handled receiver-side as a hint, not a guarantee).
  void sendKeyframeRequest() {
    final session = callManager.currentCall;
    if (session == null || session.state != CallState.inCall) return;
    sendToUser(
      recipientUserId: hexToBytes(session.peerNodeIdHex),
      messageType: proto.MessageTypeV3.MTV3_CALL_KEYFRAME_REQUEST,
      payload: Uint8List(0),
    );
  }

  /// Callbacks for video frame events (set by VideoEngine)
  void Function(Uint8List serializedVideoFrame)? onVideoFrameReceived;
  void Function()? onKeyframeRequested;

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
  }

  // ── Persistence ────────────────────────────────────────────────────

  // Cached FileEncryption instance — reuses the same db.key for all operations.
  FileEncryption? _fileEncCached;
  FileEncryption get _fileEnc {
    return _fileEncCached ??= FileEncryption(baseDir: '${AppPaths.home}/.cleona');
  }

  void _loadContacts() {
    try {
      final json = _fileEnc.readJsonFile('$profileDir/contacts.json');
      if (json == null) {
        final encFile = File('$profileDir/contacts.json.enc');
        if (encFile.existsSync()) {
          _log.warn('contacts.json.enc exists (${encFile.lengthSync()} bytes) but could not be decrypted — DATA LOSS');
        } else {
          _log.info('No contacts file found (fresh profile)');
        }
        _contactsLoaded = true; // File genuinely absent = nothing to protect
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
    } catch (e) {
      _log.warn('Failed to save contacts: $e');
    }
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
          _log.warn('conversations.json.enc exists (${encFile.lengthSync()} bytes) but could not be decrypted — DATA LOSS');
        }
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

  /// Post an Android system notification for an incoming message.
  void _postAndroidNotification(String senderName, String text, String conversationId) {
    if (onPostNotificationAndroid == null) return;
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

  void _saveConversations() {
    if (!_conversationsLoaded && conversations.isEmpty) {
      final encFile = File('$profileDir/conversations.json.enc');
      if (encFile.existsSync()) {
        _log.warn('REFUSED to save empty conversations — load failed but file exists');
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
          // Use UiMessage.toJson for complete serialization (media, transcripts, reactions, etc.)
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
          _log.warn('groups.json.enc exists (${encFile.lengthSync()} bytes) but could not be decrypted — DATA LOSS');
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
          _log.warn('channels.json.enc exists (${encFile.lengthSync()} bytes) but could not be decrypted — DATA LOSS');
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
    final confirmed = node.confirmedPeerIds;
    final dvReachable = node.dvRouting.allDestinations;
    return node.routingTable.allPeers
        .where((p) => confirmed.contains(p.nodeIdHex) || dvReachable.contains(p.nodeIdHex))
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
    );
  }

  // ── Contact issue reporting ────────────────────────────────────────
  @override
  ContactIssueReport? buildContactIssueReport(String contactNodeIdHex) {
    final contact = _contacts[contactNodeIdHex];
    if (contact == null) return null;
    return contactIssueReporter.buildReport(contact);
  }

  @override
  Future<bool> publishContactIssueReport(String contactNodeIdHex) async {
    final report = buildContactIssueReport(contactNodeIdHex);
    if (report == null) return false;
    return contactIssueReporter.publishReport(report);
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
    final sodium = SodiumFFI();

    // 1. Generate new seed → new keys (BEFORE sending, so we can dual-sign)
    final newEntropy = sodium.randomBytes(32);
    final newMasterSeed = SeedPhrase.entropyToSeed(newEntropy);
    final hdIndex = identity.hdIndex ?? 0;

    final newEd25519 = HdWallet.deriveEd25519(newMasterSeed, hdIndex);
    final newX25519Pk = sodium.ed25519PkToX25519(newEd25519.publicKey);
    final newX25519Sk = sodium.ed25519SkToX25519(newEd25519.secretKey);

    // PQ keygen in background isolate (ANR fix)
    final pqKeys = await generatePqKeypairsIsolated();
    final newMlDsa = pqKeys.mlDsa;
    final newMlKem = pqKeys.mlKem;

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

    // 3. Send KEY_ROTATION_BROADCAST to all contacts (signed with OLD identity).
    //    Welle 6 §7.4 Variant (b) — Emergency-flavor MUST go on the
    //    InfrastructureFrame path: KEM-encap under each contact's
    //    Device-KEM-PK, Outer Device-Sig under the unchanged Device-Sig keys
    //    (rotation-stable per §3.5b). The dual-sig in the body is the inner
    //    authentication subject. Every recipient device gets its own frame
    //    (per-device fan-out via 2D-DHT auth-manifest).
    final payloadBytes = Uint8List.fromList(broadcast.writeToBuffer());
    // Paket C: captured BEFORE `rotateIdentityFull` overwrites identity.userId,
    // so the retry timer can address contacts under the pre-rotation hex.
    // (Currently informational on the InfraFrame path — the routing key is
    // recipientDeviceId, not envelope.senderId — but kept for symmetry with
    // the persisted retry state.)
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

    // 4. Send new seed to twin devices via TWIN_SYNC (encrypted with OLD key)
    if (_devices.length > 1) {
      final seedPayload = utf8.encode(jsonEncode({
        'emergencyRotation': true,
        'newEntropy': bytesToHex(newEntropy),
        'hdIndex': hdIndex,
      }));
      _sendTwinSync(
          proto.TwinSyncType.SETTINGS_CHANGED, Uint8List.fromList(seedPayload));
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
        'New Node-ID: ${identity.userIdHex.substring(0, 16)}...');
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

  /// Handle SETTINGS_CHANGED from twin: includes emergency key rotation (§26.6.2).
  /// When a twin device triggers rotateIdentityKeys(), it sends the new entropy
  /// so this device can derive and apply the same new keys.
  /// Async: PQ keygen runs in background isolate (ANR fix).
  Future<void> _handleTwinSettingsChanged(List<int> payload) async {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;

      if (json['emergencyRotation'] == true) {
        final newEntropyHex = json['newEntropy'] as String;
        final hdIndex = json['hdIndex'] as int? ?? identity.hdIndex ?? 0;
        final newEntropy = hexToBytes(newEntropyHex);
        final newMasterSeed = SeedPhrase.entropyToSeed(newEntropy);

        final sodium = SodiumFFI();
        final newEd25519 = HdWallet.deriveEd25519(newMasterSeed, hdIndex);
        final newX25519Pk = sodium.ed25519PkToX25519(newEd25519.publicKey);
        final newX25519Sk = sodium.ed25519SkToX25519(newEd25519.secretKey);

        // PQ keygen in background isolate (ANR fix)
        final pqKeys = await generatePqKeypairsIsolated();

        identity.rotateIdentityFull(
          newEd25519Pk: newEd25519.publicKey,
          newEd25519Sk: newEd25519.secretKey,
          newMlDsaPk: pqKeys.mlDsa.publicKey,
          newMlDsaSk: pqKeys.mlDsa.secretKey,
          newX25519Pk: newX25519Pk,
          newX25519Sk: newX25519Sk,
          newMlKemPk: pqKeys.mlKem.publicKey,
          newMlKemSk: pqKeys.mlKem.secretKey,
        );
        // §5.11 — same as the originating-device path: push refreshed
        // PeerInfo to all known peers so the mesh heals stale-PK caches
        // without waiting for the §5.12 cold-path 1 h tick.
        node.broadcastAddressUpdate();
        _log.info('Emergency key rotation applied from twin. '
            'New Node-ID: ${identity.userIdHex.substring(0, 16)}...');
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

    contact.ed25519Pk = newEd25519Pk;
    contact.mlDsaPk = newMlDsaPk;
    contact.x25519Pk = newX25519Pk;
    contact.mlKemPk = newMlKemPk;

    // Compute new Node-ID for this contact
    final newNodeId = HdWallet.computeNodeId(newEd25519Pk, NetworkSecret.secret);
    final newNodeIdHex = bytesToHex(newNodeId);
    contact.nodeId = newNodeId;

    // Re-key across all data structures if Node-ID changed
    if (newNodeIdHex != senderHex) {
      _contacts.remove(senderHex);
      _contacts[newNodeIdHex] = contact;

      // Re-key group members
      for (final group in _groups.values) {
        final member = group.members.remove(senderHex);
        if (member != null) {
          group.members[newNodeIdHex] = GroupMemberInfo(
            nodeIdHex: newNodeIdHex,
            displayName: member.displayName,
            role: member.role,
            ed25519Pk: newEd25519Pk,
            x25519Pk: newX25519Pk,
            mlKemPk: newMlKemPk,
          );
          if (group.ownerNodeIdHex == senderHex) {
            group.ownerNodeIdHex = newNodeIdHex;
          }
        }
      }
      _saveGroups();

      // Re-key channel members
      for (final channel in _channels.values) {
        final member = channel.members.remove(senderHex);
        if (member != null) {
          channel.members[newNodeIdHex] = ChannelMemberInfo(
            nodeIdHex: newNodeIdHex,
            displayName: member.displayName,
            role: member.role,
            ed25519Pk: newEd25519Pk,
            x25519Pk: newX25519Pk,
            mlKemPk: newMlKemPk,
          );
          if (channel.ownerNodeIdHex == senderHex) {
            channel.ownerNodeIdHex = newNodeIdHex;
          }
        }
      }
      _saveChannels();

      // Re-key conversations (Conversation.id is final → rebuild)
      if (conversations.containsKey(senderHex)) {
        final oldConv = conversations.remove(senderHex)!;
        conversations[newNodeIdHex] = Conversation(
          id: newNodeIdHex,
          displayName: oldConv.displayName,
          messages: oldConv.messages,
          unreadCount: oldConv.unreadCount,
          lastActivity: oldConv.lastActivity,
          profilePictureBase64: oldConv.profilePictureBase64,
          isGroup: oldConv.isGroup,
          isChannel: oldConv.isChannel,
          config: oldConv.config,
          pendingConfigProposal: oldConv.pendingConfigProposal,
          pendingConfigProposer: oldConv.pendingConfigProposer,
          isFavorite: oldConv.isFavorite,
        );
        _saveConversations();
      }

      // Update routing table: copy old peer's addresses to new peer entry.
      // Architecture §17.3: KEY_ROTATION_BROADCAST is authenticated with the
      // old key (verified upstream), so the new key is firstParty.
      final oldPeer = node.routingTable.getPeer(senderUserId);
      if (oldPeer != null) {
        node.routingTable.removePeer(senderUserId);
        node.routingTable.addPeer(PeerInfo(
          nodeId: newNodeId,
          addresses: oldPeer.addresses,
          ed25519PublicKey: newEd25519Pk,
          x25519PublicKey: newX25519Pk,
          mlKemPublicKey: newMlKemPk,
          pkSource: PkSource.firstParty,
        ));
      }
    } else {
      // Node-ID unchanged — update keys in-place. firstParty per §17.3.
      final peer = node.routingTable.getPeer(contact.nodeId);
      if (peer != null) {
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
    }

    _saveContacts();

    // §26.6.2 Send KEY_ROTATION_ACK back to the rotator at their new
    // Node-ID. Pure ACK — empty payload. V3 inner User-Sig + outer Device-
    // Sig + KEM-decap chain provides Paket-C-F2 forge defence.
    unawaited(sendToUser(
      recipientUserId: newNodeId,
      messageType: proto.MessageTypeV3.MTV3_KEY_ROTATION_ACK,
      payload: Uint8List(0),
    ));

    _log.info('Emergency key rotation from ${contact.displayName}: '
        'all keys updated, Node-ID ${senderHex.substring(0, 8)} → ${newNodeIdHex.substring(0, 8)}');
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

  /// Handle incoming CALENDAR_INVITE from a group event creator.
  /// Pending Free/Busy query results, keyed by requestId hex.
  final Map<String, List<FreeBusyBlockResult>> _freeBusyResults = {};
  final Map<String, void Function(List<FreeBusyBlockResult>)> _freeBusyCallbacks = {};

  @override
  Future<String> createCalendarEvent(CalendarEvent event) async {
    if (_reducedMode) {
      _log.warn('createCalendarEvent blocked: reducedMode active');
      return '';
    }
    calendarManager.createEvent(event);
    if (event.groupId != null) {
      await sendCalendarInvite(event);
    }
    return event.eventId;
  }

  @override
  Future<bool> updateCalendarEvent(String eventIdHex, {
    String? title, String? description, String? location,
    int? startTime, int? endTime, bool? allDay, bool? hasCall,
    List<int>? reminders, String? recurrenceRule,
    bool? taskCompleted, int? taskPriority, bool? cancelled,
  }) async {
    if (_reducedMode) {
      _log.warn('updateCalendarEvent blocked: reducedMode active');
      return false;
    }
    final ok = calendarManager.updateEvent(eventIdHex,
      title: title, description: description, location: location,
      startTime: startTime, endTime: endTime, allDay: allDay,
      hasCall: hasCall, reminders: reminders, recurrenceRule: recurrenceRule,
      taskCompleted: taskCompleted, taskPriority: taskPriority,
      cancelled: cancelled,
    );
    if (ok) {
      final evt = calendarManager.events[eventIdHex];
      if (evt?.groupId != null && evt?.createdBy == identity.userIdHex) {
        await sendCalendarUpdate(eventIdHex);
      }
    }
    return ok;
  }

  @override
  Future<bool> deleteCalendarEvent(String eventIdHex) async {
    if (_reducedMode) {
      _log.warn('deleteCalendarEvent blocked: reducedMode active');
      return false;
    }
    final evt = calendarManager.events[eventIdHex];
    if (evt?.groupId != null && evt?.createdBy == identity.userIdHex) {
      await sendCalendarDelete(eventIdHex);
    } else {
      calendarManager.deleteEvent(eventIdHex);
    }
    return true;
  }

  /// Send a calendar invite to all members of a group (Pairwise Fan-out).
  @override
  Future<void> sendCalendarInvite(CalendarEvent event) async {
    if (_reducedMode) {
      _log.warn('sendCalendarInvite blocked: reducedMode active');
      return;
    }
    if (event.groupId == null) return;

    final group = _groups[event.groupId!];
    if (group == null) {
      _log.warn('Cannot send calendar invite: group ${event.groupId} not found');
      return;
    }

    final invite = proto.CalendarInviteMsg()
      ..eventId = hexToBytes(event.eventId)
      ..title = event.title
      ..description = event.description ?? ''
      ..location = event.location ?? ''
      ..startTime = Int64(event.startTime)
      ..endTime = Int64(event.endTime)
      ..allDay = event.allDay
      ..timeZone = event.timeZone
      ..recurrenceRule = event.recurrenceRule ?? ''
      ..hasCall = event.hasCall
      ..groupId = hexToBytes(event.groupId!)
      ..createdBy = identity.userId
      ..createdByName = displayName
      ..category = proto.EventCategory.valueOf(event.category.index) ?? proto.EventCategory.APPOINTMENT;
    for (final m in event.reminders) {
      invite.reminders.add(proto.CalendarReminderOffset()..minutesBefore = m);
    }

    final payload = invite.writeToBuffer();
    for (final memberHex in group.members.keys) {
      if (memberHex == identity.userIdHex) continue;
      await _sendEncryptedPayload(
        hexToBytes(memberHex),
        proto.MessageTypeV3.MTV3_CALENDAR_INVITE,
        Uint8List.fromList(payload),
      );
    }

    _log.info('Sent CALENDAR_INVITE for ${event.title} to ${group.members.length - 1} members');
  }

  /// Send RSVP response for a group calendar event.
  @override
  Future<void> sendCalendarRsvp(String eventIdHex, RsvpStatus status, {
    int? proposedStart,
    int? proposedEnd,
    String? comment,
  }) async {
    if (_reducedMode) {
      _log.warn('sendCalendarRsvp blocked: reducedMode active');
      return;
    }
    final event = calendarManager.events[eventIdHex];
    if (event == null || event.groupId == null) return;

    final group = _groups[event.groupId!];
    if (group == null) return;

    final rsvp = proto.CalendarRsvpMsg()
      ..eventId = hexToBytes(eventIdHex)
      ..response = proto.RsvpStatus.valueOf(status.index) ?? proto.RsvpStatus.RSVP_ACCEPTED
      ..comment = comment ?? '';
    if (proposedStart != null) rsvp.proposedStart = Int64(proposedStart);
    if (proposedEnd != null) rsvp.proposedEnd = Int64(proposedEnd);

    // Record own RSVP
    calendarManager.setRsvp(eventIdHex, identity.userIdHex, status);

    // Fan-out to all group members
    final payload = rsvp.writeToBuffer();
    for (final memberHex in group.members.keys) {
      if (memberHex == identity.userIdHex) continue;
      await _sendEncryptedPayload(
        hexToBytes(memberHex),
        proto.MessageTypeV3.MTV3_CALENDAR_RSVP,
        Uint8List.fromList(payload),
      );
    }

    _log.info('Sent CALENDAR_RSVP for $eventIdHex: $status');
  }

  /// Send calendar update to all group members.
  @override
  Future<void> sendCalendarUpdate(String eventIdHex) async {
    if (_reducedMode) {
      _log.warn('sendCalendarUpdate blocked: reducedMode active');
      return;
    }
    final event = calendarManager.events[eventIdHex];
    if (event == null || event.groupId == null) return;

    final group = _groups[event.groupId!];
    if (group == null) return;

    final update = proto.CalendarUpdateMsg()
      ..eventId = hexToBytes(eventIdHex)
      ..title = event.title
      ..description = event.description ?? ''
      ..location = event.location ?? ''
      ..startTime = Int64(event.startTime)
      ..endTime = Int64(event.endTime)
      ..allDay = event.allDay
      ..timeZone = event.timeZone
      ..recurrenceRule = event.recurrenceRule ?? ''
      ..hasCall = event.hasCall
      ..cancelled = event.cancelled
      ..updatedAt = Int64(event.updatedAt);
    for (final m in event.reminders) {
      update.reminders.add(proto.CalendarReminderOffset()..minutesBefore = m);
    }

    final payload = update.writeToBuffer();
    for (final memberHex in group.members.keys) {
      if (memberHex == identity.userIdHex) continue;
      await _sendEncryptedPayload(
        hexToBytes(memberHex),
        proto.MessageTypeV3.MTV3_CALENDAR_UPDATE,
        Uint8List.fromList(payload),
      );
    }

    _log.info('Sent CALENDAR_UPDATE for $eventIdHex');
  }

  /// Send calendar delete to all group members.
  @override
  Future<void> sendCalendarDelete(String eventIdHex) async {
    if (_reducedMode) {
      _log.warn('sendCalendarDelete blocked: reducedMode active');
      return;
    }
    final event = calendarManager.events[eventIdHex];
    if (event == null || event.groupId == null) return;

    final group = _groups[event.groupId!];
    if (group == null) return;

    final del = proto.CalendarDeleteMsg()
      ..eventId = hexToBytes(eventIdHex)
      ..deletedAt = Int64(DateTime.now().millisecondsSinceEpoch);

    final payload = del.writeToBuffer();
    for (final memberHex in group.members.keys) {
      if (memberHex == identity.userIdHex) continue;
      await _sendEncryptedPayload(
        hexToBytes(memberHex),
        proto.MessageTypeV3.MTV3_CALENDAR_DELETE,
        Uint8List.fromList(payload),
      );
    }

    calendarManager.deleteEvent(eventIdHex);
    _log.info('Sent CALENDAR_DELETE for $eventIdHex');
  }

  /// Send a FREE_BUSY_REQUEST to a contact.
  @override
  Future<String> sendFreeBusyRequest(String contactNodeIdHex, int queryStart, int queryEnd) async {
    if (_reducedMode) {
      _log.warn('sendFreeBusyRequest blocked: reducedMode active');
      return '';
    }
    final requestIdBytes = SodiumFFI().randomBytes(16);
    final requestIdHex = bytesToHex(requestIdBytes);

    final req = proto.FreeBusyRequestMsg()
      ..queryStart = Int64(queryStart)
      ..queryEnd = Int64(queryEnd)
      ..requestId = requestIdBytes;

    await _sendEncryptedPayload(
      hexToBytes(contactNodeIdHex),
      proto.MessageTypeV3.MTV3_FREE_BUSY_REQUEST,
      req.writeToBuffer(),
    );

    _log.info('Sent FREE_BUSY_REQUEST to ${contactNodeIdHex.substring(0, 8)} '
        '(${DateTime.fromMillisecondsSinceEpoch(queryStart)} – '
        '${DateTime.fromMillisecondsSinceEpoch(queryEnd)})');
    return requestIdHex;
  }

  // ── Polls (§24) ──────────────────────────────────────────────────────

  /// Iterable of member/subscriber node IDs for a group or channel, excluding
  /// the local identity. Returns null if the entity is unknown.
  Iterable<String>? _pollRecipients(String entityIdHex) {
    final group = _groups[entityIdHex];
    if (group != null) {
      return group.members.keys.where((h) => h != identity.userIdHex);
    }
    final channel = _channels[entityIdHex];
    if (channel != null) {
      return channel.members.keys.where((h) => h != identity.userIdHex);
    }
    return null;
  }

  /// Returns the cached channel public keys of all recipients plus our own
  /// public key — used as the ring for anonymous voting (§24.4).
  List<Uint8List> _ringForEntity(String entityIdHex) {
    final members = _pollRecipients(entityIdHex)?.toList() ?? const [];
    final keys = <Uint8List>[];
    for (final memberHex in members) {
      final c = _contacts[memberHex];
      if (c?.ed25519Pk != null) keys.add(c!.ed25519Pk!);
    }
    keys.add(identity.ed25519PublicKey);
    // Canonical ordering so every participant derives the same challenge.
    keys.sort((a, b) {
      for (var i = 0; i < a.length && i < b.length; i++) {
        final d = a[i] - b[i];
        if (d != 0) return d;
      }
      return a.length - b.length;
    });
    return keys;
  }

  /// Protobuf helper: wrap PollCreateMsg from a local Poll.
  proto.PollCreateMsg _encodePollCreate(Poll poll) {
    final msg = proto.PollCreateMsg()
      ..pollId = hexToBytes(poll.pollId)
      ..question = poll.question
      ..description = poll.description
      ..pollType =
          proto.PollType.valueOf(poll.pollType.index) ?? proto.PollType.POLL_SINGLE_CHOICE
      ..groupId = hexToBytes(poll.groupId)
      ..createdBy = identity.userId
      ..createdByName = poll.createdByName
      ..createdAt = Int64(poll.createdAt)
      ..settings = (proto.PollSettingsMsg()
        ..anonymous = poll.settings.anonymous
        ..deadline = Int64(poll.settings.deadline)
        ..allowVoteChange = poll.settings.allowVoteChange
        ..showResultsBeforeClose = poll.settings.showResultsBeforeClose
        ..maxChoices = poll.settings.maxChoices
        ..scaleMin = poll.settings.scaleMin
        ..scaleMax = poll.settings.scaleMax
        ..onlyMembersCanVote = poll.settings.onlyMembersCanVote);
    for (final o in poll.options) {
      msg.options.add(proto.PollOptionMsg()
        ..optionId = o.optionId
        ..label = o.label
        ..dateStart = Int64(o.dateStart ?? 0)
        ..dateEnd = Int64(o.dateEnd ?? 0));
    }
    return msg;
  }

  Poll _decodePollCreate(proto.PollCreateMsg msg, {required String senderHex}) {
    final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
    final groupIdHex = bytesToHex(Uint8List.fromList(msg.groupId));
    final settings = PollSettings(
      anonymous: msg.settings.anonymous,
      deadline: msg.settings.deadline.toInt(),
      allowVoteChange: msg.settings.allowVoteChange,
      showResultsBeforeClose: msg.settings.showResultsBeforeClose,
      maxChoices: msg.settings.maxChoices,
      scaleMin: msg.settings.scaleMin == 0 ? 1 : msg.settings.scaleMin,
      scaleMax: msg.settings.scaleMax == 0 ? 5 : msg.settings.scaleMax,
      onlyMembersCanVote: msg.settings.onlyMembersCanVote,
    );
    final options = msg.options
        .map((o) => PollOption(
              optionId: o.optionId,
              label: o.label,
              dateStart: o.dateStart.toInt() == 0 ? null : o.dateStart.toInt(),
              dateEnd: o.dateEnd.toInt() == 0 ? null : o.dateEnd.toInt(),
            ))
        .toList();
    return Poll(
      pollId: pollIdHex,
      identityId: identity.userIdHex,
      question: msg.question,
      description: msg.description,
      pollType:
          PollType.values[msg.pollType.value.clamp(0, PollType.values.length - 1)],
      options: options,
      settings: settings,
      groupId: groupIdHex,
      createdByHex: senderHex,
      createdByName: msg.createdByName,
      createdAt: msg.createdAt.toInt(),
    );
  }

  proto.PollVoteMsg _encodePollVote(PollVoteRecord v, {bool stripIdentity = false}) {
    final msg = proto.PollVoteMsg()
      ..pollId = hexToBytes(v.pollId)
      ..scaleValue = v.scaleValue
      ..freeText = v.freeText
      ..votedAt = Int64(v.votedAt);
    if (!stripIdentity) {
      msg
        ..voterId = identity.userId
        ..voterName = v.voterName;
    }
    msg.selectedOptions.addAll(v.selectedOptions);
    for (final entry in v.dateResponses.entries) {
      msg.dateResponses.add(proto.DateResponseMsg()
        ..optionId = entry.key
        ..availability = proto.DateAvailability.valueOf(entry.value.index) ??
            proto.DateAvailability.DATE_AVAIL_YES);
    }
    return msg;
  }

  PollVoteRecord _decodePollVote(
    proto.PollVoteMsg msg, {
    required String voterIdHex,
    required bool anonymous,
  }) {
    return PollVoteRecord(
      pollId: bytesToHex(Uint8List.fromList(msg.pollId)),
      voterIdHex: voterIdHex,
      voterName: msg.voterName,
      selectedOptions: msg.selectedOptions.toList(),
      dateResponses: {
        for (final r in msg.dateResponses)
          r.optionId:
              DateAvailability.values[r.availability.value.clamp(0, DateAvailability.values.length - 1)]
      },
      scaleValue: msg.scaleValue,
      freeText: msg.freeText,
      votedAt: msg.votedAt.toInt(),
      anonymous: anonymous,
    );
  }

  // ── Handlers ──────────────────────────────────────────────────────────

  // ── Senders ──────────────────────────────────────────────────────────

  Future<void> _fanoutToEntity(String entityIdHex, proto.MessageTypeV3 type, List<int> payload) async {
    final recipients = _pollRecipients(entityIdHex);
    if (recipients == null) return;
    for (final memberHex in recipients) {
      await _sendEncryptedPayload(
        hexToBytes(memberHex),
        type,
        Uint8List.fromList(payload),
      );
    }
  }

  Future<void> _sendPollCreate(Poll poll) async {
    final payload = _encodePollCreate(poll).writeToBuffer();
    await _fanoutToEntity(poll.groupId, proto.MessageTypeV3.MTV3_POLL_CREATE, payload);
    _log.info('Sent POLL_CREATE ${poll.pollId.substring(0, 8)} to entity ${poll.groupId.substring(0, 8)}');
  }

  Future<void> _sendPollVoteNonAnonymous(Poll poll, PollVoteRecord vote) async {
    final msg = _encodePollVote(vote);
    final payload = msg.writeToBuffer();

    // Channels: send only to creator (§24.3.2). Groups: fan-out.
    if (_channels.containsKey(poll.groupId) &&
        poll.createdByHex != identity.userIdHex) {
      await _sendEncryptedPayload(
        hexToBytes(poll.createdByHex),
        proto.MessageTypeV3.MTV3_POLL_VOTE,
        Uint8List.fromList(payload),
      );
    } else {
      await _fanoutToEntity(poll.groupId, proto.MessageTypeV3.MTV3_POLL_VOTE, payload);
    }
  }

  Future<void> _sendPollVoteAnonymous(Poll poll, PollVoteRecord vote) async {
    final identityIndexed = _encodePollVote(vote, stripIdentity: true);
    final voteBytes = identityIndexed.writeToBuffer();
    final ring = _ringForEntity(poll.groupId);
    final context = hexToBytes(poll.pollId);
    final signed = LinkableRingSignature.sign(
      message: Uint8List.fromList(voteBytes),
      context: context,
      ringMembers: ring,
      signerSk: identity.ed25519SecretKey,
      signerPk: identity.ed25519PublicKey,
    );

    final msg = proto.PollVoteAnonymousMsg()
      ..pollId = hexToBytes(poll.pollId)
      ..encryptedChoice = voteBytes
      ..keyImage = signed.keyImage
      ..ringSignature = signed.signature
      ..votedAt = Int64(vote.votedAt);
    for (final pk in ring) {
      msg.ringMembers.add(pk);
    }

    final payload = msg.writeToBuffer();
    await _fanoutToEntity(poll.groupId, proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS, payload);
  }

  Future<void> _sendPollVoteRevoke(Poll poll, Uint8List keyImage) async {
    final ring = _ringForEntity(poll.groupId);
    final context = hexToBytes(poll.pollId);
    final marker = Uint8List.fromList('revoke'.codeUnits);
    final signed = LinkableRingSignature.sign(
      message: marker,
      context: context,
      ringMembers: ring,
      signerSk: identity.ed25519SecretKey,
      signerPk: identity.ed25519PublicKey,
      presetKeyImage: keyImage,
    );

    final msg = proto.PollVoteRevokeMsg()
      ..pollId = hexToBytes(poll.pollId)
      ..keyImage = keyImage
      ..ringSignature = signed.signature
      ..revokedAt = Int64(DateTime.now().millisecondsSinceEpoch);
    for (final pk in ring) {
      msg.ringMembers.add(pk);
    }

    await _fanoutToEntity(poll.groupId, proto.MessageTypeV3.MTV3_POLL_REVOKE, msg.writeToBuffer());
  }

  Future<void> _sendPollUpdate(Poll poll, proto.PollAction action,
      {List<PollOption>? addedOptions,
      List<int>? removedOptions,
      int? newDeadline}) async {
    final msg = proto.PollUpdateMsg()
      ..pollId = hexToBytes(poll.pollId)
      ..action = action
      ..updatedBy = identity.userId
      ..updatedAt = Int64(DateTime.now().millisecondsSinceEpoch);
    if (addedOptions != null) {
      for (final o in addedOptions) {
        msg.addedOptions.add(proto.PollOptionMsg()
          ..optionId = o.optionId
          ..label = o.label
          ..dateStart = Int64(o.dateStart ?? 0)
          ..dateEnd = Int64(o.dateEnd ?? 0));
      }
    }
    if (removedOptions != null) msg.removedOptions.addAll(removedOptions);
    if (newDeadline != null) msg.newDeadline = Int64(newDeadline);

    await _fanoutToEntity(poll.groupId, proto.MessageTypeV3.MTV3_POLL_UPDATE, msg.writeToBuffer());
  }

  Future<void> _broadcastPollSnapshot(Poll poll) async {
    final tally = pollManager.computeTally(poll.pollId);
    final msg = proto.PollSnapshotMsg()
      ..pollId = hexToBytes(poll.pollId)
      ..totalVotes = tally.totalVotes
      ..scaleAverage = tally.scaleAverage
      ..scaleCount = tally.scaleCount
      ..closed = poll.closed
      ..snapshotAt = Int64(DateTime.now().millisecondsSinceEpoch);
    if (poll.pollType == PollType.datePoll) {
      for (final entry in tally.dateCounts.entries) {
        msg.optionCounts.add(proto.OptionCountMsg()
          ..optionId = entry.key
          ..yesCount = entry.value[DateAvailability.yes] ?? 0
          ..maybeCount = entry.value[DateAvailability.maybe] ?? 0
          ..noCount = entry.value[DateAvailability.no] ?? 0);
      }
    } else {
      for (final entry in tally.optionCounts.entries) {
        msg.optionCounts.add(proto.OptionCountMsg()
          ..optionId = entry.key
          ..count = entry.value);
      }
    }
    await _fanoutToEntity(poll.groupId, proto.MessageTypeV3.MTV3_POLL_SNAPSHOT, msg.writeToBuffer());
  }

  void _startPollDeadlineTimer() {
    _pollDeadlineTimer?.cancel();
    _pollDeadlineTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final closed = pollManager.enforceDeadlines();
      for (final id in closed) {
        final poll = pollManager.polls[id];
        if (poll != null && poll.createdByHex == identity.userIdHex) {
          _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_CLOSE);
          if (_channels.containsKey(poll.groupId)) {
            _broadcastPollSnapshot(poll);
          }
        }
        onPollStateChanged?.call(id);
      }
      if (closed.isNotEmpty) onStateChanged?.call();
    });
  }

  // ── Interface implementation ────────────────────────────────────────

  @override
  Future<String> createPoll({
    required String question,
    String description = '',
    required PollType pollType,
    required List<PollOption> options,
    required PollSettings settings,
    required String groupIdHex,
  }) async {
    if (_reducedMode) {
      _log.warn('createPoll blocked: reducedMode active');
      return '';
    }
    if (_pollRecipients(groupIdHex) == null) {
      throw ArgumentError('Unknown group/channel $groupIdHex');
    }
    final normalisedOptions = <PollOption>[];
    for (var i = 0; i < options.length; i++) {
      normalisedOptions.add(PollOption(
        optionId: i,
        label: options[i].label,
        dateStart: options[i].dateStart,
        dateEnd: options[i].dateEnd,
      ));
    }
    final poll = Poll(
      pollId: PollManager.generateUuid(),
      identityId: identity.userIdHex,
      question: question,
      description: description,
      pollType: pollType,
      options: normalisedOptions,
      settings: settings,
      groupId: groupIdHex,
      createdByHex: identity.userIdHex,
      createdByName: displayName,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    pollManager.createPoll(poll);

    if (conversations.containsKey(groupIdHex)) {
      _addMessageToConversation(groupIdHex, UiMessage(
        id: bytesToHex(SodiumFFI().randomBytes(16)),
        conversationId: groupIdHex,
        senderNodeIdHex: identity.userIdHex,
        text: '$displayName: ${poll.question}',
        timestamp: DateTime.fromMillisecondsSinceEpoch(poll.createdAt),
        type: UiMessageType.pollCreate,
        status: MessageStatus.delivered,
        isOutgoing: true,
        pollId: poll.pollId,
      ), isGroup: _groups.containsKey(groupIdHex), isChannel: _channels.containsKey(groupIdHex));
    }

    await _sendPollCreate(poll);
    onPollCreated?.call(poll.pollId, groupIdHex, poll.question);
    onStateChanged?.call();
    return poll.pollId;
  }

  @override
  Future<bool> submitPollVote({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  }) async {
    if (_reducedMode) {
      _log.warn('submitPollVote blocked: reducedMode active');
      return false;
    }
    final poll = pollManager.polls[pollId];
    if (poll == null || poll.closed) return false;
    if (poll.settings.anonymous) {
      throw StateError('Use submitPollVoteAnonymous for anonymous polls');
    }
    final vote = PollVoteRecord(
      pollId: pollId,
      voterIdHex: identity.userIdHex,
      voterName: displayName,
      selectedOptions: selectedOptions ?? [],
      dateResponses: dateResponses ?? {},
      scaleValue: scaleValue ?? 0,
      freeText: freeText ?? '',
      votedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (!pollManager.recordVote(vote)) return false;
    await _sendPollVoteNonAnonymous(poll, vote);

    if (_channels.containsKey(poll.groupId) &&
        poll.createdByHex == identity.userIdHex) {
      await _broadcastPollSnapshot(poll);
    }
    onPollTallyUpdated?.call(pollId);
    onStateChanged?.call();
    return true;
  }

  @override
  Future<bool> submitPollVoteAnonymous({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  }) async {
    if (_reducedMode) {
      _log.warn('submitPollVoteAnonymous blocked: reducedMode active');
      return false;
    }
    final poll = pollManager.polls[pollId];
    if (poll == null || poll.closed) return false;
    if (!poll.settings.anonymous) {
      throw StateError('Poll is not configured as anonymous');
    }

    final vote = PollVoteRecord(
      pollId: pollId,
      voterIdHex: '', // Set after ring signing from key image
      voterName: '',
      selectedOptions: selectedOptions ?? [],
      dateResponses: dateResponses ?? {},
      scaleValue: scaleValue ?? 0,
      freeText: freeText ?? '',
      votedAt: DateTime.now().millisecondsSinceEpoch,
      anonymous: true,
    );

    // Derive key image locally so we can record our own vote without waiting
    // for network echo — keeps UI responsive and prevents accidental double-send.
    final ring = _ringForEntity(poll.groupId);
    final keyImage = LinkableRingSignature.deriveKeyImage(
      signerSk: identity.ed25519SecretKey,
      signerPk: identity.ed25519PublicKey,
      context: hexToBytes(pollId),
    );
    final keyImageHex = bytesToHex(keyImage);

    final seen = _anonymousKeyImages.putIfAbsent(pollId, () => {});
    if (seen.contains(keyImageHex)) {
      // Re-vote on an anonymous poll requires revoke first (§24.4.5).
      if (!poll.settings.allowVoteChange) return false;
      await _sendPollVoteRevoke(poll, keyImage);
      pollManager.revokeAnonymousVote(pollId, keyImageHex);
      seen.remove(keyImageHex);
    }

    pollManager.recordVote(PollVoteRecord(
      pollId: pollId,
      voterIdHex: keyImageHex,
      voterName: '',
      selectedOptions: vote.selectedOptions,
      dateResponses: vote.dateResponses,
      scaleValue: vote.scaleValue,
      freeText: vote.freeText,
      votedAt: vote.votedAt,
      anonymous: true,
    ));
    seen.add(keyImageHex);

    // _sendPollVoteAnonymous uses an internally-derived ring that must match
    // the canonical sort used here, so both sides produce the same key image.
    ring.length; // ensure variable escapes so analyzer does not complain
    await _sendPollVoteAnonymous(poll, vote);
    onPollTallyUpdated?.call(pollId);
    onStateChanged?.call();
    return true;
  }

  @override
  Future<bool> revokePollVoteAnonymous(String pollId) async {
    if (_reducedMode) {
      _log.warn('revokePollVoteAnonymous blocked: reducedMode active');
      return false;
    }
    final poll = pollManager.polls[pollId];
    if (poll == null || !poll.settings.anonymous) return false;
    final keyImage = LinkableRingSignature.deriveKeyImage(
      signerSk: identity.ed25519SecretKey,
      signerPk: identity.ed25519PublicKey,
      context: hexToBytes(pollId),
    );
    final keyImageHex = bytesToHex(keyImage);
    if (!(_anonymousKeyImages[pollId]?.contains(keyImageHex) ?? false)) {
      return false;
    }
    await _sendPollVoteRevoke(poll, keyImage);
    pollManager.revokeAnonymousVote(pollId, keyImageHex);
    _anonymousKeyImages[pollId]?.remove(keyImageHex);
    onPollTallyUpdated?.call(pollId);
    onStateChanged?.call();
    return true;
  }

  @override
  Future<bool> updatePoll(String pollId, {
    bool? close,
    bool? reopen,
    List<PollOption>? addOptions,
    List<int>? removeOptions,
    int? newDeadline,
    bool delete = false,
  }) async {
    if (_reducedMode) {
      _log.warn('updatePoll blocked: reducedMode active');
      return false;
    }
    final poll = pollManager.polls[pollId];
    if (poll == null) return false;
    // Only creator or group/channel owner/admin may mutate.
    final group = _groups[poll.groupId];
    final channel = _channels[poll.groupId];
    final role = group?.members[identity.userIdHex]?.role ??
        channel?.members[identity.userIdHex]?.role;
    final isCreator = poll.createdByHex == identity.userIdHex;
    final isAdmin = role == 'owner' || role == 'admin';
    if (!isCreator && !isAdmin) return false;

    if (delete) {
      pollManager.deletePoll(pollId);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_DELETE);
      // System channels: remove the UiMessage container entirely
      if (SystemChannels.isSystemChannel(poll.groupId)) {
        final conv = conversations[poll.groupId];
        conv?.messages.removeWhere((m) => m.pollId == pollId);
      }
      onPollStateChanged?.call(pollId);
      onStateChanged?.call();
      _saveConversations();
      return true;
    }
    if (close == true) {
      pollManager.closePoll(pollId);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_CLOSE);
      if (_channels.containsKey(poll.groupId)) {
        await _broadcastPollSnapshot(poll);
      }
    }
    if (reopen == true) {
      pollManager.reopenPoll(pollId);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_REOPEN);
    }
    if (addOptions != null && addOptions.isNotEmpty) {
      pollManager.addOptions(pollId, addOptions);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_ADD_OPTIONS,
          addedOptions: addOptions);
    }
    if (removeOptions != null && removeOptions.isNotEmpty) {
      pollManager.removeOptions(pollId, removeOptions);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_REMOVE_OPTIONS,
          removedOptions: removeOptions);
    }
    if (newDeadline != null) {
      pollManager.extendDeadline(pollId, newDeadline);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_EXTEND_DEADLINE,
          newDeadline: newDeadline);
    }
    onPollStateChanged?.call(pollId);
    onStateChanged?.call();
    return true;
  }

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

      // Verify signature with old ed25519 key
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
        final valid = SodiumFFI().verifyEd25519(
          dataToVerify,
          Uint8List.fromList(rb.signature),
          contact.ed25519Pk!,
        );
        if (!valid) {
          _log.warn('RESTORE_BROADCAST signature invalid from ${oldNodeIdHex.substring(0, 8)}');
          return;
        }
      }

      _log.info('Valid RESTORE_BROADCAST from ${contact.displayName} (old: ${oldNodeIdHex.substring(0, 8)}, new: ${newNodeIdHex.substring(0, 8)})');

      // Update contact with new keys and node ID
      _contacts.remove(oldNodeIdHex);
      contact.nodeId = Uint8List.fromList(rb.newNodeId);
      contact.ed25519Pk = Uint8List.fromList(rb.newEd25519Pk);
      contact.x25519Pk = Uint8List.fromList(rb.newX25519Pk);
      contact.mlKemPk = Uint8List.fromList(rb.newMlKemPk);
      contact.mlDsaPk = Uint8List.fromList(rb.newMlDsaPk);
      if (rb.displayName.isNotEmpty) contact.displayName = rb.displayName;
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

    // Sign with OLD key to prove ownership
    final dataToSign = rb.writeToBuffer();
    rb.signature = SodiumFFI().signEd25519(dataToSign, oldEd25519Sk);

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
    _stopAudioMixer();
    _stopGroupVideo();
    groupCallManager.leaveGroupCall();
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
    _startupPollingTimer?.cancel();
    _startupPollingTimer = null;
    _channelIndexGossipTimer?.cancel();
    _channelIndexGossipTimer = null;
    _moderationTimer?.cancel();
    _moderationTimer = null;
    _systemChannelEvictionTimer?.cancel();
    _systemChannelEvictionTimer = null;
    _updateCheckTimer?.cancel();
    _updateCheckTimer = null;
    _natWizardTrigger?.stop();
    _natWizardTrigger = null;
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
    Timer(const Duration(seconds: 8), () {
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
          onUpdateAvailable?.call(manifest, false);
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

  /// Store the current identity registry in the DHT.
  /// Called after identity creation/deletion to keep the registry up-to-date.
  void storeRegistryInDht(Uint8List masterSeed, List<({int? hdIndex, String name})> identities, int nextIndex) {
    final registry = IdentityDhtRegistry(masterSeed: masterSeed, profileDir: profileDir);
    final entries = IdentityDhtRegistry.buildIdentityEntries(identities);

    registry.storeInDht(entries, nextIndex, (mailboxId, fragmentIndex, fragmentData) {
      // Store via FRAGMENT_STORE to closest DHT peers.
      // V3 (Architecture §23.3): FRAGMENT_STORE is an infrastructure
      // message — route via DV cascade as InfrastructureFrame.
      final peers = node.routingTable.findClosestPeers(mailboxId, count: 10);
      for (final peer in peers) {
        final store = proto.FragmentStore()
          ..mailboxId = mailboxId
          ..fragmentIndex = fragmentIndex
          ..fragmentData = fragmentData
          ..messageId = mailboxId // Use registry key as message ID
          ..totalFragments = 10
          ..originalSize = fragmentData.length;
        node.sendInfraTo(
          messageType: proto.MessageTypeV3.MTV3_FRAGMENT_STORE,
          innerPayload: Uint8List.fromList(store.writeToBuffer()),
          recipientDeviceId: Uint8List.fromList(peer.nodeId),
        );
      }
    });
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
    if (contact.deviceNodeIds.isNotEmpty) {
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
      final kemBytes = V3FrameCodec.buildAndEncryptInner(
        inner: inner,
        senderUserEd25519Sk: identity.ed25519SecretKey,
        senderUserMlDsaSk: identity.mlDsaSecretKey,
        recipientUserX25519Pk: contact.x25519Pk!,
        recipientUserMlKemPk: contact.mlKemPk!,
      );
      final outer = V3FrameCodec.buildOuter(
        nextHopDeviceId: recipientUserId,
        senderDeviceId: node.primaryIdentity.deviceNodeId,
        deviceKeys: node.deviceKeyPair,
        innerPayload: kemBytes,
        payloadType: proto.PayloadTypeV3.PAYLOAD_APPLICATION_FRAME,
        applicationFlavor: true,
        skipPoW: true,
      );
      final canonicalBytes = node.serializePacketForOfflineDelivery(outer);
      final fragmentBundleId =
          SodiumFFI().sha256(canonicalBytes).sublist(0, 16);
      await _distributeErasureFragments(
        packetBytes: canonicalBytes,
        messageId: fragmentBundleId,
        recipientUserEd25519Pk: contact.ed25519Pk,
        recipientUserNodeId: recipientUserId,
      );
      _storeSafOnMutualPeers(
        recipientUserId: recipientUserId,
        wrappedEnvelope: canonicalBytes,
        storeId: SodiumFFI().randomBytes(16),
      );
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

        final kemBytes = V3FrameCodec.buildAndEncryptInner(
          inner: inner,
          senderUserEd25519Sk: identity.ed25519SecretKey,
          senderUserMlDsaSk: identity.mlDsaSecretKey,
          recipientUserX25519Pk: contact.x25519Pk!,
          recipientUserMlKemPk: contact.mlKemPk!,
        );

        // Outer is application-flavor (hybrid Device-Sig). PoW skipped for now
        // and re-evaluated in Welle 3 once the LAN-detection helper is wired
        // through the codec — Architecture §2.4 sender step 10 allows the
        // skip on infrastructure / LAN destinations.
        final outer = V3FrameCodec.buildOuter(
          nextHopDeviceId: deviceId,
          senderDeviceId: myDeviceNodeId,
          deviceKeys: node.deviceKeyPair,
          innerPayload: kemBytes,
          payloadType: proto.PayloadTypeV3.PAYLOAD_APPLICATION_FRAME,
          applicationFlavor: true,
          skipPoW: true,
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
    //
    // V3.0 has no local re-send park (`onRetryNeeded` consumer in cleona_node
    // forwards to `onMessageRetryExhausted`, which the offline cascade —
    // S&F + Reed-Solomon — picks up). So we deliberately pass empty
    // `usedAddresses` and null `serializedPacket`: the AckTracker only
    // does timeout-bookkeeping + DV-bridge for V3 sends, not local retry.
    // Address-success crediting still happens in the inbound path
    // (`_onEnvelopeReceived → _touchPeer`) — see ack_tracker.dart:178.
    if (dispatched > 0 &&
        AckTracker.isAckWorthyV3(messageType) &&
        !_constantTimeEq(recipientUserId, identity.userId)) {
      final messageIdHex = bytesToHex(effectiveMessageId);
      final recipientHex = bytesToHex(recipientUserId);
      final baseRtt = node.dhtRpc.getRtt(recipientUserId);
      final timeout = AckTracker.computeTimeout(baseRtt);
      // Fire-and-forget — completer resolves on receipt or timeout, but
      // the resolution path is already wired through the tracker callbacks
      // (onAckReceived / onAckTimeout / onRouteDown).
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
      _storeSafOnMutualPeers(
        recipientUserId: recipientUserId,
        wrappedEnvelope: canonicalBytes,
        storeId: SodiumFFI().randomBytes(16),
      );
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
  ///
  // ── §8.1.1 rev3 step 1b: Deferred Key Exchange handlers ──────────

  /// Handle incoming DEVICE_KEM_REQUEST — respond with DEVICE_KEM_OFFER
  /// containing our Device-KEM-PK pair, signed with our user Ed25519 SK.
  void handleIncomingDeviceKemRequest(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
  ) {
    try {
      final req = proto.DeviceKemRequestV3.fromBuffer(frame.payload);
      final targetUserHex = bytesToHex(Uint8List.fromList(req.targetUserId));
      final targetDevHex = bytesToHex(Uint8List.fromList(req.targetDeviceId));
      if (targetUserHex != identity.userIdHex) return;
      if (targetDevHex != identity.deviceNodeIdHex) return;

      final dxk = node.deviceKem.x25519PublicKey;
      final dmk = node.deviceKem.mlKemPublicKey;
      final nonce = Uint8List.fromList(req.nonce);

      // Sign (dxk + dmk + nonce) with user Ed25519 SK.
      final sigPayload = Uint8List(dxk.length + dmk.length + nonce.length);
      sigPayload.setRange(0, dxk.length, dxk);
      sigPayload.setRange(dxk.length, dxk.length + dmk.length, dmk);
      sigPayload.setRange(dxk.length + dmk.length, sigPayload.length, nonce);
      final sig = SodiumFFI().signEd25519(sigPayload, identity.ed25519SecretKey);

      final offer = proto.DeviceKemOfferV3()
        ..deviceX25519Pk = dxk
        ..deviceMlKemPk = dmk
        ..nonce = nonce
        ..userEd25519Sig = sig
        ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch);
      final offerBytes = Uint8List.fromList(offer.writeToBuffer());

      unawaited(node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_DEVICE_KEM_OFFER,
        innerPayload: offerBytes,
        recipientDeviceId: senderDeviceId,
      ));
      _log.info('DEVICE_KEM_REQUEST from '
          '${bytesToHex(senderDeviceId).substring(0, 8)} — '
          'replied with DEVICE_KEM_OFFER');
    } catch (e) {
      _log.warn('DEVICE_KEM_REQUEST parse/handle error: $e');
    }
  }

  /// Handle incoming DEVICE_KEM_OFFER — verify signature against the ep
  /// trust-anchor and resolve the pending completer.
  void handleIncomingDeviceKemOffer(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
  ) {
    try {
      final offer = proto.DeviceKemOfferV3.fromBuffer(frame.payload);
      final senderDevHex = bytesToHex(senderDeviceId);
      final completer = _pendingKemOfferCompleters[senderDevHex];
      if (completer == null || completer.isCompleted) {
        _log.debug('DEVICE_KEM_OFFER from $senderDevHex — '
            'no pending completer (stale or duplicate)');
        return;
      }

      final dxk = Uint8List.fromList(offer.deviceX25519Pk);
      final dmk = Uint8List.fromList(offer.deviceMlKemPk);
      final nonce = Uint8List.fromList(offer.nonce);
      final sig = Uint8List.fromList(offer.userEd25519Sig);

      // Find the ep trust-anchor for this device from the pending contact.
      Uint8List? epPk;
      for (final c in _contacts.values) {
        if (c.seedDeviceIdHex == senderDevHex && c.seedEpB64 != null) {
          epPk = base64Decode(c.seedEpB64!);
          break;
        }
      }
      if (epPk == null) {
        _log.warn('DEVICE_KEM_OFFER from $senderDevHex — '
            'no ep trust-anchor found, dropping');
        return;
      }

      // Verify: sig over (dxk + dmk + nonce) with the ep public key.
      final sigPayload = Uint8List(dxk.length + dmk.length + nonce.length);
      sigPayload.setRange(0, dxk.length, dxk);
      sigPayload.setRange(dxk.length, dxk.length + dmk.length, dmk);
      sigPayload.setRange(dxk.length + dmk.length, sigPayload.length, nonce);
      final valid = SodiumFFI().verifyEd25519(sigPayload, sig, epPk);
      if (!valid) {
        _log.warn('DEVICE_KEM_OFFER from $senderDevHex — '
            'Ed25519 signature verification FAILED against ep');
        return;
      }

      completer.complete((dxk: dxk, dmk: dmk));
      _log.info('DEVICE_KEM_OFFER from $senderDevHex — '
          'sig verified against ep, completer resolved');
    } catch (e) {
      _log.warn('DEVICE_KEM_OFFER parse/handle error: $e');
    }
  }

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

    final senderDeviceId = Uint8List.fromList(packet.senderDeviceId);
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
        _handleChannelBadBadgeReportV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_JURY_VOTE:
        _handleChannelJuryVoteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_MOD_DECISION:
        _handleChannelModDecisionV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_SUBSCRIBE_PROBE:
        _handleChannelSubscribeProbeV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_JOIN_REQUEST:
        _handleChannelJoinRequestV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CHANNEL_REPORT:
        _handleChannelReportV3(frame, senderDeviceId, snapshot);
        break;

      // Calls — Cluster C3
      case proto.MessageTypeV3.MTV3_CALL_INVITE:
        _handleCallInviteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_ANSWER:
        _handleCallAnswerV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_REJECT:
        _handleCallRejectV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_HANGUP:
        _handleCallHangupV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_ICE_CANDIDATE:
        _handleIceCandidateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_REJOIN:
        _handleCallRejoinV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_AUDIO:
        _handleCallAudioV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_VIDEO:
        _handleCallVideoV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_KEYFRAME_REQUEST:
        // Signal-only: ask our video encoder to force the next frame as a
        // keyframe. Empty payload by design.
        onKeyframeRequested?.call();
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_AUDIO:
        _handleCallGroupAudioV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_VIDEO:
        _handleCallGroupVideoV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_LEAVE:
        _handleCallGroupLeaveV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_GROUP_KEY_ROTATE:
        _handleCallGroupKeyRotateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_RTT_PING:
        _handleCallRttPingV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_RTT_PONG:
        _handleCallRttPongV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_TREE_UPDATE:
        _handleCallTreeUpdateV3(frame, senderDeviceId, snapshot);
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
        _handleCalendarInviteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALENDAR_RSVP:
        _handleCalendarRsvpV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALENDAR_UPDATE:
        _handleCalendarUpdateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALENDAR_DELETE:
        _handleCalendarDeleteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_FREE_BUSY_REQUEST:
        _handleFreeBusyRequestV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_FREE_BUSY_RESPONSE:
        _handleFreeBusyResponseV3(frame, senderDeviceId, snapshot);
        break;

      // Polls — Cluster C4
      case proto.MessageTypeV3.MTV3_POLL_CREATE:
        _handlePollCreateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_POLL_VOTE:
        _handlePollVoteV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS:
        _handlePollVoteAnonymousV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_POLL_UPDATE:
        _handlePollUpdateV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_POLL_SNAPSHOT:
        _handlePollSnapshotV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_POLL_REVOKE:
        _handlePollRevokeV3(frame, senderDeviceId, snapshot);
        break;

      // In-Call Collaboration (§25, geplant) — Cluster C3
      case proto.MessageTypeV3.MTV3_WHITEBOARD_STROKE:
        _handleWhiteboardStrokeV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_WHITEBOARD_PAGE:
        _handleWhiteboardPageV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_FILE_EXCHANGE:
        _handleFileExchangeV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CLIPBOARD_EXCHANGE:
        _handleClipboardExchangeV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_SCREEN_SHARE_FRAME:
        _handleScreenShareFrameV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_CALL_CHAT:
        _handleCallChatV3(frame, senderDeviceId, snapshot);
        break;
      case proto.MessageTypeV3.MTV3_REMOTE_CONTROL_INPUT:
        _handleRemoteControlInputV3(frame, senderDeviceId, snapshot);
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
        );
      }
    }
  }

  /// Emit a V3 DELIVERY_RECEIPT (Architecture §5.8 RUDP-Light) for a
  /// successfully received ApplicationFrame. Fire-and-forget — receipt
  /// loss is tolerable (sender's AckTracker times out and triggers its
  /// own retry / route-down logic).
  void _sendDeliveryReceiptV3({
    required Uint8List recipientUserId,
    required Uint8List messageId,
  }) {
    final receipt = proto.DeliveryReceipt()
      ..messageId = messageId
      ..deliveredAt = Int64(DateTime.now().millisecondsSinceEpoch);
    sendToUser(
      recipientUserId: recipientUserId,
      messageType: proto.MessageTypeV3.MTV3_DELIVERY_RECEIPT,
      payload: receipt.writeToBuffer(),
    );
  }

  // ──────────────────────────── V3 Handler Stubs ────────────────────────────
  // All handlers are intentional NO-OPs that log "TODO V3 handler not migrated".
  // Migration order: C1 (layer-replies) → C2 (messaging) → C3 (calls) → C4 (rest).
  // Per Architecture-Regel #1: explicit TODO is the spec, NOT silent fallback.

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

      final conv = conversations[conversationId];
      if (conv == null) return;
      for (final msg in conv.messages) {
        if (msg.id == msgIdHex &&
            msg.isOutgoing &&
            msg.status == MessageStatus.sent) {
          msg.status = MessageStatus.delivered;
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
      _addMessageToConversation(conversationId, msg,
          isGroup: isGroup, isChannel: isChannel);
      if (!_shouldSuppressNotification(
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
      final savePath = '${mediaDir.path}/$filename';
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
      );

      final isGroup = _groups.containsKey(conversationId);
      _addMessageToConversation(conversationId, msg, isGroup: isGroup);
      if (!_shouldSuppressNotification(
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
        _log.warn(
            'media-request-v3: no pending media for ${originalMsgId.length >= 8 ? originalMsgId.substring(0, 8) : originalMsgId}');
        return;
      }
      final file = File(filePath);
      if (!file.existsSync()) {
        _log.warn('media-request-v3: pending file vanished: $filePath');
        _pendingMediaSends.remove(originalMsgId);
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
      if (okComplete) _pendingMediaSends.remove(originalMsgId);
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
      final savePath = '${mediaDir.path}/$filename';
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
      final reaction = proto.EmojiReaction.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
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
      final tm = proto.TextMessageV3.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
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
      final editMsg = proto.MessageEdit.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
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

      // Edit-Window check (per-chat config).
      final chatEditWindowMs =
          conv.config.editWindowMs ?? _defaultEditWindowMs;
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
      final deleteMsg = proto.MessageDelete.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
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

  // C3 — Calls (Architecture §10 + §10.5; live-frame skip-verify §4.4.5/§10.4.5)
  //
  // Setup-class (INVITE/ANSWER/REJECT/HANGUP/REJOIN/GROUP_LEAVE/GROUP_KEY_ROTATE):
  //   inner User-Sig already verified upstream; frame.payload is the parsed
  //   sub-message bytes. Dispatch routes to 1:1 (callManager) vs group
  //   (groupCallManager) — for ANSWER/REJECT/HANGUP the rule is: if a
  //   group call is currently active, the frame belongs to it.
  //
  // Live-frame class (GROUP_AUDIO/VIDEO, RTT_PING/PONG, TREE_UPDATE):
  //   sender skipped ML-DSA + zstd per §4.4.5; AES-GCM under call_key carries
  //   pro-frame authenticity. Receive side just dispatches into relay/RTT/tree
  //   machinery.
  void _handleCallInviteV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    proto.CallInvite invite;
    try {
      invite = proto.CallInvite.fromBuffer(f.payload);
    } catch (e) {
      _log.warn('CALL_INVITE V3: payload parse failed: $e');
      return;
    }
    if (invite.isGroupCall) {
      groupCallManager.handleGroupCallInviteV3(f, sd, s);
    } else {
      callManager.handleCallInviteV3(f, sd, s);
    }
    notificationSound.startRingtone();
    notificationSound.vibrate(VibrationType.call);
  }

  void _handleCallAnswerV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    notificationSound.stopRingtone();
    notificationSound.stopRingback();
    notificationSound.playConnected();
    if (groupCallManager.currentGroupCall != null) {
      groupCallManager.handleGroupCallAnswerV3(f, sd, s);
    } else {
      callManager.handleCallAnswerV3(f, sd, s);
    }
  }

  void _handleCallRejectV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    notificationSound.stopRingtone();
    notificationSound.stopRingback();
    if (groupCallManager.currentGroupCall != null) {
      groupCallManager.handleGroupCallRejectV3(f, sd, s);
    } else {
      callManager.handleCallRejectV3(f, sd, s);
    }
  }

  void _handleCallHangupV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    notificationSound.stopRingtone();
    notificationSound.stopRingback();
    if (groupCallManager.currentGroupCall != null) {
      groupCallManager.handleGroupCallHangupV3(f, sd, s);
    } else {
      callManager.handleCallHangupV3(f, sd, s);
    }
  }

  // ICE_CANDIDATE: MTV3 enum exists, but no live handler or send-path.
  // Reserved for a future ICE/NAT-traversal wave.
  void _handleIceCandidateV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    _log.debug('ICE_CANDIDATE V3: not wired yet — drop');
  }

  void _handleCallRejoinV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    groupCallManager.handleCallRejoinV3(f, sd, s);
  }

  void _handleCallAudioV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    if (_audioEngine == null || !_audioEngine!.isRunning) return;
    callManager.currentCall?.framesReceived++;
    _audioEngine!.playFrame(Uint8List.fromList(f.payload));
  }

  void _handleCallVideoV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    final session = callManager.currentCall;
    if (session == null || session.state != CallState.inCall) return;
    session.videoFramesReceived++;
    onVideoFrameReceived?.call(Uint8List.fromList(f.payload));
  }

  void _handleCallGroupAudioV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    // Tree relay
    groupCallManager.handleGroupCallAudioV3(f, sd, s);
    // Local mix for playback
    if (_audioMixer != null) {
      try {
        final audio = proto.GroupCallAudio.fromBuffer(f.payload);
        final senderHex = bytesToHex(Uint8List.fromList(audio.senderNodeId));
        if (senderHex != identity.userIdHex) {
          _audioMixer!.addFrame(senderHex, Uint8List.fromList(audio.encryptedAudio));
        }
      } catch (e) {
        _log.debug('Group audio V3 parse failed: $e');
      }
    }
  }

  void _handleCallGroupVideoV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    // Tree relay
    groupCallManager.handleGroupCallVideoV3(f, sd, s);
    // Local decode for display
    if (_groupVideoReceiver != null) {
      try {
        final video = proto.GroupCallVideo.fromBuffer(f.payload);
        final senderHex = bytesToHex(Uint8List.fromList(video.senderNodeId));
        if (senderHex != identity.userIdHex) {
          _groupVideoReceiver!.addFrame(senderHex, Uint8List.fromList(video.videoFrameData));
        }
      } catch (e) {
        _log.debug('Group video V3 parse failed: $e');
      }
    }
  }

  void _handleCallGroupLeaveV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    groupCallManager.handleGroupCallLeaveV3(f, sd, s);
  }

  void _handleCallGroupKeyRotateV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    // V3-Pipeline liefert frame.payload bereits klartext.
    groupCallManager.handleGroupCallKeyRotateV3(f, sd, s);
  }

  void _handleCallRttPingV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    groupCallManager.handleCallRttPingV3(f, sd, s);
  }

  void _handleCallRttPongV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    groupCallManager.handleCallRttPongV3(f, sd, s);
  }

  void _handleCallTreeUpdateV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {
    groupCallManager.handleCallTreeUpdateV3(f, sd, s);
  }
  void _handleWhiteboardStrokeV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: WHITEBOARD_STROKE (C3)');
  void _handleWhiteboardPageV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: WHITEBOARD_PAGE (C3)');
  void _handleFileExchangeV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: FILE_EXCHANGE (C3)');
  void _handleClipboardExchangeV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: CLIPBOARD_EXCHANGE (C3)');
  void _handleScreenShareFrameV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: SCREEN_SHARE_FRAME (C3)');
  void _handleCallChatV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: CALL_CHAT (C3)');
  void _handleRemoteControlInputV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: REMOTE_CONTROL_INPUT (C3)');

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
  void _handleContactRequestV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    _log.debug('_handleContactRequestV3 from device ${bytesToHex(senderDeviceId).substring(0, 8)}');
    _log.info('_handleContactRequestV3 ENTER for ${identity.userIdHex.substring(0, 8)}');
    try {
      final cr = proto.ContactRequestMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));

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
        existing.displayName = cr.displayName;
        existing.ed25519Pk = Uint8List.fromList(cr.ed25519PublicKey);
        existing.x25519Pk = Uint8List.fromList(cr.x25519PublicKey);
        existing.mlKemPk = Uint8List.fromList(cr.mlKemPublicKey);
        existing.mlDsaPk = Uint8List.fromList(cr.mlDsaPublicKey);
        if (cr.profilePicture.isNotEmpty) {
          existing.profilePictureBase64 = base64Encode(cr.profilePicture);
        }
        // Refresh device ID so sendToUser → deviceNodeIds fallback stays warm.
        if (!existing.deviceNodeIds.contains(bytesToHex(senderDeviceId))) {
          existing.deviceNodeIds.add(bytesToHex(senderDeviceId));
        }
        _saveContacts();
        _log.info('Re-contact from accepted ${cr.displayName} — sending acceptance response');
        // Re-send acceptance so the remote side knows we still have them.
        // Not awaited intentionally: sendEnvelope is ACK-tracked by AckTracker,
        // and the CR retry timer handles failures — no need to block here.
        acceptContactRequest(senderHex);
        return;
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
        existing.ed25519Pk = Uint8List.fromList(resp.ed25519PublicKey);
        existing.x25519Pk = Uint8List.fromList(resp.x25519PublicKey);
        existing.mlKemPk = Uint8List.fromList(resp.mlKemPublicKey);
        existing.mlDsaPk = Uint8List.fromList(resp.mlDsaPublicKey);
        existing.displayName = resp.displayName;
        if (picBase64 != null) existing.profilePictureBase64 = picBase64;
        // Store sender's device ID so sendToUser can reach them immediately
        // even before the DHT auth-manifest is warm (§2.6.2 bootstrapping).
        existing.deviceNodeIds.add(bytesToHex(senderDeviceId));
        _saveContacts();

        if (wasAlreadyAccepted) {
          _log.debug('CR-Response retry from ${senderHex.substring(0, 8)} — keys refreshed, no system msg');
          onStateChanged?.call();
          return;
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

    final group = GroupInfo(
      groupIdHex: groupIdHex,
      name: invite.groupName,
      description: invite.groupDescription,
      pictureBase64: invite.groupPicture.isNotEmpty ? base64Encode(invite.groupPicture) : null,
      ownerNodeIdHex: ownerHex,
      members: members,
    );

    final isUpdate = _groups.containsKey(groupIdHex);
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
  void _handleGroupKeyUpdateV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: GROUP_KEY_UPDATE (C4)');
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

    // Verify sender is owner or admin
    final senderMember = channel.members[senderHex];
    if (senderMember == null || (senderMember.role != 'owner' && senderMember.role != 'admin')) {
      _log.warn('CHANNEL_POST from unauthorized sender $senderHex');
      return;
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
    );

    final isUpdate = _channels.containsKey(channelIdHex);
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
  void _handleChannelBadBadgeReportV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: CHANNEL_BAD_BADGE_REPORT (C4)');

  /// V3-direct handler for MTV3_CHANNEL_JOIN_REQUEST (Wave 2B.3, §10.2).
  /// Owner-bound AppFrame; payload is the `ChannelJoinRequest` proto
  /// already decrypted+authenticated by the V3 receive pipeline.
  void _handleChannelJoinRequestV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    _handleChannelJoinRequest(
      Uint8List.fromList(frame.payload),
      Uint8List.fromList(frame.senderUserId),
    );
  }

  /// V3-direct handler for MTV3_CHANNEL_REPORT (Wave 2B.3, §10.2). No
  /// active V3 sender today (reportChannel mutates local state only) —
  /// handler in place so future moderator-fanout can land without a
  /// silent drop. Payload is the `ChannelReportMsg` proto already
  /// decrypted+authenticated by the V3 receive pipeline.
  void _handleChannelReportV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    _handleIncomingChannelReport(
      Uint8List.fromList(frame.payload),
      Uint8List.fromList(frame.senderUserId),
    );
  }

  /// V3-direct InfraFrame handler for MTV3_CHANNEL_INDEX_EXCHANGE (Wave
  /// 2B.3, §10.2). Gossip-style channel-index distribution to non-contact
  /// peers; payload is untrusted by design — handler just merges entries
  /// into `_channelIndex`. No KEM-decap and no inner User-Sig (public
  /// gossip on the InfraFrame path); the outer Device-Sig is the only
  /// authenticator and is verified upstream by the V3 receive pipeline.
  void handleIncomingChannelIndexExchangeInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) {
    _handleChannelIndexExchange(Uint8List.fromList(frame.payload));
  }
  /// V3-direct dispatcher for MTV3_CHANNEL_JURY_VOTE. The wire-type is
  /// overloaded by the V3 sender (cleona_service Z.~5023) — it carries
  /// either a `JuryRequestMsg` (initiator → juror, "you've been selected")
  /// or a `JuryVoteMsg` (juror → initiator, "here's my vote"). Both
  /// proto-bodies share the leading `juryId` field, so we early-parse as
  /// `JuryVoteMsg` and discriminate by initiator-side state: if we hold an
  /// `_activeSessions[juryId]` entry, this incoming frame is a vote-back
  /// for that session; otherwise it's a fresh request to participate.
  void _handleChannelJuryVoteV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final payload = Uint8List.fromList(frame.payload);
      final senderUserId = Uint8List.fromList(frame.senderUserId);
      // Try parsing as JuryVoteMsg first (vote-back from juror to initiator).
      // If we hold an active session for this juryId, it's a vote; otherwise
      // parse as JuryRequestMsg (initiator → juror selection).
      try {
        final voteCandidate = proto.JuryVoteMsg.fromBuffer(payload);
        final juryIdHex = bytesToHex(Uint8List.fromList(voteCandidate.juryId));
        if (_activeSessions.containsKey(juryIdHex)) {
          _handleIncomingJuryVote(payload, senderUserId);
          return;
        }
      } catch (_) {
        // Not a valid JuryVoteMsg — fall through to JuryRequestMsg parse
      }
      _handleIncomingJuryRequest(payload, senderUserId);
    } catch (e) {
      _log.warn('_handleChannelJuryVoteV3: dispatch fail: $e '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))})');
    }
  }

  /// V3-direct handler for MTV3_CHANNEL_MOD_DECISION (jury verdict
  /// broadcast). Payload is the `JuryResultMsg` proto already
  /// decrypted+authenticated by the V3 receive pipeline. The handler is
  /// sender-agnostic (only updates local state from the result tally), so
  /// no senderUserId is forwarded.
  void _handleChannelModDecisionV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    _handleIncomingJuryResult(Uint8List.fromList(frame.payload));
  }
  void _handleChannelSubscribeProbeV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: CHANNEL_SUBSCRIBE_PROBE (C4)');
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
  void _handleChatConfigResponseV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: CHAT_CONFIG_RESPONSE (C4)');
  // Wave 2B.3: ROUTE_UPDATE, REACHABILITY_*, RELAY_*, HOLE_PUNCH_*
  // dead-stub declarations removed — all dispatched in cleona_node.dart
  // (`_dispatchInfrastructureFrameLocal`, see Wave 2B.3 section). RELAY_*
  // remains on the KEM-path with §5.5 logic (out of Wave 2B.3 scope).
  void _handleIdentityAuthPublishV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: IDENTITY_AUTH_PUBLISH (C4)');
  void _handleIdentityAuthRetrieveV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: IDENTITY_AUTH_RETRIEVE (C4)');
  void _handleIdentityAuthResponseV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: IDENTITY_AUTH_RESPONSE (C4)');
  void _handleIdentityLivePublishV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: IDENTITY_LIVE_PUBLISH (C4)');
  void _handleIdentityLiveRetrieveV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: IDENTITY_LIVE_RETRIEVE (C4)');
  void _handleIdentityLiveResponseV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: IDENTITY_LIVE_RESPONSE (C4)');
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
        default:
          _log.debug('Unhandled TWIN_SYNC type: ${sync.syncType}');
      }
      _saveDevices(); // Persist dedup IDs
    } catch (e) {
      _log.error('TWIN_SYNC processing failed: $e');
    }
  }
  void _handleDevicePairRequestV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: DEVICE_PAIR_REQUEST (C4)');
  void _handleDevicePairApproveV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) =>
      _log.warn('TODO V3 handler not migrated: DEVICE_PAIR_APPROVE (C4)');
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
  /// Handle incoming CALENDAR_INVITE — V3-direct.
  void _handleCalendarInviteV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final invite = proto.CalendarInviteMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final eventIdHex = bytesToHex(Uint8List.fromList(invite.eventId));

      // Create local calendar event from invite
      final event = CalendarEvent(
        eventId: eventIdHex,
        identityId: identity.userIdHex,
        title: invite.title,
        description: invite.description.isNotEmpty ? invite.description : null,
        location: invite.location.isNotEmpty ? invite.location : null,
        startTime: invite.startTime.toInt(),
        endTime: invite.endTime.toInt(),
        allDay: invite.allDay,
        timeZone: invite.timeZone.isNotEmpty ? invite.timeZone : 'UTC',
        recurrenceRule: invite.recurrenceRule.isNotEmpty ? invite.recurrenceRule : null,
        hasCall: invite.hasCall,
        groupId: invite.groupId.isNotEmpty ? bytesToHex(Uint8List.fromList(invite.groupId)) : null,
        category: EventCategory.values[invite.category.value.clamp(0, EventCategory.values.length - 1)],
        reminders: invite.reminders.map((r) => r.minutesBefore).toList(),
        createdBy: senderHex,
      );
      calendarManager.createEvent(event);

      // Add system message to group chat if it's a group event
      if (event.groupId != null && conversations.containsKey(event.groupId)) {
        final senderName = _contacts[senderHex]?.displayName ?? invite.createdByName;
        _addMessageToConversation(event.groupId!, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: event.groupId!,
          senderNodeIdHex: '',
          text: '$senderName hat einen Termin erstellt: ${event.title}',
          timestamp: DateTime.now(),
          type: UiMessageType.calendarInvite,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      _log.info('Received calendar invite: ${event.title} from ${senderHex.substring(0, 8)}');
      onCalendarInviteReceived?.call(senderHex, eventIdHex, event.title);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('_handleCalendarInviteV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  /// Handle incoming CALENDAR_RSVP from a group event participant — V3-direct.
  void _handleCalendarRsvpV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final rsvp = proto.CalendarRsvpMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final eventIdHex = bytesToHex(Uint8List.fromList(rsvp.eventId));

      final status = RsvpStatus.values[rsvp.response.value.clamp(0, RsvpStatus.values.length - 1)];
      calendarManager.setRsvp(eventIdHex, senderHex, status);

      // System message in group chat
      final event = calendarManager.events[eventIdHex];
      if (event?.groupId != null && conversations.containsKey(event!.groupId)) {
        final senderName = _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        final statusText = switch (status) {
          RsvpStatus.accepted => 'hat zugesagt',
          RsvpStatus.declined => 'hat abgesagt',
          RsvpStatus.tentative => 'hat vorläufig zugesagt',
          RsvpStatus.proposeNewTime => 'schlägt eine andere Zeit vor',
        };
        _addMessageToConversation(event.groupId!, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: event.groupId!,
          senderNodeIdHex: '',
          text: '$senderName $statusText',
          timestamp: DateTime.now(),
          type: UiMessageType.calendarRsvp,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      _log.info('RSVP for $eventIdHex from ${senderHex.substring(0, 8)}: $status');
      onCalendarRsvpReceived?.call(eventIdHex, senderHex, status);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('_handleCalendarRsvpV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  /// Handle incoming CALENDAR_UPDATE from the event creator — V3-direct.
  void _handleCalendarUpdateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final update = proto.CalendarUpdateMsg.fromBuffer(frame.payload);
      final eventIdHex = bytesToHex(Uint8List.fromList(update.eventId));

      final event = calendarManager.events[eventIdHex];
      if (event == null) {
        _log.debug('CALENDAR_UPDATE for unknown event $eventIdHex');
        return;
      }

      calendarManager.updateEvent(eventIdHex,
        title: update.title.isNotEmpty ? update.title : null,
        description: update.description.isNotEmpty ? update.description : null,
        location: update.location.isNotEmpty ? update.location : null,
        startTime: update.startTime.toInt() > 0 ? update.startTime.toInt() : null,
        endTime: update.endTime.toInt() > 0 ? update.endTime.toInt() : null,
        allDay: update.allDay,
        hasCall: update.hasCall,
        cancelled: update.cancelled,
        reminders: update.reminders.isNotEmpty
            ? update.reminders.map((r) => r.minutesBefore).toList()
            : null,
      );

      if (event.groupId != null && conversations.containsKey(event.groupId)) {
        final action = update.cancelled ? 'hat den Termin abgesagt' : 'hat den Termin geändert';
        final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
        final senderName = _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        _addMessageToConversation(event.groupId!, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: event.groupId!,
          senderNodeIdHex: '',
          text: '$senderName $action: ${event.title}',
          timestamp: DateTime.now(),
          type: UiMessageType.calendarUpdate,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      _log.info('Calendar event updated: $eventIdHex');
      onCalendarEventUpdated?.call(eventIdHex);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('_handleCalendarUpdateV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  /// Handle incoming CALENDAR_DELETE from the event creator — V3-direct.
  void _handleCalendarDeleteV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final del = proto.CalendarDeleteMsg.fromBuffer(frame.payload);
      final eventIdHex = bytesToHex(Uint8List.fromList(del.eventId));

      final event = calendarManager.events[eventIdHex];
      if (event != null && event.groupId != null) {
        final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
        final senderName = _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        _addMessageToConversation(event.groupId!, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: event.groupId!,
          senderNodeIdHex: '',
          text: '$senderName hat den Termin gelöscht: ${event.title}',
          timestamp: DateTime.now(),
          type: UiMessageType.calendarDelete,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      calendarManager.deleteEvent(eventIdHex);
      _log.info('Calendar event deleted: $eventIdHex');
      onCalendarEventUpdated?.call(eventIdHex);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('_handleCalendarDeleteV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  /// Handle incoming FREE_BUSY_REQUEST — auto-respond with filtered availability. V3-direct.
  Future<void> _handleFreeBusyRequestV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) async {
    try {
      final req = proto.FreeBusyRequestMsg.fromBuffer(frame.payload);
      final querierHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final requestIdBytes = Uint8List.fromList(req.requestId);

      // Only respond to accepted contacts (KEX Gate already filtered, but double-check)
      if (_contacts[querierHex]?.status != 'accepted') {
        _log.debug('FREE_BUSY_REQUEST from non-contact ${querierHex.substring(0, 8)}, ignoring');
        return;
      }

      // Generate response — cross-identity merge handled by IPC daemon layer
      final blocks = calendarManager.generateFreeBusyResponse(
        queryStart: req.queryStart.toInt(),
        queryEnd: req.queryEnd.toInt(),
        querierNodeIdHex: querierHex,
      );

      // Build response proto
      final response = proto.FreeBusyResponseMsg()
        ..requestId = requestIdBytes;
      for (final block in blocks) {
        response.blocks.add(proto.FreeBusyBlock()
          ..start = Int64(block.start)
          ..end = Int64(block.end)
          ..level = proto.FreeBusyLevel.valueOf(block.level.index) ?? proto.FreeBusyLevel.FB_TIME_ONLY
          ..title = block.title ?? ''
          ..location = block.location ?? '');
      }

      // Send response
      await _sendEncryptedPayload(
        Uint8List.fromList(frame.senderUserId),
        proto.MessageTypeV3.MTV3_FREE_BUSY_RESPONSE,
        response.writeToBuffer(),
      );

      _log.info('Sent FREE_BUSY_RESPONSE to ${querierHex.substring(0, 8)} '
          '(${blocks.length} blocks)');
    } catch (e) {
      _log.warn('_handleFreeBusyRequestV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  /// Handle incoming FREE_BUSY_RESPONSE — V3-direct.
  void _handleFreeBusyResponseV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final resp = proto.FreeBusyResponseMsg.fromBuffer(frame.payload);
      final requestIdHex = bytesToHex(Uint8List.fromList(resp.requestId));

      final blocks = <FreeBusyBlockResult>[];
      for (final b in resp.blocks) {
        blocks.add(FreeBusyBlockResult(
          start: b.start.toInt(),
          end: b.end.toInt(),
          level: FreeBusyLevel.values[b.level.value.clamp(0, FreeBusyLevel.values.length - 1)],
          title: b.title.isNotEmpty ? b.title : null,
          location: b.location.isNotEmpty ? b.location : null,
        ));
      }

      // Accumulate responses
      _freeBusyResults.putIfAbsent(requestIdHex, () => []).addAll(blocks);

      // Notify callback if registered
      final cb = _freeBusyCallbacks[requestIdHex];
      if (cb != null) {
        cb(_freeBusyResults[requestIdHex]!);
      }

      _log.info('Received FREE_BUSY_RESPONSE for $requestIdHex '
          '(${blocks.length} blocks)');
    } catch (e) {
      _log.warn('_handleFreeBusyResponseV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }
  void _handlePollCreateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollCreateMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final poll = _decodePollCreate(msg, senderHex: senderHex);

      // Must reference a known group or channel, otherwise silently drop.
      if (_pollRecipients(poll.groupId) == null) {
        _log.debug('POLL_CREATE for unknown entity ${poll.groupId.substring(0, 8)}, ignoring');
        return;
      }

      if (pollManager.polls.containsKey(poll.pollId)) {
        _log.debug('Duplicate POLL_CREATE ${poll.pollId.substring(0, 8)}');
        return;
      }
      pollManager.createPoll(poll);

      if (conversations.containsKey(poll.groupId)) {
        final name = _contacts[senderHex]?.displayName ?? msg.createdByName;
        _addMessageToConversation(poll.groupId, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: poll.groupId,
          senderNodeIdHex: senderHex,
          text: '$name: ${poll.question}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(poll.createdAt),
          type: UiMessageType.pollCreate,
          status: MessageStatus.delivered,
          isOutgoing: false,
          pollId: poll.pollId,
        ), isGroup: _groups.containsKey(poll.groupId), isChannel: _channels.containsKey(poll.groupId));
      }

      onPollCreated?.call(poll.pollId, poll.groupId, poll.question);
      onStateChanged?.call();
      _log.info('Received POLL_CREATE ${poll.pollId.substring(0, 8)} from ${senderHex.substring(0, 8)}');
    } catch (e) {
      _log.warn('_handlePollCreateV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void _handlePollVoteV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollVoteMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) {
        _log.debug('POLL_VOTE for unknown poll $pollIdHex');
        return;
      }
      if (poll.settings.anonymous) {
        _log.warn('Ignoring non-anonymous POLL_VOTE on anonymous poll $pollIdHex');
        return;
      }
      final record = _decodePollVote(msg, voterIdHex: senderHex, anonymous: false);
      if (pollManager.recordVote(record)) {
        onPollTallyUpdated?.call(pollIdHex);
        onStateChanged?.call();

        // Channel mode: creator re-broadcasts a snapshot so subscribers see totals.
        if (_channels.containsKey(poll.groupId) &&
            poll.createdByHex == identity.userIdHex) {
          _broadcastPollSnapshot(poll);
        }
      }
    } catch (e) {
      _log.warn('_handlePollVoteV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void _handlePollVoteAnonymousV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollVoteAnonymousMsg.fromBuffer(frame.payload);
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) return;
      if (!poll.settings.anonymous) {
        _log.warn('POLL_VOTE_ANONYMOUS for non-anonymous poll, dropping');
        return;
      }

      final ring = msg.ringMembers.map((e) => Uint8List.fromList(e)).toList();
      final keyImage = Uint8List.fromList(msg.keyImage);
      final keyImageHex = bytesToHex(keyImage);
      final payload = Uint8List.fromList(msg.encryptedChoice);

      // Context domain-separates polls so the same voter can participate in
      // multiple anonymous polls without linkage across them.
      final context = hexToBytes(pollIdHex);
      final valid = LinkableRingSignature.verify(
        message: payload,
        context: context,
        keyImage: keyImage,
        ringMembers: ring,
        signature: Uint8List.fromList(msg.ringSignature),
      );
      if (!valid) {
        _log.warn('Ring signature invalid for poll $pollIdHex, dropping');
        return;
      }

      final seen = _anonymousKeyImages.putIfAbsent(pollIdHex, () => {});
      if (seen.contains(keyImageHex) && !poll.settings.allowVoteChange) {
        _log.debug('Duplicate key image for $pollIdHex, dropping');
        return;
      }
      seen.add(keyImageHex);

      final voteMsg = proto.PollVoteMsg.fromBuffer(payload);
      final record = _decodePollVote(voteMsg, voterIdHex: keyImageHex, anonymous: true);
      // Override voter identifiers so UI never surfaces identity.
      record.voterName = '';
      pollManager.recordVote(PollVoteRecord(
        pollId: record.pollId,
        voterIdHex: keyImageHex,
        voterName: '',
        selectedOptions: record.selectedOptions,
        dateResponses: record.dateResponses,
        scaleValue: record.scaleValue,
        freeText: record.freeText,
        votedAt: record.votedAt,
        anonymous: true,
      ));
      onPollTallyUpdated?.call(pollIdHex);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('_handlePollVoteAnonymousV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void _handlePollUpdateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollUpdateMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) return;

      // Permission: creator or group/channel admin/owner.
      final group = _groups[poll.groupId];
      final channel = _channels[poll.groupId];
      final role = group?.members[senderHex]?.role ?? channel?.members[senderHex]?.role;
      final isCreator = senderHex == poll.createdByHex;
      final isAdmin = role == 'owner' || role == 'admin';
      if (!isCreator && !isAdmin) {
        _log.warn('POLL_UPDATE from non-privileged ${senderHex.substring(0, 8)}, ignoring');
        return;
      }

      switch (msg.action) {
        case proto.PollAction.POLL_ACTION_CLOSE:
          pollManager.closePoll(pollIdHex);
          break;
        case proto.PollAction.POLL_ACTION_REOPEN:
          pollManager.reopenPoll(pollIdHex);
          break;
        case proto.PollAction.POLL_ACTION_ADD_OPTIONS:
          pollManager.addOptions(
              pollIdHex,
              msg.addedOptions
                  .map((o) => PollOption(
                        optionId: -1,
                        label: o.label,
                        dateStart: o.dateStart.toInt() == 0 ? null : o.dateStart.toInt(),
                        dateEnd: o.dateEnd.toInt() == 0 ? null : o.dateEnd.toInt(),
                      ))
                  .toList());
          break;
        case proto.PollAction.POLL_ACTION_REMOVE_OPTIONS:
          pollManager.removeOptions(pollIdHex, msg.removedOptions.toList());
          break;
        case proto.PollAction.POLL_ACTION_EXTEND_DEADLINE:
          pollManager.extendDeadline(pollIdHex, msg.newDeadline.toInt());
          break;
        case proto.PollAction.POLL_ACTION_DELETE:
          if (SystemChannels.isSystemChannel(poll.groupId)) {
            final conv = conversations[poll.groupId];
            conv?.messages.removeWhere((m) => m.pollId == pollIdHex);
          }
          pollManager.deletePoll(pollIdHex);
          _saveConversations();
          break;
        default:
          break;
      }
      onPollStateChanged?.call(pollIdHex);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('_handlePollUpdateV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void _handlePollSnapshotV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollSnapshotMsg.fromBuffer(frame.payload);
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) return;

      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      // Only the creator may publish authoritative snapshots.
      if (senderHex != poll.createdByHex) {
        _log.warn('POLL_SNAPSHOT from non-creator, ignoring');
        return;
      }

      final optionCounts = <int, int>{};
      final dateCounts = <int, Map<DateAvailability, int>>{};
      for (final oc in msg.optionCounts) {
        if (oc.yesCount + oc.maybeCount + oc.noCount > 0) {
          dateCounts[oc.optionId] = {
            DateAvailability.yes: oc.yesCount,
            DateAvailability.maybe: oc.maybeCount,
            DateAvailability.no: oc.noCount,
          };
        } else {
          optionCounts[oc.optionId] = oc.count;
        }
      }

      poll.cachedSnapshot = PollSnapshotCache(
        pollId: pollIdHex,
        totalVotes: msg.totalVotes,
        optionCounts: optionCounts,
        dateCounts: dateCounts,
        scaleAverage: msg.scaleAverage,
        scaleCount: msg.scaleCount,
        closed: msg.closed,
        snapshotAt: msg.snapshotAt.toInt(),
      );
      if (msg.closed && !poll.closed) poll.closed = true;
      poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
      pollManager.save();

      onPollTallyUpdated?.call(pollIdHex);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('_handlePollSnapshotV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void _handlePollRevokeV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollVoteRevokeMsg.fromBuffer(frame.payload);
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) return;

      final ring = msg.ringMembers.map((e) => Uint8List.fromList(e)).toList();
      final keyImage = Uint8List.fromList(msg.keyImage);
      final keyImageHex = bytesToHex(keyImage);
      final context = hexToBytes(pollIdHex);
      final marker = Uint8List.fromList('revoke'.codeUnits);
      final valid = LinkableRingSignature.verify(
        message: marker,
        context: context,
        keyImage: keyImage,
        ringMembers: ring,
        signature: Uint8List.fromList(msg.ringSignature),
      );
      if (!valid) {
        _log.warn('Revoke signature invalid for poll $pollIdHex, dropping');
        return;
      }
      if (pollManager.revokeAnonymousVote(pollIdHex, keyImageHex)) {
        _anonymousKeyImages[pollIdHex]?.remove(keyImageHex);
        onPollTallyUpdated?.call(pollIdHex);
        onStateChanged?.call();
      }
    } catch (e) {
      _log.warn('_handlePollRevokeV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
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

/// Internal state for an active jury session we initiated.
class _JurySession {
  final String juryId;
  final String reportId;
  final String channelIdHex;
  final ReportCategory category;
  final List<String> jurorNodeIds;
  final bool isPlausibilityJury;
  final DateTime createdAt;
  final Map<String, JuryVoteResult> votes = {};
  bool isComplete = false;

  _JurySession({
    required this.juryId,
    required this.reportId,
    required this.channelIdHex,
    required this.category,
    required this.jurorNodeIds,
    this.isPlausibilityJury = false,
    required this.createdAt,
  });
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
