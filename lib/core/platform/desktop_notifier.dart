import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dbus/dbus.dart';

/// Hands one notification to the desktop's notification service and returns
/// the identifier the service gave it. The seam of [DesktopNotifier]: a test
/// replaces it, the product uses [DesktopNotifier.notifyOverSessionBus].
typedef DesktopNotificationCall = Future<int> Function({
  required String appName,
  required int replacesId,
  required String summary,
  required String body,
});

/// Posts a notification on the Linux desktop (§22.6 "notifications via
/// `notify-send`/D-Bus").
///
/// WHAT IT SHOWS (§22.8 "What a system notification shows"): the sender's
/// display name as title and the beginning of the message as text — the
/// same two values the Android notification gets, from the same place
/// (`CleonaService._postSystemNotification`). A reminder shows the event's
/// title and how long until it starts.
///
/// WHY THE SESSION BUS AND NO PROGRAM: "The text is handed to the platform's
/// notification service and to nothing else: it is not written to a log,
/// and it is not passed as an argument of a process, where every local user
/// could read it" (§22.8). `notify-send` takes title and text as arguments;
/// they stand in `/proc/<pid>/cmdline`, readable by every local user while
/// the program runs. Here they travel in ONE method call over the session
/// bus — a socket of this user's session — to
/// `org.freedesktop.Notifications`. Without a session bus or without a
/// notification service nothing is shown; there is no fallback that puts
/// the text into an argument list.
///
/// [post] never throws and never waits: it is called from the receive path.
/// A failure costs one log line, once per run — and that line names the
/// kind of failure, never the title or the text.
class DesktopNotifier {
  DesktopNotifier({
    DesktopNotificationCall? call,
    this.warn,
    this.appName = 'Cleona',
  }) : _call = call ?? notifyOverSessionBus;

  static const String busName = 'org.freedesktop.Notifications';
  static const String objectPath = '/org/freedesktop/Notifications';

  /// How long one notification may take before it is dropped. A service
  /// that is there answers at once; without one the bus waits for its
  /// activation timeout.
  static const Duration callLimit = Duration(seconds: 10);

  /// How many notification identifiers are remembered for replacing.
  static const int keysAtMost = 64;

  final DesktopNotificationCall _call;

  /// Where the one failure line of a run goes (the daemon's log).
  final void Function(String line)? warn;
  final String appName;
  bool _failureLogged = false;

  /// Key (a conversation, a reminder) -> the identifier of the notification
  /// last shown for it. A second notification under the same key replaces
  /// the first instead of stacking — what Android does with the
  /// conversation as notification id.
  final LinkedHashMap<String, int> _shown = LinkedHashMap<String, int>();

  /// Post a notification. Returns immediately; the outcome is only logged.
  void post({required String summary, required String body, String? key}) {
    try {
      final replaces = key == null ? 0 : (_shown[key] ?? 0);
      unawaited(_call(
        appName: appName,
        replacesId: replaces,
        summary: summary,
        body: body,
      ).then((id) {
        if (key != null && id > 0) _remember(key, id);
      }, onError: (Object e) {
        _logFailureOnce(failureKind(e));
      }));
    } catch (e) {
      _logFailureOnce(failureKind(e));
    }
  }

  void _remember(String key, int id) {
    _shown.remove(key);
    _shown[key] = id;
    while (_shown.length > keysAtMost) {
      _shown.remove(_shown.keys.first);
    }
  }

  void _logFailureOnce(String why) {
    if (_failureLogged) return;
    _failureLogged = true;
    warn?.call('Desktop notifications unavailable: $why — not reported '
        'again in this run');
  }

  /// What went wrong, in words that carry NOTHING of the notification: the
  /// text of an exception is not used — an error reply is written by the
  /// other side of the bus and may quote what it was sent.
  static String failureKind(Object e) {
    if (e is SocketException || e is DBusClosedException) {
      return 'no session bus';
    }
    if (e is DBusServiceUnknownException) return 'no notification service';
    if (e is TimeoutException) return 'the notification service did not answer';
    return 'the notification service refused (${e.runtimeType})';
  }

  /// The body as the service must be given it.
  ///
  /// Desktop Notifications Specification 1.2, capability `body-markup`:
  /// "Supports markup in the body text. If marked up text is sent to a
  /// server that does not give this cap, the markup will show through as
  /// regular text so must be stripped clientside." The markup includes
  /// `<a href="...">` and `<img src="..." alt="..."/>`
  /// (https://specifications.freedesktop.org/notification/latest/markup.html).
  /// A message is text, written by somebody else: where the service reads
  /// markup, the three characters that start it are escaped, so that a
  /// message shows as written and can place neither a link nor an image in
  /// the notification. Where the service reads none, the text goes as it
  /// is.
  static String bodyFor(String text, {required bool markup}) => markup
      ? text
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
      : text;

  /// The product way: ONE `Notify` call over the session bus, on a
  /// connection opened for it and closed after it — nothing stays open and
  /// nothing runs between two notifications.
  ///
  /// `Notify(app_name, replaces_id, app_icon, summary, body, actions, hints,
  /// expire_timeout)` returns the notification's identifier (Desktop
  /// Notifications Specification 1.2, protocol.html): `replaces_id` 0
  /// replaces nothing, `expire_timeout` -1 leaves the duration to the
  /// service.
  ///
  /// [busAddress] is for tests (a private bus); the product takes the
  /// session bus of the environment (`DBUS_SESSION_BUS_ADDRESS`, else the
  /// user's runtime directory — `DBusClient.session`).
  ///
  /// Throws when there is no bus, no service, or no answer within [limit].
  static Future<int> notifyOverSessionBus({
    required String appName,
    required int replacesId,
    required String summary,
    required String body,
    String? busAddress,
    Duration limit = callLimit,
  }) async {
    final client = busAddress == null
        ? DBusClient.session()
        : DBusClient(DBusAddress(busAddress));
    try {
      return await _notify(client, appName, replacesId, summary, body)
          .timeout(limit);
    } finally {
      // Not awaited: a connection that never came about must not hold the
      // caller, and a failing close has nobody to tell.
      unawaited(client.close().catchError((Object _) {}));
    }
  }

  static Future<int> _notify(DBusClient client, String appName,
      int replacesId, String summary, String body) async {
    final path = DBusObjectPath(objectPath);
    final capabilities = await client.callMethod(
      destination: busName,
      path: path,
      interface: busName,
      name: 'GetCapabilities',
      replySignature: DBusSignature('as'),
    );
    final markup =
        capabilities.returnValues.first.asStringArray().contains('body-markup');
    final reply = await client.callMethod(
      destination: busName,
      path: path,
      interface: busName,
      name: 'Notify',
      values: [
        DBusString(appName),
        DBusUint32(replacesId),
        const DBusString(''),
        DBusString(summary),
        DBusString(bodyFor(body, markup: markup)),
        DBusArray.string(const []),
        DBusDict.stringVariant(const {}),
        const DBusInt32(-1),
      ],
      replySignature: DBusSignature('u'),
    );
    return reply.returnValues.first.asUint32();
  }
}
