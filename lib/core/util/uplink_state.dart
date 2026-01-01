// The internet leg — does this node get outside at all?
//
// ── WHY THIS FILE EXISTS (S373) ────────────────────────────────────
//
// The question was already answered, the answer just landed nowhere.
// `NostrProvider.publish` counts at EVERY publication how many
// relays answered, and writes the number into a log line
// (`rendezvous/nostr_provider.dart`, "Nostr publish: $successCount/…").
// Measured on 06.09.2026: there was not a single reader of this
// quantity in `lib/`. A node thus knew that it reaches the internet, and
// could tell nobody — neither itself nor its neighbours.
//
// ── NO SECOND RHYTHM, NOT A SINGLE ADDITIONAL PACKET ───────────
//
// Working rule #5. This file has no timer, no probe and no
// socket. It is fed exclusively by an event that takes place
// anyway: the outcome of an external rendezvous. What stands here
// is the EDGE of this event, not its repetition.
//
// A reachability check of its own (a "ping into the internet") would be the
// obvious alternative and is expressly rejected: it costs
// traffic, it puts a regular pattern on the exit, and it
// answers a DIFFERENT question — "is any target reachable" instead of
// "does the path via which this node actually works outside
// carry".
//
// ── WHY `lib/core/util/` AND NOT `tagline/` OR `rendezvous/` ─────
//
// Because both sides need it and neither of the two may know the other:
// `rendezvous/` WRITES (the event arises there), `tagline/`
// READS (the LAN call is built there and the cover stream dimensioned). An
// edge from the delivery layer into the rendezvous — or vice versa — would be
// a new dependency for a single `bool`. `util/` is the
// lowest level and imports nothing except the SDK.
//
// Until S389 here stood "imports nothing except `dart:core`". With [NetworkKind]
// (below) `dart:io` is added: the node reads the network kind from the
// operating system, and that WITHOUT a Flutter plugin, because the daemon has none
// (measured S388: `service_daemon.dart` does not know `connectivity_plus`).
// A dependency on another layer of the project is not added
// by this — the statement the note was about holds.
//
// ── WHAT THIS STATE IS NOT ───────────────────────────────────────
//
// It is NO statement about whether the node is REACHABLE from outside.
// A phone behind CGNAT has an internet leg and is nonetheless not
// dialable from outside. The two questions regularly coincide and are
// different; only the first stands here.
library;

import 'dart:io';

/// How long a success counts as a statement about the present.
///
/// ── WHERE THE 30 MINUTES COME FROM ───────────────────────────────────────
///
/// From the tick of the source, not from a feeling. This
/// state is fed by the external rendezvous; if nothing runs for longer than one such
/// round, there is simply no fresh observation any more. A
/// statement that is older than the interval of its own source
/// claims knowledge it does not have.
///
/// The direction of the error is deliberately chosen: after expiry the
/// state says "I do not know" (= [hasUplink] false), not "I have
/// one". A node that falsely reports NO internet leg is not
/// chosen as a relay by neighbours — that costs a detour. A node
/// that falsely reports ONE pulls neighbours onto a dead path. The
/// first error is the cheaper one.
const Duration kUplinkStaleAfter = Duration(minutes: 30);

/// How many complete failures in a row drop the leg.
///
/// A failure here is already "NOT a single relay has answered"
/// (`successCount == 0`), so not a single slip, but the
/// failure of all asked remote sides at once. Nonetheless one
/// of them is not yet a statement about the leg: a network change in the middle of a
/// round, a one-second WLAN outage or a block against exactly these
/// relays look the same from here. Two in a row are.
const int kUplinkFailureTolerance = 2;

// In order: [UplinkState] (does the node get out?) and [NetworkKind]
// (does the path out cost money?). Two questions, two states — a phone in
// flight mode with WLAN has an internet leg and no metered connection,
// a laptop on a hotspot has both.

/// Whether this node gets into the internet — a state, node-wide.
///
/// NODE-WIDE AND NOT PER IDENTITY, for the same reason as with the
/// cover stream (`CoverSaver`): a process can carry several identities,
/// but it has exactly one network connection. The question "do I get
/// out" is a question to the machine, not to the user.
final class UplinkState {
  static final UplinkState instance = UplinkState._();

  UplinkState._();

  DateTime? _reachedAt;
  DateTime? _lastAttemptAt;
  int _failuresSinceSuccess = 0;

  /// How many edges have come in in total. Only for the statistics
  /// and for tests — a zero here means "nobody reports anything", and that
  /// is a finding about the wiring, not an operating state.
  int observations = 0;

  /// Reports the outcome of ONE external rendezvous round.
  ///
  /// [reached] is true if at least one remote side has answered.
  /// A round without any asked remote side is NO observation and
  /// does not belong here — the caller checks that (see
  /// `NostrProvider`: with an empty relay list the call is dropped).
  void note({required bool reached, DateTime? now}) {
    final t = now ?? DateTime.now();
    observations++;
    _lastAttemptAt = t;
    if (reached) {
      _reachedAt = t;
      _failuresSinceSuccess = 0;
    } else {
      _failuresSinceSuccess++;
    }
  }

  /// When a remote side last answered, or `null`.
  DateTime? get reachedAt => _reachedAt;

  /// When a round last ran at all, or `null`.
  DateTime? get lastAttemptAt => _lastAttemptAt;

  /// How old the last successful observation is, or `null` if there
  /// is none. **The age belongs to the statement** — a "yes" from two
  /// hours ago is something different from one from two minutes ago, and whoever only
  /// passes on the `bool` loses exactly this difference.
  Duration? age({DateTime? now}) {
    final r = _reachedAt;
    if (r == null) return null;
    return (now ?? DateTime.now()).difference(r);
  }

  /// How many complete failures since the last success.
  int get failuresSinceSuccess => _failuresSinceSuccess;

  /// Does this node get into the internet?
  ///
  /// Three conditions, and all three must hold:
  ///
  ///  1. There has been a success at all at some point. **Without observation
  ///     the answer is "no" and not "maybe"** — the value is
  ///     written below into a call into the LAN, and a call is a
  ///     claim. Whoever knows nothing claims nothing.
  ///  2. The success is younger than [kUplinkStaleAfter].
  ///  3. Since then fewer than [kUplinkFailureTolerance] complete
  ///     failures have accumulated. This third condition is the fast
  ///     edge: a pulled cable shows here within two rounds,
  ///     without the half hour from (2) having to expire.
  bool hasUplink({DateTime? now}) {
    final a = age(now: now);
    if (a == null) return false;
    if (a > kUplinkStaleAfter) return false;
    return _failuresSinceSuccess < kUplinkFailureTolerance;
  }

  /// Resets the state — exclusively for tests, so that one case does not
  /// colour the next.
  void resetForTest() {
    _reachedAt = null;
    _lastAttemptAt = null;
    _failuresSinceSuccess = 0;
    observations = 0;
  }
}

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
// Like [UplinkState]: no timer, no probe, no socket. Reading happens at
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
/// Node-wide and not per identity, for the same reason as
/// [UplinkState]: a process carries several identities, but exactly one
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
