/// The shell — the pairwise wrapping around EVERY packet on the data port.
///
/// WHAT FOR: V4.2 §4.2 (link confidentiality "an additional shell underneath"
/// sealing); §5.5 rule 3 (every cover packet sealed pairwise, filled or
/// empty). Between [Wire] and `split.dart`: **1200 B, always, without a
/// single plaintext byte** — cover and a part of 1 to 1170 B look the same.
///
/// ```
/// data packet, 1200 B:
///   nonce  12 B ‖ AEAD_{k_direction}( length u16 2 B ‖ payload ‖ zeros ) 1188 B
/// ```
///
/// Filling inside the seal may be zero; in the handshake not (`shell_start.dart`).
///
/// WHAT THIS COSTS: one handshake per neighbour (2400 B out, 1200 B back,
/// one round trip; waiting packets lie here meanwhile); 30 B per packet;
/// renewal only after a pause (§11.6: real traffic after silence AND an own
/// real sending pause, [renewDue]; before a request to a counterpart silent
/// for more than 2 s, [renewIfSilent]) — never by cover. **No protection
/// against replay** here; the layers above discard duplicates (§9.2).
///
/// **Not WHO the neighbour is:** the handshake is anonymous; the envelope decides that. A moved
/// neighbour is found under its old link (`shell_roam.dart`), a node under several addresses
/// holds one link (`shell_counterpart.dart`, D-92).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/link/link_kdf.dart';
import 'package:mycelium/wire.dart';
import 'package:mycelium/shell_start.dart';
import 'package:mycelium/shell_counterpart.dart';
import 'package:mycelium/shell_link.dart';
import 'package:mycelium/shell_roam.dart';
import 'package:mycelium/trace.dart' show traceOn;

class Shell implements PacketRoute {
  final PacketRoute _bottom;
  final void Function(String) _report;

  /// Deadline from [kLinkSilence]. To be set differently only for probes — waiting
  /// 120 s would not be a smoke but a coffee break.
  final Duration silence;

  /// The clock for [Link.heard]/[Link.last]; probes pass a simulated one.
  final DateTime Function() _now;

  final Map<String, Link> _links = {};
  final Map<String, Start> _running = {};
  final Map<String, List<Uint8List>> _waiting = {};
  final Map<String, Unclear> _unclear = {};
  final Map<String, (Uint8List, Uint8List)> _answered = {};
  final Map<String, DateTime> _freshStartLast = {};
  final Map<String, Timer> _deadlines = {};
  final Map<String, int> _attempt = {};
  /// Running fresh starts ([_freshStart]): the only handshakes started
  /// WITHOUT repetition, and the ones [kFreshStartConcurrent] counts (C-12).
  /// A real send wish meeting one makes it its own and it leaves ([_start]).
  /// One lost packet once left an entry forever (S397-2): one deadline each.
  final Set<String> _oneShot = {};

  void Function(Uint8List packet, InternetAddress from, int fromPort)? _further;
  bool _to = false;

  /// Counters for probes and the network statistics (§25) — read only.
  int handshakesStarted = 0;
  int handshakesDone = 0;
  int dropped = 0;
  int get unclearKept => _unclear.length; // addresses with a kept packet ([kUnclearAtMost])
  HopEnd? onHopEnd; // §20.2: how a handshake with waiting packets ended (`split.dart` attach)
  Silent? onSilent; // §11.3a: a handshake and its repeats without an answer — the address failed (`shell_link.dart`)
  Silent? onHeard; // §11.8.6: a packet opened under this address's own link
  Moved? onMoved; // §11.8.6: opened under ANOTHER address's link (`shell_roam.dart`)
  Silent? onCalled; // §11.8.6: a handshake from there set up a link here
  Silent? onSelf; // D-92 A.4: the own flight 1 came back — that address is this node
  SameNode? sameNode; // §11.8.7, D-92 A.3: one link per counterpart (`shell_counterpart.dart`)
  /// A move (`shell_roam.dart`): [to] borrows [old]'s link; `false` if none ([roamEnd] gives it back).
  bool roamValidate(InternetAddress to, int toPort, InternetAddress old, int oldPort) =>
      roamLend(_links, shellWho(to, toPort), shellWho(old, oldPort));
  void roamEnd(InternetAddress to, int toPort, InternetAddress old, int oldPort) =>
      roamUnlend(_links, shellWho(to, toPort), shellWho(old, oldPort));
  Iterable<String> _same(InternetAddress a, int p) =>
      [for (final o in sameNode?.call(a, p) ?? const []) shellWho(o.$1, o.$2)];

  Shell(this._bottom,
      {void Function(String)? report, this.silence = kLinkSilence, DateTime Function()? clock})
      : _report = report ?? ((String s) => stderr.writeln(s)),
        _now = clock ?? DateTime.now {
    _bottom.listen(_onPacket);
  }

  /// Whether a key stands towards [target]:[targetPort], heard within [silence].
  bool stands(InternetAddress target, int targetPort) =>
      !(_links[shellWho(target, targetPort)]?.heard ?? DateTime(0))
          .isBefore(_now().subtract(silence));

  /// Before a request that expects an answer (post box `0x32`): a link not
  /// heard for > [kCompanionAfter] is dropped, so a gone counterpart ends
  /// `unreachable` after the handshake (S399 step 4, finding 7, variant A).
  void renewIfSilent(InternetAddress target, int targetPort) {
    final w = shellWho(target, targetPort);
    final l = _links[w];
    if (l == null || _now().difference(l.heard) <= kCompanionAfter) return;
    linkDrop(_links, l, _answered.remove); // nothing re-sent under the new key (§11.3a, S407)
    _report('Shell: $w silent for > 2 s — new handshake for a request');
  }

  /// Whether packets to [target]:[targetPort] wait for a handshake.
  bool holds(InternetAddress target, int targetPort) => _waiting.containsKey(shellWho(target, targetPort));

  @override
  bool send(Uint8List payload, InternetAddress target, int targetPort) =>
      _send(payload, target, targetPort, cover: false);

  /// The path of the cover stream (§5.1: own buffer, no path to delivery).
  ///
  /// Via [send] cover (1170 B since W4) occupied the (since S407 removed) resend buffer and
  /// displaced real packets in the handshake queue (S391, E3). So it is
  /// never kept and never waits: without a key it triggers the handshake
  /// and is itself lost; with a key, however old, it never renews (F29-A).
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
    final w = shellWho(target, targetPort);
    final l = nodeLink(_links, w, _same(target, targetPort)); // D-92 A.3
    if (l != null) {
      final now = _now();
      // Cover and keep-alive never renew (F29-A, V4.2 §11.6): towards a
      // silent neighbour that was a handshake every ≈ 130 s in idle.
      // Real traffic renews only after a sending pause ([renewDue]).
      if (cover || !renewDue(l, now, silence)) {
        l.last = now;
        if (!cover) l.lastReal = now; // own cover is no sign of life (S406 V-1)
        // Cover is never kept — nothing waits on it, and a repeated cover
        // packet would be a pattern on the wire. Empty payload likewise.
        if (!cover && payload.isNotEmpty) {
          companion(l, now, () => _to || _links[w] != l || // F28-1
              _bottom.send(pack(Uint8List(0), l.sendKey), target, targetPort));
        }
        return _bottom.send(pack(payload, l.sendKey), target, targetPort);
      }
      // Expired: see [kLinkSilence]. First gone, then new — otherwise the
      // branch below takes the old key again. What went out under the old
      // key is NOT sent again (S407, §11.3a): the one repeat path is the
      // transport's silence rule, for the packets that expect an answer.
      linkDrop(_links, l, _answered.remove); // under every address (D-92)
      _report('Shell: key to $w has been unconfirmed for ${silence.inSeconds} s '
          '— new handshake');
    }
    if (cover) {
      // Nothing waits for a cover packet, but flight 1 expects an answer
      // like every packet that does: repeated, then the address has failed
      // (§11.3a). Until S407 a one-shot whose silence counted as one use.
      _start(w, target, targetPort);
      return false;
    }
    // Held without eviction for the handshake ([HopEnd]).
    _waiting.putIfAbsent(w, () => []).add(Uint8List.fromList(payload));
    _start(w, target, targetPort);
    return true;
  }

  @override
  void listen(void Function(Uint8List packet, InternetAddress from, int fromPort) onPacket) =>
      _further = onPacket;

  /// Ends the own timers; the [Wire] stays with the caller.
  void close() {
    _to = true;
    for (final t in _deadlines.values) { t.cancel(); }
    _deadlines.clear();
    _running.clear();
    _oneShot.clear();
    _waiting.clear();
    _unclear.clear();
  }

  // ── Sending ─────────────────────────────────────────────────────────────

  /// [withRetry] `false` means: ONE attempt — how the recipient starts
  /// ([_freshStart]); a repetition would amplify (4 packets for 2), and if no
  /// answer comes the counterpart keeps sending ([kFreshStartLock]).
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
    if (traceOn) _report('TRACE shell handshake to $w started${withRetry ? "" : " (one attempt)"}');
    flight1(_bottom, b, target, targetPort);
    if (withRetry) {
      _deadline(w, target, targetPort);
      return;
    }
    _oneShot.add(w);
    _deadlines[w]?.cancel();
    _deadlines[w] = Timer(kAnswerDeadline, () {
      _deadlines.remove(w);
      if (!_oneShot.remove(w)) return; // answered or upgraded
      _forget(w);
      // Not repeated (§11.6), so nothing is declared failed (§11.3a).
    });
  }

  void _deadline(String w, InternetAddress target, int targetPort) {
    _deadlines[w]?.cancel();
    _deadlines[w] = Timer(kAnswerDeadline, () {
      _deadlines.remove(w);
      final b = _running[w];
      if (b == null) return; // done or given up
      final n = (_attempt[w] ?? 1) + 1;
      if (n > kAttempts) return _fail(w, target, targetPort, 'does not answer');
      _attempt[w] = n;
      flight1(_bottom, b, target, targetPort);
      _deadline(w, target, targetPort);
    });
  }

  void _forget(String w) {
    _running.remove(w);
    _oneShot.remove(w);
    _attempt.remove(w);
    _deadlines.remove(w)?.cancel();
  }

  /// [w]'s start ended without a link: the address has failed (§11.3a).
  void _fail(String w, InternetAddress target, int targetPort, String why, {bool self = false}) {
    if (self) onSelf?.call(target, targetPort);
    _forget(w);
    final q = _waiting.remove(w);
    dropped += q?.length ?? 0;
    _report('Shell: $w $why — ${q?.length ?? 0} packet(s) '
        'dropped; other steps of the ladder keep running');
    if (q != null) onHopEnd?.call(target, targetPort, true);
    onSilent?.call(target, targetPort);
  }

  // ── Receiving ───────────────────────────────────────────────────────────

  void _onPacket(Uint8List p, InternetAddress from, int fromPort) {
    // On the data port lies NOTHING other than a shell. Whatever has a
    // different length is foreign traffic, not an old format.
    if (p.length != kShellSize) return;
    final w = shellWho(from, fromPort);
    final l = _links[w];
    if (l != null) {
      final content = unpack(p, l.receiveKey);
      if (content != null) {
        l.heard = _now();
        l.last = l.heard;
        l.companionSpent = false; // a new silence starts ([kCompanionAfter])
        onHeard?.call(from, fromPort); // authenticated: only under this address's key
        // Empty = cover; it does not go upwards (§5.1).
        if (content.isNotEmpty) _further?.call(content, from, fromPort);
        return;
      }
      // D-92 A.5, once per key: "nothing arrived" is not "nothing opened".
      if (traceOn && l.unopenedFirst()) _report('TRACE shell packet from $w does not open under the key that stands there');
    }
    final b = _running[w];
    final k = b == null ? null : complete(b, p);
    // §11.8.7: the answer is bound to its handshake, not to an address (D-92 A.2).
    final x = k != null ? (w, k) : answerElsewhere(_running, p, w, fromPort);
    if (x != null) {
      final t = whoAddress(x.$1)!;
      _forget(x.$1);
      return _setUp(x.$1, x.$2, caller: true, target: t.$1, targetPort: t.$2, also: w);
    }
    // A moved counterpart's packet opens under its old link (§11.8.6): read
    // as any packet; only the answer to the path request adopts the address
    // (tried under a dead key too: unreadable means under none, §11.8.7).
    final moved = l != null || onMoved != null ? roamOpen(_links, p, w) : null;
    final old = moved == null ? null : whoAddress(moved);
    if (old != null) {
      final m = onMoved; // joined by the list, or the path request decides
      if (roamReceive(_links, w, moved!, l, _same(from, fromPort),
          m == null ? null : () => m(old.$1, old.$2, from, fromPort))) {
        _onPacket(p, from, fromPort);
      }
      return;
    }
    _assemble(w, p, from, fromPort);
  }

  /// A packet that was neither a data packet nor an expected answer: it can
  /// be part A or part B of a foreign flight 1. Which of the two
  /// is decided only by the counterpart piece — therefore collecting and not
  /// guessing (`ordnen` in `shell_start.dart`).
  void _assemble(String w, Uint8List p, InternetAddress from, int fromPort) {
    final u = unclearFor(_unclear, w); // bounded, the oldest goes (§20.2)
    final old = u.last;
    final pair = old == null ? null : sort(old, p);
    if (pair != null) {
      _unclear.remove(w);
      _answer(w, pair.$1, pair.$2, from, fromPort);
      return;
    }
    // [p] fits nothing kept: IT is now the half a flight 1 may complete,
    // what was kept goes ([Unclear], S401). Every SECOND such packet: two
    // that do not fit together, from someone without key — either
    // nonsense, or a counterpart that still knows us while we no longer
    // know it. We cannot distinguish that, so we answer with exactly as
    // many packets as came in ([kFreshStartLock]).
    u.last = p;
    u.first = !u.first;
    if (!u.first) _freshStart(w, from, fromPort);
  }

  void _freshStart(String w, InternetAddress from, int fromPort) {
    // §11.8.7: "open under no key" — a link that does not open them is no
    // key for them (D-92 A.1); until S412 it stopped the heal (RCA B-1).
    if (_running.containsKey(w)) return;
    if (_oneShot.length >= kFreshStartConcurrent) return; // own: not (C-12)
    final now = _now();
    _freshStartLast
        .removeWhere((_, t) => now.difference(t) > kFreshStartLock);
    if (_freshStartLast.containsKey(w)) return;
    _freshStartLast[w] = now;
    _start(w, from, fromPort, withRetry: false);
  }

  void _answer(String w, Uint8List partA, Uint8List partB,
      InternetAddress from, int fromPort) {
    final uniformA = Uint8List.sublistView(partA, 0, kUniform);
    final mine = startOf(_running, uniformA), to = mine == null ? null : whoAddress(mine); // own flight 1 back
    // D-92 A.4: remembered until a network change ([onSelf]).
    if (to != null) return _fail(mine!, to.$1, to.$2, 'is this node itself (own handshake back from $w)', self: true);

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
    _forget(w);
    _answered[w] = (a.uniformCaller, a.packet);
    _bottom.send(a.packet, from, fromPort);
    _setUp(w, a.key, caller: false, target: from, targetPort: fromPort);
    onCalled?.call(from, fromPort);
  }

  void _setUp(String w, Uint8List linkKey,
      {required bool caller,
      required InternetAddress target,
      required int targetPort,
      String? also}) {
    // The caller sends under `cell/init` and listens on `cell/resp`, the
    // callee the other way round: two directions never share a
    // nonce space (`link_kdf.dart`).
    final init = LinkKdf.deriveCellKeyInit(linkKey);
    final resp = LinkKdf.deriveCellKeyResp(linkKey);
    final n = Link(caller ? init : resp, caller ? resp : init, _now());
    linkPut(_links, w, n); // under every address of the counterpart (D-92)
    if (also != null && also != w) linkPut(_links, also, n);
    handshakesDone++;
    if (traceOn) _report('TRACE shell link to $w set up as ${caller ? "caller" : "callee"}');
    capLinks(_links, _answered.remove);
    final q = _waiting.remove(w);
    if (q == null) return;
    for (final n in q) {
      send(n, target, targetPort);
    }
    onHopEnd?.call(target, targetPort, false);
  }
}
