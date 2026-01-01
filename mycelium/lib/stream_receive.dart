/// The recipient of lane 2 (§17.6): joins the volunteer the offer names,
/// opens the frames, asks once for what is missing, and hands over to
/// lane 3 what the stream could not bring.
///
/// Loss repair follows §11.3: after the last frame and 300 ms without a new
/// one, ONE `0x5A` names the missing pieces of every stripe that cannot be
/// decoded yet, at most 3 rounds. "The last frame" is the one before the
/// sender's end of pass (`0x5A` form 4, S407 M-1): a pause on the path in
/// the middle of a pass is no round. A repeated end of the same pass gets
/// the same list again. Still undecodable after the third →
/// give-up to the sender and [StreamFallback] to the layer above, which
/// takes lane 3 for the rest. There is no per-frame acknowledgement; a
/// mark every [kTallyEvery] frames (a count) lets the sender see that the
/// volunteer still carries and adapt its rate.
///
/// Pieces are lane-neutral (§9.4): [StreamFallback.pieces] holds every
/// piece already opened, so lane 3 needs to bring only the rest. A join for
/// a transfer already open (the sender's retry with another volunteer)
/// continues the same collection.
///
/// NO RENEGING (§17.6 "the recipient keeps what it opened"; the rule of
/// QUIC, RFC 9002 §3: what is acknowledged stays acknowledged). A stripe
/// the give-up does not name, the sender never places (S407 M-2) — the
/// opened pieces are then the only copy. So the give-up hands them to the
/// join's `keep` first (the collector's disk, `BulkCollector.stash`) and
/// names every stripe where they cannot be kept (S407-N4).
///
/// ## Bounds (§20.2)
/// At most [kReceptionsAtMost] open receptions; one more displaces the
/// oldest (fallback "displaced"). Opened pieces stay in memory until the
/// object is assembled — at most `C` (25 MB) per reception. Clocks exist
/// only while a reception is open: the quiet of 300 ms, the loss deadline
/// of 10 s (§17.4), the connect window of 30 s and, after a loss, the
/// [StreamReceiver.resumeHold] for the sender's one retry.
library;

import 'dart:async';
import 'dart:io' show InternetAddress;
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/bulk_piece.dart';
import 'package:mycelium/card_address.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/media.dart'
    show kPiecesPerStripe, kStripeWidth, objectFromPieces, stripeNumber;
import 'package:mycelium/silence.dart';
import 'package:mycelium/split.dart' show kAtMostAttempts, kRestPeriod;
import 'package:mycelium/stream_frame.dart';
import 'package:mycelium/stream_send.dart' show kTallyEvery;
import 'package:mycelium/stream_volunteer.dart' show kStreamConnect, kStreamLoss;

const int kReceptionsAtMost = 4;

class StreamFallback {
  final Uint8List tag;

  /// Stripes below seven pieces — what lane 3 must still bring.
  final List<int> missingStripes;

  /// Every opened piece: stripe -> (number -> 1024 B block).
  final Map<int, Map<int, Uint8List>> pieces;
  final String reason;
  StreamFallback(this.tag, this.missingStripes, this.pieces, this.reason);
}

typedef OnStreamObject = void Function(Uint8List tag, Uint8List object);
typedef OnStreamFallback = void Function(StreamFallback f);
typedef OnStreamProgress = void Function(Uint8List tag, int complete, int stripes);

/// Keeps the opened pieces of a give-up across a restart; `false` if it
/// cannot (see NO RENEGING above).
typedef OnStreamKeep = bool Function(
    Uint8List tag, Map<int, Map<int, Uint8List>> pieces);

/// A 4.2.x sender that predates the end of pass sends none, and a 4.2.3
/// volunteer does not hand one on (S407-KOMPAT #3). Until the first end of
/// pass arrives, a quiet of this length after the last frame counts as the
/// end — §11.3 for a transmission without end mark (D-41: quiet 300 ms +
/// answer deadline 800 ms). A pause shorter than that stays no round.
const Duration kNoPassEndQuiet = Duration(milliseconds: 1100);

class _Reception {
  final Uint8List tag;
  final Uint8List seal;
  final int length;
  final Uint8List sha256;
  final int stripes;
  final Map<int, Map<int, Uint8List>> per = {};
  int complete = 0;
  late CardAddress volunteer;
  late Uint8List cookie;
  bool paired = false;
  Completer<void> pairing = Completer<void>(); // the join's answer (§11.3a)
  int received = 0;
  int rounds = 0;

  /// The latest end of pass seen (-1 none) and the list that answered it.
  int passSeen = -1;
  Uint8List? answer;
  DateTime last = DateTime.now();
  Timer? quiet;
  Timer? loss;
  Timer? hold;
  OnStreamObject? onObject;
  OnStreamFallback? onFallback;
  OnStreamProgress? progress;
  OnStreamKeep? keep;
  _Reception(Uint8List k, this.length, this.sha256)
      : tag = bulkTag(k),
        seal = bulkSealKey(k),
        stripes = stripeNumber(length);

  void cancel() {
    quiet?.cancel();
    loss?.cancel();
    hold?.cancel();
  }
}

class StreamReceiver {
  final void Function(Uint8List packet, CardAddress to) _send;
  final void Function(String)? report;

  /// After the volunteer is lost: how long the reception waits for the
  /// sender's one retry — three asks and a connect window (§17.6).
  Duration resumeHold = const Duration(seconds: 60);

  /// The connect window the join and its repeats share (§17.6) — probes
  /// shorten it.
  Duration connectWindow = kStreamConnect;

  /// Frames with a valid cookie whose piece did not open — for probes.
  int rejected = 0;

  final Map<String, _Reception> _open = {};

  /// Where the join is repeated and given up (§11.3a) — the node's.
  final Silence silence;

  StreamReceiver(
      {required void Function(Uint8List, CardAddress) send,
      this.report,
      Silence? silence})
      : _send = send,
        silence = silence ?? Silence();

  int get openReceptions => _open.length;

  /// Joins [volunteer] with [cookie] (from the offer) for the object the
  /// announcement describes. For a transfer already open it moves the
  /// collection to the new session. Without [keep] a give-up names every
  /// stripe (nothing it opened is promised to stay).
  Uint8List join({
    required CardAddress volunteer,
    required Uint8List cookie,
    required Uint8List transferKey,
    required int length,
    required Uint8List sha256,
    OnStreamObject? onObject,
    OnStreamFallback? onFallback,
    OnStreamProgress? progress,
    OnStreamKeep? keep,
  }) {
    if (transferKey.length != kTransferKeyLength || sha256.length != 32 ||
        length <= 0 || length > kStreamCap || cookie.length != kCookieLength) {
      throw ArgumentError('join: K_T 32 B, SHA-256 32 B, 0 < length <= C, '
          'cookie 8 B');
    }
    final k = tagHex(bulkTag(transferKey));
    var r = _open[k];
    if (r == null) {
      if (_open.length >= kReceptionsAtMost) {
        _giveUp(_open.values.first, 'displaced — more than '
            '$kReceptionsAtMost open receptions (§20.2)');
      }
      r = _open[k] = _Reception(transferKey, length, sha256);
    }
    r
      ..cancel()
      ..volunteer = volunteer
      ..cookie = Uint8List.fromList(cookie)
      ..paired = false
      ..pairing = Completer<void>()
      ..received = 0
      ..rounds = 0
      ..passSeen = -1
      ..answer = null
      ..onObject = onObject ?? r.onObject
      ..onFallback = onFallback ?? r.onFallback
      ..progress = progress ?? r.progress
      ..keep = keep ?? r.keep;
    _knock(r);
    return r.tag;
  }

  /// The join `0x58` expects its echo: repeated by the transport within
  /// the connect window (§17.6, §11.3a — until S407 its own 0/3/10 s);
  /// without an echo the reception gives up.
  void _knock(_Reception r) {
    final pairing = r.pairing, join = joinPacket(r.cookie);
    bool gone() => _open[tagHex(r.tag)] != r || !identical(r.pairing, pairing);
    unawaited(silence
        .ask(pairing.future,
            to: InternetAddress.fromRawAddress(Uint8List.fromList(r.volunteer.address)),
            port: r.volunteer.port,
            send: (_, __) => _send(join, r.volunteer),
            wait: connectWindow ~/ kSendingsAtMost,
            others: false,
            cancelled: gone,
            what: 'stream join 0x58')
        .then((at) {
      if (at == null && !r.paired && !gone()) {
        _giveUp(r, 'no pairing within the connect window');
      }
    }));
  }

  _Reception? _of(Uint8List c, CardAddress from) {
    for (final r in _open.values) {
      if (cookieSame(r.cookie, c) && r.volunteer.equal(from)) return r;
    }
    return null;
  }

  /// Handles a lane-2 packet meant for a recipient; `false` otherwise.
  bool receive(Uint8List p, CardAddress from) {
    final c = streamCookie(p);
    final r = c == null ? null : _of(c, from);
    if (r == null) return false;
    if (isJoin(p)) {
      if (!r.paired) _paired(r);
      return true;
    }
    if (p[0] == kinds.kStreamMissing) {
      final m = readMissing(p);
      if (m != null && m.form == kMissingPassEnd) _passEnd(r, m.round);
      return true;
    }
    if (p[0] != kinds.kStreamFrame) return true;
    final f = readFrame(p);
    if (f == null || f.stripe >= r.stripes || f.no >= kPiecesPerStripe) {
      return true;
    }
    if (!r.paired) _paired(r);
    r
      ..last = DateTime.now()
      ..received += 1;
    if (r.passSeen < 0) r.quiet ??= Timer(kNoPassEndQuiet, () => _quiet(r));
    if (r.received % kTallyEvery == 0) {
      _send(markPacket(r.cookie, r.received), r.volunteer);
    }
    final there = r.per[f.stripe] ??= {};
    if (there.length >= kStripeWidth || there.containsKey(f.no)) return true;
    final block = pieceOpen(r.seal, r.tag, f.stripe, f.no, f.sealed);
    if (block == null) {
      rejected++;
      report?.call('Stream: frame ${f.stripe}/${f.no} does not open — discarded');
      return true;
    }
    there[f.no] = block;
    if (there.length == kStripeWidth) {
      r.complete++;
      r.progress?.call(r.tag, r.complete, r.stripes);
      if (r.complete == r.stripes) _finish(r);
    }
    return true;
  }

  void _paired(_Reception r) {
    if (!r.pairing.isCompleted) r.pairing.complete();
    r
      ..paired = true
      ..last = DateTime.now();
    r.loss?.cancel();
    r.loss = Timer(kStreamLoss, () => _lossCheck(r));
    // A resumed collection says at once what it still lacks, so that the
    // sender does not stream everything again (round 0, not counted).
    if (r.per.isNotEmpty) _send(requestPacket(r.cookie, 0, _missing(r)), r.volunteer);
  }

  /// Stripe -> mask of the missing numbers, for every stripe below seven.
  Missing _missing(_Reception r) {
    const all = (1 << kPiecesPerStripe) - 1;
    final m = <int, int>{};
    for (var s = 0; s < r.stripes; s++) {
      final there = r.per[s];
      if ((there?.length ?? 0) >= kStripeWidth) continue;
      var have = 0;
      for (final n in there?.keys ?? const <int>[]) {
        have |= 1 << n;
      }
      m[s] = all & ~have;
    }
    return m;
  }

  /// The sender ended [pass]: 300 ms after the last frame the list goes
  /// (§11.3). The same end again: its list was lost — the same list again.
  void _passEnd(_Reception r, int pass) {
    if (pass < r.passSeen) return;
    if (pass == r.passSeen) {
      final a = r.answer;
      if (a != null) _send(a, r.volunteer);
      return;
    }
    r
      ..passSeen = pass
      ..answer = null
      ..last = DateTime.now();
    r.quiet?.cancel();
    r.quiet = Timer(kRestPeriod, () => _quiet(r));
  }

  void _quiet(_Reception r) {
    r.quiet = null;
    if (_open[tagHex(r.tag)] != r) return;
    final wait = r.passSeen < 0 ? kNoPassEndQuiet : kRestPeriod;
    final still = wait - DateTime.now().difference(r.last);
    if (still > Duration.zero) {
      r.quiet = Timer(still, () => _quiet(r));
      return;
    }
    if (r.rounds >= kAtMostAttempts) {
      return _giveUp(r, 'stripes undecodable after $kAtMostAttempts rounds');
    }
    r.rounds++;
    final m = _missing(r);
    report?.call('Stream: round ${r.rounds} after '
        '${r.passSeen < 0 ? 'a quiet of ${kNoPassEndQuiet.inMilliseconds} ms' : 'pass ${r.passSeen}'}, '
        '${m.length} stripes missing');
    // The round answers the pass (round = pass + 1), so that the sender
    // can tell it from a repeat for an earlier end.
    // Without any end of pass (a sender before S407) the round is numbered
    // as 4.2.3 numbered it.
    final round = r.passSeen < 0 ? r.rounds : r.passSeen + 1;
    _send(r.answer = requestPacket(r.cookie, round, m), r.volunteer);
  }

  void _lossCheck(_Reception r) {
    if (_open[tagHex(r.tag)] != r) return;
    final quiet = DateTime.now().difference(r.last);
    if (quiet < kStreamLoss) {
      r.loss = Timer(kStreamLoss - quiet, () => _lossCheck(r));
      return;
    }
    report?.call('Stream: 10 s without a frame — waiting ${resumeHold.inSeconds} s '
        'for a retry');
    r.quiet?.cancel();
    r.quiet = null;
    r.hold = Timer(resumeHold, () => _giveUp(r, 'volunteer lost, no retry'));
  }

  void _finish(_Reception r) {
    _remove(r);
    Uint8List? object;
    try {
      object = objectFromPieces(r.per, r.length);
      final sum = SodiumFFI().sha256(object);
      if (!cookieSame(sum, r.sha256)) object = null;
    } on Object {
      object = null;
    }
    if (object == null) {
      _send(giveUpPacket(r.cookie, [for (var s = 0; s < r.stripes; s++) s]),
          r.volunteer);
      r.onFallback?.call(StreamFallback(r.tag,
          [for (var s = 0; s < r.stripes; s++) s], const {},
          'SHA-256 does not match the announcement'));
      return;
    }
    _send(donePacket(r.cookie), r.volunteer);
    r.onObject?.call(r.tag, object);
  }

  void _giveUp(_Reception r, String why) {
    _remove(r);
    var missing = _missing(r).keys.toList()..sort();
    // NO RENEGING (head): a stripe left unnamed must stay here.
    final kept = r.per.isNotEmpty && (r.keep?.call(r.tag, r.per) ?? false);
    if (!kept) missing = [for (var s = 0; s < r.stripes; s++) s];
    if (r.paired) _send(giveUpPacket(r.cookie, missing), r.volunteer);
    report?.call('Stream: ${tagHex(r.tag)} to lane 3 — $why '
        '(${missing.length} of ${r.stripes} stripes missing, opened pieces '
        '${kept ? 'kept' : 'not kept'})');
    r.onFallback?.call(StreamFallback(r.tag, missing, r.per, why));
  }

  void _remove(_Reception r) {
    r.cancel();
    _open.remove(tagHex(r.tag));
  }

  void stop() {
    for (final r in _open.values) {
      r.cancel();
    }
  }
}
