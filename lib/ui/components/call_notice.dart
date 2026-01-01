// lib/ui/components/call_notice.dart
//
// The short hint after a 1:1 call that ended for a reason the user did not
// cause (§17.4 "UI: connection lost"), or that did not come about because
// Plane D carries no media (§17.3 "clear message").
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
    case CallEndReason.unspecified:
      return null;
  }
}

/// i18n key of the hint for a call that did not come about for [reason].
String callUnavailableNoticeKey(CallUnavailableReason reason) {
  switch (reason) {
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
  messenger.showSnackBar(
    SnackBar(content: Text(AppLocale.read(context).get(key))),
  );
}
