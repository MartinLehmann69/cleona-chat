import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/device_keys_store.dart';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/crypto/key_migration.dart';
import 'package:cleona/core/crypto/legacy_key_purge.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/pq_isolate.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/identity/kem_generation.dart';
import 'package:cleona/core/log/log_redaction.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/platform/first_start_wipe.dart';
import 'package:cleona/core/identity/linked_device_keys.dart';
import 'package:cleona/core/storage/message_store.dart';

/// One persisted soft-re-key link old→new (§7.4b / SR-2). Plain data holder
/// in this file. The reason for this stood here until S368 as
/// "auth_manifest.dart imports identity_context, defining the class here
/// avoids the cycle" — that file no longer exists (2D DHT model, fell
/// with the CUT), and with it the wire-level `RotationChainLink` onto
/// which the IdentityPublisher once mapped these links. The class stays
/// exactly here, because it is the PERSISTED state of the rotation chain:
/// it is written and read by [IdentityContext], has nothing to do with a
/// wire form any more, and its content still carries the stable anchor.
/// The OLD key signs `newEd25519Pk || newMlDsaPk` (the §4.3 link shape).
class StoredRotationLink {
  final Uint8List oldEd25519Pk;

  /// The ML-DSA-65 key BEFORE this rotation (S388). Since "identifier = A"
  /// the UserID depends on both signing keys (v4.2 §4.1); without this
  /// field the founding UserID of a rotated identity could no longer be
  /// computed — the first link carries the founding ML-DSA.
  final Uint8List oldMlDsaPk;
  final Uint8List newEd25519Pk;
  final Uint8List newMlDsaPk;
  final Uint8List oldSignatureEd25519;

  /// The ML-DSA-65 signature of the OLD keypair over the same bytes
  /// (S392). v4.2 §4.5.4: "The chain is signed hybrid (§4.4.3, a long-lived
  /// verifiable artifact)." Without this field the founding binding of
  /// every rotated author hangs on Ed25519 alone — whoever breaks Ed25519
  /// builds himself a chain to any foreign UserID and writes in its name.
  /// Empty exactly where [oldSignatureEd25519] is empty as well. Until S392
  /// that was the regular case of every second and later LD-8 rotation
  /// (stale user sig SK); since the co-rotation per v4_2 §14.4 it is the
  /// exceptional case of an incomplete LD-8 message — see
  /// [IdentityContext.rotateDelegation].
  final Uint8List oldSignatureMlDsa;

  StoredRotationLink({
    required this.oldEd25519Pk,
    required this.oldMlDsaPk,
    required this.newEd25519Pk,
    required this.newMlDsaPk,
    required this.oldSignatureEd25519,
    required this.oldSignatureMlDsa,
  });

  /// The bytes over which both signatures run: `newEd25519Pk ‖
  /// newMlDsaPk`. ONE place, so that producer and checker cannot drift
  /// apart.
  static Uint8List linkContentOf(Uint8List newEd25519Pk, Uint8List newMlDsaPk) {
    final out = Uint8List(newEd25519Pk.length + newMlDsaPk.length);
    out.setRange(0, newEd25519Pk.length, newEd25519Pk);
    out.setRange(newEd25519Pk.length, out.length, newMlDsaPk);
    return out;
  }

  Uint8List get linkContent => linkContentOf(newEd25519Pk, newMlDsaPk);

  Map<String, dynamic> toJson() => {
        'old_ed25519_pk': bytesToHex(oldEd25519Pk),
        'old_ml_dsa_pk': bytesToHex(oldMlDsaPk),
        'new_ed25519_pk': bytesToHex(newEd25519Pk),
        'new_ml_dsa_pk': bytesToHex(newMlDsaPk),
        'old_signature_ed25519': bytesToHex(oldSignatureEd25519),
        'old_signature_ml_dsa': bytesToHex(oldSignatureMlDsa),
      };

  /// Reads a stored link. Every field is mandatory.
  ///
  /// K-5 (S388): if a field is missing — e.g. `old_ml_dsa_pk` in a chain from
  /// before `3f9d3b83` —, this throws a [StateError] that names the field,
  /// instead of a null-cast `_TypeError` without a cause. No migration, no
  /// substitute value: such a chain belongs to a profile that does not exist
  /// on the V4.2 line.
  static StoredRotationLink fromJson(Map<String, dynamic> json) {
    Uint8List mandatory(String field) {
      final value = json[field];
      if (value is! String) {
        throw StateError('StoredRotationLink: required field $field '
            '${value == null ? 'is missing' : 'is not text (${value.runtimeType})'}'
            ' — link not readable; no conversion (v4.2 §4.1, S388)');
      }
      return hexToBytes(value);
    }

    return StoredRotationLink(
      oldEd25519Pk: mandatory('old_ed25519_pk'),
      oldMlDsaPk: mandatory('old_ml_dsa_pk'),
      newEd25519Pk: mandatory('new_ed25519_pk'),
      newMlDsaPk: mandatory('new_ml_dsa_pk'),
      oldSignatureEd25519: mandatory('old_signature_ed25519'),
      // Mandatory like the other five (S392). A chain from before this
      // change does not carry the field and is thus not readable — that
      // is intended: it could not be checked hybrid, and on the 4.2 line
      // there is no profile that would have it (CLAUDE.md "Linien").
      oldSignatureMlDsa: mandatory('old_signature_ml_dsa'),
    );
  }
}

/// Holds all cryptographic keys and identity for one user profile.
///
/// **HISTORICAL:** here stood "Multiple IdentityContexts can share a single
/// CleonaNode." `CleonaNode` was deleted with the CUT of 2026-08-31
/// (`lib/core/node/` has zero files, measured 2026-09-03). What is shared
/// today is the ONE V4.1 node of the process — `V41Runtime`, held in
/// `lib/service_daemon.dart` or `lib/main.dart` respectively.
class IdentityContext {
  final String profileDir;
  final String networkChannel;
  final String displayName;
  final CLogger _log;

  // Identity keys (permanent)
  late Uint8List ed25519PublicKey;
  late Uint8List ed25519SecretKey;
  late Uint8List mlDsaPublicKey;
  late Uint8List mlDsaSecretKey;

  // KEM keys (rotatable)
  late Uint8List x25519PublicKey;
  late Uint8List x25519SecretKey;
  late Uint8List mlKemPublicKey;
  late Uint8List mlKemSecretKey;

  // Previous KEM keys — retained for [previousKeyRetention] after rotation so
  // that a cell sealed against the old generation is still openable
  // (§4.5.4; the reader side is `MessageOpener`, see there).
  Uint8List? previousX25519Sk;
  Uint8List? previousMlKemSk;
  DateTime? keyRotatedAt;
  DateTime? keysCreatedAt;

  // §7.1 LD-3: Inner-Sig signing keys.
  // Linked Device → delegated keys; Primary/legacy → User-Keys.
  Uint8List get signingEd25519Sk =>
      linkedDeviceKeys?.delegatedEd25519Sk ?? ed25519SecretKey;
  Uint8List get signingMlDsaSk =>
      linkedDeviceKeys?.delegatedMlDsaSk ?? mlDsaSecretKey;
  Uint8List get signingEd25519Pk =>
      linkedDeviceKeys?.delegatedEd25519Pk ?? ed25519PublicKey;
  Uint8List get signingMlDsaPk =>
      linkedDeviceKeys?.delegatedMlDsaPk ?? mlDsaPublicKey;
  bool get isLinkedDevice => linkedDeviceKeys != null;

  /// SR-2 (§3.1 stable anchor / §7.4b): persisted founding→current rotation
  /// chain. Empty unless the identity has soft-re-keyed. The userId is
  /// derived from [foundingEd25519Pk], NOT from the current key — it never
  /// changes across rotations. The IdentityPublisher embeds this chain in
  /// every Auth-Manifest so resolvers verify via §4.3 path 2.
  final List<StoredRotationLink> rotationChain = [];

  /// The founding Ed25519 pubkey — the key whose hash IS the userId.
  /// Equals the current key for never-rotated identities.
  Uint8List get foundingEd25519Pk => rotationChain.isEmpty
      ? ed25519PublicKey
      : rotationChain.first.oldEd25519Pk;

  /// The founding ML-DSA-65 pubkey — the second key whose hash IS the userId
  /// (v4.2 §4.1, S388). Equals the current key for never-rotated identities.
  Uint8List get foundingMlDsaPk => rotationChain.isEmpty
      ? mlDsaPublicKey
      : rotationChain.first.oldMlDsaPk;

  /// True once this identity has soft-re-keyed at least once.
  bool get hasRotated => rotationChain.isNotEmpty;

  /// The FOUNDING secret key of this identity (§15.2).
  ///
  /// ── WHY THIS GETTER EXISTS (path A of the S361 proposal) ────────────
  ///
  /// §15.2 normative: "`K_AB` has exactly one source: the founding keys of
  /// both sides … Because the founding keys are the identity anchor stable
  /// across rotations (§4.1), `K_AB` survives every key rotation without a
  /// transition window."
  ///
  /// Until now the pair key took [ed25519SecretKey] — the CURRENT one.
  /// After a rotation this side computed under a different tag than the
  /// counterpart, which keeps using the founding pubkey. Delivery failed
  /// silently; after the 14-day cap of the transition window (§14.4)
  /// permanently.
  ///
  /// ── WHERE IT COMES FROM, WITHOUT STORING IT ───────────────────────────
  ///
  /// From the HD wallet: the founding keypair IS the derivation at
  /// [hdIndex] (`_generateKeysAsync`, §3.6 invariant "hdIndex implies
  /// deterministic keys from seed", `identity_manager.dart:554-560`).
  /// [rotateIdentityFull] only overwrites the fields and does not touch
  /// the seed — so the derivation stays valid. That is why NOTHING is
  /// cached here and NOTHING is newly persisted: the value can be
  /// recomputed at any time, and a second stored place would be a second
  /// truth about the same key.
  ///
  /// ── THE PROBE, AND WHY IT IS NOT OMITTED ─────────────────
  ///
  /// The derived PUBKEY must match [foundingEd25519Pk] — the anchor on
  /// which the UserID and the outgoing direction hang. Only then does the
  /// derived secret key demonstrably belong to the anchor against which
  /// the counterpart computes. Without this probe the match would be an
  /// assumption (e.g. an identity created the legacy way and later given
  /// a `hdIndex` would silently deliver a foreign key).
  ///
  /// ── THE LIMIT, NAMED INSTEAD OF HIDDEN ─────────────────────────────
  ///
  /// Without [masterSeed]/[hdIndex] (identities created the legacy way;
  /// linked devices, which per v4_2 §14.6.2 do NOT receive a seed — the
  /// seed is the only piece explicitly excluded there) there is no
  /// back-derivation. These cases stay on [ed25519SecretKey] — which is
  /// EXACTLY today's behaviour, so no deterioration, but no improvement
  /// either.
  ///
  /// **For a linked device this fallback is, since S392, NOT accidentally
  /// the founding key any more — and the warning sentence below is now
  /// true.** Until then [rotateDelegation] left `ed25519SecretKey`
  /// untouched; the device therefore kept holding the original user sig SK
  /// and fell out of its own system channels on exactly that, while this
  /// getter accidentally returned the correct founding key. Since the
  /// co-rotation per §14.4 the device carries the CURRENT user sig SK at
  /// any time; this getter consequently hands it the current one, and the
  /// `hasRotated` branch below logs exactly what happens then ("K_AB
  /// continues under the CURRENT key"). Whoever NEEDS the founding key here
  /// needs the seed — and a linked device does not have it per §14.6.2.
  ///
  /// S392 reported this, it did not decide it: whether a rotated linked
  /// device should keep its K_AB anchor (the chain or the LD-8 message
  /// would then have to carry the founding key) belongs to the owner. It
  /// is latent anyway — LD-8 has no sender today.
  Uint8List get foundingEd25519SecretKey {
    final seed = masterSeed;
    final idx = hdIndex;
    if (seed == null || idx == null) {
      if (hasRotated) {
        _log.warn('§15.2: rotated identity without HD wallet '
            '(masterSeed/hdIndex missing) — the founding secret cannot be '
            'recomputed, K_AB continues for this identity under '
            'the CURRENT key.');
      }
      return ed25519SecretKey;
    }
    final derived = HdWallet.deriveEd25519(seed, idx);
    if (!_bytesEqual(derived.publicKey, foundingEd25519Pk)) {
      _log.warn('§15.2: the HD derivation at index $idx does NOT match the '
          'founding pubkey — anchor and derivation diverge. '
          'K_AB stays on the current key instead of '
          'silently using a foreign one.');
      return ed25519SecretKey;
    }
    return derived.secretKey;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// User-ID: stable identity across all devices =
  /// SHA-256(kIdentityDomain ‖ founding ed25519_pk ‖ founding mldsa65_pk)
  /// (v4.2 §4.1; until S388 the V3 formula with network_secret still stood here).
  /// Used for contact lookup, sender_id in envelopes, S&F storage key.
  late Uint8List userId;

  /// Device-Node-ID: daemon-global routing identifier.
  /// device_id = SHA-256(network_secret + ed25519_device_pubkey)
  /// Derived from the daemon-global Device-Sig keypair (§3.5/§3.7) — all
  /// hosted UserIDs share the same DeviceID. See Architecture §3.1.
  late Uint8List deviceNodeId;

  // ── 2D-DHT IDENTITY RESOLUTION: DROPPED (S366) ──────────────────
  //
  // Here stood four counter fields (`_authManifestSeq`, `_livenessSeq`,
  // `_deviceKemSeq`, `_lastAuthManifestContentHash`), their getters, three
  // `bump*` methods, `setLastAuthManifestContentHash`, `recoverAuthSeq`
  // as well as `persistIdentityResolutionState` / `_loadIdentityResolutionState`
  // together with the file `<profileDir>/identity_resolution.json.enc`.
  //
  // RE-MEASURED ON 04.09.2026 AGAINST THIS BRANCH: not a single one of these
  // members still had a caller in `lib/`. The only one there ever was,
  // was `IdentityPublisher._publishLivenessNow` in
  // `lib/core/identity_resolution/` — and that directory was deleted with
  // the CUT of 31.08.2026 (`_initIdentityPublisher` in
  // `cleona_service_identity.dart` is an empty body today; until S368 the
  // line number 420 stood here — the file has since become shorter,
  // because the unentered V3 infra entrance of the emergency rotation
  // fell. The symbol name does not wander, the line does). The counters
  // were thus read on every start, never incremented and never written
  // again.
  //
  // IT IS NOT A BACKLOG BUT THE REPLACEMENT. v3_0 §4.3 (2D-DHT
  // Identity Resolution) is REPLACED in V4.1 and not renumbered:
  // V4.1 knows no pollable third-party knowledge, liveness is pairwise
  // (v4_1 §6, §8). Whoever brings these counters back rebuilds the
  // rejected layer.
  //
  // The name `identity_resolution.json` remains in
  // `first_start_wipe.dart` — the list clears out existing
  // installations.

  /// Legacy alias: returns userId (backward compat for identity comparisons).
  /// 50+ places in the codebase compare identity.nodeId with contact IDs,
  /// group member IDs, etc. — all of these are identity operations, not routing.
  Uint8List get nodeId => userId;

  /// Base directory for shared daemon-global resources (device keys, db.key).
  /// Always resolves to ~/.cleona regardless of profileDir.
  final String _baseDir;
  String get baseDir => _baseDir;

  /// The daemon-global device key bundle (Device-Sig + Device-KEM),
  /// set by [initKeys].
  ///
  /// ── WHY IT LIES HERE AND NOT IN THE SERVICE ─────────────────────────
  ///
  /// `cleona_service.dart` (gap G-9) justified the empty field by saying
  /// that "every service with its own `identity.baseDir` would get a
  /// DIFFERENT device keypair" and §3.1 C-1 (all hosted identities share
  /// ONE deviceNodeId) would thereby break. The concern is justified and
  /// the solution is precisely therefore HERE: [initKeys] already loads the
  /// bundle anyway — from [_baseDir], which according to its own
  /// documentation "always resolves to ~/.cleona regardless of profileDir".
  /// It is THE SAME bundle from which [deviceNodeId] derives; C-1 holds
  /// today exactly for that reason. It was just thrown away after this one
  /// derivation.
  ///
  /// So nothing is loaded a second time and no second source is opened —
  /// the existing one is no longer discarded. A service that called
  /// `DeviceKeysStore.loadOrCreate` itself would be the second source that
  /// comment warns against; that stays forbidden.
  ///
  /// Null until [initKeys] has run. Carrier for §7.5/§14.5: without the
  /// private Device-Sig key no approval token comes into existence, and
  /// without a token there is no quorum.
  DeviceKeyBundle? _deviceKeys;
  DeviceKeyBundle? get deviceKeys => _deviceKeys;

  /// HD-Wallet derivation index (null = legacy random keys).
  final int? hdIndex;

  /// Master seed for HD-Wallet derivation (null = legacy).
  final Uint8List? masterSeed;

  // §7.1 LD-3: delegation keys for Linked Devices (null = Primary or legacy).
  LinkedDeviceKeys? linkedDeviceKeys;

  /// When this identity was created (from IdentityManager).
  final DateTime createdAt;

  /// Self-declaration: user claims to be 18+ (from IdentityManager).
  bool isAdult;

  /// §7.1.3 (P2): true iff this identity was restored from the seed phrase
  /// AND the user told the restore screen they still have another device
  /// running with this identity ("additional device"). Read by
  /// `IdentityPublisher._isPrimaryDevice` to withhold the AuthManifest
  /// publish until pairing completes — see `Identity.restoreAwaitingPairing`
  /// (identity_manager.dart) for the full rationale, this is its runtime
  /// mirror. Mutable (not `final`) for the same reason `linkedDeviceKeys` is:
  /// pairing can complete while this IdentityContext instance is already
  /// running, and the publisher must see the change on its next cycle
  /// without a restart.
  bool restoreAwaitingPairing;

  /// §13 (S382): runtime mirror of `Identity.restoredFromPhrase`
  /// (identity_manager.dart) — the complete reasoning stands there.
  /// Together with [restoreAwaitingPairing] it represents the recovery
  /// case: created from the phrase AND no other device under the same
  /// phrase.
  ///
  /// Not `final`, for the same reason as [restoreAwaitingPairing]:
  /// the marker is deleted as soon as the search has fulfilled its
  /// purpose, and the running service must see that without a restart.
  bool restoredFromPhrase;

  IdentityContext({
    required this.profileDir,
    required this.displayName,
    this.networkChannel = 'beta',
    String? baseDir,
    this.hdIndex,
    this.masterSeed,
    DateTime? createdAt,
    this.isAdult = false,
    this.restoreAwaitingPairing = false,
    this.restoredFromPhrase = false,
  })  : _baseDir = baseDir ?? _resolveBaseDir(),
        createdAt = createdAt ?? DateTime.now(),
        _log = CLogger.get('identity', profileDir: profileDir) {
    // `displayName` is `final` here — a registration in the constructor is
    // therefore complete. It stands BEFORE every log line of this context,
    // in particular before `_log.debug('Identity displayName=...')`
    // further below.
    LogRedaction.registerName(displayName);
  }

  /// Daemon-global default base dir (§3.1). Deliberately takes no
  /// `profileDir`: the base dir is per-DEVICE, never per-profile. Callers
  /// that need isolation (tests, multi-device scenarios) MUST pass an
  /// explicit `baseDir` — setting only `profileDir` does not isolate
  /// device keys, db.key or device_kem_public.json.
  static String _resolveBaseDir() => '${AppPaths.home}/.cleona';

  // ── Shared startup sequence (S106 fix) ──────────────────────────────
  // Single source of truth for crypto init + IdentityContext creation.
  // All entry points (service_daemon, main.dart) use these
  // instead of duplicating the init sequence.

  /// §3.7: Initialize crypto subsystem — keyring + migration.
  /// Call once at daemon/app startup before any key access.
  /// On Android/iOS: call MobileKeyringService.init() BEFORE this.
  static Future<void> initCrypto(String baseDir) async {
    // ── THE DELETION PATH AT FIRST START (§21.4, AP-8) ───────────────────
    //
    // Owner decision of 03.09.2026, option A of the S363 proposal: a
    // first start without the V4.1 marker deletes the profile content
    // completely and creates an empty one. Reasoning, markers and deletion
    // set: `lib/core/platform/first_start_wipe.dart`.
    //
    // **MUST BE THE FIRST LINE.** Not only "before
    // `migrateDeviceScopedFiles`" (otherwise the migration first re-keys
    // what falls right afterwards), but before EVERY step of this
    // sequence: `KeyringService.init` builds a `CLogger` on `baseDir`,
    // and every construction of `FileEncryption(baseDir:)` without a key
    // creates `db.key` ANEW (`file_encryption.dart:66-68`).
    // `db.key` stands in `FirstStartWipe.baseEvidenceFiles`; whoever writes
    // before the deletion path produces, on a real fresh start, the very
    // evidence by which it recognises legacy holdings.
    final wipeReport = FirstStartWipe.runFirstStartWipe(baseDir);

    final keyring = await KeyringService.init(baseDir);

    // ── THE SECOND HALF OF THE SAME WIPE (RB-4, S370) ───────────────
    //
    // The line above clears the disk. On four of five platforms the
    // keyring does NOT lie on the disk (GNOME keyring via `secret-tool`,
    // macOS Keychain, Android/iOS backend) and therefore stayed: measured
    // on 06.09.2026, `hasMasterSeed()` kept returning `true` after the wipe
    // and `loadMasterSeed()` the V3 seed byte-IDENTICALLY. A surviving V3
    // seed is a compatibility path — and there is none on this line.
    //
    // **Why here and not in `runFirstStartWipe`:** the deletion path must
    // run BEFORE `KeyringService.init` (see reasoning above, D3 in the
    // guard). At that time there is no backend. The keyring therefore
    // goes one line later.
    //
    // **Only on a wipe that really ran.** `wipeReport == null` means: V4.1
    // marker present or no profile there at all. In both cases the keyring
    // stays untouched — otherwise the first start of a freshly created
    // identity would take away its own seed.
    //
    // MERGE S370 — WHAT CHANGES COMPARED TO BOTH SIDES.
    // The version this block stems from additionally justified its place
    // with "still BEFORE `KeyMigration.migrateIfNeeded`". This reasoning
    // has been DROPPED, not skipped: the two migration calls no longer
    // exist on this line (removal of the legacy profile takeover, reasoning
    // below). What remains is the order relative to
    // `reconcileKeyringDeposit`, and that is necessarily the other way
    // round than the migration was: FIRST clear the V3 seed out of the
    // keyring, THEN put today's in. Swapped, the wipe would take away the
    // deposit just made.
    if (wipeReport != null) {
      FirstStartWipe.wipeKeyringSecrets(keyring, baseDir, report: wipeReport);
    }

    IdentityManager(baseDir: baseDir).reconcileKeyringDeposit();

    // ── HERE STOOD `migrateIfNeeded` AND `repairIfNeeded` (S368) ─────
    //
    // Both are removed. They took over a profile from the time before the
    // keyring — under the owner invariant ("V4.1 is not backward
    // compatible", "There are no legacy profiles") dead code. And since
    // S363 they could no longer hit their set anyway: the line above this
    // one has already deleted a profile without the V4.1 marker at this
    // moment, a profile WITH the marker was never a legacy profile.
    //
    // Both decided "new or old?" by the mere EXISTENCE of a file
    // (`db.key` or `.keyring_migrated`/`.db.key.migrated`) — a proxy the
    // application creates itself. Reasoning and measurement: header of
    // `lib/core/crypto/key_migration.dart`.

    // S362: the device-wide V4.1 storages at the profile root directory
    // (`node_keys.enc`, `v41_entries.json.enc`, `v41_ages.json.enc`) lay
    // until now under the legacy random key `db.key`, which lies NEXT TO
    // the ciphertext. MUST stand before the first reader: `NodeKeys
    // .loadOrCreate` is fail-loud (`node_keys.dart:455-459`) and throws
    // if the container is there but does not open — a key change without
    // this step would no longer have let the daemon start.
    KeyMigration.migrateDeviceScopedFiles(baseDir);

    // ── THE RAW KEY FROM THE REMOVED TAKEOVER (S368) ─────
    //
    // `.db.key.migrated` — 32 key bytes in plaintext that the old
    // `migrateIfNeeded` left behind on EVERY freshly created profile,
    // because it wrongly considered it a legacy profile. After the removal
    // the file can no longer come into existence anew; the profiles that
    // already carry it are cleaned up here. `LegacyKeyPurge` DELETES only
    // when demonstrably nothing hangs on it any more — otherwise it
    // touches nothing.
    //
    // MUST STAND AFTER `migrateDeviceScopedFiles`: that first takes the
    // device-wide files off this key. The other way round, the cleaner
    // would find them still hanging on it and would leave the key lying
    // forever.
    LegacyKeyPurge.purge(baseDir);

    // S363, measurement question 1: a leftover FILE copy of the 24 words
    // (`seed_phrase.json.enc` under the raw `db.key`) leads past the
    // device code lock, and nothing ever moved it over. MUST stand AFTER
    // the keyring and the cleaner, because both can still change the
    // storage place of the words, and `MobileKeyringService.init` — the
    // only other place where takeover happens — runs in `main.dart`
    // BEFORE this sequence. Without this call a migrated phrase would lie
    // ungated until the next start. Without a lock (every non-Android
    // platform, thus also the daemon) the call is a no-op.
    await IdentityManager(baseDir: baseDir).reconcileSeedPhraseGate();
  }

  /// The key under which the files of THIS identity lie — in three stages,
  /// and none of them creates a plaintext key.
  ///
  /// ── WHY THERE ARE THREE (S368) ────────────────────────────────────────
  ///
  /// Until S368 the call sites simply had `key: _fileEncKey`. If that is
  /// `null` — an identity without HD wallet, i.e. without master seed —,
  /// `FileEncryption` fell back to `_loadOrCreateLegacyKey` and put
  /// 32 random bytes as `$baseDir/db.key` NEXT TO the ciphertext. Exactly
  /// that is the plaintext key this work eliminates.
  ///
  ///   1. **Seed-derived** (`deriveFileEncKey(masterSeed, hdIndex)`) —
  ///      the normal case and the only one that occurs in the field.
  ///   2. **An EXISTING legacy key** — read-only, so that a developer
  ///      profile from the time before S368 opens. `LegacyKeyPurge`
  ///      cleans it away at start as soon as nothing hangs on it any more.
  ///   3. **The keyring.** If there is neither seed nor legacy key,
  ///      ONE key per profile directory is held in the keyring
  ///      (`identity_file_key`). It is generated there, not on the disk
  ///      — the same answer as for the master seed itself: what cannot be
  ///      derived belongs in the keyring and not in a file next to it.
  ///
  /// It throws only if the keyring cannot be had either. Then there is no
  /// permissible storage place, and silence would be the wrong answer.
  Uint8List? _resolvedFileEncKey;

  Future<Uint8List> _dissolveFileEncKey() async {
    final derived = _fileEncKey;
    if (derived != null) return _resolvedFileEncKey = derived;
    final already = _resolvedFileEncKey;
    if (already != null) return already;

    final old = FileEncryption.legacyKeyBytes(_baseDir);
    if (old != null) {
      _log.warn('Identity without HD wallet: the files are still under '
          'the old key of this profile. `LegacyKeyPurge` replaces it '
          'as soon as nothing depends on it any more.');
      return _resolvedFileEncKey = old;
    }
    return _resolvedFileEncKey =
        await _dissolveBundleKey(_identityFileKeyName);
  }

  /// Fetches a 32-B key from the keyring and creates it THERE if it is
  /// missing. Throws if the keyring does not accept it — there is no
  /// falling back to a plaintext file (S368).
  Future<Uint8List> _dissolveBundleKey(String name) async {
    if (!KeyringService.isInitialized) {
      await KeyringService.init(_baseDir);
    }
    final ring = KeyringService.instance;
    final outBundle = ring.load(name);
    if (outBundle != null && outBundle.length == 32) return outBundle;
    final fresh = SodiumFFI().randomBytes(32);
    if (!ring.store(name, fresh)) {
      throw StateError(
          'No master seed in $_baseDir, and the keyring does not accept '
          '"$name". Formerly a fresh plaintext `db.key` was created '
          'here; that has been forbidden since S368.');
    }
    _log.info('Without master seed: "$name" now lies in the keyring — '
        'not on the disk.');
    return fresh;
  }

  /// The two names in the keyring for the case without master seed.
  /// Both are DEVICE-WIDE: an identity without seed has no HD index on
  /// which a key could hang.
  static const String _identityFileKeyName = 'identity_file_key';
  static const String _deviceFileKeyName = 'device_shared_file_key';

  /// The resolved key for the SYNCHRONOUS write paths.
  ///
  /// [_dissolveFileEncKey] is `async` (the keyring may cost a process
  /// call) and runs once in [initKeys]; after that the result stands here.
  /// The remaining places are synchronous and take it from here — they all
  /// run AFTER [initKeys].
  Uint8List? get _fileEncKeyEffective => _fileEncKey ?? _resolvedFileEncKey;

  /// Create a fully-configured IdentityContext from an Identity record.
  /// Ensures masterSeed, hdIndex, baseDir, networkChannel are always set.
  static Future<IdentityContext> createFromIdentity({
    required Identity identity,
    required String baseDir,
    required Uint8List? masterSeed,
    String? overrideDisplayName,
  }) async {
    final ctx = IdentityContext(
      profileDir: identity.profileDir,
      baseDir: baseDir,
      displayName: overrideDisplayName ?? identity.displayName,
      networkChannel: NetworkSecret.channel.name,
      hdIndex: identity.hdIndex,
      masterSeed: masterSeed,
      createdAt: identity.createdAt,
      isAdult: identity.isAdult,
      restoreAwaitingPairing: identity.restoreAwaitingPairing,
      restoredFromPhrase: identity.restoredFromPhrase,
    );
    await ctx.initKeys();
    identity.nodeIdHex = ctx.userIdHex;
    return ctx;
  }

  /// nodeIdHex returns the per-device routing ID (used by transport layer).
  /// For service-level identification (contacts, groups, channels), use userIdHex.
  String get nodeIdHex => bytesToHex(deviceNodeId);
  String get userIdHex => bytesToHex(userId);
  String get deviceNodeIdHex => bytesToHex(deviceNodeId);

  /// §3.7 step 5: per-identity FileEncryption key derived from master seed.
  /// Null for legacy profiles without HD-Wallet (random keys, pre-migration).
  Uint8List? get _fileEncKey =>
      (masterSeed != null && hdIndex != null)
          ? HdWallet.deriveFileEncKey(masterSeed!, hdIndex!)
          : null;

  // ── THE ENCRYPTED STORAGE OF THIS IDENTITY (S366, §21.4) ─────
  //
  // WHY IT LIES HERE AND NOT IN THE SERVICE. Until S366 `CleonaService.store`
  // was the only opener. That held as long as only service collections
  // were switched — but [initKeys] runs BEFORE there is a
  // `CleonaService` (`IdentityContext.createFromIdentity` ->
  // `initKeys`, only afterwards `CleonaService(identity: ...)`). The owner
  // of the storage must therefore be the one that can hold its key:
  // profile directory, master seed and HD index all lie here.
  //
  // `CleonaService.store` has since forwarded here — ONE handle per
  // identity on ONE file, not two.
  //
  // ── THE UNLOCK CHAIN, RE-MEASURED (S366) ───────────────────────
  //
  // What is needed to OPEN the storage cannot lie in it. Measured against
  // the start order, these are exactly two things, and both stay files:
  //   * the master seed — keyring, otherwise `<baseDir>/master_seed.json`
  //     (`IdentityManager.loadMasterSeed`, explicitly justified there),
  //   * `<baseDir>/identities.json`, which carries the `hdIndex`.
  // `service_daemon.dart:541` or `main.dart:2097` fetch the seed,
  // `identities.first.hdIndex` comes from `identities.json` — and only
  // AFTER that does `createFromIdentity` (`identity_context.dart:427`) call
  // `initKeys()`. `keys.json` was thus never part of the unlock chain,
  // but always its consumer.
  MessageStore? _store;

  /// The storage of this identity, or `null` if no seed-derived key
  /// exists.
  ///
  /// `null` is NOT an operating case: an identity without HD wallet already
  /// fails in the field at `_loadContacts`, because `CleonaService.store`
  /// (rightly) refuses to open with a substitute key (§21.4.1).
  /// It is the case of the guards that must measure an identity WITHOUT a
  /// seed — there [initKeys] stays on the file path, visibly named.
  MessageStore? get storeOrNull {
    final k = _fileEncKey;
    if (k == null) return null;
    if (_store != null) return _store;
    Directory(profileDir).createSync(recursive: true);
    return _store = MessageStore.open('$profileDir/messages.db', k, logger: _log);
  }

  /// Closes the storage. Callable separately, so that an identity switch
  /// does not leave the file open.
  void closeStore() {
    _store?.close();
    _store = null;
  }

  /// The area with the key material of this identity.
  static const String areaKeys = 'keys';

  /// The ONE row in it. The key material is fixed in the number of its
  /// fields; it does not grow.
  static const String keyKeys = '_';

  /// The rotation chain (SR-2) — AN AREA OF ITS OWN, and for the same
  /// reason for which `syschan_records`/`syschan_gone` and
  /// `devices`/`device_sync_dedup` are also separate: it GROWS. Every soft
  /// re-key appends a link of about 4 kB, and none is ever removed
  /// (`foundingEd25519Pk` needs the first link forever). If it lay as a
  /// field in the `keys` row, every rotation would rewrite the whole chain
  /// — exactly the full write the table is built against. Here one link
  /// costs one row.
  static const String areaRotationChain = 'key_rotation_chain';

  /// Loads the key material of this identity — or generates it.
  ///
  /// S366: from the encrypted storage (area [areaKeys], chain in
  /// [areaRotationChain]) instead of from `keys.json.enc`. The takeover
  /// step for legacy holdings is deliberately dropped; the reasoning
  /// stands above `MessageStore.putEntry` (first-start deletion,
  /// owner decision 3 of 03.09.2026).
  ///
  /// Also dropped: the branch that tentatively opened `keys.json.enc` with
  /// the legacy `db.key` and then re-encrypted it. It had exactly the same
  /// subject — legacy profiles — and that does not exist.
  ///
  /// ── THE DATA-LOSS LATCH THAT NEVER EXISTED HERE ──────────────────
  ///
  /// The previous version ran into the `else` branch on `json == null`
  /// and GENERATED NEW KEYS. But `FileEncryption.readJsonFile` returns
  /// `null` not only if the file is missing, but also if it cannot be
  /// decrypted (own documentation: "Returns null if file doesn't exist
  /// **or cannot be decrypted**"). A single flipped bit in
  /// `keys.json.enc` thus cost the identity: new Ed25519 key, new user
  /// ID, every contact points to a stranger, every group loses the member
  /// — and the log said "New keys generated", as if it were a first
  /// start.
  ///
  /// The latch now measures on the carrier: if the area holds rows
  /// (`countArea`) from which nevertheless no key set can be built, it
  /// THROWS. An empty area remains the first start. The same for the
  /// rotation chain: if even just its FIRST link is missing,
  /// `foundingEd25519Pk` wanders onto today's key and the user ID of the
  /// identity changes (§3.1 stable anchor / SR-2) — so there too it throws
  /// instead of guessing.
  Future<void> initKeys() async {
    // S368: WITHOUT a seed-derived key no plaintext `db.key` comes into
    // existence any more — the key then comes from the KEYRING.
    // Resolution in [_dissolveFileEncKey].
    final fileEnc =
        FileEncryption(baseDir: _baseDir, key: await _dissolveFileEncKey());
    final deposit = storeOrNull;
    if (deposit == null) {
      // No seed-derived key -> no storage. See [storeOrNull]: that is the
      // guard case, not an operating case.
      _log.warn('Identity without HD wallet: the key material stays in '
          'keys.json.enc under the legacy `db.key`. In the field this '  // V3-TOUCH-OK: legacy key fallback, normative in v4_1 §4.5.3 (db.key is one of the six files that never move into the database)
          'case does not exist — there even the store of the conversations fails '
          '(§21.4.1).');
    }

    final Map<String, dynamic>? json = deposit == null
        ? fileEnc.readJsonFile('$profileDir/keys.json')
        : _readKeysOutDeposit(deposit);

    if (json != null) {
      ed25519PublicKey = hexToBytes(json['ed25519_pk'] as String);
      ed25519SecretKey = hexToBytes(json['ed25519_sk'] as String);
      mlDsaPublicKey = hexToBytes(json['ml_dsa_pk'] as String);
      mlDsaSecretKey = hexToBytes(json['ml_dsa_sk'] as String);
      x25519PublicKey = hexToBytes(json['x25519_pk'] as String);
      x25519SecretKey = hexToBytes(json['x25519_sk'] as String);
      mlKemPublicKey = hexToBytes(json['ml_kem_pk'] as String);
      mlKemSecretKey = hexToBytes(json['ml_kem_sk'] as String);
      // Load previous keys if present (rotation fallback)
      if (json['prev_x25519_sk'] != null) {
        previousX25519Sk = hexToBytes(json['prev_x25519_sk'] as String);
      }
      if (json['prev_ml_kem_sk'] != null) {
        previousMlKemSk = hexToBytes(json['prev_ml_kem_sk'] as String);
      }
      if (json['key_rotated_at'] != null) {
        keyRotatedAt = DateTime.fromMillisecondsSinceEpoch(json['key_rotated_at'] as int);
      }
      if (json['keys_created_at'] != null) {
        keysCreatedAt = DateTime.fromMillisecondsSinceEpoch(json['keys_created_at'] as int);
      } else {
        // Migrate legacy keys: set creation time to now, rotation starts in 7 days
        keysCreatedAt = DateTime.now();
        _saveKeys(fileEnc);
      }
      // SR-2: the rotation chain. From its own area if there is a
      // storage; otherwise (guard without seed) from the field of the file.
      rotationChain.clear();
      if (deposit != null) {
        _readRotationChainOutDeposit(deposit);
      } else {
        final chainJson = json['rotation_chain'] as List<dynamic>?;
        if (chainJson != null) {
          for (final l in chainJson) {
            rotationChain
                .add(StoredRotationLink.fromJson(l as Map<String, dynamic>));
          }
        }
      }
      _log.info('Keys loaded'
          '${rotationChain.isNotEmpty ? ' (rotation chain: ${rotationChain.length} link(s))' : ''}');
    } else {
      await _generateKeysAsync();
      keysCreatedAt = DateTime.now();
      _saveKeys(fileEnc);
      _log.info('New keys generated');
    }

    // Compute User-ID: SHA-256(kIdentityDomain + FOUNDING ed25519 pk) —
    // stable anchor (v4.1 §4.1 / SR-2). `kIdentityDomain` is the PUBLIC,
    // channel-specific domain constant; it replaced the maintainer-key-derived
    // `NetworkSecret.identitySecret` because §4.1 forbids binding network
    // identity to the maintainer key. For never-rotated identities the founding
    // key IS the current key; after a soft re-key the userId stays pinned to
    // the chain's first link.
    // S388 ("identifier = A", v4.2 §4.1): the UserID depends on BOTH
    // founding signing keys, Ed25519 AND ML-DSA-65 — the same value as
    // `Address.identifier` in mycelium and the card fingerprint.
    userId = HdWallet.computeUserId(foundingEd25519Pk, foundingMlDsaPk);

    // Compute Device-Node-ID from the daemon-global Device-Sig keypair
    // (§3.1, §3.5). Multi-Identity sharing: all IdentityContexts in this
    // daemon load the SAME DeviceKeysStore (single file in baseDir) and
    // therefore derive the SAME deviceNodeId.
    // Device keys use the daemon-global SHARED encryption key (not the
    // per-identity key) so that every identity in this daemon decrypts
    // the same file with the same key. (Here stood "all identities and
    // CleonaNode"; `CleonaNode` was deleted with the CUT of 2026-08-31 —
    // the statement about the shared key applies unchanged.)
    // S368: WITHOUT a master seed this key was `null`, and `FileEncryption`
    // created a plaintext `db.key` for it. The same three-stage resolution
    // as for the identity files, only with a DEVICE-WIDE name in the
    // keyring — `device_keys.bin` belongs to the device, not to an
    // identity.
    final sharedFileEncKey = masterSeed != null
        ? HdWallet.deriveSharedFileEncKey(masterSeed!)
        : await _dissolveBundleKey(_deviceFileKeyName);
    final deviceFileEnc = FileEncryption(baseDir: _baseDir, key: sharedFileEncKey);
    final deviceBundle = DeviceKeysStore.loadOrCreate(baseDir: _baseDir, fileEnc: deviceFileEnc);
    // S360: the bundle is KEPT instead of thrown away after the one
    // derivation — see [deviceKeys].
    _deviceKeys = deviceBundle;
    deviceNodeId =
        HdWallet.computeDeviceNodeId(deviceBundle.sig.ed25519PublicKey);

    // S362: the display name is now only on `debug`. The identifiers
    // carry the diagnosis; the name is the part that names a person.
    _log.debug('Identity displayName="$displayName"');
    _log.info('Identity User-ID: ${userIdHex.substring(0, 16)}... '
        'Device-Node-ID: ${deviceNodeIdHex.substring(0, 16)}...');

    // Export device KEM public keys to plaintext JSON for E2E test
    // infrastructure (Android has no IPC — tests read this via ADB run-as).
    // Contains only PUBLIC keys, no secrets.
    //
    // ── S362: STAYS IN PLAINTEXT DELIBERATELY ──────────────────────────
    //
    // The finding report lists this file under 2.2 ("number and
    // identifiers of the devices"). Re-measured on 02.09.2026, that is not
    // right: EXACTLY THREE SCALAR FIELDS of this ONE device are written —
    // `deviceNodeIdHex`, `deviceX25519PkB64`, `deviceMlKemPkB64`. It is
    // not a list; no count stands in it, and neither do the identifiers of
    // other devices. The device list lies in `devices.json.enc` and is
    // encrypted.
    //
    // What would remain is the own device node ID plus two public keys.
    // The device node ID is the ROUTING identifier of this node — it
    // stands on the wire in every frame it sends. Whoever has the disk has
    // `identities/` anyway; he learns nothing here that the network does
    // not freely show every intermediate node.
    //
    // Against this stands a measurable price: FOUR E2E suites read the
    // file with `adb run-as … cat` and have no seed on the device from
    // which they could derive a key —
    // `gui-01b-ensure-contacts-android` (:123),
    // `gui-01c-ensure-contacts-avm-pair` (:210, :1012),
    // `gui-55-identity-resolution` (:156). An encryption here would cost
    // these four suites and buy nothing.
    //
    // OPEN and NOT to be decided here: that a pure test crutch is written
    // at all on every production start. That is a question of its own
    // (E2E access without IPC on Android) and not one of encryption at
    // rest.
    //
    // ── S368: THE TRUST ANCHOR IS ADDED ──────────────────────────
    //
    // `userEd25519PkB64` and `foundingEd25519PkB64` are the two keys that
    // EVERY ContactSeed carries publicly as `ep` and `fp` (§8.1.1) — so
    // nothing stands here that is not printed on every invitation link of
    // this node anyway.
    //
    // They must stand here, because `gui-01c-ensure-contacts-avm-pair`
    // (:1025-1033) assembles its ContactSeed URI from exactly this file
    // and until today built it WITHOUT `ep`. Such a seed could not be
    // recomputed by the other side; since S368 it is rejected, and without
    // this addition the suite could no longer build a valid one at all.
    // (The request would never have gone out before either — the then
    // `sendContactRequest` aborted without `ep` —, it just did not become
    // visible.) S389: `sendContactRequest` no longer exists
    // (S388-BAU-KONTAKT); on the V4.2 line the request arises when
    // redeeming an invitation card (§15.5) and goes out via the seam
    // `sendToUser` (§22.5, `mycelium_seam.dart`).
    try {
      File('$_baseDir/device_kem_public.json').writeAsStringSync(jsonEncode({
        'deviceNodeIdHex': deviceNodeIdHex,
        'deviceX25519PkB64': base64Encode(deviceBundle.kem.x25519PublicKey),
        'deviceMlKemPkB64': base64Encode(deviceBundle.kem.mlKemPublicKey),
        'userEd25519PkB64': base64Encode(ed25519PublicKey),
        'foundingEd25519PkB64': base64Encode(foundingEd25519Pk),
      }));
    } catch (_) {
      // Non-fatal: file is only consumed by E2E tests.
    }
  }

  /// Reads the `keys` row — with the latch from [initKeys].
  Map<String, dynamic>? _readKeysOutDeposit(MessageStore deposit) {
    final line = deposit.loadArea(areaKeys)[keyKeys];
    if (line != null) return line;

    final present = deposit.countArea(areaKeys);
    if (present > 0) {
      throw StateError(
          'IdentityContext: the area `$areaKeys` holds $present '
          'row(s), but no readable key set — NO new keys '
          'are generated. New keys would mean: a new '
          'Ed25519 root, a new user ID, every contact and every group '
          'points to a stranger (§3.1 stable anchor).');
    }
    return null; // First start — there is nothing yet.
  }

  /// Reads the rotation chain — with the latch from [initKeys].
  void _readRotationChainOutDeposit(MessageStore deposit) {
    final lines = deposit.loadArea(areaRotationChain);
    final present = deposit.countArea(areaRotationChain);
    if (lines.length < present) {
      throw StateError(
          'IdentityContext: the area `$areaRotationChain` holds '
          '$present link(s), of which only ${lines.length} '
          'can be unpacked — NO incomplete chain is '
          'returned. If the first link is missing, `foundingEd25519Pk` moves '
          'to the current key and the user ID of the identity '
          'changes (SR-2 / §7.4b).');
    }
    // The storage does not guarantee any order; but the chain is an
    // order. The key IS the position.
    final positions = lines.keys.map(int.parse).toList()..sort();
    for (final i in positions) {
      rotationChain.add(StoredRotationLink.fromJson(lines['$i']!));
    }
  }

  Future<void> _generateKeysAsync() async {
    final sodium = SodiumFFI();

    // Ed25519 + X25519: deterministic from seed if HD-Wallet, random otherwise
    if (masterSeed != null && hdIndex != null) {
      final edKeys = HdWallet.deriveEd25519(masterSeed!, hdIndex!);
      ed25519PublicKey = edKeys.publicKey;
      ed25519SecretKey = edKeys.secretKey;
      _log.info('Ed25519 keys derived from HD-Wallet index $hdIndex');
    } else {
      final edKeys = sodium.generateEd25519KeyPair();
      ed25519PublicKey = edKeys.publicKey;
      ed25519SecretKey = edKeys.secretKey;
    }

    x25519PublicKey = sodium.ed25519PkToX25519(ed25519PublicKey);
    x25519SecretKey = sodium.ed25519SkToX25519(ed25519SecretKey);

    // PQ keys: deterministic from seed (seed recovery), or random.
    // Background isolate avoids ANR on Android (15-30s on slow devices).
    final ({Uint8List mlDsaPk, Uint8List mlDsaSk, Uint8List mlKemPk, Uint8List mlKemSk}) pqKeys;
    if (masterSeed != null && hdIndex != null) {
      pqKeys = await generatePqKeysDeterministicIsolated(masterSeed!, hdIndex!);
      _log.info('PQ keys derived deterministically from HD-Wallet index $hdIndex');
    } else {
      pqKeys = await generatePqKeysIsolated();
    }
    mlDsaPublicKey = pqKeys.mlDsaPk;
    mlDsaSecretKey = pqKeys.mlDsaSk;
    mlKemPublicKey = pqKeys.mlKemPk;
    mlKemSecretKey = pqKeys.mlKemSk;
  }

  /// Writes the key material.
  ///
  /// `putEntry` and not `replaceArea` — for BOTH areas, but for two
  /// different reasons: the `keys` row is the only copy of the secret keys
  /// of this identity, and `replaceArea` would delete it first; the
  /// rotation chain grows monotonically, and a link never disappears
  /// from it.
  void _saveKeys(FileEncryption fileEnc) {
    Directory(profileDir).createSync(recursive: true);
    final data = <String, dynamic>{
      'ed25519_pk': bytesToHex(ed25519PublicKey),
      'ed25519_sk': bytesToHex(ed25519SecretKey),
      'ml_dsa_pk': bytesToHex(mlDsaPublicKey),
      'ml_dsa_sk': bytesToHex(mlDsaSecretKey),
      'x25519_pk': bytesToHex(x25519PublicKey),
      'x25519_sk': bytesToHex(x25519SecretKey),
      'ml_kem_pk': bytesToHex(mlKemPublicKey),
      'ml_kem_sk': bytesToHex(mlKemSecretKey),
    };
    if (previousX25519Sk != null) data['prev_x25519_sk'] = bytesToHex(previousX25519Sk!);
    if (previousMlKemSk != null) data['prev_ml_kem_sk'] = bytesToHex(previousMlKemSk!);
    if (keyRotatedAt != null) data['key_rotated_at'] = keyRotatedAt!.millisecondsSinceEpoch;
    if (keysCreatedAt != null) data['keys_created_at'] = keysCreatedAt!.millisecondsSinceEpoch;

    final deposit = storeOrNull;
    if (deposit == null) {
      // Guard without seed — see [storeOrNull]. There the chain keeps its
      // field in the same map, because there is no second carrier.
      if (rotationChain.isNotEmpty) {
        data['rotation_chain'] =
            rotationChain.map((l) => l.toJson()).toList();
      }
      fileEnc.writeJsonFile('$profileDir/keys.json', data);
      return;
    }

    deposit.putEntry(areaKeys, keyKeys, data);
    // ORDER: first the key set, then the chain. If it breaks off in
    // between, the most recent chain link is missing — the identity keeps
    // its user ID (that hangs on the FIRST link) and the rotation is
    // appended again on the next run. The other way round, a link would
    // lie there whose new key stands nowhere.
    for (var i = 0; i < rotationChain.length; i++) {
      deposit.putEntry(areaRotationChain, '$i', rotationChain[i].toJson());
    }
  }

  /// Check if KEM keys need rotation (older than [kKemRotationInterval]).
  ///
  /// ── THE NUMBER STOOD HERE TWICE, BARE (S363) ──────────────────────
  ///
  /// Until S363 a literal `7` stood in both branches, and there was no
  /// named constant for it. But the same quantity also decides from when
  /// on a STORED copy of foreign KEM keys misses the one previous
  /// generation from §4.5.4 ([kemCopyFreshness]). Two literals for one
  /// quantity means: the freshness rule would hang on a number that only
  /// coincides with the rotation interval by chance. It now stands once,
  /// in `kem_generation.dart`.
  bool needsRotation() {
    final now = DateTime.now();
    // If rotated before, check time since last rotation
    if (keyRotatedAt != null) {
      return now.difference(keyRotatedAt!) >= kKemRotationInterval;
    }
    // Never rotated: check time since key creation
    if (keysCreatedAt != null) {
      return now.difference(keysCreatedAt!) >= kKemRotationInterval;
    }
    return false;
  }

  /// Rotate x25519 + ML-KEM keys. Moves current to previous, generates new.
  /// ML-KEM keygen runs in background isolate to avoid ANR on Android.
  Future<void> rotateKemKeys() async {
    final fileEnc = FileEncryption(baseDir: _baseDir, key: _fileEncKeyEffective);
    final sodium = SodiumFFI();

    // Move current to previous
    previousX25519Sk = x25519SecretKey;
    previousMlKemSk = mlKemSecretKey;

    // Generate new x25519 (independent, not derived from ed25519)
    final newX25519 = sodium.generateX25519KeyPair();
    x25519PublicKey = newX25519.publicKey;
    x25519SecretKey = newX25519.secretKey;

    // Generate new ML-KEM in background isolate (avoids ANR)
    final newKem = await generateMlKemIsolated();
    mlKemPublicKey = newKem.publicKey;
    mlKemSecretKey = newKem.secretKey;

    keyRotatedAt = DateTime.now();
    _saveKeys(fileEnc);
    _log.info('KEM keys rotated. Previous keys kept for '
        '${previousKeyRetention.inDays} days.');
  }

  /// Emergency full identity rotation (§26.6.2).
  /// Replaces ALL keys (Ed25519, ML-DSA, X25519, ML-KEM), recomputes Node-ID,
  /// keeps old KEM secret keys as previous for the [previousKeyRetention]
  /// transit-message grace period.
  void rotateIdentityFull({
    required Uint8List newEd25519Pk,
    required Uint8List newEd25519Sk,
    required Uint8List newMlDsaPk,
    required Uint8List newMlDsaSk,
    required Uint8List newX25519Pk,
    required Uint8List newX25519Sk,
    required Uint8List newMlKemPk,
    required Uint8List newMlKemSk,
  }) {
    final fileEnc = FileEncryption(baseDir: _baseDir, key: _fileEncKeyEffective);

    // SR-2 (§3.1 stable anchor / §7.4b step 4): append the continuity link
    // BEFORE replacing keys — the OLD secret key signs the successor pubkeys
    // (`newEd25519Pk || newMlDsaPk`, the §4.3 RotationChainLink shape).
    // Ed25519 signing is deterministic, so a twin device re-deriving the
    // same new keys from the synced entropy produces a byte-identical
    // Ed25519 link signature. The ML-DSA signature next to it is NOT
    // (liboqs signs hedged) — two twins produce different bytes there.
    // That is without consequence: no consumer compares links across
    // devices, and every checker checks the signature instead of comparing
    // it (S392, measured in
    // `test/smoke/smoke_syschan_rotation_chain.dart`).
    final linkContent =
        StoredRotationLink.linkContentOf(newEd25519Pk, newMlDsaPk);
    rotationChain.add(StoredRotationLink(
      oldEd25519Pk: ed25519PublicKey,
      oldMlDsaPk: mlDsaPublicKey,
      newEd25519Pk: newEd25519Pk,
      newMlDsaPk: newMlDsaPk,
      oldSignatureEd25519:
          SodiumFFI().signEd25519(linkContent, ed25519SecretKey),
      // §4.5.4 "The chain is signed hybrid": the whole keypair is present
      // here, so BOTH old keys sign.
      oldSignatureMlDsa: OqsFFI().mlDsaSign(linkContent, mlDsaSecretKey),
    ));

    // Keep old KEM secret keys for transit messages ([previousKeyRetention])
    previousX25519Sk = x25519SecretKey;
    previousMlKemSk = mlKemSecretKey;

    // Replace all keys
    ed25519PublicKey = newEd25519Pk;
    ed25519SecretKey = newEd25519Sk;
    mlDsaPublicKey = newMlDsaPk;
    mlDsaSecretKey = newMlDsaSk;
    x25519PublicKey = newX25519Pk;
    x25519SecretKey = newX25519Sk;
    mlKemPublicKey = newMlKemPk;
    mlKemSecretKey = newMlKemSk;

    keyRotatedAt = DateTime.now();

    // SR-2: the User-ID is NOT recomputed — it stays pinned to the founding
    // key (§3.1 stable anchor); the chain above proves founding→current.
    // (The pre-SR-2 implementation recomputed it from the new key here —
    // that contradicted §3.1, left the D1 chain path unused, and made
    // rotation a free identity reset.) DeviceID is likewise unchanged: it
    // derives from the daemon-global Device-Sig keypair (§3.1, §3.5).

    _saveKeys(fileEnc);
    _log.info('Full identity rotation complete (stable anchor): User-ID '
        '${userIdHex.substring(0, 16)}... unchanged, '
        'chain length ${rotationChain.length}');
  }

  /// LD-8: Linked-Device delegation rotation after the Primary's emergency
  /// key rotation. Updates the User-PKs, the user signature SKs, the user KEM
  /// SK, the delegation keys and the rotation chain — WITHOUT receiving the
  /// master seed.
  ///
  /// ── THE SIGNATURE SECRET KEYS ROTATE ALONG (v4_2 §14.4) ──────────────
  ///
  /// Until S392 this method updated the PUBLIC user signature keys and left
  /// the SECRET ones untouched, justified in the doc comment as "the
  /// load-bearing boundary of §7.1.1". **That justification came from a
  /// record state, not from the norm.** §7.1.1 is a V3 number
  /// (`Cleona_Chat_Architecture_v3_0.md:3233`, the linked-device model:
  /// delegated subkey + certificate + user KEM SK, but no user sig SK); in
  /// v4_2 chapter 7 is the delivery ladder and no §7.1.1 exists there.
  ///
  /// v4_2 §14.4 ("What rotates along") says the opposite, verbatim:
  ///
  /// > **The identity signature keys also rotate along at lock-out.** They
  /// > sit — like the user KEM SK — **under the shared key on every
  /// > device**; only this way can every device issue delegation
  /// > certificates alone. Without co-rotation, a locked-out device would
  /// > retain the ability to sign in the identity's name.
  ///
  /// §14.6.2 lists exactly one piece a linked device does NOT receive:
  /// **the seed**. Not the signature keys. So [newUserEd25519Sk] /
  /// [newUserMlDsaSk] travel in the LD-8 message — the same channel, the
  /// same sealing that already carries `newUserX25519Sk` / `newUserMlKemSk`
  /// — and are set here.
  ///
  /// What that repairs (measured, S392 report `S392-FIX-LD8.md`): before
  /// this change the device signed every system-channel record with a key
  /// that did not belong to the public key the same record carried inline,
  /// so `SystemChannelRecordStore.verifyRecord` failed at its FIRST step —
  /// in the device's own admission. Bug Log, feature requests, voting and
  /// retraction fell out silently from the FIRST rotation on. From the
  /// second rotation a second cause was added: the chain link could no
  /// longer be signed (see `canProveLink` below) and a chain with an empty
  /// link is rejected. Both causes share this one root.
  ///
  /// What this does NOT change: `signingEd25519Sk` / `signingMlDsaSk` keep
  /// routing every inner-sig of a linked device to the DELEGATED keys, and
  /// the device's own device-bound records keep going out under the
  /// delegated key plus certificate chain (§14.6.2). The user signature keys
  /// are the identity's keys, not the device's.
  ///
  /// The trade-off is §14.4's, not this code's: the secret identity
  /// signature keys now lie on every linked device, which widens what a
  /// stolen, unlocked device holds. §14.4 makes that call explicitly — "a
  /// stolen, unlocked device is a **valid** member" — and puts the
  /// protection into the quorum lock-out (§14.8), not into withholding keys.
  void rotateDelegation({
    required Uint8List newUserEd25519Pk,
    required Uint8List newUserMlDsaPk,
    required Uint8List newUserEd25519Sk,
    required Uint8List newUserMlDsaSk,
    required Uint8List newUserX25519Pk,
    required Uint8List newUserMlKemPk,
    required Uint8List newUserX25519Sk,
    required Uint8List newUserMlKemSk,
    required LinkedDeviceKeys newLinkedKeys,
  }) {
    final fileEnc = FileEncryption(baseDir: _baseDir, key: _fileEncKeyEffective);

    final linkContent =
        StoredRotationLink.linkContentOf(newUserEd25519Pk, newUserMlDsaPk);
    // The link is only a continuity proof if the OLD User-SK we still hold
    // actually belongs to `ed25519PublicKey`. Since S392 it does — the sig
    // SKs rotate along (§14.4), so `canProveLink` is expected to be true on
    // every rotation, and a linked device produces a fully hybrid-signed
    // chain just like the Primary does in `rotateIdentityFull`.
    //
    // The check stays as a fail-closed guard, not as an expected path: if a
    // caller ever hands in a key pair that does not match (a truncated LD-8
    // message, a future sender that forgets a field), signing anyway would
    // emit a link that LOOKS like a proof but verifies against nothing —
    // worse than an absent one, because a resolver classifies a manifest
    // carrying a broken chain as `forged`. Better an empty link plus the
    // warning below than a forged-looking one.
    // S392: the probe runs over BOTH signatures. A chain whose link only
    // holds classically is not a hybrid proof according to §4.5.4 — and a
    // checker that checks it hybrid (system_channel_records.dart) would
    // reject it anyway. Either both or neither.
    final candidateSig = SodiumFFI().signEd25519(linkContent, ed25519SecretKey);
    final candidateSigMlDsa = OqsFFI().mlDsaSign(linkContent, mlDsaSecretKey);
    final canProveLink =
        SodiumFFI().verifyEd25519(linkContent, candidateSig, ed25519PublicKey) &&
            OqsFFI()
                .mlDsaVerify(linkContent, candidateSigMlDsa, mlDsaPublicKey);
    if (!canProveLink) {
      // Since S392 this is an ANOMALY, not the normal path: §14.4 has the
      // sig SKs rotate along, so the key we sign with must match. Reaching
      // this line means the LD-8 message was incomplete.
      _log.error('LD-8: User-Sig-SK does not match current User-PK although '
          '§14.4 co-rotation is in effect — rotation-chain link stored '
          'WITHOUT signature (fail closed); the LD-8 message is incomplete');
    }
    rotationChain.add(StoredRotationLink(
      oldEd25519Pk: ed25519PublicKey,
      oldMlDsaPk: mlDsaPublicKey,
      newEd25519Pk: newUserEd25519Pk,
      newMlDsaPk: newUserMlDsaPk,
      oldSignatureEd25519: canProveLink ? candidateSig : Uint8List(0),
      oldSignatureMlDsa: canProveLink ? candidateSigMlDsa : Uint8List(0),
    ));

    previousX25519Sk = x25519SecretKey;
    previousMlKemSk = mlKemSecretKey;

    ed25519PublicKey = newUserEd25519Pk;
    mlDsaPublicKey = newUserMlDsaPk;
    // §14.4: "The identity signature keys also rotate along at lock-out …
    // they sit under the shared key on EVERY device." Before S392 these two
    // lines were missing; see the doc comment above for what that broke.
    ed25519SecretKey = newUserEd25519Sk;
    mlDsaSecretKey = newUserMlDsaSk;
    x25519PublicKey = newUserX25519Pk;
    x25519SecretKey = newUserX25519Sk;
    mlKemPublicKey = newUserMlKemPk;
    mlKemSecretKey = newUserMlKemSk;

    linkedDeviceKeys = newLinkedKeys;
    keyRotatedAt = DateTime.now();

    _saveKeys(fileEnc);
    _log.info('Delegation rotation complete (LD-8): User-ID '
        '${userIdHex.substring(0, 16)}... unchanged, '
        'chain length ${rotationChain.length}');
  }

  /// How long the PREVIOUS KEM generation stays around after a rotation.
  ///
  /// ── THE BRACKET FROM §4.5.4, BUILT ON 02.09.2026 (S362) ─────────────
  ///
  /// §4.5.4 names two deadlines in one sentence: "the retention deadline for
  /// the previous KEM keys is the **rotation interval itself — 7 days**
  /// (32 days for the 31-day TTL class)". Until S362 only the first number
  /// stood here. The second belongs to the management retention class
  /// (`kManagementKeepEpochs` = 31, `secure_mode.dart`), whose cells lie
  /// up to 31 days at the responsible relay and whose harvest also
  /// collects them since S362.
  ///
  /// THERE IS ONLY ONE PREDECESSOR SLOT, so there can only be ONE
  /// deadline: §4.5.4 explicitly holds on to "Exactly **one** previous
  /// generation is retained", and `MessageOpener` knows no classes at all
  /// (it only sees a cell, never its storage frame). The longer of the two
  /// deadlines is therefore the only one that can carry both promises at
  /// once — 7 days would break the 31-day class, 32 days does not break
  /// the 7-day class (it holds longer than necessary, never shorter).
  ///
  /// ── WHAT THIS DEADLINE DOES NOT ACHIEVE, AND MEASURED SO ────────────────
  ///
  /// It extends the lifetime of a particular generation ONLY as long as no
  /// rotation comes in between: [rotateKemKeys] overwrites the predecessor
  /// slot on EVERY rotation (`previousX25519Sk = x25519SecretKey`, above).
  /// A continuously running device rotates every 7 days, so generation N−1
  /// still falls out of the slot there after 7 days — not through this
  /// deadline, but through the next rotation. Whoever reads "32 days
  /// openable during operation" out of this number reads too much; that
  /// would be a SECOND predecessor slot, and §4.5.4 rules that out.
  ///
  /// WHAT IT DOES ACHIEVE: it takes away the discarding's lead over the
  /// replacing. Until S362 the condition here and the one in
  /// [needsRotation] were IDENTICAL WORD FOR WORD (`inDays >= 7` on
  /// [keyRotatedAt]) — the discarding could thus never fire without a
  /// simultaneously due rotation, but very well WITHOUT that rotation
  /// arriving: the caller calls it first and starts the rotation
  /// afterwards unobserved (`cleona_service.dart`, `_performKeyRotation()`
  /// is `async` and not awaited; the ML-KEM generation runs in an
  /// isolate). If it aborts or the process dies in between, the
  /// predecessor was destroyed without having been replaced. With 32 days
  /// it stays around in this case until the rotation is caught up.
  static const Duration previousKeyRetention = Duration(days: 32);

  /// Discard previous keys once [previousKeyRetention] has passed.
  void discardPreviousKeysIfExpired() {
    if (keyRotatedAt == null || previousX25519Sk == null) return;
    if (DateTime.now().difference(keyRotatedAt!) >= previousKeyRetention) {
      previousX25519Sk = null;
      previousMlKemSk = null;
      final fileEnc = FileEncryption(baseDir: _baseDir, key: _fileEncKeyEffective);
      _saveKeys(fileEnc);
      _log.info('Previous KEM keys discarded (retention expired)');
    }
  }

  // ── `ownPeerInfo()` REMOVED ON 2026-08-31 (CUT) ───────────────────
  //
  // The method built a `PeerInfo` from this identity — the V3 wire model
  // of a node (address list with `PeerAddressType`, public/local IP pair,
  // device PoW nonce) — for the self-broadcast via PEER_LIST_PUSH. It had
  // FOUR callers, all in `lib/core/node/cleona_node.dart` (:3220, :7370,
  // :7480, :7542), and not a single one outside of that. With
  // `lib/core/node/` and `lib/core/network/peer_info.dart` the last
  // consumer falls away.
  //
  // V4.1 has no counterpart at this place and needs none: the own
  // reachability is no longer scattered as a node record into a routing
  // table, but published pairwise via the rendezvous (§4.1/§23) —
  // `lib/core/rendezvous/` reads the addresses there via
  // `RendezvousAddress`, not via `PeerInfo`.
  // Hence (T) and not (G): without replacement, no gap.
}
