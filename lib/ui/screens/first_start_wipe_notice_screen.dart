import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/platform/first_start_wipe.dart';

/// THE NOTICE FOR THE DELETION PATH (§21.4, owner decision 03.09.2026 / S363 A).
///
/// v4_1 §13.8 makes the notice about the limits of recovery
/// normative: "this limit must be communicated to the user actively and
/// unambiguously". The same applies by analogy to deleting the profile —
/// a silent process is a statement about the process, and a
/// false one. Therefore a blocking screen following the pattern of
/// [UpdateRequiredScreen] and not a side note.
///
/// Three translated keys, nothing else: heading, explanation,
/// button. The numbers (`WipeReport.technicalSummary`) stand untranslated
/// below — they are digits and units.
class FirstStartWipeNoticeScreen extends StatelessWidget {
  final WipeReport report;
  final VoidCallback onAcknowledge;

  const FirstStartWipeNoticeScreen({
    super.key,
    required this.report,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.delete_sweep_outlined, size: 56,
                      color: cs.error),
                  const SizedBox(height: 16),
                  Text(locale.get('first_start_wipe_title'),
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(locale.get('first_start_wipe_body'),
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  // Untranslated and without ornament: what was measured.
                  Text(report.technicalSummary,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                  const SizedBox(height: 24),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton(
                      onPressed: onAcknowledge,
                      child: Text(locale.get('first_start_wipe_continue')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
