import 'dart:io';

import 'package:cleona/core/crypto/file_sha256.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex;

/// Outcome of [seedBinaryFileToStore]: the SHA-256 of the stored object and
/// its size — the hash computed by streaming the file, never by holding it
/// in memory.
class SeedFileResult {
  final String binaryHash;
  final int bytes;

  const SeedFileResult({required this.binaryHash, required this.bytes});
}

/// Seed a binary FROM DISK into the store layout of [profileDir] as the
/// complete object, with bounded memory: the hash is streamed
/// (`sha256.bind`) and `complete.bin` is a `File.copySync` — the file is
/// never held in memory.
///
/// v4_2 §26.6.1 step 2: "Every node that holds an object encodes fountain
/// blocks from it, one block per packet and fresh for each request … nothing
/// is placed in advance"; step 3: desktops "hold the complete objects".
/// Until S407 this body ALSO wrote Reed-Solomon fragments (`fragment-NNN.bin`,
/// §19.6.2 of the 3.x line) next to `complete.bin` — on the bootstrap
/// ≈ 655 MB for 4.2.3 that nothing in 4.2 reads (S407-UPDATEFRAGMENTE).
///
/// This is the body the seeding isolate runs. It uses raw file I/O instead
/// of [UpdateBinaryStore] to avoid CLogger's Timer.periodic which is not
/// sendable across isolate boundaries.
///
/// Returns null when [binaryPath] does not exist or when [expectedHash] is
/// given and does not match. Otherwise writes `complete.bin` and
/// `meta.json` (`storedAt`, `binaryHash`) under
/// `$profileDir/binary-updates/$platform/$version` and returns the measured
/// hash and size.
Future<SeedFileResult?> seedBinaryFileToStore({
  required String binaryPath,
  required String profileDir,
  required String platform,
  required String version,
  String? expectedHash,
}) async {
  final file = File(binaryPath);
  if (!file.existsSync()) return null;

  final hash = bytesToHex(await sha256OfFile(binaryPath));
  if (expectedHash != null && hash != expectedHash.toLowerCase()) return null;

  final storageDir = '$profileDir/binary-updates/$platform/$version';
  Directory(storageDir).createSync(recursive: true);

  final tmp = '$storageDir/complete.bin.tmp';
  file.copySync(tmp);
  File(tmp).renameSync('$storageDir/complete.bin');

  File('$storageDir/meta.json').writeAsStringSync(
      '{"storedAt":${DateTime.now().millisecondsSinceEpoch},'
      '"binaryHash":"$hash"}');

  return SeedFileResult(binaryHash: hash, bytes: file.lengthSync());
}
