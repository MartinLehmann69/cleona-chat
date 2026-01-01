// lib/ui/components/call_notice.dart
//
// The short hint after a 1:1 call that ended for a reason the user did not
// cause (§17.4 "UI: connection lost"), or that did not come about because
// Plane D carries no media (§17.3 "clear message") or because the user
// switched calls off for that contact (§17 principle, RL-7).
//
// A SnackBar on the app's root messenger, reached through the navigator's
// context: the call screen closes itself when the call ends, and a refused
// `startCall` never opens one, so the hint cannot live on that screen.
import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_types.dart';

/// i18n key of the hint for a call that ended with [reason], or `null` when
/// the end needs none — somebody hung up, rejected, or the ringing ran out.
String? callEndNoticeKey(CallEndReason reason) {
  switch (reason) {
    case CallEndReason.connectionLost:
      return 'call_connection_lost';
    case CallEndReason.notReachable:
      return 'call_not_reachable';
    case CallEndReason.unspecified:
      return null;
  }
}

/// i18n key of the hint for a call that did not come about for [reason].
String callUnavailableNoticeKey(CallUnavailableReason reason) {
  switch (reason) {
    case CallUnavailableReason.callsNotAllowed:
      return 'call_unavailable_calls_not_allowed';
    case CallUnavailableReason.noCommonConnectionType:
      return 'call_unavailable_no_common_type';
    case CallUnavailableReason.noMediaPath:
      return 'call_unavailable_no_path';
  }
}

/// Shows the hint for [key] on the root messenger above [context] (the
/// navigator's context, `navigatorKey.currentContext`). A `null` [key] or a
/// missing context shows nothing — an event before the first frame has no
/// screen to show a hint on.
void showCallNotice(BuildContext? context, String? key) {
  if (context == null || key == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final locale = AppLocale.read(context);
  final hint = callNoticeHintKey(key);
  messenger.showSnackBar(
    SnackBar(
      content: hint == null
          ? Text(locale.get(key))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(locale.get(key),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(locale.get(hint)),
              ],
            ),
    ),
  );
}

/// The explaining second line under a notice, or `null` when it needs none.
///
/// "Not reachable" names a platform boundary that the app must name, not
/// paper over (§22.6 "Callability"): the callee may be an iPhone whose app
/// is not open — the caller cannot know — and a message still reaches them
/// (S418 V10, D-123 item 6).
String? callNoticeHintKey(String key) =>
    key == 'call_not_reachable' ? 'call_not_reachable_hint' : null;
