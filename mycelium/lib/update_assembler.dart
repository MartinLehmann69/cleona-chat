/// The assembler — the side that FETCHES the object of the node's own
/// update target (V4.2 §26.6.1 "The fetch path"; S387, rebuilt S406-UPDPKG).
///
/// ── THE TARGET ────────────────────────────────────────────────────────
///
/// ONE object at a time ([expect]). Its partial state lies on disk
/// ([UpdatePartial], P2), fed by the rounds of a run ([fetch]) and by cover
/// fill ([aside], P3) — also while no run is allowed (§24.4.2). Another
/// target ends the run and deletes every other state (§26.6.1, P1); a
/// completed object whose SHA-256 does not match is deleted whole.
///
/// ── A RUN ──────────────────────────────────────────────────────────────
///
/// Per holder: request → task → request with task and count → answer.
/// * The next request follows the ARRIVAL of the answer: all pieces asked
///   for, or a quiet gap after the last one (§11.3). No clock runs while
///   pieces arrive. Three answers in a row without a new piece (a task is
///   one) → next holder.
/// * **Silence is no answer** (§8.2, P6): a request without any packet back
///   within the quiet period gets ONE more request; silent again → next
///   holder. After the last holder the run ends; the state stays, and the
///   next moment of §26.5.4 resumes it — never a timer.
/// * A task from the asked holder is always taken (an address change needs
///   one again); a request names how many pieces it wants, sized from the
///   round trip ([piecesPerAnswerFor], P7) — never which ones. No cover
///   stream (§3.1); pieces count only from the holder asked.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_sha256.dart';
import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:cleona/core/fountain/fountain_decoder.dart' show FountainOffer;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/update_partial.dart';
import 'package:mycelium/update_piece.dart';
import 'package:mycelium/update_run.dart';
import 'package:mycelium/update_trace.dart';

class UpdateAssembler {
  final UpdateSend send;
  final String partialDir; // the partial state: one directory per object
  final Duration restPeriod;
  final void Function(String)? report;

  /// The target completed outside a run (by cover fill): its file.
  void Function(Uint8List object, String path)? onComplete;

  UpdatePartial? _partial;
  String? _taken;
  UpdateRun? _run;
  bool _checking = false, _draining = false;

  int receivedPieces = 0;
  int sentPleas = 0;
  int asidePieces = 0;
  int asideDropped = 0;

  UpdateAssembler({
    required this.send,
    required this.partialDir,
    this.restPeriod = kRestPeriod,
    this.report,
  });

  bool get runs => _run != null;
  UpdatePartial? get partial => _partial;

  /// [object] ([length] B) becomes the target: a former one's run ends, every
  /// other state under [partialDir] is deleted, its own opened from disk.
  void expect(Uint8List object, int length) {
    final p = _partial;
    if (p != null && sameBytes(p.object, object) && p.length == length) return;
    final hex = partialHex(object);
    if (_taken == hex) return;
    final r = _run;
    if (r != null) _end(r, null, 'aborted — another object is the target');
    p?.close();
    _taken = null;
    final base = Directory(partialDir);
    if (base.existsSync()) {
      for (final e in base.listSync()) {
        if (e.path.endsWith(hex)) continue;
        updateTrace('discard',
            object: e.path.split(Platform.pathSeparator).last,
            reason: 'partial state of a former target deleted');
        e.deleteSync(recursive: true);
      }
    }
    final n = _partial = UpdatePartial.open(partialDir, object, length);
    updateTrace('partial',
        object: object,
        reason: '${n.resumed ? 'resumed from disk' : 'new'}: ${n.describe()}');
    if (n.isComplete) unawaited(_complete(n));
  }

  /// The caller checked and moved the target's file: its state goes.
  void taken(Uint8List object) {
    final p = _partial;
    if (p == null || !sameBytes(p.object, object)) return;
    p.delete();
    _partial = null;
    _taken = partialHex(object);
  }

  /// The target failed its check: the whole state goes, the target stays.
  void discard(Uint8List object) {
    final p = _partial;
    if (p == null || !sameBytes(p.object, object)) return;
    final r = _run;
    if (r != null) _end(r, null, 'discarded');
    p.delete();
    _partial = UpdatePartial.open(partialDir, object, p.length);
  }

  /// Fetches the target [object] from [withWhom], in order. The file of the
  /// complete, SHA-256-checked object, or `null`: no holder delivered it
  /// (the state stays). A run for the same object hands back its result.
  Future<String?> fetch({
    required Uint8List object,
    required int length,
    required List<UpdateNeighbour> withWhom,
  }) {
    if (object.length != kObjectLength) {
      throw ArgumentError('Object must be $kObjectLength B');
    }
    expect(object, length);
    final p = _partial;
    if (p == null) return Future.value(null);
    final r = _run;
    if (r != null) return r.result.future;
    final run = _run = UpdateRun(List.of(withWhom), p.sourceBlocks);
    updateTrace('fetch-start',
        object: object,
        reason: '$length B, ${p.describe()}, ${run.holder.length} holder(s): '
            '${run.holder.map((h) => '${h.$1.address}:${h.$2}').join(', ')}');
    if (p.isComplete) {
      unawaited(_complete(p));
    } else {
      _plea(run);
    }
    return run.result.future;
  }

  /// A piece from a packet that was flying anyway (§5.5 rule 2): kept if it
  /// belongs to the target, run or not (§24.4.2 "pieces arriving by cover
  /// fill are still kept"). Never a packet, never the end of a round.
  bool aside(FountainBlock block) {
    final p = _partial;
    final f = p == null ? FountainOffer.foreign : _offer(p, block);
    if (f == FountainOffer.foreign ||
        f == FountainOffer.duplicate ||
        f == FountainOffer.complete) {
      asideDropped++;
      return false;
    }
    asidePieces++;
    return true;
  }

  FountainOffer _offer(UpdatePartial p, FountainBlock block) {
    try {
      final f = p.offer(block);
      if (p.busy) _drainSoon(p);
      if (p.isComplete && f != FountainOffer.complete) unawaited(_complete(p));
      return f;
    } on FileSystemException catch (e) {
      // A disk error drops the piece — it never reaches the packet path.
      report?.call('Update collector: partial state not writable: $e');
      return FountainOffer.foreign;
    }
  }

  /// The rest of the peeling wave, one batch per event-loop turn — no clock.
  void _drainSoon(UpdatePartial p) {
    if (_draining) return;
    _draining = true;
    void step() {
      try {
        if (identical(_partial, p) && p.drain()) return Timer.run(step);
        if (identical(_partial, p) && p.isComplete) unawaited(_complete(p));
      } on FileSystemException catch (e) {
        report?.call('Update collector: partial state not readable: $e');
      }
      _draining = false;
    }

    Timer.run(step);
  }

  /// Ends a running run without result; the state stays.
  void abort() {
    final r = _run;
    if (r != null) _end(r, null, 'aborted');
  }

  /// Packets of kinds 0x71-0x73. Every other kind is ignored.
  void receive(Uint8List packet, InternetAddress from, int fromPort) {
    final l = _run;
    final p = _partial;
    if (l == null || p == null || packet.isEmpty) return;
    if (l.holderNo >= l.holder.length || _checking) return;
    final h = l.holder[l.holderNo];
    if (h.$1.address != from.address || h.$2 != fromPort) return;
    switch (packet[0]) {
      case kinds.kPieceTask:
        final a = pleaOrTaskRead(packet);
        if (a == null || !sameBytes(a.object, p.object)) return;
        l.sample();
        updateTrace('task-in',
            object: p.object, reason: 'from ${from.address}:$fromPort taken');
        l.task = a.task;
        _answerEnd(l);
      case kinds.kNoPieces:
        final o = noRead(packet);
        if (o == null || !sameBytes(o, p.object)) return;
        _nextHolder(l, 'does not have it');
      case kinds.kUpdatePiece:
        final block = pieceRead(packet);
        if (block == null) return;
        final finding = _offer(p, block);
        if (finding == FountainOffer.foreign) return;
        receivedPieces++;
        l.piece(fresh: finding != FountainOffer.duplicate);
        if (_checking || !identical(_run, l)) return;
        if (l.piecesFromHolder > l.upperLimitPerHolder) {
          _nextHolder(l, 'upper limit ${l.upperLimitPerHolder} without object');
        } else if (l.inRound >= l.asked) {
          _answerEnd(l);
        } else {
          _arm(l, l.gap());
        }
    }
  }

  void _arm(UpdateRun l, Duration d) {
    l.quiet?.cancel();
    l.quiet = Timer(d, () => _quietEnd(l));
  }

  void _plea(UpdateRun l) {
    if (!identical(_run, l)) return;
    final p = _partial!;
    if (l.holderNo >= l.holder.length) {
      _end(l, null, 'no holder delivered the object — the state stays');
      return;
    }
    l.roundStart();
    send(pleaPacket(p.object, l.task ?? Uint8List(kTaskLength), count: l.asked),
        l.current);
    sentPleas++;
    _arm(l, l.silence(restPeriod));
  }

  void _quietEnd(UpdateRun l) {
    if (!identical(_run, l) || _checking) return;
    if (l.inRound > 0) {
      _answerEnd(l);
      return;
    }
    final h = l.holder[l.holderNo];
    if (!l.askedAgain) {
      l.askedAgain = true;
      updateTrace('ask-again',
          object: _partial?.object,
          reason: '${h.$1.address}:${h.$2} — no answer within the quiet '
              'period, asked once more');
      _plea(l);
      return;
    }
    _nextHolder(l, 'silent after one more request');
  }

  void _answerEnd(UpdateRun l) {
    l.quiet?.cancel();
    final p = _partial!;
    final h = l.holder[l.holderNo];
    updateTrace('round',
        object: p.object,
        reason: 'holder ${h.$1.address}:${h.$2}: ${l.inRound} of ${l.asked} '
            'piece(s), ${l.newInRound} new, ${p.describe()}, rtt '
            '${l.rtt?.inMilliseconds ?? '-'} ms, empty answers before '
            '${l.emptyAnswers}');
    l.askedAgain = false;
    if (l.newInRound > 0) {
      l.emptyAnswers = 0;
    } else if (++l.emptyAnswers >= kEmptyAnswersPerHolder) {
      _nextHolder(l, '$kEmptyAnswersPerHolder answers without a new piece');
      return;
    }
    _plea(l);
  }

  void _nextHolder(UpdateRun l, String reason) {
    l.quiet?.cancel();
    final h = l.holder[l.holderNo];
    updateTrace('holder-next',
        object: _partial?.object,
        reason: '${h.$1.address}:${h.$2} — $reason (${_partial?.describe()})');
    report?.call('Update collector: ${objectShort(_partial!.object)} at '
        '${h.$1.address}:${h.$2} — $reason, next holder');
    l.nextHolder();
    _plea(l);
  }

  /// The target is complete: cut, checked against its SHA-256. Matches →
  /// the run (or [onComplete]) gets the file; does not → the whole state
  /// is deleted (§26.6.1 self-healing).
  Future<void> _complete(UpdatePartial p) async {
    if (_checking) return;
    _checking = true;
    _run?.quiet?.cancel();
    try {
      final path = p.finish();
      final ok = sameBytes(await sha256OfFile(path), p.object);
      if (!identical(_partial, p)) return;
      if (!ok) {
        updateTrace('discard',
            object: p.object,
            reason: 'complete, but SHA-256 does not match — the state is deleted');
        discard(p.object);
        return;
      }
      updateTrace('object-complete',
          object: p.object,
          reason: '${p.length} B, SHA-256 matches — ${_run == null ? 'by cover fill, no run' : 'in a run'}');
      final r = _run;
      if (r != null) {
        _end(r, path, 'complete (${p.length} B)');
      } else {
        onComplete?.call(p.object, path);
      }
    } on FileSystemException catch (e) {
      report?.call('Update collector: completing failed: $e');
      final r = _run;
      if (r != null) _end(r, null, 'completing failed');
    } finally {
      _checking = false;
    }
  }

  void _end(UpdateRun l, String? path, String reason) {
    l.quiet?.cancel();
    if (identical(_run, l)) _run = null;
    updateTrace('fetch-end',
        object: _partial?.object,
        reason: '$reason — ${path == null ? 'without result, ${_partial?.describe()}' : 'object'}');
    report?.call('Update collector: ${_partial == null ? '-' : objectShort(_partial!.object)} $reason');
    if (!l.result.isCompleted) l.result.complete(path);
  }
}
