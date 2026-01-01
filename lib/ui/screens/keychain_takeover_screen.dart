import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// THE ONE-TIME TAKEOVER OF THE macOS KEYCHAIN ENTRIES (D-95).
///
/// Shown before anything reads the seed when the keychain holds an entry of
/// 4.2.3–4.2.6 that this build cannot read without the confirmation dialog
/// (their access list is empty). The button starts the takeover; the system
/// dialog of macOS then asks for the login password, once per entry. The
/// window stays usable meanwhile — the dialog is answered in a helper
/// isolate with a bound (`KeychainTakeover`), and a declined or unanswered
/// dialog leaves everything as it was and offers the takeover again.
/// Nothing is generated or overwritten on this screen.
class KeychainTakeoverScreen extends StatelessWidget {
  final VoidCallback? onStart;
  final bool running;
  final bool failedOnce;

  const KeychainTakeoverScreen({
    super.key,
    required this.onStart,
    required this.running,
    required this.failedOnce,
  });

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final theme = Theme.of(context);
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
                  Icon(Icons.key_outlined,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(locale.get('keychain_takeover_title'),
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(locale.get('keychain_takeover_body'),
                      style: theme.textTheme.bodyMedium),
                  if (failedOnce && !running) ...[
                    const SizedBox(height: 12),
                    Text(locale.get('keychain_takeover_retry'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  if (running)
                    Row(children: [
                      const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(locale.get('keychain_takeover_waiting'))),
                    ])
                  else
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton(
                        onPressed: onStart,
                        child: Text(locale.get('keychain_takeover_start')),
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
