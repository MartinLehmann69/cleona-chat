import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/network/contact_seed.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/service/service_interface.dart';

/// Screen showing own QR code for contact sharing.
class QrShowScreen extends StatelessWidget {
  final ICleonaService service;
  const QrShowScreen({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);

    // Use GUI-selected identity, not daemon IPC state.
    // When Alice-Tab is visible but daemon internally has AllyCat active,
    // the QR must show Alice's nodeId (IdentityManager tracks GUI selection).
    final activeIdentity = IdentityManager().getActiveIdentity();
    final qrNodeIdHex = activeIdentity?.nodeIdHex ?? service.nodeIdHex;
    final qrDisplayName = activeIdentity?.displayName ?? service.displayName;

    // Build ContactSeed URI: own private + public addresses,
    // confirmed peers from various subnets.
    // Deduplicate by address:port (same NAT endpoint = same routing value).
    final validPeers = service.peerSummaries
        .where((p) => p.address.isNotEmpty && p.port > 0)
        .toList();
    final peers = <dynamic>[];
    final seenEndpoints = <String>{};
    // LAN peers from different /16 subnets (max 2)
    for (final p in validPeers.where((p) => _isPrivateIp(p.address))) {
      final endpoint = '${p.address}:${p.port}';
      if (!seenEndpoints.add(endpoint)) continue;
      peers.add(p);
      if (peers.length >= 2) break;
    }
    // Public peers with unique endpoints (max 4 total, Architecture §6.1)
    for (final p in validPeers.where((p) => !_isPrivateIp(p.address))) {
      final endpoint = '${p.address}:${p.port}';
      if (!seenEndpoints.add(endpoint)) continue;
      peers.add(p);
      if (peers.length >= 4) break;
    }
    // Own addresses: up to 2 private + public IP (if confirmed)
    final ownAddrs = service.localIps.take(2).map((ip) => '$ip:${service.port}').toList();
    if (service.publicIp != null && service.publicPort != null) {
      ownAddrs.add('${service.publicIp}:${service.publicPort}');
    }
    final seed = ContactSeed(
      nodeIdHex: qrNodeIdHex,
      displayName: qrDisplayName,
      ownAddresses: ownAddrs,
      // 1 address per peer for QR (keeps URI scannable, ~500 chars for 4 peers)
      seedPeers: peers.map((p) => SeedPeer(
        nodeIdHex: p.nodeIdHex,
        addresses: ['${p.address}:${p.port}'],
      )).toList(),
      channelTag: NetworkSecret.channel == NetworkChannel.beta ? 'b' : 'l',
    );
    final uri = seed.toUri();

    return Scaffold(
      appBar: AppBar(title: Text(locale.get('qr_my_code'))),
      body: SafeArea(top: false, child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                qrDisplayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                locale.get('qr_show_instruction'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: uri,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  size: 280,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Node-ID: ${qrNodeIdHex.substring(0, 16)}...',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: Text(locale.get('copy')),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: uri));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(locale.get('copied_to_clipboard'))),
                  );
                },
              ),
            ],
          ),
        ),
      )),
    );
  }
}

/// Screen for scanning a QR code to add a contact.
class QrScanScreen extends StatefulWidget {
  final ICleonaService service;
  const QrScanScreen({super.key, required this.service});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  ContactSeed? _scannedSeed;
  bool _processing = false;
  String? _error;
  final _manualController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);

    return Scaffold(
      appBar: AppBar(title: Text(locale.get('qr_scan_title'))),
      body: SafeArea(top: false, child: _scannedSeed != null
          ? _buildResult(context, locale)
          : (Platform.isAndroid || Platform.isIOS)
              ? _buildCameraScanner(context, locale)
              : _buildManualInput(context, locale)),
    );
  }

  Widget _buildCameraScanner(BuildContext context, AppLocale locale) {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              if (_scannedSeed != null) return; // Already scanned
              for (final barcode in capture.barcodes) {
                final data = barcode.rawValue;
                if (data == null) continue;
                debugPrint('[QR-SCAN] Raw data (${data.length} chars): $data');
                final seed = ContactSeed.fromUri(data);
                if (seed != null) {
                  debugPrint('[QR-SCAN] Parsed: target=${seed.nodeIdHex.substring(0, 8)}, '
                      'ownAddrs=${seed.ownAddresses.length}, seedPeers=${seed.seedPeers.length}');
                  for (final sp in seed.seedPeers) {
                    debugPrint('[QR-SCAN]   Seed: ${sp.nodeIdHex.substring(0, 8)} @ ${sp.addresses}');
                  }
                }
                if (seed != null && mounted) {
                  setState(() => _scannedSeed = seed);
                  return;
                }
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(locale.get('qr_scan_instruction'), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => _ManualInputScreen(
                    onParsed: (seed) {
                      setState(() => _scannedSeed = seed);
                      Navigator.pop(context);
                    },
                  )),
                ),
                child: Text(locale.get('qr_manual_input')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManualInput(BuildContext context, AppLocale locale) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(locale.get('qr_manual_input'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _manualController,
            decoration: InputDecoration(
              labelText: 'cleona://... oder Node-ID',
              border: const OutlineInputBorder(),
              hintText: locale.get('qr_paste_uri'),
            ),
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final input = _manualController.text.trim();
              // Try as ContactSeed URI
              var seed = ContactSeed.fromUri(input);
              // Try as plain Node-ID hex
              if (seed == null && input.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(input)) {
                seed = ContactSeed(nodeIdHex: input, displayName: '');
              }
              if (seed != null) {
                setState(() { _scannedSeed = seed; _error = null; });
              } else {
                setState(() => _error = locale.get('qr_invalid'));
              }
            },
            child: Text(locale.get('qr_connect')),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context, AppLocale locale) {
    final seed = _scannedSeed!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              seed.displayName.isNotEmpty ? seed.displayName : locale.get('qr_unknown_contact'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Node-ID: ${seed.nodeIdHex.substring(0, 16)}...',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            if (seed.seedPeers.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${seed.seedPeers.length} Seed-Peers'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _processing ? null : () => _sendContactRequest(seed),
              icon: _processing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.person_add),
              label: Text(_processing ? '...' : locale.get('qr_add_contact')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() { _scannedSeed = null; _error = null; }),
              child: Text(locale.get('qr_scan_again')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendContactRequest(ContactSeed seed) async {
    final locale = AppLocale.read(context);

    // Channel mismatch check — applies to QR, NFC, URI paste, manual input
    final localTag = NetworkSecret.channel == NetworkChannel.beta ? 'b' : 'l';
    if (!seed.isChannelCompatible(localTag)) {
      final localName = NetworkSecret.channel == NetworkChannel.beta ? 'Beta' : 'Live';
      setState(() {
        _processing = false;
        _error = locale.tr('channel_mismatch', {
          'contact': seed.channelDisplayName,
          'local': localName,
        });
      });
      return;
    }

    setState(() { _processing = true; _error = null; });

    try {
      // Register target + seed peers in routing table, then wait for PONGs
      // so relay candidates are confirmed before sending the CR.
      widget.service.addPeersFromContactSeed(
        seed.nodeIdHex,
        seed.ownAddresses,
        seed.seedPeers.map((p) => (nodeIdHex: p.nodeIdHex, addresses: p.addresses)).toList(),
      );
      await Future.delayed(const Duration(seconds: 3));

      final success = await widget.service.sendContactRequest(seed.nodeIdHex);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locale.get('contact_request_sent'))),
          );
          Navigator.of(context).pop();
        } else {
          setState(() { _processing = false; _error = locale.get('qr_send_failed'); });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() { _processing = false; _error = locale.tr('error_generic', {'error': '$e'}); });
      }
    }
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }
}

bool _isPrivateIp(String ip) {
  if (ip.contains(':')) {
    final lower = ip.toLowerCase();
    return lower.startsWith('fe80:') || lower.startsWith('fc') ||
           lower.startsWith('fd') || lower == '::1';
  }
  return ip.startsWith('10.') ||
      ip.startsWith('192.168.') ||
      ip.startsWith('172.16.') || ip.startsWith('172.17.') ||
      ip.startsWith('172.18.') || ip.startsWith('172.19.') ||
      ip.startsWith('172.2') || ip.startsWith('172.3') ||
      ip.startsWith('192.0.0.') ||
      (ip.startsWith('100.') && (int.tryParse(ip.split('.')[1]) ?? 0) >= 64 &&
          (int.tryParse(ip.split('.')[1]) ?? 0) <= 127);
}

/// Manual URI input screen (fallback when camera scanner is open).
class _ManualInputScreen extends StatefulWidget {
  final void Function(ContactSeed) onParsed;
  const _ManualInputScreen({required this.onParsed});

  @override
  State<_ManualInputScreen> createState() => _ManualInputScreenState();
}

class _ManualInputScreenState extends State<_ManualInputScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    return Scaffold(
      appBar: AppBar(title: Text(locale.get('qr_manual_input'))),
      body: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'cleona://...',
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final seed = ContactSeed.fromUri(_controller.text.trim());
                if (seed != null) {
                  widget.onParsed(seed);
                } else {
                  setState(() => _error = locale.get('qr_invalid'));
                }
              },
              child: Text(locale.get('qr_connect')),
            ),
          ],
        ),
      )),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
