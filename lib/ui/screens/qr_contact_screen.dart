import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart' as qr_lib;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/network/contact_seed.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/service/service_interface.dart';

/// Screen showing own QR code for contact sharing.
/// Implements a convergence gate (§8.1.1): shows a progress indicator until
/// at least one peer is session-confirmed (fresh direct packet in this
/// daemon session), then displays the QR code with reliable seed peers.
class QrShowScreen extends StatefulWidget {
  final ICleonaService service;
  const QrShowScreen({super.key, required this.service});

  @override
  State<QrShowScreen> createState() => _QrShowScreenState();
}

class _QrShowScreenState extends State<QrShowScreen> {
  Timer? _pollTimer;
  static const _typicalConvergenceSeconds = 15;

  @override
  void initState() {
    super.initState();
    if (!widget.service.hasSessionConfirmedPeers) {
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (widget.service.hasSessionConfirmedPeers) {
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

    if (!service.hasSessionConfirmedPeers) {
      final elapsed = service.nodeStartedAt != null
          ? DateTime.now().difference(service.nodeStartedAt!).inSeconds
          : 0;
      final progress = (elapsed / _typicalConvergenceSeconds).clamp(0.0, 0.95);
      return Scaffold(
        appBar: AppBar(title: Text(locale.get('qr_my_code'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 120, height: 120,
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
          ),
        ),
      );
    }

    // Use GUI-selected identity, not daemon IPC state.
    // When identity A's tab is visible but daemon internally has identity B
    // active, the QR must show A's nodeId (IdentityManager tracks GUI selection).
    final activeIdentity = IdentityManager().getActiveIdentity();
    final qrNodeIdHex = activeIdentity?.nodeIdHex ?? service.nodeIdHex;
    final qrDisplayName = activeIdentity?.displayName ?? service.displayName;

    // Build ContactSeed URI: own private + public addresses,
    // confirmed peers from various subnets.
    // §8.1.1 seed-peer selection: at least 1 relay-capable peer (has public
    // IP = reachable from any network), rest by freshness/diversity.
    final freshCutoff = DateTime.now().subtract(const Duration(minutes: 30));
    final validPeers = service.peerSummaries
        .where((p) => p.address.isNotEmpty && p.port > 0 && p.lastSeen.isAfter(freshCutoff))
        .toList();
    final peers = <dynamic>[];
    final seenNodeIds = <String>{};
    // Slot 1: guaranteed relay-capable peer (has public IP in allAddresses).
    // This ensures scanners on different networks can reach at least one peer.
    for (final p in validPeers) {
      final hasPublic = p.allAddresses.any((a) {
        final ip = a.contains('[') ? a.substring(1, a.indexOf(']')) : a.split(':').first;
        return !_isPrivateIp(ip) && !ip.contains(':');
      });
      if (hasPublic && seenNodeIds.add(p.nodeIdHex)) {
        peers.add(p);
        break;
      }
    }
    // Remaining slots: LAN peers (max 2) + public peers (up to 5 total)
    for (final p in validPeers.where((p) => _isPrivateIp(p.address))) {
      if (!seenNodeIds.add(p.nodeIdHex)) continue;
      peers.add(p);
      if (peers.length >= 3) break;
    }
    for (final p in validPeers.where((p) => !_isPrivateIp(p.address))) {
      if (!seenNodeIds.add(p.nodeIdHex)) continue;
      peers.add(p);
      if (peers.length >= 5) break;
    }
    // Own addresses: up to 2 private + public IP (if confirmed)
    final ownAddrs = service.localIps.take(2).map((ip) => '$ip:${service.port}').toList();
    if (service.publicIp != null && service.publicPort != null) {
      ownAddrs.add('${service.publicIp}:${service.publicPort}');
    }
    final seedPeerList = peers.map((p) {
      // Sort addresses: public IPv4 first (reachable from mobile/CGNAT),
      // then private IPv4 (LAN), then IPv6.
      final sorted = List<String>.from(p.allAddresses);
      sorted.sort((a, b) {
        final aScore = _addressPriority(a);
        final bScore = _addressPriority(b);
        return aScore.compareTo(bScore);
      });
      return SeedPeer(
        nodeIdHex: p.nodeIdHex,
        addresses: sorted.isNotEmpty
            ? sorted.take(3).toList()
            : ['${p.address}:${p.port}'],
      );
    }).toList();

    // §8.1.1 rev3: QR carries userEd25519Pk (32B trust-anchor) instead of
    // dxk+dmk (1216B). Device-KEM keys resolved via DHT or Deferred KE.
    final seed = ContactSeed(
      nodeIdHex: qrNodeIdHex,
      displayName: qrDisplayName,
      ownAddresses: ownAddrs,
      seedPeers: seedPeerList,
      channelTag: NetworkSecret.channel == NetworkChannel.beta ? 'b' : 'l',
      deviceIdHex: service.deviceNodeIdHex,
      userEd25519Pk: service.userEd25519Pk,
    );
    final qrBytes = seed.toQrBytes();
    final qrCode = qr_lib.QrCode.fromUint8List(
      data: qrBytes,
      errorCorrectLevel: qr_lib.QrErrorCorrectLevel.L,
    );
    final shareUri = seed.toUri();

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
                child: QrImageView.withQr(
                  qr: qrCode,
                  size: 400,
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
                  Clipboard.setData(ClipboardData(text: shareUri));
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
              if (_scannedSeed != null) return;
              for (final barcode in capture.barcodes) {
                ContactSeed? seed;

                // Binary format (compact QR with KEM keys)
                final rawBytes = barcode.rawBytes;
                if (rawBytes != null && rawBytes.isNotEmpty) {
                  seed = ContactSeed.fromQrBytes(Uint8List.fromList(rawBytes));
                  if (seed != null) {
                    debugPrint('[QR-SCAN] Binary format: ${rawBytes.length} bytes, '
                        'target=${seed.nodeIdHex.substring(0, 8)}, '
                        'did=${seed.deviceIdHex?.substring(0, 8) ?? "<legacy>"}, '
                        'dxk=${seed.deviceX25519Pk != null}, dmk=${seed.deviceMlKemPk != null}');
                  }
                }

                // Fallback: legacy URI format
                if (seed == null) {
                  final data = barcode.rawValue;
                  if (data != null) {
                    seed = ContactSeed.fromUri(data);
                    if (seed != null) {
                      debugPrint('[QR-SCAN] URI format: target=${seed.nodeIdHex.substring(0, 8)}');
                    }
                  }
                }

                if (seed != null) {
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
      // §8.1.1 rev3: v2 seeds carry ep (userEd25519Pk) instead of dxk/dmk.
      // v1 legacy seeds with dxk/dmk still work (passed through).
      final dxk = seed.deviceX25519Pk;
      final dmk = seed.deviceMlKemPk;
      final dxkB64 = dxk != null ? base64.encode(dxk) : null;
      final dmkB64 = dmk != null ? base64.encode(dmk) : null;
      final ep = seed.userEd25519Pk;
      final epB64 = ep != null ? base64Url.encode(ep).replaceAll('=', '') : null;
      widget.service.addPeersFromContactSeed(
        seed.nodeIdHex,
        seed.ownAddresses,
        seed.seedPeers.map((p) => (nodeIdHex: p.nodeIdHex, addresses: p.addresses)).toList(),
        targetDeviceIdHex: seed.deviceIdHex,
        targetDxkB64: dxkB64,
        targetDmkB64: dmkB64,
        targetEpB64: epB64,
      );
      await Future.delayed(const Duration(seconds: 3));
      final success = await widget.service.sendContactRequest(
        seed.nodeIdHex,
        seedDeviceIdHex: seed.deviceIdHex,
        seedDxkB64: dxkB64,
        seedDmkB64: dmkB64,
        seedEpB64: epB64,
      );
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
  if (ip.startsWith('10.')) return true;
  if (ip.startsWith('192.168.')) return true;
  if (ip.startsWith('172.')) {
    final second = int.tryParse(ip.split('.')[1]);
    if (second != null && second >= 16 && second <= 31) return true;
  }
  if (ip.startsWith('192.0.0.')) return true;
  if (ip.startsWith('100.')) {
    final second = int.tryParse(ip.split('.')[1]) ?? 0;
    if (second >= 64 && second <= 127) return true;
  }
  if (ip.startsWith('127.')) return true;
  return false;
}

/// Address priority for QR seed peers: lower = higher priority.
/// Public IPv4 and global IPv6 first (reachable from CGNAT/mobile),
/// then private/link-local.
int _addressPriority(String addrPort) {
  final addr = addrPort.startsWith('[')
      ? addrPort.substring(1, addrPort.indexOf(']'))
      : addrPort.split(':').first;
  if (addr.contains(':')) {
    final lower = addr.toLowerCase();
    if (lower.startsWith('fe80:') || lower.startsWith('fc') ||
        lower.startsWith('fd') || lower == '::1') {
      return 2; // Link-local/private IPv6
    }
    return 0; // Global IPv6 (same priority as public IPv4)
  }
  if (_isPrivateIp(addr)) return 2; // Private IPv4
  return 0; // Public IPv4
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
