// Port Mapper — Coordinator for NAT-PMP/PCP and UPnP/IGD.
//
// Runs both protocols in parallel, uses whichever succeeds first.
// Manages lease renewal with a single timer at lifetime/2.
// Provides an event stream for state changes.
import 'dart:async';

import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/nat_pmp.dart';
import 'package:cleona/core/network/nat_traversal.dart';
import 'package:cleona/core/network/upnp_igd.dart';

// ── Events ──────────────────────────────────────────────────────────

/// Port mapper event types.
enum PortMapperEventType {
  mappingAcquired,
  mappingRenewed,
  mappingLost,
  externalIpDiscovered,
}

/// Event emitted by PortMapper when state changes.
class PortMapperEvent {
  final PortMapperEventType type;
  final PortMappingResult? mapping;
  final String? externalIp;
  final String? source; // 'nat-pmp', 'pcp', 'upnp'

  PortMapperEvent({
    required this.type,
    this.mapping,
    this.externalIp,
    this.source,
  });

  /// External IP discovered without a port mapping (e.g. GetExternalIPAddress
  /// succeeded but AddPortMapping was rejected by the router).
  factory PortMapperEvent.externalIpOnly(String ip, int port) => PortMapperEvent(
    type: PortMapperEventType.externalIpDiscovered,
    externalIp: ip,
    source: 'upnp-ip-only',
  );

  @override
  String toString() => 'PortMapperEvent($type, mapping=$mapping, '
      'ip=$externalIp, source=$source)';
}

// ── Port Mapper State ───────────────────────────────────────────────

/// Current state of the port mapper.
enum PortMapperState {
  idle,
  acquiring,
  mapped,
  failed,
  disposed,
}

// ── Port Mapper ─────────────────────────────────────────────────────

/// Coordinates NAT-PMP/PCP and UPnP/IGD for port mapping.
///
/// Usage:
/// ```dart
/// final mapper = PortMapper(internalPort: 41338);
/// mapper.events.listen((event) => print(event));
/// await mapper.start();
/// // ...
/// await mapper.dispose();
/// ```
class PortMapper {
  final int internalPort;
  final int requestedExternalPort;
  final int requestedLifetime;
  final String? profileDir;

  final CLogger _log;
  final NatPmpClient _natPmp;
  final UpnpIgdClient _upnp;

  /// Optional NatTraversal reference for NAT-Wizard status propagation
  /// (§27.9.1). Null in tests that only care about event-stream behavior.
  final NatTraversal? _natTraversal;

  PortMapperState _state = PortMapperState.idle;
  PortMapperState get state => _state;

  PortMappingResult? _activeMapping;
  String? _mappingSource; // 'nat-pmp', 'pcp', 'upnp'

  Timer? _renewalTimer;
  bool _disposed = false;

  final StreamController<PortMapperEvent> _eventController =
      StreamController<PortMapperEvent>.broadcast();

  /// Event stream for state changes.
  Stream<PortMapperEvent> get events => _eventController.stream;

  /// Whether we currently have an active port mapping.
  bool get hasMapping => _activeMapping != null && !_activeMapping!.isExpired;

  /// Current mapping result (or null).
  PortMappingResult? get activeMapping => _activeMapping;

  /// External IP from the active mapping.
  String? get externalIp => _activeMapping?.externalIp;

  /// External port from the active mapping.
  int? get externalPort => _activeMapping?.externalPort;

  PortMapper({
    required this.internalPort,
    this.requestedExternalPort = 0,
    this.requestedLifetime = 7200,
    this.profileDir,
    NatPmpClient? natPmpClient,
    UpnpIgdClient? upnpClient,
    NatTraversal? natTraversal,
  })  : _log = CLogger.get('port-mapper', profileDir: profileDir),
        _natPmp = natPmpClient ?? NatPmpClient(profileDir: profileDir),
        _upnp = upnpClient ?? UpnpIgdClient(profileDir: profileDir),
        _natTraversal = natTraversal;

  /// Start acquiring a port mapping.
  ///
  /// Runs NAT-PMP/PCP and UPnP in parallel. Uses the first successful result.
  /// Non-blocking — returns immediately, emits events via [events] stream.
  Future<void> start() async {
    if (_disposed) return;
    if (_state == PortMapperState.acquiring) return;

    _state = PortMapperState.acquiring;
    _log.info('Starting port mapping for port $internalPort...');

    try {
      // Run both protocols in parallel
      final results = await Future.wait<PortMappingResult?>([
        _tryNatPmp(),
        _tryUpnp(),
      ], eagerError: false);

      if (_disposed) return;

      // Use the first successful result
      PortMappingResult? result;
      String? source;

      if (results[0] != null) {
        result = results[0];
        source = 'nat-pmp';
      } else if (results[1] != null) {
        result = results[1];
        source = 'upnp';
      }

      if (result != null) {
        _setMapping(result, source!);
      } else {
        _state = PortMapperState.failed;
        // Port mapping failed, but we may still learn the external IP.
        // The IGD device (Fritzbox) may reject AddPortMapping from a
        // non-local client but still respond to GetExternalIPAddress.
        // Reuse devices from requestMapping() — no second SSDP scan.
        try {
          final devices = _upnp.lastDiscoveredDevices;
          if (devices.isNotEmpty) {
            final externalIp = await _upnp.getExternalIp(knownDevices: devices);
            if (externalIp != null && externalIp.isNotEmpty && externalIp != '0.0.0.0') {
              _log.info('Port mapping failed, but external IP via UPnP: $externalIp');
              _eventController.add(PortMapperEvent.externalIpOnly(externalIp, internalPort));
            } else {
              _log.info('Port mapping failed — no external IP from IGD');
            }
          } else {
            _log.info('Port mapping failed — no IGD devices');
          }
        } catch (e) {
          _log.info('Port mapping failed — external IP query error: $e');
        }
      }
    } catch (e) {
      if (_disposed) return;
      _state = PortMapperState.failed;
      _log.debug('Port mapping error: $e');
    }
  }

  /// Stop and clear all mappings.
  Future<void> stop() async {
    _renewalTimer?.cancel();
    _renewalTimer = null;

    if (_activeMapping != null && _mappingSource != null) {
      // Try to delete the mapping (best effort)
      try {
        if (_mappingSource == 'upnp') {
          await _upnp.deleteMapping(
            externalPort: _activeMapping!.externalPort,
          );
        } else {
          await _natPmp.deleteMapping(
            internalPort: internalPort,
          );
        }
      } catch (_) {}
    }

    _activeMapping = null;
    _mappingSource = null;
    _state = PortMapperState.idle;
  }

  /// Reset after network change: stop → clear → ready for restart.
  Future<void> reset() async {
    await stop();
  }

  /// Dispose the port mapper permanently.
  Future<void> dispose() async {
    _disposed = true;
    _state = PortMapperState.disposed;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    _natPmp.dispose();
    await _eventController.close();
  }

  // ── Internal ──────────────────────────────────────────────────────

  Future<PortMappingResult?> _tryNatPmp() async {
    try {
      final result = await _natPmp.requestMapping(
        internalPort: internalPort,
        externalPort: requestedExternalPort,
        lifetime: requestedLifetime,
      );
      // NAT-Wizard signal (§27.9.1): success = PCP ok, null = PCP failed
      // (retry exhaustion or error-code response inside NatPmpClient).
      _natTraversal?.setPcpStatus(result != null ? 'ok' : 'failed');
      return result;
    } catch (e) {
      _log.debug('NAT-PMP attempt failed: $e');
      _natTraversal?.setPcpStatus('failed');
      return null;
    }
  }

  Future<PortMappingResult?> _tryUpnp() async {
    // Explicit discover → attempt-mapping split so we can distinguish
    // "no IGD on the network" from "IGD rejected AddPortMapping" for the
    // NAT-Wizard signal (§27.9.1 condition 2).
    List<IgdDevice> devices;
    try {
      devices = await _upnp.discoverDevices();
    } catch (e) {
      _log.debug('UPnP discovery error: $e');
      _natTraversal?.setUpnpStatus('unavailable');
      return null;
    }

    // Always propagate router info whenever rootDesc parse succeeded — even
    // if AddPortMapping later fails, the router *is* identified, and that
    // drives the wizard's router-DB match in §27.9.2 Step 2.
    final routerInfo = _upnp.lastRouterInfoJson;
    if (routerInfo != null) {
      _natTraversal?.setUpnpRouterInfoJson(routerInfo);
    }

    if (devices.isEmpty) {
      // SSDP returned no IGD after the discovery deadline. UPnP is either
      // disabled on the router, not supported, or blocked by the firewall.
      _natTraversal?.setUpnpStatus('unavailable');
      return null;
    }

    try {
      final result = await _upnp.requestMapping(
        internalPort: internalPort,
        externalPort: requestedExternalPort,
        leaseDuration: requestedLifetime,
      );
      // A working IGD responded but may have rejected the mapping (error 718
      // conflict retry also failed, or admin-disabled AddPortMapping while
      // advertising the service). Either way: rejected, not unavailable.
      _natTraversal?.setUpnpStatus(result != null ? 'ok' : 'rejected');
      return result;
    } catch (e) {
      _log.debug('UPnP attempt failed: $e');
      // IGD was reachable during discovery but the mapping call threw.
      // Classify as rejected rather than unavailable — the router is there.
      _natTraversal?.setUpnpStatus('rejected');
      return null;
    }
  }

  void _setMapping(PortMappingResult result, String source) {
    _activeMapping = result;
    _mappingSource = source;
    _state = PortMapperState.mapped;

    _log.info('Port mapping acquired via $source: '
        '${result.externalIp}:${result.externalPort} '
        '(lifetime=${result.lifetimeSeconds}s)');

    _emitEvent(PortMapperEvent(
      type: PortMapperEventType.mappingAcquired,
      mapping: result,
      externalIp: result.externalIp,
      source: source,
    ));

    if (result.externalIp != '0.0.0.0') {
      _emitEvent(PortMapperEvent(
        type: PortMapperEventType.externalIpDiscovered,
        externalIp: result.externalIp,
        source: source,
      ));
    }

    _scheduleRenewal(result);
  }

  void _scheduleRenewal(PortMappingResult result) {
    _renewalTimer?.cancel();

    // Renewal at lifetime/2. For permanent leases (lifetime=0): 30 minutes.
    final renewalSeconds = result.lifetimeSeconds > 0
        ? result.lifetimeSeconds ~/ 2
        : 1800;

    _log.debug('Lease renewal scheduled in ${renewalSeconds}s');

    _renewalTimer = Timer(Duration(seconds: renewalSeconds), () {
      if (!_disposed) _renewMapping();
    });
  }

  Future<void> _renewMapping() async {
    if (_disposed || _activeMapping == null || _mappingSource == null) return;

    _log.debug('Renewing port mapping via $_mappingSource...');

    PortMappingResult? result;

    try {
      if (_mappingSource == 'upnp') {
        result = await _upnp.requestMapping(
          internalPort: internalPort,
          externalPort: _activeMapping!.externalPort,
          leaseDuration: requestedLifetime,
        );
      } else {
        result = await _natPmp.requestMapping(
          internalPort: internalPort,
          externalPort: _activeMapping!.externalPort,
          lifetime: requestedLifetime,
        );
      }
    } catch (e) {
      _log.debug('Renewal attempt failed: $e');
    }

    if (_disposed) return;

    if (result != null) {
      _activeMapping = result;
      _log.info('Mapping renewed: ${result.externalPort} (${result.lifetimeSeconds}s)');

      _emitEvent(PortMapperEvent(
        type: PortMapperEventType.mappingRenewed,
        mapping: result,
        externalIp: result.externalIp,
        source: _mappingSource,
      ));

      _scheduleRenewal(result);
    } else {
      // Retry once after 5 seconds
      _log.debug('Renewal failed — retrying in 5s');
      _renewalTimer = Timer(const Duration(seconds: 5), () async {
        if (_disposed) return;

        PortMappingResult? retryResult;
        try {
          if (_mappingSource == 'upnp') {
            retryResult = await _upnp.requestMapping(
              internalPort: internalPort,
              externalPort: _activeMapping?.externalPort ?? internalPort,
              leaseDuration: requestedLifetime,
            );
          } else {
            retryResult = await _natPmp.requestMapping(
              internalPort: internalPort,
              externalPort: _activeMapping?.externalPort ?? 0,
              lifetime: requestedLifetime,
            );
          }
        } catch (_) {}

        if (_disposed) return;

        if (retryResult != null) {
          _activeMapping = retryResult;
          _log.info('Mapping renewed (retry): ${retryResult.externalPort}');
          _emitEvent(PortMapperEvent(
            type: PortMapperEventType.mappingRenewed,
            mapping: retryResult,
            externalIp: retryResult.externalIp,
            source: _mappingSource,
          ));
          _scheduleRenewal(retryResult);
        } else {
          // Both attempts failed — mapping lost
          _log.info('Mapping lost — renewal failed after retry');
          _activeMapping = null;
          _state = PortMapperState.failed;
          _emitEvent(PortMapperEvent(
            type: PortMapperEventType.mappingLost,
            source: _mappingSource,
          ));
          _mappingSource = null;
        }
      });
    }
  }

  void _emitEvent(PortMapperEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }
}
