/// The volunteer of lane 2 (§17.6): pairs two cookies and forwards frames
/// 1:1, holding no key.
///
/// Every inbound-reachable always-on node volunteers; there is no switch
/// (D-31). The layer above says whether this node IS one ([allowed]:
/// desktop class and evidenced reachability, `host_stream.dart`).
///
/// ## What it answers (§17.4: no amplification surface)
/// - `0x56` ask: exactly one `0x57`, 34 B against 37 B asked — cookies, or
///   a refusal: size above `C` ([kStreamCap], D-1), already carrying or
///   reserved for a stream (V-b, D-29), or not a volunteer. No dialog.
/// - `0x58` join, `0x59` frame, `0x5A` missing: ONLY with a cookie of the
///   session, and after the join only from the address that joined with it.
///   Anything else is silence. A join is echoed (9 B for 9 B) once both
///   sides stand; a frame and a missing list are forwarded to the other
///   side under ITS cookie — the only packets larger than what they answer,
///   and they answer nothing: they are the other side's packets.
///
/// ## Bounds (§20.2)
/// ONE session at a time (V-b); per session two cookies, two addresses and
/// two stamps — no buffer: a frame is forwarded in the call that receives
/// it, so the memory per session is constant (about 100 B). A reservation
/// nobody joins dissolves after the connect window of 30 s; a paired
/// session after 10 s without a valid frame or list (§17.4). Both are
/// deadlines on a session, not idle clocks: without a session no timer
/// exists. A done or give-up list dissolves the session once forwarded.
/// No path migration: a packet with a valid cookie from another address is
/// ignored (a challenge as in §17.4 is not built for lane 2).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/card_address.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/stream_frame.dart';

/// The connect window of §17.6 ("connect window 30 s").
const Duration kStreamConnect = Duration(seconds: 30);

/// §17.4: 10 s without valid frames end the session.
const Duration kStreamLoss = Duration(seconds: 10);

class _Session {
  final Uint8List random;
  final CardAddress asker;
  final Uint8List senderCookie;
  final Uint8List recipientCookie;
  CardAddress? sender;
  CardAddress? recipient;
  bool paired = false;
  DateTime lastValid = DateTime.now();
  Timer? timer;
  bool timerIsLoss = false;
  _Session(this.random, this.asker, this.senderCookie, this.recipientCookie);
}

class StreamVolunteer {
  final void Function(Uint8List packet, CardAddress to) _send;
  final void Function(String)? report;

  /// Whether this node volunteers now: desktop and reachable from outside.
  bool Function() allowed;

  _Session? _s;

  /// Sessions carried to their end and sessions dissolved — for probes.
  int carried = 0;
  int dissolved = 0;

  StreamVolunteer(
      {required void Function(Uint8List, CardAddress) send,
      required this.allowed,
      this.report})
      : _send = send;

  /// Whether a session is reserved or running (V-b).
  bool get busy => _s != null;

  /// Handles a lane-2 packet; `false` if it is not the volunteer's.
  bool receive(Uint8List p, CardAddress from) {
    final k = p[0];
    if (k == kinds.kStreamAsk) {
      _ask(p, from);
      return true;
    }
    final s = _s;
    final c = streamCookie(p);
    if (s == null || c == null) return false;
    final fromSender = cookieSame(c, s.senderCookie);
    final fromRecipient = cookieSame(c, s.recipientCookie);
    if (!fromSender && !fromRecipient) return false;
    if (k == kinds.kStreamJoin && isJoin(p)) {
      _join(s, fromSender, from);
    } else if (k == kinds.kStreamFrame && fromSender && s.paired &&
        _at(s.sender, from) && p.length == kFrameLength) {
      _live(s);
      _send(cookieSwap(p, s.recipientCookie), s.recipient!);
    } else if (k == kinds.kStreamMissing && fromRecipient && s.paired &&
        _at(s.recipient, from)) {
      final m = readMissing(p);
      if (m == null) return true;
      _live(s);
      _send(cookieSwap(p, s.senderCookie), s.sender!);
      if (m.form == kMissingDone || m.form == kMissingGiveUp) {
        carried++;
        _end(s, m.form == kMissingDone ? 'done' : 'given up');
      }
    }
    return true;
  }

  static bool _at(CardAddress? a, CardAddress from) => a != null && a.equal(from);

  void _ask(Uint8List p, CardAddress from) {
    final a = readAsk(p);
    if (a == null) return;
    final s = _s;
    if (s != null && cookieSame(s.random, a.random) && s.asker.equal(from)) {
      // The answer was lost: the same answer again, nothing new reserved.
      return _answer(from, a.random, kVerdictGranted, s);
    }
    final int verdict;
    if (!allowed()) {
      verdict = kVerdictNoVolunteer;
    } else if (a.size == 0 || a.size > kStreamCap) {
      verdict = kVerdictTooLarge;
    } else if (s != null) {
      verdict = kVerdictBusy;
    } else {
      final sodium = SodiumFFI();
      final n = _Session(a.random, from, sodium.randomBytes(kCookieLength),
          sodium.randomBytes(kCookieLength));
      _s = n;
      n.timer = Timer(kStreamConnect, () {
        if (_s == n && !n.paired) _end(n, 'nobody joined within 30 s');
      });
      report?.call('Stream: reserved for ${a.size} B');
      return _answer(from, a.random, kVerdictGranted, n);
    }
    _answer(from, a.random, verdict, null);
  }

  void _answer(CardAddress to, Uint8List random, int verdict, _Session? s) =>
      _send(
          answerPacket((
            random: random,
            verdict: verdict,
            senderCookie: s?.senderCookie ?? Uint8List(kCookieLength),
            recipientCookie: s?.recipientCookie ?? Uint8List(kCookieLength),
          )),
          to);

  void _join(_Session s, bool sender, CardAddress from) {
    final at = sender ? s.sender : s.recipient;
    if (at != null && !at.equal(from)) return; // no migration
    if (sender) {
      s.sender = from;
    } else {
      s.recipient = from;
    }
    if (s.sender == null || s.recipient == null) return;
    if (!s.paired) {
      s.paired = true;
      _live(s);
      report?.call('Stream: paired');
      _send(joinPacket(s.senderCookie), s.sender!);
      _send(joinPacket(s.recipientCookie), s.recipient!);
      return;
    }
    // A repeated join after pairing: its echo was lost.
    _send(joinPacket(sender ? s.senderCookie : s.recipientCookie), from);
  }

  /// A valid frame or list: the loss deadline moves. The timer is re-armed
  /// only when it fires, not per frame.
  void _live(_Session s) {
    s.lastValid = DateTime.now();
    if (s.timer?.isActive ?? false) {
      if (s.paired && s.timerIsLoss) return;
      s.timer!.cancel();
    }
    s.timerIsLoss = true;
    s.timer = Timer(kStreamLoss, () => _check(s));
  }

  void _check(_Session s) {
    if (_s != s) return;
    final quiet = DateTime.now().difference(s.lastValid);
    if (quiet >= kStreamLoss) return _end(s, '10 s without a valid frame');
    s.timer = Timer(kStreamLoss - quiet, () => _check(s));
  }

  void _end(_Session s, String why) {
    s.timer?.cancel();
    if (_s == s) _s = null;
    dissolved++;
    report?.call('Stream: session dissolved — $why');
  }

  void stop() {
    final s = _s;
    if (s != null) _end(s, 'stopped');
  }
}
