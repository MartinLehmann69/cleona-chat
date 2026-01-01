/// The two limits of §17.2 in a group call, and the ringing limit of the
/// callee (S407-GAMUTE, finding H-1 / B-H1 of `S407-GA-P4.md`).
///
/// §17.2: "Caller state `reaching`, at most 10 s … When the callee's
/// `RING_ACK` arrives, it really is ringing on their end: ringtone and the
/// 60-s answer timeout start then, and only then. When 10 s have passed
/// without a `RING_ACK`, the caller shows "not reachable", ends the call,
/// sends one `HANGUP` … Reaching and answering are two limits in a row — up
/// to 10 s until `RING_ACK`, then up to 60 s until `ANSWER`. Both are limits
/// of the call, counted by the caller on its own clock; the delivery layer
/// holds no clock for them (§9.3)." And: "a `RING_ACK` for a call the caller
/// has already ended is answered with one `HANGUP`. A ringing device stops by
/// itself after 60 s."
///
/// The 1:1 path counts them in `CallManager` (`_startReachingTimeout`,
/// `_startRingingTimeout`, `_answerLateRingAck`). A group call invites
/// several members at once, so the initiator counts the same two limits per
/// invited member: a member not reached or not answering ends its own
/// invitation, not the call — the call ends when no invitation is open any
/// more and nobody joined. The numbers are the 1:1 path's, not a second
/// writing of them.
///
/// No repetition and no other clock here (§11.3a): a call signal is sent
/// once, and the delivery layer repeats it while the call rings.
library;

import 'dart:async';

import 'package:cleona/core/calls/call_manager.dart' show CallManager;

/// One group call's invitation clocks — on the initiator per invited
/// member, on a callee its own ringing.
final class GroupCallRinging {
  GroupCallRinging({
    this.onNotReached,
    this.onNotAnswered,
    this.onRingingOver,
  });

  /// §17.2: 10 s until `RING_ACK` — the 1:1 path's number.
  static const Duration reachingLimit =
      Duration(seconds: CallManager.reachingTimeoutSec);

  /// §17.2: 60 s from `RING_ACK` until `ANSWER`; a ringing device stops by
  /// itself after the same 60 s.
  static const Duration answerLimit =
      Duration(seconds: CallManager.ringingTimeoutSec);

  /// The reaching limit passed: these members sent no `RING_ACK` (may be
  /// empty — then only "is any invitation still open?" is asked).
  final void Function(Set<String> members)? onNotReached;

  /// A member rang for 60 s without an `ANSWER`.
  final void Function(String member)? onNotAnswered;

  /// This device (a callee) rang for 60 s.
  final void Function()? onRingingOver;

  final Set<String> _reaching = {};
  final Map<String, Timer> _answer = {};
  Timer? _reachingTimer;
  Timer? _ringTimer;

  /// Invitations that ended without an answer — not reached, not answered,
  /// or ended by the caller. A `RING_ACK` or `ANSWER` from such a member is
  /// answered with one `HANGUP` ([claimLateReply]).
  final Set<String> _ended = {};
  final Set<String> _lateReplied = {};

  /// Members the missed-call message was started for (§17.2) — once per
  /// member and call, whichever end of its invitation came first.
  final Set<String> _missed = {};

  // ── The initiator ──────────────────────────────────────────────────────

  /// The user started the call: [invited] are being reached from now on.
  void startReaching(Iterable<String> invited) {
    _reaching.addAll(invited);
    _reachingTimer?.cancel();
    _reachingTimer = Timer(reachingLimit, () {
      _reachingTimer = null;
      final gone = {..._reaching};
      _reaching.clear();
      _ended.addAll(gone);
      onNotReached?.call(gone);
    });
  }

  /// [member]'s `RING_ACK`: true if it was being reached — now it rings and
  /// its 60 s run. A further `RING_ACK` (another of its devices) changes
  /// nothing.
  bool ringAck(String member) {
    if (!_reaching.remove(member)) return false;
    _answer[member] = Timer(answerLimit, () {
      _answer.remove(member);
      _ended.add(member);
      onNotAnswered?.call(member);
    });
    return true;
  }

  /// [member] answered or rejected: its invitation is closed.
  void closed(String member) {
    _reaching.remove(member);
    _answer.remove(member)?.cancel();
  }

  /// Is an invitation still being reached or ringing?
  bool get anyOpen => _reaching.isNotEmpty || _answer.isNotEmpty;

  /// The caller ends the call: every open invitation ends with it. Returns
  /// the members that are owed one `HANGUP`.
  Set<String> endAll() {
    final open = {..._reaching, ..._answer.keys};
    _reaching.clear();
    for (final t in _answer.values) {
      t.cancel();
    }
    _answer.clear();
    _reachingTimer?.cancel();
    _reachingTimer = null;
    _ended.addAll(open);
    return open;
  }

  /// Did [member]'s invitation end without an answer?
  bool hasEnded(String member) => _ended.contains(member);

  /// Is [member]'s invitation still being reached or ringing?
  bool isOpen(String member) =>
      _reaching.contains(member) || _answer.containsKey(member);

  /// May the missed-call message for [member] be started now? True once per
  /// member: the 60 s of the initiator and the callee's own `REJECT
  /// "timeout"` end the same invitation, and only one message goes.
  bool claimMissed(String member) => _missed.add(member);

  /// May a late `RING_ACK`/`ANSWER` of [member] with [marker] be answered
  /// with a `HANGUP`? Once per marker; an empty marker cannot be told apart
  /// and is answered each time (as `TerminatedCallLedger`).
  bool claimLateReply(String member, String marker) {
    if (!_ended.contains(member)) return false;
    if (marker.isEmpty) return true;
    return _lateReplied.add('$member|$marker');
  }

  // ── A callee ───────────────────────────────────────────────────────────

  /// This device rings: it stops by itself after [answerLimit].
  void startRinging() {
    _ringTimer?.cancel();
    _ringTimer = Timer(answerLimit, () {
      _ringTimer = null;
      onRingingOver?.call();
    });
  }

  void stopRinging() {
    _ringTimer?.cancel();
    _ringTimer = null;
  }

  /// Stops every clock; what ended stays known for late replies.
  void stopClocks() {
    stopRinging();
    _reachingTimer?.cancel();
    _reachingTimer = null;
    for (final t in _answer.values) {
      t.cancel();
    }
    _answer.clear();
    _reaching.clear();
  }
}
