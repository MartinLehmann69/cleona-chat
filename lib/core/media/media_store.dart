import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/media_cipher.dart';

/// The at-rest storage of media attachments (S362, variant B).
///
/// **The finding this class closes.** Until S362 four
/// places wrote the attachment in PLAINTEXT to `$profileDir/media` — while the
/// message it belongs to lay encrypted next to it. The numbers are
/// the occurrences at state `d4d1f680`, BEFORE the switch; today there stands at
/// each a call of this class:
///
/// * `service/cleona_service_media.dart:281` — V4.1 bulk receive
/// * `service/cleona_service_media.dart:445` — V3 stage 2 receive
/// * `service/cleona_service.dart:11608` — inline receive (<256 KB)
/// * `service/cleona_service.dart:1650/:1657/:1660` — the SEND PATH, which copies the
///   file chosen by the user into the profile
///
/// Whoever had the device needed neither seed nor key: image, sound and
/// file lay open, and only the text was protected.
///
/// **The identifier stays the plaintext path.** `UiMessage.filePath` still carries
/// `$profileDir/media/foo.jpg`; the bytes lie under
/// `$profileDir/media/foo.jpg.cmenc`. Exactly the same convention is used by
/// [FileEncryption] with `.enc`. That keeps existing `conversations.json`
/// valid — no field has to be rewritten, and the sweeper can
/// abort at any time without a message pointing to a path that
/// does not exist.
///
/// **Why a key directory instead of a field.** On Linux and
/// Windows service and UI run in TWO processes
/// (`main.dart:1865` connects the GUI via IPC to the daemon). Both
/// must be able to read media, and both derive the same key from
/// the same master seed (`IdentityManager.loadMasterSeed`,
/// `identity_manager.dart:207`, is process-independent). The directory
/// maps `profileDir -> key`; whoever has a path finds its key via
/// the longest matching prefix.
class MediaStore {
  MediaStore._();

  static final MediaStore instance = MediaStore._();

  final Map<String, Uint8List> _keys = <String, Uint8List>{};

  /// Registers the key for a profile. Calling it multiple times with the same
  /// directory is allowed and overwrites — on an identity switch
  /// the key does not change, on a seed change it does.
  void register(String profileDir, Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError('MediaStore: key must have 32 bytes, '
          'not ${key.length}');
    }
    _keys[_normalise(profileDir)] = key;
  }

  /// Only for tests and identity teardown.
  void clear() => _keys.clear();

  /// The key for [path] — or `null` if no registered profile
  /// contains it.
  ///
  /// The LONGEST matching prefix is searched. If it were the first
  /// matching one, the wrong one would be hit with nested directories.
  Uint8List? keyForPath(String path) {
    final p = _normalise(path);
    String? best;
    for (final dir in _keys.keys) {
      if (!p.startsWith('$dir/')) continue;
      if (best == null || dir.length > best.length) best = dir;
    }
    return best == null ? null : _keys[best];
  }

  static String _normalise(String path) {
    var p = path.replaceAll('\\', '/');
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  // ── Writing ─────────────────────────────────────────────────────────

  /// Stores [bytes] encrypted under [path]. Throws if no
  /// key is registered — **not** a silent fallback to
  /// plaintext. A fallback would be exactly the finding this class
  /// closes, and it would be invisible.
  void writeBytes(String path, Uint8List bytes) {
    MediaCipher.encryptBytes(path, bytes, _needKey(path));
  }

  /// Takes over [srcPath] encrypted to [path], without ever holding the source
  /// entirely in memory. The send path takes this route: the
  /// upper limit for an attachment is 500 MB
  /// (`cleona_service.dart:1655`).
  void writeFromFile(String path, String srcPath) {
    MediaCipher.encryptFile(path, srcPath, _needKey(path));
  }

  // ── Reading ─────────────────────────────────────────────────────────

  bool exists(String path) => MediaCipher.exists(path);

  /// Is the attachment present at all — encrypted OR still in
  /// plaintext?
  ///
  /// **Why this second question exists.** `_recoverStuckMedia`
  /// (`cleona_service.dart:6924`) resets every message to `announced`
  /// and **deletes its `filePath`** if the file is missing. A
  /// sweep run that fails on a file would thereby permanently decouple exactly this
  /// message — the attachment would still lie there, but no
  /// message would point to it any more. The same question is asked by the
  /// send path on name collisions and by the UI before displaying.
  bool existsEitherWay(String path) =>
      MediaCipher.exists(path) || File(path).existsSync();

  /// Opens the attachment — preferably the ciphertext, otherwise the plaintext.
  /// `null` if both are missing or the key is not registered.
  MediaSource? openEitherWay(String path) {
    if (MediaCipher.exists(path)) return open(path);
    if (File(path).existsSync()) return PlainMediaSource(path);
    return null;
  }

  /// Length of the plaintext, without decrypting it. `null` if the
  /// file does not exist or its header does not open.
  int? plainLength(String path) {
    final key = keyForPath(path);
    if (key == null || !MediaCipher.exists(path)) return null;
    try {
      final r = MediaCipher.open(path, key);
      try {
        return r.length;
      } finally {
        r.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Whole file in one piece. Only for consumers who need the content
  /// completely anyway — clipboard and archive upload. Whoever
  /// displays or plays takes `MediaVault` and pays 192 KiB.
  Uint8List? readAll(String path) {
    final key = keyForPath(path);
    if (key != null && MediaCipher.exists(path)) {
      return MediaCipher.decryptAll(path, key);
    }
    // Legacy stock that the sweeper has not yet caught. Read yes,
    // write never — see [MediaSource].
    final plain = File(path);
    if (plain.existsSync()) return plain.readAsBytesSync();
    return null;
  }

  MediaReader? open(String path) {
    final key = keyForPath(path);
    if (key == null || !MediaCipher.exists(path)) return null;
    return MediaCipher.open(path, key);
  }

  void delete(String path) => MediaCipher.delete(path);

  /// Removes the attachment in BOTH forms — ciphertext AND leftover
  /// plaintext. The counterpart to [existsEitherWay], and for the same
  /// reason: whoever asks with `existsEitherWay` and deletes with [delete] leaves
  /// the file lying with legacy stock, but reports "gone".
  ///
  /// S392/B2: the archive asks with [existsEitherWay] before deleting and
  /// afterwards advances the stage. If the plaintext stayed, the
  /// conversation would show a placeholder next to a file that is still there — and the
  /// storage space that §21.6 promises would still not be free.
  /// [PlaintextSweep] would find the rest later, but "later" is here
  /// not a state a display may rely on.
  ///
  /// Reports whether REALLY nothing is left afterwards. The caller must not
  /// ignore the result: `false` means that the file resisted
  /// deletion (permissions, lock, running reader).
  bool deleteEitherWay(String path) {
    MediaCipher.delete(path);
    final plain = File(path);
    if (plain.existsSync()) {
      try {
        plain.deleteSync();
      } catch (_) {
        // Deliberately swallowed — the report below tells the
        // caller more precisely than an exception could.
      }
    }
    return !existsEitherWay(path);
  }

  Uint8List _needKey(String path) {
    final key = keyForPath(path);
    if (key != null) return key;
    throw StateError('MediaStore: no key registered for $path — '
        'an attachment is NOT stored in plaintext (S362). The caller '
        'must have gone through `MediaStore.instance.register(profileDir, key)` '
        'first.');
  }
}
