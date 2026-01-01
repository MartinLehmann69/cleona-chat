/// The loss report of the control plane (§17.1.1, D-69, D-75; S407-GALOSS).
///
/// ══ WHAT THE NORM SAYS ═══════════════════════════════════════════════
///
/// §17.1.1: "… and loss reports — a receiver tells the participant it
/// receives from how many frames of a second went missing, sent only in a
/// second with loss, and a broker that loses frames to several receivers
/// has shown its limit (§17.7)." D-69: "A relay at its upload limit keeps
/// voice and drops video for that pair". §17.5: the video rate "follows the
/// measured available bandwidth and is tracked throughout the call".
///
/// ══ THE ESTABLISHED PROCEDURE THIS FOLLOWS ═════════════════════════════
///
/// RTCP's receiver report, RFC 3550 §6.4.1 and Appendix A.3: the receiver
/// counts, per interval, the frames it EXPECTED (the rise of the highest
/// sequence number seen) against the frames it RECEIVED; the difference is
/// the loss of that interval. The sequence numbers are already on every
/// D-frame (`kind ‖ seq ‖ len`, §17.1; one counter per session over every
/// frame kind, `DSession.sendTo`). The round trip comes the same way RTCP
/// computes it (§6.4.1, "A − LSR − DLSR"): the report names the highest
/// sequence number seen and how long ago it arrived; the sender knows when it
/// sent that frame.
///
/// Two departures, both forced by Cleona's own rules:
///
/// 1. **Only in a second with loss** (§17.1.1, working rule 5) — RTCP sends
///    its reports periodically. Here no report means no loss.
/// 2. **No report about a probing second.** A punch window (§17.3) and a
///    migration burst (§17.4) send probes to every candidate of the other
///    side under the session's ONE counter; those to the wrong candidates
///    never arrive and would read as loss. A probe or path-validation frame
///    therefore silences the interval it arrives in and the next one, and a
///    network change of the receiver itself silences
///    [LossCounter.quietAfterNetworkChange] intervals.
///
/// ══ WHAT THE SENDER DOES WITH IT ══════════════════════════════════════
///
/// - The 1:1 video rate: the loss and the round trip go into
///   `BandwidthEstimator` (§17.5), whose cascade then works.
/// - The line's limit ([LineLimitJudge]): loss above 10 % (the threshold of
///   the loss-based controller of Google Congestion Control,
///   draft-ietf-rmcat-gcc-02 §6) reported by two different receivers within
///   [LineLimitJudge.window] — or by the only one there is — is this line's
///   limit and not one receiver's downlink. That feeds
///   `UploadProbe.recordCongestion` and the broker's limit edge (§17.7).
library;

import 'dart:typed_data';

import 'package:cleona/core/calls/call_control_frame.dart';

// ── The record ─────────────────────────────────────────────────────────

/// A read [ControlRecordType.lossReport].
///
/// Form: `highest(2) ‖ expected(2) ‖ lost(2) ‖ delay(2)`, big endian — 8 B
/// of value, 10 B with the record header. Two-byte counts, because one
/// second of video in the 1200-B class is up to ~320 frames, beyond a byte.
final class LossReport {
  const LossReport({
    required this.highestSeq16,
    required this.expected,
    required this.lost,
    required this.delayMs,
  });

  /// The low 16 bits of the highest sequence number the receiver had seen
  /// when the interval closed.
  final int highestSeq16;

  /// Frames the interval should have carried (RFC 3550 A.3
  /// `expected_interval`).
  final int expected;

  /// Frames missing of them (`expected_interval − received_interval`, never
  /// negative).
  final int lost;

  /// Milliseconds between the arrival of [highestSeq16] and the report
  /// leaving (RFC 3550 "DLSR"); saturates at 0xFFFF.
  final int delayMs;

  /// The fraction lost, 0..1.
  double get fraction => expected <= 0 ? 0 : lost / expected;

  @override
  String toString() => 'LossReport($lost/$expected lost, highest '
      '$highestSeq16, delay $delayMs ms)';
}

/// The value length of a loss report.
const int kLossReportValueLength = 8;

int _u16(int v) => v < 0 ? 0 : (v > 0xFFFF ? 0xFFFF : v);

ControlRecord buildLossReport(LossReport r) {
  final v = Uint8List(kLossReportValueLength);
  final view = ByteData.sublistView(v);
  view.setUint16(0, r.highestSeq16 & 0xFFFF);
  view.setUint16(2, _u16(r.expected));
  view.setUint16(4, _u16(r.lost));
  view.setUint16(6, _u16(r.delayMs));
  return ControlRecord(ControlRecordType.lossReport, v);
}

/// `null` if the record is not a well-formed loss report — a record of
/// another length is not half a report.
LossReport? readLossReport(ControlRecord record) {
  if (record.type != ControlRecordType.lossReport) return null;
  final v = record.value;
  if (v.length != kLossReportValueLength) return null;
  final view = ByteData.sublistView(v);
  final expected = view.getUint16(2);
  final lost = view.getUint16(4);
  if (lost > expected) return null;
  return LossReport(
    highestSeq16: view.getUint16(0),
    expected: expected,
    lost: lost,
    delayMs: view.getUint16(6),
  );
}

// ── The receiver: RFC 3550 A.3 per incoming session ─────────────────────

/// One closed interval with loss, waiting for the next control tick.
final class LossInterval {
  LossInterval({
    required this.expected,
    required this.lost,
    required this.highestSeq,
    required this.highestAtUs,
  });

  int expected;
  int lost;
  int highestSeq;

  /// When [highestSeq] arrived, on the transport's monotonic clock.
  int highestAtUs;

  /// A later interval joins one that has not left yet (the tick and the
  /// interval are not aligned): the counts add, the newest highest wins.
  void absorb(LossInterval later) {
    expected += later.expected;
    lost += later.lost;
    highestSeq = later.highestSeq;
    highestAtUs = later.highestAtUs;
  }

  /// The record, with the delay measured NOW — when it leaves (RFC 3550:
  /// DLSR is the time "between receiving the last SR packet … and sending
  /// this reception report block").
  ControlRecord toRecord(int nowUs) => buildLossReport(LossReport(
        highestSeq16: highestSeq & 0xFFFF,
        expected: expected,
        lost: lost,
        delayMs: (nowUs - highestAtUs) ~/ 1000,
      ));
}

/// Counts what arrives on ONE session (RFC 3550 Appendix A.3).
///
/// No timer: an interval closes when the first frame after its end arrives.
/// A session on which nothing arrives reports nothing — the 10-s loss rule
/// of §17.4 is the answer to that, not a report.
class LossCounter {
  LossCounter({this.intervalUs = 1000000});

  /// One second (§17.1.1: "how many frames of a second went missing").
  final int intervalUs;

  /// Intervals silenced after the RECEIVER's own network change: the
  /// migration burst of §17.4 runs up to three rounds a second apart, and
  /// until the other side's path validation swings, its frames go to the old
  /// address — loss this line did not cause.
  static const int quietAfterNetworkChange = 4;

  bool _started = false;
  int _maxSeq = 0;
  int _maxAtUs = 0;
  int _baseMax = 0;
  int _received = 0;
  int _intervalStartUs = 0;
  int _quiet = 0;

  /// Closed intervals with loss so far — the count a smoke reads.
  int reported = 0;

  /// A frame of [seq] arrived at [nowUs]. [probing] = punch or path
  /// validation. Returns the interval that closed with loss, if one did.
  LossInterval? onFrame(int seq, {required bool probing, required int nowUs}) {
    if (!_started) {
      _started = true;
      _baseMax = seq - 1;
      _maxSeq = seq;
      _maxAtUs = nowUs;
      _received = 1;
      _intervalStartUs = nowUs;
      if (probing) _quiet = _quiet < 2 ? 2 : _quiet;
      return null;
    }
    LossInterval? closed;
    if (nowUs - _intervalStartUs >= intervalUs) {
      closed = _close(nowUs);
    }
    if (probing) _quiet = _quiet < 2 ? 2 : _quiet;
    _received++;
    if (seq > _maxSeq) {
      _maxSeq = seq;
      _maxAtUs = nowUs;
    }
    return closed;
  }

  /// The own network changed: the coming intervals say nothing about the
  /// sender's line.
  void quiet(int intervals) {
    if (intervals > _quiet) _quiet = intervals;
  }

  LossInterval? _close(int nowUs) {
    final expected = _maxSeq - _baseMax;
    // A frame of an earlier interval arriving late counts as received here
    // and can make this negative; RFC 3550 A.3 clamps it the same way.
    final lost = expected - _received;
    _baseMax = _maxSeq;
    _received = 0;
    _intervalStartUs = nowUs;
    if (_quiet > 0) {
      _quiet--;
      return null;
    }
    if (lost <= 0 || expected <= 0) return null;
    reported++;
    return LossInterval(
      expected: expected,
      lost: lost,
      highestSeq: _maxSeq,
      highestAtUs: _maxAtUs,
    );
  }
}

// ── The sender: when its frames left ────────────────────────────────────

/// When the own frames of one session left — for the round trip of RFC 3550
/// §6.4.1. A ring: the report names a frame of the last second or two, and
/// 2048 entries cover over six seconds at the ~320 frames/s of full video.
class SendTimes {
  static const int _size = 2048;
  final Int64List _seq = Int64List(_size)..fillRange(0, _size, -1);
  final Int64List _at = Int64List(_size);

  void record(int seq, int nowUs) {
    final i = seq & (_size - 1);
    _seq[i] = seq;
    _at[i] = nowUs;
  }

  /// The send time of the frame whose low 16 bits are [seq16], the newest
  /// such below [nextSeq]; `null` if it is no longer (or never was) here —
  /// a probe, for instance, is not recorded.
  int? sentAt(int seq16, int nextSeq) {
    var full = (nextSeq & ~0xFFFF) | (seq16 & 0xFFFF);
    if (full >= nextSeq) full -= 0x10000;
    if (full < 0) return null;
    final i = full & (_size - 1);
    return _seq[i] == full ? _at[i] : null;
  }
}

/// What a report means to the sender of the frames it is about.
final class LossFeedback {
  const LossFeedback({
    required this.expected,
    required this.lost,
    required this.rttMs,
  });
  final int expected;
  final int lost;

  /// The round trip from this report, or `null` when the frame it names is
  /// not known here.
  final int? rttMs;

  double get fraction => expected <= 0 ? 0 : lost / expected;

  @override
  String toString() =>
      'LossFeedback($lost/$expected lost, rtt ${rttMs ?? "—"} ms)';
}

/// Round trip after RFC 3550 §6.4.1: arrival of the report, minus the send
/// time of the frame it names, minus the receiver's delay. `null` when the
/// frame is unknown or the result is negative (clock step).
int? roundTripMs(LossReport r, SendTimes times, int nextSeq, int nowUs) {
  final sent = times.sentAt(r.highestSeq16, nextSeq);
  if (sent == null) return null;
  final us = nowUs - sent - r.delayMs * 1000;
  return us < 0 ? null : us ~/ 1000;
}

// ── The line's limit ────────────────────────────────────────────────────

/// Decides when reports show THIS line's limit, not one receiver's downlink
/// (§17.1.1: "a broker that loses frames to several receivers has shown its
/// limit").
class LineLimitJudge {
  /// Loss above this is congestion — the decrease threshold of the
  /// loss-based controller of Google Congestion Control
  /// (draft-ietf-rmcat-gcc-02 §6: "if more than 10% of the packets have been
  /// lost"). Below it, random loss of a radio link does not mark a limit.
  static const double congestedFraction = 0.10;

  /// Reports about the same second of sending reach the sender up to two
  /// control ticks apart: each receiver closes its interval and sends with
  /// its own tick, neither aligned with the other's.
  static const int windowUs = 2000000;

  final Map<String, ({int atUs, double fraction})> _notes = {};

  /// A report from [peerHex]. Returns the loss fraction to record as the
  /// line's limit, or `null`. [receivers] = the sessions this node sends on.
  double? onReport({
    required String peerHex,
    required double fraction,
    required int nowUs,
    required int receivers,
  }) {
    if (fraction <= congestedFraction) return null;
    _notes[peerHex] = (atUs: nowUs, fraction: fraction);
    _notes.removeWhere((_, n) => nowUs - n.atUs > windowUs);
    final need = receivers >= 2 ? 2 : 1;
    if (_notes.length < need) return null;
    var worst = 0.0;
    for (final n in _notes.values) {
      if (n.fraction > worst) worst = n.fraction;
    }
    _notes.clear();
    return worst;
  }

  void forget(String peerHex) => _notes.remove(peerHex);
  void clear() => _notes.clear();
}
