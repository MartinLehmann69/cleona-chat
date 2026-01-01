import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/platform/first_start_wipe.dart';

enum ProfileMoveOutcome {
  /// Nothing to do: no beta profile under the old name.
  nothing,

  /// The profile moved, and the old name now links to it.
  moved,

  /// An abort between the rename and the link was repaired.
  linkRestored,

  /// A live build made `.cleona` its own directory.
  claimedForLive,

  /// The move has not happened; this process uses `.cleona`, the next start
  /// tries again.
  blocked,
}

/// Moves a beta profile from `.cleona` to `.cleona-beta` once (v4_2 §21.4,
/// D-89). The move is complete or has not happened, and no data is deleted.
///
/// A link `.cleona` → `.cleona-beta` stays behind. It is what keeps a user's
/// data safe from every version that only knows the old name:
///
/// * A rollback (§26.5.4) starts the previous version, and so does an old
///   AppImage file, an old tar.gz, or a package installed by hand. Without a
///   profile it would create an empty one, and the setup would overwrite the
///   master seed in the keyring, whose entry belongs to the user and not to a
///   directory. Through the link it finds its profile.
/// * Old and new share the file `cleona.lock` behind both names, so they
///   exclude each other as before.
/// * Absolute paths in the databases ([AppPaths.rebaseProfilePath]) and a
///   window of the old version that is still open keep working.
///
/// A live build removes the link, and only the link, to take `.cleona`.
///
/// There is no channel field in an older profile. Decrypting the list of
/// identities to check the identity domain needs the keyring, which may be
/// locked, and a wrong "no" would leave a beta user in front of an empty
/// profile. So a profile is beta unless its marker says live: all 51 published
/// releases are beta. See `mycelium/berichte/S411-PARALLEL.md`.
abstract final class ProfileMove {
  /// In the moved profile: this directory once lay under the old name. Tells a
  /// missing link (an abort after the rename) from a profile that never lay
  /// there, which gets no link.
  static const String movedNote = '.moved-from-cleona';

  static const String _lockName = '.cleona-move.lock';

  /// What happened, for the log. The move runs before the logger may touch the
  /// profile directory.
  static String? lastReport;

  /// Called first thing by window and daemon when they use the default
  /// directory. With [home] and [channel] it is a pure probe: nothing is
  /// remembered in [AppPaths].
  static ProfileMoveOutcome ensure(
      {String? home, NetworkChannel? channel, int attempts = 4}) {
    if (home == null && !AppPaths.isDesktop) return ProfileMoveOutcome.nothing;
    final h = home ?? AppPaths.home;
    final ch = channel ?? activeNetworkChannel;
    final sep = Platform.pathSeparator;
    final old = '$h$sep${AppPaths.liveDataDirName}';
    final beta = '$h$sep${AppPaths.betaDataDirName}';

    RandomAccessFile? lock;
    ProfileMoveOutcome outcome;
    try {
      lock = File('$h$sep$_lockName').openSync(mode: FileMode.append);
      // Window and daemon start within moments of each other.
      lock.lockSync(FileLock.blockingExclusive);
      outcome = _run(old, beta, ch, attempts);
    } catch (e) {
      lastReport = 'profile move not possible: $e';
      outcome = ProfileMoveOutcome.blocked;
    } finally {
      try { lock?.unlockSync(); } catch (_) {}
      try { lock?.closeSync(); } catch (_) {}
    }
    if (outcome == ProfileMoveOutcome.blocked && home == null) {
      AppPaths.setDataDir(old);
    }
    return outcome;
  }

  static FileSystemEntityType _kind(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false);

  static ProfileMoveOutcome _run(
      String old, String beta, NetworkChannel channel, int attempts) {
    final live = channel == NetworkChannel.live;
    switch (_kind(old)) {
      case FileSystemEntityType.link:
        return live ? _claim(old) : ProfileMoveOutcome.nothing;
      case FileSystemEntityType.directory:
        break;
      case FileSystemEntityType.notFound:
        if (!live && File('$beta${Platform.pathSeparator}$movedNote').existsSync()) {
          return _link(old, beta)
              ? ProfileMoveOutcome.linkRestored
              : ProfileMoveOutcome.nothing;
        }
        return ProfileMoveOutcome.nothing;
      default:
        return ProfileMoveOutcome.nothing;
    }

    if (_markerSaysLive(old) || !_holdsProfile(old)) {
      return ProfileMoveOutcome.nothing;
    }

    if (_holdsProfile(beta)) {
      // Two profiles are never merged. Beta uses its own and leaves this one.
      // Live cannot use a directory holding beta's data, so it sets it aside.
      if (!live) {
        lastReport = 'profile under both names — never merged, ${old.split(Platform.pathSeparator).last} stays';
        return ProfileMoveOutcome.nothing;
      }
      Directory(old).renameSync('$old.beta-set-aside-${DateTime.now().millisecondsSinceEpoch}');
      return ProfileMoveOutcome.claimedForLive;
    }

    final moved = _move(old, beta, attempts);
    if (moved != ProfileMoveOutcome.moved) return moved;
    return live ? _claim(old) : moved;
  }

  static bool _holdsProfile(String dir) =>
      FirstStartWipe.isCurrentProfile(dir) ||
      FirstStartWipe.hasLegacyProfileEvidence(dir);

  static bool _markerSaysLive(String dir) {
    try {
      final m = jsonDecode(File(
                  '$dir${Platform.pathSeparator}${FirstStartWipe.markerFilename}')
              .readAsStringSync()) as Map<String, dynamic>;
      return m['channel'] == NetworkChannel.live.name;
    } catch (_) {
      return false;
    }
  }

  /// Is a daemon working in [dir]? The same lock it holds for its lifetime; a
  /// window needs no asking, its paths stay valid through the link.
  static bool _daemonHolds(String dir) {
    final f = File('$dir${Platform.pathSeparator}cleona.lock');
    if (!f.existsSync()) return false;
    RandomAccessFile? raf;
    try {
      raf = f.openSync(mode: FileMode.append);
      raf.lockSync(FileLock.exclusive);
      raf.unlockSync();
      return false;
    } catch (_) {
      return true;
    } finally {
      try { raf?.closeSync(); } catch (_) {}
    }
  }

  static ProfileMoveOutcome _move(String old, String beta, int attempts) {
    final sep = Platform.pathSeparator;
    final note = File('$old$sep$movedNote');
    Object? why;
    // Waits out what ends by itself: the old daemon on its way down after an
    // update, and on Windows its helper script, which still has a file open in
    // `.cleona\update\`.
    for (var i = 0; i < attempts; i++) {
      if (i > 0) sleep(const Duration(seconds: 1));
      if (_daemonHolds(old)) {
        why = 'a daemon holds cleona.lock';
        continue;
      }
      try {
        _clearTarget(beta);
        note.writeAsStringSync('');
        Directory(old).renameSync(beta);
        if (_link(old, beta)) {
          lastReport = 'profile moved to ${beta.split(sep).last}, link left behind';
          return ProfileMoveOutcome.moved;
        }
        // Without the link an older version would meet no profile.
        Directory(beta).renameSync(old);
        why = 'no link could be created';
      } catch (e) {
        why = e;
      }
      if (_kind(old) == FileSystemEntityType.directory) {
        try { note.deleteSync(); } catch (_) {}
      }
    }
    lastReport = 'profile move has not happened: $why';
    return ProfileMoveOutcome.blocked;
  }

  /// A target without a profile: empty it goes, with content it is set aside.
  static void _clearTarget(String beta) {
    if (_kind(beta) != FileSystemEntityType.directory) return;
    final dir = Directory(beta);
    if (dir.listSync().isEmpty) {
      dir.deleteSync();
    } else {
      dir.renameSync('$beta.set-aside-${DateTime.now().millisecondsSinceEpoch}');
    }
  }

  static bool _link(String old, String beta) {
    try {
      if (Platform.isWindows) {
        // A junction needs no rights; a symbolic link needs Developer Mode.
        final r = Process.runSync('cmd.exe', ['/c', 'mklink', '/J', old, beta]);
        return r.exitCode == 0 && _kind(old) == FileSystemEntityType.link;
      }
      Link(old).createSync(beta);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Only the link goes; the directory it names is never touched.
  static ProfileMoveOutcome _claim(String old) {
    Link(old).deleteSync();
    Directory(old).createSync();
    return ProfileMoveOutcome.claimedForLive;
  }
}
