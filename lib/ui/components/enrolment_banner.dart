// B-4b (§13.0, §14.6.1, D-39, D-40): what a fresh install from the 24 words
// shows while its case is undecided. It searches only and collects no post;
// the banner says so, points to "Add another device" on the other device,
// and offers recovery — the recovery case begins only with that choice.

import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';

class EnrolmentBanner extends StatelessWidget {
  final ICleonaService service;
  const EnrolmentBanner({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final view = service.enrolmentView;
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);
    final String text;
    // S398, lab B-4b note H-2: the device notices the other device's window
    // and its approval only at its next edge — one of them is the user
    // opening the app (§8.2, never on a timer). The banner says so: no
    // clock, no traffic, a text only.
    String? reopenHint;
    var offerRecovery = true;
    switch (view.phase) {
      case EnrolmentPhase.searching:
        text = locale.get('enrol_searching');
        reopenHint = locale.get('enrol_reopen_hint_searching');
      case EnrolmentPhase.noWindow:
        final at = view.bundleAt;
        final days = at == null ? 0 : DateTime.now().difference(at).inDays;
        text = locale.tr('enrol_no_window', {'days': '$days'});
      case EnrolmentPhase.waiting:
        text = locale.get('enrol_waiting');
        reopenHint = locale.get('enrol_reopen_hint_waiting');
        offerRecovery = false;
      case EnrolmentPhase.rejected:
        text = locale.get('enrol_rejected');
      case EnrolmentPhase.none:
      case EnrolmentPhase.recovering:
        return const SizedBox.shrink();
    }
    return Material(
      key: const Key('enrolment_banner'),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer)),
            if (reopenHint != null) ...[
              const SizedBox(height: 4),
              Text(reopenHint,
                  key: const Key('enrol_reopen_hint'),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer)),
            ],
            if (offerRecovery)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('enrol_recover_now'),
                  onPressed: () => _confirm(context, locale),
                  child: Text(locale.get('enrol_recover_now')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, AppLocale locale) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('enrol_recover_now')),
        content: Text(locale.get('enrol_recover_warning')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(locale.get('cancel'))),
          FilledButton(
              key: const Key('enrol_recover_confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(locale.get('enrol_recover_now'))),
        ],
      ),
    );
    if (ok == true) await service.enrolmentRecoverNow();
  }
}
