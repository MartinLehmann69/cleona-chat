// The tile an archived medium gets in the chat (§21.6, S392/C2).
//
// §21.6 gives the archive four tiers, and the last three are things a person
// looks at: a preview, a mini, and "a metadata reference (date, size, type
// icon)". Until S392 the chat drew none of them. What it drew instead were
// three fallbacks meant for a DIFFERENT fact — "not downloaded yet" — and the
// report `S392-BAU-PLATZHALTER.md` §2.2 measured what each of them said about
// an offloaded file:
//
//   * image  -> the SENDER's transmission thumbnail, with no hint that the
//               original sits on the share, no date, no size and no way to
//               fetch it back;
//   * video  -> a grey 240x135 box with a camera icon, i.e. "this was never
//               downloaded" about a file that WAS here and that the archive
//               moved away;
//   * audio  -> the same claim through the same branch.
//
// This file replaces all three for archived media. It is deliberately split
// into a decision and a drawing:
//
//   [ArchiveTileLayout.of]  — which tile, and with which bytes. Pure, no
//                             widgets, no context; this is the statement a
//                             probe can measure.
//   [ArchivePlaceholderTile] — the drawing.
//
// Wording comes from `archive_placeholder_labels.dart` (S392/C3) through an
// [ArchiveLabelLookup]; nothing here builds a sentence (working rule 7).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_placeholder.dart';
import 'package:cleona/core/service/service_types.dart' show UiMessage;
import 'package:cleona/ui/components/archive_placeholder_labels.dart';
import 'package:cleona/ui/components/archive_retrieval_state.dart';

/// Which of the three tiles an archived medium gets.
enum ArchiveTileKind {
  /// Tier 2 — the 512 px preview, drawn large.
  preview,

  /// Tier 3 — the ~64 px mini, drawn beside the metadata.
  mini,

  /// Tier 4 — type icon, name, size, date. Also the answer whenever a tier
  /// that wants a picture has none.
  metadata,
}

/// The decision: which tile, and with which image bytes.
///
/// Built once and handed to the widget, so the base64 is decoded exactly once
/// per build rather than once for the choice and again for the drawing.
@immutable
class ArchiveTileLayout {
  final ArchiveTileKind kind;

  /// The decoded picture, or `null` — then [kind] is
  /// [ArchiveTileKind.metadata] and there is nothing to draw.
  final Uint8List? imageBytes;

  const ArchiveTileLayout._(this.kind, this.imageBytes);

  /// Chooses the tile for [info].
  ///
  /// **A missing picture is never a missing tile.** `miniBase64` is empty
  /// today for two independent reasons and both are permanent enough to
  /// design for: `ArchiveManager.applyArchiveView` does not yet stamp the
  /// field at all (`archive_manager.dart:567`), and video has no still to
  /// stamp — S392/B1 refuses it outright with `videoNoFrameGrab`
  /// (`S392-BAU-ARCHIV-B1.md` §1). A tier 2 or 3 medium without bytes
  /// therefore falls to the metadata tile, which is the tier the norm
  /// describes for exactly this content: date, size, type icon. Drawing an
  /// empty box instead would be the "silently wrong effect" the whole rework
  /// exists to remove.
  ///
  /// [ArchiveTier.metadataOnly] ignores any bytes that happen to be present:
  /// the tier is the archive index's statement about the medium, not a
  /// suggestion, and a tier 4 entry that still carries a stale mini must not
  /// show a picture the archive considers gone.
  factory ArchiveTileLayout.of(ArchivePlaceholderInfo info) {
    final bytes = decodeArchiveMini(info.miniBase64);
    if (bytes == null) return const ArchiveTileLayout._(ArchiveTileKind.metadata, null);
    switch (info.tier) {
      case ArchiveTier.thumbnail:
        return ArchiveTileLayout._(ArchiveTileKind.preview, bytes);
      case ArchiveTier.mini:
        return ArchiveTileLayout._(ArchiveTileKind.mini, bytes);
      case ArchiveTier.metadataOnly:
      case ArchiveTier.original:
        // `original` cannot arrive: `ArchivePlaceholder.forMessage` returns
        // null for it. Answered rather than asserted, because a crash in a
        // chat list over a stale index entry is worse than a plain tile.
        return const ArchiveTileLayout._(ArchiveTileKind.metadata, null);
    }
  }
}

/// Decodes the stored mini, or `null` when there is nothing usable.
///
/// Empty, whitespace and malformed base64 all mean the same thing to the
/// caller — "no picture" — and all three reach this function in practice: the
/// field crosses the IPC wire as an optional string and a half-written index
/// entry can carry a truncated value. A `FormatException` escaping into a
/// chat list build would take the whole conversation down.
Uint8List? decodeArchiveMini(String? base64Value) {
  final raw = base64Value?.trim();
  if (raw == null || raw.isEmpty) return null;
  try {
    final bytes = base64Decode(raw);
    return bytes.isEmpty ? null : bytes;
  } on FormatException {
    return null;
  }
}

/// The type icon for tier 4 (§21.6: "date, size, type icon").
///
/// Coarser than the chat's own file icon on purpose: at tier 4 the archive
/// knows the MIME type and nothing else, and a confident "spreadsheet" glyph
/// derived from a guess is the kind of detail that reads as a fact.
IconData archiveTypeIcon(String? mimeType) {
  final mime = mimeType?.trim().toLowerCase() ?? '';
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('video/')) return Icons.movie_outlined;
  if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mime.startsWith('text/')) return Icons.article_outlined;
  if (mime.contains('zip') ||
      mime.contains('compressed') ||
      mime.contains('tar')) {
    return Icons.folder_zip_outlined;
  }
  return Icons.inventory_2_outlined;
}

/// The rule that decides WHICH messages get a tile at all.
///
/// Returns the archived medium, or `null` when [message] must be drawn the
/// ordinary way. Two conditions, and both are load-bearing:
///
///  * `ArchivePlaceholder.forMessage` != null — the archive index has an entry
///    for this message on a tier below `original` (S392/C1); and
///  * [localFilePresent] is false — the original is really gone.
///
/// The second one is not belt and braces. §21.6's tiers are computed from the
/// age of the message alone (`ArchiveManager._checkTierTransition`), while the
/// eviction that actually removes the original is S392/B2, which is not built.
/// Today a year-old photo therefore sits on tier 4 in the index while the
/// full-size file is still on disk. Without this check the chat would hide a
/// picture it can display behind a metadata card — a regression, and the same
/// species of false statement as the three branches this tile replaces.
///
/// Lives here and not in `chat_screen.dart` so that the rule the app runs is
/// the rule a probe can measure; a probe that re-implemented it would only
/// show that the probe agrees with itself.
ArchivePlaceholderInfo? archivedMediumFor(
  UiMessage message, {
  required bool localFilePresent,
  required ArchiveRetrievalState retrievals,
}) {
  if (localFilePresent) return null;
  return ArchivePlaceholder.forMessage(
    message,
    isRetrieving: retrievals.isRetrieving(message.id),
    retrievalProgress: retrievals.progressOf(message.id),
  );
}

/// Draws an archived medium: preview, mini, or metadata.
class ArchivePlaceholderTile extends StatelessWidget {
  const ArchivePlaceholderTile({
    super.key,
    required this.info,
    required this.translate,
    this.onRetrieve,
    this.width = 240,
  });

  /// What the archive knows, as data (S392/C1).
  final ArchivePlaceholderInfo info;

  /// The wording (S392/C3). `AppLocale.tr` satisfies this.
  final ArchiveLabelLookup translate;

  /// Starts a retrieval. `null` means no path to `archive_retrieve` exists —
  /// the tile is then NOT tappable. An inert tap target that looks alive is
  /// the failure mode this whole rework is about.
  final VoidCallback? onRetrieve;

  /// Width of the tile; images are fitted inside it.
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = ArchivePlaceholderLabels.from(info, translate);
    final layout = ArchiveTileLayout.of(info);

    // A tap during a run starts nothing — the second latch, beside the one in
    // `ArchiveRetrievalState` and the binding one in `ArchiveManager`. Here it
    // also removes the ripple, so the tile does not look like it took the tap.
    final tappable = onRetrieve != null && !info.isRetrieving;

    Widget body;
    switch (layout.kind) {
      case ArchiveTileKind.preview:
        body = _preview(context, scheme, labels, layout.imageBytes!);
      case ArchiveTileKind.mini:
        body = _mini(context, scheme, labels, layout.imageBytes!);
      case ArchiveTileKind.metadata:
        body = _metadata(context, scheme, labels);
    }

    return Semantics(
      button: tappable,
      label: '${labels.title} — ${labels.tier}',
      child: InkWell(
        onTap: tappable ? onRetrieve : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              body,
              const SizedBox(height: 6),
              _footer(scheme, labels),
            ],
          ),
        ),
      ),
    );
  }

  // ── The three tiles ─────────────────────────────────────────────────────

  /// Tier 2: the picture, and under it the file's name and type.
  ///
  /// The name is not decoration. The branch this tile replaces
  /// (`chat_screen.dart`, the image thumbnail fallback) printed
  /// `message.filename` under the picture, and dropping it here would have
  /// been a quiet loss of information in the middle of a change that exists
  /// to ADD information. A probe caught exactly that: the first version of
  /// this method drew the image alone.
  Widget _preview(BuildContext context, ColorScheme scheme,
      ArchivePlaceholderLabels labels, Uint8List bytes) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _withRing(
          scheme,
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              bytes,
              width: width - 16,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // Valid base64 can still be invalid image bytes; the tile then
              // degrades to the metadata form instead of a broken glyph.
              errorBuilder: (_, _, _) => _iconBlock(scheme, 96),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _titleBlock(context, scheme, labels),
      ],
    );
  }

  Widget _mini(BuildContext context, ColorScheme scheme,
      ArchivePlaceholderLabels labels, Uint8List bytes) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _withRing(
          scheme,
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              bytes,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _iconBlock(scheme, 64),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _titleBlock(context, scheme, labels)),
      ],
    );
  }

  Widget _metadata(BuildContext context, ColorScheme scheme,
      ArchivePlaceholderLabels labels) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _withRing(scheme, _iconBlock(scheme, 48)),
        const SizedBox(width: 8),
        Expanded(child: _titleBlock(context, scheme, labels)),
      ],
    );
  }

  // ── Pieces ──────────────────────────────────────────────────────────────

  Widget _iconBlock(ColorScheme scheme, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(archiveTypeIcon(info.mimeType),
            size: size * 0.5, color: scheme.onSurfaceVariant),
      );

  Widget _titleBlock(BuildContext context, ColorScheme scheme,
          ArchivePlaceholderLabels labels) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            labels.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            labels.type,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      );

  /// Tier, size and date — the line §21.6 asks tier 4 to keep, shown on all
  /// three tiles so the person always knows WHY the medium looks like this.
  Widget _footer(ColorScheme scheme, ArchivePlaceholderLabels labels) {
    final hint = info.isRetrieving
        ? translate('archive_retrieving')
        : (onRetrieve != null ? translate('archive_retrieve_hint') : null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 12, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${labels.tier} · ${labels.size} · ${labels.date}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              hint,
              style: TextStyle(
                  fontSize: 10,
                  color: scheme.primary,
                  fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }

  /// Lays the progress ring over [child] while a retrieval runs.
  ///
  /// `value: null` is Flutter's indeterminate ring, which is exactly the right
  /// picture for "running, total size not known" — the state the holder stores
  /// as a null progress. A determinate ring at 0 % would claim a measurement
  /// nobody made.
  Widget _withRing(ColorScheme scheme, Widget child) {
    if (!info.isRetrieving) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0.45, child: child),
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            value: info.retrievalProgress,
            strokeWidth: 3,
            color: scheme.primary,
          ),
        ),
      ],
    );
  }
}
