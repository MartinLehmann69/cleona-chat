import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/network/network_stats.dart';
import 'package:cleona/core/service/service_interface.dart';

/// Network Statistics Dashboard — 4 sections:
/// 1. Network Health & Active Nodes
/// 2. Personal Data Usage
/// 3. Relay Contribution
/// 4. Connection Details (Technical)
class NetworkStatsScreen extends StatefulWidget {
  final ICleonaService service;
  const NetworkStatsScreen({super.key, required this.service});

  @override
  State<NetworkStatsScreen> createState() => _NetworkStatsScreenState();
}

class _NetworkStatsScreenState extends State<NetworkStatsScreen> {
  NetworkStats _stats = const NetworkStats();
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
    if (mounted) setState(() => _stats = stats);
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
        // ── Section 1: Network Health ──────────────────────────────
        _SectionHeader(locale.get('stats_network_health')),
        _HealthBadge(stats: _stats),
        const SizedBox(height: 8),
        _StatTile(
          icon: Icons.cell_tower,
          label: locale.get('stats_active_peers'),
          value: '${_stats.activePeerCount}',
          color: _healthColor(_stats.healthLevel, colorScheme),
        ),
        _StatTile(
          icon: Icons.hub,
          label: locale.get('stats_total_known_peers'),
          value: '${_stats.totalKnownPeers}',
        ),
        _StatTile(
          icon: Icons.router,
          label: locale.get('stats_nat_type'),
          value: _stats.natType,
        ),
        if (_stats.publicIp != null)
          _StatTile(
            icon: Icons.language,
            label: locale.get('stats_public_ip'),
            value: '${_stats.publicIp}:${_stats.publicPort ?? "?"}',
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

        // ── Section 2: Data Usage ─────────────────────────────────
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

        // ── Section 3: Relay Contribution ─────────────────────────
        _SectionHeader(locale.get('stats_relay_contribution')),
        _StatTile(
          icon: Icons.inventory_2,
          label: locale.get('stats_fragments_stored'),
          value: '${_stats.fragmentsStored}',
        ),
        _StatTile(
          icon: Icons.swap_horiz,
          label: locale.get('stats_messages_relayed'),
          value: '${_stats.messagesRelayed}',
        ),
        _StatTile(
          icon: Icons.data_usage,
          label: locale.get('stats_relay_volume'),
          value: _formatBytes(_stats.relayDataVolume),
        ),
        _StatTile(
          icon: Icons.storage,
          label: locale.get('stats_storage_used'),
          value: _formatBytes(_stats.storageUsedBytes),
        ),
        _StatTile(
          icon: Icons.dataset,
          label: locale.get('stats_db_size'),
          value: _formatBytes(_stats.dbSizeBytes),
        ),

        const Divider(),

        // ── Section 4: Connection Details ─────────────────────────
        _SectionHeader(locale.get('stats_connection_details')),
        _StatTile(
          icon: Icons.link,
          label: locale.get('stats_direct_connections'),
          value: '${_stats.directConnections}',
        ),
        _StatTile(
          icon: Icons.table_chart,
          label: locale.get('stats_routing_table_size'),
          value: '${_stats.routingTableSize}',
        ),
        if (_stats.avgLatencyMs > 0) ...[
          _StatTile(
            icon: Icons.speed,
            label: locale.get('stats_avg_latency'),
            value: '${_stats.avgLatencyMs.toStringAsFixed(1)} ms',
          ),
          _StatTile(
            icon: Icons.speed,
            label: locale.get('stats_min_max_latency'),
            value: '${_stats.minLatencyMs.toStringAsFixed(1)} / ${_stats.maxLatencyMs.toStringAsFixed(1)} ms',
          ),
        ],

        // K-Bucket fill visualization
        if (_stats.kBucketStats.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              locale.get('stats_kbucket_fill'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _KBucketChart(buckets: _stats.kBucketStats),
            ),
          ),
        ],

        // Peer latency list
        if (_stats.peerLatencies.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              locale.get('stats_peer_latencies'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          ...(_stats.peerLatencies.take(10).map((p) => ListTile(
                dense: true,
                leading: Icon(Icons.circle, size: 8,
                    color: p.latencyMs < 50 ? Colors.green : p.latencyMs < 200 ? Colors.orange : colorScheme.error),
                title: Text(
                  '${p.nodeIdHex.substring(0, 12)}...',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                trailing: Text('${p.latencyMs.toStringAsFixed(1)} ms'),
              ))),
        ],

        const SizedBox(height: 16),
      ],
    );
  }

  Color _healthColor(String level, ColorScheme cs) {
    switch (level) {
      case 'good':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      default:
        return cs.error;
    }
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

class _HealthBadge extends StatelessWidget {
  final NetworkStats stats;
  const _HealthBadge({required this.stats});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final color = stats.healthLevel == 'good'
        ? Colors.green
        : stats.healthLevel == 'warning'
            ? Colors.orange
            : Theme.of(context).colorScheme.error;

    final label = stats.healthLevel == 'good'
        ? locale.get('stats_health_good')
        : stats.healthLevel == 'warning'
            ? locale.get('stats_health_warning')
            : locale.get('stats_health_critical');

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
  const _StatTile({required this.icon, required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(label),
      trailing: Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontFamily: 'monospace',
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

class _KBucketChart extends StatelessWidget {
  final List<KBucketStats> buckets;
  const _KBucketChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final maxCount = buckets.fold<int>(0, (max, b) => b.peerCount > max ? b.peerCount : max);
    if (maxCount == 0) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: buckets.map((b) {
        final height = (b.peerCount / 20.0) * 50.0; // max 20 peers per bucket
        return Expanded(
          child: Tooltip(
            message: 'Bucket ${b.index}: ${b.peerCount}/${b.capacity}',
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 0.5),
              height: height.clamp(2.0, 50.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
