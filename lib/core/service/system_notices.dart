/// System notices the SERVICE writes into a conversation and the UI
/// translates.
///
/// A system line of the service (`senderNodeIdHex` empty) carries its text
/// as it is, and until now that text was English, built in the service
/// process: `AppLocale` lives in the UI process (§22.6, same reason as
/// `archive_placeholder.dart`). A notice listed here carries instead its
/// i18n KEY as text; the UI renders it through `systemNoticeText`
/// (`lib/ui/components/system_notice_text.dart`) in the user's language
/// (working rule 7, §24.2). A reader without translation (log, CLI) sees the
/// key — stable and unambiguous.
///
/// A notice about ONE person carries that person's display name after the
/// key, separated by [kNoticeArgSeparator] ([noticeWithName]); the
/// translation takes it as `{name}`.
library;

/// Owner decision W-a (S398): an update removed the delivery layer's memory
/// (format change), the relationship to this contact is ended (§15.9
/// "deleted") — "after the update, please connect again".
const String kNoticeReconnectAfterUpdate = 'system_notice_reconnect_after_update';

/// "{name} accepted your contact request." — written when the counterpart
/// accepted this side's request (app path and line join). Until S398 lab
/// run 2 an English text built in the service (note in `S398-LABOR-2.md`).
const String kNoticeContactAccepted = 'system_notice_contact_accepted';

/// B-3 stage 0 (S398, §22.5.1 `failed`): a group leg to this member had no
/// way — it is neither a contact nor a group pair (yet). Named once per
/// member and group, not per message.
const String kNoticeGroupMemberUnreachable =
    'system_notice_group_member_unreachable';

/// B-3 (§16.2.2, E3): the self-signed address of this member did not prove
/// itself — no group pair is formed with it.
const String kNoticeGroupMemberUnconfirmed =
    'system_notice_group_member_unconfirmed';

/// v4_2 §21.5.3, §9.5 (owner decision 11, F5 = C): "{count} messages expired
/// before you could read them." — shown once in a conversation when a party
/// answers a catching up and names how many of its messages expired at the
/// sender before they were acknowledged. Its argument is the number.
const String kNoticeExpiredBeforeRead = 'system_notice_expired_before_read';

/// Every key a system line may carry instead of a text.
const Set<String> kSystemNoticeKeys = {
  kNoticeReconnectAfterUpdate,
  kNoticeContactAccepted,
  kNoticeGroupMemberUnreachable,
  kNoticeGroupMemberUnconfirmed,
  kNoticeExpiredBeforeRead,
};

/// Between the key and its `{name}` argument. A control character (unit
/// separator) no key contains; a display name may contain anything after it.
const String kNoticeArgSeparator = '\u001f';

/// The system line for [key] with the `{name}` argument [name].
String noticeWithName(String key, String name) =>
    '$key$kNoticeArgSeparator$name';

/// The system line for [key] with the `{count}` argument [count]. The one
/// argument a notice carries stands behind the separator either way; the
/// translation of the key says whether it reads it as `{name}` or `{count}`.
String noticeWithCount(String key, int count) =>
    '$key$kNoticeArgSeparator$count';

/// The notice a system line [text] carries — its key and, if any, its
/// `{name}` argument — or `null` for a plain text line.
({String key, String? name})? systemNoticeParse(String text) {
  final i = text.indexOf(kNoticeArgSeparator);
  final key = i < 0 ? text : text.substring(0, i);
  if (!kSystemNoticeKeys.contains(key)) return null;
  return (key: key, name: i < 0 ? null : text.substring(i + 1));
}
