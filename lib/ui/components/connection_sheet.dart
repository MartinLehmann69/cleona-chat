// lib/ui/components/connection_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/stats/network_stats.dart';
import 'package:mycelium/neighbourhood.dart' show Neighbourhood;

/// Connection sheet — §25.7
///
/// Opened from the tile "answering neighbours" (NetworkStatsScreen) and the
/// entry "neighbours" (SettingsScreen → Network section).
///
/// Content:
///   1. the readiness state and the answering neighbours (§22.7.1), one row
///      each: address families, fixed or not, last confirmed. Never an
///      address, a node identifier or a contact (§25.7).
///   2. Debounced Reconnect button; its answer is a SnackBar on the sheet
///      (own ScaffoldMessenger, see [_ConnectionSheetState._messenger]).
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

  /// The sheet's own messenger. The answer to "reconnect" is a SnackBar
  /// (owner decision 04.11.2026, S412 E3 = A). The root ScaffoldMessenger
  /// would put it into the Scaffold of the page BELOW this modal route —
  /// behind the barrier and under the sheet, out of sight. The sheet
  /// therefore carries its own ScaffoldMessenger + transparent Scaffold, and
  /// the SnackBar stands at the bottom edge of the sheet, which is the bottom
  /// of the screen above the system bar (SafeArea in [build]).
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  // Refreshed on open, reactively on every service state change — a readiness
  // edge is one (`mycelium_seam.dart`, `readinessChanged`) — and at the 5-s
  // cadence of §25, only while the sheet is open: a stamp moves without an
  // edge, and "8 s ago" (§25.7) must not stand still. Local only, no packet
  // (§25.10).
  NetworkStats _stats = const NetworkStats();
  String _readiness = kReadinessSearching;
  bool _fetching = false;
  bool _again = false;
  Timer? _displayTimer;
  void Function()? _prevOnStateChanged;

  @override
  void initState() {
    super.initState();
    _refresh();
    _displayTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _prevOnStateChanged = widget.service.onStateChanged;
    widget.service.onStateChanged = () {
      _prevOnStateChanged?.call();
      _refresh();
    };
  }

  /// At most one request at a time: state changes come in bursts, and over
  /// IPC each read is a round trip to the daemon.
  Future<void> _refresh() async {
    if (_fetching) {
      _again = true;
      return;
    }
    _fetching = true;
    do {
      _again = false;
      final service = widget.service;
      final stats = service is IpcClient
          ? await service.fetchNetworkStats()
          : service.getNetworkStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _readiness = service.readinessState;
      });
    } while (_again);
    _fetching = false;
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    widget.service.onStateChanged = _prevOnStateChanged;
    super.dispose();
  }

  // ── Reconnect ────────────────────────────────────────────────────────

  Future<void> _onReconnect() async {
    if (_reconnecting) return;
    setState(() => _reconnecting = true);
    final locale = AppLocale.read(context);
    try {
      // §25.7: the edge "network change" (§11.8.2) through its one entry —
      // over IPC in the daemon, in process on the phone (S407-LB-P12).
      final result = await widget.service.reconnect();

      if (!mounted) return;

      final debounced = result['debounced'] as bool? ?? false;
      final remaining = result['remainingSeconds'] as int? ?? 0;

      // The edge runs behind the answer: what it finds arrives as readiness
      // edges and fills the list. This notice claims no result (§25.2 rule 4).
      _notify(debounced
          ? locale
              .get('connection_sheet_reconnect_debounced')
              .replaceAll('{s}', '$remaining')
          : locale.get('connection_sheet_reconnect_started'));
    } catch (e) {
      if (mounted) _notify('$e');
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  /// One place for the answer: a SnackBar on the sheet that leaves by itself
  /// (default duration, 4 s). It does not depend on the scroll position — the
  /// reconnect empties and refills the neighbour list, and the list stands
  /// at its top again (S412 RCA B-3). A second click replaces the notice
  /// instead of queueing behind it.
  void _notify(String text) {
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        // The messenger and its Scaffold sit INSIDE the draggable sheet, so
        // they cover exactly the sheet: the area above it stays the modal
        // barrier (a tap there still closes the sheet), and the SnackBar
        // follows the sheet's bottom edge at every drag size.
        builder: (ctx, scrollController) => ScaffoldMessenger(
          key: _messenger,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: _content(context, scrollController),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ScrollController scrollController) {
    final locale = AppLocale.read(context);
    final colorScheme = Theme.of(context).colorScheme;
    final neighbours = _stats.neighbours;
    return Column(
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
                  // ── Section 1: readiness and answering neighbours ────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      switch (_readiness) {
                        kReadinessReady => locale.get('readiness_ready'),
                        kReadinessConnecting =>
                          locale.get('readiness_connecting'),
                        _ => locale.get('readiness_searching'),
                      },
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  _SectionHeader(locale.tr('connection_sheet_answering', {
                    'n': '${neighbours.length}',
                    'max': '${Neighbourhood.atMost}',
                  })),
                  if (neighbours.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        locale.get('connection_sheet_no_neighbours'),
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    ...neighbours.map((n) => NeighbourRowTile(row: n)),

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
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        );
  }
}

/// One row of §25.7: address family, fixed, found by, last confirmed. Used by
/// this sheet and by the section "Neighbours" of the statistics.
class NeighbourRowTile extends StatelessWidget {
  final NeighbourRow row;
  const NeighbourRowTile({super.key, required this.row});

  /// International unit symbols (s/min/h/d), the words around them are i18n.
  static String _age(DateTime stamp) {
    final d = DateTime.now().difference(stamp);
    if (d.inSeconds < 60) return '${d.inSeconds < 0 ? 0 : d.inSeconds} s';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final source = switch (row.foundBy) {
      'remembered' => locale.get('neighbour_source_remembered'),
      'localSegment' => locale.get('neighbour_source_local_segment'),
      'invitation' => locale.get('neighbour_source_invitation'),
      'externalRecords' => locale.get('neighbour_source_external_records'),
      'board' => locale.get('neighbour_source_board'),
      _ => null,
    };
    return ListTile(
      dense: true,
      leading: Icon(row.fixed ? Icons.push_pin : Icons.hub, size: 16),
      title: Text(row.fixed
          ? '${row.families.join(' + ')} · '
              '${locale.get('connection_sheet_neighbour_fixed')}'
          : row.families.join(' + ')),
      subtitle: Text(
        [
          if (source != null) locale.tr('neighbour_found_by', {'s': source}),
          locale.tr(
              'connection_sheet_last_confirmed', {'t': _age(row.lastConfirmed)}),
        ].join('\n'),
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
