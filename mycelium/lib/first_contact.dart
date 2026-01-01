/// First contact — five packets, and each is complete in itself.
///
/// This file knows no network. It gets a function for sending and
/// is fed with incoming packets; how the bytes fly is the
/// business of wire.dart and split.dart. This makes the sequence checkable without
/// a network.
///
/// ```
/// ALICE                                   BOB
///  (0) bundle please   ---------------->  unsealed, 17/40/52 B, no identity
///      random value                       <---- (1) signed bundle + random value
///      checks signature, then identifier against the card's fingerprint
///  (2) request         ---------------->  proof header (visible) + sealed
///                                         code + introduction in the seal;
///                                         Bob checks proof BEFORE unsealing,
///                                         then code, GUI asks, Bob accepts
///                      <----------------  (3) answer, sealed:
///                                         decision byte + introduction
///  (4) receipt         ---------------->  sealed
/// ```
///
/// Packet (2) carries a visible proof of work before the envelope
/// (`proof_of_work.dart`): type byte(1) + random value(8) + counter(8), only then
/// the sealed envelope. Bob checks this header BEFORE he unseals —
/// without it every junk request costs him opening a hybrid
/// envelope.
///
/// [Join] — Alice's side — stands here. Bob's side ([Invitation]) stands
/// in `first_contact_invitation.dart` and is re-exported from here;
/// the reasoning for the cut stands in its header.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/bundle.dart';
import 'package:mycelium/first_contact_pair.dart';
import 'package:mycelium/first_contact_plea.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/card_expiry.dart';
import 'package:mycelium/proof_of_work.dart';
import 'package:mycelium/pair.dart' show firstContactCode;
import 'package:mycelium/envelope.dart';
import 'package:mycelium/introduction.dart';
import 'package:mycelium/kinds.dart' as kinds;

/// Bob's side of first contact lies in a separate file, but is
/// re-exported from here — every existing caller still imports only
/// `package:mycelium/first_contact.dart` and finds [Invitation] there.
export 'package:mycelium/first_contact_invitation.dart';

/// What a request and its answer say about the sender.
export 'package:mycelium/introduction.dart';

/// [Join.cardsExpiry] returns an [ExpiryState] — a
/// public return type that the caller must be able to name.
export 'package:mycelium/card_expiry.dart';

/// The five packets of first contact.
enum PacketKind {
  bundlePlea(kinds.kBundlePlea),
  bundle(kinds.kBundle),
  request(kinds.kRequest),
  answer(kinds.kAnswer),
  receipt(kinds.kReceiptFirstContact);

  const PacketKind(this.code);
  final int code;

  static PacketKind? fromCode(int c) {
    for (final s in PacketKind.values) {
      if (s.code == c) return s;
    }
    return null;
  }
}

/// Length of the visible proof header before the envelope in packet (2):
/// random value (8 B) + counter (8 B). The type byte before it does not count
/// here — it is part of [withKind].
const int proofOfWorkHeaderLength = ProofOfWork.randomValueLength + 8;

/// Where a packet goes. The delivery itself is done by the caller.
///
/// Applies to [Invitation] — the WAITING side. It always answers to the
/// address from which the request just came, and thus selects nothing.
typedef Send = void Function(Uint8List packet, CardAddress target);

/// How a packet of the JOIN goes out — **without [Join] choosing an
/// address**.
///
/// Until S390 [Send] stood here, and [Join] picked its target
/// itself (`oeffentlich ?? nachbar ?? lan`). Both were wrong: a
/// card carries THREE addresses for THREE steps (§7.1, §15.2), and the
/// neighbour address is no address of the peer at all — via it
/// forwarding happens with `0x20` (§8.1). Whoever writes to it sends the
/// join to a third party who is not the invitee.
///
/// [proof] is the address from which the packet just answered
/// came in. It is EVIDENCE and beats every card address in the
/// LAN role (`memory.dart`: evidence before claim); moreover it is
/// the proof that the peer is ON at this moment — the
/// post box (§8.2) then does not apply. `null` means: there is none
/// — on the first packet, or if the answered one was passed on or fetched from a
/// compartment and the sender address belongs to the third party.
typedef JoinSend = void Function(Uint8List packet, CardAddress? proof);

/// What the caller learns when something worth reporting happens.
typedef Report = void Function(String what);

class FirstContactError implements Exception {
  final String reason;
  FirstContactError(this.reason);
  @override
  String toString() => 'ErstkontaktFehler: $reason';
}

/// Alice's side: she has scanned or pasted the card.
class Join {
  final PostBox me;
  final Card card;
  final JoinSend send;
  final Report? report;

  /// What Alice writes about herself into the request (2) — name and greeting.
  ///
  /// Optional: if it stays null, the payload of the request is still the
  /// bare code, byte for byte as before the introduction. Fields that are too long
  /// throw NOT only when sending, but already when building the
  /// [Introduction] — and once more at the recipient, because only its
  /// check is a limit.
  final Introduction? introduction;

  final Uint8List _random;

  /// The one-time answer code of this join (proposal M): sealed in the
  /// request, registered with the own fixed neighbour (part M2).
  final Uint8List answerCode;
  Uint8List? _pairRandom;
  Address? _counterpart;
  CardAddress? _proof;
  Introduction? _counterpartIntroduction;
  bool _done = false;
  bool _declined = false;

  /// Does the contact stand on my side?
  bool get done => _done;

  /// Has the other side explicitly declined (answer with `0x00`)?
  bool get declined => _declined;

  /// Fires when the answer (3) is there — accepted ([done]) or
  /// declined ([declined]). The decision can fall hours after the request
  /// (§12.5): whoever waits for the join hooks in HERE, not
  /// on a deadline.
  void Function(Join b)? onCompletion;

  /// Bob's complete address — known only after packet (1).
  Address? get counterpart => _counterpart;

  /// The network address from which a packet of THIS join last came —
  /// the only EVIDENCE that this side has about the route to the peer
  /// (§6.2). `null` as long as nothing came, or if the last packet
  /// was passed on or fetched from a compartment.
  ///
  /// The caller remembers it with the freshly created contact as a proven
  /// route. Until S390 it took an address from the CARD for that — a
  /// claim at the place where `memory.dart` keeps evidence.
  CardAddress? get provenRoute => _proof;

  /// What Bob wrote about himself into the answer (3). Null as long as
  /// no answer is there or Bob sent nothing along.
  Introduction? get counterpartIntroduction => _counterpartIntroduction;

  /// `s_AB` from the acceptance (proposal M) — set only with [done].
  Uint8List? get pairRandom => _pairRandom;

  /// What the clock says about the scanned card — information, not a
  /// decision. This class does NOT reject an expired card:
  /// the grace period lies with the issuer (`invitation.dart`
  /// `kGracePeriodDays`), and only it knows whether it still listens. The caller
  /// can warn, ask or abort with this information.
  ExpiryState get cardsExpiry =>
      card.expiryStateAt(DateTime.now().millisecondsSinceEpoch ~/ 1000);

  Join({
    required this.me,
    required this.card,
    required this.send,
    this.report,
    this.introduction,
    Random? random,
  })  : _random = _randomBytes(16, random),
        answerCode = _randomBytes(16, random);

  /// Whether [packet] is the bundle (1) for THIS join — recognised by the 16
  /// random bytes that only this join has drawn. Changes nothing.
  ///
  /// A node with several identities possibly runs several
  /// joins at once; until S385 the FIRST unfinished one got every bundle,
  /// threw at the random value, and the second one's bundle was lost.
  bool expectedBundle(Uint8List packet) =>
      !_done &&
      _counterpart == null &&
      packet.length >= 1 + 16 + kBundleMinLength &&
      packet[0] == PacketKind.bundle.code &&
      bytesEqual(Uint8List.sublistView(packet, 1, 17), _random);

  /// Whether [packet] is the answer (3) to THIS join: sealed to [me]
  /// and signed by the counterpart from the bundle. Unseals
  /// once as a probe for that and changes nothing — the answer names neither
  /// code nor random value, the seal is the only feature.
  bool answerFits(Uint8List packet) {
    final g = _counterpart;
    if (_done || g == null || packet.isEmpty) return false;
    if (packet[0] != PacketKind.answer.code) return false;
    try {
      final (_, sender) = Envelope.unseal(
          envelope: Uint8List.sublistView(packet, 1), recipient: me);
      return sender.sameIdentity(g);
    } on Object {
      return false;
    }
  }

  /// Packet (0): request bundle. Contains NO identity.
  void start() {
    final neighbour = pairHook[me]?.ownNeighbour();
    final p = BytesBuilder()
      ..addByte(PacketKind.bundlePlea.code)
      ..add(_random);
    // §15.5 "The way back for the bundle": the reply code is registered
    // with the own fixed neighbour before this goes out (`node_join.dart`).
    bundlePleaWayBackWrite(p, answerCode, neighbour);
    report?.call('bundle requested${neighbour == null ? "" : " (way back via the own fixed neighbour)"}');
    send(p.toBytes(), null);
  }

  /// Feeds in an incoming packet. [origin] is the address from which
  /// it came — and only if it belongs to the PEER:
  /// for a passed-on (§8.1) or collected (§8.2) packet it belongs
  /// to the third party, and the caller then passes `null`.
  void receive(Uint8List packet, [CardAddress? origin]) {
    if (packet.isEmpty) throw FirstContactError('empty packet');
    final kind = PacketKind.fromCode(packet[0]);
    switch (kind) {
      case PacketKind.bundle:
        _bundleCame(packet, origin);
      case PacketKind.answer:
        _answerCame(packet, origin);
      default:
        throw FirstContactError('unexpected kind ${packet[0]}');
    }
  }

  void _bundleCame(Uint8List packet, CardAddress? origin) {
    if (packet.length < 1 + 16 + kBundleMinLength) {
      throw FirstContactError('bundle has ${packet.length} B, '
          'expected at least ${1 + 16 + kBundleMinLength}');
    }
    final randomBack = Uint8List.sublistView(packet, 1, 17);
    if (!bytesEqual(randomBack, _random)) {
      throw FirstContactError('Random value does not match — foreign answer');
    }
    // FIRST the signature (over THIS random value), THEN the identifier. The
    // identifier binds only the signing part; without a signature
    // a foreign KEM part could be slipped in (`bundle.dart`).
    final Address bob;
    try {
      bob = bundleCheck(_random, Uint8List.sublistView(packet, 17));
    } on EnvelopeBroken catch (e) {
      throw FirstContactError('Bundle without a carrying signature: ${e.reason}');
    }
    if (!card.matchesIdentifier(bob.identifier)) {
      throw FirstContactError(
          'Bundle does not match the fingerprint of the card');
    }
    _counterpart = bob;
    // Only NOW is the sender address evidence: the bundle carries
    // a signature over [_random] and matches the card's fingerprint.
    // Before, it would be the claim of an arbitrary sender.
    _proof = origin;
    report?.call('Bundle checked — it is the right one');

    // Packet (2): the request. Before the sealed envelope stands a
    // visible proof of work for Bob's code, with the difficulty from
    // his card — Bob checks it BEFORE he unseals.
    report?.call('computing the proof of work…');
    final (randomValue, counter) =
        ProofOfWork.generate(card.code, card.difficulty);

    // Payload: code, behind it — if there is one — the introduction.
    // Without it Bob would see nothing but a key address and would have to
    // decide without knowing who is asking.
    // Proposal M: behind it answer code and own fixed neighbour.
    final hook = pairHook[me];
    final content = requestContentBuild(
        card.code, answerCode, hook?.ownNeighbour(), introduction);
    final envelope = Envelope.seal(
      plaintext: content,
      recipient: _counterpart!,
      sender: me,
    );

    final header = Uint8List(proofOfWorkHeaderLength)
      ..setRange(0, ProofOfWork.randomValueLength, randomValue);
    ByteData.sublistView(header)
        .setUint64(ProofOfWork.randomValueLength, counter, Endian.little);
    final rest = Uint8List(header.length + envelope.length)
      ..setRange(0, header.length, header)
      ..setRange(header.length, header.length + envelope.length, envelope);

    report?.call('request sent (${envelope.length} B sealed)');
    final request = withKind(PacketKind.request, rest);
    send(request, _proof);
    _underCode(request);
  }

  /// Proposal M: additionally under the first-contact code to the card's
  /// neighbour — the route that carries behind NAT (sending: part M2).
  void _underCode(Uint8List packet) {
    final n = card.neighbourAddress;
    if (n != null) {
      pairHook[me]?.underCodeSend(firstContactCode(card.code), n, packet);
    }
  }

  void _answerCame(Uint8List packet, CardAddress? origin) {
    final (content, sender) = Envelope.unseal(
      envelope: Uint8List.sublistView(packet, 1),
      recipient: me,
    );
    if (_counterpart == null || !sender.sameIdentity(_counterpart!)) {
      throw FirstContactError('Answer comes from someone else');
    }
    // The signed answer is the best source for Bob's address — if
    // he rotated between bundle and answer, the newer one applies.
    if (Address.adopt(_counterpart!, sender)) _counterpart = sender;
    // The seal is checked and the sender is the peer — the
    // address from which the answer came is thus evidence (§6.2). It
    // replaces the bundle's evidence: if Bob has changed network in the
    // meantime, the newer one applies.
    if (origin != null) _proof = origin;
    if (content.isEmpty || content[0] != 1) {
      report?.call('declined');
      _declined = true;
      onCompletion?.call(this);
      return;
    }
    // Behind the decision byte stands Bob's introduction — the same
    // fields and the same limits as in the request. A field that is too long
    // throws and does NOT let the contact come about: the limit applies
    // even when the other side is the inviting one.
    // Proposal M: without s_AB it is no acceptance — throws, no contact.
    final acceptance = acceptanceContentRead(content);
    _counterpartIntroduction = acceptance.self;
    _pairRandom = acceptance.sAB;
    _done = true;
    final receipt = Envelope.seal(
      plaintext: Uint8List.fromList([1]),
      recipient: _counterpart!,
      sender: me,
    );
    report?.call('contact established');
    final q = withKind(PacketKind.receipt, receipt);
    send(q, _proof);
    _underCode(q);
    onCompletion?.call(this);
  }
}

/// Puts the kind byte in front of a finished payload. Needed by both sides,
/// therefore not private.
Uint8List withKind(PacketKind s, Uint8List rest) {
  final b = Uint8List(1 + rest.length);
  b[0] = s.code;
  b.setRange(1, b.length, rest);
  return b;
}

Uint8List _randomBytes(int n, Random? r) {
  final q = r ?? Random.secure();
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = q.nextInt(256);
  }
  return b;
}

/// Byte-wise comparison. Needed by both sides, therefore not private.
bool bytesEqual(Uint8List x, Uint8List y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
