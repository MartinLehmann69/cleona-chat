/// The addresses this node removed because a use failed — a request and its
/// repeats stayed unanswered (§11.3a, §11.8.5) — and when.
///
/// §5.5 and §11.9 say a hint that does not answer "is dropped by whoever
/// tries it". Without this memory the next hint with the SAME, older
/// information re-admitted it as a new neighbour — and since the removal
/// itself starts the refill, which reads the external records again
/// (§11.8, §11.9), removal, refill, re-admission and the next collection
/// round formed a loop that ran in idle once per refill interval (D-9;
/// measured on Node2 and the bootstrap, `berichte/S406-VORLAGE-ABHOLRUNDEN.md`).
///
/// A removed address returns as soon as a hint confirms it AFTER its
/// removal — no score, no probation, no waiting time (§11.8). The answer
/// to the own neighbour call is such a confirmation, dated now (§11.8.4). A
/// hint that carries no time — the address in an invitation, a foreign call
/// — says nothing newer and does not bring it back (§11.8.6; S407-LB-P7,
/// C-8). The one check is `neighbourAdd`. Memory only, bounded (§20.2); a
/// network change clears it (§11.8: remembered addresses are re-attempted
/// once).
library;

import 'dart:io';

class DroppedAddresses {
  /// At most this many removals are remembered; the oldest gives way.
  static const int atMost = 64;

  /// `address:port` -> when it was removed, oldest first.
  final Map<String, DateTime> _at = {};

  /// [a]:[port] was removed at [when]: its request and repeats stayed
  /// unanswered (§11.3a).
  void dropped(InternetAddress a, int port, DateTime when) {
    final k = _key(a, port);
    _at.remove(k); // re-inserted: it is the newest now
    _at[k] = when;
    while (_at.length > atMost) {
      _at.remove(_at.keys.first);
    }
  }

  /// When [a]:[port] was removed, or `null` if it is not remembered.
  DateTime? removedAt(InternetAddress a, int port) => _at[_key(a, port)];

  /// True when [a]:[port] was removed and [confirmedAt] says nothing newer
  /// than the removal — such a hint is not admitted.
  bool stale(InternetAddress a, int port, DateTime confirmedAt) {
    final at = _at[_key(a, port)];
    return at != null && !confirmedAt.isAfter(at);
  }

  /// [a]:[port] is in the list again — it is no longer "removed".
  void forget(InternetAddress a, int port) => _at.remove(_key(a, port));

  /// Network change or stop (§11.8).
  void clear() => _at.clear();

  int get length => _at.length;

  /// `address:port` -> when it was removed, oldest first — for diagnostics.
  Iterable<MapEntry<String, DateTime>> get entries => _at.entries;

  static String _key(InternetAddress a, int port) => '${a.address}:$port';
}
