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

/// §18.1.7 (S410): the calendar lines of a group chat. Each is written by
/// the RECEIVING service from the calendar cell (`calendar_protocol_
/// service.dart`); nothing of it travels on the wire, so a 4.2.3 counterpart
/// is not touched. Until S410 they were fixed English/German texts
/// ("hat zugesagt", "declined") in every language. The four event lines
/// carry `{name}` and `{title}` ([noticeWithNameAndTitle]), the four
/// answers `{name}` ([noticeWithName]).
const String kNoticeCalendarCreated = 'system_notice_calendar_created';
const String kNoticeCalendarChanged = 'system_notice_calendar_changed';
const String kNoticeCalendarCancelled = 'system_notice_calendar_cancelled';
const String kNoticeCalendarDeleted = 'system_notice_calendar_deleted';
const String kNoticeCalendarAccepted = 'system_notice_calendar_accepted';
const String kNoticeCalendarDeclined = 'system_notice_calendar_declined';
const String kNoticeCalendarTentative = 'system_notice_calendar_tentative';
const String kNoticeCalendarProposesTime =
    'system_notice_calendar_proposes_time';

/// The keys whose line carries a second argument, `{title}`.
const Set<String> kNoticeKeysWithTitle = {
  kNoticeCalendarCreated,
  kNoticeCalendarChanged,
  kNoticeCalendarCancelled,
  kNoticeCalendarDeleted,
};

/// Every key a system line may carry instead of a text.
const Set<String> kSystemNoticeKeys = {
  kNoticeReconnectAfterUpdate,
  kNoticeContactAccepted,
  kNoticeGroupMemberUnreachable,
  kNoticeGroupMemberUnconfirmed,
  kNoticeExpiredBeforeRead,
  ...kNoticeKeysWithTitle,
  kNoticeCalendarAccepted,
  kNoticeCalendarDeclined,
  kNoticeCalendarTentative,
  kNoticeCalendarProposesTime,
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

/// The system line for [key] with `{name}` [name] and `{title}` [title]
/// (a key of [kNoticeKeysWithTitle]). The title is the event's own text and
/// is shown as it is, in every language.
String noticeWithNameAndTitle(String key, String name, String title) =>
    '$key$kNoticeArgSeparator$name$kNoticeArgSeparator$title';

/// The notice a system line [text] carries — its key, its `{name}` argument
/// and, for a key of [kNoticeKeysWithTitle], its `{title}` — or `null` for a
/// plain text line. A line written before S410 ("Alice created an event:
/// …") is a plain text line and is shown as it was stored.
({String key, String? name, String? title})? systemNoticeParse(String text) {
  final i = text.indexOf(kNoticeArgSeparator);
  final key = i < 0 ? text : text.substring(0, i);
  if (!kSystemNoticeKeys.contains(key)) return null;
  if (i < 0) return (key: key, name: null, title: null);
  final rest = text.substring(i + 1);
  if (!kNoticeKeysWithTitle.contains(key)) {
    return (key: key, name: rest, title: null);
  }
  final j = rest.indexOf(kNoticeArgSeparator);
  return j < 0
      ? (key: key, name: rest, title: null)
      : (key: key, name: rest.substring(0, j), title: rest.substring(j + 1));
}
