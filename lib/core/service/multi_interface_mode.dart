// The "multi-interface" setting and its two JSON converters.
//
// EXTRACTED ON 2026-08-31 (CUT, step 0) from
// `lib/core/network/multi_interface.dart`.
//
// WHY. `multi_interface.dart` is real V3 network logic: `MultiInterfaceManager`
// enumerates local interfaces, binds one UDP socket per interface and
// keeps their send state (`lib/core/network/multi_interface.dart`,
// `dart:io` sockets, ~450 lines). From outside, however, only a
// three-valued enum plus two string converters for the profile JSON are
// used from it:
//
//   lib/core/service/service_interface.dart:3  — only `MultiInterfaceMode`
//   lib/ui/screens/settings_screen.dart:23     — only `MultiInterfaceMode`
//   lib/core/ipc/ipc_server.dart:12            — only `modeFromString`
//   lib/core/ipc/ipc_client.dart:16            — `MultiInterfaceMode` + both
//   lib/core/service/cleona_service.dart:51    — `MultiInterfaceMode` + both
//
// Five import edges of the application layer onto `lib/core/network/`, not
// a single one of them for a socket. The same error class as D-5 with
// `LocalDiscovery.discoveryPort`: a value in the wrong place drags the
// whole layer along behind it.
//
// NO `export` AS A SHORTCUT. `multi_interface.dart` could re-export this
// file and leave all callers unchanged — the guard in
// `test/smoke/smoke_link_io_milestone.dart` explicitly counts an `export`
// of the V3 tree as an edge (see its reversal probe "an export of the V3
// tree counts as an edge"), and it is right: a re-export is an edge that
// is merely written differently. The callers have been switched over
// instead.
//
// ONE PLACE OF DEFINITION, NO FORWARDER. `MultiInterfaceManager.modeToString`
// and `.modeFromString` have moved here and been DELETED there, not left
// standing as a forwarding — that is the same procedure with which AP-3a
// stage 1 moved `DataPort.drawDataPort`, and for the same reason
// ("five accesses instead of one", AP-1b §3b).
//
// WHY `lib/core/service/` AND NOT `lib/core/util/`. The mode is a user
// setting that lies in the profile JSON (`multi_interface_mode.json`,
// `cleona_service.dart:5431`) and travels over IPC between GUI and daemon;
// its reader is the service layer. `lib/core/network/transport.dart`
// imported it from here — an edge network -> service that followed the
// direction of the CUT and died with `lib/core/network/` (2026-08-31;
// zero files there, measured 2026-09-03). The readers have since been
// exclusively service and IPC.

library;

/// User-facing multi-interface mode setting.
/// Persisted as `multi_interface_mode` in the profile JSON.
enum MultiInterfaceMode {
  /// Single socket (0.0.0.0), no multi-path. Saves battery and
  /// mobile data. Identical to pre-23.2 behavior.
  off,

  /// Parallel send on all active interfaces for every packet. Maximum
  /// reliability at the cost of doubled data consumption on metered
  /// connections.
  on,

  /// Smart mode (default): use the cheapest interface (wifi preferred) for
  /// normal sends. Parallel send on all interfaces only for:
  ///   - ACK-timeout retransmits
  ///   - High-priority messages (e.g. call signaling)
  /// Balances reliability vs. data cost.
  auto;

  /// JSON serialization of a mode (for profile persistence and IPC).
  ///
  /// Stood until 2026-08-31 as `MultiInterfaceManager.modeToString` in
  /// `lib/core/network/multi_interface.dart:441`; deleted there.
  static String modeToString(MultiInterfaceMode mode) => mode.name;

  /// Inverse of [modeToString].
  ///
  /// The two fallbacks are DELIBERATELY DIFFERENT and come unchanged from
  /// the predecessor version (`lib/core/network/multi_interface.dart:443`):
  /// `null` — i.e. no stored value at all — yields [off], a STORED but
  /// unknown value yields [auto]. The former is the first run without a
  /// profile entry, the latter an entry from another version.
  static MultiInterfaceMode modeFromString(String? s) {
    if (s == null) return MultiInterfaceMode.off;
    return MultiInterfaceMode.values.firstWhere(
      (e) => e.name == s,
      orElse: () => MultiInterfaceMode.auto,
    );
  }
}
