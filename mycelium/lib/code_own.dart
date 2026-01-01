/// The own codes of a node (V4.2 §8.1): which codes belong to a mailbox of
/// THIS device, cached per UTC day. Out of `node_codes.dart` for the line
/// budget (mycelium/README.md rule 2, S398); only [CodeRoute] holds one.
library;

import 'dart:typed_data';

import 'package:mycelium/node_helpers.dart' show hexFrom;
import 'package:mycelium/pair.dart' show utcDay;

class OwnCodes {
  /// All inbound codes of all mailboxes on a UTC day — asked at every use:
  /// the host sets the function after the node has started.
  final List<Uint8List> Function(int day) Function() _inbound;

  /// The clock of the code route — changeable there for tests.
  final DateTime Function() Function() _now;

  final Map<int, Set<String>> _own = {};
  DateTime? _freshComputed;

  OwnCodes(this._inbound, this._now);

  /// The own codes of [day], as hex.
  Set<String> at(int day) =>
      _own[day] ??= {for (final c in _inbound()(day)) hexFrom(c)};

  /// The list changed (an edge of the mailboxes): computed anew at next use.
  void clear() => _own.clear();

  /// Does [code] belong to a mailbox of this device (yesterday, today,
  /// tomorrow — for a skewed clock)?
  bool contains(Uint8List code) {
    final today = utcDay(_now()());
    _own.removeWhere((t, _) => t < today - 1 || t > today + 1);
    final h = hexFrom(code);
    bool search() => [today - 1, today, today + 1].any((t) => at(t).contains(h));
    if (search()) return true;
    // A new contact without a reported edge: recompute at most once per second.
    final t = _now()();
    final last = _freshComputed;
    if (last != null && t.difference(last) < const Duration(seconds: 1)) {
      return false;
    }
    _freshComputed = t;
    _own.clear();
    return search();
  }
}
