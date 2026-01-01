// UPnP/IGD (Internet Gateway Device) port mapping client.
//
// Discovers IGD devices via SSDP multicast, then uses SOAP to
// request port mappings. No external dependencies — uses dart:io
// HttpClient for HTTP/SOAP and RegExp for XML parsing.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/nat_pmp.dart' show PortMappingResult;

// ── Constants ───────────────────────────────────────────────────────

/// SSDP multicast address and port.
const String ssdpMulticastAddress = '239.255.255.250';
const int ssdpPort = 1900;

/// SSDP M-SEARCH timeout.
const Duration ssdpTimeout = Duration(seconds: 3);

/// UPnP service types in priority order.
const List<String> igdServiceTypes = [
  'urn:schemas-upnp-org:service:WANIPConnection:2',
  'urn:schemas-upnp-org:service:WANIPConnection:1',
  'urn:schemas-upnp-org:service:WANPPPConnection:1',
];

/// SSDP search targets for IGD discovery.
const List<String> ssdpSearchTargets = [
  'urn:schemas-upnp-org:device:InternetGatewayDevice:2',
  'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
  'upnp:rootdevice',
];

/// UPnP SOAP error codes.
const int upnpErrorConflict = 718;
const int upnpErrorOnlyPermanentLease = 725;
const int upnpErrorNoSuchEntry = 714;

// ── Data Classes ────────────────────────────────────────────────────

/// Discovered IGD device with its control URL.
class IgdDevice {
  final String baseUrl;
  final String controlPath;
  final String serviceType;

  IgdDevice({
    required this.baseUrl,
    required this.controlPath,
    required this.serviceType,
  });

  /// Full URL for SOAP control requests.
  String get fullControlUrl {
    if (controlPath.startsWith('http')) return controlPath;
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final path = controlPath.startsWith('/') ? controlPath : '/$controlPath';
    return '$base$path';
  }

  @override
  String toString() => 'IgdDevice($serviceType, $fullControlUrl)';
}

// ── SSDP Discovery ──────────────────────────────────────────────────

/// Build an SSDP M-SEARCH request packet.
String buildMSearch(String searchTarget) {
  return 'M-SEARCH * HTTP/1.1\r\n'
      'HOST: $ssdpMulticastAddress:$ssdpPort\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 2\r\n'
      'ST: $searchTarget\r\n'
      '\r\n';
}

/// Parse the LOCATION header from an SSDP response.
String? parseSsdpLocation(String response) {
  final match = RegExp(r'LOCATION:\s*(.+)', caseSensitive: false)
      .firstMatch(response);
  return match?.group(1)?.trim();
}

/// Parse the ST (Search Target) header from an SSDP response.
String? parseSsdpSt(String response) {
  final match = RegExp(r'^ST:\s*(.+)', caseSensitive: false, multiLine: true)
      .firstMatch(response);
  return match?.group(1)?.trim();
}

// ── XML Parsing (RegExp, no XML library) ────────────────────────────

/// Extract the base URL from a device description URL.
/// e.g., "http://192.168.1.1:5000/rootDesc.xml" → "http://192.168.1.1:5000"
String extractBaseUrl(String locationUrl) {
  final uri = Uri.parse(locationUrl);
  return '${uri.scheme}://${uri.host}:${uri.port}';
}

/// Parse the device description XML to find WANIPConnection/WANPPPConnection
/// service control URLs.
///
/// Returns a list of (serviceType, controlUrl) pairs, sorted by priority.
List<({String serviceType, String controlUrl})> parseDeviceDescription(
    String xml) {
  final results = <({String serviceType, String controlUrl})>[];

  // Find all <service> blocks
  final serviceBlocks = RegExp(
    r'<service>(.*?)</service>',
    dotAll: true,
  ).allMatches(xml);

  for (final block in serviceBlocks) {
    final content = block.group(1) ?? '';
    final serviceType = _extractXmlValue(content, 'serviceType');
    final controlUrl = _extractXmlValue(content, 'controlURL');

    if (serviceType != null && controlUrl != null) {
      // Check if this is a WAN service we care about
      for (final target in igdServiceTypes) {
        if (serviceType.contains(target) || serviceType == target) {
          results.add((serviceType: target, controlUrl: controlUrl));
          break;
        }
      }
    }
  }

  // Sort by priority (WANIPConnection:2 > :1 > WANPPPConnection:1)
  results.sort((a, b) {
    final ai = igdServiceTypes.indexOf(a.serviceType);
    final bi = igdServiceTypes.indexOf(b.serviceType);
    return ai.compareTo(bi);
  });

  return results;
}

/// Extract a simple XML tag value using RegExp.
String? _extractXmlValue(String xml, String tag) {
  final match = RegExp('<$tag>([^<]*)</$tag>').firstMatch(xml);
  return match?.group(1)?.trim();
}

/// Parse `<manufacturer>`, `<modelName>`, `<modelNumber>`, `<friendlyName>`
/// from the top-level `<device>` element of a UPnP rootDesc.xml.
///
/// Same shape as [NatTraversal.upnpRouterInfoJson] — keys omitted when the
/// tag is absent. Returns null on any parse failure (malformed XML, no
/// top-level device, empty result). Never throws.
///
/// Used by the NAT-Troubleshooting-Wizard router-DB matcher (§27.9.2 Step 2).
Map<String, dynamic>? parseRouterInfo(String xml) {
  try {
    // Find the outer <device> block only. Nested devices (e.g. WANDevice) also
    // carry manufacturer tags — those would mask the real router identity.
    // We take the first <device>...</device> and within that, the first
    // occurrence of each tag BEFORE any nested <deviceList>.
    final deviceMatch = RegExp(r'<device>(.*?)</device>', dotAll: true)
        .firstMatch(xml);
    if (deviceMatch == null) return null;

    var content = deviceMatch.group(1) ?? '';
    // Strip nested deviceList blocks so we only see the outer device's fields.
    content = content.replaceAll(
      RegExp(r'<deviceList>.*?</deviceList>', dotAll: true),
      '',
    );

    final info = <String, dynamic>{};
    final manufacturer = _extractXmlValue(content, 'manufacturer');
    final modelName = _extractXmlValue(content, 'modelName');
    final modelNumber = _extractXmlValue(content, 'modelNumber');
    final friendlyName = _extractXmlValue(content, 'friendlyName');

    if (manufacturer != null && manufacturer.isNotEmpty) {
      info['manufacturer'] = manufacturer;
    }
    if (modelName != null && modelName.isNotEmpty) {
      info['modelName'] = modelName;
    }
    if (modelNumber != null && modelNumber.isNotEmpty) {
      info['modelNumber'] = modelNumber;
    }
    if (friendlyName != null && friendlyName.isNotEmpty) {
      info['friendlyName'] = friendlyName;
    }

    if (info.isEmpty) return null;
    return info;
  } catch (_) {
    return null;
  }
}

// ── SOAP Request/Response ───────────────────────────────────────────

/// Build a SOAP AddPortMapping request body.
String buildAddPortMappingSoap({
  required String serviceType,
  required int externalPort,
  required String protocol,
  required int internalPort,
  required String internalClient,
  required String description,
  int leaseDuration = 7200,
}) {
  return '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body>'
      '<u:AddPortMapping xmlns:u="$serviceType">'
      '<NewRemoteHost></NewRemoteHost>'
      '<NewExternalPort>$externalPort</NewExternalPort>'
      '<NewProtocol>$protocol</NewProtocol>'
      '<NewInternalPort>$internalPort</NewInternalPort>'
      '<NewInternalClient>$internalClient</NewInternalClient>'
      '<NewEnabled>1</NewEnabled>'
      '<NewPortMappingDescription>$description</NewPortMappingDescription>'
      '<NewLeaseDuration>$leaseDuration</NewLeaseDuration>'
      '</u:AddPortMapping>'
      '</s:Body>'
      '</s:Envelope>';
}

/// Build a SOAP DeletePortMapping request body.
String buildDeletePortMappingSoap({
  required String serviceType,
  required int externalPort,
  required String protocol,
}) {
  return '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body>'
      '<u:DeletePortMapping xmlns:u="$serviceType">'
      '<NewRemoteHost></NewRemoteHost>'
      '<NewExternalPort>$externalPort</NewExternalPort>'
      '<NewProtocol>$protocol</NewProtocol>'
      '</u:DeletePortMapping>'
      '</s:Body>'
      '</s:Envelope>';
}

/// Build a SOAP GetExternalIPAddress request body.
String buildGetExternalIpSoap({required String serviceType}) {
  return '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body>'
      '<u:GetExternalIPAddress xmlns:u="$serviceType">'
      '</u:GetExternalIPAddress>'
      '</s:Body>'
      '</s:Envelope>';
}

/// Parse the external IP from a GetExternalIPAddress SOAP response.
String? parseExternalIpResponse(String xml) {
  return _extractXmlValue(xml, 'NewExternalIPAddress');
}

/// Parse a SOAP fault/error response. Returns error code or null.
int? parseSoapErrorCode(String xml) {
  final code = _extractXmlValue(xml, 'errorCode');
  if (code != null) return int.tryParse(code);
  return null;
}

/// Parse a SOAP fault error description.
String? parseSoapErrorDescription(String xml) {
  return _extractXmlValue(xml, 'errorDescription');
}

// ── UPnP IGD Client ─────────────────────────────────────────────────

/// UPnP/IGD client for port mapping.
class UpnpIgdClient {
  final CLogger _log;

  /// Devices found by the last discoverDevices() call.
  List<IgdDevice> _lastDevices = [];
  List<IgdDevice> get lastDiscoveredDevices => _lastDevices;

  /// Parsed rootDesc info (manufacturer/modelName/modelNumber/friendlyName)
  /// from the last successful device-description fetch. Same shape as
  /// `NatTraversal.upnpRouterInfoJson`. Null if no descriptor parsed.
  ///
  /// Consumed by [PortMapper] → `NatTraversal.setUpnpRouterInfoJson(...)` so
  /// the NAT-Troubleshooting-Wizard can match a router-DB entry (§27.9.2).
  Map<String, dynamic>? _lastRouterInfoJson;
  Map<String, dynamic>? get lastRouterInfoJson => _lastRouterInfoJson;

  UpnpIgdClient({String? profileDir})
      : _log = CLogger.get('upnp', profileDir: profileDir);

  /// Discover IGD devices via SSDP multicast + unicast gateway probes.
  ///
  /// SSDP multicast only reaches the local subnet. If the IGD device (e.g.
  /// Fritzbox) is behind a firewall/router (OPNsense) in a different subnet,
  /// multicast won't reach it. As fallback, we also send M-SEARCH unicast
  /// to the default gateway AND probe known gateway IPs directly for their
  /// UPnP description (standard port 49000).
  Future<List<IgdDevice>> discoverDevices({
    Duration timeout = ssdpTimeout,
  }) async {
    final devices = <IgdDevice>[];
    final seenLocations = <String>{};

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      final multicastAddr = InternetAddress(ssdpMulticastAddress);

      // 1. SSDP multicast (works if IGD is on same subnet)
      for (final st in ssdpSearchTargets) {
        final request = buildMSearch(st);
        socket.send(utf8.encode(request), multicastAddr, ssdpPort);
      }

      // 2. SSDP unicast to default gateway + upstream gateways
      // Covers cases where IGD is behind a router (e.g. Fritzbox behind OPNsense)
      final gatewayIps = await _detectGatewayIps();
      for (final gwIp in gatewayIps) {
        try {
          final gwAddr = InternetAddress(gwIp);
          for (final st in ssdpSearchTargets) {
            socket.send(utf8.encode(buildMSearch(st)), gwAddr, ssdpPort);
          }
        } catch (_) {}
      }

      // Collect responses
      final completer = Completer<void>();
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      final sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket!.receive();
          if (datagram != null) {
            final response = utf8.decode(datagram.data, allowMalformed: true);
            final location = parseSsdpLocation(response);
            if (location != null && seenLocations.add(location)) {
              _log.debug('SSDP response: $location');
            }
          }
        }
      });

      await completer.future;
      timer.cancel();
      await sub.cancel();
    } catch (e) {
      _log.debug('SSDP discovery error: $e');
    } finally {
      socket?.close();
    }

    // 3. Direct probe: if SSDP found nothing, try well-known UPnP description
    // URLs on gateway IPs (port 49000 is standard for Fritzbox/many routers)
    if (seenLocations.isEmpty) {
      final gatewayIps = await _detectGatewayIps();
      for (final gwIp in gatewayIps) {
        final url = 'http://$gwIp:49000/igddesc.xml';
        try {
          final device = await _fetchDeviceDescription(url);
          if (device != null) {
            _log.info('IGD found via direct probe: $gwIp');
            devices.add(device);
            _lastDevices = devices;
            return devices; // Found one — no need to continue
          }
        } catch (_) {}
      }
    }

    // Fetch device descriptions and find control URLs.
    // Cache result so callers can reuse without a second SSDP scan.
    for (final location in seenLocations) {
      try {
        final device = await _fetchDeviceDescription(location);
        if (device != null) {
          devices.add(device);
        }
      } catch (e) {
        _log.debug('Failed to fetch device description from $location: $e');
      }
    }

    _lastDevices = devices;
    return devices;
  }

  /// Detect gateway IPs: default gateway + traceroute to find upstream routers.
  /// Returns the default gateway and any router hops (e.g. Fritzbox behind OPNsense).
  static Future<List<String>> _detectGatewayIps() async {
    final ips = <String>[];
    try {
      // Default gateway from `ip route`
      final result = await Process.run('ip', ['route', 'show', 'default']);
      final match = RegExp(r'via\s+([\d.]+)').firstMatch(result.stdout as String);
      if (match != null) ips.add(match.group(1)!);

      // First 3 hops via tracepath to find upstream routers (e.g. Fritzbox behind OPNsense).
      // tracepath is available on most Linux systems (iproute2 package).
      final tr = await Process.run('tracepath', ['-n', '-m', '3', '8.8.8.8'],
          stdoutEncoding: const SystemEncoding())
          .timeout(const Duration(seconds: 5), onTimeout: () => ProcessResult(0, 1, '', ''));
      for (final line in (tr.stdout as String).split('\n')) {
        final hopMatch = RegExp(r'^\s*\d+:\s+([\d.]+)').firstMatch(line);
        if (hopMatch != null) {
          final hop = hopMatch.group(1)!;
          // Only add private IPs (routers), not the public IP itself
          if (!ips.contains(hop) && _isPrivateIpStatic(hop)) ips.add(hop);
        }
      }
    } catch (_) {}
    return ips;
  }

  static bool _isPrivateIpStatic(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]) ?? 0;
    final b = int.tryParse(parts[1]) ?? 0;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  /// Request a port mapping via UPnP/IGD.
  ///
  /// [internalPort] - local UDP port.
  /// [externalPort] - requested external port (0 = same as internal).
  /// [leaseDuration] - lease time in seconds (0 = permanent).
  /// [description] - mapping description (default "Cleona").
  /// [internalClient] - internal IP (auto-detected if null).
  ///
  /// Returns a [PortMappingResult] on success, null on failure.
  Future<PortMappingResult?> requestMapping({
    required int internalPort,
    int externalPort = 0,
    int leaseDuration = 7200,
    String description = 'Cleona',
    String? internalClient,
  }) async {
    // Discover IGD
    final devices = await discoverDevices();
    if (devices.isEmpty) {
      _log.debug('No IGD devices found');
      return null;
    }

    // Detect own IP if not provided
    final myIp = internalClient ?? await _detectInternalIp();
    if (myIp == null) {
      _log.debug('Cannot detect internal IP');
      return null;
    }

    final extPort = externalPort > 0 ? externalPort : internalPort;

    // Try each device
    for (final device in devices) {
      final result = await _tryMapping(
        device: device,
        internalPort: internalPort,
        externalPort: extPort,
        leaseDuration: leaseDuration,
        description: description,
        internalClient: myIp,
      );
      if (result != null) return result;
    }

    return null;
  }

  /// Delete a port mapping.
  Future<bool> deleteMapping({
    required int externalPort,
    String protocol = 'UDP',
  }) async {
    final devices = await discoverDevices();
    for (final device in devices) {
      try {
        final soap = buildDeletePortMappingSoap(
          serviceType: device.serviceType,
          externalPort: externalPort,
          protocol: protocol,
        );

        final response = await _soapRequest(
          device.fullControlUrl,
          device.serviceType,
          'DeletePortMapping',
          soap,
        );

        if (response != null && !response.contains('errorCode')) {
          _log.info('UPnP mapping deleted: port $externalPort');
          return true;
        }
      } catch (e) {
        _log.debug('DeletePortMapping error on ${device.fullControlUrl}: $e');
      }
    }
    return false;
  }

  /// Query the external IP via UPnP/IGD.
  /// Optionally pass [knownDevices] to skip rediscovery.
  Future<String?> getExternalIp({List<IgdDevice>? knownDevices}) async {
    final devices = knownDevices ?? await discoverDevices();
    for (final device in devices) {
      try {
        final soap = buildGetExternalIpSoap(serviceType: device.serviceType);
        final response = await _soapRequest(
          device.fullControlUrl,
          device.serviceType,
          'GetExternalIPAddress',
          soap,
        );

        if (response != null) {
          final ip = parseExternalIpResponse(response);
          if (ip != null && ip.isNotEmpty) return ip;
        }
      } catch (e) {
        _log.debug('GetExternalIPAddress error: $e');
      }
    }
    return null;
  }

  // ── Internal ──────────────────────────────────────────────────────

  Future<IgdDevice?> _fetchDeviceDescription(String locationUrl) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse(locationUrl);
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));
      final body = await response.transform(utf8.decoder).join();

      // Parse router identification (NAT-Wizard §27.9.2) before services.
      // Even if no matching service is found, the descriptor identifies the
      // router — useful for the wizard UI ("UPnP disabled on FRITZ!Box 7590").
      final routerInfo = parseRouterInfo(body);
      if (routerInfo != null) {
        _lastRouterInfoJson = routerInfo;
        _log.debug('Router identified via rootDesc: $routerInfo');
      }

      final services = parseDeviceDescription(body);
      if (services.isEmpty) return null;

      final best = services.first;
      final baseUrl = extractBaseUrl(locationUrl);

      return IgdDevice(
        baseUrl: baseUrl,
        controlPath: best.controlUrl,
        serviceType: best.serviceType,
      );
    } catch (e) {
      _log.debug('Device description fetch error: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<PortMappingResult?> _tryMapping({
    required IgdDevice device,
    required int internalPort,
    required int externalPort,
    required int leaseDuration,
    required String description,
    required String internalClient,
  }) async {
    try {
      final soap = buildAddPortMappingSoap(
        serviceType: device.serviceType,
        externalPort: externalPort,
        protocol: 'UDP',
        internalPort: internalPort,
        internalClient: internalClient,
        description: description,
        leaseDuration: leaseDuration,
      );

      final response = await _soapRequest(
        device.fullControlUrl,
        device.serviceType,
        'AddPortMapping',
        soap,
      );

      if (response == null) return null;

      // Check for errors
      final errorCode = parseSoapErrorCode(response);
      if (errorCode != null) {
        if (errorCode == upnpErrorConflict) {
          // Conflict: delete existing mapping and retry
          _log.debug('UPnP conflict on port $externalPort — deleting and retrying');
          final deleteSoap = buildDeletePortMappingSoap(
            serviceType: device.serviceType,
            externalPort: externalPort,
            protocol: 'UDP',
          );
          await _soapRequest(
            device.fullControlUrl,
            device.serviceType,
            'DeletePortMapping',
            deleteSoap,
          );
          // Retry
          final retryResponse = await _soapRequest(
            device.fullControlUrl,
            device.serviceType,
            'AddPortMapping',
            soap,
          );
          if (retryResponse == null) return null;
          final retryError = parseSoapErrorCode(retryResponse);
          if (retryError != null) {
            _log.debug('UPnP retry failed: error $retryError');
            return null;
          }
        } else if (errorCode == upnpErrorOnlyPermanentLease) {
          // Router only supports permanent leases: retry with lease=0
          _log.debug('UPnP only permanent leases — retrying with lease=0');
          final permSoap = buildAddPortMappingSoap(
            serviceType: device.serviceType,
            externalPort: externalPort,
            protocol: 'UDP',
            internalPort: internalPort,
            internalClient: internalClient,
            description: description,
            leaseDuration: 0,
          );
          final permResponse = await _soapRequest(
            device.fullControlUrl,
            device.serviceType,
            'AddPortMapping',
            permSoap,
          );
          if (permResponse == null) return null;
          final permError = parseSoapErrorCode(permResponse);
          if (permError != null) return null;
          // Permanent lease
          leaseDuration = 0;
        } else {
          final desc = parseSoapErrorDescription(response);
          _log.debug('UPnP AddPortMapping error: $errorCode ($desc)');
          return null;
        }
      }

      // Get external IP
      String externalIp = '0.0.0.0';
      final ipSoap = buildGetExternalIpSoap(serviceType: device.serviceType);
      final ipResponse = await _soapRequest(
        device.fullControlUrl,
        device.serviceType,
        'GetExternalIPAddress',
        ipSoap,
      );
      if (ipResponse != null) {
        final ip = parseExternalIpResponse(ipResponse);
        if (ip != null && ip.isNotEmpty) externalIp = ip;
      }

      _log.info('UPnP mapping: $externalIp:$externalPort '
          '→ $internalClient:$internalPort (lease=${leaseDuration}s)');

      return PortMappingResult(
        externalIp: externalIp,
        externalPort: externalPort,
        lifetimeSeconds: leaseDuration,
      );
    } catch (e) {
      _log.debug('UPnP AddPortMapping error: $e');
      return null;
    }
  }

  Future<String?> _soapRequest(
    String controlUrl,
    String serviceType,
    String action,
    String body,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse(controlUrl);
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      request.headers.set('SOAPAction', '"$serviceType#$action"');
      request.persistentConnection = false; // Fritzbox may close connection early
      request.headers.contentLength = utf8.encode(body).length;
      request.write(body);
      final response = await request.close().timeout(const Duration(seconds: 5));
      return response.transform(utf8.decoder).join();
    } catch (e) {
      _log.debug('SOAP request error ($action): $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _detectInternalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        if (iface.name == 'lo') continue;
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('10.') ||
              ip.startsWith('192.168.') ||
              _isClass172Private(ip)) {
            return ip;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isClass172Private(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }
}
