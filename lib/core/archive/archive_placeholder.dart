// Placeholder rendering for archived media.
//
// Generates visual representations based on the current ArchiveTier:
// - thumbnail: Preview image (~20-50 KB) with download tap
// - mini: Mini-thumbnail (~2-5 KB, 64px) with download tap
// - metadataOnly: Type icon + filename + size, tappable
//
// Supports progress display for retrieval actions.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_types.dart';

/// Description of a placeholder element (UI-independent).
///
/// The UI layer (Flutter) uses this data to render the appropriate widget.
/// The placeholder itself is platform-independent (no Flutter import).
class ArchivePlaceholderInfo {
  /// The current storage tier.
  final ArchiveTier tier;

  /// Display text (e.g. filename or "Image archived").
  final String displayText;

  /// Type description (e.g. "JPEG Image", "MP4 Video").
  final String typeDescription;

  /// File size as formatted string (e.g. "2.3 MB").
  final String formattedSize;

  /// Base64-encoded thumbnail (only when tier == thumbnail).
  final String? thumbnailBase64;

  /// Mini-thumbnail as Base64 (only when tier == mini).
  final String? miniBase64;

  /// Whether a tap should start retrieval.
  final bool isTappable;

  /// Whether a retrieval is in progress.
  final bool isRetrieving;

  /// Retrieval progress (0.0-1.0, null when not active).
  final double? retrievalProgress;

  /// Whether the media item is pinned.
  final bool isPinned;

  /// Share URL for reference.
  final String shareUrl;

  /// Message ID for retrieval.
  final String messageId;

  ArchivePlaceholderInfo({
    required this.tier,
    required this.displayText,
    required this.typeDescription,
    required this.formattedSize,
    this.thumbnailBase64,
    this.miniBase64,
    this.isTappable = true,
    this.isRetrieving = false,
    this.retrievalProgress,
    this.isPinned = false,
    required this.shareUrl,
    required this.messageId,
  });
}

/// Creates placeholder info based on ArchiveEntry and tier.
class ArchivePlaceholder {
  /// Create placeholder for an archived entry.
  static ArchivePlaceholderInfo build(
    ArchiveEntry entry, {
    String? thumbnailBase64,
    String? miniBase64,
    bool isRetrieving = false,
    double? retrievalProgress,
  }) {
    final typeDesc = _typeDescription(entry.mimeType);
    final sizeStr = _formatFileSize(entry.fileSizeBytes);
    final displayText = entry.originalFilename ?? _tierDisplayText(entry.tier);

    switch (entry.tier) {
      case ArchiveTier.original:
        return ArchivePlaceholderInfo(
          tier: entry.tier,
          displayText: displayText,
          typeDescription: typeDesc,
          formattedSize: sizeStr,
          thumbnailBase64: thumbnailBase64,
          isTappable: false, // Original present, no download needed
          isPinned: entry.pinned,
          shareUrl: entry.shareUrl,
          messageId: entry.messageId,
        );

      case ArchiveTier.thumbnail:
        return ArchivePlaceholderInfo(
          tier: entry.tier,
          displayText: displayText,
          typeDescription: typeDesc,
          formattedSize: sizeStr,
          thumbnailBase64: thumbnailBase64,
          isTappable: true,
          isRetrieving: isRetrieving,
          retrievalProgress: retrievalProgress,
          isPinned: entry.pinned,
          shareUrl: entry.shareUrl,
          messageId: entry.messageId,
        );

      case ArchiveTier.mini:
        return ArchivePlaceholderInfo(
          tier: entry.tier,
          displayText: displayText,
          typeDescription: typeDesc,
          formattedSize: sizeStr,
          miniBase64: miniBase64,
          isTappable: true,
          isRetrieving: isRetrieving,
          retrievalProgress: retrievalProgress,
          isPinned: entry.pinned,
          shareUrl: entry.shareUrl,
          messageId: entry.messageId,
        );

      case ArchiveTier.metadataOnly:
        return ArchivePlaceholderInfo(
          tier: entry.tier,
          displayText: displayText,
          typeDescription: typeDesc,
          formattedSize: sizeStr,
          isTappable: true,
          isRetrieving: isRetrieving,
          retrievalProgress: retrievalProgress,
          isPinned: entry.pinned,
          shareUrl: entry.shareUrl,
          messageId: entry.messageId,
        );
    }
  }

  /// Generate tier-specific display text.
  static String getTierDescription(ArchiveTier tier) {
    switch (tier) {
      case ArchiveTier.original:
        return 'Original on device';
      case ArchiveTier.thumbnail:
        return 'Preview (original in archive)';
      case ArchiveTier.mini:
        return 'Mini preview (original in archive)';
      case ArchiveTier.metadataOnly:
        return 'Metadata only (original in archive)';
    }
  }

  /// Tier icon name (for Material Icons in Flutter).
  static String getTierIconName(ArchiveTier tier) {
    switch (tier) {
      case ArchiveTier.original:
        return 'image';
      case ArchiveTier.thumbnail:
        return 'photo_size_select_large';
      case ArchiveTier.mini:
        return 'photo_size_select_small';
      case ArchiveTier.metadataOnly:
        return 'link';
    }
  }

  /// Generate thumbnail from original image data (max thumbnailMaxKB).
  ///
  /// Returns the first [maxKB] KB of image data as Base64.
  /// In production, a proper image resize would be performed.
  static String? generateThumbnailBase64(
    Uint8List imageData, {
    int maxKB = 100,
  }) {
    if (imageData.isEmpty) return null;
    final maxBytes = maxKB * 1024;
    final data = imageData.length <= maxBytes
        ? imageData
        : Uint8List.fromList(imageData.sublist(0, maxBytes));
    return base64Encode(data);
  }

  /// Generate mini-thumbnail (max miniMaxKB).
  static String? generateMiniBase64(
    Uint8List imageData, {
    int maxKB = 10,
  }) {
    if (imageData.isEmpty) return null;
    final maxBytes = maxKB * 1024;
    final data = imageData.length <= maxBytes
        ? imageData
        : Uint8List.fromList(imageData.sublist(0, maxBytes));
    return base64Encode(data);
  }

  // -- Private helper methods -----------------------------------------------

  static String _tierDisplayText(ArchiveTier tier) {
    switch (tier) {
      case ArchiveTier.original:
        return 'Original';
      case ArchiveTier.thumbnail:
        return 'Archived (preview)';
      case ArchiveTier.mini:
        return 'Archived (mini)';
      case ArchiveTier.metadataOnly:
        return 'Archived (link)';
    }
  }

  static String _typeDescription(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) return 'File';
    final lower = mimeType.toLowerCase();
    if (lower.startsWith('image/')) {
      final sub = lower.substring(6).toUpperCase();
      return '$sub Image';
    }
    if (lower.startsWith('video/')) {
      final sub = lower.substring(6).toUpperCase();
      return '$sub Video';
    }
    if (lower.startsWith('audio/')) {
      final sub = lower.substring(6).toUpperCase();
      return '$sub Audio';
    }
    if (lower == 'application/pdf') return 'PDF Document';
    if (lower == 'application/zip') return 'ZIP Archive';
    if (lower == 'text/plain') return 'Text File';
    return 'File';
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
