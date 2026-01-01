import 'package:cleona/core/i18n/app_locale.dart';
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
/// A notice carries at most one argument; a translation reads it as `{name}`
/// or — a number (`noticeWithCount`) — as `{count}`.
String systemNoticeText(AppLocale locale, String text) {
  final n = systemNoticeParse(text);
  if (n == null) return text;
  final arg = n.name;
  if (arg == null) return locale.get(n.key);
  // A contact accepted before its introduction arrived still carries the
  // pending mark as its name (S394-11) — translated like every other name.
  final name = shownContactName(arg, locale);
  return locale.tr(n.key, {'name': name, 'count': arg});
}
