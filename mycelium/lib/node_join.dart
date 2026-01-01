import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/first_contact.dart';
import 'package:mycelium/envelope.dart' show Address;
import 'package:mycelium/identity.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/address_class.dart' show routesFromCard;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart' show hexFrom, shortFrom;
import 'package:mycelium/node_join_plea.dart';
import 'package:mycelium/ladder.dart';
import 'package:mycelium/card_text_key.dart' show cardWithNeighbour;
import 'package:mycelium/neighbourhood_card.dart' show cardSeatForStrangers;
import 'package:mycelium/pair.dart' show dayValue, firstContactCode;
import 'package:mycelium/proof_of_work.dart' show ProofOfWork;

/// How THIS side joins — and why that is a file of its own.
///
/// The join is the only send path of the node that **has no
/// contact**. `Node._viaLadder` asks `routesTo` and gets the
/// three addresses from the mailbox; here there is no mailbox and no
/// contact that one could ask. The routes are exclusively in the
/// CARD (§15.2), and that is the only reason why this file
/// exists: it is the place where a card becomes a [Target].
///
/// Until S390 nothing was sent here at all — `Join` itself chose an
/// address (`oeffentlich ?? nachbar ?? lan`) and went via `rohSenden` past
/// the ladder. That had two consequences, and the second is the
/// worse one:
///
///  1. Of three addresses of a card exactly one carried (§7.1 requires all
///     applicable steps simultaneously).
///  2. If the public address was missing — the normal case behind CGNAT —,
///     the join went to the **neighbour address**. That belongs to a
///     third party. §8.1 FORWARDS via him with `0x20`; a
///     first-contact packet to him himself belongs to no invitation at his side
///     and is discarded. The join failed silently.
extension NodeJoin on Node {
  /// Joins via a card. [introduction] stands in the request (2) and
  /// is what the inviter sees in his question (§15.5).
  ///
  /// [lineBundle] and [pkInv] come from a `cleona:2:` line (proposal E): no
  /// bundle round trip, and step 4 leaves the request under the invitation
  /// value `dayValue(pkInv)` ([Target.boxValue]) — the issuer may be off. Throws
  /// [FirstContactError] if the bundle does not match the card.
  ///
  /// For such an out-of-band join (S405 F-1, owner decision 06.10.2026):
  /// [onRequest] is told ONCE what became of the request (2) — `true` when a
  /// way carried it or the post box took it (§9.1 `in transit`, the rule of
  /// `mailbox_outbound.dispatch`), `false` when its placing ended without
  /// either (it rests and goes out again at the next edge, [joinsSendAgain]);
  /// [onPlaced] each time the post box took it (the caller saves).
  Join join(Card card,
      {Identity? forField,
      Introduction? introduction,
      Address? lineBundle,
      Uint8List? pkInv,
      void Function(bool inTransit)? onRequest,
      void Function()? onPlaced}) {
    final asValue = forField ?? main;
    final underInvitation =
        lineBundle != null && pkInv != null ? dayValue(pkInv) : null;
    late final Join b;
    b = Join(
      me: asValue.postBox,
      card: card,
      send: (p, proof) =>
          _viaTheLadder(b, p, card, asValue, proof, underInvitation),
      report: report,
      introduction: introduction,
      lineBundle: lineBundle,
    );
    _watch[b] = (onRequest: onRequest, onPlaced: onPlaced);
    asValue.joins.add(b);
    // EDGE (§8.1): the join's one-time answer code joins the list, and it
    // must be at the fixed neighbour BEFORE the request goes out — the
    // bundle and the acceptance come back under it (§15.5). Missing until
    // S394: the code went with the next cover packet, 25 s after the request
    // (handset, 24.09.). Since F-B the request leaves when the `0x25` for the
    // piece carrying the code is back, or after its re-send stayed
    // unanswered at every address (§11.3a) — and it names the address
    // that answered (`RegistrationSend.namedAddress`). Field 06.10.2026: the
    // code went to a dead first address, the answer arrived before it.
    codeRoute.codesChanged();
    final seat = cardSeatForStrangers(neighbourhood);
    if (seat == null) {
      b.start();
      joinStartedMark(b);
    } else {
      final t0 = DateTime.now();
      codeRoute.registration.whenRegistered(seat, b.answerCode, (at) {
        report('Join: answer code ${shortFrom(hexFrom(b.answerCode))} '
            '${at == null ? "not confirmed by the fixed neighbour" : "registered at $at"} '
            'after ${DateTime.now().difference(t0).inMilliseconds} ms — request leaves');
        b.start();
        joinStartedMark(b);
      });
    }
    return b;
  }

  /// The round trip's deadline passed without a bundle (owner decision
  /// 06.10.2026, S405 V4 = A): the join ends ENTIRELY — off the list, its
  /// sending given up, its reply code no longer registered. Until S405 only
  /// the waiting ended: the join lived on, sent its request when a bundle
  /// came late, and was gone after the next restart, so the issuer's
  /// acceptance found no code (`berichte/S405-ERSTKONTAKT-GESAMTANALYSE.md`
  /// E-1). A bundle that arrives later finds no join and is reported. Since
  /// S408 also when the request (2) failed at its only step ([why]).
  ///
  /// An ended join sends NOTHING any more ([_viaTheLadder]): the waiter on
  /// its reply code's registration would otherwise still start it (Fable,
  /// `berichte/S405-FABLE-F1-OOB.md` 1b). Only for the QR/NFC round trip —
  /// an out-of-band join has no deadline (§15.1, S405 F-1).
  void joinAbandon(Join b,
      {Identity? forField, String why = 'no bundle within the deadline'}) {
    _ended[b] = true;
    (forField ?? main).joins.remove(b);
    _running[b]?.giveUp();
    _sentTo[b]?.giveUp();
    codeRoute.codesChanged();
    report('Join: $why — join '
        '${shortFrom(hexFrom(b.answerCode))} ended, its reply code deregistered');
  }

  /// A join restored from disk after a restart (proposal E,
  /// `memory_first_contact.dart`): its request is out, it waits for the
  /// answer (3) — which arrives directly, under its answer code, or out of
  /// the own post box. Sends nothing here; the answer code is registered
  /// again. An out-of-band join's [request] that no post box took yet goes
  /// out again at the next edge ([joinsSendAgain], S405 F-1), under the
  /// invitation value of [pkInv].
  Join joinRestore(Card card, Address counterpart, Uint8List answerCode,
      int window,
      {Identity? forField, Uint8List? pkInv, Uint8List? request, void Function()? onPlaced}) {
    final asValue = forField ?? main;
    final underInvitation = pkInv == null ? null : dayValue(pkInv);
    late final Join b;
    b = Join(
      me: asValue.postBox,
      card: card,
      send: (p, proof) => _viaTheLadder(b, p, card, asValue, proof, underInvitation),
      report: report,
      answerCode: answerCode,
    )..resume(counterpart, window);
    _watch[b] = (onRequest: null, onPlaced: onPlaced);
    if (request != null && underInvitation != null) {
      _pending[b] = request;
      _request[b] = request;
      _again[b] = () => _viaTheLadder(b, request, card, asValue, null, underInvitation);
    }
    asValue.joins.add(b);
    codeRoute.codesChanged();
    return b;
  }

  /// At an edge of §8.2 (`MailboxOutbound.giveUpAgain`): every out-of-band
  /// request of [i] that no post box has taken yet goes out again, unchanged
  /// (D-44 "only what is neither acknowledged nor placed is sent again",
  /// §9.3) — while the issuer still accepts its window (§15.5.1: seven days
  /// and one window). After that the invitation's 7 days are over and the
  /// user sends anew if he still wants to (owner decision 06.10.2026).
  void joinsSendAgain(Identity i) {
    final now = ProofOfWork.windowNow();
    for (final b in List.of(i.joins)) {
      final again = _again[b], w = b.requestWindow;
      if (b.done || b.declined || _pending[b] == null || again == null) continue;
      if (w == null || !ProofOfWork.windowAccepted(w, now)) continue;
      // Its placing still runs: nothing is sent again (as for messages,
      // `mailbox_outbound` `running`). Lab 06.10.2026 23:54:27: eight "new
      // neighbour" edges in 120 ms each re-sent the request — eight deposits.
      final run = _running[b];
      if (run != null && !run.finished && run.placed == null) continue;
      report('Join: out-of-band request ${shortFrom(hexFrom(b.answerCode))} not '
          'yet placed — sent again at this edge (D-44)');
      again();
    }
  }

  /// The out-of-band request of [b] that no post box has taken yet — what
  /// the caller saves with the join (`memory_first_contact.dart` version 3).
  Uint8List? joinPendingRequest(Join b) => _pending[b];

  /// The out-of-band joins of [i] whose issuer is looked up at this edge
  /// (§15.2, S407 V2): request out, no answer yet, its window still
  /// accepted, not looked up before in this run. Each is returned — and
  /// noted — ONCE; a restart is a start edge and may look it up again.
  List<Join> joinsToLookUp(Identity i) {
    final now = ProofOfWork.windowNow();
    final out = <Join>[];
    for (final b in List.of(i.joins)) {
      final w = b.requestWindow;
      if (_request[b] == null || b.done || b.declined || _ended[b] == true) continue;
      if (_lookedUp[b] == true || w == null || !ProofOfWork.windowAccepted(w, now)) {
        continue;
      }
      _lookedUp[b] = true;
      out.add(b);
    }
    return out;
  }

  /// [b]'s out-of-band request once more, to the addresses [moved] names
  /// (the issuer's record, `publisher_lookup.dart`) — directly only: the
  /// card's neighbour did not answer and the post box keeps its own rule
  /// ([joinsSendAgain]). The same packet: the issuer takes it once. Step 1
  /// is repeated until the issuer's end mark (§11.3a, as in [_viaTheLadder];
  /// S408, FLAKERCA O-2) — until S408 it left once.
  void joinSendTo(Join b, Card moved) {
    final packet = _request[b];
    if (packet == null || b.done || b.declined || _ended[b] == true) return;
    report('Join: out-of-band request ${shortFrom(hexFrom(b.answerCode))} '
        "sent to the issuer's current addresses (§15.2)");
    _sentTo[b]?.giveUp();
    _sentTo[b] = ladder.send(
        packet,
        Target.outDueTo(routesFromCard(moved),
            identifier: b.card.fingerprint,
            code: firstContactCode(b.card.code),
            postBoxApplicable: false),
        answeredByEndMark: true);
  }

  /// [b]'s card neighbour moved: the record under its key names [now]
  /// (`neighbour_find.dart`). Every later packet of [b] takes it, and the
  /// request goes again at once — the same packet (D-44): step 3 by the
  /// first-contact code and, for a line, the post box with [now] as holder.
  void joinNeighbourMoved(Join b, CardAddress now) {
    if (b.done || b.declined || _ended[b] == true) return;
    _moved[b] = cardWithNeighbour(b.card, now);
    report('Join ${shortFrom(hexFrom(b.answerCode))}: card neighbour found '
        'again at $now under its record key (§11.9) — request again');
    _again[b]?.call();
  }

  /// Put a first-contact packet on the ladder (§7.1).
  ///
  /// [proof] is the address from which the packet just answered came.
  /// It overrides the LAN role — evidence beats the claim
  /// of the card (`memory.dart`) — and it makes the post box
  /// moot: §8.2 keeps it for a recipient who is OFF,
  /// and whoever has just sent a packet is ON. Without evidence the
  /// post box applies, and if the card is empty too, it is the only route —
  /// exactly as it should be.
  ///
  /// Post box before the contact stands only for a line join, under its
  /// invitation value [underInvitation] (OP-20, S398): QR and NFC keep the
  /// round trip and are redeemable only while the issuer is on (§15.1), and
  /// no packet of a join goes under a day value another identity of this
  /// node knows (`node_step_four.dart`). Once [Join.done] — the receipt
  /// (4) — the ordinary day value of the now standing contact applies.
  ///
  /// Identifier and code travel ALONG: without the identifier the
  /// post box step cannot deposit, without the code the neighbour step cannot
  /// forward. The target identifier is the fingerprint of the card (§15.2
  /// „The fingerprint is the identifier"); the code is the
  /// first-contact code of the card (proposal M 5.7), which the issuer registers with
  /// his fixed neighbour (S391: registration builds M1).
  void _viaTheLadder(Join b, Uint8List packet, Card given,
      Identity asValue, CardAddress? proof, [Uint8List? underInvitation]) {
    // S407 a': the card's neighbour found again under its record key.
    final card = _moved[b] ?? given;
    if (_ended[b] == true) {
      // S405 F-1: an ended join sends nothing (the line above it may still
      // have reported building the packet).
      report('Join ${shortFrom(hexFrom(b.answerCode))} ended — packet '
          '0x${packet[0].toRadixString(16).padLeft(2, '0')} not sent');
      return;
    }
    // A new packet of this join means: the previous one is answered.
    // The five packets form a chain (0 → 2 → 4), each link is the
    // answer to the previous one. Without this line the bundle request (0)
    // would still deposit into three post boxes after [kVersatzBriefkasten], although the
    // bundle (1) has long been there — three deposits with 18 bits of
    // proof of work each (§8.2) for a packet that nobody needs any more.
    //
    // The SAME packet again (an edge of §8.2 re-sends the out-of-band
    // request, D-44) is no answer: the previous sending is replaced, not
    // acknowledged. Until S407 it was reported "delivered … acknowledged"
    // without any receipt (Windows lab 07.10.2026 20:47:53, ladder b25f9fae).
    final previous = _running[b];
    if (previous != null && bytesEqual(previous.packet, packet)) {
      previous.giveUp();
    } else {
      _sentTo[b]?.giveUp(); // the next link answers it as well
      // [proof]: where the answering link came from — it stamps the step-1
      // address of the previous link, else the plea's (§11.8.4, O-2), once.
      final stamped = previous?.acknowledged(from: proof) ?? false;
      // a new link of the chain answers the plea (§11.3a)
      joinPleaAnswered(b, from: stamped ? null : proof);
    }
    // The ONE line that makes the first contact via step 3 measurable: the
    // code under which the issuer should be registered with his fixed neighbour,
    // and whether the card names a neighbour at all —
    // without it the ladder SILENTLY does not plan step 3 (`ladder.dart`,
    // `ziel.nachbar != null && ziel.code != null`). The code prefix is
    // the same under which the issuer registers: this lets both
    // logs be brought together.
    final kn = card.neighbourAddress;
    final where = kn == null
        ? 'NONE — step 3 is dropped'
        : '${InternetAddress.fromRawAddress(kn.address).address}:${kn.port}';
    report('Join: first-contact code '
        '${shortFrom(hexFrom(firstContactCode(card.code)))}, card neighbour $where, '
        'proof ${proof == null ? "none" : "present"}');
    Shipment out() => _running[b] = ladder.send(
        packet,
        Target.outDueTo(routesFromCard(card),
            lan: proof,
            identifier: card.fingerprint,
            code: firstContactCode(card.code),
            postBoxApplicable:
                proof == null && (underInvitation != null || b.done),
            boxValue: b.done ? null : underInvitation,
            recipientOwn: card.ownAddresses),
        // §15.1, §11.3a: the request is repeated until the issuer holds it whole
        answeredByEndMark: packet[0] == PacketKind.request.code);
    // The QR/NFC plea expects the bundle: a request under §11.3a
    // (`node_join_plea.dart`, F-3) — every repeat goes all applicable steps.
    final to = proof ?? card.ownAddresses.firstOrNull ?? card.neighbourAddress;
    if (packet[0] == PacketKind.bundlePlea.code && underInvitation == null) {
      if (to == null) {
        out();
        return joinPleaNoWay(b);
      }
      return joinPleaAsk(b, to, () {
        _running[b]?.giveUp();
        out();
      }, () => _ended[b] == true);
    }
    final s = out();
    if (packet[0] == PacketKind.request.code && underInvitation == null && !b.done) {
      joinRequestWatch(b, s); // QR/NFC: answered or failed (§11.3a, O-1)
    }
    if (underInvitation != null && !b.done && packet[0] == PacketKind.request.code) {
      _requestOut(b, packet, s,
          () => _viaTheLadder(b, packet, card, asValue, null, underInvitation));
    }
  }

  /// §9.1 for the out-of-band request (S405 F-1; the rule of
  /// `mailbox_outbound.dispatch`, V11): `in transit` when a way carried it
  /// (step 1 or 3 left) or the post box took it (the second `0x31`, §8.2);
  /// until then it rests, never an error (§12.2). Placed is final (§9.3).
  void _requestOut(Join b, Uint8List packet, Shipment s, void Function() again) {
    _pending[b] = packet;
    _request[b] = packet;
    _again[b] = again;
    final w = _watch[b];
    void tell(bool inTransit) {
      if (_told[b] == true) return;
      _told[b] = true;
      report('Join: out-of-band request ${shortFrom(hexFrom(b.answerCode))} '
          '${inTransit ? "in transit (§9.1)" : "rests — no way carried it, no post box took it; again at the next edge"}');
      w?.onRequest?.call(inTransit);
    }

    if (s.started.any((x) => x != LadderStep.postBox)) tell(true);
    s.onPlacingEnd = (placed) {
      if (placed) {
        _pending[b] = null;
        w?.onPlaced?.call();
      }
      tell(placed);
    };
  }
}

/// Per out-of-band join: who is told about its request ([NodeJoin.join]).
final Expando<({void Function(bool)? onRequest, void Function()? onPlaced})>
    _watch = Expando('join watch');

/// Per out-of-band join: its request while no post box has taken it, and
/// how it goes out again ([NodeJoin.joinsSendAgain]).
final Expando<Uint8List> _pending = Expando('pending out-of-band request');
final Expando<void Function()> _again = Expando('send the request again');

/// Per out-of-band join: its request, kept after a post box took it, and
/// whether its issuer was looked up in this run (S407 V2).
final Expando<Uint8List> _request = Expando('out-of-band request');
final Expando<bool> _lookedUp = Expando('issuer looked up');
final Expando<Card> _moved = Expando('card with its neighbour found again');

/// Whether the out-of-band request's state was told ([NodeJoin._requestOut]).
final Expando<bool> _told = Expando('request state told');

/// Joins ended by [NodeJoin.joinAbandon] — they send nothing any more.
final Expando<bool> _ended = Expando('ended join');

/// The running sending per join. An [Expando] and not a map in the
/// node: the key is weak, so an abandoned join takes
/// its entry with it without anyone having to clean up.
final Expando<Shipment> _running = Expando('running first contact send');

/// The request sent to the issuer's current addresses ([NodeJoin.joinSendTo]).
final Expando<Shipment> _sentTo = Expando('request to current addresses');
