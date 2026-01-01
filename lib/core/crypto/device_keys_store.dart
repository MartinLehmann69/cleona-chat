// Device-keys persistence (v4_2 §4.4.2, §4.5.2 "Fail-loud is normative").
//
// Holds the device-bound keypair container of this device — shared across
// all hosted user identities; the DeviceID is device-bound, not
// identity-bound. The container carries BOTH:
//
//   * Device-Sig keypair (Ed25519 + ML-DSA-65)  — see device_signature.dart
//   * Device-KEM keypair (X25519 + ML-KEM-768)  — see device_kem.dart
//
// Lazy-create-on-first-start: if no container is stored, both keypairs are
// generated via DeviceKeyPair.generate() / DeviceKemKeyPair.generate()
// (OS CSPRNG, NOT seed-derived, §4.4.2) and stored before they are
// returned.
//
// ── WHERE IT LIES (S403) ───────────────────────────────────────────────
//
// In the device database, `<baseDir>/device.db` (v4_2 §4.5.2, §4.5.3 form
// 2, §21.4.1, D-51): ONE row, area `DeviceStore.areaDeviceKeys`, the
// container below as base64. Until S403 the container was the file
// `<baseDir>/device_keys.bin.enc`; nothing reads that file any more, and
// the start removes it (`superseded_device_files.dart`). There is no
// takeover: a device that carried the file gets new device keys.
//
// The state table takes JSON, hence base64 (4/3 of 6 104 B). The row is
// written once at first start and once more when the admission nonce is
// added.
//
// Container layout:
//
//   [4B magic = "CLDK" / 0x43 0x4C 0x44 0x4B]
//   [4B u32 little-endian version = 2 or 3]
//   [DeviceKeyPair.serializedLength bytes  : Device-Sig keypair]
//   [DeviceKemKeyPair.serializedLength bytes: Device-KEM keypair]
//   [8B admission nonce — version 3 only]
//
// The unheadered v1 container (Sig keypair only) and the fallback to a
// found `db.key` are gone with the file: both were takeovers of stock from
// before this line, reachable only through a file this build no longer
// reads.
//
// THE KEY of the database is not chosen here. The caller supplies it, and
// the caller is `IdentityContext.initKeys`:
// `HdWallet.deriveSharedFileEncKey(masterSeed)`, the device-wide,
// seed-recoverable key.
//
// ── TWO CALLERS AT ONCE ────────────────────────────────────────────────
//
// [loadOrCreate] reads and, if nothing is there, generates and writes — in
// ONE transaction of the device database, which holds the write lock from
// its start. Two identities whose keys are initialised at the same time,
// or two programs on the same profile, cannot both find "nothing there" and
// each write a pair of their own: the second one waits and reads what the
// first one wrote. Until S403 that hung on the callers running one after
// the other, and this header carried it as an open item.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/admission_pow.dart';
import 'package:cleona/core/crypto/device_kem.dart';
import 'package:cleona/core/crypto/device_signature.dart';
import 'package:cleona/core/storage/device_store.dart';

/// Combined device keypair bundle (Sig + KEM). What [DeviceKeysStore.loadOrCreate]
/// returns — a single value to wire into the startup path without two
/// parallel calls. (Here stood "into CleonaNode"; deleted with the CUT of
/// 2026-08-31.)
class DeviceKeyBundle {
  final DeviceKeyPair sig;
  final DeviceKemKeyPair kem;

  /// D3 Admission-PoW nonce (§13.1.2) — 8 bytes certifying sig.ed25519PublicKey.
  /// Null until computed; [DeviceKeysStore.ensureAdmissionNonce] fills it
  /// lazily (isolate) and persists the container as v3.
  Uint8List? admissionNonce;

  DeviceKeyBundle({required this.sig, required this.kem, this.admissionNonce});
}

class DeviceKeysStore {
  /// The field of the row that carries the container, base64.
  static const String _field = 'container';

  /// Container magic — ASCII "CLDK" (Cleona Device Keys).
  static const List<int> _magic = [0x43, 0x4C, 0x44, 0x4B];

  /// Current container format version (v3 = v2 + 8-byte admission nonce, D3).
  static const int containerVersion = 3;

  /// D3 Admission-PoW nonce length (§13.1.2).
  static const int _nonceLength = 8;

  /// v2 container length (header + Sig + KEM).
  static int get _v2Length =>
      _magic.length + 4 + DeviceKeyPair.serializedLength + DeviceKemKeyPair.serializedLength;

  /// v3 container length (v2 + admission nonce).
  static int get _v3Length => _v2Length + _nonceLength;

  /// Loads the device's Device-Sig + Device-KEM keypair bundle from the
  /// device database of [baseDir], or generates and stores a fresh one if
  /// none is stored. [key] is the key of the device database.
  ///
  /// **Fail-loud (§4.5.2).** Keys are generated only when the database
  /// opens and holds no container. A database that lies there and does not
  /// open under [key] THROWS (`DeviceStoreException`); a stored container
  /// that does not decode THROWS ([DeviceKeysStoreException]). New keys in
  /// either case would change the device node id behind the back of
  /// everything that knows the old one.
  static DeviceKeyBundle loadOrCreate(
      {required String baseDir, required Uint8List key}) {
    final store = DeviceStore.at(baseDir, key);
    return store.transaction(() {
      final row =
          store.entry(DeviceStore.areaDeviceKeys, DeviceStore.keySingle);
      if (row == null) {
        // Genuine first start of this device — nothing stored.
        final fresh = DeviceKeyBundle(
          sig: DeviceKeyPair.generate(),
          kem: DeviceKemKeyPair.generate(),
        );
        _write(store, fresh);
        return fresh;
      }
      final Uint8List bytes;
      try {
        bytes = base64Decode(row[_field] as String);
      } catch (e) {
        throw DeviceKeysStoreException(
            'the device key container in the device database of $baseDir '
            'is not readable ($e) — will NOT regenerate (would change the '
            'device node id)');
      }
      if (!_hasMagic(bytes)) {
        // Unknown shape. Fail loud — silently regenerating would change
        // the device node id.
        throw DeviceKeysStoreException(
            'unrecognised device key container in the device database of '
            '$baseDir: ${bytes.length} bytes, no "CLDK" magic (expected '
            '$_v2Length or $_v3Length bytes)');
      }
      return _decodeVersioned(bytes);
    });
  }

  static void _write(DeviceStore store, DeviceKeyBundle bundle) =>
      store.putEntry(DeviceStore.areaDeviceKeys, DeviceStore.keySingle,
          {_field: base64Encode(_encodeBundle(bundle))});

  /// Re-persist an in-memory bundle. Useful only for explicit rotation
  /// flows (currently none — there is no automatic device-key rotation).
  static void persist(
      {required String baseDir,
      required Uint8List key,
      required DeviceKeyBundle bundle}) {
    _write(DeviceStore.at(baseDir, key), bundle);
  }

  /// D3 (§13.1.2): make sure the admission PoW nonce exists.
  /// Grinds in the isolate (~50-100ms desktop, <=2s mobile, once) and
  /// stores the container as v3. No-op if the nonce is already there.
  static Future<void> ensureAdmissionNonce(
      {required DeviceKeyBundle bundle,
      required String baseDir,
      required Uint8List key}) async {
    if (bundle.admissionNonce != null) return;
    final nonce =
        await AdmissionPow.computeAsync(bundle.sig.ed25519PublicKey);
    bundle.admissionNonce = nonce;
    _write(DeviceStore.at(baseDir, key), bundle);
  }

  // DROPPED ON 09.09.2026 (S378): no caller in lib/ or test/.
  // A test hook that no test touches.

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

  /// Encode the bundle: v3 when the admission nonce is present, v2 otherwise
  /// (a fresh install before [ensureAdmissionNonce] completes stays v2 —
  /// the next nonce-persist upgrades it in place).
  static Uint8List _encodeBundle(DeviceKeyBundle bundle) {
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
    final nonce = bundle.admissionNonce;
    if (nonce != null && nonce.length != _nonceLength) {
      throw DeviceKeysStoreException(
          'unexpected admission nonce length: ${nonce.length}');
    }
    final version = nonce != null ? 3 : 2;
    final out = BytesBuilder(copy: false);
    out.add(_magic);
    final ver = ByteData(4)..setUint32(0, version, Endian.little);
    out.add(ver.buffer.asUint8List());
    out.add(sigBytes);
    out.add(kemBytes);
    if (nonce != null) out.add(nonce);
    final result = out.toBytes();
    final expected = nonce != null ? _v3Length : _v2Length;
    if (result.length != expected) {
      throw DeviceKeysStoreException(
          'v$version encode length mismatch: got ${result.length}, expected $expected');
    }
    return result;
  }

  static DeviceKeyBundle _decodeVersioned(Uint8List bytes) {
    if (bytes.length < _magic.length + 4) {
      throw DeviceKeysStoreException(
          'container too short: ${bytes.length} bytes');
    }
    final ver =
        ByteData.sublistView(bytes, _magic.length, _magic.length + 4)
            .getUint32(0, Endian.little);
    if (ver != 2 && ver != 3) {
      throw DeviceKeysStoreException(
          'unsupported container version $ver (this build expects 2 or 3)');
    }
    final expected = ver == 3 ? _v3Length : _v2Length;
    if (bytes.length != expected) {
      throw DeviceKeysStoreException(
          'v$ver container length mismatch: got ${bytes.length}, expected $expected');
    }
    var off = _magic.length + 4;
    final sigSlice = Uint8List.sublistView(
        bytes, off, off + DeviceKeyPair.serializedLength);
    off += DeviceKeyPair.serializedLength;
    final kemSlice = Uint8List.sublistView(
        bytes, off, off + DeviceKemKeyPair.serializedLength);
    off += DeviceKemKeyPair.serializedLength;
    Uint8List? nonce;
    if (ver == 3) {
      nonce = Uint8List.fromList(
          Uint8List.sublistView(bytes, off, off + _nonceLength));
    }

    return DeviceKeyBundle(
      sig: DeviceKeyPair.deserialize(Uint8List.fromList(sigSlice)),
      kem: DeviceKemKeyPair.deserialize(Uint8List.fromList(kemSlice)),
      admissionNonce: nonce,
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
