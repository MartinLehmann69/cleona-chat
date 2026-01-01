// lib/ui/components/connection_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';

/// Connection sheet — §25.7
///
/// Opened when the user taps "Active Peers" (NetworkStatsScreen) or
/// "Connected Peers" (SettingsScreen → Network section).
///
/// Content:
///   1. Live list of active peers
///   2. Debounced Reconnect button
///
/// No manual address entry and no peer bundle: the sources of the first
/// neighbour are closed (§11.8, §11.8a) — S399 P1 part C.
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
    super.dispose();
  }

  // ── Reconnect ────────────────────────────────────────────────────────

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
        // In-process fallback (direct service)
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

                  // ── Section 2: Reconnect ─────────────────────────────
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
