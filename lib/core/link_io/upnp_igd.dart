/// UPnP/IGD (Internet Gateway Device) — the second port mapping.
///
/// ── WHERE THIS FILE COMES FROM (S373) ──────────────────────────────────
///
/// Like `nat_pmp.dart` next to it: until the CUT of 31.08.2026 it stood as
/// `lib/core/network/upnp_igd.dart` in the V3 tree, fell with it, and the
/// owner approved bringing it back on 07.09.2026. SSDP, SOAP and
/// XML parts are taken over unchanged. Three things are changed, and
/// each has a reason that stands below at the relevant place:
///
///  1. Log sink instead of `CLogger` (directory convention, see `nat_pmp.dart`).
///  2. The gateway detection NO longer calls a subprocess as
///     precondition. The default route comes from [detectGatewayIp]
///     (`nat_pmp.dart`: `/proc/net/route`, otherwise heuristic), the
///     additional candidates from [UpnpIgdClient.gatewayCandidates] — there
///     the operating system tool is one of three sources and never the
///     prerequisite. `Process.run('ip', …)` does not exist on Windows and
///     not at all on iOS.
///  3. The search runs in TWO rounds instead of one (see
///     [UpnpIgdClient.discoverDevices]). The expensive part — the hop probe —
///     only runs if the cheap round found nothing.
///
/// ── TWO SEARCH PATHS, AND WHY BOTH ARE NEEDED ──────────────────────
///
/// SSDP multicast only reaches the own segment. If the IGD stands behind
/// a second router — in this project's test network a Fritzbox behind
/// an OPNsense —, the multicast never arrives there. That is why the same
/// `M-SEARCH` additionally goes as UNICAST to the detected gateways.
///
/// ── PACKET COUNT (working rule #5) ─────────────────────────────────────
///
/// Round 1: 3 multicast datagrams + 3 unicast to the default gateway = 6,
/// in one burst, then 3 s of listening. Round 2 ONLY runs if round 1
/// stayed empty; it costs 3 unicast per candidate with at most
/// [UpnpIgdClient.kMaxCandidates] = 8 candidates, i.e. **at most 24
/// datagrams**, plus — where a tool exists — up to 9 TTL-limited
/// probes that reach no host. Per device found after that: 1
/// HTTP GET (rootDesc) and 2 SOAP POSTs (`AddPortMapping`,
/// `GetExternalIPAddress`). No polling, no retry without cause.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/link_io/nat_pmp.dart'
    show PortMappingResult, detectGatewayIp, detectOwnPrivateIpv4;
import 'package:cleona/core/util/host_interfaces.dart';

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

/// The service that opens IPv6 pinholes (S391, task E4).
///
/// Source: UPnP Forum, "WANIPv6FirewallControl:1 Service, Standardized DCP
/// (SDCP), version 1.00, December 10, 2010", §2.1 "Service Type". It is
/// part of IGDv2 (V4.2 §7.3: "UPnP through IGDv2 `WANIPv6FirewallControl`").
///
/// ── NO OWN SSDP SEARCH TARGET, AND WHY ───────────────────────────
///
/// [ssdpSearchTargets] does NOT contain it. Every additional search target
/// costs per round one multicast datagram plus one per unicast target
/// (working rule 5), and it would find no device that the existing targets
/// do not already find: `upnp:rootdevice` answers EVERY root device
/// (UPnP Device Architecture 1.1 §1.3.3 "Search response": "Devices
/// respond if the ST header field of the M-SEARCH request is … upnp:root
/// device …"), and the IGDv2 root device, in whose
/// description the service stands, additionally answers to
/// `InternetGatewayDevice:2`. The service is therefore recognised where the
/// description is read anyway ([parseFirewallControlUrl] in
/// `_fetchDeviceDescription`) — the same discovery, zero packets more.
const String wanIpv6FirewallControlService =
    'urn:schemas-upnp-org:service:WANIPv6FirewallControl:1';

/// Error codes of the service — WANIPv6FirewallControl:1 §2.6.3.7, §2.6.4.7,
/// §2.6.5.7 (tables 2-12, 2-14, 2-16); 606 "Action not authorized" stands
/// in the same tables (UDA 1.1 reserves 606–612 for DeviceSecurity).
const int upnpFwErrorNotAuthorized = 606;
const int upnpFwErrorPinholeSpaceExhausted = 701;
const int upnpFwErrorFirewallDisabled = 702;
const int upnpFwErrorInboundPinholeNotAllowed = 703;
const int upnpFwErrorNoSuchEntry = 704;
const int upnpFwErrorProtocolNotSupported = 705;
const int upnpFwErrorInternalPortWildcardingNotAllowed = 706;
const int upnpFwErrorProtocolWildcardingNotAllowed = 707;
const int upnpFwErrorWildCardNotPermittedInSrcIp = 708;

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
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
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
  final match =
      RegExp(r'LOCATION:\s*(.+)', caseSensitive: false).firstMatch(response);
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
///
/// IPv6 (S391, task E4): `Uri.host` returns an IPv6 address WITHOUT
/// square brackets; without them `http://::1:49000` would no longer be a URL
/// (RFC 3986 §3.2.2: "IP-literal = "[" ( IPv6address / IPvFuture ) "]"").
String extractBaseUrl(String locationUrl) {
  final uri = Uri.parse(locationUrl);
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  return '${uri.scheme}://$host:${uri.port}';
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

/// The control URL of the service [wanIpv6FirewallControlService] from a
/// device description, or `null` (S391, task E4).
///
/// Separate from [parseDeviceDescription], because this service cannot do
/// port mapping and therefore must never stand in [igdServiceTypes] —
/// otherwise the IPv4 path would choose it as the "best" service and send
/// `AddPortMapping` to a service that does not know it.
String? parseFirewallControlUrl(String xml) {
  for (final block in RegExp(r'<service>(.*?)</service>', dotAll: true)
      .allMatches(xml)) {
    final content = block.group(1) ?? '';
    final kind = _extractXmlValue(content, 'serviceType');
    final url = _extractXmlValue(content, 'controlURL');
    if (kind == wanIpv6FirewallControlService && url != null && url.isNotEmpty) {
      return url;
    }
  }
  return null;
}

/// Extract a simple XML tag value using RegExp.
String? _extractXmlValue(String xml, String tag) {
  final match = RegExp('<$tag>([^<]*)</$tag>').firstMatch(xml);
  return match?.group(1)?.trim();
}

/// Parse `<manufacturer>`, `<modelName>`, `<modelNumber>`, `<friendlyName>`
/// from the top-level `<device>` element of a UPnP rootDesc.xml.
///
/// The same shape as `UpnpRouterInfo.toJson`
/// (`lib/core/platform/router_db.dart`) — keys are missing if the tag
/// is missing. Returns `null` on any parse error and never throws.
///
/// Consumer is the router matching of the NAT assistant (§27.9.2 step 2).
Map<String, dynamic>? parseRouterInfo(String xml) {
  try {
    // Find the outer <device> block only. Nested devices (e.g. WANDevice) also
    // carry manufacturer tags — those would mask the real router identity.
    // We take the first <device>...</device> and within that, the first
    // occurrence of each tag BEFORE any nested <deviceList>.
    final deviceMatch =
        RegExp(r'<device>(.*?)</device>', dotAll: true).firstMatch(xml);
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

/// Build a SOAP GetSpecificPortMappingEntry request body.
///
/// ── WHY THIS CALL IS NEEDED (S380, 10.09.2026) ─────────────
///
/// This module could only CREATE a port mapping. A router on
/// which automatic port forwarding is switched off — the normal case
/// when someone maintains their forwardings by hand —, refuses `AddPortMapping`
/// and HAS the mapping nonetheless. The node concluded from this "no
/// mapping" and suppressed its public address.
///
/// MEASURED on the owner's FRITZ!Box 7590 AX, reading via curl:
///   AddPortMapping             -> 403 "Not available Action"
///   GetSpecificPortMappingEntry 8081/UDP
///     -> NewInternalClient (the bootstrap's LAN address, `192.168.178.x`), NewInternalPort 8081,
///        NewEnabled 1, "Cleona UDP 8081 (beta)"
///
/// The forwarding stands, is active, points to the node — and was invisible to the
/// program because it asked the wrong question.
///
/// Empty [remoteHost] means "from any sender", just as the forwardings
/// of the user interface create them.
String buildGetSpecificPortMappingSoap({
  required String serviceType,
  required int externalPort,
  required String protocol,
  String remoteHost = '',
}) {
  return '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body>'
      '<u:GetSpecificPortMappingEntry xmlns:u="$serviceType">'
      '<NewRemoteHost>$remoteHost</NewRemoteHost>'
      '<NewExternalPort>$externalPort</NewExternalPort>'
      '<NewProtocol>$protocol</NewProtocol>'
      '</u:GetSpecificPortMappingEntry>'
      '</s:Body>'
      '</s:Envelope>';
}

/// What an existing mapping says about itself.
class ExistingMapping {
  const ExistingMapping({
    required this.internalClient,
    required this.internalPort,
    required this.enabled,
  });

  /// Where the router sends the packets.
  final String internalClient;

  /// Auf welchen Port.
  final int internalPort;

  /// Whether the forwarding is armed.
  final bool enabled;
}

/// Reads the three fields from the response. `null` if no mapping
/// exists (the router then reports error 714) or the response is unclear
/// — both mean the same here: no proof.
ExistingMapping? parseSpecificPortMappingResponse(String xml) {
  String? field(String name) {
    final m = RegExp('<$name>([^<]*)</$name>').firstMatch(xml);
    return m?.group(1)?.trim();
  }

  final client = field('NewInternalClient');
  final port = int.tryParse(field('NewInternalPort') ?? '');
  final enabled = field('NewEnabled');
  if (client == null || client.isEmpty || port == null) return null;
  return ExistingMapping(
    internalClient: client,
    internalPort: port,
    // Some routers answer with "true" instead of "1".
    enabled: enabled == '1' || enabled?.toLowerCase() == 'true',
  );
}

// ── SOAP for WANIPv6FirewallControl:1 (S391, task E4) ────────────
//
// Action and argument names: WANIPv6FirewallControl:1 §2.6.1
// (GetFirewallStatus, OUT FirewallEnabled + InboundPinholeAllowed),
// §2.6.3 (AddPinhole, IN RemoteHost, RemotePort, InternalClient,
// InternalPort, Protocol, LeaseTime; OUT UniqueID), §2.6.4 (UpdatePinhole,
// IN UniqueID, NewLeaseTime), §2.6.5 (DeletePinhole, IN UniqueID). Unlike
// WANIPConnection the arguments carry NO prefix `New` — except
// `NewLeaseTime` in UpdatePinhole.

String _soapShell(String serviceType, String action, String arguments) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
    's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
    '<s:Body>'
    '<u:$action xmlns:u="$serviceType">$arguments</u:$action>'
    '</s:Body>'
    '</s:Envelope>';

/// GetFirewallStatus — §2.6.1, no input arguments.
String buildGetFirewallStatusSoap() => _soapShell(
    wanIpv6FirewallControlService, 'GetFirewallStatus', '');

/// AddPinhole — §2.6.3.
///
/// [remoteHost] empty and [remotePort] 0 are the placeholders "any
/// sender" (§2.4.5: "wildcard (an empty string)"; §2.4.6: "Value "0" is
/// the wildcard value"). [internalClient] must NOT be empty (§2.6.3.2,
/// error 708). [protocol] is the IANA number (§2.4.7; 17 = UDP).
/// [leaseTime] lies in 1..86400 (§2.4.8, table 2-4).
String buildAddPinholeSoap({
  required String internalClient,
  required int internalPort,
  required int protocol,
  required int leaseTime,
  String remoteHost = '',
  int remotePort = 0,
}) =>
    _soapShell(
        wanIpv6FirewallControlService,
        'AddPinhole',
        '<RemoteHost>$remoteHost</RemoteHost>'
            '<RemotePort>$remotePort</RemotePort>'
            '<InternalClient>$internalClient</InternalClient>'
            '<InternalPort>$internalPort</InternalPort>'
            '<Protocol>$protocol</Protocol>'
            '<LeaseTime>$leaseTime</LeaseTime>');

/// UpdatePinhole — §2.6.4.
String buildUpdatePinholeSoap(
        {required int uniqueId, required int newLeaseTime}) =>
    _soapShell(
        wanIpv6FirewallControlService,
        'UpdatePinhole',
        '<UniqueID>$uniqueId</UniqueID>'
            '<NewLeaseTime>$newLeaseTime</NewLeaseTime>');

/// DeletePinhole — §2.6.5.
String buildDeletePinholeSoap({required int uniqueId}) => _soapShell(
    wanIpv6FirewallControlService,
    'DeletePinhole',
    '<UniqueID>$uniqueId</UniqueID>');

/// A truth value UPnP style: `1`/`0`, some devices write
/// `true`/`false` (the same leniency as with `NewEnabled` above).
bool? _upnpBool(String? v) {
  if (v == null) return null;
  final t = v.trim().toLowerCase();
  if (t == '1' || t == 'true' || t == 'yes') return true;
  if (t == '0' || t == 'false' || t == 'no') return false;
  return null;
}

/// The response to GetFirewallStatus, or `null` on error/unclarity.
({bool firewallEnabled, bool inboundPinholeAllowed})?
    parseFirewallStatusResponse(String xml) {
  if (parseSoapErrorCode(xml) != null) return null;
  final to = _upnpBool(_extractXmlValue(xml, 'FirewallEnabled'));
  final allowed = _upnpBool(_extractXmlValue(xml, 'InboundPinholeAllowed'));
  if (to == null || allowed == null) return null;
  return (firewallEnabled: to, inboundPinholeAllowed: allowed);
}

/// `UniqueID` from the response to AddPinhole (ui2, §2.4.9), or `null`.
int? parseAddPinholeResponse(String xml) {
  if (parseSoapErrorCode(xml) != null) return null;
  final id = int.tryParse(_extractXmlValue(xml, 'UniqueID') ?? '');
  if (id == null || id < 0 || id > 0xFFFF) return null;
  return id;
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
  /// As in `nat_pmp.dart`: a bare sink instead of a `CLogger`.
  final void Function(String)? log;

  /// Devices found by the last discoverDevices() call.
  List<IgdDevice> _lastDevices = [];
  List<IgdDevice> get lastDiscoveredDevices => _lastDevices;

  /// Parsed rootDesc info (manufacturer/modelName/modelNumber/friendlyName)
  /// from the last successful device-description fetch. Same shape as
  /// `UpnpRouterInfo.toJson`. Null if no descriptor parsed.
  ///
  /// Consumed by `PortMapper.upnpRouterInfoJson`, so that the
  /// NAT assistant can match an entry of the curated router list
  /// (§27.9.2).
  Map<String, dynamic>? _lastRouterInfoJson;
  Map<String, dynamic>? get lastRouterInfoJson => _lastRouterInfoJson;

  UpnpIgdClient({this.log});

  /// Discover IGD devices via SSDP multicast + unicast gateway probes.
  ///
  /// ── TWO ROUNDS, AND WHY (S373) ─────────────────────────────────
  ///
  /// The V3 version ALWAYS determined the gateway list, i.e. also
  /// when the multicast had found the IGD immediately — and the determination
  /// included a hop probe that sends packets outside. That is
  /// traffic without cause (working rule #5) and useless in the normal case (IGD in the
  /// own segment).
  ///
  /// Round 1 is therefore cheap and local: multicast plus unicast to the
  /// DEFAULT GATEWAY, which falls out of `/proc/net/route` without a single network access.
  /// Only if it stays empty does round 2 search for the
  /// upstream routers — that is exactly the case "IGD behind a
  /// second router" the probe exists for.
  Future<List<IgdDevice>> discoverDevices({
    Duration timeout = ssdpTimeout,
  }) {
    // ONE SEARCH, TWO ASKERS (S391, task E4). The IPv4 mapping
    // (`PortMapper`) and the IPv6 pinhole (`Ipv6Pinhole`) start at
    // the same edge and need the same device list. If a search is already
    // running, the second asker gets its result — otherwise
    // every edge would cost two SSDP rounds instead of one (working rule 5).
    final running = _runningSearch;
    if (running != null) return running;
    _searchStarted = DateTime.now();
    final search = _searchRun(timeout).whenComplete(() {
      _runningSearch = null;
    });
    _runningSearch = search;
    return search;
  }

  Future<List<IgdDevice>>? _runningSearch;
  DateTime? _searchStarted;

  /// The most recently found devices with the service
  /// [wanIpv6FirewallControlService] (S391, task E4).
  List<IgdDevice> _lastFirewallDevices = const <IgdDevice>[];
  List<IgdDevice> get lastFirewallDevices => _lastFirewallDevices;

  /// The devices with [wanIpv6FirewallControlService] for an edge that
  /// began around [edgeSince] — WITHOUT a second SSDP search, where possible.
  ///
  /// * If a search is currently running: its result.
  /// * If one has already begun since [edgeSince] (and is done): its
  ///   result — it belongs to THIS edge.
  /// * Otherwise: an own search. An older list stems from a
  ///   network that need no longer be the own one.
  Future<List<IgdDevice>> firewallDevices({required DateTime edgeSince}) async {
    final running = _runningSearch;
    if (running != null) {
      await running;
      return _lastFirewallDevices;
    }
    final started = _searchStarted;
    if (started != null && !started.isBefore(edgeSince)) {
      return _lastFirewallDevices;
    }
    await discoverDevices();
    return _lastFirewallDevices;
  }

  /// Reads ONE device description and adds its firewall service to
  /// [lastFirewallDevices]. For the guard
  /// (`smoke_ipv6_pinhole`), which measures the description path over real HTTP
  /// without sending an SSDP search into the segment.
  Future<IgdDevice?> descriptionRead(String locationUrl) async {
    final fw = <IgdDevice>[];
    final d = await _fetchDeviceDescription(locationUrl, fw);
    if (fw.isNotEmpty) _lastFirewallDevices = [..._lastFirewallDevices, ...fw];
    return d;
  }

  Future<List<IgdDevice>> _searchRun(Duration timeout) async {
    final devices = <IgdDevice>[];
    final firewall = <IgdDevice>[];
    final seenLocations = <String>{};

    // Round 1: multicast + unicast to the default gateway.
    final standardGw = await detectGatewayIp();
    await _searchRound(
      unicastTargets: standardGw == null ? const [] : [standardGw],
      timeout: timeout,
      seenLocations: seenLocations,
    );

    // Round 2 — only if round 1 found nothing.
    var gatewayIps = standardGw == null ? <String>[] : <String>[standardGw];
    if (seenLocations.isEmpty) {
      final upstream = await gatewayCandidates(known: gatewayIps);
      if (upstream.isNotEmpty) {
        gatewayIps = [...gatewayIps, ...upstream];
        await _searchRound(
          unicastTargets: upstream,
          timeout: timeout,
          seenLocations: seenLocations,
        );
      }
    }

    // Direct probe: if SSDP found nothing, try the well-known
    // description URL on the gateway IPs (port 49000 is the default on
    // Fritzbox and many other routers).
    if (seenLocations.isEmpty) {
      for (final gwIp in gatewayIps) {
        final url = 'http://$gwIp:49000/igddesc.xml';
        try {
          final device = await _fetchDeviceDescription(url, firewall);
          if (device != null) {
            log?.call('IGD found via direct probe: $gwIp');
            devices.add(device);
            _lastDevices = devices;
            _lastFirewallDevices = firewall;
            return devices; // Found one — no need to continue
          }
        } catch (_) {}
      }
    }

    // Fetch device descriptions and find control URLs.
    // Cache result so callers can reuse without a second SSDP scan.
    for (final location in seenLocations) {
      try {
        final device = await _fetchDeviceDescription(location, firewall);
        if (device != null) {
          devices.add(device);
        }
      } catch (e) {
        log?.call('Device description from $location not loadable: $e');
      }
    }

    _lastDevices = devices;
    _lastFirewallDevices = firewall;
    return devices;
  }

  /// One search round: `M-SEARCH` as multicast and as unicast to
  /// [unicastTargets], then listen for [timeout].
  Future<void> _searchRound({
    required List<String> unicastTargets,
    required Duration timeout,
    required Set<String> seenLocations,
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final local = socket;

      final multicastAddr = InternetAddress(ssdpMulticastAddress);

      // 1. SSDP multicast (works if IGD is on same subnet)
      for (final st in ssdpSearchTargets) {
        try {
          local.send(utf8.encode(buildMSearch(st)), multicastAddr, ssdpPort);
        } catch (_) {}
      }

      // 2. SSDP unicast — covers the case "IGD behind a second router".
      for (final gwIp in unicastTargets) {
        try {
          final gwAddr = InternetAddress(gwIp);
          for (final st in ssdpSearchTargets) {
            local.send(utf8.encode(buildMSearch(st)), gwAddr, ssdpPort);
          }
        } catch (_) {}
      }

      // Collect responses
      final completer = Completer<void>();
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      final sub = local.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = local.receive();
          if (datagram != null) {
            final response = utf8.decode(datagram.data, allowMalformed: true);
            final location = parseSsdpLocation(response);
            if (location != null && seenLocations.add(location)) {
              log?.call('SSDP answer: $location');
            }
          }
        }
      }, onError: (Object _) {});

      await completer.future;
      timer.cancel();
      await sub.cancel();
    } catch (e) {
      log?.call('SSDP search: $e');
    } finally {
      socket?.close();
    }
  }

  /// The usual LAN address of an UPSTREAM router.
  ///
  /// They stand here because in a double NAT they are the only information
  /// obtainable at all without an operating system tool:
  /// the own prefixes reveal the network of the FIRST router, never that
  /// of the second. All are RFC 1918 addresses — they leave no
  /// private network and are routed nowhere on the internet.
  ///
  /// FILTERING HAPPENS NONETHELESS (see [gatewayCandidates]): only those are taken
  /// whose first two octets match an own address. In
  /// this project's measured double NAT situation (LAN 192.168.10.x
  /// behind a Fritzbox on 192.168.178.1) this applies; a probe
  /// to 10.x from a 192.168 network on the other hand would only be traffic that
  /// perishes at the default gateway.
  static const List<String> kUsualRouterAddresses = <String>[
    '192.168.0.1',
    '192.168.1.1',
    '192.168.2.1',
    '192.168.178.1',
    '10.0.0.1',
    '10.0.0.138',
    '172.16.0.1',
  ];

  /// At most this many additional candidates. Each costs three datagrams.
  static const int kMaxCandidates = 8;

  /// Further gateway candidates for the case "IGD behind a second
  /// router" — in this project's test network a Fritzbox behind an
  /// OPNsense.
  ///
  /// ── OPERATING-SYSTEM INDEPENDENT, OWNER DECISION 07.09.2026 ────────
  ///
  /// "The more nodes we reach, the better. I am not the only one with
  /// complex network structures." The first version of this function ran
  /// only on a Linux desktop and only via `tracepath`; thus the
  /// two-router detection was structurally switched off on Windows, macOS, Android and iOS
  /// — i.e. on the four platforms on which
  /// most users sit.
  ///
  /// THREE SOURCES, AND NO SUBPROCESS IS A PRECONDITION:
  ///
  ///  1. **Derived from the own prefixes.** Per own private
  ///     IPv4 address the `.1` and the `.254` of the same /24. That
  ///     works on EVERY platform, costs no process and
  ///     finds the router of the own segment even where no
  ///     routing table is readable (Windows, iOS).
  ///  2. **Usual addresses of an upstream router**
  ///     ([kUsualRouterAddresses]), filtered to the own /16.
  ///  3. **The operating system tool — as an ADDITION, never as a
  ///     prerequisite.** If it fails, is missing, or is
  ///     forbidden (iOS), 1 and 2 remain.
  ///
  /// ── THE FOREIGN ADDRESS IS GONE ──────────────────────────────────────
  ///
  /// The V3 version ran `tracepath` on `8.8.8.8`. The probes
  /// never reached Google (TTL ≤ 3), but carried its address in the header.
  /// In its place comes [kProbeTarget] = `192.0.2.1` — TEST-NET-1 from
  /// RFC 5737, expressly reserved for documentation and assigned to no
  /// host. The way out is the same (the packet goes
  /// to the default route and dies at the TTL), but it is addressed to
  /// nobody.
  ///
  /// RESIDUAL RISK, named: a provider that discards TEST-NET already at the first hop
  /// delivers only this one hop — and that is the
  /// default gateway, which round 1 has already asked anyway. Then only
  /// sources 1 and 2 carry. That is the price for writing to
  /// nobody.
  static const String kProbeTarget = '192.0.2.1';

  Future<List<String>> gatewayCandidates(
      {required List<String> known}) async {
    final out = <String>[];
    void take(String ip) {
      if (out.length >= kMaxCandidates) return;
      if (ip.isEmpty || known.contains(ip) || out.contains(ip)) return;
      if (!_isPrivateIpStatic(ip)) return;
      out.add(ip);
    }

    // ── Source 1: the own prefixes ──────────────────────────────────
    final own = <String>[];
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final i in ifs) {
        // S376 (P2-4): virtual host bridges would otherwise deliver here
        // `192.168.122.1` and `192.168.122.254` as gateway candidates,
        // and both use up one of the `kMaxCandidates` slots for
        // a device that is not an IGD.
        if (!interfaceLeadsAfterOutside(i.name)) continue;
        for (final a in i.addresses) {
          if (!_isPrivateIpStatic(a.address)) continue;
          own.add(a.address);
          final t = a.address.split('.');
          if (t.length != 4) continue;
          take('${t[0]}.${t[1]}.${t[2]}.1');
          take('${t[0]}.${t[1]}.${t[2]}.254');
        }
      }
    } catch (_) {}

    // ── Source 2: usual addresses, filtered to the own /16 ───
    for (final ip in kUsualRouterAddresses) {
      final t = ip.split('.');
      final fits = own.any((e) {
        final o = e.split('.');
        return o.length == 4 && o[0] == t[0] && o[1] == t[1];
      });
      if (fits) take(ip);
    }

    // ── Source 3: the operating system tool, as an addition ───────────
    for (final hop in await _hopsOutTool()) {
      take(hop);
    }

    return out;
  }

  /// The first hops according to the operating system tool, or an empty list.
  ///
  /// Never throws and blocks at most five seconds. On iOS not even
  /// attempted: `Process.run` is not allowed there, and a
  /// failure would be a silent start delay without value. On
  /// Android likewise — `tracepath`/`traceroute` are not in the path there.
  Future<List<String>> _hopsOutTool() async {
    if (Platform.isIOS || Platform.isAndroid) return const <String>[];
    // Order per platform; the first line that delivers something applies.
    final attempts = <List<String>>[
      if (Platform.isWindows) ['tracert', '-d', '-h', '3', '-w', '800'],
      if (Platform.isLinux) ['tracepath', '-n', '-m', '3'],
      if (Platform.isLinux || Platform.isMacOS)
        ['traceroute', '-n', '-m', '3', '-w', '1'],
    ];
    for (final v in attempts) {
      try {
        final r = await Process.run(v.first, [...v.skip(1), kProbeTarget],
                stdoutEncoding: const SystemEncoding())
            .timeout(const Duration(seconds: 5),
                onTimeout: () => ProcessResult(0, 1, '', ''));
        final hit = <String>[];
        for (final line in (r.stdout as String).split('\n')) {
          // Covers both output forms: `1:  192.168.10.1` (tracepath)
          // and `  1    <1 ms  192.168.10.1` (tracert/traceroute).
          for (final m in RegExp(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b')
              .allMatches(line)) {
            final ip = m.group(1)!;
            if (ip == kProbeTarget) continue;
            if (_isPrivateIpStatic(ip) && !hit.contains(ip)) {
              hit.add(ip);
            }
          }
        }
        if (hit.isNotEmpty) return hit;
      } catch (_) {
        // Tool missing, forbidden, or output unusable — the
        // next attempt, otherwise the two other sources.
      }
    }
    return const <String>[];
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
  /// [tryTcp] - whether after the UDP mapping the TCP half of the same
  ///   port should be opened as well (S376). As with `NatPmpClient`: the
  ///   RENEWAL passes `false` through if the device refused the TCP half
  ///   on creation.
  Future<PortMappingResult?> requestMapping({
    required int internalPort,
    int externalPort = 0,
    int leaseDuration = 7200,
    String description = 'Cleona',
    String? internalClient,
    List<IgdDevice>? knownDevices,
    bool tryTcp = true,
  }) async {
    final devices = knownDevices ?? await discoverDevices();
    if (devices.isEmpty) {
      log?.call('No IGD found');
      return null;
    }

    // Detect own IP if not provided
    final myIp = internalClient ?? await detectOwnPrivateIpv4();
    if (myIp == null) {
      log?.call('Own private address cannot be determined');
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
        protocol: 'UDP',
      );
      if (result == null) continue;
      if (!tryTcp) return result;

      // ── THE SECOND HALF OF THE SAME PORT (S376, P2-1) ───────────
      //
      // The node binds UDP and TCP on the same port number
      // (§2.1a/E-60), the mapping until then only opened UDP. In a
      // network that blocks UDP (RL-15), the TCP fallback is the only
      // way in.
      //
      // ONLY AFTER THE UDP SUCCESS, and only on THE SAME device: a
      // second SOAP request to a device that refused the first
      // learns nothing new. Failure is not a failure of the whole
      // — the UDP mapping stands and is returned.
      //
      // The conflict retry (error 718) sits in
      // `_tryMapping` and thus runs per protocol on its own: a
      // TCP conflict deletes the TCP mapping of the previous run, not the
      // UDP mapping just created.
      final tcp = await _tryMapping(
        device: device,
        internalPort: internalPort,
        // The port the device really assigned for UDP.
        externalPort: result.externalPort,
        leaseDuration: leaseDuration,
        description: description,
        internalClient: myIp,
        protocol: 'TCP',
        // The outer address is already settled from the UDP mapping.
        fetchExternalIp: false,
      );
      if (tcp == null) {
        log?.call('UPnP: TCP mapping rejected — the TCP fallback '
            'stays closed behind NAT (UDP stands on ${result.externalPort})');
        return result;
      }
      if (tcp.externalPort != result.externalPort) {
        // Two different outer numbers are not representable in the entry record
        // (one port for both protocols). The
        // TCP mapping is discarded and runs out.
        log?.call('UPnP: TCP mapping on a different port '
            '${tcp.externalPort} instead of ${result.externalPort} — discarded');
        return result;
      }
      log?.call('UPnP: TCP mapping also open on '
          '${result.externalPort}');
      return PortMappingResult(
        externalIp: result.externalIp,
        externalPort: result.externalPort,
        lifetimeSeconds: result.lifetimeSeconds,
        tcpMapped: true,
        acquiredAt: result.acquiredAt,
      );
    }

    return null;
  }

  /// Delete a port mapping.
  ///
  /// [knownDevices] saves the second SSDP search. The teardown runs on
  /// shutdown; a search there keeps the process alive three seconds
  /// longer without achieving anything the device list of the
  /// last run would not already know.
  Future<bool> deleteMapping({
    required int externalPort,
    String protocol = 'UDP',
    List<IgdDevice>? knownDevices,
  }) async {
    final devices = knownDevices ?? await discoverDevices();
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
          log?.call('UPnP mapping deleted: port $externalPort');
          return true;
        }
      } catch (e) {
        log?.call('DeletePortMapping auf ${device.fullControlUrl}: $e');
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
        log?.call('GetExternalIPAddress: $e');
      }
    }
    return null;
  }

  // ── Internal ──────────────────────────────────────────────────────

  /// [firewall] collects a found [wanIpv6FirewallControlService]
  /// (S391, task E4) — even if the description carries no
  /// mapping service and `null` therefore comes back.
  Future<IgdDevice?> _fetchDeviceDescription(
      String locationUrl, List<IgdDevice> firewall) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse(locationUrl);
      final request = await client.getUrl(uri);
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      final body = await response.transform(utf8.decoder).join();

      // Parse router identification (NAT-Wizard §27.9.2) before services.
      // Even if no matching service is found, the descriptor identifies the
      // router — useful for the wizard UI ("UPnP disabled on FRITZ!Box 7590").
      final routerInfo = parseRouterInfo(body);
      if (routerInfo != null) {
        _lastRouterInfoJson = routerInfo;
        log?.call('Router detected from rootDesc: $routerInfo');
      }

      final baseUrl = extractBaseUrl(locationUrl);
      final fwUrl = parseFirewallControlUrl(body);
      if (fwUrl != null) {
        final fw = IgdDevice(
          baseUrl: baseUrl,
          controlPath: fwUrl,
          serviceType: wanIpv6FirewallControlService,
        );
        if (!firewall.any((d) => d.fullControlUrl == fw.fullControlUrl)) {
          firewall.add(fw);
          log?.call('IPv6 firewall service found: ${fw.fullControlUrl}');
        }
      }

      final services = parseDeviceDescription(body);
      if (services.isEmpty) return null;

      final best = services.first;

      return IgdDevice(
        baseUrl: baseUrl,
        controlPath: best.controlUrl,
        serviceType: best.serviceType,
      );
    } catch (e) {
      log?.call('Geraetebeschreibung: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// [protocol] is `'UDP'` or `'TCP'` (S376). Previously it was hard `'UDP'`
  /// at three places of this body — also in the
  /// conflict retry and in the branch for permanent forwardings,
  /// and exactly that is why it must be a parameter and not a second
  /// method: the three places must name the same protocol as the
  /// first, otherwise the conflict branch deletes the wrong mapping.
   /// Asks the router whether the sought mapping ALREADY exists (S380).
  ///
  /// Counts as proof only if all three conditions hold:
  ///
  /// 1. **`NewEnabled`** — a registered but switched-off forwarding
  ///    carries nothing.
  /// 2. **The internal port is ours.** A forwarding on the same
  ///    outer port that points elsewhere is no mapping for
  ///    this service.
  /// 3. **The internal address is OURS.** Without this check
  ///    a node would claim reachability while the router sends the packets to a
  ///    FOREIGN machine in the same network — and the same check
  ///    catches the outdated forwarding after a DHCP change. It fails
  ///    closed.
  ///
  /// If the router does not answer at all or with error 714 ("no such
  /// entry"), that is `null` — no proof, as before.
  Future<PortMappingResult?> _existingMapping({
    required IgdDevice device,
    required int externalPort,
    required String protocol,
    required String internalClient,
    required int internalPort,
    bool fetchExternalIp = true,
  }) async {
    try {
      final soap = buildGetSpecificPortMappingSoap(
        serviceType: device.serviceType,
        externalPort: externalPort,
        protocol: protocol,
      );
      final answer = await _soapRequest(
        device.fullControlUrl,
        device.serviceType,
        'GetSpecificPortMappingEntry',
        soap,
      );
      if (answer == null) return null;
      final b = parseSpecificPortMappingResponse(answer);
      if (b == null) return null;
      if (!b.enabled) {
        log?.call('UPnP: forwarding on $externalPort/$protocol exists, but is '
            'disabled — no evidence');
        return null;
      }
      if (b.internalPort != internalPort) {
        log?.call('UPnP: forwarding on $externalPort/$protocol points to '
            'port ${b.internalPort}, not to $internalPort — no evidence');
        return null;
      }
      if (b.internalClient != internalClient) {
        log?.call('UPnP: forwarding on $externalPort/$protocol points to a '
            'FOREIGN address — no evidence');
        return null;
      }
      // [fetchExternalIp] is `false` for the second (TCP) half
      // of the same port — the outer address is then already settled from the
      // UDP half and the caller discards this field
      // anyway. A second request for it would be traffic without value
      // (working rule 5). Without the query NO abort: the proof for the
      // TCP half is the mapping itself, not the address.
      String outside = '0.0.0.0';
      if (fetchExternalIp) {
        final found = await getExternalIp(knownDevices: [device]);
        if (found == null || found.isEmpty) {
          log?.call('UPnP: forwarding on $externalPort/$protocol exists, but '
              'the external address is unknown — no evidence');
          return null;
        }
        outside = found;
      }
      log?.call('UPnP: existing forwarding adopted — '
          '$outside:$externalPort/$protocol -> $internalClient:$internalPort '
          '(entered by the operator, AddPortMapping was rejected)');
      return PortMappingResult(
        externalIp: outside,
        externalPort: externalPort,
        // A forwarding entered by hand has no lifetime that the
        // router tells us — it stands until someone removes it. 0 means
        // here the same as for a permanent forwarding.
        lifetimeSeconds: 0,
        acquiredAt: DateTime.now(),
        tcpMapped: protocol == 'TCP',
      );
    } catch (e) {
      log?.call('GetSpecificPortMappingEntry: $e');
      return null;
    }
  }


  Future<PortMappingResult?> _tryMapping({
    required IgdDevice device,
    required int internalPort,
    required int externalPort,
    required int leaseDuration,
    required String description,
    required String internalClient,
    required String protocol,
    bool fetchExternalIp = true,
  }) async {
    try {
      final soap = buildAddPortMappingSoap(
        serviceType: device.serviceType,
        externalPort: externalPort,
        protocol: protocol,
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
          log?.call('UPnP conflict on port $externalPort — '
              'delete and try again');
          final deleteSoap = buildDeletePortMappingSoap(
            serviceType: device.serviceType,
            externalPort: externalPort,
            protocol: protocol,
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
            log?.call('UPnP retry failed: error $retryError');
            return null;
          }
        } else if (errorCode == upnpErrorOnlyPermanentLease) {
          // Router only supports permanent leases: retry with lease=0
          log?.call('UPnP only with permanent forwarding — again with lease=0');
          final permSoap = buildAddPortMappingSoap(
            serviceType: device.serviceType,
            externalPort: externalPort,
            protocol: protocol,
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
          log?.call('UPnP AddPortMapping: $errorCode ($desc)');
          // ── CREATION REFUSED DOES NOT MEAN "NO MAPPING" (S380) ──
          //
          // A router on which automatic port forwarding is switched off
          // refuses creation and HAS the mapping nonetheless —
          // entered by hand. Until now this module concluded from the
          // refusal "no mapping" and the node suppressed
          // its public address.
          //
          // MEASURED on the owner's FRITZ!Box: AddPortMapping 403,
          // GetSpecificPortMappingEntry 8081/UDP -> NewInternalClient
          // <the bootstrap's LAN address>, NewEnabled 1. The forwarding stood the whole
          // time; the program asked the wrong question.
          final existing = await _existingMapping(
            device: device,
            externalPort: externalPort,
            protocol: protocol,
            internalClient: internalClient,
            internalPort: internalPort,
            fetchExternalIp: fetchExternalIp,
          );
          if (existing != null) return existing;
          return null;
        }
      }

      // Get external IP
      //
      // [fetchExternalIp] is `false` for the SECOND (TCP) mapping
      // of the same port (S376): the outer address has been settled since the
      // first and does not change between two SOAP requests to
      // the same device. Without this switch the
      // TCP half would cost two additional requests instead of one
      // (working rule 5).
      String externalIp = '0.0.0.0';
      if (fetchExternalIp) {
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
      }

      log?.call('UPnP mapping: $externalIp:$externalPort '
          '→ $internalClient:$internalPort (lease=${leaseDuration}s)');

      return PortMappingResult(
        externalIp: externalIp,
        externalPort: externalPort,
        lifetimeSeconds: leaseDuration,
      );
    } catch (e) {
      log?.call('UPnP AddPortMapping: $e');
      return null;
    }
  }

  // ── Pinhole actions (S391, task E4) ───────────────────────────
  //
  // ALL FOUR GO OVER IPv6, FROM THE OWN GLOBAL ADDRESS, as soon as
  // the IPv6 router is known ([target]/[source]). Reason:
  // WANIPv6FirewallControl:1 §2.6.3.3 recommends allowing unauthenticated
  // control points AddPinhole only with "InternalClient value equals to the
  // control point's IP address", and §2.6.3.4 demands of the
  // control point: "SHOULD use their IPv6 GUA when calling this action"
  // (identically §2.6.4.4, §2.6.5.4). A request over IPv4 would come from
  // a DIFFERENT address than the one the hole is to apply to, and a
  // router following this recommendation then answers 606.
  //
  // Without a known IPv6 router ([target] `null`) the request goes to the
  // URL from the description as it is. Whether a router accepts that is
  // a matter of its policy; if it refuses, that is a refusal like any
  // other — nothing changes.

  /// GetFirewallStatus (§2.6.1). `null` means: no usable response
  /// (also 606) — the caller treats that like "not allowed".
  Future<({bool firewallEnabled, bool inboundPinholeAllowed})?>
      getFirewallStatus(IgdDevice device,
          {InternetAddress? target, InternetAddress? source}) async {
    final answer = await _soapRequest(device.fullControlUrl,
        wanIpv6FirewallControlService, 'GetFirewallStatus',
        buildGetFirewallStatusSoap(),
        target: target, source: source);
    if (answer == null) return null;
    final error = parseSoapErrorCode(answer);
    if (error != null) {
      log?.call('UPnP GetFirewallStatus: error $error '
          '(${parseSoapErrorDescription(answer)})');
      return null;
    }
    return parseFirewallStatusResponse(answer);
  }

  /// AddPinhole (§2.6.3). Returns the `UniqueID` or the error code.
  Future<({int? uniqueId, int? error})> addPinhole(
    IgdDevice device, {
    required String internalClient,
    required int internalPort,
    required int leaseTime,
    int protocol = 17,
    InternetAddress? target,
    InternetAddress? source,
  }) async {
    final answer = await _soapRequest(
        device.fullControlUrl,
        wanIpv6FirewallControlService,
        'AddPinhole',
        buildAddPinholeSoap(
          internalClient: internalClient,
          internalPort: internalPort,
          protocol: protocol,
          leaseTime: leaseTime,
        ),
        target: target,
        source: source);
    if (answer == null) return (uniqueId: null, error: null);
    final error = parseSoapErrorCode(answer);
    if (error != null) {
      log?.call('UPnP AddPinhole: error $error '
          '(${parseSoapErrorDescription(answer)})');
      return (uniqueId: null, error: error);
    }
    return (uniqueId: parseAddPinholeResponse(answer), error: null);
  }

  /// UpdatePinhole (§2.6.4). `null` means success, otherwise the error code
  /// (`-1` for "no response").
  Future<int?> updatePinhole(IgdDevice device,
      {required int uniqueId,
      required int newLeaseTime,
      InternetAddress? target,
      InternetAddress? source}) async {
    final answer = await _soapRequest(
        device.fullControlUrl,
        wanIpv6FirewallControlService,
        'UpdatePinhole',
        buildUpdatePinholeSoap(uniqueId: uniqueId, newLeaseTime: newLeaseTime),
        target: target,
        source: source);
    if (answer == null) return -1;
    return parseSoapErrorCode(answer);
  }

  /// DeletePinhole (§2.6.5). `true` on success.
  Future<bool> deletePinhole(IgdDevice device,
      {required int uniqueId,
      InternetAddress? target,
      InternetAddress? source}) async {
    final answer = await _soapRequest(
        device.fullControlUrl,
        wanIpv6FirewallControlService,
        'DeletePinhole',
        buildDeletePinholeSoap(uniqueId: uniqueId),
        target: target,
        source: source);
    return answer != null && parseSoapErrorCode(answer) == null;
  }

  /// [target]/[source] (S391, task E4): the request goes to [target] instead of
  /// the machine from [controlUrl] (port and path stay), and it leaves
  /// the device from [source]. Justification at the pinhole actions above.
  Future<String?> _soapRequest(
    String controlUrl,
    String serviceType,
    String action,
    String body, {
    InternetAddress? target,
    InternetAddress? source,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      var uri = Uri.parse(controlUrl);
      if (target != null) {
        final port = uri.port;
        // The `Host` header carries the address without zone identifier — the
        // zone identifier only applies on this device (RFC 6874 §3: "URIs
        // including a ZoneID have no meaning outside the originating node
        // … highly desirable … to remove the ZoneID … before including that
        // URI in an HTTP request").
        uri = uri.replace(host: target.address.split('%').first);
        client.connectionFactory = (_, _, _) =>
            Socket.startConnect(target, port, sourceAddress: source);
      }
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      request.headers.set('SOAPAction', '"$serviceType#$action"');
      request.persistentConnection = false; // Fritzbox closes early
      request.headers.contentLength = utf8.encode(body).length;
      request.write(body);
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      return response.transform(utf8.decoder).join();
    } catch (e) {
      log?.call('SOAP ($action): $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
