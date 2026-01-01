// Data types for the Media Auto-Archive system.
//
// ArchiveEntry: An archived media item with metadata.
// Helper functions: filename generation, batch filtering.

import 'package:cleona/core/archive/archive_config.dart';

/// An archived media entry.
class ArchiveEntry {
  final String messageId;
  final String conversationId;
  final String shareUrl;
  final DateTime archivedAt;
  final ArchiveTier tier;
  final String contentHash;
  final bool pinned;
  final int fileSizeBytes;
  final String? mimeType;
  final String? originalFilename;

  ArchiveEntry({
    required this.messageId,
    required this.conversationId,
    required this.shareUrl,
    required this.archivedAt,
    required this.tier,
    required this.contentHash,
    this.pinned = false,
    this.fileSizeBytes = 0,
    this.mimeType,
    this.originalFilename,
  });

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'conversationId': conversationId,
        'shareUrl': shareUrl,
        'archivedAt': archivedAt.millisecondsSinceEpoch,
        'tier': tier.index,
        'contentHash': contentHash,
        if (pinned) 'pinned': true,
        'fileSizeBytes': fileSizeBytes,
        if (mimeType != null) 'mimeType': mimeType,
        if (originalFilename != null) 'originalFilename': originalFilename,
      };

  static ArchiveEntry fromJson(Map<String, dynamic> json) => ArchiveEntry(
        messageId: json['messageId'] as String,
        conversationId: json['conversationId'] as String,
        shareUrl: json['shareUrl'] as String,
        archivedAt: DateTime.fromMillisecondsSinceEpoch(
            json['archivedAt'] as int),
        tier: ArchiveTier.values[json['tier'] as int? ?? 0],
        contentHash: json['contentHash'] as String,
        pinned: json['pinned'] as bool? ?? false,
        fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
        mimeType: json['mimeType'] as String?,
        originalFilename: json['originalFilename'] as String?,
      );
}

/// Generates a content-hash-based filename for deduplication.
///
/// Format: `hash-hex-prefix.extension`
/// Same content -> same filename -> automatic deduplication.
String generateArchiveFilename(String contentHashHex, String? mimeType) {
  if (contentHashHex.isEmpty) {
    throw ArgumentError('contentHashHex must not be empty');
  }
  final ext = _mimeToExtension(mimeType);
  return '$contentHashHex.$ext';
}

/// Filters ArchiveEntries for batch retrieval.
///
/// [from]/[to]: Optional time range.
/// [conversationId]: Optional chat restriction.
/// [maxItems]: Max number of results.
List<ArchiveEntry> filterArchiveEntries(
  List<ArchiveEntry> entries, {
  DateTime? from,
  DateTime? to,
  String? conversationId,
  int? maxItems,
}) {
  var result = entries.where((e) {
    if (from != null && e.archivedAt.isBefore(from)) return false;
    if (to != null && e.archivedAt.isAfter(to)) return false;
    if (conversationId != null && e.conversationId != conversationId) {
      return false;
    }
    return true;
  }).toList();

  if (maxItems != null && result.length > maxItems) {
    result = result.sublist(0, maxItems);
  }
  return result;
}

/// MIME type to file extension.
String _mimeToExtension(String? mimeType) {
  if (mimeType == null || mimeType.isEmpty) return 'bin';
  final lower = mimeType.toLowerCase();
  // Images
  if (lower == 'image/jpeg' || lower == 'image/jpg') return 'jpg';
  if (lower == 'image/png') return 'png';
  if (lower == 'image/gif') return 'gif';
  if (lower == 'image/webp') return 'webp';
  if (lower == 'image/svg+xml') return 'svg';
  // Video
  if (lower == 'video/mp4') return 'mp4';
  if (lower == 'video/webm') return 'webm';
  if (lower == 'video/quicktime') return 'mov';
  // Audio
  if (lower == 'audio/ogg') return 'ogg';
  if (lower == 'audio/mpeg' || lower == 'audio/mp3') return 'mp3';
  if (lower == 'audio/aac') return 'aac';
  if (lower == 'audio/wav') return 'wav';
  // Documents
  if (lower == 'application/pdf') return 'pdf';
  if (lower == 'application/zip') return 'zip';
  if (lower == 'text/plain') return 'txt';
  // Fallback
  return 'bin';
}
