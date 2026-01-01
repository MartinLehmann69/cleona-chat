/// The assembler — the side that FETCHES an object of the public update
/// (V4.2 §26.6.1 „The fetch path", decision P1 of 14.09.2026). S387.
///
/// Flow per holder: request without task → task → request with task → up
/// to [UpdateAssembler.piecesPerAnswer] pieces. If the round is full, or
/// [UpdateAssembler.restPeriod] passes without a further piece: if something
/// new was among them, the next request to the same holder; if nothing was among them,
/// the next holder. After the last one the run ends without result — the
/// next occasion (start, network change, app opened, new neighbour) asks
/// again („asks again at the next such moment").
///
/// **No clock.** The next request follows the ARRIVAL of a round;
/// the quiet period ends a round, it does not trigger one.
///
/// **The request names the object, never a piece**, and it does not depend on the
/// cover stream: this route carries the update even with the cover stream
/// switched off (§3.1 test sentence, decision A).
///
/// Pieces are accepted only from the holder currently asked. The finished
/// state is checked against SHA-256 of the object; if it does not match, the
/// whole state is discarded (§26.6.1 self-healing) and the run ends without
/// result.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:cleona/core/fountain/fountain_decoder.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/update_piece.dart';

/// How long a round waits for the next piece. PROVISIONAL —
/// decision point in report S387 (cellular round trip against waiting time
/// with a mute holder).
const Duration kRestPeriod = Duration(milliseconds: 800);

/// This many rounds in a row without a new piece, then the next holder.
///
/// Measured (S387, `smoke_update_piece` (3)): with ONE round the
/// assembler gave up its only holder at 20 % loss as soon as the first
/// request or the task got lost — „1 requests, 0 pieces". Three, like
/// the attempts of the splitter (`split.dart` `kHoechstensAnlaeufe`). Price:
/// a mute holder costs 3 × [kRestPeriod] instead of one. PROVISIONAL.
const int kEmptyRoundsPerHolder = 3;

/// How many unrequested pieces the pool holds per object until a
/// request fetches them ([UpdateAssembler.aside]).
///
/// 1024 x 1041 B = **1.07 MB per object**, with [kPoolObjects] thus
/// at most 2.14 MB. The number is measured on the superseded layer,
/// which kept the same item (`cover_fill_blocks.dart`: 1024 blocks
/// per object, own pot next to the holder service) — and it is the
/// SMALLER of the two limits: a 5-MB object needs roughly 5000 blocks,
/// so the pool contributes at most a fifth of them. More would
/// not be justifiable on the retention-bounded level (§22.6), and the
/// level is not distinguished here: what the node ACCEPTS is the same on
/// all platforms — only the pushing is distinguished (§5.5).
const int kPoolPerObject = 1024;

/// For how many objects a pool is kept at the same time. Two:
/// the current target and the previous one, so that a version change does not throw
/// the pool away in the middle. The third displaces the oldest.
const int kPoolObjects = 2;

class _Run {
  final Uint8List object;
  final FountainDecoder decoder;
  final List<UpdateNeighbour> holder;
  final Completer<Uint8List?> result = Completer();

  /// A run does not accept more pieces than this from ONE holder — a
  /// holder that endlessly sends pieces that never make up an object
  /// would otherwise hold the run fast.
  final int upperLimitPerHolder;
  int holderNo = 0;
  Uint8List? task;
  int tasksFromHolder = 0;
  int piecesFromHolder = 0;
  int emptyRounds = 0;
  int inRound = 0;
  int newInRound = 0;
  Timer? deadline;

  _Run(this.object, this.decoder, this.holder, int piecesPerAnswer)
      : upperLimitPerHolder =
            3 * FountainBlock.sourceBlockCount(decoder.objectLength) +
                2 * piecesPerAnswer;
}

class UpdateAssembler {
  final UpdateSend send;
  final Duration restPeriod;
  final int piecesPerAnswer;
  final void Function(String)? report;
  _Run? _run;

  /// Unrequested pieces, by fountain identifier (8 B, hex). See
  /// [aside].
  final Map<String, List<FountainBlock>> _pool = {};

  /// The identifiers that this node ITSELF has already fetched or is currently
  /// fetching — youngest last. Only for them does [aside] accept anything.
  final List<String> _expected = [];

  /// Diagnostics over the lifetime.
  int receivedPieces = 0;
  int sentPleas = 0;

  /// Unrequested pieces: accepted or rejected ([aside]).
  int asidePieces = 0;
  int asideDropped = 0;

  /// Unrequested pieces that a request has taken over from the pool.
  int outPool = 0;

  UpdateAssembler({
    required this.send,
    this.restPeriod = kRestPeriod,
    this.piecesPerAnswer = kPiecesPerAnswer,
    this.report,
  });

  bool get runs => _run != null;

  /// Fetches [object] (SHA-256, [length] B) from [withWhom], in order.
  /// `null`: no holder delivered a matching object. If a run for THE SAME
  /// object is already running, the caller gets its result.
  Future<Uint8List?> fetch({
    required Uint8List object,
    required int length,
    required List<UpdateNeighbour> withWhom,
  }) {
    if (object.length != kObjectLength) {
      throw ArgumentError('Object must be $kObjectLength B');
    }
    final l = _run;
    if (l != null) {
      if (sameBytes(l.object, object)) return l.result.future;
      throw StateError('a different object is being fetched — abort first');
    }
    final run = _Run(
      Uint8List.fromList(object),
      FountainDecoder(objectId: fountainIdentifier(object), objectLength: length),
      List.of(withWhom),
      piecesPerAnswer,
    );
    _run = run;
    // What arrived unrequested counts BEFORE the first request — it saves requests,
    // it does not replace them (§26.6.1: „Push makes fetching cheaper; it does
    // not replace it"). If the pool is empty, from here on everything runs as
    // without it.
    _expect(_identifier(object));
    final v = _pool.remove(_identifier(object));
    if (v != null) {
      for (final b in v) {
        if (run.decoder.offer(b) != FountainOffer.foreign) outPool++;
      }
      report?.call('Update collector: ${objectShort(object)} — ${v.length} '
          'piece(s) taken over from the pool');
    }
    if (run.decoder.isComplete) {
      _done(run);
    } else {
      _pleas(run);
    }
    return run.result.future;
  }

  /// A piece that did NOT come from a round: it lay in a packet that
  /// was flying anyway (§5.5 rule 2, §26.6.1 „Push over cover fill").
  /// `true` if it was accepted.
  ///
  /// Three caps, in this order:
  ///
  /// 1. only for an object that this node itself has already fetched
  ///    or is currently fetching. What was never asked for is never stored —
  ///    this way §5.5 („retention-bounded nodes keep only their own
  ///    platform's pieces") holds without this layer knowing the platform,
  ///    and a stranger cannot occupy memory that the node did not
  ///    want anyway;
  /// 2. at most [kPoolObjects] such objects;
  /// 3. at most [kPoolPerObject] pieces per object.
  ///
  /// **Never a packet.** This place does not send, plans nothing and
  /// ends no round: [_Run.inRound] and [_Run.newInRound] stay
  /// untouched, so that the rhythm of the requests is the same as without
  /// this route (§3.1). The only thing it may do is make a run FINISHED
  /// when the piece resolves the last source block.
  bool aside(FountainBlock block) {
    final id = _identifier(block.objectId);
    if (!_expected.contains(id)) {
      asideDropped++;
      return false;
    }
    final l = _run;
    if (l != null && _identifier(l.object) == id) {
      if (l.decoder.offer(block) == FountainOffer.foreign) {
        asideDropped++;
        return false;
      }
      asidePieces++;
      if (l.decoder.isComplete) _done(l);
      return true;
    }
    final list = _pool.putIfAbsent(id, () => <FountainBlock>[]);
    if (list.length >= kPoolPerObject) {
      asideDropped++;
      return false;
    }
    list.add(block);
    asidePieces++;
    return true;
  }

  void _expect(String id) {
    _expected
      ..remove(id)
      ..add(id);
    while (_expected.length > kPoolObjects) {
      _pool.remove(_expected.removeAt(0));
    }
  }

  /// The 8-B fountain identifier as text. [b] is either the 32-B object
  /// or the identifier itself.
  static String _identifier(Uint8List b) => b
      .sublist(0, kFountainObjectIdBytes)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();

  /// Ends a running run without result — a newer manifest has
  /// made another object the target (Z1).
  void abort() {
    final l = _run;
    if (l != null) _end(l, null, 'abgebrochen');
  }

  /// Packets of kinds 0x71-0x73. Every other kind is ignored.
  void receive(Uint8List packet, InternetAddress from, int fromPort) {
    final l = _run;
    if (l == null || packet.isEmpty || l.holderNo >= l.holder.length) return;
    final h = l.holder[l.holderNo];
    if (h.$1.address != from.address || h.$2 != fromPort) return;
    switch (packet[0]) {
      case kinds.kPieceTask:
        final a = pleaOrTaskRead(packet);
        // At most two tasks per holder: a second one is only needed
        // when its window changes; more would be ping-pong with a
        // forged source.
        if (a == null ||
            !sameBytes(a.object, l.object) ||
            l.tasksFromHolder >= 2) {
          return;
        }
        l.tasksFromHolder++;
        l.task = a.task;
        _pleas(l);
      case kinds.kNoPieces:
        final o = noRead(packet);
        if (o == null || !sameBytes(o, l.object)) return;
        _nextHolder(l, 'does not have it');
      case kinds.kUpdatePiece:
        final block = pieceRead(packet);
        if (block == null) return;
        final finding = l.decoder.offer(block);
        if (finding == FountainOffer.foreign) return;
        receivedPieces++;
        l.inRound++;
        l.piecesFromHolder++;
        if (finding != FountainOffer.duplicate) l.newInRound++;
        if (l.decoder.isComplete) {
          _done(l);
        } else if (l.piecesFromHolder > l.upperLimitPerHolder) {
          _nextHolder(l, 'upper limit ${l.upperLimitPerHolder} without object');
        } else if (l.inRound >= piecesPerAnswer) {
          _roundEnd(l);
        }
    }
  }

  void _pleas(_Run l) {
    l.deadline?.cancel();
    if (l.holderNo >= l.holder.length) {
      _end(l, null, 'no holder delivered the object');
      return;
    }
    l.inRound = 0;
    l.newInRound = 0;
    send(pleaPacket(l.object, l.task ?? Uint8List(kTaskLength)),
        l.holder[l.holderNo]);
    sentPleas++;
    l.deadline = Timer(restPeriod, () => _roundEnd(l));
  }

  void _roundEnd(_Run l) {
    if (!identical(_run, l)) return;
    l.deadline?.cancel();
    if (l.newInRound > 0) {
      l.emptyRounds = 0;
      _pleas(l);
    } else if (++l.emptyRounds < kEmptyRoundsPerHolder) {
      _pleas(l);
    } else {
      _nextHolder(l, '$kEmptyRoundsPerHolder rounds without a new piece');
    }
  }

  void _nextHolder(_Run l, String reason) {
    if (l.holderNo < l.holder.length) {
      final h = l.holder[l.holderNo];
      report?.call('Update collector: ${objectShort(l.object)} at '
          '${h.$1.address}:${h.$2} — $reason, next holder');
    }
    l.holderNo++;
    l.task = null;
    l.tasksFromHolder = 0;
    l.piecesFromHolder = 0;
    l.emptyRounds = 0;
    _pleas(l);
  }

  void _done(_Run l) {
    final bytes = l.decoder.takeObject();
    if (bytes != null && sameBytes(SodiumFFI().sha256(bytes), l.object)) {
      // Fetched no longer means wanted: from now on [aside] rejects pieces
      // of this object instead of filling a pool for nothing.
      _expected.remove(_identifier(l.object));
      _pool.remove(_identifier(l.object));
      _end(l, bytes, 'complete (${bytes.length} B)');
    } else {
      _end(l, null, 'complete, but SHA-256 does not match — version discarded');
    }
  }

  void _end(_Run l, Uint8List? bytes, String reason) {
    l.deadline?.cancel();
    if (identical(_run, l)) _run = null;
    report?.call('Update collector: ${objectShort(l.object)} $reason');
    if (!l.result.isCompleted) l.result.complete(bytes);
  }
}
