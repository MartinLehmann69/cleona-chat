// lib/ui/components/connection_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';

/// Connection sheet — §18 / §12.3.1 / §8.1.2
///
/// Opened when the user taps "Active Peers" (NetworkStatsScreen) or
/// "Connected Peers" (SettingsScreen → Network section).
///
/// Content:
///   1. Live list of active peers
///   2. Debounced Reconnect button (Feature ②)
///   3. Peer Rescue Bundle import/export section (Feature ③)
///   4. Manual Peer Entry (co-located with bundle import)
///
/// Must be wrapped in SafeArea(top: false) to respect Android edge-to-edge.
void showConnectionSheet(BuildContext context, ICleonaService service) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _ConnectionSheet(service: service),
  );
}

class _ConnectionSheet extends StatefulWidget {
  final ICleonaService service;
  const _ConnectionSheet({required this.service});

  @override
  State<_ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<_ConnectionSheet> {
  // Reconnect state
  bool _reconnecting = false;
  String? _reconnectResult; // displayed after reconnect finishes

  // Import state
  final _importController = TextEditingController();
  bool _importing = false;
  String? _importResult;

  // Manual peer state
  final _ipController = TextEditingController();
  final _portController = TextEditingController();

  // Peer list — refreshed on open, after reconnect, and reactively on
  // every service state change (S119 B: no polling timer; the sheet chains
  // into onStateChanged, which node.onPeersChanged already drives).
  List<PeerSummary> _peers = [];
  void Function()? _prevOnStateChanged;

  @override
  void initState() {
    super.initState();
    _peers = widget.service.peerSummaries;
    _prevOnStateChanged = widget.service.onStateChanged;
    widget.service.onStateChanged = () {
      _prevOnStateChanged?.call();
      if (mounted) {
        setState(() => _peers = widget.service.peerSummaries);
      }
    };
  }

  @override
  void dispose() {
    widget.service.onStateChanged = _prevOnStateChanged;
    _importController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // ── Reconnect (Feature ②) ────────────────────────────────────────────────

  Future<void> _onReconnect() async {
    if (_reconnecting) return;
    setState(() {
      _reconnecting = true;
      _reconnectResult = null;
    });
    final locale = AppLocale.read(context);
    try {
      final svc = widget.service;
      Map<String, dynamic> result;
      if (svc is IpcClient) {
        result = await svc.manualReconnect();
      } else {
        // In-process fallback (headless / direct service)
        await svc.onNetworkChanged();
        result = {'debounced': false, 'peersFound': svc.peerCount};
      }

      if (!mounted) return;

      final debounced = result['debounced'] as bool? ?? false;
      final remaining = result['remainingSeconds'] as int? ?? 0;
      final found = result['peersFound'] as int? ?? 0;

      if (debounced) {
        final msg = locale.get('connection_sheet_reconnect_debounced')
            .replaceAll('{s}', '$remaining');
        setState(() => _reconnectResult = msg);
      } else if (found > 0) {
        final msg = locale.get('connection_sheet_reconnect_success')
            .replaceAll('{n}', '$found');
        setState(() {
          _reconnectResult = msg;
          _peers = svc.peerSummaries;
        });
      } else {
        setState(() => _reconnectResult = locale.get('connection_sheet_reconnect_none'));
      }
    } catch (e) {
      if (mounted) setState(() => _reconnectResult = '$e');
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  // ── Bundle Export (Feature ③) ────────────────────────────────────────────

  Future<void> _onShareBundle() async {
    final locale = AppLocale.read(context);
    final svc = widget.service;

    // Privacy confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('connection_sheet_share_bundle')),
        content: Text(locale.get('connection_sheet_bundle_privacy_warning')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(locale.get('connection_sheet_bundle_share_confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final bundleData = await svc.exportPeerBundle();

      if (bundleData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locale.get('connection_sheet_bundle_import_error'))),
          );
        }
        return;
      }

      final uri = bundleData['uri'] as String? ?? '';
      if (uri.isEmpty) return;

      // Copy URI to clipboard and show share sheet
      await Clipboard.setData(ClipboardData(text: uri));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${locale.get('connection_sheet_share_bundle')}: URI copied')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  // ── Bundle Import (Feature ③) ────────────────────────────────────────────

  Future<void> _onImportBundle() async {
    final locale = AppLocale.read(context);
    final input = _importController.text.trim();
    if (input.isEmpty) return;

    final svc = widget.service;
    setState(() {
      _importing = true;
      _importResult = null;
    });
    try {
      final result = await svc.importPeerBundle(
        uri: input.startsWith('cleona://') ? input : null,
        bundleBase64: !input.startsWith('cleona://') ? input : null,
      );

      if (!mounted) return;

      final valid = result['networkTagValid'] as bool? ?? false;
      if (!valid) {
        setState(() => _importResult = locale.get('connection_sheet_bundle_import_error'));
      } else {
        final contacted = result['peersContacted'] as int? ?? 0;
        setState(() {
          _importResult = locale.get('connection_sheet_bundle_import_success')
              .replaceAll('{n}', '$contacted');
          _importController.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _importResult = '$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── Manual Peer Entry ────────────────────────────────────────────────────

  void _onAddPeer() {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 0;
    if (ip.isEmpty || port <= 0 || port > 65535) return;
    widget.service.addManualPeer(ip, port);
    _ipController.clear();
    _portController.clear();
    FocusScope.of(context).unfocus();
  }

  /// Compact relative age using international unit symbols (s/min/h/d) —
  /// the surrounding label comes from i18n (`connection_sheet_last_seen`).
  String _formatLastSeen(DateTime lastSeen) {
    final d = DateTime.now().difference(lastSeen);
    if (d.inSeconds < 60) return '${d.inSeconds} s';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Column(
          children: [
            // Drag handle
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Title bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    locale.get('connection_sheet_title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // ── Section 1: Active Peers ──────────────────────────
                  _SectionHeader(locale.get('connection_sheet_active_peers')),
                  if (_peers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        locale.get('connection_sheet_no_peers'),
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    ..._peers.take(20).map((p) => ListTile(
                      dense: true,
                      // S119 B: green = direct (confirmed bidirectional
                      // UDP), amber = reachable via relay route only.
                      leading: Icon(Icons.circle, size: 10,
                          color: p.isDirect ? Colors.green : Colors.amber),
                      // Problem 1 (S119): peer ID + address selectable.
                      title: SelectableText(
                        '${p.nodeIdHex.substring(0, 16)}…',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (p.allAddresses.isNotEmpty)
                            SelectableText(p.allAddresses.first,
                                style: const TextStyle(fontSize: 11)),
                          Text(
                            locale.get('connection_sheet_last_seen').replaceAll(
                                '{t}', _formatLastSeen(p.lastSeen)),
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )),

                  const Divider(),

                  // ── Section 2: Reconnect (Feature ②) ─────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _reconnecting ? null : _onReconnect,
                          icon: _reconnecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(locale.get('connection_sheet_reconnect')),
                        ),
                        if (_reconnectResult != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _reconnectResult!,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Divider(),

                  // ── Section 3: Rescue Bundle (Feature ③) ──────────────
                  _SectionHeader(locale.get('connection_sheet_rescue_bundle_section')),
                  ListTile(
                    leading: const Icon(Icons.ios_share),
                    title: Text(locale.get('connection_sheet_share_bundle')),
                    onTap: _onShareBundle,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _importController,
                            decoration: InputDecoration(
                              hintText: locale.get('connection_sheet_bundle_paste_hint'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            maxLines: 3,
                            minLines: 1,
                            keyboardType: TextInputType.multiline,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: [
                            FilledButton(
                              onPressed: _importing ? null : _onImportBundle,
                              child: _importing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(locale.get('connection_sheet_import_bundle')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_importResult != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text(
                        _importResult!,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),

                  const Divider(),

                  // ── Section 4: Manual Peer Entry ──────────────────────
                  _SectionHeader(locale.get('connection_sheet_manual_peer_section')),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _ipController,
                            decoration: InputDecoration(
                              hintText: locale.get('connection_sheet_peer_ip_hint'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            keyboardType: TextInputType.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _portController,
                            decoration: InputDecoration(
                              hintText: locale.get('connection_sheet_peer_port_hint'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _onAddPeer,
                          child: Text(locale.get('connection_sheet_add_peer')),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
