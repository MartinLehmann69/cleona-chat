import 'dart:typed_data';
import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/crypto/constant_time.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// HD-Wallet style key derivation from a master seed.
///
/// All keys (Ed25519, X25519, ML-DSA-65, ML-KEM-768) are deterministically
/// derived via HKDF from the master seed. Same seed + index always yields
/// identical keys — critical for seed-phrase recovery.
class HdWallet {
  /// Derive Ed25519 keypair from master seed + identity index.
  /// Deterministic: same seed + index always gives same keys.
  static ({Uint8List publicKey, Uint8List secretKey}) deriveEd25519(
    Uint8List masterSeed,
    int index,
  ) {
    final sodium = SodiumFFI();

    // Derive 32-byte Ed25519 seed via HKDF
    final ed25519Seed = sodium.hkdfSha256(
      masterSeed,
      info: Uint8List.fromList('cleona-ed25519-$index'.codeUnits),
      length: 32,
    );

    // Generate Ed25519 keypair from seed
    return sodium.generateEd25519KeyPairFromSeed(ed25519Seed);
  }

  /// Derive X25519 keypair from Ed25519 keys.
  static ({Uint8List publicKey, Uint8List secretKey}) deriveX25519(
    Uint8List ed25519Pk,
    Uint8List ed25519Sk,
  ) {
    final sodium = SodiumFFI();
    return (
      publicKey: sodium.ed25519PkToX25519(ed25519Pk),
      secretKey: sodium.ed25519SkToX25519(ed25519Sk),
    );
  }

  /// Derive deterministic ML-DSA-65 keypair from master seed + identity index.
  static ({Uint8List publicKey, Uint8List secretKey}) deriveMlDsa(
    Uint8List masterSeed,
    int index,
  ) {
    final sodium = SodiumFFI();
    final seed = sodium.hkdfSha256(
      masterSeed,
      info: Uint8List.fromList('cleona-mldsa-$index'.codeUnits),
      length: 64,
    );
    return OqsFFI().mlDsaKeypairDerand(seed);
  }

  /// Derive deterministic ML-KEM-768 keypair from master seed + identity index.
  static ({Uint8List publicKey, Uint8List secretKey}) deriveMlKem(
    Uint8List masterSeed,
    int index,
  ) {
    final sodium = SodiumFFI();
    final seed = sodium.hkdfSha256(
      masterSeed,
      info: Uint8List.fromList('cleona-mlkem-$index'.codeUnits),
      length: 64,
    );
    return OqsFFI().mlKemKeypairDerand(seed);
  }

  /// The preimage builder of the DEVICE derivation (v4.2 §4.1):
  ///
  ///   deviceId = SHA-256(kIdentityDomain ‖ ed25519_device_pubkey)
  ///
  /// Until S388 it also built the userId. Since the owner decision
  /// „identifier = A" (15.09.2026) the userId carries the ML-DSA-65 key as well
  /// and has its own builder in [computeUserId]; the device derivation is
  /// unchanged.
  ///
  /// [suppliedDomain] exists only so the call sites that still pass the old
  /// second argument keep compiling. It is **never hashed** — the domain that
  /// is hashed is always [kIdentityDomainBytes]. Passing anything else is a
  /// programming error and throws: that is the fail-closed behaviour §4.1
  /// demands ("identity derivations compute exclusively against this domain
  /// constant"). Silently ignoring the argument instead would let a caller
  /// believe it had chosen a domain while the value came from somewhere else.
  static Uint8List _deriveIdentityId(
    Uint8List ed25519Pk,
    Uint8List? suppliedDomain,
    String site,
  ) {
    final domain = kIdentityDomainBytes;
    if (suppliedDomain != null && !constantTimeEquals(suppliedDomain, domain)) {
      throw StateError(
        'HdWallet.$site: identity derivation was handed a domain that is not '
        'kIdentityDomain ($kIdentityDomain). Identity derives EXCLUSIVELY '
        'from the public, channel-specific domain constant (architecture '
        'v4.1 §4.1) — never from NetworkSecret, which is maintainer-key '
        'material and would bind network access to that key. Drop the second '
        'argument.',
      );
    }
    final sodium = SodiumFFI();
    final combined = Uint8List(domain.length + ed25519Pk.length);
    combined.setRange(0, domain.length, domain);
    combined.setRange(domain.length, combined.length, ed25519Pk);
    return sodium.sha256(combined);
  }

  /// Compute the User-ID (architecture v4.2 §4.1, normative).
  ///
  ///   userId = SHA-256(kIdentityDomain ‖ ed25519_user_pubkey ‖ mldsa65_user_pubkey)
  ///
  /// ONE identifier (owner decision „identifier = A", 15.09.2026): this value
  /// IS mycelium's `Address.identifier` and the fingerprint of the invitation card
  /// (§15.2 „the identifier of §4.1"). §4.1: „The KEM keys are not part of
  /// the identifier: they rotate every 7 days, the identifier does not."
  ///
  /// [kIdentityDomain] is a **public**, channel-specific domain-separation
  /// constant (beta ≠ live), not a secret. Until V4.1 this hashed
  /// `NetworkSecret.identitySecret` — a value derived from the maintainer's
  /// Ed25519 private key — which bound network identity to a maintainer key.
  /// §4.1 forbids that: "Network access is not bound to any maintainer key.
  /// The maintainer key carries exclusively update signatures."
  ///
  /// This is the **founding** derivation, computed once over the founding
  /// pubkey. It is the stable anchor: it does not follow key rotation
  /// (continuity is carried by the dual-signed old→new proof, §4.5.4/§14.5)
  /// and it is never persisted — it is recomputed on every identity load, so
  /// a change to the domain constant is immediately and loudly visible
  /// instead of silently drifting against a stored copy.
  ///
  /// FAIL-CLOSED BY LENGTH. Both keys must have their exact length (32 B and
  /// [OqsFFI.mlDsaPublicKeyLength]); anything else throws [ArgumentError].
  /// This replaces the former second-argument guard: the old call shape
  /// `computeUserId(pk, kIdentityDomainBytes)` still type-checks, and without
  /// the length check it would silently hash the domain where the ML-DSA key
  /// belongs.
  static Uint8List computeUserId(Uint8List ed25519Pk, Uint8List mlDsa65Pk) {
    if (ed25519Pk.length != 32) {
      throw ArgumentError.value(ed25519Pk.length, 'ed25519Pk',
          'HdWallet.computeUserId: the Ed25519 key must be 32 B (v4.2 §4.1)');
    }
    if (mlDsa65Pk.length != OqsFFI.mlDsaPublicKeyLength) {
      throw ArgumentError.value(
          mlDsa65Pk.length,
          'mlDsa65Pk',
          'HdWallet.computeUserId: the ML-DSA-65 key must be '
              '${OqsFFI.mlDsaPublicKeyLength} B (v4.2 §4.1)');
    }
    final domain = kIdentityDomainBytes;
    final pre = Uint8List(domain.length + 32 + mlDsa65Pk.length);
    pre.setRange(0, domain.length, domain);
    pre.setRange(domain.length, domain.length + 32, ed25519Pk);
    pre.setRange(domain.length + 32, pre.length, mlDsa65Pk);
    return SodiumFFI().sha256(pre);
  }

  /// Fingerprint of the identity derivation **this build compiles in**.
  ///
  /// `computeUserId(testvector_ed, testvector_mldsa)` — the Ed25519 vector is
  /// the bytes 0..31, the ML-DSA vector `i & 0xff` over 1952 B —, first 8
  /// bytes as hex. It is a
  /// derivation of a fixed, public test vector — not of any real key — so it
  /// carries no identity and no secret. Two builds produce the same value if
  /// and only if they mint the same UserID for the same pubkey.
  ///
  /// Why this exists (measured 2026-08-30 on cleona1/cleona2). Commit
  /// `838ef07e` moved identity derivation off the maintainer-key secret onto
  /// the public domain constant (§4.1). The daemon was rebuilt, the GUI bundle
  /// was five days older, and the two halves of the same app then minted
  /// different UserIDs from the same key. The only symptom the user could see
  /// was the QR screen resting at 95 % forever: `ContactSeed.verifyIntegrity()`
  /// recomputed the advertised UserID with the old formula, got a different
  /// value, and `ContactSeedBuilder.getContactSeedFor` returned null — with no
  /// log line anywhere. A skew in the one formula that defines who everybody
  /// *is* must not be diagnosable only by hand-recomputing hashes, so both
  /// halves publish this value and compare it (`IpcClient`, `getStateSnapshot`).
  ///
  /// It deliberately compares behaviour, not a version string: a hand-kept
  /// constant can be forgotten exactly when the formula changes, which is the
  /// failure this is meant to catch.
  static String get identityDerivationFingerprint {
    final probe = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final probeDsa = Uint8List.fromList(
        List<int>.generate(OqsFFI.mlDsaPublicKeyLength, (i) => i & 0xff));
    final id = computeUserId(probe, probeDsa);
    final sb = StringBuffer();
    for (var i = 0; i < 8; i++) {
      sb.write(id[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// V3 Node-ID: `SHA-256(network_secret ‖ pubkey)`.
  ///
  /// **Not an identity anchor in V4.** V4 has no Node-ID as identity anchor
  /// (§4.1); this survives only for the V3 closed-network smoke corpus
  /// (`smoke_network_secret`, `smoke_key_rotation`, `smoke_recovery`), which
  /// measures the secret-binding property itself. It hashes exactly what it
  /// is given and is deliberately NOT routed through [_deriveIdentityId].
  /// No file under `lib/` may call it — enforced by
  /// `test/smoke/smoke_identity_secret_pin.dart`.
  static Uint8List computeNodeId(Uint8List ed25519Pk, Uint8List networkSecret) {
    final sodium = SodiumFFI();
    final combined = Uint8List(networkSecret.length + ed25519Pk.length);
    combined.setRange(0, networkSecret.length, networkSecret);
    combined.setRange(networkSecret.length, combined.length, ed25519Pk);
    return sodium.sha256(combined);
  }

  /// Compute the Device-Node-ID (architecture v4.1 §4.1, normative).
  ///
  ///   deviceId = SHA-256(kIdentityDomain ‖ ed25519_device_pubkey)
  ///
  /// Same public domain constant as [computeUserId] — see there for why this
  /// no longer hashes `NetworkSecret.identitySecret`.
  ///
  /// **Daemon-global identifier**: derived from the daemon's Device-Sig keypair
  /// (lives in `~/.cleona/device_keys.enc`, see §3.5/§3.7), NOT from any User-
  /// keypair. A daemon hosting N UserIDs has exactly one DeviceID — Multi-
  /// Identity is a User-Layer property and has no Device-Layer consequence
  /// (§3.1).
  ///
  /// Multi-Device (one UserID on N physical devices) yields N distinct
  /// DeviceIDs — one per device, each computed from its own device-keypair.
  ///
  /// The optional second parameter is a compile-compatibility stub for the
  /// call sites not yet migrated; see [_deriveIdentityId]. New code passes one
  /// argument.
  static Uint8List computeDeviceNodeId(Uint8List deviceEd25519Pk,
          [Uint8List? deprecatedNetworkSecret]) =>
      _deriveIdentityId(
          deviceEd25519Pk, deprecatedNetworkSecret, 'computeDeviceNodeId');

  // ── `deriveDbKey` — DROPPED ON 09.09.2026 (S378) ──────────────────
  //
  // It computed `SHA-256(ed25519_user_sk || "cleona-db-key-v1")` according
  // to architecture **§3.8** — the 3.x version. The storage of this line is
  // opened with `deriveFileEncKey(master_seed, hd_index)` (v4_1 §21.4.1,
  // as `PRAGMA hexkey`), and since 04.09.2026 §4.5.3 explicitly listed
  // the function as "historical … **not** the key of the
  // message store".
  //
  // Callers in `lib/` at the time of the removal: **zero**. Two tests kept
  // it alive — one of them only checks that it matches the §3.8 spec,
  // i.e. that a dropped formula is still the dropped formula. Both are
  // removed along with it.

  /// Derive the FileEncryption-Key for a specific identity (Architecture §3.7 step 5).
  /// Used for identity_meta.json.enc, identity_resolution_state.json.enc,
  /// keys.json.enc and other per-identity files.
  static Uint8List deriveFileEncKey(Uint8List masterSeed, int index) {
    final sodium = SodiumFFI();
    return sodium.hkdfSha256(
      masterSeed,
      info: Uint8List.fromList('cleona-file-enc-$index'.codeUnits),
      length: 32,
    );
  }

  /// Derive a shared FileEncryption-Key for daemon-wide files (routing_table,
  /// network_secret). Not per-identity — shared across all identities on this
  /// daemon, but still seed-recoverable.
  static Uint8List deriveSharedFileEncKey(Uint8List masterSeed) {
    final sodium = SodiumFFI();
    return sodium.hkdfSha256(
      masterSeed,
      info: Uint8List.fromList('cleona-shared-file-enc-v1'.codeUnits),
      length: 32,
    );
  }

  /// Derive the DHT registry key for multi-identity backup.
  static Uint8List registryId(Uint8List masterSeed) {
    final sodium = SodiumFFI();
    return sodium.sha256(Uint8List.fromList([
      ...'cleona-registry-id'.codeUnits,
      ...masterSeed,
    ]));
  }

  /// Derive the encryption key for the registry.
  static Uint8List registryKey(Uint8List masterSeed) {
    final sodium = SodiumFFI();
    return sodium.sha256(Uint8List.fromList([
      ...'cleona-registry-key'.codeUnits,
      ...masterSeed,
    ]));
  }

  // ── Linked-Device Delegation (§7.1 LD-1) ─────────────────────────────

  /// Derive a per-device delegated Ed25519 sig keypair for a Linked Device.
  /// Deterministic: same (masterSeed, deviceId) always yields the same keys.
  static ({Uint8List publicKey, Uint8List secretKey}) deriveDelegatedEd25519(
    Uint8List masterSeed,
    Uint8List deviceId,
  ) {
    final sodium = SodiumFFI();
    final info = Uint8List.fromList([
      ...'cleona-deleg-ed25519-v1'.codeUnits,
      ...deviceId,
    ]);
    final seed = sodium.hkdfSha256(masterSeed, info: info, length: 32);
    return sodium.generateEd25519KeyPairFromSeed(seed);
  }

  // -- Invitation line (§15.3.1) ---------------------------------------
  //
  // §15.3.1 writes it as two HKDF stages:
  //
  //     invite_root = HKDF(master_line, "invite-root" || identity_index || g_inv)
  //     K_inv(i)    = HKDF(invite_root, "invite"      || i)
  //
  // WHY TWO STAGES AND NOT ONE. The root value is what an additional
  // device receives on enrolment (§15.3.1: "Additional devices
  // receive `invite_root` the same way as the user KEM secret key"), and
  // it is explicitly what does NOT go into the seed ("The
  // ContactSeed carries `K_inv(i)` and `exp` — **never** `invite_root`").
  // If K_inv were derived directly from the master seed, the device would
  // have to receive the seed; that is exactly the transfer §15.3.1 avoids.
  //
  // WHY `g_inv` GOES INTO THE ROOT AND NOT INTO THE INDIVIDUAL KEY.
  // A counter step at the root invalidates ALL open invitations at one
  // stroke — that is the mass revocation from §15.3.1 ("an
  // increment invalidates all open invitations at once, e.g. after a mass
  // URI leak"). If `g_inv` sat in the second stage, the mass revocation
  // would be N individual revocations, and a forgotten one would be a leak.

  /// The prefix of the first stage. Its own domain, collides with no
  /// existing one: the other master-seed-fed derivations of this file
  /// carry `cleona-ed25519-`, `cleona-mldsa-`, `cleona-mlkem-`,
  /// `cleona-file-enc-`, `cleona-shared-file-enc-v1`, `cleona-deleg-*`.
  static const String kInviteRootInfoPrefix = 'cleona-invite-root-v1';

  /// The prefix of the second stage.
  static const String kInviteKeyInfoPrefix = 'cleona-invite-v1';

  /// Eight bytes, big-endian — the UNAMBIGUOUS encoding of the numbers in
  /// the `info` field.
  ///
  /// **Why not as text.** `‖` in §15.3.1 is concatenation, not text
  /// formatting. If the numbers were written one after the other in
  /// decimal, `identity_index=1, g_inv=23` would be indistinguishable from
  /// `identity_index=12, g_inv=3`: both would yield "…-123". Two different
  /// identities would get the same invitation root — a silent total loss
  /// that would only be noticed when two identities of the same device
  /// could open each other's invitations. A fixed width rules that out.
  static Uint8List _be64(int v) {
    final b = Uint8List(8);
    ByteData.view(b.buffer).setUint64(0, v, Endian.big);
    return b;
  }

  /// Stage 1 (§15.3.1): the invitation root of an identity.
  ///
  /// Input, complete: the master seed as IKM; in the `info`
  /// [kInviteRootInfoPrefix] + 8 B `identityIndex` + 8 B `generation`.
  /// No salt — as with every other derivation of this file; the master
  /// seed is already 256 bits uniformly distributed.
  ///
  /// [generation] is `g_inv`. It is a LOCAL counter and does NOT come
  /// from the 24 words (§15.3.3 "Recovery"): with a wrong `g_inv` every
  /// `K_inv(i)` is wrong, every tag wrong, and every printed invitation
  /// would be silently dead. That is why it belongs in the recovery
  /// package — see `InviteLedger.recoveryFields`.
  static Uint8List deriveInviteRoot(
    Uint8List masterSeed,
    int identityIndex,
    int generation,
  ) {
    if (identityIndex < 0) {
      throw ArgumentError.value(identityIndex, 'identityIndex', 'must be >= 0');
    }
    if (generation < 0) {
      throw ArgumentError.value(generation, 'generation', 'must be >= 0');
    }
    final sodium = SodiumFFI();
    final info = BytesBuilder(copy: false)
      ..add(Uint8List.fromList(kInviteRootInfoPrefix.codeUnits))
      ..add(_be64(identityIndex))
      ..add(_be64(generation));
    return sodium.hkdfSha256(masterSeed, info: info.toBytes(), length: 32);
  }

  /// Stage 2 (§15.3.1): the key of ONE invitation, `K_inv(i)`.
  ///
  /// Input, complete: the invitation root as IKM; in the `info`
  /// [kInviteKeyInfoPrefix] + 8 B `index`. The index is monotonic per
  /// identity and generation — §15.3.1: "i monotonic per invitation".
  ///
  /// What does NOT go in here, and why: neither class nor expiry date nor
  /// label. Class and deadline are promises of the issuer and change
  /// (an invitation can be revoked without its key becoming a different
  /// one); if the class went into the key, a subsequent class change
  /// would be a key change and every seed already issued dead. The key
  /// identifies the INVITATION, the promises hang next to it (§15.5:
  /// `cls` is "enforced at the issuer").
  static Uint8List deriveInviteKey(Uint8List inviteRoot, int index) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index', 'must be >= 0');
    }
    final sodium = SodiumFFI();
    final info = BytesBuilder(copy: false)
      ..add(Uint8List.fromList(kInviteKeyInfoPrefix.codeUnits))
      ..add(_be64(index));
    return sodium.hkdfSha256(inviteRoot, info: info.toBytes(), length: 32);
  }

  /// Derive the HKDF seed for deterministic ML-DSA-65 delegation keygen.
  /// The actual keypair generation requires OQS_SIG_keypair_derand (LD-2).
  static Uint8List deriveDelegatedMlDsaSeed(
    Uint8List masterSeed,
    Uint8List deviceId,
  ) {
    final sodium = SodiumFFI();
    final info = Uint8List.fromList([
      ...'cleona-deleg-mldsa-v1'.codeUnits,
      ...deviceId,
    ]);
    return sodium.hkdfSha256(masterSeed, info: info, length: 64);
  }
}
