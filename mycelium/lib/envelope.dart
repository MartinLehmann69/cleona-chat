import 'dart:math' show max;
import 'dart:typed_data';

import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/identity/kem_generation.dart'
    show kKemRotationInterval;
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/address.dart';

/// [Address] has stood in `address.dart` since S385 (E1) and is
/// re-exported from here — every existing caller still imports
/// only `package:mycelium/envelope.dart`.
export 'package:mycelium/address.dart';

/// The envelope.
///
/// Seal and unseal — nothing more. NO crypto is
/// written here: every computation of this file goes to `PerMessageKem`,
/// `SodiumFFI` or `OqsFFI` in `lib/core/crypto/`. What this file
/// contributes is exclusively packing and unpacking the bytes.
///
/// No state between two envelopes. Whoever seals the same content twice
/// gets two different envelopes, and both can be opened
/// independently of each other.

/// A pair: the [Address] to the outside, the secret parts to the inside.
///
/// The secret part does not leave this class. Whoever seals passes the
/// whole post box in — the signature carries the own address along,
/// and the public ML-DSA part cannot be derived from the secret one.
/// The parts of a KEM generation, as the app creates them on rotation.
typedef KemParts = ({
  Uint8List x25519Pk,
  Uint8List x25519Sk,
  Uint8List mlKemPk,
  Uint8List mlKemSk,
});

/// The secret KEM parts of the previous generation.
typedef PreviousParts = ({Uint8List x25519Sk, Uint8List mlKemSk});

class PostBox {
  /// Changeable ONLY via [rotate], and in the same object: identity,
  /// messages, amendments and group hold this post box `final` —
  /// a new object would only see one layer.
  Address get address => _address;
  Address _address;
  final Uint8List _ed25519Sk;
  Uint8List _x25519Sk;
  Uint8List _mlKemSk;
  final Uint8List _mlDsaSk;
  PreviousParts? _previous;

  PostBox._(this._address, this._ed25519Sk, this._x25519Sk, this._mlKemSk,
      this._mlDsaSk, [this._previous]);

  /// Routine KEM rotation (V4.2 §4.5.4): [fresh] becomes the current
  /// generation, the previous one becomes the ONE previous (an older previous one falls).
  /// The keys are created by the caller (the app, W1) — mycelium draws
  /// no second identity. `state = max(now, before + 1)`: even with a
  /// clock set back it rises (S385-E1-WIDERLEGUNG 4a).
  void rotate(KemParts fresh, {DateTime? now}) {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    _previous = (x25519Sk: _x25519Sk, mlKemSk: _mlKemSk);
    _x25519Sk = fresh.x25519Sk;
    _mlKemSk = fresh.mlKemSk;
    _address = Address(
      ed25519Pk: _address.ed25519Pk,
      mlDsaPk: _address.mlDsaPk,
      x25519Pk: fresh.x25519Pk,
      mlKemPk: fresh.mlKemPk,
      state: max(t, _address.state + 1),
    );
  }

  /// The previous generation — as long as `now < state + 7 d`
  /// ([kKemRotationInterval], the same number as the app). After that it is
  /// discarded HERE, on access: no timer, and the next save
  /// no longer writes it.
  PreviousParts? _previousInDeadline() {
    final limit = _address.state + kKemRotationInterval.inMilliseconds;
    if (DateTime.now().millisecondsSinceEpoch >= limit) _previous = null;
    return _previous;
  }

  /// At founding X25519 is derived from Ed25519 — exactly as the
  /// app does (`identity_context.dart`, founding). Before the first rotation
  /// both sides are thus byte-identical; only a rotation sets an
  /// independent key.
  static PostBox _reasons(
    ({Uint8List publicKey, Uint8List secretKey}) ed,
    ({Uint8List publicKey, Uint8List secretKey}) kem,
    ({Uint8List publicKey, Uint8List secretKey}) dsa,
    DateTime? now,
  ) {
    final sodium = SodiumFFI();
    return PostBox._(
      Address(
        ed25519Pk: ed.publicKey,
        mlDsaPk: dsa.publicKey,
        x25519Pk: sodium.ed25519PkToX25519(ed.publicKey),
        mlKemPk: kem.publicKey,
        state: (now ?? DateTime.now()).millisecondsSinceEpoch,
      ),
      ed.secretKey,
      sodium.ed25519SkToX25519(ed.secretKey),
      kem.secretKey,
      dsa.secretKey,
    );
  }

  /// Creates a fresh pair. No random source of its own. [now] is the
  /// `state` of the first generation (default: the clock).
  static PostBox fresh({DateTime? now}) {
    final oqs = OqsFFI()..init();
    return _reasons(SodiumFFI().generateEd25519KeyPair(), oqs.mlKemKeypair(),
        oqs.mlDsaKeypair(), now);
  }

  /// Derives a post box from a root key.
  ///
  /// The KEYS are deterministic: the same root key and
  /// the same [index] yield the same identity ([Address.identifier]).
  /// Not deterministic is the `state`: it is [now], never 0 — a
  /// restored identity with state 0 would be older for every contact
  /// than its remembered copy and would never be adopted
  /// (S385-E1-WIDERLEGUNG 4b). TWO things depend on this, which are the same
  /// procedure:
  ///
  /// * **Recovery.** If a device is lost, the
  ///   word sequence brings back the root key and with it every identity.
  /// * **Several identities.** Index 0, 1, 2 are different
  ///   identities from the same word sequence — not linkable
  ///   with each other.
  static PostBox outRoot(Uint8List rootKey, int index,
      {DateTime? now}) {
    // Without this call the first derivation throws — precisely on the
    // first recovery.
    OqsFFI().init();
    return _reasons(
      HdWallet.deriveEd25519(rootKey, index),
      HdWallet.deriveMlKem(rootKey, index),
      HdWallet.deriveMlDsa(rootKey, index),
      now,
    );
  }

  /// Rebuilds a post box from stored parts.
  ///
  /// Without this path an identity survives no restart: the
  /// secret parts are file-private, and Dart knows privacy per FILE.
  /// That is a language limit, and it is opened here by name.
  static PostBox outSplit({
    required Address address,
    required Uint8List ed25519Sk,
    required Uint8List x25519Sk,
    required Uint8List mlKemSk,
    required Uint8List mlDsaSk,
    PreviousParts? previous,
  }) =>
      PostBox._(address, ed25519Sk, x25519Sk, mlKemSk, mlDsaSk, previous);

  /// Hands out the secret parts — exclusively to store them
  /// encrypted. Whoever uses the result otherwise gives away the
  /// identity. [previous] only as long as it is within the grace period.
  ({
    Uint8List ed25519Sk,
    Uint8List x25519Sk,
    Uint8List mlKemSk,
    Uint8List mlDsaSk,
    PreviousParts? previous,
  }) secretParts() => (
        ed25519Sk: _ed25519Sk,
        x25519Sk: _x25519Sk,
        mlKemSk: _mlKemSk,
        mlDsaSk: _mlDsaSk,
        previous: _previousInDeadline(),
      );

  /// [sign]: hybrid (Ed25519 AND ML-DSA-65), for packets that travel signed
  /// outside an envelope (bundle of first contact).
  /// [signEd25519]: only Ed25519 (64 B), for proofs to a holder
  /// (S385 F2). Neither hands out anything secret.
  ({Uint8List ed, Uint8List dsa}) sign(Uint8List data) => (
        ed: signEd25519(data),
        dsa: (OqsFFI()..init()).mlDsaSign(data, _mlDsaSk),
      );
  Uint8List signEd25519(Uint8List data) =>
      SodiumFFI().signEd25519(data, _ed25519Sk);
}

/// An envelope that does not open: wrong header, too short, bent
/// bytes, wrong recipient or a signature that does not hold.
class EnvelopeBroken implements Exception {
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

  /// Inside, before the plaintext: sender address 3208 + length of the
  /// ML-DSA signature 2 + Ed25519 signature 64 = 3274 B, plus the
  /// ML-DSA signature itself (up to 3309 B).
  static const int _insideHeader = Address.length + 2 + _edSigLength;

  /// Closes [plaintext] for [recipient], signed by [sender].
  ///
  /// The sender address and both signatures lie INSIDE the
  /// seal. Whoever sees the envelope on the wire therefore does not see
  /// who wrote it.
  ///
  /// What is signed is header code, sender address, recipient address
  /// and plaintext. The recipient address belongs in it: otherwise
  /// a recipient could re-close the same content, pass it on to a third party,
  /// and the first sender's signature would still hold there.
  static Uint8List seal({
    required Uint8List plaintext,
    required Address recipient,
    required PostBox sender,
  }) {
    final signed = _charsData(
      sender: sender.address,
      recipient: recipient,
      plaintext: plaintext,
    );
    final sig = sender.sign(signed);

    final inside = Uint8List(_insideHeader + sig.dsa.length + plaintext.length);
    var i = 0;
    inside.setRange(i, i += Address.length, sender.address.toBytes());
    ByteData.sublistView(inside).setUint16(i, sig.dsa.length, Endian.big);
    i += 2;
    inside.setRange(i, i += _edSigLength, sig.ed);
    inside.setRange(i, i += sig.dsa.length, sig.dsa);
    inside.setRange(i, i += plaintext.length, plaintext);

    final (header, ciphertext) = PerMessageKem.encrypt(
      plaintext: inside,
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
  /// exactly this recipient, and the returned address has
  /// signed it. The address is complete — one can answer it immediately
  /// without looking it up elsewhere.
  static (Uint8List plaintext, Address sender) unseal({
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

    Uint8List? open(Uint8List x25519Sk, Uint8List mlKemSk) {
      try {
        return PerMessageKem.decrypt(
          kemHeader: KemHeader(
            ephemeralX25519Pk: ephPk,
            mlKemCiphertext: kemCt,
            aesNonce: nonce,
            version: version,
          ),
          ciphertext: ciphertext,
          ourX25519Sk: x25519Sk,
          ourMlKemSk: mlKemSk,
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
    final previous = recipient._previousInDeadline();
    final inside = open(recipient._x25519Sk, recipient._mlKemSk) ??
        (previous == null ? null : open(previous.x25519Sk, previous.mlKemSk)) ??
        (throw EnvelopeBroken('does not open'));

    if (inside.length < _insideHeader) {
      throw EnvelopeBroken('inside too short: ${inside.length} B');
    }
    var p = 0;
    final sender = Address.outBytes(_cut(inside, p, p += Address.length));
    final dsaSigLength = ByteData.sublistView(inside).getUint16(p, Endian.big);
    p += 2;
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

    return (plaintext, sender);
  }

  /// What is signed: header code, the complete sender address, the
  /// recipient's IDENTIFIER, plaintext. Both signatures — Ed25519 and
  /// ML-DSA-65 — go over exactly these bytes.
  ///
  /// Identifier instead of recipient address (S385, E1): the sender seals
  /// against ITS copy, the recipient checks with ITS current address.
  /// If the recipient has rotated (or restored from the word sequence with a new `state`),
  /// these would be different bytes, and every message
  /// would fail at the signature — the previous generation would be without effect.
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

/// Real copy of a view. `sublistView` shares the buffer — that
/// would be wrong here, because the views outlive the envelope.
Uint8List _cut(Uint8List b, int from, int until) =>
    Uint8List.fromList(Uint8List.sublistView(b, from, until));
