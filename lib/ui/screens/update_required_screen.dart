import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/update/binary_update_manager.dart' show BinaryUpdateState;

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

  // `onStartInNetworkUpdate` stood here — the download click. Since S387
  // the app collects without user action (owner decision 14.09.2026, v4_2
  // §26.5.4: "While a hard-blocked node is still assembling,
  // `UpdateRequiredScreen` shows the assembly state instead of a button").

  /// Called when the update is ready and the user taps "Install" (Android)
  /// or "Restart" (desktop).
  final VoidCallback? onApplyUpdate;

  final BinaryUpdateState updateState;
  final double updateProgress;

  const UpdateRequiredScreen({
    super.key,
    required this.downloadUrl,
    required this.reasonI18nKey,
    required this.onSkipLimited,
    this.inNetworkAvailable = false,
    this.onApplyUpdate,
    this.updateState = BinaryUpdateState.idle,
    this.updateProgress = 0.0,
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
    final cs = Theme.of(context).colorScheme;
    final isActive = updateState != BinaryUpdateState.idle &&
        updateState != BinaryUpdateState.failed &&
        updateState != BinaryUpdateState.ready;

    return Scaffold(
      body: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update, size: 80, color: cs.primary),
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
                // Progress feedback during in-network download
                if (isActive) ...[
                  _buildProgressSection(locale, cs),
                  const SizedBox(height: 24),
                ] else if (updateState == BinaryUpdateState.ready) ...[
                  _buildReadySection(locale, cs),
                  const SizedBox(height: 24),
                ] else if (updateState == BinaryUpdateState.failed) ...[
                  _buildFailedSection(locale, cs),
                  const SizedBox(height: 24),
                ] else ...[
                  // Idle: the in-network update collects without a click (S387);
                  // only the external path remains (store/GitHub, §26.6.7
                  // steps 1-2) — a link, not a download of the update.
                  if (inNetworkAvailable)
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
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onSkipLimited,
                  child: Text(
                    locale.get('update_required_skip_limited'),
                    style: TextStyle(color: cs.outline),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection(AppLocale locale, ColorScheme cs) {
    final label = switch (updateState) {
      BinaryUpdateState.checking => locale.get('update_verifying'),
      BinaryUpdateState.downloading => locale.get('update_downloading'),
      BinaryUpdateState.assembling => locale.get('update_assembling'),
      BinaryUpdateState.verifying => locale.get('update_verifying'),
      _ => '',
    };
    return Column(children: [
      LinearProgressIndicator(value: updateProgress),
      const SizedBox(height: 8),
      Text('$label ${(updateProgress * 100).toInt()}%',
          style: TextStyle(color: cs.onSurface)),
    ]);
  }

  Widget _buildReadySection(AppLocale locale, ColorScheme cs) {
    final label = Platform.isAndroid
        ? locale.get('update_ready_install')
        : locale.get('update_ready_restart');
    return Column(children: [
      Icon(Icons.check_circle, size: 48, color: cs.primary),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: const Icon(Icons.install_mobile),
        label: Text(label),
        onPressed: onApplyUpdate,
      ),
    ]);
  }

  Widget _buildFailedSection(AppLocale locale, ColorScheme cs) {
    return Column(children: [
      Icon(Icons.error_outline, size: 48, color: cs.error),
      const SizedBox(height: 12),
      Text(locale.get('update_failed'),
          style: TextStyle(color: cs.error)),
      // No [Retry] any more: the next occasion (start,
      // network change, app opened, new neighbour) collects again by itself
      // (§26.6.1 "asks again at the next such moment").
    ]);
  }
}
