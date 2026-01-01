import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/network/nfc_contact_exchange.dart';
import 'package:cleona/core/network/nfc_platform_bridge.dart';
import 'package:cleona/core/service/service_interface.dart';

/// NFC Contact Exchange Screen.
///
/// Flow:
///   1. Shows current identity name + "Hold phones together"
///   2. Waits for NFC tap
///   3. Shows received contact info + Confirm/Cancel
///   4. On confirm: creates contact with Verification Level 3
class NfcExchangeScreen extends StatefulWidget {
  final ICleonaService service;
  const NfcExchangeScreen({super.key, required this.service});

  @override
  State<NfcExchangeScreen> createState() => _NfcExchangeScreenState();
}

class _NfcExchangeScreenState extends State<NfcExchangeScreen> {
  NfcSessionManager? _session;
  NfcSessionState _state = NfcSessionState.idle;
  NfcContactPayload? _receivedPayload;
  String? _error;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  Future<void> _initSession() async {
    final service = widget.service;

    // Get active identity info (same as QR screen)
    final activeIdentity = IdentityManager().getActiveIdentity();
    final nodeIdHex = activeIdentity?.nodeIdHex ?? service.nodeIdHex;
    final displayName = activeIdentity?.displayName ?? service.displayName;

    // Get crypto keys from the service
    final ed25519Pk = service.ed25519PublicKey;
    final mlDsaPk = service.mlDsaPublicKey;
    final x25519Pk = service.x25519PublicKey;
    final mlKemPk = service.mlKemPublicKey;

    if (ed25519Pk == null || mlDsaPk == null || x25519Pk == null || mlKemPk == null) {
      setState(() {
        _state = NfcSessionState.failed;
        _error = 'Crypto-Schlüssel nicht verfügbar';
        _starting = false;
      });
      return;
    }

    // Build address list (same as QR screen) — incl. IPv6 global (§27)
    final ipv4Ips = service.localIps.where((ip) => !ip.contains(':')).take(2);
    final ipv6Ips = service.localIps.where((ip) => ip.contains(':') && !ip.toLowerCase().startsWith('fe80:')).take(1);
    final ownAddrs = [...ipv4Ips, ...ipv6Ips]
        .map((ip) => ip.contains(':') ? '[$ip]:${service.port}' : '$ip:${service.port}')
        .toList();
    if (service.publicIp != null && service.publicPort != null) {
      ownAddrs.add('${service.publicIp}:${service.publicPort}');
    }

    // Build seed peers — include allAddresses for IPv4+IPv6 bridging (§27)
    final validPeers = service.peerSummaries
        .where((p) => p.address.isNotEmpty && p.port > 0)
        .take(5)
        .toList();
    final seedPeers = validPeers
        .map((p) => NfcPeerEntry(
              nodeId: _hexToBytes(p.nodeIdHex),
              addresses: p.allAddresses.isNotEmpty
                  ? p.allAddresses.take(2).toList()
                  : [p.address.contains(':') ? '[${p.address}]:${p.port}' : '${p.address}:${p.port}'],
            ))
        .toList();

    // Create NfcContactExchange with real crypto
    final exchange = NfcContactExchange(
      ownNodeId: _hexToBytes(nodeIdHex),
      sign: (msg) => service.signEd25519(msg),
      verify: (msg, sig, pk) => service.verifyEd25519(msg, sig, pk),
    );

    _session = NfcSessionManager(
      exchange: exchange,
      onSessionUpdate: (state, payload, error) {
        if (!mounted) return;
        setState(() {
          _state = state;
          _receivedPayload = payload;
          _error = error;
        });
      },
    );

    final started = await _session!.startSession(
      displayName: displayName,
      ed25519PublicKey: ed25519Pk,
      mlDsaPublicKey: mlDsaPk,
      x25519PublicKey: x25519Pk,
      mlKemPublicKey: mlKemPk,
      profilePicture: service.profilePicture,
      description: service.profileDescription,
      addresses: ownAddrs,
      seedPeers: seedPeers,
    );

    setState(() {
      _starting = false;
      if (!started) {
        _state = NfcSessionState.failed;
        _error ??= 'NFC konnte nicht gestartet werden';
      }
    });
  }

  @override
  void dispose() {
    _session?.cancelSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeIdentity = IdentityManager().getActiveIdentity();
    final myName = activeIdentity?.displayName ?? widget.service.displayName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC Kontakttausch'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _session?.cancelSession();
            Navigator.pop(context);
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _buildContent(context, colorScheme, myName),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme, String myName) {
    if (_starting) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('NFC wird vorbereitet...'),
        ],
      );
    }

    switch (_state) {
      case NfcSessionState.idle:
      case NfcSessionState.waitingForTap:
        return _buildWaitingState(colorScheme, myName);

      case NfcSessionState.pendingConfirmation:
        return _buildConfirmationState(context, colorScheme);

      case NfcSessionState.completed:
        return _buildCompletedState(colorScheme);

      case NfcSessionState.failed:
        return _buildFailedState(colorScheme);
    }
  }

  Widget _buildWaitingState(ColorScheme colorScheme, String myName) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.nfc, size: 80, color: colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          'Kontakttausch als',
          style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          myName,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withAlpha(80),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(Icons.phonelink_ring, size: 48, color: colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'Halte dein Phone an das andere',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onPrimaryContainer,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Beide Phones müssen diese App geöffnet haben',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onPrimaryContainer.withAlpha(180),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          backgroundColor: colorScheme.surfaceContainerHighest,
          color: colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildConfirmationState(BuildContext context, ColorScheme colorScheme) {
    final payload = _receivedPayload!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.person_add, size: 64, color: colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Kontakt gefunden!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 24),
        // Contact card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  payload.displayName.isNotEmpty
                      ? payload.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      fontSize: 28, color: colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                payload.displayName,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600),
              ),
              if (payload.description != null &&
                  payload.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    payload.description!,
                    style: TextStyle(
                        fontSize: 14, color: colorScheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Verifiziert (NFC)',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Als Kontakt hinzufügen?',
          style: TextStyle(
              fontSize: 16, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () {
                _session?.cancelSession();
                Navigator.pop(context);
              },
              child: const Text('Ablehnen'),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Annehmen'),
              onPressed: () => _confirmContact(context),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmContact(BuildContext context) {
    final contact = _session?.confirmContact();
    if (contact == null) return;

    // Add contact to the service
    final service = widget.service;
    service.addNfcContact(contact);

    // Show success briefly, then pop
    setState(() => _state = NfcSessionState.completed);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context); // ignore: use_build_context_synchronously
    });
  }

  Widget _buildCompletedState(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 80, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          'Kontakt hinzugefügt!',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        if (_receivedPayload != null) ...[
          const SizedBox(height: 8),
          Text(
            _receivedPayload!.displayName,
            style: TextStyle(fontSize: 18, color: colorScheme.onSurface),
          ),
          Text(
            'Verifiziert (Level 3)',
            style: TextStyle(fontSize: 14, color: colorScheme.primary),
          ),
        ],
      ],
    );
  }

  Widget _buildFailedState(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 64, color: colorScheme.error),
        const SizedBox(height: 16),
        Text(
          'NFC-Austausch fehlgeschlagen',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colorScheme.error,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () {
            setState(() {
              _state = NfcSessionState.idle;
              _error = null;
              _starting = true;
            });
            _initSession();
          },
          child: const Text('Erneut versuchen'),
        ),
      ],
    );
  }
}

Uint8List _hexToBytes(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}
