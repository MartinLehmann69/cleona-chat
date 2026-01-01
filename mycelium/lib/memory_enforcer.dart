/// THE ENFORCER: LEGACY DATA IS REMOVED, NOT SAT OUT.
///
/// ── THE FINDING THAT TRIGGERED THIS FILE (S391, 17.09.2026) ────
///
/// The version jump from S390 — host memory 4 -> 5, mailbox 12 -> 13
/// — made every node unable to start that had already run
/// once. Measured on two independent platforms, same line:
///
/// ```
/// 07:16:24 [ERROR] [daemon] `Dienst-Start fehlgeschlagen:`  (german-ok)
///                           `GedaechtnisFehler: unbekannte Fassung 4`  (german-ok)
/// 07:16:24 [ERROR] [daemon] Stack: #0 `WirtGedaechtnis._dekodieren`  (german-ok)
///                           #1 `WirtGedaechtnis.oeffnen`  #2 `Wirt.starten`  (german-ok)
/// Main PID: 932527 (code=exited, status=0/SUCCESS)
/// ```
///
/// [open] REJECTS a foreign version, and that stays so: W4 in
/// `test/smoke_memory.dart` demands it, and the reason holds — a
/// state with raw 4 B addresses read as version 5 turns every field
/// behind it into garbage. But rejecting means "the FILE is no longer fit",
/// not "the NODE dies". What was missing is the enforcer that
/// `CLAUDE.md` explicitly names next to `FirstStartWipe` and `PlaintextSweep`:
/// "enforcers that delete or reject legacy data".
///
/// ── WHAT IT DOES NOT DO ──────────────────────────────────────────────────
///
/// **It does not convert.** A legacy format is not read and not
/// adopted; exactly ONE field is rescued, and only for the reason in the
/// next paragraph.
///
/// **It clears only for a foreign version.** A file that cannot be
/// decrypted, and a truncated one, stay lying; there
/// [open] throws as before. "Unreadable" is not "outdated" —
/// an enforcer that treats both alike deletes the memory of a healthy node
/// on a wrong key. That is
/// deliberately an open edge: a damaged memory still makes the
/// node unable to start. Closing it means
/// deciding when data may be thrown away WITHOUT a format change —
/// a different question from this one.
///
/// ── WHY THE PORT IS RESCUED ──────────────────────────────────────
///
/// V4.2 §11.1: "The port is fixed at first start and never changes on its
/// own. A node that changes its port is unreachable to everybody holding
/// its card until a new card is exchanged."
///
/// An enforcer that throws away the host file including the port changes the
/// port on EVERY version jump and thereby devalues every issued
/// card — it would keep one rule by breaking another.
/// Therefore [HostMemory.clearedOpen] reads, before deleting, the
/// four bytes of the HEADER (version, port flag, port) and writes the port
/// back into the fresh file.
///
/// That is not converting, because the header has no version: it has stood since
/// version 2 unchanged at the same place, in the same width, with
/// the same byte order. So that it stays that way, it is pinned —
/// `test/smoke_memory_enforcer.dart` checks the position of the three
/// fields against the current encoding. Whoever moves the header turns
/// this probe red, rather than making the port rescue silently wrong.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';

/// Removes the memory file [fileName] in [directory] if it carries a
/// different version than [runningVersion].
///
/// `true` if clearing happened. `false` means: there was nothing to clear —
/// the file is missing, carries the running version, or cannot be
/// decrypted (then the enforcer does NOT judge, see header).
///
/// [beforeTheDelete] gets the decrypted legacy data before it
/// disappears — the one way to rescue a field without this file
/// having to know the legacy format. If the callback throws, nothing is deleted:
/// a half-rescued state would be worse than the old one.
///
/// Deletion happens via [FileEncryption.deleteFile], not via
/// `File(...).deleteSync()`: otherwise an `.enc.old` from an
/// aborted write would stay lying and bring back the legacy data on the
/// next read — the enforcer would then have reported that it
/// cleared, and cleared nothing.
bool legacyDataClear({
  required Directory directory,
  required String fileName,
  required int runningVersion,
  required Uint8List key,
  void Function(Uint8List old)? beforeTheDelete,
  void Function(String)? report,
}) {
  final path = '${directory.path}/$fileName';
  if (!File('$path.enc').existsSync()) return false;

  final enc = FileEncryption(baseDir: directory.path, key: key);
  final old = enc.readBinaryFile(path);
  if (old == null || old.isEmpty) return false;
  if (old[0] == runningVersion) return false;

  beforeTheDelete?.call(old);
  enc.deleteFile(path);
  report?.call('mycelium: $fileName.enc carried version ${old[0]}, running is '
      '$runningVersion — old stock removed, the node starts empty '
      'instead of not at all');
  return true;
}
