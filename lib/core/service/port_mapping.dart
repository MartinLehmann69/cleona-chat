/// The port mapping at the own router — task D, V4.2 §7.3, §5.4.
///
/// ── WHERE FROM ───────────────────────────────────────────────────────
///
/// `lib/core/link_io/nat_pmp.dart`, `upnp_igd.dart` and `port_mapper.dart`
/// have been in the tree since the retrieval of 07.09.2026 (owner approval),
/// but hang exclusively off `lib/core/tagline/port_map_wiring.dart`
/// — and that in turn off `v41_attach.dart`, whose `attachV41` has had
/// no caller since S388. Measured 17.09.2026: no node of the
/// mycelium line maps a port.
///
/// This file is the NEW seam — for the mycelium line, on [Host.port]
/// instead of on `V41Node`. `port_mapper.dart` (`PortMapper`) stays
/// unchanged: the translation between it and the application is all
/// that was missing, exactly as `lib/core/tagline/port_map_wiring.dart` did
/// it for the superseded layer (`PortMapBinding`). This class is its
/// counterpart.
///
/// ── WHAT IT DOES, AND WHAT IT EXPLICITLY DOES NOT DO ─────────────────
///
/// It starts/renews the coordinator (§5.4, third clock — only the own
/// router, never the data port) at EXACTLY two edges (start, network change),
/// both via [toEdge]. Whether it is the first or a later one, it decides
/// from its own state, not the caller: the first starts the
/// coordinator, every further one is a network-change reset (otherwise the old
/// mapping points into a network that is no longer the own one — the same
/// reasoning as in `PortMapBinding.onNetworkChanged`).
///
/// It publishes NOTHING. With `PortMapBinding` that was its own
/// task (`V41Node.advertiseMapped`, `announceOwnEntry`) — here it is
/// deliberately not so: the card/the board of the mycelium line does not
/// belong to this class, and a write access from `lib/core/service/`
/// would be a second place triggering the same publication. Instead it
/// reports ONLY via [onMapping] — whoever is to carry the address into an
/// announcement (§11.9, the board) wires that against
/// this one field.
///
/// [layDown] IS MANDATORY on shutdown — see the file header of
/// `port_mapper.dart`: otherwise the renewal timer keeps the Dart VM alive
/// for up to an hour.
///
/// ── TASK E4 (S391): THE IPv6 PINHOLE ────────────────────────────────
///
/// §7.3 demands "a mapping (IPv4) and a pinhole (IPv6)". The IPv4 half
/// is [PortMapper], the IPv6 half [Ipv6Pinhole]
/// (`lib/core/link_io/ipv6_pinhole.dart`). Both run at the same edge
/// SIDE BY SIDE and share ONE [UpnpIgdClient] — so the
/// edge costs one SSDP search, not two.
///
/// * [mappingProven] is true when an IPv4 mapping OR an
///   IPv6 pinhole was granted and has not expired (§11.8a).
/// * [onMapping] also fires for the pinhole — with the own
///   global IPv6 address and the data port.
/// * Switch off ([active] `false`, §12.7): neither mapping nor pinhole,
///   no packet.
/// * [layDown] clears both: the pinhole is deleted at the router,
///   the IPv4 mapping torn down via `PortMapper.stop`.
library;

import 'dart:async';
import 'dart:io';

import 'package:cleona/core/link_io/ipv6_pinhole.dart';
import 'package:cleona/core/link_io/nat_pmp.dart';
import 'package:cleona/core/link_io/port_mapper.dart';
import 'package:cleona/core/link_io/upnp_igd.dart';

export 'package:cleona/core/link_io/ipv6_pinhole.dart'
    show Ipv6Pinhole, Ipv6Environment, Pinhole, PcpPinholeClient;
export 'package:cleona/core/link_io/port_mapper.dart'
    show PortMapper, PortMapperEvent, PortMapperEventType, PortMapperState;

/// The running port mapping of a host port (task D).
///
/// One object per host, bound via `mycelium_seam.dart`
/// (`portMappingToEdge`/`portMappingLayDown`/`portMappingFrom`).
final class PortMapping {
  final PortMapper _mapper;
  final Ipv6Pinhole _pinhole;
  late final StreamSubscription<PortMapperEvent> _sub;

  /// The setting W9: `false` means — no router is asked, no
  /// datagram is created. [toEdge] then becomes a no-op; [_mapper] does
  /// exist (for a uniform state), but never starts.
  final bool active;

  bool _started = false;

  /// Fires with the mapped OUTER address — ONLY on a
  /// confirmed mapping, never on a mere `externalIpDiscovered`
  /// without an open port (an address without a mapping is an address at
  /// which nobody listens — the same reasoning as in the file header of
  /// `port_map_wiring.dart`). Whoever hangs the publication (§11.9) off it
  /// sets this field.
  void Function(InternetAddress outside, int port)? onMapping;

  /// The router has granted an IPv4 mapping OR an IPv6 pinhole, and
  /// it has not expired (§11.8a, S391/E4).
  bool get mappingProven => _mapper.hasMapping || _pinhole.proven;

  /// Per address type — for the keep-alive (§8.1): on a mapped
  /// path the router keeps it open, there the keep-alive is dropped.
  bool get ipv4Proven => _mapper.hasMapping;
  bool get ipv6Proven => _pinhole.proven;

  /// The IPv6 half — for an integrator and the guard.
  Ipv6Pinhole get pinhole => _pinhole;

  /// The coordinator itself — for the NAT assistant (§27.9) and for
  /// an integrator who needs the current address without waiting for the
  /// next event (`mapper.externalIp`/`externalPort`).
  PortMapper get mapper => _mapper;

  /// [pinhole] replaces the IPv6 half (guard). Without it an
  /// [Ipv6Pinhole] is created that shares ONE [UpnpIgdClient] with the
  /// [PortMapper] — unless [mapper] is injected; then the pinhole gets
  /// [upnpClient] or its own.
  factory PortMapping({
    required int port,
    bool active = true,
    void Function(String)? log,
    PortMapper? mapper,
    NatPmpClient? natPmpClient,
    UpnpIgdClient? upnpClient,
    Ipv6Pinhole? pinhole,
  }) {
    final upnp = upnpClient ?? UpnpIgdClient(log: log);
    return PortMapping._(
      active,
      mapper ??
          PortMapper(
            internalPort: port,
            // THE SAME PORT OUTSIDE AS INSIDE, if the router plays along —
            // reasoning as in `PortMapBinding.bind` in
            // `port_map_wiring.dart`: the host port is the ONE
            // data port (V4.2 §4.5.1), for UDP and the TCP fallback.
            requestedExternalPort: port,
            log: log,
            natPmpClient: natPmpClient,
            upnpClient: upnp,
          ),
      pinhole ?? Ipv6Pinhole(port: port, log: log, upnp: upnp),
    );
  }

  PortMapping._(this.active, this._mapper, this._pinhole) {
    _sub = _mapper.events.listen(_onEvent);
    // The pinhole reports via the same callback — [onMapping] is only
    // read when firing, a callback set later applies.
    _pinhole.onGranted = (address, port) => onMapping?.call(address, port);
  }

  void _onEvent(PortMapperEvent e) {
    switch (e.type) {
      case PortMapperEventType.mappingAcquired:
      case PortMapperEventType.mappingRenewed:
        final m = e.mapping;
        if (m == null) return;
        // '0.0.0.0' means "mapping yes, outer address unknown" (NAT-
        // PMP cases without an answered address query) — an announcement on it
        // would be worse than none.
        if (m.externalIp.isEmpty || m.externalIp == '0.0.0.0') return;
        final addr = InternetAddress.tryParse(m.externalIp);
        if (addr == null) return;
        onMapping?.call(addr, m.externalPort);
      case PortMapperEventType.mappingLost:
      case PortMapperEventType.externalIpDiscovered:
        // No event for the integrator: `mappingProven` reports the
        // loss live, without a second channel that could go stale, and an
        // address WITHOUT a mapping (`externalIpDiscovered` alone) is never
        // announced (see file header).
        break;
    }
  }

  /// Start OR network change — the same method, because §7.3 asks the same
  /// router the same way at both edges. Whether it is the first or a
  /// later edge is in [_started]: the first starts the
  /// coordinator, every further one first clears the old mapping
  /// (`PortMapper.reset`) — otherwise it points into the old network until a new
  /// answer is there.
  ///
  /// With [active] `false`: no-op, no datagram (W9).
  Future<void> toEdge() async {
    if (!active) return;
    final first = !_started;
    _started = true;
    // IPv4 and IPv6 SIDE BY SIDE (S391/E4): the RFC 6886 backoff of the
    // IPv4 half must not delay the pinhole by minutes.
    // [Ipv6Pinhole.toEdge] clears an old pinhole itself.
    await Future.wait<void>([
      () async {
        if (!first) await _mapper.reset();
        await _mapper.start();
      }(),
      _pinhole.toEdge(),
    ]);
  }

  /// MANDATORY on shutdown. See file header.
  ///
  /// Clears BOTH (S391/E4): the pinhole is deleted at the router
  /// (1 datagram or 1 SOAP request), the IPv4 mapping torn down via
  /// `PortMapper.stop` (same rule: only if one exists).
  /// Harmless even with [active] `false` — then none exists, and
  /// no packet is created.
  Future<void> layDown() async {
    await _sub.cancel();
    await Future.wait<void>([
      _pinhole.layDown(),
      _mapper.stop(),
    ]);
    await _mapper.dispose();
  }
}
