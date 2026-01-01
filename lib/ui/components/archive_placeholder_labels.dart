// Wording for an archived medium (§21.6, S392/C3).
//
// This is the other half of S392/C1. `ArchivePlaceholderInfo` carries numbers,
// a tier and a MIME type; everything a person reads is built here, in the UI
// process, through `AppLocale`. Until S392 the four strings were assembled in
// `lib/core/archive/archive_placeholder.dart` — in English, in the service
// process, where `AppLocale` does not exist (§22.6: on Linux, Windows and
// macOS service and UI are two processes). Working rule 7 could not be met
// from there at all.
//
// Deliberately free of Flutter: the caller hands in a lookup, so the wording
// can be measured for all 34 locales without a widget tree. The one caller in
// production passes `AppLocale.tr`, whose signature this typedef matches.

import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_placeholder.dart';

/// A translator. `AppLocale.tr` satisfies this exactly.
typedef ArchiveLabelLookup = String Function(String key,
    [Map<String, String>? params]);

/// The four strings a placeholder shows, plus the headline.
class ArchivePlaceholderLabels {
  /// Tier wording, e.g. "Archived (preview)".
  final String tier;

  /// Type wording, e.g. "JPEG image".
  final String type;

  /// Size of the original, e.g. "2.3 MB", or "Size unknown".
  final String size;

  /// Archiving date, e.g. "17.09.2026", or "Date unknown".
  final String date;

  /// What to put on the first line: the original file name when it is known,
  /// otherwise the type wording. Never an untranslated fallback.
  final String title;

  const ArchivePlaceholderLabels({
    required this.tier,
    required this.type,
    required this.size,
    required this.date,
    required this.title,
  });

  /// Builds the wording for [info] through [t].
  factory ArchivePlaceholderLabels.from(
      ArchivePlaceholderInfo info, ArchiveLabelLookup t) {
    final type = archiveTypeLabel(info.mimeType, t);
    final name = info.originalFilename?.trim();
    return ArchivePlaceholderLabels(
      tier: archiveTierLabel(info.tier, t),
      type: type,
      size: archiveSizeLabel(info.fileSizeBytes, t),
      date: archiveDateLabel(info.archivedAt, t),
      title: (name == null || name.isEmpty) ? type : name,
    );
  }
}

/// Wording for a storage tier.
///
/// [ArchiveTier.original] yields the empty string. It cannot arrive here:
/// `ArchivePlaceholder.forMessage` returns `null` for it, which is where the
/// guard belongs — a second check here would only duplicate it, and a
/// made-up label would be exactly the false statement C1 removed.
String archiveTierLabel(ArchiveTier tier, ArchiveLabelLookup t) {
  switch (tier) {
    case ArchiveTier.thumbnail:
      return t('archive_tier_thumbnail');
    case ArchiveTier.mini:
      return t('archive_tier_mini');
    case ArchiveTier.metadataOnly:
      return t('archive_tier_metadata');
    case ArchiveTier.original:
      return '';
  }
}

/// Wording for a MIME type, e.g. `image/jpeg` -> "JPEG-Bild".
///
/// Anything not recognised becomes the plain word for "file". Guessing a
/// family from a file extension is not attempted: a wrong type icon is worse
/// than a generic one.
String archiveTypeLabel(String? mimeType, ArchiveLabelLookup t) {
  final mime = mimeType?.trim().toLowerCase() ?? '';
  final slash = mime.indexOf('/');
  if (slash <= 0 || slash == mime.length - 1) return t('archive_type_file');

  final top = mime.substring(0, slash);
  final sub = mime.substring(slash + 1);
  final format = _formatToken(top, sub);
  if (format.isEmpty) return t('archive_type_file');

  switch (top) {
    case 'image':
      return t('archive_type_image', {'format': format});
    case 'video':
      return t('archive_type_video', {'format': format});
    case 'audio':
      return t('archive_type_audio', {'format': format});
    case 'text':
      return t('archive_type_document', {'format': format});
  }
  if (_documentFormats.contains(format)) {
    return t('archive_type_document', {'format': format});
  }
  if (_archiveFormats.contains(format)) {
    return t('archive_type_archive', {'format': format});
  }
  return t('archive_type_file');
}

/// Size of the original. `null` and a negative value both mean "not known" —
/// printing "0 B" for an unmeasured file is the kind of confident wrong
/// number this rework exists to remove.
String archiveSizeLabel(int? bytes, ArchiveLabelLookup t) {
  if (bytes == null || bytes < 0) return t('archive_size_unknown');
  if (bytes < 1024) return t('archive_size_b', {'size': '$bytes'});

  final sep = t('archive_decimal_sep');
  const kib = 1024;
  const mib = 1024 * 1024;
  const give = 1024 * 1024 * 1024;
  if (bytes < mib) {
    return t('archive_size_kb', {'size': _oneDecimal(bytes / kib, sep)});
  }
  if (bytes < give) {
    return t('archive_size_mb', {'size': _oneDecimal(bytes / mib, sep)});
  }
  return t('archive_size_gb', {'size': _oneDecimal(bytes / give, sep)});
}

/// Archiving date in the locale's own field order (`archive_date_pattern`).
///
/// Local time, because the person reads it next to message timestamps that
/// are local too. Day and month two digits, year four — a pattern that only
/// reorders fields cannot get a locale's separator or order wrong the way a
/// hard-coded `dd.MM.yyyy` did.
String archiveDateLabel(DateTime? when, ArchiveLabelLookup t) {
  if (when == null) return t('archive_date_unknown');
  final l = when.toLocal();
  return t('archive_date_pattern', {
    'd': l.day.toString().padLeft(2, '0'),
    'm': l.month.toString().padLeft(2, '0'),
    'y': l.year.toString().padLeft(4, '0'),
  });
}

// ── Internals ─────────────────────────────────────────────────────────────

/// One decimal place, with the locale's own decimal mark.
///
/// `toStringAsFixed` always produces a dot; German reads "4,0 KB", and a dot
/// there is a small but constant wrongness on every archived medium.
String _oneDecimal(double value, String separator) =>
    value.toStringAsFixed(1).replaceFirst('.', separator);

const Set<String> _documentFormats = {'PDF', 'TXT', 'RTF'};
const Set<String> _archiveFormats = {'ZIP', 'GZIP', 'TAR', '7Z', 'RAR'};

/// Short, readable name of a MIME subtype.
///
/// The aliases exist because the raw subtype reads badly on a chat tile:
/// `video/quicktime` is "MOV" to a person, and `audio/mpeg` is "MP3" — but
/// `video/mpeg` is genuinely MPEG, which is why the alias table is keyed by
/// the full type and not by the subtype alone.
String _formatToken(String top, String sub) {
  var s = sub;
  final semi = s.indexOf(';');
  if (semi >= 0) s = s.substring(0, semi); // drop parameters
  final plus = s.indexOf('+');
  if (plus > 0) s = s.substring(0, plus); // svg+xml -> svg
  s = s.trim();
  if (s.startsWith('x-')) s = s.substring(2);
  if (s.startsWith('vnd.')) s = s.substring(4);

  final alias = _aliases['$top/$sub'] ?? _subAliases[s];
  if (alias != null) return alias;
  return s.toUpperCase();
}

const Map<String, String> _aliases = {
  'audio/mpeg': 'MP3',
  'video/quicktime': 'MOV',
  'text/plain': 'TXT',
};

const Map<String, String> _subAliases = {
  'matroska': 'MKV',
  '7z-compressed': '7Z',
  'gzip': 'GZIP',
};
