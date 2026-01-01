import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/update/update_manifest.dart';

/// The per-user copy of a package installation (v4_2 §22.6, §26.6.7, D-85).
///
/// `.deb`, `.rpm` and AppImage bundles are read-only for the user. An
/// in-network update of such an installation goes into
/// `~/.local/share/cleona/app`, and the starter
/// (`scripts/build-linux-packages.sh`, `write_starter`) starts the higher
/// version of the two. A restart from Dart has to reach the same decision,
/// so the rule stands here a second time; `smoke_update_user_copy` runs both
/// against the same bundles.
class UserCopy {
  /// Written last when the copy is complete, removed first when it is
  /// replaced. Without it the copy counts as absent: a copy cut off half way
  /// must never be started, and its version file says nothing about that.
  static const String completeNote = '.user-copy-complete';

  /// The network channel of a bundle, one word (`beta`, `live`), written by
  /// `scripts/release-build.sh` beside the version. One path holds the copy
  /// (§22.6), and a copy of the other channel is ignored, never deleted.
  static const String channelFile = 'data/channel';

  /// Beta and live keep separate copies (§22.6).
  static String dirFor(NetworkChannel channel) =>
      '${AppPaths.home}/.local/share/'
      '${channel == NetworkChannel.beta ? 'cleona-beta' : 'cleona'}/app';

  static String get dir => dirFor(activeNetworkChannel);

  /// Whether files can be created in [path]. Measured by creating one: the
  /// mode bits say nothing about a read-only mount (AppImage).
  static bool isWritable(String path) {
    final probe = File('$path/.cleona-write-probe-$pid');
    try {
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Where an update of the bundle [running] goes: the bundle itself when it
  /// and its parent are writable (tar.gz in the home directory; the backup
  /// lies beside the bundle), otherwise the copy.
  static String installTarget(String running, {String? copy}) {
    if (isWritable(running) && isWritable(File(running).parent.path)) {
      return running;
    }
    return copy ?? dir;
  }

  /// The version in `data/flutter_assets/version.json` of [bundle].
  static String? versionOf(String bundle) {
    try {
      final json = jsonDecode(
              File('$bundle/data/flutter_assets/version.json').readAsStringSync())
          as Map<String, dynamic>;
      return json['version'] as String?;
    } catch (_) {
      return null;
    }
  }

  static String? channelOf(String bundle) {
    try {
      return File('$bundle/$channelFile').readAsStringSync().trim();
    } catch (_) {
      return null;
    }
  }

  /// Complete, of [channel], and its window may be executed here (`test -x`
  /// also fails on a `noexec` mount).
  static bool isUsable(String copy, {NetworkChannel? channel}) =>
      File('$copy/$completeNote').existsSync() &&
      channelOf(copy) == (channel ?? activeNetworkChannel).name &&
      canExecute('$copy/cleona');

  static bool canExecute(String path) {
    try {
      return Process.runSync('test', ['-x', path]).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static void dropCompleteNote(String bundle) {
    try {
      File('$bundle/$completeNote').deleteSync();
    } catch (_) {}
  }

  /// The bundle a restart of a process running from [running] belongs in: the
  /// copy when it is usable and strictly newer, otherwise [running]. The same
  /// rule as the starter; a tie stays with the package. A [running] without a
  /// readable version is a mount that is gone (AppImage): a usable copy wins.
  /// The channel is this program's own, compiled in, for the same reason.
  static String preferredBundle(String running,
      {String? copy, NetworkChannel? channel}) {
    final c = copy ?? dir;
    if (c == running || !isUsable(c, channel: channel)) return running;
    final copyVersion = versionOf(c);
    if (copyVersion == null) return running;
    final runningVersion = versionOf(running);
    if (runningVersion == null) return c;
    return UpdateChecker().isNewer(copyVersion, runningVersion) ? c : running;
  }

  /// [current] with the library directory of [from] replaced by that of [to].
  /// The window's RUNPATH (`$ORIGIN/lib`, measured with readelf) comes after
  /// `LD_LIBRARY_PATH`: left unchanged, the new program would load the old
  /// libraries.
  static String libraryPath(String? current, String from, String to) => [
        '$to/lib',
        ...(current ?? '')
            .split(':')
            .where((e) => e.isNotEmpty && e != '$from/lib' && e != '$to/lib'),
      ].join(':');

  /// The environment a restart into [to] needs beyond the inherited one.
  static Map<String, String> restartEnvironment(String from, String to,
          {String? current}) =>
      from == to
          ? const {}
          : {
              'LD_LIBRARY_PATH': libraryPath(
                  current ?? Platform.environment['LD_LIBRARY_PATH'], from, to),
            };

  /// How the window restarts after its process ended: [command] with the
  /// program of the preferred bundle.
  ///
  /// An AppImage's bundle is a mount that ends with the window's process, so
  /// by the time the restart runs, a path inside it is gone. When the window
  /// came from there and no copy takes over, the restart goes through the
  /// AppImage file itself ([appImage], the runtime's `APPIMAGE` variable),
  /// whose starter decides anew. A window running from the copy carries the
  /// variable too, but its bundle stays.
  static ({List<String> command, Map<String, String> environment}) windowRestart(
    List<String> command,
    String running, {
    String? copy,
    NetworkChannel? channel,
    String? appImage,
    String? libraryPathNow,
  }) {
    final c = copy ?? dir;
    final to = preferredBundle(running, copy: c, channel: channel);
    if (to != running) {
      return (
        command: ['$to/cleona', ...command.skip(1)],
        environment: restartEnvironment(running, to, current: libraryPathNow),
      );
    }
    if (appImage != null && appImage.isNotEmpty && running != c) {
      final rest = (libraryPathNow ?? Platform.environment['LD_LIBRARY_PATH'] ?? '')
          .split(':')
          .where((e) => e.isNotEmpty && e != '$running/lib')
          .join(':');
      return (
        command: [appImage, ...command.skip(1)],
        environment: {'LD_LIBRARY_PATH': rest},
      );
    }
    return (command: command, environment: const {});
  }
}
