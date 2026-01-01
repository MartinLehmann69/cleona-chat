/// The collector role of the post box: ask the holders, prove the day key,
/// take over what they hand out, acknowledge it for deletion.
///
/// **A conversation per holder** (v4_2 §8.2 "collection ends", D-44):
///
/// * **no holder waits for another** — every holder has a row of its own
///   with the questions put to it. The first is open (its `0x32` is out),
///   the others follow one another: the next goes out when the one before
///   is done. Between holders nothing waits.
/// * **a holder is done** when it has handed out the number it announced in
///   its `0x33` (`0x34`: none; `0x37`: refused), or its link has ended
///   unanswered (a send to it ended `unreachable`, §11.6; a request to a
///   holder silent for more than 2 s renews the link first,
///   [beforeRequest]).
/// * **what a conversation still lacks is asked for the way §11.3 asks for
///   missing parts** (owner decision 01.10.2026): after a quiet period of
///   [kRestPeriod] without a new answer of that holder the collector asks
///   ONCE more for everything still open — the question, if no task has
///   come; otherwise the proofs of the values still unanswered. If that
///   brings nothing within another quiet period, the holder is done for this
///   edge with what it has handed out for that question, and the next
///   question in its row goes out; if it answered nothing at all, that is
///   ONE use without an answer per holder and edge (§11.8); an unreachable
///   holder drops what waits for it (§20.2). No timer runs while answers are
///   arriving ([arriving]). "Done" ends the waiting, not the taking over: an
///   answer that comes afterwards is processed as if the question were open.
/// * **every piece at once** — handed to its consumer and, if that took it,
///   acknowledged for deletion when it arrives, to every holder asked whose
///   task is answered (M-2).
/// * **the request identifier** (owner decision 02.10.2026): every `0x32`
///   carries one, and every packet back names the question it answers — an
///   answer is matched to its question by the identifier, by its value only
///   where that names no question held here ([PostBoxCollector._asking]).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/post_box_holder.dart'
    show Neighbour, Send, kHereItIsHeader, kNodeIdentifierLength;
import 'package:mycelium/post_box_disk.dart' show kIdLength, kValueLength;
import 'package:mycelium/post_box_log.dart'
    show collectOutcome, holdersNamed, talkOpen;
import 'package:mycelium/post_box_proof.dart';
import 'package:mycelium/post_box_runs.dart';
import 'package:mycelium/split.dart' show kRestPeriod;
import 'package:mycelium/split_flow.dart' show SendEnd;
import 'package:mycelium/update_manifest_compartment.dart' show isManifestValue;

class PostBoxCollector {
  final Send send;
  final void Function(List<Neighbour> withoutAnswer)? onMute;
  final void Function(InternetAddress from, int port, String node)? onNode;
  final void Function(String)? report;
  PostBoxCollector(
      {required this.send, this.onMute, this.onNode, this.report});

  /// Per holder (`adresse:port`): the questions put to it, in turn. The
  /// first is open, the others wait; a holder without a question has no row.
  final Map<String, Queue<Conversation>> _rows = {};

  /// The conversations that ended [TalkEnd.quiet], oldest first — a late
  /// answer finds its question here by the identifier, also when a newer one
  /// has gone to that holder. At most [kLateAtMost]; the oldest drops (§20.2).
  final List<Conversation> _late = [];

  /// The holders whose silence was counted as a use without an answer
  /// (§11.8) — ONE per holder and edge, not one per question in its row:
  /// emptied by [edge] (an edge begins), and a holder leaves when it answers.
  final Set<String> _silent = {};
  void edge() => _silent.clear();

  /// After [close]: nothing is sent, nothing is taken, no timer runs.
  bool _closed = false;

  /// The node stops: every open and waiting conversation ends without
  /// counting a use and without sending; their runs complete.
  void close() {
    _closed = true;
    final open = [for (final row in _rows.values) ...row];
    _rows.clear();
    _late.clear();
    for (final t in open) {
      t.quiet?.cancel();
      t.end = TalkEnd.dropped;
    }
    open.map((t) => t.of).toSet().forEach(_check);
  }

  /// Called before a request goes to a holder — in the node the shell's
  /// `renewIfSilent` (§11.6 variant A, owner 30.09.2026).
  void Function(Neighbour holder)? beforeRequest;

  /// Whether a transmission of [holder] is arriving right now — in the node
  /// the splitter's receive state. While it is, the quiet period does not
  /// count: a running hand-out is never cut off.
  bool Function(Neighbour holder)? arriving;

  /// Whether a question is open at any holder.
  bool get runs => _rows.isNotEmpty;

  /// Asks [withWhom] for everything under the values of [ask]. At a holder
  /// with an open question this one waits its turn. Every piece goes to
  /// [onPiece] when it arrives; the future completes with all of them once
  /// every asked holder is done.
  Future<List<Uint8List>> collect({
    required List<Question> ask,
    required List<Neighbour> withWhom,
    bool keep = false,
    PieceTaken? onPiece,
  }) {
    final a = CollectionRun(_closed ? const [] : withWhom, ask,
        keep: keep, onPiece: onPiece);
    // Named at the start: a holder that never answers writes no final line,
    // and which holder is asked must be readable all the same.
    report?.call(
        'collect: asks ${holdersNamed(a.holder)} under ${ask.length} value(s)');
    for (final t in a.talks.values) {
      final row = _rows.putIfAbsent(neighbourKey(t.holder), Queue.new);
      if (row.length >= kRowAtMost) {
        // R-2: the row of a holder must not grow without bound.
        t.end = TalkEnd.dropped;
        report?.call('collect: the row of ${neighbourKey(t.holder)} is full '
            '($kRowAtMost) — this question is not put to it');
        continue;
      }
      row.add(t);
      if (row.length == 1) _request(t);
    }
    _check(a); // covers withWhom.isEmpty at once
    return a.result.future;
  }

  /// Whether a question of an earlier round still stands at [holder].
  bool busy(Neighbour holder) => _rows.containsKey(neighbourKey(holder));

  /// Of [ask], the questions whose value stands in no question of
  /// [holder]'s row, open or waiting (§8.2 "follow one another": the same
  /// values are not put a second time behind themselves).
  List<Question> unasked(Neighbour holder, List<Question> ask) {
    final row = _rows[neighbourKey(holder)];
    if (row == null) return ask;
    return [
      for (final q in ask)
        if (!row.any((t) => t.of.ask.containsKey(asHex(q.value)))) q
    ];
  }

  /// The request of [t] to its holder, under a new identifier.
  void _request(Conversation t) {
    beforeRequest?.call(t.holder);
    final packet = collectPacket(
        t.of.ask.values.toList(), SodiumFFI().randomBytes(kCollectLength));
    t.ids.add(asHex(collectRequestId(packet)));
    _send(t, packet, starts: true);
  }

  /// The quiet period of [t] starts anew. It exists only while [t] is open.
  void _listen(Conversation t) {
    t.quiet?.cancel();
    t.quiet = Timer(kRestPeriod, () => _quiet(t));
  }

  /// [kRestPeriod] without a new answer of [t]'s holder (§8.2, as §11.3).
  void _quiet(Conversation t) {
    if (t.end != null) return;
    // Parts of a transmission are arriving: no timer runs meanwhile.
    if (arriving?.call(t.holder) ?? false) return _listen(t);
    // The one request for what is missing brought nothing.
    if (t.progressAtRequest == t.progress) return _end(t, TalkEnd.quiet);
    t.progressAtRequest = t.progress;
    final key = neighbourKey(t.holder);
    final random = t.random;
    if (random == null) {
      report?.call('collect: $key silent — the question is asked once more');
      return _request(t);
    }
    final open = [
      for (final f in t.of.ask.values)
        if (!t.done(asHex(f.value))) f
    ];
    report?.call('collect: $key silent — the proofs of ${open.length} '
        'value(s) still unanswered go out once more');
    for (final f in open) {
      t.restart(asHex(f.value));
      _send(t, proofPacket(f, random));
    }
    _listen(t);
  }

  /// A packet of holder [n] carrying [req] — `0x35`, `0x33`, `0x34` or
  /// `0x37`. Returns the open conversation it answers, or `null`; an answer
  /// starts that conversation's quiet period anew.
  Conversation? _from(Neighbour n, Uint8List req) {
    if (_closed) return null;
    final key = neighbourKey(n), id = asHex(req);
    final t = _rows[key]?.firstOrNull;
    if (t != null && t.ids.contains(id)) {
      _silent.remove(key);
      t.answered = true;
      t.progress++;
      _listen(t);
      return t;
    }
    // The question had ended quiet; what comes all the same is taken over as
    // if the conversation were open (§8.2 "every piece is taken over … when
    // it arrives") — nothing waits for it, no timer runs.
    final late = _lateAt(key).where((c) => c.ids.contains(id)).firstOrNull;
    if (late != null) _silent.remove(key);
    return late;
  }

  /// The conversations with holder [key] that ended quiet, newest first.
  Iterable<Conversation> _lateAt(String key) =>
      _late.reversed.where((c) => neighbourKey(c.holder) == key);

  /// The conversation with holder [n] an answer under [valueHex] belongs to:
  /// the one its identifier names ([named], §8.2). By the value where that is
  /// none asking it — a refusal under a task the holder does not know (zero),
  /// a question no longer held, a holder that names the newest question (the
  /// state before S403): the open one, else the newest that ended quiet.
  Conversation? _asking(Neighbour n, Conversation? named, String valueHex) {
    final key = neighbourKey(n);
    return [if (named != null) named, ...?_rows[key]?.take(1), ..._lateAt(key)]
        .where((c) => c.random != null && c.of.ask.containsKey(valueHex))
        .firstOrNull;
  }

  /// Sends [p] to the holder of [t]; an `unreachable` end ends [t].
  /// [starts]: the question itself — its quiet period starts when it has
  /// really left (a request held for a handshake leaves when that ends,
  /// §11.6), not when it was handed over.
  void _send(Conversation t, Uint8List p, {bool starts = false}) {
    if (_closed) return;
    final s = send(p, t.holder);
    if (s is! Future) {
      if (starts) _listen(t); // a send without flow (probes): out at once
      return;
    }
    unawaited(s.then((end) {
      if (end == SendEnd.unreachable) return _end(t, TalkEnd.unreachable);
      if (starts && t.end == null) _listen(t);
    }, onError: (Object _) {}));
  }

  /// [t] is done; the next question to the same holder goes out — also when
  /// [t] ended quiet: what a holder leaves unanswered delays no other identity
  /// (§8.2). Only when the holder is unreachable what waits drops (§20.2).
  void _end(Conversation t, TalkEnd how) {
    final key = neighbourKey(t.holder);
    // Late answers have completed a conversation that had ended quiet: it
    // stays held, so a repeated answer still finds it by its identifier.
    if (t.end != null) return;
    t.end = how;
    t.quiet?.cancel();
    final row = _rows[key];
    if (row != null && identical(row.firstOrNull, t)) {
      row.removeFirst();
      if (how == TalkEnd.unreachable) {
        for (final w in row) {
          w.end = TalkEnd.dropped;
          _check(w.of);
        }
        row.clear();
      } else if (how == TalkEnd.quiet) {
        _late.add(t); // newest last: the cap drops the oldest (§20.2)
        while (_late.length > kLateAtMost) {
          _late.removeAt(0);
        }
      }
      if (row.isEmpty) {
        _rows.remove(key);
      } else {
        _request(row.first);
      }
    }
    _check(t.of);
    if (how == TalkEnd.unreachable) {
      report?.call('collect: $key unreachable — one use without an answer');
      onMute?.call([t.holder]);
    } else if (how == TalkEnd.quiet) {
      // ONE use per holder and edge, however many questions it leaves.
      final counts = !t.answered && _silent.add(key);
      report?.call('collect: one request for what is missing brought nothing '
          '— this question is done for this edge; open: ${talkOpen(t)}'
          '${counts ? ' — one use without an answer' : ''}');
      if (counts) onMute?.call([t.holder]);
    }
  }

  void _check(CollectionRun a) {
    if (!a.complete || a.result.isCompleted) return;
    a.result.complete(a.found);
    report?.call(collectOutcome(a));
  }

  /// 0x35 `Sorte | Zufall | Knoten | Anfragekennung`: the task of an asked
  /// holder — answered with one proof for each asked value, then the deletion
  /// of what this run has already taken over.
  void onTask(Uint8List packet, Neighbour from) {
    const at = 1 + kRandomLength + kNodeIdentifierLength;
    if (packet.length != at + kRequestIdLength) return;
    final t = _from(from, packet.sublist(at));
    if (t == null || t.random != null) return;
    final a = t.of;
    final random = packet.sublist(1, 1 + kRandomLength);
    t.random = random;
    report?.call('collect: ${neighbourKey(from)} answered with its task');
    onNode?.call(from.$1, from.$2, asHex(packet.sublist(1 + kRandomLength, at)));
    // What was taken BEFORE this task — a piece this holder hands out in
    // answer to the proofs below gets its deletion at its takeover.
    final before = {for (final e in a.taken.entries) e.key: List.of(e.value)};
    for (final f in a.ask.values) {
      _send(t, proofPacket(f, random));
    }
    for (final MapEntry(key: v, value: ids) in before.entries) {
      final pair = a.ask[v]!.pair!;
      for (final id in ids) {
        _send(t, deletePacket(pair, a.ask[v]!.value, random, id));
      }
    }
  }

  /// 0x33 `Sorte | Wert | id | Anzahl | Anfragekennung | Inhalt` — [Anzahl]:
  /// the number this holder hands out under this value.
  void onHereItIs(Uint8List packet, Neighbour from) {
    if (packet.length < kHereItIsHeader) return;
    var i = 1;
    final value = packet.sublist(i, i += kValueLength);
    final id = packet.sublist(i, i += kIdLength);
    final count = packet[i++];
    final req = packet.sublist(i, i += kRequestIdLength);
    final content = packet.sublist(i);
    final valueHex = asHex(value);
    // Only under a task that is answered: otherwise there is no random
    // value to which the delete receipt can be bound.
    final t = _asking(from, _from(from, req), valueHex);
    final random = t?.random;
    if (t == null || random == null) {
      final key = neighbourKey(from); // named only for a holder that was asked
      if (_rows.containsKey(key) || _lateAt(key).isNotEmpty) {
        report?.call('collect: a piece under ${valueHex.substring(0, 8)} from '
            '$key fits no question with a task — it stays with its holder');
      }
      return;
    }
    final a = t.of;
    final question = a.ask[valueHex]!;
    final deletes = question.pair != null && !isManifestValue(value) && !a.keep;
    t.handed.putIfAbsent(valueHex, () => {}).add(asHex(id)); // a copy counts once
    t.expected[valueHex] = count;
    // Taken over once per run, and at once: to its consumer, then the
    // deletion to every holder asked whose task is answered (M-2). What the
    // consumer does not take is not acknowledged: it stays with its holder
    // (§8.2 "deletion only after the collector acknowledges receipt").
    if (!a.seen.contains(asHex(id))) {
      if (!(a.onPiece?.call(content, from) ?? true)) {
        report?.call('collect: a piece from ${neighbourKey(from)} was not '
            'taken by its consumer — not acknowledged for deletion');
      } else {
        a.seen.add(asHex(id));
        a.found.add(content);
        t.pieces++;
        if (deletes) {
          a.taken.putIfAbsent(valueHex, () => []).add(id);
          for (final u in a.talks.values) {
            final r = u.random;
            if (r != null) _send(u, deletePacket(question.pair!, value, r, id));
          }
        }
      }
    } else if (deletes) {
      // A copy of what is already taken: its deletion was lost or crossed
      // this hand-out — acknowledge once more, to this holder.
      _send(t, deletePacket(question.pair!, value, random, id));
    }
    if (t.handedOut) _end(t, TalkEnd.answered);
  }

  /// 0x34 `Sorte | Wert | Anfragekennung`: nothing under the value.
  /// 0x37 (same form, [refused]): the proof is refused — no valid proof or
  /// the task unknown; what lies there stays held.
  void onNothingThere(Uint8List packet, Neighbour from, {bool refused = false}) {
    if (packet.length != 1 + kValueLength + kRequestIdLength) return;
    final valueHex = asHex(packet.sublist(1, 1 + kValueLength));
    // Before the proof, or under a value nobody asked: not from the holder.
    final t =
        _asking(from, _from(from, packet.sublist(1 + kValueLength)), valueHex);
    if (t == null) return;
    t.expected[valueHex] = refused ? t.received(valueHex) : 0;
    if (refused) {
      report?.call('collect: ${neighbourKey(from)} refused '
          '${valueHex.substring(0, 8)}');
    }
    if (t.handedOut) _end(t, TalkEnd.answered);
  }
}
