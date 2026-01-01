/// The missed-call message (v4_2 §17.2 "Missed call", D-45).
///
/// "Whenever a call ends without having been answered — no `RING_ACK`
/// within 10 s, the caller hanging up before an answer, or 60 s of ringing
/// without an `ANSWER` — the caller sends the missed-call message. It is an
/// ordinary message, not a call signal … It carries the `callId` and whether
/// the call was audio or video. The callee shows it with the time its own
/// device received it (§22.5.3)."
///
/// A conversation entry of this kind carries its i18n KEY as text, like a
/// system notice (`system_notices.dart`): the service process has no
/// `AppLocale` (§22.6); the UI translates it.
library;

/// i18n key of the entry for a missed audio call.
const String kMissedCallKey = 'call_missed';

/// i18n key of the entry for a missed video call.
const String kMissedVideoCallKey = 'call_missed_video';

/// The key of the entry for a missed call of the given kind.
String missedCallKey({required bool isVideo}) =>
    isVideo ? kMissedVideoCallKey : kMissedCallKey;

/// Whether [text] is one of the two keys — what the UI translates.
bool isMissedCallKey(String text) =>
    text == kMissedCallKey || text == kMissedVideoCallKey;
