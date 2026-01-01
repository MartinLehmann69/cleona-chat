import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// Hard-block splash shown when `appVersion < manifest.minRequiredVersion`.
/// User can either update or skip into Reduced-Mode.
class UpdateRequiredScreen extends StatelessWidget {
  final String downloadUrl;
  final String reasonI18nKey;
  final VoidCallback onSkipLimited;

  /// §19.6: true when this platform's update was confirmed reachable via
  /// in-network binary distribution (peer-fetched fragments), not just the
  /// external `downloadUrl`. Set once [CleonaService.onUpdateAvailable]
  /// fires with the result of [BinaryUpdateManager.checkForUpdate].
  final bool inNetworkAvailable;

  /// Called when the user picks the in-network update path instead of the
  /// external download link. Only invoked when [inNetworkAvailable] is true.
  final VoidCallback? onStartInNetworkUpdate;

  const UpdateRequiredScreen({
    super.key,
    required this.downloadUrl,
    required this.reasonI18nKey,
    required this.onSkipLimited,
    this.inNetworkAvailable = false,
    this.onStartInNetworkUpdate,
  });

  Future<void> _openDownload(BuildContext context) async {
    final uri = Uri.parse(downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: $downloadUrl')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    return Scaffold(
      body: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update, size: 80, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  locale.get('update_required_title'),
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  locale.get(reasonI18nKey),
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (inNetworkAvailable && onStartInNetworkUpdate != null) ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.cloud_download),
                    label: Text(locale.get('updateInNetworkButton')),
                    onPressed: onStartInNetworkUpdate,
                  ),
                  const SizedBox(height: 12),
                ],
                if (inNetworkAvailable && onStartInNetworkUpdate != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text(locale.get('update_required_download')),
                    onPressed: () => _openDownload(context),
                  )
                else
                  FilledButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text(locale.get('update_required_download')),
                    onPressed: () => _openDownload(context),
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onSkipLimited,
                  child: Text(
                    locale.get('update_required_skip_limited'),
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
