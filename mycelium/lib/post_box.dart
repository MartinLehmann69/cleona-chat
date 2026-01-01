import 'dart:math' show max;
import 'dart:typed_data';

import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/identity/kem_generation.dart'
    show kKemRotationInterval;
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/address.dart';
import 'package:mycelium/anchor_book.dart';

/// The parts of a KEM generation, as the app creates them on rotation.
typedef KemParts = ({
  Uint8List x25519Pk,
  Uint8List x25519Sk,
  Uint8List mlKemPk,
  Uint8List mlKemSk,
});

/// The secret KEM parts of the previous generation.
typedef PreviousParts = ({Uint8List x25519Sk, Uint8List mlKemSk});

/// The day-key seed of the signing key an Emergency Key Rotation replaced,
/// and until when (ms) the identity still asks under it (§8.2: "After such
/// a rotation the identity asks under its previous day keys for 7 more
/// days", E-A6).
typedef PreviousDaySeed = ({Uint8List seed, int until});

/// The post box — an identity's key pair: the [Address] to the outside, the
/// secret parts to the inside.
///
/// Stood in `envelope.dart` until S398; moved out when the Emergency Key
/// Rotation (proposal A, D-33) gave it the founding secret key, the book and
/// the own chain, and `envelope.dart` would have passed its line budget. The
/// envelope reads the secret KEM parts through [kemOpeners] — the one door
/// a second file needs, named instead of widened.
///
/// The secret part does not leave this class. Whoever seals passes the
/// whole post box in — the signature carries the own address along,
/// and the public ML-DSA part cannot be derived from the secret one.
class PostBox {
  /// Changeable ONLY via [rotate], and in the same object: identity,
  /// messages, amendments and group hold this post box `final` —
  /// a new object would only see one layer.
  Address get address => _address;
  Address _address;
  Uint8List _ed25519Sk;
  Uint8List _x25519Sk;
  Uint8List _mlKemSk;
  Uint8List _mlDsaSk;
  PreviousParts? _previous;

  /// The founding Ed25519 secret key, `null` while it IS [_ed25519Sk] — an
  /// identity that never rotated. `K_AB` hangs on it (§4.3).
  Uint8List? _foundingEd25519Sk;

  PreviousDaySeed? _previousDaySeed;

  /// The previous day-key seed while its 7 days run — see [PreviousDaySeed].
  PreviousDaySeed? get previousDaySeed {
    final d = _previousDaySeed;
    if (d != null && DateTime.now().millisecondsSinceEpoch >= d.until) {
      _previousDaySeed = null;
    }
    return _previousDaySeed;
  }

  /// Takes over a previous day-key seed kept in memory, when the post box
  /// comes from a caller that does not keep it (the app, `mailbox_start.dart`).
  void previousDaySeedKeep(PreviousDaySeed? d) => _previousDaySeed = d;

  /// The seed the day keys derive from: the first 32 B of the CURRENT
  /// Ed25519 secret key (§8.2, never the founding one) — `pair.dart`.
  Uint8List get daySeed => Uint8List.sublistView(_ed25519Sk, 0, 32);

  /// What this identity holds about the identifiers it knows — the prior
  /// state of every acceptance (`anchor_book.dart`). Set by its mailbox;
  /// without one there is none.
  AnchorBook book = AnchorBook.none;

  PostBox._(this._address, this._ed25519Sk, this._x25519Sk, this._mlKemSk,
      this._mlDsaSk,
      [this._previous, this._foundingEd25519Sk]) {
    final a = _address;
    if (!a.rotated) return;
    // A rotated post box must be able to prove itself and to form its
    // pairs: its chain ends at its keys and starts at its identifier, and
    // the founding secret key belongs to the chain's first key.
    final f = _foundingEd25519Sk;
    final founding = a.chain.founding;
    if (f == null ||
        founding == null ||
        !a.chain.keys.last.same(a.signingKeys) ||
        !_equal(Uint8List.sublistView(f, 32), founding.ed25519Pk)) {
      throw ArgumentError('rotated post box without its chain or without '
          'the founding secret key of that chain');
    }
  }

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
    _address = _address.withKem(
        fresh.x25519Pk, fresh.mlKemPk, max(t, _address.state + 1));
  }

  /// Emergency Key Rotation (V4.2 §4.5.4, D-33): ALL four keys of [fresh]
  /// become this post box's, in the same object (see [address]). The keys and
  /// the chain are made by the caller — the app, which appended the hybrid
  /// link (`IdentityContext.rotateIdentityFull`); mycelium draws none.
  /// [fresh] must be the SAME identity, rotated one link further: its chain
  /// passes through the current keys and ends at its own.
  ///
  /// What stays: the identifier, the founding secret key, the book. What
  /// becomes previous: the current KEM generation (§4.5.4, 7 d) and the
  /// current day-key seed (§8.2, asked 7 more days, E-A6).
  void signingAdopt(PostBox fresh, {DateTime? now}) {
    final a = fresh._address;
    if (!a.sameIdentity(_address) ||
        !a.rotated ||
        !a.chain.passesThrough(_address.signingKeys) ||
        a.sameKeys(_address) ||
        !a.chain.holds(a.identifier, a.signingKeys)) {
      throw ArgumentError('not this identity one rotation further');
    }
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    _previous = (x25519Sk: _x25519Sk, mlKemSk: _mlKemSk);
    _previousDaySeed = (
      seed: Uint8List.fromList(daySeed),
      until: t + kKemRotationInterval.inMilliseconds,
    );
    _foundingEd25519Sk = fresh.secretParts().foundingEd25519Sk;
    _ed25519Sk = fresh._ed25519Sk;
    _mlDsaSk = fresh._mlDsaSk;
    _x25519Sk = fresh._x25519Sk;
    _mlKemSk = fresh._mlKemSk;
    _address = Address(
        identifier: a.identifier,
        ed25519Pk: a.ed25519Pk,
        mlDsaPk: a.mlDsaPk,
        x25519Pk: a.x25519Pk,
        mlKemPk: a.mlKemPk,
        state: max(t, max(a.state, _address.state + 1)),
        chain: a.chain);
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

  /// The secret KEM parts to try on an envelope, in order: the current
  /// generation, then the previous one within its grace period. Only for
  /// `envelope.dart` — see the class header.
  List<PreviousParts> get kemOpeners {
    final previous = _previousInDeadline();
    return [
      (x25519Sk: _x25519Sk, mlKemSk: _mlKemSk),
      if (previous != null) previous,
    ];
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
  ///   word sequence brings back the root key and with it every identity —
  ///   the FOUNDING keys: after an Emergency Key Rotation the words alone
  ///   restore superseded keys, the recovery bundle the current ones
  ///   (§4.5.4, E-A12).
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
  /// [foundingEd25519Sk] is required exactly for a rotated [address] (its
  /// chain rides on the address).
  static PostBox outSplit({
    required Address address,
    required Uint8List ed25519Sk,
    required Uint8List x25519Sk,
    required Uint8List mlKemSk,
    required Uint8List mlDsaSk,
    PreviousParts? previous,
    Uint8List? foundingEd25519Sk,
    PreviousDaySeed? previousDaySeed,
  }) =>
      PostBox._(address, ed25519Sk, x25519Sk, mlKemSk, mlDsaSk, previous,
          address.rotated ? foundingEd25519Sk : null)
        .._previousDaySeed = previousDaySeed;

  /// This post box with [kem] as its sealing keys — what opens a request
  /// sealed from a `cleona:2:` line (the invitation's own keys, R-b). The
  /// signing part, the chain and the book are this identity's.
  PostBox withKem(KemParts kem) => PostBox._(
      _address.withKem(kem.x25519Pk, kem.mlKemPk, _address.state),
      _ed25519Sk,
      kem.x25519Sk,
      kem.mlKemSk,
      _mlDsaSk,
      null,
      _foundingEd25519Sk)
    ..book = book
    .._previousDaySeed = _previousDaySeed;

  /// Hands out the secret parts — exclusively to store them
  /// encrypted, and the founding one to form `K_AB` (`pair.dart`). Whoever
  /// uses the result otherwise gives away the identity. [previous] only as
  /// long as it is within the grace period.
  ({
    Uint8List ed25519Sk,
    Uint8List x25519Sk,
    Uint8List mlKemSk,
    Uint8List mlDsaSk,
    PreviousParts? previous,
    Uint8List foundingEd25519Sk,
  }) secretParts() => (
        ed25519Sk: _ed25519Sk,
        x25519Sk: _x25519Sk,
        mlKemSk: _mlKemSk,
        mlDsaSk: _mlDsaSk,
        previous: _previousInDeadline(),
        foundingEd25519Sk: _foundingEd25519Sk ?? _ed25519Sk,
      );

  /// Does an envelope to [recipient] carry the own chain? Exactly while the
  /// identity has rotated and [recipient] has not acknowledged an envelope
  /// that carried it (§4.5.4, E-A7). For a stranger: always.
  bool carriesChainTo(Address recipient) =>
      !_address.chain.isEmpty && !book.chainAcked(recipient.identifier);

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

bool _equal(Uint8List x, Uint8List y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
