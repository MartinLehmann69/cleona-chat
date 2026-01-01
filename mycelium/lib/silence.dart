/// Silence (V4.2 §11.3a) — the ONE place where a packet that expects an
/// answer is waited for, repeated and given up.
///
/// The rule, as the norm states it (owner decision 13.10.2026): a packet that
/// expects an answer and gets none within its answer wait is repeated, at most
/// [kRepeatsAtMost] times. When it and its repeats all stay without an answer,
/// that address has failed — provided this node has confirmed, since its
/// start or last network change, another neighbour it reaches the same way
/// (same family, same side of the own segment) that is not itself silent
/// (D-68; the readiness decides that, `Readiness.addressFailed`). A neighbour is gone only when
/// every address it is known under has failed; until then the packet goes to
/// its other addresses the same way. Call media is the only exception: it
/// expects no answer, is never repeated and says nothing about a neighbour —
/// it never passes through here.
///
/// **The layers above learn two things: answered, or failed** (§11.3a "The
/// transport alone handles silence"). The delivery layer of §7–§10 and the
/// application do not repeat, count or time anything themselves. This is the
/// established procedure of every ARQ and of liveness detection (BFD, OSPF:
/// the counterpart is down after a fixed number of missed answers); here the
/// number is one packet plus three repeats per address.
///
/// Two forms, one count:
///
/// * [Silence.ask] — one request, one answer (an address question, a
///   registration piece, a deposit, a board question …).
/// * [SilentRounds] — a conversation that asks for what is still missing the
///   way §11.3 does (collection, re-request); each request that brings
///   nothing is a repeat, a request that brings something starts over.
///
/// No clock outside a running request: the only timer is the answer wait of
/// a packet that has just left (§1.2, nothing periodic in idle).
library;

import 'dart:async';
import 'dart:io';

import 'package:mycelium/shell_link.dart' show kAnswerDeadline;
import 'package:mycelium/split_flow.dart' show SendEnd;

/// At most this many repeats of a packet that got no answer (§11.3a).
const int kRepeatsAtMost = 3;

/// The packet and its repeats: after this many sendings without an answer
/// the address has failed (§11.3a).
const int kSendingsAtMost = 1 + kRepeatsAtMost;

/// The answer wait of a single packet over a standing link (§11.6, 800 ms).
const Duration kAnswerWait = kAnswerDeadline;

/// The longest a single packet takes to fail at one address over a standing
/// link — it and its repeats, each with its answer wait (3.2 s). A caller
/// that waits for an outcome of the transport sizes its budget with it
/// instead of a count of its own.
final Duration kAddressFailsAfter = kAnswerWait * kSendingsAtMost;

/// One address and its port.
typedef Address = (InternetAddress, int);

/// Sends the packet ONCE to [to]:[port]. The future says how the sending
/// ended: a [SendEnd] where it goes through the splitter, anything else
/// (or `null`) when it left at once. The answer wait starts only then — a
/// packet held for a handshake leaves when that ends (§11.6).
typedef SendOnce = FutureOr<Object?> Function(InternetAddress to, int port);

/// Who learns that an address has failed — the readiness (§22.7.1), which
/// applies the condition of the other confirmed neighbour and removes the
/// address from the list of §11.8. Returns whether it counted.
///
/// [silentNow]: the addresses (`address:port`) that are themselves without
/// an answer right now — a request to them has had a sending go unanswered
/// and has not ended. They are no counter-evidence: when the uplink dies,
/// every running request falls silent together, and the first to give up
/// must not take the others as proof that the uplink works (§11.3a "a dead
/// uplink … declares nothing failed").
typedef AddressFailed = bool Function(InternetAddress a, int port,
    {Set<String> silentNow});

/// The addresses of the node [a]:[port] belongs to, [a] first — the
/// neighbourhood's view (§11.8: a neighbour is held as a set of addresses).
typedef AddressesOf = List<Address> Function(InternetAddress a, int port);

/// What [Silence.ask] returns: the address that answered, or `null` when
/// every address it tried stayed silent (failed).
typedef Answered = Address?;

/// Who learns that [a]:[port] answered a packet of this node that expected
/// an answer — the neighbourhood, which stamps it (§11.8.4).
typedef AddressAnswered = void Function(InternetAddress a, int port);

class Silence {
  final AddressesOf _addressesOf;
  final AddressFailed _failed;
  final void Function(String)? _report;

  /// §11.8.4 "Only an answer confirms. Every answer to a packet of this node
  /// that expected one stamps the address that packet went to … and every
  /// other": the one place an answer turns into a stamp, the counterpart of
  /// [failedAddress]. Set by the host (`host_network.dart`), which stamps
  /// only an address its list holds; unset, an answer stamps nothing.
  AddressAnswered? onAnswered;

  /// Counters for probes and the network statistics (§25) — read only.
  int asked = 0;
  int repeated = 0;
  int answered = 0;
  int addressesFailed = 0;

  Silence(
      {AddressesOf? addressesOf,
      AddressFailed? failed,
      void Function(String)? report,
      this.onAnswered})
      : _addressesOf = addressesOf ?? ((a, p) => [(a, p)]),
        _failed = failed ?? ((a, p, {silentNow = const {}}) => false),
        _report = report;

  /// `address:port` -> running requests to it with an unanswered sending.
  final Map<String, int> _silent = {};

  void _quiet(String k, int d) {
    final n = (_silent[k] ?? 0) + d;
    n > 0 ? _silent[k] = n : _silent.remove(k);
  }

  /// Sends a packet that expects an answer to [to]:[port] with [send] and
  /// waits for [answer] — the station completes it from its receive path
  /// when the answer arrives (matched by its own identifier). Without an
  /// answer within [wait] the packet is repeated, at most [kRepeatsAtMost]
  /// times; then that address has failed ([failedAddress]) and, with
  /// [others], the packet goes to the next address of the same node the same
  /// way. Returns the address the packet last went to when [answer]
  /// completed, `null` when every address stayed silent or [cancelled]
  /// returned `true` (the station no longer needs the answer — nothing is
  /// declared failed then).
  ///
  /// An answer stamps the address the packet last went to ([answeredBy]) —
  /// only when [answer] completed with a value and [cancelled] does not say
  /// that the station had already ended the request: a station that
  /// completes its future to stop the repeats has received no answer
  /// (S407-LB-P1).
  ///
  /// [send] returning [SendEnd.unreachable] means the handshake towards that
  /// address got no answer to its own sendings (`Shell`, the same rule): the
  /// address has failed without further repeats. [SendEnd.refused] means the
  /// node's own bound took nothing (§20.2): the request ends without blame.
  /// [SendEnd.unconfirmed] means a transmission of several parts got neither
  /// end mark nor request (§11.3): that sending stayed without an answer.
  Future<Answered> ask(
    Future<Object?> answer, {
    required InternetAddress to,
    required int port,
    required SendOnce send,
    Duration wait = kAnswerWait,
    bool others = true,
    bool Function()? cancelled,
    String what = 'request',
  }) async {
    asked++;
    var done = false, withValue = false;
    unawaited(answer.then((_) => done = withValue = true,
        onError: (Object _) => done = true));
    // The answer stamps only what the station still waited for.
    Answered answeredAt(InternetAddress a, int p) {
      answered++;
      if (withValue && !(cancelled?.call() ?? false)) answeredBy(a, p);
      return (a, p);
    }

    final addresses = others ? _addressesOf(to, port) : [(to, port)];
    if (addresses.isEmpty) addresses.add((to, port));
    for (final (a, p) in addresses) {
      final k = '${a.address}:$p';
      var inSilence = false, shellDeclared = false;
      try {
        for (var n = 0; n < kSendingsAtMost; n++) {
          if (done) return answeredAt(a, p);
          // The first sending always leaves; only repeats ask whether the
          // station still needs the answer.
          if (n > 0 && (cancelled?.call() ?? false)) return null;
          if (n > 0) repeated++;
          Object? end;
          // A handshake still running after one answer wait has had its
          // first flight unanswered: the address is silent now as well.
          final t = Timer(wait, () {
            if (!inSilence) _quiet(k, 1);
            inSilence = true;
          });
          try {
            end = await send(a, p);
          } on Object {
            end = SendEnd.unreachable;
          } finally {
            t.cancel();
          }
          if (done) return answeredAt(a, p);
          if (end == SendEnd.refused) return null;
          // The handshake had its sendings, and the shell has declared the
          // address (`Shell.onSilent`): on to the next one.
          if (end == SendEnd.unreachable) {
            shellDeclared = true;
            break;
          }
          if (end != SendEnd.unconfirmed && await _within(answer, wait)) {
            return answeredAt(a, p);
          }
          // This sending stayed without an answer (an unconfirmed
          // transmission had no end mark): the address is silent now.
          if (!inSilence) _quiet(k, 1);
          inSilence = true;
        }
        if (done) return answeredAt(a, p);
        if (cancelled?.call() ?? false) return null;
      } finally {
        if (inSilence) _quiet(k, -1);
      }
      if (!shellDeclared) failedAddress(a, p, what);
    }
    return null;
  }

  /// [a]:[port] answered a packet of this node that expected an answer — a
  /// request through [ask], or one a station sends once outside it (the
  /// board question towards a 4.2.3 peer, `board.dart`). The neighbourhood
  /// stamps it ([onAnswered], §11.8.4).
  void answeredBy(InternetAddress a, int port) => onAnswered?.call(a, port);

  /// [a]:[port] has failed: a packet and its repeats, or a handshake and its
  /// repeats, stayed without an answer (§11.3a). The readiness decides
  /// whether that counts (another neighbour confirmed the same way, D-68)
  /// and removes it.
  void failedAddress(InternetAddress a, int port, [String what = 'request']) {
    final counted = _failed(a, port, silentNow: _silent.keys.toSet());
    if (counted) addressesFailed++;
    _report?.call('Silence: ${a.address}:$port — $what and its '
        '$kRepeatsAtMost repeats without an answer'
        '${counted ? ' — address failed' : ' — nothing declared failed (no other neighbour confirmed the same way)'}');
  }

  /// Whether [answer] completes within [wait].
  static Future<bool> _within(Future<Object?> answer, Duration wait) {
    final c = Completer<bool>();
    final t = Timer(wait, () {
      if (!c.isCompleted) c.complete(false);
    });
    answer.then((_) {
      t.cancel();
      if (!c.isCompleted) c.complete(true);
    }, onError: (Object _) {
      t.cancel();
      if (!c.isCompleted) c.complete(true);
    });
    return c.future;
  }
}

/// The count of a conversation that asks again for what is still missing
/// (§11.3, §8.2 collection, §9.4 media, §17.6 stream): the request that
/// brings nothing is repeated as [Silence.ask] repeats a packet — at most
/// [kRepeatsAtMost] times; a request that brings something starts over.
class SilentRounds {
  int _silent = 0;

  /// The repeats spent since the last progress.
  int get silent => _silent;

  /// Something new arrived: the count starts over.
  void progress() => _silent = 0;

  /// A request brought nothing within its wait. `true`: ask once more;
  /// `false`: the request and its repeats are spent — failed.
  bool again() => ++_silent <= kRepeatsAtMost;
}
