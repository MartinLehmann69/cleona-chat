// The DEVICE-BOUND tag line (§14.1, §14.7).
//
// ── WHAT DISTINGUISHES IT FROM THE SHARED LINE ───────────────────────
//
// §14.7 lists TWO lines for the own devices, and they answer
// different questions:
//
//   * The SHARED twin line `HKDF(K_own, "twin" ‖ epoch ‖ n)`
//     (`own_line.dart`) carries everything that is the same for ALL devices.
//     §14.7: "All of the user's own devices share `K_own` and harvest the
//     same tag line, so for the general types **a single delivery** … is
//     enough."
//
//   * This one, `HKDF(K_own, "device" ‖ deviceId ‖ n)`, carries the
//     opposite — §14.7 literally: it "is needed only where the payload
//     **differs per device**: Type 16 (key package), the initial
//     reconciliation (§14.6.3), and the delivery of delegated keys".
//
// Both are NO second delivery path. Like the invitation line
// (`invite_line.dart`) and the own line, this one too is a
// PSEUDO COUNTERPART in the `PairRegistry` whose pair secret is a
// derived 32 B value — the Secure mechanics are generic over a
// secret and not bound to `K_AB`. Placement, responsibility set,
// harvest, split and reassembly are the same mechanics as for
// every other message.
//
// The family `n` from the formula is the `family` of [secureTag]; the
// two HKDF steps together — first [deriveKDevice], then `secureTag` —
// are exactly `HKDF(K_own, "device" ‖ deviceId ‖ n)`. The same decomposition
// as with the invitation line, where `K_inv(i)` delivers the root and `secureTag`
// the family.
//
// ── THE DIRECTION: A ROLE, NOT AN ORDER ──────────────────────────────
//
// The question here is NOT the same as with the shared line, and it
// is not answered the same way either.
//
// With the shared line §14.7 abolishes the direction question: all
// place onto the same line and harvest from it, inbound and outbound direction
// are the same, and the sender sorts out its own placement one layer
// higher by the `sync_id`.
//
// Here the line is assigned to ONE device, and from that follow two
// things that must be kept apart:
//
//   1. **The direction results from the ROLE, not from an order** —
//      the same situation as on the invitation line. B-22 determines the
//      direction of a pair from the lexicographic order of the two
//      FOUNDING KEYS; here there is only one (it is the same
//      identity), and the order cannot order a self-relation.
//      Unlike the invitation line there are moreover
//      not two roles here, but up to four placing siblings and
//      exactly one harvester — a pairwise direction would not be
//      definable even if one wanted it.
//
//      Therefore: ONE fixed direction, [kDeviceLineDirection], on both
//      sides. The placer takes it as outbound, the owner of the
//      line as inbound direction.
//
//   2. **Separation is not via the direction, but via WHO
//      HARVESTS THIS LINE.** That is the difference from the shared
//      line, and it is the actual point of this component. If
//      a sibling harvested the line of another device too, it would get
//      exactly what §14.7 wants to prevent: material meant for another
//      device. It could even open it — §14.2: "All
//      devices share the user KEM SK → all can unseal the same cell" —,
//      and exactly therefore the sealing does NOT carry this separation.
//
//      A device therefore registers its own line as an ordinary
//      counterpart (place and harvest) and the line of every sibling
//      ONLY FOR PLACING (`PairRegistry.remember(..., harvest: false)`).
//      Without this distinction the line would be built and ineffective.
//
// ── SECURE, AND FROM THE DOCUMENT ─────────────────────────────────────
//
// §14.7 assigns the three device-bound uses to Secure mode
// ("Key packages (Type 16) ride Secure with the 31-day management TTL";
// the initial reconciliation is the manifest-and-fetch machinery from §13.5.2,
// the delivery of delegated keys belongs to device admission).
// None of them is latency-critical. The carrier is therefore registered with
// `setChatMode(secure: true)`, and that has a measured
// price: `publishLiveness` skips Secure counterparts
// (`v41_node.dart`, `_secureOnly`), so a device line costs ZERO
// liveness cells. Without this line every device would publish a
// return path per line — with five devices (§14.8) `min(R, bekannte)` = up
// to 20 cells per line and day, for a path that nobody takes.
//
// ── WHICH DEVICE IDENTIFIER, AND WHY NOT THE OTHER ───────────────────
//
// §14.1 writes "deviceId". The build knows TWO identifiers at this place,
// and the document knows only one — the choice is therefore a
// named substitution and not a detail:
//
//   * `CleonaService._localDeviceId` — a UUID, generated per IDENTITY
//     and held in `devices.json` (`_initLocalDevice`).
//   * `IdentityContext.deviceNodeId` — `computeDeviceNodeId` over the
//     daemon-global device sig key, i.e. one per DEVICE, the same across
//     all identities of the same daemon (§3.1 C-1).
//
// [deviceNodeId] is taken, for three verifiable reasons:
//
//   1. §14.1 justifies the line by it being "derivable **without any
//      lookup**". The recipient knows its `deviceNodeId` as a field
//      of the identity; `_localDeviceId` stands in a loaded store
//      that is empty before `_initLocalDevice()`.
//   2. All three places in the build that name a target device today
//      carry the device node ID: `approvePairRequest` (from
//      `_pendingPairRequests`, filled from `frame.senderDeviceId`),
//      `rejectRotation` (`pending.requestingDeviceId`) and
//      `_handleDelegationRotation`, which compares against
//      `bytesToHex(identity.deviceNodeId)`. With the UUID
//      the send side would need a mapping node ID -> UUID, and
//      exactly for the most important case — a device that is just being
//      admitted — this mapping does not yet exist.
//   3. The UUID differs per identity, but the line is to address a
//      DEVICE. Two identities of the same device have
//      different `K_own` anyway and thus different lines; the
//      separation is achieved by the designator (see [deviceLineKey]), not by the
//      identifier.
//
// **As soon as `DeviceRecord` no longer carries the device node ID or §14.1
// explicitly names one of the two identifiers, this choice must be
// decided anew.** Until then it stands here and not scattered across the build.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../crypto/sodium_ffi.dart';
import '../util/hex.dart';

/// Prefix of the pseudo counterpart of a device line.
///
/// It must be distinguishable from every real pair designator:
/// `_v41PeerKey` builds `<eigen64>/<fremd64>` from two hex identifiers, and a
/// colon does not occur in it. The same procedure as with
/// `kOwnPeerPrefix` (`own_line.dart`) and `kInvitePeerPrefix`
/// (`invite_line.dart`).
const String kDevicePeerPrefix = 'dev:';

/// Inbound AND outbound direction of the device line.
///
/// **One value for both roles**, and the derivation is in the file header:
/// B-22 does not order a self-relation, and up to four placers
/// against one harvester are no pair. Separation is not via the
/// direction, but via who harvests the line.
const int kDeviceLineDirection = 0;

/// The local designator of the device line of [deviceNodeId] under the
/// identity [userId].
///
/// **The identity identifier MUST be in it** (B-31). The `PairRegistry`
/// sits NODE-WIDE, and the device node ID is daemon-globally identical
/// for all identities of the same process (§3.1 C-1,
/// `identity_context.dart`). Without the identity in the designator
/// two identities of the same device would carry the same entry — with
/// different `K_own`, i.e. different secrets. The second
/// registration would overwrite the first, and one of the two
/// identities would afterwards harvest under a tag that nobody serves.
/// That is the same error that B-31 already cost once for `_v41PeerKey`.
String deviceLineKey(Uint8List userId, Uint8List deviceNodeId) =>
    '$kDevicePeerPrefix${bytesToHex(userId)}/${bytesToHex(deviceNodeId)}';

/// Whether [peer] denotes a device line.
bool isDevicePeer(String peer) => peer.startsWith(kDevicePeerPrefix);

/// Derives the root of the device line from `K_own` (§14.1, §14.7).
///
/// `HKDF(K_own, "device" ‖ deviceId)`. The family `n` from the formula of the
/// document comes one step later from `secureTag` — reasoning for the
/// decomposition in the file header.
///
/// OWN SALT, the same as with `deriveKOwn` (`cleona-own`), but a
/// different `info` branch. Both come from the same supply and belong
/// together; they must be separated from `cleona-secure` (pair lines),
/// `cleona-v41-invite` (invitation) and `cleona-recovery` (§13).
///
/// NO ACCIDENTAL COLLISION WITH `K_own` ITSELF: `deriveKOwn` uses
/// `info` = `K_own/v1`, this function `device/v1/<hex>`. Two
/// different `info` strings cannot yield the same value
/// without breaking HKDF.
Uint8List deriveKDevice({
  required Uint8List kOwn,
  required Uint8List deviceNodeId,
}) {
  if (kOwn.length != 32) {
    throw ArgumentError('K_own must be 32 B, is ${kOwn.length}');
  }
  if (deviceNodeId.isEmpty) {
    throw ArgumentError('Device line needs a device identifier');
  }
  return SodiumFFI().hkdfSha256(
    kOwn,
    salt: Uint8List.fromList(utf8.encode('cleona-own')),
    info: Uint8List.fromList(
        utf8.encode('device/v1/${bytesToHex(deviceNodeId)}')),
    length: 32,
  );
}
