import 'package:flutter/material.dart';

import 'package:cleona/core/channels/system_channel_api.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// Text of the state of an own report (§16.7: four states and no other).
String systemStateText(AppLocale locale, SystemReportStatus status) {
  switch (status.state) {
    case SystemReportState.saved:
      return locale.get('sys_state_saved');
    case SystemReportState.deposited:
      return locale.tr('sys_state_deposited', {
        'count': '${status.acknowledgements}',
      });
    case SystemReportState.published:
      return locale.get('sys_state_published');
    case SystemReportState.failed:
      return locale.tr('sys_state_failed', {
        'reason': systemFailureText(locale, status),
      });
  }
}

String systemFailureText(AppLocale locale, SystemReportStatus status) {
  switch (status.failure) {
    case SystemFailureReason.noHolderKnown:
      return locale.get('sys_fail_no_holder');
    case SystemFailureReason.notAcknowledged:
      return locale.get('sys_fail_not_acknowledged');
    case SystemFailureReason.rejected:
      return locale.tr('sys_fail_rejected', {'detail': status.detail ?? ''});
    case null:
      return '';
  }
}

String systemRefusalText(AppLocale locale, SystemRefusal refusal) {
  switch (refusal) {
    case SystemRefusal.perHour:
      return locale.get('sys_refusal_per_hour');
    case SystemRefusal.perDay:
      return locale.get('sys_refusal_per_day');
    case SystemRefusal.featurePerDay:
      return locale.get('sys_refusal_feature_per_day');
    case SystemRefusal.share:
      return locale.get('sys_refusal_share');
    case SystemRefusal.tooLarge:
      return locale.get('sys_refusal_too_large');
  }
}

/// Chip with the state of an own report.
class SystemReportStateChip extends StatelessWidget {
  final SystemReportStatus status;
  const SystemReportStateChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final cs = Theme.of(context).colorScheme;
    final state = status.state;
    final (IconData icon, Color color) = switch (state) {
      SystemReportState.saved => (Icons.save_outlined, cs.outline),
      SystemReportState.deposited => (Icons.cloud_upload_outlined, cs.primary),
      SystemReportState.published => (Icons.public, cs.primary),
      SystemReportState.failed => (Icons.error_outline, cs.error),
    };
    return Container(
      key: ValueKey('sys_state_${state.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              systemStateText(locale, status),
              style: TextStyle(fontSize: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "new" mark of §16.7.
class SystemNewBadge extends StatelessWidget {
  const SystemNewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('sys_new_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        AppLocale.read(context).get('sys_new'),
        style: TextStyle(fontSize: 10, color: cs.onPrimary),
      ),
    );
  }
}
