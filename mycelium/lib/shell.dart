/// The shell — the pairwise wrapping around EVERY packet on the data port.
///
/// ── WHAT FOR ─────────────────────────────────────────────────────────────────
///
/// V4.2 §4.2: link confidentiality is „not an exception to sealing, but an
/// additional shell underneath it". §5.5 rule 3 turns this into a duty
/// that can be measured: every cover packet is sealed pairwise, filled
/// or empty. Measured (S388 D2), neither was the case — the cover packet
/// was a naked zero buffer, and real traffic carried kind byte and
/// splitter header openly. An observer needed no key to separate filling
/// from traffic.
///
/// The shell lies between [Wire] and `split.dart` and makes both
/// indistinguishable: **1200 B, always, without a single plaintext byte.**
/// Cover is a shell with cover payload (§5.5); a part packet is a
/// shell with 1 to 1170 B inside. From outside they are the same.
///
/// ```
/// data packet, 1200 B:
///   nonce  12 B ‖ AEAD_{k_direction}( length u16 2 B ‖ payload ‖ zeros ) 1188 B
/// ```
///
/// The filling INSIDE the seal may be zero — it lies behind the
/// encryption and from outside is nothing but ciphertext. The filling
/// in the handshake may not, because that lies open (`shell_start.dart`).
///
/// ── WHAT THIS COSTS, named ──────────────────────────────────────────────
///
/// * **One handshake per neighbour**, 2400 B out and 1200 B back, and one
///   round-trip time before the first packet goes out to a new neighbour.
///   Waiting packets lie here meanwhile; the ladder notices nothing of it,
///   because it starts its four steps simultaneously anyway (§3.4).
/// * **30 B per packet** (12 nonce + 16 authenticator + 2 length). `kMaxPaket`
///   in `split.dart` therefore drops from 1200 to 1170 — on the wire
///   it stays at 1200.
/// * **No key change during the run.** A link lives until the process
///   ends or the cap displaces it. That is a limit, not a
///   design: §14.5 (rotation) concerns identities, not this wrapping.
/// * **No protection against replay** at this level. An
///   intercepted packet can be delivered again; the layers
///   above already discard duplicates (receipt, part number, §9.2).
///
/// ── WHAT THE SHELL IS NOT ─────────────────────────────────────────────
///
/// No determination of WHO the neighbour is. The handshake is anonymous
/// (`shell_start.dart`); who the counterpart is, is decided by the envelope
/// one level higher and by nobody else.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/link/link_kdf.dart';

import 'package:mycelium/wire.dart';
import 'package:mycelium/shell_start.dart';
import 'package:mycelium/shell_link.dart';

class Shell implements PacketRoute {
  final PacketRoute _bottom;
  final void Function(String) _report;

  /// Deadline from [kLinkSilence]. To be set differently only for probes — waiting
  /// 120 s would not be a smoke but a coffee break.
  final Duration silence;

  final Map<String, Link> _links = {};
  final Map<String, Start> _running = {};
  final Map<String, List<Uint8List>> _waiting = {};
  final Map<String, List<Uint8List>> _unclear = {};
  final Map<String, (Uint8List, Uint8List)> _answered = {};
  final Map<String, DateTime> _freshStartLast = {};
  final Map<String, Timer> _deadlines = {};
  final Map<String, int> _attempt = {};

  /// Running handshakes started WITHOUT repetition (cover, fresh start).
  /// Until S397 they had no deadline at all: one lost packet left the entry
  /// forever, and [_start] returned early for every later real send — those
  /// packets waited silently, with no deadline and no report (S397-2).
  final Set<String> _oneShot = {};

  void Function(Uint8List packet, InternetAddress from, int fromPort)? _further;
  bool _to = false;

  /// Counters for probes and the network statistics (§25) — read only.
  int handshakesStarted = 0;
  int handshakesDone = 0;
  int dropped = 0;

  Shell(this._bottom,
      {void Function(String)? report, this.silence = kLinkSilence})
      : _report = report ?? ((String s) => stderr.writeln(s)) {
    _bottom.listen(_onPacket);
  }

  /// Whether a key already stands towards [target]:[targetPort].
  bool stands(InternetAddress target, int targetPort) =>
      _links.containsKey(_who(target, targetPort));

  @override
  bool send(Uint8List payload, InternetAddress target, int targetPort) =>
      _send(payload, target, targetPort, cover: false);

  /// The path of the cover stream (§5.1: own buffer, no path to delivery).
  ///
  /// Since W4 every cover payload carries 1170 B and can no longer be
  /// distinguished from traffic by the shell. Via [send] it occupied the
  /// resend buffer (real packets found no more room) and displaced
  /// in the handshake queue the oldest waiting — real —
  /// packet (S391, E3). Cover is therefore never kept here and never
  /// waits: without a key it triggers the handshake (otherwise the
  /// open set would never get one) and is itself lost.
  bool sendCover(Uint8List payload, InternetAddress target, int targetPort) =>
      _send(payload, target, targetPort, cover: true);

  bool _send(Uint8List payload, InternetAddress target, int targetPort,
      {required bool cover}) {
    if (_to) return false;
    if (payload.length > kPayloadAtMost) {
      _report('Shell: ${payload.length} B do not fit into a shell '
          '(at most $kPayloadAtMost) — not sent');
      return false;
    }
    final w = _who(target, targetPort);
    final l = _links[w];
    if (l != null) {
      final now = DateTime.now();
      if (now.difference(l.heard) <= silence) {
        l.last = now;
        // Cover is never kept — it carries nothing on which anything
        // waits, and a repeated cover packet would be a pattern on the
        // wire. Empty payload likewise (probes, edge cases).
        if (!cover &&
            payload.isNotEmpty &&
            l.resend.length < kResendAtMost) {
          l.resend.add(Uint8List.fromList(payload));
        }
        return _bottom.send(
            pack(payload, l.sendKey), target, targetPort);
      }
      // Expired: see [kLinkSilence]. First gone, then new — otherwise
      // the branch below takes the old key again.
      _links.remove(w);
      _answered.remove(w);
      _report('Shell: key to $w has been unconfirmed for ${silence.inSeconds} s '
          '— new handshake');
    }
    if (cover) {
      // One attempt, no deadline: nothing waits for a cover packet.
      _start(w, target, targetPort, withRetry: false);
      return false;
    }
    final q = _waiting.putIfAbsent(w, () => []);
    if (q.length >= kWaitingAtMost) {
      q.removeAt(0);
      dropped++;
    }
    q.add(Uint8List.fromList(payload));
    _start(w, target, targetPort);
    return true;
  }

  @override
  void listen(
      void Function(Uint8List packet, InternetAddress from, int fromPort) onPacket) {
    _further = onPacket;
  }

  /// Ends the own timers; the [Wire] stays with the caller.
  void close() {
    _to = true;
    for (final t in _deadlines.values) {
      t.cancel();
    }
    _deadlines.clear();
    _running.clear();
    _oneShot.clear();
    _waiting.clear();
    _unclear.clear();
  }

  // ── Sending ─────────────────────────────────────────────────────────────

  /// [withRetry] `false` means: ONE attempt, no deadline.
  ///
  /// This is how the recipient starts ([_freshStart]). A repetition would there
  /// be 4 packets for 2 — an amplification of 2, and exactly that is what the
  /// procedure is not supposed to have. Besides, nothing waits for it: if no
  /// answer comes, the counterpart keeps sending, and after [kFreshStartLock]
  /// it may be tried once more.
  ///
  /// A one-shot start still gets ONE deadline, after which it is simply
  /// forgotten (no repetition — the ratio stays 1). A real send wish that
  /// meets a running one-shot start turns it into an ordinary one with
  /// repetition and report, instead of silently waiting behind it.
  void _start(String w, InternetAddress target, int targetPort,
      {bool withRetry = true}) {
    if (_running.containsKey(w)) {
      if (withRetry && _oneShot.remove(w)) {
        _attempt[w] = 1;
        _deadline(w, target, targetPort);
      }
      return;
    }
    final b = beginShellHandshake();
    _running[w] = b;
    _attempt[w] = 1;
    handshakesStarted++;
    _flight1(b, target, targetPort);
    if (withRetry) {
      _deadline(w, target, targetPort);
      return;
    }
    _oneShot.add(w);
    _deadlines[w]?.cancel();
    _deadlines[w] = Timer(kAnswerDeadline * kAttempts, () {
      _deadlines.remove(w);
      if (!_oneShot.remove(w)) return; // answered or upgraded
      _running.remove(w);
      _attempt.remove(w);
    });
  }

  void _flight1(Start b, InternetAddress target, int targetPort) {
    _bottom.send(b.partA, target, targetPort);
    _bottom.send(b.partB, target, targetPort);
  }

  void _deadline(String w, InternetAddress target, int targetPort) {
    _deadlines[w]?.cancel();
    _deadlines[w] = Timer(kAnswerDeadline, () {
      _deadlines.remove(w);
      final b = _running[w];
      if (b == null) return; // done or given up
      final n = (_attempt[w] ?? 1) + 1;
      if (n > kAttempts) {
        _running.remove(w);
        _attempt.remove(w);
        final q = _waiting.remove(w);
        dropped += q?.length ?? 0;
        _report('Shell: $w does not answer — ${q?.length ?? 0} packet(s) '
            'dropped; other steps of the ladder keep running');
        return;
      }
      _attempt[w] = n;
      _flight1(b, target, targetPort);
      _deadline(w, target, targetPort);
    });
  }

  // ── Receiving ───────────────────────────────────────────────────────────

  void _onPacket(Uint8List p, InternetAddress from, int fromPort) {
    // On the data port lies NOTHING other than a shell. Whatever has a
    // different length is not an old format — mycelium has not been
    // shipped —, but foreign traffic.
    if (p.length != kShellSize) return;
    final w = _who(from, fromPort);
    final l = _links[w];
    if (l != null) {
      final content = unpack(p, l.receiveKey);
      if (content != null) {
        l.heard = DateTime.now();
        l.last = l.heard;
        // Sign of life: the counterpart still has the key.
        l.resend.clear();
        // Empty = cover. It does not go upwards; §5.1 „no code path
        // connects it to the send path".
        if (content.isNotEmpty) _further?.call(content, from, fromPort);
        return;
      }
    }
    final b = _running[w];
    if (b != null) {
      final k = complete(b, p);
      if (k != null) {
        _running.remove(w);
        _oneShot.remove(w);
        _attempt.remove(w);
        _deadlines.remove(w)?.cancel();
        _setUp(w, k, caller: true, target: from, targetPort: fromPort);
        return;
      }
    }
    _assemble(w, p, from, fromPort);
  }

  /// A packet that was neither a data packet nor an expected answer: it can
  /// be part A or part B of a foreign flight 1. Which of the two
  /// is decided only by the counterpart piece — therefore collecting and not
  /// guessing (`ordnen` in `shell_start.dart`).
  void _assemble(String w, Uint8List p, InternetAddress from, int fromPort) {
    final open = _unclear.putIfAbsent(w, () => []);
    for (final old in open) {
      final pair = sort(old, p);
      if (pair == null) continue;
      open.clear();
      _unclear.remove(w);
      _answer(w, pair.$1, pair.$2, from, fromPort);
      return;
    }
    if (open.isNotEmpty) {
      // Two packets that do not fit together, from someone without
      // key: either nonsense, or a counterpart that still knows us
      // while we no longer know it. We cannot distinguish that,
      // so we answer with exactly as many packets as came in
      // ([kFreshStartLock]).
      open.clear();
      _unclear.remove(w);
      _freshStart(w, from, fromPort);
      return;
    }
    open.add(p);
  }

  void _freshStart(String w, InternetAddress from, int fromPort) {
    if (_running.containsKey(w) || _links.containsKey(w)) return;
    if (_running.length >= kFreshStartConcurrent) return;
    final now = DateTime.now();
    _freshStartLast
        .removeWhere((_, t) => now.difference(t) > kFreshStartLock);
    if (_freshStartLast.containsKey(w)) return;
    _freshStartLast[w] = now;
    _start(w, from, fromPort, withRetry: false);
  }

  void _answer(String w, Uint8List partA, Uint8List partB,
      InternetAddress from, int fromPort) {
    final uniformA = Uint8List.sublistView(partA, 0, kUniform);

    // Tie: both started at the same time. The decision is made by the
    // smaller Elligator share, and in the same way on BOTH sides — otherwise
    // both set up a link and neither matches the other.
    final own = _running[w];
    if (own != null && smaller(own.uniform, uniformA)) return;

    // Repetition of the same flight 1 (flight 2 got lost): the same
    // answer once more. A NEW key would be the error — the
    // counterpart could already have set up the old one.
    final old = _answered[w];
    if (old != null && equal(old.$1, uniformA)) {
      _bottom.send(old.$2, from, fromPort);
      return;
    }

    final a = answerShellHandshake(partA, partB);
    if (a == null) return;
    _running.remove(w);
    _oneShot.remove(w);
    _attempt.remove(w);
    _deadlines.remove(w)?.cancel();
    _answered[w] = (a.uniformCaller, a.packet);
    _bottom.send(a.packet, from, fromPort);
    _setUp(w, a.key, caller: false, target: from, targetPort: fromPort);
  }

  void _setUp(String w, Uint8List linkKey,
      {required bool caller,
      required InternetAddress target,
      required int targetPort}) {
    // The caller sends under `cell/init` and listens on `cell/resp`, the
    // callee the other way round: two directions never share a
    // nonce space (`link_kdf.dart`).
    final init = LinkKdf.deriveCellKeyInit(linkKey);
    final resp = LinkKdf.deriveCellKeyResp(linkKey);
    // What went out under the PREVIOUS key the counterpart
    // could not read — otherwise it would not have needed a new one.
    final toResend = _links[w]?.resend;
    _links[w] = Link(caller ? init : resp, caller ? resp : init,
        DateTime.now());
    handshakesDone++;
    _cap();
    final q = _waiting.remove(w);
    for (final n in toResend ?? const <Uint8List>[]) {
      send(n, target, targetPort);
    }
    if (q == null) return;
    for (final n in q) {
      send(n, target, targetPort);
    }
  }

  void _cap() {
    while (_links.length > kLinksAtMost) {
      var oldest = _links.keys.first;
      for (final e in _links.entries) {
        if (e.value.last.isBefore(_links[oldest]!.last)) {
          oldest = e.key;
        }
      }
      _links.remove(oldest);
      _answered.remove(oldest);
    }
  }

  static String _who(InternetAddress a, int port) => '${a.address}:$port';
}
