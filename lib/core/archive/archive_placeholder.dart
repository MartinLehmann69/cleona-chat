// Placeholder description for archived media (§21.6).
//
// This type carries DATA ONLY. Until S392/C1 it also carried three ready-made
// strings — `displayText`, `typeDescription`, `formattedSize` — built right
// here, in the core layer, in English: 'JPEG Image', '2.3 MB',
// 'Archived (preview)'. That cannot be retrofitted to working rule 7 (every
// user-visible string in all 34 locales), because `AppLocale` lives in the
// UI process and this file runs in the service process (§22.6). Formatting
// therefore moved to `lib/ui/components/archive_placeholder_labels.dart`,
// which is handed a translator.
//
// The `original` tier produces NO placeholder: the file is still on the
// device, and drawing a placeholder over it is the false statement this
// rework exists to remove.

import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/service/service_types.dart' show UiMessage;

/// What the UI needs in order to draw an archived medium, as data.
///
/// Every field is a measurement, never a sentence. The one thing that looks
/// like a decision — [tier] — is the archive index's own value, carried over
/// IPC by S392/B3 and read back with [archiveTierFromWire].
class ArchivePlaceholderInfo {
  /// The storage tier. Never [ArchiveTier.original] — see the file header.
  final ArchiveTier tier;

  /// When the medium was offloaded. §21.6 names the date explicitly as part
  /// of what tier 4 still shows ("a metadata reference (date, size, type
  /// icon)"). `null` means the archive entry carried no date; the UI says so
  /// rather than inventing one.
  final DateTime? archivedAt;

  /// Size of the ORIGINAL in bytes, `null` when unknown.
  ///
  /// Nullable on purpose: `0` and "not known" are different facts, and a
  /// placeholder that prints '0 B' for the second one is the same class of
  /// lie as the one this rework removes.
  final int? fileSizeBytes;

  /// MIME type of the original, `null` when unknown.
  final String? mimeType;

  /// The original file name, `null` when unknown.
  final String? originalFilename;

  /// Tier-3 mini image (~2–5 KB, 64 px) as base64.
  ///
  /// **Empty today and that is not a defect.** The downscaler is S392/B1
  /// (`archive_thumbnail.dart`); until it lands, `applyArchiveView` never
  /// fills the wire field. Consumers MUST render the tier without it — a
  /// missing mini is a missing picture, never a missing placeholder.
  final String? miniBase64;

  /// Whether a retrieval is currently running (S392/B4).
  final bool isRetrieving;

  /// Retrieval progress 0.0–1.0, `null` while no retrieval runs.
  final double? retrievalProgress;

  /// Whether the medium is pinned.
  ///
  /// **Nothing fills this over IPC yet.** S392/B3 deliberately left `pinned`
  /// off the wire, so the UI process cannot know it; the parameter exists for
  /// the in-process caller and defaults to false. Reported as an open point
  /// rather than silently defaulted to something prettier.
  final bool isPinned;

  /// Where the original sits on the share — the retrieval path for B4.
  /// `null` when the wire field was absent.
  final String? shareUrl;

  /// The message this placeholder stands for.
  final String messageId;

  const ArchivePlaceholderInfo({
    required this.tier,
    required this.messageId,
    this.archivedAt,
    this.fileSizeBytes,
    this.mimeType,
    this.originalFilename,
    this.miniBase64,
    this.isRetrieving = false,
    this.retrievalProgress,
    this.isPinned = false,
    this.shareUrl,
  });
}

/// Builds [ArchivePlaceholderInfo] from the state the UI process actually has.
class ArchivePlaceholder {
  /// The placeholder for [m], or `null` when [m] must be drawn normally.
  ///
  /// Returns `null` in exactly three cases, and they are different reasons for
  /// the same answer:
  ///
  ///  * `archiveTier == null` — no archive entry for this message. NOT the
  ///    same as `original` (see `service_types.dart`), and the reason this
  ///    check cannot be folded into the next one.
  ///  * an unknown tier name — a newer service process talking to an older
  ///    UI. Showing nothing beats guessing a tier.
  ///  * [ArchiveTier.original] — archived, but the file is still here.
  static ArchivePlaceholderInfo? forMessage(
    UiMessage m, {
    bool isRetrieving = false,
    double? retrievalProgress,
    bool isPinned = false,
  }) {
    final tier = archiveTierFromWire(m.archiveTier);
    if (tier == null || tier == ArchiveTier.original) return null;

    return ArchivePlaceholderInfo(
      tier: tier,
      messageId: m.id,
      archivedAt: m.archivedAt,
      fileSizeBytes: m.fileSize,
      mimeType: m.mimeType,
      originalFilename: m.filename,
      miniBase64: m.archiveMiniBase64,
      isRetrieving: isRetrieving,
      retrievalProgress: retrievalProgress,
      isPinned: isPinned,
      shareUrl: m.archiveShareUrl,
    );
  }
}
