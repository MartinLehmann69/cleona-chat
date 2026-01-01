import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/ip_address_class.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/util/endpoint_address.dart';
import 'package:cleona/core/update/update_binary_store.dart';
import 'package:cleona/core/update/installed_binary.dart';
import 'package:cleona/core/update/update_manifest.dart' show UpdateChecker;

/// Helper for physical binary transfer (§19.6.7).
///
/// Supports USB, NFC, Bluetooth, and Local Wi-Fi transfer by providing
/// binary export, hash verification, and LAN URL generation. The actual
/// transport mechanism (USB copy, OBEX push, etc.) is OS-level and
/// outside this class's scope.
class PhysicalTransferHelper {
  final UpdateBinaryStore _store;
  final CLogger _log;

  PhysicalTransferHelper({
    required this._store,
    String? profileDir,
  })  : _log = CLogger.get('phys-transfer', profileDir: profileDir);

  /// Export the current binary for a given platform to a file at [outputPath].
  /// Returns the SHA-256 hash of the exported file, or null on failure.
  ///
  /// Use case: user wants to copy the binary to USB stick for physical transfer.
  ///
  /// The source is the complete object in the store, or — on a phone, which
  /// holds no copy (S407-UPDATEFRAGMENTE W9, §26.6.1 step 3) — the
  /// installed binary [installedPath] the caller names for its own running
  /// platform/version. Copied and hashed streaming (`copyWithHash`): until
  /// S407 the whole object was read into memory (android ~390 MB).
  Future<String?> exportBinary({
    required String platform,
    required String version,
    required String outputPath,
    String? installedPath,
  }) async {
    try {
      final source = _store.getCompletePath(platform, version) ??
          (installedPath != null && File(installedPath).existsSync()
              ? installedPath
              : null);
      if (source == null) {
        _log.warn('exportBinary: no complete binary for $platform/$version');
        return null;
      }
      return await copyWithHash(source, outputPath);
    } catch (e) {
      _log.error('exportBinary $platform/$version -> $outputPath failed: $e');
      return null;
    }
  }

  // `exportFragment`, `exportAllFragments` and `importFragment` stood
  // here: Reed-Solomon fragments of the 3.x layout handed over on a stick.
  // v4_2 §26.6.6 hands over "the APK/binary" only, and nothing stores
  // fragments any more (S407-UPDATEFRAGMENTE). None of the three had a
  // caller.

  /// Import a binary from a file path (received via physical transfer).
  /// Verifies SHA-256 hash and Ed25519 maintainer signature before storing.
  /// Returns true if verification passed and the binary was stored.
  Future<bool> importAndVerifyBinary({
    required String filePath,
    required String platform,
    required String version,
    required String expectedHash,
    required Uint8List maintainerSignature,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _log.warn('importAndVerifyBinary: file not found: $filePath');
        return false;
      }
      return await importAndVerifyBytes(
        data: await file.readAsBytes(),
        platform: platform,
        version: version,
        expectedHash: expectedHash,
        maintainerSignature: maintainerSignature,
      );
    } catch (e) {
      _log.error('importAndVerifyBinary $filePath failed: $e');
      return false;
    }
  }

  /// The same check for bytes that already lie in memory — the
  /// fetch path of the delivery layer (S388, `_startInNetworkUpdate` source 0).
  /// SHA-256 against [expectedHash] AND Ed25519 signature of the maintainer
  /// over this hash; only then `complete.bin`. `false` = nothing stored.
  ///
  /// The hash runs in an isolate as in `BinaryUpdateManager.verify`:
  /// a binary of 100-190 MB would otherwise block the UI (Android
  /// carries the GUI in the same process).
  Future<bool> importAndVerifyBytes({
    required Uint8List data,
    required String platform,
    required String version,
    required String expectedHash,
    required Uint8List maintainerSignature,
  }) async {
    try {
      final hash = await Isolate.run(() => SodiumFFI().sha256(data));
      final actualHash = bytesToHex(hash);
      if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
        _log.warn('importAndVerifyBinary: hash mismatch for $platform/$version '
            '(expected $expectedHash, got $actualHash)');
        return false;
      }
      final maintainerPubKey = hexToBytes(UpdateChecker.maintainerPublicKeyHex);
      final sigOk = SodiumFFI().verifyEd25519(hash, maintainerSignature, maintainerPubKey);
      if (!sigOk) {
        _log.warn('importAndVerifyBinary: maintainer signature verification FAILED '
            'for $platform/$version');
        return false;
      }
      await _store.storeComplete(platform, version, data);
      _log.info('importAndVerifyBinary: verified + stored $platform/$version '
          '(${data.length} bytes)');
      return true;
    } catch (e) {
      _log.error('importAndVerifyBytes $platform/$version failed: $e');
      return false;
    }
  }

  /// Generate the Local Wi-Fi transfer URL for the current node.
  /// This URL points to the embedded HTTP server (§19.6.6) on the LAN IP.
  ///
  /// Returns null if no LAN IP is available.
  String? lanTransferUrl({
    required List<EndpointAddress> localAddresses,
    required int port,
    required String platform,
  }) {
    for (final addr in localAddresses) {
      if (!IpAddressClass.isPrivate(addr.ip)) continue;
      final host = addr.ip.contains(':') ? '[${addr.ip}]' : addr.ip;
      return 'http://$host:$port/cleona/binary/$platform';
    }
    return null;
  }

  // DROPPED ON 09.09.2026 (S378): no caller in lib/ or test/.

  /// Compute the SHA-256 hash of a file (streaming, handles large files).
  Future<String?> hashFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _log.warn('hashFile: file not found: $filePath');
        return null;
      }
      // Binaries are 50-110MB — reading the whole file into memory is
      // acceptable here; SodiumFFI().sha256() operates on a full buffer
      // rather than a streaming API.
      final data = await file.readAsBytes();
      return bytesToHex(SodiumFFI().sha256(data));
    } catch (e) {
      _log.error('hashFile $filePath failed: $e');
      return null;
    }
  }

  void dispose() {}
}
