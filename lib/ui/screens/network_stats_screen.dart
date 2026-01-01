import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/stats/network_stats.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/connection_sheet.dart';

/// The network statistics — five sections, ordered by the three questions
/// that a user really has:
///
///   1. **Connection** — "am I connected?"
///   2. **Delivery** — "does my mail arrive?"
///   3. **Faults** — "what is the cause if not?"
///   4. Data usage — what it costs
///   5. Contribution for others — what this device carries for the network
///
/// ── WHY REORDERED AND NOT JUST SHORTENED (S360, 01.09.2026) ────
///
/// The old structure ("Network Health", "Data Usage", "Relay
/// Contribution", "Connection Details") was the structure of the
/// V3 DATA STRUCTURE: four sections that only belonged together because
/// four V3 components supplied them — routing table, transport,
/// fragment store, NAT traversal. All four were deleted with the CUT of
/// 31.08.
///
/// Since then twelve tiles showed a 0 that looked like a measurement.
/// The owner on 01.09.: "Remove everything that delivers numbers about V 3 and
/// replace it with correspondingly meaningful information about v4."
///
/// Draft and field table: `docs/v4-redesign/S360-netzstatistik-v41.md`.
class NetworkStatsScreen extends StatefulWidget {
  final ICleonaService service;
  const NetworkStatsScreen({super.key, required this.service});

  @override
  State<NetworkStatsScreen> createState() => _NetworkStatsScreenState();
}

class _NetworkStatsScreenState extends State<NetworkStatsScreen> {
  NetworkStats _stats = const NetworkStats();

  /// §22.7 — read along at the 5-s cadence like the other metrics.
  ///
  /// It does NOT come from [NetworkStats]: the collection there is the
  /// V3 network statistics, the readiness arises in the
  /// V4.1 delivery layer and stands directly on the service interface
  /// (`ICleonaService.readinessState`). Routing it through the statistics
  /// would mean keeping it a second time.
  String _readiness = kReadinessSearching;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Auto-refresh every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final service = widget.service;
    NetworkStats stats;
    if (service is IpcClient) {
      stats = await service.fetchNetworkStats();
    } else {
      stats = service.getNetworkStats();
    }
    if (mounted) {
      setState(() {
        _stats = stats;
        _readiness = service.readinessState;
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // ── Section 1: Connection ──────────────────────────────────
        _SectionHeader(locale.get('stats_network_health')),
        // §25.4: the health badge maps the READINESS 1:1
        // ("The badge mirrors the readiness state 1:1 and applies no
        // threshold logic of its own"). Before, it drew from
        // `NetworkStats.healthLevel`, i.e. from two thresholds on a
        // peer count (>= 10 / >= 3). §25.4 rejects exactly that: "many sync
        // partners in the same island are not deliverable."
        _HealthBadge(readiness: _readiness),
        const SizedBox(height: 8),
        // §25.4 section 1, header line: the readiness is the
        // lead metric of the dashboard, and the hint below says what
        // is still missing — before `ready` the app reports progress, not
        // success (§22.7.1).
        _StatTile(
          icon: Icons.verified,
          label: locale.get('stats_readiness'),
          value: switch (_readiness) {
            kReadinessReady => locale.get('readiness_ready'),
            kReadinessConnecting => locale.get('readiness_connecting'),
            _ => locale.get('readiness_searching'),
          },
          color: _readinessColor(_readiness, colorScheme),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            switch (_readiness) {
              kReadinessReady => locale.get('readiness_ready_hint'),
              kReadinessConnecting => locale.get('readiness_connecting_hint'),
              _ => locale.get('readiness_searching_hint'),
            },
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        // ══ VARIANT B (owner decision 02.09.2026) ═══════════════
        //
        // §25.4 demands the three numbers SEPARATELY, and all three stay.
        // What changes is their WEIGHTING: the independent number
        // stands large and first, the two direction-split ones smaller
        // below.
        //
        // WHY THE INDEPENDENT ONE STANDS AT THE TOP. It is the only one that
        // carries the readiness statement — `ready` depends on
        // `Partition.independentCount` (>= 2, §22.7.1), not on a
        // gross count. Three equally large numbers side by side suggested to the
        // reader that the largest is the most important; that is exactly the
        // confusion that §22.7.3 forbids ("no display element derives
        // deliverability from a partner count").
        //
        // WHY THE INCOMING ONE STILL STAYS VISIBLE. It is the
        // only one that tells a user behind CGNAT/DS-Lite whether they are
        // reachable from outside at all (§25.4: "a precondition for
        // inbound calls"). Pushing it into a submenu would take the information
        // from exactly the group that needs it most urgently.
        //
        // THE COLOUR STILL BELONGS TO THE READINESS (§25.4: "the badge
        // mirrors the readiness state 1:1") — therefore only the
        // large tile carries `_readinessColor`, the two small ones none.
        _LeadStatTile(
          icon: Icons.call_split,
          label: locale.get('stats_partners_independent_lead'),
          value: '${widget.service.independentSyncPartners}',
          note: locale.get('stats_partners_independent_note'),
          color: _readinessColor(_readiness, colorScheme),
        ),
        // §25.4: the partner counts SEPARATED by direction — smaller, but
        // fully visible.
        _StatTile(
          icon: Icons.north_east,
          label: locale.get('stats_sync_partners_outbound'),
          value: '${widget.service.syncPartnersOutbound}',
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => showConnectionSheet(context, widget.service),
        ),
        _StatTile(
          icon: Icons.south_west,
          label: locale.get('stats_sync_partners_inbound'),
          value: '${widget.service.syncPartnersInbound}',
        ),
        // §25.4: what the incoming number MEANS — "states how much the
        // node contributes for others; a precondition for inbound calls".
        // As a subordinate line under the number, not as its own traffic light: the
        // colouring of this section belongs to the readiness (§25.4,
        // "the badge mirrors the readiness state 1:1"), and "not
        // reachable" is the normal case behind CGNAT/DS-Lite, not an
        // error. Therefore deliberately `onSurfaceVariant` and no
        // error colour (decision variant C, 2026-08-30).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '${locale.get(widget.service.syncPartnersInbound > 0 ? 'reach_inbound_yes' : 'reach_inbound_no')}'
            ' \u2014 ${locale.get('reach_inbound_explain')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        // §25.4 lists the DATA-SAVING MODE as a metric of this section
        // ("Data-saving mode | §22.6, §5.4 | active/inactive"), and
        // §24.4.2 turns it into the requirement: "a visible state, not a
        // setting buried in a submenu". Here it is fulfilled — the
        // switch in the settings is the action, THIS line
        // is the state.
        //
        // The value comes directly from the service interface, like the
        // partner counts above; the 5-s cadence of `_refresh` redraws
        // the view anyway.
        _StatTile(
          icon: widget.service.dataSaverLockedBySecure
              ? Icons.lock_outline
              : Icons.data_saver_on,
          label: locale.get('datasaver_title'),
          value: locale.get(widget.service.dataSaverActive
              ? 'datasaver_state_on'
              : 'datasaver_state_off'),
          color: widget.service.dataSaverActive ? Colors.orange : null,
        ),
        // §24.4.2: the consequence stands NEXT TO the state, not behind a
        // question mark. If the switch is locked, the
        // reason stands here ("locked with its reason named").
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            widget.service.dataSaverLockedBySecure
                ? locale.get('datasaver_locked_secure')
                : locale.get('datasaver_consequence'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        // §11 — WITH WHAT THE SEARCH CAN START AT ALL.
        //
        // Until S360 four V3 tiles stood here: "Active peers",
        // "Known peers", "NAT type" and the public address. All
        // four needed components that no longer exist — a global
        // peer set, a STUN classification, a port mapping.
        //
        // This one takes their place, and it answers a
        // question that the four never answered: if the
        // readiness is at `searching`, it says WHETHER the cascade
        // has anything at all to start with.
        _StatTile(
          icon: Icons.hub,
          label: locale.get('stats_entry_records'),
          value: '${_stats.entryRecords}',
          note: locale.get('stats_entry_records_note'),
        ),
        _StatTile(
          icon: Icons.timer,
          label: locale.get('stats_uptime'),
          value: _formatDuration(_stats.uptime),
        ),
        _StatTile(
          icon: Icons.circle,
          label: 'Status',
          value: _stats.isRunning ? 'Online' : 'Offline',
          color: _stats.isRunning ? Colors.green : colorScheme.error,
        ),

        const Divider(),

        // ── Section 2: delivery ────────────────────────────────
        //
        // "Does my mail arrive?" The four counters of the assembler
        // stand together here, and that is the whole purpose: without them
        // three completely different findings looked alike — "nothing
        // arrived at all", "pieces arrived, the payload was never
        // finished" and "the payload was finished but could not be
        // opened" (`v41_node.dart`, comment at `verworfeneStuecke`).
        _SectionHeader(locale.get('stats_delivery')),
        _StatTile(
          icon: Icons.av_timer,
          label: locale.get('stats_slots_emitted'),
          value: '${_stats.slotsEmitted}',
          note: locale.get('stats_slots_emitted_note'),
        ),
        _StatTile(
          icon: Icons.timer_off,
          label: locale.get('stats_slots_missed'),
          value: '${_stats.slotsSkipped} / ${_stats.slotsFailed}',
          color: _stats.slotsFailed > 0 ? colorScheme.error : null,
        ),
        _StatTile(
          icon: Icons.download_for_offline,
          label: locale.get('stats_harvest_runs'),
          value: '${_stats.harvestRuns}',
        ),
        _StatTile(
          icon: Icons.travel_explore,
          label: locale.get('stats_lookup_runs'),
          value: '${_stats.lookupRuns}',
        ),
        _StatTile(
          icon: Icons.extension,
          label: locale.get('stats_payloads_assembled'),
          value: '${_stats.payloadsAssembled}',
        ),
        _StatTile(
          icon: Icons.mark_email_read,
          label: locale.get('stats_payloads_opened'),
          value: '${_stats.payloadsOpened}',
          note: locale.get('stats_payloads_opened_note'),
        ),
        _StatTile(
          icon: Icons.hourglass_bottom,
          label: locale.get('stats_open_transfers'),
          value: '${_stats.openTransfers}',
        ),
        _StatTile(
          icon: Icons.delete_sweep,
          label: locale.get('stats_pieces_discarded'),
          value: '${_stats.piecesDiscarded}',
        ),

        const Divider(),

        // ── Section 3: faults ────────────────────────────────
        //
        // "What is the cause if not?" These five tiles are the
        // only place where a user learns that something fails
        // SILENTLY. The carriers were built and measured; until S360
        // they stood only in the node's status line — a
        // log line that no user sees.
        _SectionHeader(locale.get('stats_disturbances')),
        _StatTile(
          icon: Icons.queue,
          label: locale.get('stats_control_queue'),
          value: '${_stats.controlQueueDepth} / ${_stats.controlQueueMax}',
        ),
        _StatTile(
          icon: Icons.report_gmailerrorred,
          label: locale.get('stats_control_dropped'),
          value: '${_stats.droppedControl} + ${_stats.droppedEphemeral}',
          color: _stats.droppedControl > 0 ? Colors.orange : null,
          note: locale.get('stats_control_dropped_note'),
        ),
        _StatTile(
          icon: Icons.error_outline,
          label: locale.get('stats_control_failures'),
          value: '${_stats.controlFailures}',
          color: _stats.controlFailures > 0 ? Colors.orange : null,
        ),
        // §21.3.3 no. 4, verbatim: „a node that evicts under budget
        // pressure shows this visibly in the network statistics (§25). A
        // silently shrinking delivery layer is the storage variant of the
        // failure mode §1.2 rules out for delivery." The number was there, the
        // display was missing.
        _StatTile(
          icon: Icons.remove_circle_outline,
          label: locale.get('stats_store_evicted'),
          value: '${_stats.storedEvicted + _stats.blindEvicted}',
          color: (_stats.storedEvicted + _stats.blindEvicted) > 0
              ? Colors.orange
              : null,
          note: locale.get('stats_store_evicted_note'),
        ),
        _StatTile(
          icon: Icons.block,
          label: locale.get('stats_store_refused'),
          value: '${_stats.blindRefused}',
        ),

        const Divider(),

        // ── Section 4: Data usage ─────────────────────────────────
        _SectionHeader(locale.get('stats_data_usage')),
        _StatTile(
          icon: Icons.upload,
          label: locale.get('stats_sent_total'),
          value: _formatBytes(_stats.bytesSentTotal),
        ),
        _StatTile(
          icon: Icons.download,
          label: locale.get('stats_received_total'),
          value: _formatBytes(_stats.bytesReceivedTotal),
        ),
        _StatTile(
          icon: Icons.today,
          label: locale.get('stats_sent_today'),
          value: _formatBytes(_stats.bytesSentToday),
        ),
        _StatTile(
          icon: Icons.today,
          label: locale.get('stats_received_today'),
          value: _formatBytes(_stats.bytesReceivedToday),
        ),
        _StatTile(
          icon: Icons.message,
          label: locale.get('stats_messages_sent'),
          value: '${_stats.messagesSent}',
        ),
        _StatTile(
          icon: Icons.message_outlined,
          label: locale.get('stats_messages_received'),
          value: '${_stats.messagesReceived}',
        ),

        const Divider(),

        // ── Section 5: contribution for others ──────────────────────
        _SectionHeader(locale.get('stats_relay_contribution')),
        _StatTile(
          icon: Icons.swap_horiz,
          label: locale.get('stats_messages_relayed'),
          value: '${_stats.messagesRelayed}',
        ),
        // THE SUBSET REQUIREMENT (owner, 31.08.). The forwarded
        // envelope runs through the socket anyway and is thus
        // already contained in "Sent". Without this hint the reader adds
        // the same bytes twice.
        _StatTile(
          icon: Icons.data_usage,
          label: locale.get('stats_relay_volume'),
          value: _formatBytes(_stats.relayDataVolume),
          note: locale.get('stats_relay_volume_note'),
        ),
        // THE V4.1 COUNTERPART TO "STORED FRAGMENTS". There it was
        // Reed-Solomon fragments of foreign messages; here it is
        // cells on foreign taglines that lie until the harvest.
        _StatTile(
          icon: Icons.inventory_2,
          label: locale.get('stats_stored_cells'),
          value: '${_stats.storedCells}',
          note: locale.get('stats_stored_cells_note'),
        ),
        _StatTile(
          icon: Icons.visibility_off,
          label: locale.get('stats_blind_held'),
          value: '${_stats.blindHeld}',
        ),
        _StatTile(
          icon: Icons.dataset,
          label: locale.get('stats_db_size'),
          value: _formatBytes(_stats.dbSizeBytes),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// §25.4, table "Health badge": `ready` green, `connecting` yellow,
/// `searching` red — without threshold logic of its own.
///
/// Replaces `_healthColor(stats.healthLevel, ...)`, which came from two
/// peer-count thresholds (`>= 10` good, `>= 3` warning). §22.7.3
/// forbids exactly that: inferring deliverability from a partner count.
/// `NetworkStats.healthLevel` thus lost its last consumer from AP-5 on
/// and fell on 01.09.2026 (S360) together with the peer counts
/// themselves.
Color _readinessColor(String readiness, ColorScheme cs) => switch (readiness) {
      kReadinessReady => Colors.green,
      kReadinessConnecting => Colors.orange,
      _ => cs.error,
    };

class _HealthBadge extends StatelessWidget {
  final String readiness;
  const _HealthBadge({required this.readiness});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final scheme = Theme.of(context).colorScheme;
    // §25.4, table: ready = green, connecting = yellow, searching = red.
    final color = _readinessColor(readiness, scheme);
    final label = switch (readiness) {
      kReadinessReady => locale.get('readiness_ready'),
      kReadinessConnecting => locale.get('readiness_connecting'),
      _ => locale.get('readiness_searching'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// A subordinate line under the label — for numbers whose meaning
  /// does NOT follow from the name.
  ///
  /// First case: the relay volume is a SUBSET of "Sent",
  /// not an additional quantity. Without the hint the reader adds
  /// the same bytes twice — and the neighbouring numbers have been right since S357,
  /// so the confusion would be new and would be due to this change.
  final String? note;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.trailing,
    this.onTap,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: color,
      fontFamily: 'monospace',
    );
    // Problem 1 (S119): stat values without onTap are selectable (public
    // IP etc.); tappable tiles (Aktive Peers → Connection-Sheet) keep Text
    // so the tap gesture is not swallowed.
    final valueWidget = onTap == null
        ? SelectableText(value, style: valueStyle)
        : Text(value, style: valueStyle);
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(label),
      subtitle: note == null
          ? null
          : Text(note!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
      trailing: trailing != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [valueWidget, const SizedBox(width: 4), trailing!],
            )
          : valueWidget,
      onTap: onTap,
    );
  }
}

/// The LOAD-BEARING metric of a section — set large, with a
/// subordinate line below that says why exactly it carries.
///
/// ── WHY A SEPARATE WIDGET AND NOT A FLAG ON [_StatTile] ───────────
///
/// [_StatTile] is a ROW: same height, same rhythm, thirty
/// of them one below another. An `isLead: true` on it would have let the same class
/// be two different things and made every future change to the
/// row height a change to the lead metric. The two
/// have different jobs, so they are two widgets.
///
/// **The colour comes from outside and is not decided here.** §25.4
/// binds the colouring of this section to the READINESS; a
/// threshold logic on the partner count itself would be exactly what §22.7.3
/// forbids.
class _LeadStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String note;
  final Color? color;

  const _LeadStatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.note,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // SelectableText as in [_StatTile]: the number should be copyable
          // for a bug report (problem 1, S119).
          SelectableText(
            value,
            style: text.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: color,
            ),
          ),
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
