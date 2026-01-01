import 'dart:convert';
import 'dart:typed_data';

import '../crypto/sodium_ffi.dart';

/// The pair keys known to the delivery layer.
///
/// WHAT WAS MISSING HERE. The delivery layer knew positions and partners —
/// i.e. infrastructure. It knew no PAIRS. Thus `livenessTag`
/// and `secureTag` had no caller outside their own modules: both
/// need `K_AB`, and `K_AB` did not exist in this layer. WP-2 and
/// WP-4 were therefore built and dead.
///
/// WHAT DOES NOT BELONG HERE. Contacts, names, profiles, verification
/// levels — none of that. The delivery layer needs exactly one number per
/// counterpart, and the less it knows otherwise, the less it can
/// reveal. The key comes in from above; how it came about
/// is the business of the identity layer.
final class PairRegistry {
  final Map<String, Uint8List> _kAb = <String, Uint8List>{};

  /// A secret only this device knows.
  ///
  /// It carries the decoy tags (§6): the harvest asks, besides the real tags,
  /// `d` invented ones too, and those must stay EQUAL between two queries of the same
  /// epoch — otherwise the set of changing tags would itself
  /// be the signal. That is why derived and not rolled.
  final Uint8List deviceSecret;

  PairRegistry({required this.deviceSecret}) {
    if (deviceSecret.length != 32) {
      throw ArgumentError('Device secret must be 32 B');
    }
  }

  /// Derives the device secret from a long-lived key.
  static PairRegistry fromNodeSecret(Uint8List nodeSecret) => PairRegistry(
        deviceSecret: SodiumFFI().hkdfSha256(
          nodeSecret,
          salt: Uint8List.fromList(utf8.encode('cleona-device')),
          info: Uint8List.fromList(utf8.encode('decoys/v1')),
          length: 32,
        ),
      );

  int get length => _kAb.length;

  /// All known counterparts.
  Iterable<String> get peers => _kAb.keys;

  /// Counterparts that are ONLY SUPPLIED — never harvested.
  ///
  /// ── WHY THIS DISTINCTION IS NEEDED AT ALL ────────────
  ///
  /// For every real pair and for the own line it is empty: whoever
  /// stores also harvests. It is populated solely for the DEVICE LINE
  /// of a sibling (`device_line.dart`). §14.7 gives it exactly the
  /// payloads that differ PER DEVICE — and §14.2 says
  /// at the same time that every device could OPEN the cell of every other
  /// („All devices share the user KEM SK → all can unseal the same
  /// cell"). The sealing therefore does not separate here; the separation is
  /// by WHO harvests the line.
  ///
  /// Without this set the device line would be built and ineffective: every
  /// sibling would harvest the line of every other too and get exactly
  /// what §14.7 is supposed to prevent — material meant for another device.
  /// On top of that the price: every foreign line would draw six real tags per
  /// harvest run (`kMaxRealHarvestTags` = 6, i.e. a whole frame) from
  /// a budget that §9.2/§6 intends for contacts.
  final Set<String> _placeOnly = <String>{};

  /// Counterparts that are HARVESTED from — all except [_placeOnly].
  ///
  /// The harvest, the self-harvest, the liveness publication and the
  /// search for uncovered targets run over THIS set, not over
  /// [peers]. [peers] stays complete: whoever stores also needs the
  /// supplied ones.
  Iterable<String> get harvestPeers =>
      _kAb.keys.where((p) => !_placeOnly.contains(p));

  /// Whether [peer] is only supplied and never harvested.
  bool isPlaceOnly(String peer) => _placeOnly.contains(peer);

  /// The outbound direction per counterpart (B-22).
  final Map<String, int> _out = <String, int>{};

  /// Under which direction a counterpart is HARVESTED from, IF it
  /// is not the opposite direction of the output.
  ///
  /// Empty for every real pair — there `1 - out` applies, and it must
  /// stay that way (B-22). It is populated solely for the OWN line
  /// (`own_line.dart`): there all twins store onto THE SAME line
  /// and harvest from it, because §14.7 does not solve the direction question
  /// but abolishes it. A default value `1 - out` would be exactly the
  /// bug there that B-22 fixes for pairs — only the other way round.
  final Map<String, int> _in = <String, int>{};

  /// [harvest] `false` enters [peer] as a pure STORAGE target — see
  /// [_placeOnly]. The default value `true` is the normal case and changes
  /// nothing for any existing caller.
  void remember(String peer, Uint8List kAb,
      {int outDirection = 0, int? inDirection, bool harvest = true}) {
    if (kAb.length != 32) throw ArgumentError('K_AB must be 32 B');
    if (outDirection != 0 && outDirection != 1) {
      throw ArgumentError('Direction must be 0 or 1');
    }
    if (inDirection != null && inDirection != 0 && inDirection != 1) {
      throw ArgumentError('Inbound direction must be 0 or 1');
    }
    if (inDirection == null) {
      _in.remove(peer);
    } else {
      _in[peer] = inDirection;
    }
    // EXPLICITLY SET AND NOT ONLY ADDED. A second
    // `remember` for the same identifier must determine the state
    // COMPLETELY — otherwise a storage block once set would stay after
    // an ordinary re-entry, and the counterpart would
    // silently no longer be harvested.
    if (harvest) {
      _placeOnly.remove(peer);
    } else {
      _placeOnly.add(peer);
    }
    _kAb[peer] = Uint8List.fromList(kAb);
    _out[peer] = outDirection;
  }

  Uint8List? kAbFor(String peer) => _kAb[peer];

  /// Under which direction [peer] is STORED to.
  int outDirectionFor(String peer) => _out[peer] ?? 0;

  /// Under which direction [peer] is HARVESTED from — the other one.
  ///
  /// Without this distinction every side harvests its own stored items
  /// back and thereby displaces those of the counterpart (B-22, measured in the field on
  /// 28.08.).
  /// **Exception: the own line.** If an input direction is
  /// explicitly stored, it applies — see [_in]. For every real
  /// pair it is not, and then it stays at `1 - out`.
  int inDirectionFor(String peer) => _in[peer] ?? 1 - outDirectionFor(peer);

  void forget(String peer) {
    _kAb.remove(peer);
    _out.remove(peer);
    _in.remove(peer);
    _placeOnly.remove(peer);
  }
}

/// Derives the pair key `K_AB` from the user keys.
///
/// WHERE ELSE K_AB WOULD COME FROM: nowhere. The delivery layer needs
/// exactly one number per counterpart, and without it liveness and Secure tags
/// cannot be computed. The link between contact list and delivery
/// is this derivation — it is the last missing step before the seam
/// (IP-3).
///
/// THE SAME CONSTRUCTION AS `derivePairwiseSecret` (rendezvous), but with
/// its OWN DOMAIN. Two derivations from the same DH must not
/// yield the same key: if they were equal, a
/// rendezvous tag would reveal something about a mailbox line and vice versa. The
/// salt string is the whole difference and therefore fixed here,
/// not passed in.
///
/// SYMMETRIC: both sides arrive at the same number, because
/// `DH(a_sk, b_pk) == DH(b_sk, a_pk)`. Without that the two would have
/// different tags and would harvest past each other.
Uint8List deriveDeliveryPairKey({
  required Uint8List ownX25519Secret,
  required Uint8List peerX25519Public,
}) {
  if (ownX25519Secret.length != 32 || peerX25519Public.length != 32) {
    throw ArgumentError('X25519-Anteile muessen 32 B sein');
  }
  final sodium = SodiumFFI();
  final dh = sodium.x25519ScalarMult(ownX25519Secret, peerX25519Public);
  return sodium.hkdfSha256(
    dh,
    salt: Uint8List.fromList(utf8.encode('cleona-pair/v1')),
    info: Uint8List.fromList(utf8.encode('delivery')),
    length: 32,
  );
}

/// `K_AB` from the FOUNDING KEYS of both sides (§15.2, normative).
///
/// ── WHY NOT FROM THE CURRENT KEYS (S349) ─────────────────
///
/// [deriveDeliveryPairKey] computes over the current user X25519 parts.
/// That has two flaws, and the second is fatal:
///
/// **1. It does not survive rotation.** §15.2: „`K_AB` has exactly one
/// source: the founding keys of both sides … Because the founding keys are
/// the identity anchor stable across rotations (§4.1), `K_AB` survives
/// every key rotation without a transition window." Derived from current
/// keys, `K_AB` diverges at every rotation — and with
/// it `secureTag`, `livenessTag` and every other tag of the pair. The
/// delivery then fails **silently and completely**.
///
/// **2. On first contact it does not exist at all.** The requester has from the
/// counterpart only its **device** KEM (from the ContactSeed, `dxk`/`dmk`);
/// the user X25519 only comes WITH the answer. Whoever forms `K_AB` from current
/// keys cannot compute it before the answer arrives —
/// and thus cannot harvest the tag line on which the answer lies. Exactly
/// this circle was measured in the field on 28.08.: B stored the answer,
/// A never harvested, because `pairs.peers` stayed empty.
///
/// §15.2 solves both, because the founding key is known **before** the contact:
/// it travels as `ep` in the ContactSeed, and the UserID is its
/// hash. The requester can thus form `K_AB` **immediately** — „Seed read:
/// has Bob's founding pubkey (`fp`/`ep`) -> **can derive `K_AB`
/// immediately**".
///
/// The Ed25519 parts are converted to Curve25519 (libsodium
/// `crypto_sign_ed25519_{pk,sk}_to_curve25519`), then pairwise
/// Diffie-Hellman — deterministic, without asking back, both sides compute
/// the same independently.
/// The canonical outgoing direction of a pair (B-22, §15.2).
///
/// Both sides must compute the same without coordination, otherwise
/// one stores under a tag the other never harvests. The
/// lexicographic order of two public values achieves that: it is
/// total, it is antisymmetric, both sides know both values, and
/// no one has to send anything for it.
///
/// ── WHY THE FOUNDING KEYS AND NOT THE USER IDS (S353) ──────
///
/// Until S353 this function compared two **UserIDs**. That holds exactly as
/// long as no UserID changes — and V4.1 changed them all:
/// since §4.1 the derivation reads the public domain constant instead of
/// a derived network secret (`network_secret.dart`,
/// `identitySecret`), so EVERY identifier in the network was minted anew. On
/// 29.08. measured in the field: `0d1c821d` -> `10b3cc3f` and `2708863c` ->
/// `f64b2c3b`, while `K_AB` of both pairs stayed unchanged (it comes
/// from the founding keys, §15.2).
///
/// The damage is not the re-minting but that the two sides
/// do NOT see it AT THE SAME TIME: each side knows its own identifier
/// anew immediately, but that of the counterpart still as it stands in the contact record.
/// Then two identifiers from different
/// generations are compared — a different pair on each side. The invariant
/// „exactly one side stores under direction 0" then only holds
/// by chance; if it fails, both sides store under the same direction
/// and displace each other. That is B-22, reintroduced.
///
/// The founding key does not have this flaw: it is the
/// identity anchor that survives every rotation (§4.1), it travels as
/// `ep`/`fp` in the ContactSeed and is thus already on both sides BEFORE the first contact,
/// and it is exactly the value from which `K_AB` is derived
/// anyway (`deriveDeliveryPairKeyFromFounding`). Direction and tag
/// thus hang on THE SAME anchor — they can no longer
/// diverge without `K_AB` diverging too, and that is
/// visible instead of silent.
///
/// *Why not `K_AB` itself:* it is symmetric, both sides compute
/// the same value. From a symmetric value alone no
/// antisymmetric direction can be obtained; the ordered pair is needed.
///
/// **Existing data.** A change of the derivation shifts the tag lines
/// of a pair. What was stored under the old direction is then
/// no longer found — it expires with the normal period of the
/// storage instead of being delivered.
///
/// Returns: 0 if the own founding key is the lexicographically
/// smaller one, otherwise 1. Whoever sends takes this value; whoever harvests, the
/// other.
int outboundDirection({
  required Uint8List ownFoundingEd25519Pk,
  required Uint8List peerFoundingEd25519Pk,
}) {
  final a = ownFoundingEd25519Pk;
  final b = peerFoundingEd25519Pk;
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] < b[i] ? 0 : 1;
  }
  return a.length <= b.length ? 0 : 1;
}

Uint8List deriveDeliveryPairKeyFromFounding({
  required Uint8List ownEd25519Secret,
  required Uint8List peerEd25519Public,
}) {
  final sodium = SodiumFFI();
  final ownX = sodium.ed25519SkToX25519(ownEd25519Secret);
  final peerX = sodium.ed25519PkToX25519(peerEd25519Public);
  return deriveDeliveryPairKey(
    ownX25519Secret: ownX,
    peerX25519Public: peerX,
  );
}
