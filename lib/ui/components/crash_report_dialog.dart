import 'package:flutter/material.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/channels/crash_reporter.dart';
import 'package:cleona/core/channels/system_channels.dart';

/// Result of the crash report dialog interaction.
enum CrashDialogResult {
  /// User approved publishing a new crash report.
  publish,
  /// User dismissed the dialog without publishing (new crash).
  discard,
  /// User tapped "OK" on a known-crash dialog (no navigation).
  dismissKnown,
  /// User tapped "Zum Bericht" on a known-crash dialog.
  navigateToReport,
  /// Rate limit reached, user tapped OK.
  rateLimitAck,
}

/// Shows the appropriate crash report popup (§9.5.4).
///
/// Returns a [CrashDialogResult] indicating what the user chose, plus
/// the existing post ID for the [navigateToReport] case.
class CrashReportDialogResult {
  final CrashDialogResult action;
  final String? existingPostId;

  const CrashReportDialogResult(this.action, {this.existingPostId});
}

Future<CrashReportDialogResult> showCrashReportDialog({
  required BuildContext context,
  required CrashReporter reporter,
  required CrashReport report,
}) async {
  // Rate limit check
  if (reporter.isRateLimited) {
    return _showRateLimitDialog(context);
  }

  // Duplicate check
  final existingPostId = reporter.findExistingReport(report.fingerprint);
  if (existingPostId != null) {
    final dupeCount = reporter.countDuplicates(report.fingerprint) + 1;
    return _showKnownCrashDialog(context, dupeCount, existingPostId);
  }

  // New crash — consent popup
  return _showNewCrashDialog(context, report);
}

// ── Variant 1: New crash (consent required) ─────────────────────────

Future<CrashReportDialogResult> _showNewCrashDialog(
  BuildContext context,
  CrashReport report,
) async {
  final locale = AppLocale.read(context);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(locale.get('crash_dialog_title')),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(locale.get('crash_dialog_consent_text')),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  report.toPreviewText(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(locale.get('crash_dialog_discard')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(locale.get('crash_dialog_publish')),
        ),
      ],
    ),
  );

  if (result == true) {
    return const CrashReportDialogResult(CrashDialogResult.publish);
  }
  return const CrashReportDialogResult(CrashDialogResult.discard);
}

// ── Variant 2: Known crash (info + link) ────────────────────────────

Future<CrashReportDialogResult> _showKnownCrashDialog(
  BuildContext context,
  int reportCount,
  String existingPostId,
) async {
  final locale = AppLocale.read(context);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(locale.get('crash_dialog_known_title')),
          ),
        ],
      ),
      content: Text(
        locale.get('crash_dialog_known_text')
            .replaceFirst('{count}', reportCount.toString()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(locale.get('crash_dialog_ok')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(locale.get('crash_dialog_goto_report')),
        ),
      ],
    ),
  );

  if (result == true) {
    return CrashReportDialogResult(
      CrashDialogResult.navigateToReport,
      existingPostId: existingPostId,
    );
  }
  return const CrashReportDialogResult(CrashDialogResult.dismissKnown);
}

// ── Variant 3: Rate limit reached ───────────────────────────────────

Future<CrashReportDialogResult> _showRateLimitDialog(
  BuildContext context,
) async {
  final locale = AppLocale.read(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(locale.get('crash_dialog_rate_title')),
          ),
        ],
      ),
      content: Text(locale.get('crash_dialog_rate_text')),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(locale.get('crash_dialog_ok')),
        ),
      ],
    ),
  );
  return const CrashReportDialogResult(CrashDialogResult.rateLimitAck);
}
