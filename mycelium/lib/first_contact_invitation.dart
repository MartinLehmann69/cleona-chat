/// Bob's side of first contact: he has invited and is waiting.
///
/// A separate file, because both sides together broke the line budget of 400
/// (`mycelium/README.md`, proposal from S384-RESTLISTE 2.5/2.6). The
/// cut is the direction: over there [Join] — who APPROACHES; here
/// [Invitation] — who WAITS. Shared only the wire format ([PacketKind],
/// [proofOfWorkHeaderLength], [withKind]), no state; `first_contact.dart`
/// re-exports this file.
///
/// [ContactRequest] has stood in `first_contact_request.dart` since S391 and is
/// re-exported from here.
library;

export 'package:mycelium/first_contact_request.dart';

import 'dart:typed_data';

import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/first_contact.dart';
import 'package:mycelium/first_contact_pair.dart';
import 'package:mycelium/first_contact_plea.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/proof_of_work.dart';
import 'package:mycelium/pair.dart' show newPairRandom;
import 'package:mycelium/envelope.dart';

/// Bob's side: he has invited and is waiting.
class Invitation {
  final PostBox me;
  final Uint8List code;
  final int expiryUnixSeconds;
  final Send send;
  final Report? report;

  /// Is asked before the contact comes about. That is the place
  /// where the GUI asks the user.
  ///
  /// [origin] is the network address from which the request arrived.
  /// It stands here because the inviting side otherwise learns NO route to the
  /// peer: the card carries its own address, not that
  /// of the joiner. Without it the inviter afterwards has a contact
  /// that it cannot reach (S383, proven in the field).
  ///
  /// It is also the only address that is right at this place: with
  /// a request the joiner dials the address from the card
  /// itself, so the packet comes directly. A message arriving later
  /// is NOT fit for this — it may have been passed on via a neighbour
  /// or fetched from a post box, and
  /// then the sender address belongs to the forwarder, not to the
  /// contact.
  ///
  /// `null` means "later" (V4.2 §12.5): the request waits in the buffer
  /// ([waiting]), [onBuffered] reports it, and the decision is made with
  /// [decide]. `true`/`false` decide immediately (probes).
  final bool? Function(Address who, CardAddress origin) ask;

  /// The same question with the asker's introduction (name, greeting); if it is
  /// set, IT is asked. A separate callback instead of a third
  /// argument to [ask], whose callers stand outside this file.
  final bool? Function(Address who, CardAddress origin, Introduction? self)?
      askWithIntroduction;

  /// What Bob writes about himself into the answer (3) — set at the decision
  /// (S394-11); without it the answer is still the bare decision byte.
  Introduction? introduction;

  /// How an ACCEPTANCE (3) goes out (ES-6 (a), S388): via ladder including
  /// post box; without specification directly to `origin`. A rejection always directly.
  final void Function(Uint8List packet, CardAddress origin, Address who)?
      acceptanceSend;

  /// A request is ACCEPTED — immediately or after [decide], no matter.
  /// The one place for the consequences (consume invitation, remember route).
  final void Function(Address who, CardAddress origin)? onAccepted;

  /// A request is NEWLY waiting for the decision (§12.5) — the question to
  /// the user. A repeated request from the same peer replaces
  /// the waiting one and is not reported again.
  final void Function(ContactRequest a)? onBuffered;

  /// Kind, counter, revocation, expiry (`invitation.dart`) — until S388 a separate
  /// flag here (B2, B4). Without specification (probes): single-use with [code].
  final inv.Invitation? entry;
  late final inv.Invitation _entry = entry ??
      inv.Invitation.outSplit(
          code: code,
          kind: inv.Kind.singleUse,
          expiryUnixSeconds: expiryUnixSeconds,
          difficulty: difficulty,
          atMost: 1,
          accepted: 0,
          revoke: false);

  /// Already a contact with the same keys (§15.5)? Answer without a question and
  /// WITHOUT consumption (ES-11).
  final bool Function(Address who, CardAddress origin)? recontact;

  /// The waiting requests, oldest first (§15.4); revoked: none. They
  /// lie in the buffer of the [entry] — only there do they go to disk with the invitation
  /// (E-1). The constructor binds every loaded request to
  /// this invitation; an unbound one stands out here as a type error.
  List<ContactRequest> get waiting => _entry.revoke
      ? const []
      : List.unmodifiable(_entry.requests.all.cast<ContactRequest>());

  /// Leading zero bits that the proof must have before unsealing —
  /// the same number with which Alice computed via [card].difficulty.
  /// The default matches the default value of a card ([Card.difficultyDefault]),
  /// so that existing callers without their own specification keep matching.
  final int difficulty;

  final RetryStore _retryStore = RetryStore();
  int _unsealAttempts = 0;
  Introduction? _requestIntroduction;

  bool _done = false;

  /// Whom this invitation has accepted — only for being able to assign a receipt (4)
  /// ([receiptFrom]).
  final List<Address> _accepted = [];

  bool get done => _done;

  /// All admissible acceptances are given out (single-use: one, open: `n`).
  bool get consumed => _entry.accepted >= _entry.atMost;

  bool get revoke => _entry.revoke;

  /// Does it still accept — not revoked, not consumed, grace period open?
  bool get accepts => _entry
      .acceptanceWindowOpenAt(DateTime.now().millisecondsSinceEpoch ~/ 1000);

  /// What the last request that came through said about its sender.
  /// Null as long as none was there or it sent nothing along.
  Introduction? get requestIntroduction => _requestIntroduction;

  /// How often [Envelope.unseal] was actually attempted for a request
  /// — the metric that shows that a junk request NEVER gets
  /// that far (see `berichte/P13-nachweis-verdrahtet.md`).
  int get unsealAttempts => _unsealAttempts;

  Invitation({
    required this.me,
    required this.code,
    required this.expiryUnixSeconds,
    required this.send,
    required this.ask,
    this.askWithIntroduction,
    this.introduction,
    this.report,
    this.difficulty = Card.difficultyDefault,
    this.onAccepted,
    this.onBuffered,
    this.entry,
    this.recontact,
    this.acceptanceSend,
  }) {
    // E-1: loaded requests get THIS invitation — only then are
    // they answerable and the question to the user is there again (§12.5).
    _entry.requests.bind(
        (a) => ContactRequest.buffered(this, a.who, a.origin, a.introduction, a.at,
            a.neighbour, a.answerCode));
  }

  /// Whether the request (2) in [packet] goes to THIS invitation: header long
  /// enough and the proof of work bound to [code] (steps 1 and 3 from
  /// [_requestCame]). Changes nothing — not the retry store either,
  /// otherwise a foreign invitation would remember a random value that it never
  /// checked. NO unsealing happens here.
  ///
  /// Until S385 the first open invitation of any identity got every
  /// request and silently discarded the foreign one at step 3.
  bool fitsProofOfWork(Uint8List packet) {
    if (packet.length < 1 + proofOfWorkHeaderLength) return false;
    if (packet[0] != PacketKind.request.code) return false;
    final (randomValue, counter) = _header(packet);
    return ProofOfWork.codeFindRecent([code], randomValue, counter,
            difficulty) !=
        null;
  }

  /// Random value and counter from the visible proof header.
  (Uint8List, int) _header(Uint8List p) => (
        Uint8List.sublistView(p, 1, 1 + ProofOfWork.randomValueLength),
        ByteData.sublistView(p)
            .getUint64(1 + ProofOfWork.randomValueLength, Endian.little),
      );

  /// Who receipts with [packet] — someone accepted by THIS invitation — or
  /// `null`. Whether the receipt (4) goes to THIS invitation at all is
  /// the same question: sealed to [me] and signed by someone whom it
  /// has accepted. Unseals as a probe for that; changes nothing.
  Address? receiptFrom(Uint8List packet) {
    if (_accepted.isEmpty || packet.isEmpty) return null;
    if (packet[0] != PacketKind.receipt.code) return null;
    try {
      final (_, sender) = Envelope.unseal(
          envelope: Uint8List.sublistView(packet, 1), recipient: me);
      return _accepted.any((a) => a.sameIdentity(sender)) ? sender : null;
    } on Object {
      return null;
    }
  }

  void receive(Uint8List packet, CardAddress from, {bool forwarded = false}) {
    if (packet.isEmpty) throw FirstContactError('empty packet');
    switch (PacketKind.fromCode(packet[0])) {
      case PacketKind.bundlePlea:
        _bundlePleaCame(packet, from, forwarded);
      case PacketKind.request:
        _requestCame(packet, from);
      case PacketKind.receipt:
        _done = true;
        // Proposal M: the edge "new contact" on this side.
        final who = receiptFrom(packet);
        if (who != null) pairHook[me]?.onContactStands(who);
        report?.call('receipt arrived — contact established on both sides');
      default:
        throw FirstContactError('unexpected kind ${packet[0]}');
    }
  }

  /// Packet (1): hand out the own bundle. It is public —
  /// nothing is given away here that is not public anyway.
  /// §15.5 "The way back for the bundle": directly when the request came
  /// directly; under the reply code through the named neighbour when it came
  /// through one — [from] is then the forwarder's address (S394-7).
  void _bundlePleaCame(Uint8List packet, CardAddress from, bool forwarded) {
    final r = bundlePleaRead(packet);
    final bundle = bundleAnswerBuild(r.randomValue, me);
    final back = r.replyCode != null && r.neighbour != null;
    report?.call(!forwarded ? 'Bundle handed out directly' : back
        ? 'Bundle handed out under the reply code'
        : 'Bundle request through a neighbour without a way back — not answerable');
    if (!forwarded) send(bundle, from);
    if (forwarded && back) pairHook[me]?.underCodeSend(r.replyCode!, r.neighbour!, bundle);
  }

  void _requestCame(Uint8List packet, CardAddress from) {
    // Step 1: header long enough? Otherwise discard silently — no
    // answer, no unsealing. On the same step as a
    // failed code check.
    if (packet.length < 1 + proofOfWorkHeaderLength) {
      return;
    }
    final (randomValue, counter) = _header(packet);
    final timeWindow = ProofOfWork.windowNow();

    // Step 2: random value already seen? Otherwise discard silently.
    if (!_retryStore.fresh(
        Uint8List.fromList(randomValue), timeWindow)) {
      return;
    }

    // Step 3: does the proof match one of the own codes? Otherwise
    // discard silently. `codeFind` keeps that bounded to at most ten
    // SHA-256 calls (here: one, there is only [code]).
    if (ProofOfWork.codeFindRecent(
            [code], randomValue, counter, difficulty) ==
        null) {
      return;
    }

    // Step 4: only now unseal.
    _unsealAttempts++;
    final (content, sender) = Envelope.unseal(
      envelope: Uint8List.sublistView(packet, 1 + proofOfWorkHeaderLength),
      recipient: me,
    );
    // Expiry PLUS grace period, revocation, consumption (`inv.Invitation.check`).
    // Revoked/expired stay silent immediately (§15.3), consumed only after
    // the recontact.
    final state = _entry.check(code);
    if (state == inv.Rejection.revoke) {
      report?.call('rejected: invitation revoked');
      return;
    }
    if (state == inv.Rejection.expired) {
      report?.call('rejected: code expired (the grace period of '
          '${inv.kGracePeriodDays} days is over as well)');
      return;
    }
    if (content.length < code.length ||
        !bytesEqual(Uint8List.sublistView(content, 0, code.length), code)) {
      report?.call('rejected: wrong code');
      return;
    }
    // Behind the code stands the introduction — or nothing, then it is
    // a request without one, and that still applies. A field that is too long is
    // REJECTED, not truncated, and here at the recipient: the
    // sender's check is no limit, it is the other side.
    // Before [ask], so that the user never gets to see a greeting
    // that exceeds the promised length.
    // Proposal M: before it answer code and neighbour of the requester.
    final RequestExtra z;
    try {
      z = requestExtraRead(content, code.length);
    } on IntroductionError catch (e) {
      report?.call('rejected: ${e.reason}');
      return;
    }
    final self = z.self;
    _requestIntroduction = self;
    // Recontact (§15.5, ES-11): answer without a question, BEFORE the consumed
    // check. If [recontact] asks along, ITS answer applies (§15.9).
    final already = _accepted.any((a) => a.sameIdentity(sender));
    if (recontact?.call(sender, from) ?? already) {
      report?.call('Re-contact — answer again, unconsumed (ES-11)');
      if (!already) _accepted.add(sender);
      onAccepted?.call(sender, from);
      _answer(sender, from, true, z.neighbour, z.answerCode);
      return;
    }
    if (state == inv.Rejection.consumed) {
      report?.call('rejected: code already used');
      return;
    }
    final yes = askWithIntroduction == null
        ? ask(sender, from)
        : askWithIntroduction!(sender, from, self);
    if (yes == null) {
      _buffer(ContactRequest.buffered(this, sender, from, self, DateTime.now(),
          z.neighbour, z.answerCode));
      return;
    }
    _decided(sender, from, yes, z.neighbour, z.answerCode);
  }

  /// The ONE decision about a waiting request (§12.5, §15.5).
  /// `false` if [a] is not (any longer) waiting or the invitation is consumed
  /// ([a] then stays); after a revocation nothing (§15.3, B2).
  /// [recontact]: already a contact (§15.5) — no consumption (ES-11).
  bool decide(ContactRequest a,
      {required bool accept, bool recontact = false}) {
    if (!_entry.requests.leads(a) || _entry.revoke) return false;
    if (accept && !recontact && _entry.check(code) != null) {
      return false;
    }
    _entry.requests.drop(a);
    _decided(a.who, a.origin, accept, a.neighbour, a.answerCode,
        count: !recontact);
    return true;
  }

  /// Takes [a] out of the buffer without an answer — the displacement from §15.4.
  bool drop(ContactRequest a) => _entry.requests.drop(a);

  void _buffer(ContactRequest a) {
    // Replacing, displacing and the cap of 20 lie in the buffer (§15.4).
    final fresh = _entry.requests.admit(a);
    report?.call('Request waits for the decision of the user');
    if (fresh) onBuffered?.call(a);
  }

  void _decided(Address sender, CardAddress from, bool yes,
      CardAddress? neighbour, Uint8List? answerCode, {bool count = true}) {
    if (yes) {
      if (count) _entry.acceptedThroughUser();
      _accepted.add(sender);
      onAccepted?.call(sender, from);
    }
    _answer(sender, from, yes, neighbour, answerCode);
  }

  void _answer(Address sender, CardAddress from, bool yes,
      CardAddress? neighbour, Uint8List? answerCode) {
    if (!yes) {
      final no = Envelope.seal(
        plaintext: Uint8List.fromList([0]),
        recipient: sender,
        sender: me,
      );
      report?.call('declined by the user');
      send(withKind(PacketKind.answer, no), from);
      return;
    }
    // On acceptance also the own introduction — then each
    // side holds name and greeting of the other, and nothing has to be asked
    // afterwards. NOT on a rejection: whoever declines gives nothing away.
    // Proposal M: s_AB — on recontact the remembered one, otherwise fresh.
    final h = pairHook[me];
    final s = h?.knownRandom(sender) ?? newPairRandom();
    h?.onPair(sender, s, neighbour);
    final yes2 = Envelope.seal(
      plaintext: acceptanceContentBuild(s, introduction),
      recipient: sender,
      sender: me,
    );
    report?.call('accepted — answer sent');
    final acceptance = withKind(PacketKind.answer, yes2);
    final ladder = acceptanceSend;
    ladder == null ? send(acceptance, from) : ladder(acceptance, from, sender);
    if (neighbour != null && answerCode != null) {
      h?.underCodeSend(answerCode, neighbour, acceptance);
    }
  }
}
