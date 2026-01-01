import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// Persistent red banner shown at the top of the home shell when
/// [CleonaService.reducedMode] is active. Reuses the existing i18n key
/// `update_required_skip_limited` ("Open anyway (limited)" / "Trotzdem öffnen
/// (eingeschränkt)") — same semantic as the button on
/// [UpdateRequiredScreen] that put the user into this state (sec-h5 §8.2).
///
/// Tapping it does nothing intentionally — the user dismissed the splash
/// once and should keep seeing the warning until they update the app.
class ReducedModeBanner extends StatelessWidget {
  const ReducedModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    return Material(
      color: Colors.red.shade700,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  locale.get('update_required_skip_limited'),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
