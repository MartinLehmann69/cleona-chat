/// Port Mapper — the coordinator over NAT-PMP/PCP and UPnP/IGD.
///
/// ── WHERE THIS FILE COMES FROM (S373) ──────────────────────────────────
///
/// Like its two building blocks next to it: until the CUT of 31.08.2026 it stood
/// as `lib/core/network/port_mapper.dart` in the V3 tree and fell with it.
/// Bringing it back approved by the owner on 07.09.2026.
///
/// ONE DIFFERENCE FROM THE V3 VERSION, and it is the only substantive one: back then it
/// was passed a `NatTraversal` and wrote its
/// status signals there (§27.9.1: `upnpStatus`, `pcpStatus`,
/// `upnpRouterInfoJson`). This class no longer exists in V4.1. The three
/// signals have therefore become fields of THIS class — they arise here,
/// they are read here, and there is no third place where they
/// could become outdated.
///
/// ── WHAT IT DOES ─────────────────────────────────────────────────────
///
/// Both protocols run SIDE BY SIDE, not one after the other; the first
/// result wins, on a tie NAT-PMP/PCP (it is the cheaper and
/// the more precise one — it delivers the outer address in the same dialogue). The
/// renewal runs at half lifetime, with exactly ONE retry
/// after 5 s; after that the mapping counts as lost and the event stream
/// says so.
///
/// ── A TIMER THAT KEEPS THE VM ALIVE ────────────────────────
///
/// [dispose] IS MANDATORY. The renewal timer is a `Timer` with a
/// duration of up to one hour, and a pending timer keeps the
/// Dart VM alive — the same trap for which `V41Runtime.entryPersist`
/// stands in the return value of `startV41Node` at all. A daemon that
/// forgets this call does not terminate after `stopAll()` for up to an
/// hour.
///
/// ── PACKET COUNT (working rule #5) ─────────────────────────────────────
///
/// It stands with the two building blocks. Summarised, per detection run:
/// in the FAVOURABLE case (gateway answers, IGD in the own segment) 2
/// NAT-PMP datagrams + 6 SSDP datagrams + 3 HTTP/SOAP requests; in the
/// WORST case (nothing answers) 37 NAT-PMP/PCP datagrams over around
/// eight and a half minutes, 12 SSDP datagrams and the hop probe. A
/// detection run occurs at node start and afterwards only on a
/// NETWORK CHANGE. Ongoing operation: 1 datagram per half lifetime, i.e.
/// with the default of 7200 s one packet per hour. There is no polling.
///
/// SINCE S380 THE WORST CASE ONLY APPLIES IF UPnP ALSO COMES UP
/// EMPTY. If UPnP delivers a mapping — three SOAP requests, in the field
/// 3.2 s —, the NAT-PMP/PCP path is waved off: `requestMapping` asks
/// there before every stage and before every retry whether it is still worthwhile.
/// 37 datagrams over eight and a half minutes thus become two to four depending on
/// timing. Until then they ran completely, although the
/// result was settled.
///
/// SINCE S376 (P2-1) the second mapping for TCP is added — namely
/// ONLY after a successful UDP mapping, with exactly one datagram
/// or one SOAP request without retry. The worst case therefore stays
/// at 37; the favourable one goes from 2 to 3 datagrams (or from 3
/// to 4 SOAP requests). If the gateway refuses the TCP half, the
/// RENEWAL passes `tryTcp: false` through — otherwise a gateway without
/// TCP mappings would cost a useless datagram per hour, permanently.
///
/// ── THE GENERATION COUNTER (S376, P2-2) ─────────────────────────────
///
/// A detection run takes in the worst case eight and a half minutes
/// (RFC 6886 backoff). A network change during this time is the normal case,
/// not the special case — exactly for that there is `onNetworkChanged`.
///
/// Until 08.09.2026 [start] only checked `_disposed` after the `await Future.wait`.
/// [reset] does not abort the running run (there is in
/// Dart no cancellation for a `Future`) and sets the state to
/// `idle`, whereby the lock `_state == acquiring` at the start of [start]
/// let the SECOND run through. Two runs then ran side by side,
/// and the OLD one typically came back first — it had been running longer, after all.
/// Its `_setMapping` set `mappingAcquired`, the seam set
/// `portMappingConfirmed = true` and called `announceOwnEntry(vorrangig:
/// true)`. The entry board then carried the outer address of the
/// OLD network, announced with priority, and the node counted as proven
/// reachable.
///
/// [generation] turns this into a question with an answer: every run remembers
/// its number and checks it after EVERY `await`. [start] increments
/// it, [stop] increments it (and thus also [reset], which only calls
/// `stop`). What comes back too late no longer stores its results
/// — neither the mapping nor the status signals of the NAT assistant.
///
/// THIS ALSO APPLIES TO THE RENEWAL. `_scheduleRenewal` remembers the
/// generation when scheduling; if the timer fires after a network change,
/// it belongs to the old one and does nothing.
library;

import 'dart:async';

import 'package:cleona/core/link_io/nat_pmp.dart';
import 'package:cleona/core/link_io/upnp_igd.dart';

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
  ///
  /// [source] IS MANDATORY AND HAS NO DEFAULT (S377, W-2). Until
  /// 09.09.2026 this factory hard-wrote `'upnp-ip-only'`, because there was only
  /// the UPnP path. Since W-2 the failure branch also asks NAT-PMP
  /// (`nat-pmp-ip-only`), and a fixed label would have shown the gateway's
  /// response as a UPnP measurement. A DEFAULT would be the same
  /// error, only quieter: it enters the wrong value exactly where
  /// a new caller forgets to choose. `source` is read
  /// today only in the log (`tagline/port_map_wiring.dart:121`, and there
  /// only in the branch `mappingAcquired`/`mappingRenewed`) — that nobody
  /// evaluates it today is the reason to be careful, not the
  /// reason to leave it: a wrong value in the log is later read as a
  /// measurement.
  factory PortMapperEvent.externalIpOnly(String ip,
          {required String source}) =>
      PortMapperEvent(
        type: PortMapperEventType.externalIpDiscovered,
        externalIp: ip,
        source: source,
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
class PortMapper {
  final int internalPort;
  final int requestedExternalPort;
  final int requestedLifetime;

  final void Function(String)? _log;
  final NatPmpClient _natPmp;
  final UpnpIgdClient _upnp;

  PortMapperState _state = PortMapperState.idle;
  PortMapperState get state => _state;

  PortMappingResult? _activeMapping;
  String? _mappingSource; // 'nat-pmp', 'pcp', 'upnp'

  Timer? _renewalTimer;
  bool _disposed = false;

  /// The number of the currently valid run. See file header.
  ///
  /// A run counts as outdated as soon as this number has changed;
  /// it may then no longer write anything and no longer report anything.
  int _generation = 0;

  /// Visible for the gate: without it
  /// `smoke_port_mapping_wired` would have to measure the race by its effect, and
  /// an effect that only sometimes occurs is no guard.
  int get generation => _generation;

  // ── The signals of the NAT assistant (§27.9.1) ─────────────────────
  //
  // In V3 they lay on `NatTraversal`. The class no longer exists;
  // the signals arise here and are read here.
  //
  //   `pcpStatus`   — 'ok' | 'failed' | null (not yet attempted)
  //   `upnpStatus`  — 'ok' | 'rejected' (IGD present, mapping refused)
  //                 | 'unavailable' (no IGD found) | null
  //
  // The difference between 'rejected' and 'unavailable' is the whole
  // point: §27.9.2 step 2 tells the user in the first case "UPnP is switched off
  // on your router" and in the second "your router does not speak
  // UPnP". Two different instructions.
  String? _pcpStatus;
  String? get pcpStatus => _pcpStatus;

  String? _upnpStatus;
  String? get upnpStatus => _upnpStatus;

  /// Manufacturer/model from the UPnP `rootDesc`, as soon as one has been read.
  /// Shape like `UpnpRouterInfo.toJson` (`lib/core/platform/router_db.dart`).
  Map<String, dynamic>? get upnpRouterInfoJson => _upnp.lastRouterInfoJson;

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
    void Function(String)? log,
    NatPmpClient? natPmpClient,
    UpnpIgdClient? upnpClient,
  })  : _log = log,
        _natPmp = natPmpClient ?? NatPmpClient(log: log),
        _upnp = upnpClient ?? UpnpIgdClient(log: log);

  /// Start acquiring a port mapping.
  ///
  /// Runs NAT-PMP/PCP and UPnP in parallel. Uses the first successful result.
  Future<void> start() async {
    if (_disposed) return;
    if (_state == PortMapperState.acquiring) return;

    // The number of THIS run. Everything below checks it after every
    // `await` — see file header, section "The generation counter".
    final gen = ++_generation;

    _state = PortMapperState.acquiring;
    _log?.call('Port mapping for port $internalPort is being searched...');

    try {
      // ── THE FIRST RESULT WINS — AND REALLY SO (S380) ───────
      //
      // Here stood `await Future.wait([...])`. That waits for BOTH
      // paths, and the file header above this class had always claimed
      // the opposite ("the first result wins").
      //
      // MEASURED IN THE FIELD on 10.09.2026 on the owner's bootstrap:
      // UPnP had a confirmed mapping after 3.2 s
      // (188.174.130.132:8081, static port forwarding of the FRITZ!Box).
      // NAT-PMP/PCP ran alongside through its four stages — gateway,
      // PCP at the gateway, PCP at two CGNAT addresses — with nine
      // retries each in the RFC 6886 backoff, together around eight and a half
      // minutes. `Future.wait` hangs that long, `_setMapping` never ran,
      // `portMappingConfirmed` stayed `false`, and the node stored
      // no board record.
      //
      // It did not stop at the delay: the run was typically
      // still underway when the next network change incremented the generation
      // — "result of run 1 discarded, meanwhile 3 is running"
      // stands three times in the log of the same day. A node behind a
      // router without NAT-PMP thus NEVER got a mapping, although
      // one of the two paths was done in three seconds.
      //
      // ON A TIE NAT-PMP/PCP, as the file header says: it is
      // the cheaper path and names the outer address in the same
      // dialogue. The priority costs nothing — it only decides who
      // wins when both answer in the same turn.
      final abort = Completer<void>();
      final natPmp = _tryNatPmp(gen, () => abort.isCompleted);
      final upnp = _tryUpnp(gen);
      final winner = await _firstSuccess(natPmp: natPmp, upnp: upnp);
      // THE LOSER IS WAVED OFF, not waited for: as soon as the
      // mapping stands, every further datagram of the other path is
      // traffic without value (working rule 5). `_tryUpnp` has no
      // long tail — it is three SOAP requests —, that is why only
      // the NAT-PMP path has this leash.
      if (!abort.isCompleted) abort.complete();

      if (_disposed || gen != _generation) {
        _log?.call('Port mapping: result of run $gen discarded — '
            'run $_generation is running meanwhile (network change)');
        return;
      }

      if (winner != null) {
        _setMapping(winner.$1, winner.$2);
      } else {
        _state = PortMapperState.failed;
        await _questionOnlyTheOutsideAddress(gen);
      }
    } catch (e) {
      if (_disposed || gen != _generation) return;
      _state = PortMapperState.failed;
      _log?.call('Port mapping: $e');
    }
  }

  /// Stop and clear all mappings.
  ///
  /// INCREMENTS THE GENERATION (S376). A detection run that is currently
  /// running cannot be aborted — it is declared invalid here
  /// and no longer stores its result. This also applies to
  /// [reset], which does nothing more than `stop`.
  Future<void> stop() async {
    _generation++;
    _renewalTimer?.cancel();
    _renewalTimer = null;

    if (_activeMapping != null && _mappingSource != null) {
      // Try to delete the mapping (best effort)
      // BOTH HALVES, but only if there are two (S376). `tcpMapped`
      // says so; an unconditional second teardown would be a packet for
      // a mapping that mostly does not exist.
      final alsoTcp = _activeMapping!.tcpMapped;
      try {
        if (_mappingSource == 'upnp') {
          await _upnp.deleteMapping(
            externalPort: _activeMapping!.externalPort,
            // WITHOUT A SECOND SEARCH. Reasoning at `deleteMapping`.
            knownDevices: _upnp.lastDiscoveredDevices,
          );
          if (alsoTcp) {
            await _upnp.deleteMapping(
              externalPort: _activeMapping!.externalPort,
              protocol: 'TCP',
              knownDevices: _upnp.lastDiscoveredDevices,
            );
          }
        } else {
          await _natPmp.deleteMapping(
              internalPort: internalPort, tcp: alsoTcp);
        }
      } catch (_) {}
    }

    _activeMapping = null;
    _mappingSource = null;
    _state = PortMapperState.idle;
  }

  /// Reset after network change: stop → clear → ready for restart.
  ///
  /// The generation is incremented in [stop] — that is why it does not stand here
  /// again. Two increments would not be wrong (the number
  /// only has to be different), but they would be a second place where
  /// the same rule stands.
  Future<void> reset() async {
    await stop();
  }

  /// Dispose the port mapper permanently.
  ///
  /// MANDATORY on shutdown — see the file header: the
  /// renewal timer otherwise keeps the VM alive.
  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    _state = PortMapperState.disposed;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    _natPmp.dispose();
    await _eventController.close();
  }

  // ── Internal ──────────────────────────────────────────────────────

  /// [gen] is the number of the run this attempt belongs to.
  ///
  /// It is needed because the STATUS SIGNALS of the NAT assistant
  /// (§27.9.1) can also become outdated: a run from the old network that comes back
  /// with `failed` after the network change would otherwise tell the user
  /// "PCP fails at your router" about a network in which it
  /// never tried.
  Future<PortMappingResult?> _tryNatPmp(int gen,
      [bool Function()? abort]) async {
    try {
      final result = await _natPmp.requestMapping(
        internalPort: internalPort,
        externalPort: requestedExternalPort,
        lifetime: requestedLifetime,
        abort: abort,
      );
      if (_disposed || gen != _generation) return null;
      // NAT assistant (§27.9.1): success = PCP ok, null = PCP failed
      // (retries exhausted or error code in the NatPmpClient).
      _pcpStatus = result != null ? 'ok' : 'failed';
      return result;
    } catch (e) {
      _log?.call('NAT-PMP attempt: $e');
      if (_disposed || gen != _generation) return null;
      _pcpStatus = 'failed';
      return null;
    }
  }

  /// [gen] as with [_tryNatPmp] — `_upnpStatus` must not stem from an
  /// outdated run either.
  Future<PortMappingResult?> _tryUpnp(int gen) async {
    // Explicit discover → attempt-mapping split so we can distinguish
    // "no IGD on the network" from "IGD rejected AddPortMapping" for the
    // NAT-Wizard signal (§27.9.1 condition 2).
    List<IgdDevice> devices;
    try {
      devices = await _upnp.discoverDevices();
    } catch (e) {
      _log?.call('UPnP search: $e');
      if (_disposed || gen != _generation) return null;
      _upnpStatus = 'unavailable';
      return null;
    }

    if (_disposed || gen != _generation) return null;

    if (devices.isEmpty) {
      // SSDP returned no IGD after the discovery deadline. UPnP is either
      // disabled on the router, not supported, or blocked by the firewall.
      _upnpStatus = 'unavailable';
      return null;
    }

    try {
      final result = await _upnp.requestMapping(
        internalPort: internalPort,
        externalPort: requestedExternalPort,
        leaseDuration: requestedLifetime,
        knownDevices: devices,
      );
      if (_disposed || gen != _generation) return null;
      // A working IGD responded but may have rejected the mapping (error 718
      // conflict retry also failed, or admin-disabled AddPortMapping while
      // advertising the service). Either way: rejected, not unavailable.
      _upnpStatus = result != null ? 'ok' : 'rejected';
      return result;
    } catch (e) {
      _log?.call('UPnP attempt: $e');
      if (_disposed || gen != _generation) return null;
      // IGD was reachable during discovery but the mapping call threw.
      // Classify as rejected rather than unavailable — the router is there.
      _upnpStatus = 'rejected';
      return null;
    }
  }

  /// THE FAILURE BRANCH, AND ONLY IT: no mapping — but perhaps the
  /// outer address.
  ///
  /// ── WHEN IT RUNS ────────────────────────────────────────────────
  ///
  /// Exclusively when NEITHER NAT-PMP/PCP NOR UPnP brought a mapping.
  /// The only call stands in the `else` of
  /// `if (result != null)` in [start]. In the success case this method
  /// is not entered, and thus NO additional datagram arises —
  /// that is the assurance from working rule 5, and
  /// `smoke_port_mapping_wired` measures it by behaviour (section 10),
  /// not by source text.
  ///
  /// ── WHY TWO SOURCES (S377, W-2) ────────────────────────────────
  ///
  /// Until 09.09.2026 this branch asked ONLY the IGD. If it was silent —
  /// no IGD found, or no usable address —, it ended, and
  /// the node did not know its outer address.
  /// `NatPmp.queryExternalIp` existed (`nat_pmp.dart`), but in `lib/`
  /// nobody called it: when `nat_pmp.dart` was brought back (S373)
  /// only the UPnP path of this branch came along.
  ///
  /// What that costs stands in §25.9: "A node that does not know its
  /// external address publishes its private one, and the cold-start board
  /// fills with records nobody can dial." Exactly this finding killed
  /// the cold start on beta in S373 — 15 of 17 board entries private.
  ///
  /// ── ORDER AND PRICE ─────────────────────────────────────────
  ///
  /// UPnP first, because its devices are already known from [start]
  /// (`lastDiscoveredDevices`) and the question there costs no second
  /// SSDP search. Only if nothing usable comes from there
  /// does a NAT-PMP dialogue go to the gateway: at most nine datagrams
  /// in the RFC 6886 backoff, two on a response (header of
  /// `nat_pmp.dart`). The gateway is NOT determined anew — it is
  /// the one that [_tryNatPmp] has just used
  /// (`NatPmpClient.lastGatewayIp`).
  ///
  /// ── THE GENERATION ENCLOSES BOTH QUESTIONS ───────────────────────
  ///
  /// The NAT-PMP backoff takes up to eight and a half minutes in the field. A
  /// network change in this window makes the response worthless: it names
  /// the outer address of the OLD network. That is why the check
  /// `gen != _generation` stands behind EVERY `await` of this method, and an
  /// outdated run reports nothing any more.
  Future<void> _questionOnlyTheOutsideAddress(int gen) async {
    bool usable(String? ip) =>
        ip != null && ip.isNotEmpty && ip != '0.0.0.0';

    // (1) UPnP — unchanged. The devices stem from requestMapping(),
    //     there is no second SSDP search.
    try {
      final devices = _upnp.lastDiscoveredDevices;
      if (devices.isNotEmpty) {
        final externalIp = await _upnp.getExternalIp(knownDevices: devices);
        if (_disposed || gen != _generation) return;
        if (usable(externalIp)) {
          _log?.call(
              'No mapping, but external address via UPnP: $externalIp');
          _emitEvent(PortMapperEvent.externalIpOnly(externalIp!,
              source: 'upnp-ip-only'));
          return;
        }
        _log?.call('No mapping — no external address from the IGD');
      } else {
        _log?.call('No mapping — no IGD found');
      }
    } catch (e) {
      _log?.call('No mapping — query of the external address '
          'via UPnP: $e');
    }

    if (_disposed || gen != _generation) return;

    // (2) NAT-PMP — the part that was missing until S377.
    try {
      final externalIp =
          await _natPmp.queryExternalIp(gatewayIp: _natPmp.lastGatewayIp);
      if (_disposed || gen != _generation) return;
      if (usable(externalIp)) {
        _log?.call('No mapping, but external address via NAT-PMP: '
            '$externalIp');
        _emitEvent(PortMapperEvent.externalIpOnly(externalIp!,
            source: 'nat-pmp-ip-only'));
        return;
      }
      _log?.call('No mapping — the gateway does not name an external '
          'address either');
    } catch (e) {
      _log?.call('No mapping — query of the external address '
          'via NAT-PMP: $e');
    }
  }

  /// The first of the two procedures that delivers a mapping — with
  /// priority for NAT-PMP/PCP on a tie.
  ///
  /// `null` means: BOTH are done and neither has anything. A `null`
  /// from one side thus does not end the run; only the second one does.
  /// Exactly that distinguishes this function from `Future.any`, which would
  /// already come back on the first failure.
  ///
  /// An exception counts as a failure and is reported — otherwise
  /// it would hang as an unhandled error in the zone handler
  /// after the caller has long since moved on.
  Future<(PortMappingResult, String)?> _firstSuccess({
    required Future<PortMappingResult?> natPmp,
    required Future<PortMappingResult?> upnp,
  }) {
    final done = Completer<(PortMappingResult, String)?>();
    var open = 2;
    void observe(Future<PortMappingResult?> f, String source) {
      f.then(
        (r) {
          if (done.isCompleted) return;
          if (r != null) {
            done.complete((r, source));
          } else if (--open == 0) {
            done.complete(null);
          }
        },
        onError: (Object e) {
          _log?.call('Port mapping via $source: $e');
          if (done.isCompleted) return;
          if (--open == 0) done.complete(null);
        },
      );
    }

    // NAT-PMP REGISTERED FIRST, and that is the tie priority:
    // if both come back in the same turn, its `then` runs first.
    observe(natPmp, 'nat-pmp');
    observe(upnp, 'upnp');
    return done.future;
  }

  void _setMapping(PortMappingResult result, String source) {
    _activeMapping = result;
    _mappingSource = source;
    _state = PortMapperState.mapped;

    _log?.call('Port mapping via $source: '
        '${result.externalIp}:${result.externalPort} '
        '(lifetime ${result.lifetimeSeconds}s, '
        '${result.tcpMapped ? 'UDP+TCP' : 'UDP only'})');

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

    // The generation this mapping belongs to. If the timer fires
    // after a network change, it is a different one and the run stays silent.
    final gen = _generation;

    // Renewal at lifetime/2. For permanent leases (lifetime=0): 30 minutes.
    final renewalSeconds =
        result.lifetimeSeconds > 0 ? result.lifetimeSeconds ~/ 2 : 1800;

    _log?.call('Renewal scheduled in ${renewalSeconds}s');

    _renewalTimer = Timer(Duration(seconds: renewalSeconds), () {
      if (!_disposed && gen == _generation) _renewMapping(gen);
    });
  }

  Future<void> _renewMapping(int gen) async {
    if (_disposed || gen != _generation) return;
    if (_activeMapping == null || _mappingSource == null) return;

    _log?.call('Port mapping is being renewed via $_mappingSource...');

    PortMappingResult? result;

    try {
      // `tryTcp` from the previous result: if the TCP half was refused on
      // creation, it is not asked for anew every hour here
      // (working rule 5). A gateway that changes its mind
      // is asked again at the next detection run — and that
      // occurs on every network change.
      final tcpRenew = _activeMapping!.tcpMapped;
      if (_mappingSource == 'upnp') {
        result = await _upnp.requestMapping(
          internalPort: internalPort,
          externalPort: _activeMapping!.externalPort,
          leaseDuration: requestedLifetime,
          tryTcp: tcpRenew,
          knownDevices: _upnp.lastDiscoveredDevices.isEmpty
              ? null
              : _upnp.lastDiscoveredDevices,
        );
      } else {
        result = await _natPmp.requestMapping(
          internalPort: internalPort,
          externalPort: _activeMapping!.externalPort,
          lifetime: requestedLifetime,
          tryTcp: tcpRenew,
        );
      }
    } catch (e) {
      _log?.call('Renewal: $e');
    }

    if (_disposed || gen != _generation) return;
    if (_state == PortMapperState.idle) return;

    if (result != null) {
      _activeMapping = result;
      _log?.call('Mapping renewed: ${result.externalPort} '
          '(${result.lifetimeSeconds}s)');

      _emitEvent(PortMapperEvent(
        type: PortMapperEventType.mappingRenewed,
        mapping: result,
        externalIp: result.externalIp,
        source: _mappingSource,
      ));

      _scheduleRenewal(result);
    } else {
      // Retry once after 5 seconds
      _log?.call('Renewal failed — one attempt in 5 s');
      _renewalTimer = Timer(const Duration(seconds: 5), () async {
        if (_disposed || gen != _generation) return;
        if (_state == PortMapperState.idle) return;

        PortMappingResult? retryResult;
        try {
          final tcpRepeat = _activeMapping?.tcpMapped ?? false;
          if (_mappingSource == 'upnp') {
            retryResult = await _upnp.requestMapping(
              internalPort: internalPort,
              externalPort: _activeMapping?.externalPort ?? internalPort,
              leaseDuration: requestedLifetime,
              tryTcp: tcpRepeat,
              knownDevices: _upnp.lastDiscoveredDevices.isEmpty
                  ? null
                  : _upnp.lastDiscoveredDevices,
            );
          } else {
            retryResult = await _natPmp.requestMapping(
              internalPort: internalPort,
              externalPort: _activeMapping?.externalPort ?? 0,
              lifetime: requestedLifetime,
              tryTcp: tcpRepeat,
            );
          }
        } catch (_) {}

        if (_disposed || gen != _generation) return;
        if (_state == PortMapperState.idle) return;

        if (retryResult != null) {
          _activeMapping = retryResult;
          _log?.call('Mapping renewed (retry): '
              '${retryResult.externalPort}');
          _emitEvent(PortMapperEvent(
            type: PortMapperEventType.mappingRenewed,
            mapping: retryResult,
            externalIp: retryResult.externalIp,
            source: _mappingSource,
          ));
          _scheduleRenewal(retryResult);
        } else {
          // Both attempts failed — mapping lost
          _log?.call('Mapping lost — renewal without success even after '
              'retry');
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
