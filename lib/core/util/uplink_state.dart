// The network kind of this node (§26.6.1).
//
// Until S409 this file also carried `UplinkState` ("does this node get
// outside at all?", S373), fed by the outcome of every Nostr publication.
// Its only reader was the V4.1 delivery layer (`lib/core/tagline/`), which
// fell in S408-P23; in 4.2 the delivery layer answers that question itself
// (v4_2 §11.8.4, §22.7). The class fell with D-83 (v4_2 §22.4.5:
// `lib/core/util/` carries "network kind").
//
// `lib/core/util/` is the lowest level and imports nothing from the
// project. `dart:io` because the node reads the network kind from the
// operating system, and that WITHOUT a Flutter plugin, because the daemon
// has none (measured S388: `service_daemon.dart` does not know
// `connectivity_plus`).
library;

import 'dart:io';

// ═══════════════════════════════════════════════════════════════════════
// The network kind — does the path out cost money? (S389, package 8 = B)
// ═══════════════════════════════════════════════════════════════════════
//
// Owner decision 15.09.2026: the detection of metered connections is
// built — desktop hotspot and iOS `NWPath.isExpensive`. It is a
// limit for LARGE transfers (fetching the update binary,
// 100-190 MB), **not** for the manifest slot: that is asked even over
// mobile (package 9 = A, a few KB per edge).
//
// v4_2 §26.6.1: "Data-saving mode suspends the fetch path over metered
// connections; pieces arriving by cover fill are still kept."
//
// ── NO TICK ──────────────────────────────────────────────────────────
//
// No timer, no probe, no socket. Reading happens at
// the edges at which something happens anyway — start, network change, new
// neighbour, app opened (§8.2) — and the last read value is
// synchronously available, because the consumer (`UpdateAngebot.holenGesperrt`)
// asks synchronously.
//
// ── WHY A PROCESS CALL AND NOT A PLUGIN ────────────────────────────
//
// Measured in S388: the only source of the app was `connectivity_plus`
// (a Flutter plugin) plus an Android method channel; the daemon
// (Linux/Windows/macOS) had NONE — "a laptop on the phone hotspot keeps fetching
// there" (S388-BAU-UPDATE, section 5, side effects). A
// process call runs in the daemon as in the app and needs no
// plugin registration.

/// Whether the active connection is METERED — a state, node-wide.
///
/// Node-wide and not per identity: a process carries several identities,
/// but exactly one
/// network connection.
final class NetworkKind {
  static final NetworkKind instance = NetworkKind._();

  NetworkKind._();

  bool? _metered;
  DateTime? _readAt;

  /// How often an edge has reported something. A zero means "nobody
  /// reads the network kind" — a finding about the wiring, not an
  /// operating state (like [UplinkState.observations]).
  int readings = 0;

  /// `null`: never read yet. **The consumer decides what he makes of
  /// the ignorance** — on mobile an unread network kind counts as
  /// metered (`_updateHolenGesperrt` in `lib/main.dart`), on the desktop
  /// as unmetered. This class does not guess.
  bool? get metered => _metered;

  DateTime? get readAt => _readAt;

  /// The EDGE. [value] `null` means "the platform does not say" — then
  /// the last known value stays, instead of replacing it with a
  /// nothing.
  ///
  /// Returns `true` if the value has CHANGED; exactly then does
  /// the caller have an edge to report (`UpdateAngebot.netzartGeaendert`).
  /// Without this return value every reading would report an edge, and a
  /// waiting collection would start anew at every reading.
  bool note({required bool? value, DateTime? now}) {
    readings++;
    if (value == null) return false;
    final before = _metered;
    _metered = value;
    _readAt = now ?? DateTime.now();
    return before != value;
  }

  /// Resets the state — exclusively for tests.
  void resetForTest() {
    _metered = null;
    _readAt = null;
    readings = 0;
  }
}

/// How long a call of the operating system may take at most.
/// Longer means: the answer does not come, and "unknown" is better than
/// an edge that hangs.
const Duration kNetworkKindDeadline = Duration(seconds: 3);

/// Reads the network kind from the operating system. `null` = unknown.
///
/// The caller is the EDGE; this function has no clock.
///
/// | Platform | Source | Status |
/// |---|---|---|
/// | Linux | NetworkManager via `nmcli`, device of the default route | built, measured |
/// | Windows | `NetworkInformation.GetConnectionCost()` via PowerShell | built, NOT measured (no Windows machine in the run) |
/// | macOS | — | `NWPath.isExpensive` needs Swift; not built, see report |
/// | Android/iOS | — | there the app reads the system channel (`lib/main.dart`) |
///
/// **The direction of the error is chosen:** whoever does not answer counts as
/// UNMETERED (`null` -> the consumer decides, and on the desktop
/// that means "fetch"). The other way round a desktop without NetworkManager
/// would never have fetched an update again — a silent total failure of distribution
/// against an occasionally too expensive transfer.
Future<bool?> networkKindFromSystem({
  Future<ProcessResult> Function(String command, List<String> arguments)?
      start,
}) async {
  final run = start ??
      (b, a) => Process.run(b, a).timeout(kNetworkKindDeadline,
          onTimeout: () => ProcessResult(0, 124, '', 'Time expired'));
  try {
    if (Platform.isLinux) {
      final route = await run('ip', ['-o', 'route', 'show', 'default']);
      final device = _deviceOutRoute(route.exitCode == 0 ? '${route.stdout}' : '');
      if (device == null) return null;
      final r = await run(
          'nmcli', ['-t', '-f', 'GENERAL.METERED', 'device', 'show', device]);
      if (r.exitCode != 0) return null;
      return _nmcliMetered('${r.stdout}');
    }
    if (Platform.isWindows) {
      final r = await run('powershell', [
        '-NoProfile',
        '-Command',
        r'''[Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime] > $null; $p = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile(); if ($p -eq $null) { 'unbekannt' } else { $p.GetConnectionCost().NetworkCostType }''',
      ]);
      if (r.exitCode != 0) return null;
      return _windowsMetered('${r.stdout}');
    }
  } on Object {
    // A missing tool, a sandbox without process rights: "unknown"
    // is the right answer, not a crash at an edge.
    return null;
  }
  return null;
}

/// `default via 192.0.2.100 dev wlp113s0 proto dhcp …` -> `wlp113s0`.
String? _deviceOutRoute(String output) {
  for (final line in output.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    final i = parts.indexOf('dev');
    if (i >= 0 && i + 1 < parts.length) return parts[i + 1];
  }
  return null;
}

/// `GENERAL.METERED:yes (guessed)` -> `true`.
///
/// **A "guessed yes" counts too.** NetworkManager guesses exactly where it
/// matters: with a mobile modem and with an Android hotspot
/// that reports itself as metered. Whoever only takes the explicit "yes"
/// fails to recognise precisely the case for which this decision was built.
bool? _nmcliMetered(String output) {
  final line = output
      .split('\n')
      .map((z) => z.trim())
      .firstWhere((z) => z.startsWith('GENERAL.METERED:'), orElse: () => '');
  if (line.isEmpty) return null;
  final value = line.substring('GENERAL.METERED:'.length).trim();
  if (value.startsWith('yes')) return true;
  if (value.startsWith('no')) return false;
  return null; // „unknown"
}

/// `NetworkCostType`: `Unrestricted` = 1, `Fixed` = 2, `Variable` = 3,
/// `Unknown` = 0. Fixed and Variable are metered — Windows reports exactly
/// that for a hotspot and for a WLAN marked as metered.
bool? _windowsMetered(String output) {
  final value = output.trim().toLowerCase();
  if (value.isEmpty || value == 'unbekannt') return null;
  if (value == 'unrestricted' || value == '1') return false;
  if (value == 'fixed' || value == '2') return true;
  if (value == 'variable' || value == '3') return true;
  return null;
}
