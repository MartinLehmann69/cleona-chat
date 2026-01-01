/// NAT-Troubleshooting-Wizard — Step 3: Instructions + Jetzt-pruefen (§27.9.2).
///
/// Renders resolved i18n steps + admin-URL hints (clickable via url_launcher),
/// plus a "Jetzt pruefen" action that calls the service-side recheck and
/// displays the result inline. Explicit close via "Fertig" — no auto-close.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/network/router_db.dart';

enum _CheckState { idle, running, success, fail }

class NatWizardInstructionsScreen extends StatefulWidget {
  final RouterDbEntry entry;
  final int currentPort;
  final String? localIp;
  final Future<bool> Function() onRecheck;

  const NatWizardInstructionsScreen({
    super.key,
    required this.entry,
    required this.currentPort,
    required this.localIp,
    required this.onRecheck,
  });

  @override
  State<NatWizardInstructionsScreen> createState() =>
      _NatWizardInstructionsScreenState();
}

class _NatWizardInstructionsScreenState
    extends State<NatWizardInstructionsScreen> {
  _CheckState _state = _CheckState.idle;

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silently ignore — user sees the URL anyway and can type it manually.
    }
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    final locale = AppLocale.read(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(locale.get('copied_to_clipboard')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _runRecheck() async {
    setState(() => _state = _CheckState.running);
    final ok = await widget.onRecheck();
    if (!mounted) return;
    setState(() => _state = ok ? _CheckState.success : _CheckState.fail);
  }

  /// Split multi-line i18n text into individual step lines, skipping blanks.
  List<String> _splitSteps(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  Widget _buildUrlHint(BuildContext context, String url) {
    final entry = widget.entry;
    final displayUrl =
        entry.deeplinkPath != null ? '$url${entry.deeplinkPath}' : url;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.open_in_new, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => _openUrl(displayUrl),
              child: Text(
                displayUrl,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: AppLocale.read(context).get('copy_to_clipboard'),
            icon: const Icon(Icons.copy, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => _copy(context, displayUrl),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context) {
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);

    switch (_state) {
      case _CheckState.idle:
        return const SizedBox.shrink();
      case _CheckState.running:
        return Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(locale.get('nat_wizard_check_running')),
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
            ),
          ),
        );
      case _CheckState.success:
        return Card(
          color: Colors.green.shade100,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locale.get('nat_wizard_check_success'),
                    style: TextStyle(color: Colors.green.shade900),
                  ),
                ),
              ],
            ),
          ),
        );
      case _CheckState.fail:
        return Card(
          color: Colors.red.shade100,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.error, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locale.get('nat_wizard_check_fail'),
                    style: TextStyle(color: Colors.red.shade900),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final theme = Theme.of(context);
    final entry = widget.entry;

    final stepsRaw = locale.get(entry.stepsI18nKey);
    final notesRaw = locale.get(entry.notesI18nKey);
    final steps = _splitSteps(stepsRaw);
    final hasNotes = notesRaw.isNotEmpty && notesRaw != entry.notesI18nKey;

    final port = widget.currentPort.toString();
    final ip = widget.localIp ?? '—';

    final isChecking = _state == _CheckState.running;

    return Scaffold(
      appBar: AppBar(title: Text(entry.displayName)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Copy-values reminder card (what the user has to enter).
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      locale.get('nat_wizard_values_hint'),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('${locale.get('nat_wizard_port_label')}: '),
                        SelectableText(
                          port,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 14),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _copy(context, port),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text('${locale.get('nat_wizard_local_ip_label')}: '),
                        Expanded(
                          child: SelectableText(
                            ip,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 14),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _copy(context, ip),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (entry.adminUrlHints.isNotEmpty) ...[
              Text(
                locale.get('nat_wizard_admin_url_hint'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              ...entry.adminUrlHints.map((u) => _buildUrlHint(context, u)),
              const SizedBox(height: 16),
            ],
            Text(
              locale.get('nat_wizard_steps_heading'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...List.generate(steps.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${i + 1}.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(child: Text(steps[i])),
                  ],
                ),
              );
            }),
            if (hasNotes) ...[
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        locale.get('nat_wizard_notes_heading'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notesRaw,
                        style: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _buildStatusBanner(context),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: isChecking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(locale.get('nat_wizard_check_now')),
              onPressed: isChecking ? null : _runRecheck,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: isChecking ? null : () => Navigator.of(context).pop(),
              child: Text(locale.get('nat_wizard_done')),
            ),
          ],
        ),
      ),
    );
  }
}
