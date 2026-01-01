// V4.2 §14.4, §14.6.3, §24.4.5 (S422) — what the interface shows of the
// initial reconciliation of own devices and of a lock-out:
//
//   * [LockedOutNotice] — this device was locked out by the user's other
//     devices and removed every identity on itself ("the interface says why");
//   * [ReconcileRunningBar] — "reconciling state" while a fetch is open;
//   * [ReconcileOfferCard] — the full history offered with its size and way,
//     the attachments as one transfer, records that were too large;
//   * [showReconcileAttachmentsConsent] — the consent for this one transfer
//     (number of files and size, §24.4.5) before the attachments are asked.

import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// A size as the chat shows file sizes (B, KB, MB).
String reconcileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// §14.4: the notice on a locked-out device, with a dismiss button.
class LockedOutNotice extends StatelessWidget {
  final VoidCallback onDismiss;
  const LockedOutNotice({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(locale.get('device_locked_out_self'),
                key: const Key('device_locked_out_self')),
          ),
          IconButton(
            key: const Key('device_locked_out_self_dismiss'),
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// §14.6.3 "reconciling state": a bar above the conversation list.
class ReconcileRunningBar extends StatelessWidget {
  const ReconcileRunningBar({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('reconcile_running'),
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(locale.get('reconcile_running'),
              style: TextStyle(color: scheme.onSecondaryContainer)),
        ),
      ]),
    );
  }
}

/// §14.6.3: the offer for one conversation, as `reconcileView['offers']`
/// names it (`device`, `count`, `bytes`, `held`, `way`, `tooLarge`, `files`,
/// `fileBytes`, `filesHeld`, `filesWay`).
class ReconcileOfferCard extends StatelessWidget {
  final Map<String, dynamic> offer;
  final VoidCallback onFetchHistory;
  final VoidCallback onFetchAttachments;

  const ReconcileOfferCard({
    super.key,
    required this.offer,
    required this.onFetchHistory,
    required this.onFetchAttachments,
  });

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);
    final device = '${offer['device'] ?? ''}';
    final count = (offer['count'] as int?) ?? 0;
    final held = (offer['held'] as int?) ?? 0;
    final files = (offer['files'] as int?) ?? 0;
    final filesHeld = (offer['filesHeld'] as int?) ?? 0;
    final tooLarge = (offer['tooLarge'] as int?) ?? 0;
    final direct = offer['way'] == 'direct';
    final history = count > held;
    final attachments = files > filesHeld;
    return Card(
      key: const Key('reconcile_offer'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (history) ...[
              Text(
                locale.tr('reconcile_history_offer', {
                  'device': device,
                  'count': '$count',
                  'size': reconcileSize((offer['bytes'] as int?) ?? 0),
                }),
                key: const Key('reconcile_history_offer'),
              ),
              const SizedBox(height: 4),
              Text(
                locale.get(direct
                    ? 'reconcile_way_direct'
                    : 'reconcile_way_post_box'),
                key: const Key('reconcile_way'),
                style: theme.textTheme.bodySmall,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('reconcile_history_fetch'),
                  onPressed: onFetchHistory,
                  child: Text(locale.get('reconcile_history_fetch')),
                ),
              ),
            ],
            if (attachments) ...[
              Text(
                locale.tr('reconcile_attachments_offer', {
                  'count': '$files',
                  'size': reconcileSize((offer['fileBytes'] as int?) ?? 0),
                }),
                key: const Key('reconcile_attachments_offer'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('reconcile_attachments_fetch'),
                  onPressed: onFetchAttachments,
                  child: Text(locale.get('reconcile_attachments_fetch')),
                ),
              ),
            ],
            if (tooLarge > 0)
              Text(
                locale.tr('reconcile_too_large', {'count': '$tooLarge'}),
                key: const Key('reconcile_too_large'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

/// §24.4.5: the consent for this one transfer — `true` when the user agreed.
Future<bool> showReconcileAttachmentsConsent(
    BuildContext context, Map<String, dynamic> offer) async {
  final locale = AppLocale.read(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('reconcile_attachments_consent'),
      content: Text(locale.tr('reconcile_attachments_consent', {
        'count': '${offer['files'] ?? 0}',
        'size': reconcileSize((offer['fileBytes'] as int?) ?? 0),
        'device': '${offer['device'] ?? ''}',
      })),
      actions: [
        TextButton(
          key: const Key('reconcile_attachments_consent_no'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(locale.get('cancel')),
        ),
        FilledButton(
          key: const Key('reconcile_attachments_consent_yes'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(locale.get('reconcile_attachments_fetch')),
        ),
      ],
    ),
  );
  return ok == true;
}
