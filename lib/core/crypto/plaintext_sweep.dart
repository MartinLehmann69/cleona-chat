import 'dart:io';

import 'package:cleona/core/log/clogger.dart';

/// Result of a cleanup run over ONE file at rest.
///
/// Shared with `MediaSweep` (`lib/core/media/media_sweep.dart`), which
/// converts attachments under `media/` — files that DO have a reader.
enum SweepOutcome {
  /// There was no plaintext version (any more) — nothing to do.
  nothingToDo,

  /// A readable ciphertext was already present; the plaintext version
  /// lying next to it was removed.
  plaintextRemoved,

  /// The plaintext version was written encrypted, read back, checked and
  /// only then deleted.
  migrated,

  /// The run deleted NOTHING. The plaintext version lies on unchanged —
  /// deliberately, so that an error costs no data.
  failed,
}

/// Enforcer for user content that must not lie in a file next to the
/// store: it REMOVES what it finds under a given name.
///
/// ── WHAT IT WAS, AND WHY IT IS NO LONGER THAT (S401, 02.10.2026) ──────
///
/// From S362 on this class SEALED a plaintext file it found (`sweepOne`:
/// write encrypted, read back, delete the plaintext). That was right as
/// long as the sealed file was what the service read. Since S366 the
/// service reads the same content from the STORE — transcripts from the
/// area `voice_transcriptions`, picture and self-description from the
/// area `profile`; the interaction graph has no reader at all. From then
/// on every run that found something produced a sealed file NO code
/// opened: a second storage of message content next to the store, which
/// v4_2 §21.4.2 rules out ("Message text and conversation metadata always
/// live in the message store").
///
/// ── WHY REMOVING LOSES NOTHING ─────────────────────────────────────────
///
/// No build of this line ever wrote these names in plaintext: the writers
/// have sealed since S362 (02.09.2026), the profile marker without which
/// `FirstStartWipe` deletes the whole profile exists since S363
/// (03.09.2026), and the store carries the content since S366
/// (04.09.2026). A file found under one of the names therefore holds
/// nothing this line stored — and it is not taken over either: this line
/// reads no foreign stock (CLAUDE.md "Linien"; `FileEncryption.readJsonFile`
/// refuses a plaintext without ciphertext for the same reason).
///
/// ── WHY IT STAYS AT ALL ────────────────────────────────────────────────
///
/// Its statement is "under this name nothing lies in this profile", and
/// that statement has no other keeper: a name without a writer and without
/// a reader is exactly the file nobody comes past again.
class PlaintextSweep {
  PlaintextSweep._();

  /// The forms in which a file handled by `FileEncryption` can lie on
  /// disk: the plaintext name itself, the sealed file and the two side
  /// pieces of an interrupted write.
  ///
  /// The side pieces matter: `FileEncryption.readJsonFile` promotes a
  /// readable `.enc.tmp`/`.enc.old` back to `.enc`. A cleaner that left
  /// them would have removed nothing.
  static const List<String> forms = ['', '.enc', '.enc.tmp', '.enc.old'];

  /// Removes every form of [path] ([forms]). [path] is the PLAINTEXT path,
  /// without `.enc`.
  ///
  /// Nothing is read: the content is of no interest, and neither is the
  /// key a sealed form lies under. Returns the base names of the files
  /// actually removed, empty if there was nothing.
  ///
  /// A file that cannot be deleted (open elsewhere, no permission) stays
  /// and is reported through [log]; the run goes on with the other forms
  /// and repeats at the next start — it is deliberately bound to no marker.
  static List<String> removeAllForms(String path, {CLogger? log}) {
    final removed = <String>[];
    for (final suffix in forms) {
      final f = File('$path$suffix');
      if (!f.existsSync()) continue;
      try {
        f.deleteSync();
        removed.add(f.uri.pathSegments.last);
      } catch (e) {
        log?.warn('Sweeper: $path$suffix could not be removed: $e — it '
            'still lies in the profile.');
      }
    }
    if (removed.isNotEmpty) {
      log?.info('Sweeper: removed ${removed.join(', ')} — content that '
          'belongs in the store, found in a file next to it.');
    }
    return removed;
  }
}
