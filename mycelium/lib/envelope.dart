import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/identity/rotation_chain.dart';
import 'package:mycelium/address.dart';
import 'package:mycelium/anchor_book.dart';
import 'package:mycelium/envelope_tag.dart';
import 'package:mycelium/post_box.dart';

/// [Address] has stood in `address.dart` since S385 (E1), [PostBox] in
/// `post_box.dart` since S398 (A); both are re-exported from here — every
/// existing caller still imports only `package:mycelium/envelope.dart`.
export 'package:mycelium/address.dart';
export 'package:mycelium/anchor_book.dart';
export 'package:mycelium/post_box.dart';

/// The envelope.
///
/// Seal and unseal — nothing more. NO crypto is
/// written here: every computation of this file goes to `PerMessageKem`,
/// `SodiumFFI`, `OqsFFI` and `RotationChain` in `lib/core/`. What this file
/// contributes is exclusively packing and unpacking the bytes — and the ONE
/// point where a sender is accepted (`anchor_book.dart`, [senderAccept]).
///
/// No state between two envelopes. Whoever seals the same content twice
/// gets two different envelopes, and both can be opened
/// independently of each other.

/// An envelope that does not open: wrong header, too short, bent
/// bytes, wrong recipient or a signature that does not hold.
class EnvelopeBroken implements Exception {
  /// The reason when no held KEM generation opens it — the one failure a
  /// later generation can cure (parking, D-40, `parked.dart`).
  static const String kemClosed = 'does not open';

  final String reason;
  EnvelopeBroken(this.reason);
  @override
  String toString() => 'UmschlagKaputt: $reason';
}

/// Seal and unseal.
class Envelope {
  Envelope._();

  /// Four bytes at the start. Not meant as protection, but so that a
  /// packet that is no envelope at all stands out immediately instead of occupying expensive
  /// crypto.
  static final Uint8List _headerCode =
      Uint8List.fromList(<int>[0x4d, 0x59, 0x5a, 0x31]); // "MYZ1"

  static const int _edSigLength = 64;

  /// Outside, before the closed part: header 4 + version 1 + ephemeral
  /// X25519 32 + ML-KEM ciphertext 1088 + AEAD nonce 12 = 1137 B.
  static const int _outsideHeader =
      4 + 1 + 32 + OqsFFI.mlKemCiphertextLength + 12;

  /// Inside, before the plaintext — signed form: sender address 3240 + chain
  /// (at least its count byte, 1) + length of the ML-DSA signature 2 +
  /// Ed25519 signature 64 = 3307 B, plus the chain's links (5357 B each) and
  /// the ML-DSA signature itself (up to 3309 B). Tagged form (§4.4.3): the
  /// mark [kEnvelopeTagMark] 2 and the tag 32 in place of the length and both
  /// signatures = 3275 B, the shortest inside there is.
  static const int _insideHeaderTagged =
      Address.length + 1 + 2 + kEnvelopeTagLength;

  /// Closes [plaintext] for [recipient], signed by [sender].
  ///
  /// The sender address, its rotation chain and both signatures lie INSIDE
  /// the seal (§4.5.4 "It travels inside the seal"). Whoever sees the
  /// envelope on the wire therefore does not see who wrote it.
  ///
  /// What is signed is header code, sender address, recipient identifier
  /// and plaintext. The recipient belongs in it: otherwise
  /// a recipient could re-close the same content, pass it on to a third party,
  /// and the first sender's signature would still hold there. The chain is
  /// NOT signed: it proves itself, link by link, and a swapped chain that
  /// still holds proves the same.
  ///
  /// The chain rides along while [PostBox.carriesChainTo] says so — the
  /// sender has rotated and [recipient] has not acknowledged one yet (E-A7).
  ///
  /// [pairTag] (a message or a group leg, §4.4.3): where [recipient] is a
  /// pair that has shown it reads the tagged form, the two signatures give
  /// way to the pair tag (`envelope_tag.dart`) — length field
  /// [kEnvelopeTagMark], then 32 B. Everything else stays signed: first
  /// contact, twin sync, a pair that showed nothing, a post box with no pairs.
  static Uint8List seal({
    required Uint8List plaintext,
    required Address recipient,
    required PostBox sender,
    bool pairTag = false,
  }) {
    final bound = _charsData(
      sender: sender.address,
      recipient: recipient,
      plaintext: plaintext,
    );
    final kAB = pairTag ? envelopePairsOf(sender)?.tagKeyTo(recipient) : null;
    final chain = sender.carriesChainTo(recipient)
        ? sender.address.chain.toWire()
        : Uint8List(1);

    final inside = BytesBuilder()
      ..add(sender.address.toBytes())
      ..add(chain);
    if (kAB != null) {
      inside
        ..add(_u16(kEnvelopeTagMark))
        ..add(envelopeTag(kAB, bound));
    } else {
      final sig = sender.sign(bound);
      inside
        ..add(_u16(sig.dsa.length))
        ..add(sig.ed)
        ..add(sig.dsa);
    }
    inside.add(plaintext);

    final (header, ciphertext) = PerMessageKem.encrypt(
      plaintext: inside.toBytes(),
      recipientX25519Pk: recipient.x25519Pk,
      recipientMlKemPk: recipient.mlKemPk,
    );

    final outside = Uint8List(_outsideHeader + ciphertext.length);
    var j = 0;
    outside.setRange(j, j += 4, _headerCode);
    outside[j] = header.version;
    j += 1;
    outside.setRange(j, j += 32, header.ephemeralX25519Pk);
    outside.setRange(j, j += OqsFFI.mlKemCiphertextLength, header.mlKemCiphertext);
    outside.setRange(j, j += 12, header.aesNonce);
    outside.setRange(j, j += ciphertext.length, ciphertext);
    return outside;
  }

  /// Opens [envelope] with the secret part of [recipient] and returns the
  /// plaintext together with the verified sender address.
  ///
  /// Throws [EnvelopeBroken] as soon as anything does not hold. A result
  /// from this method means: the plaintext is unchanged, it was addressed to
  /// exactly this recipient, the returned address has signed it, and its
  /// keys are the ones [recipient] holds for its identifier or a chain
  /// connects them (`anchor_book.dart`, [senderAccept] — superseded keys and
  /// a fork end here, before any acknowledgement). The address is complete —
  /// one can answer it immediately without looking it up elsewhere.
  ///
  /// A tagged envelope (§4.4.3) holds when its tag holds under the `K_AB` of
  /// the pair the asserted sender address names — the sender the tag knows
  /// is the one the application gets (the implementation note of §4.4.3).
  static (Uint8List plaintext, Address sender) unseal({
    required Uint8List envelope,
    required PostBox recipient,
  }) {
    final o = open(envelope: envelope, recipient: recipient);
    return (o.plaintext, o.sender);
  }

  /// [unseal], and whether the envelope was the tagged form.
  static ({Uint8List plaintext, Address sender, bool tagged}) open({
    required Uint8List envelope,
    required PostBox recipient,
  }) {
    final sodium = SodiumFFI();
    final oqs = OqsFFI()..init();

    if (envelope.length <= _outsideHeader) {
      throw EnvelopeBroken('too short: ${envelope.length} B');
    }
    for (var k = 0; k < 4; k++) {
      if (envelope[k] != _headerCode[k]) {
        throw EnvelopeBroken('not an envelope');
      }
    }

    var i = 4;
    final version = envelope[i];
    i += 1;
    final ephPk = _cut(envelope, i, i += 32);
    final kemCt = _cut(envelope, i, i += OqsFFI.mlKemCiphertextLength);
    final nonce = _cut(envelope, i, i += 12);
    final ciphertext = _cut(envelope, i, envelope.length);

    Uint8List? open(PreviousParts parts) {
      try {
        return PerMessageKem.decrypt(
          kemHeader: KemHeader(
            ephemeralX25519Pk: ephPk,
            mlKemCiphertext: kemCt,
            aesNonce: nonce,
            version: version,
          ),
          ciphertext: ciphertext,
          ourX25519Sk: parts.x25519Sk,
          ourMlKemSk: parts.mlKemSk,
        );
      } catch (_) {
        return null;
      }
    }

    // First the current generation, then — only within the grace period — the previous one.
    // The fallback depends on the failure of the WHOLE attempt, not on a
    // single event (§4.5.4). One error text for all cases: wrong
    // recipient, bent bytes, unknown version, expired
    // generation — a distinguishable one would be an oracle, also for whether
    // a previous generation exists.
    Uint8List? inside;
    for (final parts in recipient.kemOpeners) {
      inside ??= open(parts);
    }
    if (inside == null) throw EnvelopeBroken(EnvelopeBroken.kemClosed);

    if (inside.length < _insideHeaderTagged) {
      throw EnvelopeBroken('inside too short: ${inside.length} B');
    }
    var p = 0;
    final addressBytes = _cut(inside, p, p += Address.length);
    final RotationChain chain;
    try {
      final n = RotationChain.wireLengthAt(inside, p);
      final keys = ChainKeys(Uint8List.sublistView(addressBytes, 32, 64),
          Uint8List.sublistView(
              addressBytes, 64, 64 + OqsFFI.mlDsaPublicKeyLength));
      chain = RotationChain.fromWire(_cut(inside, p, p += n), keys);
    } on RotationChainError catch (e) {
      throw EnvelopeBroken('chain: ${e.reason}');
    }
    // `proven`: [senderAccept] below decides — with the book it may spare
    // the chain check for keys it already holds.
    final sender = Address.outBytes(addressBytes, chain: chain, proven: true);
    if (p + 2 + kEnvelopeTagLength > inside.length) {
      throw EnvelopeBroken('inside too short: ${inside.length} B');
    }
    final dsaSigLength = ByteData.sublistView(inside).getUint16(p, Endian.big);
    p += 2;
    if (dsaSigLength == kEnvelopeTagMark) {
      final tag = _cut(inside, p, p += kEnvelopeTagLength);
      final plaintext = _cut(inside, p, inside.length);
      final pairs = envelopePairsOf(recipient);
      final keys = pairs?.tagKeysOf(sender) ?? const <Uint8List>[];
      if (pairs == null || keys.isEmpty) {
        throw EnvelopeBroken('tagged envelope from no pair');
      }
      final bound = _charsData(
          sender: sender, recipient: recipient.address, plaintext: plaintext);
      if (!keys.any((kAB) => envelopeTagHolds(kAB, bound, tag))) {
        throw EnvelopeBroken('pair tag does not hold');
      }
      final accepted = senderAccept(recipient.book, sender);
      pairs.tagShown(accepted);
      return (plaintext: plaintext, sender: accepted, tagged: true);
    }
    if (p + _edSigLength > inside.length) {
      throw EnvelopeBroken('inside too short: ${inside.length} B');
    }
    final edSig = _cut(inside, p, p += _edSigLength);
    if (dsaSigLength > OqsFFI.mlDsaSignatureLength ||
        p + dsaSigLength > inside.length) {
      throw EnvelopeBroken('signature does not fit into the envelope');
    }
    final dsaSig = _cut(inside, p, p += dsaSigLength);
    final plaintext = _cut(inside, p, inside.length);

    final signed = _charsData(
      sender: sender,
      recipient: recipient.address,
      plaintext: plaintext,
    );

    if (!sodium.verifyEd25519(signed, edSig, sender.ed25519Pk)) {
      throw EnvelopeBroken('Ed25519 signature does not verify');
    }
    if (!oqs.mlDsaVerify(signed, dsaSig, sender.mlDsaPk)) {
      throw EnvelopeBroken('ML-DSA signature does not verify');
    }

    return (
      plaintext: plaintext,
      sender: senderAccept(recipient.book, sender),
      tagged: false
    );
  }

  /// What is signed: header code, the complete sender address, the
  /// recipient's IDENTIFIER, plaintext. Both signatures — Ed25519 and
  /// ML-DSA-65 — go over exactly these bytes, and so does the pair tag of
  /// the tagged form (`envelope_tag.dart`).
  ///
  /// Identifier instead of recipient address (S385, E1): the sender seals
  /// against ITS copy, the recipient checks with ITS current address.
  /// If the recipient has rotated (or restored from the word sequence with a new `state`),
  /// these would be different bytes, and every message
  /// would fail at the signature — the previous generation would be without effect.
  /// Since D-33 the identifier also survives a change of the recipient's
  /// signing keys, so a sender that has not yet adopted them still seals
  /// something the recipient can check.
  /// What the place is there for stays bound: a third party has a different
  /// identifier, repackaging to it does not hold. The KEM part was bound by the full
  /// address only incidentally; since E1 that is done by the signed bundle of
  /// first contact (`bundle.dart`) — only THEREFORE is this change
  /// sustainable (S385-E1-WIDERLEGUNG 3).
  static Uint8List _charsData({
    required Address sender,
    required Address recipient,
    required Uint8List plaintext,
  }) {
    final b = Uint8List(4 + Address.length + 32 + plaintext.length);
    var i = 0;
    b.setRange(i, i += 4, _headerCode);
    b.setRange(i, i += Address.length, sender.toBytes());
    b.setRange(i, i += 32, recipient.identifier);
    b.setRange(i, i += plaintext.length, plaintext);
    return b;
  }
}

Uint8List _u16(int x) =>
    (ByteData(2)..setUint16(0, x, Endian.big)).buffer.asUint8List();

/// Real copy of a view. `sublistView` shares the buffer — that
/// would be wrong here, because the views outlive the envelope.
Uint8List _cut(Uint8List b, int from, int until) =>
    Uint8List.fromList(Uint8List.sublistView(b, from, until));
