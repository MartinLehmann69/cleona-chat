import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/network/clogger.dart';

/// Auto-discovery of CalDAV servers on the local network via mDNS/DNS-SD.
///
/// Sends multicast DNS queries for `_caldav._tcp.local` and
/// `_caldavs._tcp.local`, collects responses for [timeout] duration,
/// and returns a list of discovered server endpoints.
///
/// mDNS may not work on all platforms (e.g. Android restricts multicast
/// without a Wi-Fi multicast lock). Callers should treat an empty result
/// as "discovery unavailable" rather than "no servers exist".
class CalDAVDiscovery {
  static final CLogger _log = CLogger.get('caldav-discovery');

  // -- mDNS constants -------------------------------------------------------
  static final InternetAddress _mDnsIPv4 =
      InternetAddress('224.0.0.251');
  static const int _mDnsPort = 5353;

  // DNS record types
  static const int _typeA = 1;
  static const int _typeAAAA = 28;
  static const int _typePTR = 12;
  static const int _typeSRV = 33;
  static const int _typeTXT = 16;

  // DNS-SD service types we query for
  static const String _caldavService = '_caldav._tcp.local';
  static const String _caldavsService = '_caldavs._tcp.local';

  /// Discover CalDAV servers via mDNS. Returns discovered servers within
  /// [timeout] duration. Returns empty list on any error (graceful).
  static Future<List<DiscoveredCalDAVServer>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0, // ephemeral port
        reuseAddress: true,
        reusePort: false,
      );
    } catch (e) {
      _log.info('mDNS: cannot bind UDP socket, skipping discovery: $e');
      return [];
    }

    try {
      // Join multicast group. This may fail on platforms that restrict
      // multicast (Android without WifiManager.MulticastLock, some Docker
      // containers, etc.).
      try {
        socket.joinMulticast(_mDnsIPv4);
      } catch (e) {
        _log.info('mDNS: cannot join multicast group, skipping: $e');
        socket.close();
        return [];
      }

      // Accumulate parsed records across all response packets.
      final ptrInstances = <String, bool>{}; // instance name -> secure?
      final srvRecords = <String, _SrvRecord>{}; // instance -> SRV
      final txtRecords = <String, Map<String, String>>{}; // instance -> kv
      final hostAddresses = <String, String>{}; // hostname -> IP

      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket!.receive();
        if (dg == null) return;
        try {
          _parseResponse(
            dg.data,
            ptrInstances,
            srvRecords,
            txtRecords,
            hostAddresses,
          );
        } catch (e) {
          _log.debug('mDNS: failed to parse response: $e');
        }
      });

      // Send queries for both service types.
      final q1 = _buildQuery(_caldavService);
      final q2 = _buildQuery(_caldavsService);
      socket.send(q1, _mDnsIPv4, _mDnsPort);
      socket.send(q2, _mDnsIPv4, _mDnsPort);

      // Re-send once after 1s for reliability (mDNS uses UDP, packets may
      // be lost).
      Future<void>.delayed(const Duration(seconds: 1)).then((_) {
        try {
          socket!.send(q1, _mDnsIPv4, _mDnsPort);
          socket.send(q2, _mDnsIPv4, _mDnsPort);
        } catch (_) {
          // Socket may already be closed if timeout < 1s.
        }
      });

      // Wait for the timeout, then assemble results.
      await Future<void>.delayed(timeout);
      await sub.cancel();
      socket.close();

      final servers = _assembleServers(
        ptrInstances,
        srvRecords,
        txtRecords,
        hostAddresses,
      );
      if (servers.isNotEmpty) {
        _log.info('mDNS: discovered ${servers.length} CalDAV server(s)');
      } else {
        _log.debug('mDNS: no CalDAV servers discovered');
      }
      return servers;
    } catch (e) {
      _log.info('mDNS: discovery failed: $e');
      try {
        socket.close();
      } catch (_) {}
      return [];
    }
  }

  // --------------------------------------------------------------------------
  // DNS packet construction
  // --------------------------------------------------------------------------

  /// Build a minimal mDNS query packet asking for PTR records of [service].
  static Uint8List _buildQuery(String service) {
    final builder = BytesBuilder(copy: false);

    // -- Header (12 bytes) ---------------------------------------------------
    builder.add([0x00, 0x00]); // Transaction ID (0 for mDNS)
    builder.add([0x00, 0x00]); // Flags: standard query
    builder.add([0x00, 0x01]); // QDCOUNT = 1
    builder.add([0x00, 0x00]); // ANCOUNT = 0
    builder.add([0x00, 0x00]); // NSCOUNT = 0
    builder.add([0x00, 0x00]); // ARCOUNT = 0

    // -- Question section ----------------------------------------------------
    _writeDnsName(builder, service);
    builder.add([0x00, _typePTR]); // QTYPE = PTR
    builder.add([0x80, 0x01]); // QCLASS = IN, unicast-response bit set

    return builder.toBytes();
  }

  /// Encode a dotted DNS name into label-length-prefixed wire format.
  static void _writeDnsName(BytesBuilder builder, String name) {
    final parts = name.split('.');
    for (final part in parts) {
      final encoded = part.codeUnits; // ASCII is fine for service names
      builder.addByte(encoded.length);
      builder.add(encoded);
    }
    builder.addByte(0); // root label
  }

  // --------------------------------------------------------------------------
  // DNS response parsing
  // --------------------------------------------------------------------------

  /// Parse a DNS response packet and populate the record maps.
  static void _parseResponse(
    Uint8List data,
    Map<String, bool> ptrInstances,
    Map<String, _SrvRecord> srvRecords,
    Map<String, Map<String, String>> txtRecords,
    Map<String, String> hostAddresses,
  ) {
    if (data.length < 12) return;

    final flags = (data[2] << 8) | data[3];
    // Bit 15 (QR) must be 1 for a response.
    if ((flags & 0x8000) == 0) return;

    final qdCount = (data[4] << 8) | data[5];
    final anCount = (data[6] << 8) | data[7];
    final nsCount = (data[8] << 8) | data[9];
    final arCount = (data[10] << 8) | data[11];

    var offset = 12;

    // Skip question section.
    for (var i = 0; i < qdCount; i++) {
      final r = _skipDnsName(data, offset);
      if (r < 0) return;
      offset = r + 4; // skip QTYPE (2) + QCLASS (2)
      if (offset > data.length) return;
    }

    // Parse answer + authority + additional sections (all share the same
    // resource-record format).
    final totalRecords = anCount + nsCount + arCount;
    for (var i = 0; i < totalRecords; i++) {
      if (offset >= data.length) break;

      final nameResult = _readDnsName(data, offset);
      if (nameResult == null) break;
      final rrName = nameResult.name;
      offset = nameResult.nextOffset;

      if (offset + 10 > data.length) break;

      final rrType = (data[offset] << 8) | data[offset + 1];
      // rrClass at offset+2..+3 (skip)
      // TTL at offset+4..+7 (skip)
      final rdLength = (data[offset + 8] << 8) | data[offset + 9];
      offset += 10;

      if (offset + rdLength > data.length) break;
      final rdEnd = offset + rdLength;

      switch (rrType) {
        case _typePTR:
          final target = _readDnsName(data, offset);
          if (target != null) {
            final instanceName = target.name;
            final secure = rrName.contains('_caldavs._tcp');
            ptrInstances[instanceName] = secure;
          }
          break;

        case _typeSRV:
          if (rdLength >= 6) {
            final priority = (data[offset] << 8) | data[offset + 1];
            final weight = (data[offset + 2] << 8) | data[offset + 3];
            final port = (data[offset + 4] << 8) | data[offset + 5];
            final targetName = _readDnsName(data, offset + 6);
            if (targetName != null) {
              srvRecords[rrName] = _SrvRecord(
                priority: priority,
                weight: weight,
                port: port,
                target: targetName.name,
              );
            }
          }
          break;

        case _typeTXT:
          final kv = _parseTxtRecord(data, offset, rdLength);
          if (kv.isNotEmpty) {
            txtRecords[rrName] = kv;
          }
          break;

        case _typeA:
          if (rdLength == 4) {
            final ip =
                '${data[offset]}.${data[offset + 1]}.${data[offset + 2]}.${data[offset + 3]}';
            hostAddresses[rrName] = ip;
          }
          break;

        case _typeAAAA:
          if (rdLength == 16) {
            final groups = <String>[];
            for (var g = 0; g < 16; g += 2) {
              groups.add(
                ((data[offset + g] << 8) | data[offset + g + 1])
                    .toRadixString(16),
              );
            }
            hostAddresses[rrName] = groups.join(':');
          }
          break;
      }

      offset = rdEnd;
    }
  }

  /// Parse a TXT resource-record RDATA section. TXT records consist of one or
  /// more length-prefixed strings. We look for `key=value` pairs.
  static Map<String, String> _parseTxtRecord(
    Uint8List data,
    int offset,
    int rdLength,
  ) {
    final kv = <String, String>{};
    final end = offset + rdLength;
    while (offset < end) {
      final len = data[offset];
      offset += 1;
      if (offset + len > end) break;
      final str = String.fromCharCodes(data, offset, offset + len);
      offset += len;
      final eq = str.indexOf('=');
      if (eq > 0) {
        kv[str.substring(0, eq).toLowerCase()] = str.substring(eq + 1);
      }
    }
    return kv;
  }

  /// Read a DNS name starting at [offset], handling label-length encoding and
  /// pointer compression. Returns null on malformed data.
  static _DnsNameResult? _readDnsName(Uint8List data, int offset) {
    final parts = <String>[];
    var pos = offset;
    int? jumpedFrom; // first byte after the pointer (for nextOffset)
    var jumps = 0;
    const maxJumps = 10; // prevent infinite loops on malformed packets

    while (pos < data.length) {
      final len = data[pos];

      if (len == 0) {
        // Root label — end of name.
        pos += 1;
        break;
      }

      if ((len & 0xC0) == 0xC0) {
        // Pointer compression: next byte forms a 14-bit offset into the
        // packet.
        if (pos + 1 >= data.length) return null;
        jumpedFrom ??= pos + 2;
        jumps += 1;
        if (jumps > maxJumps) return null;
        pos = ((len & 0x3F) << 8) | data[pos + 1];
        continue;
      }

      // Normal label.
      pos += 1;
      if (pos + len > data.length) return null;
      parts.add(String.fromCharCodes(data, pos, pos + len));
      pos += len;
    }

    return _DnsNameResult(
      name: parts.join('.'),
      nextOffset: jumpedFrom ?? pos,
    );
  }

  /// Skip over a DNS name without decoding it. Returns the offset after the
  /// name, or -1 on error.
  static int _skipDnsName(Uint8List data, int offset) {
    var pos = offset;
    while (pos < data.length) {
      final len = data[pos];
      if (len == 0) return pos + 1;
      if ((len & 0xC0) == 0xC0) return pos + 2; // pointer: 2 bytes
      pos += 1 + len;
    }
    return -1;
  }

  // --------------------------------------------------------------------------
  // Server assembly
  // --------------------------------------------------------------------------

  /// Combine the collected DNS records into a list of CalDAV servers.
  static List<DiscoveredCalDAVServer> _assembleServers(
    Map<String, bool> ptrInstances,
    Map<String, _SrvRecord> srvRecords,
    Map<String, Map<String, String>> txtRecords,
    Map<String, String> hostAddresses,
  ) {
    final servers = <DiscoveredCalDAVServer>[];

    for (final entry in ptrInstances.entries) {
      final instanceName = entry.key;
      final secure = entry.value;

      final srv = srvRecords[instanceName];
      if (srv == null) continue; // Need at least the SRV record.

      // Resolve hostname to IP via A/AAAA record. If we didn't receive an
      // address record, fall back to the SRV target hostname (the caller
      // can try DNS resolution themselves).
      final host = hostAddresses[srv.target] ?? _stripTrailingDot(srv.target);

      // Extract path from TXT records if available.
      final txt = txtRecords[instanceName];
      String? path = txt?['path'];

      // Some servers use 'txtvers' and 'path' keys, others use different
      // conventions. Normalize the path.
      if (path != null && path.isNotEmpty && !path.startsWith('/')) {
        path = '/$path';
      }

      // Infer default paths for common self-hosted servers if no path was
      // advertised.
      if (path == null || path.isEmpty) {
        path = _guessPathFromName(instanceName, host);
      }

      // Derive a human-readable name from the instance name. mDNS instance
      // names are formatted as "Service Name._caldav._tcp.local".
      final name = _extractServiceName(instanceName);

      servers.add(DiscoveredCalDAVServer(
        name: name,
        host: host,
        port: srv.port,
        secure: secure,
        path: path,
      ));
    }

    // Sort by name for deterministic output.
    servers.sort((a, b) => a.name.compareTo(b.name));
    return servers;
  }

  /// Strip trailing dot from a fully-qualified DNS name.
  static String _stripTrailingDot(String name) {
    if (name.endsWith('.')) return name.substring(0, name.length - 1);
    return name;
  }

  /// Extract a human-readable service name from an mDNS instance name like
  /// "Nextcloud CalDAV._caldav._tcp.local".
  static String _extractServiceName(String instanceName) {
    // Instance names are: <service-name>.<service-type>.local
    // The service type starts with an underscore.
    final idx = instanceName.indexOf('._');
    if (idx > 0) return instanceName.substring(0, idx);
    return instanceName;
  }

  /// Guess the CalDAV path for common self-hosted servers based on service
  /// name or hostname patterns.
  static String? _guessPathFromName(String instanceName, String host) {
    final lower = instanceName.toLowerCase();
    final hostLower = host.toLowerCase();

    // Nextcloud / ownCloud
    if (lower.contains('nextcloud') || lower.contains('owncloud') ||
        hostLower.contains('nextcloud') || hostLower.contains('owncloud')) {
      return '/remote.php/dav';
    }

    // Synology CalDAV
    if (lower.contains('synology') || lower.contains('diskstation') ||
        hostLower.contains('synology') || hostLower.contains('diskstation')) {
      return '/caldav';
    }

    // Radicale
    if (lower.contains('radicale') || hostLower.contains('radicale')) {
      return '/';
    }

    // Baikal
    if (lower.contains('baikal') || hostLower.contains('baikal')) {
      return '/dav.php';
    }

    // DAViCal
    if (lower.contains('davical') || hostLower.contains('davical')) {
      return '/caldav.php';
    }

    return null;
  }
}

/// A CalDAV server discovered via mDNS/DNS-SD.
class DiscoveredCalDAVServer {
  /// Human-readable service name (e.g. "Nextcloud CalDAV").
  final String name;

  /// Resolved hostname or IP.
  final String host;

  /// Port number.
  final int port;

  /// Whether HTTPS (from `_caldavs._tcp`) or HTTP.
  final bool secure;

  /// Path from TXT record (e.g. "/remote.php/dav").
  final String? path;

  /// Full base URL for CalDAV configuration.
  String get url {
    final scheme = secure ? 'https' : 'http';
    final portSuffix =
        (secure && port == 443) || (!secure && port == 80) ? '' : ':$port';
    final pathPart = path ?? '/';
    return '$scheme://$host$portSuffix$pathPart';
  }

  DiscoveredCalDAVServer({
    required this.name,
    required this.host,
    required this.port,
    required this.secure,
    this.path,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'secure': secure,
        'url': url,
        if (path != null) 'path': path,
      };

  @override
  String toString() => 'DiscoveredCalDAVServer($name @ $url)';
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

class _SrvRecord {
  final int priority;
  final int weight;
  final int port;
  final String target;

  _SrvRecord({
    required this.priority,
    required this.weight,
    required this.port,
    required this.target,
  });
}

class _DnsNameResult {
  final String name;
  final int nextOffset;

  _DnsNameResult({required this.name, required this.nextOffset});
}
