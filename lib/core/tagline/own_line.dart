// The OWN tag line — the twin sync (§14.1, §14.7).
//
// ── WHAT IS NOT HERE, AND WHY THAT IS THE POINT ────────────────
//
// No second delivery path. §14.7 describes the line as
//
//     HKDF(K_own, "twin" ‖ epoch ‖ n)
//
// and that is the same form as the pair line
// `secureTag(K_AB, epoch, family, direction)` (`secure_mode.dart`). The
// built Secure mechanism is generic over a 32-B secret and
// not bound to `K_AB`. The own line is therefore — just like the
// invitation line (`invite_line.dart`) — a PSEUDO-COUNTERPART in the
// `PairRegistry` whose pair secret is `K_own`, and nothing more.
//
// ── THE DIRECTION: HERE INPUT AND OUTPUT ARE THE SAME ────────────────
//
// That is the point at which a self-relationship differs from every pair,
// and the reason why the twin sync has not worked at all since the
// CUT (gap G-14). The comment at the old
// failure site in `cleona_service.dart` named it correctly:
//
//   * `K_AB` needs TWO founding keys; with self-sending it is
//     twice the same.
//   * B-22 determines the direction from the lexicographic order of the
//     two keys — a self-relationship does NOT order them. Both
//     twins compute 0, store under 0 and harvest per
//     `inDirectionFor` (`1 - 0`) under 1. No twin would ever find the
//     stored item of the other.
//
// §14.7 does not solve this with a direction, but by abolishing the
// question — verbatim: „All of the user's own devices share `K_own`
// and harvest **the same tag line**, so for the general types **a single
// delivery** … is enough. The triggering sender recognizes its own
// delivery by the `sync_id` and ignores it — the sender excludes
// itself."
//
// ONE line onto which all store and from which all harvest. Input and
// output direction are therefore EQUAL ([kOwnLineDirection]), and the
// sender finds its own stored item again — that is not a bug
// but the construction. It is sorted out one layer higher by the
// `sync_id`, which `_sendTwinSync` pre-registers in `_processedSyncIds`
// before sending.
//
// ── WHAT `K_own` IS DERIVED FROM, AND WHY IT IS NOT THE „SHARED KEY" ───
//
// §14.7: „`K_own` is the cross-device own material; it derives from the
// shared key and therefore rotates with every device-set change
// (§14.4)." The `shared_key` from §14.4 — random per device set,
// wrapped per device with its device key — **does not exist in the
// build.** Re-measured: `LinkedDeviceKeys` (what an
// attached device really gets at admission) carries
// `delegatedEd25519*`, `delegatedMlDsa*`, `userX25519Sk`, `userMlKemSk`,
// the delegation proof, `userId` and the display name — no
// shared key.
//
// What is needed is a secret with exactly two properties: **all
// my devices have it, and no one else.** Exactly that is provided by the
// user KEM secrets, and not by chance but according to §14.2
// and §14.6.2 by construction: „All devices share the user KEM SK → all
// can unseal the same cell", and the admission table of §14.6.2 lists
// „**User KEM SK** (X25519 + ML-KEM-768) | so **all** devices unseal the
// same cell".
//
// The rotation property demanded by §14.4 thus holds as well,
// and at the place where it is needed: the user KEM
// keys rotate along at LOCK-OUT („That is why this rotates
// along at lock-out too"), so a locked-out device loses with
// them also `K_own` and thus the twin line — structurally, not
// rule-based. On mere ADDING they do not rotate, and §14.4
// says itself why that is right: „on mere adding, this is not
// needed, because no one is excluded" — the new device gets the
// user KEM keys anyway (§14.6.2) and computes the same line.
//
// **BOTH keys enter, not just one.** If only one of the
// two rotates, `K_own` must still change; one input would otherwise be
// a silent exception.
//
// **This is a substitution and it is named.** As soon as the `shared_key`
// from §14.4 is built, it belongs in here — then `K_own` rotates
// on adding too, which is stricter than necessary but closer to the
// document. Until then a field pointing to an unbuilt
// key would be exactly the dummy this migration must not
// produce.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../crypto/sodium_ffi.dart';
import '../util/hex.dart';

/// Prefix of the pseudo-counterpart of the own line.
///
/// It must be distinguishable from every real pair identifier:
/// `_v41PeerKey` builds `<own64>/<foreign64>` from two hex identifiers, and
/// a colon does not occur in it. The same procedure as for
/// [kInvitePeerPrefix] in `invite_line.dart`.
const String kOwnPeerPrefix = 'own:';

/// Input AND output direction of the own line.
///
/// **Both, and that is the whole peculiarity.** The reasoning is
/// in the file header; the implementation demands that `PairRegistry.remember`
/// is called with `inDirection: kOwnLineDirection` — the default value
/// `1 - out` would be exactly the bug here that B-22 fixes for pairs.
const int kOwnLineDirection = 0;

/// The local identifier of the own line of this identity.
///
/// The identity identifier is in it because the `PairRegistry`
/// sits NODE-WIDE (B-31): two identities in one process have
/// different `K_own` and must not share the same entry.
String ownPeerKey(Uint8List userId) => '$kOwnPeerPrefix${bytesToHex(userId)}';

/// Is [peer] the own line?
bool isOwnPeer(String peer) => peer.startsWith(kOwnPeerPrefix);

/// Derives `K_own` from the user KEM secrets (§14.7).
///
/// Derivation and the named substitution of the `shared_key`: file header.
///
/// Own salt, separate from `cleona-secure` (pair lines) and
/// `cleona-recovery` (§13). Two derivations with the same salt and
/// different inputs would not be wrong, but the separation makes
/// a mix-up of two secrets impossible instead of merely
/// unlikely.
Uint8List deriveKOwn({
  required Uint8List userX25519Secret,
  required Uint8List userMlKemSecret,
}) {
  if (userX25519Secret.isEmpty || userMlKemSecret.isEmpty) {
    throw ArgumentError('K_own needs both user KEM secrets');
  }
  return SodiumFFI().hkdfSha256(
    Uint8List.fromList(<int>[...userX25519Secret, ...userMlKemSecret]),
    salt: Uint8List.fromList(utf8.encode('cleona-own')),
    info: Uint8List.fromList(utf8.encode('K_own/v1')),
    length: 32,
  );
}
