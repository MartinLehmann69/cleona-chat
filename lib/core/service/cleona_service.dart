import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/pq_isolate.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/seed_phrase.dart';
import 'package:cleona/core/dht/channel_index.dart';
import 'package:cleona/core/dht/mailbox_store.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/compression.dart';
import 'package:cleona/core/network/ack_tracker.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/erasure/reed_solomon.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/network/network_stats.dart';
import 'package:cleona/core/calls/call_manager.dart';
import 'package:cleona/core/calls/audio_engine.dart';
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
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

// Re-export types so existing imports still work
export 'package:cleona/core/service/service_types.dart';

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
  final NetworkStatsCollector _statsCollector = NetworkStatsCollector();
  @override
  final NotificationSoundService notificationSound = NotificationSoundService();
  AudioEngine? _audioEngine;
  late GroupCallManager groupCallManager;
  AudioMixer? _audioMixer;
  dynamic _groupVideoEngine; // VideoEngine (loaded by GUI, avoids dart:ui in daemon)
  GroupVideoReceiver? _groupVideoReceiver;

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
  final Set<String> _processedMessageIds = {};

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

  // Guardian restore callback
  @override
  void Function(String ownerName, String triggeringGuardianName, String ownerNodeIdHex, String recoveryMailboxIdHex)? onGuardianRestoreRequest;

  // Update checking (Architecture Section 17.5.5)
  Timer? _updateCheckTimer;
  UpdateManifest? _latestManifest;
  /// Callback when a new version is available. UI should show banner/prompt.
  void Function(UpdateManifest manifest, bool isCurrent)? onUpdateAvailable;

  /// The current app version string (set by the GUI at startup).
  String currentAppVersion = '3.1.25';

  // Recovery state
  @override
  void Function(int phase, int contactsRestored, int messagesRestored)? onRestoreProgress;
  DateTime? _lastRestoreBroadcast;
  Timer? _restoreRetryTimer;
  Timer? _restorePollingTimer;
  int _restorePollCount = 0;

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

    // Init group call manager
    groupCallManager = GroupCallManager(
      identity: identity,
      node: node,
      contacts: _contacts,
      groups: _groups,
      profileDir: profileDir,
    );
    groupCallManager.sendEncrypted = _sendKemEncryptedForGroupCall;
    groupCallManager.sendDirect = _sendDirectForGroupCall;
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

    // Schedule mailbox poll (5 seconds after startup)
    Timer(const Duration(seconds: 5), _pollMailbox);

    // §26: TWIN_ANNOUNCE at startup so existing twins learn about this device.
    // 6 seconds lets the first peers come up first. Fire-and-forget; a no-op
    // when we have no known twins yet (first twin learns us when its own
    // announce arrives here — our handler echoes _sendTwinAnnounce back).
    Timer(const Duration(seconds: 6), _sendTwinAnnounce);

    // Schedule Store-and-Forward poll (8 seconds after startup)
    Timer(const Duration(seconds: 8), _pollStoredMessages);

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

    // Wire transport byte counters to stats collector
    node.transport.onBytesSent ??= (bytes) => _statsCollector.addBytesSent(bytes);
    node.transport.onBytesReceived ??= (bytes) => _statsCollector.addBytesReceived(bytes);

    // Wire relay byte counter — onRelayBytes fires for each relay forward/delivery
    node.onRelayBytes ??= (bytes) => _statsCollector.addRelayBytes(bytes);

    // RUDP Light: downgrade message status on ACK timeout.
    node.ackTracker.onAckTimeout = _handleAckTimeout;

    // Track end-to-end reachability per contact (used to stop CR-Response retry).
    // AckTracker callback provides the deviceNodeId of the recipient (Phase 2
    // routing). Contacts are keyed by userId with deviceNodeIds as aliases —
    // resolve deviceNodeId → userId so the retry loop (which iterates userId
    // keys) finds the ACK.
    node.ackTracker.onAckReceived = (_, recipientHex) {
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

    _statsCollector.markStarted();
    await notificationSound.init(identity.profileDir);

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
        uptimeSeconds: _statsCollector.uptime.inSeconds,
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
  Future<void> start({List<String> bootstrapPeers = const []}) async {
    await startService();
  }

  /// Legacy alias.
  Future<void> startQuick({List<String> bootstrapPeers = const []}) async {
    await startService();
  }

  // ── Message Handling ───────────────────────────────────────────────

  /// Called when a message is received for this identity.
  void handleMessage(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    // Decompress non-encrypted payloads (e.g. CONTACT_REQUEST, FRAGMENT_STORE)
    // For encrypted messages (TEXT), decompression happens after decryption
    if (envelope.compression == proto.CompressionType.ZSTD &&
        envelope.encryptedPayload.isNotEmpty &&
        !envelope.hasKemHeader()) {
      try {
        envelope.encryptedPayload = ZstdCompression.instance.decompress(
          Uint8List.fromList(envelope.encryptedPayload),
        );
      } catch (e) {
        _log.debug('Zstd decompress failed: $e');
        return;
      }
    }

    final msgIdHex = bytesToHex(Uint8List.fromList(envelope.messageId));

    // Dedup: check persisted messages
    if (_processedMessageIds.contains(msgIdHex) && msgIdHex.isNotEmpty) {
      final dedupType = envelope.messageType;
      if (dedupType == proto.MessageType.CONTACT_REQUEST || dedupType == proto.MessageType.CONTACT_REQUEST_RESPONSE) {
        _log.debug('DEDUP: dropped ${dedupType.name} msgId=${msgIdHex.substring(0, 8)} (already processed)');
      }
      return;
    }

    final type = envelope.messageType;

    // Count user-visible incoming messages for network stats
    if (_isUserVisibleMessage(type)) {
      _statsCollector.addMessageReceived();
    }

    // KEX Gate (Architecture 5.6.2): Only process encrypted content messages
    // if the sender is an accepted contact or member of a shared group/channel.
    // Infrastructure, discovery, and contact establishment are always allowed.
    if (!_isKexGateExempt(type)) {
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
      if (!_isKnownSender(senderHex)) {
        _log.debug('KEX Gate: dropped ${type.name} from unknown sender ${senderHex.length > 8 ? senderHex.substring(0, 8) : senderHex}');
        return;
      }
    }

    // §26 Phase 3: Learn sender's deviceNodeId from every incoming message.
    _learnDeviceNodeId(envelope);

    switch (type) {
      case proto.MessageType.TEXT:
        _handleTextMessage(envelope);
        break;
      case proto.MessageType.CONTACT_REQUEST:
        _handleContactRequest(envelope);
        break;
      case proto.MessageType.CONTACT_REQUEST_RESPONSE:
        _handleContactResponse(envelope);
        break;
      case proto.MessageType.TYPING_INDICATOR:
      case proto.MessageType.READ_RECEIPT:
      case proto.MessageType.DELIVERY_RECEIPT:
        _handleEphemeral(envelope);
        break;
      case proto.MessageType.FRAGMENT_STORE:
        _handleFragmentStore(envelope, from, fromPort);
        break;
      case proto.MessageType.FRAGMENT_RETRIEVE:
        _handleFragmentRetrieve(envelope, from, fromPort);
        break;
      case proto.MessageType.FRAGMENT_DELETE:
        _handleFragmentDelete(envelope);
        break;
      case proto.MessageType.MESSAGE_EDIT:
        _handleMessageEdit(envelope);
        break;
      case proto.MessageType.MESSAGE_DELETE:
        _handleMessageDelete(envelope);
        break;
      case proto.MessageType.MEDIA_ANNOUNCEMENT:
        _handleMediaAnnouncement(envelope);
        break;
      case proto.MessageType.MEDIA_ACCEPT:
        _handleMediaAccept(envelope);
        break;
      case proto.MessageType.IMAGE:
      case proto.MessageType.FILE:
      case proto.MessageType.VIDEO:
      case proto.MessageType.VOICE_MESSAGE:
        _handleMediaContent(envelope);
        break;
      case proto.MessageType.GROUP_INVITE:
        _handleGroupInvite(envelope);
        break;
      case proto.MessageType.GROUP_LEAVE:
        _handleGroupLeave(envelope);
        break;
      case proto.MessageType.CHANNEL_INVITE:
        _handleChannelInvite(envelope);
        break;
      case proto.MessageType.CHANNEL_LEAVE:
        _handleChannelLeave(envelope);
        break;
      case proto.MessageType.CHANNEL_ROLE_UPDATE:
        _handleChannelRoleUpdate(envelope);
        break;
      case proto.MessageType.CHANNEL_POST:
        _handleChannelPost(envelope);
        break;
      case proto.MessageType.EMOJI_REACTION:
        _handleEmojiReaction(envelope);
        break;
      case proto.MessageType.PROFILE_UPDATE:
        _handleProfileUpdate(envelope);
        break;
      case proto.MessageType.CHAT_CONFIG_UPDATE:
      case proto.MessageType.CHAT_CONFIG_RESPONSE:
        _handleChatConfigUpdate(envelope);
        break;
      case proto.MessageType.IDENTITY_DELETED:
        _handleIdentityDeleted(envelope);
        break;
      case proto.MessageType.RESTORE_BROADCAST:
        _handleRestoreBroadcast(envelope);
        break;
      case proto.MessageType.RESTORE_RESPONSE:
        _handleRestoreResponse(envelope);
        break;
      case proto.MessageType.GUARDIAN_SHARE_STORE:
        _handleGuardianShareStore(envelope);
        break;
      case proto.MessageType.GUARDIAN_RESTORE_REQUEST:
        _handleGuardianRestoreRequest(envelope);
        break;
      case proto.MessageType.GUARDIAN_RESTORE_RESPONSE:
        guardianService.handleRestoreResponse(envelope);
        break;
      case proto.MessageType.CALL_INVITE:
        // Route to group or 1:1 call manager.
        // CALL_INVITE may be KEM-encrypted (group calls use sendEncrypted).
        // Decrypt first to probe isGroupCall, then dispatch.
        _handleCallInviteDispatch(envelope);
        notificationSound.startRingtone();
        notificationSound.vibrate(VibrationType.call);
        break;
      case proto.MessageType.CALL_ANSWER:
        notificationSound.stopRingtone();
        notificationSound.stopRingback();
        notificationSound.playConnected();
        if (groupCallManager.currentGroupCall != null) {
          groupCallManager.handleGroupCallAnswer(envelope);
        } else {
          callManager.handleCallAnswer(envelope);
        }
        break;
      case proto.MessageType.CALL_REJECT:
        notificationSound.stopRingtone();
        notificationSound.stopRingback();
        if (groupCallManager.currentGroupCall != null) {
          groupCallManager.handleGroupCallReject(envelope);
        } else {
          callManager.handleCallReject(envelope);
        }
        break;
      case proto.MessageType.CALL_HANGUP:
        notificationSound.stopRingtone();
        notificationSound.stopRingback();
        if (groupCallManager.currentGroupCall != null) {
          groupCallManager.handleGroupCallHangup(envelope);
        } else {
          callManager.handleCallHangup(envelope);
        }
        break;
      case proto.MessageType.CALL_AUDIO:
        _handleCallAudio(envelope);
        break;
      case proto.MessageType.CALL_VIDEO:
        _handleCallVideo(envelope);
        break;
      case proto.MessageType.CALL_KEYFRAME_REQUEST:
        _handleKeyframeRequest(envelope);
        break;
      // Group Calls (Phase 3c)
      case proto.MessageType.CALL_GROUP_AUDIO:
        _handleGroupCallAudio(envelope);
        break;
      case proto.MessageType.CALL_GROUP_VIDEO:
        _handleGroupCallVideo(envelope);
        break;
      case proto.MessageType.CALL_GROUP_LEAVE:
        groupCallManager.handleGroupCallLeave(envelope);
        break;
      case proto.MessageType.CALL_GROUP_KEY_ROTATE:
        // KEM-encrypted — decrypt before dispatching
        if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
          try {
            var decrypted = PerMessageKem.decrypt(
              kemHeader: envelope.kemHeader,
              ciphertext: Uint8List.fromList(envelope.encryptedPayload),
              ourX25519Sk: identity.x25519SecretKey,
              ourMlKemSk: identity.mlKemSecretKey,
            );
            if (envelope.compression == proto.CompressionType.ZSTD) {
              decrypted = ZstdCompression.instance.decompress(decrypted);
            }
            groupCallManager.handleGroupCallKeyRotate(envelope, decrypted);
          } catch (e) {
            _log.debug('GROUP_KEY_ROTATE decrypt failed: $e');
          }
        } else {
          groupCallManager.handleGroupCallKeyRotate(envelope, null);
        }
        break;
      case proto.MessageType.CALL_RTT_PING:
        groupCallManager.handleCallRttPing(envelope);
        break;
      case proto.MessageType.CALL_RTT_PONG:
        groupCallManager.handleCallRttPong(envelope);
        break;
      case proto.MessageType.CALL_TREE_UPDATE:
        groupCallManager.handleCallTreeUpdate(envelope);
        break;
      case proto.MessageType.CALL_REJOIN:
        groupCallManager.handleCallRejoin(envelope);
        break;
      case proto.MessageType.CHANNEL_JOIN_REQUEST:
        _handleChannelJoinRequest(envelope);
        break;
      case proto.MessageType.CHANNEL_INDEX_EXCHANGE:
        _handleChannelIndexExchange(envelope);
        break;
      case proto.MessageType.CHANNEL_REPORT:
        _handleIncomingChannelReport(envelope);
        break;
      case proto.MessageType.JURY_REQUEST:
        _handleIncomingJuryRequest(envelope);
        break;
      case proto.MessageType.JURY_VOTE_MSG:
        _handleIncomingJuryVote(envelope);
        break;
      case proto.MessageType.JURY_RESULT:
        _handleIncomingJuryResult(envelope);
        break;
      // Multi-Device (§26)
      case proto.MessageType.TWIN_ANNOUNCE:
        _handleTwinAnnounce(envelope);
        break;
      case proto.MessageType.TWIN_SYNC:
        _handleTwinSync(envelope);
        break;
      case proto.MessageType.DEVICE_REVOKED:
        _handleDeviceRevokedBroadcast(envelope);
        break;
      case proto.MessageType.KEY_ROTATION_BROADCAST:
        _handleKeyRotationBroadcast(envelope);
        break;
      case proto.MessageType.KEY_ROTATION_ACK:
        _handleKeyRotationAck(envelope);
        break;
      // Calendar (§23)
      case proto.MessageType.CALENDAR_INVITE:
        _handleCalendarInvite(envelope);
        break;
      case proto.MessageType.CALENDAR_RSVP:
        _handleCalendarRsvp(envelope);
        break;
      case proto.MessageType.CALENDAR_UPDATE:
        _handleCalendarUpdate(envelope);
        break;
      case proto.MessageType.CALENDAR_DELETE:
        _handleCalendarDelete(envelope);
        break;
      case proto.MessageType.FREE_BUSY_REQUEST:
        _handleFreeBusyRequest(envelope);
        break;
      case proto.MessageType.FREE_BUSY_RESPONSE:
        _handleFreeBusyResponse(envelope);
        break;
      // Polls (§24)
      case proto.MessageType.POLL_CREATE:
        _handlePollCreate(envelope);
        break;
      case proto.MessageType.POLL_VOTE:
        _handlePollVote(envelope);
        break;
      case proto.MessageType.POLL_UPDATE:
        _handlePollUpdate(envelope);
        break;
      case proto.MessageType.POLL_SNAPSHOT:
        _handlePollSnapshot(envelope);
        break;
      case proto.MessageType.POLL_VOTE_ANONYMOUS:
        _handlePollVoteAnonymous(envelope);
        break;
      case proto.MessageType.POLL_VOTE_REVOKE:
        _handlePollVoteRevoke(envelope);
        break;
      default:
        _log.debug('Unhandled message type: $type');
    }

    // RUDP Light: auto-send DELIVERY_RECEIPT for ACK-worthy message types.
    // V3.1: If message arrived via relay (from=0.0.0.0), send receipt via relay too.
    if (AckTracker.isAckWorthy(type) && envelope.senderId.isNotEmpty && envelope.messageId.isNotEmpty) {
      final viaRelay = from.address == '0.0.0.0';
      _sendDeliveryReceipt(Uint8List.fromList(envelope.senderId), Uint8List.fromList(envelope.messageId),
          preferRelay: viaRelay);
    }

    if (msgIdHex.isNotEmpty) {
      _processedMessageIds.add(msgIdHex);
    }
  }

  /// §26 Phase 3: Learn sender's deviceNodeId from incoming messages.
  /// Passively builds the per-contact device list from senderDeviceNodeId.
  void _learnDeviceNodeId(proto.MessageEnvelope envelope) {
    if (envelope.senderDeviceNodeId.isEmpty) return;
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') return;
    final deviceNodeIdHex = bytesToHex(Uint8List.fromList(envelope.senderDeviceNodeId));
    if (contact.deviceNodeIds.add(deviceNodeIdHex)) {
      _saveContacts();
      _log.debug('Learned deviceNodeId ${deviceNodeIdHex.substring(0, 8)} for ${contact.displayName}');
    }
  }

  /// Message types exempt from KEX Gate (infrastructure, contact establishment, recovery).
  static bool _isKexGateExempt(proto.MessageType type) {
    switch (type) {
      // Contact establishment — by definition from unknown senders
      case proto.MessageType.CONTACT_REQUEST:
      case proto.MessageType.CONTACT_REQUEST_RESPONSE:
      // Transport-layer ACKs — must always arrive
      case proto.MessageType.DELIVERY_RECEIPT:
      case proto.MessageType.READ_RECEIPT:
      case proto.MessageType.TYPING_INDICATOR:
      // DHT infrastructure — no sender relationship required
      case proto.MessageType.FRAGMENT_STORE:
      case proto.MessageType.FRAGMENT_RETRIEVE:
      case proto.MessageType.FRAGMENT_DELETE:
      // Recovery — from old device or guardians
      case proto.MessageType.RESTORE_BROADCAST:
      case proto.MessageType.RESTORE_RESPONSE:
      case proto.MessageType.GUARDIAN_SHARE_STORE:
      case proto.MessageType.GUARDIAN_RESTORE_REQUEST:
      case proto.MessageType.GUARDIAN_RESTORE_RESPONSE:
      // Public channel operations — from unknown subscribers
      case proto.MessageType.CHANNEL_JOIN_REQUEST:
      case proto.MessageType.CHANNEL_INDEX_EXCHANGE:
      // Moderation — jury members may not be contacts
      case proto.MessageType.CHANNEL_REPORT:
      case proto.MessageType.JURY_REQUEST:
      case proto.MessageType.JURY_VOTE_MSG:
      case proto.MessageType.JURY_RESULT:
      // Multi-Device (§26) — twin messages come from our own Node-ID
      case proto.MessageType.TWIN_ANNOUNCE:
      case proto.MessageType.TWIN_SYNC:
      // Key rotation broadcast — from a contact who rotated keys (need to accept with old key)
      case proto.MessageType.KEY_ROTATION_BROADCAST:
      case proto.MessageType.KEY_ROTATION_ACK:
      // Device revoked broadcast — from a contact notifying about removed device
      case proto.MessageType.DEVICE_REVOKED:
        return true;
      default:
        return false;
    }
  }

  /// Check if a sender is known: accepted contact OR member of any group/channel.
  bool _isKnownSender(String senderHex) {
    // 1. Accepted contact?
    final contact = _contacts[senderHex];
    if (contact != null && contact.status == 'accepted') return true;

    // 2. Member of any group?
    for (final group in _groups.values) {
      if (group.members.containsKey(senderHex)) return true;
    }

    // 3. Member of any channel?
    for (final channel in _channels.values) {
      if (channel.members.containsKey(senderHex)) return true;
    }

    return false;
  }

  void _handleTextMessage(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt if encrypted
    String text;
    if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
      try {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        // Decompress after decryption
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        text = utf8.decode(decrypted);
      } catch (e) {
        _log.error('Decryption failed: $e');
        return;
      }
    } else {
      text = utf8.decode(envelope.encryptedPayload);
    }

    final msgId = bytesToHex(Uint8List.fromList(envelope.messageId));

    // Determine conversation: group or DM
    final groupIdHex = envelope.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(envelope.groupId))
        : null;
    final conversationId = groupIdHex ?? senderHex;

    // Extract reply/quote fields
    final replyToMsgId = envelope.replyToMessageId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(envelope.replyToMessageId))
        : null;

    final msg = UiMessage(
      id: msgId,
      conversationId: conversationId,
      senderNodeIdHex: senderHex,
      text: text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(envelope.timestamp.toInt()),
      type: proto.MessageType.TEXT,
      status: MessageStatus.delivered,
      isOutgoing: false,
      readAt: DateTime.now(), // Incoming messages are read on receipt
      replyToMessageId: replyToMsgId,
      replyToText: envelope.replyToText.isNotEmpty ? envelope.replyToText : null,
      replyToSender: envelope.replyToSender.isNotEmpty ? envelope.replyToSender : null,
    );

    // Extract sender-side link preview (recipient makes NO network request)
    if (envelope.hasLinkPreview() && envelope.linkPreview.url.isNotEmpty) {
      final lp = envelope.linkPreview;
      msg.linkPreviewUrl = lp.url;
      msg.linkPreviewTitle = lp.title.isNotEmpty ? lp.title : null;
      msg.linkPreviewDescription = lp.description.isNotEmpty ? lp.description : null;
      msg.linkPreviewSiteName = lp.siteName.isNotEmpty ? lp.siteName : null;
      if (lp.thumbnail.isNotEmpty) {
        msg.linkPreviewThumbnailBase64 = base64Encode(lp.thumbnail);
      }
    }

    final isChannel = groupIdHex != null && _channels.containsKey(groupIdHex);
    final isGroup = groupIdHex != null && !isChannel;
    _addMessageToConversation(conversationId, msg, isGroup: isGroup, isChannel: isChannel);
    notificationSound.playMessageSound();
    notificationSound.vibrate(VibrationType.message);
    final textSenderName = _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
    _postAndroidNotification(textSenderName, text.length > 100 ? '${text.substring(0, 100)}...' : text, conversationId);
    // Badge update happens inside _addMessageToConversation — single source of truth.

    _log.info('TEXT from ${senderHex.substring(0, 8)}: ${text.length > 50 ? text.substring(0, 50) : text}');
  }

  void _handleContactRequest(proto.MessageEnvelope envelope) {
    try {
      final cr = proto.ContactRequestMsg.fromBuffer(envelope.encryptedPayload);
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

      // Multi-Identity guard: only process CRs addressed to THIS identity.
      // Without this, a CR to AllyCat could be processed by Alice's service
      // on the same node, resulting in Alice responding instead of AllyCat.
      // Accept both userId and deviceNodeId: senders with pre-V3.1.44 contacts
      // may have stored our deviceNodeId instead of userId.
      if (envelope.recipientId.isNotEmpty) {
        final recipientHex = bytesToHex(Uint8List.fromList(envelope.recipientId));
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
      final existing = _contacts[senderHex];
      if (existing != null && existing.status == 'accepted') {
        existing.displayName = cr.displayName;
        existing.ed25519Pk = Uint8List.fromList(cr.ed25519PublicKey);
        existing.x25519Pk = Uint8List.fromList(cr.x25519PublicKey);
        existing.mlKemPk = Uint8List.fromList(cr.mlKemPublicKey);
        existing.mlDsaPk = Uint8List.fromList(cr.mlDsaPublicKey);
        if (cr.profilePicture.isNotEmpty) {
          existing.profilePictureBase64 = base64Encode(cr.profilePicture);
        }
        _saveContacts();
        _log.info('Re-contact from accepted ${cr.displayName} — sending acceptance response');
        // Re-send acceptance so the remote side knows we still have them.
        // Not awaited intentionally: sendEnvelope is ACK-tracked by AckTracker,
        // and the CR retry timer handles failures — no need to block here.
        acceptContactRequest(senderHex);
        return;
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
        _saveContacts();
        _log.info('Bidirectional CR from ${cr.displayName} — auto-accepting');
        acceptContactRequest(senderHex);
        return;
      }

      final contact = ContactInfo(
        nodeId: Uint8List.fromList(envelope.senderId),
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
            type: proto.MessageType.IDENTITY_DELETED,
            status: MessageStatus.delivered,
          );
          oldConv.messages.add(systemMsg);
          _log.info('Stale contact detected: ${cr.displayName} has new identity '
              '${senderHex.substring(0, 8)}, old was ${entry.key.substring(0, 8)}');
        }
      }

      _contacts[senderHex] = contact;
      _saveContacts();
      _saveConversations();

      onContactRequestReceived?.call(senderHex, cr.displayName);
      onStateChanged?.call();
      _log.info('Contact request from ${cr.displayName} (${senderHex.substring(0, 8)})');
    } catch (e) {
      _log.error('Contact request parse error: $e');
    }
  }

  void _handleContactResponse(proto.MessageEnvelope envelope) {
    try {
      final resp = proto.ContactRequestResponse.fromBuffer(envelope.encryptedPayload);
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

      // Multi-Identity guard: only accept responses addressed to THIS identity.
      // Accept both userId and deviceNodeId (backward compat with pre-V3.1.44 contacts).
      if (envelope.recipientId.isNotEmpty) {
        final recipientHex = bytesToHex(Uint8List.fromList(envelope.recipientId));
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
        // Without this check, a response from a wrong identity (e.g. Alice
        // responding to a CR addressed to AllyCat) would create a ghost contact.
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
        _crRetryCountPerContact.remove(nodeIdHex);
        _staleWarningWrittenFor.remove(nodeIdHex);
        existing.ed25519Pk = Uint8List.fromList(resp.ed25519PublicKey);
        existing.x25519Pk = Uint8List.fromList(resp.x25519PublicKey);
        existing.mlKemPk = Uint8List.fromList(resp.mlKemPublicKey);
        existing.mlDsaPk = Uint8List.fromList(resp.mlDsaPublicKey);
        existing.displayName = resp.displayName;
        if (picBase64 != null) existing.profilePictureBase64 = picBase64;
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
          type: proto.MessageType.IDENTITY_DELETED, // system message type
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
      _log.error('Contact response parse error: $e');
    }
  }

  /// Tracks when each contact last sent a typing indicator.
  final Map<String, DateTime> _typingTimestamps = {};

  /// Returns true if the given contact is currently typing (within last 5 seconds).
  bool isTyping(String nodeIdHex) {
    final ts = _typingTimestamps[nodeIdHex];
    if (ts == null) return false;
    return DateTime.now().difference(ts).inSeconds < 5;
  }

  void _handleEphemeral(proto.MessageEnvelope envelope) {
    final type = envelope.messageType;
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final groupIdHex = envelope.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(envelope.groupId))
        : null;
    final conversationId = groupIdHex ?? senderHex;
    final conv = conversations[conversationId];

    if (type == proto.MessageType.DELIVERY_RECEIPT) {
      _handleDeliveryReceipt(envelope, conversationId);
    }
    if (type == proto.MessageType.READ_RECEIPT) {
      _handleReadReceipt(envelope);
    }
    if (type == proto.MessageType.TYPING_INDICATOR) {
      // Enforce: ignore typing indicators if disabled for this chat
      if (conv != null && !conv.config.typingIndicators) return;
      // Parse TypingIndicator protobuf (with backward compat for empty payload)
      bool isTyping = true;
      try {
        if (envelope.encryptedPayload.isNotEmpty) {
          final indicator = proto.TypingIndicator.fromBuffer(envelope.encryptedPayload);
          isTyping = indicator.isTyping;
        }
      } catch (_) {
        // Backward compat: empty/unparseable payload = is_typing=true
      }
      if (isTyping) {
        _typingTimestamps[senderHex] = DateTime.now();
      } else {
        _typingTimestamps.remove(senderHex);
      }
      onStateChanged?.call();
    }
  }

  /// Handle DELIVERY_RECEIPT: mark outgoing message as delivered in UI.
  void _handleDeliveryReceipt(proto.MessageEnvelope envelope, String conversationId) {
    try {
      final receipt = proto.DeliveryReceipt.fromBuffer(envelope.encryptedPayload);
      final msgIdHex = bytesToHex(Uint8List.fromList(receipt.messageId));
      final conv = conversations[conversationId];
      if (conv == null) return;
      for (final msg in conv.messages) {
        if (msg.id == msgIdHex && msg.isOutgoing && msg.status == MessageStatus.sent) {
          msg.status = MessageStatus.delivered;
          onStateChanged?.call();
          break;
        }
      }
    } catch (_) {}
  }

  /// RUDP Light: ACK timeout — downgrade message status from "sent" to "queued".
  void _handleAckTimeout(String messageIdHex, String recipientNodeIdHex) {
    for (final conv in conversations.values) {
      for (final msg in conv.messages) {
        if (msg.id == messageIdHex && msg.isOutgoing && msg.status == MessageStatus.sent) {
          msg.status = MessageStatus.queued;
          _log.info('ACK timeout for ${messageIdHex.substring(0, 8)} to '
              '${recipientNodeIdHex.substring(0, 8)} — status downgraded to queued');
          onStateChanged?.call();
          return;
        }
      }
    }
  }

  /// Handle READ_RECEIPT: mark outgoing message as read, set readAt for expiry.
  void _handleReadReceipt(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Parse ReadReceipt protobuf (with backward compat for raw bytes)
    String msgIdHex;
    DateTime readAt;
    try {
      final receipt = proto.ReadReceipt.fromBuffer(envelope.encryptedPayload);
      if (receipt.messageId.isEmpty) return;
      msgIdHex = bytesToHex(Uint8List.fromList(receipt.messageId));
      readAt = receipt.readAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(receipt.readAt.toInt())
          : DateTime.now();
    } catch (_) {
      // Backward compat: old nodes may send raw message ID bytes
      if (envelope.encryptedPayload.isEmpty) return;
      msgIdHex = bytesToHex(Uint8List.fromList(envelope.encryptedPayload));
      readAt = DateTime.now();
    }

    // Find the conversation (DM or group)
    final groupIdHex = envelope.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(envelope.groupId))
        : null;
    final conversationId = groupIdHex ?? senderHex;
    final conv = conversations[conversationId];
    if (conv == null) return;

    for (final msg in conv.messages) {
      if (msg.id == msgIdHex && msg.isOutgoing) {
        msg.status = MessageStatus.read;
        msg.readAt ??= readAt;
        break;
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

  void _handleFragmentStore(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    try {
      final frag = proto.FragmentStore.fromBuffer(envelope.encryptedPayload);
      final stored = mailboxStore.storeFragment(StoredFragment(
        mailboxId: Uint8List.fromList(frag.mailboxId),
        messageId: Uint8List.fromList(frag.messageId),
        fragmentIndex: frag.fragmentIndex,
        totalFragments: frag.totalFragments,
        requiredFragments: frag.requiredFragments,
        data: Uint8List.fromList(frag.fragmentData),
        originalSize: frag.originalSize,
      ));

      // Send ACK
      if (stored) {
        final ack = identity.createSignedEnvelope(
          proto.MessageType.FRAGMENT_STORE_ACK,
          (proto.FragmentStoreAck()
                ..messageId = frag.messageId
                ..fragmentIndex = frag.fragmentIndex)
              .writeToBuffer(),
          recipientId: Uint8List.fromList(envelope.senderId),
        );
        if (from.address != '0.0.0.0') {
          node.transport.sendUdp(ack, from, fromPort);
        } else {
          // Came via relay — send ACK via cascade (uses learned relay route)
          node.sendEnvelope(ack, Uint8List.fromList(envelope.senderId));
        }
      }

      // Check if this fragment is for our mailbox before reassembly
      final mailboxId = Uint8List.fromList(frag.mailboxId);
      if (_isOurMailbox(mailboxId)) {
        _tryReassemble(Uint8List.fromList(frag.messageId));
      } else if (stored) {
        // Proactive fragment push (Architecture 3.5):
        // If we know the mailbox owner, forward the fragment immediately.
        _proactivePush(frag, mailboxId);
      }
    } catch (e) {
      _log.debug('Fragment store error: $e');
    }
  }

  /// Proactive fragment push: forward a stored fragment to the mailbox owner
  /// if we know their address. This converts pull-based delivery (polling)
  /// to push-based (< 1s latency). Per Architecture Section 3.5.
  /// Checks both contacts AND routing table peers (PeerExchange provides PKs).
  void _proactivePush(proto.FragmentStore frag, Uint8List mailboxId) {
    final sodium = SodiumFFI();

    // Collect all known ed25519 PKs: from contacts + routing table peers
    final candidates = <({Uint8List nodeId, Uint8List ed25519Pk})>[];

    for (final contact in _contacts.values) {
      if (contact.ed25519Pk != null) {
        candidates.add((nodeId: contact.nodeId, ed25519Pk: contact.ed25519Pk!));
      }
    }
    for (final peer in node.routingTable.allPeers) {
      if (peer.ed25519PublicKey != null && peer.ed25519PublicKey!.isNotEmpty) {
        candidates.add((nodeId: peer.nodeId, ed25519Pk: peer.ed25519PublicKey!));
      }
    }

    for (final candidate in candidates) {
      final candidateMailbox = sodium.sha256(Uint8List.fromList(
        [...utf8.encode('mailbox'), ...candidate.ed25519Pk],
      ));
      if (!_bytesEqual(mailboxId, candidateMailbox)) continue;

      // Found the owner — check if they're reachable
      final peer = node.routingTable.getPeer(candidate.nodeId);
      if (peer == null) continue;

      // Forward using our own senderId (not the original sender's)
      // to prevent falsely updating lastSeen on the recipient.
      final pushEnvelope = identity.createSignedEnvelope(
        proto.MessageType.FRAGMENT_STORE,
        frag.writeToBuffer(),
        recipientId: candidate.nodeId,
      );

      // V3: UDP only — fragments are pushed via UDP
      final targets = peer.allConnectionTargets();
      for (final addr in targets.take(3)) {
        try {
          node.transport.sendUdp(pushEnvelope, InternetAddress(addr.ip), addr.port);
        } catch (_) {}
      }

      _log.debug('Proactive push: fragment ${frag.fragmentIndex} to '
          '${bytesToHex(candidate.nodeId).substring(0, 8)}');
      return;
    }
  }

  void _handleFragmentRetrieve(proto.MessageEnvelope envelope, InternetAddress from, int fromPort) {
    try {
      final req = proto.FragmentRetrieve.fromBuffer(envelope.encryptedPayload);
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

        final env = identity.createSignedEnvelope(
          proto.MessageType.FRAGMENT_STORE,
          fragStore.writeToBuffer(),
          recipientId: Uint8List.fromList(envelope.senderId),
        );
        if (from.address != '0.0.0.0') {
          node.transport.sendUdp(env, from, fromPort);
        } else {
          node.sendEnvelope(env, Uint8List.fromList(envelope.senderId));
        }
      }
    } catch (e) {
      _log.debug('Fragment retrieve error: $e');
    }
  }

  void _handleFragmentDelete(proto.MessageEnvelope envelope) {
    try {
      final del = proto.FragmentDelete.fromBuffer(envelope.encryptedPayload);
      mailboxStore.deleteFragments(
        Uint8List.fromList(del.mailboxId),
        Uint8List.fromList(del.messageId),
      );
    } catch (_) {}
  }

  // Pending media: maps messageIdHex -> local file path (sender keeps file until accepted)
  final Map<String, String> _pendingMediaSends = {};

  /// Send a media file (image, file, etc.) to a contact or group.
  /// Two-Stage: sends MEDIA_ANNOUNCEMENT first, actual content on MEDIA_ACCEPT.
  @override
  Future<UiMessage?> sendMediaMessage(String conversationId, String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return null;

    final audioBytes = await file.readAsBytes();
    final filename = filePath.split('/').last;
    final mimeType = _guessMimeType(filename);
    final fileSize = audioBytes.length;
    final isVoice = _msgTypeFromMime(mimeType) == proto.MessageType.VOICE_MESSAGE;
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
    final tempId = bytesToHex(SodiumFFI().randomBytes(16));
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

    // Generate thumbnail for images
    Uint8List? thumbnail;
    if (mimeType.startsWith('image/') && bytes.isNotEmpty) {
      thumbnail = bytes.length <= 100 * 1024 ? bytes : Uint8List.fromList(bytes.sublist(0, 100 * 1024));
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
      if (contact == null || contact.status != 'accepted') return null;
      recipients = [contact];
    }

    // ── Encrypt and send ──
    String? firstMsgId;
    if (fileSize <= 256 * 1024) {
      for (final recipient in recipients) {
        if (recipient.x25519Pk == null || recipient.mlKemPk == null) continue;

        var payload = bytes;
        var compression = proto.CompressionType.NONE;
        if (payload.length >= 64) {
          try {
            final compressed = ZstdCompression.instance.compress(payload);
            if (compressed.length < payload.length) {
              payload = compressed;
              compression = proto.CompressionType.ZSTD;
            }
          } catch (_) {}
        }

        final (kemHeader, ciphertext) = PerMessageKem.encrypt(
          plaintext: payload,
          recipientX25519Pk: recipient.x25519Pk!,
          recipientMlKemPk: recipient.mlKemPk!,
        );

        final msgType = _msgTypeFromMime(mimeType);
        final envelope = identity.createSignedEnvelope(
          msgType,
          ciphertext,
          recipientId: recipient.nodeId,
          compress: false,
        );
        envelope.kemHeader = kemHeader;
        envelope.compression = compression;
        envelope.contentMetadata = metadata;
        if (isGroup) envelope.groupId = hexToBytes(conversationId);

        firstMsgId ??= bytesToHex(Uint8List.fromList(envelope.messageId));
        await node.sendEnvelope(envelope, recipient.nodeId);
        _statsCollector.addMessageSent();
        _storeErasureCodedBackup(envelope, _contacts[bytesToHex(recipient.nodeId)], recipientNodeId: recipient.nodeId);
      }
    } else {
      // Two-Stage: send MEDIA_ANNOUNCEMENT only
      for (final recipient in recipients) {
        if (recipient.x25519Pk == null || recipient.mlKemPk == null) continue;

        var payload = Uint8List.fromList(announcementBytes);
        var compression = proto.CompressionType.NONE;
        if (payload.length >= 64) {
          try {
            final compressed = ZstdCompression.instance.compress(payload);
            if (compressed.length < payload.length) {
              payload = compressed;
              compression = proto.CompressionType.ZSTD;
            }
          } catch (_) {}
        }

        final (kemHeader, ciphertext) = PerMessageKem.encrypt(
          plaintext: payload,
          recipientX25519Pk: recipient.x25519Pk!,
          recipientMlKemPk: recipient.mlKemPk!,
        );

        final envelope = identity.createSignedEnvelope(
          proto.MessageType.MEDIA_ANNOUNCEMENT,
          ciphertext,
          recipientId: recipient.nodeId,
          compress: false,
        );
        envelope.kemHeader = kemHeader;
        envelope.compression = compression;
        envelope.contentMetadata = metadata;
        if (isGroup) envelope.groupId = hexToBytes(conversationId);

        firstMsgId ??= bytesToHex(Uint8List.fromList(envelope.messageId));
        node.sendEnvelope(envelope, recipient.nodeId);
      }
    }

    // Store pending media for two-stage delivery
    if (fileSize > 256 * 1024 && firstMsgId != null) {
      _pendingMediaSends[firstMsgId] = persistentPath;
    }

    // Update message with final ID and status
    if (firstMsgId != null) msg.id = firstMsgId;
    final thumbnailB64 = thumbnail != null ? base64Encode(thumbnail) : null;
    msg.thumbnailBase64 = thumbnailB64;
    msg.status = MessageStatus.sent;
    _saveConversations();
    onStateChanged?.call();

    _log.info('Media sent: $filename ($fileSize bytes) to $conversationId');
    return msg;
  }

  /// Accept a media download (Two-Stage: send MEDIA_ACCEPT).
  @override
  Future<bool> acceptMediaDownload(String conversationId, String messageId) async {
    final conv = conversations[conversationId];
    if (conv == null) return false;

    // Enforce allowDownloads policy
    if (!conv.config.allowDownloads) {
      _log.warn('Download blocked: allowDownloads=false for $conversationId');
      return false;
    }

    final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null || msg.mediaState != MediaDownloadState.announced) return false;

    // For now, just mark as downloading (the actual content delivery is handled
    // when we receive the IMAGE/FILE response from sender)
    msg.mediaState = MediaDownloadState.downloading;
    onStateChanged?.call();
    _saveConversations();

    // Send MEDIA_ACCEPT to the original sender
    final senderNodeId = hexToBytes(msg.senderNodeIdHex);
    final contact = _contacts[msg.senderNodeIdHex];
    if (contact == null || contact.x25519Pk == null || contact.mlKemPk == null) return false;

    // The accept message references the original messageId
    final acceptPayload = Uint8List.fromList(hexToBytes(messageId));
    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: acceptPayload,
      recipientX25519Pk: contact.x25519Pk!,
      recipientMlKemPk: contact.mlKemPk!,
    );

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.MEDIA_ACCEPT,
      ciphertext,
      recipientId: senderNodeId,
    );
    envelope.kemHeader = kemHeader;
    node.sendEnvelope(envelope, senderNodeId);

    _log.info('Media download accepted for $messageId');
    return true;
  }

  void _handleMediaAnnouncement(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt
    Uint8List payload;
    try {
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
    } catch (e) {
      _log.error('MEDIA_ANNOUNCEMENT decrypt failed: $e');
      return;
    }

    final metadata = proto.ContentMetadata.fromBuffer(payload);
    final msgId = bytesToHex(Uint8List.fromList(envelope.messageId));
    final groupIdHex = envelope.groupId.isNotEmpty ? bytesToHex(Uint8List.fromList(envelope.groupId)) : null;
    final conversationId = groupIdHex ?? senderHex;

    final thumbnailB64 = metadata.thumbnail.isNotEmpty ? base64Encode(metadata.thumbnail) : null;

    final msg = UiMessage(
      id: msgId,
      conversationId: conversationId,
      senderNodeIdHex: senderHex,
      text: metadata.filename,
      timestamp: DateTime.fromMillisecondsSinceEpoch(envelope.timestamp.toInt()),
      type: _msgTypeFromMime(metadata.mimeType),
      status: MessageStatus.delivered,
      isOutgoing: false,
      mimeType: metadata.mimeType,
      fileSize: metadata.fileSize.toInt(),
      filename: metadata.filename,
      thumbnailBase64: thumbnailB64,
      mediaState: MediaDownloadState.announced,
    );

    _addMessageToConversation(conversationId, msg, isGroup: groupIdHex != null);
    _log.info('Media announcement from ${senderHex.substring(0, 8)}: ${metadata.filename} (${metadata.fileSize} bytes)');

    // Auto-accept if below threshold (Architecture 3.4.3)
    if (_mediaSettings.shouldAutoDownload(metadata.mimeType, metadata.fileSize.toInt())) {
      acceptMediaDownload(conversationId, msgId);
    }
  }

  void _handleMediaContent(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt file content
    Uint8List fileData;
    try {
      _log.debug('Media decrypt: hasKem=${envelope.hasKemHeader()} '
          'kemPkLen=${envelope.hasKemHeader() ? envelope.kemHeader.ephemeralX25519Pk.length : 0} '
          'compression=${envelope.compression} payloadLen=${envelope.encryptedPayload.length}');
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        fileData = decrypted;
      } else {
        fileData = Uint8List.fromList(envelope.encryptedPayload);
      }
    } catch (e) {
      _log.error('Media content decrypt failed: $e');
      return;
    }

    final msgId = bytesToHex(Uint8List.fromList(envelope.messageId));
    final groupIdHex = envelope.groupId.isNotEmpty ? bytesToHex(Uint8List.fromList(envelope.groupId)) : null;
    final conversationId = groupIdHex ?? senderHex;
    final metadata = envelope.contentMetadata;

    // Voice messages: try to parse VoicePayload (audio + transcript)
    Uint8List actualFileData = fileData;
    String? transcriptText;
    String? transcriptLanguage;
    double? transcriptConfidence;

    if (envelope.messageType == proto.MessageType.VOICE_MESSAGE) {
      try {
        final voicePayload = proto.VoicePayload.fromBuffer(fileData);
        if (voicePayload.audioData.isNotEmpty) {
          // New format: VoicePayload wrapper
          actualFileData = Uint8List.fromList(voicePayload.audioData);
          if (voicePayload.transcriptText.isNotEmpty) {
            transcriptText = voicePayload.transcriptText;
            transcriptLanguage = voicePayload.transcriptLanguage;
            transcriptConfidence = voicePayload.transcriptConfidence.toDouble();
            _log.info('Voice received with transcript: "${transcriptText.length > 40 ? '${transcriptText.substring(0, 40)}...' : transcriptText}"');
          }
        }
        // If audioData is empty, the parse "succeeded" on raw audio bytes
        // (protobuf accepts anything) — treat as raw audio.
      } catch (_) {
        // Parse failed — old client sent raw audio bytes, no VoicePayload wrapper.
      }
    }

    // Save file to media directory
    final mediaDir = Directory('$profileDir/media');
    if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
    final filename = metadata.filename.isNotEmpty ? metadata.filename : 'file_$msgId';
    final savePath = '${mediaDir.path}/$filename';
    File(savePath).writeAsBytesSync(actualFileData);

    final thumbnailB64 = metadata.thumbnail.isNotEmpty ? base64Encode(metadata.thumbnail) : null;
    // For images: use the image data itself as thumbnail if small
    final effectiveThumbnail = thumbnailB64 ?? (metadata.mimeType.startsWith('image/') && actualFileData.length <= 100 * 1024 ? base64Encode(actualFileData) : null);

    final msg = UiMessage(
      id: msgId,
      conversationId: conversationId,
      senderNodeIdHex: senderHex,
      text: filename,
      timestamp: DateTime.fromMillisecondsSinceEpoch(envelope.timestamp.toInt()),
      type: envelope.messageType,
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

    _addMessageToConversation(conversationId, msg, isGroup: groupIdHex != null);
    notificationSound.playMessageSound();
    notificationSound.vibrate(VibrationType.message);
    final mediaSenderName = _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
    final mediaTypeLabel = metadata.mimeType.startsWith('image/') ? '📷 Bild'
        : metadata.mimeType.startsWith('video/') ? '🎬 Video'
        : metadata.mimeType.startsWith('audio/') ? '🎵 Audio'
        : '📎 Datei';
    _postAndroidNotification(mediaSenderName, mediaTypeLabel, conversationId);
    // Badge update happens inside _addMessageToConversation — single source of truth.
    _log.info('Media received: $filename (${actualFileData.length} bytes) from ${senderHex.substring(0, 8)}');

    // Local transcription fallback: if voice message has no transcript, transcribe locally
    if (envelope.messageType == proto.MessageType.VOICE_MESSAGE && transcriptText == null) {
      _voiceTranscription?.enqueueTranscription(
        messageId: msgId,
        audioFilePath: savePath,
      );
    }
  }

  void _handleMediaAccept(proto.MessageEnvelope envelope) {
    // Sender receives MEDIA_ACCEPT → send the actual file content
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    Uint8List payload;
    try {
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        payload = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
    } catch (e) {
      _log.error('MEDIA_ACCEPT decrypt failed: $e');
      return;
    }

    final originalMsgId = bytesToHex(payload);
    final filePath = _pendingMediaSends[originalMsgId];
    if (filePath == null) {
      _log.warn('No pending media for $originalMsgId');
      return;
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      _log.warn('Pending media file not found: $filePath');
      _pendingMediaSends.remove(originalMsgId);
      return;
    }

    // Send the actual content to the requester
    final contact = _contacts[senderHex];
    if (contact == null || contact.x25519Pk == null || contact.mlKemPk == null) return;

    final fileBytes = file.readAsBytesSync();
    final filename = filePath.split('/').last;
    final mimeType = _guessMimeType(filename);

    var data = Uint8List.fromList(fileBytes);
    var compression = proto.CompressionType.NONE;
    if (data.length >= 64) {
      try {
        final compressed = ZstdCompression.instance.compress(data);
        if (compressed.length < data.length) {
          data = compressed;
          compression = proto.CompressionType.ZSTD;
        }
      } catch (_) {}
    }

    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: data,
      recipientX25519Pk: contact.x25519Pk!,
      recipientMlKemPk: contact.mlKemPk!,
    );

    final msgType = _msgTypeFromMime(mimeType);
    final contentEnvelope = identity.createSignedEnvelope(
      msgType,
      ciphertext,
      recipientId: contact.nodeId,
      compress: false,
    );
    contentEnvelope.kemHeader = kemHeader;
    contentEnvelope.compression = compression;
    contentEnvelope.contentMetadata = proto.ContentMetadata()
      ..mimeType = mimeType
      ..fileSize = Int64(fileBytes.length)
      ..filename = filename;

    node.sendEnvelope(contentEnvelope, contact.nodeId);
    _statsCollector.addMessageSent();
    // Erasure-coded backup for offline delivery (Architecture 3.4.2)
    _storeErasureCodedBackup(contentEnvelope, contact);
    _log.info('Media content sent to ${senderHex.substring(0, 8)}: $filename (+ erasure backup)');
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
  proto.MessageType _msgTypeFromMime(String mimeType) {
    if (mimeType.startsWith('image/')) return proto.MessageType.IMAGE;
    if (mimeType.startsWith('audio/')) return proto.MessageType.VOICE_MESSAGE;
    if (mimeType.startsWith('video/')) return proto.MessageType.VIDEO;
    return proto.MessageType.FILE;
  }

  /// Whether this message type represents user-visible content (for stats counting).
  static bool _isUserVisibleMessage(proto.MessageType type) {
    switch (type) {
      case proto.MessageType.TEXT:
      case proto.MessageType.IMAGE:
      case proto.MessageType.GIF:
      case proto.MessageType.FILE:
      case proto.MessageType.VIDEO:
      case proto.MessageType.VOICE_MESSAGE:
      case proto.MessageType.CHANNEL_POST:
      // Two-stage media: user sees a chat placeholder the moment the
      // announcement arrives, long before (or without) the content pull.
      case proto.MessageType.MEDIA_ANNOUNCEMENT:
      // Edits/deletes/reactions modify visible content; user perceives
      // them as "received messages" in the Network-Stats sense.
      case proto.MessageType.MESSAGE_EDIT:
      case proto.MessageType.MESSAGE_DELETE:
      case proto.MessageType.EMOJI_REACTION:
        return true;
      default:
        return false;
    }
  }

  /// Default edit window: 15 minutes.
  static const int _defaultEditWindowMs = 60 * 60 * 1000; // 1 hour

  void _handleMessageEdit(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt payload
    proto.MessageEdit editMsg;
    try {
      Uint8List payload;
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
      editMsg = proto.MessageEdit.fromBuffer(payload);
    } catch (e) {
      _log.error('MESSAGE_EDIT decrypt/parse failed: $e');
      return;
    }

    final originalMsgId = bytesToHex(Uint8List.fromList(editMsg.originalMessageId));

    // Find the original message — group or DM conversation
    final groupIdHex = envelope.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(envelope.groupId))
        : null;
    final conversationId = groupIdHex ?? senderHex;
    final conv = conversations[conversationId];
    if (conv == null) return;

    final msgIndex = conv.messages.indexWhere((m) => m.id == originalMsgId);
    if (msgIndex < 0) return;

    final original = conv.messages[msgIndex];

    // Dual-Enforcement: verify sender is original author
    if (original.senderNodeIdHex != senderHex) {
      _log.warn('Edit rejected: sender ${senderHex.substring(0, 8)} is not author');
      return;
    }

    // Dual-Enforcement: check edit window (per-chat config or default)
    final chatEditWindowMs = conv.config.editWindowMs ?? _defaultEditWindowMs;
    // editWindowMs == 0 means editing disabled; null config → use default
    if (chatEditWindowMs > 0) {
      final ageMs = DateTime.now().millisecondsSinceEpoch - original.timestamp.millisecondsSinceEpoch;
      if (ageMs > chatEditWindowMs) {
        _log.warn('Edit rejected: message too old (${ageMs}ms > ${chatEditWindowMs}ms)');
        return;
      }
    } else if (chatEditWindowMs == 0) {
      _log.warn('Edit rejected: editing disabled for this conversation');
      return;
    }
    // chatEditWindowMs < 0 would mean unlimited (not enforced here)

    // Apply edit
    original.text = editMsg.newText;
    original.editedAt = DateTime.fromMillisecondsSinceEpoch(editMsg.editTimestamp.toInt());

    onStateChanged?.call();
    _saveConversations();
    _log.info('Message edited by ${senderHex.substring(0, 8)}: $originalMsgId');
  }

  void _handleMessageDelete(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt payload
    proto.MessageDelete deleteMsg;
    try {
      Uint8List payload;
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
      deleteMsg = proto.MessageDelete.fromBuffer(payload);
    } catch (e) {
      _log.error('MESSAGE_DELETE decrypt/parse failed: $e');
      return;
    }

    final targetMsgId = bytesToHex(Uint8List.fromList(deleteMsg.messageId));

    // Find the message — group or DM conversation
    final groupIdHex = envelope.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(envelope.groupId))
        : null;
    final conversationId = groupIdHex ?? senderHex;
    final conv = conversations[conversationId];
    if (conv == null) return;

    final msgIndex = conv.messages.indexWhere((m) => m.id == targetMsgId);
    if (msgIndex < 0) return;

    final original = conv.messages[msgIndex];

    // Verify sender is original author
    if (original.senderNodeIdHex != senderHex) {
      _log.warn('Delete rejected: sender ${senderHex.substring(0, 8)} is not author');
      return;
    }

    // Apply deletion (keep placeholder, clear text)
    original.text = '';
    original.isDeleted = true;

    onStateChanged?.call();
    _saveConversations();
    _log.info('Message deleted by ${senderHex.substring(0, 8)}: $targetMsgId');
  }

  // ── Emoji Reactions (Architecture Section 14.3) ──────────────────────

  void _handleEmojiReaction(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt payload
    proto.EmojiReaction reaction;
    try {
      Uint8List payload;
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
      reaction = proto.EmojiReaction.fromBuffer(payload);
    } catch (e) {
      _log.error('EMOJI_REACTION decrypt/parse failed: $e');
      return;
    }

    final targetMsgId = bytesToHex(Uint8List.fromList(reaction.messageId));
    final emoji = reaction.emoji;
    if (emoji.isEmpty) return;

    // Find the message — group or DM conversation
    final groupIdHex = envelope.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(envelope.groupId))
        : null;
    final conversationId = groupIdHex ?? senderHex;
    final conv = conversations[conversationId];
    if (conv == null) return;

    final msgIndex = conv.messages.indexWhere((m) => m.id == targetMsgId);
    if (msgIndex < 0) return;

    final msg = conv.messages[msgIndex];

    if (reaction.remove) {
      // Remove reaction
      msg.reactions[emoji]?.remove(senderHex);
      if (msg.reactions[emoji]?.isEmpty ?? false) {
        msg.reactions.remove(emoji);
      }
      _log.debug('Reaction removed: $emoji on ${targetMsgId.substring(0, 8)} by ${senderHex.substring(0, 8)}');
    } else {
      // Add reaction
      msg.reactions.putIfAbsent(emoji, () => {});
      msg.reactions[emoji]!.add(senderHex);
      _log.debug('Reaction added: $emoji on ${targetMsgId.substring(0, 8)} by ${senderHex.substring(0, 8)}');
    }

    onStateChanged?.call();
    _saveConversations();
  }

  /// Send an emoji reaction to a message.
  @override
  Future<void> sendReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
    required bool remove,
  }) async {
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

    // Group or DM?
    final group = _groups[conversationId];
    if (group != null) {
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final (x25519Pk, mlKemPk) = _resolveMemberKeys(member.nodeIdHex,
            memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk);
        if (x25519Pk == null || mlKemPk == null) continue;

        var payload = Uint8List.fromList(basePayload);
        var compression = proto.CompressionType.NONE;
        if (payload.length >= 64) {
          try {
            final compressed = ZstdCompression.instance.compress(payload);
            if (compressed.length < payload.length) {
              payload = compressed;
              compression = proto.CompressionType.ZSTD;
            }
          } catch (_) {}
        }

        final (kemHeader, ciphertext) = PerMessageKem.encrypt(
          plaintext: payload,
          recipientX25519Pk: x25519Pk,
          recipientMlKemPk: mlKemPk,
        );
        final envelope = identity.createSignedEnvelope(
          proto.MessageType.EMOJI_REACTION, ciphertext,
          recipientId: hexToBytes(member.nodeIdHex), compress: false);
        envelope.kemHeader = kemHeader;
        envelope.compression = compression;
        envelope.groupId = hexToBytes(conversationId);
        node.sendEnvelope(envelope, hexToBytes(member.nodeIdHex));
      }
    } else {
      // DM
      final contact = _contacts[conversationId];
      if (contact == null || contact.x25519Pk == null || contact.mlKemPk == null) return;

      var payload = Uint8List.fromList(basePayload);
      var compression = proto.CompressionType.NONE;
      if (payload.length >= 64) {
        try {
          final compressed = ZstdCompression.instance.compress(payload);
          if (compressed.length < payload.length) {
            payload = compressed;
            compression = proto.CompressionType.ZSTD;
          }
        } catch (_) {}
      }

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: contact.x25519Pk!,
        recipientMlKemPk: contact.mlKemPk!,
      );
      final envelope = identity.createSignedEnvelope(
        proto.MessageType.EMOJI_REACTION, ciphertext,
        recipientId: contact.nodeId, compress: false);
      envelope.kemHeader = kemHeader;
      envelope.compression = compression;
      await node.sendEnvelope(envelope, contact.nodeId);
    }

    onStateChanged?.call();
    _saveConversations();
    _log.info('Reaction ${remove ? "removed" : "added"}: $emoji on ${messageId.substring(0, 8)}');
  }

  /// Broadcast IDENTITY_DELETED to all accepted contacts before deletion.
  void broadcastIdentityDeleted() {
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
        final (kemHeader, ciphertext) = PerMessageKem.encrypt(
          plaintext: payload,
          recipientX25519Pk: contact.x25519Pk!,
          recipientMlKemPk: contact.mlKemPk!,
        );
        final envelope = identity.createSignedEnvelope(
          proto.MessageType.IDENTITY_DELETED,
          ciphertext,
          recipientId: contact.nodeId,
          compress: false,
        );
        envelope.kemHeader = kemHeader;
        node.sendEnvelope(envelope, contact.nodeId);
        sent++;
      } catch (e) {
        _log.debug('IDENTITY_DELETED send to ${contact.displayName} failed: $e');
      }
    }
    _log.info('IDENTITY_DELETED broadcast sent to $sent contacts');
  }

  /// Handle IDENTITY_DELETED: contact notifies us their identity is being deleted.
  void _handleIdentityDeleted(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt payload
    proto.IdentityDeletedNotification notification;
    try {
      final payload = _decryptPayload(envelope);
      notification = proto.IdentityDeletedNotification.fromBuffer(payload);
    } catch (e) {
      _log.error('IDENTITY_DELETED decrypt/parse failed: $e');
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

    // Add system message to conversation
    final conv = conversations[senderHex];
    if (conv != null) {
      final systemMsg = UiMessage(
        id: bytesToHex(Uint8List.fromList(envelope.messageId)),
        conversationId: senderHex,
        senderNodeIdHex: '',
        text: '$displayName has deleted their identity.',
        isOutgoing: false,
        timestamp: DateTime.now(),
        type: proto.MessageType.IDENTITY_DELETED,
        status: MessageStatus.delivered,
      );
      conv.messages.add(systemMsg);
      _saveConversations();
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

  void _handleProfileUpdate(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt payload
    Uint8List payload;
    try {
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
    } catch (e) {
      _log.error('PROFILE_UPDATE decrypt failed: $e');
      return;
    }

    try {
      final profile = proto.ProfileData.fromBuffer(payload);
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

  // ── Guardian Handlers ──────────────────────────────────────────────

  void _handleGuardianShareStore(proto.MessageEnvelope envelope) {
    try {
      final payload = _decryptPayload(envelope);
      guardianService.handleShareStore(envelope, payload);
    } catch (e) {
      _log.error('GUARDIAN_SHARE_STORE handler failed: $e');
    }
  }

  void _handleGuardianRestoreRequest(proto.MessageEnvelope envelope) {
    try {
      final payload = _decryptPayload(envelope);
      guardianService.handleRestoreRequest(envelope, payload);
    } catch (e) {
      _log.error('GUARDIAN_RESTORE_REQUEST handler failed: $e');
    }
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

  // ── Fragment Reassembly ────────────────────────────────────────────

  void _tryReassemble(Uint8List messageId) {
    final fragments = mailboxStore.getFragmentsForMessage(messageId);
    if (fragments.isEmpty) return;

    final first = fragments.first;
    if (fragments.length < first.requiredFragments) return;

    // Build fragment map
    final fragMap = <int, Uint8List>{};
    for (final f in fragments) {
      fragMap[f.fragmentIndex] = f.data;
    }

    try {
      final rs = ReedSolomon();
      final data = rs.decode(fragMap, first.originalSize);

      // Parse as MessageEnvelope
      final envelope = proto.MessageEnvelope.fromBuffer(data);
      handleMessage(envelope, InternetAddress.loopbackIPv4, 0);

      // Multi-device: do NOT delete fragments after reassembly.
      // A second device polling the same mailbox needs them too.
      // Fragments expire naturally via TTL (7 days).
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

    // Request fragments from all recent peers
    final peers = node.routingTable.allPeers;
    for (final peer in peers) {
      // Primary mailbox
      _requestFragments(peer, primaryMailboxId);
      // Fallback mailbox
      _requestFragments(peer, fallbackMailboxId);
    }

    _log.info('Mailbox poll sent to ${peers.length} peers');
  }

  void _requestFragments(PeerInfo peer, Uint8List mailboxId) {
    final req = proto.FragmentRetrieve()..mailboxId = mailboxId;
    final envelope = identity.createSignedEnvelope(
      proto.MessageType.FRAGMENT_RETRIEVE,
      req.writeToBuffer(),
      recipientId: peer.nodeId,
    );
    node.sendEnvelope(envelope, peer.nodeId);
  }

  /// Poll known peers for Store-and-Forward messages (startup + network change).
  void _pollStoredMessages() {
    final peers = node.routingTable.allPeers;
    var sent = 0;
    for (final peer in peers) {
      final retrieve = proto.PeerRetrieve()
        ..requesterNodeId = identity.nodeId;
      final env = identity.createSignedEnvelope(
        proto.MessageType.PEER_RETRIEVE,
        retrieve.writeToBuffer(),
        recipientId: peer.nodeId,
      );
      node.sendEnvelope(env, peer.nodeId);
      sent++;
    }
    if (sent > 0) {
      _log.info('Store-and-Forward poll sent to $sent peers');
    }
  }

  // ── Sending ────────────────────────────────────────────────────────

  /// Send a text message to a contact.
  @override
  Future<UiMessage?> sendTextMessage(String recipientNodeIdHex, String text, {String? forwardedFrom, String? replyToMessageId, String? replyToText, String? replyToSender}) async {
    final contact = _contacts[recipientNodeIdHex];
    if (contact == null || contact.status != 'accepted') {
      _log.warn('Cannot send to non-accepted contact: $recipientNodeIdHex');
      return null;
    }

    _maybeWriteStaleContactWarning(recipientNodeIdHex);

    // Show message in UI immediately (optimistic update)
    final tempId = bytesToHex(SodiumFFI().randomBytes(16));
    final msg = UiMessage(
      id: tempId,
      conversationId: recipientNodeIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: proto.MessageType.TEXT,
      status: MessageStatus.sending,
      isOutgoing: true,
      forwardedFrom: forwardedFrom,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSender: replyToSender,
    );
    _addMessageToConversation(recipientNodeIdHex, msg);

    // Yield to let UI repaint before heavy crypto work
    await Future.delayed(Duration.zero);

    var payload = Uint8List.fromList(utf8.encode(text));

    // Compress before encryption (encrypted data is incompressible)
    var compression = proto.CompressionType.NONE;
    if (payload.length >= 64) {
      try {
        final compressed = ZstdCompression.instance.compress(payload);
        if (compressed.length < payload.length) {
          payload = compressed;
          compression = proto.CompressionType.ZSTD;
        }
      } catch (_) {}
    }

    // Encrypt with Per-Message KEM
    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: payload,
      recipientX25519Pk: contact.x25519Pk!,
      recipientMlKemPk: contact.mlKemPk!,
    );

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.TEXT,
      ciphertext,
      recipientId: contact.nodeId,
      compress: false, // Already compressed before encryption
    );
    envelope.kemHeader = kemHeader;
    envelope.compression = compression;
    if (replyToMessageId != null) {
      envelope.replyToMessageId = hexToBytes(replyToMessageId);
      if (replyToText != null) envelope.replyToText = replyToText.length > 200 ? replyToText.substring(0, 200) : replyToText;
      if (replyToSender != null) envelope.replyToSender = replyToSender;
    }

    // Sender-side link preview (non-blocking, best-effort)
    if (_linkPreviewSettings.enabled && extractFirstUrl(text) != null) {
      try {
        final preview = await _linkPreviewFetcher.fetchPreview(text);
        if (preview != null) {
          envelope.linkPreview = preview.toProto();
          msg.linkPreviewUrl = preview.url;
          msg.linkPreviewTitle = preview.title;
          msg.linkPreviewDescription = preview.description;
          msg.linkPreviewSiteName = preview.siteName;
          if (preview.thumbnail != null) {
            msg.linkPreviewThumbnailBase64 = base64Encode(preview.thumbnail!);
          }
          onStateChanged?.call();
        }
      } catch (e) {
        _log.debug('Link preview fetch failed: $e');
      }
    }

    // Direct send (PoW runs in isolate via computeAsync)
    final sent = await node.sendEnvelope(envelope, contact.nodeId);
    _statsCollector.addMessageSent();

    // Update message with real ID and status
    final realMsgId = bytesToHex(Uint8List.fromList(envelope.messageId));
    msg.id = realMsgId;
    msg.status = sent ? MessageStatus.sent : MessageStatus.queued;
    onStateChanged?.call();

    // Erasure-coded backup (non-blocking)
    _storeErasureCodedBackup(envelope, contact);

    // Twin-Sync: notify other devices about sent message (§26)
    _sendTwinSync(proto.TwinSyncType.MESSAGE_SENT, Uint8List.fromList(utf8.encode(jsonEncode({
      'conversationId': recipientNodeIdHex,
      'text': text,
      'messageId': realMsgId,
      'timestamp': msg.timestamp.millisecondsSinceEpoch,
    }))));

    return msg;
  }

  /// Edit a previously sent message.
  @override
  Future<bool> editMessage(String conversationId, String messageId, String newText) async {
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

    // Build edit payload
    final editMsg = proto.MessageEdit()
      ..originalMessageId = hexToBytes(messageId)
      ..newText = newText
      ..editTimestamp = Int64(DateTime.now().millisecondsSinceEpoch);

    var basePayload = Uint8List.fromList(editMsg.writeToBuffer());

    // Group or DM?
    final group = _groups[conversationId];
    bool anySent = false;

    if (group != null) {
      // Pairwise fan-out to all group members
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final (x25519Pk, mlKemPk) = _resolveMemberKeys(member.nodeIdHex, memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk);
        if (x25519Pk == null || mlKemPk == null) continue;

        var payload = Uint8List.fromList(basePayload);
        var compression = proto.CompressionType.NONE;
        if (payload.length >= 64) {
          try {
            final compressed = ZstdCompression.instance.compress(payload);
            if (compressed.length < payload.length) {
              payload = compressed;
              compression = proto.CompressionType.ZSTD;
            }
          } catch (_) {}
        }

        final (kemHeader, ciphertext) = PerMessageKem.encrypt(
          plaintext: payload,
          recipientX25519Pk: x25519Pk,
          recipientMlKemPk: mlKemPk,
        );

        final envelope = identity.createSignedEnvelope(
          proto.MessageType.MESSAGE_EDIT,
          ciphertext,
          recipientId: hexToBytes(member.nodeIdHex),
          compress: false,
        );
        envelope.kemHeader = kemHeader;
        envelope.compression = compression;
        envelope.groupId = hexToBytes(conversationId);

        // Fire-and-forget: don't await — edit is applied locally
        node.sendEnvelope(envelope, hexToBytes(member.nodeIdHex));
        anySent = true;
      }
    } else {
      // DM
      final contact = _contacts[conversationId];
      if (contact == null || contact.status != 'accepted') return false;

      var payload = Uint8List.fromList(basePayload);
      var compression = proto.CompressionType.NONE;
      if (payload.length >= 64) {
        try {
          final compressed = ZstdCompression.instance.compress(payload);
          if (compressed.length < payload.length) {
            payload = compressed;
            compression = proto.CompressionType.ZSTD;
          }
        } catch (_) {}
      }

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: contact.x25519Pk!,
        recipientMlKemPk: contact.mlKemPk!,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.MESSAGE_EDIT,
        ciphertext,
        recipientId: contact.nodeId,
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      envelope.compression = compression;

      final sent = await node.sendEnvelope(envelope, contact.nodeId);
      if (sent) {
        anySent = true;
        _storeErasureCodedBackup(envelope, contact);
      }
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
    final conv = conversations[conversationId];
    if (conv == null) return false;

    final msgIndex = conv.messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return false;

    final original = conv.messages[msgIndex];

    // Only own messages
    if (!original.isOutgoing) return false;

    // Already deleted
    if (original.isDeleted) return false;

    // Build delete payload
    final deleteMsg = proto.MessageDelete()
      ..messageId = hexToBytes(messageId)
      ..deletedAt = Int64(DateTime.now().millisecondsSinceEpoch);

    var basePayload = Uint8List.fromList(deleteMsg.writeToBuffer());

    // Group or DM?
    final group = _groups[conversationId];
    bool anySent = false;

    if (group != null) {
      // Pairwise fan-out to all group members
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final (x25519Pk, mlKemPk) = _resolveMemberKeys(member.nodeIdHex, memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk);
        if (x25519Pk == null || mlKemPk == null) continue;

        var payload = Uint8List.fromList(basePayload);
        var compression = proto.CompressionType.NONE;
        if (payload.length >= 64) {
          try {
            final compressed = ZstdCompression.instance.compress(payload);
            if (compressed.length < payload.length) {
              payload = compressed;
              compression = proto.CompressionType.ZSTD;
            }
          } catch (_) {}
        }

        final (kemHeader, ciphertext) = PerMessageKem.encrypt(
          plaintext: payload,
          recipientX25519Pk: x25519Pk,
          recipientMlKemPk: mlKemPk,
        );

        final envelope = identity.createSignedEnvelope(
          proto.MessageType.MESSAGE_DELETE,
          ciphertext,
          recipientId: hexToBytes(member.nodeIdHex),
          compress: false,
        );
        envelope.kemHeader = kemHeader;
        envelope.compression = compression;
        envelope.groupId = hexToBytes(conversationId);

        // Fire-and-forget: don't await — delete is applied locally
        node.sendEnvelope(envelope, hexToBytes(member.nodeIdHex));
        anySent = true;
      }
    } else {
      // DM
      final contact = _contacts[conversationId];
      if (contact == null || contact.status != 'accepted') return false;

      var payload = Uint8List.fromList(basePayload);
      var compression = proto.CompressionType.NONE;
      if (payload.length >= 64) {
        try {
          final compressed = ZstdCompression.instance.compress(payload);
          if (compressed.length < payload.length) {
            payload = compressed;
            compression = proto.CompressionType.ZSTD;
          }
        } catch (_) {}
      }

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: contact.x25519Pk!,
        recipientMlKemPk: contact.mlKemPk!,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.MESSAGE_DELETE,
        ciphertext,
        recipientId: contact.nodeId,
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      envelope.compression = compression;

      final sent = await node.sendEnvelope(envelope, contact.nodeId);
      if (sent) {
        anySent = true;
        _storeErasureCodedBackup(envelope, contact);
      }
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

  /// Send a CHAT_CONFIG_UPDATE message to a contact.
  void _sendChatConfigUpdate(ContactInfo contact, String conversationId, ChatConfig config, {required bool isRequest, bool accepted = false, String? groupIdHex}) {
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

    var payload = Uint8List.fromList(configMsg.writeToBuffer());
    var compression = proto.CompressionType.NONE;
    if (payload.length >= 64) {
      try {
        final compressed = ZstdCompression.instance.compress(payload);
        if (compressed.length < payload.length) {
          payload = compressed;
          compression = proto.CompressionType.ZSTD;
        }
      } catch (_) {}
    }

    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: payload,
      recipientX25519Pk: contact.x25519Pk!,
      recipientMlKemPk: contact.mlKemPk!,
    );

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CHAT_CONFIG_UPDATE,
      ciphertext,
      recipientId: contact.nodeId,
      compress: false,
    );
    envelope.kemHeader = kemHeader;
    envelope.compression = compression;
    if (groupIdHex != null) {
      envelope.groupId = hexToBytes(groupIdHex);
    }

    node.sendEnvelope(envelope, contact.nodeId);
  }

  /// Handle incoming CHAT_CONFIG_UPDATE from a peer.
  void _handleChatConfigUpdate(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt payload
    proto.ChatConfigUpdate configMsg;
    try {
      Uint8List payload;
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
      configMsg = proto.ChatConfigUpdate.fromBuffer(payload);
    } catch (e) {
      _log.error('CHAT_CONFIG_UPDATE decrypt/parse failed: $e');
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
    final groupIdHex = envelope.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(envelope.groupId))
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
  Future<void> _storeErasureCodedBackup(proto.MessageEnvelope envelope, ContactInfo? contact, {Uint8List? recipientNodeId}) async {
    try {
      final rs = ReedSolomon();
      final data = envelope.writeToBuffer();
      final fragments = rs.encode(Uint8List.fromList(data));

      // Compute mailbox ID
      final sodium = SodiumFFI();
      Uint8List mailboxId;
      if (contact?.ed25519Pk != null && contact!.ed25519Pk!.isNotEmpty) {
        mailboxId = sodium.sha256(Uint8List.fromList([...utf8.encode('mailbox'), ...contact.ed25519Pk!]));
      } else {
        final nodeId = contact?.nodeId ?? recipientNodeId!;
        mailboxId = sodium.sha256(Uint8List.fromList([...utf8.encode('mailbox-nid'), ...nodeId]));
      }

      final messageId = Uint8List.fromList(envelope.messageId);
      final peers = node.routingTable.findClosestPeers(mailboxId, count: 10);

      for (var i = 0; i < fragments.length; i++) {
        final fragStore = proto.FragmentStore()
          ..mailboxId = mailboxId
          ..messageId = messageId
          ..fragmentIndex = i
          ..totalFragments = fragments.length
          ..requiredFragments = ReedSolomon.defaultK
          ..fragmentData = fragments[i]
          ..originalSize = data.length;

        final fragEnv = identity.createSignedEnvelope(
          proto.MessageType.FRAGMENT_STORE,
          fragStore.writeToBuffer(),
        );

        // Send to the peer at index i % peerCount
        if (peers.isNotEmpty) {
          final targetPeer = peers[i % peers.length];
          node.sendEnvelope(fragEnv, targetPeer.nodeId);
        }
      }
    } catch (e) {
      _log.debug('Erasure backup failed: $e');
    }
  }

  /// Add peers from a scanned ContactSeed QR code to the routing table.
  /// This ensures the target node and its seed peers are reachable before sending a CR.
  @override
  void addPeersFromContactSeed(
    String targetNodeIdHex,
    List<String> targetAddresses,
    List<({String nodeIdHex, List<String> addresses})> seedPeers,
  ) {
    // Add the target node itself — always, even without addresses.
    // Without addresses the Three-Layer Cascade will relay via seed peers.
    final targetNodeId = hexToBytes(targetNodeIdHex);
    final addresses = <PeerAddress>[];
    for (final addr in targetAddresses) {
      final parsed = _parseAddrString(addr);
      if (parsed != null) {
        addresses.add(PeerAddress(ip: parsed.$1, port: parsed.$2));
      }
    }
    final targetPeer = PeerInfo(nodeId: targetNodeId, addresses: addresses)
      ..isProtectedSeed = true; // Survive Doze pruning (§27)
    node.routingTable.addPeer(targetPeer);
    _log.info('QR seed: added target ${targetNodeIdHex.substring(0, 8)} with ${addresses.length} addresses (protected)');

    // Add seed peers (bootstrap, mutual contacts, etc.)
    for (final sp in seedPeers) {
      final peerNodeId = hexToBytes(sp.nodeIdHex);
      final addresses = <PeerAddress>[];
      for (final addr in sp.addresses) {
        final parsed = _parseAddrString(addr);
        if (parsed != null) {
          // High initial score — these peers were recommended by the contact as reachable.
          addresses.add(PeerAddress(ip: parsed.$1, port: parsed.$2)..score = 0.95);
        }
      }
      if (addresses.isNotEmpty) {
        final seedPeer = PeerInfo(nodeId: peerNodeId, addresses: addresses)
          ..isProtectedSeed = true; // Survive Doze pruning (§27)
        node.routingTable.addPeer(seedPeer);
        _log.info('QR seed: added peer ${sp.nodeIdHex.substring(0, 8)} with ${addresses.length} addresses (protected)');
        // Ping seed peer to establish connection
        for (final addr in addresses) {
          node.sendPing(addr.ip, addr.port);
        }
      }
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

    // Send PING to the address — if a node is listening there,
    // it will respond with PONG, which registers it in our routing table
    // and triggers PeerExchange (standard Kademlia bootstrap flow).
    node.sendPing(ip, port);
    _log.info('Manual peer entry: PING sent to $ip:$port');
    return true;
  }

  /// Send a contact request.
  /// If the contact already exists as "accepted", re-sends CR with fresh keys
  /// so the remote side can re-establish the relationship (e.g. after data loss).
  @override
  Future<bool> sendContactRequest(String recipientNodeIdHex, {String message = ''}) async {
    final existing = _contacts[recipientNodeIdHex];
    final isReContact = existing != null && existing.status == 'accepted';

    final recipientNodeId = hexToBytes(recipientNodeIdHex);

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

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CONTACT_REQUEST,
      cr.writeToBuffer(),
      recipientId: recipientNodeId,
    );

    if (isReContact) {
      // Re-contact: send CR with fresh keys but keep "accepted" status.
      // Remote side handles this in _handleContactRequest as "re-contact from accepted".
      _log.info('Re-contact to accepted ${existing.displayName} — sending CR with fresh keys');
    } else {
      // New contact: store as pending
      _contacts[recipientNodeIdHex] = ContactInfo(
        nodeId: recipientNodeId,
        displayName: 'Pending...',
        status: 'pending_outgoing',
      );
      _saveContacts();
    }

    _log.info('Sending CONTACT_REQUEST to ${recipientNodeIdHex.substring(0, 8)} '
        '(envelope size: ${envelope.writeToBuffer().length} bytes)');
    final sent = await node.sendEnvelope(envelope, recipientNodeId);
    _log.info('CONTACT_REQUEST sendEnvelope result: $sent');

    // Erasure-coded backup on DHT peers (offline delivery)
    _storeErasureCodedBackup(envelope, null, recipientNodeId: recipientNodeId);

    // Always return true — delivery via relay/S&F may succeed even if direct fails.
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
        type: proto.MessageType.IDENTITY_DELETED, // system message type
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

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CONTACT_REQUEST_RESPONSE,
      resp.writeToBuffer(),
      recipientId: contact.nodeId,
    );

    onContactAccepted?.call(nodeIdHex);
    onStateChanged?.call();
    final sent = await node.sendEnvelope(envelope, contact.nodeId);
    // Erasure-coded backup for offline delivery
    _storeErasureCodedBackup(envelope, contact);

    // Twin-Sync: notify other devices about accepted contact (§26)
    _sendTwinSync(proto.TwinSyncType.CONTACT_ADDED, Uint8List.fromList(utf8.encode(jsonEncode({
      'nodeId': nodeIdHex,
      'displayName': contact.displayName,
      if (contact.ed25519Pk != null) 'ed25519Pk': bytesToHex(contact.ed25519Pk!),
      if (contact.x25519Pk != null) 'x25519Pk': bytesToHex(contact.x25519Pk!),
      if (contact.mlKemPk != null) 'mlKemPk': bytesToHex(contact.mlKemPk!),
      if (contact.mlDsaPk != null) 'mlDsaPk': bytesToHex(contact.mlDsaPk!),
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

  void _sendDeliveryReceipt(Uint8List recipientId, Uint8List messageId, {bool preferRelay = false}) {
    final receipt = proto.DeliveryReceipt()
      ..messageId = messageId
      ..deliveredAt = Int64(DateTime.now().millisecondsSinceEpoch);

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.DELIVERY_RECEIPT,
      receipt.writeToBuffer(),
      recipientId: recipientId,
    );

    if (preferRelay) {
      // V3.1 "Reply via same path": message came via relay, so send receipt
      // via the SAME specific relay. Direct to LAN IPs may fail (AP isolation).
      final recipientHex = bytesToHex(recipientId);
      final peer = node.routingTable.getPeer(recipientId);

      // Use the learned specific relay route (e.g. via Bootstrap)
      if (peer != null && peer.relayViaNodeId != null) {
        final relayPeer = node.routingTable.getPeer(peer.relayViaNodeId!);
        if (relayPeer != null) {
          _log.debug('DELIVERY_RECEIPT via specific relay ${relayPeer.nodeIdHex.substring(0, 8)} for ${recipientHex.substring(0, 8)}');
          node.sendViaNextHopPublic(envelope, recipientId, relayPeer);
          return;
        }
      }

      // Fallback: DV next-hop relay
      final route = node.dvRouting.bestRouteTo(recipientHex);
      if (route != null && !route.isDirect && route.nextHop != null) {
        final nextHopPeer = node.routingTable.getPeer(route.nextHop!);
        if (nextHopPeer != null) {
          _log.debug('DELIVERY_RECEIPT via DV relay ${nextHopPeer.nodeIdHex.substring(0, 8)} for ${recipientHex.substring(0, 8)}');
          node.sendViaNextHopPublic(envelope, recipientId, nextHopPeer);
          return;
        }
      }
    }

    node.sendEnvelope(envelope, recipientId);
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
      type: proto.MessageType.IDENTITY_DELETED,
      status: MessageStatus.delivered,
    );
    conv.messages.add(systemMsg);
    _saveConversations();
    _log.info('Stale sender-side warning for ${userIdHex.substring(0, 8)} (${contact.displayName})');
    onStateChanged?.call();
  }

  // ── CR Retry ───────────────────────────────────────────────────────

  void _retryPendingContactRequests() {
    final now = DateTime.now();
    final pending = _contacts.entries
        .where((e) => e.value.status == 'pending_outgoing')
        .where((e) => !_deletedContacts.contains(e.key))
        .toList();

    for (final entry in pending) {
      final recipientNodeId = entry.value.nodeId;
      // Exponential backoff: 10s, 20s, 40s, 80s, 160s, 320s, capped at 600s.
      // ML-DSA signing + erasure-coded backup per retry is expensive — without
      // backoff we'd flood unreachable contacts with CR + erasure writes every 10s
      // indefinitely.
      final count = _crRetryCountPerContact[entry.key] ?? 0;
      final shift = count > 6 ? 6 : count;
      final backoffSec = 10 * (1 << shift) > 600 ? 600 : 10 * (1 << shift);
      final lastRetry = _lastCrRetryPerContact[entry.key];
      if (lastRetry != null && now.difference(lastRetry).inSeconds < backoffSec) continue;

      // Only retry if peer is in routing table (known peer)
      if (node.routingTable.getPeer(recipientNodeId) == null) continue;

      final cr = proto.ContactRequestMsg()
        ..displayName = displayName
        ..ed25519PublicKey = identity.ed25519PublicKey
        ..mlDsaPublicKey = identity.mlDsaPublicKey
        ..x25519PublicKey = identity.x25519PublicKey
        ..mlKemPublicKey = identity.mlKemPublicKey;

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.CONTACT_REQUEST,
        cr.writeToBuffer(),
        recipientId: recipientNodeId,
      );

      node.sendEnvelope(envelope, recipientNodeId);
      // Also store erasure-coded backup for offline delivery
      _storeErasureCodedBackup(envelope, null, recipientNodeId: recipientNodeId);
      _lastCrRetryPerContact[entry.key] = now;
      _crRetryCountPerContact[entry.key] = count + 1;
      _log.debug('CR retry to ${entry.key.substring(0, 8)} (attempt ${count + 1}, backoff ${backoffSec}s)');
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
      if (node.routingTable.getPeer(contact.nodeId) == null) continue;

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

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.CONTACT_REQUEST_RESPONSE,
        resp.writeToBuffer(),
        recipientId: contact.nodeId,
      );

      node.sendEnvelope(envelope, contact.nodeId);
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
    if (conv.unreadCount == 0) return;

    conv.unreadCount = 0;
    onCancelNotificationAndroid?.call(conversationId);
    _updateBadgeCount();

    // Send READ_RECEIPTs for unread incoming messages (if readReceipts enabled)
    if (!conv.config.readReceipts) return;

    for (final msg in conv.messages) {
      if (!msg.isOutgoing && msg.status != MessageStatus.read) {
        msg.status = MessageStatus.read;
        // Send receipt to original sender
        final senderNodeId = hexToBytes(msg.senderNodeIdHex);
        final receipt = proto.ReadReceipt()
          ..messageId = hexToBytes(msg.id)
          ..readAt = Int64(DateTime.now().millisecondsSinceEpoch);
        final envelope = identity.createSignedEnvelope(
          proto.MessageType.READ_RECEIPT,
          receipt.writeToBuffer(),
          recipientId: senderNodeId,
        );
        node.sendEnvelope(envelope, senderNodeId);
      }
    }

    _saveConversations();
    onStateChanged?.call();

    // Twin-Sync: notify other devices that this conversation was read (§26)
    _sendTwinSync(proto.TwinSyncType.TWIN_READ_RECEIPT, Uint8List.fromList(utf8.encode(jsonEncode({
      'conversationId': conversationId,
    }))));
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
    final envelope = identity.createSignedEnvelope(
      proto.MessageType.TYPING_INDICATOR,
      indicator.writeToBuffer(),
      recipientId: contact.nodeId,
    );
    node.sendEnvelope(envelope, contact.nodeId);
  }

  // ── Mutual Peer Selection (Architecture Section 3.3.7) ─────────

  /// Compute set of nodeIdHex that the recipient is likely to know.
  /// Sources: shared contacts (bidirectional) + shared group members.
  Set<String> _computeMutualPeerIds(Uint8List recipientNodeId) {
    final recipientHex = bytesToHex(recipientNodeId);
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
    final invite = proto.GroupInvite()
      ..groupId = groupId
      ..groupName = name
      ..inviterId = identity.nodeId;
    for (final m in members.values) {
      invite.members.add(proto.GroupMember()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role
        ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
        ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
        ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0));
    }

    final inviteBytes = invite.writeToBuffer();
    for (final m in members.values) {
      if (m.nodeIdHex == identity.userIdHex) continue; // Don't send to self
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(m.nodeIdHex, memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;

      var payload = Uint8List.fromList(inviteBytes);
      var compression = proto.CompressionType.NONE;
      if (payload.length >= 64) {
        try {
          final compressed = ZstdCompression.instance.compress(payload);
          if (compressed.length < payload.length) {
            payload = compressed;
            compression = proto.CompressionType.ZSTD;
          }
        } catch (_) {}
      }

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: x25519Pk,
        recipientMlKemPk: mlKemPk,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.GROUP_INVITE,
        ciphertext,
        recipientId: hexToBytes(m.nodeIdHex),
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      envelope.compression = compression;

      // Fire-and-forget: don't await — group is already saved locally
      node.sendEnvelope(envelope, hexToBytes(m.nodeIdHex));
    }

    onStateChanged?.call();
    _log.info('Group "$name" created with ${members.length} members: $groupIdHex');
    return groupIdHex;
  }

  @override
  Future<UiMessage?> sendGroupTextMessage(String groupIdHex, String text) async {
    final group = _groups[groupIdHex];
    if (group == null) return null;

    var payload = Uint8List.fromList(utf8.encode(text));
    var compression = proto.CompressionType.NONE;
    if (payload.length >= 64) {
      try {
        final compressed = ZstdCompression.instance.compress(payload);
        if (compressed.length < payload.length) {
          payload = compressed;
          compression = proto.CompressionType.ZSTD;
        }
      } catch (_) {}
    }

    String? firstMsgId;

    // Fan-out: send to each member pairwise
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(member.nodeIdHex, memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: x25519Pk,
        recipientMlKemPk: mlKemPk,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.TEXT,
        ciphertext,
        recipientId: hexToBytes(member.nodeIdHex),
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      envelope.compression = compression;
      envelope.groupId = hexToBytes(groupIdHex);

      firstMsgId ??= bytesToHex(Uint8List.fromList(envelope.messageId));

      // Fire-and-forget: don't await — optimistic UI
      node.sendEnvelope(envelope, hexToBytes(member.nodeIdHex));
    }

    if (firstMsgId == null) return null;
    _statsCollector.addMessageSent();

    // Create single UI message
    final msg = UiMessage(
      id: firstMsgId,
      conversationId: groupIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: proto.MessageType.TEXT,
      status: MessageStatus.sent,
      isOutgoing: true,
    );

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
      _broadcastGroupUpdate(group);
    }

    // Also send GROUP_LEAVE so members know we left (fire-and-forget)
    final leaveMsg = proto.GroupLeave()..groupId = hexToBytes(groupIdHex);
    final leaveBytes = leaveMsg.writeToBuffer();
    for (final member in group.members.values) {
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(member.nodeIdHex, memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: Uint8List.fromList(leaveBytes),
        recipientX25519Pk: x25519Pk,
        recipientMlKemPk: mlKemPk,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.GROUP_LEAVE,
        ciphertext,
        recipientId: hexToBytes(member.nodeIdHex),
        compress: false,
      );
      envelope.kemHeader = kemHeader;

      node.sendEnvelope(envelope, hexToBytes(member.nodeIdHex));
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
    _broadcastGroupUpdate(group);

    // System message
    final sysMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: groupIdHex,
      senderNodeIdHex: '',
      text: '${contact.displayName} wurde eingeladen',
      timestamp: DateTime.now(),
      type: proto.MessageType.GROUP_INVITE,
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
    _broadcastGroupUpdate(group);

    // System message
    final sysMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: groupIdHex,
      senderNodeIdHex: '',
      text: '$memberName wurde entfernt',
      timestamp: DateTime.now(),
      type: proto.MessageType.GROUP_LEAVE,
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
    // Dual-mode: works for both groups and channels (Architecture v2.2 Section 10.2)
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
      _broadcastGroupUpdate(group);
      _broadcastRoleUpdate(entityIdHex, memberNodeIdHex, role, group.members);

      final sysMsg = UiMessage(
        id: bytesToHex(SodiumFFI().randomBytes(16)),
        conversationId: entityIdHex,
        senderNodeIdHex: '',
        text: '${member.displayName}: $oldRole → $role',
        timestamp: DateTime.now(),
        type: proto.MessageType.CHANNEL_ROLE_UPDATE,
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
        type: proto.MessageType.CHANNEL_ROLE_UPDATE,
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
  /// Architecture v2.2: "must be sent to ALL members, not just the affected member"
  void _broadcastRoleUpdate(String entityIdHex, String targetIdHex, String newRole,
      Map<String, dynamic> members) {
    final roleUpdate = proto.ChannelRoleUpdate()
      ..channelId = hexToBytes(entityIdHex)
      ..targetId = hexToBytes(targetIdHex)
      ..newRole = newRole;

    final roleBytes = roleUpdate.writeToBuffer();
    for (final entry in members.entries) {
      final mHex = entry.key;
      if (mHex == identity.userIdHex) continue;
      final m = entry.value;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(mHex,
          memberX25519Pk: m.x25519Pk as Uint8List?, memberMlKemPk: m.mlKemPk as Uint8List?);
      if (x25519Pk == null || mlKemPk == null) continue;

      var payload = Uint8List.fromList(roleBytes);
      var compression = proto.CompressionType.NONE;
      if (payload.length >= 64) {
        try {
          final compressed = ZstdCompression.instance.compress(payload);
          if (compressed.length < payload.length) {
            payload = compressed;
            compression = proto.CompressionType.ZSTD;
          }
        } catch (_) {}
      }

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: x25519Pk,
        recipientMlKemPk: mlKemPk,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.CHANNEL_ROLE_UPDATE,
        ciphertext,
        recipientId: hexToBytes(mHex),
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      envelope.compression = compression;

      node.sendEnvelope(envelope, hexToBytes(mHex));
    }
  }

  /// Broadcast updated group member list to all members via GROUP_INVITE.
  void _broadcastGroupUpdate(GroupInfo group) {
    final groupId = hexToBytes(group.groupIdHex);
    final invite = proto.GroupInvite()
      ..groupId = groupId
      ..groupName = group.name
      ..inviterId = identity.nodeId;
    for (final m in group.members.values) {
      invite.members.add(proto.GroupMember()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role
        ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
        ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
        ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0));
    }

    final inviteBytes = invite.writeToBuffer();
    for (final m in group.members.values) {
      if (m.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(m.nodeIdHex, memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;

      var payload = Uint8List.fromList(inviteBytes);
      var compression = proto.CompressionType.NONE;
      if (payload.length >= 64) {
        try {
          final compressed = ZstdCompression.instance.compress(payload);
          if (compressed.length < payload.length) {
            payload = compressed;
            compression = proto.CompressionType.ZSTD;
          }
        } catch (_) {}
      }

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: x25519Pk,
        recipientMlKemPk: mlKemPk,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.GROUP_INVITE,
        ciphertext,
        recipientId: hexToBytes(m.nodeIdHex),
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      envelope.compression = compression;

      // Fire-and-forget: don't await — broadcast is best-effort
      node.sendEnvelope(envelope, hexToBytes(m.nodeIdHex));
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

  void _handleGroupInvite(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt
    proto.GroupInvite invite;
    try {
      Uint8List payload;
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
      invite = proto.GroupInvite.fromBuffer(payload);
    } catch (e) {
      _log.error('GROUP_INVITE decrypt/parse failed: $e');
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

  void _handleGroupLeave(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt
    proto.GroupLeave leaveMsg;
    try {
      Uint8List payload;
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
      leaveMsg = proto.GroupLeave.fromBuffer(payload);
    } catch (e) {
      _log.error('GROUP_LEAVE decrypt/parse failed: $e');
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
      type: proto.MessageType.GROUP_LEAVE,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    _addMessageToConversation(groupIdHex, sysMsg, isGroup: true);
    _log.info('$memberName left group "${group.name}"');
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
    final channel = _channels[channelIdHex];
    if (channel == null) return null;

    // Only owner/admin can post
    if (!_hasChannelPermission(channel, 'post')) {
      _log.warn('No permission to post in channel');
      return null;
    }

    var payload = Uint8List.fromList(utf8.encode(text));
    var compression = proto.CompressionType.NONE;
    if (payload.length >= 64) {
      try {
        final compressed = ZstdCompression.instance.compress(payload);
        if (compressed.length < payload.length) {
          payload = compressed;
          compression = proto.CompressionType.ZSTD;
        }
      } catch (_) {}
    }

    String? firstMsgId;

    // Fan-out: send to each member pairwise (same as groups)
    for (final member in channel.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(member.nodeIdHex, memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: x25519Pk,
        recipientMlKemPk: mlKemPk,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.CHANNEL_POST,
        ciphertext,
        recipientId: hexToBytes(member.nodeIdHex),
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      envelope.compression = compression;
      envelope.groupId = hexToBytes(channelIdHex); // reuse groupId field for channel routing

      firstMsgId ??= bytesToHex(Uint8List.fromList(envelope.messageId));

      // Fire-and-forget: don't await — optimistic UI
      node.sendEnvelope(envelope, hexToBytes(member.nodeIdHex));
    }

    // If no other members received the post, generate a local message ID
    // (e.g. owner-only public channel — post is stored locally for future subscribers)
    firstMsgId ??= bytesToHex(SodiumFFI().randomBytes(16));
    _statsCollector.addMessageSent();

    // Create single UI message
    final msg = UiMessage(
      id: firstMsgId,
      conversationId: channelIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: proto.MessageType.CHANNEL_POST,
      status: MessageStatus.sent,
      isOutgoing: true,
    );

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

    // Send CHANNEL_LEAVE so members know we left (fire-and-forget)
    final leaveMsg = proto.ChannelLeave()..channelId = hexToBytes(channelIdHex);
    final leaveBytes = leaveMsg.writeToBuffer();
    for (final member in channel.members.values) {
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(member.nodeIdHex, memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: Uint8List.fromList(leaveBytes),
        recipientX25519Pk: x25519Pk,
        recipientMlKemPk: mlKemPk,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.CHANNEL_LEAVE,
        ciphertext,
        recipientId: hexToBytes(member.nodeIdHex),
        compress: false,
      );
      envelope.kemHeader = kemHeader;

      node.sendEnvelope(envelope, hexToBytes(member.nodeIdHex));
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
      type: proto.MessageType.CHANNEL_INVITE,
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
      type: proto.MessageType.CHANNEL_LEAVE,
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
    final channel = _channels[channelIdHex];
    if (channel == null) return false;
    if (!['owner', 'admin', 'subscriber'].contains(role)) return false;

    // Only owner can change roles
    if (channel.ownerNodeIdHex != identity.userIdHex) return false;
    if (memberNodeIdHex == identity.userIdHex) return false;

    final member = channel.members[memberNodeIdHex];
    if (member == null) return false;

    final oldRole = member.role;
    member.role = role;

    // If promoting to owner, demote self to admin
    if (role == 'owner') {
      channel.members[identity.userIdHex]?.role = 'admin';
      channel.ownerNodeIdHex = memberNodeIdHex;
    }

    _saveChannels();

    // Broadcast updated member list
    _broadcastChannelUpdate(channel);

    // System message
    final sysMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: channelIdHex,
      senderNodeIdHex: '',
      text: '${member.displayName}: $oldRole → $role',
      timestamp: DateTime.now(),
      type: proto.MessageType.CHANNEL_INVITE,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    _addMessageToConversation(channelIdHex, sysMsg, isChannel: true);

    onStateChanged?.call();
    _log.info('Channel role changed: ${member.displayName} $oldRole -> $role in "${channel.name}"');
    return true;
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
      invite.members.add(proto.GroupMember() // reuse GroupMember proto
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role
        ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
        ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
        ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0));
    }

    final inviteBytes = invite.writeToBuffer();
    for (final m in channel.members.values) {
      if (m.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk) = _resolveMemberKeys(m.nodeIdHex, memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk);
      if (x25519Pk == null || mlKemPk == null) continue;

      var payload = Uint8List.fromList(inviteBytes);
      var compression = proto.CompressionType.NONE;
      if (payload.length >= 64) {
        try {
          final compressed = ZstdCompression.instance.compress(payload);
          if (compressed.length < payload.length) {
            payload = compressed;
            compression = proto.CompressionType.ZSTD;
          }
        } catch (_) {}
      }

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: x25519Pk,
        recipientMlKemPk: mlKemPk,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.CHANNEL_INVITE,
        ciphertext,
        recipientId: hexToBytes(m.nodeIdHex),
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      envelope.compression = compression;

      // Fire-and-forget: don't await — broadcast is best-effort
      node.sendEnvelope(envelope, hexToBytes(m.nodeIdHex));
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

  // ── Decrypt helper ─────────────────────────────────────────────

  /// Decrypt an incoming KEM-encrypted envelope. Returns null on failure.
  _DecryptedEnvelope? _decryptEnvelope(proto.MessageEnvelope envelope) {
    try {
      Uint8List payload;
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
      return _DecryptedEnvelope(payload);
    } catch (e) {
      _log.debug('Decrypt failed for ${envelope.messageType}: $e');
      return null;
    }
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

    final payload = exchangeMsg.writeToBuffer();
    for (final peer in targets) {
      final envelope = identity.createSignedEnvelope(
        proto.MessageType.CHANNEL_INDEX_EXCHANGE,
        Uint8List.fromList(payload),
        recipientId: peer.nodeId,
      );
      node.sendEnvelope(envelope, peer.nodeId);
    }
    _log.debug('Channel index gossip: sent ${entries.length} entries to ${targets.length} peers');
  }

  /// Handle incoming channel index exchange from a peer.
  void _handleChannelIndexExchange(proto.MessageEnvelope envelope) {
    try {
      final exchange = proto.ChannelIndexExchange.fromBuffer(envelope.encryptedPayload);
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
  void _handleChannelJoinRequest(proto.MessageEnvelope envelope) {
    try {
      final decrypted = _decryptEnvelope(envelope);
      if (decrypted == null) return;

      final joinReq = proto.ChannelJoinRequest.fromBuffer(decrypted.payload);
      final channelIdHex = bytesToHex(Uint8List.fromList(joinReq.channelId));
      final channel = _channels[channelIdHex];
      if (channel == null || !channel.isPublic) {
        _log.debug('Join request for unknown/private channel $channelIdHex');
        return;
      }

      // Only owner processes join requests
      if (channel.ownerNodeIdHex != identity.userIdHex) return;

      final requesterNodeIdHex = bytesToHex(Uint8List.fromList(envelope.senderId));

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
      final gm = proto.GroupMember()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role;
      if (m.ed25519Pk != null) gm.ed25519PublicKey = m.ed25519Pk!;
      if (m.x25519Pk != null) gm.x25519PublicKey = m.x25519Pk!;
      if (m.mlKemPk != null) gm.mlKemPublicKey = m.mlKemPk!;
      invite.members.add(gm);
    }

    // Encrypt and send
    final (x25519Pk, mlKemPk) = _resolveMemberKeys(memberNodeIdHex,
        memberX25519Pk: memberInfo.x25519Pk, memberMlKemPk: memberInfo.mlKemPk);
    if (x25519Pk == null || mlKemPk == null) return;

    final payload = invite.writeToBuffer();
    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: Uint8List.fromList(payload),
      recipientX25519Pk: x25519Pk,
      recipientMlKemPk: mlKemPk,
    );

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CHANNEL_INVITE,
      ciphertext,
      recipientId: hexToBytes(memberNodeIdHex),
    );
    envelope.kemHeader = kemHeader;

    await node.sendEnvelope(envelope, hexToBytes(memberNodeIdHex));
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

    // Send join request to owner
    final ownerNodeId = hexToBytes(entry.ownerNodeIdHex);
    final ownerContact = _contacts[entry.ownerNodeIdHex];
    if (ownerContact?.x25519Pk != null && ownerContact?.mlKemPk != null) {
      final joinReq = proto.ChannelJoinRequest()
        ..channelId = hexToBytes(channelIdHex)
        ..displayName = displayName
        ..ed25519Pk = identity.ed25519PublicKey
        ..x25519Pk = identity.x25519PublicKey
        ..mlKemPk = identity.mlKemPublicKey;

      final payload = joinReq.writeToBuffer();
      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: Uint8List.fromList(payload),
        recipientX25519Pk: ownerContact!.x25519Pk!,
        recipientMlKemPk: ownerContact.mlKemPk!,
      );
      final envelope = identity.createSignedEnvelope(
        proto.MessageType.CHANNEL_JOIN_REQUEST,
        ciphertext,
        recipientId: ownerNodeId,
      );
      envelope.kemHeader = kemHeader;
      await node.sendEnvelope(envelope, ownerNodeId);
      _log.info('Sent join request for public channel "${entry.name}" to owner');
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

    final payload = juryReq.writeToBuffer();
    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: Uint8List.fromList(payload),
      recipientX25519Pk: juror.x25519Pk!,
      recipientMlKemPk: juror.mlKemPk!,
    );

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.JURY_REQUEST,
      ciphertext,
      recipientId: hexToBytes(juror.nodeIdHex),
    );
    envelope.kemHeader = kemHeader;
    node.sendEnvelope(envelope, hexToBytes(juror.nodeIdHex));
  }

  /// Handle incoming JuryRequest (we've been selected as juror).
  void _handleIncomingJuryRequest(proto.MessageEnvelope envelope) {
    try {
      final decrypted = _decryptEnvelope(envelope);
      if (decrypted == null) return;

      final msg = proto.JuryRequestMsg.fromBuffer(decrypted.payload);
      final juryId = bytesToHex(Uint8List.fromList(msg.juryId));
      final reportId = bytesToHex(Uint8List.fromList(msg.reportId));
      final channelIdHex = bytesToHex(Uint8List.fromList(msg.channelId));
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

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

        final payload = voteMsg.writeToBuffer();
        final (kemHeader, ciphertext) = PerMessageKem.encrypt(
          plaintext: Uint8List.fromList(payload),
          recipientX25519Pk: contact!.x25519Pk!,
          recipientMlKemPk: contact.mlKemPk!,
        );

        final envelope = identity.createSignedEnvelope(
          proto.MessageType.JURY_VOTE_MSG,
          ciphertext,
          recipientId: hexToBytes(request.requesterNodeIdHex!),
        );
        envelope.kemHeader = kemHeader;
        await node.sendEnvelope(envelope, hexToBytes(request.requesterNodeIdHex!));
      }
    }

    _log.info('Jury vote submitted for $juryId: ${JuryVoteResult.values[vote].name}');
    return true;
  }

  /// Handle incoming jury vote (we initiated this jury).
  void _handleIncomingJuryVote(proto.MessageEnvelope envelope) {
    try {
      final decrypted = _decryptEnvelope(envelope);
      if (decrypted == null) return;

      final msg = proto.JuryVoteMsg.fromBuffer(decrypted.payload);
      final juryId = bytesToHex(Uint8List.fromList(msg.juryId));
      final voterHex = bytesToHex(Uint8List.fromList(envelope.senderId));

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

    final payload = resultMsg.writeToBuffer();

    for (final jurorId in session.jurorNodeIds) {
      final contact = _contacts[jurorId];
      if (contact?.x25519Pk == null || contact?.mlKemPk == null) continue;

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: Uint8List.fromList(payload),
        recipientX25519Pk: contact!.x25519Pk!,
        recipientMlKemPk: contact.mlKemPk!,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.JURY_RESULT,
        ciphertext,
        recipientId: hexToBytes(jurorId),
      );
      envelope.kemHeader = kemHeader;
      node.sendEnvelope(envelope, hexToBytes(jurorId));
    }
  }

  /// Handle incoming jury result (we were a juror).
  void _handleIncomingJuryResult(proto.MessageEnvelope envelope) {
    try {
      final decrypted = _decryptEnvelope(envelope);
      if (decrypted == null) return;

      final msg = proto.JuryResultMsg.fromBuffer(decrypted.payload);
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
  void _handleIncomingChannelReport(proto.MessageEnvelope envelope) {
    try {
      final decrypted = _decryptEnvelope(envelope);
      if (decrypted == null) return;

      final msg = proto.ChannelReportMsg.fromBuffer(decrypted.payload);
      final channelIdHex = bytesToHex(Uint8List.fromList(msg.channelId));
      final reportId = bytesToHex(Uint8List.fromList(msg.reportId));
      final reporterHex = bytesToHex(Uint8List.fromList(envelope.senderId));

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

  void _handleChannelInvite(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt
    proto.ChannelInvite invite;
    try {
      Uint8List payload;
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
      invite = proto.ChannelInvite.fromBuffer(payload);
    } catch (e) {
      _log.error('CHANNEL_INVITE decrypt/parse failed: $e');
      return;
    }

    final channelIdHex = bytesToHex(Uint8List.fromList(invite.channelId));

    // Build members map from the repeated GroupMember field
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

  void _handleChannelLeave(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt
    proto.ChannelLeave leaveMsg;
    try {
      Uint8List payload;
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
      leaveMsg = proto.ChannelLeave.fromBuffer(payload);
    } catch (e) {
      _log.error('CHANNEL_LEAVE decrypt/parse failed: $e');
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
      type: proto.MessageType.CHANNEL_LEAVE,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    _addMessageToConversation(channelIdHex, sysMsg, isChannel: true);
    _log.info('$memberName left channel "${channel.name}"');
  }

  /// Handle CHANNEL_ROLE_UPDATE (type 73): update member role in channel or group.
  /// Architecture v2.2 Section 10.2: sent to ALL members, handler checks both
  /// channelManager and groupManager. Only owner/admin may change roles.
  void _handleChannelRoleUpdate(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Decrypt
    proto.ChannelRoleUpdate roleMsg;
    try {
      Uint8List payload;
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } else {
        payload = Uint8List.fromList(envelope.encryptedPayload);
      }
      roleMsg = proto.ChannelRoleUpdate.fromBuffer(payload);
    } catch (e) {
      _log.error('CHANNEL_ROLE_UPDATE decrypt/parse failed: $e');
      return;
    }

    final entityIdHex = bytesToHex(Uint8List.fromList(roleMsg.channelId));
    final targetIdHex = bytesToHex(Uint8List.fromList(roleMsg.targetId));
    final newRole = roleMsg.newRole;

    // Check both channels and groups (Architecture v2.2: dual-mode handler)
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
        type: proto.MessageType.CHANNEL_ROLE_UPDATE,
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
        type: proto.MessageType.CHANNEL_ROLE_UPDATE,
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

  void _handleChannelPost(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));

    // Route to channel via groupId field
    final channelIdHex = envelope.groupId.isNotEmpty
        ? bytesToHex(Uint8List.fromList(envelope.groupId))
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

    // Decrypt
    Uint8List decryptedPayload;
    try {
      if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        decryptedPayload = decrypted;
      } else {
        decryptedPayload = Uint8List.fromList(envelope.encryptedPayload);
      }
    } catch (e) {
      _log.error('CHANNEL_POST decrypt failed: $e');
      return;
    }

    final text = utf8.decode(decryptedPayload, allowMalformed: true);
    final msgId = bytesToHex(Uint8List.fromList(envelope.messageId));

    final msg = UiMessage(
      id: msgId,
      conversationId: channelIdHex,
      senderNodeIdHex: senderHex,
      text: text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(envelope.timestamp.toInt()),
      type: proto.MessageType.CHANNEL_POST,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );

    _addMessageToConversation(channelIdHex, msg, isChannel: true);
    _log.debug('Channel post received in "${channel.name}" from ${senderMember.displayName}');
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

    var payload = Uint8List.fromList(profileData.writeToBuffer());

    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;

      var compression = proto.CompressionType.NONE;
      var toEncrypt = payload;
      if (payload.length >= 64) {
        try {
          final compressed = ZstdCompression.instance.compress(payload);
          if (compressed.length < payload.length) {
            toEncrypt = compressed;
            compression = proto.CompressionType.ZSTD;
          }
        } catch (_) {}
      }

      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: toEncrypt,
        recipientX25519Pk: contact.x25519Pk!,
        recipientMlKemPk: contact.mlKemPk!,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.PROFILE_UPDATE,
        ciphertext,
        recipientId: contact.nodeId,
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      envelope.compression = compression;

      node.sendEnvelope(envelope, contact.nodeId);
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
    _stopAudioEngine();
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
    if (!Platform.isLinux || session.callKey == null) return;
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
  }

  Future<void> _startGroupVideo(GroupCallSession session) async {
    if (!Platform.isLinux || session.callKey == null) return;
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

  void _handleGroupCallVideo(proto.MessageEnvelope envelope) {
    // Forward to GroupCallManager for tree relay
    groupCallManager.handleGroupCallVideo(envelope);

    // Forward to GroupVideoReceiver for decoding
    if (_groupVideoReceiver != null) {
      try {
        final video = proto.GroupCallVideo.fromBuffer(envelope.encryptedPayload);
        final senderHex = bytesToHex(Uint8List.fromList(video.senderNodeId));
        if (senderHex != identity.userIdHex) {
          _groupVideoReceiver!.addFrame(
            senderHex, Uint8List.fromList(video.videoFrameData));
        }
      } catch (e) {
        _log.debug('Group video parse failed: $e');
      }
    }
  }

  /// Callback: group video I420 frame decoded (UI converts to RGBA).
  void Function(String senderHex, Uint8List i420, int width, int height)? onGroupVideoI420Frame;

  /// Dispatch CALL_INVITE: decrypt KEM if needed, then route to group or 1:1.
  void _handleCallInviteDispatch(proto.MessageEnvelope envelope) {
    Uint8List payload = Uint8List.fromList(envelope.encryptedPayload);

    // Decrypt KEM-encrypted invites (group calls use sendEncrypted)
    if (envelope.hasKemHeader() && envelope.kemHeader.ephemeralX25519Pk.isNotEmpty) {
      try {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: payload,
          ourX25519Sk: identity.x25519SecretKey,
          ourMlKemSk: identity.mlKemSecretKey,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        payload = decrypted;
      } catch (e) {
        _log.debug('CALL_INVITE KEM decrypt failed: $e');
        // Fall through to 1:1 handler (may be unencrypted)
      }
    }

    try {
      final invite = proto.CallInvite.fromBuffer(payload);
      if (invite.isGroupCall) {
        // Replace encryptedPayload with decrypted for downstream handler
        envelope.encryptedPayload = payload;
        groupCallManager.handleGroupCallInvite(envelope, payload);
      } else {
        // 1:1 calls — handler uses raw (unencrypted) payload
        envelope.encryptedPayload = payload;
        callManager.handleCallInvite(envelope);
      }
    } catch (_) {
      callManager.handleCallInvite(envelope);
    }
  }

  void _handleGroupCallAudio(proto.MessageEnvelope envelope) {
    // Forward to GroupCallManager for tree relay
    groupCallManager.handleGroupCallAudio(envelope);

    // Forward to AudioMixer for playback
    if (_audioMixer != null) {
      try {
        final audio = proto.GroupCallAudio.fromBuffer(envelope.encryptedPayload);
        final senderHex = bytesToHex(Uint8List.fromList(audio.senderNodeId));
        if (senderHex != identity.userIdHex) {
          _audioMixer!.addFrame(senderHex, Uint8List.fromList(audio.encryptedAudio));
        }
      } catch (e) {
        _log.debug('Group audio parse failed: $e');
      }
    }
  }

  /// Send KEM-encrypted message to a single recipient (used by GroupCallManager).
  Future<bool> _sendKemEncryptedForGroupCall(
      String recipientHex, proto.MessageType type, Uint8List payload) async {
    final (x25519Pk, mlKemPk) = _resolveMemberKeys(recipientHex);
    if (x25519Pk == null || mlKemPk == null) return false;

    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: payload,
      recipientX25519Pk: x25519Pk,
      recipientMlKemPk: mlKemPk,
    );

    final envelope = identity.createSignedEnvelope(
      type,
      ciphertext,
      recipientId: hexToBytes(recipientHex),
      compress: false,
    );
    envelope.kemHeader = kemHeader;

    return await node.sendEnvelope(envelope, hexToBytes(recipientHex));
  }

  /// Send unencrypted (call-key-encrypted) envelope directly.
  void _sendDirectForGroupCall(
      String recipientHex, proto.MessageType type, Uint8List payload) {
    final envelope = identity.createSignedEnvelope(
      type,
      payload,
      recipientId: hexToBytes(recipientHex),
    );
    node.sendEnvelope(envelope, hexToBytes(recipientHex));
  }

  // ── Audio Engine ──────────────────────────────────────────────────

  Future<void> _startAudioEngine(CallSession session) async {
    if (!Platform.isLinux || session.sharedSecret == null) return;

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
  }

  void _sendAudioFrame(CallSession session, Uint8List encryptedFrame) {
    session.framesSent++;
    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CALL_AUDIO,
      encryptedFrame,
      recipientId: hexToBytes(session.peerNodeIdHex),
    );
    // Fire-and-forget UDP, no ACK needed for audio
    node.sendEnvelope(envelope, hexToBytes(session.peerNodeIdHex));
  }

  void _handleCallAudio(proto.MessageEnvelope envelope) {
    if (_audioEngine == null || !_audioEngine!.isRunning) return;
    callManager.currentCall?.framesReceived++;
    _audioEngine!.playFrame(Uint8List.fromList(envelope.encryptedPayload));
  }

  void _handleCallVideo(proto.MessageEnvelope envelope) {
    final session = callManager.currentCall;
    if (session == null || session.state != CallState.inCall) return;
    session.videoFramesReceived++;
    // Notify listeners (VideoEngine will decode + display)
    onVideoFrameReceived?.call(Uint8List.fromList(envelope.encryptedPayload));
  }

  void _handleKeyframeRequest(proto.MessageEnvelope envelope) {
    // Notify VideoEngine to force next frame as keyframe
    onKeyframeRequested?.call();
  }

  void sendKeyframeRequest() {
    final session = callManager.currentCall;
    if (session == null || session.state != CallState.inCall) return;
    final request = proto.KeyframeRequest()
      ..callId = session.callId;
    final envelope = identity.createSignedEnvelope(
      proto.MessageType.CALL_KEYFRAME_REQUEST,
      request.writeToBuffer(),
      recipientId: hexToBytes(session.peerNodeIdHex),
    );
    node.sendEnvelope(envelope, hexToBytes(session.peerNodeIdHex));
  }

  /// Callbacks for video frame events (set by VideoEngine)
  void Function(Uint8List serializedVideoFrame)? onVideoFrameReceived;
  void Function()? onKeyframeRequested;

  // ── Network Change ─────────────────────────────────────────────────

  @override
  Future<void> onNetworkChanged() async {
    await node.onNetworkChanged();
    // Re-poll mailbox after network change (erasure fragments on DHT).
    _pollMailbox();
    // Also poll Store-and-Forward peers (they may hold messages for us).
    _pollStoredMessages();
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
  void _syncTierRegistration() {
    final dv = node.dvRouting;
    // Contacts: register all accepted contacts
    for (final entry in _contacts.entries) {
      if (entry.value.status == 'accepted') {
        dv.registerContact(entry.key);
      } else {
        dv.unregisterContact(entry.key);
      }
    }
    // Channels: register all channel members
    for (final channel in _channels.values) {
      for (final memberHex in channel.members.keys) {
        dv.registerChannelMember(memberHex);
      }
    }
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
        final (kemHeader, ciphertext) = PerMessageKem.encrypt(
          plaintext: revokePayload,
          recipientX25519Pk: contact.x25519Pk!,
          recipientMlKemPk: contact.mlKemPk!,
        );
        final envelope = identity.createSignedEnvelope(
          proto.MessageType.DEVICE_REVOKED,
          ciphertext,
          recipientId: contact.nodeId,
          compress: false,
        );
        envelope.kemHeader = kemHeader;
        node.sendEnvelope(envelope, contact.nodeId);
      } catch (e) {
        _log.warn('Failed to send DEVICE_REVOKED to ${contact.displayName}: $e');
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
  int get peerCount => node.routingTable.peerCount;
  @override
  int get confirmedPeerCount => node.confirmedPeerIds.length;
  @override
  bool get hasPortMapping => node.natTraversal.hasPortMapping;
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
  ContactInfo? getContact(String nodeIdHex) => _contacts[nodeIdHex];

  @override
  List<PeerSummary> get peerSummaries {
    final confirmed = node.confirmedPeerIds;
    return node.routingTable.allPeers
        .where((p) => confirmed.contains(p.nodeIdHex))
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
      // Include IPv6 global addresses from the multi-address list
      for (final addr in p.addresses) {
        if (addr.type == PeerAddressType.ipv6Global) {
          final key = '[${addr.ip}]:${addr.port}';
          if (seen.add(key)) addrs.add(key);
        }
      }
      // Primary address: prefer IPv6 global > public IPv4 > local IPv4
      final ipv6Addr = p.addresses.where((a) => a.type == PeerAddressType.ipv6Global).toList();
      final primaryIp = ipv6Addr.isNotEmpty ? ipv6Addr.first.ip
          : p.publicIp.isNotEmpty ? p.publicIp : p.localIp;
      final primaryPort = ipv6Addr.isNotEmpty ? ipv6Addr.first.port
          : p.publicPort > 0 ? p.publicPort : p.localPort;
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
    };
  }

  // ── Network Statistics ──────────────────────────────────────────

  /// Collect a full network statistics snapshot.
  @override
  NetworkStats getNetworkStats() {
    return _statsCollector.collect(
      routingTable: node.routingTable,
      mailboxStore: mailboxStore,
      natTraversal: node.natTraversal,
      rttMap: node.dhtRpc.rttMap,
      isRunning: isRunning,
      profileDir: profileDir,
    );
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

    // Build KEY_ROTATION message
    final rotationMsg = proto.KeyRotation()
      ..newX25519Pk = identity.x25519PublicKey
      ..newMlKemPk = identity.mlKemPublicKey
      ..rotationTimestamp = Int64(DateTime.now().millisecondsSinceEpoch);

    // Sign the rotation data with our identity key
    final dataToSign = rotationMsg.writeToBuffer();
    rotationMsg.signature = SodiumFFI().signEd25519(dataToSign, identity.ed25519SecretKey);

    // Broadcast to all accepted contacts
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;

      final payload = rotationMsg.writeToBuffer();
      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: Uint8List.fromList(payload),
        recipientX25519Pk: contact.x25519Pk!,
        recipientMlKemPk: contact.mlKemPk!,
      );

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.KEY_ROTATION_BROADCAST,
        ciphertext,
        recipientId: contact.nodeId,
        compress: false,
      );
      envelope.kemHeader = kemHeader;

      node.sendEnvelope(envelope, contact.nodeId);
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

    // 3. Send KEY_ROTATION_BROADCAST to all contacts (signed with OLD identity)
    final payloadBytes = Uint8List.fromList(broadcast.writeToBuffer());
    // Paket C: captured BEFORE `rotateIdentityFull` overwrites identity.userId,
    // so retries can keep using the pre-rotation hex as envelope.senderId and
    // the offline receiver's `_contacts[senderHex]` lookup still hits.
    final oldUserIdHex = identity.userIdHex;
    final sentToHex = <String>[];
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;

      try {
        final (kemHeader, ciphertext) = PerMessageKem.encrypt(
          plaintext: payloadBytes,
          recipientX25519Pk: contact.x25519Pk!,
          recipientMlKemPk: contact.mlKemPk!,
        );
        final envelope = identity.createSignedEnvelope(
          proto.MessageType.KEY_ROTATION_BROADCAST,
          ciphertext,
          recipientId: contact.nodeId,
          compress: false,
        );
        envelope.kemHeader = kemHeader;
        node.sendEnvelope(envelope, contact.nodeId);
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
  void _handleKeyRotation(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') return;

    // Decrypt
    try {
      var payload = _decryptPayload(envelope);
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
      final peerNodeId = Uint8List.fromList(envelope.senderId);
      final peer = node.routingTable.getPeer(peerNodeId);
      if (peer != null) {
        peer.x25519PublicKey = contact.x25519Pk!;
        peer.mlKemPublicKey = contact.mlKemPk!;
      }

      _log.info('Key rotation received from ${contact.displayName}');
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

    // Encrypt with own public key — we are both sender and recipient
    try {
      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: syncBytes,
        recipientX25519Pk: identity.x25519PublicKey,
        recipientMlKemPk: identity.mlKemPublicKey,
      );
      final envelope = identity.createSignedEnvelope(
        proto.MessageType.TWIN_SYNC,
        ciphertext,
        recipientId: identity.nodeId, // To our own Node-ID
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      node.sendEnvelope(envelope, identity.nodeId);
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

    try {
      final (kemHeader, ciphertext) = PerMessageKem.encrypt(
        plaintext: payload,
        recipientX25519Pk: identity.x25519PublicKey,
        recipientMlKemPk: identity.mlKemPublicKey,
      );
      final envelope = identity.createSignedEnvelope(
        proto.MessageType.TWIN_ANNOUNCE,
        ciphertext,
        recipientId: identity.nodeId,
        compress: false,
      );
      envelope.kemHeader = kemHeader;
      node.sendEnvelope(envelope, identity.nodeId);
      _log.info('TWIN_ANNOUNCE sent for device $_localDeviceId');
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

  /// Handle incoming TWIN_ANNOUNCE: register a new twin device.
  void _handleTwinAnnounce(proto.MessageEnvelope envelope) {
    try {
      final payload = _decryptPayload(envelope);
      final record = proto.DeviceRecord.fromBuffer(payload);
      final deviceIdHex = bytesToHex(Uint8List.fromList(record.deviceId));

      if (deviceIdHex == _localDeviceId) return; // Ignore our own announce

      // §26 Phase 4: extract deviceNodeId from announce
      final devNodeIdHex = record.deviceNodeId.isNotEmpty
          ? bytesToHex(Uint8List.fromList(record.deviceNodeId))
          : null;

      final now = DateTime.now();
      if (_devices.containsKey(deviceIdHex)) {
        // Update existing device
        _devices[deviceIdHex]!.lastSeen = now;
        _devices[deviceIdHex]!.deviceName = record.deviceName;
        if (devNodeIdHex != null) _devices[deviceIdHex]!.deviceNodeIdHex = devNodeIdHex;
      } else {
        // Register new twin device
        _devices[deviceIdHex] = DeviceRecord(
          deviceId: deviceIdHex,
          deviceName: record.deviceName,
          platform: _detectPlatformFromProto(record.platform),
          firstSeen: now,
          lastSeen: now,
          deviceNodeIdHex: devNodeIdHex,
        );
        _log.info('New twin device registered: $deviceIdHex (${record.deviceName})');
      }
      _saveDevices();
      _notifyDevicesChanged();

      // Send our own announce back so the new device knows about us
      _sendTwinAnnounce();
    } catch (e) {
      _log.error('TWIN_ANNOUNCE processing failed: $e');
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

  /// Handle incoming TWIN_SYNC: apply local action from another twin device.
  void _handleTwinSync(proto.MessageEnvelope envelope) {
    try {
      final payload = _decryptPayload(envelope);
      final sync = proto.TwinSyncEnvelope.fromBuffer(payload);
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
        default:
          _log.debug('Unhandled TWIN_SYNC type: ${sync.syncType}');
      }
      _saveDevices(); // Persist dedup IDs
    } catch (e) {
      _log.error('TWIN_SYNC processing failed: $e');
    }
  }

  // ── Twin-Sync sub-handlers ─────────────────────────────────────────

  void _handleTwinContactAdded(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final nodeIdHex = json['nodeId'] as String;
      if (_contacts.containsKey(nodeIdHex)) return; // Already known

      _contacts[nodeIdHex] = ContactInfo(
        nodeId: hexToBytes(nodeIdHex),
        displayName: json['displayName'] as String? ?? '',
        ed25519Pk: json['ed25519Pk'] != null ? hexToBytes(json['ed25519Pk'] as String) : null,
        x25519Pk: json['x25519Pk'] != null ? hexToBytes(json['x25519Pk'] as String) : null,
        mlKemPk: json['mlKemPk'] != null ? hexToBytes(json['mlKemPk'] as String) : null,
        mlDsaPk: json['mlDsaPk'] != null ? hexToBytes(json['mlDsaPk'] as String) : null,
        status: 'accepted',
        acceptedAt: DateTime.now(),
      );
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
        type: proto.MessageType.TEXT,
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

  /// Handle DEVICE_REVOKED broadcast from a contact (§26.6.1).
  /// Contact notifies us that one of their devices has been deregistered.
  /// §26 Phase 4: removes the specific deviceNodeId from routing table + contact.
  void _handleDeviceRevokedBroadcast(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') return;

    try {
      final payload = _decryptPayload(envelope);
      final revokedDevice = proto.DeviceRecord.fromBuffer(payload);
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

  /// Handle KEY_ROTATION_BROADCAST from a contact.
  /// Dispatches between periodic KEM rotation (legacy KeyRotation format)
  /// and emergency full rotation (KeyRotationBroadcast with dual-signature).
  void _handleKeyRotationBroadcast(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') return;

    try {
      final payload = _decryptPayload(envelope);

      // Discriminator: KeyRotationBroadcast has dual signatures (fields 5+6).
      // Periodic KEM rotation uses KeyRotation (no fields 5+6 → empty when
      // parsed as KeyRotationBroadcast).
      final broadcast = proto.KeyRotationBroadcast.fromBuffer(payload);
      if (broadcast.oldSignatureEd25519.isNotEmpty &&
          broadcast.newSignatureEd25519.isNotEmpty) {
        _handleEmergencyKeyRotation(envelope, contact, senderHex, broadcast);
      } else {
        // Periodic KEM rotation — delegate to legacy handler
        _handleKeyRotation(envelope);
      }
    } catch (e) {
      _log.error('KEY_ROTATION_BROADCAST processing failed: $e');
    }
  }

  /// Emergency full key rotation (§26.6.2): dual-signature verification,
  /// ALL keys updated, Node-ID re-keyed across contacts/groups/channels.
  void _handleEmergencyKeyRotation(
    proto.MessageEnvelope envelope,
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

      // Update routing table: copy old peer's addresses to new peer entry
      final oldPeer = node.routingTable.getPeer(Uint8List.fromList(envelope.senderId));
      if (oldPeer != null) {
        node.routingTable.removePeer(Uint8List.fromList(envelope.senderId));
        node.routingTable.addPeer(PeerInfo(
          nodeId: newNodeId,
          addresses: oldPeer.addresses,
          ed25519PublicKey: newEd25519Pk,
          x25519PublicKey: newX25519Pk,
          mlKemPublicKey: newMlKemPk,
        ));
      }
    } else {
      // Node-ID unchanged — update keys in-place
      final peer = node.routingTable.getPeer(contact.nodeId);
      if (peer != null) {
        peer.ed25519PublicKey = newEd25519Pk;
        peer.x25519PublicKey = newX25519Pk;
        peer.mlKemPublicKey = newMlKemPk;
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

    // Send KEY_ROTATION_ACK back to contact (at new Node-ID)
    try {
      final ackEnvelope = identity.createSignedEnvelope(
        proto.MessageType.KEY_ROTATION_ACK,
        Uint8List(0),
        recipientId: newNodeId,
        compress: false,
      );
      node.sendEnvelope(ackEnvelope, newNodeId);
    } catch (e) {
      _log.warn('Failed to send KEY_ROTATION_ACK: $e');
    }

    _log.info('Emergency key rotation from ${contact.displayName}: '
        'all keys updated, Node-ID ${senderHex.substring(0, 8)} → ${newNodeIdHex.substring(0, 8)}');
    onStateChanged?.call();
  }

  /// Handle KEY_ROTATION_ACK from a contact (§26.6.2).
  /// Removes the contact from the persisted pending-retry set.
  ///
  /// Paket C F2: the outer envelope Ed25519 signature is verified against
  /// the contact's stored pubkey. Without this, an attacker who knows a
  /// contact's nodeId could forge an ACK with that contact's senderId,
  /// silently suppressing retries to the real contact and stranding them
  /// on the old keys forever.
  void _handleKeyRotationAck(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final contact = _contacts[senderHex];
    if (contact == null || contact.ed25519Pk == null) {
      _log.warn('KEY_ROTATION_ACK from unknown sender ${senderHex.substring(0, 8)} — dropped');
      return;
    }
    if (!_verifyOuterEd25519(envelope, contact.ed25519Pk!)) {
      _log.warn('KEY_ROTATION_ACK signature INVALID from ${senderHex.substring(0, 8)} — dropped');
      return;
    }
    _keyRotationRetry.markAcked(senderHex);
    final acked = _keyRotationRetry.ackedCount;
    final pending = _keyRotationRetry.pendingCount;
    final expired = _keyRotationRetry.expiredCount;
    _log.info('KEY_ROTATION_ACK from ${senderHex.substring(0, 8)} '
        '(acked=$acked pending=$pending expired=$expired)');
    if (pending == 0 && acked > 0) {
      _log.info('All still-reachable contacts acknowledged key rotation');
    }
    _emitKeyRotationRetryEvents();
  }

  /// Verify `envelope.signatureEd25519` against [pubkey]. Reconstructs the
  /// exact byte sequence the sender signed: envelope serialized WITHOUT
  /// any signature fields and WITHOUT PoW (PoW is added after signing in
  /// `cleona_node.dart`). Used for the KEY_ROTATION_ACK path (§26.6.2 F2);
  /// other handlers rely on inner-payload authentication.
  bool _verifyOuterEd25519(proto.MessageEnvelope envelope, Uint8List pubkey) {
    if (envelope.signatureEd25519.isEmpty) return false;
    final stripped = envelope.clone()
      ..clearSignatureEd25519()
      ..clearSignatureMlDsa()
      ..clearPow();
    final bytes = stripped.writeToBuffer();
    return SodiumFFI().verifyEd25519(
      bytes,
      Uint8List.fromList(envelope.signatureEd25519),
      pubkey,
    );
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
    // Paket C F1: offline receiver still has us under the pre-rotation
    // userId. Force envelope.senderId to the old hex so the receiver's
    // `_contacts[senderHex]` lookup hits and the inner dual-signature path
    // actually runs. Falls back to current userId if the state was loaded
    // from a pre-fix persisted file without oldUserIdHex.
    final oldSenderId = due.oldUserIdHex.isNotEmpty
        ? hexToBytes(due.oldUserIdHex)
        : null;

    for (final hex in due.contacts) {
      final contact = _contacts[hex];
      if (contact == null ||
          contact.status != 'accepted' ||
          contact.x25519Pk == null ||
          contact.mlKemPk == null) {
        // Contact removed / invalid — just count it as an attempt so it will
        // eventually expire instead of being retried every tick forever.
        _keyRotationRetry.markAttempt(hex, now: now);
        continue;
      }
      try {
        final (kemHeader, ciphertext) = PerMessageKem.encrypt(
          plaintext: due.broadcastBytes,
          recipientX25519Pk: contact.x25519Pk!,
          recipientMlKemPk: contact.mlKemPk!,
        );
        final envelope = identity.createSignedEnvelope(
          proto.MessageType.KEY_ROTATION_BROADCAST,
          ciphertext,
          recipientId: contact.nodeId,
          compress: false,
          senderIdOverride: oldSenderId,
        );
        envelope.kemHeader = kemHeader;
        node.sendEnvelope(envelope, contact.nodeId);
        _keyRotationRetry.markAttempt(hex, now: now);
        _log.info('KEY_ROTATION_BROADCAST retry to '
            '${hex.substring(0, 8)} (${contact.displayName})');
      } catch (e) {
        _log.warn('Retry KEY_ROTATION_BROADCAST to '
            '${hex.substring(0, 8)} failed: $e');
        // Still count attempt so we do not loop forever on permanent failure.
        _keyRotationRetry.markAttempt(hex, now: now);
      }
    }

    _emitKeyRotationRetryEvents();
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

  /// Send an encrypted payload to a single contact (encrypt + sign + deliver).
  Future<void> _sendEncryptedPayload(
    Uint8List recipientNodeId,
    proto.MessageType messageType,
    Uint8List payload,
  ) async {
    final recipientHex = bytesToHex(recipientNodeId);
    final contact = _contacts[recipientHex];
    if (contact == null || contact.x25519Pk == null || contact.mlKemPk == null) {
      _log.warn('Cannot send $messageType to $recipientHex: missing keys');
      return;
    }

    var compression = proto.CompressionType.NONE;
    if (payload.length >= 64) {
      try {
        final compressed = ZstdCompression.instance.compress(payload);
        if (compressed.length < payload.length) {
          payload = compressed;
          compression = proto.CompressionType.ZSTD;
        }
      } catch (_) {}
    }

    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: payload,
      recipientX25519Pk: contact.x25519Pk!,
      recipientMlKemPk: contact.mlKemPk!,
    );

    final envelope = identity.createSignedEnvelope(
      messageType,
      ciphertext,
      recipientId: contact.nodeId,
      compress: false,
    );
    envelope.kemHeader = kemHeader;
    envelope.compression = compression;

    await node.sendEnvelope(envelope, contact.nodeId);
    _storeErasureCodedBackup(envelope, contact, recipientNodeId: contact.nodeId);
    _statsCollector.addMessageSent();
  }

  /// Handle incoming CALENDAR_INVITE from a group event creator.
  void _handleCalendarInvite(proto.MessageEnvelope envelope) {
    try {
      final invite = proto.CalendarInviteMsg.fromBuffer(envelope.encryptedPayload);
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
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
          type: proto.MessageType.CALENDAR_INVITE,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      _log.info('Received calendar invite: ${event.title} from ${senderHex.substring(0, 8)}');
      onCalendarInviteReceived?.call(senderHex, eventIdHex, event.title);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Failed to handle CALENDAR_INVITE: $e');
    }
  }

  /// Handle incoming CALENDAR_RSVP from a group event participant.
  void _handleCalendarRsvp(proto.MessageEnvelope envelope) {
    try {
      final rsvp = proto.CalendarRsvpMsg.fromBuffer(envelope.encryptedPayload);
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
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
          type: proto.MessageType.CALENDAR_RSVP,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      _log.info('RSVP for $eventIdHex from ${senderHex.substring(0, 8)}: $status');
      onCalendarRsvpReceived?.call(eventIdHex, senderHex, status);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Failed to handle CALENDAR_RSVP: $e');
    }
  }

  /// Handle incoming CALENDAR_UPDATE from the event creator.
  void _handleCalendarUpdate(proto.MessageEnvelope envelope) {
    try {
      final update = proto.CalendarUpdateMsg.fromBuffer(envelope.encryptedPayload);
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
        final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
        final senderName = _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        _addMessageToConversation(event.groupId!, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: event.groupId!,
          senderNodeIdHex: '',
          text: '$senderName $action: ${event.title}',
          timestamp: DateTime.now(),
          type: proto.MessageType.CALENDAR_UPDATE,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      _log.info('Calendar event updated: $eventIdHex');
      onCalendarEventUpdated?.call(eventIdHex);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Failed to handle CALENDAR_UPDATE: $e');
    }
  }

  /// Handle incoming CALENDAR_DELETE from the event creator.
  void _handleCalendarDelete(proto.MessageEnvelope envelope) {
    try {
      final del = proto.CalendarDeleteMsg.fromBuffer(envelope.encryptedPayload);
      final eventIdHex = bytesToHex(Uint8List.fromList(del.eventId));

      final event = calendarManager.events[eventIdHex];
      if (event != null && event.groupId != null) {
        final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
        final senderName = _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        _addMessageToConversation(event.groupId!, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: event.groupId!,
          senderNodeIdHex: '',
          text: '$senderName hat den Termin gelöscht: ${event.title}',
          timestamp: DateTime.now(),
          type: proto.MessageType.CALENDAR_DELETE,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ), isGroup: true);
      }

      calendarManager.deleteEvent(eventIdHex);
      _log.info('Calendar event deleted: $eventIdHex');
      onCalendarEventUpdated?.call(eventIdHex);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Failed to handle CALENDAR_DELETE: $e');
    }
  }

  /// Handle incoming FREE_BUSY_REQUEST — auto-respond with filtered availability.
  Future<void> _handleFreeBusyRequest(proto.MessageEnvelope envelope) async {
    try {
      final req = proto.FreeBusyRequestMsg.fromBuffer(envelope.encryptedPayload);
      final querierHex = bytesToHex(Uint8List.fromList(envelope.senderId));
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
        Uint8List.fromList(envelope.senderId),
        proto.MessageType.FREE_BUSY_RESPONSE,
        response.writeToBuffer(),
      );

      _log.info('Sent FREE_BUSY_RESPONSE to ${querierHex.substring(0, 8)} '
          '(${blocks.length} blocks)');
    } catch (e) {
      _log.warn('Failed to handle FREE_BUSY_REQUEST: $e');
    }
  }

  /// Pending Free/Busy query results, keyed by requestId hex.
  final Map<String, List<FreeBusyBlockResult>> _freeBusyResults = {};
  final Map<String, void Function(List<FreeBusyBlockResult>)> _freeBusyCallbacks = {};

  /// Handle incoming FREE_BUSY_RESPONSE.
  void _handleFreeBusyResponse(proto.MessageEnvelope envelope) {
    try {
      final resp = proto.FreeBusyResponseMsg.fromBuffer(envelope.encryptedPayload);
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
      _log.warn('Failed to handle FREE_BUSY_RESPONSE: $e');
    }
  }

  @override
  Future<String> createCalendarEvent(CalendarEvent event) async {
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
    bool? taskCompleted, int? taskPriority,
  }) async {
    final ok = calendarManager.updateEvent(eventIdHex,
      title: title, description: description, location: location,
      startTime: startTime, endTime: endTime, allDay: allDay,
      hasCall: hasCall, reminders: reminders, recurrenceRule: recurrenceRule,
      taskCompleted: taskCompleted, taskPriority: taskPriority,
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
        proto.MessageType.CALENDAR_INVITE,
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
        proto.MessageType.CALENDAR_RSVP,
        Uint8List.fromList(payload),
      );
    }

    _log.info('Sent CALENDAR_RSVP for $eventIdHex: $status');
  }

  /// Send calendar update to all group members.
  @override
  Future<void> sendCalendarUpdate(String eventIdHex) async {
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
        proto.MessageType.CALENDAR_UPDATE,
        Uint8List.fromList(payload),
      );
    }

    _log.info('Sent CALENDAR_UPDATE for $eventIdHex');
  }

  /// Send calendar delete to all group members.
  @override
  Future<void> sendCalendarDelete(String eventIdHex) async {
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
        proto.MessageType.CALENDAR_DELETE,
        Uint8List.fromList(payload),
      );
    }

    calendarManager.deleteEvent(eventIdHex);
    _log.info('Sent CALENDAR_DELETE for $eventIdHex');
  }

  /// Send a FREE_BUSY_REQUEST to a contact.
  @override
  Future<String> sendFreeBusyRequest(String contactNodeIdHex, int queryStart, int queryEnd) async {
    final requestIdBytes = SodiumFFI().randomBytes(16);
    final requestIdHex = bytesToHex(requestIdBytes);

    final req = proto.FreeBusyRequestMsg()
      ..queryStart = Int64(queryStart)
      ..queryEnd = Int64(queryEnd)
      ..requestId = requestIdBytes;

    await _sendEncryptedPayload(
      hexToBytes(contactNodeIdHex),
      proto.MessageType.FREE_BUSY_REQUEST,
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

  void _handlePollCreate(proto.MessageEnvelope envelope) {
    try {
      final msg = proto.PollCreateMsg.fromBuffer(envelope.encryptedPayload);
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
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
          type: proto.MessageType.POLL_CREATE,
          status: MessageStatus.delivered,
          isOutgoing: false,
          pollId: poll.pollId,
        ), isGroup: _groups.containsKey(poll.groupId), isChannel: _channels.containsKey(poll.groupId));
      }

      onPollCreated?.call(poll.pollId, poll.groupId, poll.question);
      onStateChanged?.call();
      _log.info('Received POLL_CREATE ${poll.pollId.substring(0, 8)} from ${senderHex.substring(0, 8)}');
    } catch (e) {
      _log.warn('Failed to handle POLL_CREATE: $e');
    }
  }

  void _handlePollVote(proto.MessageEnvelope envelope) {
    try {
      final msg = proto.PollVoteMsg.fromBuffer(envelope.encryptedPayload);
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
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
      _log.warn('Failed to handle POLL_VOTE: $e');
    }
  }

  void _handlePollUpdate(proto.MessageEnvelope envelope) {
    try {
      final msg = proto.PollUpdateMsg.fromBuffer(envelope.encryptedPayload);
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
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
          pollManager.deletePoll(pollIdHex);
          break;
        default:
          break;
      }
      onPollStateChanged?.call(pollIdHex);
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Failed to handle POLL_UPDATE: $e');
    }
  }

  void _handlePollSnapshot(proto.MessageEnvelope envelope) {
    try {
      final msg = proto.PollSnapshotMsg.fromBuffer(envelope.encryptedPayload);
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) return;

      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
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
      _log.warn('Failed to handle POLL_SNAPSHOT: $e');
    }
  }

  void _handlePollVoteAnonymous(proto.MessageEnvelope envelope) {
    try {
      final msg = proto.PollVoteAnonymousMsg.fromBuffer(envelope.encryptedPayload);
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
      _log.warn('Failed to handle POLL_VOTE_ANONYMOUS: $e');
    }
  }

  void _handlePollVoteRevoke(proto.MessageEnvelope envelope) {
    try {
      final msg = proto.PollVoteRevokeMsg.fromBuffer(envelope.encryptedPayload);
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
      _log.warn('Failed to handle POLL_VOTE_REVOKE: $e');
    }
  }

  // ── Senders ──────────────────────────────────────────────────────────

  Future<void> _fanoutToEntity(String entityIdHex, proto.MessageType type, List<int> payload) async {
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
    await _fanoutToEntity(poll.groupId, proto.MessageType.POLL_CREATE, payload);
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
        proto.MessageType.POLL_VOTE,
        Uint8List.fromList(payload),
      );
    } else {
      await _fanoutToEntity(poll.groupId, proto.MessageType.POLL_VOTE, payload);
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
    await _fanoutToEntity(poll.groupId, proto.MessageType.POLL_VOTE_ANONYMOUS, payload);
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

    await _fanoutToEntity(poll.groupId, proto.MessageType.POLL_VOTE_REVOKE, msg.writeToBuffer());
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

    await _fanoutToEntity(poll.groupId, proto.MessageType.POLL_UPDATE, msg.writeToBuffer());
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
    await _fanoutToEntity(poll.groupId, proto.MessageType.POLL_SNAPSHOT, msg.writeToBuffer());
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
        type: proto.MessageType.POLL_CREATE,
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
      onPollStateChanged?.call(pollId);
      onStateChanged?.call();
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
  void _handleRestoreBroadcast(proto.MessageEnvelope envelope) {
    try {
      // RestoreBroadcast is NOT encrypted (sender has new keys, we don't know them yet)
      // but it IS signed with the OLD key to prove ownership
      final rb = proto.RestoreBroadcast.fromBuffer(envelope.encryptedPayload);
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
  void _sendRestoreResponse(ContactInfo recipient, int phase) {
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
            ..messageType = msg.type
            ..payload = utf8.encode(msg.text));
        }
      }
    }

    final payload = response.writeToBuffer();
    final (kemHeader, ciphertext) = PerMessageKem.encrypt(
      plaintext: Uint8List.fromList(payload),
      recipientX25519Pk: recipient.x25519Pk!,
      recipientMlKemPk: recipient.mlKemPk!,
    );

    final envelope = identity.createSignedEnvelope(
      proto.MessageType.RESTORE_RESPONSE,
      ciphertext,
      recipientId: recipient.nodeId,
      compress: false,
    );
    envelope.kemHeader = kemHeader;

    node.sendEnvelope(envelope, recipient.nodeId);
    _storeErasureCodedBackup(envelope, recipient);

    _log.info('Sent RestoreResponse phase $phase to ${recipient.displayName} '
        '(${phase == 1 ? '${response.contacts.length} contacts' : '${response.messages.length} messages'})');
  }

  /// Handle incoming RESTORE_RESPONSE: restore contacts and messages.
  void _handleRestoreResponse(proto.MessageEnvelope envelope) {
    try {
      final payload = _decryptPayload(envelope);
      final response = proto.RestoreResponse.fromBuffer(payload);
      final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
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
            type: proto.MessageType.TEXT,
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

    // Send to all old contacts (unencrypted but signed)
    for (final contact in oldContacts) {
      if (contact.status != 'accepted') continue;

      final envelope = identity.createSignedEnvelope(
        proto.MessageType.RESTORE_BROADCAST,
        broadcastBytes,
        recipientId: contact.nodeId,
      );

      node.sendEnvelope(envelope, contact.nodeId);
      _storeErasureCodedBackup(envelope, contact);
      sent++;
    }

    _log.info('Restore broadcast sent to $sent contacts');

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

  /// Decrypt envelope payload with fallback to previous keys.
  Uint8List _decryptPayload(proto.MessageEnvelope envelope) {
    if (!envelope.hasKemHeader() || envelope.kemHeader.ephemeralX25519Pk.isEmpty) {
      return Uint8List.fromList(envelope.encryptedPayload);
    }

    // Try current keys first
    try {
      var decrypted = PerMessageKem.decrypt(
        kemHeader: envelope.kemHeader,
        ciphertext: Uint8List.fromList(envelope.encryptedPayload),
        ourX25519Sk: identity.x25519SecretKey,
        ourMlKemSk: identity.mlKemSecretKey,
      );
      if (envelope.compression == proto.CompressionType.ZSTD) {
        decrypted = ZstdCompression.instance.decompress(decrypted);
      }
      return decrypted;
    } catch (_) {
      // Try previous keys (for transit messages during rotation)
      if (identity.previousX25519Sk != null && identity.previousMlKemSk != null) {
        var decrypted = PerMessageKem.decrypt(
          kemHeader: envelope.kemHeader,
          ciphertext: Uint8List.fromList(envelope.encryptedPayload),
          ourX25519Sk: identity.previousX25519Sk!,
          ourMlKemSk: identity.previousMlKemSk!,
        );
        if (envelope.compression == proto.CompressionType.ZSTD) {
          decrypted = ZstdCompression.instance.decompress(decrypted);
        }
        _log.debug('Decrypted with previous keys (rotation fallback)');
        return decrypted;
      }
      rethrow;
    }
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
    _channelIndexGossipTimer?.cancel();
    _channelIndexGossipTimer = null;
    _moderationTimer?.cancel();
    _moderationTimer = null;
    _updateCheckTimer?.cancel();
    _updateCheckTimer = null;
    _natWizardTrigger?.stop();
    _natWizardTrigger = null;
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
      // Store via FRAGMENT_STORE to closest DHT peers
      final peers = node.routingTable.findClosestPeers(mailboxId, count: 10);
      for (final peer in peers) {
        final store = proto.FragmentStore()
          ..mailboxId = mailboxId
          ..fragmentIndex = fragmentIndex
          ..fragmentData = fragmentData
          ..messageId = mailboxId // Use registry key as message ID
          ..totalFragments = 10
          ..originalSize = fragmentData.length;
        final env = identity.createSignedEnvelope(
          proto.MessageType.FRAGMENT_STORE,
          store.writeToBuffer(),
          recipientId: peer.nodeId,
        );
        node.sendEnvelope(env, peer.nodeId);
      }
    });
  }
}

/// Simple wrapper for decrypted payload.
class _DecryptedEnvelope {
  final Uint8List payload;
  _DecryptedEnvelope(this.payload);
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
