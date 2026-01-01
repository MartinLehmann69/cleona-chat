/// Plaintext in transit — the ONE place for files that carry user content
/// unencrypted for the length of one operation.
///
/// ── WHY SUCH FILES EXIST AT ALL ────────────────────────────────────────
///
/// Message content lives in the store and attachments lie sealed under
/// `media/` (v4_2 §4.5.3, §21.4.2). Between those two there are moments in
/// which a foreign program needs a FILE: the recorder writes the voice
/// message it has just taken, `ffmpeg` writes the WAV the transcription
/// reads, `smbclient`/`sftp`/`curl` read the attachment they carry to the
/// share. None of them can be handed a sealed file.
///
/// ── WHAT THIS FILE GUARANTEES ──────────────────────────────────────────
///
///  1. PLACE. Such a file lies in `<root>/transient/`, a directory only the
///     owner can enter (mode 700 where the platform knows modes) — never in
///     the system temp directory, which on Linux every account of the
///     machine can list and, with the usual umask, read.
///  2. END OF THE OPERATION. Whoever created the file calls [discard] when
///     its content has been taken over or the operation was abandoned.
///     [discard] deletes ONLY inside a directory it is told to regard as
///     transient: handing it the path of a file the user picked is harmless.
///  3. START EDGE. A crash between creation and [discard] leaves the file.
///     [sweep] empties the directory when its owner starts — an edge, not a
///     timer; nothing here runs periodically.
///
/// ── TWO OWNERS, TWO DIRECTORIES ────────────────────────────────────────
///
/// The surface owns `<dataDir>/transient/` (recording, pasted file, camera
/// picture, a file handed to the share dialog); each identity's service
/// owns `<profileDir>/transient/` (transcription, archive transfer). They
/// are separate so that the start of one never deletes a file the other is
/// still working on: on the desktop the surface and the daemon are two
/// processes with independent starts, and one daemon carries several
/// identities.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:cleona/core/platform/app_paths.dart';

class TransientFiles {
  TransientFiles._();

  /// Name of the directory below its root.
  static const String directoryName = 'transient';

  /// `<root>/transient`, created on first use and closed to other accounts.
  static Directory directoryIn(String root) =>
      ensure(p.join(root, directoryName));

  /// Makes sure the directory [path] exists and is closed to other
  /// accounts. For a holder that was handed the path of its transient
  /// directory instead of the root.
  static Directory ensure(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      _ownerOnly(dir.path);
    } else if ((Platform.isLinux || Platform.isMacOS) &&
        (dir.statSync().mode & 0x3F) != 0) {
      // Present, but open to group or others (0o077) — whoever made it.
      _ownerOnly(dir.path);
    }
    return dir;
  }

  /// The path of a new file [name] in the transient directory of [root].
  static String pathIn(String root, String name) =>
      p.join(directoryIn(root).path, name);

  static void _ownerOnly(String path) {
    // Windows: the profile lies below the user's own profile directory and
    // inherits its access list. Android/iOS: the app container is private.
    if (!Platform.isLinux && !Platform.isMacOS) return;
    try {
      Process.runSync('chmod', ['700', path]);
    } catch (_) {
      // Without `chmod` the directory keeps the mode of its creation; the
      // parent (`.cleona`, mode 700 once the daemon has run) still closes it.
    }
  }

  /// Whether [path] lies inside [directory] (not the directory itself).
  ///
  /// Links are resolved where the entries exist: on Android the same cache
  /// directory is reachable as `/data/data/<package>/cache` and as
  /// `/data/user/0/<package>/cache`, and the two sides of this comparison
  /// come from different sources.
  static bool isWithin(String directory, String path) {
    return p.isWithin(_resolved(directory), _canonical(path));
  }

  /// [path] with the links of its DIRECTORY resolved. The entry itself is
  /// not followed: a link lying in a transient directory is that link.
  static String _canonical(String path) =>
      p.join(_resolved(p.dirname(path)), p.basename(path));

  static String _resolved(String path) {
    final absolute = p.normalize(p.absolute(path));
    try {
      return Directory(absolute).resolveSymbolicLinksSync();
    } catch (_) {
      return absolute; // does not exist — nothing to resolve
    }
  }

  /// Deletes the file at [path] if — and only if — it lies inside one of
  /// the directories in [within]. Returns whether a file was deleted.
  ///
  /// The condition is what makes this safe to call on EVERY path that went
  /// through a send funnel: a file the user picked from their own folders
  /// lies in none of the transient directories and is left alone.
  static bool discard(String path, {required Iterable<String> within}) {
    if (!within.any((d) => isWithin(d, path))) return false;
    try {
      final f = File(path);
      if (!f.existsSync()) return false;
      f.deleteSync();
      return true;
    } catch (_) {
      // Still open elsewhere (Windows) or already gone: the start edge
      // takes what is left.
      return false;
    }
  }

  /// Deletes everything inside [directory], except the paths in [keep].
  /// The directory itself stays. Returns the number of entries removed.
  static int sweep(Directory directory, {Set<String> keep = const {}}) {
    if (!directory.existsSync()) return 0;
    final kept = keep.map(_canonical).toSet();
    var removed = 0;
    final List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } catch (_) {
      return 0;
    }
    for (final e in entries) {
      if (kept.contains(_canonical(e.path))) continue;
      try {
        // A link is removed as a link, never followed.
        e.deleteSync(recursive: e is Directory);
        removed++;
      } catch (_) {
        // Stays for the next start.
      }
    }
    return removed;
  }

  /// Deletes the FILES directly inside [directory] whose base name matches
  /// one of [names] as a whole. For places that are not ours alone — the
  /// names decide, nothing else in the directory is touched.
  static int sweepNamed(Directory directory, Iterable<RegExp> names) {
    if (!directory.existsSync()) return 0;
    var removed = 0;
    final List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } catch (_) {
      return 0;
    }
    for (final e in entries) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (!names.any((n) => _whole(n, name))) continue;
      try {
        e.deleteSync();
        removed++;
      } catch (_) {
        // Not ours to delete (another account's file under a sticky
        // directory) or gone meanwhile.
      }
    }
    return removed;
  }

  static bool _whole(RegExp pattern, String name) {
    final m = pattern.firstMatch(name);
    return m != null && m.start == 0 && m.end == name.length;
  }

  // ── The surface ───────────────────────────────────────────────────────

  /// The names under which the surface put plaintext into the SYSTEM temp
  /// directory until S401 and never deleted it: the voice recording, a
  /// pasted clipboard item, the camera picture for the profile.
  static final List<RegExp> surfaceNamesInSystemTemp = [
    RegExp(r'voice_\d+\.m4a'),
    RegExp(r'clipboard_\d+(\.[A-Za-z0-9]+)?'),
    RegExp(r'cleona_camera_capture\.jpg'),
  ];

  /// Where the temp directory belongs to this app alone: on Android it is
  /// the app's cache directory, on iOS the `tmp` of the app container. What
  /// lies there and went through a send funnel is a COPY made for the app
  /// (a shared-in file, a clipboard item, what a picker handed over) —
  /// never the user's own file.
  static bool get tempIsAppPrivate => Platform.isAndroid || Platform.isIOS;

  /// The path of a new file [name] of the surface.
  static String surfacePath(String name, {String? dataDir}) =>
      pathIn(dataDir ?? AppPaths.dataDir, name);

  /// The directories in which a file counts as the surface's own plaintext
  /// in transit: its transient directory, and — only where
  /// [tempIsAppPrivate] — the temp directories of the app.
  static List<String> surfaceDirectories({
    String? dataDir,
    bool? appPrivateTemp,
    Iterable<String>? tempDirs,
  }) =>
      [
        p.join(dataDir ?? AppPaths.dataDir, directoryName),
        if (appPrivateTemp ?? tempIsAppPrivate)
          ...(tempDirs ?? _tempDirs()),
      ];

  /// The end of an operation of the surface: deletes [path] if it is the
  /// surface's own plaintext in transit ([surfaceDirectories]). A file the
  /// user picked on a desktop lies in none of them and stays. `null` and a
  /// path that is already gone are fine.
  static bool discardSurface(
    String? path, {
    String? dataDir,
    bool? appPrivateTemp,
    Iterable<String>? tempDirs,
  }) {
    if (path == null || path.isEmpty) return false;
    return discard(path,
        within: surfaceDirectories(
            dataDir: dataDir,
            appPrivateTemp: appPrivateTemp,
            tempDirs: tempDirs));
  }

  /// The start edge of the surface: clears its transient directory and
  /// what earlier operations left at the former place, by name
  /// ([surfaceNamesInSystemTemp]). Called once per process, before any
  /// recording, paste or camera picture can exist.
  static int sweepSurfaceAtStart({String? dataDir, Iterable<String>? tempDirs}) {
    var removed = sweep(directoryIn(dataDir ?? AppPaths.dataDir));
    for (final d in tempDirs ?? _tempDirs()) {
      removed += sweepNamed(Directory(d), surfaceNamesInSystemTemp);
    }
    return removed;
  }

  /// A directory the Android side copies files into for the surface
  /// (`cacheDir/shared_in`): everything in it except [keep] goes. Called at
  /// the edge at which the pending share was handed over — what is not in
  /// [keep] then belongs to no operation any more.
  static int sweepSharedIn({required Set<String> keep, Iterable<String>? tempDirs}) {
    var removed = 0;
    for (final d in tempDirs ?? _tempDirs()) {
      removed += sweep(Directory(p.join(d, 'shared_in')), keep: keep);
    }
    return removed;
  }

  static Set<String> _tempDirs() =>
      {Directory.systemTemp.path, AppPaths.tempDir};

  // ── The service of an identity ────────────────────────────────────────

  /// The names under which the archive transfer put a decrypted attachment
  /// (or the batch file naming identity and conversation) into the SYSTEM
  /// temp directory until S401. A build of that time that died in the
  /// middle of a transfer left them there; this build writes none of them
  /// (`archive_transport.dart` works in the transient directory).
  static final List<RegExp> archiveNamesInSystemTemp = [
    RegExp(r'cleona_(upload|download)_\d+'),
    RegExp(r'cleona_sftp_(upload|download|batch|dbatch)_\d+'),
    RegExp(r'cleona_ftps_(upload|download)_\d+'),
    RegExp(r'cleona_smb_(id|new)_\d+'),
  ];

  /// The name under which the transcription put the decoded voice message
  /// directly into the profile directory until S401.
  static final RegExp transcriptionNameInProfile =
      RegExp(r'tmp_whisper_\d+\.wav');

  /// The start edge of ONE identity's service: clears what a crash left.
  ///
  ///  * everything in `<profileDir>/transient/` — nothing in there outlives
  ///    the operation that made it, and at the start of this identity's
  ///    service none of its operations runs;
  ///  * the WAV of a transcription at its former place in [profileDir];
  ///  * the archive intermediate files at their former place, [systemTemp]
  ///    (default: the system temp directory), by name — including the
  ///    credential file of an FTPS transfer.
  ///
  /// Returns the number of entries removed.
  static int sweepServiceAtStart(
      {required String profileDir, Directory? systemTemp}) {
    final outside = systemTemp ?? Directory.systemTemp;
    return sweep(directoryIn(profileDir)) +
        sweepNamed(Directory(profileDir), [transcriptionNameInProfile]) +
        sweepNamed(outside, archiveNamesInSystemTemp) +
        _sweepCredentialDirs(outside);
  }

  /// `cleona_ftps_<random>/.netrc`: the credentials of the share, written
  /// for one `curl` call (v4_2 §21.6). Only a directory that holds nothing
  /// but that one file is ours.
  static int _sweepCredentialDirs(Directory outside) {
    if (!outside.existsSync()) return 0;
    var removed = 0;
    final List<FileSystemEntity> entries;
    try {
      entries = outside.listSync(followLinks: false);
    } catch (_) {
      return 0;
    }
    final name = RegExp(r'cleona_ftps_[A-Za-z0-9]+');
    for (final e in entries) {
      if (e is! Directory || !_whole(name, p.basename(e.path))) continue;
      try {
        final inside = e.listSync(followLinks: false);
        final onlyNetrc = inside.every(
            (x) => x is File && p.basename(x.path) == '.netrc');
        if (!onlyNetrc) continue;
        e.deleteSync(recursive: true);
        removed++;
      } catch (_) {
        // Not ours to delete, or gone meanwhile.
      }
    }
    return removed;
  }
}
