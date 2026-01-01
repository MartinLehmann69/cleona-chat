/// The measures of the shell — deadlines, caps, and what a key carries
/// with it.
///
/// Its own file because `shell.dart` must not exceed the line budget of 400
/// (mycelium/README.md rule 2) and because the justification
/// of a deadline is longer than its line. Whoever changes a number reads
/// here what it costs.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/shell_start.dart' show Start;
import 'package:mycelium/wire.dart' show PacketRoute;

/// How long flight 2 is waited for before flight 1 is repeated ONCE.
/// No clock: the timer exists only while a handshake is running,
/// and is not set anew after the second attempt (§1.2).
const Duration kAnswerDeadline = Duration(milliseconds: 800);

/// This many attempts, then the neighbour counts as not reachable and the
/// waiting packets drop. A failure is not an error of delivery —
/// the ladder has three further steps (§7.1).
const int kAttempts = 2;

/// How a handshake the shell held packets for ended (§20.2 "packets waiting
/// for a link"): [unreachable] `false` — it completed and they left;
/// `true` — the neighbour did not answer and all of them dropped.
///
/// There is no count bound on the waiting packets and nothing is displaced
/// (D-41 as amended, S399 step 2): the bound is what the flow of §11.3 lets
/// through — at most one transmission of two or more parts per hop, plus
/// single parts —, and only while the handshake runs, two answer deadlines
/// at most. Until S399 a queue of 32 displaced the rest of a large
/// transmission (measured: 335 of 367 parts, `smoke_burst_loss`).
typedef HopEnd = void Function(InternetAddress target, int targetPort, bool unreachable);

/// A handshake towards [target]:[targetPort] got no answer — with waiting
/// packets after its repetitions, or a one-shot start (cover, fresh start)
/// after its deadline. Each is a request without an answer, i.e. a failed
/// use of the address (V4.2 §11.8 "two uses failed"); until S405 the one-shot
/// case was forgotten silently, and a dead neighbour stayed in the open set
/// for good — two handshake packets per cover draw towards it (S404-7) and
/// the first hop of step 3 (S404-6).
typedef Silent = void Function(InternetAddress target, int targetPort);

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
/// **What it no longer does (S398, OP-29, V4.2 §11.6).** Until S398 every
/// packet — cover and keep-alive included — checked the deadline, so a
/// neighbour that never sends anything back cost a handshake every
/// ≈ 130 s even in idle (≈ 2.3 MB/day, in no budget). Cover and
/// keep-alive now go out under the existing key and never renew
/// (F29-A); a restarted counterpart notices them itself (two unreadable
/// packets, [kFreshStartLock]). There is no timer: the deadline is
/// checked when sending real traffic (§1.2).
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

/// What the shell keeps of the packets from ONE address that it could
/// neither open nor take as the answer to its own handshake (S401).
///
/// [last] is the most recent one — the half a foreign flight 1 may still
/// complete. It is ALWAYS the most recent: until S401 a kept packet that
/// did not fit the next one took that next one down with it. A single
/// leftover — a late packet under a key this side no longer holds — then met
/// part A of the counterpart's next flight 1, both were dropped, part B
/// stayed alone, and the handshake of a restarted counterpart was lost
/// together with everything it still owed (measured on lane 3: a holder
/// restarted, and a recipient that had kept one such packet since its own
/// restart never reached it again; `test/smoke_shell_stray_packet.dart`).
///
/// [first] counts for [kFreshStartLock]: `true` while ONE packet that fitted
/// nothing waits for a second. Every second one starts — the ratio stays 1.
class Unclear {
  Uint8List? last;
  bool first = false;
}

/// For this many sender addresses the shell keeps an [Unclear] — one packet
/// of 1200 B each, 76 800 B in all (V4.2 §20.2: every buffer has a declared
/// limit and a declared behaviour when it is reached).
///
/// **Why this must exist.** Until S403 an entry left only when its packet
/// found its counterpart piece; every other address that ever sent one
/// packet of shell size kept 1200 B until the shell closed. Anyone can send
/// such packets, under any sender address.
///
/// **Why this number.** An entry is the first step towards a link with that
/// address: half of its flight 1, or the first of the two unreadable packets
/// after which this side starts itself ([kFreshStartLock]). The shell holds
/// at most [kLinksAtMost] links — a restart loses at most that many keys,
/// and more first steps than links it can hold serve nobody.
///
/// **How long an entry is needed.** The two parts of a flight 1 leave in
/// one call, so the second arrives right behind the first; if one is lost,
/// the counterpart sends BOTH again after [kAnswerDeadline]. A kept packet
/// older than that completes nothing any more.
///
/// **At the bound** the address whose packet was kept longest ago goes
/// ([unclearFor]) — evicting, not refusing (§20.2): a full store that took
/// nothing new would let one burst of forged addresses stop every later
/// handshake. The price, named: a half pushed out between the two parts of
/// its flight 1 costs that attempt, which the counterpart repeats; that
/// takes [kUnclearAtMost] packets from other addresses between two packets
/// that left together.
const int kUnclearAtMost = kLinksAtMost;

/// The entry of [w] in [unclear], made the most recent one; the least
/// recently touched entries beyond [kUnclearAtMost] go. Here and not in
/// `shell.dart` for the line budget (mycelium/README.md rule 2).
Unclear unclearFor(Map<String, Unclear> unclear, String w) {
  final u = unclear.remove(w) ?? Unclear();
  unclear[w] = u; // a map keeps insertion order: the first key is the oldest
  while (unclear.length > kUnclearAtMost) {
    unclear.remove(unclear.keys.first);
  }
  return u;
}

/// Silence of the counterpart after which the first real single-packet
/// sending gets ONE empty sealed packet behind it (F28-1, S398; V4.2
/// §11.6, budget line in §5.6).
///
/// **Why.** A restarted counterpart answers only two unreadable packets
/// ([kFreshStartLock]); a single one — a bundle request, a board question,
/// a small post box packet — stays unanswered and is lost (W-a, S398: 3 of
/// 7 runs). With the companion it holds two and starts itself. A healthy
/// counterpart opens it as an empty packet, i.e. as cover (§5.1).
///
/// **What it costs, named.** +1 packet (1200 B) per single-packet sending
/// to a counterpart silent for more than 2 s, at most once until it is
/// heard again ([Link.companionSpent]); nothing behind a multi-packet
/// sending (two or more real packets in one event-loop turn already make
/// two), nothing in idle, no clock — `Timer.run` only ends the turn.
const Duration kCompanionAfter = Duration(seconds: 2);

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

  /// When a REAL packet last went out under this key — the own sending
  /// pause of [renewDue]. Cover and keep-alive do not count (S406 V-1):
  /// own sending says nothing about whether the counterpart lives.
  DateTime lastReal;

  /// What went out since the last sign of life, for the case that the
  /// counterpart no longer has the key ([kResendAtMost]).
  final List<Uint8List> resend = [];

  /// The companion of the current silence is used up (sent, or not needed
  /// because a second real packet followed). Reset when a packet is heard.
  bool companionSpent = false;

  /// A companion waits for the end of this event-loop turn.
  bool companionPending = false;

  Link(this.sendKey, this.receiveKey, this.heard)
      : last = heard,
        lastReal = heard;
}

/// Called for every real, non-empty packet sent on [l] ([kCompanionAfter]).
/// A second real packet in the same turn cancels a waiting companion;
/// otherwise [sendEmpty] runs once the turn is over.
void companion(Link l, DateTime now, void Function() sendEmpty) {
  if (l.companionPending) {
    l.companionPending = false;
    return;
  }
  if (l.companionSpent || now.difference(l.heard) <= kCompanionAfter) return;
  l.companionSpent = l.companionPending = true;
  Timer.run(() {
    if (!l.companionPending) return;
    l.companionPending = false;
    sendEmpty();
  });
}

/// Whether a REAL send on [l] must renew the link first (F29-B, S398;
/// V4.2 §11.6: „there is no renewal on silence while real sending
/// continues").
///
/// Only when both hold: nothing heard under the key for [silence], AND an
/// own REAL sending pause longer than [kFreshStartLock]. In a running stream
/// a renewal only held packets back for a round trip and resent up to
/// [kResendAtMost] duplicates (measured .201, S398: every 120.03 s during
/// a 25-MB transfer); a counterpart that restarted meanwhile notices the
/// stream itself — two unreadable packets, and it starts ([kFreshStartLock]).
///
/// Whether the counterpart lives is judged only by what arrives from it
/// ([Link.heard], its cover included). Own cover and keep-alive to it do
/// not count as sending here ([Link.lastReal], S406 V-1; owner 07.10.2026):
/// until S406 they kept the pause short, so a real packet to a dead
/// counterpart that still got cover went out under the dead key — no
/// handshake, no `Shell.onSilent`, and step 3 never handed on (field case
/// 1d.07, `berichte/S406-RCA-E2E4.md` finding 2). They still never renew.
bool renewDue(Link l, DateTime now, Duration silence) =>
    now.difference(l.heard) > silence &&
    now.difference(l.lastReal) > kFreshStartLock;

/// Keeps [links] at [kLinksAtMost]: the least recently used link goes,
/// and [gone] is told its key. Here and not in `shell.dart` for the line
/// budget (mycelium/README.md rule 2).
void capLinks(Map<String, Link> links, void Function(String) gone) {
  while (links.length > kLinksAtMost) {
    var oldest = links.keys.first;
    for (final e in links.entries) {
      if (e.value.last.isBefore(links[oldest]!.last)) oldest = e.key;
    }
    links.remove(oldest);
    gone(oldest);
  }
}

/// The key of a peer in the shell's maps. Out of `shell.dart` for the line
/// budget when the layer diagnosis came in (S405, proposal D) — unchanged.
String shellWho(InternetAddress a, int port) => '${a.address}:$port';

/// Flight 1 of a handshake: part A and part B to [target] (`shell.dart`
/// `_start`, `_deadline`). Moved out of `shell.dart` unchanged (S405).
void flight1(PacketRoute bottom, Start b, InternetAddress target, int targetPort) {
  bottom.send(b.partA, target, targetPort);
  bottom.send(b.partB, target, targetPort);
}
