import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Signed donation configuration.
/// The signature covers the address string signed by the maintainer key.
class DonationConfig {
  final String btcAddress;
  final String signature; // base64-encoded Ed25519 signature
  final int timestamp;    // Unix epoch seconds when signed

  const DonationConfig({
    required this.btcAddress,
    required this.signature,
    required this.timestamp,
  });
}

/// Signed IBAN donation configuration.
class IbanConfig {
  final String iban;
  final String bic;
  final String recipient;
  final String institute;
  final String signature; // base64-encoded Ed25519 signature over IBAN (no spaces)

  const IbanConfig({
    required this.iban,
    required this.bic,
    required this.recipient,
    required this.institute,
    required this.signature,
  });

  /// IBAN without spaces (for verification and QR).
  String get ibanCompact => iban.replaceAll(' ', '');
}

/// Current donation config — signed by maintainer private key.
/// To update: sign "$newAddress\n$timestamp" with cleona_maintainer_private.pem,
/// then update this constant.
const _donationConfig = DonationConfig(
  btcAddress: 'bc1qg85gzxrqd2ntkcs7dgqs2guw2kkn3sac5duwms',
  signature: '/sDIjSMCmIL/bhpL2O7FlnY6A+ZQv6gT1aFQF4HLFtoKRbNFKu4n3ZpOveW1jBCqPf6LUMHYkclqYuM7S24CBA==',
  timestamp: 1711641600, // 2025-03-28
);

/// IBAN config — signed by maintainer private key.
/// Signature covers the compact IBAN string (no spaces).
const _ibanConfig = IbanConfig(
  iban: 'DE05 5065 0023 0037 1449 53',
  bic: 'HELADEF1HAN',
  recipient: 'Martin Lehmann',
  institute: 'Sparkasse Hanau',
  signature: 'tF+pB2+kh0x7CBA/jkS73vVhb9u2KEs8cHHCBr5GO3TYGLldVj06gYOk8sEzaaE6GfAlJ/sqT4pQulYF69rhAQ==',
);

/// Raw 32-byte Ed25519 public key of the Cleona project maintainer (hex).
const _maintainerPublicKeyHex =
    '8a8589febfca4e0cecc21b036621861c4595192d56cfd1f5ec6573eece932daa';

class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  bool? _btcSignatureValid;
  bool? _ibanSignatureValid;

  @override
  void initState() {
    super.initState();
    _verifySignatures();
  }

  void _verifySignatures() {
    try {
      final sodium = SodiumFFI();
      final pubKeyBytes = _hexToBytes(_maintainerPublicKeyHex);

      // Verify BTC
      final btcSig = base64Decode(_donationConfig.signature);
      final btcMsg = utf8.encode(_donationConfig.btcAddress);
      final btcValid = sodium.verifyEd25519(
        Uint8List.fromList(btcMsg),
        Uint8List.fromList(btcSig),
        Uint8List.fromList(pubKeyBytes),
      );

      // Verify IBAN
      final ibanSig = base64Decode(_ibanConfig.signature);
      final ibanMsg = utf8.encode(_ibanConfig.ibanCompact);
      final ibanValid = sodium.verifyEd25519(
        Uint8List.fromList(ibanMsg),
        Uint8List.fromList(ibanSig),
        Uint8List.fromList(pubKeyBytes),
      );

      setState(() {
        _btcSignatureValid = btcValid;
        _ibanSignatureValid = ibanValid;
      });
    } catch (_) {
      setState(() {
        _btcSignatureValid = false;
        _ibanSignatureValid = false;
      });
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.get('donate_title')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header message
            Text(
              locale.get('donate_message'),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── IBAN / Bank Transfer ─────────────────────────────
            _SectionHeader(locale.get('donate_bank_transfer')),
            const SizedBox(height: 8),
            _VerificationBadge(valid: _ibanSignatureValid),
            const SizedBox(height: 12),

            // EPC QR Code (SEPA Credit Transfer)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: 'BCD\n002\n1\nSCT\n${_ibanConfig.bic}\n${_ibanConfig.recipient}\n${_ibanConfig.ibanCompact}\n\n\n\nCleona Spende',
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // IBAN details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CopyRow(label: 'IBAN', value: _ibanConfig.iban, locale: locale),
                  const SizedBox(height: 8),
                  _CopyRow(label: 'BIC', value: _ibanConfig.bic, locale: locale),
                  const SizedBox(height: 8),
                  _CopyRow(label: locale.get('donate_recipient'), value: _ibanConfig.recipient, locale: locale),
                  const SizedBox(height: 8),
                  _CopyRow(label: locale.get('donate_institute'), value: _ibanConfig.institute, locale: locale),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Bitcoin ──────────────────────────────────────────
            _SectionHeader(locale.get('donate_bitcoin')),
            const SizedBox(height: 8),
            _VerificationBadge(valid: _btcSignatureValid),
            const SizedBox(height: 12),

            // QR Code
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: 'bitcoin:${_donationConfig.btcAddress}',
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Address with copy button
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _donationConfig.btcAddress,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: locale.get('copy'),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _donationConfig.btcAddress),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(locale.get('copied_to_clipboard')),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Thank you note
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.favorite, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      locale.get('donate_thank_you'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  final bool? valid;
  const _VerificationBadge({required this.valid});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (valid == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final icon = valid! ? Icons.verified : Icons.warning_amber;
    final color = valid! ? Colors.green : colorScheme.error;
    final text = valid!
        ? locale.get('donate_verified')
        : locale.get('donate_not_verified');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final AppLocale locale;

  const _CopyRow({required this.label, required this.value, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value.replaceAll(' ', '')));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(locale.get('copied_to_clipboard')),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: const Icon(Icons.copy, size: 16),
        ),
      ],
    );
  }
}
