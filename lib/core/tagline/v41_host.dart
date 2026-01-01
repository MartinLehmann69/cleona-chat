import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/sync/cover_stream.dart' show kAggregationBudgetBytes;

import '../crypto/constant_time.dart';
import '../crypto/oqs_ffi.dart';
import '../crypto/sodium_ffi.dart';
import 'delivery_api.dart';
import 'device_line.dart';
import 'harvest_horizon.dart';
import 'frame_split.dart';
import 'message_seal.dart';
import 'lan_entry_wiring.dart';
import 'own_line.dart';
import 'prekey_pool.dart';
import 'package:cleona/core/bulk/responsibility.dart' show kEpochSeconds;

/// What a single piece on the wire may carry.
///
/// Not the delivery's `maxPayloadBytes`: a Speed payload is
/// AGGREGATED (`aggregate.dart`), and the aggregate costs a 3 B header plus
/// 2 B length per entry. Whoever fills up to the delivery limit builds a
/// piece that can no longer be fitted into the aggregate — and the
/// cover stream then silently lets it run in circles, because `Aggregate.pack`
/// returns `null` and the entry never leaves the slot.
const int kMaxPieceBytes = kAggregationBudgetBytes - 5;

/// Length of the sender MAC that precedes every application frame.
///
/// 32 B — the full output of HMAC-SHA-256. Not truncated: the MAC is
/// the ONLY sender information in Speed mode (§4.3: "in Speed-Mode there
/// is **no field tag**"), and 16 B would be the entire
/// sender authenticity there.
const int kV41SenderMacBytes = 32;

/// The domain separation of the sender MAC.
///
/// `K_AB` carries SEVERAL tags in this layer — `secureTag`,
/// `livenessTag`, `pairAnchor`. Two derivations from the same root
/// must never yield the same value, otherwise one tag would reveal something
/// about the other. The domain is therefore fixed here and
/// not passed in.
const String kV41SenderMacContext = 'cleona-v41/sender/v1';

/// The sender MAC of an application frame (§4.4.3).
///
/// `HMAC-SHA-256(K_AB, "cleona-v41/sender/v1" ‖ frame)`.
///
/// ── WHAT IT PROVIDES AND WHAT NOT ────────────────────────────────────
///
/// **It provides sender authenticity.** Exactly two parties hold `K_AB`
/// (§15.2: from the founding keys of both sides). Whoever does not
/// have it cannot form the MAC — a freely claimed
/// `senderUserId` thus fails, and without any graded trust:
/// the frame is discarded. This is the replacement for B-20.
///
/// **It provides frame integrity.** It covers the WHOLE
/// application frame, and that names sender AND receiver. It is thus
/// also direction-bound: the same MAC under the same `K_AB` is valid
/// only for exactly this assignment.
///
/// **It provides NO non-repudiation — and that is the purpose.**
/// Both sides of the pair can produce it. The receiver can therefore
/// present nothing to a third party that the sender could not just as well
/// have built himself. §4.4.3: "Cleona is deniable."
///
/// **The limit, named rather than concealed:** `K_AB` arises from an
/// X25519 Diffie-Hellman of the founding keys
/// (`deriveDeliveryPairKeyFromFounding`). The MAC itself is symmetric
/// and thus post-quantum-secure; ITS KEY is not. Whoever breaks the
/// classical DH can forge senders. This is no disadvantage
/// compared with the superseded Ed25519 signature — it stood on the same
/// classical curve —, but the sentence from §4.4.3 ("and thus
/// post-quantum-securely") holds for the MAC, not for `K_AB`.
Uint8List v41SenderMac({
  required Uint8List kAb,
  required Uint8List frame,
}) {
  final ctx = utf8.encode(kV41SenderMacContext);
  final input = Uint8List(ctx.length + frame.length)
    ..setRange(0, ctx.length, ctx)
    ..setRange(ctx.length, ctx.length + frame.length, frame);
  return SodiumFFI().hmacSha256(kAb, input);
}

/// How the sender check of a V4.1 frame turned out.
enum V41SenderVerdict {
  /// The MAC holds under the pair key of the claimed sender,
  /// and — if a tag line was present — it names the same one. The sender
  /// is established.
  verified,

  /// No pair key at hand: the claimed sender is not a
  /// contact, or his founding key is not available. That is the
  /// situation at FIRST CONTACT and not an error — the frame continues with
  /// the state "unknown sender" (`SenderTrust.unknownKey`), exactly
  /// as in the V3 path.
  unverifiable,

  /// The claimed sender is not the real one. Discard.
  forged,
}

/// Checks whether an application frame really comes from the one it names.
///
/// THE ONE PLACE where this rule stands — it is the replacement for the
/// superseded Ed25519 signature (§4.4.3) and must therefore be at least as
/// strict as that. It is so at two independent points:
///
/// **1. The tag line** ([peer], only in the Secure path). The pair identifier
/// `<own64>/<foreign64>` comes from the harvest: the cell lay under
/// `secureTag(K_AB, …)`, and this tag cannot be computed without `K_AB`.
/// If the frame names a different sender than the tag line, someone has
/// placed a frame with a third name under the tag of the pair A/B.
///
/// **2. The MAC** (always). `HMAC(K_AB, context ‖ frame)` — whoever does not
/// have `K_AB` does not form it. It is checked against the pair key of the
/// CLAIMED sender, not against all known ones: a false
/// claim fails precisely because of that, and trying them all through would
/// be neither necessary nor cheaper.
///
/// **Why the tag line does not replace the MAC.** On placement the tag travels
/// in plaintext to the responsible relay — it MUST see it in order to
/// store under it. A relay that has seen a placement therefore knows
/// the tag and could place something under it itself. What it cannot
/// do: form the MAC. The MAC is thus the stronger of the two
/// pieces of information, and the tag line is the second opinion.
///
/// **Why the MAC does not replace the tag line.** It is the only
/// information available BEFORE unsealing, and it binds the cell to
/// this identity — on a node with several identities that is
/// not the same as "addressed to me".
/// [ownDeviceLine] is the identifier of the OWN device line of this
/// identity (`deviceLineKey(userId, deviceNodeId)`), or `null` if
/// the caller cannot form one. It is ONLY needed if [peer] is a
/// device line — see the exception in the body.
V41SenderVerdict verifyV41Sender({
  required String peer,
  required String ownUserIdHex,
  required String senderUserIdHex,
  required Uint8List? kAb,
  required Uint8List mac,
  required Uint8List frame,
  String? ownDeviceLine,
}) {
  // ── THE OWN LINE IS THE ONE EXCEPTION (§14.7, G-14) ───────────
  //
  // A twin sync comes in under `own:<own64>`, not
  // under `<own64>/<foreign64>` — there is no counterpart, only the same
  // identity on another device. The tag-line information is
  // therefore a DIFFERENT one here, but it is not weaker: only the own,
  // non-locked-out devices hold `K_own` (§14.4), and the
  // cell lay under `secureTag(K_own, …)`.
  //
  // KEPT STRICT: the frame MUST name the own identifier as sender.
  // A frame that lies on the own line and names a
  // stranger is exactly the case this function stands against —
  // it fails here, not later. And the MAC is still checked
  // unchanged below: for this case the caller passes in `K_own`
  // as [kAb].
  // ── THE DEVICE LINE IS THE SECOND EXCEPTION (§14.1, §14.7) ────────
  //
  // A delivery that differs PER DEVICE comes in under
  // `dev:<own64>/<device64>`. Here too there is no counterpart
  // — it is the same identity on another device —, and the
  // MAC key is the root of this line (`deriveKDevice`), not
  // `K_AB`.
  //
  // THE CHECK IS AGAINST THE OWN LINE, NOT AGAINST THE PREFIX. A
  // comparison that only required `dev:` and the own identifier would
  // let through a frame that lay on the line of a SISTER. The case
  // is not reachable today (foreign device lines are not
  // harvested, `PairRegistry.isPlaceOnly`), but it is exactly such
  // proxy checks that later silently turn wrong.
  //
  // WITHOUT [ownDeviceLine] THE FRAME FAILS. A caller that cannot form the
  // own device line also cannot say that
  // this cell is meant for it — then discarding is the answer, not
  // waving it through.
  if (isDevicePeer(peer)) {
    if (ownDeviceLine == null ||
        peer != ownDeviceLine ||
        senderUserIdHex != ownUserIdHex) {
      return V41SenderVerdict.forged;
    }
  } else if (isOwnPeer(peer)) {
    // Compared at the HEX level, not via `ownPeerKey` with
    // a back-conversion: `ownUserIdHex` already is the string
    // from which `ownPeerKey` builds its identifier. A detour via bytes
    // and back could differ in upper/lower case
    // and would be a second truth about the same thing.
    if (senderUserIdHex != ownUserIdHex ||
        peer != '$kOwnPeerPrefix$ownUserIdHex') {
      return V41SenderVerdict.forged;
    }
  } else if (peer.isNotEmpty && peer != '$ownUserIdHex/$senderUserIdHex') {
    return V41SenderVerdict.forged;
  }
  if (kAb == null) return V41SenderVerdict.unverifiable;
  return constantTimeEquals(v41SenderMac(kAb: kAb, frame: frame), mac)
      ? V41SenderVerdict.verified
      : V41SenderVerdict.forged;
}

/// What is inside a V4.1 payload.
///
/// One byte, and it has to be: application frames AND prekey refills
/// travel over the same path. Without a marker the
/// receiver would have to guess, and guessing here would mean: interpreting a frame as
/// a key supply.
abstract final class V41Kind {
  /// An application frame. Body: `senderMac(32) ‖ ApplicationFrameV3`.
  ///
  /// ── AN ED25519 SIGNATURE STOOD HERE, AND IT HAD TO GO (S352) ───
  ///
  /// The problem it solved is real and remains (B-20, S349): the
  /// AEAD of the sealing only proves that SOMEONE sealed against the
  /// public keys of the receiver. Whoever knows them
  /// — and they are public — builds a frame with an arbitrary
  /// `senderUserId`, and the receiver reads it as genuine.
  ///
  /// The signature solved it with the wrong tool. §4.4.3 is
  /// normative and says it twice: "1:1 message — **none**", "Group leg
  /// (pairwise) — **none**", and in addition "**Cleona is deniable.** Without a
  /// signature in the message path, no receiver can prove to a third
  /// party that a specific person said something." An Ed25519 signature
  /// over the frame is exactly this proof — TRANSFERABLE, permanent,
  /// verifiable by any third party. The receiver thus held a
  /// piece of evidence against the sender that the protocol expressly
  /// does not want to issue.
  ///
  /// **What takes its place is in the same line of §4.4.3:**
  /// "the tag `HKDF(K_AB, …)` authenticates the sender symmetrically and
  /// thus post-quantum-securely". The MAC under the PAIR KEY achieves
  /// the same as the signature — whoever does not have `K_AB` cannot
  /// form it, so no `senderUserId` can be freely claimed any more —, but
  /// it proves nothing to a third party: BOTH sides of the pair can
  /// produce it, so the receiver can too. That is exactly
  /// deniability.
  ///
  /// It lies UNDER the seal, at the same place as the signature
  /// before: if it lay above, r2 would see a pair quantity constant over time
  /// and could link cells of the same pair.
  static const int appFrame = 0x01;
  static const int prekeyRefill = 0x02;

  /// Length of the sender MAC before the frame.
  static const int senderMacBytes = kV41SenderMacBytes;

  // S368: here stood a `@Deprecated` constant named
  // `signature`+`Bytes`, carried since S352 as "TRANSITION, NOT PERMANENT",
  // with the sentence "As soon as both places are switched over, this
  // line goes without replacement." Both are switched over — the size estimate of the
  // switch in `cleona_service.dart` and `smoke_v41_ack_offpath.dart` —,
  // so it goes. The name was wrong (there is no signature any more), the
  // number was right because it pointed to `senderMacBytes`; now the
  // right name stands there directly.

  static Uint8List wrap(int kind, Uint8List body) {
    final out = Uint8List(1 + body.length);
    out[0] = kind;
    out.setRange(1, out.length, body);
    return out;
  }

  static ({int kind, Uint8List body})? unwrap(Uint8List p) {
    if (p.isEmpty) return null;
    return (kind: p[0], body: Uint8List.sublistView(p, 1));
  }
}

/// Encodes a prekey refill:
/// `count(1) ‖ ml_kem_pk(1184) ‖ [index(4) ‖ x25519(32)]*`
///
/// ══════════════════════════════════════════════════════════════════════
/// THE ML-KEM KEY TRAVELS IN THE BATCH (E1, S363)
/// ══════════════════════════════════════════════════════════════════════
///
/// **Measured:** at B = 16 a batch measures **1761 B** instead of the previous
/// 577 B; the 1184 B are the ML-KEM-768 pubkey OF THIS batch, i.e.
/// 74 B per prekey amortised. It thus no longer fits into one cell
/// (`kMaxPlaceContentBytes` = 1043) — the refill is split like
/// any other payload, and `_sendeVersiegelt` does that anyway since
/// S355.
///
/// **The one-time prekeys stay pure X25519** (§4.6). A HYBRID
/// prekey would have cost 1184 B **per prekey** — 19.5 KB per batch,
/// not even one would have fitted; that is exactly what §4.6 rejected. One
/// pk **per batch** is a different quantity, and the objection does not
/// apply to it.
///
/// **What this buys:** the encapsulation key hangs on the batch and not on
/// the rotation clock of the identity. The selector names the prekey, the
/// prekey its batch, the batch exactly one ML-KEM secret part — one
/// decapsulation per capsule cell, and no announcement that can
/// expire.
///
/// **NO BACKWARD BRANCH.** A batch in the old format (577 B) is
/// no longer read: [decode] returns `null`, `V41Host.accept` counts it
/// in `refillsMalformed` and discards. A reading branch for a format
/// that was never shipped on this line would be built,
/// untrodden code — and the counterpart switches over with the same commit.
///
/// HERE 4 B OF EPOCH STOOD IN FRONT (dropped on 30.08.2026 with version B
/// of §4.6, hence 577 instead of 581). They travelled along because the sender
/// later had to name the epoch in the selector `(epoch, n)`. The
/// hash selector no longer names an epoch, and outside this encoding
/// the field had no reader after the rebuild: `Prekey.epoch` was
/// written, read and otherwise looked at by nobody. Expiry
/// does not hang on it, it hangs on `born` in [PrekeyPool] — the same
/// clock, but the receiver's, and only he cleans up.
///
/// THE INDEX MUST STAY. It is the house number under which the
/// receiver deletes his prekey after a successful open
/// ([V41Host._oneTimeUsed]) — it reaches the sender via this batch
/// and comes back via [PrekeyMatch].
abstract final class PrekeyBatchCodec {
  /// The ML-KEM-768 pubkey at the front, the prekeys behind it.
  static const int mlKemBytes = OqsFFI.mlKemPublicKeyLength;

  /// What a batch of [n] prekeys measures on the wire.
  ///
  /// ONE place for the number, so that a guard does not have to recompute it
  /// and thereby deviate from the encoding.
  static int wireBytes(int n) => 1 + mlKemBytes + n * (4 + 32);

  static Uint8List encode(PrekeyBatch batch) {
    final keys = batch.keys;
    if (keys.isEmpty || keys.length > 255) {
      throw ArgumentError('1..255 Prekeys');
    }
    if (batch.mlKemPublic.length != mlKemBytes) {
      // WITHOUT PK NO BATCH. Letting an empty or wrong-length key
      // through would mean that the other side encapsulates against 1184 B of
      // nonsense — and the failure would lie with the RECEIVER and would be
      // silent. It fails here, with the one who caused it.
      throw ArgumentError('ML-KEM pk must measure $mlKemBytes B, '
          'is ${batch.mlKemPublic.length}');
    }
    final out = Uint8List(wireBytes(keys.length));
    out[0] = keys.length;
    var o = 1;
    out.setRange(o, o += mlKemBytes, batch.mlKemPublic);
    for (final p in keys) {
      out[o++] = (p.index >> 24) & 0xff;
      out[o++] = (p.index >> 16) & 0xff;
      out[o++] = (p.index >> 8) & 0xff;
      out[o++] = p.index & 0xff;
      out.setRange(o, o += 32, p.x25519Public);
    }
    return out;
  }

  static PrekeyBatch? decode(Uint8List b) {
    if (b.isEmpty) return null;
    final n = b[0];
    if (n == 0 || wireBytes(n) > b.length) return null;
    var o = 1;
    final kem = Uint8List.fromList(b.sublist(o, o += mlKemBytes));
    final out = <Prekey>[];
    for (var i = 0; i < n; i++) {
      final idx = (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
      o += 4;
      final x = Uint8List.fromList(b.sublist(o, o += 32));
      out.add(Prekey(idx, x));
    }
    return PrekeyBatch(out, kem);
  }
}

/// Prekeys if there are any — otherwise the static keys.
///
/// THE BOOTSTRAP, and it is unavoidable: in order to SEND a refill,
/// one must already be able to seal. The very first message
/// to a counterpart therefore has no prekey yet. It goes against the
/// static keys and thus has NO per-message forward secrecy
/// — after that the supply takes over.
///
/// This is the same compromise every asynchronous scheme makes at this
/// point. What counts here: it is VISIBLE. [fallbackCount] counts
/// every message that took it, and a node that permanently
/// falls back gets no refills — that is then an error
/// and not a property.
final class BootstrapPrekeys implements PrekeySource {
  final PoolPrekeys pool;
  final Uint8List Function(String peer) staticMlKem;
  final Uint8List Function(String peer) staticX25519;

  int fallbackCount = 0;
  final Set<String> _fellBackFor = <String>{};

  BootstrapPrekeys({
    required this.pool,
    required this.staticMlKem,
    required this.staticX25519,
  });

  /// INITIALLY TRUE, and that is not a detail. Earlier `false` stood here:
  /// whoever called `x25519PublicFor` BEFORE `advance()` had ever run
  /// ended up in the pool — and that throws `Bad state: kein Prekey gezogen`.
  /// Exactly that happened on 22.08. on the phone, from within the
  /// chat settings dialog (`updateChatConfig` ->
  /// `_sendChatConfigUpdate` -> `sendToUser` -> `seal` without `advance`).
  /// The caller has since been corrected (S348, B-3); the
  /// initial value would still be the wrong way round — a supply from which
  /// nothing has ever been drawn is empty, and empty means fallback.
  bool _usingFallback = true;

  /// Whether one-time prekeys may be drawn at all.
  ///
  /// ── THE BOLT HAS FALLEN (S355) ─────────────────────────────────
  ///
  /// **Why it stood from S349 to S355.** [MessageOpener] held exactly
  /// ONE X25519 secret — the long-lived one of the identity. If the sender
  /// instead drew a one-time prekey, he formed `dh = X25519(eph_sk,
  /// einmal_pk)`, while the receiver computed `dh = X25519(langlebig_sk,
  /// eph_pk)`. Different secrets, AEAD fails,
  /// message SILENTLY gone. Worse still: the switch-over point was not
  /// controllable — `pool.advance(peer)` returned `true` as soon as a
  /// batch arrived at some point, so delivery would first have worked and
  /// then stopped in the middle of operation.
  ///
  /// **Why it could not fall earlier, and what has changed.**
  /// The receiver must KNOW which prekey is meant. Until 29.08.2026 §4.6
  /// provided "no extra field on the wire" for that — the
  /// index was to follow from the tag counter of the pair. This counter
  /// does not exist on the V4.1 line: `secureTag(kAb, epoch, family,
  /// direction)` (`secure_mode.dart:79`) hangs on the 24 h epoch, not
  /// on a message number, and the Speed path has no
  /// tag at all (§4.3: "in Speed-Mode there is **no field tag**"). The rule
  /// was unbuildable, not merely unbuilt. §4.6 was therefore relaxed on 29.08.
  /// (S351, B2): a selector travels along under the seal. On
  /// 30.08. it was switched from a counter `(epoch, n)` to
  /// `SHA-256(pk_n ‖ eph_pk)` (version B) — the counter was
  /// monotonic and in plaintext, a responsible relay could use it to assign
  /// two tags to the same receiver and thus broke the promise
  /// of §10.1. The selector is built ([PrekeySelector]), and with it
  /// the receiving side holds:
  ///
  ///   * `MessageOpener.oneTimeSecret` looks up `sk_n` via the
  ///     candidate probe, without consuming — [V41Host.opener] hooks
  ///     it in;
  ///   * deletion only happens after a successful AEAD (§4.6 point 3), otherwise
  ///     a stranger could empty the supply with forged selectors;
  ///   * `V41Host.refillIfNeeded` tops up, and `sendFrame` calls it —
  ///     without a caller the supply would have stayed empty and everything would
  ///     have continued on the static fallback.
  ///
  /// **The fallback remains and remains visible.** The first message to
  /// a counterpart has no prekey yet (step 3 of the ladder, §4.6);
  /// `fallbackCount` keeps counting it.
  static const bool oneTimePrekeysWired = true;

  /// Draws the next prekey — or visibly falls back.
  void advance(String peer) {
    _usingFallback = !oneTimePrekeysWired || !pool.advance(peer);
    if (_usingFallback) {
      fallbackCount++;
      _fellBackFor.add(peer);
    }
  }

  bool fellBackFor(String peer) => _fellBackFor.contains(peer);

  @override
  Uint8List mlKemPublicFor(String peer) =>
      _usingFallback ? staticMlKem(peer) : pool.mlKemPublicFor(peer);

  /// HERE LAY A SOURCE OF ERROR THAT VERSION B CLOSED. Next to
  /// this method stood `selectorFor(peer)` with the same
  /// `_usingFallback` switch, and its comment explained why it
  /// HAD to be the same: if the selector ran on the supply while the
  /// key came from the fallback, the receiver would look for a prekey
  /// and compute with the wrong `dh` — silently lost message. Two
  /// switches that had to be kept in line by diligence are now one:
  /// the selector is computed from THE key that this method
  /// returns (`message_seal.dart`, `seal`).
  @override
  Uint8List x25519PublicFor(String peer) =>
      _usingFallback ? staticX25519(peer) : pool.x25519PublicFor(peer);

  @override
  bool get providesForwardSecrecy => !_usingFallback;
}

/// Binds together the delivery, the sealing and the prekey supply
/// — the thing the application hooks in (IP-4).
///
/// WHY AS A HOST OF ITS OWN and not spread across the service: the service is built
/// in TWO places (daemon and in-process), and exactly this drift
/// was the reason `NodeHost` exists. A host that carries everything
/// is hooked in at both places with one line.
final class V41Host {
  final V41Delivery delivery;
  final MessageSealer sealer;
  final BootstrapPrekeys prekeys;

  /// The own supply per counterpart — THIS side hands it out.
  final Map<String, PrekeyPool> _ownPools = {};

  /// What the counterpart has sent us.
  final PeerPrekeys theirs;

  /// Step 2 of the entry cascade, if it started. `null` means: the
  /// node runs without LAN entry and finds no partners via this segment
  /// — not that it has crashed.
  LanEntryHandle? lanEntry;

  // ══════════════════════════════════════════════════════════════════
  // THE SAVE TICK OF THIS HOST (S376, P5 finding 3)
  // ══════════════════════════════════════════════════════════════════
  //
  // `attachV41` holds a `Timer.periodic(30 s)` that does three things:
  // re-arm the invitation lines (§15.3.3), save the prekey supply
  // (§21.4) and save the daily secrets. Until S376 it stood
  // EXCLUSIVELY in the body of `attachV41` — without a handle, not in the
  // return value, without `cancel` anywhere in the tree.
  //
  // THREE CONSEQUENCES, all measured:
  //
  //  1. **One timer per identity that never ends.** `attachV41` runs per
  //     identity; three identities are three ticks, and none of
  //     them is ever cancelled.
  //  2. **After `removeIdentity` it ticks against a stopped service.**
  //     The comment at both deletion points claimed the opposite
  //     ("The V4.1 attachment of this identity dies with
  //     `service.stop()`"). It does not die: the timer holds a
  //     closure over `service` and `host`, keeps calling
  //     `armV41InviteLines` and keeps writing to the store — until
  //     process end, every 30 seconds.
  //  3. **One more per iOS wake-up.** `IosBackgroundFetch` builds new
  //     services per run and calls `attachV41`; the `finally` block tears down
  //     `entryPersist`, LAN entry, port mapping and node —
  //     not this tick. A `Timer.periodic` keeps the Dart VM
  //     alive, and exactly that is the expensive case in a background run that iOS
  //     ends after the report (the same reasoning stands
  //     at `V41Runtime.entryPersist`).
  //
  // IT HANGS ON THE HOST AND NOT ON THE RUNTIME, because it exists per
  // IDENTITY: `V41Runtime` is the ONE node of the process, `V41Host`
  // is the pairwise part per identity. A field on the runtime would carry
  // the same overwriting that finding 1 describes for the
  // node callbacks.
  Timer? saveTick;

  /// The body of the save tick, so that [dispose] can run it one LAST time
  /// before the tick goes.
  ///
  /// WITHOUT THIS LAST RUN, TEARING DOWN WOULD BE DATA LOSS: the
  /// tick saves prekey supply and daily secrets, and both are written
  /// ONLY by it. If it goes without a final run, up to
  /// 30 seconds of supply changes are lost — and §4.6 point 3 says
  /// what that costs: "or cells from days 9-14 become unopenable (silent
  /// message loss)".
  ///
  /// ONLY THE SAVING PART. Re-arming the invitation lines belongs
  /// to ongoing operation; a host that is just being torn down
  /// needs no fresh lines any more.
  void Function()? saveNow;

  /// What has to be unregistered from the NODE when this host is torn down
  /// (S376, P5 finding 1).
  ///
  /// ── WHY THIS IS A LIST OF CLOSURES ────────────────────
  ///
  /// Since S376 the node keeps a DISTRIBUTOR per callback instead of a
  /// single slot: placement receipts, readiness edge, harvest run and
  /// harvest horizon. A distributor into which entries are only added is the
  /// flip side of the old error — after `removeIdentity` it would otherwise tick
  /// against a stopped service, and for the harvest horizon it would be more
  /// than noise: a frozen state of a removed identity
  /// would hold [V41Node.oldestHorizon] at its date forever
  /// and make all others catch up the same stretch at every start.
  ///
  /// CLOSURES AND NOT A NODE REFERENCE: `V41Host` does not know the
  /// node and should not know it (it belongs to the process, the
  /// host to the identity — the same separation as everywhere in this
  /// file). `attachV41` is the only place where both are present, and
  /// it deposits the unregistration where it arises.
  final List<void Function()> deregistrations = <void Function()>[];

  /// Tears down this host: **first save, then unregister, then
  /// cancel.**
  ///
  /// The order is the whole point (see [saveNow]).
  /// Callable multiple times — the second call finds neither tick nor
  /// unregistrations and does nothing.
  void dispose() {
    final last = saveNow;
    saveNow = null;
    if (last != null) {
      try {
        last();
      } catch (_) {
        // A failed final run must not prevent the cancelling
        // — otherwise exactly the timer on whose account this method exists
        // would stay. The tick itself logs its
        // failures.
      }
    }
    // UNREGISTER AFTER SAVING: the final run writes the
    // harvest horizon into the store too, and an already removed
    // horizon would still be the same item, but the order
    // "first take away, then save" could no longer be justified
    // on the next read.
    //
    // ONE CATCH PER UNREGISTRATION, and the list is cleared in any case: an
    // unregistration that throws must not take the others with it — otherwise
    // exactly the distributor entry on whose account this list exists
    // would stay.
    for (final from in deregistrations) {
      try {
        from();
      } catch (_) {}
    }
    deregistrations.clear();
    saveTick?.cancel();
    saveTick = null;
  }

  V41Host({
    required this.delivery,
    required this.sealer,
    required this.prekeys,
    required this.theirs,
  }) : anchorSource = StaticKeyPrekeys(
          mlKem: prekeys.staticMlKem,
          x25519: prekeys.staticX25519,
        );

  // ══════════════════════════════════════════════════════════════════
  // THE PAIR ANCHOR (E3, S363)
  // ══════════════════════════════════════════════════════════════════
  //
  // ── WHAT IT IS ────────────────────────────────────────────────────
  //
  // The long-lived key pair of the counterpart IDENTITY: X25519 + ML-KEM,
  // the same two that `BootstrapPrekeys` carries as step 3 of the
  // fallback ladder (§4.6) and that `rememberPeerKeys` stores from the
  // contact record. On the opener side it corresponds to
  // `MessageOpener.ownX25519Secret` / `ownMlKemSecret` — both have been
  // candidates there all along, so the anchor needs NO new branch in the
  // opener and NO new field on the wire.
  //
  // ── IT IS NOT THE FOUNDING KEY ─────────────────────────
  //
  // Owner decision of 03.09.2026 (A-9 = reading B): the anchor rotates
  // along on **lock-out** and **emergency rotation**, with a
  // continuity chain. The reasoning is a side condition of the
  // owner: an immutable founding anchor would give a
  // LOCKED-OUT device permanent read-along access to exactly the cell class over
  // which key packets and emergency rotations run. Under B the
  // anchor inherits the lock-out effect that §14.4 has for the user KEM anyway.
  //
  // That this rotation already takes effect in the build is measured and not
  // assumed: `_handleKeyRotation` writes `contact.x25519Pk` and
  // `contact.mlKemPk` (`cleona_service.dart`), and the body of
  // `sendToUser` passes exactly these two through to [rememberPeerKeys].
  // The anchor thus moves along without anything having to be updated here.
  //
  // ── WHAT IS SEALED UNDER IT ─────────────────────────────────
  //
  // Control cells: the prekey refill ([refillIfNeeded]) and everything
  // the application puts into the 31-day class (`management: true` —
  // emergency rotation, restore broadcast, key packets).
  // NOT the user's message: it keeps its
  // per-message forward secrecy.
  //
  // ── WHY THIS IS AN OBJECT OF ITS OWN AND NOT A SWITCH ─────────────
  //
  // `BootstrapPrekeys` carries a state (`_usingFallback`,
  // `_current`) that depends on the last draw. Sending a control cell
  // via a switch in this object would mean flipping the state
  // of the regular path in the middle of a send — and the
  // next payload message would read it wrongly. The anchor is therefore a
  // SECOND, stateless source; the two cannot
  // interfere with each other.
  final StaticKeyPrekeys anchorSource;

  /// How many cells this host has sealed under the pair anchor
  /// (E3).
  ///
  /// The metric of E3: if it stayed at 0 while refills
  /// and management messages flow, the anchor would be built and
  /// untrodden — exactly the class that has already cost this migration money
  /// three times.
  int anchorSeals = 0;

  /// How often the anchor was taken BECAUSE the prekey batch of the
  /// counterpart was dead (variant E, S367).
  ///
  /// A SUBSET of [anchorSeals] and therefore a counter of its own:
  /// the one measures "sealed under the anchor" (intended, decided at
  /// the send site), this one measures "FELL BACK to the anchor"
  /// (unintended, forced by the state of the counterpart). If they were
  /// the same number, the fallback could no longer be distinguished
  /// from the intention — and it is exactly the change of
  /// security posture that must stay visible.
  ///
  /// If it rises permanently, that is the proof of need for E4 (the
  /// catch-up request), which according to D5 comes last.
  int anchorDueToStaleness = 0;

  /// Where this host reports a change of security posture.
  /// `null` = nobody is listening (tests); the counters run anyway.
  ///
  /// NO `CLogger` HERE, for the same reason as with
  /// [PeerPrekeys.report]: it hangs a timer on the process (S360,
  /// "CLogger held EVERY process"). `v41_attach.dart` hooks in its
  /// existing log sink — at the same place as the one of
  /// [PeerPrekeys].
  void Function(String message)? report;

  /// One counting space for ALL supplies of this identity.
  ///
  /// Not per supply, and that is not thrift: an incoming
  /// cell only names the index, not the contact (invariant 3 — the
  /// opener does not know before opening who it is from). If the
  /// counter started at 0 per contact, index 0 would exist in every supply, and
  /// [_oneTimeSecretFor] would have to guess between several secrets.
  final PrekeyIndexSpace _prekeyIndices = PrekeyIndexSpace();

  /// Up to where the harvest has scanned — the clock on which the deadline of the
  /// one-time prekeys hangs (E5, S363).
  ///
  /// ONE PER IDENTITY, like the counting space next to it and for the same
  /// reason: it measures a property of THIS node ("how long was I
  /// away"), not one of the counterpart. All supplies share it.
  ///
  /// IT IS KEPT BY THE NODE, not here: `V41Node.harvestTick` is
  /// the only regular tick that knows whether a catch-up is
  /// open. `attachV41` passes this object through there
  /// (`runtime.node.ernteHorizont = host.ernteHorizont`). It travels in
  /// [exportPrekeyState] — together with the item whose deadline
  /// it carries, so that the two cannot drift apart.
  final HarvestHorizon harvestHorizon = HarvestHorizon();

  PrekeyPool poolFor(String peer) => _ownPools.putIfAbsent(
      peer, () => PrekeyPool(space: _prekeyIndices, horizon: harvestHorizon));

  /// How many one-time prekey indices this identity has assigned
  /// in total.
  ///
  /// **NOT the "prekey pool identifier" from §13.4.4** — that does not exist
  /// in the tree (`prekey_pool.dart` keeps no `prekey_pool_epoch`, and
  /// `cleona_service.dart` names this as an open finding at the restore
  /// broadcast). This here is the assignment counter of the shared
  /// index space, and it is therefore named so.
  ///
  /// It is needed by the rescue bundle (§13.3.2): a
  /// restored identity that continued assigning at 0 would use
  /// indices a second time that counterparts still hold — and
  /// [_oneTimeSecretFor] would then have to guess between two secrets,
  /// exactly the state the shared counting space excludes.
  int get prekeyIndicesIssued => _prekeyIndices.issued;

  // ── THE STORAGE OF THE ONE-TIME PREKEYS (S356) ───────────────────────────
  //
  // §21.4 lists the item explicitly: it lies "mandatorily
  // under the DB key, together with `inbox_key` and the prekey pool
  // (§4.6)". Until S356 it lay nowhere — `PrekeyPool` had no
  // serialisation at all, and every process start threw away the one-time prekeys.
  // §4.6 point 3 names the price: retention must outlast the full
  // delivery period, "or cells from days 9-14 become unopenable
  // (silent message loss)".
  //
  // WHY THE COLLECTING OBJECT HANGS HERE AND NOT ON THE SUPPLY. A supply
  // alone is not restorable: it shares a counting space with all others
  // ([_prekeyIndices]), and that is the part whose
  // loss is most expensive (see [PrekeyIndexSpace.ensurePast] — a
  // number assigned twice deletes the wrong prekey on opening).
  // Whoever stored the supplies individually would have to store the counter next to them
  // and bring both into the right order by hand when loading.
  // Here it is ONE item with ONE order, and the
  // construction site sees only two methods.
  //
  // THE STRUCTURE IS THE FORM, NOT THE STORAGE. This layer writes
  // no file and knows no key; `v41_attach.dart` hooks that in
  // against `FileEncryption`, as with the entry supply and the
  // peer age. What comes out here carries `sk_i` in plaintext and may
  // leave the layer only encrypted.

  /// The state of all one-time prekeys of this identity.
  ///
  /// CONTAINS SECRET KEYS. Store only encrypted.
  Map<String, dynamic> exportPrekeyState() => {
        'v': 1,
        'space': _prekeyIndices.toJson(),
        'own': {
          for (final e in _ownPools.entries) e.key: e.value.toJson(),
        },
        'theirs': theirs.toJson(),
        // THE HARVEST HORIZON TRAVELS ALONG HERE (E5, S363) — see
        // [ernteHorizont]. It carries no secret, only a
        // timestamp; it is stored encrypted nonetheless because the file
        // is.
        'ernte': harvestHorizon.toJson(),
      };

  /// Loads what [exportPrekeyState] delivered.
  ///
  /// Returns what was really taken over — the construction site can
  /// log that, just as it logs "Vorrat geladen — N Datensaetze".
  /// Zero loaded prekeys with an existing file are a
  /// finding, not a normal case.
  ///
  /// THE ORDER IS FIXED. First the counting space, then the supplies: the
  /// supplies lift the counter above every index they load
  /// ([PrekeyPool.loadJson]), and this lifting must not be overwritten by a
  /// lower counter state loaded afterwards.
  /// [PrekeyIndexSpace.loadJson] never lowers anyway — but
  /// an invariant that holds only through the right call order
  /// is fixed here instead of presupposed.
  ///
  /// ONLY AT START. A second load into a running host would
  /// revive consumed secrets; the supplies therefore
  /// reject it themselves ([PrekeyPool.acceptsSnapshot]).
  ({int pools, int own, int theirs}) importPrekeyState(
      Map<String, dynamic> j,
      {required DateTime now}) {
    if (j['v'] != 1) return (pools: 0, own: 0, theirs: 0);

    // THE HORIZON FIRST, and that is not cosmetics: the supplies
    // decide ON LOADING what they throw away ([PrekeyPool.loadJson]),
    // and for that they ask exactly this horizon. If it came afterwards,
    // loading would run against an empty horizon — that throws nothing away
    // (the cautious side), but the rule would then hang on the
    // call order instead of on this line.
    final eh = j['ernte'];
    if (eh is Map) harvestHorizon.loadJson(eh.cast<String, Object?>());

    final sp = j['space'];
    if (sp is Map) _prekeyIndices.loadJson(sp.cast<String, Object?>());

    var pools = 0;
    var ownList = 0;
    final own = j['own'];
    if (own is Map) {
      for (final e in own.entries) {
        final peer = e.key;
        final value = e.value;
        // NO EMPTY COUNTERPART NAME. A supply under `''` would mix
        // the prekeys of all contacts — the same trap against which
        // `acceptSealed` guards the `prekeyRefill` branch.
        if (peer is! String || peer.isEmpty || value is! Map) continue;
        final n = poolFor(peer).loadJson(value.cast<String, Object?>(), now: now);
        if (n > 0) pools++;
        ownList += n;
      }
    }

    var foreign = 0;
    final th = j['theirs'];
    if (th is Map) {
      foreign = theirs.loadJson(th.cast<String, Object?>(), loaded: now);
    }

    // FRESHLY LOADED IS NOT DIRTY. Otherwise the first tick
    // after start would write the same file back once more.
    prekeyStateDirty = false;
    return (pools: pools, own: ownList, theirs: foreign);
  }

  /// Whether anything about the prekeys has changed since the last save.
  ///
  /// ── WHY A FLAG AND NOT A TICK ─────────────────────────────────
  ///
  /// Saving the prekeys must not hang on a clock alone, and
  /// for a reason the entry supply does not have: there
  /// a missed write costs an address that one learns
  /// again. Here it costs a message.
  ///
  ///   * If a consumed prekey is not saved as consumed promptly,
  ///     it comes back to life after a crash — and with it
  ///     an `sk_i` that should long have been deleted.
  ///   * If a draw from [theirs] is not saved, the
  ///     sender seals a second time against the same prekey after a crash;
  ///     the receiver has already deleted his `sk_i`, and the
  ///     message is silently lost.
  ///
  /// The flag is therefore set at exactly the places where a prekey
  /// is created, drawn, consumed or discarded. The construction site
  /// decides how fast it reacts to it; it can do so immediately.
  ///
  /// It is NOT cleared by [exportPrekeyState] — otherwise the
  /// state would count as saved as soon as someone merely looked at it, and a
  /// failed write would go unnoticed. Whoever has written
  /// calls [markPrekeyStateSaved].
  ///
  /// SINCE S363 THE HARVEST HORIZON COUNTS TOO. It travels in the same
  /// store and advances with every harvest run; if it did not set the flag,
  /// an outdated horizon would stand in the file after a restart.
  /// So that this does not mean "rewrite the file every 32 s",
  /// [HarvestHorizon.dirty] only reports after
  /// [HarvestHorizon.saveThreshold] — the calculation of why that is
  /// without consequence stands there.
  bool _prekeyStateDirty = false;

  bool get prekeyStateDirty => _prekeyStateDirty || harvestHorizon.dirty;

  set prekeyStateDirty(bool v) => _prekeyStateDirty = v;

  /// Reports that the state delivered by [exportPrekeyState] was really
  /// stored.
  ///
  /// Between [exportPrekeyState] and this call nothing may lie
  /// that touches the prekeys — so no `await`. `FileEncryption`
  /// writes synchronously, that fits.
  void markPrekeyStateSaved() {
    _prekeyStateDirty = false;
    harvestHorizon.markSecured();
  }

  /// The long-lived KEM keys per counterpart.
  ///
  /// WHY THIS HAS TO STAND HERE (B-19, S349). `attachV41` built the
  /// fallback like this:
  ///
  ///     staticMlKem: (_) => keys.nMlKemPublic,
  ///     staticX25519: (_) => keys.nX25519Public,
  ///
  /// The underscore is the error: the counterpart is ignored and the
  /// OWN node key is delivered. The sender thus sealed to himself,
  /// and the receiver could by construction never open it —
  /// regardless of whether the cell arrived. Together with the never
  /// sent daily capsule these were two reasons for which the same
  /// message was unreadable.
  ///
  /// They are the IDENTITY keys (user KEM), not those of the node:
  /// §4.3/§4.6 bind the sealing to the identity, and
  /// `deriveDeliveryPairKey` in the body of `sendToUser` has long done
  /// the same for `K_AB`. The node holds `L_node` and the port; the
  /// end-to-end keys belong to the identity.
  final Map<String, ({Uint8List x25519, Uint8List? mlKem})> _peerKeys = {};

  /// Remembers against which keys sealing to [peer] happens.
  ///
  /// Called from the body of `sendToUser`, which has already
  /// resolved them anyway — including the overrides for group members
  /// that are not a contact at all. Looking them up here again would mean
  /// building a second resolution that can deviate from the first.
  /// [mlKem] may be missing, and that is no loophole: at FIRST CONTACT
  /// it does not exist. The requester knows `ep` from the ContactSeed and
  /// computes `X_B` from it; the long-lived ML-KEM pubkey (1184 B) stands
  /// only in the extended seed profile (§15.5) and in no QR code
  /// (§15.3.1). Exactly for that reason §15.4 puts the invitation key there in
  /// place of the capsule.
  ///
  /// ENTERING A PLACEHOLDER WOULD BE WORSE THAN `null`. `peerMlKem`
  /// is read in `attachV41` with `?? keys.nMlKemPublic` — an empty
  /// or invented field would run past this fallback and end in
  /// `mlKemEncapsulate` with a throw or, worse, with a capsule
  /// against a key nobody holds.
  void rememberPeerKeys(String peer,
          {required Uint8List x25519, Uint8List? mlKem}) =>
      _peerKeys[peer] = (x25519: x25519, mlKem: mlKem);

  /// The X25519 part of the counterpart, or `null`.
  Uint8List? peerX25519(String peer) => _peerKeys[peer]?.x25519;

  /// The ML-KEM part of the counterpart, or `null`.
  Uint8List? peerMlKem(String peer) => _peerKeys[peer]?.mlKem;

  /// Sequential identifier of the transmissions of this host.
  ///
  /// ── IT STARTS RANDOM, NOT AT ZERO (S376, finding 4) ─────────
  ///
  /// Until S375 `= 0` stood here, on every host. The identifier goes out as a
  /// 32-bit header with every piece (`splitPayload`,
  /// `frame_split.dart:81-84`), and the receiver reassembles Speed pieces
  /// in ONE shared `PayloadReassembler` — with the
  /// key `(id, total)` (`frame_split.dart`, `final schluessel =
  /// (id, total);`).
  ///
  /// This reassembler MUST be shared, and is so for a
  /// proven reason: in Speed mode the onion addresses, there
  /// is no field tag (§4.3, "in Speed-Mode there is no field tag"),
  /// so the receiver only knows the sender AFTER reassembly
  /// and the AEAD. Keying by sender is thus not merely
  /// inconvenient but impossible — and the split per SESSION that existed
  /// until 30.08. was itself a field finding ("offene
  /// Uebertragungen 3", nothing ever completed).
  ///
  /// The collision could therefore only be closed on the SENDER SIDE.
  /// With `0` as start the first transmissions of EVERY host carried the
  /// identifiers 0, 1, 2 …; two first-of-day messages from different
  /// senders to the same receiver fall into two pieces with their capsule (§4.3)
  /// and, with equal sealed length, also have
  /// the same `total`. Both transmissions then ran into the same
  /// entry, the pieces overwrote each other, and BOTH messages
  /// were lost — silently, because a length conflict is counted, a
  /// perfectly fitting collision is not.
  ///
  /// 4 bytes from the CSPRNG as the start. The collision is thus not
  /// excluded, but pushed down to the random probability
  /// (~2^-32 per pair of simultaneously open transmissions with equal
  /// `total`) — the same order of magnitude the header reckons with
  /// anyway.
  int _transfer = _randomIdentifier();

  /// A random 32-bit start value. Static, because a
  /// field initialiser has no access to `this`.
  static int _randomIdentifier() {
    final b = SodiumFFI().randomBytes(4);
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  }

  /// Sends an application frame — split if it does not fit into one cell.
  ///
  /// THE ORDER IS ESSENTIAL: first seal, THEN split. The
  /// reverse way — a separate seal per piece — does not only cost 60 B per
  /// piece, it cannot even be built for the first piece of the day:
  /// that one carries the daily capsule (1088 B) and then fits into no cell
  /// any more, however small one makes the piece. One seal over the
  /// whole solves this, because the capsule is then itself split along.
  ///
  /// The price, openly named: the receiver cannot check a single piece.
  /// Whether the pieces belong together is only told by the AEAD
  /// after reassembly — that is why the gates in
  /// [PayloadReassembler] are the actual protection, not the crypto.
  SendOutcome sendFrame({
    required String peer,
    required Uint8List frame,
    required SendMode mode,
    required DateTime now,
    /// Opaque recognition value of the application. Not
    /// read and not put on the wire — it comes back in the
    /// placement receipt, so that `placed` can have a producer.
    Uint8List? messageId,

    /// The 31-day retention class (§21.1, `kRetentionManagement`).
    ///
    /// It is PASSED THROUGH, not decided: the host knows no
    /// message types. Who sets it and why only there is stated at
    /// `V41Node.placeSecure`.
    bool management = false,
  }) {
    // ── FIRST THE PAIR KEY, THEN EVERYTHING ELSE ─────────────────
    //
    // Without `K_AB` there is no sender MAC, and without it the
    // `senderUserId` would again be freely claimable at the receiver (B-20). The
    // message must then not go out "unauthenticated" — it does not go
    // out at all.
    //
    // This is no new rejection: `V41Node.send` rejects the same case
    // with the same reason (`pairs.kAbFor(peer) == null` ->
    // `noPairKey`). Here it only fails earlier — BEFORE `prekeys.advance`,
    // so that a rejected send attempt does not drive up the fallback counter
    // and consume a prekey that nobody ever redeems.
    final kAb = pairKeyFor?.call(peer);
    if (kAb == null) {
      return const SendOutcome.refused(SendRefusal.noPairKey);
    }

    // ── FIRST TOP UP THE OWN SUPPLY (§4.6) ────────────────────
    //
    // THE CALLER WAS MISSING HERE, and that was half the gap. `refillIfNeeded`
    // was built and was called NOWHERE in `lib/` and `bin/` (measured
    // S355); the own supply thus stayed empty, the counterpart never got
    // prekeys, and every message in this direction ran on the
    // static fallback — exactly the pattern "built, not trodden"
    // on which the receiving side (S349) and the Speed read side (S353)
    // had already got stuck.
    //
    // WHY AT THIS POINT: sending to a counterpart is the
    // moment at which it is established that this pair exists and that
    // traffic flows. §4.6 wants the refill "ahead of exhaustion,
    // with B/2 headroom" — at the first send the supply is 0, so
    // it takes effect immediately, and after that only again below 8.
    //
    // WHY THE RESULT IS NOT PASSED THROUGH: the user's message does
    // not depend on it. If the refill fails, the
    // supply stays empty and the counterpart keeps sending with the static
    // key — visible in `fallbackCount`, not silent.
    final after = refillIfNeeded(peer: peer, now: now);
    if (after != null && !after.accepted) refillsRefused++;

    // ── CONTROL CELLS RUN UNDER THE ANCHOR (E3, S363) ────────────────
    //
    // `management` is already today the marker of the 31-day class (§21.1)
    // — emergency rotation, restore broadcast, key packets.
    // It is exactly these cells that E3 detaches from the rotating material,
    // and the class is thus ONE and not two: what may lie 31
    // days at the relay must still be OPENABLE after 31 days.
    //
    // WHY THIS WAS NECESSARY (measured 03.09.2026). Without this switch
    // a management message also drew a one-time prekey. Its `sk_i`
    // goes at the receiver after `PrekeyPool.retention` = **15 days**;
    // the cell then still lay at the relay (`kManagementKeepEpochs` = 31)
    // and could no longer be opened. On the opener side the
    // 31-day class was thus really a 15-day class — and the loss
    // silent, because an unopenable cell looks like no cell.
    //
    // NO DRAW. A control cell consumes no one-time prekey;
    // drawing it and then not using it would be giving away the
    // forward secrecy of a payload message.
    //
    // ══════════════════════════════════════════════════════════════════
    // AND A DEAD BATCH AS WELL — variant E, S367
    // ══════════════════════════════════════════════════════════════════
    //
    // ── THE FINDING ────────────────────────────────────────────────────
    //
    // Until S367 the switch hung ONLY on `management`, and exactly ONE
    // place in `lib/` sets it (`cleona_service.dart`, the
    // emergency rotation). The restore broadcast does NOT set it,
    // and neither does the answer to it.
    //
    // Topping up happens only when sending TO THIS counterpart (the lines
    // above). Whoever has not written to a contact for 15 days only has
    // a batch for him whose `sk_i` the receiver has
    // thrown away ([PeerPrekeys.stackStaleFrom] =
    // [PrekeyPool.retention]). The broadcast goes to ALL contacts —
    // especially to the rarely written ones, i.e. to exactly these. The path
    // that has to take effect on total loss is thus the path on which
    // staleness is most likely. And the loss is
    // silent: an unopenable cell looks like no cell.
    //
    // ── WHY THE ANCHOR AND NOT "DON'T SEND AT ALL" ──────────────────
    //
    // A cell nobody can open has perfect
    // forward secrecy and ZERO value. In exactly the cases in which
    // this switch changes something, the one-time prekey protects nothing — it
    // only prevents the delivery.
    //
    // ── AND WHY NOT ALWAYS RIGHT AWAY (variant B) ─────────────────────
    //
    // In the remaining cases the per-message forward secrecy is
    // real. Giving it up there without need would be a trade without
    // return. The information about which case applies is available anyway:
    // [PeerPrekeys.take] computes `stackStale` exactly at the moment
    // of the draw. Here THE SAME information is asked, only earlier.
    //
    // ── THE CHANGE IS NOT SILENT, AND THAT IS A CONDITION ────────────
    //
    // A fallback from the one-time prekey to the long-lived anchor is a
    // change of security posture. The hard project rule on this reads
    // "Speed may fall back to Secure, Secure never silently to Speed";
    // a silent fallback here would be the same figure and would trade
    // a silent loss for a silent weakening. It is
    // therefore counted ([anchorDueToVeraltung]) and reported ([report]).
    //
    // ── NO ADDITIONAL NETWORK TRAFFIC ────────────────────────────────
    //
    // An anchor cell draws no prekey and sends no second
    // cell; the capsule lies next to the batch capsule in the same cache
    // (`message_seal.dart`).
    //
    // ── FIRST CLEAR AWAY THE DEAD HEAD ──────────────────────────────
    //
    // Without that, variant E would in practice be variant B: `receive`
    // appends, the dead head would stay in front, and because nothing is
    // drawn here any more, fresh material behind it would never get its
    // turn. Full reasoning at
    // [PeerPrekeys.dropToteBeforeFrischen].
    if (theirs.dropDeadBeforeFresh(peer, now) > 0) {
      prekeyStateDirty = true;
    }

    final stackDead = theirs.stackStale(peer, now);
    if (stackDead && !management) {
      anchorDueToStaleness++;
      report?.call(
          'Prekey stack for $peer is ${theirs.stackAge(peer, now)!.inDays} '
          'days old (limit ${PeerPrekeys.stackStaleFrom.inDays} d) — this '
          'cell goes under the long-lived pair anchor instead of under a '
          'one-time prekey. The forward secrecy per message is dropped for '
          'it; the alternative would be a silent loss (E4 missing, S363). '
          'So far ${anchorDueToStaleness}x. Stale DRAWS so far '
          '${theirs.staleDraws}x — this number must stay 0, every '
          'increase means that a send path bypasses this switch.');
    }

    final anchor = (management || stackDead) ? anchorSource : null;
    if (anchor == null) {
      prekeys.advance(peer);
      // DRAWN IS CHANGED. The draw takes a prekey from
      // [theirs]; if that is not saved, the sender seals against it a second time
      // after a crash, and the receiver has
      // already deleted his `sk_i` — silently lost message (see
      // [prekeyStateDirty]).
      prekeyStateDirty = true;
    } else {
      anchorSeals++;
    }

    // AUTHENTICATE, THEN SEAL. The MAC belongs under the seal:
    // if it lay above, r2 would see a value per pair stable over time
    // and could link cells of the same pair — exactly what
    // the onion prevents.
    final certified = Uint8List(V41Kind.senderMacBytes + frame.length)
      ..setRange(0, V41Kind.senderMacBytes,
          v41SenderMac(kAb: kAb, frame: frame))
      ..setRange(V41Kind.senderMacBytes,
          V41Kind.senderMacBytes + frame.length, frame);
    final isSealed = sealer.seal(
      peer: peer,
      plaintext: V41Kind.wrap(V41Kind.appFrame, certified),
      now: now,
      source: anchor,
    );

    // ALL OR NOTHING. A half-sent frame cannot be opened at the receiver
    // and binds memory there until displacement. If
    // one piece is rejected, the whole message counts as not accepted.
    //
    // HERE STOOD A ROLLBACK THAT ROLLED NOTHING BACK (until S351): on
    // rejection `sealer.forgetCapsuleSent` was called in order to delete the
    // dispatch note of the daily capsule. The note lay in
    // `_capsuleSent` — a set that was written and read for no
    // decision. Decisions are made via `_capsuleConfirmed`.
    // The comment thus described an effect the code did not have.
    //
    // The concern behind it was justified and is answered, only at another
    // place and more strongly: the capsule is only dropped after EVIDENCE (an
    // opened answer from the counterpart), not after sending. A
    // lost cell cannot produce evidence, so the capsule keeps travelling
    // along by itself. A rollback is thus superfluous, not merely
    // ineffective.
    return _sendSealed(
        peer: peer,
        sealed: isSealed,
        mode: mode,
        messageId: messageId,
        management: management);
  }

  /// Puts a CONTACT REQUEST onto the invitation line (§15.3.2, §15.4).
  ///
  /// ── WHY THIS IS NOT [sendFrame] ─────────────────────────────────
  ///
  /// [sendFrame] does two things on the way that would both be
  /// harmful on an invitation line:
  ///
  ///   1. `refillIfNeeded` tops up a prekey batch for the counterpart.
  ///      The counterpart here is a PSEUDO counterpart — the
  ///      invitation —, and its tag line can be computed from `K_inv(i)`,
  ///      for the class "published" thus **by every URI holder**
  ///      (§15.3.1). A prekey batch there would be a supply that a
  ///      stranger can collect and use up.
  ///   2. It seals against the daily capsule of the counterpart. That does
  ///      not exist here: the requester does not hold the long-lived
  ///      ML-KEM pubkey of the issuer (§15.5 — `mk` stands only in the
  ///      extended profile, and it does not fit into the QR code).
  ///
  /// §15.4 puts the INVITATION KEY in place of the capsule:
  /// `seal_key = HKDF( K_inv(i) ‖ X25519(eph_sk, X_B) )`. [sealSecret] is
  /// the symmetric part derived from `K_inv(i)`
  /// (`invite_line.dart`), `X_B` comes from [rememberPeerKeys] — the
  /// requester computes it from the `ep` of the ContactSeed.
  ///
  /// ── HERE THE MAC ONLY AUTHENTICATES THE INVITATION ───────────────────────
  ///
  /// As everywhere it is formed under the pair secret, and that is
  /// `K_inv(i)` here. It thus says "the sender held this invitation"
  /// — and the invitation line claims no more than that anyway. It cannot be
  /// evidence ABOUT THE PERSON: with a published
  /// invitation anyone can form it. The receiving side therefore passes
  /// NO pair identifier upwards (`v41_attach.dart`), so that
  /// `verifyV41Sender` says `unverifiable` instead of `verified` — the honest
  /// information. The evidence about the person is `sig_founding` (§15.4) and
  /// cannot be formed today because the founding secret is not
  /// persisted; that is named as a gap, not glossed over.
  ///
  /// The MAC stays in the frame nonetheless: the form is the same as with
  /// every other cell, and a missing or zeroed field would be a
  /// feature — the same consideration for which `message_seal.dart`
  /// removed the reserved marker `staticMarker` without replacement.
  ///
  /// ALWAYS SECURE. Speed presupposes a liveness route of the receiver
  /// (§6), and that only arises with `K_AB`. For a stranger
  /// nobody publishes one — that he does not is exactly the
  /// protection from §15.4 against the presence oracle.
  SendOutcome sendInviteRequest({
    required String peer,
    required Uint8List frame,
    required Uint8List sealSecret,
    required DateTime now,
    Uint8List? messageId,
  }) {
    final kInv = pairKeyFor?.call(peer);
    if (kInv == null) {
      return const SendOutcome.refused(SendRefusal.noPairKey);
    }
    // DRAW, BUT DO NOT TOP UP. `advance` is the place at which
    // [BootstrapPrekeys] decides whether it uses a one-time prekey or the
    // long-lived fallback; without the call
    // `x25519PublicFor` would read the state of the LAST served counterpart. For
    // a pseudo counterpart the supply is always empty, so the fallback
    // reliably takes effect — and `fallbackCount` counts it, as it should.
    prekeys.advance(peer);
    final certified = Uint8List(V41Kind.senderMacBytes + frame.length)
      ..setRange(0, V41Kind.senderMacBytes, v41SenderMac(kAb: kInv, frame: frame))
      ..setRange(V41Kind.senderMacBytes,
          V41Kind.senderMacBytes + frame.length, frame);
    final isSealed = sealer.seal(
      peer: peer,
      plaintext: V41Kind.wrap(V41Kind.appFrame, certified),
      now: now,
      staticSharedSecret: sealSecret,
    );
    inviteRequestsSent++;
    return _sendSealed(
        peer: peer,
        sealed: isSealed,
        mode: SendMode.secure,
        messageId: messageId);
  }

  /// Contact requests that this host has put onto an invitation line.
  int inviteRequestsSent = 0;

  /// Cells that arrived under an invitation tag and were NOT a
  /// contact request (§15.3.2, type binding).
  ///
  /// It stands here and not in the sink because §15.3.2 expressly lists it
  /// as a "testable invariant for the test strategy (§28)" — a
  /// number nobody can read is no testable invariant.
  int inviteTypeViolations = 0;

  /// Tops up when the own supply for [peer] is running low.
  ///
  /// The refill rides **Secure** — normatively (§4.6): on the
  /// linkable Speed path it would reveal that a conversation is about to
  /// begin.
  SendOutcome? refillIfNeeded({required String peer, required DateTime now}) {
    // As long as the receiving side cannot resolve one-time prekeys
    // ([BootstrapPrekeys.oneTimePrekeysWired]), a refill would be
    // harmful: it switches the OTHER SIDE to a path that THIS
    // side cannot open. The bolt has been open since S355; the line
    // stays because it is the only place at which it closes again
    // should the receiving side ever be dismantled.
    if (!BootstrapPrekeys.oneTimePrekeysWired) return null;
    final pool = poolFor(peer);

    // ── EXPIRY BELONGS HERE (§4.6 point 3) ────────────────────
    //
    // "Unused prekeys are deleted after `delivery TTL + margin` (15
    // days)." This layer has no tick of its own on which a
    // cleaner could hang without creating a second rhythm in the egress
    // (invariant 1) — and an expiry that is called nowhere
    // is no expiry. The top-up check is the natural place:
    // it passes by at every send to this counterpart, costs one
    // pass over a few dozen entries, and what it throws away
    // makes room for what it creates right after.
    //
    // WHAT IT THROWS AWAY IS COUNTED. Since version B (30.08.) this is the
    // only remaining measurement of the expiry: the hash selector carries
    // no epoch any more by which a cell arriving too late would be recognisable
    // as "too late" (see the note at [expiredPrekeysSwept]).
    final expired = pool.sweep(now);
    expiredPrekeysSwept += expired;
    if (expired > 0) prekeyStateDirty = true;

    if (!pool.needsRefill) return null;
    final batch = pool.refill(now: now);
    // FRESHLY MINTED AND NOT YET STORED ANYWHERE. Exactly these 16 `sk_i`
    // are needed by the receiver after the next restart — they are what
    // the counterpart seals against from now on.
    prekeyStateDirty = true;

    // ── THE REFILL RUNS UNDER THE ANCHOR (E3, S363) ───────────
    //
    // HERE STOOD A DRAW OF ITS OWN (`prekeys.advance(peer)`), and it
    // was right under the old construction: the refill must
    // not seal against the prekey of the last sent message,
    // which the receiver has already consumed.
    //
    // With E3 it is moot, not merely dispensable. The
    // refill is the control cell par excellence — it carries the
    // material from which an exhausted pair finds its way out again. Sealing it
    // against a one-time prekey binds exactly this
    // material to the supply it is supposed to refill: if
    // the counterpart's supply is dead (deadline expired, batch
    // used up), the refill can no longer be opened either,
    // and both sides seal to each other against dead material.
    // This deadlock cannot arise under the anchor.
    //
    // The anchor has no per-message forward secrecy. The content
    // of this cell is public key material — 16 X25519 pks
    // and one ML-KEM pk —, and this price is paid expressly.
    anchorSeals++;

    final isSealed = sealer.seal(
      peer: peer,
      plaintext:
          V41Kind.wrap(V41Kind.prekeyRefill, PrekeyBatchCodec.encode(batch)),
      now: now,
      source: anchorSource,
    );

    // SPLIT LIKE ANY OTHER PAYLOAD, AND SINCE E1 ALWAYS. Measured
    // 03.09.2026: with the batch ML-KEM pk a batch measures **1761 B**
    // (before 577 B), with the header byte of `V41Kind.wrap` and the
    // 64 B seal **1826 B**, with the daily capsule **2914 B**. A placement
    // carries 1043 B (`kMaxPlaceContentBytes`), so 2 or 3 cells respectively —
    // before 1 or 2. Until S355 the refill went unsplit to the
    // delivery and would have been rejected there.
    //
    // ── THE RETENTION CLASS STAYS THE ORDINARY ONE ──────────────
    //
    // Briefly `management: true` stood here. That was an extension
    // I am not entitled to, and it has been withdrawn:
    //
    //  * `V41Node.placeSecure` keeps the 31-day class as an
    //    explicit, named list (§4.5.4 l. 1007-1008: the
    //    emergency rotation; §14.4/§14.7: the key packet per device)
    //    and states what expressly does NOT belong in it. The
    //    refill is in neither of the two lists.
    //  * The cost calculation of the draft expressly prices it into the
    //    CONTENT deadline of 14 days
    //    (`S363-VORLAGE-31-tage-konsolidiert.md` 7.2, line
    //    "Nachlieferung, Zuwachs (2. Zelle), Inhalts-Frist 14 d").
    //    31 days would be roughly double the resting relay storage —
    //    a number that needs a decision and not an implementation.
    //
    // E3 changes the SEAL SIDE, not the placement deadline. The gain
    // remains complete: binding is now the relay's deadline (14 d,
    // intended and calculated) instead of the deadline of a one-time prekey
    // (15 d, unintended and silent).
    return _sendSealed(
        peer: peer, sealed: isSealed, mode: SendMode.secure);
  }

  /// Splits a sealed payload and hands it to the delivery.
  ///
  /// ONE place for both senders ([sendFrame] and [refillIfNeeded]).
  /// Two places would be two opportunities to forget the splitting,
  /// and the forgetting only shows at the first message that
  /// is longer than one cell.
  SendOutcome _sendSealed({
    required String peer,
    required Uint8List sealed,
    required SendMode mode,
    Uint8List? messageId,

    /// PER PIECE, NOT PER MESSAGE — and that is no negligence.
    /// The deadline hangs on the CELL at the holding relay; if only one
    /// piece of a split management message lay 31 days and the rest
    /// three, nothing could be reassembled after four days and the
    /// long deadline would be a dummy (§22.5.1: a single piece cannot even
    /// be checked).
    bool management = false,
  }) {
    // THE ATTEMPT IDENTIFIER IS HELD, not consumed in the call.
    // It goes down with every piece and comes back with the receipt;
    // without it pieces from DIFFERENT
    // sealings of the same message could be added up to a `placed`,
    // although no complete sealing lies anywhere.
    // MODULO 2^32, because the header carries exactly 32 bits
    // (`frame_split.dart:81-84` masks with `& 0xff`). Without the
    // limit the LOCAL identifier would at some point run beyond the value
    // the wire carries — the placement bookkeeping
    // (`_merkeEigeneAblage`, `PlacementAck`) would then compute with a
    // different number than the receiver. With `0` as start that lay
    // beyond any reach; with a random start it lies,
    // on average, after 2^31 transmissions and must therefore stand here.
    final attempt = _transfer;
    _transfer = (_transfer + 1) & 0xffffffff;
    final pieces = splitPayload(
      sealed,
      transferId: attempt,
      maxChunkBytes: kMaxPieceBytes,
    );
    var legs = 0;
    // ── THE PIECE NUMBER GOES ALONG, AND IT DOES SO HERE ──────────────────────
    //
    // This is the only place in the tree at which a message falls apart into
    // several cells, and thus the only one that knows which
    // piece is which. Further down the delivery only sees
    // bytes; further up the application only sees one message.
    // Whoever does not pass the number along here can later only
    // guess at `placed` — and guessing would mean: claiming "two families lie"
    // about ANY piece, while another lies nowhere and the
    // receiver can open nothing.
    for (var i = 0; i < pieces.length; i++) {
      final out = delivery.send(
          peer: peer,
          payload: pieces[i],
          mode: mode,
          messageId: messageId,
          transferId: attempt,
          piece: i,
          management: management);
      if (!out.accepted) {
        return SendOutcome.refused(out.refusal);
      }
      legs += out.legs;
    }
    return SendOutcome.accepted(legs,
        pieces: pieces.length, transferId: attempt);
  }

  /// Refills that the delivery did not accept.
  ///
  /// No reason to let the message itself fail — the supply
  /// then simply stays empty and the next attempt visibly falls back to
  /// the static key (`fallbackCount`).
  int refillsRefused = 0;

  /// Prekey refills that arrived without an attributable sender.
  int refillsWithoutPeer = 0;

  /// Prekey refills whose encoding could not be read (E1).
  ///
  /// The one expectable reason is a sender in the pre-E1 format
  /// (`count ‖ [index ‖ x25519]*`, without the batch ML-KEM). If the
  /// number rises, two versions are talking to each other.
  int refillsMalformed = 0;

  /// The pair key `K_AB` for a counterpart, or `null`.
  ///
  /// ONE SOURCE, NOT TWO. The host does not derive `K_AB` itself — it
  /// asks the delivery's pair registry, the same one from which
  /// `secureTag` and `livenessTag` come. A second derivation in the host
  /// would be exactly the drift through which the tag line and the sender MAC
  /// could silently diverge: the placement would then lie under a
  /// tag belonging to a different key than the MAC in the
  /// frame, and the receiver would discard a genuine message.
  ///
  /// `null` (not set, or no key for this counterpart)
  /// means: [sendFrame] rejects with `noPairKey`. An unauthenticated
  /// frame is NOT built.
  Uint8List? Function(String peer)? pairKeyFor;

  /// The receiver side of this identity.
  ///
  /// It MUST exist per identity and not per node: the sealing
  /// runs against the user KEM keys (§4.3/§4.6), and they belong
  /// to the identity. A node with two identities holds two openers
  /// and offers every reassembled payload to both — whoever
  /// gets it open was meant.
  ///
  /// ── THE SETTER WIRES THE ONE-TIME PREKEYS (S355) ────────────────
  ///
  /// It does so here and not at the construction site (`v41_attach.dart:468`)
  /// for a reason that has already cost money once: the construction site
  /// does not know the supplies — they lie in the host. Whoever wanted to supply the opener there
  /// with callbacks would have to bind `host` late and
  /// could forget it; exactly this class ("built, not trodden")
  /// kept §4.6 unused for six sessions. A setter cannot be
  /// forgotten: whoever sets the opener wires it.
  MessageOpener? get opener => _opener;

  set opener(MessageOpener? o) {
    _opener = o;
    if (o == null) return;
    o.oneTimeSecret = _oneTimeSecretFor;
    o.oneTimeUsed = _oneTimeUsed;
    o.candidateCount = _candidatesNumber;
  }

  /// How expensive a full pass would be: all unused prekeys of all
  /// supplies plus the long-lived key.
  ///
  /// The opener charges it IN ADVANCE with it (`MessageOpener.maxProbesPerSecond`,
  /// version C): what is protected is compute time, so the limit must know
  /// what a cell costs. The number is cheap — a sum over the
  /// supply lengths, not a pass.
  int _candidatesNumber() {
    var n = 1; // the long-lived key, step 3 of the fallback ladder
    for (final p in _ownPools.values) {
      n += p.unused;
    }
    return n;
  }

  MessageOpener? _opener;

  // HERE STOOD `unknownPrekeySelectors` AND `expiredPrekeySelectors`
  // (merged on 30.08.2026 with version B of §4.6).
  //
  // They separated "the selector points to a prekey that never
  // existed here" from "to one whose epoch is older than the
  // retention period". §4.6 expressly calls the second case
  // "silent message loss", and the separation was the only place at
  // which it became visible.
  //
  // IT IS NO LONGER MEASURABLE, and that is said here instead of concealed.
  // The counter selector carried an epoch in plaintext; the hash selector
  // carries none and cannot carry one — it is `SHA-256(pk_i ‖ eph_pk)`,
  // and an expired prekey is deleted, so there is no `pk_i`
  // left to hash against. An expired and a never
  // existing selector look identical from here. Keeping two counters
  // of which one can never count up would be a
  // claim.
  //
  // What remains and what takes their place:
  //   * `MessageOpener.unresolvedSelectors` — "no candidate matched",
  //     the one honest number, measured where all candidates
  //     come together (supplies AND long-lived key);
  //   * [expiredPrekeysSwept] — the expiry measured from the OTHER side:
  //     not "a cell came too late", but "this many
  //     prekeys were thrown away by the deadline". That is weaker (it says
  //     nothing about lost messages), but it is a measurement.

  /// How many unused prekeys the retention period has thrown away.
  ///
  /// If this number rises in an operation in which writing happens regularly,
  /// then supplies are minted and never retrieved — the indication
  /// that refills do not reach the sender.
  int expiredPrekeysSwept = 0;

  /// How many one-time prekeys were really consumed.
  int oneTimePrekeysConsumed = 0;

  /// Looks up `sk_n` — across ALL supplies, without consuming.
  ///
  /// Across all, because an incoming cell does not name the sender
  /// (invariant 3): the contact for whom the batch was minted is
  /// only known from the opened frame. The price is the only
  /// notable running cost of the receiving side —
  /// `sum of the supplies` times 0.947 us per cell, with 20 contacts
  /// 152..303 us; the full calculation stands at `PrekeySelector`.
  ///
  /// NO COUNTER HERE ANY MORE. `null` means "none of my prekeys", and
  /// that is also the case when the counterpart has quite correctly fallen back
  /// to the long-lived key (step 3 of the ladder). Whoever
  /// counted "unknown" at this point would count every first contact as a
  /// disturbance. Counting therefore happens in the opener, which also knows the last
  /// candidate (`MessageOpener.unresolvedSelectors`).
  PrekeyMatch? _oneTimeSecretFor(Uint8List selector, Uint8List ephPk) {
    for (final p in _ownPools.values) {
      final hit = p.matchSelector(selector, ephPk);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Deletes `sk_n` — AFTER successful unsealing (§4.6 point 3).
  ///
  /// [index] comes back from the hit of the candidate probe, not from
  /// the selector: the prekey cannot be determined a second
  /// time from a hash without repeating the whole probe. All that is still
  /// searched for is in WHICH supply it lies — and because the counting space
  /// is identity-wide ([_prekeyIndices]), that can be at most
  /// one.
  void _oneTimeUsed(int index) {
    for (final e in _ownPools.entries) {
      final p = e.value;
      if (!p.holds(index)) continue;
      p.consume(index);
      oneTimePrekeysConsumed++;
      // CONSUMED MUST STAY CONSUMED — also across a crash.
      // As long as the deletion stands only in memory, an
      // older store brings back the `sk_i` and cancels the
      // forward secrecy without anything failing.
      prekeyStateDirty = true;
      _supplyAfterReception(e.key);
      return;
    }
  }

  /// When a top-up last happened from the RECEIVE PATH, per counterpart —
  /// as epoch number (24 h, [kEpochSeconds]).
  final Map<String, int> _supplyEpoch = <String, int>{};

  /// How often the receive path has triggered a refill.
  ///
  /// Counter-number to [oneTimePrekeysConsumed]: if it stays at 0 while
  /// consumption rises, the resupply is again only running on sending.
  int receiveSideRefills = 0;

  /// Tops up when RECEIVING has emptied the supply (§4.6 no. 1).
  ///
  /// ── WHY THE SEND PATH IS THE WRONG PLACE FOR THIS (S376, finding 5) ─
  ///
  /// `refillIfNeeded` had EXACTLY ONE caller: `sendFrame`. But the own supply
  /// is consumed on RECEIVING — every incoming cell
  /// that was sealed against one of our one-time prekeys takes one
  /// with it ([_oneTimeUsed], called from `message_seal.dart` AFTER the AEAD).
  /// §4.6 no. 1 says exactly that: consumption becomes "visible on harvest".
  ///
  /// A one-sided conversation — someone writes, we only read — thus emptied
  /// the supply after 16 messages (`PrekeyPool.batch`), and
  /// after that the pair silently fell back to the static anchor (step 3
  /// of the ladder, §4.6). Silently, because nothing fails anywhere: the anchor
  /// carries, only without the forward secrecy of the one-time prekeys. A
  /// message `PREKEY_CONSUMED` that could inform the other side
  /// does not exist — §14.3 lists it in the proto as `reserved`.
  ///
  /// ── WHY THIS IS NO ADDITIONAL TRAFFIC (working rule 5) ──────
  ///
  /// Sending only happens when the supply has REALLY fallen below the threshold
  /// (`PrekeyPool.needsRefill`) — the same condition as in the
  /// send path. The trigger moves to where the consumption arises;
  /// it does not arise anew. In addition at most ONE refill per
  /// counterpart and epoch, so that a counterpart that writes a lot
  /// does not repeatedly cost egress when the first attempt does not
  /// arrive.
  ///
  /// ── CAUGHT ──────────────────────────────────────────────────────
  ///
  /// The call lies in the middle of unsealing. A throw here — say from the
  /// delivery — would tear down the opening of the message that just arrived
  /// with it, although the AEAD has already held. The message is
  /// more important than the refill.
  void _supplyAfterReception(String peer) {
    if (peer.isEmpty) return;
    final now = DateTime.now().toUtc();
    final epoch = now.millisecondsSinceEpoch ~/ 1000 ~/ kEpochSeconds;
    if (_supplyEpoch[peer] == epoch) return;
    try {
      // THE EPOCH IS ONLY BOOKED WHEN A TOP-UP REALLY HAPPENED.
      // Whoever set it on merely looking would block the
      // refill for the rest of the day — precisely for the
      // case in which the supply only runs low later in the day.
      if (refillIfNeeded(peer: peer, now: now) != null) {
        _supplyEpoch[peer] = epoch;
        receiveSideRefills++;
      }
    } catch (e) {
      prekeyRefillErrors++;
    }
  }

  /// Throws from the resupply in the receive path. Visible, because a
  /// caught throw would otherwise produce the same silence against which this
  /// resupply is built.
  int prekeyRefillErrors = 0;

  /// Accepts a reassembled, still sealed payload.
  ///
  /// Returns the application frame, `null` otherwise. `null` is the
  /// NORMAL CASE and not an error: dummy cells, cells of foreign pairs and
  /// prekey refills all look the same here.
  ({String peer, Uint8List mac, Uint8List frame})? acceptSealed({
    required String peer,
    required Uint8List sealed,
    DateTime? now,
  }) {
    final onto = opener?.open(sealed);
    if (onto == null) return null;
    // ── THE SENDER FROM THE TAG LINE (path A, S352) ──────────────────
    //
    // HERE STOOD `accept(peer: '', ...)`, and that was the reason for which
    // the signature was introduced at all. The harvest KNOWS the
    // sender: `V41Node._geerntetVon(peer, zelle)` is called from the
    // tag-bound branch, and the tag can only be computed with `K_AB`.
    // This information was thrown away one level lower, and
    // the application was left only with the freely claimable `senderUserId` in the
    // frame — B-20. A piece of evidence (the signature) was issued
    // to replace information that was already available.
    //
    // [peer] is the pair identifier in the Secure path
    // (`<own64>/<foreign64>`), EMPTY in the Speed path: there the onion
    // addresses, and §4.3 expressly says "in Speed-Mode there is **no
    // field tag**". Both cases go on — the sender check
    // is done by the application via the MAC, which holds in both modes; the
    // pair identifier is the ADDITIONAL information that only Secure has.
    //
    // [now] ONLY TRAVELS THROUGH (S367). `null` means "unknown" and lets
    // [PeerPrekeys.receive] fall back to the wall clock — that is the
    // operating case and remains so for the only caller in `lib/`
    // (`v41_attach.dart`, which calls without this argument). A caller that
    // KNOWS a receive time — say a test with a fixed time base —
    // can feed it in bindingly from here, instead of it being silently replaced one level
    // lower by the real clock.
    final body = accept(peer: peer, plaintext: onto, now: now);
    if (body == null) return null;
    if (body.length < V41Kind.senderMacBytes) return null;
    return (
      peer: peer,
      mac: Uint8List.sublistView(body, 0, V41Kind.senderMacBytes),
      frame: Uint8List.sublistView(body, V41Kind.senderMacBytes),
    );
  }

  /// Accepts an opened payload.
  ///
  /// Returns the application frame, or `null` if it was a
  /// refill — that disappears here and never shows up in the
  /// application.
  Uint8List? accept({
    required String peer,
    required Uint8List plaintext,
    DateTime? now,
  }) {
    final u = V41Kind.unwrap(plaintext);
    if (u == null) return null;
    switch (u.kind) {
      case V41Kind.appFrame:
        return Uint8List.fromList(u.body);
      case V41Kind.prekeyRefill:
        // DO NOT STORE UNDER AN EMPTY PEER. A batch under `''` would
        // not only be useless, it would mix the supplies of all counterparts.
        //
        // Since S352 `acceptSealed` passes the sender from the tag line
        // through, so this branch really takes effect in the SECURE path. In the
        // Speed path it stays empty — there is no field tag there (§4.3)
        // —, and there counting continues instead of storing. That is
        // without consequence as long as `oneTimePrekeysWired` stands: no
        // refills are sent at all, and if they are,
        // they normatively ride Secure (§4.6, see `refillIfNeeded`).
        if (peer.isEmpty) {
          refillsWithoutPeer++;
          return null;
        }
        final batch = PrekeyBatchCodec.decode(Uint8List.fromList(u.body));
        if (batch != null) {
          // `now` passes through to here (see [acceptSealed]) — `null`
          // lets [PeerPrekeys.receive] fall back to the wall clock as
          // before.
          theirs.receive(peer, batch, received: now);
          prekeyStateDirty = true;
        } else {
          // NOT SILENT. Since E1 a batch carries 1184 B more; a
          // sender in the old format (577 B) lands exactly here. Without
          // this number it would look like "no refill
          // came" — and the channel would permanently run on the
          // static fallback without anyone being able to name the
          // reason.
          refillsMalformed++;
        }
        return null;
      default:
        // Unknown kind: discard silently (E-83).
        return null;
    }
  }
}
