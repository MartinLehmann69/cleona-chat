import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/media_cipher.dart';
import 'package:cleona/core/crypto/plaintext_sweep.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/media/media_store.dart';

/// Result of a run over a whole media directory.
class MediaSweepResult {
  const MediaSweepResult({
    required this.migrated,
    required this.plaintextRemoved,
    required this.failed,
    required this.tmpRemoved,
  });

  /// Plaintext encrypted, read back, compared, then deleted.
  final int migrated;

  /// A readable ciphertext was already present; the plaintext next to it has fallen.
  final int plaintextRemoved;

  /// Nothing deleted — the plaintext continues to lie unchanged.
  final int failed;

  /// Side pieces `.cmenc.tmp` from aborted runs.
  final int tmpRemoved;

  int get touched => migrated + plaintextRemoved + failed;

  @override
  String toString() => 'migrated=$migrated already=$plaintextRemoved '
      'failed=$failed tmp=$tmpRemoved';
}

/// Transfers the media attachments stored in plaintext before S362 into the
/// framed storage ([MediaCipher]).
///
/// **Why this run is needed.** The four switched write places
/// only protect what arrives from now on. What lies open today in
/// `$profileDir/media` — every received image, every video, every
/// voice message and every sent file — would stay lying open, and
/// nobody would ever get past it again.
///
/// **The order is the whole security** — the same as in
/// [PlaintextSweep], only streaming, because an attachment may be up to 500 MB large
/// (`cleona_service.dart:1655`):
///
/// 1. **Write.** [MediaCipher.encryptFile] goes via `.cmenc.tmp` and
///    ONE `renameSync` ([atomicReplace]). There is either no `.cmenc`
///    or a complete one. **On Windows this assurance did NOT hold until S371:**
///    there a two-step ran (delete `.cmenc`, then
///    rename), and an abort in between left neither the one nor
///    the other behind. The justification for it — "Windows cannot
///    rename over an existing file" — is refuted by measurement.
/// 2. **Read back and compared byte by byte.** Without this step
///    "written" would only mean "it did not throw". The comparison is
///    frame by frame against the source file — never do both versions
///    lie in memory at once, it is two buffers of 64 KiB.
/// 3. **Only now does the plaintext fall.** `deleteSync` is a single
///    `unlink`, it goes through entirely or not at all.
///
/// Every abort in between is without consequence, and the run is **repeatable**:
///
/// * Abort while writing — at most a `.cmenc.tmp` remains.
///   The next run clears it away and starts over with the file.
/// * Abort after writing, before deleting — both versions lie
///   there. The next run finds a readable ciphertext, checks it against the
///   plaintext and removes the plaintext ([MediaSweepResult.plaintextRemoved]).
/// * Abort while deleting — `unlink` is indivisible.
///
/// **What the run does NOT do:** an existing `.cmenc` that cannot be
/// opened or does not match the plaintext, it does not overwrite, and
/// it deletes nothing next to it either. It reports it and leaves both files
/// lying — the same attitude as [PlaintextSweep] and
/// `CleonaService._loadContacts`.
class MediaSweep {
  MediaSweep._();

  /// Runs over [mediaDir]. The key comes from [MediaStore]; if
  /// none is registered, nothing runs at all (and nothing is deleted).
  static MediaSweepResult sweepDirectory(String mediaDir, {CLogger? log}) {
    final dir = Directory(mediaDir);
    if (!dir.existsSync()) {
      return const MediaSweepResult(
          migrated: 0, plaintextRemoved: 0, failed: 0, tmpRemoved: 0);
    }

    var migrated = 0;
    var removed = 0;
    var failed = 0;
    var tmp = 0;

    for (final e in dir.listSync()) {
      if (e is! File) continue;
      final name = e.path;

      // Side pieces from aborted runs. They carry NO
      // complete content (the header is in it, but the renamer did
      // not get to it) and must not count as ciphertext.
      if (name.endsWith('${MediaCipher.suffix}.tmp')) {
        try {
          e.deleteSync();
          tmp++;
        } catch (_) {}
        continue;
      }
      // Already transferred — the question is about the HEADER, not the
      // name. An attachment received before S362 that happens to be called
      // `bericht.cmenc` lies in plaintext; deciding by the name
      // would leave precisely it lying open forever.
      if (name.endsWith(MediaCipher.suffix) && MediaCipher.hasMagic(name)) {
        continue;
      }

      switch (sweepOne(name, log: log)) {
        case SweepOutcome.migrated:
          migrated++;
        case SweepOutcome.plaintextRemoved:
          removed++;
        case SweepOutcome.failed:
          failed++;
        case SweepOutcome.nothingToDo:
          break;
      }
    }

    return MediaSweepResult(
        migrated: migrated,
        plaintextRemoved: removed,
        failed: failed,
        tmpRemoved: tmp);
  }

  /// Transfers exactly one file. [plainPath] is the path WITHOUT
  /// `.cmenc` — the same identifier that stands in `UiMessage.filePath`.
  static SweepOutcome sweepOne(String plainPath, {CLogger? log}) {
    final plain = File(plainPath);
    if (!plain.existsSync()) return SweepOutcome.nothingToDo;

    final key = MediaStore.instance.keyForPath(plainPath);
    if (key == null) {
      log?.warn('Media sweep: no key registered for $plainPath '
          '— nothing written, nothing deleted.');
      return SweepOutcome.failed;
    }

    // ── 1. Is there already a ciphertext? ────────────────────────────────────
    // Then the question is not "is a .cmenc there" (that would be the
    // stand-in), but "does it carry the same content".
    if (MediaCipher.exists(plainPath)) {
      if (_matchesPlaintext(plainPath, key)) {
        try {
          plain.deleteSync();
        } catch (e) {
          log?.warn('Media sweeper: $plainPath could not be '
              'deleted: $e');
          return SweepOutcome.failed;
        }
        log?.info('Media sweeper: $plainPath was present twice — the '
            'ciphertext carries the same content, the plaintext version is '
            'removed.');
        return SweepOutcome.plaintextRemoved;
      }
      log?.warn('Media sweep: $plainPath${MediaCipher.suffix} exists, '
          'but does not carry the same content as the plaintext version. '
          'NOTHING is deleted and NOTHING overwritten — which of the '
          'two versions is the newer one, this run cannot know.');
      return SweepOutcome.failed;
    }

    // ── 2. Writing ──────────────────────────────────────────────────────
    try {
      MediaCipher.encryptFile(plainPath, plainPath, key);
    } catch (e) {
      log?.warn('Media sweep: $plainPath could not be written '
          'encrypted: $e — the plaintext stays in place.');
      MediaCipher.delete(plainPath); // only the half result, never the plaintext
      return SweepOutcome.failed;
    }

    // ── 3. Read back and compared byte by byte ─────────────────
    if (!_matchesPlaintext(plainPath, key)) {
      log?.warn('Media sweep: $plainPath${MediaCipher.suffix} '
          'written, but the read-back did not give the same content — '
          'the ciphertext is dropped, the plaintext stays in place.');
      MediaCipher.delete(plainPath);
      return SweepOutcome.failed;
    }

    // ── 4. Only now does the plaintext fall ───────────────────────────────
    try {
      plain.deleteSync();
    } catch (e) {
      log?.warn('Media sweep: $plainPath could not be deleted: '
          '$e — the ciphertext stays, unfortunately the plaintext too.');
      return SweepOutcome.failed;
    }
    log?.info('Media sweep: $plainPath is stored encrypted and '
        'the plaintext version removed.');
    return SweepOutcome.migrated;
  }

  /// Compares the ciphertext frame by frame against the plaintext file. Never do
  /// both versions lie in memory at once — two buffers of 64 KiB.
  static bool _matchesPlaintext(String plainPath, Uint8List key) {
    RandomAccessFile? src;
    MediaReader? reader;
    try {
      src = File(plainPath).openSync(mode: FileMode.read);
      reader = MediaCipher.open(plainPath, key);
      if (reader.length != src.lengthSync()) return false;
      final buf = Uint8List(reader.frameSize);
      for (var i = 0; i < reader.frameCount; i++) {
        final f = reader.frame(i);
        var got = 0;
        while (got < f.length) {
          final n = src.readIntoSync(buf, got, f.length);
          if (n <= 0) return false;
          got += n;
        }
        for (var j = 0; j < f.length; j++) {
          if (buf[j] != f[j]) return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      reader?.close();
      try {
        src?.closeSync();
      } catch (_) {}
    }
  }
}
