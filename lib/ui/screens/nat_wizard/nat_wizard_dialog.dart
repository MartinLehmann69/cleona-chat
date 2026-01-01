/// NAT-Troubleshooting-Wizard — Step 1: Diagnose (§27.9.2).
///
/// Plain-language explanation + copyable port/IP + QR code + 3 actions.
///
/// The QR code is Desktop-only: its use-case is letting a Desktop user
/// hand the local-IP:port pair to a phone that then opens the router's
/// admin UI. On the phone itself the QR is redundant (same device that
/// opened the dialog) AND causes the entire AlertDialog to render blank
/// on Android — the qr_flutter CustomPainter fails silently inside the
/// Material 3 modal overlay, leaving only the barrier dim / or nothing
/// depending on theme. Skipping the QR block on Android restores the
/// rest of the dialog (text + chips + actions) and keeps the Desktop
/// experience unchanged.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:cleona/core/i18n/app_locale.dart';

class NatWizardDialog extends StatelessWidget {
  final int currentPort;
  final String? localIp;
  final VoidCallback onShowInstructions;
  final VoidCallback onLater;
  final VoidCallback onNeverAgain;

  const NatWizardDialog({
    super.key,
    required this.currentPort,
    required this.localIp,
    required this.onShowInstructions,
    required this.onLater,
    required this.onNeverAgain,
  });

  String _qrPayload() {
    final ip = localIp ?? '0.0.0.0';
    return 'cleona-router-forward://$ip:$currentPort/UDP';
  }

  Future<void> _copy(BuildContext context, String value, String confirmKey) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    final locale = AppLocale.read(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(locale.get(confirmKey)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final locale = AppLocale.read(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: theme.textTheme.bodyMedium,
        ),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: locale.get('copy_to_clipboard'),
          icon: const Icon(Icons.copy, size: 18),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () => _copy(context, value, 'copied_to_clipboard'),
        ),
      ],
    );
  }

  /// True on platforms where `qr_flutter`'s CustomPainter is known to fail
  /// silently inside a Material 3 AlertDialog overlay. Android reliably
  /// reproduces the blank-dialog symptom; Desktop (Linux/macOS/Windows)
  /// renders fine.
  bool get _skipQrCode => !kIsWeb && Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final qrData = _qrPayload();
    final ipDisplay = localIp ?? '—';

    return AlertDialog(
      title: Text(locale.get('nat_wizard_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(locale.get('nat_wizard_diagnose_body')),
            const SizedBox(height: 16),
            _chip(
              context,
              label: locale.get('nat_wizard_port_label'),
              value: currentPort.toString(),
            ),
            const SizedBox(height: 8),
            _chip(
              context,
              label: locale.get('nat_wizard_local_ip_label'),
              value: ipDisplay,
            ),
            if (!_skipQrCode) ...[
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    errorCorrectionLevel: QrErrorCorrectLevel.L,
                    size: 140,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          onPressed: onNeverAgain,
          child: Text(locale.get('nat_wizard_never_again')),
        ),
        TextButton(
          onPressed: onLater,
          child: Text(locale.get('nat_wizard_later')),
        ),
        FilledButton(
          onPressed: onShowInstructions,
          child: Text(locale.get('nat_wizard_show_instructions')),
        ),
      ],
    );
  }
}
