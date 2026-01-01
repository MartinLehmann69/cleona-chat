// B-4b (§13.0, §14.6.1, D-39, D-40): what a fresh install from the 24 words
// shows while its case is undecided. It searches only and collects no post;
// the banner says so, points to "Add another device" on the other device,
// and offers recovery — the recovery case begins only with that choice.
//
// D-102/D-103 (§13.0, §13.3.4, §13.6): while a recovery runs, the banner
// says how many restored contacts are back, that old devices can read along,
// and offers "finish and renew keys"; after a few days the opening of the
// app reminds once. It names identities this device removed because a
// recovery elsewhere retired them (dismissable, marked as read locally), and
// copies of the bundle whose chains fork. Without a window it says that a
// second device comes later and recovery moves the identity here.
//
// D-107 (§14.6.3): a device whose keys another own device changed, and which
// found no key package for it, says it was offline too long and must be
// enrolled again.

import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';

class EnrolmentBanner extends StatefulWidget {
  final ICleonaService service;
  const EnrolmentBanner({super.key, required this.service});

  /// §13.6 "a reminder after a few days at the opening of the app": asked
  /// once per run of the app, not at every rebuild. A test resets it.
  static bool reminderAsked = false;

  @override
  State<EnrolmentBanner> createState() => _EnrolmentBannerState();
}

class _EnrolmentBannerState extends State<EnrolmentBanner> {
  ICleonaService get service => widget.service;

  @override
  Widget build(BuildContext context) {
    final view = service.enrolmentView;
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);
    if (view.recoveryOpen &&
        view.recoveryReminder &&
        !EnrolmentBanner.reminderAsked) {
      EnrolmentBanner.reminderAsked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _remind(context, locale, view);
      });
    }
    final String? text;
    // S398, lab B-4b note H-2: the device notices the other device's window
    // and its approval only at its next edge — one of them is the user
    // opening the app (§8.2, never on a timer). The banner says so: no
    // clock, no traffic, a text only.
    String? reopenHint;
    String? movesHere;
    var offerRecovery = true;
    var offerFinish = false;
    switch (view.phase) {
      case EnrolmentPhase.searching:
        text = locale.get('enrol_searching');
        reopenHint = locale.get('enrol_reopen_hint_searching');
      case EnrolmentPhase.noWindow:
        final at = view.bundleAt;
        final days = at == null ? 0 : DateTime.now().difference(at).inDays;
        text = locale.tr('enrol_no_window', {'days': '$days'});
        // F-3 = A (D-103): enrolment is locked; recovery moves the identity.
        movesHere = locale.get('enrolment_moves_here');
      case EnrolmentPhase.waiting:
        text = locale.get('enrol_waiting');
        reopenHint = locale.get('enrol_reopen_hint_waiting');
        offerRecovery = false;
      case EnrolmentPhase.rejected:
        text = locale.get('enrol_rejected');
      case EnrolmentPhase.none:
      case EnrolmentPhase.recovering:
        offerRecovery = false;
        if (view.recoveryOpen) {
          text = locale.tr('recovery_running', {
            'back': '${view.recoveryBack}',
            'total': '${view.recoveryTotal}',
          });
          offerFinish = true;
        } else {
          text = null;
        }
    }
    // §13.7: the search for the other identities of the words runs on after
    // the first bundle is decided — never ended automatically.
    final run = view.identityRunOpen;
    final fork = view.forkSeenAt != null;
    final retired = view.retired;
    // §14.6.3 (D-107): the keys changed on another own device, and this one
    // found no key package for it — it says so plainly instead of running
    // on silently. Nothing was deleted.
    final tooLong = view.offlineTooLong;
    if (text == null && !run && !fork && retired.isEmpty && !tooLong) {
      return const SizedBox.shrink();
    }
    final onBanner = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSecondaryContainer);
    final small = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSecondaryContainer);
    final material = MaterialLocalizations.of(context);
    return Material(
      key: const Key('enrolment_banner'),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < retired.length; i++)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                        locale.tr('identity_retired', {
                          'name': retired[i].name,
                          'date': material.formatMediumDate(retired[i].at),
                        }),
                        key: Key('identity_retired_$i'),
                        style: onBanner),
                  ),
                  if (i == 0)
                    IconButton(
                      key: const Key('identity_retired_dismiss'),
                      icon: const Icon(Icons.close),
                      tooltip: material.closeButtonTooltip,
                      onPressed: () => service.enrolmentRetiredSeen(),
                    ),
                ],
              ),
            if (tooLong)
              Text(locale.get('device_offline_too_long'),
                  key: const Key('device_offline_too_long'), style: onBanner),
            if (fork)
              Text(locale.get('bundle_fork_seen'),
                  key: const Key('bundle_fork_seen'), style: onBanner),
            if (text != null)
              Text(text,
                  key: offerFinish ? const Key('recovery_running') : null,
                  style: onBanner),
            if (offerFinish) ...[
              const SizedBox(height: 4),
              Text(locale.get('recovery_read_along'),
                  key: const Key('recovery_read_along'), style: small),
            ],
            if (movesHere != null) ...[
              const SizedBox(height: 4),
              Text(movesHere,
                  key: const Key('enrolment_moves_here'), style: small),
            ],
            if (run) ...[
              if (text != null) const SizedBox(height: 6),
              Text(
                  locale.tr('identity_run_found',
                      {'count': '${view.identityRunFound}'}),
                  key: const Key('identity_run_found'),
                  style: onBanner),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    key: const Key('identity_run_name_index'),
                    onPressed: () => _nameIndex(context, locale),
                    child: Text(locale.get('identity_run_name_index')),
                  ),
                  TextButton(
                    key: const Key('identity_run_end'),
                    onPressed: () => service.identityRunEnd(),
                    child: Text(locale.get('identity_run_end')),
                  ),
                ],
              ),
            ],
            if (reopenHint != null) ...[
              const SizedBox(height: 4),
              Text(reopenHint,
                  key: const Key('enrol_reopen_hint'), style: small),
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
            if (offerFinish)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('recovery_finish'),
                  onPressed: () => service.enrolmentRecoveryFinish(),
                  child: Text(locale.get('recovery_finish')),
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(locale.get('enrol_recover_warning')),
              const SizedBox(height: 8),
              // F-3 = A (D-103): what recovery means while enrolment is locked.
              Text(locale.get('enrolment_moves_here'),
                  key: const Key('enrol_recover_moves_here')),
            ],
          ),
        ),
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

  /// §13.6: the reminder at the opening of the app, once per run.
  Future<void> _remind(
      BuildContext context, AppLocale locale, EnrolmentView view) async {
    final since = view.recoverySince;
    final days = since == null ? 0 : DateTime.now().difference(since).inDays;
    final finish = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('recovery_reminder_dialog'),
        content: Text(locale.tr('recovery_reminder', {
          'days': '$days',
          'back': '${view.recoveryBack}',
          'total': '${view.recoveryTotal}',
        })),
        actions: [
          TextButton(
              key: const Key('recovery_later'),
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(locale.get('recovery_later'))),
          FilledButton(
              key: const Key('recovery_reminder_finish'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(locale.get('recovery_finish'))),
        ],
      ),
    );
    if (finish == true) await service.enrolmentRecoveryFinish();
  }

  /// §13.7, §13.2.2: the user names the index of an identity they had.
  Future<void> _nameIndex(BuildContext context, AppLocale locale) async {
    final controller = TextEditingController();
    final index = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('identity_run_name_index')),
        content: TextField(
          key: const Key('identity_run_index_field'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              helperText: locale.get('identity_run_name_index_hint'),
              helperMaxLines: 3),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(locale.get('cancel'))),
          FilledButton(
              key: const Key('identity_run_index_confirm'),
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(controller.text.trim())),
              child: Text(locale.get('ok'))),
        ],
      ),
    );
    controller.dispose();
    if (index != null) await service.identityRunNameIndex(index);
  }
}
