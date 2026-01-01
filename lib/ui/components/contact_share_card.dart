import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart' as qr_lib;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/share_cleona_dialog.dart';

/// Unified QR-code + copy + share widget used by both
/// [IdentityDetailScreen] and [QrShowScreen] to avoid divergent
/// implementations (ContactSeed parameters, loading UI, share options).
class ContactShareCard extends StatefulWidget {
  final ICleonaService service;

  /// If non-null, use this identity's nodeIdHex/displayName.
  /// If null, falls back to the active identity or the service default.
  final Identity? identity;

  /// Whether to show the "Share Cleona" button below the QR code.
  final bool showShareCleonaButton;

  const ContactShareCard({
    super.key,
    required this.service,
    this.identity,
    this.showShareCleonaButton = true,
  });

  @override
  State<ContactShareCard> createState() => _ContactShareCardState();
}

class _ContactShareCardState extends State<ContactShareCard> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.service.contactSeedBuilder.isReady) {
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (widget.service.contactSeedBuilder.isReady) {
          _pollTimer?.cancel();
          _pollTimer = null;
        }
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final locale = AppLocale.read(context);

    final id = widget.identity ?? IdentityManager().getActiveIdentity();
    final nodeIdHex = id?.nodeIdHex ?? service.nodeIdHex;
    final displayName = id?.displayName ?? service.displayName;
    final channelTag = NetworkSecret.channel == NetworkChannel.beta ? 'b' : 'l';

    final seed = service.contactSeedBuilder.getContactSeedFor(
      nodeIdHex: nodeIdHex,
      displayName: displayName,
      channelTag: channelTag,
      userEd25519Pk: service.userEd25519Pk,
      foundingEd25519Pk: service.foundingEd25519Pk,
      deviceX25519Pk: service.deviceX25519Pk,
      deviceMlKemPk: service.deviceMlKemPk,
    );

    if (seed == null) {
      return _buildLoadingState(context, service, locale);
    }

    final qrBytes = seed.toQrBytes();
    final shareUri = seed.toUri();
    final qrCode = qr_lib.QrCode.fromUint8List(
      data: qrBytes,
      errorCorrectLevel: qr_lib.QrErrorCorrectLevel.L,
    );

    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = (screenWidth * 0.55).clamp(180.0, 400.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            displayName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            locale.get('qr_show_instruction'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView.withQr(
              qr: qrCode,
              size: qrSize,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SelectableText(
                'Node-ID: ${nodeIdHex.substring(0, 16)}...',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: locale.get('copy'),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: shareUri));
                  final rn = seed.rendezvousNonce;
                  if (rn != null) {
                    service.notifyContactSeedUriShared(
                        base64Url.encode(rn).replaceAll('=', ''));
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(locale.get('copied_to_clipboard'))),
                  );
                },
              ),
            ],
          ),
          if (widget.showShareCleonaButton) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: Text(locale.get('share_cleona')),
                    onPressed: () => ShareCleonaDialog.show(context, service),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingState(
      BuildContext context, ICleonaService service, AppLocale locale) {
    final elapsed = service.nodeStartedAt != null
        ? DateTime.now().difference(service.nodeStartedAt!).inSeconds
        : 0;
    final progress = (elapsed / 15).clamp(0.0, 0.95);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Column(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 6,
            ),
          ),
          const SizedBox(height: 24),
          Text('${(progress * 100).toInt()}%',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(locale.get('qr_mesh_converging'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
