// Central configuration for the Media Auto-Archive system.
//
// Controls: tier boundaries, storage budget, network detection,
// protocol selection and security rules.
// [ArchiveConfig.production] provides the production values,
// [ArchiveConfig.test] provides shortened values for automated tests.

import 'package:cleona/core/service/service_types.dart' show Conversation;

/// Supported archive protocols.
enum ArchiveProtocol { smb, sftp, ftps, http }

/// Storage tiers for archived media on the device.
enum ArchiveTier {
  /// Original file on the device (not yet archived).
  original,

  /// Thumbnail (~20-50 KB) on the device, original on share.
  thumbnail,

  /// Mini-thumbnail (~2-5 KB, 64px) on the device, original on share.
  mini,

  /// Metadata link only (date, size, type icon), original on share.
  metadataOnly,
}

/// Status of an archive operation.
enum ArchiveStatus {
  /// Not yet started.
  pending,

  /// Upload in progress.
  uploading,

  /// Successfully archived and confirmed.
  confirmed,

  /// Archival failed.
  failed,
}

/// Action when budget is exceeded.
enum EvictionAction {
  /// No action possible (already at lowest tier).
  none,

  /// Downgrade to next lower tier.
  downgrade,
}

class ArchiveConfig {
  // -- Tier boundaries (message age) --------------------------------------

  /// At this age: Original -> Thumbnail.
  final Duration tier1Boundary;

  /// At this age: Thumbnail -> Mini.
  final Duration tier2Boundary;

  /// At this age: Mini -> MetadataOnly.
  final Duration tier3Boundary;

  // -- Storage budget ------------------------------------------------------

  /// Max media storage on the device in MB.
  final int storageBudgetMB;

  // -- Network detection ---------------------------------------------------

  /// Allowed WiFi names (SSIDs). Empty = user must configure.
  final List<String> allowedSSIDs;

  /// Timeout for share reachability check in seconds.
  final int shareReachabilityTimeoutSec;

  // -- Protocol ------------------------------------------------------------

  /// Default protocol for new archives.
  final ArchiveProtocol defaultProtocol;

  /// All supported protocols.
  final List<ArchiveProtocol> supportedProtocols;

  // -- Thumbnails ---------------------------------------------------------

  /// Max thumbnail size in KB (Tier 2).
  final int thumbnailMaxKB;

  /// Max mini-thumbnail size in KB (Tier 3).
  final int miniMaxKB;

  // -- Security ------------------------------------------------------------

  /// NEVER delete without confirmed archival.
  /// MUST NEVER be set to false — neither in test nor production.
  final bool requireConfirmedArchival;

  // -- Connection ----------------------------------------------------------

  /// Host/server for the archive share.
  final String archiveHost;

  /// Path/share on the archive server.
  final String archivePath;

  /// Username for authentication (optional, null = anonymous).
  final String? archiveUsername;

  /// Password for authentication (optional).
  final String? archivePassword;

  /// Port for the archive protocol (optional, null = default).
  final int? archivePort;

  // -- Behavior ------------------------------------------------------------

  /// Archival enabled by default.
  final bool enabledByDefault;

  /// Max entries per batch retrieval.
  final int batchRetrievalMaxItems;

  /// Check interval in minutes (how often archival runs).
  final int archiveCheckIntervalMinutes;

  const ArchiveConfig({
    // Tier boundaries
    this.tier1Boundary = const Duration(days: 30),
    this.tier2Boundary = const Duration(days: 90),
    this.tier3Boundary = const Duration(days: 365),
    // Budget
    this.storageBudgetMB = 500,
    // Network
    this.allowedSSIDs = const [],
    this.shareReachabilityTimeoutSec = 10,
    // Protocol
    this.defaultProtocol = ArchiveProtocol.smb,
    this.supportedProtocols = const [
      ArchiveProtocol.smb,
      ArchiveProtocol.sftp,
      ArchiveProtocol.ftps,
      ArchiveProtocol.http,
    ],
    // Thumbnails
    this.thumbnailMaxKB = 100,
    this.miniMaxKB = 10,
    // Security
    this.requireConfirmedArchival = true,
    // Connection
    this.archiveHost = '',
    this.archivePath = '',
    this.archiveUsername,
    this.archivePassword,
    this.archivePort,
    // Behavior
    this.enabledByDefault = false,
    this.batchRetrievalMaxItems = 50,
    this.archiveCheckIntervalMinutes = 60,
  });

  /// Production configuration with the values from docs/ARCHIVE.md.
  factory ArchiveConfig.production() => const ArchiveConfig();

  /// Test configuration with greatly shortened time periods.
  factory ArchiveConfig.test() => const ArchiveConfig(
        // Tier boundaries: seconds instead of days
        tier1Boundary: Duration(seconds: 30),
        tier2Boundary: Duration(seconds: 60),
        tier3Boundary: Duration(seconds: 120),
        // Budget: small
        storageBudgetMB: 10,
        // Network: test WiFi
        allowedSSIDs: ['TestWLAN'],
        shareReachabilityTimeoutSec: 2,
        // Security: NEVER disable!
        requireConfirmedArchival: true,
        // Connection: test server
        archiveHost: 'localhost',
        archivePath: '/test-archive',
        // Behavior: more aggressive in test
        enabledByDefault: true,
        batchRetrievalMaxItems: 10,
        archiveCheckIntervalMinutes: 1,
      );

  // -- Calculation methods --------------------------------------------------

  /// Determines the tier for a media item based on message age.
  /// [pinned]: Pinned media always stays at [ArchiveTier.original].
  ArchiveTier tierForAge(Duration age, {bool pinned = false}) {
    if (pinned) return ArchiveTier.original;
    if (age >= tier3Boundary) return ArchiveTier.metadataOnly;
    if (age >= tier2Boundary) return ArchiveTier.mini;
    if (age >= tier1Boundary) return ArchiveTier.thumbnail;
    return ArchiveTier.original;
  }

  /// Whether a media item should be archived (from tier 1 boundary).
  /// Pinned media is still archived (backup).
  bool shouldArchive(Duration age, {bool pinned = false}) {
    return age >= tier1Boundary;
  }

  /// Which tier a pinned media item retains when archived.
  ArchiveTier archivedTierForPinned() => ArchiveTier.original;

  /// Whether a media item can be evicted when budget is exceeded.
  bool isEvictableForBudget({required bool pinned}) => !pinned;

  /// Whether the storage budget is exceeded.
  bool needsEviction({required int usedMB}) => usedMB >= storageBudgetMB;

  /// Whether a local media item may be deleted.
  bool canDeleteLocal(ArchiveStatus status) {
    if (!requireConfirmedArchival) return false; // Safety valve
    return status == ArchiveStatus.confirmed;
  }

  /// Which eviction action is possible for a given tier.
  EvictionAction evictionAction(ArchiveTier tier) {
    switch (tier) {
      case ArchiveTier.original:
      case ArchiveTier.thumbnail:
      case ArchiveTier.mini:
        return EvictionAction.downgrade;
      case ArchiveTier.metadataOnly:
        return EvictionAction.none;
    }
  }

  /// Whether archival is ready (network conditions met).
  bool isArchiveReady({
    required String? currentSSID,
    required bool shareReachable,
    required List<String> allowedSSIDs,
  }) {
    if (allowedSSIDs.isEmpty) return false;
    if (currentSSID == null) return false;
    if (!shareReachable) return false;
    return allowedSSIDs.contains(currentSSID);
  }

  // -- Static methods ------------------------------------------------------

  /// Whether a conversation type is eligible for archival.
  /// DMs and groups: yes. Channels: no.
  static bool isEligible({required bool isGroup, required bool isChannel}) {
    if (isChannel) return false;
    return true; // DM or group
  }

  /// Whether a conversation is eligible for archival.
  static bool isConversationEligible(Conversation conv) {
    return isEligible(isGroup: conv.isGroup, isChannel: conv.isChannel);
  }

  /// Whether a MIME type is archivable (media message).
  static bool isMediaArchivable(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) return false;
    return true;
  }

  /// Generates a share URL from protocol, host, path and filename.
  static String generateShareUrl(
      ArchiveProtocol protocol, String host, String path, String filename) {
    final prefix = switch (protocol) {
      ArchiveProtocol.smb => 'smb://',
      ArchiveProtocol.sftp => 'sftp://',
      ArchiveProtocol.ftps => 'ftps://',
      ArchiveProtocol.http => 'https://',
    };
    final cleanPath = path.endsWith('/') ? path : '$path/';
    return '$prefix$host/$cleanPath$filename';
  }

  // -- JSON Round-Trip ----------------------------------------------------

  Map<String, dynamic> toJson() => {
        'tier1BoundaryMs': tier1Boundary.inMilliseconds,
        'tier2BoundaryMs': tier2Boundary.inMilliseconds,
        'tier3BoundaryMs': tier3Boundary.inMilliseconds,
        'storageBudgetMB': storageBudgetMB,
        'allowedSSIDs': allowedSSIDs,
        'shareReachabilityTimeoutSec': shareReachabilityTimeoutSec,
        'defaultProtocol': defaultProtocol.index,
        'thumbnailMaxKB': thumbnailMaxKB,
        'miniMaxKB': miniMaxKB,
        'requireConfirmedArchival': requireConfirmedArchival,
        'archiveHost': archiveHost,
        'archivePath': archivePath,
        if (archiveUsername != null) 'archiveUsername': archiveUsername,
        if (archivePassword != null) 'archivePassword': archivePassword,
        if (archivePort != null) 'archivePort': archivePort,
        'enabledByDefault': enabledByDefault,
        'batchRetrievalMaxItems': batchRetrievalMaxItems,
        'archiveCheckIntervalMinutes': archiveCheckIntervalMinutes,
      };

  static ArchiveConfig fromJson(Map<String, dynamic> json) => ArchiveConfig(
        tier1Boundary: Duration(
            milliseconds: json['tier1BoundaryMs'] as int? ??
                const Duration(days: 30).inMilliseconds),
        tier2Boundary: Duration(
            milliseconds: json['tier2BoundaryMs'] as int? ??
                const Duration(days: 90).inMilliseconds),
        tier3Boundary: Duration(
            milliseconds: json['tier3BoundaryMs'] as int? ??
                const Duration(days: 365).inMilliseconds),
        storageBudgetMB: json['storageBudgetMB'] as int? ?? 500,
        allowedSSIDs: (json['allowedSSIDs'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        shareReachabilityTimeoutSec:
            json['shareReachabilityTimeoutSec'] as int? ?? 10,
        defaultProtocol: json['defaultProtocol'] != null
            ? ArchiveProtocol.values[json['defaultProtocol'] as int]
            : ArchiveProtocol.smb,
        thumbnailMaxKB: json['thumbnailMaxKB'] as int? ?? 100,
        miniMaxKB: json['miniMaxKB'] as int? ?? 10,
        requireConfirmedArchival: true, // ALWAYS true, regardless of JSON content
        archiveHost: json['archiveHost'] as String? ?? '',
        archivePath: json['archivePath'] as String? ?? '',
        archiveUsername: json['archiveUsername'] as String?,
        archivePassword: json['archivePassword'] as String?,
        archivePort: json['archivePort'] as int?,
        enabledByDefault: json['enabledByDefault'] as bool? ?? false,
        batchRetrievalMaxItems: json['batchRetrievalMaxItems'] as int? ?? 50,
        archiveCheckIntervalMinutes:
            json['archiveCheckIntervalMinutes'] as int? ?? 60,
      );
}
