import 'dart:convert';
import 'dart:typed_data';

import '../crypto/oqs_ffi.dart';
import '../crypto/sodium_ffi.dart';

/// WHICH prekey was used — as a HASH, not as a counter (§4.6,
/// version B, approved by the owner on 30.08.2026).
///
///     sel = SHA-256(pk_n ‖ eph_pk), truncated to the first 4 B
///
/// `pk_n` is the public X25519 part against which sealing happens;
/// `eph_pk` the ephemeral public key of THIS cell.
///
/// ── WHY THIS FIELD MUST EXIST AT ALL ───────────────────────
///
/// The receiver holds a SUPPLY of one-time secrets and must pick the right
/// one per cell BEFORE it computes `dh = X25519(sk_n, eph_pk)`.
/// Without information it would only be left to try them all — one
/// scalar multiplication per candidate, and that for EVERY incoming
/// cell, including every cover cell that is not for it at all. §4.6
/// excludes that: „the receiver must be able to **name** that prekey
/// without trial-unsealing the whole batch."
///
/// It cannot be derived. Until 29.08.2026 §4.6 provided that the
/// index follows from the pair's tag counter — „no extra field on the
/// wire". This counter exists on the V4.1 line in NEITHER of the two
/// modes: Speed has no tag at all (§4.3: „in Speed-Mode there is
/// **no field tag** — the cell is addressed by the onion path"), and the
/// built Secure mark `secureTag(kAb, epoch, family, direction)`
/// (`secure_mode.dart:79`) hangs on the 24-h epoch, on the family and
/// on the direction, on no message number. The rule was
/// unbuildable, not merely unbuilt; §4.6 was therefore relaxed on 29.08. (S351,
/// B2).
///
/// ── WHY NO LONGER THE COUNTER (S356, the actual finding) ──────
///
/// The first built version was an explicit counter `(epoch, n)`, 8 B
/// in plaintext. It HAD to be in plaintext — the opener is
/// pair-agnostic (invariant 3), it cannot unblind anything under
/// `K_AB` before opening. But that made it readable for the responsible relay
/// too, and it was MONOTONIC. A relay in Secure mode sees
/// `(mark, selector)` and can thereby assign TWO DIFFERENT marks
/// to the same receiver: neighbouring counters come from
/// the same supply. Exactly this linkage §10.1 declares
/// closed — „without `K_AB`, the attacker cannot tell which relays
/// hold a given target's cells". In Speed mode it was worse: there
/// the counter runs per identity of the RECEIVER, so the counter sequence
/// revealed its total volume across ALL senders.
///
/// The hash removes both. `eph_pk` is fresh per cell, so the
/// selector is pseudorandom per cell; two cells to the same receiver
/// can no longer be linked through it, not even against the same
/// prekey (measured in `smoke_v41_one_time_prekeys.dart`, section 11).
/// Four instead of eight bytes, because a hash field no longer carries any structure
/// that could be exploited: the 4 B are pure preselection, the decision
/// is made by the AEAD.
///
/// ── THE LONG-LIVED KEY IS NO LONGER A SPECIAL CASE ───────────────
///
/// Here stood a constant `staticMarker = 0xFFFFFFFF` for „no
/// one-time prekey, but the long-lived key". It was removed WITHOUT
/// REPLACEMENT, and not out of economy: a reserved mark is
/// a visible feature on the wire. It told every eavesdropper „this
/// cell is the first contact of a pair" — the same information that the
/// distinguishing byte of the capsule would disclose and that for exactly
/// this reason was not introduced (see [MessageSealer]). In
/// version B the sender computes the selector over the static
/// public part like over any other candidate, and the
/// receiver tries it as one candidate among the others
/// ([MessageOpener.open]). Re-measured: after the rebuild no caller
/// needed `isStatic` or `staticMarker` any more — the special case was
/// entirely in the mark, not in the computation.
///
/// ── WHAT IT COSTS ────────────────────────────────────────────────────
///
/// On the wire 4 B per message (previously 8), in plaintext before the
/// ephemeral key.
///
/// In computing time VERSION B COSTS MORE THAN VERSION A, and that belongs
/// here instead of in a footnote. The counter was a lookup in
/// a map, i.e. O(1); the hash is not: because `eph_pk` is fresh per cell,
/// NOTHING can be precomputed, the receiver must hash once per
/// candidate. Measured on the development machine
/// (libsodium, 2026-08-30): SHA-256 over 64 B = **0.947 us**, X25519 =
/// **37.76 us** — a candidate thus costs 1/40 of a
/// scalar multiplication. With 20 contacts and 8..16 unused prekeys
/// per supply that is 160..320 candidates, making **152..303 us per
/// incoming cell**. Compared with trying through with
/// scalar multiplications (160..320 x 37.76 us = 6..12 ms) this is
/// still the gain §4.6 is about; compared with the map lookup
/// of version A it is a loss which at the DoS cap
/// ([MessageOpener.maxAttemptsPerSecond] = 2000) amounts to about 0.6
/// core-seconds per second. The cap was NOT
/// adjusted — that would be a decision, not an implementation.
///
/// The selector is AEAD-bound: the 4 B go as associated data into
/// AES-256-GCM. Whoever changes them in transit destroys the checksum.
abstract final class PrekeySelector {
  /// Length on the wire.
  static const int bytes = 4;

  /// The selector for a prekey and a cell.
  ///
  /// ONE place for both sides. Sender and receiver must compute
  /// bit-identically; two versions would be exactly the drift by which a
  /// crypto path silently diverges — the same reasoning for which
  /// [MessageSealer.combineForOpen] exists.
  static Uint8List of(Uint8List prekeyPublic, Uint8List ephemeralPublic) {
    final ikm = Uint8List(prekeyPublic.length + ephemeralPublic.length)
      ..setRange(0, prekeyPublic.length, prekeyPublic)
      ..setRange(prekeyPublic.length, prekeyPublic.length + ephemeralPublic.length,
          ephemeralPublic);
    return Uint8List.sublistView(SodiumFFI().sha256(ikm), 0, bytes);
  }

  /// Does [selector] carry the prekey [prekeyPublic] for this cell?
  ///
  /// A hit is a PRESELECTION, not a proof: with 4 B an arbitrary
  /// candidate hits by chance with 2^-32. The decision is made by the
  /// AEAD that runs afterwards. Exactly for that reason nothing may be
  /// deleted here either (§4.6 point 3, see [MessageOpener.oneTimeSecret]).
  static bool matches(Uint8List selector, Uint8List prekeyPublic,
      Uint8List ephemeralPublic) {
    final s = of(prekeyPublic, ephemeralPublic);
    for (var i = 0; i < bytes; i++) {
      if (s[i] != selector[i]) return false;
    }
    return true;
  }
}

/// A hit of the candidate probe: the secret and its identifier.
///
/// WHY THE IDENTIFIER COMES ALONG. Deletion happens only AFTER the AEAD
/// (§4.6 point 3), i.e. at a different place than the lookup. Without
/// the identifier the deletion site would have to compute the 160..320 hashes a second time
/// to find the same prekey again — double work in the
/// DoS path and, worse, a second search that may deviate
/// from the first. [index] is the supply-wide index from
/// `PrekeyIndexSpace`; it does NOT travel on the wire, it is purely the
/// receiver's house number.
final class PrekeyMatch {
  final Uint8List secret;
  final int index;

  /// The ML-KEM secret part of the BATCH this prekey comes from
  /// (E1, S363) — 2400 B, or `null`.
  ///
  /// ── WHY IT COMES ALONG HERE AND IS NOT LOOKED UP ───────────
  ///
  /// Which batch was meant is known **only** at the place where
  /// the selector hit: the index alone does not say it, because the
  /// opener does not know the supplies (it gets a callback, not a
  /// supply). A second search would be the 160..320 hashes once more —
  /// and, worse, a second search that may deviate from the first.
  /// The same reasoning for which [index] travels along.
  ///
  /// `null` means „this prekey carries no batch KEM": a stored item
  /// from the time before E1. The opener then falls back to the
  /// identity generations ([MessageOpener.open], step 2) —
  /// exactly the path such a prekey took at the sender too.
  final Uint8List? mlKemSk;

  const PrekeyMatch(this.secret, this.index, {this.mlKemSk});
}

/// Where the receiver's keys come from.
///
/// §4.3 demands a DAILY CADENCE: the ML-KEM capsule is formed once per day
/// and contact against a **daily prekey**, the X25519 per
/// message against a **one-time prekey** (§4.6).
abstract interface class PrekeySource {
  /// The ML-KEM part against which the daily capsule is formed.
  Uint8List mlKemPublicFor(String peer);

  /// The X25519 part against which the per-message DH is formed.
  ///
  /// HERE ALSO STOOD `selectorFor(peer)` — the information WHICH prekey
  /// that was. It was dropped with version B, and that is the quietest
  /// gain of the rebuild: the selector is now computed from EXACTLY THE
  /// public part this method supplies
  /// ([MessageSealer.seal] calls it once and uses the result for
  /// both). As long as there were two methods, they could diverge
  /// — two draws, two answers, and the message was SILENTLY not
  /// openable. This class of bug no longer exists, because
  /// the second information no longer exists.
  Uint8List x25519PublicFor(String peer);

  /// Whether this supply delivers real one-time prekeys.
  ///
  /// `false` means: these are the static keys, and the per-message
  /// forward secrecy from §4.6 does NOT exist.
  bool get providesForwardSecrecy;
}

/// The static contact keys as prekey substitute.
///
/// **EXPLICITLY A SHORTCUT, not an implementation of §4.6.** It delivers
/// the right form and the right size — 32 B ephemeral X25519 on
/// the wire instead of a 1088 B capsule —, but it buys NO
/// per-message forward secrecy: whoever later obtains the static key of the
/// receiver thereby opens everything that was sealed against it.
///
/// It is therefore not the default but must be chosen. Whoever
/// chooses it should see it in the code.
final class StaticKeyPrekeys implements PrekeySource {
  final Uint8List Function(String peer) mlKem;
  final Uint8List Function(String peer) x25519;

  const StaticKeyPrekeys({required this.mlKem, required this.x25519});

  @override
  Uint8List mlKemPublicFor(String peer) => mlKem(peer);

  /// Step 3 of the fallback ladder (§4.6). For that it no longer needs to
  /// report ANYTHING special: the selector is computed over this
  /// public part like over any one-time prekey, and
  /// the receiver finds it because it owns the same key.
  @override
  Uint8List x25519PublicFor(String peer) => x25519(peer);

  @override
  bool get providesForwardSecrecy => false;
}

/// The day capsule of a contact.
final class DailyCapsule {
  /// The day for which it applies (days since epoch, UTC).
  final int day;

  /// The shared secret of the capsule.
  final Uint8List sharedSecret;

  /// The ciphertext the receiver needs to form the same.
  ///
  /// 1088 B — it does NOT travel in every cell, but once per day and
  /// contact. Exactly that is the difference on which the whole
  /// cell arithmetic hangs: with one capsule per message not even
  /// an empty message would fit into a cell (1088 > 1043).
  final Uint8List ciphertext;

  /// What it was formed with — the identifier of the ML-KEM pubkey (E1,
  /// S363).
  ///
  /// ── WHY THE CAPSULE NO LONGER SUFFICES „PER DAY AND CONTACT" ───────
  ///
  /// Until E1 there was ONE ML-KEM key per identity; „the capsule
  /// of this day for this contact" was thus unambiguous. Since E1
  /// the capsule key hangs on the BATCH: if the batch changes (all 16
  /// prekeys used up, replenishment arrived), the cached
  /// capsule is formed against a key the receiver does not carry for the
  /// now drawn `sk_i`. Continuing to use it would mean:
  /// the receiver finds the right prekey via the selector,
  /// decapsulates with the ML-KEM sk of **this** batch and gets a
  /// different `ss_pq` — the AEAD fails, and SILENTLY.
  ///
  /// That is why every capsule carries the identifier of its key, the cache
  /// is keyed by it, and the counterpart's proof applies exactly
  /// to the one capsule it proved.
  final String pkFp;

  const DailyCapsule(this.day, this.sharedSecret, this.ciphertext, this.pkFp);

  /// The identifier of an ML-KEM pubkey: the first 8 B of its SHA-256, hex.
  ///
  /// It never leaves the process — it is an identifier in two
  /// maps, not a field on the wire. On the wire it would stand
  /// as a feature: an eavesdropper would read from it when a pair changes
  /// batch. Exactly for that reason it is here and not there.
  static String fp(Uint8List pk) {
    final h = SodiumFFI().sha256(pk);
    final b = StringBuffer();
    for (var i = 0; i < 8; i++) {
      b.write(h[i].toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }
}

/// Seals messages for the V4.1 path (§4.3).
///
/// ```
/// Once per day and contact: ss_pq = ML-KEM-Encaps(daily prekey)
/// Per message:              dh    = X25519(eph_sk, one-time prekey)
///                            mk    = KDF(ss_pq ‖ dh)
/// ```
///
/// On the wire ride the selector (4 B) and the ephemeral X25519
/// (32 B). Overhead per message: 4 + 32 + 12 + 16 = **64 B**. That
/// leaves of the 1043 B of a stored item **979 B** for the frame — a
/// whole paragraph measures 190 B as measured.
///
/// ── THE CAPSULE MUST TRAVEL ALONG (S349) ────────────────────────────────
///
/// Until S349 [seal] built `eph ‖ nonce ‖ ciphertext` and left the
/// **capsule ciphertext lying on the floor**. `capsuleFor` formed it, the
/// sender derived `ss_pq` from it — and the receiver had no
/// way to form the same `ss_pq`: ML-KEM is not
/// Diffie-Hellman, without the ciphertext there is no shared secret.
/// [open] demanded `capsuleSharedSecret` as a parameter, and in `lib/`
/// no one could obtain it; the only caller was a
/// smoke test that fetched it by hand from the sender. **Every
/// sealed message was thus unopenable even with perfect
/// delivery.**
///
/// On the wire it now looks like this:
///
///     sel(4) ‖ eph(32) ‖ capsule(1088) ‖ nonce(12) ‖ ciphertext  first per day
///     sel(4) ‖ eph(32) ‖               ‖ nonce(12) ‖ ciphertext  every further one
///
/// `sel` is the prekey selector from §4.6 — `SHA-256(pk_n ‖ eph_pk)`,
/// truncated to 4 B. It says AGAINST WHICH prekey the `dh` was formed.
/// It is in plaintext (the opener is pair-agnostic, it cannot
/// unblind it) and goes as associated data into the AEAD, so it is
/// not forgeable. Why hash and not counter, and what that
/// costs: see [PrekeySelector].
///
/// **NO DISTINGUISHING BYTE.** A header byte „a capsule follows here"
/// would lie in the aggregate, and r2 sees the aggregate in plaintext (it strips
/// shell 2) — it would read from it when a pair speaks for the first time
/// in the day. The receiver instead TRIES both forms; the
/// AEAD check decides. That costs a second attempt and
/// reveals nothing.
///
/// **WHY THE RECEIVER DOES NOT HAVE TO TRY OVER CONTACTS.** §4.6:
/// „The ML-KEM component is a single daily prekey per identity, **not
/// part of the one-time pool**." The capsule is thus formed against a
/// key of the RECEIVER, not against a pair — a
/// single decapsulation per cell suffices, regardless of how many
/// contacts the node has. Only the X25519 of the second half is
/// pairwise — and which one-time prekey is meant is said since S355 by the
/// selector in the header ([PrekeySelector]), instead of the receiver having
/// to try through the whole supply.
final class MessageSealer {
  final PrekeySource prekeys;

  /// The daily capsules, PER COUNTERPART and per key identifier.
  ///
  /// TWO LEVELS, NOT ONE COMPOSITE STRING. Since E1 there are
  /// several capsules side by side per pair (one per prekey batch,
  /// one under the anchor), and the question „do I have one for this
  /// counterpart at all?" must be answerable without a string prefix:
  /// `peer` in the Secure path is itself a
  /// pair identifier with a `/` in it (`<own64>/<foreign64>`), so a
  /// prefix comparison could hit foreign entries.
  final Map<String, Map<String, DailyCapsule>> _capsules = {};

  /// Counterparts that have already received the capsule of this day.
  ///
  /// It is sent along ONCE per day and contact (§4.3
  /// „once per day and contact") — every further message saves the
  /// 1088 B as soon as a proof exists. The key is `peer/tag`,
  /// so that the day change sends the capsule along again by itself.
  MessageSealer(this.prekeys);

  /// How long a capsule proof stands without contradiction.
  ///
  /// ── THE FIELD FINDING THAT MAKES THIS PERIOD NECESSARY (30.08.2026) ───────
  ///
  /// Until here the proof was valid until UTC MIDNIGHT, because its key
  /// carries the day. The receiver however keeps its daily secrets in
  /// memory ([MessageOpener]) — if it restarts in the middle of the day, its
  /// stock is empty while the sender keeps leaving out the capsule.
  /// **Every further Secure message of the day is then unopenable**,
  /// visible as `V4.1 UNGEOEFFNET … Selektor passte, AEAD fiel`.
  /// Measured on 30.08. against a freshly installed phone.
  ///
  /// Path 1 ([MessageOpener.toJsonString]) takes away the ground of the case, but
  /// not completely: a reinstallation, a restore from the
  /// seed phrase and a lost supply look exactly the same for the SENDER.
  /// The sender therefore needs a measurement of its own.
  ///
  /// ── WHY A PERIOD AND NOT A CLOCK ─────────────────────────────
  ///
  /// A fixed clock (midnight) says nothing about the receiver. The
  /// period by contrast measures exactly what counts: **we have been sending for longer
  /// than the Secure ceiling and hear nothing back.** A newly
  /// started receiver cannot open anything, so it does not acknowledge —
  /// exactly then it applies, and only then. A receiver legitimately
  /// offline is the same case and gets the capsule too; that
  /// is right and not a side effect, because when it comes back it needs
  /// it.
  ///
  /// ── WHERE THE HOUR COMES FROM ──────────────────────────────────────────
  ///
  /// The Secure ceiling, not a number grabbed from the air: `delivery_api.dart`
  /// carries `SendMode.secure` with „~1 h (§8)", `secure_mode.dart` with
  /// „~1 h ceiling on reachable platforms", `delivery_state.dart`
  /// with „Speed (~8.5 s) or Secure (~1 h)". Shorter would be a false alarm
  /// for every normally slow Secure delivery; longer would leave the
  /// receiver deaf longer than the delivery itself needs.
  static const Duration capsuleBeliefTimeout = Duration(hours: 1);

  /// The overhead per message on the wire — WITHOUT capsule.
  ///
  /// 64 B: `sel(4) ‖ eph(32) ‖ nonce(12) ‖ tag(16)`. The way there: 60 B
  /// without any selector (until S355), 68 B with the counter `(epoch, n)`
  /// (S355, version A), 64 B with the hash selector (version B, 30.08.).
  /// The four saved bytes are incidental — the reason for version B is
  /// the linkability of the counter, not its size
  /// ([PrekeySelector]).
  static const int overheadBytes = PrekeySelector.bytes + 32 + 12 + 16;

  /// Size of the ML-KEM-768 ciphertext (`oqs_ffi.dart`).
  static const int capsuleBytes = 1088;

  /// The overhead of the FIRST message of a day to a counterpart.
  static const int firstOfDayOverheadBytes = overheadBytes + capsuleBytes;

  /// Does the next message to [peer] carry the capsule?
  ///
  /// The switch in the body of `sendToUser` must know this before it
  /// measures: a message with capsule is 1088 B larger and breaks the
  /// cell limit even when its frame is tiny.
  ///
  /// THE ONE PLACE where the question is answered — [seal] calls it
  /// itself since 30.08. Until then the condition stood there twice
  /// (here and in the body of [seal]); with the expiry of the proof those
  /// would have become two rules that can diverge, and the
  /// switch would have judged the size of a message differently from the one
  /// who builds it.
  bool carriesCapsule(String peer, DateTime now, {PrekeySource? source}) {
    // ── WITHOUT CAPSULE THE ANSWER IS YES, AND IT COSTS NOTHING ─────────
    //
    // If there is no capsule at all for this counterpart yet, the
    // next cell carries one — that can be answered WITHOUT touching the
    // supply. The difference is not only computing time: [capsuleFor]
    // asks the source for an ML-KEM pubkey, and a caller that
    // merely wants to estimate the SIZE of a future cell does
    // not necessarily have a supply that can answer.
    final forPeer = _capsules[peer];
    if (forPeer == null || forPeer.isEmpty) return true;
    return _carriesCapsule(capsuleFor(peer, now, source: source), peer, now);
  }

  /// The same question when the capsule is already in hand — [seal] has
  /// it then and should not form it a second time.
  bool _carriesCapsule(DailyCapsule k, String peer, DateTime now) {
    final confirmedAt = _capsuleConfirmed[_capsuleIdentifier(peer, k)];
    if (confirmedAt == null) return true;
    return _proofExpired(peer, confirmedAt, now);
  }

  static int dayOf(DateTime utc) => utc.millisecondsSinceEpoch ~/ 86400000;

  /// The identifier of ONE capsule: counterpart, key identifier, day.
  ///
  /// THE DAY IS AT THE END, and that is not cosmetics: [_forgetOldDays]
  /// reads it behind the last `/`. If the key identifier stood there,
  /// the cleanup would never trim anything again.
  static String _capsuleIdentifier(String peer, DailyCapsule k) =>
      '$peer/${k.pkFp}/${k.day}';

  /// The daily capsule — newly formed if it is missing, the day has
  /// changed OR the ML-KEM key is a different one (E1, S363).
  ///
  /// [source] overrides the supply against which encapsulation happens.
  /// It is the path of E3: control cells encapsulate against the PAIR ANCHOR
  /// and not against the batch currently drawn from. Both
  /// capsules lie SIDE BY SIDE in the cache — they carry different
  /// identifiers —, otherwise control cell and payload message would displace
  /// each other alternately, and every cell would carry its 1088 B again.
  DailyCapsule capsuleFor(String peer, DateTime now, {PrekeySource? source}) {
    final tag = dayOf(now.toUtc());
    final pk = (source ?? prekeys).mlKemPublicFor(peer);
    final fp = DailyCapsule.fp(pk);
    final forPeer = _capsules.putIfAbsent(peer, () => {});
    final there = forPeer[fp];
    if (there != null && there.day == tag) return there;
    final enc = OqsFFI().mlKemEncapsulate(pk);
    final fresh = DailyCapsule(tag, enc.sharedSecret, enc.ciphertext, fp);
    forPeer[fp] = fresh;
    return fresh;
  }

  /// Seals [plaintext] for [peer].
  ///
  /// Returned is `sel(4) ‖ eph(32) ‖ nonce(12) ‖ ciphertext ‖ tag(16)`.
  ///
  /// THE PUBLIC PART IS FETCHED ONCE and then carries both:
  /// the selector and the Diffie-Hellman. In version A these were two
  /// questions to the source (`x25519PublicFor` and `selectorFor`), which
  /// could hit different draws; then the receiver searched for
  /// a secret that does not belong to this `dh`, and the failure
  /// was SILENT. With version B that can no longer happen — the
  /// selector IS a function of the key used.
  /// [source] overrides the supply for THIS sealing — the
  /// path of E3 (S363).
  ///
  /// ── CONTROL CELLS RUN UNDER THE PAIR ANCHOR, NEVER UNDER ROTATING
  ///    MATERIAL ─────────────────────────────────────────────────────
  ///
  /// Replenishment, emergency rotation, restore broadcast and
  /// key packages carry the material from which a relationship finds its way
  /// back. Sealing them against a one-time prekey binds
  /// exactly this material to the shortest period in the house
  /// ([PrekeyPool.retention] = 15 d) — the 31-day class was therefore
  /// really a 15-day class on the opener side, and the deadlock
  /// „both sides seal against each other against dead material" could
  /// only arise in the first place.
  ///
  /// The anchor is the long-lived pair material (X25519 + ML-KEM of the
  /// identity). It has NO per-message forward secrecy, and that
  /// is the knowingly paid price: the content of a control cell is
  /// public key material plus authentication. It is also
  /// not immutable — it rotates along on revocation and
  /// emergency rotation (owner decision 03.09.2026, A-9 = B), so that
  /// a revoked device does not permanently read along on exactly the cell class
  /// over which key packages run.
  ///
  /// Whoever does NOT set it gets the regular path: one-time prekey plus
  /// batch capsule, with per-message forward secrecy.
  Uint8List seal({
    required String peer,
    required Uint8List plaintext,
    required DateTime now,
    Uint8List? ephemeralSeed,
    Uint8List? staticSharedSecret,
    PrekeySource? source,
  }) {
    final sodium = SodiumFFI();
    // ── FIRST CONTACT HAS NO CAPSULE, IT HAS `K_inv` (§15.4) ──────
    //
    // §15.4 writes the seal key of the contact request as
    //
    //     HKDF( K_inv(i) ‖ X25519(eph_sk, X_B) [ ‖ ML-KEM.Encaps(M_B) ] )
    //
    // — the ML-KEM part in square brackets, i.e. only if the seed carries PQ
    // material. Exactly this formula arises when the secret derived from
    // `K_inv(i)` stands in the place of the capsule secret:
    // [_combine] is `HKDF(ss_pq ‖ dh)`.
    //
    // WHY THIS NOT ONLY REPLACES A CAPSULE BUT EXCLUDES IT. An
    // ML-KEM capsule against the receiver could not be formed here at all:
    // the requester does not have its long-lived ML-KEM pubkey. It has from
    // the ContactSeed `ep` (and thereby `X_B` via Ed25519->X25519), but
    // 1184 B of ML-KEM neither fit into a QR code nor are they in the seed
    // built today (§15.3.1, §15.5 „extended only").
    //
    // NO FEATURE ARISES ON THE WIRE, and that is the reason
    // why it goes this way and not via an identifying byte: the form is byte for byte
    // that of the „capsule already proven" message. Further up in this file
    // it says why that counts — the reserved mark `staticMarker` was
    // removed WITHOUT REPLACEMENT because it „told every eavesdropper: this cell is
    // the first contact of a pair".
    //
    // NO SENT NOTE. `_capsuleConfirmed` and `_unbeantwortetSeit`
    // keep book on the DAILY CAPSULE of a pair. A pseudo-counterpart
    // (the invitation line) has none, and an entry there would later be read
    // for the REAL pair — the same identifier mix-up that
    // as B-31 has already cost cells twice.
    final DailyCapsule? capsule = staticSharedSecret == null
        ? capsuleFor(peer, now, source: source)
        : null;
    final Uint8List ssPq =
        staticSharedSecret ?? capsule!.sharedSecret;
    final Uint8List ephSk;
    final Uint8List ephPk;
    if (ephemeralSeed != null) {
      ephSk = Uint8List.fromList(ephemeralSeed);
      ephPk = sodium.x25519ScalarMult(ephSk, _basepoint);
    } else {
      final kp = sodium.generateX25519KeyPair();
      ephSk = kp.secretKey;
      ephPk = kp.publicKey;
    }
    // ONE call, two uses — see the header note of this method.
    // AND FROM THE SAME SOURCE AS THE CAPSULE: if the two
    // diverged (anchor capsule, batch X25519), the receiver would search
    // for a one-time prekey via the selector and decapsulate with the
    // batch secret part, while the sender encapsulated against the anchor
    // — different `ss_pq`, AEAD fails, silently.
    final pk = (source ?? prekeys).x25519PublicFor(peer);
    final selBytes = PrekeySelector.of(pk, ephPk);
    final dh = sodium.x25519ScalarMult(ephSk, pk);
    final mk = _combine(ssPq, dh);
    final nonce = sodium.randomBytes(12);
    final ct = sodium.aesGcmEncrypt(plaintext, mk, nonce, ad: selBytes);

    // FIRST OF THE DAY: the capsule rides along, otherwise the receiver cannot
    // form `ss_pq`. After that it is dropped — it is constant per day and
    // contact (§4.3) — but only as long as the proof HOLDS; see
    // [capsuleBeliefTimeout].
    // THE ONE PLACE where the question is answered — and [seal]
    // calls it itself. Writing it twice (here and in
    // [carriesCapsule]) would be two rules that can diverge,
    // and the switch would judge the size of a message
    // differently from the one who builds it.
    final withCapsule =
        capsule != null && carriesCapsule(peer, now, source: source);
    if (capsule != null) {
      final key = _capsuleIdentifier(peer, capsule);
      if (withCapsule && _capsuleConfirmed.containsKey(key)) {
        capsuleReattached++;
      }
      // ── WHAT WAS SENT MAY BE CONFIRMED BY A PROOF ──────────
      //
      // Until S351 there was a set `_capsuleSent` here, which was written
      // and read for NO decision; it rightly
      // fell. Since E1 there are SEVERAL capsules side by side per pair
      // (one per batch, one under the anchor), and a proof from the
      // counterpart only says „something from me arrived". Applying it to a
      // capsule this side NEVER sent would mean
      // saving 1088 B the receiver never got — exactly
      // the silent loss class against which [capsuleBeliefTimeout]
      // was built. This set thus has a reader
      // ([confirmCapsuleReceived]) and is not bookkeeping for its own
      // sake.
      if (withCapsule) {
        _capsuleSentOff[key] = (peer: peer, tag: capsule.day);
      }
    }

    // THE CLOCK OF THE PROOF RUNS FROM HERE, and it runs AFTER the question
    // above — otherwise this sending would judge itself.
    //
    // WHY IN `seal` AND NOT IN THE SERVICE: `seal` is the ONE funnel
    // through which every own V4.1 sealing passes. `V41Host` seals
    // in TWO places — `sendFrame` for the user's message and
    // `refillIfNeeded` for the prekey replenishment (`v41_host.dart`,
    // „ONE place for both senders"). Only the first creates a record in the
    // delivery register; a measurement in the service would never see the second,
    // although it too is a message the receiver must be able
    // to open.
    //
    // `putIfAbsent`: what is measured is the OLDEST still unanswered
    // sending, not the youngest. The difference is the whole benefit —
    // whoever writes every minute would with „youngest sending" never have a
    // sending older than the ceiling, and a newly started
    // receiver would stay undetected precisely in the liveliest chat.
    if (capsule != null) _unansweredSince.putIfAbsent(peer, () => now);

    const header = PrekeySelector.bytes;
    final capsuleLen = withCapsule ? capsule.ciphertext.length : 0;
    final out = Uint8List(header + 32 + capsuleLen + 12 + ct.length);
    out.setRange(0, header, selBytes);
    out.setRange(header, header + 32, ephPk);
    if (withCapsule) {
      out.setRange(header + 32, header + 32 + capsuleLen, capsule.ciphertext);
    }
    out.setRange(header + 32 + capsuleLen, header + 44 + capsuleLen, nonce);
    out.setRange(header + 44 + capsuleLen, out.length, ct);
    return out;
  }

  // HERE STOOD `forgetCapsuleSent` AND THE SET `_capsuleSent` (until S351).
  //
  // Both formed a rollback for the case that a capsule-carrying
  // cell gets lost: the sent note was to be withdrawn
  // so that a later message would take the capsule along again. The concern was
  // right, the mechanism ineffective — `_capsuleSent` was filled and
  // emptied, but read for no decision. The decision is made, here
  // as ever, via `_capsuleConfirmed` (see `carriesCapsule` and
  // `seal`). The rollback deleted an entry that had no effect.
  //
  // The property it was supposed to establish holds without it, and more strongly:
  // the capsule is only dropped against a PROOF from the counterpart. A
  // lost cell produces no proof, so the capsule keeps travelling along —
  // without anyone having to withdraw anything.

  /// Proves that [peer] really has the daily secret.
  ///
  /// WHY „SENT" IS NOT ENOUGH. „First message of the day" is
  /// a notion of the SENDER. Delivery is unordered: in Speed mode
  /// over changing relays, in Secure mode harvested from three families.
  /// If precisely the capsule-carrying cell gets lost — or
  /// a later one arrives first —, the receiver lacks the daily secret,
  /// and **every further message of this day to it is unopenable**.
  /// §4.6 warns of exactly this class („cells become unopenable
  /// (silent message loss)").
  ///
  /// That is why the capsule keeps travelling along UNTIL a proof exists: an
  /// opened message from the counterpart on the same day. The price is
  /// an additional cell per message as long as no answer came —
  /// it is paid only where no one answers anyway.
  ///
  /// ── AND SINCE 30.08. IT HAS A SHELF LIFE ─────────────────────
  ///
  /// The call resets the clock from [capsuleBeliefTimeout]: what was
  /// unanswered until here is answered. If nothing comes back afterwards
  /// while we keep sending, the proof expires by itself
  /// and the capsule travels along again. The time is RECORDED
  /// and not merely noted — without it „unanswered since the receipt"
  /// could not be separated from „already open before the receipt", and
  /// the period would strike immediately at the first sending after the
  /// receipt.
  ///
  /// [now] may be local or UTC: `isAfter` and `difference` compute in
  /// Dart on the instant, not on the zone. The callers are
  /// indeed mixed — the receiving side passes `DateTime.now()`
  /// (`cleona_service_receive.dart`), the send path
  /// `DateTime.now().toUtc()` (`cleona_service.dart`).
  void confirmCapsuleReceived(String peer, DateTime now) {
    // ── PER CAPSULE, NOT PER PAIR (E1/E3, S363) ────────────────────────
    //
    // Since E1 a pair carries several capsules side by side: one per
    // prekey batch and one under the pair anchor (E3). A proof applies
    // to the one this side really sent to the counterpart —
    // for a never-sent capsule it proves nothing, and continuing to
    // send it along costs 1088 B, while leaving it out would make the cell
    // silently unopenable.
    // ── COMPARED, NOT PARSED ─────────────────────────────────────
    //
    // The identifier is `peer/fp/tag`, and `peer` in the Secure path is
    // itself a pair identifier with a `/` in it
    // (`<own64>/<foreign64>`). Reading it back from the string
    // would mean relying on fixed lengths that this layer
    // does not know — and a prefix comparison could confirm a foreign
    // proof. The component is therefore CARRIED ALONG.
    final tag = dayOf(now.toUtc());
    for (final e in _capsuleSentOff.entries) {
      if (e.value.peer != peer || e.value.tag != tag) continue;
      _capsuleConfirmed[e.key] = now;
    }
    _unansweredSince.remove(peer);
    _forgetOldDays(now);
  }

  /// Has the proof for [peer] expired through a MISSING answer?
  ///
  /// Three conditions, and each single one is necessary:
  ///
  ///   1. There is an open own sending at all. Without it we have
  ///      measured nothing — a silent chat is no finding, and
  ///      sending the capsule again would cost 1088 B for nothing.
  ///   2. It lies AFTER the receipt. Otherwise it is exactly the
  ///      sending that triggered the receipt, and that one is proven.
  ///      (The normal case already clears it away in [confirmCapsuleReceived];
  ///      the condition catches the order in which a
  ///      delayed receipt arrives after a new sending.)
  ///   3. It is older than the Secure ceiling. Before that every
  ///      normally slow Secure leg would be a false alarm.
  ///
  /// WHAT IS DELIBERATELY NOT HERE: a query of `V41DeliveryRegister`.
  /// It would be a second bookkeeping about the same fact — the
  /// register flips to `delivered` when `_v41NoteReceipt` applies, and
  /// that is tied to exactly the same condition as the call of
  /// [confirmCapsuleReceived]: `_v41ReceiptProvesCapsule` and
  /// `_v41NoteReceipt` stand in `cleona_service_msgstate.dart`
  /// directly next to each other, both against `verified` and both against
  /// `v41Deliveries.lookup(...) != null`. Where they differ, the
  /// register is the WEAKER measure: the prekey replenishment from
  /// `refillIfNeeded` creates no record there, but is very much a
  /// sending that must be openable.
  bool _proofExpired(String peer, DateTime confirmedAt, DateTime now) {
    final openSince = _unansweredSince[peer];
    if (openSince == null) return false;
    if (!openSince.isAfter(confirmedAt)) return false;
    return now.difference(openSince) > capsuleBeliefTimeout;
  }

  /// When a counterpart proved the capsule of this day.
  ///
  /// `Set` until 30.08.: „proven, full stop". The time came with the
  /// shelf life — it is the boundary from which an unanswered
  /// sending counts at all (see [_proofExpired]).
  final Map<String, DateTime> _capsuleConfirmed = <String, DateTime>{};

  /// Capsules this side really sent (E1/E3, S363).
  ///
  /// Only they may be confirmed by a proof from the counterpart — the reasoning
  /// is at [confirmCapsuleReceived]. It is trimmed with
  /// [_forgetOldDays], by the same day key.
  final Map<String, ({String peer, int tag})> _capsuleSentOff = {};

  /// Since when sending to this counterpart has happened without anything
  /// coming back. One entry per pair, set in [seal], deleted in
  /// [confirmCapsuleReceived].
  final Map<String, DateTime> _unansweredSince = <String, DateTime>{};

  /// How often the capsule travelled along again DESPITE a standing proof
  /// — i.e. how often the shelf life applied.
  ///
  /// Counted, not logged (E-83): in the field the value can only be read
  /// relative to the number of messages. If it stays at 0 permanently
  /// although `V4.1 UNGEOEFFNET` occurs, the period does not apply and the
  /// finding lies elsewhere.
  int capsuleReattached = 0;

  /// Throw away proofs from the day before yesterday and older.
  ///
  /// They can never hit again — the key carries the day — and
  /// without this trimming the map grows with contacts TIMES
  /// days of runtime. For a daemon that runs for weeks, that is
  /// the same class of leak as the cooldown maps that
  /// `_checkMessageExpiry` trims hourly. YESTERDAY stays,
  /// because a receipt can arrive across the day change.
  void _forgetOldDays(DateTime now) {
    final today = dayOf(now.toUtc());
    bool toOld(String k) {
      final i = k.lastIndexOf('/');
      final tag = i < 0 ? null : int.tryParse(k.substring(i + 1));
      return tag != null && tag < today - 1;
    }

    _capsuleConfirmed.removeWhere((k, _) => toOld(k));
    // THE SAME rule for the sent list — otherwise it grows with
    // contacts times batches times days of runtime while the proofs
    // are trimmed. Here via the CARRIED-ALONG day, not via
    // the identifier: it is available anyway.
    _capsuleSentOff.removeWhere((_, v) => v.tag < today - 1);
  }

  // `open()` STOOD HERE and was dropped (S349). It demanded
  // `capsuleSharedSecret` as a parameter — a secret only the
  // SENDER had, because the capsule ciphertext never saw the wire. In `lib/`
  // no one could therefore call it; its only caller was a
  // smoke test that fetched the secret from the sender and thereby
  // faked a delivery that did not exist.
  //
  // The way back is now [MessageOpener] — ONE, with the state
  // of the receiver instead of with a parameter the caller has to
  // make up.

  /// The same derivation, for the receiver side ([MessageOpener]).
  ///
  /// It MUST be the same — a second version would be exactly the kind of
  /// drift by which a crypto path silently diverges.
  static Uint8List combineForOpen(Uint8List ssPq, Uint8List dh) =>
      _combine(ssPq, dh);

  static Uint8List _combine(Uint8List ssPq, Uint8List dh) {
    final ikm = Uint8List(ssPq.length + dh.length)
      ..setRange(0, ssPq.length, ssPq)
      ..setRange(ssPq.length, ssPq.length + dh.length, dh);
    return SodiumFFI().hkdfSha256(
      ikm,
      salt: SodiumFFI()
          .sha256(Uint8List.fromList(utf8.encode('cleona-v41-msg/salt/v1'))),
      info: Uint8List.fromList(utf8.encode('cleona-v41-msg/v1')),
      length: 32,
    );
  }
}

final Uint8List _basepoint = Uint8List(32)..[0] = 9;

/// Byte-wise comparison without timing guarantee.
///
/// Deliberately NOT constant-time: compared here are public
/// quantities (selectors, daily secrets against the own stock) and
/// the own `sk` against its own copy. Where timing equality
/// matters — the AEAD check —, libsodium decides, not this
/// line.
bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A daily secret with the time at which it was learned.
///
/// THE TIMESTAMP IS NEW (30.08.2026) and the reason why the
/// bare `Uint8List` became a record: without it a secret has no
/// metadata, and without metadata there is neither a retention period
/// ([MessageOpener.secretRetention]) nor an honest serialisation —
/// a loaded stock without age would be a stock that never expires.
final class _DailySecret {
  final Uint8List secret;
  final DateTime learnedAt;

  const _DailySecret(this.secret, this.learnedAt);
}

/// The receiver side of sealing (§4.3).
///
/// WHY IT IS A CLASS OF ITS OWN. [MessageSealer] carries the state
/// of the SENDER — which daily capsule was formed against which counterpart,
/// to whom it has already been sent. The receiver carries an entirely
/// different state: its own secrets and the capsules that
/// OTHERS sent to it. Both in one class would have mixed two
/// life cycles in one object.
///
/// THE ASSIGNMENT PROBLEM, stated openly. An incoming cell
/// does not say whom it is from — that is invariant 3, not an omission.
/// The receiver therefore tries; whoever could open it learns the
/// sender only from the opened frame. Tried in this
/// order:
///
///   0. read the selector and `eph_pk` and DETERMINE the X25519 secret:
///      compute `SHA-256(pk_i ‖ eph_pk)` per candidate and compare the
///      front 4 B. Candidates are the unused
///      one-time prekeys ([oneTimeSecret]) AND the long-lived key —
///      the latter without a special mark, as one among them (version B).
///      If none fits, it ends here: no scalar multiplication, no
///      decapsulation. That is the regular case for every foreign cell.
///   1. with the already known daily secrets (1x X25519 each),
///   2. if the cell is long enough: read the front 1088 B as a capsule,
///      decapsulate, open with it — and keep the secret.
///
/// COSTS, computed instead of estimated. At `R_cover` = 1/8 s about
/// 10 800 cells arrive per partner per day, the great majority dummies;
/// with four partners thus ~43 000. Step 1 costs per known
/// daily secret one scalar multiplication (measured 37.4 us,
/// `relay.dart`), step 2 additionally one decapsulation. With 20
/// contacts that is ~32 s of computing time per day. Whoever wants to
/// saturate the node with it must push ~14 MB/s into it — a bandwidth
/// problem, not a computing problem, the same situation as with path-block trying.
final class MessageOpener {
  /// The own ML-KEM part — §4.6: **one** daily prekey per identity,
  /// not per pair. Exactly for that reason ONE decapsulation per cell suffices.
  final Uint8List Function() ownMlKemSecret;

  /// The own LONG-LIVED X25519 part — step 3 of the fallback ladder
  /// (§4.6). It carries the first message of every contact before a
  /// replenishment has flowed, and every message of a counterpart
  /// whose supply is exhausted.
  final Uint8List Function() ownX25519Secret;

  // ── THE PREVIOUS KEM GENERATION (§4.5.4, built S362) ─────────────────
  //
  // §4.5.4 verbatim and normative: „The previous private KEM keys are
  // retained after rotation (`previousX25519Sk`, `previousMlKemSk`); the
  // receiver first attempts unsealing with the current keys and, on
  // `kemDecapFailed`, with the previous ones, so that senders who have not
  // yet harvested the announcement keep getting through."
  //
  // NOTHING OF THAT WAS BUILT. `IdentityContext` produced the two fields
  // on every rotation, saved them encrypted (`prev_x25519_sk` /
  // `prev_ml_kem_sk`) and read them back at start — and NOT A SINGLE
  // decrypting place pointed to them. The body that read them lived
  // in the V3 receive path and fell with the CUT
  // (`cleona_service_receive.dart` says so itself at the demolition site).
  //
  // ── TWO CALLBACKS, NOT ONE, AND THAT IS THE CORE ───────────────
  //
  // The ML-KEM predecessor alone heals NOTHING. The selector decides
  // BEFORE the capsule (see [open]): it is checked against the current
  // long-lived X25519 PUBLIC, and if it does not fit, [open] turns back
  // with `unresolvedSelectors++` — the ML-KEM branch is never reached.
  // Both keys however rotate TOGETHER (`rotateKemKeys`). Whoever only
  // supplies `previousMlKemSecret` builds a branch that no
  // program flow enters.
  //
  // ── THEY MAY RETURN `null` ──────────────────────────────────────
  //
  // Before the first rotation there is no predecessor, and after expiry
  // of the retention period there is none again
  // (`IdentityContext.discardPreviousKeysIfExpired`). Both are the
  // normal case and not an error — the opener then skips the candidate
  // without computing.
  //
  // ── WHAT THEY DO NOT CHANGE ───────────────────────────────────────────
  //
  // They create NO key material and extend NO
  // lifetime. The 2432 B lie encrypted in the profile anyway; whoever
  // breaks the device at rest already has them today. These two
  // lines only give them a reader.

  /// The PREVIOUS generation of the long-lived X25519 — the second
  /// selector candidate. `null` as long as no rotation happened or the
  /// retention period has expired.
  Uint8List? Function()? previousX25519Secret;

  /// The PREVIOUS generation of the ML-KEM — the second capsule candidate.
  /// Tried independently of [previousX25519Secret]: a cell can
  /// come in over a still valid one-time prekey and still
  /// carry a capsule against the old generation.
  Uint8List? Function()? previousMlKemSecret;

  /// Searches among the unused one-time prekeys for the one whose
  /// `SHA-256(pk_i ‖ eph_pk)` hits the selector — WITHOUT
  /// consuming it.
  ///
  /// ── WHY IT NEEDS BOTH ARGUMENTS (version B) ──────────────────
  ///
  /// In version A the selector sufficed: it WAS the index, the lookup
  /// a map query. The hash selector is bound to the cell, so
  /// `eph_pk` must come along — without it it cannot be recomputed. That is
  /// not incidental but the whole gain: precisely because `eph_pk` is fresh per
  /// cell, the selector no longer links two cells
  /// ([PrekeySelector]).
  ///
  /// ── WHY LOOKUP AND CONSUMPTION ARE SEPARATE (§4.6) ────────
  ///
  /// §4.6 says it precisely: „The receiver deletes `sk_i` immediately **after
  /// successful unsealing**." Whoever deletes already at lookup builds
  /// a weapon: a relay on the path can intercept a real cell,
  /// corrupt its ciphertext and send it on — selector and
  /// `eph_pk` then still match, the lookup hits, the AEAD fails.
  /// Whoever deletes at this point destroys the prekey without a
  /// message arriving. The lookup therefore has no consequences;
  /// deletion happens only when the AEAD has held ([oneTimeUsed]).
  ///
  /// `null` means „none of my prekeys" and is the FREQUENT case:
  /// every cover cell carries randomness at this position. The opener then
  /// still tries the long-lived key and then discards — without
  /// scalar multiplication, without decapsulation.
  ///
  /// Not set in the constructor but by `V41Host` when
  /// hooking in the opener — the construction site (`v41_attach.dart:468`)
  /// does not know the supplies, the host carries them.
  PrekeyMatch? Function(Uint8List selector, Uint8List ephemeralPublic)?
      oneTimeSecret;

  /// How many candidates a full pass would check.
  ///
  /// WHY THE OPENER MUST KNOW THIS: since S354 it caps the WORK,
  /// not the calls ([maxProbesPerSecond]) — and the work per cell
  /// is exactly this number times one SHA-256. Without it it would have to guess or
  /// settle afterwards; afterwards would mean paying the bill first
  /// and then finding out that one did not want it.
  ///
  /// Set by the host like [oneTimeSecret]. If it is missing, the
  /// cap falls back to „one candidate per cell" and behaves like the
  /// old call cap — conservative in the wrong direction, but
  /// never quieter than before.
  int Function()? candidateCount;

  /// Reports that a one-time prekey REALLY held. Only here does
  /// deletion happen — and exactly this deletion is the forward secrecy.
  ///
  /// It gets the [PrekeyMatch.index] of the lookup, not the
  /// selector: the selector is a hash, the prekey cannot be determined
  /// from it a second time without repeating the whole candidate
  /// probe.
  void Function(int index)? oneTimeUsed;

  /// Cells for whose selector NO candidate fitted — neither a
  /// one-time prekey nor the long-lived key.
  ///
  /// In the cover stream the normal case (random bytes), therefore counted and
  /// not logged (E-83). The number only becomes interesting in
  /// relation to [oneTimeOpened].
  ///
  /// IT IS THE ONLY NUMBER OF THIS KIND, and that is a deterioration
  /// compared with version A, which is named here and not hidden. The
  /// counter selector carried an epoch; from it „long expired" could be told apart
  /// from „never existed", and §4.6 calls the first case
  /// explicitly „silent message loss". The hash selector carries no
  /// epoch and cannot carry one — an expired prekey is
  /// deleted, so there is no `pk_i` any more against which one could
  /// hash. The case is thus no longer measurable. What takes its
  /// place measures from the other side: `V41Host.expiredPrekeysSwept`
  /// counts how many prekeys the retention period THREW AWAY.
  int unresolvedSelectors = 0;

  /// How many ML-KEM decapsulations this opener has computed.
  ///
  /// The measure of E1 (S363): the draft says „**one**
  /// decapsulation per capsule cell", and without this number that would be a
  /// claim. Before E1 there were up to two per capsule cell
  /// (generation loop); since E1 it is exactly one as soon as the
  /// selector has hit a one-time prekey with batch KEM.
  ///
  /// What is counted is the ATTEMPT, not the success — a failed
  /// decapsulation costs the same computing time as a successful one, and
  /// what is protected is computing time.
  int capsuleDecapsulations = 0;

  /// How many messages a one-time prekey has carried — the only
  /// proof that §4.6 really runs and is not only built.
  int oneTimeOpened = 0;

  /// Daily secrets that come from received capsules.
  ///
  /// Capped: a capsule costs a decapsulation, and whoever sends many
  /// would otherwise fill memory without limit. If the oldest drops
  /// out, that costs at most one renewed decapsulation — the
  /// capsule travels anew at every day change anyway.
  ///
  /// ── WHY 256 STAYS (checked on 30.08.2026) ────────────────
  ///
  /// With the retention period of 7 days ([secretRetention]) the
  /// cap holds about **36 active contacts** (7 days x 1 secret per contact
  /// and day). The question was whether it has to be raised for that. The
  /// answer is no, and the reason is measured instead of estimated.
  ///
  /// Step 1 of [open] tries EVERY known secret. An attempt
  /// is NOT only an AEAD: [MessageSealer.combineForOpen] derives
  /// the message key beforehand. Measured on the
  /// development machine (libsodium, 2026-08-30, 50 000 runs per
  /// item):
  ///
  ///   HKDF-SHA256 (`combineForOpen`)          4,788 us
  ///   AES-256-GCM, failing (with throw)       3,519 us
  ///   ------------------------------------------------
  ///   per candidate in step 1                 8,31 us
  ///
  ///   (for context, same measurement: AES-256-GCM successful
  ///   1.369 us, SHA-256 over 64 B 0.913 us — the value 0.947 us from
  ///   [PrekeySelector] is thus confirmed on this machine.)
  ///
  /// A candidate in step 1 thus costs **8.8x as much as a
  /// candidate probe** from §4.6. With a full cap that is 256 x 8.31 us
  /// = **2.1 ms per cell** that passes the preselection. Every further
  /// slot lengthens this path linearly. Raising it would mean making an already
  /// expensive loop more expensive without a measured need
  /// — 36 active contacts in seven days is not a limit
  /// anyone would have hit in the field.
  ///
  /// ── WHAT THIS MEASUREMENT BRINGS TO LIGHT OTHERWISE (not fixed) ─────────
  ///
  /// The loop lies OUTSIDE the probe budget:
  /// [maxProbesPerSecond] counts candidate probes (SHA-256), not
  /// step-1 attempts. It is only entered when the preselection
  /// hit — so never for a foreign cover cell, but indeed for
  /// every cell addressed against one of our prekeys. A
  /// CONTACT can thus force it: at [maxAttemptsPerSecond] = 2000
  /// and a full stock that would arithmetically be 4.2 core-seconds per
  /// second. That is a finding on the cap, not on this change —
  /// the period below makes it smaller (the steady-state stock is
  /// now `Kontakte x 7` instead of „everything that ever came"), it does not remove
  /// it. Adjusting the cap would be a decision, not an
  /// implementation; the number is here so that it can be made.
  static const int maxSecrets = 256;

  /// How long a daily secret is retained.
  ///
  /// ── WHY RETAIN AT ALL (path 1, 30.08.2026) ────────────────
  ///
  /// Until here this stock lived only in memory. A restart of the
  /// receiver deleted it, while the sender kept leaving out the capsule because of
  /// its proof — every further Secure message of the
  /// day was unopenable (see [MessageSealer.capsuleBeliefTimeout]).
  ///
  /// ── WHY 7 DAYS AND NOT 15 ───────────────────────────────────────
  ///
  /// The owner verbatim: „Keys on the disk is nonsense. If
  /// anything it has to go encrypted into the database!" — that is why
  /// this class only supplies a serialisation; storing it encrypted is done by the
  /// caller.
  ///
  /// That this is defensible AT ALL depends on a calculation that
  /// must be here: `ss_pq = ML-KEM-Decaps(kapsel, mlKemSecretKey)`.
  /// The key from which each of these secrets can be
  /// recovered is already stored encrypted in the profile anyway
  /// (`lib/core/identity/identity_context.dart:481` writes `ml_kem_sk`
  /// via `FileEncryption`, `:350` reads it). Whoever breaks the device
  /// at rest has the KEM key and can decapsulate every retained
  /// capsule himself — a persisted `ss_pq` gives him nothing
  /// he would not already have.
  ///
  /// That holds however ONLY as long as the period does not exceed the KEM retention.
  /// Rotation runs every 7 days
  /// (`identity_context.dart`, `needsRotation()`, `inDays >= 7`), and the
  /// previous generation stays for **32 days** since S362
  /// (`IdentityContext.previousKeyRetention`, the clamp from §4.5.4 for
  /// the 31-day class). An `ss_pq` retained longer than
  /// the key it comes from would reopen exactly
  /// what rotation is supposed to close. 7 days lie well
  /// below that — since the clamp the period here is more conservative than
  /// necessary, never tighter.
  ///
  /// (UNTIL S362 THIS SAID „the predecessor stays another 7 days".
  /// The number was right, the calculation drawn from it no longer: it
  /// justified 7 days by the cadence being exactly covered. Covered
  /// it still is, but for a different reason.)
  ///
  /// In practice the period is not needed in full anyway: a
  /// daily secret is useful for one day (§4.3), after that the
  /// counterpart sends a new capsule. The six days beyond that are
  /// reserve for clock drift and for messages harvested from an older
  /// stored item.
  ///
  /// ── THE 31-DAY PROMISE AND ITS OPENABLE HORIZON (S362) ──────────
  ///
  /// Here stood „§22.4.1 harvests three epochs backwards". Since S362
  /// that is wrong: the harvest reaches back to `kManagementKeepEpochs` = 31
  /// epochs (`ernteEpochenPlan`, `secure_mode.dart`), so that the
  /// management class (§21.1, „31 d for management types") is queried
  /// at all.
  ///
  /// After that stood here the finding that the harvest reaches further than
  /// this side can open — the opener held only the CURRENT
  /// KEM key, while rotation happens every 7 days. **This finding
  /// is closed** (owner decision of 02.09.2026, „path 1 with
  /// clamp"): since S362 [MessageOpener] carries the previous generation
  /// as second selector and second capsule candidate
  /// ([previousX25519Secret], [previousMlKemSecret]), and the
  /// retention stands at 32 days.
  ///
  /// WHAT THIS DOES NOT HEAL, and it is here so that it is not taken for
  /// healed: there is exactly ONE predecessor slot, and
  /// [IdentityContext.rotateKemKeys] overwrites it at every
  /// rotation. A CONTINUOUSLY RUNNING device therefore still loses generation N−1
  /// after 7 days — not at the period but at the
  /// next rotation. The fallback fully hits the case for which the
  /// class is intended (§14.4, „Return after a long absence"): a
  /// switched-off device does not rotate, catches up exactly one
  /// rotation at start, and the predecessor then covers the whole
  /// absence.
  static const Duration secretRetention = Duration(days: 7);

  final List<_DailySecret> _secrets = <_DailySecret>[];

  // ── STANDING SECRETS: THE INVITATION LINES (§15.3, §15.4) ───────
  //
  // They are NOT daily secrets and therefore must not lie in
  // [_secrets]. The difference is not tidiness but
  // effect — two mechanisms hang on [_secrets], both of which would be
  // wrong here:
  //
  //   * [secretRetention] throws away after 7 days. An invitation lives
  //     per §15.3.3 **90 days** by default, optionally unlimited.
  //     It would be silently deaf after a week — and „silently" is the
  //     bad part here: the requester would never get an answer and never see
  //     a reason.
  //   * The cap [maxSecrets] displaces the OLDEST. An identity
  //     with lively traffic would push its own invitations out of the
  //     stock as soon as 256 daily capsules have run through.
  //
  // NOT SAVED, AND INTENTIONALLY SO. [toJson] does not take them along:
  // they are in the invitation book (`InviteLedger`), which lies encrypted
  // on disk anyway, and are recomputed from it at every attach.
  // A second store would be a second truth about
  // the same set — and that can go stale while the book has already
  // revoked (§15.3.3).
  final List<Uint8List> _standing = <Uint8List>[];

  /// How many standing secrets are held at most.
  ///
  /// §15.3.2 caps the simultaneously OPEN invitations hard at **10**.
  /// Added to that are the already revoked ones whose harvest window is still running
  /// (`InviteLedger.harvestedAt`). 32 leaves room for that and keeps the
  /// work per cell within bounds: step 1 of [open] tries them too,
  /// but only AFTER the selector has hit.
  static const int maxStandingSecrets = 32;

  /// Standing secrets that were not accepted because the cap
  /// was reached. A value > 0 means: at least one invitation is
  /// not harvestable.
  int standingRefused = 0;

  int get standingSecrets => _standing.length;

  /// Enters the secret of an invitation line (§15.4).
  ///
  /// Entering the same value several times has no consequences — the caller
  /// runs through its invitation book at every start and at every change,
  /// and a comparison here is cheaper than a state there.
  void rememberStandingSecret(Uint8List secret) {
    if (secret.length != 32) {
      throw ArgumentError('Standing secret must be 32 B');
    }
    for (final s in _standing) {
      if (_sameBytes(s, secret)) return;
    }
    if (_standing.length >= maxStandingSecrets) {
      standingRefused++;
      return;
    }
    _standing.add(Uint8List.fromList(secret));
  }

  // HERE STOOD `forgetStandingSecret(Uint8List)` — the withdrawal of ONE
  // secret. It was dropped without replacement, and the reason belongs
  // here so that it does not come back:
  //
  // In `lib/` it had ZERO callers, and necessarily so. The only
  // consumer is `CleonaService.armV41InviteLines`, and it deliberately
  // does not work with a reconciliation but sets the set completely
  // anew (first [clearStandingSecrets], then enter the still valid ones
  // again). The reasoning is there: a reconciliation would have two paths
  // on which a withdrawal can be forgotten, and a forgotten
  // withdrawal is a write right into the inbox (§15.1).
  //
  // `smoke_tagline_lab_only_guard` found it on 01.09. — a test
  // is not a consumer. The property it was supposed to establish
  // (§15.3.3: a revoked invitation loses its line) holds without
  // it and is measured in `smoke_v41_erstkontakt` against [clearStandingSecrets].

  /// Throws away all standing secrets.
  ///
  /// The caller then enters the still valid ones again. That is
  /// cheaper and safer than a reconciliation: a forgotten withdrawal
  /// would be silent, a forgotten entry is visible as a missing
  /// request.
  void clearStandingSecrets() => _standing.clear();

  /// How many cells could not be opened. Counted, never logged
  /// (E-83) — with a cover stream that is the normal case, not an
  /// error.
  int unopened = 0;

  /// How many capsules were adopted.
  int capsulesLearned = 0;

  /// How many cells the PREVIOUS generation opened (§4.5.4).
  ///
  /// The measure of the fallback: without it it could not be proven that
  /// it is entered at all. > 0 means „messages arrived here
  /// that would have been silently lost before S362".
  int openedWithPreviousKey = 0;

  /// How many cells were addressed to ME and still stayed closed.
  ///
  /// ── THE SILENT LOSS GETS A NAME (S362) ───────────────────
  ///
  /// [unopened] is unfit for that: it counts every cover and
  /// foreign cell too, and that is the normal case. [unresolvedSelectors]
  /// is unfit too — it counts the cells whose selector fitted NONE
  /// of my keys, i.e. again predominantly foreign traffic.
  ///
  /// THIS counter separates the one case that is a finding: the
  /// selector hit one of my candidates (one-time prekey,
  /// current or previous long-lived key), the
  /// Diffie-Hellman ran — and afterwards no secret made the AEAD
  /// hold. That is „found, not opened": either a cell
  /// against a generation I no longer hold (the one before the previous or
  /// older), or a corrupted ciphertext.
  ///
  /// Exactly this quantity was missing when the management class was built:
  /// the harvest fetched the cell, the opener discarded it, and in the field it
  /// looked like silence. Counted, never logged (E-83).
  int sealedForMeButUnopened = 0;

  MessageOpener({
    required this.ownMlKemSecret,
    required this.ownX25519Secret,
  });

  int get knownSecrets => _secrets.length;

  /// The own long-lived X25519 PUBLIC, cached.
  ///
  /// ── WHY THE OPENER NOW NEEDS IT ────────────────────────────
  ///
  /// In version A the long-lived key could be recognised by a reserved
  /// mark; the opener only needed the secret. In
  /// version B it is a candidate like any other, so the opener must compute
  /// `SHA-256(pk ‖ eph_pk)` over ITS own public part
  /// — and it does not hold that, it only holds `sk`.
  ///
  /// ── WHY CACHE, AND WHY WITH A CHECK ────────────────
  ///
  /// `pk = X25519(sk, base point)` costs 37.76 us (measured). Computed per cell
  /// that would be exactly the scalar multiplication the selector
  /// is supposed to save — the opener would then pay it for EVERY cover cell.
  /// So compute once and keep.
  ///
  /// Once FOR EVER would however be wrong: the long-lived keys
  /// ROTATE. `smoke_device_revocation_rotates.dart:253` measures exactly that
  /// — after a device revocation the fallback delivers the just
  /// rotated key (§14.10). A blind cache would
  /// then compare against the old `pk`, no selector would hit any more,
  /// and EVERY first-contact message would silently fail. That is why the
  /// remembered `sk` is carried along and compared per cell: 32 byte comparisons
  /// against 37.76 us, and the rotation takes effect at the next call.
  Uint8List _staticSk = Uint8List(0);
  Uint8List _staticPk = Uint8List(0);

  Uint8List _ownX25519Public() {
    final sk = ownX25519Secret();
    if (_staticPk.isNotEmpty && _sameBytes(_staticSk, sk)) {
      return _staticPk;
    }
    _staticSk = Uint8List.fromList(sk);
    _staticPk = SodiumFFI().x25519ScalarMult(sk, _basepoint);
    return _staticPk;
  }

  // The same cache for the PREVIOUS generation, for the same
  // reason: without it the second candidate would cost per cover cell a
  // scalar multiplication (42.62 us measured) instead of a SHA-256 probe
  // (0.920 us) — and thus exactly what the selector saves. With it
  // it costs 32 byte comparisons and one hash.
  Uint8List _predecessorSk = Uint8List(0);
  Uint8List _predecessorPk = Uint8List(0);

  /// The public part of the PREVIOUS generation, or `null` if there
  /// is none (never rotated / period expired).
  Uint8List? _previousX25519Public() {
    final sk = previousX25519Secret?.call();
    if (sk == null || sk.length != 32) return null;
    if (_predecessorPk.isNotEmpty && _sameBytes(_predecessorSk, sk)) {
      return _predecessorPk;
    }
    _predecessorSk = Uint8List.fromList(sk);
    _predecessorPk = SodiumFFI().x25519ScalarMult(sk, _basepoint);
    return _predecessorPk;
  }

  void _remember(Uint8List ss, DateTime now) {
    for (final s in _secrets) {
      if (_sameBytes(s.secret, ss)) return;
    }
    _secrets.add(_DailySecret(ss, now));
    capsulesLearned++;
    if (_secrets.length > maxSecrets) _secrets.removeAt(0);
  }

  /// Throws away what is older than [secretRetention].
  ///
  /// WHERE IT RUNS and why not per cell: the call hangs on the
  /// second window of [open] (see there) and on [loadJson]. Per cell
  /// it would be a `removeWhere` over up to 256 records in the DoS path — for
  /// a period that measures in DAYS, that would be a precision
  /// no one needs, at the most expensive place in the program.
  ///
  /// A CLOCK THAT JUMPS BACK MUST NOT THROW ANYTHING AWAY, and one that
  /// jumps forward must not make anything immortal: a record from the future
  /// is brought back to [now] instead of discarded. Brought back and not
  /// discarded, because a wrongly set clock is no reason to take
  /// delivery away from the counterpart.
  void _expiredDiscard(DateTime now) {
    final before = _secrets.length;
    for (var i = 0; i < _secrets.length; i++) {
      if (_secrets[i].learnedAt.isAfter(now)) {
        _secrets[i] = _DailySecret(_secrets[i].secret, now);
      }
    }
    _secrets.removeWhere((s) => now.difference(s.learnedAt) > secretRetention);
    expiredSecretsDropped += before - _secrets.length;
  }

  /// How many daily secrets the retention period has thrown away.
  ///
  /// The counterpart of `V41Host.expiredPrekeysSwept` and kept for the same
  /// reason: a stock that silently shrinks looks in the field
  /// exactly like one that was never filled.
  int expiredSecretsDropped = 0;

  /// How many daily secrets [loadJson] has taken over.
  int secretsLoaded = 0;

  // ────────────────────── THE STOCK ACROSS A RESTART ──────────────
  //
  // WHAT THIS INTERFACE DELIBERATELY DOES NOT KNOW: files, paths,
  // keys, `FileEncryption`. It supplies and takes a map
  // or a string; where that goes and what it is sealed with
  // is decided by the construction site (`v41_attach.dart`). The reason is
  // the same for which `EntryRecordStore` keeps it this way: the delivery layer
  // runs in the daemon, in the app and in the lab, and each of these three
  // environments stores differently. A class that writes itself would have
  // a special path at all three.
  //
  // PLAINTEXT DOES NOT OCCUR HERE — the result is Base64, but Base64
  // is not encryption, and the caller MUST store it
  // encrypted. Why that is still defensible is explained at
  // [secretRetention]: the KEM key from which the same
  // secrets can be recovered lies encrypted in the
  // profile anyway.

  /// The stock as a map — expired records are already out.
  Map<String, Object?> toJson({DateTime? now}) {
    final current = now ?? DateTime.now();
    _expiredDiscard(current);
    return {
      'v': 1,
      's': [
        for (final s in _secrets)
          {
            'k': base64Encode(s.secret),
            't': s.learnedAt.toUtc().millisecondsSinceEpoch,
          }
      ],
    };
  }

  String toJsonString({DateTime? now}) => jsonEncode(toJson(now: now));

  // ── ONLY STORE WHEN SOMETHING HAS CHANGED (S366) ───────────────
  //
  // MEASURED why this is needed: `v41_attach.dart` stored this stock
  // UNCONDITIONALLY in a 30-second cycle — 2880 encryptions
  // and 2880 writes per day, almost all of them with the same
  // content. The supply right next to it has always done it right
  // (`schmutzig`/`prekeyStateDirty`).
  //
  // THE PLAINTEXT IS COMPARED, NOT THE CIPHERTEXT. `FileEncryption`
  // is XSalsa20-Poly1305 with a fresh nonce per run; two ciphertexts
  // of the same content differ, a comparison on them would always
  // say „changed" and save nothing.
  //
  // NO SECOND DIRTY MARK, and that is the point. At this place
  // stood the reasoning that there is deliberately no mark here, because a
  // second place with a forgotten `markiere…()` means silent
  // loss. The objection stays valid — that is why it is NOT a flag that
  // every writer of the secrets would have to set, but a comparison
  // on the state itself. No one can forget a comparison.

  /// The last CONFIRMED stored state, encoded.
  ///
  /// `null` means „nothing stored in this run yet" — the first cycle
  /// then writes once, even if nothing was learned. That is
  /// intended: [loadJson] throws away expired items on loading, but the version
  /// on disk still carries them.
  String? _depositedState;

  /// The state to store — or `null` if it has not changed since the last
  /// confirmed store.
  ///
  /// Calls [toJson] and thus `_verfalleneWegwerfen` in EVERY call: the
  /// cycle keeps its second purpose (expiry), even if it writes nothing
  /// any more.
  Map<String, Object?>? changedState({DateTime? now}) {
    final j = toJson(now: now);
    if (jsonEncode(j) == _depositedState) return null;
    _depositsHandedOut++;
    return j;
  }

  /// To be called after SUCCESSFUL writing, with the state that
  /// was written.
  ///
  /// Only here is the comparison value set — a failed
  /// write leaves it standing, and the next cycle tries
  /// again. If it were already set in [changedState], a
  /// write error would be silent loss until the next change.
  void depositConfirmed(Map<String, Object?> state) {
    _depositedState = jsonEncode(state);
  }

  /// How often [changedState] has handed out a state — the number
  /// of WRITES this stock causes.
  ///
  /// For the guard: it measures the statement („with unchanged content
  /// nothing is written") and not the proxy „the timer has
  /// ticked".
  int get depositsHandedOut => _depositsHandedOut;
  int _depositsHandedOut = 0;

  /// Loads what [toJson] supplied.
  ///
  /// SUPPLEMENTING, NOT REPLACING — the same choice as for
  /// `EntryRecordStore.loadJson`. At start the stock is empty, and
  /// whoever loads later does not want a just learned secret
  /// to disappear.
  ///
  /// OLDEST FIRST, so that the cap keeps the YOUNGEST: [_remember]
  /// displaces at the front. If the order were random, with
  /// a full stock chance would decide which contact can still be opened
  /// after the restart.
  ///
  /// UNREADABLE ITEMS ARE SILENTLY SKIPPED. A damaged stock must not prevent the
  /// start — the price is exactly the state from before
  /// (empty stock), and that is survivable, because the sender then
  /// sends the capsule along again.
  void loadJson(Map<String, Object?> j, {DateTime? now}) {
    if (j['v'] != 1) return;
    final list = j['s'];
    if (list is! List) return;
    final current = now ?? DateTime.now();
    final loaded = <_DailySecret>[];
    for (final item in list) {
      if (item is! Map) continue;
      final k = item['k'];
      final t = item['t'];
      if (k is! String || t is! int) continue;
      Uint8List raw;
      try {
        raw = base64Decode(k);
      } catch (_) {
        continue;
      }
      if (raw.isEmpty) continue;
      loaded.add(_DailySecret(
          raw, DateTime.fromMillisecondsSinceEpoch(t, isUtc: true)));
    }
    loaded.sort((a, b) => a.learnedAt.compareTo(b.learnedAt));
    for (final s in loaded) {
      // Not via [_remember]: the record brings its own age along,
      // and `capsulesLearned` counts RECEIVED capsules — a loaded
      // stock is not a received capsule, and counting it along would let
      // the number claim that traffic had flowed.
      if (current.difference(s.learnedAt) > secretRetention) {
        expiredSecretsDropped++;
        continue;
      }
      var know = false;
      for (final v in _secrets) {
        if (_sameBytes(v.secret, s.secret)) {
          know = true;
          break;
        }
      }
      if (know) continue;
      _secrets.add(s);
      secretsLoaded++;
      if (_secrets.length > maxSecrets) _secrets.removeAt(0);
    }
  }

  /// Loads what [toJsonString] wrote.
  void loadJsonString(String s, {DateTime? now}) {
    try {
      final j = jsonDecode(s);
      if (j is! Map) return;
      loadJson(j.cast<String, Object?>(), now: now);
    } catch (_) {
      // silent — see [loadJson].
    }
  }

  /// How many full passes per second are computed at most.
  ///
  /// WITHOUT THIS CAP, TRYING IS A COMPUTE DoS. Every cell that
  /// could not be assigned to a relay role lands here, and with garbage
  /// every candidate fails — so the full pass is ALWAYS
  /// paid. A partner sending at line rate would otherwise force
  /// unlimited work. `ReplyBlockResolver` caps its trying for
  /// exactly this reason; here the cap was missing.
  ///
  /// ── SINCE VERSION B THE CAP COVERS MORE, AND IT WAS NOT
  ///    ADJUSTED ────────────────────────────────────────────────────
  ///
  /// The „full pass" on garbage is a different one than until 30.08.
  /// The counter selector failed at a map lookup, i.e. close to
  /// zero; the hash selector costs one SHA-256 over 64 B per candidate
  /// (measured 0.947 us), and candidates are all unused prekeys
  /// of all supplies plus the long-lived key. With 20 contacts that is
  /// 160..320, making 152..303 us per cell — at 2000 cells per
  /// second about **0.6 core-seconds per second**.
  ///
  /// Decided on 30.08. (owner, version C): **the cap lies on
  /// the WORK, not on the calls.** It stays as a coarse outer
  /// bolt — it costs nothing and also limits a node with a
  /// tiny supply —, but the load-bearing limit is
  /// [maxProbesPerSecond].
  static const int maxAttemptsPerSecond = 2000;

  /// How many candidate probes per second are computed at most.
  ///
  /// ── WHY THE LIMIT LIES ON THE WORK AND NOT ON THE CALLS
  ///    (owner decision, 30.08., version C) ─────────────────
  ///
  /// A call cap is a constant number, but the cost per call is
  /// linear in the NUMBER OF CONTACTS: candidates are all unused
  /// prekeys of all supplies plus the long-lived key. At 2000
  /// calls per second that makes 0.3-0.6 core-seconds per second at
  /// 20 contacts — and **3.0 at 100**. The protection thus became weaker
  /// exactly where it is needed, and above one core the DoS
  /// succeeds THROUGH the cap: the node additionally loses
  /// its slot cycle (`driver.slotsSkipped`).
  ///
  /// What is protected is computing time, so the limit belongs on computing time.
  /// **52 000 probes per second** are, at a measured 0.947 us per probe,
  /// about **49 ms/s, i.e. 5 % of a core** — the share set by the owner.
  /// What that allows in cells per number of contacts:
  ///
  ///   5 contacts (~80 candidates)   -> ~650 cells/s
  ///   20 contacts (~320)            -> ~165 cells/s
  ///   100 contacts (~1600)          -> ~33 cells/s
  ///
  /// Against that the legitimate load, re-measured: `PartnerPolicy.target` = 4
  /// partners times one cell per 8 s = **0.5 cells/s**, in the aggregate
  /// structurally up to 32 calls/s (`Aggregate.maxEntries` = 64, in the
  /// regular case one entry per cell). The headroom is thus even in the tightest
  /// case (100 contacts) still an order of magnitude.
  ///
  /// SETTLED IN ADVANCE, not afterwards: the probe is rejected
  /// BEFORE it is computed. Afterwards the bill would already be
  /// paid, and a cap that only applies after the work is none.
  static const int maxProbesPerSecond = 52000;

  int _window = 0;
  int _inWindow = 0;
  int _probesInWindow = 0;

  /// How many candidate probes are used up in the current window.
  int get probesThisSecond => _probesInWindow;

  /// How many cells the cap has rejected.
  int throttled = 0;

  /// Opens what [MessageSealer.seal] built — or returns `null`.
  ///
  /// `null` is the MOST FREQUENT answer and not an error: dummy cells and
  /// cells of foreign pairs look exactly the same here.
  Uint8List? open(Uint8List sealed, {DateTime? now}) {
    final nowDt = now ?? DateTime.now();
    final current = nowDt.millisecondsSinceEpoch ~/ 1000;
    if (current != _window) {
      _window = current;
      _inWindow = 0;
      _probesInWindow = 0;
      // AT THE WINDOW CHANGE, not per cell: the retention period measures in
      // days, checking at most once per second is exactly
      // enough and costs nothing in the DoS path. A node that receives
      // nothing at all never trims here — for it [toJson] does it at the
      // next save.
      _expiredDiscard(nowDt);
    }
    if (_inWindow >= maxAttemptsPerSecond) {
      throttled++;
      return null;
    }
    // THE WORK OF THIS CELL, IN ADVANCE. `candidateCount` says how expensive the
    // full pass would be; if it no longer fits into the per-second budget,
    // nothing is computed at all. If the callback is missing, the cell counts as
    // one candidate — then the cap behaves like the old one.
    //
    // THE PREDECESSOR COUNTS TOO (§4.5.4, S362). `candidateCount` comes from the
    // host and sums the unused prekeys plus the current
    // long-lived key — the predecessor it does not know, that belongs to
    // the opener. Without this `+1` the cap would compute with too
    // small a number and protect less computing time than a cell
    // really costs; a cap that underestimates the work is
    // just as broken as one that applies too late.
    final candidates =
        (candidateCount?.call() ?? 1) + (_previousX25519Public() != null ? 1 : 0);
    if (_probesInWindow + candidates > maxProbesPerSecond) {
      throttled++;
      return null;
    }
    _probesInWindow += candidates;
    _inWindow++;

    const header = PrekeySelector.bytes;
    if (sealed.length <= header + 44 + 16) {
      unopened++;
      return null;
    }

    // ── FIRST DETERMINE THE PREKEY, THEN COMPUTE (§4.6) ─────────────────
    //
    // The order is the whole gain of the selector, and it stays
    // unchanged in version B: first the candidate probe (per candidate one
    // SHA-256 over 64 B, measured 0.947 us), then — only on a
    // hit — the scalar multiplication (37.76 us) and if applicable the
    // decapsulation. A foreign cover cell is still discarded WITHOUT
    // scalar multiplication.
    //
    // TWO CANDIDATE GROUPS, NO SPECIAL CASE. First the unused
    // one-time prekeys (the regular case), then the long-lived key
    // (step 3 of the fallback ladder, §4.6). The order is a
    // question of cost and not of meaning — both are checked with the same
    // formula, and on the wire the fallback cannot be recognised
    // by anything. That was exactly the purpose of the rebuild.
    //
    // FIRST HIT WINS. With 4 B a wrong candidate hits with
    // 2^-32; the cell would then not be openable. A second attempt
    // with the next candidate would again be the trying through that
    // §4.6 excludes — the price is one lost message per about
    // four billion candidate checks, and it is knowingly paid.
    final selector = Uint8List.sublistView(sealed, 0, header);
    final ephView = Uint8List.sublistView(sealed, header, header + 32);
    final int? onceIndex;
    final Uint8List sk;
    //
    // THIRD CANDIDATE SINCE S362: THE PREVIOUS GENERATION (§4.5.4). It
    // stands LAST, and the order is again a question of cost:
    // the regular case is the current key, the predecessor only carries
    // what was sealed between two rotations and harvested late.
    // It costs the same one SHA-256 probe as any other
    // candidate and cannot be recognised on the wire by anything.
    final hit = oneTimeSecret?.call(selector, ephView);
    final predecessorPk = _previousX25519Public();
    // Whether THIS cell came in via the previous generation. Only carries the
    // counter [openedWithPreviousKey]; the computation below is the same.
    var viaPredecessor = false;
    if (hit != null) {
      sk = hit.secret;
      onceIndex = hit.index;
    } else if (PrekeySelector.matches(selector, _ownX25519Public(), ephView)) {
      sk = ownX25519Secret();
      onceIndex = null;
    } else if (predecessorPk != null &&
        PrekeySelector.matches(selector, predecessorPk, ephView)) {
      // `_previousX25519Public()` delivered a value, so
      // `previousX25519Secret` delivers one too — the `!` is not an assumption
      // but the same condition.
      sk = previousX25519Secret!.call()!;
      onceIndex = null;
      viaPredecessor = true;
    } else {
      unresolvedSelectors++;
      unopened++;
      return null;
    }

    // The selector is AEAD-bound: whoever bends it in transit to another
    // prekey destroys the checksum. Without this binding it would be
    // an unauthenticated field in the header of an authenticated cell.
    // These are THE SAME bytes as above — until 30.08. there was a
    // second view `aad` on the same range here, which gave the impression
    // that preselection and binding could diverge. They cannot;
    // it is one variable.
    final aad = selector;

    // THE DIFFIE-HELLMAN ONCE, NOT PER CANDIDATE.
    //
    // `dh = X25519(own_sk, eph)` depends EXCLUSIVELY on the own
    // key and on the ephemeral part of THIS cell — not on the
    // daily secret being tried against. The first version
    // computed it in the candidate loop and paid, with 20 contacts,
    // 20 scalar multiplications (37.4 us each) where one suffices: ~32 s
    // of computing time per day instead of ~1.6 s. The bug was all the more expensive as it
    // sat right in the DoS path.
    final Uint8List dh;
    try {
      final eph = Uint8List.fromList(sealed.sublist(header, header + 32));
      dh = SodiumFFI().x25519ScalarMult(sk, eph);
    } catch (_) {
      // The selector hit, so the cell was addressed to me —
      // it counts in [sealedForMeButUnopened], not only in [unopened].
      sealedForMeButUnopened++;
      unopened++;
      return null;
    }

    // 1a. THE INVITATION LINES FIRST (§15.4). A contact request carries
    //     NO capsule — its `ss_pq` is derived from `K_inv(i)`
    //     (`invite_line.dart`, `inviteSealSecret`). Step 2 can thus
    //     never open it, and without this branch first contact silently
    //     falls through.
    //
    //     BEFORE the daily secrets, because the set is small and capped
    //     (at most [maxStandingSecrets]), while [_secrets] carries up to 256
    //     entries. The order is a question of cost and not
    //     of meaning: the AEAD decides, and there cannot be two
    //     hits.
    for (final ss in _standing) {
      final onto = _attempt(sealed, 0, ss, dh, aad);
      if (onto != null) return _opened(onto, onceIndex, viaPredecessor);
    }

    // 1. With what is already known — short form, without capsule field.
    //    SINCE 30.08. THIS STOCK SURVIVES A RESTART, provided
    //    the construction site saves it ([toJsonString]/[loadJsonString]).
    //    Without that it was empty after every start, and because the sender
    //    leaves out the capsule against its proof, everything fell through here —
    //    step 2 did not apply because there was no capsule field.
    for (final ss in _secrets) {
      final onto = _attempt(sealed, 0, ss.secret, dh, aad);
      if (onto != null) return _opened(onto, onceIndex, viaPredecessor);
    }

    // 2. Long enough for a capsule? Then read the 1088 B behind the
    //    ephemeral key as ciphertext. A wrong interpretation
    //    yields a plausible but wrong secret — the AEAD catches
    //    that, therefore no test is needed here whether it „really"
    //    was a capsule.
    //
    //    ── THE BATCH NAMES THE KEY (E1, S363) ──────────────
    //
    //    If the selector hit a ONE-TIME PREKEY and it carries
    //    a batch ML-KEM, then the capsule key is thereby fixed:
    //    **exactly one decapsulation**, without generation loop. That is
    //    the core of E1 — the PQ key hangs on the batch, not on
    //    a clock, and the question „which generation was that?" no longer
    //    arises for these cells at all.
    //
    //    ── WHY THE GENERATION LOOP STAYS NEVERTHELESS ──────
    //
    //    It now carries exactly two situations, and in both the sender
    //    really encapsulated against the IDENTITY KEM:
    //
    //      * **Step 3 of the fallback ladder** (§4.6) — the selector hit
    //        the long-lived key, not a
    //        one-time prekey. That is every first message of a pair,
    //        every message with an exhausted supply, and since E3 EVERY
    //        CONTROL CELL (it runs under the pair anchor).
    //      * **A stored item from the time before E1** — the prekey carries
    //        no batch KEM (`mlKemSk == null`).
    //
    //    Removing it while the routine rotation of the
    //    identity KEM is still running (that is E2, not built) would take away
    //    exactly the fallback that §4.5.4 demands verbatim: „the
    //    receiver first attempts unsealing with the current keys and, on
    //    `kemDecapFailed`, with the previous ones, so that senders who
    //    have not yet harvested the announcement keep getting through."
    //    The price would be silently lost mail exactly for the senders who
    //    have not yet harvested the announcement.
    //
    //    COSTS: for a cell over a one-time prekey **one**
    //    decapsulation (previously up to two). For an anchor/fallback cell
    //    unchanged up to two. For a foreign cover cell none —
    //    that one is already out at the selector above.
    const capsule = MessageSealer.capsuleBytes;
    if (sealed.length > header + 32 + capsule + 12 + 16) {
      final ct = Uint8List.sublistView(sealed, header + 32, header + 32 + capsule);
      final stackKem = hit?.mlKemSk;
      final List<Uint8List?> candidates = stackKem != null
          ? <Uint8List?>[stackKem]
          : <Uint8List?>[ownMlKemSecret(), previousMlKemSecret?.call()];
      // The predecessor is only the second candidate if the
      // identity generations are tried at all.
      var generation = 0;
      for (final kemSk in candidates) {
        final isPredecessor = stackKem == null && generation++ == 1;
        if (kemSk == null) continue;
        try {
          capsuleDecapsulations++;
          final ss =
              OqsFFI().mlKemDecapsulate(Uint8List.fromList(ct), kemSk);
          final onto = _attempt(sealed, capsule, ss, dh, aad);
          if (onto != null) {
            // THE SECRET OF THE PREVIOUS GENERATION IS REMEMBERED TOO. It
            // drops away like any other after [secretRetention] = 7 days
            // and thus does NOT outlive the key it comes from:
            // the previous generation stays according to
            // `IdentityContext.previousKeyRetention` for 32 days.
            _remember(ss, nowDt);
            return _opened(
                onto, onceIndex, viaPredecessor || isPredecessor);
          }
        } catch (_) {
          // No reason to complain — it simply was not a capsule of this
          // generation. The next candidate gets its turn anyway; a
          // `return` here would be exactly the abort that §4.5.4 excludes.
        }
      }
    }

    // FOUND, NOT OPENED. The selector hit above — this
    // cell was addressed to me, and still no secret opened
    // it. Until S362 this path ended only in [unopened] and was
    // thus indistinguishable from a foreign cover cell; exactly
    // for that reason the loss of the management class stayed invisible in the field.
    sealedForMeButUnopened++;
    unopened++;
    return null;
  }

  /// The one exit from [open] at which the prekey is consumed.
  ///
  /// ONE exit, not two: the short and the capsule-carrying form
  /// both end here. Two deletion sites would be two opportunities to forget
  /// one — and a forgotten deletion is a silent,
  /// permanent cancellation of forward secrecy that no test
  /// notices, because the message does arrive.
  /// [onceIndex] is `null` if the long-lived key
  /// held — then there is nothing to delete, and §4.6 says so too:
  /// step 3 of the ladder has no per-message forward secrecy.
  /// [viaPredecessor] says whether the PREVIOUS KEM generation held —
  /// either as selector candidate or as capsule key (§4.5.4).
  /// Only [openedWithPreviousKey] hangs on it; it changes nothing
  /// about the plaintext.
  Uint8List _opened(
      Uint8List plaintext, int? onceIndex, bool viaPredecessor) {
    if (onceIndex != null) {
      oneTimeOpened++;
      oneTimeUsed?.call(onceIndex);
    }
    if (viaPredecessor) openedWithPreviousKey++;
    return plaintext;
  }

  /// An opening attempt with a given daily secret and capsule offset.
  ///
  /// [dh] comes in ready-made — see [open]: it does not hang on the
  /// candidate and therefore must not be computed per candidate.
  /// [aad] are the selector bytes against which the sender sealed.
  Uint8List? _attempt(Uint8List sealed, int capsuleLen, Uint8List ssPq,
      Uint8List dh, Uint8List aad) {
    const header = PrekeySelector.bytes;
    if (sealed.length <= header + 32 + capsuleLen + 12 + 16) return null;
    try {
      final o = header + 32 + capsuleLen;
      final nonce = Uint8List.fromList(sealed.sublist(o, o + 12));
      return SodiumFFI().aesGcmDecrypt(
        Uint8List.fromList(sealed.sublist(o + 12)),
        MessageSealer.combineForOpen(ssPq, dh),
        nonce,
        ad: aad,
      );
    } catch (_) {
      return null;
    }
  }
}
