// Is the connection metered? — the answer for the cover stream (S391, W1).
//
// V4.2 §5.1/§5.3: on metered mobile the cover stream runs at a
// lowered rate (`kMeanMetered` in `mycelium/lib/cover_stream.dart`), on
// W/LAN at `R_cover`. Proposal W1: metered is what the
// OPERATING SYSTEM says.
//
// ── WHY NO PLUGIN IMPORT HERE ──────────────────────────────────────
//
// This file also runs in the daemon via the seam (`mycelium_seam.dart`), and
// the daemon is built without Flutter (`scripts/build-daemon.sh`). An
// import of `connectivity_plus` would break the build there. The app therefore passes the
// connection kinds in as names ([connectionKinds]), and the
// mapping ([meteredOutConnectionKinds]) is pure.
//
// ── SOURCES, PER PLATFORM ──────────────────────────────────────────────
//
// | Platform | Source | Status |
// |---|---|---|
// | Linux, Windows | `networkKindFromSystem` (`uplink_state.dart`) | built |
// | Android | [mobilMetered]: `ConnectivityManager.isActiveNetworkMetered` (app, `lib/main.dart`) | built, set |
// | iOS | [mobilMetered]: mobile without WLAN/Ethernet = metered (app) | built, set; `NWPath.isExpensive` missing |
// | Android, iOS without app hook | [connectionKinds] | fallback |
// | macOS | — | returns `null`; default unmetered |
//
// The app sets [mobilMetered] to the same determination as for the
// update gate (`_meteredErmitteln` in `lib/main.dart`, S391) — one source,
// not two. iOS `NWPath.isExpensive` remains open.
//
// No tick: reading happens at the edges the node has anyway (start,
// network change — `mycelium/lib/node_cover.dart`).
library;

import 'dart:io';

import 'package:cleona/core/util/uplink_state.dart';

/// The connection kinds as the app knows them (`ConnectivityResult.name`:
/// `wifi`, `ethernet`, `mobile`, …). To be set by the Flutter app; in the
/// daemon it stays `null`.
Future<List<String>> Function()? connectionKinds;

/// The information of the app for mobile devices (W1) — taking precedence over
/// [connectionKinds]. `null` in the daemon.
Future<bool?> Function()? mobilMetered;

/// W1, first implementation: mobile without WLAN and without Ethernet is
/// metered, everything else not. `null` if no kind at all is named.
bool? meteredOutConnectionKinds(Iterable<String> kinds) {
  final a = kinds.toSet();
  if (a.isEmpty || (a.length == 1 && a.contains('none'))) return null;
  if (a.contains('wifi') || a.contains('ethernet')) return false;
  return a.contains('mobile');
}

/// Reads the network kind at an edge and records it in [NetworkKind].
///
/// If nobody knows anything, a mobile device counts as METERED and a desktop
/// as unmetered — the same direction as the update gate of the app
/// (`_updateHolenGesperrt`): on the phone the lowered rate is the
/// cheaper mistake.
Future<bool> coverMeteredRead({
  Future<bool?> Function()? system,
  bool? mobil,
}) async {
  final isMobil = mobil ?? (Platform.isAndroid || Platform.isIOS);
  bool? value;
  if (isMobil) {
    value = await mobilMetered?.call();
    if (value == null) {
      final kinds = await connectionKinds?.call();
      if (kinds != null) value = meteredOutConnectionKinds(kinds);
    }
  } else {
    value = await (system ?? networkKindFromSystem)();
  }
  NetworkKind.instance.note(value: value);
  return NetworkKind.instance.metered ?? isMobil;
}
