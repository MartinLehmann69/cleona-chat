import 'dart:typed_data';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/moderation/moderation_config.dart' show ReportCategory;

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

/// Message delivery status.
///
/// State machine (§5.8):
///   sending → sent (direct dispatch OK) → delivered (DELIVERY_RECEIPT) → read
///   sending → queuedOffline (no direct route, but L3 artefacts placed)
///           → delivered once recipient pulls from S&F/Erasure
///   sending → failed (no connectivity at all — sender has 0 peers, L3
///           placement impossible); entry kept in One-Shot-Outbox until the
///           next onNetworkChanged edge-trigger retries placement.
///   queuedOffline → expired (local check: 7-day TTL elapsed, no DELIVERY_RECEIPT)
///           → UI offers Resend
///   sending → queued (short-lived intermediate: in-flight but not yet
///           dispatched; also used by ACK-timeout downgrade)
enum MessageStatus {
  sending,
  queued,
  sent,
  storedInNetwork,
  delivered,
  read,
  /// L3 artefacts placed (Erasure + S&F) — waiting for recipient pull.
  queuedOffline,
  /// No connectivity at send time — L3 placement impossible; message is
  /// parked in the local one-shot outbox.
  failed,
  /// queuedOffline TTL (7 days) elapsed without DELIVERY_RECEIPT — local
  /// timestamp check only, zero network traffic.
  expired,
}

extension MessageStatusGuard on MessageStatus {
  bool get _isTerminal =>
      this == MessageStatus.delivered || this == MessageStatus.read;

  /// Forward-only state-machine guard: returns true only if [next] is a valid
  /// forward transition.  Terminal states (delivered, read) block all
  /// non-terminal writes; delivered may advance to read.
  bool canTransitionTo(MessageStatus next) {
    if (this == next) return false;
    if (this == MessageStatus.read) return false;
    if (this == MessageStatus.delivered) return next == MessageStatus.read;
    if (this == MessageStatus.expired) return false;
    if (next._isTerminal) return true;
    return !_isTerminal;
  }
}

/// Media download state for two-stage media delivery.
enum MediaDownloadState { none, announced, downloading, completed, failed }

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
  /// Timestamp when the message was read (for expiry timer).
  DateTime? readAt;
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
  // GM-2 (§9.1.4): true when sender's membership hash differs at same/lower epoch
  bool membershipMismatch;

  /// Emoji reactions: emoji → set of senderNodeIdHex.
  /// Example: {"👍": {"aabb...", "ccdd..."}, "❤️": {"aabb..."}}
  Map<String, Set<String>> reactions = {};

  UiMessage({
    required this.id,
    required this.conversationId,
    required this.senderNodeIdHex,
    required this.text,
    required this.timestamp,
    required this.type,
    this.status = MessageStatus.queued,
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
    this.membershipMismatch = false,
    Map<String, Set<String>>? reactions,
  }) : reactions = reactions ?? {};

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
        'status': status.index,
        'isOutgoing': isOutgoing,
        'filePath': filePath,
        if (editedAt != null) 'editedAt': editedAt!.millisecondsSinceEpoch,
        if (readAt != null) 'readAt': readAt!.millisecondsSinceEpoch,
        if (isDeleted) 'isDeleted': true,
        if (mimeType != null) 'mimeType': mimeType,
        if (fileSize != null) 'fileSize': fileSize,
        if (filename != null) 'filename': filename,
        if (thumbnailBase64 != null) 'thumbnailBase64': thumbnailBase64,
        if (mediaState != MediaDownloadState.none) 'mediaState': mediaState.index,
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
        if (reactions.isNotEmpty)
          'reactions': reactions.map((emoji, senders) => MapEntry(emoji, senders.toList())),
      };

  static UiMessage fromJson(Map<String, dynamic> json) => UiMessage(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        senderNodeIdHex: json['sender'] as String? ?? '',
        text: json['text'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        type: UiMessageType.fromInt(json['type'] as int),
        status: MessageStatus.values[json['status'] as int? ?? 3],
        isOutgoing: json['isOutgoing'] as bool,
        filePath: json['filePath'] as String?,
        editedAt: json['editedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['editedAt'] as int)
            : null,
        readAt: json['readAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['readAt'] as int)
            : null,
        isDeleted: json['isDeleted'] as bool? ?? false,
        mimeType: json['mimeType'] as String?,
        fileSize: json['fileSize'] as int?,
        filename: json['filename'] as String?,
        thumbnailBase64: json['thumbnailBase64'] as String?,
        mediaState: json['mediaState'] != null
            ? MediaDownloadState.values[json['mediaState'] as int]
            : MediaDownloadState.none,
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
        reactions: _parseReactions(json['reactions']),
      );

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
}

/// Conversation state.
class Conversation {
  final String id; // nodeIdHex for DMs, groupIdHex for groups, channelIdHex for channels
  String displayName;
  final List<UiMessage> messages;
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
  String name;
  String? description;
  String? pictureBase64;
  final Map<String, GroupMemberInfo> members; // nodeIdHex -> member
  String ownerNodeIdHex;
  DateTime createdAt;
  int membershipEpoch;

  GroupInfo({
    required this.groupIdHex,
    required this.name,
    this.description,
    this.pictureBase64,
    Map<String, GroupMemberInfo>? members,
    required this.ownerNodeIdHex,
    DateTime? createdAt,
    this.membershipEpoch = 0,
  })  : members = members ?? {},
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'groupIdHex': groupIdHex,
        'name': name,
        'description': description,
        'pictureBase64': pictureBase64,
        'ownerNodeIdHex': ownerNodeIdHex,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'members': members.map((k, v) => MapEntry(k, v.toJson())),
        'membershipEpoch': membershipEpoch,
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
  String name;
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
    required this.name,
    this.description,
    this.pictureBase64,
    Map<String, ChannelMemberInfo>? members,
    required this.ownerNodeIdHex,
    DateTime? createdAt,
    this.isPublic = false,
    this.isAdult = true,
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
  })  : members = members ?? {},
        createdAt = createdAt ?? DateTime.now();

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
    this.isAdult = true,
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

/// A content report (Meldung) for moderation.
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

/// A single-post report (Einzelbeitrag-Meldung).
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
  /// Birthday month (1-12), day (1-31), optional year. Feeds the calendar
  /// birthday auto-sync (§23.4). Purely local — never broadcast to other contacts.
  int? birthdayMonth;
  int? birthdayDay;
  int? birthdayYear;

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

  /// Returns localAlias if set, otherwise the contact's own displayName.
  String get effectiveName => localAlias ?? displayName;

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
    this.birthdayMonth,
    this.birthdayDay,
    this.birthdayYear,
    this.seedDeviceIdHex,
    this.seedDxkB64,
    this.seedDmkB64,
    this.seedEpB64,
  }) : deviceNodeIds = deviceNodeIds ?? {};

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
        if (birthdayMonth != null) 'birthdayMonth': birthdayMonth,
        if (birthdayDay != null) 'birthdayDay': birthdayDay,
        if (birthdayYear != null) 'birthdayYear': birthdayYear,
        if (seedDeviceIdHex != null) 'seedDeviceIdHex': seedDeviceIdHex,
        if (seedDxkB64 != null) 'seedDxkB64': seedDxkB64,
        if (seedDmkB64 != null) 'seedDmkB64': seedDmkB64,
        if (seedEpB64 != null) 'seedEpB64': seedEpB64,
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
        birthdayMonth: json['birthdayMonth'] as int?,
        birthdayDay: json['birthdayDay'] as int?,
        birthdayYear: json['birthdayYear'] as int?,
        seedDeviceIdHex: json['seedDeviceIdHex'] as String?,
        seedDxkB64: json['seedDxkB64'] as String?,
        seedDmkB64: json['seedDmkB64'] as String?,
        seedEpB64: json['seedEpB64'] as String?,
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
