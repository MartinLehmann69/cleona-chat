/// The sender of lane 2 (§17.6): asks a volunteer, joins, streams the
/// sealed pieces, repairs what the recipient names, and falls back to
/// lane 3 when the stream cannot finish.
///
/// Cascade (§17.6 "Cascade and windows"): ask up to three candidates, 10 s
/// each ([askVolunteer]) → the offer goes to the recipient as an ordinary
/// delivery (the caller's `offer`) → join and wait for the volunteer's echo,
/// connect window 30 s → stream. No payload byte leaves before the session
/// stands. The volunteer lost (no mark, list or echo within the loss
/// deadline) → ONE retry with the next candidates, which resumes where the
/// recipient stands; lost again → "fall back to lane 3", naming the stripes
/// the recipient cannot decode as far as they are known.
///
/// ## Rate ([kStreamRate], adaptive by halving)
/// 256 frames/s at the start — 1200 B each on the wire, about 300 KB/s,
/// eight times `R_bulk`. A SETTING, not a measurement (Appendix C): §17.6
/// says "adaptive" and names no number. It is halved, down to `R_bulk`,
/// when a mark window or a request shows more than 10 % missing.
///
/// ## Loss of the volunteer
/// The recipient sends a mark every [kTallyEvery] frames it receives (a
/// count, not a clock; about every 2 s at 256/s). While streaming, the
/// sender checks before each frame whether it has heard the volunteer
/// within 10 s plus one mark window; after a pass it sends the end of the
/// pass (`0x5A` form 4, S407 M-1) and waits 10 s for the recipient's list
/// (§17.4 rule), repeating the end once after [kPassEndAgain]. Without an
/// answer the volunteer counts as lost. Nothing runs between transfers.
library;

import 'dart:async';
import 'dart:io' show InternetAddress;
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/bulk_piece.dart';
import 'package:mycelium/card_address.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/media.dart' show kPiecesPerStripe, stripeForm, stripeNumber;
import 'package:mycelium/silence.dart';
import 'package:mycelium/split.dart' show kAtMostAttempts;
import 'package:mycelium/stream_frame.dart';
import 'package:mycelium/stream_volunteer.dart' show kStreamConnect, kStreamLoss;

const String kRecipientGaveUp = 'the recipient gave up after its request and three repeats';

/// Frames per second at the start of a stream (setting, see above).
const int kStreamRate = 256;

/// The recipient marks every this many frames received.
const int kTallyEvery = 512;

/// §17.6: "ask up to three candidates (10 s)".
const int kAskAtMost = 3;
const Duration kAskWait = Duration(seconds: 10);

/// After a retry: how long the sender waits for the recipient's list of what
/// it still lacks before streaming everything again.
const Duration kResumeWait = Duration(seconds: 2);

/// After an end of pass without an answer: when it is sent once more
/// (setting; the recipient answers 300 ms after the last frame, §11.3).
const Duration kPassEndAgain = Duration(seconds: 1);

typedef StreamSession = ({
  CardAddress volunteer,
  Uint8List senderCookie,
  Uint8List recipientCookie,
});

/// What asking gave: a session or none, and every candidate's verdict
/// (-1 = no answer within 10 s). [next] is where a retry continues.
typedef StreamAsked = ({
  StreamSession? session,
  int next,
  List<({CardAddress at, int verdict})> answers,
});

class StreamResult {
  /// The recipient decoded the object.
  final bool done;

  /// Stripes the recipient cannot decode, as far as known; `null` unknown.
  final List<int>? missingStripes;
  final String reason;
  final int frames;
  final int bytes;
  final int sessions;
  final int rate;
  final Duration took;
  StreamResult(this.done, this.missingStripes, this.reason, this.frames,
      this.bytes, this.sessions, this.rate, this.took);

  /// Take lane 3 for the remainder (§17.6).
  bool get fallback => !done;

  /// The recipient gave up and kept what it opened: [missingStripes] is its
  /// final word, so lane 3 needs to carry only those (S407 M-2).
  bool get recipientGaveUp => reason == kRecipientGaveUp;
}

enum _End { done, gaveUp, lost, noJoin }

class _Run {
  final StreamSession s;
  final Completer<void> paired = Completer<void>();
  final List<MissingRead> lists = [];
  Completer<void>? waiting;
  DateTime heard = DateTime.now();
  int tallied = 0;
  int sentAtMark = 0;
  _Run(this.s);
}

class StreamSender {
  final void Function(Uint8List packet, CardAddress to) _send;
  final void Function(String)? report;
  final BulkPace pace = BulkPace(kStreamRate);
  final Map<String, (CardAddress, Completer<StreamAnswer>)> _asks = {};
  _Run? _run;
  int _sent = 0;
  int _bytes = 0;
  List<int>? _known;

  /// Where the ask is repeated and given up (§11.3a) — the node's.
  final Silence silence;

  StreamSender(
      {required void Function(Uint8List, CardAddress) send,
      this.report,
      Silence? silence})
      : _send = send,
        silence = silence ?? Silence();

  /// Handles a lane-2 packet meant for a sender; `false` otherwise.
  bool receive(Uint8List p, CardAddress from) {
    if (p[0] == kinds.kStreamAnswer) {
      final a = readAnswer(p);
      final w = a == null ? null : _asks[tagHex(a.random)];
      if (w == null || !w.$1.equal(from)) return false;
      if (!w.$2.isCompleted) w.$2.complete(a);
      return true;
    }
    final r = _run;
    final c = streamCookie(p);
    if (r == null || c == null || !cookieSame(c, r.s.senderCookie) ||
        !r.s.volunteer.equal(from)) {
      return false;
    }
    r.heard = DateTime.now();
    if (isJoin(p)) {
      if (!r.paired.isCompleted) r.paired.complete();
    } else if (p[0] == kinds.kStreamMissing) {
      final m = readMissing(p);
      if (m == null) return true;
      if (m.form == kMissingMark) {
        _mark(r, m.received);
        return true;
      }
      r.lists.add(m);
      r.waiting?.complete();
      r.waiting = null;
    }
    return true;
  }

  /// Per mark window: frames received against frames sent since the last
  /// mark. Frames in flight shift from one window to the next and cancel.
  void _mark(_Run r, int received) {
    final got = received - r.tallied;
    final sent = _sent - r.sentAtMark;
    r
      ..tallied = received
      ..sentAtMark = _sent;
    if (sent > 0 && got < sent * 0.9) _halve('mark: $got of $sent');
  }

  void _halve(String why) {
    final was = pace.rate;
    pace.rate = max(kRBulk, pace.rate ~/ 2);
    if (pace.rate != was) report?.call('Stream: rate $was -> ${pace.rate}/s ($why)');
  }

  /// Asks candidates from [start] on, one after another, at most three,
  /// 10 s each (§17.6). Size and a random value — no identity.
  Future<StreamAsked> askVolunteer(int size, List<CardAddress> candidates,
      {int start = 0}) async {
    final answers = <({CardAddress at, int verdict})>[];
    var i = start;
    for (; i < candidates.length && answers.length < kAskAtMost; i++) {
      final at = candidates[i];
      final random = SodiumFFI().randomBytes(kAskRandomLength);
      final w = Completer<StreamAnswer>();
      _asks[tagHex(random)] = (at, w);
      final ask = askPacket(size, random);
      StreamAnswer? a;
      try {
        // The ask and its repeats share the candidate's 10 s (§17.6,
        // §11.3a); the volunteer answers a repeat as the first.
        final ip = InternetAddress.fromRawAddress(Uint8List.fromList(at.address));
        final got = await silence.ask(w.future,
            to: ip,
            port: at.port,
            send: (_, __) => _send(ask, at),
            wait: kAskWait ~/ kSendingsAtMost,
            others: false,
            what: 'stream ask 0x56');
        a = got == null ? null : await w.future;
      } finally {
        _asks.remove(tagHex(random));
      }
      answers.add((at: at, verdict: a?.verdict ?? -1));
      if (a != null && a.verdict == kVerdictGranted) {
        return (
          session: (
            volunteer: at,
            senderCookie: a.senderCookie,
            recipientCookie: a.recipientCookie,
          ),
          next: i + 1,
          answers: answers,
        );
      }
    }
    return (session: null, next: i, answers: answers);
  }

  /// The whole of lane 2 for one object: ask, [offer], stream, one retry,
  /// fallback. [offer] delivers the STREAM_OFFER to the recipient
  /// (`streamOfferPack`) — an ordinary delivery of the layer above.
  Future<StreamResult> streamSend({
    required Uint8List object,
    required Uint8List transferKey,
    required List<CardAddress> candidates,
    required Future<void> Function(CardAddress volunteer, Uint8List cookie) offer,
    void Function(int sent, int total)? progress,
  }) async {
    final began = DateTime.now();
    _sent = 0;
    _bytes = 0;
    _known = null;
    pace.rate = kStreamRate;
    final all = [for (var s = 0; s < stripeNumber(object.length); s++) s];
    var sessions = 0;
    StreamResult out(bool done, String why, [List<int>? missing]) =>
        StreamResult(done, done ? const [] : missing, why, _sent, _bytes,
            sessions, pace.rate, DateTime.now().difference(began));
    if (object.isEmpty || object.length > kStreamCap) {
      return out(false, 'above C — lane 3 without asking (D-1)', all);
    }
    final blocks = stripeForm(object);
    var asked = await askVolunteer(object.length, candidates);
    for (var attempt = 0; attempt < 2; attempt++) {
      final s = asked.session;
      if (s == null) {
        return out(false, 'no volunteer accepted', _sent == 0 ? all : _known);
      }
      sessions++;
      await offer(s.volunteer, s.recipientCookie);
      final e = await _stream(blocks, transferKey, s, attempt > 0, progress);
      switch (e) {
        case _End.done:
          return out(true, 'done');
        case _End.gaveUp:
          return out(false, kRecipientGaveUp, _known);
        case _End.noJoin:
          return out(false, 'no pairing within the connect window',
              _sent == 0 ? all : _known);
        case _End.lost:
          report?.call('Stream: volunteer ${s.volunteer} lost');
          if (attempt == 0) {
            asked = await askVolunteer(object.length, candidates,
                start: asked.next);
          }
      }
    }
    return out(false, 'volunteer lost twice', _known);
  }

  Future<_End> _stream(List<Uint8List> blocks, Uint8List transferKey,
      StreamSession s, bool resume,
      void Function(int sent, int total)? progress) async {
    final r = _run = _Run(s)..sentAtMark = _sent;
    try {
      // The join expects its echo: repeated by the transport within the
      // connect window (§17.6, §11.3a — until S407 its own 3/7/20 s).
      final join = joinPacket(s.senderCookie);
      await silence.ask(r.paired.future,
          to: InternetAddress.fromRawAddress(Uint8List.fromList(s.volunteer.address)),
          port: s.volunteer.port,
          send: (_, __) => _send(join, s.volunteer),
          wait: kStreamConnect ~/ kSendingsAtMost,
          others: false,
          what: 'stream join 0x58');
      if (!r.paired.isCompleted) return _End.noJoin;
      r.heard = DateTime.now();
      final tag = bulkTag(transferKey);
      final seal = bulkSealKey(transferKey);
      final total = blocks.length;
      var todo = [for (var i = 0; i < total; i++) i];
      if (resume) {
        final m = await _next(r, kResumeWait);
        if (m != null && m.form == kMissingRequest) todo = _listed(m.request);
      }
      var pass = 0;
      while (true) {
        for (final i in todo) {
          final window = Duration(
              milliseconds: kTallyEvery * 1000 ~/ max(1, pace.rate));
          if (DateTime.now().difference(r.heard) > kStreamLoss + window) {
            return _End.lost;
          }
          await pace.turn();
          final st = i ~/ kPiecesPerStripe, no = i % kPiecesPerStripe;
          _send(framePacket(s.senderCookie, st, no,
              pieceSeal(seal, tag, st, no, blocks[i])), s.volunteer);
          _sent++;
          _bytes += kFrameLength;
          progress?.call(_sent, total);
        }
        final m = await _passEnd(r, s, pass);
        if (m == null) return _End.lost;
        if (m.form == kMissingDone) return _End.done;
        if (m.form == kMissingGiveUp) {
          _known = m.stripes;
          return _End.gaveUp;
        }
        todo = _listed(m.request);
        _known = m.request.keys.toList()..sort();
        if (++pass > kAtMostAttempts) todo = const [];
        if (todo.length > total * 0.1) _halve('request: ${todo.length} of $total');
      }
    } finally {
      if (_run == r) _run = null;
    }
  }

  static List<int> _listed(Missing m) => [
        for (final e in m.entries)
          for (var no = 0; no < kPiecesPerStripe; no++)
            if (e.value & (1 << no) != 0) e.key * kPiecesPerStripe + no
      ];

  /// §11.3 "after the last frame": the end of [pass], then the recipient's
  /// answer to it. Repeated [kPassEndAgain] apart without one, at most
  /// [kRepeatsAtMost] times (§17.6, §11.3a) — a lost end would otherwise
  /// cost the whole loss deadline.
  Future<MissingRead?> _passEnd(_Run r, StreamSession s, int pass) async {
    final p = streamPassEndPacket(s.senderCookie, pass, _sent);
    for (var n = 0; n < kRepeatsAtMost; n++) {
      _send(p, s.volunteer);
      final m = await _next(r, kPassEndAgain, pass);
      if (m != null) return m;
    }
    _send(p, s.volunteer);
    return _next(r, kStreamLoss - kPassEndAgain * kRepeatsAtMost, pass);
  }

  /// The next list within [limit]. After [pass] only its own answer counts:
  /// a request of another round is a repeat for an earlier end and is
  /// dropped, so that it is never taken for the answer to this one.
  Future<MissingRead?> _next(_Run r, Duration limit, [int? pass]) async {
    final end = DateTime.now().add(limit);
    for (;;) {
      while (r.lists.isNotEmpty) {
        final m = r.lists.removeAt(0);
        if (pass == null || m.form != kMissingRequest || m.round == pass + 1) {
          return m;
        }
      }
      final left = end.difference(DateTime.now());
      if (left <= Duration.zero) return null;
      final w = r.waiting = Completer<void>();
      try {
        await w.future.timeout(left);
      } on TimeoutException {
        return null;
      }
    }
  }
}
