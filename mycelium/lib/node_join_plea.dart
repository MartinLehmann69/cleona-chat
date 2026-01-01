/// The first packets of a QR/NFC join as requests under the one rule of
/// silence (V4.2 §11.3a, §15.5; S407-STILLE F-3).
///
/// Until S407 the application timed the join's round trip itself: 5 s for
/// the bundle, plus the longest step-3 hand-on, plus the registration of the
/// reply code (`mailbox_invitation.dart`, up to 24.2 s with §11.3a) — a clock
/// above the transport. Now the bundle plea (`0x01`) is a packet that
/// expects an answer — the bundle, which moves the join's chain on — and the
/// transport repeats it and says "answered" or "failed"; the caller waits
/// for that and for the start of the join (after the reply code's
/// registration, itself answered or failed), never for a deadline.
library;

import 'dart:async';
import 'dart:io' show InternetAddress;
import 'dart:typed_data';

import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/first_contact.dart' show Join;
import 'package:mycelium/ladder.dart' show LadderStep, Shipment;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_silence.dart';
import 'package:mycelium/silence.dart';

final Expando<Completer<bool>> _outcome = Expando('join plea outcome');
final Expando<Completer<void>> _answer = Expando('join plea answer');
final Expando<Completer<void>> _started = Expando('join started');
final Expando<CardAddress> _pleaTo = Expando('join plea address');
final Expando<Completer<bool>> _request = Expando('join request outcome');

extension NodeJoinPlea on Node {
  /// `true` once the plea of [b] was answered (the bundle came), `false`
  /// once it and its repeats stayed without one at the card's address.
  Future<bool> joinPleaOutcome(Join b) =>
      (_outcome[b] ??= Completer<bool>()).future;

  /// Completes when [b] has started (its request window stands, or its
  /// plea left) — after the reply code's registration answered or failed.
  Future<void> joinStartedEvent(Join b) =>
      (_started[b] ??= Completer<void>()).future;

  /// [b] has started.
  void joinStartedMark(Join b) {
    final s = _started[b] ??= Completer<void>();
    if (!s.isCompleted) s.complete();
  }

  /// Sends the plea with [send] (all applicable ladder steps) as a request
  /// to [to], repeated by the transport until [joinPleaAnswered]; [ended]:
  /// the join was given up — no more repeats.
  void joinPleaAsk(Join b, CardAddress to, void Function() send,
      bool Function() ended) {
    final a = _answer[b] = Completer<void>();
    final o = _outcome[b] ??= Completer<bool>();
    _pleaTo[b] = to;
    unawaited(silence
        .ask(a.future,
            to: InternetAddress.fromRawAddress(Uint8List.fromList(to.address)),
            port: to.port,
            send: (_, __) {
              send();
              return null;
            },
            // One sending crosses a handshake and a hop: the answer wait of
            // a whole address (§11.3a), not of a single packet.
            wait: kAddressFailsAfter,
            others: false,
            // The plea goes by every ladder step: the transport cannot tell
            // which one the bundle answered — [joinPleaAnswered] stamps.
            cancelled: () => ended() || a.isCompleted,
            what: 'first contact plea 0x01')
        .then((at) {
      if (!o.isCompleted) o.complete(at != null && a.isCompleted);
    }));
  }

  /// The plea of [b] had no address at all: nothing can answer it.
  void joinPleaNoWay(Join b) {
    final o = _outcome[b] ??= Completer<bool>();
    if (!o.isCompleted) o.complete(false);
  }

  /// The chain of [b] moved on: its plea is answered. [from]: the address
  /// the answer arrived from (`null`: a post box, a neighbour, or already
  /// stamped by the ladder). Only when it is the plea's own address does the
  /// answer stamp it (§11.8.4, S407-LB-P1 O-2).
  void joinPleaAnswered(Join b, {CardAddress? from}) {
    final a = _answer[b];
    if (a == null || a.isCompleted) return;
    a.complete();
    final to = _pleaTo[b];
    if (to != null && from != null && from.equal(to)) {
      silence.answeredBy(
          InternetAddress.fromRawAddress(Uint8List.fromList(to.address)), to.port);
    }
  }

  /// What the transport says about the request (2) of the QR/NFC join [b]
  /// (§11.3a "answered, or failed"; S408, S407-FLAKERCA O-1): `true` once a
  /// way carried it — step 1 answered by the issuer's end mark (the issuer
  /// holds it whole, §11.3), or step 3 left, which has no answer of its own
  /// and leaves the waiting for the answer (3) as it was — `false` once no
  /// step applied, or step 1 was the only one and it and its repeats stayed
  /// silent. A QR/NFC invitation is redeemable only while its issuer is on
  /// (§15.1): then the join ends like a plea without answer (S405 V4).
  Future<bool> joinRequestOutcome(Join b) =>
      (_request[b] ??= Completer<bool>()).future;

  /// [s] carries the request (2) of the QR/NFC join [b]: watch it for
  /// [joinRequestOutcome]. Only its first sending counts.
  void joinRequestWatch(Join b, Shipment s) {
    final o = _request[b] ??= Completer<bool>();
    if (o.isCompleted) return;
    final failed = s.stepOneFailed;
    if (s.started.any((x) => x != LadderStep.lan) || s.started.isEmpty) {
      o.complete(s.started.isNotEmpty);
    } else if (failed == null) {
      o.complete(true); // step 1 without an answer to wait for: as before
    } else {
      unawaited(failed.then((f) {
        if (!o.isCompleted) o.complete(!f);
      }));
    }
  }
}
