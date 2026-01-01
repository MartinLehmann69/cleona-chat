import 'dart:convert';
import 'dart:io';

import '../rendezvous/nostr_provider.dart' show kDefaultNostrRelays;

/// Where the relay list of the external rendezvous (§11.3 stage A) comes from.
///
/// ── WHAT IS DECIDED HERE AND WHAT EXPLICITLY IS NOT ─────────────
///
/// **What is not decided is WHICH relays are shipped.** That is a
/// configuration and product decision (supply chain, operator,
/// jurisdiction, censorship situation) and belongs to the owner — level
/// C. This file only builds the MECHANISM, so that the answer can be
/// entered later without touching the code.
///
/// **What is decided is that the list is configurable at all.**
/// Until now it stood as `const List<String> kDefaultNostrRelays` in the
/// code, and `v41_attach.dart` built `NostrProvider()` without argument —
/// there was no way to change it except a new build. For a list whose
/// entries can fail, become paid or be blocked (two have already been
/// removed for exactly these reasons, see the header of
/// `nostr_provider.dart`), that is the wrong change interval.
///
/// ── THE ORDER ───────────────────────────────────────────────────
///
/// 1. Environment variable `CLEONA_RENDEZVOUS_RELAYS` (comma-separated) —
///    for lab runs and the field test, without creating a file.
/// 2. `$baseDir/rendezvous_relays.json` — the permanent configuration.
/// 3. `kDefaultNostrRelays` — what the build brings along.
///
/// NO EMPTY RESULT. A configuration that leaves nothing after filtering
/// (typo, commented-out list) falls back to the default instead of
/// silently switching off the stage. An external rendezvous without
/// relays looks from outside exactly like one that finds nobody — and
/// that is the difference this layer carefully keeps visible everywhere
/// else.
abstract final class RendezvousRelays {
  static const String envVar = 'CLEONA_RENDEZVOUS_RELAYS';
  static const String fileName = 'rendezvous_relays.json';

  /// The list with which the provider is built.
  ///
  /// [baseDir] is the device directory (the same one
  /// `NodeKeys.loadOrCreate` reads from) — the list is device-bound, not
  /// identity-bound: there is ONE node per process, and it has ONE
  /// external rendezvous.
  ///
  /// [onNote] gets a line when a configuration took effect or was
  /// discarded. Staying silent would be particularly expensive here:
  /// whoever creates a file and notices nothing looks for the error in
  /// the network.
  static List<String> forNode(String? baseDir, {void Function(String)? onNote}) {
    final outEnvironment = _parseCsv(Platform.environment[envVar]);
    if (outEnvironment.isNotEmpty) {
      onNote?.call('Rendezvous: ${outEnvironment.length} relays from $envVar');
      return outEnvironment;
    }

    if (baseDir != null && baseDir.isNotEmpty) {
      final path = '$baseDir/$fileName';
      try {
        final file = File(path);
        if (file.existsSync()) {
          final outFile = parseJson(file.readAsStringSync());
          if (outFile.isNotEmpty) {
            onNote?.call(
                'Rendezvous: ${outFile.length} relays from $fileName');
            return outFile;
          }
          onNote?.call('Rendezvous: $fileName contains no usable '
              'relay — the built-in list applies');
        }
      } catch (e) {
        // An unreadable configuration is not a startup error. But it is
        // also nothing to stay silent about.
        onNote?.call('Rendezvous: $fileName not readable ($e) — the '
            'built-in list applies');
      }
    }

    return List<String>.unmodifiable(kDefaultNostrRelays);
  }

  /// Reads `{"relays": ["wss://…", …]}` or a bare JSON list.
  ///
  /// Both forms, because both are obvious and the wrong form would
  /// otherwise look like an empty configuration.
  static List<String> parseJson(String text) {
    final dynamic j = jsonDecode(text);
    final List<dynamic> raw;
    if (j is List) {
      raw = j;
    } else if (j is Map && j['relays'] is List) {
      raw = j['relays'] as List<dynamic>;
    } else {
      return const <String>[];
    }
    return _filter(raw.whereType<String>());
  }

  static List<String> _parseCsv(String? s) {
    if (s == null || s.trim().isEmpty) return const <String>[];
    return _filter(s.split(','));
  }

  /// ONLY `wss://`.
  ///
  /// Not `ws://`: the rendezvous lies before network entry, on a
  /// foreign substrate, and an unencrypted hop there would give everyone
  /// along the way the mark of the day in plaintext. The payload would
  /// remain opaque (it lies under `ExternalTag.keyForDay`) — the mark
  /// itself then no longer is, and exactly through it runs the
  /// attribution "a Cleona node is starting here".
  static List<String> _filter(Iterable<String> raw) {
    final out = <String>[];
    for (final e in raw) {
      final u = e.trim();
      if (u.isEmpty) continue;
      if (!u.startsWith('wss://')) continue;
      if (out.contains(u)) continue;
      out.add(u);
    }
    return out;
  }
}
