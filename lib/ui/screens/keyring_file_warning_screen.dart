import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// THE ONE-TIME WARNING FOR THE FILE VARIANT OF THE KEYRING (V18).
///
/// Where the system has a keyring, the keyring is binding. Where it has
/// none — or logs in automatically, leaving the collection LOCKED — the
/// master secret lies in the file-variant containers sealed under the
/// per-installation `.keyring_salt`, and whoever can read the disk can
/// open them. The owner decision demands the warning "at the 1st start of
/// the app, which attack is possible on his system due to the missing
/// keyring" — an active, unmistakable screen in the pattern of
/// [FirstStartWipeNoticeScreen], not a side note, because a silent
/// process would be a statement about the risk, and a false one.
///
/// Exactly two translated keys and the acknowledge button; the flag that
/// makes it "once" lives in the device database
/// (`keyring_file_warning.dart`). Shown only on the desktop platforms —
/// the text speaks of the disk and the machine.
class KeyringFileWarningScreen extends StatelessWidget {
  final VoidCallback onAcknowledge;

  const KeyringFileWarningScreen({
    super.key,
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
                  Icon(Icons.key_off_outlined, size: 56, color: cs.error),
                  const SizedBox(height: 16),
                  Text(locale.get('keyring_file_warning_title'),
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(locale.get('keyring_file_warning_body'),
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton(
                      onPressed: onAcknowledge,
                      child: Text(locale.get('keyring_file_warning_acknowledge')),
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