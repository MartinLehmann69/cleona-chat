import 'dart:convert';
import 'dart:typed_data';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/platform/app_paths.dart';

/// Signed update manifest for decentralized update checking.
///
/// ── THE MANIFEST IS HYBRID-SIGNED (v4_2 §4.4.3, §26.5.2) ──────────
///
/// §4.4.3 "Signature rule (normative)" lists the manifest in the row
/// `| Update manifest (maintainer key) | hybrid | must be verifiable by third
/// parties years later |`. §4.4.1: "the receiver checks both signatures
/// individually; acceptance requires that **both** are valid."
///
/// There are therefore TWO signatures over the same bytes ([signedPayload]):
/// [signature] (Ed25519, 64 B) and [signaturePq] (ML-DSA-65, ~3,309 B).
/// [verify] requires both. A missing, empty or wrong signature makes
/// the manifest invalid — **fail closed**, no transitional format with an
/// optional second signature. On 4.2.x there are no old manifests that
/// would still have to be valid, and a field "for older counterparts" is
/// expressly forbidden (`CLAUDE.md`, section "Linien").
///
/// Why precisely here: the manifest is the artefact with which code comes onto foreign
/// devices, and §26.5.2 justifies it in plain text — "it must still be
/// verifiable when a node catches up after months of offline time, and a
/// manifest that could be forged retroactively would be full access to every
/// installation."
///
/// **Not to be confused with [binarySignatures].** That is a DIFFERENT
/// signature over a DIFFERENT artefact (the raw SHA-256 of the
/// platform binary) and stays classical — see there.
///
/// **There is no DHT any more.** Until S372 here stood "Published to DHT under
/// key SHA-256("cleona-update-manifest")". `lib/core/dht/` does not exist on
/// this line. The hash value lives on as [manifestStoreTag] —
/// but as the key of a LOCAL storage slot
/// (`storage/mailbox_store.dart`), not as a network address. The
/// manifest is distributed according to §26.6.1: harvested during the cover stream reconciliation, not
/// queried. That this harvest has no carrier today is stated by
/// `cleona_service_update.dart` as gap G-18 in plain text.
class UpdateManifest {
  /// Current version string (semver).
  final String version;

  /// Download URL for the release.
  final String downloadUrl;

  /// SHA-256 hash of the release archive.
  final String archiveHash;

  /// Short changelog summary.
  final String changelog;

  /// Unix timestamp when this manifest was created.
  final int timestamp;

  /// Classical half of the hybrid signature: Ed25519 over
  /// [signedPayload]. Worthless without [signaturePq] — [verify] requires both.
  final Uint8List signature;

  /// Post-quantum half of the hybrid signature: ML-DSA-65 over THE SAME
  /// bytes as [signature] ([signedPayload]). §4.4.3 lists the manifest as
  /// `hybrid`; §4.4.1 requires that both signatures are checked individually
  /// and that **both** must be valid.
  ///
  /// Mandatory field, not `Uint8List?`: a manifest without a PQ signature is no
  /// valid 4.2 manifest, and a nullable field would be exactly the
  /// transitional form that CLAUDE.md ("Linien") forbids. [fromJson] returns
  /// `null` if `sigPq` is missing.
  final Uint8List signaturePq;

  /// NEW (V3.1.72): if set, clients with `appVersion < minRequiredVersion` are hard-blocked.
  /// Null on legacy manifests.
  final String? minRequiredVersion;

  /// NEW (V3.1.72): i18n key for the hard-block reason text.
  /// Null on legacy manifests.
  final String? minRequiredReason;

  /// Presence marker per platform — **not a lookup key**.
  ///
  /// Keys: linux, windows, android, macos, ios. Null on old manifests.
  ///
  /// ── WHAT STOOD HERE UNTIL S372, AND WHY IT WAS MISLEADING ──────
  ///
  /// "per-platform DHT lookup tag for erasure-coded binary fragments".
  /// Both is wrong. There is no DHT on this line
  /// (`lib/core/dht/` does not exist), and there is no lookup either:
  /// **the value is evaluated nowhere.** Re-measured on
  /// 06.09.2026 over the complete call set — `BinaryUpdateManager`
  /// checks `tag == null`, `cleona_service_update.dart` checks `containsKey` at two
  /// places. No reader ever reads the content. The pipeline
  /// accordingly writes a placeholder: `release-build.sh` calls
  /// `sign-update-manifest.sh … --dht-tag 1`, i.e. the digit `1` for
  /// every platform.
  ///
  /// ── WHERE THE REAL COLLECTION ANCHOR LIES ─────────────────────────────────
  ///
  /// At `binaryTransferRoot` (`lib/core/update/binary_fountain.dart`):
  /// `HKDF(netzgeheimnis, "update/root/" ‖ hex(binaryHash))`. It follows from
  /// [binaryHashes] and the network secret, not from this field. Whoever looks for
  /// a tag here looks in the wrong place — that is why the
  /// reference stands at the declaration and not merely in a session report.
  ///
  /// What the field still achieves today: it says "for this platform there is
  /// an in-network distribution". Exactly that, and only that.
  final Map<String, String>? binaryTag;

  /// Per platform a mapping source version -> tag of the delta blob
  /// (§26.6.2). Null on old manifests — and currently ALWAYS null: neither
  /// does `scripts/sign-update-manifest.sh` produce the field (the payload position
  /// stays empty), nor could a receiver do anything with it
  /// as long as `DeltaUpdateManager.applyDelta` without `libcleona_bsdiff`
  /// returns `null`. The same remark as with [binaryTag]: a tag,
  /// not a lookup.
  final Map<String, Map<String, String>>? deltaBinaryTag;

  /// NEW (§19.6): monotonically increasing sequence number for downgrade protection.
  /// Null on legacy manifests.
  final int? minMonotoneSeq;

  /// NEW (§19.6.2): per-platform SHA-256 hash (hex) of the release binary.
  /// This is the trust anchor an in-network downloader verifies the
  /// assembled/reconstructed binary against — see
  /// [BinaryUpdateManager.verify]. Null on legacy manifests or manifests
  /// without in-network distribution.
  final Map<String, String>? binaryHashes;

  /// NEW (§19.6.2): per-platform Ed25519 signature (base64) by the
  /// maintainer key over the raw 32-byte SHA-256 hash of that platform's
  /// binary (same scheme as `PhysicalTransferHelper.importAndVerifyBinary`
  /// / `InviteLink`). Independent of [signature] (which covers the manifest
  /// payload as a whole) so the binary itself carries its own portable proof
  /// of authenticity. Null on legacy manifests.
  ///
  /// -- STAYS CLASSICAL, AND WHY (S389) ------------------------------
  ///
  /// §4.4.3 lists in its table the **Update manifest** as `hybrid` —
  /// this field is a different artefact and does not stand there. The
  /// trust anchor of the binary is [binaryHashes]: this hash lies IN the
  /// hybrid-signed payload ([signedPayload] interpolates
  /// `jsonEncode(binaryHashes)`), is thus post-quantum-covered, and
  /// `BinaryUpdateManager.verify` checks the assembled binary against
  /// it. The signature here is the PORTABLE additional proof for the paths
  /// WITHOUT a manifest — invitation link, physical handover, the browser page
  /// from `bootstrap_web_app.dart`.
  ///
  /// Making it hybrid is not buildable today: the consumer of the
  /// browser page is browser JavaScript (`bootstrap_web_app.dart:997-1005`,
  /// `ed25519Verify` in pure JS), and there is no ML-DSA-65 there. A
  /// second field that part of the consumers cannot check would be
  /// exactly the transitional form that CLAUDE.md forbids. The finding is
  /// named with its price in the session report `mycelium/berichte/S389-BAU-MANIFEST.md`,
  /// not silently decided here.
  final Map<String, String>? binarySignatures;

  /// NEW (§19.6.2): per-platform exact byte size of the unpadded release
  /// binary, required to truncate the Reed-Solomon reconstruction back to
  /// the original binary (erasure-coded fragments are padded to a multiple
  /// of K). Null on legacy manifests.
  final Map<String, int>? binarySizes;

  /// S387, D1 (§26.6.2): per platform and source version the SHA-256 (hex) of the
  /// bsdiff delta. Without hash and length a node can neither derive the
  /// key of the delta nor recognise when it is complete.
  final Map<String, Map<String, String>>? deltaHashes;

  /// S387, D1: per platform and source version the length of the delta.
  final Map<String, Map<String, int>>? deltaSizes;

  UpdateManifest({
    required this.version,
    required this.downloadUrl,
    required this.archiveHash,
    required this.changelog,
    required this.timestamp,
    required this.signature,
    required this.signaturePq,
    this.minRequiredVersion,
    this.minRequiredReason,
    this.binaryTag,
    this.deltaBinaryTag,
    this.minMonotoneSeq,
    this.binaryHashes,
    this.binarySignatures,
    this.binarySizes,
    this.deltaHashes,
    this.deltaSizes,
  });

  /// Payload to sign. Legacy format (no new fields) preserved when all new
  /// fields are null — keeps old manifests verifiable. When new fields are
  /// set, they are appended to the payload.
  String get signedPayload {
    final base = '$version\n$downloadUrl\n$archiveHash\n$changelog\n$timestamp';
    final withDelta = deltaHashes != null || deltaSizes != null;
    if (minRequiredVersion == null && minRequiredReason == null &&
        binaryTag == null && deltaBinaryTag == null && minMonotoneSeq == null &&
        binaryHashes == null && binarySignatures == null && binarySizes == null &&
        !withDelta) {
      return base;
    }
    var payload = '$base\n${minRequiredVersion ?? ''}\n${minRequiredReason ?? ''}';
    if (binaryTag != null || deltaBinaryTag != null || minMonotoneSeq != null ||
        binaryHashes != null || binarySignatures != null || binarySizes != null ||
        withDelta) {
      payload += '\n${binaryTag != null ? jsonEncode(binaryTag) : ''}'
          '\n${deltaBinaryTag != null ? jsonEncode(deltaBinaryTag) : ''}'
          '\n${minMonotoneSeq ?? ''}'
          '\n${binaryHashes != null ? jsonEncode(binaryHashes) : ''}'
          '\n${binarySignatures != null ? jsonEncode(binarySignatures) : ''}'
          '\n${binarySizes != null ? jsonEncode(binarySizes) : ''}';
      // S387, D1: hash and length of the deltas are appended at the end — only if
      // there are any, so that a manifest without delta signs the same bytes
      // as before (`scripts/sign-update-manifest.sh` likewise).
      if (withDelta) {
        payload += '\n${deltaHashes != null ? jsonEncode(deltaHashes) : ''}'
            '\n${deltaSizes != null ? jsonEncode(deltaSizes) : ''}';
      }
    }
    return payload;
  }

  /// Checks the hybrid signature of the manifest (§4.4.3, §4.4.1).
  ///
  /// **Both** signatures must be valid. It is deliberately NOT
  /// short-circuited (`&&` only after both calls): thus every
  /// check enters each of the two paths, and a mutation that removes one of the two
  /// calls is visible in a probe instead of hiding behind the
  /// already failed first branch. No timing channel arises
  /// from this — both inputs are public.
  ///
  /// If one of the two checks throws (wrong key length, too long
  /// signature, liboqs not loadable), the result is `false`: **fail
  /// closed**. A manifest that COULD not be completely checked
  /// never counts as checked.
  bool verify(
    Uint8List maintainerEd25519PublicKey,
    Uint8List maintainerMlDsaPublicKey,
  ) {
    try {
      final message = Uint8List.fromList(utf8.encode(signedPayload));
      final classic = SodiumFFI()
          .verifyEd25519(message, signature, maintainerEd25519PublicKey);
      // liboqs only binds after `init()`; without the call
      // `mlDsaVerify` throws `StateError` and the `catch` below would turn it into a
      // silent "signature invalid". The call is harmless
      // (`init()` returns immediately if already bound) and necessary,
      // because the manifest check can be the EARLIEST PQ path of a process:
      // `main.dart:268` checks the cached manifest at
      // start, a tool or a probe has not done the binding at all.
      // The same pattern as `mycelium/lib/envelope.dart`.
      OqsFFI().init();
      final postQuantum = OqsFFI()
          .mlDsaVerify(message, signaturePq, maintainerMlDsaPublicKey);
      return classic && postQuantum;
    } catch (e) {
      return false;
    }
  }

  /// Serialises the manifest as JSON (file, storage slot, release asset).
  ///
  /// ── THE JSON KEYS ARE FROZEN ───────────────────────────
  ///
  /// Especially `'dhtBin'`. The DART identifier has been called
  /// [binaryTag] since S372, the WIRE key stays `dhtBin` — deliberately, with a
  /// calculated price:
  ///
  ///   * The SIGNATURE is untouched by both. [signedPayload]
  ///     interpolates exclusively VALUES; neither the Dart identifier nor
  ///     the JSON key ever stands in the signed bytes.
  ///     `scripts/sign-update-manifest.sh` builds the same string from
  ///     the same values. Recalculated on 06.09.2026 against both sides:
  ///     identical, and neither of the two strings contains
  ///     "dhtBinaryTag" or "dhtBin".
  ///   * The KEY on the other hand is wire. It is written by
  ///     `scripts/sign-update-manifest.sh` and read by
  ///     `scripts/verify-release.sh`, `scripts/release-build.sh`, by
  ///     [fromJson] — and by every already published manifest
  ///     together with the `update_manifest_cache.json` on the devices in the field.
  ///     Renaming it would need a double reader across two releases,
  ///     for a field whose value nobody evaluates (see [binaryTag]).
  ///
  /// Whoever changes a key here changes the critical
  /// update click path — `project_android_update_flow_v145.md`.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'v': version,
      'url': downloadUrl,
      'hash': archiveHash,
      'log': changelog,
      'ts': timestamp,
      'sig': base64Encode(signature),
      // §4.4.3: the second half of the hybrid signature. New wire
      // key — the remaining keys stay frozen (above).
      'sigPq': base64Encode(signaturePq),
    };
    if (minRequiredVersion != null) json['minReq'] = minRequiredVersion;
    if (minRequiredReason != null) json['minReqReason'] = minRequiredReason;
    if (binaryTag != null) json['dhtBin'] = binaryTag;
    if (deltaBinaryTag != null) json['deltaBin'] = deltaBinaryTag;
    if (minMonotoneSeq != null) json['monotoneSeq'] = minMonotoneSeq;
    if (binaryHashes != null) json['binHash'] = binaryHashes;
    if (binarySignatures != null) json['binSig'] = binarySignatures;
    if (binarySizes != null) json['binSize'] = binarySizes;
    if (deltaHashes != null) json['deltaHash'] = deltaHashes;
    if (deltaSizes != null) json['deltaSize'] = deltaSizes;
    return json;
  }

  /// Reads a manifest from its JSON. Keys frozen — see
  /// [toJson].
  static UpdateManifest? fromJson(Map<String, dynamic> json) {
    try {
      return UpdateManifest(
        version: json['v'] as String,
        downloadUrl: json['url'] as String,
        archiveHash: json['hash'] as String,
        changelog: json['log'] as String,
        timestamp: json['ts'] as int,
        signature: base64Decode(json['sig'] as String),
        // If `sigPq` is missing, the cast throws — and `fromJson` returns `null`.
        // Exactly so it should be: a manifest without a PQ signature is not
        // read, not accepted "with one signature" (§4.4.3).
        signaturePq: base64Decode(json['sigPq'] as String),
        minRequiredVersion: json['minReq'] as String?,
        minRequiredReason: json['minReqReason'] as String?,
        binaryTag: (json['dhtBin'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as String),
        ),
        deltaBinaryTag: (json['deltaBin'] as Map?)?.map(
          (k, v) => MapEntry(
            k as String,
            (v as Map).map((k2, v2) => MapEntry(k2 as String, v2 as String)),
          ),
        ),
        minMonotoneSeq: json['monotoneSeq'] as int?,
        binaryHashes: (json['binHash'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as String),
        ),
        binarySignatures: (json['binSig'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as String),
        ),
        binarySizes: (json['binSize'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as int),
        ),
        deltaHashes: (json['deltaHash'] as Map?)?.map(
          (k, v) => MapEntry(
            k as String,
            (v as Map).map((k2, v2) => MapEntry(k2 as String, v2 as String)),
          ),
        ),
        deltaSizes: (json['deltaSize'] as Map?)?.map(
          (k, v) => MapEntry(
            k as String,
            (v as Map).map((k2, v2) => MapEntry(k2 as String, v2 as int)),
          ),
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// The slot in which the manifest lies LOCALLY.
  ///
  /// Until S372 this was called `dhtKey()` and the comment "DHT key for the update
  /// manifest". The bytes are unchanged — SHA-256("cleona-update-manifest")
  /// —, but the place is a different one: `storage/mailbox_store.dart` on the
  /// own disk, no network namespace. Whoever read the old name
  /// looked for a network fetch that has not existed since the cut of 31.08.2026
  /// (gap G-18).
  static Uint8List manifestStoreTag() {
    return SodiumFFI().sha256(
      Uint8List.fromList(utf8.encode('cleona-update-manifest')),
    );
  }

  @override
  String toString() => 'UpdateManifest(v$version, $downloadUrl, ts=$timestamp, minReq=$minRequiredVersion, '
      'binTag=$binaryTag, deltaBin=$deltaBinaryTag, monotoneSeq=$minMonotoneSeq, '
      'binHash=$binaryHashes, binSize=$binarySizes)';
}

/// Checks and authenticates update manifests. Where the manifest comes from
/// is decided by the caller — this checker only sees JSON.
class UpdateChecker {
  final CLogger _log;

  /// Classical maintainer key (hex, 32 B Ed25519).
  ///
  /// Carries TWO different signatures: the classical half of the
  /// hybrid manifest signature ([UpdateManifest.signature]) and — alone —
  /// the binary signatures ([UpdateManifest.binarySignatures], invitation
  /// links, `PhysicalTransferHelper`, the browser page in
  /// `bootstrap_web_app.dart`).
  static const String maintainerPublicKeyHex =
      '8a8589febfca4e0cecc21b036621861c4595192d56cfd1f5ec6573eece932daa';

  /// Post-quantum maintainer key (hex, 1,952 B ML-DSA-65) — the second
  /// half of the hybrid manifest signature (§4.4.3, §26.5.2, §26.7).
  ///
  /// ── SET SINCE 16.09.2026 ────────────────────────────────────────────
  ///
  /// Generated with `scripts/gen-maintainer-mldsa-key.sh` on instruction of the
  /// owner; the secret part lies next to the classical key
  /// (`~/CleonaPrivat/keys/cleona_maintainer_mldsa.key`, permissions 600) and
  /// has never touched this tree. The script itself checked the signature against the
  /// public part standing here.
  ///
  /// **It does NOT REPLACE the classical key, it stands next to it.**
  /// [maintainerPublicKeyHex] has existed since V3 and still signs the
  /// binary files, the invitation links and the browser page — alone. The
  /// manifest on the other hand §4.4.3 requires to be HYBRID: an Ed25519 alone does not hold
  /// against a quantum computer, and the update signature is according to
  /// §26.7 "the one central lever in the entire system".
  ///
  /// If this value were empty, [verifyManifest] would reject EVERY manifest
  /// ([maintainerMlDsaKeyConfigured] `false`) and the check would abort
  /// before it accepts anything — better no update than one signed only
  /// classically. This direction stays; it just no longer
  /// takes effect.
  ///
  /// If the secret part is lost, no device in the field can ever accept an
  /// update again (threshold signatures are roadmap §30, not
  /// built). It must be backed up like the classical one.
  static const String maintainerMlDsaPublicKeyHex =
      'b654cafbd6c42474124e6fb1ce2f05b0f9f5f884aad5ae6e1961e2cad60145d5'
      '848b15fd3681cc11d9c9874396eef4af9aeb54a8bbebe5b131cf2d485b1aa99a'
      'a91fb549f05d32ee3f172b809d73422a384e4049f77bba58f129aba3be4ba8dd'
      'c86e8b3b8e9604f7515aef4006dfaaffd6e2200681d0e6ab86171f1a789b18aa'
      '944c933c06f922f29ffa22c49c9959cc8f5b52fabff34cdb274479f0941385a5'
      'f75b309761d885a9c9a32f899334f22da89757b4c9e4fbbe9f8c1466ed78008e'
      '865ab59d44b195e51dd9fa48fddd492c0995a41b3b4292c64ac6094e5ca01adb'
      '8d12b589f81968b807605f59518427a963b1a6d51244abe6a84c229c293b6733'
      '5262103e65eaad38fb23abdac714f24ee31435194960cf338b472a56cd576273'
      'd00b8eec3fe65c0f2092e09e865e5498d311ba023ea1c6a79d44f04f45c379c3'
      '5c4ca675a49382d0dfb332354721a9c20e82a2fb252a6aa6b1f71fd9a4d126ea'
      '41b3d5910eb13c4edc14262f2692bdf9f3dbd5d9a1879973f1595a7d976d1603'
      '776b78268c14ed67a2f028cd65e25f3a1df8356665fd3975500be0bbb8053783'
      '7f59e4297fd3a88b224f959960fd6d1534efaa0293f8b55b09e3627f665e8340'
      'c8e6c0a4401e2630844d6eae6548faae35be8ed27593df78e66491fe41b11ecc'
      '76f03ed7dea2d9e8ac2eef6d8b40567ccd643068a3864d37400ab0db4ca7c1b6'
      '0052fe77556175196a8d15ba3aca4d19d8a4cfbda4ab26dd856103795d846b3d'
      '477e464c72d23ef20b35f1ca0e9f536180e510a846dfc7bb923b9b016c568bd7'
      '7771e635a494e2e06a76645a77add75e4ee883678077bbad85478886d90fef8d'
      'e48cb5cbc0b1b26c8ed696fc82bb8c080bb540ec3ee8161371877aa332faa09c'
      'd0bdd03b377143844469b9fdfa1c9daad1973df8ddf715ad505be2e67f80af4e'
      '86a670e694465c615739975cf59eea4dec41663d741713823782ef0ee9aafd22'
      '6e9b691c35bf7e4826c312b1a482bb82dd9c49e56920f5f742a61c0b5ddae5e6'
      '01eb4bc7ca17ea0fef9266e23bcea0783ae72525214039a684850a46e298b1bf'
      'b67c7dd6ad8d83ed6bc16123d30b8bccbedf5de74809d9992a7764f53f42e284'
      'd423ce0def33971b55fa5a9ad896c3e6b5f8dc2cad78ac9c7fe810fa9b2f5dfb'
      '30f71250119a9b4d7bbb8f37ebd04093f26d7453d1c1f804195b1d7f90945f77'
      '5f74f82a87e55097fd2259893454f73d58308ae3b8c68ba8df14a4129d23d166'
      '02589311b171a9861484953cc20d056afa837a1dd3c1c5a7f43a06d6a8cf7fb7'
      'a13bf47f0ae47ae82def335a9f2de7e9ff111a8b1b0a8d73db75cc666ab7cedb'
      '30783f779ae5c56aac4cbe09f9175eef17f4fe652ee9a64a4aed54433d8e7df8'
      '241656139d20d2207f7c096fb3db549624e3b9cd24b62a7f9f9f2fd7b9c9b5dc'
      '97458b32065ee6b88c43cbe28c4f5ea8feb7b6a8dab3351db5d93836b903edaa'
      'a1a1b713baffb3964c3963871543677002cf8da9ba10e2fceac14296db123bb6'
      '111613f19ae4a5945f931b0fe0be7e811e34ec58ebe6387c4fd3987298b304a1'
      '2483c267b97631d24c7c316de2671a64ed979e6482a17e8b8e85f46d07778fe3'
      'ecb468fe87dee3b538e63486b5e64928105553b5ff0eba1d423fd9b9cac7c9ff'
      '976fd0c2f76ea53af59b602213736efc217e85683f227265eb2cf49bf8e906a1'
      'd1fb27a22bdebc51b07ee51ebc3ac3c03256e531131ca70f465abb8886344852'
      'b9916e20a8123c991ed87c1843bd3027df705beae6874dcd85f03b58edb72120'
      'ba4daa571e7e822c1b6e0161471c6f7cc63410e068d0e85e0cd87222336bd0a5'
      'f3c4ce34ea80a1a61c8ba074ac92da1768b920e84e3501566286b685a8a1fc5c'
      '78553443324dfdc3c8b94009b0ae022dac6aaddd4aec35243b8b083f0d8dfb99'
      'e4c16d8efcc233c215f920fe2ecd96d75a17a40cf3ecb42922dce3e9ac9eb163'
      '65e51202f9bfe0e2776e09ad0b334d3ad61ec77af00668e0dcd049f14c5356be'
      '0db1d909e77b203d4a250a90a7f5f69b2ec88e9a0b5d46855686e1eac2c8317c'
      'f5092b7ec478cb32e66bbcb6106caca4d8b58d0e1b3dae025d5833946c49a073'
      '2f3801a592aa2857dc419f029d3c4da813184758e3133a4ec36f3ead080cf891'
      '00722b5f5418d25f427cd1d352eeb125cfccf0ad671cda457f7f21d30f614b74'
      '46db6737555bf0f6f80277d4e193adf71a62bf1b45fe31924a63a00b8bb98238'
      '79128413c15b1b63b84a7bb007fe11ffd45831ef9223e0a71ac0ae69fdb396c1'
      '52eff27a9e68e552e566e0f3a3a5a9e9f7e87fb9f77716da7a06b292f7c06ed2'
      'dea9a388e77aea422ae52ddb796559afd759e01d65a11d3a23fb766c5eb3d7f1'
      'a3003abe575f30e05bd54fc054d744bce8f48976e573b117c4bdf22962212855'
      '92bf82b817b40ef801d52ac3ba9a5ddb8c99e53c0cc3d83325e9636ed54c7822'
      'b68b72244076369e7490c0a962e580acbd0ca817fc326a1d9a3a6d6f1ecece2d'
      '6c7c49e70b10229228e12d96d89214661d443bb6a70b61a00b49d6642284226e'
      'bb21b9baf0fcd1d699f2e77723c92fb39d6849adcc4b20d612b05414f42ed573'
      'a794a42f2bb48174a56fb2004b192b9ff9208f788485d1f0251e86689015f73d'
      '73f3a46be64704a6e65399f26406ce39c9e756e1805b40e50cd4b725128377db'
      '3c700db8ff0ea1c56099b71691783fa644478d4312dd8f6511738ec902174785';

  /// Whether [maintainerMlDsaPublicKeyHex] is set and has the length required by §4.4
  /// (1,952 B = 3,904 hex characters).
  static bool get maintainerMlDsaKeyConfigured =>
      maintainerMlDsaPublicKeyHex.length ==
          OqsFFI.mlDsaPublicKeyLength * 2 &&
      RegExp(r'^[0-9a-f]+$').hasMatch(maintainerMlDsaPublicKeyHex);

  // `log` is missing at several call sites in main.dart (before any identity,
  // hence no per-identity profileDir available). The fallback uses
  // AppPaths.dataDir instead of a profileDir-less CLogger, otherwise the
  // startup branch (manifest signature check) is invisible in the field.
  UpdateChecker({CLogger? log})
      : _log = log ?? CLogger.get('UpdateChecker', profileDir: AppPaths.dataDir);

  /// Parse and verify an update manifest from its JSON.
  ///
  /// Returns the manifest if signature is valid, null otherwise.
  UpdateManifest? verifyManifest(String jsonData) {
    try {
      final json = jsonDecode(jsonData) as Map<String, dynamic>;
      final manifest = UpdateManifest.fromJson(json);
      if (manifest == null) return null;

      // §4.4.3: without the PQ key the hybrid check cannot be
      // carried out — and what cannot be checked does not count as
      // checked. A message of its own, so that this state does not appear in the field as
      // "signature wrong".
      if (!maintainerMlDsaKeyConfigured) {
        _log.warn('Update manifest rejected: no ML-DSA-65 maintainer key '
            'compiled in (UpdateChecker.maintainerMlDsaPublicKeyHex is empty). '
            'The manifest is hybrid-signed (v4_2 4.4.3) and cannot be verified '
            'without it. See scripts/gen-maintainer-mldsa-key.sh');
        return null;
      }

      final pubKey = _hexToBytes(maintainerPublicKeyHex);
      final pubKeyPq = _hexToBytes(maintainerMlDsaPublicKeyHex);
      if (!manifest.verify(pubKey, pubKeyPq)) {
        _log.warn('Update manifest hybrid signature verification FAILED '
            '(Ed25519 and/or ML-DSA-65)');
        return null;
      }

      _log.info('Update manifest verified: v${manifest.version}');
      return manifest;
    } catch (e) {
      _log.warn('Failed to parse update manifest: $e');
      return null;
    }
  }

  /// True if [a] and [b] represent the same semver version (ignoring build metadata).
  bool isSameVersion(String a, String b) {
    return !isNewer(a, b) && !isNewer(b, a);
  }

  /// Check if a manifest version is newer than the current version.
  bool isNewer(String manifestVersion, String currentVersion) {
    final mv = _parseVersion(manifestVersion);
    final cv = _parseVersion(currentVersion);
    if (mv == null || cv == null) return false;

    for (var i = 0; i < 3; i++) {
      if (mv[i] > cv[i]) return true;
      if (mv[i] < cv[i]) return false;
    }
    return false; // equal
  }

  /// Hard-block check (Sec H-5 V3.1.72): true if the manifest specifies a
  /// minRequiredVersion AND the current app version is older.
  bool isHardBlocked(UpdateManifest manifest, String currentVersion) {
    final minReq = manifest.minRequiredVersion;
    if (minReq == null) return false;
    final mv = _parseVersion(minReq);
    final cv = _parseVersion(currentVersion);
    if (mv == null || cv == null) return false;
    for (var i = 0; i < 3; i++) {
      if (cv[i] < mv[i]) return true;
      if (cv[i] > mv[i]) return false;
    }
    return false;  // equal → not blocked
  }

  /// Downgrade protection (§19.6): true if the manifest may not be trusted
  /// to be newer than what this node has already seen.
  ///
  /// ── S368: A MISSING FIELD IS NOW A REASON FOR REJECTION ──────────
  ///
  /// Here stood `manifest.minMonotoneSeq != null && … <= highestSeenSeq`.
  /// If the sequence number was missing, the result was `false` — **no
  /// downgrade attempt, let through**. Thus an old, validly
  /// signed manifest WITHOUT a sequence number bypassed the replay protection
  /// completely: the check that is supposed to reject it returned "harmless" for exactly this
  /// manifest. The protection only took effect against manifests
  /// that brought it along themselves — i.e. against all except the attack case.
  ///
  /// **The mechanism itself stays unchanged** and is expressly
  /// NO way back to an older line: it fends off a SLIPPED-IN
  /// older binary package (an attacker replays a version with
  /// known holes). Only its leniency towards
  /// manifests without a sequence number goes.
  ///
  /// **Price, named:** a manifest without `monotoneSeq` is no longer accepted for
  /// in-network updates. `scripts/sign-update-manifest.sh`
  /// therefore now requires the number, instead of only entering it if it
  /// happens to be set — otherwise the pipeline would publish manifests
  /// that its own clients reject.
  bool isDowngradeAttempt(UpdateManifest manifest, int highestSeenSeq) {
    final seq = manifest.minMonotoneSeq;
    if (seq == null) return true; // fail closed
    return seq <= highestSeenSeq;
  }

  List<int>? _parseVersion(String version) {
    final parts = version.replaceAll('+', '.').split('.');
    if (parts.length < 3) return null;
    try {
      return [int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])];
    } catch (_) {
      return null;
    }
  }

  Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
