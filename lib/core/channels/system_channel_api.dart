// What the user interface of the system channels needs from the service
// (v4_2 §16.7, S407 SK-3). Plain values only, so that the IPC bridge can
// carry them; the transport behind it (deposit, fetch, fingerprint
// question) is wired by SK-4 and is not visible here.
import 'dart:convert';

import 'package:cleona/core/channels/system_channels.dart';

/// Channel numbers of §16.7 (the same numbers as the durable identifier).
class SystemChannel {
  SystemChannel._();
  static const int bugLog = 1;
  static const int featureRequests = 2;

  /// The conversation id the home list shows for [channel].
  static String conversationIdOf(int channel) => channel == bugLog
      ? SystemChannels.bugLogChannelIdHex
      : SystemChannels.featureReqChannelIdHex;

  /// The channel of a conversation id, or null when it is no system channel.
  static int? ofConversation(String conversationId) {
    if (SystemChannels.isBugLogChannel(conversationId)) return bugLog;
    if (SystemChannels.isFeatureReqChannel(conversationId)) {
      return featureRequests;
    }
    return null;
  }
}

/// Why an own report failed (§16.7: "failed … with the reason").
enum SystemFailureReason {
  /// No holder was known in 14 days.
  noHolderKnown,

  /// Holders were known, but fewer than two acknowledged in 14 days.
  notAcknowledged,

  /// A holder refused the object; [SystemReportStatus.detail] names why.
  rejected,
}

/// The four states of §16.7 and no other.
enum SystemReportState { saved, deposited, published, failed }

/// Delivery state of an own report. "Published" is not a field the service
/// can set: it follows from two acknowledgements, so it can never be shown
/// before them (§16.7: "Published is never shown before two
/// acknowledgements").
class SystemReportStatus {
  /// Holders that acknowledged the deposit (`0x91`).
  final int acknowledgements;

  /// Set when the report failed; wins over the acknowledgements.
  final SystemFailureReason? failure;

  /// Holder's reason when [failure] is [SystemFailureReason.rejected].
  final String? detail;

  const SystemReportStatus({
    this.acknowledgements = 0,
    this.failure,
    this.detail,
  });

  static const int kPublishedAt = 2;

  SystemReportState get state {
    if (failure != null) return SystemReportState.failed;
    if (acknowledgements >= kPublishedAt) return SystemReportState.published;
    if (acknowledgements > 0) return SystemReportState.deposited;
    return SystemReportState.saved;
  }
}

/// One report (crash, log, contact issue or feature request) as the user
/// interface shows it.
class SystemReportView {
  /// Hex of the 16-byte hash part of the durable identifier.
  final String idHex;
  final int channel;

  /// The report's text (the JSON of [CrashReport], [LogReport],
  /// [ContactIssueReport] or a feature request); empty while not fetched.
  final String text;
  final DateTime created;

  /// Written by this identity's report pseudonym.
  final bool own;

  /// Only for [own] reports.
  final SystemReportStatus? status;

  /// Not yet seen by the user of this device (§16.7: "marks as new").
  final bool isNew;

  /// False while only the identifier is known (a phone before opening).
  final bool fetched;

  const SystemReportView({
    required this.idHex,
    required this.channel,
    required this.text,
    required this.created,
    this.own = false,
    this.status,
    this.isNew = false,
    this.fetched = true,
  });
}

/// A Bug Log group: the oldest valid report heads it, every later report
/// with the same crash fingerprint is a variant (§16.7 Dedup and +1).
class BugLogGroupView {
  final SystemReportView head;
  final List<SystemReportView> variants;

  /// Distinct pseudonyms with a +1 entry — a mood indicator, never proof.
  final int othersSawThis;

  /// This identity has sent a +1 for the group.
  final bool ownPlusOne;

  const BugLogGroupView({
    required this.head,
    this.variants = const [],
    this.othersSawThis = 0,
    this.ownPlusOne = false,
  });
}

/// A feature request with its automatically attached poll.
class FeatureRequestView {
  final SystemReportView request;
  final int yes;
  final int no;
  final int dontCare;

  /// [SystemVote] option of this identity, null when it has not voted.
  final int? ownVote;

  const FeatureRequestView({
    required this.request,
    this.yes = 0,
    this.no = 0,
    this.dontCare = 0,
    this.ownVote,
  });

  int get net => yes - no;
}

/// What the user wants to publish, before the preview.
class SystemDraft {
  final int channel;
  final String text;

  /// Crash fingerprint (64 hex), only for crash reports.
  final String? fingerprintHex;

  const SystemDraft(this.channel, this.text, {this.fingerprintHex});

  factory SystemDraft.crash(CrashReport r) => SystemDraft(
    SystemChannel.bugLog,
    r.toPostText(),
    fingerprintHex: r.fingerprint,
  );

  factory SystemDraft.log(LogReport r) =>
      SystemDraft(SystemChannel.bugLog, r.toPostText());

  factory SystemDraft.contactIssue(ContactIssueReport r) =>
      SystemDraft(SystemChannel.bugLog, r.toPostText());

  factory SystemDraft.featureRequest(String title, String body) => SystemDraft(
    SystemChannel.featureRequests,
    jsonEncode({
      'type': 'feature_request',
      'title': title.trim(),
      'body': body.trim(),
    }),
  );
}

/// Why the own device will not deposit a draft (the per-pseudonym limits of
/// §16.7, checked before the preview).
enum SystemRefusal { perHour, perDay, featurePerDay, share, tooLarge }

/// The preview before a deposit (§16.7 "Before a deposit the device asks").
class SystemDepositPreview {
  /// Names this prepared deposit; [SystemChannelApi.send] sends exactly
  /// what this preview showed.
  final String token;
  final int channel;

  /// The exact text that will be signed and published.
  final String publication;

  /// Beta builds only: the UserID the report names (D-57); null on live.
  final String? statedUserIdHex;

  /// The chosen holder is a device of a contact (no non-contact known).
  final bool holderIsContact;

  /// The head of the group the chosen holder (or the own read cache) knows
  /// for the crash fingerprint; null when unknown or no crash report.
  final SystemReportView? existing;

  /// +1 count of [existing]'s group.
  final int existingOthers;

  /// Set when the own limits forbid this deposit; nothing can be sent.
  final SystemRefusal? refusal;

  const SystemDepositPreview({
    required this.token,
    required this.channel,
    required this.publication,
    this.statedUserIdHex,
    this.holderIsContact = false,
    this.existing,
    this.existingOthers = 0,
    this.refusal,
  });
}

/// What the user chose in the preview.
enum SystemSendChoice {
  /// A new report (no known group).
  report,

  /// The own report, attached to the known group as a variant.
  variant,

  /// Only a +1 entry for the known group.
  plusOne,
}

/// Outcome of a send, vote or retraction on the own device.
class SystemSendResult {
  /// Identifier (hash hex) of the object written, when one was.
  final String? idHex;

  /// Why nothing was written.
  final SystemRefusal? refusal;

  const SystemSendResult.written(this.idHex) : refusal = null;
  const SystemSendResult.refused(this.refusal) : idHex = null;

  bool get ok => refusal == null;
}

/// The service side of the system channels as the user interface uses it.
/// SK-4 implements it in `CleonaService` (over `SystemObjectStore` and the
/// mycelium `DurableTransport`) and carries it over IPC.
abstract class SystemChannelApi {
  /// Fires whenever a list, a state or a tally may have changed.
  Stream<void> get changes;

  /// Bug Log groups, newest group first.
  Future<List<BugLogGroupView>> bugLog();

  /// Feature requests with their tallies (the UI sorts by net votes).
  Future<List<FeatureRequestView>> featureRequests();

  /// Edge of §16.0: the user opened [channel]; a phone fetches what it
  /// lacks. Returns at once; the result arrives through [changes].
  Future<void> channelOpened(int channel);

  /// The user has seen these reports (removes "new", protects them from
  /// eviction, §16.7).
  Future<void> markSeen(int channel, List<String> idHexes);

  /// Builds the object for [draft], checks the own limits and, for a crash
  /// report, asks the chosen holder about the fingerprint (`0x97`).
  Future<SystemDepositPreview> prepare(SystemDraft draft);

  /// Writes what [token] previewed and deposits it (state "saved" at once,
  /// the rest through [changes]).
  Future<SystemSendResult> send(String token, SystemSendChoice choice);

  /// The user closed the preview without sending.
  Future<void> discard(String token);

  /// Votes on a feature request; a newer vote replaces the older.
  Future<SystemSendResult> vote(String requestIdHex, int option);

  /// Retracts an own report (tombstone, §16.7 Retraction).
  Future<SystemSendResult> retract(String idHex);

  /// Whether a holder is known now — a contact-issue report offers the
  /// deposit only then (§16.7 "the deposit is only an option once holders
  /// are known"); the export is always offered.
  Future<bool> holdersKnown();
}
