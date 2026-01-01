/// S426 AVM-M1 measurement (AVM 35.05, `berichte/S426-RCA-AVM3505-MESSUNG.md`
/// §4), used only with tracing on. A counterpart's packet opened under no
/// key this node holds — why was its key gone? Three candidates, which the
/// log alone did not tell apart: K1 this node replaced the key by a new
/// handshake ([linkPut]), K2 the cap dropped it ([capLinks]), K3 the
/// counterpart changed its key itself. The last replaced or dropped receive
/// keys are kept (at most [kKeyHistoryAtMost]); a packet that opens under
/// none of the held keys is tried under them. It is NOT read — the line
/// only says which key it opens under: a replaced one is K1, a dropped one
/// K2, none of them points to K3. Nothing changes on the wire (rule 5).
///
/// Cost, named: up to [kKeyHistoryAtMost] trial opens (one AEAD check each,
/// as `roamOpen`) per packet that opens under no held key, only with
/// tracing on.
library;

import 'dart:typed_data';

import 'package:mycelium/shell_link.dart' show Link;
import 'package:mycelium/shell_start.dart' show unpack;

const int kKeyHistoryAtMost = 64;

class KeyHistory {
  KeyHistory(this._now);
  final DateTime Function() _now;
  final List<(Uint8List, String)> _gone = [];

  /// S427 AVM-K1 (`berichte/S427-RCA-AVM3505-K1.md` §4): when and how each
  /// link was set up, so a replacement can say how old the replaced one was.
  final Expando<(DateTime, String, String)> _born = Expando();

  /// [n] was set up under [w] as [how]; returns the trace line of the set-up.
  String setUp(Link n, String w, String how) {
    _born[n] = (_now(), w, how);
    return 'TRACE shell link to $w set up as $how';
  }

  /// [old] gave way to the link set up as [how] (caller/callee); it stood
  /// under [at]. [running]: addresses of [at] under which a handshake still
  /// runs — a second handshake of the same counterpart under another
  /// address (explanation (ii) of S427 AVM-K1). Returns the trace line.
  String replaced(Link old, List<String> at, String how,
      [List<String> running = const []]) {
    final b = _born[old];
    final age = b == null
        ? 'set up before the measurement'
        : 'set up ${_now().difference(b.$1).inMilliseconds} ms before under ${b.$2} as ${b.$3}';
    return _keep(old,
        'replaced at ${_now().toIso8601String()} under ${at.join(', ')} by a link set up as $how '
        '(the replaced link: $age; handshake running under: '
        '${running.isEmpty ? 'none' : running.join(', ')})');
  }

  /// The cap dropped [old] under [w]; [elsewhere]: the same key still
  /// stands under another address. Returns the trace line.
  String dropped(String w, Link old, bool elsewhere) => _keep(old,
      'dropped by the cap at ${_now().toIso8601String()} under $w'
      '${elsewhere ? ' (still held under another address)' : ''}');

  String _keep(Link old, String how) {
    if (_gone.length >= kKeyHistoryAtMost) _gone.removeAt(0);
    _gone.add((old.receiveKey, how));
    return 'TRACE shell key $how';
  }

  /// [p] from [w] opened under no held key: if it opens under a kept one,
  /// [say] gets one line — once per kept key (it leaves the history), so
  /// a repeated flight 1 cannot use up the line as it did the once-per-key
  /// line of D-92 A.5. No line: under none of them (K3, or a foreign
  /// flight 1).
  void match(Uint8List p, String w, void Function(String) say) {
    for (var i = _gone.length - 1; i >= 0; i--) {
      if (unpack(p, _gone[i].$1) == null) continue;
      say('TRACE shell packet from $w opens under the key ${_gone[i].$2}');
      _gone.removeAt(i);
      return;
    }
  }
}
