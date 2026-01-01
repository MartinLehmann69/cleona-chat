import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cleona/core/channels/system_channel_api.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/ui/components/system_channel_post.dart';
import 'package:cleona/ui/components/system_report_widgets.dart';

/// The publication as the preview shows it: every field of the report with
/// its value unshortened, one per line — the same content that is signed
/// (§16.7: "a preview of the exact publication").
String systemPublicationText(String publication) {
  Object? decoded;
  try {
    decoded = jsonDecode(publication);
  } catch (_) {
    return publication;
  }
  if (decoded is! Map<String, dynamic>) return publication;
  final buf = StringBuffer();
  decoded.forEach((k, v) => buf.writeln('$k: $v'));
  return buf.toString().trimRight();
}

/// Preview, fingerprint question and deposit of one report (§16.7 "Before a
/// deposit the device asks"). Nothing is sent without the user's choice in
/// the preview; for a known crash fingerprint the user picks "+1" or "send
/// my report as a variant" — the device never decides this alone.
///
/// Returns the result of the send, or null when nothing was sent.
Future<SystemSendResult?> showSystemDepositFlow({
  required BuildContext context,
  required SystemChannelApi api,
  required SystemDraft draft,
  required String titleKey,
  required String introKey,
}) async {
  final locale = AppLocale.read(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final SystemDepositPreview preview;
  try {
    preview = await api.prepare(draft);
  } catch (e) {
    // No preview, no consent: an empty window would look like a result.
    debugPrint('System report preview unavailable: $e');
    messenger?.showSnackBar(
      SnackBar(content: Text(locale.get('sys_preview_unavailable'))),
    );
    return null;
  }
  if (!context.mounted) {
    await api.discard(preview.token);
    return null;
  }
  final refusal = preview.refusal;
  if (refusal != null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('crash_dialog_rate_title')),
        content: Text(systemRefusalText(locale, refusal)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(locale.get('crash_dialog_ok')),
          ),
        ],
      ),
    );
    await api.discard(preview.token);
    return SystemSendResult.refused(refusal);
  }
  final choice = await showDialog<SystemSendChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => SystemDepositPreviewDialog(
      preview: preview,
      title: locale.get(
        preview.existing != null ? 'sys_preview_known_title' : titleKey,
      ),
      intro: locale.get(
        preview.existing != null ? 'sys_preview_known_text' : introKey,
      ),
    ),
  );
  if (choice == null) {
    await api.discard(preview.token);
    return null;
  }
  final SystemSendResult result;
  try {
    result = await api.send(preview.token, choice);
  } catch (e) {
    debugPrint('System report send failed: $e');
    messenger?.showSnackBar(
      SnackBar(content: Text(locale.get('sys_action_failed'))),
    );
    return null;
  }
  final refused = result.refusal;
  if (refused != null) {
    messenger?.showSnackBar(
      SnackBar(content: Text(systemRefusalText(locale, refused))),
    );
  }
  return result;
}

/// The preview itself; pops a [SystemSendChoice] or null (cancel).
class SystemDepositPreviewDialog extends StatelessWidget {
  final SystemDepositPreview preview;
  final String title;
  final String intro;

  const SystemDepositPreviewDialog({
    super.key,
    required this.preview,
    required this.title,
    required this.intro,
  });

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final cs = Theme.of(context).colorScheme;
    final existing = preview.existing;
    final publication = systemPublicationText(preview.publication);

    Widget note(Key key, IconData icon, String text, {Color? color}) => Padding(
      key: key,
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? cs.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color ?? cs.outline),
            ),
          ),
        ],
      ),
    );

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            existing != null ? Icons.info_outline : Icons.outbox_outlined,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(intro),
              if (existing != null) ...[
                const SizedBox(height: 8),
                SystemChannelPost(
                  key: const ValueKey('sys_preview_existing'),
                  text: existing.text,
                  isOutgoing: false,
                  timestamp: MaterialLocalizations.of(
                    context,
                  ).formatShortDate(existing.created),
                ),
                if (preview.existingOthers > 0)
                  Text(
                    locale.tr('sys_others_saw', {
                      'count': '${preview.existingOthers}',
                    }),
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                locale.get('sys_preview_exact'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    publication,
                    key: const ValueKey('sys_preview_publication'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              note(
                const ValueKey('sys_preview_privacy'),
                Icons.shield_outlined,
                locale.get('sys_preview_privacy'),
              ),
              if (preview.statedUserIdHex != null)
                note(
                  const ValueKey('sys_preview_beta_userid'),
                  Icons.science_outlined,
                  locale.tr('sys_preview_beta_userid', {
                    'id': preview.statedUserIdHex!,
                  }),
                ),
              if (preview.holderIsContact)
                note(
                  const ValueKey('sys_preview_contact_holder'),
                  Icons.people_outline,
                  locale.get('sys_preview_contact_holder'),
                  color: cs.tertiary,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(locale.get('cancel')),
        ),
        IconButton(
          tooltip: locale.get('copy'),
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: preview.publication)),
        ),
        if (existing != null) ...[
          OutlinedButton(
            key: const ValueKey('sys_send_variant'),
            onPressed: () =>
                Navigator.of(context).pop(SystemSendChoice.variant),
            child: Text(locale.get('sys_preview_variant')),
          ),
          FilledButton(
            key: const ValueKey('sys_send_plus_one'),
            onPressed: () =>
                Navigator.of(context).pop(SystemSendChoice.plusOne),
            child: Text(locale.get('sys_preview_plus_one')),
          ),
        ] else
          FilledButton.icon(
            key: const ValueKey('sys_send_report'),
            onPressed: () => Navigator.of(context).pop(SystemSendChoice.report),
            icon: const Icon(Icons.upload_outlined, size: 16),
            label: Text(locale.get('crash_dialog_publish')),
          ),
      ],
    );
  }
}
