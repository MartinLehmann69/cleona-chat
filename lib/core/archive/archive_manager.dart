// Orchestrates the Media Auto-Archive system.
//
// Responsible for:
// - Periodic archive checks (based on config interval)
// - Network state verification (SSID + share reachability)
// - Tier transitions (Original -> Thumbnail -> Mini -> MetadataOnly)
// - Storage budget enforcement (eviction when exceeded)
// - Security rule: Never delete without confirmed archival

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_transport.dart';
import 'package:cleona/core/archive/archive_types.dart';
import 'package:cleona/core/service/service_types.dart';

/// Callback for archive status changes.
typedef ArchiveStatusCallback = void Function(
    String messageId, ArchiveStatus status);

/// Manages automatic media archival.
class ArchiveManager {
  final ArchiveConfig config;
  final ArchiveTransport transport;
  final String profileDir;

  Timer? _scheduler;
  bool _running = false;

  /// Persisted archive entries, indexed by messageId.
  final Map<String, ArchiveEntry> _entries = {};

  /// Pin status per message.
  final Map<String, bool> _pinned = {};

  /// Current archive status per message.
  final Map<String, ArchiveStatus> _statusMap = {};

  /// Callback on status changes.
  ArchiveStatusCallback? onStatusChanged;

  ArchiveManager({
    required this.config,
    required this.transport,
    required this.profileDir,
  });

  // -- Lifecycle -----------------------------------------------------------

  /// Starts the periodic archive scheduler.
  Future<void> startScheduler() async {
    if (_running) return;
    _running = true;
    await _loadEntries();

    _scheduler = Timer.periodic(
      Duration(minutes: config.archiveCheckIntervalMinutes),
      (_) => runArchiveCheck(),
    );
  }

  /// Stops the scheduler.
  Future<void> stopScheduler() async {
    _running = false;
    _scheduler?.cancel();
    _scheduler = null;
  }

  /// Performs a single archive check.
  ///
  /// 1. Checks network conditions (SSID, share reachability)
  /// 2. Scans conversations for archivable media
  /// 3. Archives and performs tier transitions
  /// 4. Evicts when budget is exceeded
  Future<ArchiveCheckResult> runArchiveCheck({
    String? currentSSID,
    Map<String, Conversation>? conversations,
  }) async {
    final result = ArchiveCheckResult();

    // Network check
    final ssid = currentSSID ?? await getCurrentSSID();
    final shareReachable = await checkShareReachability();
    final ready = config.isArchiveReady(
      currentSSID: ssid,
      shareReachable: shareReachable,
      allowedSSIDs: config.allowedSSIDs,
    );

    if (!ready) {
      result.skippedReason = 'Network not ready (SSID: $ssid, Share: $shareReachable)';
      return result;
    }

    // Scan conversations
    if (conversations != null) {
      for (final conv in conversations.values) {
        if (!ArchiveConfig.isConversationEligible(conv)) continue;

        for (final msg in conv.messages) {
          if (!msg.isMedia) continue;
          if (!ArchiveConfig.isMediaArchivable(msg.mimeType)) continue;

          final age = DateTime.now().difference(msg.timestamp);
          if (!config.shouldArchive(age, pinned: isPinned(msg.id))) continue;

          // Already archived?
          if (_entries.containsKey(msg.id)) {
            // Check tier transition
            await _checkTierTransition(msg.id, age);
            result.tierChecked++;
            continue;
          }

          // Archive
          final success = await _archiveMessage(msg, conv);
          if (success) {
            result.archived++;
          } else {
            result.failed++;
          }
        }
      }
    }

    // Budget-Enforcement
    final evicted = await _enforceStorageBudget();
    result.evicted = evicted;

    await _saveEntries();
    return result;
  }

  // -- Network detection ---------------------------------------------------

  /// Determine current WiFi SSID (Linux: nmcli/iwgetid).
  Future<String?> getCurrentSSID() async {
    try {
      // Try nmcli first (NetworkManager).
      final result = await Process.run(
          'nmcli', ['-t', '-f', 'active,ssid', 'dev', 'wifi']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        for (final line in lines) {
          if (line.startsWith('yes:')) {
            return line.substring(4).trim();
          }
        }
      }

      // Fallback: iwgetid.
      final result2 = await Process.run('iwgetid', ['-r']);
      if (result2.exitCode == 0) {
        final ssid = (result2.stdout as String).trim();
        if (ssid.isNotEmpty) return ssid;
      }
    } catch (_) {
      // No WiFi tool available.
    }
    return null;
  }

  /// Check share reachability.
  Future<bool> checkShareReachability() async {
    try {
      return await transport.testConnectivity(
        timeout: Duration(seconds: config.shareReachabilityTimeoutSec),
      );
    } catch (_) {
      return false;
    }
  }

  // -- Archival ------------------------------------------------------------

  /// Archive a single media item.
  Future<bool> _archiveMessage(UiMessage msg, Conversation conv) async {
    if (msg.filePath == null) return false;
    final file = File(msg.filePath!);
    if (!file.existsSync()) return false;

    _updateStatus(msg.id, ArchiveStatus.uploading);

    try {
      final data = await file.readAsBytes();
      final contentHashHex = _computeSimpleHash(data);
      final archiveFilename = generateArchiveFilename(contentHashHex, msg.mimeType);

      // Remote path: <Identity>/<Chat>/<YYYY-MM>/<filename>
      final monthDir = _monthDir(msg.timestamp);
      final chatName = _sanitizeName(conv.displayName);
      final remotePath = '$chatName/$monthDir/$archiveFilename';

      // Create directory and upload.
      await transport.createDirectory('$chatName/$monthDir');
      await transport.uploadFile(data, remotePath, onProgress: (sent, total) {
        // Progress could be forwarded to UI.
      });

      // Verify: file exists on share.
      final exists = await transport.fileExists(remotePath);
      if (!exists) {
        _updateStatus(msg.id, ArchiveStatus.failed);
        return false;
      }

      // Generate share URL.
      final shareUrl = ArchiveConfig.generateShareUrl(
        config.defaultProtocol,
        '', // Host is set on connect
        remotePath,
        archiveFilename,
      );

      // Create entry.
      final entry = ArchiveEntry(
        messageId: msg.id,
        conversationId: msg.conversationId,
        shareUrl: shareUrl,
        archivedAt: DateTime.now(),
        tier: isPinned(msg.id)
            ? config.archivedTierForPinned()
            : config.tierForAge(DateTime.now().difference(msg.timestamp)),
        contentHash: contentHashHex,
        pinned: isPinned(msg.id),
        fileSizeBytes: data.length,
        mimeType: msg.mimeType,
        originalFilename: msg.filename,
      );

      _entries[msg.id] = entry;
      _updateStatus(msg.id, ArchiveStatus.confirmed);
      return true;
    } catch (e) {
      _updateStatus(msg.id, ArchiveStatus.failed);
      return false;
    }
  }

  /// Check and perform tier transition.
  Future<void> _checkTierTransition(String messageId, Duration age) async {
    final entry = _entries[messageId];
    if (entry == null) return;

    final targetTier = config.tierForAge(age, pinned: entry.pinned);
    if (targetTier.index <= entry.tier.index) return; // No downgrade needed

    // Security rule: only downgrade if archived
    if (!config.canDeleteLocal(getStatus(messageId))) return;

    // Create new entry with updated tier
    _entries[messageId] = ArchiveEntry(
      messageId: entry.messageId,
      conversationId: entry.conversationId,
      shareUrl: entry.shareUrl,
      archivedAt: entry.archivedAt,
      tier: targetTier,
      contentHash: entry.contentHash,
      pinned: entry.pinned,
      fileSizeBytes: entry.fileSizeBytes,
      mimeType: entry.mimeType,
      originalFilename: entry.originalFilename,
    );
  }

  /// Budget enforcement: evict oldest unpinned media.
  Future<int> _enforceStorageBudget() async {
    final usedMB = await getUsedStorageMB();
    if (!config.needsEviction(usedMB: usedMB)) return 0;

    // Sort by archivedAt (oldest first), only unpinned.
    final evictable = _entries.values
        .where((e) => config.isEvictableForBudget(pinned: e.pinned))
        .where((e) => config.evictionAction(e.tier) == EvictionAction.downgrade)
        .toList()
      ..sort((a, b) => a.archivedAt.compareTo(b.archivedAt));

    var evicted = 0;
    for (final entry in evictable) {
      if (!config.needsEviction(usedMB: await getUsedStorageMB())) break;

      // Downgrade to next tier.
      final nextTier = ArchiveTier.values[entry.tier.index + 1];
      _entries[entry.messageId] = ArchiveEntry(
        messageId: entry.messageId,
        conversationId: entry.conversationId,
        shareUrl: entry.shareUrl,
        archivedAt: entry.archivedAt,
        tier: nextTier,
        contentHash: entry.contentHash,
        pinned: entry.pinned,
        fileSizeBytes: entry.fileSizeBytes,
        mimeType: entry.mimeType,
        originalFilename: entry.originalFilename,
      );
      evicted++;
    }

    return evicted;
  }

  // -- Pin management ------------------------------------------------------

  /// Pin/unpin a media item.
  void setPin(String messageId, bool pinned) {
    _pinned[messageId] = pinned;
    final entry = _entries[messageId];
    if (entry != null) {
      _entries[messageId] = ArchiveEntry(
        messageId: entry.messageId,
        conversationId: entry.conversationId,
        shareUrl: entry.shareUrl,
        archivedAt: entry.archivedAt,
        tier: pinned ? ArchiveTier.original : entry.tier,
        contentHash: entry.contentHash,
        pinned: pinned,
        fileSizeBytes: entry.fileSizeBytes,
        mimeType: entry.mimeType,
        originalFilename: entry.originalFilename,
      );
    }
  }

  /// Whether a media item is pinned.
  bool isPinned(String messageId) => _pinned[messageId] ?? false;

  // -- Status tracking -----------------------------------------------------

  /// Query the current archive status of a message.
  ArchiveStatus getStatus(String messageId) =>
      _statusMap[messageId] ?? ArchiveStatus.pending;

  void _updateStatus(String messageId, ArchiveStatus status) {
    _statusMap[messageId] = status;
    onStatusChanged?.call(messageId, status);
  }

  // -- Storage tracking ----------------------------------------------------

  /// Used media storage in MB (local media files).
  Future<int> getUsedStorageMB() async {
    final mediaDir = Directory('$profileDir/media');
    if (!mediaDir.existsSync()) return 0;

    var totalBytes = 0;
    await for (final entity in mediaDir.list()) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes ~/ (1024 * 1024);
  }

  /// Return all archive entries.
  List<ArchiveEntry> get entries => _entries.values.toList();

  /// Pending archivals.
  List<ArchiveEntry> get pendingEntries =>
      _entries.values.where((e) => getStatus(e.messageId) == ArchiveStatus.pending).toList();

  /// Filter entries (delegates to archive_types.dart).
  List<ArchiveEntry> queryEntries({
    DateTime? from,
    DateTime? to,
    String? conversationId,
    int? maxItems,
  }) {
    return filterArchiveEntries(
      _entries.values.toList(),
      from: from,
      to: to,
      conversationId: conversationId,
      maxItems: maxItems ?? config.batchRetrievalMaxItems,
    );
  }

  // -- Batch-Retrieval ----------------------------------------------------

  /// Retrieve archived media from share.
  Future<Uint8List?> retrieveArchivedMedia(
    String messageId, {
    ProgressCallback? onProgress,
  }) async {
    final entry = _entries[messageId];
    if (entry == null) return null;

    try {
      // Convert share URL to remote path.
      final remotePath = _shareUrlToRemotePath(entry.shareUrl);
      return await transport.downloadFile(remotePath, onProgress: onProgress);
    } catch (_) {
      return null;
    }
  }

  // -- Persistence ---------------------------------------------------------

  String get _archiveFilePath => '$profileDir/archive_entries.json';

  Future<void> _loadEntries() async {
    final file = File(_archiveFilePath);
    if (!file.existsSync()) return;

    try {
      final jsonStr = await file.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final entriesList = data['entries'] as List<dynamic>? ?? [];
      for (final e in entriesList) {
        final entry = ArchiveEntry.fromJson(e as Map<String, dynamic>);
        _entries[entry.messageId] = entry;
        _statusMap[entry.messageId] = ArchiveStatus.confirmed;
      }

      final pinnedMap = data['pinned'] as Map<String, dynamic>? ?? {};
      for (final e in pinnedMap.entries) {
        _pinned[e.key] = e.value as bool;
      }
    } catch (_) {
      // Corrupt file — start fresh.
    }
  }

  Future<void> _saveEntries() async {
    final data = {
      'entries': _entries.values.map((e) => e.toJson()).toList(),
      'pinned': _pinned,
    };
    final file = File(_archiveFilePath);
    await file.writeAsString(jsonEncode(data));
  }

  // -- Helper methods ------------------------------------------------------

  String _monthDir(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

  String _sanitizeName(String name) =>
      name.replaceAll(RegExp(r'[^\w\-. ]'), '_').trim();

  String _computeSimpleHash(Uint8List data) {
    // Simple hash for deduplication (FNV-1a 64-bit as hex).
    // In production, SodiumFFI.sha256 would be used.
    var hash = 0xcbf29ce484222325;
    for (final byte in data) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String _shareUrlToRemotePath(String shareUrl) {
    // Remove protocol prefix, remove host.
    final uri = Uri.parse(shareUrl);
    return uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
  }
}

/// Result of an archive check.
class ArchiveCheckResult {
  int archived = 0;
  int failed = 0;
  int tierChecked = 0;
  int evicted = 0;
  String? skippedReason;

  bool get wasSkipped => skippedReason != null;

  @override
  String toString() => wasSkipped
      ? 'ArchiveCheck: skipped ($skippedReason)'
      : 'ArchiveCheck: $archived archived, $failed failed, '
          '$tierChecked tier checks, $evicted evicted';
}
