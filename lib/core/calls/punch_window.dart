// The punch window (§17.3) — the loop that turns two candidate lists
// into a carrying address pair.
//
// ══ WHAT §17.3 PRESCRIBES, VERBATIM ═══════════════════════════════════════
//
//   "**Punch window instead of a point in time:** after INVITE/ANSWER, both
//    sides send for up to **30 s at 1 packet/s to all of the other side's
//    candidates**. The first address pair on which valid AEAD responses
//    arrive carries the session. A window needs neither synchronized clocks
//    nor a third party."
//
// From this sentence come [kPunchRounds] = 30 and [kPunchInterval] = 1 s.
// Both are COPIED, not chosen.
//
// ══ WHAT §17.3 LEAVES OPEN — THREE OWN CHOICES (step C, S361) ════════
//
// Each one is justified and priced below at its constant. In short:
//
//  1. **"1 packet/s" — per candidate or in total?** Read as: ONE
//     round per second, in which every candidate gets one packet. The
//     other reading (one packet per second in total, round-robin) needs, with
//     eight candidates, eight seconds for the first complete round and
//     thus misses the purpose: a NAT hole only arises if BOTH
//     sides touch the same pair at roughly the same time.
//  2. **How many candidates** — cap in `address_candidates.dart`
//     ([kMaxCallCandidates] = 8).
//  3. **When port prediction runs** — [kPlainRounds] = 15.
//
// ══ THE PRICE, COMPUTED (working rule 12) ═════════════════════════════
//
// A punch packet is a D frame of the class `voice` = **176 B on the
// wire** (§17.1; 160 B on 05.09.2026, 128 B before, and all numbers
// of this block have grown along with it). It is NOT a cell: it goes directly to an address and
// not via the tag line, so it costs **no cover slot and no
// second of egress** — the currency `cells x 8 s` does not apply here. What it
// costs are bytes and packets:
//
//   phase 1 (round 0-14):   15 x  8 candidates =  120 packets
//   phase 2 (round 15-29):  15 x 24 (cap)      =  360 packets
//   echo                                        =    1 packet
//   ─────────────────────────────────────────────────────────
//   worst case per side and call attempt       =  481 packets
//                                               = **84,7 kB**
//
// Peak rate in phase 2: 24 x 176 B = **4.22 kB/s**. A standing
// voice call measures 8.8 kB/s per direction (§17.1: 176 B x 50 frames/s), the
// window thus still lies at **48 %** of a conversation — both
// sides of the comparison have grown with the class — and runs
// at most 30 s. The usual case is a fraction of that: in the LAN
// the first local candidate carries immediately, that is 8 packets plus echo =
// **1.4 kB**.
//
// ══ WHY THERE ARE TWO PHASES AT ALL ═══════════════════════════════
//
// Port prediction generates 20 candidates per affected address
// (§17.3: ±10). If it ran along from round 0, EVERY call would pay its
// price — including the one in the same Wi-Fi, where the first local candidate
// carries. It therefore only runs once the named candidates have not carried
// for 15 s; then the simple explanation ("one of the
// named ones carries") is refuted and the expensive one ("symmetric NAT, the
// carrying port was never named") is the next.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/calls/address_candidates.dart';
import 'package:cleona/core/link_io/d_frame.dart';
import 'package:cleona/core/link_io/d_socket.dart';

/// Interval between two rounds. §17.3 "at 1 packet/s".
const Duration kPunchInterval = Duration(seconds: 1);

/// How many rounds the window runs at most. §17.3 "up to 30 s".
const int kPunchRounds = 30;

/// From which round on port prediction runs along.
///
/// **Own choice; §17.3 names no point in time** (step C finding S361). The
/// spec lists the prediction as a candidate generator for the case
/// "symmetric NAT" and does not say whether it runs from the start.
///
/// **15 = half the window, derived.** Earlier would be too early:
/// the named candidates would not yet have had a fair chance —
/// an ANSWER can arrive at the counterpart up to one harvest cadence later
/// (§17.2 lists "seconds" for Android/desktop background),
/// and until then only one side sends. Later would be too late: under 15
/// rounds every predicted port would only get its turn a few more times,
/// and a prediction that misses once is worthless — it lives
/// from covering a window of 20 ports several times.
const int kPlainRounds = 15;

/// How many packets one round triggers at most.
///
/// **Own choice; it caps the price of the prediction** (step C finding
/// S361). Without it there would be 8 named + 20 predicted = 28 packets per
/// round, and 48 with two affected addresses. The number arises from the
/// comparison: 24 x 176 B = 4.22 kB/s is just under half of a
/// standing voice call per direction (8.8 kB/s, §17.1). A window that
/// needs more wire than the conversation it sets up would be the wrong
/// trade-off — it is meant to enable a conversation, not replace it.
///
/// The named candidates have priority; the predicted ones fill the
/// rest and rotate through over the rounds (see [_zieleFuerRunde]).
const int kMaxPunchPacketsPerRound = 24;

/// How a punch window ended.
final class PunchOutcome {
  /// The carrying address pair, or `null`.
  final InternetAddress? address;
  final int? port;

  /// Why nothing carries — the diagnostic line for log and support, not
  /// translated (the same rule as `CallTransport.mediaUnavailableReason`).
  final String? refusal;

  /// What the window cost. Stands in the result and not merely in the
  /// log, so that a measurement can READ it instead of estimating it.
  final int packetsSent;
  final int bytesSent;

  /// In which round the path was confirmed (−1 if never).
  final int roundCarried;

  const PunchOutcome({
    this.address,
    this.port,
    this.refusal,
    required this.packetsSent,
    required this.bytesSent,
    required this.roundCarried,
  });

  bool get carried => address != null;

  @override
  String toString() => carried
      ? 'PunchOutcome(carries ${address!.address}:$port, round $roundCarried, '
          '$packetsSent packets / $bytesSent B)'
      : 'PunchOutcome(does not carry: $refusal, '
          '$packetsSent packets / $bytesSent B)';
}

/// Runs ONE punch window against the other side's candidates (§17.3).
///
/// The session is already admitted ([DSocket.open]) — it must be,
/// because without an entry in the cookie table the other side's ANSWER
/// would be discarded by the demux (`d_socket.dart`, step 2). Its
/// `peerAddress` is a GUESS at this point; the window
/// replaces it with the finding.
final class PunchWindow {
  final DSession session;
  final List<CallCandidate> peerCandidates;

  /// Is called for every line that should appear in the log. No `CLogger`
  /// here: this module should also run from a standalone smoke, and
  /// a `CLogger` requires a profile directory.
  final void Function(String message)? log;

  /// Solely for measurements: the tick. The usual case is [kPunchInterval].
  final Duration interval;

  PunchWindow({
    required this.session,
    required this.peerCandidates,
    this.log,
    this.interval = kPunchInterval,
  });

  var _packets = 0;
  var _bytes = 0;
  var _aborted = false;

  /// The round currently running — and, after the end, the round in which
  /// the path was CONFIRMED.
  ///
  /// **It is recorded in the callback and not read at the end of the loop.**
  /// Measured on 01.09.: the confirmation occurs during the
  /// `await` at the end of the round, the loop then counts up and only breaks off
  /// at the top — read off, that always yielded one round too many. A value that
  /// is only read AFTER the event does not measure the event.
  var _round = -1;
  var _roundConfirmed = -1;

  /// Aborts a running window (call hung up, rejection harvested).
  void cancel() => _aborted = true;

  /// Runs the window. Returns as soon as a pair carries, the window
  /// has expired or [cancel] occurred.
  Future<PunchOutcome> run({
    List<CallCandidate> ownCandidates = const <CallCandidate>[],
  }) async {
    // ── TWO REFUSALS BEFORE THE FIRST PACKET (§17.3) ────────────────────
    //
    // Both are explicitly in the spec and both are better than 30 s
    // of sending into nothing: "v4-only ↔ v6-only has no common pair — clear
    // message ,no common connection type'" and, for the case without any
    // observable outer address, "no call is possible, messaging
    // unaffected".
    if (peerCandidates.isEmpty) {
      return _cancellation('The other side named no address candidates '
          '(§17.3). Without candidates there is no pair that could carry — '
          'possible with CGNAT without an observable outer address.');
    }
    if (ownCandidates.isNotEmpty &&
        !haveCommonFamily(ownCandidates, peerCandidates)) {
      return _cancellation('No common connection type (§17.3): the own '
          'candidates and those of the other side share no address '
          'family. Messages are unaffected by this.');
    }

    final prediction = predictPorts(peerCandidates);
    log?.call('Punch window (§17.3): ${peerCandidates.length} named '
        'candidates, ${prediction.length} predicted ports, '
        '$kPunchRounds rounds of ${interval.inMilliseconds} ms');

    final done = Completer<void>();
    final before = session.onPathConfirmed;
    session.onPathConfirmed = (a, p) {
      if (_roundConfirmed < 0) _roundConfirmed = _round;
      // The echo: ONE packet back on the path just confirmed. Without
      // it the other side only confirms its own path in its
      // next round — up to one second later, although the hole is
      // open NOW. Exactly one packet, and only because a frame with
      // valid AEAD arrived: the promise from §17.4 ("no response to
      // unknown parties") stays.
      _send(a, p);
      before?.call(a, p);
      if (!done.isCompleted) done.complete();
    };

    try {
      for (_round = 0; _round < kPunchRounds; _round++) {
        if (_aborted || done.isCompleted) break;
        for (final z
            in _targetsForRound(_round, peerCandidates, prediction)) {
          _send(z.address, z.port);
        }
        if (done.isCompleted) break;
        await Future.any(<Future<void>>[
          done.future,
          Future<void>.delayed(interval),
        ]);
      }
    } finally {
      session.onPathConfirmed = before;
    }

    final path = session.confirmedPath;
    if (path != null) {
      log?.call('Punch window carries: ${path.address.address}:${path.port} '
          'in round $_roundConfirmed, $_packets packets / $_bytes B');
      return PunchOutcome(
        address: path.address,
        port: path.port,
        packetsSent: _packets,
        bytesSent: _bytes,
        roundCarried: _roundConfirmed,
      );
    }
    return _cancellation(_aborted
        ? 'The punch window was cancelled before a pair carried.'
        : 'No address pair carried within ${kPunchRounds}s (§17.3). With '
            'symmetric NAT on both sides, the spec leaves only '
            'a media relay with consent from both sides — or, honestly, '
            '"no call".');
  }

  PunchOutcome _cancellation(String reason) {
    log?.call('Punch window (§17.3) without success: $reason');
    return PunchOutcome(
      refusal: reason,
      packetsSent: _packets,
      bytesSent: _bytes,
      roundCarried: -1,
    );
  }

  void _send(InternetAddress address, int port) {
    try {
      _bytes += session.sendTo(
          DFrameKind.punch, Uint8List(0), address, port);
      _packets++;
    } catch (e) {
      // Catches what `send` throws SYNCHRONOUSLY — today exactly one case: an
      // address family that this node has not bound at all
      // (`UdpSocketSet.send`, `StateError`). One candidate must not drag the other
      // destinations of the same round down with it.
      //
      // ── WHAT IT EXPLICITLY DOES NOT CATCH (measured 01.09., S361) ────
      //
      // "No route to this address" does NOT arrive here.
      // `RawDatagramSocket.send` reports that asynchronously on the stream of the
      // socket, the call here returns normally. The error branch
      // for that sits in `UdpSocketSet.open`; the measurement is there. Whoever
      // takes this `catch` for the network problem builds themselves the same
      // fallacy as S351 ("`unawaited()` behind synchronous try/catch").
      log?.call('Punch an ${address.address}:$port misslang: $e');
    }
  }

  /// The destinations of a round: first the named ones, then — from [kPlainRounds] on —
  /// as many predicted ones as fit under [kMaxPunchPacketsPerRound].
  ///
  /// The predicted ones ROTATE over the rounds: round 15 takes the first
  /// n, round 16 the next n, and after the end from the start again. That way
  /// every predicted port gets several attempts, instead of the
  /// first n occupying the whole rest of the window.
  static List<CallCandidate> _targetsForRound(
    int round,
    List<CallCandidate> named,
    List<CallCandidate> predicted,
  ) {
    final out = <CallCandidate>[...named];
    if (round < kPlainRounds || predicted.isEmpty) return out;
    final place = kMaxPunchPacketsPerRound - out.length;
    if (place <= 0) return out;
    final n = place < predicted.length ? place : predicted.length;
    final start = ((round - kPlainRounds) * n) % predicted.length;
    for (var i = 0; i < n; i++) {
      out.add(predicted[(start + i) % predicted.length]);
    }
    return out;
  }
}
