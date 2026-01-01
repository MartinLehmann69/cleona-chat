/// The measures of the shell — deadlines, caps, and what a key carries
/// with it.
///
/// Its own file because `shell.dart` must not exceed the line budget of 400
/// (mycelium/README.md rule 2) and because the justification
/// of a deadline is longer than its line. Whoever changes a number reads
/// here what it costs.
library;

import 'dart:typed_data';

/// How long flight 2 is waited for before flight 1 is repeated ONCE.
/// No clock: the timer exists only while a handshake is running,
/// and is not set anew after the second attempt (§1.2).
const Duration kAnswerDeadline = Duration(milliseconds: 800);

/// This many attempts, then the neighbour counts as not reachable and the
/// waiting packets drop. A failure is not an error of delivery —
/// the ladder has three further steps (§7.1).
const int kAttempts = 2;

/// Maximum number of waiting packets per neighbour while the handshake runs.
/// Displacing instead of blocking, like the request buffer (§15.4).
const int kWaitingAtMost = 32;

/// Maximum number of held links. Above the neighbour number (§11.8: 32), because
/// the ladder also sends to counterparts that are not neighbours.
const int kLinksAtMost = 64;

/// This long without a RECEIVED packet, then a link counts as expired and
/// the next send builds a new one.
///
/// **Why this must exist.** If the counterpart restarts, it has lost the
/// key while we still hold it. It cannot open our packets
/// and discards them silently — and it cannot tell us:
/// an answer „I do not know that" would be a packet that anyone with a
/// forged sender address could trigger, and thus an
/// amplifier. Without this deadline the route would stay mute forever without
/// either side noticing — the worst kind of error.
///
/// **What it costs, named.** If we send permanently to a neighbour who
/// never sends anything back, a handshake occurs every 120 s: 3600 B per
/// 120 s, i.e. roughly 2.6 MB/day. That is only the case at all when
/// sending happens — there is no timer, the deadline is checked when sending
/// (§1.2: nothing periodic when idle).
///
/// The usual way back is faster than the deadline: a newly started
/// counterpart sends in turn, and its flight 1 REPLACES our link
/// immediately.
const Duration kLinkSilence = Duration(seconds: 120);

/// This many real payloads a link keeps in order to send them once more after a
/// key change.
///
/// **Why this exists.** If the counterpart restarts, the packets that
/// we already sent under the old key are nonsense to it —
/// it discards them. The shell has accepted them ([send] returned `true`) and
/// thereby owes them to the wire; sending them once more under the new key
/// is the same duty that the splitter fulfils with its
/// re-request. COVER is never kept: it carries nothing,
/// and a repeated cover packet would be a pattern.
///
/// The stack empties as soon as something ARRIVES under this key —
/// that is the evidence that the counterpart still has it. In a running
/// conversation it is therefore almost always empty.
///
/// **The price, named: duplicates.** If the counterpart did receive the packets
/// and restarted ONLY AFTERWARDS, we send them a second
/// time. The shell cannot distinguish that, and the layers above
/// discard duplicates anyway (§9.2: "duplicate → ignore"). A duplicate
/// packet is the cheaper error than a lost one.
const int kResendAtMost = 16;

/// After two non-matching packets from someone for whom no
/// key stands, THIS side starts a handshake.
///
/// **Why the recipient must act.** After a restart the other side holds
/// our old key and we none at all. We cannot open its
/// packets, and we cannot tell it that — an answer
/// „I do not know that" could be triggered with a forged sender. So
/// we start ourselves. Two packets in, two packets out: the
/// ratio is 1, so there is no amplification. A SINGLE
/// unknown packet therefore stays unanswered — otherwise it would be 1 to 2.
const Duration kFreshStartLock = Duration(seconds: 10);

/// Maximum number of simultaneously running handshakes that do NOT stem from a
/// send wish. A cap against a sender who wants to force computing work with forged
/// addresses.
const int kFreshStartConcurrent = 8;

class Link {
  final Uint8List sendKey;
  final Uint8List receiveKey;

  /// When a packet last arrived UNDER THIS KEY. Only that
  /// counts: that we have sent says nothing about whether the
  /// counterpart still has the key.
  DateTime heard;

  /// When it was last used — only for the cap.
  DateTime last;

  /// What went out since the last sign of life, for the case that the
  /// counterpart no longer has the key ([kResendAtMost]).
  final List<Uint8List> resend = [];

  Link(this.sendKey, this.receiveKey, this.heard)
      : last = heard;
}

