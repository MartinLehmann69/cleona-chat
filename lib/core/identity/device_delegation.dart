// §7.1 LD-1: Linked-Device Delegation Certificate.
//
// Authorizes a Linked Device to sign ApplicationFrames on behalf of the user
// identity using a per-device delegated Sig-Key. The certificate is embedded
// in the AuthManifest (field 11) and hybrid-signed by the User-Key.
//
// Key derivation (Primary-side, at pairing time):
//   delegated_ed25519_seed = HKDF-SHA256(user_ed25519_sk,
//       "cleona-deleg-ed25519-v1" || device_id, 32)
//   delegated_ml_dsa_seed  = HKDF-SHA256(master_seed,
//       "cleona-deleg-mldsa-v1" || device_id, 64)
//
// The delegated keys are deterministic per device_id — Primary can re-derive
// at any time without storing additional state.

import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;

/// §7.1.4 / §4.3: the signing material a **Linked Device** uses for its own
/// device-bound DHT records (LivenessRecord, DeviceKemRecord).
///
/// A device signs its own device-bound records with its **delegated**
/// Ed25519-SK and names [ed25519Pk] in the record, so the receiver can walk
/// `User-Anchor → cert → delegated PK → record`.
///
/// **The reason given here used to be a different one, and it was wrong.**
/// Until S392 this comment read: "A Linked Device does NOT hold the
/// User-Sig-SK after an emergency rotation (§7.1.1 …)". That is the V3 model
/// (`Cleona_Chat_Architecture_v3_0.md:3233`); v4_2 has no §7.1.1 and §14.4
/// says the opposite — the identity signature keys rotate along and "sit
/// under the shared key on every device". Since S392
/// `IdentityContext.rotateDelegation` implements that, so a linked device
/// DOES hold the current User-Sig-SK.
///
/// The delegated path stays anyway, and not as a leftover: these are
/// **device-bound** records. Signing them under the delegated key is what
/// makes them attributable to one device and revocable with that device's
/// certificate (§14.6.2) — the User-Sig-SK would name only the identity and
/// take the revocability with it.
///
/// P6: the certificate itself is NOT carried by the record — the receiver
/// looks it up in the AuthManifest it already holds for this user
/// (`AuthManifest.delegationFor(deviceId)`). Shipping it cost ~5.3 KB per
/// record and fragmented every 15-minute liveness republish. This class
/// therefore only holds the key material that actually has to leave the
/// device: the delegated keypair.
class DelegatedSigner {
  final Uint8List ed25519Pk;
  final Uint8List ed25519Sk;

  const DelegatedSigner({
    required this.ed25519Pk,
    required this.ed25519Sk,
  });
}

class DeviceDelegation {
  final Uint8List deviceId;
  final Uint8List delegatedEd25519Pk;
  final Uint8List delegatedMlDsaPk;
  final int capabilities;
  final int issuedAtMs;
  final int maxValidUntilMs;
  Uint8List userEd25519Sig;
  Uint8List userMlDsaSig;

  DeviceDelegation({
    required this.deviceId,
    required this.delegatedEd25519Pk,
    required this.delegatedMlDsaPk,
    required this.capabilities,
    required this.issuedAtMs,
    required this.maxValidUntilMs,
    required this.userEd25519Sig,
    required this.userMlDsaSig,
  });

  static const int capSendMessages = 1;
  static const int capManageContacts = 2;
  static const int capManageGroups = 4;
  static const int capManageChannels = 8;
  static const int capAllStandard = 15;

  bool hasCapability(int cap) => (capabilities & cap) == cap;

  bool isExpired() {
    if (maxValidUntilMs == 0) return false;
    return DateTime.now().millisecondsSinceEpoch > maxValidUntilMs;
  }

  Uint8List _bytesToSign() {
    final p = proto.DeviceDelegationCertProto()
      ..deviceId = deviceId
      ..delegatedEd25519Pk = delegatedEd25519Pk
      ..delegatedMlDsaPk = delegatedMlDsaPk
      ..capabilities = capabilities
      ..issuedAtMs = Int64(issuedAtMs)
      ..maxValidUntilMs = Int64(maxValidUntilMs)
      // Sig fields excluded from signing (zeroed in proto3 default)
      ;
    return Uint8List.fromList(p.writeToBuffer());
  }

  static DeviceDelegation sign({
    required Uint8List deviceId,
    required Uint8List delegatedEd25519Pk,
    required Uint8List delegatedMlDsaPk,
    required int capabilities,
    required int maxValidUntilMs,
    required Uint8List userEd25519Sk,
    required Uint8List userMlDsaSk,
  }) {
    final issuedAtMs = DateTime.now().millisecondsSinceEpoch;
    final cert = DeviceDelegation(
      deviceId: deviceId,
      delegatedEd25519Pk: delegatedEd25519Pk,
      delegatedMlDsaPk: delegatedMlDsaPk,
      capabilities: capabilities,
      issuedAtMs: issuedAtMs,
      maxValidUntilMs: maxValidUntilMs,
      userEd25519Sig: Uint8List(0),
      userMlDsaSig: Uint8List(0),
    );
    final data = cert._bytesToSign();
    cert.userEd25519Sig = SodiumFFI().signEd25519(data, userEd25519Sk);
    cert.userMlDsaSig = OqsFFI().mlDsaSign(data, userMlDsaSk);
    return cert;
  }

  bool verify(Uint8List userEd25519Pk, Uint8List userMlDsaPk) {
    final data = _bytesToSign();
    final edOk =
        SodiumFFI().verifyEd25519(data, userEd25519Sig, userEd25519Pk);
    if (!edOk) return false;
    return OqsFFI().mlDsaVerify(data, userMlDsaSig, userMlDsaPk);
  }

  /// §7.1.4 + §4.3: validate the certificate chain that a device-bound record
  /// (LivenessRecord / DeviceKemRecord) presents when it was signed by a
  /// **delegated** device key instead of the User-Sig-Key.
  ///
  /// ── STATE S368 (05.09.2026): WITHOUT CALLER, AND NO LONGER CALLABLE ──
  ///
  /// This method had exactly one caller, `identity/device_kem_record.dart`,
  /// and that is deleted along with the 2D DHT model. It does not silently
  /// fall along with it nevertheless: under V4.1 it cannot be fulfilled at
  /// all any more. Its own contract (below) requires an anchor from a
  /// **verified AuthManifest** — "never from the record itself" —, and an
  /// AuthManifest no longer exists on this line (`cleona_service_identity.dart`
  /// says so literally, gap G-9).
  ///
  /// It stays for now, because its deletion would be a statement about
  /// how a delegated-signed record is anchored in V4.1 — and that question
  /// is open. The LIVING delegation path is a different one and untouched:
  /// `DeviceDelegation.sign` in `device_pairing_service.dart` issues the
  /// certificate, `DeviceDelegation.verify` in `cleona_service.dart` checks
  /// it on receipt. Whoever reads the paragraph further below ("the two
  /// production call sites") should read it as past — both fell with the
  /// CUT or in S368 respectively.
  ///
  /// Returns true only if the chain `User-Anchor → cert → signerEd25519Pk`
  /// holds for exactly [recordDeviceId]. The caller MUST then verify the
  /// record itself against [signerEd25519Pk] — this helper deliberately does
  /// not see the record payload.
  ///
  /// P6: [cert] no longer travels with the record; the caller resolves it via
  /// `AuthManifest.delegationFor(recordDeviceId)`. Null (no manifest, or no
  /// delegation entry for this device) is a **drop**, not a fallback.
  ///
  /// Every condition is load-bearing, none may be shortcut:
  ///   (a) the cert hybrid-verifies (Ed25519 **and** ML-DSA) under the
  ///       anchored User-PKs — "Forging a delegation requires breaking both
  ///       signature schemes". That sentence is **V3 wording**
  ///       (`Cleona_Chat_Architecture_v3_0.md:3309`); it was cited here as
  ///       "§7.1.1" until S392, a number v4_2 does not have. The rule
  ///       itself survives unchanged in 4.2: v4_2 §4.4.3 lists key-rotation
  ///       and delegation artifacts among the ML-DSA **mandatory** cases,
  ///       and §14.4/§14.6.2 put the delegation cert under the identity
  ///       signature keys. A cert is what turns an arbitrary key
  ///       into a key that speaks for the user; a classical-only check would
  ///       hand a quantum adversary the whole identity.
  ///       P6 note: the cert now comes out of an AuthManifest that was itself
  ///       hybrid-verified at store time, and `AuthManifest._bytesToSign()`
  ///       covers `deviceDelegations` — so (a) is *currently* redundant. It
  ///       stays because nothing enforces that coupling: this helper is a
  ///       standalone entry point, and the day the manifest's signing scope
  ///       changes, (a) is the only thing between a manifest and a forged
  ///       delegation. Cost is one ML-DSA verify on the delegated path only.
  ///       **Until S370 (06.09.2026) here additionally stood
  ///       "`IdentityDhtHandler.getDelegatedKeys` re-verifies certs out of
  ///       stored manifests for exactly the same reason" — this class no
  ///       longer exists on this line.** `IdentityDhtHandler` lay in
  ///       `lib/core/identity_resolution/` and was dropped with the V3 cut;
  ///       re-measured, the name has only three occurrences left in `lib/`,
  ///       all in comments. A piece of evidence that points to a deleted
  ///       class carries nothing.
  ///   (b) the PK the cert delegates equals the PK the record claims to be
  ///       signed by — otherwise a valid cert would launder a signature made
  ///       by an unrelated key.
  ///   (c) the cert is not expired — the dead-man switch (§7.1, LD-1) is the
  ///       only bound on a leaked delegated SK.
  ///   (d) the cert names exactly the device whose record this is — without
  ///       it, ONE compromised Linked Device could publish addresses and KEM
  ///       keys for EVERY other device of the same user and silently become
  ///       the inbound path for all of them. P6: `delegationFor(deviceId)`
  ///       already selects by device id, so (d) is structurally satisfied at
  ///       the call site. Kept as an assertion for direct callers of this helper
  ///       — it is the cheapest of the five checks and the most expensive one
  ///       to be missing. **Until S370 here stood "the two production call
  ///       sites"; it is exactly ONE** — `device_kem_record.dart:139`,
  ///       re-measured on 06.09.2026.
  ///
  /// ── STATE ON THIS LINE, measured on 06.09.2026 (S370) ───────────
  ///
  /// Today this function has **no reachable calling context**, and that
  /// is intentional, not a backlog. Its only caller
  /// [DeviceKemRecord.verifyAnchored] (`device_kem_record.dart:137`) in
  /// turn has **zero** callers in `lib/` and `test/`, and a
  /// `DeviceKemRecord` is nowhere received from the network in `lib/`.
  /// Reason: V4.1 has no pollable third-party knowledge — the 2D DHT
  /// identity resolution (v3_0 §4.3) is REPLACED, liveness is pairwise,
  /// and `tagline/liveness.dart` carries an unsigned `LivenessRecord`.
  /// Without a ring there is no record that a third party fetches and
  /// whose delegation chain it would have to check.
  ///
  /// **This is not a gap but a missing consumer.** The productive
  /// delegation check of this line is the certificate self-check
  /// [DeviceDelegation.verify] in the pairing receive path
  /// (`service/cleona_service.dart:14266`, hybrid against the own anchor
  /// PKs). Nothing is signed delegated here anyway:
  /// `IdentityContext.signingEd25519Sk` and siblings have no consumer. So
  /// nothing arrives that would need (a)-(d).
  ///
  /// The condition for the return stands in
  /// `test/smoke/smoke_delegation_rotation.dart`: "Whoever builds §14.6
  /// (enrolment of a device) belongs back here."
  ///
  /// [anchorUserEd25519Pk]/[anchorUserMlDsaPk] must come from a verified
  /// AuthManifest (embedded keys, §4.3 D1) — never from the record itself.
  static bool verifyDelegatedSigner({
    required Uint8List signerEd25519Pk,
    required DeviceDelegation? cert,
    required Uint8List anchorUserEd25519Pk,
    required Uint8List anchorUserMlDsaPk,
    required Uint8List recordDeviceId,
  }) {
    if (cert == null) return false;
    if (signerEd25519Pk.isEmpty) return false;
    // No hybrid anchor → the ML-DSA half of (a) is unverifiable. Fail closed:
    // an Ed25519-only cert check is exactly the shortcut the hybrid rule
    // forbids (v4_2 §4.4.3, ML-DSA mandatory for delegation and rotation
    // artifacts; until S392 cited here as "§7.1.1", which is a V3 number —
    // see the class doc comment).
    if (anchorUserEd25519Pk.isEmpty || anchorUserMlDsaPk.isEmpty) return false;
    if (!_ctEquals(cert.delegatedEd25519Pk, signerEd25519Pk)) return false; // (b)
    if (cert.isExpired()) return false; // (c)
    if (recordDeviceId.isEmpty) return false;
    if (!_ctEquals(cert.deviceId, recordDeviceId)) return false; // (d)
    return cert.verify(anchorUserEd25519Pk, anchorUserMlDsaPk); // (a)
  }

  static bool _ctEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  proto.DeviceDelegationCertProto toProto() {
    return proto.DeviceDelegationCertProto()
      ..deviceId = deviceId
      ..delegatedEd25519Pk = delegatedEd25519Pk
      ..delegatedMlDsaPk = delegatedMlDsaPk
      ..capabilities = capabilities
      ..issuedAtMs = Int64(issuedAtMs)
      ..maxValidUntilMs = Int64(maxValidUntilMs)
      ..userEd25519Sig = userEd25519Sig
      ..userMlDsaSig = userMlDsaSig;
  }

  static DeviceDelegation fromProto(proto.DeviceDelegationCertProto p) {
    return DeviceDelegation(
      deviceId: Uint8List.fromList(p.deviceId),
      delegatedEd25519Pk: Uint8List.fromList(p.delegatedEd25519Pk),
      delegatedMlDsaPk: Uint8List.fromList(p.delegatedMlDsaPk),
      capabilities: p.capabilities,
      issuedAtMs: p.issuedAtMs.toInt(),
      maxValidUntilMs: p.maxValidUntilMs.toInt(),
      userEd25519Sig: Uint8List.fromList(p.userEd25519Sig),
      userMlDsaSig: Uint8List.fromList(p.userMlDsaSig),
    );
  }

  Uint8List toProtoBytes() => toProto().writeToBuffer();

  static DeviceDelegation fromProtoBytes(Uint8List bytes) =>
      fromProto(proto.DeviceDelegationCertProto.fromBuffer(bytes));
}

