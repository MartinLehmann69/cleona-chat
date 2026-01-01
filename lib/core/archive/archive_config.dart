// Central configuration for the Media Auto-Archive system.
//
// Controls: tier boundaries, storage budget, network detection,
// protocol selection and security rules.
// [ArchiveConfig.production] provides the production values,
// [ArchiveConfig.test] provides shortened values for automated tests.

import 'package:cleona/core/archive/archive_network.dart';
import 'package:cleona/core/archive/share_identity.dart';
import 'package:cleona/core/storage/message_store.dart';
import 'package:cleona/core/service/service_types.dart' show Conversation;

/// The area of the encrypted store that carries the archive setting
/// (§21.4.1).
///
/// S366: until now it lay as `archive_config.json` NAKED in the profile —
/// neither via `FileEncryption` nor via the store, but
/// `writeAsStringSync(json.encode(...))`. That is the most expensive of the
/// plaintext spots, because [ArchiveConfig.archivePassword] is written
/// along in plaintext (`toJson`, further below): the password of the
/// SMB/SFTP/FTPS storage, plus host name, path, user name and the
/// allowed Wi-Fi names — i.e. the network environment of the home.
const String kArchiveConfigArea = 'archive_config';

/// The key of the ONE record in [kArchiveConfigArea].
///
/// The setting is not a collection but exactly one state; a
/// fixed key prevents a second row from arising at all
/// (the same rationale as `kEinzelzustandSchluessel` in
/// `cleona_service_pure.dart` — independent here, because neither
/// `ipc_server.dart` nor `settings_screen.dart` should include the service library
/// for it).
const String kArchiveConfigKey = '_';

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

/// Reads the wire value back from `UiMessage.archiveTier` (S392/B3).
///
/// The tier crosses the IPC boundary as `ArchiveTier.name`. This reader
/// is the ONE reverse direction — so that the UI process does not build its
/// own string mapping that diverges with the next enum
/// value.
///
/// `null` for `null`, for nonsense and for a name this version
/// does not know. "Unknown tier" is for the display the same as "no
/// archive entry": show nothing, claim nothing.
ArchiveTier? archiveTierFromWire(Object? wire) {
  if (wire is! String) return null;
  for (final t in ArchiveTier.values) {
    if (t.name == wire) return t;
  }
  return null;
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

  /// Allowed WiFi names (SSIDs) — an optional narrowing, applied only
  /// where the platform reads the name for free (Linux, Windows; §21.6).
  /// Empty = narrows nothing.
  final List<String> allowedSSIDs;

  /// "Only in this network" — optional narrowing by subnet and gateway
  /// (§21.6). Empty = narrows nothing (VPN stays possible).
  final List<ArchiveNetwork> allowedNetworks;

  /// The share identity pinned on first use (§21.6 security rules), with
  /// the share it belongs to. Written by the archive run, never by the
  /// settings surface.
  final ShareIdentityPin? shareIdentity;

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
    this.allowedNetworks = const [],
    this.shareIdentity,
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

  /// Do the optional narrowings allow a run here (§21.6)?
  ///
  /// Evaluated BEFORE the share is probed — a run outside the configured
  /// network costs no packet. An empty narrowing narrows nothing. A
  /// configured one that cannot be evaluated (no subnet, unreadable
  /// gateway where one was captured, no SSID on Linux/Windows) does not
  /// match and skips the run. The SSID list is not applied at all where
  /// the platform does not read the name for free ([ssidReadable]).
  bool narrowingAllows({
    required CurrentNetwork? current,
    required String? currentSSID,
    required bool ssidReadable,
  }) {
    if (allowedNetworks.isNotEmpty) {
      if (current == null) return false;
      if (!allowedNetworks.any((n) => n.matches(current))) return false;
    }
    if (ssidReadable && allowedSSIDs.isNotEmpty) {
      if (currentSSID == null) return false;
      if (!allowedSSIDs.contains(currentSSID)) return false;
    }
    return true;
  }

  /// Whether archival is ready.
  ///
  /// Normative source is §21.6 (S394 wording): "the share's identity
  /// decides, not the network's name. Archiving happens when the share
  /// answers AND presents the identity pinned on first use". Reachability
  /// and identity are required; the narrowings only narrow.
  ///
  /// History: before S392 an empty SSID list returned false (the archive
  /// was a silent no-op off Linux Wi-Fi); S392 made reachability alone
  /// sufficient, which let the run deliver to whatever answered under the
  /// address in a foreign network (S392-19). Identity closes that.
  bool isArchiveReady({
    required bool narrowingAllows,
    required ShareIdentityState? identity,
    required bool shareReachable,
  }) {
    if (!narrowingAllows) return false;
    // §21.6: "never write to an unidentified share".
    if (!shareIdentityAllowsAccess(identity)) return false;
    // "never delete without confirmed archiving" begins here.
    return shareReachable;
  }

  /// The share this setting points at — the key a pin belongs to.
  String get shareTarget =>
      '${defaultProtocol.name}://$archiveHost:${archivePort ?? ''}/$archivePath';

  /// The pin in force for the CONFIGURED share, or `null` (unpinned). A pin
  /// taken from a different target does not apply: a newly typed address
  /// names a new share, which is unknown, not changed.
  String? get activeShareIdentity {
    final p = shareIdentity;
    return p != null && p.target == shareTarget ? p.value : null;
  }

  ArchiveConfig withShareIdentity(ShareIdentityPin? pin) =>
      _copy(shareIdentity: pin, clearShareIdentity: pin == null);

  ArchiveConfig withAllowedNetworks(List<ArchiveNetwork> networks) =>
      _copy(allowedNetworks: networks);

  ArchiveConfig _copy({
    ShareIdentityPin? shareIdentity,
    bool clearShareIdentity = false,
    List<ArchiveNetwork>? allowedNetworks,
  }) =>
      ArchiveConfig(
        tier1Boundary: tier1Boundary,
        tier2Boundary: tier2Boundary,
        tier3Boundary: tier3Boundary,
        storageBudgetMB: storageBudgetMB,
        allowedSSIDs: allowedSSIDs,
        allowedNetworks: allowedNetworks ?? this.allowedNetworks,
        shareIdentity:
            clearShareIdentity ? null : (shareIdentity ?? this.shareIdentity),
        shareReachabilityTimeoutSec: shareReachabilityTimeoutSec,
        defaultProtocol: defaultProtocol,
        supportedProtocols: supportedProtocols,
        thumbnailMaxKB: thumbnailMaxKB,
        miniMaxKB: miniMaxKB,
        requireConfirmedArchival: requireConfirmedArchival,
        archiveHost: archiveHost,
        archivePath: archivePath,
        archiveUsername: archiveUsername,
        archivePassword: archivePassword,
        archivePort: archivePort,
        enabledByDefault: enabledByDefault,
        batchRetrievalMaxItems: batchRetrievalMaxItems,
        archiveCheckIntervalMinutes: archiveCheckIntervalMinutes,
      );

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
        'allowedNetworks': allowedNetworks.map((n) => n.toJson()).toList(),
        if (shareIdentity != null) 'shareIdentity': shareIdentity!.toJson(),
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
        allowedNetworks: (json['allowedNetworks'] as List<dynamic>?)
                ?.map(ArchiveNetwork.fromJson)
                .whereType<ArchiveNetwork>()
                .toList() ??
            const [],
        shareIdentity: ShareIdentityPin.fromJson(json['shareIdentity']),
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

  // -- Store (S366) -------------------------------------------------------
  //
  // Four places read the setting as a FILE until S366
  // (`cleona_service.dart:_initArchive`, `ipc_server.dart`
  // `archive_test_connection`, `settings_screen.dart:_load`) and one
  // WROTE it as a file (`settings_screen.dart:_save`). Whoever switches over only the
  // writer lets the readers run into `existsSync() == false`:
  // the archive silently stays off, without an error and without a log line.
  // Therefore the path stands exactly ONCE here, and all five places go
  // through it.

  /// Reads the setting from the store. `null` means: never
  /// configured — that is the normal case and not an error.
  ///
  /// If the store throws, it is NOT caught: an unreadable store is
  /// something different from an empty one, and the caller must be able to
  /// distinguish the two (see [store] and the latch in
  /// `settings_screen.dart`).
  static ArchiveConfig? readFrom(MessageStore store) {
    final j = store.loadArea(kArchiveConfigArea)[kArchiveConfigKey];
    if (j == null) return null;
    return ArchiveConfig.fromJson(j);
  }

  /// Writes the setting as ONE record.
  ///
  /// `replaceArea` and not `putEntry`: the area carries exactly one
  /// row, and the replacement runs in a transaction — an abort
  /// midway thus does not leave half the setting behind.
  void writeTo(MessageStore store) => store.replaceArea(
      kArchiveConfigArea, {kArchiveConfigKey: toJson()});
}
