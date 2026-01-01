import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/platform/desktop_notifier.dart';
import 'package:crypto/crypto.dart';

/// Starts the toast helper. The seam of [WindowsToastNotifier]: a test
/// replaces it, the product uses `Process.start` (a real argument list, no
/// shell).
typedef ToastHelperStart = Future<Process> Function(
    String executable, List<String> arguments);

/// Posts a system notification on the Windows desktop (§22.6 "toast
/// notifications") through the bundled helper `cleona-notify.exe`
/// (`windows/cleona_notify/`), one process per notification.
///
/// WHAT IT SHOWS (§22.8 "What a system notification shows"): the same
/// title and text as on every platform — from
/// `CleonaService._postSystemNotification`, unchanged.
///
/// WHY STDIN: "it is not passed as an argument of a process, where every
/// local user could read it" (§22.8; D-49 "no secret in a process
/// argument"). The argument list names the app only ([arguments]: app id,
/// display name, icon path — public product data). Title, text and the
/// replacement tag travel over the child's standard input, a pipe only the
/// child reads.
///
/// THE TAG: a later toast with the same tag and group replaces the earlier
/// one ("You can replace a notification by sending a new notification with
/// the same Tag and Group",
/// https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-progress-bar).
/// The key is a conversation id — a contact id — or a reminder key longer
/// than the 64 characters Windows allows
/// (https://learn.microsoft.com/en-us/uwp/api/windows.ui.notifications.toastnotification.tag),
/// so the tag is derived here: [tagFor].
///
/// [post] never throws and never waits: it is called from the receive path.
/// A failure costs one log line per run, naming the kind of failure (the
/// helper's exit code), never the title, the text or the key.
class WindowsToastNotifier implements SystemNotifier {
  WindowsToastNotifier({
    required this.appId,
    required this.displayName,
    required this.iconPath,
    required this.helperPath,
    ToastHelperStart? start,
    this.warn,
    this.limit = callLimit,
  }) : _start = start ?? Process.start;

  /// File name of the helper in the bundle root. The Windows build fails
  /// when it is missing (`windows/verify_bundle_dlls.cmake`,
  /// `-DEXPECTED_PROGRAMS`).
  static const String helperName = 'cleona-notify.exe';

  /// App ids (AppUserModelID) of the two channels: "no more than 128
  /// characters and cannot contain spaces. Each section should be
  /// pascal-cased", without version information
  /// (https://learn.microsoft.com/en-us/windows/win32/shell/appids). The
  /// setup (`windows/installer/cleona-setup.iss`, `ToastAppId`) carries the
  /// same two texts.
  static const String liveAppId = 'Cleona.Chat';
  static const String betaAppId = 'Cleona.Chat.Beta';

  /// The ONE place that decides the app id of a channel.
  static String appIdFor(NetworkChannel channel) =>
      channel == NetworkChannel.beta ? betaAppId : liveAppId;

  /// Path of the helper for a bundle root: next to `cleona.exe`, where the
  /// MSVC runtime DLLs it needs are bundled as well.
  static String helperPathFor(String bundleDir) => '$bundleDir\\$helperName';

  /// The icon Windows shows with the toast — the PNG of the channel in the
  /// Flutter assets of the bundle (`pubspec.yaml`); the setup registers the
  /// same file.
  static String iconPathFor(String bundleDir, NetworkChannel channel) =>
      '$bundleDir\\data\\flutter_assets\\assets\\'
      '${channel == NetworkChannel.beta ? 'app_icon_beta.png' : 'app_icon.png'}';

  /// How long the helper may run before it is killed.
  static const Duration callLimit = Duration(seconds: 10);

  final String appId;
  final String displayName;
  final String iconPath;
  final String helperPath;
  final ToastHelperStart _start;

  /// Where the one failure line of a run goes (the daemon's log).
  final void Function(String line)? warn;
  final Duration limit;
  bool _failureLogged = false;

  /// The ONLY argument list the helper is started with: nothing of a
  /// notification.
  List<String> get arguments =>
      ['--app-id', appId, '--name', displayName, '--icon', iconPath];

  static final Random _random = Random.secure();

  /// The toast tag for a key: 32 hex characters of SHA-256 over the key —
  /// at most 64 characters, never empty, the same for the same key, and no
  /// contact id in the clear. Without a key a fresh random tag, so that the
  /// toast replaces nothing (as `replaces_id` 0 under Linux).
  static String tagFor(String? key) {
    if (key == null) {
      final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }
    return sha256.convert(utf8.encode(key)).toString().substring(0, 32);
  }

  /// [text] with every character XML 1.0 does not allow removed: the
  /// `Char` production admits `#x9 | #xA | #xD | [#x20-#xD7FF] |
  /// [#xE000-#xFFFD] | [#x10000-#x10FFFF]`
  /// (https://www.w3.org/TR/xml/#charsets). A text node with any other
  /// character would make Windows refuse the toast. A lone surrogate is
  /// dropped by the same rule.
  static String xmlSafe(String text) {
    final out = StringBuffer();
    for (final r in text.runes) {
      if (r == 0x9 ||
          r == 0xA ||
          r == 0xD ||
          (r >= 0x20 && r <= 0xD7FF) ||
          (r >= 0xE000 && r <= 0xFFFD) ||
          (r >= 0x10000 && r <= 0x10FFFF)) {
        out.writeCharCode(r);
      }
    }
    return out.toString();
  }

  /// The helper's standard input: tag, title, body — each a 4-byte
  /// little-endian length and that many UTF-8 bytes (the reader is
  /// `NextField` in `windows/cleona_notify/cleona_notify.cpp`).
  static Uint8List frame(String tag, String title, String body) {
    final parts = [
      utf8.encode(xmlSafe(tag)),
      utf8.encode(xmlSafe(title)),
      utf8.encode(xmlSafe(body)),
    ];
    final total = parts.fold<int>(0, (n, p) => n + 4 + p.length);
    final out = Uint8List(total);
    final view = ByteData.sublistView(out);
    var at = 0;
    for (final p in parts) {
      view.setUint32(at, p.length, Endian.little);
      at += 4;
      out.setRange(at, at + p.length, p);
      at += p.length;
      p.fillRange(0, p.length, 0);
    }
    return out;
  }

  @override
  void post({required String summary, required String body, String? key}) {
    try {
      unawaited(_run(frame(tagFor(key), summary, body)));
    } catch (e) {
      _logFailureOnce('the helper could not be started (${e.runtimeType})');
    }
  }

  /// Starts the helper, hands it [input] and waits for its exit — in the
  /// background of [post]. Never throws.
  Future<void> _run(Uint8List input) async {
    final Process process;
    try {
      process = await _start(helperPath, arguments);
    } catch (e) {
      input.fillRange(0, input.length, 0);
      _logFailureOnce('the helper could not be started (${e.runtimeType})');
      return;
    }
    try {
      // stdout carries at most one diagnostic line (step and HRESULT, never
      // text, S420 35.W02); bounded, the rest is drained unread.
      final out = <int>[];
      final outDone = process.stdout
          .forEach((b) {
            if (out.length < kDetailLimit) out.addAll(b.take(kDetailLimit - out.length));
          })
          .catchError((Object _) {});
      unawaited(process.stderr.drain<void>().catchError((Object _) {}));
      try {
        process.stdin.add(input);
        await process.stdin.close();
      } catch (_) {
        // A helper that ended before reading (usage error) closes its end;
        // its exit code below says why.
      } finally {
        input.fillRange(0, input.length, 0);
      }
      final code = await process.exitCode.timeout(limit, onTimeout: () {
        process.kill();
        return -1;
      });
      if (code != 0) {
        await outDone.timeout(const Duration(seconds: 1), onTimeout: () {});
        final detail = detailOf(out);
        _logFailureOnce(detail == null
            ? failureKind(code)
            : '${failureKind(code)} (${detail.step}, HRESULT ${detail.hresult})');
      }
    } catch (e) {
      _logFailureOnce('the helper failed (${e.runtimeType})');
    }
  }

  /// What an exit code of the helper means, in words that carry nothing of
  /// the notification (codes: `windows/cleona_notify/cleona_notify.cpp`).
  static String failureKind(int code) => switch (code) {
        -1 => 'the helper did not finish in time',
        2 => 'the helper refused its arguments',
        3 => 'the helper refused its input',
        // Registry key (step=registration) or start-menu shortcut
        // (step=shortcut); the step comes with the helper's line.
        4 => 'the app id could not be registered',
        5 => 'Windows refused the toast',
        6 => 'toasts are switched off for this app or user',
        _ => 'the helper ended with exit $code',
      };

  /// Bytes of the helper's stdout that are looked at.
  static const int kDetailLimit = 128;

  /// The one diagnostic line of the helper (`cleona_notify.cpp` `Report`):
  /// `cleona-notify: step=<word> hresult=0x<8 hex>`. Anything else — a
  /// different form, more than one line, any other character — yields null,
  /// so no text the helper did not build can reach the log.
  static ({String step, String hresult})? detailOf(List<int> out) {
    final String line;
    try {
      line = ascii.decode(out);
    } on FormatException {
      return null;
    }
    final m = RegExp(r'^cleona-notify: step=([a-z]{1,16}) hresult=(0x[0-9A-F]{8})\r?\n?$')
        .firstMatch(line);
    return m == null ? null : (step: m.group(1)!, hresult: m.group(2)!);
  }

  void _logFailureOnce(String why) {
    if (_failureLogged) return;
    _failureLogged = true;
    warn?.call('System notifications unavailable: $why — not reported '
        'again in this run');
  }
}
