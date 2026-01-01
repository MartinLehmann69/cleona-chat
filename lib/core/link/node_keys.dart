/// Node keys — the node-bound, identity-free key material of the link layer
/// (AP-3a stage 2; architecture v4 §2.6, §3.5.2, §4.5;
/// docs/SPEC_MYZEL_NETWORK_DRAFT.md §20 E-81 and E-82).
///
/// Four pieces of key material live here, all **device**-bound and carrying
/// **no** UserID — a device hosts several identities (§3.5.1) and an
/// identity-bound entry record would correlate them (§4.5):
///
/// ```
/// L_node            32 B     entry secret; MAC key of the handshake `init` (§2.6)
/// E_node            Ed25519  issuer of the entry record (§4.5)
/// N_x25519          X25519   static node key; k_prov of flight 1 (E-82)
/// N_mlkem           ML-KEM-768 static node key; the link handshake
///                            encapsulates against it (E-82; pk 1184 B, sk 2400 B)
/// ```
///
/// **Why this file exists at all (E-81).** The profile layout of §3.5.2 named
/// every key class individually — master seed, device keys, field state, entry
/// cache — and `L_node`/`E_node` appeared in none of them. It was therefore not
/// even stated whether they survive a restart. They must: an `L_node`
/// regenerated on every start invalidates every outstanding entry record (6 h)
/// and every ContactSeed in circulation (up to 90 days) — and it does so
/// **silently**, because a wrong `L_node` produces neither an answer nor an
/// error, by construction (§2.6). [loadOrCreate] is that persistence.
///
/// The container sits in `node_keys.enc` at the profile root, next to
/// `device_keys.enc` and **outside** `identities/` (§3.5.2). It is encrypted
/// with the same XSalsa20-Poly1305 file envelope as every other `.enc` file in
/// the profile ([FileEncryption]); no new cryptography is introduced here.
///
/// **Rotation is not automatic (E-81).** There is deliberately no timer, no
/// scheduler and no clock-driven path in this class — the only way to rotate is
/// the explicit [rotate] call. See the comment on [rotate] for the reasoning.
library;

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/secure_memory.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

/// The node-bound, identity-free key material of the link layer.
///
/// Instances are long-lived: the daemon loads one at start via [loadOrCreate]
/// and keeps it for its whole run. The secret fields are therefore **not**
/// zeroed by this class — only the transient serialization buffers are.
class NodeKeys {
  static final SodiumFFI _sodium = SodiumFFI();
  /// liboqs handle. `init()` is idempotent and is applied here for the same
  /// reason `DeviceKemKeyPair.generate()` applies it
  /// (lib/core/crypto/device_kem.dart:152): the ML-KEM path must not depend on
  /// some other subsystem having initialised the singleton first.
  static final OqsFFI _oqs = OqsFFI()..init();

  // ===========================================================================
  // On-disk container
  // ===========================================================================

  /// On-disk filename stem (relative to the profile directory). The `.enc`
  /// suffix is appended by [FileEncryption.writeBinaryFile], which yields
  /// exactly the `node_keys.enc` named in §3.5.2.
  static const String filenameStem = 'node_keys';

  /// Container magic — ASCII "CLNK" (Cleona Node Keys). Same role as the
  /// "CLDK" magic of `device_keys.bin.enc`: it separates a versioned container
  /// from anything else that might end up under this path.
  static const List<int> _magic = [0x43, 0x4C, 0x4E, 0x4B];

  /// Current container format version.
  static const int containerVersion = 2;

  /// `L_node` length: 32 B (§2.6).
  static const int lNodeLength = 32;

  /// Ed25519 public key length of `E_node`.
  static const int eNodePublicLength = cryptoSignPublicKeyBytes; // 32

  /// Ed25519 secret key length of `E_node`.
  static const int eNodeSecretLength = cryptoSignSecretKeyBytes; // 64

  /// Static node X25519 public key length (32 B, E-82).
  static const int nX25519PublicLength = 32;

  /// Static node X25519 secret key length (32 B).
  static const int nX25519SecretLength = 32;

  /// Static node ML-KEM-768 public key length (1,184 B, E-82).
  static const int nMlKemPublicLength = OqsFFI.mlKemPublicKeyLength; // 1184

  /// Static node ML-KEM-768 secret key length (2,400 B, E-82).
  static const int nMlKemSecretLength = OqsFFI.mlKemSecretKeyLength; // 2400

  /// Overlap window after an explicit [rotate]: the **previous** `L_node`
  /// stays accepted for **30 days** (E-81, decision 3). That covers entry
  /// records (6 h) and entry caches completely. It does **not** cover
  /// ContactSeeds with 90-day or unlimited validity — that residue is accepted
  /// deliberately and noted in §8.3.3.
  static const Duration previousLNodeOverlap = Duration(days: 30);

  /// Byte offsets are implied by this field order; see [_encode].
  static const int _containerLength = 4 // magic
      +
      4 // version (u32 LE)
      +
      lNodeLength +
      eNodePublicLength +
      eNodeSecretLength +
      nX25519PublicLength +
      nX25519SecretLength +
      nMlKemPublicLength +
      nMlKemSecretLength +
      1 // hasPrevious flag
      +
      lNodeLength // previous L_node (zeroed when absent)
      +
      8 // previousLNodeValidUntil, i64 LE, ms since epoch (0 when absent)
      +
      // v2: the previous STATIC key set. It has to be kept, because a peer
      // holding an entry record from before the rotation dials the old keys
      // — the responder must still be able to decapsulate with them for as
      // long as the overlap window is open. Zeroed when absent.
      eNodePublicLength +
      eNodeSecretLength +
      nX25519PublicLength +
      nX25519SecretLength +
      nMlKemPublicLength +
      nMlKemSecretLength;

  // ===========================================================================
  // Fields
  // ===========================================================================

  /// `L_node` — the 32-byte per-node entry secret (§2.6, E-58). Delivered
  /// exclusively together with an address: in the entry record of the
  /// rendezvous (§4.8), in ContactSeed and entry hints (§8.5), and in cached
  /// entry entries from the last run.
  final Uint8List lNode;

  /// `E_node` public key — the issuer of the entry record (§4.5). Ed25519-only
  /// is deliberate: a forged record costs the reader one failed handshake
  /// attempt, grants no access and outlives nothing.
  final Uint8List eNodePublic;

  /// `E_node` secret key (Ed25519, 64 B).
  final Uint8List eNodeSecret;

  /// Static node X25519 public key (E-82). Travels in the entry record; the
  /// initiator derives `k_prov` against it.
  final Uint8List nX25519Public;

  /// Static node X25519 secret key (E-82).
  final Uint8List nX25519Secret;

  /// Static node ML-KEM-768 public key (1,184 B, E-82). Travels in the entry
  /// record because it does not fit a 1,200-byte cell on the wire, and because
  /// answering a 48-byte `init` with 1,184 bytes would be a ~25x amplification
  /// lever.
  final Uint8List nMlKemPublic;

  /// Static node ML-KEM-768 secret key (2,400 B, E-82).
  final Uint8List nMlKemSecret;

  /// The `L_node` value in force before the last [rotate], or null if this node
  /// has never rotated. Still accepted until [previousLNodeValidUntil].
  Uint8List? previousLNode;

  /// End of the 30-day overlap window for [previousLNode] (E-81, decision 3).
  /// Null exactly when [previousLNode] is null.
  DateTime? previousLNodeValidUntil;

  /// The static key set in force before the last [rotate].
  ///
  /// WHY THIS HAD TO BE ADDED. Until 2026-08-22 [rotate] renewed `L_node`
  /// alone and left the static keys standing — the class said so itself. With
  /// entry records in circulation that made the rotation pointless: a
  /// collector links the old and the new position by identical static keys,
  /// so E-81 bought nothing against exactly the observer it was meant for.
  /// The keys now rotate together (§4.5, "rotated with it"), and that in turn
  /// forces this: peers still holding the pre-rotation record dial the old
  /// keys, and the responder has to answer with them until the 30-day window
  /// closes.
  Uint8List? previousENodePublic;
  Uint8List? previousENodeSecret;
  Uint8List? previousNX25519Public;
  Uint8List? previousNX25519Secret;
  Uint8List? previousNMlKemPublic;
  Uint8List? previousNMlKemSecret;

  /// True while the previous static key set must still be accepted.
  bool previousStaticUsable({DateTime? now}) {
    final until = previousLNodeValidUntil;
    if (until == null || previousNMlKemSecret == null) return false;
    return (now ?? DateTime.now()).isBefore(until);
  }


  NodeKeys({
    required this.lNode,
    required this.eNodePublic,
    required this.eNodeSecret,
    required this.nX25519Public,
    required this.nX25519Secret,
    required this.nMlKemPublic,
    required this.nMlKemSecret,
    this.previousLNode,
    this.previousLNodeValidUntil,
    this.previousENodePublic,
    this.previousENodeSecret,
    this.previousNX25519Public,
    this.previousNX25519Secret,
    this.previousNMlKemPublic,
    this.previousNMlKemSecret,
  }) {
    _checkLength('lNode', lNode, lNodeLength);
    _checkLength('eNodePublic', eNodePublic, eNodePublicLength);
    _checkLength('eNodeSecret', eNodeSecret, eNodeSecretLength);
    _checkLength('nX25519Public', nX25519Public, nX25519PublicLength);
    _checkLength('nX25519Secret', nX25519Secret, nX25519SecretLength);
    _checkLength('nMlKemPublic', nMlKemPublic, nMlKemPublicLength);
    _checkLength('nMlKemSecret', nMlKemSecret, nMlKemSecretLength);
    final prev = previousLNode;
    if (prev != null) {
      _checkLength('previousLNode', prev, lNodeLength);
      if (previousLNodeValidUntil == null) {
        throw ArgumentError(
            'NodeKeys: previousLNode without previousLNodeValidUntil — the '
            '30-day window of E-81 would have no end');
      }
    } else if (previousLNodeValidUntil != null) {
      throw ArgumentError(
          'NodeKeys: previousLNodeValidUntil without previousLNode');
    }
  }

  static void _checkLength(String name, Uint8List value, int expected) {
    if (value.length != expected) {
      throw ArgumentError(
          'NodeKeys: $name must be $expected bytes, got ${value.length}');
    }
  }

  /// Domain separation string of the position derivation.
  static const String lNodeDomain = 'cleona/lnode/v1';

  /// Derives `L_node` from the three static node keys (decided 2026-08-22).
  ///
  /// WHY THIS EXISTS AT ALL. `L_node` used to be `randomBytes` — a number a
  /// node simply asserted. It is used as the HMAC key of the init MAC, which
  /// proves knowledge of a value that is public anyway, and it is the metric
  /// position from which relay responsibility is computed (§9.1). Nothing
  /// bound it to the keys that actually hold the position. Consequence:
  /// whoever answered an entry request DECIDED which keys a requester would
  /// associate with a position — impersonation of any position, without
  /// owning it. That is strictly cheaper than the Sybil grind M6 prices, and
  /// it invalidated §10.2 outright.
  ///
  /// Binding the position to the keys makes an entry record
  /// **self-certifying**: recompute the hash over the three public keys in
  /// the record and compare. A substituted key yields a different position.
  ///
  /// WHY THIS DOES NOT REINTRODUCE A PERMANENT PSEUDONYM. §9.1 rejected a
  /// *stable, identity-derived* position, because it would undo the `L_node`
  /// rotation of E-81. This derivation is not identity-derived — no
  /// `user_id`, no `device_id`, no master seed enters it (§4.5) — and it is
  /// not stable: [rotate] renews all three keys, so the position moves with
  /// them. The two properties that were previously in tension are now the
  /// same property.
  static Uint8List computeLNode({
    required Uint8List eNodePublic,
    required Uint8List nX25519Public,
    required Uint8List nMlKemPublic,
  }) {
    final domain = Uint8List.fromList(utf8.encode(lNodeDomain));
    final buf = Uint8List(domain.length +
        eNodePublic.length +
        nX25519Public.length +
        nMlKemPublic.length);
    var o = 0;
    buf.setRange(o, o += domain.length, domain);
    buf.setRange(o, o += eNodePublic.length, eNodePublic);
    buf.setRange(o, o += nX25519Public.length, nX25519Public);
    buf.setRange(o, o + nMlKemPublic.length, nMlKemPublic);
    return _sodium.sha256(buf);
  }

  /// True when [claimed] is the position these three public keys produce.
  ///
  /// This is the check that makes a third-party entry record usable at all.
  static bool verifyPosition({
    required Uint8List claimed,
    required Uint8List eNodePublic,
    required Uint8List nX25519Public,
    required Uint8List nMlKemPublic,
  }) {
    if (claimed.length != lNodeLength) return false;
    final want = computeLNode(
        eNodePublic: eNodePublic,
        nX25519Public: nX25519Public,
        nMlKemPublic: nMlKemPublic);
    var diff = 0;
    for (var i = 0; i < lNodeLength; i++) {
      diff |= claimed[i] ^ want[i];
    }
    return diff == 0;
  }

  /// Length of the v1 container — kept so an existing file can still be read.
  static const int _containerLengthV1 = 4 +
      4 +
      lNodeLength +
      eNodePublicLength +
      eNodeSecretLength +
      nX25519PublicLength +
      nX25519SecretLength +
      nMlKemPublicLength +
      nMlKemSecretLength +
      1 +
      lNodeLength +
      8;

  /// Reads a v1 container and recomputes the position from its keys.
  static NodeKeys _decodeV1(Uint8List bytes) {
    var off = 8;
    Uint8List take(int n) {
      final slice =
          Uint8List.fromList(Uint8List.sublistView(bytes, off, off + n));
      off += n;
      return slice;
    }

    take(lNodeLength); // the old, asserted position — deliberately discarded
    final eNodePublic = take(eNodePublicLength);
    final eNodeSecret = take(eNodeSecretLength);
    final nX25519Public = take(nX25519PublicLength);
    final nX25519Secret = take(nX25519SecretLength);
    final nMlKemPublic = take(nMlKemPublicLength);
    final nMlKemSecret = take(nMlKemSecretLength);
    return NodeKeys(
      lNode: computeLNode(
          eNodePublic: eNodePublic,
          nX25519Public: nX25519Public,
          nMlKemPublic: nMlKemPublic),
      eNodePublic: eNodePublic,
      eNodeSecret: eNodeSecret,
      nX25519Public: nX25519Public,
      nX25519Secret: nX25519Secret,
      nMlKemPublic: nMlKemPublic,
      nMlKemSecret: nMlKemSecret,
    );
  }

  // ===========================================================================
  // Generation
  // ===========================================================================

  /// Generates a complete, fresh set of node keys from the OS CSPRNG.
  ///
  /// Every part is generated independently — none of this is derived from the
  /// master seed. That is the point: the entry record must stay identity-free
  /// (§4.5), and node keys survive an identity being deleted.
  static NodeKeys generate() {
    final ed = _sodium.generateEd25519KeyPair();
    final x = _sodium.generateX25519KeyPair();
    final kem = _oqs.mlKemKeypair();
    return NodeKeys(
      lNode: computeLNode(
          eNodePublic: ed.publicKey,
          nX25519Public: x.publicKey,
          nMlKemPublic: kem.publicKey),
      eNodePublic: ed.publicKey,
      eNodeSecret: ed.secretKey,
      nX25519Public: x.publicKey,
      nX25519Secret: x.secretKey,
      nMlKemPublic: kem.publicKey,
      nMlKemSecret: kem.secretKey,
    );
  }

  // ===========================================================================
  // Persistence (E-81)
  // ===========================================================================

  /// Loads the node keys from `<baseDir>/node_keys.enc`, or generates and
  /// persists a fresh set when the file does not exist yet.
  ///
  /// **This is the substance of E-81.** Without it, every restart would
  /// silently invalidate all outstanding entry records and every ContactSeed in
  /// circulation, because a wrong `L_node` produces no answer and no error.
  ///
  /// [baseDir] is the **profile root** — the level at which `device_keys.enc`
  /// lives, deliberately **outside** `identities/` (§3.5.2). The parameter is
  /// not called `profileDir` on purpose: elsewhere in this codebase that name
  /// denotes the directory of a *single identity*
  /// (`identity_manager.dart`: `'$baseDir/identities/$id'`), and a caller
  /// following that convention would end up with one `L_node` **per identity**
  /// — which is exactly what §2.6 ("per-node") and §4.5 (identity-free entry
  /// record) forbid.
  ///
  /// [fileEnc] is **required**, with no default. Making it required removed
  /// the former `?? FileEncryption(baseDir: …)` default, whose keyless form
  /// is the **legacy** path of `file_encryption.dart` — a random key in
  /// `db.key`, neither derived nor recoverable. Structurally impossible now
  /// instead of merely discouraged.
  ///
  /// **Where the envelope key comes from (D-4, settled S362).**
  /// `HdWallet.deriveSharedFileEncKey(masterSeed)` — the daemon-global,
  /// seed-recoverable key, the same one under which the sibling artefact
  /// `device_keys.bin.enc` already sits (`identity_context.dart:407-409`).
  /// The three production call sites build exactly that
  /// (`service_daemon.dart`, `main.dart`,
  /// `core/platform/ios_background_fetch.dart`).
  ///
  /// The guard for this file encodes the same choice: the "good" reference
  /// sample in `test/smoke/smoke_link_node_keys_scope_guard.dart` is
  /// `HdWallet.deriveSharedFileEncKey(masterSeed)` +
  /// `FileEncryption(baseDir: baseDir, key: sharedKey)`.
  ///
  /// An earlier V1-era prescription here derived the envelope key from the
  /// device-sig key instead. **Owner's decision, 02.09.2026: it has no place
  /// in V4.1 and is gone.** Do not reintroduce it — it was never built
  /// (`cleona-field-index-v1` exists nowhere in `lib/`), so the call sites
  /// fell through to the keyless `db.key` it was meant to avoid.
  ///
  /// **The seedless case is unchanged and still open.** With no master
  /// seed the call sites pass `null` and this file falls back to `db.key`,
  /// exactly as `device_keys.bin.enc` does beside it. Closing that needs a
  /// device-bound keyring, not a different derivation — the same open
  /// question `identities.json` raises (S362 report, section 4.1).
  /// Seed recoverability, incidentally, is irrelevant either way:
  /// `node_keys.enc` has to survive a **restart** (E-81), not a change of
  /// device.
  ///
  /// Fail-loud, mirroring `DeviceKeysStore`: if the `.enc` file exists but
  /// cannot be decrypted or does not parse, this throws instead of generating
  /// a new set. Silently regenerating would rotate `L_node` behind the user's
  /// back, which is the exact silent outage E-81 forbids.
  static Future<NodeKeys> loadOrCreate(String baseDir,
      {required FileEncryption fileEnc}) async {
    final enc = fileEnc;
    final path = '$baseDir/$filenameStem';
    final encFile = File('$path.enc');

    final existing = enc.readBinaryFile(path);
    if (existing != null) {
      try {
        return _decode(existing);
      } finally {
        SecureMemory.zero(existing);
      }
    }

    if (encFile.existsSync()) {
      // ── S362 DEFENCE-IN-DEPTH: THE LEGACY ENVELOPE, ONCE ─────────────
      //
      // Until S362 this container was sealed with the random `db.key`
      // (the keyless `FileEncryption` the three call sites used to build).
      // `KeyMigration.migrateDeviceScopedFiles` moves it to the derived
      // key at startup, and `IdentityContext.initCrypto` calls that — but
      // not every entry point goes through `initCrypto`: on Linux and
      // Windows `main.dart` skips it deliberately ("daemon owns the
      // keyring"), and `ios_background_fetch.dart` never calls it at all.
      //
      // WITHOUT THIS BRANCH the consequence of a missed migration is not a
      // background inconvenience but a DEAD START: the throw below is
      // correct for a genuinely unreadable container, and it would fire on
      // a container that is merely still in its old envelope. So: try the
      // legacy key once, and if it opens, re-seal under the caller's key
      // immediately — the same S106 pattern `DeviceKeysStore.loadOrCreate`
      // already uses for `device_keys.bin.enc`.
      //
      // The legacy key is only ever READ, never created: a keyless
      // `FileEncryption` would mint a fresh random `db.key` here and then
      // fail to decrypt anyway, leaving a misleading file behind.
      final legacyKey = FileEncryption.legacyKeyBytes(baseDir);
      if (legacyKey != null) {
        final legacyEnc = FileEncryption(baseDir: baseDir, key: legacyKey);
        final rescued = legacyEnc.readBinaryFile(path);
        if (rescued != null) {
          NodeKeys recovered;
          try {
            recovered = _decode(rescued);
          } finally {
            SecureMemory.zero(rescued);
          }
          recovered.persist(baseDir, fileEnc: enc);
          stderr.writeln('[NodeKeys] INFO: $path.enc was still under the '
              'legacy db.key envelope — re-sealed with the caller key.');
          return recovered;
        }
      }
      throw NodeKeysException(
          '$path.enc exists (${encFile.lengthSync()} bytes) but cannot be '
          'decrypted with the caller key or the legacy db.key — will NOT '
          'regenerate (a fresh L_node would silently invalidate every '
          'outstanding entry record and ContactSeed, E-81)');
    }

    final fresh = generate();
    fresh.persist(baseDir, fileEnc: enc);
    return fresh;
  }

  // ── `_legacyKeyBytes` — REMOVED ON 08.09.2026 (S376) ─────────────
  //
  // The header justified the copy by saying this class must not
  // depend on the migration module. That is true — only the copy was
  // not needed for it: the same reader has been in
  // `FileEncryption.legacyKeyBytes` since S368, and this file imports
  // `file_encryption.dart` anyway (l. 40). The justification thus
  // protected a dependency that did not exist at all, and paid for it
  // with a second list of legacy key file names.

  /// Writes this set to `<baseDir>/node_keys.enc`, atomically (tmp+rename,
  /// courtesy of [FileEncryption.writeBinaryFile]).
  ///
  /// Call this after [rotate] — [rotate] itself touches no disk, so that the
  /// caller decides when the new value becomes the persisted one.
  ///
  /// [baseDir] and [fileEnc] carry the same contract as in [loadOrCreate]:
  /// the profile **root**, not an identity directory, and the daemon-global
  /// seed-derived envelope. `fileEnc` is required here for the same reason —
  /// a keyless default would write the container under a random `db.key`, and
  /// a `persist` that disagrees with `loadOrCreate` about the key produces
  /// precisely the undecryptable-but-present file that the fail-loud branch
  /// above then refuses to recover from.
  void persist(String baseDir, {required FileEncryption fileEnc}) {
    final enc = fileEnc;
    final blob = _encode();
    try {
      enc.writeBinaryFile('$baseDir/$filenameStem', blob);
    } finally {
      // The container holds three secret keys in the clear; wipe the transient
      // buffer as soon as the envelope has been written (house pattern, cf.
      // per_message_kem.dart).
      SecureMemory.zero(blob);
    }
  }

  // ===========================================================================
  // Rotation (E-81) — explicit act only, never a timer
  // ===========================================================================

  /// Returns a new [NodeKeys] with a freshly drawn `L_node`; the current value
  /// moves to [previousLNode] and stays accepted until `now + 30 days`.
  ///
  /// **Rotation is an explicit act — suspected compromise, profile reset —
  /// never a timer (E-81).** Deliberately, there is no scheduler, no timestamp
  /// of last rotation and no age check anywhere in this class:
  ///
  /// - `L_node` is an **entry secret, not a session key**. Rotating it has no
  ///   forward-secrecy effect, because confidentiality hangs on `link_key`
  ///   (§2.6) — so a timer buys nothing on the security side.
  /// - What a timer *does* buy, reliably, is a **silent outage** for every
  ///   holder of a longer-lived carrier: entry records (6 h), entry caches, and
  ///   above all ContactSeeds (up to 90 days, optionally unlimited). A wrong
  ///   `L_node` produces no answer and no error, so the failure is invisible on
  ///   both sides.
  ///
  /// The 30-day overlap covers entry records and caches completely. It does
  /// **not** cover 90-day or unlimited ContactSeeds; that residue is a
  /// deliberate acceptance recorded in §8.3.3, together with its asymmetry —
  /// an expired invitation raises an explicit error, a dead `L_node` only
  /// silence.
  ///
  /// Scope note: only `L_node` is rotated here. `E_node` and the static node
  /// KEM pair are untouched by this method — see the class-level report of
  /// AP-3a stage 2 and §4.5 ("rotated with it"), for which no overlap rule
  /// exists in the specification.
  NodeKeys rotate({DateTime? now}) {
    final at = now ?? DateTime.now();
    final ed = _sodium.generateEd25519KeyPair();
    final x = _sodium.generateX25519KeyPair();
    final kem = _oqs.mlKemKeypair();
    return NodeKeys(
      lNode: computeLNode(
          eNodePublic: ed.publicKey,
          nX25519Public: x.publicKey,
          nMlKemPublic: kem.publicKey),
      eNodePublic: ed.publicKey,
      eNodeSecret: ed.secretKey,
      nX25519Public: x.publicKey,
      nX25519Secret: x.secretKey,
      nMlKemPublic: kem.publicKey,
      nMlKemSecret: kem.secretKey,
      previousLNode: Uint8List.fromList(lNode),
      previousLNodeValidUntil: at.add(previousLNodeOverlap),
      previousENodePublic: Uint8List.fromList(eNodePublic),
      previousENodeSecret: Uint8List.fromList(eNodeSecret),
      previousNX25519Public: Uint8List.fromList(nX25519Public),
      previousNX25519Secret: Uint8List.fromList(nX25519Secret),
      previousNMlKemPublic: Uint8List.fromList(nMlKemPublic),
      previousNMlKemSecret: Uint8List.fromList(nMlKemSecret),
    );
  }

  /// True when [candidate] is this node's current `L_node`, or — while the
  /// 30-day window of E-81 is still open — the value in force before the last
  /// [rotate].
  ///
  /// [now] is injectable so the window boundary is testable; production callers
  /// omit it. Comparison is constant-time in both branches: `L_node` is a MAC
  /// key, and a length- or content-dependent timing difference would hand a
  /// prober exactly the signal E-58 removes.
  bool acceptsLNode(Uint8List candidate, {DateTime? now}) {
    if (candidate.length != lNodeLength) return false;
    if (_constantTimeEquals(candidate, lNode)) return true;

    final prev = previousLNode;
    final until = previousLNodeValidUntil;
    if (prev == null || until == null) return false;
    final at = now ?? DateTime.now();
    // Window is closed at and after `until` — `until` itself is the first
    // instant that no longer accepts.
    if (!at.isBefore(until)) return false;
    return _constantTimeEquals(candidate, prev);
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ===========================================================================
  // Container encoding
  // ===========================================================================
  //
  // v1 layout (fixed length, no optional parts):
  //
  //   [4B   magic "CLNK"]
  //   [4B   u32 LE version = 1]
  //   [32B  L_node]
  //   [32B  E_node Ed25519 public]
  //   [64B  E_node Ed25519 secret]
  //   [32B  N_x25519 public]
  //   [32B  N_x25519 secret]
  //   [1184B N_mlkem public]
  //   [2400B N_mlkem secret]
  //   [1B   hasPrevious: 0 or 1]
  //   [32B  previous L_node (all-zero when hasPrevious == 0)]
  //   [8B   i64 LE previousLNodeValidUntil, ms since epoch (0 when absent)]
  //
  // Fixed width throughout, so the container length alone identifies the
  // version alongside the magic.

  Uint8List _encode() {
    final out = Uint8List(_containerLength);
    var off = 0;
    out.setRange(off, off + 4, _magic);
    off += 4;
    final header = ByteData.sublistView(out, off, off + 4);
    header.setUint32(0, containerVersion, Endian.little);
    off += 4;
    off = _put(out, off, lNode);
    off = _put(out, off, eNodePublic);
    off = _put(out, off, eNodeSecret);
    off = _put(out, off, nX25519Public);
    off = _put(out, off, nX25519Secret);
    off = _put(out, off, nMlKemPublic);
    off = _put(out, off, nMlKemSecret);

    final prev = previousLNode;
    final until = previousLNodeValidUntil;
    out[off] = prev != null ? 1 : 0;
    off += 1;
    if (prev != null) {
      out.setRange(off, off + lNodeLength, prev);
    }
    off += lNodeLength;
    ByteData.sublistView(out, off, off + 8).setInt64(
        0, until != null ? until.millisecondsSinceEpoch : 0, Endian.little);
    off += 8;

    // v2: the previous static key set, zeroed when absent. Fixed width, so
    // the container length still identifies the version on its own.
    off = _putOrZero(out, off, previousENodePublic, eNodePublicLength);
    off = _putOrZero(out, off, previousENodeSecret, eNodeSecretLength);
    off = _putOrZero(out, off, previousNX25519Public, nX25519PublicLength);
    off = _putOrZero(out, off, previousNX25519Secret, nX25519SecretLength);
    off = _putOrZero(out, off, previousNMlKemPublic, nMlKemPublicLength);
    off = _putOrZero(out, off, previousNMlKemSecret, nMlKemSecretLength);

    if (off != _containerLength) {
      throw NodeKeysException(
          'encode length mismatch: wrote $off, expected $_containerLength');
    }
    return out;
  }

  static int _putOrZero(
      Uint8List out, int off, Uint8List? value, int length) {
    if (value != null) out.setRange(off, off + length, value);
    return off + length;
  }

  static int _put(Uint8List out, int off, Uint8List value) {
    out.setRange(off, off + value.length, value);
    return off + value.length;
  }

  static NodeKeys _decode(Uint8List bytes) {
    // A v1 container is shorter and carries a RANDOM `L_node`. It is read,
    // and the position is recomputed from the keys it holds — a v1 node
    // would otherwise present a record that every peer rightly rejects,
    // because the position it claims is not the one its keys produce. The
    // position therefore moves once on upgrade; that is a rotation, and the
    // node loses the cells it held for its former neighbourhood (§9.1).
    if (bytes.length == _containerLengthV1) {
      return _decodeV1(bytes);
    }
    if (bytes.length != _containerLength) {
      throw NodeKeysException(
          'container length mismatch: got ${bytes.length}, expected '
          '$_containerLength');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw NodeKeysException(
            'bad container magic (expected "CLNK") at $filenameStem.enc');
      }
    }
    final version =
        ByteData.sublistView(bytes, 4, 8).getUint32(0, Endian.little);
    if (version != containerVersion && version != 1) {
      throw NodeKeysException(
          'unsupported container version $version (this build expects '
          '$containerVersion)');
    }

    var off = 8;
    Uint8List take(int n) {
      final slice = Uint8List.fromList(Uint8List.sublistView(bytes, off, off + n));
      off += n;
      return slice;
    }

    final lNode = take(lNodeLength);
    final eNodePublic = take(eNodePublicLength);
    final eNodeSecret = take(eNodeSecretLength);
    final nX25519Public = take(nX25519PublicLength);
    final nX25519Secret = take(nX25519SecretLength);
    final nMlKemPublic = take(nMlKemPublicLength);
    final nMlKemSecret = take(nMlKemSecretLength);

    final hasPrevious = bytes[off];
    off += 1;
    if (hasPrevious != 0 && hasPrevious != 1) {
      throw NodeKeysException(
          'bad hasPrevious flag $hasPrevious (expected 0 or 1)');
    }
    final prevRaw = take(lNodeLength);
    final untilMs =
        ByteData.sublistView(bytes, off, off + 8).getInt64(0, Endian.little);
    off += 8;

    final prevE = take(eNodePublicLength);
    final prevIt = take(eNodeSecretLength);
    final prevX = take(nX25519PublicLength);
    final prevXs = take(nX25519SecretLength);
    final prevK = take(nMlKemPublicLength);
    final prevKs = take(nMlKemSecretLength);

    return NodeKeys(
      lNode: lNode,
      eNodePublic: eNodePublic,
      eNodeSecret: eNodeSecret,
      nX25519Public: nX25519Public,
      nX25519Secret: nX25519Secret,
      nMlKemPublic: nMlKemPublic,
      nMlKemSecret: nMlKemSecret,
      previousLNode: hasPrevious == 1 ? prevRaw : null,
      previousLNodeValidUntil: hasPrevious == 1
          ? DateTime.fromMillisecondsSinceEpoch(untilMs)
          : null,
      previousENodePublic: hasPrevious == 1 ? prevE : null,
      previousENodeSecret: hasPrevious == 1 ? prevIt : null,
      previousNX25519Public: hasPrevious == 1 ? prevX : null,
      previousNX25519Secret: hasPrevious == 1 ? prevXs : null,
      previousNMlKemPublic: hasPrevious == 1 ? prevK : null,
      previousNMlKemSecret: hasPrevious == 1 ? prevKs : null,
    );
  }
}

/// Container-level error of `node_keys.enc` (bad magic, wrong version, wrong
/// length, undecryptable file). Distinct from [ArgumentError], which this
/// module uses for malformed in-memory key material.
class NodeKeysException implements Exception {
  final String message;
  const NodeKeysException(this.message);

  @override
  String toString() => 'NodeKeysException: $message';
}
