// V3.0 Device-Keys persistence (Architecture v3.0 §3.5 + §3.5b + §3.6 #5).
//
// Holds the device-bound keypair container per Daemon
// (`<baseDir>/device_keys.bin.enc`, shared across all hosted user identities
// — DeviceID is device-bound, not identity-bound). The container carries
// BOTH:
//
//   * Device-Sig keypair (Ed25519 + ML-DSA-65)  — see device_signature.dart
//   * Device-KEM keypair (X25519 + ML-KEM-768)  — see device_kem.dart
//
// Lazy-create-on-first-start: if the encrypted blob does not exist, both
// keypairs are generated via DeviceKeyPair.generate() / DeviceKemKeyPair.generate()
// (OS CSPRNG, NOT seed-derived per §3.6 #5) and persisted atomically before
// returning them.
//
// On-disk container layout (after FileEncryption.writeBinaryFile applies the
// XSalsa20-Poly1305 envelope):
//
//   v2 (current — Welle 5):
//     [4B magic = "CLDK" / 0x43 0x4C 0x44 0x4B]
//     [4B u32 little-endian version = 2]
//     [DeviceKeyPair.serializedLength bytes  : Device-Sig keypair]
//     [DeviceKemKeyPair.serializedLength bytes: Device-KEM keypair]
//
//   v1 (legacy — pre-Welle-5):
//     [DeviceKeyPair.serializedLength bytes  : Device-Sig keypair only]
//     (no header, no magic, fixed length)
//
// v1 → v2 migration: if [loadOrCreate] reads a blob that does not start with
// the magic and matches the v1 length exactly, it is treated as a legacy
// v1-only container. The Sig keypair is parsed, a fresh KEM keypair is
// generated (CSPRNG, this is a hard-cut: there is no v1 KEM keypair to
// migrate), and the combined v2 blob is rewritten in place. This is the
// hard-cut-friendly path: existing devices upgrade in place at first launch
// after the Welle 5 deployment, without requiring a manual reset of the
// daemon's key material.
//
// Storage uses the same XSalsa20-Poly1305 file encryption as the rest of the
// profile (`db.key` keyed) — see FileEncryption.writeBinaryFile. Write is
// crash-atomic (tmp + rename), recovery probes `.enc.tmp` / `.enc.old`
// sidecars on read.
//
// Threading: callers must serialize calls to [loadOrCreate] from a single
// daemon-startup path; concurrent invocations would race on the
// generate-and-persist branch. In practice CleonaNode.start() awaits this
// before registerIdentity is called for any identity, so the constraint is
// trivially satisfied.

import 'dart:typed_data';

import 'package:cleona/core/crypto/device_kem.dart';
import 'package:cleona/core/crypto/device_signature.dart';
import 'package:cleona/core/crypto/file_encryption.dart';

/// Combined device keypair bundle (Sig + KEM). What [DeviceKeysStore.loadOrCreate]
/// returns — single value to wire into CleonaNode without two parallel calls.
class DeviceKeyBundle {
  final DeviceKeyPair sig;
  final DeviceKemKeyPair kem;

  const DeviceKeyBundle({required this.sig, required this.kem});
}

class DeviceKeysStore {
  /// On-disk filename (relative to baseDir). The `.enc` suffix is appended
  /// by FileEncryption.writeBinaryFile.
  static const String _filename = 'device_keys.bin';

  /// Container magic — ASCII "CLDK" (Cleona Device Keys). Distinguishes
  /// v2+ containers (with header) from the unheadered v1 layout.
  static const List<int> _magic = [0x43, 0x4C, 0x44, 0x4B];

  /// Current container format version.
  static const int containerVersion = 2;

  /// v1 container length (Sig keypair only, no header).
  static int get _v1Length => DeviceKeyPair.serializedLength;

  /// v2 container length (header + Sig + KEM).
  static int get _v2Length =>
      _magic.length + 4 + DeviceKeyPair.serializedLength + DeviceKemKeyPair.serializedLength;

  /// Load the daemon's Device-Sig + Device-KEM keypair bundle from disk, or
  /// generate-and-persist a fresh one if none exists. If a legacy v1 blob
  /// (Sig only) is found, it is migrated in place by generating a fresh
  /// KEM keypair and rewriting the file as v2.
  ///
  /// On read of an existing blob, deserialize-failures throw rather than
  /// silently regenerating — a corrupt key store usually means the wrong
  /// `db.key` is present (e.g. profile cross-contamination), which would
  /// silently break Auth-Manifest replay if we just generated a new one.
  static DeviceKeyBundle loadOrCreate(
      {required String baseDir, required FileEncryption fileEnc}) {
    final path = '$baseDir/$_filename';
    final existing = fileEnc.readBinaryFile(path);

    if (existing == null) {
      // Fresh install — generate both keypairs, persist v2, return.
      final fresh = DeviceKeyBundle(
        sig: DeviceKeyPair.generate(),
        kem: DeviceKemKeyPair.generate(),
      );
      fileEnc.writeBinaryFile(path, _encodeV2(fresh));
      return fresh;
    }

    // Detect format: v2 starts with magic; v1 is exactly _v1Length bytes
    // and lacks the magic prefix.
    if (_hasMagic(existing)) {
      // v2 (or future versions — currently only 2 is accepted).
      return _decodeV2(existing);
    }

    if (existing.length == _v1Length) {
      // Legacy v1: parse the Sig keypair, generate fresh KEM, rewrite as v2.
      // deserialize throws DeviceSignatureException on length-mismatch — let
      // it propagate so the daemon fails loud rather than silently rotating
      // the device identity (which would orphan the Auth-Manifest).
      final sig = DeviceKeyPair.deserialize(existing);
      final kem = DeviceKemKeyPair.generate();
      final bundle = DeviceKeyBundle(sig: sig, kem: kem);
      // Rewrite atomically as v2 — on next launch the v2 path is taken.
      fileEnc.writeBinaryFile(path, _encodeV2(bundle));
      return bundle;
    }

    // Unknown shape: not v2 magic, not v1 length. Fail loud — silently
    // regenerating would orphan the Auth-Manifest.
    throw DeviceKeysStoreException(
        'unrecognised device key container at $path: '
        '${existing.length} bytes, no "CLDK" magic, not a v1-sized blob '
        '(expected $_v1Length or $_v2Length bytes for v2)');
  }

  /// Re-persist an in-memory bundle. Useful only for explicit rotation
  /// flows (currently none — V3.0 has no automatic device-key rotation; if
  /// added later it lives in a separate device_revocation flow per §7.4).
  static void persist(
      {required String baseDir,
      required FileEncryption fileEnc,
      required DeviceKeyBundle bundle}) {
    fileEnc.writeBinaryFile('$baseDir/$_filename', _encodeV2(bundle));
  }

  /// Test/util: explicit reset path so a profile-wipe test can drop the
  /// device key alongside the rest of the encrypted state.
  static Uint8List? rawBytesForTest(
      {required String baseDir, required FileEncryption fileEnc}) {
    return fileEnc.readBinaryFile('$baseDir/$_filename');
  }

  // ===========================================================================
  // Encoding helpers
  // ===========================================================================

  static bool _hasMagic(Uint8List bytes) {
    if (bytes.length < _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  static Uint8List _encodeV2(DeviceKeyBundle bundle) {
    final sigBytes = bundle.sig.serialize();
    final kemBytes = bundle.kem.serialize();
    if (sigBytes.length != DeviceKeyPair.serializedLength) {
      throw DeviceKeysStoreException(
          'unexpected sig serializedLength: ${sigBytes.length}');
    }
    if (kemBytes.length != DeviceKemKeyPair.serializedLength) {
      throw DeviceKeysStoreException(
          'unexpected kem serializedLength: ${kemBytes.length}');
    }
    final out = BytesBuilder(copy: false);
    out.add(_magic);
    final ver = ByteData(4)..setUint32(0, containerVersion, Endian.little);
    out.add(ver.buffer.asUint8List());
    out.add(sigBytes);
    out.add(kemBytes);
    final result = out.toBytes();
    if (result.length != _v2Length) {
      throw DeviceKeysStoreException(
          'v2 encode length mismatch: got ${result.length}, expected $_v2Length');
    }
    return result;
  }

  static DeviceKeyBundle _decodeV2(Uint8List bytes) {
    if (bytes.length != _v2Length) {
      throw DeviceKeysStoreException(
          'v2 container length mismatch: got ${bytes.length}, expected $_v2Length');
    }
    // Verify version field (offset 4..8).
    final ver =
        ByteData.sublistView(bytes, _magic.length, _magic.length + 4)
            .getUint32(0, Endian.little);
    if (ver != containerVersion) {
      throw DeviceKeysStoreException(
          'unsupported container version $ver (this build expects $containerVersion)');
    }
    var off = _magic.length + 4;
    final sigSlice = Uint8List.sublistView(
        bytes, off, off + DeviceKeyPair.serializedLength);
    off += DeviceKeyPair.serializedLength;
    final kemSlice = Uint8List.sublistView(
        bytes, off, off + DeviceKemKeyPair.serializedLength);

    return DeviceKeyBundle(
      sig: DeviceKeyPair.deserialize(Uint8List.fromList(sigSlice)),
      kem: DeviceKemKeyPair.deserialize(Uint8List.fromList(kemSlice)),
    );
  }
}

/// Exception thrown for container-level errors (unknown shape, bad magic,
/// version mismatch). Distinct from [DeviceSignatureException] /
/// [DeviceKemException] which fire on the inner blobs.
class DeviceKeysStoreException implements Exception {
  final String message;
  const DeviceKeysStoreException(this.message);

  @override
  String toString() => 'DeviceKeysStoreException: $message';
}
