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
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// §7.1.4 / §4.3: the signing material a **Linked Device** uses for its own
/// device-bound DHT records (LivenessRecord, DeviceKemRecord).
///
/// A Linked Device does NOT hold the User-Sig-SK after an emergency rotation
/// (§7.1.1 — the new User-SK is created from fresh entropy on the Primary and
/// is carried by neither `DevicePairApproveV3` nor the LD-8 rotation message).
/// Signing device records with the stale User-SK while advertising the new
/// User-PK makes every receiver drop both records; the device becomes
/// unreachable. Instead the device signs with its **delegated** Ed25519-SK and
/// names [ed25519Pk] in the record, so the receiver can walk
/// `User-Anchor → cert → delegated PK → record`.
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
  ///       signature schemes" (§7.1.1). A cert is what turns an arbitrary key
  ///       into a key that speaks for the user; a classical-only check would
  ///       hand a quantum adversary the whole identity.
  ///       P6 note: the cert now comes out of an AuthManifest that was itself
  ///       hybrid-verified at store time, and `AuthManifest._bytesToSign()`
  ///       covers `deviceDelegations` — so (a) is *currently* redundant. It
  ///       stays because nothing enforces that coupling: this helper is a
  ///       standalone entry point, and the day the manifest's signing scope
  ///       changes, (a) is the only thing between a manifest and a forged
  ///       delegation. `IdentityDhtHandler.getDelegatedKeys` re-verifies certs
  ///       out of stored manifests for exactly the same reason. Cost is one
  ///       ML-DSA verify on the delegated path only.
  ///   (b) the PK the cert delegates equals the PK the record claims to be
  ///       signed by — otherwise a valid cert would launder a signature made
  ///       by an unrelated key.
  ///   (c) the cert is not expired — the dead-man switch (§7.1, LD-1) is the
  ///       only bound on a leaked delegated SK.
  ///   (d) the cert names exactly the device whose record this is — without
  ///       it, ONE compromised Linked Device could publish addresses and KEM
  ///       keys for EVERY other device of the same user and silently become
  ///       the inbound path for all of them. P6: `delegationFor(deviceId)`
  ///       already selects by device id, so (d) is structurally satisfied on
  ///       the two production call sites. Kept as an assertion for direct
  ///       callers of this helper — it is the cheapest of the five checks and
  ///       the most expensive one to be missing.
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
    // an Ed25519-only cert check would be exactly the shortcut §7.1.1 forbids.
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

