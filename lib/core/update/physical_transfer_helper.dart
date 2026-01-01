import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/ip_address_class.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:cleona/core/rendezvous/rendezvous_provider.dart' show EndpointAddress;
import 'package:cleona/core/update/binary_fragment_store.dart';
import 'package:cleona/core/update/update_manifest.dart' show UpdateChecker;

/// Helper for physical binary transfer (§19.6.7).
///
/// Supports USB, NFC, Bluetooth, and Local Wi-Fi transfer by providing
/// binary export, hash verification, and LAN URL generation. The actual
/// transport mechanism (USB copy, OBEX push, etc.) is OS-level and
/// outside this class's scope.
class PhysicalTransferHelper {
  final BinaryFragmentStore _store;
  final CLogger _log;

  PhysicalTransferHelper({
    required this._store,
    String? profileDir,
  })  : _log = CLogger.get('phys-transfer', profileDir: profileDir);

  /// Export the current binary for a given platform to a file at [outputPath].
  /// Returns the SHA-256 hash of the exported file, or null on failure.
  ///
  /// Use case: user wants to copy the binary to USB stick for physical transfer.
  Future<String?> exportBinary({
    required String platform,
    required String version,
    required String outputPath,
  }) async {
    try {
      final data = await _store.getComplete(platform, version);
      if (data == null) {
        _log.warn('exportBinary: no complete binary for $platform/$version');
        return null;
      }
      await File(outputPath).writeAsBytes(data);
      return bytesToHex(SodiumFFI().sha256(data));
    } catch (e) {
      _log.error('exportBinary $platform/$version -> $outputPath failed: $e');
      return null;
    }
  }

  /// Export a single fragment to a file. Used when the node doesn't have
  /// the complete binary but has individual fragments.
  Future<bool> exportFragment({
    required String platform,
    required String version,
    required int index,
    required String outputPath,
  }) async {
    try {
      final data = await _store.getFragment(platform, version, index);
      if (data == null) {
        _log.warn('exportFragment: no fragment #$index for $platform/$version');
        return false;
      }
      await File(outputPath).writeAsBytes(data);
      return true;
    } catch (e) {
      _log.error('exportFragment $platform/$version#$index -> $outputPath failed: $e');
      return false;
    }
  }

  /// Export all available fragments to a directory.
  /// Creates files named `fragment-NNN.bin` in the output directory.
  /// Returns the number of fragments exported.
  Future<int> exportAllFragments({
    required String platform,
    required String version,
    required String outputDir,
  }) async {
    var exported = 0;
    try {
      final indices = await _store.availableFragments(platform, version);
      if (indices.isEmpty) return 0;
      final dir = Directory(outputDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      for (final index in indices) {
        final data = await _store.getFragment(platform, version, index);
        if (data == null) continue;
        final name = 'fragment-${index.toString().padLeft(3, '0')}.bin';
        await File('$outputDir/$name').writeAsBytes(data);
        exported++;
      }
    } catch (e) {
      _log.error('exportAllFragments $platform/$version -> $outputDir failed: $e');
    }
    return exported;
  }

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

  /// Import a fragment from a file path.
  Future<bool> importFragment({
    required String filePath,
    required String platform,
    required String version,
    required int index,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _log.warn('importFragment: file not found: $filePath');
        return false;
      }
      final data = await file.readAsBytes();
      await _store.storeFragment(platform, version, index, data);
      return true;
    } catch (e) {
      _log.error('importFragment $filePath failed: $e');
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
