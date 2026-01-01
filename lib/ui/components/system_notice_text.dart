import 'package:cleona/core/calls/missed_call.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/system_notices.dart';
import 'package:cleona/ui/components/contact_name.dart';

/// The text of a system line (`senderNodeIdHex` empty) as the user reads it.
///
/// A notice from [kSystemNoticeKeys] carries its i18n key instead of a text
/// (`system_notices.dart`: the service process has no `AppLocale`), with a
/// `{name}` argument if it has one ([systemNoticeParse]); it is translated
/// here. Every other system line is shown as it is. The ONE place for the
/// chat bubble and both conversation-list previews.
///
/// A notice carries one argument; a translation reads it as `{name}` or — a
/// number (`noticeWithCount`) — as `{count}`. A calendar line carries the
/// event title as a second one, `{title}` (`noticeWithNameAndTitle`).
String systemNoticeText(AppLocale locale, String text) {
  final n = systemNoticeParse(text);
  if (n == null) return text;
  final arg = n.name;
  if (arg == null) return locale.get(n.key);
  // A contact accepted before its introduction arrived still carries the
  // pending mark as its name (S394-11) — translated like every other name.
  final name = shownContactName(arg, locale);
  return locale.tr(n.key, {'name': name, 'count': arg, 'title': n.title ?? ''});
}

/// The text of a conversation entry [msg] from a person (`senderNodeIdHex`
/// set) as the user reads it. A missed call (§17.2, `missed_call.dart`)
/// carries its i18n key and is translated here; every other entry is shown
/// as it is. The ONE place for the chat bubble and both previews.
String messageShownText(AppLocale locale, UiMessage msg) =>
    msg.type == UiMessageType.callMissed && isMissedCallKey(msg.text)
        ? locale.get(msg.text)
        : msg.text;
