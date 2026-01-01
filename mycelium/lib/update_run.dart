/// One run of the fetch path at its holders — the bookkeeping of
/// `update_assembler.dart` (S406-UPDPKG): which holder, its task, the round
/// trip measured, and the current round. No packet, no clock: the
/// assembler sends and arms; this file only counts and computes.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mycelium/update_piece.dart';

/// How long a request waits for the first packet back before it is asked
/// once more — at least; twice the measured round trip if longer (S387).
const Duration kRestPeriod = Duration(milliseconds: 800);

/// §11.3: the quiet gap after the last piece ends an answer — four mean
/// piece intervals within [kPieceGapMin, kPieceGapMax]. A late piece lands
/// in the next round at no cost (every piece is a fresh draw).
const Duration kPieceGapMax = Duration(milliseconds: 300);
const Duration kPieceGapMin = Duration(milliseconds: 30);

/// §26.6.1 "after three answers without a new piece" → the next holder.
const int kEmptyAnswersPerHolder = 3;

class UpdateRun {
  final List<UpdateNeighbour> holder;
  final Completer<String?> result = Completer();

  /// A holder that sends endless pieces that never make the object is left.
  final int upperLimitPerHolder;
  int holderNo = 0;
  Uint8List? task;
  int piecesFromHolder = 0;
  int emptyAnswers = 0;
  bool askedAgain = false;
  Duration? rtt;
  int asked = kPiecesPerAnswer;
  DateTime pleaAt = DateTime.now();
  DateTime? firstAt;
  DateTime? lastAt;
  int inRound = 0;
  int newInRound = 0;
  Timer? quiet;

  UpdateRun(this.holder, int sourceBlocks)
      : upperLimitPerHolder = 3 * sourceBlocks + 2 * kPiecesPerAnswerMax;

  bool get holderLeft => holderNo < holder.length;
  UpdateNeighbour get current => holder[holderNo];

  /// A new request goes out: the count is sized from the round trip (P7).
  void roundStart() {
    asked = piecesPerAnswerFor(rtt);
    inRound = 0;
    newInRound = 0;
    firstAt = null;
    lastAt = null;
    pleaAt = DateTime.now();
  }

  /// How long the request waits for the first packet back.
  Duration silence(Duration restPeriod) {
    final r2 = (rtt ?? Duration.zero) * 2;
    return r2 > restPeriod ? r2 : restPeriod;
  }

  /// Round trip: from the request to the first packet back (smoothed).
  void sample() {
    final s = DateTime.now().difference(pleaAt);
    final o = rtt;
    rtt = o == null ? s : (o * 7 + s) ~/ 8;
  }

  /// A piece of the current answer arrived ([fresh]: not a duplicate).
  void piece({required bool fresh}) {
    if (firstAt == null) sample();
    final now = DateTime.now();
    firstAt ??= now;
    lastAt = now;
    inRound++;
    piecesFromHolder++;
    if (fresh) newInRound++;
  }

  /// The quiet gap that ends the flowing answer.
  Duration gap() {
    final a = firstAt, b = lastAt;
    if (a == null || b == null || inRound < 2) return kPieceGapMax;
    final g = b.difference(a) * 4 ~/ (inRound - 1);
    return g < kPieceGapMin ? kPieceGapMin : (g > kPieceGapMax ? kPieceGapMax : g);
  }

  /// The next holder: nothing of the former one carries over.
  void nextHolder() {
    holderNo++;
    task = null;
    rtt = null;
    piecesFromHolder = 0;
    emptyAnswers = 0;
    askedAgain = false;
  }
}
