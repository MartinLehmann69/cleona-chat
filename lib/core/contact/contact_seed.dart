import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/codec/compression.dart';
import 'package:cleona/core/util/hex.dart' show hexToBytes, bytesToHex;
import 'package:cleona/core/service/readiness_names.dart' show kReadinessSearching;
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/contact/invite_class.dart';

// ── THE READ SIDE HAS BEEN DROPPED (S389, package 17 = A) ──────────────────
//
// Owner decision 15.09.2026 on finding K-1 (`S388-BAU-KENNUNG.md:211`),
// fix proposal (b): "Seed is no longer read on the V4.2 line — the
// card (§15.2) is the way." Reason: v4_2 §4.1 derives the identifier from
// Ed25519 AND ML-DSA-65; the seed carries only the Ed25519 anchor
// (`ep`/`fp`), so a reader could no longer recompute the claimed UserID
// and ran into `SeedRefusal.integrityFailed`. A reader that rejects
// every record is not a read side.
//
// Deleted (542 lines): `fromUri`, `_parseQuery`, `readQrBytes`,
// `fromQrBytes`, `_parseBinaryPayloadV41`, `qrFormatsObsolete`,
// `refusalAt`, `hasAnchor`, `isChannelCompatible`,
// `channelDisplayName`, `isInviteExpiredAt`, `inviteRemainingAt`,
// `ageFrom` and `enum SeedRefusal`; plus the three files
// `contact_seed_refusal.dart`, `contact_seed_invite_gate.dart` and
// `contact_seed_from_node_id.dart`.
//
// Measured before the cut (S389-BAU-APP.md §1.1): none of these members
// had a caller in `lib/` or `bin/`. The scanner branch already read
// only the card before (`qr_contact_screen.dart:132-156` via
// `invitation_card_reader.dart`), and `deep_link_receiver.dart:15-16`
// records that the URI path `cleona://<id>?…` is removed there.
//
// WHAT REMAINS is the write side: `ContactSeedBuilder.getContactSeedFor`
// and `toUri()` hang via `CleonaService.generateInviteLinkUrl` on
// `share_cleona_dialog.dart:12` and `settings_screen.dart:133`. With it
// remains `verifyIntegrity` — the issuer's SELF-check, which holds back
// a seed with a wrong anchor (`getContactSeedFor`). In the first
// measurement it was wrongly listed as a reader member; the analyzer
// reported that, see S389-BAU-APP.md §2.2.

/// ContactSeed: encodes identifier + reachability as a URI (ISSUING only).
///
/// **URI form (clipboard/sharing)**
/// `cleona://<userIdHex>?n=<name>&c=<b|l>&did=<deviceIdHex>&ep=<…>&dxk=<…>&dmk=<…>&a=<addrs>&s=<seedPeers>`
///
/// There is no reader of this form in this program any more. What a
/// counterpart reads in is the invitation card (§15.2, §15.6,
/// `invitation_card_reader.dart`).
///
/// - nodeIdHex: 64-char hex of the user's 32-byte UserID (§8.1.1).
/// - n: display name (URL-encoded)
/// - c: network channel ('b' = beta, 'l' = live)
/// - did: deviceId (64-char hex)
/// - ep: userEd25519Pk, 32 bytes, base64url — trust-anchor for Deferred
///   Key Exchange and DHT record verification. Integrity: SHA-256(networkSecret + ep) == nodeIdHex.
/// - dxk/dmk: Device-KEM keys (X25519 32B + ML-KEM-768 1184B, standard base64).
///   Enables offline first-CR on CGNAT without synchronous DEVICE_KEM_REQUEST.
/// - a: own addresses (multi-address, + encoded as %2B)
/// - s: seed peers (up to 5, each: nodeIdHex@ip:port+ip:port)
class ContactSeed {
  /// Length of the X25519 public key in bytes.
  static const int deviceX25519PkLength = 32;

  /// Length of the ML-KEM-768 public key in bytes.
  static const int deviceMlKemPkLength = 1184;

  final String nodeIdHex;
  final String displayName;
  final List<String> ownAddresses; // ip:port pairs
  final List<SeedPeer> seedPeers;
  /// 'b' (beta) or 'l' (live). In the QR profile `null` can no longer come
  /// from an old format (there is none) — only from a channel byte
  /// that is neither 0x62 nor 0x6C. `refusalAt` rejects that with
  /// [SeedRefusal.channelMissing].
  final String? channelTag;

  /// 64 characters hex. `null` if the field in the record consists of
  /// nothing but zero bytes — the issuer then had no device ID.
  final String? deviceIdHex;

  /// User-Ed25519 public key. 32 bytes, base64url in URI.
  ///
  /// Trust anchor of the seed: `SHA-256(networkSecret + ep) == nodeIdHex`
  /// (for softly rotated identities `fp` stands in this place).
  ///
  /// S376: here stood "verifies DHT DeviceKemRecords and DEVICE_KEM_OFFER
  /// signatures (§8.1.1)". The 2D DHT ring in which these records lay has
  /// been dropped with `lib/core/identity_resolution/` (v3_0 §4.3
  /// is REPLACED in V4.1, not renumbered), and `DeviceKemRecord` no
  /// longer exists in the tree. The anchor itself remains.
  final Uint8List? userEd25519Pk;

  /// Device-X25519 public key. 32 bytes. Included in URI format to enable
  /// offline first-CR (FIRST_CR_STORE) without Deferred Key Exchange.
  final Uint8List? deviceX25519Pk;

  /// Device-ML-KEM-768 public key. 1184 bytes.
  final Uint8List? deviceMlKemPk;

  /// Creation time of the seed (ms since epoch) — URI `t`, in the QR
  /// profile a fixed 8-B field. `null` means: the field was 0, so the
  /// issuer gave no time. The scanner uses it to distinguish an outdated
  /// seed ("get yourself a fresh code") from a counterpart that is just
  /// offline at the moment. Does NOT go into the integrity check.
  final int? createdAtMs;

  /// SR-2 (§8.1.1 / §3.1 stable anchor): founding User-Ed25519 pubkey —
  /// the key whose hash IS the userId. Only emitted when the identity has
  /// soft-re-keyed (`fp != ep`); the integrity check then anchors on `fp`
  /// instead of `ep`. The binding founding→current `ep` is proven by the
  /// rotation chain in the D1-verified Auth-Manifest at first resolution
  /// (§4.3 path 2). URI param `fp`, QR formats 0x09/0x0A.
  final Uint8List? foundingEd25519Pk;

  /// §4.11.10 First-Contact Rendezvous: 32-byte random nonce shared via the
  /// clipboard/share URI (param `r`, base64url). Owner and scanner derive
  /// URI-scoped lookup tags + encryption keys from it so both sides can find
  /// each other's endpoint addresses over the external rendezvous channel
  /// before the first CR succeeds. URI format only — QR/NFC are synchronous
  /// channels and stay unchanged. `null` for QR seeds and for URIs that
  /// do not use the procedure.
  final Uint8List? rendezvousNonce;

  /// §15.5 field `cls` — the invitation class, visible to the scanner.
  ///
  /// `null` means "the issuer said nothing" (every seed from the
  /// 3.x line). That is NOT the same as [InviteClass.published]: a
  /// missing statement must neither fake a promise nor refuse one.
  /// In that case the UI shows no class at all.
  final InviteClass? inviteClass;

  /// §15.5 field `exp` — expiry date of the invitation, in milliseconds
  /// since epoch. `null` means unlimited (§15.3.3: selectable 7/30/90 days
  /// or unlimited).
  ///
  /// **It binds the INVITATION, not the entry hints.** §15.3.3
  /// explicitly places them side by side: an expired seed gives the
  /// scanner an explicit error, while outdated entry hints in the same
  /// seed silently run into nothing. This asymmetry is intended and
  /// noted here so that it is not rediscovered as a bug.
  final int? inviteExpiresAtMs;

  /// §15.5 field `ki` — `K_inv(i)`, 32 B, the key of THIS invitation
  /// (§15.3.1).
  ///
  /// **What is in here and what explicitly is not.** In here is the key
  /// of ONE invitation. Not in here is the invitation root: §15.3.1 says
  /// it literally — "The ContactSeed carries `K_inv(i)` and
  /// `exp` — **never** `invite_root`. … no identity-wide material sits in
  /// the seed." If the root were in the seed, every recipient of an
  /// invitation could compute ALL invitations of the same identity and
  /// eavesdrop on their tag lines; the attribution "this invitation is
  /// open" would then be information about the person instead of about a
  /// sheet of paper.
  ///
  /// **The value is not secret everywhere, and that is intended.** With
  /// the class [InviteClass.published] it is public (notice board,
  /// business card) — then the symmetric part of the sealing (§15.4)
  /// carries nothing any more, and the PQ promise hangs solely on the
  /// ML-KEM material of the extended profile. Exactly this distinction
  /// is the whole purpose of the field `cls`.
  ///
  /// `null` = no invitation key in the seed. Every seed of the 3.x line
  /// is like that, and a seed without an invitation should not claim one.
  final Uint8List? inviteKey;

  /// Length of `K_inv(i)` in bytes.
  static const int inviteKeyLength = 32;

  ContactSeed({
    required this.nodeIdHex,
    required this.displayName,
    this.ownAddresses = const [],
    this.seedPeers = const [],
    this.channelTag,
    this.deviceIdHex,
    this.userEd25519Pk,
    this.deviceX25519Pk,
    this.deviceMlKemPk,
    this.createdAtMs,
    this.foundingEd25519Pk,
    this.rendezvousNonce,
    this.inviteClass,
    this.inviteExpiresAtMs,
    this.inviteKey,
  });

  /// §8.1.1 integrity check: `SHA-256(kIdentityDomain ‖ anchor ‖
  /// mldsa) == userId`, computed against `fp` (rotated identity),
  /// otherwise against `ep`.
  ///
  /// **This is the ISSUER'S SELF-CHECK, not a reader member.** It
  /// remains as the only piece of the former check chain because
  /// [ContactSeedBuilder.getContactSeedFor] calls it before a seed leaves
  /// the house: a seed whose anchor does not prove the announced UserID
  /// should not come into existence at all. Measured on 28.07.2026 on a
  /// multi-identity node: the issued URI carried Alice's nodeId with
  /// AllyCat's anchor.
  ///
  /// Without [mlDsaPk] the result is `false` — v4_2 §4.1 takes ML-DSA-65
  /// into the identifier, and a UserID that nobody can recompute is not
  /// proven. The issuer has the key (`foundingMlDsaPk`); the seed does not
  /// carry it, and exactly for that reason the read side has been dropped
  /// (finding K-1, S389).
  bool verifyIntegrity({Uint8List? mlDsaPk}) {
    final anchor = foundingEd25519Pk ?? userEd25519Pk;
    if (anchor == null || anchor.length != 32) return false;
    if (mlDsaPk == null) return false;
    final Uint8List derived;
    try {
      derived = HdWallet.computeUserId(anchor, mlDsaPk);
    } on ArgumentError {
      return false;
    }
    return bytesToHex(derived) == nodeIdHex.toLowerCase();
  }

  /// Build the URI string for clipboard / share (includes Device-KEM-PK
  /// when available so CGNAT-to-CGNAT first-CR works without synchronous
  /// DEVICE_KEM_REQUEST round-trip). QR uses [toQrBytes] (compact v2).
  String toUri() {
    final sb = StringBuffer('cleona://$nodeIdHex');
    sb.write('?n=${Uri.encodeComponent(displayName)}');

    // Channel tag: 1 char ('b' = beta, 'l' = live)
    if (channelTag != null) {
      sb.write('&c=$channelTag');
    }

    // Device ID, 64 characters hex. It stands only in the URI branch
    // conditionally; in the QR profile the field is fixed (zero bytes =
    // none).
    // S376: here stood "(V3.0 2-Layer-Frames). Optional for backward
    // compat" — the two-layer frames of the 3.x line no longer exist,
    // and there is nothing backwards that would have to be compatible.
    if (deviceIdHex != null && deviceIdHex!.isNotEmpty) {
      sb.write('&did=$deviceIdHex');
    }

    // Vertrauensanker `ep`, base64url (RFC 4648 §5).
    final ep = userEd25519Pk;
    if (ep != null && ep.length == 32) {
      sb.write('&ep=${base64Url.encode(ep).replaceAll('=', '')}');
    }

    // Device-KEM-PK: enables offline first-CR (FIRST_CR_STORE on seed
    // peers) without Deferred Key Exchange. Critical for CGNAT-to-CGNAT
    // clipboard exchange where both phones may not be online simultaneously.
    final dxk = deviceX25519Pk;
    final dmk = deviceMlKemPk;
    if (dxk != null && dxk.length == deviceX25519PkLength &&
        dmk != null && dmk.length == deviceMlKemPkLength) {
      sb.write('&dxk=${base64.encode(dxk)}');
      sb.write('&dmk=${base64.encode(dmk)}');
    }

    // Creation time: the scanner uses it to judge the age of the seed.
    if (createdAtMs != null) {
      sb.write('&t=$createdAtMs');
    }

    // SR-2: founding pubkey — only for rotated identities (fp != ep).
    final fp = foundingEd25519Pk;
    if (fp != null && fp.length == 32 && !_sameBytes(fp, ep)) {
      sb.write('&fp=${base64Url.encode(fp).replaceAll('=', '')}');
    }

    // §4.11.10 First-Contact Rendezvous nonce (URI-only, base64url).
    final rn = rendezvousNonce;
    if (rn != null && rn.length == 32) {
      sb.write('&r=${base64Url.encode(rn).replaceAll('=', '')}');
    }

    // §15.5: `cls` and `exp`. Both are written ONLY if they are set — a
    // seed without an invitation class should not claim one
    // (see `ContactSeed.inviteClass`).
    final cls = inviteClass;
    if (cls != null) {
      sb.write('&cls=${cls.wireChar}');
    }
    final exp = inviteExpiresAtMs;
    if (exp != null) {
      sb.write('&exp=$exp');
    }
    // §15.5 `ki` — base64url without padding characters, like `ep`, `fp` and `r`.
    final ki = inviteKey;
    if (ki != null && ki.length == inviteKeyLength) {
      sb.write('&ki=${base64Url.encode(ki).replaceAll('=', '')}');
    }

    if (ownAddresses.isNotEmpty) {
      // Join with + but encode as %2B in URI
      final joined = ownAddresses.join('+');
      sb.write('&a=${joined.replaceAll('+', '%2B')}');
    }

    if (seedPeers.isNotEmpty) {
      final peers = seedPeers.take(5).map((p) {
        final addrs = p.addresses.take(2).join('+');
        return '${p.nodeIdHex}@${addrs.replaceAll('+', '%2B')}';
      }).join(',');
      sb.write('&s=$peers');
    }

    return sb.toString();
  }

  // --- Compact QR binary format: EXACTLY ONE PROFILE (§15.5) ------------
  //
  // ── WHAT WAS DROPPED HERE ON 08.09.2026 (S376) ─────────────────────
  //
  // Until today this file knew FIVE format pairs and issued one of them
  // depending on which fields were filled:
  //
  //   0x01/0x02  v1  — 32 B dxk + 1184 B dmk, QR version 26-28
  //   0x03/0x04  v2  — 32 B ep instead of dxk+dmk, QR version 8-10
  //   0x07/0x08  v2 + 8 B timestamp
  //   0x09/0x0A  SR-2: + 32 B founding key
  //   0x0B/0x0C  V4.1 invitation profile (§15.5): + cls/exp/ki
  //
  // The first FOUR pairs are the 3.x line. V4.1 has no V3 compatibility,
  // neither data nor network (owner, 08.09.2026); a seed from that line
  // carries neither invitation class nor expiry date nor `K_inv(i)` and
  // is thus, according to §15.3/§15.5, not a valid first contact — it
  // could only be accepted here in order to fail later in delivery.
  //
  // There is therefore only ONE pair left, and it is ALWAYS issued:
  //
  //   0x0B = zstd-compressed V4.1 profile
  //   0x0C = uncompressed V4.1 profile
  //
  // ── THE RECORD LAYOUT IS FIXED ───────────────────────────────────────────
  //
  // All formerly conditional fields now ALWAYS stand, as zero bytes if
  // necessary. That costs 81 B before compression and spares the reader
  // the computation over three format bits — exactly the computation from
  // which the five pairs arose.
  //
  // Wire: [1B format] [payload]
  //
  // Payload (0x0B/0x0C):
  //   [32B userId] [32B deviceId] [32B userEd25519Pk]
  //   [8B createdAtMs]          0 = no timestamp
  //   [32B foundingEd25519Pk]   all zeros = no rotation, anchor is ep
  //   [1B cls] [8B expMs] [32B ki]
  //                             cls 0 = not specified, exp 0 = unlimited,
  //                             ki of all zero bytes = no key
  //                             (a real K_inv(i) is HKDF output and by
  //                             construction does not consist of zeros)
  //   [1B channel] [1B nameLen] [nameUTF8]
  //   [1B addrCount] [{1B len, addrUTF8}...]
  //   [1B peerCount] [{32B nodeId, 1B addrCount, {1B len, addrUTF8}...}...]
  //
  // Minimum length of the payload: 181 B.

  /// The only two format bytes that V4.1 issues and accepts.
  static const int qrFormatCompressed = 0x0B;
  static const int qrFormatUncompressed = 0x0C;

  /// Minimum length of the payload in the V4.1 profile (fixed record layout).
  ///
  /// 32 userId + 32 deviceId + 32 ep + 8 ts + 32 fp + 1 cls + 8 exp
  /// + 32 ki + 1 channel + 1 nameLen + 1 addrCount + 1 peerCount.
  static const int qrPayloadMinLength = 181;

  Uint8List toQrBytes() {
    final bb = BytesBuilder(copy: false);

    bb.add(hexToBytes(nodeIdHex));

    if (deviceIdHex != null && deviceIdHex!.length == 64) {
      bb.add(hexToBytes(deviceIdHex!));
    } else {
      bb.add(Uint8List(32));
    }

    bb.add(userEd25519Pk ?? Uint8List(32));

    // Fixed record layout (S376): timestamp, founding key and the three
    // invitation fields ALWAYS stand. Until then each of these three
    // groups decided via its own format byte pair; that produced five
    // formats for one subject.
    final tsBytes = Uint8List(8);
    ByteData.view(tsBytes.buffer).setUint64(0, createdAtMs ?? 0, Endian.big);
    bb.add(tsBytes);

    // `fp` only if the identity has softly rotated (fp != ep) — otherwise
    // zero bytes. The anchor is then `ep`, and `hasAnchor`/`verifyIntegrity`
    // read exactly this distinction.
    final fp = foundingEd25519Pk;
    final hasFp =
        fp != null && fp.length == 32 && !_sameBytes(fp, userEd25519Pk);
    bb.add(hasFp ? fp : Uint8List(32));

    bb.addByte(inviteClass?.wireByte ?? 0);
    final expBytes = Uint8List(8);
    ByteData.view(expBytes.buffer)
        .setUint64(0, inviteExpiresAtMs ?? 0, Endian.big);
    bb.add(expBytes);
    // §15.5 `ki`: fixed 32 B. Zero bytes mean "no key".
    final ki = inviteKey;
    bb.add(ki != null && ki.length == inviteKeyLength
        ? ki
        : Uint8List(inviteKeyLength));

    bb.addByte(channelTag == 'b' ? 0x62 : channelTag == 'l' ? 0x6C : 0x00);

    final nameBytes = utf8.encode(displayName);
    final nameLen = nameBytes.length.clamp(0, 255);
    bb.addByte(nameLen);
    bb.add(nameBytes.sublist(0, nameLen));

    final addrs = ownAddresses.take(15).toList();
    bb.addByte(addrs.length);
    for (final a in addrs) {
      final from = utf8.encode(a);
      final al = from.length.clamp(0, 255);
      bb.addByte(al);
      bb.add(from.sublist(0, al));
    }

    final peers = seedPeers.take(5).toList();
    bb.addByte(peers.length);
    for (final sp in peers) {
      bb.add(hexToBytes(sp.nodeIdHex));
      final pa = sp.addresses.take(3).toList();
      bb.addByte(pa.length);
      for (final a in pa) {
        final from = utf8.encode(a);
        final al = from.length.clamp(0, 255);
        bb.addByte(al);
        bb.add(from.sublist(0, al));
      }
    }

    final raw = bb.toBytes();
    // There is only ONE pair left. The choice between the two bytes is
    // solely the question of whether zstd makes the record smaller — no
    // longer a statement about the content.
    try {
      final compressed = ZstdCompression.instance.compress(
          Uint8List.fromList(raw), level: 3);
      if (compressed.length < raw.length) {
        final out = BytesBuilder(copy: false);
        out.addByte(qrFormatCompressed);
        out.add(compressed);
        return out.toBytes();
      }
    } catch (_) {}
    final out = BytesBuilder(copy: false);
    out.addByte(qrFormatUncompressed);
    out.add(raw);
    return out.toBytes();
  }

  static bool _sameBytes(Uint8List a, Uint8List? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

}

/// A seed peer with node ID and reachable addresses.
class SeedPeer {
  final String nodeIdHex;
  final List<String> addresses; // ip:port pairs

  const SeedPeer({required this.nodeIdHex, this.addresses = const []});
}

/// An entry record (§11), as far as a ContactSeed needs it.
///
/// ── WHY THIS TYPE EXISTS AND NOT `EntryRecord` (G-11) ─────────
///
/// The SEND side of the entry bridge needs exactly three things from an
/// entry record: who (position), where (addresses), how much longer
/// (expiry). Everything else about it — the three static keys, the
/// signature — belongs in the handshake and has no business in a
/// QR code; it carries only `ip:port` anyway, and the recipient
/// explicitly makes NO record out of it
/// (`addPeersFromContactSeed`: "THEY ARE ADDRESSES, NOT RECORDS").
///
/// The second reason is the layering. `EntryRecord` lies in
/// `core/tagline/`, i.e. in the delivery layer; this file lies below it
/// and is also used by the UI and by the IPC client, which has no
/// node at all. The candidate therefore travels in as a flat record
/// via [ContactSeedDataSource] — the same way that `localIps`,
/// `publicIp` and `readinessState` already go.
class EntrySeedCandidate {
  /// Network position `L_node` of the node, hex (64 characters).
  ///
  /// It lands in the `s=` field at the place where, until the V3
  /// shutdown, a peer's node ID stood. The recipient only notes it as a
  /// trace on the contact (§5.5b) — the addresses are what gets dialled.
  final String nodeIdHex;

  /// Addresses as `ip:port` or `[v6]:port`.
  ///
  /// **ONLY THOSE DIALLABLE FROM OUTSIDE.** The selection happens at the
  /// source (that is where `isExternallyReachable` lies), not here — this
  /// record is the result, not the raw material.
  final List<String> addresses;

  /// Until when the record is valid (ms since epoch, UTC) — [EntryRecord.expiryMs].
  final int expiryMs;

  const EntrySeedCandidate({
    required this.nodeIdHex,
    required this.addresses,
    required this.expiryMs,
  });
}

// ---------------------------------------------------------------------------
// ContactSeedBuilder — central, stable CR generation (§8.1.1)
//
// Peer-selection, address-computation, and caching live here. The UI never
// assembles a ContactSeed itself — it calls [getContactSeedFor].
// ---------------------------------------------------------------------------

/// Inputs the builder needs from the service layer.
abstract class ContactSeedDataSource {
  /// The node's entry stock (§11), filtered to what is useful to a
  /// FOREIGN scanner — the send side of the entry bridge.
  ///
  /// ── WHAT STOOD HERE AND WHY IT IS GONE (gap G-11) ─────────────
  ///
  /// `List<PeerSummary> get peerSummaries` — the V3 peer address list.
  /// It is empty on the V4.1 line, and on purpose, not out of
  /// incompleteness: `CleonaService.peerSummaries` returns `const []`
  /// and justifies that there at length (§7: whoever knows the address
  /// set of a node can link). The builder thus read a list that never
  /// contained anything, and EVERY issued ContactSeed therefore did not
  /// carry `s=` at all.
  ///
  /// MEASURED IN THE FIELD on 10.09.2026: an issued code carried exactly
  /// one address, `a=192.0.2.202:13086`, and no `s=`. Whoever scans it
  /// outside that home network has no way into the network —
  /// keys and a private address are no entry.
  ///
  /// The V4.1 way for this are the entry records, and the
  /// RECEIVE side of this bridge has stood since S356
  /// (`addPeersFromContactSeed` -> `personEntryHints`, §11.3 stage
  /// "human"). This here is its send side.
  List<EntrySeedCandidate> get entrySeedCandidates;

  List<String> get localIps;
  String? get publicIp;
  int? get publicPort;
  int get port;
  String get deviceNodeIdHex;

  /// The readiness state (§22.7) as a string — `searching` /
  /// `connecting` / `ready`.
  ///
  /// It replaces `hasSessionConfirmedPeers` as the input quantity of the
  /// convergence gate. §22.7.2 names exactly this place: "ContactSeed/QR
  /// convergence: `isReady` is `readiness == ready`. There are no address
  /// conditions — neither a peer-reported public IPv4, nor a global IPv6,
  /// nor a confirmed partner count."
  ///
  /// Both implementers (`CleonaService`, `IpcClient`) already fulfil it
  /// via `ICleonaService.readinessState`; it stands here so that this
  /// file does not have to import the service interface.
  String get readinessState;

  /// Where this identity's log file lives. Needed so the withheld-seed
  /// diagnosis below lands in the identity log and not only in the console —
  /// a module constructed without it writes to no log file at all
  /// (scripts/check_clogger_profiledir.dart). Both implementers already carry
  /// it via `ICleonaService.profileDir`.
  String get profileDir;
}

/// Cached network snapshot — the stable half of a ContactSeed.
class _NetworkSnapshot {
  final List<String> ownAddresses;
  final List<SeedPeer> seedPeers;
  final String fingerprint;

  _NetworkSnapshot({
    required this.ownAddresses,
    required this.seedPeers,
    required this.fingerprint,
  });
}

class ContactSeedBuilder {
  final ContactSeedDataSource _source;

  _NetworkSnapshot? _snapshot;
  int? _createdAtMs;
  Uint8List? _rendezvousNonce;

  ContactSeedBuilder(this._source);

  /// Whether a complete ContactSeed may be issued (§22.7.2).
  ///
  /// **What has been dropped here and why.** Until AP-5 an address
  /// condition stood here: a public IPv4 (STUN), OR a global IPv6,
  /// OR any session-confirmed peer. Each of these three quantities says
  /// something about REACHABILITY from outside — and exactly that is not
  /// a condition for one's own deliverability under V4.1:
  /// "Every delivery runs outbound (§22.5.2); a public address of one's
  /// own is not needed for a ContactSeed's deliverability" (§22.7.2).
  /// The paragraph names all three old conditions individually and
  /// strikes them individually.
  ///
  /// What remains is the proof: `ready` means "two independent relays
  /// have confirmed storage" (§22.7.1) — and only then can a contact
  /// request made in response to this seed be placed at all.
  ///
  /// The entry hints in the seed are NOT a criterion: "The seed
  /// carries entry hints (§11, §15); their presence is not a readiness
  /// criterion."
  /// ── THE GATE HANGS ON `connecting`, NOT ON `ready` (S378) ───────
  ///
  /// Owner decision of 09.09.2026, variant (a). Here stood
  /// `== kReadinessReady`, and that closed a ring:
  ///
  /// `ready` requires TWO INDEPENDENT relays, and independence is
  /// measured by `Partition.independentCount` by NETWORK BLOCK (`/24`, `/48`).
  /// Two people in the same Wi-Fi share a `/24` and are thus ONE
  /// relay — measured on 09.09.2026 on two nodes in
  /// `192.168.10.0/24`: "Partner 2 (aus 0, ein 2, unabhaengig 1)".
  /// They never reached `ready`, therefore never saw a QR, therefore
  /// could not make a contact and never get to a second block
  /// — which `ready` requires.
  ///
  /// §11.3 lists the ContactSeed via QR as "always, and it is the
  /// normal way in". Both sentences stood in the same document.
  ///
  /// ONE relay suffices: the seed is an INVITATION, not a delivery.
  /// `searching` still holds it back — with zero relays nothing can be
  /// placed, and a seed that nobody can answer is worse than honest
  /// waiting.
  ///
  /// The price stands in §22.7.2 and is not argued away: a contact
  /// request against such a seed runs via ONE relay instead of two; if
  /// it is lost between issuing and answer, the scanner sees silence
  /// instead of an error.
  bool get isReady => _source.readinessState != kReadinessSearching;

  /// Build a stable ContactSeed for the given identity.
  ///
  /// **The three invitation fields (§15.3/§15.5) explicitly have NO
  /// default.** Whoever omits them gets a seed without class, without
  /// deadline and without `K_inv(i)` — i.e. exactly what every seed of
  /// this line was until today. That is intentional:
  ///
  /// - A default class would be a promise nobody gave.
  ///   §15.3.1 says the class depends on the PATH, and only the issuer
  ///   knows it: "the issuer must **choose the class at creation
  ///   time**". A default value in the builder would overrule him.
  /// - The 90-day default from §15.3.3 belongs where the UI DISPLAYS the
  ///   deadline (`kInviteDefaultValidity`), not here. A deadline set here
  ///   would stand in no dialog.
  /// - A `K_inv(i)` without ledger would be worse than none: two
  ///   invitations would get the same key as soon as the index does not
  ///   come from `InviteLedger`.
  ///
  /// The read side tolerates the absence correctly
  /// (`InviteClass.fromWireChar(null) == null`,
  /// `isInviteExpiredAt` = false without `exp`).
  ///
  /// [inviteKey] is `K_inv(i)` from `InviteLedger.keyFor` — 32 B. Another
  /// length is discarded instead of passed through (see below).
  ///
  /// Returns null if the network isn't ready yet.
  ContactSeed? getContactSeedFor({
    required String nodeIdHex,
    required String displayName,
    required String channelTag,
    Uint8List? userEd25519Pk,
    Uint8List? foundingEd25519Pk,
    /// S388: the issuer's founding ML-DSA-65 — does NOT go into the
    /// seed, only into the self-check below (v4.2 §4.1).
    Uint8List? foundingMlDsaPk,
    Uint8List? deviceX25519Pk,
    Uint8List? deviceMlKemPk,
    InviteClass? inviteClass,
    int? inviteExpiresAtMs,
    Uint8List? inviteKey,
  }) {
    if (!isReady) return null;
    // §15.5: `ki` is 32 B or nothing at all. A key of wrong length would
    // produce a different tag line at the scanner than at the issuer —
    // the request would lie under a tag that nobody listens to. That
    // would be silent non-delivery; §15.3.3 has just abolished it for
    // expiry, it must not come back here through the back door.
    final ki = (inviteKey != null &&
            inviteKey.length == ContactSeed.inviteKeyLength)
        ? inviteKey
        : null;
    if (inviteKey != null && ki == null) {
      CLogger.get('contact-seed', profileDir: _source.profileDir).error(
          'ContactSeed withheld: inviteKey has ${inviteKey.length} bytes, '
          'expected ${ContactSeed.inviteKeyLength} (K_inv(i), v4.1 §15.5). '
          'A short or long invitation key derives a different tag line than '
          'the issuer harvests — the request would be placed where nobody '
          'listens, with no error on either side.');
      return null;
    }
    final snap = _ensureSnapshot();
    final seed = ContactSeed(
      nodeIdHex: nodeIdHex,
      displayName: displayName,
      ownAddresses: snap.ownAddresses,
      seedPeers: snap.seedPeers,
      channelTag: channelTag,
      deviceIdHex: _source.deviceNodeIdHex,
      userEd25519Pk: userEd25519Pk,
      foundingEd25519Pk: foundingEd25519Pk,
      deviceX25519Pk: deviceX25519Pk,
      deviceMlKemPk: deviceMlKemPk,
      createdAtMs: _createdAtMs!,
      rendezvousNonce: _rendezvousNonce,
      inviteClass: inviteClass,
      inviteExpiresAtMs: inviteExpiresAtMs,
      inviteKey: ki,
    );
    // Self-check before handing the seed out. §8.1.1 requires the seed to be
    // self-certifying: SHA-256(kIdentityDomain || anchor || mldsa) must
    // reproduce the (S388: the ML-DSA key comes from the issuer, see
    // `foundingMlDsaPk`; the seed does not carry it)
    // advertised userId. A caller that mixes identities — advertised nodeId
    // from one, anchor keys from another — produces a seed that every scanner
    // rejects, and the rejection happens silently on the far side where nobody
    // is watching. Failing here turns a broken QR into a visible loading state
    // instead of an unusable code. Observed 2026-07-28 on a multi-identity
    // node: the exported URI carried Alice's nodeId with AllyCat's anchor.
    // S368: here stood "`== false` and not `!`: verifyIntegrity() returns
    // bool? — null means 'no anchor in this seed, nothing to check' (a
    // legitimate compact QR), which must not be treated as a failure."
    // Exactly this exception was the defect: it let a seed WITHOUT an
    // anchor out of this builder, and every scanner would then in turn
    // have accepted it as "not checkable = passed". `verifyIntegrity()` is
    // now two-valued, and an anchorless seed is held back here —
    // that is the right way round: a code that nobody can recompute should
    // not come into existence at all.
    if (!seed.verifyIntegrity(mlDsaPk: foundingMlDsaPk)) {
      // Never silently. Withholding the seed is correct, but until 2026-08-30
      // it was also invisible: the QR screen showed a network-flavoured
      // "connecting" message at a frozen 95 %, no log line existed on this
      // path, and the true cause (a GUI and a daemon deriving UserIDs by
      // different formulas after a partial redeploy) was reachable only by
      // recomputing the hashes by hand. The caller renders a distinct state
      // for this; the log is what makes it diagnosable after the fact.
      final anchor = foundingEd25519Pk ?? userEd25519Pk;
      CLogger.get('contact-seed', profileDir: _source.profileDir).error(
          'ContactSeed withheld: anchor does not certify the advertised '
          'UserID. advertised=${nodeIdHex.length >= 16 ? nodeIdHex.substring(0, 16) : nodeIdHex} '
          'anchor=${anchor == null ? "none" : bytesToHex(anchor).substring(0, 16)} '
          'derivation-fp=${HdWallet.identityDerivationFingerprint}. Either the '
          'advertised identity and the anchor keys come from two different '
          'identities, or this build derives UserIDs differently from the one '
          'that minted them.');
      return null;
    }
    return seed;
  }

  /// Force a snapshot rebuild (e.g. after significant network change).
  void invalidate() {
    _snapshot = null;
    _createdAtMs = null;
    _rendezvousNonce = null;
  }

  _NetworkSnapshot _ensureSnapshot() {
    // §4.11.10: the rendezvous nonce is created once per snapshot lifetime
    // (`??=` like _createdAtMs — it survives fingerprint refreshes until
    // invalidate()). It must NOT change per toUri() call, otherwise the
    // owner-side rendezvous session and the handed-out URI diverge.
    _rendezvousNonce ??= _generateRendezvousNonce();
    // ── FIRST CHOOSE, THEN THE FINGERPRINT OVER THE RESULT ───────
    //
    // Until S380 only `_computeFingerprint()` stood here, and it read
    // exclusively STABLE quantities (port, own IPs). With the entry stock
    // a very unsteady one would be added: during the cold-start cascade
    // new records keep arriving, and `_seed()` runs on every `build()` AND
    // once per second from the poll timer of `contact_share_card.dart`.
    // A fingerprint over the whole stock would make the displayed QR code
    // redraw every second — while someone is scanning it.
    //
    // The fingerprint therefore hangs on the CHOSEN five, not on the
    // stock they come from: a hundred newly arrived records that do not
    // make it into the selection do not change the code.
    final startPeers = _chooseStartPeers(
      _source.entrySeedCandidates,
      DateTime.now().millisecondsSinceEpoch,
    );
    final fp = _computeFingerprint(startPeers);
    if (_snapshot != null && _snapshot!.fingerprint == fp) return _snapshot!;
    _snapshot = _buildSnapshot(fp, startPeers);
    _createdAtMs ??= DateTime.now().millisecondsSinceEpoch;
    return _snapshot!;
  }

  static Uint8List _generateRendezvousNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(32, (_) => rng.nextInt(256)));
  }

  String _computeFingerprint(List<SeedPeer> startPeers) {
    final sb = StringBuffer();
    sb.write(_source.port);
    sb.write('|');
    for (final ip in _source.localIps) {
      sb.write(ip);
      sb.write(',');
    }
    sb.write('|');
    sb.write(_source.publicIp ?? '');
    sb.write(':');
    sb.write(_source.publicPort ?? 0);
    sb.write('|');
    // The CHOSEN start peers, in selection order. It is deterministic
    // (see [_chooseStartPeers], step 3), so it may go in here — unlike
    // the order of the stock, which is deliberately random within an
    // issuing hour.
    for (final p in startPeers) {
      sb.write(p.nodeIdHex);
      sb.write('@');
      sb.write(p.addresses.join('+'));
      sb.write(',');
    }
    return sb.toString();
  }

  _NetworkSnapshot _buildSnapshot(String fp, List<SeedPeer> seedPeers) {
    // --- Own addresses ---
    final ownAddrs = <String>[];
    // Up to 2 private IPv4
    final ipv4 = _source.localIps.where((ip) => !ip.contains(':')).take(2);
    for (final ip in ipv4) {
      ownAddrs.add(_formatAddr(ip, _source.port));
    }
    // Public IPv4
    if (_source.publicIp != null && _source.publicPort != null) {
      ownAddrs.add(_formatAddr(_source.publicIp!, _source.publicPort!));
    }
    // First global IPv6 (DS-Lite bypass)
    final gv6 = _source.localIps.firstWhere(
      (ip) => ip.contains(':') && !ip.startsWith('fe80:') &&
              !ip.startsWith('fd') && !ip.startsWith('fc'),
      orElse: () => '',
    );
    if (gv6.isNotEmpty) ownAddrs.add(_formatAddr(gv6, _source.port));

    return _NetworkSnapshot(
      ownAddresses: ownAddrs,
      seedPeers: seedPeers,
      fingerprint: fp,
    );
  }

  // --- Helpers (shared, no longer duplicated in UI) ---

  /// How many start peers a ContactSeed carries at most.
  ///
  /// FIVE, and that is a FORMAT limit, not a preference: [ContactSeed.toUri]
  /// and [ContactSeed.toQrBytes] both cut off at `take(5)`. Whatever were
  /// chosen here beyond that would silently fall away on writing — namely
  /// the one chosen LAST, i.e. precisely the one that was meant to
  /// establish family diversity.
  static const int kMaxSeedPeers = 5;

  /// How many addresses ONE start peer carries.
  ///
  /// THREE is the limit of the binary form ([ContactSeed.toQrBytes]:
  /// `p.addresses.take(3)`); the URI form takes only TWO ([ContactSeed.toUri]:
  /// `p.addresses.take(2)`). The smaller of the two is the yardstick for the
  /// ORDER — that is why [_familiesChange] ensures that already the
  /// first two addresses cover two families, if the record has
  /// two.
  ///
  /// ── WHAT THESE TWO NUMBERS COST THE QR CODE, MEASURED ────────────
  ///
  /// Measured on 10.09.2026 on [ContactSeed.toQrBytes] (zstd, then
  /// QR byte mode, error correction L — that is how
  /// `contact_share_card.dart` renders it). One start peer = 32 B position
  /// plus the addresses, and positions do not compress:
  ///
  /// ```
  ///   start peers x addresses   bytes     QR
  ///   0 (state before S380)      119     version  6 = 41 modules
  ///   1 x 1                      171     version  8 = 49 modules
  ///   3 x 2                      292     version 11 = 61 modules
  ///   5 x 2                      384     version 13 = 69 modules
  ///   5 x 3                      438     version 14 = 73 modules
  /// ```
  ///
  /// The full set thus costs about 78 % more modules than a code without
  /// start peers. That is paid deliberately: a code without `s=` is no
  /// entry at all for anyone who does not stand in the same segment anyway
  /// — measured in the field on 10.09.2026, see [ContactSeedDataSource.
  /// entrySeedCandidates]. Becoming denser is the cheaper price than
  /// not carrying at all.
  ///
  /// **WHOEVER WANTS TO LOWER THE PRICE has two levers and the table:**
  /// `5 x 2` saves four modules and makes URI and QR form congruent,
  /// `3 x 2` saves twelve. Both are a decision about entry chance versus
  /// scannability and belong to the owner, not to this builder.
  static const int kMaxSeedPeerAddresses = 3;

  /// Does this `host:port` specification carry an IPv6?
  ///
  /// Recognised by the bracket and not by the colon: `192.168.1.5:41338`
  /// has one too. The bracket form is the one that [_formatAddr] and
  /// `EntryAddress.toString()` produce — both producers of this string.
  static bool _isV6Address(String addrPort) => addrPort.startsWith('[');

  /// Order the addresses of a record so that the families alternate
  /// — v4 first.
  ///
  /// ── WHY ALTERNATING (guard rail 4, §17.3/§25) ─────────────────────
  ///
  /// A start peer named only under IPv6 is of no use to a v4-only
  /// scanner, and vice versa. The record knows both families
  /// (`EntryRecord.addresses` carries them explicitly for that reason —
  /// "whoever is reachable on both families is simply better
  /// reachable"), but the QR code carries only two to three addresses per
  /// peer. If they were cut off in record order, a node with three IPv6
  /// and one IPv4 would lose exactly the IPv4 in the URI form.
  ///
  /// v4 FIRST, and that is the only point where a preference is hidden
  /// here: among scanners, v4-only is more frequent than v6-only.
  /// Both families are represented after two positions, provided the
  /// record has both; that is what matters.
  static List<String> _familiesChange(List<String> addresses) {
    final v4 = <String>[];
    final v6 = <String>[];
    for (final a in addresses) {
      (_isV6Address(a) ? v6 : v4).add(a);
    }
    final out = <String>[];
    for (var i = 0; i < v4.length || i < v6.length; i++) {
      if (i < v4.length) out.add(v4[i]);
      if (i < v6.length) out.add(v6[i]);
    }
    return out;
  }

  /// Latest validity first; on a tie, the position.
  ///
  /// The tie is the point: within an issuing hour the source deliberately
  /// delivers in random order (RL-1), and without this second criterion
  /// the selection would be equally random for equal expiry — the QR code
  /// would change while being looked at.
  static int _afterFresh(EntrySeedCandidate a, EntrySeedCandidate b) =>
      a.expiryMs != b.expiryMs
          ? b.expiryMs.compareTo(a.expiryMs)
          : a.nodeIdHex.compareTo(b.nodeIdHex);

  /// The start peers of a ContactSeed from the entry stock (§11) —
  /// the SEND side of the entry bridge, gap G-11.
  ///
  /// ── THE SELECTION RULE, FOUR STEPS ───────────────────────────────────
  ///
  ///   1. **Usable.** A candidate without an address diallable from outside
  ///      is none. The selection itself lies at the source
  ///      (`isExternallyReachable`, `core/tagline/local_addresses.dart`);
  ///      here only what arrives empty or carries no valid 64-digit
  ///      position is dropped — both would be an error of the source,
  ///      and an `s=` field with half a position could not even be parsed
  ///      by the recipient (`toBytes` writes 32 fixed bytes).
  ///   2. **Fresh.** An expired start peer is WORSE than none:
  ///      it costs the scanner a dial attempt, and the scanner books it
  ///      against the record, not against the address
  ///      (`EntryCache.noteUnreachable`). Checked against [nowMs] and
  ///      not against `DateTime.now()`, so that a guard can drive
  ///      across the limit.
  ///   3. **Latest validity first.** The validity window is fixed
  ///      (`EntryRecord.issue`, `validFor`), so a later expiry is
  ///      equivalent to a later ISSUING — and whoever reported last is
  ///      most likely still running. On a tie the position decides, so
  ///      that the selection is DETERMINISTIC: within an issuing hour the
  ///      source deliberately delivers in random order (RL-1), and a QR
  ///      code that changes while being looked at is none.
  ///   4. **Both families, if they exist.** Before filling up by
  ///      step 3, each address family gets its best-placed carrier.
  ///      Without this anticipation a stock of five fresh v6-only nodes
  ///      and one older v4 node could yield a seed that a v4-only scanner
  ///      can do nothing with — exactly the case that §17.3 names for
  ///      calls and §25 for the family share.
  ///
  /// ── WHAT DOES NOT HAPPEN HERE ─────────────────────────────────────────
  ///
  /// No dialling, no query, no network traffic. This function reads a
  /// stock the node holds anyway and chooses from it. It also changes
  /// nothing about `a=` — WHEN an observed public IPv4 is announced is an
  /// open decision of the owner and lies in `port_map_wiring.dart`, not
  /// here.
  static List<SeedPeer> _chooseStartPeers(
    List<EntrySeedCandidate> pool,
    int nowMs,
  ) {
    // Step 1 + 2
    final usable = <EntrySeedCandidate>[
      for (final k in pool)
        if (k.addresses.isNotEmpty &&
            k.nodeIdHex.length == 64 &&
            k.expiryMs > nowMs)
          k,
    ];
    // Step 3
    usable.sort(_afterFresh);

    // Step 4: first the best per family, then fill up.
    //
    // The anticipation occupies at most TWO of the five slots — there are
    // exactly two address families, and each round takes at most one
    // carrier. That is why NO subsequent cut-off stands here: it would be
    // unreachable code with a reasoning that does not hold.
    final chosen = <EntrySeedCandidate>[];
    final seen = <String>{};
    for (final v6 in const [false, true]) {
      for (final k in usable) {
        if (seen.contains(k.nodeIdHex)) continue;
        if (!k.addresses.any((a) => _isV6Address(a) == v6)) continue;
        seen.add(k.nodeIdHex);
        chosen.add(k);
        break;
      }
    }
    for (final k in usable) {
      if (chosen.length >= kMaxSeedPeers) break;
      if (!seen.add(k.nodeIdHex)) continue;
      chosen.add(k);
    }
    // Output is in the order from step 3 — the anticipation determines
    // WHO is included, not who stands in front.
    chosen.sort(_afterFresh);

    return <SeedPeer>[
      for (final k in chosen)
        SeedPeer(
          nodeIdHex: k.nodeIdHex,
          addresses: _familiesChange(k.addresses)
              .take(kMaxSeedPeerAddresses)
              .toList(growable: false),
        ),
    ];
  }

  static String _formatAddr(String ip, int port) =>
      ip.contains(':') ? '[$ip]:$port' : '$ip:$port';
}
