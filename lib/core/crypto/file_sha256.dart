import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

/// SHA-256 of the file at [path], streamed in the chunks of
/// `File.openRead` — the file is never held in memory.
///
/// `SodiumFFI.sha256` takes the whole object as one buffer and copies it
/// into native memory once more: for a ~200 MB APK that is 2 × 200 MB at
/// once, which together with the holder's own copy OOM-killed the
/// bootstrap daemon (S406-OOM, 07.10.2026). Same digest, O(chunk) memory.
Future<Uint8List> sha256OfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).last;
  return Uint8List.fromList(digest.bytes);
}
