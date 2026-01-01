import 'dart:io';
import 'dart:isolate';

import 'package:cleona/core/crypto/file_sha256.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex;
import 'package:cleona/core/update/update_binary_store.dart';

/// A phone hands its own binary out from the INSTALLED file, never from a
/// copy in the update store (S407-UPDATEFRAGMENTE, W9).
///
/// v4_2 §26.6.1 step 3: "desktop installations hold the complete objects of
/// the current manifest; a phone holds none". Until S407 a phone copied its
/// running APK (≈ 390 MB for 4.2.3) into the update store at every start
/// (`_selfSeedCurrentBinary`), and the store's budget evicted it again.
/// The two places where a phone legitimately hands its own binary out are
/// the HTTP path of the invitation link (§26.6.3, §26.6.5 — also "Local
/// WLAN (HTTP)" of §26.6.6) and the export for a physical handover
/// (§26.6.6). Both read the installed file now (Android:
/// `ApplicationInfo.sourceDir`); the system share sheet already did.

/// Whether this device stores its running binary in the update store at
/// start. Only a desktop holds objects (§26.6.1 step 3), a store build never
/// updates itself, and a stored complete object is not stored again.
bool selfSeedWanted(
        {required bool phone,
        required bool playStore,
        required bool hasComplete}) =>
    !phone && !playStore && !hasComplete;

/// The file the HTTP path serves for [platform]: the newest complete object
/// in [store]; else, on a phone, the installed binary when [platform] is
/// its own ([installedPath], resolved at start; null on a desktop).
String? servedBinaryPath(UpdateBinaryStore store, String platform,
    {required String ownPlatform, String? installedPath}) {
  final versions = store.storedVersionsSync(platform);
  for (final v in versions.reversed) {
    final p = store.getCompletePath(platform, v);
    if (p != null) return p;
  }
  if (platform != ownPlatform || installedPath == null) return null;
  return File(installedPath).existsSync() ? installedPath : null;
}

/// Copies [source] to [outputPath] and returns the SHA-256 (lowercase hex)
/// of what was copied — streamed, in an isolate, the file never in memory
/// (the android object is ~390 MB; `SodiumFFI.sha256` would need it whole).
Future<String> copyWithHash(String source, String outputPath) async {
  final tmp = '$outputPath.tmp';
  await File(source).copy(tmp);
  await File(tmp).rename(outputPath);
  return bytesToHex(await Isolate.run(() => sha256OfFile(outputPath)));
}
