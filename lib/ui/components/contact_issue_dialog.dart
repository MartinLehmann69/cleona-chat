import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';

enum ContactIssueDialogResult {
  exported,
  posted,
  cancelled,
}

Future<ContactIssueDialogResult> showContactIssueDialog({
  required BuildContext context,
  required ICleonaService service,
  required ContactIssueReport report,
  required String contactNodeIdHex,
}) async {
  final locale = AppLocale.of(context);
  final canPost = service.peerCount > 0;

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
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: locale.get('contact_issue_dialog_save_title'),
      fileName: 'cleona-contact-issue-${report.contactIdShort}.txt',
    );
    if (savePath != null) {
      await File(savePath).writeAsString(report.toExportText());
      return ContactIssueDialogResult.exported;
    }
    return ContactIssueDialogResult.cancelled;
  }

  if (result == 'post') {
    final success =
        await service.publishContactIssueReport(contactNodeIdHex);
    if (success) return ContactIssueDialogResult.posted;
    return ContactIssueDialogResult.cancelled;
  }

  return ContactIssueDialogResult.cancelled;
}
