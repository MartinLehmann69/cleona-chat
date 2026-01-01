/// The IPv6 pinhole at the own router — task E4 (S391), V4.2 §7.3.
///
/// ── WHAT THE SPEC REQUIRES ───────────────────────────────────────────
///
/// §7.3: "it asks its own router for a mapping (IPv4) and a pinhole (IPv6)
/// of its data port — NAT-PMP/PCP first, UPnP/IGD second; PCP covers both
/// families, UPnP through IGDv2 `WANIPv6FirewallControl` — at the edges of
/// §11.8 only (start, network change), never on a timer." The IPv4 half
/// is handled by `port_mapper.dart`. This file handles the IPv6 half.
///
/// A pinhole TRANSLATES nothing: it opens the own global
/// IPv6 address (GUA) on the data port in the router's firewall. The
/// address that is valid from outside afterwards is therefore the own one — PCP names
/// it nonetheless in its response (RFC 6887 §11.1: with a pure
/// firewall "the assigned external IP address and port … always match the
/// internal IP address and port"), UPnP names none.
///
/// ── WHEN ────────────────────────────────────────────────────────────
///
/// Only at an edge ([Ipv6Pinhole.toEdge]: start, network change) and only
/// when the node has a GUA ([determineIpv6Environment]). Otherwise the
/// only clockwork is the renewal before expiry — the third clock from §5.4,
/// "the node's own router, local segment, not the data port".
///
/// ── ORDER ─────────────────────────────────────────────────────
///
/// 1. PCP (RFC 6887) to the IPv6 default router — only if it is known
///    (`detectIpv6Gateway` in `nat_pmp.dart`).
/// 2. Otherwise, or if PCP does not grant: UPnP `WANIPv6FirewallControl:1`
///    (`upnp_igd.dart`) — GetFirewallStatus, then AddPinhole.
///
/// ── PACKET COUNT (working rule #5, §7.3 "cost of a failure") ───────────
///
/// PCP: at most [kPcpPinholeShipments] = 2 datagrams to the router in the
/// own segment, 3 s and 6 s wait (RFC 6887 §8.1.1: IRT 3 s,
/// doubling). RFC 6887 recommends MRC = 0 (unlimited); the limit 2 is
/// a deliberate deviation and follows the spec ("a mapping that fails costs
/// two packets in the local segment"). A router that answers with an
/// error code is not asked again.
/// UPnP: 0 SSDP datagrams (the search of the IPv4 path is reused,
/// `UpnpIgdClient.firewallDevices`), then per device 1 SOAP request
/// (GetFirewallStatus) and only if permitted a second one (AddPinhole).
/// Renewal: 1 datagram or 1 SOAP request per attempt.
/// Teardown: 1 datagram or 1 SOAP request.
///
/// ── WHAT IS ONLY CHECKED AGAINST A TEST DOUBLE ──────────────────────
///
/// See `mycelium/berichte/S391-BAU-E4-PINHOLE.md` (open points): whether a
/// FRITZ!Box router answers PCP for IPv6, whether it accepts the SOAP request on
/// its link-local address and from the GUA, and how it reads an
/// empty `RemoteHost`, is to be measured in the lab.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/link_io/nat_pmp.dart'
    show
        detectIpv6Gateway,
        encodePcpMapRequest,
        natPmpPort,
        parsePcpMapResponse,
        pcpOpMap,
        pcpProtocolUdp,
        pcpResultName,
        pcpResultSuccess,
        pcpVersion;
import 'package:cleona/core/link_io/upnp_igd.dart';
import 'package:cleona/core/util/host_interfaces.dart';
import 'package:cleona/core/util/local_addresses.dart'
    show isExternallyReachable;

/// RFC 6887 §8.1.1: „IRT: Initial retransmission time, SHOULD be 3 seconds".
const Duration kPcpIrt = Duration(seconds: 3);

/// At most this many datagrams per PCP setup (see file header).
const int kPcpPinholeShipments = 2;

/// Upper limit for a lifetime named by the router. RFC 6887 §15:
/// "Upon receipt of a PCP response with an absurdly long assigned
/// lifetime, the PCP client SHOULD behave as if it received a more sane
/// value (e.g., 24 hours)". The same number is the maximum of
/// `A_ARG_TYPE_LeaseTime` in WANIPv6FirewallControl:1 §2.4.8 (86400).
const int kPinholeLifetimeAtMost = 86400;

/// RFC 6887 §11.2.1: „renewal requests MUST NOT be sent less than four
/// seconds apart".
const Duration kRenewalMinInterval = Duration(seconds: 4);

// ── Environment ─────────────────────────────────────────────────────

/// What the pinhole needs to know about the own network.
class Ipv6Environment {
  /// The own global IPv6 address — the hole applies to it.
  final InternetAddress own;

  /// The IPv6 default router WITH zone identifier, or `null` if it cannot
  /// be determined (then no PCP, and UPnP goes to the URL from the
  /// description).
  final InternetAddress? router;

  const Ipv6Environment({required this.own, this.router});

  @override
  String toString() => 'Ipv6Environment(${own.address}, '
      'router=${router?.address ?? '-'})';
}

/// Determines [Ipv6Environment] — or `null` if the node has no global
/// IPv6. Then there is no pinhole and not a single packet.
///
/// "Global" means here the same as everywhere in the app:
/// [isExternallyReachable] (no loopback, no link-local, no ULA
/// `fc00::/7`, no tunnel pseudo-form) on an interface that leads
/// outside ([interfaceLeadsAfterOutside], the same filter as
/// `dialableLocalAddresses`). If the router is known, the GUA on
/// ITS interface is taken — the PCP request must come from the address
/// it applies to (RFC 6887 §8.1: "The PCP client MUST include
/// the source IP address of the PCP message in the PCP request").
Future<Ipv6Environment?> determineIpv6Environment() async {
  final gw = await detectIpv6Gateway();
  InternetAddress? first;
  InternetAddress? onRouterInterface;
  try {
    for (final s
        in await NetworkInterface.list(type: InternetAddressType.IPv6)) {
      if (!interfaceLeadsAfterOutside(s.name)) continue;
      for (final a in s.addresses) {
        if (a.rawAddress.length != 16) continue;
        if (!isExternallyReachable(a.address)) continue;
        first ??= a;
        if (gw != null && s.name == gw.networkInterface) {
          onRouterInterface ??= a;
        }
      }
    }
  } catch (_) {
    // Enumeration during an interface change — not an error.
  }
  if (first == null) return null;
  if (gw != null && onRouterInterface != null) {
    final router =
        InternetAddress.tryParse('${gw.router}%${gw.networkInterface}');
    return Ipv6Environment(own: onRouterInterface, router: router);
  }
  return Ipv6Environment(own: first);
}

// ── PCP ─────────────────────────────────────────────────────────────

/// What a PCP router answered to a MAP request.
typedef PcpPinholeAnswer = ({
  int result,
  int lifetime,
  int outsidePort,
  String outsideAddress,
});

/// The PCP dialogue for the IPv6 pinhole (RFC 6887 §11, MAP opcode).
///
/// Own, short-lived socket per dialogue — the same justification as in
/// `nat_pmp.dart` (header, "Own, short-lived socket"). It is bound to the
/// OWN GUA, so that the source address of the packet matches the address in the
/// header (otherwise ADDRESS_MISMATCH, RFC 6887 §7.4 code 12).
class PcpPinholeClient {
  final void Function(String)? log;

  /// The port of the PCP server — RFC 6887 §19.1 (port 5351). Changeable only for the
  /// guard.
  final int serverPort;

  final Set<RawDatagramSocket> _open = <RawDatagramSocket>{};
  final Random _random;

  PcpPinholeClient({this.log, this.serverPort = natPmpPort, Random? random})
      : _random = random ?? Random();

  /// A MAP request to [router], from [own].
  ///
  /// At most [shipments] datagrams, the wait starts at
  /// [firstWait] and doubles, each with ±10 % randomness (RFC 6887
  /// §8.1.1: "RT = (1 + RAND) * IRT", "RT = (1 + RAND) * MIN (2 * RTprev,
  /// MRT)", RAND in [-0.1, +0.1]). `null` means: no matching response.
  ///
  /// [lifetime] 0 is the deletion (RFC 6887 §15.1); then the
  /// address suggestion stays zero, as §15.1 demands.
  Future<PcpPinholeAnswer?> map({
    required InternetAddress own,
    required InternetAddress router,
    required int port,
    required int lifetime,
    required Uint8List nonce,
    String? proposalAddress,
    int proposalPort = 0,
    int shipments = kPcpPinholeShipments,
    Duration firstWait = kPcpIrt,
    bool Function()? abort,
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? sub;
    try {
      socket = await RawDatagramSocket.bind(own, 0);
      _open.add(socket);
      final local = socket;
      final request = encodePcpMapRequest(
        clientIp: own.address,
        internalPort: port,
        externalPort: lifetime == 0 ? 0 : proposalPort,
        lifetime: lifetime,
        protocol: pcpProtocolUdp,
        nonce: nonce,
        suggestedExternalIp: lifetime == 0 ? null : proposalAddress,
      );
      final result = Completer<PcpPinholeAnswer>();
      sub = local.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = local.receive();
        if (d == null || result.isCompleted) return;
        final a = _check(d, router, port, nonce);
        if (a != null) result.complete(a);
      }, onError: (Object _) {});

      var wait = firstWait;
      for (var i = 0; i < shipments; i++) {
        if (abort?.call() ?? false) return null;
        local.send(request, router, serverPort);
        final rt = wait * (0.9 + 0.2 * _random.nextDouble());
        final a = await result.future
            .timeout(rt, onTimeout: () => _noAnswer);
        if (a.result >= 0) return a;
        wait *= 2;
      }
      return null;
    } catch (e) {
      log?.call('PCP-Pinhole: $e');
      return null;
    } finally {
      await sub?.cancel();
      if (socket != null) {
        _open.remove(socket);
        socket.close();
      }
    }
  }

  /// The marker "wait elapsed" — a genuine result code is one
  /// byte and never negative.
  static const PcpPinholeAnswer _noAnswer =
      (result: -1, lifetime: 0, outsidePort: 0, outsideAddress: '');

  /// RFC 6887 §8.3 (processing a response) and §11.4 (matching a MAP response):
  /// sender = server, R bit set, length 24..1100 and divisible by 4,
  /// opcode MAP, and nonce, protocol and internal port as in the request.
  /// Everything else is silently discarded.
  PcpPinholeAnswer? _check(
      Datagram d, InternetAddress router, int port, Uint8List nonce) {
    if (d.port != serverPort) return null;
    if (!_sameBytes(d.address.rawAddress, router.rawAddress)) return null;
    final raw = Uint8List.fromList(d.data);
    if (raw.length < 60 || raw.length > 1100 || raw.length % 4 != 0) {
      return null;
    }
    if (raw[0] != pcpVersion || raw[1] != (0x80 | pcpOpMap)) return null;
    final p = parsePcpMapResponse(raw);
    if (p == null) return null;
    if (!_sameBytes(p.nonce ?? Uint8List(0), nonce)) return null;
    if (p.protocol != pcpProtocolUdp || p.internalPort != port) return null;
    return (
      result: p.resultCode,
      lifetime: p.lifetime,
      outsidePort: p.externalPort,
      outsideAddress: p.assignedAddress ?? '',
    );
  }

  void dispose() {
    for (final s in _open.toList()) {
      try {
        s.close();
      } catch (_) {}
    }
    _open.clear();
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ── Das gewaehrte Pinhole ───────────────────────────────────────────

/// A pinhole granted by the router.
class Pinhole {
  /// The address under which the node is now reachable (the GUA).
  final InternetAddress address;
  final int port;

  /// Granted lifetime in seconds, capped at
  /// [kPinholeLifetimeAtMost].
  final int lifetime;
  final DateTime since;

  /// `'pcp'` or `'upnp'`.
  final String source;

  /// PCP: the nonce (renewal and deletion MUST repeat it,
  /// RFC 6887 §8.1.1, §15.1).
  final Uint8List? nonce;

  /// UPnP: the `UniqueID` and the device (§2.6.4, §2.6.5).
  final int? uniqueId;
  final IgdDevice? device;

  Pinhole({
    required this.address,
    required this.port,
    required this.lifetime,
    required this.source,
    DateTime? since,
    this.nonce,
    this.uniqueId,
    this.device,
  }) : since = since ?? DateTime.now();

  DateTime get expiry => since.add(Duration(seconds: lifetime));

  /// Expired — §11.8a: „a mapping or pinhole its router granted … and
  /// that has not lapsed".
  bool get expired => !DateTime.now().isBefore(expiry);

  @override
  String toString() => 'Pinhole(${address.address}:$port via $source, '
      '${lifetime}s)';
}

// ── The coordinator ─────────────────────────────────────────────────

/// Asks the own router for an IPv6 pinhole for the data port,
/// keeps it fresh until shortly before expiry and deletes it on teardown.
///
/// The same generation counter as in `PortMapper` (header there, "The
/// generation counter"): every edge and the teardown increment it; a
/// run or a renewal timer from an older generation no longer stores
/// anything and no longer reports anything.
class Ipv6Pinhole {
  final int port;

  /// Requested lifetime in seconds. Default as for the IPv4 mapping
  /// (7200); WANIPv6FirewallControl:1 §2.4.8 recommends at least 3600.
  final int lifetime;

  /// First PCP wait ([kPcpIrt]); shorter only for the guard.
  final Duration pcpWait;

  final void Function(String)? _log;
  final PcpPinholeClient _pcp;
  final UpnpIgdClient _upnp;
  final Future<Ipv6Environment?> Function() _environment;
  final Random _random;

  /// Fires with the GUA and the port on every grant AND every
  /// successful renewal — the same behaviour as `beiAbbildung` for
  /// IPv4 (`mappingAcquired`/`mappingRenewed`).
  void Function(InternetAddress address, int port)? onGranted;

  Pinhole? _active;
  Ipv6Environment? _environmentTheEdge;
  int _generation = 0;
  Timer? _timer;
  bool _disposed = false;

  Ipv6Pinhole({
    required this.port,
    this.lifetime = 7200,
    this.pcpWait = kPcpIrt,
    void Function(String)? log,
    PcpPinholeClient? pcp,
    UpnpIgdClient? upnp,
    Future<Ipv6Environment?> Function()? environment,
    Random? random,
  })  : _log = log,
        _pcp = pcp ?? PcpPinholeClient(log: log),
        _upnp = upnp ?? UpnpIgdClient(log: log),
        _environment = environment ?? determineIpv6Environment,
        _random = random ?? Random();

  /// Granted and not expired (§11.8a).
  bool get proven {
    final a = _active;
    return a != null && !a.expired;
  }

  Pinhole? get active => _active;

  /// For the guard: changes on every edge and on teardown.
  int get generation => _generation;

  bool _stale(int gen) => _disposed || gen != _generation;

  /// Start OR network change (§7.3, §11.8). An existing pinhole is
  /// deleted first — it applies to an address that after the change
  /// need no longer be the own one.
  Future<void> toEdge() async {
    if (_disposed) return;
    final edgeSince = DateTime.now();
    await _giveUp();
    final gen = _generation;

    final u = await _environment();
    if (_stale(gen)) return;
    if (u == null) {
      _log?.call('IPv6-Pinhole: no global IPv6 — nothing to ask');
      return;
    }
    _environmentTheEdge = u;

    // One nonce per edge — RFC 6887 §11.2: "RECOMMENDED to choose a new
    // random mapping nonce whenever the PCP client is initialized"; it
    // must be unguessable (RFC 4086), hence `Random.secure`.
    final safe = Random.secure();
    final nonce =
        Uint8List.fromList(List<int>.generate(12, (_) => safe.nextInt(256)));

    Pinhole? p;
    if (u.router != null) {
      p = await _pcpCreate(u, nonce, gen);
      if (_stale(gen)) return;
    }
    p ??= await _upnpCreate(u, edgeSince, gen);
    if (_stale(gen)) return;
    if (p == null) {
      _log?.call('IPv6-Pinhole: not granted by the router — '
          'reachability unchanged');
      return;
    }
    _set(p, gen);
  }

  /// MANDATORY on shutdown: deletes the pinhole at the router and stops
  /// the renewal timer (otherwise it keeps the Dart VM alive).
  Future<void> layDown() async {
    if (_disposed) return;
    await _giveUp();
    _disposed = true;
    _pcp.dispose();
  }

  // ── Create ────────────────────────────────────────────────────────

  Future<Pinhole?> _pcpCreate(
      Ipv6Environment u, Uint8List nonce, int gen) async {
    final a = await _pcp.map(
      own: u.own,
      router: u.router!,
      port: port,
      lifetime: lifetime,
      nonce: nonce,
      firstWait: pcpWait,
      abort: () => _stale(gen),
    );
    if (a == null) {
      _log?.call('IPv6-Pinhole: PCP router ${u.router!.address} does not '
          'answer');
      return null;
    }
    if (a.result != pcpResultSuccess) {
      _log?.call('IPv6 pinhole: PCP refused '
          '(${pcpResultName(a.result)})');
      return null;
    }
    return _outPcp(a, u, nonce);
  }

  Pinhole? _outPcp(PcpPinholeAnswer a, Ipv6Environment u, Uint8List nonce) {
    if (a.lifetime <= 0) return null;
    // The response names the address valid from outside. For a pure
    // firewall that is the own one; if it differs (NPTv6, RFC 6887 §11.3),
    // the router's applies — it is the one a stranger dials.
    final outside = InternetAddress.tryParse(a.outsideAddress);
    final address = (outside != null &&
            outside.rawAddress.length == 16 &&
            isExternallyReachable(outside.address))
        ? outside
        : u.own;
    return Pinhole(
      address: address,
      port: a.outsidePort == 0 ? port : a.outsidePort,
      lifetime: min(a.lifetime, kPinholeLifetimeAtMost),
      source: 'pcp',
      nonce: nonce,
    );
  }

  Future<Pinhole?> _upnpCreate(
      Ipv6Environment u, DateTime edgeSince, int gen) async {
    List<IgdDevice> devices;
    try {
      devices = await _upnp.firewallDevices(edgeSince: edgeSince);
    } catch (e) {
      _log?.call('IPv6 pinhole: UPnP search: $e');
      return null;
    }
    if (_stale(gen)) return null;
    if (devices.isEmpty) {
      _log?.call('IPv6-Pinhole: no router with WANIPv6FirewallControl');
      return null;
    }
    final leasing = min(lifetime, kPinholeLifetimeAtMost);
    for (final g in devices) {
      final status =
          await _upnp.getFirewallStatus(g, target: u.router, source: _source(u));
      if (_stale(gen)) return null;
      if (status == null) continue;
      if (!status.firewallEnabled) {
        // §2.4.2: firewall off means "all inbound … traffic is allowed".
        // That is NOT a granted pinhole and thus no proof under
        // §11.8a — nothing changes.
        _log?.call('IPv6-Pinhole: router reports FirewallEnabled=0 — no '
            'pinhole needed, none created');
        continue;
      }
      if (!status.inboundPinholeAllowed) {
        _log?.call('IPv6-Pinhole: router allows no pinholes '
            '(InboundPinholeAllowed=0)');
        continue;
      }
      final r = await _upnp.addPinhole(g,
          internalClient: u.own.address,
          internalPort: port,
          leaseTime: leasing,
          target: u.router,
          source: _source(u));
      if (_stale(gen)) return null;
      final id = r.uniqueId;
      if (id == null) continue;
      return Pinhole(
        address: u.own,
        port: port,
        lifetime: leasing,
        source: 'upnp',
        uniqueId: id,
        device: g,
      );
    }
    return null;
  }

  /// The source address of the SOAP request: the GUA, but only if the request
  /// also goes over IPv6 (to the router). Without a router it goes to the
  /// IPv4 URL of the description, and an IPv6 source would be unbindable there.
  InternetAddress? _source(Ipv6Environment u) =>
      u.router == null ? null : u.own;

  // ── Hold ──────────────────────────────────────────────────────────

  void _set(Pinhole p, int gen) {
    _active = p;
    _log?.call('IPv6 pinhole granted: $p');
    onGranted?.call(p.address, p.port);
    _planeRenewal(p, 0, gen);
  }

  /// RFC 6887 §11.2.1: first renewal uniformly distributed in [1/2, 5/8] of the
  /// lifetime; if it fails, the next in [3/4, 3/4 + 1/16], then
  /// [7/8, 7/8 + 1/32] etc. — never closer than 4 s to each other. The same
  /// plan applies to the UPnP pinhole; WANIPv6FirewallControl:1 does not define
  /// its own (§2.3: "If a longer duration is needed, then the control
  /// point needs to use the UpdatePinhole() action").
  void _planeRenewal(Pinhole p, int attempt, int gen, [DateTime? last]) {
    _timer?.cancel();
    final denominator = 1 << (attempt + 1); // 2, 4, 8, …
    final bottom = 1 - 1 / denominator; // 1/2, 3/4, 7/8, …
    final width = 1 / (denominator * 4); // 1/8, 1/16, 1/32, …
    final share = bottom + width * _random.nextDouble();
    var target = p.since.add(Duration(
        milliseconds: (p.lifetime * 1000 * share).round()));
    if (last != null) {
      final early = last.add(kRenewalMinInterval);
      if (target.isBefore(early)) target = early;
    }
    if (!target.isBefore(p.expiry)) {
      _log?.call('IPv6-Pinhole: renewal before expiry no longer possible — '
          'it expires at ${p.expiry.toIso8601String()}');
      return;
    }
    final wait = target.difference(DateTime.now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (_stale(gen)) return;
      unawaited(_renew(p, attempt, gen));
    });
  }

  Future<void> _renew(Pinhole p, int attempt, int gen) async {
    final u = _environmentTheEdge;
    if (u == null || !identical(_active, p)) return;
    final sent = DateTime.now();
    Pinhole? fresh;
    try {
      if (p.source == 'pcp' && u.router != null && p.nonce != null) {
        // RFC 6887 §11.2.1: "a single renewal request packet", with the
        // previous address and port as suggestion.
        final a = await _pcp.map(
          own: u.own,
          router: u.router!,
          port: port,
          lifetime: lifetime,
          nonce: p.nonce!,
          proposalAddress: p.address.address,
          proposalPort: p.port,
          shipments: 1,
          firstWait: pcpWait,
          abort: () => _stale(gen),
        );
        if (a != null && a.result == pcpResultSuccess) {
          fresh = _outPcp(a, u, p.nonce!);
        } else if (a != null) {
          _log?.call('IPv6 pinhole: PCP renewal refused '
              '(${pcpResultName(a.result)})');
        }
      } else if (p.source == 'upnp' && p.device != null && p.uniqueId != null) {
        final leasing = min(lifetime, kPinholeLifetimeAtMost);
        var error = await _upnp.updatePinhole(p.device!,
            uniqueId: p.uniqueId!,
            newLeaseTime: leasing,
            target: u.router,
            source: _source(u));
        var id = p.uniqueId;
        if (error == upnpFwErrorNoSuchEntry) {
          // §2.6.4.7: 704 — the router no longer knows the hole. AddPinhole
          // extends or creates anew (§2.3 point 2, §2.6.3.3).
          final r = await _upnp.addPinhole(p.device!,
              internalClient: u.own.address,
              internalPort: port,
              leaseTime: leasing,
              target: u.router,
              source: _source(u));
          id = r.uniqueId;
          error = id == null ? (r.error ?? -1) : null;
        }
        if (error == null && id != null) {
          fresh = Pinhole(
            address: p.address,
            port: p.port,
            lifetime: leasing,
            source: 'upnp',
            uniqueId: id,
            device: p.device,
          );
        } else {
          _log?.call('IPv6-Pinhole: UPnP renewal without success '
              '(error $error)');
        }
      }
    } catch (e) {
      _log?.call('IPv6 pinhole: renewal: $e');
    }
    if (_stale(gen) || !identical(_active, p)) return;
    if (fresh != null) {
      _active = fresh;
      _log?.call('IPv6-Pinhole erneuert: $fresh');
      onGranted?.call(fresh.address, fresh.port);
      _planeRenewal(fresh, 0, gen);
    } else {
      _planeRenewal(p, attempt + 1, gen, sent);
    }
  }

  // ── Delete ────────────────────────────────────────────────────────

  /// Declares every running run outdated, stops the timer
  /// and deletes a still valid pinhole at the router (best effort: one
  /// datagram or one SOAP request).
  Future<void> _giveUp() async {
    _generation++;
    _timer?.cancel();
    _timer = null;
    final p = _active;
    final u = _environmentTheEdge;
    _active = null;
    if (p == null || u == null || p.expired) return;
    try {
      if (p.source == 'pcp' && u.router != null && p.nonce != null) {
        // RFC 6887 §15.1: lifetime 0 deletes; the nonce must match.
        final a = await _pcp.map(
          own: u.own,
          router: u.router!,
          port: port,
          lifetime: 0,
          nonce: p.nonce!,
          shipments: 1,
          firstWait: pcpWait < const Duration(seconds: 2)
              ? pcpWait
              : const Duration(seconds: 2),
        );
        _log?.call('IPv6-Pinhole: PCP deletion '
            '${a == null ? 'without answer' : pcpResultName(a.result)}');
      } else if (p.source == 'upnp' && p.device != null && p.uniqueId != null) {
        final ok = await _upnp.deletePinhole(p.device!,
            uniqueId: p.uniqueId!, target: u.router, source: _source(u));
        _log?.call('IPv6-Pinhole: DeletePinhole ${ok ? 'ok' : 'without success'}');
      }
    } catch (e) {
      _log?.call('IPv6 pinhole: deletion: $e');
    }
  }
}
