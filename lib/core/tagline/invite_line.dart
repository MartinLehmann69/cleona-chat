// The invitation line of first contact (§15.3.2, §15.4).
//
// ── WHAT IS NOT HERE, AND WHY THAT IS THE WHOLE POINT ────────────────
//
// There is NO second delivery path here. §15.3.2 writes the line as
//
//     σ(i, e) = HKDF(K_inv(i), "shard" ‖ epoch_e)
//
// and that is literally the same form as the pair line
// `secureTag(K_AB, epoch, family, direction)` (`secure_mode.dart`).
// The built Secure mechanism is generic over a 32-B secret anyway
// and not bound to `K_AB` — `v41_node.dart` stores in one place
// under a PROBE secret with the same function.
// That is why the invitation line here is a PSEUDO-COUNTERPART in the
// `PairRegistry` whose pair secret is `K_inv(i)`, and nothing more.
//
// The gain is not economy but uniformity: storing, responsibility set,
// harvest, splitting and reassembly are the same mechanism as for any
// other message. A path of its own would be a second path to the same
// thing, and such paths drift apart.
//
// ── THE DIRECTION FOLLOWS FROM THE ROLE, NOT FROM THE ORDER ──────────
//
// B-22 determines the direction of a pair from the lexicographic
// order of the two FOUNDING KEYS — both sides compute the same thing
// without coordination. On the invitation line that does not work: the
// issuer does not know the requester yet and has nothing to order.
//
// Here the direction therefore follows from the ROLE: the requester stores
// under 0, the issuer registers with outgoing direction 1 and thereby
// harvests (`inDirectionFor = 1 - out`) under 0. This is the only
// exception to B-22 in the whole tree, and it ends with the answer — from
// then on `K_AB` exists, and with it the order.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../crypto/sodium_ffi.dart';
import '../util/hex.dart';

/// Prefix of the pseudo-counterpart of an invitation line.
///
/// It must be distinguishable from every real pair identifier:
/// `_v41PeerKey` builds `<own64>/<foreign64>` from two hex identifiers, and
/// a colon does not occur in it. The sink decides by
/// [isInvitePeer] whether it has to apply the type binding from §15.3.2.
const String kInvitePeerPrefix = 'invite:';

/// The outgoing direction of the REQUESTER on the invitation line.
const int kInviteRequesterDirection = 0;

/// The outgoing direction of the ISSUER.
///
/// It is 1 so that `PairRegistry.inDirectionFor` turns it into 0 — the
/// direction under which the requester stores. Whoever enters 0 here
/// harvests its own (empty) opposite direction and never finds anything.
const int kInviteIssuerDirection = 1;

/// The local identifier of the invitation line for [inviteKey].
///
/// ── WHY FROM THE KEY AND NOT FROM THE INDEX ──────────────────────────
///
/// The issuer knows the index `i` of its invitation, the requester does
/// not — the ContactSeed carries `ki`, not `i` (§15.3.1: „The
/// ContactSeed carries `K_inv(i)` and `exp` — **never** `invite_root`").
/// Computed from the key, both sides arrive at the same
/// identifier; that is not needed for operation (the identifier is
/// purely local), but it makes the log lines of both sides
/// comparable, and exactly that has already mattered for two
/// debugging efforts in this migration (B-22, B-31).
///
/// NO ADDITIONAL DISCLOSURE: whoever can recompute the identifier
/// already holds `K_inv(i)` — and with the class „published" that is
/// public anyway. So the identifier reveals nothing the
/// holder of the URI does not already know, and in particular it does not
/// reveal WHICH identity the invitation belongs to (§15.3.2: „not which node
/// it belongs to").
String invitePeerLabel(Uint8List inviteKey) {
  final ikm = Uint8List.fromList([
    ...utf8.encode('cleona-v41-invite/label/v1'),
    ...inviteKey,
  ]);
  return '$kInvitePeerPrefix${bytesToHex(SodiumFFI().sha256(ikm)).substring(0, 32)}';
}

/// Whether [peer] denotes an invitation line.
bool isInvitePeer(String peer) => peer.startsWith(kInvitePeerPrefix);

/// The SYMMETRIC part of the sealing from §15.4.
///
/// §15.4 normatively:
///
///     seal_key = HKDF( K_inv(i) ‖ X25519(eph_sk, X_B) [ ‖ ML-KEM.Encaps(M_B) ] )
///
/// [MessageSealer] forms the session key as `HKDF(ss_pq ‖ dh)`.
/// This function supplies the `ss_pq` of that formula: the place where
/// ordinary traffic has the encapsulation secret carries, on
/// first contact, the invitation key.
///
/// ── WHAT THIS CARRIES AND WHAT NOT (§15.4, roles from §15.1) ─────────
///
///   * Against the **co-invitee** who knows `K_inv(i)`: he has
///     `ss_pq`, but not the secret for `X_B`. Without `dh` no key.
///   * Against the **relay archivist with CRQC** for a CONFIDENTIALLY
///     handed-over invitation: `ss_pq` is 256 bits symmetric and
///     unknown to him — he can break X25519 and still does not get through.
///   * For a PUBLISHED invitation it does NOT hold. The archivist
///     knows `K_inv(i)` and breaks X25519. That is not negligence
///     but the deviation §15.4 explicitly declares („A
///     request without PQ material in the seed carries no ML-KEM and
///     thereby deviates from the cell format"). It is closed
///     as soon as the seed carries the field `mk` (§15.5, „extended only") —
///     the encapsulation branch of the opener is already in place for it.
///
/// A SEPARATE derivation and not `K_inv(i)` raw: the key in the seed
/// already carries the tag line (`secureTag`). Using the same value additionally
/// as seal key would mean hanging two independent tasks on
/// one number — the same reasoning by which `v41_host.dart` draws
/// `secureTag`, `livenessTag` and `pairAnchor` separately from `K_AB`.
Uint8List inviteSealSecret(Uint8List inviteKey) {
  if (inviteKey.length != 32) {
    throw ArgumentError('K_inv(i) must be 32 B, is ${inviteKey.length}');
  }
  return SodiumFFI().hkdfSha256(
    inviteKey,
    salt: Uint8List.fromList(utf8.encode('cleona-v41-invite')),
    info: Uint8List.fromList(utf8.encode('cleona-v41-invite/seal/v1')),
    length: 32,
  );
}
