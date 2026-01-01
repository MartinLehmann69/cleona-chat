import 'package:flutter/material.dart';

import 'package:cleona/core/channels/system_channel_api.dart';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/save_text_file.dart';
import 'package:cleona/ui/components/system_deposit_dialog.dart';

enum ContactIssueDialogResult {
  exported,
  posted,
  /// The export did not write a file.
  exportFailed,
  cancelled,
}

Future<ContactIssueDialogResult> showContactIssueDialog({
  required BuildContext context,
  required ICleonaService service,
  required ContactIssueReport report,
  required String contactNodeIdHex,
}) async {
  // Reached from a menu handler (`_showContactIssueReport`), so this is a
  // handler-side read, not a build-time watch.
  final locale = AppLocale.read(context);
  // §16.7 dual path: the export always, the deposit "only an option once
  // holders are known" (SK-3 finding B-3) — asked at the transport, not
  // derived from the readiness; an unanswerable question offers only the
  // export.
  bool canPost;
  try {
    canPost = await service.systemChannelApi.holdersKnown();
  } catch (_) {
    canPost = false;
  }
  if (!context.mounted) return ContactIssueDialogResult.cancelled;

  final result = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.contact_support, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(locale.get('contact_issue_dialog_title')),
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
              Text(locale.get('contact_issue_dialog_text')),
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
              if (!canPost) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16,
                        color: Theme.of(ctx).colorScheme.outline),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        locale.get('contact_issue_dialog_no_network'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: Text(locale.get('cancel')),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(ctx).pop('export'),
          icon: const Icon(Icons.save_alt, size: 16),
          label: Text(locale.get('contact_issue_dialog_export')),
        ),
        if (canPost)
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop('post'),
            icon: const Icon(Icons.send, size: 16),
            label: Text(locale.get('contact_issue_dialog_post')),
          ),
      ],
    ),
  );

  if (result == 'export') {
    final saved = await exportContactIssueReport(
        report, locale.get('contact_issue_dialog_save_title'));
    return switch (saved.outcome) {
      SaveTextOutcome.saved => ContactIssueDialogResult.exported,
      SaveTextOutcome.cancelled => ContactIssueDialogResult.cancelled,
      SaveTextOutcome.failed => ContactIssueDialogResult.exportFailed,
    };
  }

  if (result == 'post' && context.mounted) {
    // §16.7: the deposit goes through the preview (exact publication,
    // privacy notice, contact line) like every other report.
    final sent = await showSystemDepositFlow(
      context: context,
      api: service.systemChannelApi,
      draft: SystemDraft.contactIssue(report),
      titleKey: 'contact_issue_dialog_title',
      introKey: 'contact_issue_dialog_text',
    );
    if (sent != null && sent.ok) return ContactIssueDialogResult.posted;
    return ContactIssueDialogResult.cancelled;
  }

  return ContactIssueDialogResult.cancelled;
}


/// Saves [report] as a text file the user picks (§16.7: "file export is
/// always available").
@visibleForTesting
Future<SaveTextResult> exportContactIssueReport(
        ContactIssueReport report, String dialogTitle) =>
    saveTextFile(
      text: report.toExportText(),
      fileName: 'cleona-contact-issue-${report.contactIdShort}.txt',
      dialogTitle: dialogTitle,
    );
