import 'dart:io';
import 'package:cleona/core/dht/kbucket.dart';
import 'package:cleona/core/dht/mailbox_store.dart';
import 'package:cleona/core/network/nat_traversal.dart';
import 'package:cleona/core/network/peer_info.dart';

/// UPnP IGD status for NAT-Troubleshooting-Wizard trigger (§27.9.1).
enum UpnpStatus {
  /// Not yet probed or indeterminate.
  unknown,
  /// AddPortMapping succeeded.
  ok,
  /// No IGD responded to SSDP discovery (UPnP disabled or no router support).
  unavailable,
  /// IGD responded but AddPortMapping was rejected.
  rejected,
}

/// PCP / NAT-PMP status for NAT-Troubleshooting-Wizard trigger (§27.9.1).
enum PcpStatus {
  unknown,
  /// MAP request returned a successful response.
  ok,
  /// No response after retries, or error-code response.
  failed,
}

/// UPnP IGD rootDesc parse result. Populated by [UpnpIgdClient] when the
/// descriptor XML is fetched during discovery. Used by the NAT-Wizard
/// router-DB matcher (§27.9.2 Step 2).
class UpnpRouterInfo {
  final String? manufacturer;
  final String? modelName;
  final String? modelNumber;
  final String? friendlyName;

  const UpnpRouterInfo({
    this.manufacturer,
    this.modelName,
    this.modelNumber,
    this.friendlyName,
  });

  bool get isEmpty =>
      (manufacturer?.isEmpty ?? true) &&
      (modelName?.isEmpty ?? true) &&
      (modelNumber?.isEmpty ?? true) &&
      (friendlyName?.isEmpty ?? true);

  Map<String, dynamic> toJson() => {
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (modelName != null) 'modelName': modelName,
        if (modelNumber != null) 'modelNumber': modelNumber,
        if (friendlyName != null) 'friendlyName': friendlyName,
      };

  static UpnpRouterInfo fromJson(Map<String, dynamic> json) => UpnpRouterInfo(
        manufacturer: json['manufacturer'] as String?,
        modelName: json['modelName'] as String?,
        modelNumber: json['modelNumber'] as String?,
        friendlyName: json['friendlyName'] as String?,
      );

  @override
  String toString() =>
      'UpnpRouterInfo(manufacturer=$manufacturer, model=$modelName, '
      'number=$modelNumber, friendly=$friendlyName)';
}

/// Aggregated network statistics for the Network Stats Dashboard.
/// Collects data from RoutingTable, Transport, MailboxStore, NatTraversal.
class NetworkStats {
  // ── Section 1: Network Health ──────────────────────────────────
  final int activePeerCount;
  final int totalKnownPeers;
  final String natType;
  final String? publicIp;
  final int? publicPort;
  final Duration uptime;
  final bool isRunning;
  final List<PeerHealthEntry> peerHistory;

  // ── Section 2: Data Usage ──────────────────────────────────────
  final int bytesSentTotal;
  final int bytesReceivedTotal;
  final int bytesSentToday;
  final int bytesReceivedToday;
  final int messagesSent;
  final int messagesReceived;
  final int dhtMaintenanceBytes;
  final int relayBytes;

  // ── Section 3: Relay Contribution ──────────────────────────────
  final int fragmentsStored;
  final int messagesRelayed;
  final int relayDataVolume;
  final int storageUsedBytes;

  // ── Section 4: Connection Details ──────────────────────────────
  final int directConnections;
  final int routingTableSize;
  final List<KBucketStats> kBucketStats;
  final double avgLatencyMs;
  final double minLatencyMs;
  final double maxLatencyMs;
  final List<PeerLatencyEntry> peerLatencies;
  final int dbSizeBytes;

  // ── Section 5: NAT-Wizard Signals (§27.9) ───────────────────────
  /// UPnP IGD state — consumed by the NAT-Wizard trigger (§27.9.1).
  final UpnpStatus upnpStatus;
  /// PCP / NAT-PMP state — consumed by the NAT-Wizard trigger (§27.9.1).
  final PcpStatus pcpStatus;
  /// Parsed UPnP rootDesc (manufacturer/model). Null if UPnP yielded nothing.
  /// Used by the NAT-Wizard router-DB matcher (§27.9.2 Step 2).
  final UpnpRouterInfo? upnpRouterInfo;

  const NetworkStats({
    this.activePeerCount = 0,
    this.totalKnownPeers = 0,
    this.natType = 'unknown',
    this.publicIp,
    this.publicPort,
    this.uptime = Duration.zero,
    this.isRunning = false,
    this.peerHistory = const [],
    this.bytesSentTotal = 0,
    this.bytesReceivedTotal = 0,
    this.bytesSentToday = 0,
    this.bytesReceivedToday = 0,
    this.messagesSent = 0,
    this.messagesReceived = 0,
    this.dhtMaintenanceBytes = 0,
    this.relayBytes = 0,
    this.fragmentsStored = 0,
    this.messagesRelayed = 0,
    this.relayDataVolume = 0,
    this.storageUsedBytes = 0,
    this.directConnections = 0,
    this.routingTableSize = 0,
    this.kBucketStats = const [],
    this.avgLatencyMs = 0,
    this.minLatencyMs = 0,
    this.maxLatencyMs = 0,
    this.peerLatencies = const [],
    this.dbSizeBytes = 0,
    this.upnpStatus = UpnpStatus.unknown,
    this.pcpStatus = PcpStatus.unknown,
    this.upnpRouterInfo,
  });

  Map<String, dynamic> toJson() => {
        'activePeerCount': activePeerCount,
        'totalKnownPeers': totalKnownPeers,
        'natType': natType,
        'publicIp': publicIp,
        'publicPort': publicPort,
        'uptimeSeconds': uptime.inSeconds,
        'isRunning': isRunning,
        'bytesSentTotal': bytesSentTotal,
        'bytesReceivedTotal': bytesReceivedTotal,
        'bytesSentToday': bytesSentToday,
        'bytesReceivedToday': bytesReceivedToday,
        'messagesSent': messagesSent,
        'messagesReceived': messagesReceived,
        'dhtMaintenanceBytes': dhtMaintenanceBytes,
        'relayBytes': relayBytes,
        'fragmentsStored': fragmentsStored,
        'messagesRelayed': messagesRelayed,
        'relayDataVolume': relayDataVolume,
        'storageUsedBytes': storageUsedBytes,
        'directConnections': directConnections,
        'routingTableSize': routingTableSize,
        'avgLatencyMs': avgLatencyMs,
        'minLatencyMs': minLatencyMs,
        'maxLatencyMs': maxLatencyMs,
        'peerLatencies': peerLatencies.map((p) => p.toJson()).toList(),
        'kBucketStats': kBucketStats.map((k) => k.toJson()).toList(),
        'dbSizeBytes': dbSizeBytes,
        'upnpStatus': upnpStatus.name,
        'pcpStatus': pcpStatus.name,
        if (upnpRouterInfo != null) 'upnpRouterInfo': upnpRouterInfo!.toJson(),
      };

  static NetworkStats fromJson(Map<String, dynamic> json) => NetworkStats(
        activePeerCount: json['activePeerCount'] as int? ?? 0,
        totalKnownPeers: json['totalKnownPeers'] as int? ?? 0,
        natType: json['natType'] as String? ?? 'unknown',
        publicIp: json['publicIp'] as String?,
        publicPort: json['publicPort'] as int?,
        uptime: Duration(seconds: json['uptimeSeconds'] as int? ?? 0),
        isRunning: json['isRunning'] as bool? ?? false,
        bytesSentTotal: json['bytesSentTotal'] as int? ?? 0,
        bytesReceivedTotal: json['bytesReceivedTotal'] as int? ?? 0,
        bytesSentToday: json['bytesSentToday'] as int? ?? 0,
        bytesReceivedToday: json['bytesReceivedToday'] as int? ?? 0,
        messagesSent: json['messagesSent'] as int? ?? 0,
        messagesReceived: json['messagesReceived'] as int? ?? 0,
        dhtMaintenanceBytes: json['dhtMaintenanceBytes'] as int? ?? 0,
        relayBytes: json['relayBytes'] as int? ?? 0,
        fragmentsStored: json['fragmentsStored'] as int? ?? 0,
        messagesRelayed: json['messagesRelayed'] as int? ?? 0,
        relayDataVolume: json['relayDataVolume'] as int? ?? 0,
        storageUsedBytes: json['storageUsedBytes'] as int? ?? 0,
        directConnections: json['directConnections'] as int? ?? 0,
        routingTableSize: json['routingTableSize'] as int? ?? 0,
        avgLatencyMs: (json['avgLatencyMs'] as num?)?.toDouble() ?? 0,
        minLatencyMs: (json['minLatencyMs'] as num?)?.toDouble() ?? 0,
        maxLatencyMs: (json['maxLatencyMs'] as num?)?.toDouble() ?? 0,
        peerLatencies: (json['peerLatencies'] as List<dynamic>?)
                ?.map((p) => PeerLatencyEntry.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        kBucketStats: (json['kBucketStats'] as List<dynamic>?)
                ?.map((k) => KBucketStats.fromJson(k as Map<String, dynamic>))
                .toList() ??
            [],
        dbSizeBytes: json['dbSizeBytes'] as int? ?? 0,
        upnpStatus: _parseUpnpStatus(json['upnpStatus']),
        pcpStatus: _parsePcpStatus(json['pcpStatus']),
        upnpRouterInfo: json['upnpRouterInfo'] is Map<String, dynamic>
            ? UpnpRouterInfo.fromJson(json['upnpRouterInfo'] as Map<String, dynamic>)
            : null,
      );

  static UpnpStatus _parseUpnpStatus(dynamic v) {
    if (v is String) {
      for (final s in UpnpStatus.values) {
        if (s.name == v) return s;
      }
    }
    return UpnpStatus.unknown;
  }

  static PcpStatus _parsePcpStatus(dynamic v) {
    if (v is String) {
      for (final s in PcpStatus.values) {
        if (s.name == v) return s;
      }
    }
    return PcpStatus.unknown;
  }

  /// Health level: 'good' (>=10 peers), 'warning' (3-9), 'critical' (<3).
  String get healthLevel {
    if (activePeerCount >= 10) return 'good';
    if (activePeerCount >= 3) return 'warning';
    return 'critical';
  }
}

/// Historical peer count entry for timeline graph.
class PeerHealthEntry {
  final DateTime timestamp;
  final int peerCount;
  const PeerHealthEntry({required this.timestamp, required this.peerCount});

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.millisecondsSinceEpoch,
        'peerCount': peerCount,
      };

  static PeerHealthEntry fromJson(Map<String, dynamic> json) => PeerHealthEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        peerCount: json['peerCount'] as int,
      );
}

/// Per-peer latency entry.
class PeerLatencyEntry {
  final String nodeIdHex;
  final double latencyMs;
  final DateTime lastSeen;
  const PeerLatencyEntry({required this.nodeIdHex, required this.latencyMs, required this.lastSeen});

  Map<String, dynamic> toJson() => {
        'nodeIdHex': nodeIdHex,
        'latencyMs': latencyMs,
        'lastSeen': lastSeen.millisecondsSinceEpoch,
      };

  static PeerLatencyEntry fromJson(Map<String, dynamic> json) => PeerLatencyEntry(
        nodeIdHex: json['nodeIdHex'] as String,
        latencyMs: (json['latencyMs'] as num).toDouble(),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int),
      );
}

/// K-bucket fill statistics.
class KBucketStats {
  final int index;
  final int peerCount;
  final int capacity;
  const KBucketStats({required this.index, required this.peerCount, this.capacity = 20});

  Map<String, dynamic> toJson() => {
        'index': index,
        'peerCount': peerCount,
        'capacity': capacity,
      };

  static KBucketStats fromJson(Map<String, dynamic> json) => KBucketStats(
        index: json['index'] as int,
        peerCount: json['peerCount'] as int,
        capacity: json['capacity'] as int? ?? 20,
      );
}

/// Collects stats from live components.
class NetworkStatsCollector {
  DateTime? _startTime;
  int _bytesSent = 0;
  int _bytesReceived = 0;
  int _bytesSentToday = 0;
  int _bytesReceivedToday = 0;
  int _messagesSent = 0;
  int _messagesReceived = 0;
  int _dhtBytes = 0;
  int _relayBytes = 0;
  int _messagesRelayed = 0;
  DateTime? _lastDayReset;

  // Peer history (sampled periodically)
  final List<PeerHealthEntry> _peerHistory = [];
  static const int _maxHistoryEntries = 720; // 30 days * 24h

  void markStarted() {
    _startTime = DateTime.now();
    _lastDayReset = DateTime.now();
  }

  Duration get uptime => _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;

  void addBytesSent(int bytes) {
    _bytesSent += bytes;
    _bytesSentToday += bytes;
  }

  void addBytesReceived(int bytes) {
    _bytesReceived += bytes;
    _bytesReceivedToday += bytes;
  }

  void addMessageSent() => _messagesSent++;
  void addMessageReceived() => _messagesReceived++;
  void addDhtBytes(int bytes) => _dhtBytes += bytes;
  void addRelayBytes(int bytes) {
    _relayBytes += bytes;
    // Count relay operations (each relay forward call = one relay event).
    // Note: a large message may be chunked into multiple relay ops, but
    // each onRelayBytes call corresponds to one relay envelope delivery.
    _messagesRelayed++;
  }

  /// Increment relay counter without adding bytes (for relay-only counting).
  void addRelayEvent() => _messagesRelayed++;

  /// Call periodically to record peer count history.
  void recordPeerCount(int count) {
    _peerHistory.add(PeerHealthEntry(timestamp: DateTime.now(), peerCount: count));
    if (_peerHistory.length > _maxHistoryEntries) {
      _peerHistory.removeAt(0);
    }
  }

  /// Reset daily counters if calendar date changed (day, month, or year).
  void _checkDayReset() {
    final now = DateTime.now();
    if (_lastDayReset == null ||
        now.day != _lastDayReset!.day ||
        now.month != _lastDayReset!.month ||
        now.year != _lastDayReset!.year) {
      _bytesSentToday = 0;
      _bytesReceivedToday = 0;
      _lastDayReset = now;
    }
  }

  /// Build full NetworkStats snapshot from collector + live components.
  /// [confirmedPeerCount] is the number of peers with a confirmed direct
  /// connection (e.g. received a PONG or DELIVERY_RECEIPT directly), as
  /// opposed to merely known DHT entries.
  NetworkStats collect({
    required RoutingTable routingTable,
    required MailboxStore mailboxStore,
    required NatTraversal natTraversal,
    required Map<String, Duration> rttMap,
    required bool isRunning,
    String? profileDir,
    int? confirmedPeerCount,
  }) {
    _checkDayReset();

    final now = DateTime.now();
    final activeCutoff = now.subtract(const Duration(seconds: 120));

    // Active peers = seen within last 120 seconds
    final allPeers = routingTable.allPeers;
    final activePeers = allPeers.where((p) => p.lastSeen.isAfter(activeCutoff)).toList();

    // K-bucket stats (only non-empty buckets)
    final bucketStats = <KBucketStats>[];
    for (var i = 0; i < routingTable.buckets.length; i++) {
      final count = routingTable.buckets[i].peers.length;
      if (count > 0) {
        bucketStats.add(KBucketStats(index: i, peerCount: count));
      }
    }

    // Latency stats
    final latencies = <PeerLatencyEntry>[];
    var totalLatency = 0.0;
    var minLat = double.infinity;
    var maxLat = 0.0;

    for (final entry in rttMap.entries) {
      final ms = entry.value.inMicroseconds / 1000.0;
      final peer = allPeers.cast<PeerInfo?>().firstWhere(
        (p) => p!.nodeIdHex == entry.key,
        orElse: () => null,
      );
      latencies.add(PeerLatencyEntry(
        nodeIdHex: entry.key,
        latencyMs: ms,
        lastSeen: peer?.lastSeen ?? now,
      ));
      totalLatency += ms;
      if (ms < minLat) minLat = ms;
      if (ms > maxLat) maxLat = ms;
    }

    final avgLat = latencies.isNotEmpty ? totalLatency / latencies.length : 0.0;

    // Fragment storage size: measure actual stored bytes from MailboxStore
    final storageBytes = mailboxStore.totalStoredBytes;

    // Direct connections: peers with confirmed RTT (actual bidirectional contact),
    // NOT just DHT entries. Falls back to rttMap size if no explicit count.
    final directConns = confirmedPeerCount ?? rttMap.length;

    // NAT-Wizard signals (§27.9.1): read enum-names from NatTraversal, convert
    // back to enums. Router-info JSON → class. Defaults apply if unset.
    final upnpStatus = NetworkStats._parseUpnpStatus(natTraversal.upnpStatusName);
    final pcpStatus = NetworkStats._parsePcpStatus(natTraversal.pcpStatusName);
    final routerInfoJson = natTraversal.upnpRouterInfoJson;
    final upnpRouterInfo = routerInfoJson == null
        ? null
        : UpnpRouterInfo.fromJson(routerInfoJson);

    return NetworkStats(
      activePeerCount: activePeers.length,
      totalKnownPeers: allPeers.length,
      natType: natTraversal.natType.name,
      publicIp: natTraversal.publicIp,
      publicPort: natTraversal.publicPort,
      uptime: uptime,
      isRunning: isRunning,
      peerHistory: List.unmodifiable(_peerHistory),
      bytesSentTotal: _bytesSent,
      bytesReceivedTotal: _bytesReceived,
      bytesSentToday: _bytesSentToday,
      bytesReceivedToday: _bytesReceivedToday,
      messagesSent: _messagesSent,
      messagesReceived: _messagesReceived,
      dhtMaintenanceBytes: _dhtBytes,
      relayBytes: _relayBytes,
      fragmentsStored: mailboxStore.fragmentCount,
      messagesRelayed: _messagesRelayed,
      relayDataVolume: _relayBytes,
      storageUsedBytes: storageBytes,
      directConnections: directConns,
      routingTableSize: allPeers.length,
      kBucketStats: bucketStats,
      avgLatencyMs: avgLat,
      minLatencyMs: latencies.isNotEmpty && minLat.isFinite ? minLat : 0,
      maxLatencyMs: latencies.isNotEmpty ? maxLat : 0,
      peerLatencies: latencies,
      dbSizeBytes: _measureDbSize(profileDir),
      upnpStatus: upnpStatus,
      pcpStatus: pcpStatus,
      upnpRouterInfo: upnpRouterInfo,
    );
  }

  /// Measure total size of encrypted database files in profile dir.
  static int _measureDbSize(String? profileDir) {
    if (profileDir == null) return 0;
    try {
      var total = 0;
      final dir = Directory(profileDir);
      if (!dir.existsSync()) return 0;
      for (final entity in dir.listSync()) {
        if (entity is File && (entity.path.endsWith('.enc') || entity.path.endsWith('.json'))) {
          total += entity.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
