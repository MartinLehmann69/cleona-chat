/// The check of a held file, ONCE per file state (S407-UPDATETARGET) — the
/// bookkeeping of `update_holder.dart`.
///
/// The holder keeps ONE encoder: holding a second object replaces the
/// encoder that was still checking the first. Until S407 the first plea for
/// the first object then started a SECOND streamed SHA-256 of the same file
/// beside the running one — on a ~200 MB APK the seconds of silence the
/// holder's header wants to avoid ("Checked once, at holding"), and a
/// collector meeting them turns to the next holder.
///
/// Here a check is kept per object: a passed one by path, size and
/// modification time; a running one is shared by everyone who asks for the
/// same file state. No clock, no packet.
library;

import 'dart:async';
import 'dart:io';

class FileChecks {
  final Map<String, (String, int, DateTime)> _passed = {};
  final Map<String, ((String, int, DateTime), Future<bool>)> _running = {};

  /// The object [h] is held anew or released: nothing of it counts any more.
  void forget(String h) {
    _passed.remove(h);
    _running.remove(h);
  }

  /// Whether the file at [path] with the state [s] matches the object [h]:
  /// a passed check of the same state counts, a running one is shared, and
  /// only otherwise [run] checks it.
  Future<bool> check(String h, String path, FileStat s, Future<bool> Function() run) {
    final state = (path, s.size, s.modified);
    if (_passed[h] == state) return Future.value(true);
    final running = _running[h];
    if (running != null && running.$1 == state) return running.$2;
    late final Future<bool> f;
    f = run().then((ok) {
      if (ok && identical(_running[h]?.$2, f)) _passed[h] = state;
      return ok;
    }).whenComplete(() {
      if (identical(_running[h]?.$2, f)) _running.remove(h);
    });
    _running[h] = (state, f);
    return f;
  }
}
