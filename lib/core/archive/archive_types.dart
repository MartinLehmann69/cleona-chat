// Data types for the Media Auto-Archive system.
//
// ArchiveEntry: An archived media item with metadata.
// Helper functions: filename generation, batch filtering.

import 'dart:convert';
import 'dart:typed_data';

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

  /// Tier 2 (§21.6): the preview, ~20-50 KB, produced by
  /// [ArchiveThumbnails] (`archive_thumbnail.dart`).
  ///
  /// **Why in the index record and not as a file.** The record lives in
  /// the `archive_entries` area of the [MessageStore] — a page-encrypted
  /// SQLite (§4.5.3 form 1, §21.4.2 destination 1). A second store next
  /// to the attachment's `.cmenc` would be a third storage form for
  /// 5 KB, with its own sweeper and its own orphan question: when the
  /// original goes, the image must stay — when the message goes, it must
  /// go too. On the index record both hold by themselves.
  ///
  /// `null` while the tier is `original`, or when the source was not a
  /// still image (video: see the header of `archive_thumbnail.dart`).
  final Uint8List? previewBytes;

  /// Tier 3 (§21.6): 64 px, ~2-5 KB. This is the image that travels over
  /// IPC into the UI process; the preview stays in the service until it
  /// is needed.
  final Uint8List? miniBytes;

  /// `image/jpeg` or `image/png` — applies to [previewBytes] AND
  /// [miniBytes]. Not the original's MIME type, which is in [mimeType].
  final String? thumbnailMimeType;

  /// When the original was last brought back from the share (§21.6: "A
  /// retrieved original counts as new"). The tiers then count from here,
  /// not from the message — without it the next hourly run computed the
  /// tier from the message age again and deleted the retrieved file
  /// (S392-15). `null`: never retrieved.
  final DateTime? retrievedAt;

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
    this.previewBytes,
    this.miniBytes,
    this.thumbnailMimeType,
    this.retrievedAt,
  });

  /// The age that decides the tier (§21.6): counted from the retrieval when
  /// the original was brought back later than the message arrived.
  Duration tierAge(Duration messageAge, DateTime now) {
    final r = retrievedAt;
    if (r == null) return messageAge;
    final sinceRetrieval = now.difference(r);
    return sinceRetrieval < messageAge ? sinceRetrieval : messageAge;
  }

  /// The same entry with a new tier and/or new images.
  ///
  /// Passing `null` does NOT clear an image — whoever wants to drop one
  /// (tier 4 needs none) sets [dropPreview] or [dropMini]. Otherwise
  /// every caller that only raises the tier would be a silent deleter.
  ArchiveEntry copyWith({
    ArchiveTier? tier,
    bool? pinned,
    Uint8List? previewBytes,
    Uint8List? miniBytes,
    String? thumbnailMimeType,
    bool dropPreview = false,
    bool dropMini = false,
  }) =>
      ArchiveEntry(
        messageId: messageId,
        conversationId: conversationId,
        shareUrl: shareUrl,
        archivedAt: archivedAt,
        tier: tier ?? this.tier,
        contentHash: contentHash,
        pinned: pinned ?? this.pinned,
        fileSizeBytes: fileSizeBytes,
        mimeType: mimeType,
        originalFilename: originalFilename,
        previewBytes: dropPreview ? null : (previewBytes ?? this.previewBytes),
        miniBytes: dropMini ? null : (miniBytes ?? this.miniBytes),
        thumbnailMimeType: thumbnailMimeType ?? this.thumbnailMimeType,
        retrievedAt: retrievedAt,
      );

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
        // Base64, because the record goes into the store as JSON. The
        // one-third overhead is the price of the index having ONE
        // format; on a 5 KB mini that is 1.7 KB.
        if (previewBytes != null) 'preview': base64Encode(previewBytes!),
        if (miniBytes != null) 'mini': base64Encode(miniBytes!),
        if (thumbnailMimeType != null) 'thumbMime': thumbnailMimeType,
        if (retrievedAt != null)
          'retrievedAt': retrievedAt!.millisecondsSinceEpoch,
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
        previewBytes: _decodeImageBytes(json['preview']),
        miniBytes: _decodeImageBytes(json['mini']),
        thumbnailMimeType: json['thumbMime'] as String?,
        retrievedAt: json['retrievedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['retrievedAt'] as int)
            : null,
      );

  /// A damaged image costs the image, not the entry — the entry carries
  /// the mapping message -> share location and is the most expensive
  /// thing in the index (`archive_manager.dart`, data-loss latch).
  static Uint8List? _decodeImageBytes(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }
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
